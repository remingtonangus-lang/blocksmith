import Foundation
import simd

// Climate variants of cows, pigs and chickens: each takes the look of the biome it first appears in
// (temperate, warm or cold); babies take a parent's; chickens lay matching eggs (egg, brown egg,
// blue egg) and a thrown egg hatches its own kind. `variant`: 0 not yet placed, 1 temperate, 2 warm, 3 cold.
enum FarmVariant {
    static let warm: Set<String> = ["savanna", "savanna_plateau", "windswept_savanna", "jungle", "sparse_jungle", "bamboo_jungle",
                                    "badlands", "eroded_badlands", "wooded_badlands", "mangrove_swamp", "desert", "warm_ocean",
                                    "nether_wastes", "soul_sand_valley", "crimson_forest", "warped_forest", "basalt_deltas"]
    static let cold: Set<String> = ["snowy_plains", "ice_spikes", "frozen_peaks", "jagged_peaks", "snowy_slopes", "grove", "snowy_taiga",
                                    "taiga", "old_growth_pine_taiga", "old_growth_spruce_taiga", "windswept_hills", "windswept_gravelly_hills",
                                    "windswept_forest", "stony_shore", "frozen_ocean", "deep_frozen_ocean", "cold_ocean", "deep_cold_ocean",
                                    "frozen_river", "snowy_beach", "the_end"]

    static func climate(_ variant: Int) -> Int { variant == 0 ? 1 : variant }

    static func forBiome(_ w: World, _ p: V3) -> Int {
        let n = Spawns.biome(w, Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))).name
        return warm.contains(n) ? 2 : (cold.contains(n) ? 3 : 1)
    }

    // Rabbit coats by biome as in the reference (Remington, playtest 2: every colour of rabbit hopped about the desert):
    // deserts gold; snowy biomes 80 % white, 20 % black and white; elsewhere brown 50 %, salt and pepper 40 %, black 10 %.
    // 0 brown, 1 white, 2 black, 3 gold, 4 salt and pepper, 5 black and white. Placed coats carry 16 (see Mob.tick).
    static let snowy: Set<String> = ["snowy_plains", "ice_spikes", "snowy_taiga", "grove", "snowy_slopes", "frozen_peaks", "jagged_peaks",
                                     "snowy_beach", "frozen_river"]
    static func rabbitCoat(_ w: World, _ p: V3) -> Int {
        let n = Spawns.biome(w, Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))).name
        let r = Rand.float(in: 0..<1)
        if n == "desert" { return 3 }
        if snowy.contains(n) { return r < 0.8 ? 1 : 5 }
        return r < 0.5 ? 0 : (r < 0.9 ? 4 : 2)
    }

    static func eggKey(_ variant: Int) -> String {
        switch climate(variant) {
        case 2: return Items.has("brown_egg") ? "brown_egg" : "egg"
        case 3: return Items.has("blue_egg") ? "blue_egg" : "egg"
        default: return "egg"
        }
    }

    static func forEgg(_ item: ItemID) -> Int {
        guard item != 0 else { return 1 }
        switch Items.key(item) {
        case "brown_egg": return 2
        case "blue_egg": return 3
        default: return 1
        }
    }
}
