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
            // P428 (Oct 24 10:17, "this giant log, which isn't the same log I hit, it morphed into something else"): a
            // felled tree is not a vehicle. Its crown came down faster than a crash, so it was torn apart where it struck
            // (leaf blobs left in ragged pieces, bits drifting off as wreckage, a blast's bang and shake) and ploughed a
            // pit in the ground under it. It lands as a tree (Felling: a thud and a rustle of leaves).
            if Felling.isFelled(s) { continue }
            let held = Momentum.held(s, dt)
            if (s.pushing || held || Momentum.underWay(s)) && !s.kinematic { Momentum.shove(s, dt, g) } else { s.shoveStore = 0 }
            s.pushing = false; s.pushInto = 0
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
            let riding = aboard?.root === s || pilot === s
            g.particles.explosion(at: at, power: 0.4 + k)
            Explosion.sparePlayer = riding
            if !cells.isEmpty { removeCells(s, cells, chipped: [], center: at, power: 4 + 8 * k, game: g) }
            Explosion.sparePlayer = false
            // Whoever rides it is thrown about. P472 (Oct 26 20:14, "with a wreck, I don't see why that needs to actually
            // hurt me"): shaken, not hurt; the vehicle takes the crash.
            if riding { g.addShake(0.4 + 0.5 * k) }
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
    static var broken = 0, shoved = 0, shoveCalls = 0                // (tests)
    static var sideContacts = 0, lastSide: (V3, V3, Float) = (.zero, .zero, 0)

    // P455 (Oct 25 14:19, the Ironstride Siege Carriage: "the trees are bullying it too much. This thing should be able
    // to just drive through trees and destroy them as it drives because it's so heavy. The physics and momentum and the
    // power of the engine should all work together... Should be a consistent physics engine, not something specific to
    // the crawlers"): a hull driven into something keeps pushing with its engine. The push banks up (its mass times the
    // throttle, a second's worth at most) and pays for what stands ahead of its bow at twelve times each block's
    // hardness, four at most a frame, the middle of the bow first: what it can't shift (natural ground and rock, masonry
    // and metal harder than 3, anything harder than its mass allows: a hundredth of its mass, so a heavy carriage snaps
    // trunks, timber walls and glass while a light car only gets through leaves, brush and glass) stops it as before. A trunk snapped at the hull brings the tree above down (Felling). Nothing is
    // left to pick up (P452). The crawlers' own crush stays (they drive by script, not by their engines).
    // A driven hull held up: its engine on (a quarter throttle or more) and it all but stopped along its heading for a
    // moment. (The contact solver's sideways contacts start it too, but a hull riding up on what it meets, wheels on the
    // trunk, meets it with its wheels, not its sides: questcheck --shovecheck, the carriage stopped dead at a row of
    // trunks with no side contact at all.)
    static func held(_ s: Ship, _ dt: Float) -> Bool {
        guard s.piloted, abs(s.throttleEase) > 0.25, s.engines > 0 else { s.heldT = 0; return false }
        let along = simd_dot(s.vel, s.dirToWorld(s.fwd)) * (s.throttleEase > 0 ? 1 : -1)
        s.heldT = along < 1.2 ? s.heldT + dt : 0
        return s.heldT > 0.25
    }

    // P455 (Oct 25 14:19-14:25; questcheck --shovecheck: the siege carriage rode up and over a three-high plank wall,
    // 15 of its 17 columns left standing): a heavy hull's wheels meet a wall's foot with an upward contact, so it climbed
    // instead of pushing and the shove never started. A hull of 300 t or more under power shoves all the time, so what
    // it could break (timber, glass, brush: up to a hundredth of its mass in hardness) goes before it rides up on it;
    // what it drives on (anything not standing above its lowest point) is left alone.
    static func underWay(_ s: Ship) -> Bool {
        s.piloted && abs(s.throttleEase) > 0.25 && s.mass >= 300 && s.engines > 0
    }

    static func shove(_ s: Ship, _ dt: Float, _ g: Game) {
        shoveCalls += 1
        guard s.engines > 0, s.blockCount > 1 else { return }
        let heft = s.mass / 100
        let power = s.mass * abs(s.throttleEase) * 0.25
        s.shoveStore = min(s.shoveStore + power * dt, power + 4)
        // The way it is driving, level.
        var dir = s.dirToWorld(s.fwd) * (s.throttleEase < 0 ? -1 : 1)
        dir.y = 0
        guard simd_length(dir) > 1e-3 else { return }
        dir = simd_normalize(dir)
        let w = g.world
        // What stands just ahead of its forward face: every hull cell and wheel with none of its own hull in front of it
        // (the bow, and a superstructure set further back that a tree's crown presses on: P455, the carriage stopped by
        // a spruce's leaves against its upper works), from a block under the wheels' axles up to its top.
        let gr = s.grid
        func own(_ q: V3) -> Bool {
            let l = s.toLocal(q)
            return gr.get(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z))) != AIR
        }
        let pts = (s.hull + s.wheels).map { s.toWorld($0) }
        var seen = Set<IVec3>()
        var cand: [(IVec3, Float, BlockID)] = []
        let mid = (s.worldMin + s.worldMax) * 0.5
        let floorY = s.worldMin.y + 0.25                     // (cells under this are what it drives on)
        for p in pts where !own(p + dir) {
            for k: Float in [0.6, 1.3] {
                let q = p + dir * k
                // (and the cell over it: a crown hanging onto the top edge of its bow held the carriage at a spruce)
                for dy in -1...1 {
                    let c = IVec3(Int(floor(q.x)), Int(floor(q.y)) + dy, Int(floor(q.z)))
                    guard c.y >= 1, c.y < CH - 1, Float(c.y + 1) > floorY, seen.insert(c).inserted else { continue }
                    let b = w.block(c.x, c.y, c.z)
                    guard b != AIR, Blocks.collide[Int(b)], !Blocks.isLiquid(b), w.blockEntities[c] == nil else { continue }
                    let hard = Blocks.hardness[Int(b)]
                    guard hard >= 0, hard <= min(heft, 3), !w.groundAt(c.x, c.y, c.z),
                          !SmoothTerrain.natural[Int(b)] || CapitalBase.isLog(b) || CapitalBase.isLeaf(b) else { continue }
                    // What it is touching, nearest the middle of its bow and lowest first: the trunk it presses on goes before its crown.
                    let off = V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 0.5) - mid
                    let side = simd_length(off - dir * simd_dot(off, dir))
                    cand.append((c, (k - 0.6) * 2 + side * 0.2 + Float(c.y) * 0.05, b))
                }
            }
        }
        // The block the contact solver found it pressing on, first (P455: a spruce crown against the carriage's
        // chamfered bow corner, off the straight line ahead of any hull cell, held it).
        if s.pushing {
            let q = s.pushAt - s.pushN * 0.3
            let c = IVec3(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z)))
            let b = w.block(c.x, c.y, c.z)
            let hard = Blocks.hardness[Int(b)]
            if c.y >= 1, c.y < CH - 1, Float(c.y + 1) > floorY, !seen.contains(c), b != AIR, Blocks.collide[Int(b)], !Blocks.isLiquid(b),
               w.blockEntities[c] == nil, hard >= 0, hard <= min(heft, 3), !w.groundAt(c.x, c.y, c.z),
               !SmoothTerrain.natural[Int(b)] || CapitalBase.isLog(b) || CapitalBase.isLeaf(b) {
                cand.append((c, -1, b))
            }
        }
        guard !cand.isEmpty else { return }
        cand.sort { $0.1 < $1.1 }
        var gone: [(IVec3, BlockID)] = []
        for (p, _, b) in cand where gone.count < 4 {
            let cost = max(0.4, Blocks.hardness[Int(b)]) * 12
            guard cost <= s.shoveStore else { break }
            s.shoveStore -= cost
            gone.append((p, b))
        }
        guard !gone.isEmpty else { return }
        shoved += gone.count
        for (i, (p, b)) in gone.enumerated() {
            if i < 6 { g.particles.blockBreak(b, at: p) }
            for st in Explosion.blastDrops(b) { g.drops.spawn(st, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)) }
            _ = w.setBlockAsync(p.x, p.y, p.z, AIR)
            g.debris.blockChanged(p)
        }
        for (p, b) in gone where CapitalBase.isLog(b) { g.fellCheck(p, b) }
        g.blockSound(g.audioBreakSound(gone[0].1), at: gone[0].0)
    }

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
        for y in stride(from: max(1, cy - ri), through: min(CH - 2, cy + ri), by: 1) { for z in (cz - ri)...(cz + ri) { for x in (cx - ri)...(cx + ri) {
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
            for st in Explosion.blastDrops(b) { g.drops.spawn(st, at: mid) }                      // (P452: smashed is gone)
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
