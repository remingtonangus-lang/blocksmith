import Foundation

struct SectionMesh {
    var opaque: [UInt32]
    var trans: [UInt32]
    var light: [UInt8]?     // 4096 values (sky << 4 | block) for the section, nil if not computed
}

// Builds one 16x16x16 section. The 3x3 chunk neighbourhood (n9, index cx+cz*3, centre 4) and its
// heightmaps (h9) are gathered into a 48x48x48 region around the section: light travels at most 15
// blocks, so every source that can reach the section (or the 1-block border faces sample) is inside,
// and skylight above the heightmap is known directly. Nothing about light is stored between meshes
// except the section's own result (used for mob spawning).
//
// Vertex = 2 x UInt32 (positions/uv in 1/16 block):
//   w0: x(9) y(9)<<9 z(9)<<18 shade(3)<<27 tint(2)<<30        tint: 0 none, 1 grass, 2 foliage, 3 water
//   w1: u(5) v(5)<<5 layer(10)<<10 ao(2)<<20 sky(4)<<22 block(4)<<26 overlay(1)<<30
// 4 verts per quad (corners 0..3 CCW seen from outside), drawn with a shared index buffer.
enum Mesher {
    static let RW = 48
    static let RH = 48
    static let RL = RW * RW
    static let C0 = 16          // region coordinate of the section's local 0 (x, y and z)

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

    static func flood(_ L: inout [UInt8], _ q: inout [Int32], _ R: [BlockID], _ lo: [Bool]) {
        var head = 0
        while head < q.count {
            let i = Int(q[head])
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

    static func computeLight(_ R: [BlockID], _ heights: [Int], y0: Int) -> (sky: [UInt8], blk: [UInt8]) {
        let lo = Blocks.lightOpaque, emitT = Blocks.emit
        var sky = [UInt8](repeating: 0, count: RL * RH)
        var blk = [UInt8](repeating: 0, count: RL * RH)
        var q = [Int32]()
        q.reserveCapacity(1 << 14)
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
        flood(&sky, &q, R, lo)

        q.removeAll(keepingCapacity: true)
        for i in 0..<(RL * RH) {
            let e = emitT[Int(R[i])]
            if e > 0 { blk[i] = e; q.append(Int32(i)) }
        }
        if !q.isEmpty { flood(&blk, &q, R, lo) }
        return (sky, blk)
    }

    // MARK: Build

    static func buildSection(_ n9: [[BlockID]], _ h9: [[Int16]], sy: Int) -> SectionMesh {
        let renderT = Blocks.render, opaqueT = Blocks.opaque, aoT = Blocks.aoOcc, loT = Blocks.lightOpaque
        let cullSameT = Blocks.cullSame, texT = Blocks.tex, tintT = Blocks.tint, levelT = Blocks.fluidLevel, fkT = Blocks.fluidKind
        let layerT = Blocks.layer, boxesT = Blocks.boxes
        let CT = cornerTable, NT = normalTable, PTab = plantTable
        let rCube = RenderType.cube.rawValue, rCross = RenderType.cross.rawValue
        let rLiquid = RenderType.liquid.rawValue, rModel = RenderType.model.rawValue, rNone = RenderType.none.rawValue
        let rConnect = RenderType.connect.rawValue, connT = Blocks.connectKind
        let rWire = RenderType.wire.rawValue, rsK = Redstone.kinds, gbT = Blocks.groupBase
        let translucent = RenderLayer.translucent.rawValue
        let y0 = sy * 16 - 16

        // Quick exit: an all-air section has no geometry of its own.
        let centre = n9[4]
        var anyBlock = false
        let base = sy * 16 * CSQ
        for i in base..<(base + 16 * CSQ) where centre[i] != AIR { anyBlock = true; break }
        if !anyBlock { return SectionMesh(opaque: [], trans: [], light: nil) }

        // Gather the region: index = x + z*RW + ry*RL, world y = y0 + ry.
        var region = [BlockID](repeating: AIR, count: RL * RH)
        for ry in 0..<RH {
            let y = y0 + ry
            if y < 0 {
                for i in 0..<RL { region[ry * RL + i] = BEDROCK }
                continue
            }
            if y >= CH { continue }
            for cz in 0..<3 {
                for cx in 0..<3 {
                    let src = n9[cx + cz * 3]
                    for z in 0..<CS {
                        let si = z * CS + y * CSQ
                        let di = cx * CS + (cz * CS + z) * RW + ry * RL
                        for x in 0..<CS { region[di + x] = src[si + x] }
                    }
                }
            }
        }
        let R = region

        // Fully buried section (all opaque, and so is the 1-block shell around it): nothing visible.
        var buried = true
        outer: for ry in (C0 - 1)...(C0 + 16) {
            for z in (C0 - 1)...(C0 + 16) {
                for x in (C0 - 1)...(C0 + 16) {
                    let edges = (ry == C0 - 1 || ry == C0 + 16 ? 1 : 0) + (z == C0 - 1 || z == C0 + 16 ? 1 : 0) + (x == C0 - 1 || x == C0 + 16 ? 1 : 0)
                    if edges >= 2 { continue }
                    if !opaqueT[Int(R[x + z * RW + ry * RL])] { buried = false; break outer }
                }
            }
        }
        if buried { return SectionMesh(opaque: [], trans: [], light: [UInt8](repeating: 0, count: 4096)) }

        var heights = [Int](repeating: -1, count: RL)
        for cz in 0..<3 {
            for cx in 0..<3 {
                let h = h9[cx + cz * 3]
                for z in 0..<CS { for x in 0..<CS { heights[cx * CS + x + (cz * CS + z) * RW] = Int(h[x + z * CS]) } }
            }
        }
        let (skyL, blkL) = computeLight(R, heights, y0: y0)

        var lightOut = [UInt8](repeating: 0, count: 4096)
        for ly in 0..<16 {
            for lz in 0..<16 {
                for lx in 0..<16 {
                    let ri = (lx + C0) + (lz + C0) * RW + (ly + C0) * RL
                    lightOut[lx + lz * 16 + ly * 256] = (skyL[ri] << 4) | blkL[ri]
                }
            }
        }

        var opq = [UInt32]()
        opq.reserveCapacity(8192)
        var trn = [UInt32]()
        let offs = [1, -1, RL, -RL, RW, -RW]

        func at(_ x: Int, _ y: Int, _ z: Int) -> BlockID { R[x + z * RW + y * RL] }
        func occ(_ x: Int, _ y: Int, _ z: Int) -> Int { aoT[Int(R[x + z * RW + y * RL])] ? 1 : 0 }
        // Packed sky | blk << 4, or -1 for solid cells (excluded from smoothing).
        func light(_ x: Int, _ y: Int, _ z: Int) -> Int {
            let i = x + z * RW + y * RL
            if loT[Int(R[i])] { return -1 }
            return Int(skyL[i]) | (Int(blkL[i]) << 4)
        }
        func vert(_ trans: Bool, _ x16: Int, _ y16: Int, _ z16: Int, _ shade: Int, _ tint: Int,
                  _ u: Int, _ v: Int, _ layer: Int, _ ao: Int, _ l: Int, _ overlay: Bool) {
            let w0 = UInt32(x16) | (UInt32(y16) << 9) | (UInt32(z16) << 18) | (UInt32(shade) << 27) | (UInt32(tint) << 30)
            let w1 = UInt32(u) | (UInt32(v) << 5) | (UInt32(layer) << 10) | (UInt32(ao) << 20)
                | (UInt32(l & 15) << 22) | (UInt32((l >> 4) & 15) << 26) | (overlay ? (1 << 30) : 0)
            if trans { trn.append(w0); trn.append(w1) } else { opq.append(w0); opq.append(w1) }
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

        var lit = [Int](repeating: 0, count: 4)
        var aos = [Int](repeating: 3, count: 4)
        for ly in 0..<16 {
            let y = ly + C0
            for z in C0..<(C0 + 16) {
                for x in C0..<(C0 + 16) {
                    let i = x + z * RW + y * RL
                    let b = R[i]
                    if b == AIR { continue }
                    let bi = Int(b)
                    let rt = renderT[bi]
                    if rt == rNone { continue }
                    let lx = x - C0, lz = z - C0
                    let bx16 = lx * 16, by16 = ly * 16, bz16 = lz * 16
                    let tintB = Int(tintT[bi])
                    let tintV = tintB == 3 ? 1 : tintB
                    let isTrans = layerT[bi] == translucent

                    if rt == rCross {
                        let l = Int(skyL[i]) | (Int(blkL[i]) << 4)
                        let layer = Int(texT[bi * 6 + 2])
                        for q in 0..<4 {
                            for k in 0..<4 {
                                let ci = (q * 4 + k) * 3
                                vert(isTrans, bx16 + PTab[ci] * 16, by16 + PTab[ci + 1] * 16, bz16 + PTab[ci + 2] * 16,
                                     6, tintV, cornerU[k], cornerV[k], layer, 3, l, false)
                            }
                        }
                        continue
                    }

                    if rt == rWire {
                        // Redstone dust: a cross when alone, lines toward what it connects to, and
                        // strips up the side of blocks it climbs.
                        func connects(_ n: BlockID, _ d: Int) -> Bool {
                            let st = Int(n - gbT[Int(n)])
                            switch rsK[Int(n)] {
                            case .wire, .torch, .block, .lever, .button, .plate, .weightedPlate, .target, .daylight, .comparator: return true
                            case .repeater: return ((st & 3) + 2) / 2 == d / 2
                            case .observer: return st % 6 == d
                            default: return false
                            }
                        }
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
                        if count == 0 { conn = [true, true, true, true] }
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

                    if rt == rModel || rt == rConnect {
                        var boxes = boxesT[bi]
                        if rt == rConnect {
                            let ck = connT[bi]
                            boxes = BlockRegistry.connectBoxes(ck, n: Blocks.connects(ck, R[i - RW]), s: Blocks.connects(ck, R[i + RW]),
                                                               w: Blocks.connects(ck, R[i - 1]), e: Blocks.connects(ck, R[i + 1]), collision: false)
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
                                if onBoundary && opaqueT[Int(nb)] { continue }
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
                                    let (u, v) = faceUV(f, px, py, pz)
                                    vert(isTrans, bx16 + px, by16 + py, bz16 + pz, f, tintV, u, v, layer, 3, l, false)
                                }
                            }
                        }
                        continue
                    }

                    let isLiquid = rt == rLiquid
                    let fk = fkT[bi]
                    let liquidTop = isLiquid && fkT[Int(at(x, y + 1, z))] != fk
                    for f in 0..<6 {
                        let nb = R[i + offs[f]]
                        if opaqueT[Int(nb)] { continue }
                        if isLiquid {
                            if fkT[Int(nb)] == fk { continue }
                        } else if cullSameT[bi] && nb == b {
                            continue
                        }
                        let nx = NT[f * 3], ny = NT[f * 3 + 1], nz = NT[f * 3 + 2]
                        let ax = x + nx, ay = y + ny, az = z + nz
                        let flat = max(0, light(ax, ay, az))
                        if isLiquid || rt != rCube {
                            for c in 0..<4 { lit[c] = flat; aos[c] = 3 }
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
                        let overlay = tintB == 3 && f != 2 && f != 3
                        let tintF = (tintB == 3 && f == 3) ? 0 : tintV
                        for k in 0..<4 {
                            let c = flip ? (k + 1) & 3 : k
                            let ci = (f * 4 + c) * 3
                            let px = CT[ci] * 16, pz = CT[ci + 2] * 16
                            var py = CT[ci + 1] * 16
                            if liquidTop && py == 16 { py = 16 - 2 * cornerDrop(x + CT[ci], y, z + CT[ci + 2], fk) }
                            let (u, v) = faceUV(f, px, py, pz)
                            let shadeIdx = isLiquid && fk == 2 ? 7 : f      // 7 = lava (flat bright, animated)
                            vert(isTrans, bx16 + px, by16 + py, bz16 + pz, shadeIdx, isLiquid ? (fk == 1 ? 3 : 0) : tintF, u, v, layer, aos[c], lit[c], overlay)
                        }
                    }
                }
            }
        }
        return SectionMesh(opaque: opq, trans: trn, light: lightOut)
    }
}
