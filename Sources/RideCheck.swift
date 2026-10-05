import Foundation
import Metal
import simd

// `Blocksmith --ridecheck [--scenes a,b,...] [--scale F] [--seed N] [--out DIR]`: bots ride the capital vehicles
// through the real Game.tick (Agent API: keys and mouse in, nothing teleported after the start fixture) and every tick
// is checked. Scenes (--scale shortens or stretches their minutes):
//   crawler     stand, then walk laps (sprinting, jumping) on the command deck of an Ironback Crawler driving S-turns
//               at full speed over plains, 4 minutes
//   rough       the same over the roughest ground near spawn
//   frigate     the same on the flight deck of a Capital frigate cruising and turning, 4 minutes
//   warfrigate  the same on the hangar deck of a Stormwarden frigate, 90 s
//   board       on a moving crawler: up the side ladder, over the roof walkway and through the hatch into the command
//               deck, back out and down the ladder to the ground, round to the rear ramp, up it into the troop bay,
//               and down it to the ground again
//   frigateboard a creative bot flies in through a cruising, turning Capital frigate's starboard hangar opening, lands,
//               climbs to the crew deck, walks its corridor forward and back, slides down again and flies out to port
//   crew        a crewed crawler driving S-turns: every soldier holds its post; then half its wheels are shot away:
//               it grinds to a stop, the crew stay aboard and fight two enemy soldiers
//   troops      a crewed crawler meets enemy soldiers: it stops, lowers its ramp and its bay troops walk out down it
//   frigatecrew a crewed Capital frigate cruising: crew hold their posts; engines destroyed: it crash-lands, crew aboard
//   frigatecrash a survival bot standing on a frigate's flight deck as its engines die: carried down, survives
// Oracles: never off the deck or below it, never inside a solid (exact, in the ship's frame), standing drift relative
// to the deck, deck-relative velocity spikes and shoves, bouncing on a flat deck, world-velocity jumps, laps walked,
// crew at their posts, smooth stops, no despawn. Report: DIR/ridecheck.md; exit 3 on any failure.
enum RideCheck {
    final class Report {
        var md: [String] = []
        var fails = 0
        var scene = ""
        func check(_ ok: Bool, _ what: String) {
            print("\(ok ? "PASS" : "FAIL") ride \(scene): \(what)")
            md.append("- " + (ok ? "" : "**FAIL** ") + what)
            if !ok { fails += 1 }
        }
        func note(_ s: String) { print("ride \(scene): \(s)"); md.append("- " + s) }
    }

    final class Bot: AgentBot {
        let name = "ride"
        var plan: (AgentState) -> AgentAction = { _ in AgentAction.idle }
        func act(_ s: AgentState, _ a: Agent) -> AgentAction { plan(s) }
        func goals() -> [(String, Bool, String)] { [] }
    }

    struct Scene { let agent: Agent; let game: Game; let world: World; let ship: Ship; let st: CapitalState }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)            // a CI timeout still shows how far it got
        guard let device = MTLCreateSystemDefaultDevice() else { print("ridecheck: no Metal device"); return 2 }
        PrefsSandbox.begin()
        defer { PrefsSandbox.end() }
        let out = arg("--out") ?? "snaps"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let seed = UInt64(arg("--seed") ?? "") ?? 12345
        let scale = max(0.05, Float(arg("--scale") ?? "") ?? 1)
        let all = "crawler,rough,frigate,warfrigate,board,frigateboard,crew,troops,frigatecrew,frigatecrash"
        let names = (arg("--scenes") ?? all).split(separator: ",").map(String.init)
        let r = Report()
        r.md = ["# Ride check", "", "Seed \(seed), scale \(scale). Bots ride the capital vehicles through Game.tick.", ""]
        let t0 = CFAbsoluteTimeGetCurrent()
        for n in names {
            r.scene = n
            r.md.append("## \(n)")
            let ts = CFAbsoluteTimeGetCurrent()
            let secs: (Float) -> Int = { max(10, Int(($0 * scale).rounded())) }
            switch n {
            case "crawler", "rough":
                guard let sc = makeScene(device, seed: seed, kind: "crawler", rough: n == "rough") else { r.check(false, "the crawler spawned"); continue }
                deckScene(r, sc, deckY: 22, start: V3(12.5, 22.02, 46.5),
                          lap: [V3(12.5, 22, 32.5), V3(22.5, 22, 32.5), V3(22.5, 22, 60.5), V3(12.5, 22, 60.5)], seconds: secs(240), turnEvery: 20)
            case "frigate":
                guard let sc = makeScene(device, seed: seed, kind: "capfrigate") else { r.check(false, "the frigate spawned"); continue }
                // Laps on the hangar deck (feet 5; the Capital frigate's centreline is x 23.5, the hangar z 66-104).
                deckScene(r, sc, deckY: 5, start: V3(23.5, 5.02, 85.5),
                          lap: [V3(17.5, 5, 74.5), V3(29.5, 5, 74.5), V3(29.5, 5, 96.5), V3(17.5, 5, 96.5)], seconds: secs(240), turnEvery: 30)
            case "warfrigate":
                guard let sc = makeScene(device, seed: seed, kind: "warfrigate") else { r.check(false, "the frigate spawned"); continue }
                deckScene(r, sc, deckY: 27, start: V3(56.5, 27.02, 190.5),
                          lap: [V3(53.5, 27, 172.5), V3(59.5, 27, 172.5), V3(59.5, 27, 208.5), V3(53.5, 27, 208.5)], seconds: secs(90), turnEvery: 30)
            case "board":
                guard let sc = makeScene(device, seed: seed, kind: "crawler") else { r.check(false, "the crawler spawned"); continue }
                boardScene(r, sc, seconds: max(secs(200), 160))     // it stops when every step is done
            case "frigateboard":
                guard let sc = makeScene(device, seed: seed, kind: "capfrigate") else { r.check(false, "the frigate spawned"); continue }
                frigateBoardScene(r, sc, seconds: max(secs(150), 120))
            case "crew":
                guard let sc = makeScene(device, seed: seed, kind: "crawler", crew: true) else { r.check(false, "the crawler spawned"); continue }
                crewScene(r, sc, seconds: secs(120), frigate: false)
            case "troops":
                guard let sc = makeScene(device, seed: seed, kind: "crawler", crew: true) else { r.check(false, "the crawler spawned"); continue }
                troopScene(r, sc)
            case "frigatecrew":
                guard let sc = makeScene(device, seed: seed, kind: "capfrigate", crew: true) else { r.check(false, "the frigate spawned"); continue }
                crewScene(r, sc, seconds: secs(90), frigate: true)
            case "frigatecrash":
                guard let sc = makeScene(device, seed: seed, kind: "capfrigate") else { r.check(false, "the frigate spawned"); continue }
                crashScene(r, sc)
            default:
                r.check(false, "unknown scene \(n)")
            }
            r.note(String(format: "scene took %.0f s", CFAbsoluteTimeGetCurrent() - ts))
            r.md.append("")
        }
        let summary = String(format: "ridecheck: %@ (%ld scenes in %.0f s)", r.fails == 0 ? "PASS" : "\(r.fails) FAILED", names.count, CFAbsoluteTimeGetCurrent() - t0)
        r.md.insert(summary, at: 2)
        try? (r.md.joined(separator: "\n") + "\n").write(toFile: "\(out)/ridecheck.md", atomically: true, encoding: .utf8)
        print(summary)
        return r.fails == 0 ? 0 : 3
    }

    // MARK: Scene setup

    // Land near p: flat (height range under 7 over 84 blocks) or, for `rough`, the roughest (10-28) found.
    // verify: a flat spot is loaded and checked on the real ground too (the generator's heights miss carved river
    // valleys: a 'flat' spot straddled one, and the bot at the crawler's ladder stood 17 blocks below its wheels).
    static func land(_ w: World, near p: V3, rough: Bool, verify: Bool = false) -> (Int, Int) {
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        var first: (Int, Int)?
        var best: (Int, Int)?
        var bestRange = 0
        for r in stride(from: 0, through: 1500, by: 60) { for a in 0..<12 {
            let ang: Float = Float(a) * 0.5236 + Float(r) * 0.01
            let ax = x + Int(Float(r) * cosf(ang)), az = z + Int(Float(r) * sinf(ang))
            var lo = Int.max, hi = Int.min
            for j in -3...3 { for k in -3...3 {
                let h = w.gen.column(ax + j * 14, az + k * 14).height
                lo = min(lo, h); hi = max(hi, h)
            } }
            if lo <= SEA + 2 { continue }
            if first == nil { first = (ax, az) }
            let range = hi - lo
            if !rough {
                if range <= 6 && verify {
                    _ = w.loadSync(center: V3(Float(ax), 100, Float(az)), radius: 3)
                    var lo2: Float = .greatestFiniteMagnitude, hi2: Float = -.greatestFiniteMagnitude
                    for j in -3...3 { for k in -3...3 {
                        let h = w.ships.groundTop(ax + j * 10, az + k * 10)
                        lo2 = min(lo2, h); hi2 = max(hi2, h)
                    } }
                    if hi2 - lo2 <= 6 { return (ax, az) }
                    continue
                }
                if range <= 6 { return (ax, az) }
            } else if range >= 10 && range <= 28 && range > bestRange {
                bestRange = range; best = (ax, az)
            }
        } }
        return best ?? first ?? (x, z)
    }

    static func makeScene(_ device: MTLDevice, seed: UInt64, kind: String, rough: Bool = false, crew: Bool = false) -> Scene? {
        let (world, game) = Agent.makeWorld(device: device, seed: seed, botSeed: 1, rd: 6)
        // Ordinary streaming: the replay-deterministic mode waits on every frame's chunk jobs, and a vehicle crossing
        // new ground all the time made each tick wait (the ride check ran past CI's limit).
        World.deterministic = false
        world.ships.encounters = false
        game.difficulty = 0
        if crew { game.survival = false }          // creative: the crew fight each other's factions, not the bot
        let spot = land(world, near: game.player.pos, rough: rough, verify: kind == "crawler")
        world.ships.spawnCapital(kind, home: IVec3(spot.0, 0, spot.1), yaw: 0.4, region: nil, sync: true)
        guard let c = world.ships.capitals.first(where: { $0.role == kind }), let st = world.ships.capState[c.id] else { return nil }
        if !crew { st.crewDone = Set(0..<st.crew.count); st.crewless = true }
        game.autoJump = true                        // the bots walk over 1-block steps on the ground like a player would
        _ = world.loadSync(center: c.pos, radius: 4)
        return Scene(agent: Agent(game: game, world: world), game: game, world: world, ship: c, st: st)
    }

    // The bot at a ship-space point, moving with the deck.
    static func place(_ sc: Scene, local: V3) {
        let p = sc.game.player
        p.flying = false
        p.pos = sc.ship.toWorld(local)
        p.vel = sc.ship.velocity(at: p.pos)
        p.yaw = sc.ship.yaw
        p.pitch = 0
        p.airPeak = p.pos.y
        p.lastUpdatePos = p.pos
        _ = sc.world.loadSync(center: p.pos, radius: 3)
    }

    // Walk toward a world point: turn (at most 0.25 rad a tick), forward while roughly facing it.
    static func walk(_ s: AgentState, to w: V3, sprint: Bool = false, jump: Bool = false) -> AgentAction {
        var a = AgentAction()
        let dx = w.x - s.pos.x, dz = w.z - s.pos.z
        var d = atan2f(-dx, -dz) - s.yaw
        while d > .pi { d -= 2 * .pi }
        while d < -Float.pi { d += 2 * Float.pi }
        a.yaw = max(-0.25, min(0.25, d))
        let dist = (dx * dx + dz * dz).squareRoot()
        if dist > 0.15 && abs(d) < 0.8 { a.forward = 1 }
        a.sprint = sprint && dist > 3
        a.jump = jump
        return a
    }

    static func wrap(_ a: Float) -> Float {
        var d = a
        while d > .pi { d -= 2 * .pi }
        while d < -Float.pi { d += 2 * Float.pi }
        return d
    }

    // MARK: Per-tick oracles for the bot

    final class Monitor {
        let sc: Scene
        let deckY: Float
        var ticks = 0, offTicks = 0, insideTicks = 0, belowTicks = 0, spikes = 0, shoves = 0, bounces = 0
        var maxRelJump: Float = 0, maxRelSpeed: Float = 0, maxWorldJump: Float = 0, maxBounce: Float = 0, worstDrift: Float = 0
        var firstOff = "", firstInside = "", firstSpike = ""
        private var prevL: V3?, prevRV: V3?, prevW: V3?, prevWV: V3?
        private var prevGround = false, prevAboard = false
        private var ref: V3?
        private var calm = 0                        // ticks since the last jump or landing (velocity checks skip 3 after one)
        var transitions = 0
        var maxTransitionJump: Float = 0
        var spikeLimit: Float = 3                   // b/s in a tick (a bot walking into a wall stops dead: 4.3)
        init(_ sc: Scene, deckY: Float) { self.sc = sc; self.deckY = deckY }

        // After a tick. standing: the bot gives no input (its drift over the deck is measured); aboard: it should be.
        func sample(standing: Bool, aboard expect: Bool, flatDeck: Bool) {
            let p = sc.game.player, s = sc.ship, w = sc.world
            let l = s.toLocal(p.pos)
            let dt: Float = 1.0 / 60
            ticks += 1
            let aboard = w.ships.aboard === s
            let where_ = String(format: "tick %ld, ship-space %.2f %.2f %.2f", ticks, l.x, l.y, l.z)
            if expect && !aboard { offTicks += 1; if firstOff.isEmpty { firstOff = where_ } }
            if expect && l.y < deckY - 0.5 { belowTicks += 1; if firstOff.isEmpty { firstOff = where_ + " (below the deck)" } }
            if aboard {
                w.frame = s
                let lo = V3(l.x - p.halfW + 0.05, l.y + 0.05, l.z - p.halfW + 0.05)
                let hi = V3(l.x + p.halfW - 0.05, l.y + p.height - 0.1, l.z + p.halfW - 0.05)
                let inside = w.collides(lo, hi)
                let b = w.block(Int(floor(l.x)), Int(floor(l.y + 0.5)), Int(floor(l.z)))
                w.frame = nil
                if inside { insideTicks += 1; if firstInside.isEmpty { firstInside = where_ + " in " + Blocks.key(b) } }
            }
            calm = p.jumped || p.onGround != prevGround ? 0 : calm + 1
            let jumpy = calm < 3
            if aboard != prevAboard && ticks > 1 { transitions += 1 }
            if let pl = prevL, aboard && prevAboard {
                let rv = (l - pl) / dt
                let h = simd_length(V2(rv.x, rv.z))
                maxRelSpeed = max(maxRelSpeed, h)
                if h > 7.5 { shoves += 1 }
                if let pr = prevRV, !jumpy {
                    let j = simd_length(V2(rv.x - pr.x, rv.z - pr.z))
                    maxRelJump = max(maxRelJump, j)
                    if j > spikeLimit { spikes += 1; if firstSpike.isEmpty { firstSpike = where_ + String(format: " (%.1f b/s in a tick)", j) } }
                }
                if flatDeck && p.onGround && prevGround && !jumpy {
                    maxBounce = max(maxBounce, abs(rv.y))
                    if abs(rv.y) > 0.6 { bounces += 1 }
                }
                prevRV = rv
            } else {
                prevRV = nil
            }
            if let pw = prevW {
                let wv = (p.pos - pw) / dt
                if let pv = prevWV, !jumpy {
                    let j = simd_length(wv - pv)
                    maxWorldJump = max(maxWorldJump, j)
                    // (horizontal: leaving onto the world's ground may step up onto it)
                    if aboard != prevAboard { maxTransitionJump = max(maxTransitionJump, simd_length(V2(wv.x - pv.x, wv.z - pv.z))) }
                }
                prevWV = wv
            }
            if standing && aboard {
                if ref == nil { ref = l }
                if let r0 = ref { worstDrift = max(worstDrift, simd_length(V2(l.x - r0.x, l.z - r0.z))) }
            } else { ref = nil }
            prevL = l; prevW = p.pos; prevGround = p.onGround; prevAboard = aboard
        }
    }

    // Distance driven and turned by a ship (accumulated each tick).
    final class Odometer {
        let s: Ship
        var dist: Float = 0, turned: Float = 0
        private var last: V3, lastYaw: Float
        init(_ s: Ship) { self.s = s; last = s.pos; lastYaw = s.yaw }
        func tick() {
            dist += simd_length(V2(s.pos.x - last.x, s.pos.z - last.z))
            turned += abs(RideCheck.wrap(s.yaw - lastYaw))
            last = s.pos; lastYaw = s.yaw
        }
    }

    // MARK: Scenes

    // Stand 20 s, then cycles of 25 s walking laps (every other lap sprinting, a jump every 6 s) and 8 s standing,
    // while the vehicle drives S-turns (full turn one way, then the other, every `turnEvery` seconds).
    static func deckScene(_ r: Report, _ sc: Scene, deckY: Float, start: V3, lap: [V3], seconds: Int, turnEvery: Int) {
        let s = sc.ship, st = sc.st, g = sc.game
        place(sc, local: start)
        st.testTurn = 1
        let bot = Bot()
        let mon = Monitor(sc, deckY: deckY)
        let odo = Odometer(s)
        var wp = 0, laps = 0, legs = 0
        var standing = true
        var t: Float = 0
        bot.plan = { stt in
            let cyc = (t - 20).truncatingRemainder(dividingBy: 33)
            standing = t < 20 || cyc >= 25
            if standing { return AgentAction.idle }
            let target = s.toWorld(lap[wp])
            if simd_length(V2(target.x - stt.pos.x, target.z - stt.pos.z)) < 0.6 {
                wp = (wp + 1) % lap.count
                legs += 1
                if wp == 0 { laps += 1 }
            }
            let jump = Int(t * 60) % 360 == 0
            return walk(stt, to: s.toWorld(lap[wp]), sprint: laps % 2 == 1, jump: jump)
        }
        var standT: Float = 0
        let ticks = seconds * 60
        for i in 0..<ticks {
            t = Float(i) / 60
            if turnEvery > 0 && i > 0 && i % (60 * turnEvery) == 0 { st.testTurn = (i / (60 * turnEvery)) % 2 == 0 ? 1 : -1 }
            g.health = 20
            g.hunger = 20
            sc.agent.step(bot)
            standT = standing ? standT + 1.0 / 60 : 0
            mon.sample(standing: standing && standT > 1.5, aboard: true, flatDeck: true)
            odo.tick()
            if i % (60 * 30) == 0 {
                let l = s.toLocal(g.player.pos)
                r.note(String(format: "t %3.0f s: ship at %.0f,%.0f,%.0f yaw %.2f speed %.1f; bot ship-space %.2f,%.2f,%.2f%@",
                              t, s.pos.x, s.pos.y, s.pos.z, s.yaw, simd_length(s.vel), l.x, l.y, l.z, standing ? " standing" : ""))
            }
        }
        let minLaps = max(1, seconds / 60)
        let oc = sc.agent.counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        r.note("agent oracles: \(oc.isEmpty ? "none" : oc)")
        r.check(sc.agent.counts["inside_solid"] == nil, "the general bot oracle sees no inside-solid either (\(sc.agent.counts["inside_solid"] ?? 0))")
        r.note(String(format: "drove %.0f blocks, turned %.0f degrees; bot walked %ld laps (%ld legs)", odo.dist, odo.turned * 180 / .pi, laps, legs))
        r.check(odo.dist > Float(seconds) * 2.5 && odo.turned > 1, String(format: "the vehicle drives and turns (%.0f blocks, %.1f rad)", odo.dist, odo.turned))
        r.check(mon.offTicks == 0 && mon.belowTicks == 0, "the bot never leaves the deck (\(mon.offTicks) ticks off, \(mon.belowTicks) below)\(mon.firstOff.isEmpty ? "" : ", first at " + mon.firstOff)")
        r.check(mon.insideTicks == 0, "the bot is never inside a solid (\(mon.insideTicks) ticks)\(mon.firstInside.isEmpty ? "" : ", first at " + mon.firstInside)")
        r.check(mon.worstDrift < 0.05, String(format: "standing still, the bot drifts %.4f blocks over the deck (limit 0.05)", mon.worstDrift))
        r.check(mon.spikes == 0, String(format: "no deck-relative velocity spikes (%ld over 3 b/s in a tick, worst %.2f)%@", mon.spikes, mon.maxRelJump,
                                        mon.firstSpike.isEmpty ? "" : ", first at " + mon.firstSpike))
        r.check(mon.shoves == 0, String(format: "never shoved across the deck (fastest %.2f b/s relative; sprint is 5.6)", mon.maxRelSpeed))
        r.check(mon.bounces == 0, String(format: "no bouncing on the flat deck (%ld ticks, worst %.2f b/s)", mon.bounces, mon.maxBounce))
        r.check(mon.maxWorldJump < 6, String(format: "world velocity never jumps (worst change %.2f b/s in a tick, limit 6)", mon.maxWorldJump))
        r.check(laps >= minLaps, "the bot walks laps (\(laps), at least \(minLaps))")
    }

    // Boarding and leaving a moving crawler by its ladder, hatch and ramp.
    static func boardScene(_ r: Report, _ sc: Scene, seconds: Int) {
        let s = sc.ship, st = sc.st, g = sc.game, w = sc.world
        st.testTurn = 0
        st.testSpeed = 1.2
        // Let it get going (the ramp folds up only above a creep; at 1.2 b/s it stays down).
        for _ in 0..<120 { sc.agent.step(Bot()) }
        let foot = s.toWorld(V3(3.3, 0, 29.5))
        let fx = Int(floor(foot.x)), fz = Int(floor(foot.z))
        _ = w.loadSync(center: foot, radius: 3)
        g.player.flying = false
        let up = s.dirToWorld(V3(0, 1, 0))
        let cx = Int(floor(s.pos.x)), cz = Int(floor(s.pos.z))
        r.note(String(format: "crawler at %.1f,%.1f,%.1f, wheels' bottom %.1f, ground under it %.0f (world top %ld, generator %ld), up %.2f,%.2f,%.2f; ground at the ladder foot %ld",
                      s.pos.x, s.pos.y, s.pos.z, s.worldMin.y, w.ships.groundTop(cx, cz), w.topY(cx, cz), w.gen.column(cx, cz).height, up.x, up.y, up.z, w.topY(fx, fz)))
        g.player.pos = V3(foot.x, Float(w.topY(fx, fz) + 1), foot.z)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
        g.player.lastUpdatePos = g.player.pos
        g.player.yaw = s.yaw
        let mon = Monitor(sc, deckY: 0)
        mon.spikeLimit = 6                           // hatches, ladders and stairs: walking into a wall stops the bot
        let bot = Bot()
        var phase = 0
        var stuckT: Float = 0
        var lastPos = g.player.pos
        var wp = 0, underRamp = 0
        var reached: [String] = []
        var phaseT: Float = 0
        let names = ["reach the port ladder", "climb it to the roof walkway", "walk through the hatch into the command deck",
                     "walk back out and down the ladder to the ground", "walk round to the rear ramp and up it into the troop bay",
                     "walk down the ramp to the ground"]
        let routes: [[V3]] = [
            [V3(5.45, 0, 29.5)],
            [],
            [V3(7.4, 21, 30.5), V3(9.7, 22, 30.5), V3(13.5, 22, 30.5), V3(15.5, 22, 35.5)],
            [V3(13.5, 22, 30.5), V3(9.7, 22, 30.5), V3(7.4, 21, 30.0), V3(4.9, 21, 29.5)],
            [V3(-1.5, 0, 33), V3(-1.5, 0, 90), V3(17.5, 0, 90), V3(17.5, 0, 86), V3(17.5, 10, 74.6), V3(17.5, 10, 72.6), V3(25, 10, 66)],
            [V3(17.5, 10, 72.6), V3(17.5, 10, 74.6), V3(17.5, 1, 83.5), V3(17.5, 0, 90)],
        ]
        func advance(_ why: String) {
            reached.append(String(format: "%@ at %.0f s", why, phaseT))
            r.note("reached: " + why)
            phase += 1; wp = 0; phaseT = 0
        }
        bot.plan = { stt in
            let l = s.toLocal(stt.pos)
            let aboard = w.ships.aboard === s
            switch phase {
            case 0:
                if l.x > 5.15 && abs(l.z - 29.5) < 0.6 { advance(names[0]); return AgentAction.idle }
                return walk(stt, to: s.toWorld(routes[0][0]))
            case 1:
                // Done once standing on the roof (stopping at the ladder's top to turn, it would drop off).
                if l.y > 20.95 && aboard && stt.onGround && l.x > 6.05 { advance(names[1]); return AgentAction.idle }
                var a = walk(stt, to: s.toWorld(V3(9, 0, 29.5)))
                a.forward = 1
                a.jump = true
                return a
            case 2, 3, 4, 5:
                let route = routes[phase]
                if wp >= route.count {
                    let done: Bool
                    switch phase {
                    case 2: done = aboard && l.y > 21.9 && l.y < 22.4
                    case 3: done = !aboard && stt.onGround && l.y < 1.5
                    case 4: done = aboard && l.y > 9.9 && l.y < 10.4
                    default: done = !aboard && stt.onGround && l.z > 84
                    }
                    if done { advance(names[phase]); return AgentAction.idle }
                    // Down the ladder: off the roof edge into the rungs, no input while it slides down, then step off.
                    if phase == 3 { return l.y > 1.2 ? AgentAction.idle : walk(stt, to: s.toWorld(V3(2.8, 0, 29.5))) }
                    return AgentAction.idle
                }
                let target = route[wp]
                let tw = s.toWorld(target)
                if simd_length(V2(tw.x - stt.pos.x, tw.z - stt.pos.z)) < 0.45 {
                    // A point up on the ramp counts only at its height: the stairs have open space under them, and a bot
                    // that missed the bottom step walked on under the ramp past every point (run of c7bad4f). Back to
                    // the foot and up again.
                    if target.y > 2 && l.y < target.y - 2.5 && wp > 0 {
                        underRamp += 1
                        wp = max(0, (route.firstIndex { $0.y > 2 } ?? 1) - 1)
                        return AgentAction.idle
                    }
                    wp += 1; return AgentAction.idle
                }
                var a = walk(stt, to: tw)
                // Stuck on the ground (a bush, a step the auto-jump won't take): jump, then side-step a moment.
                let moved = simd_length(V2(stt.pos.x - lastPos.x, stt.pos.z - lastPos.z))
                lastPos = stt.pos
                stuckT = a.forward > 0 && moved < 0.02 ? stuckT + 1.0 / 60 : 0
                if stuckT > 0.5 { a.jump = true }
                if stuckT > 1.5 { a.strafe = Int(stuckT * 2) % 2 == 0 ? 1 : -1 }
                if stuckT > 3 { stuckT = 0 }
                return a
            default:
                return AgentAction.idle
            }
        }
        for i in 0..<(seconds * 60) {
            phaseT += 1.0 / 60
            // At the ramp the crawler creeps slower (still moving: boarding a moving vehicle).
            st.testSpeed = phase >= 4 ? 0.8 : 1.2
            g.health = 20
            g.hunger = 20
            sc.agent.step(bot)
            mon.sample(standing: false, aboard: false, flatDeck: false)
            if phase >= 6 { break }
            if i % (60 * 20) == 0 {
                let l = s.toLocal(g.player.pos)
                r.note(String(format: "t %3.0f s: phase %ld step %ld, bot ship-space %.2f,%.2f,%.2f, aboard %@, ramp %@, ship speed %.2f", Float(i) / 60, phase, wp,
                              l.x, l.y, l.z, w.ships.aboard === s ? "yes" : "no", st.rampDown ? "down" : "up", simd_length(V2(s.vel.x, s.vel.z))))
            }
        }
        r.note("reached: " + (reached.isEmpty ? "nothing" : reached.joined(separator: "; ")))
        if underRamp > 0 || phase == 4 {
            // The ramp as it stands: its stairs present (of 50) and the ground under its foot (ship space).
            let ox = s.grid.sx / 2
            let stairs = Capital.crawlerRamp(down: true).filter { $0.1 != AIR && s.grid.get($0.0.x + ox, $0.0.y, $0.0.z) == $0.1 }.count
            let foot = s.toWorld(V3(Float(ox) + 0.5, 0, 83.5))
            let gy = Float(w.topY(Int(floor(foot.x)), Int(floor(foot.z))) + 1)
            r.note(String(format: "ramp: %@, %ld of 50 stairs in place, ground under its foot at ship-space y %.2f; the bot went back to the foot %ld times",
                          st.rampDown ? "down" : "up", stairs, s.toLocal(V3(foot.x, gy, foot.z)).y, underRamp))
        }
        for (k, n) in names.enumerated() { r.check(phase > k, "the bot can \(n) while the crawler moves") }
        r.check(mon.insideTicks == 0, "never inside a solid while aboard (\(mon.insideTicks) ticks)\(mon.firstInside.isEmpty ? "" : ", first at " + mon.firstInside)")
        r.check(mon.transitions >= 2 && mon.maxTransitionJump < 3, String(format: "boarding and leaving keep the bot's world velocity (%ld changes, worst jump %.2f b/s)",
                                                                       mon.transitions, mon.maxTransitionJump))
        r.check(mon.spikes == 0, String(format: "no deck-relative velocity spikes aboard (%ld, worst %.2f)", mon.spikes, mon.maxRelJump))
    }

    // Landing on a moving frigate by flight, walking its hangar, deckhouse, side door and narrow side deck, taking off.
    static func frigateBoardScene(_ r: Report, _ sc: Scene, seconds: Int) {
        let s = sc.ship, st = sc.st, g = sc.game, w = sc.world
        g.survival = false
        st.testTurn = 0.6
        st.testSpeed = 5
        for _ in 0..<60 { sc.agent.step(Bot()) }
        let p = g.player
        // Ship space: the Capital frigate's centreline is x 23.5; the hangar deck is at 4 (feet 5), open through both
        // flanks for z 72-98; the ladder from the hangar to the crew deck (feet 13) is at x 22.5, z 107.5.
        p.pos = s.toWorld(V3(23.5 + 24, 6.3, 85.5))
        p.vel = s.velocity(at: p.pos)
        p.flying = true
        p.yaw = s.yaw
        p.lastUpdatePos = p.pos
        _ = w.loadSync(center: p.pos, radius: 3)
        let mon = Monitor(sc, deckY: 5)
        mon.spikeLimit = 6                           // ladders and doorways: walking into a wall stops the bot
        let bot = Bot()
        var phase = 0, wp = 0
        var phaseT: Float = 0
        var reached: [String] = []
        let names = ["fly in through the starboard hangar opening and land on the hangar deck",
                     "walk the hangar to the ladder and climb to the crew deck",
                     "walk the crew deck's corridor forward and back",
                     "go down the ladder to the hangar",
                     "walk out through the port opening and take off"]
        let corridor: [V3] = [V3(23.5, 13, 100.5), V3(23.5, 13, 60.5), V3(23.5, 13, 104.5), V3(23.5, 13, 107.5)]
        func advance(_ why: String) {
            reached.append(String(format: "%@ at %.0f s", why, phaseT))
            r.note("reached: " + why)
            phase += 1; wp = 0; phaseT = 0
        }
        bot.plan = { stt in
            let aboard = w.ships.aboard === s
            let l = s.toLocal(stt.pos)
            func go(_ route: [V3]) -> AgentAction? {
                if wp >= route.count { return nil }
                let tw = s.toWorld(route[wp])
                if simd_length(V2(tw.x - stt.pos.x, tw.z - stt.pos.z)) < 0.4 { wp += 1; return AgentAction.idle }
                return walk(stt, to: tw)
            }
            switch phase {
            case 0:
                if aboard && stt.onGround && l.y > 4.9 && l.y < 5.5 { advance(names[0]); return AgentAction.idle }
                let tw = s.toWorld(V3(29.5, 5, 85.5))
                var a = walk(stt, to: tw)
                let d = simd_length(V2(tw.x - stt.pos.x, tw.z - stt.pos.z))
                a.forward = d > 0.8 && a.forward > 0 ? 1 : 0
                // Level through the opening (y 5-10; the walk helper's step jump would lift a flier onto the roof),
                // then down onto the deck once inside the flank.
                a.jump = false
                a.sneak = l.x < 34 || l.y > 7.5
                return a
            case 1:
                if let a = go([V3(23.5, 5, 100.5), V3(23.5, 5, 107.5)]) { return a }
                if l.y > 12.9 && l.y < 13.5 && aboard && stt.onGround && l.x > 22.95 { advance(names[1]); return AgentAction.idle }
                // Into the rungs (against the wall behind them), climbing; at the top, off onto the corridor floor.
                var a = walk(stt, to: s.toWorld(V3(l.y > 12.4 ? 24.0 : 21.0, 0, 107.5)))
                a.forward = 1
                a.jump = l.y < 12.4
                return a
            case 2:
                if let a = go(corridor) { return a }
                if aboard { advance(names[2]) }
                return AgentAction.idle
            case 3:
                if aboard && stt.onGround && l.y < 5.5 { advance(names[3]); return AgentAction.idle }
                // Over the shaft beside the corridor, clear of the rungs' panel against the wall (pushing into the wall the
                // bot stood on top of it), then no input while it drops in and slides down the ladder.
                if l.y > 11.5 && l.x > 22.75 { return walk(stt, to: s.toWorld(V3(22.55, 0, 107.5))) }
                return AgentAction.idle
            case 4:
                if let a = go([V3(23.5, 5, 100.5), V3(23.5, 5, 85.5), V3(14.5, 5, 85.5), V3(2.5, 5, 85.5)]) {
                    var b = a
                    if l.x < 13 && phaseT > 0.5 && !p.flying { b.key = KeyBinds.key(.fly) }
                    return b
                }
                if !aboard && phaseT > 1 { advance(names[4]); return AgentAction.idle }
                var a = AgentAction()
                if !p.flying { a.key = KeyBinds.key(.fly) }
                a.jump = true
                a.strafe = -1
                return a
            default:
                return AgentAction.idle
            }
        }
        for i in 0..<(seconds * 60) {
            phaseT += 1.0 / 60
            g.hunger = 20
            sc.agent.step(bot)
            mon.sample(standing: false, aboard: phase >= 1 && phase <= 3, flatDeck: false)
            if phase >= 5 { break }
            if i % (phase <= 3 ? 60 : 60 * 20) == 0 {
                let l = s.toLocal(p.pos)
                r.note(String(format: "t %3.0f s: phase %ld, bot ship-space %.2f,%.2f,%.2f, aboard %@, flying %@", Float(i) / 60, phase,
                              l.x, l.y, l.z, w.ships.aboard === s ? "yes" : "no", p.flying ? "yes" : "no"))
            }
        }
        r.note("reached: " + (reached.isEmpty ? "nothing" : reached.joined(separator: "; ")))
        for (k, n) in names.enumerated() { r.check(phase > k, "the bot can \(n) while the frigate cruises and turns") }
        r.check(mon.offTicks == 0 && mon.belowTicks == 0, "aboard all the way round (\(mon.offTicks) ticks off)\(mon.firstOff.isEmpty ? "" : ", first at " + mon.firstOff)")
        r.check(mon.insideTicks == 0, "never inside a solid (\(mon.insideTicks) ticks)\(mon.firstInside.isEmpty ? "" : ", first at " + mon.firstInside)")
        r.check(mon.transitions >= 2 && mon.maxTransitionJump < 3, String(format: "landing and taking off keep the bot's world velocity (%ld changes, worst jump %.2f b/s)",
                                                                       mon.transitions, mon.maxTransitionJump))
        r.check(mon.spikes == 0 && mon.bounces == 0, String(format: "no velocity spikes or bouncing aboard (%ld, %ld; worst %.2f)", mon.spikes, mon.bounces, mon.maxRelJump))
    }

    // The crawler's bay troops go out on foot: the ramp lowers and they walk round the engine room and down it.
    static func troopScene(_ r: Report, _ sc: Scene) {
        let s = sc.ship, st = sc.st, g = sc.game, w = sc.world
        place(sc, local: V3(23.5, 22.02, 44.5))
        let idle = Bot()
        // Driving on patrol first (whatever its AI would chase near the spawn), then left to its own AI with the foes.
        st.testTurn = 0
        st.testSpeed = 3
        for _ in 0..<(10 * 60) { sc.agent.step(idle) }
        st.testTurn = nil
        st.testSpeed = nil
        let rampAtStart = st.rampDown
        r.note(String(format: "before the foes: ramp %@, AI wants %.1f b/s, speed %.1f, driver alive %@", st.rampDown ? "down" : "up", st.wantSpeed,
                      simd_length(V2(s.vel.x, s.vel.z)), st.driverAlive ? "yes" : "no"))
        var foes: [Mob] = []
        for k in 0..<2 {
            let at = s.toWorld(V3(17.5 + Float(k) * 4, 0, -55))
            let ix = Int(floor(at.x)), iz = Int(floor(at.z))
            _ = w.loadSync(center: at, radius: 2)
            let m = Mob(.soldierIronclad, at: V3(at.x, Float(w.topY(ix, iz) + 1), at.z))
            m.persistent = true
            g.mobs.mobs.append(m)
            foes.append(m)
        }
        var out = Set<ObjectIdentifier>()
        var jumps = 0, inside = 0, rampSeen = false
        var last: [ObjectIdentifier: (V3, Bool)] = [:]
        var firstJump = "", firstInside = ""
        var t: Float = 0
        while t < 80 {
            for m in foes { m.health = max(m.health, 50) }        // they must outlast the crawler's guns for the test
            sc.agent.step(idle)
            t += 1.0 / 60
            if Int(t * 60) % 300 == 0 {
                let walking = st.crewMobs.values.filter { !$0.crewRoute.isEmpty && $0.deck === s }
                let where_ = walking.prefix(2).map { m -> String in
                    let l = s.toLocal(m.pos)
                    return String(format: "%.1f,%.1f,%.1f (%ld left)", l.x, l.y, l.z, m.crewRoute.count)
                }.joined(separator: "; ")
                r.note(String(format: "t %.0f s: ramp %@, AI wants %.1f b/s, speed %.1f, target %@, %ld troops walking out %@", t, st.rampDown ? "down" : "up",
                              st.wantSpeed, simd_length(V2(s.vel.x, s.vel.z)), st.target == nil ? "none" : "yes", walking.count, where_))
            }
            if st.rampDown { rampSeen = true }
            for (k, m) in st.crewMobs where m.health > 0 && k < st.crew.count && st.crew[k].y < 15 && st.crewRoles[k] == .troop {
                let id = ObjectIdentifier(m)
                let l = s.toLocal(m.pos)
                if let prev = last[id], simd_length(m.pos - prev.0) > 1 {
                    let p = prev.0, wasAboard = prev.1
                    jumps += 1
                    if firstJump.isEmpty {
                        let a = s.toLocal(p)
                        firstJump = String(format: "t %.1f s: %.1f,%.1f,%.1f -> %.1f,%.1f,%.1f ship space, aboard %@ -> %@, route %ld left, ramp %@", t, a.x, a.y, a.z,
                                           l.x, l.y, l.z, wasAboard ? "yes" : "no", m.deck === s ? "yes" : "no", m.crewRoute.count, st.rampDown ? "down" : "up")
                    }
                }
                last[id] = (m.pos, m.deck === s)
                if m.deck === s {
                    w.frame = s
                    if m.collides(l + V3(0, 0.05, 0), w) {
                        inside += 1
                        if firstInside.isEmpty {
                            let c = IVec3(Int(floor(l.x)), Int(floor(l.y + 0.5)), Int(floor(l.z)))
                            firstInside = String(format: "t %.1f s: %.2f,%.2f,%.2f ship space (block %@ there, %@ under), route %ld left, ramp %@", t, l.x, l.y, l.z,
                                                 Blocks.key(s.grid.get(c.x, c.y, c.z)), Blocks.key(s.grid.get(c.x, c.y - 1, c.z)), m.crewRoute.count, st.rampDown ? "down" : "up")
                        }
                    }
                    w.frame = nil
                } else if m.onGround && l.z > 76 { out.insert(id) }
            }
            if out.count >= 2 && t > 30 { break }
        }
        r.note(String(format: "ramp %@ before the foes came; %ld troops walked out in %.0f s; troops left %ld", rampAtStart ? "down" : "up", out.count, t, st.troops.count))
        r.check(!rampAtStart && rampSeen, "the ramp is up while it drives and comes down for the troops")
        r.check(out.count >= 2, "bay troops walk out by the ramp onto the ground (\(out.count))")
        r.check(jumps == 0, "no troop is teleported (\(jumps) jumps over a block in a tick)\(firstJump.isEmpty ? "" : "; first " + firstJump)")
        r.check(inside == 0, "no troop inside a solid on the way out (\(inside) troop-ticks)\(firstInside.isEmpty ? "" : "; first " + firstInside)")
    }

    // Crew: soldiers ride at their posts while the vehicle drives and turns; then it is disabled and they stay aboard.
    static func crewScene(_ r: Report, _ sc: Scene, seconds: Int, frigate: Bool) {
        let s = sc.ship, st = sc.st, g = sc.game, w = sc.world
        place(sc, local: frigate ? V3(23.5, 5.02, 85.5) : V3(23.5, 22.02, 44.5))
        st.testTurn = 1
        let idle = Bot()
        let floorY: Float = frigate ? 3.5 : 9.5          // no crew member ever below the lowest deck (the frigate's hangar and hold: 4)
        var worstPost: Float = 0, worstWho = ""
        var off = 0, inside = 0, firstOff = ""
        func crewCheck(_ i: Int, posts: Bool) {
            for (k, m) in st.crewMobs where m.health > 0 {
                let l = s.toLocal(m.pos)
                if m.deck !== s || l.y < floorY - 0.6 {
                    off += 1
                    if firstOff.isEmpty { firstOff = String(format: "%@ (post %ld) at ship-space %.1f,%.1f,%.1f, deck %@", m.kind.key, k, l.x, l.y, l.z, m.deck === s ? "kept" : "lost") }
                    continue
                }
                w.frame = s
                if m.collides(l + V3(0, 0.05, 0), w) { inside += 1 }
                w.frame = nil
                if posts, k < st.crew.count {
                    let p = st.crew[k]
                    let e = simd_length(V2(l.x - p.x, l.z - p.z))
                    if e > worstPost { worstPost = e; worstWho = "\(m.kind.key) at post \(k)" }
                }
            }
        }
        let n = seconds * 60
        for i in 0..<n {
            if i > 0 && i % 1200 == 0 { st.testTurn = (i / 1200) % 2 == 0 ? 1 : -1 }
            sc.agent.step(idle)
            if i > 300 { crewCheck(i, posts: true) }
        }
        let spawned = st.crewMobs.count
        r.note(String(format: "crew %ld of %ld aboard; ship at %.0f,%.0f,%.0f speed %.1f", spawned, st.crew.count, s.pos.x, s.pos.y, s.pos.z, simd_length(s.vel)))
        r.check(spawned == st.crew.count, "every crew post is manned (\(spawned)/\(st.crew.count))")
        r.check(off == 0, "the crew ride the moving vehicle (\(off) crew-ticks off it)\(firstOff.isEmpty ? "" : ", first: " + firstOff)")
        r.check(worstPost < 1.0, String(format: "every soldier holds its post while it drives and turns (worst %.2f blocks: %@)", worstPost, worstWho))
        r.check(inside == 0, "no crew member inside a solid (\(inside) crew-ticks)")
        // Disable it: half the wheels (the port side) of the crawler, the frigate's drive engines.
        let kinds = ShipParts.kinds
        var cells: [(IVec3, BlockID)] = []
        let gr = s.grid
        if frigate {
            for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx where kinds[Int(gr.get(x, y, z))] == .engine { cells.append((IVec3(x, y, z), AIR)) } } }
        } else {
            for wh in st.wheels where wh.lo.x < gr.sx / 2 {
                for y in wh.lo.y...wh.hi.y { for z in wh.lo.z...wh.hi.z { for x in wh.lo.x...wh.hi.x where kinds[Int(gr.get(x, y, z))] == .wheel {
                    cells.append((IVec3(x, y, z), AIR))
                } } }
            }
        }
        let fw0 = s.dirToWorld(V3(0, 0, -1))
        let speed0 = simd_dot(s.vel, fw0)
        w.ships.setBlocks(s, cells)
        off = 0; inside = 0; firstOff = ""
        var stopT: Float = -1, worstDecel: Float = 0, worstDrop: Float = 0
        var lastV = speed0, lastY = s.pos.y
        var shots = 0
        var aliveAtRest = -1
        var mags: [ObjectIdentifier: Int] = [:]
        var foes: [Mob] = []
        let limit = frigate ? 120 * 60 : 60 * 60
        for i in 0..<limit {
            sc.agent.step(idle)
            let fw = s.dirToWorld(V3(0, 0, -1))
            let v = simd_dot(s.vel, fw)
            worstDecel = max(worstDecel, (lastV - v) * 60)
            worstDrop = max(worstDrop, (lastY - s.pos.y) * 60)
            lastV = v; lastY = s.pos.y
            if stopT < 0 && st.settled { stopT = Float(i) / 60; aliveAtRest = st.crewMobs.values.filter { $0.health > 0 }.count }
            // (Once it is being laid down as a wreck of world blocks the crew stand on those: no deck to stay on.)
            if i > 60 && w.ships.list.contains(where: { $0 === s }) && !s.baking { crewCheck(i, posts: false) }
            // Two enemy soldiers turn up beside the wreck once it is still: the crew fight them from aboard.
            if !frigate && st.settled && foes.isEmpty {
                let side = s.dirToWorld(V3(1, 0, 0))
                for k in 0..<2 {
                    let at = s.pos + side * Float(-34 - k * 3) + V3(0, 0, Float(k) * 3)
                    let ix = Int(floor(at.x)), iz = Int(floor(at.z))
                    let m = Mob(.soldierRecruit, at: V3(at.x, Float(w.topY(ix, iz) + 1), at.z))
                    m.persistent = true
                    g.mobs.mobs.append(m)
                    foes.append(m)
                }
            }
            if !foes.isEmpty {
                for m in st.crewMobs.values where m.health > 0 {
                    let b = m.soldierBrain
                    let id = ObjectIdentifier(m)
                    if let last = mags[id], b.mag < last { shots += last - b.mag }
                    mags[id] = b.mag
                }
            }
            if stopT >= 0 && Float(i) / 60 > stopT + 30 { break }
        }
        let inList = w.ships.list.contains { $0 === s } || !w.ships.wrecks.isEmpty
        let alive = st.crewMobs.values.filter { $0.health > 0 }.count
        r.note(String(format: "disabled at %.1f b/s (%@): came to rest after %.1f s; worst deceleration %.2f b/s2, fastest drop %.2f b/s; impact %.1f b/s; %ld crew alive",
                      speed0, st.disabledWhy, stopT, worstDecel, worstDrop, st.impact, alive))
        r.check(s.wrecked && stopT >= 0, "the disabled vehicle comes to rest (\(st.disabledWhy))")
        r.check(inList, "it stays in the world (no despawn: still a vessel, or laid down as a wreck, \(w.ships.wrecks.count))")
        if frigate {
            r.check(stopT > 6, String(format: "it comes down over time, not at once (%.1f s)", stopT))
            r.check(worstDrop < 8.5, String(format: "it never drops faster than 8 b/s (%.2f)", worstDrop))
            r.check(st.impact < 5, String(format: "the crew flare it: touchdown at %.1f b/s (under 5)", st.impact))
        } else {
            r.check(stopT > 1.5 || speed0 < 1, String(format: "it grinds to a stop, not at once (%.1f s from %.1f b/s)", stopT, speed0))
            r.check(worstDecel < 4, String(format: "no sudden stop (worst deceleration %.2f b/s2)", worstDecel))
            r.check(shots > 0, "the crew fight enemy soldiers from aboard (\(shots) shots)")
        }
        r.check(off == 0, "the crew stay aboard the disabled vehicle (\(off) crew-ticks off)\(firstOff.isEmpty ? "" : ", first: " + firstOff)")
        r.check(aliveAtRest == spawned, "the crew survive it (\(aliveAtRest) of \(spawned) alive when it came to rest, \(alive) at the end)")
        r.check(st.crewMobs.values.allSatisfy { $0.health <= 0 || $0.crewFree }, "the crew are released to fight")
    }

    // A survival bot on the flight deck when the frigate's engines die: carried down, survives the touchdown.
    static func crashScene(_ r: Report, _ sc: Scene) {
        let s = sc.ship, st = sc.st, g = sc.game, w = sc.world
        place(sc, local: V3(23.5, 5.02, 85.5))
        st.testTurn = 0
        let mon = Monitor(sc, deckY: 5)
        let idle = Bot()
        for _ in 0..<(15 * 60) {
            g.hunger = 20
            sc.agent.step(idle)
            mon.sample(standing: false, aboard: true, flatDeck: true)
        }
        let h0 = g.health
        var cells: [(IVec3, BlockID)] = []
        let gr = s.grid, kinds = ShipParts.kinds
        for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx where kinds[Int(gr.get(x, y, z))] == .engine { cells.append((IVec3(x, y, z), AIR)) } } }
        w.ships.setBlocks(s, cells)
        let y0 = s.pos.y
        var t: Float = 0
        var after: Float = 0
        while t < 150 {
            g.hunger = 20
            sc.agent.step(idle)
            t += 1.0 / 60
            mon.sample(standing: t > 1, aboard: true, flatDeck: true)
            if st.settled { after += 1.0 / 60; if after > 5 { break } }
        }
        r.note(String(format: "came down %.0f blocks in %.0f s, touchdown at %.1f b/s; bot health %ld -> %ld", y0 - s.pos.y, t, st.impact, h0, g.health))
        r.check(st.settled && (w.ships.list.contains { $0 === s } || !w.ships.wrecks.isEmpty), "the frigate crash-lands and stays (no despawn)")
        r.check(mon.offTicks == 0 && mon.belowTicks == 0, "the bot rides it down on the deck (\(mon.offTicks) ticks off)\(mon.firstOff.isEmpty ? "" : ", first at " + mon.firstOff)")
        r.check(mon.insideTicks == 0, "never inside a solid (\(mon.insideTicks) ticks)")
        r.check(mon.worstDrift < 0.05, String(format: "standing, it drifts %.4f blocks over the deck on the way down", mon.worstDrift))
        r.check(g.alive && g.health >= h0 - 4, "the bot survives with sensible damage (\(h0) -> \(g.health))")
    }
}
