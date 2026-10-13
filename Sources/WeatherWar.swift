import Foundation
import simd

// Weather that matters (backlog O7).
//   storms  a thunderstorm grounds flyers: frigates and other flying capitals break off and hold over home, and no
//           dropship launches (hunters and raids wait for it to pass); a toast says so when it starts and ends
//   fog     banks of fog roll in now and then (most often at dawn) for 4-10 minutes: the view closes in to about 30
//           blocks and soldiers spot you at 40% of their usual range; rain cuts it to 85%, a storm to 70%
//   snow    falling snow near you, or snow underfoot, slows soldiers to 70% of their pace
// The fog is in memory (a reload starts clear).
enum WeatherWar {
    static var fog: Float = 0                // 0 clear .. 1 thick
    static var fogOn = false
    static var fogTimer: Double = 1200
    static var sight: Float = 1              // soldiers' spotting range scale (per second)
    static var snowNear = false
    static var stormed = false
    static var forceStorm: Bool?             // (the checks set the weather)
    static var forceSnow: Bool?
    static let fogSee: Float = 30
}

extension Game {
    var stormGrounds: Bool {
        WeatherWar.forceStorm ?? (dim.dim == .overworld && weather.raining && weather.thundering && weather.thunder > 0.5)
    }

    // The fog's reach for the renderers (nil: no fog).
    // P211 (Oct 13 18:47-18:50, "fog banks keep rolling in and blinding me, especially high up"): fog is a weather
    // of its own now (rarer, announced), and it lies low: it thins above the valleys and is gone 60 blocks up.
    var weatherFogEnd: Float? {
        guard WeatherWar.fog > 0.02, dim.dim == .overworld else { return nil }
        let up = simd_clamp((player.pos.y - Float(YOFF) - 90) / 60, 0, 1)
        let f = WeatherWar.fog * (1 - up)
        guard f > 0.02 else { return nil }
        return WeatherWar.fogSee + (1 - f) * (1 - f) * 220
    }

    // Once a second (the HUD tick).
    func weatherWarTick(_ dt: Double = 1) {
        let over = dim.dim == .overworld
        WeatherWar.fogTimer -= dt
        if WeatherWar.fogTimer <= 0 {
            if WeatherWar.fogOn {
                WeatherWar.fogOn = false
                WeatherWar.fogTimer = Double(Rand.float(in: 900...4000))
            } else {
                let dawn = dayFraction > 0.95 || dayFraction < 0.1
                WeatherWar.fogOn = over && weather.rain < 0.5 && Rand.float(in: 0..<1) < (dawn ? 0.2 : 0.05)   // (P211: was 0.8 / 0.35)
                if WeatherWar.fogOn { onToast?("Fog is rolling in") }
                WeatherWar.fogTimer = WeatherWar.fogOn ? Double(Rand.float(in: 240...600)) : Double(Rand.float(in: 600...2400))
            }
        }
        let want: Float = WeatherWar.fogOn && over ? 1 : 0
        WeatherWar.fog += (want - WeatherWar.fog) * min(1, Float(dt) * 0.05)
        if abs(want - WeatherWar.fog) < 0.01 { WeatherWar.fog = want }
        // Spotting range.
        var s: Float = 1 - 0.6 * WeatherWar.fog
        if stormGrounds { s = min(s, 0.7) } else if over && weather.rain > 0.5 { s = min(s, 0.85) }
        WeatherWar.sight = max(0.35, s)
        // Snow about the player.
        let p = player.pos
        WeatherWar.snowNear = WeatherWar.forceSnow ?? (over && weather.rain > 0.2 && precipitation(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))) == 2)
        // Storm news.
        let storm = stormGrounds
        if storm != WeatherWar.stormed {
            WeatherWar.stormed = storm
            if over { onToast?(storm ? "A storm rolls in: flyers are grounded and no dropship will launch" : "The storm has passed: the skies are open again") }
        }
    }

    // A soldier's pace in the weather: snow falling near the player, or snow underfoot.
    func troopWeatherSpeed(_ m: Mob) -> Float {
        if WeatherWar.snowNear && simd_length(m.pos - player.pos) < 128 { return 0.7 }
        let x = Int(floor(m.pos.x)), y = Int(floor(m.pos.y)), z = Int(floor(m.pos.z))
        guard world.isLoaded(x, z) else { return 1 }
        let at = Blocks.key(world.block(x, y, z)), under = Blocks.key(world.block(x, y - 1, z))
        if at.hasPrefix("snow") || under.hasPrefix("snow_block") || under.hasPrefix("powder_snow") { return 0.7 }
        return 1
    }
}
