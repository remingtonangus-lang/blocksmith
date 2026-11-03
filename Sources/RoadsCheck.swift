import Foundation
import simd

// P507 (Nov 1 12:40:22, flying over plains at -5574 4571 in his field world: "what ever happened to roads? Like, wasn't
// that a thing we were supposed to have?"): questcheck --roadscheck makes his world (his seed, a field world as the
// headset makes them), lists the roads within 1,500 blocks of his spot, loads the nearest one at 24 points along it and
// counts the points where the road is drawn on the ground (the packed earth a field world's road is laid in).
enum RoadsCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds, p440 = WorldRules.p44
        FieldTerrain.newWorlds = true
        WorldRules.p44 = true                           // (the headset's rules: the host checks turn P44 off for their fixtures)
        defer { FieldTerrain.newWorlds = field0; WorldRules.p44 = p440 }
        let w = World(seed: 1091709452045888406, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 2; w.activeDistance = 2
        let g = Game(world: w, save: nil, persistent: false)
        guard let gen = w.gen as? WorldGen else { check(false, "roadscheck: needs the overworld generator"); return }
        let px = -5574, pz = 4571
        let segs = Roads.near(gen, x0: px - 1500, z0: pz - 1500, x1: px + 1500, z1: pz + 1500, pad: 0)
        var towns = 0
        let span = 34 * CS
        for rz in (floorDiv(pz - 1500, span))...(floorDiv(pz + 1500, span)) { for rx in (floorDiv(px - 1500, span))...(floorDiv(px + 1500, span)) {
            if Roads.square(gen, rx, rz) != nil { towns += 1 }
        } }
        guard let (seg, _, _) = Roads.nearest(gen, to: V3(Float(px), 100, Float(pz)), range: 1500) else {
            check(false, "roadscheck: no road within 1,500 blocks of his spot (\(towns) towns there, \(segs.count) roads)"); return
        }
        let d = Roads.distance(seg, V2(Float(px), Float(pz))).0
        var drawn = 0, looked = 0, why: [String: Int] = [:]
        let road = StructWriter.roadID
        for k in 0..<24 {
            let p = Roads.point(seg, 0.1 + 0.8 * Float(k) / 23)
            let x = Int(floor(p.x)), z = Int(floor(p.y))
            g.player.pos = V3(p.x, 150, p.y)
            _ = w.loadSync(center: g.player.pos, radius: 1)
            looked += 1
            var y = CH - 2
            while y > 1 && !(Blocks.collide[Int(w.block(x, y, z))] && !CapitalBase.isLeaf(w.block(x, y, z))) { y -= 1 }
            let top = w.block(x, y, z)
            if top == road || top == StructWriter.pathID || Blocks.key(top).contains("sandstone") { drawn += 1 }
            else { why[Blocks.key(top), default: 0] += 1 }
        }
        let whyS = why.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        check(drawn * 4 >= looked * 3,
              String(format: "roadscheck: %d towns and %d roads within 1,500 blocks of his spot; the nearest road %.0f blocks off (%.0f,%.0f to %.0f,%.0f) is drawn at %d of %d points along it",
                     towns, segs.count, d, seg.a.x, seg.a.y, seg.b.x, seg.b.y, drawn, looked) + (whyS.isEmpty ? "" : "; bare: " + whyS))
        // P510 (Nov 1 20:40): a road over water crosses on a stone bridge: the deck over the water, parapets, piers.
        var bridged: (Roads.Seg, Roads.Bridge)?
        for r in [1500, 3000, 5000] where bridged == nil {
            for sg in Roads.near(gen, x0: px - r, z0: pz - r, x1: px + r, z1: pz + r, pad: 0) {
                if let b = sg.bridges.first(where: { $0.ys.count >= 6 }) { bridged = (sg, b); break }
            }
        }
        if let (sg, br) = bridged {
            let mid = br.ys.count / 2
            let p = Roads.point(sg, Float(br.j0 + mid) / Float(br.n))
            let x = Int(floor(p.x)), z = Int(floor(p.y)), y = br.ys[mid]
            g.player.pos = V3(p.x, Float(y + 2), p.y)
            _ = w.loadSync(center: g.player.pos, radius: 1)
            let deckB = Blocks.has("stone_bricks") ? Blocks.id("stone_bricks") : STONE
            var under = y - 1
            while under > 1 && w.block(x, under, z) == AIR { under -= 1 }
            let wet = Blocks.isLiquid(w.block(x, under, z)) || w.block(x, under, z) == deckB
            // A parapet: along the deck's side, 2 out from the line.
            let d = sg.b - sg.a, nrm = V2(-d.y, d.x) / max(1, simd_length(d))
            var walls = 0
            for side in [Float(-1), 1] {
                let q = p + nrm * side * 2.0
                let wb = w.block(Int(floor(q.x)), y + 1, Int(floor(q.y)))
                if Blocks.key(wb).contains("wall") || wb == deckB { walls += 1 }
            }
            check(w.block(x, y, z) == deckB && wet && w.block(x, y + 1, z) == AIR,
                  "roadscheck: a road over water (\(Roads.bridgesPlanned) bridges planned) crosses on a bridge \(br.ys.count) cells long at \(x) \(y - YOFF) \(z): its deck \(Blocks.key(w.block(x, y, z))), under it \(Blocks.key(w.block(x, under, z))) \(y - under) down, clear over it (\(Blocks.key(w.block(x, y + 1, z)))), parapets \(walls) of 2")
        } else {
            check(false, "roadscheck: no road with a bridge within 5,000 blocks of his spot (\(Roads.bridgesPlanned) bridges planned)")
        }
        // His Nov 1 20:40 flight (seed 6387856731608716243, Dry Bend to Belohold): the towns and roads under it.
        do {
            let hw = World(seed: 6387856731608716243, device: g0.world.device, save: nil)
            hw.makeFieldWorld()
            if let hg = hw.gen as? WorldGen {
                for (fx, fz) in [(-1229, 998), (-1575, 795), (-1704, 737), (-2032, 681)] {
                    let near = Roads.near(hg, x0: fx - 400, z0: fz - 400, x1: fx + 400, z1: fz + 400, pad: 0)
                    var tw = 0
                    for rz in floorDiv(fz - 400, span)...floorDiv(fz + 400, span) { for rx in floorDiv(fx - 400, span)...floorDiv(fx + 400, span) where Roads.square(hg, rx, rz) != nil { tw += 1 } }
                    let nr = Roads.nearest(hg, to: V3(Float(fx), 100, Float(fz)), range: 400)
                    print("roadscheck: his 20:40 flight at \(fx) \(fz): \(tw) town squares and \(near.count) roads within 400, the nearest road " + (nr.map { String(format: "%.0f off", Roads.distance($0.0, V2(Float(fx), Float(fz))).0) } ?? "none"))
                }
            }
        }
    }
}
