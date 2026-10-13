import Foundation

// Trophy room and museum (backlog O6), `questcheck --trophies-only`: trophies framed and placed at home go on show,
// three or more make a museum that pays each day, and the ledger lists them.
enum TrophiesTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let spawn0 = g.spawnPoint, money0 = g.money, time0 = g.time, saved0 = Trophies.encode()
        var placed: [IVec3] = []
        defer {
            for p in placed { g.world.blockEntities[p] = nil; g.world.setBlock(p.x, p.y, p.z, AIR) }
            g.spawnPoint = spawn0; g.money = money0; g.time = time0; Trophies.decode(saved0)
        }
        Trophies.decode("")
        let home = g.player.pos
        g.spawnPoint = home
        let hx = Int(floor(home.x)), hz = Int(floor(home.z)), hy = Int(floor(home.y))
        func frame(_ dx: Int, _ key: String) {
            let p = IVec3(hx + dx, hy + 1, hz + 3)
            let be = g.world.entity(p, .frame)
            be.container[0] = ItemStack(Items.id(key), 1)
            g.world.blockEntities[p] = be
            placed.append(p)
        }
        let pelt = Hunting.legends[0].pelt
        frame(0, pelt)
        frame(1, "nether_star")
        frame(2, "diamond")                               // not a trophy
        g.trophiesTick(force: true)
        let two = Trophies.onShow
        let egg = IVec3(hx - 2, hy, hz + 4)
        g.world.setBlock(egg.x, egg.y, egg.z, Blocks.id("dragon_egg")); placed.append(egg)
        g.time = DAY_LENGTH * 3
        let m0 = g.money
        g.trophiesTick(force: true)
        let opened = Trophies.paidDay == 3 && g.money == m0          // the first museum day opens, no takings yet
        g.time = DAY_LENGTH * 4
        g.trophiesTick(force: true)
        let paid = g.money - m0
        check(two == [pelt, "nether_star"], "trophies: a framed legendary pelt and the Blight Star are on show, a diamond is not (\(two.sorted()))")
        check(Trophies.onShow.count == 3 && opened && paid == 3 * Trophies.admission && Trophies.shown.count == 3,
              "trophies: the placed Wyrm Egg makes three, the museum opens and next day pays \(Money.format(paid))")
        let saved = Trophies.encode()
        Trophies.decode(saved)
        let menu = TrophyLedgerMenu(game: g)
        let rows = menu.rows
        check(Trophies.shown.count == 3 && rows.count == Trophies.all.count && rows.filter { $0.value != "Missing" }.count == 3,
              "trophies: kept through a save (\(saved)); the ledger lists \(rows.count) trophies")
    }
}
