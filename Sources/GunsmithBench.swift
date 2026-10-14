import Foundation
import simd

// D31: the gunsmith bench. A workbench (crafting: a smithing table, an anvil and two steel ingots) where guns are
// built from parts. Three parts in three tiers each:
//   part       iron (1)                steel (2)                       fine (3)
//   receiver   4 iron ingots           3 steel, 1 redstone             3 steel, 2 gold, 1 diamond
//   barrel     3 iron ingots           2 steel                         2 steel, 1 diamond
//   stock      4 oak planks            3 dark oak planks, 1 leather    2 dark oak planks, 2 leather, 1 gold
// Using the bench lists the parts to make, then the frames it can assemble (the revolver, the bolt rifle, the
// shotgun, the pistol and the carbine): assembly takes your best receiver, barrel and stock and the gun comes out
// with a rarity from the three tiers (T7 grades, GunGrade): all iron is Common, mixed steel Fine, all steel Rare,
// and all fine parts Elite; the finer the weakest part, the better the roll.
enum GunsmithBench {
    static let key = "gunsmith_bench"
    static let kinds = ["receiver", "barrel", "stock"]
    static let tierNames = ["Iron", "Steel", "Fine"]
    static let costs: [[[(String, Int)]]] = [
        [[("iron_ingot", 4)], [("steel_ingot", 3), ("redstone", 1)], [("steel_ingot", 3), ("gold_ingot", 2), ("diamond", 1)]],
        [[("iron_ingot", 3)], [("steel_ingot", 2)], [("steel_ingot", 2), ("diamond", 1)]],
        [[("oak_planks", 4)], [("dark_oak_planks", 3), ("leather", 1)], [("dark_oak_planks", 2), ("leather", 2), ("gold_ingot", 1)]],
    ]
    static let frames = ["gun_revolver", "gun_kessel", "gun_shotgun", "gun_sidearm", "gun_sturmwind"]
    static var built = 0                                   // (harness)

    static func partKey(_ kind: Int, _ tier: Int) -> String { "gun_\(kinds[kind])_\(tier + 1)" }

    // The best tier of a part kind in the pack (nil: none).
    static func best(_ g: Game, _ kind: Int) -> Int? {
        for t in stride(from: 2, through: 0, by: -1) where Items.has(partKey(kind, t)) && g.inventory.main.countOf(Items.id(partKey(kind, t))) > 0 { return t }
        return nil
    }

    // The grade a gun from parts of tiers (0...2) gets.
    static func grade(_ tiers: [Int]) -> Int {
        let sum = tiers.reduce(0, +)                       // 0 ... 6
        let tier = sum == 0 ? 0 : (sum <= 2 ? 1 : (sum <= 5 ? 2 : 3))
        guard tier > 0 else { return 0 }
        let roll = min(99, 30 + (tiers.min() ?? 0) * 30 + sum * 4)
        return tier * 100 + roll
    }

    static func recipes() -> [Recipe?] {
        [Recipes.shapeless(["smithing_table", "anvil", "steel_ingot", "steel_ingot"], key)]
    }
}

extension ItemRegistry {
    func registerGunParts() {
        let looks: [(String, UInt32)] = [("mechanism", 0x5A5E66), ("rod", 0x3A3D44), ("stick", 0x7A5232)]
        let tint: [UInt32] = [0x9AA0A8, 0x6F7A86, 0xC8A24A]
        for k in 0..<3 { for t in 0..<3 {
            let key = GunsmithBench.partKey(k, t)
            guard !has(key) else { continue }
            var d = ItemDef(key, "\(GunsmithBench.tierNames[t]) \(GunsmithBench.kinds[k].capitalized)")
            d.sprite = Sprite(mask: looks[k].0, base: k == 2 && t == 0 ? looks[k].1 : (k == 2 ? 0x4A3020 : tint[t]), extras: ["c": tint[t]])
            d.maxStack = 16
            add(d)
        } }
    }
}

extension BlockRegistry {
    func registerGunsmithBench() {
        guard !has(GunsmithBench.key) else { return }
        var d = BlockDef(GunsmithBench.key, "Gunsmith Bench")
        d.tex = ["smithing_table_side", "smithing_table_side", "smithing_table_top", "dark_oak_planks", "smithing_table_side", "smithing_table_side"]
        d.hardness = 2.5; d.resistance = 2.5; d.tool = .axe; d.sound = .wood
        add(d)
    }
}

final class GunsmithBenchMenu: ListMenu {
    enum Item { case part(Int, Int), frame(String) }
    var items: [Item] = []
    init(game g: Game) {
        super.init("Gunsmith Bench", game: g)
        subtitle = "Make parts, then assemble a gun from your best ones"
        for k in 0..<3 { for t in 0..<3 where Items.has(GunsmithBench.partKey(k, t)) { items.append(.part(k, t)) } }
        for f in GunsmithBench.frames where Items.has(f) { items.append(.frame(f)) }
        say("Receiver, barrel and stock: the finer the parts, the finer the gun.", good: true)
    }

    func has(_ cost: [(String, Int)]) -> Bool {
        !game.survival || cost.allSatisfy { Items.has($0.0) && game.inventory.main.countOf(Items.id($0.0)) >= $0.1 }
    }
    func name(_ k: String) -> String { Items.has(k) ? Items.def(Items.id(k)).display : k }

    override var rows: [Row] {
        corner = game.survival ? "" : "Creative"
        return items.map { it in
            switch it {
            case .part(let k, let t):
                let c = GunsmithBench.costs[k][t]
                let key = GunsmithBench.partKey(k, t)
                return Row(icon: ItemStack(Items.id(key), 1), name: name(key), detail: c.map { "\($0.1) \(name($0.0))" }.joined(separator: ", "),
                           value: has(c) ? "Make" : "Short", enabled: true, good: has(c))
            case .frame(let f):
                let tiers = (0..<3).map { GunsmithBench.best(game, $0) }
                let ready = !game.survival || !tiers.contains(where: { $0 == nil })
                let detail = ready ? "From " + (0..<3).map { k in GunsmithBench.tierNames[tiers[k] ?? 2].lowercased() + " " + GunsmithBench.kinds[k] }.joined(separator: ", ")
                                   : "Needs a receiver, a barrel and a stock"
                return Row(icon: ItemStack(Items.id(f), 1), name: "Assemble: \(name(f))", detail: detail, value: ready ? "Build" : "Parts", enabled: true, good: ready)
            }
        }
    }

    override func pressed(_ index: Int) {
        guard index < items.count else { return }
        switch items[index] {
        case .part(let k, let t):
            let c = GunsmithBench.costs[k][t]
            guard has(c) else { say("Not enough materials.", good: false); game.sfx(.villagerNo, 0.4); return }
            if game.survival { for (key, n) in c { _ = game.inventory.main.remove(Items.id(key), n) } }
            let rest = game.inventory.add(ItemStack(Items.id(GunsmithBench.partKey(k, t)), 1)); if !rest.isEmpty { game.dropItem(rest) }
            game.sfx(.anvil, 0.5)
            say("Made a \(name(GunsmithBench.partKey(k, t))).", good: true)
        case .frame(let f):
            var tiers: [Int] = []
            for k in 0..<3 {
                guard let t = GunsmithBench.best(game, k) ?? (game.survival ? nil : 2) else {
                    say("You need a \(GunsmithBench.kinds[k]) first.", good: false); game.sfx(.villagerNo, 0.4); return
                }
                tiers.append(t)
            }
            if game.survival { for k in 0..<3 { _ = game.inventory.main.remove(Items.id(GunsmithBench.partKey(k, tiers[k])), 1) } }
            var out = ItemStack(Items.id(f), 1)
            out.grade = GunsmithBench.grade(tiers)
            out.tag = Guns.magSize(out)
            let rest = game.inventory.add(out); if !rest.isEmpty { game.dropItem(rest) }
            GunsmithBench.built += 1
            game.sfx(.anvil, 0.7)
            say("Built a \(out.displayName).", good: true)
        }
    }
}
