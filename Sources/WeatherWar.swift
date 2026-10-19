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
    // P253 (Oct 14 12:00 and 12:16, "the mysterious fog just hit me... the air is still open, so it has to be fixed"):
    // the fog banks started under a clear sky ("Fog is rolling in" a second before each note). Fog is now a weather you
    // see coming: the sky clouds over first (Game.cloudCover follows `fog`), and the fog only thickens once the sky is
    // overcast. Under a clear sky there is no fog: the bank, the valley mist (Quest) and the lowland mist (Fancy, Mac)
    // all follow `fogThick`.
    static var fogThick: Float { max(0, (fog - 0.4) / 0.6) }
}

extension Game {
    var stormGrounds: Bool {
        WeatherWar.forceStorm ?? (dim.dim == .overworld && weather.raining && weather.thundering && weather.thunder > 0.5)
    }

    // The fog's reach for the renderers (nil: no fog).
    // P211 (Oct 13 18:47-18:50, "fog banks keep rolling in and blinding me, especially high up"): fog is a weather
    // of its own now (rarer, announced), and it lies low: it thins above the valleys and is gone 60 blocks up.
    var weatherFogEnd: Float? {
        if let s = Storms.sight() {                                         // D49 blizzards and sandstorms
            let up = simd_clamp((player.pos.y - Float(YOFF) - 150) / 60, 0, 1)
            let f = s + (260 - s) * up
            if let o = fogBankEnd { return min(o, f) }
            return f
        }
        return fogBankEnd
    }
    private var fogBankEnd: Float? {
        guard WeatherWar.fog > 0.02, dim.dim == .overworld else { return nil }
        let up = simd_clamp((player.pos.y - Float(YOFF) - 90) / 60, 0, 1)
        let f = WeatherWar.fogThick * (1 - up)
        guard f > 0.02 else { return nil }
        // P365 (g, "fog rolled in and vanished at once"): the reach starts far past any view distance and closes in
        // smoothly as the bank thickens (it opened at 250 blocks the moment the bank began, and snapped back to the
        // full view when it ended).
        return WeatherWar.fogSee + (1 - f) * (1 - f) * (1 - f) * 1400
    }
    // Where the fog starts, as a share of its reach: near the reach while the bank is thin, closing to a fifth when it
    // is thick (it jumped from the clear edge band to a fifth at once).
    var weatherFogStartK: Float {
        if Storms.sight() != nil { return 0.2 }                            // (blizzards and sandstorms: thick at once)
        let f = WeatherWar.fogThick
        return 0.2 + 0.74 * (1 - f) * (1 - f)
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
                // P365 (g): fog only where and when air is foggy: the early morning, light rain, and swamps, coasts,
                // rivers and the sea; never in dry country (deserts, badlands, savanna) or the high peaks.
                let dawn = dayFraction > 0.95 || dayFraction < 0.1
                let b = audio.biomeHere
                let damp = b.isOcean || b.isBeach || b.isRiver || b == .swamp || b == .mangroveSwamp
                let dry = [.desert, .badlands, .erodedBadlands, .woodedBadlands, .savanna, .savannaPlateau, .windsweptSavanna,
                           .jaggedPeaks, .frozenPeaks, .stonyPeaks].contains(b)
                let wet = weather.rain > 0.2 && weather.rain < 0.7 && !weather.thundering
                let chance: Float = dry ? 0 : (dawn ? 0.2 : 0) + (damp ? 0.12 : 0) + (wet ? 0.1 : 0)
                WeatherWar.fogOn = over && Rand.float(in: 0..<1) < chance   // (P211: was 0.8 / 0.35)
                if WeatherWar.fogOn { onToast?("The sky is clouding over: fog is coming") }
                WeatherWar.fogTimer = WeatherWar.fogOn ? Double(Rand.float(in: 240...600)) : Double(Rand.float(in: 600...2400))
            }
        }
        let want: Float = WeatherWar.fogOn && over ? 1 : 0
        // P365 (g): it rolls in and lifts over two to three minutes (a steady drift, not a quick exponential snap).
        let step = Float(dt) / 150
        WeatherWar.fog = want > WeatherWar.fog ? min(want, WeatherWar.fog + step) : max(want, WeatherWar.fog - step)
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

    // P253: the valley mist's strength (the Quest's chunk shaders, SH1): only in foggy weather, never under a clear sky
    // (it lay in the low ground every dawn, dusk and night).
    var valleyMist: Float {
        guard dim.dim == .overworld && dim.dim.hasSky else { return 0 }
        return 0.55 * WeatherWar.fogThick * (1 - min(1, weather.rain * 2))
    }

    // A soldier's pace in the weather: snow falling near the player, or snow underfoot.
    func troopWeatherSpeed(_ m: Mob) -> Float {
        if WeatherWar.snowNear && simd_length(m.pos - player.pos) < 128 { return 0.7 }
        let x = Int(floor(m.pos.x)), y = Int(floor(m.pos.y)), z = Int(floor(m.pos.z))
        guard world.isLoaded(x, z) else { return 1 }
        let at = Blocks.key(world.materialAt(x, y, z)), under = Blocks.key(world.materialAt(x, y - 1, z))
        if at.hasPrefix("snow") || under.hasPrefix("snow_block") || under.hasPrefix("powder_snow") { return 0.7 }
        return 1
    }
}
