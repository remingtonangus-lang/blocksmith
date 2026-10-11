import Foundation
import simd

// Hunting, legendary animals and fishing (backlog B3, Hunting.swift, Fishing.swift; docs/status/hunting.md).
extension TownTests {
    static func hunting(_ g: Game, _ check: (Bool, String) -> Void) {
        let savedMobs = g.mobs.mobs, savedPos = g.player.pos, savedSurvival = g.survival, savedYaw = g.player.yaw, savedPitch = g.player.pitch
        let savedInv = g.inventory.main.slots, savedSel = g.inventory.selected, savedState = Hunting.state, savedMoney = g.money
        defer {
            g.mobs.mobs = savedMobs; g.player.pos = savedPos; g.survival = savedSurvival; g.player.yaw = savedYaw; g.player.pitch = savedPitch
            g.inventory.main.slots = savedInv; g.inventory.selected = savedSel; g.money = savedMoney
            Hunting.reset(); Hunting.state = savedState; g.bobber = nil; g.target = nil
        }
        Hunting.reset()
        g.survival = true
        let base = groundSpot(g)
        func hold(_ k: String) { g.inventory.held = Items.has(k) ? ItemStack(Items.id(k), 1) : .empty }
        func animal(_ k: MobKind, _ q: Int8, at p: V3? = nil) -> Mob {
            let m = Mob(k, at: p ?? base + V3(0, 0, -3)); m.peltQ = q; return m
        }

        // Items, values and the quality table.
        let pelts = Hunting.animals.flatMap { a in (1...3).map { Hunting.peltKey(a, $0) } }
        check(pelts.allSatisfy { Items.has($0) } && Hunting.legends.allSatisfy { Items.has($0.pelt) && Items.has($0.trophy) }
              && ["game_meat", "cooked_game_meat", "perch", "trout", "pike", "catfish", "cooked_fish", "hunters_map", "hunters_satchel",
                  "fur_chestplate"].allSatisfy { Items.has($0) },
              "hunting: \(pelts.count) pelts (5 species x poor/good/perfect), 4 legendary pelts and trophies, meat, fish, fur, satchels")
        let ordered = Hunting.animals.allSatisfy { a in
            let v = (1...3).map { Economy.value[Hunting.peltKey(a, $0)] ?? 0 }
            return v[0] < v[1] && v[1] < v[2] && Economy.buysItem(.butcher, Items.id(Hunting.peltKey(a, 3)))
        }
        check(ordered && (Economy.value["legend_pelt_bear"] ?? 0) > (Economy.value["bear_pelt_perfect"] ?? 0),
              "hunting: the butcher buys every pelt, priced poor < good < perfect < legendary (fox \(Economy.value["fox_pelt_poor"] ?? 0)/\(Economy.value["fox_pelt_good"] ?? 0)/\(Economy.value["fox_pelt_perfect"] ?? 0) cents)")
        var counts = [0, 0, 0, 0]
        for _ in 0..<2000 { counts[Hunting.quality(Mob(.rabbit, at: base))] += 1 }
        check(abs(counts[1] - 600) < 100 && abs(counts[2] - 1000) < 110 && abs(counts[3] - 400) < 90,
              "hunting: quality rolls poor \(counts[1]), good \(counts[2]), perfect \(counts[3]) of 2000")
        let fits: [(HuntWeapon, GameSize, Int)] = [(.arrow, .small, 0), (.pistol, .small, 0), (.rifle, .small, 1), (.shotgun, .small, 2),
                                                    (.rifle, .medium, 0), (.heavy, .medium, 2), (.rifle, .large, 0), (.pistol, .large, 1),
                                                    (.melee, .large, 1), (.none, .medium, 2)]
        check(fits.allSatisfy { $0.0.loss($0.1) == $0.2 } && HuntWeapon.of(ItemStack(Items.id("gun_sniper"), 1)) == .rifle
              && HuntWeapon.of(ItemStack(Items.id("bow"), 1)) == .arrow, "hunting: right tools by size (bow/pistol small, rifle medium/large; shotguns and launchers ruin)")

        // Clean kills.
        func kill(_ k: MobKind, _ q: Int8, _ weapon: String, hits: Int, player: Bool = true) -> (Bool, Int) {
            Hunting.bodies = []
            let m = animal(k, q)
            hold(weapon)
            for _ in 0..<hits { m.provoke(g) }
            m.killedByPlayer = player
            let made = Hunting.died(g, m)
            return (made, Hunting.bodies.last?.quality ?? 0)
        }
        let clean = kill(.fox, 3, "bow", hits: 1), shotgun = kill(.fox, 3, "gun_shotgun", hits: 1), sword = kill(.fox, 3, "iron_sword", hits: 2)
        let sprayed = kill(.wolf, 3, "gun_rifle", hits: 6), sniper = kill(.polarBear, 3, "gun_sniper", hits: 2)
        let blast = kill(.goat, 3, "bow", hits: 0), wild = kill(.rabbit, 3, "bow", hits: 1, player: false)
        check(clean == (true, 3) && shotgun.1 == 1 && sword.1 == 2 && sprayed.1 == 1 && sniper.1 == 3 && blast.1 == 1 && !wild.0,
              "hunting: a perfect fox stays perfect to one arrow (\(clean.1)); shotgun \(shotgun.1), sword \(sword.1); a wolf sprayed 6 times \(sprayed.1); a bear in 2 Farsight rounds \(sniper.1); no hit of yours \(blast.1); not your kill leaves no body")
        let pet = animal(.wolf, 3); pet.owner = true; pet.killedByPlayer = true
        let cub = animal(.fox, 3); cub.baby = true; cub.killedByPlayer = true
        check(!Hunting.died(g, pet) && !Hunting.died(g, cub) && !Hunting.isGame(pet) && !Hunting.isGame(cub), "hunting: tamed and baby animals aren't game")

        // The body lies on its side (lower and wider than the animal standing).
        Hunting.bodies = []
        let wolf = animal(.wolf, 2, at: base + V3(0, 0, -2.5))
        hold("bow"); wolf.provoke(g); wolf.killedByPlayer = true
        _ = Hunting.died(g, wolf)
        Hunting.bodyMobs = Hunting.bodies.map { $0.mob }
        func extent(_ list: [Mob], _ m: Mob) -> (Float, Float, Int) {
            let cap = 8192
            let buf = UnsafeMutablePointer<MobVert>.allocate(capacity: cap)
            defer { buf.deallocate() }
            let eye = m.pos + V3(0, 1.6, 4)
            let n = writeMobVertices(list, eye: eye, daylight: 1, world: g.world, into: buf, capacity: cap)
            var top: Float = -99, bottom: Float = 99
            for i in 0..<n { let y = buf[i].pos.y + eye.y - m.pos.y; top = max(top, y); bottom = min(bottom, y) }
            return (top, bottom, n)
        }
        let keepBodies = Hunting.bodyMobs
        Hunting.bodyMobs = []
        let standing = extent([Mob(.wolf, at: wolf.pos)], wolf)
        Hunting.bodyMobs = keepBodies
        let lying = extent([], Hunting.bodies[0].mob)
        check(lying.2 > 0 && lying.0 < standing.0 * 0.75 && lying.1 > -0.05,
              String(format: "hunting: the body is drawn on its side (top %.2f vs %.2f standing, %d vertices, resting on the ground at %.2f)", lying.0, standing.0, lying.2, lying.1))

        // Skinning: hold use on it.
        g.inventory.main.slots = Array(repeating: .empty, count: g.inventory.main.slots.count)
        g.inventory.selected = 0
        hold("bow")
        g.player.pos = base + V3(0, 0, 0)
        g.target = nil
        let body = Hunting.bodies[0].mob
        let to = simd_normalize(body.pos + V3(0, 0.2, 0) - g.player.eye)
        g.player.yaw = atan2f(-to.x, -to.z); g.player.pitch = asinf(to.y)
        let aimed = Hunting.body(g, under: g.player.eye, g.player.look) != nil
        var started = g.skinUse(true, 0.3), progress = Hunting.skinProgress
        let released = !g.skinUse(false, 0.1) && Hunting.skinProgress == 0
        var steps = 0
        started = g.skinUse(true, 0.1)
        while !Hunting.bodies.isEmpty && steps < 40 { _ = g.skinUse(true, 0.1); steps += 1 }
        progress = Float(steps) * 0.1
        let good = Items.id(Hunting.peltKey(Hunting.animals[2], 2))
        let gotPelt = g.inventory.main.countOf(good) == 1, gotMeat = g.inventory.main.countOf(Items.id("game_meat")) == 2
        check(aimed && started && released && Hunting.bodies.isEmpty && gotPelt && gotMeat && abs(progress - 1.2) < 0.25,
              String(format: "hunting: holding use on a wolf's body skins it in %.1f s (a Good Wolf Pelt and 2 game meat); letting go starts over", progress))

        // Selling and crafting.
        let p = ShopPricing(reputation: 0, hero: 0, honour: 0)
        let poorP = Economy.sellPrice(Items.id("wolf_pelt_poor"), p), goodP = Economy.sellPrice(good, p), perfP = Economy.sellPrice(Items.id("wolf_pelt_perfect"), p)
        check(poorP < goodP && goodP * 2 < perfP, "hunting: the butcher pays \(Money.format(poorP)) / \(Money.format(goodP)) / \(Money.format(perfP)) for a poor / good / perfect wolf pelt")
        let coat = Recipes.all.first { Items.key($0.result.item) == "fur_chestplate" }
        let fine = coat?.cells.compactMap { $0 }.first ?? ""
        check(coat != nil && Recipes.matches(fine, good) && Recipes.matches(fine, Items.id("bear_pelt_perfect")) && !Recipes.matches(fine, Items.id("wolf_pelt_poor"))
              && Recipes.all.contains { Items.key($0.result.item) == "hunters_satchel" } && Recipes.all.contains { Items.key($0.result.item) == "saddle" },
              "hunting: a fur coat takes good or perfect pelts (not poor); satchel and saddle recipes")
        var sat = ItemStack(Items.id("hunters_satchel"), 1)
        for _ in 0..<5 { (sat, _) = Bundles.insert(sat, ItemStack(Items.id("cobblestone"), 64)) }
        check(Bundles.isBundle(sat) && Bundles.fill(sat) == 256 && ArmorLook.color(Items.id("fur_chestplate")) != nil,
              "hunting: a Hunter's Satchel holds \(Bundles.fill(sat)) (a bundle 64); fur is drawn when worn")

        // Studying an animal.
        // (on open ground: the first of four bearings with a clear view)
        g.player.pos = base
        var foxAt = base + V3(0, 0, -10)
        for d in [V3(0, 0, -10), V3(10, 0, 0), V3(0, 0, 10), V3(-10, 0, 0)] {
            let q = base + d
            let at = V3(q.x, Float(g.world.topY(Int(floor(q.x)), Int(floor(q.z))) + 1), q.z)
            if g.world.canSee(g.player.eye, at + V3(0, 0.4, 0)) { foxAt = at; break }
        }
        let fox = animal(.fox, 3, at: foxAt)
        g.mobs.mobs = [fox]
        let tf = simd_normalize(fox.pos + V3(0, fox.height * 0.5, 0) - g.player.eye)
        g.player.yaw = atan2f(-tf.x, -tf.z); g.player.pitch = asinf(tf.y)
        Hunting.aimed = nil; Hunting.shown = nil
        let t0 = g.clock
        let first = Hunting.current(g, now: t0), settled = Hunting.current(g, now: t0 + Hunting.settle + 0.05)
        let line = Hunting.describe(fox)
        check(first == nil && settled === fox && line.contains("perfect") && line.contains("bow"), "hunting: studying a fox reads \"\(line)\" after \(Hunting.settle) s of aim")

        // Legendary animals: dens, the map, the kill.
        let dens = Hunting.dens(g)
        let ranges = dens.map { simd_length(V2(Float($0.x), Float($0.z))) }
        let again = { Hunting.denCache = nil; Hunting.state.dens = nil; return Hunting.dens(g) }()
        check(dens.count == 4 && Set(dens.map { [$0.x, $0.z] }).count == 4 && ranges.allSatisfy { $0 > 300 && $0 < 2000 } && dens == again,
              "hunting: 4 legendary dens, seeded per world, \(ranges.map { Int($0) }) blocks out")
        Hunting.state.revealed = []; Hunting.state.killed = []
        hold("hunters_map")
        let read1 = Hunting.readMap(g), read2 = Hunting.readMap(g)
        check(read1 && read2 && Hunting.state.revealed == [0, 1], "hunting: each Hunter's Map marks the next legend's den on the map (\(Hunting.state.revealed.sorted()))")
        let ash = Hunting.spawnLegend(g, 0, at: base + V3(0, 0, -4))
        check(ash.scale > 1.4 && ash.health == 60 && Hunting.isGame(ash) && Hunting.describe(ash).contains("legendary") && Hunting.live(g, 0) === ash,
              "hunting: \(Hunting.describe(ash)) (x\(ash.scale), \(ash.health) health)")
        Hunting.bodies = []
        hold("gun_shotgun"); ash.provoke(g); ash.killedByPlayer = true
        _ = Hunting.died(g, ash)
        let loot = Hunting.bodies.first.map { Hunting.yield($0) } ?? []
        check(Hunting.state.killed.contains(0) && loot.contains { Items.key($0.item) == "legend_pelt_wolf" } && loot.contains { Items.key($0.item) == "ashen_fang" },
              "hunting: a legend always gives its pelt and trophy (\(loot.map { $0.displayName }.joined(separator: ", "))) and stays dead")
        var d: [String: String] = [:]
        Hunting.state.records["pike"] = 12.5
        Hunting.save(&d)
        Hunting.load(d)
        check(Hunting.state.killed == [0] && Hunting.state.revealed == [0, 1] && Hunting.state.records["pike"] == 12.5 && Hunting.load0(),
              "hunting: legends, revealed dens and fish records survive a save")
        let rec = animal(.goat, 3).record
        check(Mob.from(rec)?.peltQ == 3, "hunting: an animal's quality is saved with it")

        // Fishing: species by water, weights, the fight.
        let sea = (0..<400).map { _ in Fishing.species[Fishing.pick(.ocean, night: false)].key }
        let lake = (0..<400).map { _ in Fishing.species[Fishing.pick(.plains, night: false)].key }
        let reef = (0..<400).filter { _ in Fishing.species[Fishing.pick(.warmOcean, night: false)].key == "tropical_fish" }.count
        check(!sea.contains("perch") && !lake.contains("cod") && Set(lake).count >= 4 && reef > 60,
              "hunting: the sea gives \(Set(sea).sorted()), a lake \(Set(lake).sorted()), a warm sea tropical fish \(reef)/400")
        let pikeS = Fishing.species[2]
        let ws = (0..<300).map { _ in Fishing.weight(pikeS, luck: 0) }
        check(ws.allSatisfy { $0 >= pikeS.minLb && $0 <= pikeS.maxLb } && (ws.max() ?? 0) - (ws.min() ?? 0) > 10, String(format: "hunting: pike weigh %.1f-%.1f lb", ws.min() ?? 0, ws.max() ?? 0))
        func play(_ power: Float, _ bot: (Fishing.Fight) -> Bool) -> Fishing.Outcome {
            let f = Fishing.Fight(species: 2, weight: 20, power: power, line: 16, dir: V3(0, 0, -1))
            for _ in 0..<(120 * 30) {
                let r = Fishing.step(f, reel: bot(f), dt: 1.0 / 30)
                if r != .fighting { return r }
            }
            return .fighting
        }
        let patient = (0..<40).filter { _ in play(1.3) { $0.run <= 0 && $0.tension < 0.8 } == .landed }.count
        let greedy = (0..<40).filter { _ in play(1.3) { _ in true } == .snapped }.count
        let idle = (0..<20).filter { _ in play(0.8) { _ in false } == .escaped }.count
        let perch = (0..<20).filter { _ in play(0.3) { _ in true } == .landed }.count
        check(patient >= 36 && greedy >= 32 && idle == 20 && perch >= 18,
              "hunting: a big pike lands \(patient)/40 for an angler who eases off on runs, snaps \(greedy)/40 reeling non-stop; idle loses it \(idle)/20; a small perch reels straight in \(perch)/20")
        // The fight through the rod: a bite hooked starts it; reeling lands it.
        hold("fishing_rod")
        var hooked = false
        for _ in 0..<30 where !hooked {
            let b = Bobber(g.player.eye + V3(0, -1, -8), .zero, wait: 99)
            b.bite = 1
            g.bobber = b
            _ = g.fishingUse(true, false)
            hooked = g.bobber?.fight != nil
        }
        let landed0 = Fishing.landedCount + Fishing.snapped + Fishing.escaped
        var t = 0
        while let b = g.bobber, let f = b.fight, t < 3000 {
            Fishing.reeling = f.run <= 0 && f.tension < 0.8
            g.fishFightTick(b, f, 1.0 / 30); t += 1
        }
        check(hooked && g.bobber == nil && Fishing.landedCount + Fishing.snapped + Fishing.escaped == landed0 + 1 && (Fishing.lastCatch != nil),
              "hunting: a hooked fish fights on the rod and comes in (\(Fishing.lastCatch.map { String(format: "%@ %.1f lb", $0.0, $0.1) } ?? "none") in \(t / 30) s)")
    }
}

extension Hunting {
    // The tests' save check: a load of nothing starts clean.
    static func load0() -> Bool {
        let keep = state
        load([:])
        let clean = state.killed.isEmpty && state.records.isEmpty
        state = keep
        return clean
    }
}
