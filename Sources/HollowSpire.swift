import Foundation

// End cities on the outer islands (grid spacing 20 chunks, separation 11; only where the island
// surface is high enough): a violite house, a stacked tower with a spiral stair, a wide top room with
// treasure chests and shellsentrys, and often a bridge out to an end ship whose hold carries an glider wings.
enum HollowSpire {
    static func type(_ gen: HollowGen) -> StructureType {
        StructureType(name: "end_city", spacing: 20, separation: 11, salt: 10387313, reach: 5) { [unowned gen] seed, cx, cz in
            let ox = cx * CS + 8, oz = cz * CS + 8
            guard ox * ox + oz * oz > 1000 * 1000 else { return nil }
            // Needs solid island under the whole base (checked at the centre and four corners).
            guard let y0 = gen.surface(ox, oz), y0 >= YOFF + 60 else { return nil }
            for (dx, dz) in [(-5, -5), (5, -5), (-5, 5), (5, 5)] { guard gen.surface(ox + dx, oz + dz) != nil else { return nil } }
            var rng = SRng(seed)
            let floors = rng.range(2, 4)
            let ship = rng.chance(0.6)
            let shipDir = rng.int(4)
            let s = rng.next()
            let topY = y0 + 1 + 6 + floors * 5
            var pieces: [Piece] = []
            // The box covers the doorway steps out to 11 blocks (writes land only in chunks the box overlaps).
            pieces.append(Piece(min: IVec3(ox - 12, y0 - 10, oz - 12), max: IVec3(ox + 12, topY + 10, oz + 12)) { w in
                buildCity(&w, ox: ox, oz: oz, y0: y0 + 1, floors: floors, seed: s)
            })
            if ship {
                let (dx, dz) = [(1, 0), (-1, 0), (0, 1), (0, -1)][shipDir]
                let bx = ox + dx * 6, bz = oz + dz * 6
                let sx = ox + dx * 30, sz = oz + dz * 30, sy = topY + 6
                pieces.append(Piece(min: IVec3(min(bx, sx) - 12, topY - 1, min(bz, sz) - 12), max: IVec3(max(bx, sx) + 12, sy + 14, max(bz, sz) + 12)) { w in
                    // Bridge 7 + 7 steps: the top step sits right before the ship's tip (deck at a = -10, 20 out),
                    // level with the deck. 13 long put the steps under the hull, the head hit the keel three steps up
                    // (structcheck: every ship's three hold chests unreachable, run 361).
                    bridge(&w, from: IVec3(bx, topY, bz), dx: dx, dz: dz, length: 7)
                    buildShip(&w, cx: sx, y: sy, cz: sz, alongX: dx != 0, seed: s &+ 99)
                })
            }
            return StructureStart(kind: "end_city", pieces: pieces, anchor: IVec3(ox + 8, y0 + 2, oz + 8))
        }
    }

    static var purpur: BlockID { Blocks.id("purpur_block") }
    static var pillar: BlockID { Blocks.id("purpur_pillar") }

    static func box(_ w: inout StructWriter, _ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, floor: BlockID, wall: BlockID) {
        for y in y0...y1 { for z in z0...z1 { for x in x0...x1 where w.inside(x, y, z) {
            let edge = x == x0 || x == x1 || z == z0 || z == z1
            let corner = (x == x0 || x == x1) && (z == z0 || z == z1)
            if y == y0 { w.set(x, y, z, floor) }
            else if y == y1 { w.set(x, y, z, wall) }
            else if corner { w.set(x, y, z, pillar) }
            else if edge {
                let window = (y - y0) % 5 == 2 && (x + z) % 3 == 0
                w.set(x, y, z, window ? Blocks.id("glass") : wall)
            } else { w.set(x, y, z, AIR) }
        } } }
    }

    static func buildCity(_ w: inout StructWriter, ox: Int, oz: Int, y0: Int, floors: Int, seed: UInt64) {
        var rng = SRng(seed)
        // Foundation down into the island, then the house.
        for z in (oz - 5)...(oz + 5) { for x in (ox - 5)...(ox + 5) { w.pillarDown(x, y0 - 1, z, purpur, minY: y0 - 6) } }
        box(&w, ox - 5, y0, oz - 5, ox + 5, y0 + 6, oz + 5, floor: purpur, wall: purpur)
        // A doorway on every side, each with a slab step up to the sill (the floor sits a block above the island): one
        // door facing north often looked out over the island's edge, so no walk reached it (structcheck 33/33).
        let slab = Blocks.id("purpur_slab"), st = Blocks.id("purpur_stairs")
        w.fill(ox - 1, y0 + 1, oz - 5, ox + 1, y0 + 3, oz - 5, AIR)
        w.fill(ox - 1, y0 + 1, oz + 5, ox + 1, y0 + 3, oz + 5, AIR)
        w.fill(ox - 5, y0 + 1, oz - 1, ox - 5, y0 + 3, oz + 1, AIR)
        w.fill(ox + 5, y0 + 1, oz - 1, ox + 5, y0 + 3, oz + 1, AIR)
        w.fill(ox - 1, y0, oz - 6, ox + 1, y0, oz - 6, slab); w.fill(ox - 1, y0 + 1, oz - 7, ox + 1, y0 + 3, oz - 6, AIR)
        w.fill(ox - 1, y0, oz + 6, ox + 1, y0, oz + 6, slab); w.fill(ox - 1, y0 + 1, oz + 6, ox + 1, y0 + 3, oz + 7, AIR)
        w.fill(ox - 6, y0, oz - 1, ox - 6, y0, oz + 1, slab); w.fill(ox - 7, y0 + 1, oz - 1, ox - 6, y0 + 3, oz + 1, AIR)
        w.fill(ox + 6, y0, oz - 1, ox + 6, y0, oz + 1, slab); w.fill(ox + 6, y0 + 1, oz - 1, ox + 7, y0 + 3, oz + 1, AIR)
        // Where the island drops away below the sill, stairs (high side toward the house) step down from each slab to
        // the ground, pillared (a slab over air was a step no one could climb onto; structcheck: every end city
        // reached only the island beside its walls, run 355).
        let outward: [(Int, Int, Int)] = [(0, -1, 1), (0, 1, 0), (-1, 0, 3), (1, 0, 2)]
        for (dx, dz, facing) in outward {
            for k in 1...5 {
                let d = 6 + k, yy = y0 - k
                let cx = ox + dx * d, cz = oz + dz * d
                if Blocks.collide[Int(w.get(cx, yy, cz))] && Blocks.collide[Int(w.get(cx, yy - 1, cz))] { break }
                for a in -1...1 {
                    let x = cx + (dz != 0 ? a : 0), z = cz + (dx != 0 ? a : 0)
                    w.set(x, yy, z, st + BlockID(facing))
                    w.fill(x, yy + 1, z, x, yy + 3, z, AIR)
                    w.pillarDown(x, yy - 1, z, purpur, minY: yy - 8)
                }
            }
        }
        for (tx, tz) in [(-4, -4), (4, -4), (-4, 4), (4, 4)] { w.set(ox + tx, y0 + 1, oz + tz, Blocks.id("end_rod")) }
        // Tower floors, each with a spiral stair segment and an opening in the floor above.
        var y = y0 + 6
        for f in 0...floors {
            let top = f == floors
            let r = top ? 6 : 3
            box(&w, ox - r, y, oz - r, ox + r, y + (top ? 8 : 5), oz + r, floor: purpur, wall: purpur)
            if f > 0 {
                // Top step of the stair below pokes through this floor next to the opening; the floor above the
                // two steps before it stays open too (this floor was laid over their headroom: a head bump).
                // ...and over the second step (climbing from it, a head met this floor: structcheck, every end city's
                // walk ended on that step, run 357).
                w.set(ox - 2, y, oz + 1, AIR)
                w.set(ox - 2, y, oz, AIR)
                w.set(ox - 2, y, oz - 1, AIR)
                w.set(ox - 2, y, oz - 2, st)
            }
            if !top {
                // Stairs climbing along the inner wall to a hole in the ceiling.
                for i in 0..<5 {
                    let (sx, sz, facing) = [(-2, 2, 0), (-2, 1, 0), (-2, 0, 0), (-2, -1, 0), (-2, -2, 0)][i]
                    w.set(ox + sx, y + 1 + i, oz + sz, st + BlockID(facing))
                    w.fill(ox + sx, y + 2 + i, oz + sz, ox + sx, y + 4 + i, oz + sz, AIR)
                }
                w.set(ox + 2, y + 3, oz + 2, Blocks.id("end_rod"))
                y += 5
            } else {
                // Treasure room.
                w.chest(ox + 4, y + 1, oz + 4, loot: "end_city_treasure", seed: rng.next(), facing: 0)
                w.chest(ox - 4, y + 1, oz + 4, loot: "end_city_treasure", seed: rng.next(), facing: 0)
                for (tx, tz) in [(-5, 0), (5, 0), (0, 5)] { w.set(ox + tx, y + 4, oz + tz, Blocks.id("end_rod")) }
                w.mob("shulker", V3(Float(ox + 5) + 0.5, Float(y + 1), Float(oz - 5) + 0.5))
                w.mob("shulker", V3(Float(ox - 5) + 0.5, Float(y + 1), Float(oz - 5) + 0.5))
                w.mob("shulker", V3(Float(ox) + 0.5, Float(y + 7), Float(oz + 4) + 0.5))
            }
        }
        // Stairs from the house up through its ceiling into the first tower floor (the house had no way up, so the
        // tower and its treasure room were unreachable on foot: structcheck poi_unreachable 33 of 33).
        for i in 0..<6 {
            let sz = oz + 3 - i
            w.set(ox - 2, y0 + 1 + i, sz, st)
            w.fill(ox - 2, y0 + 2 + i, sz, ox - 2, y0 + 4 + i, sz, AIR)
        }
        w.mob("shulker", V3(Float(ox + 4) + 0.5, Float(y0 + 1), Float(oz + 4) + 0.5))
    }

    static func bridge(_ w: inout StructWriter, from p: IVec3, dx: Int, dz: Int, length: Int) {
        for i in 0..<length {
            let x = p.x + dx * i, z = p.z + dz * i
            for s in -1...1 {
                let bx = x + (dz != 0 ? s : 0), bz = z + (dx != 0 ? s : 0)
                w.set(bx, p.y, bz, purpur)
                w.fill(bx, p.y + 1, bz, bx, p.y + 3, bz, AIR)
            }
            if i % 4 == 0 { w.set(x + (dz != 0 ? 1 : 0), p.y + 1, z + (dx != 0 ? 1 : 0), Blocks.id("end_rod")) }
        }
        // Steps up to the ship deck (the seventh is level with the deck tip).
        let end = IVec3(p.x + dx * length, p.y, p.z + dz * length)
        for i in 0..<7 {
            let x = end.x + dx * i, z = end.z + dz * i
            for s in -1...1 { w.set(x + (dz != 0 ? s : 0), p.y + i, z + (dx != 0 ? s : 0), purpur) }
        }
    }

    // A floating ship ~20 long: violite hull, obsidian keel, a mast with black sails, a hold with two
    // treasure chests and the glider wings chest, shellsentrys on deck.
    static func buildShip(_ w: inout StructWriter, cx: Int, y: Int, cz: Int, alongX: Bool, seed: UInt64) {
        var rng = SRng(seed)
        func put(_ a: Int, _ h: Int, _ b: Int, _ blk: BlockID) {
            // a = along the ship, b = across, h = height offset.
            if alongX { w.set(cx + a, y + h, cz + b, blk) } else { w.set(cx + b, y + h, cz + a, blk) }
        }
        for a in -10...10 {
            let taper = abs(a) > 7 ? abs(a) - 7 : 0
            let half = 3 - taper
            guard half >= 0 else { continue }
            for b in -half...half {
                put(a, 0, b, purpur)                                   // deck
                if abs(b) == half { put(a, 1, b, purpur) }             // gunwale
            }
            for b in -max(0, half - 1)...max(0, half - 1) { put(a, -1, b, purpur) }
            put(a, -2, 0, OBSIDIAN)
        }
        // Hold (below deck, two blocks tall so it can be walked) with chests, and a two-step hatch down into it.
        for a in -4...4 { for b in -1...1 { put(a, -1, b, AIR); put(a, -2, b, AIR) } }
        for a in -4...4 { for b in -2...2 where abs(b) == 2 { put(a, -1, b, purpur); put(a, -2, b, purpur) } }
        for a in -4...4 { for b in -2...2 { put(a, -3, b, purpur) }; put(a, -4, 0, OBSIDIAN) }
        // Hatch three long: stepping off the second step onto the hold floor, the head passes under the third
        // (two long, the deck met it: structcheck, the hold's chests unreachable on every ship, run 358).
        put(1, 0, 0, AIR); put(2, 0, 0, AIR); put(3, 0, 0, AIR)          // hatch
        put(1, -1, 0, purpur); put(2, -2, 0, purpur)                   // steps
        let chestAt: (Int, Int) -> IVec3 = { a, b in alongX ? IVec3(cx + a, y - 2, cz + b) : IVec3(cx + b, y - 2, cz + a) }
        let c1 = chestAt(-3, 0), c2 = chestAt(4, 0), c3 = chestAt(-1, 1)
        w.chest(c1.x, c1.y, c1.z, loot: "end_city_treasure", seed: rng.next(), facing: 0)
        w.chest(c2.x, c2.y, c2.z, loot: "end_city_treasure", seed: rng.next(), facing: 0)
        w.chest(c3.x, c3.y, c3.z, loot: "end_ship_elytra", seed: rng.next(), facing: 0)
        // Mast and sails.
        let wool = Blocks.has("black_wool") ? Blocks.id("black_wool") : OBSIDIAN
        for h in 1...10 { put(-1, h, 0, pillar) }
        for h in 4...9 { for b in -3...3 where abs(b) > 0 { put(-2, h, b, wool) } }
        // Bow and stern tips open where the bridge steps arrive; the lamps sit on the gunwale instead.
        put(10, 1, 0, AIR); put(-10, 1, 0, AIR)
        put(9, 2, 1, Blocks.id("end_rod")); put(-9, 2, 1, Blocks.id("end_rod"))
        let s1 = alongX ? V3(Float(cx + 6) + 0.5, Float(y + 1), Float(cz) + 0.5) : V3(Float(cx) + 0.5, Float(y + 1), Float(cz + 6) + 0.5)
        let s2 = alongX ? V3(Float(cx - 6) + 0.5, Float(y + 1), Float(cz) + 0.5) : V3(Float(cx) + 0.5, Float(y + 1), Float(cz - 6) + 0.5)
        w.mob("shulker", s1)
        w.mob("shulker", s2)
    }
}
