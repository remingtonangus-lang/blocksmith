import Foundation
import simd

// D29: the mail-order catalog. Every general store keeps a catalog (ShopService.catalog) of rare goods no shelf in
// the territory stocks: pay up front and the parcel comes in on the next day's coach, to be collected at any general
// store (the catalog's first row once something has arrived; a toast says so). Orders are saved (TownLaw.state.orders:
// item key, count, the day it's due).
enum MailOrder {
    struct Entry { let key: String; let count: Int; let price: Int; let blurb: String }
    static let catalog: [Entry] = [
        Entry(key: "spyglass", count: 1, price: 2500, blurb: "Brass, from back East"),
        Entry(key: "saddle", count: 1, price: 3000, blurb: "Tooled leather, a fine seat"),
        Entry(key: "iron_horse_armor", count: 1, price: 3500, blurb: "Barding for a working horse"),
        Entry(key: "diamond_horse_armor", count: 1, price: 9000, blurb: "Barding for a prize horse"),
        Entry(key: "name_tag", count: 1, price: 1500, blurb: "Name a beast of your own"),
        Entry(key: "compass", count: 1, price: 1200, blurb: "Never lose the trail home"),
        Entry(key: "clock", count: 1, price: 1500, blurb: "A pocket watch on a chain"),
        Entry(key: "golden_apple", count: 1, price: 4000, blurb: "A tonic in fruit form"),
        Entry(key: "experience_bottle", count: 4, price: 2400, blurb: "Bottled know-how, four to a crate"),
        Entry(key: "enchanted_book", count: 1, price: 6000, blurb: "A mystery volume from the coast"),
        Entry(key: "music_disc_cat", count: 1, price: 2000, blurb: "A record for the phonograph"),
        Entry(key: "bundle", count: 1, price: 800, blurb: "A drawstring sack"),
        Entry(key: "trident", count: 1, price: 12000, blurb: "A fisherman's spear, ocean-made"),
        Entry(key: "totem_of_undying", count: 1, price: 25000, blurb: "A charm that cheats death once"),
    ]
    static var placed = 0, collected = 0             // (harness)

    static func today(_ g: Game) -> Int { Int(g.time / DAY_LENGTH) }
    static var orders: [[String]] { TownLaw.state.orders ?? [] }        // [key, count, due day]
    static func ready(_ g: Game) -> [[String]] { orders.filter { $0.count == 3 && (Int($0[2]) ?? 0) <= today(g) } }

    static func order(_ g: Game, _ e: Entry) -> (String, Bool) {
        guard Items.has(e.key) else { return ("That's out of print.", false) }
        guard g.money >= e.price else { return ("That's \(Money.format(e.price)). You have \(Money.format(g.money)).", false) }
        guard orders.count < 8 else { return ("Collect what's come in before ordering more.", false) }
        g.money -= e.price
        var o = orders; o.append([e.key, String(e.count), String(today(g) + 1)]); TownLaw.state.orders = o
        TownLaw.state.ordersToasted = false
        placed += 1
        g.sfx(.pageTurn, 0.6)
        return ("Ordered. It comes in on tomorrow's coach: collect it at any general store.", true)
    }

    static func collect(_ g: Game) -> (String, Bool) {
        let r = ready(g)
        guard !r.isEmpty else { return ("Nothing's come in for you yet.", false) }
        for o in r where Items.has(o[0]) {
            let rest = g.inventory.add(ItemStack(Items.id(o[0]), Int(o[1]) ?? 1))
            if !rest.isEmpty { g.dropItem(rest) }
        }
        let due = today(g)
        TownLaw.state.orders = orders.filter { !($0.count == 3 && (Int($0[2]) ?? 0) <= due) }
        if TownLaw.state.orders?.isEmpty == true { TownLaw.state.orders = nil }
        collected += r.count
        g.sfx(.villagerTrade, 0.7)
        return ("\(r.count == 1 ? "Your parcel" : "\(r.count) parcels"), signed for.", true)
    }

    // Once a second (TownLaw.tick): the arrival notice.
    static func tick(_ g: Game) {
        guard TownLaw.state.ordersToasted == false, !ready(g).isEmpty else { return }
        TownLaw.state.ordersToasted = true
        g.onToast?("Your catalog order has come in. Collect it at any general store")
    }
}

final class CatalogMenu: ListMenu {
    init(game g: Game) {
        super.init("Mail-Order Catalog", game: g)
        subtitle = "Paid now, on tomorrow's coach"
    }
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        let r = MailOrder.ready(game).count, waiting = MailOrder.orders.count - r
        var out = [Row(icon: Items.has("paper") ? ItemStack(Items.id("paper"), 1) : .empty, name: r > 0 ? "Collect \(r) parcel\(r == 1 ? "" : "s")" : "Parcels",
                       detail: waiting > 0 ? "\(waiting) on the way" : (r > 0 ? "Come in on the coach" : "Nothing on order"), value: "", enabled: r > 0)]
        for e in MailOrder.catalog where Items.has(e.key) {
            let st = ItemStack(Items.id(e.key), e.count)
            out.append(Row(icon: st, name: (e.count > 1 ? "\(e.count) x " : "") + st.def.display, detail: e.blurb, value: Money.format(e.price), enabled: game.money >= e.price))
        }
        return out
    }
    override func pressed(_ i: Int) {
        if i == 0 { let r = MailOrder.collect(game); say(r.0, good: r.1); return }
        let list = MailOrder.catalog.filter { Items.has($0.key) }
        guard i - 1 < list.count else { return }
        let r = MailOrder.order(game, list[i - 1])
        say(r.0, good: r.1)
    }
}
