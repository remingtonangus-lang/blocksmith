import Foundation

struct MeshData {
    var opaque: [UInt32]
    var water: [UInt32]
    var minY: Int
    var maxY: Int
}

// Builds packed vertex data for one chunk from a 3x3 neighborhood of chunk arrays.
// Vertex = 2 x UInt32 (8 bytes):
//   w0: x(5) y(9) z(5) face(3) corner(2) ao(2) lowerTop(1)
//   w1: textureLayer(8) light(4)
enum Mesher {
    static let PW = CS + 2
    static let PL = PW * PW

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

    static func build(_ n9: [[UInt8]]) -> MeshData {
        let PW = Mesher.PW, PL = Mesher.PL
        let kindT = Blocks.kind, opaqueT = Blocks.opaque, skyT = Blocks.sky, aoT = Blocks.aoOcc
        let cullSameT = Blocks.cullSame, texT = Blocks.tex
        let CT = cornerTable, NT = normalTable
        let liquid = BlockKind.liquid.rawValue

        var padB = [UInt8](repeating: AIR, count: PL * CH)
        for pz in 0..<PW {
            let lz = pz - 1
            let cz = lz < 0 ? 0 : (lz >= CS ? 2 : 1)
            let sz = (lz + CS) % CS
            for px in 0..<PW {
                let lx = px - 1
                let cx = lx < 0 ? 0 : (lx >= CS ? 2 : 1)
                let sx = (lx + CS) % CS
                let src = n9[cx + cz * 3]
                var si = sx + sz * CS
                var di = px + pz * PW
                for _ in 0..<CH {
                    padB[di] = src[si]
                    si += CSQ
                    di += PL
                }
            }
        }
        let P = padB

        var top = [Int](repeating: -1, count: PL)
        for c in 0..<PL {
            var y = CH - 1
            while y >= 0 && !skyT[Int(P[c + y * PL])] { y -= 1 }
            top[c] = y
        }
        var yMax = 0
        for pz in 1...CS {
            for px in 1...CS {
                var y = CH - 1
                while y > 0 && P[px + pz * PW + y * PL] == AIR { y -= 1 }
                if y > yMax { yMax = y }
            }
        }

        var opq = [UInt32]()
        opq.reserveCapacity(32768)
        var wat = [UInt32]()
        wat.reserveCapacity(4096)
        var minY = CH, maxY = 0
        let offs = [1, -1, PL, -PL, PW, -PW]

        func at(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
            if y < 0 { return STONE }
            if y >= CH { return AIR }
            return P[x + z * PW + y * PL]
        }
        func occ(_ x: Int, _ y: Int, _ z: Int) -> Int { aoT[Int(at(x, y, z))] ? 1 : 0 }

        for y in 0...min(yMax, CH - 1) {
            for pz in 1...CS {
                for px in 1...CS {
                    let i = px + pz * PW + y * PL
                    let b = P[i]
                    if b == AIR { continue }
                    let bi = Int(b)
                    let isWater = kindT[bi] == liquid
                    let waterTop = isWater && at(px, y + 1, pz) != b
                    for f in 0..<6 {
                        if f == 3 && y == 0 { continue }
                        let nb: UInt8 = (f == 2 && y == CH - 1) ? AIR : P[i + offs[f]]
                        if opaqueT[Int(nb)] { continue }
                        if isWater {
                            if nb == b { continue }
                        } else if cullSameT[bi] && nb == b {
                            continue
                        }
                        let nx = NT[f * 3], ny = NT[f * 3 + 1], nz = NT[f * 3 + 2]
                        let ax = px + nx, ay = y + ny, az = pz + nz
                        let t = top[ax + az * PW]
                        var light = 15
                        if ay <= t { light = max(5, 14 - 2 * (t - ay)) }
                        var ao0 = 3, ao1 = 3, ao2 = 3, ao3 = 3
                        if !isWater {
                            for c in 0..<4 {
                                let ci = (f * 4 + c) * 3
                                let ox = nx == 0 ? CT[ci] * 2 - 1 : 0
                                let oy = ny == 0 ? CT[ci + 1] * 2 - 1 : 0
                                let oz = nz == 0 ? CT[ci + 2] * 2 - 1 : 0
                                let s1: Int, s2: Int
                                if nx != 0 { s1 = occ(ax, ay + oy, az); s2 = occ(ax, ay, az + oz) }
                                else if ny != 0 { s1 = occ(ax + ox, ay, az); s2 = occ(ax, ay, az + oz) }
                                else { s1 = occ(ax + ox, ay, az); s2 = occ(ax, ay + oy, az) }
                                let cc = occ(ax + ox, ay + oy, az + oz)
                                let v = (s1 == 1 && s2 == 1) ? 0 : 3 - s1 - s2 - cc
                                switch c {
                                case 0: ao0 = v
                                case 1: ao1 = v
                                case 2: ao2 = v
                                default: ao3 = v
                                }
                            }
                        }
                        let w1 = UInt32(texT[bi * 6 + f]) | (UInt32(light) << 8)
                        let flip = ao0 + ao2 < ao1 + ao3 // rotate quad diagonal to avoid AO artifacts
                        let base = UInt32(f) << 19
                        for k in 0..<4 {
                            let c = flip ? (k + 1) & 3 : k
                            let ci = (f * 4 + c) * 3
                            let dy = CT[ci + 1]
                            let x = px - 1 + CT[ci], yy = y + dy, z = pz - 1 + CT[ci + 2]
                            let a = c == 0 ? ao0 : (c == 1 ? ao1 : (c == 2 ? ao2 : ao3))
                            let lower: UInt32 = (waterTop && dy == 1) ? 1 : 0
                            let w0 = UInt32(x) | (UInt32(yy) << 5) | (UInt32(z) << 14) | base
                                | (UInt32(c) << 22) | (UInt32(a) << 24) | (lower << 26)
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
