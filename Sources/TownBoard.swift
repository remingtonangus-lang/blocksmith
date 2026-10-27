import Foundation
import simd

// The town notice board (the gap pass, docs/status/cloud-gap-pass.md): every town's WANTED board in the sheriff's
// office opens it, and so does talking to the sheriff or a deputy when you owe nothing. It shows
//   - your honour, the reason for its last change and the latest entries of the honour log;
//   - wanted posters: every bounty on your head, town by town;
//   - two jobs a day per town, the redemption path the brief asks for: a delivery (bring N of something the town needs,
//     paid below any shop's price so no money loop opens), a hunt (clear N monsters within 96 blocks of the town) and
//     an outlaw to bring in (a named Brigand with a companion, last seen 80-140 blocks out; killed, the job is done);
//     each pays dollars and honour (capped per day, Honour.dailyCap);
//   - a donation to the town fund ($1 for 2 honour, 6 honour a day at most);
//   - your name as the town knows it (VR friendly: a press picks the next name; townsfolk who think well of you
//     greet you by it, and it is on your wanted posters).
// While you're wanted in a town or an outlaw, its WANTED boards show your own poster (TownBoard.posters).

struct TownJob: Codable {
    var day: Int
    var kind: String                 // deliver, hunt, outlaw
    var item: String? = nil          // deliver: the item key
    var count: Int
    var pay: Int                     // cents
    var honour: Float
    var progress = 0
    var taken = false
    var done = false
    var paid = false
    var anchor: [Int]? = nil         // the town's board (x, z): hunts count kills within 96 blocks of it
    var target: [Int]? = nil         // outlaw: where he was last seen (x, z)
    var outlaw: String? = nil        // outlaw: his name
    var spawned: Bool? = nil

    init(day: Int, kind: String, item: String? = nil, count: Int, pay: Int, honour: Float, outlaw: String? = nil) {
        self.day = day; self.kind = kind; self.item = item; self.count = count; self.pay = pay; self.honour = honour; self.outlaw = outlaw
    }
    // Tolerant: a missing flag reads as its default (one odd job never costs the whole town-law save).
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        day = try c.decodeIfPresent(Int.self, forKey: .day) ?? 0
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "hunt"
        item = try c.decodeIfPresent(String.self, forKey: .item)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        pay = try c.decodeIfPresent(Int.self, forKey: .pay) ?? 0
        honour = try c.decodeIfPresent(Float.self, forKey: .honour) ?? 0
        progress = try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        taken = try c.decodeIfPresent(Bool.self, forKey: .taken) ?? false
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        paid = try c.decodeIfPresent(Bool.self, forKey: .paid) ?? false
        anchor = try c.decodeIfPresent([Int].self, forKey: .anchor)
        target = try c.decodeIfPresent([Int].self, forKey: .target)
        outlaw = try c.decodeIfPresent(String.self, forKey: .outlaw)
        spawned = try c.decodeIfPresent(Bool.self, forKey: .spawned)
    }
}

enum TownBoard {
    static let names = ["Stranger", "Drifter", "Partner", "Ace", "Bo", "Cal", "Dusty", "Eli", "Frankie", "Gus", "Hank", "Jesse",
                        "Kit", "Lou", "Mae", "Nat", "Ollie", "Rae", "Sam", "Tex", "Val", "Wren"]
    static var playerName: String { TownLaw.state.playerName ?? "Stranger" }
    static let deliveries: [(String, Int)] = [("wheat", 24), ("carrot", 16), ("potato", 16), ("leather", 6), ("coal", 16), ("bread", 8),
                                              ("iron_ingot", 4), ("cooked_beef", 6), ("white_wool", 8), ("string", 8), ("feather", 12),
                                              ("arrow", 24), ("bone", 12), ("honey_bottle", 2)]
    static let outlawFirst = ["Black", "Mad", "Slim", "One-Eye", "Gentleman", "Red", "Lucky", "Cold", "Snake", "Smiling"]
    static let outlawLast = ["Jack", "Bill", "Haskell", "Morrow", "Tolliver", "Crane", "Pike", "Varga", "Kincaid", "Stokes"]

    // MARK: Jobs

    static func hash(_ town: String, _ day: Int, _ slot: Int) -> UInt64 {
        var h: UInt64 = 0xC0FFEE ^ UInt64(day &* 31 &+ slot)
        for u in town.utf8 { h = (h ^ UInt64(u)) &* 0x100000001B3 }
        h ^= h >> 29; h = h &* 0xBF58476D1CE4E5B9; h ^= h >> 32
        return h
    }

    // Today's two jobs in a town (a taken, unpaid job stays until done or three days old).
    static func jobs(_ g: Game, _ town: String, anchor: IVec3?) -> [TownJob] {
        let day = Int(g.time / DAY_LENGTH)
        var out: [TownJob] = []
        for slot in 0..<2 {
            let key = "\(town)#\(slot)"
            if let j = TownLaw.state.jobs?[key], (j.day == day || (j.taken && !j.paid && day - j.day < 3)) { out.append(j); continue }
            var j = make(town, day, slot)
            if let a = anchor { j.anchor = [a.x, a.z] }
            if TownLaw.state.jobs == nil { TownLaw.state.jobs = [:] }
            TownLaw.state.jobs?[key] = j
            out.append(j)
        }
        return out
    }
    static func save(_ town: String, _ slot: Int, _ j: TownJob) {
        if TownLaw.state.jobs == nil { TownLaw.state.jobs = [:] }
        TownLaw.state.jobs?["\(town)#\(slot)"] = j
    }

    static func make(_ town: String, _ day: Int, _ slot: Int) -> TownJob {
        let h = hash(town, day, slot)
        // Slot 0: a delivery or a hunt; slot 1: a hunt or an outlaw.
        let kind = slot == 0 ? (h % 3 == 0 ? "hunt" : "deliver") : (h % 2 == 0 ? "outlaw" : "hunt")
        switch kind {
        case "deliver":
            let options = deliveries.filter { Items.has($0.0) && Economy.value[$0.0] != nil }
            let (item, n) = options[Int((h >> 8) % UInt64(max(1, options.count)))]
            // Paid 60% of the goods' value: under any shop's price (Economy.minBuyMult 0.85), over what a shop pays (<= 0.55).
            // (The 50-cent floor never above 75% of the value: per-unit price rounding can't open a buy-and-deliver loop.)
            let v = (Economy.value[item] ?? 10) * n
            let pay = min(max(50, Int(Float(v) * 0.6)), Int(Float(v) * 0.75))
            return TownJob(day: day, kind: kind, item: item, count: n, pay: pay, honour: 4)
        case "hunt":
            let n = 4 + Int((h >> 12) % 5)
            return TownJob(day: day, kind: kind, count: n, pay: 150 + 40 * n, honour: 5)
        default:
            let name = "\(outlawFirst[Int((h >> 16) % UInt64(outlawFirst.count))]) \(outlawLast[Int((h >> 24) % UInt64(outlawLast.count))])"
            return TownJob(day: day, kind: kind, count: 1, pay: 600 + Int((h >> 32) % 6) * 100, honour: 6, outlaw: name)
        }
    }

    static func describe(_ j: TownJob, _ g: Game) -> (String, String) {
        switch j.kind {
        case "deliver":
            let name = Items.has(j.item ?? "") ? ItemStack(Items.id(j.item!), 1).def.display : (j.item ?? "goods")
            let have = Items.has(j.item ?? "") ? g.inventory.main.countOf(Items.id(j.item!)) : 0
            return ("Deliver \(j.count) \(name)", j.paid ? "Done. Thank you kindly." : "You have \(have). Press to hand them over")
        case "hunt":
            let what = "Clear \(j.count) monsters near town"
            if j.paid { return (what, "Done. Thank you kindly.") }
            if j.done { return (what, "Done: press to collect") }
            return (what, j.taken ? "\(j.progress) of \(j.count) killed within 96 blocks" : "Press to take the job")
        default:
            let what = "Bring in \(j.outlaw ?? "an outlaw")"
            if j.paid { return (what, "Done. Thank you kindly.") }
            if j.done { return (what, "Done: press to collect") }
            guard j.taken, let t = j.target else { return (what, "Wanted dead or alive. Press to take the job") }
            let d = V2(Float(t[0]) + 0.5 - g.player.pos.x, Float(t[1]) + 0.5 - g.player.pos.z)
            return (what, "Last seen \(Int(simd_length(d))) blocks \(direction(d.x, d.y)) of you. W on your map")
        }
    }

    static func direction(_ dx: Float, _ dz: Float) -> String {
        let a = atan2f(dx, -dz)                        // 0 = north (-z), clockwise
        let i = Int(((a / (2 * .pi) * 8).rounded() + 8)) % 8
        return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][i]
    }

    // A press on a job's row: take it, hand in, or collect.
    static func use(_ g: Game, _ town: String, _ slot: Int, anchor: IVec3) -> (String, Bool) {
        var j = jobs(g, town, anchor: anchor)[slot]
        guard !j.paid else { return ("That job is done.", false) }
        switch j.kind {
        case "deliver":
            guard let key = j.item, Items.has(key) else { return ("That job's been called off.", false) }
            let id = Items.id(key)
            guard g.inventory.main.countOf(id) >= j.count else { return ("You need \(j.count) \(ItemStack(id, 1).def.display).", false) }
            g.inventory.main.remove(id, j.count)
            j.taken = true; j.done = true
        case "hunt":
            if !j.taken {
                j.taken = true; j.anchor = [anchor.x, anchor.z]; save(town, slot, j)
                return ("Job taken: clear \(j.count) monsters within 96 blocks of town.", true)
            }
            guard j.done else { return ("\(j.progress) of \(j.count) so far.", false) }
        default:
            if !j.taken {
                // Last seen 80-140 blocks out from town, in a direction of his own.
                let h = hash(town, j.day, 7)
                let a = Float(h % 360) * .pi / 180, r = 80 + Float((h >> 9) % 61)
                j.taken = true
                j.anchor = [anchor.x, anchor.z]
                j.target = [anchor.x + Int(sinf(a) * r), anchor.z - Int(cosf(a) * r)]
                save(town, slot, j)
                let d = V2(Float(j.target![0]) - g.player.pos.x, Float(j.target![1]) - g.player.pos.z)
                // P474: followed at once (HUD marker, beacon) and marked W on the map.
                if g.dim.dim == .overworld, let t = Waymarks.outlaws(g, g.player.pos.y).first(where: { $0.key == "\(town)#\(slot)" }) {
                    Waymarks.marksAt = -1e9
                    Waymarks.track(g, t)
                }
                return ("\(j.outlaw ?? "He") was last seen \(Int(simd_length(d))) blocks \(direction(d.x, d.y)) of here. Followed on your HUD and map.", true)
            }
            guard j.done else { return ("He's still out there.", false) }
        }
        j.paid = true
        save(town, slot, j)
        g.money += j.pay
        g.sfx(.villagerTrade, 0.7)
        Honour.earn(g, j.honour, source: "job", "a job for \(town)")
        return ("Paid \(Money.format(j.pay)). \(town) won't forget it.", true)
    }

    // Hunts and outlaws: kills by the player (Honour.mobDied).
    static func mobDied(_ g: Game, _ m: Mob) {
        Contracts.mobDied(g, m)                          // C11: camp bandits
        Strangers.mobDied(g, m)                          // D20
        GangLeaders.mobDied(g, m)                        // D26
        Stagecoach.mobDied(g, m)                         // D4: a guarded coach's driver
        guard var all = TownLaw.state.jobs else { return }
        var changed = false
        for (k, var j) in all where j.taken && !j.done {
            // The outlaw dead some other way (drowned, a fall, the sheriff got him): the job's off, no reward.
            if j.kind == "outlaw", m.posse == 1, let n = j.outlaw, m.customName == n, !m.killedByPlayer {
                j.done = true; j.paid = true
                all[k] = j; changed = true
                g.onToast?("\(n) is dead, but not by your hand. No reward")
                continue
            }
            // P474: the outlaw is yours in Creative too (he went looking for one in Creative and never found him).
            if j.kind == "outlaw", m.killedByPlayer, m.posse == 1, let n = j.outlaw, m.customName == n {
                j.done = true; j.progress = 1
                all[k] = j; changed = true
                g.onToast?("\(n) is dead. Collect at the board")
                continue
            }
            guard m.killedByPlayer, g.survival else { continue }
            if j.kind == "hunt", m.kind.hostile, m.posse == 0, let a = j.anchor,
               simd_length(V2(m.pos.x - Float(a[0]), m.pos.z - Float(a[1]))) < 96 {
                j.progress += 1
                if j.progress >= j.count { j.done = true; g.onToast?("Job done") }
                all[k] = j; changed = true
            }
        }
        if changed { TownLaw.state.jobs = all }
    }

    // Once a second (TownLaw.tick): a taken outlaw shows up when you get near where he was seen.
    static func tick(_ g: Game) {
        guard g.dim.dim == .overworld, g.difficulty > 0, let all = TownLaw.state.jobs else { return }      // P474: Creative too
        let day = Int(g.time / DAY_LENGTH)
        // He turns up once (persistent: he's saved with his ground after that), on dry land, while the job is fresh.
        for (k, var j) in all where j.kind == "outlaw" && j.taken && !j.done && j.spawned != true && day - j.day < 3 {
            guard let t0 = j.target, let name = j.outlaw else { continue }
            guard simd_length(V2(Float(t0[0]) - g.player.pos.x, Float(t0[1]) - g.player.pos.z)) < 56,
                  g.world.isLoaded(t0[0], t0[1]) else { continue }
            // The nearest dry spot to where he was seen (a spiral out to 12 blocks); none: try again next second.
            var spot: (Int, Int)?
            search: for r in 0...12 { for dx in -r...r { for dz in -r...r where max(abs(dx), abs(dz)) == r {
                let x = t0[0] + dx, z = t0[1] + dz
                guard g.world.isLoaded(x, z) else { continue }
                let y = g.world.topY(x, z) + 1
                if !Blocks.isLiquid(g.world.builtBlock(x, y - 1, z)) && !Blocks.isLiquid(g.world.builtBlock(x, y, z)) { spot = (x, z); break search }
            } } }
            guard let (sx, sz) = spot else { continue }
            let c = V3(Float(sx) + 0.5, 0, Float(sz) + 0.5)
            let y = Float(g.world.topY(sx, sz) + 1)
            let boss = Mob(.vindicator, at: g.world.freeSpawn(V3(c.x, y, c.z)))
            boss.customName = name; boss.persistent = true; boss.aggro = true; boss.lockTime = 20; boss.posse = 1
            boss.health = boss.spec.health * 3 / 2
            g.mobs.mobs.append(boss)
            let pal = Mob(.pillager, at: g.world.freeSpawn(V3(c.x + 3, y, c.z + 2)))
            pal.customName = "\(name)'s Gang"; pal.persistent = true; pal.aggro = true; pal.lockTime = 20; pal.posse = 2
            g.mobs.mobs.append(pal)
            g.onToast?("That's \(name)!")
            j.spawned = true
            var a2 = all; a2[k] = j; TownLaw.state.jobs = a2
        }
    }

    // MARK: Posters

    // The WANTED boards near the player (in the town they are in): your own poster while you're wanted there or an
    // outlaw, the town's old notice otherwise. Once a second (TownLaw.tick).
    static let oldPoster = ["WANTED", "Dead or Alive", "Reward", "$50"]
    // A town's WANTED board: the poster the office went up with, or one of yours we put up (a sign you wrote yourself
    // that starts "WANTED" is left alone).
    static func isBoard(_ be: BlockEntity) -> Bool {
        be.lines == oldPoster || (be.lines.count == 4 && be.lines[0] == "WANTED" && be.lines[2] == "Dead or Alive")
    }
    static func posters(_ g: Game, town: String?) {
        guard g.dim.dim == .overworld else { return }
        let p = g.player.pos
        let owed = town.map { Honour.bounty($0) } ?? 0
        let known = Honour.outlawKnown(g)
        let wanted = town != nil && g.survival && (owed > 0 || known)
        // What surrendering costs: the bounty here, plus the outlaw's fine (Honour.settle).
        let poster = wanted ? ["WANTED", ShopMenu.fit(playerName, 88), "Dead or Alive", Money.format(owed + (known ? Honour.outlawFine : 0))] : oldPoster
        for (q, be) in g.world.blockEntities where be.kind == .sign && isBoard(be) {
            guard abs(Float(q.x) - p.x) < 64 && abs(Float(q.z) - p.z) < 64, TownLaw.isTownSpot(g, q) else { continue }
            if be.lines != poster { be.lines = poster }
        }
    }

    // MARK: Opening it

    static func open(_ g: Game, town: String, anchor: IVec3) {
        g.openMenu(NoticeBoardMenu(game: g, town: town, anchor: anchor))
    }
}

final class NoticeBoardMenu: ListMenu {
    let town: String
    let anchor: IVec3
    enum Item { case poster(String, Int), job(Int), contract(Int), gang, deed(Int), donate, emeralds, name, log(Int) }
    var items: [Item] = []
    var gangWanted: (GangLeaders.Gang, Int, String)?

    init(game: Game, town: String, anchor: IVec3) {
        self.town = town
        self.anchor = anchor
        super.init("\(town) Notice Board", game: game)
        refresh()
        g.sfx(.pageTurn, 0.6)
    }
    private var g: Game { game }

    func refresh() {
        let h = Honour.value
        subtitle = "Honour: \(Honour.standing(h)) (\(Int(h.rounded())))" + (Honour.lastWhy.isEmpty ? "" : ", last: \(Honour.lastWhy)")
        corner = "Wallet " + Money.format(g.money)
        items = []
        for (t, c) in (TownLaw.state.bounty ?? [:]).sorted(by: { $0.key < $1.key }) where c > 0 { items.append(.poster(t, c)) }
        if Honour.isOutlaw && g.survival { items.append(.poster("", 0)) }
        for i in 0..<2 { items.append(.job(i)) }
        for i in 0..<Contracts.slots { items.append(.contract(i)) }      // C11
        gangWanted = GangLeaders.wanted(g, from: anchor)                  // D26
        if gangWanted != nil { items.append(.gang) }
        items.append(.deed(0)); items.append(.deed(1))                     // D28: the land office
        items.append(.donate)
        items.append(.emeralds)
        items.append(.name)
        for i in Honour.log.indices.reversed().prefix(4) { items.append(.log(i)) }
    }

    override var rows: [Row] {
        let jobs = TownBoard.jobs(g, town, anchor: anchor)
        let contracts = Contracts.contracts(g, board: town, at: anchor)
        let log = Honour.log
        return items.map { it in
            switch it {
            case .poster(let t, let c):
                if t.isEmpty { return Row(name: "WANTED: \(TownBoard.playerName), outlaw", detail: "Surrender to any sheriff to pay your fine", value: Money.format(Honour.outlawFine), enabled: false, good: false) }
                return Row(name: "WANTED: \(TownBoard.playerName) in \(t)", detail: "Pay the sheriff or a deputy there", value: Money.format(c), enabled: false, good: false)
            case .job(let i):
                let j = jobs[i]
                let (name, detail) = TownBoard.describe(j, g)
                let icon = j.kind == "deliver" ? (Items.has(j.item ?? "") ? ItemStack(Items.id(j.item!), 1) : .empty)
                    : ItemStack(Items.id(j.kind == "hunt" ? "iron_sword" : Guns.revolverKey), 1)
                return Row(icon: icon, name: name, detail: detail, value: Money.format(j.pay), enabled: !j.paid)
            case .contract(let i):
                let c = contracts[i]
                let (name, detail) = Contracts.describe(g, c)
                let icon = Items.has(c.kind == "courier" ? "paper" : "iron_sword") ? ItemStack(Items.id(c.kind == "courier" ? "paper" : "iron_sword"), 1) : .empty
                return Row(icon: icon, name: name, detail: detail, value: Money.format(c.pay), enabled: !c.paid && !c.failed)
            case .gang:
                guard let (gg, d, dir) = gangWanted else { return Row(name: "", enabled: false) }
                return Row(icon: ItemStack(Items.id(Guns.revolverKey), 1), name: "WANTED: \(gg.leader), boss of \(gg.gang)",
                           detail: "Hides out \(d) blocks \(dir) of here. Double if brought in alive", value: Money.format(gg.bounty), enabled: false, good: false)
            case .deed(let i):
                let key = i == 0 ? Property.townKey : Property.homeKey, price = i == 0 ? Property.townPrice : Property.homePrice
                return Row(icon: Items.has(key) ? ItemStack(Items.id(key), 1) : .empty, name: i == 0 ? "Land office: a town house" : "Land office: a homestead",
                           detail: i == 0 ? "A deed for an empty town building" : "Stake a cabin in open country",
                           value: Money.format(price), enabled: g.money >= price)
            case .donate:
                let left = Honour.capLeft(g, "donation")
                return Row(icon: Items.has("emerald") ? ItemStack(Items.id("emerald"), 1) : .empty, name: "Donate to the town fund",
                           detail: left > 0 ? "+2 honour (up to 6 a day)" : "The fund thanks you. Come back tomorrow",
                           value: Money.format(TownBoard.donation), enabled: left > 0 && g.money >= TownBoard.donation)
            case .emeralds:
                // (G14) The exchange spelled out where every town's news is read: what an emerald is worth and where they come from.
                return Row(icon: Items.has("emerald") ? ItemStack(Items.id("emerald"), 1) : .empty, name: "The bank buys emeralds",
                           detail: "Mined from mountain stone; found in chests and shop tills", value: Money.format(Bank.sellEmerald), enabled: false, good: true)
            case .name:
                return Row(name: "Your name here: \(TownBoard.playerName)", detail: "Press to pick another")
            case .log(let i):
                let e = log[i]
                return Row(name: (e.amount > 0 ? "+" : "") + String(format: "%.1f", e.amount) + " " + e.why, detail: "Day \(e.day + 1)", enabled: false, good: e.amount > 0)
            }
        }
    }

    override func pressed(_ index: Int) {
        guard index < items.count else { return }
        switch items[index] {
        case .job(let i):
            let r = TownBoard.use(g, town, i, anchor: anchor)
            say(r.0, good: r.1)
        case .contract(let i):
            let r = Contracts.use(g, board: town, at: anchor, i)
            say(r.0, good: r.1)
        case .deed(let i):
            let key = i == 0 ? Property.townKey : Property.homeKey, price = i == 0 ? Property.townPrice : Property.homePrice
            guard g.money >= price, Items.has(key) else { say("That's \(Money.format(price)).", good: false); return }
            g.money -= price
            let r = g.inventory.add(ItemStack(Items.id(key), 1)); if !r.isEmpty { g.dropItem(r) }
            g.sfx(.villagerTrade, 0.6)
            say(i == 0 ? "Stand inside an empty town building and use the deed." : "Ride out into open country and use the deed where you want your cabin.", good: true)
        case .donate:
            guard g.money >= TownBoard.donation else { say("You can't spare it.", good: false); return }
            g.money -= TownBoard.donation
            Honour.earn(g, 2, source: "donation", "a donation to \(town)")
            g.sfx(.villagerTrade, 0.6)
            say("\(town) thanks you for your kindness.", good: true)
        case .name:
            let n = TownBoard.names
            let i = n.firstIndex(of: TownBoard.playerName) ?? 0
            TownLaw.state.playerName = n[(i + 1) % n.count]
            g.sfx(.click, 0.4)
            say("Folks will know you as \(TownBoard.playerName).", good: true)
        default: break
        }
        refresh()
    }

    override func tick() {
        if simd_length(V2(Float(anchor.x) + 0.5 - g.player.pos.x, Float(anchor.z) + 0.5 - g.player.pos.z)) > 12 { g.closeMenu() }
    }
}

extension TownBoard {
    static let donation = 100
}
