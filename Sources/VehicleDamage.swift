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
    static var crashes = 0, wingsLost = 0       // (tests)
}

extension ShipManager {
    func collisionDamage(_ dt: Float, _ g: Game) {
        for s in list where s.parent == nil {
            s.crashCD = max(0, s.crashCD - dt)
            let v = s.crashSpeed
            s.crashSpeed = 0
            // P262: a heavy, fast hull breaks through what it hits in the world (any physics hull, AI or yours).
            var gave = false
            if v > Momentum.minSpeed && s.crashWorld && !s.kinematic && s.crashCD <= 0 { gave = Momentum.ram(s, v, g) }
            // (P435: the salvaged fighter is flown as a Capital plane, role "capplane", yet it is his own and breaks up.)
            guard v > VehicleDamage.safe, s.crashCD <= 0, !s.kinematic, s.role == nil || s.name == AshWrecks.fighterName, s.blockCount > 1 else { continue }
            s.crashCD = 0.6
            VehicleDamage.crashes += 1
            var k: Float = min(1, (v - VehicleDamage.safe) / (VehicleDamage.wreck - VehicleDamage.safe))
            if gave { k *= 0.55 }                                       // P262 (e): the obstacle gave way
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
            // P435 (Oct 24 15:53, "that should have torn its wing off when I hit the pillar"): a wing struck hard
            // enough comes off whole from where it was hit out to its tip (the split hull drifts away as wreckage).
            if v > VehicleDamage.safe + 4, !s.wings.isEmpty {
                let right = simd_normalize(simd_cross(s.fwd, V3(0, 1, 0)))
                let near = s.wings.min { simd_length_squared($0 - lc) < simd_length_squared($1 - lc) }
                if let wc = near, simd_length(wc - lc) < 1.6 {
                    let side = simd_dot(wc - s.com, right)
                    if abs(side) > 1.4 {
                        for w in s.wings where simd_dot(w - s.com, right) * (side > 0 ? 1 : -1) >= abs(side) - 0.5 {
                            cells.insert(IVec3(Int(floor(w.x)), Int(floor(w.y)), Int(floor(w.z))))
                        }
                        VehicleDamage.wingsLost += 1
                    }
                }
            }
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

// P262 (Oct 14 12:16, "a fast, heavy object breaks through blocks it hits, scaled by speed and mass"). A physics hull
// (ship, airship, vehicle, a wreck coming down) that hits the world faster than 6.5 blocks a second breaks the blocks in its way:
// a budget of mass x (speed - 6) x 0.05 pays for blocks at four times their hardness each, nearest the point of impact
// first and only ahead of it, within a ball that grows with the budget (a rowing boat snaps leaves, glass and dirt; a
// laden ship or a falling dropship ploughs through walls and trees); bedrock and anything harder than 20 never breaks.
// What breaks makes the block's own break sound and particles (a debris rain on a big breach, flying pieces in
// realistic worlds); a third drop as items, containers spill. Breaking through gives back part of the speed the
// contact took (it ploughs on), and the hull's own crash damage is softer (VehicleDamage). Polygon worlds take a bowl
// in the ground as a blast does.
enum Momentum {
    static let minSpeed: Float = 6.5               // a gentle landing or bump breaks nothing
    static let maxCells = 48
    static var broken = 0                                            // (tests)

    // Returns true when it broke something.
    static func ram(_ s: Ship, _ v: Float, _ g: Game) -> Bool {
        let budget = s.mass * (v - 6) * 0.05
        guard budget >= 1 else { return false }
        let w = g.world
        var dir = -s.crashN
        if simd_length(s.crashVel) > 1 { dir = simd_normalize(simd_normalize(s.crashVel) + dir) }
        let c = s.crashAt + dir * 0.5
        let reach: Float = min(4, 0.8 + budget.squareRoot() * 0.35)
        let ri = Int(ceilf(reach))
        let cx = Int(floor(c.x)), cy = Int(floor(c.y)), cz = Int(floor(c.z))
        var cand: [(IVec3, Float, BlockID)] = []
        for y in max(1, cy - ri)...min(CH - 2, cy + ri) { for z in (cz - ri)...(cz + ri) { for x in (cx - ri)...(cx + ri) {
            let m = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
            let off = m - c, d = simd_length(off)
            guard d <= reach, d < 0.8 || simd_dot(off / d, dir) > -0.3 else { continue }
            let b = w.block(x, y, z)
            guard b != AIR, Blocks.collide[Int(b)], !Blocks.isLiquid(b) else { continue }
            let hard = Blocks.hardness[Int(b)]
            guard hard >= 0, hard <= 20 else { continue }
            cand.append((IVec3(x, y, z), d, b))
        } } }
        guard !cand.isEmpty else { return false }
        cand.sort { $0.1 < $1.1 }
        var left = budget
        var gone: [(IVec3, BlockID)] = []
        for (p, _, b) in cand where gone.count < maxCells {
            let cost = max(0.4, Blocks.hardness[Int(b)]) * 4
            guard cost <= left else { continue }
            left -= cost
            gone.append((p, b))
        }
        guard !gone.isEmpty else { return false }
        broken += gone.count
        for (i, (p, b)) in gone.enumerated() {
            let mid = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
            if i < 12 { g.particles.blockBreak(b, at: p) }
            if i < 6 && World.realistic && Blocks.render[Int(b)] == RenderType.cube.rawValue {
                g.debris.shatter(b, cell: p, impact: c, direction: dir, count: 3, speed: min(14, v * 0.6) + 1,
                                 seed: hash3(p.x, p.y, p.z, 0xA11E), crowding: 0.3)
            }
            if hashf(p.x, p.y, p.z, 0xA11F) < 0.34 {
                for st in Mining.drops(b, ItemStack(Items.id("netherite_pickaxe"), 1)) { g.drops.spawn(st, at: mid) }
            }
            if let be = w.blockEntities.removeValue(forKey: p) {
                for st in be.container.slots where !st.isEmpty { g.drops.spawn(st, at: mid) }
                be.container.slots = Array(repeating: .empty, count: be.container.slots.count)
            }
            _ = w.setBlockAsync(p.x, p.y, p.z, AIR)
            g.debris.blockChanged(p)
        }
        for (p, _) in gone { w.scheduleFluid(around: p) }
        g.blockSound(g.audioBreakSound(gone[0].1), at: gone[0].0)
        if gone.count >= 8 { g.sfx(.debrisRain, min(1, 0.4 + Float(gone.count) / 40), at: c) }
        if w.keepsField || w.fieldTerrain {
            let far = gone.map { simd_length(V3(Float($0.0.x), Float($0.0.y), Float($0.0.z)) + 0.5 - c) }.max() ?? 1
            _ = w.carve(at: c, radius: min(reach, far + 0.3), mode: .shape)
        }
        // It ploughs on: part of the speed the contact took comes back, more when it had budget to spare.
        let lost = s.crashVel - s.vel
        if simd_dot(lost, dir) > 0 { s.vel += lost * (0.35 + 0.35 * min(1, left / budget)) }
        return true
    }
}
