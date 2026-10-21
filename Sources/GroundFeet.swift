import Foundation
import simd

// P386 (Remington, Oct 20, "feet and aim on the drawn ground"): in a field world the ground the player sees is the
// section meshes' ground triangles (adaptive since P381), not the field's collision columns. Bodies stood on the columns
// (quarter-block steps under the middle of the body, the trilinear field's height rather than the drawn one) and rays
// stopped where the field crossed zero, so feet hung or sank up to half a block and dig/place hits landed off the
// surface. Each near section now keeps its drawn ground triangles (positions only, bucketed by column), built by the
// mesher with the mesh; bodies stand on them under their middle and rays stop on them.
final class GroundTris {
    // BS_FEET=0: bodies and rays on the field as before P386 (before/after checks).
    static let feetOn = ProcessInfo.processInfo.environment["BS_FEET"] != "0"
    private static let N = 20                         // columns -2...17 (a section's ground reaches past its own cells)
    private(set) var pos: [UInt32] = []               // 4 packed positions per quad (1/16 block: x | y << 9 | z << 18)
    private var start = [UInt32](repeating: 0, count: GroundTris.N * GroundTris.N + 1)
    private var list: [UInt16] = []                   // quad indices per column, start[k]..<start[k + 1]
    var quads: Int { pos.count / 4 }
    var bytes: Int { pos.count * 4 + list.count * 2 + start.count * 4 }

    // The ground quads in buf[from..<to] (words: 4 vertices of 2 words each, lone triangles as (a, b, c, c)).
    init?(_ buf: UnsafeMutablePointer<UInt32>, from g0: Int, to g1: Int) {
        let n = (g1 - g0) / 8
        guard n > 0 && n < 65536 else { return nil }
        pos.reserveCapacity(n * 4)
        var count = [UInt32](repeating: 0, count: GroundTris.N * GroundTris.N)
        @inline(__always) func span(_ q: Int) -> (Int, Int, Int, Int) {
            var x0 = 1 << 20, x1 = -(1 << 20), z0 = 1 << 20, z1 = -(1 << 20)
            for k in 0..<4 {
                let w = pos[q * 4 + k]
                let x = Int(w & 511), z = Int((w >> 18) & 511)
                x0 = min(x0, x); x1 = max(x1, x); z0 = min(z0, z); z1 = max(z1, z)
            }
            // (a corner on a column's west or north line belongs to the column too: (x - 1) >> 4 for the low side)
            return (max(-2, (x0 - 1) >> 4), min(17, x1 >> 4), max(-2, (z0 - 1) >> 4), min(17, z1 >> 4))
        }
        for q in 0..<n {
            for k in 0..<4 { pos.append(buf[g0 + q * 8 + k * 2] & 0x7FFFFFF) }
            let (x0, x1, z0, z1) = span(q)
            guard x0 <= x1 && z0 <= z1 else { continue }
            for z in z0...z1 { for x in x0...x1 { count[(x + 2) + (z + 2) * GroundTris.N] += 1 } }
        }
        var s: UInt32 = 0
        for k in 0..<count.count { start[k] = s; s += count[k] }
        start[count.count] = s
        list = [UInt16](repeating: 0, count: Int(s))
        var fill = Array(start.dropLast())
        for q in 0..<n {
            let (x0, x1, z0, z1) = span(q)
            guard x0 <= x1 && z0 <= z1 else { continue }
            for z in z0...z1 { for x in x0...x1 {
                let k = (x + 2) + (z + 2) * GroundTris.N
                list[Int(fill[k])] = UInt16(q); fill[k] += 1
            } }
        }
    }

    @inline(__always) private func p(_ q: Int, _ k: Int) -> SIMD3<Float> {
        let w = pos[q * 4 + k]
        return SIMD3<Float>(Float(w & 511), Float((w >> 9) & 511), Float((w >> 18) & 511)) * (1.0 / 16)
    }

    // The highest up-facing drawn ground (section-local blocks) at (x, z) in [lo, hi]; nil if none.
    func height(_ x: Float, _ z: Float, lo: Float, hi: Float) -> Float? {
        let cx = Int(floor(x)), cz = Int(floor(z))
        guard cx >= -2 && cx <= 17 && cz >= -2 && cz <= 17 else { return nil }
        let k = (cx + 2) + (cz + 2) * GroundTris.N
        var best: Float = -.greatestFiniteMagnitude
        // (barycentric in x, z; up-facing only: corners counter-clockwise seen from above)
        @inline(__always) func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ e: SIMD3<Float>) {
            let ny = (b.z - a.z) * (e.x - a.x) - (b.x - a.x) * (e.z - a.z)
            guard ny > 1e-6 else { return }
            let den = (b.z - e.z) * (a.x - e.x) + (e.x - b.x) * (a.z - e.z)
            if abs(den) < 1e-9 { return }
            let u = ((b.z - e.z) * (x - e.x) + (e.x - b.x) * (z - e.z)) / den
            let v = ((e.z - a.z) * (x - e.x) + (a.x - e.x) * (z - e.z)) / den
            let w = 1 - u - v
            let tol: Float = -1e-4
            guard u >= tol && v >= tol && w >= tol else { return }
            let y = u * a.y + v * b.y + w * e.y
            if y >= lo && y <= hi && y > best { best = y }
        }
        for j in Int(start[k])..<Int(start[k + 1]) {
            let q = Int(list[j])
            let a = p(q, 0), c = p(q, 2)
            tri(a, p(q, 1), c)
            tri(a, c, p(q, 3))            // (a lone triangle's second half (a, c, c) has no area: skipped)
        }
        return best > -.greatestFiniteMagnitude ? best : nil
    }

    // The nearest drawn ground triangle facing the ray (section-local origin o, direction d) with t in [t0, t1]: its t
    // and the triangle's normal.
    func ray(_ o: SIMD3<Float>, _ d: SIMD3<Float>, _ t0: Float, _ t1: Float) -> (Float, SIMD3<Float>)? {
        var bestT = t1, bestN = SIMD3<Float>(0, 1, 0), found = false
        // (the columns the segment crosses, walked at quarter-block steps)
        let len = max(0, t1 - t0)
        let steps = max(1, Int(ceil(len * 4)))
        var lastK = -1
        // Moller-Trumbore, front faces only (corners counter-clockwise from outside)
        @inline(__always) func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ e: SIMD3<Float>) {
            let e1 = b - a, e2 = e - a
            let n = simd_cross(e1, e2)
            guard simd_dot(n, d) < 0 else { return }
            let h = simd_cross(d, e2), det = simd_dot(e1, h)
            if abs(det) < 1e-9 { return }
            let f = 1 / det, s0 = o - a
            let u = f * simd_dot(s0, h)
            guard u >= -1e-4 && u <= 1 + 1e-4 else { return }
            let qv = simd_cross(s0, e1)
            let v = f * simd_dot(d, qv)
            guard v >= -1e-4 && u + v <= 1 + 1e-4 else { return }
            let t = f * simd_dot(e2, qv)
            if t >= t0 && t <= bestT { bestT = t; bestN = simd_normalize(n); found = true }
        }
        for s in 0...steps {
            let q0 = o + d * (t0 + len * Float(s) / Float(steps))
            let cx = Int(floor(q0.x)), cz = Int(floor(q0.z))
            guard cx >= -2 && cx <= 17 && cz >= -2 && cz <= 17 else { continue }
            let k = (cx + 2) + (cz + 2) * GroundTris.N
            if k == lastK { continue }
            lastK = k
            for j in Int(start[k])..<Int(start[k + 1]) {
                let q = Int(list[j])                // (a quad in several columns is tested again: harmless)
                let a = p(q, 0), c = p(q, 2)
                tri(a, p(q, 1), c)
                tri(a, c, p(q, 3))
            }
        }
        return found ? (bestT, bestN) : nil
    }
}

extension World {
    // The drawn ground's height at (x, z) between lo and hi (world blocks), from the sections that draw it (the column's
    // own chunk, and the chunks to its -x / -z, which draw a chunk's first block row). Nil where a section that could
    // hold it has no current ground triangles (not meshed yet, re-meshing after an edit, far): callers fall back to the
    // field.
    func drawnGround(_ x: Float, _ z: Float, lo: Float, hi: Float, check: Bool = true) -> Float? {
        guard GroundTris.feetOn, fieldTerrain, frame == nil, hi >= lo, lo < Float(CH), hi > 0 else { return nil }
        let bx = Int(floor(x)), bz = Int(floor(z))
        let cx = floorDiv(bx, CS), cz = floorDiv(bz, CS)
        let lx = x - Float(cx * CS), lz = z - Float(cz * CS)
        // (a section's ground reaches up to a block past its own cells, up and down and sideways)
        let sy0 = max(0, (Int(floor(lo)) - 1) >> 4), sy1 = min(NSEC - 1, (Int(floor(hi)) + 1) >> 4)
        guard sy0 <= sy1 else { return nil }
        var best: Float? = nil
        let ox0 = lx < 2.5 ? -1 : 0, ox1 = lx > 13.5 ? 1 : 0, oz0 = lz < 2.5 ? -1 : 0, oz1 = lz > 13.5 ? 1 : 0
        for oz in oz0...oz1 { for ox in ox0...ox1 {
            guard let c = chunks[ChunkKey(x: cx + ox, z: cz + oz)] else { if ox == 0 && oz == 0 { return nil }; continue }
            let px = lx - Float(ox * CS), pz = lz - Float(oz * CS)
            for sy in sy0...sy1 {
                let s = c.sections[sy]
                guard let g = s.ground else { continue }
                let b = Float(sy * 16)
                if let h = g.height(px, pz, lo: lo - b, hi: hi - b) { best = max(best ?? -.greatestFiniteMagnitude, h + b) }
            }
        } }
        // (the mesh may lag an edit by a frame or two (the world's own changes remesh on the workers): ground blown or dug
        // away under it shows in the field first)
        if check, let h = best, fieldDensity(at: V3(x, h - 0.25, z)) <= 0 && fieldDensity(at: V3(x, h - 0.5, z)) <= 0 { return nil }
        return best
    }

    // The nearest drawn ground the ray o + d t meets for t in [t0, t1] (world blocks): t, the point, the face normal.
    func drawnRay(_ o: V3, _ d: V3, from t0: Float, to t1: Float) -> (t: Float, at: V3, normal: V3)? {
        guard GroundTris.feetOn, fieldTerrain, frame == nil, t1 > t0 else { return nil }
        let a = o + d * t0, b = o + d * t1
        let x0 = floorDiv(Int(floor(min(a.x, b.x))) - 1, CS), x1 = floorDiv(Int(floor(max(a.x, b.x))) + 1, CS)
        let z0 = floorDiv(Int(floor(min(a.z, b.z))) - 1, CS), z1 = floorDiv(Int(floor(max(a.z, b.z))) + 1, CS)
        let s0 = max(0, (Int(floor(min(a.y, b.y))) - 1) >> 4), s1 = min(NSEC - 1, (Int(floor(max(a.y, b.y))) + 1) >> 4)
        guard s0 <= s1 else { return nil }
        var best: (t: Float, at: V3, normal: V3)? = nil
        for cz in z0...z1 { for cx in x0...x1 {
            guard let c = chunks[ChunkKey(x: cx, z: cz)] else { continue }
            for sy in s0...s1 {
                guard let g = c.sections[sy].ground else { continue }
                let off = V3(Float(cx * CS), Float(sy * 16), Float(cz * CS))
                if let (t, n) = g.ray(o - off, d, t0, best?.t ?? t1) { best = (t, o + d * t, n) }
            }
        } }
        return best
    }

    // The way down drawn ground steeper than 50 degrees under a body standing at p (x, z: a unit vector), else nil.
    func steepDrawnGround(_ p: V3) -> SIMD2<Float>? {
        guard fieldTerrain && GroundTris.feetOn else { return nil }
        let r: Float = 0.2
        guard let x0 = drawnGround(p.x - r, p.z, lo: p.y - 0.6, hi: p.y + 0.6), let x1 = drawnGround(p.x + r, p.z, lo: p.y - 0.6, hi: p.y + 0.6),
              let z0 = drawnGround(p.x, p.z - r, lo: p.y - 0.6, hi: p.y + 0.6), let z1 = drawnGround(p.x, p.z + r, lo: p.y - 0.6, hi: p.y + 0.6)
        else { return nil }
        let g = SIMD2<Float>(x1 - x0, z1 - z0) / (2 * r)
        let m = simd_length(g)
        return m > 1.19 ? -g / m : nil
    }
}
