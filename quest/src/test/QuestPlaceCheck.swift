import Foundation
import simd
import Metal

// P448 (Oct 25 08:52-08:58, New World (4)): blocks placed in a field world. A crafting table, dispenser or observer set
// down a thin 2x2 wall piece; copper wire on the ground was aimed at as a full block, so a line of it couldn't be laid
// in front of him. Checks: which held blocks still set down a wall piece, a stray wall piece from an older build turns
// back into its block, wire is aimed at as a thin strip and the next one goes on in front.
//   questcheck --placecheck
enum QuestPlaceCheck {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        TextureGen.registerAll()
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "ok  " : "FAIL") placecheck: \(what)"); if !ok { fails += 1 } }
        let blocks = ["crafting_table", "dispenser", "dropper", "observer", "furnace", "bookshelf", "note_block", "redstone_lamp",
                      "ship_balloon", "tnt", "jukebox", "smithing_table", "barrel", "redstone_block",
                      "oak_planks", "bricks", "stone_bricks", "cobblestone", "white_wool", "polished_andesite", "iron_block"]
        let walls = Set(["oak_planks", "bricks", "stone_bricks", "cobblestone", "white_wool", "polished_andesite", "iron_block"])
        for k in blocks where Blocks.has(k) {
            let wall = FreeBuild.wallMaterial[Int(Blocks.id(k))]
            check(wall == walls.contains(k), "\(k) \(wall ? "sets down a wall piece" : "places as a block")")
        }
        let all = (0..<Blocks.count).filter { FreeBuild.wallMaterial[$0] }.map { Blocks.key(BlockID($0)) }
        print("placecheck: \(all.count) blocks set down wall pieces: \(all.joined(separator: " "))")

        let w = World(seed: 4797859299361840175, device: sharedSystemDevice, save: nil)
        FieldTerrain.newWorlds = true; w.makeFieldWorld()
        w.renderDistance = 4
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true
        SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.menu = nil
        g.player.pos = V3(-496.5, 72 + Float(YOFF), 6102.5)            // (his 08:53 copper wire spot)
        _ = w.loadSync(center: g.player.pos, radius: 3)
        g.tick(1.0 / 72)
        // P484 (Oct 28 18:02-18:18, "Who makes walls like this?"): nothing sets down a wall piece any more.
        check(g.freePieceKind(Blocks.id("crafting_table")) == nil && g.freePieceKind(Blocks.id("oak_planks")) == nil
              && g.freePieceKind(Blocks.id("cobblestone")) == nil, "in a field world crafting tables, planks and cobblestone place as blocks")

        // A stray dispenser wall (as P338 set them down) by him: a dispenser again within about a second.
        func top(_ x: Int, _ z: Int) -> Int {
            var y = CH - 1
            while y > 1 && !w.groundAt(x, y, z) && w.builtBlock(x, y, z) == AIR { y -= 1 }
            return y
        }
        let sx = -490, sz = 6102, sy = top(sx, sz) + 1
        w.pieces.append(FreePiece(k: FreeBuild.Kind.wall.rawValue, m: "dispenser", p: [Float(sx) + 0.5, Float(sy), Float(sz) + 0.5], yaw: 0))
        w.strayPieces = true
        w.strayTick = 71                                                // (the next settle pass is due: no game tick first,
        g.settleStrayPieces()                                           //  whose support check may take a piece off the slope)
        let became = (sy...sy + 1).map { Blocks.key(Blocks.groupBase[Int(w.builtBlock(sx, $0, sz))]) }
        check(w.pieces.isEmpty && became.contains("dispenser"), "a stray dispenser wall turned back into a dispenser (\(became.joined(separator: ", ")), \(w.pieces.count) pieces left)")
        // P484: a cobblestone wall he set down before turns back into cobblestone too.
        let cx = sx + 3, cy = top(cx, sz) + 1
        w.pieces.append(FreePiece(k: FreeBuild.Kind.wall.rawValue, m: "cobblestone", p: [Float(cx) + 0.5, Float(cy), Float(sz) + 0.5], yaw: 0))
        w.strayPieces = true
        w.strayTick = 71
        g.settleStrayPieces()
        let cob = (cy...cy + 1).map { Blocks.key(Blocks.groupBase[Int(w.builtBlock(cx, $0, sz))]) }
        check(w.pieces.isEmpty && cob.contains("cobblestone"), "a cobblestone wall turned back into cobblestone (\(cob.joined(separator: ", ")), \(w.pieces.count) pieces left)")

        // Wire on a stone strip: aimed at from above, it is met at its thin strip, and the next goes on in front.
        let x = -500, z0 = 6100
        var y = 0
        for dz in -4...1 { y = max(y, top(x, z0 + dz) + 1) }
        w.restoring = true
        for dz in -4...1 { w.setBlock(x, y, z0 + dz, Blocks.id("stone_bricks")); for up in 1...4 { w.setBlock(x, y + up, z0 + dz, AIR) } }
        w.restoring = false
        let wire = Blocks.id("redstone_wire")
        w.setBlock(x, y + 1, z0, wire)
        let p = g.player
        p.pos = V3(Float(x) + 0.5, Float(y + 1), Float(z0) + 0.8)
        p.yaw = 0; p.pitch = -70 * .pi / 180                                // (north, steeply down: at the wire at his feet)
        let box = w.selectionBoxes(wire).first.map { $0.1.y } ?? 1
        check(box <= 0.07, String(format: "wire is aimed at as a strip %.3f high", box))
        let t = w.raycast(p.eye, p.look, maxDist: 6)
        let hit = t.map { "\($0.hit.x) \($0.hit.y) \($0.hit.z) normal \($0.normal.y)" } ?? "nothing"
        check(t?.hit == IVec3(x, y + 1, z0) && t?.normal.y == 1, "looking down at the wire meets its top (\(hit))")
        if let t {
            let at = g.floorAhead(t, for: wire)
            check(at == IVec3(x, y + 1, z0 - 1), "the next wire goes on in front of it (\(at.map { "\($0.x) \($0.y) \($0.z)" } ?? "nowhere"))")
            p.yaw = .pi / 2                                                  // (looking west: the strip's edge, nothing to stand on)
            let side = g.floorAhead(t, for: wire)
            check(side == nil, "looking off the strip's side it isn't laid in the air")
        }
        print(fails == 0 ? "placecheck: all passed" : "placecheck: \(fails) failed")
        return fails == 0 ? 0 : 1
    }
}
