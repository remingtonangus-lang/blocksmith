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
            m.escort = !oldEscort
            g.mobs.mobs.append(m)
            if let t = c.destAt { c.count = Int(simd_length(V2(Float(t[0]) - g.player.pos.x, Float(t[1]) - g.player.pos.z))) }
            save(board, slot, c)
            EscortHUD.seed(key: "\(board)#\(slot)", hp: Float(m.health), clock: g.clock)
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
        // P466 (Oct 25 19:53, a parcel to Silver Gulch taken at a base: "I wanna see that parcel on a map of some kind"):
        // where it goes is on the map at once, and followed (the compass and the beacon), not after the next marks pass.
        if let a = c.target ?? c.destAt, a.count >= 2, g.dim.dim == .overworld {
            Waymarks.marksAt = -1e9
            Waymarks.track(g, Waymarks.Target(kind: "contract", key: "\(board)#\(slot)", name: "Contract: " + what, pos: Waymarks.v(a[0], a[1], g.player.pos.y)))
        }
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
        g.onToast?("Contract done: \(Money.format(c.pay)) from \(patron(g, board))."); Spine.lead(g, from: "Your patron")   // Y6 (P328: the lead is the map marker alone)
        return ("Paid \(Money.format(c.pay)).", true)
    }

    static func split(_ key: String) -> (String, Int)? {
        guard let i = key.lastIndex(of: "#"), let s = Int(key[key.index(after: i)...]) else { return nil }
        return (String(key[..<i]), s)
    }

    // Takes the parcel of contract `key` from the player (main slots, the off hand), sealed or by its label.
    static func takeParcel(_ g: Game, key: String, dest: String?) -> Bool {
        let seal = ["parcel:\(key)"], label = "Parcel for \(dest ?? "?")"
        let paper = Items.has("paper") ? Int(Items.id("paper")) : -1
        for box in [g.inventory.main, g.inventory.offhand] {
            if let i = box.slots.firstIndex(where: { $0.pages == seal }) { box.slots[i] = .empty; return true }
        }
        for box in [g.inventory.main, g.inventory.offhand] {
            if let i = box.slots.firstIndex(where: { Int($0.item) == paper && $0.label == label && $0.pages == nil }) {
                box.slots[i].count -= 1
                if box.slots[i].count <= 0 { box.slots[i] = .empty }
                return true
            }
        }
        return false
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
                // P499 (Oct 30 20:11-20:12 in Flint Valley: "I delivered the parcel... it's not letting me collect pay"):
                // the parcel counts wherever he carries it (either hand, the pack), and by its label if its seal (pages)
                // was lost on the way; only the main slots were searched, by the seal alone.
                guard let t = c.destAt, simd_length(V2(Float(t[0]) - pos.x, Float(t[1]) - pos.z)) < 64 else { continue }
                if takeParcel(g, key: key, dest: c.dest) { pay(g, board, slot, &c) }
            case "escort":
                guard let t = c.destAt else { continue }
                guard let m = g.mobs.mobs.first(where: { $0.kind == .villager && $0.customName == c.who && $0.persistent }) else { continue }
                if m.health <= 0 { c.failed = true; save(board, slot, c); EscortHUD.clear(key: key); g.onToast?("\(c.who ?? "The traveller") is dead. The contract's off"); continue }
                // Follow the player; half way, bandits. Nov 15: they keep to him every frame (Mob.escortStep), riding
                // behind him on his horse; the escort mark is put back on after a load.
                let d = simd_length(m.pos - pos)
                if oldEscort {
                    if d > 4 { m.wanderGoal = pos; m.moving = true; m.aiTimer = 2; m.panic = 0 }
                } else { m.escort = true }
                if d > 40 && m.mount == nil { m.pos = g.world.freeSpawn(pos + V3(1.5, 0, 1.5)) }        // kept up on horseback
                let left = simd_length(V2(Float(t[0]) - m.pos.x, Float(t[1]) - m.pos.z))
                if !c.ambushed, c.count > 0, left < Float(c.count) * 0.55 {
                    c.ambushed = true; save(board, slot, c)
                    bandits(g, near: pos + V3(14, 0, 10), 3, "Road Agent")
                    g.onToast?("Road agents!")
                }
                if left < 40 {
                    if m.mount != nil { m.pos = g.world.freeSpawn(m.pos + V3(1.2, 0, 0)) }
                    m.mount = nil; m.mountOffset = nil; m.escort = false
                    m.customName = nil
                    m.home = m.pos
                    var v = m.villager ?? VillagerData()
                    v.person = c.who; m.villager = v
                    Townsfolk.setup(m, tag: "", game: g)
                    if var v2 = m.villager { v2.town = c.dest; m.villager = v2 }
                    EscortHUD.clear(key: key)
                    pay(g, board, slot, &c)
                }
            case "stage":
                Stagecoach.tick(g, board, slot, c)
            case "camp":
                guard !c.spawned, let t = c.target, simd_length(V2(Float(t[0]) - pos.x, Float(t[1]) - pos.z)) < 60, g.world.isLoaded(t[0], t[1]) else { continue }
                let y = g.world.topY(t[0], t[1]) + 1
                if Blocks.has("campfire") && !Blocks.isLiquid(g.world.builtBlock(t[0], y - 1, t[1])) { g.world.setBlock(t[0], y, t[1], Blocks.id("campfire")) }
                bandits(g, near: V3(Float(t[0]) + 0.5, Float(y), Float(t[1]) + 0.5), c.count, "Bandit")
                c.spawned = true
                save(board, slot, c)
                g.onToast?("The bandit camp!")
            default:
                // Defend: after dark in the town, the raid comes.
                guard TownLaw.inTown == board, TownRaids.night(g.dayFraction), g.raid == nil, !c.spawned else { continue }
                if TownRaids.start(g, town: board) { c.spawned = true; save(board, slot, c) }
            }
        }
        EscortHUD.observe(g, activeEscorts(g))
    }

    static func bandits(_ g: Game, near c: V3, _ n: Int, _ name: String) {
        for i in 0..<n {
            let a = Float(i) * 2.1
            let m = Mob(i % 2 == 0 ? .vindicator : .pillager, at: g.world.freeSpawn(c + V3(cosf(a) * 3, 0, sinf(a) * 3)))
            m.customName = name; m.persistent = true; m.aggro = true; m.lockTime = 20; m.posse = banditPosse
            g.mobs.mobs.append(m)
        }
    }

    // Nov 15 playtest (08:41:05-08:41:12, his escort killed: "That should cause an immediate failure of the... quest,
    // 'cause I kill them"): the once-a-second check looked for the traveller among the living, found nobody (the dead
    // leave that list at once) and so never failed it. The death itself fails it now (BS_OLDESCORT=1: as before, and
    // the old once-a-second follow).
    static let oldEscort = Env.all["BS_OLDESCORT"] == "1"
    static func escortDied(_ g: Game, _ m: Mob) {
        guard !oldEscort, m.kind == .villager, m.persistent, let name = m.customName, let st0 = TownLaw.state.contracts else { return }
        for (key, c0) in st0 where c0.kind == "escort" && c0.taken && !c0.paid && !c0.failed && c0.who == name {
            guard let (board, slot) = split(key) else { continue }
            var c = c0
            c.failed = true
            save(board, slot, c)
            EscortHUD.clear(key: key)
            g.onToast?("\(name) is dead. The contract's off")
            return
        }
    }

    // Honour.mobDied (via TownBoard.mobDied): bandits of a camp.
    static func mobDied(_ g: Game, _ m: Mob) {
        escortDied(g, m)
        guard m.posse == banditPosse, m.customName == "Bandit", let st0 = TownLaw.state.contracts else { return }
        for (key, c0) in st0 where c0.kind == "camp" && c0.taken && c0.spawned && !c0.done {
            guard let t = c0.target, simd_length(V2(Float(t[0]) - m.pos.x, Float(t[1]) - m.pos.z)) < 64, let (board, slot) = split(key) else { continue }
            var c = c0
            c.progress += 1
            if c.progress >= c.count { c.done = true; g.onToast?("The camp is cleared") }
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

// Nov 15 playtest (08:38:36-08:38:51 on an escort: "He needs to follow me"; "You should also be able to ride in the back
// of my horse if I had one"): the traveller was pointed at him once a second through the stroll (which gave up and
// stood), so he walked off and left them. Now, every frame, they walk after him (running when more than 8 behind), stop
// within 3, and while he rides a horse within 10 of them they ride behind him on it, getting down when he does.
extension Mob {
    static let escortMounts: Set<MobKind> = [.horse, .donkey, .mule, .camel]
    func escortStep(_ g: Game) -> Float {
        if let h = g.riding, Mob.escortMounts.contains(h.kind), h.health > 0, simd_length(h.pos - pos) < 10 {
            mount = h
            mountOffset = V3(0, h.height * 0.8 - 0.1, 0.62)
            moving = false; wanderGoal = nil
            return 0
        }
        let pp = g.player.pos
        let dp = simd_length(V2(pp.x - pos.x, pp.z - pos.z))
        wanderGoal = nil
        panic = 0
        guard dp > 3 else { moving = false; return 0 }
        face(pp)
        moving = true
        aiTimer = max(aiTimer, 1)
        // Ledger 414 (Nov 20 evening, his own notes: Willa Ellery lagged behind on a long escort; "they need to move faster"):
        // 2.6 blocks a second close in (his walk is 4.3) and 4.5 behind, so a traveller fell back the whole way. Now they
        // keep his walk inside 8 and his sprint (5.6) further back. BS_OLDESCORTPACE=1: as before.
        if Mob.oldEscortPace { return spec.speed * (dp > 8 ? 2.8 : 1.6) }
        return dp > 8 ? 5.6 : (dp > 5 ? 4.3 : 3.2)
    }
    static let oldEscortPace = Env.all["BS_OLDESCORTPACE"] == "1"
}

extension Contracts {
    struct EscortStatus {
        let key: String
        let name: String
        let dest: String
        let pos: V3
        let dist: Float
        let rel: Float
        let health: Float
        let maxHealth: Float
        let riding: Bool
        let unloaded: Bool
    }

    static func activeEscorts(_ g: Game) -> [EscortStatus] {
        guard g.dim.dim == .overworld, let st0 = TownLaw.state.contracts, !st0.isEmpty else { return [] }
        var hasAny = false
        for c in st0.values where c.kind == "escort" && c.taken && !c.paid && !c.failed { hasAny = true; break }
        guard hasAny else { return [] }
        let p = g.player.pos
        var out: [EscortStatus] = []
        for key in st0.keys.sorted() {
            guard let c = st0[key], c.kind == "escort", c.taken, !c.paid, !c.failed, let who = c.who, !who.isEmpty else { continue }
            if let m = g.mobs.mobs.first(where: { $0.kind == .villager && $0.customName == who && $0.persistent && $0.health > 0 }) {
                let hp = Float(m.health)
                let maxHp = max(EscortHUD.villagerMaxHp, EscortHUD.peakHealth(for: key), hp)
                let dx = m.pos.x - p.x, dz = m.pos.z - p.z
                let horiz = (dx * dx + dz * dz).squareRoot()
                let dist = simd_length(m.pos - p)
                var rel: Float = 0
                if horiz >= 1.5 {
                    rel = atan2f(dx, -dz) + g.player.yaw
                    rel = rel.truncatingRemainder(dividingBy: 2 * .pi)
                    if rel > .pi { rel -= 2 * .pi } else if rel < -.pi { rel += 2 * .pi }
                }
                let riding = g.riding.map { m.mount === $0 } ?? false
                out.append(EscortStatus(key: key, name: who, dest: c.dest ?? "town", pos: m.pos, dist: dist, rel: rel,
                                        health: hp, maxHealth: maxHp, riding: riding, unloaded: false))
            } else {
                var storedPos: V3? = nil
                for (_, list) in g.mobs.stored {
                    if let r = list.first(where: { $0.name == who }), r.p.count >= 3 {
                        storedPos = V3(r.p[0], r.p[1], r.p[2])
                        break
                    }
                }
                if let sp = storedPos {
                    let dx = sp.x - p.x, dz = sp.z - p.z
                    let horiz = (dx * dx + dz * dz).squareRoot()
                    let dist = simd_length(sp - p)
                    var rel: Float = 0
                    if horiz >= 1.5 {
                        rel = atan2f(dx, -dz) + g.player.yaw
                        rel = rel.truncatingRemainder(dividingBy: 2 * .pi)
                        if rel > .pi { rel -= 2 * .pi } else if rel < -.pi { rel += 2 * .pi }
                    }
                    let maxHp = max(EscortHUD.villagerMaxHp, EscortHUD.peakHealth(for: key))
                    let lastHp = EscortHUD.lastHealth(for: key) ?? maxHp
                    out.append(EscortStatus(key: key, name: who, dest: c.dest ?? "town", pos: sp, dist: dist, rel: rel,
                                            health: lastHp, maxHealth: maxHp, riding: false, unloaded: true))
                }
            }
        }
        return out
    }
}

// T07 (Nov 20, part 9: escort jobs had no HUD distance marker or health bar for the escorted NPC, so you could
// outpace her and only learn she died from "the contract's off"). Shows a bearing-eased HUD card for each active
// escorted NPC with her name, directional distance marker, and color-coded health bar, plus damage alerts.
// BS_OLDESCORTHUD=1: nothing.
enum EscortHUD {
    static let old = Env.all["BS_OLDESCORTHUD"] == "1"
    static let villagerMaxHp: Float = max(1, Float(Mob(.villager, at: V3(0, 0, 0)).health))

    struct State {
        var lastHp: Float
        var peakHp: Float
        var hurtAt: Double = -100
        var warnAt: Double = -100
    }
    struct Ease {
        var offset: Float = 0
        var behindSign: Float = 1
        var clock: Double = -1
    }

    static var states: [String: State] = [:]
    static var ease: [String: Ease] = [:]
    private static var lastClock: Double = -1

    static func peakHealth(for key: String) -> Float { states[key]?.peakHp ?? 0 }
    static func lastHealth(for key: String) -> Float? { states[key]?.lastHp }

    static func seed(key: String, hp: Float, clock: Double) {
        if clock < lastClock { states.removeAll(); ease.removeAll() }
        lastClock = clock
        states[key] = State(lastHp: hp, peakHp: max(villagerMaxHp, hp))
    }

    static func clear(key: String) {
        states.removeValue(forKey: key)
        ease = ease.filter { !$0.key.hasPrefix(key + "#") }
    }

    static func observe(_ g: Game, _ escorts: [Contracts.EscortStatus]) {
        if g.clock < lastClock { states.removeAll(); ease.removeAll() }
        lastClock = g.clock
        let live = Set(escorts.map { $0.key })
        if !states.isEmpty { states = states.filter { live.contains($0.key) } }
        if !ease.isEmpty { ease = ease.filter { entry in live.contains(where: { entry.key.hasPrefix($0 + "#") }) } }
        guard !old else { return }
        for e in escorts where !e.unloaded {
            if var st = states[e.key] {
                st.peakHp = max(st.peakHp, e.health)
                if e.health + 0.01 < st.lastHp {
                    st.hurtAt = g.clock
                    let frac = e.health / max(1, st.peakHp)
                    if g.clock - st.warnAt >= 8 || g.clock < st.warnAt {
                        if frac <= 0.35 {
                            st.warnAt = g.clock
                            g.onToast?("\(e.name) is badly hurt!")
                        } else if e.dist > 10 {
                            st.warnAt = g.clock
                            g.onToast?("\(e.name) is under attack!")
                        }
                    }
                }
                st.lastHp = e.health
                states[e.key] = st
            } else {
                states[e.key] = State(lastHp: e.health, peakHp: max(villagerMaxHp, e.health))
            }
        }
    }

    static func lines(_ g: Game, _ L: HudLayout, below: [HudLine] = []) -> [HudLine] {
        guard !old, g.menu == nil, g.alive, g.dim.dim == .overworld else { return [] }
        let escorts = Contracts.activeEscorts(g)
        observe(g, escorts)
        guard !escorts.isEmpty else { return [] }

        let s = L.s
        let cx = L.W / 2
        var y = L.insetY + (Waymarks.hud(g) != nil ? 36 * s : 22 * s)
        if let wy = WaymarkEase.y, g.clock - WaymarkEase.clock < 1, wy >= L.insetY, wy < L.H * 0.3 {
            y = max(y, wy + 14 * s)
        }
        for l in below where l.y < L.H * 0.3 {
            let lw = l.box?.x ?? (Float(Font.width(l.text)) * l.scale)
            if l.x + lw > cx - L.W * 0.25 && l.x < cx + L.W * 0.25 {
                let lh = l.box?.y ?? (10 * l.scale)
                y = max(y, l.y + lh + 4 * s)
            }
        }
        y = min(y, L.H * 0.36)

        let seat = g.coop.active ? g.coop.current : 0
        let padX = 4 * s, padY = 3 * s
        let boxH = 24 * s
        var out: [HudLine] = []

        for (idx, e) in escorts.enumerated() {
            let eKey = "\(e.key)#\(seat)"
            var es = ease[eKey] ?? Ease()
            if abs(e.rel) < 2.85 && abs(e.rel) > 0.2 {
                es.behindSign = e.rel >= 0 ? 1 : -1
            }
            let effRel: Float = abs(e.rel) >= 2.85 ? es.behindSign * .pi : e.rel
            let targetOff: Float = (e.riding || e.dist <= 4) ? 0 : max(-1, min(1, effRel / (.pi * 0.45)))
            let dt = es.clock < 0 || g.clock < es.clock ? 1 : Float(max(0, min(0.25, g.clock - es.clock)))
            let alpha = es.clock < 0 || g.clock < es.clock ? 1 : min(1, dt * 10)
            es.offset += (targetOff - es.offset) * alpha
            es.clock = g.clock
            ease[eKey] = es

            let st = states[e.key]
            let hurtAge = st.map { Float(g.clock - $0.hurtAt) } ?? 99
            let hurt = hurtAge >= 0 && hurtAge < 1.5
            let hpFrac = max(0, min(1, e.health / max(1, e.maxHealth)))

            let distStr = e.riding ? "Riding" : "\(Int(e.dist.rounded())) m"
            let leftArrow = (!e.riding && e.dist > 4 && effRel < -.pi * 0.16)
                ? (abs(e.rel) > .pi * 0.72 ? "<< " : "< ") : ""
            let rightArrow = (!e.riding && e.dist > 4 && effRel > .pi * 0.16)
                ? (abs(e.rel) > .pi * 0.72 ? " >>" : " >") : ""
            let leftText = leftArrow + e.name
            let rightText = distStr + rightArrow
            let leftW = Float(Font.width(leftText)) * s
            let rightW = Float(Font.width(rightText)) * s
            let maxInt = max(1, Int(ceil(e.maxHealth)))
            let curInt = min(maxInt, max(1, Int(ceil(e.health))))
            let hpText = e.unloaded ? "?" : "\(curInt)/\(maxInt)"
            let hpW = Float(Font.width(hpText)) * s

            let innerW = max(108 * s, leftW + rightW + 10 * s)
            let boxW = innerW + padX * 2
            let maxSpan = max(0, (L.W - 2 * L.insetX - boxW) / 2 - 4 * s)
            let span = min(maxSpan, min(L.W * 0.25, 96 * s))
            let bx = floor(cx + es.offset * span - boxW / 2)
            let by = floor(y + Float(idx) * (boxH + 3 * s))

            let hpColor: V4 = (hurt && sinf(hurtAge * 20) > 0)
                ? V4(1, 0.35, 0.3, 1)
                : (hpFrac < 0.35 ? Settings.shared.badColor : (hpFrac < 0.65 ? V4(0.95, 0.75, 0.2, 1) : Settings.shared.goodColor))
            let distColor: V4 = e.riding
                ? V4(0.65, 0.92, 0.72, 1)
                : (e.dist > 30 ? Settings.shared.badColor : (e.dist > 18 ? V4(0.95, 0.75, 0.2, 1) : V4(0.9, 0.94, 0.98, 1)))
            let cardBg = hurt ? V4(0.32, 0.04, 0.04, 0.72) : V4(0, 0, 0, 0.55)

            out.append(HudLine(text: "", x: bx, y: by, scale: s, bg: cardBg, box: V2(boxW, boxH)))
            out.append(HudLine(text: "", x: bx, y: by, scale: s, bg: hpColor, box: V2(2 * s, boxH)))
            out.append(HudLine(text: leftText, x: bx + padX + s, y: by + padY, scale: s, color: V4(1, 0.92, 0.65, 1)))
            out.append(HudLine(text: rightText, x: bx + boxW - padX - rightW, y: by + padY, scale: s, color: distColor))

            let barX = bx + padX + s
            let barY = by + 14 * s
            let barW = max(24 * s, innerW - s - hpW - 5 * s)
            out.append(HudLine(text: "", x: barX, y: barY, scale: s, bg: V4(0.2, 0.2, 0.22, 0.9), box: V2(barW, 5 * s)))
            out.append(HudLine(text: "", x: barX, y: barY, scale: s, bg: hpColor, box: V2(barW * hpFrac, 5 * s)))
            out.append(HudLine(text: hpText, x: bx + boxW - padX - hpW, y: by + 13 * s, scale: s,
                               color: (hpFrac < 0.35 || hurt) ? Settings.shared.badColor : V4(0.85, 0.88, 0.92, 0.95)))
        }
        return out
    }
}
