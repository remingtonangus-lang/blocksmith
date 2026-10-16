import Foundation

// --fidelitycheck: numbers that must match the reference game (break times, blast resistances, hardness), checked
// without a world so a later edit can't drift them silently (2026-10-05 audit: shears had no speed, a sword sped up
// stone, Mining Fatigue III was 10x too weak, every block's blast resistance was its hardness).
enum FidelityCheck {
    static func run() -> Int32 {
        var fails = 0, n = 0
        func check(_ ok: Bool, _ what: String) {
            n += 1
            if !ok { fails += 1 }
            print("\(ok ? "PASS" : "FAIL") fidelity: \(what)")
        }
        func tool(_ k: String, _ ench: [(Ench, Int)] = []) -> ItemStack? {
            guard Items.has(k) else { return nil }
            var s = ItemStack(Items.id(k), 1)
            s.ench = Enchant.pack(ench)
            return s
        }
        // Seconds to break `block` with `item` (nil = hand) against the reference value, to the tick.
        func secs(_ block: String, _ item: String?, ench: [(Ench, Int)] = [], mul: Float = 1, _ want: Float) {
            guard Blocks.has(block) else { print("fidelity: no block \(block)"); return }
            let t: ItemStack
            if let k = item { guard let s = tool(k, ench) else { print("fidelity: no item \(k)"); return }; t = s } else { t = .empty }
            let got = Mining.breakSeconds(Blocks.id(block), t, onGround: true, inWater: false, mul: mul)
            let label = "\(block) with \(item ?? "hand")\(ench.isEmpty ? "" : " +ench")\(mul != 1 ? " x\(mul)" : "")"
            check(abs(got - want) < 0.026, "\(label): \(String(format: "%.2f", got)) s (reference \(String(format: "%.2f", want)) s)")
        }
        secs("stone", nil, 7.5)
        secs("stone", "wooden_pickaxe", 1.15)
        secs("stone", "diamond_pickaxe", ench: [(.efficiency, 5)], 0.1)
        secs("stone", "diamond_pickaxe", ench: [(.efficiency, 5)], mul: 1.4, 0)               // Haste II: instant
        secs("stone", "diamond_pickaxe", mul: 0.0027, 104.2)                              // Mining Fatigue III
        secs("obsidian", "diamond_pickaxe", 9.4)
        secs("dirt", nil, 0.75)
        secs("oak_log", nil, 3)
        secs("cobweb", "diamond_sword", 0.4)
        secs("oak_leaves", "shears", 0)
        secs("white_wool", "shears", 0.25)
        secs("melon", "diamond_sword", 1)
        secs("dirt", "diamond_sword", 0.75)                                               // a sword is no shovel

        func resist(_ block: String, _ want: Float) {
            guard Blocks.has(block) else { print("fidelity: no block \(block)"); return }
            let got = Blocks.resistance[Int(Blocks.id(block))]
            check(got == want, "\(block) blast resistance \(got) (reference \(want))")
        }
        resist("stone", 6); resist("cobblestone", 6); resist("stone_bricks", 6); resist("deepslate", 6)
        resist("oak_planks", 3); resist("end_stone", 9); resist("obsidian", 1200); resist("dirt", 0.5)
        resist("glass", 0.3); resist("coal_ore", 3); resist("iron_block", 6); resist("sandstone", 0.8)

        func hard(_ block: String, _ want: Float) {
            guard Blocks.has(block) else { print("fidelity: no block \(block)"); return }
            let got = Blocks.hardness[Int(Blocks.id(block))]
            check(got == want, "\(block) hardness \(got) (reference \(want))")
        }
        hard("gold_block", 3); hard("lapis_block", 3); hard("copper_block", 3); hard("iron_block", 5); hard("diamond_block", 5)

        // Fuel (ticks), stack sizes, block drops and smelting XP (fidelity audit round 2).
        func fuel(_ k: String, _ want: Int) {
            guard Items.has(k) else { print("fidelity: no item \(k)"); return }
            let got = Recipes.fuel(Items.id(k))
            check(got == want, "\(k) burns \(got) ticks (reference \(want))")
        }
        fuel("oak_planks", 300); fuel("oak_slab", 150); fuel("stick", 100); fuel("coal", 1600); fuel("bamboo", 50)
        fuel("dried_kelp_block", 4001); fuel("white_wool", 100); fuel("crimson_planks", 0); fuel("torch", 0); fuel("lava_bucket", 20000)
        func stack(_ k: String, _ want: Int) {
            guard Items.has(k) else { print("fidelity: no item \(k)"); return }
            let got = Items.def(Items.id(k)).maxStack
            check(got == want, "\(k) stacks to \(got) (reference \(want))")
        }
        stack("totem_of_undying", 1); stack("red_bed", 1); stack("oak_sign", 16); stack("ender_pearl", 16); stack("cobblestone", 64)
        func drop(_ block: String, _ item: String, _ lo: Int, _ hi: Int) {
            guard Blocks.has(block), Items.has(item), let pick = tool("netherite_pickaxe") else { print("fidelity: no \(block) / \(item)"); return }
            var okAll = true
            for _ in 0..<20 {
                let d = Mining.drops(Blocks.id(block), pick)
                let n = d.filter { $0.item == Items.id(item) }.reduce(0) { $0 + $1.count }
                if n < lo || n > hi || d.contains(where: { $0.item != Items.id(item) }) { okAll = false }
            }
            check(okAll, "\(block) drops \(lo)-\(hi) \(item)")
        }
        drop("nether_quartz_ore", "quartz", 1, 1); drop("nether_gold_ore", "gold_nugget", 2, 6); drop("bookshelf", "book", 3, 3)
        drop("ender_chest", "obsidian", 8, 8); drop("stone", "cobblestone", 1, 1); drop("sea_lantern", "prismarine_crystals", 2, 3)
        if Items.has("iron_ingot") {
            let xp = Recipes.smeltXP(Items.id("iron_ingot"))
            check(abs(xp - 0.7) < 0.001, "iron ingot smelting XP \(xp) (reference 0.7)")
        }

        // Fire odds (ignite, burn) per the reference FireBlock table.
        func fire(_ block: String, _ ig: UInt8, _ burn: UInt8) {
            guard Blocks.has(block) else { print("fidelity: no block \(block)"); return }
            let o = World.fireOdds[Int(Blocks.id(block))]
            check(o.ignite == ig && o.burn == burn, "\(block) fire odds \(o.ignite)/\(o.burn) (reference \(ig)/\(burn))")
        }
        fire("oak_log", 5, 5); fire("oak_planks", 5, 20); fire("oak_leaves", 30, 60); fire("white_wool", 30, 60)
        fire("bookshelf", 30, 20); fire("tnt", 15, 100); fire("hay_block", 60, 20)

        // Hurt invulnerability: within 0.5 s only a bigger hit counts, by the difference.
        // (A pig: a zombie's natural armour rounds damage down at random, which made this flaky.)
        let z = Mob(.pig, at: V3(0, 100, 0))
        let h0 = z.health
        z.hit(from: V3(1, 100, 0), damage: 5, iframes: true)
        z.hit(from: V3(1, 100, 0), damage: 3, iframes: true)
        let h1 = z.health
        z.hit(from: V3(1, 100, 0), damage: 7, iframes: true)
        check(h0 - h1 == 5 && h1 - z.health == 2, "hurt invulnerability: 5, then 3 ignored, then 7 deals 2 (took \(h0 - h1), \(h1 - z.health))")

        print("fidelitycheck: \(n) checks, \(fails) FAILED")
        return fails == 0 && n > 40 ? 0 : 1
    }
}
