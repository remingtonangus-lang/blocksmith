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
    static func use(world on: Bool, world w: World?) { set(forced ?? on, world: w) }

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

    // Smooth quads for the section whose local 0 is region (C0, C0, C0). `emit` takes position (1/16 block,
    // section-local), face, tint, layer, ao, packed light, overlay.
    // `site` (P142): the section's chunk in a world whose generator has fields; nil meshes round the blocks (round 2).
    // `leaves` (T17): mesh the leaf blocks instead, as rounded blobs (round-2 rounding, no pins), each quad twice: the
    // outer shell and a darker one 0.45 block inside it, so the leaf texture's holes show leaves behind, not the sky.
    // `leafHoles`: the ground pass treats leaves as open (their blobs mesh apart and the ground under a bush shows).
    static func smoothQuads(_ R: UnsafeMutablePointer<BlockID>, _ sc: MeshScratch, dmg: [Int: UInt8], site: SmoothSite? = nil, sy: Int = 0,
                            leaves: Bool = false, leafHoles: Bool = false, detailHoles: Bool = false, world: SIMD3<Int>? = nil,
                            crater: CraterSet? = nil, carveOut: GrowBuf<UInt32>? = nil,
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
        var anyLoose = field == nil

        // Density for blocks -KO...KO+17 (index +KO): half the block, half its 3x3x3 mean. A chipped natural
        // block (being dug, P106) keeps its smooth surface but shrinks toward its centre as the chips come off (its
        // solid density falls toward the 0.5 threshold), instead of turning back into a cube of sub-cubes.
        let M = 18 + 2 * KO, MM = M * M, DO = KO
        let D = sc.smD
        if field == nil { for y in 0..<M { for z in 0..<M { for x in 0..<M {
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
            VQ[vi] = pinned ? 1 : (field != nil && !loose ? 2 : 0)
            if loose { anyLoose = true }
            // The ring only feeds the relaxation: its normals and light are never drawn.
            if cx < 0 || cy < 0 || cz < 0 || cx > 16 || cy > 16 || cz > 16 { VL[vi] = 0; continue }
            // Normal: minus the gradient of solidity over the 4x4x4 blocks around the vertex (S index = block + 3).
            // P142: on the field, the field's own outward direction instead.
            let fieldN = field != nil && !loose && fnSeen != 0
            var g = fieldN ? -fn : SIMD3<Float>(0, 0, 0)
            if !fieldN { for j in 0..<4 { for k in 0..<4 { for i in 0..<4 {
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
            if field != nil {
                var cnt = 0
                for j in 0..<4 { for k in 0..<4 { for i in 0..<4 {
                    cnt += Int(S[(cx + SO - 1 + i) + (cz + SO - 1 + k) * N + (cy + SO - 1 + j) * NN])
                } } }
                ao = 3 - min(3, max(0, (cnt - 42) / 5))
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
                if snow && up > 0.3 { m = snowB } else if turf >= 0 && up > 0.35 { m = turf }
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
                guard VL[vi] >= 0, VQ[vi] == 0 else { continue }
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
                if field != nil && rockSlot[id] >= 0 {
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
                let blendQuad = field != nil && blendT[id]
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
                for k in 0..<4 {
                    let cc = flip ? (k + 1) & 3 : k
                    let v = Int(VL[corner[cc]])
                    let pt = pts[cc] * 16
                    let vi = corner[cc]
                    var vn = SIMD3<Float>(VN[vi * 3], VN[vi * 3 + 1], VN[vi * 3 + 2])
                    vn = simd_length_squared(vn) > 1e-6 ? simd_normalize(vn) : nrm / max(len, 1e-6)
                    var lay = layer, tnt = tint
                    if blendQuad, case let m = Int(VM[vi]), m >= 0 {
                        let tb = Int(tintT[m]), tf = tb == 3 ? (vn.y > 0.2 ? 2 : 3) : f
                        lay = Int(texT[m * 6 + tf]); tnt = tb == 3 ? (tf == 2 ? 1 : 0) : tb
                    }
                    emit(Int(pt.x.rounded()), Int(pt.y.rounded()), Int(pt.z.rounded()), f, tnt, lay, v >> 8, v & 255,
                         SmoothTerrain.normalCode(vn, face: f))
                }
                if leaves {
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
