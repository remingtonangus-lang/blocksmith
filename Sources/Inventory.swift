import Foundation

struct ItemStack: Codable, Equatable {
    var item: ItemID = 0
    var count: Int = 0
    var damage: Int = 0                 // durability used (tools/armor)
    var ench: UInt64 = 0                // up to 7 enchantments, 9 bits each (see Enchant)
    var repairCost = 0                  // anvil prior-work penalty
    var label: String? = nil            // anvil rename
    var tag = 0                         // item-specific state (crossbow: loaded projectile item id)
    var contents: [ItemStack]? = nil    // shell box items
    var pat: [Int]? = nil               // banner pattern layers (pattern * 16 + colour)
    var pages: [String]? = nil          // book text

    // Saved by item name so registry changes never scramble inventories.
    enum CodingKeys: String, CodingKey { case id, n, d, e, r, l, t, c, p, g }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .id)
        item = Items.has(name) ? Items.id(name) : 0
        count = try (item == 0 ? 0 : c.decode(Int.self, forKey: .n))
        damage = (try? c.decode(Int.self, forKey: .d)) ?? 0
        if let e = try? c.decode([String].self, forKey: .e) { ench = Enchant.decode(e) }
        repairCost = (try? c.decode(Int.self, forKey: .r)) ?? 0
        label = try? c.decode(String.self, forKey: .l)
        tag = (try? c.decode(Int.self, forKey: .t)) ?? 0
        contents = try? c.decode([ItemStack].self, forKey: .c)
        pat = try? c.decode([Int].self, forKey: .p)
        pages = try? c.decode([String].self, forKey: .g)
    }
    func encode(to enc: Encoder) throws {
        var c = enc.container(keyedBy: CodingKeys.self)
        try c.encode(Items.key(item), forKey: .id)
        try c.encode(count, forKey: .n)
        if damage != 0 { try c.encode(damage, forKey: .d) }
        if ench != 0 { try c.encode(Enchant.encode(ench), forKey: .e) }
        if repairCost != 0 { try c.encode(repairCost, forKey: .r) }
        if let l = label { try c.encode(l, forKey: .l) }
        if tag != 0 { try c.encode(tag, forKey: .t) }
        if let k = contents { try c.encode(k, forKey: .c) }
        if let p = pat { try c.encode(p, forKey: .p) }
        if let g = pages { try c.encode(g, forKey: .g) }
    }

    static let empty = ItemStack()
    init() {}
    init(_ item: ItemID, _ count: Int = 1, damage: Int = 0) { self.item = item; self.count = count; self.damage = damage }

    var isEmpty: Bool { item == 0 || count <= 0 }
    var def: ItemDef { Items.def(item) }
    var maxStack: Int { Items.def(item).maxStack }
    func stacks(with o: ItemStack) -> Bool { item == o.item && damage == o.damage && ench == o.ench && label == o.label && tag == o.tag && contents == nil && o.contents == nil && pat == o.pat && pages == nil && o.pages == nil && maxStack > 1 }
    func with(count n: Int) -> ItemStack { var s = self; s.count = n; return s }
    var displayName: String { label ?? def.display }
}

// A fixed-size list of slots (player inventory, chest, furnace, crafting grid...).
final class ItemContainer {
    var slots: [ItemStack]
    init(_ n: Int) { slots = Array(repeating: ItemStack.empty, count: n) }
    var count: Int { slots.count }
    subscript(i: Int) -> ItemStack {
        get { slots[i] }
        set { slots[i] = newValue.isEmpty ? .empty : newValue }
    }

    // Adds as much of `s` as fits into `range` (merging into matching stacks first). Returns the rest.
    @discardableResult
    func add(_ s0: ItemStack, range: Range<Int>? = nil) -> ItemStack {
        var s = s0
        let r = range ?? 0..<slots.count
        for i in r where !s.isEmpty && slots[i].stacks(with: s) && slots[i].count < slots[i].maxStack {
            let n = min(s.count, slots[i].maxStack - slots[i].count)
            slots[i].count += n
            s.count -= n
        }
        for i in r where !s.isEmpty && slots[i].isEmpty {
            let n = min(s.count, s.maxStack)
            slots[i] = s.with(count: n)
            s.count -= n
        }
        return s.isEmpty ? .empty : s
    }

    func countOf(_ item: ItemID) -> Int { slots.reduce(0) { $0 + ($1.item == item ? $1.count : 0) } }

    @discardableResult
    func remove(_ item: ItemID, _ n: Int) -> Int {
        var left = n
        for i in slots.indices where left > 0 && slots[i].item == item {
            let k = min(left, slots[i].count)
            slots[i].count -= k
            left -= k
            if slots[i].count <= 0 { slots[i] = .empty }
        }
        return n - left
    }
}

// Player inventory: slots 0-8 hotbar, 9-35 main; armor 0 head ... 3 feet; one off-hand slot.
final class PlayerInventory {
    let main = ItemContainer(36)
    let armor = ItemContainer(4)
    let offhand = ItemContainer(1)
    var selected = 0

    var held: ItemStack {
        get { main[selected] }
        set { main[selected] = newValue }
    }

    // Picks up a stack: hotbar first, then the main inventory. Returns what didn't fit.
    @discardableResult
    func add(_ s: ItemStack) -> ItemStack {
        var rest = s
        // Merge into existing stacks anywhere first, then fill empty hotbar, then empty main slots.
        for i in 0..<36 where !rest.isEmpty && main[i].stacks(with: rest) && main[i].count < main[i].maxStack {
            let n = min(rest.count, main[i].maxStack - main[i].count)
            main.slots[i].count += n
            rest.count -= n
        }
        if rest.isEmpty { return .empty }
        rest = main.add(rest, range: 0..<9)
        if rest.isEmpty { return .empty }
        return main.add(rest, range: 9..<36)
    }

    var armorPoints: Int { armor.slots.reduce(0) { $0 + ($1.isEmpty ? 0 : $1.def.armor) } }
    var toughness: Float { armor.slots.reduce(0) { $0 + ($1.isEmpty ? 0 : $1.def.toughness) } }

    struct Saved: Codable { var main: [ItemStack]; var armor: [ItemStack]; var offhand: [ItemStack]; var selected: Int }
    var saved: Saved { Saved(main: main.slots, armor: armor.slots, offhand: offhand.slots, selected: selected) }
    func load(_ s: Saved) {
        for (i, v) in s.main.prefix(36).enumerated() { main[i] = v }
        for (i, v) in s.armor.prefix(4).enumerated() { armor[i] = v }
        for (i, v) in s.offhand.prefix(1).enumerated() { offhand[i] = v }
        selected = max(0, min(8, s.selected))
    }
}
