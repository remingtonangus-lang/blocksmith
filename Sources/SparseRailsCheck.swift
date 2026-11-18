import Foundation

// Ledger 230 (Nov 17 evening: "reduce the amount of railroads there are by about half", "more twisty and turny",
// "they gotta go to villages more"): in a new world only every second row of village regions carries track, its
// open-country stretches and links wind over the land, and one town is enough for a station. The same ground both
// ways (Railways.sparseOn; each on its own generator, plans are kept by generator).
extension RailwayTests {
    static func sparseCountry(_ check: (Bool, String) -> Void) {
        guard Railways.wildOn, !Railways.oldRailRows else { print("sparse rails: off"); return }
        let t0 = CFAbsoluteTimeGetCurrent()
        let on0 = Railways.sparseOn
        defer { Railways.sparseOn = on0 }
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
        passingTrain(check)
        for b in bad.prefix(12) { print("sparse rails: " + b) }
        print(String(format: "sparse rails: %.1f s", CFAbsoluteTimeGetCurrent() - t0))
        let wind0 = spread[0] / max(1, wilds[0]), wind1 = spread[1] / max(1, wilds[1])
        let ok = oddTrack == 0 && evenBare == 0 && linked * 100 >= links * 95 && steps == 0 && jumps == 0 && crossings == 0
            && cells[1] * 100 <= cells[0] * 70 && wind1 >= 60 && wind1 > 2 * wind0 && stations[1] > 0
        check(ok, "ledger 230: in a new world every second row carries track, it winds over the land and a lone town has its station (3 worlds, 25 stretches each: track in \(tracked[1]) stretches, \(tracked[0]) before; \(cells[1]) cells of track and links, \(cells[0]) before; open-country track strays \(wind1) blocks north to south on average, \(wind0) before; \(stations[1]) town stations on those rows, \(oneStop) lines of one station, \(stations[0]) stations on all rows before; \(oddTrack) odd rows with track, \(evenBare) even stretches bare, \(linked) of \(links) joins laid, \(steps) broken steps, \(jumps) grade jumps, \(crossings) cells on another track)")
    }

    // Ledger 238: a line of one station runs its train over a long window (the open country before it, the links and
    // the next stretch), not out and back along its own hundred-odd cells.
    static func passingTrain(_ check: (Bool, String) -> Void) {
        var one: (WorldGen, Railways.Line)?
        search: for k in 0..<3 {
            let gen = WorldGen(seed: UInt64(1000 + k * 7919))
            gen.fieldWorld = true
            for row in [-2, 0, 2] { for st in -2...2 {
                if let l = Railways.line(gen, row: row, stretch: st), !l.wild, l.stations.count == 1 { one = (gen, l); break search }
            } }
        }
        guard let (gen, l) = one else { check(false, "ledger 238: no line of one station in 45 stretches of 3 worlds"); return }
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
        let ownAt = t.parts[0].cells.count + t.parts[1].cells.count + st.index
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
        let ok = t.parts.count == 5 && atStation && t.cells.count > 8 * l.cells.count && stood >= Trains.dwell && leap < 4 && lo < 8 && hi > n - 8
            && turns(t, over: 600) <= 2
        check(ok, String(format: "ledger 238: a line of one station runs its train through, not along its platform and back (%@: its own track %d cells, a train on it would turn %d times in ten minutes; its window %d cells over %d parts, turns %d times, stands %.0f s at its %d stations (%@ among them) a round of %.0f min, never moves more than %.1f cells in a tenth of a second, runs cells %.0f to %.0f)",
                         l.name, l.cells.count, turns(stub, over: 600), t.cells.count, t.parts.count, turns(t, over: 600), stood, t.stops.count, st.name, t.period / 60, leap, lo, hi))
    }
}
