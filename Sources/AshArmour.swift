import Foundation
import simd

// P449 (Oct 25 09:03, the Ash Vault: "the truck shouldn't be entities, they should be built up of blocks. Same thing
// with the tank. Its armor should be individual blocks that somehow work. That's how every vehicle should work too...
// Although I want it to still look like this"). The Ashguard's vehicles keep their look and their driving, and their
// armour now works plate by plate: the hull is six plates round it (front, the two front quarters, the two rear
// quarters, the back). A hit lands on the plate on its side of the hull: an intact plate takes half the hit and wears,
// and once it has taken its strength it comes off (a clang, sparks and torn pieces) and leaves the hull there bare:
// hits on a bare side do half as much again. Front plates are thickest, the back thinnest. The plates shot off show
// (the bare hull charred and torn on that side) and are saved with the vehicle.
enum AshArmour {
    static let sectors = 6                       // 0 front, 1 front right, 2 rear right, 3 back, 4 rear left, 5 front left
    static var shed: [(Mob, Int)] = []           // plates come off since the last frame (their effects: shedEffects)
    static var lost = 0, soaked = 0              // (counters)

    // What a plate takes before it comes off.
    static func strength(_ k: MobKind, _ s: Int) -> Float {
        let base: Float
        switch k {
        case .ashTank: base = 36
        case .ashBehemoth: base = 70
        case .ashHalftrack: base = 18
        case .ashArtillery: base = 14
        default: base = 8                        // the truck
        }
        return s == 0 ? base * 1.4 : (s == 3 ? base * 0.5 : base)
    }

    // The plate facing a point (its bearing from the hull's middle, against the hull's heading).
    static func sector(_ m: Mob, _ src: V3) -> Int {
        let d = V2(src.x - m.pos.x, src.z - m.pos.z)
        guard simd_length(d) > 0.01 else { return 0 }
        let f = V2(m.forward.x, m.forward.z), r = V2(-f.y, f.x)
        return sector(angle: atan2f(simd_dot(d, r), simd_dot(d, f)))
    }
    static func sector(angle a: Float) -> Int {
        let n = Int(floorf((a + .pi / 6) / (.pi / 3)))
        return ((n % 6) + 6) % 6
    }

    // A hit of `damage` from `src`: what gets through to the hull.
    static func hit(_ m: Mob, _ damage: Int, from src: V3) -> Int {
        if m.armourWear.count != sectors { m.armourWear = [Float](repeating: 0, count: sectors) }
        let s = sector(m, src)
        if m.armourLost & (1 << s) != 0 { return damage + damage / 2 }
        m.armourWear[s] += Float(damage)
        soaked += 1
        if m.armourWear[s] >= strength(m.kind, s) {
            m.armourLost |= UInt8(1 << s)
            shed.append((m, s))
            lost += 1
        }
        return max(1, damage / 2)
    }

    // The outward direction of a plate (world).
    static func outward(_ m: Mob, _ s: Int) -> V3 {
        let a = Float(s) * .pi / 3
        let f = m.forward, r = V3(-f.z, 0, f.x)
        return f * cosf(a) + r * sinf(a)
    }

    // The plates come off: a clang and sparks where each was, torn pieces thrown out from the hull.
    static func shedEffects(_ g: Game) {
        guard !shed.isEmpty else { return }
        let iron = Blocks.has("iron_block") ? Blocks.id("iron_block") : STONE
        for (m, s) in shed {
            let out = outward(m, s)
            let at = m.pos + out * (m.halfW + 0.4) + V3(0, m.spec.height * 0.45, 0)
            let cell = IVec3(Int(floor(at.x)), Int(floor(at.y)), Int(floor(at.z)))
            g.particles.explosion(at: at, power: 0.5)
            g.particles.blockBreak(iron, at: cell)
            g.sfx(.anvilLand, 0.9, at: at)
            if World.realistic {
                g.debris.shatter(iron, cell: cell, impact: m.pos, direction: out, count: 4, speed: 7,
                                 seed: hash3(cell.x, cell.y, cell.z, 0x449), crowding: 0.3)
            }
        }
        shed.removeAll()
    }

    // The model (1/16 block, facing -Z, right +X) with the plates shot off: the armour on that side of the hull drawn
    // bare (charred dark steel), and a torn, scorched patch over the hull's face there.
    static func strip(_ m: Mob, _ p: inout [Part]) {
        guard m.armourLost != 0 else { return }
        var lo = V3(repeating: 1e9), hi = V3(repeating: -1e9)
        for q in p where q.pivot == .zero { lo = simd_min(lo, q.mn); hi = simd_max(hi, q.mx) }
        guard hi.x > lo.x else { return }
        let mid = (lo + hi) * 0.5, half = (hi - lo) * 0.5
        let bare = V3(0.05, 0.04, 0.035)
        for i in p.indices where p[i].pivot == .zero {
            let c = (p[i].mn + p[i].mx) * 0.5 - mid
            // The armour, not the running gear: parts out toward the hull's skin (wheels and tracks are dark already).
            guard max(abs(c.x) / max(1, half.x), abs(c.z) / max(1, half.z)) > 0.35 else { continue }
            let s = sector(angle: atan2f(c.x, -c.z))
            guard m.armourLost & (1 << s) != 0 else { continue }
            p[i].color = p[i].color * 0.35 + bare
        }
        // The torn patch on each bare side: over the face of the hull's box toward that plate, the middle half of its
        // height.
        let y0 = lo.y + (hi.y - lo.y) * 0.3, y1 = lo.y + (hi.y - lo.y) * 0.75
        for s in 0..<sectors where m.armourLost & (1 << s) != 0 {
            let a = Float(s) * .pi / 3
            let dx = sinf(a), dz = -cosf(a)
            // The face point: the hull box's edge along that bearing.
            let t = min(abs(dx) > 0.01 ? half.x / abs(dx) : 1e9, abs(dz) > 0.01 ? half.z / abs(dz) : 1e9)
            let c = mid + V3(dx * t, 0, dz * t)
            let w: Float = s == 0 || s == 3 ? half.x * 0.9 : half.z * 0.6
            if abs(dz) > abs(dx) {
                p.append(Part(mn: V3(c.x - w * 0.5, y0, c.z - 0.5), mx: V3(c.x + w * 0.5, y1, c.z + 0.5), color: bare, pattern: 4))
            } else {
                p.append(Part(mn: V3(c.x - 0.5, y0, c.z - w * 0.5), mx: V3(c.x + 0.5, y1, c.z + w * 0.5), color: bare, pattern: 4))
            }
        }
    }
}
