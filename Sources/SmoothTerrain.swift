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
// Quads use the existing vertex format: the dominant normal axis picks the face (texture, shade) and u = v = 31
// projects the texture from the position, so no shader changes on Mac (Fast, Fancy) or Quest.
// A section owns the dual cells 0...16 of its own corner (vertices 0.5...17.5 blocks, never negative in the
// unsigned 1/16 position bits), so it meshes quads that touch its +x/+y/+z neighbours' first block row.
enum SmoothTerrain {
    // Settings (Video: Smooth Terrain), or `--smooth` / `--cubic` on the command line (harness, bench, smoke).
    static var enabled: Bool = {
        let a = CommandLine.arguments
        if a.contains("--cubic") { return false }
        return a.contains("--smooth") || Settings.shared.smoothTerrain
    }()

    static let naturalNames: Set<String> = [
        "stone", "dirt", "grass_block", "snowy_grass_block", "coarse_dirt", "rooted_dirt", "podzol", "mycelium", "mud",
        "clay", "sand", "red_sand", "gravel", "sandstone", "red_sandstone", "snow_block", "deepslate", "emberslate",
        "andesite", "diorite", "granite", "tuff", "calcite", "dripstone_block", "moss_block", "smooth_basalt",
        "terracotta", "netherrack", "soul_soil", "blackstone", "end_stone",
    ]
    // Per block state: meshes as smooth ground.
    static let natural: [Bool] = (0..<Blocks.count).map { i in
        let id = BlockID(i)
        guard Blocks.opaque[i] && Blocks.render[i] == RenderType.cube.rawValue else { return false }
        let n = Blocks.key(id)
        if naturalNames.contains(n) || n.hasSuffix("_ore") { return true }
        return n.hasSuffix("_terracotta") && !n.contains("glazed")
    }

    // Turns the mode on/off and remeshes everything loaded.
    static func set(_ on: Bool, world: World?) {
        guard on != enabled else { return }
        enabled = on
        world?.remeshAll()
    }
}

extension Mesher {
    // Does the +x / +z / +y boundary row of an all-air section's 17^3 block range hold natural ground? Then the
    // section still owns smooth quads there.
    static func smoothEdgeNatural(_ srcs: [[BlockID]], sy: Int) -> Bool {
        let nat = SmoothTerrain.natural
        for ly in 0...16 {
            let wy = sy * 16 + ly
            if wy >= CH { break }
            for lz in 0...16 {
                for lx in 0...16 where lx == 16 || lz == 16 || ly == 16 {
                    let src = srcs[(lx == 16 ? 2 : 1) + (lz == 16 ? 2 : 1) * 3]
                    let si = (lx & 15) + (lz & 15) * CS + wy * CSQ
                    if si < src.count && nat[Int(src[si])] { return true }
                }
            }
        }
        return false
    }

    // Smooth quads for the section whose local 0 is region (C0, C0, C0). `emit` takes position (1/16 block,
    // section-local), face, tint, layer, ao, packed light, overlay.
    static func smoothQuads(_ R: UnsafeMutablePointer<BlockID>, _ sc: MeshScratch, dmg: [Int: UInt8],
                            _ emit: (Int, Int, Int, Int, Int, Int, Int, Int, Bool) -> Void) {
        let nat = SmoothTerrain.natural, opaqueT = Blocks.opaque, aoT = Blocks.aoOcc, loT = Blocks.lightOpaque
        let texT = Blocks.tex, tintT = Blocks.tint
        let skyL = sc.sky, blkL = sc.blk
        func ri(_ x: Int, _ y: Int, _ z: Int) -> Int { (x + C0) + (z + C0) * RW + (y + C0) * RL }

        // Anything natural in the owned 17^3 block range?
        var any = false
        scan: for y in 0...16 { for z in 0...16 { for x in 0...16 where nat[Int(R[ri(x, y, z)])] { any = true; break scan } } }
        if !any { return }

        // Solid flags for blocks -1...18 (index +1, 20 per axis).
        let N = 20, NN = N * N
        let S = sc.smS
        for y in 0..<N { for z in 0..<N { for x in 0..<N {
            S[x + z * N + y * NN] = opaqueT[Int(R[ri(x - 1, y - 1, z - 1)])] ? 1 : 0
        } } }
        // Density for blocks 0...17 (18 per axis): half the block, half its 3x3x3 mean.
        let M = 18, MM = M * M
        let D = sc.smD
        for y in 0..<M { for z in 0..<M { for x in 0..<M {
            var s = 0
            for dy in 0...2 { for dz in 0...2 {
                let row = x + (z + dz) * N + (y + dy) * NN
                s += Int(S[row]) + Int(S[row + 1]) + Int(S[row + 2])
            } }
            let selfS = Float(S[(x + 1) + (z + 1) * N + (y + 1) * NN])
            D[x + z * M + y * MM] = 0.5 * selfS + Float(s) / 54
        } } }

        // Dual cell vertices 0...16 (17 per axis): position (blocks, section-local), light, ao.
        let K = 17, KK = K * K
        let VP = sc.smV, VL = sc.smL
        for cy in 0..<K { for cz in 0..<K { for cx in 0..<K {
            let vi = cx + cz * K + cy * KK
            var mask = 0
            for c in 0..<8 where S[(cx + 1 + (c & 1)) + (cz + 1 + (c >> 2)) * N + (cy + 1 + ((c >> 1) & 1)) * NN] != 0 { mask |= 1 << c }
            if mask == 0 || mask == 255 { VL[vi] = -1; continue }
            var sum = SIMD3<Float>(0, 0, 0)
            var n: Float = 0
            for c in 0..<8 {
                for sh in 0..<3 where (c >> sh) & 1 == 0 {
                    let bit = 1 << sh
                    let c2 = c | bit
                    if (mask >> c & 1) == (mask >> c2 & 1) { continue }
                    let d1 = D[(cx + (c & 1)) + (cz + (c >> 2)) * M + (cy + ((c >> 1) & 1)) * MM]
                    let d2 = D[(cx + (c2 & 1)) + (cz + (c2 >> 2)) * M + (cy + ((c2 >> 1) & 1)) * MM]
                    let t = (d1 - 0.5) / (d1 - d2)
                    let p1 = SIMD3<Float>(Float(c & 1), Float((c >> 1) & 1), Float(c >> 2))
                    let p2 = SIMD3<Float>(Float(c2 & 1), Float((c2 >> 1) & 1), Float(c2 >> 2))
                    sum += p1 + (p2 - p1) * t
                    n += 1
                }
            }
            let p = sum / n + SIMD3<Float>(Float(cx) + 0.5, Float(cy) + 0.5, Float(cz) + 0.5)
            VP[vi * 3] = p.x; VP[vi * 3 + 1] = p.y; VP[vi * 3 + 2] = p.z
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
            let ao = max(0, 3 - max(0, occ - 4))
            VL[vi] = Int32(l | ao << 8)
        } } }

        // Quads: block p and its +axis neighbour q, one solid (natural, not chipped) and one open.
        var corner = [Int](repeating: 0, count: 4)
        var pts = [SIMD3<Float>](repeating: .zero, count: 4)
        for y in 0...16 { for z in 0...16 { for x in 0...16 {
            let p = SIMD3<Int>(x, y, z)
            for a in 0..<3 {
                let b = (a + 1) % 3, c = (a + 2) % 3
                if p[a] > 15 || p[b] < 1 || p[c] < 1 { continue }
                var q = p
                q[a] += 1
                let sp = S[(p[0] + 1) + (p[2] + 1) * N + (p[1] + 1) * NN] != 0
                let sq = S[(q[0] + 1) + (q[2] + 1) * N + (q[1] + 1) * NN] != 0
                if sp == sq { continue }
                let s = sp ? p : q
                let si = ri(s[0], s[1], s[2])
                let id = Int(R[si])
                if !nat[id] || dmg[si] != nil { continue }
                // Dual cells around the edge, counter-clockwise seen from the open side.
                for k in 0..<4 {
                    var d = p
                    let kk = sp ? k : 3 - k
                    d[b] -= (kk == 0 || kk == 3) ? 1 : 0
                    d[c] -= (kk == 0 || kk == 1) ? 1 : 0
                    let vi = d[0] + d[2] * K + d[1] * KK
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
                let tintB = Int(tintT[id])
                let texF = tintB == 3 ? (nrm.y > 0.2 * len ? 2 : 3) : f
                let layer = Int(texT[id * 6 + texF])
                let overlay = false
                let tint = tintB == 3 ? (texF == 2 ? 1 : 0) : tintB
                let a0 = Int(VL[corner[0]]) >> 8, a1 = Int(VL[corner[1]]) >> 8
                let a2 = Int(VL[corner[2]]) >> 8, a3 = Int(VL[corner[3]]) >> 8
                let flip = a0 + a2 < a1 + a3
                for k in 0..<4 {
                    let cc = flip ? (k + 1) & 3 : k
                    let v = Int(VL[corner[cc]])
                    let pt = pts[cc] * 16
                    emit(Int(pt.x.rounded()), Int(pt.y.rounded()), Int(pt.z.rounded()), f, tint, layer, v >> 8, v & 255, overlay)
                }
            }
        } } }
    }
}
