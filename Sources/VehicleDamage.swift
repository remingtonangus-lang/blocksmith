import Foundation
import simd

// H11: vehicle damage physics. A vessel of your own (ships, airships, carriages: not the AI's capital hulls) that hits
// the ground, a cliff or another vessel hard enough breaks up where it struck: the contact solver records each hull's
// hardest closing speed in a step (ShipManager.solve), and once a frame a crash over `safe` tears out the hull around
// the point of impact (more and wider the harder it hit, the dense frame of a heavy hull holding a little better),
// shakes the camera and hurts whoever is aboard. Torn-off parts drift away as their own wreckage (removeCells splits
// the hull). A hull that crashed waits a moment before it can be hurt again, so one collision is one crash.
enum VehicleDamage {
    static let safe: Float = 9                  // closing speed (b/s) a hull takes without harm
    static let wreck: Float = 30                // ... at which the impact tears the widest hole
    static let maxRadius: Float = 3.2
    static var crashes = 0                      // (tests)
}

extension ShipManager {
    func collisionDamage(_ dt: Float, _ g: Game) {
        for s in list where s.parent == nil {
            s.crashCD = max(0, s.crashCD - dt)
            let v = s.crashSpeed
            s.crashSpeed = 0
            guard v > VehicleDamage.safe, s.crashCD <= 0, !s.kinematic, s.role == nil, s.blockCount > 1 else { continue }
            s.crashCD = 0.6
            VehicleDamage.crashes += 1
            let k: Float = min(1, (v - VehicleDamage.safe) / (VehicleDamage.wreck - VehicleDamage.safe))
            let heft: Float = 1 / (1 + s.mass / 400)                  // a big, heavy hull spreads the blow
            let radius: Float = 0.7 + (VehicleDamage.maxRadius - 0.7) * k * (0.5 + 0.5 * heft)
            let at = s.crashAt
            let lc = s.toLocal(at)
            let ri = Int(ceilf(radius))
            var cells = Set<IVec3>()
            for dz in -ri...ri { for dy in -ri...ri { for dx in -ri...ri {
                let o = V3(Float(dx), Float(dy), Float(dz))
                guard simd_length(o) <= radius * (0.75 + 0.25 * hashf(dx, dy, dz, 4111)) else { continue }
                let c = IVec3(Int(floor(lc.x)) + dx, Int(floor(lc.y)) + dy, Int(floor(lc.z)) + dz)
                let b = s.grid.get(c.x, c.y, c.z)
                // The helm survives a crash you walk away from (a hull you can still steer home).
                if b != AIR && Blocks.hardness[Int(b)] >= 0 && s.helm != c { cells.insert(c) }
            } } }
            g.sfx(.explode, min(1, 0.3 + k), at: at)
            g.particles.explosion(at: at, power: 0.4 + k)
            if !cells.isEmpty { removeCells(s, cells, chipped: [], center: at, power: 4 + 8 * k, game: g) }
            // Whoever rides it is thrown about.
            if aboard?.root === s || pilot === s {
                g.addShake(0.4 + 0.5 * k)
                if g.survival {
                    let hurt = Int((v - VehicleDamage.safe) * 0.45)
                    if hurt > 0 { g.damage(hurt, "was killed in a crash") }
                }
            }
        }
    }
}
