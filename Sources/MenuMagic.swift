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
        // Q2c-console-64: room for the status lines between the stand and the pack.
        height = 190
        inventoryLabelY = 98
        addPlayerInventory(y: 108)
    }
    static func name(_ k: String) -> String { Items.has(k) ? Items.name(Items.id(k)) : k.replacingOccurrences(of: "_", with: " ") }
    // P317 (a): a slot that won't take the carried item bounces it with a clunk (Menu.refuse), no words.
    // Q2c-console-64: what it is doing, or why it is stuck (amber): up to two lines.
    var status: [(String, Bool)] {
        let c = be.container
        let bottles = (0..<3).map { c[$0] }.filter { !$0.isEmpty }
        let powder = BrewingMenu.name("blaze_powder")
        let fuelLine = be.fuel > 0 ? "Fuel for \(be.fuel) more brew\(be.fuel == 1 ? "" : "s")"
            : (c[4].isEmpty ? "No \(powder) left: add some on the left" : "Fuel for \(20 * c[4].count) more brews")
        if be.brewTime > 0 {
            let secs = max(1, be.brewTime / 20)
            return [("Brewing: about \(secs) s", false), (fuelLine, be.fuel == 0 && c[4].isEmpty)]
        }
        if bottles.isEmpty { return [("Put water bottles in the three bottom slots", true)] }
        if bottles.allSatisfy({ Items.key($0.item) == "glass_bottle" }) { return [("Fill the bottles with water first: use them on water", true)] }
        let ing = c[3]
        if ing.isEmpty { return [("Add an ingredient on top: start with \(BrewingMenu.name("nether_wart"))", true)] }
        if !bottles.contains(where: { Potions.brew($0.item, ing.item) != nil }) { return [("\(ing.def.display) does nothing to these bottles", true)] }
        if be.fuel <= 0 && c[4].isEmpty { return [("Add \(powder) on the left to fuel it", true)] }
        return [("Ready to brew", false), (fuelLine, false)]
    }
    override func quickMoveTargets(from: MenuSlot) -> [MenuSlot] {
        if from.isPlayerInv {
            // Blaze powder fills the fuel slot first (it is also an ingredient: it went into the ingredient slot).
            if Items.key(from.stack.item) == "blaze_powder" { return [slots[4], slots[3]] }
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
        super.init("Upgrade Bench", game: game)
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
        // Q2c-console-68: room for the bench's two lines under the slots.
        height = 186
        inventoryLabelY = 93
        addPlayerInventory(y: 104)
        shelves = Enchant.countBookshelves(game.world, p)
        changed()
    }

    // Q2c-console-68: what the bench wants and what would make it better (true: he must act; drawn amber).
    var status: [(String, Bool)] {
        func n(_ k: String) -> String { Items.has(k) ? Items.name(Items.id(k)) : k.replacingOccurrences(of: "_", with: " ") }
        let s = box[0]
        if s.isEmpty { return [("Put a tool, weapon, armour or book in the left slot", false)] }
        if s.ench != 0 { return [("Already enchanted: add more with an enchanted book at an anvil", true)] }
        if s.def.enchantability <= 0 { return [("\(s.def.display) can't be enchanted", true)] }
        let bs = n("bookshelf"), shelvesName = bs.hasSuffix("shelf") ? String(bs.dropLast()) + "ves" : bs + "s"
        let shelvesLine = ("\(shelvesName) around: \(shelves) of 15 (more give stronger offers)", false)
        guard game.survival else { return [shelvesLine] }
        if box[1].isEmpty { return [("Add \(n("lapis_lazuli")) on the right: 1 to 3 per offer", true), shelvesLine] }
        if let low = costs.filter({ $0 > 0 }).min(), game.xpLevel < low {
            return [("You need more levels: you have \(game.xpLevel)", true), shelvesLine]
        }
        return [shelvesLine]
    }

    override func changed() {
        let s = box[0]
        costs = [0, 0, 0]
        clues = [nil, nil, nil]
        guard !s.isEmpty, s.ench == 0, s.def.enchantability > 0 else { return }
        costs = Enchant.tableCosts(bookshelves: shelves, seed: game.enchantSeed)
        for i in 0..<3 {
            if costs[i] < i + 1 { costs[i] = 0; continue }
            let o = Enchant.tableOffer(item: s.item, cost: costs[i], seed: game.enchantSeed, slot: i)
            if let c = o.clue { clues[i] = c } else { costs[i] = 0 }
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
        let l = Enchant.tableOffer(item: s.item, cost: costs[i], seed: game.enchantSeed, slot: i).ench
        if Items.key(s.item) == "book" { s = ItemStack(Items.id("enchanted_book"), 1) }   // (one entry fewer: tableOffer)
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
        // Q2c-console-66: room for the reason line under the slots, clear of the cost plate.
        height = 193
        inventoryLabelY = 100
        addPlayerInventory(y: 111)
    }

    // Q2c-console-66: why the output is empty (nil when it isn't, or when nothing is in).
    var reason: String? {
        let l = box[0], r = box[1]
        guard !l.isEmpty, out[0].isEmpty else { return nil }
        func a(_ n: String) -> String { ("AEIOU".contains(n.first ?? "x") ? "an " : "a ") + n }
        if r.isEmpty { return name.isEmpty || name == l.displayName ? "Add a second item to repair or enchant it, or type a new name" : nil }
        if cost > 0 && !tooExpensive && game.survival && game.xpLevel < cost { return "You need \(cost) levels (you have \(game.xpLevel))" }
        if tooExpensive { return nil }                                       // the plate says it
        let rk = Items.key(r.item)
        if l.def.durability > 0, let mat = Enchant.repairMaterial(l.item) {
            if rk == mat && l.damage == 0 { return "Your \(l.displayName) isn't damaged" }
            if rk != mat && r.item != l.item && rk != "enchanted_book" {
                let mn = Items.has(mat) ? Items.name(Items.id(mat)) : mat.replacingOccurrences(of: "_", with: " ")
                return "\(a(l.def.display).capitalizedFirst) is repaired with \(mn)"
            }
        }
        if rk != "enchanted_book" && r.item != l.item { return "These two can't be combined: use two of the same item, or a book" }
        if Items.key(l.item) != "enchanted_book" && !Enchant.list(r).contains(where: { Enchant.applies($0.0, l.item, table: false) }) {
            return "None of these enchantments can go on \(a(l.def.display))"
        }
        return "Nothing to gain: these enchantments clash with what it has"
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
        // Only what went into the result leaves the left slot (clearing it lost the rest of a stack: renaming 64
        // diamonds gave one and deleted 63).
        var left = box[0]
        left.count -= r.count
        box[0] = left.count > 0 ? left : .empty
        var right = box[1]
        right.count -= rightUsed
        box[1] = right.count > 0 ? right : .empty
        name = ""
        editing = false
        game.sfx(.anvil, 0.6, at: V3(Float(pos.x), Float(pos.y), Float(pos.z)) + 0.5)
        // 12% chance to wear the anvil a stage (chipped -> damaged -> gone).
        if game.survival && Rand.float(in: 0..<1) < 0.12 {
            let k = Blocks.key(game.world.materialAt(pos.x, pos.y, pos.z))
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
