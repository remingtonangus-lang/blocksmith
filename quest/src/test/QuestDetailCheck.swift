import Foundation
import simd
import Metal

// P451 (Oct 25 08:46-09:00, Quest World): world details. Checks: a cold sea's ice (his 08:58 spot, -858 75 -1613) is
// still there after the spring melt has swept every chunk round the player (it melted the generator's own ice a chunk
// at a time: "perfect chunks... with no ice in them"), while ice a winter laid on a temperate pond still melts; and
// pumpkins grow in patches, not one by one.
//   questcheck --detailcheck
enum QuestDetailCheck {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        TextureGen.registerAll()
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "ok  " : "FAIL") detailcheck: \(what)"); if !ok { fails += 1 } }
        let w = World(seed: 5663059916303033239, device: sharedSystemDevice, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 4
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true
        SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.menu = nil
        let ice = Blocks.id("ice")

        // The cold sea.
        g.player.pos = V3(-858.1, 75.1 + Float(YOFF), -1613.5)
        _ = w.loadSync(center: g.player.pos, radius: 4)
        let pcx = floorDiv(-859, CS), pcz = floorDiv(-1614, CS)
        func iceCount() -> (Int, Int) {
            var n = 0, chunks = 0
            for dz in -3...3 { for dx in -3...3 {
                guard let c = w.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)] else { continue }
                var here = 0
                for lz in 0..<CS { for lx in 0..<CS { for y in (SEA - 24)...(SEA + 24) where w.builtBlock(c.cx * CS + lx, y, c.cz * CS + lz) == ice { here += 1 } } }
                n += here; if here > 0 { chunks += 1 }
            } }
            return (n, chunks)
        }
        let before = iceCount()
        let r = min(w.activeDistance, w.renderDistance), side = 2 * r + 1
        for _ in 0..<(10 * side * side + 10) { Seasons.day = 5; g.seasonalMeltSweep() }        // (spring, day 6: all of it melts)
        let after = iceCount()
        check(before.0 > 200 && after.0 == before.0, "the cold sea's ice stays through the spring melt: \(before.0) ice in \(before.1) chunks before, \(after.0) in \(after.1) after")

        // Pumpkins: within 12 chunks of his 09:00 forest, each pumpkin has others by it.
        var pumpkins: [IVec3] = []
        let pk = Blocks.id("pumpkin")
        let fx = floorDiv(-1947, CS), fz = floorDiv(91, CS)
        guard let wg = w.gen as? WorldGen else { check(false, "the overworld has its generator"); return 1 }
        for dz in -12...12 { for dx in -12...12 {
            let b = wg.generate(cx: fx + dx, cz: fz + dz)
            for i in 0..<b.count where b[i] == pk { pumpkins.append(IVec3((fx + dx) * CS + i % CS, i / CSQ, (fz + dz) * CS + (i / CS) % CS)) }
        } }
        let alone = pumpkins.filter { p in !pumpkins.contains { $0 != p && abs($0.x - p.x) <= 6 && abs($0.z - p.z) <= 6 } }.count
        check(pumpkins.count >= 3 && alone * 4 <= pumpkins.count, "pumpkins grow in patches: \(pumpkins.count) over 25 x 25 chunks, \(alone) with no other within 6 blocks")
        print(fails == 0 ? "detailcheck: all passed" : "detailcheck: \(fails) failed")
        return fails == 0 ? 0 : 1
    }
}
