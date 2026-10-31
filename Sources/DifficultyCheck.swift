import Foundation
import simd

// P358's check (questcheck --difficulty-only, Mac --difficultycheck), on a stone floor high over the ground at noon:
//   (a) hits to kill: each Ashguard soldier type (and a Capital heavy in Hannibal plate) held still, rounds from each of
//       the player's guns fired into it through the real round path (Armory, Ballistics.impactMob) to the body and to
//       the head, a rocket and a cannon shell: how many until it falls. A soldier must fall to one or two pistol or
//       rifle rounds to the body, one to the head, a burst of four or fewer from a machine gun, any rocket or shell.
//   (c) a fight per level: a mid-geared player (an iron set, an StG 44 with 600 rounds) against an Ash Vault camp (six
//       soldiers, a machine gun among them) and then a German base (ten, two machine guns, a heavy and a marksman) in
//       two waves, through Game.tick. The player stands his ground and shoots like a person (a moment to pick each
//       target up, the aim off by up to half a block); his deaths and the damage he took per level. Very Easy and Easy
//       must come out at one death or none, and the damage taken must rise with the level.
enum DifficultyCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let pos0 = g.player.pos, yaw0 = g.player.yaw, pitch0 = g.player.pitch, surv0 = g.survival, fly0 = g.player.flying
        let time0 = g.time, lvl0 = g.diffLevel, diff0 = g.difficulty, health0 = g.health, mobs0 = g.mobs.mobs
        let armour0 = g.inventory.armor.slots, main0 = g.inventory.main.slots, sel0 = g.inventory.selected
        let enc0 = w.ships.encounters
        var placed: [IVec3] = []
        let fx = Int(floor(pos0.x)), fz = Int(floor(pos0.z))
        let py = min(CH - 30, w.topY(fx, fz) + 24)
        defer {
            for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }
            g.mobs.mobs = mobs0; w.pendingMobs.removeAll(); g.arms.slugs.removeAll()
            g.player.pos = pos0; g.player.yaw = yaw0; g.player.pitch = pitch0; g.player.vel = .zero
            g.survival = surv0; g.player.flying = fly0; g.time = time0; g.diffLevel = lvl0; g.difficulty = diff0
            Difficulty.level = lvl0
            g.health = health0; g.alive = true; g.menu = nil; g.input.leftDown = false
            g.inventory.armor.slots = armour0; g.inventory.main.slots = main0; g.inventory.selected = sel0
            w.ships.encounters = enc0
        }
        w.ships.encounters = false
        g.time = DAY_LENGTH * 0.25
        // P369 (c, Oct 18 08:15: bandit shotgun fire did nothing on Peaceful and he couldn't switch): on Peaceful a round
        // takes nothing; two steps of the pause menu's Difficulty row (Very Easy, Easy) and the same round hurts.
        do {
            g.survival = true; g.alive = true; g.diffLevel = 0; Difficulty.level = 0; g.health = 20; g.lastHurtAt = -100
            let src = g.player.pos + V3(6, 1, 0)
            g.hurtPlayer(6, from: src, cause: "was shot by a bandit", knockback: 0, type: .projectile)
            let peaceful = g.health
            let menu = PauseMenu(game: g)
            g.menu = menu
            menu.act("difficulty", back: false); menu.act("difficulty", back: false)
            g.menu = nil
            let level = g.diffLevel
            g.lastHurtAt = -100
            g.hurtPlayer(6, from: src, cause: "was shot by a bandit", knockback: 0, type: .projectile)
            check(peaceful == 20 && level == 2 && g.health < 20,
                  "P369 difficulty any time: a round on Peaceful \(20 - peaceful) damage; the Difficulty row stepped to \(Difficulty.name(level)); the same round now takes \(20 - g.health)")
            g.health = 20
        }
        _ = w.loadSync(center: V3(Float(fx), Float(py), Float(fz)), radius: 4)
        // A 61 x 61 stone floor, a low wall round it, a few two-high blocks of cover out on it.
        func arena() {
            for z in (fz - 30)...(fz + 30) { for x in (fx - 30)...(fx + 30) { for y in (py - 1)...(py + 4) {
                let edge = x == fx - 30 || x == fx + 30 || z == fz - 30 || z == fz + 30
                let cover = y <= py + 2 && (x - fx + 60) % 9 == 0 && (z - fz + 60) % 7 == 0 && z < fz - 10
                let want = y <= py || (edge && y <= py + 1) || cover ? STONE : AIR
                if w.block(x, y, z) != want { w.setBlock(x, y, z, want) }
            } } }
            g.drops.items.removeAll()
        }
        for z in (fz - 30)...(fz + 30) { for x in (fx - 30)...(fx + 30) { for y in (py - 1)...(py + 4) { placed.append(IVec3(x, y, z)) } } }
        arena()
        let spot = V3(Float(fx) + 0.5, Float(py + 1), Float(fz) + 0.5)
        func soldier(_ name: String, _ at: V3) -> Mob? {
            guard let m = Mob.structureMob(name, at: at) else { return nil }
            m.persistent = false
            return m
        }

        // (a) Hits to kill.
        g.survival = false; g.player.flying = false
        g.player.pos = spot; g.player.vel = .zero
        let kinds: [(String, String)] = [("Recruit", "soldier_recruit@ash"), ("Trooper", "soldier_trooper@ash"), ("Marksman", "soldier_marksman@ash"),
                                         ("MG gunner", "soldier_trooper:mg@ash"), ("Officer", "soldier_officer@ash"), ("Heavy", "soldier_ironclad@ash"),
                                         ("Capital heavy (Hannibal plate)", "soldier_ironclad:heavy")]
        let guns: [(String, String)] = [("Falke pistol", "gun_sidearm"), ("Sechser revolver", "gun_revolver"), ("Hagel", "gun_hagel"),
                                        ("Sturmwind", "gun_sturmwind"), ("Kessel", "gun_kessel"), ("Kettensturm MG", "gun_ashsaw")]
        func hits(_ name: String, _ make: (V3, V3) -> Slug, head: Bool) -> Int? {
            guard let m = soldier(name, spot + V3(0, 0, -6)) else { return nil }
            g.mobs.mobs = [m]; w.pendingMobs.removeAll(); g.arms.slugs.removeAll()
            let hold = m.pos
            var n = 0
            while n < 60 && m.health > 0 && g.mobs.mobs.contains(where: { $0 === m }) {
                m.pos = hold; m.vel = .zero
                let t = hold + V3(0, m.height * (head ? 0.9 : 0.55), 0)
                let from = t + V3(0, 0, 5)
                g.arms.spawn(make(from, simd_normalize(t - from)))
                n += 1
                for _ in 0..<4 where !g.arms.slugs.isEmpty { g.tick(0.05) }
                g.arms.slugs.removeAll()
            }
            return m.health <= 0 || !g.mobs.mobs.contains(where: { $0 === m }) ? n : nil
        }
        var table = ["| soldier | " + guns.map { $0.0 + " body / head" }.joined(separator: " | ") + " | rocket | cannon shell |",
                     "|---|" + String(repeating: "---|", count: guns.count + 2)]
        var worst: [String] = []
        for (label, name) in kinds {
            var row = "| \(label) |"
            for (gname, key) in guns {
                guard let gi = Guns.all.firstIndex(where: { $0.key == key }) else { continue }
                let gs = Guns.all[gi]
                let make = { (p: V3, d: V3) in Slug(pos: p, vel: d * gs.speed, kind: .bullet, damage: gs.damage, fromPlayer: true, shooter: nil, by: "Player", life: 1, gravity: 0) }
                let body = hits(name, make, head: false), headN = hits(name, make, head: true)
                row += " \(body.map(String.init) ?? "-") / \(headN.map(String.init) ?? "-") |"
                let light = gs.damage < 4
                if (body ?? 99) > (light ? 4 : 2) || (headN ?? 99) > 1 { worst.append("\(label) \(gname) \(body ?? -1)/\(headN ?? -1)") }
            }
            let rocket = hits(name, { p, d in var s = Slug(pos: p, vel: d * 60, kind: .rocket, damage: 0, fromPlayer: true, shooter: nil, by: "Player", life: 1, gravity: 0); s.power = Guns.rocketPower; return s }, head: false)
            let shell = hits(name, { p, d in var s = Slug(pos: p, vel: d * 90, kind: .shell, damage: 0, fromPlayer: true, shooter: nil, by: "Player", life: 1, gravity: 0); s.power = 4; return s }, head: false)
            row += " \(rocket.map(String.init) ?? "-") | \(shell.map(String.init) ?? "-") |"
            if rocket != 1 || shell != 1 { worst.append("\(label) rocket \(rocket ?? -1) shell \(shell ?? -1)") }
            table.append(row)
        }
        print("difficulty: hits to kill (body / head)\n" + table.joined(separator: "\n"))
        // P499 (Oct 30 15:05, "tougher proportionally to the difficulty"): a trooper takes more Sturmwind rounds to the
        // body on Hard than on Normal and more again on Very Hard; one to the head still drops him on every level.
        if let gi = Guns.all.firstIndex(where: { $0.key == "gun_sturmwind" }) {
            let gs = Guns.all[gi]
            let make = { (p: V3, d: V3) in Slug(pos: p, vel: d * gs.speed, kind: .bullet, damage: gs.damage, fromPlayer: true, shooter: nil, by: "Player", life: 1, gravity: 0) }
            var body: [Int] = [], heads: [Int] = []
            for lv in 3...5 {
                g.diffLevel = lv; g.difficulty = Difficulty.band(lv); Difficulty.level = lv
                body.append(hits("soldier_trooper@ash", make, head: false) ?? 99)
                heads.append(hits("soldier_trooper@ash", make, head: true) ?? 99)
            }
            g.diffLevel = lvl0; g.difficulty = diff0; Difficulty.level = lvl0
            check(body[0] < body[1] && body[1] < body[2] && body[2] < 99 && heads.allSatisfy { $0 == 1 },
                  "difficulty P499: Sturmwind rounds to drop a trooper, body \(body) and head \(heads) on Normal / Hard / Very Hard")
        }
        check(worst.isEmpty, "difficulty (a): every soldier falls to 1-2 pistol or rifle rounds to the body, 1 to the head, a burst of 4 or fewer from a machine gun, one rocket or shell\(worst.isEmpty ? "" : ": not " + worst.joined(separator: ", "))")

        // (c) A fight per level.
        let camp: [(String, Float, Float)] = [("soldier_trooper@ash", -6, -24), ("soldier_trooper@ash", 5, -26), ("soldier_trooper:mg@ash", 0, -28),
                                              ("soldier_recruit@ash", -11, -22), ("soldier_recruit@ash", 10, -23), ("soldier_officer@ash", 2, -29)]
        let base: [(String, Float, Float)] = [("soldier_trooper@ash", -8, -25), ("soldier_trooper@ash", 8, -25), ("soldier_trooper:mg@ash", -3, -28),
                                              ("soldier_trooper:mg@ash", 4, -28), ("soldier_ironclad@ash", 0, -24), ("soldier_marksman@ash", -14, -27),
                                              ("soldier_trooper@ash", 13, -22), ("soldier_recruit@ash", -18, -20), ("soldier_recruit@ash", 18, -20),
                                              ("soldier_officer@ash", 0, -29)]
        func fight(_ level: Int, _ squads: [[(String, Float, Float)]], seed: UInt64) -> (deaths: Int, taken: Int, secs: Float, left: Int) {
            Rand.seed(seed)
            arena()
            g.diffLevel = level; g.difficulty = Difficulty.band(level); Difficulty.level = level
            g.survival = true; g.player.flying = false
            g.health = 20; g.hunger = 20; g.saturation = 5; g.alive = true; g.menu = nil
            for e in Effect.allCases { g.effects.remove(e) }
            let iron = ["iron_helmet", "iron_chestplate", "iron_leggings", "iron_boots"]
            for i in 0..<4 { g.inventory.armor[i] = ItemStack(Items.id(iron[i]), 1) }
            g.inventory.selected = 0
            var gun = ItemStack(Items.id("gun_sturmwind"), 1)
            gun.tag = Guns.all[Guns.all.firstIndex { $0.key == "gun_sturmwind" }!].mag
            g.inventory.main[0] = gun
            g.inventory.main[1] = ItemStack(Items.id(Guns.all[Guns.all.firstIndex { $0.key == "gun_sturmwind" }!].ammo), 64)
            for i in 2..<11 { g.inventory.main[i] = g.inventory.main[1] }
            g.player.pos = spot; g.player.vel = .zero; g.player.yaw = 0; g.player.pitch = 0
            var deaths = 0, taken = 0, s: Float = 0, left = 0
            var target: Mob?, onTarget: Float = 0, offset = V3(0, 0, 0)
            for (wave, squad) in squads.enumerated() {
                g.arms.slugs.removeAll(); w.pendingMobs.removeAll()
                var foes: [Mob] = []
                for (name, dx, dz) in squad {
                    guard let m = soldier(name, spot + V3(dx, 0, dz)) else { continue }
                    m.aggro = true
                    m.soldierBrain.lastSeen = g.player.eye; m.soldierBrain.seenAgo = 0
                    foes.append(m)
                }
                g.mobs.mobs = foes
                var t: Float = 0
                while t < 90 {
                    let alive = foes.filter { f in f.health > 0 && g.mobs.mobs.contains(where: { $0 === f }) }
                    left = alive.count
                    if alive.isEmpty { break }
                    // Pick up the nearest one in sight; a moment on it before firing, the aim off by up to half a block.
                    if target == nil || !alive.contains(where: { $0 === target }) {
                        target = alive.min { simd_length($0.pos - spot) < simd_length($1.pos - spot) }
                        onTarget = 0
                        offset = V3(Rand.float(in: -0.5...0.5), Rand.float(in: -0.4...0.4), 0)
                    }
                    if let m = target {
                        let d = m.pos + V3(0, m.height * 0.55, 0) + offset - g.player.eye
                        g.player.yaw = atan2f(-d.x, -d.z)
                        g.player.pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
                    }
                    onTarget += 0.05
                    if onTarget > 1.2 { offset = V3(Rand.float(in: -0.5...0.5), Rand.float(in: -0.4...0.4), 0); onTarget = 0.6 }
                    g.input.leftDown = onTarget > 0.6
                    g.player.pos.x = spot.x; g.player.pos.z = spot.z; g.player.vel.x = 0; g.player.vel.z = 0
                    let h0 = g.health
                    g.tick(0.05)
                    t += 0.05; s += 0.05
                    if !g.alive {
                        deaths += 1; taken += h0
                        g.alive = true; g.health = 20; g.menu = nil
                        g.player.pos = spot; g.player.vel = .zero
                    } else { taken += max(0, h0 - g.health) }
                    g.hunger = 20
                    g.mobs.mobs.removeAll { !$0.kind.hostile && Soldier.rank($0.kind) == nil }
                }
                if wave < squads.count - 1 && left > 0 { break }
            }
            g.input.leftDown = false
            return (deaths, taken, s, left)
        }
        var lines: [String] = []
        var res: [[(deaths: Int, taken: Int, secs: Float, left: Int)]] = []
        for level in 1...5 {
            let a = fight(level, [camp], seed: 0xD1FF_0000 + UInt64(level))
            let b = fight(level, [Array(base.prefix(5)), Array(base.dropFirst(5))], seed: 0xD1FF_1000 + UInt64(level))
            res.append([a, b])
            lines.append(String(format: "%@: camp %d deaths, %d half-hearts taken, %.0f s%@; base %d deaths, %d taken, %.0f s%@", Difficulty.name(level),
                                a.deaths, a.taken, a.secs, a.left > 0 ? " (\(a.left) left)" : "", b.deaths, b.taken, b.secs, b.left > 0 ? " (\(b.left) left)" : ""))
        }
        print("difficulty: fights\n" + lines.joined(separator: "\n"))
        let easyOK = (0..<2).allSatisfy { lv in res[lv].allSatisfy { $0.deaths <= 1 && $0.left == 0 } }
        check(easyOK, "difficulty (c): Very Easy and Easy: a mid-geared player clears the camp and the base with at most one death each (\(lines[0]); \(lines[1]))")
        let takenBy = res.map { $0[0].taken + $0[1].taken + 20 * ($0[0].deaths + $0[1].deaths) }
        check(takenBy[0] <= takenBy[1] && takenBy[1] < takenBy[2] && takenBy[2] <= takenBy[4],
              "difficulty (c): the damage taken rises with the level (\(takenBy.map(String.init).joined(separator: " / ")) half-hearts, Very Easy to Very Hard; \(lines[2]); \(lines[3]); \(lines[4]))")
    }
}
