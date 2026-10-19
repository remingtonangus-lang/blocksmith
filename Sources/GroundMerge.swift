import Foundation
import simd

// P375 (Remington, Oct 18 21:57: far geometry may be simplified ONLY where it cannot be seen, triangles merged when the
// change is under about one Quest 3 pixel at that distance; no change in shape, silhouette, colour or materials).
// A field section's up-facing ground is a grid of dual-contoured quads, one per column (x, z in 1...16). Each section
// also keeps a second copy of the parts of that grid which lie flat enough: a square of 2x2 to 16x16 quads becomes one
// quad when every vertex inside it lies within `tol16` (1/16 block) of the merged quad's two triangles, every vertex on
// its edge within 1/16 block of the edge (so its unmerged neighbours meet it with no visible seam), and every vertex
// carries the same material, tint, light, occlusion and normal (so colour and shading are the same, not just close).
// The renderer draws the merged copy only for sections whose nearest point is at least `farDistance` from the eye,
// where `tol16` is under one pixel of the Quest 3's sharpest (centre) resolution; nearer, the full grid. The choice is
// made per frame from the exact distance, so nothing is remeshed as the player moves.
// Layout in the section's opaque buffer: [replaced quads][the rest of the solid quads][cutout quads][merged quads];
// near draws the solid range as before, far draws [replaced count ..< solid] plus the merged quads.
final class GroundMerge {
    static var enabled = ProcessInfo.processInfo.environment["BS_PIXELMERGE"] != "0"
    // Quest 3: 2064 x 2208 per eye, about 25 pixels a degree at the centre of the lens (its sharpest).
    static let pixelRadians: Float = (1 / 25.5) * .pi / 180
    static let tol16: Float = 2                                  // 1/8 block
    static let farDistance: Float = tol16 / 16 / pixelRadians      // ~180 blocks (11 chunks)
    static var merged = 0, replaced = 0                            // (harness tallies, quads)

    // One up-facing quad: 4 corners in dual-cell order (x-1,z-1), (x-1,z), (x,z), (x,z-1); per corner
    // x16, y16, z16, tint, layer, ao, light, normal code.
    struct Quad { var v: [SIMD8<Int32>]; var flip: Bool }
    private var cells = [Int32](repeating: -1, count: 17 * 17)     // column (x, z) -> quad index, -2 two or more
    private(set) var quads: [Quad] = []
    var collecting: Bool { GroundMerge.enabled }

    func reset() {
        for i in cells.indices { cells[i] = -1 }
        quads.removeAll(keepingCapacity: true)
    }
    func add(x: Int, z: Int, _ q: Quad) {
        let i = x + z * 17
        quads.append(q)
        cells[i] = cells[i] == -1 ? Int32(quads.count - 1) : -2
    }

    // Splits the collected quads: `replaced` (drawn near only), `kept` (always) and `mergedOut` (far only, each 4
    // corners in emission order).
    func solve(replaced: inout [Int], kept: inout [Int], mergedOut: inout [[SIMD8<Int32>]]) {
        replaced.removeAll(); kept.removeAll(); mergedOut.removeAll()
        let tol = GroundMerge.tol16
        var covered = [Bool](repeating: false, count: 17 * 17)
        func quadAt(_ x: Int, _ z: Int) -> Quad? {
            guard x >= 1 && x <= 16 && z >= 1 && z <= 16 else { return nil }
            let k = cells[x + z * 17]
            return k >= 0 ? quads[Int(k)] : nil
        }
        // The vertex grid of the n x n square at (x0, z0): dual cells (x0-1+i, z0-1+j), i, j in 0...n.
        func grid(_ x0: Int, _ z0: Int, _ n: Int) -> [SIMD8<Int32>]? {
            let m = n + 1
            var g = [SIMD8<Int32>?](repeating: nil, count: m * m)
            for dz in 0..<n { for dx in 0..<n {
                guard let q = quadAt(x0 + dx, z0 + dz) else { return nil }
                if covered[x0 + dx + (z0 + dz) * 17] { return nil }
                for (k, (ox, oz)) in [(0, 0), (0, 1), (1, 1), (1, 0)].enumerated() {
                    let gi = (dx + ox) + (dz + oz) * m
                    if let o = g[gi] { if o != q.v[k] { return nil } } else { g[gi] = q.v[k] }
                }
            } }
            let a = g[0]!
            for v in g where !(v!.highHalf == a.highHalf && v![3] == a[3] && v![4] == a[4]) { return nil }   // same attributes
            return g.map { $0! }
        }
        func flat(_ g: [SIMD8<Int32>], _ n: Int) -> Bool {
            let m = n + 1
            func p(_ i: Int, _ j: Int) -> SIMD3<Float> { let v = g[i + j * m]; return SIMD3(Float(v[0]), Float(v[1]), Float(v[2])) }
            let A = p(0, 0), B = p(0, n), C = p(n, n), D = p(n, 0)
            // Triangles A B C and A C D (the merged quad's diagonal A-C, as Mesher's index pattern draws it).
            func height(_ q: SIMD3<Float>, _ t0: SIMD3<Float>, _ t1: SIMD3<Float>, _ t2: SIMD3<Float>) -> Float? {
                let nrm = simd_cross(t1 - t0, t2 - t0)
                guard abs(nrm.y) > 1e-3 else { return nil }
                return t0.y - (nrm.x * (q.x - t0.x) + nrm.z * (q.z - t0.z)) / nrm.y
            }
            let acx = C.x - A.x, acz = C.z - A.z
            let sideB = acx * (B.z - A.z) - acz * (B.x - A.x)
            func segDist(_ q: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
                let ab = b - a
                let t = max(0, min(1, simd_dot(q - a, ab) / max(1e-6, simd_length_squared(ab))))
                return simd_length(q - (a + ab * t))
            }
            for j in 0...n { for i in 0...n {
                let q = p(i, j)
                let edge = i == 0 || j == 0 || i == n || j == n
                if edge {
                    let corner = (i == 0 || i == n) && (j == 0 || j == n)
                    if corner { continue }
                    let d: Float
                    if i == 0 { d = segDist(q, A, B) } else if i == n { d = segDist(q, D, C) }
                    else if j == 0 { d = segDist(q, A, D) } else { d = segDist(q, B, C) }
                    if d > 1.0 { return false }
                } else {
                    let s = acx * (q.z - A.z) - acz * (q.x - A.x)
                    guard let h = (s * sideB >= 0) ? height(q, A, B, C) : height(q, A, C, D) else { return false }
                    if abs(q.y - h) > tol { return false }
                }
            }}
            return true
        }
        for n in [16, 8, 4, 2] {
            var z0 = 1
            while z0 + n - 1 <= 16 {
                var x0 = 1
                while x0 + n - 1 <= 16 {
                    if let g = grid(x0, z0, n), flat(g, n) {
                        let m = n + 1
                        mergedOut.append([g[0], g[n * m], g[n + n * m], g[n]])
                        for dz in 0..<n { for dx in 0..<n {
                            let c = x0 + dx + (z0 + dz) * 17
                            covered[c] = true
                            replaced.append(Int(cells[c]))
                        } }
                    }
                    x0 += n
                }
                z0 += n
            }
        }
        var isRep = [Bool](repeating: false, count: quads.count)
        for r in replaced { isRep[r] = true }
        for i in quads.indices where !isRep[i] { kept.append(i) }
        GroundMerge.merged += mergedOut.count; GroundMerge.replaced += replaced.count
    }
}
