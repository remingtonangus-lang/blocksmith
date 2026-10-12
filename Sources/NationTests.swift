import Foundation
import simd

// Your own nation (backlog C3), `questcheck --nation-only`:
//   provinces  a taken town and a taken Greywall base are the nation's two provinces
//   days       20 days at fair taxes draw settlers and keep loyalty near 55; high taxes with every law lose loyalty
//              and settlers; low taxes and the open market gain loyalty; a raid while away is fought by the garrison
//   tribute    low < fair < high, the open market adds 15%, settlers add to it
//   revolt     a town held at high taxes under curfew and conscription from low loyalty rises up and is lost
//   building   at a province by the player the settlers build a farm (wheat on farmland, water), a cabin (walls,
//              a window) and, at the capital, the hall in its style with the nation's flag
//   map        the world map draws each province in the flag colour, the capital larger
//   council    ringing a bell in your town opens the council; its rows cycle the taxes, laws and capital
//   save       the nation survives a save (TownLaw.Saved round trip)
enum NationTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let saved = TownLaw.state, taken = g.greywallAlarm.taken, time = g.time
        defer { TownLaw.state = saved; g.greywallAlarm.taken = taken; g.time = time }
        let p = g.player.pos
        let tx = Int(floor(p.x)), tz = Int(floor(p.z))
        func fresh(_ st: Nation.Saved = Nation.Saved()) {
            TownLaw.state.owned = ["Testford": [tx, tz, 0, 0]]
            g.greywallAlarm.taken = ["greywall:\(tx + 5000),\(tz)"]
            TownLaw.state.nation = st
            g.time = 0
        }
        func days(_ n: Int) { Nation.advance(g, to: Int(g.time / DAY_LENGTH) + n); g.time += Double(n) * DAY_LENGTH }

        // Provinces.
        fresh()
        Nation.tick(g)
        let ps = Nation.provinces(g)
        check(ps.count == 2 && Nation.s.provinces.count == 2 && ps.contains { $0.key == "Testford" } && ps.contains { Nation.isBase($0.key) },
              "C3 provinces: \(ps.map { Nation.displayName($0.key) }) (a taken town and a taken base)")

        // Days at each policy.
        func run(tax: Int, laws: [String], loyalty: Float = 50, n: Int = 20) -> Nation.Province {
            var st = Nation.Saved(); st.tax = tax; st.laws = laws; st.day = 0
            st.provinces["Testford"] = Nation.Province(loyalty: loyalty)
            st.provinces["greywall:\(tx + 5000),\(tz)"] = Nation.Province()
            fresh(st)
            days(n)
            return Nation.s.provinces["Testford"] ?? Nation.Province(settlers: -1, loyalty: -1)
        }
        Nation.raids = false
        let fair = run(tax: 1, laws: [])
        let harsh = run(tax: 2, laws: ["curfew", "conscription"])
        let kind = run(tax: 0, laws: ["market"])
        let drafted = run(tax: 1, laws: ["conscription"])
        check(fair.settlers >= 10 && abs(fair.loyalty - 55) < 15 && harsh.loyalty < fair.loyalty - 15 && kind.loyalty > fair.loyalty + 15
              && drafted.garrison > fair.garrison,
              String(format: "C3 days: 20 days fair: %d settlers, loyalty %.0f, garrison %d; high taxes + curfew + conscription: loyalty %.0f, %d settlers; low taxes + market: loyalty %.0f; conscription: garrison %d",
                     fair.settlers, fair.loyalty, fair.garrison, harsh.loyalty, harsh.settlers, kind.loyalty, drafted.garrison))
        Nation.raids = true
        Nation.events = []
        _ = run(tax: 1, laws: [], n: 30)
        let raids = Nation.events.filter { $0.contains("raiders") || $0.contains("Raiders") }
        check(!raids.isEmpty, "C3 raids: \(raids.count) raids on 2 provinces over 30 days away (\(raids.prefix(2).joined(separator: "; ")))")

        // Tribute.
        var st = Nation.Saved(); st.provinces["Testford"] = Nation.Province(settlers: 0)
        var tr: [Int] = []
        for t in 0..<3 { st.tax = t; TownLaw.state.nation = st; tr.append(Nation.tributePerDay("Testford")) }
        st.tax = 1; st.laws = ["market"]; TownLaw.state.nation = st
        let market = Nation.tributePerDay("Testford")
        st.laws = []; st.provinces["Testford"]?.settlers = 10; TownLaw.state.nation = st
        let peopled = Nation.tributePerDay("Testford")
        check(tr[0] < tr[1] && tr[1] < tr[2] && market > tr[1] && peopled > tr[1],
              "C3 tribute a day: low \(Money.format(tr[0])), fair \(Money.format(tr[1])), high \(Money.format(tr[2])), open market \(Money.format(market)), 10 settlers \(Money.format(peopled))")

        // Revolt.
        _ = run(tax: 2, laws: ["curfew", "conscription"], loyalty: 12, n: 12)
        let lost = TownLaw.state.owned?["Testford"] == nil
        check(lost && Nation.s.provinces["Testford"] == nil && Nation.s.provinces.count == 1,
              "C3 revolt: a town held at high taxes under curfew and conscription from loyalty 12 \(lost ? "rose up and is lost" : "is still yours"); the base holds")

        // Building by the player.
        building(g, check, tx, tz)

        // Map.
        var st2 = Nation.Saved(); st2.capital = "Testford"; st2.flag = 1
        fresh(st2)
        Nation.tick(g)
        var out: [HudLine] = []
        Nation.mapDrawn = 0
        Nation.mapProvinces(&out, g, x0: 0, y0: 0, cols: 400, rows: 400, px: 1, wx: Float(tx), wz: Float(tz), bpc: 32, s: 1)
        let blue = out.filter { $0.bg == Nation.flagColors[1].c }
        let capBox = blue.map { $0.box?.x ?? 0 }.max() ?? 0, other = blue.map { $0.box?.x ?? 0 }.min() ?? 0
        check(Nation.mapDrawn == 2 && blue.count == 2 && capBox > other && out.contains { $0.text == "*" },
              "C3 map: \(Nation.mapDrawn) provinces drawn in \(Nation.flagColors[1].name.lowercased()), the capital larger with a star")

        // The council.
        fresh()
        let m = NationMenu(game: g, town: "Testford")
        let r0 = m.rows
        let taxRow = m.items.firstIndex { if case .tax = $0 { return true }; return false } ?? 0
        let lawRow = m.items.firstIndex { if case .law(0) = $0 { return true }; return false } ?? 0
        let capRow = m.items.firstIndex { if case .capital = $0 { return true }; return false } ?? 0
        m.pressed(taxRow); m.pressed(lawRow); m.pressed(capRow)
        let after = Nation.s
        check(r0.count >= 10 && after.tax == 2 && after.laws == ["curfew"] && after.capital == "Testford" && m.rows.contains { $0.name.hasPrefix("Testford") },
              "C3 council: \(r0.count) rows; taxes now \(Nation.taxNames[after.tax].lowercased()), laws \(after.laws), capital \(after.capital ?? "none")")

        // Save.
        var ss = TownLaw.state
        ss.nation?.name = "The Westmark League"; ss.nation?.provinces["Testford"] = Nation.Province(settlers: 7, loyalty: 61, garrison: 3)
        let back = (try? JSONEncoder().encode(ss)).flatMap { try? JSONDecoder().decode(TownLaw.Saved.self, from: $0) }
        let bp = back?.nation?.provinces["Testford"]
        check(back?.nation?.name == "The Westmark League" && bp?.settlers == 7 && bp?.loyalty == 61 && back?.nation?.capital == "Testford",
              "C3 save: the nation's name, capital and provinces survive a save")
    }

    static func building(_ g: Game, _ check: (Bool, String) -> Void, _ tx: Int, _ tz: Int) {
        let w = g.world
        var st = Nation.Saved(); st.capital = "Testford"; st.hallStyle = 1; st.flag = 0; st.day = 0
        st.provinces["Testford"] = Nation.Province(settlers: 9, loyalty: 60)
        TownLaw.state.owned = ["Testford": [tx, tz, 0, 0]]
        g.greywallAlarm.taken = []
        TownLaw.state.nation = st
        g.time = 0
        // Remember what the builds replace.
        var undo: [(IVec3, BlockID)] = []
        let r = 80
        _ = w.loadSync(center: V3(Float(tx), g.player.pos.y, Float(tz)), radius: 6)
        for _ in 0..<120 where (Nation.s.provinces["Testford"]?.sites.count ?? 0) < Nation.earned("Testford") {
            let before = Nation.s.provinces["Testford"]?.sites.count ?? 0
            if before < Nation.earned("Testford") {
                // Snapshot the next candidate area lazily: record the whole ring once.
                if undo.isEmpty {
                    for x in stride(from: tx - r, through: tx + r, by: 1) { for z in stride(from: tz - r, through: tz + r, by: 1) where w.isLoaded(x, z) {
                        let top = w.topY(x, z)
                        guard top > 0 else { continue }
                        for y in max(1, top - 4)...min(CH - 1, top + 12) { undo.append((IVec3(x, y, z), w.block(x, y, z))) }
                    } }
                }
            }
            Nation.build(g, "Testford", x: tx, z: tz)
        }
        defer { for (q, b) in undo.reversed() where w.block(q.x, q.y, q.z) != b { w.setBlock(q.x, q.y, q.z, b) } }
        let sites = Nation.s.provinces["Testford"]?.sites ?? []
        func count(_ s: [Int], _ name: String, r: Int, h: Int) -> Int {
            guard Blocks.has(name) else { return 0 }
            let id = Blocks.id(name)
            var n = 0
            for dx in -r...r { for dz in -r...r { for dy in 0...h where w.block(s[0] + dx, s[1] + dy, s[2] + dz) == id { n += 1 } } }
            return n
        }
        let farm = sites.first { $0[3] == 0 }, cabin = sites.first { $0[3] == 1 }, hall = sites.first { $0[3] == 2 }
        let wheat = farm.map { count($0, "wheat", r: 3, h: 1) } ?? 0
        let water = farm.map { count($0, "water", r: 0, h: 0) } ?? 0
        let walls = cabin.map { count($0, "spruce_planks", r: 3, h: 3) } ?? 0
        let panes = cabin.map { count($0, "glass_pane", r: 3, h: 3) } ?? 0
        let stone = hall.map { count($0, Nation.hallStyles[1].wall, r: 6, h: 5) } ?? 0
        let flag = hall.map { count($0, Nation.flagColors[0].wool, r: 3, h: 12) } ?? 0
        check(sites.count == 4 && wheat >= 20 && water == 1 && walls >= 30 && panes >= 2 && stone >= 100 && flag >= 4,
              "C3 building: \(sites.count) of 4 built (farm: \(wheat) wheat, \(water) water; cabin: \(walls) plank wall blocks, \(panes) windows; hall: \(stone) stone brick, flag \(flag) blocks); \(Nation.s.provinces["Testford"]?.tries ?? 0) sites tried")
    }
}
