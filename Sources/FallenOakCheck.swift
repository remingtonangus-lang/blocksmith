import Foundation
import simd

// questcheck --fallenoaks: Nov 15 playtest (08:14:38-08:14:54 at -44 71 39 and -48 70 46: "This log was hovering and then
// it corrected to sitting down... We don't do patches. We fix the problem", "This log's hovering. How is that
// possible?"). Fallen oaks in field worlds over five seeds (180 at least): every length lies on its ground (no air under
// it), each is a lying log from the start (its axis along the trunk, not upright wood the mesher has to guess about), and
// nothing moves them: in the first 10 s of play no felled body, no debris body and no change to any of their cells.
enum FallenOakCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let wood = Blocks.has("oak_wood") ? Blocks.groupBase[Int(Blocks.id("oak_wood"))] : AIR
        let logG = Blocks.groupBase[Int(LOG)]
        var trunks = 0, cellsAll = 0, airUnder = 0, upright = 0, changed = 0, bodies = 0, short = 0, mossy = 0
        let moss = Blocks.has("moss_carpet") ? Blocks.id("moss_carpet") : AIR
        var notes: [String] = [], uprightNotes: [String] = []
        var tested = 0
        let seeds: [UInt64] = [530054557992772521, 12345, 4242, 7639458412018979794, 99173]
        for seed in seeds {
            let w = World(seed: seed, device: g0.world.device, save: nil)
            w.makeFieldWorld()
            w.renderDistance = 4; w.activeDistance = 4
            let g = Game(world: w, save: nil, persistent: false)
            g.paused = false; g.survival = false
            var cells: [IVec3: BlockID] = [:]
            var found = 0
            // Spots in the woods (fallen oaks lie only there, one oak in fifty), spiralling out from spawn in 112-block
            // steps, until this seed has given 40 trunks or 20 spots. (Walking spots round spawn found 12 trunks in two
            // seeds' 12 spots, most of them in plains.)
            let spots = woods(w.gen, 20)
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
                        // A fallen oak lies bare on the floor; wood with leaves round it is a standing tree's bough.
                        let leafy = run.contains { q in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)].contains { d in
                            Mesher.leafT[Int(w.builtBlock(q.x + d.0, q.y + d.1, q.z + d.2))] } }
                        guard !leafy else { continue }
                        found += 1; trunks += 1
                        if run.count < 3 { short += 1 }
                        for q in run {
                            let qb = w.builtBlock(q.x, q.y, q.z)
                            cells[q] = qb
                            if !w.groundAt(q.x, q.y - 1, q.z) && !Blocks.collide[Int(w.builtBlock(q.x, q.y - 1, q.z))] {
                                airUnder += 1
                                if notes.count < 6 { notes.append("air under \(q.x) \(q.y - YOFF) \(q.z) (seed \(seed))") }
                            }
                            // (A trunk's stump stands upright by its first length, as a log: only the lengths are oak wood.)
                            if Blocks.groupBase[Int(qb)] == wood && ShapeTrunks.axisOf[Int(qb)] == 1 {
                                upright += 1
                                if uprightNotes.count < 6 {
                                    uprightNotes.append("upright \(Blocks.key(qb)) at \(q.x) \(q.y - YOFF) \(q.z), run \(run.count) (seed \(seed))")
                                }
                            }
                            if moss != AIR && w.builtBlock(q.x, q.y + 1, q.z) == moss { mossy += 1 }
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
            // Only cells still loaded: the spots before the last were let go as the camera moved on (an unloaded cell reads
            // as air, which counted 466 of them as "changed").
            for (q, b) in cells where w.isLoaded(q.x, q.z) {
                tested += 1
                guard w.builtBlock(q.x, q.y, q.z) != b else { continue }
                changed += 1
                if notes.count < 10 { notes.append("changed \(q.x) \(q.y - YOFF) \(q.z) (seed \(seed))") }
            }
            print("fallenoaks: seed \(seed): \(found) trunks, \(cells.count) cells, \(spots.count) spots in the woods")
        }
        for n in notes + uprightNotes { print("fallenoaks:   \(n)") }
        check(trunks >= 180 && airUnder == 0 && tested >= 20 && changed == 0 && bodies == 0,
              "Nov 15 fallen oaks: \(trunks) over 5 field seeds (\(cellsAll) lengths): \(airUnder) with air under, \(changed) of \(tested) still loaded changed and \(bodies) bodies in the first 10 s")
        check(TreeShapes.oldLitterLie || (upright == 0 && short == 0),
              "Nov 15 fallen oaks: every length a lying log along its trunk (\(upright) upright), no trunk shorter than 3 (\(short))")
        check(TreeShapes.oldLitterMoss || mossy == 0, "Nov 15 fallen oaks: no moss carpet on them (\(mossy) lengths)")
    }

    // Up to n spots whose column and four points 40 out are oak woods (forest, flower forest, dark forest).
    static func woods(_ gen: TerrainGenerator, _ n: Int) -> [(Int, Int)] {
        let oaks: Set<Biome> = [.forest, .flowerForest, .darkForest]
        var out: [(Int, Int)] = []
        var x = 0, z = 0, dx = 0, dz = -1
        for _ in 0..<4000 where out.count < n {
            let wx = x * 112 + 8, wz = z * 112 + 8
            if [(0, 0), (40, 0), (-40, 0), (0, 40), (0, -40)].allSatisfy({ oaks.contains(gen.column(wx + $0.0, wz + $0.1).biome) }) { out.append((wx, wz)) }
            if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
            x += dx; z += dz
        }
        return out
    }
}
