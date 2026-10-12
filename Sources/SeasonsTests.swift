import Foundation
import simd

// Seasons (backlog C9), `questcheck --seasons-only`:
//   calendar   day 0 spring, day 7 summer, 14 autumn, 21 winter, 28 spring again; festival on each season's third day
//   weather    in winter plains and forest snow; in summer they don't; the snowy taiga and the desert keep their own
//   melt       a snow layer and shore ice on a plains lake in spring melt away under the precipitation ticks; in winter
//              the same lake freezes
//   crops      open-sky wheat grows in summer and never in winter; a roofed field still grows in winter
//   prices     pelts sell dearer in autumn, crops dearer in winter, festival days 10% off
//   animals    winter spawns a third outside warm biomes; autumn herds walk south, spring north
//   hunting    a deer killed near a town in spring costs honour; in autumn it doesn't
//   festival   at night on festival day in a town, fireworks go up
enum SeasonsTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let time = g.time, sday = Seasons.day
        defer { g.time = time; Seasons.day = sday }
        func at(day d: Int, frac: Double = 0.25) { g.time = (Double(d) + frac) * DAY_LENGTH; Seasons.day = d }

        // Calendar.
        let names = [0, 7, 14, 21, 28].map { Seasons.of(day: $0).0.name }
        let fest = (0..<28).filter { at(day: $0); return Seasons.festival }
        check(names == ["Spring", "Summer", "Autumn", "Winter", "Spring"] && fest == [2, 9, 16, 23],
              "C9 calendar: days 0/7/14/21/28 are \(names); festivals on days \(fest.map { $0 + 1 })")

        // Weather.
        let y = SEA + 10
        func snowy(_ b: Biome, _ d: Int) -> Bool { at(day: d); return Seasons.snows(b, at: y) }
        let plainsW = snowy(.plains, 22), forestW = snowy(.forest, 22), plainsS = snowy(.plains, 8), desertW = snowy(.desert, 22)
        let taigaS = snowy(.snowyTaiga, 8)
        check(plainsW && forestW && !plainsS && !desertW && taigaS,
              "C9 weather: winter snow on plains \(plainsW), forest \(forestW); summer plains \(plainsS); winter desert \(desertW); summer snowy taiga \(taigaS)")

        // Melt and freeze on a little pond by the player.
        let w = g.world
        let p = g.player.pos
        let bx = Int(floor(p.x)) + 6, bz = Int(floor(p.z)) + 6
        var undo: [(IVec3, BlockID)] = []
        func set(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { undo.append((IVec3(x, y, z), w.block(x, y, z))); w.setBlock(x, y, z, b) }
        let gy = Int(floor(p.y)) + 20                    // up in the air, on a platform of our own (open sky)
        let stone = STONE, ice = Blocks.id("ice"), snow = Blocks.id("snow")
        for dx in -2...2 { for dz in -2...2 { set(bx + dx, gy - 1, bz + dz, stone); set(bx + dx, gy, bz + dz, abs(dx) == 2 || abs(dz) == 2 ? stone : WATER) } }
        set(bx, gy, bz, ice); set(bx + 1, gy, bz, stone); set(bx + 1, gy + 1, bz, snow)
        defer { for (q, b) in undo.reversed() { w.setBlock(q.x, q.y, q.z, b) } }
        at(day: 1)
        let biome = Biome.plains
        for _ in 0..<40 { g.seasonalMelt(bx, gy, bz, w.block(bx, gy, bz), biome); g.seasonalMelt(bx + 1, gy, bz, w.block(bx + 1, gy, bz), biome) }
        let melted = w.block(bx, gy, bz) == WATER && w.block(bx + 1, gy + 1, bz) == AIR
        at(day: 22)
        let keepIce = { () -> Bool in w.setBlock(bx, gy, bz, ice); for _ in 0..<40 { g.seasonalMelt(bx, gy, bz, ice, biome) }; return w.block(bx, gy, bz) == ice }()
        check(melted && keepIce, "C9 melt: in spring a plains pond's ice and a snow layer melt (\(melted)); in winter the ice stays (\(keepIce))")

        // Crops.
        func growth(_ d: Int, sky: Int) -> Float { at(day: d); return Seasons.cropScale(sky: sky) }
        check(growth(8, sky: 15) > growth(1, sky: 15) && growth(1, sky: 15) > growth(15, sky: 15) && growth(22, sky: 15) == 0 && growth(22, sky: 9) > 0,
              String(format: "C9 crops: open-field growth spring %.1fx, summer %.1fx, autumn %.1fx, winter %.1fx; a roofed field in winter %.1fx",
                     growth(1, sky: 15), growth(8, sky: 15), growth(15, sky: 15), growth(22, sky: 15), growth(22, sky: 9)))

        // Prices.
        let pelt = (1..<Items.count).map { ItemID($0) }.first { Items.key($0).contains("_pelt_") }
        let wheat = Items.has("wheat") ? Items.id("wheat") : nil
        at(day: 1); let peltSpring = pelt.map(Seasons.sellScale) ?? 0, wheatSpring = wheat.map(Seasons.sellScale) ?? 0
        at(day: 15); let peltAutumn = pelt.map(Seasons.sellScale) ?? 0
        at(day: 22); let wheatWinter = wheat.map(Seasons.sellScale) ?? 0
        at(day: 2); let fair = ShopPricing(reputation: 0, hero: 0).buyMult
        at(day: 3); let plain = ShopPricing(reputation: 0, hero: 0).buyMult
        check(peltAutumn > peltSpring && wheatWinter > wheatSpring && fair < plain,
              String(format: "C9 prices: pelts x%.2f in spring, x%.2f in autumn; wheat x%.2f in spring, x%.2f in winter; shop prices x%.2f at the fair, x%.2f the day after",
                     peltSpring, peltAutumn, wheatSpring, wheatWinter, fair, plain))

        // Animals.
        at(day: 22); let winter = Seasons.animalChance(.plains), winterJungle = Seasons.animalChance(.jungle)
        at(day: 8); let summer = Seasons.animalChance(.plains)
        let saved = g.mobs.mobs
        defer { g.mobs.mobs = saved; g.mobs.rebuildIndex() }
        func herd(day d: Int) -> Float {
            at(day: d)
            let deerKind = MobKind.allCases.first { Hunting.animal($0) != nil } ?? .cow
            let herd = (0..<20).map { i -> Mob in let m = Mob(deerKind, at: p + V3(Float(i), 0, 0)); return m }
            g.mobs.mobs = herd; g.mobs.rebuildIndex()
            for _ in 0..<60 { Seasons.migrate(g); for m in herd where m.moving { m.moving = false } }
            let goals = herd.compactMap { $0.wanderGoal.map { $0.z - p.z } }
            return goals.isEmpty ? 0 : goals.reduce(0, +) / Float(goals.count)
        }
        let south = herd(day: 15), north = herd(day: 1)
        check(winter < 0.5 && winterJungle == 1 && summer == 1 && south > 10 && north < -10,
              String(format: "C9 animals: winter spawns x%.2f on the plains (jungle x%.2f, summer x%.2f); autumn herds head %.0f blocks south, spring %.0f north",
                     winter, winterJungle, summer, south, -north))

        // Hunting out of season.
        let honour0 = Honour.value, n0 = Seasons.outOfSeason
        let surv = g.survival
        g.survival = true
        defer { g.survival = surv; Honour.value = honour0 }
        let near = g.world.gen.structures?.nearest("village", x: Int(floor(p.x)), z: Int(floor(p.z)), maxRegions: 8)
        let deer = Mob(.cow, at: near.map { V3(Float($0.anchor.x) + 20, Float($0.anchor.y), Float($0.anchor.z)) } ?? p)
        at(day: 15); Seasons.gameKilled(g, deer)
        let autumnCost = Seasons.outOfSeason - n0
        at(day: 1); Seasons.gameKilled(g, deer)
        let springCost = Seasons.outOfSeason - n0 - autumnCost
        check(near == nil || (autumnCost == 0 && springCost == 1 && Honour.value < honour0),
              "C9 hunting: a kill 20 blocks from a town costs honour in spring (\(springCost)), not in autumn (\(autumnCost))" + (near == nil ? " (no town near: skipped)" : ""))

        // Festival fireworks.
        if let v = near {
            let pos0 = g.player.pos
            defer { g.player.pos = pos0; TownLaw.inTown = nil; g.rockets.removeAll() }
            g.player.pos = V3(Float(v.anchor.x), Float(v.anchor.y + 1), Float(v.anchor.z))
            _ = w.loadSync(center: g.player.pos, radius: 3)
            TownLaw.inTown = "Testford"
            let villager = Mob(.villager, at: g.player.pos + V3(2, 0, 0))
            g.mobs.mobs = [villager]; g.mobs.rebuildIndex()
            at(day: 9, frac: 0.6)
            Seasons.nextShow = 0
            let s0 = Seasons.shows
            for _ in 0..<5 { Seasons.festivalNight(g); Seasons.nextShow = 0 }
            at(day: 10, frac: 0.6)
            let off = Seasons.shows
            Seasons.festivalNight(g)
            check(Seasons.shows - s0 == 5 && Seasons.shows == off && !g.rockets.isEmpty,
                  "C9 festival: \(off - s0) rockets over the square on Midsummer Fair night, none the night after")
        }
        at(day: 16)
        check(Seasons.label.contains("Autumn") && Seasons.label.contains("Harvest Festival"), "C9 map label: \(Seasons.label)")
    }
}
