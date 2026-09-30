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
        if correctTool(b, tool) { speed = tool.def.toolSpeed }
        else if !tool.isEmpty && tool.def.tool == .sword { speed = key == "cobweb" ? 15 : 1.5 }
        else if !tool.isEmpty && tool.def.tool == .shears && key.hasSuffix("leaves") { speed = 15 }
        if inWater { speed /= 5 }
        if !onGround { speed /= 5 }
        let perTick = speed / h / (canHarvest(b, tool) ? 30 : 100)
        if perTick >= 1 { return 0 }
        return ceilf(1 / perTick) / 20
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
        case "glass": return []
        case "gravel": return Float.random(in: 0..<1) < 0.1 ? one("flint") : one("gravel")
        case "short_grass":
            if shears { return one("short_grass") }
            return Float.random(in: 0..<1) < 0.125 ? one("wheat_seeds") : []
        case "oak_leaves", "birch_leaves", "spruce_leaves":
            if shears { return one(key) }
            var out: [ItemStack] = []
            let sap = key.replacingOccurrences(of: "leaves", with: "sapling")
            if Float.random(in: 0..<1) < 0.05 { out += one(sap) }
            if Float.random(in: 0..<1) < 0.02 { out += one("stick", rnd(1, 2)) }
            if key == "oak_leaves" && Float.random(in: 0..<1) < 0.005 { out += one("apple") }
            return out
        default:
            if let i = Items.item(forBlock: b) { return [ItemStack(i, 1)] }
            return []
        }
    }
}
