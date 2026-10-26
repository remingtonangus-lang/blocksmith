import Foundation
import simd

// P461 (Remington, Oct 25 16:43, flying the taken dropship near a volcano: "Just make it so blocks like metal and stuff
// just slowly melt in when put in lava... if I like drop this drop ship into the volcano, the lava just degrades it"):
// a hull's blocks touching lava heat up, crack and melt away. Lava holds a hull up as water does, denser and thick
// (ShipPhysics: integrateForces), so a ship dropped in settles, rides low and loses its bottom layer by layer. Planks go
// in about 14 s, an iron block in 26, warship plate in 38, the hardest in a minute; obsidian and unbreakable blocks
// never. Nothing melted drops. Checked twice a second, and a ship's cells are only looked at while one of its
// buoyancy buckets is in lava.
extension ShipManager {
    static let meltEvery: Float = 0.5

    // Seconds in lava before a block melts; nil: it never does.
    static func meltTime(_ b: BlockID) -> Float? {
        let h = Blocks.hardness[Int(b)]
        guard b != AIR, h >= 0, h < 40 else { return nil }
        return min(60, 6 + 4 * h)
    }

    func meltTick(_ dt: Float, game: Game?) {
        meltClock += dt
        guard meltClock >= ShipManager.meltEvery else { return }
        let step = meltClock
        meltClock = 0
        var rd = ShipBlockReader(world)
        let fk = Blocks.fluidKind
        for s in list where !s.asleep && s.blockCount > 0 {
            // Cheap first: a bucket's centre or bottom (or the cell under it) in lava; the highest such cell.
            var top = Int.min
            for b in s.buckets {
                let c = s.toWorld(b.centre)
                let x = Int(floor(c.x)), z = Int(floor(c.z))
                let y0 = Int(floor(c.y - b.height * 0.5)) - 1, y1 = Int(floor(c.y))
                for y in y0...max(y0, y1) where fk[Int(rd.raw(x, y, z))] == 2 { top = max(top, y) }
            }
            guard top != Int.min else { continue }
            // Then every lava cell in the hull's bounds up to there, and the hull cells beside or in it.
            let lo = simd_int3(Int32(floor(s.worldMin.x)) - 1, Int32(floor(s.worldMin.y)) - 1, Int32(floor(s.worldMin.z)) - 1)
            let hi = simd_int3(Int32(floor(s.worldMax.x)) + 1, Int32(min(Float(top + 1), s.worldMax.y)), Int32(floor(s.worldMax.z)) + 1)
            guard lo.y <= hi.y else { continue }
            let g = s.grid
            var hot = Set<IVec3>()
            // Only the hull's faces open to lava heat: an empty cell of the hull's grid (or one past its edge) that
            // sits in lava heats the blocks round it. A block inside the hull waits until the one over it has gone,
            // so a hull melts layer by layer instead of all through at once (the lava under a ship isn't displaced).
            for y in Int(lo.y)...Int(hi.y) { for z in Int(lo.z)...Int(hi.z) { for x in Int(lo.x)...Int(hi.x) where fk[Int(rd.raw(x, y, z))] == 2 {
                let l = s.toLocal(V3(Float(x), Float(y), Float(z)) + 0.5)
                let cell = IVec3(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z)))
                guard g.get(cell.x, cell.y, cell.z) == AIR else { continue }
                for d in World.allDirs {
                    let n = IVec3(cell.x + d.x, cell.y + d.y, cell.z + d.z)
                    if g.get(n.x, n.y, n.z) != AIR { hot.insert(n) }
                }
            } } }
            guard !hot.isEmpty else { continue }
            var gone = Set<IVec3>(), cracked: [IVec3] = []
            for cell in hot {
                guard let t = ShipManager.meltTime(g.get(cell.x, cell.y, cell.z)) else { continue }
                let heat = s.melt[cell, default: 0] + step
                if heat >= t { gone.insert(cell); s.melt.removeValue(forKey: cell); continue }
                s.melt[cell] = heat
                // The cracks grow as it heats (the capital hulls' chip overlay, level 1-7), eaten from below (face 3).
                let lv = UInt8(1 + Int(heat / t * 6))
                let cur = s.damage[cell]
                if (cur ?? 0) & 31 < lv { s.damage[cell] = (cur.map { $0 & ~31 } ?? 3 << 5) | lv; cracked.append(cell) }
            }
            if let g = game, let first = gone.first ?? cracked.first {
                let at = s.toWorld(V3(Float(first.x), Float(first.y), Float(first.z)) + 0.5)
                for _ in 0..<3 { g.particles.smoke(at: at + V3(0, 0.6, 0)) }
                if !gone.isEmpty { g.sfx(.fizz, 0.8, at: at) }
            }
            if gone.isEmpty {
                if !cracked.isEmpty { s.mesh.rebuildAround(s, cracked, device: world.device, queue: meshQueue) }
                continue
            }
            ShipManager.melted += gone.count
            removeCells(s, gone, chipped: cracked, center: s.pos, power: 0, game: nil)    // (nothing drops)
        }
    }
    static var melted = 0          // (harness tally)
}
