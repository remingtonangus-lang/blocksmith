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

    static func check(_ vw: World, eye: V3) -> String {
        let pcx = floorDiv(Int(floor(eye.x)), CS), pcz = floorDiv(Int(floor(eye.z)), CS)
        var msFull = 0.0, msAd = 0.0, trisFull = 0, trisAd = 0, quadsFull = 0, quadsAd = 0, sections = 0
        var worstA: Float = 0, worstB: Float = 0, overA = 0, overB = 0, pointsA = 0, pointsB = 0
        var crackEdges = 0
        let tol = AdaptiveGround.tolerance + 1.0 / 512          // (positions are on the 1/16 grid: float slack)
        for dz in -2...2 { for dx in -2...2 {
            guard let c = vw.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)], let nb = vw.neighbourhood(c) else { continue }
            for sy in 0..<NSEC {
                var t0 = CFAbsoluteTimeGetCurrent()
                let full = Mesher.buildSection(nb.0, nb.1, sy: sy, chunk: (c.cx, c.cz), adaptive: false)
                msFull += (CFAbsoluteTimeGetCurrent() - t0) * 1000
                t0 = CFAbsoluteTimeGetCurrent()
                let ad = Mesher.buildSection(nb.0, nb.1, sy: sy, chunk: (c.cx, c.cz), adaptive: true)
                msAd += (CFAbsoluteTimeGetCurrent() - t0) * 1000
                let tf = groundTris(full), ta = groundTris(ad)
                guard !tf.isEmpty else { continue }
                if let dir = ProcessInfo.processInfo.environment["BS_ADAPTIVE_DUMP"] {      // (the full ground, for tuning offline)
                    let words = Array(full.opaque.prefix(full.groundQuads * 8))
                    let data = words.withUnsafeBufferPointer { Data(buffer: $0) }
                    try? data.write(to: URL(fileURLWithPath: "\(dir)/s\(sections).bin"))
                }
                sections += 1
                trisFull += tf.count; trisAd += ta.count; quadsFull += full.groundQuads; quadsAd += ad.groundQuads
                let ga = Grid(ta), gf = Grid(tf)
                for t in tf { for p in [t.0, t.1, t.2] {
                    let d = ga.near(p); pointsA += 1
                    worstA = max(worstA, d); if d > tol { overA += 1 }
                } }
                for t in ta {
                    let ps = [t.0, t.1, t.2, (t.0 + t.1) / 2, (t.1 + t.2) / 2, (t.0 + t.2) / 2, (t.0 + t.1 + t.2) / 3]
                    for p in ps { let d = gf.near(p); pointsB += 1; worstB = max(worstB, d); if d > tol { overB += 1 } }
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
                crackEdges += borders(ta).symmetricDifference(borders(tf)).count
            }
        } }
        return String(format: "adaptivecheck: %d sections; ground %d -> %d triangles (%d -> %d quads, %.1f%%); full ground to adaptive: worst %.4f block, %d of %d points over %.3f; adaptive to full ground: worst %.4f, %d of %d over; border edges differing %d; mesh %.1f ms full, %.1f ms adaptive",
                      sections, trisFull, trisAd, quadsFull, quadsAd, Double(quadsAd) * 100 / Double(max(1, quadsFull)),
                      worstA, overA, pointsA, AdaptiveGround.tolerance, worstB, overB, pointsB, crackEdges, msFull, msAd)
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
            for s in (sy - 1)...(sy + 1) {
                for t in tris(cx, cz, s, adaptive) {
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
            }
            return best
        }
        let start = g.player.pos
        var gaps: [[Float]] = [[], []]
        for k in 0..<8 {
            g.player.pos = start; g.player.vel = .zero; g.player.flying = false
            g.player.yaw = Float(k) * .pi / 4
            for _ in 0..<60 { g.player.update(dt: 1.0 / 30, input: MoveInput(), world: w) }
            for f in 0..<120 {
                g.player.update(dt: 1.0 / 30, input: MoveInput(forward: 1), world: w)
                guard f % 3 == 0, g.player.onGround, w.fieldNear(g.player.pos) else { continue }
                let p = g.player.pos
                for (i, ad) in [false, true].enumerated() { if let h = drawn(p.x, p.y, p.z, ad), abs(h - p.y) < 1 { gaps[i].append(p.y - h) } }
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
                for s in (sy - 1)...(sy + 1) { for t in tris(cx, cz, s, ad) { best = min(best, AdaptiveGround.dist(h.at, t)) } }
                if best < 9 { hits[i].append(best) }
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
    }
}
