import Foundation
import simd

// Honour, bounties, the Sheriff's Revolver and frontier towns (Honour.swift, FrontierTown.swift; docs/status/honour.md).
// Run by TownTests.run (questcheck on the host, `--towntests` on the Mac) and alone by `questcheck --towns-only`.
//   standing: the five standings at their bounds; prices move with honour and never leave the shop bounds the
//             no-arbitrage check relies on, at any reputation, honour or Friend of the Town.
//   crimes:   witnessed theft and assault cost honour, unseen theft doesn't; a town turning on you costs more and puts
//             $5 on your head; murder costs 15 and $15, the sheriff 25 and $25.
//   deeds:    monsters killed near townsfolk raise it, capped per day (a night of farming earns 8, not 20); outlaws in
//             the wild raise it; the cap resets the next day; creative changes nothing.
//   bounty:   keepers in a wanted town won't serve; the sheriff takes payment (not without the money), which ends the
//             hostility and lets the shop open again; an outlaw or a wanted player is challenged once a visit; a
//             bounty lapses after 7 days; honour and bounties survive a save round trip.
//   heat:     cools twice as fast for the honourable, half as fast for an outlaw.
//   revolver: a registered one-handed six-shooter with its own model and icon, bought (not sold) by gunsmiths; a
//             killed sheriff drops it at a 5% rate (20,000 rolls) and always some cartridges; a forced drop is loaded.
//   hud:      the standing shows under the wallet in town, on screen, with the bounty.
//   towns:    generated towns have a sheriff's office (sign, jail bars, WANTED board) and plank boardwalks in front of
//             their shops; a town on ground a save already generated keeps its old lots (no office).
extension TownTests {
    static func honour(_ g: Game, _ makeWorld: () -> World, _ check: (Bool, String) -> Void) {
        let savedMobs = g.mobs.mobs, savedPos = g.player.pos, savedSurvival = g.survival, savedMoney = g.money, savedTime = g.time
        let savedDrops = g.drops.items
        defer {
            g.mobs.mobs = savedMobs; g.player.pos = savedPos; g.survival = savedSurvival; g.money = savedMoney; g.time = savedTime
            g.drops.items = savedDrops
            if g.menu != nil { g.closeMenu() }
            TownLaw.forceTown = nil; TownLaw.reset(); Honour.revolverChance = 0.05
        }
        standings(check)
        honourCrimes(g, check)
        honourDeeds(g, check)
        bounties(g, check)
        revolver(g, check)
        frontierTowns(makeWorld, check)
    }

    static func standings(_ check: (Bool, String) -> Void) {
        let names = [-100, -60, -59, -20, -19, 19, 20, 59, 60, 100].map { Honour.standing(Float($0)) }
        check(names == ["Outlaw", "Outlaw", "Disreputable", "Disreputable", "Neutral", "Neutral", "Respected", "Respected", "Honourable", "Honourable"],
              "honour: standings at their bounds (\(names.joined(separator: ", ")))")
        var out: [String] = []
        for h in stride(from: -100, through: 100, by: 10) { for rep in [-100, -50, 0, 50, 100] { for hero in [0, 1] {
            let p = ShopPricing(reputation: rep, hero: hero, honour: Float(h))
            if p.buyMult < Economy.minBuyMult - 1e-6 || p.buyMult > Economy.maxBuyMult + 1e-6 || p.sellMult < Economy.minSellMult - 1e-6
                || p.sellMult > Economy.maxSellMult + 1e-6 || p.sellMult >= p.buyMult { out.append("h\(h) r\(rep) x\(hero)") }
        } } }
        check(out.isEmpty, "honour: prices stay inside the shop bounds at every honour, reputation and Friend of the Town" + (out.isEmpty ? "" : " (\(out.prefix(5)))"))
        let good = ShopPricing(reputation: 0, hero: 0, honour: 100), neutral = ShopPricing(reputation: 0, hero: 0), bad = ShopPricing(reputation: 0, hero: 0, honour: -100)
        check(good.buyMult < neutral.buyMult && neutral.buyMult < bad.buyMult && good.sellMult > neutral.sellMult && neutral.sellMult > bad.sellMult,
              String(format: "honour: honourable buys at x%.2f, neutral x%.2f, outlaw x%.2f (sells x%.3f / x%.3f / x%.3f)",
                     good.buyMult, neutral.buyMult, bad.buyMult, good.sellMult, neutral.sellMult, bad.sellMult))
    }

    static func townPerson(_ g: Game, _ at: V3, tag: String = "") -> Mob {
        let m = Mob(.villager, at: at); m.home = at
        Townsfolk.setup(m, tag: tag, game: g)
        return m
    }

    static func honourCrimes(_ g: Game, _ check: (Bool, String) -> Void) {
        TownLaw.reset(); TownLaw.forceTown = true; g.survival = true
        let base = groundSpot(g)
        g.player.pos = base
        let spot = base + V3(1, 0.5, 1)
        g.mobs.mobs = []
        TownLaw.offence(g, heat: 1, at: spot)
        check(Honour.value == 0, "honour: unseen theft costs nothing (\(Honour.value))")
        let witness = townPerson(g, base + V3(3, 0, 0))
        g.mobs.mobs = [witness]
        TownLaw.offence(g, heat: 1, at: spot)
        let afterTheft = Honour.value
        check(afterTheft == -1.5, "honour: witnessed theft costs 1.5 a point of heat (\(afterTheft))")
        TownLaw.assault(g, witness)
        let afterAssault = Honour.value
        check(afterAssault < afterTheft, "honour: assault costs honour (\(afterTheft) -> \(afterAssault))")
        let town = TownLaw.town(of: witness, g)
        TownLaw.offence(g, heat: 3, at: spot)        // heat past 4: the town turns
        check(TownLaw.isHostile(town) && Honour.bounty(town) == 500,
              "honour: a town that turns on you puts \(Money.format(Honour.bounty(town))) on your head (honour \(Honour.value))")
        // Murder: the townsperson, then the sheriff.
        let h0 = Honour.value, b0 = Honour.bounty(town)
        let victim = townPerson(g, base + V3(2, 0, 2))
        if var v = victim.villager { v.town = town; victim.villager = v }
        victim.killedByPlayer = true; victim.playerHurtAt = g.clock
        g.mobDied(victim)
        check(Honour.value == max(-100, h0 - 15) && Honour.bounty(town) == b0 + 1500,
              "honour: murder costs 15 and adds $15 (honour \(Honour.value), bounty \(Money.format(Honour.bounty(town))))")
        // A villager the player hurt a minute ago, dying now to something else, isn't murder; nor is a villager
        // killed away from any town (at the player's base: no law there to pay).
        let h1 = Honour.value, b1 = Honour.bounty(town)
        let stale = townPerson(g, base + V3(2, 0, -2)); stale.killedByPlayer = true; stale.playerHurtAt = g.clock - 60
        g.mobDied(stale)
        TownLaw.forceTown = false
        let away = townPerson(g, base + V3(-2, 0, 2)); away.killedByPlayer = true; away.playerHurtAt = g.clock
        g.mobDied(away)
        TownLaw.forceTown = true
        check(Honour.value == h1 && Honour.bounty(town) == b1 && Honour.bounty(TownLaw.town(of: away, g)) == (TownLaw.town(of: away, g) == town ? b1 : 0),
              "honour: an old hit or a villager killed outside any town isn't murder")
        // Creative: nothing changes.
        g.survival = false
        let hc = Honour.value
        TownLaw.offence(g, heat: 1, at: spot)
        Honour.change(g, -10, "test")
        check(Honour.value == hc, "honour: creative changes nothing")
        g.survival = true
    }

    static func honourDeeds(_ g: Game, _ check: (Bool, String) -> Void) {
        TownLaw.reset(); TownLaw.forceTown = true; g.survival = true
        let base = groundSpot(g)
        g.player.pos = base
        let folk = townPerson(g, base + V3(4, 0, 0))
        g.mobs.mobs = [folk]
        TownLaw.inTown = nil
        g.time = 3.6 * DAY_LENGTH
        for _ in 0..<20 {
            let z = Mob(.zombie, at: base + V3(6, 0, 0)); z.killedByPlayer = true
            g.mobDied(z)
        }
        let night = Honour.value
        check(night == Honour.dailyCap["monster"], "honour: 20 monsters killed near townsfolk earn \(night) (the daily cap), not 20")
        g.time = 4.6 * DAY_LENGTH
        let r = Mob(.zombie, at: base + V3(6, 0, 0)); r.killedByPlayer = true; r.raider = true
        g.mobDied(r)
        check(Honour.value == night + 2, "honour: the next day earns again, a raider counts 2 (\(night) -> \(Honour.value))")
        // An outlaw in the wild (no townsfolk about).
        g.mobs.mobs = []
        let o = Mob(.vindicator, at: base + V3(100, 0, 0)); o.killedByPlayer = true
        let before = Honour.value
        g.mobDied(o)
        check(Honour.value == before + 3, "honour: an outlaw killed in the wild earns 3 (\(before) -> \(Honour.value))")
        // A monster far from any town earns nothing.
        let far = Mob(.zombie, at: base + V3(200, 0, 0)); far.killedByPlayer = true
        let b2 = Honour.value
        g.mobDied(far)
        check(Honour.value == b2, "honour: a monster killed far from any town earns nothing")
        // Heat cools faster for the honourable, slower for an outlaw.
        func cooled(_ h: Float) -> Float {
            TownLaw.state.heat = ["Testville": 3]; Honour.value = h
            TownLaw.lastTick = g.clock - 5
            TownLaw.tick(g)
            return 3 - (TownLaw.state.heat["Testville"] ?? 0)
        }
        let c0 = cooled(0), cHi = cooled(80), cLo = cooled(-80)
        check(cHi > c0 * 1.9 && cLo < c0 * 0.6 && c0 > 0, String(format: "honour: heat cools %.3f (honourable %.3f, outlaw %.3f) in 5 s", c0, cHi, cLo))
    }

    static func bounties(_ g: Game, _ check: (Bool, String) -> Void) {
        TownLaw.reset(); TownLaw.forceTown = true; g.survival = true
        let base = groundSpot(g)
        g.player.pos = base
        g.time = 2.3 * DAY_LENGTH
        let keeper = keeper(g, .general, at: base + V3(2, 0, 0))
        let sheriff = townPerson(g, base + V3(-3, 0, 0), tag: "sheriff")
        let town = TownLaw.town(of: keeper, g)
        if var v = sheriff.villager { v.town = town; sheriff.villager = v }
        g.mobs.mobs = [keeper, sheriff]
        // Grudges: the sheriff saw a murder (reputation -250, which alone sets him on you within 10 blocks).
        if var v = sheriff.villager { v.addGossip(.majorNeg, 50); sheriff.villager = v }
        Honour.addBounty(g, town, 2000)
        TownLaw.state.hostile[town] = 60
        _ = g.talkToTownsperson(keeper)
        check(!(g.menu is ShopMenu), "bounty: a keeper in a wanted town won't serve you")
        if g.menu != nil { g.closeMenu() }
        g.money = 1500
        _ = g.talkToTownsperson(sheriff)
        check(Honour.bounty(town) == 2000 && g.money == 1500, "bounty: the sheriff won't take $15.00 for a $20.00 bounty")
        g.money = 2600
        let h0 = Honour.value
        _ = g.talkToTownsperson(sheriff)
        check(Honour.bounty(town) == 0 && g.money == 600 && !TownLaw.isHostile(town) && Honour.value == h0 + 3 && sheriff.town.anger <= 0,
              "bounty: paying the sheriff $20.00 clears it, ends the hostility and earns 3 honour (wallet \(Money.format(g.money)))")
        sheriff.town.think = 0
        _ = sheriff.townDefend(0.6, g)
        check(sheriff.town.anger <= 0 && (sheriff.villager?.reputation ?? -1) >= 0,
              "bounty: once paid, the sheriff lets the old grudge go (reputation \(sheriff.villager?.reputation ?? 0), anger \(sheriff.town.anger))")
        if g.menu != nil { g.closeMenu() }
        g.time = 2.4 * DAY_LENGTH                    // shop hours
        _ = g.talkToTownsperson(keeper)
        check(g.menu is ShopMenu, "bounty: the keeper serves you again once it's paid")
        if g.menu != nil { g.closeMenu() }
        // The law's challenge: once a visit, for a wanted player or an outlaw.
        TownLaw.reset(); TownLaw.forceTown = true
        g.mobs.mobs = [keeper, sheriff]
        Honour.value = -80
        TownLaw.lastTick = -1
        TownLaw.tick(g)
        let first = Honour.challengedVisit
        TownLaw.lastTick = g.clock - 2
        TownLaw.tick(g)
        check(first == town && Honour.challengedVisit == town, "bounty: the law challenges an outlaw on arrival (\(first ?? "nobody"))")
        // Lapse after 7 days.
        Honour.value = 0
        Honour.addBounty(g, town, 500)
        g.time += 6 * DAY_LENGTH
        TownLaw.lastTick = g.clock - 2; TownLaw.tick(g)
        let still = Honour.bounty(town)
        g.time += 1.2 * DAY_LENGTH
        TownLaw.lastTick = g.clock - 2; TownLaw.tick(g)
        check(still == 500 && Honour.bounty(town) == 0, "bounty: lapses after 7 days, not 6 (\(Money.format(still)) on day 6)")
        // Saved and loaded with the town law.
        Honour.value = 42
        Honour.addBounty(g, "Saveton", 750)
        var d: [String: String] = [:]
        TownLaw.save(&d)
        TownLaw.load(d, seed: g.world.seed)
        check(Honour.value == 42 && Honour.bounty("Saveton") == 750, "honour: honour and bounties survive a save round trip")
        // The HUD: the standing (and the bounty) in town, on screen.
        TownLaw.inTown = "Saveton"
        let L = HudLayout(1280, 720)
        let lines = HonourHUD.lines(g, L)
        let text = lines.map(\.text)
        let onScreen = lines.allSatisfy { $0.x >= 0 && $0.x + Float(Font.width($0.text)) * $0.scale <= L.W && $0.y >= 0 }
        check(text.contains("Honour: Respected") && text.contains("Wanted: $7.50") && onScreen, "hud: \(text.joined(separator: " | ")) shown in town, on screen")
        TownLaw.inTown = nil
    }

    static func revolver(_ g: Game, _ check: (Bool, String) -> Void) {
        guard Items.has(Guns.revolverKey) else { check(false, "revolver: registered"); return }
        let id = Items.id(Guns.revolverKey)
        let gi = Guns.index(id)
        let gs = gi.map { Guns.all[$0] }
        check(gi == Guns.revolver && gs?.mag == 6 && Items.def(id).maxStack == 1 && Guns.isHandgun(Guns.revolver),
              "revolver: \(Items.def(id).name) is a six-shot handgun (index \(gi ?? -1))")
        check(CapitalArms.models.count == Guns.all.count && !CapitalArms.models[Guns.revolver].shouldered
              && CapitalArms.models[Guns.revolver].parts.contains { $0.color == CapitalArms.walnut },
              "revolver: its own one-handed model with a walnut grip (\(CapitalArms.models[min(Guns.revolver, CapitalArms.models.count - 1)].parts.count) parts)")
        check(TextureGen.painters()["item_gun_revolver"] != nil, "revolver: has its own icon")
        let sold = ShopKind.allCases.contains { Economy.catalog($0).contains { $0.item == id } }
        check(!sold && Economy.buysItem(.gunsmith, id), "revolver: gunsmiths buy it, nobody sells it")
        // The 5% drop.
        var hits = 0
        let n = 20_000
        for _ in 0..<n where Honour.rollRevolver(Rand.float(in: 0..<1)) { hits += 1 }
        let rate = Float(hits) / Float(n)
        check(abs(Honour.revolverChance - 0.05) < 1e-6 && rate > 0.04 && rate < 0.06, String(format: "revolver: a killed sheriff drops it %.2f%% of the time (20,000 rolls)", rate * 100))
        TownLaw.reset(); TownLaw.forceTown = true; g.survival = true
        let s = townPerson(g, groundSpot(g) + V3(1, 0, 1), tag: "sheriff")
        s.killedByPlayer = true; s.playerHurtAt = g.clock
        g.drops.items = []
        Honour.revolverChance = 1
        g.mobDied(s)
        let gun = g.drops.items.first { $0.stack.item == id }
        let ammo = g.drops.items.first { Items.key($0.stack.item) == "rifle_rounds" }
        check(gun?.stack.tag == 6 && (ammo?.stack.count ?? 0) >= 3, "revolver: a forced drop comes loaded (\(gun?.stack.tag ?? -1)) with \(ammo?.stack.count ?? 0) cartridges")
        Honour.revolverChance = 0
        g.drops.items = []
        let s2 = townPerson(g, groundSpot(g) + V3(1, 0, 1), tag: "sheriff"); s2.killedByPlayer = true; s2.playerHurtAt = g.clock
        g.mobDied(s2)
        check(!g.drops.items.contains { $0.stack.item == id } && g.drops.items.contains { Items.key($0.stack.item) == "rifle_rounds" },
              "revolver: otherwise just cartridges")
        Honour.revolverChance = 0.05
        g.drops.items = []
    }

    static func frontierTowns(_ makeWorld: () -> World, _ check: (Bool, String) -> Void) {
        let w = makeWorld()
        w.renderDistance = 3
        guard let sc = w.gen.structures else { check(false, "frontier: structures"); return }
        var seen: [IVec3] = [], offices = 0, cells = 0, wanted = 0, walks = 0, fronts = 0, visited = 0
        let bars = Blocks.id("iron_bars")
        for _ in 0..<3 {
            guard let s = sc.nearest("village", x: 0, z: 0, maxRegions: 12, accept: { st in !seen.contains { $0 == st.anchor } }) else { break }
            seen.append(s.anchor)
            _ = w.loadSync(center: V3(Float(s.anchor.x), 140, Float(s.anchor.z)), radius: 4)
            visited += 1
            for (p, be) in w.blockEntities where be.kind == .sign && abs(p.x - s.anchor.x) < 80 && abs(p.z - s.anchor.z) < 80 {
                if be.lines.contains("Sheriff") {
                    offices += 1
                    var n = 0
                    for dy in -2...0 { for dz in -8...8 { for dx in -8...8 where w.block(p.x + dx, p.y + dy, p.z + dz) == bars { n += 1 } } }
                    if n >= 6 { cells += 1 }
                }
                if be.lines.first == "WANTED" { wanted += 1 }
                if ShopKind.allCases.contains(where: { be.lines.contains($0.name) }) {
                    fronts += 1
                    let k = Blocks.key(Blocks.groupBase[Int(w.block(p.x, p.y - 3, p.z))])
                    if k.contains("planks") || k.contains("sandstone") { walks += 1 }
                }
            }
        }
        check(visited >= 2 && offices == visited && cells == offices && wanted == offices,
              "frontier: \(visited) towns, \(offices) sheriff's offices, \(cells) with a jail cell, \(wanted) WANTED boards")
        check(fronts > 0 && Float(walks) >= Float(fronts) * 0.75, "frontier: \(walks)/\(fronts) shop fronts have a plank boardwalk")
        // A town on ground a save already generated keeps its old lots.
        guard let first = seen.first else { return }
        let w2 = makeWorld()
        w2.renderDistance = 3
        guard let sc2 = w2.gen.structures else { return }
        var guardSet = Set<Int64>()
        let cx = floorDiv(first.x, CS), cz = floorDiv(first.z, CS)
        for dz in -2...2 { for dx in -2...2 { guardSet.insert(StructureCache.key(cx + dx, cz + dz)) } }
        sc2.legacyFrontier = guardSet
        guard let s2 = sc2.nearest("village", x: first.x, z: first.z, maxRegions: 1) else { check(false, "frontier: guarded town found"); return }
        _ = w2.loadSync(center: V3(Float(s2.anchor.x), 140, Float(s2.anchor.z)), radius: 4)
        let office = w2.blockEntities.contains { $0.value.kind == .sign && $0.value.lines.contains("Sheriff") && abs($0.key.x - s2.anchor.x) < 80 && abs($0.key.z - s2.anchor.z) < 80 }
        check(s2.anchor == first && !office, "frontier: a town on ground a save already generated keeps its old lots (no office)")
    }
}
