import Foundation
import Metal
import simd

// --basetest [patrol|crawler|lockdown|rebuild|air|all]: the reactive citadel (CapitalBases.swift) through the real Game.tick.
//  1. A gunshot 40 blocks outside the gate: a patrol forms, reaches the spot, searches and walks back to its posts.
//  2. A blast inside the plaza: lockdown, turret crews in the gunner stance, Capital dropships land troops.
//  3. A blasted hall wall: once calm, rebuilt from the citadel's original blocks within one in-game day; a "wreck"
//     block dropped in the crater is left alone. Also: the bases record survives a save round trip, and the cost of
//     the once-a-second citadel update (avg / worst ms).
//  5. A gunshot outside the east wall: the Kestrel lifts off the tower pad, circles the spot, lands back on the pad.
// With a phase name it stops when that phase is on show (camera on it) for a shot.
enum BaseTests {
    static var failures: [String] = []
    static var results: [String] = []
    static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        let d = detail()
        let line = "basetest \(ok ? "ok  " : "FAIL") \(name)\(d.isEmpty ? "" : ": " + d)"
        print(line)
        results.append(line)
        if !ok { failures.append(name) }
    }

    static func run(game g: Game, world w: World, phase: String) -> Bool {
        failures = []; results = []
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let sc = w.gen.structures,
              let s = sc.nearest("military_base", x: Int(g.player.pos.x), z: Int(g.player.pos.z), maxRegions: 2) else {
            check(false, "a citadel nearby"); return false
        }
        let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2, y0 = s.min.y + 20
        let centre = V3(Float(cx) + 0.5, Float(y0 + 5), Float(cz) + 0.5)
        _ = w.loadSync(center: centre, radius: 7)
        // The garrison as the game spawns it (persistent, officers at some vanguard posts).
        for (name, p) in w.pendingMobs { if let k = MobKind.named(name) { g.mobs.mobs.append(Mob(Soldier.garrison(k, at: p), at: p)) } }
        w.pendingMobs.removeAll()
        for m in g.mobs.mobs where m.kind.steelhold { m.persistent = true }
        g.survival = false; g.paused = false; g.menu = nil  // the soldiers can't target the observer
        g.player.flying = true
        w.ships.encounters = false                           // no stationed frigate firing into the scenes
        let b = g.bases
        let watchPos = centre + V3(0, 60, 0)
        var pinAt = watchPos                                 // where the observer is held (a scene can move it)
        func pin() { g.player.pos = pinAt; g.player.vel = .zero; if g.survival { g.health = max(g.health, 16) } }
        pin()
        // Let the citadel be found (once-a-second tick).
        var t: Float = 0
        func sim(_ secs: Float, until: () -> Bool) -> Float? {
            var e: Float = 0
            while e < secs {
                g.tick(0.05); pin(); e += 0.05; t += 0.05
                if until() { return e }
            }
            return nil
        }
        _ = sim(3) { !b.records.isEmpty }
        let key = "citadel:\(cx),\(cz)"
        check(b.records[key] != nil, "the citadel is watched", "\(b.records.keys.sorted())")
        guard b.records[key] != nil else { return false }
        let rec = { b.records[key]! }
        func look(at p: V3, from: V3) {
            g.player.pos = from
            let d = p - (from + V3(0, 1.62, 0))
            g.player.yaw = atan2f(-d.x, -d.z)
            g.player.pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
        }

        let gate = rec().gate
        let shotOnly = phase.hasSuffix("shot")
        let name = shotOnly ? String(phase.dropLast(4)) : phase
        func want(_ n: String) -> Bool { name == "all" || name == n }
        var phaseT0 = CFAbsoluteTimeGetCurrent(), simT0 = t
        func lap(_ n: String) {
            let real = CFAbsoluteTimeGetCurrent() - phaseT0, game = t - simT0
            print(String(format: "basetest phase %@: %.0f s of game in %.1f s (%.2f ms a tick)", n, game, real, game > 0 ? real * 1000 / Double(game / 0.05) : 0))
            phaseT0 = CFAbsoluteTimeGetCurrent(); simT0 = t
        }

        // 1. Gunshot outside: patrol out, search, back.
        if want("patrol") {
            let shotX = gate.x + 6, shotZ = gate.z + 40
            let shot = V3(shotX, g.standY(shotX, shotZ, from: gate.y + 10), shotZ)
            g.baseNoise(at: shot, kind: .gunshot)
            let formed = sim(4) { rec().patrol != nil && b.patrols[key] != nil }
            check(formed != nil, "a gunshot 40 blocks out sends a patrol", "alert \(rec().alert.name)")
            let team = b.patrols[key] ?? []
            check(team.first?.kind == .soldierOfficer && team.count >= 3, "the patrol is an officer and soldiers", team.map { $0.kind.key }.joined(separator: " "))
            if shotOnly {
                // On the march, a few seconds out of the gate: seen from the side, a little above, the citadel behind.
                _ = sim(60) { (rec().patrol?.phase ?? 0) >= 1 && (rec().patrol?.t ?? 0) > 7 }
                let team = b.patrols[key] ?? []
                let lead = team.first?.pos ?? gate
                let mid = team.isEmpty ? lead : team.reduce(V3(0, 0, 0)) { $0 + $1.pos } / Float(team.count)
                let dir = simd_normalize(V3(shot.x - lead.x, 0, shot.z - lead.z) + V3(1e-3, 0, 0))
                let side = V3(-dir.z, 0, dir.x)
                // A spot with a clear line to the patrol: either side, rising (run 634's camera stood in a tree crown
                // beside the road and framed only leaves).
                let target = mid + V3(0, 1.2, 0)
                func clear(_ from: V3) -> Bool {
                    let d = target - from
                    let n = Int(simd_length(d) * 2)
                    for i in 0...n {
                        let q = from + d * (Float(i) / Float(max(1, n)))
                        if simd_length(q - target) < 1.5 { break }
                        if Blocks.collide[Int(g.world.block(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z))))] { return false }
                    }
                    return true
                }
                var from = mid + side * 9 + dir * 6 + V3(0, 3.5, 0)
                search: for up in stride(from: Float(3.5), through: 15.5, by: 3) {
                    for sd in [Float(1), -1] {
                        let c0: V3 = mid + side * (9 * sd)
                        let c: V3 = c0 + dir * 6 + V3(0, up, 0)
                        if clear(c + V3(0, 1.62, 0)) { from = c; break search }
                    }
                }
                look(at: target, from: from)
                return finish(g, b, t0)
            }
            let reach = sim(150) { (b.patrols[key] ?? []).contains { simd_length(V2($0.pos.x - shot.x, $0.pos.z - shot.z)) < 6 } }
            check(reach != nil, "the patrol reaches the spot", String(format: "within %.0f s", reach ?? -1))
            if shotOnly {
                let lead = (b.patrols[key] ?? team).first?.pos ?? shot
                look(at: lead + V3(0, 1, 0), from: lead + V3(7, 4, 9))
                return finish(g, b, t0)
            }
            let back = sim(240) { rec().patrol == nil }
            check(back != nil, "the patrol returns", String(format: "after %.0f s", back ?? -1))
            if back == nil {
                for m in b.patrols[key] ?? [] {
                    let post = b.posts[ObjectIdentifier(m)] ?? rec().gate
                    print(String(format: "basetest log: straggler %@ at %.0f,%.0f,%.0f post %.0f,%.0f,%.0f order %@", m.kind.key, m.pos.x, m.pos.y, m.pos.z,
                                 post.x, post.y, post.z, m.soldierBrain.order.map { String(format: "%.0f,%.0f,%.0f", $0.x, $0.y, $0.z) } ?? "none"))
                }
            }
            let home = team.filter { $0.health > 0 }
            let strays = home.filter { m in offPost(m) > 6 }
            check(strays.isEmpty, "patrol members back at their posts", "\(strays.count) of \(home.count) away")
            lap("patrol")
        }

        // 2. A blast far outside: the crawler drives out, holds, comes back (a foot patrol goes too).
        if want("crawler") {
            let far = V3(gate.x + 8, g.standY(gate.x + 8, gate.z + 48, from: gate.y + 10), gate.z + 48)
            Explosion.explode(at: far + V3(0, 0.5, 0), power: 2, game: g)
            let crawler = { w.ships.capitals.first { $0.role == "crawler" && $0.faction == Faction.steelhold.rawValue } }
            let rolled = sim(40) { crawler() != nil }
            check(rolled != nil, "a distant blast sends the crawler", rec().crawlerGoal == nil ? "no crawler patrol" : "phase \(rec().crawlerPhase)")
            let there = sim(200) { rec().crawlerPhase >= 2 || rec().crawlerGoal == nil }
            check(there != nil && rec().crawlerGoal != nil, "the crawler reaches the blast", "phase \(rec().crawlerPhase), \(crawler().map { Int(simd_length(V2($0.pos.x - far.x, $0.pos.z - far.z))) } ?? -1) blocks off")
            if shotOnly {
                let c = crawler()?.pos ?? far
                look(at: c, from: c + V3(-30, 14, 30))
                return finish(g, b, t0)
            }
            let parked = sim(300) { rec().crawlerGoal == nil }
            let pool = rec().motorPool
            check(parked != nil && crawler() == nil, "the crawler comes back in", String(format: "after %.0f s; %@", parked ?? -1,
                  crawler().map { c in String(format: "%.0f blocks from the motor pool, target %@", simd_length(V2(c.pos.x - pool.x, c.pos.z - pool.z)),
                                              w.ships.capState[c.id]?.target.map { "\($0.point)" } ?? "none") } ?? "gone"))
            lap("crawler")
        }

        // 3. A blast inside the plaza: lockdown, turret crews, dropships.
        if want("lockdown") {
            // Soldiers on foot in and round the plaza (the Kestrel's seated crew and anyone aboard don't count).
            let plaza = rec().plaza
            func onFoot() -> Int {
                g.mobs.mobs.filter { $0.faction == Faction.steelhold.rawValue && $0.health > 0 && $0.station == .none && $0.deck == nil
                    && simd_length(V2($0.pos.x - plaza.x, $0.pos.z - plaza.z)) < 45 }.count
            }
            let soldiersBefore = onFoot()
            Explosion.explode(at: rec().plaza + V3(9, 0.5, -6), power: 2.5, game: g)
            let locked = sim(3) { rec().alert == .lockdown }
            check(locked != nil, "a blast inside locks the citadel down")
            let crewed = sim(60) { g.mobs.mobs.contains { $0.brain?.station == .gunner && $0.health > 0 } }
            check(crewed != nil, "crews man the turrets", String(format: "after %.0f s", crewed ?? -1))
            let flying = sim(20) { w.ships.capitals.contains { $0.role == "dropship" && $0.faction == Faction.steelhold.rawValue } }
            check(flying != nil, "a Capital dropship is called")
            // The troops the dropships put down (CapitalState.troops), standing on the ground.
            func landedTroops() -> Int {
                w.ships.capitals.filter { $0.role == "dropship" }.reduce(0) { n, d in
                    n + (w.ships.capState[d.id]?.troops.filter { $0.health > 0 && $0.deck == nil && $0.onGround }.count ?? 0)
                }
            }
            // Followed through its flight: the last state seen, every soldier it deployed (it may leave before the end).
            var lastSeen = "never seen", deployed: [Mob] = []
            func track() {
                for d in w.ships.capitals where d.role == "dropship" {
                    guard let st = w.ships.capState[d.id] else { continue }
                    for m in st.troops where !deployed.contains(where: { $0 === m }) { deployed.append(m) }
                    lastSeen = String(format: "t %.0f: phase %d (%.0f s), %.0f from the drop point, keel %+.0f over the plaza, %d left, %d deployed%@",
                                      t, st.phase, st.phaseT, simd_length(V2(d.pos.x - st.dropPoint.x, d.pos.z - st.dropPoint.z)),
                                      d.worldMin.y - plaza.y, st.troopsLeft, st.troops.count, d.wrecked ? ", wrecked" : "")
                }
            }
            let landed = sim(120) { track(); return deployed.filter { $0.health > 0 && $0.deck == nil && $0.onGround }.count >= 3 }
            _ = soldiersBefore
            print("basetest log: dropship last seen \(lastSeen); deployed \(deployed.count): " + deployed.map { m in
                String(format: "%@ hp %.0f%@ at %.0f %.0f %.0f", m.kind.key, Float(m.health), m.onGround ? "" : " airborne", m.pos.x, m.pos.y, m.pos.z) }.joined(separator: ", "))
            let ships = w.ships.capitals.filter { $0.role == "dropship" }.map { d -> String in
                guard let st = w.ships.capState[d.id] else { return "no state" }
                let drop = st.dropPoint
                return String(format: "phase %d (%.0f s), %.0f blocks from the drop point, %.0f up, %d troops left, %d deployed%@", st.phase, st.phaseT,
                              simd_length(V2(d.pos.x - drop.x, d.pos.z - drop.z)), d.worldMin.y - plaza.y, st.troopsLeft, st.troops.count, d.wrecked ? ", wrecked" : "")
            }
            check(landed != nil, "dropship reinforcements land", String(format: "after %.0f s, %d troops down; dropships: %@", landed ?? -1, landedTroops(),
                                                                             ships.isEmpty ? "none" : ships.joined(separator: "; ")))
            if shotOnly {
                let ds = w.ships.capitals.first { $0.role == "dropship" }?.pos ?? rec().plaza
                look(at: ds, from: rec().plaza + V3(-14, 3, 16))
                return finish(g, b, t0)
            }
            lap("lockdown")
        }

        // 4. Blast a hall wall; a wreck block in the crater; rebuilt once calm, within a day (the stand-down is
        // sped up 4x here: its timing is not what's under test).
        if want("rebuild") {
            BaseWatch.calmScale = 0.25
            defer { BaseWatch.calmScale = 1 }
            let P1 = y0 + 4
            let stone = Blocks.has("capital_stone") ? Blocks.id("capital_stone") : STONE
            var wall = IVec3(cx + 6, P1 + 3, cz + 22)
            for dz in 10...40 where w.block(cx, P1 + 2, cz + dz) == stone && w.block(cx, P1 + 2, cz + dz + 1) == AIR {
                wall = IVec3(cx, P1 + 3, cz + dz); break
            }
            var before: [IVec3: BlockID] = [:]
            for dz in -4...4 { for dy in -4...4 { for dx in -4...4 { let p = IVec3(wall.x + dx, wall.y + dy, wall.z + dz); before[p] = w.block(p.x, p.y, p.z) } } }
            // Power 5: Capital stone (resistance 9) takes 2.8 of a ray's strength per block.
            Explosion.explode(at: V3(Float(wall.x) + 0.5, Float(wall.y) + 0.5, Float(wall.z) + 1.2), power: 5, game: g)
            let holes = before.filter { $0.value != AIR && w.block($0.key.x, $0.key.y, $0.key.z) == AIR }.map { $0.key }
            check(holes.count >= 8, "the blast opened the wall", "\(holes.count) blocks gone")
            // A wreck block left in the crater (another stream's wrecks): the rebuild must not overwrite it.
            let wreck = holes.max { $0.y < $1.y } ?? wall
            let wreckID = Blocks.has("iron_block") ? Blocks.id("iron_block") : COBBLE
            w.setBlock(wreck.x, wreck.y, wreck.z, wreckID)
            func restored() -> Int { holes.filter { $0 != wreck && w.block($0.x, $0.y, $0.z) == before[$0] }.count }
            let wallView = { look(at: V3(Float(wall.x), Float(wall.y), Float(wall.z)), from: V3(Float(wall.x) + 5, Float(P1) + 1, Float(wall.z) + 12)) }
            if shotOnly {
                _ = sim(600) { restored() > holes.count / 3 }
                wallView()
                return finish(g, b, t0)
            }
            let done = sim(Float(DAY_LENGTH)) { restored() == holes.count - 1 }
            check(done != nil, "the wall is rebuilt within a day", "\(restored()) of \(holes.count - 1) after \(Int(done ?? Float(DAY_LENGTH))) s")
            check(w.block(wreck.x, wreck.y, wreck.z) == wreckID, "the wreck block in the crater is left alone")
            check(rec().damage.isEmpty, "no damage left on the record")
            wallView()
            lap("rebuild")
        }

        // 5. A gunshot just outside the east wall: alert; the Kestrel lifts off the tower pad, flies out, circles
        // the spot, flies back and lands on the pad, and is stowed.
        if want("air") {
            let ex = Float(cx + CapitalBase.A + 6), ez = Float(cz)
            let shot = V3(ex, g.standY(ex, ez, from: Float(y0 + 30)), ez)
            g.baseNoise(at: shot, kind: .gunshot)
            let kestrel = { () -> Ship? in rec().airShip.flatMap { id in w.ships.list.first { $0.id == id } } }
            let up = sim(6) { kestrel() != nil }
            let pad = rec().pad
            check(up != nil, "a gunshot near the walls sends the Kestrel up", "alert \(rec().alert.name), air \(rec().air != nil)")
            if let k = kestrel() {
                check(simd_length(V2(k.pos.x - pad.x, k.pos.z - pad.z)) < 3, "it starts on the tower's landing pad",
                      String(format: "%.1f blocks from the pad centre", simd_length(V2(k.pos.x - pad.x, k.pos.z - pad.z))))
            }
            let over = sim(120) { (rec().airPhase ?? 0) >= 3 || rec().air == nil }
            check(over != nil && rec().air != nil, "it flies out over the noise", String(format: "after %.0f s, phase %d", over ?? -1, rec().airPhase ?? -1))
            if shotOnly {
                _ = sim(6) { false }
                // From beyond the Kestrel, so the citadel's tower stands behind it.
                let p = kestrel()?.pos ?? shot
                let away = simd_normalize(V3(p.x - rec().centre.x, 0, p.z - rec().centre.z) + V3(1e-3, 0, 0))
                look(at: p, from: p + away * 26 + V3(0, 3, 0))
                return finish(g, b, t0)
            }
            // Door gunners: a survival player standing at the noise while it circles draws fire from the cabin.
            if let k = kestrel() {
                let gunners = FlightCrew.seats.filter { $0.ship === k }.compactMap { $0.mob }.filter { $0.station == .passenger }
                let mags = gunners.map { $0.soldierBrain.mag }
                g.survival = true
                pinAt = shot + V3(0, 0.1, 0)
                let fired = sim(20) { zip(gunners, mags).contains { m, n in m.soldierBrain.mag < n || m.soldierBrain.reload > 0 } }
                g.survival = false
                pinAt = watchPos
                check(fired != nil, "its door gunners fire on a player below", String(format: "%d gunners, after %.0f s", gunners.count, fired ?? -1))
            }
            let back = sim(150) { (rec().airPhase ?? 0) >= 5 || rec().air == nil }
            check(back != nil && rec().air != nil, "it circles and flies back over the pad", String(format: "after %.0f s, phase %d", back ?? -1, rec().airPhase ?? -1))
            let down = sim(90) { (rec().airPhase ?? 0) >= 6 || rec().air == nil }
            if let k = kestrel() {
                let off = simd_length(V2(k.pos.x - pad.x, k.pos.z - pad.z)), up = k.dirToWorld(V3(0, 1, 0)).y
                check(down != nil && off < 2.5 && up > 0.95 && k.worldMin.y > pad.y - 0.5, "it lands on the pad",
                      String(format: "%.1f off the centre, upright %.2f, skids %+.1f", off, up, k.worldMin.y - pad.y))
            } else {
                check(false, "it lands on the pad", "no Kestrel (\(b.log.last ?? ""))")
            }
            let stowed = sim(20) { rec().air == nil }
            check(stowed != nil && kestrel() == nil && !b.log.contains { $0.contains("kestrel lost") }, "it is stowed with its crew aboard",
                  b.log.filter { $0.contains("kestrel") }.joined(separator: "; "))
            lap("air")
        }

        // Saved state round trip.
        let saved = g.saveExtra()
        let data = saved["bases"]?.data(using: .utf8)
        let recs = data.flatMap { try? JSONDecoder().decode([BaseRecord].self, from: $0) } ?? []
        check(recs.contains { $0.key == key }, "the citadel's state is saved", "\(recs.count) records")
        return finish(g, b, t0)
    }

    // --basetest reload: a real save mid-patrol and mid-air-patrol (a temporary save folder, as the playthrough does),
    // loaded into a fresh game: the citadel's alert, patrol and Kestrel phase come back, the airborne Kestrel is there
    // with its pilot back at the controls, and both finish (patrol back at its posts, Kestrel stowed on its pad).
    static func reloadTest(device: MTLDevice) -> Bool {
        failures = []; results = []
        let t0 = CFAbsoluteTimeGetCurrent()
        let seed: UInt64 = 12345
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("blocksmith-basereload", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        let save = SaveManager(dir: dir)
        let w = World(seed: seed, device: device, save: save, dim: .overworld)
        w.renderDistance = 8
        let g = Game(world: w, save: save, persistent: true)
        guard let sc = w.gen.structures, let st = sc.nearest("military_base", x: 0, z: 0, maxRegions: 8) else {
            check(false, "a citadel nearby"); return false
        }
        let cx = (st.min.x + st.max.x) / 2, cz = (st.min.z + st.max.z) / 2, y0 = st.min.y + 20
        let centre = V3(Float(cx) + 0.5, Float(y0 + 5), Float(cz) + 0.5)
        let key = "citadel:\(cx),\(cz)"
        func setUp(_ g: Game) {
            g.survival = false; g.paused = false; g.menu = nil
            g.player.flying = true
            g.world.ships.encounters = false
            g.player.pos = centre + V3(0, 60, 0)
        }
        setUp(g)
        _ = w.loadSync(center: centre, radius: 7)
        for (name, p) in w.pendingMobs { if let k = MobKind.named(name) { g.mobs.mobs.append(Mob(Soldier.garrison(k, at: p), at: p)) } }
        w.pendingMobs.removeAll()
        for m in g.mobs.mobs where m.kind.steelhold { m.persistent = true }
        func sim(_ g: Game, _ secs: Float, until: () -> Bool) -> Float? {
            var e: Float = 0
            while e < secs {
                g.tick(0.05); g.player.pos = centre + V3(0, 60, 0); g.player.vel = .zero; e += 0.05
                if until() { return e }
            }
            return nil
        }
        _ = sim(g, 3) { g.bases.records[key] != nil }
        guard g.bases.records[key] != nil else { check(false, "the citadel is watched"); return finish(g, g.bases, t0) }
        // A gunshot just outside the east wall: alert, a patrol out, the Kestrel up.
        let ex = Float(cx + CapitalBase.A + 6), ez = Float(cz)
        g.baseNoise(at: V3(ex, g.standY(ex, ez, from: Float(y0 + 30)), ez), kind: .gunshot)
        let airborne = sim(g, 60) { (g.bases.records[key]?.airPhase ?? 0) >= 2 && (g.bases.records[key]?.patrol?.phase ?? 0) >= 1 }
        let before = g.bases.records[key]!
        check(airborne != nil, "before the save: a patrol out and the Kestrel in the air",
              "patrol phase \(before.patrol?.phase ?? -1), air phase \(before.airPhase ?? -1)")
        g.saveNow()
        SaveIO.flush()                                       // the chunk writes are on disk before the reload

        // A fresh game from the save (a new session: no crews buckled in from the old one).
        FlightCrew.seats.removeAll()
        guard let meta = save.loadMeta() else { check(false, "world.json written"); return finish(g, g.bases, t0) }
        let w2 = World(seed: seed, device: device, save: save, dim: .overworld)
        w2.renderDistance = 8
        let g2 = Game(world: w2, save: save, persistent: false)
        g2.apply(meta)
        setUp(g2)
        _ = w2.loadSync(center: centre, radius: 7)
        let b2 = g2.bases
        let r2 = b2.records[key]
        check(r2?.alert == before.alert && r2?.patrol?.phase == before.patrol?.phase && r2?.airPhase == before.airPhase,
              "the citadel's alert, patrol and Kestrel phase come back",
              "alert \(r2?.alert.name ?? "none"), patrol \(r2?.patrol?.phase ?? -1), air \(r2?.airPhase ?? -1)")
        let kestrel = { w2.ships.list.first { $0.id == before.airShip && $0.role == "kestrel" } }
        check(kestrel() != nil, "the airborne Kestrel is in the loaded world", "ship \(before.airShip ?? -1), \(w2.ships.list.count) ships")
        let seated = sim(g2, 5) { FlightCrew.seats.contains { $0.ship != nil && $0.ship === kestrel() && $0.mob?.station == .seated } }
        check(seated != nil, "its pilot is back at the controls", "\(FlightCrew.seats.count) seats")
        let done = sim(g2, 300) { b2.records[key]?.patrol == nil && b2.records[key]?.air == nil }
        let log = b2.log.joined(separator: "; ")
        check(done != nil && !log.contains("kestrel lost") && log.contains("kestrel stowed"), "after the reload the patrol comes back and the Kestrel lands and is stowed",
              String(format: "after %.0f s: ", done ?? -1) + log)
        return finish(g2, b2, t0)
    }

    static func offPost(_ m: Mob) -> Float {
        guard let h = m.home else { return 0 }
        return simd_length(V2(m.pos.x - h.x, m.pos.z - h.z))
    }

    static func finish(_ g: Game, _ b: BaseWatch, _ t0: Double) -> Bool {
        for line in b.log { print("basetest log: \(line)") }
        let avg = b.ticks > 0 ? b.tickMs / Double(b.ticks) : 0
        print(String(format: "basetest: citadel update %.3f ms avg, %.3f ms worst over %d updates", avg, b.tickWorstMs, b.ticks))
        check(avg < 1.0, "citadel update stays cheap", String(format: "%.3f ms avg", avg))
        for r in results { print(r) }                  // again at the end, where the CI log tail shows them
        print(String(format: "basetest: %ld failed (%.1f s)%@", failures.count, CFAbsoluteTimeGetCurrent() - t0,
                     failures.isEmpty ? "" : " -> " + failures.joined(separator: ", ")))
        g.player.flying = true
        return failures.isEmpty
    }
}
