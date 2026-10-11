import Foundation
import simd

// The stable (the gap pass, A1e and ER7: "a stable to keep and swap horses", "Stable UI: buy, sell, store, swap"; ER1:
// "name your horse", VR-friendly). The stablehand's shop has a "Horses" button that opens StableMenu:
//   buy     a horse of any breed, saddled, tamed and yours (it becomes the one that comes when called);
//   stable  a horse of yours standing near the stable: it is kept (its whole record: name, breed, bond, gear, bags)
//           and leaves the world; up to six, in any town's stable;
//   take    one back out here (a horse kept in another town's stable is brought over for a small fee); it becomes the
//           one that comes when called, so swapping horses is stable one, take out another;
//   sell    a horse of yours near the stable, for half its breed's price and a little for its bond;
//   rename  your horse from a list of names (no typing in VR): each press gives the next name.
// Kept horses are saved in TownLaw.Saved.stabled.
struct StabledHorse: Codable {
    var rec: MobRecord
    var town: String
    var day: Int
}

enum Stable {
    static let maxKept = 6
    static let fetchFee = 200                     // cents: a horse kept in another town's stable, brought over
    static let near: Float = 24                   // how close to the stablehand a horse must stand to be stabled or sold
    static var kept: [StabledHorse] {
        get { TownLaw.state.stabled ?? [] }
        set { TownLaw.state.stabled = newValue.isEmpty ? nil : newValue }
    }

    // Your horses standing near the stable (not down; the one you ride counts: you get off).
    static func nearby(_ g: Game, _ at: V3) -> [Mob] {
        g.mobs.mobs.filter { $0.gaited && $0.yours && $0.health > 0 && $0.downed <= 0 && simd_length($0.pos - at) < near }
    }

    static func name(_ m: Mob) -> String { m.customName ?? "your horse" }
    static func name(_ s: StabledHorse) -> String { s.rec.name ?? "Your horse" }
    static func breed(_ s: StabledHorse) -> HorseBreed {
        HorseBreed(rawValue: Int(s.rec.extra?["breed"] ?? 0)) ?? .mustang
    }

    static func sellValue(_ m: Mob) -> Int { m.horseBreed.price / 2 + 200 * max(0, m.bondLevel - 1) }

    // Ground beside the stablehand for a horse to stand on.
    static func spot(_ g: Game, _ at: V3) -> V3 {
        let x0 = Int(floor(at.x)), z0 = Int(floor(at.z))
        for r in 2...6 {
            for (dx, dz) in [(r, 0), (-r, 0), (0, r), (0, -r), (r, r), (-r, r), (r, -r), (-r, -r)] {
                if let p = g.groundSpot(x0 + dx, z0 + dz), abs(p.y - at.y) < 4 { return p }
            }
        }
        return g.world.freeSpawn(at)
    }

    static func buy(_ g: Game, _ b: HorseBreed, at: V3) -> (String, Bool) {
        guard g.money >= b.price else { return ("A \(b.name) is \(Money.format(b.price)). You have \(Money.format(g.money)).", false) }
        let m = Mob(.horse, at: spot(g, at))
        HorseLife.roll(m, breed: b)
        m.owner = true
        m.saddled = true
        m.persistent = true
        m.yaw = Rand.float(in: 0..<(2 * .pi))
        g.mobs.mobs.append(m)
        g.money -= b.price
        g.makeCurrentHorse(m)
        g.sfx(.mob(m.kind, .ambient), 1, at: m.pos)
        bought += 1
        return ("\(name(m)) the \(b.name) is yours, saddled and waiting outside.", true)
    }

    static func store(_ g: Game, _ m: Mob, town: String) -> (String, Bool) {
        guard kept.count < maxKept else { return ("Every stall's full: \(maxKept) horses at most.", false) }
        guard m.health > 0, m.downed <= 0, m.yours else { return ("That horse isn't here.", false) }
        if g.riding === m { g.dismount() }
        m.stayAt = nil
        var k = kept
        k.append(StabledHorse(rec: m.record, town: town, day: Int(g.time / DAY_LENGTH)))
        kept = k
        g.mobs.mobs.removeAll { $0 === m }
        stored += 1
        return ("\(name(m)) is in a stall at \(town). Fed and brushed.", true)
    }

    static func takeOut(_ g: Game, _ i: Int, town: String, at: V3) -> (String, Bool) {
        var k = kept
        guard i >= 0, i < k.count else { return ("That stall's empty.", false) }
        let s = k[i]
        let fee = s.town == town ? 0 : fetchFee
        guard g.money >= fee else { return ("Bringing \(name(s)) over from \(s.town) costs \(Money.format(fee)).", false) }
        guard let m = Mob.from(s.rec) else { return ("That stall's empty.", false) }
        m.pos = spot(g, at)
        m.vel = .zero
        m.stayAt = nil
        k.remove(at: i)
        kept = k
        g.money -= fee
        g.mobs.mobs.append(m)
        g.makeCurrentHorse(m)
        takenOut += 1
        return (fee > 0 ? "\(name(s)) came over from \(s.town) (\(Money.format(fee))): waiting outside." : "\(name(s)) is waiting outside.", true)
    }

    static func sell(_ g: Game, _ m: Mob) -> (String, Bool) {
        guard m.health > 0, m.downed <= 0, m.yours else { return ("That horse isn't here.", false) }
        if g.riding === m { g.dismount() }
        let v = sellValue(m)
        if m.bond == g.horseBond { g.horseBond = 0 }
        g.mobs.mobs.removeAll { $0 === m }
        g.money += v
        sold += 1
        return ("Sold \(name(m)) for \(Money.format(v)). They'll treat it well.", true)
    }

    static func rename(_ m: Mob) -> String {
        m.customName = HorseLife.nextName(m.customName)
        return m.customName ?? ""
    }

    static var bought = 0, stored = 0, takenOut = 0, sold = 0, opened = 0
}

// The stable's horse menu (StableMenu), from the stablehand's shop ("Horses").
final class StableMenu: ListMenu {
    weak var keeper: Mob?
    let town: String
    private enum Act { case buy(HorseBreed), store(Mob), take(Int), sell(Mob), rename(Mob) }
    private var acts: [Act] = []

    init(game g: Game, keeper m: Mob) {
        keeper = m
        town = m.villager?.town ?? Townsfolk.town(g, at: m.pos)
        super.init("Horses", game: g)
        subtitle = "\(town) Stable"
        let mine = Stable.nearby(g, m.pos).count, kept = Stable.kept.count
        say(mine + kept == 0 ? "Looking for a horse? Every one here's broke to the saddle." : "Your horses are in good hands.", good: true)
        Stable.opened += 1
    }

    private var at: V3 { keeper?.pos ?? game.player.pos }

    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        var out: [Row] = []
        acts = []
        let saddle = Items.has("saddle") ? ItemStack(Items.id("saddle"), 1) : ItemStack.empty
        let hay = Items.has("hay_block") ? ItemStack(Items.id("hay_block"), 1) : ItemStack.empty
        let mine = Stable.nearby(game, at)
        for m in mine {
            let lv = m.bondLevel
            out.append(Row(icon: saddle, name: "Stable \(Stable.name(m))", detail: "\(m.horseBreed.name), bond \(lv)", value: "Free",
                           enabled: Stable.kept.count < Stable.maxKept))
            acts.append(.store(m))
        }
        for (i, s) in Stable.kept.enumerated() {
            let here = s.town == town
            out.append(Row(icon: hay, name: "Take out \(Stable.name(s))", detail: here ? Stable.breed(s).name : "\(Stable.breed(s).name), kept at \(s.town)",
                           value: here ? "Free" : Money.format(Stable.fetchFee), enabled: here || game.money >= Stable.fetchFee))
            acts.append(.take(i))
        }
        for m in mine {
            out.append(Row(name: "Rename \(Stable.name(m))", detail: "Next name: \(HorseLife.nextName(m.customName))", value: ""))
            acts.append(.rename(m))
        }
        for b in HorseBreed.allCases {
            out.append(Row(name: "Buy a \(b.name)", detail: b.blurb, value: Money.format(b.price), enabled: game.money >= b.price))
            acts.append(.buy(b))
        }
        for m in mine {
            out.append(Row(name: "Sell \(Stable.name(m))", detail: m.horseBreed.name, value: Money.format(Stable.sellValue(m))))
            acts.append(.sell(m))
        }
        return out
    }

    override func tick() {
        super.tick()
        if TownServices.keeperGone(game, keeper) { game.closeMenu() }
    }

    override func pressed(_ i: Int) {
        _ = rows
        guard i >= 0, i < acts.count else { return }
        let r: (String, Bool)
        switch acts[i] {
        case .buy(let b): r = Stable.buy(game, b, at: at)
        case .store(let m): r = Stable.store(game, m, town: town)
        case .take(let k): r = Stable.takeOut(game, k, town: town, at: at)
        case .sell(let m): r = Stable.sell(game, m)
        case .rename(let m): r = ("Your horse is called \(Stable.rename(m)) now.", true)
        }
        say(r.0, good: r.1)
    }
}
