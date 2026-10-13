import Foundation

// Town sizes (backlog C13), `questcheck --sizes-only`:
//   histogram  the towns of 7x7 village regions round the origin of 50 seeds: hamlets most, then villages, towns,
//              large towns and cities, each size about 3 to 4 times rarer than the one below
//   growth     bigger places have more lots, more shops and more deputies; a hamlet has no office or bank
//   mines      only towns and up work a mine
//   railways   a line gives villages and up a station, hamlets only a halt (eight seeds)
enum TownSizesTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let on0 = TownSizes.on
        TownSizes.on = true
        defer { TownSizes.on = on0 }
        var count = [Int](repeating: 0, count: 5), lots = [Int](repeating: 0, count: 5), shops = [Int](repeating: 0, count: 5)
        var deputies = [Int](repeating: 0, count: 5), offices = [Int](repeating: 0, count: 5), mines = [Int](repeating: 0, count: 5)
        var unsized = 0
        let t0 = CFAbsoluteTimeGetCurrent()
        var gens: [WorldGen] = []
        for k in 0..<50 {
            let gen = WorldGen(seed: UInt64(5000 + k * 104_729))
            if k < 8 { gens.append(gen) }
            guard let sc = gen.structures, let vt = sc.types.first(where: { $0.name == "village" }) else { continue }
            for rz in -3...3 { for rx in -3...3 {
                guard let s = sc.start(vt, regionX: rx, regionZ: rz) else { continue }
                guard let z = TownSizes.of(s)?.rawValue else { unsized += 1; continue }
                count[z] += 1; lots[z] += s.info["lots"] ?? 0; shops[z] += s.info["shops"] ?? 0
                deputies[z] += s.info["deputies"] ?? 0; offices[z] += s.info["office"] ?? 0
                if s.plan is Mine { mines[z] += 1 }
            } }
        }
        print(String(format: "sizes: 50 seeds in %.1f s", CFAbsoluteTimeGetCurrent() - t0))
        func mean(_ a: [Int], _ i: Int) -> Float { count[i] > 0 ? Float(a[i]) / Float(count[i]) : 0 }
        let r1 = Float(count[0]) / Float(max(1, count[1])), r2 = Float(count[1]) / Float(max(1, count[2]))
        let hist = (0..<5).map { "\(TownSizes.names[$0]) \(count[$0])" }.joined(separator: ", ")
        check(count[0] > count[1] && count[1] > count[2] && count[2] > count[3] && count[3] >= count[4] && count[3] + count[4] >= 1
              && r1 >= 2 && r1 <= 6 && r2 >= 2 && r2 <= 6 && unsized == 0,
              String(format: "C13 histogram over 50 seeds: %@ (hamlet:village %.1f, village:town %.1f); unsized %d", hist, r1, r2, unsized))
        let present = (0..<5).filter { count[$0] > 0 }
        let lotMeans = present.map { mean(lots, $0) }, shopMeans = present.map { mean(shops, $0) }, depMeans = present.map { mean(deputies, $0) }
        let rising = zip(lotMeans, lotMeans.dropFirst()).allSatisfy { $0 < $1 + 0.5 } && lotMeans.first! < lotMeans.last!
        let moreShops = zip(shopMeans, shopMeans.dropFirst()).allSatisfy { $0 <= $1 + 0.01 }
        let moreLaw = zip(depMeans, depMeans.dropFirst()).allSatisfy { $0 < $1 }
        check(rising && moreShops && moreLaw && offices[0] == 0 && (1..<5).allSatisfy { offices[$0] * 10 >= count[$0] * 9 },
              "C13 growth: lots \(lotMeans.map { String(format: "%.1f", $0) }), shops \(shopMeans.map { String(format: "%.1f", $0) }), deputies \(depMeans.map { Int($0) }); offices \(offices)")
        check(mines[0] == 0 && mines[1] == 0 && (count[2] + count[3] + count[4] == 0 || mines[2] + mines[3] + mines[4] >= 1),
              "C13 mines: by size \(mines) (towns and up only)")

        // Railways: no station at a hamlet.
        var stations = 0, halts = 0, wrong = 0
        for gen in gens {
            guard let sc = gen.structures, let vt = sc.types.first(where: { $0.name == "village" }) else { continue }
            let found = Railways.near(gen, x0: -4000, z0: -4000, x1: 4000, z1: 4000, pad: 0)
            for l in found { for st in l.stations {
                stations += 1
                if st.halt { halts += 1 }
                let rx = floorDiv(floorDiv(st.x, CS), vt.spacing), rz = floorDiv(floorDiv(st.z - 40, CS), vt.spacing)
                for dz in -1...1 { for dx in -1...1 {
                    if let s = sc.start(vt, regionX: rx + dx, regionZ: rz + dz),
                       Townsfolk.townName(s.anchor.x, s.anchor.z, seed: gen.seed) == st.name, (TownSizes.of(s) == .hamlet) != st.halt { wrong += 1 }
                } }
            } }
        }
        check(stations > 0 && wrong == 0, "C13 railways: \(stations) stops over 8 seeds, \(halts) of them hamlet halts; \(wrong) of the wrong kind")
    }
}
