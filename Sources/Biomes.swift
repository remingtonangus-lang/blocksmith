import Foundation

// Every biome of the reference game (surface, Emberdeep, End), with the facts that drive generation
// and colour: base temperature (snow below 0.15 after the altitude drop), grass/foliage/water colours.
enum Biome: Int, CaseIterable {
    // Surface: oceans and shores
    case ocean, deepOcean, warmOcean, lukewarmOcean, deepLukewarmOcean, coldOcean, deepColdOcean, frozenOcean, deepFrozenOcean
    case beach, snowyBeach, stonyShore, river, frozenRiver
    // Surface: land
    case plains, sunflowerPlains, snowyPlains, iceSpikes, desert, swamp, mangroveSwamp
    case forest, flowerForest, birchForest, oldGrowthBirchForest, darkForest
    case taiga, oldGrowthPineTaiga, oldGrowthSpruceTaiga, snowyTaiga
    case savanna, savannaPlateau, windsweptHills, windsweptGravellyHills, windsweptForest, windsweptSavanna
    case jungle, sparseJungle, bambooJungle, badlands, erodedBadlands, woodedBadlands
    case meadow, cherryGrove, grove, snowySlopes, frozenPeaks, jaggedPeaks, stonyPeaks, mushroomFields
    // Surface: caves
    case dripstoneCaves, lushCaves, deepDark
    // Emberdeep / End
    case netherWastes, soulSandValley, crimsonForest, warpedForest, basaltDeltas, theEnd

    struct Info {
        let id: String
        let temp: Float
        let grass: UInt32
        let foliage: UInt32
        let water: UInt32
    }

    static let table: [Info] = [
        Info(id: "ocean", temp: 0.5, grass: 0x8EB971, foliage: 0x71A74D, water: 0x3F76E4),
        Info(id: "deep_ocean", temp: 0.5, grass: 0x8EB971, foliage: 0x71A74D, water: 0x3F76E4),
        Info(id: "warm_ocean", temp: 0.5, grass: 0x8EB971, foliage: 0x71A74D, water: 0x43D5EE),
        Info(id: "lukewarm_ocean", temp: 0.5, grass: 0x8EB971, foliage: 0x71A74D, water: 0x45ADF2),
        Info(id: "deep_lukewarm_ocean", temp: 0.5, grass: 0x8EB971, foliage: 0x71A74D, water: 0x45ADF2),
        Info(id: "cold_ocean", temp: 0.5, grass: 0x8EB971, foliage: 0x71A74D, water: 0x3D57D6),
        Info(id: "deep_cold_ocean", temp: 0.5, grass: 0x8EB971, foliage: 0x71A74D, water: 0x3D57D6),
        Info(id: "frozen_ocean", temp: 0.0, grass: 0x80B497, foliage: 0x60A17B, water: 0x3938C9),
        Info(id: "deep_frozen_ocean", temp: 0.5, grass: 0x80B497, foliage: 0x60A17B, water: 0x3938C9),
        Info(id: "beach", temp: 0.8, grass: 0x91BD59, foliage: 0x77AB2F, water: 0x3F76E4),
        Info(id: "snowy_beach", temp: 0.05, grass: 0x83B593, foliage: 0x64A278, water: 0x3D57D6),
        Info(id: "stony_shore", temp: 0.2, grass: 0x8AB689, foliage: 0x6DA36B, water: 0x3F76E4),
        Info(id: "river", temp: 0.5, grass: 0x8EB971, foliage: 0x71A74D, water: 0x3F76E4),
        Info(id: "frozen_river", temp: 0.0, grass: 0x80B497, foliage: 0x60A17B, water: 0x3938C9),
        Info(id: "plains", temp: 0.8, grass: 0x91BD59, foliage: 0x77AB2F, water: 0x3F76E4),
        Info(id: "sunflower_plains", temp: 0.8, grass: 0x91BD59, foliage: 0x77AB2F, water: 0x3F76E4),
        Info(id: "snowy_plains", temp: 0.0, grass: 0x80B497, foliage: 0x60A17B, water: 0x3F76E4),
        Info(id: "ice_spikes", temp: 0.0, grass: 0x80B497, foliage: 0x60A17B, water: 0x3F76E4),
        Info(id: "desert", temp: 2.0, grass: 0xBFB755, foliage: 0xAEA42A, water: 0x3F76E4),
        Info(id: "swamp", temp: 0.8, grass: 0x6A7039, foliage: 0x6A7039, water: 0x617B64),
        Info(id: "mangrove_swamp", temp: 0.8, grass: 0x6A7039, foliage: 0x8DB127, water: 0x3A7A6A),
        Info(id: "forest", temp: 0.7, grass: 0x79C05A, foliage: 0x59AE30, water: 0x3F76E4),
        Info(id: "flower_forest", temp: 0.7, grass: 0x79C05A, foliage: 0x59AE30, water: 0x3F76E4),
        Info(id: "birch_forest", temp: 0.6, grass: 0x88BB67, foliage: 0x6BA941, water: 0x3F76E4),
        Info(id: "old_growth_birch_forest", temp: 0.6, grass: 0x88BB67, foliage: 0x6BA941, water: 0x3F76E4),
        Info(id: "dark_forest", temp: 0.7, grass: 0x507A32, foliage: 0x59AE30, water: 0x3F76E4),
        Info(id: "taiga", temp: 0.25, grass: 0x86B783, foliage: 0x68A464, water: 0x3F76E4),
        Info(id: "old_growth_pine_taiga", temp: 0.3, grass: 0x86B87F, foliage: 0x68A55F, water: 0x3F76E4),
        Info(id: "old_growth_spruce_taiga", temp: 0.25, grass: 0x86B783, foliage: 0x68A464, water: 0x3F76E4),
        Info(id: "snowy_taiga", temp: -0.5, grass: 0x80B497, foliage: 0x60A17B, water: 0x3D57D6),
        Info(id: "savanna", temp: 2.0, grass: 0xBFB755, foliage: 0xAEA42A, water: 0x3F76E4),
        Info(id: "savanna_plateau", temp: 2.0, grass: 0xBFB755, foliage: 0xAEA42A, water: 0x3F76E4),
        Info(id: "windswept_hills", temp: 0.2, grass: 0x8AB689, foliage: 0x6DA36B, water: 0x3F76E4),
        Info(id: "windswept_gravelly_hills", temp: 0.2, grass: 0x8AB689, foliage: 0x6DA36B, water: 0x3F76E4),
        Info(id: "windswept_forest", temp: 0.2, grass: 0x8AB689, foliage: 0x6DA36B, water: 0x3F76E4),
        Info(id: "windswept_savanna", temp: 2.0, grass: 0xBFB755, foliage: 0xAEA42A, water: 0x3F76E4),
        Info(id: "jungle", temp: 0.95, grass: 0x59C93C, foliage: 0x30BB0B, water: 0x3F76E4),
        Info(id: "sparse_jungle", temp: 0.95, grass: 0x64C73F, foliage: 0x3EB80F, water: 0x3F76E4),
        Info(id: "bamboo_jungle", temp: 0.95, grass: 0x59C93C, foliage: 0x30BB0B, water: 0x3F76E4),
        Info(id: "badlands", temp: 2.0, grass: 0x90814D, foliage: 0x9E814D, water: 0x3F76E4),
        Info(id: "eroded_badlands", temp: 2.0, grass: 0x90814D, foliage: 0x9E814D, water: 0x3F76E4),
        Info(id: "wooded_badlands", temp: 2.0, grass: 0x90814D, foliage: 0x9E814D, water: 0x3F76E4),
        Info(id: "meadow", temp: 0.5, grass: 0x83BB6D, foliage: 0x63A948, water: 0x0E4ECF),
        Info(id: "cherry_grove", temp: 0.5, grass: 0xB6DB61, foliage: 0xB6DB61, water: 0x5DB7EF),
        Info(id: "grove", temp: -0.2, grass: 0x80B497, foliage: 0x60A17B, water: 0x3F76E4),
        Info(id: "snowy_slopes", temp: -0.3, grass: 0x80B497, foliage: 0x60A17B, water: 0x3F76E4),
        Info(id: "frozen_peaks", temp: -0.7, grass: 0x80B497, foliage: 0x60A17B, water: 0x3F76E4),
        Info(id: "jagged_peaks", temp: -0.7, grass: 0x80B497, foliage: 0x60A17B, water: 0x3F76E4),
        Info(id: "stony_peaks", temp: 1.0, grass: 0x9ABE4B, foliage: 0x82AC1E, water: 0x3F76E4),
        Info(id: "mushroom_fields", temp: 0.9, grass: 0x55C93F, foliage: 0x2BBB0F, water: 0x3F76E4),
        Info(id: "dripstone_caves", temp: 0.8, grass: 0x91BD59, foliage: 0x77AB2F, water: 0x3F76E4),
        Info(id: "lush_caves", temp: 0.5, grass: 0x8EB971, foliage: 0x71A74D, water: 0x3F76E4),
        Info(id: "deep_dark", temp: 0.8, grass: 0x91BD59, foliage: 0x77AB2F, water: 0x3F76E4),
        Info(id: "nether_wastes", temp: 2.0, grass: 0xBFB755, foliage: 0xAEA42A, water: 0x3F76E4),
        Info(id: "soul_sand_valley", temp: 2.0, grass: 0xBFB755, foliage: 0xAEA42A, water: 0x3F76E4),
        Info(id: "crimson_forest", temp: 2.0, grass: 0xBFB755, foliage: 0xAEA42A, water: 0x3F76E4),
        Info(id: "warped_forest", temp: 2.0, grass: 0xBFB755, foliage: 0xAEA42A, water: 0x3F76E4),
        Info(id: "basalt_deltas", temp: 2.0, grass: 0xBFB755, foliage: 0xAEA42A, water: 0x3F76E4),
        Info(id: "the_end", temp: 0.5, grass: 0x8EB971, foliage: 0x71A74D, water: 0x3F76E4),
    ]

    var info: Info { Biome.table[rawValue] }
    var name: String { info.id }
    // Player-facing biome name (Blocksmith names for the other dimensions).
    var displayName: String {
        let own: [String: String] = ["nether_wastes": "Ember Wastes", "soul_sand_valley": "Ghost Sand Valley", "crimson_forest": "Crimson Forest",
                                     "warped_forest": "Warped Forest", "basalt_deltas": "Basalt Deltas", "the_end": "The Hollow", "deep_dark": "Murk Depths"]
        return own[info.id] ?? info.id.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
    static func named(_ n: String) -> Biome? { allCases.first { $0.name == n } }

    var isOcean: Bool { rawValue <= Biome.deepFrozenOcean.rawValue }
    var isDeepOcean: Bool { [.deepOcean, .deepLukewarmOcean, .deepColdOcean, .deepFrozenOcean].contains(self) }
    var isRiver: Bool { self == .river || self == .frozenRiver }
    var isBeach: Bool { self == .beach || self == .snowyBeach || self == .stonyShore }
    var isBadlands: Bool { self == .badlands || self == .erodedBadlands || self == .woodedBadlands }
    var isPeak: Bool { self == .frozenPeaks || self == .jaggedPeaks || self == .stonyPeaks || self == .snowySlopes }
    // Snow falls here at the given internal y (temperature drops 0.05 per 30 blocks above y 80).
    func snows(at y: Int) -> Bool {
        let t = info.temp - Float(max(0, y - YOFF - 80)) * 0.05 / 30
        return t < 0.15
    }
}
