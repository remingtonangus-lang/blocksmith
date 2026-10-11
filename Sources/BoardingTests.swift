import Foundation
import simd

// The way aboard the Meridian frigate from the ground (FrigateBoarding.swift; done audit 25b6, G11): a bot stands on
// the ground under a cruising frigate's boarding winch, is hauled up into the hangar, walks to the ladder, climbs to
// the bridge deck and walks to the helm, all through Game.tick with the left stick (nothing teleported after the
// start fixture). Run by questcheck after the main gun checks.
enum BoardingTests {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        guard g.dim.dim == .overworld else { check(false, "boarding: needs the overworld"); return }
        let w = g.world
        let pm = PadManager.shared
        let home = g.player.pos, wasPaused = g.paused, wasFlying = g.player.flying, wasSim = pm.simulated
        let wasYaw = g.player.yaw, wasMoveYaw = g.player.moveYaw, wasHealth = g.health
        defer {
            pm.simulated = wasSim
            g.player.pos = home; g.player.vel = .zero; g.player.flying = wasFlying; g.paused = wasPaused
            g.player.yaw = wasYaw; g.player.moveYaw = wasMoveYaw; g.health = wasHealth
            _ = w.loadSync(center: home, radius: 8)
        }
        g.paused = false
        g.player.flying = false
        g.player.moveYaw = nil
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
        for _ in 0..<72 { g.tick(1.0 / 72) }
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
            g.tick(1.0 / 72)
            frames += 1
            slowest = min(slowest, simd_length(V2(s.vel.x, s.vel.z)))
        }
        pm.simulated = nil
        let inHangar = s.toLocal(g.player.pos)
        check(FrigateBoarding.hauled == hauled0 + 1 && inHangar.y > 8.5 && inHangar.y < 14 && slowest < 2,
              String(format: "boarding: standing at the winch's foot hauls the player %.0f blocks up into the hangar in %.1f s (the frigate heaves to: %.1f -> %.1f b/s)",
                     a0.y - foot.y, Float(frames) / 72, speed0, slowest))
        check(g.health >= wasHealth || !g.survival, "boarding: the haul does no fall damage (health \(g.health))")
        // Walk the hangar to the ladder, climb to the bridge deck, walk to the helm (grid targets, the ship's frame).
        let ladder = V3(10.5, 9.05, 89.5), helm = V3(13.5, 25.05, 75.5)   // (the ladder's cell; its wall is to the west)
        var stage = 0
        frames = 0
        var best: Float = 999
        while stage < 3 && frames < 72 * 40 {
            let l = s.toLocal(g.player.pos)
            switch stage {
            case 0:
                walk(g, toward: s.toWorld(V3(ladder.x, l.y, ladder.z)))
                if simd_length(V2(l.x - ladder.x, l.z - ladder.z)) < 0.6 { stage = 1 }
            case 1:
                walk(g, toward: s.toWorld(V3(ladder.x - 2, l.y, ladder.z)), jump: true)   // into the ladder's wall: climb
                if l.y > 25 { stage = 2 }
            default:
                walk(g, toward: s.toWorld(V3(helm.x, l.y, helm.z)))
                best = min(best, simd_length(l - helm))
                if simd_length(l - helm) < 2 { stage = 3 }
            }
            g.tick(1.0 / 72)
            frames += 1
        }
        pm.simulated = nil
        let l = s.toLocal(g.player.pos)
        check(stage == 3, String(format: "boarding: from the hangar the bot walks to the ladder, climbs to the bridge and reaches the helm in %.1f s (stage %d, at %.1f,%.1f,%.1f, %.1f from the helm)",
                                 Float(frames) / 72, stage, l.x, l.y, l.z, best))
        check(w.ships.canCommandeer(s), "boarding: the helm reached can be taken (canCommandeer)")
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
