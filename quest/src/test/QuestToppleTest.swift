import Foundation
import simd
import Metal

// P407 step 3: what nothing holds falls whole, drawn as itself. At the Oct 22 22:06 tree note (seed 5663059916303033239,
// -4921 107 2260) in a Polygons world: a 6x6x50 stone tower (1,800 blocks: past the load check's 1,536-block fill, as
// the Boreal Station tower was) stood on one stone, and a birch on a one-block plinth; each footing broken. Both must
// come down as one body (a ship), and the falling birch's hull mesh must draw its leaves as blobs, not cubes.
//   questcheck --toppletest   (also P411: a placed deck gun is drawn as the gun it becomes before its first tick)
enum QuestToppleTest {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        TextureGen.registerAll()
        let w = World(seed: 5663059916303033239, device: sharedSystemDevice, save: nil)
        FieldTerrain.newWorlds = true; w.makeFieldWorld()
        w.renderDistance = 4
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true
        SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.menu = nil
        g.player.pos = V3(-4921.4, 107 + Float(YOFF), 2260.3)
        _ = w.loadSync(center: g.player.pos, radius: 4)
        g.tick(1.0 / 72)
        func top(_ x: Int, _ z: Int) -> Int {
            var y = CH - 1
            while y > 1 && !w.groundAt(x, y, z) && w.builtBlock(x, y, z) == AIR { y -= 1 }
            return y
        }
        var fails = 0
        func settle(_ s: Ship?, _ what: String) {
            guard let s else { print("FAIL toppletest: \(what) did not come down as one body"); fails += 1; return }
            let name = s.root.name, n = s.blockCount
            let y0 = s.pos.y
            var tops: [String] = []
            for sec in 1...4 {
                for _ in 0..<72 { g.menu = nil; g.tick(1.0 / 72) }
                // (a felled tree sheds its crown once still: the trunk is a new body)
                let cur = w.ships.list.filter { $0.root.name == name }.min { simd_length($0.pos - s.pos) < simd_length($1.pos - s.pos) }
                tops.append(cur.map { String(format: "%ds %.1f%@", sec, $0.pos.y - y0, $0.asleep ? " asleep" : "") } ?? "\(sec)s gone")
            }
            print("toppletest: \(what): one body of \(n) blocks (\(name)); its height from the start: " + tops.joined(separator: ", "))
        }
        let brick = Blocks.id("stone_bricks")         // (built: plain stone set in a field world joins the ground)
        // The tower, 12 blocks east of him, on one stone.
        let tx = -4908, tz = 2260, g0 = top(tx, tz) + 1
        var hi = g0
        for dz in -4...3 { for dx in -4...3 { hi = max(hi, top(tx + dx, tz + dz) + 1) } }
        let ty = hi + 2                                     // (clear of the slope round it: it stands on its column alone)
        w.restoring = true                                  // (built as generation would: no checks until a change)
        for y in g0...ty { w.setBlock(tx, y, tz, brick) }
        for y in 1...50 { for dz in -3...2 { for dx in -3...2 { w.setBlock(tx + dx, ty + y, tz + dz, brick) } } }
        w.restoring = false
        let ships0 = w.ships.list.count
        for y in stride(from: ty, through: g0, by: -1) { w.setBlock(tx, y, tz, AIR) }      // (its column knocked out)
        for _ in 0..<40 { g.tick(1.0 / 72) }
        let tower = w.ships.list.dropFirst(ships0).first { $0.root.name == Game.toppledName }
        let left = (1...50).reduce(0) { n, y in n + (w.builtBlock(tx, ty + y, tz) == brick ? 1 : 0) }
        if left > 0 { print("FAIL toppletest: \(left) tower blocks still stand in the air"); fails += 1 }
        settle(tower, "tower cut from its footing")
        // The birch, 10 blocks west, on a one-block plinth of planks.
        let log = Blocks.id("birch_log"), leaf = Blocks.id("birch_leaves"), plank = Blocks.id("birch_planks")
        let bx = -4932, bz = 2260, by = top(bx, bz) + 1
        w.restoring = true
        w.setBlock(bx, by, bz, plank)
        for y in 1...6 { w.setBlock(bx, by + y, bz, log) }
        for dy in 4...7 { for dz in -2...2 { for dx in -2...2 where (dx != 0 || dz != 0 || dy == 7) && abs(dx) + abs(dz) < 4 {
            w.setBlock(bx + dx, by + dy, bz + dz, leaf)
        } } }
        w.restoring = false
        let ships1 = w.ships.list.count
        w.setBlock(bx, by, bz, AIR)
        for _ in 0..<40 { g.tick(1.0 / 72) }
        let tree = w.ships.list.dropFirst(ships1).first { Felling.isFelled($0) }
        if let t = tree {
            let gr = t.grid
            let secs = ShipMesh.build(sx: gr.sx, sy: gr.sy, sz: gr.sz, blocks: gr.blocks, only: nil, trunks: !Felling.roundTrunks)
            let blob = secs.reduce(Int32(0)) { $0 + $1.1.kinds[MeshKind.blob] }, cube = secs.reduce(Int32(0)) { $0 + $1.1.kinds[MeshKind.cube] }
            print("toppletest: falling birch mesh: \(blob) leaf-blob vertices, \(cube) cube vertices (round trunks \(Felling.roundTrunks))")
            if blob == 0 { print("FAIL toppletest: the falling tree's leaves are drawn as cubes"); fails += 1 }
        }
        settle(tree, "birch on a broken plinth")
        // P411: a placed deck gun is the gun it will be from its first drawing, not from its first tick.
        for (name, want) in [("deck_gun@grey", HeavyTurret.lightVariant)] {
            guard let m = Mob.structureMob(name, at: g.player.pos + V3(40, 0, 0)) else { print("FAIL toppletest: no \(name)"); fails += 1; continue }
            let v0 = m.variant
            Mob.settleLooks([m], w)
            print("toppletest: \(name) placed as variant \(v0), drawn as \(m.variant) (small tower gun \(want))")
            if m.variant != want { print("FAIL toppletest: \(name) is drawn as the big gun until it ticks"); fails += 1 }
        }
        print(fails == 0 ? "PASS toppletest" : "FAIL toppletest: \(fails)")
        return fails == 0 ? 0 : 1
    }
}
