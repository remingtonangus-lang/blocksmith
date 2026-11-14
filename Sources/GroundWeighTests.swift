import Foundation
import simd

// Ledger 127 (`questcheck --groundweigh`), in a field world of seed 4242, each scene a made block of ground:
//   (1) earth: a room 5 across dug under three cells of earth stands, and 15 across; dug out to 23 across its roof
//       caves in;
//   (2) rock: the same room 23 across stands;
//   (3) a 294-cell boulder on four neck cells: two of them carved away it stands, three it comes down;
//   (4) a roof the world came with (made, not dug) that no weighing would pass is left alone by a carve beside it;
//   (5) earth, 23 across, with props every other cell: the roof stands.
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
        func block(_ x0: Int, _ z0: Int, _ mat: UInt8, side: Int = 21) {
            for z in z0..<(z0 + side) { for x in x0..<(x0 + side) {
                // (down into the land under it: on a slope a block made from a fixed height hung in the air and the
                // older rule, rightly, dropped it whole)
                for y in min(base - 12, top(x, z) - 2)...H { set(x, y, z, mat) }
                for y in (H + 1)...(H + 12) { set(x, y, z, nil) }
            } }
        }
        // The room under three cells of cover, `n` across round the block's middle, three cells high.
        func room(_ x0: Int, _ z0: Int, _ n: Int, carve: Bool, side: Int = 21) {
            let a = side / 2 - n / 2
            for z in (z0 + a)..<(z0 + a + n) { for x in (x0 + a)..<(x0 + a + n) { for y in (H - 5)...(H - 3) {
                if carve { if w.groundAt(x, y, z) { dig(x, y, z) } } else { set(x, y, z, nil) }
            } } }
        }
        func cover(_ x0: Int, _ z0: Int, _ n: Int, side: Int = 21) -> Int {
            let a = side / 2 - n / 2
            var left = 0
            for z in (z0 + a)..<(z0 + a + n) { for x in (x0 + a)..<(x0 + a + n) { for y in (H - 2)...H { if w.groundAt(x, y, z) { left += 1 } } } }
            return left
        }
        // (the weighing alone: the older rules, loose pieces and thin overhangs, have their own checks in --settletest)
        func settle() {
            GroundWeigh.settle(g)
            w.collapseQueue.removeAll()
        }
        func tally() -> String { "older rules: dropped \(GroundCollapse.dropped), thin \(GroundSettle.overhangDrops), big \(GroundSettle.bigDrops), objects \(GroundSettle.objectFalls)" }
        w.groundWeigh.carved.removeAll()
        // (1) earth: a block 31 across at the world's -x -z corner of the loaded land
        let ex = -56, ez = -56
        block(ex, ez, dirt, side: 31)
        room(ex, ez, 5, carve: true, side: 31)
        settle()
        let small = cover(ex, ez, 5, side: 31)
        room(ex, ez, 15, carve: true, side: 31)
        settle()
        let mid15 = cover(ex, ez, 15, side: 31)
        room(ex, ez, 23, carve: true, side: 31)
        let fell0 = GroundWeigh.fell
        settle()
        let wide = cover(ex, ez, 23, side: 31)
        let middle = (H - 2...H).filter { w.groundAt(ex + 15, $0, ez + 15) }.count
        let rim = (H - 2...H).filter { w.groundAt(ex + 1, $0, ez + 1) }.count
        check(small == 75 && mid15 == 675 && middle == 0 && rim == 3,
              "groundweigh (1): earth over a room 5 across stands (\(small) of 75 cover cells left) and 15 across (\(mid15) of 675); 23 across it caves in (\(wide) of 1587 left, \(middle) over the middle, \(GroundWeigh.fell - fell0) cells fell; the block's corner keeps \(rim) of 3)"
              + String(format: "; %d cells weighed in %.1f ms; ", GroundWeigh.lastCells, GroundWeigh.lastSolveMs) + tally())
        // (2) rock
        let rx = -20, rz = -56
        block(rx, rz, stone, side: 31)
        let rock0 = cover(rx, rz, 23, side: 31)
        room(rx, rz, 23, carve: true, side: 31)
        let rock1 = cover(rx, rz, 23, side: 31)
        let fell1 = GroundWeigh.fell
        settle()
        let rock = cover(rx, rz, 23, side: 31)
        check(rock == 1587 && GroundWeigh.fell == fell1, "groundweigh (2): rock over the same room 23 across stands (\(rock) of 1587 cover cells left, \(GroundWeigh.fell - fell1) fell; \(rock0) as made, \(rock1) once dug; " + tally() + ")")
        // (3) a boulder on a neck: 7 x 7 x 6 of rock on four cells, three high, over a rock floor
        func boulder(_ x0: Int, _ z0: Int, cut: Int) -> Int {
            let F = base + 4
            for z in (z0 - 6)...(z0 + 7) { for x in (x0 - 6)...(x0 + 7) {
                for y in min(base - 12, top(x, z) - 2)...F { set(x, y, z, stone) }
                for y in (F + 1)...(F + 16) { set(x, y, z, nil) }
            } }
            let neck = [(x0, z0), (x0 + 1, z0), (x0, z0 + 1), (x0 + 1, z0 + 1)]
            for (x, z) in neck { for y in (F + 1)...(F + 3) { set(x, y, z, stone) } }
            for z in (z0 - 3)...(z0 + 3) { for x in (x0 - 3)...(x0 + 3) { for y in (F + 4)...(F + 9) { set(x, y, z, stone) } } }
            var made = 0
            for z in (z0 - 3)...(z0 + 3) { for x in (x0 - 3)...(x0 + 3) { for y in (F + 4)...(F + 9) { if w.groundAt(x, y, z) { made += 1 } } } }
            for (x, z) in neck.suffix(cut) { for y in (F + 1)...(F + 3) { dig(x, y, z) } }
            var dug = 0
            for z in (z0 - 3)...(z0 + 3) { for x in (x0 - 3)...(x0 + 3) { for y in (F + 4)...(F + 9) { if w.groundAt(x, y, z) { dug += 1 } } } }
            print("groundweigh (3) boulder at \(x0) \(z0): \(made) cells as made, \(dug) once the neck was cut; floor at \(F); " + tally())
            settle()
            var left = 0
            for z in (z0 - 3)...(z0 + 3) { for x in (x0 - 3)...(x0 + 3) { for y in (F + 4)...(F + 9) { if w.groundAt(x, y, z) { left += 1 } } } }
            return left
        }
        let two = boulder(30, -44, cut: 2), one = boulder(54, -44, cut: 3)
        check(two == 294 && one == 0, "groundweigh (3): a 294-cell boulder on two neck cells stands (\(two) left), on one it comes down (\(one) left)")
        // (4) a roof the world came with: made, not dug; a carve in the wall beside it
        let mx = -56, mz = -20
        block(mx, mz, dirt, side: 31)
        room(mx, mz, 23, carve: false, side: 31)
        let spared0 = GroundWeigh.spared, fell2 = GroundWeigh.fell
        dig(mx + 1, H - 4, mz + 15)
        settle()
        let made = cover(mx, mz, 23, side: 31)
        check(made == 1587 && GroundWeigh.fell == fell2 && GroundWeigh.spared > spared0,
              "groundweigh (4): a roof the world came with is left alone by a carve beside it (\(made) of 1587 cover cells left, \(GroundWeigh.fell - fell2) fell, \(GroundWeigh.spared - spared0) cells with no way down before either)")
        // (5) props
        let px = -20, pz = -20
        block(px, pz, dirt, side: 31)
        room(px, pz, 23, carve: true, side: 31)
        let planks = Blocks.id("oak_planks")
        let a = 31 / 2 - 23 / 2
        for z in stride(from: pz + a, to: pz + a + 23, by: 2) { for x in stride(from: px + a, to: px + a + 23, by: 2) {
            for y in (H - 5)...(H - 3) { w.setBlock(x, y, z, planks) }
        } }
        let fell3 = GroundWeigh.fell
        settle()
        let propped = cover(px, pz, 23, side: 31)
        check(propped == 1587, "groundweigh (5): the same earth roof on props every other cell stands (\(propped) of 1587 cover cells left, \(GroundWeigh.fell - fell3) fell)")
        print(String(format: "groundweigh: %d weighings, slowest %.1f ms off the frame, worst read slice %.2f ms", GroundWeigh.weighed, GroundWeigh.worstSolveMs, GroundWeigh.worstSliceMs))
    }
}
