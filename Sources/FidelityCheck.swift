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

        print("fidelitycheck: \(n) checks, \(fails) FAILED")
        return fails == 0 && n > 20 ? 0 : 1
    }
}
