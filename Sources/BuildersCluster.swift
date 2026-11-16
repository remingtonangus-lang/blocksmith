import Foundation
import simd

// Ledger 202 (Nov 15 20:37-20:42, the Builders' Grounds: "All six built. Where are they built?... we gotta do a little
// better at showing me where the builds are. Maybe put them right in front of my face when I spawn in"): each build had
// the nearest spot of its own kind of ground, up to 1,200 blocks out and 40 or more from the others, and he started by
// the first. Now the six go up together: the nearest place where a spot for each stands within 22 of one middle (their
// origins 20 or more apart along x or z, so no two touch), and he starts 12 from that middle, facing it, every build
// within 40 of him. A kind of ground with no spot in such a place has its build on the nearest spot of plain, dry,
// gentle ground in it (the boathouse always on the water). BS_OLDBUILDSITES=1: as before.
extension BuildersGrounds {
    static let oldSites = Env.all["BS_OLDBUILDSITES"] == "1"
    static let spread = 22, apart = 20, spawnOut: Float = 12, near: Float = 40
    static var lastWhy = ""                   // (checks: how the last search went)

    struct Cluster {
        var sites: [String: IVec3]           // each kind's spot (the build's origin corner, y 0)
        var own: Set<String>                  // the kinds on their own kind of ground
        var spawn: V3                         // where he starts (y: the ground there)
        var yaw: Float                        // facing the middle
        var middle: V3
    }

    // The generator's columns and the spots' first looks, kept while a search runs.
    final class Screen {
        let w: World
        private var cols: [Int64: (h: Int, cls: UInt8)] = [:]
        private var looks: [Int64: [String]] = [:]
        var dropped: [Int64: Set<String>] = [:]          // kinds a spot was read and found not to be
        init(_ w: World) { self.w = w }
        @inline(__always) static func key(_ x: Int, _ z: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(bitPattern: Int32(z))) }
        // A column: its height and its kind of land (1 beach, 2 rock, 4 wood, 8 grass).
        func col(_ x: Int, _ z: Int) -> (h: Int, cls: UInt8) {
            let k = Screen.key(x, z)
            if let c = cols[k] { return c }
            let c = w.gen.column(x, z)
            var cls: UInt8 = 0
            switch c.biome {
            case .beach, .snowyBeach: cls = 1
            case .stonyShore, .windsweptHills, .windsweptGravellyHills, .stonyPeaks, .jaggedPeaks, .frozenPeaks, .grove, .snowySlopes,
                 .badlands, .erodedBadlands: cls = 2
            case .forest, .flowerForest, .birchForest, .oldGrowthBirchForest, .darkForest, .taiga, .oldGrowthPineTaiga,
                 .oldGrowthSpruceTaiga, .snowyTaiga, .windsweptForest, .jungle, .sparseJungle, .paleGarden, .cherryGrove, .woodedBadlands: cls = 4
            case .plains, .sunflowerPlains, .meadow, .savanna, .savannaPlateau: cls = 8
            default: cls = 0
            }
            let v: (h: Int, cls: UInt8) = (c.height, cls)
            cols[k] = v
            return v
        }
        // The kinds a spot could be from the generator's columns (as `maybe`), and "any": plain, dry, gentle ground.
        func kinds(_ x0: Int, _ z0: Int) -> [String] {
            let k = Screen.key(x0, z0)
            if let l = looks[k] { return l }
            var hs: [Int] = [], wet = 0, beach = 0, wood = 0, rock = 0, grass = 0
            for z in stride(from: 0, through: 10, by: 2) { for x in stride(from: 0, through: 10, by: 2) {
                let c = col(x0 + x, z0 + z)
                hs.append(c.h)
                if c.h < SEA { wet += 1 }
                if c.cls == 1 { beach += 1 } else if c.cls == 2 { rock += 1 } else if c.cls == 4 { wood += 1 } else if c.cls == 8 { grass += 1 }
            } }
            let lo = hs.min() ?? 0, hi = hs.max() ?? 0, n = hs.count
            var out: [String] = []
            if wet == 0 && hi - lo >= 4 && hi - lo <= 9 && grass + wood > n / 2 { out.append("slope") }
            if beach > n / 3 && wet >= 2 && wet <= n / 2 { out.append("beach") }
            // (the boathouse's water: any shore, a sea beach too, where the land is north and the water south of it)
            if wet >= n / 4 && wet <= n / 2 && hi - lo <= 7 && dockLie(x0, z0) { out.append("shore") }
            if wet == 0 && wood > n * 2 / 3 && hi - lo <= 3 { out.append("forest") }
            if wet == 0 && rock > n / 2 && hi - lo <= 5 { out.append("rocky") }
            if wet == 0 && hi - lo <= 4 && lo > SEA + 8 {
                var lower = 0
                for (ox, oz) in [(-16, 4), (26, 4), (4, -16), (4, 26), (-12, -12), (22, 22), (-12, 22), (22, -12)] where col(x0 + ox, z0 + oz).h <= lo - 3 { lower += 1 }
                if lower >= 6 { out.append("hilltop") }
            }
            if wet == 0 && hi - lo <= 5 { out.append("any") }
            looks[k] = out
            return out
        }
        // The boathouse's lie: dry land at its hut (the north rows), water under its slip (the south rows, out to 16).
        func dockLie(_ x0: Int, _ z0: Int) -> Bool {
            var dry = 0, wet = 0
            for x in stride(from: 0, through: 6, by: 2) {
                for z in [0, 2] where col(x0 + x, z0 + z).h >= SEA { dry += 1 }
                for z in [10, 12, 14, 16] where col(x0 + x, z0 + z).h < SEA { wet += 1 }
            }
            return dry >= 5 && wet >= 12
        }
        func could(_ x0: Int, _ z0: Int, _ kind: String) -> Bool {
            kinds(x0, z0).contains(kind) && !(dropped[Screen.key(x0, z0)]?.contains(kind) ?? false)
        }
    }

    // The ground read once its chunks are made (as findSites reads it): whether the spot is that kind.
    static func reads(_ w: World, _ x0: Int, _ z0: Int, _ kind: String) -> Bool {
        _ = w.loadSync(center: V3(Float(x0 + 5), 100, Float(z0 + 8)), radius: 1)
        var hs: [Int] = [], wet = 0
        for z in stride(from: 0, through: 10, by: 2) { for x in stride(from: 0, through: 10, by: 2) {
            hs.append(groundY(w, x0 + x, z0 + z))
            if water(w, x0 + x, z0 + z) { wet += 1 }
        } }
        let lo = hs.min() ?? 0, hi = hs.max() ?? 0, n = hs.count
        switch kind {
        case "slope": return wet == 0 && hi - lo >= 3 && hi - lo <= 9
        case "beach": return wet >= 2 && wet <= n / 2 && hi - lo <= 6
        case "shore":
            guard wet >= n / 5 && wet <= n * 3 / 5 && hi - lo <= 7 else { return false }
            var dry = 0, under = 0
            for x in stride(from: 0, through: 6, by: 2) {
                for z in [0, 2] where !water(w, x0 + x, z0 + z) { dry += 1 }
                for z in [10, 12, 14, 16] where water(w, x0 + x, z0 + z) { under += 1 }
            }
            return dry >= 6 && under >= 12
        case "forest":
            guard wet == 0 && hi - lo <= 4 else { return false }
            var trunks = 0
            for z in -6...16 { for x in -6...16 {
                let g = groundY(w, x0 + x, z0 + z)
                let b = Blocks.key(Blocks.groupBase[Int(w.block(x0 + x, g + 1, z0 + z))])
                if b.hasSuffix("_log") && w.topY(x0 + x, z0 + z) > g + 4 { trunks += 1 }
            } }
            return trunks >= 4
        case "rocky", "any": return wet == 0 && hi - lo <= 6
        case "hilltop": return wet == 0 && hi - lo <= 4
        default: return false
        }
    }

    // The nearest place round `centre` (out to `reach`) where the six stand together. Nil when no place has the water
    // the boathouse needs.
    static func findCluster(_ w: World, centre: V3, kinds: [String], reach: Int = 480) -> Cluster? {
        let s = Screen(w)
        let cx = Int(centre.x) & ~3, cz = Int(centre.z) & ~3
        var rings: [(Int, Int)] = []
        let step = 12
        for r in stride(from: 0, through: reach, by: step) {
            if r == 0 { rings.append((0, 0)); continue }
            for i in stride(from: -r, to: r, by: step) { rings.append((i, -r)); rings.append((r, i)); rings.append((-i, r)); rings.append((-r, -i)) }
        }
        func clash(_ a: IVec3, _ b: IVec3) -> Bool { abs(a.x - b.x) < apart && abs(a.z - b.z) < apart }
        // The best assignment at one middle: the most kinds on their own ground; nil without the boathouse's water.
        func assign(_ mx: Int, _ mz: Int) -> ([String: IVec3], Set<String>)? {
            var spots: [IVec3] = []
            for dz in stride(from: -spread - 8, through: spread, by: 4) { for dx in stride(from: -spread - 8, through: spread, by: 4) {
                let x0 = mx + dx, z0 = mz + dz
                let ex = Float(x0 + 5 - mx), ez = Float(z0 + 5 - mz)
                if ex * ex + ez * ez <= Float(spread * spread) { spots.append(IVec3(x0, 0, z0)) }
            } }
            func dist(_ p: IVec3) -> Int { (p.x + 5 - mx) * (p.x + 5 - mx) + (p.z + 5 - mz) * (p.z + 5 - mz) }
            var cands: [String: [IVec3]] = [:]
            for k in kinds { cands[k] = Array(spots.filter { s.could($0.x, $0.z, k) }.sorted { dist($0) < dist($1) }.prefix(3)) }
            if cands["shore"]?.isEmpty ?? false, kinds.contains("shore") { return nil }
            let anyCands = spots.filter { s.could($0.x, $0.z, "any") }.sorted { dist($0) < dist($1) }
            let order = kinds.sorted { (cands[$0]?.count ?? 0) < (cands[$1]?.count ?? 0) }
            var best: ([String: IVec3], Set<String>)?
            var cur: [String: IVec3] = [:]
            func dfs(_ i: Int, _ matched: Int) {
                if best.map({ $0.1.count == kinds.count }) ?? false { return }
                if i == order.count {
                    if let b = best, b.1.count >= matched { return }
                    // the rest on plain ground
                    var full = cur
                    for k in kinds where full[k] == nil {
                        guard k != "shore", let p = anyCands.first(where: { q in !full.values.contains(where: { clash($0, q) }) }) else { return }
                        full[k] = p
                    }
                    best = (full, Set(cur.keys))
                    return
                }
                let k = order[i]
                for p in cands[k] ?? [] where !cur.values.contains(where: { clash($0, p) }) {
                    cur[k] = p; dfs(i + 1, matched + 1); cur[k] = nil
                }
                if k != "shore" { dfs(i + 1, matched) }
            }
            dfs(0, 0)
            return best
        }
        var shoreMids = 0, dropped: [String] = []
        defer { lastWhy = "\(shoreMids) middles with a spot for the boathouse, \(dropped.count) spots read and dropped (\(dropped.suffix(8).joined(separator: ", ")))" }
        for _ in 0..<30 {
            var found: ([String: IVec3], Set<String>, Int, Int)?
            shoreMids = 0
            for (dx, dz) in rings {
                guard let a = assign(cx + dx, cz + dz) else { continue }
                shoreMids += 1
                if found == nil || a.1.count > found!.1.count { found = (a.0, a.1, cx + dx, cz + dz) }
                if a.1.count == kinds.count { break }
            }
            guard let f = found else { return nil }
            // Read each spot's ground; a spot that is not what the screen took it for is dropped and the search runs again.
            var bad = false
            for (k, p) in f.0 where !reads(w, p.x, p.z, f.1.contains(k) ? k : "any") {
                s.dropped[Screen.key(p.x, p.z), default: []].insert(f.1.contains(k) ? k : "any")
                dropped.append("\(f.1.contains(k) ? k : "any") \(p.x),\(p.z)")
                bad = true
            }
            if bad { continue }
            return finish(w, f.0, f.1)
        }
        return nil
    }

    // Where he starts: 12 from the builds' middle on the side from which they spread least across his view, facing it.
    static func finish(_ w: World, _ sites: [String: IVec3], _ own: Set<String>) -> Cluster {
        let mids = sites.values.map { V3(Float($0.x) + 5, 0, Float($0.z) + 5) }
        let m = mids.reduce(V3.zero, +) / Float(max(1, mids.count))
        var best: (V3, Float)?
        for k in 0..<8 {
            let a = Float(k) * .pi / 4
            let p = m + V3(sinf(a), 0, cosf(a)) * spawnOut
            let look = simd_normalize(V3(m.x - p.x, 0, m.z - p.z))
            var worst: Float = 0, far: Float = 0
            for b in mids {
                let d = V3(b.x - p.x, 0, b.z - p.z)
                far = max(far, simd_length(d))
                worst = max(worst, acosf(max(-1, min(1, simd_dot(simd_normalize(d), look)))))
            }
            let score = worst + (far > near - 6 ? 10 : 0)
            if best == nil || score < best!.1 { best = (p, score) }
        }
        let p = best!.0
        let y = Float(groundY(w, Int(floorf(p.x)), Int(floorf(p.z))) + 1)
        return Cluster(sites: sites, own: own, spawn: V3(p.x, y, p.z), yaw: atan2f(-(m.x - p.x), -(m.z - p.z)), middle: m)
    }
}
