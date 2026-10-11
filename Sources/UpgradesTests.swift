import Foundation
import simd

// Tool upgrades replace enchanting (backlog B5, Upgrades.swift; docs/status/upgrades.md).
extension TownTests {
    static func upgrades(_ g: Game, _ check: (Bool, String) -> Void) {
        let savedInv = g.inventory.main.slots, savedArmor = g.inventory.armor.slots, savedSel = g.inventory.selected
        let savedXP = g.xpLevel, savedSurvival = g.survival
        defer {
            g.inventory.main.slots = savedInv; g.inventory.armor.slots = savedArmor; g.inventory.selected = savedSel
            g.xpLevel = savedXP; g.survival = savedSurvival
        }
        func id(_ k: String) -> ItemID { Items.id(k) }
        func clear() { g.inventory.main.slots = savedInv.map { _ in .empty }; g.inventory.armor.slots = savedArmor.map { _ in .empty } }

        // Every enchantment is an upgrade (curses aside), with a part, a name and materials that exist; every item's
        // anvil-supported enchantments are in its tree.
        let missing = Ench.allCases.filter { !Enchant.def($0).curse && Upgrades.specs[$0] == nil }
        let badMat = Upgrades.specs.values.compactMap { $0.extra }.filter { !Items.has($0) }
        let names = Ench.allCases.filter { Upgrades.isUpgrade($0) }.map { Enchant.def($0).name }
        check(missing.isEmpty && badMat.isEmpty && Set(names).count == names.count,
              "upgrades: \(names.count) upgrades, each with a part and materials, names unique\(missing.isEmpty ? "" : ", missing \(missing)")\(badMat.isEmpty ? "" : ", unknown \(badMat)")")
        var trees = 0, gaps: [String] = []
        for i in 0..<Items.count {
            let it = ItemID(i), k = Items.key(it)
            guard k != "book", k != "enchanted_book" else { continue }
            let t = Upgrades.tree(it)
            if !t.isEmpty { trees += 1 }
            for e in Ench.allCases where Upgrades.isUpgrade(e) && Enchant.applies(e, it, table: false) && !t.contains(e) { gaps.append("\(k):\(e)") }
            if !t.isEmpty && Upgrades.base(it, level: 1) == nil && Upgrades.specs[t[0]]?.extra == nil { gaps.append("\(k): no cost") }
        }
        check(trees > 60 && gaps.isEmpty, "upgrades: \(trees) items have an upgrade tree\(gaps.isEmpty ? "" : ", gaps: \(gaps.prefix(5))")")
        let swordTree = Upgrades.tree(id("iron_sword")).map { Enchant.def($0).name }
        check(swordTree.contains("Honed Edge") && swordTree.contains("Weighted Pommel") && !Upgrades.tree(id("iron_pickaxe")).isEmpty
              && Upgrades.tree(id("gun_rifle")).map({ Enchant.def($0).name }).contains("Stabilising Scope"),
              "upgrades: the iron sword's tree: \(swordTree.joined(separator: ", "))")
        check(Blocks.def(Blocks.id("enchanting_table")).display == "Upgrade Bench" && Items.def(id("enchanted_book")).display == "Upgrade Kit",
              "upgrades: the enchanting table is the Upgrade Bench, enchanted books are Upgrade Kits")

        // Costs: experience levels plus the item's material and the part's.
        let c1 = Upgrades.cost(id("iron_sword"), .sharpness, level: 1), c3 = Upgrades.cost(id("iron_sword"), .sharpness, level: 3)
        check(c1.xp == 2 && c3.xp == 4 && c1.items.contains { $0.0 == id("iron_ingot") && $0.1 == 1 } && c1.items.contains { $0.0 == id("flint") && $0.1 == 1 }
              && c3.items.contains { $0.0 == id("iron_ingot") && $0.1 == 3 },
              "upgrades: Honed Edge I on an iron sword costs \(c1.xp) levels + \(Upgrades.costText(c1)); III costs \(c3.xp) + \(Upgrades.costText(c3))")
        check(Upgrades.cost(id("iron_sword"), .mending, level: 1).xp == 5, "upgrades: an advanced part (Field Kit) costs 3 levels more")

        // Fitting in survival: charges, refuses, conflicts, maximum.
        clear()
        g.survival = true
        g.inventory.selected = 0
        g.inventory.main[0] = ItemStack(id("iron_sword"), 1)
        g.inventory.main[1] = ItemStack(id("iron_ingot"), 20)
        g.inventory.main[2] = ItemStack(id("flint"), 20)
        g.xpLevel = 1
        let poor = Upgrades.fit(g, g.inventory.main, 0, .sharpness)
        g.xpLevel = 10
        let ok = Upgrades.fit(g, g.inventory.main, 0, .sharpness)
        check(!poor.1 && ok.1 && Enchant.level(.sharpness, g.inventory.main[0]) == 1 && g.xpLevel == 8
              && g.inventory.main.countOf(id("iron_ingot")) == 19 && g.inventory.main.countOf(id("flint")) == 19,
              "upgrades: \"\(poor.0)\" then \"\(ok.0)\" (10 -> \(g.xpLevel) levels, 20 -> 19 iron and flint)")
        let clash = Upgrades.fit(g, g.inventory.main, 0, .smite)
        check(!clash.1 && Enchant.level(.smite, g.inventory.main[0]) == 0, "upgrades: one edge treatment at a time: \"\(clash.0)\"")
        g.survival = false
        for _ in 0..<6 { Upgrades.fit(g, g.inventory.main, 0, .sharpness) }
        check(Enchant.level(.sharpness, g.inventory.main[0]) == 5 && Upgrades.blocker(g.inventory.main[0], .sharpness) == "Fully upgraded",
              "upgrades: creative fits free, up to the maximum (Honed Edge V)")
        g.survival = true

        // Worn armour, through the bench screen.
        clear()
        g.inventory.armor[1] = ItemStack(id("iron_chestplate"), 1)
        g.inventory.main[0] = ItemStack(id("iron_ingot"), 10)
        g.inventory.main[1] = ItemStack(id("white_wool"), 10)
        g.xpLevel = 10
        let m = UpgradeBenchMenu(game: g)
        let rows = m.rows
        let protRow = Upgrades.tree(id("iron_chestplate")).firstIndex(of: .protection).map { $0 + 1 } ?? -1
        if protRow > 0 { m.pressed(protRow) }
        check(rows.count == 1 + Upgrades.tree(id("iron_chestplate")).count && rows[0].detail.hasPrefix("worn")
              && Enchant.level(.protection, g.inventory.armor[1]) == 1 && g.inventory.main.countOf(id("white_wool")) == 8,
              "upgrades: the bench lists the worn chestplate's \(rows.count - 1) parts and fits Padded Lining (\(m.status))")

        // Old saves: enchantments load as upgrades, curses dropped.
        var cursed = ItemStack(id("iron_sword"), 1)
        cursed.ench = Enchant.pack([(.sharpness, 3), (.vanishingCurse, 1), (.looting, 2)])
        let back = (try? JSONEncoder().encode(cursed)).flatMap { try? JSONDecoder().decode(ItemStack.self, from: $0) }
        check(back.map { Enchant.level(.sharpness, $0) == 3 && Enchant.level(.looting, $0) == 2 && Enchant.level(.vanishingCurse, $0) == 0 } == true,
              "upgrades: an old enchanted sword loads as \(back.map { Enchant.list($0).map { Enchant.displayLine($0.0, $0.1) }.joined(separator: ", ") } ?? "nothing"), the curse gone")
        var rng = SRng(7), curses = 0
        for _ in 0..<300 { curses += Enchant.select(item: id("iron_chestplate"), level: 30, rng: &rng, treasure: true).filter { Enchant.def($0.0).curse }.count }
        check(curses == 0, "upgrades: loot never rolls a curse (300 treasure rolls)")

        // On the model: gun parts, tool accents, icon pips.
        let all: UInt64 = Enchant.pack([(.stability, 3), (.extendedMag, 3), (.penetration, 1), (.quickReload, 2)])
        var maxVerts = 0, grew = true
        for gi in 0..<Guns.all.count {
            let ex = Guns.upgradeParts(gi, all, magOut: false)
            if ex.count < 3 { grew = false }
            maxVerts = max(maxVerts, (Guns.models[gi].count + ex.count + 1) * 36)
        }
        check(grew && maxVerts <= 1336, "upgrades: every gun model gains its scope, magazine and parts (largest \(maxVerts) vertices; the arm buffer holds 1536)")
        var sw = ItemStack(id("iron_sword"), 1)
        sw.ench = Enchant.pack([(.sharpness, 2), (.knockback, 1), (.unbreaking, 3)])
        let buf = UnsafeMutablePointer<EntityVert>.allocate(capacity: 200)
        defer { buf.deallocate() }
        var wr = EntityWriter(out: buf, capacity: 200)
        Upgrades.writeAccents(&wr, sw, center: .zero, half: 0.2, right: V3(1, 0, 0), up: V3(0, 1, 0), normal: V3(0, 0, 1), thick: 0.01, light: 1)
        check(Upgrades.accents(sw).count == 3 && wr.n == 36 && Upgrades.pips(sw).count == 3,
              "upgrades: an upgraded sword shows an edge line, a grip wrap and a head band (\(wr.n) vertices) and three icon pips")
    }
}
