import Foundation
import simd

// The gap pass on honour (docs/status/cloud-gap-pass.md, area H). Run by HonourTests (TownTests.run: questcheck and
// `questcheck --towns-only`; the Mac's --towntests).
//   log:      every change is logged with its reason; the log is capped and saved.
//   meter:    a change pulses the HUD meter (bigger, then settling) and shows the reason under it.
//   deeds:    fair trades earn a little, capped per day; donations earn 2 each, 6 a day; jobs pay money and honour.
//   tiers:    an outlaw is fought on sight (the armed come after 3 s, the unarmed run), refused service everywhere,
//             and can surrender to the law for a fine (back to Disreputable); the disreputable are warned off; the
//             respected get tips about places nearby and are greeted by name; the honourable get one gift a town a day.
//   board:    two jobs a day per town (stable for the day), deliveries paid under shop prices, a hunt counted by kills
//             near town, an outlaw who shows up where he was seen and pays once killed; the screen fits its panel.
//   posters:  the WANTED boards in a town show your poster while you're wanted there, the old notice otherwise.
//   hunters:  wanted out in the wild, a posse of named hunters spawns near you and hunts you; killing one earns
//             no honour; nobody is sent while you're clean or in town.
extension TownTests {
    static func honourGap(_ g: Game, _ check: (Bool, String) -> Void) {
        let savedMobs = g.mobs.mobs, savedPos = g.player.pos, savedMoney = g.money, savedTime = g.time
        let savedChance = BountyHunters.chancePerSecond
        defer {
            g.mobs.mobs = savedMobs; g.player.pos = savedPos; g.money = savedMoney; g.time = savedTime
            if g.menu != nil { g.closeMenu() }
            TownLaw.forceTown = nil; TownLaw.reset()
            Honour.tipChance = 0.25; Honour.giftChance = 0.5; BountyHunters.chancePerSecond = savedChance   // (R21: was left at 1/240)
        }
        TownLaw.reset(); TownLaw.forceTown = true; g.survival = true
        let base = groundSpot(g)
        g.player.pos = base
        g.mobs.mobs = []
        g.time = 5.3 * DAY_LENGTH

        // Log and meter.
        Honour.change(g, -4, "a test of the log")
        check(Honour.log.last.map { $0.amount == -4 && $0.why == "a test of the log" && $0.day == 5 } == true,
              "honour gap: a change is logged with its day and reason (\(TownLaw.state.honourLog?.last ?? "none"))")
        for i in 0..<(Honour.logCap + 10) { Honour.change(g, i % 2 == 0 ? 1 : -1, "spam \(i)") }
        check(Honour.log.count == Honour.logCap, "honour gap: the log keeps the last \(Honour.logCap) (\(Honour.log.count))")
        var d: [String: String] = [:]
        TownLaw.save(&d); TownLaw.load(d, seed: g.world.seed)
        check(Honour.log.count == Honour.logCap, "honour gap: the log survives a save round trip")
        TownLaw.reset(); TownLaw.forceTown = true
        Honour.change(g, 3, "you helped a test")
        let L = HudLayout(1280, 720)
        let now = HonourHUD.lines(g, L)
        let clock0 = g.clock
        Honour.changedAt = clock0 - 2
        let later = HonourHUD.lines(g, L)
        check((now.first?.scale ?? 0) > (later.first?.scale ?? 1) && now.contains { $0.text == "you helped a test" }
              && later.contains { $0.text == "you helped a test" },
              String(format: "honour gap: the meter pulses on a change (scale %.2f -> %.2f) and shows the reason", now.first?.scale ?? 0, later.first?.scale ?? 0))

        // Fair trades, capped.
        TownLaw.reset(); TownLaw.forceTown = true
        let keeper = keeper(g, .general, at: base + V3(2, 0, 0))
        g.mobs.mobs = [keeper]
        g.money = 100_000
        g.time = 5.3 * DAY_LENGTH
        for _ in 0..<12 { _ = Shop.buy(g, keeper, .general, index: 0, count: 1) }
        check(Honour.value == Honour.dailyCap["trade"], "honour gap: fair trades earn honour, \(Honour.dailyCap["trade"] ?? 0) a day at most (\(Honour.value) after 12)")

        // Outlaws: on sight, refused, surrender.
        TownLaw.reset(); TownLaw.forceTown = true
        let farmer = townPerson(g, base + V3(4, 0, 0)), elder = townPerson(g, base + V3(-4, 0, 1))
        if var v = farmer.villager { v.role = "farmer"; farmer.villager = v }
        if var v = elder.villager { v.role = "elder"; elder.villager = v }
        let sheriff = townPerson(g, base + V3(0, 0, 5), tag: "sheriff")
        let town = TownLaw.town(of: farmer, g)
        for m in [keeper, elder, sheriff] { if var v = m.villager { v.town = town; m.villager = v } }
        g.mobs.mobs = [keeper, farmer, elder, sheriff]
        Honour.value = -80
        TownLaw.lastTick = -1; TownLaw.tick(g)
        let early = farmer.town.anger
        Honour.outlawSpotted = (town, g.clock - 4)
        TownLaw.lastTick = g.clock - 2; TownLaw.tick(g)
        check(early <= 0 && farmer.town.anger > 0 && elder.panic > 0,
              "honour gap: an outlaw is fought on sight after a 3 s warning (farmer anger \(early) -> \(farmer.town.anger), elder runs \(elder.panic > 0))")
        farmer.town.anger = 0; sheriff.town.anger = 0
        g.time = 5.3 * DAY_LENGTH
        _ = g.talkToTownsperson(keeper)
        check(!(g.menu is ShopMenu), "honour gap: no keeper serves an outlaw")
        if g.menu != nil { g.closeMenu() }
        g.money = 1200
        _ = g.talkToTownsperson(sheriff)
        check(g.money == 200 && Honour.value == Honour.outlaw + 5 && !Honour.isOutlaw,
              "honour gap: an outlaw surrenders to the law for a \(Money.format(Honour.outlawFine)) fine and is Disreputable again (\(Honour.value))")
        if g.menu != nil { g.closeMenu() }

        // Disreputable: warned. Respected: tips, name. Honourable: one gift a town a day.
        let said = Honour.greet(g, farmer, farmer.villager!)
        check(said, "honour gap: the disreputable are warned off when greeted")
        TownLaw.state.playerName = "Wren"
        Honour.value = 40
        Honour.tipChance = 1
        let tip = Honour.tip(g, from: base)
        // P50: the first respected greeting in a country tells what its hills are rich in (the map shows it after).
        let ctry = Countries.of(g, town: TownLaw.town(of: farmer, g), near: farmer.pos)
        Countries.state.learned = nil
        let knew = Countries.knows(ctry)
        _ = Honour.greet(g, farmer, farmer.villager!)
        check(!knew && Countries.knows(ctry), "honour gap P50: \(ctry.name)'s riches are unknown until a townsperson tells the respected (told: \(Countries.knows(ctry)))")
        let tips0 = Honour.tipsGiven
        _ = Honour.greet(g, farmer, farmer.villager!)
        check(tip != nil && Honour.tipsGiven == tips0 + 1, "honour gap: the respected are told where things are (\"\(tip ?? "no tip")\")")
        Honour.value = 80
        Honour.giftChance = 1; Honour.tipChance = 0
        g.drops.items = []
        let gifts0 = Honour.giftsGiven
        _ = Honour.greet(g, farmer, farmer.villager!)
        _ = Honour.greet(g, elder, elder.villager!)
        check(Honour.giftsGiven == gifts0 + 1 && g.drops.items.count == 1,
              "honour gap: the honourable get one gift a town a day (\(Honour.giftsGiven - gifts0) given, \(g.drops.items.count) dropped)")
        g.time += DAY_LENGTH
        _ = Honour.greet(g, elder, elder.villager!)
        check(Honour.giftsGiven == gifts0 + 2, "honour gap: and another the next day")
        g.drops.items = []

        // The notice board: jobs, donations, the screen.
        TownLaw.reset(); TownLaw.forceTown = true
        g.mobs.mobs = [sheriff]
        g.time = 7.3 * DAY_LENGTH
        let anchor = IVec3(Int(floor(base.x)), Int(floor(base.y)), Int(floor(base.z)))
        let j1 = TownBoard.jobs(g, town, anchor: anchor), j2 = TownBoard.jobs(g, town, anchor: anchor)
        check(j1.count == 2 && j1.map(\.kind) == j2.map(\.kind) && j1.map(\.count) == j2.map(\.count),
              "honour gap: two jobs a day per town, the same all day (\(j1.map { "\($0.kind) \($0.count)" }.joined(separator: ", ")))")
        // Every delivery over many days pays under what any shop asks and over what any shop pays.
        var bad: [String] = []
        var kinds = Set<String>()
        for day in 0..<200 { for slot in 0..<2 {
            let j = TownBoard.make("Cedar Ford", day, slot)
            kinds.insert(j.kind)
            guard j.kind == "deliver", let k = j.item, let v = Economy.value[k] else { continue }
            let each = Float(j.pay) / Float(j.count)
            if each >= Float(v) * Economy.minBuyMult || each <= Float(v) * Economy.maxSellMult { bad.append("\(k) \(each)") }
        } }
        check(bad.isEmpty && kinds == ["deliver", "hunt", "outlaw"], "honour gap: deliveries pay between shop buy and sell prices; all three job kinds come up" + (bad.isEmpty ? "" : " (\(bad.prefix(3)))"))
        // Do one of each by hand.
        func job(_ kind: String) -> (Int, TownJob)? {
            for day in 7..<60 {
                g.time = (Double(day) + 0.3) * DAY_LENGTH
                let js = TownBoard.jobs(g, town, anchor: anchor)
                if let i = js.firstIndex(where: { $0.kind == kind && !$0.taken }) { return (i, js[i]) }
            }
            return nil
        }
        g.money = 0
        if let (i, j) = job("deliver"), let key = j.item {
            _ = g.inventory.add(ItemStack(Items.id(key), j.count))
            let h0 = Honour.value
            let r = TownBoard.use(g, town, i, anchor: anchor)
            check(r.1 && g.money == j.pay && Honour.value == h0 + j.honour && TownBoard.jobs(g, town, anchor: anchor)[i].paid,
                  "honour gap: a delivery of \(j.count) \(key) pays \(Money.format(j.pay)) and \(j.honour) honour (\(r.0))")
        } else { check(false, "honour gap: a delivery job comes up") }
        if let (i, j) = job("hunt") {
            _ = TownBoard.use(g, town, i, anchor: anchor)
            for _ in 0..<j.count { let z = Mob(.zombie, at: base + V3(10, 0, 0)); z.killedByPlayer = true; g.mobDied(z) }
            let far = Mob(.zombie, at: base + V3(300, 0, 0)); far.killedByPlayer = true; g.mobDied(far)
            let st = TownBoard.jobs(g, town, anchor: anchor)[i]
            let m0 = g.money
            let r = TownBoard.use(g, town, i, anchor: anchor)
            check(st.done && st.progress == j.count && r.1 && g.money == m0 + j.pay, "honour gap: a hunt counts \(st.progress) of \(j.count) kills near town (not far off) and pays")
        } else { check(false, "honour gap: a hunt job comes up") }
        if let (i, j) = job("outlaw") {
            let msg = TownBoard.use(g, town, i, anchor: anchor).0
            let t = TownBoard.jobs(g, town, anchor: anchor)[i]
            let dist = t.target.map { simd_length(V2(Float($0[0] - anchor.x), Float($0[1] - anchor.z))) } ?? 0
            check(t.taken && dist >= 78 && dist <= 142 && msg.contains("blocks"), "honour gap: an outlaw job says where he was last seen (\(msg))")
            // P474: taking him is following him: the HUD marker, and W on the map where he was seen.
            let tr = Waymarks.current(g)
            Waymarks.tick(g)
            let mark = MapCache.shared.marks.first { $0.kind == "outlaw" }
            let mOff = mark.map { abs($0.x - t.target![0]) + abs($0.z - t.target![1]) } ?? 99
            check(tr?.kind == "outlaw" && mOff <= 8 && Waymarks.hud(g) != nil,
                  "honour gap (P474): the taken outlaw is followed (\(tr?.name ?? "-")) and marked on the map (\(mark == nil ? "no mark" : "\(mOff) off"))")
            // Near where he was seen, he turns up with his gang.
            let spot = V3(Float(t.target![0]) + 0.5, 0, Float(t.target![1]) + 0.5)
            g.player.pos = V3(spot.x + 10, base.y, spot.z)
            _ = g.world.loadSync(center: g.player.pos, radius: 3)
            g.player.pos.y = Float(g.world.topY(Int(floor(g.player.pos.x)), Int(floor(g.player.pos.z))) + 1)
            TownBoard.tick(g)
            let boss = g.mobs.mobs.first { $0.customName == j.outlaw }
            check(boss != nil && g.mobs.mobs.contains { $0.customName == "\(j.outlaw ?? "")'s Gang" }, "honour gap: \(j.outlaw ?? "the outlaw") shows up with his gang")
            // Verifier 2026-10-11: he turns up once (no respawn loop); a name-tagged stand-in doesn't count.
            let n1 = g.mobs.mobs.count
            TownBoard.tick(g); TownBoard.tick(g)
            let fake = Mob(.chicken, at: spot); fake.customName = j.outlaw; fake.killedByPlayer = true; g.mobDied(fake)
            check(g.mobs.mobs.count == n1 && boss?.posse == 1 && !TownBoard.jobs(g, town, anchor: anchor)[i].done,
                  "honour gap: he shows up once, and a chicken name-tagged \(j.outlaw ?? "") doesn't finish the job")
            // P474: once he's out, the marker follows the man; dead, it points back to the board that pays.
            Waymarks.cache = (-1e9, nil)
            let onHim = boss.map { b in Waymarks.current(g).map { simd_length($0.pos - b.pos) < 0.5 } ?? false } ?? false
            if let b = boss { b.killedByPlayer = true; g.mobDied(b) }
            Waymarks.cache = (-1e9, nil)
            let home = Waymarks.current(g)
            let homeOff = home.map { abs(Int(floor($0.pos.x)) - anchor.x) + abs(Int(floor($0.pos.z)) - anchor.z) } ?? 99
            check(onHim && home?.kind == "outlaw" && homeOff <= 1,
                  "honour gap (P474): the marker follows \(j.outlaw ?? "him") (\(onHim)), then points to the board (\(home?.name ?? "-"))")
            g.player.pos = base
            let m0 = g.money
            let r = TownBoard.use(g, town, i, anchor: anchor)
            check(r.1 && g.money == m0 + j.pay, "honour gap: bringing him in pays \(Money.format(j.pay))")
            // Another day's outlaw drowns before you get to him: the job's off, unpaid, and he doesn't come back.
            if let (i2, j2) = job("outlaw") {
                _ = TownBoard.use(g, town, i2, anchor: anchor)
                let t2 = TownBoard.jobs(g, town, anchor: anchor)[i2]
                g.player.pos = V3(Float(t2.target![0]) + 10.5, base.y, Float(t2.target![1]) + 0.5)
                _ = g.world.loadSync(center: g.player.pos, radius: 3)
                g.mobs.mobs = []
                TownBoard.tick(g)
                if let b2 = g.mobs.mobs.first(where: { $0.posse == 1 }) {
                    b2.killedByPlayer = false; g.mobDied(b2)
                    g.mobs.mobs = []
                    TownBoard.tick(g)
                    let st = TownBoard.jobs(g, town, anchor: anchor)[i2]
                    let m1 = g.money
                    let r2 = TownBoard.use(g, town, i2, anchor: anchor)
                    check(st.done && st.paid && !r2.1 && g.money == m1 && g.mobs.mobs.isEmpty,
                          "honour gap: \(j2.outlaw ?? "an outlaw") dead by other means ends the job unpaid, no respawn (\(r2.0))")
                } else { check(false, "honour gap: the second outlaw shows up") }
                g.player.pos = base
            }
        } else { check(false, "honour gap: an outlaw job comes up") }
        // Donations: 2 each, 6 a day.
        TownLaw.state.honourGains = [:]
        g.money = 10_000
        let board = NoticeBoardMenu(game: g, town: town, anchor: anchor)
        let h0 = Honour.value
        for _ in 0..<5 {
            if let i = board.items.firstIndex(where: { if case .donate = $0 { return true }; return false }) {
                board.scroll = 0
                if board.rows[i].enabled { board.pressed(i) }
            }
        }
        check(Honour.value == h0 + 6 && g.money == 10_000 - 3 * TownBoard.donation,
              "honour gap: donations earn 2 honour each, 6 a day (\(Honour.value - h0) for \(Money.format(10_000 - g.money)))")
        // Your name.
        if let i = board.items.firstIndex(where: { if case .name = $0 { return true }; return false }) { board.pressed(i) }
        check(TownBoard.playerName != "Stranger", "honour gap: the board picks your name (\(TownBoard.playerName))")
        // The screen fits, with the longest names and a full log.
        TownLaw.state.playerName = "Frankie"
        Honour.addBounty(g, "Juniper Crossing", 99_999); Honour.addBounty(g, "Silver Junction", 1500)
        for i in 0..<6 { Honour.change(g, -1, "theft, unseen \(i) and a longer reason to fit") }
        let big = NoticeBoardMenu(game: g, town: "Juniper Crossing", anchor: anchor)
        big.status = "Paid $99.99. Juniper Crossing won't forget it."
        let over = big.overflow()
        check(over.isEmpty && big.rows.count >= 9, "honour gap: the notice board fits its panel at every scroll (\(big.rows.count) rows)" + (over.isEmpty ? "" : ": \(over.prefix(3))"))

        // Posters.
        TownLaw.reset(); TownLaw.forceTown = true
        let p = IVec3(Int(floor(base.x)) + 2, Int(floor(base.y)) + 1, Int(floor(base.z)))
        let be = g.world.entity(p, .sign)
        be.lines = TownBoard.oldPoster
        g.world.blockEntities[p] = be
        TownLaw.state.playerName = "Kit"
        Honour.addBounty(g, town, 1500)
        TownBoard.posters(g, town: town)
        let wanted = be.lines
        Honour.clearBounty(town)
        TownBoard.posters(g, town: town)
        check(wanted == ["WANTED", "Kit", "Dead or Alive", "$15.00"] && be.lines == TownBoard.oldPoster,
              "honour gap: a town's WANTED board shows your poster while you're wanted (\(wanted.joined(separator: " / ")))")
        // An outlaw's poster shows what surrendering costs (the bounty plus the fine); a player's own WANTED sign is
        // left alone.
        let mine = g.world.entity(IVec3(p.x + 1, p.y, p.z), .sign)
        mine.lines = ["WANTED", "my lost dog", "brown, small", ""]
        g.world.blockEntities[IVec3(p.x + 1, p.y, p.z)] = mine
        Honour.value = -90
        Honour.addBounty(g, town, 500)
        TownBoard.posters(g, town: town)
        check(be.lines[3] == Money.format(500 + Honour.outlawFine) && mine.lines[1] == "my lost dog",
              "honour gap: an outlaw's poster asks \(be.lines[3]) (bounty + fine); your own WANTED sign is untouched")
        Honour.clearBounty(town); Honour.value = 0
        g.world.blockEntities[p] = nil; g.world.blockEntities[IVec3(p.x + 1, p.y, p.z)] = nil

        // Unseen theft is capped at 10 a day (a town field cleared at night).
        TownLaw.reset(); TownLaw.forceTown = true
        g.mobs.mobs = []
        for _ in 0..<100 { TownLaw.offence(g, heat: 1, at: g.player.eye) }
        check(abs(Honour.value + 10) < 0.01, "honour gap: unseen theft costs at most 10 honour a day (\(Honour.value) after 100)")
        // The inventory shows the meter (and the wallet) wherever you are.
        TownLaw.reset(); TownLaw.forceTown = nil; TownLaw.inTown = nil
        g.openMenu(InventoryMenu(game: g))
        let hud = HonourHUD.lines(g, HudLayout(1280, 800)).map(\.text) + Wallet.lines(g, HudLayout(1280, 800)).map(\.text)
        g.closeMenu()
        check(hud.contains { $0.hasPrefix("Honour: ") } && hud.contains { $0.hasPrefix("$") }, "honour gap: the inventory shows your honour and wallet (\(hud.joined(separator: ", ")))")

        // Bounty hunters.
        TownLaw.reset(); TownLaw.forceTown = nil
        g.mobs.mobs = []
        g.player.pos = base
        TownLaw.inTown = nil
        BountyHunters.chancePerSecond = 1
        BountyHunters.lastPosse = -1e9
        FactionRaids.lastAssault = -1e9                    // (P215: no posse within 90 minutes of any check's assault)
        BountyHunters.tick(g)
        check(!g.mobs.mobs.contains { $0.customName == BountyHunters.name }, "honour gap: no hunters for someone with a clean name")
        Honour.value = -90
        // Where the posse can stand depends on the random ring of tries around the player (water, sight lines); a fixed
        // seed keeps this check from turning on whatever other checks drew from Rand before it (it failed after the sky
        // checks, PR #26, drew a few more numbers).
        Rand.seed(12345)
        BountyHunters.tick(g)
        // (O8: the first tick sets a party on the trail far off; brought to 50 blocks, the posse rides in.)
        if BountyHunters.party != nil { TownLaw.state.trackers = [g.player.pos.x + 50, g.player.pos.z, 600]; BountyHunters.tick(g) }
        let hunters = g.mobs.mobs.filter { $0.customName == BountyHunters.name }
        // (P88: a bigger posse, from 30-42 blocks out, so it rides in.)
        // (R21: two to four on the soldier AI, riding in on an order to where he is.)
        let near = hunters.allSatisfy { simd_length($0.pos - g.player.pos) < 50 && $0.brain?.order != nil }
        let why: String = hunters.count >= 2 ? "" : " [party \(BountyHunters.party.map { "\(Int($0.x - g.player.pos.x)),\(Int($0.y - g.player.pos.z))" } ?? "none"), "
            + "survival \(g.survival), difficulty \(g.difficulty), dim \(g.dim.dim), in town \(TownLaw.inTown != nil), won \(Reckoning.won), worth \(BountyHunters.worthHunting()), "
            + "below \(BountyHunters.below(g)), hunters day \(TownLaw.state.huntersDay ?? -99) today \(Int(g.time / DAY_LENGTH)), mobs \(g.mobs.mobs.count)]"
        check(hunters.count >= 2 && near, "honour gap: an outlaw in the wild gets \(hunters.count) bounty hunters within 44 blocks, already on the trail" + why)
        let n0 = g.mobs.mobs.count
        BountyHunters.tick(g)
        check(g.mobs.mobs.count == n0, "honour gap: at most one posse a day")
        if let h = hunters.first {
            let before = Honour.value
            h.killedByPlayer = true
            g.mobDied(h)
            check(Honour.value == before, "honour gap: killing a bounty hunter earns no honour")
        }
        // They ride off once you're no longer wanted and they're out of range; never sent on Peaceful.
        Honour.value = 0
        for h in hunters { h.pos = g.player.pos + V3(60, 0, 0) }
        BountyHunters.tick(g)
        check(!g.mobs.mobs.contains { $0.posse == 3 }, "honour gap: hunters leave once you're no longer wanted")
        g.mobs.mobs = []; Honour.value = -90; TownLaw.state.huntersDay = nil; g.difficulty = 0
        BountyHunters.tick(g)
        check(g.mobs.mobs.isEmpty, "honour gap: no bounty hunters on Peaceful")
        g.difficulty = 2; Honour.value = 0
        g.mobs.mobs = []
    }
}
