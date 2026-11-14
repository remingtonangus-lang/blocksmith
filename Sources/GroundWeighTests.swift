import Foundation
import simd

// Ledger 127 (`questcheck --groundweigh`), in a field world of seed 4242, each scene a made block of ground:
//   (1) earth: a room 5 across dug under three cells of earth stands; dug out to 15 across its roof caves in;
//   (2) rock: the same room 15 across stands;
//   (3) a 294-cell boulder on four neck cells: two of them carved away it stands, three it comes down;
//   (4) a roof the world came with (made, not dug) that no weighing would pass is left alone by a carve beside it;
//   (5) earth, 15 across, with props every other cell: the roof stands.
enum GroundWeighTests {
    static func run(_ g0: Game, check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 4242, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 4; w.activeDistance = 4
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        let at = V3(8, 200, 8)
        g.player.pos = at
        _ = w.loadSync(center: at, radius: 4)
        let stone = FieldMat.index[Int(STONE)], dirt = FieldMat.index[Int(DIRT)]
        func set(_ x: Int, _ y: Int, _ z: Int, _ mat: UInt8?) {
            guard let c = w.chunkAt(x, z) else { return }
            c.blocks.setDensity(Chunk.index(mod(x, CS), y, mod(z, CS)), mat != nil ? 32 : -32, material: mat)
        }
        func top(_ x: Int, _ z: Int) -> Int {
            var y = CH - 2
            while y > 1 && !w.groundAt(x, y, z) { y -= 1 }
            return y
        }
        func dig(_ x: Int, _ y: Int, _ z: Int) {
            _ = w.fieldSphere(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5), radius: 0.6, carve: true, material: nil)
        }
        let base = top(0, 0)
        let H = base + 16
        // A block of ground 21 x 21, solid from well under the terrain up to H, clear air over it.
        func block(_ x0: Int, _ z0: Int, _ mat: UInt8) {
            for z in z0...(z0 + 20) { for x in x0...(x0 + 20) {
                for y in (base - 12)...H { set(x, y, z, mat) }
                for y in (H + 1)...(H + 12) { set(x, y, z, nil) }
            } }
        }
        // The room under three cells of cover, `n` across round the block's middle, three cells high.
        func room(_ x0: Int, _ z0: Int, _ n: Int, carve: Bool) {
            let a = 10 - n / 2
            for z in (z0 + a)..<(z0 + a + n) { for x in (x0 + a)..<(x0 + a + n) { for y in (H - 5)...(H - 3) {
                if carve { if w.groundAt(x, y, z) { dig(x, y, z) } } else { set(x, y, z, nil) }
            } } }
        }
        func cover(_ x0: Int, _ z0: Int, _ n: Int) -> Int {
            let a = 10 - n / 2
            var left = 0
            for z in (z0 + a)..<(z0 + a + n) { for x in (x0 + a)..<(x0 + a + n) { for y in (H - 2)...H { if w.groundAt(x, y, z) { left += 1 } } } }
            return left
        }
        func settle() {
            GroundWeigh.settle(g)
            var n = 0
            while !w.collapseQueue.isEmpty && n < 64 { GroundCollapse.tick(g); n += 1 }
            GroundWeigh.settle(g)
        }
        w.groundWeigh.carved.removeAll()
        // (1) earth
        block(-48, -48, dirt)
        room(-48, -48, 5, carve: true)
        settle()
        let small = cover(-48, -48, 5)
        room(-48, -48, 15, carve: true)
        let fell0 = GroundWeigh.fell
        settle()
        let wide = cover(-48, -48, 15), middle = (H - 2...H).filter { w.groundAt(-38, $0, -38) }.count
        let rim = (H - 2...H).filter { w.groundAt(-47, $0, -47) }.count
        check(small == 75 && middle == 0 && rim == 3,
              "groundweigh (1): earth over a room 5 across stands (\(small) of 75 cover cells left); 15 across it caves in (\(wide) of 675 left, \(middle) over the middle, \(GroundWeigh.fell - fell0) cells fell; the block's corner keeps \(rim) of 3)"
              + String(format: "; %d cells weighed in %.1f ms", GroundWeigh.lastCells, GroundWeigh.lastSolveMs))
        // (2) rock
        block(-16, -48, stone)
        room(-16, -48, 15, carve: true)
        let fell1 = GroundWeigh.fell
        settle()
        let rock = cover(-16, -48, 15)
        check(rock == 675 && GroundWeigh.fell == fell1, "groundweigh (2): rock over the same room 15 across stands (\(rock) of 675 cover cells left, \(GroundWeigh.fell - fell1) fell)")
        // (3) a boulder on a neck: 7 x 7 x 6 of rock on four cells, three high, over a rock floor
        func boulder(_ x0: Int, _ z0: Int, cut: Int) -> Int {
            let F = base + 4
            for z in (z0 - 6)...(z0 + 7) { for x in (x0 - 6)...(x0 + 7) {
                for y in (base - 12)...F { set(x, y, z, stone) }
                for y in (F + 1)...(F + 16) { set(x, y, z, nil) }
            } }
            let neck = [(x0, z0), (x0 + 1, z0), (x0, z0 + 1), (x0 + 1, z0 + 1)]
            for (x, z) in neck { for y in (F + 1)...(F + 3) { set(x, y, z, stone) } }
            for z in (z0 - 3)...(z0 + 3) { for x in (x0 - 3)...(x0 + 3) { for y in (F + 4)...(F + 9) { set(x, y, z, stone) } } }
            for (x, z) in neck.suffix(cut) { for y in (F + 1)...(F + 3) { dig(x, y, z) } }
            settle()
            var left = 0
            for z in (z0 - 3)...(z0 + 3) { for x in (x0 - 3)...(x0 + 3) { for y in (F + 4)...(F + 9) { if w.groundAt(x, y, z) { left += 1 } } } }
            return left
        }
        let two = boulder(24, -40, cut: 2), one = boulder(48, -40, cut: 3)
        check(two == 294 && one == 0, "groundweigh (3): a 294-cell boulder on two neck cells stands (\(two) left), on one it comes down (\(one) left)")
        // (4) a roof the world came with: made, not dug; a carve in the wall beside it
        block(-48, -16, dirt)
        room(-48, -16, 15, carve: false)
        let spared0 = GroundWeigh.spared, fell2 = GroundWeigh.fell
        dig(-48 + 1, H - 4, -16 + 10)
        GroundWeigh.settle(g)
        w.collapseQueue.removeAll()
        let made = cover(-48, -16, 15)
        check(made == 675 && GroundWeigh.fell == fell2 && GroundWeigh.spared > spared0,
              "groundweigh (4): a roof the world came with is left alone by a carve beside it (\(made) of 675 cover cells left, \(GroundWeigh.fell - fell2) fell, \(GroundWeigh.spared - spared0) cells with no way down before either)")
        // (5) props
        block(-16, -16, dirt)
        room(-16, -16, 15, carve: true)
        let planks = Blocks.id("oak_planks")
        let a = 10 - 15 / 2
        for z in stride(from: -16 + a, to: -16 + a + 15, by: 2) { for x in stride(from: -16 + a, to: -16 + a + 15, by: 2) {
            for y in (H - 5)...(H - 3) { w.setBlock(x, y, z, planks) }
        } }
        let fell3 = GroundWeigh.fell
        settle()
        let propped = cover(-16, -16, 15)
        check(propped == 675, "groundweigh (5): the same earth roof on props every other cell stands (\(propped) of 675 cover cells left, \(GroundWeigh.fell - fell3) fell)")
        print(String(format: "groundweigh: %d weighings, slowest %.1f ms off the frame, worst read slice %.2f ms", GroundWeigh.weighed, GroundWeigh.worstSolveMs, GroundWeigh.worstSliceMs))
    }
}
