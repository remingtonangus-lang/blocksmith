import Foundation

// Per-block state that doesn't fit in a block ID: chest and furnace inventories, furnace progress.
final class BlockEntity: Codable {
    enum Kind: String, Codable { case chest, furnace }
    let kind: Kind
    var items: [ItemStack]
    var burn = 0         // furnace: fuel ticks left
    var burnMax = 0
    var cook = 0         // furnace: progress ticks (200 = one item)
    lazy var container: ItemContainer = {
        let c = ItemContainer(items.count)
        c.slots = items
        return c
    }()

    init(_ k: Kind) {
        kind = k
        items = Array(repeating: .empty, count: k == .chest ? 27 : 3)
    }

    enum CodingKeys: String, CodingKey { case kind, items, burn, burnMax, cook }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(container.slots, forKey: .items)
        try c.encode(burn, forKey: .burn)
        try c.encode(burnMax, forKey: .burnMax)
        try c.encode(cook, forKey: .cook)
    }

    // One furnace game tick (20 per second). Returns true if the lit state changed.
    func tickFurnace() -> Bool {
        let c = container
        let wasLit = burn > 0
        if burn > 0 { burn -= 1 }
        let input = c[0]
        var canSmelt = false
        var out: ItemID = 0
        if !input.isEmpty, let r = Recipes.smelt(input.item) {
            out = r
            let o = c[2]
            canSmelt = o.isEmpty || (o.item == r && o.count < o.maxStack)
        }
        if burn == 0 && canSmelt {
            let f = c[1]
            let ticks = f.isEmpty ? 0 : Recipes.fuel(f.item)
            if ticks > 0 {
                burn = ticks
                burnMax = ticks
                var nf = f
                nf.count -= 1
                if Items.key(f.item) == "lava_bucket" { nf = ItemStack(Items.id("bucket"), 1) }
                c[1] = nf
            }
        }
        if burn > 0 && canSmelt {
            cook += 1
            if cook >= 200 {
                cook = 0
                var i = c[0]; i.count -= 1; c[0] = i
                var o = c[2]
                if o.isEmpty { o = ItemStack(out, 1) } else { o.count += 1 }
                c[2] = o
            }
        } else if cook > 0 {
            cook = max(0, cook - 2)
        }
        return wasLit != (burn > 0)
    }
}

struct BlockEntitySave: Codable {
    var entries: [String: BlockEntity]
}
