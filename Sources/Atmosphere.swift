import Foundation
import simd

extension Game {
    // Underwater fog: the local biome's water colour, dimmed at night (was one fixed dark blue).
    var underwaterFog: V3 {
        let p = player.eye
        let w = world.gen.column(Int(floor(p.x)), Int(floor(p.z))).biome.info.water
        let c = V3(Float((w >> 16) & 255), Float((w >> 8) & 255), Float(w & 255)) / 255
        let light = dim.dim.hasSky ? 0.12 + 0.88 * daylight : 0.5
        return c * 0.42 * min(1, light)
    }
}
