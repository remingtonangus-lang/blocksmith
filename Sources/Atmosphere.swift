import Foundation
import simd

extension Game {
    // Underwater fog: the local biome's water colour, dimmed at night (was one fixed dark blue).
    static let lavaFog = V3(0.75, 0.22, 0.02)         // view colour with the eye inside lava
    static let fuelFog = V3(0.26, 0.16, 0.03)         // P478: with the eye inside fuel
    var underwaterFog: V3 {
        let p = player.eye
        let w = world.gen.column(Int(floor(p.x)), Int(floor(p.z))).biome.info.water
        let c = V3(Float((w >> 16) & 255), Float((w >> 8) & 255), Float(w & 255)) / 255
        let light = dim.dim.hasSky ? 0.12 + 0.88 * daylight : 0.5
        if player.headInFuel { return Game.fuelFog * (0.4 + 0.6 * min(1, light)) }      // P478: inside fuel, dark amber
        return c * 0.42 * min(1, light)
    }
}
