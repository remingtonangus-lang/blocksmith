import Foundation
import simd

// questcheck --fallenoaks: Nov 15 playtest (08:14:38-08:14:54 at -44 71 39 and -48 70 46: "This log was hovering and then
// it corrected to sitting down... We don't do patches. We fix the problem", "This log's hovering. How is that
// possible?"). Fallen oaks in field worlds over five seeds (200 at least): every length lies on its ground (no air under
// it), each is a lying log from the start (its axis along the trunk, not upright wood the mesher has to guess about), and
// nothing moves them: in the first 10 s of play no felled body, no debris body and no change to any of their cells.
enum FallenOakCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let wood = Blocks.has("oak_wood") ? Blocks.groupBase[Int(Blocks.id("oak_wood"))] : AIR
        let logG = Blocks.groupBase[Int(LOG)]
        var trunks = 0, cellsAll = 0, airUnder = 0, upright = 0, changed = 0, bodies = 0, short = 0
        var notes: [String] = []
        let seeds: [UInt64] = [530054557992772521, 12345, 4242, 7639458412018979794, 99173]
        for seed in seeds {
            let w = World(seed: seed, device: g0.world.device, save: nil)
            w.makeFieldWorld()
            w.renderDistance = 4; w.activeDistance = 4
            let g = Game(world: w, save: nil, persistent: false)
            g.paused = false; g.survival = false
            var cells: [IVec3: BlockID] = [:]
            var found = 0
            // Spots spiralling out from spawn until this seed has given 40 trunks (or 6 spots).
            let spots: [(Int, Int)] = [(0, 0), (160, 0), (0, 160), (-160, 0), (0, -160), (160, 160)]
            for (sx, sz) in spots where found < 40 {
                let at = V3(Float(sx) + 0.5, 200, Float(sz) + 0.5)
                g.player.pos = at; g.player.flying = true; w.activeCenter = at
                _ = w.loadSync(center: at, radius: 4)
                let r = 3 * CS
                var seen = Set<IVec3>()
                for z in (sz - r)...(sz + r) { for x in (sx - r)...(sx + r) where w.isLoaded(x, z) {
                    for y in 64..<300 {
                        let b = w.builtBlock(x, y, z)
                        let gb = Blocks.groupBase[Int(b)]
                        guard gb == wood || (gb == logG && b != LOG) else { continue }
                        let p = IVec3(x, y, z)
                        guard !seen.contains(p) else { continue }
                        // A lying length: no log over or under it (a tree's trunk is tree wood; built wood stands in walls).
                        let over = Blocks.groupBase[Int(w.builtBlock(x, y + 1, z))], under = Blocks.groupBase[Int(w.builtBlock(x, y - 1, z))]
                        guard over != wood && over != logG && under != wood && under != logG else { continue }
                        // The trunk: the run along x or z at this height.
                        var run: [IVec3] = [p]
                        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                            var k = 1
                            while k < 8 {
                                let q = IVec3(x + dx * k, y, z + dz * k)
                                let qb = Blocks.groupBase[Int(w.builtBlock(q.x, q.y, q.z))]
                                guard (qb == wood || qb == logG), !seen.contains(q) else { break }
                                run.append(q); k += 1
                            }
                        }
                        for q in run { seen.insert(q) }
                        guard run.count >= 2 || gb == wood else { continue }
                        found += 1; trunks += 1
                        if run.count < 3 { short += 1 }
                        for q in run {
                            let qb = w.builtBlock(q.x, q.y, q.z)
                            cells[q] = qb
                            if !w.groundAt(q.x, q.y - 1, q.z) && !Blocks.collide[Int(w.builtBlock(q.x, q.y - 1, q.z))] {
                                airUnder += 1
                                if notes.count < 6 { notes.append("air under \(q.x) \(q.y - YOFF) \(q.z) (seed \(seed))") }
                            }
                            if ShapeTrunks.axisOf[Int(qb)] == 1 { upright += 1 }
                        }
                    }
                } }
            }
            cellsAll += cells.count
            // Ten seconds of play round the last spot: nothing may move them.
            let felled0 = Felling.felled, toppled0 = Felling.toppled
            var debrisPeak = 0
            for _ in 0..<720 { g.tick(1.0 / 72); debrisPeak = max(debrisPeak, g.debris.count) }
            bodies += Felling.felled - felled0 + Felling.toppled - toppled0 + debrisPeak + Felling.falls.count
            for (q, b) in cells where w.builtBlock(q.x, q.y, q.z) != b {
                changed += 1
                if notes.count < 10 { notes.append("changed \(q.x) \(q.y - YOFF) \(q.z) (seed \(seed))") }
            }
            print("fallenoaks: seed \(seed): \(found) trunks, \(cells.count) cells")
        }
        for n in notes { print("fallenoaks:   \(n)") }
        check(trunks >= 200 && airUnder == 0 && changed == 0 && bodies == 0,
              "Nov 15 fallen oaks: \(trunks) over 5 field seeds (\(cellsAll) lengths): \(airUnder) with air under, \(changed) changed and \(bodies) bodies in the first 10 s")
        check(TreeShapes.oldLitterLie || (upright == 0 && short == 0),
              "Nov 15 fallen oaks: every length a lying log along its trunk (\(upright) upright), no trunk shorter than 3 (\(short))")
    }
}
