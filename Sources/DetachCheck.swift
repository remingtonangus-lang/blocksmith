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

    // Nov 15 (the headset's capture of 08:35:47, piloting the Ironback Crawler in a fight at the citadel: a 97 ms tick,
    // 26.9 ms of it "shells: hull blast"): a warship's shell on another capital hull is the common burst (power 4) and
    // then ShipManager.blast at one and a half times that. questcheck --hullblast: twelve such hits walked along the
    // flank of a fresh crawler and a fresh frigate, each part timed, the slowest shown stage by stage.
    static func hullBlast(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        for kind in ["crawler", "frigate"] {
            let n1 = w.ships.list.count
            let home = g.player.pos + V3(0, 0, 140)
            w.ships.spawnCapital(kind, home: IVec3(Int(home.x), 0, Int(home.z)), yaw: 0, region: nil, sync: true)
            guard let e = w.ships.list.dropFirst(n1).first(where: { $0.kinematic && $0.parent == nil }) else { check(false, "hullblast: no \(kind)"); continue }
            defer { w.ships.remove(e); w.ships.capState.removeValue(forKey: e.id); w.ships.shockwaves.removeAll(); g.arms.breaches.removeAll() }
            _ = w.loadSync(center: e.pos, radius: 3)
            // (her first mesh job holds her grid: a hit before it ends copies the whole grid, which play never does)
            var waited = 0
            while e.mesh.building > 0 && waited < 3000 { usleep(2000); waited += 1 }
            func hull() -> Int { w.ships.list.filter { $0.root === e.root }.reduce(0) { $0 + $1.blockCount } }
            var worstA = 0.0, lapsA = "", worstB = 0.0, lapsB = "", sumA = 0.0, sumB = 0.0, torn = 0
            let ships0 = w.ships.list.count, drops0 = g.drops.items.count
            for k in 0..<12 {
                let c = (e.worldMin + e.worldMax) * 0.5
                let along = (e.worldMax.z - e.worldMin.z) * (Float(k % 6) / 6 - 0.42)
                // (the flank's skin at mid height: walked in from outside until a hull cell is met)
                var p = V3(e.worldMax.x + 1, c.y + Float(k / 6) * 3 - 1, c.z + along)
                var steps = 0
                while steps < 80 && !w.ships.shipBlock(at: p, except: -1) { p.x -= 0.5; steps += 1 }
                let before = hull()
                Explosion.worstMs = 0; Explosion.worstLaps = ""
                Explosion.explode(at: p, power: 4, game: g, breakBlocks: true)
                let a = Explosion.worstMs, la = Explosion.worstLaps
                Explosion.worstMs = 0; Explosion.worstLaps = ""
                Explosion.lapStart()
                w.ships.blast(at: p, power: 6, game: g)
                Explosion.lapEnd("end")
                let b = Explosion.worstMs, lb = Explosion.worstLaps
                sumA += a; sumB += b
                if a > worstA { worstA = a; lapsA = la }
                if b > worstB { worstB = b; lapsB = lb }
                torn += before - hull()
            }
            print(String(format: "hullblast: %@ (%d blocks, grid %dx%dx%d): 12 hits tore %d blocks, %d new bodies, %d drops", kind, hull(), e.grid.sx, e.grid.sy, e.grid.sz,
                         torn, w.ships.list.count - ships0, g.drops.items.count - drops0))
            print(String(format: "hullblast:   the burst: average %.2f ms, slowest %.2f ms (%@)", sumA / 12, worstA, lapsA))
            print(String(format: "hullblast:   the hull blast: average %.2f ms, slowest %.2f ms (%@)", sumB / 12, worstB, lapsB))
            check(worstA + worstB < 6, String(format: "hullblast: a warship's shell on a %@'s hull takes %.1f ms at worst on this machine (burst %.1f + hull blast %.1f; want under 6: the headset is several times slower)", kind, worstA + worstB, worstA, worstB))
        }
    }
}
