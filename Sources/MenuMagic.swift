import Foundation
import simd

// Brewing stand, enchanting table and anvil screens.

final class BrewingMenu: Menu {
    let be: BlockEntity
    init(game: Game, entity: BlockEntity) {
        be = entity
        super.init("Brewing Stand", game: game)
        let bottle: (ItemStack) -> Bool = { s in
            Potions.potion(of: s.item).map { $0.form < 3 } ?? (Items.key(s.item) == "glass_bottle")
        }
        for (i, p) in [(56, 51), (79, 58), (102, 51)].enumerated() {
            let sl = MenuSlot(p.0, p.1, be.container, i)
            sl.filter = bottle
            sl.limit = 1
            slots.append(sl)
        }
        let ing = MenuSlot(79, 17, be.container, 3)
        ing.filter = { Potions.isIngredient($0.item) }
        slots.append(ing)
        let fuel = MenuSlot(17, 17, be.container, 4, .fuel)
        fuel.filter = { Items.key($0.item) == "blaze_powder" }
        slots.append(fuel)
        addPlayerInventory()
    }
    override func quickMoveTargets(from: MenuSlot) -> [MenuSlot] {
        if from.isPlayerInv {
            let t = slots.prefix(5).filter { $0.accepts(from.stack) }
            if !t.isEmpty { return Array(t) }
            return from.isHotbar ? slots.filter { $0.isPlayerInv && !$0.isHotbar } : slots.filter { $0.isHotbar }
        }
        return super.quickMoveTargets(from: from)
    }
}

final class EnchantMenu: Menu {
    let pos: IVec3
    let box = ItemContainer(2)          // 0 item, 1 lapis
    var costs = [0, 0, 0]
    var clues: [(Ench, Int)?] = [nil, nil, nil]
    var shelves = 0

    init(game: Game, at p: IVec3) {
        pos = p
        super.init("Enchant", game: game)
        let item = MenuSlot(15, 47, box, 0)
        item.limit = 1
        slots.append(item)
        let lapis = MenuSlot(35, 47, box, 1)
        lapis.filter = { Items.key($0.item) == "lapis_lazuli" }
        slots.append(lapis)
        for i in 0..<3 {
            let b = MenuSlot(60, 14 + 19 * i, nil, 0, .button(i))
            b.w = 106; b.h = 17
            slots.append(b)
        }
        addPlayerInventory()
        shelves = Enchant.countBookshelves(game.world, p)
        changed()
    }

    override func changed() {
        let s = box[0]
        costs = [0, 0, 0]
        clues = [nil, nil, nil]
        guard !s.isEmpty, s.ench == 0, s.def.enchantability > 0 else { return }
        var rng = SRng(game.enchantSeed)
        costs = Enchant.tableCosts(bookshelves: shelves, rng: &rng)
        for i in 0..<3 {
            if costs[i] < i + 1 { costs[i] = 0; continue }
            var r = SRng(game.enchantSeed &+ UInt64(i))
            let l = Enchant.select(item: s.item, level: costs[i], rng: &r)
            if let first = l.first { clues[i] = first } else { costs[i] = 0 }
        }
    }

    func available(_ i: Int) -> Bool {
        guard costs[i] > 0 else { return false }
        if !game.survival { return true }
        return game.xpLevel >= costs[i] && game.xpLevel >= i + 1 && box[1].count >= i + 1
    }

    override func buttonPressed(_ i: Int) {
        guard available(i) else { return }
        game.achieve("enchant")
        var s = box[0]
        var r = SRng(game.enchantSeed &+ UInt64(i))
        var l = Enchant.select(item: s.item, level: costs[i], rng: &r)
        if Items.key(s.item) == "book" {
            s = ItemStack(Items.id("enchanted_book"), 1)
            // Books drop one random enchantment when they would get several (reference rule).
            if l.count > 1 { l.remove(at: Rand.int(in: 0..<l.count)) }
        }
        s.ench = Enchant.pack(l)
        box[0] = s
        if game.survival {
            game.xpLevel = max(0, game.xpLevel - (i + 1))
            var lap = box[1]; lap.count -= i + 1; box[1] = lap
        }
        game.enchantSeed = Rand.u64(in: 1...UInt64.max)
        game.sfx(.enchant, 0.7)
        changed()
    }

    override func quickMoveTargets(from: MenuSlot) -> [MenuSlot] {
        if from.isPlayerInv {
            if Items.key(from.stack.item) == "lapis_lazuli" { return [slots[1]] }
            if box[0].isEmpty { return [slots[0]] }
            return from.isHotbar ? slots.filter { $0.isPlayerInv && !$0.isHotbar } : slots.filter { $0.isHotbar }
        }
        return super.quickMoveTargets(from: from)
    }

    override func onClose() {
        for i in 0..<2 where !box[i].isEmpty {
            let rest = game.inventory.add(box[i])
            if !rest.isEmpty { game.dropItem(rest) }
            box[i] = .empty
        }
    }
}

final class AnvilMenu: Menu {
    let pos: IVec3
    let box = ItemContainer(2)
    let out = ItemContainer(1)
    var name = ""
    var editing = false
    var cost = 0
    var tooExpensive = false
    private var rightUsed = 0

    init(game: Game, at p: IVec3) {
        pos = p
        super.init("Repair & Name", game: game)
        slots.append(MenuSlot(27, 47, box, 0))
        slots.append(MenuSlot(76, 47, box, 1))
        slots.append(MenuSlot(134, 47, out, 0, .result))
        let field = MenuSlot(60, 20, nil, 0, .button(0))
        field.w = 103; field.h = 12
        slots.append(field)
        addPlayerInventory()
    }

    override var capturesText: Bool { editing }

    override func buttonPressed(_ i: Int) { editing = !box[0].isEmpty }

    override func typed(_ s: String) {
        guard editing else { return }
        for c in s {
            if c == "\u{8}" { if !name.isEmpty { name.removeLast() } }
            else if name.count < 50 { name.append(c) }
        }
        changed()
    }

    override func changed() {
        let l = box[0]
        if l.isEmpty { name = ""; editing = false }
        else if !editing && name.isEmpty { name = l.displayName }
        guard let r = Enchant.combine(l, box[1], rename: name, creative: !game.survival) else {
            out[0] = .empty; cost = 0; tooExpensive = false; return
        }
        tooExpensive = r.out.isEmpty
        cost = r.cost
        rightUsed = r.rightUsed
        out[0] = (game.survival && game.xpLevel < cost) ? .empty : r.out
        if tooExpensive { out[0] = .empty }
    }

    override func takeResult(_ slot: MenuSlot) -> ItemStack? {
        let r = out[0]
        guard !r.isEmpty else { return nil }
        if game.survival { game.xpLevel = max(0, game.xpLevel - cost) }
        box[0] = .empty
        var right = box[1]
        right.count -= rightUsed
        box[1] = right.count > 0 ? right : .empty
        name = ""
        editing = false
        game.sfx(.anvil, 0.6, at: V3(Float(pos.x), Float(pos.y), Float(pos.z)) + 0.5)
        // 12% chance to wear the anvil a stage (chipped -> damaged -> gone).
        if game.survival && Rand.float(in: 0..<1) < 0.12 {
            let k = Blocks.key(game.world.block(pos.x, pos.y, pos.z))
            let next = k == "anvil" ? "chipped_anvil" : (k == "chipped_anvil" ? "damaged_anvil" : "")
            if next.isEmpty { game.world.setBlock(pos.x, pos.y, pos.z, AIR) }
            else { game.world.setBlock(pos.x, pos.y, pos.z, Blocks.id(next)) }
        }
        changed()
        return r
    }

    override func onClose() {
        for i in 0..<2 where !box[i].isEmpty {
            let rest = game.inventory.add(box[i])
            if !rest.isEmpty { game.dropItem(rest) }
            box[i] = .empty
        }
    }
}
