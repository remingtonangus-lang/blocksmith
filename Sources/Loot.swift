import Foundation

// Mining speed, harvestability and block drops (numbers follow the reference game's rules).
enum Mining {
    static func item(_ n: String) -> ItemID { Items.id(n) }

    static func correctTool(_ b: BlockID, _ tool: ItemStack) -> Bool {
        if tool.isEmpty { return false }
        let t = tool.def.tool
        let need = ToolType(rawValue: Blocks.tool[Int(b)]) ?? .none
        return need != .none && t == need
    }

    static func canHarvest(_ b: BlockID, _ tool: ItemStack) -> Bool {
        if !Blocks.requiresTool[Int(b)] { return true }
        return correctTool(b, tool) && tool.def.tier >= Int(Blocks.harvestLevel[Int(b)])
    }

    // Seconds to break a block (0 = instant, .infinity = unbreakable).
    static func breakSeconds(_ b: BlockID, _ tool: ItemStack, onGround: Bool, inWater: Bool) -> Float {
        let h = Blocks.hardness[Int(b)]
        if h < 0 { return .infinity }
        if h == 0 { return 0 }
        var speed: Float = 1
        let key = Blocks.key(b)
        if correctTool(b, tool) {
            speed = tool.def.toolSpeed
            let eff = Enchant.level(.efficiency, tool)
            if eff > 0 { speed += Float(eff * eff + 1) }
        }
        else if !tool.isEmpty && tool.def.tool == .sword { speed = key == "cobweb" ? 15 : 1.5 }
        else if !tool.isEmpty && tool.def.tool == .shears && key.hasSuffix("leaves") { speed = 15 }
        if inWater { speed /= 5 }
        if !onGround { speed /= 5 }
        let perTick = speed / h / (canHarvest(b, tool) ? 30 : 100)
        if perTick >= 1 { return 0 }
        return ceilf(1 / perTick) / 20
    }

    static let noSilk: Set<String> = ["wheat", "carrots", "potatoes", "beetroots", "nether_wart", "spawner", "budding_amethyst",
                                      "reinforced_deepslate", "cocoa", "sweet_berry_bush", "torchflower_crop", "pitcher_crop", "melon_stem",
                                      "pumpkin_stem", "redstone_wire", "piston_head", "end_portal", "end_gateway", "cave_vines", "chorus_plant"]
    static let fortuneOres: Set<String> = ["coal_ore", "deepslate_coal_ore", "diamond_ore", "deepslate_diamond_ore", "emerald_ore",
                                           "deepslate_emerald_ore", "nether_quartz_ore", "lapis_ore", "deepslate_lapis_ore", "iron_ore",
                                           "deepslate_iron_ore", "gold_ore", "deepslate_gold_ore", "copper_ore", "deepslate_copper_ore",
                                           "nether_gold_ore", "redstone_ore", "deepslate_redstone_ore"]

    // Drops with Silk Touch and Fortune applied (reference ore / plant formulas).
    static func enchantedDrops(_ b: BlockID, _ tool: ItemStack) -> [ItemStack] {
        guard !tool.isEmpty, tool.ench != 0 else { return drops(b, tool) }
        let key = Blocks.key(Blocks.groupBase[Int(b)])
        if Enchant.level(.silkTouch, tool) > 0 && canHarvest(b, tool) && !noSilk.contains(key) && !Blocks.isLiquid(b) {
            if let i = Items.item(forBlock: b) { return [ItemStack(i, 1)] }
        }
        var out = drops(b, tool)
        let f = Enchant.level(.fortune, tool)
        guard f > 0 else { return out }
        if fortuneOres.contains(key) {
            if key.contains("redstone") || key.contains("lapis") || key.contains("copper") {
                for i in out.indices { out[i].count += Int.random(in: 0...f) }       // uniform bonus
            } else {
                let mult = max(1, Int.random(in: 0..<(f + 2)))                    // ore bonus: x1..x(f+1)
                for i in out.indices { out[i].count *= mult }
            }
        } else if key == "glowstone" {
            for i in out.indices { out[i].count = min(4, out[i].count + Int.random(in: 0...f)) }
        } else if key == "melon" {
            for i in out.indices { out[i].count = min(9, out[i].count + Int.random(in: 0...f)) }
        } else if key == "gravel" && !out.isEmpty && Items.key(out[0].item) == "gravel" {
            if Float.random(in: 0..<1) < [0.1, 0.14285715, 0.25, 1.0][min(3, f)] - 0.1 { out = [ItemStack(item("flint"), 1)] }
        } else if ["wheat", "beetroots"].contains(key) || ["carrots", "potatoes"].contains(key) {
            let seed = key == "wheat" ? "wheat_seeds" : (key == "beetroots" ? "beetroot_seeds" : (key == "carrots" ? "carrot" : "potato"))
            let stage = Int(b - Blocks.groupBase[Int(b)])
            if stage == (key == "beetroots" ? 3 : 7) {
                for i in out.indices where Items.key(out[i].item) == seed {
                    for _ in 0..<f where Float.random(in: 0..<1) < 0.5714 { out[i].count += 1 }
                }
            }
        }
        return out
    }

    static func drops(_ b: BlockID, _ tool: ItemStack) -> [ItemStack] {
        if !canHarvest(b, tool) { return [] }
        let key = Blocks.key(b)
        let shears = !tool.isEmpty && tool.def.tool == .shears
        func one(_ n: String, _ c: Int = 1) -> [ItemStack] { [ItemStack(item(n), c)] }
        func rnd(_ a: Int, _ b: Int) -> Int { Int.random(in: a...b) }
        // Crops: drops by growth stage (seeds roll binomially at full growth, as in the reference game).
        let base = Blocks.groupBase[Int(b)]
        let gkey = Blocks.key(base), stage = Int(b - base)
        func binom(_ n: Int, _ p: Float) -> Int { (0..<n).reduce(0) { a, _ in a + (Float.random(in: 0..<1) < p ? 1 : 0) } }
        switch gkey {
        case "wheat":
            return stage == 7 ? one("wheat") + one("wheat_seeds", 1 + binom(3, 0.5714)) : one("wheat_seeds")
        case "carrots": return one("carrot", stage == 7 ? 1 + binom(3, 0.5714) : 1)
        case "potatoes":
            var out = one("potato", stage == 7 ? 1 + binom(3, 0.5714) : 1)
            if stage == 7 && Items.has("poisonous_potato") && Float.random(in: 0..<1) < 0.02 { out += one("poisonous_potato") }
            return out
        case "beetroots":
            return stage == 3 ? one("beetroot") + one("beetroot_seeds", 1 + binom(3, 0.5714)) : one("beetroot_seeds")
        case "nether_wart": return one("nether_wart", stage == 3 ? rnd(2, 4) : 1)
        case "tripwire": return one("string")
        case "composter": return one("composter") + (stage == 8 ? one("bone_meal") : [])
        default: break
        }
        switch key {
        case "stone": return one("cobblestone")
        case "deepslate": return one("cobbled_deepslate")
        case "grass_block", "snowy_grass_block": return one("dirt")
        case "coal_ore", "deepslate_coal_ore": return one("coal")
        case "iron_ore", "deepslate_iron_ore": return one("raw_iron")
        case "gold_ore", "deepslate_gold_ore": return one("raw_gold")
        case "copper_ore", "deepslate_copper_ore": return one("raw_copper", rnd(2, 5))
        case "diamond_ore", "deepslate_diamond_ore": return one("diamond")
        case "emerald_ore": return one("emerald")
        case "lapis_ore", "deepslate_lapis_ore": return one("lapis_lazuli", rnd(4, 9))
        case "redstone_ore", "deepslate_redstone_ore": return one("redstone", rnd(4, 5))
        case "glowstone": return one("glowstone_dust", rnd(2, 4))
        case "clay": return one("clay_ball", 4)
        case "snow_block": return one("snowball", 4)
        case "glass", "spawner", "glass_pane": return []
        case "fern":
            if shears { return one(key) }
            return Float.random(in: 0..<1) < 0.125 ? one("wheat_seeds") : []
        case "tall_grass", "large_fern", "dead_bush", "seagrass", "vine":
            return shears ? one(Blocks.key(Blocks.groupBase[Int(b)])) : (key == "dead_bush" ? one("stick", rnd(0, 2)) : [])
        case "melon": return one("melon_slice", rnd(3, 7))
        case "creaking_heart": return one("resin_clump", rnd(1, 3))
        case "sweet_berry_bush_2": return one("sweet_berries", rnd(1, 2))
        case "sweet_berry_bush_3": return one("sweet_berries", rnd(2, 3))
        case "budding_amethyst", "reinforced_deepslate", "cave_vines", "sculk_shrieker": return key == "cave_vines" ? one("glow_berries") : []
        case "amethyst_cluster": return one("amethyst_shard", 4)
        case "ice", "packed_ice", "blue_ice", "kelp", "bubble_coral", "tube_coral", "brain_coral", "fire_coral", "horn_coral": return key == "kelp" ? one("kelp") : []
        case "snow": return one("snowball", 1)
        case "brown_mushroom_block": return Float.random(in: 0..<1) < 0.15 ? one("brown_mushroom", rnd(1, 2)) : []
        case "red_mushroom_block": return Float.random(in: 0..<1) < 0.15 ? one("red_mushroom", rnd(1, 2)) : []
        case _ where key.hasPrefix("redstone_wire"): return one("redstone")
        case _ where key.hasPrefix("piston_head"): return []
        case "chorus_plant": return Float.random(in: 0..<1) < 0.5 ? one("chorus_fruit") : []
        case "gilded_blackstone": return Float.random(in: 0..<1) < 0.1 ? one("gold_nugget", rnd(2, 5)) : one("gilded_blackstone")
        case "gravel": return Float.random(in: 0..<1) < 0.1 ? one("flint") : one("gravel")
        case "short_grass":
            if shears { return one("short_grass") }
            return Float.random(in: 0..<1) < 0.125 ? one("wheat_seeds") : []
        case _ where key.hasSuffix("_leaves") && !key.hasPrefix("crimson") && !key.hasPrefix("warped"):
            if shears { return one(key) }
            var out: [ItemStack] = []
            let sap = key == "mangrove_leaves" ? "" : key.replacingOccurrences(of: "leaves", with: "sapling")
            let sapChance: Float = key == "jungle_leaves" ? 0.025 : 0.05
            if !sap.isEmpty && Items.has(sap) && Float.random(in: 0..<1) < sapChance { out += one(sap) }
            if Float.random(in: 0..<1) < 0.02 { out += one("stick", rnd(1, 2)) }
            if (key == "oak_leaves" || key == "dark_oak_leaves") && Float.random(in: 0..<1) < 0.005 { out += one("apple") }
            return out
        default:
            if let i = Items.item(forBlock: b) { return [ItemStack(i, 1)] }
            return []
        }
    }
}
