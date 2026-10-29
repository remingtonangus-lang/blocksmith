import Foundation
import simd

// P381 steps 2 and 6 (questcheck --adaptivecheck): the 5 x 5 chunks round the eye meshed with the full ground and with
// the adaptive ground, section by section. Walking, collision, digging and placing all go by the field, which the full
// ground draws; so the adaptive ground matches them when it stays within the bound of the full ground both ways:
// every full-ground vertex lies within it of an adaptive triangle, and every point of an adaptive triangle (corners,
// edge middles, centre) within it of a full triangle. Also: the mesh time each way (the workers' cost).
extension AdaptiveGround {
    private typealias Tri = (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)

    // Triangles of a section's ground: the quads up to groundQuads (both triangles of each, the lone ones once).
    private static func groundTris(_ m: SectionMesh) -> [Tri] {
        var out: [Tri] = []
        let n = min(m.groundQuads, m.opaque.count / 8)
        func p(_ q: Int, _ k: Int) -> SIMD3<Float> {
            let w = m.opaque[q * 8 + k * 2]
            return SIMD3<Float>(Float(w & 511), Float((w >> 9) & 511), Float((w >> 18) & 511)) / 16
        }
        for q in 0..<n {
            let a = p(q, 0), b = p(q, 1), c = p(q, 2), d = p(q, 3)
            // (zero-area quads, slivers the surface nets leave on a line, draw nothing and are left out)
            if simd_length(simd_cross(b - a, c - a)) > 1e-6 { out.append((a, b, c)) }
            if d != c && simd_length(simd_cross(c - a, d - a)) > 1e-6 { out.append((a, c, d)) }
        }
        return out
    }

    // Closest point on a triangle (Ericson, Real-Time Collision Detection 5.1.5), as a distance.
    private static func dist(_ p: SIMD3<Float>, _ t: Tri) -> Float {
        let (a, b, c) = t
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return simd_length(p - a) }
        let bp = p - b
        let d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return simd_length(p - b) }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 { let v = d1 / (d1 - d3); return simd_length(p - (a + ab * v)) }
        let cp = p - c
        let d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return simd_length(p - c) }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 { let w = d2 / (d2 - d6); return simd_length(p - (a + ac * w)) }
        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return simd_length(p - (b + (c - b) * w))
        }
        let denom = 1 / (va + vb + vc)
        let v = vb * denom, w = vc * denom
        let q = a + ab * v + ac * w
        return simd_length(p - q)
    }

    // Nearest-triangle search over a 1-block grid of the triangles' boxes (padded by the search radius).
    private struct Grid {
        var cells: [Int: [Int32]] = [:]
        let tris: [Tri]
        static let pad: Float = 0.25
        init(_ t: [Tri]) {
            tris = t
            for (i, tr) in t.enumerated() {
                let lo = simd_min(simd_min(tr.0, tr.1), tr.2) - Grid.pad, hi = simd_max(simd_max(tr.0, tr.1), tr.2) + Grid.pad
                let l = SIMD3<Int32>(Int32(lo.x.rounded(.down)), Int32(lo.y.rounded(.down)), Int32(lo.z.rounded(.down)))
                let h = SIMD3<Int32>(Int32(hi.x.rounded(.down)), Int32(hi.y.rounded(.down)), Int32(hi.z.rounded(.down)))
                for z in l.z...h.z { for y in l.y...h.y { for x in l.x...h.x { cells[Grid.key(x, y, z), default: []].append(Int32(i)) } } }
            }
        }
        static func key(_ x: Int32, _ y: Int32, _ z: Int32) -> Int { Int(x + 64) | Int(y + 64) << 8 | Int(z + 64) << 16 }
        // Distance to the nearest triangle, capped at pad (farther counts as pad).
        func near(_ p: SIMD3<Float>) -> Float {
            let c = SIMD3<Int32>(Int32(p.x.rounded(.down)), Int32(p.y.rounded(.down)), Int32(p.z.rounded(.down)))
            var best = Grid.pad
            for i in cells[Grid.key(c.x, c.y, c.z)] ?? [] { best = min(best, AdaptiveGround.dist(p, tris[Int(i)])) }
            return best
        }
    }

    // Triangles of a run of quads (words), at the positions `exact` gives a vertex (by its index in the run) when given.
    // allArea: slivers too (every triangle of three different points: the crack check).
    private static func quadTris(_ w: ArraySlice<UInt32>, exact: UnsafePointer<Float>? = nil, allArea: Bool = false) -> [Tri] {
        var out: [Tri] = []
        let base = w.startIndex
        func p(_ q: Int, _ k: Int) -> SIMD3<Float> {
            if let e = exact { let i = (q * 4 + k) * 3; return SIMD3<Float>(e[i], e[i + 1], e[i + 2]) }
            let x = w[base + q * 8 + k * 2]
            return SIMD3<Float>(Float(x & 511), Float((x >> 9) & 511), Float((x >> 18) & 511)) / 16
        }
        let minA: Float = allArea ? -1 : 1e-6
        for q in 0..<(w.count / 8) {
            let a = p(q, 0), b = p(q, 1), c = p(q, 2), d = p(q, 3)
            if a != b && b != c && a != c && simd_length(simd_cross(b - a, c - a)) > minA { out.append((a, b, c)) }
            if d != c && a != d && a != c && simd_length(simd_cross(c - a, d - a)) > minA { out.append((a, c, d)) }
        }
        return out
    }
    private static func flat(_ t: [SIMD3<Float>]) -> [Tri] { stride(from: 0, to: t.count - 2, by: 3).map { (t[$0], t[$0 + 1], t[$0 + 2]) } }

    // Both ways between two triangle sets: worst distance and points over `tol`, from every vertex of `ref` to `test`,
    // and from every point of `test` (corners, edge middles, centre) to `ref`.
    private struct TwoWay {
        var worstA: Float = 0, worstB: Float = 0, overA = 0, overB = 0, pointsA = 0, pointsB = 0
        mutating func add(ref: [Tri], test: [Tri], tol: Float) {
            let gt = Grid(test), gr = Grid(ref)
            for t in ref { for p in [t.0, t.1, t.2] {
                let d = gt.near(p); pointsA += 1
                worstA = max(worstA, d); if d > tol { overA += 1 }
            } }
            for t in test {
                let m01: V3 = (t.0 + t.1) / 2, m12: V3 = (t.1 + t.2) / 2, m02: V3 = (t.0 + t.2) / 2
                let mid: V3 = (t.0 + t.1 + t.2) / 3
                let ps: [V3] = [t.0, t.1, t.2, m01, m12, m02, mid]
                for p in ps { let d = gr.near(p); pointsB += 1; worstB = max(worstB, d); if d > tol { overB += 1 } }
            }
        }
        func line(_ tol: Float) -> String {
            String(format: "worst %.4f block (%d of %d points over %.3f) / %.4f (%d of %d over)", worstA, overA, pointsA, tol, worstB, overB, pointsB)
        }
    }

    // P381 step 2 / P383 step 5 (questcheck --adaptivecheck): the 5 x 5 chunks round the eye meshed with the full ground
    // and with the adaptive ground, section by section, both measured against the field's exact surface (the full
    // ground at its unsnapped positions, MeshScratch.groundExact): the near copy (bound `tolerance`) and the far copy
    // (farTolerance), both ways; the drawn (1/16-snapped) grounds against it too; crack-free borders; and how many
    // ground positions are drawn with two or more different vertices (P383 step 2).
    static func check(_ vw: World, eye: V3) -> String {
        let pcx = floorDiv(Int(floor(eye.x)), CS), pcz = floorDiv(Int(floor(eye.z)), CS)
        var msFull = 0.0, msAd = 0.0, trisFull = 0, trisAd = 0, quadsFull = 0, quadsAd = 0, sections = 0, farIn = 0, farOut = 0
        var near = TwoWay(), far = TwoWay(), drawnFull = TwoWay(), drawnAd = TwoWay()
        var crackEdges = 0, noExact = 0, posAll = 0, posSplit = 0
        let slack: Float = 1.0 / 4096
        let tol = AdaptiveGround.tolerance + slack, ftol = AdaptiveGround.farTolerance + slack
        for dz in -2...2 { for dx in -2...2 {
            guard let c = vw.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)], let nb = vw.neighbourhood(c) else { continue }
            for sy in 0..<NSEC {
                var t0 = CFAbsoluteTimeGetCurrent()
                let full = Mesher.buildSection(nb.0, nb.1, sy: sy, chunk: (c.cx, c.cz), adaptive: false)
                msFull += (CFAbsoluteTimeGetCurrent() - t0) * 1000
                let ex = MeshScratch.current.groundExact
                let fullW = full.opaque.prefix(full.groundQuads * 8)
                var exactCopy: [Float] = []
                if ex.count == full.groundQuads * 4 * 3 {
                    exactCopy = ex.toArray()
                    var per: [UInt32: Set<UInt64>] = [:]
                    for i in 0..<(full.groundQuads * 4) {
                        let w0 = full.opaque[i * 2]
                        per[w0 & 0x07FF_FFFF, default: []].insert(UInt64(w0) << 32 | UInt64(full.opaque[i * 2 + 1]))
                    }
                    posAll += per.count; posSplit += per.values.filter { $0.count > 1 }.count
                } else if full.groundQuads > 0 { noExact += 1 }
                AdaptiveGround.capture = true; AdaptiveGround.captured = ([], [])
                t0 = CFAbsoluteTimeGetCurrent()
                let ad = Mesher.buildSection(nb.0, nb.1, sy: sy, chunk: (c.cx, c.cz), adaptive: true)
                msAd += (CFAbsoluteTimeGetCurrent() - t0) * 1000
                AdaptiveGround.capture = false
                let adW = ad.opaque.prefix(ad.groundQuads * 8)
                let tf = quadTris(fullW), ta = quadTris(adW)
                guard !tf.isEmpty else { continue }
                if let dir = ProcessInfo.processInfo.environment["BS_ADAPTIVE_DUMP"] {      // (the full ground, for tuning offline)
                    let words = Array(fullW)
                    let data = words.withUnsafeBufferPointer { Data(buffer: $0) }
                    try? data.write(to: URL(fileURLWithPath: "\(dir)/s\(sections).bin"))
                }
                sections += 1
                trisFull += tf.count; trisAd += ta.count; quadsFull += full.groundQuads; quadsAd += ad.groundQuads
                // The exact surface (the full ground at its unsnapped positions), and the adaptive copies at theirs (the
                // near copy unchanged when the simplifier gave nothing back).
                let tx = exactCopy.isEmpty ? tf : exactCopy.withUnsafeBufferPointer { quadTris(fullW, exact: $0.baseAddress!) }
                let nearX = AdaptiveGround.captured.0.isEmpty || ad.groundQuads == full.groundQuads ? tx : flat(AdaptiveGround.captured.0)
                near.add(ref: tx, test: nearX, tol: tol)
                drawnFull.add(ref: tx, test: tf, tol: tol)
                drawnAd.add(ref: tx, test: ta, tol: tol)
                if !ad.farGround.isEmpty {
                    farIn += ad.farSkip; farOut += ad.farGround.count / 8
                    far.add(ref: tx, test: AdaptiveGround.captured.1.isEmpty ? quadTris(ad.farGround[...]) : flat(AdaptiveGround.captured.1), tol: ftol)
                }
                // Cracks: an edge of the adaptive ground used by one triangle only must be an edge of the full ground
                // used by one triangle only too (the section's sides, holes): the border is the same, vertex for vertex.
                func borders(_ ts: [Tri]) -> Set<[Float]> {
                    var n: [[Float]: Int] = [:]
                    for t in ts { for (a, b) in [(t.0, t.1), (t.1, t.2), (t.2, t.0)] {
                        let k = a.x < b.x || (a.x == b.x && (a.y < b.y || (a.y == b.y && a.z < b.z))) ? [a.x, a.y, a.z, b.x, b.y, b.z] : [b.x, b.y, b.z, a.x, a.y, a.z]
                        n[k, default: 0] += 1
                    } }
                    return Set(n.filter { $0.value == 1 }.keys)
                }
                crackEdges += borders(quadTris(adW, allArea: true)).symmetricDifference(borders(quadTris(fullW, allArea: true))).count
            }
        } }
        return String(format: "adaptivecheck: %d sections; ground %d -> %d triangles (%d -> %d quads, %.1f%%); far copy %d -> %d quads; ground positions %d, drawn with 2+ vertices %d (%.1f%%)",
                      sections, trisFull, trisAd, quadsFull, quadsAd, Double(quadsAd) * 100 / Double(max(1, quadsFull)), farIn, farOut,
                      posAll, posSplit, Double(posSplit) * 100 / Double(max(1, posAll)))
            + (noExact > 0 ? " (\(noExact) sections without exact positions)" : "")
            + "\n  near copy to the exact surface (full to adaptive / adaptive to full): " + near.line(AdaptiveGround.tolerance)
            + "\n  far copy to the exact surface: " + far.line(AdaptiveGround.farTolerance)
            + "\n  drawn (1/16-snapped) full ground to the exact surface: " + drawnFull.line(AdaptiveGround.tolerance)
            + "\n  drawn adaptive ground to the exact surface: " + drawnAd.line(AdaptiveGround.tolerance)
            + String(format: "\n  border edges differing %d; mesh %.1f ms full, %.1f ms adaptive", crackEdges, msFull, msAd)
            + " (seams " + (AdaptiveGround.joinSeams ? "joined" : "kept") + ", triGround \(SmoothTerrain.triGround)"
            + String(format: ", light %.2f, ao %.2f, material %.2f)", AdaptiveGround.lightTol, AdaptiveGround.aoTol, AdaptiveGround.matTol)
    }

    // P384 step 3 (questcheck --farcheck): the 5 x 5 chunks round the eye meshed as the game does, section by section,
    // and each far copy measured both ways against what it stands for: every near point (corners) within the bound of
    // the far copy and every far point (corners, edge middles, centre) within it of the near quads. Bevelled faces, things
    // laid on the ground and the detail stream as drawn; the leaf blobs' far shell against the exact surface of the outer
    // shell it stands for (as the ground's far copy is, --adaptivecheck: the 1/16 grid adds up to 0.054 at a vertex
    // either way). Also the quads each way and the workers' mesh time with and without the far copies.
    static func farCheck(_ vw: World, eye: V3) -> String {
        let pcx = floorDiv(Int(floor(eye.x)), CS), pcz = floorDiv(Int(floor(eye.z)), CS)
        let ftol = AdaptiveGround.farTolerance + 1.0 / 4096
        var bevel = TwoWay(), blob = TwoWay(), drape = TwoWay(), det = TwoWay()
        var msOn = 0.0, msOff = 0.0, sections = 0
        var bevN = 0, bevF = 0, blobN = 0, blobF = 0, drapeN = 0, drapeF = 0, detN = 0, detF = 0
        func detTris(_ w: ArraySlice<UInt32>) -> [Tri] {
            var out: [Tri] = []
            let base = w.startIndex
            func p(_ q: Int, _ k: Int) -> SIMD3<Float> {
                let o = base + q * 16 + k * 4
                let w0 = w[o], w1 = w[o + 1]
                return SIMD3<Float>(Float(Int16(bitPattern: UInt16(w0 & 0xFFFF))), Float(Int16(bitPattern: UInt16(w0 >> 16))),
                                    Float(Int16(bitPattern: UInt16(w1 & 0xFFFF)))) / 256
            }
            for q in 0..<(w.count / 16) {
                let a = p(q, 0), b = p(q, 1), c = p(q, 2), d = p(q, 3)
                if a != b && b != c && a != c && simd_length(simd_cross(b - a, c - a)) > 1e-6 { out.append((a, b, c)) }
                if d != c && a != d && a != c && simd_length(simd_cross(c - a, d - a)) > 1e-6 { out.append((a, c, d)) }
            }
            return out
        }
        let was = Mesher.farCopies
        defer { Mesher.farCopies = was; AdaptiveGround.capture = false }
        for dz in -2...2 { for dx in -2...2 {
            guard let c = vw.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)], let nb = vw.neighbourhood(c) else { continue }
            for sy in 0..<NSEC {
                Mesher.farCopies = false
                var t0 = CFAbsoluteTimeGetCurrent()
                _ = Mesher.buildSection(nb.0, nb.1, sy: sy, chunk: (c.cx, c.cz))
                msOff += (CFAbsoluteTimeGetCurrent() - t0) * 1000
                Mesher.farCopies = true
                AdaptiveGround.capture = true; AdaptiveGround.capturedBlob = ([], [])
                t0 = CFAbsoluteTimeGetCurrent()
                let m = Mesher.buildSection(nb.0, nb.1, sy: sy, chunk: (c.cx, c.cz))
                msOn += (CFAbsoluteTimeGetCurrent() - t0) * 1000
                AdaptiveGround.capture = false
                if m.farGround.isEmpty && m.detailFar.isEmpty && m.farTail == 0 { continue }
                sections += 1
                let p = m.farParts
                let g = min(m.groundQuads, m.farSkip)
                // Bevelled faces: the near ones (after the ground) against the far plain ones.
                if p[1] > 0 {
                    let a = Int(p[0]), b = a + Int(p[1])
                    bevel.add(ref: quadTris(m.opaque[(g * 8)..<(m.farSkip * 8)]), test: quadTris(m.farGround[(a * 8)..<(b * 8)]), tol: ftol)
                    bevN += m.farSkip - g; bevF += Int(p[1])
                }
                // Leaf blobs: the far shell against the outer shell's exact surface.
                if p[2] > 0 {
                    let cb = AdaptiveGround.capturedBlob
                    if !cb.0.isEmpty { blob.add(ref: flat(cb.0), test: flat(cb.1), tol: ftol) }
                    blobN += m.farCut - Int(p[3]); blobF += Int(p[2])
                }
                // Things laid on the ground: the pieces against the far quads (the last farTail cutout quads).
                if m.farTail > 0 {
                    let n0 = m.solidQuads + m.farCut - Int(p[3]), n1 = m.solidQuads + m.farCut
                    let all = m.opaque.count / 8
                    drape.add(ref: quadTris(m.opaque[(n0 * 8)..<(n1 * 8)]), test: quadTris(m.opaque[((all - m.farTail) * 8)..<(all * 8)]), tol: ftol)
                    drapeN += Int(p[3]); drapeF += m.farTail
                }
                if !m.detailFar.isEmpty {
                    det.add(ref: detTris(m.detail[0..<(m.detailFarSkip * 16)]), test: detTris(m.detailFar[...]), tol: ftol)
                    detN += m.detailFarSkip; detF += m.detailFar.count / 16
                }
            }
        } }
        let t = AdaptiveGround.farTolerance
        return "farcheck: \(sections) sections with far copies (near -> far quads): bevelled faces \(bevN) -> \(bevF), leaf blobs \(blobN) -> \(blobF), things laid on the ground \(drapeN) -> \(drapeF), detail \(detN) -> \(detF)"
            + "\n  bevelled faces, near to far / far to near: " + bevel.line(t)
            + "\n  leaf blobs (exact outer shell to far shell / far shell to it): " + blob.line(t)
            + "\n  things laid on the ground: " + drape.line(t)
            + "\n  detail: " + det.line(t)
            + String(format: "\n  mesh %.1f ms without far copies, %.1f ms with", msOff, msOn)
    }

    // P381 step 6 (questcheck --adaptivewalk): the player walks 4 s in 8 directions from the eye's spot (Player.update,
    // the field's collision), and at every step the drawn ground straight under the feet is found in the section meshes,
    // full and adaptive: how far the feet are from each. Then 64 rays from the eye at the ground ahead (World.raycast:
    // digging and placing aim by the field), and how far each hit point is from the drawn ground, full and adaptive.
    static func walkCheck(_ g: Game) -> String {
        let w = g.world
        var meshes: [String: [Tri]] = [:]
        func tris(_ cx: Int, _ cz: Int, _ sy: Int, _ adaptive: Bool) -> [Tri] {
            let key = "\(cx) \(cz) \(sy) \(adaptive)"
            if let t = meshes[key] { return t }
            var out: [Tri] = []
            if sy >= 0 && sy < NSEC, let c = w.chunks[ChunkKey(x: cx, z: cz)], let nb = w.neighbourhood(c) {
                let m = Mesher.buildSection(nb.0, nb.1, sy: sy, chunk: (cx, cz), adaptive: adaptive)
                let o = SIMD3<Float>(Float(cx * CS), Float(sy * 16), Float(cz * CS))     // (as the renderer places a section)
                out = groundTris(m).map { ($0.0 + o, $0.1 + o, $0.2 + o) }
            }
            meshes[key] = out
            return out
        }
        // The drawn ground's height nearest y on the vertical line through (x, z).
        func drawn(_ x: Float, _ y: Float, _ z: Float, _ adaptive: Bool) -> Float? {
            let cx = floorDiv(Int(floor(x)), CS), cz = floorDiv(Int(floor(z)), CS), sy = Int(floor(y)) >> 4
            var best: Float? = nil
            // (P386: the chunks round it too: a chunk's west and north block row is drawn by its neighbours)
            for s in (sy - 1)...(sy + 1) { for oz in -1...1 { for ox in -1...1 {
                for t in tris(cx + ox, cz + oz, s, adaptive) {
                    // barycentric in xz
                    let a = SIMD2<Float>(t.0.x, t.0.z), b = SIMD2<Float>(t.1.x, t.1.z), c = SIMD2<Float>(t.2.x, t.2.z), p = SIMD2<Float>(x, z)
                    let v0 = b - a, v1 = c - a, v2 = p - a
                    let den = v0.x * v1.y - v1.x * v0.y
                    guard abs(den) > 1e-8 else { continue }
                    let l1 = (v2.x * v1.y - v1.x * v2.y) / den, l2 = (v0.x * v2.y - v2.x * v0.y) / den
                    guard l1 >= -1e-4 && l2 >= -1e-4 && l1 + l2 <= 1 + 1e-4 else { continue }
                    let h = t.0.y + (t.1.y - t.0.y) * l1 + (t.2.y - t.0.y) * l2
                    if best == nil || abs(h - y) < abs(best! - y) { best = h }
                }
            } } }
            return best
        }
        let start = g.player.pos
        var gaps: [[Float]] = [[], []]
        // BS_FEET_DEBUG: each sample over 0.05: where, what is under it, what the bodies' lookup says there.
        let debug = ProcessInfo.processInfo.environment["BS_FEET_DEBUG"] != nil
        // (a body standing on something built (a log, a crate, a step) is on that, not on the ground: not counted)
        var onBuilt = 0
        func builtUnder(_ p: V3, _ hw: Float) -> Bool {
            for z in Int(floor(p.z - hw))...Int(floor(p.z + hw)) { for x in Int(floor(p.x - hw))...Int(floor(p.x + hw)) {
                for y in Int(floor(p.y - 0.6))...Int(floor(p.y + 0.3)) where Blocks.collide[Int(w.builtBlock(x, y, z))] { return true }
            } }
            return false
        }
        func note(_ what: String, _ p: V3, _ h: Float, _ hw: Float, _ ht: Float) {
            let bx = Int(floor(p.x)), bz = Int(floor(p.z)), by = Int(floor(p.y - 0.05))
            let look = w.drawnGround(p.x, p.z, lo: p.y - 0.6, hi: p.y + 0.6)
            let raw = w.drawnGround(p.x, p.z, lo: p.y - 0.6, hi: p.y + 0.6, check: false)
            let fall = w.sweep(V3(p.x - hw, p.y, p.z - hw), V3(p.x + hw, p.y + ht, p.z + hw), axis: 1, -0.5)
            func f(_ v: Float?) -> String { v.map { String(format: "%.3f", $0) } ?? "nil" }
            print(String(format: "  %@ %.2f %.2f %.2f: drawn %.3f (gap %.3f), lookup %@ (raw %@, density %.3f %.3f), fall %.3f (built boxes %.3f, floor %@), under %@ ground %d, fine %d",
                         what, p.x, p.y, p.z, h, p.y - h, f(look), f(raw), w.fieldDensity(at: V3(p.x, h - 0.25, p.z)), w.fieldDensity(at: V3(p.x, h - 0.5, p.z)),
                         fall, w.sweepBoxesDD, f(w.sweepFloorY), Blocks.key(w.builtBlock(bx, by, bz)), w.groundAt(bx, by, bz) ? 1 : 0, w.fineNear(p) ? 1 : 0))
        }
        // P386 (3): the drawn eye's climb rate tick to tick (its jolts: the largest change, and how often it turns over).
        var jolt: Float = 0, turns = 0, eyeTicks = 0
        for k in 0..<8 {
            g.player.pos = start; g.player.vel = .zero; g.player.flying = false
            g.player.yaw = Float(k) * .pi / 4
            for _ in 0..<60 { g.player.update(dt: 1.0 / 30, input: MoveInput(), world: w); g.updateViewStep(1.0 / 30) }
            var lastEye = g.player.viewEye.y, lastV: Float? = nil
            for f in 0..<120 {
                g.player.update(dt: 1.0 / 30, input: MoveInput(forward: 1), world: w)
                g.updateViewStep(1.0 / 30)
                let e = g.player.viewEye.y, v = (e - lastEye) * 30
                if let lv = lastV, g.player.onGround, abs(v - lv) < 20 {      // (not a fall or a landing)
                    jolt = max(jolt, abs(v - lv)); eyeTicks += 1
                    if (v > 0.3 && lv < -0.3) || (v < -0.3 && lv > 0.3) { turns += 1 }
                }
                lastEye = e; lastV = v
                guard f % 3 == 0, g.player.onGround, w.fieldNear(g.player.pos) else { continue }
                let p = g.player.pos
                if builtUnder(p, 0.3) { onBuilt += 1; continue }
                for (i, ad) in [false, true].enumerated() { if let h = drawn(p.x, p.y, p.z, ad), abs(h - p.y) < 1 { gaps[i].append(p.y - h) } }
                if debug, let h = drawn(p.x, p.y, p.z, true), abs(h - p.y) > 0.05 && abs(h - p.y) < 1 { note("feet", p, h, 0.3, 1.8) }
            }
        }
        // P386 (5): a cow-sized body walked the same way through World.moveBody (as mobs, townsfolk and animals move).
        var mobGaps: [Float] = []
        for k in 0..<8 {
            var p = start, onG = false, vy: Float = 0
            let a = Float(k) * .pi / 4 + 0.2, dir = V3(-sinf(a), 0, -cosf(a)) * 2.5
            for f in 0..<150 {
                vy = onG ? -1 : max(-20, vy - 32 / 30)
                let hit = w.moveBody(&p, halfW: 0.45, height: 1.4, (f < 30 ? V3(0, vy, 0) : dir + V3(0, vy, 0)) / 30, step: 0.6, onGround: onG)
                onG = hit.y && vy < 0
                guard f % 3 == 0, onG, w.fieldNear(p) else { continue }
                if builtUnder(p, 0.45) { onBuilt += 1; continue }
                if let h = drawn(p.x, p.y, p.z, true), abs(h - p.y) < 1 { mobGaps.append(p.y - h); if debug && abs(h - p.y) > 0.05 { note("mob", p, h, 0.45, 1.4) } }
            }
        }
        g.player.pos = start
        // Rays at the ground ahead: where digging and placing land against the drawn ground.
        var hits: [[Float]] = [[], []]
        let eye = start + V3(0, 1.62, 0)
        for k in 0..<64 {
            let yaw = g.player.yaw + Float(k % 16 - 8) * 0.08, pitch: Float = -0.25 - Float(k / 16) * 0.2
            let dir = V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
            guard w.raycast(eye, dir, maxDist: 12) != nil, let h = w.fieldHit else { continue }
            for (i, ad) in [false, true].enumerated() {
                let cx = floorDiv(Int(floor(h.at.x)), CS), cz = floorDiv(Int(floor(h.at.z)), CS), sy = Int(floor(h.at.y)) >> 4
                var best: Float = 9
                for s in (sy - 1)...(sy + 1) { for oz in -1...1 { for ox in -1...1 {
                    for t in tris(cx + ox, cz + oz, s, ad) { best = min(best, AdaptiveGround.dist(h.at, t)) }
                } } }
                if best < 9 { hits[i].append(best) }
                if debug && ad && best > 0.05 && best < 9 {
                    let c = h.cell
                    let all = w.drawnRay(eye, dir, from: 0, to: 12)
                    print(String(format: "  ray %.2f %.2f %.2f off %.3f: cell %d %d %d %@ ground %d; hit t %.3f, drawn along the whole ray t %@", h.at.x, h.at.y, h.at.z, best, c.x, c.y, c.z,
                                 Blocks.key(w.builtBlock(c.x, c.y, c.z)), w.groundAt(c.x, c.y, c.z) ? 1 : 0, h.t, all.map { String(format: "%.3f", $0.t) } ?? "nil"))
                }
            }
        }
        func stat(_ a: [Float], signed: Bool) -> String {
            guard !a.isEmpty else { return "none" }
            let worst = a.map { abs($0) }.max()!, mean = a.map { abs($0) }.reduce(0, +) / Float(a.count)
            let over = a.filter { abs($0) > 0.05 }.count
            return String(format: "%d samples, worst %.3f, mean %.3f, %d over 0.05", a.count, worst, mean, over)
        }
        return "adaptivewalk: feet to drawn ground: full " + stat(gaps[0], signed: true) + "; adaptive " + stat(gaps[1], signed: true)
            + ". Field hits (dig/place) to drawn ground: full " + stat(hits[0], signed: false) + "; adaptive " + stat(hits[1], signed: false)
            + ". Mob-sized body (adaptive): " + stat(mobGaps, signed: true) + " (\(onBuilt) samples on built things left out)"
            + String(format: ". Eye: %d ticks, largest change in climb rate %.2f blocks/s, %d turn-overs", eyeTicks, jolt, turns)
            + ". Kept ground triangles: \(w.chunks.values.reduce(0) { $0 + $1.sections.reduce(0) { $0 + ($1.ground?.quads ?? 0) } }) quads, "
            + String(format: "%.1f MB", Double(w.chunks.values.reduce(0) { $0 + $1.sections.reduce(0) { $0 + ($1.ground?.bytes ?? 0) } }) / 1048576)
            + " in \(w.chunks.count) chunks"
    }
}
