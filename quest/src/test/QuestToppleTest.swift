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
        // Nov 12 playtest (06:21:17, "that helipad's hovering": a Boreal tower's top over the floors his shells took out).
        // (a) A shell's hole: a 6x6 tower 60 high on its own footing, a 4-block-thick slab of it taken out at once (as a
        // blast carves), the one check the slab queued from a cell in the hole's middle. The top must come down.
        // (BS_OLDLOADSEED=1: the check found nothing built beside its cell and the top hung.)
        do {
            let hx = -4895, hz = 2240
            var base = 0
            for dz in -3...2 { for dx in -3...2 { base = max(base, top(hx + dx, hz + dz) + 1) } }
            w.restoring = true
            for dz in -3...2 { for dx in -3...2 {
                for y in (top(hx + dx, hz + dz) + 1)...(base + 60) { w.setBlock(hx + dx, y, hz + dz, brick) }
            } }
            let s0 = floorDiv(base + 12, 4) * 4
            for y in s0...(s0 + 3) { for dz in -3...2 { for dx in -3...2 { w.setBlock(hx + dx, y, hz + dz, AIR) } } }
            w.restoring = false
            let p = IVec3(hx - 1, s0 + 1, hz - 1)
            if w.loadQueued.insert(IVec3(floorDiv(p.x, 4), floorDiv(p.y, 4), floorDiv(p.z, 4))).inserted { w.loadQueue.append(p) }
            let rim0 = Structure.rimChecks
            for _ in 0..<40 { g.tick(1.0 / 72) }
            var up = 0
            for y in (s0 + 4)...(base + 60) { for dz in -3...2 { for dx in -3...2 where w.builtBlock(hx + dx, y, hz + dz) == brick { up += 1 } } }
            print("toppletest: a 4-thick hole shot through a 60-high tower, checked from the hole's middle: \(up) blocks of its top still stand (\(Structure.rimChecks - rim0) checks from the hole's rim)")
            if up > 0 { print("FAIL toppletest: the top of a tower shot through hangs over the hole (\(up) blocks)"); fails += 1 }
        }
        // (b) Two pieces cut loose by one change: two 6x6x45 stacks high in the air joined by a single block between
        // them. Taken out, both must come down. (BS_OLDLOOSE=1: the first piece found fell, the second hung.)
        do {
            let sx = -4921, sz = 2282
            var base = 0
            for dz in -3...2 { for dx in -3...2 { base = max(base, top(sx + dx, sz + dz) + 1) } }
            base += 40
            w.restoring = true
            for y in 0..<45 { for dz in -3...2 { for dx in -3...2 {
                w.setBlock(sx + dx, base + y, sz + dz, brick); w.setBlock(sx + dx, base + 46 + y, sz + dz, brick)
            } } }
            w.setBlock(sx, base + 45, sz, brick)
            w.restoring = false
            w.setBlock(sx, base + 45, sz, AIR)
            for _ in 0..<60 { g.tick(1.0 / 72) }
            var low = 0, high = 0
            for y in 0..<45 { for dz in -3...2 { for dx in -3...2 {
                if w.builtBlock(sx + dx, base + y, sz + dz) == brick { low += 1 }
                if w.builtBlock(sx + dx, base + 46 + y, sz + dz) == brick { high += 1 }
            } } }
            print("toppletest: two stacks in the air cut apart by one block: \(low) of the lower, \(high) of the upper still stand")
            if low + high > 0 { print("FAIL toppletest: a piece cut loose with another hangs in the air (\(low), \(high))"); fails += 1 }
        }
        // (c) Nov 13 (his note 13:05:46, "all the wire despawned when it fell"): a 5x5 brick platform in the air with
        // copper wire laid over it, cut loose: the wire rides it down.
        // (BS_OLDRIDERS=1: they are left in the air and pop off.)
        do {
            let sx = -4940, sz = 2300
            var base = 0
            for dz in -2...2 { for dx in -2...2 { base = max(base, top(sx + dx, sz + dz) + 1) } }
            base += 30
            let wire = Blocks.id("redstone_wire")
            w.restoring = true
            for dz in -2...2 { for dx in -2...2 { w.setBlock(sx + dx, base, sz + dz, brick); w.setBlock(sx + dx, base + 1, sz + dz, wire) } }
            w.setBlock(sx, base - 1, sz, brick)
            w.restoring = false
            let r0 = Game.ridersTaken
            w.setBlock(sx, base - 1, sz, AIR)
            for _ in 0..<60 { g.tick(1.0 / 72) }
            var left = 0, slab = 0
            for dz in -2...2 { for dx in -2...2 {
                if w.block(sx + dx, base + 1, sz + dz) != AIR { left += 1 }
                if w.builtBlock(sx + dx, base, sz + dz) == brick { slab += 1 }
            } }
            let rode = Game.ridersTaken - r0
            print("toppletest: a wired platform cut loose: \(slab) of 25 slab blocks still up, \(left) of its 25 wires left in the air, \(rode) rode it down")
            if slab > 0 || left > 0 || rode < 25 { print("FAIL toppletest: wire on a falling platform is left behind (\(slab), \(left), \(rode))"); fails += 1 }
        }
        // Nov 13 (the physics revamp; his shelled citadel at Beach -2902 79 2601: "even though it's still technically
        // connected, this wouldn't realistically be able to sustain that much weight"): two 8x8 brick towers 40 high over the slope,
        // each with a storey taken out but for its middle: four columns left under one (too few for what stands on
        // them: the top comes down), sixteen under the other (enough: it stands, weighed all the same).
        // (BS_COLLAPSE=0: both stand, as before.)
        do {
            func tower(_ cx: Int, _ cz: Int, keep: Int) -> (Int, () -> Int) {
                // (the storey shot out lies over the slope round the tower: above it nothing leans on the hill)
                var base = 0
                for dz in -7...6 { for dx in -7...6 { base = max(base, top(cx + dx, cz + dz) + 1) } }
                w.restoring = true
                for dz in -4...3 { for dx in -4...3 { for y in (top(cx + dx, cz + dz) + 1)...(base + 40) { w.setBlock(cx + dx, y, cz + dz, brick) } } }
                w.restoring = false
                let cut = base + 5
                // (the storey shot out, as changes: their checks stop at the fill's bound and ask for the whole piece)
                // (eight high: the corners the check near the change drops land on the storey's floor, and a storey two
                // high was filled by them and stood on its own rubble)
                for y in cut...(cut + 7) { for dz in -4...3 { for dx in -4...3 {
                    let inside = dx >= -keep && dx < keep && dz >= -keep && dz < keep
                    if !inside { w.setBlock(cx + dx, y, cz + dz, AIR) }
                } } }
                return (cut, { var n = 0; for y in (cut + 8)...(base + 40) { for dz in -4...3 { for dx in -4...3 where w.builtBlock(cx + dx, y, cz + dz) == brick { n += 1 } } }; return n })
            }
            let w0 = StructureCollapse.weighed, b0 = StructureCollapse.bodies
            let (_, weakUp) = tower(-4962, 2245, keep: 1)
            let weakAll = weakUp()
            for t in 0..<720 { g.menu = nil; g.tick(1.0 / 72); if StructureCollapse.withWorker { usleep(2000) }; if t > 150 && !StructureCollapse.busy && w.loadQueue.isEmpty && StructureCollapse.weighed > w0 { break } }
            let weakLeft = weakUp(), weakBodies = StructureCollapse.bodies - b0
            let w1 = StructureCollapse.weighed
            let (_, soundUp) = tower(-4962, 2275, keep: 2)
            let soundAll = soundUp()
            for t in 0..<720 { g.menu = nil; g.tick(1.0 / 72); if StructureCollapse.withWorker { usleep(2000) }; if t > 150 && !StructureCollapse.busy && w.loadQueue.isEmpty && StructureCollapse.weighed > w1 { break } }
            let soundLeft = soundUp()
            print(String(format: "toppletest: a storey shot out under an 8x8 tower: on four columns %d of %d blocks above still stand (%d bodies fell); on sixteen %d of %d (asked %d times, weighed whole %d times, %d blocks, read %.1f ms in slices of %.2f ms at most, weighed %.1f ms)",
                         weakLeft, weakAll, weakBodies, soundLeft, soundAll, StructureCollapse.asked, StructureCollapse.weighed - w0, StructureCollapse.lastBlocks,
                         StructureCollapse.lastCaptureMs, StructureCollapse.worstSliceMs, StructureCollapse.lastSolveMs))
            if StructureCollapse.enabled {
                if weakLeft > 0 { print("FAIL toppletest: a tower's top stands on four columns that cannot carry it (\(weakLeft) blocks)"); fails += 1 }
                // (the check near the change takes the corners past the bricks' reach off both towers)
                if soundAll - soundLeft > 64 { print("FAIL toppletest: a tower on sixteen columns that carry it lost \(soundAll - soundLeft) blocks"); fails += 1 }
                if StructureCollapse.weighed - w1 < 1 { print("FAIL toppletest: the tower on sixteen columns was never weighed whole"); fails += 1 }
            }
        }
        // Ledger 125 (the Proving Grounds' circuit builds): a lamp on a signal torch on a stone, and a cobble on wire on a
        // stone, stand; the circuit part carries them down. (BS_OLDCIRCUITLOAD=1: both fall.)
        do {
            let cx = -4990, cz = 2245
            let y0 = top(cx, cz) + 1
            let stone = Blocks.id("stone"), cobble = Blocks.id("cobblestone")
            let torch = Blocks.id("redstone_torch"), wire = Blocks.id("redstone_wire"), lamp = Blocks.id("redstone_lamp")
            w.setBlock(cx, y0, cz, stone); w.setBlock(cx, y0 + 1, cz, torch); w.setBlock(cx, y0 + 2, cz, lamp)
            let y1 = top(cx + 4, cz) + 1
            w.setBlock(cx + 4, y1, cz, stone); w.setBlock(cx + 4, y1 + 1, cz, wire); w.setBlock(cx + 4, y1 + 2, cz, cobble)
            for _ in 0..<300 { g.menu = nil; g.tick(1.0 / 72); if StructureCollapse.withWorker { usleep(1000) } }
            let lampUp = Blocks.groupBase[Int(w.builtBlock(cx, y0 + 2, cz))] == Blocks.groupBase[Int(lamp)]
            let torchUp = Blocks.groupBase[Int(w.builtBlock(cx, y0 + 1, cz))] == Blocks.groupBase[Int(torch)]
            let cobbleUp = w.builtBlock(cx + 4, y1 + 2, cz) == cobble
            let wireUp = Blocks.groupBase[Int(w.builtBlock(cx + 4, y1 + 1, cz))] == Blocks.groupBase[Int(wire)]
            print("toppletest: a lamp on a signal torch stands (\(lampUp), torch \(torchUp)); a cobble on wire stands (\(cobbleUp), wire \(wireUp))")
            if Structure.circuitStrut[Int(torch)] && !(lampUp && torchUp && cobbleUp && wireUp) {
                print("FAIL toppletest: what stands on a circuit part falls (lamp \(lampUp), torch \(torchUp), cobble \(cobbleUp), wire \(wireUp))"); fails += 1
            }
        }
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
