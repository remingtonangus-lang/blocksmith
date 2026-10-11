import Foundation
import simd

// Countries that give minerals (backlog B4, Countries.swift; docs/status/countries.md).
extension TownTests {
    static func countries(_ g: Game, _ check: (Bool, String) -> Void) {
        let savedPos = g.player.pos, savedSurvival = g.survival, savedState = Countries.state, savedMoney = g.money
        let savedInv = g.inventory.main.slots, savedToast = g.onToast, savedTownLaw = TownLaw.state
        var toasts: [String] = []
        defer {
            g.player.pos = savedPos; g.survival = savedSurvival; g.money = savedMoney; g.inventory.main.slots = savedInv
            g.onToast = savedToast; TownLaw.state = savedTownLaw
            Countries.reset(); Countries.state = savedState
        }
        Countries.reset()
        Countries.state.seed = g.world.seed
        g.survival = true
        g.onToast = { toasts.append($0) }
        g.inventory.main.slots = savedInv.map { _ in .empty }
        let seed = g.world.seed
        func tick(at p: V3) {
            g.player.pos = p
            Countries.lastTick = g.clock - 2
            Countries.tick(g)
        }

        // The layer: every seat inside its own cell and belonging to itself; names, flags and minerals well formed.
        var ok = true, names = Set<String>(), flagsOK = true, richOK = true, taxOK = true
        for cz in -3...3 { for cx in -3...3 {
            let c = Countries.make(cx, cz, seed: seed)
            if floorDiv(c.seatX, Countries.cell) != cx || floorDiv(c.seatZ, Countries.cell) != cz { ok = false }
            if Countries.cellAt(c.seatX, c.seatZ, seed: seed) != (cx, cz) { ok = false }
            names.insert(c.name)
            if c.flag.0 == c.flag.1 { flagsOK = false }
            if c.rich.count != 2 || c.rich[0] == c.rich[1] { richOK = false }
            if c.tax < 0 || c.tax > 15 { taxOK = false }
            if Countries.make(cx, cz, seed: seed).name != c.name || Countries.richMinerals(cx, cz, seed: seed) != c.rich { ok = false }
        } }
        check(ok && flagsOK && richOK && taxOK && names.count >= 35,
              "countries: 49 seat cells, each seat in its own country, \(names.count) distinct names, two-colour flags, two rich minerals, tax 0-15%")
        let here = Countries.at(g, g.player.pos)
        check(!here.name.isEmpty && here.name.first!.isUppercase && !here.name.contains(" "),
              "countries: you start in \(here.name), rich in \(here.richText), tax \(here.tax)%")

        // Generation: the same chunk with and without its country's veins differs only in ores of those two minerals,
        // laid into stone (nothing else moves).
        do {
            let a = WorldGen(seed: seed), b = WorldGen(seed: seed)
            b.countryOres = false
            let cx = floorDiv(Int(floor(g.player.pos.x)), CS) + 3, cz = floorDiv(Int(floor(g.player.pos.z)), CS) + 3
            let rich = Countries.rich(atX: cx * CS + 8, z: cz * CS + 8, seed: seed)
            var richOres = Set<BlockID>()
            for m in rich {
                let keys: [String]
                switch m {
                case .coal: keys = ["coal_ore", "deepslate_coal_ore"]
                case .iron: keys = ["iron_ore", "deepslate_iron_ore"]
                case .copper: keys = ["copper_ore", "deepslate_copper_ore"]
                case .gold: keys = ["gold_ore", "deepslate_gold_ore"]
                case .lapis: keys = ["lapis_ore", "deepslate_lapis_ore"]
                case .titanium: keys = ["diamond_ore", "deepslate_diamond_ore"]
                case .emerald: keys = ["emerald_ore", "deepslate_emerald_ore"]
                }
                for k in keys where Blocks.has(k) { richOres.insert(Blocks.id(k)) }
            }
            let stones: Set<BlockID> = [STONE, GRANITE_ID, DIORITE_ID, ANDESITE_ID, DEEPSLATE, TUFF_ID, EMBERSLATE]
            let with = a.generate(cx: cx, cz: cz), without = b.generate(cx: cx, cz: cz)
            var added = 0, other = 0
            for i in 0..<min(with.count, without.count) where with[i] != without[i] {
                if richOres.contains(with[i]) && stones.contains(without[i]) { added += 1 } else { other += 1 }
            }
            check(added > 20 && other == 0, "countries: a chunk rich in \(rich.map { $0.name }.joined(separator: " and ")) gets \(added) more ore blocks, \(other) other changes")
        }

        // Prices: a country pays less for what it's rich in and more for what it lacks; tax on purchases; no
        // buy-and-sell loop whatever the country or your standing.
        let ironRich = CountryTerms(rich: [.iron, .coal], tax: 0, ally: false, active: true)
        let ironPoor = CountryTerms(rich: [.gold, .lapis], tax: 0, ally: false, active: true)
        let iron = Items.id("raw_iron")
        let plain = ShopPricing(reputation: 0, hero: 0)
        let sRich = Economy.sellPrice(iron, ShopPricing(reputation: 0, hero: 0, country: ironRich))
        let sPoor = Economy.sellPrice(iron, ShopPricing(reputation: 0, hero: 0, country: ironPoor))
        check(sRich < Economy.sellPrice(iron, plain) && Economy.sellPrice(iron, plain) < sPoor,
              "countries: raw iron sells for \(Money.format(sRich)) where iron is plentiful, \(Money.format(sPoor)) where it's scarce")
        let taxed = Economy.buyPrice(Items.id("bread"), ShopPricing(reputation: 0, hero: 0, country: CountryTerms(rich: [], tax: 0.15, ally: false, active: true)))
        check(taxed > Economy.buyPrice(Items.id("bread"), plain), "countries: a 15% tax raises bread to \(Money.format(taxed))")
        var loop: String?
        for (item, _) in Countries.mineralOf {
            guard let v = Economy.value(of: item), !Economy.isEmerald(item), ShopKind.allCases.contains(where: { Economy.buysItem($0, item) }) else { continue }
            let bestSell = Economy.sellPrice(item, ShopPricing(reputation: 1000, hero: 1, honour: 100, town: .owned, country: ironPoor))
            let cheapest = Economy.buyPrice(item, ShopPricing(reputation: 1000, hero: 1, honour: 100, town: .owned,
                                                               country: CountryTerms(rich: Mineral.allCases, tax: 0, ally: true, active: true)))
            if bestSell >= cheapest || (Economy.cashIn[item].map { Float(bestSell) >= $0 } ?? false) {
                loop = Items.key(item) + " (value \(v), sells \(bestSell), buys \(cheapest), cash-in \(Economy.cashIn[item] ?? -1))"
            }
        }
        check(loop == nil, "countries: no mineral sells for what it costs anywhere (best sell under the cheapest buy and the least cash-in)\(loop.map { ": " + $0 } ?? "")")

        // Borders: crossing shows the country you enter.
        let a = here
        let n = Countries.neighbours(g, a).first { abs($0.cx - a.cx) + abs($0.cz - a.cz) == 1 }!
        var dir = V2(Float(n.seatX - a.seatX), Float(n.seatZ - a.seatZ)); dir = dir / simd_length(dir)
        let mid = V2(Float(a.seatX + n.seatX) / 2, Float(a.seatZ + n.seatZ) / 2)
        func spot(_ along: Float) -> V3 { V3(mid.x + dir.x * along, 100, mid.y + dir.y * along) }
        Countries.lastKey = nil
        toasts = []
        tick(at: spot(-30)); tick(at: spot(30))
        let entering = toasts.first { $0.hasPrefix("Entering \(n.name)") }
        check(Countries.at(g, spot(-30)) == a && Countries.at(g, spot(30)) == n && Countries.crossings == 1 && entering != nil,
              "countries: walking from \(a.name) into \(n.name): \"\(entering ?? toasts.first ?? "no toast")\"")
        check(Countries.hudLine(g)?.0.hasPrefix(n.name) == true, "countries: the minimap names the country you're in")

        // Standing: crimes lower it; at -50 its towns are on edge (wary prices) when you arrive.
        let town = "Testcountry Ford"
        Countries.state.towns[town] = [n.seatX, n.seatZ]
        Countries.crime(g, town: town, at: V3(Float(n.seatX), 80, Float(n.seatZ)), heat: 2)
        let s1 = Countries.standing(n)
        Countries.townTurned(g, town: town, at: V3(Float(n.seatX), 80, Float(n.seatZ)))
        Countries.lawKilled(g, town: town, at: V3(Float(n.seatX), 80, Float(n.seatZ)))
        Countries.lawKilled(g, town: town, at: V3(Float(n.seatX), 80, Float(n.seatZ)))
        check(s1 == -6 && Countries.isEnemy(n) && Countries.isEnemyTown(town) && TownConquest.standing(town) == .wary,
              "countries: a crime costs \(Int(-s1)), a town turning and two dead lawmen make you \(n.name)'s enemy (\(Int(Countries.standing(n)))): its towns are wary")
        Countries.state.standing[n.key] = 0
        for _ in 0..<10 { Countries.traded(g, town: town, at: V3(Float(n.seatX), 80, Float(n.seatZ))) }
        check(abs(Countries.standing(n) - 2) < 0.01, "countries: ten trades raise your standing by 2")

        // The capital, the treaty and annexing.
        // (a country with no town near its seat has no capital: the first of you and your neighbours that has one)
        let withCap = ([a] + Countries.neighbours(g, a)).first { Countries.capital(g, $0) != nil } ?? a
        if let cap = Countries.capital(g, withCap) {
            let a = withCap
            let keeper = Mob(.villager, at: V3(Float(cap.x), 80, Float(cap.z)))
            var v = VillagerData(); v.town = cap.name; v.shop = "general"; v.person = "Test Keeper"; keeper.villager = v
            check(Countries.offersTreaty(g, keeper) && Countries.at(g, x: cap.x, z: cap.z) == a,
                  "countries: \(a.name)'s capital is \(cap.name) (\(cap.x), \(cap.z)), \(simd_length(V2(Float(cap.x - a.seatX), Float(cap.z - a.seatZ))).rounded()) blocks from its seat")
            g.money = 100_000
            Countries.state.standing[a.key] = 10
            let refused = Countries.signTreaty(g, keeper)
            Countries.state.standing[a.key] = 30
            let signed = Countries.signTreaty(g, keeper)
            check(!refused.1 && signed.1 && Countries.isAlly(a) && g.money == 100_000 - Countries.treatyFee,
                  "countries: the treaty needs standing \(Int(Countries.allyAt)) (\"\(refused.0)\"), then \"\(signed.0)\"")
            let allyBuy = Economy.buyPrice(Items.id("bread"), ShopPricing(reputation: 0, hero: 0, country: Countries.terms(g, town: cap.name, at: keeper.pos)))
            let other = Economy.buyPrice(Items.id("bread"), ShopPricing(reputation: 0, hero: 0, country: CountryTerms(rich: a.rich, tax: Float(a.tax) / 100, ally: false, active: true)))
            check(allyBuy < other || (allyBuy == other && other <= 2), "countries: an ally's bread costs \(Money.format(allyBuy)) (\(Money.format(other)) otherwise)")
            g.inventory.main.slots = savedInv.map { _ in .empty }
            g.inventory.main[0] = ItemStack(Items.id("raw_iron"), 10)
            check(Countries.duty(g, into: a) == 0 && Countries.duty(g, into: n == a ? here : n) == 60 * 10 * Countries.dutyPct / 100,
                  "countries: customs: an ally charges no duty, a neighbour \(Money.format(Countries.duty(g, into: n == a ? here : n))) on ten raw iron")
            // Take the capital: the whole country is yours.
            let lesser = "Testcountry Bend"
            Countries.state.towns[lesser] = [a.seatX + 30, a.seatZ + 30]
            Countries.townTaken(g, cap.name, at: keeper.pos)
            check(Countries.isAnnexed(a) && TownConquest.owns(lesser) && !Countries.isAlly(a) && Countries.terms(g, town: lesser, at: V3(Float(a.seatX), 80, Float(a.seatZ))).tax == 0,
                  "countries: taking \(cap.name) annexes \(a.name): its other towns are yours and untaxed")
            Countries.state.annexed = []; Countries.state.allies = []
        } else {
            let sc = g.world.gen.structures
            let v = sc?.nearest("village", x: a.seatX, z: a.seatZ, maxRegions: 3)
            check(false, "countries: \(a.name) or a neighbour has a capital (structures \(sc != nil), nearest village \(v.map { "\($0.anchor.x),\($0.anchor.z)" } ?? "none"), seat \(a.seatX),\(a.seatZ))")
        }

        // Customs at the border post between the two: owe on the way up, pay at the post; run it and it counts.
        if let post = Countries.postSpot(g, a, n) {
            let p = V3(Float(post.0), 100, Float(post.1))
            check(Countries.at(g, p) == a || Countries.at(g, p) == n, "countries: \(a.name) and \(n.name) share a border post at (\(post.0), \(post.1))")
            g.inventory.main.slots = savedInv.map { _ in .empty }
            g.inventory.main[0] = ItemStack(Items.id("raw_iron"), 10)
            g.money = 10_000
            Countries.state.standing[n.key] = 0
            Countries.paidPost = nil; Countries.owed = 0; Countries.owedTo = nil; Countries.owedPost = nil
            let near = p - V3(dir.x, 0, dir.y) * 25
            Countries.lastKey = nil
            tick(at: near)
            let owed = Countries.owed
            tick(at: p - V3(dir.x, 0, dir.y) * 3)
            check(owed > 0 && Countries.owed == 0 && g.money == 10_000 - owed && Countries.paidPost != nil,
                  "countries: customs asks \(Money.format(owed)) duty near the post and takes it at the booth")
            // Back away, then run the post.
            tick(at: p - V3(dir.x, 0, dir.y) * 120)
            tick(at: near)
            let before = Countries.standing(n)
            tick(at: p + V3(dir.x, 0, dir.y) * 20)
            check(Countries.smuggled == 1 && Countries.standing(n) < before, "countries: running the post costs standing with \(n.name) (\(Int(before)) -> \(Int(Countries.standing(n))))")
            // A post built near you: floor, booth and both flags.
            let bx = Int(floor(savedPos.x)) + 20, bz = Int(floor(savedPos.z)) + 20
            Countries.build(g, at: (bx, bz), a, n)
            let gy = g.world.gen.column(bx, bz).height
            let flag = g.world.block(bx + 4, gy + 6, bz - 1)
            check(g.world.block(bx, gy, bz) == Blocks.id("stone_bricks") && Blocks.def(flag).name.hasSuffix("_wool"),
                  "countries: a border post builds its floor and flags (\(Blocks.def(flag).name))")
        } else {
            check(true, "countries: \(a.name) and \(n.name) have no post spot (water or a town on the line)")
        }

        // Wars: declared and ended over the days, frontier towns change hands.
        Countries.state.wars = [:]
        var declared = 0, peace = 0
        for day in 1...60 {
            let before = Countries.state.wars.count
            Countries.simulateDay(g, day: day)
            if Countries.state.wars.count > before { declared += 1 }
            if Countries.state.wars.count < before { peace += 1 }
        }
        check(declared > 0 && peace > 0, "countries: over 60 days around you, \(declared) wars declared and \(peace) peaces made")
        let front = "Testcountry Crossing"
        let fp = mid - dir * 100
        Countries.state.towns[front] = [Int(fp.x), Int(fp.y)]
        Countries.state.townOwner = [:]
        var took = false
        for h in 0..<64 {
            Countries.fight(g, a, n, UInt64(h) &* 0x9E3779B97F4A7C15 | 0)
            if Countries.ofKnown(g, town: front) == n { took = true; break }
        }
        check(took && toasts.contains { $0.contains("took \(front) from \(a.name)") }, "countries: a war moves a frontier town to \(n.name)")

        // Saved and loaded.
        var d: [String: String] = [:]
        Countries.save(&d)
        let owner = Countries.state.townOwner[front]
        Countries.load(d)
        check(Countries.state.townOwner[front] == owner && Countries.state.towns[town] != nil, "countries: standing, towns and wars survive a save")

        // The big map draws the borders.
        var lines: [HudLine] = []
        Countries.mapBorders(&lines, g, x0: 0, y0: 0, cols: 152, rows: 82, px: 2, wx: mid.x, wz: mid.y, bpc: 16, s: 1)
        check(lines.count > 40, "countries: the world map draws borders and names (\(lines.count) lines)")
    }
}
