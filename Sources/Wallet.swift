import Foundation
import simd

// The wallet on the HUD, the emerald exchange and the craftsfolk's cash counters (docs/status/economy.md).
//
// Wallet: "$12.50" at the top right (under the minimap and its coordinate lines, or under the effect icons), shown
// while you're in a town and for 6 s after the amount changes (with the change beside it, green or red). Drawn by
// HudExtras.lines, so the Mac HUD and the Quest's HUD panel both show it.
//
// Emeralds: one emerald is one dollar. The general store buys emeralds at $1.00 and sells them at $1.20 (the spread
// keeps buy-sell loops at a loss), whatever the town thinks of you. Every barter offer of the craftsfolk was checked
// against the shop prices at that rate (TownTests "economy: barter"), so no loop of shop -> barter -> exchange makes
// money from nothing.
//
// Craftsfolk (the old job-site professions) keep their barter, but talking to one now opens a cash counter for their
// trade (a toolsmith's is the blacksmith's catalogue, a librarian's the general store's...) with a Barter button for
// the emerald trades: every working townsperson takes money, in old villages without shop buildings too.

extension Economy {
    static let emeraldBuy = 120     // the store sells an emerald for $1.20
    static let emeraldSell = 100    // and buys one for $1.00

    static func isEmerald(_ item: ItemID) -> Bool { Items.key(item) == "emerald" }
    // What the player pays for one / is paid for one at this counter.
    static func buyPrice(_ item: ItemID, _ p: ShopPricing) -> Int { isEmerald(item) ? emeraldBuy : p.buy(value(of: item) ?? 0) }
    static func sellPrice(_ item: ItemID, _ p: ShopPricing) -> Int { isEmerald(item) ? emeraldSell : p.sell(value(of: item) ?? 0) }

    // A craftsperson's cash counter: the shop catalogue closest to their trade.
    static let professionShop: [String: ShopKind] = [
        "armorer": .blacksmith, "toolsmith": .blacksmith, "weaponsmith": .blacksmith, "mason": .general, "butcher": .butcher,
        "cartographer": .general, "librarian": .general, "cleric": .doctor, "farmer": .general, "fisherman": .butcher,
        "fletcher": .gunsmith, "leatherworker": .tailor, "shepherd": .tailor,
    ]
}

extension VillagerData {
    // The counter this person keeps: their shop, else their trade's.
    var tradeKind: ShopKind? { shopKind ?? (profession == "none" || profession == "nitwit" ? nil : Economy.professionShop[profession]) }
}

enum Wallet {
    private static var shown = Int.min
    private static var changedAt: Double = -100
    private static var delta = 0

    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        guard HudExtras.enabled, !g.hideHUD, g.menu == nil, g.alive else { return [] }
        let money = g.money
        if money != shown {
            if shown != Int.min { delta = money - shown; changedAt = g.clock }
            shown = money
        }
        let recent = g.clock - changedAt < 6
        guard recent || TownLaw.inTown != nil else { return [] }
        let s = L.s
        var y = L.insetY + 6 * s + (g.effects.any ? 54 * s : 0)
        if Settings.shared.minimap { y += 64 * s + 30 * s }          // under the minimap, its coordinates and waypoint line
        let t = Money.format(money)
        let w = Float(Font.width(t)) * s
        let x = L.W - L.insetX - w - 8 * s
        var out = [HudLine(text: t, x: x, y: y, scale: s, color: V4(1, 0.86, 0.42, 1), bg: V4(0, 0, 0, 0.55))]
        if recent && delta != 0 {
            let fade = Float(max(0, min(1, 6 - (g.clock - changedAt))))
            let d = (delta > 0 ? "+" : "") + Money.format(delta)
            let dw = Float(Font.width(d)) * s
            out.append(HudLine(text: d, x: x - dw - 6 * s, y: y, scale: s,
                               color: delta > 0 ? V4(0.45, 1, 0.45, fade) : V4(1, 0.45, 0.4, fade)))
        }
        return out
    }
}
