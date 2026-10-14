import Foundation
import simd

// Crafter: a 3x3 grid that crafts one item per sparkstone pulse and ejects it from its front.
// W7 (reference): slots can be disabled (click an empty slot in its screen; a disabled slot takes nothing, hoppers
// skip it and a comparator counts it as filled); hoppers fill the enabled slots evenly; the result goes into any
// container in front (or a chest/hopper minecart there), else out as an item; leftovers (empty buckets and bottles)
// come out of the front with it.
extension BlockEntity {
    // The disabled-slot mask lives in `spawned` (saved for every kind; a crafter has no other use for it).
    func crafterDisabled(_ i: Int) -> Bool { kind == .crafter && i >= 0 && i < 9 && (spawned >> i) & 1 == 1 }
    func setCrafterDisabled(_ i: Int, _ on: Bool) {
        guard kind == .crafter, i >= 0, i < 9 else { return }
        if on { spawned |= 1 << i } else { spawned &= ~(1 << i) }
    }
}

extension Game {
    // One item from a hopper or dropper into a crafter (reference CrafterBlockEntity.canPlaceItem): never a disabled
    // or full slot; an occupied slot only when no later enabled slot is empty or holds fewer of the same item.
    func crafterInsert(_ be: BlockEntity, _ one: ItemStack) -> Bool {
        let c = be.container
        let n9 = min(9, c.count)
        for i in 0..<n9 where !be.crafterDisabled(i) {
            let cur = c[i]
            if cur.isEmpty { c[i] = one.with(count: 1); return true }
            guard cur.stacks(with: one), cur.count < cur.maxStack else { continue }
            var smaller = false
            var j = i + 1
            while j < n9 {
                let o = c[j]
                if !be.crafterDisabled(j) && (o.isEmpty || (o.count < cur.count && o.stacks(with: cur))) { smaller = true; break }
                j += 1
            }
            if smaller { continue }
            var n = cur
            n.count += 1
            c[i] = n
            return true
        }
        return false
    }

    // What a used-up grid item leaves behind (reference remainders).
    static func craftRemainder(_ s: ItemStack) -> ItemStack {
        let k = Items.key(s.item)
        if k == "water_bucket" || k == "lava_bucket" || k == "milk_bucket" || k == "powder_snow_bucket" { return ItemStack(Items.id("bucket"), 1) }
        let potion = Potions.potion(of: s.item).map { $0.form == 0 } ?? false
        if k == "honey_bottle" || k == "dragon_breath" || potion {
            return Items.has("glass_bottle") ? ItemStack(Items.id("glass_bottle"), 1) : .empty
        }
        return .empty
    }

    func crafterFire(_ p: IVec3) {
        guard let be = world.blockEntities[p], be.kind == .crafter else { return }
        let grid = be.container.slots
        let result: ItemStack
        var keep = Set<Int>()
        if let sp = Fireworks.craft(grid) { result = sp.0; keep = sp.keep }
        else if let r = Recipes.match(grid.map { $0.item }, 3, 3) { result = Recipes.keepContents(r.result, grid) }
        else { sfx(.crafterFail, 0.5, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5); return }
        var leftovers: [ItemStack] = []
        for i in 0..<min(9, grid.count) where !grid[i].isEmpty && !keep.contains(i) {
            var s = be.container[i]
            let rest = Game.craftRemainder(s)
            if !rest.isEmpty { leftovers.append(rest) }
            s.count -= 1
            be.container[i] = s.count > 0 ? s : .empty
        }
        let b = world.block(p.x, p.y, p.z)
        let f = Int(b - Blocks.groupBase[Int(b)]) % 4
        let d = [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0)][f]
        let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        let front = p + IVec3(Int(d.x), 0, Int(d.z))
        // Into a container in front if there is one (by its face, one at a time), else onto the ground.
        let frontBE = world.blockEntities[front]
        let blockContainer = frontBE.map { $0.container.count > 0 && $0.kind != .spawner && $0.kind != .campfire && $0.kind != .frame } ?? false
        let isContainer = blockContainer || cartContainer(at: front) != nil
        for out in [result] + leftovers {
            var rest = out
            if isContainer {
                while rest.count > 0 && containerInsert(front, rest.with(count: 1), dir: f + 2) { rest.count -= 1 }
            }
            if rest.count > 0 { drops.spawn(rest, at: c + d * 0.7, vel: d * 3 + V3(0, 1, 0)) }
        }
        sfx(.crafterCraft, 0.7, at: c)
        particles.smoke(at: c + d * 0.6, dark: false)
    }
}

final class CrafterMenu: Menu {
    let be: BlockEntity
    let preview = ItemContainer(1)
    init(game: Game, entity: BlockEntity) {
        be = entity
        super.init("Crafter", game: game)
        for r in 0..<3 { for c in 0..<3 {
            let i = c + r * 3
            let sl = MenuSlot(26 + c * 18, 17 + r * 18, entity.container, i)
            sl.filter = { [weak entity] _ in !(entity?.crafterDisabled(i) ?? false) }      // W7: a disabled slot takes nothing
            slots.append(sl)
        } }
        slots.append(MenuSlot(134, 35, preview, 0, .result))
        addPlayerInventory()
        changed()
    }
    override func changed() {
        if let sp = Fireworks.craft(be.container.slots) { preview[0] = sp.0 }
        else { preview[0] = Recipes.match(be.container.slots.map { $0.item }, 3, 3)?.result ?? .empty }
    }
    // W7: clicking an empty grid slot with nothing in hand turns it off (or back on).
    override func click(_ slot: MenuSlot, button: Int, shift: Bool) {
        if slot.container === be.container, slot.index < 9, slot.stack.isEmpty, game.carried.isEmpty, !shift {
            let off = !be.crafterDisabled(slot.index)
            be.setCrafterDisabled(slot.index, off)
            game.sfx(.click, 0.4)
            game.onToast?(off ? "Crafter slot disabled" : "Crafter slot enabled")
            return
        }
        super.click(slot, button: button, shift: shift)
    }
    // The preview can't be taken out.
    override func takeResult(_ slot: MenuSlot) -> ItemStack? { nil }
}
