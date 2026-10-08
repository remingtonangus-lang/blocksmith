import simd

// `--questbugs`: checks for the Quest playtest bug list of 2026-10-06 (task 20): ore drop counts, sword damage against a
// zombie, climbing out of water onto a one-block bank, and skeletons holding a bow. Prints one line per check.
enum QuestBugTests {
    static func run(_ game: Game) -> Int {
        var fails = 0
        func check(_ ok: Bool, _ msg: String) {
            print("questbugs: \(ok ? "ok  " : "FAIL") \(msg)")
            if !ok { fails += 1 }
        }
        // `--only r3`: just the round 3 checks (save migration and the round 3 features), for quick local runs.
        if let i = CommandLine.arguments.firstIndex(of: "--only"), i + 1 < CommandLine.arguments.count, CommandLine.arguments[i + 1] == "r3" {
            round3(game, check)
            print("questbugs: \(fails) failures")
            return fails
        }
        // Ore drops with an iron pickaxe, no Fortune (reference: lapis 4-9, sparkstone dust 4-5).
        let pick = ItemStack(Items.id("iron_pickaxe"), 1)
        for (ore, item, lo, hi) in [("lapis_ore", "lapis_lazuli", 4, 9), ("deepslate_lapis_ore", "lapis_lazuli", 4, 9),
                                    ("redstone_ore", "redstone", 4, 5), ("deepslate_redstone_ore", "redstone", 4, 5)] {
            var mn = 99, mx = 0
            for _ in 0..<400 {
                let n = Mining.drops(Blocks.id(ore), pick).filter { Items.key($0.item) == item }.reduce(0) { $0 + $1.count }
                mn = min(mn, n); mx = max(mx, n)
            }
            check(mn == lo && mx == hi, "\(ore) drops \(mn)...\(mx) \(item) (want \(lo)...\(hi))")
        }
        // Sword damage (reference Java values) and hits to kill a 20 HP zombie with full-strength swings.
        for (k, d) in [("wooden_sword", 4), ("stone_sword", 5), ("iron_sword", 6), ("diamond_sword", 7), ("netherite_sword", 8)] {
            guard Items.has(k) else { check(false, "\(k) missing"); continue }
            let a = ItemStack(Items.id(k), 1).def.attack
            let z = Mob(.zombie, at: game.player.pos + V3(0, 0, -3))
            z.equip = nil                                       // no random armour roll
            var hits = 0
            while z.health > 0 && hits < 20 {
                z.invulnerable = 0
                z.hit(from: game.player.pos, damage: max(1, Int(a.rounded())), knockback: 0, iframes: true)
                hits += 1
            }
            let want = (20 + d - 1) / d
            check(Int(a) == d && hits == want, "\(k): \(a) damage, zombie (20 HP) dies in \(hits) hits (want \(d), \(want))")
        }
        // Climbing out of water: a 3-deep pool with a bank one block above the surface, swim into it.
        let w = game.world
        let p = game.player
        let x0 = Int(floor(p.pos.x)), z0 = Int(floor(p.pos.z)), y0 = min(CH - 20, Int(p.pos.y) + 40)
        for x in (x0 - 3)...(x0 + 4) {
            for z in (z0 - 3)...(z0 + 3) {
                for y in (y0 - 4)...(y0 + 3) {
                    let wall = x == x0 - 3 || x == x0 + 4 || z == z0 - 3 || z == z0 + 3 || y == y0 - 4
                    let bank = x >= x0 + 2 && y <= y0
                    w.setBlock(x, y, z, wall || bank ? STONE : (y < y0 ? WATER : AIR))
                }
            }
        }
        let save = (p.pos, p.vel, p.yaw, p.flying, p.moveLook)
        p.flying = false
        p.moveLook = nil
        p.pos = V3(Float(x0) + 0.5, Float(y0) - 1.5, Float(z0) + 0.5)
        p.vel = .zero
        p.yaw = -.pi / 2                                    // facing +x
        var t: Float = 0
        while t < 6 && !(p.onGround && p.pos.y >= Float(y0) + 0.99) {
            p.update(dt: 1.0 / 60, input: MoveInput(forward: 1), world: w)
            t += 1.0 / 60
            if Int(t * 60) % 20 == 0 && CommandLine.arguments.contains("--verbose") {
                print(String(format: "questbugs:   t %.2f pos %.2f %.2f %.2f vel %.2f %.2f wet %d ground %d", t, p.pos.x - Float(x0), p.pos.y, p.pos.z - Float(z0), p.vel.x, p.vel.y, p.inWater ? 1 : 0, p.onGround ? 1 : 0))
            }
        }
        check(p.onGround && p.pos.y >= Float(y0) + 0.99, String(format: "swim out onto a 1-block bank: %.2f s, y %.2f (bank %d)", t, p.pos.y, y0 + 1))
        (p.pos, p.vel, p.yaw, p.flying, p.moveLook) = save
        // VR locomotion: with Player.moveYaw (the head) set, the aim yaw/pitch (the right hand, randomised every
        // tick here) must not change where the stick takes you: walking, flying, sprint-swimming and ladders.
        do {
            let head: Float = 0.7                                    // head yaw: forward = (-sin, -cos)
            let fwd = V3(-sinf(head), 0, -cosf(head))
            let save = (p.pos, p.vel, p.yaw, p.pitch, p.flying, p.moveLook, p.moveYaw, p.swimming)
            var seed: UInt32 = 12345
            func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) }
            func run(_ mode: String, input: MoveInput, start: V3, ticks: Int, handStill: Bool) -> V3 {
                p.pos = start; p.vel = .zero; p.flying = mode == "fly"; p.swimming = false
                p.inWater = false; p.headInWater = false; p.onGround = false
                p.moveYaw = head
                p.moveLook = V3(-sinf(head), 0, -cosf(head))
                p.yaw = 2.5; p.pitch = 0.4
                for _ in 0..<ticks {
                    if !handStill { p.yaw = (rnd() - 0.5) * 6.2; p.pitch = (rnd() - 0.5) * 3 }
                    p.update(dt: 1.0 / 60, input: input, world: w)
                }
                return p.pos - start
            }
            // Flat floor at y0+3 (over the pool area, which is sealed below), walls far away.
            for x in (x0 - 8)...(x0 + 8) { for z in (z0 - 8)...(z0 + 8) { for y in (y0 + 3)...(y0 + 9) { w.setBlock(x, y, z, y == y0 + 3 ? STONE : AIR) } } }
            let floorP = V3(Float(x0) + 0.5, Float(y0) + 4, Float(z0) + 0.5)
            for (mode, inp) in [("walk", MoveInput(forward: 1)), ("strafe", MoveInput(forward: 0, strafe: 1)), ("fly", MoveInput(forward: 1, sprint: true))] {
                let a = run(mode, input: inp, start: floorP, ticks: 60, handStill: true)
                let b = run(mode, input: inp, start: floorP, ticks: 60, handStill: false)
                let dir = simd_normalize(V3(b.x, 0, b.z))
                let want = mode == "strafe" ? V3(cosf(head), 0, -sinf(head)) : fwd
                check(simd_length(V3(a.x, 0, a.z)) > 1.5 && simd_length(a - b) < 1e-3 && simd_dot(dir, want) > 0.999,
                      String(format: "VR %@: moved %.2f along the head (dot %.4f), hand waving changes it by %.4f", mode, simd_length(V3(b.x, 0, b.z)), simd_dot(dir, want), simd_length(a - b)))
            }
            // Sprint-swimming in a deep pool: follows moveLook (the head), not the hand.
            for x in (x0 - 8)...(x0 + 8) { for z in (z0 - 8)...(z0 + 8) { for y in (y0 + 4)...(y0 + 8) { w.setBlock(x, y, z, WATER) } } }
            let deep = V3(Float(x0) + 0.5, Float(y0) + 5.5, Float(z0) + 0.5)
            var swim = MoveInput(forward: 1); swim.sprint = true
            let sa = run("swim", input: swim, start: deep, ticks: 90, handStill: true)
            let sb = run("swim", input: swim, start: deep, ticks: 90, handStill: false)
            let sdir = simd_normalize(V3(sb.x, 0, sb.z))
            check(p.swimming && simd_length(sa - sb) < 1e-3 && simd_dot(sdir, fwd) > 0.999 && simd_length(V3(sa.x, 0, sa.z)) > 2,
                  String(format: "VR swim: swimming %d, moved %.2f along the head (dot %.4f), hand waving changes it by %.4f", p.swimming ? 1 : 0, simd_length(V3(sb.x, 0, sb.z)), simd_dot(sdir, fwd), simd_length(sa - sb)))
            // Ladder: a wall straight ahead of the head with a ladder on it; pushing forward climbs whatever the hand does.
            for x in (x0 - 8)...(x0 + 8) { for z in (z0 - 8)...(z0 + 8) { for y in (y0 + 4)...(y0 + 9) { w.setBlock(x, y, z, AIR) } } }
            // The player stands in a vine shaft (climbable, no collision box, stone all round): pushing forward
            // presses into the wall ahead of the head and climbs, whatever the hand does.
            let vine = Blocks.id("vine")
            if vine != 0 {
                for dx in -1...1 { for dz in -1...1 { for y in (y0 + 4)...(y0 + 9) {
                    w.setBlock(x0 + dx, y, z0 + dz, dx == 0 && dz == 0 ? vine : STONE) } } }
                let la1 = run("ladder", input: MoveInput(forward: 1), start: floorP, ticks: 90, handStill: true)
                let la2 = run("ladder", input: MoveInput(forward: 1), start: floorP, ticks: 90, handStill: false)
                check(la1.y > 2.5 && abs(la1.y - la2.y) < 1e-3, String(format: "VR ladder: climbed %.2f with the hand still, %.2f waving", la1.y, la2.y))
                for dx in -1...1 { for dz in -1...1 { for y in (y0 + 4)...(y0 + 9) { w.setBlock(x0 + dx, y, z0 + dz, AIR) } } }
            } else { check(false, "vine block missing") }
            (p.pos, p.vel, p.yaw, p.pitch, p.flying, p.moveLook, p.moveYaw, p.swimming) = save
        }
        // Skeletons hold a bow (more parts than the bare biped), raised while drawing.
        let sk = Mob(.skeleton, at: p.pos)
        let idle = mobModelParts(sk).count
        sk.aimHold = 1
        let aimParts = mobModelParts(sk)
        check(idle >= 13 && aimParts.contains { abs($0.rotX - 1.45) < 0.01 && $0.color.x > 0.8 && $0.mx.z - $0.mn.z > 13 },
              "skeleton: \(idle) parts, bow string raised while aiming")
        // VR trigger attacks (Game.bufferAttacks): clicking every 0.25 s, each click waits for the cooldown and lands at
        // full strength, so an iron sword kills a 20 HP zombie in 4 hits (v63: ~8 weak, half-charged hits).
        do {
            let save = (game.inventory.held, p.yaw, p.pitch, game.paused, p.pos, p.flying)
            p.pos.y += 60; p.flying = true; p.vel = .zero                  // open air: nothing between the player and it
            game.inventory.held = ItemStack(Items.id("iron_sword"), 1)
            game.bufferAttacks = true
            game.paused = false
            let zp = p.pos + V3(0, 0, -1.6)
            let z = Mob(.husk, at: zp)                              // a zombie that does not burn in the sun
            z.equip = nil
            game.mobs.mobs.append(z)
            var hits = 0, last = z.health, t: Float = 0, sinceClick: Float = 1
            while z.health > 0 && t < 6 {
                p.yaw = 0; p.pitch = -0.4
                p.pos = save.4 + V3(0, 60, 0); p.vel = .zero
                z.pos = zp; z.vel = .zero
                sinceClick += 1.0 / 60
                if sinceClick >= 0.25 { game.input.leftClicked = true; sinceClick = 0 }
                game.tick(1.0 / 60)
                if z.health < last {
                    hits += 1; last = z.health
                    if CommandLine.arguments.contains("--verbose") { print(String(format: "questbugs:   hit %d at %.2f s: zombie %d HP", hits, t, z.health)) }
                }
                t += 1.0 / 60
            }
            check(z.health <= 0 && hits == 4, String(format: "VR trigger spam (iron sword, a click every 0.25 s): zombie dead %@ in %d hits, %.1f s (want 4)",
                                                   z.health <= 0 ? "yes" : "no", hits, t))
            game.mobs.mobs.removeAll { $0 === z }
            game.bufferAttacks = false
            (game.inventory.held, p.yaw, p.pitch, game.paused, p.pos, p.flying) = save
        }
        // Round 2 (v63): a bed's head half drops the bed; a saddled horse drops its saddle; the mount screen takes the
        // saddle off; a villager asleep lies on its bed.
        check(Mining.drops(Blocks.id("red_bed_head"), .empty).contains { Items.key($0.item) == "red_bed" }, "bed head drops the bed")
        do {
            let h = Mob(.horse, at: p.pos + V3(2, 0, 0))
            h.owner = true; h.saddled = true; h.armorTier = 2
            let before = game.drops.items.count
            game.mobDied(h)
            let got = game.drops.items[before...].map { Items.key($0.stack.item) }
            check(got.contains("saddle") && got.contains("iron_horse_armor"), "saddled, armoured horse drops \(got.filter { $0.contains("saddle") || $0.contains("armor") })")
            game.drops.items.removeLast(game.drops.items.count - before)
            let h2 = Mob(.horse, at: p.pos + V3(2, 0, 0))
            h2.owner = true; h2.saddled = true
            let menu = MountMenu(game: game, mob: h2)
            let saddleSlot = menu.slots[0]
            let took = saddleSlot.stack
            saddleSlot.stack = .empty
            menu.onClose()
            check(Items.key(took.item) == "saddle" && !h2.saddled, "mount screen: saddle slot held \(Items.key(took.item)), horse saddled after taking it: \(h2.saddled)")
        }
        do {
            let bx = Int(floor(p.pos.x)) + 3, by = Int(floor(p.pos.y)) + 50, bz = Int(floor(p.pos.z))
            let w = game.world
            for x in (bx - 1)...(bx + 1) { for z in (bz - 1)...(bz + 2) { w.setBlock(x, by - 1, z, STONE); for y in by...(by + 2) { w.setBlock(x, y, z, AIR) } } }
            w.setBlock(bx, by, bz, Blocks.id("red_bed")); w.setBlock(bx, by, bz + 1, Blocks.id("red_bed_head"))     // facing 0: head toward +z
            let v = Mob(.villager, at: V3(Float(bx) + 1.5, Float(by), Float(bz) + 1.5))
            var vd = VillagerData(); vd.bed = [bx, by, bz + 1]; v.villager = vd
            let saveT = game.time
            game.time = 0.75 * DAY_LENGTH
            let asleep = v.villagerNight(game)
            check(asleep && v.lying && abs(v.pos.y - (Float(by) + 0.5625)) < 0.01 && abs(v.pos.z - (Float(bz + 1) + 0.5 - 1.45)) < 0.01,
                  String(format: "villager at night: asleep %@, lying %@ on the bed at y %.2f", asleep ? "yes" : "no", v.lying ? "yes" : "no", v.pos.y - Float(by)))
            game.time = saveT
            for x in (bx - 1)...(bx + 1) { for z in (bz - 1)...(bz + 2) { for y in (by - 1)...(by + 2) { w.setBlock(x, y, z, AIR) } } }
        }
        // The bonded horse (Quest round 4): ridden while tamed it bonds; stored with a chunk 2,000+ blocks away, a call
        // brings it to a spot near the player (out of the store, no copy left) and it gallops up.
        do {
            let h = Mob(.horse, at: game.player.pos + V3(2, 0, 0))
            h.owner = true; h.saddled = true
            game.bondHorse(h)
            h.pos = game.player.pos + V3(2100, 0, 300)
            let k = ChunkKey(x: floorDiv(Int(h.pos.x), CS), z: floorDiv(Int(h.pos.z), CS))
            game.mobs.stored[k, default: []].append(h.record)
            let surv = game.survival
            game.survival = true
            let called = game.callHorse()
            let back = game.mobs.mobs.first { $0.bond == game.horseBond }
            let d = back.map { simd_length($0.pos - game.player.pos) } ?? 999
            let left = game.mobs.stored.values.joined().contains { $0.extra?["bond"] == game.horseBond }
            let run = back.flatMap { $0.bondedHorseAI(0.05, game, dist: d) } ?? 0
            check(called && back != nil && d < 20 && !left && run > 0,
                  String(format: "horse call from 2,100 blocks: back %@, %.1f blocks from the player, store copy left %@, runs at %.1f", back != nil ? "yes" : "no", d, left ? "yes" : "no", run))
            game.mobs.mobs.removeAll { $0.bond != 0 }
            game.horseBond = 0; game.horseCall = 0
            game.survival = surv
        }
        round3(game, check)
        print("questbugs: \(fails) failures")
        return fails
    }

    // Round 3 features (docs/requests/round3-features-after-reset.md).
    static func round3(_ game: Game, _ check: (Bool, String) -> Void) {
        // Round 3 save migration: an old-format world (no extra["format"]) with aliased block and item names.
        do {
            let fm = FileManager.default
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-migr-\(UInt32.random(in: 0...UInt32.max))")
            let wdir = tmp.appendingPathComponent("Worlds/Old World", isDirectory: true)
            let saveB = SaveMigration.blockAliases, saveI = SaveMigration.itemAliases
            let stateKey = (0..<Blocks.count).map { Blocks.key(BlockID($0)) }.first { $0.contains("[") && !$0.hasPrefix("#") } ?? "stone"
            let stateBase = String(stateKey.prefix { $0 != "[" }), suffix = String(stateKey.dropFirst(stateBase.count))
            SaveMigration.blockAliases["old_test_rock"] = "cobblestone"
            SaveMigration.blockAliases["old_test_state"] = stateBase
            SaveMigration.itemAliases["old_test_gem"] = "diamond"
            var sm = SaveManager(dir: wdir)
            var bytes: [UInt8] = []
            let names = ["air", "old_test_rock", "old_test_state" + suffix]
            bytes += [UInt8(names.count), 0, 0, 0]
            for n in names { let u = Array(n.utf8); bytes += [UInt8(u.count & 255), UInt8(u.count >> 8)] + u }
            var idx = [UInt16](repeating: 0, count: CSQ * CH)
            idx[0] = 1; idx[1] = 2
            for v in idx { bytes += [UInt8(v & 255), UInt8(v >> 8)] }
            let comp = try? (Data(bytes) as NSData).compressed(using: .lzfse) as Data
            try? comp?.write(to: sm.chunkURL(ChunkKey(x: 0, z: 0)))
            var meta = game.meta
            meta.extra = nil
            try? JSONEncoder().encode(meta).write(to: sm.metaURL)
            _ = sm.loadMeta()
            _ = SaveManager(dir: wdir).loadMeta()
            let backups = ((try? fm.contentsOfDirectory(atPath: tmp.appendingPathComponent("Backups").path)) ?? [])
            let listed = (try? fm.contentsOfDirectory(atPath: tmp.appendingPathComponent("Worlds").path)) ?? []
            check(backups.count == 1 && backups[0].hasPrefix("Old World-before-r3-") && listed == ["Old World"],
                  "pre-round-3 backup made once outside the world list (\(backups), worlds \(listed))")
            let blocks = sm.loadChunk(ChunkKey(x: 0, z: 0)) ?? []
            let k0 = blocks.isEmpty ? "-" : Blocks.key(blocks[0]), k1 = blocks.count < 2 ? "-" : Blocks.key(blocks[1])
            check(k0 == "cobblestone" && k1 == stateKey, "aliased chunk blocks load as \(k0), \(k1) (want cobblestone, \(stateKey))")
            let st = try? JSONDecoder().decode([ItemStack].self, from: Data(#"[{"id":"old_test_gem","n":5},{"id":"stick","n":2}]"#.utf8))
            let ok = st?.count == 2 && Items.key(st![0].item) == "diamond" && st![0].count == 5 && Items.key(st![1].item) == "stick"
            check(ok, "aliased items load (\(st.map { $0.map { "\(Items.key($0.item))x\($0.count)" } } ?? []))")
            sm.saveMeta(meta)
            sm = SaveManager(dir: wdir)
            check(sm.loadMeta().map { !SaveMigration.needsMigration($0) } ?? false, "next save stamps format \(SaveMigration.format)")
            SaveMigration.blockAliases = saveB; SaveMigration.itemAliases = saveI
            try? fm.removeItem(at: tmp)
        }
        // Titanium replaces diamond on screen (save keys stay diamond_*).
        let diaItems = Items.defs.filter { $0.display.contains("Diamond") }.map { $0.name }
        let diaBlocks = Blocks.defs.filter { $0.display.contains("Diamond") }.map { $0.name }
        check(diaItems.isEmpty && diaBlocks.isEmpty, "no display name says Diamond (items \(diaItems.prefix(3)), blocks \(diaBlocks.prefix(3)))")
        let ipick = ItemStack(Items.id("iron_pickaxe"), 1)
        var tiOK = true
        for ore in ["diamond_ore", "deepslate_diamond_ore"] {
            for _ in 0..<50 {
                let d = Mining.drops(Blocks.id(ore), ipick)
                if !(d.count == 1 && Items.key(d[0].item) == "raw_titanium" && d[0].count == 1) { tiOK = false }
            }
        }
        check(tiOK, "titanium ore with an iron pickaxe drops raw_titanium x1")
        let sm = Recipes.smelt(Items.id("raw_titanium")).map { Items.key($0) } ?? "nil"
        check(sm == "diamond", "raw_titanium smelts into \(sm) (want diamond = Titanium Ingot)")
        let pt = TextureGen.painters()
        func diff(_ a: String) -> Float {
            guard let f = pt[a], let st = pt["stone"] else { return 99 }
            var t: Float = 0
            for y in 0..<16 { for x in 0..<16 { let p = f(x, y), q = st(x, y); t += abs(p.x - q.x) + abs(p.y - q.y) + abs(p.z - q.z) } }
            return t / 256
        }
        let dTi = diff("diamond_ore"), dFe = diff("iron_ore")
        check(dTi < 0.6 * dFe && dTi > 0.15 * dFe, String(format: "titanium ore contrast vs stone %.4f: harder to spot than iron ore (%.4f) but visible", dTi, dFe))
        // Round 3 steel: 2 iron + coal/charcoal -> 2 steel blend, blast furnace only, steel armour tier.
        do {
            let iron = Items.id("iron_ingot"), blend = Items.id("steel_blend"), steel = Items.id("steel_ingot")
            for c in ["coal", "charcoal"] {
                let r = Recipes.match([iron, iron, Items.id(c), 0, 0, 0, 0, 0, 0], 3, 3)
                check(r?.result.item == blend && r?.result.count == 2, "r3 steel: 2 iron + \(c) crafts 2 steel blend")
            }
            check(Recipes.smelt(blend) == steel, "r3 steel: steel blend smelts into a steel ingot")
            check(BlockEntity.allowed(steel, blend, in: "blast_furnace") && !BlockEntity.allowed(steel, blend, in: "furnace")
                  && !BlockEntity.allowed(steel, blend, in: "smoker"), "r3 steel: blend smelts only in a blast furnace")
            let s = Items.id("steel_ingot"), e: ItemID = 0
            let grids: [(String, [ItemID])] = [("helmet", [s, s, s, s, e, s, e, e, e]), ("chestplate", [s, e, s, s, s, s, s, s, s]),
                                               ("leggings", [s, s, s, s, e, s, s, e, s]), ("boots", [s, e, s, s, e, s, e, e, e])]
            var pts = 0
            for (p, g) in grids {
                let r = Recipes.match(g, 3, 3)
                check(r?.result.item == Items.id("steel_\(p)"), "r3 steel: steel \(p) crafts")
                pts += Items.def(Items.id("steel_\(p)")).armor
            }
            check(pts == 17, "r3 steel: steel armour totals 17 points (\(pts))")
            var worn = ItemStack(Items.id("steel_chestplate"), 1); worn.damage = 200
            let fix = Enchant.combine(worn, ItemStack(steel, 1), rename: nil, creative: true)
            check((fix?.out.damage ?? 999) < 200, "r3 steel: steel ingot repairs a steel chestplate on the anvil")
        }
    }
}

