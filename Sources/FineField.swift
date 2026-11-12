import Foundation
import simd

// P377 step 1 (P338 step 4, option 1): two density samples per block, only where the ground has been edited. A field
// world keeps one sample per block (FieldTerrain), so a hole dug, a blast's bowl or a lump of placed ground could not be
// finer than a block: shapes smaller than that rounded off. Now the first edit in a 16-high section gives it a second,
// finer field (BlockStore.fine: 32^3 samples at the half-block cells' centres, upsampled from the cells), every later
// edit writes both, and that section and the ones round it draw the ground from the fine samples. Untouched land has
// none and is unchanged. Saved in the chunk's field file (FLD2). BS_FINE=0 turns it off (before/after measurements).
//
// What reads it: the mesher (Mesher.fineGround: dual contouring at half-block cells), collision (World.fieldBoxes),
// rays and every World.fieldDensity(at:) query. The cells (BlockStore.fd) stay what they were (cell solidity, drops,
// light and the game's block queries are unchanged).
enum FineField {
    static var gridColumns = ProcessInfo.processInfo.environment["BS_OLDFINECOLS"] != "1"   // (World.fineColumns)
    static let n = 32, count = 32 * 32 * 32
    static var enabled = ProcessInfo.processInfo.environment["BS_FINE"] != "0"
    @inline(__always) static func index(_ fx: Int, _ fy: Int, _ fz: Int) -> Int { fx + fz * 32 + fy * 1024 }

    // A cell's eight samples follow a write to the cell (BlockStore.setDensity): moved by as much as the cell, or set to
    // its new value where the cell was far inside or outside before (no surface near it to keep).
    static func follow(_ fine: inout [Int: [Int8]], _ i: Int, from old: Int8, to new: Int8) {
        let y = i / CSQ, sy = y >> 4
        guard fine[sy] != nil else { return }
        let lx = i & 15, lz = (i >> 4) & 15, ly = y & 15
        let delta = Int(new) - Int(old), far = old == FieldTerrain.inside || old == FieldTerrain.outside
        for c in 0..<8 {
            let k = index(lx * 2 + (c & 1), ly * 2 + ((c >> 1) & 1), lz * 2 + (c >> 2))
            let v = far ? Int(new) : Int(fine[sy]![k]) + delta
            fine[sy]![k] = Int8(max(-127, min(127, v)))
        }
    }

    // A sample between eight cell samples (t: the weights along x, y, z): trilinear, each cell clamped to 1.5 blocks unless
    // all eight are the same far value (far inside or outside stays far).
    @inline(__always) static func upsample(_ c: SIMD8<Float>, raw0: Int8, allSame: Bool, _ t: SIMD3<Float>) -> Int8 {
        if allSame && (raw0 == FieldTerrain.inside || raw0 == FieldTerrain.outside) { return raw0 }
        let v = simd_clamp(c, SIMD8(repeating: -48), SIMD8(repeating: 48))
        let a = v[0] + (v[1] - v[0]) * t.x, b = v[2] + (v[3] - v[2]) * t.x
        let d = v[4] + (v[5] - v[4]) * t.x, e = v[6] + (v[7] - v[6]) * t.x
        let f = a + (b - a) * t.y, g = d + (e - d) * t.y
        return Int8(max(-127, min(127, (f + (g - f) * t.z).rounded())))
    }

    // Memory (harness): fine sections and bytes over the loaded chunks.
    static func tally(_ w: World) -> (sections: Int, bytes: Int) {
        var n = 0
        for (_, c) in w.chunks { n += c.blocks.fine.count }
        return (n, n * count)
    }
}

extension World {
    // The fine sample at world fine coordinates (centre ((f + 0.5) / 2) on each axis), in blocks: the section's own, or
    // the cells' trilinear value there.
    func fineSample(_ fx: Int, _ fy: Int, _ fz: Int) -> Float {
        if fy < 0 { return 4 }
        if fy >= CH * 2 { return -4 }
        guard let c = chunkAt(fx >> 1, fz >> 1), c.blocks.isField else { return -4 }
        if let f = c.blocks.fine[fy >> 5] { return FieldTerrain.f(f[FineField.index(fx & 31, fy & 31, fz & 31)]) }
        return coarseDensity(at: V3((Float(fx) + 0.5) * 0.5, (Float(fy) + 0.5) * 0.5, (Float(fz) + 0.5) * 0.5))
    }

    // Does the ground at p read fine samples (its chunk has a fine section at or next to p's)?
    @inline(__always) func fineNear(_ p: V3) -> Bool {
        guard FineField.enabled, let c = chunkAt(Int(floor(p.x)), Int(floor(p.z))), !c.blocks.fine.isEmpty else { return false }
        let y = Int(floor(p.y))
        guard y >= -1 && y <= CH else { return false }
        let s0 = max(0, y - 1) >> 4, s1 = min(CH - 1, y + 1) >> 4
        return c.blocks.fine[s0] != nil || c.blocks.fine[s1] != nil
    }

    // Trilinear between the eight fine samples round p.
    func fineDensity(at p: V3) -> Float {
        let q = p * 2 - 0.5
        let x0 = Int(floor(q.x)), y0 = Int(floor(q.y)), z0 = Int(floor(q.z))
        let tx = q.x - Float(x0), ty = q.y - Float(y0), tz = q.z - Float(z0)
        let c000 = fineSample(x0, y0, z0), c100 = fineSample(x0 + 1, y0, z0)
        let c010 = fineSample(x0, y0 + 1, z0), c110 = fineSample(x0 + 1, y0 + 1, z0)
        let c001 = fineSample(x0, y0, z0 + 1), c101 = fineSample(x0 + 1, y0, z0 + 1)
        let c011 = fineSample(x0, y0 + 1, z0 + 1), c111 = fineSample(x0 + 1, y0 + 1, z0 + 1)
        let a = c000 + (c100 - c000) * tx, b = c010 + (c110 - c010) * tx
        let c = c001 + (c101 - c001) * tx, d = c011 + (c111 - c011) * tx
        let e = a + (b - a) * ty, f = c + (d - c) * ty
        return e + (f - e) * tz
    }

    // Gives section sy of chunk c its fine samples (once), upsampled from the cells as they are now.
    @discardableResult
    func ensureFine(_ c: Chunk, _ sy: Int) -> Bool {
        guard FineField.enabled, fieldTerrain, c.blocks.isField, sy >= 0, sy < NSEC, c.blocks.fine[sy] == nil else { return false }
        // The cells -1...16 round the section (a neighbour not loaded: the section's own edge cell).
        let N = 18, NN = N * N
        var raw = [Int8](repeating: 0, count: N * NN)
        for lz in -1...16 { for lx in -1...16 {
            let x = c.cx * CS + lx, z = c.cz * CS + lz
            let src: Chunk = chunkAt(x, z).flatMap { $0.blocks.isField ? $0 : nil } ?? c
            let ox = src === c ? max(0, min(15, lx)) : mod(x, CS), oz = src === c ? max(0, min(15, lz)) : mod(z, CS)
            for ly in -1...16 {
                let y = sy * 16 + ly
                let v: Int8 = y < 0 ? FieldTerrain.inside : (y >= CH ? FieldTerrain.outside : src.blocks.density(Chunk.index(ox, y, oz)))
                raw[(lx + 1) + (lz + 1) * N + (ly + 1) * NN] = v
            }
        } }
        // (Store review, callgrind of the rocket craters: this upsampling was 44% of a blast's ground carving, every
        // sample reading its eight cells. The eight cells round each corner are looked at once: where they are all
        // wholly inside or outside, so are the eight samples between them, as upsample gives.)
        let U = 17, UU = U * U, mixed: Int16 = 0x7FFF
        var uni = [Int16](repeating: mixed, count: U * UU)
        for by in -1...15 { for bz in -1...15 { for bx in -1...15 {
            let r0 = raw[(bx + 1) + (bz + 1) * N + (by + 1) * NN]
            guard r0 == FieldTerrain.inside || r0 == FieldTerrain.outside else { continue }
            var same = true
            for k in 1..<8 where raw[(bx + 1 + (k & 1)) + (bz + 1 + (k >> 2)) * N + (by + 1 + ((k >> 1) & 1)) * NN] != r0 { same = false; break }
            if same { uni[(bx + 1) + (bz + 1) * U + (by + 1) * UU] = Int16(r0) }
        } } }
        var f = [Int8](repeating: 0, count: FineField.count)
        for fy in 0..<32 { for fz in 0..<32 { for fx in 0..<32 {
            // Cell centres at local n + 0.5: the sample at (f + 0.5) / 2 lies between cells (f - 1) / 2 and that + 1.
            let bx = (fx - 1) >> 1, by = (fy - 1) >> 1, bz = (fz - 1) >> 1
            let u = uni[(bx + 1) + (bz + 1) * U + (by + 1) * UU]
            if u != mixed { f[FineField.index(fx, fy, fz)] = Int8(u); continue }
            let t = SIMD3<Float>(fx & 1 == 0 ? 0.75 : 0.25, fy & 1 == 0 ? 0.75 : 0.25, fz & 1 == 0 ? 0.75 : 0.25)
            var v = SIMD8<Float>()
            var same = true
            let r0 = raw[(bx + 1) + (bz + 1) * N + (by + 1) * NN]
            for k in 0..<8 {
                let ix: Int = bx + 1 + (k & 1), iz: Int = bz + 1 + (k >> 2), iy: Int = by + 1 + ((k >> 1) & 1)
                let r = raw[ix + iz * N + iy * NN]
                v[k] = Float(r)
                if r != r0 { same = false }
            }
            f[FineField.index(fx, fy, fz)] = FineField.upsample(v, raw0: r0, allSame: same, t)       // (corners: bit 0 x, 1 y, 2 z)
        } } }
        c.blocks.fine[sy] = f
        World.fineMade &+= 1
        // Nov 12 (FAILURES 4): the sections round it (3x3 chunks, a section up and down) now draw half-block ground,
        // and the half-block sections one further out pinned their outer edge onto those sections' cells: the callers
        // remesh the 3x3, nobody remeshed the ring, whose edge then lay on a line its neighbour no longer drew (a slit
        // or a sliver of sky until something else remeshed it). The ring's half-block sections go stale here.
        if !Mesher.oldFineCorners {
            for dz in -2...2 { for dx in -2...2 where abs(dx) == 2 || abs(dz) == 2 {
                guard let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)], n.meshedOnce else { continue }
                for s in max(0, sy - 2)...min(NSEC - 1, sy + 2) {
                    var drawsFine = false
                    for oz in -1...1 where !drawsFine { for ox in -1...1 {
                        guard let m = chunks[ChunkKey(x: n.cx + ox, z: n.cz + oz)], !m.blocks.fine.isEmpty else { continue }
                        for t in max(0, s - 1)...min(NSEC - 1, s + 1) where m.blocks.fine[t] != nil && !(m === c && t == sy) { drawsFine = true }
                        if drawsFine { break }
                    } }
                    if drawsFine { n.sections[s].version += 1 }
                }
            } }
            for dz in -1...1 { for dx in -1...1 {
                guard let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)], n.meshedOnce else { continue }
                for s in [sy - 2, sy + 2] where s >= 0 && s < NSEC {
                    var drawsFine = false
                    for oz in -1...1 where !drawsFine { for ox in -1...1 {
                        guard let m = chunks[ChunkKey(x: n.cx + ox, z: n.cz + oz)], !m.blocks.fine.isEmpty else { continue }
                        for t in max(0, s - 1)...min(NSEC - 1, s + 1) where m.blocks.fine[t] != nil && !(m === c && t == sy) { drawsFine = true }
                        if drawsFine { break }
                    } }
                    if drawsFine { n.sections[s].version += 1 }
                }
            } }
        }
        if World.fineWhy { World.fineLog.append(SIMD3(Int32(c.cx), Int32(sy), Int32(c.cz))) }
        return true
    }

    // Store review (build 97's crawler soak: a wheel's rut cut was 2-3 ms of one frame, most of it the fine samples of
    // each new ground section the ball reached, made at once): the sections a carve at `ctr` will reach are made ahead,
    // at most one a call. True while one was made now (the carve waits a frame); false once all of them have theirs.
    func prefetchFine(_ ctr: V3, radius r: Float) -> Bool {
        guard FineField.enabled, fieldTerrain else { return false }
        let reach = r + 1.0
        let s0 = max(0, Int(floor(ctr.y - reach)) >> 4), s1 = min(NSEC - 1, max(0, Int(floor(ctr.y + reach))) >> 4)
        guard s0 <= s1 else { return false }
        for cz in floorDiv(Int(floor(ctr.z - reach)), CS)...floorDiv(Int(floor(ctr.z + reach)), CS) {
            for cx in floorDiv(Int(floor(ctr.x - reach)), CS)...floorDiv(Int(floor(ctr.x + reach)), CS) {
                guard let c0 = chunks[ChunkKey(x: cx, z: cz)], c0.blocks.isField else { continue }
                for sy in s0...s1 where c0.blocks.fine[sy] == nil {
                    let c = c0.hollow || !c0.cacheDropped ? editing(c0) : c0
                    guard c.blocks.isField, ensureFine(c, sy) else { continue }
                    World.notePrefetched(c, sy)
                    return true
                }
            }
        }
        return false
    }

    // fieldSphere's fine part: the same sphere on the fine samples of the sections it reaches (given them first, from
    // the cells before the sphere). Returns the sections whose samples changed.
    func fineSphere(_ ctr: V3, radius r: Float, carve: Bool, prepared: [(Chunk, Int, Bool)]) -> [(Chunk, Int)] {
        var changed: [(Chunk, Int)] = []
        let reach = r + 1.0
        for (c, sy, fresh) in prepared {
            guard var f = c.blocks.fine[sy] else { continue }
            c.blocks.fine[sy] = nil                                  // (written back below: no copy on write)
            let ox = Float(c.cx * CS), oy = Float(sy * 16), oz = Float(c.cz * CS)
            let lo = (ctr - reach - V3(ox, oy, oz)) * 2, hi = (ctr + reach - V3(ox, oy, oz)) * 2
            let x0 = max(0, Int(floor(lo.x))), x1 = min(31, Int(ceil(hi.x)))
            let y0 = max(0, Int(floor(lo.y))), y1 = min(31, Int(ceil(hi.y)))
            let z0 = max(0, Int(floor(lo.z))), z1 = min(31, Int(ceil(hi.z)))
            var any = false
            if x0 <= x1 && y0 <= y1 && z0 <= z1 {
                for fy in y0...y1 { for fz in z0...z1 { for fx in x0...x1 {
                    let p = V3(ox + (Float(fx) + 0.5) * 0.5, oy + (Float(fy) + 0.5) * 0.5, oz + (Float(fz) + 0.5) * 0.5)
                    let dist = simd_length(p - ctr)
                    let k = FineField.index(fx, fy, fz)
                    let d0 = FieldTerrain.f(f[k])
                    let d1 = carve ? min(d0, dist - r) : max(d0, r - dist)
                    var q = FieldTerrain.q(d1)
                    if q == f[k] { continue }
                    let ci = Chunk.index(fx >> 1, sy * 16 + (fy >> 1), fz >> 1)
                    if carve && c.blocks.ground(ci) && Blocks.hardness[Int(FieldMat.blocks[Int(c.blocks.material(ci))])] < 0 { q = max(q, 8) }   // (bedrock)
                    if !carve && c.blocks.raw(ci) != AIR { continue }                     // (a fill never swallows a built block)
                    if q == f[k] { continue }
                    f[k] = q; any = true
                    noteChange(c.cx * CS + (fx >> 1), sy * 16 + (fy >> 1), c.cz * CS + (fz >> 1))
                } } }
            }
            if any || !fresh { c.blocks.fine[sy] = f }
            if any { changed.append((c, sy)) }
        }
        return changed
    }

    // The sections a sphere at ctr of radius r reaches, each given its fine samples first (fresh: given here).
    func prepareFine(_ ctr: V3, radius r: Float) -> [(Chunk, Int, Bool)] {
        guard FineField.enabled, fieldTerrain else { return [] }
        var out: [(Chunk, Int, Bool)] = []
        let reach = r + 1.0
        let s0 = max(0, Int(floor(ctr.y - reach)) >> 4), s1 = min(NSEC - 1, max(0, Int(floor(ctr.y + reach))) >> 4)
        guard s0 <= s1 else { return [] }
        for cz in floorDiv(Int(floor(ctr.z - reach)), CS)...floorDiv(Int(floor(ctr.z + reach)), CS) {
            for cx in floorDiv(Int(floor(ctr.x - reach)), CS)...floorDiv(Int(floor(ctr.x + reach)), CS) {
                guard let c0 = chunks[ChunkKey(x: cx, z: cz)] else { continue }
                let c = c0.hollow || !c0.cacheDropped ? editing(c0) : c0
                guard c.blocks.isField else { continue }
                for sy in s0...s1 {
                    // (made ahead by prefetchFine and still untouched: as fresh as one made now, so a sphere that leaves
                    // it as it was doesn't keep it)
                    let ahead = !World.finePrefetched.isEmpty && World.takePrefetched(c, sy)
                    out.append((c, sy, ensureFine(c, sy) || ahead))
                }
            }
        }
        return out
    }

    // fieldBoxes for a cell whose ground reads fine samples: the 4 x 4 quarter-block columns, each solid between the
    // lowest and highest of 9 points up its centre line inside the ground (the fine field as the mesh draws it).
    // (Store review, the crawler and citadel soaks: one step of a mob's path search took 4-6 ms over cratered or rutted
    // ground, every cell it looked at reading 144 points here, each eight samples through a chunk lookup (and a coarse
    // sample's eight more). The 144 points all lie between the same 4 x 4 x 4 samples round the cell: read once, then
    // interpolated exactly as fineDensity does. FineField.gridColumns false: the old way.)
    func fineColumns(_ x: Int, _ y: Int, _ z: Int, _ out: UnsafeMutablePointer<Float>) {
        guard FineField.gridColumns else { fineColumnsPointwise(x, y, z, out); return }
        withUnsafeTemporaryAllocation(of: Float.self, capacity: 64) { S in
            let bx = 2 * x - 1, by = 2 * y - 1, bz = 2 * z - 1
            for k in 0..<4 { for j in 0..<4 { for i in 0..<4 { S[i + j * 4 + k * 16] = fineSample(bx + i, by + k, bz + j) } } }
            @inline(__always) func s(_ fx: Int, _ fy: Int, _ fz: Int) -> Float {
                let i = fx - bx, k = fy - by, j = fz - bz
                if i >= 0 && i < 4 && j >= 0 && j < 4 && k >= 0 && k < 4 { return S[i + j * 4 + k * 16] }
                return fineSample(fx, fy, fz)                    // (far from the origin, where a float's step is coarse)
            }
            // fineDensity(at:), its samples taken from S.
            func dens(_ p: V3) -> Float {
                let q = p * 2 - 0.5
                let x0 = Int(floor(q.x)), y0 = Int(floor(q.y)), z0 = Int(floor(q.z))
                let tx = q.x - Float(x0), ty = q.y - Float(y0), tz = q.z - Float(z0)
                let c000 = s(x0, y0, z0), c100 = s(x0 + 1, y0, z0)
                let c010 = s(x0, y0 + 1, z0), c110 = s(x0 + 1, y0 + 1, z0)
                let c001 = s(x0, y0, z0 + 1), c101 = s(x0 + 1, y0, z0 + 1)
                let c011 = s(x0, y0 + 1, z0 + 1), c111 = s(x0 + 1, y0 + 1, z0 + 1)
                let a = c000 + (c100 - c000) * tx, b = c010 + (c110 - c010) * tx
                let c = c001 + (c101 - c001) * tx, d = c011 + (c111 - c011) * tx
                let e = a + (b - a) * ty, f = c + (d - c) * ty
                return e + (f - e) * tz
            }
            columns(x, y, z, out, dens)
        }
    }
    func fineColumnsPointwise(_ x: Int, _ y: Int, _ z: Int, _ out: UnsafeMutablePointer<Float>) {
        columns(x, y, z, out) { fineDensity(at: $0) }
    }
    @inline(__always) private func columns(_ x: Int, _ y: Int, _ z: Int, _ out: UnsafeMutablePointer<Float>, _ density: (V3) -> Float) {
        for v in 0..<4 { for u in 0..<4 {
            let px = Float(x) + (Float(u) + 0.5) / 4, pz = Float(z) + (Float(v) + 0.5) / 4
            var lo: Float = -1, hi: Float = -1
            var prev = density(V3(px, Float(y), pz)), prevT: Float = 0
            if prev > 0 { lo = 0; hi = 0 }
            for s in 1...8 {
                let t = Float(s) / 8
                let d = density(V3(px, Float(y) + t, pz))
                if d > 0 {
                    if lo < 0 { lo = prev > 0 ? prevT : prevT + (t - prevT) * prev / (prev - d) }
                    hi = t
                } else if prev > 0 {
                    hi = prevT + (t - prevT) * prev / (prev - d)
                }
                prev = d; prevT = t
            }
            out[(u + v * 4) * 2] = lo; out[(u + v * 4) * 2 + 1] = hi
        } }
    }
}

extension Mesher {
    // P377 step 1: does section sy draw its ground from fine samples (it, or a section round it, has them)? The ring
    // round an edited section draws fine too, so where fine meets cells the ground on both sides is the cells' own.
    static func fineSection(_ n9: [BlockStore], sy: Int) -> Bool {
        guard FineField.enabled else { return false }
        for st in n9 where !st.fine.isEmpty {
            for s in thru(max(0, sy - 1), min(NSEC - 1, sy + 1)) where st.fine[s] != nil { return true }
        }
        return false
    }

    // The section's ground at half-block cells: its 16^3 blocks as eight 16^3 sections of half blocks, each meshed by
    // smoothQuads on a region built at half scale (cells, light and materials of the block each half block is in; the
    // density from the fine samples, or upsampled from the cells, in half-block units), positions scaled back.
    // P404 (Remington, Oct 22, 23:08, 23:10, 23:12: "cracks in the ground"): a section drawn from its cells meets the
    // half-block ground beside it along the half-block ground's outer edge, and the two surfaces (the same field, drawn
    // at two sizes of cell) differed by up to a twentieth of a block there: from a low angle the eye slipped under the
    // higher edge and saw the sky through the ground, a pale hairline along the border of the edited chunks' ring. Now
    // the half-block ground's outer edge takes the cells-drawn neighbour's own vertices: on a side meeting a section
    // drawn from its cells (`fineBeyond` from World.fineBeyond says what lies past the 3x3 chunks), the ground's two
    // outer half-block cells pin onto the vertex the cells draw there (the nearest of the cells' vertices the half-block
    // cell lies in), so the border is the very polyline the neighbour draws: no slit, no overlap.
    // (meshbench only: where the half-block ground's time goes; main thread)
    static var fineTiming = false
    static var fineT = (pre: 0.0, fill: 0.0, quads: 0.0, subs: 0, empty: 0, adaptive: 0.0)
    static var oldFineFill = ProcessInfo.processInfo.environment["BS_OLDFINEFILL"] == "1"
    static var oldFineLookup = ProcessInfo.processInfo.environment["BS_OLDFINELOOKUP"] == "1"
    static func fineGround(_ n9: [BlockStore], sy: Int, _ R: UnsafeMutablePointer<BlockID>, _ sc: MeshScratch, leafHoles: Bool, detailHoles: Bool,
                           exact: GrowBuf<Float>? = nil, fineBeyond: [UInt32] = [], _ emit: (Int, Int, Int, Int, Int, Int, Int, Int, Int) -> Void) {
        let vs = sc.fineScratch
        let vR = vs.region, vSky = vs.sky, vBlk = vs.blk, vD = vs.dens
        let dens = sc.dens, sky = sc.sky, blk = sc.blk
        let natT = SmoothTerrain.natural, opaqueT = Blocks.opaque, loT = Blocks.lightOpaque
        @inline(__always) func ri(_ x: Int, _ y: Int, _ z: Int) -> Int { (x + C0) + (z + C0) * RW + (y + C0) * RL }
        // P404: the sides (bits as World.sides: 0 -x, 1 +x, 2 -z, 3 +z; 4 below, 5 above) whose neighbour draws from its
        // cells: no chunk of its 3x3 has fine samples at its height or next to it.
        var coarse = 0
        // Nov 12: the same for all 26 neighbours (bit (ax + 1) + (az + 1) * 3 + (ay + 1) * 9), from the 5x5 masks:
        // an edge or corner neighbour can draw from its cells while both side neighbours between draw half blocks.
        var coarseN: UInt32 = 0
        if fineBeyond.count >= 29 && !Mesher.oldFineCorners {
            for ay in -1...1 { for az in -1...1 { for ax in -1...1 where ax != 0 || ay != 0 || az != 0 {
                let t = sy + ay
                guard t >= 0 && t < NSEC else { continue }
                var m: UInt32 = 0
                for oz in -1...1 { for ox in -1...1 { m |= fineBeyond[4 + (ax + ox + 2) + (az + oz + 2) * 5] } }
                var want: UInt32 = 0
                for u in max(0, t - 1)...min(NSEC - 1, t + 1) { want |= 1 << UInt32(u) }
                if m & want == 0 { coarseN |= 1 << UInt32((ax + 1) + (az + 1) * 3 + (ay + 1) * 9) }
            } } }
        }
        if fineBeyond.count >= 4 {
            let lo = max(0, sy - 1), hi = min(NSEC - 1, sy + 1)
            for s in 0..<4 {
                let (dx, dz) = World.sides[s]
                var fine = false
                for oz in -1...1 where abs(oz - dz) <= 1 { for ox in -1...1 where abs(ox - dx) <= 1 {
                    let st = n9[(ox + 1) + (oz + 1) * 3]
                    if st.fine.isEmpty { continue }
                    for t in lo...hi where st.fine[t] != nil { fine = true }
                } }
                for t in lo...hi where fineBeyond[s] & (1 << UInt32(t)) != 0 { fine = true }
                if !fine { coarse |= 1 << s }
            }
            if sy > 0 && !fineSection(n9, sy: sy - 1) { coarse |= 16 }
            if sy < NSEC - 1 && !fineSection(n9, sy: sy + 1) { coarse |= 32 }
        }
        sc.dbgCoarse = (coarse, coarseN, 0)
        // The cells' own vertices (the ones the neighbour draws there: the same in every section that meshes them).
        let timing = Mesher.fineTiming
        var tA = timing ? CFAbsoluteTimeGetCurrent() : 0
        defer { if timing { Mesher.fineT.quads += CFAbsoluteTimeGetCurrent() - tA } }
        if coarse != 0 || coarseN != 0 {
            smoothQuads(R, sc, dmg: [:], stored: dens, sy: sy, leafHoles: leafHoles, detailHoles: detailHoles) { _, _, _, _, _, _, _, _, _ in }
        }
        let KOc = SmoothTerrain.maxRelax, Kc = 17 + 2 * KOc, KKc = Kc * Kc
        let VPc = sc.smV, VLc = sc.smL
        // (smoothQuads reads its section's 0...16 and a ring of maxRelax + 3 round it)
        let lo = max(0, C0 - SmoothTerrain.maxRelax - 4), hi = min(RW - 1, C0 + 21 + SmoothTerrain.maxRelax)
        vR.initialize(repeating: AIR, count: RL * RH)
        vD.initialize(repeating: FieldTerrain.outside, count: RL * RH)
        // The fine samples of the 3x3 chunks' sections below, at and above this one, looked up once: looked up for every
        // half-block sample (a dictionary find, a SipHash of the section number) they were a fifth of every instruction
        // the mesh workers ran in the worst-case soak (callgrind, build 265). BS_OLDFINELOOKUP=1: a find a sample.
        let fineT: [[Int8]?] = (0..<27).map { k in
            let t = sy + k / 9 - 1
            return t >= 0 && t < NSEC ? n9[k % 9].fine[t] : nil
        }
        let oldLookup = Mesher.oldFineLookup
        if timing { let t = CFAbsoluteTimeGetCurrent(); Mesher.fineT.pre += t - tA; tA = t }
        // The half block at fine, section-local gx, gy, gz: what it is, its density (half-block units) and its light.
        @inline(__always) func half(_ gx: Int, _ gy: Int, _ gz: Int) -> (BlockID, Int8, UInt8, UInt8) {
            let src = ri(gx >> 1, gy >> 1, gz >> 1)
            var d: Int8
            let ni = (gx >> 5) + 1 + ((gz >> 5) + 1) * 3
            if let f = oldLookup ? n9[ni].fine[sy + (gy >> 5)] : fineT[ni + ((gy >> 5) + 1) * 9] {
                d = f[FineField.index(gx & 31, gy & 31, gz & 31)]
            } else {
                let bx = (gx - 1) >> 1, by = (gy - 1) >> 1, bz = (gz - 1) >> 1
                let t = SIMD3<Float>(gx & 1 == 0 ? 0.75 : 0.25, gy & 1 == 0 ? 0.75 : 0.25, gz & 1 == 0 ? 0.75 : 0.25)
                var c = SIMD8<Float>()
                let r0 = dens[ri(bx, by, bz)]
                var same = true
                for k in 0..<8 {
                    let r = dens[ri(bx + (k & 1), by + ((k >> 1) & 1), bz + (k >> 2))]
                    c[k] = Float(r)
                    if r != r0 { same = false }
                }
                d = FineField.upsample(c, raw0: r0, allSame: same, t)
            }
            // (distances in half blocks: twice as many units)
            let dv: Int8 = d == FieldTerrain.inside || d == FieldTerrain.outside ? d : Int8(max(-126, min(126, Int(d) * 2)))
            // The half block's own: ground where its sample is inside (the cell's ground material, or the one it had
            // before it was dug), open where it is outside; a built block stays what it is.
            let rb = R[src]
            let cellGround = dens[src] > 0 && natT[Int(rb)]
            var b = rb
            if d > 0 && !cellGround && (rb == AIR || !opaqueT[Int(rb)]) {
                // (the ground beside it, under it first: grass reaching up into the open cell over it stays grass)
                b = DIRT
                var found = false
                let around: [Int] = [-RL, 1, -1, RW, -RW, RL]
                for o in around where dens[src + o] > 0 && natT[Int(R[src + o])] { b = R[src + o]; found = true; break }
                if !found {
                    let bx: Int = gx >> 1, by: Int = sy * 16 + (gy >> 1), bz: Int = gz >> 1
                    let ni: Int = (bx >> 4) + 1 + ((bz >> 4) + 1) * 3
                    let st = n9[ni]
                    var m = 0
                    if by >= 0 && by < CH { m = Int(st.material(Chunk.index(bx & 15, by, bz & 15))) }
                    if m != 0 { b = FieldMat.blocks[m] }
                }
            } else if d <= 0 && cellGround {
                b = AIR
            }
            var sl = sky[src], bl = blk[src]
            if !loT[Int(b)] && loT[Int(rb)] {
                // (open inside a cell the light flood took as solid: the light of the open cells beside it)
                for o in [1, -1, RW, -RW, RL, -RL] where !loT[Int(R[src + o])] { sl = max(sl, sky[src + o]); bl = max(bl, blk[src + o]) }
            }
            return (b, dv, sl, bl)
        }
        // Each eighth's region reaches maxRelax + 4 half blocks past its own 16, so the eight overlapped: every half block
        // was worked out about three times (a fifth of the mesher's time in dug ground). Now once each, over the 50^3 box
        // all eight read (fine -8...41 on each axis), copied row by row into each eighth's region. BS_OLDFINEFILL=1: before.
        let fW = hi - lo + 1 + 16, fL = fW * fW, g0 = lo - C0
        let oldFill = Mesher.oldFineFill
        precondition(fW == MeshScratch.fineFillW)
        if !oldFill {
            let FF = vs.fill, FR = FF.r, FD = FF.d, FS = FF.s, FB = FF.b
            var k = 0
            for gy in g0..<(g0 + fW) { for gz in g0..<(g0 + fW) { for gx in g0..<(g0 + fW) {
                let h = half(gx, gy, gz)
                FR[k] = h.0; FD[k] = h.1; FS[k] = h.2; FB[k] = h.3
                k += 1
            } } }
        }
        // (Nov 12, `edge` in the pin below: the true point, the point drawn, the border's vertices beside, the look)
        var fins: [(SIMD3<Int32>, SIMD3<Int32>, [SIMD3<Int32>], (Int, Int, Int, Int, Int, Int)?)] = []
        var finAt: [SIMD3<Int32>: Int] = [:]
        var lastAttr: (Int, Int, Int, Int, Int, Int)? = nil
        var pinnedTo: Set<Int> = []          // (BS_FINEDEBUG: the cells' vertices a half-block cell was put on)
        // Nov 12, third cause (a steep slope across the border): half-block cells are put on the nearest of the border's
        // vertices, which leaves out the ones in between where the neighbour's ground climbs faster than a cell a cell
        // (a wall running along the border has a stair of them). The neighbour's edge runs through every one; the
        // half-block ground's edge cut the corner: a slit seen from the side. Every drawn half-block edge between two
        // border vertices that are not neighbours is now walked along the border's own vertices and the gap between
        // filled with a fan of triangles (`stitch`). BS_OLDFINESTITCH=1: no fan.
        let stitchOn = !Mesher.oldFineStitch
        var pinCell: [SIMD3<Int32>: (SIMD3<Int>, SIMD3<Int>)] = [:]     // (a drawn point: the cells' cell, the axes fixed)
        var quad: [(SIMD3<Int32>, (Int, Int, Int, Int, Int, Int))] = []
        var stitchDone: Set<Int> = []
        var stitches: [(SIMD3<Int32>, SIMD3<Int32>, SIMD3<Int32>, (Int, Int, Int, Int, Int, Int))] = []
        func stitch(_ p: SIMD3<Int32>, _ q: SIMD3<Int32>, _ at: (Int, Int, Int, Int, Int, Int)) {
            guard let (cp, fp) = pinCell[p], let (cq, fq) = pinCell[q], cp != cq else { return }
            var a = -1
            for k in 0..<3 where fp[k] >= 0 && fp[k] == fq[k] && cp[k] == cq[k] { a = k; break }
            guard a >= 0 else { return }
            let u = (a + 1) % 3, w = (a + 2) % 3
            if abs(cp[u] - cq[u]) + abs(cp[w] - cq[w]) <= 1 { return }
            func vi(_ c: SIMD3<Int>) -> Int { (c.x + KOc) + (c.z + KOc) * Kc + (c.y + KOc) * KKc }
            let key = min(vi(cp), vi(cq)) * (Kc * KKc) + max(vi(cp), vi(cq))
            guard stitchDone.insert(key).inserted else { return }
            // The shortest way from one to the other over the border's vertices (cells side by side, then corner to corner).
            for diag in [false, true] {
                var from: [Int: Int] = [vi(cp): -1]
                var cellOf: [Int: SIMD3<Int>] = [vi(cp): cp]
                var front = [cp], found = false, depth = 0
                while !front.isEmpty && !found && depth < 14 {
                    depth += 1
                    var next: [SIMD3<Int>] = []
                    for c in front {
                        for du in -1...1 { for dw in -1...1 where (du != 0 || dw != 0) && (diag || du == 0 || dw == 0) {
                            var n = c
                            n[u] += du; n[w] += dw
                            guard n[u] >= 0, n[w] >= 0, n[u] <= 16, n[w] <= 16 else { continue }
                            let i = vi(n)
                            guard VLc[i] >= 0, from[i] == nil else { continue }
                            from[i] = vi(c); cellOf[i] = n
                            if n == cq { found = true }
                            next.append(n)
                        } }
                    }
                    front = next
                }
                guard found else { continue }
                var path: [SIMD3<Int32>] = [q]
                var i = from[vi(cq)]!
                while i != vi(cp) && i >= 0 {
                    let x16 = (SIMD3<Float>(VPc[i * 3], VPc[i * 3 + 1], VPc[i * 3 + 2]) * 16).rounded(.toNearestOrAwayFromZero)
                    if x16.x >= 0 && x16.y >= 0 && x16.z >= 0 { path.append(SIMD3<Int32>(Int32(x16.x), Int32(x16.y), Int32(x16.z))) }
                    i = from[i]!
                }
                for k in 1..<path.count { stitches.append((p, path[k - 1], path[k], at)) }
                return
            }
            sc.dbgCoarse.2 += 1_000_000_000
        }
        let dbg = !Mesher.fineDebug.isEmpty
        sc.fineFins.removeAll(keepingCapacity: true)
        defer {
            if dbg {
                // (the border's vertices no half-block cell was put on: the neighbour's ground runs through them)
                var missed = 0, line = ""
                for sd in 0..<4 where coarse & (1 << sd) != 0 {
                    let fixed = sd & 1 == 0 ? 0 : 16
                    for cy in 0...16 { for u in 0...16 {
                        let cx = sd < 2 ? fixed : u, cz = sd < 2 ? u : fixed
                        let vi = (cx + KOc) + (cz + KOc) * Kc + (cy + KOc) * KKc
                        guard VLc[vi] >= 0, !pinnedTo.contains(vi) else { continue }
                        missed += 1
                        if missed <= 12 { line += String(format: " %d,%d,%d@%.2f,%.2f,%.2f", cx, cy, cz, VPc[vi * 3], VPc[vi * 3 + 1], VPc[vi * 3 + 2]) }
                    } }
                }
                if missed > 0 { print("finedebug: sy \(sy) border vertices no half-block cell took: \(missed):\(line)") }
            }
            if Mesher.fineTrace {
                for t in stitches { sc.dbgTrace.append("stitch \(t.0) \(t.1) \(t.2)") }
                for f in fins { sc.dbgTrace.append("fin true \(f.0) drawn \(f.1) to \(f.2) look \(f.3 != nil)") }
            }
            for t in stitches {
                for p in [t.0, t.1, t.2, t.2, t.2, t.1, t.0, t.0] {
                    sc.fineFins.append((Int(p.x), Int(p.y), Int(p.z), t.3.0, t.3.1, t.3.2, t.3.3, t.3.4, t.3.5))
                }
            }
            for fin in fins {
                guard let at = fin.3 ?? lastAttr else { sc.dbgCoarse.2 += 1_000_000; continue }
                for x in fin.2 where x != fin.0 && x != fin.1 {
                    // (a triangle as a quad with a doubled corner, once for each side)
                    for p in [fin.0, fin.1, x, x, x, fin.1, fin.0, fin.0] {
                        sc.fineFins.append((Int(p.x), Int(p.y), Int(p.z), at.0, at.1, at.2, at.3, at.4, at.5))
                    }
                }
            }
        }
        for v in 0..<8 {
            let vx = v & 1, vy = (v >> 1) & 1, vz = v >> 2
            if oldFill {
                for ry in lo...hi { for rz in lo...hi { for rx in lo...hi {
                    let h = half(rx - C0 + vx * 16, ry - C0 + vy * 16, rz - C0 + vz * 16)     // fine, section-local
                    let j = rx + rz * RW + ry * RL
                    vR[j] = h.0; vD[j] = h.1; vSky[j] = h.2; vBlk[j] = h.3
                } } }
            } else {
                let n = hi - lo + 1, FF = vs.fill
                for ry in lo...hi { for rz in lo...hi {
                    let j = lo + rz * RW + ry * RL
                    let k = vx * 16 + (rz - lo + vz * 16) * fW + (ry - lo + vy * 16) * fL
                    (vR + j).update(from: FF.r + k, count: n)
                    (vD + j).update(from: FF.d + k, count: n)
                    (vSky + j).update(from: FF.s + k, count: n)
                    (vBlk + j).update(from: FF.b + k, count: n)
                } }
            }
            if timing { let t = CFAbsoluteTimeGetCurrent(); Mesher.fineT.fill += t - tA; tA = t }
            var emitted = 0
            defer { if timing { Mesher.fineT.subs += 1; if emitted == 0 { Mesher.fineT.empty += 1 } } }
            let e0 = exact?.count ?? 0
            let off = SIMD3<Float>(Float(vx * 16), Float(vy * 16), Float(vz * 16))
            let pin: ((Int, Int, Int, SIMD3<Float>) -> SIMD3<Float>?)? = coarse == 0 && coarseN == 0 ? nil : { hx, hy, hz, p in
                let gx = hx + vx * 16, gy = hy + vy * 16, gz = hz + vz * 16          // half-block dual cell, 0...32
                var fx = -1, fy = -1, fz = -1                                        // the cells' cell a side fixes
                if coarse & 1 != 0 && gx <= 1 { fx = 0 }
                if coarse & 2 != 0 && gx >= 31 { fx = 16 }
                if coarse & 4 != 0 && gz <= 1 { fz = 0 }
                if coarse & 8 != 0 && gz >= 31 { fz = 16 }
                if coarse & 16 != 0 && gy <= 1 { fy = 0 }
                if coarse & 32 != 0 && gy >= 31 { fy = 16 }
                if coarseN != 0 {
                    // The neighbours this half-block cell touches: every mix of its outer sides. One drawn from its
                    // cells fixes the cell on each axis it lies across.
                    let zx = gx <= 1 ? -1 : (gx >= 31 ? 1 : 0), zy = gy <= 1 ? -1 : (gy >= 31 ? 1 : 0), zz = gz <= 1 ? -1 : (gz >= 31 ? 1 : 0)
                    if zx != 0 || zy != 0 || zz != 0 {
                        for k in 1..<8 {
                            let ax = k & 1 != 0 ? zx : 0, ay = k & 2 != 0 ? zy : 0, az = k & 4 != 0 ? zz : 0
                            if (k & 1 != 0 && zx == 0) || (k & 2 != 0 && zy == 0) || (k & 4 != 0 && zz == 0) { continue }
                            guard coarseN & (1 << UInt32((ax + 1) + (az + 1) * 3 + (ay + 1) * 9)) != 0 else { continue }
                            // (Only a neighbour none of the nearer ones between stands for: beside a side neighbour drawn
                            // from its cells, the cell is already on that neighbour's border, whose vertices run on
                            // across the edge; fixing the other axis too skipped one of them, a slit along the edge.)
                            var nearer = false
                            for j in 1..<k where j & k == j {
                                let bx = j & 1 != 0 ? zx : 0, by = j & 2 != 0 ? zy : 0, bz = j & 4 != 0 ? zz : 0
                                if coarseN & (1 << UInt32((bx + 1) + (bz + 1) * 3 + (by + 1) * 9)) != 0 { nearer = true; break }
                            }
                            if nearer { continue }
                            if ax != 0 { fx = ax < 0 ? 0 : 16 }
                            if ay != 0 { fy = ay < 0 ? 0 : 16 }
                            if az != 0 { fz = az < 0 ? 0 : 16 }
                        }
                    }
                }
                let trace = Mesher.fineTrace && (gx <= 2 || gx >= 30) && (gz <= 2 || gz >= 30)
                guard fx >= 0 || fy >= 0 || fz >= 0 else {
                    if trace { sc.dbgTrace.append(String(format: "free g %d,%d,%d at %.2f,%.2f,%.2f", gx, gy, gz, (p.x + off.x) * 0.5, (p.y + off.y) * 0.5, (p.z + off.z) * 0.5)) }
                    return nil
                }
                // On the other axes the cells' cell holding the half-block cell (odd), or the two it straddles (even):
                // the cells' cell c holds a vertex in c + 0.5 ... c + 1.5, the half-block cell g in g / 2 + 0.25 ... + 0.75.
                // Nov 12 (FAILURES 4, his second spot, 3919 64.5 1041.4, "a really big one"): the outermost half-block
                // cell (32) is the next section's cell 0 and straddles the cells' 15 and 16, the next section's -1 and 0.
                // The next section was offered its 0 alone (a vertex of its -1 can lie below its floor, and a drawn
                // vertex has no sign), so where the border's vertex lay just under the section line the two half-block
                // sections put their shared cell on two different points, or the upper one left it loose: a triangle of
                // sky up to a block wide on the border. Now both take the nearest of the same two cells, and a vertex
                // under the line is drawn on the line by both (`edge` below closes the step that leaves).
                let edgeFix = !Mesher.oldFineEdge
                func cand(_ g: Int, _ fixed: Int) -> [Int] {
                    if fixed >= 0 { return [fixed] }
                    return (g & 1 == 1 ? [(g - 1) / 2] : [g / 2 - 1, g / 2]).filter { $0 >= (edgeFix && g == 0 ? -1 : 0) && $0 <= 16 }
                }
                let pw = (p + off) * 0.5
                var best = SIMD3<Float>(repeating: 0), bestD = Float.infinity, bestC = SIMD3<Int>(0, 0, 0)
                for cx in cand(gx, fx) { for cy in cand(gy, fy) { for cz in cand(gz, fz) {
                    let vi = (cx + KOc) + (cz + KOc) * Kc + (cy + KOc) * KKc
                    guard VLc[vi] >= 0 else { continue }
                    let q = SIMD3<Float>(VPc[vi * 3], VPc[vi * 3 + 1], VPc[vi * 3 + 2])
                    let d = simd_length_squared(q - pw)
                    if d < bestD { bestD = d; best = q; bestC = SIMD3(cx, cy, cz) }
                } } }
                // (On the 1/16 grid the cells' vertex is drawn on, so the half-block vertex, drawn at half its own 1/16
                // grid, lands on the very same point: a vertex a thirty-second off was still a slit from a low angle.)
                if bestD == .infinity && !Mesher.oldFineCorners {
                    // (Still none: the nearest of the cells' vertices one further out on the free axes, on the same border.)
                    // (A cell two sections share keeps its two: the sections must come to the same answer.)
                    func wide(_ g: Int, _ fixed: Int) -> [Int] {
                        if fixed >= 0 { return [fixed] }
                        if g == 0 || g == 32 { return cand(g, fixed) }
                        let c = (g - 1) / 2
                        return Array(max(0, c - 1)...min(16, (g & 1 == 1 ? c : c + 1) + 1))
                    }
                    for cx in wide(gx, fx) { for cy in wide(gy, fy) { for cz in wide(gz, fz) {
                        let vi = (cx + KOc) + (cz + KOc) * Kc + (cy + KOc) * KKc
                        guard VLc[vi] >= 0 else { continue }
                        let q = SIMD3<Float>(VPc[vi * 3], VPc[vi * 3 + 1], VPc[vi * 3 + 2])
                        let d = simd_length_squared(q - pw)
                        if d < bestD { bestD = d; best = q; bestC = SIMD3(cx, cy, cz) }
                    } } }
                    sc.dbgCoarse.2 += bestD < .infinity ? 1 : 1000
                    if bestD == .infinity && !Mesher.fineDebug.isEmpty && sc.dbgCoarse.2 < 12000 {
                        var near = ""
                        for cy in 0...16 { for cz in max(0, gz / 2 - 1)...min(16, gz / 2 + 1) { for cx in max(0, gx / 2 - 2)...min(16, gx / 2 + 1) {
                            let vi = (cx + KOc) + (cz + KOc) * Kc + (cy + KOc) * KKc
                            if VLc[vi] >= 0 { near += String(format: " %d,%d,%d@%.2f,%.2f,%.2f", cx, cy, cz, VPc[vi * 3], VPc[vi * 3 + 1], VPc[vi * 3 + 2]) }
                        } } }
                        print(String(format: "finedebug: loose sy %d cell %d,%d,%d fixed %d,%d,%d at %.2f,%.2f,%.2f; the cells' vertices near:%@", sy, gx, gy, gz, fx, fy, fz, pw.x, pw.y, pw.z, near))
                    }
                }
                guard bestD < .infinity else {
                    if trace { sc.dbgTrace.append(String(format: "none g %d,%d,%d fixed %d,%d,%d at %.2f,%.2f,%.2f", gx, gy, gz, fx, fy, fz, pw.x, pw.y, pw.z)) }
                    return nil
                }
                if dbg { pinnedTo.insert((bestC.x + KOc) + (bestC.z + KOc) * Kc + (bestC.y + KOc) * KKc) }
                var q16 = (best * 16).rounded(.toNearestOrAwayFromZero)
                if edgeFix {
                    // `edge`: a shared cell's vertex under its section line, drawn on the line. The section below (the
                    // one that can draw the true point) closes the step between the two: a triangle from the pair to
                    // each of the border's vertices beside it, drawn after the ground (Mesher).
                    let v16 = q16
                    let g = SIMD3<Int>(gx, gy, gz), fixed = SIMD3<Int>(fx, fy, fz)
                    for a in 0..<3 where fixed[a] < 0 {
                        if g[a] == 0 { q16[a] = max(q16[a], 0) }
                        if g[a] == 32 { q16[a] = max(q16[a], 256) }
                    }
                    if q16 != v16 && v16.x >= 0 && v16.y >= 0 && v16.z >= 0 {
                        let key = SIMD3<Int32>(Int32(q16.x), Int32(q16.y), Int32(q16.z))
                        if finAt[key] == nil {
                            var xs: [SIMD3<Int32>] = []
                            for oy in -1...1 { for oz in -1...1 { for ox in -1...1 where ox != 0 || oy != 0 || oz != 0 {
                                let o = SIMD3<Int>(ox, oy, oz)
                                var ok = true
                                for a in 0..<3 where o[a] != 0 && fixed[a] >= 0 { ok = false }
                                let c = bestC &+ o
                                guard ok, c.x >= 0, c.y >= 0, c.z >= 0, c.x <= 16, c.y <= 16, c.z <= 16 else { continue }
                                let vi = (c.x + KOc) + (c.z + KOc) * Kc + (c.y + KOc) * KKc
                                guard VLc[vi] >= 0 else { continue }
                                let x16 = (SIMD3<Float>(VPc[vi * 3], VPc[vi * 3 + 1], VPc[vi * 3 + 2]) * 16).rounded(.toNearestOrAwayFromZero)
                                guard x16.x >= 0, x16.y >= 0, x16.z >= 0 else { continue }
                                var xt = x16
                                for a in 0..<3 where q16[a] != v16[a] && c[a] == 15 { xt[a] = max(xt[a], 256) }
                                xs.append(SIMD3<Int32>(Int32(x16.x), Int32(x16.y), Int32(x16.z)))
                                if xt != x16 { xs.append(SIMD3<Int32>(Int32(xt.x), Int32(xt.y), Int32(xt.z))) }
                            } } }
                            finAt[key] = fins.count
                            fins.append((SIMD3<Int32>(Int32(v16.x), Int32(v16.y), Int32(v16.z)), key, xs, nil))
                        }
                    }
                }
                if trace { sc.dbgTrace.append(String(format: "pin g %d,%d,%d fixed %d,%d,%d at %.2f,%.2f,%.2f cell %d,%d,%d true %.3f,%.3f,%.3f drawn %.3f,%.3f,%.3f", gx, gy, gz, fx, fy, fz, pw.x, pw.y, pw.z, bestC.x, bestC.y, bestC.z, best.x, best.y, best.z, q16.x / 16, q16.y / 16, q16.z / 16)) }
                if stitchOn { pinCell[SIMD3<Int32>(Int32(q16.x), Int32(q16.y), Int32(q16.z))] = (bestC, SIMD3<Int>(fx, fy, fz)) }
                return q16 / 16 * 2 - off
            }
            quad.removeAll(keepingCapacity: true)
            smoothQuads(vR, vs, dmg: [:], stored: vD, sy: sy, leafHoles: leafHoles, detailHoles: detailHoles, exact: exact, pin: pin) { x16, y16, z16, f, tint, layer, ao, l, ncode in
                emitted += 1
                let ex = (x16 + vx * 256) >> 1, ey = (y16 + vy * 256) >> 1, ez = (z16 + vz * 256) >> 1
                if stitchOn && !pinCell.isEmpty {
                    // (each drawn quad's four edges: both ends on the border, not neighbours there)
                    quad.append((SIMD3<Int32>(Int32(ex), Int32(ey), Int32(ez)), (f, tint, layer, ao, l, ncode)))
                    if quad.count == 4 {
                        for k in 0..<4 where quad[k].0 != quad[(k + 1) & 3].0 { stitch(quad[k].0, quad[(k + 1) & 3].0, quad[k].1) }
                        quad.removeAll(keepingCapacity: true)
                    }
                }
                if !fins.isEmpty {
                    lastAttr = (f, tint, layer, ao, l, ncode)
                    if let i = finAt[SIMD3<Int32>(Int32(ex), Int32(ey), Int32(ez))], fins[i].3 == nil { fins[i].3 = (f, tint, layer, ao, l, ncode) }
                }
                emit(ex, ey, ez, f, tint, layer, ao, l, ncode)
            }
            // (P383: the unsnapped positions, scaled back from half blocks like the snapped ones)
            if let ex = exact {
                for i in stride(from: e0, to: ex.count, by: 3) {
                    ex.ptr[i] = (ex.ptr[i] + Float(vx * 16)) * 0.5
                    ex.ptr[i + 1] = (ex.ptr[i + 1] + Float(vy * 16)) * 0.5
                    ex.ptr[i + 2] = (ex.ptr[i + 2] + Float(vz * 16)) * 0.5
                }
            }
            if timing { let t = CFAbsoluteTimeGetCurrent(); Mesher.fineT.quads += t - tA; tA = t }
        }
        sc.smValid = false
    }
}

// A section prefetchFine made: the chunk (its identity and a mark it was given then: an ObjectIdentifier outlives its
// chunk and comes back for the next one made at that address, which starts unmarked) and the section's version then.
// It counts as fresh only while both still hold: any edit since (a placed block's ensureFine, another carve) bumps the
// version, and a fresh section a sphere leaves as it was is let go, which would throw that edit's fine ground away.
// (Item 7: it held the chunk weakly, and a weak reference gives its object a side table for life: every retain and
// release of the chunks round a blast or a rut, the busiest chunks there are, took the slow path, part of the 6% of the
// worst-case soak's instructions in slow reference counting.)
struct FinePrefetch { let c: ObjectIdentifier; let mark: Int; let sy: Int; let version: Int }
extension World {
    static var finePrefetched: [FinePrefetch] = []      // (prefetchFine's sections not carved yet)
    static var fineMade = 0                              // (sections given their fine samples: the soak's slowest bowl step)
    // (BS_FINEWHY=1, the soak: which sections a bowl step made past its prefetch, printed by CraterJob)
    static let fineWhy = ProcessInfo.processInfo.environment["BS_FINEWHY"] == "1"
    static var fineLog: [SIMD3<Int32>] = []
    static var prefetchMarks = 0                         // (main thread)
    static func notePrefetched(_ c: Chunk, _ sy: Int) {
        if c.prefetchMark == 0 { prefetchMarks += 1; c.prefetchMark = prefetchMarks }
        if finePrefetched.count >= 64 { finePrefetched.removeFirst(finePrefetched.count - 63) }  // (never carved: let go)
        finePrefetched.append(FinePrefetch(c: ObjectIdentifier(c), mark: c.prefetchMark, sy: sy, version: c.sections[sy].version))
    }
    static func takePrefetched(_ c: Chunk, _ sy: Int) -> Bool {
        let id = ObjectIdentifier(c)
        guard c.prefetchMark != 0, let i = finePrefetched.firstIndex(where: { $0.c == id && $0.mark == c.prefetchMark && $0.sy == sy }) else { return false }
        let p = finePrefetched.remove(at: i)
        return p.version == c.sections[sy].version
    }
}
