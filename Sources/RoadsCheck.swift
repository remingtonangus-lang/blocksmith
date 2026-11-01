import Foundation
import simd

// P507 (Nov 1 12:40:22, flying over plains at -5574 4571 in his field world: "what ever happened to roads? Like, wasn't
// that a thing we were supposed to have?"): questcheck --roadscheck makes his world (his seed, a field world as the
// headset makes them), lists the roads within 1,500 blocks of his spot, loads the nearest one at 24 points along it and
// counts the points where the road is drawn on the ground (the packed earth a field world's road is laid in).
enum RoadsCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
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
    }
}
