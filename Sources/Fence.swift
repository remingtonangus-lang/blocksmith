import Foundation
import simd

// D27: a fence for stolen goods. What you take from a town's chests and barrels (TownLaw.settle) and what a held-up
// stagecoach throws down (Stagecoach.robbed) is hot: the stolen count per item is kept in TownLaw.state.hot. Honest
// shopkeepers only buy what you hold beyond that count ("That's stolen goods"); the saloon's back room (a service at
// every saloon: ShopService.fence) takes the hot goods for 60 % of their value, no questions asked, and costs a
// little honour. The goods cool off on their own: five days after the last theft the ledger is cleared.
enum Fence {
    static let cut: Float = 0.6
    static let coolDays = 5
    static var fenced = 0                            // (harness)
    static var today = 0                             // the day number, kept by TownLaw.tick

    static func hot(_ item: ItemID) -> Int { TownLaw.state.hot?[Items.key(item)] ?? 0 }
    static var hotCount: Int { (TownLaw.state.hot ?? [:]).values.reduce(0, +) }

    static func mark(_ key: String, _ n: Int, day: Int) {
        guard n > 0 else { return }
        var h = TownLaw.state.hot ?? [:]
        h[key, default: 0] += n
        TownLaw.state.hot = h
        TownLaw.state.hotDay = day
    }

    // The hot goods you still carry (the ledger capped by what's in the pack) and what the fence pays for them.
    static func offer(_ g: Game) -> (count: Int, pay: Int) {
        var n = 0, pay = 0
        for (k, c) in TownLaw.state.hot ?? [:] where Items.has(k) {
            let id = Items.id(k)
            let have = min(c, g.inventory.main.countOf(id))
            n += have
            pay += Int(Float(have * (Economy.value(of: id) ?? 0)) * cut)
        }
        return (n, pay)
    }

    // ShopService.fence.
    static func sell(_ g: Game, _ m: Mob) -> (String, Bool) {
        let (n, pay) = offer(g)
        guard n > 0 else {
            g.sfx(.villagerNo, 0.6, at: m.pos + V3(0, 1.6, 0))
            return ("You've got nothing hot on you, friend. Come back when you do.", false)
        }
        var h = TownLaw.state.hot ?? [:]
        for (k, c) in h where Items.has(k) {
            let id = Items.id(k)
            let take = min(c, g.inventory.main.countOf(id))
            if take > 0 { _ = g.inventory.main.remove(id, take) }
            h[k] = c - take > 0 ? c - take : nil
        }
        TownLaw.state.hot = h.isEmpty ? nil : h
        g.money += pay
        fenced += n
        g.sfx(.villagerTrade, 0.5, at: m.pos + V3(0, 1.6, 0))
        Honour.change(g, -0.5, "fenced stolen goods")
        return ("\(n) hot items, gone. Here's \(Money.format(pay)), and we never met.", true)
    }

    // Once a second (TownLaw.tick): the goods cool off.
    static func tick(_ g: Game) {
        guard let d = TownLaw.state.hotDay, TownLaw.state.hot != nil else { return }
        if Int(g.time / DAY_LENGTH) - d >= coolDays { TownLaw.state.hot = nil; TownLaw.state.hotDay = nil }
    }
}
