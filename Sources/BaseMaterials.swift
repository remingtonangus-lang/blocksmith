import Foundation

// P254 (Oct 14 12:01-12:08, "those barrels, make it so they store building material, a whole bunch of it... getting
// blocks is boring"; "these little ammo crates, I don't know what they are, there should be something in them, not that
// valuable, but a ton of it"): raiding a base yields blocks to build with.
// - The olive crates stacked in every base (key ammo_crate, now named Supply Crate) open like a barrel and hold bulk
//   building materials: near-full stacks of stone, planks, bricks, glass, logs and the like (six to nine stacks).
//   The structures lay them as plain blocks; each is filled the first time it is opened or broken, from its position
//   and the world's seed. Broken, it splinters (no crate drops) and its contents spill, so it can't be farmed.
// - Store barrels of the same beside the crate stacks in Greywall yards and in Capital citadels' armouries. The yards'
//   sundry barrels keep their sundries (P133).
enum BaseMaterials {
    static let loot = "base_materials"
    static let crate = "ammo_crate"
    static let table: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)]) =
        (6...9, [("cobblestone", 48, 64, 10), ("stone", 32, 64, 8), ("stone_bricks", 32, 64, 8), ("oak_planks", 48, 64, 9),
                 ("spruce_planks", 32, 64, 7), ("bricks", 24, 64, 6), ("smooth_stone", 24, 64, 5), ("glass", 16, 48, 5),
                 ("sand", 32, 64, 4), ("gravel", 32, 64, 4), ("dirt", 48, 64, 5), ("oak_log", 16, 32, 5), ("spruce_log", 16, 32, 3),
                 ("andesite", 32, 64, 3), ("polished_andesite", 24, 64, 3), ("bunker_concrete", 24, 64, 4), ("oak_slab", 32, 64, 3),
                 ("cobblestone_stairs", 16, 48, 2), ("ladder", 16, 32, 2), ("torch", 32, 64, 3)])
}

extension StructWriter {
    // A store barrel full of building materials (P254).
    mutating func materials(_ x: Int, _ y: Int, _ z: Int, seed s: UInt64) {
        guard inside(x, y, z) else { return }
        set(x, y, z, Blocks.id("barrel"))
        let be = BlockEntity(.chest)
        var rng = SRng(UInt64(hash3(x, y, z, UInt32(truncatingIfNeeded: s ^ (s >> 32)) ^ 0x2541)) | 1)
        Loot.fill(be.container, table: BaseMaterials.loot, rng: &rng)
        entities.append((IVec3(x, y, z), be))
    }
}

extension Game {
    // A supply crate's contents: filled the first time (P254).
    func crateEntity(_ p: IVec3) -> BlockEntity {
        if let be = world.blockEntities[p] { return be }
        let be = BlockEntity(.chest)
        var rng = SRng(UInt64(hash3(p.x, p.y, p.z, UInt32(truncatingIfNeeded: world.seed ^ (world.seed >> 32)) ^ 0xC8A7)) | 1)
        Loot.fill(be.container, table: BaseMaterials.loot, rng: &rng)
        world.blockEntities[p] = be
        return be
    }
}
