import Foundation
import simd

// `--questbugs --only pm9d`: the Oct 9 PM Quest playtest, task 9 (enchanting table). The table follows the reference
// algorithm: slot costs from bookshelves, a modified level from enchantability, a weighted pick among the item's table
// enchantments, extra picks while rand(50) <= level (level halved each time, incompatible ones removed), and offers that
// stay put until an enchant re-rolls the player's seed. Prints the level-30 distributions (evidence: docs/status/evidence/2026-10-09-pm/).
enum PM9DTests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        runNames(check)
        // Slot costs: 15 shelves always give a 30 in slot 3; no shelves keep every slot at 8 or under.
        var c15 = Set<Int>(), c0 = 0
        for s in 0..<2000 {
            c15.insert(Enchant.tableCosts(bookshelves: 15, seed: UInt64(s * 7919 + 1))[2])
            c0 = max(c0, Enchant.tableCosts(bookshelves: 0, seed: UInt64(s * 7919 + 1)).max() ?? 0)
        }
        check(c15 == [30] && c0 <= 8, "pm9d table: 15 shelves -> slot 3 costs \(c15.sorted()) (want [30]); 0 shelves max \(c0) (want <= 8)")

        var rng = SRng(0x5EED_0909)
        // 10,000 level-30 rolls (15 shelves, slot 3) per item: every table enchantment of the item shows up, no treasure,
        // no incompatible pair, and a sensible multi-enchant rate.
        let items = ["diamond_pickaxe", "iron_pickaxe", "golden_pickaxe", "iron_shovel", "diamond_axe", "diamond_sword", "iron_sword",
                     "diamond_helmet", "diamond_chestplate", "iron_leggings", "diamond_boots", "bow", "crossbow", "trident",
                     "fishing_rod", "book"] + (Guns.all.first.map { [$0.key] } ?? [])
        for k in items {
            guard Items.has(k) else { check(false, "pm9d table: item \(k) missing"); continue }
            let item = Items.id(k)
            var count: [Ench: Int] = [:], levels: [String: Int] = [:], sizes = [Int](repeating: 0, count: 8)
            var bad: [String] = [], treasure = 0
            let n = 10_000
            for _ in 0..<n {
                let seed = rng.next()
                let cost = Enchant.tableCosts(bookshelves: 15, seed: seed)[2]
                let l = Enchant.tableOffer(item: item, cost: cost, seed: seed, slot: 2).ench
                sizes[min(7, l.count)] += 1
                for (i, a) in l.enumerated() {
                    count[a.0, default: 0] += 1
                    levels[Enchant.displayLine(a.0, a.1), default: 0] += 1
                    if Enchant.def(a.0).treasure { treasure += 1 }
                    for b in l[(i + 1)...] where !Enchant.compatible(a.0, b.0) {
                        bad.append("\(Enchant.def(a.0).key)+\(Enchant.def(b.0).key)")
                    }
                }
            }
            let multi = Float(n - sizes[0] - sizes[1]) / Float(n)
            let want = Ench.allCases.filter { !Enchant.def($0).treasure && Enchant.applies($0, item, table: true) }
            let missing = want.filter { count[$0, default: 0] == 0 }.map { Enchant.def($0).key }
            let pct = { (c: Int) in String(format: "%.1f%%", 100 * Float(c) / Float(n)) }
            print("pm9d dist \(k): multi \(pct(n - sizes[0] - sizes[1])) sizes " + (0..<8).filter { sizes[$0] > 0 }.map { "\($0):\(pct(sizes[$0]))" }.joined(separator: " "))
            print("pm9d dist \(k): " + count.sorted { $0.value > $1.value }.map { "\(Enchant.def($0.key).name) \(pct($0.value))" }.joined(separator: ", "))
            print("pm9d dist \(k) levels: " + levels.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            check(missing.isEmpty, "pm9d table \(k): every table enchantment appears at level 30 (missing \(missing))")
            check(bad.isEmpty && treasure == 0, "pm9d table \(k): no incompatible pairs (\(Set(bad).sorted().prefix(4))) and no treasure (\(treasure))")
            // Reference at level 30: a book keeps one entry fewer; the rest get a 2nd pick with chance (L+1)/50 where L is
            // the modified level (~31-40), so roughly 60-85% (low-enchantability bows/tridents ~60%).
            let lo: Float = k == "book" ? 0.15 : 0.45, hi: Float = k == "book" ? 0.6 : 0.9
            check(multi >= lo && multi <= hi, "pm9d table \(k): multi-enchant rate \(String(format: "%.1f%%", multi * 100)) in \(Int(lo * 100))...\(Int(hi * 100))%")
            if k.hasSuffix("pickaxe") {
                let f = count[.fortune, default: 0], s = count[.silkTouch, default: 0]
                check(f > 0 && s > 0 && !bad.contains { $0.contains("fortune") && $0.contains("silk") },
                      "pm9d table \(k): Fortune \(pct(f)) and Gentle Touch (silk_touch) \(pct(s)) both offered, never together")
            }
        }

        // Offers vary: the three slots of one seed are not clones, seeds differ, and items differ for one seed.
        let pick = Items.id("diamond_pickaxe"), sword = Items.id("diamond_sword")
        var sameAll = 0, distinct = Set<String>(), itemSame = 0
        for s in 0..<500 {
            let seed = Enchant.mix(UInt64(s), 7)
            let costs = Enchant.tableCosts(bookshelves: 15, seed: seed)
            let offers = (0..<3).map { Enchant.encode(Enchant.pack(Enchant.tableOffer(item: pick, cost: costs[$0], seed: seed, slot: $0).ench)) }
            if offers[0] == offers[1] && offers[1] == offers[2] { sameAll += 1 }
            distinct.insert(offers[2].joined(separator: ","))
            let sw = Enchant.encode(Enchant.pack(Enchant.tableOffer(item: sword, cost: costs[2], seed: seed, slot: 2).ench))
            if sw == offers[2] { itemSame += 1 }
        }
        check(sameAll < 25 && distinct.count > 40 && itemSame < 50,
              "pm9d table: offers vary (3 slots alike \(sameAll)/500, \(distinct.count) distinct slot-3 pickaxe offers, pickaxe==sword \(itemSame))")

        // The menu: the clue is one of the offer's entries, the enchant applies exactly the offer, then the seed re-rolls.
        let surv0 = game.survival, seed0 = game.enchantSeed
        game.survival = false
        let p = IVec3(Int(floor(game.player.pos.x)), Int(floor(game.player.pos.y)), Int(floor(game.player.pos.z)))
        let m = EnchantMenu(game: game, at: p)
        var applied = 0, clueOk = 0, rerolled = 0, changedOffers = 0
        for _ in 0..<20 {
            m.box[0] = ItemStack(pick, 1)
            m.changed()
            let before = m.clues.map { $0.map { Enchant.displayLine($0.0, $0.1) } ?? "-" } + m.costs.map(String.init)
            let slot = m.costs.lastIndex { $0 > 0 } ?? 0
            let want = Enchant.tableOffer(item: pick, cost: m.costs[slot], seed: game.enchantSeed, slot: slot).ench
            if let c = m.clues[slot], want.contains(where: { $0.0 == c.0 && $0.1 == c.1 }) { clueOk += 1 }
            let s0 = game.enchantSeed
            m.buttonPressed(slot)
            if Enchant.encode(m.box[0].ench) == Enchant.encode(Enchant.pack(want)) && !want.isEmpty { applied += 1 }
            if game.enchantSeed != s0 { rerolled += 1 }
            m.box[0] = ItemStack(pick, 1)
            m.changed()
            let after = m.clues.map { $0.map { Enchant.displayLine($0.0, $0.1) } ?? "-" } + m.costs.map(String.init)
            if after != before { changedOffers += 1 }
        }
        m.box[0] = .empty
        game.survival = surv0; game.enchantSeed = seed0
        check(applied == 20 && clueOk == 20 && rerolled == 20 && changedOffers >= 15,
              "pm9d table menu: enchant applies the offer \(applied)/20, clue in offer \(clueOk)/20, seed re-rolls \(rerolled)/20, offers change \(changedOffers)/20 (shelves \(m.shelves))")
    }

    // Task 10: every display name the game registers, written to /tmp/blocksmith-display-names.txt (or `--namedump FILE`)
    // for `tools/namecheck.py --coined --dump FILE`, and checked here against tools/coined-terms.txt.
    static func displayStrings() -> [String] {
        var shown: [String] = []
        for i in 0..<Blocks.count { shown.append(Blocks.name(BlockID(i))) }
        for i in 0..<Items.count { shown.append(Items.name(ItemID(i))) }
        for k in MobKind.allCases { shown.append(k.name) }
        for b in Biome.allCases { shown.append(b.displayName) }
        for d in [Dim.overworld, .nether, .end, .deep] { shown.append(d.displayName) }
        for a in Advancements.all { shown.append(a.title); shown.append(a.desc) }
        shown += Advancements.tabs
        for e in Ench.allCases { shown.append(Enchant.def(e).name) }
        for e in Effect.allCases { shown.append(e.name) }
        for m in MusicMood.allCases { shown.append(m.label) }
        shown += Game.creditsLines
        return Array(Set(shown)).sorted()
    }

    static func coinedHits(_ names: [String], termsFile: String = "tools/coined-terms.txt") -> [String]? {
        guard let text = try? String(contentsOfFile: termsFile, encoding: .utf8) else { return nil }
        var res: [NSRegularExpression] = []
        for raw in text.split(separator: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            let ci = t.hasPrefix("*")
            let term = NSRegularExpression.escapedPattern(for: ci ? String(t.dropFirst()) : t)
            if let r = try? NSRegularExpression(pattern: ci ? "\\b" + term : "\\b" + term + "\\b", options: ci ? [.caseInsensitive] : []) { res.append(r) }
        }
        return names.filter { n in res.contains { $0.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil } }
    }

    static func runNames(_ check: (Bool, String) -> Void) {
        let names = displayStrings()
        let out = CommandLine.arguments.firstIndex(of: "--namedump").flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil }
            ?? "/tmp/blocksmith-display-names.txt"
        try? names.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        let hits = coinedHits(names)
        check(hits != nil, "pm9d names: tools/coined-terms.txt readable (run from the repo root)")
        check(hits?.isEmpty ?? false, "pm9d names: \(names.count) display names (dump \(out)), coined terms: \(hits?.prefix(20).joined(separator: " | ") ?? "-")")
    }
}
