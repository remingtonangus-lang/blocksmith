import Foundation
import simd

// Town law, the sheriff, the wallet, the emerald exchange, every villager a townsperson, and the voices (run by
// TownTests.run: `--towntests` on the Mac, questcheck on the host). Playtest 2026-10-10 (Quest 0.95): "this guy was
// updated, the rest of them weren't", "I have a wallet... cash up in the side", "an emerald would be a dollar",
// "villagers get real angry when you start stealing... a sheriff that would replace the iron golem", "they speak
// English too", "find a few more lines besides that one".
//   people:  an old-save villager (JSON with no town fields), an egg villager with no data and a newborn are all
//            townsfolk after one MobManager update; a craftsperson opens a cash counter with a Barter button.
//   economy: the emerald exchange ($1.00 / $1.20, any reputation; TownTests.barter checks the offers against it).
//   law:     witnessed theft from a town chest warns and costs standing; unseen or from your own chest doesn't count;
//            breaking town crops does; repeated offences turn the town (the armed fight, the rest run, the sheriff
//            draws after his challenge, keepers won't serve); it calms down again.
//   sheriff: new towns put a sheriff on the square and no golem; townsfolk don't summon golems; a town without one
//            gets one; he carries a revolver, has a man's name and voice, and shoots an outlaw player.
//   wallet:  the HUD shows the cash in town and when it changes (with the change), inside the screen.
//   voices:  every take is packed, decodes, peaks <= -1 dBFS, 0.3-6 s, starts and ends at zero; every voice has
//            every context it needs; lines don't repeat back to back; chatter is throttled.
extension TownTests {
    static func law(_ g: Game, _ makeWorld: () -> World, _ check: (Bool, String) -> Void) {
        let savedMobs = g.mobs.mobs, savedPos = g.player.pos, savedSurvival = g.survival, savedMoney = g.money, savedHealth = g.health
        let savedInv = (0..<36).map { g.inventory.main[$0] }
        defer {
            g.mobs.mobs = savedMobs; g.player.pos = savedPos; g.survival = savedSurvival; g.money = savedMoney; g.health = savedHealth
            for i in 0..<36 { g.inventory.main[i] = savedInv[i] }
            if g.menu != nil { g.closeMenu() }
            TownLaw.forceTown = nil; TownLaw.reset()
        }
        TownLaw.reset()
        everyone(g, check)
        exchange(g, check)
        theft(g, check)
        sheriff(g, makeWorld, check)
        wallet(g, check)
        voices(g, check)
    }

    static func groundSpot(_ g: Game) -> V3 {
        let w = g.world
        let x = g.player.pos.x, z = g.player.pos.z
        return V3(x, Float(w.topY(Int(floor(x)), Int(floor(z))) + 1), z)
    }

    // MARK: Every villager a townsperson

    static func everyone(_ g: Game, _ check: (Bool, String) -> Void) {
        let base = groundSpot(g)
        g.player.pos = base
        let json = String(format: """
            {"k":"villager","p":[%.1f,%.1f,%.1f],"yaw":0,"hp":20,"persistent":true,"home":[%.1f,%.1f,%.1f],
             "villager":{"profession":"librarian","level":2,"xp":12,"type":"taiga","offers":[],"restocksToday":0,"lastRestockDay":-1,
                         "locked":true,"cured":false,"levelUpTimer":0}}
            """, base.x + 2, base.y, base.z, base.x + 2, base.y, base.z)
        let rec = try? JSONDecoder().decode(MobRecord.self, from: Data(json.utf8))
        guard let r = rec, let old = Mob.from(r) else { check(false, "people: an old-save villager record decodes"); return }
        let egg = Mob(.villager, at: base + V3(-2, 0, 0))                // spawn egg / raid / cure: no data at all
        let kid = Mob(.villager, at: base + V3(0, 0, 2)); kid.baby = true
        var kv = VillagerData(); kv.type = "plains"; kid.villager = kv      // a newborn: data without a name
        g.mobs.mobs = [old, egg, kid]
        g.mobs.update(0.05, game: g)
        let all = [old, egg, kid]
        let ok = all.allSatisfy { $0.villager?.person != nil && $0.villager?.town != nil && $0.villager?.role != nil }
        check(ok && old.villager?.profession == "librarian" && old.villager?.level == 2 && kid.villager?.role == "child",
              "people: an old-save villager, an egg villager and a newborn are townsfolk after one update ("
                + all.map { "\($0.villager?.person ?? "?") \($0.villager?.role ?? "?")" }.joined(separator: ", ") + ")")
        // A craftsperson takes money now: a cash counter for their trade, the barter behind a button.
        _ = g.talkToTownsperson(old)
        let sm = g.menu as? ShopMenu
        check(sm?.kind == .general && sm?.hasBarter == true, "people: a librarian opens a cash counter (\(sm?.kind.rawValue ?? "no shop")) with a Barter button")
        if let sm {
            sm.buttonPressed(ShopMenu.barter)
            check(g.menu != nil && !(g.menu is ShopMenu), "people: the Barter button opens the emerald trades (\(g.menu.map { "\(type(of: $0))" } ?? "nothing"))")
        }
        if g.menu != nil { g.closeMenu() }
    }

    // MARK: Emeralds and dollars

    static func exchange(_ g: Game, _ check: (Bool, String) -> Void) {
        let em = Items.id("emerald")
        let prices = [-100, 0, 100].map { (Economy.buyPrice(em, ShopPricing(reputation: $0, hero: 0)), Economy.sellPrice(em, ShopPricing(reputation: $0, hero: 1))) }
        check(prices.allSatisfy { $0 == (Economy.emeraldBuy, Economy.emeraldSell) } && Economy.emeraldSell == 100 && Economy.emeraldBuy > Economy.emeraldSell,
              "economy: one emerald is one dollar (the store pays \(Money.format(Economy.emeraldSell)), sells at \(Money.format(Economy.emeraldBuy)), at any standing)")
        for i in 0..<36 { g.inventory.main[i] = .empty }
        g.inventory.main[0] = ItemStack(em, 5)
        g.money = 0
        let m = keeper(g, .general, at: g.player.pos + V3(2, 0, 0))
        _ = Shop.sell(g, m, .general, item: em, count: 5)
        let sold = g.money
        let idx = Economy.catalog(.general).firstIndex { $0.item == em } ?? -1
        _ = Shop.buy(g, m, .general, index: idx, count: 2)
        check(sold == 500 && g.money == 500 - 2 * Economy.emeraldBuy && count(g, "emerald") == 2,
              "economy: 5 emeralds sell for \(Money.format(sold)) at the general store, 2 buy back for \(Money.format(500 - g.money))")
        // Barter vs shops at that rate: TownTests.barter (economy).
    }

    // MARK: Theft

    static func theft(_ g: Game, _ check: (Bool, String) -> Void) {
        TownLaw.reset()
        TownLaw.forceTown = true
        g.survival = true
        let base = groundSpot(g)
        g.player.pos = base
        let chestAt = IVec3(Int(floor(base.x)) + 1, Int(floor(base.y)), Int(floor(base.z)) + 1)
        func person(_ dx: Float, _ dz: Float, tag: String = "", job: String? = nil) -> Mob {
            let m = Mob(.villager, at: base + V3(dx, 0, dz)); m.home = m.pos
            if let j = job { var v = VillagerData(); v.profession = j; v.locked = true; m.villager = v }
            Townsfolk.setup(m, tag: tag, game: g)
            return m
        }
        func take(_ n: Int) {
            let c = ItemContainer(27)
            c[0] = ItemStack(Items.id("bread"), 20)
            TownLaw.opening(g, chestAt)
            g.openMenu(ChestMenu(game: g, container: c, title: "Chest"))
            var s = c[0]; s.count -= n; c[0] = s
            g.closeMenu()
        }
        // Unseen: nobody about.
        g.mobs.mobs = []
        take(5)
        check(TownLaw.offences == 0, "law: taking from a chest with nobody about isn't noticed")
        // Seen: a warning and lost standing.
        let witness = person(3, 0)
        g.mobs.mobs = [witness]
        let town = TownLaw.town(of: witness, g)
        let rep0 = witness.villager?.reputation ?? 0
        Townsfolk.townLastLine = -100
        take(5)
        let warned = Townsfolk.townLastLine == g.clock
        check(TownLaw.heat(town) >= 1 && TownLaw.heat(town) < 2 && (witness.villager?.reputation ?? 0) < rep0 && warned && !TownLaw.isHostile(town),
              String(format: "law: a witnessed theft warns (heat %.1f, standing %d -> %d)", TownLaw.heat(town), rep0, witness.villager?.reputation ?? 0))
        // Your own chest: nothing.
        let h0 = TownLaw.heat(town)
        TownLaw.placed(g, chestAt)
        take(5)
        check(TownLaw.heat(town) == h0, "law: taking from a chest you placed isn't theft")
        TownLaw.placedSet.remove(chestAt)
        // Trampling town crops in sight.
        let wheat = Blocks.id("wheat")
        TownLaw.broke(g, chestAt + IVec3(1, 0, 0), wheat)
        check(TownLaw.heat(town) > h0, String(format: "law: breaking town crops in sight counts (heat %.1f)", TownLaw.heat(town)))
        TownLaw.broke(g, chestAt + IVec3(2, 0, 0), Blocks.id("short_grass"))
        let h1 = TownLaw.heat(town)
        check(h1 < TownLaw.hostileHeat, "law: picking grass in town doesn't")
        // Keep at it: the town turns.
        let farmer = person(-3, 0, job: "farmer")
        let elder = person(0, 3); if var v = elder.villager { v.role = "elder"; elder.villager = v }
        let sheriff = person(0, -4, tag: "sheriff")
        let shop = keeper(g, .general, at: base + V3(4, 0, 4))
        g.mobs.mobs = [witness, farmer, elder, sheriff, shop]
        take(20)
        take(20)
        check(TownLaw.isHostile(town) && farmer.town.anger > 0 && elder.panic > 0 && TownLaw.pending.contains { $0.0 === sheriff },
              String(format: "law: repeated theft turns the town (heat %.1f; farmer angry %.0f s, elder runs, the sheriff calls his challenge)", TownLaw.heat(town), farmer.town.anger))
        let pr = ShopPricing(reputation: shop.villager?.reputation ?? 0, hero: 0)
        _ = g.talkToTownsperson(shop)
        check(pr.buyMult > 1 && !(g.menu is ShopMenu), String(format: "law: prices go up (x%.2f) and the keeper won't serve while the town is hostile", pr.buyMult))
        if g.menu != nil { g.closeMenu() }
        // The sheriff draws once his challenge is out.
        TownLaw.pending = TownLaw.pending.map { ($0.0, g.clock - 1) }
        TownLaw.tick(g)
        check(sheriff.town.anger > 0, "law: the sheriff draws after his challenge")
        // It blows over.
        TownLaw.state.hostile[town] = 0.5
        TownLaw.lastTick = g.clock - 2
        TownLaw.tick(g)
        check(!TownLaw.isHostile(town) && TownLaw.heat(town) <= 1, "law: the town calms down when its anger runs out")
        // Saved with the world.
        TownLaw.state.heat[town] = 2.5
        TownLaw.placed(g, chestAt)
        let d = g.saveExtra()
        TownLaw.reset()
        g.loadExtra(d)
        check(TownLaw.heat(town) == 2.5 && TownLaw.placedSet.contains(chestAt), "law: heat and your placed blocks are saved with the world")
        TownLaw.placedSet.remove(chestAt)
        TownLaw.forceTown = nil
    }

    // MARK: The sheriff

    static func sheriff(_ g: Game, _ makeWorld: () -> World, _ check: (Bool, String) -> Void) {
        // A structure sheriff: role, revolver, a man's name and the sheriff's voice.
        var men = 0, n = 0
        for i in 0..<12 {
            guard let m = Mob.structureMob("villager:sheriff", at: g.player.pos + V3(Float(i) * 7.3, 0, Float(i) * 3.1)) else { continue }
            n += 1
            if m.villager?.role == "sheriff" && m.townWeapon == .revolver && !Townsfolk.isWoman(m.villager) && TownVoice.voice(m) == "sheriff" { men += 1 }
        }
        check(n == 12 && men == 12, "sheriff: \(men)/\(n) structure sheriffs carry a revolver, have a man's name and the sheriff's voice")
        let parts = Mob.structureMob("villager:sheriff", at: g.player.pos).map { townsfolkParts($0, swing: 0).filter { $0.mn.x.isFinite && $0.mx.y.isFinite }.count } ?? 0
        check(parts >= 30, "sheriff: the model builds (\(parts) parts, star and hat)")
        // Townsfolk no longer summon golems.
        let base = groundSpot(g)
        var group: [Mob] = []
        for i in 0..<6 {
            let m = Mob(.villager, at: base + V3(Float(i % 3), 0, Float(i / 3))); m.home = m.pos
            Townsfolk.setup(m, game: g); m.sleptAt = g.time; m.golemSeenAt = -1000
            group.append(m)
        }
        g.mobs.mobs = group
        group[0].spawnGolemIfNeeded(g, needed: 3)
        check(!g.mobs.mobs.contains { $0.kind == .ironGolem }, "sheriff: townsfolk don't summon iron golems")
        // Townsfolk living away from any town (a villager at your base) don't get one.
        TownLaw.reset()
        TownLaw.forceTown = false
        g.player.pos = base
        TownLaw.tick(g)
        check(!g.mobs.mobs.contains { $0.villager?.role == "sheriff" }, "sheriff: none is sent to villagers living outside a town")
        // A town without a sheriff gets one.
        TownLaw.reset()
        TownLaw.forceTown = true
        TownLaw.tick(g)
        let sent = g.mobs.mobs.filter { $0.villager?.role == "sheriff" }
        check(sent.count == 1 && TownLaw.inTown != nil, "sheriff: a town without one gets a sheriff (\(sent.first?.villager?.person ?? "none") in \(TownLaw.inTown ?? "?"))")
        TownLaw.lastTick = g.clock - 2
        TownLaw.tick(g)
        check(g.mobs.mobs.filter { $0.villager?.role == "sheriff" }.count == 1, "sheriff: only one is sent")
        TownLaw.forceTown = nil
        // He shoots an outlaw.
        if let s = sent.first {
            g.survival = true; g.health = 20
            s.pos = base + V3(6, 0, 0); s.home = s.pos
            g.player.pos = base
            g.mobs.mobs = [s]
            s.town.anger = 30
            for _ in 0..<200 { s.update(0.05, game: g); if g.health < 20 { break } }
            check(g.health < 20, "sheriff: shoots an outlaw player (health \(g.health))")
            g.health = 20
        }
        // New towns: the sheriff on the square, no golem.
        let w = makeWorld()
        w.renderDistance = 3
        if let sc = w.gen.structures, let st = sc.nearest("village", x: 0, z: 0, maxRegions: 12) {
            w.pendingMobs.removeAll()
            _ = w.loadSync(center: V3(Float(st.anchor.x), 140, Float(st.anchor.z)), radius: 4)
            let names = w.pendingMobs.map { $0.0 }
            check(names.contains("villager:sheriff") && !names.contains("iron_golem"),
                  "sheriff: a new town puts a sheriff on the square, no iron golem (\(names.filter { $0 == "villager:sheriff" }.count) sheriff, \(names.filter { $0 == "iron_golem" }.count) golems)")
        } else {
            check(false, "sheriff: a village to look at")
        }
    }

    // MARK: Wallet

    static func wallet(_ g: Game, _ check: (Bool, String) -> Void) {
        let L = HudLayout(1280, 800)
        let hud = HudExtras.enabled, menu = g.menu
        HudExtras.enabled = true; g.menu = nil                     // the harness turns HUD extras off
        defer { HudExtras.enabled = hud; g.menu = menu }
        g.money = 1250
        TownLaw.inTown = nil
        _ = Wallet.lines(g, L)
        let away = Wallet.lines(g, L)
        TownLaw.inTown = "Test Town"
        let town = Wallet.lines(g, L)
        TownLaw.inTown = nil
        g.money += 150
        let changed = Wallet.lines(g, L)
        let inside = (town + changed).allSatisfy { $0.x >= 0 && $0.x + Float(Font.width($0.text)) * $0.scale <= L.W && $0.y >= 0 && $0.y < L.H / 2 }
        check(away.isEmpty && town.first?.text == "$12.50" && changed.contains { $0.text == "+$1.50" } && changed.contains { $0.text == "$14.00" } && inside,
              "wallet: shown in town (\(town.first?.text ?? "-")) and when it changes (\(changed.map { $0.text }.joined(separator: " "))), hidden otherwise, inside the top of the screen")
    }

    // MARK: Voices

    static func voices(_ g: Game, _ check: (Bool, String) -> Void) {
        let takes = TownVoice.takes
        check(TownVoice.loaded >= takes.count && TownVoice.bankBytes < 6_000_000,
              String(format: "voices: %d/%d takes packed (%.2f MB)", TownVoice.loaded, takes.count, Double(TownVoice.bankBytes) / 1e6))
        var bad: [String] = [], secs = 0.0, peak: Float = 0
        for (i, t) in takes.enumerated() {
            let x = TownVoice.render(i)
            let p = x.reduce(0) { max($0, abs($1)) }
            peak = max(peak, p)
            let s = Double(x.count) / SoundBank.rate
            secs += s
            if x.isEmpty || p > 0.891 || p < 0.1 || s < 0.3 || s > 6 || abs(x.first ?? 1) > 0.02 || abs(x.last ?? 1) > 0.02 { bad.append("\(t.voice) '\(t.text)'") }
        }
        check(bad.isEmpty, String(format: "voices: every take decodes, peaks <= -1 dBFS (loudest %.1f dBFS), 0.3-6 s, starts and ends at zero (%.0f s in all)", 20 * log10(max(1e-6, peak)), secs)
              + (bad.isEmpty ? "" : ": " + bad.prefix(4).joined(separator: ", ")))
        // Coverage: every voice has what its people need.
        var gaps: [String] = []
        for v in TownVoice.voices.keys {
            var need: [TownVoice.Ctx] = [.greet, .chatter, .night, .bye, .theft, .angry, .hurt]
            if v.hasPrefix("keeper") || v.hasPrefix("chef") || v.hasPrefix("folk") || v.hasPrefix("farmer") { need += [.trade, .broke] }
            if v.hasPrefix("sheriff") || v.hasPrefix("deputy") { need.append(.challenge) }
            for c in need where (TownVoice.index[v]?[c] ?? []).isEmpty { gaps.append("\(v) \(c.rawValue)") }
        }
        var perCtx: [String] = []
        for c in TownVoice.Ctx.allCases {
            let n = Set(takes.filter { $0.ctx == c }.map { $0.text }).count
            if n < 6 { perCtx.append("\(c.rawValue) \(n)") }
        }
        check(gaps.isEmpty && perCtx.isEmpty, "voices: every voice covers its contexts, 6+ different lines per context"
              + (gaps.isEmpty && perCtx.isEmpty ? "" : ": " + (gaps + perCtx).prefix(6).joined(separator: ", ")))
        // People get the right voice; lines don't repeat back to back; a spoken line plays its take with a caption.
        let a = keeper(g, .butcher, at: g.player.pos), b = keeper(g, .general, at: g.player.pos)
        check(TownVoice.voice(a).hasPrefix("chef") && TownVoice.voice(b).hasPrefix("keeper"), "voices: the butcher speaks as a cook, the storekeeper as a keeper")
        var last = "", repeats = 0
        for _ in 0..<30 { let l = TownVoice.line(.chatter, b)?.0 ?? ""; if l == last { repeats += 1 }; last = l }
        check(repeats == 0, "voices: no line twice running (\(repeats) repeats in 30)")
        let played0 = TownVoice.played
        g.mobs.mobs = [b]
        Townsfolk.townLastLine = -100
        let said = TownVoice.speak(g, b, .greet) ?? ""
        let id = TownVoice.takeID[TownVoice.hashKey(TownVoice.voice(b), said)] ?? -1
        check(TownVoice.played == played0 + 1 && (Snd.voice(id).caption(positional: true) ?? "").hasSuffix(said),
              "voices: a spoken line plays its take with a caption (\(Snd.voice(id).caption(positional: true) ?? "none"))")
        // Ambient chatter waits its turn.
        Townsfolk.townLastLine = g.clock
        let before = TownVoice.played + TownVoice.murmured
        for _ in 0..<50 { TownLaw.lastAmbient = -100; TownLaw.ambientChatter(g) }
        check(TownVoice.played + TownVoice.murmured == before, "voices: no chatter within 20 s of the last line")
    }
}
