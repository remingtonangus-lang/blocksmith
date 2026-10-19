import Foundation
import simd

struct SectionMesh {
    var opaque: [UInt32]
    var trans: [UInt32]
    var light: [UInt8]?     // 4096 values (sky << 4 | block) for the section, nil if not computed
    var vis: UInt64 = ~0    // face-to-face connectivity through open cells (bit a*6+b), for cave culling
    var solidQuads = 0      // opaque = solid quads first (no alpha test: keeps the GPU's hidden-surface removal), then cutout
    var leafy = true        // has faces between leaf blocks (false: lod 0 and 2 mesh the same, no remesh across that ring)
    // Realistic world (DetailMesh): round shapes in 16-byte vertices, solid quads first, then alpha-tested ones.
    var detail: [UInt32] = []
    var detailSolid = 0
    var groundQuads = 0     // P283: of the opaque quads, the smooth ground's and the leaf blobs' (questcheck --perfscenes)
    var blobQuads = 0
    var naturalCubes = 0    // P338 step 2: natural ground drawn as cubes in a field world (must be 0)
    // P375 (GroundMerge): far from the eye the first `farSkip` opaque quads are left out and `farGround` drawn instead.
    var farSkip = 0
    var farGround: [UInt32] = []
}

// Builds one 16x16x16 section. The 3x3 chunk neighbourhood (n9, index cx+cz*3, centre 4) and its
// heightmaps (h9) are gathered into a 48x48x48 region around the section: light travels at most 15
// blocks, so every source that can reach the section (or the 1-block border faces sample) is inside,
// and skylight above the heightmap is known directly. Nothing about light is stored between meshes
// except the section's own result (used for mob spawning).
//
// Vertex = 2 x UInt32 (positions/uv in 1/16 block):
//   w0: x(9) y(9)<<9 z(9)<<18 shade(3)<<27 tint(2)<<30        tint: 0 none, 1 grass, 2 foliage, 3 water
//   w1: u(5) v(5)<<5 layer(10)<<10 ao(2)<<20 sky(4)<<22 block(4)<<26 overlay(1)<<30   (cross plants: overlay = sways, ao = its phase)
// 4 verts per quad (corners 0..3 CCW seen from outside), drawn with a shared index buffer.
enum Mesher {
    // P239: ice block states (their top faces carry the overlay bit, which the Quest's water.frag mirrors the sky on).
    static let iceTable: [Bool] = (0..<Blocks.opaque.count).map { i in
        let k = Blocks.key(Blocks.groupBase[i])
        return k == "ice" || k.hasPrefix("frosted_ice")
    }
    // Water top faces carry the water depth in their AO bits (Quest only: its water shader reads it; the Mac's water
    // shaders shade water by AO-free rules and the Fancy path measures depth from the scene).
    #if os(macOS)
    static var waterDepthAO = false
    #else
    static var waterDepthAO = true
    #endif
    // Cross plants that bend in the wind (Blocks.sway) carry the overlay bit (crosses have no overlay otherwise); the
    // Quest chunk and ship shaders move their top corners (the Mac's shaders don't read it, so it stays off there).
    #if os(macOS)
    static var plantSway = false
    #else
    static var plantSway = true
    #endif
    // Realistic world (docs/design/realistic-world.md): in polygon worlds trunks, limbs and organic objects are drawn as
    // round shapes in the section's detail stream (DetailMesh) instead of cubes. Quest only: the Mac's renderer has no
    // detail pipeline, so its sections keep the cubes. BLOCKSMITH_DETAIL=0 keeps the cubes (side by side shots).
    #if os(macOS)
    static var detailMeshes = false
    #else
    static var detailMeshes = ProcessInfo.processInfo.environment["BLOCKSMITH_DETAIL"] != "0"
    #endif
    // Blocks drawn by the detail generators: the ground and the cube faces round them treat them as open.
    static let detailT: [Bool] = (0..<Blocks.count).map { i in
        ShapeClass.kind[i] == .trunk || ShapeClass.kind[i] == .organic || i != 0 && i == Int(pointedDrip)    // (P338: ShapeSpikes)
            || ShapeRails.isRail[i]                                                                           // (P337: ShapeRails)
    }
    // Built cubes (planks, bricks, metal, concrete...): crisp, but no knife edges (realistic world 1.6).
    static let bevelT: [Bool] = (0..<Blocks.count).map { ShapeClass.kind[$0] == .built && Blocks.tint[$0] != 3 }

    // Shared light arrays for uniform sections (most of a chunk's sections are fully dark or fully sky-lit).
    static let dark = [UInt8](repeating: 0, count: 4096)
    static let fullSky = [UInt8](repeating: 0xF0, count: 4096)

    static let RW = 48
    static let RH = 48
    static let RL = RW * RW
    static let C0 = 16          // region coordinate of the section's local 0 (x, y and z)
    // P297 (b): the cells two out from a shore cell (Mesher shoreWater), nearest first.
    static let shoreRing2: [(Int, Int)] = [(2, 0), (-2, 0), (0, 2), (0, -2), (2, 1), (2, -1), (-2, 1), (-2, -1),
                                            (1, 2), (-1, 2), (1, -2), (-1, -2), (2, 2), (2, -2), (-2, 2), (-2, -2)]

    // Faces +X,-X,+Y,-Y,+Z,-Z; corners BL,BR,TR,TL counter-clockwise seen from outside.
    static let cornerTable: [Int] = [
        1,0,1, 1,0,0, 1,1,0, 1,1,1,
        0,0,0, 0,0,1, 0,1,1, 0,1,0,
        0,1,1, 1,1,1, 1,1,0, 0,1,0,
        0,0,0, 1,0,0, 1,0,1, 0,0,1,
        0,0,1, 1,0,1, 1,1,1, 0,1,1,
        1,0,0, 0,0,0, 0,1,0, 1,1,0,
    ]
    static let normalTable: [Int] = [1,0,0, -1,0,0, 0,1,0, 0,-1,0, 0,0,1, 0,0,-1]
    static let plantTable: [Int] = [
        0,0,0, 1,0,1, 1,1,1, 0,1,0,
        1,0,1, 0,0,0, 0,1,0, 1,1,1,
        1,0,0, 0,0,1, 0,1,1, 1,1,0,
        0,0,1, 1,0,0, 1,1,0, 0,1,1,
    ]
    static let cornerU: [Int] = [0, 16, 16, 0]
    static let cornerV: [Int] = [16, 16, 0, 0]

    // Texture coordinates for a point (1/16 units inside the block) on face f.
    // Progressive block damage: which of a block's 64 sub-cubes (bit a | b << 2 | c << 4 for x a, z b, y c) are
    // still there at damage `level` (1...7 of 8) chipped in from `face` (0 +x, 1 -x, 2 +y, 3 -y, 4 +z, 5 -z). Sub-cubes
    // nearest that face go first, in a ragged order that differs per block (4 variants by position).
    static let chipTable: [UInt64] = {
        var t = [UInt64](repeating: ~0, count: 6 * 8 * 4)
        for f in 0..<6 { for variant in 0..<4 {
            var order: [(Float, Int)] = []
            for c in 0..<64 {
                let a = c & 3, b = (c >> 2) & 3, y = c >> 4
                let depth: Int
                switch f {
                case 0: depth = 3 - a
                case 1: depth = a
                case 2: depth = 3 - y
                case 3: depth = y
                case 4: depth = 3 - b
                default: depth = b
                }
                // Ragged: noise across the face, and edge sub-cubes a little earlier (corners crumble first).
                let edge: Float = (a == 0 || a == 3 ? 0.35 : 0) + (b == 0 || b == 3 ? 0.35 : 0) + (y == 0 || y == 3 ? 0.35 : 0)
                let n: Float = hashf(c, f, variant, 0xC41B) * 1.6
                order.append((Float(depth) + n - edge, c))
            }
            order.sort { $0.0 < $1.0 }
            for level in 1..<8 {
                var m: UInt64 = ~0
                for k in 0..<(level * 8) { m &= ~(UInt64(1) << UInt64(order[k].1)) }
                t[(f * 8 + level) * 4 + variant] = m
            }
        } }
        return t
    }()
    // Whole 4x4 layers a chip mask has cleared from its face (0...3): what collision can safely give up.
    static let chipLayers: [UInt8] = {
        var t = [UInt8](repeating: 0, count: 6 * 8 * 4)
        for f in 0..<6 { for lv in 0..<8 { for v in 0..<4 {
            let m = chipTable[(f * 8 + lv) * 4 + v]
            var k = 0
            while k < 3 {
                var clear = true
                for c in 0..<64 {
                    let a = c & 3, b = (c >> 2) & 3, y = c >> 4
                    let depth = [3 - a, a, 3 - y, y, 3 - b, b][f]
                    if depth == k && m & (UInt64(1) << UInt64(c)) != 0 { clear = false; break }
                }
                if !clear { break }
                k += 1
            }
            t[(f * 8 + lv) * 4 + v] = UInt8(k)
        } } }
        return t
    }()
    // The collision box left of a chipped full block at world cell x, y, z (unit cube, cleared layers cut from the
    // struck face). The variant hash takes the same section-local coordinates the mesher passes to chipMask.
    static func chipBox(face: Int, level: Int, x: Int, y: Int, z: Int) -> (V3, V3) {
        let f = max(0, min(5, face)), lv = max(0, min(7, level))
        let v = Int(hash3((x & 15) + 16, (y & 15) + 16, (z & 15) + 16, 0xD4A6) & 3)
        let k = Float(chipLayers[(f * 8 + lv) * 4 + v]) / 4
        var mn = V3(0, 0, 0), mx = V3(1, 1, 1)
        switch f {
        case 0: mx.x = 1 - k
        case 1: mn.x = k
        case 2: mx.y = 1 - k
        case 3: mn.y = k
        case 4: mx.z = 1 - k
        default: mn.z = k
        }
        return (mn, mx)
    }

    @inline(__always) static func chipMask(face: Int, level: Int, x: Int, y: Int, z: Int) -> UInt64 {
        let f = max(0, min(5, face)), lv = max(0, min(7, level))
        return chipTable[(f * 8 + lv) * 4 + Int(hash3(x, y, z, 0xD4A6) & 3)]
    }

    @inline(__always) static func faceUV(_ f: Int, _ x: Int, _ y: Int, _ z: Int) -> (Int, Int) {
        switch f {
        case 0: return (16 - z, 16 - y)
        case 1: return (z, 16 - y)
        case 2: return (x, z)
        case 3: return (x, 16 - z)
        case 4: return (x, 16 - y)
        default: return (16 - x, 16 - y)
        }
    }

    // MARK: Light

    static func flood(_ L: UnsafeMutablePointer<UInt8>, _ q: GrowBuf<Int32>, _ R: UnsafeMutablePointer<BlockID>, _ lo: [Bool]) {
        var head = 0
        while head < q.count {
            let i = Int(q.ptr[head])
            head += 1
            let l = L[i]
            if l <= 1 { continue }
            let nl = l - 1
            let y = i / RL
            let rem = i - y * RL
            let z = rem / RW
            let x = rem - z * RW
            for d in 0..<6 {
                let j: Int
                switch d {
                case 0: if x == RW - 1 { continue }; j = i + 1
                case 1: if x == 0 { continue }; j = i - 1
                case 2: if y == RH - 1 { continue }; j = i + RL
                case 3: if y == 0 { continue }; j = i - RL
                case 4: if z == RW - 1 { continue }; j = i + RW
                default: if z == 0 { continue }; j = i - RW
                }
                if lo[Int(R[j])] || L[j] >= nl { continue }
                L[j] = nl
                q.append(Int32(j))
            }
        }
    }

    // Fills sc.sky / sc.blk for the region.
    static func computeLight(_ R: UnsafeMutablePointer<BlockID>, _ heights: UnsafeMutablePointer<Int>, y0: Int, _ sc: MeshScratch, emitters: Bool = true) {
        let lo = Blocks.lightOpaque, emitT = Blocks.emit
        let sky = sc.sky, blk = sc.blk
        sky.initialize(repeating: 0, count: RL * RH)
        blk.initialize(repeating: 0, count: RL * RH)
        let q = sc.queue
        q.count = 0
        for z in 0..<RW {
            for x in 0..<RW {
                let c = x + z * RW
                let h = heights[c]
                // Direct skylight above the heightmap.
                let firstSky = max(0, h + 1 - y0)
                if firstSky < RH {
                    for ry in firstSky..<RH { sky[c + ry * RL] = 15 }
                    if h + 1 - y0 >= 0 { q.append(Int32(c + firstSky * RL)) }
                }
                // Sky cells next to taller columns spread sideways (overhangs, canopies).
                var hi = h
                if x > 0 { hi = max(hi, heights[c - 1]) }
                if x < RW - 1 { hi = max(hi, heights[c + 1]) }
                if z > 0 { hi = max(hi, heights[c - RW]) }
                if z < RW - 1 { hi = max(hi, heights[c + RW]) }
                if hi > h + 1 {
                    let a = max(firstSky + 1, 0), b = min(hi - y0, RH - 1)
                    if a <= b { for ry in a...b { q.append(Int32(c + ry * RL)) } }
                }
            }
        }
        // Only the section and its 1-block shell are read back. When every shell column's heightmap is
        // below the shell, all of it is direct skylight (15) and spreading can't change it: skip the flood.
        var shellLit = true
        check: for z in (C0 - 1)...(C0 + 16) {
            for x in (C0 - 1)...(C0 + 16) where heights[x + z * RW] >= y0 + C0 - 1 { shellLit = false; break check }
        }
        if !shellLit { flood(sky, q, R, lo) }

        q.count = 0
        if !emitters { return }                     // no light-emitting block in the region (BlockStore.emitMask)
        for i in 0..<(RL * RH) {
            let e = emitT[Int(R[i])]
            if e > 0 { blk[i] = e; q.append(Int32(i)) }
        }
        if q.count > 0 { flood(blk, q, R, lo) }
    }

    // MARK: Build

    // `damage`: chipped blocks around this section (World.damage): x and z relative to the centre chunk's corner
    // (-16...31), world y, and the packed damage (face << 5 | level). They mesh as their remaining sub-cubes.
    // smoothOK false keeps the section cubic in smooth-terrain worlds (ships: built hulls must not melt into lumps).
    // `bites` (realistic world): where blows struck blocks round this section (World.biteList), carved as craters.
    static func buildSection(_ n9: [BlockStore], _ h9: [[Int16]], sy: Int, lod: Int = 0, damage: [(Int, Int, Int, UInt8)] = [],
                             bites: [(Int, Int, Int, Bite)] = [], pieces: [FreePiece] = [],
                             smoothOK: Bool = true, site: SmoothSite? = nil, chunk: (x: Int, z: Int)? = nil, nearSides: Int = 0) -> SectionMesh {
        guard sy >= 0 && sy < NSEC else { return SectionMesh(opaque: [], trans: [], light: nil) }
        // lod: 0 full detail, 1 far (flat light, merged faces, no small decorations, "fast" leaves), 2 mid (full detail
        // but "fast" leaves: no faces between leaves; World.leafNear, Quest).
        let far = lod == 1
        let renderT = Blocks.render, opaqueT = Blocks.opaque, aoT = Blocks.aoOcc, loT = Blocks.lightOpaque
        let crossT = Blocks.crossSize
        let swayT = Blocks.sway, swayOn = Mesher.plantSway, driftT = Blocks.drift
        let cullSameT = Blocks.cullSame, texT = Blocks.tex, tintT = Blocks.tint, levelT = Blocks.fluidLevel, fkT = Blocks.fluidKind
        let layerT = Blocks.layer, boxesT = Blocks.boxes, collideT = Blocks.collide
        let CT = cornerTable, NT = normalTable, PTab = plantTable
        let rCube = RenderType.cube.rawValue, rCross = RenderType.cross.rawValue
        let rLiquid = RenderType.liquid.rawValue, rModel = RenderType.model.rawValue, rNone = RenderType.none.rawValue
        let rConnect = RenderType.connect.rawValue, connT = Blocks.connectKind
        let rWire = RenderType.wire.rawValue, rsK = Circuit.kinds, gbT = Blocks.groupBase, joinT = ChestJoin.joinable
        let rRail = RenderType.rail.rawValue
        let waterTex = Int(WATER) * 6
        let translucent = RenderLayer.translucent.rawValue
        let iceT = Mesher.iceTable
        let y0 = sy * 16 - 16

        // Quick exit: an all-air section has no geometry of its own.
        let base = sy * 16 * CSQ
        let srcs = n9.map { $0.data }          // stored sections only; everything above is air
        let centre = srcs[4]
        // PG1 field worlds (FieldTerrain.swift): the ground is the chunks' density field, not blocks.
        let fieldOn = n9[4].isField
        if base >= n9[4].storedCount { return SectionMesh(opaque: [], trans: [], light: nil) }
        var anyBlock = false
        if base < centre.count { for i in base..<(base + 16 * CSQ) where centre[i] != AIR { anyBlock = true; break } }
        if !anyBlock && fieldOn { for i in base..<(base + 16 * CSQ) where n9[4].ground(i) { anyBlock = true; break } }
        if !anyBlock && pieces.contains(where: { Int(floor($0.p[1])) >> 4 == sy }) { anyBlock = true }     // (FreeBuild)
        // Smooth terrain: an empty section still owns the quads against its +x/+y/+z neighbours' first row.
        let smooth = (SmoothTerrain.enabled || n9[4].isField) && smoothOK, natT = SmoothTerrain.natural, snowLayerID = SmoothTerrain.snowLayer
        // T17: leaf canopies as rounded blobs in field worlds (smoothQuads leaves pass).
        let leafBlob = smooth && (site != nil || fieldOn) && SmoothTerrain.leafBlobs
        let detail = smooth && Mesher.detailMeshes, detT = Mesher.detailT
        // PG3: far sections (lod 1) draw them round too, with the fewest sides (ShapeTrunks, ShapeOrganic): a polygon
        // world shows no square trunk at any distance.
        let detailDraw = detail
        // Realistic world: built blocks near the eye get a 1/16 chamfer on their exposed edges (Mesher.bevelT).
        let bevel = detail && lod == 0, bevelT = Mesher.bevelT
        if !anyBlock && !(smooth && (smoothEdgeNatural(srcs, sy: sy, leaves: leafBlob) || fieldOn && fieldEdgeGround(n9, sy: sy))) {
            return SectionMesh(opaque: [], trans: [], light: nil)
        }

        // Gather the region: index = x + z*RW + ry*RL, world y = y0 + ry.
        // All scratch memory is per worker thread and reused (allocating and zeroing three 110K-cell arrays
        // per section, plus copy-on-write checks on every array write, were ~half of the meshing time).
        let sc = MeshScratch.current
        let region = sc.region
        region.initialize(repeating: AIR, count: RL * RH)
        for ry in 0..<RH {
            let y = y0 + ry
            if y < 0 {
                for i in 0..<RL { region[ry * RL + i] = BEDROCK }
                continue
            }
            if y >= CH { continue }
            for cz in 0..<3 {
                for cx in 0..<3 {
                    let src = srcs[cx + cz * 3]
                    if y * CSQ >= src.count { continue }        // above the stored part: air (already)
                    for z in 0..<CS {
                        let si = z * CS + y * CSQ
                        let di = cx * CS + (cz * CS + z) * RW + ry * RL
                        for x in 0..<CS { region[di + x] = src[si + x] }
                    }
                }
            }
        }
        // The field's ground into the region (as its material, so light, ao and the cube pass's culling see it) and its
        // densities beside it (sc.dens, the same indices; inside below the world, outside above it).
        let dens = sc.dens
        if fieldOn {
            let idx = FieldMat.blocks
            for ry in 0..<RH {
                let y = y0 + ry, row = ry * RL
                if y < 0 { (dens + row).initialize(repeating: FieldTerrain.inside, count: RL); continue }
                (dens + row).initialize(repeating: FieldTerrain.outside, count: RL)
                if y >= CH { continue }
                for cz in 0..<3 {
                    for cx in 0..<3 {
                        let st = n9[cx + cz * 3]
                        if y * CSQ >= st.storedCount { continue }
                        for z in 0..<CS {
                            let si = z * CS + y * CSQ
                            let di = cx * CS + (cz * CS + z) * RW + row
                            for x in 0..<CS {
                                let d = st.density(si + x)
                                dens[di + x] = d
                                if d > 0 && region[di + x] == AIR { region[di + x] = idx[Int(st.material(si + x))] }
                            }
                        }
                    }
                }
            }
        }
        let R = region
        // Natural ground at region index j: in a field world only the field's ground (a structure's sandstone or stone in
        // the built layer is a block, drawn and culled as one).
        @inline(__always) func natAt(_ j: Int) -> Bool { natT[Int(R[j])] && (!fieldOn || dens[j] > 0) }

        // Fully buried section (all opaque, and so is the 1-block shell around it): nothing visible.
        var buried = true
        outer: for ry in (C0 - 1)...(C0 + 16) {
            for z in (C0 - 1)...(C0 + 16) {
                for x in (C0 - 1)...(C0 + 16) {
                    let edges = (ry == C0 - 1 || ry == C0 + 16 ? 1 : 0) + (z == C0 - 1 || z == C0 + 16 ? 1 : 0) + (x == C0 - 1 || x == C0 + 16 ? 1 : 0)
                    if edges >= 2 && !smooth { continue }
                    if !opaqueT[Int(R[x + z * RW + ry * RL])] { buried = false; break outer }
                }
            }
        }
        if buried { return SectionMesh(opaque: [], trans: [], light: Mesher.dark, vis: 0) }

        let heights = sc.heights
        heights.initialize(repeating: -1, count: RL)
        for cz in 0..<3 {
            for cx in 0..<3 {
                let h = h9[cx + cz * 3]
                for z in 0..<CS { for x in 0..<CS { heights[cx * CS + x + (cz * CS + z) * RW] = Int(h[x + z * CS]) } }
            }
        }
        // Far (LOD 1) sections drop faces whose light is 0. Skylight can't reach the section's shell when every
        // column in the region has its surface more than 15 blocks above it (light falls 1 per block, water
        // included); without an emitter in the region the whole section is dark and would mesh to nothing.
        if far {
            var minH = Int.max
            for i in 0..<RL where heights[i] < minH { minH = heights[i] }
            if minH > y0 + C0 + 16 + 15 {
                // ...unless it holds an emitter, or a seabed (water and solid blocks in this section): under deep
                // water the floor is unlit but shows through the surface. All-water sections still skip.
                let emitT = Blocks.emit
                var lit = false
                for i in 0..<(RL * RH) where emitT[Int(R[i])] > 0 { lit = true; break }
                if !lit {
                    var wet = false, solid = false
                    for ly in 0..<16 { for lz in 0..<16 { for lx in 0..<16 {
                        let b = Int(R[(lx + C0) + (lz + C0) * RW + (ly + C0) * RL])
                        if fkT[b] == 1 { wet = true } else if opaqueT[b] { solid = true }
                    } } }
                    lit = wet && solid
                }
                if !lit { return SectionMesh(opaque: [], trans: [], light: Mesher.dark, vis: ~0) }
            }
        }
        // The region spans sections sy-1...sy+1 of the nine chunks.
        let near: UInt32 = sy == 0 ? 0b11 : (0b111 << UInt32(sy - 1))
        let emitters = n9.contains { $0.emitMask & near != 0 }
        computeLight(R, heights, y0: y0, sc, emitters: emitters)
        let skyL = sc.sky, blkL = sc.blk

        let lightOut = [UInt8](unsafeUninitializedCapacity: 4096) { out, n in
            for ly in 0..<16 {
                for lz in 0..<16 {
                    for lx in 0..<16 {
                        let ri = (lx + C0) + (lz + C0) * RW + (ly + C0) * RL
                        out[lx + lz * 16 + ly * 256] = (skyL[ri] << 4) | blkL[ri]
                    }
                }
            }
            n = 4096
        }

        let opq = sc.opq, cut = sc.cut, trn = sc.trn     // cut: alpha-tested faces (leaves, plants, models), after the solid ones
        opq.count = 0; cut.count = 0; trn.count = 0
        var curCut = false
        var groundV = 0, blobV = 0                       // (P283 stats: vertices from the two smooth passes)
        var farSkip = 0, farGround: [UInt32] = []        // P375 (GroundMerge)
        var leafy = false                                // faces between leaf blocks met (lod 0 and 2 differ)
        var naturalCubes = 0
        let solidLayer = RenderLayer.opaque.rawValue
        let leafT = Mesher.leafT, farLeaf = Mesher.farLeaves
        let offs = [1, -1, RL, -RL, RW, -RW]

        func at(_ x: Int, _ y: Int, _ z: Int) -> BlockID { R[x + z * RW + y * RL] }
        // Smooth terrain: a natural neighbour near the surface rounds away from a cubic block (or liquid), so the
        // block keeps its face against it (else sky shows through the gap); buried natural cells still hide faces.
        func smoothOpen(_ j: Int) -> Bool {
            if leafBlob && leafT[Int(R[j])] { return true }      // (a blob rounds away from a log or a built block)
            if detailDraw && detT[Int(R[j])] { return true }     // (a round trunk doesn't fill its block)
            guard smooth && natAt(j) else { return false }
            for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where !opaqueT[Int(R[j + dx + dz * RW + dy * RL])] { return true } } }
            return false
        }
        func occ(_ x: Int, _ y: Int, _ z: Int) -> Int { aoT[Int(R[x + z * RW + y * RL])] ? 1 : 0 }
        // R22: a plant (or a stack of up to four) at region index i standing on natural ground: in smooth worlds one in a
        // section's first row is drawn by the section below (the pass after the main loop), which can lower it.
        func plantOnNatural(_ i: Int) -> Bool {
            var g = -1, j = i - RL
            while g > -SmoothTerrain.maxRelax && renderT[Int(R[j])] == rCross { g -= 1; j -= RL }
            return natAt(j)
        }
        // P281 (a): the bottom and top offsets (1/16) of a plant lowered onto the drawn ground by dy16, `below` plants of
        // its stack under it. A stack the ground lookup reaches whole (maxRelax blocks or fewer) moves as one; in a taller
        // one (kelp, 20+ blocks) only the blocks within reach knew the ground and moved, the rest stayed: a gap (or an
        // overlap) opened between the 4th and 5th block of every strand. There the bottom block alone stretches to
        // the ground and every joint stays on its block line.
        func stackOffsets(_ i: Int, below: Int, _ dy16: Int) -> (Int, Int) {
            guard dy16 != 0 else { return (0, 0) }
            var n = below + 1, j = i + RL
            while n <= SmoothTerrain.maxRelax && renderT[Int(R[j])] == rCross { n += 1; j += RL }
            // P365 (d): a short stack moving as one still opened a gap between cane's 2nd and 3rd pieces where the stack
            // crossed into the next section up (each section reads the drawn ground from its own smoothing, which can
            // differ by a 1/16 or two). Any stack of two or more now keeps every joint on its block line and only the
            // foot stretches to the ground; a single plant still moves whole.
            if n == 1 { return (dy16, dy16) }
            return below == 0 ? (dy16, 0) : (0, 0)
        }
        // P281 (b): a drifting water plant's corner moves unless it is the stalk's foot (no drifting plant under it).
        // Its AO bits hold 3, which tells chunk.vert to move the bottom corners as well (wind-swayed crosses use 0-2).
        func driftFoot(_ i: Int) -> Bool { !(renderT[Int(R[i - RL])] == rCross && driftT[Int(R[i - RL])]) }
        // Packed sky | blk << 4, or -1 for solid cells (excluded from smoothing).
        func light(_ x: Int, _ y: Int, _ z: Int) -> Int {
            let i = x + z * RW + y * RL
            if loT[Int(R[i])] { return -1 }
            return Int(skyL[i]) | (Int(blkL[i]) << 4)
        }
        func vert(_ trans: Bool, _ x16: Int, _ y16: Int, _ z16: Int, _ shade: Int, _ tint: Int,
                  _ u: Int, _ v: Int, _ layer: Int, _ ao: Int, _ l: Int, _ overlay: Bool) {
            let w0 = UInt32(x16) | (UInt32(y16) << 9) | (UInt32(z16) << 18) | (UInt32(shade) << 27) | (UInt32(tint) << 30)
            let uv: UInt32 = UInt32(u) | (UInt32(v) << 5)
            let w1: UInt32 = uv | (UInt32(layer) << 10) | (UInt32(ao) << 20)
                | (UInt32(l & 15) << 22) | (UInt32((l >> 4) & 15) << 26) | (overlay ? (1 << 30) : 0) | (UInt32((layer >> 10) & 1) << 31)
            if trans { trn.append(w0); trn.append(w1) } else if curCut { cut.append(w0); cut.append(w1) } else { opq.append(w0); opq.append(w1) }
        }
        // Realistic world (built blocks): face f drawn 1/16 short of each edge it shares with another exposed side `ex`,
        // the 45-degree strip across each such edge (drawn by the lower-numbered face) and a corner triangle where three
        // exposed sides meet (drawn by the lowest). Strips carry a tilted normal (u = 31, projected texture).
        func bevelFace(f: Int, ex: Int, bx16: Int, by16: Int, bz16: Int, layer: Int, tint: Int, flat: Int, flip: Bool, isTrans: Bool) {
            let a = f >> 1, sa = f & 1 == 0 ? 1 : -1, pa = sa > 0 ? 16 : 0
            let base = SIMD3<Int>(bx16, by16, bz16)
            func put(_ q: SIMD3<Int>, _ n: SIMD3<Float>, _ l: Int, _ ao: Int) {
                let code = SmoothTerrain.normalCode(simd_normalize(n), face: f)
                vert(isTrans, base.x + q.x, base.y + q.y, base.z + q.z, f, tint, 31, code % 31, layer, ao, l, code >= 31)
            }
            // The face, inset where its edges are chamfered (texture from the face's own UVs, cropped the same way).
            for k in 0..<4 {
                let c = flip ? (k + 1) & 3 : k
                let ci = (f * 4 + c) * 3
                var q = SIMD3<Int>(CT[ci] * 16, CT[ci + 1] * 16, CT[ci + 2] * 16)
                for t in [(a + 1) % 3, (a + 2) % 3] {
                    if q[t] == 0 && ex & (1 << (t * 2 + 1)) != 0 { q[t] = 1 }
                    if q[t] == 16 && ex & (1 << (t * 2)) != 0 { q[t] = 15 }
                }
                let (u, v) = faceUV(f, q.x, q.y, q.z)
                vert(isTrans, base.x + q.x, base.y + q.y, base.z + q.z, f, tint, u, v, layer, aos[c], lit[c], false)
            }
            var nf = SIMD3<Float>(0, 0, 0); nf[a] = Float(sa)
            // Strips to the exposed sides with a higher index.
            for g in (f + 1)..<6 where g >> 1 != a && ex & (1 << g) != 0 {
                let b = g >> 1, sb = g & 1 == 0 ? 1 : -1, pb = sb > 0 ? 16 : 0
                let c3 = 3 - a - b
                let c0 = ex & (1 << (c3 * 2 + 1)) != 0 ? 1 : 0, c1 = ex & (1 << (c3 * 2)) != 0 ? 15 : 16
                var ng = SIMD3<Float>(0, 0, 0); ng[b] = Float(sb)
                var pts = [SIMD3<Int>](repeating: .zero, count: 4)
                for (k, (onF, cc)) in [(true, c0), (true, c1), (false, c1), (false, c0)].enumerated() {
                    var q = SIMD3<Int>(0, 0, 0)
                    q[c3] = cc
                    if onF { q[a] = pa; q[b] = pb - sb } else { q[b] = pb; q[a] = pa - sa }
                    pts[k] = q
                }
                let n = nf + ng
                let e1 = SIMD3<Float>(pts[1] &- pts[0]), e2 = SIMD3<Float>(pts[2] &- pts[0])
                if simd_dot(simd_cross(e1, e2), n) < 0 { pts.reverse() }
                for q in pts { put(q, n, flat, 3) }
            }
            // Corner triangles (three exposed sides meet; drawn when f is the lowest of them).
            for c in 0..<4 {
                let ci = (f * 4 + c) * 3
                let corner = SIMD3<Int>(CT[ci], CT[ci + 1], CT[ci + 2])
                let b = (a + 1) % 3, c3 = (a + 2) % 3
                let g = b * 2 + (corner[b] == 1 ? 0 : 1), h = c3 * 2 + (corner[c3] == 1 ? 0 : 1)
                guard g > f && h > f && ex & (1 << g) != 0 && ex & (1 << h) != 0 else { continue }
                let sb = corner[b] == 1 ? 1 : -1, sc = corner[c3] == 1 ? 1 : -1
                let pb = corner[b] * 16, pc = corner[c3] * 16
                var p0 = SIMD3<Int>(0, 0, 0), p1 = p0, p2 = p0
                p0[a] = pa; p0[b] = pb - sb; p0[c3] = pc - sc
                p1[b] = pb; p1[a] = pa - sa; p1[c3] = pc - sc
                p2[c3] = pc; p2[a] = pa - sa; p2[b] = pb - sb
                var n = nf; n[b] += Float(sb); n[c3] += Float(sc)
                var tri = [p0, p1, p2]
                if simd_dot(simd_cross(SIMD3<Float>(p1 &- p0), SIMD3<Float>(p2 &- p0)), n) < 0 { tri = [p0, p2, p1] }
                for q in tri { put(q, n, flat, 3) }
                put(tri[2], n, flat, 3)
            }
        }
        // T17 smooth water (field worlds): does a column sharing this top corner step down a level (open at y, still water
        // under it)? Then the corner drops to the lower surface, so a river's steps ramp down instead of standing as boxes.
        let smoothWater = smooth && (site != nil || fieldOn)
        func stepDown(_ cx: Int, _ y: Int, _ cz: Int) -> Bool {
            for dz in -1...0 {
                for dx in -1...0 {
                    let cell = Int(at(cx + dx, y, cz + dz))
                    if fkT[cell] != 0 || collideT[cell] { continue }
                    let under = at(cx + dx, y - 1, cz + dz)
                    if fkT[Int(under)] == 1 && levelT[Int(under)] == 0 { return true }
                }
            }
            return false
        }
        // Realistic world: is this top corner on the edge of a spilled sheet (a cell sharing it is open, holds no liquid
        // and has solid ground right under it)? Then the surface comes down to the ground there.
        func thinEdge(_ cx: Int, _ y: Int, _ cz: Int, _ kind: UInt8) -> Bool {
            var dry = false
            for dz in -1...0 {
                for dx in -1...0 {
                    let cell = Int(at(cx + dx, y, cz + dz))
                    if fkT[cell] == kind {
                        if fkT[Int(at(cx + dx, y + 1, cz + dz))] == kind { return false }    // full column: no edge
                        continue
                    }
                    if collideT[cell] || fkT[cell] != 0 { continue }
                    if collideT[Int(at(cx + dx, y - 1, cz + dz))] { dry = true }
                }
            }
            return dry
        }
        // Water surface drop (eighths) at a corner: highest of the up-to-4 liquid cells sharing it.
        func cornerDrop(_ cx: Int, _ y: Int, _ cz: Int, _ kind: UInt8) -> Int {
            var best = 7
            for dz in -1...0 {
                for dx in -1...0 {
                    let cell = at(cx + dx, y, cz + dz)
                    if fkT[Int(cell)] != kind { continue }
                    let lv = Int(levelT[Int(cell)])
                    if fkT[Int(at(cx + dx, y + 1, cz + dz))] == kind { return 0 }
                    let d = (lv == 0 || lv == 8) ? 1 : 1 + (lv * 6 + 3) / 7
                    if d < best { best = d }
                }
            }
            return best
        }

        // Water depth at a top corner in the AO bits (mean depth of the up-to-4 columns sharing it; see the liquid faces).
        // P297 (b): over smooth ground the depth runs from the water's top down to the drawn bed, not a count of water
        // cells, so the line between the shallows and dark deep water follows the bed instead of tracing cell squares.
        func depthAO(_ cx: Int, _ y: Int, _ cz: Int) -> Int {
            let smoothBed = smoothWater && sc.smValid          // (set by the ground pass, which runs before the faces)
            var sum = 0
            var depth: Float = 0
            for dz in -1...0 {
                for dx in -1...0 {
                    let bx = cx + dx, bz = cz + dz
                    var k = 0
                    while k < 9 && fkT[Int(at(bx, y - k, bz))] == 1 { k += 1 }
                    sum += k
                    guard smoothBed else { continue }
                    var g = y - k, d = Float(k)
                    if k < 9 && g > 0 && R[bx + bz * RW + g * RL] == AIR && natAt(bx + bz * RW + (g - 1) * RL) { g -= 1 }
                    if k < 9 && g >= 0 && natAt(bx + bz * RW + g * RL),
                       let top = Mesher.smoothGroundTop(sc, bx - C0, g - C0, bz - C0) {
                        d = max(0, Float(y - C0) + 0.875 - top)
                    }
                    depth += d
                }
            }
            if smoothBed { depth *= 0.25; return depth <= 0.75 ? 3 : (depth < 2 ? 2 : (depth < 5 ? 1 : 0)) }
            return sum <= 3 ? 3 : (sum < 8 ? 2 : (sum < 20 ? 1 : 0))
        }
        // P175 (polygon worlds): the water plane carries on over natural ground beside a water surface, under the ground's
        // smooth surface, so the waterline is wherever the ground crosses the water level (a curve), not a block outline.
        // Lava does the same (PG1 rewrite: a lava pool's edge was a sawtooth of cell squares against the smooth ground).
        func shoreWater(_ i: Int, _ ly: Int) {
            let up = fkT[Int(R[i + RL])]
            var src = -1
            for o in [1, -1, RW, -RW, 1 + RW, 1 - RW, -1 + RW, -1 - RW] {
                let j = i + o
                let k = fkT[Int(R[j])]
                if k != 0 && k != up && fkT[Int(R[j + RL])] != k { src = j; break }
            }
            // P297 (b): two cells out too (water, then a cell of low ground, then this one), so the plane runs on until the
            // ground has risen over it and never stops at a cell's edge with the bank still under the waterline.
            if src < 0 {
                for (dx, dz) in Mesher.shoreRing2 {
                    let j = i + dx + dz * RW
                    let k = fkT[Int(R[j])]
                    let mid = i + dx / 2 + dz / 2 * RW                  // (through low bank, never through a wall)
                    if k != 0 && k != up && fkT[Int(R[j + RL])] != k && (!opaqueT[Int(R[mid])] || natAt(mid)) { src = j; break }
                }
            }
            guard src >= 0 else { return }
            let fk = fkT[Int(R[src])]
            let x = i % RW, z = (i / RW) % RW, y = ly + C0
            let lx = x - C0, lz = z - C0
            let l = max(0, light(src % RW, y, (src / RW) % RW))
            let layer = Int(texT[Int(R[src]) * 6 + 2])
            let lavaTrans = layerT[Int(R[src])] == translucent
            for k in 0..<4 {
                let ci = (2 * 4 + k) * 3
                let px = CT[ci] * 16, pz = CT[ci + 2] * 16
                let d = cornerDrop(x + CT[ci], y, z + CT[ci + 2], fk)
                var py = 16 - 2 * (d == 7 ? 1 : d)
                // P297 (b): a corner with no water round it goes just under the drawn ground there when that is lower
                // than the water, so the plane meets the bank along the ground's own curve; at the full height it ended
                // at the cell's edge over low ground, a saw-tooth waterline.
                if d == 7, let g = Mesher.groundCorner(sc, lx + CT[ci], ly, lz + CT[ci + 2]) {
                    py = max(-ly * 16, min(py, Int(((g - Float(ly)) * 16).rounded()) - 2))
                }
                let (u, v) = faceUV(2, px, max(0, py), pz)
                if fk == 1 {
                    vert(true, lx * 16 + px, ly * 16 + py, lz * 16 + pz, 2, 3, u, v, layer,
                         Mesher.waterDepthAO ? depthAO(x + CT[ci], y, z + CT[ci + 2]) : 3, l, false)
                } else {
                    vert(lavaTrans, lx * 16 + px, ly * 16 + py, lz * 16 + pz, 7, 0, u, v, layer, 3, l, false)
                }
            }
        }

        var waterMask: [Int32] = []                    // P184: far still-water tops to merge (allocated on first use)
        let lit = sc.lit, aos = sc.aos
        lit.initialize(repeating: 0, count: 4)
        aos.initialize(repeating: 3, count: 4)
        // Greedy meshing: flat-lit cube faces are collected per face direction and slice, then merged
        // into big quads (u = v = 31 tells the shader to take UVs from the position, repeating per block).
        // key = 1 + (layer | tint<<11 | overlay<<13 | ao<<14 | light<<16 | trans<<24)
        let mask = sc.mask
        mask.initialize(repeating: 0, count: 6 * 16 * 256)
        // Chipped blocks in the region (progressive block damage): region index -> packed damage.
        var dmg: [Int: UInt8] = [:]
        // (Realistic world: blows are drawn as craters, below; the chipped sub-cubes and dents are the block worlds'.)
        for (dx, wy, dz, v) in damage where !detail {
            let rx = dx + C0, rz = dz + C0, ry = wy - y0
            if rx < 0 || rz < 0 || ry < 0 || rx >= RW || rz >= RW || ry >= RH { continue }
            dmg[rx + rz * RW + ry * RL] = v
        }
        let anyDmg = !dmg.isEmpty
        // Realistic world: craters where blows struck (Craters.swift), carved into the detail stream by the ground pass and
        // the struck cubes below.
        let det = sc.det, detCut = sc.detCut
        det.count = 0; detCut.count = 0
        let wox = (chunk?.x ?? site?.cx ?? 0) * CS, woz = (chunk?.z ?? site?.cz ?? 0) * CS
        let crater: CraterSet? = detailDraw && !bites.isEmpty
            ? CraterSet(bites, sy: sy, wo: SIMD3<Float>(Float(wox), Float(sy * 16), Float(woz))) { x, y, z in
                let rx = x + C0, ry = y + C0, rz = z + C0
                return rx >= 0 && ry >= 0 && rz >= 0 && rx < RW && ry < RH && rz < RW ? rx + rz * RW + ry * RL : nil }
            : nil
        let craters = crater.flatMap { $0.isEmpty ? nil : $0 }
        // The smooth ground first: the plants below stand on its drawn surface (P175), read back from its vertices.
        sc.smValid = false
        if smooth && fieldOn && far && Mesher.farGround {
            // P283: far field ground on the two-block lattice (SmoothTerrain.coarseGround).
            coarseGround(R, dens, sc, nearSides: nearSides) { x16, y16, z16, f, tint, layer, ao, l, ncode in
                curCut = false
                groundV += 1
                vert(false, x16, y16, z16, f, tint, 31, ncode % 31, layer, ao, l, ncode >= 31)
            }
        } else if smooth {
            let gm: GroundMerge? = fieldOn && GroundMerge.enabled && opq.count == 0 ? sc.groundMerge : nil     // (replaced quads lead the buffer)
            gm?.reset()
            let g0 = opq.count
            smoothQuads(R, sc, dmg: dmg, site: fieldOn ? nil : site, stored: fieldOn ? dens : nil, sy: sy, leafHoles: leafBlob, detailHoles: detail,
                        world: fieldOn ? SIMD3<Int>(wox, sy * 16, woz) : nil, crater: craters, carveOut: det, merge: gm) { x16, y16, z16, f, tint, layer, ao, l, ncode in
                curCut = false
                groundV += 1
                // u = 31 projects the texture; v (+ 31 when the overlay bit is set) is the vertex normal code (< 49).
                vert(false, x16, y16, z16, f, tint, 31, ncode % 31, layer, ao, l, ncode >= 31)
            }
            // P375 (GroundMerge): the merged ground's replaced quads first, the rest of the ground after them, and the
            // merged copy kept aside (appended past the cutout quads, drawn far only).
            if let gm, !gm.quads.isEmpty {
                var rep: [Int] = [], kept: [Int] = [], mergedQ: [[SIMD8<Int32>]] = []
                gm.solve(replaced: &rep, kept: &kept, mergedOut: &mergedQ)
                let rest = Array(UnsafeBufferPointer(start: opq.ptr + g0, count: opq.count - g0))
                opq.count = g0
                curCut = false
                func put(_ q: [SIMD8<Int32>], flip: Bool) {
                    for k in 0..<4 {
                        let v = q[flip ? (k + 1) & 3 : k]
                        let nc = Int(v[7])
                        vert(false, Int(v[0]), Int(v[1]), Int(v[2]), 2, Int(v[3]), 31, nc % 31, Int(v[4]), Int(v[5]), Int(v[6]), nc >= 31)
                        groundV += 1
                    }
                }
                for i in rep { put(gm.quads[i].v, flip: gm.quads[i].flip) }
                for w in rest { opq.append(w) }
                for i in kept { put(gm.quads[i].v, flip: gm.quads[i].flip) }
                farSkip = rep.count
                let before = opq.count
                for q in mergedQ { put(q, flip: false) }
                groundV -= mergedQ.count * 4
                farGround = Array(UnsafeBufferPointer(start: opq.ptr + before, count: opq.count - before))
                opq.count = before
            }
        }

        // P338 step 5 / P363 (Remington, Oct 16-17: "lava still conforms to blocks", "water still shows blocks", water not
        // settling onto the beach): in a field world water and lava near the eye are drawn as surfaces of their own field,
        // not as cell boxes. Each sample (a cell's centre) gets the fluid's signed height over it: a fluid cell its own
        // top (from its level; a full cell under more of it), ground, built solids and the bank (an open cell the ground
        // reaches into) the level of the fluid round it (5 x 5 cells, a layer up and down), so the surface runs on as
        // the flat level through the bank and under the ground's surface and meets the ground wherever the ground
        // crosses the level (a beach takes the water up to the waterline, a pool's edge is the ground's own curve);
        // open air beside it with no ground holds it back (a wall at the edge of a drop, rounded). The surface is
        // the field's zero crossing (surface nets: a vertex per cell at the mean of its edge crossings, normals from
        // the field), quads wholly inside the ground left out. Far sections keep the merged cell water.
        let fluidNets = fieldOn && !far && Mesher.fluidNets
        if fluidNets {
            for kind in [UInt8(1), UInt8(2)] {
                var any = false
                outer: for y in (C0 - 2)..<(C0 + 20) { for z in (C0 - 2)..<(C0 + 20) { for x in (C0 - 2)..<(C0 + 20) where fkT[Int(R[x + z * RW + y * RL])] == kind { any = true; break outer } } }
                if !any { continue }
                let N = 18, NN = N * N, M = 17, MM = M * M
                func top(_ j: Int) -> Float {
                    if fkT[Int(R[j + RL])] == kind { return 1 }
                    let lv = Int(levelT[Int(R[j])])
                    let d = (lv == 0 || lv == 8) ? 1 : 1 + (lv * 6 + 3) / 7
                    return Float(16 - 2 * d) / 16
                }
                withUnsafeTemporaryAllocation(of: Float.self, capacity: N * NN) { F in
                withUnsafeTemporaryAllocation(of: SIMD3<Float>.self, capacity: M * MM) { V in
                withUnsafeTemporaryAllocation(of: Bool.self, capacity: M * MM) { has in
                    for sy in 0..<N { for sz in 0..<N { for sx in 0..<N {
                        let i = (sx + C0) + (sz + C0) * RW + (sy + C0) * RL
                        let b = Int(R[i]), fk = fkT[b]
                        var f: Float = -1
                        if fk == kind {
                            f = fkT[Int(R[i + RL])] == kind ? 1 : top(i) - 0.5
                        } else if fk == 0 {
                            var L: Float = -9
                            for dy in -1...1 { for dz in -2...2 { for dx in -2...2 {
                                let j = i + dx + dz * RW + dy * RL
                                if fkT[Int(R[j])] == kind { L = max(L, Float(dy) + top(j)) }
                            } } }
                            if L > -9 {
                                f = L - 0.5
                                if !(collideT[b] || dens[i] > -32) { f = min(f, -0.5) }      // open air, no ground: held back
                            }
                        }
                        F[sx + sz * N + sy * NN] = max(-1, min(1, f))
                    } } }
                    // A vertex per cell with a crossing: the mean of its edges' crossings (sample s sits at s + 0.5).
                    for cy in 0..<M { for cz in 0..<M { for cx in 0..<M {
                        let ci = cx + cz * M + cy * MM
                        has[ci] = false
                        var c8 = SIMD8<Float>(repeating: 0)
                        var inside = 0
                        for k in 0..<8 {
                            let v = F[(cx + (k & 1)) + (cz + ((k >> 2) & 1)) * N + (cy + ((k >> 1) & 1)) * NN]
                            c8[k] = v; if v > 0 { inside += 1 }
                        }
                        if inside == 0 || inside == 8 { continue }
                        var sum = SIMD3<Float>(repeating: 0), n: Float = 0
                        for (a, b) in Mesher.cubeEdges {
                            let va = c8[a], vb = c8[b]
                            guard (va > 0) != (vb > 0) else { continue }
                            let t = va / (va - vb)
                            let pa = SIMD3<Float>(Float(a & 1), Float((a >> 1) & 1), Float((a >> 2) & 1))
                            let pb = SIMD3<Float>(Float(b & 1), Float((b >> 1) & 1), Float((b >> 2) & 1))
                            sum += pa + (pb - pa) * t; n += 1
                        }
                        V[ci] = SIMD3<Float>(Float(cx), Float(cy), Float(cz)) + 0.5 + sum / n
                        has[ci] = true
                    } } }
                    let layer = Int(texT[(kind == 1 ? Int(WATER) : Int(LAVA)) * 6 + 2])
                    let trans = kind == 1 || layerT[Int(LAVA)] == translucent
                    // Quads: one per sample edge with a crossing, round it the four cells' vertices. A section owns the
                    // edges starting at 0...15 along the edge and 1...16 across it, so every edge is drawn once.
                    for a in 0..<3 {
                        let b = (a + 1) % 3, c = (a + 2) % 3
                        var p = SIMD3<Int>(0, 0, 0)
                        for pc in 1...16 { for pb in 1...16 { for pa in 0..<16 {
                            p[a] = pa; p[b] = pb; p[c] = pc
                            var q = p; q[a] += 1
                            let f0 = F[p.x + p.z * N + p.y * NN], f1 = F[q.x + q.z * N + q.y * NN]
                            guard (f0 > 0) != (f1 > 0) else { continue }
                            var cells = [SIMD3<Int>](repeating: p, count: 4)
                            cells[0][b] -= 1; cells[0][c] -= 1
                            cells[1][c] -= 1
                            cells[3][b] -= 1
                            var vs = [SIMD3<Float>](repeating: .zero, count: 4)
                            var ok = true, buried = 0
                            for k in 0..<4 {
                                let ci = cells[k].x + cells[k].z * M + cells[k].y * MM
                                if !has[ci] { ok = false; break }
                                vs[k] = V[ci]
                                let g = SIMD3<Int>(Int(floor(vs[k].x)), Int(floor(vs[k].y)), Int(floor(vs[k].z))) &+ C0
                                if dens[g.x + g.z * RW + g.y * RL] > 8 { buried += 1 }
                            }
                            if !ok || buried == 4 { continue }
                            // Facing out of the fluid: +a where the inside is the lower sample.
                            var dir = SIMD3<Float>(0, 0, 0); dir[a] = f0 > 0 ? 1 : -1
                            if simd_dot(simd_cross(vs[1] - vs[0], vs[2] - vs[0]), dir) < 0 { vs.swapAt(1, 3); cells.swapAt(1, 3) }
                            // The face (shade and texture projection) from the quad's facing; lava tops animate (7).
                            let nq = simd_cross(vs[2] - vs[0], vs[3] - vs[1])
                            let ax = abs(nq.x) >= abs(nq.y) && abs(nq.x) >= abs(nq.z) ? 0 : (abs(nq.y) >= abs(nq.z) ? 1 : 2)
                            let face = ax * 2 + (nq[ax] >= 0 ? 0 : 1)
                            let (ua, va) = ax == 1 ? (0, 2) : (ax == 0 ? (2, 1) : (0, 1))
                            let ou = floor(min(min(vs[0][ua], vs[1][ua]), min(vs[2][ua], vs[3][ua])))
                            let ov = floor(min(min(vs[0][va], vs[1][va]), min(vs[2][va], vs[3][va])))
                            for k in 0..<4 {
                                let v = vs[k], cl = cells[k]
                                var sky = 0, blk = 0
                                for m in 0..<8 {
                                    let l = light(cl.x + (m & 1) + C0, cl.y + ((m >> 1) & 1) + C0, cl.z + ((m >> 2) & 1) + C0)
                                    if l >= 0 { sky = max(sky, l & 15); blk = max(blk, l >> 4) }
                                }
                                let u16 = min(31, max(0, Int(((v[ua] - ou) * 16).rounded()))), v16 = min(31, max(0, Int(((v[va] - ov) * 16).rounded())))
                                let x16 = Int((v.x * 16).rounded()), y16 = Int((v.y * 16).rounded()), z16 = Int((v.z * 16).rounded())
                                if kind == 1 {
                                    let ao = Mesher.waterDepthAO && face == 2 ? depthAO(cl.x + 1 + C0, cl.y + C0, cl.z + 1 + C0) : 3
                                    vert(true, x16, y16, z16, face, 3, u16, v16, layer, ao, sky | blk << 4, false)
                                } else {
                                    curCut = false
                                    vert(trans, x16, y16, z16, face == 2 ? 7 : face, 0, u16, v16, layer, 3, sky | blk << 4, false)
                                }
                            }
                        } } }
                    }
                } } }
            }
        }
        for ly in 0..<16 {
            let y = ly + C0
            for z in C0..<(C0 + 16) {
                for x in C0..<(C0 + 16) {
                    let i = x + z * RW + y * RL
                    let b = R[i]
                    if b == AIR {
                        // P297 (b): air over low ground on the bank carries the water plane on too (the bank's smooth
                        // surface dips under the waterline inside it; the water used to end at the cell's square there).
                        if smoothWater && !fluidNets && natAt(i - RL) { shoreWater(i, ly) }
                        continue
                    }
                    let bi = Int(b)
                    let rt = renderT[bi]
                    if rt == rNone { continue }
                    if smooth && natT[bi] && (!fieldOn || dens[i] > 0) {    // (chipped too: it shrinks in the smooth surface, P106)
                        if smoothWater && !fluidNets { shoreWater(i, ly) }
                        continue
                    }
                    if fieldOn && natT[bi] { naturalCubes += 1 }        // (P338 step 2: the debug counter)
                    if leafBlob && leafT[bi] { continue }               // (T17: the leaf blobs below)
                    if detailDraw && detT[bi] { continue }              // (round shapes: the detail generators below)
                    // A struck cube (realistic world): its open faces subdivided and carved where the blows landed.
                    if let cr = craters, rt == rCube, cr.regionIndex.contains(i) {
                        let tb = Int(tintT[bi]), inner = (layer: Int(texT[bi * 6 + 3]), tint: tb == 3 ? 0 : tb)
                        for f in 0..<6 {
                            let j = i + offs[f]
                            if opaqueT[Int(R[j])] && !smoothOpen(j) { continue }
                            if cullSameT[bi] && R[j] == b { continue }
                            let lv = max(0, light(x + NT[f * 3], y + NT[f * 3 + 1], z + NT[f * 3 + 2]))
                            var ps = [SIMD3<Float>](repeating: .zero, count: 4)
                            for k in 0..<4 {
                                let ci = (f * 4 + k) * 3
                                ps[k] = SIMD3<Float>(Float(x - C0 + Int(CT[ci])), Float(ly + Int(CT[ci + 1])), Float(z - C0 + Int(CT[ci + 2])))
                            }
                            let fn = SIMD3<Float>(Float(NT[f * 3]), Float(NT[f * 3 + 1]), Float(NT[f * 3 + 2]))
                            let lay = Int(texT[bi * 6 + f]), tn = tb == 3 ? (f == 2 ? 1 : 0) : tb
                            if cr.touches(ps) {
                                cr.carve(det, ps, [fn, fn, fn, fn], layers: [lay, lay, lay, lay], tints: [tn, tn, tn, tn],
                                         light: [lv, lv, lv, lv], ao: [3, 3, 3, 3], inner: inner, face: f, grid: cr.ticks(ps, base: 6))
                            } else {
                                for k in 0..<4 {
                                    let q = ps[k]
                                    DetailMesh.vertex(det, q, fn, Craters.faceUV(f, q), layer: lay, tint: tn, ao: 3, light: lv)
                                }
                            }
                        }
                        continue
                    }
                    // A snow layer on smooth ground: the ground under it shows snow instead (smoothQuads); its slab drew a
                    // white sawtooth of block steps over every snowy slope (P142).
                    if smooth && (site != nil || fieldOn) && bi == snowLayerID && natAt(i - RL) { continue }
                    let lx = x - C0, lz = z - C0
                    let bx16 = lx * 16, by16 = ly * 16, bz16 = lz * 16
                    let tintB = Int(tintT[bi])
                    let tintV = tintB == 3 ? 1 : tintB
                    let isTrans = layerT[bi] == translucent
                    curCut = !(rt == rCube && layerT[bi] == solidLayer)

                    if anyDmg, let dv = dmg[i], rt == rCube {
                        // A chipped block: its remaining 4x4x4 sub-cubes, faces between them and against undamaged
                        // opaque neighbours left out, lit by its brightest open neighbour.
                        let keep = Mesher.chipMask(face: Int(dv >> 5), level: Int(dv & 31), x: x, y: y, z: z)
                        var l = 0
                        for f in 0..<6 {
                            let lv = light(x + NT[f * 3], y + NT[f * 3 + 1], z + NT[f * 3 + 2])
                            if lv >= 0 && (lv & 15) + ((lv >> 4) & 15) > (l & 15) + ((l >> 4) & 15) { l = lv }
                        }
                        curCut = true
                        for c in 0..<64 where keep & (UInt64(1) << UInt64(c)) != 0 {
                            let a = c & 3, bb = (c >> 2) & 3, cc = c >> 4          // x, z, y sub-cube
                            for f in 0..<6 {
                                let na = a + NT[f * 3], nc = cc + NT[f * 3 + 1], nb2 = bb + NT[f * 3 + 2]
                                if na >= 0 && na < 4 && nb2 >= 0 && nb2 < 4 && nc >= 0 && nc < 4 {
                                    if keep & (UInt64(1) << UInt64(na | (nb2 << 2) | (nc << 4))) != 0 { continue }
                                } else {
                                    let j = i + offs[f]
                                    if opaqueT[Int(R[j])] && dmg[j] == nil { continue }
                                }
                                let mn = [a * 4, cc * 4, bb * 4], mx = [a * 4 + 4, cc * 4 + 4, bb * 4 + 4]
                                let layer = Int(texT[bi * 6 + f])
                                for k in 0..<4 {
                                    let ci = (f * 4 + k) * 3
                                    let px = CT[ci] == 1 ? mx[0] : mn[0]
                                    let py = CT[ci + 1] == 1 ? mx[1] : mn[1]
                                    let pz = CT[ci + 2] == 1 ? mx[2] : mn[2]
                                    let (u, v) = faceUV(f, px, py, pz)
                                    vert(false, bx16 + px, by16 + py, bz16 + pz, f, tintV, u, v, layer, 3, l, false)
                                }
                            }
                        }
                        continue
                    }
                    // Water held in a waterlogged block (and round kelp / seagrass): drawn like a source cell beside the
                    // block's own model, its surface and the sides open to air (the reference's waterlogged look).
                    if fkT[bi] == 1 && rt != rLiquid {
                        let waterTop = fkT[Int(R[i + RL])] != 1
                        for f in 0..<6 {
                            let nb = Int(R[i + offs[f]])
                            if fkT[nb] == 1 || opaqueT[nb] { continue }
                            if collideT[nb] && layerT[nb] != translucent { continue }
                            let flat = max(0, light(x + NT[f * 3], y + NT[f * 3 + 1], z + NT[f * 3 + 2]))
                            let layer = Int(texT[waterTex + f])
                            for k in 0..<4 {
                                let ci = (f * 4 + k) * 3
                                let px = CT[ci] * 16, pz = CT[ci + 2] * 16
                                var py = CT[ci + 1] * 16
                                if waterTop && py == 16 { py = 16 - 2 * cornerDrop(x + CT[ci], y, z + CT[ci + 2], 1) }
                                let (u, v) = faceUV(f, px, py, pz)
                                vert(true, bx16 + px, by16 + py, bz16 + pz, f, 3, u, v, layer, 3, flat, false)
                            }
                        }
                    }
                    if far && (rt == rCross || rt == rRail || rt == rWire) { continue }     // far: no small decorations
                    if rt == rCross {
                        // R22 (Oct 13, "floating grass in the polygon world"): vertex heights can't go under the section's
                        // floor, so a plant in its first row over a dip stayed up to 3/4 block over the drawn ground: the
                        // section below draws it (after the main loop).
                        if smooth && ly == 0 && plantOnNatural(i) { continue }
                        let l = Int(skyL[i]) | (Int(blkL[i]) << 4)
                        // P175: a plant (or a stack of them, cane) on smooth ground stands on the drawn surface, not on the
                        // block top it was rounded from (grass floated over every dip).
                        var dy16 = 0, dyTop = 0
                        if sc.smValid {
                            var g = ly - 1, j = i - RL
                            while g > -SmoothTerrain.maxRelax && renderT[Int(R[j])] == rCross { g -= 1; j -= RL }
                            if natAt(j), let top = Mesher.smoothGroundTop(sc, lx, g, lz) {
                                let want = max(-by16, max(-12, min(12, Int(((top - Float(g + 1)) * 16).rounded()))))
                                (dy16, dyTop) = stackOffsets(i, below: ly - 1 - g, want)
                            }
                        }
                        let layer = Int(texT[bi * 6 + 2])
                        let cs = Int(crossT[bi]), ci0 = (16 - cs) / 2
                        let drift = swayOn && driftT[bi], foot = drift && driftFoot(i)
                        let sway = drift || swayOn && swayT[bi]
                        // swaying: the AO bits hold its phase 0-2 (crosses draw unshaded); 3 marks a drifting stalk (P281 b)
                        let aoC = drift ? 3 : (sway ? (x &* 5 &+ z &* 3 &+ y) % 3 : 3)
                        // Pointed driprock: the texture hangs (point down); one growing up from a floor is drawn flipped
                        // so its point is on top (Oct 11 Quest playtest P3: "the drip stone's still upside down").
                        var flipV = false
                        if b == Mesher.pointedDrip {
                            var j = i, hangs = false
                            for _ in 0..<4 {
                                let up = R[j + RL]
                                if up == b { j += RL; continue }
                                hangs = opaqueT[Int(up)]; break
                            }
                            flipV = !hangs
                        }
                        for q in 0..<4 {
                            for k in 0..<4 {
                                let ci = (q * 4 + k) * 3
                                let up = PTab[ci + 1]
                                vert(isTrans, bx16 + ci0 + PTab[ci] * cs, by16 + (up == 1 ? dyTop : dy16) + up * cs, bz16 + ci0 + PTab[ci + 2] * cs,
                                     6, tintV, cornerU[k], flipV ? 16 - cornerV[k] : cornerV[k], layer, aoC, l, sway && !(foot && up == 0))
                            }
                        }
                        continue
                    }

                    if rt == rRail {
                        // One textured quad a sixteenth above the floor; slopes lift one edge a full block.
                        let st = Int(b - gbT[bi])
                        let shape = rsK[bi] == .rail ? st : st % 6
                        let l = Int(skyL[i]) | (Int(blkL[i]) << 4)
                        let layer = Int(texT[bi * 6 + 2])
                        for k in 0..<4 {
                            let ci = (2 * 4 + k) * 3
                            let px = CT[ci] * 16, pz = CT[ci + 2] * 16
                            var py = 1
                            switch shape {
                            case 2: if px == 16 { py += 16 }
                            case 3: if px == 0 { py += 16 }
                            case 4: if pz == 0 { py += 16 }
                            case 5: if pz == 16 { py += 16 }
                            default: break
                            }
                            var u = px, v = pz
                            switch shape {
                            case 1, 2, 3: (u, v) = (pz, px)                     // east-west: rotate the texture
                            case 7: (u, v) = (16 - px, pz)
                            case 8: (u, v) = (16 - px, 16 - pz)
                            case 9: (u, v) = (px, 16 - pz)
                            default: break
                            }
                            vert(false, bx16 + px, by16 + py, bz16 + pz, 2, 0, u, v, layer, 3, l, false)
                        }
                        continue
                    }

                    if rt == rWire {
                        // Sparkstone dust: a cross when alone, lines toward what it connects to, and
                        // strips up the side of blocks it climbs.
                        func connects(_ n: BlockID, _ d: Int) -> Bool { Circuit.dustConnects(n, d) }
                        var conn = [false, false, false, false], climb = [false, false, false, false]
                        let aboveSolid = opaqueT[Int(R[i + RL])]
                        let nOff = [-RW, RW, -1, 1]
                        for k in 0..<4 {
                            let n = R[i + nOff[k]]
                            if connects(n, k + 2) { conn[k] = true; continue }
                            if !opaqueT[Int(n)] && rsK[Int(R[i + nOff[k] - RL])] == .wire { conn[k] = true; continue }
                            if opaqueT[Int(n)] && !aboveSolid && rsK[Int(R[i + nOff[k] + RL])] == .wire { conn[k] = true; climb[k] = true }
                        }
                        let count = conn.filter { $0 }.count
                        if count == 0 && Int(b - gbT[Int(b)]) < 16 { conn = [true, true, true, true] }   // cross (a dot stays bare)
                        else if count == 1, let k = conn.firstIndex(of: true) { conn[[1, 0, 3, 2][k]] = true }
                        var quads: [(Box, Int)] = [(Box(5, 1, 5, 11, 1, 11), 2)]
                        let arms = [Box(6, 1, 0, 10, 1, 5), Box(6, 1, 11, 10, 1, 16), Box(0, 1, 6, 5, 1, 10), Box(11, 1, 6, 16, 1, 10)]
                        let walls = [(Box(6, 0, 1, 10, 16, 1), 4), (Box(6, 0, 15, 10, 16, 15), 5), (Box(1, 0, 6, 1, 16, 10), 0), (Box(15, 0, 6, 15, 16, 10), 1)]
                        for k in 0..<4 where conn[k] { quads.append((arms[k], 2)) }
                        for k in 0..<4 where climb[k] { quads.append(walls[k]) }
                        let l = Int(skyL[i]) | (Int(blkL[i]) << 4)
                        let layer = Int(texT[bi * 6 + 2])
                        for (box, f) in quads {
                            let mn = [Int(box.x0), Int(box.y0), Int(box.z0)], mx = [Int(box.x1), Int(box.y1), Int(box.z1)]
                            for k in 0..<4 {
                                let ci = (f * 4 + k) * 3
                                let px = CT[ci] == 1 ? mx[0] : mn[0]
                                let py = CT[ci + 1] == 1 ? mx[1] : mn[1]
                                let pz = CT[ci + 2] == 1 ? mx[2] : mn[2]
                                let (u, v) = faceUV(f, px, py, pz)
                                vert(false, bx16 + px, by16 + py, bz16 + pz, f, 0, u, v, layer, 3, l, false)
                            }
                        }
                        continue
                    }

                    // A lily pad on water is drawn as a single leaf 1/16 above the surface (water tops sit at 14/16), not a
                    // slab 2/16 up with edges: floating that high it read as pasted on (store-quality pass). The Quest's
                    // chunk.vert bobs it with the swell (foliage tint, top face, y at 15/16, AO = the water's shore factor).
                    if b == Mesher.lilyPad && ly > 0 && fkT[Int(at(x, y - 1, z))] == 1 {
                        let l = Int(skyL[i]) | (Int(blkL[i]) << 4)
                        let layer = Int(texT[bi * 6 + 2])
                        for f in 2...3 {
                            for k in 0..<4 {
                                let ci = (f * 4 + k) * 3
                                let px = CT[ci] == 1 ? 16 : 0, pz = CT[ci + 2] == 1 ? 16 : 0
                                let (u, v) = faceUV(2, px, 15, pz)
                                // Quest: the same shore factor (water depth at this corner) as the water corner under it,
                                // so chunk.vert lifts pad and water by the same swell and they never part in storms.
                                var padAO = 3
                                if Mesher.waterDepthAO { padAO = depthAO(x + CT[ci], y - 1, z + CT[ci + 2]) }
                                vert(isTrans, bx16 + px, by16 - 1, bz16 + pz, f, tintV, u, v, layer, padAO, l, false)
                            }
                        }
                        continue
                    }
                    if rt == rModel || rt == rConnect {
                        var boxes = boxesT[bi]
                        if rt == rConnect {
                            let ck = connT[bi]
                            boxes = BlockRegistry.connectBoxes(ck, n: Blocks.connects(ck, R[i - RW]), s: Blocks.connects(ck, R[i + RW]),
                                                               w: Blocks.connects(ck, R[i - 1]), e: Blocks.connects(ck, R[i + 1]), collision: false)
                        } else if joinT[bi] {
                            // P264: a double chest's half runs to the seam (ChestJoin.swift).
                            let wide = bi - Int(gbT[bi]) < 2
                            if let jb = ChestJoin.boxes(R[i], lo: R[i - (wide ? 1 : RW)], hi: R[i + (wide ? 1 : RW)], base: boxes,
                                                        tex: { texT[bi * 6 + $0] }) { boxes = jb }
                        }
                        for box in boxes {
                            let mn = [Int(box.x0), Int(box.y0), Int(box.z0)], mx = [Int(box.x1), Int(box.y1), Int(box.z1)]
                            for f in 0..<6 {
                                let axis = f / 2
                                let positive = f % 2 == 0
                                let a1 = (axis + 1) % 3, a2 = (axis + 2) % 3
                                if mx[a1] == mn[a1] || mx[a2] == mn[a2] { continue }   // zero-area face (thin planes)
                                let onBoundary = positive ? mx[axis] == 16 : mn[axis] == 0
                                let nb = R[i + offs[f]]
                                if onBoundary && opaqueT[Int(nb)] && !smoothOpen(i + offs[f]) && !(anyDmg && dmg[i + offs[f]] != nil) { continue }
                                let l: Int
                                if onBoundary {
                                    l = max(0, light(x + NT[f * 3], y + NT[f * 3 + 1], z + NT[f * 3 + 2]))
                                } else {
                                    l = Int(skyL[i]) | (Int(blkL[i]) << 4)
                                }
                                let layer = box.tex.isEmpty ? Int(texT[bi * 6 + f]) : Int(box.tex[f])
                                for k in 0..<4 {
                                    let ci = (f * 4 + k) * 3
                                    let px = CT[ci] == 1 ? mx[0] : mn[0]
                                    let py = CT[ci + 1] == 1 ? mx[1] : mn[1]
                                    let pz = CT[ci + 2] == 1 ? mx[2] : mn[2]
                                    // A slanted prism (a wall torch) samples its texture as if centred (columns 7-9), where
                                    // torch art is painted; at the wall's edge its sides came out blank (P86).
                                    let slant = box.leanX != 0 || box.leanZ != 0
                                    let (u, v) = slant ? faceUV(f, px + 7 - mn[0], py, pz + 7 - mn[2]) : faceUV(f, px, py, pz)
                                    let top = py == mx[1]
                                    let lx = top ? Int(box.leanX) : 0, lz = top ? Int(box.leanZ) : 0
                                    vert(isTrans, bx16 + px + lx, by16 + py, bz16 + pz + lz, f, tintV, u, v, layer, 3, l, false)
                                }
                            }
                        }
                        continue
                    }

                    let isLiquid = rt == rLiquid
                    if isLiquid && fluidNets { continue }                // (P338 step 5: drawn by the fluid's own surface above)
                    let fk = fkT[bi]
                    let liquidTop = isLiquid && fkT[Int(at(x, y + 1, z))] != fk
                    for f in 0..<6 {
                        let nb = R[i + offs[f]]
                        if opaqueT[Int(nb)] && !smoothOpen(i + offs[f]) && !(anyDmg && dmg[i + offs[f]] != nil) { continue }
                        if isLiquid {
                            if fkT[Int(nb)] == fk { continue }
                            // P175: no water (or lava) walls against natural ground (the shore plane above carries it on).
                            if smoothWater && fk != 0 && NT[f * 3 + 1] == 0 && natAt(i + offs[f]) { continue }
                            // P297 (b): nor against the air over low bank ground that carries the plane on.
                            if smoothWater && liquidTop && NT[f * 3 + 1] == 0 && nb == AIR && natAt(i + offs[f] - RL) { continue }
                            // Water round a solid-but-not-full block (fence, slab, stair, wall) behaves as if that block were
                            // waterlogged: no inner faces. Seen through the surface, the faces over a shipwreck's sunken
                            // rail fences were bright blue tiles (blind critic, run 417; --slice, run 420).
                            // Never the top face: a lily pad (or carpet, slab, trapdoor) resting on the surface left a
                            // hole in the water under it, showing the seabed through every pad (Quest playtest, v61).
                            if NT[f * 3 + 1] != 1 && collideT[Int(nb)] && layerT[Int(nb)] != translucent && fkT[Int(nb)] == 0 { continue }
                            // Ice in water is frozen water: no water face against it, or the flowing sides showed through
                            // the clear ice (Oct 11 Quest playtest P1).
                            if Mesher.iceT[Int(nb)] { continue }
                        } else if cullSameT[bi] && nb == b {
                            continue
                        } else if leafT[bi] && leafT[Int(nb)] {
                            leafy = true                       // meshes differently at lod 0 and 2
                            if lod != 0 { continue }           // far and mid: "fast" leaves, no faces inside the canopy
                            // Near: skip faces into a leaf cell that is itself closed in on all sides.
                            let j = i + offs[f]
                            var enclosed = true
                            for g in 0..<6 {
                                let q = R[j + offs[g]]
                                if !(opaqueT[Int(q)] || leafT[Int(q)]) { enclosed = false; break }
                            }
                            if enclosed { continue }
                        } else if farLeaf && far && leafT[Int(nb)] && opaqueT[bi] && rt == rCube {
                            continue                           // far: trunks and ground inside the "fast" canopy
                        }
                        let nx = NT[f * 3], ny = NT[f * 3 + 1], nz = NT[f * 3 + 2]
                        let ax = x + nx, ay = y + ny, az = z + nz
                        var flat = max(0, light(ax, ay, az))
                        // Far: pitch-dark cave walls can't be seen. Faces under water stay: a deep seabed gets no light,
                        // and without it far oceans showed the sky through the water.
                        // From a cave these missing faces let the surface's trees show through (Oct 11 Quest playtest P4):
                        // a dark eye's sight ends before the far ring (World.caveSight).
                        if Mesher.farDarkCull && far && flat == 0 && !isLiquid && fkT[Int(nb)] != 1 { continue }
                        // Far leaves: light in steps of 4 (sky 3/7/11/15), so a canopy's faces share keys and the greedy
                        // merge below joins them (Oct 10 taiga: leaves were two thirds of the far quads).
                        if farLeaf && far && leafT[bi] {
                            let sky = flat & 15, blk = flat >> 4
                            flat = (sky | 3) | ((blk == 0 ? 0 : blk | 3) << 4)
                        }
                        if isLiquid || rt != rCube || far {
                            for c in 0..<4 { lit[c] = flat; aos[c] = 3 }
                            if Mesher.waterDepthAO && fk == 1 && f != 3 && liquidTop {
                                // Quest: the water's depth at each corner of a surface cell in the AO bits (water never
                                // uses AO; sides get it too so the swell, damped on the shore by it, keeps them joined): the
                                // mean depth of the up-to-4 columns sharing the corner, dry ones 0. The Quest water
                                // shader turns it into absorption (see the bed in the shallows, dark deep water) and
                                // shoreline foam: it has no copy of the scene's depth like the Mac's Fancy water.
                                for c in 0..<4 {
                                    let ci = (f * 4 + c) * 3
                                    aos[c] = depthAO(x + CT[ci], y, z + CT[ci + 2])     // mean <= 0.75, < 2, < 5, 5+
                                }
                            }
                        } else {
                            for c in 0..<4 {
                                let ci = (f * 4 + c) * 3
                                let ox = nx == 0 ? CT[ci] * 2 - 1 : 0
                                let oy = ny == 0 ? CT[ci + 1] * 2 - 1 : 0
                                let oz = nz == 0 ? CT[ci + 2] * 2 - 1 : 0
                                let s1x: Int, s1y: Int, s1z: Int, s2x: Int, s2y: Int, s2z: Int
                                if nx != 0 { s1x = ax; s1y = ay + oy; s1z = az; s2x = ax; s2y = ay; s2z = az + oz }
                                else if ny != 0 { s1x = ax + ox; s1y = ay; s1z = az; s2x = ax; s2y = ay; s2z = az + oz }
                                else { s1x = ax + ox; s1y = ay; s1z = az; s2x = ax; s2y = ay + oy; s2z = az }
                                let o1 = occ(s1x, s1y, s1z), o2 = occ(s2x, s2y, s2z)
                                let oc = occ(ax + ox, ay + oy, az + oz)
                                aos[c] = (o1 == 1 && o2 == 1) ? 0 : 3 - o1 - o2 - oc
                                let l1 = light(s1x, s1y, s1z), l2 = light(s2x, s2y, s2z)
                                let lc = (l1 < 0 && l2 < 0) ? -1 : light(ax + ox, ay + oy, az + oz)
                                var sSum = flat & 15, bSum = flat >> 4, n = 1
                                if l1 >= 0 { sSum += l1 & 15; bSum += l1 >> 4; n += 1 }
                                if l2 >= 0 { sSum += l2 & 15; bSum += l2 >> 4; n += 1 }
                                if lc >= 0 { sSum += lc & 15; bSum += lc >> 4; n += 1 }
                                lit[c] = ((sSum + n / 2) / n) | (((bSum + n / 2) / n) << 4)
                            }
                        }
                        let flip = aos[0] + aos[2] < aos[1] + aos[3]
                        let layer = Int(texT[bi * 6 + f])
                        // P184 (Oct 13: "render distance struggles over water, where it should be cheapest"): far (LOD 1)
                        // still water tops whose four corners match (a source surface, same depth band and light) are
                        // collected and merged into big quads below, like the flat-lit cube faces: open sea was one quad
                        // per block out to the edge of the view.
                        if far && Mesher.mergeFarWater && isLiquid && fk == 1 && f == 2 && liquidTop && !smoothWater
                            && aos[0] == aos[1] && aos[1] == aos[2] && aos[2] == aos[3]
                            && lit[0] == lit[1] && lit[1] == lit[2] && lit[2] == lit[3]
                            && cornerDrop(x, y, z, 1) == 1 && cornerDrop(x + 1, y, z, 1) == 1
                            && cornerDrop(x, y, z + 1, 1) == 1 && cornerDrop(x + 1, y, z + 1, 1) == 1 {
                            if waterMask.isEmpty { waterMask = [Int32](repeating: 0, count: 16 * 256) }
                            waterMask[ly * 256 + lx + lz * 16] = Int32(1 + (aos[0] | ((lit[0] & 255) << 2) | (layer << 10)))
                            continue
                        }
                        // P239: the top of ice carries the overlay bit: the Quest's translucent shader mirrors the sky there.
                        let overlay = (tintB == 3 && f != 2 && f != 3) || (f == 2 && isTrans && iceT[bi])
                        let tintF = (tintB == 3 && f == 3) ? 0 : tintV
                        if bevel && bevelT[bi] && rt == rCube {
                            // Exposed sides of this block (the faces the loop draws); an edge between two of them is chamfered.
                            var ex = 0
                            for g in 0..<6 {
                                let j = i + offs[g]
                                let nb = Int(R[j])
                                // (Natural ground counts as contact here: a wall standing on it has no chamfer at its foot.)
                                if (!opaqueT[nb] || detT[nb] || leafBlob && leafT[nb]) && !(cullSameT[bi] && R[j] == b) { ex |= 1 << g }
                            }
                            let a = f >> 1, t1 = (a + 1) % 3, t2 = (a + 2) % 3
                            let sideMask = (3 << (t1 * 2)) | (3 << (t2 * 2))
                            if ex & sideMask != 0 {
                                bevelFace(f: f, ex: ex, bx16: bx16, by16: by16, bz16: bz16, layer: layer, tint: tintF, flat: flat, flip: flip, isTrans: isTrans)
                                continue
                            }
                        }
                        if !isLiquid && rt == rCube && aos[0] == aos[1] && aos[1] == aos[2] && aos[2] == aos[3]
                            && lit[0] == lit[1] && lit[1] == lit[2] && lit[2] == lit[3] {
                            // Slice along the face axis; a, bb = the next two axes (x->y,z  y->z,x  z->x,y).
                            let sl: Int, a: Int, bb: Int
                            switch f >> 1 {
                            case 0: sl = lx; a = ly; bb = lz
                            case 1: sl = ly; a = lz; bb = lx
                            default: sl = lz; a = lx; bb = ly
                            }
                            let key = layer | (tintF << 11) | ((overlay ? 1 : 0) << 13) | (aos[0] << 14) | ((lit[0] & 255) << 16) | ((isTrans ? 1 : 0) << 24) | ((curCut ? 1 : 0) << 25)
                            mask[(f * 16 + sl) * 256 + a + bb * 16] = Int32(key + 1)
                            continue
                        }
                        // Realistic world: a liquid sheet thins out to the ground at its edge (no block-high wall round
                        // spilled water); a side face left under a 1/16 sliver is dropped.
                        var pys = (0, 0, 0, 0)
                        var sliver = isLiquid && liquidTop && f != 2 && f != 3
                        for k in 0..<4 {
                            let ci = (f * 4 + k) * 3
                            var py = CT[ci + 1] * 16
                            if liquidTop && py == 16 {
                                py = smoothWater && fk == 1 && stepDown(x + CT[ci], y, z + CT[ci + 2]) ? 0
                                    : (detail && thinEdge(x + CT[ci], y, z + CT[ci + 2], fk) ? 1
                                       : 16 - 2 * cornerDrop(x + CT[ci], y, z + CT[ci + 2], fk))
                            }
                            if py > 1 { sliver = false }
                            switch k { case 0: pys.0 = py; case 1: pys.1 = py; case 2: pys.2 = py; default: pys.3 = py }
                        }
                        if sliver && detail { continue }
                        for k in 0..<4 {
                            let c = flip ? (k + 1) & 3 : k
                            let ci = (f * 4 + c) * 3
                            let px = CT[ci] * 16, pz = CT[ci + 2] * 16
                            let py = c == 0 ? pys.0 : (c == 1 ? pys.1 : (c == 2 ? pys.2 : pys.3))
                            let (u, v) = faceUV(f, px, py, pz)
                            let shadeIdx = isLiquid && fk == 2 ? 7 : f      // 7 = lava (flat bright, animated)
                            vert(isTrans, bx16 + px, by16 + py, bz16 + pz, shadeIdx, isLiquid ? (fk == 1 ? 3 : 0) : tintF, u, v, layer, aos[c], lit[c], overlay)
                        }
                    }
                }
            }
        }
        // R22: the plants of the section above's first row that stand on natural ground (see plantOnNatural), drawn here
        // 16 blocks up and lowered onto this section's drawn ground, as the main loop does for its own.
        if smooth && !far {
            let y = C0 + 16
            for z in C0..<(C0 + 16) { for x in C0..<(C0 + 16) {
                let i = x + z * RW + y * RL
                let b = R[i]
                guard b != AIR else { continue }
                let bi = Int(b)
                guard renderT[bi] == rCross, plantOnNatural(i), !(detailDraw && detT[bi]) else { continue }
                let lx = x - C0, lz = z - C0
                var dy16 = 0, dyTop = 0
                if sc.smValid {
                    var g = 15, j = i - RL
                    while g > 16 - SmoothTerrain.maxRelax && renderT[Int(R[j])] == rCross { g -= 1; j -= RL }
                    if let top = Mesher.smoothGroundTop(sc, lx, g, lz) {
                        let want: Float = (top - Float(g + 1)) * 16
                        (dy16, dyTop) = stackOffsets(i, below: 15 - g, max(-12, min(12, Int(want.rounded()))))
                    }
                }
                let l = Int(skyL[i]) | (Int(blkL[i]) << 4)
                let tintB = Int(tintT[bi])
                let tintV = tintB == 3 ? 1 : tintB
                let isTrans = layerT[bi] == translucent
                curCut = true
                let layer = Int(texT[bi * 6 + 2])
                let cs = Int(crossT[bi]), ci0 = (16 - cs) / 2
                let drift = swayOn && driftT[bi], foot = drift && driftFoot(i)
                let sway = drift || swayOn && swayT[bi]
                let aoC = drift ? 3 : (sway ? (x &* 5 &+ z &* 3 &+ y) % 3 : 3)
                var flipV = false
                if b == Mesher.pointedDrip {
                    var j = i, hangs = false
                    for _ in 0..<4 {
                        let up = R[j + RL]
                        if up == b { j += RL; continue }
                        hangs = opaqueT[Int(up)]; break
                    }
                    flipV = !hangs
                }
                let bx16 = lx * 16, by16 = 16 * 16 + dy16, bz16 = lz * 16
                for q in 0..<4 {
                    for k in 0..<4 {
                        let ci = (q * 4 + k) * 3
                        let up = PTab[ci + 1]
                        vert(isTrans, bx16 + ci0 + PTab[ci] * cs, by16 + (up == 1 ? dyTop - dy16 : 0) + up * cs, bz16 + ci0 + PTab[ci + 2] * cs,
                             6, tintV, cornerU[k], flipV ? 16 - cornerV[k] : cornerV[k], layer, aoC, l, sway && !(foot && up == 0))
                    }
                }
            } }
        }
        // Realistic world: trunks and limbs grown from the log graph (ShapeTrunks) and rounded organic objects
        // (ShapeOrganic), into the detail stream.
        if detailDraw {
            let ctx = DetailContext(out: det, cutOut: detCut, R: R, sky: skyL, blk: blkL, wx0: wox, wy0: sy * 16, wz0: woz,
                                    lod: lod, sc: sc, srcs: srcs, sy: sy, field: fieldOn ? n9 : nil)
            ShapeTrunks.emit(ctx)
            ShapeOrganic.emit(ctx)
            ShapeSpikes.emit(ctx)
            ShapeRails.emit(ctx)
        }
        // P338 step 8: free building pieces standing in this section (FreeBuild), in any world that has them.
        if !pieces.isEmpty {
            let ctx = DetailContext(out: det, cutOut: detCut, R: R, sky: skyL, blk: blkL, wx0: wox, wy0: sy * 16, wz0: woz,
                                    lod: lod, sc: sc, srcs: srcs, sy: sy, field: fieldOn ? n9 : nil)
            FreeBuild.emit(ctx, pieces)
        }
        if smooth {
            if leafBlob {
                let wo = detail ? SIMD3<Int>((chunk?.x ?? site?.cx ?? 0) * CS, sy * 16, (chunk?.z ?? site?.cz ?? 0) * CS) : nil
                // P283: far canopies (lod 1, past World.lodNear) are one solid shell, the blob's "fast leaves": the inner
                // shell behind the cut-out one doubled every canopy (leaf blobs were half of a Polygons world's quads) and
                // the alpha test cost the tiled GPU its early depth test; drawn solid, the leaf texture's clear texels show
                // their mid grey under the leaf tint, a darker green where the inner shell showed through.
                let farBlob = lod == 1 && Mesher.farLeaves
                smoothQuads(R, sc, dmg: dmg, sy: sy, leaves: true, shells: farBlob ? 1 : 2, world: wo) { x16, y16, z16, f, tint, layer, ao, l, ncode in
                    curCut = !farBlob
                    blobV += 1
                    vert(false, x16, y16, z16, f, tint, 31, ncode % 31, layer, ao, l, ncode >= 31)
                }
            }
        }
        // Merge the collected faces: grow each run along a, then along b while the whole row matches.
        for f in 0..<6 {
            let axis = f / 2
            let a1 = (axis + 1) % 3, a2 = (axis + 2) % 3
            for sl in 0..<16 {
                let base = (f * 16 + sl) * 256
                for bb in 0..<16 {
                    var a = 0
                    while a < 16 {
                        let k = mask[base + a + bb * 16]
                        if k == 0 { a += 1; continue }
                        var w = 1
                        while a + w < 16 && mask[base + a + w + bb * 16] == k { w += 1 }
                        var h = 1
                        grow: while bb + h < 16 {
                            for t in 0..<w where mask[base + a + t + (bb + h) * 16] != k { break grow }
                            h += 1
                        }
                        for hh in 0..<h { for t in 0..<w { mask[base + a + t + (bb + hh) * 16] = 0 } }
                        let key = Int(k) - 1
                        let layer = key & 2047, tint = (key >> 11) & 3, overlay = (key >> 13) & 1 == 1
                        let ao = (key >> 14) & 3, l = (key >> 16) & 255, trans = (key >> 24) & 1 == 1
                        curCut = (key >> 25) & 1 == 1
                        for c in 0..<4 {
                            let ci = (f * 4 + c) * 3
                            let ps = (sl + CT[ci + axis]) * 16
                            let pa = (CT[ci + a1] == 1 ? a + w : a) * 16
                            let pb = (CT[ci + a2] == 1 ? bb + h : bb) * 16
                            switch axis {
                            case 0: vert(trans, ps, pa, pb, f, tint, 31, 31, layer, ao, l, overlay)
                            case 1: vert(trans, pb, ps, pa, f, tint, 31, 31, layer, ao, l, overlay)
                            default: vert(trans, pa, pb, ps, f, tint, 31, 31, layer, ao, l, overlay)
                            }
                        }
                        a += w
                    }
                }
            }
        }
        // P184: the far still-water tops, merged per layer into rectangles 14/16 up their cells (the swell in chunk.vert
        // still moves their corners; projected UVs, u = v = 31).
        if !waterMask.isEmpty {
            curCut = false
            for ly in 0..<16 {
                let base = ly * 256
                for bb in 0..<16 {
                    var a = 0
                    while a < 16 {
                        let k = waterMask[base + a + bb * 16]
                        if k == 0 { a += 1; continue }
                        var w = 1
                        while a + w < 16 && waterMask[base + a + w + bb * 16] == k { w += 1 }
                        var h = 1
                        grow: while bb + h < 16 {
                            for t in 0..<w where waterMask[base + a + t + (bb + h) * 16] != k { break grow }
                            h += 1
                        }
                        for hh in 0..<h { for t in 0..<w { waterMask[base + a + t + (bb + hh) * 16] = 0 } }
                        let key = Int(k) - 1
                        let ao = key & 3, l = (key >> 2) & 255, layer = key >> 10
                        for c in 0..<4 {
                            let ci = (2 * 4 + c) * 3
                            let px = (CT[ci] == 1 ? a + w : a) * 16, pz = (CT[ci + 2] == 1 ? bb + h : bb) * 16
                            vert(true, px, ly * 16 + 14, pz, 2, 3, 31, 31, layer, ao, l, false)
                        }
                        Mesher.mergedWater += w * h
                        a += w
                    }
                }
            }
        }
        let solid = opq.count / 8
        var opaqueOut = [UInt32]()
        opaqueOut.reserveCapacity(opq.count + cut.count)
        opaqueOut.append(contentsOf: UnsafeBufferPointer(start: opq.ptr, count: opq.count))
        opaqueOut.append(contentsOf: UnsafeBufferPointer(start: cut.ptr, count: cut.count))
        var detailOut = [UInt32]()
        if det.count + detCut.count > 0 {
            detailOut.reserveCapacity(det.count + detCut.count)
            detailOut.append(contentsOf: UnsafeBufferPointer(start: det.ptr, count: det.count))
            detailOut.append(contentsOf: UnsafeBufferPointer(start: detCut.ptr, count: detCut.count))
        }
        return SectionMesh(opaque: opaqueOut, trans: trn.toArray(), light: Mesher.shared(lightOut), vis: connectivity(R, opaqueT, sc), solidQuads: solid, leafy: leafy,
                           detail: detailOut, detailSolid: det.count / DetailMesh.wordsPerQuad, groundQuads: groundV / 4, blobQuads: blobV / 4, naturalCubes: naturalCubes,
                           farSkip: farSkip, farGround: farGround)
    }

    // A uniform light array is swapped for the shared copy so loaded chunks don't each hold their own.
    static func shared(_ l: [UInt8]) -> [UInt8] {
        let v = l[0]
        guard v == 0 || v == 0xF0 else { return l }
        for x in l where x != v { return l }
        return v == 0 ? dark : fullSky
    }

    // P184: merge far still-water tops (environment BS_WATERMERGE=0 turns it off, for before/after measurements).
    static var mergeFarWater = ProcessInfo.processInfo.environment["BS_WATERMERGE"] != "0"
    static var mergedWater = 0                     // cells drawn inside merged water quads (counter; racy, a measure only)
    static let lilyPad: BlockID = Blocks.has("lily_pad") ? Blocks.id("lily_pad") : BlockID.max
    // Far (LOD 1) canopies: solid faces against leaves dropped, leaf light in steps of 4 so faces merge
    // (environment BS_FARLEAF=0 turns it off, for before/after measurements).
    static var farLeaves = ProcessInfo.processInfo.environment["BS_FARLEAF"] != "0"
    // P283: far field ground on the two-block lattice (SmoothTerrain.coarseGround); BS_FARGROUND=0 meshes it in full.
    static var farGround = ProcessInfo.processInfo.environment["BS_FARGROUND"] != "0"
    // P338 step 5: field worlds draw water and lava near the eye as their own field's surface (BS_FLUIDNETS=0: the cells).
    static var fluidNets = ProcessInfo.processInfo.environment["BS_FLUIDNETS"] != "0"
    // The twelve edges of a cell's corner cube (corner k: x = k & 1, y = (k >> 1) & 1, z = (k >> 2) & 1).
    static let cubeEdges: [(Int, Int)] = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]
    static var farDarkCull = true
    static let pointedDrip: BlockID = Blocks.has("pointed_dripstone") ? Blocks.id("pointed_dripstone") : 0
    static let iceT: [Bool] = (0..<Blocks.count).map { Blocks.key(BlockID($0)) == "ice" }
    static let leafT: [Bool] = (0..<Blocks.count).map { Blocks.key(BlockID($0)).hasSuffix("_leaves") }

    // Which section faces see each other through non-opaque cells (flood fill per open region).
    static func connectivity(_ R: UnsafeMutablePointer<BlockID>, _ opaqueT: [Bool], _ sc: MeshScratch) -> UInt64 {
        let seen = sc.seen
        seen.initialize(repeating: false, count: 4096)
        let stack = sc.stack
        var vis: UInt64 = 0
        for start in 0..<4096 where !seen[start] {
            let sx = start & 15, sz = (start >> 4) & 15, sy = start >> 8
            if opaqueT[Int(R[(sx + C0) + (sz + C0) * RW + (sy + C0) * RL])] { seen[start] = true; continue }
            var faces = 0
            seen[start] = true
            var top = 0
            stack[top] = Int32(start); top += 1
            while top > 0 {
                top -= 1
                let i = Int(stack[top])
                let x = i & 15, z = (i >> 4) & 15, y = i >> 8
                if x == 15 { faces |= 1 }; if x == 0 { faces |= 2 }
                if y == 15 { faces |= 4 }; if y == 0 { faces |= 8 }
                if z == 15 { faces |= 16 }; if z == 0 { faces |= 32 }
                let r0 = (x + C0) + (z + C0) * RW + (y + C0) * RL
                for d in 0..<6 {
                    let ni: Int, ri: Int
                    switch d {
                    case 0: if x == 15 { continue }; ni = i + 1; ri = r0 + 1
                    case 1: if x == 0 { continue }; ni = i - 1; ri = r0 - 1
                    case 2: if y == 15 { continue }; ni = i + 256; ri = r0 + RL
                    case 3: if y == 0 { continue }; ni = i - 256; ri = r0 - RL
                    case 4: if z == 15 { continue }; ni = i + 16; ri = r0 + RW
                    default: if z == 0 { continue }; ni = i - 16; ri = r0 - RW
                    }
                    if seen[ni] { continue }
                    seen[ni] = true                     // each cell is pushed at most once: 4096 slots suffice
                    if opaqueT[Int(R[ri])] { continue }
                    stack[top] = Int32(ni); top += 1
                }
            }
            for a in 0..<6 where faces & (1 << a) != 0 { for b in 0..<6 where faces & (1 << b) != 0 { vis |= 1 << UInt64(a * 6 + b) } }
            if vis == (1 << 36) - 1 { break }
        }
        return vis
    }
}

// Growable buffer of trivial values (no copy-on-write checks on append).
final class GrowBuf<T> {
    private(set) var ptr: UnsafeMutablePointer<T>
    private(set) var cap: Int
    var count = 0
    init(_ cap: Int) { self.cap = cap; ptr = UnsafeMutablePointer<T>.allocate(capacity: cap) }
    deinit { ptr.deallocate() }
    @inline(__always) func append(_ v: T) {
        if count == cap { grow() }
        ptr[count] = v
        count += 1
    }
    private func grow() {
        let n = cap * 2
        let p = UnsafeMutablePointer<T>.allocate(capacity: n)
        p.moveInitialize(from: ptr, count: count)
        ptr.deallocate()
        ptr = p; cap = n
    }
    func toArray() -> [T] { Array(UnsafeBufferPointer(start: ptr, count: count)) }
}

// Per-thread meshing scratch memory (kept in the thread dictionary; worker threads reuse theirs).
final class MeshScratch {
    let region = UnsafeMutablePointer<BlockID>.allocate(capacity: Mesher.RL * Mesher.RH)
    let sky = UnsafeMutablePointer<UInt8>.allocate(capacity: Mesher.RL * Mesher.RH)
    let blk = UnsafeMutablePointer<UInt8>.allocate(capacity: Mesher.RL * Mesher.RH)
    let heights = UnsafeMutablePointer<Int>.allocate(capacity: Mesher.RL)
    let mask = UnsafeMutablePointer<Int32>.allocate(capacity: 6 * 16 * 256)
    let groundMerge = GroundMerge()
    let lit = UnsafeMutablePointer<Int>.allocate(capacity: 4)
    let aos = UnsafeMutablePointer<Int>.allocate(capacity: 4)
    let seen = UnsafeMutablePointer<Bool>.allocate(capacity: 4096)
    let stack = UnsafeMutablePointer<Int32>.allocate(capacity: 4096)
    let queue = GrowBuf<Int32>(1 << 16)
    let opq = GrowBuf<UInt32>(1 << 14), cut = GrowBuf<UInt32>(1 << 12), trn = GrowBuf<UInt32>(1 << 12)
    let det = GrowBuf<UInt32>(1 << 12), detCut = GrowBuf<UInt32>(1 << 10)     // realistic world: DetailMesh vertices
    // Smooth terrain (SmoothTerrain.swift): solid flags, density, dual vertices (xyz, light | ao << 8, normal, pinned,
    // relaxation scratch), each with SmoothTerrain.maxRelax blocks of ring past a section's own.
    static let smN0 = 20 + 2 * SmoothTerrain.maxRelax, smM0 = 18 + 2 * SmoothTerrain.maxRelax, smK0 = 17 + 2 * SmoothTerrain.maxRelax
    let smS = UnsafeMutablePointer<UInt8>.allocate(capacity: MeshScratch.smN0 * MeshScratch.smN0 * MeshScratch.smN0)
    let smD = UnsafeMutablePointer<Float>.allocate(capacity: MeshScratch.smM0 * MeshScratch.smM0 * MeshScratch.smM0)
    let smV = UnsafeMutablePointer<Float>.allocate(capacity: MeshScratch.smK0 * MeshScratch.smK0 * MeshScratch.smK0 * 3)
    let smL = UnsafeMutablePointer<Int32>.allocate(capacity: MeshScratch.smK0 * MeshScratch.smK0 * MeshScratch.smK0)
    let smN = UnsafeMutablePointer<Float>.allocate(capacity: MeshScratch.smK0 * MeshScratch.smK0 * MeshScratch.smK0 * 3)
    let smQ = UnsafeMutablePointer<UInt8>.allocate(capacity: MeshScratch.smK0 * MeshScratch.smK0 * MeshScratch.smK0)
    let smR = UnsafeMutablePointer<Float>.allocate(capacity: MeshScratch.smK0 * MeshScratch.smK0 * MeshScratch.smK0 * 3)
    // P142: which samples agree with the generator's fields (0 unknown, 1 yes, 2 no), and the fields themselves.
    let smF = UnsafeMutablePointer<UInt8>.allocate(capacity: MeshScratch.smN0 * MeshScratch.smN0 * MeshScratch.smN0)
    let smM = UnsafeMutablePointer<Int32>.allocate(capacity: MeshScratch.smK0 * MeshScratch.smK0 * MeshScratch.smK0)   // vertex material
    let dens = UnsafeMutablePointer<Int8>.allocate(capacity: Mesher.RL * Mesher.RH)    // PG1: the region's field densities
    lazy var field = SmoothField()
    var smValid = false             // P175: smV/smL hold the section's ground surface (Mesher.smoothGroundTop)

    deinit {
        region.deallocate(); sky.deallocate(); blk.deallocate(); heights.deallocate(); mask.deallocate()
        lit.deallocate(); aos.deallocate(); seen.deallocate(); stack.deallocate()
        smS.deallocate(); smD.deallocate(); smV.deallocate(); smL.deallocate(); smN.deallocate(); smQ.deallocate(); smR.deallocate(); smF.deallocate(); smM.deallocate(); dens.deallocate()
    }

    static var current: MeshScratch {
        let d = Thread.current.threadDictionary
        if let s = d["blocksmith.meshScratch"] as? MeshScratch { return s }
        let s = MeshScratch()
        d["blocksmith.meshScratch"] = s
        return s
    }
}
