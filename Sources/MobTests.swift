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
        pathScenarios(game: game, world: world, pos: pos)
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

    // MARK: Pathfinding

    struct Arena {
        let w: World
        let cx: Int, cz: Int, gy: Int
        func set(_ u: Int, _ y: Int, _ v: Int, _ b: BlockID) { w.setBlockAsync(cx + u, gy + y, cz + v, b) }
        func fill(_ u0: Int, _ y0: Int, _ v0: Int, _ u1: Int, _ y1: Int, _ v1: Int, _ b: BlockID) {
            for u in min(u0, u1)...max(u0, u1) { for y in min(y0, y1)...max(y0, y1) { for v in min(v0, v1)...max(v0, v1) { set(u, y, v, b) } } }
        }
        func p(_ u: Int, _ y: Int, _ v: Int) -> V3 { V3(Float(cx + u) + 0.5, Float(gy + y), Float(cz + v) + 0.5) }
        func local(_ n: IVec3) -> (Int, Int, Int) { (n.x - cx, n.y - gy, n.z - cz) }
        // Stone floor under y = 0 and 8 cells of air above, 17x17.
        func clear() {
            fill(-8, -8, -8, 8, 8, 8, AIR)
            fill(-8, -1, -8, 8, -1, 8, STONE)
        }
        func route(_ from: V3, _ to: V3, _ pr: PathProfile) -> [IVec3] {
            PathFinder.find(w, from: from, to: to, profile: pr, maxNodes: 3000) ?? []
        }
        func reaches(_ r: [IVec3], _ to: V3, span: Int = 1) -> Bool {
            guard let l = r.last else { return false }
            let g = PathFinder.anchor(to, span: span)
            return l.x == g.x && l.z == g.z && abs(l.y - g.y) <= 1
        }
        func show(_ r: [IVec3]) -> String {
            "\(r.count) nodes " + r.prefix(40).map { n in let (u, y, v) = local(n); return "\(u),\(y),\(v)" }.joined(separator: " ")
        }
    }

    static func profile(tall: Int = 2, span: Int = 1, drop: Int = 3, water: Float = 8, doors: Bool = false) -> PathProfile {
        var pr = PathProfile()
        pr.tall = tall; pr.span = span; pr.maxDrop = drop; pr.waterCost = water; pr.doors = doors; pr.climbs = span == 1
        return pr
    }

    static func pathScenarios(game: Game, world: World, pos: V3) {
        let x0 = Int(floor(pos.x)), z0 = Int(floor(pos.z))
        var top = 0
        for x in stride(from: x0 - 70, through: x0 + 70, by: 5) { for z in stride(from: z0 - 50, through: z0 + 50, by: 5) { top = max(top, world.topY(x, z)) } }
        let gy = min(CH - 24, top + 14)
        func arena(_ i: Int, _ j: Int) -> Arena {
            let a = Arena(w: world, cx: x0 - 60 + i * 20, cz: z0 - 30 + j * 20, gy: gy)
            a.clear()
            return a
        }
        let walker = profile()
        // 1. Wall with a gap at one end: walk around it.
        var a = arena(0, 0)
        a.fill(-8, 0, 0, 5, 2, 0, STONE_BRICKS)
        var r = a.route(a.p(0, 0, -5), a.p(0, 0, 5), walker)
        check(a.reaches(r, a.p(0, 0, 5)) && r.count >= 14, "path wall detour", a.show(r))
        // 2. Open field diagonal: 8-way moves.
        a = arena(1, 0)
        r = a.route(a.p(-5, 0, -5), a.p(5, 0, 5), walker)
        check(a.reaches(r, a.p(5, 0, 5)) && r.count <= 12, "path diagonal", a.show(r))
        // 3. Lava trench with a stone bridge at the far end: never over or beside lava.
        a = arena(2, 0)
        a.fill(-8, -1, 0, 5, -1, 0, LAVA)
        r = a.route(a.p(0, 0, -5), a.p(0, 0, 5), walker)
        let overLava = r.contains { n in world.block(n.x, n.y - 1, n.z) == LAVA || world.block(n.x, n.y, n.z) == LAVA }
        check(a.reaches(r, a.p(0, 0, 5)) && !overLava && r.contains { a.local($0).0 >= 6 }, "path lava bridge", a.show(r))
        // 4. Cliff 6 down with a staircase at the side: drops of at most 3 unless the mob accepts more.
        a = arena(3, 0)
        a.fill(-8, -7, 1, 8, -1, 8, AIR)
        a.fill(-8, -7, 1, 8, -7, 8, STONE)
        for v in 1...5 { a.set(8, -1 - v, v, STONE) }
        let low = a.p(0, -6, 5)
        r = a.route(a.p(0, 0, -5), low, walker)
        var worst = 0
        var prevY = gy
        for n in r { worst = min(worst, n.y - prevY); prevY = n.y }
        check(a.reaches(r, low) && worst >= -3, "path cliff uses stairs", "max drop \(-worst): " + a.show(r))
        r = a.route(a.p(0, 0, -5), low, profile(drop: 8))
        check(a.reaches(r, low) && r.count <= 14, "path cliff drop when allowed", a.show(r))
        // 5. Ladder up a 4-high wall to a platform.
        a = arena(4, 0)
        a.fill(-8, 0, 1, 8, 3, 8, STONE)
        for y in 0...3 { a.set(0, y, 0, Blocks.id("ladder")) }
        let deck = a.p(0, 4, 5)
        r = a.route(a.p(0, 0, -5), deck, walker)
        var climbs = 0
        for k in 1..<max(1, r.count) where r[k].x == r[k - 1].x && r[k].z == r[k - 1].z && r[k].y > r[k - 1].y { climbs += 1 }
        check(a.reaches(r, deck) && climbs >= 3, "path ladder climb", "\(climbs) rungs: " + a.show(r))
        // 6. Wooden door into a closed room: door openers get in, others don't; iron doors stop everyone.
        for (j, doorKey) in ["oak_door", "iron_door"].enumerated() {
            a = arena(0, 1 + j)
            a.fill(-3, 0, 2, 3, 3, 8, STONE_BRICKS)
            a.fill(-2, 0, 3, 2, 2, 7, AIR)
            a.set(0, 0, 2, Blocks.id(doorKey))
            a.set(0, 1, 2, Blocks.id(doorKey) + 8)
            let inside = a.p(0, 0, 5)
            let opener = a.route(a.p(0, 0, -5), inside, profile(doors: true))
            let other = a.route(a.p(0, 0, -5), inside, walker)
            if j == 0 {
                check(a.reaches(opener, inside) && !a.reaches(other, inside), "path wooden door", "opener " + a.show(opener) + " | other " + a.show(other))
            } else {
                check(!a.reaches(opener, inside) && !a.reaches(other, inside), "path iron door blocks")
            }
        }
        // 7. Water channel with a bridge: land mobs take the bridge, swimmers go straight across.
        a = arena(1, 1)
        a.fill(-8, -3, -1, 5, -1, 1, WATER)
        a.fill(-8, -4, -1, 5, -4, 1, STONE)
        r = a.route(a.p(0, 0, -5), a.p(0, 0, 5), walker)
        let wet = r.contains { Blocks.fluidKind[Int(world.block($0.x, $0.y, $0.z))] == 1 }
        check(a.reaches(r, a.p(0, 0, 5)) && !wet, "path land mob avoids water", a.show(r))
        r = a.route(a.p(0, 0, -5), a.p(0, 0, 5), profile(water: 0))
        let swam = r.contains { Blocks.fluidKind[Int(world.block($0.x, $0.y, $0.z))] == 1 }
        check(a.reaches(r, a.p(0, 0, 5)) && swam, "path swimmer crosses water", a.show(r))
        // 8. Wide mob: a 1-wide gap in the middle, a 2-wide gap at the side.
        a = arena(2, 1)
        a.fill(-8, 0, 0, 8, 2, 0, STONE_BRICKS)
        a.set(0, 0, 0, AIR); a.set(0, 1, 0, AIR); a.set(0, 2, 0, AIR)
        a.fill(6, 0, 0, 7, 2, 0, AIR)
        let golemGoal = a.p(0, 0, 5)
        r = a.route(a.p(0, 0, -5), golemGoal, profile(tall: 3, span: 2))
        check(a.reaches(r, golemGoal, span: 2) && r.contains { a.local($0).0 >= 5 }, "path wide mob uses wide gap", a.show(r))
        r = a.route(a.p(0, 0, -5), golemGoal, walker)
        check(a.reaches(r, golemGoal) && r.count <= 11, "path narrow mob uses narrow gap", a.show(r))
        // 9. Steps: one block up is a jump, two is a wall.
        a = arena(3, 1)
        a.fill(-8, 0, 1, 8, 0, 8, STONE)
        r = a.route(a.p(0, 0, -5), a.p(0, 1, 5), walker)
        check(a.reaches(r, a.p(0, 1, 5)), "path one-block step", a.show(r))
        a.fill(-8, 1, 1, 8, 1, 8, STONE)
        r = a.route(a.p(0, 0, -5), a.p(0, 2, 5), walker)
        check(!a.reaches(r, a.p(0, 2, 5)), "path two-block step blocked", a.show(r))

        // Live: a zombie climbs the ladder (arena 5) to reach the player on the deck; a brigand opens the
        // oak door (arena 6) to reach the player inside the room.
        game.time = 0.75 * DAY_LENGTH
        game.survival = true
        game.difficulty = 2
        game.paused = false
        game.player.flying = true
        func chase(_ kind: MobKind, _ from: V3, _ to: V3, seconds: Float) -> (Float, Float) {
            let m = Mob(kind, at: from)
            m.persistent = true
            game.mobs.mobs.removeAll()
            game.mobs.mobs.append(m)
            var reached: Float = -1
            var t: Float = 0
            while t < seconds {
                game.tick(0.05)
                t += 0.05
                game.player.pos = to; game.player.vel = .zero
                game.health = 20
                game.mobs.mobs.removeAll { $0 !== m }
                if simd_length(m.pos - to) < 1.8 { reached = t; break }
            }
            return (reached, simd_length(m.pos - to))
        }
        let ladder = Arena(w: world, cx: x0 - 60 + 4 * 20, cz: z0 - 30, gy: gy)
        let (lt, ld) = chase(.zombie, ladder.p(0, 0, -5), ladder.p(0, 4, 4), seconds: 25)
        check(lt >= 0, "live zombie climbs ladder", lt >= 0 ? String(format: "after %.1f s", lt) : String(format: "still %.1f away", ld))
        let room = Arena(w: world, cx: x0 - 60, cz: z0 - 30 + 20, gy: gy)
        let (dt, dd) = chase(.vindicator, room.p(0, 0, -5), room.p(0, 0, 5), seconds: 25)
        check(dt >= 0, "live brigand opens door", dt >= 0 ? String(format: "after %.1f s", dt) : String(format: "still %.1f away", dd))
        game.mobs.mobs.removeAll()
    }
}
