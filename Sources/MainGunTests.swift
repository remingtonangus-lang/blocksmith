import Foundation
import simd

// The Tidebreaker, the Meridian frigate's spinal gun (MainGun.swift): run by questcheck (the Quest build's host check,
// with stereo renders on lavapipe) and the Mac harness (--questbugs --only maingun).
//   1. The barrel: 63 blocks between the booms, a clear bore, glowing coil rings, the muzzle at the bow.
//   2. The shockwave: zombies at 8, 20 and 35 blocks are struck and thrown outward (the two inner ones killed), one
//      at 60 is untouched, the firing frigate's own deck is spared.
//   3. A shot from the helm through Game.tick at 72 Hz: the charge (shake, coil thumps in the controllers getting
//      stronger and quicker, light on the barrel), the slug, recoil, the 22 s reload, the impact (a crater of
//      thousands of blocks within the cap, the shockwave) and the frame time for 4 s after it (MainGunPerf).
// `render(name, yaw, pitch)`: a stereo frame from the player's eye (questcheck --render), or nil.
enum MainGunTests {
    static func run(_ g: Game, _ check: (Bool, String) -> Void, render: ((String, Float, Float) -> Void)? = nil) {
        guard g.dim.dim == .overworld else { check(false, "maingun: needs the overworld"); return }
        let w = g.world
        let home = g.player.pos
        let wasFlying = g.player.flying, wasTime = g.time, wasPaused = g.paused
        let pm = PadManager.shared
        let wasSim = pm.simulated
        pm.simulated = PadSnapshot()                            // rumble requests are logged (rumbleLog)
        defer {
            g.player.pos = home; g.player.vel = .zero; g.player.flying = wasFlying; g.time = wasTime; g.paused = wasPaused
            // The shots streamed the world around the frigate, far from the start: load the start again for the
            // checks that run after this one (they stand mobs on the ground around the player).
            _ = w.loadSync(center: home, radius: 8)
            pm.simulated = wasSim
            g.shake = 0
        }
        g.player.flying = true
        g.time = 0.3 * DAY_LENGTH
        // The shot runs through Game.tick, which does nothing while paused, and a fresh Game starts paused (the Mac
        // harness never unpaused it: the live shot "charged for 5.56 s" and never fired; done audit 25b6, G1).
        g.paused = false

        // The frigate, about 300 blocks east of the start, heading north (-z), placed where the ground the helm shot
        // lands on (100 to 180 blocks ahead, within the streamed world around the player) is dry land near the
        // highest ground under the hull, which sets the frigate's cruise height (spawnCapital), so the crater is dug
        // in earth rather than under the sea and the shot lands about 130 blocks out.
        let open: Set<Biome> = [.plains, .sunflowerPlains, .meadow, .savanna, .snowyPlains]
        func dry(_ x: Int, _ z: Int) -> Bool {
            var top = SEA
            for k in -4...4 { for j in -1...1 { top = max(top, w.gen.column(x + k * 60, z + j * 40).height) } }
            // The landing strip and the crater's reach either side: open country well above the sea (no swamp pools,
            // rivers or jungle crowns for the slug to burst in).
            return stride(from: 100, through: 180, by: 20).allSatisfy { d in
                [(0, 0), (-16, 0), (16, 0), (0, -16), (0, 16)].allSatisfy { o in
                    let c = w.gen.column(x + o.0, z - d + o.1)
                    return c.height > SEA + 3 && c.height >= top - 10 && open.contains(c.biome)
                }
            }
        }
        // (From the world spawn, not wherever earlier checks left the player: the full questcheck and the slice then
        // test the same site; the walk check ahead of it ends a different distance out from build to build.)
        let origin = (w.gen as? WorldGen).map { WorldRules.spawnCentre($0) } ?? V2(home.x, home.z)
        var fx = Int(origin.x) + 300, fz = Int(origin.y)
        search: for r in 0..<20 {
            for k in -r...r {
                for (dx, dz) in [(k, -r), (k, r), (-r, k), (r, k)] where dry(fx + dx * 96, fz + dz * 96) {
                    fx += dx * 96; fz += dz * 96
                    break search
                }
            }
        }
        let n0 = w.ships.list.count
        print("maingun: the frigate at \(fx),\(fz) (spawn \(Int(origin.x)),\(Int(origin.y)); the player was at \(Int(home.x)),\(Int(home.z)))")
        w.ships.spawnCapital("capfrigate", home: IVec3(fx, 0, fz), yaw: 0, region: nil, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "capfrigate" }), let st = w.ships.capState[s.id] else {
            check(false, "maingun: the Meridian frigate spawns"); return
        }
        defer { w.ships.remove(s); w.ships.capState.removeValue(forKey: s.id); w.ships.shockwaves.removeAll() }

        // 1. The barrel.
        let ox = 13                                            // grid x of the centre line (HullBuilder ox)
        var tube = 0, bore = 0, coils = 0
        let thr = Blocks.has("frigate_thruster") ? Blocks.id("frigate_thruster") : AIR
        for z in 1...63 {
            if s.grid.get(ox, 9, z) == AIR { bore += 1 }
            if s.grid.get(ox + 2, 9, z) != AIR && s.grid.get(ox - 2, 9, z) != AIR && s.grid.get(ox, 11, z) != AIR && s.grid.get(ox, 7, z) != AIR { tube += 1 }
            if s.grid.get(ox + 3, 9, z) == thr { coils += 1 }
        }
        check(tube == 63 && bore == 63 && coils >= 9 && st.mainGunLength == 115 && st.mainGunMuzzle.z < 1,
              "maingun: a 63-block barrel between the booms (tube \(tube), clear bore \(bore), \(coils) glowing coil rings), muzzle at the bow (z \(st.mainGunMuzzle.z)), \(Int(st.mainGunLength)) blocks to the breech")
        // The world around the camera meshed and the ships' meshes built (released far away, rebuilt on the workers).
        func settle() {
            _ = w.loadSync(center: g.player.pos, radius: 4)
            w.ships.update(0, game: g)
            for sh in w.ships.list {
                var n = 0
                while sh.mesh.busy && n < 4000 { usleep(1000); sh.mesh.apply(device: w.device); n += 1 }
                sh.mesh.apply(device: w.device)
            }
        }
        if let render {
            // Side-on from 70 blocks off the port bow, level with the barrel.
            let mw = s.toWorld(st.mainGunMuzzle)
            g.player.pos = mw + V3(-70, -1.6, 40)
            settle()
            let to = mw - s.dirToWorld(st.mainGunDir) * 31 - g.player.eye       // the barrel's middle
            render("maingun_frigate", atan2f(-to.x, -to.z), atan2f(to.y, simd_length(V2(to.x, to.z))))   // forward = (-sin yaw, -cos yaw)
            // From ahead and below the bow, where the barrel shows between the booms.
            g.player.pos = mw + V3(-18, -24, -45)
            settle()
            let to2 = mw - s.dirToWorld(st.mainGunDir) * 20 - g.player.eye
            render("maingun_barrel", atan2f(-to2.x, -to2.z), atan2f(to2.y, simd_length(V2(to2.x, to2.z))))
        }

        // 1b. The drive's glow (G8): from 300 blocks astern at night, a sprite over each nozzle big enough to read.
        do {
            let wasT = g.time, at = g.player.pos
            g.time = 0.75 * DAY_LENGTH
            let aft = s.dirToWorld(V3(0, 0, 1))
            g.player.pos = s.toWorld(V3(13.5, 15, Float(Capital.mfLength))) + aft * 300
            g.particles.list.removeAll()                       // (room under the particle cap)
            let n0 = g.particles.list.count
            w.ships.driveGlow(s, st, w.ships.boundsDistance(s, g.player.pos), 1.0 / 72, g)
            let glows = g.particles.list.dropFirst(n0).filter { $0.glow && $0.size > 6 }
            // Angular size of the big nozzles' sprites from 300 blocks: at least ~2.5 degrees (a dot is under 1).
            let deg = (glows.map { $0.size }.max() ?? 0) / 300 * 180 / .pi
            check(glows.count >= 4 && deg > 2.5, String(format: "maingun: the frigate's drive glows from 300 blocks astern at night (%d nozzle sprites, %.1f degrees across)", glows.count, deg))
            if let render {
                settle()
                let to = s.toWorld(V3(13.5, 15, Float(Capital.mfLength))) - g.player.eye
                render("maingun_stern_night", atan2f(-to.x, -to.z), atan2f(to.y, simd_length(V2(to.x, to.z))))
            }
            g.time = wasT; g.player.pos = at
        }

        // 2. The shockwave on its own, on open ground 150 blocks west of the start.
        do {
            let cx = Int(home.x) - 150, cz = Int(home.z)
            _ = w.loadSync(center: V3(Float(cx), 80, Float(cz)), radius: 5)
            let top = w.topY(cx, cz)
            let c = V3(Float(cx) + 0.5, Float(top) + 1, Float(cz) + 0.5)
            var zs: [(Mob, Float)] = []
            for d: Float in [8, 20, 35, 60] {
                let x = Int(c.x + d), z = cz
                let m = Mob(.zombie, at: V3(Float(x) + 0.5, Float(w.topY(x, z)) + 1, Float(z) + 0.5))
                m.equip = nil
                m.persistent = true
                g.mobs.mobs.append(m)
                zs.append((m, d))
            }
            // A crewman standing on the frigate's deck (marked by `deck`), 10 blocks out and level with the blast, is spared.
            let crew = Mob(.soldierTrooper, at: c + V3(10, 2, 0))
            crew.deck = s
            g.mobs.mobs.append(crew)
            let crewHP = crew.health
            defer { g.mobs.mobs.removeAll { m in zs.contains { $0.0 === m } || m === crew } }
            let hp0 = zs.map { $0.0.health }
            w.ships.shockwaves.append(Shockwave(center: c, owner: s.id))
            var thrown = [Float](repeating: 0, count: zs.count)
            for _ in 0..<80 {                                        // 1.1 s at 72 Hz: the front passes 60 blocks
                w.ships.updateShockwaves(1.0 / 72, game: g)
                for (i, (m, _)) in zs.enumerated() { thrown[i] = max(thrown[i], m.vel.x) }
            }
            w.ships.shockwaves.removeAll()
            let hp = zs.map { $0.0.health }
            check(hp[0] <= 0 && hp[1] <= 0 && hp[2] < hp0[2] && hp[2] > 0 && hp[3] == hp0[3] && thrown[2] > 4 && thrown[3] == 0 && crew.health == crewHP,
                  "maingun: the shockwave flattens zombies at 8 and 20 blocks, throws one at 35 (\(hp0[2]) -> \(hp[2]) hp, \(String(format: "%.1f", thrown[2])) b/s out), spares one at 60 and the frigate's own deck")
        }

        // 3. A shot from the helm, through the game loop.
        s.captured = true
        st.mainGunCD = 0                                        // (a new frigate's first shot waits 8 s)
        var mw0 = s.toWorld(st.mainGunMuzzle)
        var md = s.dirToWorld(st.mainGunDir)
        // The frigate holds still for the shot (the commandeered helm with nobody steering holds station): where the
        // slug lands no longer follows its drift while chunks stream in (known-test-issues: a busy machine moved the
        // landing onto shallow water, a 1425-block crater).
        s.vel = .zero
        s.angVel = .zero
        // P325: the gun is fixed along the keel, so the hull is pointed (pitched down) to lay it.
        // The steepest pitch whose landing (the helm's own prediction over the loaded world) is dry ground: a crater dug in
        // a pond or a swamp is mostly water and says nothing about the gun.
        g.player.pos = mw0 + V3(-50, 0, -10)
        g.player.vel = .zero
        _ = w.loadSync(center: g.player.pos, radius: 3)
        func wetTops(_ c: V3) -> Int {
            var wet = 0
            for dz in stride(from: -14, through: 14, by: 2) { for dx in stride(from: -14, through: 14, by: 2) where dx * dx + dz * dz <= 196 {
                let x = Int(floor(c.x)) + dx, z = Int(floor(c.z)) + dz
                var y = CH - 1
                while y > 0 && w.isAir(x, y, z) { y -= 1 }
                if Blocks.isLiquid(w.builtBlock(x, y, z)) { wet += 1 }
            } }
            return wet
        }
        var pitch: Float = .nan
        for k in 0..<10 {
            let pk = -Capital.maxPitch + Float(k) * 0.03
            w.ships.pointHull(s, pitch: pk)
            mw0 = s.toWorld(st.mainGunMuzzle)
            let ray = s.dirToWorld(st.mainGunDir)
            var t: Float = 0, guess = mw0
            while t < 600 {
                t += 2
                let p = mw0 + ray * t
                if p.y <= Float(w.gen.column(Int(floor(p.x)), Int(floor(p.z))).height) + 1 { guess = p; break }
            }
            _ = w.loadSync(center: guess, radius: 2)
            guard let at = w.ships.mainGunAimPoint(s, st) else { continue }
            _ = w.loadSync(center: at, radius: 2)                   // (the bowl and its rim, round the predicted landing)
            // On the ground itself, not in a tree's crown (a slug that bursts in a jungle canopy digs half a bowl of air).
            let ground = Float(w.gen.column(Int(floor(at.x)), Int(floor(at.z))).height) + 1
            if wetTops(at) == 0 && at.y < ground + 3 { pitch = pk; break }
        }
        // No dry landing at any pitch: say so (firing into water anyway made a small, drowned crater that read as a
        // weak gun; done audit 25b6 verifier).
        guard !pitch.isNaN else {
            check(false, String(format: "maingun: a dry landing ahead of the frigate at %.0f,%.0f (every pitch lands in water or past the world)", mw0.x, mw0.z))
            return
        }
        w.ships.pointHull(s, pitch: pitch)
        mw0 = s.toWorld(st.mainGunMuzzle)
        md = s.dirToWorld(st.mainGunDir)
        let h = simd_normalize(V2(md.x, md.z))
        let dir = md
        // Where the slug will land (the generator's heights along its path), loaded beforehand.
        var land = mw0
        var t: Float = 0
        while t < 600 {
            t += 2
            let p = mw0 + dir * t
            if p.y <= Float(w.gen.column(Int(floor(p.x)), Int(floor(p.z))).height) + 1 { land = p; break }
        }
        // The player watches the charge from 50 blocks off the frigate's bow (near enough to feel it), then from beside
        // the landing once the slug is away (a landing past the streamed world waits as a pending crater, dug only when
        // its ground loads, and the shot can land 160 blocks out).
        g.player.pos = mw0 + V3(-50, 0, -10)
        g.player.vel = .zero
        _ = w.loadSync(center: g.player.pos, radius: 3)
        let side = simd_normalize(V3(-h.y, 0, h.x))
        var watch = land - V3(h.x, 0, h.y) * 40 + side * 45      // (outside the 48-block strike radius)
        watch.y = Float(w.gen.column(Int(watch.x), Int(watch.z)).height) + 12
        _ = w.loadSync(center: land, radius: 4)
        print(String(format: "maingun: aiming %.0f blocks ahead of the muzzle, %.0f from the player", simd_length(land - mw0), simd_length(land - g.player.pos)))
        // The helm's aim marker: where the shot will land, predicted before it is fired, drawn as a ring.
        let ta = CFAbsoluteTimeGetCurrent()
        let predicted = w.ships.mainGunAimPoint(s, st)
        var aimMs = (CFAbsoluteTimeGetCurrent() - ta) * 1000
        // The longest trace: raised all the way, the slug's whole flight over unstreamed country.
        w.ships.pointHull(s, pitch: Capital.maxPitch)
        let tl = CFAbsoluteTimeGetCurrent()
        _ = w.ships.mainGunAimPoint(s, st)
        aimMs = max(aimMs, (CFAbsoluteTimeGetCurrent() - tl) * 1000)
        w.ships.pointHull(s, pitch: pitch)
        g.particles.list.removeAll()                           // (the earlier checks filled the particle cap)
        let parts0 = g.particles.list.count, aims0 = MainGun.aimUpdates
        st.aimTimer = 0
        w.ships.mainGunAimTick(s, st, 1.0 / 72, g)
        let puff = Int(Tex.id("puff"))
        let ring = g.particles.list.dropFirst(parts0).filter { $0.layer == puff && $0.glow }.count
        check(predicted != nil && MainGun.aimUpdates == aims0 + 1 && ring >= 21 && aimMs < 4,
              "maingun: the helm shows where the shot will land (a \(ring)-puff ring \(String(format: "%.0f", predicted.map { simd_length($0 - mw0) } ?? -1)) blocks out, predicted in \(String(format: "%.2f", aimMs)) ms)")
        pm.rumbleLog.removeAll()
        let shells0 = w.ships.shells.filter { $0.kind == 3 }.count
        let started = w.ships.playerMainGun(s, game: g)
        let again = w.ships.playerMainGun(s, game: g)
        var maxShake: Float = 0, flashes = 0, frames = 0
        var shotRendered = false
        // The shot as a sequence of frames (EF5, "the shot recorded as a video-like screenshot sequence"): with
        // --render and BLOCKSMITH_SHOT_SEQUENCE set, twelve stereo frames maingun_seq_NN_<when>.png from the charge to the
        // smoke clearing; tools/shot_sheet.py lays them out as one sheet (docs/qa/tidebreaker_sequence.jpg).
        let seq = ProcessInfo.processInfo.environment["BLOCKSMITH_SHOT_SEQUENCE"] != nil ? render : nil
        var seqN = 0
        func seqFrame(_ when: String, look: V3, from: V3? = nil) {
            guard let seq else { return }
            seqN += 1
            let at = g.player.pos
            if let f = from { g.player.pos = f }
            let to = look - g.player.eye
            seq(String(format: "maingun_seq_%02d_%@", seqN, when), atan2f(-to.x, -to.z), atan2f(to.y, simd_length(V2(to.x, to.z))))
            g.player.pos = at
        }
        var seqCharge = Set<Int>()
        while st.gunCharge >= 0 && frames < 400 {
            let a = CFAbsoluteTimeGetCurrent()
            g.tick(1.0 / 72)
            frames += 1
            let ms = (CFAbsoluteTimeGetCurrent() - a) * 1000
            if ms < 1000.0 / 72 { usleep(useconds_t((1000.0 / 72 - ms) * 1000)) }   // paced like the headset (workers run alongside)
            maxShake = max(maxShake, g.shake)
            flashes = max(flashes, g.flashes.count)
            for (k, f) in [(0, Float(0.1)), (1, 0.55), (2, 0.95)] where !seqCharge.contains(k) && st.gunCharge > MainGun.chargeTime * f {
                seqCharge.insert(k)
                seqFrame("charge-\(Int(f * 100))pct", look: s.toWorld(st.mainGunMuzzle) - md * 30)
            }
            if let render, !shotRendered && st.gunCharge > MainGun.chargeTime * 0.8 {
                shotRendered = true
                let to = s.toWorld(st.mainGunMuzzle) - md * 30 - g.player.eye
                render("maingun_charge", atan2f(-to.x, -to.z), atan2f(to.y, simd_length(V2(to.x, to.z))))
            }
        }
        let thumps = pm.rumbleLog
        let fired = w.ships.shells.filter { $0.kind == 3 }.count == shells0 + 1
        check(started && !again && fired && abs(Float(frames) / 72 - MainGun.chargeTime) < 0.1,
              "maingun: the helm's attack charges the Tidebreaker for \(String(format: "%.2f", Float(frames) / 72)) s, then it fires (a second press while charging does nothing)")
        check(thumps.count >= 6 && (thumps.last ?? 0) > (thumps.first ?? 0) * 1.5 && maxShake > 0.1 && flashes >= 2,
              "maingun: the charge is felt and seen: \(thumps.count) coil thumps in the controllers (\(String(format: "%.2f -> %.2f", thumps.first ?? 0, thumps.last ?? 0))), shake \(String(format: "%.2f", maxShake)), \(flashes) lights on the barrel")
        check((w.ships.mainGunCooldown(s) ?? 0) > MainGun.playerReload - 1 && w.ships.mainGunStatus(s)?.ready == false,
              "maingun: a slow reload (\(String(format: "%.0f", w.ships.mainGunCooldown(s) ?? 0)) s)")
        // The slug's flight and impact; then 4 s of frames timed (Game.tick, which streams the world, as the headset's frame
        // thread runs them) into MainGunPerf.
        var impactFrame = -1
        var tickMs: [Double] = []
        var detail: [String] = []
        let blasts0 = MainGun.impacts
        for i in 0..<(72 * 6) {
            let a = CFAbsoluteTimeGetCurrent()
            let gq = w.gravityQueue.count, fl = w.fluidPending.count, falls = g.falling.count
            g.tick(1.0 / 72)
            let ms = (CFAbsoluteTimeGetCurrent() - a) * 1000
            if impactFrame < 0 && MainGun.impacts > blasts0 { impactFrame = i }
            if i == 1 { seqFrame("fired", look: s.toWorld(st.mainGunMuzzle) + md * 40) }
            if i == 1 { g.player.pos = watch; g.player.vel = .zero; _ = w.loadSync(center: land, radius: 2) }   // (the landing streamed back in)
            if impactFrame < 0, i == 12, let pr = predicted { seqFrame("in-flight", look: pr + V3(0, 4, 0), from: pr + V3(-36, 14, 34)) }
            if impactFrame >= 0, [1, 5, 12, 24, 48, 96, 180].contains(i - impactFrame) {
                seqFrame(String(format: "impact+%.2fs", Float(i - impactFrame) / 72), look: MainGun.lastImpact + V3(0, 6, 0), from: MainGun.lastImpact + V3(-36, 14, 34))
            }
            if impactFrame >= 0 { detail.append(String(format: "tick %.1f [%@] (crater slice %.1f ms, gravity queue %d, fluid %d, falling %d, particles %d)",
                                                        ms, TickProf.summary(), MainGun.craterStepMs, gq, fl, falls, g.particles.list.count)) }
            MainGun.craterStepMs = 0
            if impactFrame < 0 && ms < 1000.0 / 72 { usleep(useconds_t((1000.0 / 72 - ms) * 1000)) }   // the slug's flight, paced too
            if impactFrame >= 0 {
                if ms < 1000.0 / 72 { usleep(useconds_t((1000.0 / 72 - ms) * 1000)) }   // paced like the headset: worker meshing runs between frames
                tickMs.append(ms)
                MainGunPerf.record(frameMs: ms, budget: 1000.0 / 72, clock: g.clock)
                if let render, i == impactFrame + 4 {
                    // From 50 blocks off (the headless check's fog is nearer than the headset's), then back.
                    let at = g.player.pos
                    g.player.pos = MainGun.lastImpact + V3(-36, 14, 34)
                    let to = MainGun.lastImpact + V3(0, 6, 0) - g.player.eye
                    render("maingun_blast", atan2f(-to.x, -to.z), atan2f(to.y, simd_length(V2(to.x, to.z))))
                    g.player.pos = at
                }
                if Double(i - impactFrame) / 72 > MainGunPerf.window + 0.1 { break }
            }
        }
        MainGunPerf.finish(budget: 1000.0 / 72)
        check(w.gravityQueue.count < Game.gravityChecksPerTick * 4,
              "maingun: the crater's support checks drain within the window (\(w.gravityQueue.count) cells left; \(Game.gravityChecksPerTick) a tick)")
        check(impactFrame >= 0 && MainGun.lastCrater > 2000 && MainGun.lastCrater <= MainGun.craterCap,
              "maingun: the slug lands \(String(format: "%.0f", simd_length(MainGun.lastImpact - mw0))) blocks out and blasts a \(MainGun.lastCrater)-block crater (cap \(MainGun.craterCap))")
        let miss = predicted.map { simd_length($0 - MainGun.lastImpact) } ?? 999
        check(impactFrame >= 0 && miss < 6, String(format: "maingun: the slug lands where the helm's marker showed (%.1f blocks off)", miss))
        // The bowl burnt black (blackstone, basalt, glowing magma) and a ring of scorched earth round it.
        do {
            var frames = 0
            while !w.ships.shockwaves.isEmpty && frames < 1500 { w.ships.updateShockwaves(1.0 / 72, game: g); frames += 1 }
            let c = MainGun.lastImpact
            let black: Set<BlockID> = [Blocks.id("blackstone"), Blocks.id("basalt"), Blocks.id("magma_block")]
            var burnt = 0, scorchedRim = 0
            var bowlTops: [String: Int] = [:]
            let R = Int(MainGun.craterRadius * 1.5)
            for dz in -R...R { for dx in -R...R {
                let x = Int(c.x) + dx, z = Int(c.z) + dz
                let top = w.topY(x, z)
                guard top > 0 else { continue }
                let b = w.block(x, top, z)
                if black.contains(b) { burnt += 1 }
                if dx * dx + dz * dz < 100 { bowlTops[Blocks.name(b), default: 0] += 1 }
                if b == Blocks.id("coarse_dirt") && dx * dx + dz * dz > Int(MainGun.craterRadius * MainGun.craterRadius * 0.7) { scorchedRim += 1 }
            } }
            let solid = bowlTops.filter { $0.key != "Water" && !$0.key.contains("Leaves") }.values.reduce(0, +)
            check(MainGun.lastScorched > 200 && burnt * 2 > solid && burnt > 40 && scorchedRim > 30,
                  "maingun: the crater is scorched (\(MainGun.lastScorched) blocks burnt: \(burnt) of \(solid) solid tops in the bowl black, \(scorchedRim) scorched earth round the rim; bowl tops \(bowlTops.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key) \($0.value)" }.joined(separator: ", ")))")
        }
        if !tickMs.isEmpty {
            let srt = tickMs.sorted()
            print(String(format: "maingun: frame thread for %.1f s after the impact (host): median %.2f ms, p99 %.2f ms, worst %.2f ms; first frame %.2f ms",
                         Double(tickMs.count) / 72, srt[srt.count / 2], srt[srt.count * 99 / 100], srt.last!, tickMs[0]))
            let slowest = tickMs.indices.sorted { tickMs[$0] > tickMs[$1] }.prefix(5)
            print("maingun: slowest frames after the impact: " + slowest.map { String(format: "#%d %.1f ms", $0, tickMs[$0]) }.joined(separator: ", "))
            for k in slowest where k < detail.count { print("maingun:   #\(k): " + detail[k]) }
            print("maingun: " + MainGunPerf.lastReport)
            print("maingun: the impact's own work (ms): " + MainGun.impactCost)
            // The impact frame (the crater's first slice comes the frame after): the structure lookup that planned
            // a region here was a 76-125 ms hitch on the host at the gun's biggest moment.
            check(MainGun.impactMs < 12, String(format: "maingun: the impact itself is cheap on the frame thread (%.1f ms: %@)", MainGun.impactMs, MainGun.impactCost))
        }
        if let render, impactFrame >= 0 {
            // The crater once the world has remeshed it and the smoke has cleared, from above its rim.
            let c = MainGun.lastImpact
            g.particles.list.removeAll()
            g.player.pos = c + V3(-24, 26, 24)
            _ = w.loadSync(center: c, radius: 3)
            w.remeshArea(x0: Int(c.x) - 20, z0: Int(c.z) - 20, x1: Int(c.x) + 20, z1: Int(c.z) + 20, y0: Int(c.y) - 24, y1: Int(c.y) + 20)
            let to = c - g.player.eye
            render("maingun_crater", atan2f(-to.x, -to.z), atan2f(to.y, simd_length(V2(to.x, to.z))))
        }

        // 4. A hit past the streamed world (a long shot from the helm): the bowl waits and is dug, quietly, once its
        // ground loads.
        do {
            w.ships.shockwaves.removeAll()
            let fx = Int(home.x) + 2400, fz = Int(home.z) - 2400
            let p = V3(Float(fx) + 0.5, Float(w.gen.column(fx, fz).height) + 1, Float(fz) + 0.5)
            let pending0 = w.ships.pendingCraters.count
            w.ships.mainGunImpact(at: p, owner: s.id, game: g)
            MainGunPerf.finish(budget: 1000.0 / 72)
            let waited = w.ships.pendingCraters.count == pending0 + 1 && MainGun.lastCrater == 0
            g.player.pos = p + V3(0, 20, 0)
            _ = w.loadSync(center: p, radius: 3)
            var frames = 0
            while frames < 600 && (w.ships.pendingCraters.count > pending0 || !w.ships.shockwaves.isEmpty) {
                w.ships.updateShockwaves(1.0 / 72, game: g)
                frames += 1
            }
            check(waited && MainGun.lastCrater > 1000 && w.ships.shockwaves.isEmpty,
                  "maingun: a hit on ground not loaded yet waits, then the bowl is dug when it loads (\(MainGun.lastCrater) blocks after \(frames) frames)")
            w.ships.pendingCraters.removeAll()
        }

        // 6. A slug into another Capital vessel's hull tears it open and knocks out its drive: it goes down.
        do {
            let n1 = w.ships.list.count
            let tp = s.toWorld(st.mainGunMuzzle) + s.dirToWorld(st.mainGunDir) * 160
            w.ships.spawnCapital("frigate", home: IVec3(Int(tp.x), 0, Int(tp.z)), yaw: 0, region: nil, sync: true)
            if let e = w.ships.list.dropFirst(n1).first(where: { $0.role == "frigate" }) {
                defer { w.ships.remove(e); w.ships.capState.removeValue(forKey: e.id); w.ships.shockwaves.removeAll() }
                func hull() -> Int { w.ships.list.filter { $0.root === e.root }.reduce(0) { $0 + $1.blockCount } }
                let blocks0 = hull(), engines0 = e.engines, hits0 = MainGun.shipHits
                let mw = s.toWorld(st.mainGunMuzzle)
                let aim = (e.worldMin + e.worldMax) * 0.5
                w.ships.fireMainGun(s, st, dir: simd_normalize(aim - mw), game: g)
                var frames = 0
                while MainGun.shipHits == hits0 && frames < 300 { w.ships.updateShells(1.0 / 72, game: g); frames += 1 }
                check(MainGun.shipHits == hits0 + 1 && e.engines == 0 && engines0 > 0 && MainGun.lastTorn > 40 && hull() <= blocks0 - MainGun.lastTorn,
                      "maingun: a slug into a Stormwarden frigate's hull knocks out its drive (\(engines0) -> \(e.engines) engines) and tears a hole in it (\(MainGun.lastTorn) blocks: \(blocks0) -> \(hull()))")
            } else { check(false, "maingun: the target frigate spawns") }
        }

        // 7. Against an Ironback Crawler (Oct 11 playtest, G13: "it should tear off a huge chunk or destroy it outright"):
        // a direct hit wrecks it and tears a hole hundreds of blocks big; a near miss on the ground beside it still
        // tears its side and, close enough, wrecks it too.
        for near in [false, true] {
            let n1 = w.ships.list.count
            let tp = s.toWorld(st.mainGunMuzzle) + s.dirToWorld(st.mainGunDir) * 150
            g.player.pos = tp + V3(-40, 30, 60)                  // (near: a capital past 1,400 blocks of the player is dropped)
            g.player.vel = .zero
            w.ships.spawnCapital("crawler", home: IVec3(Int(tp.x) + (near ? 60 : 0), 0, Int(tp.z)), yaw: 0, region: nil, sync: true)
            guard let e = w.ships.list.dropFirst(n1).first(where: { $0.role == "crawler" }), let est = w.ships.capState[e.id] else {
                check(false, "maingun: the target crawler spawns"); continue
            }
            defer { w.ships.remove(e); w.ships.capState.removeValue(forKey: e.id); w.ships.shockwaves.removeAll() }
            _ = w.loadSync(center: e.pos, radius: 3)
            func hull() -> Int { w.ships.list.filter { $0.root === e.root }.reduce(0) { $0 + $1.blockCount } }
            let blocks0 = hull(), hits0 = MainGun.shipHits
            if near {
                // A slug into the ground 3 blocks off its flank (its side, level with the wheels).
                let p = V3(e.worldMax.x + 3, e.worldMin.y + 2, (e.worldMin.z + e.worldMax.z) * 0.5)
                w.ships.mainGunHullDamage(at: p, owner: s.id, direct: nil, game: g)
            } else {
                let mw = s.toWorld(st.mainGunMuzzle)
                w.ships.fireMainGun(s, st, dir: simd_normalize((e.worldMin + e.worldMax) * 0.5 - mw), game: g)
                var frames = 0
                while MainGun.shipHits == hits0 && frames < 300 { w.ships.updateShells(1.0 / 72, game: g); frames += 1 }
            }
            w.ships.capitalTick(1.0 / 72, game: g)                // (the wreck is declared on its next tick)
            let torn = blocks0 - hull()
            check(MainGun.shipHits == hits0 + 1 && e.wrecked && torn >= (near ? 150 : 400),
                  "maingun: a \(near ? "near miss 3 blocks off" : "direct hit on") an Ironback Crawler wrecks it (\(est.disabledWhy)) and tears out \(torn) of its \(blocks0) blocks")
            // T9: with its driver dead the wreck can be taken; ingots rebuild its lost wheels and it drives again.
            if near {
                est.crewDone = Set(est.crewRoles.indices)
                let takeable = w.ships.canCommandeer(e)
                e.captured = true; e.wrecked = false
                let lost0 = est.wheelsLost
                var rebuilt = 0
                while rebuilt < 40, w.ships.repairVehicle(e, near: IVec3(Int(e.com.x), Int(e.com.y), Int(e.com.z))) != nil { rebuilt += 1 }
                w.ships.pilot = e; e.throttle = 1
                for _ in 0..<144 { w.ships.capitalTick(1.0 / 72, game: g) }
                let v = simd_length(V2(e.vel.x, e.vel.z))
                w.ships.pilot = nil; e.throttle = 0
                check(takeable && est.wheelsLost == 0 && rebuilt >= lost0 && est.disabledWhy.isEmpty && v > 2,
                      String(format: "crawler: a crewless wreck can be taken, %d ingot uses rebuild its %d lost wheels (%d/%d) and engines (%d/%d), and it drives at %.1f b/s", rebuilt, lost0, est.wheels.count - est.wheelsLost, est.wheels.count, e.engines, est.engines0, v))
            }
        }

        // 8. The frigates carry their own navy, not Capital soldiers: a Meridian crewman goes by the navy's ranks.
        do {
            let m = Mob(.soldierTrooper, at: g.player.pos)
            let capital = m.spec.name
            m.faction = Faction.meridian.rawValue
            let navy = m.spec.name
            check(capital.hasPrefix("Capital") && navy.hasPrefix("Meridian") && Mob.crewNames.values.allSatisfy { $0.count == 6 },
                  "maingun: a Meridian frigate's crewman is a \(navy), not a \(capital)")
            // G7: no Capital city shares the navy's name.
            check(!CapitalTown.cityNames.contains { $0.contains("Meridian") }, "maingun: no Capital city is named after the Meridian Navy")
        }

        // 5. An AI frigate charging at the player warns them (a toast and a buzz) while there is time to get clear.
        do {
            var said: String?
            let wasToast = g.onToast
            g.onToast = { said = $0 }
            defer { g.onToast = wasToast }
            let w0 = MainGun.warnings
            st.target = CapTarget(point: g.player.eye, vel: .zero, ship: nil, mob: nil, player: true, seat: 0)
            w.ships.startMainGunCharge(s, st, g, byPlayer: false)
            st.gunCharge = -1
            st.target = nil
            check(MainGun.warnings == w0 + 1 && (said ?? "").contains("main gun"),
                  "maingun: an AI frigate charging at the player warns them (\"\(said ?? "nothing")\")")
        }

        // 6. The gap pass (MainGunGapTests.swift): Blast Shake, a citadel struck and broken.
        gap(g, check)
    }
}
