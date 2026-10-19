import Foundation
import simd

// H9 Storms at sea.
// - The sea gets rough with the weather (Weather.sea: rain ~0.4, a thunderstorm 1): boats pitch and roll on it, tilted
//   with the slope of the drawn swell where it is drawn (the Quest) and by a rolling motion of their own that grows from
//   a gentle rock in calm water to a heavy one in a storm (everywhere: the Mac's water is flat).
// - The storm wind (ShipManager.wind, stronger in rain and thunder) pushes boats and floating hulls downwind, so holding
//   a course in a gale takes paddling or throttle.
// - Assembled ships ride the storm swell through their buoyancy buckets (the wave height is added to the water surface
//   under each bucket), so they heave, pitch and roll with it.
// - Spray: wave crests blow white spray about a player at sea in rough weather, a boat cutting through the waves throws
//   it over its bow, and a thunderstorm's rain falls heavier (Game.writeWeather).
enum SeaStorms {
    static var sea: Float = 0              // the current world's sea state, 0...1
    static var swellScale: Float = 0       // multiplier on OceanSwell.height under ship buckets (0: flat water)
    static var t: Float = 0                // swell clock: Game.time mod 1000, as the water shader and boats use
    private static var crestAcc: Float = 0
    static let sprayColor = V3(0.86, 0.92, 0.97)

    // Once a frame (ShipManager.update): sea state and swell clock, crest spray round the player.
    static func tick(_ g: Game, _ dt: Float) {
        let wet = g.wetWorld
        sea = wet ? g.weather.sea : 0
        // Ships ride the swell where it is drawn; on flat (Mac) water only the storm's part of it, so calm seas stay still.
        swellScale = !wet ? 0 : (Game.oceanSwellDrawn ? g.weather.swell : 3 * sea)
        t = Float(g.time.truncatingRemainder(dividingBy: 1000))
        crestSpray(g, dt)
    }

    // A thunderstorm's extra rain (0...1): denser, brighter streaks.
    static func rainBoost(_ g: Game) -> Float { min(1, max(0, g.weather.thunder)) }

    // Extra water height for a ship's buoyancy bucket at world point p over water whose flat top is `top`: open sea
    // (water at sea level) only.
    @inline(__always) static func waveLift(_ p: V3, top: Float) -> Float {
        guard swellScale > 0 else { return 0 }
        let off: Float = top - Float(SEA) - 0.875
        guard abs(off) < 1.6 else { return 0 }
        return OceanSwell.height(p.x, p.z, t) * swellScale
    }

    // A gale on a floating hull (tonne-blocks/s^2): the wind relative to the hull against its mean side area.
    // Airships have their own drift (lift balloons); a hull in the air or on land takes none.
    static func windForce(_ s: Ship, wind: V3, submerged: Float) -> V3 {
        guard sea > 0.05, submerged > 0, s.balloons == 0 else { return .zero }
        let rel = V3(wind.x - s.vel.x, 0, wind.z - s.vel.z)
        let speed: Float = simd_length(rel)
        let area: Float = (s.area.x + s.area.z) * 0.5
        let k: Float = 0.004 * sea * speed * area
        return rel * k
    }

    // White spray blown off wave crests within 14 blocks of a player near the open sea (rough weather only).
    private static func crestSpray(_ g: Game, _ dt: Float) {
        guard sea > 0.35 else { crestAcc = 0; return }
        let pp = g.player.pos
        guard abs(pp.y - Float(SEA)) < 14 else { return }
        crestAcc += sea * sea * 14 * dt
        var tries = 0
        while crestAcc >= 1 && tries < 6 {
            crestAcc -= 1; tries += 1
            let a = Rand.float(in: 0..<(2 * .pi)), d = Rand.float(in: 3...14)
            let x = Int(floor(pp.x + cosf(a) * d)), z = Int(floor(pp.z + sinf(a) * d))
            guard g.world.block(x, SEA, z) == WATER, g.world.isAir(x, SEA + 1, z) else { continue }
            let fx = Float(x) + Rand.float(in: 0..<1), fz = Float(z) + Rand.float(in: 0..<1)
            let lift: Float = Game.oceanSwellDrawn ? OceanSwell.height(fx, fz, t) * g.weather.swell : 0
            spray(g, at: V3(fx, Float(SEA) + 0.9 + lift, fz), push: V3(0, 0, 0), count: 4)
        }
        if crestAcc > 4 { crestAcc = 4 }
    }

    // A burst of spray at `at`, carried by the wind plus `push`.
    static func spray(_ g: Game, at: V3, push: V3, count: Int) {
        let w = g.world.ships.wind
        let layer = Int(Tex.id("smoke"))
        for _ in 0..<count {
            let up: Float = Rand.float(in: 1.5...3.5) * (0.6 + sea)
            let v = V3(w.x * 0.3 + push.x + Rand.float(in: -1...1), up, w.z * 0.3 + push.z + Rand.float(in: -1...1))
            let o = V3(Rand.float(in: -0.3...0.3), 0, Rand.float(in: -0.3...0.3))
            g.particles.add(Particle(pos: at + o, vel: v, life: 0.7, maxLife: 0.7, layer: layer, uv0: V2(0, 0), uvSize: 1,
                                     size: Rand.float(in: 0.05...0.11), gravity: 9, color: sprayColor, collide: false))
        }
    }
}

extension Mob {
    // A boat on the water each frame (Mob.updateBoat): its drawn rock on the waves, the storm's drift and bow spray.
    func boatSea(_ dt: Float, _ g: Game, onWater: Bool, ocean: Bool, sea: Float) {
        var want = V2.zero
        if onWater {
            let fx: Float = -sinf(yaw), fz: Float = -cosf(yaw)          // bow (model -Z)
            let rx: Float = cosf(yaw), rz: Float = -sinf(yaw)           // right side (model +X)
            if ocean && Game.oceanSwellDrawn {
                // Tilted with the drawn swell's slope under the hull: bow against stern, right side against left.
                let t = Float(g.time.truncatingRemainder(dividingBy: 1000))
                let k: Float = g.weather.swell
                let hb: Float = OceanSwell.height(pos.x + fx * 0.9, pos.z + fz * 0.9, t)
                let hs: Float = OceanSwell.height(pos.x - fx * 0.9, pos.z - fz * 0.9, t)
                let hr: Float = OceanSwell.height(pos.x + rx * 0.6, pos.z + rz * 0.6, t)
                let hl: Float = OceanSwell.height(pos.x - rx * 0.6, pos.z - rz * 0.6, t)
                want.x = atanf((hb - hs) * k / 1.8)
                want.y = atanf((hr - hl) * k / 1.2)
            }
            // A rock of its own: gentle in calm water, heavy in a storm.
            let c = Float(g.clock.truncatingRemainder(dividingBy: 10000))
            let amp: Float = 0.02 + 0.2 * sea
            let p1: Float = sinf(c * 0.9 + pos.x * 0.21) + 0.5 * sinf(c * 1.7 + pos.z * 0.33)
            let r1: Float = sinf(c * 0.7 + pos.z * 0.19 + 1.3) + 0.4 * sinf(c * 2.1 + pos.x * 0.27)
            want.x += amp * 0.6 * p1
            want.y += amp * r1
            if sea > 0.05 {
                // The gale drifts it downwind (about 1.7 b/s in a full storm against the water's drag).
                let w = g.world.ships.wind
                vel.x += w.x * 0.25 * sea * dt
                vel.z += w.z * 0.25 * sea * dt
                // Spray over the bow as it slams into the waves, more the faster it goes.
                let speed: Float = simd_length(V2(vel.x, vel.z))
                let rate: Float = sea * sea * (2 + speed * 1.5)
                if sea > 0.25 && Rand.float(in: 0..<1) < rate * dt {
                    let bow = pos + V3(fx * 1.1, 0.4, fz * 1.1)
                    SeaStorms.spray(g, at: bow, push: V3(fx, 0, fz) * (speed * 0.3), count: 3)
                }
            }
        }
        boatRock += (want - boatRock) * min(1, dt * 5)
        boatRock = simd_clamp(boatRock, V2(repeating: -0.45), V2(repeating: 0.45))
    }
}
