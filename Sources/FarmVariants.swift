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
