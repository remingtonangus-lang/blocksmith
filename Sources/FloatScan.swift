import Foundation
import simd

// Nov 12 playtest (06:20:51-06:21:17, after shelling a Capital tower from its deck gun: "we got a hovering part of the
// building here. That's bad", "Also that helipad's hovering"): every built piece in a box round a point that nothing
// holds up. The structural members (Structure.part) are joined as the load check joins them (faces and edges); a piece
// touching ground, a liquid or bedrock (Structure.anchor) or the box's side (held by what lies beyond) stands; any other
// piece of 4 blocks or more is listed (its size, its lowest cell and its box) and counted.
enum FloatScan {
    static func pieces(_ w: World, around p: IVec3, r: Int) -> [(n: Int, lo: IVec3, hi: IVec3)] {
        var seen = Set<IVec3>()
        var out: [(Int, IVec3, IVec3)] = []
        let yLo = max(1, p.y - r), yHi = min(CH - 2, p.y + r)
        for y in yLo...yHi { for z in (p.z - r)...(p.z + r) { for x in (p.x - r)...(p.x + r) {
            let s = IVec3(x, y, z)
            guard !seen.contains(s), w.isLoaded(x, z), Structure.part(w, x, y, z) != nil else { continue }
            seen.insert(s)
            var stack = [s], cells: [IVec3] = [], held = false
            while let c = stack.popLast() {
                cells.append(c)
                for e in World.allDirs where Structure.anchor(w, c.x + e.x, c.y + e.y, c.z + e.z) { held = true }
                for e in Structure.nbrs {
                    let q = c + e
                    if seen.contains(q) { continue }
                    if abs(q.x - p.x) > r || abs(q.z - p.z) > r || q.y < yLo || q.y > yHi {
                        if Structure.part(w, q.x, q.y, q.z) != nil { held = true }
                        continue
                    }
                    guard w.isLoaded(q.x, q.z) else { held = true; continue }
                    if Structure.part(w, q.x, q.y, q.z) != nil { seen.insert(q); stack.append(q) }
                }
            }
            guard !held, cells.count >= 4 else { continue }
            var lo = cells[0], hi = cells[0]
            for c in cells { lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)); hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z)) }
            out.append((cells.count, lo, hi))
        } } }
        return out.sorted { $0.0 > $1.0 }
    }

    static func scan(_ w: World, around p: IVec3, r: Int) -> String {
        let f = pieces(w, around: p, r: r)
        var s = "floatscan: \(f.count) built pieces nothing holds up within \(r) of \(p.x) \(p.y) \(p.z), \(f.reduce(0) { $0 + $1.n }) blocks"
        for (n, lo, hi) in f.prefix(8) { s += "\n  \(n) blocks, \(lo.x)..\(hi.x) \(lo.y)..\(hi.y) \(lo.z)..\(hi.z)" }
        return s
    }
}
