import Foundation

struct MeshData {
    var opaque: [UInt32]
    var water: [UInt32]
    var minY: Int
    var maxY: Int
}

// Builds packed vertex data for one chunk from a 3x3 neighborhood of chunk arrays.
// Lighting (sky + block) is flood-filled over the whole 48x48 neighbourhood first: light travels
// at most 15 blocks, so every source that can reach the centre chunk (or its 1-block border that
// faces sample) lies inside it. Nothing about light is stored; remeshing recomputes it.
// Vertex = 2 x UInt32 (8 bytes):
//   w0: x(5) y(9) z(5) face(3) corner(2) ao(2) waterDrop(3)   (drop = eighths of a block, water tops)
//   w1: textureLayer(8) skyLight(4) blockLight(4)      (smooth lighting: per-vertex values)
enum Mesher {
    static let RW = CS * 3      // region width (3 chunks)
    static let RL = RW * RW     // region layer size
    static let C0 = CS          // region coordinate of the centre chunk's local x/z = 0

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
    // Plants: two diagonal planes, each emitted in both windings so back-face culling keeps one.
    static let plantTable: [Int] = [
        0,0,0, 1,0,1, 1,1,1, 0,1,0,
        1,0,1, 0,0,0, 0,1,0, 1,1,1,
        1,0,0, 0,0,1, 0,1,1, 1,1,0,
        0,0,1, 1,0,0, 1,1,0, 0,1,1,
    ]
    static let plantFace: UInt32 = 6 // face slot 6 in the vertex format = "plant" (own shade value)

    // MARK: Light

    // Breadth-first relaxation: each step into a non-solid cell costs 1 level.
    static func flood(_ L: inout [UInt8], _ q: inout [Int32], _ R: [UInt8], _ lo: [Bool]) {
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
                case 2: if y == CH - 1 { continue }; j = i + RL
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

    static func computeLight(_ R: [UInt8]) -> (sky: [UInt8], blk: [UInt8]) {
        let skyStop = Blocks.sky, lo = Blocks.lightOpaque, emitT = Blocks.emit
        var sky = [UInt8](repeating: 0, count: RL * CH)
        var blk = [UInt8](repeating: 0, count: RL * CH)
        var top = [Int](repeating: -1, count: RL)
        // Direct skylight: 15 straight down until the first block that stops it.
        for c in 0..<RL {
            var y = CH - 1
            while y >= 0 && !skyStop[Int(R[c + y * RL])] {
                sky[c + y * RL] = 15
                y -= 1
            }
            top[c] = y
        }
        // Seeds: the lowest sky cell of each column (spreads down into leaves/water) and the sky
        // cells beside taller neighbour columns (spread sideways under overhangs and canopies).
        var q = [Int32]()
        q.reserveCapacity(1 << 16)
        for z in 0..<RW {
            for x in 0..<RW {
                let c = x + z * RW
                let t = top[c]
                if t >= CH - 1 { continue }
                q.append(Int32(c + (t + 1) * RL))
                var hi = t
                if x > 0 { hi = max(hi, top[c - 1]) }
                if x < RW - 1 { hi = max(hi, top[c + 1]) }
                if z > 0 { hi = max(hi, top[c - RW]) }
                if z < RW - 1 { hi = max(hi, top[c + RW]) }
                if hi > t + 1 {
                    for y in (t + 2)...min(hi, CH - 1) { q.append(Int32(c + y * RL)) }
                }
            }
        }
        flood(&sky, &q, R, lo)

        q.removeAll(keepingCapacity: true)
        for i in 0..<(RL * CH) {
            let e = emitT[Int(R[i])]
            if e > 0 { blk[i] = e; q.append(Int32(i)) }
        }
        if !q.isEmpty { flood(&blk, &q, R, lo) }
        return (sky, blk)
    }

    // MARK: Mesh

    static func build(_ n9: [[UInt8]]) -> MeshData {
        let kindT = Blocks.kind, opaqueT = Blocks.opaque, aoT = Blocks.aoOcc, loT = Blocks.lightOpaque
        let cullSameT = Blocks.cullSame, texT = Blocks.tex
        let CT = cornerTable, NT = normalTable, PTab = plantTable
        let liquid = BlockKind.liquid.rawValue, plant = BlockKind.plant.rawValue

        // Gather the 3x3 neighbourhood into one region array: index = x + z*RW + y*RL.
        var region = [UInt8](repeating: AIR, count: RL * CH)
        for cz in 0..<3 {
            for cx in 0..<3 {
                let src = n9[cx + cz * 3]
                for y in 0..<CH {
                    for z in 0..<CS {
                        let si = z * CS + y * CSQ
                        let di = cx * CS + (cz * CS + z) * RW + y * RL
                        for x in 0..<CS { region[di + x] = src[si + x] }
                    }
                }
            }
        }
        let R = region
        let (skyL, blkL) = computeLight(R)

        var yMax = 0
        for z in C0..<(C0 + CS) {
            for x in C0..<(C0 + CS) {
                var y = CH - 1
                while y > 0 && R[x + z * RW + y * RL] == AIR { y -= 1 }
                if y > yMax { yMax = y }
            }
        }

        var opq = [UInt32]()
        opq.reserveCapacity(32768)
        var wat = [UInt32]()
        wat.reserveCapacity(4096)
        var minY = CH, maxY = 0
        let offs = [1, -1, RL, -RL, RW, -RW]

        func at(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
            if y < 0 { return STONE }
            if y >= CH { return AIR }
            return R[x + z * RW + y * RL]
        }
        func occ(_ x: Int, _ y: Int, _ z: Int) -> Int { aoT[Int(at(x, y, z))] ? 1 : 0 }
        // Light sample: returns packed sky | blk << 4, or -1 if the cell is solid (excluded from smoothing).
        func light(_ x: Int, _ y: Int, _ z: Int) -> Int {
            if y >= CH { return 15 }
            if y < 0 { return -1 }
            let i = x + z * RW + y * RL
            if loT[Int(R[i])] { return -1 }
            return Int(skyL[i]) | (Int(blkL[i]) << 4)
        }

        // Water surface height at a cell corner (region coords of the corner): the highest of the up to
        // four water cells sharing it; 0 (full block) if any of them has water above.
        let levelT = Blocks.fluidLevel
        func cornerDrop(_ cx: Int, _ y: Int, _ cz: Int) -> Int {
            var best = 7
            for dz in -1...0 {
                for dx in -1...0 {
                    let id = at(cx + dx, y, cz + dz)
                    let lv = Int(levelT[Int(id)])
                    if lv < 0 { continue }
                    if kindT[Int(at(cx + dx, y + 1, cz + dz))] == liquid { return 0 }
                    let d = (lv == 0 || lv == 8) ? 1 : 1 + (lv * 6 + 3) / 7
                    if d < best { best = d }
                }
            }
            return best
        }

        var lit = [Int](repeating: 0, count: 4)
        for y in 0...min(yMax, CH - 1) {
            for z in C0..<(C0 + CS) {
                for x in C0..<(C0 + CS) {
                    let i = x + z * RW + y * RL
                    let b = R[i]
                    if b == AIR { continue }
                    let bi = Int(b)
                    let lx = x - C0, lz = z - C0
                    if kindT[bi] == plant {
                        let l = UInt32(skyL[i]) | (UInt32(blkL[i]) << 4)
                        let w1 = UInt32(texT[bi * 6 + 2]) | (l << 8)
                        let base = (plantFace << 19) | (UInt32(3) << 24)
                        for q in 0..<4 {
                            for k in 0..<4 {
                                let ci = (q * 4 + k) * 3
                                let vx = lx + PTab[ci], vy = y + PTab[ci + 1], vz = lz + PTab[ci + 2]
                                let w0 = UInt32(vx) | (UInt32(vy) << 5) | (UInt32(vz) << 14) | base | (UInt32(k) << 22)
                                opq.append(w0); opq.append(w1)
                            }
                        }
                        if y < minY { minY = y }
                        if y + 1 > maxY { maxY = y + 1 }
                        continue
                    }
                    let isWater = kindT[bi] == liquid
                    let waterTop = isWater && kindT[Int(at(x, y + 1, z))] != liquid
                    for f in 0..<6 {
                        if f == 3 && y == 0 { continue }
                        let nb: UInt8 = (f == 2 && y == CH - 1) ? AIR : R[i + offs[f]]
                        if opaqueT[Int(nb)] { continue }
                        if isWater {
                            if kindT[Int(nb)] == liquid { continue }
                        } else if cullSameT[bi] && nb == b {
                            continue
                        }
                        let nx = NT[f * 3], ny = NT[f * 3 + 1], nz = NT[f * 3 + 2]
                        let ax = x + nx, ay = y + ny, az = z + nz
                        var ao0 = 3, ao1 = 3, ao2 = 3, ao3 = 3
                        let flat = max(0, light(ax, ay, az))
                        if isWater {
                            lit[0] = flat; lit[1] = flat; lit[2] = flat; lit[3] = flat
                        } else {
                            for c in 0..<4 {
                                let ci = (f * 4 + c) * 3
                                let ox = nx == 0 ? CT[ci] * 2 - 1 : 0
                                let oy = ny == 0 ? CT[ci + 1] * 2 - 1 : 0
                                let oz = nz == 0 ? CT[ci + 2] * 2 - 1 : 0
                                // Side cells (s1, s2) and the diagonal corner cell around this vertex.
                                let s1x: Int, s1y: Int, s1z: Int, s2x: Int, s2y: Int, s2z: Int
                                if nx != 0 { s1x = ax; s1y = ay + oy; s1z = az; s2x = ax; s2y = ay; s2z = az + oz }
                                else if ny != 0 { s1x = ax + ox; s1y = ay; s1z = az; s2x = ax; s2y = ay; s2z = az + oz }
                                else { s1x = ax + ox; s1y = ay; s1z = az; s2x = ax; s2y = ay + oy; s2z = az }
                                let s1 = occ(s1x, s1y, s1z), s2 = occ(s2x, s2y, s2z)
                                let cc = occ(ax + ox, ay + oy, az + oz)
                                let v = (s1 == 1 && s2 == 1) ? 0 : 3 - s1 - s2 - cc
                                switch c {
                                case 0: ao0 = v
                                case 1: ao1 = v
                                case 2: ao2 = v
                                default: ao3 = v
                                }
                                // Smooth light: average the non-solid cells among face cell, sides, corner.
                                let l1 = light(s1x, s1y, s1z), l2 = light(s2x, s2y, s2z)
                                let lc = (l1 < 0 && l2 < 0) ? -1 : light(ax + ox, ay + oy, az + oz)
                                var sSum = flat & 15, bSum = flat >> 4, n = 1
                                if l1 >= 0 { sSum += l1 & 15; bSum += l1 >> 4; n += 1 }
                                if l2 >= 0 { sSum += l2 & 15; bSum += l2 >> 4; n += 1 }
                                if lc >= 0 { sSum += lc & 15; bSum += lc >> 4; n += 1 }
                                lit[c] = ((sSum + n / 2) / n) | (((bSum + n / 2) / n) << 4)
                            }
                        }
                        let flip = ao0 + ao2 < ao1 + ao3 // rotate quad diagonal to avoid AO artifacts
                        let base = UInt32(f) << 19
                        let tex = UInt32(texT[bi * 6 + f])
                        for k in 0..<4 {
                            let c = flip ? (k + 1) & 3 : k
                            let ci = (f * 4 + c) * 3
                            let dy = CT[ci + 1]
                            let vx = lx + CT[ci], vy = y + dy, vz = lz + CT[ci + 2]
                            let a = c == 0 ? ao0 : (c == 1 ? ao1 : (c == 2 ? ao2 : ao3))
                            let lower: UInt32 = (waterTop && dy == 1) ? UInt32(cornerDrop(x + CT[ci], y, z + CT[ci + 2])) : 0
                            let w0 = UInt32(vx) | (UInt32(vy) << 5) | (UInt32(vz) << 14) | base
                                | (UInt32(c) << 22) | (UInt32(a) << 24) | (lower << 26)
                            let w1 = tex | (UInt32(lit[c]) << 8)
                            if isWater {
                                wat.append(w0); wat.append(w1)
                            } else {
                                opq.append(w0); opq.append(w1)
                            }
                        }
                        if y < minY { minY = y }
                        if y + 1 > maxY { maxY = y + 1 }
                    }
                }
            }
        }
        return MeshData(opaque: opq, water: wat, minY: minY, maxY: maxY)
    }
}
