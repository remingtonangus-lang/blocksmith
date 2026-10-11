import Foundation
import simd

// The look of the overworld sky beyond the dome gradient (L1 look upgrade, docs/status/look-upgrade.md):
// - one wind that drives every cloud layer (the Quest draws a cumulus deck and a high cirrus deck in clouds.frag; the
//   drift accumulates here in Double, and the eye's cloud-space position is sent as Float, fine to ~1e6 blocks);
// - how cloudy the biome's air is and its tint (hazy warm over desert and badlands, cold blue over snow, damp grey-green
//   over swamps), eased in over a few seconds as you travel;
// - distant storm flashes: during a thunderstorm the clouds light up far away between the real strikes, with a far
//   thunder roll a few seconds later (sound travels slower than light).
// Platform-neutral; the Mac's skyColor/skyZenith pick up the biome tint too.
struct SkyState {
    var driftX: Double = 0, driftZ: Double = 0      // cloud-space offset of the world (blocks)
    var windAngle: Float = 0.6                       // radians; veers slowly
    var tint = V3(1, 1, 1)                           // biome air colour multiplier
    var haze: Float = 0                              // 0 clear air ... 1 dusty haze (desert)
    var cover: Float = 0.45                          // fair-weather cloud cover 0...1 (rain pushes it to 1)
    var targetTint = V3(1, 1, 1), targetHaze: Float = 0, targetCover: Float = 0.45
    var biomeTimer: Float = 0
    var flashDir = V3(0, 0.3, 1)                     // where the latest flash lit the clouds (unit, from the eye)
    var flashStrength: Float = 0
    var flashAge: Float = 9
    var distantTimer: Float = 4
    var thunderIn: Float = -1                        // seconds until a scheduled far thunder roll (-1 none)
    var thunderVolume: Float = 0
    var distantFlashes = 0                           // counted for the checks

    var wind: V2 { V2(cosf(windAngle), sinf(windAngle)) }

    // The flash as drawn now: a bright stroke and one or two flickers over ~0.5 s.
    var flash: Float {
        guard flashAge < 0.55 else { return 0 }
        let a = flashAge
        let env = max(0, 1 - a / 0.55)
        return flashStrength * env * (0.55 + 0.45 * cosf(a * 38))
    }

    mutating func flashAt(_ rel: V3, strength: Float) {
        let l = simd_length(rel)
        flashDir = l > 1e-3 ? rel / l : V3(0, 1, 0)
        flashDir.y = max(flashDir.y, 0.12)
        flashDir = simd_normalize(flashDir)
        flashStrength = max(strength, flash)
        flashAge = 0
    }

    func tinted(_ c: V3) -> V3 {
        let lum = (c.x + c.y + c.z) / 3
        let hazeC = V3(0.95, 0.86, 0.7) * (lum * 1.1 + 0.02)
        return simd_mix(c * tint, hazeC, V3(repeating: haze * 0.38))
    }

    // Air per biome: (tint, haze, fair-weather cover).
    static func air(_ b: Biome) -> (V3, Float, Float) {
        switch b {
        case .desert: return (V3(1.04, 1.0, 0.93), 1, 0.2)
        case .badlands, .erodedBadlands, .woodedBadlands: return (V3(1.06, 0.97, 0.9), 0.8, 0.25)
        case .savanna, .savannaPlateau, .windsweptSavanna: return (V3(1.03, 1.0, 0.95), 0.5, 0.32)
        case .swamp, .mangroveSwamp: return (V3(0.93, 0.98, 0.92), 0.3, 0.62)
        case .jungle, .sparseJungle, .bambooJungle: return (V3(0.96, 1.0, 0.97), 0.25, 0.6)
        case .paleGarden, .darkForest: return (V3(0.95, 0.96, 0.98), 0.15, 0.55)
        default:
            if b.info.temp <= 0.05 { return (V3(0.9, 0.97, 1.1), 0, 0.5) }        // snow: cold, clear blue
            if b.info.temp <= 0.3 { return (V3(0.95, 0.99, 1.05), 0, 0.5) }       // taiga, cold hills
            return (V3(1, 1, 1), 0, 0.45)
        }
    }
}

extension Game {
    // Called from weatherTick every tick.
    func skyTick(_ dt: Float) {
        var s = sky
        let speed: Float = 1.4 + 4.5 * weather.thunder + 1.2 * weather.rain       // blocks per second at cumulus height
        s.windAngle += dt * 0.0008 * sinf(Float(clock * 0.0003))               // a slow veer over many minutes
        s.driftX += Double(s.wind.x * speed * dt)
        s.driftZ += Double(s.wind.y * speed * dt)
        s.biomeTimer -= dt
        if s.biomeTimer <= 0 {
            s.biomeTimer = 0.5
            if dim.dim == .overworld {
                let p = player.pos
                let (t, h, c) = SkyState.air(world.gen.column(Int(floor(p.x)), Int(floor(p.z))).biome)
                s.targetTint = t; s.targetHaze = h; s.targetCover = c
            } else {
                s.targetTint = V3(1, 1, 1); s.targetHaze = 0; s.targetCover = 0.45
            }
        }
        let k = 1 - expf(-dt / 4)
        s.tint += (s.targetTint - s.tint) * k
        s.haze += (s.targetHaze - s.haze) * k
        s.cover += (s.targetCover - s.cover) * k
        s.flashAge += dt
        // Distant storm flashes: every 3-12 s in a full storm, somewhere in the clouds toward the horizon.
        if weather.thunder > 0.3 && wetWorld {
            s.distantTimer -= dt
            if s.distantTimer <= 0 {
                s.distantTimer = Rand.float(in: 3...12) / max(0.5, weather.thunder)
                let a = Rand.float(in: 0..<(2 * .pi)), e = Rand.float(in: 0.08...0.35)
                s.flashAt(V3(cosf(a) * cosf(e), sinf(e), sinf(a) * cosf(e)), strength: Rand.float(in: 0.45...0.9))
                s.distantFlashes += 1
                // One roll at a time (a pending roll takes the louder of the two flashes).
                let vol = Rand.float(in: 0.22...0.45)
                if s.thunderIn < 0 { s.thunderIn = Rand.float(in: 2.5...7); s.thunderVolume = vol } else { s.thunderVolume = max(s.thunderVolume, vol) }
            }
        }
        if s.thunderIn >= 0 {
            s.thunderIn -= dt
            if s.thunderIn < 0 { sfx(.thunderFar, s.thunderVolume) }
        }
        sky = s
    }

    // Cloud cover as drawn: the biome's fair-weather cover, pushed to overcast by rain and thunder.
    var cloudCover: Float { min(1, sky.cover + (1 - sky.cover) * min(1, weather.rain * 0.85 + weather.thunder * 0.3)) }
}
