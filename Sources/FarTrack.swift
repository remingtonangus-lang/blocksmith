import Foundation
import simd

// Ledger 361, the far layer's railways: past the loaded chunks a line's track stands as its bed, a strip 5 blocks wide
// along the rails with earth flanks down to the ground (an embankment, or a bridge's deck and its piers as one wall),
// out to `reach` blocks. Quads in the far ring's own vertex list (FarRing.build), like the stand-in trees.
//
// Only plans already made are drawn in a build (`wait: false`): planning a line can take a second, and the first ring
// of a world is built at load. `warm` then plans the lines in reach on a background queue, and the ring is built again.
enum FarTrack {
    static let reach = 800
    // BS_FARTRACKWAIT=1: a build plans the lines itself (one-frame harness pictures).
    static let waitInBuild = Env.all["BS_FARTRACKWAIT"] == "1"

    static func lines(_ gen: WorldGen, cx: Int, cz: Int, wait: Bool) -> [Railways.Line] {
        let R = reach
        var l = Railways.near(gen, x0: cx - R, z0: cz - R, x1: cx + R, z1: cz + R, pad: 0, wait: wait, wild: true)
        l += Railways.linksNear(gen, x0: cx - R, z0: cz - R, x1: cx + R, z1: cz + R, pad: 0, wait: wait)
        l += Railways.loopsNear(gen, x0: cx - R, z0: cz - R, x1: cx + R, z1: cz + R, pad: 0, wait: wait)
        return l
    }

    // The 4-block squares within 6 blocks of a planned track in reach: no stand-in tree there (the tree pass keeps 5
    // blocks clear of a railway).
    static func clear(_ gen: WorldGen, cx: Int, cz: Int) -> Set<Int64> {
        var out = Set<Int64>()
        let R = reach + 16
        for l in lines(gen, cx: cx, cz: cz, wait: waitInBuild) {
            for c in l.cells where abs(c.x - cx) <= R && abs(c.z - cz) <= R {
                for dz in stride(from: -6, through: 6, by: 4) { for dx in stride(from: -6, through: 6, by: 4) {
                    out.insert(key((c.x + dx) >> 2, (c.z + dz) >> 2))
                } }
            }
        }
        return out
    }
    @inline(__always) static func key(_ x: Int, _ z: Int) -> Int64 { (Int64(x) << 32) | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: z))) }

    static func warm(_ gen: WorldGen, cx: Int, cz: Int) { _ = lines(gen, cx: cx, cz: cz, wait: true) }

    // The beds between `from` and `reach` blocks of the centre; returns the quads added.
    @discardableResult
    static func emit(_ gen: WorldGen, cx: Int, cz: Int, from: Float, into out: inout [SimpleVert]) -> Int {
        let up: Float = 512 + 512 * 1024
        func nq(_ nx: Float, _ nz: Float) -> Float { ((nx * 0.5 + 0.5) * 1023).rounded() + ((nz * 0.5 + 0.5) * 1023).rounded() * 1024 }
        let bed = V4(V3(0.42, 0.39, 0.35) * 0.8, 0), flank = V4(V3(0.44, 0.36, 0.28) * 0.72, 0)
        let step = 6, half: Float = 2.5, drop: Float = 6
        let far = Float(reach)
        var quads = 0
        var seen = Set<Int64>()
        for l in lines(gen, cx: cx, cz: cz, wait: waitInBuild) where seen.insert(l.id ^ (l.target << 1) ^ Int64(l.cells.count) << 40).inserted {
            let n = l.cells.count
            guard n > step else { continue }
            var i = 0
            while i + step < n {
                let a = l.cells[i], b = l.cells[min(n - 1, i + step)]
                i += step
                let ax = Float(a.x - cx) + 0.5, az = Float(a.z - cz) + 0.5, bx = Float(b.x - cx) + 0.5, bz = Float(b.z - cz) + 0.5
                let da: Float = (ax * ax + az * az).squareRoot(), db: Float = (bx * bx + bz * bz).squareRoot()
                if max(da, db) > far || min(da, db) < from { continue }
                var dx = bx - ax, dz = bz - az
                let len: Float = (dx * dx + dz * dz).squareRoot()
                guard len > 0.5 else { continue }
                dx /= len; dz /= len
                let px = -dz * half, pz = dx * half
                // (The ring's shader draws everything 2 blocks low, the ground with it; the bed a block proud of the
                // rails' own height keeps it over the coarse ground between samples.)
                let ya = Float(a.y) + 1.2, yb = Float(b.y) + 1.2
                out.append(SimpleVert(pos: V4(ax - px, ya, az - pz, up), color: bed)); out.append(SimpleVert(pos: V4(ax + px, ya, az + pz, up), color: bed))
                out.append(SimpleVert(pos: V4(bx + px, yb, bz + pz, up), color: bed)); out.append(SimpleVert(pos: V4(bx - px, yb, bz - pz, up), color: bed))
                for s: Float in [1, -1] {
                    let q = nq(-dz * s * 0.7, dx * s * 0.7)
                    let ex = px * s, ez = pz * s
                    out.append(SimpleVert(pos: V4(ax + ex, ya, az + ez, q), color: flank)); out.append(SimpleVert(pos: V4(bx + ex, yb, bz + ez, q), color: flank))
                    out.append(SimpleVert(pos: V4(bx + ex * 1.6, yb - drop, bz + ez * 1.6, q), color: flank)); out.append(SimpleVert(pos: V4(ax + ex * 1.6, ya - drop, az + ez * 1.6, q), color: flank))
                }
                quads += 3
            }
        }
        return quads
    }
}
