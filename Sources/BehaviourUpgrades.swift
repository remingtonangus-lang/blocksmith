import Foundation
import simd

// D32: upgrades that change behaviour, not just numbers (fitted at the Upgrade Bench like any other line; their
// blueprints turn up in chests like the rest).
//   Ricochet Rounds (gun, rounds part, 2 levels)  a round that strikes stone, metal or brick at a glancing angle (or
//                  anything, square on, at level 2) skips off it instead of stopping: up to one bounce a level, at 75%
//                  of its damage and speed each time. Shoot round corners; clear a trench from its lip.
//   Serrated Edge  (sword, axe or spear, edge part, 2 levels)  each hit opens a wound that bleeds: a point of damage
//                  every 0.8 s for 3 s a level, topped up by the next hit. Plate, bone and stone don't bleed.
enum Ricochet {
    static var bounces = 0                                 // (harness)

    // Reflects the round off the face; false when it buries itself instead.
    static func bounce(_ s: inout Slug, at: V3, normal n: IVec3, _ g: Game) -> Bool {
        let nv = V3(Float(n.x), Float(n.y), Float(n.z))
        let sp = simd_length(s.vel)
        guard sp > 20 else { return false }
        let d = s.vel / sp
        let glancing = abs(simd_dot(d, nv)) < 0.7                     // within about 45 degrees of the surface
        guard glancing || s.ricochet >= 2 else { return false }
        s.vel = (s.vel - nv * (2 * simd_dot(s.vel, nv))) * 0.75
        s.damage *= 0.75
        s.ricochet -= 1
        s.pos = at + nv * 0.04
        bounces += 1
        g.sfx(.gun(8), 0.5, at: at)
        return true
    }
}

enum Serrated {
    static let perLevel: Float = 3, every: Float = 0.8
    static var wounds = 0                                  // (harness)

    static func bloodless(_ m: Mob) -> Bool {
        let k = m.kind
        return k == .skeleton || k == .stray || k == .witherSkeleton || k == .ironGolem || k == .snowGolem || k == .blaze
            || k == .soldierIronclad || k == .deckGun || k.ashArmoured || m.spec.behavior == .vehicle
    }

    static func cut(_ m: Mob, _ level: Int) {
        guard level > 0, m.health > 0, !bloodless(m) else { return }
        m.bleed = max(m.bleed, perLevel * Float(level))
        wounds += 1
    }

    static func tick(_ m: Mob, _ dt: Float, _ g: Game) {
        m.bleed -= dt
        m.bleedTick += dt
        guard m.bleedTick >= every else { return }
        m.bleedTick = 0
        guard m.health > 0 else { m.bleed = 0; return }
        m.health -= 1
        m.hurt = 0.3
        g.particles.add(Particle(pos: m.pos + V3(0, m.height * 0.55, 0), vel: V3(Rand.float(in: -0.4...0.4), -0.5, Rand.float(in: -0.4...0.4)),
                                 life: 0.5, maxLife: 0.5, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: 0.06, gravity: 9,
                                 color: V3(0.5, 0.05, 0.05), collide: false))
    }
}
