import Foundation
import simd

// P387 (Remington, Oct 20, "placed blocks meet the ground"): in a field world a block placed on a slope kept its cell,
// so a gap showed under its downhill side (the drawn ground runs through the cells, the block sits on its floor). Placing
// a block that rests on its cell's floor (a full block, a lamp, a chest...) on the ground now raises the ground under
// its footprint to that floor, with a 45-degree skirt out to the ground round it (no cliff), as a field edit in the
// edited band (FineField: half-block samples there, so the skirt is smooth); land it doesn't reach is unchanged. The
// raised ground is ground: breaking the block leaves it. Saved with the chunk's field (its own format).
extension World {
    // BS_MEET=0: blocks placed on field ground as before P387 (before/after checks).
    static let meetGroundOn = ProcessInfo.processInfo.environment["BS_MEET"] != "0"

    // Does a block of this state rest on its cell's floor (so the ground under it should reach that floor)?
    static let restsOnFloor: [Bool] = {
        var out = [Bool](repeating: false, count: Blocks.render.count)
        for b in 0..<out.count where Blocks.collide[b] && GroundDrape.seat[b] == 0 && !Blocks.isLiquid(BlockID(b)) {
            if Blocks.fullCollide[b] { out[b] = true; continue }
            let bx = Blocks.boxes[b]
            guard !bx.isEmpty else { continue }
            var y0 = 16, x0 = 16, x1 = 0, z0 = 16, z1 = 0
            for q in bx { y0 = min(y0, Int(q.y0)); x0 = min(x0, Int(q.x0)); x1 = max(x1, Int(q.x1)); z0 = min(z0, Int(q.z0)); z1 = max(z1, Int(q.z1)) }
            out[b] = y0 == 0 && x1 - x0 >= 10 && z1 - z0 >= 10           // (on the floor and most of the cell wide)
        }
        return out
    }()

    // The largest gap (blocks) between the floor of cell (x, y, z) and the field's ground under its footprint (its
    // corners, edge middles and middle, each searched down a block and a half); 0 where the ground reaches the floor.
    func floorGap(_ x: Int, _ y: Int, _ z: Int) -> Float {
        var worst: Float = 0
        for k in 0..<9 {
            let px = Float(x) + 0.02 + Float(k % 3) * 0.48, pz = Float(z) + 0.02 + Float(k / 3) * 0.48
            let o = V3(px, Float(y) + 0.02, pz)
            guard fieldDensity(at: o) <= 0 else { continue }
            if let h = fieldRaySegment(o, V3(0, -1, 0), from: 0, to: 1.5) { worst = max(worst, Float(y) - h.at.y) } else { worst = max(worst, 1.5) }
        }
        return worst
    }

    // P387: after a block that rests on its floor is placed at (x, y, z) on field ground, the ground under it rises to
    // the floor. Returns the cells that turned to ground.
    @discardableResult
    func meetGround(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) -> Int {
        guard World.meetGroundOn, fieldTerrain, frame == nil, World.restsOnFloor[Int(id)], y > 0 else { return 0 }
        // On the ground only: what stands on a built block is the building's business.
        let under = builtBlock(x, y - 1, z)
        guard !Blocks.collide[Int(under)] else { return 0 }
        let gap = floorGap(x, y, z)
        guard gap > 0.03 else { return 0 }
        // The shape: solid up to the floor over the footprint, falling away at 45 degrees round it.
        let fy = Float(y), x0 = Float(x), x1 = Float(x + 1), z0 = Float(z), z1 = Float(z + 1)
        // (a flat apron a third of a block wide round the foot first: the drawn ground interpolates between half-block
        // samples, so a skirt starting right at the footprint's edge still showed a third of a block of gap under it)
        let apron: Float = 0.35, skirt = min(2.5, gap + 0.5) + apron
        func inside(_ p: V3) -> Float {
            let dx = max(0, x0 - p.x, p.x - x1), dz = max(0, z0 - p.z, p.z - z1)
            let out = (dx * dx + dz * dz).squareRoot()
            if out > skirt { return -4 }
            // (about the distance to the surface: straight up over the footprint and apron, across the 45-degree skirt round them)
            return out <= apron ? fy - p.y : (fy - (out - apron) - p.y) * 0.7071
        }
        let lo = IVec3(x - 3, max(0, y - 3), z - 3), hi = IVec3(x + 3, y, z + 3)
        return fieldFill(lo, hi, inside, keep: IVec3(x, y, z))
    }

    // Fills the field's ground in the cells lo...hi (and their fine samples) up to the shape `inside` (> 0 inside, about
    // the distance to its surface): each sample becomes the larger of what it was and the shape, so the ground only
    // grows. Never into a built block's cell, nor `keep`. Material from the ground round each new cell.
    func fieldFill(_ lo: IVec3, _ hi: IVec3, _ inside: (V3) -> Float, keep: IVec3) -> Int {
        var flipped = 0
        var touched: [(Chunk, Int)] = []
        func touch(_ c: Chunk, _ sy: Int) { if !touched.contains(where: { $0.0 === c && $0.1 == sy }) { touched.append((c, sy)) } }
        // (P440: the cells whose samples changed, for the sections the frame meshes)
        var clo = IVec3(Int.max, Int.max, Int.max), chi = IVec3(Int.min, Int.min, Int.min)
        func grow(_ p: IVec3) {
            clo = IVec3(min(clo.x, p.x), min(clo.y, p.y), min(clo.z, p.z)); chi = IVec3(max(chi.x, p.x), max(chi.y, p.y), max(chi.z, p.z))
        }
        // The fine samples first (given from the cells as they are before the fill), then the cells.
        let ctr = V3(Float(lo.x + hi.x + 1) * 0.5, Float(lo.y + hi.y + 1) * 0.5, Float(lo.z + hi.z + 1) * 0.5)
        let r = Float(max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z) + 1) * 0.5
        for (c, sy, fresh) in prepareFine(ctr, radius: r) {
            guard var f = c.blocks.fine[sy] else { continue }
            c.blocks.fine[sy] = nil
            let ox = c.cx * CS, oy = sy * 16, oz = c.cz * CS
            let fx0 = max(0, (lo.x - ox) * 2), fx1 = min(31, (hi.x - ox) * 2 + 1)
            let fy0 = max(0, (lo.y - oy) * 2), fy1 = min(31, (hi.y - oy) * 2 + 1)
            let fz0 = max(0, (lo.z - oz) * 2), fz1 = min(31, (hi.z - oz) * 2 + 1)
            var any = false
            if fx0 <= fx1 && fy0 <= fy1 && fz0 <= fz1 {
                for fy in fy0...fy1 { for fz in fz0...fz1 { for fx in fx0...fx1 {
                    let ci = Chunk.index(fx >> 1, oy + (fy >> 1), fz >> 1)
                    if c.blocks.raw(ci) != AIR { continue }                     // (a fill never swallows a built block)
                    if ox + (fx >> 1) == keep.x && oy + (fy >> 1) == keep.y && oz + (fz >> 1) == keep.z { continue }
                    let p = V3(Float(ox) + (Float(fx) + 0.5) * 0.5, Float(oy) + (Float(fy) + 0.5) * 0.5, Float(oz) + (Float(fz) + 0.5) * 0.5)
                    let k = FineField.index(fx, fy, fz)
                    let q = FieldTerrain.q(max(FieldTerrain.f(f[k]), inside(p)))
                    if q != f[k] { f[k] = q; any = true; grow(IVec3(ox + (fx >> 1), oy + (fy >> 1), oz + (fz >> 1))) }
                } } }
            }
            if any || !fresh { c.blocks.fine[sy] = f }
            if any { c.modified = true; touch(c, sy) }
        }
        for y in lo.y...hi.y where y >= 0 && y < CH {
            for z in lo.z...hi.z { for x in lo.x...hi.x {
                guard let c0 = chunkAt(x, z) else { continue }
                let c = editing(c0)
                guard c.blocks.isField else { continue }
                if x == keep.x && y == keep.y && z == keep.z { continue }
                let i = Chunk.index(mod(x, CS), y, mod(z, CS))
                if c.blocks.raw(i) != AIR { continue }
                let d0 = FieldTerrain.f(c.blocks.density(i))
                let q = FieldTerrain.q(max(d0, inside(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))))
                if q == c.blocks.density(i) { continue }
                let was = d0 > 0, now = q > 0
                if was != now {
                    c.blocks.setDensity(i, max(q, 1), material: fieldNeighbourMaterial(x, y, z), follow: false)
                    flipped += 1
                    c.recomputeHeight(mod(x, CS), mod(z, CS))
                } else {
                    c.blocks.setDensity(i, q, material: nil, follow: false)
                }
                c.modified = true
                touch(c, y >> 4)
                grow(IVec3(x, y, z))
            } }
        }
        // (as fieldSphere: the sections round each changed one remesh, now)
        var all: [(Chunk, Int)] = []
        for (c, sy) in touched {
            for dz in -1...1 { for dx in -1...1 {
                guard let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)] else { continue }
                for s in max(0, sy - 1)...min(NSEC - 1, sy + 1) where !all.contains(where: { $0.0 === n && $0.1 == s }) { all.append((n, s)) }
            } }
        }
        for (n, s) in all { n.sections[s].version += 1 }
        // (P440: only the sections within a cell of a changed sample mesh on the frame; the rest of the ring follows on a
        // worker ahead of the queue)
        for (n, s) in all where !deferRemesh && clo.x <= chi.x {
            let x0 = n.cx * CS, z0 = n.cz * CS, y0 = s * 16
            guard chi.x + 1 >= x0 && clo.x - 1 < x0 + 16 && chi.z + 1 >= z0 && clo.z - 1 < z0 + 16 && chi.y + 1 >= y0 && clo.y - 1 < y0 + 16 else { continue }
            remeshSync(n, s)
        }
        if !touched.isEmpty { fieldStamp &+= 1 }
        return flipped
    }
}
