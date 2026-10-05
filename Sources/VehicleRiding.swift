import Foundation
import simd

// Riding moving vehicles: who belongs to a ship's frame and what holds them up there.
//
// A body rides a ship (moves and collides in its frame, ShipPlay.shipPlayerUpdate / Mob.update with Mob.deck, and is
// carried by ShipManager.update) once something of the ship holds it: a ship block under its feet, a ship ladder it
// is on or next to, or the hull's enclosed air around it. It stays aboard while it is over or about the hull, and
// leaves when it stands on the world's ground (the foot of a ramp, the ground beside a ladder, under a hull) or is
// clear of the hull. Standing next to a moving vehicle, or walking under its belly, no longer drags you along.
extension ShipManager {
    // The ship's own block (or one of its turrets') at a ship-space cell: never the world block frameBlock falls back to.
    func shipCell(_ s: Ship, _ x: Int, _ y: Int, _ z: Int) -> BlockID {
        let b = s.grid.get(x, y, z)
        if b != AIR || s.children.isEmpty { return b }
        let p = s.toWorld(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))
        for t in s.children where p.x > t.worldMin.x && p.x < t.worldMax.x && p.y > t.worldMin.y && p.y < t.worldMax.y
            && p.z > t.worldMin.z && p.z < t.worldMax.z {
            let l = t.toLocal(p)
            let tb = t.grid.get(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z)))
            if tb != AIR { return tb }
        }
        return AIR
    }

    // Feet at l (ship space) rest on the ship: a collidable ship block under a corner or the middle of the footprint.
    func holdsRider(_ s: Ship, _ l: V3, halfW: Float) -> Bool {
        let y = Int(floor(l.y - 0.08))
        let r = halfW * 0.95
        for (dx, dz) in [(Float(0), Float(0)), (-r, -r), (r, -r), (-r, r), (r, r)] {
            let b = shipCell(s, Int(floor(l.x + dx)), y, Int(floor(l.z + dz)))
            if b != AIR && Blocks.collide[Int(b)] { return true }
        }
        return false
    }

    // At a ladder of the ship: the body overlaps a ladder cell (ship ladders are no obstacle in world space, so a
    // climber walks into the rungs and is taken into the ship's frame there, where the ladder is exact; standing at
    // its foot it stays aboard, holding on, until it steps away).
    func atShipLadder(_ s: Ship, _ l: V3, halfW: Float) -> Bool {
        let r = halfW - 0.05
        for dy in [Float(0.1), 0.9, 1.7] {
            for (dx, dz) in [(Float(0), Float(0)), (-r, 0), (r, 0), (0, -r), (0, r)] {
                let b = s.grid.get(Int(floor(l.x + dx)), Int(floor(l.y + dy)), Int(floor(l.z + dz)))
                if Player.climbable(b) { return true }
            }
        }
        return false
    }

    // In the hull's enclosed air (a cabin, a bay) at the body's middle.
    func insideHull(_ s: Ship, _ l: V3) -> Bool {
        let x = Int(floor(l.x)), y = Int(floor(l.y + 0.5)), z = Int(floor(l.z))
        guard s.grid.inside(x, y, z), s.dryMask.count == s.grid.blocks.count else { return false }
        return s.dryMask[s.grid.index(x, y, z)]
    }

    // Whether a body at world position w, not yet aboard s, boards it now.
    func canBoard(_ s: Ship, _ w: V3, halfW: Float) -> Bool {
        let l = s.toLocal(w)
        return holdsRider(s, l, halfW: halfW) || atShipLadder(s, l, halfW: halfW) || insideHull(s, l)
    }

    // Capital hulls: many blocks set at once (a ramp lowering), counts and column floors kept current, one remesh.
    func setBlocks(_ s: Ship, _ cells: [(IVec3, BlockID)]) {
        guard s.kinematic else { for (c, b) in cells { setBlock(s, c, b) }; return }
        let kinds = ShipParts.kinds
        var changed: [IVec3] = []
        var cols = Set<Int>()
        for (c, b) in cells where s.grid.inside(c.x, c.y, c.z) {
            let old = s.grid.get(c.x, c.y, c.z)
            if old == b { continue }
            if kinds[Int(old)] == .engine { s.engines -= 1 }
            if kinds[Int(b)] == .engine { s.engines += 1 }
            if old == AIR { s.blockCount += 1 } else if b == AIR { s.blockCount -= 1 }
            s.damage.removeValue(forKey: c)
            s.grid.set(c.x, c.y, c.z, b)
            if b == AIR { s.blockEntities.removeValue(forKey: c) }
            changed.append(c)
            cols.insert(c.x + c.z * s.grid.sx)
        }
        if changed.isEmpty { return }
        let g = s.grid
        for k in cols where k < s.colMin.count {
            let x = k % g.sx, z = k / g.sx
            var lo = Int16.max
            for y in 0..<g.sy where Blocks.collide[Int(g.blocks[g.index(x, y, z)])] { lo = Int16(y); break }
            s.colMin[k] = lo
        }
        s.mesh.rebuildAround(s, changed, device: world.device, queue: meshQueue)
    }
}
