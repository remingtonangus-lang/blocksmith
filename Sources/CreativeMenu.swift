import Foundation

// Creative palette: tabs (LB/RB, Tab key, or clicking the tab strip) and a Search tab that filters by name
// (type on the keyboard, or Y for the on-screen keyboard). The right stick / wheel scrolls, LT/RT page.
final class CreativeMenu: Menu {
    enum Tab: Int, CaseIterable {
        case all, building, natural, functional, sparkstone, tools, food, misc, search
        var name: String { ["All Items", "Building Blocks", "Natural Blocks", "Functional Blocks", "Copper Circuits", "Tools & Combat", "Food & Potions", "Ingredients", "Search"][rawValue] }
        var icon: String { ["compass", "bricks", "grass_block", "crafting_table", "redstone", "iron_pickaxe", "apple", "stick", "spyglass"][rawValue] }
        var short: String { ["All", "Build", "Nature", "Use", "Spark", "Tools", "Food", "Misc", "Find"][rawValue] }
    }
    static let every: [ItemID] = Items.creativeList
    static var cache: [Int: [ItemID]] = [:]
    var all: [ItemID] = CreativeMenu.every
    var tab: Tab = .all
    var query = ""
    var scroll = 0
    let rows = 5
    static let tabButton = 700

    init(game: Game) {
        super.init("Creative Inventory", game: game)
        width = 195
        height = 150
        for r in 0..<rows { for c in 0..<9 {
            let s = MenuSlot(9 + c * 18, 32 + r * 18, nil, 0, .palette)
            slots.append(s)
        } }
        for c in 0..<9 {
            let s = MenuSlot(9 + c * 18, 126, game.inventory.main, c)
            s.isPlayerInv = true
            s.isHotbar = true
            slots.append(s)
        }
        // Tab strip (buttons, so the controller cursor can reach them too).
        for t in Tab.allCases {
            let b = MenuSlot(4 + t.rawValue * 21, 15, nil, 0, .button(CreativeMenu.tabButton + t.rawValue))      // 14 touched the title
            b.w = 20; b.h = 16
            slots.append(b)
        }
        showInventoryLabel = false
        refresh()
    }

    var maxScroll: Int { max(0, (all.count + 8) / 9 - rows) }

    func refresh() {
        for i in 0..<(rows * 9) {
            let k = scroll * 9 + i
            slots[i].paletteItem = k < all.count ? all[k] : 0
        }
        title = tab == .search ? "Search: \(query)\(Int(game.clock * 2) % 2 == 0 ? "_" : "")" : tab.name
    }

    func scrollBy(_ d: Int) { scroll = max(0, min(maxScroll, scroll + d)); refresh() }

    func setTab(_ t: Tab) {
        tab = t
        scroll = 0
        all = CreativeMenu.items(t, query: query)
        refresh()
        game.sfx(.click, 0.4)
    }
    func switchTab(_ d: Int) {
        let n = Tab.allCases.count
        setTab(Tab(rawValue: (tab.rawValue + d + n) % n) ?? .all)
    }

    override var capturesText: Bool { tab == .search }
    override func typed(_ s: String) {
        guard tab == .search else { return }
        for c in s {
            if c == "\u{8}" { if !query.isEmpty { query.removeLast() } }
            else if query.count < 24 { query.append(c) }
        }
        scroll = 0
        all = CreativeMenu.items(.search, query: query)
        refresh()
    }
    override func tick() {
        if game.input.tapped(Key.tab) { switchTab(game.input.shift ? -1 : 1) }
        if tab == .search { refresh() }     // caret blink
    }
    override func buttonPressed(_ i: Int) {
        if i >= CreativeMenu.tabButton, let t = Tab(rawValue: i - CreativeMenu.tabButton) { setTab(t) }
    }
    override func quickMoveTargets(from: MenuSlot) -> [MenuSlot] { [] }
    override func click(_ slot: MenuSlot, button: Int, shift: Bool) {
        if slot.isHotbar && shift { slot.stack = .empty; return }
        super.click(slot, button: button, shift: shift)
    }

    // MARK: Categories

    static func items(_ t: Tab, query: String) -> [ItemID] {
        if t == .all { return every }
        if t == .search {
            let q = query.lowercased().trimmingCharacters(in: .whitespaces)
            if q.isEmpty { return every }
            return every.filter { Items.def($0).display.lowercased().contains(q) || Items.key($0).contains(q.replacingOccurrences(of: " ", with: "_")) }
        }
        if let c = cache[t.rawValue] { return c }
        let list = every.filter { category($0) == t }
        cache[t.rawValue] = list
        return list
    }

    static let sparkWords = ["redstone", "piston", "repeater", "comparator", "lever", "button", "pressure_plate", "hopper", "dispenser", "dropper",
                             "observer", "rail", "tnt", "lamp", "daylight", "target", "note_block", "tripwire", "minecart", "sculk_sensor",
                             "crafter", "slime_block", "honey_block", "copper_bulb", "trapped_chest", "lightning_rod"]
    static let functionalWords = ["crafting_table", "furnace", "chest", "barrel", "anvil", "enchanting", "brewing", "_bed", "smoker", "loom",
                                  "stonecutter", "grindstone", "smithing", "cartography", "lectern", "composter", "bell", "campfire", "torch",
                                  "lantern", "beacon", "shulker_box", "jukebox", "sign", "banner", "item_frame", "painting", "flower_pot",
                                  "scaffolding", "ladder", "cauldron", "respawn_anchor", "lodestone", "bookshelf", "decorated_pot", "candle",
                                  "_head", "skull", "spawner", "vault", "conduit", "beehive", "bee_nest", "armor_stand", "end_portal_frame",
                                  "end_rod", "chain", "glow_lichen", "sea_lantern", "shroomlight", "froglight", "jack_o_lantern"]
    static let naturalWords = ["ore", "_log", "leaves", "sapling", "dirt", "grass", "sand", "gravel", "clay", "flower", "mushroom", "moss",
                               "ice", "snow", "coral", "kelp", "vine", "fern", "bush", "cactus", "bamboo", "sugar_cane", "netherrack", "wart",
                               "roots", "tulip", "orchid", "daisy", "poppy", "dandelion", "allium", "bluet", "cornflower", "lily", "seagrass",
                               "dripstone", "amethyst", "obsidian", "basalt", "mycelium", "podzol", "mud", "nylium", "stem", "tuff", "calcite",
                               "granite", "diorite", "andesite", "deepslate", "bedrock", "pumpkin", "melon", "hay", "sponge", "cobweb",
                               "pointed", "azalea", "dripleaf", "spore", "propagule", "petals", "pitcher", "torchflower", "wither_rose",
                               "egg", "frogspawn", "sculk", "stone", "end_stone", "soul_", "magma", "glowstone", "blossom", "hanging_moss",
                               "nightbloom", "ashen", "rose", "lilac", "peony", "sunflower", "wheat", "carrots", "potatoes", "beetroots", "cocoa",
                               "sweet_berry", "berries", "crop"]
    static let foodWords = ["potion", "stew", "soup", "apple", "bread", "cookie", "cake", "pie", "golden_carrot", "honey_bottle", "milk"]

    static func category(_ id: ItemID) -> Tab {
        let d = Items.def(id)
        let k = d.name
        func has(_ words: [String]) -> Bool { words.contains { k.contains($0) } }
        if let _ = d.block {
            if has(sparkWords) { return .sparkstone }
            if has(functionalWords) { return .functional }
            // Worked / crafted building variants of natural materials count as building blocks.
            let worked = ["brick", "planks", "slab", "stairs", "wall", "fence", "door", "polished", "chiseled", "cut_", "smooth", "tiles",
                          "pillar", "glass", "concrete", "terracotta", "wool", "carpet", "block_of", "_block", "stripped", "wood", "hyphae", "bars"]
            if has(worked) && !k.hasSuffix("_ore") { return .building }
            if has(naturalWords) { return .natural }
            return .building
        }
        if d.tool != .none || d.durability > 0 || d.armorSlot != nil || k.contains("arrow") || k.contains("firework") || k.contains("wind_charge")
            || k.contains("snowball") || k.contains("pearl") { return .tools }
        if d.food != nil || d.drink || has(foodWords) { return .food }
        if has(sparkWords) { return .sparkstone }
        return .misc
    }
}
