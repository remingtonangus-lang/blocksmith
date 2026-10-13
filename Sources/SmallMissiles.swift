import Foundation
import simd

// P135 (Oct 12 PM, 17:26 "the crawler can launch little missiles... only little ones... crawlers, bases, frigates"):
// small missiles with a limited supply. Hulls with missile pods fire their seeking salvos as small missiles (a 1.0
// blast, was 2.5) from a load of three salvos. Hulls without pods (crawlers, the Capital frigate) and Capital
// citadels launch single homing missiles: one climbs off its launcher, then turns toward the player at 80 degrees a
// second (a sidestep or cover beats it) and bursts in a small blast that breaks no blocks. Crawlers carry 6, frigates
// 10, citadels 8 (restocking one every five calm minutes); launches come 6 to 9 seconds apart, only at a survival
// player 24 to 120 blocks off (inside that the guns do the work).
enum SmallMissiles {
    static let speed: Float = 22, turn: Float = 1.4, power: Float = 1.0, life: Float = 7
    static let minRange: Float = 24, maxRange: Float = 120
    static let crawlerLoad = 6, frigateLoad = 10, baseLoad = 8, podSalvos = 3
    static let baseRestock: Float = 300
    static var launched = 0

    static func launch(_ g: Game, from p: V3, at t: V3, by: String) {
        let d = simd_normalize(t - p)
        let up = simd_normalize(V3(d.x * 0.35, 1, d.z * 0.35))           // off the rail upward first
        var s = Slug(pos: p, vel: up * speed, kind: .rocket, damage: 0, fromPlayer: false, shooter: nil, by: by, life: life, gravity: 0)
        s.power = power
        s.homing = turn
        g.arms.spawn(s)
        launched += 1
        g.sfx(.gun(4), 0.9, at: p)
        g.addFlash(at: p, color: V3(4, 2.6, 1.2), radius: 5, life: 0.1)
        if simd_length(g.player.pos - p) < maxRange + 20 { g.onToast?("Missile launch: take cover!") }
    }

    // Turn a missile's flight toward the player, keeping its speed (no more than `homing` radians a second).
    static func steer(_ s: inout Slug, _ dt: Float, _ g: Game) {
        let v = simd_length(s.vel)
        guard v > 1e-3 else { return }
        let cur = s.vel / v
        let to = g.player.pos + V3(0, 1, 0) - s.pos
        let dl = simd_length(to)
        guard dl > 0.5 else { return }
        let want = to / dl
        let c = max(-1, min(1, simd_dot(cur, want)))
        let ang = acosf(c)
        let step = s.homing * dt
        if ang <= step { s.vel = want * v; return }
        // Rotate cur toward want by `step` in their common plane.
        var axis = simd_cross(cur, want)
        if simd_length(axis) < 1e-5 { axis = V3(0, 1, 0) }
        axis = simd_normalize(axis)
        let ortho = simd_normalize(simd_cross(axis, cur))
        s.vel = (cur * cosf(step) + ortho * sinf(step)) * v
    }

    // Whether a launcher at p fires at the player now.
    static func inReach(_ g: Game, _ p: V3) -> Bool {
        guard g.survival, g.alive, g.difficulty > 0 else { return false }
        let d = simd_length(g.player.pos - p)
        return d >= minRange && d <= maxRange
    }
}

extension ShipManager {
    // A crawler's or a flying frigate's missiles (P135), at its target while that is the player.
    func shipMissiles(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        guard st.pods.isEmpty else { return }                 // pod hulls fire salvos instead (CapitalShips capitalGuns)
        if st.missiles < 0 { st.missiles = s.role == "crawler" ? SmallMissiles.crawlerLoad : (s.isFlyingCapital ? SmallMissiles.frigateLoad : 0) }
        st.smallCD -= dt
        guard st.missiles > 0, st.smallCD <= 0, st.target?.player == true else { return }
        let top = V3(s.pos.x, s.worldMax.y + 1.5, s.pos.z)
        guard SmallMissiles.inReach(g, top) else { return }
        st.missiles -= 1
        st.smallCD = Rand.float(in: 6...9)
        SmallMissiles.launch(g, from: top, at: g.player.pos, by: s.role == "crawler" ? "Capital Crawler" : "Capital Frigate")
    }
}

extension Game {
    // A citadel's missiles (P135): from the top of the keep while the base is on alert or locked down.
    func baseMissiles(_ r: inout BaseRecord, _ dt: Float) {
        var n = r.missiles ?? SmallMissiles.baseLoad
        var cd = (r.missileCD ?? 3) - dt
        defer { r.missiles = n; r.missileCD = cd }
        if r.alert.rawValue < BaseAlert.alert.rawValue {
            if n < SmallMissiles.baseLoad && cd < -SmallMissiles.baseRestock { n += 1; cd = 0 }       // restocking while calm
            if n >= SmallMissiles.baseLoad { cd = max(cd, 0) }
            return
        }
        guard n > 0, cd <= 0, world.isLoaded(r.cx, r.cz) else { return }
        let top = V3(Float(r.cx) + 0.5, Float(world.topY(r.cx, r.cz) + 2), Float(r.cz) + 0.5)
        guard SmallMissiles.inReach(self, top) else { return }
        n -= 1
        cd = Rand.float(in: 6...9)
        SmallMissiles.launch(self, from: top, at: player.pos, by: "Capital Citadel")
    }
}
