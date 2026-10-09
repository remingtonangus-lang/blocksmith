import Foundation
import simd

// Town shops and money. Every town has shops run by named shopkeepers (Townsfolk.swift): a general store, gunsmith,
// butcher, doctor, stable, tailor, blacksmith and saloon. Money is dollars and cents, kept in the player's wallet
// (Game.money, cents; saved in world.json extra["money"]). One value table prices everything: shopkeepers sell at the
// value and buy at half of it, both nudged by what the town thinks of the player (gossip reputation) and the Village
// Hero effect. The bounds of those nudges (minBuyMult, maxSellMult) are what TownTests checks every recipe against,
// so buying ingredients, crafting and selling the result never makes money from nothing.

enum Money {
    static let start = 500                        // $5.00 in a new (or pre-money) world

    static func format(_ cents: Int) -> String {
        let neg = cents < 0
        let c = abs(cents)
        let s = "$\(c / 100).\(c % 100 < 10 ? "0" : "")\(c % 100)"
        return neg ? "-" + s : s
    }
}

extension Game {
    // The wallet, in cents (stored in Game.townWallet, see Townsfolk.swift for the save hook).
    var money: Int {
        get { townWallet }
        set { townWallet = max(0, newValue) }
    }
}

// MARK: Shops

enum ShopKind: String, CaseIterable, Codable {
    case general, gunsmith, butcher, doctor, stable, tailor, blacksmith, saloon

    var name: String {
        switch self {
        case .general: return "General Store"
        case .gunsmith: return "Gunsmith"
        case .butcher: return "Butcher"
        case .doctor: return "Doctor"
        case .stable: return "Stable"
        case .tailor: return "Tailor"
        case .blacksmith: return "Blacksmith"
        case .saloon: return "Saloon"
        }
    }
    // What the keeper is called in speech ("the gunsmith").
    var keeper: String {
        switch self {
        case .general: return "storekeeper"
        case .doctor: return "doctor"
        case .stable: return "stablehand"
        case .saloon: return "barkeep"
        default: return name.lowercased()
        }
    }
    // Open hours as day fractions (0 sunrise, 0.25 noon, 0.5 sunset). The saloon stays open into the night.
    var hours: (Float, Float) { self == .saloon ? (0.08, 0.66) : (0.02, 0.47) }
}

// A paid service instead of an item (the doctor patching you up, a hot meal at the saloon).
enum ShopService: String, CaseIterable {
    case treatment, meal
    var name: String { self == .treatment ? "Patch Me Up" : "Hot Meal" }
    var icon: String { self == .treatment ? "potion_healing" : "rabbit_stew" }
    var detail: String { self == .treatment ? "Heals you fully" : "Fills you up" }
}

enum Economy {
    // Value in cents of one item. Shopkeepers sell at value x buyMult and buy at value x sellMult.
    static let value: [String: Int] = [
        // Crops and farm goods
        "wheat": 6, "wheat_seeds": 2, "carrot": 6, "potato": 6, "beetroot": 6, "beetroot_seeds": 2, "pumpkin": 25,
        "pumpkin_seeds": 3, "melon_slice": 4, "melon_seeds": 3, "sugar_cane": 5, "sugar": 6, "egg": 5, "sweet_berries": 4,
        "glow_berries": 6, "cocoa_beans": 8, "apple": 20, "hay_block": 70, "honeycomb": 25, "honey_bottle": 60,
        // Food
        "bread": 30, "baked_potato": 25, "cookie": 10, "pumpkin_pie": 70, "beetroot_soup": 50, "mushroom_stew": 50,
        "rabbit_stew": 90, "cooked_beef": 45, "cooked_porkchop": 45, "cooked_chicken": 35, "cooked_mutton": 40,
        "cooked_rabbit": 32, "cooked_cod": 28, "cooked_salmon": 33, "golden_carrot": 160, "golden_apple": 1300,
        "glistering_melon_slice": 160, "milk_bucket": 400, "dried_kelp": 3,
        // Butcher's goods
        "beef": 30, "porkchop": 30, "chicken": 22, "mutton": 26, "rabbit": 20, "cod": 18, "salmon": 22,
        "leather": 50, "rabbit_hide": 12, "feather": 5, "bone": 6, "rotten_flesh": 2,
        // Materials, ores and gems
        "stick": 1, "coal": 12, "charcoal": 10, "iron_nugget": 10, "iron_ingot": 100, "raw_iron": 60, "gold_nugget": 25,
        "gold_ingot": 250, "raw_gold": 160, "steel_ingot": 350, "raw_titanium": 900, "diamond": 1500, "emerald": 600,
        "lapis_lazuli": 40, "quartz": 30, "amethyst_shard": 20, "flint": 4, "string": 8, "gunpowder": 40, "slime_ball": 30,
        "ender_pearl": 250, "blaze_rod": 250, "blaze_powder": 125, "spider_eye": 12, "ghast_tear": 300, "rabbit_foot": 150,
        "glowstone_dust": 30, "nether_wart": 15, "phantom_membrane": 80, "paper": 4, "book": 25, "ink_sac": 8,
        "glass_bottle": 5,
        // Wool and cloth
        "white_wool": 30, "black_wool": 34, "gray_wool": 34, "brown_wool": 34, "red_wool": 34, "blue_wool": 34,
        "green_wool": 34, "yellow_wool": 34, "white_carpet": 22,
        "white_dye": 6, "black_dye": 6, "red_dye": 6, "blue_dye": 10, "yellow_dye": 6, "green_dye": 8, "brown_dye": 8,
        "leather_helmet": 300, "leather_chestplate": 470, "leather_leggings": 410, "leather_boots": 260,
        "white_bed": 130, "red_bed": 140,
        // General goods
        "torch": 4, "lantern": 110, "bucket": 330, "map": 520, "compass": 480, "clock": 1100, "shears": 220,
        "fishing_rod": 60, "lead": 60, "flint_and_steel": 120, "spyglass": 900, "name_tag": 800, "treasure_map": 2500,
        // Blacksmith
        "stone_sword": 20, "stone_pickaxe": 24, "stone_axe": 24, "stone_shovel": 12, "stone_hoe": 16,
        "iron_sword": 260, "iron_pickaxe": 360, "iron_axe": 360, "iron_shovel": 140, "iron_hoe": 240,
        "iron_helmet": 560, "iron_chestplate": 880, "iron_leggings": 780, "iron_boots": 450,
        "chainmail_helmet": 420, "chainmail_chestplate": 720, "chainmail_leggings": 620, "chainmail_boots": 360,
        "shield": 230, "iron_bars": 22, "anvil": 3600,
        // Gunsmith
        "gun_sidearm": 4500, "gun_shotgun": 8500, "gun_rifle": 14000, "gun_sniper": 22000,
        "rifle_rounds": 4, "shotgun_shells": 10, "heavy_rounds": 25, "bow": 120, "arrow": 4, "crossbow": 220,
        // Stable
        "saddle": 600, "leather_horse_armor": 320, "iron_horse_armor": 900, "golden_horse_armor": 1500,
        "carrot_on_a_stick": 70,
        // Doctor
        "potion_healing": 160, "potion_regeneration": 260, "potion_swiftness": 200, "potion_night_vision": 180,
        "splash_potion_healing": 230, "potion_fire_resistance": 220,
    ]
    // What one service costs (cents).
    static func price(_ s: ShopService, _ g: Game) -> Int {
        switch s {
        case .treatment: return 100 + 10 * max(0, 20 - g.health)       // $1 plus 10 cents a half-heart
        case .meal: return 120
        }
    }

    // Bounds of the reputation / hero price changes (Shop.buyMult / sellMult clamp to them; TownTests checks recipes).
    static let minBuyMult: Float = 0.85
    static let maxBuyMult: Float = 1.25
    static let minSellMult: Float = 0.375
    static let maxSellMult: Float = 0.55

    // Catalogue: (item, how many the shop has per day). Items the game doesn't have are skipped.
    static let stock: [ShopKind: [(String, Int)]] = [
        .general: [("bread", 16), ("apple", 16), ("baked_potato", 12), ("torch", 64), ("lantern", 4), ("bucket", 2),
                   ("glass_bottle", 16), ("map", 2), ("compass", 1), ("clock", 1), ("paper", 32), ("book", 8),
                   ("shears", 2), ("fishing_rod", 2), ("lead", 4), ("flint_and_steel", 2), ("wheat_seeds", 32),
                   ("beetroot_seeds", 16), ("carrot", 16), ("potato", 16), ("treasure_map", 1)],
        .gunsmith: [("gun_sidearm", 1), ("gun_shotgun", 1), ("gun_rifle", 1), ("gun_sniper", 1), ("rifle_rounds", 180),
                    ("shotgun_shells", 60), ("heavy_rounds", 32), ("bow", 2), ("arrow", 64), ("crossbow", 1), ("spyglass", 1)],
        .butcher: [("beef", 12), ("porkchop", 12), ("chicken", 12), ("mutton", 12), ("cooked_beef", 16), ("cooked_porkchop", 16),
                   ("cooked_chicken", 16), ("cooked_mutton", 16), ("cooked_rabbit", 8), ("rabbit_stew", 6), ("leather", 8)],
        .doctor: [("potion_healing", 4), ("splash_potion_healing", 2), ("potion_regeneration", 2), ("potion_swiftness", 2),
                  ("potion_night_vision", 2), ("potion_fire_resistance", 2), ("milk_bucket", 2), ("golden_apple", 1),
                  ("glistering_melon_slice", 4), ("honey_bottle", 6)],
        .stable: [("saddle", 1), ("lead", 4), ("hay_block", 16), ("leather_horse_armor", 1), ("iron_horse_armor", 1),
                  ("golden_horse_armor", 1), ("golden_carrot", 8), ("apple", 16), ("carrot_on_a_stick", 1)],
        .tailor: [("leather_helmet", 2), ("leather_chestplate", 2), ("leather_leggings", 2), ("leather_boots", 2),
                  ("white_wool", 16), ("black_wool", 8), ("gray_wool", 8), ("brown_wool", 8), ("red_wool", 8), ("blue_wool", 8),
                  ("white_carpet", 16), ("white_bed", 2), ("red_bed", 2), ("name_tag", 1)],
        .blacksmith: [("stone_sword", 4), ("stone_pickaxe", 4), ("stone_axe", 4), ("stone_shovel", 4), ("stone_hoe", 4),
                      ("iron_sword", 2), ("iron_pickaxe", 2), ("iron_axe", 2), ("iron_shovel", 2), ("iron_hoe", 1),
                      ("iron_helmet", 1), ("iron_chestplate", 1), ("iron_leggings", 1), ("iron_boots", 1),
                      ("chainmail_helmet", 1), ("chainmail_chestplate", 1), ("chainmail_leggings", 1), ("chainmail_boots", 1),
                      ("shield", 2), ("bucket", 2), ("iron_bars", 16), ("anvil", 1)],
        .saloon: [("beetroot_soup", 8), ("mushroom_stew", 8), ("rabbit_stew", 6), ("bread", 12), ("cooked_beef", 8),
                  ("pumpkin_pie", 6), ("cookie", 24), ("honey_bottle", 8), ("treasure_map", 1)],
    ]
    // What each shop buys from the player.
    static let buys: [ShopKind: [String]] = [
        .general: ["wheat", "carrot", "potato", "beetroot", "pumpkin", "melon_slice", "sugar_cane", "egg", "honeycomb",
                   "feather", "flint", "paper", "ink_sac", "bone", "string", "emerald", "diamond", "lapis_lazuli", "quartz",
                   "amethyst_shard", "cocoa_beans"],
        .gunsmith: ["gunpowder", "flint", "feather", "string", "iron_ingot", "steel_ingot", "coal", "gun_sidearm", "gun_shotgun",
                    "gun_rifle", "gun_sniper", "rifle_rounds", "shotgun_shells", "heavy_rounds"],
        .butcher: ["beef", "porkchop", "chicken", "mutton", "rabbit", "cod", "salmon", "leather", "rabbit_hide", "feather",
                   "bone", "rotten_flesh", "egg"],
        .doctor: ["spider_eye", "ghast_tear", "rabbit_foot", "glowstone_dust", "nether_wart", "sugar", "blaze_powder",
                  "blaze_rod", "honey_bottle", "phantom_membrane", "glass_bottle", "slime_ball"],
        .stable: ["wheat", "hay_block", "apple", "carrot", "golden_carrot", "leather", "saddle", "leather_horse_armor",
                  "iron_horse_armor", "golden_horse_armor"],
        .tailor: ["white_wool", "black_wool", "gray_wool", "brown_wool", "red_wool", "blue_wool", "green_wool", "yellow_wool",
                  "leather", "rabbit_hide", "string", "feather", "white_dye", "black_dye", "red_dye", "blue_dye",
                  "yellow_dye", "green_dye", "brown_dye", "ink_sac"],
        .blacksmith: ["coal", "charcoal", "iron_nugget", "iron_ingot", "raw_iron", "gold_nugget", "gold_ingot", "raw_gold",
                      "steel_ingot", "raw_titanium", "diamond", "iron_sword", "iron_pickaxe", "iron_axe", "iron_shovel",
                      "iron_helmet", "iron_chestplate", "iron_leggings", "iron_boots"],
        .saloon: ["sweet_berries", "glow_berries", "cocoa_beans", "sugar", "honey_bottle", "wheat", "potato", "melon_slice",
                  "pumpkin", "cod", "salmon"],
    ]
    static let services: [ShopKind: [ShopService]] = [.doctor: [.treatment], .saloon: [.meal]]

    static func value(of item: ItemID) -> Int? { value[Items.key(item)] }

    // The catalogue with items this build has (index = position in VillagerData.stock).
    static func catalog(_ k: ShopKind) -> [(item: ItemID, perDay: Int)] {
        (stock[k] ?? []).compactMap { Items.has($0.0) && value[$0.0] != nil ? (Items.id($0.0), $0.1) : nil }
    }
    static func buysItem(_ k: ShopKind, _ item: ItemID) -> Bool {
        guard value(of: item) != nil else { return false }
        return buys[k]?.contains(Items.key(item)) ?? false
    }
}

// MARK: Prices for one shopkeeper

struct ShopPricing {
    var buyMult: Float, sellMult: Float, refuses: Bool

    // Reputation 100 or more: 10% off and 10% more for what you sell; down to -100: 25% dearer and 25% less paid;
    // below -100 the shop won't serve you. Friend of the Town (heroOfTheVillage) takes another 5% off (never past minBuyMult).
    init(reputation rep: Int, hero: Int) {
        let r = Float(max(-100, min(100, rep))) / 100
        var b: Float = r >= 0 ? 1 - 0.1 * r : 1 - 0.25 * r
        var s: Float = r >= 0 ? 0.5 * (1 + 0.1 * r) : 0.5 * (1 + 0.25 * r)
        if hero > 0 { b -= 0.05 }
        b = max(Economy.minBuyMult, min(Economy.maxBuyMult, b))
        s = max(Economy.minSellMult, min(Economy.maxSellMult, s))
        buyMult = b; sellMult = s; refuses = rep < -100
    }
    func buy(_ value: Int) -> Int { max(1, Int((Float(value) * buyMult).rounded())) }
    func sell(_ value: Int) -> Int { max(0, Int((Float(value) * sellMult).rounded(.down))) }
}

extension VillagerData {
    var shopKind: ShopKind? { shop.flatMap { ShopKind(rawValue: $0) } }

    // Fresh stock once a day (at the first look after midnight of a new day).
    mutating func restockShop(day: Int) {
        guard let k = shopKind else { return }
        let cat = Economy.catalog(k)
        if stockDay != day || (stock?.count ?? -1) != cat.count {
            stock = cat.map { $0.perDay }
            stockDay = day
        }
    }
}

// MARK: Shop screen

// A shop counter readable in VR: big rows (icon, name, stock line, price), Buy / Sell tabs, a quantity toggle,
// the wallet up top and a status line at the bottom. Every control is a button slot, so the mouse, the controller
// cursor and the Touch laser all work the same way. No player inventory grid: the sell tab lists what you carry
// that this shop buys.
final class ShopMenu: Menu, CustomDrawnMenu {
    weak var mob: Mob?
    let kind: ShopKind
    var selling = false
    var scroll = 0
    var qtyIndex = 0
    var status = ""
    var statusGood = true
    static let quantities = [1, 5, 0]                  // 0 = all / as many as stocked
    static let visible = 6
    static let rowY = 48, rowH = 22, rowX = 8, rowW = 252
    static let tabBuy = 10, tabSell = 11, qtyButton = 12, scrollUp = 13, scrollDown = 14
    // Name column width (GUI px): TownTests checks every catalogue name fits.
    static var nameWidth: Int { rowW - 24 - 52 }

    enum Row { case item(Int), service(ShopService), sell(ItemID) }

    init(game: Game, keeper: Mob, kind: ShopKind) {
        mob = keeper
        self.kind = kind
        let who = keeper.villager?.person.flatMap { $0.split(separator: " ").last }.map { "\($0)'s " } ?? ""
        super.init(who.isEmpty ? kind.name : who + kind.name, game: game)
        showInventoryLabel = false
        width = 284; height = 198
        for i in 0..<ShopMenu.visible {
            let b = MenuSlot(ShopMenu.rowX, ShopMenu.rowY + ShopMenu.rowH * i, nil, 0, .button(i))
            b.w = ShopMenu.rowW; b.h = ShopMenu.rowH - 2
            slots.append(b)
        }
        func button(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ id: Int) {
            let b = MenuSlot(x, y, nil, 0, .button(id)); b.w = w; b.h = h; slots.append(b)
        }
        button(8, 26, 62, 16, ShopMenu.tabBuy)
        button(74, 26, 62, 16, ShopMenu.tabSell)
        button(196, 26, 64, 16, ShopMenu.qtyButton)
        button(264, ShopMenu.rowY, 14, 40, ShopMenu.scrollUp)
        button(264, ShopMenu.rowY + ShopMenu.rowH * ShopMenu.visible - 42, 14, 40, ShopMenu.scrollDown)
        refresh()
        status = keeper.villager.map { Townsfolk.shopGreeting($0, game) } ?? ""
    }

    var data: VillagerData? { mob?.villager }
    var pricing: ShopPricing {
        ShopPricing(reputation: data?.reputation ?? 0, hero: game.effects.level(.heroOfTheVillage))
    }

    func refresh() {
        guard let m = mob, var v = m.villager else { return }
        v.restockShop(day: Int(game.time / DAY_LENGTH))
        m.villager = v
    }

    var rows: [Row] {
        if selling {
            var seen = Set<ItemID>(), out: [Row] = []
            for j in 0..<36 {
                let s = game.inventory.main[j]
                guard !s.isEmpty, Shop.sellable(s), Economy.buysItem(kind, s.item), !seen.contains(s.item) else { continue }
                seen.insert(s.item); out.append(.sell(s.item))
            }
            return out
        }
        return (Economy.services[kind] ?? []).map { Row.service($0) } + Economy.catalog(kind).indices.map { Row.item($0) }
    }

    func have(_ item: ItemID) -> Int {
        var n = 0
        for j in 0..<36 where game.inventory.main[j].item == item && Shop.sellable(game.inventory.main[j]) { n += game.inventory.main[j].count }
        return n
    }

    // Name, detail line, price text and whether the row can be used right now.
    func describe(_ r: Row) -> (ItemStack, String, String, String, Bool) {
        let p = pricing
        switch r {
        case .item(let i):
            let c = Economy.catalog(kind)[i]
            let left = data?.stock?[safe: i] ?? 0
            let price = p.buy(Economy.value(of: c.item) ?? 0)
            let st = ItemStack(c.item, 1)
            return (st, st.def.display, left > 0 ? "\(left) in stock" : "Sold out today", Money.format(price), left > 0 && game.money >= price)
        case .service(let s):
            let price = Economy.price(s, game)
            let need = s == .treatment ? game.health < 20 : game.hunger < 20
            let st = Items.has(s.icon) ? ItemStack(Items.id(s.icon), 1) : .empty
            return (st, s.name, need ? s.detail : (s == .treatment ? "You're in good health" : "You're not hungry"),
                    Money.format(price), need && game.money >= price)
        case .sell(let it):
            let st = ItemStack(it, 1)
            let n = have(it)
            return (st, st.def.display, "You have \(n)", Money.format(p.sell(Economy.value(of: it) ?? 0)), n > 0)
        }
    }

    override func buttonPressed(_ i: Int) {
        switch i {
        case ShopMenu.tabBuy: if selling { selling = false; scroll = 0; game.sfx(.click, 0.4) }
        case ShopMenu.tabSell: if !selling { selling = true; scroll = 0; game.sfx(.click, 0.4) }
        case ShopMenu.qtyButton: qtyIndex = (qtyIndex + 1) % ShopMenu.quantities.count; game.sfx(.click, 0.4)
        case ShopMenu.scrollUp: scrollBy(-1)
        case ShopMenu.scrollDown: scrollBy(1)
        default:
            let rs = rows
            guard i >= 0 && i < ShopMenu.visible, scroll + i < rs.count else { return }
            use(rs[scroll + i])
        }
    }

    func scrollBy(_ d: Int) {
        let n = max(0, rows.count - ShopMenu.visible)
        let s = max(0, min(n, scroll + d))
        if s != scroll { scroll = s; game.sfx(.click, 0.3) }
    }

    func say(_ s: String, good: Bool) { status = s; statusGood = good }

    func use(_ r: Row) {
        guard let m = mob, m.health > 0 else { say("Nobody is minding the counter.", good: false); return }
        let p = pricing
        if p.refuses { say("\(data?.person ?? "The keeper") won't serve you.", good: false); game.sfx(.villagerNo, 0.7, at: m.pos); return }
        let want = ShopMenu.quantities[qtyIndex]
        switch r {
        case .item(let i):
            let r = Shop.buy(game, m, kind, index: i, count: want == 0 ? 64 : want)
            say(r.0, good: r.1)
        case .service(let s):
            let r = Shop.service(game, m, s)
            say(r.0, good: r.1)
        case .sell(let it):
            let r = Shop.sell(game, m, kind, item: it, count: want == 0 ? Int.max : want)
            say(r.0, good: r.1)
            scroll = max(0, min(scroll, rows.count - ShopMenu.visible))
        }
    }

    // LB / RB switch Buy / Sell, the right stick or the wheel scrolls, and pushing the cursor past the last row
    // scrolls too (MenuInput). The shop closes if its keeper falls or you walk off.
    override func tick() {
        if let m = mob, m.health <= 0 || simd_length(m.pos - game.player.pos) > 10 { game.closeMenu() }
    }

    func drawLines(_ L: HudLayout, _ o: V2) -> [HudLine] {
        let s = L.s
        var out: [HudLine] = []
        let dark = V4(0.18, 0.16, 0.14, 1), mid = V4(0.36, 0.33, 0.3, 1)
        func at(_ x: Int, _ y: Int) -> (Float, Float) { (o.x + Float(x) * s, o.y + Float(y) * s) }
        func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: V4) {
            let (px, py) = at(x, y)
            out.append(HudLine(text: "", x: px, y: py, scale: s, bg: c, box: V2(Float(w) * s, Float(h) * s)))
        }
        func label(_ t: String, _ x: Int, _ y: Int, _ c: V4) {
            let (px, py) = at(x, y)
            out.append(HudLine(text: t, x: px, y: py, scale: s, color: c))
        }
        func right(_ t: String, _ x: Int, _ y: Int, _ c: V4) { label(t, x - Font.width(t), y, c) }
        // Who and where, and the wallet.
        if let v = data {
            let line = [v.person, v.town].compactMap { $0 }.joined(separator: " of ")
            label(ShopMenu.fit(line, width - 16), 8, 15, mid)
        }
        right("Wallet " + Money.format(game.money), width - 8, 6, V4(0.1, 0.38, 0.12, 1))
        // Tabs and quantity.
        let hover = game.menuHover
        func button(_ id: Int, _ t: String, on: Bool) {
            guard let sl = slots.first(where: { if case .button(let b) = $0.kind { return b == id }; return false }) else { return }
            let hot = hover === sl
            box(sl.x, sl.y, sl.w, sl.h, V4(0.2, 0.2, 0.2, 1))
            box(sl.x + 1, sl.y + 1, sl.w - 2, sl.h - 2, on ? V4(0.93, 0.88, 0.74, 1) : (hot ? V4(0.75, 0.72, 0.66, 1) : V4(0.6, 0.58, 0.54, 1)))
            label(t, sl.x + (sl.w - Font.width(t)) / 2, sl.y + (sl.h - 7) / 2, dark)
            if hot && Prompt.pad { box(sl.x - 1, sl.y - 1, sl.w + 2, 1, V4(1, 0.85, 0.2, 1)); box(sl.x - 1, sl.y + sl.h, sl.w + 2, 1, V4(1, 0.85, 0.2, 1)) }
        }
        button(ShopMenu.tabBuy, "Buy", on: !selling)
        button(ShopMenu.tabSell, "Sell", on: selling)
        let q = ShopMenu.quantities[qtyIndex]
        button(ShopMenu.qtyButton, q == 0 ? (selling ? "Qty: All" : "Qty: Max") : "Qty: x\(q)", on: false)
        // Rows.
        let rs = rows
        if rs.isEmpty {
            label(selling ? "You have nothing this shop buys." : "Nothing for sale.", 16, ShopMenu.rowY + 8, mid)
        }
        for i in 0..<ShopMenu.visible {
            let idx = scroll + i
            guard idx < rs.count else { break }
            let (st, name, detail, price, ok) = describe(rs[idx])
            let x = ShopMenu.rowX, y = ShopMenu.rowY + ShopMenu.rowH * i
            let hot = hover === slots[i]
            box(x, y, ShopMenu.rowW, ShopMenu.rowH - 2, V4(0.22, 0.2, 0.18, 1))
            box(x + 1, y + 1, ShopMenu.rowW - 2, ShopMenu.rowH - 4, hot ? V4(0.86, 0.82, 0.72, 1) : V4(0.7, 0.67, 0.6, 1))
            if !st.isEmpty { let (px, py) = at(x + 3, y + 2); out.append(HudLine(text: "", x: px, y: py, scale: s, item: st)) }
            label(name, x + 24, y + 2, ok ? dark : V4(0.32, 0.3, 0.28, 1))
            label(detail, x + 24, y + 11, mid)
            right(price, x + ShopMenu.rowW - 5, y + 6, ok ? V4(0.08, 0.34, 0.1, 1) : V4(0.55, 0.16, 0.12, 1))
            if hot && Prompt.pad { box(x - 1, y - 1, ShopMenu.rowW + 2, 1, V4(1, 0.85, 0.2, 1)); box(x - 1, y + ShopMenu.rowH - 2, ShopMenu.rowW + 2, 1, V4(1, 0.85, 0.2, 1)) }
        }
        // Scroll buttons with a position bar between them.
        for (id, t) in [(ShopMenu.scrollUp, "^"), (ShopMenu.scrollDown, "v")] {
            guard let sl = slots.first(where: { if case .button(let b) = $0.kind { return b == id }; return false }) else { continue }
            let can = id == ShopMenu.scrollUp ? scroll > 0 : scroll + ShopMenu.visible < rs.count
            box(sl.x, sl.y, sl.w, sl.h, hover === sl ? V4(0.75, 0.72, 0.66, 1) : V4(0.5, 0.48, 0.45, 1))
            label(t, sl.x + (sl.w - Font.width(t)) / 2, sl.y + sl.h / 2 - 3, can ? dark : V4(0.4, 0.38, 0.36, 1))
        }
        if rs.count > ShopMenu.visible {
            let top = ShopMenu.rowY + 42, span = ShopMenu.rowH * ShopMenu.visible - 84
            let h = max(6, span * ShopMenu.visible / rs.count)
            let y = top + (span - h) * scroll / max(1, rs.count - ShopMenu.visible)
            box(266, top, 10, span, V4(0.3, 0.28, 0.26, 1))
            box(267, y, 8, h, V4(0.85, 0.8, 0.7, 1))
        }
        if !status.isEmpty { label(ShopMenu.fit(status, width - 16), 8, height - 13, statusGood ? V4(0.1, 0.3, 0.12, 1) : V4(0.55, 0.14, 0.1, 1)) }
        return out
    }

    // Cuts text to a pixel width with an ellipsis (names and messages never run off the panel).
    static func fit(_ t: String, _ px: Int) -> String {
        guard Font.width(t) > px else { return t }
        var s = t
        while !s.isEmpty && Font.width(s + "...") > px { s.removeLast() }
        return s + "..."
    }

    var legend: String {
        if Prompt.pad { return Prompt.line([(.select, selling ? "Sell" : "Buy"), (.tabs, "Buy / Sell"), (.scroll, "Scroll"), (.back, "Leave")]) }
        return Glyph.mouseL.s + (selling ? " Sell" : " Buy") + "   Wheel Scroll   " + Glyphs.key("Esc") + " Leave"
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}

// MARK: Transactions (shared by the screen, the bots and TownTests)

enum Shop {
    // Plain stacks only: no enchantments, no wear, no custom name, nothing inside.
    static func sellable(_ s: ItemStack) -> Bool { s.ench == 0 && s.damage == 0 && s.label == nil && s.contents == nil }

    static func buy(_ g: Game, _ m: Mob, _ k: ShopKind, index i: Int, count want: Int) -> (String, Bool) {
        guard var v = m.villager else { return ("", false) }
        v.restockShop(day: Int(g.time / DAY_LENGTH))
        let cat = Economy.catalog(k)
        guard i < cat.count, var stock = v.stock, i < stock.count else { return ("", false) }
        let item = cat[i].item
        let price = ShopPricing(reputation: v.reputation, hero: g.effects.level(.heroOfTheVillage)).buy(Economy.value(of: item) ?? 0)
        let name = ItemStack(item, 1).def.display
        guard stock[i] > 0 else { m.villager = v; return ("Sold out of \(name) until tomorrow.", false) }
        let afford = price > 0 ? g.money / price : Int.max
        let n = min(want, stock[i], afford)
        guard n > 0 else {
            m.villager = v
            g.sfx(.villagerNo, 0.6, at: m.pos + V3(0, 1.6, 0))
            return ("That's \(Money.format(price)) each. You have \(Money.format(g.money)).", false)
        }
        var left = n
        while left > 0 {
            let part = min(left, ItemStack(item, 1).maxStack)
            let rest = g.inventory.add(ItemStack(item, part))
            if !rest.isEmpty { g.dropItem(rest) }
            left -= part
        }
        g.money -= price * n
        stock[i] -= n
        v.stock = stock
        v.addGossip(.trading, 1)
        m.villager = v
        g.achieve("trade")
        g.sfx(.villagerTrade, 0.7, at: m.pos + V3(0, 1.6, 0))
        return ("Bought \(n) \(name) for \(Money.format(price * n)).", true)
    }

    static func sell(_ g: Game, _ m: Mob, _ k: ShopKind, item: ItemID, count want: Int) -> (String, Bool) {
        guard var v = m.villager, Economy.buysItem(k, item), let value = Economy.value(of: item) else { return ("", false) }
        var have = 0
        for j in 0..<36 where g.inventory.main[j].item == item && sellable(g.inventory.main[j]) { have += g.inventory.main[j].count }
        let n = min(want, have)
        let name = ItemStack(item, 1).def.display
        guard n > 0 else { return ("You have no \(name).", false) }
        let each = ShopPricing(reputation: v.reputation, hero: g.effects.level(.heroOfTheVillage)).sell(value)
        var left = n
        for j in 0..<36 where left > 0 {
            var s = g.inventory.main[j]
            guard s.item == item && sellable(s) else { continue }
            let t = min(left, s.count)
            s.count -= t; left -= t
            g.inventory.main[j] = s.count > 0 ? s : .empty
        }
        g.money += each * n
        v.addGossip(.trading, 1)
        m.villager = v
        g.sfx(.villagerTrade, 0.7, at: m.pos + V3(0, 1.6, 0))
        return ("Sold \(n) \(name) for \(Money.format(each * n)).", true)
    }

    static func service(_ g: Game, _ m: Mob, _ s: ShopService) -> (String, Bool) {
        let price = Economy.price(s, g)
        switch s {
        case .treatment where g.health >= 20: return ("You look healthy to me.", false)
        case .meal where g.hunger >= 20: return ("You don't look hungry.", false)
        default: break
        }
        guard g.money >= price else { return ("That's \(Money.format(price)). You have \(Money.format(g.money)).", false) }
        g.money -= price
        if s == .treatment {
            g.health = 20
            g.effects.remove(.poison)
            g.sfx(.drink, 0.7)
        } else {
            g.hunger = 20
            g.saturation = min(20, g.saturation + 8)
            g.sfx(.eat, 0.7)
        }
        if var v = m.villager { v.addGossip(.trading, 1); m.villager = v }
        return (s == .treatment ? "Patched up for \(Money.format(price))." : "A hot meal for \(Money.format(price)).", true)
    }
}
