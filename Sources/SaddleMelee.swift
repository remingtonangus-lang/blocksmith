import Foundation
import simd

// D5 melee from the saddle. Mounted on a horse (or any gaited mount) a blade reaches further (you strike down and
// out from a horse's back), a weapon held toward a creature finds it inside a wider cone (aiming from a moving
// horse is hard), and the horse's speed rides into the blow: up to +60 % damage and an extra knockback at the gallop.
// A hit from the saddle never lands on your own mount (Game.interact's `except: riding`).
enum SaddleMelee {
    static let reach: Float = 4.6
    static let cone: Float = 0.965                    // cos of the aim cone (about 15 degrees)

    static func mounted(_ g: Game) -> Mob? {
        guard let r = g.riding, r.gaited, r.health > 0 else { return nil }
        return r
    }

    static func meleeReach(_ g: Game, _ base: Float) -> Float { mounted(g) == nil ? base : max(base, reach) }

    static func speed(_ g: Game) -> Float {
        guard let r = mounted(g) else { return 0 }
        return simd_length(V2(r.vel.x, r.vel.z))
    }

    // Damage multiplier for a weapon swing from the saddle.
    static func damageMult(_ g: Game) -> Float {
        guard mounted(g) != nil, !g.held.isEmpty else { return 1 }
        return 1 + max(0, min(0.6, (speed(g) - 2.5) / 10))
    }

    // Extra knockback levels at the canter and gallop.
    static func knockback(_ g: Game) -> Float { mounted(g) == nil ? 0 : (speed(g) > 7 ? 1 : (speed(g) > 4.5 ? 0.5 : 0)) }

    // The nearest living creature in the wider mounted cone, within mounted reach.
    static func assist(_ g: Game) -> (Mob, Float)? {
        guard let r = mounted(g), !g.held.isEmpty else { return nil }
        var best: (Mob, Float)?
        let eye = g.player.eye, look = g.player.look
        for m in g.mobs.mobs where m.health > 0 && m !== r && m.mount !== r && g.isCreature(m) {
            let c = m.pos + V3(0, m.height * 0.5, 0) - eye
            let d = simd_length(c)
            guard d > 0.1, d < reach + m.halfW, simd_dot(c / d, look) > cone, d < (best?.1 ?? .greatestFiniteMagnitude) else { continue }
            guard g.world.canSee(eye, m.pos + V3(0, m.height * 0.5, 0)) else { continue }
            best = (m, d)
        }
        return best
    }
}
