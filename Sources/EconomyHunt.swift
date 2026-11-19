import Foundation
import Metal
import simd

// Bug hunt round (a), Fable's job 14 (questcheck --economy-hunt-only): shops, the bank and money on death, played on
// five towns of the headset's worlds through the game's own paths (talking to the keeper opens the counter; its rows
// are pressed as he presses them; the bank's rows likewise; a death through Game.die and back through respawn).
// Every fault found is printed as its own line, "economy hunt: FAULT ...", and the check fails while any is left.
//   every keeper:  opens the counter in hours, keeps it shut out of hours, shuts it when he walks off; a buy takes the
//                  price shown and gives the thing; selling it back pays less than it cost (no loop); gold sells at its
//                  face; gold he carries pays and the change lands in the wallet; a meal or treatment takes its price.
//   the bank:      opens in hours, shut at night; a deposit moves money from the wallet to savings and back; three
//                  days away pay the interest on walking in; an emerald bought and sold back loses.
//   a death:       the wallet goes, the bank's savings stay, his gold lies in the death chest with his things, the death
//                  screen names both; after respawning he has nothing on him.
enum EconomyHunt {
    static let seeds: [UInt64] = [12345, 3084501862406496736, 7780452129890778212]
    static let towns = 5

    static func run(device: MTLDevice, check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let newWorlds0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        let rules0 = (WorldRules.p44, TownSizes.on, World.fewerLakesUnsaved, World.lessWaterUnsaved)
        WorldRules.p44 = true; TownSizes.on = true; World.fewerLakesUnsaved = true; World.lessWaterUnsaved = true
        let test0 = Settings.shared.testMode
        Settings.shared.testMode = false
        let rep0 = FactionRep.rep, law0 = TownLaw.state
        defer {
            FieldTerrain.newWorlds = newWorlds0
            (WorldRules.p44, TownSizes.on, World.fewerLakesUnsaved, World.lessWaterUnsaved) = rules0
            Settings.shared.testMode = test0
            FactionRep.rep = rep0; TownLaw.state = law0
        }
        var faults: [String] = []
        var played: [String] = []
        var counters = 0, buys = 0, sells = 0, banks = 0, deaths = 0
        let gold = Items.id("gold_ingot"), nugget = Items.id("gold_nugget"), emerald = Items.id("emerald")
        for seed in seeds where played.count < towns {
            let w = World(seed: seed, device: device, save: nil)
            w.renderDistance = 4; w.activeDistance = 4
            w.makeFieldWorld()
            let g = Game(world: w, save: nil, persistent: false)
            g.smoothTerrain = true; SmoothTerrain.use(world: true, world: w)
            g.paused = false; g.survival = true; g.difficulty = 0
            TownLaw.reset()
            guard let sc = w.gen.structures else { faults.append("seed \(seed): no structures"); continue }
            var seen: [IVec3] = []
            for _ in 0..<2 where played.count < towns {
                guard let s = sc.nearest("village", x: 0, z: 0, maxRegions: 12, accept: { st in !seen.contains { $0 == st.anchor } && TownSizes.of(st) != .hamlet }) else { break }
                seen.append(s.anchor)
                // In town at noon: his things cleared, the game played two seconds so the town's people stand at their posts.
                g.time = (Double(Int(g.time / DAY_LENGTH)) + 1.25) * DAY_LENGTH
                let sq = V3(Float(s.anchor.x) + 0.5, Float(((w.gen as? WorldGen)?.groundY(s.anchor.x, s.anchor.z) ?? 130) + 1), Float(s.anchor.z) + 0.5)
                g.player.pos = sq
                _ = w.loadSync(center: sq, radius: 5)
                g.player.pos = w.freeSpawn(sq)
                for _ in 0..<40 { g.health = 20; g.tick(0.05) }
                let folk = g.mobs.mobs.filter { $0.kind == .villager && $0.health > 0 && !$0.baby && simd_length($0.pos - sq) < 110 }
                let keepers = folk.filter { $0.villager?.shopKind != nil }
                let bankers = folk.filter { $0.villager?.role == "banker" }
                let name = keepers.first?.villager?.town ?? bankers.first?.villager?.town ?? "town at \(s.anchor.x) \(s.anchor.z)"
                var note = "\(name): \(keepers.count) keepers (\(Set(keepers.compactMap { $0.villager?.shopKind?.rawValue }).sorted().joined(separator: "/"))), \(bankers.count) banker"
                if keepers.isEmpty { faults.append("\(name): no shopkeeper in the town") }
                func fault(_ s: String) { faults.append("\(name): " + s) }
                func clearPack() { for c in [g.inventory.main, g.inventory.armor, g.inventory.offhand] { for i in 0..<c.count { c[i] = .empty } } }
                func stand(by m: Mob) {
                    let d = simd_normalize(V3(g.player.pos.x - m.pos.x, 0, g.player.pos.z - m.pos.z) + V3(1e-3, 0, 1e-3))
                    g.player.pos = w.freeSpawn(m.pos + d * 1.6)
                    if simd_length(g.player.pos - m.pos) > 6 { g.player.pos = m.pos + V3(0, 0, 0) }
                    g.player.vel = .zero
                }
                func at(_ f: Double) { g.time = (Double(Int(g.time / DAY_LENGTH)) + f) * DAY_LENGTH }
                func setWallet(_ c: Int) { g.townWallet = c }

                // Every counter, one keeper of each kind.
                var doneKinds = Set<String>()
                var lastStep = "the walk into town"
                for m in keepers {
                    guard let v = m.villager, let k = v.shopKind, !doneKinds.contains(k.rawValue) else { continue }
                    doneKinds.insert(k.rawValue)
                    let who = "\(k.name) (\(v.person ?? "keeper"))"
                    if let d = g.menu as? DeathMenu { fault("he died during \(lastStep): \(d.message)"); d.buttonPressed(0) }
                    lastStep = "nothing yet at \(who)"
                    if g.menu != nil { g.closeMenu() }
                    clearPack(); setWallet(50_000)
                    g.alive = true; g.health = 20; g.hunger = 20
                    // Out of hours: shut (the saloon keeps no hours).
                    if k != ShopKind.saloon {
                        at(0.75)
                        stand(by: m)
                        _ = g.talkToTownsperson(m)
                        if g.menu != nil { fault("\(who) served him at midnight (\(type(of: g.menu!)))"); g.closeMenu() }
                    }
                    at(0.2)
                    stand(by: m)
                    _ = g.talkToTownsperson(m)
                    guard let sm = g.menu as? ShopMenu else {
                        fault("\(who) didn't open the counter at noon (menu \(g.menu.map { "\(type(of: $0))" } ?? "none"))")
                        continue
                    }
                    counters += 1
                    if sm.kind != k { fault("\(who) opened the \(sm.kind.name) counter") }
                    // A buy: the first row with stock he can afford, one at a time.
                    sm.qtyIndex = 0
                    var bought: ItemID?
                    for r in sm.rows {
                        guard case .item(let i) = r else { continue }
                        let (_, nm, _, priceText, can) = sm.describe(r)
                        guard can else { continue }
                        let item = Economy.catalog(k)[i].item
                        let price = Economy.buyPrice(item, sm.pricing)
                        if priceText != Money.format(price) { fault("\(who): \(nm) shows \(priceText) but costs \(Money.format(price))") }
                        let m0 = g.money, n0 = g.inventory.main.countOf(item)
                        lastStep = "\(who): the press at line \(#line)"
                        sm.use(r)
                        let paid = m0 - g.money, got = g.inventory.main.countOf(item) - n0
                        if !sm.statusGood || paid != price || got != 1 {
                            fault("\(who): buying one \(nm) at \(Money.format(price)) took \(Money.format(paid)) and gave \(got) (\"\(sm.status)\")")
                        } else { bought = item; buys += 1 }
                        break
                    }
                    if bought == nil && !sm.rows.contains(where: { if case .item = $0 { return true }; return false }) { fault("\(who) has nothing for sale") }
                    // Selling it back pays less than it cost, if the counter buys it at all.
                    if let it = bought, Economy.buysItem(k, it) {
                        sm.selling = true
                        if let r = sm.rows.first(where: { if case .sell(let x) = $0 { return x == it }; return false }) {
                            let m0 = g.money
                            lastStep = "\(who): the press at line \(#line)"
                            sm.use(r)
                            let back = g.money - m0
                            let cost = Economy.buyPrice(it, sm.pricing)
                            if back >= cost { fault("\(who): \(ItemStack(it, 1).def.display) bought at \(Money.format(cost)) sells back at \(Money.format(back)): a loop") }
                            if back <= 0 { fault("\(who): selling back \(ItemStack(it, 1).def.display) paid nothing (\"\(sm.status)\")") } else { sells += 1 }
                        } else { fault("\(who) buys \(ItemStack(it, 1).def.display) but its Sell tab doesn't list it") }
                        sm.selling = false
                    }
                    // Gold sells at its face (ledger 256).
                    clearPack()
                    _ = g.inventory.add(ItemStack(gold, 1))
                    sm.selling = true
                    if let r = sm.rows.first(where: { if case .sell(let x) = $0 { return x == gold }; return false }) {
                        let w0 = g.townWallet
                        lastStep = "\(who): the press at line \(#line)"
                        sm.use(r)
                        if g.townWallet - w0 != 250 || g.inventory.main.countOf(gold) != 0 { fault("\(who): a gold ingot sold for \(Money.format(g.townWallet - w0)), not $2.50 (\"\(sm.status)\")") }
                    } else { fault("\(who): the Sell tab doesn't take a gold ingot") }
                    sm.selling = false
                    // Gold he carries pays, the change lands in the wallet.
                    clearPack(); setWallet(0)
                    _ = g.inventory.add(ItemStack(gold, 4))
                    if let r = sm.rows.first(where: { r in
                        guard case .item(let i) = r else { return false }
                        let p = Economy.buyPrice(Economy.catalog(k)[i].item, sm.pricing)
                        return sm.describe(r).4 && p <= 1000 && p % 250 != 0
                    }), case .item(let i) = r {
                        let item = Economy.catalog(k)[i].item, p = Economy.buyPrice(item, sm.pricing)
                        lastStep = "\(who): the press at line \(#line)"
                        sm.use(r)
                        let left = g.inventory.main.countOf(gold), change = g.townWallet
                        let used = 4 - left
                        if !sm.statusGood || g.inventory.main.countOf(item) != 1 || used * 250 - change != p || used != (p + 249) / 250 {
                            fault("\(who): paying \(Money.format(p)) in gold used \(used) ingots, change \(Money.format(change)) (\"\(sm.status)\")")
                        }
                    }
                    // A meal or a treatment takes its price.
                    clearPack(); setWallet(50_000)
                    for r in sm.rows {
                        guard case .service(let sv) = r, sv == .meal || sv == .treatment else { continue }
                        if sv == .meal { g.hunger = 8 } else { g.health = 12 }
                        let m0 = g.money, price = Economy.price(sv, g)
                        lastStep = "\(who): the press at line \(#line)"
                        sm.use(r)
                        let fed = sv == .meal ? g.hunger == 20 : g.health == 20
                        if m0 - g.money != price || !fed { fault("\(who): \(sv.name) took \(Money.format(m0 - g.money)) of \(Money.format(price)), \(fed ? "done" : "not done") (\"\(sm.status)\")") }
                        g.hunger = 20; g.health = 20
                    }
                    lastStep = "\(who): walking 14 blocks off"
                    // Walking off shuts the counter.
                    let back = g.player.pos
                    g.player.pos = w.freeSpawn(m.pos + V3(14, 0, 0))
                    sm.tick()
                    if g.menu === sm { fault("\(who): the counter stayed open with him 14 blocks off"); g.closeMenu() }
                    g.player.pos = back
                    if g.menu != nil { g.closeMenu() }
                }

                // The bank.
                if let b = bankers.first {
                    banks += 1
                    if g.menu != nil { g.closeMenu() }
                    clearPack(); setWallet(5_000)
                    TownLaw.state.bank = nil; TownLaw.state.bankDay = nil
                    at(0.75); stand(by: b)
                    _ = g.talkToTownsperson(b)
                    if g.menu != nil { fault("the bank served him at midnight"); g.closeMenu() }
                    at(0.2); stand(by: b)
                    _ = g.talkToTownsperson(b)
                    if let bm = g.menu as? BankMenu {
                        bm.pressed(4)                                                     // deposit $10
                        if Bank.balance != 1000 || g.townWallet != 4000 { fault("bank: a $10 deposit left savings \(Money.format(Bank.balance)), wallet \(Money.format(g.townWallet))") }
                        bm.pressed(6)                                                     // withdraw $1
                        if Bank.balance != 900 || g.townWallet != 4100 { fault("bank: a $1 withdrawal left savings \(Money.format(Bank.balance)), wallet \(Money.format(g.townWallet))") }
                        let m0 = g.money
                        bm.pressed(1); bm.pressed(2)                                       // an emerald bought, sold back
                        if g.money >= m0 || g.inventory.main.countOf(emerald) != 0 { fault("bank: an emerald bought and sold back left \(Money.format(g.money - m0)), \(g.inventory.main.countOf(emerald)) emeralds") }
                        g.closeMenu()
                        // Three days away: the interest paid on walking in.
                        g.time += 3 * DAY_LENGTH
                        at(0.2)
                        let want = (0..<3).reduce(900) { a, _ in a + min(Bank.dailyCap, Int(Float(a) * Bank.rate)) }
                        _ = g.talkToTownsperson(b)
                        if g.menu is BankMenu {
                            if Bank.balance != want { fault("bank: three days on \(Money.format(900)) paid to \(Money.format(Bank.balance)), not \(Money.format(want))") }
                        } else { fault("bank: didn't open again three days later") }
                        if g.menu != nil { g.closeMenu() }
                    } else { fault("the bank didn't open at noon (menu \(g.menu.map { "\(type(of: $0))" } ?? "none"))") }
                }

                // A death: wallet $12.34, $9.00 in the bank, four gold nuggets and a loaf in the pack.
                if g.menu != nil { g.closeMenu() }
                clearPack(); setWallet(1234); TownLaw.state.bank = 900
                _ = g.inventory.add(ItemStack(nugget, 4)); _ = g.inventory.add(ItemStack(Items.id("bread"), 1))
                g.alive = true; g.health = 20
                let deathAt = g.player.pos
                let money0 = g.money
                // (the town's own chests and anything lying about hold gold too: what his death left is the change)
                func goldNear() -> Int {
                    var n = 0
                    for (p, be) in w.blockEntities where simd_length(V3(Float(p.x), Float(p.y), Float(p.z)) - deathAt) < 12 {
                        for i in 0..<be.container.count where be.container[i].item == nugget { n += be.container[i].count }
                    }
                    return n + g.drops.items.filter { $0.stack.item == nugget && simd_length($0.pos - deathAt) < 12 }.reduce(0) { $0 + $1.stack.count }
                }
                let gold0 = goldNear()
                let chests0 = Set(w.blockEntities.keys)
                g.die("was slain by a test")
                deaths += 1
                let dm = g.menu as? DeathMenu
                let detail = dm?.detailLines.joined(separator: " ") ?? ""
                let left = goldNear() - gold0
                if g.townWallet != 0 { fault("death: the wallet kept \(Money.format(g.townWallet))") }
                if Bank.balance != 900 { fault("death: the bank's savings went to \(Money.format(Bank.balance))") }
                if left != 4 { fault("death: \(left) of 4 gold nuggets where he fell (money before \(Money.format(money0)))") }
                if !detail.contains("$12.34") || !detail.contains("$9.00") { fault("death: the death screen says \"\(detail)\"") }
                for (p, _) in w.blockEntities where !chests0.contains(p) && simd_length(V3(Float(p.x), Float(p.y), Float(p.z)) - deathAt) < 12 && Blocks.key(w.block(p.x, p.y, p.z)) == "chest" {
                    w.blockEntities[p] = nil; w.setBlock(p.x, p.y, p.z, AIR)
                }
                // (back to life as he comes back: the death screen's Respawn)
                if let d = g.menu as? DeathMenu { d.buttonPressed(0) } else { if g.menu != nil { g.closeMenu() }; g.respawn() }
                if g.menu is DeathMenu { fault("death: the death screen stayed up after Respawn") }
                if g.money != 0 { fault("death: after respawning he has \(Money.format(g.money))") }
                note += ", \(doneKinds.count) counters played"
                played.append(note)
                TownLaw.state.bank = nil
            }
        }
        for f in faults { print("economy hunt: FAULT " + f) }
        let line = String(format: "%d towns (%@); %d counters, %d buys, %d sold back, %d banks, %d deaths; %d faults (%.0f s)",
                          played.count, played.joined(separator: "; "), counters, buys, sells, banks, deaths, faults.count, CFAbsoluteTimeGetCurrent() - t0)
        print("economy hunt: " + line)
        check(played.count == towns && faults.isEmpty && counters >= towns * 4 && banks >= 3, "ledger 337 economy hunt: " + line)
    }
}
