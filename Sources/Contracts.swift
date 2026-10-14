import Foundation
import simd

// Jobs and contracts (backlog C11; docs/status/contracts.md). Beside the notice board's two daily town jobs (TownBoard:
// deliveries, hunts, outlaws), every town's board and the map table of every Greywall base you hold post two contracts
// a day, each for a patron (the town, its country when it has one, or your base's quartermaster):
//   courier  carry a sealed parcel to another town 500-1,500 blocks off; paid when you walk into that town with it.
//   escort   a traveller walks with you to another town; bandits wait half way. Paid when they reach it alive.
//   camp     clear a bandit camp 120-220 blocks out (a campfire and four or five bandits); paid back at the board.
//   defend   raiders ride on the town tonight: be there after dark and beat them off (the night raid, TownRaids).
// Each pays dollars and honour, and raises your standing with the patron's country (+3); a contract taken and not done
// in three days lapses. Saved in TownLaw.Saved.contracts ("<board>#<slot>").
struct Contract: Codable {
    var day: Int
    var kind: String                  // courier, escort, camp, defend
    var board: String                 // the patron's board: a town's name, or "greywall:x,z"
    var dest: String? = nil           // courier, escort: the town to reach
    var destAt: [Int]? = nil          // its anchor (x, z)
    var target: [Int]? = nil          // camp: where it stands (x, z)
    var pay: Int
    var honour: Float
    var taken = false
    var done = false
    var paid = false
    var failed = false
    var spawned = false
    var ambushed = false
    var count = 0                     // camp: bandits; escort: the traveller's name lives in `who`
    var progress = 0
    var who: String? = nil
}

enum Contracts {
    static let banditPosse = 6
    static let slots = 2
    static var completed = 0          // (tests)

    static var all: [String: Contract] {
        get { TownLaw.state.contracts ?? [:] }
        set { TownLaw.state.contracts = newValue }
    }
    static func isBase(_ board: String) -> Bool { board.hasPrefix("greywall:") }
    static func boardAt(_ board: String) -> (Int, Int)? {
        if isBase(board) {
            let xz = board.dropFirst("greywall:".count).split(separator: ",").compactMap { Int($0) }
            return xz.count == 2 ? (xz[0], xz[1]) : nil
        }
        if let a = Countries.state.towns[board], a.count == 2 { return (a[0], a[1]) }
        return nil
    }
    static func patron(_ g: Game, _ board: String) -> String {
        if isBase(board) { return "your base's quartermaster" }
        if let c = Countries.ofKnown(g, town: board) { return "\(board), for \(c.name)" }
        return board
    }

    // MARK: Today's contracts on a board

    static func contracts(_ g: Game, board: String, at a: IVec3) -> [Contract] {
        let day = Int(g.time / DAY_LENGTH)
        var out: [Contract] = []
        var st = all
        for slot in 0..<slots {
            let key = "\(board)#\(slot)"
            if let c = st[key], c.day == day || (c.taken && !c.paid && !c.failed && day - c.day < 3) { out.append(c); continue }
            let c = make(g, board, a, day, slot)
            st[key] = c
            out.append(c)
        }
        all = st
        return out
    }
    static func save(_ board: String, _ slot: Int, _ c: Contract) { var st = all; st["\(board)#\(slot)"] = c; all = st }

    static func make(_ g: Game, _ board: String, _ a: IVec3, _ day: Int, _ slot: Int) -> Contract {
        let h = TownBoard.hash(board, day, 40 + slot)
        let base = isBase(board)
        let kinds = base ? ["camp", "courier"] : (slot == 0 ? ["courier", "escort", "stage"] : ["camp", "defend"])
        let kind = kinds[Int(h % UInt64(kinds.count))]
        var c = Contract(day: day, kind: kind, board: board, pay: 0, honour: 5)
        switch kind {
        case "courier", "escort", "stage":
            if let (name, at) = destination(g, from: a, h) {
                let d = simd_length(V2(Float(at.0 - a.x), Float(at.1 - a.z)))
                c.dest = name; c.destAt = [at.0, at.1]
                c.pay = (kind == "stage" ? 600 : kind == "escort" ? 400 : 200) + Int(d * (kind == "stage" ? 1.1 : kind == "escort" ? 0.9 : 0.5))
                c.honour = kind == "stage" ? 8 : kind == "escort" ? 7 : 4
                if kind != "courier" { c.who = "\(Townsfolk.pick(Townsfolk.firstNames, h >> 20)) \(Townsfolk.pick(Townsfolk.surnames, h >> 36))" }
            } else {
                c.kind = "camp"
            }
        default: break
        }
        if c.kind == "camp" {
            let ang = Float(h % 360) * .pi / 180, r = 120 + Float((h >> 9) % 101)
            c.target = [a.x + Int(sinf(ang) * r), a.z - Int(cosf(ang) * r)]
            c.count = 4 + Int((h >> 17) % 2)
            c.pay = 700 + 150 * c.count
            c.honour = 6
        } else if c.kind == "defend" {
            c.pay = 1500
            c.honour = 8
        }
        return c
    }

    // Another town 500-1,500 blocks off: the village nearest a point out along a seeded bearing.
    static func destination(_ g: Game, from a: IVec3, _ h: UInt64) -> (String, (Int, Int))? {
        guard let sc = g.world.gen.structures else { return nil }
        for k in 0..<8 {
            let ang = Float((h >> 4) % 360 + UInt64(k) * 45) * .pi / 180
            let r: Float = 600 + Float((h >> 13) % 600)
            let px = a.x + Int(sinf(ang) * r), pz = a.z - Int(cosf(ang) * r)
            guard let s = sc.nearest("village", x: px, z: pz, maxRegions: 1) else { continue }
            let d = simd_length(V2(Float(s.anchor.x - a.x), Float(s.anchor.z - a.z)))
            guard d >= 500 && d <= 1500 else { continue }
            return (Townsfolk.townName(s.anchor.x, s.anchor.z, seed: g.world.seed), (s.anchor.x, s.anchor.z))
        }
        return nil
    }

    static func describe(_ g: Game, _ c: Contract) -> (String, String) {
        let left = c.paid ? "Done. Paid." : (c.failed ? "Failed." : nil)
        func far(_ t: [Int]) -> String {
            let d = V2(Float(t[0]) + 0.5 - g.player.pos.x, Float(t[1]) + 0.5 - g.player.pos.z)
            return "\(Int(simd_length(d))) blocks \(TownBoard.direction(d.x, d.y))"
        }
        switch c.kind {
        case "courier":
            let what = "Parcel to \(c.dest ?? "a town")"
            return (what, left ?? (c.taken ? "Hand it over there: \(c.destAt.map(far) ?? "")" : "Press to take the parcel"))
        case "escort":
            let what = "Escort \(c.who ?? "a traveller")"
            return (what, left ?? (c.taken ? "To \(c.dest ?? "town"): \(c.destAt.map(far) ?? "")" : "To \(c.dest ?? "town"). Press to set off"))
        case "stage":
            let what = "Ride guard on the stage"
            return (what, left ?? (c.taken ? "To \(c.dest ?? "town"): \(c.destAt.map(far) ?? "")" : "To \(c.dest ?? "town"). Press to ride with it"))
        case "camp":
            let what = "Clear a bandit camp"
            if c.done && !c.paid { return (what, "Done: press to collect") }
            return (what, left ?? (c.taken ? "\(c.progress) of \(c.count) bandits; the camp is \(c.target.map(far) ?? "")" : "\(c.count) bandits. Press to take it"))
        default:
            let what = "Defend the town tonight"
            return (what, left ?? (c.taken ? "Be in town after dark" : "Raiders are coming. Press to stand with the town"))
        }
    }

    // A press on a contract's row.
    static func use(_ g: Game, board: String, at a: IVec3, _ slot: Int) -> (String, Bool) {
        var c = contracts(g, board: board, at: a)[slot]
        if c.paid { return ("That contract is closed.", false) }
        if c.failed { return ("That contract fell through.", false) }
        if c.taken {
            if c.kind == "camp" && c.done { return pay(g, board, slot, &c) }
            return (describe(g, c).1, false)
        }
        c.taken = true
        switch c.kind {
        case "courier":
            guard Items.has("paper") else { return ("No parcel to give.", false) }
            var p = ItemStack(Items.id("paper"), 1)
            p.label = "Parcel for \(c.dest ?? "?")"
            p.pages = ["parcel:\(board)#\(slot)"]
            if !g.inventory.main.add(p).isEmpty { return ("Make room for the parcel first.", false) }
            save(board, slot, c)
            fileOrders(g, board, slot, c)
            return ("Here's the parcel. Hand it over in \(c.dest ?? "town") yourself.", true)
        case "escort":
            let m = Mob(.villager, at: g.world.freeSpawn(g.player.pos + V3(1.5, 0, 1.5)))
            m.persistent = true
            m.customName = c.who                      // (a townsperson of the town they reach, not of the road)
            g.mobs.mobs.append(m)
            if let t = c.destAt { c.count = Int(simd_length(V2(Float(t[0]) - g.player.pos.x, Float(t[1]) - g.player.pos.z))) }
            save(board, slot, c)
            fileOrders(g, board, slot, c)
            return ("\(c.who ?? "The traveller") will follow you to \(c.dest ?? "town").", true)
        case "stage":
            guard Stagecoach.take(g, &c) else { return ("The stage can't stand here. Try in the open.", false) }
            save(board, slot, c)
            fileOrders(g, board, slot, c)
            return ("\(c.who ?? "The driver") whips up. Stay close: the stage waits for no one but you.", true)
        case "defend":
            save(board, slot, c)
            fileOrders(g, board, slot, c)
            return ("Be in \(board) after dark. They'll come.", true)
        default:
            save(board, slot, c)
            fileOrders(g, board, slot, c)
            return ("The camp is \(describe(g, c).1.components(separatedBy: "camp is ").last ?? "out there").", true)
        }
    }

    // R24: a contract taken is filed in the Journal (Orders) with its terms, once.
    static func fileOrders(_ g: Game, _ board: String, _ slot: Int, _ c: Contract) {
        let what = describe(g, c).0
        var body = "Patron: \(patron(g, board)).\nPay: \(Money.format(c.pay)) and honour on completion.\n\n"
        switch c.kind {
        case "courier":
            body += "Carry the sealed parcel to \(c.dest ?? "the town") and hand it over there yourself."
        case "escort":
            body += "\(c.who ?? "A traveller") walks with you to \(c.dest ?? "town"). Keep them alive: bandits wait on the road."
        case "stage":
            body += "Ride guard on \(c.who ?? "the driver")'s stage to \(c.dest ?? "town"). It waits while you fall behind; road agents work that road."
        case "camp":
            var far = "out in the wilds"
            if let t = c.target, t.count == 2 {
                let d = V2(Float(t[0]) + 0.5 - g.player.pos.x, Float(t[1]) + 0.5 - g.player.pos.z)
                far = "\(Int(simd_length(d))) blocks \(TownBoard.direction(d.x, d.y)) of the board"
            }
            body += "A bandit camp of \(c.count) stands \(far). Clear it, then collect your pay at the board."
        default:
            body += "Raiders ride on \(board) tonight. Be in town after dark and beat them off."
        }
        body += "\n\nTaken on day \(c.day + 1). It lapses if not done within three days."
        g.logDocument("Contract: \(what)", [body], cat: .orders, id: "contract:\(board)#\(slot)#\(c.day)")
    }

    @discardableResult
    static func pay(_ g: Game, _ board: String, _ slot: Int, _ c: inout Contract) -> (String, Bool) {
        c.done = true; c.paid = true
        save(board, slot, c)
        g.money += c.pay
        g.sfx(.villagerTrade, 0.7)
        Honour.earn(g, c.honour, source: "job", "a contract for \(patron(g, board))")
        if !isBase(board), let k = Countries.ofKnown(g, town: board) { Countries.change(g, k, 3) }
        completed += 1
        g.onToast?("Contract done: \(Money.format(c.pay)) from \(patron(g, board))." + Spine.lead(g, from: "Your patron"))   // Y6
        return ("Paid \(Money.format(c.pay)).", true)
    }

    static func split(_ key: String) -> (String, Int)? {
        guard let i = key.lastIndex(of: "#"), let s = Int(key[key.index(after: i)...]) else { return nil }
        return (String(key[..<i]), s)
    }

    // MARK: Once a second (TownLaw.tick)

    static func tick(_ g: Game) {
        guard g.dim.dim == .overworld, let st0 = TownLaw.state.contracts, !st0.isEmpty else { return }
        let day = Int(g.time / DAY_LENGTH)
        let pos = g.player.pos
        for (key, c0) in st0 where c0.taken && !c0.paid && !c0.failed {
            guard let (board, slot) = split(key) else { continue }
            var c = c0
            if day - c.day >= 3 {
                c.failed = true; save(board, slot, c)
                g.onToast?("A contract for \(patron(g, board)) has lapsed")
                continue
            }
            switch c.kind {
            case "courier":
                let parcel = g.inventory.main.slots.firstIndex { $0.pages == ["parcel:\(key)"] }
                guard let i = parcel, let t = c.destAt else { continue }
                if simd_length(V2(Float(t[0]) - pos.x, Float(t[1]) - pos.z)) < 64 {
                    g.inventory.main.slots[i] = .empty
                    pay(g, board, slot, &c)
                }
            case "escort":
                guard let t = c.destAt else { continue }
                guard let m = g.mobs.mobs.first(where: { $0.kind == .villager && $0.customName == c.who && $0.persistent }) else { continue }
                if m.health <= 0 { c.failed = true; save(board, slot, c); g.onToast?("\(c.who ?? "The traveller") is dead. The contract's off"); continue }
                // Follow the player; half way, bandits.
                let d = simd_length(m.pos - pos)
                if d > 4 { m.wanderGoal = pos; m.moving = true; m.aiTimer = 2; m.panic = 0 }
                if d > 40 { m.pos = g.world.freeSpawn(pos + V3(1.5, 0, 1.5)) }        // kept up on horseback
                let left = simd_length(V2(Float(t[0]) - m.pos.x, Float(t[1]) - m.pos.z))
                if !c.ambushed, c.count > 0, left < Float(c.count) * 0.55 {
                    c.ambushed = true; save(board, slot, c)
                    bandits(g, near: pos + V3(14, 0, 10), 3, "Road Agent")
                    g.onToast?("Road agents! Keep \(c.who ?? "the traveller") alive")
                }
                if left < 40 {
                    m.customName = nil
                    m.home = m.pos
                    var v = m.villager ?? VillagerData()
                    v.person = c.who; m.villager = v
                    Townsfolk.setup(m, tag: "", game: g)
                    if var v2 = m.villager { v2.town = c.dest; m.villager = v2 }
                    pay(g, board, slot, &c)
                }
            case "stage":
                Stagecoach.tick(g, board, slot, c)
            case "camp":
                guard !c.spawned, let t = c.target, simd_length(V2(Float(t[0]) - pos.x, Float(t[1]) - pos.z)) < 60, g.world.isLoaded(t[0], t[1]) else { continue }
                let y = g.world.topY(t[0], t[1]) + 1
                if Blocks.has("campfire") && !Blocks.isLiquid(g.world.block(t[0], y - 1, t[1])) { g.world.setBlock(t[0], y, t[1], Blocks.id("campfire")) }
                bandits(g, near: V3(Float(t[0]) + 0.5, Float(y), Float(t[1]) + 0.5), c.count, "Bandit")
                c.spawned = true
                save(board, slot, c)
                g.onToast?("The bandit camp! Clear it")
            default:
                // Defend: after dark in the town, the raid comes.
                guard TownLaw.inTown == board, TownRaids.night(g.dayFraction), g.raid == nil, !c.spawned else { continue }
                if TownRaids.start(g, town: board) { c.spawned = true; save(board, slot, c) }
            }
        }
    }

    static func bandits(_ g: Game, near c: V3, _ n: Int, _ name: String) {
        for i in 0..<n {
            let a = Float(i) * 2.1
            let m = Mob(i % 2 == 0 ? .vindicator : .pillager, at: g.world.freeSpawn(c + V3(cosf(a) * 3, 0, sinf(a) * 3)))
            m.customName = name; m.persistent = true; m.aggro = true; m.lockTime = 20; m.posse = banditPosse
            g.mobs.mobs.append(m)
        }
    }

    // Honour.mobDied (via TownBoard.mobDied): bandits of a camp.
    static func mobDied(_ g: Game, _ m: Mob) {
        guard m.posse == banditPosse, m.customName == "Bandit", let st0 = TownLaw.state.contracts else { return }
        for (key, c0) in st0 where c0.kind == "camp" && c0.taken && c0.spawned && !c0.done {
            guard let t = c0.target, simd_length(V2(Float(t[0]) - m.pos.x, Float(t[1]) - m.pos.z)) < 64, let (board, slot) = split(key) else { continue }
            var c = c0
            c.progress += 1
            if c.progress >= c.count { c.done = true; g.onToast?("The camp is cleared. Collect your pay at \(isBase(board) ? "your base" : board)'s board") }
            save(board, slot, c)
            return
        }
    }

    // TownRaids.won: a defence contract for that town.
    static func raidWon(_ g: Game, _ town: String) {
        for (key, c0) in all where c0.kind == "defend" && c0.board == town && c0.taken && !c0.paid {
            guard let (board, slot) = split(key) else { continue }
            var c = c0
            pay(g, board, slot, &c)
        }
    }
}

// A taken Greywall base's contracts and its war report (the map table).
final class BaseContractsMenu: ListMenu {
    let board: String
    let at: IVec3
    init(game: Game, board: String, at: IVec3) {
        self.board = board; self.at = at
        super.init("Quartermaster's Contracts", game: game)
        subtitle = "Work for your base"
    }
    override var rows: [Row] {
        let cs = Contracts.contracts(game, board: board, at: at)
        var out = cs.map { c -> Row in
            let (n, d) = Contracts.describe(game, c)
            return Row(name: n, detail: d, value: Money.format(c.pay), enabled: !c.paid && !c.failed)
        }
        out.append(Row(icon: Items.has("written_book") ? ItemStack(Items.id("written_book"), 1) : .empty, name: "Read the war report",
                       detail: "The fronts near this base"))
        return out
    }
    override func pressed(_ i: Int) {
        if i == Contracts.slots { game.closeMenu(); WarFront.openReport(game); return }
        let r = Contracts.use(game, board: board, at: at, i)
        say(r.0, good: r.1)
    }
}
