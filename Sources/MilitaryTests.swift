import Foundation
import simd

// Harness checks for the Steelhold content: gun items, reloading and firing (bullets, pellets, rockets,
// beams), recoil, soldier armour and combat, the deck gun, drops, and fortress placement and layout.
extension MobTests {
    static func military(game: Game, world: World, pos: V3) {
        let mm = game.mobs
        mm.mobs.removeAll()
        game.arms.slugs.removeAll()
        // Items.
        let guns = Guns.all.filter { Items.has($0.key) && Items.def(Items.id($0.key)).maxStack == 1 }
        let ammo = Guns.ammo.filter { Items.has($0.0) }
        check(guns.count == 6 && ammo.count == 5, "guns and ammo registered", "\(guns.count) guns, \(ammo.count) ammo")
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
        t = 0
        while t < 8 {
            mm.update(0.05, game: game)
            game.armsTick(0.05)
            game.player.pos = at(0, 0); game.player.vel = .zero
            if hurtAt < 0 && game.health < 20 { hurtAt = t }
            if game.health < 8 { game.health = 20 }
            t += 0.05
        }
        check(shooter.aggro && buddy.aggro, "soldiers alert each other")
        check(hurtAt > 0.5 && hurtAt < 6, "recruit shoots the player after a reaction delay", String(format: "first hit at %.2f s", hurtAt))
        mm.mobs.removeAll()
        game.arms.slugs.removeAll()

        // Marksman: holds a laser on the target before firing.
        game.health = 20
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
            t += 0.05
        }
        check(lasered && firedSniper, "marksman aims a laser, then fires", "laser \(lasered), shot \(firedSniper)")
        mm.mobs.removeAll()
        game.arms.slugs.removeAll()

        // Deck gun: traverses onto the player and fires twin shells.
        let gun = Mob(.deckGun, at: at(0, -45) + V3(0, 0, 0)); gun.persistent = true; gun.yaw = 0
        mm.mobs.append(gun)
        var shells = 0
        t = 0
        while t < 12 && shells == 0 {
            gun.updateDeckGun(0.05, game)
            shells = game.arms.slugs.filter { $0.kind == .shell }.count
            game.player.pos = at(0, 0)
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
            check(found >= 1 && found <= 60, "fortresses are rare", "\(found) in 144 regions of 64x64 chunks")
            // Lay one out on a plain stone slab, chunk by chunk.
            var built: [String: Int] = [:]
            var mobs: [String: Int] = [:]
            var chests = 0
            let c = 0, y0 = 100
            for cz in -3...2 { for cx in -3...2 {
                var blocks = [BlockID](repeating: AIR, count: CS * CS * CH)
                for y in 0..<(y0 - 1) { for zz in 0..<CS { for xx in 0..<CS { blocks[Chunk.index(xx, y, zz)] = STONE } } }
                blocks.withUnsafeMutableBufferPointer { buf in
                    var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
                    MilitaryBase.build(&w, c, y0, c, 12345)
                    chests += w.entities.filter { $0.1.kind == .chest }.count
                    for (k, _) in w.mobs { mobs[k, default: 0] += 1 }
                }
                for b in blocks where b != AIR && b != STONE { built[Blocks.key(Blocks.groupBase[Int(b)]), default: 0] += 1 }
            } }
            check((built["steel_plating"] ?? 0) > 10000 && (built["command_console"] ?? 0) > 30 && (built["armored_glass"] ?? 0) > 50 && (built["light_panel"] ?? 0) > 40,
                  "fortress built from steel", built.filter { $0.key.hasPrefix("steel") || $0.key.hasPrefix("command") || $0.key.hasPrefix("armored") || $0.key.hasPrefix("light") }
                    .map { "\($0.value) \($0.key)" }.sorted().joined(separator: ", "))
            let soldiers = ["soldier_recruit", "soldier_trooper", "soldier_marksman", "soldier_ironclad"].map { mobs[$0] ?? 0 }
            check(soldiers.allSatisfy { $0 > 0 } && mobs["deck_gun"] == 4 && chests >= 15, "fortress garrison, deck guns and loot",
                  "\(soldiers) soldiers, \(mobs["deck_gun"] ?? 0) deck guns, \(chests) chests")
        } else {
            check(false, "fortress structure type registered")
        }
        game.player.pos = pos
        game.health = 20
    }
}
