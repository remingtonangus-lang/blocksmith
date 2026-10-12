import Foundation
import simd

// Townsfolk variety (TownStats.swift; docs/status/townsfolk-variety.md). Run by TownTests.run.
//   roles:    across 300 people per role, farmers are weaker and slower than workers, elders the slowest and frailest
//             adults, blacksmiths the strongest and toughest, deputies the fastest.
//   people:   the same person always rolls the same; two workers differ (spread across 300 of them); a child growing
//             up re-rolls.
//   in play:  the same 12-point blow takes more off an elder than a blacksmith; a blacksmith's hammer hits harder than
//             a farmer's pitchfork swing for swing (strength) and swings no faster than a deputy's sword (rate); a
//             walking deputy outpaces a walking elder in real Mob.update frames.
//   cues:     a blacksmith's model is broader than an elder's; the crosshair line names the person, the trade and what
//             a glance tells you ("strong", "frail", "quick"...), only in town, and only for the person you look at.
extension TownTests {
    static func variety(_ g: Game, _ check: (Bool, String) -> Void) {
        let savedMobs = g.mobs.mobs, savedPos = g.player.pos, savedSurvival = g.survival, savedYaw = g.player.yaw, savedPitch = g.player.pitch
        defer {
            g.mobs.mobs = savedMobs; g.player.pos = savedPos; g.survival = savedSurvival; g.player.yaw = savedYaw; g.player.pitch = savedPitch
            TownLaw.forceTown = nil; TownLaw.reset()
        }
        let base = groundSpot(g)
        func person(_ tag: String, _ i: Int) -> Mob {
            let m = Mob(.villager, at: base + V3(Float(i % 17) * 1.3, 0, Float(i / 17) * 1.1)); m.home = m.pos
            if tag == "farmer" { var v = VillagerData(); v.profession = "farmer"; m.villager = v }
            if tag == "elder" { var v = VillagerData(); v.role = "elder"; m.villager = v }
            Townsfolk.setup(m, tag: ["farmer", "elder", "worker"].contains(tag) ? "" : tag, game: g)
            if tag == "worker", var v = m.villager { v.role = "worker"; m.villager = v }
            return m
        }
        func mean(_ tag: String, _ f: (TownStats) -> Float) -> (Float, Float, Float) {
            let xs = (0..<300).map { f(person(tag, $0).townStats) }
            return (xs.reduce(0, +) / Float(xs.count), xs.min() ?? 0, xs.max() ?? 0)
        }
        let farmer = person("farmer", 1), elder = person("elder", 2)
        check(farmer.villager?.role == "farmer" && elder.villager?.role == "elder", "variety: test people (\(farmer.villager?.role ?? "?"), \(elder.villager?.role ?? "?"))")
        let ws = mean("worker") { $0.speed }, fs = mean("farmer") { $0.speed }, es = mean("elder") { $0.speed }, ds = mean("deputy") { $0.speed }
        let wst = mean("worker") { $0.strength }, fst = mean("farmer") { $0.strength }, bst = mean("shop_blacksmith") { $0.strength }
        let et = mean("elder") { $0.toughness }, bt = mean("shop_blacksmith") { $0.toughness }, wt = mean("worker") { $0.toughness }
        check(fs.0 < ws.0 && fst.0 < wst.0, String(format: "variety: farmers are slower (x%.2f) and weaker (x%.2f) than workers (x%.2f, x%.2f)", fs.0, fst.0, ws.0, wst.0))
        check(es.0 < fs.0 && et.0 < wt.0, String(format: "variety: elders are the slowest (x%.2f) and frailest (x%.2f) adults", es.0, et.0))
        check(bst.0 > 1.35 && bt.0 > 1.3, String(format: "variety: blacksmiths are strong (x%.2f) and tough (x%.2f)", bst.0, bt.0))
        check(ds.0 > 1.2 && ds.1 > ws.0, String(format: "variety: deputies are fast (x%.2f, the slowest x%.2f beats the average worker)", ds.0, ds.1))
        check(ws.2 - ws.1 > 0.15 && wst.2 - wst.1 > 0.15, String(format: "variety: workers differ person to person (speed x%.2f-%.2f, strength x%.2f-%.2f)", ws.1, ws.2, wst.1, wst.2))
        let a = person("worker", 5), b = person("worker", 5)
        check(a.townStats == b.townStats, "variety: the same person always rolls the same")
        let kid = person("worker", 9); kid.baby = true
        if var v = kid.villager { v.role = "child"; kid.villager = v }
        let kidStats = kid.townStats
        kid.baby = false
        if var v = kid.villager { v.role = "worker"; kid.villager = v }
        check(kidStats.strength < 0.4 && kid.townStats.strength > 0.8, String(format: "variety: a child grows up and re-rolls (strength x%.2f -> x%.2f)", kidStats.strength, kid.townStats.strength))
        // In play: the same blow.
        let smith = person("shop_blacksmith", 20)
        var elderLeft = 0, smithLeft = 0
        for _ in 0..<40 {
            elder.health = 20; smith.health = 20; elder.invulnerable = 0; smith.invulnerable = 0
            elder.hit(from: base, damage: 12, knockback: 0); smith.hit(from: base, damage: 12, knockback: 0)
            elderLeft += elder.health; smithLeft += smith.health
        }
        check(elderLeft < smithLeft - 40 * 3, "variety: a 12-point blow leaves an elder \(elderLeft / 40), a blacksmith \(smithLeft / 40) of 20")
        // Their blows: the blacksmith's hammer against the farmer's pitchfork.
        TownLaw.reset(); TownLaw.forceTown = true; g.survival = true
        let target = Mob(.zombie, at: base + V3(1.5, 0, 0))
        func blow(_ m: Mob) -> (Int, Float) {
            target.health = 20; target.invulnerable = 0; m.pos = base; m.attackCooldown = 0
            m.town.foe = target; m.town.think = 1
            _ = m.townDefend(0.05, g)
            return (20 - target.health, m.attackCooldown)
        }
        g.mobs.mobs = [target]
        let sb = blow(smith), fb = blow(farmer)
        let dep = person("deputy", 30), db = blow(dep)
        // (P64: deputies carry six-irons now, so their pace is the gun's, not a sword's.)
        check(sb.0 > fb.0 && dep.townWeapon == .revolver, "variety: a blacksmith's hammer hits for \(sb.0), a farmer's pitchfork \(fb.0); the deputy draws a six-iron (every \(String(format: "%.2f", db.1)) s)")
        // Walking pace in real frames.
        let quick = person("deputy", 40), slow = person("elder", 41)
        if var v = slow.villager { v.role = "elder"; slow.villager = v }
        g.mobs.mobs = [quick, slow]
        for m in [quick, slow] { m.pos = base; m.home = base + V3(30, 0, 0); m.wanderGoal = base + V3(30, 0, 0); m.moving = true; m.aiTimer = 10 }
        var qd: Float = 0, sd: Float = 0
        let q0 = quick.pos, s0 = slow.pos
        for _ in 0..<40 {
            for m in [quick, slow] { m.wanderGoal = base + V3(30, 0, 0); m.moving = true; m.aiTimer = 10; m.update(0.05, game: g) }
        }
        qd = simd_length(V2(quick.pos.x - q0.x, quick.pos.z - q0.z)); sd = simd_length(V2(slow.pos.x - s0.x, slow.pos.z - s0.z))
        check(qd > sd * 1.3, String(format: "variety: in 2 s a deputy walks %.1f blocks, an elder %.1f", qd, sd))
        // Cues: build and the crosshair line.
        func width(_ m: Mob) -> Float {
            // The torso (13 to 23.5 px up): the shirt box every townsperson has.
            let torso = townsfolkParts(m, swing: 0).filter { abs($0.mn.y - 13) < 0.01 && abs($0.mx.y - 23.5) < 0.01 }
            return torso.map { $0.mx.x - $0.mn.x }.max() ?? 0
        }
        check(width(smith) > width(elder) + 0.6, String(format: "variety: a blacksmith is built broader (%.1f px) than an elder (%.1f px)", width(smith), width(elder)))
        let line = TownStatsHUD.describe(smith)
        check(line.hasPrefix(smith.villager?.person ?? "?") && line.contains("blacksmith") && line.contains("strong"), "variety: the crosshair line reads \"\(line)\"")
        g.mobs.mobs = [smith]
        g.player.pos = smith.pos + V3(0, 0, 4)
        let to = simd_normalize(smith.pos + V3(0, 1.2, 0) - g.player.eye)
        g.player.yaw = atan2f(-to.x, -to.z); g.player.pitch = asinf(to.y)
        let seen = TownStatsHUD.lookedAt(g)
        TownStatsHUD.aimed = nil; TownStatsHUD.shown = nil
        let t0 = g.clock
        let first = TownStatsHUD.current(g, now: t0)
        let settled = TownStatsHUD.current(g, now: t0 + TownStatsHUD.settle + 0.05)
        g.player.yaw += 1.2
        let away = TownStatsHUD.lookedAt(g)
        let lingering = TownStatsHUD.current(g, now: t0 + TownStatsHUD.settle + 0.25)
        let gone = TownStatsHUD.current(g, now: t0 + TownStatsHUD.settle + 0.25 + TownStatsHUD.hold + 0.05)
        check(seen === smith && away == nil && first == nil && settled === smith && lingering === smith && gone == nil,
              "variety: the line shows for the person you hold your aim on (\(seen?.villager?.person ?? "nobody"), after \(TownStatsHUD.settle) s), lingers \(TownStatsHUD.hold) s, not when you look away")
        // Farmers read weak or slow at a glance; a mason who takes up a lectern re-rolls as a librarian.
        let readable = (0..<100).filter { i in let t = person("farmer", 200 + i).townStats.traits; return t.contains("weak") || t.contains("slow") }.count
        check(readable >= 85, "variety: \(readable)/100 farmers read weak or slow at a glance")
        let mason = person("worker", 300)
        if var v = mason.villager { v.role = "craftsman"; v.profession = "mason"; mason.villager = v }
        let asMason = mason.townStats
        if var v = mason.villager { v.profession = "librarian"; mason.villager = v }
        check(asMason.strength > mason.townStats.strength + 0.2 && TownStatsHUD.describe(mason).contains("librarian"),
              String(format: "variety: a mason who becomes a librarian re-rolls (strength x%.2f -> x%.2f)", asMason.strength, mason.townStats.strength))
    }
}
