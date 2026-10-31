import Foundation
import simd

// The gap pass on towns (docs/status/cloud-gap-pass.md, area T). Run by TownTests.run (questcheck and
// `questcheck --towns-only`; the Mac's --towntests).
//   plans:    frontier towns come in three street plans (crossroads, main street, grid) in every biome style, each a
//             real town (6+ lots).
//   towns:    generated frontier towns have a bank with its banker, "Welcome to <name>" signs and street lamps.
//   bank:     the exchange at $1.20 / $1.00; deposits and withdrawals; interest at 1% a day, capped a day and a week.
//   upgrades: the gunsmith's Upgrade button lists each gun's next upgrade level, takes the money and fits it; maxed or
//             unaffordable upgrades can't be bought.
//   raids:    a town is raided at night (two waves, level I), not again for three days, not while you're wanted there;
//             a won defence pays the town purse and honour.
//   map:      a discovered town is marked under its name; the big map labels it; old unnamed marks get their names.
//   screens:  the bank and the upgrades fit their panels at every scroll position.
extension TownTests {
    static func townGap(_ g: Game, _ makeWorld: () -> World, _ check: (Bool, String) -> Void) {
        let savedMobs = g.mobs.mobs, savedPos = g.player.pos, savedMoney = g.money, savedTime = g.time, savedRaid = g.raid
        let savedMain = (0..<36).map { g.inventory.main[$0] }
        defer {
            g.mobs.mobs = savedMobs; g.player.pos = savedPos; g.money = savedMoney; g.time = savedTime; g.raid = savedRaid
            for j in 0..<36 { g.inventory.main[j] = savedMain[j] }
            if g.menu != nil { g.closeMenu() }
            TownLaw.forceTown = nil; TownLaw.reset()
        }
        TownLaw.reset(); g.survival = true

        // Street plans: every style gets all three, each a real town.
        if let gen = g.world.gen as? WorldGen {
            var seen: [String: Set<Int>] = [:], lots: [String: Int] = [:]
            Village.planLog = { _, _, st, plan, n in
                seen["\(st)", default: []].insert(plan)
                lots["\(st):\(plan)"] = max(lots["\(st):\(plan)"] ?? 0, n)
            }
            let styles: [Village.Style] = [.plains, .desert, .savanna, .taiga, .snowy]
            for st in styles {
                var k = 0
                for i in 0..<400 where (seen["\(st)"]?.count ?? 0) < 3 || k < 6 {
                    let ox = (i % 20) * 544 + 8 - 5000, oz = (i / 20) * 544 + 8 - 5000
                    let cy = gen.groundY(ox, oz)
                    guard cy >= SEA else { continue }
                    if Village.layout(gen, seed: UInt64(i) &* 0x9E3779B97F4A7C15, ox: ox, oz: oz, cy: cy, style: st, frontier: true) != nil { k += 1 }
                }
            }
            // Ground a save had generated before the gap pass (StructureCache.legacyTownsGap): the old crossroads, no bank.
            var oldPlans = Set<Int>(), oldTowns = 0
            Village.planLog = { _, _, _, plan, _ in oldPlans.insert(plan) }
            for i in 0..<120 where oldTowns < 8 {
                let ox = (i % 20) * 544 + 8 - 5000, oz = (i / 20) * 544 + 8 - 5000
                let cy = gen.groundY(ox, oz)
                guard cy >= SEA, Village.layout(gen, seed: UInt64(i) &* 0x9E3779B97F4A7C15, ox: ox, oz: oz, cy: cy, style: .plains,
                                                frontier: true, townsGap: false) != nil else { continue }
                oldTowns += 1
            }
            check(oldTowns > 0 && oldPlans == [0], "town gap: a town on ground saved before the gap pass keeps the crossroads plan (\(oldTowns) towns, plans \(oldPlans.sorted()))")
            Village.planLog = nil
            let missing = styles.filter { seen["\($0)"] != [0, 1, 2] }
            check(missing.isEmpty, "town gap: every biome style lays out all three street plans (" +
                  styles.map { st in "\(st) " + (0...2).map { p in "\(Village.planNames[p]) \(lots["\(st):\(p)"] ?? 0)" }.joined(separator: "/") }.joined(separator: "; ") + " lots at most)")
        } else { check(false, "town gap: the world's generator lays out towns") }

        // Generated frontier towns: the bank and its banker, welcome signs, street lamps.
        let w = makeWorld()
        w.renderDistance = 3
        if let sc = w.gen.structures {
            var bankers = 0, bankSigns = 0, welcome: [String] = [], lamps = 0, towns = 0
            var perTown: [String] = [], townsOK = 0
            var seenA: [IVec3] = []
            let lantern = Blocks.id("lantern")
            for _ in 0..<3 {
                // (C13: hamlets have no bank: towns from a village up)
                guard let s = sc.nearest("village", x: 0, z: 0, maxRegions: 12, accept: { st in !seenA.contains { $0 == st.anchor } && TownSizes.of(st) != .hamlet }) else { break }
                seenA.append(s.anchor)
                w.pendingMobs.removeAll()
                _ = w.loadSync(center: V3(Float(s.anchor.x), 140, Float(s.anchor.z)), radius: 4)
                towns += 1
                let b = w.pendingMobs.filter { $0.0 == "villager:banker" }.count
                bankers += b
                // The name the map and the townsfolk use (Townsfolk.town: the nearest town's anchor).
                let name = Townsfolk.townName(s.anchor.x, s.anchor.z, seed: w.seed)
                var signsHere = 0, bankSignHere = 0
                for (p, be) in w.blockEntities where be.kind == .sign && abs(p.x - s.anchor.x) < 90 && abs(p.z - s.anchor.z) < 90 {
                    if be.lines.contains("BANK") { bankSigns += 1; bankSignHere += 1 }
                    if be.lines.first == "Welcome to" {
                        let n = be.lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
                        welcome.append(n)
                        if n == ShopMenu.fit(name, 88) { signsHere += 1 }
                    }
                }
                perTown.append("\(name) (\(TownSizes.of(s).map { "\($0)" } ?? "old")): bank \(b), signs \(signsHere)")
                if b >= 1 && bankSignHere >= 1 && signsHere >= 1 { townsOK += 1 }
                for dz in -60...60 { for dx in -60...60 {
                    let x = s.anchor.x + dx, z = s.anchor.z + dz
                    for y in (s.anchor.y - 4)...(s.anchor.y + 12) where w.block(x, y, z) == lantern && Blocks.key(w.materialAt(x, y - 1, z)).contains("fence") { lamps += 1 }
                } }
            }
            check(towns >= 3 && bankSigns >= bankers && townsOK == towns,
                  "town gap: every town has a bank (banker and BANK sign) and a \"Welcome to\" sign with the name the map uses (\(perTown.joined(separator: "; ")))")
            check(!welcome.contains { $0.isEmpty }, "town gap: welcome signs carry a name (\(welcome.prefix(4).joined(separator: ", ")))")
            check(lamps >= towns * 3, "town gap: street lamps line the frontier streets (\(lamps) in \(towns) towns)")
        } else { check(false, "town gap: structures") }

        // The bank.
        TownLaw.reset(); TownLaw.forceTown = true
        let base = groundSpot(g)
        g.player.pos = base
        g.time = 3.2 * DAY_LENGTH
        let banker = townPerson(g, base + V3(2, 0, 0), tag: "banker")
        g.mobs.mobs = [banker]
        check(banker.villager?.role == "banker" && banker.townWeapon == .none && banker.activity(0.2) == .work && banker.activity(0.7) == .idle,
              "town gap: the banker works the counter in shop hours, unarmed")
        g.money = 1000
        for j in 0..<36 { g.inventory.main[j] = .empty }
        _ = g.talkToTownsperson(banker)
        let bank = g.menu as? BankMenu
        check(bank != nil, "town gap: talking to the banker opens the bank")
        if let b = bank {
            b.pressed(1); b.pressed(1)                     // buy two emeralds
            let em = g.inventory.main.countOf(Items.id("emerald"))
            check(em == 2 && g.money == 1000 - 2 * Bank.buyEmerald, "town gap: the bank sells emeralds at \(Money.format(Bank.buyEmerald)) (\(em) for \(Money.format(1000 - g.money)))")
            b.pressed(2)
            check(g.inventory.main.countOf(Items.id("emerald")) == 1 && g.money == 1000 - 2 * Bank.buyEmerald + Bank.sellEmerald,
                  "town gap: and buys them at \(Money.format(Bank.sellEmerald))")
            // (R20: stores sell emeralds at a fixed price whatever the discounts, Economy.buyPrice; the bank pays the exchange's dollar.)
            let cheapest = Economy.buyPrice(Items.id("emerald"), ShopPricing(reputation: 1000, hero: 1, honour: 100))
            check(Bank.sellEmerald < cheapest, "town gap: the bank buys an emerald back for less than the cheapest store sells one (\(Money.format(Bank.sellEmerald)) < \(Money.format(cheapest)))")
            let m0 = g.money
            b.pressed(5)                                   // deposit all
            check(g.money == 0 && Bank.balance == m0, "town gap: deposit all puts \(Money.format(m0)) in the bank")
            b.pressed(6)
            check(g.money == 100 && Bank.balance == m0 - 100, "town gap: withdraw $1")
            check(b.overflow().isEmpty, "town gap: the bank fits its panel" + (b.overflow().isEmpty ? "" : " (\(b.overflow().prefix(3)))"))
            g.closeMenu()
        }
        // Interest: 1% a day, capped a day and at a week.
        Bank.balance = 10_000; TownLaw.state.bankDay = 3
        g.time = 5.2 * DAY_LENGTH
        let i2 = Bank.accrue(g)
        Bank.balance = 1_000_000; TownLaw.state.bankDay = 5
        g.time = 40.2 * DAY_LENGTH
        let iBig = Bank.accrue(g)
        check(i2 == 100 + 101 && iBig == Bank.dailyCap * Bank.maxDays, "town gap: savings earn 1% a day (\(Money.format(i2)) in 2 days on $100), at most \(Money.format(Bank.dailyCap)) a day and a week's worth (\(Money.format(iBig)))")
        g.time = 3.7 * DAY_LENGTH
        g.mobs.mobs = [banker]
        _ = g.talkToTownsperson(banker)
        check(!(g.menu is BankMenu), "town gap: the bank is shut at night")
        if g.menu != nil { g.closeMenu() }
        g.time = 3.2 * DAY_LENGTH

        // The gunsmith's upgrades.
        TownLaw.reset(); TownLaw.forceTown = true
        let smith = keeper(g, .gunsmith, at: base + V3(2, 0, 0))
        g.mobs.mobs = [smith]
        for j in 0..<36 { g.inventory.main[j] = .empty }
        let rifle = Items.id(Guns.all[0].key)
        g.inventory.main[0] = ItemStack(rifle, 1)
        g.money = 5000
        let shop = ShopMenu(game: g, keeper: smith, kind: .gunsmith)
        check(shop.extraTitle == "Upgrade", "town gap: the gunsmith's counter has an Upgrade button")
        g.openMenu(shop)
        shop.buttonPressed(ShopMenu.extra)
        if let up = g.menu as? GunUpgradeMenu {
            let rows = up.rows
            let names = rows.map(\.name)
            let fits = names.filter { !$0.hasPrefix("Rework to ") && $0 != "Repair" }       // (O4: grade lifts and repairs head the list)
            check(names.contains("Extended Magazine I") && names.contains("Incendiary Rounds I") && fits.count == GunUpgrades.price.count,
                  "town gap: the upgrades list each gun upgrade's next level (\(names.joined(separator: ", ")))")
            let ix = names.firstIndex(of: "Extended Magazine I") ?? 0
            up.pressed(ix)
            let s = g.inventory.main[0]
            check(Enchant.level(.extendedMag, s) == 1 && g.money == 5000 - 400 && up.rows.map(\.name).contains("Extended Magazine II"),
                  "town gap: buying one fits it ($4.00) and offers the next level (\(up.status))")
            g.money = 100
            let before = g.inventory.main[0].ench
            up.buttonPressed(0)
            check(g.inventory.main[0].ench == before && g.money == 100, "town gap: an upgrade you can't afford isn't fitted")
            var maxed = g.inventory.main[0]
            maxed.ench = Enchant.pack([(.extendedMag, 3), (.quickReload, 3), (.stability, 3), (.penetration, 4), (.incendiary, 1)])
            g.inventory.main[0] = maxed
            check(GunUpgrades.offers(g).isEmpty, "town gap: a fully upgraded gun has nothing left to buy")
            check(up.overflow().isEmpty, "town gap: the upgrades fit their panel")
        } else { check(false, "town gap: Upgrade opens the upgrades") }
        if g.menu != nil { g.closeMenu() }

        // Night raids.
        TownLaw.reset(); TownLaw.forceTown = true
        g.raid = nil
        FactionRaids.lastAssault = -1e9                    // (P215: no assault within 90 minutes of the last one, any check's)
        let folk = (0..<4).map { townPerson(g, base + V3(Float($0), 0, 3)) }
        g.mobs.mobs = folk
        TownLaw.inTown = "Cedar Ford"
        TownRaids.chancePerSecond = 1
        g.time = 8.3 * DAY_LENGTH                           // day: nothing
        TownRaids.tick(g)
        let byDay = g.raid != nil
        g.time = 8.7 * DAY_LENGTH
        Honour.addBounty(g, "Cedar Ford", 500)
        TownRaids.tick(g)
        let wanted = g.raid != nil
        Honour.clearBounty("Cedar Ford")
        TownRaids.tick(g)
        let r = g.raid
        check(!byDay && !wanted && r?.night == true && r?.totalWaves == TownRaids.waves && r?.level == 1,
              "town gap: raiders ride on a town at night (\(r?.totalWaves ?? 0) waves), not by day, not while you're wanted there")
        if let rec = r?.record, let d = try? JSONEncoder().encode(rec), let back = try? JSONDecoder().decode(RaidRecord.self, from: d) {
            let r2 = Raid(back)
            check(r2.night && r2.totalWaves == TownRaids.waves, "town gap: a night raid saves as one")
        }
        g.raid = nil
        g.time = 9.7 * DAY_LENGTH
        TownRaids.tick(g)
        check(g.raid == nil, "town gap: no second raid on the town within three days")
        g.time = 11.7 * DAY_LENGTH
        FactionRaids.lastAssault = -1e9                    // (the clock stood still: the days went by on g.time alone)
        TownRaids.tick(g)
        check(g.raid != nil, "town gap: and another after")
        if let rr = g.raid {
            let m0 = g.money, h0 = Honour.value
            TownRaids.won(g, rr)
            check(g.money == m0 && Honour.value == h0, "town gap: no purse for a player who didn't fight")
            rr.playerKills = 1
            TownRaids.won(g, rr)
            check(g.money == m0 + 500 * TownRaids.waves && Honour.value == h0 + 5, "town gap: a won defence pays the town purse and 5 honour")
            // The victory itself (Raid.raidTick): a night raid gives no Friend of the Town, no omen-raid achievement.
            g.effects.remove(.heroOfTheVillage)
            rr.wave = rr.totalWaves; rr.state = 1; rr.raiders = []; rr.rejoin = 0
            g.raidTick(0.05)
            check(rr.state == 2 && g.effects[.heroOfTheVillage] == nil, "town gap: a night raid's victory gives no Friend of the Town discount")
        }
        g.raid = nil
        // The townsfolk fight raiders beside you: an armed townsperson (the farmer's pitchfork) hits a raider in town.
        do {
            let foe = groundSpot(g) + V3(3, 0, 0)
            let farmer = townPerson(g, base + V3(0, 0, 0))
            var fv = farmer.villager ?? VillagerData(); fv.profession = "farmer"; fv.role = "farmer"; farmer.villager = fv
            let raider = Mob(.vindicator, at: V3(foe.x, Float(g.world.topY(Int(floor(foe.x)), Int(floor(foe.z))) + 1), foe.z))
            raider.raider = true
            g.mobs.mobs = [farmer, raider]
            g.player.pos = base + V3(0, 0, 30)
            let hp0 = raider.health
            for _ in 0..<240 where raider.health > 0 { farmer.update(0.05, game: g) }
            check(farmer.townWeapon != .none && raider.health < hp0, "town gap: an armed townsperson fights a raider (\(farmer.townWeapon), raider \(raider.health)/\(hp0))")
            g.player.pos = base
            g.mobs.mobs.removeAll()
        }
        TownRaids.chancePerSecond = 1.0 / 600
        TownLaw.inTown = nil

        // The map: towns under their names.
        MapCache.shared.resetMarks()
        let town = Townsfolk.town(g, at: base)
        MapCache.shared.discover(g, kind: "village", x: Int(base.x), z: Int(base.z))
        let mark = MapCache.shared.marks.first
        var out: [HudLine] = []
        MapDraw.markers(&out, g, x0: 0, y0: 0, cols: 200, rows: 200, px: 4, wx: base.x, wz: base.z, bpc: 2, s: 2, labels: true)
        var mini: [HudLine] = []
        MapDraw.markers(&mini, g, x0: 0, y0: 0, cols: 200, rows: 200, px: 4, wx: base.x, wz: base.z, bpc: 2, s: 2)
        check(mark?.name == town && out.contains { $0.text == town } && !mini.contains { $0.text == town },
              "town gap: a discovered town is marked as \(mark?.name ?? "?") and the big map names it")
        MapCache.shared.resetMarks()
    }
}
