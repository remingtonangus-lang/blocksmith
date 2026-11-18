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
    static let meetGroundOn = Env.all["BS_MEET"] != "0"
    static let oldMeet = Env.all["BS_OLDMEET"] == "1"

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

    // Ledger 273 (bug hunt a, Fable Nov 18: "nothing floats over the ground or sinks under it, the ground under it
    // closes with no gap"): what stands on its cell's floor but is too narrow to count as resting on it (a door, a
    // fence or wall post, a pane, a rail, a ladder, a lever...) kept whatever the slope gave it: on 420 placements on
    // sloped Polygons ground, doors, fences and rails floated up to half a block over the downhill side or stood half a
    // block deep in the uphill ground in four of every five. Built pieces stay on the grid, so the ground comes to
    // them: it rises under the cell to its floor (meetGround) and falls inside the cell to it (floorPad).
    // BS_OLDFLOORMEET=1: as before.
    static let oldFloorMeet = Env.all["BS_OLDFLOORMEET"] == "1"
    static let standsOnFloor: [Bool] = {
        var out = [Bool](repeating: false, count: Blocks.render.count)
        for b in 0..<out.count where !restsOnFloor[b] && GroundDrape.seat[b] == 0 && !Blocks.isLiquid(BlockID(b))
            && Blocks.render[b] != RenderType.cross.rawValue && Blocks.render[b] != RenderType.liquid.rawValue
            && Blocks.render[b] != RenderType.wire.rawValue {          // (wire lies on the drawn ground: GroundDrape)
            if Blocks.connectKind[b] != 0 { out[b] = true; continue }      // (fences, walls, panes: their post from the floor)
            let bx = Blocks.boxes[b]
            guard !bx.isEmpty, bx.map({ Int($0.y0) }).min() == 0 else { continue }
            out[b] = true
        }
        return out
    }()
    static func meetsGround(_ id: BlockID) -> Bool { restsOnFloor[Int(id)] || (!oldFloorMeet && standsOnFloor[Int(id)]) }

    // Ledger 273: the ground inside the cell of something standing on its floor falls to that floor, rising again at
    // 45 degrees round the cell to the ground beside it (a level pad, not a cliff). Returns the cells that changed.
    @discardableResult
    func floorPad(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) -> Int {
        guard !World.oldFloorMeet, World.meetGroundOn, fieldTerrain, frame == nil, World.standsOnFloor[Int(id)], y > 0, y + 2 < CH else { return 0 }
        guard !Blocks.collide[Int(builtBlock(x, y - 1, z))] || !Blocks.fullCollide[Int(builtBlock(x, y - 1, z))] else { return 0 }
        // (only where the ground stands over the floor somewhere in the cell)
        var over = false
        for k in 0..<9 where !over {
            let px = Float(x) + 0.1 + Float(k % 3) * 0.4, pz = Float(z) + 0.1 + Float(k / 3) * 0.4
            if fieldDensity(at: V3(px, Float(y) + 0.06, pz)) > 0 { over = true }
        }
        guard over else { return 0 }
        let fy = Float(y), x0 = Float(x), x1 = Float(x + 1), z0 = Float(z), z1 = Float(z + 1)
        let apron: Float = 0.15
        func most(_ p: V3) -> Float {
            let dx = max(0, x0 - p.x, p.x - x1), dz = max(0, z0 - p.z, p.z - z1)
            let out = (dx * dx + dz * dz).squareRoot()
            if out > 1.2 { return 8 }
            return out <= apron ? fy - p.y : (fy + (out - apron) - p.y) * 0.7071
        }
        return fieldFill(IVec3(x - 2, y, z - 2), IVec3(x + 2, y + 2, z + 2), most, keep: IVec3(x, y, z), cut: true)
    }

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
        guard World.meetGroundOn, fieldTerrain, frame == nil, World.meetsGround(id), y > 0 else { return 0 }
        // On the ground only: what stands on a built block is the building's business.
        let under = builtBlock(x, y - 1, z)
        guard !Blocks.collide[Int(under)] else { return 0 }
        let gap = floorGap(x, y, z)
        guard gap > 0.03 else { return 0 }
        // Ledger 130 (Nov 14, building a house on a beach: "All that sand just spawned", "the ground just fucked up my
        // house", "that shit was just hanging in the air", "look what happened inside"): a block set out from a wall's
        // top, a block and more over the ground, raised a mound of ground up to its floor with a skirt nearly three
        // blocks wide, into the rooms. The ground now rises only under a block set down on it (a gap of 0.8 at
        // most; the caller says whether it was placed on ground), and its skirt is at most a block wide.
        // BS_OLDMEET=1: as before.
        // (ledger 273: on a steep slope the downhill corner of a block set down on the ground is a block below its
        // floor while its middle stands half a block over the ground: the middle tells whether it was set down)
        if !World.oldMeet && World.oldFloorMeet && gap > 0.8 { return 0 }
        if !World.oldMeet && !World.oldFloorMeet && gap > 0.8 {
            let o = V3(Float(x) + 0.5, Float(y) + 0.02, Float(z) + 0.5)
            guard fieldDensity(at: o) <= 0, let h = fieldRaySegment(o, V3(0, -1, 0), from: 0, to: 1.5), Float(y) - h.at.y <= 0.8 else { return 0 }
        }
        // Builders' Grounds (Nov 14): over a drop, not on the ground. A lintel over an arch, a bridge deck, an eave, a
        // block put against a wall's side found no ground a block and a half under its floor and the fill still ran, a
        // plug of earth three cells deep hung under it in the air (ten cells grew in a stone gate's opening as the agent
        // laid its lintel; 63 round it). The ground meets a block only where it lies under the block: under its middle
        // and most of its footprint. BS_OLDMEET=1: as before.
        if !World.oldMeet {
            var none = 0, middle = false
            for k in 0..<9 {
                let px = Float(x) + 0.02 + Float(k % 3) * 0.48, pz = Float(z) + 0.02 + Float(k / 3) * 0.48
                let o = V3(px, Float(y) + 0.02, pz)
                if fieldDensity(at: o) > 0 { continue }
                if fieldRaySegment(o, V3(0, -1, 0), from: 0, to: 1.5) == nil { none += 1; if k == 4 { middle = true } }
            }
            if middle || none >= 3 { return 0 }
        }
        // The shape: solid up to the floor over the footprint, falling away at 45 degrees round it.
        let fy = Float(y), x0 = Float(x), x1 = Float(x + 1), z0 = Float(z), z1 = Float(z + 1)
        // (a flat apron a third of a block wide round the foot first: the drawn ground interpolates between half-block
        // samples, so a skirt starting right at the footprint's edge still showed a third of a block of gap under it)
        let apron: Float = 0.35
        let run: Float = World.oldMeet ? min(2.5, gap + 0.5) : min(1.0, gap + 0.2)
        let skirt = run + apron
        // (the skirt's fall: 45 degrees, steeper where a block's width would not reach the ground)
        let fall: Float = World.oldMeet ? 1 : max(1, (gap + 0.2) / run)
        let norm: Float = 1 / (1 + fall * fall).squareRoot()
        func inside(_ p: V3) -> Float {
            let dx = max(0, x0 - p.x, p.x - x1), dz = max(0, z0 - p.z, p.z - z1)
            let out = (dx * dx + dz * dz).squareRoot()
            if out > skirt { return -4 }
            // (about the distance to the surface: straight up over the footprint and apron, across the skirt round them)
            return out <= apron ? fy - p.y : (fy - (out - apron) * fall - p.y) * norm
        }
        let lo = IVec3(x - 3, max(0, y - 3), z - 3), hi = IVec3(x + 3, y, z + 3)
        return fieldFill(lo, hi, inside, keep: IVec3(x, y, z))
    }

    // Ledger 160 (Nov 15 08:45:01, bricks put into a hollow he had dug beside a floor: "Can't place blocks in here. And
    // look, the ground doesn't come back to it"; "Still pretty unsatisfying, building"; 08:46:27 "Nearly unplayable").
    // A blow on the ground takes a cell and rounds the ground of the cells beside it down into a bowl; a block put back
    // in that cell is a cube, so the bowl stayed open all round it. The ground of the cells round a full block he
    // places now stands up to it again: in each cell beside it that the blow only rounded off (its middle still within
    // half a block of the level), up to the ground a block and a half further out that way, never over the block's
    // top; a cell he dug out (its middle lower) is left: a trench or a cellar beside the block stays open. Returns the samples' cells it changed. BS_OLDBACK=1: as before.
    static let oldBack = Env.all["BS_OLDBACK"] == "1"
    @discardableResult
    func groundBack(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) -> Int {
        guard !World.oldBack, World.meetGroundOn, fieldTerrain, frame == nil, Blocks.fullCollide[Int(id)], y > 1, y + 2 < CH else { return 0 }
        let fy = Float(y), top = fy + 1
        // The ground further out, each of the eight ways: its height, or nil where there is none within a block of the
        // block's own height (open air, a drop, a pit: nothing to come back to).
        var ref = [Float?](repeating: nil, count: 9)
        var any = false
        for sz in -1...1 { for sx in -1...1 where sx != 0 || sz != 0 {
            let reach: Float = sx != 0 && sz != 0 ? 1.4 : 1.7
            let px = Float(x) + 0.5 + Float(sx) * reach, pz = Float(z) + 0.5 + Float(sz) * reach
            let cx = Int(floor(px)), cz = Int(floor(pz))
            var h: Float?
            if Blocks.fullCollide[Int(builtBlock(cx, y, cz))] { h = top }                       // (a block of the same row: flush with it)
            else if builtBlock(cx, y + 1, cz) != AIR && Blocks.collide[Int(builtBlock(cx, y + 1, cz))] { h = nil }
            else {
                let o = V3(px, top + 0.6, pz)
                if fieldDensity(at: o) > 0 { h = top + 0.6 }
                else if let hit = fieldRaySegment(o, V3(0, -1, 0), from: 0, to: 1.9) { h = hit.at.y }
            }
            // (ground lower than the block's floor that way: the block stands proud of it, nothing to raise)
            guard let hh = h, hh > fy + 0.05 else { continue }
            // The cell beside the block that way: rounded off by the blow (its middle still stands within half a block
            // of the level) or dug out (lower: his, left alone).
            let mx = Float(x + sx) + 0.5, mz = Float(z + sz) + 0.5
            guard !Blocks.collide[Int(builtBlock(x + sx, y, z + sz))] else { continue }
            let mo = V3(mx, top + 0.6, mz)
            var mid: Float = -1
            if fieldDensity(at: mo) > 0 { mid = top + 0.6 } else if let hit = fieldRaySegment(mo, V3(0, -1, 0), from: 0, to: 2.2) { mid = hit.at.y }
            // (the level further out can itself be rounded down by the blow that dug the cell, so it alone cannot tell a
            // dug cell: a cell with no ground left over a fifth of its height is open, whatever stands beyond it)
            guard mid >= min(top, hh) - 0.5, mid >= fy + 0.2 else { continue }
            ref[(sx + 1) + (sz + 1) * 3] = hh; any = true
        } }
        guard any else { return 0 }
        let x0 = Float(x), x1 = Float(x + 1), z0 = Float(z), z1 = Float(z + 1)
        var changed = 0
        func inside(_ p: V3) -> Float {
            let ox = p.x < x0 ? p.x - x0 : (p.x > x1 ? p.x - x1 : 0), oz = p.z < z0 ? p.z - z0 : (p.z > z1 ? p.z - z1 : 0)
            guard ox != 0 || oz != 0 else { return -4 }
            let out = max(abs(ox), abs(oz))
            guard out <= 1 else { return -4 }
            guard let h = ref[(ox < 0 ? 0 : (ox > 0 ? 2 : 1)) + (oz < 0 ? 0 : (oz > 0 ? 2 : 1)) * 3] else { return -4 }
            let near = min(top, h)
            let t = near + max(0, h - top) * out
            return t - p.y
        }
        _ = fieldFill(IVec3(x - 1, y - 1, z - 1), IVec3(x + 1, y + 1, z + 1), { p in
            let v = inside(p)
            if v > 0 { changed += 1 }
            return v
        }, keep: IVec3(x, y, z))
        return changed
    }

    // Fills the field's ground in the cells lo...hi (and their fine samples) up to the shape `inside` (> 0 inside, about
    // the distance to its surface): each sample becomes the larger of what it was and the shape, so the ground only
    // grows. Never into a built block's cell, nor `keep`. Material from the ground round each new cell.
    // cut: the other way (ledger 273): each sample becomes the smaller of what it was and the shape (`inside` is then
    // the most the ground may be there), so the ground only falls; it may cut into `keep`'s own cell.
    func fieldFill(_ lo: IVec3, _ hi: IVec3, _ inside: (V3) -> Float, keep: IVec3, cut: Bool = false) -> Int {
        var flipped = 0
        var touched: [(Chunk, Int)] = []
        func touch(_ c: Chunk, _ sy: Int) { if !touched.contains(where: { $0.0 === c && $0.1 == sy }) { touched.append((c, sy)) } }
        // (P440: the cells whose samples changed, for the sections the frame meshes)
        var clo = IVec3(Int.max, Int.max, Int.max), chi = IVec3(Int.min, Int.min, Int.min)
        func grow(_ p: IVec3) {
            clo = IVec3(min(clo.x, p.x), min(clo.y, p.y), min(clo.z, p.z)); chi = IVec3(max(chi.x, p.x), max(chi.y, p.y), max(chi.z, p.z))
            noteChange(p.x, p.y, p.z)
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
                    let isKeep = ox + (fx >> 1) == keep.x && oy + (fy >> 1) == keep.y && oz + (fz >> 1) == keep.z
                    if c.blocks.raw(ci) != AIR && !(cut && isKeep) { continue }  // (a fill never swallows a built block)
                    if isKeep && !cut { continue }
                    let p = V3(Float(ox) + (Float(fx) + 0.5) * 0.5, Float(oy) + (Float(fy) + 0.5) * 0.5, Float(oz) + (Float(fz) + 0.5) * 0.5)
                    let k = FineField.index(fx, fy, fz)
                    let q = FieldTerrain.q(cut ? min(FieldTerrain.f(f[k]), inside(p)) : max(FieldTerrain.f(f[k]), inside(p)))
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
                let isKeep = x == keep.x && y == keep.y && z == keep.z
                if isKeep && !cut { continue }
                let i = Chunk.index(mod(x, CS), y, mod(z, CS))
                if c.blocks.raw(i) != AIR && !(cut && isKeep) { continue }
                let d0 = FieldTerrain.f(c.blocks.density(i))
                let shape = inside(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))
                let q = FieldTerrain.q(cut ? min(d0, shape) : max(d0, shape))
                if q == c.blocks.density(i) { continue }
                let was = d0 > 0, now = q > 0
                if was != now && cut {
                    c.blocks.setDensity(i, min(q, -1), material: nil, follow: false)
                    flipped += 1
                    c.recomputeHeight(mod(x, CS), mod(z, CS))
                } else if was != now {
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
                for s in thru(max(0, sy - 1), min(NSEC - 1, sy + 1)) where !all.contains(where: { $0.0 === n && $0.1 == s }) { all.append((n, s)) }
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
