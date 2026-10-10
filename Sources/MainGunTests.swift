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
        let wasFlying = g.player.flying, wasTime = g.time
        let pm = PadManager.shared
        let wasSim = pm.simulated
        pm.simulated = PadSnapshot()                            // rumble requests are logged (rumbleLog)
        defer {
            g.player.pos = home; g.player.vel = .zero; g.player.flying = wasFlying; g.time = wasTime
            // The shots streamed the world around the frigate, far from the start: load the start again for the
            // checks that run after this one (they stand mobs on the ground around the player).
            _ = w.loadSync(center: home, radius: 8)
            pm.simulated = wasSim
            g.shake = 0
        }
        g.player.flying = true
        g.time = 0.3 * DAY_LENGTH

        // The frigate, about 300 blocks east of the start, heading north (-z), placed where the ground the helm shot
        // lands on (100 to 180 blocks ahead, within the streamed world around the player) is dry land near the
        // highest ground under the hull, which sets the frigate's cruise height (spawnCapital), so the crater is dug
        // in earth rather than under the sea and the shot lands about 130 blocks out.
        func dry(_ x: Int, _ z: Int) -> Bool {
            var top = SEA
            for k in -4...4 { for j in -1...1 { top = max(top, w.gen.column(x + k * 60, z + j * 40).height) } }
            return stride(from: 100, through: 180, by: 20).allSatisfy { d in
                let h = w.gen.column(x, z - d).height
                return h > SEA + 1 && h >= top - 10
            }
        }
        var fx = Int(home.x) + 300, fz = Int(home.z)
        search: for r in 0..<20 {
            for k in -r...r {
                for (dx, dz) in [(k, -r), (k, r), (-r, k), (r, k)] where dry(fx + dx * 96, fz + dz * 96) {
                    fx += dx * 96; fz += dz * 96
                    break search
                }
            }
        }
        let n0 = w.ships.list.count
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
        check(tube == 63 && bore == 63 && coils >= 9 && st.mainGunLength == 63 && st.mainGunMuzzle.z < 1,
              "maingun: a 63-block barrel between the booms (tube \(tube), clear bore \(bore), \(coils) glowing coil rings), muzzle at the bow (z \(st.mainGunMuzzle.z))")
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
        let mw0 = s.toWorld(st.mainGunMuzzle)
        let md = s.dirToWorld(st.mainGunDir)
        let pitch: Float = -0.52
        let h = simd_normalize(V2(md.x, md.z))
        let dir = V3(h.x * cosf(pitch), sinf(pitch), h.y * cosf(pitch))
        // Where the slug will land (the generator's heights along its path), loaded beforehand.
        var land = mw0
        var t: Float = 0
        while t < 600 {
            t += 2
            let p = mw0 + dir * t
            if p.y <= Float(w.gen.column(Int(floor(p.x)), Int(floor(p.z))).height) + 1 { land = p; break }
        }
        // The player watches from 50 blocks off the frigate's bow, near enough to feel the charge and see the impact.
        g.player.pos = mw0 + V3(-50, 0, -10)
        g.player.vel = .zero
        _ = w.loadSync(center: g.player.pos, radius: 3)
        _ = w.loadSync(center: land, radius: 4)
        print(String(format: "maingun: aiming %.0f blocks ahead of the muzzle, %.0f from the player", simd_length(land - mw0), simd_length(land - g.player.pos)))
        pm.rumbleLog.removeAll()
        let shells0 = w.ships.shells.filter { $0.kind == 3 }.count
        let started = w.ships.playerMainGun(s, pitch: pitch, game: g)
        st.gunPitch = pitch
        let again = w.ships.playerMainGun(s, pitch: pitch, game: g)
        var maxShake: Float = 0, flashes = 0, frames = 0
        var shotRendered = false
        while st.gunCharge >= 0 && frames < 400 {
            g.tick(1.0 / 72)
            frames += 1
            maxShake = max(maxShake, g.shake)
            flashes = max(flashes, g.flashes.count)
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
            if impactFrame >= 0 { detail.append(String(format: "tick %.1f [%@] (gravity queue %d, fluid %d, falling %d, particles %d)",
                                                        ms, TickProf.summary(), gq, fl, falls, g.particles.list.count)) }
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
        if !tickMs.isEmpty {
            let srt = tickMs.sorted()
            print(String(format: "maingun: frame thread for %.1f s after the impact (host): median %.2f ms, p99 %.2f ms, worst %.2f ms; first frame %.2f ms",
                         Double(tickMs.count) / 72, srt[srt.count / 2], srt[srt.count * 99 / 100], srt.last!, tickMs[0]))
            let slowest = tickMs.indices.sorted { tickMs[$0] > tickMs[$1] }.prefix(5)
            print("maingun: slowest frames after the impact: " + slowest.map { String(format: "#%d %.1f ms", $0, tickMs[$0]) }.joined(separator: ", "))
            for k in slowest where k < detail.count { print("maingun:   #\(k): " + detail[k]) }
            print("maingun: " + MainGunPerf.lastReport)
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
    }
}
