import Foundation
import simd

// P389 step 1 (questcheck --objectcensus [--field] [--seed S]): which multi-cell objects the player meets most at Stone
// Gulch, the nearest capital city and the nearest base. Every loaded cell in each site's box is read from the built
// layer; cells that can be part of an object (anything drawn from boxes, a log or stem, an organic block, and the small
// built blocks: barrels, crates, lamps, hay, pumpkins...) are joined into connected groups (6-neighbours), and each
// group is named by what it is made of (WorldObjects.classify: the same rule a hit uses to find the object it struck).
// Groups over 40 cells or 7 blocks across are buildings, not objects; a log column under leaves is a tree.
extension World {
    // The three sites: Stone Gulch (the town round his playtest spot) and the capital city and base nearest it.
    static func objectSites(_ w: World) -> [(name: String, lo: IVec3, hi: IVec3)] {
        let gulch = (x: 6094, z: 688)
        var sites: [(name: String, lo: IVec3, hi: IVec3)] = [("Stone Gulch", IVec3(gulch.x - 64, 0, gulch.z - 64), IVec3(gulch.x + 64, CH - 1, gulch.z + 64))]
        for kind in ["capital_city", "military_base"] {
            if let st = w.gen.structures?.nearest(kind, x: gulch.x, z: gulch.z, maxRegions: 24) {
                // (the structure's own box, at most 160 across round its anchor: the streets he walks)
                let lo = IVec3(max(st.min.x, st.anchor.x - 80), 0, max(st.min.z, st.anchor.z - 80))
                let hi = IVec3(min(st.max.x, st.anchor.x + 80), CH - 1, min(st.max.z, st.anchor.z + 80))
                sites.append((kind == "capital_city" ? "capital city at \(st.anchor.x) \(st.anchor.z)" : "base at \(st.anchor.x) \(st.anchor.z)", lo, hi))
            }
        }
        return sites
    }

    // Every group of object cells in a site's box (loaded first), with what it is.
    static func scanObjects(_ w: World, lo: IVec3, hi: IVec3, _ visit: (WorldObjects.Group, WorldObjects.Kind) -> Void) {
        let cx = (lo.x + hi.x) / 2, cz = (lo.z + hi.z) / 2
        let r = max(hi.x - lo.x, hi.z - lo.z) / 2 / CS + 1
        _ = w.loadSync(center: V3(Float(cx), 150, Float(cz)), radius: r)
        var seen = Set<IVec3>()
        for x in lo.x...hi.x { for z in lo.z...hi.z {
            guard w.chunkAt(x, z) != nil else { continue }
            for y in 1..<(CH - 1) {
                let b = w.builtBlock(x, y, z)
                guard WorldObjects.candidate[Int(b)] else { continue }
                let p = IVec3(x, y, z)
                if seen.contains(p) { continue }
                let grp = WorldObjects.group(w, from: p, limit: 64)
                for q in grp.cells { seen.insert(q) }
                visit(grp, WorldObjects.classify(w, grp))
            }
        } }
    }

    static func objectCensus(_ g: Game) -> String {
        let w = g.world
        var lines = ["objectcensus (P389 step 1): connected groups of object cells per site, named by WorldObjects.classify"]
        var total: [String: Int] = [:], totalCells: [String: Int] = [:]
        for site in objectSites(w) {
            var counts: [String: Int] = [:], cells: [String: Int] = [:], sigs: [String: Int] = [:]
            var kindSigs: [String: [String: Int]] = [:], sample: [String: IVec3] = [:]
            var buildings = 0, trees = 0
            scanObjects(w, lo: site.lo, hi: site.hi) { grp, k in
                switch k {
                case .building: buildings += 1
                case .tree: trees += 1
                case .none: break
                default:
                    counts[k.name, default: 0] += 1; cells[k.name, default: 0] += grp.cells.count
                    kindSigs[k.name, default: [:]][grp.signature, default: 0] += 1
                    if sample[k.name] == nil { sample[k.name] = grp.lo }
                }
                if k == .other { sigs[grp.signature, default: 0] += 1 }
            }
            lines.append("  \(site.name): \(buildings) buildings, \(trees) trees; objects:")
            for (k, n) in counts.sorted(by: { $0.value > $1.value }) {
                let ks = (kindSigs[k] ?? [:]).sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) x\($0.value)" }.joined(separator: ", ")
                let sp = sample[k].map { "\($0.x) \($0.y) \($0.z)" } ?? "-"
                lines.append("    \(k): \(n) (\(cells[k] ?? 0) cells; e.g. at \(sp); \(ks))")
                total[k, default: 0] += n; totalCells[k, default: 0] += cells[k] ?? 0
            }
            let top = sigs.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key) x\($0.value)" }
            if !top.isEmpty { lines.append("    unnamed groups (most common): " + top.joined(separator: ", ")) }
        }
        lines.append("  all three sites:")
        for (i, (k, n)) in total.sorted(by: { $0.value > $1.value }).enumerated() {
            lines.append("    \(i + 1). \(k): \(n) (\(totalCells[k] ?? 0) cells)")
        }
        return lines.joined(separator: "\n")
    }
}
