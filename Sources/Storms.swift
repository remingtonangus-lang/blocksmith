import Foundation
import simd

// D49: blizzards and sandstorms that cut visibility, body temperature, lightning risk to riders.
// Objectives:
//  - The rain weather becomes a blizzard where it would snow (strongest in a thunderstorm) and a sandstorm over the dry
//    biomes (desert, badlands, savanna), which have no rain today. Out in it, the fog closes in to 20-40 blocks
//    (white in a blizzard, ochre in a sandstorm) and the wind drives snow or sand past the player.
//  - Body temperature (0 freezing, 0.5 comfortable, 1 heatstroke) drifts with the weather where the player stands:
//    a blizzard or snow country at night chills, a sandstorm or the desert at midday heats. Shelter (a roof), a fire,
//    lava or a lit furnace close by, and water (for heat) bring it back; leather or fur armour slows the chill. At the
//    extremes the player slows down and takes a little damage, with a warning before it starts.
//  - Riders out in the open in a thunderstorm draw lightning: now and then a strike lands near a mounted player.
enum Storms {
    static var kind = 0                  // at the player: 0 none, 1 blizzard, 2 sandstorm
    static var strength: Float = 0       // 0...1 (fades in and out)
    static var bodyTemp: Float = 0.5
    static var warned = 0                // -1 cold warned, 1 heat warned
    static var hurtT: Float = 0
    static var riderStrikes = 0          // (checks)
    static let dryBiomes: Set<Biome> = [.desert, .badlands, .erodedBadlands, .woodedBadlands, .savanna, .savannaPlateau, .windsweptSavanna]

    static func sight() -> Float? {
        guard kind != 0, strength > 0.05 else { return nil }
        let clear: Float = 260
        let worst: Float = kind == 1 ? 22 : 30
        return clear + (worst - clear) * strength
    }
    static func tint() -> V3? {
        guard kind != 0, strength > 0.05 else { return nil }
        return kind == 1 ? V3(0.86, 0.9, 0.95) : V3(0.78, 0.62, 0.4)
    }
}

extension Game {
    var stormFogTint: V3? { Storms.tint() }

    func stormTick(_ dt: Float) {
        guard dim.dim == .overworld, alive else { Storms.strength = max(0, Storms.strength - dt * 0.3); return }
        let p = player.pos
        let ix = Int(floor(p.x)), iy = Int(floor(p.y + 1)), iz = Int(floor(p.z))
        let biome = world.gen.column(ix, iz).biome
        let pr = precipitation(ix, iy, iz)
        var want = 0
        if weather.rain > 0.3 {
            if pr == 2 { want = 1 } else if Storms.dryBiomes.contains(biome) { want = 2 }
        }
        let level: Float = want == 0 ? 0 : min(1, (weather.rain - 0.3) / 0.5) * (0.55 + 0.45 * weather.thunder)
        if want != 0 { Storms.kind = want }
        Storms.strength += (level - Storms.strength) * min(1, dt * 0.25)
        if Storms.strength < 0.02 && want == 0 { Storms.kind = 0 }
        let outside = skyExposed(ix, iy, iz)
        // Wind-driven snow or sand round the player.
        if Storms.kind != 0 && Storms.strength > 0.15 && outside {
            let n = Int(Storms.strength * 10)
            let wind = V3(cosf(Float(time) * 0.01), 0, sinf(Float(time) * 0.01)) * (6 + 6 * Storms.strength)
            let col = Storms.kind == 1 ? V3(0.95, 0.97, 1) : V3(0.8, 0.66, 0.44)
            for _ in 0..<n {
                let q = p + V3(Rand.float(in: -9...9), Rand.float(in: 0...4), Rand.float(in: -9...9)) - wind * 0.4
                particles.add(Particle(pos: q, vel: wind + V3(0, Storms.kind == 1 ? -1.5 : 0.2, 0), life: 1.2, maxLife: 1.2,
                                       layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: Storms.kind == 1 ? 0.06 : 0.05,
                                       gravity: 0, color: col, collide: false))
            }
        }
        bodyTemperatureTick(dt, biome: biome, outside: outside, ix: ix, iy: iy, iz: iz)
    }

    private func bodyTemperatureTick(_ dt: Float, biome: Biome, outside: Bool, ix: Int, iy: Int, iz: Int) {
        guard survival else { Storms.bodyTemp = 0.5; return }
        // Where the weather pulls the body: below 0.5 cold, above hot.
        var pull: Float = 0.5
        let noon = daylight
        if Storms.kind == 1 && outside { pull = 0.5 - 0.6 * Storms.strength }
        else if precipitation(ix, iy, iz) == 2 && outside && noon < 0.3 { pull = 0.32 }
        if Storms.kind == 2 && outside { pull = 0.5 + 0.55 * Storms.strength }
        else if biome == .desert && outside && noon > 0.85 { pull = max(pull, 0.72) }
        // A fire nearby warms (block light from fire, lava, a lit furnace or campfire); water cools.
        let bl = world.lightAt(ix, iy, iz).block
        if bl >= 11 && pull < 0.5 { pull = 0.5 + 0.1 * Float(bl - 11) }
        if player.inWater && pull > 0.5 { pull = 0.42 }
        if !outside { pull = 0.5 + (pull - 0.5) * 0.25 }
        // Leather or fur armour: the cold comes on slower.
        var rate: Float = 0.012
        if pull < 0.5 {
            let warm = inventory.armor.slots.filter { !$0.isEmpty && Items.key($0.item).hasPrefix("leather_") }.count
            rate *= 1 - 0.18 * Float(warm)
        }
        Storms.bodyTemp += (pull - Storms.bodyTemp) * min(1, dt * rate * 4)
        let t = Storms.bodyTemp
        if t < 0.22 && Storms.warned != -1 { Storms.warned = -1; onToast?("You're getting dangerously cold") }
        if t > 0.8 && Storms.warned != 1 { Storms.warned = 1; onToast?("The heat is getting to you") }
        if t > 0.3 && t < 0.7 { Storms.warned = 0 }
        Storms.hurtT -= dt
        if t < 0.12 {
            applyEffect(.slowness, amp: 0, seconds: 3)
            if Storms.hurtT <= 0 { Storms.hurtT = 4; hurtPlayer(1, from: player.pos, cause: "froze to death", knockback: 0, type: .magic) }
        } else if t > 0.9 {
            exhaustion += dt * 0.4
            if Storms.hurtT <= 0 { Storms.hurtT = 6; hurtPlayer(1, from: player.pos, cause: "died of heatstroke", knockback: 0, type: .magic) }
        }
    }

    // During a thunderstorm's lightning roll: a mounted player out in the open draws a strike now and then.
    func riderLightning() -> V3? {
        guard riding != nil, weather.thunder > 0.5, Rand.float(in: 0..<1) < 0.18 else { return nil }
        let p = player.pos
        let ix = Int(floor(p.x)), iy = Int(floor(p.y + 2)), iz = Int(floor(p.z))
        guard skyExposed(ix, iy, iz), precipitation(ix, iy, iz) == 1 else { return nil }
        let a = Rand.float(in: 0..<(2 * .pi)), d = Rand.float(in: 1.5...7)
        let x = p.x + cosf(a) * d, z = p.z + sinf(a) * d
        Storms.riderStrikes += 1
        return V3(x, Float(world.topY(Int(floor(x)), Int(floor(z))) + 1), z)
    }
}
