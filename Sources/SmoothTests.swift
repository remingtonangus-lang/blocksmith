import Foundation
import simd

// --smoothtest: the smooth terrain prototype (SmoothTerrain.swift, docs/proposals/smooth-terrain.md).
//   ./snap.sh x --seed 12345 --smoothtest      (any snapshot flags; the test builds its own pad above the terrain)
// Walking: a one-block natural step is walked up without a jump with smooth on, not with it off, and never for a
// built (cubic) block. Meshing: a lone natural block still has a surface, vertices stay inside the unsigned 1/16
// position range, smooth meshes have no natural cube faces left, and turning the mode off restores the cube mesh.
enum SmoothTests {
    static func run(_ g: Game) -> Int {
        let w = g.world
        var fail = 0
        func check(_ ok: Bool, _ name: String, _ detail: String) {
            print("smoothtest \(ok ? "PASS" : "FAIL") \(name): \(detail)")
            if !ok { fail += 1 }
        }
        let was = SmoothTerrain.enabled
        let stone = Blocks.id("stone"), cobble = Blocks.id("cobblestone")
        let p0 = g.player.pos
        let cx = Int(floor(p0.x)), cz = Int(floor(p0.z))
        var top = 0
        for dx in stride(from: -8, through: 8, by: 2) { for dz in stride(from: -8, through: 8, by: 2) { top = max(top, w.topY(cx + dx, cz + dz)) } }
        let y0 = min(CH - 20, top + 6)
        // Pad: a 9x5 stone floor at y0, a one-block wall 4 ahead (+x), 3 wide.
        func pad(_ wall: BlockID) {
            for x in -2...8 { for z in -3...3 { for y in y0...(y0 + 4) { w.setBlock(cx + x, y, cz + z, AIR) } } }
            for x in -2...8 { for z in -3...3 { w.setBlock(cx + x, y0, cz + z, stone) } }
            for z in -1...1 { w.setBlock(cx + 4, y0 + 1, cz + z, wall) }
        }
        func walk() -> Float {
            var pos = V3(Float(cx) + 0.5, Float(y0 + 1), Float(cz) + 0.5)
            var onGround = true, top: Float = 0
            for _ in 0..<60 {
                let hit = w.moveBody(&pos, halfW: 0.3, height: 1.8, V3(0.12, -0.1, 0), step: 0.6, onGround: onGround)
                onGround = hit.y
                top = max(top, pos.y - Float(y0 + 1))
            }
            return top          // highest point (the wall is one block thick: the walker steps down behind it)
        }
        SmoothTerrain.enabled = true
        pad(stone)
        let upSmooth = walk()
        check(upSmooth > 0.95, "walk up natural step (smooth)", "rose \(upSmooth) blocks")
        SmoothTerrain.enabled = false
        let upCubic = walk()
        check(upCubic < 0.1, "natural step blocks (cubic)", "rose \(upCubic) blocks")
        SmoothTerrain.enabled = true
        pad(cobble)
        let upBuilt = walk()
        check(upBuilt < 0.1, "built step blocks (smooth)", "rose \(upBuilt) blocks")

        // Meshing: one stone block alone in the air, at a section corner (vertices reach into the neighbours).
        for x in -2...8 { for z in -3...3 { for y in y0...(y0 + 4) { w.setBlock(cx + x, y, cz + z, AIR) } } }
        let by = min(CH - 1, ((y0 + 16) & ~15) + 15)      // a section above the terrain and the pad
        let bx = (cx & ~15) + 15, bz = (cz & ~15) + 15
        w.setBlock(bx, by, bz, stone)
        guard let c = w.chunkAt(bx, bz), let nb = w.neighbourhood(c) else { check(false, "mesh setup", "chunk not loaded"); return fail }
        let sy = by >> 4
        let m = Mesher.buildSection(nb.0, nb.1, sy: sy)
        var maxP: UInt32 = 0, cubeLike = 0
        for i in stride(from: 0, to: m.opaque.count, by: 2) {
            let w0 = m.opaque[i]
            maxP = max(maxP, w0 & 511, (w0 >> 9) & 511, (w0 >> 18) & 511)
            if (w0 & 511) % 16 == 0 && ((w0 >> 9) & 511) % 16 == 0 && ((w0 >> 18) & 511) % 16 == 0 { cubeLike += 1 }
        }
        check(m.opaque.count / 8 == 6, "lone block has a surface", "\(m.opaque.count / 8) quads (6 expected)")
        check(maxP <= 17 * 16 + 8, "vertices in range", "max \(maxP)/16 (limit 280)")
        check(cubeLike == 0, "no cube corners left", "\(cubeLike) vertices on block corners")
        // The neighbours own the quads past the +x/+y/+z faces.
        var neighbourQuads = 0
        if let cn = w.chunkAt(bx + 1, bz), let nn = w.neighbourhood(cn) {
            neighbourQuads = Mesher.buildSection(nn.0, nn.1, sy: sy).opaque.count / 8
        }
        check(neighbourQuads == 0, "no quads owned twice", "+x chunk section holds \(neighbourQuads) quads (owner is the block's chunk)")
        SmoothTerrain.enabled = false
        let mc = Mesher.buildSection(nb.0, nb.1, sy: sy)
        check(mc.opaque.count / 8 == 6, "cubic mode back to a cube", "\(mc.opaque.count / 8) quads")
        w.setBlock(bx, by, bz, AIR)
        SmoothTerrain.enabled = was
        print("smoothtest: \(fail == 0 ? "PASS" : "FAIL (\(fail))")")
        return fail
    }
}
