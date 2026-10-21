import Foundation
import simd

// P381 (Remington, Oct 19: "big procedural triangles fitted to the land"): the field ground of a section, as the
// surface nets drew it (a quad per sample cell), is simplified to triangles sized by how much the surface bends. A
// vertex collapses into a neighbour (half-edge collapse, so every vertex left stays on the 1/16 grid where the field put
// it), cheapest first by quadric error (creases, silhouettes and cliff edges cost more), when the bound holds measured
// both ways against the full ground: every full-ground vertex the collapse touches stays within it of the new triangles,
// and every new triangle (corners, edge middles, centre) within it of the full ground's triangles; no triangle turns
// over or doubles up. Flat ground keeps about a third of its triangles; hills, cliffs, cave mouths and edits more.
//   - Crack-free borders: a vertex on the mesh's own edge (the section's sides, a hole for leaves or a crater) never
//     moves or goes, so the section meets its neighbours along exactly the vertices they draw too.
//   - Vertices carry their own light, occlusion, material layer, tint and field normal. P383: the ground is drawn one
//     vertex per position (SmoothTerrain.triGround: no texture facing in the words), and a collapse may join vertices
//     of different material, light or occlusion: what a vertex stood for is then drawn by the new triangle's corners,
//     interpolated (light and occlusion) and blended (materials, chunk_solid.frag). A collapse is taken only while
//     that stays true to every vertex it stands for: light within `lightTol` level, occlusion within `aoTol` step, and
//     its own material at least `matTol` of the blend there (so borders between grounds stay where the field put
//     them, within a fraction of a triangle). A vertex drawn twice with different words (an ore's face among rock) is
//     still two vertices, an edge of the mesh, and stays.
//   - P383 step 4: the bound is measured against the field's exact surface (the surface nets' unsnapped positions,
//     MeshScratch.groundExact), not the 1/16-snapped ground, whose staircase used up most of the 0.05 on hills.
//   - Full 3D: works on the triangles whatever their facing (caves, overhangs, vertical faces); not a heightmap.
// The triangles are paired back into quads for the renderer's quad index pattern (0 1 2, 0 2 3); a lone triangle is a
// quad with its last corner repeated.
// The attribute guard of a collapse (P384: shared by the ground and the detail stream). `seams` false: only vertices
// with equal attributes join (`same`), and nothing else is checked; true: `holds` says whether vertex q is still drawn
// true by triangle t's corners weighted w at its place.
protocol CollapseGuard {
    var seams: Bool { get }
    func same(_ a: Int, _ b: Int) -> Bool
    func holds(_ q: Int, _ t: SIMD3<Int32>, _ w: SIMD3<Double>) -> Bool
}

enum AdaptiveGround {
    static var enabled = ProcessInfo.processInfo.environment["BS_ADAPTIVE"] != "0"
    // Error bound in blocks (P381 step 2: at most 0.05 block inside the active distance).
    static var tolerance: Float = Float(ProcessInfo.processInfo.environment["BS_ADAPTIVE_TOL"] ?? "") ?? 0.05
    // Harness tallies (triangles in and out, all sections; a lock per section).
    static var trisIn = 0, trisOut = 0
    static let tally = NSLock()

    // The planes' squared distances summed (a symmetric 4 x 4: its 10 terms).
    private struct Quadric {
        var a2 = 0.0, ab = 0.0, ac = 0.0, ad = 0.0, b2 = 0.0, bc = 0.0, bd = 0.0, c2 = 0.0, cd = 0.0, d2 = 0.0
        mutating func add(_ n: SIMD3<Double>, _ d: Double) {
            a2 += n.x * n.x; ab += n.x * n.y; ac += n.x * n.z; ad += n.x * d
            b2 += n.y * n.y; bc += n.y * n.z; bd += n.y * d
            c2 += n.z * n.z; cd += n.z * d; d2 += d * d
        }
        static func += (q: inout Quadric, o: Quadric) {
            q.a2 += o.a2; q.ab += o.ab; q.ac += o.ac; q.ad += o.ad; q.b2 += o.b2
            q.bc += o.bc; q.bd += o.bd; q.c2 += o.c2; q.cd += o.cd; q.d2 += o.d2
        }
        func error(_ v: SIMD3<Double>) -> Double {
            let x = v.x, y = v.y, z = v.z
            let sq: Double = a2 * x * x + b2 * y * y + c2 * z * z + d2
            let cross: Double = ab * x * y + ac * x * z + bc * y * z
            let lin: Double = ad * x + bd * y + cd * z
            return sq + 2 * (cross + lin)
        }
    }

    // Distance from a point to a triangle (Ericson, Real-Time Collision Detection 5.1.5).
    static func pointTriangle(_ p: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Double {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return simd_length(ap) }
        let bp = p - b
        let d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return simd_length(bp) }
        let vc: Double = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 { return simd_length(ap - ab * (d1 / (d1 - d3))) }
        let cp = p - c
        let d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return simd_length(cp) }
        let vb: Double = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 { return simd_length(ap - ac * (d2 / (d2 - d6))) }
        let va: Double = d3 * d6 - d5 * d4
        if va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0 { return simd_length(bp - (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))) }
        let den = 1 / (va + vb + vc)
        return simd_length(ap - ab * (vb * den) - ac * (vc * den))
    }
    // A vertex stands for at most this many collapsed ones (bounds the checks' cost on wide flat ground).
    static var maxAbsorbed = Int(ProcessInfo.processInfo.environment["BS_ADAPTIVE_MAXABS"] ?? "") ?? 96

    // Past the active distance (P381 step 2: about one Quest 3 pixel there): a second, coarser copy drawn only for
    // sections at least GroundMerge.farDistance (~180 blocks) from the eye, where 1/8 block is under a pixel at the
    // lens's sharpest; the renderer picks per frame from the exact distance (P375's far switch), so nothing is
    // remeshed as the player moves and near ground always gets the 0.05 block one.
    static var farTolerance: Float = GroundMerge.tol16 / 16
    static var farEnabled = ProcessInfo.processInfo.environment["BS_ADAPTIVE_FAR"] != "0"

    // The section's ground (buf[from...], led by nothing else when from == 0) simplified to the near bound in place,
    // and, when it leads the buffer, a far copy (the renderer's far switch: the first farSkip quads give way to the
    // farGround ones). Returns the quads removed from the buffer.
    static func mesh(_ buf: GrowBuf<UInt32>, from: Int, exact: UnsafePointer<Float>? = nil, farSkip: inout Int, farGround: inout [UInt32]) -> Int {
        let far = from == 0 && farEnabled && Mesher.farGround && buf.count - from >= 32
        let raw = far ? Array(UnsafeBufferPointer(start: buf.ptr + from, count: buf.count - from)) : []
        let removed = simplify(buf, from: from, tol: tolerance, exact: exact)
        guard far else { return removed }
        let near = buf.count, before = buf.count
        for w in raw { buf.append(w) }
        simplify(buf, from: before, tol: farTolerance, exact: exact)
        if buf.count - before < near - from {
            farSkip = (near - from) / 8
            farGround = Array(UnsafeBufferPointer(start: buf.ptr + before, count: buf.count - before))
            tally.lock(); farIn += (near - from) / 8; farOut += farGround.count / 8; tally.unlock()
        }
        buf.count = before
        return removed
    }
    static var farIn = 0, farOut = 0
    // P383 step 3: how far what a vertex shades by may drift where a collapse joins different ones (see the header).
    static var lightTol: Double = Double(ProcessInfo.processInfo.environment["BS_ADAPTIVE_LIGHT"] ?? "") ?? 1.0
    static var aoTol: Double = Double(ProcessInfo.processInfo.environment["BS_ADAPTIVE_AO"] ?? "") ?? 0.5
    static var matTol: Double = Double(ProcessInfo.processInfo.environment["BS_ADAPTIVE_MAT"] ?? "") ?? 0.6
    // BS_ADAPTIVE_SEAMS=0: collapse only between equal attributes (P381's rule, before/after numbers).
    static var joinSeams = ProcessInfo.processInfo.environment["BS_ADAPTIVE_SEAMS"] != "0"
    // P383 step 2 tallies (near pass): ground positions, and those drawn with two or more different vertices.
    static var positions = 0, splitPositions = 0
    // questcheck --adaptivecheck: the main thread's last near and far results at their exact positions (3 points a triangle).
    static var capture = false
    static var captured: ([SIMD3<Float>], [SIMD3<Float>]) = ([], [])
    static var capturedBlob: ([SIMD3<Float>], [SIMD3<Float>]) = ([], [])

    // Closest point of triangle abc to p (Ericson 5.1.5) as its distance and barycentric weights.
    static func closestBary(_ p: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> (Double, SIMD3<Double>) {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return (simd_length(ap), SIMD3(1, 0, 0)) }
        let bp = p - b
        let d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return (simd_length(bp), SIMD3(0, 1, 0)) }
        let vc: Double = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 { let t = d1 / (d1 - d3); return (simd_length(ap - ab * t), SIMD3(1 - t, t, 0)) }
        let cp = p - c
        let d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return (simd_length(cp), SIMD3(0, 0, 1)) }
        let vb: Double = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 { let t = d2 / (d2 - d6); return (simd_length(ap - ac * t), SIMD3(1 - t, 0, t)) }
        let va: Double = d3 * d6 - d5 * d4
        if va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0 {
            let t = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return (simd_length(bp - (c - b) * t), SIMD3(0, 1 - t, t))
        }
        let den = 1 / (va + vb + vc)
        let v = vb * den, w = vc * den
        return (simd_length(ap - ab * v - ac * w), SIMD3(1 - v - w, v, w))
    }

    // The ground's guard (P383 step 3): light within lightTol, occlusion within aoTol, own material at least matTol.
    struct GroundGuard: CollapseGuard {
        let words: [UInt64]
        let seams: Bool
        let lTol = AdaptiveGround.lightTol + 1e-9, oTol = AdaptiveGround.aoTol + 1e-9, mTol = AdaptiveGround.matTol - 1e-9
        static let attrMask: UInt64 = (UInt64(0xF8000000) << 32) | UInt64(0xFFFF_FFFF & ~(UInt32(0x3E0) | (1 << 30)))
        @inline(__always) func same(_ a: Int, _ b: Int) -> Bool { seams || words[a] & GroundGuard.attrMask == words[b] & GroundGuard.attrMask }
        @inline(__always) func sky(_ i: Int) -> Double { Double((words[i] >> 22) & 15) }
        @inline(__always) func blk(_ i: Int) -> Double { Double((words[i] >> 26) & 15) }
        @inline(__always) func occ(_ i: Int) -> Double { Double((words[i] >> 20) & 3) }
        @inline(__always) func mat(_ i: Int) -> UInt64 { (words[i] & 0x800F_FC00) | (words[i] >> 62) << 40 }
        func holds(_ qi: Int, _ t: SIMD3<Int32>, _ w: SIMD3<Double>) -> Bool {
            let a = Int(t[0]), b = Int(t[1]), c = Int(t[2])
            let ls: Double = w[0] * sky(a) + w[1] * sky(b) + w[2] * sky(c)
            if abs(ls - sky(qi)) > lTol { return false }
            let lb: Double = w[0] * blk(a) + w[1] * blk(b) + w[2] * blk(c)
            if abs(lb - blk(qi)) > lTol { return false }
            let lo: Double = w[0] * occ(a) + w[1] * occ(b) + w[2] * occ(c)
            if abs(lo - occ(qi)) > oTol { return false }
            let m = mat(qi)
            let w0: Double = mat(a) == m ? w[0] : 0
            let w1: Double = mat(b) == m ? w[1] : 0
            let w2: Double = mat(c) == m ? w[2] : 0
            return w0 + w1 + w2 >= mTol
        }
    }

    // The collapse (P381; see the header) on any triangle mesh: exact positions, positions as drawn (`grid`), triangles.
    // Returns the triangles left.
    static func collapse<G: CollapseGuard>(pos: [SIMD3<Double>], grid: [SIMD3<Double>], tris: [SIMD3<Int32>], tol: Float, guard g: G) -> [SIMD3<Int32>] {
        let nv = pos.count, nt0 = tris.count
        var tris = tris
        // Edges: count the triangles on each; an edge on one (the mesh's edge) or more than two locks its vertices.
        var edgeCount: [UInt64: Int32] = [:]
        edgeCount.reserveCapacity(nt0 * 3)
        @inline(__always) func ekey(_ a: Int32, _ b: Int32) -> UInt64 { a < b ? UInt64(a) << 32 | UInt64(b) : UInt64(b) << 32 | UInt64(a) }
        for t in tris { for k in 0..<3 { edgeCount[ekey(t[k], t[(k + 1) % 3]), default: 0] += 1 } }
        var locked = [Bool](repeating: false, count: nv)
        for (e, c) in edgeCount where c != 2 { locked[Int(e >> 32)] = true; locked[Int(e & 0xFFFF_FFFF)] = true }
        // Each vertex's triangles and quadric (the planes of its triangles).
        var vt = [[Int32]](repeating: [], count: nv)
        var Q = [Quadric](repeating: Quadric(), count: nv)
        var planes = [Double](repeating: 0, count: nv)
        // The original vertices each vertex stands for (collapsed into it): every one stays within the bound.
        var absorbed = [[Int32]](repeating: [], count: nv)
        var alive = [Bool](repeating: true, count: tris.count)
        func normal(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> SIMD3<Double> { simd_cross(b - a, c - a) }
        for (ti, t) in tris.enumerated() {
            let n = normal(pos[Int(t[0])], pos[Int(t[1])], pos[Int(t[2])])
            let len = simd_length(n)
            guard len > 1e-9 else { alive[ti] = false; continue }
            let un = n / len, d = -simd_dot(un, pos[Int(t[0])])
            for k in 0..<3 { vt[Int(t[k])].append(Int32(ti)); Q[Int(t[k])].add(un, d); planes[Int(t[k])] += 1 }
        }
        let tol2 = Double(tol * tol), tolD = Double(tol)
        // The original triangles (the full ground) round each vertex, for measuring new triangles against.
        let tris0 = tris, vt0 = vt
        var stamp = [Int32](repeating: -1, count: tris0.count), stampNow: Int32 = 0
        var orig: [Int32] = []
        var fan: [SIMD3<Int32>] = []
        var gone = [Bool](repeating: false, count: nv)
        // Neighbours of a vertex (through its live triangles).
        // (reused arrays: a ring is a handful of vertices, and a Set per attempt cost more than the search)
        var rv: [Int32] = [], ru: [Int32] = []
        func ring(_ v: Int, _ out: inout [Int32]) {
            out.removeAll(keepingCapacity: true)
            for ti in vt[v] where alive[Int(ti)] {
                let t = tris[Int(ti)]
                for k in 0..<3 where t[k] != Int32(v) && !out.contains(t[k]) { out.append(t[k]) }
            }
        }
        // Collapse v into u when it keeps every bound; true when done.
        func collapse(_ v: Int, into u: Int) -> Bool {
            guard !gone[v] && !gone[u] && !locked[v], g.same(v, u) else { return false }
            guard Q[v].error(pos[u]) <= tol2 * planes[v], absorbed[v].count + absorbed[u].count < maxAbsorbed else { return false }
            ring(v, &rv); ring(u, &ru)
            guard rv.contains(Int32(u)) else { return false }
            // Link condition: the edge's two triangles are the only ones its ends share (keeps the mesh a manifold).
            var shared = 0
            for ti in vt[v] where alive[Int(ti)] { let t = tris[Int(ti)]; if t[0] == Int32(u) || t[1] == Int32(u) || t[2] == Int32(u) { shared += 1 } }
            var common = 0
            for w in rv where ru.contains(w) { common += 1 }
            guard shared == 2, common == 2 else { return false }
            // No triangle turns over or folds flat.
            for ti in vt[v] where alive[Int(ti)] {
                let t = tris[Int(ti)]
                if t[0] == Int32(u) || t[1] == Int32(u) || t[2] == Int32(u) { continue }
                var a = pos[Int(t[0])], b = pos[Int(t[1])], c = pos[Int(t[2])]
                let n0 = simd_normalize(normal(a, b, c))
                if t[0] == Int32(v) { a = pos[u] } else if t[1] == Int32(v) { b = pos[u] } else { c = pos[u] }
                let n1 = normal(a, b, c)
                let l1 = simd_length(n1)
                if l1 < 1e-6 || simd_dot(n0, n1 / l1) < 0.5 { return false }
                // ...nor as drawn, on the 1/16 grid (a sliver drawn flat is fine; one drawn turned over is a hole).
                let gs = normal(t[0] == Int32(v) ? grid[u] : grid[Int(t[0])], t[1] == Int32(v) ? grid[u] : grid[Int(t[1])],
                                t[2] == Int32(v) ? grid[u] : grid[Int(t[2])])
                if simd_dot(gs, n1) < 0 { return false }
                // No triangle may become one already there (a closed lump, a pebble of ground, would fold up and go).
                var o0 = t[0] == Int32(v) ? Int32(u) : t[0], o1 = t[1] == Int32(v) ? Int32(u) : t[1], o2 = t[2] == Int32(v) ? Int32(u) : t[2]
                if o0 > o1 { swap(&o0, &o1) }; if o1 > o2 { swap(&o1, &o2) }; if o0 > o1 { swap(&o0, &o1) }
                for tj in vt[u] where alive[Int(tj)] {
                    let s = tris[Int(tj)]
                    var s0 = s[0], s1 = s[1], s2 = s[2]
                    if s0 > s1 { swap(&s0, &s1) }; if s1 > s2 { swap(&s1, &s2) }; if s0 > s1 { swap(&s0, &s1) }
                    if s0 == o0 && s1 == o1 && s2 == o2 { return false }
                }
            }
            // The bound, measured: v and every vertex v and u stand for lie within it of u's new fan (the quadrics
            // only rank the candidates: a sum over planes is too strict on ground snapped to the 1/16 grid, and planes
            // run on past their triangles).
            fan.removeAll(keepingCapacity: true)
            for ti in vt[u] where alive[Int(ti)] {
                let t = tris[Int(ti)]
                if t[0] == Int32(v) || t[1] == Int32(v) || t[2] == Int32(v) { continue }
                fan.append(t)
            }
            let changed = fan.count
            for ti in vt[v] where alive[Int(ti)] {
                let t = tris[Int(ti)]
                if t[0] == Int32(u) || t[1] == Int32(u) || t[2] == Int32(u) { continue }
                fan.append(SIMD3<Int32>(t[0] == Int32(v) ? Int32(u) : t[0], t[1] == Int32(v) ? Int32(u) : t[1], t[2] == Int32(v) ? Int32(u) : t[2]))
            }
            // Within the bound of the fan, and (joining across seams) drawn true to what vertex q shades by: the nearest
            // fan triangle's corners, weighted where q lies on it.
            func near(_ qi: Int) -> Bool {
                let q = pos[qi]
                var bestD = Double.infinity, bestT = SIMD3<Int32>(0, 0, 0), bestB = SIMD3<Double>(0, 0, 0)
                for f in fan {
                    let (d, b) = closestBary(q, pos[Int(f[0])], pos[Int(f[1])], pos[Int(f[2])])
                    if d < bestD { bestD = d; bestT = f; bestB = b }
                    // (q over a triangle's inside within the bound: that triangle draws it; no need to look further)
                    if d <= tolD && (!g.seams || b[0] > 0 && b[1] > 0 && b[2] > 0) { break }
                }
                guard bestD <= tolD else { return false }
                return !g.seams || g.holds(qi, bestT, bestB)
            }
            guard near(v) else { return false }
            for q in absorbed[v] where !near(Int(q)) { return false }
            for q in absorbed[u] where !near(Int(q)) { return false }
            // The ring's vertices lose v's triangles too: what they stand for stays within the bound of their own new
            // fans (their triangles without v, and those of the new fan).
            let mark = fan.count
            for w in rv where Int(w) != u && !absorbed[Int(w)].isEmpty {
                fan.removeSubrange(mark...)
                for ti in vt[Int(w)] where alive[Int(ti)] {
                    let t = tris[Int(ti)]
                    if t[0] == Int32(v) || t[1] == Int32(v) || t[2] == Int32(v) { continue }
                    fan.append(t)
                }
                for q in absorbed[Int(w)] where !near(Int(q)) { return false }
            }
            // And every new triangle lies within the bound of the full ground there (corners, edge middles, centre
            // against the original triangles round the vertices it stands for).
            stampNow += 1; orig.removeAll(keepingCapacity: true)
            func addOrig(_ x: Int) { for ti in vt0[x] where stamp[Int(ti)] != stampNow { stamp[Int(ti)] = stampNow; orig.append(ti) } }
            addOrig(v); addOrig(u)
            for q in absorbed[v] { addOrig(Int(q)) }
            for q in absorbed[u] { addOrig(Int(q)) }
            for w in rv { addOrig(Int(w)); for q in absorbed[Int(w)] { addOrig(Int(q)) } }
            @inline(__always) func onGround(_ q: SIMD3<Double>) -> Bool {
                for ti in orig {
                    let t = tris0[Int(ti)]
                    if pointTriangle(q, pos[Int(t[0])], pos[Int(t[1])], pos[Int(t[2])]) <= tolD { return true }
                }
                return false
            }
            for t in fan[changed..<mark] {
                let f = (pos[Int(t[0])], pos[Int(t[1])], pos[Int(t[2])])
                let c = (f.0 + f.1 + f.2) / 3
                guard onGround(c), onGround((f.0 + f.1) / 2), onGround((f.1 + f.2) / 2), onGround((f.0 + f.2) / 2) else { return false }
            }
            for ti in vt[v] where alive[Int(ti)] {
                var t = tris[Int(ti)]
                if t[0] == Int32(u) || t[1] == Int32(u) || t[2] == Int32(u) { alive[Int(ti)] = false; continue }
                for k in 0..<3 where t[k] == Int32(v) { t[k] = Int32(u) }
                tris[Int(ti)] = t
                vt[u].append(ti)
            }
            Q[u] += Q[v]; planes[u] += planes[v]
            absorbed[u].append(Int32(v)); absorbed[u] += absorbed[v]
            gone[v] = true
            return true
        }
        // Cheapest first, a few passes (costs change as vertices go).
        for _ in 0..<6 {
            var cand: [(Double, Int32, Int32)] = []
            for (ti, t) in tris.enumerated() where alive[ti] {
                for k in 0..<3 {
                    let a = Int(t[k]), b = Int(t[(k + 1) % 3])
                    if !locked[a] && g.same(a, b) { cand.append((Q[a].error(pos[b]) / planes[a], Int32(a), Int32(b))) }
                    if !locked[b] && g.same(a, b) { cand.append((Q[b].error(pos[a]) / planes[b], Int32(b), Int32(a))) }
                }
            }
            cand.sort { $0.0 < $1.0 }
            var done = 0
            for (c, v, u) in cand where c <= tol2 { if collapse(Int(v), into: Int(u)) { done += 1 } }
            if done == 0 { break }
        }
        var live: [SIMD3<Int32>] = []
        for (ti, t) in tris.enumerated() where alive[ti] { live.append(t) }
        return live
    }

    // Triangles paired into quads across a shared edge (a lone triangle: a quad with its last corner repeated).
    static func pairQuads(_ live: [SIMD3<Int32>]) -> [SIMD4<Int32>] {
        var directed: [UInt64: Int32] = [:]
        directed.reserveCapacity(live.count * 3)
        for (i, t) in live.enumerated() { for k in 0..<3 { directed[UInt64(t[k]) << 32 | UInt64(t[(k + 1) % 3])] = Int32(i) } }
        var used = [Bool](repeating: false, count: live.count)
        var out: [SIMD4<Int32>] = []
        out.reserveCapacity(live.count / 2 + 1)
        for (i, t) in live.enumerated() where !used[i] {
            used[i] = true
            var quad = SIMD4<Int32>(t[0], t[1], t[2], t[2])
            for r in 0..<3 {
                let a = t[r], b = t[(r + 1) % 3], c = t[(r + 2) % 3]
                // The triangle across c -> a holds a -> c: (a, c, d).
                guard let j = directed[UInt64(a) << 32 | UInt64(c)], !used[Int(j)] else { continue }
                let y = live[Int(j)]
                var d: Int32 = -1
                for k in 0..<3 where y[k] != a && y[k] != c { d = y[k] }
                guard d >= 0 else { continue }
                used[Int(j)] = true
                quad = SIMD4<Int32>(a, b, c, d)
                break
            }
            out.append(quad)
        }
        return out
    }

    // Simplifies the ground quads in buf[from..<buf.count] (2 words a vertex, 4 vertices a quad) in place. Returns
    // the number of quads removed.
    @discardableResult
    static func simplify(_ buf: GrowBuf<UInt32>, from: Int, tol: Float, exact: UnsafePointer<Float>? = nil, capture capt: Bool = true,
                         blob: Bool = false) -> Int {
        let nq = (buf.count - from) / 8
        guard nq >= 4 else { return 0 }
        let p = buf.ptr + from
        // Vertices by their full words (position, tint, layer, light, occlusion, normal; facing too when not triGround).
        // (with exact positions, by those too: two vertices the 1/16 grid draws at one place are still two)
        struct VKey: Hashable { let w: UInt64; let x: UInt32, y: UInt32, z: UInt32 }
        var index: [VKey: Int32] = [:]
        index.reserveCapacity(nq * 2)
        var words: [UInt64] = [], pos: [SIMD3<Double>] = [], grid: [SIMD3<Double>] = []
        words.reserveCapacity(nq * 2); pos.reserveCapacity(nq * 2); grid.reserveCapacity(nq * 2)
        // (step 2's tally: positions by their snapped place, and whether one is drawn with different words)
        let tallyPos = tol == tolerance
        var perPos: [UInt32: UInt64] = [:]
        var splitPos = Set<UInt32>()
        func vid(_ w0: UInt32, _ w1: UInt32, _ e: Int) -> Int32 {
            let key = UInt64(w0) << 32 | UInt64(w1)
            let ex = exact
            let k = VKey(w: key, x: ex?[e * 3].bitPattern ?? 0, y: ex?[e * 3 + 1].bitPattern ?? 0, z: ex?[e * 3 + 2].bitPattern ?? 0)
            if let i = index[k] { return i }
            let i = Int32(words.count)
            index[k] = i; words.append(key)
            if tallyPos {
                let pk = w0 & 0x07FF_FFFF
                if let o = perPos[pk] { if o != key { splitPos.insert(pk) } } else { perPos[pk] = key }
            }
            let g = SIMD3<Double>(Double(w0 & 511), Double((w0 >> 9) & 511), Double((w0 >> 18) & 511)) / 16
            grid.append(g)
            if let ex { pos.append(SIMD3<Double>(Double(ex[e * 3]), Double(ex[e * 3 + 1]), Double(ex[e * 3 + 2]))) } else { pos.append(g) }
            return i
        }
        var tris: [SIMD3<Int32>] = []
        tris.reserveCapacity(nq * 2)
        for q in 0..<nq {
            var v = SIMD4<Int32>(repeating: 0)
            for k in 0..<4 { v[k] = vid(p[q * 8 + k * 2], p[q * 8 + k * 2 + 1], q * 4 + k) }
            if v[0] != v[1] && v[1] != v[2] && v[0] != v[2] { tris.append(SIMD3(v[0], v[1], v[2])) }
            if v[0] != v[2] && v[2] != v[3] && v[0] != v[3] { tris.append(SIMD3(v[0], v[2], v[3])) }
        }
        if tallyPos { tally.lock(); positions += perPos.count; splitPositions += splitPos.count; tally.unlock() }
        let live = collapse(pos: pos, grid: grid, tris: tris, tol: tol, guard: GroundGuard(words: words, seams: joinSeams))
        let out = pairQuads(live)
        let nt0 = tris.count
        // (questcheck --farcheck, P384: a leaf blob's far shell and the shell it stands for, at their exact positions)
        if capture && blob && Thread.isMainThread {
            for t in tris { for k in 0..<3 { capturedBlob.0.append(SIMD3<Float>(pos[Int(t[k])])) } }
            for t in (out.count < nq ? live : tris) { for k in 0..<3 { capturedBlob.1.append(SIMD3<Float>(pos[Int(t[k])])) } }
        }
        // Written back over the old quads (never more of them).
        guard out.count < nq else { return 0 }
        var w = 0
        for q in out { for k in 0..<4 { let key = words[Int(q[k])]; p[w] = UInt32(key >> 32); p[w + 1] = UInt32(key & 0xFFFF_FFFF); w += 2 } }
        buf.count = from + w
        if tol == tolerance { tally.lock(); trisIn += nt0; trisOut += live.count; tally.unlock() }
        // (questcheck --adaptivecheck, on the main thread: the triangles left, at their exact positions)
        if capture && capt && Thread.isMainThread {
            var t: [SIMD3<Float>] = []
            for q in live { for k in 0..<3 { t.append(SIMD3<Float>(pos[Int(q[k])])) } }
            if tol == tolerance { captured.0 = t } else { captured.1 = t }
        }
        return nq - out.count
    }
}
