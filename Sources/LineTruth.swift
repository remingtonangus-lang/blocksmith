import Foundation
import simd

// P478 lines sweep (Remington's BLOOM rule, Oct 28; the example was "good to see you again" from a stranger and a horse
// line with no horse). The general rule: no line may claim something about the world that is not true when it is said.
// Every line the game speaks (the townsfolk's recorded books, TownVoice.script and script2; the soldiers', outlaws' and
// crews' lines, TroopVoice.script; the written lines for the hour and the moment, TownLines.table; and the lines said
// straight from code through Townsfolk.say) is read here for what must be true for it to be said, and the game checks
// that before it says it:
//   the hour        a "Morning" / "Afternoon" / "Evening" greeting only at that hour; stars, the moon, lit lamps only
//                   after dark; "fine day", "come in out of the sun" only by day
//   the weather     fine weather, a lovely day, bright stars only under a clear sky; wishing or forecasting rain only
//                   while it isn't raining
//   the land        heat ("hot enough for you?", "before the heat") only in warm country
//   him             "you look hungry" only when he is; "ridden a long way" only riding or with his horse; "is that a real
//                   gun?" only holding one; "nice hat" only wearing one; his horse only with it; "heard you've been busy"
//                   only after deeds the towns hear of
//   knowing him     "good to see you again" and the like only from someone he met on an earlier day; "howdy, stranger",
//                   "a new face", "welcome to town" only from someone who hadn't met him before today
//   the town        the saloon, piano, church, bank, doctor, jail, mine only where the town has one (its keeper, preacher,
//                   banker, doctor, lawman or miners live there); "the jail's empty" only with nobody in it; the creek and
//                   the river only by water; "the train's coming one day" only with no line near, "saw the train smoke"
//                   only with one; the windmill and the water tower (no town has either) never
//   a fight         "he's on the roof", "at the window", "at the stairs" only where he is; "grenade, get down!" only with
//                   his grenade near; "grenade out!" only from the one throwing; trucks and horses only where there are
// A pool with no fitting line says nothing (it fell back to the unfit lines before). A line said straight from code
// whose only fault is its greeting's hour has the greeting put right ("Afternoon, Rem" at dusk is "Evening, Rem");
// any other untrue line from code is not said. questcheck --linetruth reads every line and checks each rule both ways.
enum LineTruth {
    enum Need: String, CaseIterable {
        case morning, afternoon, evening, lateDay, dark, daylight, clearSky, dry, warmLand
        case hungry, rode, horse, gunHeld, hat, met, stranger, deeds
        case saloon, church, bank, doctor, jail, jailEmpty, mine, railway, noRailway, water, never
        case above, window, stairs, grenade, throwing, trucks, horses
        case coolLand, notFrozen, inland, armed, wasJailed
    }

    // What a line needs, read from its words (lowercased). Phrases, not single words: "neither's mine" is no mine, "quiet
    // as a church" no church.
    static let rules: [(phrases: [String], needs: [Need], prefix: Bool)] = [
        (["morning", "mornin'", "good morning"], [.morning], true),
        (["afternoon", "good afternoon"], [.afternoon], true),
        (["evening, friend. or is it still afternoon"], [.lateDay], false),
        (["evening", "good evening"], [.evening], true),
        (["stars are", "stars out here", "the stars out here", "shooting stars", "stars are thick"], [.dark, .clearSky], false),
        (["pretty sky tonight", "look at that sunset", "watched the sunset"], [.clearSky], false),
        (["moon's up", "the moon's following"], [.dark], false),
        (["lamps are lit"], [.dark], false),
        (["fine weather", "lovely day", "fine day", "nice day"], [.daylight, .clearSky], false),
        (["come in out of the sun", "in this sun", "hot out", "hot enough for you"], [.daylight, .clearSky, .warmLand], false),
        (["before the heat", "beat the heat", "too hot", "plate's warm in summer"], [.warmLand], false),
        (["good rain would do", "need rain", "pray for rain", "rain is coming", "rain's coming", "rain by supper",
          "rain tomorrow", "say rain is coming"], [.dry], false),
        (["you look hungry"], [.hungry], false),
        (["ridden a long way"], [.rode], false),
        (["is that a real gun"], [.gunHeld], false),
        (["nice hat"], [.hat], false),
        (["heard you've been busy"], [.deeds], false),
        (["back again?", "good to see you again", "look who's still breathing", "weren't you here last week",
          "welcome back", "ah, you again", "a regular", "hmph. you again", "our favourite traveller", "supper's on me next time",
          "well, look who it is", "good to see a face i know"], [.met], false),
        (["howdy, stranger", "don't think i've seen you before", "a new face", "stranger. keep your business",
          "hold it right there, stranger", "on thin ice, stranger", "pleasure. name's not important", "welcome to town"],
         [.stranger], false),
        (["saloon", "piano"], [.saloon], false),
        (["the church", "church choir", "church bell", "church roof", "church door", "church steps", "in the church"], [.church], false),
        (["the bank", "bank's safer", "this is a bank", "on the bank"], [.bank], false),
        (["doctor"], [.doctor], false),
        (["jail"], [.jail], false),
        (["jail's empty", "jail full of nobody"], [.jailEmpty], false),
        (["the old mine", "the mine", "in the mine", "first shift's going down"], [.mine], false),
        (["train's coming through here"], [.noRailway], false),
        (["saw the train smoke"], [.railway], false),
        (["creek", "the river", "side of the river"], [.water], false),
        (["windmill", "water tower", "below the mill"], [.never], false),
        (["he's on the roof"], [.above], false),
        (["he's at the window"], [.window], false),
        (["he's at the stairs", "came down the stairwell"], [.stairs], false),
        (["grenade! get down"], [.grenade], false),
        (["grenade out"], [.throwing], false),
        (["run for the trucks", "into the trucks", "behind the truck"], [.trucks], false),
        (["get the horses", "my horse bites"], [.horses], false),
        (["the stars don't salute"], [.dark, .clearSky], false),
        (["sun's too bright"], [.clearSky], false),
        (["frost came early"], [.coolLand], false),
        (["hear the crickets"], [.notFrozen], false),
        (["have you ever seen the sea", "still not seen the sea"], [.inland], false),
        (["can i see your gun"], [.armed], false),
        (["right side of the bars"], [.wasJailed], false),
        (["you new? rules are simple", "where'd you ride in from"], [.stranger], false),
    ]
    // Lines a rule's words would catch that make no claim (the past, a figure of speech, a question).
    static let exempt: Set<String> = ["We had a flood in '49. Washed the church away.", "Quiet as a church out here.",
                                      "Stars were brighter when I was young. Or my eyes were.", "Pleasure. Name's not important. Neither's mine."]

    private static var cache: [String: [Need]] = [:]
    private static let lock = NSLock()
    static func needs(_ text: String) -> [Need] {
        lock.lock(); defer { lock.unlock() }
        if let n = cache[text] { return n }
        var out: [Need] = []
        if !exempt.contains(text) {
            let t = text.lowercased()
            var greeted = false
            for r in rules {
                // (one greeting a line: "Evening, friend. Or is it still afternoon?" is the late-day joke, not two hours)
                let isGreeting = r.needs == [.morning] || r.needs == [.afternoon] || r.needs == [.evening] || r.needs == [.lateDay]
                if isGreeting && greeted { continue }
                let hit = r.phrases.contains { r.prefix ? t.hasPrefix($0) : t.contains($0) }
                guard hit else { continue }
                if isGreeting { greeted = true }
                for n in r.needs where !out.contains(n) { out.append(n) }
            }
            if TownVoice.horseOwner.contains(text) { out.append(.horse) }
        }
        cache[text] = out
        return out
    }

    // MARK: What is true now

    static let townReach: Float = 160          // the speaker's town: folk living this near
    static func hourBand(_ f: Double, _ n: Need) -> Bool {
        switch n {
        case .morning: return f >= 0.95 || f < 0.2
        case .afternoon: return f >= 0.18 && f < 0.5
        case .evening: return f >= 0.42 && f < 0.75
        case .lateDay: return f >= 0.3 && f < 0.62
        case .dark: return f >= 0.5 && f < 0.97
        case .daylight: return f >= 0.97 || f < 0.52
        default: return true
        }
    }

    static func holds(_ n: Need, _ g: Game, _ m: Mob?) -> Bool {
        let f = g.dayFraction
        let at = m?.pos ?? g.player.pos
        func townsfolk(_ p: (Mob) -> Bool) -> Bool {
            g.mobs.mobs.contains { $0.health > 0 && $0.villager != nil && simd_distance_squared($0.pos, at) < townReach * townReach && p($0) }
        }
        switch n {
        case .morning, .afternoon, .evening, .lateDay, .dark, .daylight: return hourBand(f, n)
        case .clearSky: return g.weather.rain < 0.2 && g.weather.thunder < 0.2
        case .dry: return g.weather.rain < 0.2 || g.precipitation(Int(floor(at.x)), Int(floor(at.y)), Int(floor(at.z))) == 0
        case .warmLand:
            let x = Int(floor(at.x)), z = Int(floor(at.z))
            return g.world.gen.column(x, z).biome.info.temp >= 0.8
        case .hungry: return g.survival && g.hunger <= 14
        case .rode: return g.riding != nil || TownVoice.hasHorse(g)
        case .horse: return TownVoice.hasHorse(g)
        case .gunHeld: return Guns.index(g.held.item) != nil
        case .hat: return g.inventory.armor.count > 0 && !g.inventory.armor[0].isEmpty
        case .met:
            guard let met = m?.villager?.metDay else { return false }
            return met < Int(g.time / DAY_LENGTH)
        case .stranger:
            guard let met = m?.villager?.metDay else { return true }
            return met >= Int(g.time / DAY_LENGTH)
        case .deeds: return g.survival && (abs(Honour.value) >= 25 || Honour.log.contains { $0.day >= Int(g.time / DAY_LENGTH) - 3 })
        case .saloon: return townsfolk { $0.villager?.shopKind == .saloon }
        case .church: return townsfolk { $0.villager?.profession == "cleric" }
        case .bank: return townsfolk { $0.villager?.role == "banker" }
        case .doctor: return townsfolk { $0.villager?.shopKind == .doctor }
        case .jail: return townsfolk { $0.villager?.role == "sheriff" || $0.villager?.role == "deputy" }
        case .jailEmpty: return holds(.jail, g, m) && Jail.term == nil && TownLaw.state.prisoner == nil
        case .mine: return townsfolk { $0.villager?.role == "miner" }
        case .railway, .noRailway:
            guard let gen = g.world.gen as? WorldGen else { return n == .noRailway }
            let x = Int(floor(at.x)), z = Int(floor(at.z)), r = 260
            let near = !Railways.near(gen, x0: x - r, z0: z - r, x1: x + r, z1: z + r, wait: false).isEmpty
            return n == .railway ? near : !near
        case .water: return waterNear(g, at)
        case .never: return false
        case .above: return m.map { g.player.pos.y > $0.pos.y + 3 } ?? false
        case .window: return blockNear(g, g.player.pos, 2) { Blocks.key($0).contains("glass") }
        case .stairs: return blockNear(g, g.player.pos, 2) { Blocks.key($0).contains("stairs") || Blocks.key($0).contains("ladder") }
        case .grenade: return g.arms.slugs.contains { $0.kind == .grenade && $0.fromPlayer && simd_distance_squared($0.pos, at) < 14 * 14 }
        case .throwing: return (m?.brain?.throwT ?? 0) > 0
        case .trucks: return g.world.ships.list.contains { !$0.wrecked && simd_distance_squared($0.pos, at) < 60 * 60 }
        case .horses: return g.mobs.mobs.contains { $0.gaited && $0.health > 0 && simd_distance_squared($0.pos, at) < 40 * 40 }
        case .coolLand: return g.world.gen.column(Int(floor(at.x)), Int(floor(at.z))).biome.info.temp < 0.8
        case .notFrozen: return g.world.gen.column(Int(floor(at.x)), Int(floor(at.z))).biome.info.temp > 0.15
        case .inland: return !seaNear(g, at)
        case .armed: return Guns.index(g.held.item) != nil || g.inventory.main.slots.contains { !$0.isEmpty && Guns.index($0.item) != nil }
        case .wasJailed:
            return Jail.term != nil || Honour.log.contains { ["you served your time", "you paid your fine", "you broke out of jail", "you gave yourself up"].contains($0.why) }
        }
    }

    // Water near: a river, lake, swamp or sea within 128 blocks (the drawn columns, not loaded blocks).
    private static var waterMemo: [Int64: Bool] = [:]
    static func waterNear(_ g: Game, _ p: V3) -> Bool {
        let cx = Int(floor(p.x / 64)), cz = Int(floor(p.z / 64))
        let key = Int64(cx) &* 73856093 ^ Int64(cz)
        if let w = waterMemo[key] { return w }
        var wet = false
        search: for r in stride(from: 16, through: 128, by: 16) {
            for k in 0..<12 {
                let a = Float(k) / 12 * 2 * .pi
                let c = g.world.gen.column(Int(p.x + cosf(a) * Float(r)), Int(p.z + sinf(a) * Float(r)))
                if c.height < SEA || c.biome == .river || c.biome == .frozenRiver || c.biome == .swamp || c.biome.isOcean { wet = true; break search }
            }
        }
        if waterMemo.count > 512 { waterMemo.removeAll() }
        waterMemo[key] = wet
        return wet
    }

    // The sea near: an ocean column within 256 blocks.
    private static var seaMemo: [Int64: Bool] = [:]
    static func seaNear(_ g: Game, _ p: V3) -> Bool {
        let cx = Int(floor(p.x / 64)), cz = Int(floor(p.z / 64))
        let key = Int64(cx) &* 73856093 ^ Int64(cz)
        if let w = seaMemo[key] { return w }
        var sea = g.world.gen.column(Int(p.x), Int(p.z)).biome.isOcean
        search: for r in stride(from: 32, through: 256, by: 32) where !sea {
            for k in 0..<16 {
                let a = Float(k) / 16 * 2 * .pi
                if g.world.gen.column(Int(p.x + cosf(a) * Float(r)), Int(p.z + sinf(a) * Float(r))).biome.isOcean { sea = true; break search }
            }
        }
        if seaMemo.count > 512 { seaMemo.removeAll() }
        seaMemo[key] = sea
        return sea
    }

    static func blockNear(_ g: Game, _ p: V3, _ r: Int, _ test: (BlockID) -> Bool) -> Bool {
        let x0 = Int(floor(p.x)), y0 = Int(floor(p.y)), z0 = Int(floor(p.z))
        for dy in -1...2 { for dz in -r...r { for dx in -r...r {
            let b = g.world.block(x0 + dx, y0 + dy, z0 + dz)
            if b != AIR && test(b) { return true }
        } } }
        return false
    }

    // Whether the line is true to say now (speaker m, or none).
    static var on = true
    static func fits(_ g: Game?, _ m: Mob?, _ text: String) -> Bool {
        guard on, let g = g else { return true }
        for n in needs(text) where !holds(n, g, m) { return false }
        return true
    }
    // The first need that fails (for the check's report), or nil.
    static func failing(_ g: Game, _ m: Mob?, _ text: String) -> Need? { needs(text).first { !holds($0, g, m) } }

    // A line said straight from code: itself when true; its greeting put right when that is all that's wrong; else nil.
    static let greetings: [(String, Need)] = [("Good morning", .morning), ("Good afternoon", .afternoon), ("Good evening", .evening),
                                              ("Mornin'", .morning), ("Morning", .morning), ("Afternoon", .afternoon), ("Evening", .evening)]
    static func truthful(_ g: Game, _ m: Mob?, _ text: String) -> String? {
        guard on else { return text }
        let bad = needs(text).filter { !holds($0, g, m) }
        if bad.isEmpty { return text }
        guard bad.allSatisfy({ [.morning, .afternoon, .evening].contains($0) }),
              let word = greetings.first(where: { text.hasPrefix($0.0) })?.0 else { return nil }
        let f = g.dayFraction
        let now = hourBand(f, .morning) ? "Morning" : (hourBand(f, .afternoon) && f < 0.42 ? "Afternoon" : "Evening")
        return now + text.dropFirst(word.count)
    }
}
