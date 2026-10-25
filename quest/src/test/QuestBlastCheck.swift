import Foundation
import simd
import Metal

// P452 (Remington, Oct 25 13:34: after the fight at the surface "all the blocks in the ground from the explosions" lagged
// the game): a blast leaves nothing to pick up but a very valuable block and what a container held. A wall of planks,
// stone bricks and dirt with an Upgrade Bench, a beacon, a crafting table and a chest of arrows in it is blown up.
//   questcheck --blastcheck
enum QuestBlastCheck {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        TextureGen.registerAll()
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "ok  " : "FAIL") blastcheck: \(what)"); if !ok { fails += 1 } }
        let kept = (0..<Blocks.count).filter { Explosion.valuable[$0] && Int(Blocks.groupBase[$0]) == $0 }.map { Blocks.key(BlockID($0)) }
        print("blastcheck: \(kept.count) blocks drop when blasted: \(kept.joined(separator: " "))")
        for (k, want) in [("enchanting_table", true), ("beacon", true), ("diamond_block", true), ("anvil", true), (WeaponPrinter.key, true),
                          ("crafting_table", false), ("oak_planks", false), ("stone_bricks", false), ("dirt", false), ("chest", false), ("tnt", false)]
            where Blocks.has(k) {
            check(Explosion.valuable[Int(Blocks.id(k))] == want, "\(k) \(want ? "drops" : "is gone") when blasted")
        }

        let w = World(seed: 4797859299361840175, device: sharedSystemDevice, save: nil)
        FieldTerrain.newWorlds = true; w.makeFieldWorld()
        w.renderDistance = 4
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true
        SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.menu = nil; g.survival = true
        g.player.pos = V3(-496.5, 72 + Float(YOFF), 6102.5)
        _ = w.loadSync(center: g.player.pos, radius: 3)
        g.tick(1.0 / 72)
        func top(_ x: Int, _ z: Int) -> Int {
            var y = CH - 1
            while y > 1 && !w.groundAt(x, y, z) && w.builtBlock(x, y, z) == AIR { y -= 1 }
            return y
        }
        // The wall: 7 wide, 4 high, 12 blocks east of him, with the four things set in its bottom row.
        let x0 = -484, z0 = 6100
        var y0 = 0
        for dz in -3...3 { y0 = max(y0, top(x0, z0 + dz) + 1) }
        let mats = ["oak_planks", "stone_bricks", "dirt"].map { Blocks.id($0) }
        for dz in -3...3 { for dy in 0..<4 { w.setBlock(x0, y0 + dy, z0 + dz, mats[(dz + 3 + dy) % 3]) } }
        let things = ["enchanting_table", "beacon", "crafting_table", "chest"]
        for (i, k) in things.enumerated() { w.setBlock(x0, y0, z0 - 2 + i, Blocks.id(k)) }
        g.tick(1.0 / 72)
        w.entity(IVec3(x0, y0, z0 + 1), .chest).container.slots[0] = ItemStack(Items.id("arrow"), 16)
        let before = g.drops.items.count
        Explosion.explode(at: V3(Float(x0) + 0.5, Float(y0) + 1.5, Float(z0) + 0.5), power: 6, game: g, decay: false)
        for _ in 0..<10 { g.tick(1.0 / 72) }
        let got = g.drops.items.dropFirst(before).map { "\(Items.key($0.stack.item)) x\($0.stack.count)" }
        let left = (-3...3).reduce(0) { n, dz in n + (0..<4).reduce(0) { m, dy in m + (w.builtBlock(x0, y0 + dy, z0 + dz) != AIR ? 1 : 0) } }
        let stood = things.indices.filter { w.builtBlock(x0, y0, z0 - 2 + $0) != AIR }.map { things[$0] }
        print("blastcheck: the blast left \(left) of 28 wall blocks (still standing of the four: \(stood.joined(separator: ", "))); dropped: \(got.joined(separator: ", "))")
        let keys = Set(g.drops.items.dropFirst(before).map { Items.key($0.stack.item) })
        check(left < 28, "the blast broke the wall")
        check(keys.isSubset(of: ["enchanting_table", "beacon", "arrow"]), "nothing but the valuable blocks and the chest's arrows dropped")
        check(keys.contains("arrow") || stood.contains("chest"), "the chest's arrows dropped if the chest broke")
        check(things.filter { $0 != "crafting_table" && $0 != "chest" }.allSatisfy { stood.contains($0) || keys.contains($0) },
              "each valuable block either stood or dropped")
        print(fails == 0 ? "blastcheck: all passed" : "blastcheck: \(fails) failed")
        return fails == 0 ? 0 : 1
    }
}
