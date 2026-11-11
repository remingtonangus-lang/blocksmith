import Foundation
import simd

// Nov 4 (frame rate, the worst-case soak: a shell's blast on a crawler took 11 of its 12 ms in the loose-piece search):
// questcheck --detachcheck blasts holes in a capital-sized slab hull (64 x 10 x 64, 40,960 blocks) and checks the
// pieces that break away, and how long the search takes for a hole cut clean through the middle (BS_DETACHOLD=1 runs the
// search as it was before).
enum DetachCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let stone = Blocks.id("stone")
        func slab() -> Ship {
            let grid = ShipGrid(sx: 64, sy: 16, sz: 64)
            for x in 0..<64 { for z in 0..<64 { for y in 0..<10 { grid.set(x, y, z, stone) } } }
            for y in 10..<15 { grid.set(5, y, 5, stone) }           // a post on the deck, joined by its foot
            let s = Ship(id: w.ships.newId(), grid: grid)
            s.name = "Detach Slab"
            s.rebuild()
            s.kinematic = true
            s.pos = g.player.pos + V3(0, 300, 0)
            s.prevPos = s.pos
            s.updateBounds()
            w.ships.add(s)
            return s
        }
        func wrecks(_ s: Ship) -> [Ship] { w.ships.list.filter { $0.name == s.name + " wreckage" } }
        func clear(_ s: Ship) { for x in wrecks(s) { w.ships.remove(x) }; w.ships.remove(s) }

        // 1. The post's foot shot out: the four blocks above it break away as one piece.
        var s = slab()
        w.ships.removeCells(s, [IVec3(5, 10, 5)], chipped: [], center: s.toWorld(V3(5.5, 10.5, 5.5)), power: 2, game: nil)
        let post = wrecks(s).map { $0.blockCount }
        clear(s)
        // 2. A ring cut round a 3 x 3 pillar, all the way through: the pillar (90 blocks) breaks away.
        s = slab()
        var ring = Set<IVec3>()
        for x in 40...44 { for z in 40...44 where !(x >= 41 && x <= 43 && z >= 41 && z <= 43) { for y in 0..<10 { ring.insert(IVec3(x, y, z)) } } }
        w.ships.removeCells(s, ring, chipped: [], center: s.toWorld(V3(42.5, 5, 42.5)), power: 4, game: nil)
        let pillar = wrecks(s).map { $0.blockCount }
        clear(s)
        // 3. A 24 x 24 hole clean through the middle (a heavy shell's bowl is 26 across): nothing breaks away; the time the search takes.
        s = slab()
        var hole = Set<IVec3>()
        for x in 20..<44 { for z in 20..<44 { for y in 0..<10 { hole.insert(IVec3(x, y, z)) } } }
        w.ships.removeCells(s, hole, chipped: [], center: s.toWorld(V3(32, 5, 32)), power: 6, game: nil, detach: false)
        let t0 = CFAbsoluteTimeGetCurrent()
        w.ships.detachLoose(s, around: Array(hole))
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        let middle = wrecks(s).count
        let left = s.blockCount
        clear(s)
        let mode = DetachLooseTiming.oldSearch ? "the search before Nov 4" : "the search"
        check(post == [4] && pillar == [90] && middle == 0 && left == 40_960 + 5 - 5_760,
              String(format: "detach (%@): a post shot through at its foot breaks away %@; a pillar cut round %@; a hole through the middle breaks away %d pieces (%d blocks left)",
                     mode, "\(post)", "\(pillar)", middle, left))
        check(ms < 3, String(format: "detach (%@): the hole through the middle (5,760 blocks out, 960 cells round it) took %.2f ms (want under 3)", mode, ms))
    }
}
