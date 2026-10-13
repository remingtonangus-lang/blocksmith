import Foundation

// P125 (Oct 12 PM, "there should be glow areas that show on the vines... it theoretically violates some sort of
// copyright issue with Minecraft... up to you"): the cave vine became the lanternvine. Instead of round orange berries,
// some segments (every tip, about a third of the rest) carry split seed pods with a pale mint light inside: those
// segments light the cave (emit 12), the plain strands give none. Using a podded segment picks its Lumen Pods (food,
// key glow_berries); the strand regrows pods on random ticks.
extension Game {
    func pickLumenPods(_ p: IVec3) {
        let b = world.block(p.x, p.y, p.z)
        let base = Blocks.groupBase[Int(b)]
        guard Blocks.key(base) == "cave_vines", b != base else { return }
        world.setBlock(p.x, p.y, p.z, base)
        let rest = inventory.add(ItemStack(Items.id("glow_berries"), 1))
        if !rest.isEmpty { drops.spawn(rest, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.3, Float(p.z) + 0.5)) }
        sfx(.place(soundMat(b)), 0.6, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
        swing = 1
    }
}
