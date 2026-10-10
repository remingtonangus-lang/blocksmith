import Foundation
import simd

// Villagers: professions from job-site blocks, five levels, the reference trade tables, demand-based
// prices, restocking at the job site, Village Hero discounts, zombie-villager curing.

struct TradeOffer: Codable {
    var buyA: ItemStack
    var buyB: ItemStack
    var sell: ItemStack
    var uses = 0
    var maxUses: Int
    var xp: Int
    var priceMult: Float
    var demand = 0
    var special = 0            // temporary price change (cured-zombie / hero discounts, negative = cheaper)

    // Emerald cost after demand and discounts (reference formula).
    var costA: ItemStack {
        var a = buyA
        let base = a.count
        let d = max(0, Int(floor(Float(base * demand) * priceMult)))
        a.count = max(1, min(a.maxStack, base + d + special))
        return a
    }
    var disabled: Bool { uses >= maxUses }
}

struct VillagerData: Codable {
    var profession: String = "none"      // none, nitwit, farmer, ...
    var level = 1
    var xp = 0
    var type = "plains"                  // biome style (robe colour)
    var offers: [TradeOffer] = []
    var jobSite: [Int]? = nil
    var restocksToday = 0
    var lastRestockDay = -1
    var locked = false                   // traded with: keeps its profession
    var cured = false                    // once a zombie villager: permanent discount
    var levelUpTimer: Float = 0
    var bed: [Int]? = nil                // claimed bed head
    var food: Int? = nil                 // food points (breeding needs 12)
    var gossip: [Int]? = nil             // what it has heard about the player: see Gossip (VillageLife.swift)
    var gossipDay: Int? = nil            // last day gossip decayed
}

enum Villagers {
    // Per block state: the profession whose job site it is (dictionary lookups on the block key ran per scanned cell).
    static let jobSiteOf: [String?] = (0..<Blocks.count).map { $0 == Int(AIR) ? nil : jobSites[Blocks.key(Blocks.groupBase[$0])] }
    static let jobSites: [String: String] = [
        "blast_furnace": "armorer", "smoker": "butcher", "cartography_table": "cartographer", "brewing_stand": "cleric",
        "composter": "farmer", "barrel": "fisherman", "fletching_table": "fletcher", "cauldron": "leatherworker",
        "lectern": "librarian", "stonecutter": "mason", "loom": "shepherd", "smithing_table": "toolsmith", "grindstone": "weaponsmith",
    ]
    static let levelXP = [0, 10, 70, 150, 250]
    static let levelNames = ["Novice", "Apprentice", "Journeyman", "Expert", "Master"]

    // A trade template. sell/buy item names may carry a suffix:
    //   "@ench"  enchanted with 5-19 levels (price +level)      "@book"  librarian enchanted book
    //   "@dye"   random dye colour of a leather item          "@tipped" random tipped arrow
    struct T {
        var buy: String, buyN: Int
        var buyB: String? = nil, buyBN = 0
        var sell: String, sellN: Int
        var uses: Int, xp: Int, mult: Float = 0.05
    }
    static func emeraldFor(_ i: String, _ n: Int, _ uses: Int, _ xp: Int) -> T { T(buy: i, buyN: n, sell: "emerald", sellN: 1, uses: uses, xp: xp) }
    static func forEmeralds(_ i: String, _ cost: Int, _ n: Int, _ uses: Int, _ xp: Int, _ m: Float = 0.05) -> T {
        T(buy: "emerald", buyN: cost, sell: i, sellN: n, uses: uses, xp: xp, mult: m)
    }
    static func swap(_ a: String, _ an: Int, _ cost: Int, _ s: String, _ sn: Int, _ uses: Int, _ xp: Int) -> T {
        T(buy: a, buyN: an, buyB: "emerald", buyBN: cost, sell: s, sellN: sn, uses: uses, xp: xp)
    }
    static func ench(_ i: String, _ base: Int, _ uses: Int, _ xp: Int, _ m: Float = 0.05) -> T {
        T(buy: "emerald", buyN: base, sell: i + "@ench", sellN: 1, uses: uses, xp: xp, mult: m)
    }
    // Enchanted-book offers give the villager 1 / 5 / 10 / 15 experience by level (0: book-only librarians never levelled).
    static func book(_ xp: Int) -> T { T(buy: "emerald", buyN: 0, buyB: "book", buyBN: 1, sell: "enchanted_book@book", sellN: 1, uses: 12, xp: xp, mult: 0.2) }

    static let colorsL1 = ["white", "gray", "black", "light_blue", "lime"]
    static let colorsL2 = ["yellow", "light_gray", "orange", "red", "pink"]
    static let colorsL3 = ["brown", "purple", "blue", "green", "magenta", "cyan"]

    // Level -> trade pool (two random offers are picked per level; masters get one... all as in the reference).
    static let trades: [String: [[T]]] = [
        "farmer": [
            [emeraldFor("wheat", 20, 16, 2), emeraldFor("potato", 26, 16, 2), emeraldFor("carrot", 22, 16, 2), emeraldFor("beetroot", 15, 16, 2),
             forEmeralds("bread", 1, 6, 16, 1)],
            [emeraldFor("pumpkin", 6, 12, 10), forEmeralds("pumpkin_pie", 1, 4, 12, 5), forEmeralds("apple", 1, 4, 16, 5)],
            [forEmeralds("cookie", 3, 18, 12, 10), emeraldFor("melon", 4, 12, 20)],
            [forEmeralds("cake", 1, 1, 12, 15), forEmeralds("suspicious_stew_poppy", 1, 1, 12, 15), forEmeralds("suspicious_stew_dandelion", 1, 1, 12, 15),
             forEmeralds("suspicious_stew_oxeye_daisy", 1, 1, 12, 15), forEmeralds("suspicious_stew_cornflower", 1, 1, 12, 15)],
            [forEmeralds("golden_carrot", 3, 3, 12, 30), forEmeralds("glistering_melon_slice", 4, 3, 12, 30)],
        ],
        "fisherman": [
            [emeraldFor("string", 20, 16, 2), emeraldFor("coal", 10, 16, 2), swap("cod", 6, 1, "cooked_cod", 6, 16, 1), forEmeralds("cod_bucket", 3, 1, 16, 1)],
            [emeraldFor("cod", 15, 16, 10), swap("salmon", 6, 1, "cooked_salmon", 6, 16, 5), forEmeralds("campfire", 2, 1, 12, 5)],
            [emeraldFor("salmon", 13, 16, 20), ench("fishing_rod", 3, 3, 10, 0.2)],
            [emeraldFor("tropical_fish", 6, 12, 30)],
            [emeraldFor("pufferfish", 4, 12, 30), emeraldFor("oak_boat", 1, 12, 30)],
        ],
        "shepherd": [
            [emeraldFor("white_wool", 18, 16, 2), emeraldFor("brown_wool", 18, 16, 2), emeraldFor("black_wool", 18, 16, 2),
             emeraldFor("gray_wool", 18, 16, 2), forEmeralds("shears", 2, 1, 12, 1)],
            colorsL1.map { emeraldFor("\($0)_dye", 12, 16, 10) } + BlockRegistry.colors.map { forEmeralds("\($0.0)_wool", 1, 1, 16, 5) }
                + BlockRegistry.colors.map { forEmeralds("\($0.0)_carpet", 1, 4, 16, 5) },
            colorsL2.map { emeraldFor("\($0)_dye", 12, 16, 20) } + BlockRegistry.colors.map { forEmeralds("\($0.0)_bed", 3, 1, 12, 10) },
            colorsL3.map { emeraldFor("\($0)_dye", 12, 16, 30) } + BlockRegistry.colors.map { forEmeralds("\($0.0)_banner", 3, 1, 12, 15) },
            [forEmeralds("painting", 2, 3, 12, 30)],
        ],
        "fletcher": [
            [emeraldFor("stick", 32, 16, 2), forEmeralds("arrow", 1, 16, 12, 1), swap("gravel", 10, 1, "flint", 10, 12, 1)],
            [emeraldFor("flint", 26, 12, 10), forEmeralds("bow", 2, 1, 12, 5)],
            [emeraldFor("string", 14, 16, 20), forEmeralds("crossbow", 3, 1, 12, 10)],
            [emeraldFor("feather", 24, 16, 30), ench("bow", 2, 3, 15)],
            [emeraldFor("tripwire_hook", 8, 12, 30), ench("crossbow", 3, 3, 15),
             T(buy: "arrow", buyN: 5, buyB: "emerald", buyBN: 2, sell: "tipped_arrow@tipped", sellN: 5, uses: 12, xp: 30)],
        ],
        "librarian": [
            [emeraldFor("paper", 24, 16, 2), book(1), forEmeralds("bookshelf", 9, 1, 12, 1)],
            [emeraldFor("book", 4, 12, 10), book(5), forEmeralds("lantern", 1, 1, 12, 5)],
            [emeraldFor("ink_sac", 5, 12, 20), book(10), forEmeralds("glass", 1, 4, 12, 10)],
            [emeraldFor("writable_book", 2, 12, 30), book(15), forEmeralds("clock", 5, 1, 12, 15), forEmeralds("compass", 4, 1, 12, 15)],
            [forEmeralds("name_tag", 20, 1, 12, 30)],
        ],
        "cartographer": [
            [emeraldFor("paper", 24, 16, 2), forEmeralds("map", 7, 1, 12, 1)],
            [emeraldFor("glass_pane", 11, 16, 10), swap("compass", 1, 13, "sea_temple_explorer_map", 1, 12, 5)],
            [emeraldFor("compass", 1, 12, 20), swap("compass", 1, 14, "manor_explorer_map", 1, 12, 10)],
            [forEmeralds("item_frame", 7, 1, 12, 15)] + BlockRegistry.colors.map { forEmeralds("\($0.0)_banner", 3, 1, 12, 15) },
            [forEmeralds("globe_banner_pattern", 8, 1, 12, 30), swap("compass", 1, 24, "steelhold_explorer_map", 1, 6, 30)],
        ],
        "cleric": [
            [emeraldFor("rotten_flesh", 32, 16, 2), forEmeralds("redstone", 1, 2, 12, 1)],
            [emeraldFor("gold_ingot", 3, 12, 10), forEmeralds("lapis_lazuli", 1, 1, 12, 5)],
            [emeraldFor("rabbit_foot", 2, 12, 20), forEmeralds("glowstone", 4, 1, 12, 10)],
            [emeraldFor("turtle_scute", 4, 12, 30), emeraldFor("glass_bottle", 9, 12, 30), forEmeralds("ender_pearl", 5, 1, 12, 15)],
            [emeraldFor("nether_wart", 22, 12, 30), forEmeralds("experience_bottle", 3, 1, 12, 30)],
        ],
        "armorer": [
            [emeraldFor("coal", 15, 16, 2), forEmeralds("iron_leggings", 7, 1, 12, 1, 0.2), forEmeralds("iron_boots", 4, 1, 12, 1, 0.2),
             forEmeralds("iron_helmet", 5, 1, 12, 1, 0.2), forEmeralds("iron_chestplate", 9, 1, 12, 1, 0.2)],
            [emeraldFor("iron_ingot", 4, 12, 10), forEmeralds("bell", 36, 1, 12, 5, 0.2), forEmeralds("chainmail_boots", 1, 1, 12, 5, 0.2),
             forEmeralds("chainmail_leggings", 3, 1, 12, 5, 0.2)],
            [emeraldFor("lava_bucket", 1, 12, 20), emeraldFor("diamond", 1, 12, 20), forEmeralds("chainmail_helmet", 1, 1, 12, 10, 0.2),
             forEmeralds("chainmail_chestplate", 4, 1, 12, 10, 0.2), forEmeralds("shield", 5, 1, 12, 10, 0.2)],
            [ench("diamond_leggings", 14, 3, 15, 0.2), ench("diamond_boots", 8, 3, 15, 0.2)],
            [ench("diamond_helmet", 8, 3, 30, 0.2), ench("diamond_chestplate", 16, 3, 30, 0.2)],
        ],
        "butcher": [
            [emeraldFor("chicken", 14, 16, 2), emeraldFor("porkchop", 7, 16, 2), emeraldFor("rabbit", 4, 16, 2), forEmeralds("rabbit_stew", 1, 1, 12, 1)],
            [emeraldFor("coal", 15, 16, 10), forEmeralds("cooked_porkchop", 1, 5, 16, 5), forEmeralds("cooked_chicken", 1, 8, 16, 5)],
            [emeraldFor("mutton", 7, 16, 20), emeraldFor("beef", 10, 16, 20)],
            [emeraldFor("dried_kelp_block", 10, 12, 30)],
            [emeraldFor("sweet_berries", 10, 12, 30)],
        ],
        "leatherworker": [
            [emeraldFor("leather", 6, 16, 2), forEmeralds("leather_leggings@dye", 3, 1, 12, 1), forEmeralds("leather_chestplate@dye", 7, 1, 12, 1)],
            [emeraldFor("flint", 26, 12, 10), forEmeralds("leather_helmet@dye", 5, 1, 12, 5), forEmeralds("leather_boots@dye", 4, 1, 12, 5)],
            [emeraldFor("rabbit_hide", 9, 12, 20), forEmeralds("leather_chestplate@dye", 7, 1, 12, 10)],
            [emeraldFor("turtle_scute", 4, 12, 30), forEmeralds("leather_horse_armor", 6, 1, 12, 15)],
            [forEmeralds("saddle", 6, 1, 12, 30, 0.2), forEmeralds("leather_helmet@dye", 5, 1, 12, 30)],
        ],
        "mason": [
            [emeraldFor("clay_ball", 10, 16, 2), forEmeralds("brick", 1, 10, 16, 1)],
            [emeraldFor("stone", 20, 16, 10), forEmeralds("chiseled_stone_bricks", 1, 4, 16, 5)],
            [emeraldFor("granite", 16, 16, 20), emeraldFor("andesite", 16, 16, 20), emeraldFor("diorite", 16, 16, 20),
             forEmeralds("dripstone_block", 1, 4, 16, 10), forEmeralds("polished_andesite", 1, 4, 16, 10),
             forEmeralds("polished_diorite", 1, 4, 16, 10), forEmeralds("polished_granite", 1, 4, 16, 10)],
            [emeraldFor("quartz", 12, 12, 30)] + BlockRegistry.colors.map { forEmeralds("\($0.0)_terracotta", 1, 1, 12, 15) }
                + BlockRegistry.colors.map { forEmeralds("\($0.0)_glazed_terracotta", 1, 1, 12, 15) },
            [forEmeralds("quartz_pillar", 1, 1, 12, 30), forEmeralds("quartz_block", 1, 1, 12, 30)],
        ],
        "toolsmith": [
            [emeraldFor("coal", 15, 16, 2), forEmeralds("stone_axe", 1, 1, 12, 1, 0.2), forEmeralds("stone_shovel", 1, 1, 12, 1, 0.2),
             forEmeralds("stone_pickaxe", 1, 1, 12, 1, 0.2), forEmeralds("stone_hoe", 1, 1, 12, 1, 0.2)],
            [emeraldFor("iron_ingot", 4, 12, 10), forEmeralds("bell", 36, 1, 12, 5, 0.2)],
            [emeraldFor("flint", 30, 12, 20), ench("iron_axe", 1, 3, 10, 0.2), ench("iron_shovel", 2, 3, 10, 0.2),
             ench("iron_pickaxe", 3, 3, 10, 0.2), forEmeralds("diamond_hoe", 4, 1, 3, 10, 0.2)],
            [emeraldFor("diamond", 1, 12, 30), ench("diamond_axe", 12, 3, 15, 0.2), ench("diamond_shovel", 5, 3, 15, 0.2)],
            [ench("diamond_pickaxe", 13, 3, 30, 0.2)],
        ],
        "weaponsmith": [
            [emeraldFor("coal", 15, 16, 2), forEmeralds("iron_axe", 3, 1, 12, 1, 0.2), ench("iron_sword", 2, 3, 1)],
            [emeraldFor("iron_ingot", 4, 12, 10), forEmeralds("bell", 36, 1, 12, 5, 0.2)],
            [emeraldFor("flint", 24, 12, 20)],
            [emeraldFor("diamond", 1, 12, 30), ench("diamond_axe", 12, 3, 15, 0.2)],
            [ench("diamond_sword", 8, 3, 30, 0.2)],
        ],
    ]

    static func type(for b: Biome) -> String {
        if b == .desert { return "desert" }
        if b.isBadlands || b == .savanna || b == .savannaPlateau || b == .windsweptSavanna { return "savanna" }
        if [.snowyPlains, .iceSpikes, .snowyTaiga, .snowySlopes, .frozenPeaks, .jaggedPeaks, .grove, .frozenRiver, .snowyBeach].contains(b) { return "snow" }
        if b == .jungle || b == .sparseJungle || b == .bambooJungle { return "jungle" }
        if b == .swamp || b == .mangroveSwamp { return "swamp" }
        if b == .taiga || b == .oldGrowthPineTaiga || b == .oldGrowthSpruceTaiga { return "taiga" }
        return "plains"
    }

    static func has(_ name: String) -> Bool { Items.has(String(name.split(separator: "@")[0])) }

    // Makes a concrete offer from a template.
    static func make(_ t: T) -> TradeOffer? {
        guard has(t.buy), has(t.sell), t.buyB.map(has) ?? true else { return nil }
        let sellName = String(t.sell.split(separator: "@")[0])
        let suffix = t.sell.contains("@") ? String(t.sell.split(separator: "@")[1]) : ""
        var sell = ItemStack(Items.id(sellName), t.sellN)
        var buyN = t.buyN
        switch suffix {
        case "ench":
            let lv = Rand.int(in: 5...19)
            sell = Enchant.withLevels(sell.item, lv)
            buyN = min(64, t.buyN + lv)
        case "book":
            // Random tradeable enchantment at a random level; treasure costs double.
            let opts = Ench.allCases.filter { ![.soulSpeed, .swiftSneak, .windBurst].contains($0) }
            let e = opts.pick()!
            let d = Enchant.def(e)
            let l = Rand.int(in: 1...d.max)
            sell.ench = Enchant.pack([(e, l)])
            var cost = 2 + Rand.int(in: 0..<(5 + l * 10)) + 3 * l
            if d.treasure { cost *= 2 }
            buyN = min(64, cost)
        case "tipped":
            let opts = Potions.types.filter { !$0.effects.isEmpty && !$0.key.hasPrefix("strong_turtle") }
            if let p = opts.pick(), let it = Potions.item(3, p.key) { sell = ItemStack(it, t.sellN) }
        default: break
        }
        let a = ItemStack(Items.id(t.buy), buyN)
        let b = t.buyB.map { ItemStack(Items.id($0), t.buyBN) } ?? .empty
        return TradeOffer(buyA: a, buyB: b, sell: sell, maxUses: t.uses, xp: t.xp, priceMult: t.mult)
    }

    // Adds the offers for a level (two random picks from that level's pool, like the reference).
    static func addOffers(_ v: inout VillagerData, level: Int) {
        guard let pools = trades[v.profession], level - 1 < pools.count else { return }
        var pool = pools[level - 1].filter { has($0.buy) && has($0.sell) }
        var picks = 0
        while picks < 2 && !pool.isEmpty {
            let i = Rand.int(in: 0..<pool.count)
            if let o = make(pool[i]) { v.offers.append(o); picks += 1 }
            pool.remove(at: i)
        }
    }
}

// MARK: Villager behaviour hooks

extension Mob {
    var vdata: VillagerData {
        get { villager ?? VillagerData() }
        set { villager = newValue }
    }

    // Claims a job site within 16 blocks when unemployed (ignores nitwits and children).
    func findJob(_ g: Game) {
        guard kind == .villager, !baby else { return }
        var v = vdata
        if v.profession == "nitwit" || v.locked { return }
        if v.profession != "none", let js = v.jobSite {
            // Lost the job site (broken)? Become unemployed again.
            let b = g.world.block(js[0], js[1], js[2])
            if Villagers.jobSites[Blocks.key(Blocks.groupBase[Int(b)])] == v.profession { return }
            v.profession = "none"; v.offers = []; v.jobSite = nil; v.level = 1; v.xp = 0
            villager = v
            return
        }
        let c = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
        var claimed = Set<IVec3>()
        for o in g.mobs.mobs where o !== self && o.kind == .villager { if let j = o.villager?.jobSite { claimed.insert(IVec3(j[0], j[1], j[2])) } }
        var best: (IVec3, String)?
        var bk = (Int.max, 0, 0, 0)              // (distance, dy, dz, dx): the nearest, ties in the old scan order
        let table = Villagers.jobSiteOf
        g.world.forEachBlock(around: c, r: 16, ry: 3) { b, x, y, z in
            guard Int(b) < table.count, let prof = table[Int(b)] else { return }
            let dx = x - c.x, dy = y - c.y, dz = z - c.z
            let k = (dx * dx + dy * dy + dz * dz, dy, dz, dx)
            guard k < bk, !claimed.contains(IVec3(x, y, z)) else { return }
            bk = k; best = (IVec3(x, y, z), prof)
        }
        guard let (p, prof) = best else { return }
        v.profession = prof
        v.jobSite = [p.x, p.y, p.z]
        if v.offers.isEmpty { Villagers.addOffers(&v, level: 1) }
        villager = v
        g.particles.hearts(at: pos + V3(0, 2.2, 0))
    }

    // Restock at the job site up to twice a day; demand follows how much each trade was used.
    func restock(_ g: Game) {
        guard kind == .villager, var v = villager, v.profession != "none", v.profession != "nitwit", let js = v.jobSite else { return }
        let day = Int(g.time / DAY_LENGTH)
        if day != v.lastRestockDay { v.lastRestockDay = day; v.restocksToday = 0 }
        guard v.restocksToday < 2, v.offers.contains(where: { $0.uses > 0 }) else { villager = v; return }
        let site = V3(Float(js[0]) + 0.5, Float(js[1]), Float(js[2]) + 0.5)
        guard simd_length(site - pos) < 3 else { villager = v; return }
        let frac = g.dayFraction
        // Work hours: morning to late afternoon.
        guard frac > 0.05 && frac < 0.45 else { villager = v; return }
        for i in v.offers.indices {
            let o = v.offers[i]
            v.offers[i].demand = max(0, o.demand + o.uses - (o.maxUses - o.uses))
            v.offers[i].uses = 0
        }
        v.restocksToday += 1
        villager = v
        if let w = MobVoice.workIndex(v.profession) { g.sfx(.villagerWork(w), 0.8, at: site + V3(0, 0.8, 0)) }
    }
}

// MARK: Trading

extension Game {
    // Right-click on a villager with a profession: open the trading screen.
    func openTrading(_ m: Mob) -> Bool {
        guard m.kind == .villager, !m.baby else { return false }
        var v = m.vdata
        if v.profession == "none" || v.profession == "nitwit" {
            sfx(.villagerNo, 0.8, at: m.pos + V3(0, 1.6, 0))       // shakes head
            return true
        }
        if v.offers.isEmpty { Villagers.addOffers(&v, level: 1); m.villager = v }
        openMenu(MerchantMenu(game: self, villager: m))
        return true
    }

    // Village Hero discount applied while a trade screen is open.
    func heroDiscount(_ o: TradeOffer) -> Int {
        let h = effects.level(.heroOfTheVillage)
        guard h > 0, !o.buyA.isEmpty else { return 0 }                   // every offer, not only emerald prices (20 wheat -> 14)
        let k = 0.3 + 0.0625 * Float(h - 1)
        return -max(1, Int(floor(k * Float(o.buyA.count))))
    }
}

final class MerchantMenu: Menu {
    weak var mob: Mob?
    let pay = ItemContainer(2)
    let result = ItemContainer(1)
    var selected = 0
    var scroll = 0
    static let visible = 7

    init(game: Game, villager: Mob) {
        mob = villager
        let v = villager.vdata
        let prof = v.profession.prefix(1).uppercased() + v.profession.dropFirst()
        super.init(prof, game: game)
        width = 276
        height = 166
        for i in 0..<MerchantMenu.visible {
            let b = MenuSlot(5, 18 + 20 * i, nil, 0, .button(i))
            b.w = 86; b.h = 18
            slots.append(b)
        }
        slots.append(MenuSlot(136, 37, pay, 0))
        slots.append(MenuSlot(162, 37, pay, 1))
        slots.append(MenuSlot(220, 37, result, 0, .result))
        addPlayerInventory(x: 108)
        inventoryLabelY = 73
        changed()
    }

    var offers: [TradeOffer] { mob?.villager?.offers ?? [] }

    func price(_ o: TradeOffer) -> ItemStack {
        var o2 = o
        // Reference special price: -floor(reputation x price multiplier), then the Village Hero discount.
        let rep = mob?.villager?.reputation ?? 0
        o2.special += game.heroDiscount(o) - Int(floor(Float(rep) * o.priceMult))
        return o2.costA
    }

    override func buttonPressed(_ i: Int) {
        let idx = scroll + i
        guard idx < offers.count else { return }
        selected = idx
        // Move the needed items from the inventory into the payment slots.
        for k in 0..<2 where !pay[k].isEmpty {
            let rest = game.inventory.add(pay[k]); if !rest.isEmpty { game.dropItem(rest) }
            pay[k] = .empty
        }
        let o = offers[idx]
        for (k, need) in [price(o), o.buyB].enumerated() where !need.isEmpty {
            var have = 0
            for j in 0..<36 where game.inventory.main[j].item == need.item && game.inventory.main[j].ench == 0 {
                have += game.inventory.main[j].count
            }
            let take = min(have, need.maxStack)
            if take > 0 {
                game.inventory.main.remove(need.item, take)
                pay[k] = ItemStack(need.item, take)
            }
        }
        changed()
    }

    override func changed() {
        result[0] = .empty
        guard selected < offers.count else { return }
        let o = offers[selected]
        if o.disabled { return }
        let a = price(o), b = o.buyB
        func enough(_ need: ItemStack) -> Bool {
            need.isEmpty || pay.slots.contains { $0.item == need.item && $0.count >= need.count }
        }
        if enough(a) && enough(b) { result[0] = o.sell }
    }

    override func takeResult(_ slot: MenuSlot) -> ItemStack? {
        guard let m = mob, var v = m.villager, selected < v.offers.count else { return nil }
        let o = v.offers[selected]
        guard !o.disabled, !result[0].isEmpty else { return nil }
        game.achieve("trade")
        for need in [price(o), o.buyB] where !need.isEmpty {
            if let k = (0..<2).first(where: { pay[$0].item == need.item && pay[$0].count >= need.count }) {
                var s = pay[k]; s.count -= need.count; pay[k] = s.count > 0 ? s : .empty
            }
        }
        v.offers[selected].uses += 1
        v.addGossip(.trading, 2)
        v.xp += o.xp
        v.locked = true
        // Trades give the player XP too (3-6, more when the villager levels up).
        game.addXP(Rand.int(in: 3...6))
        if v.level < 5 && v.xp >= Villagers.levelXP[v.level] {
            v.level += 1
            Villagers.addOffers(&v, level: v.level)
            game.addXP(5)
            game.particles.hearts(at: m.pos + V3(0, 2.2, 0))
            game.sfx(.villagerCelebrate, 0.8, at: m.pos + V3(0, 1.6, 0))
        }
        m.villager = v
        game.sfx(.villagerTrade, 0.7, at: m.pos + V3(0, 1.6, 0))
        let out = o.sell
        changed()
        return out
    }

    override func quickMoveTargets(from: MenuSlot) -> [MenuSlot] {
        if from.isPlayerInv {
            return from.isHotbar ? slots.filter { $0.isPlayerInv && !$0.isHotbar } : slots.filter { $0.isHotbar }
        }
        return super.quickMoveTargets(from: from)
    }

    override func onClose() {
        for k in 0..<2 where !pay[k].isEmpty {
            let rest = game.inventory.add(pay[k]); if !rest.isEmpty { game.dropItem(rest) }
            pay[k] = .empty
        }
    }
}
