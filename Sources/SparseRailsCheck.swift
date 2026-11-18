import Foundation

// Ledger 230 (Nov 17 evening: "reduce the amount of railroads there are by about half", "more twisty and turny",
// "they gotta go to villages more"): in a new world only every second row of village regions carries track, its
// open-country stretches and links wind over the land, and one town is enough for a station. The same ground both
// ways (Railways.sparseOn; each on its own generator, plans are kept by generator).
extension RailwayTests {
    static func sparseCountry(_ check: (Bool, String) -> Void) {
        guard Railways.wildOn, !Railways.oldRailRows else { print("sparse rails: off"); return }
        let t0 = CFAbsoluteTimeGetCurrent()
        let on0 = Railways.sparseOn, sea0 = Railways.oldSeaBridge
        defer { Railways.sparseOn = on0; Railways.oldSeaBridge = sea0 }
        // (ledger 230 is counted on the rows as it left them, every even stretch with track; ledger 360 below)
        Railways.oldSeaBridge = true
        let rows = -2...2, sts = -2...2
        var cells = [0, 0], stations = [0, 0], tracked = [0, 0], spread = [0, 0], wilds = [0, 0], oneStop = 0
        var oddTrack = 0, evenBare = 0, links = 0, linked = 0, steps = 0, jumps = 0, crossings = 0
        var bad: [String] = []
        for k in 0..<3 {
            let seed = UInt64(1000 + k * 7919)
            for (wi, sparse) in [false, true].enumerated() {
                Railways.sparseOn = sparse
                let gen = WorldGen(seed: seed)
                gen.fieldWorld = true
                var owner: [Int64: Int64] = [:]
                for row in rows { for st in sts {
                    guard let l = Railways.line(gen, row: row, stretch: st) else {
                        if sparse && row & 1 == 0 { evenBare += 1; bad.append("seed \(seed) row \(row) stretch \(st): no track") }
                        continue
                    }
                    if sparse && row & 1 != 0 { oddTrack += 1 }
                    tracked[wi] += 1; cells[wi] += l.cells.count; stations[wi] += l.stations.filter { !$0.site }.count
                    if l.wild { wilds[wi] += 1; spread[wi] += l.maxZ - l.minZ }
                    guard sparse else { continue }
                    if l.stations.count == 1 { oneStop += 1 }
                    for i in 1..<l.cells.count where abs(l.cells[i].x - l.cells[i - 1].x) + abs(l.cells[i].z - l.cells[i - 1].z) != 1 { steps += 1; break }
                    if let h = l.heights { for i in 1..<h.count where abs(h[i] - h[i - 1]) > Railways.grade + 0.02 { jumps += 1; break } }
                    for c in l.cells {
                        let ck = Railways.colKey(c.x, c.z)
                        if let o = owner[ck], o != l.id { crossings += 1 }
                        owner[ck] = l.id
                    }
                } }
                for row in rows { for st in sts where st < sts.upperBound {
                    guard let a = Railways.line(gen, row: row, stretch: st), let b = Railways.line(gen, row: row, stretch: st + 1) else { continue }
                    guard let lk = Railways.link(gen, row: row, stretch: st), lk.target == Railways.key(row, st + 1) else {
                        if sparse { links += 1; if bad.count < 12 { bad.append("seed \(seed) row \(row) stretch \(st): no link on") } }
                        continue
                    }
                    cells[wi] += lk.cells.count
                    guard sparse else { continue }
                    links += 1; linked += 1
                    let chain = [a.cells.last!] + lk.cells + [b.cells.first!]
                    for i in 1..<chain.count where abs(chain[i].x - chain[i - 1].x) + abs(chain[i].z - chain[i - 1].z) != 1 { steps += 1; bad.append("seed \(seed) row \(row) stretch \(st): link step \(i) not adjacent"); break }
                    if let ha = a.heights, let hl = lk.heights, let hb = b.heights {
                        let hs = [ha.last!] + hl + [hb.first!]
                        for i in 1..<hs.count where abs(hs[i] - hs[i - 1]) > Railways.grade + 0.02 { jumps += 1; bad.append("seed \(seed) row \(row) stretch \(st): link height jumps"); break }
                    }
                    for c in lk.cells {
                        let ck = Railways.colKey(c.x, c.z)
                        if let o = owner[ck], o != lk.id { crossings += 1 }
                        owner[ck] = lk.id
                    }
                } }
            }
        }
        Railways.sparseOn = true
        bothRows(check)
        Railways.oldSeaBridge = sea0
        passingTrain(check)
        townToTown(check)
        for b in bad.prefix(12) { print("sparse rails: " + b) }
        print(String(format: "sparse rails: %.1f s", CFAbsoluteTimeGetCurrent() - t0))
        let wind0 = spread[0] / max(1, wilds[0]), wind1 = spread[1] / max(1, wilds[1])
        let ok = oddTrack == 0 && evenBare == 0 && linked * 100 >= links * 95 && steps == 0 && jumps == 0 && crossings == 0
            && cells[1] * 100 <= cells[0] * 70 && wind1 >= 60 && wind1 > 2 * wind0 && stations[1] > 0
        check(ok, "ledger 230: in a new world every second row carries track, it winds over the land and a lone town has its station (3 worlds, 25 stretches each: track in \(tracked[1]) stretches, \(tracked[0]) before; \(cells[1]) cells of track and links, \(cells[0]) before; open-country track strays \(wind1) blocks north to south on average, \(wind0) before; \(stations[1]) town stations on those rows, \(oneStop) lines of one station, \(stations[0]) stations on all rows before; \(oddTrack) odd rows with track, \(evenBare) even stretches bare, \(linked) of \(links) joins laid, \(steps) broken steps, \(jumps) grade jumps, \(crossings) cells on another track)")
    }

    // Ledger 360: in a new world no track crosses more open sea than a strait, and every railway runs from town to
    // town: each end of every line is joined by a link or stands at a station, none in a field or on a beach.
    static func townToTown(_ check: (Bool, String) -> Void) {
        guard !Railways.oldSeaBridge else { print("ledger 360: off"); return }
        var cells = [0, 0], wet = [0, 0], longest = [0, 0], loose = 0, ends = 0, lone = 0, lines = 0, shared = 0
        var bad: [String] = []
        for k in 0..<4 {
            let seed = k == 3 ? UInt64(4259144782798118884) : UInt64(1000 + k * 7919)
            for (wi, old) in [true, false].enumerated() {
                Railways.oldSeaBridge = old
                defer { Railways.oldSeaBridge = false }
                let gen = WorldGen(seed: seed)
                gen.fieldWorld = true
                let all = Railways.near(gen, x0: -4400, z0: -4400, x1: 4400, z1: 4400, pad: 0, wild: true)
                    + Railways.linksNear(gen, x0: -4400, z0: -4400, x1: 4400, z1: 4400, pad: 0)
                var owner: [Int64: Int64] = [:]
                for l in all {
                    cells[wi] += l.cells.count
                    var run = 0
                    for i in stride(from: 0, to: l.cells.count, by: 4) {
                        if gen.column(l.cells[i].x, l.cells[i].z).biome.isOcean { run += 4; wet[wi] += 4; longest[wi] = max(longest[wi], run) } else { run = 0 }
                    }
                    guard !old else { continue }
                    for c in l.cells.dropFirst(2).dropLast(2) {
                        let ck = Railways.colKey(c.x, c.z)
                        if let o = owner[ck], o != l.id { shared += 1 } else { owner[ck] = l.id }
                    }
                    guard !Railways.isLink(l.id) else { continue }
                    lines += 1
                    let (row, st) = Railways.rowStretch(l.id)
                    let o = Railways.openEnds(gen, l)
                    if l.stations.count == 1 && !o.west && !o.east { lone += 1; bad.append("seed \(seed): \(l.name) is one station nothing joins") }
                    for (joined, name) in [(o.west, "west"), (o.east, "east")] {
                        ends += 1
                        if !joined && l.wild { loose += 1; bad.append("seed \(seed) row \(row) stretch \(st): open-country track's \(name) end joins nothing") }
                    }
                }
            }
        }
        for b in bad.prefix(8) { print("ledger 360: " + b) }
        let ok = longest[1] <= Railways.strait + 8 && loose == 0 && lone == 0 && shared == 0 && cells[1] > 0 && cells[1] < cells[0] && lines > 0
        check(ok, "ledger 360: no railway over the sea beyond a strait, and every one runs from town to town (4 new worlds, 8,800 blocks square: the longest run of track over the sea \(longest[1]) blocks, \(longest[0]) before; \(wet[1]) blocks of track over the sea in all, \(wet[0]) before; \(cells[1]) blocks of track, \(cells[0]) before; \(lines) lines, \(loose) open-country ends that join nothing, \(lone) lone stations, \(shared) columns shared by two tracks)")
    }

    // Ledger 239: a stretch's line serves the towns of its own row and of the empty row south of it (the chain with
    // the most town in it), so more of a new world's towns have a station, and no two tracks share a column.
    static func bothRows(_ check: (Bool, String) -> Void) {
        let old0 = Railways.oldTownRow
        defer { Railways.oldTownRow = old0 }
        guard !old0 else { print("ledger 239: off"); return }
        var got = [0, 0], all = [0, 0], shared = [0, 0], cells = [0, 0]
        for k in 0..<3 {
            for (wi, old) in [true, false].enumerated() {
                Railways.oldTownRow = old
                let gen = WorldGen(seed: UInt64(1000 + k * 7919))
                gen.fieldWorld = true
                let c = PlanMap.count(gen, 0, 0, 3000)
                got[wi] += c.served.reduce(0, +); all[wi] += c.total.reduce(0, +); shared[wi] += c.shared; cells[wi] += c.cells
            }
        }
        check(all[1] == all[0] && all[1] > 0 && got[1] * 10 >= got[0] * 13 && shared[1] == 0 && cells[1] * 10 <= cells[0] * 13,
              "ledger 239: a line serves the towns of both its rows (3 new worlds, 6,000 blocks square each: \(got[1]) of \(all[1]) towns have a station, \(got[0]) before; \(shared[1]) columns shared by two tracks; \(cells[1]) cells of track, \(cells[0]) before)")
    }

    // Ledger 238: a line of one station runs its train over a long window (the open country before it, the links and
    // the next stretch), not out and back along its own hundred-odd cells.
    static func passingTrain(_ check: (Bool, String) -> Void) {
        var one: (WorldGen, Railways.Line)?
        // (ledger 360 lays a line of one station only where a railway runs on from it, so they are fewer: look further)
        search: for k in 0..<5 {
            let gen = WorldGen(seed: UInt64(1000 + k * 7919))
            gen.fieldWorld = true
            for row in stride(from: -6, through: 6, by: 2) { for st in -3...3 {
                if let l = Railways.line(gen, row: row, stretch: st), !l.wild, l.stations.count == 1 { one = (gen, l); break search }
            } }
        }
        guard let (gen, l) = one else { check(false, "ledger 238: no line of one station in 245 stretches of 5 worlds"); return }
        let stub = Trains.track(l)
        // (the stub's train: how often it turns)
        func turns(_ t: Trains.Track, over secs: Double) -> Int {
            var n = 0, last: Float = 0, u = 0.0
            while u < secs { let d = t.at(u).dir; if last != 0 && d != last { n += 1 }; last = d; u += 0.5 }
            return n
        }
        guard let t = Trains.passingTrack(l, gen: gen, wait: true) else {
            check(false, "ledger 238: \(l.name) (one station, \(l.cells.count) cells) has no window to run"); return
        }
        let st = l.stations[0]
        // (the window's stops are every station on its parts: the line's own among them, and a neighbour stretch's if
        // that is a town line too)
        let before = t.parts.firstIndex(where: { $0 === l }) ?? 0
        let ownAt = t.parts[..<before].reduce(0) { $0 + $1.cells.count } + st.index
        let atStation = t.stops.contains(ownAt) && t.cells[ownAt].x == l.cells[st.index].x && t.cells[ownAt].z == l.cells[st.index].z
        // One whole timetable, a tenth of a second a step: it stands at the station, never leaps, reaches both ends.
        var stood = 0.0, leap: Float = 0, lo = Float.infinity, hi: Float = 0, u = 0.0
        var prev = t.at(0).s
        while u < t.period {
            let a = t.at(u)
            if a.stop != nil { stood += 0.1 }
            leap = max(leap, abs(a.s - prev)); prev = a.s
            lo = min(lo, a.s); hi = max(hi, a.s)
            u += 0.1
        }
        let n = Float(t.cells.count - 1)
        let ok = t.parts.count >= 3 && atStation && t.cells.count > 8 * l.cells.count && stood >= Trains.dwell && leap < 4 && lo < 8 && hi > n - 8
            && turns(t, over: 600) <= 2
        check(ok, String(format: "ledger 238: a line of one station runs its train through, not along its platform and back (%@: its own track %d cells, a train on it would turn %d times in ten minutes; its window %d cells over %d parts, turns %d times, stands %.0f s at its %d stations (%@ among them) a round of %.0f min, never moves more than %.1f cells in a tenth of a second, runs cells %.0f to %.0f)",
                         l.name, l.cells.count, turns(stub, over: 600), t.cells.count, t.parts.count, turns(t, over: 600), stood, t.stops.count, st.name, t.period / 60, leap, lo, hi))
    }
}
