import Foundation
import simd

// Weather that matters (backlog O7), `questcheck --weather-only`: a storm grounds dropships, fog shortens soldiers'
// spotting range and the view, snow slows soldiers.
enum WeatherWarTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let pos0 = g.player.pos, mobs0 = g.mobs.mobs, surv0 = g.survival
        defer {
            g.player.pos = pos0; g.mobs.mobs = mobs0; g.survival = surv0
            WeatherWar.forceStorm = nil; WeatherWar.forceSnow = nil; WeatherWar.fogOn = false; WeatherWar.fog = 0; WeatherWar.fogTimer = 1200
            g.weatherWarTick(0)
        }
        g.survival = true
        WeatherWar.forceStorm = false; WeatherWar.forceSnow = false
        WeatherWar.fogOn = false; WeatherWar.fog = 0; WeatherWar.fogTimer = 1e9
        g.weatherWarTick(0)
        let clearSight = WeatherWar.sight, clearFog = g.weatherFogEnd

        // Storm: no dropship launches, spotting falls.
        WeatherWar.forceStorm = true
        g.weatherWarTick(0)
        let p = g.player.pos
        let launched = g.world.ships.callDropship(faction: .greywall, from: p + V3(200, 70, 0), to: p + V3(20, 0, 0), game: g, sync: true)
        check(!launched && WeatherWar.sight <= 0.7 && clearSight == 1 && clearFog == nil,
              "weather: a storm grounds the dropship (launched \(launched)) and cuts spotting to x\(WeatherWar.sight); clear skies x\(clearSight)")
        WeatherWar.forceStorm = false

        // Fog: the view closes in, and a trooper 20 blocks off no longer spots the player.
        func spots() -> Bool {
            g.player.pos = p + V3(0, 40, 0)
            let m = Mob(.soldierTrooper, at: p + V3(20, 40, 0)); m.faction = Faction.greywall.rawValue
            g.mobs.mobs = [m]
            _ = m.soldierAI(0.05, g, dist: 20, canTarget: true)
            return m.soldierBrain.sees
        }
        g.weatherWarTick(0)
        let seesClear = spots()
        WeatherWar.fogOn = true; WeatherWar.fog = 1
        g.weatherWarTick(0)
        let seesFog = spots(), see = g.weatherFogEnd ?? 0
        check(seesClear && !seesFog && see <= WeatherWar.fogSee + 1 && WeatherWar.sight < 0.45,
              "weather: in fog the view ends at \(Int(see)) blocks and a trooper 20 blocks off loses the player (clear \(seesClear), fog \(seesFog))")
        WeatherWar.fogOn = false; WeatherWar.fog = 0

        // Snow: soldiers slow.
        let m = Mob(.soldierTrooper, at: p + V3(4, 40, 0))
        WeatherWar.forceSnow = true; g.weatherWarTick(0)
        let slow = g.troopWeatherSpeed(m)
        WeatherWar.forceSnow = false; g.weatherWarTick(0)
        let normal = g.troopWeatherSpeed(m)
        check(slow == 0.7 && normal == 1, "weather: falling snow slows soldiers to x\(slow) (x\(normal) without)")
    }
}
