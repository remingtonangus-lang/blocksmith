import Foundation
import simd

// Ledgers 130 and 131 (`questcheck --placerow`), in a field world of seed 4242 on a made flat of earth:
//   (1) a block built out from a wall's top, a block and a half over the ground, leaves the ground as it is (it rose
//       to meet it before: BS_OLDMEET=1);
//   (2) a block set down on the ground with a gap under it still has the ground rise to its floor;
//   (3) aimed at the ground beside a built block, a block joins that block's row whether the surface at the aim
//       stands low or high in its cell;
//   (4) aimed into a hole that still holds a little ground, the block takes the hole's cell;
//   (5) with nothing built beside it, the row whose floor is nearest the surface.
enum PlaceRowTests {
    static func run(_ g0: Game, check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 4242, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 3; w.activeDistance = 3
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        let at = V3(8, 200, 8)
        g.player.pos = at
        _ = w.loadSync(center: at, radius: 3)
        let dirt = FieldMat.index[Int(DIRT)]
        func set(_ x: Int, _ y: Int, _ z: Int, _ mat: UInt8?) {
            guard let c = w.chunkAt(x, z) else { return }
            c.blocks.setDensity(Chunk.index(mod(x, CS), y, mod(z, CS)), mat != nil ? 32 : -32, material: mat)
        }
        var top = CH - 2
        while top > 1 && !w.groundAt(0, top, 0) { top -= 1 }
        let H = top + 6                                  // the flat's top ground cell
        for z in -12...12 { for x in -12...12 {
            for y in (top - 6)...H { set(x, y, z, dirt) }
            for y in (H + 1)...(H + 10) { set(x, y, z, nil); if w.builtBlock(x, y, z) != AIR { w.setBlock(x, y, z, AIR) } }
        } }
        g.player.pos = V3(20, Float(H) + 6, 20)          // (well off the cells below)
        let planks = Blocks.id("oak_planks")
        func ground(_ x: Int, _ z: Int) -> Float {
            w.fieldRaySegment(V3(Float(x) + 0.5, Float(H) + 8, Float(z) + 0.5), V3(0, -1, 0), from: 0, to: 16).map { $0.at.y } ?? -1
        }
        // (1) a wall two high at (0, 0); a block built out from its top over (1, 0)
        w.setBlock(0, H + 1, 0, planks); w.setBlock(0, H + 2, 0, planks)
        let before = ground(1, 0)
        w.setBlock(1, H + 2, 0, planks)
        let rose = w.meetGround(1, H + 2, 0, planks)
        let after = ground(1, 0)
        check(World.oldMeet ? true : (rose == 0 && abs(after - before) < 0.01),
              String(format: "placerow (1): a block built out from a wall's top over the ground leaves the ground as it is (%d cells turned to ground; the ground under it %.2f before, %.2f after; its floor at %d)", rose, before - Float(YOFF), after - Float(YOFF), H + 2 - YOFF))
        // (2) a block set down on the ground at (4, 4), in the cell over the top ground cell: its floor is met
        for z in 3...5 { for x in 3...5 {                 // (the flat's top cell thin here: the surface 0.3 under the row)
            if let c = w.chunkAt(x, z) { c.blocks.setDensity(Chunk.index(mod(x, CS), H, mod(z, CS)), 8, material: dirt) }
        } }
        let g0y = ground(4, 4)
        w.setBlock(4, H + 1, 4, planks)
        w.meetGround(4, H + 1, 4, planks)
        let gap = w.floorGap(4, H + 1, 4)
        check(Float(H + 1) - g0y > 0.15 && gap < 0.08, String(format: "placerow (2): a block set down on the ground still has the ground rise to its floor (the ground stood %.2f under the floor, now %.2f)", Float(H + 1) - g0y, gap))
        // (3) beside the wall's foot (0, H + 1, 0), aimed at the ground of (-1, 0): the surface low in the cell over the
        // flat, or high in the flat's top cell, the block joins row H + 1
        func aim(_ x: Int, _ z: Int, _ y: Float) -> (cell: IVec3, sunk: Bool)? {
            let cell = IVec3(x, Int(floor(y)), z)
            g.targetGround = (cell, V3(Float(x) + 0.5, y, Float(z) + 0.5), V3(0, 1, 0))
            return g.groundRowCell((hit: cell, normal: IVec3(0, 1, 0)), for: planks)
        }
        let lowAim = aim(-1, 0, Float(H) + 0.3), highAim = aim(-1, 0, Float(H) + 0.8), overAim = aim(-1, 0, Float(H + 1) + 0.2)
        check(Game.oldPlaceRow ? true : (lowAim?.cell.y == H + 1 && highAim?.cell.y == H + 1 && overAim?.cell.y == H + 1),
              "placerow (3): beside a built block a block joins its row (row \(H + 1 - YOFF)): the surface low in the cell under it -> \(lowAim.map { String($0.cell.y - YOFF) } ?? "nil"), high in it -> \(highAim.map { String($0.cell.y - YOFF) } ?? "nil"), low in the row's own cell -> \(overAim.map { String($0.cell.y - YOFF) } ?? "nil")")
        // (4) a hole: the top cell of (8, 8) dug down to a fifth of a block of ground; the block takes that cell
        let hole = aim(8, 8, Float(H) + 0.2)
        check(Game.oldPlaceRow ? true : (hole?.cell.y == H), "placerow (4): aimed into a hole that still holds a little ground the block takes the hole's cell (row \(H - YOFF)): \(hole.map { "row \($0.cell.y - YOFF)\($0.sunk ? ", its ground cleared first" : "")" } ?? "nil")")
        // (5) nothing built beside: the nearest row
        let n0 = aim(-8, -8, Float(H) + 0.3), n1 = aim(-8, -8, Float(H) + 0.7)
        check(Game.oldPlaceRow ? true : (n0?.cell.y == H && n1?.cell.y == H + 1), "placerow (5): on open ground the row whose floor is nearest the surface: surface 0.3 up its cell -> row \(n0.map { String($0.cell.y - YOFF) } ?? "nil") (the cell itself, \(H - YOFF)), 0.7 up -> row \(n1.map { String($0.cell.y - YOFF) } ?? "nil") (the one over it)")
        g.targetGround = nil
    }
}
