import Foundation

// Crafting (shaped, shapeless, with item tags and mirroring), smelting and furnace fuels.
// Ingredient strings: an item name, or "#tag" for a group of items.
struct Recipe {
    let w: Int
    let h: Int
    let cells: [String?]        // w*h, row-major; nil = must be empty
    let result: ItemStack
    let shapeless: [String]     // non-empty => shapeless recipe
}

enum Recipes {
    static let tags: [String: [String]] = [
        "planks": ["oak_planks", "birch_planks", "spruce_planks", "crimson_planks", "warped_planks"],
        "logs": ["oak_log", "birch_log", "spruce_log", "oak_wood"],
        "stone_tool": ["cobblestone", "cobbled_deepslate"],
        "coals": ["coal", "charcoal"],
        "wooden_slabs": ["oak_slab"],
    ]
    private static var tagSets: [String: Set<ItemID>] = {
        var out: [String: Set<ItemID>] = [:]
        for (k, v) in tags { out[k] = Set(v.filter { Items.has($0) }.map { Items.id($0) }) }
        return out
    }()

    static func matches(_ ing: String, _ item: ItemID) -> Bool {
        if ing.hasPrefix("#") { return tagSets[String(ing.dropFirst())]?.contains(item) ?? false }
        return Items.has(ing) && Items.id(ing) == item
    }

    static var all: [Recipe] = build()

    static func shaped(_ rows: [String], _ key: [Character: String], _ result: String, _ n: Int = 1) -> Recipe? {
        guard Items.has(result) else { return nil }
        let h = rows.count, w = rows.map { $0.count }.max() ?? 0
        var cells: [String?] = []
        for r in rows {
            let chars = Array(r)
            for x in 0..<w { cells.append(x < chars.count && chars[x] != " " ? key[chars[x]] : nil) }
        }
        return Recipe(w: w, h: h, cells: cells, result: ItemStack(Items.id(result), n), shapeless: [])
    }

    static func shapeless(_ ings: [String], _ result: String, _ n: Int = 1) -> Recipe? {
        guard Items.has(result) else { return nil }
        return Recipe(w: 0, h: 0, cells: [], result: ItemStack(Items.id(result), n), shapeless: ings)
    }

    static func build() -> [Recipe] {
        var r: [Recipe?] = []
        // Wood
        for (log, plank) in [("oak_log", "oak_planks"), ("birch_log", "birch_planks"), ("spruce_log", "spruce_planks"), ("oak_wood", "oak_planks")] {
            r.append(shapeless([log], plank, 4))
        }
        r.append(shaped(["#", "#"], ["#": "#planks"], "stick", 4))
        r.append(shaped(["##", "##"], ["#": "#planks"], "crafting_table"))
        r.append(shaped(["###", "# #", "###"], ["#": "#planks"], "chest"))
        r.append(shaped(["###", "# #", "###"], ["#": "#stone_tool"], "furnace"))
        r.append(shaped(["C", "S"], ["C": "#coals", "S": "stick"], "torch", 4))
        for (log, plank) in [("crimson_stem", "crimson_planks"), ("warped_stem", "warped_planks")] { r.append(shapeless([log], plank, 4)) }
        // Stairs / slabs / fences / walls for every material family.
        let families: [(String, String)] = [
            ("oak_planks", "oak"), ("birch_planks", "birch"), ("spruce_planks", "spruce"), ("crimson_planks", "crimson"), ("warped_planks", "warped"),
            ("cobblestone", "cobblestone"), ("stone", "stone"), ("stone_bricks", "stone_brick"), ("bricks", "brick"), ("sandstone", "sandstone"),
            ("nether_bricks", "nether_brick"), ("red_nether_bricks", "red_nether_brick"), ("blackstone", "blackstone"),
            ("cobbled_deepslate", "cobbled_deepslate"), ("mossy_cobblestone", "mossy_cobblestone"), ("andesite", "andesite"),
            ("diorite", "diorite"), ("granite", "granite"), ("smooth_stone", "smooth_stone"),
        ]
        for (mat, n) in families {
            r.append(shaped(["#  ", "## ", "###"], ["#": mat], "\(n)_stairs", 4))
            r.append(shaped(["###"], ["#": mat], "\(n)_slab", 6))
            r.append(shaped(["###", "###"], ["#": mat], "\(n)_wall", 6))
            if mat.hasSuffix("_planks") { r.append(shaped(["#S#", "#S#"], ["#": mat, "S": "stick"], "\(n)_fence", 3)) }
        }
        r.append(shaped(["#B#", "#B#"], ["#": "nether_bricks", "B": "nether_brick"], "nether_brick_fence", 6))
        r.append(shaped(["##", "##"], ["#": "nether_brick"], "nether_bricks"))
        r.append(shaped(["###", "###"], ["#": "glass"], "glass_pane", 16))
        r.append(shaped(["###", "###"], ["#": "iron_ingot"], "iron_bars", 16))
        r.append(shaped(["# #", " # "], ["#": "#planks"], "bowl", 4))
        r.append(shaped(["##", "##"], ["#": "stone"], "stone_bricks", 4))
        r.append(shaped(["##", "##"], ["#": "sand"], "sandstone"))
        r.append(shaped(["##", "##"], ["#": "brick"], "bricks"))
        r.append(shaped(["##", "##"], ["#": "snowball"], "snow_block"))
        r.append(shaped(["##", "##"], ["#": "clay_ball"], "clay"))
        r.append(shaped(["##", "##"], ["#": "glowstone_dust"], "glowstone"))
        // Tools and weapons
        let mats: [(String, String)] = [("#planks", "wooden"), ("#stone_tool", "stone"), ("iron_ingot", "iron"),
                                        ("gold_ingot", "golden"), ("diamond", "diamond")]
        for (m, t) in mats {
            let k: [Character: String] = ["X": m, "#": "stick"]
            r.append(shaped(["XXX", " # ", " # "], k, "\(t)_pickaxe"))
            r.append(shaped(["XX", "X#", " #"], k, "\(t)_axe"))
            r.append(shaped(["X", "#", "#"], k, "\(t)_shovel"))
            r.append(shaped(["XX", " #", " #"], k, "\(t)_hoe"))
            r.append(shaped(["X", "X", "#"], k, "\(t)_sword"))
        }
        // Armor
        for (m, a) in [("leather", "leather"), ("iron_ingot", "iron"), ("gold_ingot", "golden"), ("diamond", "diamond")] {
            let k: [Character: String] = ["X": m]
            r.append(shaped(["XXX", "X X"], k, a == "leather" ? "leather_helmet" : "\(a)_helmet"))
            r.append(shaped(["X X", "XXX", "XXX"], k, "\(a)_chestplate"))
            r.append(shaped(["XXX", "X X", "X X"], k, "\(a)_leggings"))
            r.append(shaped(["X X", "X X"], k, "\(a)_boots"))
        }
        // Storage blocks and nuggets
        for (item, block) in [("coal", "coal_block"), ("iron_ingot", "iron_block"), ("gold_ingot", "gold_block"),
                              ("diamond", "diamond_block"), ("emerald", "emerald_block"), ("lapis_lazuli", "lapis_block"),
                              ("redstone", "redstone_block"), ("copper_ingot", "copper_block")] {
            r.append(shaped(["XXX", "XXX", "XXX"], ["X": item], block))
            r.append(shapeless([block], item, 9))
        }
        r.append(shaped(["XXX", "XXX", "XXX"], ["X": "iron_nugget"], "iron_ingot"))
        r.append(shapeless(["iron_ingot"], "iron_nugget", 9))
        r.append(shaped(["XXX", "XXX", "XXX"], ["X": "gold_nugget"], "gold_ingot"))
        r.append(shapeless(["gold_ingot"], "gold_nugget", 9))
        // Misc
        r.append(shaped(["# #", " # "], ["#": "iron_ingot"], "bucket"))
        r.append(shaped([" #", "# "], ["#": "iron_ingot"], "shears"))
        r.append(shapeless(["iron_ingot", "flint"], "flint_and_steel"))
        r.append(shaped([" #S", "# S", " #S"], ["#": "stick", "S": "string"], "bow"))
        r.append(shaped(["F", "#", "E"], ["F": "flint", "#": "stick", "E": "feather"], "arrow", 4))
        r.append(shaped(["###"], ["#": "wheat"], "bread"))
        r.append(shaped(["###", "#A#", "###"], ["#": "gold_ingot", "A": "apple"], "golden_apple"))
        r.append(shaped(["###", "#C#", "###"], ["#": "gold_nugget", "C": "carrot"], "golden_carrot"))
        r.append(shapeless(["paper", "paper", "paper", "leather"], "book"))
        r.append(shapeless(["bone"], "bone_meal", 3))
        r.append(shapeless(["blaze_rod"], "blaze_powder", 2))
        r.append(shapeless(["ender_pearl", "blaze_powder"], "ender_eye"))
        r.append(shaped([" # ", "#R#", " # "], ["#": "iron_ingot", "R": "redstone"], "compass"))
        r.append(shaped([" # ", "#R#", " # "], ["#": "gold_ingot", "R": "redstone"], "clock"))
        r.append(shapeless(["bowl", "beetroot", "beetroot", "beetroot", "beetroot", "beetroot", "beetroot"], "beetroot_soup"))
        return r.compactMap { $0 }
    }

    // Finds the result for a w x h crafting grid (row-major item ids, 0 = empty).
    static func match(_ grid: [ItemID], _ gw: Int, _ gh: Int) -> Recipe? {
        var minX = gw, minY = gh, maxX = -1, maxY = -1
        var items: [ItemID] = []
        for y in 0..<gh { for x in 0..<gw where grid[x + y * gw] != 0 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            items.append(grid[x + y * gw])
        } }
        if items.isEmpty { return nil }
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        func at(_ x: Int, _ y: Int) -> ItemID { grid[(x + minX) + (y + minY) * gw] }
        for rec in all {
            if !rec.shapeless.isEmpty {
                if rec.shapeless.count != items.count { continue }
                var used = [Bool](repeating: false, count: items.count)
                var ok = true
                for ing in rec.shapeless {
                    guard let i = items.indices.first(where: { !used[$0] && matches(ing, items[$0]) }) else { ok = false; break }
                    used[i] = true
                }
                if ok { return rec }
                continue
            }
            if rec.w != bw || rec.h != bh { continue }
            for mirror in [false, true] {
                var ok = true
                for y in 0..<bh where ok {
                    for x in 0..<bw {
                        let cell = rec.cells[(mirror ? bw - 1 - x : x) + y * bw]
                        let it = at(x, y)
                        if let c = cell { if it == 0 || !matches(c, it) { ok = false; break } }
                        else if it != 0 { ok = false; break }
                    }
                }
                if ok { return rec }
            }
        }
        return nil
    }

    // MARK: Smelting

    static let smelting: [String: String] = [
        "raw_iron": "iron_ingot", "raw_gold": "gold_ingot", "raw_copper": "copper_ingot",
        "iron_ore": "iron_ingot", "gold_ore": "gold_ingot", "copper_ore": "copper_ingot",
        "deepslate_iron_ore": "iron_ingot", "deepslate_gold_ore": "gold_ingot", "deepslate_copper_ore": "copper_ingot",
        "diamond_ore": "diamond", "deepslate_diamond_ore": "diamond", "coal_ore": "coal", "deepslate_coal_ore": "coal",
        "emerald_ore": "emerald", "lapis_ore": "lapis_lazuli", "redstone_ore": "redstone",
        "sand": "glass", "red_sand": "glass", "cobblestone": "stone", "stone": "smooth_stone", "cobbled_deepslate": "deepslate",
        "clay_ball": "brick", "clay": "terracotta", "oak_log": "charcoal", "birch_log": "charcoal", "spruce_log": "charcoal",
        "oak_wood": "charcoal", "beef": "cooked_beef", "porkchop": "cooked_porkchop", "chicken": "cooked_chicken",
        "mutton": "cooked_mutton", "rabbit": "cooked_rabbit", "cod": "cooked_cod", "salmon": "cooked_salmon",
        "potato": "baked_potato", "netherrack": "nether_brick", "nether_gold_ore": "gold_ingot", "nether_quartz_ore": "quartz",
        "ancient_debris": "netherite_scrap",
    ]
    static func smelt(_ i: ItemID) -> ItemID? {
        guard let r = smelting[Items.key(i)], Items.has(r) else { return nil }
        return Items.id(r)
    }
    static func fuel(_ i: ItemID) -> Int {
        let k = Items.key(i)
        switch k {
        case "coal_block": return 16000
        case "lava_bucket": return 20000
        case "blaze_rod": return 2400
        default: return Items.def(i).fuelTicks
        }
    }
}
