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
        for b in bad.prefix(12) { print("sparse rails: " + b) }
        print(String(format: "sparse rails: %.1f s", CFAbsoluteTimeGetCurrent() - t0))
        let wind0 = spread[0] / max(1, wilds[0]), wind1 = spread[1] / max(1, wilds[1])
        let ok = oddTrack == 0 && evenBare == 0 && linked * 100 >= links * 95 && steps == 0 && jumps == 0 && crossings == 0
            && cells[1] * 100 <= cells[0] * 70 && wind1 >= 60 && wind1 > 2 * wind0 && stations[1] > 0
        check(ok, "ledger 230: in a new world every second row carries track, it winds over the land and a lone town has its station (3 worlds, 25 stretches each: track in \(tracked[1]) stretches, \(tracked[0]) before; \(cells[1]) cells of track and links, \(cells[0]) before; open-country track strays \(wind1) blocks north to south on average, \(wind0) before; \(stations[1]) town stations on those rows, \(oneStop) lines of one station, \(stations[0]) stations on all rows before; \(oddTrack) odd rows with track, \(evenBare) even stretches bare, \(linked) of \(links) joins laid, \(steps) broken steps, \(jumps) grade jumps, \(crossings) cells on another track)")
    }
}
