import Foundation

// Repairs and gun grades (backlog O4), `questcheck --repair-only`: a worn gun jams and kicks harder, the blacksmith
// mends worn armour and the gunsmith mends and reworks guns, each for money.
enum RepairTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        guard let gi = Guns.all.firstIndex(where: { Items.has($0.key) }) else { check(false, "repair: no guns"); return }
        let gs = Guns.all[gi]
        let main0 = (0..<36).map { g.inventory.main[$0] }, armor0 = (0..<4).map { g.inventory.armor[$0] }, money0 = g.money, roll0 = Repairs.jamRoll
        defer {
            for i in 0..<36 { g.inventory.main[i] = main0[i] }
            for i in 0..<4 { g.inventory.armor[i] = armor0[i] }
            g.money = money0; Repairs.jamRoll = roll0
        }
        for i in 0..<36 { g.inventory.main[i] = .empty }
        var gun = ItemStack(Items.id(gs.key), 1); gun.damage = gs.durability * 95 / 100; gun.tag = gs.mag
        g.inventory.main[0] = gun
        g.inventory.selected = 0
        Repairs.jamRoll = { 0 }
        let jams = g.gunJams(gi), kick = Repairs.recoil(gun)
        var fresh = gun; fresh.damage = 0
        g.inventory.main[0] = fresh
        let freshJam2 = g.gunJams(gi)
        g.inventory.main[0] = gun
        check(jams && !freshJam2 && kick > 1.2 && Repairs.recoil(fresh) == 1, "repair: a 95% worn gun jams (\(jams)) and kicks x\(kick); a fresh one does not")

        var plate = ItemStack(Items.id("iron_chestplate"), 1); plate.damage = plate.def.durability / 2
        g.inventory.armor[1] = plate
        g.money = 100_000
        let all = Repairs.jobs(g, gunsOnly: false), guns = Repairs.jobs(g, gunsOnly: true)
        let pj = all.first { $0.at == 1 }
        let r1 = pj.map { Repairs.mend(g, $0) }
        check(all.count == 2 && guns.count == 1 && g.inventory.armor[1].damage == 0 && r1?.1 == true && g.money == 100_000 - (pj?.cost ?? 0),
              "repair: blacksmith lists \(all.count) jobs (guns \(guns.count)), mends the half-worn chestplate for \(Money.format(pj?.cost ?? 0)): \(r1?.0 ?? "-")")
        let m1 = g.money
        let r2 = Repairs.mend(g, guns[0])
        check(r2.1 && g.inventory.main[0].damage == 0 && g.money < m1, "repair: gunsmith mends the gun: \(r2.0)")

        let lifts = Repairs.gradeOffers(g)
        let r3 = lifts.first.map { Repairs.lift(g, slot: $0.slot, cost: $0.cost, roll: 0.5) }
        let t1 = GunGrade.tier(g.inventory.main[0])
        for _ in 0..<2 { if let o = Repairs.gradeOffers(g).first { _ = Repairs.lift(g, slot: o.slot, cost: o.cost) } }
        let top = GunGrade.tier(g.inventory.main[0])
        check(r3?.1 == true && t1 == 1 && top == 3 && Repairs.gradeOffers(g).isEmpty && GunGrade.damage(g.inventory.main[0]) > 1.19,
              "repair: rework Common to Fine (\(r3?.0 ?? "-")), then up to \(GunGrade.names[top]); no lift past Elite")
        g.money = 10
        var worn = g.inventory.main[0]; worn.damage = gs.durability / 2; g.inventory.main[0] = worn
        let poor = Repairs.mend(g, Repairs.jobs(g, gunsOnly: true)[0])
        check(!poor.1 && g.inventory.main[0].damage > 0, "repair: no mending without the money (\(poor.0))")
    }
}
