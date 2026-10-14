import Foundation
import simd

// D18 the saloon's table games beside High Dice (opened from the dice table's last rows).
//   knife game   the knife between the fingers: a stake, then stab the gaps as the point skips along the hand, faster
//                with each stab. Ten clean stabs doubles the stake; a stab on a finger nicks it (half a heart) and
//                loses the stake.
//   poker        five-card draw against the house: ante, hold what you like, draw once; the house draws too (it keeps
//                any pair or better, else its two best cards). Best hand takes the pot (even money); a tie pushes.
enum KnifeGame {
    static let stakes = [100, 500, 2000]
    static let slots = 9                              // gap, finger, gap, ... gap
    static let goal = 10
    static var wins = 0, nicks = 0                    // (tests)
    static func gap(_ i: Int) -> Bool { i % 2 == 0 }
}

final class KnifeGameMenu: ListMenu {
    weak var keeper: Mob?
    var stake = 0, stabs = 0
    var t: Float = 0, at = 0, dir = 1
    init(game g: Game, keeper m: Mob?) {
        keeper = m
        super.init("Knife Game", game: g)
        subtitle = "Stab the gaps, not the fingers. Ten clean stabs doubles your stake."
        say("Lay down a stake.", good: true)
    }
    var playing: Bool { stake > 0 }
    var hand: String {
        (0..<KnifeGame.slots).map { i in i == at ? "V" : (KnifeGame.gap(i) ? "_" : "I") }.joined(separator: " ")
    }
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        if playing {
            return [Row(name: hand, detail: "\(stabs) of \(KnifeGame.goal) stabs", value: "", enabled: true),
                    Row(name: "Stab", detail: KnifeGame.gap(at) ? "Now!" : "Wait for a gap", value: "Stab", enabled: true, good: KnifeGame.gap(at))]
        }
        return KnifeGame.stakes.map { s in Row(name: "Stake \(Money.format(s))", detail: "Win \(Money.format(s)) more", value: Money.format(s), enabled: game.money >= s) }
    }
    override func pressed(_ i: Int) {
        if playing { stab(); return }
        guard i < KnifeGame.stakes.count, game.money >= KnifeGame.stakes[i] else { return }
        stake = KnifeGame.stakes[i]
        game.money -= stake
        stabs = 0; t = 0; at = 0; dir = 1
        say("The hand goes flat on the table. Go.", good: true)
    }
    func stab() {
        game.sfx(.attackWeak, 0.6)
        if KnifeGame.gap(at) {
            stabs += 1
            if stabs >= KnifeGame.goal {
                game.money += stake * 2
                KnifeGame.wins += 1
                say("Ten clean! You take \(Money.format(stake * 2)).", good: true)
                game.sfx(.villagerYes, 0.6)
                stake = 0
            }
            return
        }
        KnifeGame.nicks += 1
        if game.survival { game.hurtPlayer(1, from: game.player.pos, cause: "lost at the knife game", knockback: 0) }
        say("Ow! A nicked finger. The house keeps \(Money.format(stake)).", good: false)
        stake = 0
    }
    override func tick() {
        super.tick()
        if TownServices.keeperGone(game, keeper) { game.closeMenu(); return }
        guard playing else { return }
        t += 1.0 / 60
        let step: Float = 1 / (2.2 + Float(stabs) * 0.45)          // the point skips faster with each stab
        if t >= step {
            t = 0
            at += dir
            if at <= 0 || at >= KnifeGame.slots - 1 { dir = -dir; at = max(0, min(KnifeGame.slots - 1, at)) }
        }
    }
}

enum Poker {
    static let antes = [100, 500, 2000]
    static var hands = 0, won = 0                     // (tests)

    static func name(_ c: Int) -> String {
        let r = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Ace"][c % 13]
        return "\(r) of \(["Spades", "Hearts", "Diamonds", "Clubs"][c / 13])"
    }

    // A hand's value: category (0 high card ... 8 straight flush), then tiebreak ranks.
    static func value(_ h: [Int]) -> [Int] {
        let ranks = h.map { $0 % 13 }
        var count: [Int: Int] = [:]
        for r in ranks { count[r, default: 0] += 1 }
        let groups = count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key > $1.key }
        let flush = Set(h.map { $0 / 13 }).count == 1
        let sorted = ranks.sorted(by: >)
        var straightHigh = -1
        if count.count == 5 {
            if sorted[0] - sorted[4] == 4 { straightHigh = sorted[0] }
            else if sorted == [12, 3, 2, 1, 0] { straightHigh = 3 }          // the wheel
        }
        let tie = groups.map { $0.key }
        let cat: Int
        if straightHigh >= 0 && flush { return [8, straightHigh] }
        if groups[0].value == 4 { cat = 7 }
        else if groups[0].value == 3 && groups.count == 2 { cat = 6 }
        else if flush { return [5] + sorted }
        else if straightHigh >= 0 { return [4, straightHigh] }
        else if groups[0].value == 3 { cat = 3 }
        else if groups[0].value == 2 && groups.count == 3 { cat = 2 }
        else if groups[0].value == 2 { cat = 1 }
        else { cat = 0 }
        return [cat] + tie
    }
    static let names = ["High Card", "a Pair", "Two Pair", "Three of a Kind", "a Straight", "a Flush", "a Full House", "Four of a Kind", "a Straight Flush"]
    static func better(_ a: [Int], _ b: [Int]) -> Int {
        for (x, y) in zip(a, b) where x != y { return x > y ? 1 : -1 }
        return 0
    }

    // The house's discards: keep a pair or better whole, else its two highest cards.
    static func houseDraw(_ h: [Int], _ deck: inout [Int]) -> [Int] {
        if value(h)[0] >= 1 {
            let ranks = h.map { $0 % 13 }
            var count: [Int: Int] = [:]
            for r in ranks { count[r, default: 0] += 1 }
            if value(h)[0] >= 4 { return h }
            return h.map { count[$0 % 13]! >= 2 ? $0 : deck.removeLast() }
        }
        let keep = Set(h.sorted { $0 % 13 > $1 % 13 }.prefix(2))
        return h.map { keep.contains($0) ? $0 : deck.removeLast() }
    }
}

final class PokerMenu: ListMenu {
    weak var keeper: Mob?
    var ante = 0
    var hand: [Int] = [], hold: [Bool] = []
    var deck: [Int] = []
    init(game g: Game, keeper m: Mob?) {
        keeper = m
        super.init("Five-Card Draw", game: g)
        subtitle = "Ante up, hold what you like, draw once. Best hand takes the pot."
        say("Ante up.", good: true)
    }
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        if ante > 0 {
            var r = hand.enumerated().map { (i, c) in
                Row(name: Poker.name(c), detail: hold[i] ? "Held" : "Will be swapped", value: hold[i] ? "Hold" : "Swap", enabled: true, good: hold[i])
            }
            r.append(Row(name: "Draw", detail: "You have \(Poker.names[Poker.value(hand)[0]])", value: "Draw", enabled: true))
            return r
        }
        return Poker.antes.map { a in Row(name: "Ante \(Money.format(a))", detail: "Even money", value: Money.format(a), enabled: game.money >= a) }
    }
    override func pressed(_ i: Int) {
        if ante > 0 {
            if i < 5 { hold[i].toggle(); game.sfx(.click, 0.3); return }
            draw(); return
        }
        guard i < Poker.antes.count, game.money >= Poker.antes[i] else { return }
        ante = Poker.antes[i]
        game.money -= ante
        deck = Array(0..<52).shuffled()
        hand = (0..<5).map { _ in deck.removeLast() }
        hold = Array(repeating: false, count: 5)
        game.sfx(.pageTurn, 0.5)
        say("Your cards. Pick which to hold, then draw.", good: true)
    }
    func draw() {
        for i in 0..<5 where !hold[i] { hand[i] = deck.removeLast() }
        let house = Poker.houseDraw((0..<5).map { _ in deck.removeLast() }, &deck)
        let you = Poker.value(hand), them = Poker.value(house)
        let r = Poker.better(you, them)
        Poker.hands += 1
        let theirs = "the house shows \(Poker.names[them[0]])"
        if r > 0 { game.money += ante * 2; Poker.won += 1; say("\(Poker.names[you[0]].capitalizedFirst) beats \(theirs). You take \(Money.format(ante * 2)).", good: true); game.sfx(.villagerYes, 0.6) }
        else if r == 0 { game.money += ante; say("A push: \(theirs) too. Your ante back.", good: true) }
        else { say("\(Poker.names[you[0]].capitalizedFirst) loses: \(theirs).", good: false) }
        ante = 0
    }
    override func tick() {
        super.tick()
        if TownServices.keeperGone(game, keeper) { game.closeMenu() }
    }
}
