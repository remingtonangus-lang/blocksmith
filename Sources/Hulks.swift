import Foundation
import simd

// P473 (Oct 26 19:27, his Salvaged Fighter shot up: "The plane shouldn't turn into blocks after it's destroyed... find a
// way so that the plane still looks decent... just make your own polygon shit"; 19:42, a Capital turret wrecked: "The
// gun is the structure. It doesn't have to turn into a bunch of blocks afterwards"): a gun or a vehicle destroyed stays
// where it died as its own model, a hulk: charred in patches (soot, rust, scorched paint, by each part's own hash),
// smoking for a minute, solid to bump into and climb onto. Only a few of its small fittings are still thrown off as
// pieces (Game.ashShed), instead of a heap of blocks where a gun stood (NavalGuns.wreck) or the whole model coming apart
// (ashBreakUp). A hulk is kept while he is about, gone once he is 200 blocks off or leaves the world, at most 16.
enum Hulks {
    static var mobs: [Mob] = []
    static let most = 16
    static let leave: Float = 200
    static let smokeTime: Float = 60
    static weak var game: Game?               // (the debris pool for a skinned hull's pieces, ShipCombat.splitIfNeeded)
    private static var worldAt: ObjectIdentifier?
    static var made = 0                       // (counter)

    // A dead mob stays as its hulk (not on a ship's deck: that goes with the ship).
    static func add(_ m: Mob) {
        guard m.deck == nil, !mobs.contains(where: { $0 === m }) else { return }
        m.hulk = true
        m.hulkT = 0
        m.hurt = 0; m.fire = 0; m.hitFlash = 0
        m.vel = .zero
        m.mount = nil
        mobs.append(m)
        if mobs.count > most { mobs.removeFirst() }
        made += 1
    }

    // Each tick after the bodies (MobManager.corpseTick, which refills World.bodyBoxes): smoke, the boxes, leaving.
    static func tick(_ g: Game, _ dt: Float) {
        game = g
        let wid = ObjectIdentifier(g.world)
        if worldAt != wid { worldAt = wid; mobs.removeAll() }
        guard !mobs.isEmpty else { return }
        let p = g.player.pos
        mobs.removeAll { m in
            let dx = m.pos.x - p.x, dz = m.pos.z - p.z
            return dx * dx + dz * dz > leave * leave
        }
        for m in mobs {
            m.hulkT += dt
            let r = max(0.5, min(3.5, m.halfW)), h = max(0.8, min(3.5, m.height))
            if m.hulkT < smokeTime && Rand.float(in: 0..<1) < dt * 5 * (1 - m.hulkT / smokeTime) {
                g.particles.smoke(at: m.pos + V3(Rand.float(in: -r...r) * 0.6, h * Rand.float(in: 0.6...1.0), Rand.float(in: -r...r) * 0.6), dark: true)
            }
            let dx = m.pos.x - p.x, dz = m.pos.z - p.z
            if dx * dx + dz * dz < 32 * 32 {
                g.world.bodyBoxes.append((V3(m.pos.x - r, m.pos.y, m.pos.z - r), V3(m.pos.x + r, m.pos.y + h, m.pos.z + r)))
            }
        }
    }

    // A hulk's part colour, burnt in patches by its own hash (as the Vault's wrecks, ashWreckParts).
    static func burn(_ c: V3, _ m: Mob, _ i: Int) -> V3 {
        let h = hash3(Int(m.pos.x * 4), i, Int(m.pos.z * 4), 0x4B1C)
        switch h % 7 {
        case 0, 1, 2: return c * 0.28 + V3(0.02, 0.02, 0.02)                         // soot
        case 3: return simd_mix(c, V3(0.33, 0.19, 0.11), V3(repeating: 0.7))          // rust
        case 4: return c * 0.5
        default: return c * (0.62 + Float(h >> 8 & 15) / 100)                        // scorched paint
        }
    }
}

extension Game {
    // A hulk's smallest fittings thrown off as pieces of its plate (hatches, hooks, lamps, sights): `count` of them.
    func ashShed(_ m: Mob, _ plate: BlockID, count: Int) {
        let parts = mobModelParts(m)
        guard !parts.isEmpty, count > 0 else { return }
        let k = (m.sized ? 1 : m.scale) / 16
        let cy = cosf(m.yaw), sy = sinf(m.yaw)
        let mid = m.pos + V3(0, m.height * 0.4, 0)
        let small = parts.compactMap { p -> (Part, Float)? in
            let s = (p.mx - p.mn) * k
            let v = s.x * s.y * s.z
            return min(s.x, min(s.y, s.z)) > 0.05 && v < 0.4 ? (p, v) : nil
        }.sorted { $0.1 > $1.1 }.prefix(count)
        var seed = UInt32(truncatingIfNeeded: Int(m.pos.x * 7 + m.pos.z * 13) &* 2654435761)
        for (p, _) in small {
            let size = (p.mx - p.mn) * k
            let q = p.place((p.mn + p.mx) * 0.5, p.rotation) * k
            let at = m.pos + V3(cy * q.x + sy * q.z, q.y, -sy * q.x + cy * q.z)
            let out = at - mid + V3(0, 0.8, 0)
            let dir = simd_length(out) > 1e-3 ? simd_normalize(out) : V3(0, 1, 0)
            seed = seed &* 1664525 &+ 1013904223
            debris.bits(plate, at: at, size: SIMD3(size.x, size.y, size.z), direction: dir, count: 2, speed: 6, seed: seed)
        }
    }
}
