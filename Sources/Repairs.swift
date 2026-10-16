import Foundation

// Repairs and gun grades (backlog O4), so worn loot matters.
//   wear      a gun past 60% worn can jam (up to 1 shot in 10 at the last round of wear: a click, "Jammed!" and a
//             short clear time) and kicks up to 30% harder; a soldier's dropped gun is 25-75% worn
//   repair    the blacksmith's Repair counter mends worn armour, tools and weapons (worn or carried) for a price set
//             by the wear and the item's worth; the gunsmith's Upgrade counter mends guns too
//   grades    the gunsmith lifts a gun one grade (Common to Fine $40, Fine to Rare $120, Rare to Elite $300) with a
//             new roll inside the tier; an anvil still mends with materials as before
enum Repairs {
    static let gradePrice = [4000, 12000, 30000]          // cents, to Fine / Rare / Elite

    static func wear(_ s: ItemStack) -> Float {
        guard !s.isEmpty, s.def.durability > 0 else { return 0 }
        return max(0, min(1, Float(s.damage) / Float(s.def.durability)))
    }

    // A worn gun's chance to jam on a shot, and its recoil scale.
    static func jamChance(_ s: ItemStack) -> Float { max(0, wear(s) - 0.6) * 0.25 }
    static func recoil(_ s: ItemStack) -> Float { 1 + 0.3 * max(0, wear(s) - 0.5) * 2 }
    static var jamRoll: () -> Float = { Rand.float(in: 0..<1) }

    // The worth of a whole item (cents), by its material.
    static func worth(_ s: ItemStack) -> Int {
        if let gi = Guns.index(s.item) {
            let base = min(3000, Int(Guns.all[gi].damage * 60))
            return 1500 + base + 800 * GunGrade.tier(s)
        }
        let k = Items.key(s.item)
        for (pre, w) in [("leather_", 300), ("wooden_", 100), ("stone_", 150), ("chainmail_", 700), ("copper_", 500), ("iron_", 800), ("golden_", 900),
                         ("steel_", 1200), ("regular_", 1200), ("specops_", 1800), ("diamond_", 2500), ("hannibal_", 3000), ("netherite_", 4000)] where k.hasPrefix(pre) {
            return w
        }
        return 600
    }

    static func price(_ s: ItemStack) -> Int {
        let w = wear(s)
        guard w > 0 else { return 0 }
        return max(25, Int((Float(worth(s)) * w * 0.6 / 5).rounded()) * 5)
    }

    // Where a mendable item sits: armour slot (0-3), offhand (-1) or main slot (100 + i).
    struct Job { let at: Int; let cost: Int }

    static func stack(_ g: Game, _ at: Int) -> ItemStack {
        if at >= 100 { return g.inventory.main[at - 100] }
        if at == -1 { return g.inventory.offhand[0] }
        return g.inventory.armor[at]
    }
    static func put(_ g: Game, _ at: Int, _ s: ItemStack) {
        if at >= 100 { g.inventory.main[at - 100] = s } else if at == -1 { g.inventory.offhand[0] = s } else { g.inventory.armor[at] = s }
    }

    static func jobs(_ g: Game, gunsOnly: Bool) -> [Job] {
        var out: [Job] = []
        for at in [0, 1, 2, 3, -1] + (0..<36).map({ 100 + $0 }) {
            let s = stack(g, at)
            guard !s.isEmpty, s.damage > 0, s.def.durability > 0 else { continue }
            if gunsOnly && Guns.index(s.item) == nil { continue }
            out.append(Job(at: at, cost: price(s)))
        }
        return out
    }

    static func mend(_ g: Game, _ j: Job) -> (String, Bool) {
        var s = stack(g, j.at)
        guard !s.isEmpty, s.damage > 0, price(s) == j.cost else { return ("That's not on you any more.", false) }
        guard g.money >= j.cost else { return ("That's \(Money.format(j.cost)). You have \(Money.format(g.money)).", false) }
        s.damage = 0
        put(g, j.at, s)
        g.money -= j.cost
        g.sfx(.anvil, 0.5)
        Honour.earn(g, 0.5, source: "trade", "a fair trade")
        return ("\(s.displayName) good as new for \(Money.format(j.cost)).", true)
    }

    // Grade lifts the gunsmith offers: (main slot, cost).
    static func gradeOffers(_ g: Game) -> [(slot: Int, cost: Int)] {
        (0..<36).compactMap { j in
            let s = g.inventory.main[j]
            guard !s.isEmpty, Guns.index(s.item) != nil, GunGrade.tier(s) < 3 else { return nil }
            return (j, gradePrice[GunGrade.tier(s)])
        }
    }

    static func lift(_ g: Game, slot: Int, cost: Int, roll: Float = Rand.float(in: 0..<1)) -> (String, Bool) {
        var s = g.inventory.main[slot]
        guard !s.isEmpty, Guns.index(s.item) != nil, GunGrade.tier(s) < 3, gradePrice[GunGrade.tier(s)] == cost else { return ("That gun's not on you.", false) }
        guard g.money >= cost else { return ("That's \(Money.format(cost)). You have \(Money.format(g.money)).", false) }
        let t = GunGrade.tier(s) + 1
        s.grade = t * 100 + min(99, Int(roll * 100))
        g.inventory.main[slot] = s
        g.money -= cost
        g.sfx(.anvil, 0.6)
        Honour.earn(g, 0.5, source: "trade", "a fair trade")
        return ("Reworked to \(GunGrade.names[t]) for \(Money.format(cost)).", true)
    }

    static func describe(_ s: ItemStack) -> String { "\(Int((wear(s) * 100).rounded()))% worn" }
}

extension Game {
    // A worn gun may jam instead of firing: a click, a toast and a short clear time. True when it jammed.
    func gunJams(_ gi: Int) -> Bool {
        let c = Repairs.jamChance(held)
        guard c > 0, Repairs.jamRoll() < c else { return false }
        arms.cooldown = max(arms.cooldown, 0.8)
        sfx(.gun(7), 0.8)
        onToast?("Jammed!")
        return true
    }
}

// The blacksmith's Repair counter.
final class RepairMenu: ListMenu {
    weak var keeper: Mob?
    var jobs: [Repairs.Job] = []
    init(game g: Game, keeper m: Mob) {
        keeper = m
        super.init("Repairs", game: g)
        subtitle = "Armour, tools and weapons mended"
        say(Repairs.jobs(g, gunsOnly: false).isEmpty ? "Nothing of yours needs mending." : "What needs mending?", good: true)
    }
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        jobs = Repairs.jobs(game, gunsOnly: false)
        return jobs.map { j in
            let s = Repairs.stack(game, j.at)
            return Row(icon: s, name: s.displayName, detail: Repairs.describe(s), value: Money.format(j.cost), enabled: game.money >= j.cost)
        }
    }
    override func tick() {
        super.tick()
        if TownServices.keeperGone(game, keeper) { game.closeMenu() }
    }
    override func pressed(_ i: Int) {
        let js = Repairs.jobs(game, gunsOnly: false)
        guard i < js.count else { return }
        let r = Repairs.mend(game, js[i])
        say(r.0, good: r.1)
    }
}
