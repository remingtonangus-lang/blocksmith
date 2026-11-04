import Foundation
import simd

// Nov 4 (frame rate): questcheck --surfacecheck: on a made-ground world, the field's surface under 4,096 standing spots
// (World.fieldSurfaceOffset, what a mob near him stands on where no drawn ground is found) as it is and as it was before
// (BS_SURFOLD): the same heights, and what each took.
enum SurfaceCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 9177, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 3; w.activeDistance = 3
        let at = V3(24, 200, 24)
        w.activeCenter = at
        _ = w.loadSync(center: at, radius: 3)
        var spots: [V3] = []
        var rng = SRng(77)
        for _ in 0..<4096 {
            let x = Float(rng.int(48)) + rng.float(), z = Float(rng.int(48)) + rng.float()
            var y = CH - 2
            while y > 1 && !w.groundAt(Int(floor(x)), y, Int(floor(z))) { y -= 1 }
            spots.append(V3(x, Float(y + 1) + (rng.float() - 0.5) * 1.2, z))
        }
        var same = 0, worst: Float = 0, found = 0
        var tNew = 0.0, tOld = 0.0
        for p in spots {
            let a0 = CFAbsoluteTimeGetCurrent()
            let a = w.fieldSurfaceOffset(p)
            let a1 = CFAbsoluteTimeGetCurrent()
            let b = w.fieldSurfaceOffsetOld(p)
            let b1 = CFAbsoluteTimeGetCurrent()
            tNew += a1 - a0; tOld += b1 - a1
            if a == b { same += 1 }
            worst = max(worst, abs(a - b))
            if b != 0 { found += 1 }
        }
        check(same == spots.count && found > 1000,
              String(format: "surface: the field's surface under %d standing spots (%d on a slope or step) the same as before at %d, largest difference %.6f; %.2f ms in all (before %.2f ms)",
                     spots.count, found, same, worst, tNew * 1000, tOld * 1000))
    }
}
