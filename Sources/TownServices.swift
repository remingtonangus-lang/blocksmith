import Foundation
import simd

// Town services from the gap pass (docs/status/cloud-gap-pass.md, ET4-ET6):
//   - The bank (FrontierTown.bankLot, its banker behind the teller's bars): the emerald exchange at the general
//     store's rates ($1.20 to buy one, $1.00 for one), and a savings account kept across every town: deposit and
//     withdraw in $1/$10/all steps; it pays 1% a day, at most $2 a day, at most a week's worth at once (so the bank is
//     a safe place for money, never a money farm). Open in shop hours.
//   - The gunsmith's upgrades (an Upgrade button on the gunsmith's counter): the guns you carry, each gun upgrade's
//     next level for a price (Extended Magazine, Quick Reload, Stability, Penetration, Incendiary: the gun upgrades
//     the anvil and the table already know), so money buys a better gun without the enchanting table.
//   - The saloon's dice table (a Dice button on the saloon's counter): high dice, you against the house, two dice each;
//     the house wins ties, so the odds are with it (575 in 1296 to win, 44%, paid even money: -11% a bet), $1/$5/$10
//     a throw.

// MARK: The bank

enum Bank {
    static let buyEmerald = 120, sellEmerald = 100      // cents, the exchange (Economy: an emerald is worth $1)
    static let rate: Float = 0.01, dailyCap = 200, maxDays = 7

    static var balance: Int {
        get { TownLaw.state.bank ?? 0 }
        set { TownLaw.state.bank = max(0, newValue) }
    }

    // Interest since the last visit (any bank), paid when you walk in.
    @discardableResult
    static func accrue(_ g: Game) -> Int {
        let day = Int(g.time / DAY_LENGTH)
        guard let last = TownLaw.state.bankDay else { TownLaw.state.bankDay = day; return 0 }
        let days = min(maxDays, max(0, day - last))
        TownLaw.state.bankDay = day
        var paid = 0
        for _ in 0..<days {
            let i = min(dailyCap, Int(Float(balance) * rate))
            balance += i; paid += i
        }
        return paid
    }

    static func deposit(_ g: Game, _ cents: Int) -> (String, Bool) {
        let n = min(cents, g.money)
        guard n > 0 else { return ("You've no money on you.", false) }
        g.money -= n; balance += n
        TownLaw.state.bankDay = TownLaw.state.bankDay ?? Int(g.time / DAY_LENGTH)
        g.sfx(.villagerTrade, 0.5)
        return ("Deposited \(Money.format(n)). Balance \(Money.format(balance)).", true)
    }
    static func withdraw(_ g: Game, _ cents: Int) -> (String, Bool) {
        let n = min(cents, balance)
        guard n > 0 else { return ("Your account is empty.", false) }
        balance -= n; g.money += n
        g.sfx(.villagerTrade, 0.5)
        return ("Withdrew \(Money.format(n)). Balance \(Money.format(balance)).", true)
    }
    static func buy(_ g: Game) -> (String, Bool) {
        guard g.money >= buyEmerald else { return ("An emerald is \(Money.format(buyEmerald)).", false) }
        g.money -= buyEmerald
        let rest = g.inventory.add(ItemStack(Items.id("emerald"), 1))
        if !rest.isEmpty { g.dropItem(rest) }
        g.sfx(.villagerTrade, 0.5)
        return ("Bought an emerald for \(Money.format(buyEmerald)).", true)
    }
    static func sell(_ g: Game) -> (String, Bool) {
        let id = Items.id("emerald")
        guard g.inventory.main.countOf(id) > 0 else { return ("You have no emeralds.", false) }
        _ = g.inventory.main.remove(id, 1)
        g.money += sellEmerald
        g.sfx(.villagerTrade, 0.5)
        return ("Sold an emerald for \(Money.format(sellEmerald)).", true)
    }
}

final class BankMenu: ListMenu {
    weak var banker: Mob?
    static func open(_ f: Double) -> Bool { f >= 0.02 && f <= 0.47 }       // the shops' hours

    init(game g: Game, banker m: Mob) {
        banker = m
        let who = m.villager?.person.flatMap { $0.split(separator: " ").last }.map { "\($0)'s " } ?? ""
        super.init(who + "Bank", game: g)
        let interest = Bank.accrue(g)
        subtitle = [m.villager?.person, m.villager?.town].compactMap { $0 }.joined(separator: " of ")
        say(interest > 0 ? "Interest paid while you were away: \(Money.format(interest))." : "Welcome. Your money's safe with us.", good: true)
        TownVoice.speakSoon(g, m, .greet)
        BankMenu.opened += 1
    }
    static var opened = 0
    override func onClose() { if let m = banker, m.health > 0 { TownVoice.speakSoon(game, m, .bye) } }

    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        let em = ItemStack(Items.id("emerald"), 1)
        let gold = Items.has("gold_ingot") ? ItemStack(Items.id("gold_ingot"), 1) : ItemStack.empty
        let has = game.inventory.main.countOf(em.item)
        return [
            Row(icon: gold, name: "Savings: \(Money.format(Bank.balance))", detail: "1% a day, up to \(Money.format(Bank.dailyCap)) a day", value: "", enabled: false),
            Row(icon: em, name: "Buy an emerald", detail: "The exchange", value: Money.format(Bank.buyEmerald), enabled: game.money >= Bank.buyEmerald),
            Row(icon: em, name: "Sell an emerald", detail: "You have \(has)", value: Money.format(Bank.sellEmerald), enabled: has > 0),
            Row(name: "Deposit $1", detail: "From your wallet", value: "$1.00", enabled: game.money >= 100),
            Row(name: "Deposit $10", detail: "From your wallet", value: "$10.00", enabled: game.money >= 1000),
            Row(name: "Deposit all", detail: "Everything in your wallet", value: Money.format(game.money), enabled: game.money > 0),
            Row(name: "Withdraw $1", detail: "To your wallet", value: "$1.00", enabled: Bank.balance >= 100),
            Row(name: "Withdraw $10", detail: "To your wallet", value: "$10.00", enabled: Bank.balance >= 1000),
            Row(name: "Withdraw all", detail: "Close out the account", value: Money.format(Bank.balance), enabled: Bank.balance > 0),
        ]
    }

    override func pressed(_ i: Int) {
        let r: (String, Bool)
        switch i {
        case 1: r = Bank.buy(game)
        case 2: r = Bank.sell(game)
        case 3: r = Bank.deposit(game, 100)
        case 4: r = Bank.deposit(game, 1000)
        case 5: r = Bank.deposit(game, game.money)
        case 6: r = Bank.withdraw(game, 100)
        case 7: r = Bank.withdraw(game, 1000)
        case 8: r = Bank.withdraw(game, Bank.balance)
        default: return
        }
        say(r.0, good: r.1)
    }

    override func tick() {
        super.tick()
        if !BankMenu.open(game.dayFraction) { if let m = banker { TownVoice.speak(game, m, .closed) }; game.closeMenu() }
    }
}

// MARK: The gunsmith's upgrades

enum GunUpgrades {
    // Price of each level (cents): level n costs n x this.
    static let price: [(Ench, Int)] = [(.extendedMag, 400), (.quickReload, 350), (.stability, 300), (.penetration, 600), (.incendiary, 1500)]

    struct Offer { let slot: Int; let ench: Ench; let level: Int; let cost: Int }

    // Every gun you carry (main inventory) and each upgrade's next level it can take.
    static func offers(_ g: Game) -> [Offer] {
        var out: [Offer] = []
        for j in 0..<36 {
            let s = g.inventory.main[j]
            guard !s.isEmpty, Guns.index(s.item) != nil else { continue }
            let have = Enchant.list(s)
            for (e, base) in price {
                let lv = Enchant.level(e, s)
                guard lv < Enchant.def(e).max, have.allSatisfy({ $0.0 == e || Enchant.compatible($0.0, e) }) else { continue }
                guard lv > 0 || have.count < 7 else { continue }
                out.append(Offer(slot: j, ench: e, level: lv + 1, cost: base * (lv + 1)))
            }
        }
        return out
    }

    static func apply(_ g: Game, _ o: Offer) -> (String, Bool) {
        var s = g.inventory.main[o.slot]
        guard !s.isEmpty, Guns.index(s.item) != nil, Enchant.level(o.ench, s) == o.level - 1 else { return ("That gun's not on you.", false) }
        guard g.money >= o.cost else { return ("That's \(Money.format(o.cost)). You have \(Money.format(g.money)).", false) }
        var l = Enchant.list(s).filter { $0.0 != o.ench }
        l.append((o.ench, o.level))
        s.ench = Enchant.pack(l)
        g.inventory.main[o.slot] = s
        g.money -= o.cost
        g.sfx(.anvil, 0.5)
        Honour.earn(g, 0.5, source: "trade", "a fair trade")
        return ("\(Enchant.def(o.ench).name) \(roman(o.level)) fitted for \(Money.format(o.cost)).", true)
    }

    static func roman(_ n: Int) -> String { ["", "I", "II", "III", "IV", "V", "VI", "VII"][max(0, min(7, n))] }
}

final class GunUpgradeMenu: ListMenu {
    weak var keeper: Mob?
    init(game g: Game, keeper m: Mob) {
        keeper = m
        super.init("Gun Upgrades", game: g)
        subtitle = "Fitted while you wait"
        say(GunUpgrades.offers(g).isEmpty ? "Bring me a gun and I'll make it better." : "Pick an upgrade.", good: true)
    }
    var offers: [GunUpgrades.Offer] = []
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        offers = GunUpgrades.offers(game)
        return offers.map { o in
            let s = game.inventory.main[o.slot]
            let gun = Guns.index(s.item).map { Guns.all[$0].name } ?? s.def.display
            return Row(icon: s, name: "\(Enchant.def(o.ench).name) \(GunUpgrades.roman(o.level))", detail: gun,
                       value: Money.format(o.cost), enabled: game.money >= o.cost)
        }
    }
    override func pressed(_ i: Int) {
        let os = GunUpgrades.offers(game)
        guard i < os.count else { return }
        let r = GunUpgrades.apply(game, os[i])
        say(r.0, good: r.1)
    }
}

// MARK: The saloon's dice

enum Dice {
    static let bets = [100, 500, 1000]
    static var roll: () -> Int = { Rand.int(in: 1...6) }
    static var played = 0

    // Two dice each, the house wins ties. Returns (your total, house total, won).
    static func play(_ g: Game, bet: Int) -> (Int, Int, Bool)? {
        guard bet > 0, g.money >= bet else { return nil }
        let you = roll() + roll(), house = roll() + roll()
        let won = you > house
        g.money += won ? bet : -bet
        played += 1
        g.sfx(won ? .villagerYes : .click, 0.5)
        return (you, house, won)
    }

    // The odds (the house edge test): P(you > house) for two dice each.
    static var winChance: Double {
        var w = 0, n = 0
        for a in 2...12 { for b in 2...12 {
            let ca = 6 - abs(7 - a), cb = 6 - abs(7 - b)
            n += ca * cb
            if a > b { w += ca * cb }
        } }
        return Double(w) / Double(n)
    }
}

final class DiceMenu: ListMenu {
    var last = ""
    init(game g: Game) {
        super.init("High Dice", game: g)
        subtitle = "Beat the house's two dice. Ties go to the house."
        say("Place your bet.", good: true)
    }
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        return Dice.bets.map { b in
            Row(name: "Bet \(Money.format(b))", detail: last.isEmpty ? "Even money" : last, value: Money.format(b), enabled: game.money >= b)
        }
    }
    override func pressed(_ i: Int) {
        guard i < Dice.bets.count, let (you, house, won) = Dice.play(game, bet: Dice.bets[i]) else { return }
        last = "You \(you), house \(house)"
        say(won ? "You rolled \(you) to \(house). You win \(Money.format(Dice.bets[i]))!" : "You rolled \(you) to \(house). The house wins.", good: won)
    }
}
