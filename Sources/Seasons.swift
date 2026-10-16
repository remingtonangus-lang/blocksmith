import Foundation
import simd

// Seasons (backlog C9; docs/status/seasons.md). A year is four seasons of seven days (a week each), spring first:
// day 0 of every world is the first day of spring. Everything follows the day count, so a save needs nothing new.
//   weather   the season shifts every biome's temperature (spring -0.1, summer +0.2, autumn -0.15, winter -0.7):
//             in winter snow falls instead of rain over the plains, forests and swamps, settles on the ground and the
//             treetops and lakes freeze from the shore; from spring the seasonal snow and ice melt again (never in
//             biomes that are cold all year).
//   crops     grow 1.2x in spring, 1.5x in summer, 1x in autumn; out in the open they stop in winter (under a roof,
//             a greenhouse lit to 9, they grow at half speed). Shops pay 30% more for crops in winter, 15% less at
//             the harvest (summer, autumn).
//   animals   fewer animals turn up in winter (a third outside the warm biomes); in autumn the herds drift south and
//             in spring they come back north.
//   hunting   the open season is autumn and winter: pelts sell 40% dearer. Killing game in spring (the young are born)
//             within 300 blocks of a town costs honour (-2, "hunting out of season").
//   festivals the third day of every season is a town festival (Spring Fair, Midsummer Fair, Harvest Festival, Winter
//             Lights): townsfolk gather at the bell all day, shops take 10% off, and at night fireworks go up over the
//             square while you're in town.
// The season and the day in it show on the world map's coordinates line; a toast marks each new season and festival.
enum Seasons {
    enum Season: Int, CaseIterable {
        case spring, summer, autumn, winter
        var name: String { ["Spring", "Summer", "Autumn", "Winter"][rawValue] }
        var festival: String { ["Spring Fair", "Midsummer Fair", "Harvest Festival", "Winter Lights"][rawValue] }
        var chill: Float { [0.1, -0.2, 0.15, 0.7][rawValue] }
        var crops: Float { [1.2, 1.5, 1, 0][rawValue] }
    }
    static let daysPerSeason = 7
    static let festivalDay = 2                          // the third day (0-based)

    // Set from the game's day each second (Seasons.tick); read by code that has no Game (biomes, prices).
    static var day = 0
    static var season: Season { Season(rawValue: (day / daysPerSeason) % 4)! }
    static var dayInSeason: Int { day % daysPerSeason }
    static var festival: Bool { dayInSeason == festivalDay }
    static func of(day d: Int) -> (Season, Int) { (Season(rawValue: (max(0, d) / daysPerSeason) % 4)!, max(0, d) % daysPerSeason) }

    // A biome's snow line now (Weather): the base rule with the season's chill.
    static func snows(_ b: Biome, at y: Int) -> Bool {
        let t = b.info.temp - Float(max(0, y - YOFF - 80)) * 0.05 / 30 - season.chill
        return t < 0.15
    }
    // Snow and ice in a biome that isn't cold all year (they melt once the season turns).
    static func seasonal(_ b: Biome, at y: Int) -> Bool { !b.snows(at: y) }

    // Crop growth (Farming.randomTick): open sky (sky light 14+) follows the season; under a roof winter halves it.
    static func cropScale(sky: Int) -> Float {
        let s = season
        if s == .winter { return sky >= 14 ? 0 : 0.5 }
        return s.crops
    }

    static let cropKeys: Set<String> = ["wheat", "carrot", "potato", "beetroot", "pumpkin", "melon_slice", "sweet_berries", "apple", "bread"]
    // What a shop pays, scaled (Economy.sellPrice).
    static func sellScale(_ item: ItemID) -> Float {
        let k = Items.key(item)
        if k.contains("_pelt_") { return season == .autumn || season == .winter ? 1.4 : 1 }
        if cropKeys.contains(k) { return season == .winter ? 1.3 : (season == .summer || season == .autumn ? 0.85 : 1) }
        return 1
    }
    static var buyNudge: Float { festival ? -0.1 : 0 }   // (ShopPricing) festival day: 10% off

    // Animal spawns (MobManager.trySpawnPassive): a third in winter outside warm biomes, more in spring.
    static func animalChance(_ b: Biome) -> Float {
        switch season {
        case .winter: return b.info.temp >= 0.95 ? 1 : 0.33
        case .spring: return 1
        default: return 1
        }
    }

    // MARK: Every second (Game.tick)

    static var lastAnnounced = -1
    static var migrated = 0, shows = 0, outOfSeason = 0                   // (tests)
    static var sweepTick = 0, sweepIndex = 0, swept = 0                   // P277: the melt sweep (Game.seasonalMeltSweep)
    static var nextShow: Double = 0

    static func tick(_ g: Game) {
        day = Int(g.time / DAY_LENGTH)
        if lastAnnounced != day {
            if lastAnnounced >= 0 && g.dim.dim == .overworld {
                if dayInSeason == 0 { g.onToast?(announce(season)) }
                else if festival { g.onToast?("Today is the \(season.festival): the towns gather at their bells") }
            }
            lastAnnounced = day
        }
        guard g.dim.dim == .overworld else { return }
        migrate(g)
        festivalNight(g)
    }
    static func announce(_ s: Season) -> String {
        switch s {
        case .spring: return "Spring: the snow melts and the young are born"
        case .summer: return "Summer: the crops grow fastest"
        case .autumn: return "Autumn: hunting season opens, and the herds drift south"
        case .winter: return "Winter: snow on the plains, the lakes freeze and the fields lie still"
        }
    }

    // Herds drift: autumn south, spring north (wild game only, idle, a few at a time).
    static func migrate(_ g: Game) {
        let s = season
        guard s == .autumn || s == .spring else { return }
        let dir: Float = s == .autumn ? 1 : -1
        var n = 0
        for m in g.mobs.mobs where n < 3 && m.health > 0 && !m.persistent && !m.baby && m.owner != true && Hunting.isGame(m) && !m.moving && m.wanderGoal == nil {
            guard Rand.float(in: 0..<1) < 0.08 else { continue }
            m.wanderGoal = m.pos + V3(Rand.float(in: -6...6), 0, dir * Rand.float(in: 16...28))
            m.moving = true
            m.aiTimer = 8
            n += 1; migrated += 1
        }
    }

    // Spring: hunting near a town (Hunting.died).
    static func gameKilled(_ g: Game, _ m: Mob) {
        guard season == .spring, g.survival, g.dim.dim == .overworld,
              let v = g.world.gen.structures?.nearest("village", x: Int(floor(m.pos.x)), z: Int(floor(m.pos.z)), maxRegions: 1),
              simd_length(V2(Float(v.anchor.x) - m.pos.x, Float(v.anchor.z) - m.pos.z)) < 300 else { return }
        let c = V3(Float(v.anchor.x), Float(v.anchor.y), Float(v.anchor.z))
        Honour.change(g, -2, "hunting out of season near \(Townsfolk.town(g, at: c))")
        outOfSeason += 1
    }

    // Festival nights: rockets over the square while the player is in a town.
    static func festivalNight(_ g: Game) {
        guard festival, g.dayFraction > 0.52, g.dayFraction < 0.9, TownLaw.inTown != nil, g.clock >= nextShow,
              Items.has("firework_star"), let c = g.nearVillage(g.player.pos) else { return }
        nextShow = g.clock + Double(Rand.float(in: 2...5))
        var star = ItemStack(Items.id("firework_star"), 1)
        star.tag = Rand.int(in: 0...2) | (Rand.int(in: 0..<2) == 0 ? 8 : 16)
        star.pat = [Rand.int(in: 0..<16), Rand.int(in: 0..<16)]
        let at = c + V3(Rand.float(in: -6...6), 2, Rand.float(in: -6...6))
        g.rockets.append(Rocket(at: at, dir: V3(0, 1, 0), flight: 3, stars: [star]))
        g.sfx(.fireworkLaunch, 1, at: at)
        shows += 1
    }

    // The world map's coordinates line.
    static var label: String { "\(season.name), day \(dayInSeason + 1)" + (festival ? " (\(season.festival))" : "") }
}

extension Game {
    // Winter snow and spring melt (Weather.precipitationTicks, the columns it samples).
    func seasonalMelt(_ x: Int, _ y: Int, _ z: Int, _ top: BlockID, _ biome: Biome) {
        guard Seasons.seasonal(biome, at: y), !Seasons.snows(biome, at: y), Rand.int(in: 0..<3) == 0 else { return }
        if Blocks.has("snow"), world.block(x, y + 1, z) == Blocks.id("snow") { world.setBlockAsync(x, y + 1, z, AIR) }
        else if Blocks.has("snow"), top == Blocks.id("snow") { world.setBlockAsync(x, y, z, AIR) }
        else if Blocks.has("ice"), top == Blocks.id("ice"), world.block(x, y - 1, z) == WATER || isShallowIce(x, y, z) { world.setBlockAsync(x, y, z, WATER) }
    }
    private func isShallowIce(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { world.block(x + $0.0, y, z + $0.1) == WATER }
    }

    // P277 (Oct 14 19:33, out at sea in the first days of spring: "a ground somehow floating on the water"): winter's
    // ice was left lying on the sea as floes. The melt above samples one column of a chunk now and then, so a frozen
    // stretch took game-hours to go and chunks out of reach all spring kept their ice. Now a sweep walks every chunk
    // round the player (one each half second) and melts its seasonal snow and ice: some of it on the first day of
    // spring, the rest by the third, all of it at once in summer and autumn. (Oceans no longer freeze in winter
    // either: Weather.precipitationTicks.)
    func seasonalMeltSweep() {
        Seasons.sweepTick += 1
        guard wetWorld, Seasons.sweepTick % 10 == 0, Blocks.has("ice") else { return }
        let s = Seasons.season
        guard s != .winter else { return }
        let p: Float = s == .spring ? min(1, Float(Seasons.dayInSeason + 1) / 3) : 1
        let r = min(8, world.renderDistance), side = 2 * r + 1
        let k = Seasons.sweepIndex % (side * side)
        Seasons.sweepIndex += 1
        let pcx = floorDiv(Int(floor(player.pos.x)), CS), pcz = floorDiv(Int(floor(player.pos.z)), CS)
        guard let c = world.chunks[ChunkKey(x: pcx + k % side - r, z: pcz + k / side - r)] else { return }
        let ice = Blocks.id("ice"), snow: BlockID = Blocks.has("snow") ? Blocks.id("snow") : ice
        for lz in 0..<CS { for lx in 0..<CS {
            let x = c.cx * CS + lx, z = c.cz * CS + lz
            let y = Int(c.height[lx + lz * CS])
            guard y > 0 && y < CH - 1 else { continue }
            let top = world.block(x, y, z)
            let capped = top != ice && world.block(x, y + 1, z) == snow
            guard top == ice || top == snow || capped else { continue }
            let biome = world.gen.column(x, z).biome
            guard Seasons.seasonal(biome, at: y), !Seasons.snows(biome, at: y), Rand.float(in: 0..<1) < p else { continue }
            if capped { world.setBlockAsync(x, y + 1, z, AIR) }
            else if top == snow { world.setBlockAsync(x, y, z, AIR) }
            else if world.block(x, y - 1, z) == WATER || isShallowIce(x, y, z) { world.setBlockAsync(x, y, z, WATER); Seasons.swept += 1 }
        } }
    }
}
