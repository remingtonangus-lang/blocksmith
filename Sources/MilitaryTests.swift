import Foundation
import simd

// Harness checks for the Steelhold content: gun items, reloading and firing (bullets, pellets, rockets,
// beams), recoil, soldier armour and combat, the deck gun, drops, and fortress placement and layout.
extension MobTests {
    // A running raid survives a save: its state round-trips and saved raiders rejoin it.
    static func raidSave(game: Game, pos: V3) {
        let r = Raid(center: pos, level: 3, difficulty: 3)
        r.wave = 4; r.state = 1; r.timer = 7; r.waveHealth = 120; r.idle = 300
        guard let data = try? JSONEncoder().encode(r.record), let rec = try? JSONDecoder().decode(RaidRecord.self, from: data) else {
            check(false, "raid record encodes"); return
        }
        let back = Raid(rec)
        check(back.wave == 4 && back.state == 1 && back.level == 3 && back.groups == 7 && back.totalWaves == 8 && simd_length(back.center - pos) < 0.01,
              "raid state round-trips through the save", "wave \(back.wave), level \(back.level), \(back.totalWaves) waves")
        let saved = game.raid
        game.raid = back
        let m = Mob(.pillager, at: pos + V3(5, 0, 0))
        m.raider = true
        let restored = Mob.from(m.record)
        if let rm = restored { game.mobs.mobs.append(rm) }
        let villager = Mob(.villager, at: pos + V3(-3, 0, 0))
        game.mobs.mobs.append(villager)
        game.raidTick(1)
        check(restored?.raider == true && back.raiders.count == 1 && back.state == 1 && back.wave == 4, "saved raiders rejoin the raid",
              "\(back.raiders.count) raiders, state \(back.state)")
        game.mobs.mobs.removeAll { $0 === restored || $0 === villager }
        game.raid = saved
    }

    // --fortresstest N: the camera stands inside a generated Steelhold fortress (--structure military_base) as a survival
    // player for N seconds of real Game.tick. The garrison must notice and engage (the player takes hits), at least one
    // soldier must move or duck into cover, and none may end up inside a block. The player is healed every tick.
    static func fortressFight(game g: Game, world: World, seconds: Float) -> Bool {
        let p0 = g.player.pos
        g.survival = true; g.player.flying = false; g.paused = false; g.menu = nil; g.difficulty = 2
        for (name, mp) in world.pendingMobs { if let k = MobKind.named(name) { g.mobs.mobs.append(Mob(k, at: mp)) } }
        world.pendingMobs.removeAll()
        let near = g.mobs.mobs.filter { $0.kind.steelhold && $0.kind != .deckGun && simd_length($0.pos - p0) < 48 }
        let start = near.map { $0.pos }
        var hurt = 0, coverSeen = false, t: Float = 0
        while t < seconds {
            let h0 = g.health
            g.tick(0.05)
            if g.health < h0 { hurt += h0 - g.health }
            g.health = 20; g.alive = true; g.menu = nil
            g.player.pos = p0; g.player.vel = .zero
            for m in near where m.health > 0 {
                if let c = m.brain?.cover, simd_length(V2(c.x - m.pos.x, c.z - m.pos.z)) < 1, !world.canSee(m.eye, g.player.eye) { coverSeen = true }
            }
            t += 0.05
        }
        var moved = 0, stuck = 0, aggro = 0
        for (i, m) in near.enumerated() where m.health > 0 {
            if simd_length(V2(m.pos.x - start[i].x, m.pos.z - start[i].z)) > 2 { moved += 1 }
            if m.collides(m.pos, world) { stuck += 1 }
            if m.aggro { aggro += 1 }
        }
        print(String(format: "fortresstest: %ld soldiers within 48, %ld aggro, %ld moved, %ld stuck in blocks, player took %ld damage, cover %@ (%.0f s)",
                     near.count, aggro, moved, stuck, hurt, coverSeen ? "yes" : "no", seconds))
        let ok = !near.isEmpty && aggro > 0 && hurt > 0 && moved > 0 && stuck == 0
        print("fortresstest: \(ok ? "PASS" : "FAIL")")
        return ok
    }

    static func military(game: Game, world: World, pos: V3) {
        let mm = game.mobs
        mm.mobs.removeAll()
        game.arms.slugs.removeAll()
        // Items.
        let guns = Guns.all.filter { Items.has($0.key) && Items.def(Items.id($0.key)).maxStack == 1 }
        let ammo = Guns.ammo.filter { Items.has($0.0) }
        check(guns.count == 7 && ammo.count == 5, "guns and ammo registered", "\(guns.count) guns, \(ammo.count) ammo")
        check(Guns.index(Items.id("gun_sniper")) == Guns.sniper, "gun lookup by item")

        // Arena: a long open strip with a stone floor.
        let x0 = Int(floor(pos.x)) + 40, z0 = Int(floor(pos.z)) - 5
        var top = 0
        for x in stride(from: x0 - 10, through: x0 + 10, by: 5) { for z in stride(from: z0 - 40, through: z0 + 10, by: 5) { top = max(top, world.topY(x, z)) } }
        let gy = min(CH - 30, top + 10)
        for x in (x0 - 10)...(x0 + 10) { for z in (z0 - 50)...(z0 + 10) {
            world.setBlockAsync(x, gy - 1, z, STONE)
            for y in gy..<(gy + 14) { world.setBlockAsync(x, y, z, AIR) }
        } }
        func at(_ dx: Float, _ dz: Float) -> V3 { V3(Float(x0) + 0.5 + dx, Float(gy), Float(z0) + 0.5 + dz) }
        game.survival = true
        game.alive = true
        game.health = 20
        game.time = 0.25 * DAY_LENGTH
        game.player.pos = at(0, 0)
        game.player.vel = .zero
        func look(at p: V3) {
            let d = p - game.player.eye
            game.player.yaw = atan2f(-d.x, -d.z)
            game.player.pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
        }
        let pad = PadSnapshot()
        func hold(_ name: String, tag: Int = 0) {
            game.inventory.main.slots = Array(repeating: .empty, count: 36)
            game.selected = 0
            var s = ItemStack(Items.id(name), 1); s.tag = tag
            game.inventory.held = s
            game.arms.reload = 0; game.arms.cooldown = 0
            game.arms.heldGun = Guns.index(s.item) ?? -1; game.arms.heldSlot = game.selected
        }
        func trigger(_ seconds: Float, fire: Bool, aim: Bool = false) {
            var t: Float = 0
            var first = true
            while t < seconds {
                _ = game.gunInteract(pad, pad, fire: fire, firePressed: fire && first, aim: aim, dt: 0.05)
                game.armsTick(0.05)
                first = false
                t += 0.05
            }
        }

        // Reloading: an empty rifle pulls 30 rounds from the inventory.
        hold("gun_rifle")
        game.inventory.main[5] = ItemStack(Items.id("rifle_rounds"), 64)
        _ = game.gunInteract(pad, pad, fire: true, firePressed: true, aim: false, dt: 0.05)
        let reloading = game.arms.reload > 0
        trigger(2.2, fire: false)
        check(reloading && game.held.tag == 30 && game.ammoCount("rifle_rounds") == 34, "rifle reloads from inventory",
              "tag \(game.held.tag), left \(game.ammoCount("rifle_rounds"))")

        // Automatic fire kills a zombie 12 blocks away, kicks the view up, and the view settles back.
        let z = Mob(.zombie, at: at(0, -12))
        z.persistent = true
        mm.mobs.append(z)
        look(at: z.pos + V3(0, 1.0, 0))
        let shots0 = game.arms.shotsFired
        var kick: Float = 0
        var t: Float = 0
        while t < 1.2 && z.health > 0 {
            look(at: z.pos + V3(0, 1.0, 0))
            let before = game.player.pitch
            _ = game.gunInteract(pad, pad, fire: true, firePressed: t == 0, aim: true, dt: 0.05)
            kick = max(kick, game.player.pitch - before)
            game.armsTick(0.05)
            t += 0.05
        }
        let fired = game.arms.shotsFired - shots0
        check(z.health <= 0 && fired > 0 && fired <= 10, "rifle kills a zombie at 12 blocks", "\(fired) shots, hp \(z.health), \(game.held.tag) left")
        check(kick > 0.005, "recoil kicks the view up", String(format: "%.4f rad", kick))
        let debt = game.arms.recoilDebt
        trigger(1.0, fire: false)
        check(debt > 0 && game.arms.recoilDebt < debt * 0.2, "recoil settles back", String(format: "debt %.3f -> %.3f", debt, game.arms.recoilDebt))
        mm.mobs.removeAll()

        // Shotgun: nine pellets per shell.
        hold("gun_shotgun", tag: 6)
        game.player.pitch = 0.1
        let before = game.arms.slugs.count
        _ = game.gunInteract(pad, pad, fire: true, firePressed: true, aim: false, dt: 0.05)
        check(game.arms.slugs.count - before == 9 && game.held.tag == 5, "shotgun fires 9 pellets", "\(game.arms.slugs.count - before)")
        trigger(3, fire: false)

        // Rocket: flies, explodes against a wall and blows a hole in it (player rockets break blocks).
        for x in (x0 - 2)...(x0 + 2) { for y in gy..<(gy + 4) { world.setBlockAsync(x, y, z0 - 20, Blocks.id("cobblestone")) } }
        hold("gun_launcher", tag: 1)
        look(at: at(0, -20) + V3(0, 1.5, 0))
        _ = game.gunInteract(pad, pad, fire: true, firePressed: true, aim: false, dt: 0.05)
        let rocketOut = game.arms.slugs.contains { $0.kind == .rocket }
        trigger(1.5, fire: false)
        var holes = 0
        for x in (x0 - 2)...(x0 + 2) { for y in gy..<(gy + 4) where world.block(x, y, z0 - 20) == AIR { holes += 1 } }
        check(rocketOut && !game.arms.slugs.contains { $0.kind == .rocket } && holes > 0, "rocket explodes on a wall", "\(holes) blocks blown out")
        for x in (x0 - 2)...(x0 + 2) { for y in gy..<(gy + 4) { world.setBlockAsync(x, y, z0 - 20, AIR) } }
        game.drops.items.removeAll()

        // Arc lance: instant beam that damages and ignites.
        let cow = Mob(.cow, at: at(0, -8)); cow.persistent = true
        mm.mobs.append(cow)
        hold("gun_arc", tag: 8)
        look(at: cow.pos + V3(0, 0.7, 0))
        _ = game.gunInteract(pad, pad, fire: true, firePressed: true, aim: false, dt: 0.05)
        check(cow.health < cow.spec.health && cow.fire > 0 && !game.arms.beams.isEmpty, "arc lance beam burns", "hp \(cow.health)")
        mm.mobs.removeAll()

        // Soldier armour, knockback and brains.
        let rec = Mob(.soldierRecruit, at: at(0, -10)), iron = Mob(.soldierIronclad, at: at(3, -10))
        check(rec.armorPoints.0 == 4 && iron.armorPoints.0 == 14, "soldier rank armour", "\(rec.armorPoints.0) / \(iron.armorPoints.0)")
        iron.hit(from: at(0, 0), damage: 6, knockback: 1)
        let push = simd_length(V2(iron.vel.x, iron.vel.z))
        var taken = 0
        for _ in 0..<20 { let h = iron.health; iron.hit(from: at(0, 0), damage: 6, knockback: 1); taken += h - iron.health; iron.health = h }
        check(taken < 20 * 6 * 6 / 10 && push < 1.5, "ironclad armour and knockback resistance", String(format: "%d of 120, push %.2f", taken, push))
        var kinds: Set<Int> = []
        for _ in 0..<60 { kinds.insert(Mob(.soldierTrooper, at: at(0, 0)).soldierBrain.gun) }
        check(kinds == [Guns.shotgun, Guns.rifle], "troopers carry shotguns or rifles", "\(kinds)")

        // A recruit spots the player, alerts a trooper behind cover, and shoots.
        game.health = 20
        game.inventory.main.slots = Array(repeating: .empty, count: 36)
        game.player.pos = at(0, 0)
        let shooter = Mob(.soldierRecruit, at: at(0, -14)); shooter.persistent = true; shooter.yaw = .pi; shooter.variant = Guns.rifle
        let buddy = Mob(.soldierTrooper, at: at(6, -30)); buddy.persistent = true
        mm.mobs.append(shooter); mm.mobs.append(buddy)
        var hurtAt: Float = -1
        game.audio.record = [:]
        t = 0
        while t < 8 {
            mm.update(0.05, game: game)
            game.armsTick(0.05)
            game.player.pos = at(0, 0); game.player.vel = .zero
            if hurtAt < 0 && game.health < 20 { hurtAt = t }
            game.health = 20; game.alive = true; game.menu = nil
            t += 0.05
        }
        check(shooter.aggro && buddy.aggro, "soldiers alert each other")
        check(hurtAt > 0.5 && hurtAt < 6, "recruit shoots the player after a reaction delay", String(format: "first hit at %.2f s", hurtAt))
        // Audio: the firefight is heard (barks, rifle fire, hits or whizzes) and scores combat music.
        let heard = game.audio.record ?? [:]
        game.audio.record = nil
        let shots = heard.filter { $0.key.hasPrefix("gun_") && !$0.key.hasPrefix("gun_reload") }.values.reduce(0, +)
        let near = (heard["bulletWhizz"] ?? 0) + (heard["bulletFlesh"] ?? 0)
        let barks = heard.filter { $0.key.hasPrefix("soldier_") && $0.key.hasSuffix("_alert") }.values.reduce(0, +)
        check(shots > 0 && near > 0 && barks > 0, "firefight audio: gunfire, hits or whizzes, alert barks", "\(shots) shots, \(near) near, \(barks) barks")
        game.audio.combatCheck = 0
        game.combatTick(0.05)
        check(game.combatLevel() == 2, "combat music while soldiers hunt the player", "level \(game.combatLevel())")
        mm.mobs.removeAll()
        game.arms.slugs.removeAll()

        // Cover: a trooper with an empty magazine ducks behind a wall to reload.
        for x in (x0 + 2)...(x0 + 4) { for y in gy..<(gy + 3) { world.setBlockAsync(x, y, z0 - 12, Blocks.id("cobblestone")) } }
        game.health = 20
        let tr = Mob(.soldierTrooper, at: at(0, -10)); tr.persistent = true; tr.variant = Guns.rifle; tr.yaw = .pi
        mm.mobs.append(tr)
        tr.aggro = true
        tr.soldierBrain.mag = 0
        tr.soldierBrain.react = 0
        var hid = false
        t = 0
        while t < 3 && !hid {
            mm.update(0.05, game: game)
            game.armsTick(0.05)
            game.player.pos = at(0, 0); game.player.vel = .zero
            game.health = 20; game.alive = true; game.menu = nil
            if tr.soldierBrain.reload > 0 && tr.soldierBrain.cover != nil && !world.canSee(tr.eye, game.player.eye) { hid = true }
            t += 0.05
        }
        check(hid, "trooper takes cover to reload", String(format: "%.1f s, cover %@", t, tr.soldierBrain.cover.map { String(format: "%.1f,%.1f", $0.x - Float(x0), $0.z - Float(z0)) } ?? "none"))
        for x in (x0 + 2)...(x0 + 4) { for y in gy..<(gy + 3) { world.setBlockAsync(x, y, z0 - 12, AIR) } }
        mm.mobs.removeAll()
        game.arms.slugs.removeAll()

        // Marksman: holds a laser on the target before firing.
        game.health = 20; game.alive = true; game.menu = nil
        let mk = Mob(.soldierMarksman, at: at(0, -40)); mk.persistent = true; mk.variant = Guns.sniper; mk.yaw = .pi
        mm.mobs.append(mk)
        var lasered = false, firedSniper = false
        t = 0
        while t < 6 && !firedSniper {
            mm.update(0.05, game: game)
            if (mk.brain?.aimTime ?? 0) > 0.5 { lasered = true }
            if game.arms.slugs.contains(where: { $0.shooter == ObjectIdentifier(mk) }) { firedSniper = true }
            game.armsTick(0.05)
            game.player.pos = at(0, 0)
            game.health = 20; game.alive = true
            t += 0.05
        }
        check(lasered && firedSniper, "marksman aims a laser, then fires", "laser \(lasered), shot \(firedSniper)")
        mm.mobs.removeAll()
        game.arms.slugs.removeAll()

        // Line of fire: a glass wall (see-through, so the soldier "sees" the player) between a trooper and the player
        // holds every shot; it opens up when the wall goes.
        let glass = Blocks.id("glass")
        for x in (x0 - 4)...(x0 + 4) { for y in gy..<(gy + 4) { world.setBlockAsync(x, y, z0 - 6, glass) } }
        game.health = 20; game.alive = true; game.menu = nil
        let tw = Mob(.soldierTrooper, at: at(0, -14)); tw.persistent = true; tw.variant = Guns.rifle; tw.yaw = .pi
        mm.mobs.append(tw)
        var throughGlass = 0, sawThroughGlass = false
        t = 0
        while t < 5 {
            mm.update(0.05, game: game)
            if tw.soldierBrain.sees { sawThroughGlass = true }
            throughGlass += game.arms.slugs.filter { $0.shooter == ObjectIdentifier(tw) }.count
            game.arms.slugs.removeAll()
            game.player.pos = at(0, 0); game.player.vel = .zero
            game.health = 20; game.alive = true; tw.pos = at(0, -14)
            t += 0.05
        }
        for x in (x0 - 4)...(x0 + 4) { for y in gy..<(gy + 4) { world.setBlockAsync(x, y, z0 - 6, AIR) } }
        var afterWall = 0
        t = 0
        while t < 5 && afterWall == 0 {
            mm.update(0.05, game: game)
            afterWall += game.arms.slugs.filter { $0.shooter == ObjectIdentifier(tw) }.count
            game.arms.slugs.removeAll()
            game.player.pos = at(0, 0); game.player.vel = .zero
            game.health = 20; game.alive = true; tw.pos = at(0, -14)
            t += 0.05
        }
        check(sawThroughGlass && throughGlass == 0 && afterWall > 0, "trooper holds fire behind a glass wall, fires once it is gone",
              "saw \(sawThroughGlass), \(throughGlass) shots through glass, \(afterWall) after")
        mm.mobs.removeAll()
        game.arms.slugs.removeAll()

        // Deck gun: traverses onto the player and fires twin shells.
        let gun = Mob(.deckGun, at: at(0, -45) + V3(0, 0, 0)); gun.persistent = true; gun.yaw = 0
        mm.mobs.append(gun)
        var shells = 0
        // Unmanned it never fires (Quest round 4: an empty turret shelled the player after the garrison was dead).
        t = 0
        while t < 25 && shells == 0 {
            gun.updateDeckGun(0.05, game)
            shells = game.arms.slugs.filter { $0.kind == .shell }.count
            game.player.pos = at(0, 0)
            game.health = 20; game.alive = true
            t += 0.05
        }
        check(shells == 0, "unmanned deck gun holds fire", "\(shells) shells")
        let gunner = Mob(.soldierTrooper, at: gun.pos + V3(0, 0, -9)); gunner.persistent = true
        gunner.soldierBrain.orderStation = .gunner
        mm.mobs.append(gunner)
        gun.soldierBrain.losTimer = 0
        t = 0
        // A true-scale 42 cm turret traverses at 0.2 rad/s: half a turn takes about 16 s.
        while t < 25 && shells == 0 {
            gun.updateDeckGun(0.05, game)
            shells = game.arms.slugs.filter { $0.kind == .shell }.count
            game.player.pos = at(0, 0)
            game.health = 20; game.alive = true
            t += 0.05
        }
        let face = simd_dot(V2(-sinf(gun.yaw), -cosf(gun.yaw)), simd_normalize(V2(game.player.pos.x - gun.pos.x, game.player.pos.z - gun.pos.z)))
        check(shells == 2 && face > 0.99, "deck gun turns and fires a salvo", String(format: "%d shells after %.1f s, facing %.3f", shells, t, face))
        game.health = 20
        game.survival = false
        t = 0
        while t < 4 && !game.arms.slugs.isEmpty { game.armsTick(0.05); game.player.pos = at(0, 0); t += 0.05 }
        check(game.arms.slugs.isEmpty, "shells land", String(format: "%.1f s", t))
        mm.mobs.removeAll()
        game.survival = true

        // Fallen soldiers drop ammunition for their gun (and sometimes the gun).
        var gunDrops = 0, ammoDrops = 0
        for _ in 0..<40 {
            game.drops.items.removeAll()
            let s = Mob(.soldierTrooper, at: at(0, -5)); s.variant = Guns.shotgun; s.killedByPlayer = true
            game.mobDied(s)
            if game.drops.items.contains(where: { Items.key($0.stack.item) == "gun_shotgun" }) { gunDrops += 1 }
            if game.drops.items.contains(where: { Items.key($0.stack.item) == "shotgun_shells" }) { ammoDrops += 1 }
        }
        game.drops.items.removeAll()
        check(ammoDrops == 40 && gunDrops > 2 && gunDrops < 25, "soldier drops ammo and sometimes its gun", "\(ammoDrops) ammo, \(gunDrops) guns of 40")

        // Fortress: rare, and its layout has the command room, the garrison and the deck guns.
        if let sc = world.gen.structures, let type = sc.types.first(where: { $0.name == "military_base" }) {
            var found = 0
            for rz in -6..<6 { for rx in -6..<6 where sc.start(type, regionX: rx, regionZ: rz) != nil { found += 1 } }
            check(found >= 1 && found <= 60, "fortresses are rare", "\(found) in 144 regions of 40x40 chunks")
            // Lay one out on a plain stone slab, chunk by chunk (a Capital citadel, CapitalBase.swift).
            var built: [String: Int] = [:]
            var mobs: [String: Int] = [:]
            var chests = 0
            let c = 0, y0 = 100
            for cz in -4...3 { for cx in -4...3 {
                var blocks = [BlockID](repeating: AIR, count: CS * CS * CH)
                for y in 0..<(y0 - 1) { for zz in 0..<CS { for xx in 0..<CS { blocks[Chunk.index(xx, y, zz)] = STONE } } }
                blocks.withUnsafeMutableBufferPointer { buf in
                    var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
                    CapitalBase.build(&w, c, y0, c, 12345)
                    chests += w.entities.filter { $0.1.kind == .chest }.count
                    for (k, _) in w.mobs { mobs[k, default: 0] += 1 }
                }
                for b in blocks where b != AIR && b != STONE { built[Blocks.key(Blocks.groupBase[Int(b)]), default: 0] += 1 }
            } }
            let green = (built["oak_leaves"] ?? 0) + (built["birch_leaves"] ?? 0) + (built["flowering_azalea_leaves"] ?? 0)
            check((built["capital_stone"] ?? 0) > 10000 && (built["capital_window"] ?? 0) > 200 && (built["capital_glass"] ?? 0) > 300
                  && (built["light_panel"] ?? 0) > 40 && (built["command_console"] ?? 0) > 10 && green > 400,
                  "citadel built of white stone, glass and gardens", built.filter { $0.key.hasPrefix("capital") || $0.key.hasSuffix("leaves") || $0.key.hasPrefix("command") || $0.key.hasPrefix("light") }
                    .map { "\($0.value) \($0.key)" }.sorted().joined(separator: ", "))
            let soldiers = ["soldier_recruit", "soldier_trooper", "soldier_marksman", "soldier_ironclad"].map { mobs[$0] ?? 0 }
            check(soldiers.allSatisfy { $0 > 0 } && mobs["deck_gun"] == 2 && chests >= 12, "citadel garrison, twin 42 cm turrets and loot",
                  "\(soldiers) soldiers, \(mobs["deck_gun"] ?? 0) turrets, \(chests) chests")
        } else {
            check(false, "fortress structure type registered")
        }
        // Zombies trample turtle eggs.
        let ex = x0 - 6, ez = z0 - 3
        world.setBlockAsync(ex, gy, ez, Blocks.id("turtle_egg") + 1)
        let zb = Mob(.zombie, at: V3(Float(ex) + 0.5, Float(gy), Float(ez) + 1.2))
        zb.jobTimer = 0
        var tt: Float = 0
        while tt < 6 && Blocks.groupBase[Int(world.block(ex, gy, ez))] == Blocks.id("turtle_egg") {
            zb.attackCooldown -= 0.05
            _ = zb.trampleEggs(0.05, game)
            tt += 0.05
        }
        check(world.block(ex, gy, ez) == AIR, "zombies trample turtle eggs", String(format: "%.1f s", tt))
        // Steel stairs: soldiers can path up a fortress stair run to the next floor.
        let sx = x0 - 7
        let stairs = Blocks.has("steel_plating_stairs") ? Blocks.id("steel_plating_stairs") : STONE
        for i in 0..<6 { world.setBlockAsync(sx, gy + i, z0 - 20 - i, stairs) }
        for z in (z0 - 32)...(z0 - 26) { for x in (sx - 2)...(sx + 2) { world.setBlockAsync(x, gy + 5, z, Blocks.has("steel_grating") ? Blocks.id("steel_grating") : STONE) } }
        let climber = Mob(.soldierTrooper, at: V3(Float(sx) + 0.5, Float(gy), Float(z0 - 17) + 0.5))
        let route = PathFinder.find(world, from: climber.pos, to: V3(Float(sx) + 0.5, Float(gy + 6), Float(z0 - 29) + 0.5),
                                    profile: climber.pathProfile(game), maxNodes: 2000) ?? []
        check((route.last?.y ?? 0) == gy + 6, "soldiers path up steel stairs", "\(route.count) nodes, ends at y \((route.last?.y ?? 0) - gy)")
        for i in 0..<6 { world.setBlockAsync(sx, gy + i, z0 - 20 - i, AIR) }
        for z in (z0 - 32)...(z0 - 26) { for x in (sx - 2)...(sx + 2) { world.setBlockAsync(x, gy + 5, z, AIR) } }

        // Explorer map: points at the nearest Steelhold.
        game.inventory.main.slots = Array(repeating: .empty, count: 36)
        game.selected = 0
        game.inventory.held = ItemStack(Items.id("steelhold_explorer_map"), 1)
        let used = game.useExplorerMap()
        let md = game.maps[game.held.tag]
        let target = world.gen.structures?.nearest("military_base", x: Int(pos.x), z: Int(pos.z), maxRegions: 10)
        check(used && Items.key(game.held.item) == "filled_map" && md?.marker != nil && target != nil
              && abs((md?.marker?[0] ?? 0) - ((target?.min.x ?? 0) + (target?.max.x ?? 0)) / 2) <= 1,
              "steelhold explorer map marks the nearest fortress", "marker \(md?.marker ?? [])")
        game.inventory.held = .empty
        game.player.pos = pos
        game.health = 20
    }
}
