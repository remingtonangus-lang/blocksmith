import Foundation
import simd

// Smithing table (duskium upgrade, armor trims), stonecutter and grindstone.

enum Smithing {
    static let trims = ["sentry", "dune", "coast", "wild", "ward", "eye", "vex", "tide", "snout", "rib", "spire", "wayfinder",
                        "shaper", "silence", "raiser", "host", "flow", "bolt"]
    static let trimMaterials = ["iron_ingot", "copper_ingot", "gold_ingot", "lapis_lazuli", "emerald", "diamond", "netherite_ingot",
                                "redstone", "amethyst_shard", "quartz"]
    // Duplication base block per template (reference recipes).
    static let trimBase: [String: String] = [
        "sentry": "cobblestone", "dune": "sandstone", "coast": "cobblestone", "wild": "mossy_cobblestone", "ward": "cobbled_deepslate",
        "eye": "end_stone", "vex": "cobblestone", "tide": "prismarine", "snout": "blackstone", "rib": "netherrack", "spire": "purpur_block",
        "wayfinder": "terracotta", "shaper": "terracotta", "silence": "cobbled_deepslate", "raiser": "terracotta", "host": "terracotta",
        "flow": "breeze_rod", "bolt": "copper_block",
    ]

    // Trim is packed into ItemStack.tag for armor: pattern + 1 in the low byte, material + 1 in the next.
    static func trimName(_ s: ItemStack) -> String? {
        guard s.def.armorSlot != nil, s.tag != 0 else { return nil }
        let p = (s.tag & 0xFF) - 1, m = ((s.tag >> 8) & 0xFF) - 1
        guard p >= 0 && p < trims.count && m >= 0 && m < trimMaterials.count else { return nil }
        let mat = Items.name(Items.id(trimMaterials[m])).replacingOccurrences(of: " Ingot", with: "").replacingOccurrences(of: " Shard", with: "")
        return "\(trims[p] == "vex" ? "Hexling" : trims[p].capitalized) Armor Trim (\(mat))"
    }

    static func result(template: ItemStack, base: ItemStack, addition: ItemStack) -> ItemStack? {
        guard !template.isEmpty, !base.isEmpty, !addition.isEmpty else { return nil }
        let t = Items.key(template.item)
        if t == "netherite_upgrade_smithing_template" {
            guard Items.key(addition.item) == "netherite_ingot" else { return nil }
            let k = Items.key(base.item)
            guard k.hasPrefix("diamond_") else { return nil }
            let up = "netherite_" + k.dropFirst("diamond_".count)
            guard Items.has(up) else { return nil }
            var out = base
            out.item = Items.id(up)
            out.count = 1
            return out
        }
        guard t.hasSuffix("_armor_trim_smithing_template"), base.def.armorSlot != nil, Items.key(base.item) != "elytra",
              let p = trims.firstIndex(of: String(t.dropLast("_armor_trim_smithing_template".count))),
              let m = trimMaterials.firstIndex(of: Items.key(addition.item)) else { return nil }
        var out = base
        out.count = 1
        out.tag = (p + 1) | ((m + 1) << 8)
        return out
    }
}

final class SmithingMenu: Menu {
    let box = ItemContainer(3)
    let out = ItemContainer(1)
    init(game: Game) {
        super.init("Upgrade Gear", game: game)
        slots.append(MenuSlot(8, 48, box, 0))
        slots.append(MenuSlot(26, 48, box, 1))
        slots.append(MenuSlot(44, 48, box, 2))
        slots.append(MenuSlot(98, 48, out, 0, .result))
        addPlayerInventory()
    }
    override func changed() {
        out[0] = Smithing.result(template: box[0], base: box[1], addition: box[2]) ?? .empty
    }
    override func takeResult(_ slot: MenuSlot) -> ItemStack? {
        guard let r = Smithing.result(template: box[0], base: box[1], addition: box[2]) else { return nil }
        if Items.key(box[0].item).hasSuffix("_armor_trim_smithing_template") { game.achieve("trim") }
        for i in 0..<3 { var s = box[i]; s.count -= 1; box[i] = s.count > 0 ? s : .empty }
        game.sfx(.anvil, 0.5)
        changed()
        return r
    }
    override func onClose() { returnAll(box) }
    func returnAll(_ c: ItemContainer) {
        for i in 0..<c.count where !c[i].isEmpty {
            let rest = game.inventory.add(c[i]); if !rest.isEmpty { game.dropItem(rest) }
            c[i] = .empty
        }
    }
}

// Stonecutter recipes, derived from the crafting recipes of stone-type blocks (one input block ->
// stairs 1, slabs 2, walls 1, bricks / polished 1) and chained one step further, like the reference list.
enum Stonecutting {
    static let recipes: [ItemID: [(ItemID, Int)]] = {
        var direct: [ItemID: [(ItemID, Int)]] = [:]
        for r in Recipes.all where r.shapeless.isEmpty {
            let ings = Set(r.cells.compactMap { $0 })
            guard ings.count == 1, let ing = ings.first, !ing.hasPrefix("#"), Items.has(ing) else { continue }
            let src = Items.id(ing)
            guard let sb = Items.def(src).block, let ob = r.result.def.block, src != r.result.item else { continue }
            guard Blocks.def(sb).sound == .stone || Items.key(src).contains("copper"), Blocks.def(ob).sound == .stone || Items.key(r.result.item).contains("copper") else { continue }
            let used = r.cells.compactMap { $0 }.count
            let shape = Blocks.shape[Int(ob)]
            let n = shape == "slab" ? 2 : (shape == "stairs" || shape.isEmpty || Blocks.render[Int(ob)] == RenderType.connect.rawValue ? 1 : max(1, r.result.count / used))
            if used == 4 && shape.isEmpty && r.result.count == 4 { direct[src, default: []].append((r.result.item, 1)); continue }
            direct[src, default: []].append((r.result.item, n))
        }
        var all = direct
        for (src, outs) in direct {
            for (mid, n1) in outs where n1 == 1 {
                for (o2, n2) in direct[mid] ?? [] where o2 != src && !(all[src]?.contains { $0.0 == o2 } ?? false) {
                    all[src, default: []].append((o2, n2))
                }
            }
        }
        return all.mapValues { $0.sorted { $0.0 < $1.0 } }
    }()
}

final class StonecutterMenu: Menu {
    let input = ItemContainer(1)
    let out = ItemContainer(1)
    var options: [(ItemID, Int)] = []          // the page on show (12)
    var all: [(ItemID, Int)] = []              // every cut of the input (deeprock has more than 12: they were cut off)
    var page = 0
    var pages: Int { max(1, (all.count + 11) / 12) }
    var selected = -1
    private var more: MenuSlot?
    init(game: Game) {
        super.init("Stonecutter", game: game)
        slots.append(MenuSlot(20, 33, input, 0))
        for i in 0..<12 {
            let b = MenuSlot(52 + (i % 4) * 16, 15 + (i / 4) * 18, nil, 0, .button(i))
            b.w = 14; b.h = 16
            slots.append(b)
        }
        let more = MenuSlot(120, 51, nil, 0, .button(12))         // next page (drawn only when there is one)
        more.w = 10; more.h = 16
        more.hidden = true
        self.more = more
        slots.append(more)
        slots.append(MenuSlot(143, 33, out, 0, .result))
        addPlayerInventory()
    }
    override func buttonPressed(_ i: Int) {
        if i == 12 { if pages > 1 { page = (page + 1) % pages; selected = -1; changed() }; return }
        guard i < options.count else { return }
        selected = i
        changed()
    }
    override func changed() {
        let s = input[0]
        let opts = s.isEmpty ? [] : (Stonecutting.recipes[s.item] ?? [])
        if opts.map({ $0.0 }) != all.map({ $0.0 }) { selected = -1; page = 0 }
        all = opts
        options = Array(all.dropFirst(page * 12).prefix(12))
        more?.hidden = pages <= 1
        out[0] = selected >= 0 && selected < options.count && !s.isEmpty ? ItemStack(options[selected].0, options[selected].1) : .empty
    }
    override func takeResult(_ slot: MenuSlot) -> ItemStack? {
        guard !out[0].isEmpty else { return nil }
        let r = out[0]
        var s = input[0]; s.count -= 1; input[0] = s.count > 0 ? s : .empty
        game.sfx(.smithing, 0.6)
        changed()
        return r
    }
    override func onClose() {
        if !input[0].isEmpty { let rest = game.inventory.add(input[0]); if !rest.isEmpty { game.dropItem(rest) }; input[0] = .empty }
    }
}

// Grindstone: strips non-curse enchantments (returning some XP) or merges two damaged copies (+5%).
final class GrindstoneMenu: Menu {
    let box = ItemContainer(2)
    let out = ItemContainer(1)
    init(game: Game) {
        super.init("Repair & Disenchant", game: game)
        slots.append(MenuSlot(49, 19, box, 0))
        slots.append(MenuSlot(49, 40, box, 1))
        slots.append(MenuSlot(129, 34, out, 0, .result))
        addPlayerInventory()
    }
    func compute() -> (ItemStack, Int)? {
        let a = box[0], b = box[1]
        if a.isEmpty && b.isEmpty { return nil }
        if !a.isEmpty && !b.isEmpty {
            guard a.item == b.item, a.def.durability > 0 else { return nil }
            var o = a
            let d = a.def.durability
            let remain = (d - a.damage) + (d - b.damage) + d * 5 / 100
            o.damage = max(0, d - remain)
            let curses = (Enchant.list(a) + Enchant.list(b)).filter { Enchant.def($0.0).curse }
            o.ench = Enchant.pack(curses)
            o.repairCost = Enchant.list(o).reduce(0) { r, _ in r * 2 + 1 }      // rebuilt from what's left (each curse kept)
            let xp = (Enchant.list(a) + Enchant.list(b)).filter { !Enchant.def($0.0).curse }.reduce(0) { $0 + Enchant.def($1.0).minCost($1.1) }
            return (o, xp)
        }
        let s = a.isEmpty ? b : a
        guard s.ench != 0 else { return nil }
        let keep = Enchant.list(s).filter { Enchant.def($0.0).curse }
        var o = s
        o.ench = Enchant.pack(keep)
        o.repairCost = keep.reduce(0) { r, _ in r * 2 + 1 }      // prior work rebuilt from the curses kept (reference; it was 0)
        if Items.key(s.item) == "enchanted_book" && keep.isEmpty { o = ItemStack(Items.id("book"), 1) }
        let xp = Enchant.list(s).filter { !Enchant.def($0.0).curse }.reduce(0) { $0 + Enchant.def($1.0).minCost($1.1) }
        return (o, xp)
    }
    override func changed() { out[0] = compute()?.0 ?? .empty }
    override func takeResult(_ slot: MenuSlot) -> ItemStack? {
        guard case let (o, xp)? = compute() else { return nil }
        box[0] = .empty; box[1] = .empty
        // XP back: between half and all of the (minimum) enchantment cost.
        if xp > 0 { game.addXP(Rand.int(in: (xp + 1) / 2...max((xp + 1) / 2, xp))) }
        game.sfx(.grindstone, 0.7)
        changed()
        return o
    }
    override func onClose() {
        for i in 0..<2 where !box[i].isEmpty { let rest = game.inventory.add(box[i]); if !rest.isEmpty { game.dropItem(rest) }; box[i] = .empty }
    }
}
