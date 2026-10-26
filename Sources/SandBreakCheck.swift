import Foundation
import simd

// P462 (Remington, Oct 25 16:58, digging a beach: "when I break a sand block, it's like an existing block form of it spawns
// and drops, which is wrong"): questcheck --sandbreak digs out a sand cell under the drawn sand ground and
// runs the gravity check: the ground's sand stays put (no falling block), while a sand block he placed over air still falls.
enum SandBreakCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        // His world and spot: seed 5381095465666589309, the beach at 4649 1730 (the sand he broke at 4647 62 1728).
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 5381095465666589309, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 3; w.activeDistance = 3
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = true
        let spot = V3(4649.5, 140, 1730.5)
        g.player.pos = spot
        _ = w.loadSync(center: spot, radius: 3)
        let sand = Blocks.id("sand")
        var found: IVec3?
        for r in 0...14 where found == nil {
            for cz in (1730 - r)...(1730 + r) { for cx in (4649 - r)...(4649 + r) where found == nil && max(abs(cx - 4649), abs(cz - 1730)) == r {
                var t = CH - 2
                while t > 1 && !w.groundAt(cx, t, cz) { t -= 1 }
                if w.groundAt(cx, t - 1, cz) && w.materialAt(cx, t, cz) == sand && w.materialAt(cx, t - 1, cz) == sand { found = IVec3(cx, t - 1, cz) }
            } }
        }
        guard let c = found else { check(false, "sandbreak: sand ground on his beach at 4649 1730"); return }
        g.player.pos = V3(Float(c.x) + 3.5, Float(c.y) + 2, Float(c.z) + 0.5)
        let falling0 = g.falling.count
        w.gravityQueue.removeAll()
        g.breakBlock(c, sand, drop: false, quiet: true)
        w.gravityQueue.append(c + IVec3(0, 1, 0))
        let over = w.materialAt(c.x, c.y + 1, c.z) == sand && w.groundAt(c.x, c.y + 1, c.z) && w.isAir(c.x, c.y, c.z)   // (what used to fall)
        for _ in 0..<5 { g.gravityTick() }
        let groundFell = g.falling.count - falling0
        // A sand block he placed, three over the dug cell with air under it, falls as before.
        let up = c + IVec3(0, 4, 0)
        let clear = w.isAir(up.x, up.y, up.z) && w.isAir(up.x, up.y - 1, up.z)
        w.setBlock(up.x, up.y, up.z, sand)
        w.gravityQueue.append(up)
        for _ in 0..<5 { g.gravityTick() }
        let builtFell = g.falling.count - falling0 - groundFell
        check(over && groundFell == 0 && (!clear || builtFell == 1),
              "sandbreak: dug out from under the beach's sand ground at \(c.x) \(c.y - 64) \(c.z) (sand ground over the hole: \(over ? "yes" : "no")), the sand over it stays ground (\(groundFell) falling blocks); "
              + "a placed sand block over air falls (\(clear ? "\(builtFell)" : "no air to test"))")
    }
}
