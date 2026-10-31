import Foundation
import simd

// Combat balance (Q2, scorecard "Balance: TTK tables in range"; `questcheck --balance-only`, and part of every
// questcheck run). Real duels through Game.tick on a walled stone floor high over the ground, at night, Normal:
//   tiers     early (no armour, stone sword), iron (iron set, iron sword), diamond (diamond set, diamond sword)
//   one way   the mob on the player, who stands still (health topped up each tick): seconds until it has dealt 20
//   other way the player on the mob, held two and a half blocks off (it still turns and fights): full-charge swings
//             at its middle, the real attack path; seconds until it dies
// Designed ranges (docs/status/balance.md, written by `--balance-only --write-balance`):
//   fair       with iron gear the five common night mobs (zombie, husk, drowned, skeleton, spider) take at least 4 s
//              to kill the player and nothing takes under 2 s (a Brigand's axe is the reference's: about 3 s); at the
//              early tier the five take at least 2 s
//   winnable   at the early tier the player beats each of the five common night mobs one on one (the Gravesworn
//              Duellist, a knight since P246, at the iron tier); with diamond gear every mob in the table that can win
//              (a draw, neither killing in 60 s, is no loss)
//   no trivia  even a diamond sword needs more than one swing on every mob
//   gear pays  every tier up kills each mob at least as fast and survives at least as long
//   hisser     a blast at arm's length takes at least half an unarmoured player's health; diamond armour survives it
//              (at Normal a point-blank blast can kill a player in iron, as in the reference)
enum BalanceTests {
    struct Row { let name: String; var toKill: [Float?]; var kills: [Float?] }
    static let tiers: [(String, [String], String)] = [
        ("early", [], "stone_sword"),
        ("iron", ["iron_helmet", "iron_chestplate", "iron_leggings", "iron_boots"], "iron_sword"),
        ("diamond", ["diamond_helmet", "diamond_chestplate", "diamond_leggings", "diamond_boots"], "diamond_sword"),
    ]
    static let common = Set([MobKind.zombie, .husk, .drowned, .skeleton, .spider].map { $0.spec.name })

    static func run(game g: Game, check: (Bool, String) -> Void) {
        let w = g.world
        let pos0 = g.player.pos, yaw0 = g.player.yaw, pitch0 = g.player.pitch, surv0 = g.survival, fly0 = g.player.flying
        let time0 = g.time, diff0 = g.difficulty, health0 = g.health, mobs0 = g.mobs.mobs
        let armour0 = g.inventory.armor.slots, main0 = g.inventory.main.slots, sel0 = g.inventory.selected
        let enc0 = w.ships.encounters, menu0 = g.menu, weather0 = g.weather
        var placed: [IVec3] = []
        let fx = Int(floor(pos0.x)), fz = Int(floor(pos0.z))
        let py = min(CH - 30, w.topY(fx, fz) + 24)
        defer {
            for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }
            g.mobs.mobs = mobs0; w.pendingMobs.removeAll(); g.arms.slugs.removeAll()
            g.player.pos = pos0; g.player.yaw = yaw0; g.player.pitch = pitch0; g.player.vel = .zero
            g.survival = surv0; g.player.flying = fly0; g.time = time0; g.difficulty = diff0
            g.health = health0; g.alive = true; g.menu = nil
            g.inventory.armor.slots = armour0; g.inventory.main.slots = main0; g.inventory.selected = sel0
            w.ships.encounters = enc0; g.menu = menu0; g.weather = weather0
        }
        w.ships.encounters = false
        // (whatever an earlier check left: paused, a headset's head and aim, a saddle, a helm)
        let paused0 = g.paused, head0 = g.vrHead, aim0 = g.vrAim
        defer { g.paused = paused0; g.vrHead = head0; g.vrAim = aim0 }
        g.paused = false; g.vrHead = nil; g.vrAim = nil; g.riding = nil
        w.ships.pilot = nil; w.ships.aboard = nil
        g.survival = true; g.player.flying = false; g.difficulty = 2
        g.time = DAY_LENGTH * 0.75                                   // midnight: nothing burns
        _ = w.loadSync(center: V3(Float(fx), Float(py), Float(fz)), radius: 3)
        // A 33 x 33 stone floor (room for archers to back off and strafe) walled three high, open to the sky; built again before every duel (a hisser's blast
        // left a crater the next one fell through, and it died of the fall before it could blow).
        func arena() {
            for z in (fz - 16)...(fz + 16) { for x in (fx - 16)...(fx + 16) { for y in (py - 1)...(py + 6) {
                let edge = x == fx - 16 || x == fx + 16 || z == fz - 16 || z == fz + 16
                let want = y <= py || (edge && y <= py + 3) ? STONE : AIR
                if w.block(x, y, z) != want { w.setBlock(x, y, z, want) }
            } } }
            g.drops.items.removeAll()
        }
        for z in (fz - 16)...(fz + 16) { for x in (fx - 16)...(fx + 16) { for y in (py - 1)...(py + 6) { placed.append(IVec3(x, y, z)) } } }
        arena()
        let spot = V3(Float(fx) + 0.5, Float(py + 1), Float(fz) + 0.5)

        func gear(_ t: Int) {
            for i in 0..<4 { g.inventory.armor[i] = i < tiers[t].1.count ? ItemStack(Items.id(tiers[t].1[i]), 1) : .empty }
            g.inventory.selected = 0
            g.inventory.main[0] = ItemStack(Items.id(tiers[t].2), 1)
        }
        func place(_ k: MobKind, _ d: Float) -> Mob {
            g.mobs.mobs.removeAll(); w.pendingMobs.removeAll(); g.arms.slugs.removeAll()
            arena()
            let m = Mob(k, at: spot + V3(0, 0, -d))
            m.aggro = true
            if Soldier.rank(k) != nil { m.soldierBrain.lastSeen = g.player.eye; m.soldierBrain.seenAgo = 0 }
            g.mobs.mobs = [m]
            g.player.pos = spot; g.player.vel = .zero; g.health = 20; g.alive = true
            g.time = DAY_LENGTH * 0.75          // midnight for every duel (the clock ran on into day: skeletons burned)
            // Clear skies (in the full run it could be raining, and a voidwalker in rain only teleports about).
            g.weather.raining = false; g.weather.thundering = false; g.weather.rain = 0; g.weather.thunder = 0; g.weather.rainTime = 9000; g.weather.thunderTime = 9000
            g.menu = nil; for e in Effect.allCases { g.effects.remove(e) }      // (a witch's poison or a cave spider's carries over)
            return m
        }
        func face(_ m: Mob) {
            let d = m.pos + V3(0, min(m.height * 0.5, 1.5), 0) - g.player.eye
            g.player.yaw = atan2f(-d.x, -d.z)
            g.player.pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
        }
        let trace = ProcessInfo.processInfo.environment["BALANCE_TRACE"]
        // The mob on the player.
        func toKill(_ k: MobKind, _ t: Int, limit: Float = 60) -> Float? {
            gear(t)
            let m = place(k, 5)
            var dealt = 0, s: Float = 0
            while s < limit && m.health > 0 {
                g.health = 20; g.hunger = 20; g.saturation = 5
                g.player.pos = spot; g.player.vel = .zero
                face(m)
                let shots0 = g.projectiles.arrows.count
                g.tick(0.05); s += 0.05
                dealt += max(0, 20 - g.health)
                if trace == k.key && (Int(s * 20) % 20 == 0 || g.projectiles.arrows.count > shots0) {
                    let a = g.projectiles.arrows.last
                    print(String(format: "trace %.2f s: mob %.1f,%.1f,%.1f dist %.1f cd %.2f arrows %d (last at %.1f,%.1f,%.1f v %.1f,%.1f,%.1f) dealt %d", s, m.pos.x - spot.x, m.pos.y - spot.y, m.pos.z - spot.z, simd_length(m.pos - g.player.pos), m.attackCooldown, g.projectiles.arrows.count, (a?.pos.x ?? 0) - spot.x, (a?.pos.y ?? 0) - spot.y, (a?.pos.z ?? 0) - spot.z, a?.vel.x ?? 0, a?.vel.y ?? 0, a?.vel.z ?? 0, dealt))
                }
                if !g.alive { g.alive = true; g.health = 20; g.menu = nil; dealt += 20 }
                if dealt >= 20 { return s }
            }
            return nil
        }
        // The player on the mob.
        func kills(_ k: MobKind, _ t: Int, limit: Float = 60) -> Float? {
            gear(t)
            let m = place(k, 2.5)
            let hold = m.pos
            let swing = 1 / max(0.5, Items.def(Items.id(tiers[t].2)).attackSpeed)
            var s: Float = 0, next: Float = swing
            while s < limit && m.health > 0 {
                g.health = 20; g.hunger = 20
                g.player.pos = spot; g.player.vel = .zero
                face(m)
                if s >= next { g.input.leftClicked = true; next = s + swing }
                g.tick(0.05); s += 0.05
                g.input.leftClicked = false
                if m.health > 0 { m.pos.x = hold.x; m.pos.z = hold.z; m.vel.x = 0; m.vel.z = 0 }
                g.mobs.mobs.removeAll { $0 !== m }; w.pendingMobs.removeAll()
                if !g.alive { g.alive = true; g.health = 20; g.menu = nil }
            }
            return m.health <= 0 ? s : nil
        }
        // One hisser blast at arm's length: the damage it did (20 or more = dead).
        func blast(_ t: Int) -> Int {
            gear(t)
            let m = place(.creeper, 1.5)
            var s: Float = 0, dealt = 0
            while s < 10 && dealt == 0 && g.mobs.mobs.contains(where: { $0 === m }) {
                g.health = 20
                g.player.pos = spot; g.player.vel = .zero; face(m)
                g.tick(0.05); s += 0.05
                dealt = g.alive ? 20 - g.health : 20
                if !g.alive { g.alive = true; g.health = 20; g.menu = nil }
            }
            return dealt
        }

        let roster: [MobKind] = [.zombie, .husk, .drowned, .skeleton, .stray, .spider, .caveSpider, .witch, .enderman,
                                 .vindicator, .pillager, .soldierRecruit]
        var rows: [Row] = []
        let only = ProcessInfo.processInfo.environment["BALANCE_KINDS"].map { Set($0.split(separator: ",").map(String.init)) }
        for k in roster where only?.contains(k.key) ?? true {
            var r = Row(name: k.spec.name, toKill: [], kills: [])
            for t in 0..<tiers.count {
                // Three seeded duels the mob's way, averaged (hit luck and a witch's potion pick swung one duel by 2x).
                var runs: [Float?] = []
                for n in 0..<3 {
                    Rand.seed(0xBA1A_5000 + UInt64(k.rawValue) * 16 + UInt64(t) + UInt64(n) * 0x1000)
                    runs.append(toKill(k, t))
                }
                r.toKill.append(runs.contains { $0 == nil } ? nil : runs.compactMap { $0 }.reduce(0, +) / 3)
                // (P499: a Gravesworn's guard and feints made one duel's kill time the luck of when its guard dropped:
                // the same build's diamond time went 7.2 s to 9.2 s with what ran before. Three seeds averaged still swung
                // it 6.8 s to 8.9 s against iron: five seeds, the middle one.)
                let guardedKind = k.spec.name.hasPrefix("Gravesworn")
                var kr: [Float?] = []
                for n in 0..<(guardedKind ? 5 : 1) {
                    Rand.seed(0xBA1A_6000 + UInt64(k.rawValue) * 16 + UInt64(t) + UInt64(n) * 0x1000)
                    kr.append(kills(k, t))
                }
                r.kills.append(kr.contains { $0 == nil } ? nil : kr.compactMap { $0 }.sorted()[kr.count / 2])
            }
            rows.append(r)
            print("balance: \(r.name): kills the player in " + r.toKill.map(f).joined(separator: " / ")
                  + "; the player kills it in " + r.kills.map(f).joined(separator: " / ") + " (early / iron / diamond)")
        }
        let blasts = (0..<tiers.count).map { blast($0) }
        print("balance: hisser blast at 1.5 blocks: \(blasts.map(String.init).joined(separator: " / ")) damage (early / iron / diamond)")

        let inf = Float.infinity
        let unfair = rows.filter { (common.contains($0.name) && $0.toKill[0] == nil) || ($0.toKill[1] ?? inf) < (common.contains($0.name) ? 4 : 2) || (common.contains($0.name) && ($0.toKill[0] ?? inf) < 2) }
        check(unfair.isEmpty, "balance fair: every common night mob can kill an unarmoured player within 60 s, none in under 2 s; with iron gear none in under 4 s (nothing in under 2 s)\(unfair.isEmpty ? "" : ": " + unfair.map { "\($0.name) \(f($0.toKill[0])) / \(f($0.toKill[1]))" }.joined(separator: ", "))")
        // A draw is no loss (the Voidwalker blinks away from a blade and leaves you be: neither side wins in 60 s). P246:
        // the Gravesworn Duellist is a knight in plate with a guard and feints, a fight for iron gear (early gear runs).
        let knights: Set<String> = ["Gravesworn Duellist"]
        let lost = rows.filter { r in
            func loses(_ t: Int) -> Bool { r.toKill[t] != nil && (r.kills[t] ?? inf) >= (r.toKill[t] ?? inf) }
            let early = common.contains(r.name) && loses(knights.contains(r.name) ? 1 : 0)
            return early || loses(2)
        }
        check(lost.isEmpty, "balance winnable: early gear beats each common night mob one on one (iron the Gravesworn knight), diamond gear beats every mob\(lost.isEmpty ? "" : ": lost to " + lost.map { "\($0.name) (\(f($0.kills[0])) vs \(f($0.toKill[0])), \(f($0.kills[2])) vs \(f($0.toKill[2])))" }.joined(separator: ", "))")
        let diaSwing = 1 / Items.def(Items.id("diamond_sword")).attackSpeed
        let trivial = rows.filter { ($0.kills[2] ?? inf) < diaSwing * 1.5 }
        check(trivial.isEmpty, "balance no trivia: a diamond sword needs more than one swing on every mob\(trivial.isEmpty ? "" : ": " + trivial.map { $0.name }.joined(separator: ", "))")
        // (A witch's harming potions are magic, which armour doesn't stop: only the player's side counts for her.)
        // (Gun rounds: iron and titanium both stop at most 48% of a round, P45, so against a soldier the iron-to-diamond
        // step is the luck of his hits: within 30% there.)
        let gunners = Set(roster.filter { $0.steelhold }.map { $0.spec.name })
        // (And a Gravesworn's guard and feints make one duel's kill time the luck of when its guard drops: within 15%.)
        let guarded: Set<String> = ["Gravesworn Duellist", "Gravesworn Squire"]
        let flat = rows.filter { r in
            (0..<2).contains { t in
                (r.kills[t + 1] ?? inf) > (r.kills[t] ?? inf) * (guarded.contains(r.name) ? 1.15 : 1) + 0.3
                    || (r.name != MobKind.witch.spec.name && (r.toKill[t + 1] ?? inf) * (gunners.contains(r.name) && t == 1 ? 1.3 : 1.15) + 0.3 < (r.toKill[t] ?? inf))
            }
        }
        check(flat.isEmpty, "balance gear pays: each tier up kills every mob as fast or faster and survives as long or longer\(flat.isEmpty ? "" : ": not for " + flat.map { $0.name }.joined(separator: ", "))")
        check(blasts[0] >= 10 && blasts[2] < 20 && blasts[1] <= blasts[0] && blasts[2] <= blasts[1], "balance hisser: a blast at arm's length takes \(blasts[0]) of an unarmoured player's 20 (at least 10), \(blasts[1]) in iron (the reference can kill there too), \(blasts[2]) in diamond (survived)")

        if CommandLine.arguments.contains("--write-balance") {
            var lines = ["| mob | kills you: early | iron | diamond | you kill it: early | iron | diamond |", "|---|---|---|---|---|---|---|"]
            for r in rows { lines.append("| \(r.name) | " + r.toKill.map(f).joined(separator: " | ") + " | " + r.kills.map(f).joined(separator: " | ") + " |") }
            let doc = """
            # Combat balance: time-to-kill table (Q2)

            Written by `questcheck --balance-only --write-balance` (Sources/BalanceTests.swift): real duels through
            Game.tick on a walled stone floor at midnight, Normal difficulty. "Kills you": seconds until the mob has dealt
            20 damage to a player standing still. "You kill it": seconds of full-charge swings at a mob held 2.5 blocks
            off (it still fights). Tiers: early (no armour, stone sword), iron (iron set and sword), diamond (diamond set
            and sword). "Kills you" averages three seeded duels, "you kill it" is one, so a cell can move a little with
            hit luck.

            \(lines.joined(separator: "\n"))

            Hisser blast at 1.5 blocks: \(blasts.map(String.init).joined(separator: " / ")) damage (early / iron / diamond).

            Designed ranges (the checks): with iron gear no common night mob (zombie, husk, drowned, skeleton, spider)
            kills you in under 4 s and nothing in under 2 s, and no common night mob in under 2 s unarmoured; early gear beats each common night mob one on one
            and diamond gear beats every mob here; a diamond sword needs more than one swing on everything; each tier up
            is at least as good against every mob; a hisser blast takes at least half an unarmoured player's health and
            diamond armour survives it (at Normal a point-blank blast can kill a player in iron, as in the reference). The Deep's units: docs/status/deep-balance.md; the soldier classes:
            docs/status/troop-classes.md.
            """
            try? doc.write(toFile: "docs/status/balance.md", atomically: true, encoding: .utf8)
        }
    }
    static func f(_ t: Float?) -> String { t.map { String(format: "%.1f s", $0) } ?? "> 60 s" }
}
