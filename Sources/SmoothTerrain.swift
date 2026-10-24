import Foundation
import simd

// Smooth terrain PROTOTYPE (docs/proposals/smooth-terrain.md; off by default, decision pending).
// The world stays blocks: saves, world gen, mining, pathing and circuits are unchanged. Only natural blocks
// (stone, dirt, grass, sand, ores...) mesh differently: a surface-nets surface over the solid cells instead of
// cube faces. Crafted and player-only blocks (planks, cobblestone, bricks, workblocks) stay cubic and count as
// solid for the surface, so the ground blends into them. Natural blocks a player places are smooth too.
//
// Surface nets on the block grid: samples at block centres, solid = opaque. One vertex per dual cell (the 2x2x2
// block centres around a lattice point) at the average of its edge crossings; one quad per block pair with a
// natural solid on one side and a non-solid on the other. The crossing point uses a lightly blurred density
// (half the cell itself, half its 3x3x3 neighbourhood), so the sign is always the block's own (no block vanishes)
// while corners and steps round off; flat ground stays exactly at the block top.
// Quads use the existing vertex format: the dominant normal axis picks the face (texture projection) and u = 31
// projects the texture from the position. Smooth vertices also carry a smooth normal (the gradient of the block
// solidity around the vertex, so the same on both sides of a section border): v < 31 plus the overlay bit hold
// `normalCode`, two tilts toward the face's tangent axes; v = 31 stays the plain projected quad (greedy faces).
// The shaders light smooth vertices with that normal (Gouraud), not the face's 6-direction shade.
// A section owns the dual cells 0...16 of its own corner (vertices 0.5...17.5 blocks, never negative in the
// unsigned 1/16 position bits), so it meshes quads that touch its +x/+y/+z neighbours' first block row.
enum SmoothTerrain {
    // A world option (Create New World > Terrain, saved as the world's extra "terrain" = "smooth"; Video > Smooth
    // Terrain switches the open world), or `--smooth` / `--cubic` on the command line, which win over the world's
    // choice (harness, bench, smoke).
    static let forced: Bool? = {
        let a = CommandLine.arguments
        if a.contains("--cubic") { return false }
        return a.contains("--smooth") ? true : nil
    }()
    static var enabled: Bool = forced ?? false

    // The world's own choice (Game.smoothTerrain), unless the command line forces a mode.
    // (PG1: a field world's ground is the field: always smooth.)
    static func use(world on: Bool, world w: World?) { set(w?.fieldTerrain == true ? true : (forced ?? on), world: w) }

    // Per block state: meshes as smooth ground: the realistic world's terrain class (ShapeClass: natural ground and rock
    // the generators lay down, ores, plus the round-2 cave survey's list).
    static let natural: [Bool] = ShapeClass.kind.map { $0 == .terrain }

    // Per block state: a built shape the ground must meet exactly (crafted solids, paths, farmland, fences, logs...).
    // Surface vertices touching one sit on the block corner instead of rounding, so no notch opens under its edge.
    static let pins: [Bool] = (0..<Blocks.count).map { i in
        let n = Blocks.key(BlockID(i))
        if natural[i] || n == "snow" || n.hasSuffix("_leaves") { return false }
        return Blocks.opaque[i] || Blocks.collide[i]
    }
    // ...with the realistic world's round shapes (Mesher.detailT) open: the ground runs under a trunk's root flare.
    static let pinsDetail: [Bool] = (0..<Blocks.count).map { pins[$0] && !Mesher.detailT[$0] }

    // Common rock the smooth mesher shows as the majority round a block (P142): never ores, magma or soil.
    static let rockIDs: [Int] = ["stone", "deepslate", "emberslate", "blackstone", "basalt", "smooth_basalt", "tuff", "andesite",
                                 "diorite", "granite", "netherrack"].map { Int(Blocks.id($0)) }.filter { natural[$0] }
    static let rockSlot: [Int8] = (0..<Blocks.count).map { i in Int8(rockIDs.firstIndex(of: i) ?? -1) }
    // Ground the smooth mesher blends at its borders (P142): natural blocks except ores and the few that must read on
    // their own (magma burns, geodes and sculk are finds).
    static let blend: [Bool] = (0..<Blocks.count).map { i in
        let n = Blocks.key(BlockID(i))
        return natural[i] && !n.hasSuffix("_ore") && !["magma_block", "amethyst_block", "budding_amethyst", "sculk"].contains(n)
    }
    static let snowLayer = Int(Blocks.id("snow"))
    // The blocks a rock face polls: the 3x3x3 round it.
    static let voteProbe: [(Int, Int, Int)] = {
        var r: [(Int, Int, Int)] = []
        for dy in -1...1 { for dz in -1...1 { for dx in -1...1 { r.append((dx, dy, dz)) } } }
        return r
    }()
    // Where a dirt block facing up looks for the turf it lies under: above it, then beside it and beside-above.
    static let turfProbe: [(Int, Int, Int)] = [(0, 1, 0), (0, 2, 0), (1, 1, 0), (-1, 1, 0), (0, 1, 1), (0, 1, -1),
                                               (1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0, 3, 0)]
    // Vertex normal code: tilt levels toward the face's tangent axes (axis+1, axis+2), finer near flat ground.
    // The shaders hold the same table (smoothNormal in chunk.vert / Shaders.swift / VibrantShaders / ship shaders).
    static let tiltLevels: [Float] = [-1, -0.5, -0.2, 0, 0.2, 0.5, 1]
    // P106 surface relaxation (Mesher.smoothQuads): passes and how far each moves a vertex to its neighbours' mean.
    // BLOCKSMITH_RELAX=0 meshes the round-1 surface (side by side shots, cost).
    static var relax: Int = max(0, min(maxRelax, Int(ProcessInfo.processInfo.environment["BLOCKSMITH_RELAX"] ?? "") ?? 4))
    static let maxRelax = 4
    // P142: overworld sections mesh the generator's continuous fields (SmoothField); BLOCKSMITH_FIELD=0 meshes round
    // the blocks as round 2 did (side by side shots).
    static var fromField = ProcessInfo.processInfo.environment["BLOCKSMITH_FIELD"] != "0"
    static let relaxRate: Float = 0.8
    // T17: in field worlds leaf canopies mesh as rounded blobs (Mesher.smoothQuads leaves pass) instead of leaf cubes;
    // BLOCKSMITH_LEAFBLOB=0 keeps the cubes (side by side shots).
    static var leafBlobs = ProcessInfo.processInfo.environment["BLOCKSMITH_LEAFBLOB"] != "0"
    static var vertexHook: ((Int, Int, Int, SIMD3<Float>) -> Void)?   // tests: every owned dual vertex after relaxing
    static func normalCode(_ n: SIMD3<Float>, face f: Int) -> Int {
        let a = f / 2, sgn: Float = f & 1 == 0 ? 1 : -1
        let na = max(0.1, n[a] * sgn)
        func level(_ t: Float) -> Int {
            var best = 0
            for i in 1..<7 where abs(tiltLevels[i] - t) < abs(tiltLevels[best] - t) { best = i }
            return best
        }
        return level(n[(a + 1) % 3] / na) * 7 + level(n[(a + 2) % 3] / na)
    }

    // P383 step 2 (one vertex per ground position): field ground vertices carry everything they shade by per position,
    // never per quad: an absolute normal (octahedral, 22 x 22 cells in 9 bits: the shade bits, the overlay bit and v),
    // the texture picked by the vertex's own normal (not the quad's facing), and the shader projects the texture
    // triplanar from the world position (chunk.vert / chunk_solid.frag: u = 30 marks these). So the surface nets' quads
    // round a vertex all draw it with the same words, and the adaptive ground can join across the old facing seams.
    // Quest only (the Mac's shaders keep the per-face code); BS_TRIGROUND=0 keeps the old facing (before/after shots).
    #if os(macOS)
    static var triGround = false
    #else
    static var triGround = ProcessInfo.processInfo.environment["BS_TRIGROUND"] != "0"
    #endif
    static let triN = 22
    // The 9-bit code of a unit normal (0..<484): its octahedral map's cell.
    static func triCode(_ n: SIMD3<Float>) -> Int {
        let l1 = abs(n.x) + abs(n.y) + abs(n.z)
        guard l1 > 1e-6 else { return triCode(SIMD3<Float>(0, 1, 0)) }
        var e = SIMD2<Float>(n.x, n.z) / l1
        if n.y < 0 {
            let ex = (1 - abs(e.y)) * (e.x >= 0 ? 1 : -1), ez = (1 - abs(e.x)) * (e.y >= 0 ? 1 : -1)
            e = SIMD2<Float>(ex, ez)
        }
        let i = max(0, min(triN - 1, Int(floor((e.x * 0.5 + 0.5) * Float(triN)))))
        let j = max(0, min(triN - 1, Int(floor((e.y * 0.5 + 0.5) * Float(triN)))))
        return i + j * triN
    }
    // The normal a code stands for (the shader's octDecode; tests and the harness).
    static func triNormal(_ code: Int) -> SIMD3<Float> {
        let e = (SIMD2<Float>(Float(code % triN), Float(code / triN)) + 0.5) / Float(triN) * 2 - 1
        var n = SIMD3<Float>(e.x, 1 - abs(e.x) - abs(e.y), e.y)
        if n.y < 0 { n.x = (1 - abs(e.y)) * (e.x >= 0 ? 1 : -1); n.z = (1 - abs(e.x)) * (e.y >= 0 ? 1 : -1) }
        return simd_normalize(n)
    }
    // The texture face a vertex normal picks (the quads' own rule, on the vertex's normal).
    static func triFace(_ n: SIMD3<Float>) -> Int {
        let ax = abs(n.x), ay = abs(n.y), az = abs(n.z)
        if n.y > 0.5 { return 2 }
        if ay >= ax && ay >= az { return n.y > 0 ? 2 : 3 }
        if ax >= az { return n.x > 0 ? 0 : 1 }
        return n.z > 0 ? 4 : 5
    }

    // Turns the mode on/off and remeshes everything loaded.
    static func set(_ on: Bool, world: World?) {
        guard on != enabled else { return }
        enabled = on
        world?.remeshAll()
    }
}

extension Mesher {
    // P175: the drawn ground height (section-local blocks) over the top of block (x, gy, z) (section-local), the mean of
    // the smooth surface vertices at its 4 top corners as the last ground pass left them in `sc`; nil if none.
    static func smoothGroundTop(_ sc: MeshScratch, _ x: Int, _ gy: Int, _ z: Int) -> Float? {
        let KO = SmoothTerrain.maxRelax, K = 17 + 2 * KO, KK = K * K
        let cy = gy + KO
        guard cy >= 0 && cy < K else { return nil }
        var sum: Float = 0, n: Float = 0
        for dz in -1...0 { for dx in -1...0 {
            let cx = x + dx + KO, cz = z + dz + KO
            guard cx >= 0 && cx < K && cz >= 0 && cz < K else { continue }
            let vi = cx + cz * K + cy * KK
            if sc.smL[vi] >= 0 { sum += sc.smV[vi * 3 + 1]; n += 1 }
        } }
        return n > 0 ? sum / n : nil
    }

    // P297 (b): the drawn ground's height (section-local) at block corner (X, Z) (section-local corner coordinates): the
    // smooth surface vertex there in the rows over block ly, ly - 1 or ly - 2 (the first found); nil if none.
    static func groundCorner(_ sc: MeshScratch, _ X: Int, _ ly: Int, _ Z: Int) -> Float? {
        guard sc.smValid else { return nil }
        let KO = SmoothTerrain.maxRelax, K = 17 + 2 * KO, KK = K * K
        let cx = X - 1 + KO, cz = Z - 1 + KO
        guard cx >= 0 && cx < K && cz >= 0 && cz < K else { return nil }
        for gy in stride(from: ly, through: ly - 2, by: -1) {
            let cy = gy + KO
            guard cy >= 0 && cy < K else { continue }
            let vi = cx + cz * K + cy * KK
            if sc.smL[vi] >= 0 { return sc.smV[vi * 3 + 1] }
        }
        return nil
    }

    // Does the +x / +z / +y boundary row of an all-air section's 17^3 block range hold natural ground? Then the
    // section still owns smooth quads there.
    static func smoothEdgeNatural(_ srcs: [[BlockID]], sy: Int, leaves: Bool = false) -> Bool {
        let nat = SmoothTerrain.natural, leafT = Mesher.leafT
        for ly in 0...16 {
            let wy = sy * 16 + ly
            if wy >= CH { break }
            for lz in 0...16 {
                for lx in 0...16 where lx == 16 || lz == 16 || ly == 16 {
                    let src = srcs[(lx == 16 ? 2 : 1) + (lz == 16 ? 2 : 1) * 3]
                    let si = (lx & 15) + (lz & 15) * CS + wy * CSQ
                    if si < src.count && (nat[Int(src[si])] || leaves && leafT[Int(src[si])]) { return true }
                }
            }
        }
        return false
    }

    // PG1: does the +x / +z / +y boundary row of the section's 17^3 range hold field ground (field worlds)?
    static func fieldEdgeGround(_ n9: [BlockStore], sy: Int) -> Bool {
        for ly in 0...16 {
            let wy = sy * 16 + ly
            if wy >= CH { break }
            for lz in 0...16 {
                for lx in 0...16 where lx == 16 || lz == 16 || ly == 16 {
                    if n9[(lx == 16 ? 2 : 1) + (lz == 16 ? 2 : 1) * 3].ground((lx & 15) + (lz & 15) * CS + wy * CSQ) { return true }
                }
            }
        }
        return false
    }

    // P283: far field ground (lod 1, past World.lodNear): the field's surface dual-contoured on a lattice two blocks
    // apart, a quarter of the quads (the far ground was a quarter of a Polygons world's quads on his homestead replay).
    // Every far section samples the same world-aligned lattice, so far chunks meet exactly. Toward a nearer chunk
    // (`nearSides`: bit 0 -x, 1 +x, 2 -z, 3 +z) the border cells' vertices go onto the border plane (-x, -z) or a block
    // past it (+x, +z), so the near chunk's finer surface and this one overlap instead of leaving a slit between them.
    // Flat ao, one material a quad (the ground half a block under its middle), no dents or craters that far out.
    static func coarseGround(_ R: UnsafeMutablePointer<BlockID>, _ E: UnsafeMutablePointer<Int8>, _ sc: MeshScratch, nearSides: Int,
                             _ emit: (Int, Int, Int, Int, Int, Int, Int, Int, Int) -> Void) {
        let nat = SmoothTerrain.natural, texT = Blocks.tex, tintT = Blocks.tint, loT = Blocks.lightOpaque
        let skyL = sc.sky, blkL = sc.blk
        func ri(_ x: Int, _ y: Int, _ z: Int) -> Int { (x + C0) + (z + C0) * RW + (y + C0) * RL }
        // Lattice points at section-local -2, 0, ..., 18 (index i at 2i - 2): density in blocks, > 0 inside.
        let L = 11, LL = L * L
        let D = sc.smD
        var any = false
        for iy in 0..<L { for iz in 0..<L { for ix in 0..<L {
            let e = E[ri(ix * 2 - 2, iy * 2 - 2, iz * 2 - 2)]
            if e > 0 { any = true }
            D[ix + iz * L + iy * LL] = max(-1.5, min(1.5, Float(e) / FieldTerrain.scale))
        } } }
        if !any { return }
        // Cells (index = the lattice index of their low corner, 0...9): vertex, light, normal.
        let CN = 10, CNN = CN * CN
        let VP = sc.smV, VL = sc.smL, VN = sc.smN
        for cy in 0..<CN { for cz in 0..<CN { for cx in 0..<CN {
            let vi = cx + cz * CN + cy * CNN
            var d8 = SIMD8<Float>(repeating: 0)
            var mask = 0
            for c in 0..<8 {
                let v = D[(cx + (c & 1)) + (cz + (c >> 2)) * L + (cy + ((c >> 1) & 1)) * LL]
                d8[c] = v
                if v > 0 { mask |= 1 << c }
            }
            if mask == 0 || mask == 255 { VL[vi] = -1; continue }
            var sum = SIMD3<Float>(0, 0, 0)
            var n: Float = 0
            for c in 0..<8 {
                for sh in 0..<3 where (c >> sh) & 1 == 0 {
                    let c2 = c | (1 << sh)
                    if (mask >> c & 1) == (mask >> c2 & 1) { continue }
                    let ins = (mask >> c) & 1 == 1
                    let a: Float = ins ? max(0.02, d8[c]) : min(-0.02, d8[c])
                    let b: Float = ins ? min(-0.02, d8[c2]) : max(0.02, d8[c2])
                    let t: Float = a / (a - b)
                    let p1 = SIMD3<Float>(Float(c & 1), Float((c >> 1) & 1), Float(c >> 2))
                    let p2 = SIMD3<Float>(Float(c2 & 1), Float((c2 >> 1) & 1), Float(c2 >> 2))
                    sum += p1 + (p2 - p1) * t
                    n += 1
                }
            }
            let base = SIMD3<Float>(Float(cx * 2 - 2), Float(cy * 2 - 2), Float(cz * 2 - 2))
            var p = base + sum / n * 2
            if nearSides & 1 != 0 && cx == 0 { p.x = 0 }
            if nearSides & 2 != 0 && cx == CN - 1 { p.x = max(p.x, 17) }
            if nearSides & 4 != 0 && cz == 0 { p.z = 0 }
            if nearSides & 8 != 0 && cz == CN - 1 { p.z = max(p.z, 17) }
            VP[vi * 3] = p.x; VP[vi * 3 + 1] = p.y; VP[vi * 3 + 2] = p.z
            // Normal: minus the gradient of the 8 densities (corner bits: 1 x, 2 y, 4 z).
            let gx: Float = (d8[1] + d8[3] + d8[5] + d8[7]) - (d8[0] + d8[2] + d8[4] + d8[6])
            let gy: Float = (d8[2] + d8[3] + d8[6] + d8[7]) - (d8[0] + d8[1] + d8[4] + d8[5])
            let gz: Float = (d8[4] + d8[5] + d8[6] + d8[7]) - (d8[0] + d8[1] + d8[2] + d8[3])
            VN[vi * 3] = -gx; VN[vi * 3 + 1] = -gy; VN[vi * 3 + 2] = -gz
            // Light: the mean over the cell's open corners.
            var sky = 0, blk = 0, open = 0
            for c in 0..<8 {
                let i = ri((cx + (c & 1)) * 2 - 2, (cy + ((c >> 1) & 1)) * 2 - 2, (cz + (c >> 2)) * 2 - 2)
                if loT[Int(R[i])] { continue }
                sky += Int(skyL[i]); blk += Int(blkL[i]); open += 1
            }
            VL[vi] = Int32(open == 0 ? 0 : ((sky + open / 2) / open) | (((blk + open / 2) / open) << 4))
        } } }
        // Quads: lattice edge p -> p + 1 along a (a 1...8) between ground and open, its 4 cells round it. Across a the
        // section owns 0...16 (lattice 1...9 on x and z, both borders: the far neighbour skips its own 0), up 2...16;
        // a -x / -z border toward a nearer chunk is also drawn here (its cells pushed onto the border plane).
        let loX = nearSides & 1 != 0 ? 1 : 2, loZ = nearSides & 4 != 0 ? 1 : 2
        var corner = [Int](repeating: 0, count: 4)
        var pts = [SIMD3<Float>](repeating: .zero, count: 4)
        for py in 1...9 { for pz in 1...9 { for px in 1...9 {
            let p = SIMD3<Int>(px, py, pz)
            for a in 0..<3 {
                let b = (a + 1) % 3, c = (a + 2) % 3
                if p[a] > 8 { continue }
                func lo(_ ax: Int) -> Int { ax == 0 ? loX : (ax == 2 ? loZ : 2) }
                if p[b] < lo(b) || p[c] < lo(c) { continue }
                var q = p
                q[a] += 1
                let sp = D[p[0] + p[2] * L + p[1] * LL] > 0
                let sq = D[q[0] + q[2] * L + q[1] * LL] > 0
                if sp == sq { continue }
                let s = sp ? p : q
                let sb = SIMD3<Int>(s[0] * 2 - 2, s[1] * 2 - 2, s[2] * 2 - 2)
                if !nat[Int(R[ri(sb[0], sb[1], sb[2])])] { continue }
                var ok = true
                for k in 0..<4 {
                    var d = p
                    let kk = sp ? k : 3 - k
                    d[b] -= (kk == 0 || kk == 3) ? 1 : 0
                    d[c] -= (kk == 0 || kk == 1) ? 1 : 0
                    let vi = d[0] + d[2] * CN + d[1] * CNN
                    if VL[vi] < 0 { ok = false; break }
                    corner[k] = vi
                    pts[k] = SIMD3<Float>(VP[vi * 3], VP[vi * 3 + 1], VP[vi * 3 + 2])
                }
                if !ok { continue }
                let nrm = simd_cross(pts[2] - pts[0], pts[3] - pts[1])
                let ax = abs(nrm.x), ay = abs(nrm.y), az = abs(nrm.z)
                let len = simd_length(nrm)
                guard len > 1e-6 else { continue }
                let f: Int
                if nrm.y > 0.5 * len { f = 2 }
                else if ay >= ax && ay >= az { f = nrm.y > 0 ? 2 : 3 }
                else if ax >= az { f = nrm.x > 0 ? 0 : 1 }
                else { f = nrm.z > 0 ? 4 : 5 }
                // The ground half a block under the quad's middle (the lattice sample may be the dirt under the turf).
                let mid = (pts[0] + pts[1] + pts[2] + pts[3]) * 0.25 - nrm / len * 0.5
                let mi = ri(Int(floor(mid.x)), Int(floor(mid.y)), Int(floor(mid.z)))
                var id = E[mi] > 0 && nat[Int(R[mi])] ? Int(R[mi]) : Int(R[ri(sb[0], sb[1], sb[2])])
                if id == Int(DIRT) && nrm.y > 0.35 * len {
                    turf: for (dx, dy, dz) in SmoothTerrain.turfProbe {
                        let t = Int(R[ri(sb[0] + dx, sb[1] + dy, sb[2] + dz)])
                        if nat[t] && tintT[t] == 3 { id = t; break turf }
                    }
                }
                let tintB = Int(tintT[id])
                let texF = tintB == 3 ? (nrm.y > 0.2 * len ? 2 : 3) : f
                let layer = Int(texT[id * 6 + texF])
                let tint = tintB == 3 ? (texF == 2 ? 1 : 0) : tintB
                for k in 0..<4 {
                    let vi = corner[k]
                    var vn = SIMD3<Float>(VN[vi * 3], VN[vi * 3 + 1], VN[vi * 3 + 2])
                    vn = simd_length_squared(vn) > 1e-6 ? simd_normalize(vn) : nrm / len
                    let pt = pts[k] * 16
                    emit(Int(pt.x.rounded()), Int(pt.y.rounded()), Int(pt.z.rounded()), f, tint, layer, 3, Int(VL[vi]) & 255,
                         SmoothTerrain.normalCode(vn, face: f))
                }
            }
        } } }
    }

    // Smooth quads for the section whose local 0 is region (C0, C0, C0). `emit` takes position (1/16 block,
    // section-local), face, tint, layer, ao, packed light, overlay.
    // `site` (P142): the section's chunk in a world whose generator has fields; nil meshes round the blocks (round 2).
    // `leaves` (T17): mesh the leaf blocks instead, as rounded blobs (round-2 rounding, no pins), each quad twice: the
    // outer shell and a darker one 0.45 block inside it, so the leaf texture's holes show leaves behind, not the sky.
    // `leafHoles`: the ground pass treats leaves as open (their blobs mesh apart and the ground under a bush shows).
    // `stored` (PG1 field worlds): the region's stored densities (1/32 block, > 0 inside, region indices like R). The
    // surface is the field's own: crossings and normals from the densities, no relaxing, no block rounding (dual
    // contouring of the field; a built block meeting the ground counts as 0.35 block inside).
    static func smoothQuads(_ R: UnsafeMutablePointer<BlockID>, _ sc: MeshScratch, dmg: [Int: UInt8], site: SmoothSite? = nil,
                            stored: UnsafeMutablePointer<Int8>? = nil, sy: Int = 0,
                            leaves: Bool = false, shells: Int = 2, leafHoles: Bool = false, detailHoles: Bool = false, world: SIMD3<Int>? = nil,
                            crater: CraterSet? = nil, carveOut: GrowBuf<UInt32>? = nil, merge: GroundMerge? = nil,
                            exact: GrowBuf<Float>? = nil, tri: Bool = false,
                            pin: ((Int, Int, Int, SIMD3<Float>) -> SIMD3<Float>?)? = nil,
                            _ emit: (Int, Int, Int, Int, Int, Int, Int, Int, Int) -> Void) {
        let leafT = Mesher.leafT
        let nat = leaves ? leafT : SmoothTerrain.natural, opaqueT = Blocks.opaque, aoT = Blocks.aoOcc, loT = Blocks.lightOpaque
        let texT = Blocks.tex, tintT = Blocks.tint, pinT = detailHoles ? SmoothTerrain.pinsDetail : SmoothTerrain.pins, rockSlot = SmoothTerrain.rockSlot
        let detT = Mesher.detailT
        let skyL = sc.sky, blkL = sc.blk
        func ri(_ x: Int, _ y: Int, _ z: Int) -> Int { (x + C0) + (z + C0) * RW + (y + C0) * RL }

        // Anything natural in the owned 17^3 block range?
        var any = false
        scan: for y in 0...16 { for z in 0...16 { for x in 0...16 where nat[Int(R[ri(x, y, z)])] { any = true; break scan } } }
        if !any { return }

        // The ring past the owned dual cells 0...16 that the relaxation reads (one block a pass, at most `maxRelax`).
        let KO = SmoothTerrain.maxRelax
        // Solid flags for blocks -KO-1...KO+18 (index +KO+1).
        let N = 20 + 2 * KO, NN = N * N, SO = KO + 1
        let S = sc.smS
        for y in 0..<N { for z in 0..<N { for x in 0..<N {
            let b = Int(R[ri(x - SO, y - SO, z - SO)])
            S[x + z * N + y * NN] = (leaves ? leafT[b] : opaqueT[b] && !(leafHoles && leafT[b]) && !(detailHoles && detT[b])) ? 1 : 0
        } } }
        // P142: the generator's fields over the same box (SmoothField). A sample is "on field" when its block is what the
        // fields alone make there (and not being dug); only edges between two on-field samples take the field's crossing.
        let FO = sc.smF
        let field: SmoothField? = site.map { site in
            let F = sc.field
            F.prepare(site.gen, x0: site.cx * CS - SO, y0: sy * 16 - SO, z0: site.cz * CS - SO, edits: site.edits)
            FO.initialize(repeating: 0, count: N * NN)
            return F
        }
        func onField(_ i: Int) -> Bool {
            let o = FO[i]
            if o != 0 { return o == 1 }
            guard let F = field else { return false }
            var on = F.inWorld(i) && (S[i] != 0) == F.solid(i)
            if on && S[i] != 0 && !dmg.isEmpty {
                let bx = i % N - SO, bz = (i / N) % N - SO, by = i / NN - SO
                if dmg[ri(bx, by, bz)] != nil { on = false }
            }
            FO[i] = on ? 1 : 2
            return on
        }
        var anyLoose = field == nil && stored == nil
        let fieldLike = field != nil || stored != nil
        let triOn = SmoothTerrain.triGround && (tri || !leaves && stored != nil)     // (P384: a far leaf shell asks for it)
        // PG1: the effective density at region index r (blocks): the field's, or 0.35 for a built solid block.
        @inline(__always) func eff(_ r: Int) -> Float {
            guard let E = stored else { return 0 }
            let d = E[r]
            if d > 0 { return Float(d) / FieldTerrain.scale }
            let b = Int(R[r])
            if opaqueT[b] && !(leafHoles && leafT[b]) && !(detailHoles && detT[b]) { return 0.35 }
            return max(-1.5, Float(d) / FieldTerrain.scale)
        }
        // ...for a surface crossing: a cell the split never shaped (far inside or outside) beside one of the other sign can
        // only be a chunk border where the two chunks' generators disagreed (a rule carved one side): half a block, as
        // the cells meet, not four blocks (which pushed the surface almost onto the other cell: a seam of beads).
        @inline(__always) func effX(_ r: Int) -> Float {
            guard let E = stored else { return 0 }
            let d = E[r]
            if d == FieldTerrain.inside { return 0.5 }
            let v = eff(r)
            return d == FieldTerrain.outside && v < 0 ? -0.5 : v
        }
        @inline(__always) func sToR(_ i: Int) -> Int { ri(i % N - SO, i / NN - SO, (i / N) % N - SO) }

        // Density for blocks -KO...KO+17 (index +KO): half the block, half its 3x3x3 mean. A chipped natural
        // block (being dug, P106) keeps its smooth surface but shrinks toward its centre as the chips come off (its
        // solid density falls toward the 0.5 threshold), instead of turning back into a cube of sub-cubes.
        let M = 18 + 2 * KO, MM = M * M, DO = KO
        let D = sc.smD
        if field == nil && stored == nil { for y in 0..<M { for z in 0..<M { for x in 0..<M {
            var s = 0
            for dy in 0...2 { for dz in 0...2 {
                let row = x + (z + dz) * N + (y + dy) * NN
                s += Int(S[row]) + Int(S[row + 1]) + Int(S[row + 2])
            } }
            let selfS = S[(x + 1) + (z + 1) * N + (y + 1) * NN]
            var d = 0.5 * Float(selfS) + Float(s) / 54
            if selfS != 0, !dmg.isEmpty, let dv = dmg[ri(x - DO, y - DO, z - DO)] {
                let lv = Float(min(7, Int(dv & 31)) + 1) / 8
                d = 0.5 + max(0.012, (d - 0.5) * (1 - 0.92 * lv))
            }
            D[x + z * M + y * MM] = d
        } } } }

        // Dual cell vertices -KO...16+KO (index +KO): position (blocks, section-local), light, ao. The ring past
        // 0...16 feeds the relaxation, so a vertex comes out the same in every section that meshes it.
        let K = 17 + 2 * KO, KK = K * K
        let VP = sc.smV, VL = sc.smL, VN = sc.smN, VQ = sc.smQ, VM = sc.smM
        let blendT = SmoothTerrain.blend, snowL = SmoothTerrain.snowLayer, snowB = Int(SNOW)
        let dW: [Float] = [-0.5, -1, 1, 0.5], tW: [Float] = [0.5, 1, 1, 0.5]   // normal stencil: blocks c-1...c+2
        for ky in 0..<K { for kz in 0..<K { for kx in 0..<K {
            let cx = kx - KO, cy = ky - KO, cz = kz - KO
            let vi = kx + kz * K + ky * KK
            var mask = 0
            for c in 0..<8 where S[(cx + SO + (c & 1)) + (cz + SO + (c >> 2)) * N + (cy + SO + ((c >> 1) & 1)) * NN] != 0 { mask |= 1 << c }
            if mask == 0 || mask == 255 { VL[vi] = -1; continue }
            var sum = SIMD3<Float>(0, 0, 0)
            var n: Float = 0
            // P142: the field's own crossings, and its outward direction per field that made one (0 terrain, 1-3 caves).
            var loose = false
            var fn = SIMD3<Float>(0, 0, 0)
            var fnSeen = 0
            let cell0 = (cx + SO) + (cz + SO) * N + (cy + SO) * NN
            for c in 0..<8 {
                for sh in 0..<3 where (c >> sh) & 1 == 0 {
                    let bit = 1 << sh
                    let c2 = c | bit
                    if (mask >> c & 1) == (mask >> c2 & 1) { continue }
                    let t: Float
                    if let F = field {
                        let i1 = cell0 + (c & 1) + (c >> 2) * N + ((c >> 1) & 1) * NN
                        let i2 = cell0 + (c2 & 1) + (c2 >> 2) * N + ((c2 >> 1) & 1) * NN
                        let s1 = (mask >> c) & 1 == 1
                        let a = s1 ? i1 : i2, b = s1 ? i2 : i1
                        let oa = onField(a), ob = onField(b)
                        if oa && ob, let (tt, which) = F.crossing(a, b) {
                            t = s1 ? tt : 1 - tt
                            if fnSeen & (1 << which) == 0 { fnSeen |= 1 << which; fn += F.outward(which, cell0) }
                        } else if !oa || !ob {
                            // PG1 ("not smoothed block cells"): a side the generator's field doesn't describe (built over,
                            // dug before field edits were kept, a surface rule's bank or pond, a block being chipped) is
                            // half a block past the surface, and the field side is bounded to match, so the surface sits
                            // where the cells meet instead of relaxing round block steps. A chipped block's side shrinks
                            // with each blow.
                            var da: Float = oa ? min(F.distance(a), 0.5) : 0.35
                            let db: Float = ob ? max(F.distance(b), -0.5) : -0.35
                            if !oa, !dmg.isEmpty {
                                let bx = a % N - SO, bz = (a / N) % N - SO, by = a / NN - SO
                                if let dv = dmg[ri(bx, by, bz)] { da = 0.35 * (1 - 0.9 * Float(min(7, Int(dv & 31)) + 1) / 8) }
                            }
                            let ca = max(0.02, da), cb = min(-0.02, db)
                            let tt = ca / (ca - cb)
                            t = s1 ? tt : 1 - tt
                        } else {
                            t = 0.5; loose = true
                        }
                    } else if stored != nil {
                        let i1 = cell0 + (c & 1) + (c >> 2) * N + ((c >> 1) & 1) * NN
                        let i2 = cell0 + (c2 & 1) + (c2 >> 2) * N + ((c2 >> 1) & 1) * NN
                        let s1 = (mask >> c) & 1 == 1
                        var da = effX(sToR(s1 ? i1 : i2)), db = effX(sToR(s1 ? i2 : i1))
                        if !dmg.isEmpty, let dv = dmg[sToR(s1 ? i1 : i2)] { da *= 1 - 0.9 * Float(min(7, Int(dv & 31)) + 1) / 8 }
                        da = max(0.02, da); db = min(-0.02, db)
                        let tt = da / (da - db)
                        t = s1 ? tt : 1 - tt
                    } else {
                        let d1 = D[(cx + DO + (c & 1)) + (cz + DO + (c >> 2)) * M + (cy + DO + ((c >> 1) & 1)) * MM]
                        let d2 = D[(cx + DO + (c2 & 1)) + (cz + DO + (c2 >> 2)) * M + (cy + DO + ((c2 >> 1) & 1)) * MM]
                        t = max(0, min(1, (d1 - 0.5) / (d1 - d2)))
                    }
                    let p1 = SIMD3<Float>(Float(c & 1), Float((c >> 1) & 1), Float(c >> 2))
                    let p2 = SIMD3<Float>(Float(c2 & 1), Float((c2 >> 1) & 1), Float(c2 >> 2))
                    sum += p1 + (p2 - p1) * t
                    n += 1
                }
            }
            var pinned = false
            for c in 0..<8 where !leaves && pinT[Int(R[ri(cx + (c & 1), cy + ((c >> 1) & 1), cz + (c >> 2))])] { pinned = true; break }
            let p = pinned ? SIMD3<Float>(Float(cx + 1), Float(cy + 1), Float(cz + 1))
                : sum / n + SIMD3<Float>(Float(cx) + 0.5, Float(cy) + 0.5, Float(cz) + 0.5)
            VP[vi * 3] = p.x; VP[vi * 3 + 1] = p.y; VP[vi * 3 + 2] = p.z
            // 0 relaxes (round 2, and P142 vertices with an off-field edge), 1 pinned to a built block, 2 on the field (fixed).
            VQ[vi] = pinned ? 1 : (fieldLike && !loose ? 2 : 0)
            if loose { anyLoose = true }
            // The ring only feeds the relaxation: its normals and light are never drawn.
            if cx < 0 || cy < 0 || cz < 0 || cx > 16 || cy > 16 || cz > 16 { VL[vi] = 0; continue }
            // Normal: minus the gradient of solidity over the 4x4x4 blocks around the vertex (S index = block + 3).
            // P142: on the field, the field's own outward direction instead.
            let fieldN = field != nil && !loose && fnSeen != 0
            var g = fieldN ? -fn : SIMD3<Float>(0, 0, 0)
            var occF: Float = 0
            if stored != nil {
                // PG1: the field's gradient over the 4x4x4 cells round the vertex, and how much of them is ground
                // (ground +1, open -1, softened within half a block of the surface: smooth along a wall, where counting
                // the cells' block steps put a dark dot at every other vertex of a sloping cave wall).
                for j in 0..<4 { for k in 0..<4 { for i in 0..<4 {
                    let sv = eff(ri(cx - 1 + i, cy - 1 + j, cz - 1 + k))
                    g.x += sv * dW[i] * tW[j] * tW[k]
                    g.y += sv * tW[i] * dW[j] * tW[k]
                    g.z += sv * tW[i] * tW[j] * dW[k]
                    occF += max(-1, min(1, sv * 2))
                } } }
            } else if !fieldN { for j in 0..<4 { for k in 0..<4 { for i in 0..<4 {
                let sv = Float(S[(cx + SO - 1 + i) + (cz + SO - 1 + k) * N + (cy + SO - 1 + j) * NN])
                if sv == 0 { continue }
                g.x += sv * dW[i] * tW[j] * tW[k]
                g.y += sv * tW[i] * dW[j] * tW[k]
                g.z += sv * tW[i] * tW[j] * dW[k]
            } } } }
            VN[vi * 3] = -g.x; VN[vi * 3 + 1] = -g.y; VN[vi * 3 + 2] = -g.z
            // Light: mean over the open corners; ao from how many corners occlude.
            var sky = 0, blk = 0, open = 0, occ = 0
            for c in 0..<8 {
                let i = ri(cx + (c & 1), cy + ((c >> 1) & 1), cz + (c >> 2))
                let b = Int(R[i])
                if aoT[b] { occ += 1 }
                if loT[b] { continue }
                sky += Int(skyL[i]); blk += Int(blkL[i]); open += 1
            }
            let l = open == 0 ? 0 : ((sky + open / 2) / open) | (((blk + open / 2) / open) << 4)
            var ao = max(0, 3 - max(0, occ - 4))
            // P142: on smooth land the 8 blocks round a vertex are the block steps the field was rounded to, and their ao
            // drew a dark contour line at every step of a hillside (the terraced look). Occlusion from the 4x4x4 blocks
            // round the vertex instead: about half solid on any even slope, more in a hollow or under an overhang.
            if fieldLike {
                var cnt = 0
                for j in 0..<4 { for k in 0..<4 { for i in 0..<4 {
                    cnt += Int(S[(cx + SO - 1 + i) + (cz + SO - 1 + k) * N + (cy + SO - 1 + j) * NN])
                } } }
                ao = 3 - min(3, max(0, (cnt - 42) / 5))
                if stored != nil { ao = 3 - min(3, max(0, Int(floor((occF - 20) / 10)))) }   // (the same scale: cnt = (occF + 64) / 2)
                // The vertex's own material (P142 blending: the shader blends a quad's corners): snow under a snow layer and
                // turf where the ground faces up, else the commonest ground among its 8 blocks; -1 keeps the quad's own.
                let up = -g.y / max(1e-6, simd_length(g))
                var m = -1, mn = 0, turf = -1, snow = false
                for c in 0..<8 {
                    let b = Int(R[ri(cx + (c & 1), cy + ((c >> 1) & 1), cz + (c >> 2))])
                    if b == snowL { snow = true; continue }
                    guard blendT[b] else { continue }
                    if tintT[b] == 3 { turf = b }
                    if b == m { mn += 1; continue }
                    var n = 0
                    for c2 in 0..<8 where Int(R[ri(cx + (c2 & 1), cy + ((c2 >> 1) & 1), cz + (c2 >> 2))]) == b { n += 1 }
                    if n > mn { m = b; mn = n }
                }
                // PG1 field worlds: the material where the drawn surface really is, the ground just under the vertex (half a
                // block in along the gradient), moved by world-stable noise up to ~0.8 block: a border between two grounds
                // follows the smooth surface and wanders like real ground instead of tracing the cells' block steps.
                var sampled = false
                if let E = stored, let w = world {
                    let gl = simd_length(g)
                    if gl > 1e-5 {
                        let pv = SIMD3<Float>(VP[vi * 3], VP[vi * 3 + 1], VP[vi * 3 + 2])
                        let wp = pv + SIMD3<Float>(Float(w.x), Float(w.y), Float(w.z))
                        let j = SIMD3<Float>(DetailMesh.noise(wp, 0.23, 0xB1E1), DetailMesh.noise(wp, 0.23, 0xB1E2),
                                             DetailMesh.noise(wp, 0.23, 0xB1E3)) * 0.8
                        let q = pv + g / gl * 0.5 + j
                        let r = ri(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z)))
                        let b = Int(R[r])
                        if E[r] > 0 && blendT[b] { m = b; sampled = true }
                    }
                }
                if snow && up > 0.3 { m = snowB }
                else if turf >= 0 && up > 0.35 && (!sampled || m == Int(DIRT) || tintT[m] == 3) { m = turf }
                VM[vi] = Int32(m)
            }
            VL[vi] = Int32(l | ao << 8)
        } } }
        // P106 ("you can still tell it used to be blocks"): relax the surface. Each free vertex moves `relaxRate` of the
        // way to the mean of its surface neighbours, `relax` times, kept inside its own dual cell (so no quad folds over). Steps and
        // ledges become slopes and rounded shelves; flat ground and pinned joins to built blocks don't move.
        // P142: on field land only off-field vertices (edits, structure ground) relax, one gentle pass: more pulled a dug pit's
        // floor up to the ground round it and flattened a placed block into a sliver.
        let passes = field != nil ? min(1, SmoothTerrain.relax) : SmoothTerrain.relax
        let rate: Float = field != nil ? 0.4 : SmoothTerrain.relaxRate
        if passes > 0 && anyLoose {
            let VR = sc.smR
            let nbo = [1, -1, K, -K, KK, -KK]
            for it in 0..<min(KO, passes) {
                let lo = KO - min(KO, passes) + it + 1, hi = K - 1 - lo   // ring by ring, inward
                for ky in lo...hi { for kz in lo...hi { for kx in lo...hi {
                    let vi = kx + kz * K + ky * KK
                    VR[vi * 3] = VP[vi * 3]; VR[vi * 3 + 1] = VP[vi * 3 + 1]; VR[vi * 3 + 2] = VP[vi * 3 + 2]
                    guard VL[vi] >= 0, VQ[vi] == 0 else { continue }
                    var m = SIMD3<Float>(0, 0, 0), c: Float = 0
                    for o in nbo where VL[vi + o] >= 0 {
                        m += SIMD3<Float>(VP[(vi + o) * 3], VP[(vi + o) * 3 + 1], VP[(vi + o) * 3 + 2]); c += 1
                    }
                    guard c > 0 else { continue }
                    let cur = SIMD3<Float>(VP[vi * 3], VP[vi * 3 + 1], VP[vi * 3 + 2])
                    let lo3 = SIMD3<Float>(Float(kx - KO) + 0.5, Float(ky - KO) + 0.5, Float(kz - KO) + 0.5)
                    let r = simd_clamp(cur + (m / c - cur) * rate, lo3 + 0.02, lo3 + 0.98)
                    VR[vi * 3] = r.x; VR[vi * 3 + 1] = r.y; VR[vi * 3 + 2] = r.z
                } } }
                for ky in lo...hi { for kz in lo...hi { for kx in lo...hi {
                    let vi = kx + kz * K + ky * KK
                    VP[vi * 3] = VR[vi * 3]; VP[vi * 3 + 1] = VR[vi * 3 + 1]; VP[vi * 3 + 2] = VR[vi * 3 + 2]
                } } }
            }
        }

        // Chips off a block being dug pull the corners round it in toward its centre, after relaxing (so the dent shows).
        if !dmg.isEmpty {
            for ky in KO...(KO + 16) { for kz in KO...(KO + 16) { for kx in KO...(KO + 16) {
                let vi = kx + kz * K + ky * KK
                guard VL[vi] >= 0, VQ[vi] == 0 || stored != nil && VQ[vi] == 2 else { continue }
                let cx = kx - KO, cy = ky - KO, cz = kz - KO
                var p = SIMD3<Float>(VP[vi * 3], VP[vi * 3 + 1], VP[vi * 3 + 2])
                var open = SIMD3<Float>(0, 0, 0), no: Float = 0
                for c in 0..<8 where S[(cx + SO + (c & 1)) + (cz + SO + (c >> 2)) * N + (cy + SO + ((c >> 1) & 1)) * NN] == 0 {
                    open += SIMD3<Float>(Float(c & 1), Float((c >> 1) & 1), Float(c >> 2)); no += 1
                }
                for c in 0..<8 where S[(cx + SO + (c & 1)) + (cz + SO + (c >> 2)) * N + (cy + SO + ((c >> 1) & 1)) * NN] != 0 {
                    let bx = cx + (c & 1), by = cy + ((c >> 1) & 1), bz = cz + (c >> 2)
                    guard let dv = dmg[ri(bx, by, bz)] else { continue }
                    let lv = Float(min(7, Int(dv & 31)) + 1) / 8
                    // Toward a point a quarter block past the block's centre, away from the open side.
                    let away = SIMD3<Float>(Float(c & 1), Float((c >> 1) & 1), Float(c >> 2)) - open / max(1, no)
                    let into = simd_length(away) > 1e-4 ? simd_normalize(away) * 0.25 : SIMD3<Float>(0, 0, 0)
                    p += (SIMD3<Float>(Float(bx) + 0.5, Float(by) + 0.5, Float(bz) + 0.5) + into - p) * (0.7 * lv)
                }
                VP[vi * 3] = p.x; VP[vi * 3 + 1] = p.y; VP[vi * 3 + 2] = p.z
            } } }
        }

        // Realistic world: leaf masses, not boxes. Every leaf surface vertex moves along its normal by world-stable noise
        // (two octaves, up to ~0.4 block), so a canopy's outline bulges and dips into clumps; the same vertex moves the same
        // way in every section that meshes it.
        if leaves, let w = world {
            let wo = SIMD3<Float>(Float(w.x), Float(w.y), Float(w.z))
            for ky in KO...(KO + 16) { for kz in KO...(KO + 16) { for kx in KO...(KO + 16) {
                let vi = kx + kz * K + ky * KK
                guard VL[vi] >= 0 else { continue }
                let p = SIMD3<Float>(VP[vi * 3], VP[vi * 3 + 1], VP[vi * 3 + 2])
                var n = SIMD3<Float>(VN[vi * 3], VN[vi * 3 + 1], VN[vi * 3 + 2])
                let l = simd_length(n)
                guard l > 1e-5 else { continue }
                n /= l
                let wp = p + wo
                let d = 0.3 * DetailMesh.noise(wp, 0.38, 0x1EAF) + 0.14 * DetailMesh.noise(wp, 1.1, 0x1EB0) + 0.05
                let q = simd_clamp(p + n * d, SIMD3<Float>(repeating: 0.05), SIMD3<Float>(repeating: 31.9))
                VP[vi * 3] = q.x; VP[vi * 3 + 1] = q.y; VP[vi * 3 + 2] = q.z
            } } }
        }

        if let hook = SmoothTerrain.vertexHook {             // (tests: the same cell meshed by two sections)
            for ky in KO...(KO + 16) { for kz in KO...(KO + 16) { for kx in KO...(KO + 16) {
                let vi = kx + kz * K + ky * KK
                if VL[vi] >= 0 { hook(kx - KO, ky - KO, kz - KO, SIMD3<Float>(VP[vi * 3], VP[vi * 3 + 1], VP[vi * 3 + 2])) }
            } } }
        }
        // P404: `pin` moves an owned dual vertex (section-local cell, its position) onto another mesh's vertex where the
        // two must meet (Mesher.fineGround: the half-block ground's outer edge onto the cells-drawn neighbour's vertices).
        if let pin {
            for ky in KO...(KO + 16) { for kz in KO...(KO + 16) { for kx in KO...(KO + 16) {
                let vi = kx + kz * K + ky * KK
                guard VL[vi] >= 0, let q = pin(kx - KO, ky - KO, kz - KO, SIMD3<Float>(VP[vi * 3], VP[vi * 3 + 1], VP[vi * 3 + 2])) else { continue }
                VP[vi * 3] = q.x; VP[vi * 3 + 1] = q.y; VP[vi * 3 + 2] = q.z
            } } }
        }
        if !leaves { sc.smValid = true }
        // Quads: block p and its +axis neighbour q, one solid (natural) and one open.
        var corner = [Int](repeating: 0, count: 4)
        var pts = [SIMD3<Float>](repeating: .zero, count: 4)
        for y in 0...16 { for z in 0...16 { for x in 0...16 {
            let p = SIMD3<Int>(x, y, z)
            for a in 0..<3 {
                let b = (a + 1) % 3, c = (a + 2) % 3
                if p[a] > 15 || p[b] < 1 || p[c] < 1 { continue }
                var q = p
                q[a] += 1
                let sp = S[(p[0] + SO) + (p[2] + SO) * N + (p[1] + SO) * NN] != 0
                let sq = S[(q[0] + SO) + (q[2] + SO) * N + (q[1] + SO) * NN] != 0
                if sp == sq { continue }
                let s = sp ? p : q
                let si = ri(s[0], s[1], s[2])
                let blockID = Int(R[si])
                if !nat[blockID] { continue }
                if !leaves, let E = stored, E[si] <= 0 { continue }       // (field worlds: a built block of rock: a cube)
                // Dual cells around the edge, counter-clockwise seen from the open side.
                for k in 0..<4 {
                    var d = p
                    let kk = sp ? k : 3 - k
                    d[b] -= (kk == 0 || kk == 3) ? 1 : 0
                    d[c] -= (kk == 0 || kk == 1) ? 1 : 0
                    let vi = (d[0] + KO) + (d[2] + KO) * K + (d[1] + KO) * KK
                    corner[k] = vi
                    pts[k] = SIMD3<Float>(VP[vi * 3], VP[vi * 3 + 1], VP[vi * 3 + 2])
                }
                let nrm = simd_cross(pts[2] - pts[0], pts[3] - pts[1])
                let ax = abs(nrm.x), ay = abs(nrm.y), az = abs(nrm.z)
                let len = simd_length(nrm)
                if pin != nil && len < 1e-8 { continue }        // (P404: a quad whose corners were pinned together)
                let f: Int
                if nrm.y > 0.5 * len { f = 2 }                 // up to 60 degrees: the top texture (grass on slopes)
                else if ay >= ax && ay >= az { f = nrm.y > 0 ? 2 : 3 }
                else if ax >= az { f = nrm.x > 0 ? 0 : 1 }
                else { f = nrm.z > 0 ? 4 : 5 }
                // Grass (side overlay blocks): grass wherever the ground faces up at all, dirt under overhangs; the side
                // texture's fringe would draw a band at every block row on a slope.
                // P141/P142: dirt facing up under a neighbour's turf shows the turf (on a hillside every block row exposes the
                // dirt under the row above's grass, which striped slopes grass/dirt/grass: the checkered look).
                var id = blockID
                if id == Int(DIRT) && nrm.y > 0.35 * len {
                    turf: for (dx, dy, dz) in SmoothTerrain.turfProbe {
                        let t = Int(R[ri(s[0] + dx, s[1] + dy, s[2] + dz)])
                        if nat[t] && tintT[t] == 3 { id = t; break turf }
                    }
                }
                // P142 material blending, first step: the rock a generator mixes block by block (deeprock with stone above 0,
                // emberslate with blackstone, basalt and magma below) shows as the commonest rock round the block, so a smooth
                // wall reads as patches and strata instead of a grid of single blocks. Ores and everything else keep their own look.
                if fieldLike && rockSlot[id] >= 0 {
                    var counts = SIMD16<Int32>(repeating: 0)
                    for (dx, dy, dz) in SmoothTerrain.voteProbe {
                        let k = Int(rockSlot[Int(R[ri(s[0] + dx, s[1] + dy, s[2] + dz)])])
                        if k >= 0 { counts[k] += 1 }
                    }
                    var bestK = Int(rockSlot[id])
                    for k in 0..<SmoothTerrain.rockIDs.count where counts[k] > counts[bestK] { bestK = k }
                    id = SmoothTerrain.rockIDs[bestK]
                }
                let tintB = Int(tintT[id])
                let texF = tintB == 3 ? (nrm.y > 0.2 * len ? 2 : 3) : f
                let layer = Int(texT[id * 6 + texF])
                let tint = tintB == 3 ? (texF == 2 ? 1 : 0) : tintB
                let blendQuad = fieldLike && blendT[id]
                let a0 = Int(VL[corner[0]]) >> 8, a1 = Int(VL[corner[1]]) >> 8
                let a2 = Int(VL[corner[2]]) >> 8, a3 = Int(VL[corner[3]]) >> 8
                let flip = a0 + a2 < a1 + a3
                // Realistic world: a quad a blow struck is subdivided and carved into a crater (Craters.swift), drawn from
                // the detail stream instead.
                if !leaves, let cr = crater, let co = carveOut, cr.touches(pts) {
                    var cp = pts, cn = pts, cl = [0, 0, 0, 0], ct = cl, cv = cl, ca = cl
                    for k in 0..<4 {
                        let cc = flip ? (k + 1) & 3 : k
                        let vi = corner[cc]
                        var vn = SIMD3<Float>(VN[vi * 3], VN[vi * 3 + 1], VN[vi * 3 + 2])
                        vn = simd_length_squared(vn) > 1e-6 ? simd_normalize(vn) : nrm / max(len, 1e-6)
                        var lay = layer, tnt = tint
                        if blendQuad, case let m = Int(VM[vi]), m >= 0 {
                            let tb = Int(tintT[m]), tf = tb == 3 ? (vn.y > 0.2 ? 2 : 3) : f
                            lay = Int(texT[m * 6 + tf]); tnt = tb == 3 ? (tf == 2 ? 1 : 0) : tb
                        }
                        let v = Int(VL[vi])
                        // (On the section vertices' 1/16 grid, so the carved quad meets its uncarved neighbours exactly.)
                        cp[k] = (pts[cc] * 16).rounded(.toNearestOrAwayFromZero) / 16; cn[k] = vn; cl[k] = lay; ct[k] = tnt; cv[k] = v & 255; ca[k] = v >> 8
                    }
                    let tb = Int(tintT[blockID])
                    cr.carve(co, cp, cn, layers: cl, tints: ct, light: cv, ao: ca,
                             inner: (layer: Int(texT[blockID * 6 + 3]), tint: tb == 3 ? 0 : tb), face: f, grid: cr.ticks(cp, base: 4))
                    continue
                }
                // P375: up-facing ground goes to the pixel-error merge (GroundMerge), which emits it afterwards.
                let toMerge = !leaves && a == 1 && sp && f == 2 && merge != nil
                var mq = toMerge ? GroundMerge.Quad(v: [SIMD8<Int32>](repeating: .zero, count: 4), flip: flip) : nil
                // P383: field ground drawn per position (SmoothTerrain.triGround).
                let tri = triOn && !toMerge
                for k in 0..<4 {
                    let cc = flip ? (k + 1) & 3 : k
                    let v = Int(VL[corner[cc]])
                    let pt = pts[cc] * 16
                    let vi = corner[cc]
                    var vn = SIMD3<Float>(VN[vi * 3], VN[vi * 3 + 1], VN[vi * 3 + 2])
                    vn = simd_length_squared(vn) > 1e-6 ? simd_normalize(vn) : nrm / max(len, 1e-6)
                    var lay = layer, tnt = tint
                    if blendQuad, case let m = Int(VM[vi]), m >= 0 {
                        let tb = Int(tintT[m]), tf = tb == 3 ? (vn.y > 0.2 ? 2 : 3) : (tri ? SmoothTerrain.triFace(vn) : f)
                        lay = Int(texT[m * 6 + tf]); tnt = tb == 3 ? (tf == 2 ? 1 : 0) : tb
                    }
                    if tri {
                        // (f 8...15 tells the emitter: a per-position vertex, code = (f - 8) << 6 | ncode)
                        let code = SmoothTerrain.triCode(vn)
                        if let ex = exact { ex.append(pts[cc].x); ex.append(pts[cc].y); ex.append(pts[cc].z) }
                        emit(Int(pt.x.rounded()), Int(pt.y.rounded()), Int(pt.z.rounded()), 8 + (code >> 6), tnt, lay, v >> 8, v & 255, code & 63)
                        continue
                    }
                    if mq != nil {
                        mq!.v[cc] = SIMD8<Int32>(Int32(pt.x.rounded()), Int32(pt.y.rounded()), Int32(pt.z.rounded()), Int32(tnt), Int32(lay),
                                                 Int32(v >> 8), Int32(v & 255), Int32(SmoothTerrain.normalCode(vn, face: f)))
                        continue
                    }
                    if let ex = exact { ex.append(pts[cc].x); ex.append(pts[cc].y); ex.append(pts[cc].z) }
                    emit(Int(pt.x.rounded()), Int(pt.y.rounded()), Int(pt.z.rounded()), f, tnt, lay, v >> 8, v & 255,
                         SmoothTerrain.normalCode(vn, face: f))
                }
                if let mq { merge!.add(x: p[0], z: p[2], mq); continue }
                if leaves && shells > 1 {
                    for k in 0..<4 {
                        let cc = flip ? (k + 1) & 3 : k
                        let v = Int(VL[corner[cc]])
                        let vi = corner[cc]
                        var vn = SIMD3<Float>(VN[vi * 3], VN[vi * 3 + 1], VN[vi * 3 + 2])
                        vn = simd_length_squared(vn) > 1e-6 ? simd_normalize(vn) : nrm / max(len, 1e-6)
                        let pt = simd_clamp((pts[cc] - vn * 0.45) * 16, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 511))
                        emit(Int(pt.x.rounded()), Int(pt.y.rounded()), Int(pt.z.rounded()), f, tint, layer, max(0, (v >> 8) - 2), v & 255,
                             SmoothTerrain.normalCode(vn, face: f))
                    }
                }
            }
        } } }
    }
}
