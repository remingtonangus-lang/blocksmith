import Foundation
import simd

// D16 bandit gangs that use cover and flank. Outlaws, their gangs, camp bandits and road agents (Mob.posse 1, 2 and
// Contracts.banditPosse) fight as a gang instead of each walking straight at you:
//   gunmen (marauders)   between shots they duck behind cover (the nearest standing spot within 7 blocks you can't see
//                        from where you are), reload there, then step out toward you until they have a line and fire.
//   brawlers (brigands)  swing wide: each takes a side (left or right, by who they are) and closes on a point 70
//                        degrees off your facing line, so they come at you from the flanks; inside 5 blocks they charge.
//                        A gun pointed at one makes it jink side to side.
// Everyone else keeps the plain hostile AI. The gang's cover and side are per mob and not saved.
enum GangTactics {
    static let flankAngle: Float = 70 * .pi / 180
    static var coverRuns = 0, flanks = 0           // (tests)

    static func member(_ m: Mob) -> Bool {
        (m.kind == .pillager || m.kind == .vindicator) && (m.posse == 1 || m.posse == 2 || m.posse == Contracts.banditPosse)
    }

    // Mob.update (.melee and .ranged): the gang's move this tick, or nil for the plain AI.
    static func step(_ m: Mob, _ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float? {
        guard member(m), canTarget, dist < 40, m.roped <= 0 else { return nil }
        m.gangT -= dt
        return m.kind == .pillager ? gunman(m, dt, g, dist: dist) : brawler(m, dt, g, dist: dist)
    }

    static func side(_ m: Mob) -> Float { (UInt(bitPattern: ObjectIdentifier(m).hashValue) >> 4) & 1 == 0 ? -1 : 1 }

    static func brawler(_ m: Mob, _ dt: Float, _ g: Game, dist: Float) -> Float? {
        if dist < 5 { return nil }
        let p = g.player.pos
        var away = V2(m.pos.x - p.x, m.pos.z - p.z)
        let l = max(0.01, simd_length(away)); away /= l
        let a = flankAngle * side(m)
        let rot = V2(away.x * cosf(a) - away.y * sinf(a), away.x * sinf(a) + away.y * cosf(a))
        let r = min(l * 0.6, 8)
        let goal = V3(p.x + rot.x * r, m.pos.y, p.z + rot.y * r)
        if simd_length(V2(goal.x - m.pos.x, goal.z - m.pos.z)) < 1.5 { return nil }
        m.face(goal)
        if m.gangT <= 0 { m.gangT = 4; flanks += 1 }
        // A gun on him: jink.
        if g.heldGun != nil, simd_dot(simd_normalize(m.eye - g.player.eye), g.player.look) > 0.97 {
            m.strafe = sinf(Float(g.clock) * 5) * m.spec.speed * 0.8
        }
        return m.spec.speed
    }

    static func gunman(_ m: Mob, _ dt: Float, _ g: Game, dist: Float) -> Float? {
        let w = g.world
        let eye = g.player.eye
        // Reloading (just fired): to cover, or stay in it.
        if m.attackCooldown > 0.4 {
            if m.gangCover == nil || m.gangT <= 0 {
                m.gangCover = cover(m, w, from: eye)
                m.gangT = 3
                if m.gangCover != nil { coverRuns += 1 }
            }
            guard let c = m.gangCover else { return nil }
            let d = simd_length(V2(c.x - m.pos.x, c.z - m.pos.z))
            if d < 0.6 { m.face(g.player.pos); return 0 }
            m.face(c)
            return m.spec.speed
        }
        // Ready: step out until there is a line, then the plain AI shoots.
        m.gangCover = nil
        if w.canSee(m.eye, eye) { return nil }
        m.face(g.player.pos)
        return m.spec.speed * 0.7
    }

    // The nearest standing spot within 7 blocks out of the line of sight from `from`.
    static func cover(_ m: Mob, _ w: World, from: V3) -> V3? {
        let y = Int(floor(m.pos.y + 0.1))
        let bx = Int(floor(m.pos.x)), bz = Int(floor(m.pos.z))
        var best: (Float, V3)?
        for k in 0..<28 {
            let a = Float(k) * 2.399                     // golden-angle spiral
            let r = 2 + Float(k) * 0.18
            let x = bx + Int((cosf(a) * r).rounded()), z = bz + Int((sinf(a) * r).rounded())
            for dy in [0, 1, -1] {
                let fy = y + dy
                guard w.solidAt(x, fy - 1, z), !w.solidAt(x, fy, z), !w.solidAt(x, fy + 1, z) else { continue }
                let spot = V3(Float(x) + 0.5, Float(fy), Float(z) + 0.5)
                if !w.canSee(spot + V3(0, 1.5, 0), from) {
                    let d = simd_length(spot - m.pos)
                    if d < (best?.0 ?? .greatestFiniteMagnitude) { best = (d, spot) }
                }
                break
            }
        }
        return best?.1
    }
}
