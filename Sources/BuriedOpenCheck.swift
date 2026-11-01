import Foundation
import simd

// questcheck --cratermesh (and the full suite): store media, Oct 31 (a Tidebreaker strike on village ground 60 blocks
// from the camera: the sky through the crater's floor for as long as it was watched). In a Polygons world the rock
// under a far chunk's lowest surface is left unmeshed (P440, World.deferBuried); a crater 5 chunks off is dug through
// setBlockAsync and its bowl through fieldSphere, and the sections it lays open must mesh.
enum BuriedOpenCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 4242, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 7; w.activeDistance = 7
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        func top(_ x: Int, _ z: Int) -> Int { var y = CH - 2; while y > 1 && !w.groundAt(x, y, z) { y -= 1 }; return y }
        _ = w.loadSync(center: V3(8, 200, 8), radius: 7)
        g.player.pos = V3(8.5, Float(top(8, 8) + 1), 8.5); g.player.flying = false
        for _ in 0..<120 { g.tick(1.0 / 72) }
        let cx = 5 * CS + 8, cz = 8
        let ty = top(cx, cz)
        let floorY = ty - 20
        guard let c = w.chunkAt(cx, cz) else { check(false, "cratermesh: no chunk at the crater"); return }
        let sec = c.sections[floorY >> 4]
        let before = sec.deferred
        let job = CraterJob(at: V3(Float(cx) + 0.5, Float(ty) + 0.5, Float(cz) + 0.5), radius: MainGun.craterRadius, cap: MainGun.craterCap,
                            game: g, quiet: true, depth: MainGun.craterDepth, along: V3(0, -1, 0.3))
        var steps = 0
        while !job.done && steps < 400 { job.step(g, blocks: CraterJob.blocksPerFrame); g.tick(1.0 / 72); steps += 1 }
        for _ in 0..<600 { g.tick(1.0 / 72) }
        let open = !w.groundAt(cx, floorY + 2, cz)
        let below = (0..<12).first { w.groundAt(cx, floorY - $0, cz) }.map { floorY - $0 } ?? -1
        let floorSec = below >= 0 ? c.sections[below >> 4] : sec
        check(open && !floorSec.deferred && !sec.deferred,
              "cratermesh: a crater 5 chunks off (its rock unmeshed before: \(before)) lays open y \(floorY - YOFF) (\(open)) over a floor at \(below - YOFF); its sections meshed: \(!sec.deferred), \(!floorSec.deferred)")
    }
}
