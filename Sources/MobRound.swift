import Foundation
import simd

// P366 (a) (Oct 17 15:33: "characters still look blocky, a chicken"): near mobs (MobDetail level 0, inside 20 blocks)
// draw each body part as a rounded box instead of a cube: every edge bevelled and every corner cut (a chamfered box,
// 22 faces), shaded with normals that turn smoothly round the edges, so bodies, heads and limbs read as soft forms.
// Machines (soldiers' plate past the rig, vehicles, polished metal and glass parts) keep their sharp boxes.
enum MobRound {
    // 24 points: point i = corner (i / 3) (bits x, y, z) pulled in along the two axes other than (i % 3), so it lies on
    // that axis's face. Triangles (outward, as Mesher.cornerTable) over the 6 inset faces, 12 edge bevels, 8 corners.
    static let tris: [Int] = {
        func pos(_ i: Int) -> V3 {
            let c = i / 3, a = i % 3
            var p = V3(Float(c & 1), Float((c >> 1) & 1), Float((c >> 2) & 1))
            for b in 0..<3 where b != a { p[b] += p[b] > 0.5 ? -0.3 : 0.3 }
            return p
        }
        var out: [Int] = []
        func poly(_ v: [Int], _ outward: V3) {
            var v = v
            // Order the points round their centre, then wind them outward.
            let ctr = v.map(pos).reduce(V3.zero, +) / Float(v.count)
            let u = simd_normalize(pos(v[0]) - ctr), w = simd_cross(outward, u)
            v.sort { atan2f(simd_dot(pos($0) - ctr, w), simd_dot(pos($0) - ctr, u)) < atan2f(simd_dot(pos($1) - ctr, w), simd_dot(pos($1) - ctr, u)) }
            for k in 1..<(v.count - 1) { out += [v[0], v[k], v[k + 1]] }
        }
        for a in 0..<3 { for s in 0..<2 {
            var n = V3.zero; n[a] = s == 1 ? 1 : -1
            poly((0..<8).filter { ($0 >> a) & 1 == s }.map { $0 * 3 + a }, n)
        } }
        for a in 0..<3 {
            let b = (a + 1) % 3, c = (a + 2) % 3
            for sb in 0..<2 { for sc in 0..<2 {
                let ends = (0..<8).filter { ($0 >> b) & 1 == sb && ($0 >> c) & 1 == sc }
                var n = V3.zero; n[b] = sb == 1 ? 1 : -1; n[c] = sc == 1 ? 1 : -1
                poly([ends[0] * 3 + b, ends[0] * 3 + c, ends[1] * 3 + c, ends[1] * 3 + b], n)
            } }
        }
        for c in 0..<8 {
            let n = V3(Float(c & 1) * 2 - 1, Float((c >> 1) & 1) * 2 - 1, Float((c >> 2) & 1) * 2 - 1)
            poly([c * 3, c * 3 + 1, c * 3 + 2], n)
        }
        return out
    }()
    // Per point: its corner's bits (unit cube) and its smooth normal (its face's normal leaning toward the corner).
    static let corner: [V3] = (0..<24).map { i in let c = i / 3; return V3(Float(c & 1), Float((c >> 1) & 1), Float((c >> 2) & 1)) }
    static let normal: [V3] = (0..<24).map { i in
        let c = i / 3, a = i % 3
        let d = V3(Float(c & 1) * 2 - 1, Float((c >> 1) & 1) * 2 - 1, Float((c >> 2) & 1) * 2 - 1)
        var f = V3.zero; f[a] = d[a]
        return simd_normalize(f + d * 0.45)
    }
    static let vertsPerPart = 132
    // P374: one part's placed points (24 bevelled, or a box's 8 corners), reused by every part (main thread only).
    static let scratch: UnsafeMutablePointer<MobVert> = { let p = UnsafeMutablePointer<MobVert>.allocate(capacity: 24); p.initialize(repeating: MobVert(pos: .zero, color: .zero, local: .zero), count: 24); return p }()

    // The local point i of a part's box with bevel `c` (pixels).
    @inline(__always) static func point(_ i: Int, _ mn: V3, _ mx: V3, _ c: Float) -> V3 {
        let k = corner[i], a = i % 3
        var p = mn + (mx - mn) * k
        for b in 0..<3 where b != a { p[b] += k[b] > 0.5 ? -c : c }
        return p
    }

    // A part rounds when it is organic and big enough to show it; its bevel is a third of its thinnest side, up to 2 px.
    @inline(__always) static func bevel(_ p: Part) -> Float {
        if p.pattern == 8 || p.pattern == 11 || p.pattern == 9 { return 0 }
        let s = p.mx - p.mn
        let t = min(s.x, min(s.y, s.z))
        return t < 1.2 ? 0 : min(2, t * 0.32)
    }
}
