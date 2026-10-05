import Foundation
import simd

// Crafter: a 3x3 grid that crafts one item per sparkstone pulse and ejects it from its front.
extension Game {
    func crafterFire(_ p: IVec3) {
        guard let be = world.blockEntities[p], be.kind == .crafter else { return }
        let grid = be.container.slots
        let result: ItemStack
        var keep = Set<Int>()
        if let sp = Fireworks.craft(grid) { result = sp.0; keep = sp.keep }
        else if let r = Recipes.match(grid.map { $0.item }, 3, 3) { result = Recipes.keepContents(r.result, grid) }
        else { sfx(.crafterFail, 0.5, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5); return }
        for i in 0..<9 where !grid[i].isEmpty && !keep.contains(i) {
            var s = be.container[i]
            let k = Items.key(s.item)
            s.count -= 1
            if s.count <= 0 && (k == "water_bucket" || k == "lava_bucket" || k == "milk_bucket") { s = ItemStack(Items.id("bucket"), 1) }
            be.container[i] = s.count > 0 ? s : .empty
        }
        let b = world.block(p.x, p.y, p.z)
        let f = Int(b - Blocks.groupBase[Int(b)]) % 4
        let d = [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0)][f]
        let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        // Into a container in front if there is one, else onto the ground.
        let front = p + IVec3(Int(d.x), 0, Int(d.z))
        var rest = result
        if let fb = world.blockEntities[front], fb.kind == .chest || fb.kind == .hopper || fb.kind == .dispenser || fb.kind == .shulker {
            rest = fb.container.add(rest)
        }
        if !rest.isEmpty { drops.spawn(rest, at: c + d * 0.7, vel: d * 3 + V3(0, 1, 0)) }
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
        for r in 0..<3 { for c in 0..<3 { slots.append(MenuSlot(26 + c * 18, 17 + r * 18, be.container, c + r * 3)) } }
        slots.append(MenuSlot(134, 35, preview, 0, .result))
        addPlayerInventory()
        changed()
    }
    override func changed() {
        if let sp = Fireworks.craft(be.container.slots) { preview[0] = sp.0 }
        else { preview[0] = Recipes.match(be.container.slots.map { $0.item }, 3, 3)?.result ?? .empty }
    }
    // The preview can't be taken out.
    override func takeResult(_ slot: MenuSlot) -> ItemStack? { nil }
}
