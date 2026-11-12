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
        var target: Int64 = 0              // a link's: the key of the line it runs on to (0: a line, or a link of before)
        var joins = -1                     // P511, a loop's (RailLoops.swift): the line's cell it comes back into
        var diagonal = false               // N12: planned with diagonal legs and eased turns (wider bed, beds by nearest cell)
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

    // P510 (the link checks: a link's first step not next to its line's end, "snow past" a linked end): one cache for
    // every generator, emptied whenever another generator asked (a harness world streaming beside the one checked,
    // or the map's own), so a line was planned again and again; and a line's plan can come out otherwise when the
    // structures round it were planned in another order, so a link planned off one plan of its line met another.
    // Each generator (and mode) keeps its own plans now, the four last used.
    private struct Plans { var lines: [Int64: Line?] = [:]; var planning: Set<Int64> = []; var used = 0 }
    private static var plans: [Int: Plans] = [:]                // by generator serial * 4 + mode (fieldWorld 1, railSites 2)
    private static var plansClock = 0
    private static let lock = NSCondition()                 // (a condition: a caller waits for a plan another thread is making)
    // Item 11 (Nov 10, a saved world's launch under callgrind): the first ring's chunks, made four at a time, each
    // planned the same lines at once (133-137 plans for 60 lines; the plans were 41% of making the ring): a
    // caller that needs a line another thread is planning now waits for that plan (up to 5 s, then plans it itself).
    // Lines never wait on links or on anything that waits, so no two threads wait on each other. BS_OLDRAILWAIT=1:
    // every caller plans it, as before. railPlansMade / railPlansWaited count them (the launch harness prints them).
    static let oldWait = ProcessInfo.processInfo.environment["BS_OLDRAILWAIT"] == "1"
    private(set) static var railPlansMade = 0, railPlansWaited = 0
    // N12 (Nov 12 06:19:15-06:19:55, riding a line: "we need to make sure is that the tracks aren't so autistic. Like
    // currently they're following block patterns... We want them to be able to go diagonal", "Diagonal is a value",
    // "when they turn, do a 90-degree turn, that's not natural"; Carbon's proposal docs/carbon/diagonal-rails.md, applied
    // by intent): in a field world a line's legs between towns, a link's way and a loop's corners run diagonal with
    // eased turns, as a staircase of cells (the rails stay 4-connected for minecarts and saves) that ShapeRails draws
    // and Trains.Track runs as one smooth line. Already-generated lines don't move: a line, link or loop whose old way
    // or new way comes within 3 chunks of ground a save had before N12 (structure-guard-n12.txt) keeps its old way
    // exactly. BS_OLDRAILS=1: the old ways everywhere (and the old drawing and train paths).
    static let oldRails = ProcessInfo.processInfo.environment["BS_OLDRAILS"] == "1"
    // Whether any of these cells comes within `reach` chunks of ground saved before N12.
    static func savedBeforeN12(_ sc: StructureCache, _ cells: [IVec3], reach: Int = 3) -> Bool {
        guard !sc.legacyN12.isEmpty, !cells.isEmpty else { return false }
        for i in stride(from: 0, to: cells.count, by: 8) where !sc.clear(cx: floorDiv(cells[i].x, CS), cz: floorDiv(cells[i].z, CS), reach: reach, guardSet: sc.legacyN12) { return true }
        let l = cells[cells.count - 1]
        return !sc.clear(cx: floorDiv(l.x, CS), cz: floorDiv(l.z, CS), reach: reach, guardSet: sc.legacyN12)
    }
    // The N12 gate: the old plan where saved ground holds it (or would hold the new one), else the new plan (else the old).
    static func gated(_ gen: WorldGen, old: () -> Line?, new: () -> Line?) -> Line? {
        guard !oldRails, gen.fieldWorld, let sc = gen.structures else { return old() }
        if sc.legacyN12.isEmpty { return new() ?? old() }
        let o = old()
        if let o, savedBeforeN12(sc, o.cells) { return o }
        guard let d = new(), !savedBeforeN12(sc, d.cells) else { return o }
        return d
    }

    static func key(_ row: Int, _ s: Int) -> Int64 { Int64(row) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: s))) }

    // The line of village row `row`, stretch `s` (regions s*stretch ..< (s+1)*stretch), if one runs there.
    // `wait: false` (the frame thread: Trains, P440): a line not planned yet is planned on a worker and left out until
    // then. Planning one took 1.1 s of a frame in the debug harness (perfscenes forest24: "trains" 1164 ms flying into new
    // land), a long stall on the headset too.
    static func line(_ gen: WorldGen, row: Int, stretch s: Int, wait: Bool = true) -> Line? {
        guard on else { return nil }
        return cached(gen, key(row, s), wait: wait) { plan(gen, row: row, stretch: s) }
    }

    // A plan by key from the cache, planned now (wait) or on a worker and left out until then.
    static func cached(_ gen: WorldGen, _ k: Int64, wait: Bool, _ make: @escaping () -> Line?) -> Line? {
        let mode = (gen.fieldWorld ? 1 : 0) | (gen.railSites ? 2 : 0)
        let ck = gen.planSerial &* 4 &+ mode
        lock.lock()
        plansClock += 1
        if plans[ck] == nil {
            if plans.count >= 4, let old = plans.min(by: { $0.value.used < $1.value.used })?.key { plans[old] = nil }
            plans[ck] = Plans()
        }
        plans[ck]!.used = plansClock
        if let c = plans[ck]!.lines[k] { lock.unlock(); return c }
        func keep(_ l: Line?) {
            guard plans[ck] != nil else { return }
            plans[ck]!.lines[k] = l
            if plans[ck]!.lines.count > 2048 { plans[ck]!.lines.removeAll() }
        }
        if !wait {
            let start = !plans[ck]!.planning.contains(k)
            if start { plans[ck]!.planning.insert(k) }
            lock.unlock()
            if start {
                DispatchQueue.global(qos: .utility).async {
                    let l = make()
                    lock.lock()
                    keep(l)
                    plans[ck]?.planning.remove(k)
                    lock.broadcast()
                    lock.unlock()
                }
            }
            return nil
        }
        var mine = false
        if !oldWait {
            if plans[ck]!.planning.contains(k) {
                let until = Date(timeIntervalSinceNow: 5)
                railPlansWaited += 1
                while plans[ck]?.planning.contains(k) == true, plans[ck]?.lines[k] == nil, lock.wait(until: until) {}
                if let c = plans[ck]?.lines[k] { lock.unlock(); return c }
            } else {
                plans[ck]!.planning.insert(k); mine = true
            }
        }
        railPlansMade += 1
        lock.unlock()
        let l = make()
        lock.lock()
        if mine { plans[ck]?.planning.remove(k); lock.broadcast() }
        // (planned meanwhile on another thread: that plan stands, so every caller sees one plan)
        if let c = plans[ck]?.lines[k] { lock.unlock(); return c }
        keep(l)
        lock.unlock()
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

    // MARK: P510 links

    // P510 (Nov 1 16:06-16:07, at a line's buffer stops: "The train should never end... Goes on forever... Trains keeps
    // connecting shit to shit"; 20:37-20:38, "Why does the railroad stop here?", "No, this whole thing where it stops, I
    // don't like that. It can't stop... The train doesn't stop. It goes on forever"): a line no longer ends at buffers
    // when another line lies on along its row. Its east end runs on, by a link of track (a dog-leg like a leg between
    // towns, cuttings, trestles and all), to the west end of the next line east in the row, up to `linkReach` stretches
    // on; the buffer stops stand only where nothing lies on (or the link can't be laid: the sea, a structure in every
    // way, a cliff, ground a save had before P510). A train he rides runs on through (Trains.through).
    static let linkReach = 3
    // A link's id is its line's with bit 60 flipped. (It was bit 62 set, but a line in a row south of 0 has its row's
    // sign in every high bit, bit 62 too: its link's key was the line's own, so link() handed back the line itself, every
    // such line counted as a link and its "link" ran from its own end through its own cells: the link checks' "step 1 not
    // adjacent", "height jumps -7.41", "snow past" a linked end, and 9 of 128 lines linked. A row's index stays far
    // inside 2^27, so its bit 28 always matches its sign, and flipped it marks a link.)
    static let linkFlip: Int64 = 1 << 60
    static func linkKey(_ row: Int, _ s: Int) -> Int64 { key(row, s) ^ linkFlip }
    static func isLink(_ id: Int64) -> Bool { let r = id >> 32; return r >= 1 << 27 || r < -(1 << 27) }
    static func rowStretch(_ id: Int64) -> (row: Int, s: Int) {
        let k = isLink(id) ? id ^ linkFlip : id
        return (Int(k >> 32), Int(Int32(truncatingIfNeeded: k)))
    }
    static var linksOn = true                         // (checks compare)
    static var banked = 0                             // (checks: bed cells banked up with earth instead of a trestle)
    static var deckNotes: [String: String] = [:]      // (checks: a field line's deck cell -> the column the writer saw under it)
    static let noteLock = NSLock()

    // The link from line (row, s)'s east end on to the next line east, if one is laid.
    static func link(_ gen: WorldGen, row: Int, stretch s: Int, wait: Bool = true) -> Line? {
        guard on, linksOn else { return nil }
        return cached(gen, linkKey(row, s), wait: wait) { planLink(gen, row: row, stretch: s) }
    }
    static func hasLine(_ gen: WorldGen, _ row: Int, _ s: Int) -> Bool {
        hashf(s, row, 0xC1, UInt32(truncatingIfNeeded: gen.seed) ^ 0xC1A1) < share
    }
    // The line a link runs on to (nil for a line).
    static func linkTarget(_ gen: WorldGen, _ l: Line, wait: Bool = true) -> Line? {
        guard isLink(l.id) else { return nil }
        if l.target != 0 { let (r, t) = rowStretch(l.target); return line(gen, row: r, stretch: t, wait: wait) }
        let (row, s) = rowStretch(l.id)
        for k in 1...linkReach where hasLine(gen, row, s + k) {
            if let b = line(gen, row: row, stretch: s + k, wait: wait) { return b }
            if !wait { return nil }                    // (not planned yet: asked again in a second)
        }
        return nil
    }
    // Whether line l's west end has a link coming in (from the line before it in the row) / its east end one going on.
    static func openEnds(_ gen: WorldGen, _ l: Line, wait: Bool = true) -> (west: Bool, east: Bool) {
        guard on, linksOn, !isLink(l.id) else { return (true, true) }
        let (row, s) = rowStretch(l.id)
        let east = link(gen, row: row, stretch: s, wait: wait) != nil
        return (incoming(gen, row, s, wait: wait) != nil, east)
    }
    // The line and link that run on into line (row, s)'s west end, if any: the first line west of it in its row (its
    // link is the one that comes here), or with none there, a line in the row north whose link comes south to it.
    static func incoming(_ gen: WorldGen, _ row: Int, _ s: Int, wait: Bool = true) -> (Line, Line)? {
        let me = key(row, s)
        for k in 1...linkReach where hasLine(gen, row, s - k) {
            guard let a = line(gen, row: row, stretch: s - k, wait: wait) else { continue }
            if let lk = link(gen, row: row, stretch: s - k, wait: wait), lk.target == me { return (a, lk) }
            return nil
        }
        for k in 0...linkReach where hasLine(gen, row - 1, s - k) {
            guard let a = line(gen, row: row - 1, stretch: s - k, wait: wait) else { continue }
            if let lk = link(gen, row: row - 1, stretch: s - k, wait: wait), lk.target == me { return (a, lk) }
        }
        return nil
    }

    static func planLink(_ gen: WorldGen, row: Int, stretch s: Int) -> Line? {
        gated(gen, old: { planLink(gen, row: row, stretch: s, diagonal: false) }, new: { planLink(gen, row: row, stretch: s, diagonal: true) })
    }
    static func planLink(_ gen: WorldGen, row: Int, stretch s: Int, diagonal: Bool) -> Line? {
        guard hasLine(gen, row, s), let a = line(gen, row: row, stretch: s), let sc = gen.structures else { return nil }
        var b: Line? = nil, bKey: Int64 = 0
        for k in 1...linkReach where hasLine(gen, row, s + k) {
            if let l = line(gen, row: row, stretch: s + k) { b = l; bKey = key(row, s + k); break }
        }
        // P510 (the link check: 80 of 128 lines had no line on along their row within reach, so most trains still met
        // buffers): with none, the link comes south to a line in the next row whose west end nothing else runs into
        // (no line before it in its own row), so every row's last line hands on to the row below. Only south: a west
        // end is fed from its own row or from the row north, never from two links.
        if b == nil, let pa = a.cells.last {
            south: for k in 0...linkReach where hasLine(gen, row + 1, s + k) {
                guard let l = line(gen, row: row + 1, stretch: s + k), let f = l.cells.first, f.x - pa.x >= 40 else { continue }
                for j in 1...linkReach where hasLine(gen, row + 1, s + k - j) {
                    if line(gen, row: row + 1, stretch: s + k - j) != nil { continue south }
                }
                b = l; bKey = key(row + 1, s + k)
                break
            }
        }
        guard let b, let pa = a.cells.last, let pb = b.cells.first else { tally?("link: no line on along the row"); return nil }
        // Both ends run east off a station's straight (a line's cells go west to east, its ends on straights).
        let gap = pb.x - pa.x
        guard gap >= 40 else { tally?("link: lines overlap"); return nil }
        var cells: [(Int, Int)]? = nil
        // N12: a diagonal leg with eased turns first (as a line's legs), off the sea.
        if diagonal, let l = smoothDogLeg(gen, sc, from: (pa.x, pa.z), to: (pb.x, pb.z), lead: 12, except: []),
           !stride(from: 0, to: l.count, by: 4).contains(where: { gen.column(l[$0].0, l[$0].1).biome.isOcean }) { cells = l }
        for k in 0..<7 where cells == nil {
            let xm = pa.x + gap / 2 + [0, -gap / 5, gap / 5, -gap / 3, gap / 3, -gap * 2 / 5, gap * 2 / 5][k]
            if xm - pa.x < 12 || pb.x - xm < 12 { continue }
            if blocked(gen, sc, x0: pa.x + 3, z0: pa.z, x1: xm, z1: pa.z, except: []) { continue }
            if pa.z != pb.z && blocked(gen, sc, x0: xm, z0: pa.z, x1: xm, z1: pb.z, except: []) { continue }
            if blocked(gen, sc, x0: xm, z0: pb.z, x1: pb.x - 3, z1: pb.z, except: []) { continue }
            var l: [(Int, Int)] = []
            for x in (pa.x + 1)...xm { l.append((x, pa.z)) }
            if pa.z != pb.z {
                let dz = pb.z > pa.z ? 1 : -1
                var zz = pa.z + dz
                while zz != pb.z { l.append((xm, zz)); zz += dz }
                l.append((xm, pb.z))
            }
            if xm + 1 <= pb.x - 1 { for x in (xm + 1)...(pb.x - 1) { l.append((x, pb.z)) } }
            cells = l
            break
        }
        // P510 (the link check: 6 of 128 lines linked once a link's key was its own): the seven straight dog-legs
        // across up to three stretches (thousands of blocks) almost always met a town, a ruin or the sea. Then the link
        // finds its way round them (route) as a road does, keeping off the sea and old ground.
        if let l = cells, stride(from: 0, to: l.count, by: 4).contains(where: { gen.column(l[$0].0, l[$0].1).biome.isOcean }) { cells = nil }
        let routed = cells == nil
        if routed { cells = route(gen, sc, from: (pa.x, pa.z), to: (pb.x, pb.z), diagonal: diagonal) }
        guard let run = cells, run.count > 8 else { tally?("link: blocked"); return nil }
        // Only on ground no save had before railways or before links (no half a link under explored land), never over
        // the open sea.
        for (i, c) in run.enumerated() where i % 8 == 0 || i == run.count - 1 {
            let cx = floorDiv(c.0, CS), cz = floorDiv(c.1, CS)
            if !sc.legacyC1.isEmpty && !sc.clear(cx: cx, cz: cz, reach: 3, guardSet: sc.legacyC1) { tally?("link: old ground"); return nil }
            if !sc.legacyP510.isEmpty && !sc.clear(cx: cx, cz: cz, reach: 3, guardSet: sc.legacyP510) { tally?("link: old ground"); return nil }
        }
        let flat = run.map { IVec3($0.0, 0, $0.1) }
        let name = a.name
        if gen.fieldWorld {
            let h0 = a.heights?.last ?? Float(pa.y), h1 = b.heights?.first ?? Float(pb.y)
            guard let h = gentleProfile(gen, flat, [], ends: (h0, h1), diagonal: diagonal) else { tally?("link: field grade"); return nil }
            let c = flat.indices.map { IVec3(flat[$0].x, Int(h[$0].rounded()), flat[$0].z) }
            let lk = Line(id: linkKey(row, s), name: name, cells: c, stations: [], heights: h)
            lk.target = bKey
            lk.diagonal = diagonal
            return lk
        }
        guard let lv = profile(gen, flat, [], ends: (pa.y, pb.y)) else { tally?("link: block profile"); return nil }
        let c = flat.indices.map { IVec3(flat[$0].x, lv[$0], flat[$0].z) }
        let lk = Line(id: linkKey(row, s), name: name, cells: c, stations: [])
        lk.target = bKey
        return lk
    }

    // A link's way from a line's east end (a) to the next line's west end (b), round whatever stands between them: a
    // search over 16-block squares (A*, a turn costing three squares so the track runs in long straights), clear of every
    // surface structure's pieces (4 blocks off), the open sea and ground a save had before links. It leaves a east along
    // a's row for 16 blocks and comes into b the same way. The cells, one step apart (nil: no way within the search).
    static let routeCell = 16
    static let routeWander = 40 * 16                  // how far off its rows a link may go round things (linksNear looks as far)
    // P510 (the link check on build 77: of 48 links with no way round, nearly all were walled in by the sea, a lake or a
    // coast across the whole band, and the band's edges): a link may cross open water on a trestle for up to seaRun
    // squares together (a bridge as a line takes over a lake), each such square costing seaCost.
    static let seaRun = 6, seaCost: Int32 = 6
    static func route(_ gen: WorldGen, _ sc: StructureCache, from a: (Int, Int), to b: (Int, Int), diagonal: Bool = false) -> [(Int, Int)]? {
        let G = routeCell
        // (the way's ends on the middles of their squares' columns: 9-24 blocks out from each line's end)
        let s0 = (floorDiv(a.0 + G, G) * G + G / 2, a.1), e0 = (floorDiv(b.0 - G, G) * G + G / 2, b.1)
        guard e0.0 - s0.0 >= 2 * G else { tally?("link route: too short"); return nil }
        let margin = routeWander
        let gx0 = floorDiv(min(s0.0, e0.0) - 4 * G, G), gx1 = floorDiv(max(s0.0, e0.0) + 4 * G, G)
        let gz0 = floorDiv(min(s0.1, e0.1) - margin, G), gz1 = floorDiv(max(s0.1, e0.1) + margin, G)
        let nx = gx1 - gx0 + 1, nz = gz1 - gz0 + 1
        guard nx * nz <= 400_000 else { tally?("link route: too big"); return nil }
        // Blocked squares: structure pieces (padded), filled in once from the starts round the box.
        var blocked = [Bool](repeating: false, count: nx * nz)
        var blockedBy = [UInt8](repeating: 0, count: nx * nz)  // (the "no way" note: which kind of structure, by type index + 1)
        let bx0 = gx0 * G, bx1 = (gx1 + 1) * G - 1, bz0 = gz0 * G, bz1 = (gz1 + 1) * G - 1
        for (ti, t) in sc.types.enumerated() where !skipKinds.contains(t.name) && t.name != SkyIsle.kind {
            let sp = t.spacing * CS, r = t.reach * CS
            for rz in floorDiv(bz0 - r, sp)...floorDiv(bz1 + r, sp) { for rx in floorDiv(bx0 - r, sp)...floorDiv(bx1 + r, sp) {
                guard let o = sc.start(t, regionX: rx, regionZ: rz) else { continue }
                guard o.max.x + 4 >= bx0 && o.min.x - 4 <= bx1 && o.max.z + 4 >= bz0 && o.min.z - 4 <= bz1 else { continue }
                for pc in o.pieces {
                    let ax = max(gx0, floorDiv(pc.min.x - 4, G)), cx = min(gx1, floorDiv(pc.max.x + 4, G))
                    let az = max(gz0, floorDiv(pc.min.z - 4, G)), cz = min(gz1, floorDiv(pc.max.z + 4, G))
                    if ax > cx || az > cz { continue }
                    for z in az...cz { for x in ax...cx { blocked[(z - gz0) * nx + (x - gx0)] = true; blockedBy[(z - gz0) * nx + (x - gx0)] = UInt8(min(255, ti + 1)) } }
                }
            } }
        }
        // Old ground and the sea, looked at as the search reaches each square (0 not yet, 1 clear, 2 old ground, 3 sea:
        // crossed on a trestle at a cost).
        var looked = [UInt8](repeating: 0, count: nx * nz)
        func open(_ i: Int) -> Bool {
            if blocked[i] { return false }
            if looked[i] == 0 {
                let x = (gx0 + i % nx) * G + G / 2, z = (gz0 + i / nx) * G + G / 2
                let cx = floorDiv(x, CS), cz = floorDiv(z, CS)
                var v: UInt8 = 1
                if !sc.legacyC1.isEmpty && !sc.clear(cx: cx, cz: cz, reach: 2, guardSet: sc.legacyC1) { v = 2 }
                if v == 1 && !sc.legacyP510.isEmpty && !sc.clear(cx: cx, cz: cz, reach: 2, guardSet: sc.legacyP510) { v = 2 }
                if v == 1 { let b = gen.column(x, z).biome; if b.isDeepOcean { v = 4 } else if b.isOcean { v = 3 } }   // (no legs down into the deep sea)
                looked[i] = v
            }
            return looked[i] == 1 || looked[i] == 3
        }
        let start = (floorDiv(s0.1, G) - gz0) * nx + (floorDiv(s0.0, G) - gx0)
        let goal = (floorDiv(e0.1, G) - gz0) * nx + (floorDiv(e0.0, G) - gx0)
        blocked[start] = false; blocked[goal] = false; looked[start] = 1; looked[goal] = 1
        // A* over (square, heading): headings 0 east, 1 south, 2 west, 3 north.
        let dx = [1, 0, -1, 0], dz = [0, 1, 0, -1]
        let turnCost: Int32 = 3
        var cost = [Int32](repeating: .max, count: nx * nz * 4)
        var from = [Int32](repeating: -1, count: nx * nz * 4)
        let gxg = goal % nx, gzg = goal / nx
        func h(_ i: Int) -> Int32 { Int32(abs(i % nx - gxg) + abs(i / nx - gzg)) }
        var heap: [(Int32, Int32)] = []                    // (f, state)
        func push(_ f: Int32, _ st: Int32) {
            heap.append((f, st)); var c = heap.count - 1
            while c > 0 { let p = (c - 1) / 2; if heap[p].0 <= heap[c].0 { break }; heap.swapAt(p, c); c = p }
        }
        func pop() -> (Int32, Int32) {
            let top = heap[0]; let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last; var c = 0
                while true {
                    let l = 2 * c + 1, r = l + 1; var m = c
                    if l < heap.count && heap[l].0 < heap[m].0 { m = l }
                    if r < heap.count && heap[r].0 < heap[m].0 { m = r }
                    if m == c { break }; heap.swapAt(m, c); c = m
                }
            }
            return top
        }
        cost[start * 4] = 0
        push(h(start), Int32(start * 4))
        var end = -1, expanded = 0
        while !heap.isEmpty {
            let (f, st) = pop()
            let si = Int(st), i = si / 4, d = si % 4
            if f - h(i) > cost[si] { continue }
            if i == goal && d == 0 { end = si; break }
            expanded += 1
            if expanded > 600_000 { tally?("link route: search cap"); return nil }
            let x = i % nx, z = i / nx
            for nd in 0..<4 where nd != (d + 2) % 4 {
                let x2 = x + dx[nd], z2 = z + dz[nd]
                guard x2 >= 0 && x2 < nx && z2 >= 0 && z2 < nz else { continue }
                let j = z2 * nx + x2
                guard open(j) else { continue }
                let c2 = cost[si] + 1 + (nd == d ? 0 : turnCost) + (looked[j] == 3 ? seaCost : 0)
                let sj = j * 4 + nd
                if c2 < cost[sj] { cost[sj] = c2; from[sj] = Int32(si); push(c2 + h(j), Int32(sj)) }
            }
        }
        guard end >= 0 else {
            tally?("link route: no way")
            if tally != nil {
                // (what walls the search in: the squares it reached, and what stands on the squares round them)
                var reached = [Bool](repeating: false, count: nx * nz)
                for k in 0..<(nx * nz * 4) where cost[k] != .max { reached[k / 4] = true }
                let nr = reached.filter { $0 }.count
                var wall: [String: Int] = [:]
                for i in 0..<(nx * nz) where reached[i] {
                    for nd in 0..<4 {
                        let x2 = i % nx + dx[nd], z2 = i / nx + dz[nd]
                        guard x2 >= 0 && x2 < nx && z2 >= 0 && z2 < nz else { wall["edge", default: 0] += 1; continue }
                        let j = z2 * nx + x2
                        if reached[j] { continue }
                        if blocked[j] { wall[blockedBy[j] > 0 ? sc.types[Int(blockedBy[j]) - 1].name : "?", default: 0] += 1 }
                        else if looked[j] == 2 { wall["old ground", default: 0] += 1 }
                        else if looked[j] == 4 { wall["deep sea", default: 0] += 1 }
                    }
                }
                let gw = goal % nx > 0 ? (open(goal - 1) ? "open" : "shut") : "edge"
                let sx = start % nx, sz = start / nx
                let goalReached = reached[goal]
                tally?("link route detail: \(nr) of \(nx)x\(nz) squares reached from (\(sx),\(sz)), goal (\(goal % nx),\(goal / nx)) \(goalReached ? "reached" : "not reached"), west of it \(gw); walled by " + wall.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            }
            return nil
        }
        var squares: [Int] = []
        var c = end
        while c >= 0 { squares.append(c / 4); c = Int(from[c]) }
        squares.reverse()
        // (no open water longer than a trestle takes)
        var wet = 0, wettest = 0
        for q in squares { wet = looked[q] == 3 ? wet + 1 : 0; wettest = max(wettest, wet) }
        if wettest > seaRun { tally?("link route: over the sea (\(wettest) squares at a stretch)"); return nil }
        // The corners (squares where the way turns), as block points on the squares' middles; the ends on the rows.
        var pts: [(Int, Int)] = [s0]
        for k in 1..<max(1, squares.count - 1) {
            let p = squares[k - 1], q = squares[k], r = squares[k + 1]
            if q - p != r - q { pts.append(((gx0 + q % nx) * G + G / 2, (gz0 + q / nx) * G + G / 2)) }
        }
        pts.append(e0)
        // N12: the way's corners pulled straight where the straight is clear (a diagonal across the squares between),
        // then eased round, the whole way checked again; else the square way below.
        if diagonal, let d = diagonalWay(gen, sc, pts, from: a, to: b, open: { x, z in
            let qx = floorDiv(x, G) - gx0, qz = floorDiv(z, G) - gz0
            guard qx >= 0 && qx < nx && qz >= 0 && qz < nz else { return false }
            let i = qz * nx + qx
            return open(i) && looked[i] == 1
        }) { return d }
        // Along x then z between points, one block a step; then on to b along its row.
        var cells: [(Int, Int)] = []
        for x in (a.0 + 1)...s0.0 { cells.append((x, a.1)) }
        var cur = s0
        for p in pts.dropFirst() {
            while cur.0 != p.0 { cur.0 += p.0 > cur.0 ? 1 : -1; cells.append(cur) }
            while cur.1 != p.1 { cur.1 += p.1 > cur.1 ? 1 : -1; cells.append(cur) }
        }
        if e0.0 + 1 <= b.0 - 1 { for x in (e0.0 + 1)...(b.0 - 1) { cells.append((x, b.1)) } }
        // (never over itself)
        var seen = Set<Int64>()
        for c in cells where !seen.insert(Int64(c.0) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: c.1)))).inserted { tally?("link route: over itself"); return nil }
        return cells
    }

    // Links whose track may pass within `pad` blocks of the box (as `near` for lines).
    static func linksNear(_ gen: WorldGen, x0: Int, z0: Int, x1: Int, z1: Int, pad: Int = 2, wait: Bool = true) -> [Line] {
        guard on, linksOn else { return [] }
        // (a link may go round things up to routeWander off its rows)
        // (and one from the row north may come south a row)
        let r0 = floorDiv(z0 - pad - span / 2 - routeWander - routeCell, span) - 1, r1 = floorDiv(z1 + pad + span / 2 + routeWander + routeCell, span)
        let w = stretch * span
        // (a link starts in its own line's stretch and runs up to linkReach stretches on east)
        let s0 = floorDiv(x0 - pad - span, w) - linkReach, s1 = floorDiv(x1 + pad + span, w)
        var out: [Line] = []
        for row in r0...r1 { for s in s0...s1 where hasLine(gen, row, s) {
            guard let l = link(gen, row: row, stretch: s, wait: wait) else { continue }
            if l.maxX + pad < x0 || l.minX - pad > x1 || l.maxZ + pad < z0 || l.minZ - pad > z1 { continue }
            out.append(l)
        } }
        return out
    }

    // MARK: Planning

    // Kinds the track keeps clear of: everything on the surface (underground and sky kinds are left out; a cutting at
    // most a few blocks deep doesn't reach them).
    static let skipKinds: Set<String> = ["mineshaft", "ancient_city", "trial_chambers", "fossil", "buried_treasure", "stronghold"]

    // MARK: N12 diagonal ways (Carbon's proposal, docs/carbon/diagonal-rails.md)

    // A polyline with each inner corner eased by a circular arc of up to `radius` blocks (less where its legs are short).
    static func roundPolyline(_ pts: [(Float, Float)], radius: Float, arcStep: Float = 2) -> [(Float, Float)] {
        var clean: [(Float, Float)] = []
        for p in pts { if let l = clean.last, hypotf(p.0 - l.0, p.1 - l.1) < 0.25 { continue }; clean.append(p) }
        guard clean.count >= 3 else { return clean }
        var out: [(Float, Float)] = [clean[0]]
        for i in 1..<(clean.count - 1) {
            let p0 = clean[i - 1], p1 = clean[i], p2 = clean[i + 1]
            let v1 = SIMD2<Float>(p0.0 - p1.0, p0.1 - p1.1), v2 = SIMD2<Float>(p2.0 - p1.0, p2.1 - p1.1)
            let l1 = simd_length(v1), l2 = simd_length(v2)
            guard l1 > 0.5, l2 > 0.5 else { out.append(p1); continue }
            let u1 = v1 / l1, u2 = v2 / l2
            let ang = acosf(max(-0.9999, min(0.9999, simd_dot(u1, u2))))          // (the angle between the legs)
            let tanHalf = tanf(ang * 0.5)
            guard Float.pi - ang >= 0.06, tanHalf > 0.02 else { out.append(p1); continue }
            let t = min(min(l1, l2) * 0.46, radius / tanHalf)
            let r = t * tanHalf
            guard r >= 1.5 else { out.append(p1); continue }
            let c1 = SIMD2<Float>(p1.0, p1.1)
            let t1 = c1 + u1 * t, t2 = c1 + u2 * t
            let centre = c1 + simd_normalize(u1 + u2) * (r / max(0.02, sinf(ang * 0.5)))
            let a1 = atan2f(t1.y - centre.y, t1.x - centre.x), a2 = atan2f(t2.y - centre.y, t2.x - centre.x)
            var da = a2 - a1
            while da > .pi { da -= 2 * .pi }
            while da < -.pi { da += 2 * .pi }
            let segs = max(3, Int(ceilf(abs(da) * r / max(0.75, arcStep))))
            for k in 0...segs {
                let a = a1 + da * Float(k) / Float(segs)
                let q = (centre.x + r * cosf(a), centre.y + r * sinf(a))
                if let l = out.last, hypotf(q.0 - l.0, q.1 - l.1) < 0.2 { continue }
                out.append(q)
            }
        }
        let last = clean[clean.count - 1]
        if let l = out.last, hypotf(last.0 - l.0, last.1 - l.1) < 0.2 { out[out.count - 1] = last } else { out.append(last) }
        return out
    }

    // The 4-connected cells along a polyline (one step apart, each cell once: a loop the rounding made is cut out),
    // from the cell at its first point to the cell at its last.
    static func rasterPolyline(_ pts: [(Float, Float)]) -> [(Int, Int)] {
        guard let f = pts.first else { return [] }
        var raw: [(Int, Int)] = [(Int(f.0.rounded()), Int(f.1.rounded()))]
        for i in 1..<max(1, pts.count) {
            let p0 = pts[i - 1], p1 = pts[i]
            let dx = p1.0 - p0.0, dz = p1.1 - p0.1
            let steps = max(1, Int(ceilf(hypotf(dx, dz) * 3)))
            for k in 1...steps {
                let u = Float(k) / Float(steps)
                let px = p0.0 + dx * u, pz = p0.1 + dz * u
                let gx = Int(px.rounded()), gz = Int(pz.rounded())
                while raw[raw.count - 1].0 != gx || raw[raw.count - 1].1 != gz {
                    let c = raw[raw.count - 1]
                    let sx = gx - c.0, sz = gz - c.1
                    if sx != 0 && sz != 0 {
                        // (the side step nearer the line)
                        let ex = abs(Float(c.0 + sx.signum()) - px) + abs(Float(c.1) - pz)
                        let ez = abs(Float(c.0) - px) + abs(Float(c.1 + sz.signum()) - pz)
                        raw.append(ex <= ez ? (c.0 + sx.signum(), c.1) : (c.0, c.1 + sz.signum()))
                    } else if sx != 0 { raw.append((c.0 + sx.signum(), c.1)) } else { raw.append((c.0, c.1 + sz.signum())) }
                }
            }
        }
        var out: [(Int, Int)] = [], at: [Int64: Int] = [:]
        for c in raw {
            let k = colKey(c.0, c.1)
            if let j = at[k] { while out.count - 1 > j { at[colKey(out.last!.0, out.last!.1)] = nil; out.removeLast() } }
            else { at[k] = out.count; out.append(c) }
        }
        return out
    }

    // Whether cells two or more steps apart along the run touch side by side (the rails would join there).
    static func touchesItself(_ cells: [(Int, Int)]) -> Bool {
        var at: [Int64: Int] = [:]
        for (i, c) in cells.enumerated() { at[colKey(c.0, c.1)] = i }
        for (i, c) in cells.enumerated() {
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { if let j = at[colKey(c.0 + dx, c.1 + dz)], abs(j - i) > 1 { return true } }
        }
        return false
    }

    // `blocked` along a run of cells, eight at a time (the ends' `skipEnds` cells left out).
    static func polylineBlocked(_ gen: WorldGen, _ sc: StructureCache, _ cells: [(Int, Int)], skipEnds: Int, except: Set<Int64>) -> Bool {
        var i = skipEnds
        let last = cells.count - 1 - skipEnds
        while i <= last {
            let j = min(last, i + 7)
            var x0 = Int.max, x1 = Int.min, z0 = Int.max, z1 = Int.min
            for k in i...j { x0 = min(x0, cells[k].0); x1 = max(x1, cells[k].0); z0 = min(z0, cells[k].1); z1 = max(z1, cells[k].1) }
            if blocked(gen, sc, x0: x0, z0: z0, x1: x1, z1: z1, except: except) { return true }
            i = j + 1
        }
        return false
    }

    // A leg between two eastbound straights (from just east of `pe` to just west of `dst`): a diagonal across with
    // eased turns (45 degrees first, then shallower and steeper, its middle shifted either way), nil where none is clear.
    static func smoothDogLeg(_ gen: WorldGen, _ sc: StructureCache, from pe: (x: Int, z: Int), to dst: (x: Int, z: Int),
                             lead: Int, except: Set<Int64>) -> [(Int, Int)]? {
        let gap = dst.x - pe.x, dz = dst.z - pe.z, adz = abs(dz)
        guard gap >= max(24, lead * 2) else { return nil }
        let a = (Float(pe.x + 1), Float(pe.z)), b = (Float(dst.x - 1), Float(dst.z))
        func ok(_ c: [(Int, Int)]) -> Bool {
            guard let f = c.first, let l = c.last, f == (pe.x + 1, pe.z), l == (dst.x - 1, dst.z) else { return false }
            return !touchesItself(c) && !polylineBlocked(gen, sc, c, skipEnds: 0, except: except)
        }
        if adz <= 2 {
            var poly = [a]
            if dz != 0 { poly += [(Float(pe.x) + Float(gap) * 0.35, Float(pe.z)), (Float(pe.x) + Float(gap) * 0.65, Float(dst.z))] }
            poly.append(b)
            let c = rasterPolyline(roundPolyline(poly, radius: 14))
            return ok(c) ? c : nil
        }
        for want in [adz, adz * 5 / 4, adz * 3 / 2, adz * 3 / 4, max(8, adz / 2), 0] {
            let span = min(gap - 2 * lead, want)
            if span < 0 { continue }
            for sh in [0, -gap / 6, gap / 6, -gap / 4, gap / 4, -gap / 3, gap / 3] {
                let x1 = pe.x + gap / 2 + sh - span / 2, x2 = x1 + span
                if x1 - pe.x < lead || dst.x - x2 < lead { continue }
                let rad = Float(min(22, max(6, min(x1 - pe.x - 2, dst.x - x2 - 2, adz / 2))))
                let c = rasterPolyline(roundPolyline([a, (Float(x1), Float(pe.z)), (Float(x2), Float(dst.z)), b], radius: rad))
                if ok(c) { return c }
            }
        }
        return nil
    }

    // A link's routed way (route's corner points, `open` saying which ground a straight may cross) pulled straight
    // between corners where clear, eased round its turns, from just east of a to just west of b.
    static func diagonalWay(_ gen: WorldGen, _ sc: StructureCache, _ pts: [(Int, Int)], from a: (Int, Int), to b: (Int, Int),
                            open: (Int, Int) -> Bool) -> [(Int, Int)]? {
        guard pts.count >= 2 else { return nil }
        func clear(_ p: (Int, Int), _ q: (Int, Int)) -> Bool {
            let n = max(1, Int(hypotf(Float(q.0 - p.0), Float(q.1 - p.1)) / 4))
            for k in 0...n {
                let u = Float(k) / Float(n)
                if !open(Int((Float(p.0) + Float(q.0 - p.0) * u).rounded()), Int((Float(p.1) + Float(q.1 - p.1) * u).rounded())) { return false }
            }
            return true
        }
        var keep = [pts[0]], i = 0
        while i < pts.count - 1 {
            var j = pts.count - 1
            while j > i + 1 && !clear(pts[i], pts[j]) { j -= 1 }
            keep.append(pts[j]); i = j
        }
        var poly: [(Float, Float)] = [(Float(a.0 + 1), Float(a.1))]
        poly += keep.map { (Float($0.0), Float($0.1)) }
        poly.append((Float(b.0 - 1), Float(b.1)))
        let c = rasterPolyline(roundPolyline(poly, radius: 14))
        guard let f = c.first, let l = c.last, f == (a.0 + 1, a.1), l == (b.0 - 1, b.1), c.count > 8, !touchesItself(c),
              !polylineBlocked(gen, sc, c, skipEnds: 2, except: []),
              !stride(from: 0, to: c.count, by: 4).contains(where: { gen.column(c[$0].0, c[$0].1).biome.isOcean }) else { return nil }
        return c
    }

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
        gated(gen, old: { plan(gen, row: row, stretch: s, diagonal: false) }, new: { plan(gen, row: row, stretch: s, diagonal: true) })
    }
    static func plan(_ gen: WorldGen, row: Int, stretch s: Int, diagonal: Bool) -> Line? {
        if let l = plan(gen, row: row, stretch: s, avoid: nil, need: oldMinStations, diagonal: diagonal) { return l }
        guard let sc = gen.structures else { return nil }
        // Y5: the line as before failed; on an old save, its stations and legs on fresh ground still make a line.
        if !sc.legacyC1.isEmpty, let fresh = FreshGround.guardSet(sc), let l = plan(gen, row: row, stretch: s, avoid: fresh, need: oldMinStations, diagonal: diagonal) { return l }
        // P470 ("the trains were never added": over his playtests he never met one; 64 of 80 stretches round his
        // Capital City had fewer than three towns): two stations (towns or major sites) make a line, on ground no save
        // had generated before P470 (structure-guard-p470.txt), so explored land never grows half a railway.
        return plan(gen, row: row, stretch: s, avoid: sc.legacyP470.isEmpty ? nil : sc.legacyP470, need: minStations, diagonal: diagonal)
    }

    // `avoid`: chunks no part of the line may come within 3 chunks of (a town or leg there ends the run).
    // `need`: stations a line needs (P470: with two, the major sites count toward it before the towns are counted).
    static func plan(_ gen: WorldGen, row: Int, stretch s: Int, avoid: Set<Int64>?, need: Int, diagonal: Bool = false) -> Line? {
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
            // (N12: a diagonal leg with eased turns where one fits)
            if diagonal, let l = smoothDogLeg(gen, sc, from: pe, to: (xa, z), lead: 8, except: except), fresh(l) { return l }
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
            guard let h = gentleProfile(gen, best, bestStations, diagonal: diagonal) else { tally?("field grade"); return nil }
            let cells = best.indices.map { IVec3(best[$0].x, Int(h[$0].rounded()), best[$0].z) }
            let l = Line(id: key(row, s), name: name, cells: cells, stations: bestStations, heights: h)
            l.diagonal = diagonal
            return l
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
    static func profile(_ gen: WorldGen, _ cells: [IVec3], _ stations: [Station], ends: (Int, Int)? = nil) -> [Int]? {
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
            for j in thru(max(0, i - 1), min(n - 1, i + 1)) { fixed[j] = fixed[j] ?? lv }
        }
        for st in stations {
            let a = max(0, st.index - 8), b = min(n - 1, st.index + 8)
            let lv = target[a...b].sorted()[(b - a) / 2]
            for j in a...b where fixed[j] == nil { fixed[j] = lv }
        }
        if let (e0, e1) = ends { for j in 0..<min(3, n) { fixed[j] = e0; fixed[n - 1 - j] = e1 } }      // (P510: a link meets its lines level)
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
    // `floatCurves`: a curve is levelled within what the ends reach at the grade (nearest its ground) instead of at its
    // ground, the track cut or banked to it (a terminus loop: its four corners on ground up to 10 apart were each fixed
    // at their own, and half the loops in the rail check failed the grade: "loop: field grade" 127 of 256 ends).
    static func gentleProfile(_ gen: WorldGen, _ cells: [IVec3], _ stations: [Station], ends: (Float, Float)? = nil, floatCurves: Bool = false,
                              diagonal: Bool = false) -> [Float]? {
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
        // (N12: a diagonal line's staircase is all curve cells; ShapeRails draws it as one smooth rail at the bed's own
        // heights, so its turns climb with the grade like its straights)
        func isCurve(_ i: Int) -> Bool {
            guard !diagonal, i > 0 && i + 1 < n else { return false }
            let a = cells[i], p = cells[i - 1], q = cells[i + 1]
            return (a.x - p.x) != (q.x - a.x) || (a.z - p.z) != (q.z - a.z)
        }
        if floatCurves, let (e0, e1) = ends { for j in 0..<min(3, n) { fixed[j] = e0; fixed[n - 1 - j] = e1 } }
        // (the band a cell can take from the cells fixed so far, at the grade)
        func band(_ i: Int) -> (Float, Float) {
            var lo: Float = -1e9, hi: Float = 1e9
            for j in 0..<n { if let f = fixed[j] { let r = Float(abs(i - j)) * grade; lo = max(lo, f - r); hi = min(hi, f + r) } }
            return (lo, hi)
        }
        for i in 0..<n where isCurve(i) {
            let window = target[max(0, i - 2)...min(n - 1, i + 2)].sorted()
            var lv = fixed[i] ?? window[window.count / 2]
            if floatCurves && fixed[i] == nil {
                var lo: Float = -1e9, hi: Float = 1e9
                for j in thru(max(0, i - 1), min(n - 1, i + 1)) { let b = band(j); lo = max(lo, b.0); hi = min(hi, b.1) }
                if lo <= hi { lv = max(lo, min(hi, lv)) }
            }
            for j in thru(max(0, i - 1), min(n - 1, i + 1)) { fixed[j] = fixed[j] ?? lv }
        }
        for st in stations {
            let a = max(0, st.index - 8), b = min(n - 1, st.index + 8)
            let lv = target[a...b].sorted()[(b - a) / 2]
            for j in a...b where fixed[j] == nil { fixed[j] = lv }
        }
        if let (e0, e1) = ends { for j in 0..<min(3, n) { fixed[j] = e0; fixed[n - 1 - j] = e1 } }      // (P510: a link meets its lines level)
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
        // (N12: with its turns free to climb, a diagonal line's valley floor or crest can round one cell a block off both
        // its neighbours, a rail a step down and up again (the rail check's dip/hump, 3 of 151 lines): that cell's height
        // is moved to the edge of its neighbours' block, an eighth of a block at most)
        if diagonal {
            for i in 1..<(n - 1) {
                let a = h[i - 1].rounded(), b = h[i].rounded(), c = h[i + 1].rounded()
                if a == c && b != a { h[i] = b < a ? a - 0.499 : a + 0.499 }
            }
        }
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
        // N12: across a 45-degree staircase the 3 x 3 is 2.1 blocks wide, under a train 2.9 wide: a diagonal line's turn
        // cells reach two out along both axes (3.5 across the diagonal).
        if curve && l.diagonal { bed += [(c.x - 2, c.z), (c.x + 2, c.z), (c.x, c.z - 2), (c.x, c.z + 2)] }
        return (alongX, bed)
    }

    // P379 step 3: a field world's ballast drawn at the track's own height. Each bed cell's ground (the cell under the
    // rail) and the rail's cell get densities whose zero crossing lies at the planned height, so the bed rises and falls
    // with the track on a slope instead of in block steps. Only ground the field holds (a trestle's deck is a block).
    static func shapeBed(_ gen: WorldGen, _ fd: inout [Int8], cx: Int, cz: Int) {
        let bx = cx * CS, bz = cz * CS
        // (BS_RAILTRACE=X,Z: for X,Z's chunk, each line found and how many of its bed cells were shaped)
        let tr = ShapeRails.trace.map { floorDiv($0.0, CS) == cx && floorDiv($0.1, CS) == cz } ?? false
        for l in near(gen, x0: bx, z0: bz, x1: bx + CS - 1, z1: bz + CS - 1, pad: 2) + linksNear(gen, x0: bx, z0: bz, x1: bx + CS - 1, z1: bz + CS - 1, pad: 2)
            + loopsNear(gen, x0: bx, z0: bz, x1: bx + CS - 1, z1: bz + CS - 1, pad: 2) {
            if tr {
                var inside = 0, shaped = 0, notes: [String] = []
                if let hs = l.heights { for i in l.cells.indices {
                    let c = l.cells[i]
                    guard c.x >= bx && c.x < bx + CS && c.z >= bz && c.z < bz + CS, c.y >= 1 && c.y < CH else { continue }
                    inside += 1
                    let j = (c.x - bx) + (c.z - bz) * CS + c.y * CSQ
                    if fd[j - CSQ] > 0 && fd[j] <= 0 { shaped += 1 } else if notes.count < 6 { notes.append("\(c.x) \(c.y) \(c.z) h \(hs[i]) under \(fd[j - CSQ]) at \(fd[j]) over \(c.y + 1 < CH ? fd[j + CSQ] : 0)") }
                } }
                print("railtrace: shapeBed chunk \(cx) \(cz) line \(l.id) heights \(l.heights != nil) cells \(l.cells.count), in chunk \(inside), shaped \(shaped); not: \(notes)")
            }
            guard let hs = l.heights else { continue }
            // (N12: a diagonal line's beds overlap their neighbours' at other heights: each column is shaped by its
            // nearest rail cell only, so the bed follows the grade across its whole width)
            let owner = l.diagonal ? nearestCells(l, x0: bx, z0: bz, x1: bx + CS - 1, z1: bz + CS - 1) : [:]
            for i in l.cells.indices {
                let c = l.cells[i]
                guard c.x >= bx - 2 && c.x < bx + CS + 2 && c.z >= bz - 2 && c.z < bz + CS + 2, c.y >= 1 && c.y < CH else { continue }
                let f = max(-0.45, min(0.45, hs[i] - Float(c.y)))
                for (x, z) in bed(l, i).cells where x >= bx && x < bx + CS && z >= bz && z < bz + CS && (!l.diagonal || owner[colKey(x, z)] == i) {
                    let j = (x - bx) + (z - bz) * CS + c.y * CSQ
                    guard fd[j - CSQ] > 0, fd[j] <= 0 else { continue }
                    fd[j - CSQ] = FieldTerrain.q(0.5 + f)
                    fd[j] = FieldTerrain.q(-(0.5 - f))
                }
            }
        }
    }

    // N12: the rail cell of l nearest each bed column in the box (the first such cell on a tie), by column key.
    static func colKey(_ x: Int, _ z: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: z))) }
    static func nearestCells(_ l: Line, x0: Int, z0: Int, x1: Int, z1: Int) -> [Int64: Int] {
        var best: [Int64: (Int, Int)] = [:]
        guard l.maxX + 2 >= x0 && l.minX - 2 <= x1 && l.maxZ + 2 >= z0 && l.minZ - 2 <= z1 else { return [:] }
        for i in l.cells.indices {
            let c = l.cells[i]
            guard c.x >= x0 - 2 && c.x <= x1 + 2 && c.z >= z0 - 2 && c.z <= z1 + 2 else { continue }
            for (x, z) in bed(l, i).cells where x >= x0 && x <= x1 && z >= z0 && z <= z1 {
                let d = (x - c.x) * (x - c.x) + (z - c.z) * (z - c.z), k = colKey(x, z)
                if let b = best[k], b.0 <= d { continue }
                best[k] = (d, i)
            }
        }
        return best.mapValues { $0.1 }
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
        let links = linksNear(gen, x0: bx, z0: bz, x1: bx + CS - 1, z1: bz + CS - 1, pad: 8)
        let loops = loopsNear(gen, x0: bx, z0: bz, x1: bx + CS - 1, z1: bz + CS - 1, pad: 8)
        guard !lines.isEmpty || !links.isEmpty || !loops.isEmpty, Blocks.has("rail") else { return }
        // (links and loops first: a line's own rails, stations and buffers go over their beds where they meet)
        for l in links + loops { draw(l, &w, open: (true, true)) }
        for l in lines {
            let o = openEnds(gen, l), lp = Railways.loops(gen, l)            // (P511: an end that turns in a loop has no buffers)
            draw(l, &w, open: (o.west || lp.west != nil, o.east || lp.east != nil))
        }
    }

    static func draw(_ l: Line, _ w: inout StructWriter, open: (west: Bool, east: Bool) = (false, false)) {
        func g(_ n: String, _ f: BlockID) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let rail = g("rail", AIR), ballast = g("gravel", STONE), deck = g("spruce_planks", PLANKS), leg = g("spruce_log", LOG)
        let fill = g("dirt", STONE)
        let stop = g("stone_bricks", STONE), plat = g("stone_bricks", STONE)
        let platEdge = g("smooth_stone", plat), lamp = g("lantern", AIR), post = g("spruce_fence", leg)
        let wall = g("spruce_planks", PLANKS), roof = g("dark_oak_planks", PLANKS), glass = g("glass_pane", AIR)
        let water = Blocks.has("water") ? Blocks.id("water") : AIR
        let bx = w.bx, bz = w.bz
        func inChunk(_ x: Int, _ z: Int, pad: Int) -> Bool { x >= bx - pad && x < bx + CS + pad && z >= bz - pad && z < bz + CS + pad }
        let n = l.cells.count
        // (N12: on a diagonal line each bed column is laid by its nearest rail cell: a neighbour a block up or down
        // would put its ballast or its cutting through this cell's)
        let owner = l.diagonal ? nearestCells(l, x0: bx, z0: bz, x1: bx + CS - 1, z1: bz + CS - 1) : [:]
        for i in 0..<n {
            let c = l.cells[i], y = c.y
            guard inChunk(c.x, c.z, pad: 2) else { continue }
            // Across the track: along x the bed spans z-1...z+1; along z it spans x-1...x+1 (both at a curve).
            let (alongX, bed) = Railways.bed(l, i)
            for (x, z) in bed where w.inside(x, y, z) && (!l.diagonal || owner[colKey(x, z)] == i) {
                // Cutting / tunnel: six clear blocks over the track (P470: a real-size train is four and a half
                // tall); trees overhead go (no floating trunks).
                for yy in y...(y + 5) { w.set(x, yy, z, AIR) }
                var yy = y + 6
                while yy < CH - 1 && Int(w.get(x, yy, z)) < clearable.count && clearable[Int(w.get(x, yy, z))] { w.set(x, yy, z, AIR); yy += 1 }
                let ground = w.get(x, y - 1, z)
                // P510 (Nov 1 20:39-20:40, by his line: "Wood is a block", "We need to make these rails so they sit
                // smoothly on top of the terrain... If you add blocks, it makes it choppy", "The rails end and don't
                // match the top"): in a field world a dip of up to eight blocks under the track is banked up with earth
                // under the ballast, which the field draws as ground shaped to the line's grade, not a plank trestle of
                // cubes with the rails a block step off the bed beside it. Deeper dips and water still get a trestle.
                // (Eight deep, not four: the field's smooth surface lies up to a few blocks over the block column the
                // writer sees, so a dip it drew two deep under a deck was six here; and banked earth reads as the
                // land's own shoulder where a timber deck read as cubes.)
                var bank = -1
                if l.heights != nil && !(Blocks.opaque[Int(ground)] && Blocks.collide[Int(ground)]) {
                    // (a puddle a block deep in the dip is banked over too: the deck over 1-deep water at 186 149 5155
                    // was the last plank pier in the rail check's ride; deeper water keeps its trestle)
                    var wet = 0
                    for d in 2...9 {
                        let b = w.get(x, y - d, z)
                        if Blocks.fluidKind[Int(b)] != 0 { wet += 1; if wet > 1 { break }; continue }
                        if StructWriter.holdsColumn(b) { bank = d; break }
                    }
                }
                // R22: gravel only on firm ground; over a cave or a ravine's lip the bed is stone (gravel fell out at the
                // first block update and left the rail over the hole).
                if Blocks.opaque[Int(ground)] && Blocks.collide[Int(ground)] { w.set(x, y - 1, z, w.firmUnder(x, y - 1, z) ? ballast : plat) }
                else if bank > 0 {
                    for d in 2..<bank { w.set(x, y - d, z, fill) }
                    w.set(x, y - 1, z, ballast)
                    banked += 1
                } else {
                    if l.heights != nil, Railways.deckNotes.count < 64 {
                        // (checks: what the writer saw under a field line's deck)
                        let col = (1...9).map { Blocks.key(w.get(x, y - $0, z)) }.joined(separator: ",")
                        Railways.noteLock.lock(); Railways.deckNotes["\(x) \(y) \(z)"] = col; Railways.noteLock.unlock()
                    }
                    w.set(x, y - 1, z, deck)                                       // trestle deck
                    let edge = l.diagonal ? abs(x - c.x) + abs(z - c.z) >= 2 : (alongX && z != c.z) || (!alongX && x != c.x)
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
        for (i, j) in [(0, 1), (n - 1, n - 2)] where n > 1 && !(i == 0 ? open.west : open.east) {
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
