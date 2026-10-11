import Foundation
import simd

// The sheriff's six-iron, the iron rule and taking a town (SixIron.swift, TownConquest.swift; docs/status/six-iron.md).
// Run by TownTests.honour (questcheck on the host and `--towns-only`, `--towntests` on the Mac).
//   rule:      the damage table: below iron one shot kills (even on easy), iron takes 3, steel 4+, titanium and
//              Duskium are chip damage; peaceful none. Real rounds against worn sets: leather would kill (a totem
//              pops), iron takes 8 of 20, titanium 1.
//   duel:      every sheriff carries it; his challenge draws it; the first round is a warning over your head; each
//              shot is telegraphed (arm level, a click) and fires at where you were: stand still and it hits, step
//              aside or crawl and it misses; six rounds, then a reload.
//   conquest:  a deputy falling with the sheriff alive changes nothing; the sheriff falling with no law left makes the
//              town surrender (hands up, no hostility, no bounty, -10 honour); then theft there costs nothing, its
//              keepers serve you at their best price even with a grudge, its folk call you boss, tribute is paid on
//              arrival ($6 a day, 7 days at most), a nearby town is wary (called out, heat 2, dearer) for 10 days; it
//              all survives a save round trip.
extension TownTests {
    static func sixIron(_ g: Game, _ check: (Bool, String) -> Void) {
        let savedArmor = g.inventory.armor.slots, savedOff = g.inventory.offhand[0], savedDiff = g.difficulty
        let savedMobs = g.mobs.mobs, savedPos = g.player.pos, savedHealth = g.health, savedMoney = g.money, savedTime = g.time
        let savedCrawl = g.player.crawling
        defer {
            for i in 0..<4 { g.inventory.armor[i] = savedArmor[i] }
            g.inventory.offhand[0] = savedOff; g.difficulty = savedDiff; g.mobs.mobs = savedMobs; g.player.pos = savedPos
            g.health = savedHealth; g.alive = true; g.money = savedMoney; g.time = savedTime; g.player.crawling = savedCrawl
            g.effects.clear(); g.absorption = 0
            if g.menu != nil { g.closeMenu() }
            TownLaw.forceTown = nil; TownLaw.reset()
        }
        ironRule(g, check)
        duel(g, check)
        conquest(g, check)
    }

    static func wear(_ g: Game, _ mat: String?) {
        let set = mat.map { SixIron.fullSet($0) } ?? Array(repeating: ItemStack.empty, count: 4)
        for i in 0..<4 { g.inventory.armor[i] = set[i] }
    }

    static func ironRule(_ g: Game, _ check: (Bool, String) -> Void) {
        let t = SixIron.table()
        let row = Dictionary(uniqueKeysWithValues: t.map { ($0.0, $0.2) })
        print("six-iron table (normal): " + t.map { String(format: "%@ %.2f -> %@", $0.0, $0.1, $0.2 == SixIron.lethal ? "dead" : "\($0.2)") }.joined(separator: "; "))
        let soft = ["no armour", "leather", "golden", "chainmail", "copper"]
        check(soft.allSatisfy { row[$0] == SixIron.lethal }, "iron rule: below iron one round kills (\(soft.map { "\($0) \(row[$0] ?? -1)" }.joined(separator: ", ")))")
        let iron = row["iron"] ?? 0, steel = row["steel"] ?? 0
        check(iron * 3 >= 20 && iron * 2 < 20, "iron rule: a full iron set takes \(iron) a round: three shots kill")
        check(steel < iron && steel * 3 < 20 && steel * 6 >= 20, "iron rule: steel takes \(steel) a round: 4-6 shots")
        check((row["titanium"] ?? 99) <= 1 && (row["Duskium"] ?? 99) <= 1, "iron rule: titanium and Duskium take chip damage (\(row["titanium"] ?? -1), \(row["Duskium"] ?? -1))")
        let leather = SixIron.armourScore(SixIron.fullSet("leather")), ti = SixIron.armourScore(SixIron.fullSet("diamond"))
        check(SixIron.damage(score: leather, difficulty: 1) == SixIron.lethal && SixIron.damage(score: leather, difficulty: 0) == 0
              && SixIron.damage(score: ti, difficulty: 3) == 2,
              "iron rule: still one shot on easy below iron; nothing on peaceful; titanium 2 on hard")
        // Iron with leather boots is iron; iron without boots isn't.
        var mixed = SixIron.fullSet("iron"); mixed[3] = SixIron.fullSet("leather")[3]
        var bare = SixIron.fullSet("iron"); bare[3] = .empty
        check(SixIron.tier(SixIron.armourScore(mixed)) == .iron && SixIron.tier(SixIron.armourScore(bare)) == .soft,
              String(format: "iron rule: iron with leather boots counts as iron (%.2f), iron with bare feet doesn't (%.2f)",
                     SixIron.armourScore(mixed), SixIron.armourScore(bare)))
        // Real rounds against worn armour.
        TownLaw.reset(); TownLaw.forceTown = true
        g.survival = true; g.alive = true; g.difficulty = 2; g.blocking = false; g.effects.clear(); g.absorption = 0
        let sheriff = townPerson(g, groundSpot(g) + V3(4, 0, 0), tag: "sheriff")
        func shot(_ mat: String?, totem: Bool = false) -> Int {
            wear(g, mat); g.health = 20; g.alive = true; g.effects.clear(); g.absorption = 0
            g.inventory.offhand[0] = totem && Items.has("totem_of_undying") ? ItemStack(Items.id("totem_of_undying"), 1) : .empty
            g.sixIronHit(by: sheriff, at: g.player.eye)
            return g.health
        }
        let leatherLeft = shot("leather", totem: true)
        check(leatherLeft == 1 && g.inventory.offhand[0].isEmpty && g.alive, "iron rule: a round in leather is lethal (the totem took it: \(leatherLeft) left)")
        let ironLeft = shot("iron"), tiLeft = shot("diamond")
        check(ironLeft == 12 && tiLeft == 19, "iron rule: a round in iron leaves 12 of 20 (\(ironLeft)), in titanium 19 (\(tiLeft))")
        g.difficulty = 0
        check(shot(nil) == 20, "iron rule: peaceful, no harm")
        g.difficulty = 2
        g.inventory.offhand[0] = .empty
    }

    static func duel(_ g: Game, _ check: (Bool, String) -> Void) {
        TownLaw.reset(); TownLaw.forceTown = true
        g.survival = true; g.alive = true; g.difficulty = 2; g.blocking = false; g.player.crawling = false
        // Every sheriff carries it.
        let tags = (0..<10).compactMap { i in Mob.structureMob("villager:sheriff", at: g.player.pos + V3(Float(i) * 5.1, 0, 2)) }
        check(tags.count == 10 && tags.allSatisfy { $0.townWeapon == .revolver }, "six-iron: every sheriff carries it (\(tags.filter { $0.townWeapon == .revolver }.count)/\(tags.count))")
        // A sheriff with a clear line to the player, 10 blocks off.
        let base = groundSpot(g)
        var spot: V3?
        for k in 0..<16 {
            let a = Float(k) * .pi / 8
            let p = V3(base.x + cosf(a) * 10, 0, base.z + sinf(a) * 10)
            let q = V3(p.x, Float(g.world.topY(Int(floor(p.x)), Int(floor(p.z))) + 1), p.z)
            if abs(q.y - base.y) < 3 && g.world.canSee(q + V3(0, 1.5, 0), base + V3(0, 1.5, 0)) { spot = q; break }
        }
        guard let at = spot else { check(false, "six-iron: a clear line for the duel near the spawn"); return }
        let s = townPerson(g, at, tag: "sheriff")
        g.mobs.mobs = [s]
        g.player.pos = base
        wear(g, "iron")
        // His challenge draws the gun (the town turns on you).
        TownLaw.turnHostile(g, TownLaw.town(of: s, g), at: base, witness: s)
        let drawn = s.town.drawn > 0
        let parts = townsfolkParts(s, swing: 0).count
        s.town.drawn = 0
        check(drawn && parts >= 30, "six-iron: the challenge draws it (\(parts) parts with the gun out)")
        s.town.anger = 60
        func round(dodge: (() -> Void)? = nil) -> (aimed: Bool, hit: Bool) {
            g.health = 20; g.alive = true; g.player.pos = base; g.player.crawling = false
            s.attackCooldown = 0; s.town.reload = 0
            _ = s.townDefend(0.05, g)
            let aimed = s.town.aim > 0
            dodge?()
            _ = s.townDefend(SixIron.aimTime + 0.05, g)
            return (aimed, g.health < 20)
        }
        let w0 = SixIron.warnings
        let first = round()
        check(first.aimed && !first.hit && SixIron.warnings == w0 + 1, "six-iron: the first round is a warning over your head (telegraphed \(first.aimed), hit \(first.hit))")
        let arm = townsfolkParts(s, swing: 0)
        var standHits = 0, dodgeHits = 0, proneHits = 0, telegraphed = 0
        for _ in 0..<10 { let r = round(); if r.hit { standHits += 1 }; if r.aimed { telegraphed += 1 } }
        // Six rounds fired so far: he reloads.
        let reloading = s.town.reload > 0
        let side = simd_normalize(simd_cross(V3(at.x - base.x, 0, at.z - base.z), V3(0, 1, 0)))
        for _ in 0..<10 {
            let r = round { g.player.pos = base + side * 1.3 }
            if r.hit { dodgeHits += 1 }
        }
        for _ in 0..<10 {
            let r = round { g.player.crawling = true }
            if r.hit { proneHits += 1 }
        }
        g.player.crawling = false
        check(telegraphed == 10 && standHits >= 9, "six-iron: every shot is telegraphed; standing still, \(standHits)/10 hit")
        check(dodgeHits == 0 && proneHits <= 1, "six-iron: a step aside dodges it (\(dodgeHits)/10 hit), crawling too (\(proneHits)/10)")
        check(reloading, "six-iron: six rounds, then a reload")
        check(!arm.isEmpty, "six-iron: the model builds mid-duel")
        g.player.pos = base
    }

    static func conquest(_ g: Game, _ check: (Bool, String) -> Void) {
        TownLaw.reset(); TownLaw.forceTown = true
        g.survival = true; g.alive = true; g.difficulty = 2
        let base = groundSpot(g)
        g.player.pos = base
        g.time = 4.3 * DAY_LENGTH
        let keeper = keeper(g, .general, at: base + V3(2, 0, 0))
        let sheriff = townPerson(g, base + V3(-3, 0, 0), tag: "sheriff")
        let deputy = townPerson(g, base + V3(-3, 0, 3), tag: "deputy")
        let town = TownLaw.town(of: keeper, g)
        for m in [sheriff, deputy] { if var v = m.villager { v.town = town; m.villager = v } }
        g.mobs.mobs = [keeper, sheriff, deputy]
        TownLaw.state.hostile[town] = 100
        Honour.value = 0
        func kill(_ m: Mob) { m.killedByPlayer = true; m.playerHurtAt = g.clock; m.health = 0; g.mobDied(m) }
        kill(deputy)
        check(!TownConquest.owns(town), "conquest: a deputy down with the sheriff standing changes nothing")
        let h0 = Honour.value
        kill(sheriff)
        check(TownConquest.owns(town) && !TownLaw.isHostile(town) && Honour.bounty(town) == 0 && keeper.town.handsUp > 0,
              "conquest: the sheriff down and no law left, \(town) surrenders (hands up, no hostility, no bounty)")
        check(Honour.value <= h0 - 25 - TownConquest.honourCost + 0.01, String(format: "conquest: it costs honour (%.0f -> %.0f)", h0, Honour.value))
        // Yours: theft is free, the keeper serves you at the best price even with a grudge.
        let heat0 = TownLaw.heat(town), hv = Honour.value
        TownLaw.offence(g, heat: 5, at: keeper.pos)
        check(TownLaw.heat(town) == heat0 && !TownLaw.isHostile(town) && Honour.value == hv, "conquest: taking from your own town is no crime")
        let owned = ShopPricing(reputation: -200, hero: 0, honour: -50, town: .owned), plain = ShopPricing(reputation: -200, hero: 0, honour: -50)
        check(!owned.refuses && plain.refuses && owned.buyMult < plain.buyMult && owned.buyMult >= Economy.minBuyMult && owned.sellMult <= Economy.maxSellMult
              && owned.sellMult < owned.buyMult, String(format: "conquest: your town's keepers serve you even with a grudge, x%.2f (x%.2f in a town that won't serve you)", owned.buyMult, plain.buyMult))
        if var v = keeper.villager { v.addGossip(.majorNeg, 60); keeper.villager = v }
        g.time = 4.4 * DAY_LENGTH
        _ = g.talkToTownsperson(keeper)
        check(g.menu is ShopMenu, "conquest: the keeper opens the counter for you")
        if g.menu != nil { g.closeMenu() }
        check(TownConquest.greet(g, keeper, keeper.villager!), "conquest: your townsfolk call you boss")
        // Tribute on arrival: 3 days' worth, then the 7-day cap.
        g.money = 0
        g.time = 7.4 * DAY_LENGTH
        TownConquest.greetedVisit = nil
        TownConquest.tick(g, town: town)
        let three = g.money
        TownConquest.tick(g, town: town)
        g.time = 30.4 * DAY_LENGTH
        TownConquest.greetedVisit = nil
        TownConquest.tick(g, town: town)
        check(three == 3 * TownConquest.tributePerDay && g.money == three + TownConquest.tributeCap * TownConquest.tributePerDay,
              "conquest: tribute on arrival (\(Money.format(three)) for 3 days, once a visit, \(Money.format(g.money - three)) after 23 days: capped at 7)")
        // A town nearby is wary for 10 days.
        let other = "Elsewhere Creek"
        TownLaw.state.owned?[town] = [Int(base.x), Int(base.z), Int(g.time / DAY_LENGTH) - 2, Int(g.time / DAY_LENGTH)]
        TownConquest.warnedVisit = nil
        TownConquest.tick(g, town: other)
        let wary = TownConquest.standing(other) == .wary && TownLaw.heat(other) >= 2
        let dear = ShopPricing(reputation: 0, hero: 0, town: .wary).buyMult > ShopPricing(reputation: 0, hero: 0).buyMult
        g.time += Double(TownConquest.waryDays) * DAY_LENGTH
        TownConquest.warnedVisit = nil
        TownConquest.tick(g, town: other)
        check(wary && dear && TownConquest.standing(other) == .none, "conquest: a town nearby is on edge (heat \(TownLaw.heat(other)), dearer) until the news is \(TownConquest.waryDays) days old")
        // Saved.
        let data = try? JSONEncoder().encode(TownLaw.state)
        let back = data.flatMap { try? JSONDecoder().decode(TownLaw.Saved.self, from: $0) }
        check(back?.owned?[town] != nil && back?.owned?[town] == TownLaw.state.owned?[town], "conquest: the town stays yours through a save")
        // An old save (no owned field) still loads.
        let old = try? JSONDecoder().decode(TownLaw.Saved.self, from: Data(#"{"heat":{},"hostile":{},"appointed":{},"placed":[]}"#.utf8))
        check(old != nil && old?.owned == nil, "conquest: a save from before it loads")
    }
}
