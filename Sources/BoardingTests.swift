import Foundation
import simd

// The way aboard the Meridian frigate from the ground (FrigateBoarding.swift; done audit 25b6, G11): a bot stands on
// the ground under a cruising frigate's boarding winch, is hauled up into the hangar, climbs the stairwell to the
// bridge and walks to the helm, all through Game.tick with the left stick (nothing teleported after the
// start fixture). Run by questcheck after the main gun checks.
enum BoardingTests {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        guard g.dim.dim == .overworld else { check(false, "boarding: needs the overworld"); return }
        let w = g.world
        let pm = PadManager.shared
        let home = g.player.pos, wasPaused = g.paused, wasFlying = g.player.flying, wasSim = pm.simulated
        let wasYaw = g.player.yaw, wasMoveYaw = g.player.moveYaw, wasHealth = g.health
        let wasAlive = g.alive, wasMenu = g.menu, wasSurvival = g.survival, wasPilot = w.ships.pilot
        defer {
            g.alive = wasAlive; g.menu = wasMenu; g.survival = wasSurvival
            w.ships.pilot = wasPilot                                // (P499: the walk ends at the helm; the frigate goes)
            pm.simulated = wasSim
            g.player.pos = home; g.player.vel = .zero; g.player.flying = wasFlying; g.paused = wasPaused
            g.player.yaw = wasYaw; g.player.moveYaw = wasMoveYaw; g.health = wasHealth
            _ = w.loadSync(center: home, radius: 8)
        }
        g.paused = false
        g.player.flying = false
        g.player.moveYaw = nil
        // A living player with no menu open (an earlier check in the full questcheck can leave it dead on the death
        // screen, where the stick moves nothing).
        g.alive = true; g.menu = nil; g.health = max(g.health, g.maxHealth)
        g.survival = true                                           // (falls hurt: the haul must not)
        let startHealth = g.health
        // Nobody else about: the main gun checks before this one leave Meridian crews and ships, and in survival their
        // rounds and shells hurt (so: no mobs, nothing in flight, no fire on the player).
        let mobs0 = g.mobs.mobs
        defer { g.mobs.mobs = mobs0 }
        func tick() {
            g.mobs.mobs.removeAll(); w.pendingMobs.removeAll()
            g.arms.slugs.removeAll(); w.ships.shells.removeAll(); g.onFire = 0
            g.tick(1.0 / 72)
        }
        // Every hit the player takes during the check, by cause (the message names them).
        var hurt: [String] = []
        let wasOnDamage = Game.onDamage
        Game.onDamage = { amount, cause in hurt.append("\(cause) \(amount)") }
        defer { Game.onDamage = wasOnDamage }
        // A crewless frigate (drives as if crewed, nobody aboard to shoot) cruising 200 blocks east of the start.
        let n0 = w.ships.list.count
        w.ships.spawnCapital("capfrigate", home: IVec3(Int(home.x) + 200, 0, Int(home.z)), yaw: 0.7, region: nil, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "capfrigate" }), let st = w.ships.capState[s.id] else {
            check(false, "boarding: the Meridian frigate spawns"); return
        }
        defer { w.ships.remove(s); w.ships.capState.removeValue(forKey: s.id) }
        st.crewless = true
        st.mainGunCD = 999
        // Let it get under way, then stand the bot on the ground at the line's foot (the start fixture).
        for _ in 0..<72 { tick() }
        let speed0 = simd_length(V2(s.vel.x, s.vel.z))
        let a0 = FrigateBoarding.anchor(s)
        _ = w.loadSync(center: a0, radius: 3)
        let foot = V3(a0.x, Float(w.topY(Int(floor(a0.x)), Int(floor(a0.z))) + 1), a0.z)
        g.player.pos = foot
        g.player.vel = .zero
        let hauled0 = FrigateBoarding.hauled
        var frames = 0
        var slowest: Float = 99
        while FrigateBoarding.hauled == hauled0 && frames < 72 * 15 {
            // Keep standing at the foot as the frigate heaves to (the line drifts a little while it slows).
            let a = FrigateBoarding.anchor(s)
            walk(g, toward: V3(a.x, g.player.pos.y, a.z), slow: true)
            tick()
            frames += 1
            slowest = min(slowest, simd_length(V2(s.vel.x, s.vel.z)))
        }
        pm.simulated = nil
        let inHangar = s.toLocal(g.player.pos)
        check(FrigateBoarding.hauled == hauled0 + 1 && inHangar.y > 8.5 && inHangar.y < 14 && slowest < 2,
              String(format: "boarding: standing at the winch's foot hauls the player %.0f blocks up into the hangar in %.1f s (the frigate heaves to: %.1f -> %.1f b/s)",
                     a0.y - foot.y, Float(frames) / 72, speed0, slowest))
        check(g.health >= startHealth || !g.survival, "boarding: the haul does no fall damage (health \(g.health); hurt by \(hurt.isEmpty ? "nothing" : hurt.joined(separator: ", ")))")
        // Up the stairwell to the helm (P472: the ladders became one stairwell; P434 (c): a stair up into the bridge), as a
        // player goes: grid targets in the ship's frame (grid x = the blueprint's + 13), each leg walked until its test.
        // The hangar to the first flight's foot, up it (rising forward) to the main deck's stair hall; round to the second
        // flight's foot, up it (rising aft) to the upper deck's landing; round the rails to the bridge stair, up it
        // (rising forward) through the bridge floor; forward to the helm.
        let helm = V3(13.5, 25.05, 75.5)
        let legs: [(String, V3, (V3) -> Bool)] = [
            ("the first flight's foot", V3(8.5, 9, 100.0), { l in simd_length(V2(l.x - 8.5, l.z - 100)) < 0.7 }),
            ("up to the main deck", V3(8.5, 15, 91.5), { l in l.y > 14.9 && l.z < 93.5 }),
            ("the second flight's foot", V3(11.5, 15, 90.6), { l in simd_length(V2(l.x - 11.5, l.z - 90.6)) < 0.5 }),
            ("up to the upper deck", V3(11.5, 21, 99.0), { l in l.y > 20.9 && l.z > 97.5 }),
            ("round the rails", V3(13.6, 21, 98.8), { l in abs(l.x - 13.6) < 0.4 }),
            ("along the landing", V3(13.6, 21, 91.6), { l in l.z < 92 }),
            ("the bridge stair's foot", V3(11.0, 21, 91.6), { l in abs(l.x - 11.0) < 0.4 }),
            ("up to the bridge", V3(11.0, 25, 85.0), { l in l.y > 24.9 }),
            ("the helm", helm, { l in simd_length(l - helm) < 2 }),
        ]
        var stage = 0
        frames = 0
        var best: Float = 999
        while stage < legs.count && frames < 72 * 60 {
            let l = s.toLocal(g.player.pos)
            let (_, to, done) = legs[stage]
            if done(l) { stage += 1; continue }
            walk(g, toward: s.toWorld(V3(to.x, l.y, to.z)))
            if stage == legs.count - 1 { best = min(best, simd_length(l - helm)) }
            tick()
            frames += 1
        }
        pm.simulated = nil
        let l = s.toLocal(g.player.pos)
        let reached = stage == legs.count
        check(reached, String(format: "boarding: from the hangar the bot climbs the stairwell to the bridge and reaches the helm in %.1f s (%@, at %.1f,%.1f,%.1f, %.1f from the helm)",
                              Float(frames) / 72, reached ? "there" : "stuck on " + legs[stage].0, l.x, l.y, l.z, best))
        check(reached && w.ships.canCommandeer(s), "boarding: the helm the bot reached can be taken (canCommandeer)")
    }

    // The left stick pushed toward a world point (yaw turned to face it), A held to climb when asked.
    static func walk(_ g: Game, toward t: V3, slow: Bool = false, jump: Bool = false) {
        let d = t - g.player.pos
        let flat = simd_length(V2(d.x, d.z))
        g.player.yaw = atan2f(-d.x, -d.z)                         // forward = (-sin yaw, -cos yaw)
        var p = PadSnapshot()
        p.ly = slow ? min(1, flat * 0.6) : (flat > 0.3 ? 1 : 0)
        p.a = jump
        PadManager.shared.simulated = p
    }
}
