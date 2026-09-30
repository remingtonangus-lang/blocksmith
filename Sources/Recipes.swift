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
        "planks": ["oak_planks", "birch_planks", "spruce_planks", "crimson_planks", "warped_planks", "acacia_planks", "dark_oak_planks",
                   "jungle_planks", "mangrove_planks", "cherry_planks", "bamboo_planks"],
        "logs": ["oak_log", "birch_log", "spruce_log", "oak_wood", "acacia_log", "dark_oak_log", "jungle_log", "mangrove_log", "cherry_log"],
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
        for w in ["acacia", "dark_oak", "jungle", "mangrove", "cherry"] { r.append(shapeless(["\(w)_log"], "\(w)_planks", 4)) }
        r.append(shaped(["##", "##"], ["#": "mud"], "packed_mud", 1))
        r.append(shaped(["##", "##"], ["#": "packed_mud"], "mud_bricks", 4))
        r.append(shaped(["##", "##"], ["#": "red_sand"], "red_sandstone", 1))
        r.append(shaped(["###", "###", "###"], ["#": "ice"], "packed_ice", 1))
        r.append(shaped(["###", "###", "###"], ["#": "packed_ice"], "blue_ice", 1))
        r.append(shaped(["##", "##"], ["#": "amethyst_shard"], "amethyst_block", 1))
        r.append(shaped(["###", "###", "###"], ["#": "melon_slice"], "melon", 1))
        r.append(shapeless(["melon_slice"], "melon_seeds", 1))
        r.append(shapeless(["pumpkin"], "pumpkin_seeds", 4))
        r.append(shaped(["##", "##"], ["#": "cobbled_deepslate"], "polished_deepslate", 4))
        r.append(shaped(["##", "##"], ["#": "polished_deepslate"], "deepslate_bricks", 4))
        r.append(shaped(["##", "##"], ["#": "deepslate_bricks"], "deepslate_tiles", 4))
        r.append(shaped(["##", "##"], ["#": "prismarine_shard"], "prismarine", 1))

        // Stairs / slabs / fences / walls for every material family.
        let families: [(String, String)] = [
            ("oak_planks", "oak"), ("birch_planks", "birch"), ("spruce_planks", "spruce"), ("crimson_planks", "crimson"), ("warped_planks", "warped"),
            ("cobblestone", "cobblestone"), ("stone", "stone"), ("stone_bricks", "stone_brick"), ("bricks", "brick"), ("sandstone", "sandstone"),
            ("nether_bricks", "nether_brick"), ("red_nether_bricks", "red_nether_brick"), ("blackstone", "blackstone"),
            ("cobbled_deepslate", "cobbled_deepslate"), ("mossy_cobblestone", "mossy_cobblestone"), ("andesite", "andesite"),
            ("diorite", "diorite"), ("granite", "granite"), ("smooth_stone", "smooth_stone"),
            ("polished_blackstone", "polished_blackstone"), ("polished_blackstone_bricks", "polished_blackstone_brick"),
        ]
        for (mat, n) in families {
            r.append(shaped(["#  ", "## ", "###"], ["#": mat], "\(n)_stairs", 4))
            r.append(shaped(["###"], ["#": mat], "\(n)_slab", 6))
            r.append(shaped(["###", "###"], ["#": mat], "\(n)_wall", 6))
            if mat.hasSuffix("_planks") { r.append(shaped(["#S#", "#S#"], ["#": mat, "S": "stick"], "\(n)_fence", 3)) }
        }
        r.append(shaped(["#B#", "#B#"], ["#": "nether_bricks", "B": "nether_brick"], "nether_brick_fence", 6))
        r.append(shaped(["##", "##"], ["#": "nether_brick"], "nether_bricks"))
        r.append(shaped(["##", "##"], ["#": "blackstone"], "polished_blackstone", 4))
        r.append(shapeless(["blaze_rod"], "blaze_powder", 2))
        // Redstone.
        r.append(shaped(["R", "S"], ["R": "redstone", "S": "stick"], "redstone_torch", 1))
        r.append(shaped(["S", "C"], ["S": "stick", "C": "cobblestone"], "lever", 1))
        r.append(shapeless(["stone"], "stone_button", 1))
        r.append(shapeless(["polished_blackstone"], "polished_blackstone_button", 1))
        for w in BlockRegistry.buttonWoods {
            r.append(shapeless(["\(w)_planks"], "\(w)_button", 1))
            r.append(shaped(["##"], ["#": "\(w)_planks"], "\(w)_pressure_plate", 1))
        }
        r.append(shaped(["##"], ["#": "stone"], "stone_pressure_plate", 1))
        r.append(shaped(["##"], ["#": "gold_ingot"], "light_weighted_pressure_plate", 1))
        r.append(shaped(["##"], ["#": "iron_ingot"], "heavy_weighted_pressure_plate", 1))
        r.append(shaped(["TRT", "SSS"], ["T": "redstone_torch", "R": "redstone", "S": "stone"], "repeater", 1))
        r.append(shaped([" T ", "TQT", "SSS"], ["T": "redstone_torch", "Q": "quartz", "S": "stone"], "comparator", 1))
        r.append(shaped(["CCC", "RRQ", "CCC"], ["C": "cobblestone", "R": "redstone", "Q": "quartz"], "observer", 1))
        r.append(shaped(["PPP", "CIC", "CRC"], ["P": "#planks", "C": "cobblestone", "I": "iron_ingot", "R": "redstone"], "piston", 1))
        r.append(shaped(["S", "P"], ["S": "slime_ball", "P": "piston"], "sticky_piston", 1))
        r.append(shaped(["###", "###", "###"], ["#": "slime_ball"], "slime_block", 1))
        r.append(shapeless(["slime_block"], "slime_ball", 9))
        r.append(shaped(["CCC", "CBC", "CRC"], ["C": "cobblestone", "B": "bow", "R": "redstone"], "dispenser", 1))
        r.append(shaped(["CCC", "C C", "CRC"], ["C": "cobblestone", "R": "redstone"], "dropper", 1))
        r.append(shaped(["I I", "ICI", " I "], ["I": "iron_ingot", "C": "chest"], "hopper", 1))
        r.append(shaped(["PPP", "PRP", "PPP"], ["P": "#planks", "R": "redstone"], "note_block", 1))
        r.append(shaped(["GGG", "QQQ", "SSS"], ["G": "glass", "Q": "quartz", "S": "oak_slab"], "daylight_detector", 1))
        r.append(shaped([" R ", "RHR", " R "], ["R": "redstone", "H": "hay_block"], "target", 1))
        r.append(shaped([" R ", "RGR", " R "], ["R": "redstone", "G": "glowstone"], "redstone_lamp", 1))
        r.append(shaped(["###", "###", "###"], ["#": "redstone"], "redstone_block", 1))
        r.append(shapeless(["redstone_block"], "redstone", 9))
        r.append(shaped(["G G", "GSG", "GRG"], ["G": "gold_ingot", "S": "stick", "R": "redstone"], "powered_rail", 6))
        r.append(shaped(["I I", "IPI", "IRI"], ["I": "iron_ingot", "P": "stone_pressure_plate", "R": "redstone"], "detector_rail", 6))
        r.append(shaped(["ISI", "ITI", "ISI"], ["I": "iron_ingot", "S": "stick", "T": "redstone_torch"], "activator_rail", 6))
        r.append(shaped(["I I", "III"], ["I": "iron_ingot"], "minecart", 1))
        r.append(shaped(["I I", "ISI", "I I"], ["I": "iron_ingot", "S": "stick"], "rail", 16))
        for w in BlockRegistry.doorWoods {
            r.append(shaped(["##", "##", "##"], ["#": "\(w)_planks"], "\(w)_door", 3))
            r.append(shaped(["###", "###"], ["#": "\(w)_planks"], "\(w)_trapdoor", 2))
            r.append(shaped(["S#S", "S#S"], ["#": "\(w)_planks", "S": "stick"], "\(w)_fence_gate", 1))
        }
        r.append(shaped(["##", "##", "##"], ["#": "iron_ingot"], "iron_door", 3))
        r.append(shaped(["##", "##"], ["#": "iron_ingot"], "iron_trapdoor", 1))
        r.append(shaped(["S S", "SSS", "S S"], ["S": "stick"], "ladder", 3))
        r.append(shaped(["NNN", "NTN", "NNN"], ["N": "iron_nugget", "T": "torch"], "lantern", 1))
        r.append(shaped(["###", "###", "###"], ["#": "wheat"], "hay_block", 1))
        r.append(shapeless(["hay_block"], "wheat", 9))
        r.append(shaped(["# #", "# #", "###"], ["#": "oak_slab"], "composter", 1))
        r.append(shaped(["PSP", "P P", "PSP"], ["P": "#planks", "S": "oak_slab"], "barrel", 1))
        r.append(shaped([" L ", "LFL", " L "], ["L": "#logs", "F": "furnace"], "smoker", 1))
        r.append(shaped(["III", "IFI", "SSS"], ["I": "iron_ingot", "F": "furnace", "S": "smooth_stone"], "blast_furnace", 1))
        r.append(shaped(["pp", "##", "##"], ["p": "paper", "#": "#planks"], "cartography_table", 1))
        r.append(shaped(["ff", "##", "##"], ["f": "flint", "#": "#planks"], "fletching_table", 1))
        r.append(shaped(["ii", "##", "##"], ["i": "iron_ingot", "#": "#planks"], "smithing_table", 1))
        r.append(shaped(["ss", "##"], ["s": "string", "#": "#planks"], "loom", 1))
        r.append(shaped([" i ", "SSS"], ["i": "iron_ingot", "S": "stone"], "stonecutter", 1))
        r.append(shaped(["SsS", "# #"], ["S": "stick", "s": "stone_slab", "#": "#planks"], "grindstone", 1))
        r.append(shaped(["sss", " B ", " s "], ["s": "oak_slab", "B": "bookshelf"], "lectern", 1))
        r.append(shaped(["BBB", " i ", "iii"], ["B": "iron_block", "i": "iron_ingot"], "anvil", 1))
        r.append(shaped(["i i", "i i", "iii"], ["i": "iron_ingot"], "cauldron", 1))
        r.append(shaped(["b b", " b "], ["b": "brick"], "flower_pot", 1))
        for (c, _) in BlockRegistry.colors { r.append(shaped(["##"], ["#": "\(c)_wool"], "\(c)_carpet", 3)) }
        r.append(shaped(["##", "##"], ["#": "sandstone"], "cut_sandstone", 4))
        r.append(shaped(["#", "#"], ["#": "sandstone_slab"], "chiseled_sandstone", 1))
        r.append(shaped(["##", "##"], ["#": "red_sandstone"], "cut_red_sandstone", 4))
        r.append(shapeless(["paper", "gunpowder"], "firework_rocket", 3))
        r.append(shaped(["##", "##"], ["#": "popped_chorus_fruit"], "purpur_block", 4))
        r.append(shaped(["#", "#"], ["#": "purpur_slab"], "purpur_pillar", 1))
        r.append(shaped(["B", "P"], ["B": "blaze_powder", "P": "popped_chorus_fruit"], "end_rod", 4))
        r.append(shapeless(["ender_pearl", "blaze_powder"], "ender_eye", 1))
        r.append(shaped(["###"], ["#": "sugar_cane"], "paper", 3))
        r.append(shapeless(["sugar_cane"], "sugar", 1))
        r.append(shapeless(["paper", "paper", "paper", "leather"], "book", 1))
        r.append(shaped(["###", "BBB", "###"], ["#": "#planks", "B": "book"], "bookshelf", 1))
        r.append(shaped(["##", "##"], ["#": "end_stone"], "end_stone_bricks", 4))
        r.append(shaped(["##", "##"], ["#": "stone_bricks"], "chiseled_stone_bricks", 1))
        r.append(shapeless(["stone_bricks", "vine"], "mossy_stone_bricks", 1))
        r.append(shaped(["S S", "SSS", "SSS"], ["S": "string"], "cobweb", 1))
        r.append(shaped(["##", "##"], ["#": "polished_blackstone"], "polished_blackstone_bricks", 4))
        r.append(shaped(["#", "#"], ["#": "polished_blackstone_slab"], "chiseled_polished_blackstone"))
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
        // Redstone.
        r.append(shaped(["R", "S"], ["R": "redstone", "S": "stick"], "redstone_torch", 1))
        r.append(shaped(["S", "C"], ["S": "stick", "C": "cobblestone"], "lever", 1))
        r.append(shapeless(["stone"], "stone_button", 1))
        r.append(shapeless(["polished_blackstone"], "polished_blackstone_button", 1))
        for w in BlockRegistry.buttonWoods {
            r.append(shapeless(["\(w)_planks"], "\(w)_button", 1))
            r.append(shaped(["##"], ["#": "\(w)_planks"], "\(w)_pressure_plate", 1))
        }
        r.append(shaped(["##"], ["#": "stone"], "stone_pressure_plate", 1))
        r.append(shaped(["##"], ["#": "gold_ingot"], "light_weighted_pressure_plate", 1))
        r.append(shaped(["##"], ["#": "iron_ingot"], "heavy_weighted_pressure_plate", 1))
        r.append(shaped(["TRT", "SSS"], ["T": "redstone_torch", "R": "redstone", "S": "stone"], "repeater", 1))
        r.append(shaped([" T ", "TQT", "SSS"], ["T": "redstone_torch", "Q": "quartz", "S": "stone"], "comparator", 1))
        r.append(shaped(["CCC", "RRQ", "CCC"], ["C": "cobblestone", "R": "redstone", "Q": "quartz"], "observer", 1))
        r.append(shaped(["PPP", "CIC", "CRC"], ["P": "#planks", "C": "cobblestone", "I": "iron_ingot", "R": "redstone"], "piston", 1))
        r.append(shaped(["S", "P"], ["S": "slime_ball", "P": "piston"], "sticky_piston", 1))
        r.append(shaped(["###", "###", "###"], ["#": "slime_ball"], "slime_block", 1))
        r.append(shapeless(["slime_block"], "slime_ball", 9))
        r.append(shaped(["CCC", "CBC", "CRC"], ["C": "cobblestone", "B": "bow", "R": "redstone"], "dispenser", 1))
        r.append(shaped(["CCC", "C C", "CRC"], ["C": "cobblestone", "R": "redstone"], "dropper", 1))
        r.append(shaped(["I I", "ICI", " I "], ["I": "iron_ingot", "C": "chest"], "hopper", 1))
        r.append(shaped(["PPP", "PRP", "PPP"], ["P": "#planks", "R": "redstone"], "note_block", 1))
        r.append(shaped(["GGG", "QQQ", "SSS"], ["G": "glass", "Q": "quartz", "S": "oak_slab"], "daylight_detector", 1))
        r.append(shaped([" R ", "RHR", " R "], ["R": "redstone", "H": "hay_block"], "target", 1))
        r.append(shaped([" R ", "RGR", " R "], ["R": "redstone", "G": "glowstone"], "redstone_lamp", 1))
        r.append(shaped(["###", "###", "###"], ["#": "redstone"], "redstone_block", 1))
        r.append(shapeless(["redstone_block"], "redstone", 9))
        r.append(shaped(["G G", "GSG", "GRG"], ["G": "gold_ingot", "S": "stick", "R": "redstone"], "powered_rail", 6))
        r.append(shaped(["I I", "IPI", "IRI"], ["I": "iron_ingot", "P": "stone_pressure_plate", "R": "redstone"], "detector_rail", 6))
        r.append(shaped(["ISI", "ITI", "ISI"], ["I": "iron_ingot", "S": "stick", "T": "redstone_torch"], "activator_rail", 6))
        r.append(shaped(["I I", "III"], ["I": "iron_ingot"], "minecart", 1))
        for w in BlockRegistry.doorWoods {
            r.append(shaped(["##", "##", "##"], ["#": "\(w)_planks"], "\(w)_door", 3))
            r.append(shaped(["###", "###"], ["#": "\(w)_planks"], "\(w)_trapdoor", 2))
            r.append(shaped(["S#S", "S#S"], ["#": "\(w)_planks", "S": "stick"], "\(w)_fence_gate", 1))
        }
        r.append(shaped(["##", "##", "##"], ["#": "iron_ingot"], "iron_door", 3))
        r.append(shaped(["##", "##"], ["#": "iron_ingot"], "iron_trapdoor", 1))
        r.append(shaped(["S S", "SSS", "S S"], ["S": "stick"], "ladder", 3))
        r.append(shaped(["NNN", "NTN", "NNN"], ["N": "iron_nugget", "T": "torch"], "lantern", 1))
        r.append(shaped(["###", "###", "###"], ["#": "wheat"], "hay_block", 1))
        r.append(shapeless(["hay_block"], "wheat", 9))
        r.append(shaped(["##", "##"], ["#": "sandstone"], "cut_sandstone", 4))
        r.append(shaped(["#", "#"], ["#": "sandstone_slab"], "chiseled_sandstone", 1))
        r.append(shaped(["##", "##"], ["#": "red_sandstone"], "cut_red_sandstone", 4))
        r.append(shapeless(["paper", "gunpowder"], "firework_rocket", 3))
        r.append(shaped(["##", "##"], ["#": "popped_chorus_fruit"], "purpur_block", 4))
        r.append(shaped(["#", "#"], ["#": "purpur_slab"], "purpur_pillar", 1))
        r.append(shaped(["B", "P"], ["B": "blaze_powder", "P": "popped_chorus_fruit"], "end_rod", 4))
        r.append(shapeless(["ender_pearl", "blaze_powder"], "ender_eye"))
        r.append(shaped([" # ", "#R#", " # "], ["#": "iron_ingot", "R": "redstone"], "compass"))
        r.append(shaped([" # ", "#R#", " # "], ["#": "gold_ingot", "R": "redstone"], "clock"))
        r.append(shapeless(["bowl", "beetroot", "beetroot", "beetroot", "beetroot", "beetroot", "beetroot"], "beetroot_soup"))
        r.append(shaped(["P", "T"], ["P": "carved_pumpkin", "T": "torch"], "jack_o_lantern"))
        r.append(shaped(["###", "###", "###"], ["#": "netherite_ingot"], "netherite_block"))
        r.append(shapeless(["netherite_block"], "netherite_ingot", 9))
        for (n, _) in BlockRegistry.colors {
            r.append(shaped(["WWW", "PPP"], ["W": "\(n)_wool", "P": "#planks"], "\(n)_bed"))
        }
        // Dyes from flowers and other sources, mixing, and dyeing wool / carpets / terracotta.
        let dyeSources: [(String, String, Int)] = [
            ("poppy", "red_dye", 1), ("red_tulip", "red_dye", 1), ("rose_bush", "red_dye", 2), ("beetroot", "red_dye", 1),
            ("dandelion", "yellow_dye", 1), ("sunflower", "yellow_dye", 2), ("cornflower", "blue_dye", 1), ("lapis_lazuli", "blue_dye", 1),
            ("bone_meal", "white_dye", 1), ("lily_of_the_valley", "white_dye", 1), ("ink_sac", "black_dye", 1), ("wither_rose", "black_dye", 1),
            ("cocoa_beans", "brown_dye", 1), ("blue_orchid", "light_blue_dye", 1), ("allium", "magenta_dye", 1), ("lilac", "magenta_dye", 2),
            ("orange_tulip", "orange_dye", 1), ("torchflower", "orange_dye", 1), ("pink_tulip", "pink_dye", 1), ("peony", "pink_dye", 2),
            ("pink_petals", "pink_dye", 1), ("azure_bluet", "light_gray_dye", 1), ("oxeye_daisy", "light_gray_dye", 1), ("white_tulip", "light_gray_dye", 1),
            ("pitcher_plant", "cyan_dye", 2),
        ]
        for (src, dye, n) in dyeSources { r.append(shapeless([src], dye, n)) }
        let mixes: [([String], String, Int)] = [
            (["green_dye", "white_dye"], "lime_dye", 2), (["blue_dye", "green_dye"], "cyan_dye", 2), (["blue_dye", "white_dye"], "light_blue_dye", 2),
            (["purple_dye", "pink_dye"], "magenta_dye", 2), (["blue_dye", "red_dye", "pink_dye"], "magenta_dye", 3), (["red_dye", "yellow_dye"], "orange_dye", 2),
            (["red_dye", "white_dye"], "pink_dye", 2), (["red_dye", "blue_dye"], "purple_dye", 2), (["black_dye", "white_dye"], "gray_dye", 2),
            (["gray_dye", "white_dye"], "light_gray_dye", 2), (["black_dye", "white_dye", "white_dye"], "light_gray_dye", 3),
        ]
        for (ings, out, n) in mixes { r.append(shapeless(ings, out, n)) }
        for (c, _) in BlockRegistry.colors where c != "white" {
            r.append(shapeless(["\(c)_dye", "white_wool"], "\(c)_wool"))
            r.append(shaped(["###", "#D#", "###"], ["#": "terracotta", "D": "\(c)_dye"], "\(c)_terracotta", 8))
            r.append(shaped(["###", "#D#", "###"], ["#": "white_carpet", "D": "\(c)_dye"], "\(c)_carpet", 8))
        }
        r.append(shaped(["  #", " #S", "# S"], ["#": "stick", "S": "string"], "fishing_rod"))
        r.append(shaped(["F", "R"], ["F": "fishing_rod", "R": "carrot"], "carrot_on_a_stick"))
        r.append(shaped(["F", "R"], ["F": "fishing_rod", "R": "warped_fungus"], "warped_fungus_on_a_stick"))
        r.append(shaped(["W#W", "WWW", " W "], ["W": "#planks", "#": "iron_ingot"], "shield"))
        r.append(shaped(["#T#", "S$S", " # "], ["#": "stick", "T": "tripwire_hook", "S": "string", "$": "iron_ingot"], "crossbow"))
        r.append(shaped(["SS ", "SB ", "  S"], ["S": "string", "B": "slime_ball"], "lead", 2))
        r.append(shaped(["L L", "LLL", "L L"], ["L": "leather"], "leather_horse_armor"))
        r.append(shaped(["D#D", "DND", "DDD"], ["D": "diamond", "#": "netherite_upgrade_smithing_template", "N": "netherrack"], "netherite_upgrade_smithing_template", 2))
        for t in Smithing.trims {
            let tpl = "\(t)_armor_trim_smithing_template"
            r.append(shaped(["D#D", "DBD", "DDD"], ["D": "diamond", "#": tpl, "B": Smithing.trimBase[t] ?? "cobblestone"], tpl, 2))
        }
        for (c, _) in BlockRegistry.colors {
            r.append(shapeless(["\(c)_dye", "sand", "sand", "sand", "sand", "gravel", "gravel", "gravel", "gravel"], "\(c)_concrete_powder", 8))
            r.append(shaped(["###", "#D#", "###"], ["#": "glass", "D": "\(c)_dye"], "\(c)_stained_glass", 8))
            r.append(shaped(["###", "###"], ["#": "\(c)_stained_glass"], "\(c)_stained_glass_pane", 16))
            r.append(shapeless(["candle", "\(c)_dye"], "\(c)_candle"))
            r.append(shapeless(["shulker_box", "\(c)_dye"], "\(c)_shulker_box"))
        }
        r.append(shaped(["S", "H"], ["S": "string", "H": "honeycomb"], "candle"))
        r.append(shaped(["S", "#", "S"], ["S": "shulker_shell", "#": "chest"], "shulker_box"))
        r.append(shaped(["###", "#E#", "###"], ["#": "obsidian", "E": "ender_eye"], "ender_chest"))
        r.append(shapeless(["chest", "tripwire_hook"], "trapped_chest"))
        r.append(shaped(["MMM", "SES", "WWW"], ["M": "milk_bucket", "S": "sugar", "E": "egg", "W": "wheat"], "cake"))
        for (i, st) in Copper.stages.enumerated() {
            for waxed in [false, true] {
                let blk = Copper.name("block", stage: i, waxed: waxed)
                r.append(shaped(["##", "##"], ["#": blk], Copper.name("cut_copper", stage: i, waxed: waxed), 4))
                r.append(shaped(["#", "#"], ["#": Copper.name("cut_copper_slab", stage: i, waxed: waxed)], Copper.name("chiseled_copper", stage: i, waxed: waxed)))
                r.append(shaped([" # ", "# #", " # "], ["#": blk], Copper.name("copper_grate", stage: i, waxed: waxed), 4))
                r.append(shaped([" # ", "#B#", " R "], ["#": blk, "B": "blaze_rod", "R": "redstone"], Copper.name("copper_bulb", stage: i, waxed: waxed), 4))
                r.append(shaped(["#  ", "## ", "###"], ["#": Copper.name("cut_copper", stage: i, waxed: waxed)], Copper.name("cut_copper_stairs", stage: i, waxed: waxed), 4))
                r.append(shaped(["###"], ["#": Copper.name("cut_copper", stage: i, waxed: waxed)], Copper.name("cut_copper_slab", stage: i, waxed: waxed), 6))
                if waxed {
                    for f in Copper.forms { r.append(shapeless([Copper.name(f, stage: i, waxed: false), "honeycomb"], Copper.name(f, stage: i, waxed: true))) }
                }
            }
            _ = st
        }
        r.append(shaped(["###", "###", "###"], ["#": "copper_ingot"], "copper_block"))
        r.append(shapeless(["copper_block"], "copper_ingot", 9))
        r.append(shaped(["#", "#", "#"], ["#": "copper_ingot"], "lightning_rod"))
        r.append(shaped(["##", "##"], ["#": "honeycomb"], "honeycomb_block"))
        r.append(shaped(["H", "B"], ["H": "heavy_core", "B": "breeze_rod"], "mace"))
        r.append(shaped(["F", "C", "S"], ["F": "feather", "C": "copper_ingot", "S": "stick"], "brush"))
        r.append(shaped(["# #", "#S#", "# #"], ["#": "bamboo", "S": "string"], "scaffolding", 6))
        r.append(shaped(["N", "I", "N"], ["N": "iron_nugget", "I": "iron_ingot"], "chain"))
        r.append(shaped([" S ", "SCS", "LLL"], ["S": "stick", "C": "#coals", "L": "#logs"], "campfire"))
        r.append(shaped([" S ", "SCS", "LLL"], ["S": "stick", "C": "soul_sand", "L": "#logs"], "soul_campfire"))
        r.append(shaped(["PPP", "HHH", "PPP"], ["P": "#planks", "H": "honeycomb"], "beehive"))
        r.append(shaped(["###", "###", "###"], ["#": "bone_meal"], "bone_block"))
        r.append(shapeless(["bone_block"], "bone_meal", 9))
        r.append(shaped(["###", "###", "###"], ["#": "dried_kelp"], "dried_kelp_block"))
        r.append(shapeless(["dried_kelp_block"], "dried_kelp", 9))
        r.append(shaped(["SSS", "SNS", "SSS"], ["S": "chiseled_stone_bricks", "N": "netherite_ingot"], "lodestone"))
        r.append(shaped(["OOO", "GGG", "OOO"], ["O": "crying_obsidian", "G": "glowstone"], "respawn_anchor"))
        r.append(shaped(["###", "#D#", "###"], ["#": "#planks", "D": "diamond"], "jukebox"))
        r.append(shaped(["NNN", "NHN", "NNN"], ["N": "nautilus_shell", "H": "heart_of_the_sea"], "conduit"))
        r.append(shaped(["I", "S", "#"], ["I": "iron_ingot", "S": "stick", "#": "#planks"], "tripwire_hook", 2))
        r.append(shaped(["ccc", "cRc", "cDc"], ["c": "iron_ingot", "R": "redstone", "D": "dropper"], "crafter"))
        r.append(shaped([" B ", "B B", " B "], ["B": "brick"], "decorated_pot"))
        r.append(shapeless(["torchflower"], "orange_dye"))
        r.append(shapeless(["pitcher_plant"], "cyan_dye", 2))
        for (a, b, n) in [("tuff", "polished_tuff", 1), ("polished_tuff", "tuff_bricks", 4)] {
            r.append(shaped(["##", "##"], ["#": a], b, n == 1 ? 4 : n))
        }
        r.append(shaped(["#", "#"], ["#": "tuff_slab"], "chiseled_tuff"))
        r.append(shaped(["#", "#"], ["#": "tuff_brick_slab"], "chiseled_tuff_bricks"))
        for w in BlockRegistry.doorWoods where Items.has("\(w)_planks") {
            r.append(shaped(["###", "###", " S "], ["#": "\(w)_planks", "S": "stick"], "\(w)_sign", 3))
        }
        r.append(shaped(["SSS", "SLS", "SSS"], ["S": "stick", "L": "leather"], "item_frame"))
        r.append(shapeless(["item_frame", "glow_ink_sac"], "glow_item_frame"))
        r.append(shaped(["A", "C", "C"], ["A": "amethyst_shard", "C": "copper_ingot"], "spyglass"))
        r.append(shaped(["SSS", " S ", "SXS"], ["S": "stick", "X": "smooth_stone_slab"], "armor_stand"))
        for (i, w) in Boats.woods.enumerated() where Items.has("\(w.0)_planks") {
            r.append(shaped(["P P", "PPP"], ["P": "\(w.0)_planks"], Boats.itemKey(i, chest: false)))
            r.append(shapeless([Boats.itemKey(i, chest: false), "chest"], Boats.itemKey(i, chest: true)))
        }
        r.append(shaped(["SSS", "SWS", "SSS"], ["S": "stick", "W": "white_wool"], "painting"))
        r.append(shaped(["PPP", "PCP", "PPP"], ["P": "paper", "C": "compass"], "map"))
        r.append(shapeless(["sugar_cane", "sugar_cane", "sugar_cane"], "paper", 3))
        // Brewing and enchanting.
        r.append(shaped([" B ", "###"], ["B": "blaze_rod", "#": "#stone_tool"], "brewing_stand"))
        r.append(shaped([" B ", "D#D", "###"], ["B": "book", "D": "diamond", "#": "obsidian"], "enchanting_table"))
        r.append(shaped(["# #", " # "], ["#": "glass"], "glass_bottle", 3))
        r.append(shapeless(["spider_eye", "brown_mushroom", "sugar"], "fermented_spider_eye"))
        r.append(shaped(["###", "#M#", "###"], ["#": "gold_nugget", "M": "melon_slice"], "glistering_melon_slice"))
        r.append(shapeless(["blaze_powder", "slime_ball"], "magma_cream"))
        r.append(shapeless(["blaze_powder", "coal", "gunpowder"], "fire_charge", 3))
        r.append(shaped(["GGG", "GSG", "OOO"], ["G": "glass", "S": "nether_star", "O": "obsidian"], "beacon"))
        r.append(shaped(["###", "# #"], ["#": "turtle_scute"], "turtle_helmet"))
        r.append(shapeless(["rabbit_hide", "rabbit_hide", "rabbit_hide", "rabbit_hide"], "leather"))
        r.append(shapeless(["bowl", "cooked_rabbit", "carrot", "baked_potato", "brown_mushroom"], "rabbit_stew"))
        r.append(shapeless(["bowl", "cooked_rabbit", "carrot", "baked_potato", "red_mushroom"], "rabbit_stew"))
        for f in SuspiciousStew.flowers where Items.has(f.0) {
            r.append(shapeless(["bowl", "brown_mushroom", "red_mushroom", f.0], "suspicious_stew_" + f.0))
        }
        for t in Potions.types where !t.effects.isEmpty {
            r.append(shaped(["AAA", "APA", "AAA"], ["A": "arrow", "P": Potions.itemName("lingering_potion", t.key)], Potions.itemName("tipped_arrow", t.key), 8))
        }
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
        "ancient_debris": "netherite_scrap", "sandstone": "smooth_sandstone", "red_sandstone": "smooth_red_sandstone", "kelp": "dried_kelp", "wet_sponge": "sponge", "chorus_fruit": "popped_chorus_fruit", "polished_blackstone_bricks": "cracked_polished_blackstone_bricks",
    ]
    // Additional smelting pairs generated for colour families and the newer items.
    static let smeltingExtra: [String: String] = {
        var m: [String: String] = ["cod": "cooked_cod", "salmon": "cooked_salmon", "rabbit": "cooked_rabbit", "mutton": "cooked_mutton",
                                   "potato": "baked_potato", "kelp": "dried_kelp", "cactus": "green_dye", "sea_pickle": "lime_dye",
                                   "wet_sponge": "sponge", "netherrack": "nether_brick", "ancient_debris": "netherite_scrap",
                                   "nether_gold_ore": "gold_ingot", "nether_quartz_ore": "quartz", "deepslate_lapis_ore": "lapis_lazuli",
                                   "deepslate_redstone_ore": "redstone", "deepslate_emerald_ore": "emerald", "chorus_fruit": "popped_chorus_fruit",
                                   "sandstone": "smooth_sandstone", "red_sandstone": "smooth_red_sandstone", "quartz_block": "smooth_quartz",
                                   "stone_bricks": "cracked_stone_bricks", "basalt": "smooth_basalt", "clay": "terracotta", "glass": "glass",
                                   "acacia_log": "charcoal", "dark_oak_log": "charcoal", "jungle_log": "charcoal", "mangrove_log": "charcoal",
                                   "cherry_log": "charcoal", "iron_sword": "iron_nugget", "golden_sword": "gold_nugget", "resin_clump": "resin_brick"]
        for (c, _) in BlockRegistry.colors { m["\(c)_terracotta"] = "\(c)_glazed_terracotta" }
        return m
    }()

    static func smelt(_ i: ItemID) -> ItemID? {
        if smelting[Items.key(i)] == nil, let r = smeltingExtra[Items.key(i)], Items.has(r), r != Items.key(i) { return Items.id(r) }
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
