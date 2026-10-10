import Foundation
import simd

// Checks for towns of people and shops (questcheck runs them on the host every Quest build; on the Mac
// `--towntests`). One line per check through `check`; the caller counts failures.
//   economy:  every catalogue entry is a real item with a price, every shop stocks and buys enough, prices climb with
//             the tiers, and no recipe or smelt turns bought ingredients into a profit at the best reputation.
//   pricing:  reputation and hero bounds, refusal below -100.
//   trade:    buying, stock, the wallet, selling, services, a failed purchase changes nothing.
//   shop UI:  every row's name fits its column, every drawn line stays inside the panel, rows scroll.
//   people:   names and towns for everyone, no borrowed character names, the day's routine by role, weapons by role.
//   defence:  an armed townsperson kills a zombie next to it; the unarmed don't fight; hurting one turns the armed on
//             you; a pointed gun puts hands up.
//   towns:    generated towns hold the eight shops with keepers, signs and a deputy.
//   capitals: the Capital's cities hold the eight shops, flats, offices and citizens who keep a city day
//             (CapitalTownTests.swift).
enum TownTests {
    static func run(game g: Game, makeWorld: () -> World, check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        economy(check)
        pricing(check)
        trade(g, check)
        law(g, makeWorld, check)             // TownLawTests.swift: law, sheriff, wallet, exchange, voices
        shopUI(g, check)
        people(g, check)
        defence(g, check)
        towns(makeWorld, check)
        capitals(makeWorld, check)
        print(String(format: "towntests: %.1f s", CFAbsoluteTimeGetCurrent() - t0))
    }

    // MARK: Economy

    static func economy(_ check: (Bool, String) -> Void) {
        var missing: [String] = []
        for (k, list) in Economy.stock { for (n, _) in list where !Items.has(n) || Economy.value[n] == nil { missing.append("\(k.rawValue):\(n)") } }
        for (k, list) in Economy.buys { for n in list where !Items.has(n) || Economy.value[n] == nil { missing.append("\(k.rawValue) buys \(n)") } }
        check(missing.isEmpty, "economy: every shop item exists and has a price" + (missing.isEmpty ? "" : " (missing \(missing.joined(separator: ", ")))"))
        let thin = ShopKind.allCases.filter { Economy.catalog($0).count < 6 || (Economy.buys[$0]?.count ?? 0) < 5 }
        check(thin.isEmpty, "economy: every shop sells 6+ items and buys 5+ (\(ShopKind.allCases.map { "\($0.rawValue) \(Economy.catalog($0).count)/\(Economy.buys[$0]?.count ?? 0)" }.joined(separator: ", ")))")
        // Tiers: stone < iron < chainmail/iron armour; a sidearm is a real purchase; ammo is cheap next to its gun.
        let v = Economy.value
        func lt(_ a: String, _ b: String) -> Bool { (v[a] ?? 0) < (v[b] ?? 0) }
        let order = [("stone_sword", "iron_sword"), ("stone_pickaxe", "iron_pickaxe"), ("iron_sword", "gun_sidearm"), ("gun_sidearm", "gun_shotgun"),
                     ("gun_shotgun", "gun_rifle"), ("gun_rifle", "gun_sniper"), ("leather_chestplate", "chainmail_chestplate"),
                     ("chainmail_chestplate", "iron_chestplate"), ("bread", "cooked_beef"), ("iron_ingot", "steel_ingot"), ("steel_ingot", "diamond"),
                     ("raw_iron", "iron_ingot"), ("potion_healing", "golden_apple")]
        let bad = order.filter { !lt($0.0, $0.1) }.map { "\($0.0) >= \($0.1)" }
        check(bad.isEmpty, "economy: prices climb with the tiers" + (bad.isEmpty ? "" : " (\(bad.joined(separator: ", ")))"))
        // Time to afford: the first sidearm takes real work (selling 1000+ wheat, or 90 iron ingots), a loaf of bread doesn't.
        let sell = ShopPricing(reputation: 0, hero: 0)
        let wheatForGun = (v["gun_sidearm"] ?? 0) / max(1, sell.sell(v["wheat"] ?? 1))
        let ironForGun = (v["gun_sidearm"] ?? 0) / max(1, sell.sell(v["iron_ingot"] ?? 1))
        let wheatForBread = (v["bread"] ?? 0) / max(1, sell.sell(v["wheat"] ?? 1))
        check(wheatForGun >= 1000 && ironForGun >= 60 && wheatForBread <= 12,
              "economy: progression (a sidearm = \(wheatForGun) wheat or \(ironForGun) iron sold; bread = \(wheatForBread) wheat)")
        // No buy-craft-sell or buy-smelt-sell profit at the best prices anyone can get.
        var sold: Set<ItemID> = []
        var bought: Set<ItemID> = []
        for k in ShopKind.allCases {
            for c in Economy.catalog(k) { sold.insert(c.item) }
            for n in Economy.buys[k] ?? [] where Items.has(n) { bought.insert(Items.id(n)) }
        }
        func cheapest(_ ing: String) -> Int? {
            if ing.hasPrefix("#") {
                let opts = (Recipes.tagSets[String(ing.dropFirst())] ?? []).filter { sold.contains($0) }.compactMap { Economy.value(of: $0) }
                return opts.min()
            }
            guard Items.has(ing), sold.contains(Items.id(ing)) else { return nil }
            return Economy.value[ing]
        }
        var loops: [String] = []
        var checked = 0
        for r in Recipes.all where !r.result.isEmpty && bought.contains(r.result.item) {
            let ings = r.shapeless.isEmpty ? r.cells.compactMap { $0 } : r.shapeless
            guard !ings.isEmpty else { continue }
            var cost = 0, ok = true
            for i in ings { if let c = cheapest(i) { cost += c } else { ok = false; break } }
            guard ok, let out = Economy.value(of: r.result.item) else { continue }
            checked += 1
            let gain = Float(out * r.result.count) * Economy.maxSellMult, pay = Float(cost) * Economy.minBuyMult
            if gain > pay { loops.append("\(Items.key(r.result.item)) (\(Int(gain)) > \(Int(pay)))") }
        }
        for it in sold {
            guard let out = Recipes.smelt(it), bought.contains(out), let a = Economy.value(of: it), let b = Economy.value(of: out) else { continue }
            checked += 1
            if Float(b) * Economy.maxSellMult > Float(a) * Economy.minBuyMult + 1 { loops.append("smelt \(Items.key(it))") }
        }
        // Anything sold and bought: one item round trip.
        for it in sold.intersection(bought) {
            guard let a = Economy.value(of: it) else { continue }
            checked += 1
            if Float(a) * Economy.maxSellMult >= Float(a) * Economy.minBuyMult { loops.append("resell \(Items.key(it))") }
        }
        check(loops.isEmpty, "economy: no buy-craft-sell profit (\(checked) paths checked)" + (loops.isEmpty ? "" : ": " + loops.joined(separator: ", ")))
        barter(sold: sold, bought: bought, check)
    }

    // The craftsfolk's old emerald barter (Villagers.trades) beside the shops: money must not turn into emeralds
    // (shop items -> a basket -> an emerald) for less than emeralds turn back into money (an emerald -> an offer ->
    // a shop), at list prices with the best shop multipliers. Enchanted items can't be sold, so those offers don't count.
    static func barter(sold: Set<ItemID>, bought: Set<ItemID>, _ check: (Bool, String) -> Void) {
        func price(_ n: String) -> Int? { Items.has(n) ? Economy.value[n] : nil }
        var inCost = Float.infinity, inWhy = "-"
        var outGain: Float = 0, outWhy = "-"
        var bad: [String] = []
        for (_, levels) in Villagers.trades { for level in levels { for t in level {
            let bName = String(t.sell.split(separator: "@")[0])
            if t.sell == "emerald" && t.buyB == nil, Items.has(t.buy), sold.contains(Items.id(t.buy)), let p = price(t.buy) {
                let c = Float(p * t.buyN) * Economy.minBuyMult / Float(t.sellN)
                if c < inCost { inCost = c; inWhy = "\(t.buyN) \(t.buy)" }
            }
            if t.buy == "emerald" && !t.sell.contains("@ench") && !t.sell.contains("@book") && t.buyN > 0, Items.has(bName), bought.contains(Items.id(bName)), let p = price(bName) {
                var extra: Float = 0
                if let b = t.buyB { guard Items.has(b), sold.contains(Items.id(b)), let pb = price(b) else { continue }; extra = Float(pb * t.buyBN) * Economy.minBuyMult }
                let g = (Float(p * t.sellN) * Economy.maxSellMult - extra) / Float(t.buyN)
                if g > outGain { outGain = g; outWhy = "\(t.sellN) \(bName) for \(t.buyN)" }
            }
        } } }
        // The general store's exchange (Wallet.swift): an emerald is bought from you at emeraldSell and sold at
        // emeraldBuy, so the cheapest emerald from shop goods must cost at least what the store pays for one, and the
        // best an emerald fetches through an offer must stay under what the store charges for one.
        if inCost < Float(Economy.emeraldSell) { bad.append(String(format: "shop goods -> emerald %.0f c < the store pays %d c", inCost, Economy.emeraldSell)) }
        if outGain > Float(Economy.emeraldBuy) { bad.append(String(format: "emerald -> money %.0f c > the store charges %d c", outGain, Economy.emeraldBuy)) }
        print(String(format: "towntests: barter: cheapest emerald from shop goods %.0f c (%@), best emerald back to money %.0f c (%@)", inCost, inWhy, outGain, outWhy))
        if outGain > inCost { bad.append(String(format: "emerald in %.0f c < out %.0f c", inCost, outGain)) }
        check(Set(bad).isEmpty, "economy: no shop -> barter -> shop profit" + (bad.isEmpty ? "" : ": " + Set(bad).sorted().joined(separator: ", ")))
    }

    static func pricing(_ check: (Bool, String) -> Void) {
        let best = ShopPricing(reputation: 500, hero: 3), worst = ShopPricing(reputation: -100, hero: 0), even = ShopPricing(reputation: 0, hero: 0)
        check(best.buyMult >= Economy.minBuyMult && best.sellMult <= Economy.maxSellMult && worst.buyMult <= Economy.maxBuyMult
              && worst.sellMult >= Economy.minSellMult && even.buyMult == 1 && even.sellMult == 0.5,
              String(format: "pricing: buy x%.2f-%.2f, sell x%.3f-%.2f, neutral x%.2f / x%.2f", best.buyMult, worst.buyMult, worst.sellMult, best.sellMult, even.buyMult, even.sellMult))
        check(!worst.refuses && ShopPricing(reputation: -101, hero: 0).refuses, "pricing: shops refuse below -100 reputation only")
        check(Money.format(0) == "$0.00" && Money.format(1205) == "$12.05" && Money.format(99) == "$0.99", "money format \(Money.format(1205))")
    }

    // MARK: Trade

    static func keeper(_ g: Game, _ k: ShopKind, at p: V3) -> Mob {
        let m = Mob(.villager, at: p)
        m.home = p
        Townsfolk.setup(m, tag: "shop_\(k.rawValue)", game: g)
        return m
    }

    static func count(_ g: Game, _ key: String) -> Int {
        (0..<36).reduce(0) { $0 + (g.inventory.main[$1].item == Items.id(key) ? g.inventory.main[$1].count : 0) }
    }

    static func trade(_ g: Game, _ check: (Bool, String) -> Void) {
        let savedInv = (0..<36).map { g.inventory.main[$0] }
        let savedMoney = g.money, savedHealth = g.health
        defer { for i in 0..<36 { g.inventory.main[i] = savedInv[i] }; g.money = savedMoney; g.health = savedHealth }
        for i in 0..<36 { g.inventory.main[i] = .empty }
        let m = keeper(g, .general, at: g.player.pos + V3(2, 0, 0))
        let cat = Economy.catalog(.general)
        guard let bi = cat.firstIndex(where: { Items.key($0.item) == "bread" }) else { check(false, "trade: the general store sells bread"); return }
        g.money = 1000
        let price = ShopPricing(reputation: 0, hero: 0).buy(Economy.value["bread"]!)
        let r = Shop.buy(g, m, .general, index: bi, count: 3)
        let stock0 = cat[bi].perDay
        check(r.1 && g.money == 1000 - 3 * price && count(g, "bread") == 3 && m.villager?.stock?[bi] == stock0 - 3,
              "trade: bought 3 bread for \(Money.format(3 * price)) (wallet \(Money.format(g.money)), stock \(m.villager?.stock?[bi] ?? -1)/\(stock0))")
        g.money = price - 1
        let r2 = Shop.buy(g, m, .general, index: bi, count: 1)
        check(!r2.1 && g.money == price - 1 && count(g, "bread") == 3, "trade: no sale without the money (\(r2.0))")
        // Sold out stays sold out until the next day, then restocks.
        g.money = 100_000
        _ = Shop.buy(g, m, .general, index: bi, count: 999)
        let out = Shop.buy(g, m, .general, index: bi, count: 1)
        var v = m.villager!
        v.restockShop(day: (v.stockDay ?? 0) + 1)
        check(!out.1 && v.stock?[bi] == stock0, "trade: a sold-out item restocks the next day (\(out.0))")
        // Selling: wheat to the general store, not to the gunsmith.
        g.money = 0
        g.inventory.main[5] = ItemStack(Items.id("wheat"), 40)
        let sw = Shop.sell(g, m, .general, item: Items.id("wheat"), count: Int.max)
        let each = ShopPricing(reputation: m.villager?.reputation ?? 0, hero: 0).sell(Economy.value["wheat"]!)
        check(sw.1 && count(g, "wheat") == 0 && g.money == 40 * each, "trade: sold 40 wheat for \(Money.format(g.money))")
        let gs = keeper(g, .gunsmith, at: g.player.pos + V3(-2, 0, 0))
        g.inventory.main[5] = ItemStack(Items.id("wheat"), 4)
        check(!Shop.sell(g, gs, .gunsmith, item: Items.id("wheat"), count: 4).1 && count(g, "wheat") == 4, "trade: the gunsmith won't buy wheat")
        // Worn and enchanted items aren't bought.
        var worn = ItemStack(Items.id("iron_sword"), 1); worn.damage = 10
        check(!Shop.sellable(worn), "trade: worn tools can't be sold")
        // The doctor's treatment.
        let doc = keeper(g, .doctor, at: g.player.pos + V3(0, 0, 2))
        g.health = 6; g.money = 10_000
        let fee = Economy.price(.treatment, g)
        let t = Shop.service(g, doc, .treatment)
        check(t.1 && g.health == 20 && g.money == 10_000 - fee, "trade: the doctor patched you up for \(Money.format(fee))")
        // Money survives a save round trip through world.json extra.
        g.money = 4321
        let d = g.saveExtra()
        g.money = 0
        g.loadExtra(d)
        check(g.money == 4321, "trade: the wallet is saved (\(Money.format(g.money)))")
    }

    // MARK: Shop screen

    static func shopUI(_ g: Game, _ check: (Bool, String) -> Void) {
        var long: [String] = []
        for k in ShopKind.allCases {
            var names = Economy.catalog(k).map { ItemStack($0.item, 1).def.display } + (Economy.services[k] ?? []).map { $0.name }
            names += (Economy.buys[k] ?? []).filter { Items.has($0) }.map { ItemStack(Items.id($0), 1).def.display }
            for n in names where Font.width(n) > ShopMenu.nameWidth { long.append("\(n) (\(Font.width(n)) px)") }
        }
        // The status line's messages for every item at their longest, uncut.
        var cut: [String] = []
        for k in ShopKind.allCases {
            let items = Economy.catalog(k).map { $0.item } + (Economy.buys[k] ?? []).filter { Items.has($0) }.map { Items.id($0) }
            for it in items {
                let n = ItemStack(it, 1).def.display
                for msg in ["Bought 64 \(n) for $999.99.", "Sold 64 \(n) for $999.99.", "That's $999.99 each. You have $999.99.", "Sold out of \(n) until tomorrow."]
                    where Font.width(msg) > 284 - 16 { cut.append(msg) }
            }
        }
        check(cut.isEmpty, "shop UI: every shop message fits its line uncut" + (cut.isEmpty ? "" : ": " + cut.prefix(4).joined(separator: " | ")))
        check(long.isEmpty, "shop UI: every name fits the \(ShopMenu.nameWidth) px column" + (long.isEmpty ? "" : ": " + long.joined(separator: ", ")))
        let saved = g.menu
        var overflow: [String] = []
        var rowsSeen = 0
        for k in ShopKind.allCases {
            let m = keeper(g, k, at: g.player.pos + V3(1.5, 0, 0))
            m.villager?.person = "Sophronia Merriweather"         // the longest name we can give
            m.villager?.town = "Juniper Crossing"
            let sm = ShopMenu(game: g, keeper: m, kind: k)
            g.money = 123_456
            sm.status = "You need $220.00 for Iron Horse Armor. You have $123.45."
            let L = HudLayout(1280, 800).fitted(sm)
            let o = sm.origin(L)
            for tab in [false, true] {
                sm.selling = tab
                for scroll in 0...max(0, sm.rows.count - ShopMenu.visible) {
                    sm.scroll = scroll
                    for l in sm.drawLines(L, o) {
                        let w = l.box?.x ?? Float(Font.width(l.text)) * l.scale
                        let x1 = l.x + w, y1 = l.y + (l.box?.y ?? 8 * l.scale)
                        if l.x < o.x - 0.5 || x1 > o.x + Float(sm.width) * L.s + 0.5 || l.y < o.y - 0.5 || y1 > o.y + Float(sm.height) * L.s + 0.5 {
                            overflow.append("\(k.rawValue) '\(l.text)'")
                        }
                    }
                }
                rowsSeen += sm.rows.count
            }
            // The title (drawn by the renderer at 8 px) stays clear of the wallet on the right.
            let wallet = "Wallet " + Money.format(g.money)
            if 8 + Font.width(sm.title) + 6 > sm.width - 8 - Font.width(wallet) { overflow.append("\(k.rawValue) title '\(sm.title)'") }
        }
        check(overflow.isEmpty, "shop UI: nothing drawn outside the panel (8 shops x buy/sell x every scroll)" + (overflow.isEmpty ? "" : ": " + Array(Set(overflow)).sorted().prefix(6).joined(separator: "; ")))
        // Scrolling, tabs and the quantity toggle through the same buttons the laser / cursor press.
        let m = keeper(g, .blacksmith, at: g.player.pos + V3(1.5, 0, 0))
        let sm = ShopMenu(game: g, keeper: m, kind: .blacksmith)
        sm.buttonPressed(ShopMenu.scrollDown)
        let s1 = sm.scroll
        sm.buttonPressed(ShopMenu.tabSell)
        let tabbed = sm.selling && sm.scroll == 0
        sm.buttonPressed(ShopMenu.qtyButton)
        check(s1 == 1 && tabbed && ShopMenu.quantities[sm.qtyIndex] == 5 && !sm.legend.isEmpty,
              "shop UI: scroll \(s1), sell tab \(tabbed), quantity x\(ShopMenu.quantities[sm.qtyIndex]) (\(rowsSeen) rows drawn)")
        g.menu = saved
    }

    // MARK: People

    static func people(_ g: Game, _ check: (Bool, String) -> Void) {
        // Leading characters of the game whose feel towns borrow: never used as names.
        let borrowed: Set<String> = ["Arthur", "John", "Dutch", "Micah", "Sadie", "Hosea", "Abigail", "Javier", "Charles", "Lenny",
                                     "Bill", "Tilly", "Karen", "Mary-Beth", "Molly", "Kieran", "Sean", "Josiah", "Leopold", "Susan",
                                     "Simon", "Uncle", "Jack", "Marston", "Morgan", "Matthews", "Adler", "Grimshaw", "Trelawny", "Strauss", "Pearson",
                                     "Callander", "Williamson", "Escuella", "Smith", "Bell", "Duffy", "Swanson"]
        let used = Set(Townsfolk.firstNames + Townsfolk.surnames)
        check(used.isDisjoint(with: borrowed), "people: no borrowed character names (\(Townsfolk.firstNames.count) first names, \(Townsfolk.surnames.count) surnames)")
        var names = Set<String>(), towns = Set<String>(), missing = 0
        for i in 0..<60 {
            let m = Mob(.villager, at: g.player.pos + V3(Float(i % 8) * 3.1, 0, Float(i / 8) * 2.7))
            m.home = m.pos
            Townsfolk.setup(m, game: g)
            guard let v = m.villager, let n = v.person, let t = v.town, v.role != nil else { missing += 1; continue }
            names.insert(n); towns.insert(t)
        }
        check(missing == 0 && names.count >= 40, "people: 60 townsfolk named (\(names.count) different names, \(towns.count) town; e.g. \(names.sorted().prefix(3).joined(separator: ", ")))")
        let a = Mob(.villager, at: V3(100, 80, 100)); a.home = a.pos; Townsfolk.setup(a, game: g)
        let b = Mob(.villager, at: V3(100, 80, 100)); b.home = b.pos; Townsfolk.setup(b, game: g)
        check(a.villager?.person == b.villager?.person && a.villager?.look == b.villager?.look, "people: identity is stable for a spot (\(a.villager?.person ?? "-"))")
        // The day by role (fractions: 0.05 early, 0.24 noon meal, 0.3 afternoon, 0.4 meeting, 0.48 evening, 0.6 night).
        func day(_ m: Mob) -> [Mob.Activity] { [0.05, 0.24, 0.3, 0.4, 0.48, 0.6].map { m.activity($0) } }
        let farmer = Mob(.villager, at: g.player.pos); var fv = VillagerData(); fv.profession = "farmer"; fv.role = "farmer"; farmer.villager = fv
        let shop = keeper(g, .butcher, at: g.player.pos)
        let dep = Mob(.villager, at: g.player.pos); dep.home = dep.pos; Townsfolk.setup(dep, tag: "deputy", game: g)
        check(day(farmer) == [.idle, .eat, .work, .meet, .social, .idle], "people: a farmer's day \(day(farmer))")
        check(day(shop) == [.work, .work, .work, .work, .idle, .idle], "people: a shopkeeper minds the counter in shop hours \(day(shop))")
        check(day(dep).allSatisfy { $0 == .patrol } && dep.villager?.locked == true, "people: deputies patrol day and night")
        let cit = Mob(.villager, at: g.player.pos); cit.home = cit.pos; Townsfolk.setup(cit, tag: "citizen@10,70,-4", game: g)
        check(day(cit) == [.idle, .eat, .work, .meet, .social, .idle] && cit.villager?.jobSite == [10, 70, -4] && cit.townWeapon == .none,
              "people: a Capital citizen works at the desk they were given, carries nothing \(day(cit))")
        // Weapons by role.
        let kid = Mob(.villager, at: g.player.pos); kid.baby = true; Townsfolk.setup(kid, game: g)
        var elder = VillagerData(); elder.role = "elder"
        check(farmer.townWeapon == .pitchfork && dep.townWeapon == .sword && shop.townWeapon == .cleaver && kid.townWeapon == .none
              && Townsfolk.weapon(elder, baby: false) == .none && keeper(g, .blacksmith, at: g.player.pos).townWeapon == .hammer,
              "people: farmers carry pitchforks, deputies swords, butchers cleavers, smiths hammers; children and elders nothing")
        // Models: every role and shop builds a body with a head, a weapon where armed, nothing NaN.
        var badModel: [String] = []
        let roles = ["deputy", "farmer", "elder", "child", "craftsman", "worker", "citizen"]
        for (i, r) in roles.enumerated() {
            let m = Mob(.villager, at: g.player.pos); var v = VillagerData(); v.role = r; v.look = i * 37; v.person = i % 2 == 0 ? "Clara Hale" : "Amos Hale"
            m.villager = v; m.baby = r == "child"
            let p = townsfolkParts(m, swing: 0.3)
            if p.count < 20 || p.contains(where: { !$0.mn.x.isFinite || !$0.mx.y.isFinite }) { badModel.append(r) }
            if p.map({ $0.mx.y }).max() ?? 0 < 30 { badModel.append(r + " too short") }
        }
        for k in ShopKind.allCases { if townsfolkParts(keeper(g, k, at: g.player.pos), swing: 0).count < 20 { badModel.append(k.rawValue) } }
        check(badModel.isEmpty, "people: every role and shopkeeper has a full model" + (badModel.isEmpty ? "" : " (\(badModel))"))
    }

    // MARK: Defence and reactions

    static func defence(_ g: Game, _ check: (Bool, String) -> Void) {
        let savedMobs = g.mobs.mobs
        let savedHeld = g.inventory.held, savedPos = g.player.pos, savedYaw = g.player.yaw, savedPitch = g.player.pitch
        let savedSurvival = g.survival, savedHealth = g.health
        defer {
            g.mobs.mobs = savedMobs; g.inventory.held = savedHeld; g.player.pos = savedPos; g.player.yaw = savedYaw
            g.player.pitch = savedPitch; g.survival = savedSurvival; g.health = savedHealth
        }
        let w = g.world
        // A spot with clear sight along +X.
        func ground(_ x: Float, _ z: Float) -> V3 { V3(x, Float(w.topY(Int(floor(x)), Int(floor(z))) + 1), z) }
        var base = ground(g.player.pos.x, g.player.pos.z)
        var foeAt = ground(base.x + 3, base.z)
        for t in 0..<24 {
            let b = ground(g.player.pos.x + Float(t * 5), g.player.pos.z + 7)
            let f = ground(b.x + 3, b.z)
            if abs(f.y - b.y) < 0.5 && w.canSee(b + V3(0, 1.6, 0), f + V3(0, 1.6, 0)) { base = b; foeAt = f; break }
        }
        g.mobs.mobs.removeAll()
        let farmer = Mob(.villager, at: base); farmer.home = base
        var fv = VillagerData(); fv.profession = "farmer"; fv.locked = true; farmer.villager = fv
        Townsfolk.setup(farmer, game: g)
        let z = Mob(.zombie, at: foeAt)
        g.mobs.mobs = [farmer, z]
        g.player.pos = base + V3(0, 0, 30)
        let hp0 = z.health
        var hit = -1.0
        for i in 0..<240 {
            farmer.update(0.05, game: g)
            if hit < 0 && z.health < hp0 { hit = Double(i) * 0.05 }
            if z.health <= 0 { break }
        }
        check(hit >= 0 && z.health < hp0, String(format: "defence: an armed townsperson fights a zombie (first blow after %.1f s, zombie %d/%d)", hit, z.health, hp0))
        // An elder runs instead.
        let elder = Mob(.villager, at: base); elder.home = base
        var ev = VillagerData(); ev.role = "elder"; ev.person = "Edna Holloway"; ev.town = "Test"; elder.villager = ev
        let z2 = Mob(.zombie, at: foeAt)
        g.mobs.mobs = [elder, z2]
        g.mobs.rebuildIndex()
        for _ in 0..<100 { elder.update(0.05, game: g) }
        check(z2.health == z2.spec.health && simd_length(elder.pos - z2.pos) > 4.5, String(format: "defence: an elder doesn't fight, keeps away (%.1f blocks)", simd_length(elder.pos - z2.pos)))
        // Hurting a townsperson: the armed turn on you, the unarmed run.
        g.survival = true
        let deputy = Mob(.villager, at: base + V3(1, 0, 0)); deputy.home = deputy.pos; Townsfolk.setup(deputy, tag: "deputy", game: g)
        let kid = Mob(.villager, at: base + V3(-1, 0, 0)); kid.baby = true; kid.home = kid.pos; Townsfolk.setup(kid, game: g)
        let victim = Mob(.villager, at: base); victim.home = base; Townsfolk.setup(victim, game: g)
        g.mobs.mobs = [deputy, kid, victim]
        g.player.pos = base + V3(0, 0, 3)
        victim.provoke(g)
        check(deputy.town.anger > 0 && kid.panic > 0, String(format: "defence: hurting a townsperson angers the deputy (%.0f s) and the child runs (%.0f s)", deputy.town.anger, kid.panic))
        // Fighting back against the angry deputy is self-defence: five more blows cost no more standing.
        let rep0 = deputy.villager?.reputation ?? 0
        for _ in 0..<5 { deputy.provoke(g) }
        let rep1 = deputy.villager?.reputation ?? 0
        check(rep1 == rep0, "defence: hitting a townsperson who is already fighting you costs no more standing (\(rep0) -> \(rep1))")
        g.health = 20
        for _ in 0..<120 { deputy.update(0.05, game: g) }
        check(g.health < 20, "defence: the angry deputy hits the player (health \(g.health))")
        // A pointed gun: hands up.
        let p = Mob(.villager, at: base); p.home = base; Townsfolk.setup(p, game: g)
        g.mobs.mobs = [p]
        if Items.has("gun_sidearm") {
            g.inventory.held = ItemStack(Items.id("gun_sidearm"), 1)
            g.player.pos = base + V3(0, 0, 6)
            let d = p.eye - g.player.eye
            g.player.yaw = atan2f(-d.x, -d.z)
            g.player.pitch = asinf(d.y / simd_length(d))
            let menu = g.menu; g.menu = nil
            _ = p.townReact(0.05, g)
            g.menu = menu
            check(p.town.handsUp > 0, "defence: a pointed gun puts their hands up")
        }
    }

    // MARK: Generated towns

    static func towns(_ makeWorld: () -> World, _ check: (Bool, String) -> Void) {
        let w = makeWorld()
        w.renderDistance = 3
        guard let sc = w.gen.structures else { check(false, "towns: structures"); return }
        var shopsFound: [ShopKind: Int] = [:], deputies = 0, signs = 0, visited = 0, blocked: [String] = []
        var seen: [IVec3] = []
        for _ in 0..<3 {
            guard let s = sc.nearest("village", x: 0, z: 0, maxRegions: 12, accept: { st in !seen.contains { $0 == st.anchor } }) else { break }
            seen.append(s.anchor)
            w.pendingMobs.removeAll()
            _ = w.loadSync(center: V3(Float(s.anchor.x), 140, Float(s.anchor.z)), radius: 4)
            visited += 1
            for (name, p) in w.pendingMobs {
                if name == "villager:deputy" { deputies += 1 }
                // Everyone in town stands on a floor with room for their body (not on a shelf, not in iron bars).
                if name.hasPrefix("villager"), w.collides(p + V3(-0.3, 0.01, -0.3), p + V3(0.3, 1.95, 0.3))
                    || !w.collides(p + V3(-0.3, -0.2, -0.3), p + V3(0.3, -0.01, 0.3)) {
                    blocked.append("\(name) at \(Int(p.x)) \(Int(p.y)) \(Int(p.z))")
                }
                if name.hasPrefix("villager:shop_"), let k = ShopKind(rawValue: String(name.dropFirst(14))) { shopsFound[k, default: 0] += 1 }
            }
            for (p, be) in w.blockEntities where be.kind == .sign && abs(p.x - s.anchor.x) < 80 && abs(p.z - s.anchor.z) < 80 {
                if ShopKind.allCases.contains(where: { be.lines.contains($0.name) }) { signs += 1 }
            }
        }
        let all = ShopKind.allCases.filter { (shopsFound[$0] ?? 0) > 0 }
        check(visited >= 2 && all.count == ShopKind.allCases.count && (shopsFound[.general] ?? 0) >= visited - 1 && deputies >= visited - 1,
              "towns: \(visited) towns hold \(all.count)/8 kinds of shop (\(shopsFound.map { "\($0.key.rawValue) \($0.value)" }.sorted().joined(separator: ", "))), \(deputies) deputies")
        let keepers = shopsFound.values.reduce(0, +)
        check(signs >= keepers && keepers > 0, "towns: every shop has its sign (\(signs) signs, \(keepers) shops)")
        check(blocked.isEmpty, "towns: every townsperson and keeper spawns on a floor with head room" + (blocked.isEmpty ? "" : ": " + blocked.prefix(6).joined(separator: ", ")))
    }
}
