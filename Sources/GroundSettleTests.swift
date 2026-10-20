import Foundation
import simd

// P380 test cases (`questcheck --settletest`), in a field world of seed 4242 on open ground near the origin:
//   (1) a one-cell slab 8 out from a pillar breaks off past 3 cells; a three-cell slab 6 out stays;
//   (2) small floating pieces across chunk borders: with the border check off they are counted, with it on none is left;
//   (3) a tree, a 2x2x2 planks cube and a plant on flat ground, the ground dug from under each: the tree falls as a
//       felled tree, the cube falls block by block (its top layer leaves, half of it lands below), the plant pops;
//   (4) a 2,352-cell lump on a one-cell stalk: the stalk dug, it falls in lots; the same lump on the ground stays.
enum GroundSettleTests {
    static func run(_ g0: Game, check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        func makeWorld(_ seed: UInt64, _ at: V3) -> (World, Game) {
            let w = World(seed: seed, device: g0.world.device, save: nil)
            w.makeFieldWorld()
            w.renderDistance = 3; w.activeDistance = 3
            let g = Game(world: w, save: nil, persistent: false)
            g.paused = false; g.survival = false
            g.player.pos = at
            _ = w.loadSync(center: at, radius: 3)
            return (w, g)
        }
        let stone = FieldMat.index[Int(STONE)]
        func set(_ w: World, _ x: Int, _ y: Int, _ z: Int, _ on: Bool) {
            guard let c = w.chunkAt(x, z) else { return }
            c.blocks.setDensity(Chunk.index(mod(x, CS), y, mod(z, CS)), on ? 32 : -32, material: on ? stone : nil)
        }
        func top(_ w: World, _ x: Int, _ z: Int) -> Int {          // (the drawn ground's top cell, under any tree)
            var y = CH - 2
            while y > 1 && !w.groundAt(x, y, z) { y -= 1 }
            return y
        }
        func settle(_ g: Game, _ secs: Float = 0) {
            var n = 0
            while !g.world.collapseQueue.isEmpty && n < 64 { GroundCollapse.tick(g); n += 1 }
            g.gravityTick()
            var t: Float = 0
            while t < secs { g.fallingTick(1.0 / 60); g.fellingTick(1.0 / 60); g.gravityTick(); t += 1.0 / 60 }
        }
        func dig(_ g: Game, _ x: Int, _ y: Int, _ z: Int, _ r: Float = 0.6) {
            _ = g.world.fieldSphere(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5), radius: r, carve: true, material: nil)
        }
        let (w, g) = makeWorld(4242, V3(8, 200, 8))
        let x0 = 0, z0 = 0
        let y0 = top(w, x0, z0)
        // (1) Thin overhangs: a 3x3 pillar up to Y; a slab off its east side.
        func overhang(_ thick: Int, _ out: Int, _ zOff: Int) -> (gone: Int, left: Int) {
            let Y = y0 + 14, zb = z0 + zOff
            for y in (y0 - 2)...Y { for z in zb...(zb + 2) { for x in x0...(x0 + 2) { set(w, x, y, z, true) } } }
            for y in (Y - thick + 1)...Y { for z in zb...(zb + 2) { for x in (x0 + 3)...(x0 + 2 + out) { set(w, x, y, z, true) } } }
            w.collapseQueue.append((IVec3(x0 + 3, Y, zb + 1), 1))
            settle(g)
            var gone = 0, left = 0
            for x in (x0 + 3)...(x0 + 2 + out) { if w.groundAt(x, Y, zb + 1) { left += 1 } else { gone += 1 } }
            return (gone, left)
        }
        let thin = overhang(1, 8, 0), thick = overhang(3, 6, 8)
        check(thin.gone == 5 && thin.left == 3 && thick.gone == 0,
              "P380 (1): a one-cell slab 8 out kept \(thin.left) and lost \(thin.gone) columns (3 and 5 wanted); a three-cell slab 6 out lost \(thick.gone)")
        // (3) Objects, each on a flat made patch (a hillside beside it would hold it, rightly).
        func flat(_ x: Int, _ z: Int) -> Int {
            let y = top(w, x, z) + 1
            for dz in -4...4 { for dx in -4...4 {
                for yy in (y - 5)..<y { set(w, x + dx, yy, z + dz, true) }
                for yy in y..<(y + 10) { set(w, x + dx, yy, z + dz, false) }
            } }
            return y
        }
        let ox = x0, oz = z0 - 20
        let oy = flat(ox, oz)
        let log = Blocks.id("oak_log"), leaves = Blocks.has("oak_leaves") ? Blocks.id("oak_leaves") : LEAVES
        for k in 0..<5 { w.setBlock(ox, oy + k, oz, log) }
        for dz in -2...2 { for dx in -2...2 where !(dx == 0 && dz == 0) { for k in 3...5 { w.setBlock(ox + dx, oy + k, oz + dz, leaves) } } }
        let px = ox + 10, pz = oz, py = flat(px, pz)
        for k in 0..<8 { w.setBlock(px + k & 1, py + (k >> 1) & 1, pz + (k >> 2) & 1, PLANKS) }
        let gx = ox + 20, gz = oz, gy = flat(gx, gz)
        let plant = Blocks.has("short_grass") ? Blocks.id("short_grass") : (Blocks.has("grass") ? Blocks.id("grass") : Blocks.id("poppy"))
        w.setBlock(gx, gy, gz, plant)
        let felled0 = Felling.felled
        dig(g, ox, oy - 1, oz, 1.2)
        dig(g, px, py - 1, pz, 1.0); dig(g, px + 1, py - 1, pz + 1, 1.0); dig(g, px + 1, py - 1, pz, 1.0); dig(g, px, py - 1, pz + 1, 1.0)
        dig(g, gx, gy - 1, gz, 1.0)
        settle(g, 4)
        let treeFell = Felling.felled > felled0 && w.builtBlock(ox, oy + 1, oz) != log
        let cubeGone = (0..<4).allSatisfy { k in w.builtBlock(px + k & 1, py + 1, pz + (k >> 1) & 1) != PLANKS }   // (its top layer)
        var landed = 0
        for y in (py - 6)..<py { for dz in 0...1 { for dx in 0...1 where w.builtBlock(px + dx, y, pz + dz) == PLANKS { landed += 1 } } }
        let popped = w.builtBlock(gx, gy, gz) != plant
        check(treeFell && cubeGone && landed >= 4 && popped,
              "P380 (3): dug from under, the tree fell \(treeFell), the planks cube fell \(cubeGone) and \(landed) of 8 landed below, the plant popped \(popped)")
        // (4) Big pieces: a 14 x 12 x 14 lump on a one-cell stalk; then the same lump sitting on the ground.
        let bx = x0 - 30, bz = z0 - 10, by = top(w, bx + 7, bz + 7)
        var hi = by                                                          // (clear of the hillside round it)
        for z in (bz - 1)...(bz + 14) { for x in (bx - 1)...(bx + 14) { hi = max(hi, top(w, x, z)) } }
        let L = hi + 5
        for y in (by - 1)..<L { set(w, bx + 7, y, bz + 7, true) }
        for y in L..<(L + 12) { for z in bz..<(bz + 14) { for x in bx..<(bx + 14) { set(w, x, y, z, true) } } }
        let big0 = GroundSettle.bigDrops
        dig(g, bx + 7, L - 3, bz + 7, 0.6)
        settle(g)
        var lumpLeft = 0
        for y in L..<(L + 12) { for z in bz..<(bz + 14) { for x in bx..<(bx + 14) where w.groundAt(x, y, z) { lumpLeft += 1 } } }
        let cx = x0 + 20, cz = z0 + 20, cy = top(w, cx + 7, cz + 7) - 1
        for y in cy..<(cy + 12) { for z in cz..<(cz + 14) { for x in cx..<(cx + 14) { set(w, x, y, z, true) } } }
        dig(g, cx + 7, cy + 12, cz + 7, 1.2)
        settle(g)
        var heldLeft = 0
        for y in cy..<(cy + 12) { for z in cz..<(cz + 14) { for x in cx..<(cx + 14) where w.groundAt(x, y, z) { heldLeft += 1 } } }
        check(GroundSettle.bigDrops == big0 + 1 && lumpLeft == 0 && heldLeft > 2000,
              "P380 (4): a 2,352-cell lump on a stalk fell in lots (\(GroundSettle.bigDrops - big0) big fall, \(lumpLeft) cells left); the same lump on the ground kept \(heldLeft) cells")
        // (2) Floating pieces across chunk borders: three seeds' ravine country, with the check off and on.
        // A made case: a 3 x 3 x 3 lump in the air across the border between two chunks, noted as generation would.
        let lx = 14, lz = 4, ly = y0 + 30
        for y in ly..<(ly + 3) { for z in lz..<(lz + 3) { for x in lx..<(lx + 3) { set(w, x, y, z, true) } } }
        let c0 = w.chunkAt(lx, lz)!
        c0.borderSeeds = [Chunk.index(mod(lx, CS), ly, mod(lz, CS))]
        GroundSettle.borderCheck(w, around: ChunkKey(x: c0.cx, z: c0.cz))
        var madeLeft = 0
        for y in ly..<(ly + 3) { for z in lz..<(lz + 3) { for x in lx..<(lx + 3) where w.groundAt(x, y, z) { madeLeft += 1 } } }
        var off = 0, on = 0, dropped = 0, sides = 0
        for seed: UInt64 in [4242, 13480747113613945685, 1997562484558922131] {
            GroundSettle.borderCheck = false
            let (wa, _) = makeWorld(seed, V3(0, 200, 0))
            var seeds: [IVec3] = []
            for (k, c) in wa.chunks { sides += c.borderSeeds.count; for i in c.borderSeeds { seeds.append(IVec3(k.x * CS + i & 15, i / CSQ, k.z * CS + (i >> 4) & 15)) } }
            off += closed(wa, seeds)
            GroundSettle.borderCheck = true
            let d0 = GroundSettle.borderDrops
            let (wb, _) = makeWorld(seed, V3(0, 200, 0))
            dropped += GroundSettle.borderDrops - d0
            on += closed(wb, seeds)
        }
        check(madeLeft == 0 && on == 0 && (off == 0 || dropped > 0),
              "P380 (2): a made 27-cell lump across a chunk border: \(madeLeft) cells left; generated ground: \(sides) small pieces reached a chunk side, \(off) of them float with the check off, \(on) with it on (\(dropped) cells taken out)")
    }

    // Closed floating pieces under 400 cells among the chunks whose neighbours all exist, from the given cells.
    static func closed(_ w: World, _ seeds: [IVec3]) -> Int {
        var n = 0
        var done = Set<IVec3>()
        for s in seeds where !done.contains(s) && w.isGround(s) {
            var seen: Set<IVec3> = [s]
            var stack = [s], count = 0
            var held = false
            while let q = stack.popLast() {
                count += 1
                if q.y <= 1 || count >= 400 { held = true; break }
                let ck = ChunkKey(x: floorDiv(q.x, CS), z: floorDiv(q.z, CS))
                for dz in -1...1 { for dx in -1...1 where w.chunks[ChunkKey(x: ck.x + dx, z: ck.z + dz)] == nil { held = true } }
                if held { break }
                for e in World.allDirs {
                    let m = q + e
                    if !seen.contains(m) && w.isGround(m) { seen.insert(m); stack.append(m) }
                }
            }
            done.formUnion(seen)
            if !held { n += 1 }
        }
        return n
    }
}
