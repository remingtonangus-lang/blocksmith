import Foundation
import simd

// P478's lines sweep (questcheck --linetruth): every line the game has (the townsfolk's two books, the troops' book, the
// written lines for the hour) read for what it claims (LineTruth.needs); each claim checked both ways, in a state where it
// is true and one where it is not; and the line pickers asked many times under changing hours, weather and acquaintance,
// with every line they give checked true when said.
enum LineTruthCheck {
    typealias Need = LineTruth.Need

    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        // MARK: The population
        var rows: [(String, String)] = []
        for (_, _, ls) in TownVoice.script { for t in ls { rows.append(("townsfolk book 1", t)) } }
        for (_, _, ls) in TownVoice.script2 { for t in ls { rows.append(("townsfolk book 2", t)) } }
        for (_, _, ls) in TroopVoice.script { for t in ls { rows.append(("troops", t)) } }
        for (_, _, ls) in TownLines.table { for t in ls { rows.append(("written", t)) } }
        let texts = Set(rows.map { $0.1 })
        var byNeed: [Need: Int] = [:], tagged = 0
        var bySource: [String: (Int, Int)] = [:]
        for (src, t) in rows {
            let n = LineTruth.needs(t)
            var c = bySource[src] ?? (0, 0); c.0 += 1; if !n.isEmpty { c.1 += 1 }; bySource[src] = c
        }
        for t in texts {
            let n = LineTruth.needs(t)
            if !n.isEmpty { tagged += 1 }
            for x in n { byNeed[x, default: 0] += 1 }
        }
        print("linetruth: \(rows.count) lines (\(texts.count) different), \(tagged) make a claim that must be true when said")
        for (src, c) in bySource.sorted(by: { $0.key < $1.key }) { print("linetruth:   \(src): \(c.0) lines, \(c.1) with a claim") }
        print("linetruth:   by claim: " + Need.allCases.compactMap { (k: Need) -> String? in byNeed[k].map { "\(k.rawValue) \($0)" } }.joined(separator: ", "))
        if CommandLine.arguments.contains("--list") {
            for t in texts.sorted() where !LineTruth.needs(t).isEmpty { print("linetruth: [\(LineTruth.needs(t).map { $0.rawValue }.joined(separator: ","))] \(t)") }
        }
        check(rows.count >= 1900 && tagged >= 150, "lines: \(rows.count) read, \(tagged) different lines carry a claim")
        // Every claim the rules know is carried by at least one line (a rule that matches nothing is a typo).
        let unused = Need.allCases.filter { byNeed[$0] == nil }
        check(unused.isEmpty, "lines: every claim is made by some line (none: \(unused.map { $0.rawValue }))")

        // MARK: Each claim both ways
        let saved = (g.time, g.weather.rain, g.weather.thunder, g.survival, g.hunger, g.player.pos, g.inventory.main[g.inventory.selected],
                     g.inventory.armor[0], Honour.value)
        let mobs0 = g.mobs.mobs
        defer {
            (g.time, g.weather.rain, g.weather.thunder, g.survival, g.hunger) = (saved.0, saved.1, saved.2, saved.3, saved.4)
            g.player.pos = saved.5; g.inventory.main[g.inventory.selected] = saved.6; g.inventory.armor[0] = saved.7; Honour.value = saved.8
            g.mobs.mobs = mobs0; g.mobs.rebuildIndex()
        }
        let home = g.player.pos
        g.mobs.mobs.removeAll { $0.villager != nil || $0.gaited }
        let speaker = TownTests.keeper(g, .general, at: home + V3(2, 0, 0))
        g.mobs.mobs.append(speaker)
        let day = 5.0
        func at(_ f: Double) { g.time = (day + f) * DAY_LENGTH }
        func neighbour(_ kind: ShopKind, _ setup: (Mob) -> Void) -> Mob {
            let n = TownTests.keeper(g, kind, at: home + V3(-3, 0, 2)); setup(n); g.mobs.mobs.append(n); return n
        }
        func both(_ n: Need, _ yes: () -> Void, _ no: () -> Void, undo: () -> Void = {}) -> (Bool, Bool) {
            yes(); let a = LineTruth.holds(n, g, speaker); undo()
            no(); let b = LineTruth.holds(n, g, speaker); undo()
            return (a, b)
        }
        var results: [(Need, Bool, Bool)] = []
        func record(_ n: Need, _ r: (Bool, Bool)) { results.append((n, r.0, r.1)) }
        at(0.3)
        record(.morning, both(.morning, { at(0.08) }, { at(0.6) }))
        record(.afternoon, both(.afternoon, { at(0.3) }, { at(0.05) }))
        record(.evening, both(.evening, { at(0.55) }, { at(0.25) }))
        record(.lateDay, both(.lateDay, { at(0.45) }, { at(0.1) }))
        record(.dark, both(.dark, { at(0.75) }, { at(0.25) }))
        record(.daylight, both(.daylight, { at(0.25) }, { at(0.75) }))
        g.weather.thunder = 0
        record(.clearSky, both(.clearSky, { g.weather.rain = 0 }, { g.weather.rain = 1 }))
        // Country of each kind: the first of each along a line east from here (hot, frozen, rained on, never rained on, sea).
        var warm: V3?, cold: V3?, rains: V3?, desert: V3?, sea: V3?
        for k in 0..<4000 where warm == nil || cold == nil || rains == nil || desert == nil || sea == nil {
            let x = Int(home.x) + k * 64, z = Int(home.z) + (k % 7) * 512
            let c = g.world.gen.column(x, z), t = c.biome.info.temp
            let p = V3(Float(x), Float(max(c.height, SEA) + 2), Float(z))
            if t >= 1.2 && warm == nil { warm = p } else if t <= 0.1 && cold == nil { cold = p }
            let fall = g.precipitation(x, Int(p.y), z)
            if fall == 1 && rains == nil && !c.biome.isOcean { rains = p }
            if fall == 0 && desert == nil { desert = p }
            if c.biome.isOcean && sea == nil { sea = p }
        }
        let back = { speaker.pos = home + V3(2, 0, 0) }
        if let w = rains, let d = desert {
            speaker.pos = w
            record(.dry, both(.dry, { g.weather.rain = 0 }, { g.weather.rain = 1 }))
            // ... and over a desert in the same storm: nothing falls there, so it is dry, and no rain talk.
            g.weather.rain = 1; g.weather.thunder = 1
            let wetTalk = TownLines.situation(g, speaker).soft.contains("storm")
            speaker.pos = d
            let desertDry = LineTruth.holds(.dry, g, speaker), desertTalk = TownLines.situation(g, speaker).soft.contains { $0 == "rain" || $0 == "storm" }
            g.weather.rain = 0; g.weather.thunder = 0; back()
            check(wetTalk && desertDry && !desertTalk, "lines: in a storm, rain talk where it rains (\(wetTalk)) and none over the desert, where it's dry (\(desertDry), \(!desertTalk))")
        } else { check(false, "lines: found rained-on and rainless country to test the weather lines") }
        g.weather.rain = 0
        if let w = warm, let c = cold {
            record(.warmLand, both(.warmLand, { speaker.pos = w }, { speaker.pos = c }, undo: back))
            record(.coolLand, both(.coolLand, { speaker.pos = c }, { speaker.pos = w }, undo: back))
            record(.notFrozen, both(.notFrozen, { speaker.pos = w }, { speaker.pos = c }, undo: back))
        } else { check(false, "lines: found warm and cold country to test heat claims") }
        if let s = sea {
            var far: V3?
            for k in 1..<400 where far == nil {
                let p = V3(s.x + Float(k * 211), s.y, s.z + Float((k % 5) * 400))
                if !LineTruth.seaNear(g, p) { far = p }
            }
            if let f = far { record(.inland, both(.inland, { speaker.pos = f }, { speaker.pos = s }, undo: back)) }
            else { check(false, "lines: found country far from the sea") }
        } else { check(false, "lines: found the sea to test the sea lines") }
        g.survival = true
        record(.hungry, both(.hungry, { g.hunger = 8 }, { g.hunger = 20 }))
        g.hunger = 20
        let horse = Mob(.horse, at: home + V3(4, 0, 0)); horse.owner = true
        record(.horse, both(.horse, { g.mobs.mobs.append(horse) }, {}, undo: { g.mobs.mobs.removeAll { $0 === horse } }))
        record(.rode, both(.rode, { g.mobs.mobs.append(horse) }, {}, undo: { g.mobs.mobs.removeAll { $0 === horse } }))
        let gun = Items.creativeList.first { Guns.index($0) != nil }
        record(.gunHeld, both(.gunHeld, { g.inventory.main[g.inventory.selected] = ItemStack(gun ?? 0, 1) },
                              { g.inventory.main[g.inventory.selected] = .empty }))
        let pack = g.inventory.main.slots
        record(.armed, both(.armed, { g.inventory.main[(g.inventory.selected + 3) % g.inventory.main.count] = ItemStack(gun ?? 0, 1) },
                            { for i in 0..<g.inventory.main.count { g.inventory.main[i] = .empty } }, undo: { g.inventory.main.slots = pack }))
        let hlog = TownLaw.state.honourLog
        record(.wasJailed, both(.wasJailed, { TownLaw.state.honourLog = ["3|2|you served your time"] }, { TownLaw.state.honourLog = nil },
                                undo: { TownLaw.state.honourLog = hlog }))
        record(.hat, both(.hat, { g.inventory.armor[0] = ItemStack(Items.id("iron_helmet"), 1) }, { g.inventory.armor[0] = .empty }))
        let today = Int(g.time / DAY_LENGTH)
        record(.met, both(.met, { speaker.villager?.metDay = today - 2 }, { speaker.villager?.metDay = nil }))
        record(.stranger, both(.stranger, { speaker.villager?.metDay = nil }, { speaker.villager?.metDay = today - 2 }))
        speaker.villager?.metDay = nil
        record(.deeds, both(.deeds, { Honour.value = 60 }, { g.survival = false }, undo: { g.survival = true; Honour.value = saved.8 }))
        // The town's buildings: a neighbour who keeps one, or nobody.
        func place(_ n: Need, _ kind: ShopKind = .general, _ setup: @escaping (Mob) -> Void = { _ in }) {
            var nb: Mob?
            record(n, both(n, { nb = neighbour(kind, setup) }, {}, undo: { if let x = nb { g.mobs.mobs.removeAll { $0 === x } }; nb = nil }))
        }
        place(.saloon, .saloon)
        place(.church) { $0.villager?.profession = "cleric" }
        place(.bank) { $0.villager?.role = "banker" }
        place(.doctor, .doctor)
        place(.jail) { $0.villager?.role = "sheriff" }
        place(.jailEmpty) { $0.villager?.role = "sheriff" }
        place(.mine) { $0.villager?.role = "miner" }
        record(.never, (true, LineTruth.holds(.never, g, speaker)))       // (no state makes these true: they are never said)
        // A railway and the open land: by a line's middle, and its opposite answer there.
        if let gen = g.world.gen as? WorldGen,
           let l = Railways.near(gen, x0: Int(home.x) - 3000, z0: Int(home.z) - 3000, x1: Int(home.x) + 3000, z1: Int(home.z) + 3000).first {
            let mid = V3(Float((l.minX + l.maxX) / 2), home.y, Float((l.minZ + l.maxZ) / 2))
            record(.railway, both(.railway, { speaker.pos = mid }, { speaker.pos = V3(mid.x + 9000, mid.y, mid.z + 9000) }, undo: { speaker.pos = home + V3(2, 0, 0) }))
            speaker.pos = mid
            let a = LineTruth.holds(.railway, g, speaker) != LineTruth.holds(.noRailway, g, speaker)
            speaker.pos = home + V3(2, 0, 0)
            record(.noRailway, (a, false))
        } else { check(false, "lines: a railway within 3,000 blocks to test the train lines") }
        var wet: V3?, dry: V3?
        for k in 0..<3000 where wet == nil || dry == nil {
            let p = V3(home.x + Float(k * 97), home.y, home.z - Float((k % 11) * 300))
            if LineTruth.waterNear(g, p) { if wet == nil { wet = p } } else if dry == nil { dry = p }
        }
        if let a = wet, let b = dry { record(.water, both(.water, { speaker.pos = a }, { speaker.pos = b }, undo: { speaker.pos = home + V3(2, 0, 0) })) }
        else { check(false, "lines: found wet and dry country to test the creek and river lines") }
        // A fight's claims: where he is, his grenade, horses near.
        let high = V3(home.x + 0.5, Float(CH - 30), home.z + 0.5)
        g.player.pos = high; speaker.pos = high + V3(3, 0, 0)
        record(.above, both(.above, { speaker.pos = high + V3(3, -6, 0) }, { speaker.pos = high + V3(3, 0, 0) }))
        let wx = Int(high.x) + 1, wy = Int(high.y), wz = Int(high.z)
        record(.window, both(.window, { g.world.setBlock(wx, wy, wz, Blocks.id("glass")) }, {}, undo: { g.world.setBlock(wx, wy, wz, AIR) }))
        record(.stairs, both(.stairs, { g.world.setBlock(wx, wy, wz, Blocks.id("nether_brick_stairs")) }, {}, undo: { g.world.setBlock(wx, wy, wz, AIR) }))
        let n0 = g.arms.slugs.count
        let nade = Slug(pos: speaker.pos + V3(2, 0, 0), vel: .zero, kind: .grenade, damage: 0, fromPlayer: true, shooter: nil, by: "test", life: 2, gravity: 20)
        record(.grenade, both(.grenade, { g.arms.slugs.append(nade) }, {}, undo: { if g.arms.slugs.count > n0 { g.arms.slugs.removeLast(g.arms.slugs.count - n0) } }))
        record(.throwing, (true, LineTruth.holds(.throwing, g, speaker)))           // (a townsperson never throws one)
        record(.trucks, (true, LineTruth.holds(.trucks, g, speaker)))              // (none up here; ships near: World.ships)
        let mare = Mob(.horse, at: speaker.pos + V3(5, 0, 0))
        record(.horses, both(.horses, { g.mobs.mobs.append(mare) }, {}, undo: { g.mobs.mobs.removeAll { $0 === mare } }))
        g.player.pos = home; speaker.pos = home + V3(2, 0, 0)
        let bad = results.filter { !$0.1 || $0.2 }
        let tested = Set(results.map { $0.0 })
        let untested = Need.allCases.filter { !tested.contains($0) }
        check(bad.isEmpty && untested.isEmpty,
              "lines: each of \(results.count) claims true where it holds and false where it doesn't (wrong: \(bad.map { "\($0.0.rawValue) \($0.1)/\($0.2)" }), untested: \(untested.map { $0.rawValue }))")

        // MARK: The pickers under changing hours, weather and acquaintance
        var said = 0, untrue: [String] = []
        let voices: [(ShopKind, (Mob) -> Void)] = [(.general, { _ in }), (.saloon, { _ in }), (.general, { $0.villager?.role = "farmer" }),
                                                   (.general, { $0.villager?.role = "elder" }), (.general, { $0.villager?.role = "deputy" }),
                                                   (.general, { $0.villager?.role = "sheriff" })]
        for (vi, (kind, setup)) in voices.enumerated() {
            let m = TownTests.keeper(g, kind, at: home + V3(2, 0, Float(vi))); setup(m); g.mobs.mobs.append(m)
            for k in 0..<240 {
                at(Double(k % 24) / 24)
                g.weather.rain = k % 5 == 0 ? 1 : 0
                m.villager?.metDay = k % 3 == 0 ? nil : Int(g.time / DAY_LENGTH) - (k % 2)
                g.hunger = k % 4 == 0 ? 6 : 20
                for ctx in [TownVoice.Ctx.greet, .chatter, .night, .bye] {
                    guard let picked = TownVoice.line(ctx, m, game: g) else { continue }
                    let t = picked.0
                    said += 1
                    if let n = LineTruth.failing(g, m, t) { untrue.append("\(n.rawValue): \(t)") }
                }
            }
            g.mobs.mobs.removeAll { $0 === m }
        }
        check(said > 3000 && untrue.isEmpty, "lines: \(said) lines picked over every hour, rain and shine, met and not: \(untrue.count) untrue \(untrue.prefix(4))")
        // Lines said straight from code: a greeting for the wrong hour is put right; another untrue line is not said.
        at(0.55)
        let mended = LineTruth.truthful(g, speaker, "Afternoon, Rem. This here six-iron stays holstered for folks like you.")
        at(0.1)
        let morning = LineTruth.truthful(g, speaker, "Evening, Rem. Stay safe out there.")
        speaker.villager?.metDay = nil
        let dropped = LineTruth.truthful(g, speaker, "Good to see you again, Rem.")
        check(mended?.hasPrefix("Evening, Rem.") == true && morning?.hasPrefix("Morning, Rem.") == true && dropped == nil,
              "lines from code: \"Afternoon\" at dusk says \(mended ?? "nothing"), \"Evening\" at dawn says \(morning ?? "nothing"), \"again\" to a stranger says \(dropped ?? "nothing")")
    }
}
