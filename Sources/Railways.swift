import Foundation
import simd

// C1 (the overseer's features): railways, procedural and rare. A line links three to six towns along one row of
// village regions, so finding a station is a big find: it is fast travel to every other station on the line.
//   Lines     village regions are 34 chunks; a row of them is split into stretches of `stretch` regions, and a
//             stretch carries a line when its hash falls under `share` (about one line per 4,000 x 4,000 blocks, the
//             citadels' rarity: `questcheck --rail-only` counts them over 50 seeds). Each town's station sits on a
//             straight run along the south edge of its town; between towns the track runs east, turns north or south
//             on a dog-leg (two flat curves) and runs east again. A leg that would cut through any surface structure
//             is moved (five tries) or the line ends at the town before it; a line keeps at least three stations.
//   Sites     P379: a citadel, a capital city, a Greywall base or a Boreal station in the row's band gets a station
//             too when the line can reach it without losing the town after it.
//   Profile   the track follows the land at most one block up or down a step: cuttings and tunnels through rises,
//             trestles on timber legs over dips, rivers and lakes; never over the open sea, never below sea + 2.
//             Curves and platforms are level. In a field world (P379) the grade is 1 in 8 and the drawn bed and track
//             follow the planned height itself (Railways.shapeBed, ShapeRails), not one-block steps.
//   Stations  a platform between the track and the town with lamps, a station house across the track with the
//             town's name and a TICKETS sign (Trains.swift sells the fares), buffer stops at both ends of the line.
//   Old saves ground any save had generated before railways (structure-guard-c1.txt) keeps no line, so nothing
//             explored grows half a railway. Y5 ("saved worlds get new content in unexplored ground"): a line the old
//             rule drops is planned again from its runs on ground no save had generated before Y5 (FreshGround), so
//             a long line no longer vanishes because one end touches explored land; it never crosses saved ground.
// Trains run the lines on a timetable (Trains.swift).
enum Railways {
    static let span = 34 * CS              // a village region, blocks
    static let stretch = 6                 // village regions a line may run across
    // P337 step 1: every stretch with towns enough carries a line (was 0.3: a line every 4,000 blocks was a rare find,
    // and the towns between went unlinked). Ground a save generated before keeps none (Y5, FreshGround).
    static var share: Float = 1
    static let minStations = 2             // P470: two stations make a line (on ground no save had before P470)
    static let oldMinStations = 3          // (the rule before: ground saved earlier keeps its lines as laid)
    static let stationRun = 10             // the straight past each side of a town's box
    static let southGap = 5                // the track, blocks south of the town's box
    static var on = true                   // (the host checks turn lines off to compare)
    static var tally: ((String) -> Void)?  // (questcheck --railprobe: why a stretch has no line)

    struct Station { let name: String; let index: Int; let x: Int; let z: Int; var halt = false; var site = false }   // halt: a hamlet's (C13); site: P379
    final class Line {
        let id: Int64                      // row and stretch
        let name: String
        let cells: [IVec3]                 // every rail, in order west to east (y: the rail's own y)
        let stations: [Station]
        let minX: Int, maxX: Int, minZ: Int, maxZ: Int
        // P379 step 3: in a field world, the track's height at each cell (the rail's y plus at most half a block either
        // way): the drawn bed and the track follow it at a gentle grade, not in one-block steps. Nil in block worlds.
        var heights: [Float]? = nil
        init(id: Int64, name: String, cells: [IVec3], stations: [Station], heights: [Float]? = nil) {
            self.id = id; self.name = name; self.cells = cells; self.stations = stations; self.heights = heights
            minX = cells.map { $0.x }.min() ?? 0; maxX = cells.map { $0.x }.max() ?? 0
            minZ = cells.map { $0.z }.min() ?? 0; maxZ = cells.map { $0.z }.max() ?? 0
        }
        // The rail shape at cell i (Rails.swift shapes).
        func shape(_ i: Int) -> Int {
            let c = cells[i]
            let p = i > 0 ? cells[i - 1] : nil, q = i + 1 < cells.count ? cells[i + 1] : nil
            let dIn = p.map { IVec3(c.x - $0.x, 0, c.z - $0.z) }, dOut = q.map { IVec3($0.x - c.x, 0, $0.z - c.z) }
            if let a = dIn, let b = dOut, a.x != b.x || a.z != b.z {
                // A curve: its two exits are back to p and on to q.
                let e1 = (-a.x, -a.z), e2 = (b.x, b.z)
                func has(_ e: (Int, Int)) -> Bool { (e1.0 == e.0 && e1.1 == e.1) || (e2.0 == e.0 && e2.1 == e.1) }
                if has((0, 1)) && has((1, 0)) { return 6 }
                if has((0, 1)) && has((-1, 0)) { return 7 }
                if has((0, -1)) && has((-1, 0)) { return 8 }
                return 9
            }
            let d = dOut ?? dIn ?? IVec3(1, 0, 0)
            let alongX = d.x != 0
            // A slope rises toward the neighbour one block up.
            for n in [q, p] {
                guard let n, n.y == c.y + 1 else { continue }
                let dx = n.x - c.x, dz = n.z - c.z
                if alongX { return dx > 0 ? 2 : 3 }
                return dz < 0 ? 4 : 5
            }
            return alongX ? 1 : 0
        }
        func station(near x: Int, _ z: Int, within r: Int) -> Station? {
            stations.min { abs($0.x - x) + abs($0.z - z) < abs($1.x - x) + abs($1.z - z) }
                .flatMap { abs($0.x - x) <= r && abs($0.z - z) <= r ? $0 : nil }
        }
    }

    private static var cache: [Int64: Line?] = [:]
    private static var cacheGen: ObjectIdentifier?
    private static var cacheField = 0                 // (fieldWorld 1, railSites 2)
    private static let lock = NSLock()
    private static var planning: Set<Int64> = []          // lines being planned on a worker (line(wait: false))

    static func key(_ row: Int, _ s: Int) -> Int64 { Int64(row) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: s))) }

    // The line of village row `row`, stretch `s` (regions s*stretch ..< (s+1)*stretch), if one runs there.
    // `wait: false` (the frame thread: Trains, P440): a line not planned yet is planned on a worker and left out until
    // then. Planning one took 1.1 s of a frame in the debug harness (perfscenes forest24: "trains" 1164 ms flying into new
    // land), a long stall on the headset too.
    static func line(_ gen: WorldGen, row: Int, stretch s: Int, wait: Bool = true) -> Line? {
        guard on else { return nil }
        let k = key(row, s), gid = ObjectIdentifier(gen)
        lock.lock()
        let mode = (gen.fieldWorld ? 1 : 0) | (gen.railSites ? 2 : 0)
        if cacheGen != gid || cacheField != mode { cache.removeAll(); planning.removeAll(); cacheGen = gid; cacheField = mode }
        if let c = cache[k] { lock.unlock(); return c }
        if !wait {
            let start = !planning.contains(k)
            if start { planning.insert(k) }
            lock.unlock()
            if start {
                DispatchQueue.global(qos: .utility).async {
                    let l = plan(gen, row: row, stretch: s)
                    lock.lock()
                    if cacheGen == gid && cacheField == mode { cache[k] = l }
                    planning.remove(k)
                    if cache.count > 2048 { cache.removeAll() }
                    lock.unlock()
                }
            }
            return nil
        }
        lock.unlock()
        let l = plan(gen, row: row, stretch: s)
        lock.lock(); if cacheGen == gid && cacheField == mode { cache[k] = l }; if cache.count > 2048 { cache.removeAll() }; lock.unlock()
        return l
    }

    // Lines whose track may pass within `pad` blocks of the box.
    static func near(_ gen: WorldGen, x0: Int, z0: Int, x1: Int, z1: Int, pad: Int = 2, wait: Bool = true) -> [Line] {
        guard on else { return [] }
        // A line stays inside its row's band give or take a town's box and the south gap (half a region is plenty).
        let r0 = floorDiv(z0 - pad - span / 2, span), r1 = floorDiv(z1 + pad + span / 2, span)
        let w = stretch * span
        let s0 = floorDiv(x0 - pad - span, w), s1 = floorDiv(x1 + pad + span, w)
        var out: [Line] = []
        for row in r0...r1 { for s in s0...s1 {
            guard hashf(s, row, 0xC1, UInt32(truncatingIfNeeded: gen.seed) ^ 0xC1A1) < share else { continue }
            guard let l = line(gen, row: row, stretch: s, wait: wait) else { continue }
            if l.maxX + pad < x0 || l.minX - pad > x1 || l.maxZ + pad < z0 || l.minZ - pad > z1 { continue }
            out.append(l)
        } }
        return out
    }

    // MARK: Planning

    // Kinds the track keeps clear of: everything on the surface (underground and sky kinds are left out; a cutting at
    // most a few blocks deep doesn't reach them).
    static let skipKinds: Set<String> = ["mineshaft", "ancient_city", "trial_chambers", "fossil", "buried_treasure", "stronghold"]

    static func blocked(_ gen: WorldGen, _ sc: StructureCache, x0: Int, z0: Int, x1: Int, z1: Int, except: Set<Int64>) -> Bool {
        let pad = 4
        let ax = min(x0, x1) - pad, bx = max(x0, x1) + pad, az = min(z0, z1) - pad, bz = max(z0, z1) + pad
        for t in sc.types where !skipKinds.contains(t.name) && t.name != SkyIsle.kind {
            let s = t.spacing * CS, r = t.reach * CS
            for rz in floorDiv(az - r, s)...floorDiv(bz + r, s) { for rx in floorDiv(ax - r, s)...floorDiv(bx + r, s) {
                guard let o = sc.start(t, regionX: rx, regionZ: rz) else { continue }
                if (t.name == "village" || siteKinds.contains(t.name)) && except.contains(StructureCache.key(o.anchor.x, o.anchor.z)) { continue }
                if o.max.x >= ax && o.min.x <= bx && o.max.z >= az && o.min.z <= bz {
                    // A box's corner can be empty: look at the pieces.
                    if o.pieces.contains(where: { $0.max.x >= ax && $0.min.x <= bx && $0.max.z >= az && $0.min.z <= bz }) { return true }
                }
            } }
        }
        return false
    }

    struct Town { let name: String; let box: (IVec3, IVec3); let sq: IVec3; var halt = false; var site = false }

    // P379 step 1 (P337 (b)): the major sites a line also calls at when one stands in its row's band: the Capital's
    // citadels, its cities, Greywall bases and Boreal stations. A site the line can't reach (no room for the dog-leg,
    // something in the way, or it would cut the line off from the town after it) is passed by; it never ends a line.
    static let siteKinds: Set<String> = ["military_base", "capital_city", Greywall.kind, BorealStation.kind]

    static func siteName(_ kind: String, _ o: StructureStart, _ seed: UInt64) -> String {
        let n = Townsfolk.townName(o.anchor.x, o.anchor.z, seed: seed)
        let a = String(n.split(separator: " ").first ?? Substring(n))
        switch kind {
        case "military_base": return "Fort " + a
        case "capital_city":
            if let plan = o.plan as? CapitalCity.Plan {
                let h = CapitalCity.N * CapitalCity.lot
                return CapitalTown.cityName(plan.ox + h, plan.oz + h, seed: plan.seed) + " Central"
            }
            return a + " Central"
        case Greywall.kind: return "Greywall " + a
        default: return a + " Outpost"
        }
    }

    // The major sites whose anchors lie in this row and stretch.
    static func sites(_ gen: WorldGen, _ sc: StructureCache, row: Int, stretch s: Int) -> [Town] {
        let x0 = s * stretch * span, x1 = (s + 1) * stretch * span, z0 = row * span, z1 = (row + 1) * span
        var out: [Town] = []
        for t in sc.types where siteKinds.contains(t.name) {
            let sp = t.spacing * CS
            for rz in (floorDiv(z0, sp) - 1)...floorDiv(z1, sp) { for rx in (floorDiv(x0, sp) - 1)...floorDiv(x1, sp) {
                guard let o = sc.start(t, regionX: rx, regionZ: rz) else { continue }
                guard o.anchor.x >= x0 && o.anchor.x < x1 && o.anchor.z >= z0 && o.anchor.z < z1, o.max.y >= SEA else { continue }
                out.append(Town(name: siteName(t.name, o, gen.seed), box: (o.min, o.max), sq: o.anchor, site: true))
            } }
        }
        return out
    }

    static func plan(_ gen: WorldGen, row: Int, stretch s: Int) -> Line? {
        if let l = plan(gen, row: row, stretch: s, avoid: nil, need: oldMinStations) { return l }
        guard let sc = gen.structures else { return nil }
        // Y5: the line as before failed; on an old save, its stations and legs on fresh ground still make a line.
        if !sc.legacyC1.isEmpty, let fresh = FreshGround.guardSet(sc), let l = plan(gen, row: row, stretch: s, avoid: fresh, need: oldMinStations) { return l }
        // P470 ("the trains were never added": over his playtests he never met one; 64 of 80 stretches round his
        // Capital City had fewer than three towns): two stations (towns or major sites) make a line, on ground no save
        // had generated before P470 (structure-guard-p470.txt), so explored land never grows half a railway.
        return plan(gen, row: row, stretch: s, avoid: sc.legacyP470.isEmpty ? nil : sc.legacyP470, need: minStations)
    }

    // `avoid`: chunks no part of the line may come within 3 chunks of (a town or leg there ends the run).
    // `need`: stations a line needs (P470: with two, the major sites count toward it before the towns are counted).
    static func plan(_ gen: WorldGen, row: Int, stretch s: Int, avoid: Set<Int64>?, need: Int) -> Line? {
        guard let sc = gen.structures, let vt = sc.types.first(where: { $0.name == "village" }) else { return nil }
        func fresh(_ cells: [(Int, Int)]) -> Bool {
            guard let avoid, !avoid.isEmpty else { return true }
            for i in stride(from: 0, to: cells.count, by: 8) where !sc.clear(cx: floorDiv(cells[i].0, CS), cz: floorDiv(cells[i].1, CS), reach: 3, guardSet: avoid) { return false }
            if let l = cells.last, !sc.clear(cx: floorDiv(l.0, CS), cz: floorDiv(l.1, CS), reach: 3, guardSet: avoid) { return false }
            return true
        }
        // The towns along the stretch, west to east.
        var towns: [Town] = []
        for rx in (s * stretch)..<((s + 1) * stretch) {
            guard let v = sc.start(vt, regionX: rx, regionZ: row) else { continue }
            if v.max.y < SEA { continue }
            // C13: a hamlet gets a halt (a short platform and a name board), villages and up a station.
            towns.append(Town(name: Townsfolk.townName(v.anchor.x, v.anchor.z, seed: gen.seed), box: (v.min, v.max), sq: v.anchor,
                              halt: v.info["size"] == TownSize.hamlet.rawValue))
        }
        if need < oldMinStations && gen.railSites { towns += sites(gen, sc, row: row, stretch: s) }
        guard towns.count >= need else { tally?("fewer than \(need) towns in the stretch"); return nil }
        if need >= oldMinStations && gen.railSites { towns += sites(gen, sc, row: row, stretch: s) }
        towns.sort { $0.sq.x < $1.sq.x }
        // Ground saved before railways: no line (checked along the whole run below).
        let legacy = sc.legacyC1
        var best: [IVec3] = [], bestStations: [Station] = []
        var cur: [IVec3] = [], curSt: [Station] = []
        func flush() {
            if curSt.count >= need && curSt.count > bestStations.count { best = cur; bestStations = curSt }
            cur = []; curSt = []
        }
        // (a site is passed over only by its own straight: a leg never runs through a citadel or a base)
        let except = Set(towns.filter { !$0.site }.map { StructureCache.key($0.sq.x, $0.sq.z) })
        var prevEnd: (x: Int, z: Int)?
        // The straight past a town's box (nil: something beside the town is in its way).
        func straight(_ t: Town) -> (z: Int, xa: Int, xb: Int)? {
            let z = t.box.1.z + southGap
            let xa = t.box.0.x - stationRun, xb = t.box.1.x + stationRun
            // The town's own straight must be clear (other structures beside the town).
            let own = t.site ? except.union([StructureCache.key(t.sq.x, t.sq.z)]) : except
            let townClear = !blocked(gen, sc, x0: xa, z0: z, x1: xb, z1: z + 8, except: own)
                && (avoid == nil || fresh(stride(from: xa, through: xb, by: 4).map { ($0, z) }))
            return townClear ? (z, xa, xb) : nil
        }
        // A dog-leg from the last town's straight to this one.
        func dogLeg(_ pe: (x: Int, z: Int), _ xa: Int, _ z: Int) -> [(Int, Int)]? {
            var leg: [(Int, Int)]?
            let gap = xa - pe.x
            if gap >= 24 {
                for k in 0..<5 {
                    let xm = pe.x + gap / 2 + [0, -gap / 5, gap / 5, -gap / 3, gap / 3][k]
                    if xm - pe.x < 8 || xa - xm < 8 { continue }
                    if blocked(gen, sc, x0: pe.x + 1, z0: pe.z, x1: xm, z1: pe.z, except: except) { continue }
                    if pe.z != z && blocked(gen, sc, x0: xm, z0: pe.z, x1: xm, z1: z, except: except) { continue }
                    if blocked(gen, sc, x0: xm, z0: z, x1: xa - 1, z1: z, except: except) { continue }
                    var l: [(Int, Int)] = []
                    for x in (pe.x + 1)...xm { l.append((x, pe.z)) }
                    if pe.z != z {
                        let dz = z > pe.z ? 1 : -1
                        var zz = pe.z + dz
                        while zz != z { l.append((xm, zz)); zz += dz }
                        l.append((xm, z))
                    }
                    if xm + 1 <= xa - 1 { for x in (xm + 1)...(xa - 1) { l.append((x, z)) } }
                    leg = l
                    break
                }
            }
            if let l = leg, !fresh(l) { leg = nil }                              // (Y5: a leg over saved ground ends the run)
            return leg
        }
        for (ti, t) in towns.enumerated() {
            guard let (z, xa, xb) = straight(t) else {
                if !t.site { flush(); prevEnd = nil }
                if ti == towns.count - 1 { flush() }
                continue
            }
            if t.site {
                // A site joins only if the next town is still reachable from it, and from the line before it (or, at
                // the west end, only with a town after it).
                let next = towns[(ti + 1)...].first(where: { !$0.site }).flatMap { straight($0) }
                var leg: [(Int, Int)]? = []
                if let ns = next, dogLeg((xb, z), ns.xa, ns.z) == nil { leg = nil }
                if let pe = prevEnd { leg = leg == nil ? nil : dogLeg(pe, xa, z) } else if next == nil { leg = nil }
                guard let leg else { if ti == towns.count - 1 { flush() }; continue }
                for (x, zz) in leg { cur.append(IVec3(x, 0, zz)) }
            } else if let pe = prevEnd {
                if let leg = dogLeg(pe, xa, z) { for (x, zz) in leg { cur.append(IVec3(x, 0, zz)) } }
                else { flush() }
            }
            let i0 = cur.count
            for x in xa...xb { cur.append(IVec3(x, 0, z)) }
            curSt.append(Station(name: t.name, index: i0 + (t.sq.x - xa), x: t.sq.x, z: z, halt: t.halt, site: t.site))
            prevEnd = (xb, z)
            if ti == towns.count - 1 { flush() }
        }
        guard bestStations.count >= need, bestStations.contains(where: { !$0.site }) || need >= oldMinStations else {
            tally?("no run of \(need) stations (straights or legs blocked)"); return nil
        }
        // No part on ground a save had generated before railways, and never over the open sea.
        for i in stride(from: 0, to: best.count, by: 24) {
            let c = best[i]
            if !legacy.isEmpty && !sc.clear(cx: floorDiv(c.x, CS), cz: floorDiv(c.z, CS), reach: 3, guardSet: legacy) { tally?("old ground"); return nil }
        }
        for i in stride(from: 0, to: best.count, by: 4) where gen.column(best[i].x, best[i].z).biome.isOcean { tally?("over the sea"); return nil }
        let first = bestStations.first!.name, last = bestStations.last!.name
        let name = lineName(first, last, gen.seed, row, s)
        if gen.fieldWorld {
            guard let h = gentleProfile(gen, best, bestStations) else { tally?("field grade"); return nil }
            let cells = best.indices.map { IVec3(best[$0].x, Int(h[$0].rounded()), best[$0].z) }
            return Line(id: key(row, s), name: name, cells: cells, stations: bestStations, heights: h)
        }
        guard let levels = profile(gen, best, bestStations) else { tally?("block profile"); return nil }
        let cells = best.indices.map { IVec3(best[$0].x, levels[$0], best[$0].z) }
        return Line(id: key(row, s), name: name, cells: cells, stations: bestStations)
    }

    static func lineName(_ a: String, _ b: String, _ seed: UInt64, _ row: Int, _ s: Int) -> String {
        let firstWord = { (n: String) in String(n.split(separator: " ").first ?? Substring(n)) }
        let kinds = ["Railway", "Rail Road", "Line", "Railway", "Western"]
        let k = kinds[Int(hashf(row, s, 0xC1B, UInt32(truncatingIfNeeded: seed)) * Float(kinds.count)) % kinds.count]
        return "\(firstWord(a)) & \(firstWord(b)) \(k)"
    }

    // The rail y along the run: the land plus one, at most one up or down a step; curves, their neighbours and each
    // station's platform level; no single-block dips or humps. Nil where the land is too wild (a cliff the track can't
    // climb between two fixed levels).
    static func profile(_ gen: WorldGen, _ cells: [IVec3], _ stations: [Station]) -> [Int]? {
        let n = cells.count
        guard n > 2 else { return nil }
        var target = [Int](repeating: SEA + 2, count: n)
        for i in 0..<n {
            let c = cells[i]
            let col = gen.column(c.x, c.z)
            let g = col.biome == .river || col.biome.isOcean ? SEA : gen.groundY(c.x, c.z)
            target[i] = max(SEA + 2, min(CH - 12, g + 1))
        }
        // Fixed levels: each curve with a cell either side, and each platform (16 cells about the station).
        var fixed = [Int?](repeating: nil, count: n)
        func isCurve(_ i: Int) -> Bool {
            guard i > 0 && i + 1 < n else { return false }
            let a = cells[i], p = cells[i - 1], q = cells[i + 1]
            return (a.x - p.x) != (q.x - a.x) || (a.z - p.z) != (q.z - a.z)
        }
        for i in 0..<n where isCurve(i) {
            // (A dog-leg one or two blocks across has two curves close together: the second takes the first's level.)
            let window = target[max(0, i - 2)...min(n - 1, i + 2)].sorted()
            let lv = fixed[i] ?? fixed[i - 1] ?? window[window.count / 2]
            for j in max(0, i - 1)...min(n - 1, i + 1) { fixed[j] = fixed[j] ?? lv }
        }
        for st in stations {
            let a = max(0, st.index - 8), b = min(n - 1, st.index + 8)
            let lv = target[a...b].sorted()[(b - a) / 2]
            for j in a...b where fixed[j] == nil { fixed[j] = lv }
        }
        // Between fixed runs, reachability bands keep every step within one block.
        var r = target
        for i in 0..<n { if let f = fixed[i] { r[i] = f } }
        // Clamp each free cell into the band reachable from the fixed cells before and after it.
        var lastFix: (Int, Int)? = nil
        var lo = [Int](repeating: Int.min / 4, count: n), hi = [Int](repeating: Int.max / 4, count: n)
        for i in 0..<n {
            if let f = fixed[i] { lastFix = (i, f) }
            if let (j, f) = lastFix { lo[i] = max(lo[i], f - (i - j)); hi[i] = min(hi[i], f + (i - j)) }
        }
        lastFix = nil
        for i in stride(from: n - 1, through: 0, by: -1) {
            if let f = fixed[i] { lastFix = (i, f) }
            if let (j, f) = lastFix { lo[i] = max(lo[i], f - (j - i)); hi[i] = min(hi[i], f + (j - i)) }
        }
        for i in 0..<n {
            if lo[i] > hi[i] { return nil }
            r[i] = max(lo[i], min(hi[i], r[i]))
        }
        for _ in 0..<3 {
            for i in 1..<n where fixed[i] == nil { r[i] = max(r[i - 1] - 1, min(r[i - 1] + 1, r[i])) }
            for i in stride(from: n - 2, through: 0, by: -1) where fixed[i] == nil { r[i] = max(r[i + 1] - 1, min(r[i + 1] + 1, r[i])) }
            for i in 1..<(n - 1) where fixed[i] == nil {
                if r[i - 1] > r[i] && r[i + 1] > r[i] { r[i] += 1 }
                if r[i - 1] < r[i] && r[i + 1] < r[i] { r[i] -= 1 }
            }
        }
        // Slopes only on straights: a cell next to a curve is level with it (fixed above), and a slope's two
        // neighbours lie along its own axis.
        for i in 1..<n where abs(r[i] - r[i - 1]) > 1 { return nil }
        for i in 1..<(n - 1) where (r[i - 1] > r[i] && r[i + 1] > r[i]) || (r[i - 1] < r[i] && r[i + 1] < r[i]) { return nil }
        // Too wild: track more than 28 blocks off the land (a deep valley or a mountain the whole way).
        for i in 0..<n where abs(r[i] - target[i]) > 28 { return nil }
        return r
    }

    // P379 step 3 (P337 (d)): a field world's track height along the run: the land plus one, rising or falling at most
    // `grade` a step (1 in 8), curves and platforms level at whole blocks, smoothed so the grade eases in and out. The
    // rail block stands at the rounded height (so a rail cell changes level by one at most per step and minecarts keep
    // their slopes); the drawn bed is shaped to the height itself (FieldTerrain.split: Railways.shapeBed).
    static let grade: Float = 1.0 / 8
    static func gentleProfile(_ gen: WorldGen, _ cells: [IVec3], _ stations: [Station]) -> [Float]? {
        let n = cells.count
        guard n > 2 else { return nil }
        var target = [Float](repeating: Float(SEA + 2), count: n)
        for i in 0..<n {
            let c = cells[i]
            let col = gen.column(c.x, c.z)
            let g = col.biome == .river || col.biome.isOcean ? SEA : gen.groundY(c.x, c.z)
            target[i] = Float(max(SEA + 2, min(CH - 12, g + 1)))
        }
        var fixed = [Float?](repeating: nil, count: n)
        func isCurve(_ i: Int) -> Bool {
            guard i > 0 && i + 1 < n else { return false }
            let a = cells[i], p = cells[i - 1], q = cells[i + 1]
            return (a.x - p.x) != (q.x - a.x) || (a.z - p.z) != (q.z - a.z)
        }
        for i in 0..<n where isCurve(i) {
            let window = target[max(0, i - 2)...min(n - 1, i + 2)].sorted()
            let lv = fixed[i] ?? window[window.count / 2]
            for j in max(0, i - 1)...min(n - 1, i + 1) { fixed[j] = fixed[j] ?? lv }
        }
        for st in stations {
            let a = max(0, st.index - 8), b = min(n - 1, st.index + 8)
            let lv = target[a...b].sorted()[(b - a) / 2]
            for j in a...b where fixed[j] == nil { fixed[j] = lv }
        }
        // The band each cell can reach from the fixed cells before and after it at the grade.
        var lo = [Float](repeating: -1e9, count: n), hi = [Float](repeating: 1e9, count: n)
        var last: (Int, Float)? = nil
        for i in 0..<n {
            if let f = fixed[i] { last = (i, f) }
            if let (j, f) = last { let r = Float(i - j) * grade; lo[i] = max(lo[i], f - r); hi[i] = min(hi[i], f + r) }
        }
        last = nil
        for i in stride(from: n - 1, through: 0, by: -1) {
            if let f = fixed[i] { last = (i, f) }
            if let (j, f) = last { let r = Float(j - i) * grade; lo[i] = max(lo[i], f - r); hi[i] = min(hi[i], f + r) }
        }
        var h = target
        for i in 0..<n {
            if lo[i] > hi[i] + 1e-3 { tally?("grade: fixed levels too far apart"); return nil }
            h[i] = fixed[i] ?? max(lo[i], min(hi[i], h[i]))
        }
        // Hold the grade (forward and back), then ease it: a running mean over 9 steps, kept in the bands.
        for _ in 0..<4 {
            for i in 1..<n where fixed[i] == nil { h[i] = max(h[i - 1] - grade, min(h[i - 1] + grade, h[i])) }
            for i in stride(from: n - 2, through: 0, by: -1) where fixed[i] == nil { h[i] = max(h[i + 1] - grade, min(h[i + 1] + grade, h[i])) }
            var m = h
            for i in 0..<n where fixed[i] == nil {
                let a = max(0, i - 4), b = min(n - 1, i + 4)
                var sum: Float = 0
                for j in a...b { sum += h[j] }
                m[i] = max(lo[i], min(hi[i], sum / Float(b - a + 1)))
            }
            h = m
        }
        for i in 1..<n where abs(h[i] - h[i - 1]) > grade + 0.01 { return nil }
        for i in 0..<n where abs(h[i] - target[i]) > 28 { tally?("grade: track 28+ off the land"); return nil }
        return h
    }

    // The bed's cells across the track at step i (along x the bed spans z-1...z+1; along z, x-1...x+1; both at a curve).
    static func bed(_ l: Line, _ i: Int) -> (alongX: Bool, cells: [(Int, Int)]) {
        let n = l.cells.count, c = l.cells[i]
        let alongX = (i + 1 < n ? l.cells[i + 1].x != c.x : (i > 0 && l.cells[i - 1].x != c.x))
        let curve = i > 0 && i + 1 < n && (l.cells[i + 1].x - c.x != c.x - l.cells[i - 1].x || l.cells[i + 1].z - c.z != c.z - l.cells[i - 1].z)
        var bed: [(Int, Int)] = []
        for d in -1...1 {
            if alongX || curve { bed.append((c.x, c.z + d)) }
            if !alongX || curve { bed.append((c.x + d, c.z)) }
        }
        if curve { bed += [(c.x - 1, c.z - 1), (c.x + 1, c.z - 1), (c.x - 1, c.z + 1), (c.x + 1, c.z + 1)] }
        return (alongX, bed)
    }

    // P379 step 3: a field world's ballast drawn at the track's own height. Each bed cell's ground (the cell under the
    // rail) and the rail's cell get densities whose zero crossing lies at the planned height, so the bed rises and falls
    // with the track on a slope instead of in block steps. Only ground the field holds (a trestle's deck is a block).
    static func shapeBed(_ gen: WorldGen, _ fd: inout [Int8], cx: Int, cz: Int) {
        let bx = cx * CS, bz = cz * CS
        for l in near(gen, x0: bx, z0: bz, x1: bx + CS - 1, z1: bz + CS - 1, pad: 2) {
            guard let hs = l.heights else { continue }
            for i in l.cells.indices {
                let c = l.cells[i]
                guard c.x >= bx - 2 && c.x < bx + CS + 2 && c.z >= bz - 2 && c.z < bz + CS + 2, c.y >= 1 && c.y < CH else { continue }
                let f = max(-0.45, min(0.45, hs[i] - Float(c.y)))
                for (x, z) in bed(l, i).cells where x >= bx && x < bx + CS && z >= bz && z < bz + CS {
                    let j = (x - bx) + (z - bz) * CS + c.y * CSQ
                    guard fd[j - CSQ] > 0, fd[j] <= 0 else { continue }
                    fd[j - CSQ] = FieldTerrain.q(0.5 + f)
                    fd[j] = FieldTerrain.q(-(0.5 - f))
                }
            }
        }
    }

    // MARK: Drawing

    static let clearable: [Bool] = {
        var t = [Bool](repeating: false, count: Blocks.count)
        for i in 0..<Blocks.count {
            let k = Blocks.key(Blocks.groupBase[i])
            if k.hasSuffix("_log") || k.hasSuffix("_leaves") || k.hasSuffix("_wood") || k == "vine" || k == "snow" { t[i] = true }
        }
        return t
    }()

    // Lays the railways through this chunk (StructureCache.after, after the roads).
    static func draw(_ gen: WorldGen, _ w: inout StructWriter, _ cx: Int, _ cz: Int) {
        let bx = cx * CS, bz = cz * CS
        let lines = near(gen, x0: bx, z0: bz, x1: bx + CS - 1, z1: bz + CS - 1, pad: 8)
        guard !lines.isEmpty, Blocks.has("rail") else { return }
        for l in lines { draw(l, &w) }
    }

    static func draw(_ l: Line, _ w: inout StructWriter) {
        func g(_ n: String, _ f: BlockID) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let rail = g("rail", AIR), ballast = g("gravel", STONE), deck = g("spruce_planks", PLANKS), leg = g("spruce_log", LOG)
        let stop = g("stone_bricks", STONE), plat = g("stone_bricks", STONE)
        let platEdge = g("smooth_stone", plat), lamp = g("lantern", AIR), post = g("spruce_fence", leg)
        let wall = g("spruce_planks", PLANKS), roof = g("dark_oak_planks", PLANKS), glass = g("glass_pane", AIR)
        let water = Blocks.has("water") ? Blocks.id("water") : AIR
        let bx = w.bx, bz = w.bz
        func inChunk(_ x: Int, _ z: Int, pad: Int) -> Bool { x >= bx - pad && x < bx + CS + pad && z >= bz - pad && z < bz + CS + pad }
        let n = l.cells.count
        for i in 0..<n {
            let c = l.cells[i], y = c.y
            guard inChunk(c.x, c.z, pad: 2) else { continue }
            // Across the track: along x the bed spans z-1...z+1; along z it spans x-1...x+1 (both at a curve).
            let (alongX, bed) = Railways.bed(l, i)
            for (x, z) in bed where w.inside(x, y, z) {
                // Cutting / tunnel: four clear blocks over the track; trees overhead go (no floating trunks).
                for yy in y...(y + 3) { w.set(x, yy, z, AIR) }
                var yy = y + 4
                while yy < CH - 1 && Int(w.get(x, yy, z)) < clearable.count && clearable[Int(w.get(x, yy, z))] { w.set(x, yy, z, AIR); yy += 1 }
                let ground = w.get(x, y - 1, z)
                // R22: gravel only on firm ground; over a cave or a ravine's lip the bed is stone (gravel fell out at the
                // first block update and left the rail over the hole).
                if Blocks.opaque[Int(ground)] && Blocks.collide[Int(ground)] { w.set(x, y - 1, z, w.firmUnder(x, y - 1, z) ? ballast : plat) }
                else {
                    w.set(x, y - 1, z, deck)                                       // trestle deck
                    let edge = (alongX && z != c.z) || (!alongX && x != c.x)
                    if edge && i % 4 == 0 { w.groundDown(x, y - 2, z, leg, minY: y - 48) }
                }
            }
            // Over water the deck's centre gets a leg too (a bridge pier).
            if i % 8 == 4, w.inside(c.x, y - 2, c.z), w.get(c.x, y - 2, c.z) == water || w.get(c.x, y - 2, c.z) == AIR {
                if !(Blocks.opaque[Int(w.get(c.x, y - 1, c.z))]) || w.get(c.x, y - 1, c.z) == deck { w.groundDown(c.x, y - 2, c.z, leg, minY: y - 48) }
            }
        }
        // Buffer stops past both ends (P337 (a): the line ended at a single block): the bed runs on two cells past
        // the last rail, a timber beam across it on a stone sill, posts at its ends and the red board in the middle.
        let beam = g("stripped_spruce_log", leg)
        for (i, j) in [(0, 1), (n - 1, n - 2)] where n > 1 {
            let c = l.cells[i], d = IVec3(c.x - l.cells[j].x, 0, c.z - l.cells[j].z)
            let px = d.z != 0 ? 1 : 0, pz = d.x != 0 ? 1 : 0                 // across the track
            for k in 1...2 { for a in -1...1 {
                let x = c.x + d.x * k + px * a, z = c.z + d.z * k + pz * a
                guard w.inside(x, c.y, z) else { continue }
                for yy in c.y...(c.y + 3) { w.set(x, yy, z, AIR) }
                if Blocks.opaque[Int(w.get(x, c.y - 1, z))] { w.set(x, c.y - 1, z, ballast) } else { w.set(x, c.y - 1, z, stop); w.groundDown(x, c.y - 2, z, stop, minY: c.y - 24) }
                if k == 1 {
                    w.set(x, c.y, z, a == 0 ? stop : beam)
                    w.set(x, c.y + 1, z, a == 0 ? g("red_wool", stop) : post)
                    if a != 0 { w.set(x, c.y + 2, z, lamp) }
                }
            } }
        }
        // Stations: the platform on the town (north) side, the station house across the track.
        for st in l.stations {
            let c = l.cells[st.index], y = c.y
            guard inChunk(c.x, c.z, pad: 12) else { continue }
            let half = st.halt ? 4 : 8
            for dx in -half...half {
                let i = st.index + dx
                guard i >= 0 && i < n else { continue }
                let x = l.cells[i].x, yy = l.cells[i].y
                for dz in 2...3 where w.inside(x, yy, c.z - dz) {
                    w.set(x, yy - 1, c.z - dz, dz == 2 ? platEdge : plat)
                    for k in 0...3 { w.set(x, yy + k, c.z - dz, AIR) }
                    w.groundDown(x, yy - 2, c.z - dz, plat, minY: yy - 24)
                }
                if dx % 6 == 0 && w.inside(x, yy, c.z - 3) { w.set(x, yy, c.z - 3, post); w.set(x, yy + 1, c.z - 3, post); w.set(x, yy + 2, c.z - 3, lamp) }
            }
            if st.halt {
                // A hamlet's halt: the platform and a name board on it, no station house.
                if w.inside(c.x, y, c.z - 3) { AshWar.sign(&w, c.x, y, c.z - 3, facing: (0, 1), ["", "\(st.name)", "Halt", ""]) }
                continue
            }
            // The station house: 7 x 5 south of the track, its door and windows facing the track.
            let hx0 = c.x - 3, hz0 = c.z + 3
            for hx in hx0...(hx0 + 6) { for hz in hz0...(hz0 + 4) where w.inside(hx, y, hz) {
                let edge = hx == hx0 || hx == hx0 + 6 || hz == hz0 || hz == hz0 + 4
                w.set(hx, y - 1, hz, plat)
                w.groundDown(hx, y - 2, hz, plat, minY: y - 24)
                for k in 0...3 { w.set(hx, y + k, hz, edge ? wall : AIR) }
                w.set(hx, y + 4, hz, roof)
                if edge && (hx == hx0 + 1 || hx == hx0 + 5 || hz == hz0 + 2) && (hx != hx0 + 3) { w.set(hx, y + 1, hz, glass) }
            } }
            // The walk from the track to the door: a plank crossing over the rail bed's edge and an open doorway.
            if w.inside(c.x, y, hz0) { w.set(c.x, y, hz0, AIR); w.set(c.x, y + 1, hz0, AIR) }
            for hz in (c.z + 2)...(hz0 - 1) where w.inside(c.x, y, hz) {
                w.set(c.x, y - 1, hz, platEdge); for k in 0...2 { w.set(c.x, y + k, hz, AIR) }
            }
            if w.inside(hx0 + 3, y + 1, hz0 + 3) { w.set(hx0 + 3, y + 1, hz0 + 3, lamp) }
            // The signs: the town's name over the door, the ticket board beside it (both face the track, north).
            if w.inside(c.x - 2, y + 2, hz0 - 1) {
                AshWar.sign(&w, c.x - 2, y, hz0 - 1, facing: (0, -1), ["", "\(st.name)", "Station", ""])
            }
            if w.inside(c.x + 2, y, hz0 - 1) {
                AshWar.sign(&w, c.x + 2, y, hz0 - 1, facing: (0, -1), [Trains.ticketWord, l.name, "Fares and", "times"])
            }
        }
        // The rails last: a curve's bed (and a station's clearing) spans its neighbours' cells and would clear their rails.
        for (i, c) in l.cells.enumerated() where w.inside(c.x, c.y, c.z) {
            w.set(c.x, c.y, c.z, rail + BlockID(l.shape(i)))
            for k in 1...2 where w.get(c.x, c.y + k, c.z) != AIR { w.set(c.x, c.y + k, c.z, AIR) }
        }
    }

    // MARK: Queries

    // The station (and its line) whose platform is within `r` blocks of p.
    static func station(_ gen: WorldGen, near p: V3, within r: Int = 24, wait: Bool = true) -> (Line, Station)? {
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        for l in near(gen, x0: x - r, z0: z - r, x1: x + r, z1: z + r, pad: r, wait: wait) {
            if let s = l.station(near: x, z, within: r) { return (l, s) }
        }
        return nil
    }
}
