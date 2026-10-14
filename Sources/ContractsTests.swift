import Foundation
import simd

// Jobs and contracts (backlog C11), `questcheck --contracts-only`:
//   boards     a town's board posts two contracts a day; over 30 days all four kinds come up; a base's map table posts
//              camps and couriers and still reads the war report; the town board fits its panel with them
//   courier    the parcel goes in your pack; walking into the other town with it pays (money, honour), the parcel goes
//   escort     the traveller follows; road agents half way; reaching the town pays and they settle there; a dead
//              traveller fails the contract
//   camp       the camp turns up when you get near (campfire, bandits); killing them all, then the board pays
//   defend     after dark in town the raid comes; beating it pays
//   lapse      a contract left three days lapses
enum ContractsTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let saved = TownLaw.state, money = g.money, time = g.time, pos = g.player.pos, mobs = g.mobs.mobs
        let inv = g.inventory.main.slots, surv = g.survival, inTown = TownLaw.inTown
        defer {
            TownLaw.state = saved; g.money = money; g.time = time; g.player.pos = pos; g.mobs.mobs = mobs; g.mobs.rebuildIndex()
            g.inventory.main.slots = inv; g.survival = surv; TownLaw.inTown = inTown; g.raid = nil
        }
        g.survival = true
        g.time = 0.3 * DAY_LENGTH
        let p = g.player.pos
        guard let v = g.world.gen.structures?.nearest("village", x: Int(floor(p.x)), z: Int(floor(p.z)), maxRegions: 8) else {
            check(false, "C11: no town near spawn"); return
        }
        let anchor = v.anchor
        let town = Townsfolk.townName(anchor.x, anchor.z, seed: g.world.seed)

        // Boards.
        var kinds = Set<String>(), baseKinds = Set<String>()
        for d in 0..<30 {
            g.time = (Double(d) + 0.3) * DAY_LENGTH
            for c in Contracts.contracts(g, board: town, at: anchor) { kinds.insert(c.kind) }
            for c in Contracts.contracts(g, board: "greywall:\(anchor.x + 900),\(anchor.z)", at: IVec3(anchor.x + 900, anchor.y, anchor.z)) { baseKinds.insert(c.kind) }
        }
        g.time = 0.3 * DAY_LENGTH
        let today = Contracts.contracts(g, board: town, at: anchor)
        let board = NoticeBoardMenu(game: g, town: town, anchor: anchor)
        let over = board.overflow()
        let base = BaseContractsMenu(game: g, board: "greywall:\(anchor.x + 900),\(anchor.z)", at: IVec3(anchor.x + 900, anchor.y, anchor.z))
        check(today.count == 2 && kinds.isSuperset(of: ["courier", "escort", "camp", "defend"]) && baseKinds.isSubset(of: ["camp", "courier"]) && !baseKinds.isEmpty
              && over.isEmpty && base.rows.count == 3 && base.rows.last?.name == "Read the war report",
              "C11 boards: \(town) posts \(today.map { $0.kind }); over 30 days \(kinds.sorted()); a base posts \(baseKinds.sorted()) and the war report; the board fits (\(over.prefix(2)))")

        // A contract of a kind, taken (searching the days for one).
        func take(_ kind: String) -> (Int, Contract)? {
            for d in 0..<60 {
                g.time = (Double(d) + 0.3) * DAY_LENGTH
                let cs = Contracts.contracts(g, board: town, at: anchor)
                if let i = cs.firstIndex(where: { $0.kind == kind && !$0.taken && !$0.paid }) {
                    g.player.pos = V3(Float(anchor.x), Float(anchor.y + 1), Float(anchor.z))
                    _ = Contracts.use(g, board: town, at: anchor, i)
                    return (i, Contracts.contracts(g, board: town, at: anchor)[i])
                }
            }
            return nil
        }
        func state(_ i: Int) -> Contract? { Contracts.all["\(town)#\(i)"] }

        // Courier.
        if let (i, c) = take("courier"), let t = c.destAt {
            let parcel = g.inventory.main.slots.contains { $0.pages == ["parcel:\(town)#\(i)"] }
            let m0 = g.money, h0 = Honour.value
            g.player.pos = V3(Float(t[0]), 100, Float(t[1]) + 20)
            Contracts.tick(g)
            let paid = state(i)?.paid == true
            let gone = !g.inventory.main.slots.contains { $0.pages == ["parcel:\(town)#\(i)"] }
            check(parcel && paid && gone && g.money == m0 + c.pay && Honour.value > h0,
                  "C11 courier: a parcel for \(c.dest ?? "?") (\(Int(simd_length(V2(Float(t[0] - anchor.x), Float(t[1] - anchor.z))))) blocks) pays \(Money.format(c.pay)) on arrival; parcel handed over \(gone)")
        } else { check(false, "C11 courier: none came up") }

        // Escort.
        if let (i, c) = take("escort"), let t = c.destAt {
            let traveller = g.mobs.mobs.first { $0.customName == c.who && $0.kind == .villager }
            let a = V2(Float(anchor.x), Float(anchor.z)), b = V2(Float(t[0]), Float(t[1]))
            let mid = a + (b - a) * 0.6
            g.player.pos = V3(mid.x, 100, mid.y)
            traveller?.pos = g.player.pos + V3(1, 0, 0)
            let n0 = g.mobs.mobs.count
            Contracts.tick(g)
            let agents = g.mobs.mobs.count - n0
            g.player.pos = V3(b.x, 100, b.y + 10)
            traveller?.pos = g.player.pos + V3(1, 0, 0)
            Contracts.tick(g)
            let paid = state(i)?.paid == true
            let settled = traveller?.villager?.town == c.dest && traveller?.customName == nil
            check(traveller != nil && agents == 3 && paid && settled,
                  "C11 escort: \(c.who ?? "?") follows; \(agents) road agents half way; reaching \(c.dest ?? "?") pays \(paid) and they settle there \(settled)")
        } else { check(false, "C11 escort: none came up") }
        if let (i, c) = take("escort") {
            let traveller = g.mobs.mobs.first { $0.customName == c.who && $0.kind == .villager }
            traveller?.health = 0
            Contracts.tick(g)
            check(state(i)?.failed == true, "C11 escort: the traveller dead, the contract fails")
        }

        // Camp.
        if let (i, c) = take("camp"), let t = c.target {
            g.player.pos = V3(Float(t[0]) + 10, Float(anchor.y + 1), Float(t[1]))
            _ = g.world.loadSync(center: g.player.pos, radius: 2)
            g.player.pos.y = Float(g.world.topY(t[0] + 10, t[1]) + 1)
            Contracts.tick(g)
            let bandits = g.mobs.mobs.filter { $0.posse == Contracts.banditPosse && $0.customName == "Bandit" }
            let fire = Blocks.has("campfire") && (g.world.topY(t[0], t[1]) ... g.world.topY(t[0], t[1]) + 1).contains { g.world.block(t[0], $0, t[1]) == Blocks.id("campfire") }
            for m in bandits { m.health = 0; m.killedByPlayer = true; Contracts.mobDied(g, m) }
            let done = state(i)?.done == true
            let m0 = g.money
            _ = Contracts.use(g, board: town, at: anchor, i)
            check(bandits.count == c.count && fire && done && state(i)?.paid == true && g.money == m0 + c.pay,
                  "C11 camp: \(bandits.count) bandits and a campfire \(fire) at the camp; all dead, the board pays \(Money.format(c.pay))")
        } else { check(false, "C11 camp: none came up") }

        // Defend.
        if let (i, c) = take("defend") {
            g.player.pos = V3(Float(anchor.x), Float(anchor.y + 1), Float(anchor.z))
            let folk = Mob(.villager, at: g.player.pos + V3(3, 0, 0))
            g.mobs.mobs.append(folk)
            TownLaw.inTown = town
            g.time = (floor(g.time / DAY_LENGTH) + 0.7) * DAY_LENGTH
            g.raid = nil
            Contracts.tick(g)
            let raided = g.raid != nil
            g.raid = nil
            let m0 = g.money
            Contracts.raidWon(g, town)
            check(raided && state(i)?.paid == true && g.money == m0 + c.pay, "C11 defend: after dark the raid comes (\(raided)); beating it pays \(Money.format(c.pay))")
        } else { check(false, "C11 defend: none came up") }

        // Lapse.
        if let (i, _) = take("camp") {
            g.time += 3 * DAY_LENGTH
            Contracts.tick(g)
            check(state(i)?.failed == true, "C11 lapse: a contract left three days lapses")
        }
    }
}
