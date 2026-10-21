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
        var f = [Int8](repeating: 0, count: FineField.count)
        for fy in 0..<32 { for fz in 0..<32 { for fx in 0..<32 {
            // Cell centres at local n + 0.5: the sample at (f + 0.5) / 2 lies between cells (f - 1) / 2 and that + 1.
            let bx = (fx - 1) >> 1, by = (fy - 1) >> 1, bz = (fz - 1) >> 1
            let t = SIMD3<Float>(fx & 1 == 0 ? 0.75 : 0.25, fy & 1 == 0 ? 0.75 : 0.25, fz & 1 == 0 ? 0.75 : 0.25)
            var v = SIMD8<Float>()
            var same = true
            let r0 = raw[(bx + 1) + (bz + 1) * N + (by + 1) * NN]
            for k in 0..<8 {
                let r = raw[(bx + 1 + (k & 1)) + (bz + 1 + (k >> 2)) * N + (by + 1 + ((k >> 1) & 1)) * NN]
                v[k] = Float(r)
                if r != r0 { same = false }
            }
            f[FineField.index(fx, fy, fz)] = FineField.upsample(v, raw0: r0, allSame: same, t)       // (corners: bit 0 x, 1 y, 2 z)
        } } }
        c.blocks.fine[sy] = f
        return true
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
                for sy in s0...s1 { out.append((c, sy, ensureFine(c, sy))) }
            }
        }
        return out
    }

    // fieldBoxes for a cell whose ground reads fine samples: the 4 x 4 quarter-block columns, each solid between the
    // lowest and highest of 9 points up its centre line inside the ground (the fine field as the mesh draws it).
    func fineColumns(_ x: Int, _ y: Int, _ z: Int, _ out: UnsafeMutablePointer<Float>) {
        for v in 0..<4 { for u in 0..<4 {
            let px = Float(x) + (Float(u) + 0.5) / 4, pz = Float(z) + (Float(v) + 0.5) / 4
            var lo: Float = -1, hi: Float = -1
            var prev = fineDensity(at: V3(px, Float(y), pz)), prevT: Float = 0
            if prev > 0 { lo = 0; hi = 0 }
            for s in 1...8 {
                let t = Float(s) / 8
                let d = fineDensity(at: V3(px, Float(y) + t, pz))
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
            for s in max(0, sy - 1)...min(NSEC - 1, sy + 1) where st.fine[s] != nil { return true }
        }
        return false
    }

    // The section's ground at half-block cells: its 16^3 blocks as eight 16^3 sections of half blocks, each meshed by
    // smoothQuads on a region built at half scale (cells, light and materials of the block each half block is in; the
    // density from the fine samples, or upsampled from the cells, in half-block units), positions scaled back.
    static func fineGround(_ n9: [BlockStore], sy: Int, _ R: UnsafeMutablePointer<BlockID>, _ sc: MeshScratch, leafHoles: Bool, detailHoles: Bool,
                           exact: GrowBuf<Float>? = nil, _ emit: (Int, Int, Int, Int, Int, Int, Int, Int, Int) -> Void) {
        let vs = sc.fineScratch
        let vR = vs.region, vSky = vs.sky, vBlk = vs.blk, vD = vs.dens
        let dens = sc.dens, sky = sc.sky, blk = sc.blk
        let natT = SmoothTerrain.natural, opaqueT = Blocks.opaque, loT = Blocks.lightOpaque
        @inline(__always) func ri(_ x: Int, _ y: Int, _ z: Int) -> Int { (x + C0) + (z + C0) * RW + (y + C0) * RL }
        // (smoothQuads reads its section's 0...16 and a ring of maxRelax + 3 round it)
        let lo = max(0, C0 - SmoothTerrain.maxRelax - 4), hi = min(RW - 1, C0 + 21 + SmoothTerrain.maxRelax)
        vR.initialize(repeating: AIR, count: RL * RH)
        vD.initialize(repeating: FieldTerrain.outside, count: RL * RH)
        for v in 0..<8 {
            let vx = v & 1, vy = (v >> 1) & 1, vz = v >> 2
            for ry in lo...hi { for rz in lo...hi { for rx in lo...hi {
                let gx = rx - C0 + vx * 16, gy = ry - C0 + vy * 16, gz = rz - C0 + vz * 16     // fine, section-local
                let j = rx + rz * RW + ry * RL
                let src = ri(gx >> 1, gy >> 1, gz >> 1)
                var d: Int8
                if let f = n9[(gx >> 5) + 1 + ((gz >> 5) + 1) * 3].fine[sy + (gy >> 5)] {
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
                vD[j] = d == FieldTerrain.inside || d == FieldTerrain.outside ? d : Int8(max(-126, min(126, Int(d) * 2)))
                // The half block's own: ground where its sample is inside (the cell's ground material, or the one it had
                // before it was dug), open where it is outside; a built block stays what it is.
                let rb = R[src]
                let cellGround = dens[src] > 0 && natT[Int(rb)]
                var b = rb
                if d > 0 && !cellGround && (rb == AIR || !opaqueT[Int(rb)]) {
                    // (the ground beside it, under it first: grass reaching up into the open cell over it stays grass)
                    b = DIRT
                    var found = false
                    for o in [-RL, 1, -1, RW, -RW, RL] where dens[src + o] > 0 && natT[Int(R[src + o])] { b = R[src + o]; found = true; break }
                    if !found {
                        let bx = gx >> 1, by = sy * 16 + (gy >> 1), bz = gz >> 1
                        let st = n9[(bx >> 4) + 1 + ((bz >> 4) + 1) * 3]
                        let m = by >= 0 && by < CH ? Int(st.material(Chunk.index(bx & 15, by, bz & 15))) : 0
                        if m != 0 { b = FieldMat.blocks[m] }
                    }
                } else if d <= 0 && cellGround {
                    b = AIR
                }
                vR[j] = b
                var sl = sky[src], bl = blk[src]
                if !loT[Int(b)] && loT[Int(rb)] {
                    // (open inside a cell the light flood took as solid: the light of the open cells beside it)
                    for o in [1, -1, RW, -RW, RL, -RL] where !loT[Int(R[src + o])] { sl = max(sl, sky[src + o]); bl = max(bl, blk[src + o]) }
                }
                vSky[j] = sl; vBlk[j] = bl
            } } }
            let e0 = exact?.count ?? 0
            smoothQuads(vR, vs, dmg: [:], stored: vD, sy: sy, leafHoles: leafHoles, detailHoles: detailHoles, exact: exact) { x16, y16, z16, f, tint, layer, ao, l, ncode in
                emit((x16 + vx * 256) >> 1, (y16 + vy * 256) >> 1, (z16 + vz * 256) >> 1, f, tint, layer, ao, l, ncode)
            }
            // (P383: the unsnapped positions, scaled back from half blocks like the snapped ones)
            if let ex = exact {
                for i in stride(from: e0, to: ex.count, by: 3) {
                    ex.ptr[i] = (ex.ptr[i] + Float(vx * 16)) * 0.5
                    ex.ptr[i + 1] = (ex.ptr[i + 1] + Float(vy * 16)) * 0.5
                    ex.ptr[i + 2] = (ex.ptr[i + 2] + Float(vz * 16)) * 0.5
                }
            }
        }
        sc.smValid = false
    }
}
