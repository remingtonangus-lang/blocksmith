import Foundation
import simd

// Harness checks for the mob workstream (--mobtests): raid wave tables and a simulated raid,
// pathfinding scenarios and spawning rules. Prints one line per check and returns false if any failed
// (the snapshot run then exits non-zero so CI goes red).
enum MobTests {
    static var failures: [String] = []

    static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        let d = detail()
        print("mobtest \(ok ? "ok  " : "FAIL") \(name)\(d.isEmpty ? "" : ": " + d)")
        if !ok { failures.append(name) }
    }

    static func run(game: Game, world: World, pos: V3, rd: Int) -> Bool {
        failures = []
        let t0 = CFAbsoluteTimeGetCurrent()
        raidTables()
        raidSimulation(game: game, world: world, pos: pos)
        print(String(format: "mobtests: %ld failed (%.1f s)%@", failures.count, CFAbsoluteTimeGetCurrent() - t0,
                     failures.isEmpty ? "" : " -> " + failures.joined(separator: ", ")))
        game.player.pos = pos
        return failures.isEmpty
    }

    // MARK: Raids

    static func describe(_ c: [RaidTable.Member]) -> String {
        var n: [String: Int] = [:]
        for m in c { n[m.kind.key, default: 0] += 1; if let r = m.rider { n["\(r.key) rider", default: 0] += 1 } }
        return n.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
    }

    static func raidTables() {
        check(RaidTable.groupCount(1) == 3 && RaidTable.groupCount(2) == 5 && RaidTable.groupCount(3) == 7, "raid wave counts 3/5/7")
        // Normal with no random extras: the reference table exactly.
        let lows = (1...5).map { RaidTable.composition(wave: $0, groups: 5, difficulty: 2, bonusWave: false, roll: { _ in 0 }) }
        let totals = lows.map { c in c.count + c.filter { $0.rider != nil }.count }
        check(totals == [4, 5, 4, 8, 11], "raid normal wave sizes", "\(totals)")
        for (i, c) in lows.enumerated() {
            let caps = c.filter { $0.captain }
            check(caps.count == 1 && [.pillager, .vindicator, .evoker].contains(caps[0].kind), "raid wave \(i + 1) captain", describe(c))
        }
        check(lows[4].contains { $0.kind == .ravager && $0.rider == .pillager }, "raid normal wave 5 siegebeast rider", describe(lows[4]))
        check(!lows[2].contains { $0.rider != nil }, "raid wave 3 siegebeast unridden", describe(lows[2]))
        // Hard wave 7: two siegebeasts ridden by a conjurer and a brigand; max extras add 2 marauders + 2 brigands + 1 witch.
        let hard7 = RaidTable.composition(wave: 7, groups: 7, difficulty: 3, bonusWave: false, roll: { $0 - 1 })
        let riders = hard7.compactMap { $0.rider }
        check(riders == [.evoker, .vindicator], "raid hard wave 7 riders", describe(hard7))
        check(hard7.filter { $0.kind == .pillager }.count == 4 && hard7.filter { $0.kind == .vindicator }.count == 7
              && hard7.filter { $0.kind == .witch }.count == 2, "raid hard wave 7 extras", describe(hard7))
        // Easy never adds witches; the bonus wave reuses the last regular wave's table (+ a possible siegebeast off Easy).
        let easy = (1...3).flatMap { RaidTable.composition(wave: $0, groups: 3, difficulty: 1, bonusWave: false, roll: { $0 - 1 }) }
        check(!easy.contains { $0.kind == .witch }, "raid easy has no witches")
        let bonus = RaidTable.composition(wave: 6, groups: 5, difficulty: 2, bonusWave: true, roll: { $0 - 1 })
        check(bonus.filter { $0.kind == .ravager }.count == 2 && !bonus.contains { $0.rider != nil }, "raid normal bonus wave", describe(bonus))
        check(RaidTable.enchantOdds(1) == 0 && RaidTable.enchantOdds(5) == 0.75, "raid enchant odds")
    }

    // A small village next to the player; Ill Omen II; every raider dies a second after its wave spawns.
    // Expect Siege Omen, 6 waves (5 + bonus), victory and Village Hero II.
    static func raidSimulation(game: Game, world: World, pos: V3) {
        let x0 = Int(floor(pos.x)), z0 = Int(floor(pos.z))
        game.mobs.mobs.removeAll()
        game.raid = nil
        game.survival = true
        game.difficulty = 2
        game.paused = false
        game.player.flying = true
        game.time = 0.3 * DAY_LENGTH
        var villagers: [Mob] = []
        for i in 0..<6 {
            let x = x0 + (i % 3) * 2 - 2, z = z0 + (i / 3) * 2 + 3
            let v = Mob(.villager, at: V3(Float(x) + 0.5, Float(world.topY(x, z) + 1), Float(z) + 0.5))
            v.persistent = true
            villagers.append(v)
        }
        game.mobs.mobs += villagers
        game.applyEffect(.badOmen, amp: 1, seconds: 6000)
        var sawOmen = false, waves: [String] = [], lastWave = 0
        var spawnedAt: Float = -1
        var t: Float = 0
        let dt: Float = 0.05
        while t < 260 {
            game.tick(Double(dt))
            t += dt
            game.health = 20
            game.player.pos = pos
            game.player.vel = .zero
            for v in villagers { v.health = 20 }
            game.mobs.mobs.removeAll { $0.kind.hostile && !$0.raider && $0.kind != .vex }
            if game.effects.has(.raidOmen) { sawOmen = true }
            guard let r = game.raid else { if lastWave > 0 { break } else { continue } }
            if r.wave != lastWave {
                lastWave = r.wave
                spawnedAt = t
                var n: [String: Int] = [:]
                for m in r.raiders { n[m.kind.key + (m.captain ? "*" : ""), default: 0] += 1 }
                waves.append(n.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: " "))
            }
            if r.state == 1 && spawnedAt >= 0 && t - spawnedAt > 1 {
                for m in r.raiders { m.health = 0 }
                game.mobs.mobs.removeAll { $0.kind == .vex }
            }
            if r.state >= 2 { break }
        }
        let r = game.raid
        check(sawOmen, "raid ill omen -> siege omen")
        check(r != nil && r!.totalWaves == 6, "raid omen II has a bonus wave", "total \(r?.totalWaves ?? -1)")
        check(waves.count == 6, "raid waves spawned", "\(waves.count): " + waves.joined(separator: " | "))
        check(r?.state == 2, "raid victory", "state \(r?.state ?? -1) after \(Int(t)) s")
        check(game.effects.level(.heroOfTheVillage) == 2, "raid village hero II", "level \(game.effects.level(.heroOfTheVillage))")
        game.effects.remove(.heroOfTheVillage)
        game.raid = nil
        game.mobs.mobs.removeAll()
    }
}
