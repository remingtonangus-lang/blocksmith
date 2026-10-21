import Foundation
import simd

// P389: a struck object drawn in its sections' detail stream (Mesher.buildSection hands over the objects with cells in
// the chunk; the block loop skips those cells). Each remaining piece is a convex polyhedron: its faces that are still
// the parts' own faces take the block's texture exactly where the block mesher put it (Fracture.blockUV), lit as the
// block mesher lights them (a cube's faces with the smooth corner light and occlusion, a model's faces flat with the
// light of the cell they face), so an object looks as it did before it was struck; faces a blow cut show the block's
// inner (bottom) texture, darker.
extension WorldObjects {
    static func emit(_ ctx: DetailContext, _ draws: [Draw], cx: Int, cz: Int, seat: (Int, Int, Int) -> Int) {
        let loT = Blocks.lightOpaque, aoT = Blocks.aoOcc, opqT = Blocks.opaque, natT = SmoothTerrain.natural
        let rModel = RenderType.model.rawValue
        @inline(__always) func inRegion(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            let rx = x + Mesher.C0, ry = y + Mesher.C0, rz = z + Mesher.C0
            return rx >= 0 && ry >= 0 && rz >= 0 && rx < Mesher.RW && ry < Mesher.RH && rz < Mesher.RW
        }
        // Packed sky | block << 4 of a cell; -1 inside a block that stops light (the block mesher's light()).
        func light(_ x: Int, _ y: Int, _ z: Int) -> Int {
            guard inRegion(x, y, z) else { return 0 }
            let i = ctx.ri(x, y, z)
            if loT[Int(ctx.R[i])] { return -1 }
            return Int(ctx.sky[i]) | (Int(ctx.blk[i]) << 4)
        }
        func occ(_ x: Int, _ y: Int, _ z: Int) -> Float { aoT[Int(ctx.block(x, y, z))] ? 1 : 0 }
        let sy = ctx.sy
        for d in draws {
            var here = [Bool](repeating: false, count: d.cells.count)
            var any = false
            for (k, c) in d.cells.enumerated() where d.mine[k] && floorDiv(c.x, CS) == cx && floorDiv(c.z, CS) == cz && c.y >> 4 == sy {
                here[k] = true; any = true
            }
            guard any else { continue }
            let mineSet = Set(d.cells.enumerated().filter { d.mine[$0.offset] }.map { $0.element })
            var seats = [Float](repeating: .nan, count: d.cells.count)
            for f in d.frags {
                let pt = d.parts[f.part], k = pt.cell
                guard here[k] else { continue }
                let c = d.cells[k], b = d.blocks[k], bi = Int(b)
                let lx = c.x - cx * CS, ly = c.y - sy * 16, lz = c.z - cz * CS
                if seats[k].isNaN {
                    seats[k] = Blocks.render[bi] == rModel && GroundDrape.seat[bi] == 1 ? Float(seat(lx, ly, lz)) / 16 : 0
                }
                let base = SIMD3<Float>(Float(lx), Float(ly) + seats[k], Float(lz))
                let cutL = Blocks.layer[bi] != RenderLayer.opaque.rawValue
                let tr = Int(Blocks.tint[bi]), tint = tr == 3 ? 0 : tr
                var boxTex: [UInt16]? = nil
                if pt.boxIndex >= 0 && pt.boxIndex < Blocks.boxes[bi].count && Blocks.boxes[bi][pt.boxIndex].tex.count == 6 {
                    boxTex = Blocks.boxes[bi][pt.boxIndex].tex
                }
                let ownL = max(0, light(lx, ly, lz))
                // (a log or other block that stops light holds none itself: a face inside its cell takes the open cells')
                let ownOpaque = inRegion(lx, ly, lz) && loT[Int(ctx.R[ctx.ri(lx, ly, lz)])]
                let p = f.poly
                for fi in 0..<p.faceCount {
                    let s0 = Int(p.faceStart[fi]), s1 = Int(p.faceStart[fi + 1])
                    guard s1 - s0 >= 3 else { continue }
                    let tag = Int(p.tags[fi]), pl = p.planes[fi]
                    let n = SIMD3<Float>(pl.x, pl.y, pl.z)
                    let axisF = tag < 6 ? tag : Fracture.dominantFace(n)
                    let layer = tag < 6 ? Int(boxTex?[tag] ?? Blocks.tex[bi * 6 + tag]) : Int(Blocks.tex[bi * 6 + 3])
                    // How each vertex is lit: (ao, light) from its cell-local position.
                    var flatAO = 3, flatL = ownL
                    var mid = SIMD3<Float>(repeating: 0)
                    for e in s0..<s1 { mid += p.verts[Int(p.loop[e])] }
                    mid /= Float(s1 - s0)
                    var corners: [(Float, Float, Float)]? = nil          // (ao, sky, block) at the face's 4 corners
                    var t1 = 0, t2 = 0
                    if tag < 6 {
                        let a = tag / 2, positive = tag % 2 == 0
                        // (a face lying on the cell's side: a soft box's or trunk's slanted faces carry a side's tag too)
                        let onBoundary = abs(n[a]) > 0.999 && (positive ? mid[a] > 0.999 : mid[a] < 0.001)
                        var nx = 0, ny = 0, nz = 0
                        if a == 0 { nx = positive ? 1 : -1 } else if a == 1 { ny = positive ? 1 : -1 } else { nz = positive ? 1 : -1 }
                        if onBoundary {
                            // (hidden against a solid neighbour that isn't the object, as the block mesher culls it)
                            let nbw = IVec3(c.x + nx, c.y + ny, c.z + nz)
                            let nb = Int(ctx.block(lx + nx, ly + ny, lz + nz))
                            if opqT[nb] && !natT[nb] && !mineSet.contains(nbw) { continue }
                            flatL = max(0, light(lx + nx, ly + ny, lz + nz))
                        } else if ownOpaque {
                            flatL = ctx.light(base + mid + n * 0.3)
                        }
                        if pt.cube {
                            let ax = lx + nx, ay = ly + ny, az = lz + nz
                            let flat = max(0, light(ax, ay, az))
                            t1 = (a + 1) % 3; t2 = (a + 2) % 3
                            var cs: [(Float, Float, Float)] = []
                            for cc in 0..<4 {
                                let o1 = (cc & 1) * 2 - 1, o2 = (cc >> 1) * 2 - 1
                                var e1 = [0, 0, 0], e2 = [0, 0, 0]
                                e1[t1] = o1; e2[t2] = o2
                                let s1 = (ax + e1[0], ay + e1[1], az + e1[2]), s2 = (ax + e2[0], ay + e2[1], az + e2[2])
                                let sc = (ax + e1[0] + e2[0], ay + e1[1] + e2[1], az + e1[2] + e2[2])
                                let q1 = occ(s1.0, s1.1, s1.2), q2 = occ(s2.0, s2.1, s2.2), qc = occ(sc.0, sc.1, sc.2)
                                let ao: Float = (q1 == 1 && q2 == 1) ? 0 : 3 - q1 - q2 - qc
                                let l1 = light(s1.0, s1.1, s1.2), l2 = light(s2.0, s2.1, s2.2)
                                let lc = (l1 < 0 && l2 < 0) ? -1 : light(sc.0, sc.1, sc.2)
                                var sS = flat & 15, bS = flat >> 4, m = 1
                                if l1 >= 0 { sS += l1 & 15; bS += l1 >> 4; m += 1 }
                                if l2 >= 0 { sS += l2 & 15; bS += l2 >> 4; m += 1 }
                                if lc >= 0 { sS += lc & 15; bS += lc >> 4; m += 1 }
                                cs.append((ao, Float((sS + m / 2) / m), Float((bS + m / 2) / m)))
                            }
                            corners = cs
                        }
                    } else {
                        // A face a blow cut: the block's inner texture, lit from the open cells round its middle, darker.
                        flatL = ctx.light(base + mid + n * 0.3)
                        flatAO = 1
                    }
                    @inline(__always) func put(_ v: SIMD3<Float>) {
                        let uv = Fracture.blockUV(axisF, v)
                        if let cs = corners {
                            let u = min(max(v[t1], 0), 1), w = min(max(v[t2], 0), 1)
                            let k00 = (1 - u) * (1 - w), k10 = u * (1 - w), k01 = (1 - u) * w, k11 = u * w
                            let ao = cs[0].0 * k00 + cs[1].0 * k10 + cs[2].0 * k01 + cs[3].0 * k11
                            let s = cs[0].1 * k00 + cs[1].1 * k10 + cs[2].1 * k01 + cs[3].1 * k11
                            let bl = cs[0].2 * k00 + cs[1].2 * k10 + cs[2].2 * k01 + cs[3].2 * k11
                            ctx.vertex(base + v, n, uv, layer: layer, tint: tint, ao: Int(ao.rounded()),
                                       light: Int(s.rounded()) | (Int(bl.rounded()) << 4), cut: cutL)
                        } else {
                            ctx.vertex(base + v, n, uv, layer: layer, tint: tint, ao: flatAO, light: flatL, cut: cutL)
                        }
                    }
                    // Quads of the face's fan (a triangle repeats its last corner), corners counter-clockwise from outside.
                    let v0 = p.verts[Int(p.loop[s0])]
                    var e = s0 + 1
                    while e + 1 < s1 {
                        put(v0)
                        put(p.verts[Int(p.loop[e])])
                        put(p.verts[Int(p.loop[e + 1])])
                        put(p.verts[Int(p.loop[min(e + 2, s1 - 1)])])
                        e += 2
                    }
                }
            }
        }
    }
}
