import Foundation
import simd

// The town jail (backlog R20, Oct 13 evening playtest, reported again after G14 was marked done: "a jail that looks and
// works like one"). What was actually wrong:
//   - It never worked as a jail: nothing ever put anyone in a cell. Surrendering to the law (Honour.settle) only took
//     money, or sent you off to "come back when you can pay"; the cell doors were generated standing open (so nobody
//     got stuck in one), which made them stalls.
//   - It didn't look like one: the office was a plank house with a stone front, and the cell's "bucket" was placed at
//     l.d - 3, which in that office is the bar row itself, so every cell front had a cauldron in its bars.
// Now:
//   - On R20 ground the office is a stone jail (Village.jailLot): stone walls all round with barred windows, a flat
//     stone roof with a parapet and a JAIL board over the door, a front room with the sheriff's desk and chair, a
//     WANTED board (signs on the wall; TownBoard.posters puts your own poster up while you're wanted) and the strongbox,
//     and a cell block behind iron bars: one or two cells, each with a shut iron door, a bunk, a chain, a bucket and a
//     barred window. Older offices keep their walls; their cells are shut and the cauldron is gone from the bars.
//   - Arrest: a town fighting you, an outlaw, or someone who can't pay their bounty, giving themselves up to the law
//     (talking to the sheriff or a deputy), is taken to the nearest jail cell of that town: weapons and ammunition go
//     into the strongbox (held here, the chest is locked while it holds them), the iron door shuts, and the term runs
//     (40 s plus 3 s a dollar owed, at most 4 minutes). Open your pack in the cell to pay what's left of the fine and
//     walk free, or sit it out. Either way the bounty is settled, the door opens and your things are handed back.
//     Breaking out (through the bars or the wall) is a jailbreak: the town turns on you, $10 more on your head, and
//     your things stay locked up until you settle with that town's law.
//   - Captured outlaws: an outlaw from a notice-board job who is beaten down to under 30% of his health gives up; take
//     him to any town with a jail and he is put in a cell there (he stays in it, a prisoner of the town), for the
//     reward and half again. Roped with the lasso and hogtied (use him while the rope holds), he's worth double.
// The geometry of a town's office is kept on its start (StructureStart.info "jail*", Village.layout), so the cell,
// its door and the strongbox are found again after a load without searching the world.
enum Jail {
    // MARK: Geometry (local to the office lot: u along the street, v away from it)

    struct Geo {
        let wallH: Int
        let cellV: Int                 // the bar row
        let split: Int                 // the partition column, or -1 (one cell)
        var splits: [Int] = []         // every partition column (P354: three cells)
        let doors: [Int]               // each cell's door column (in the bar row)
        let cells: [(Int, Int)]        // each cell's u range (its v range: cellV + 1 ... d - 2)
        let box: (Int, Int)?           // the strongbox
    }

    static func geometry(_ l: Village.Lot) -> Geo {
        let du = l.w / 2
        let cellV = l.r20 ? (l.d >= 7 ? l.d - 4 : l.d - 3) : l.d - 3
        let split = l.w - 2 >= 5 && (l.r20 || cellV > 2) ? du : -1
        let doors = split > 0 ? [split - 1, split + 1] : [l.w - 2]
        let cells = split > 0 ? [(1, split - 1), (split + 1, l.w - 2)] : [(1, l.w - 2)]
        let box: (Int, Int)? = l.r20 ? (l.w >= 7 ? (l.w - 2, 1) : nil) : (split > 0 && du > 2 ? (l.w - 2, 2) : nil)
        // P354 (Oct 16 20:06: "the jail is too small"): on the big house's lot, a front office four deep and three cells
        // three wide and three deep behind it, each with its own door.
        if l.p354 && l.w >= 13 && l.d >= 9 {
            let a = 1 + (l.w - 2 - 2) / 3, b2 = l.w - 1 - (l.w - 2 - 2) / 3 - 1
            let cs = [(1, a - 1), (a + 1, b2 - 1), (b2 + 1, l.w - 2)]
            return Geo(wallH: 5, cellV: l.d - 5, split: a, splits: [a, b2], doors: cs.map { ($0.0 + $0.1) / 2 }, cells: cs, box: (l.w - 2, 1))
        }
        return Geo(wallH: 5, cellV: cellV, split: split, splits: split > 0 ? [split] : [], doors: doors, cells: cells, box: box)
    }

    // Village.layout: the office lot, kept on the town's start.
    static func record(_ l: Village.Lot, into info: inout [String: Int]) {
        info["jailAX"] = l.ax; info["jailAZ"] = l.az; info["jailY"] = l.y; info["jailF"] = l.face
        info["jailW"] = l.w; info["jailD"] = l.d; info["jailR20"] = l.r20 ? 1 : 0
        info["jailP354"] = l.p354 ? 1 : 0
    }

    struct Site {
        let town: String
        let lot: Village.Lot
        let geo: Geo
        var cellCount: Int { geo.cells.count }
        func at(_ u: Int, _ v: Int, _ dy: Int = 0) -> IVec3 {
            let (x, z) = Village.world(lot, u, v)
            return IVec3(x, lot.y + dy, z)
        }
        // Where someone put in cell i stands (inside its door), the door's lower half, the door's facing.
        func spot(_ i: Int) -> IVec3 { at(geo.doors[i], geo.cellV + 1) }
        func door(_ i: Int) -> IVec3 { at(geo.doors[i], geo.cellV) }
        var face: Int { Village.dir(lot, 1) }
        var box: IVec3? { geo.box.map { at($0.0, $0.1) } }
        var front: IVec3 { at(geo.doors[0], geo.cellV - 1) }       // the front room, before the first cell's door
        // Cell i's floor area (world x0, z0, x1, z1).
        func area(_ i: Int) -> [Int] {
            let (u0, u1) = geo.cells[i]
            let a = at(u0, geo.cellV + 1), b = at(u1, lot.d - 2)
            return [min(a.x, b.x), min(a.z, b.z), max(a.x, b.x), max(a.z, b.z)]
        }
    }

    // The jail of the town nearest p (nil: no office there, or its ground isn't loaded, or its cell door is gone).
    static func site(_ g: Game, near p: V3) -> Site? {
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures else { return nil }
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        guard let s = sc.nearest("village", x: x, z: z, maxRegions: 1), abs(s.anchor.x - x) < 200, abs(s.anchor.z - z) < 200,
              let ax = s.info["jailAX"], let az = s.info["jailAZ"], let y = s.info["jailY"], let f = s.info["jailF"],
              let w = s.info["jailW"], let d = s.info["jailD"] else { return nil }
        var lot = Village.Lot(kind: .office, ax: ax, az: az, face: f, w: w, d: d, y: y, seed: 0, job: "sheriff")
        lot.frontier = true
        lot.r20 = s.info["jailR20"] == 1
        lot.p354 = s.info["jailP354"] == 1
        let site = Site(town: Townsfolk.townName(s.anchor.x, s.anchor.z, seed: g.world.seed), lot: lot, geo: geometry(lot))
        let door = site.door(0)
        guard g.world.isLoaded(door.x, door.z), Blocks.key(Blocks.groupBase[Int(g.world.materialAt(door.x, door.y, door.z))]) == "iron_door" else { return nil }
        return site
    }

    // MARK: The term

    struct Term: Codable {
        var town: String
        var cell: [Int]                // the spot (x, y, z)
        var door: [Int]                // the door's lower half (x, y, z)
        var face: Int
        var area: [Int]                // the cell's floor (x0, z0, x1, z1)
        var left: Float
        var total: Float
        var fine: Int                  // cents for the whole term (what's left of it buys you out)
        var outlaw: Bool
        var held: [ItemStack]
    }
    static var term: Term? {
        get { TownLaw.state.jail }
        set { TownLaw.state.jail = newValue }
    }
    static var arrests = 0, releases = 0, breaks = 0, caught = 0       // (tests)
    static var passPack = false        // the jail menu's "Open your pack" lets one inventory screen through

    static func sentence(_ owed: Int) -> Float { min(240, 40 + Float(owed) / 100 * 3) }
    static func fineNow(_ t: Term) -> Int {
        let share = t.total > 0 ? max(0, t.left) / t.total : 0
        return max(100, Int((Float(t.fine) * share).rounded(.up)))
    }
    static func clock(_ s: Float) -> String {
        let n = max(0, Int(s.rounded(.up)))
        return String(format: "%d:%02d", n / 60, n % 60)
    }

    // What the law takes off you: guns and their rounds, swords, bows, spears and explosives.
    static func isWeapon(_ s: ItemStack) -> Bool {
        guard !s.isEmpty else { return false }
        if Guns.index(s.item) != nil { return true }
        let k = Items.key(s.item)
        if k.contains("firework") { return false }
        return k.hasSuffix("_sword") || k == "bow" || k == "crossbow" || k == "trident" || k.contains("spear") || k == "mace"
            || k.hasSuffix("_rounds") || k.hasSuffix("_shells") || k.contains("grenade") || k.contains("dynamite") || k == "tnt"
            || k.contains("rocket")
    }

    static func setDoor(_ g: Game, _ p: IVec3, face: Int, open: Bool) {
        guard Blocks.has("iron_door"), g.world.isLoaded(p.x, p.z) else { return }
        let base = Blocks.id("iron_door")
        let o = open ? 4 : 0
        g.world.setBlock(p.x, p.y, p.z, base + BlockID(face + o))
        g.world.setBlock(p.x, p.y + 1, p.z, base + BlockID(face + o + 8))
        g.sfx(open ? .ironDoorOpen : .ironDoorClose, 0.8, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
    }

    // Honour.settle: the law takes you in. False when this town has no jail to hand (a hamlet, a far office): the old
    // fine-or-come-back answer stands.
    static func arrest(_ g: Game, _ lawman: Mob, town: String, owed: Int, outlaw: Bool) -> Bool {
        guard g.survival, g.alive, term == nil, let site = site(g, near: lawman.pos), site.town == town else { return false }
        let spot = site.spot(0)
        guard simd_length(V3(Float(spot.x) + 0.5, Float(spot.y), Float(spot.z) + 0.5) - g.player.pos) < 160 else { return false }
        if g.menu != nil { g.closeMenu() }
        g.dismount()
        var held: [ItemStack] = []
        for i in 0..<36 where isWeapon(g.inventory.main[i]) { held.append(g.inventory.main[i]); g.inventory.main[i] = .empty }
        if isWeapon(g.inventory.offhand[0]) { held.append(g.inventory.offhand[0]); g.inventory.offhand[0] = .empty }
        setDoor(g, site.door(0), face: site.face, open: false)
        g.player.pos = V3(Float(spot.x) + 0.5, Float(spot.y), Float(spot.z) + 0.5)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
        let total = sentence(owed)
        let d = site.door(0)
        term = Term(town: town, cell: [spot.x, spot.y, spot.z], door: [d.x, d.y, d.z], face: site.face, area: site.area(0),
                    left: total, total: total, fine: max(100, owed), outlaw: outlaw, held: held)
        // The term settles it: the town lets the grudge go while you sit (an outlaw is Disreputable again, as when paying).
        Honour.pardon(g, town)
        if outlaw { Honour.change(g, Honour.outlaw + 5 - Honour.value, "you gave yourself up") }
        arrests += 1
        // The lawman walks you in and keeps an eye on the cell.
        let f = site.front
        lawman.wanderGoal = V3(Float(f.x) + 0.5, Float(f.y), Float(f.z) + 0.5); lawman.moving = true; lawman.aiTimer = 8
        Townsfolk.townLastLine = -100
        Townsfolk.say(g, lawman, TownLines.pick(["You'll sit a spell in my jail. Sentence is \(clock(total)).",
                                                 "Cell's yours till your time is up. Pay the fine if you want out sooner.",
                                                 "In you go. I'll hold your irons in the strongbox till you're done.",
                                                 "Settle down, now. Everybody does their time in \(town)."]))
        let what = held.isEmpty ? "" : " Your weapons (\(held.count)) are in the jail's strongbox."
        g.onToast?("Jailed in \(town): \(clock(total)), or pay \(Money.format(fineNow(term!))) to walk free.\(what)")
        g.openMenu(JailMenu(game: g))
        return true
    }

    // Time served, or the fine paid: the door opens and your things come back.
    static func release(_ g: Game, paid: Int = 0) {
        guard let t = term else { return }
        term = nil
        releases += 1
        let door = IVec3(t.door[0], t.door[1], t.door[2])
        setDoor(g, door, face: t.face, open: true)
        let back = t.held + (TownLaw.state.impounded?[t.town] ?? [])
        TownLaw.state.impounded?[t.town] = nil
        for s in back where !s.isEmpty {
            let rest = g.inventory.add(s)
            if !rest.isEmpty { g.dropItem(rest) }
        }
        Honour.change(g, paid > 0 ? 1 : 2, paid > 0 ? "you paid your fine" : "you served your time")
        Townsfolk.townLastLine = -100
        if let law = g.mobs.mobs.filter({ TownLaw.isTownsperson($0) && TownLaw.isLaw($0) && simd_length($0.pos - g.player.pos) < 24 })
            .min(by: { simd_length($0.pos - g.player.pos) < simd_length($1.pos - g.player.pos) }) {
            law.face(g.player.pos)
            Townsfolk.say(g, law, TownLines.pick(["Door's open. Keep your nose clean out there.", "Time's up. Collect your things and go.",
                                                  "You're square with \(t.town). Don't make me do this twice.",
                                                  "Here's your irons back. Holster them while you're in town."]))
        }
        g.onToast?(paid > 0 ? "Fine of \(Money.format(paid)) paid. You're free to go." + (t.held.isEmpty ? "" : " Your things are handed back.")
                            : "You've served your time in \(t.town)." + (t.held.isEmpty ? "" : " Your things are handed back."))
    }

    static func payFine(_ g: Game) -> (String, Bool) {
        guard let t = term else { return ("You're not locked up.", false) }
        let fine = fineNow(t)
        guard g.money >= fine else { return ("The fine is \(Money.format(fine)). You have \(Money.format(g.money)).", false) }
        g.money -= fine
        g.sfx(.villagerTrade, 0.6)
        release(g, paid: fine)
        return ("Paid \(Money.format(fine)).", true)
    }

    // Out of the cell before the term is up.
    static func jailbreak(_ g: Game) {
        guard let t = term else { return }
        term = nil
        breaks += 1
        if !t.held.isEmpty {
            if TownLaw.state.impounded == nil { TownLaw.state.impounded = [:] }
            TownLaw.state.impounded?[t.town, default: []] += t.held
        }
        Honour.change(g, -10, "you broke out of jail")
        Honour.addBounty(g, t.town, 1000)
        TownLaw.state.hostile[t.town] = TownLaw.hostileSeconds
        TownLaw.state.heat[t.town] = TownLaw.hostileHeat
        for o in g.mobs.mobs where TownLaw.isTownsperson(o) && TownLaw.town(of: o, g) == t.town && simd_length(o.pos - g.player.pos) < 48 {
            if o.townWeapon != .none && !o.baby { o.town.anger = max(o.town.anger, o.villager?.role == "sheriff" ? TownLaw.hostileSeconds : 60) }
            else { o.panic = max(o.panic, 8) }
        }
        g.onToast?("Jailbreak! \(t.town) is after you, $10 more on your head." + (t.held.isEmpty ? "" : " Your weapons stay locked up."))
    }

    // Honour.settle (paid in full): what a jailbreak left in the strongbox comes back.
    static func returnImpounded(_ g: Game, _ town: String) {
        guard let items = TownLaw.state.impounded?[town], !items.isEmpty else { return }
        TownLaw.state.impounded?[town] = nil
        for s in items where !s.isEmpty {
            let rest = g.inventory.add(s)
            if !rest.isEmpty { g.dropItem(rest) }
        }
        g.onToast?("The strongbox is opened: your things are handed back.")
    }

    static func inCell(_ p: V3, _ t: Term) -> Bool {
        guard t.area.count == 4, t.cell.count == 3 else { return true }
        let m: Float = 0.45
        let inX = p.x >= Float(t.area[0]) - m && p.x <= Float(t.area[2] + 1) + m
        let inZ = p.z >= Float(t.area[1]) - m && p.z <= Float(t.area[3] + 1) + m
        let inY = p.y >= Float(t.cell[1]) - 1.5 && p.y <= Float(t.cell[1]) + 2.5
        return inX && inY && inZ
    }

    // MARK: Every second (TownLaw.tick)

    static var hunting = false         // an outlaw job's man is out (per-frame surrender check)

    static func tick(_ g: Game, _ dt: Float) {
        hunting = (TownLaw.state.jobs ?? [:]).values.contains { $0.kind == "outlaw" && $0.taken && !$0.done && $0.spawned == true }
        if var t = term, g.alive {
            let c = V3(Float(t.cell[0]) + 0.5, Float(t.cell[1]), Float(t.cell[2]) + 0.5)
            if !g.survival || g.dim.dim != .overworld || simd_length(g.player.pos - c) > 64 {
                release(g)                                              // died and woke elsewhere, or carried off
            } else if !inCell(g.player.pos, t) {
                jailbreak(g)
            } else {
                t.left -= dt
                term = t
                if t.left <= 0 { release(g) }
            }
        }
        deliverPrisoner(g)
    }

    // MARK: Captured outlaws

    // Per frame while an outlaw job's man is out (TownLaw.tick, before its once-a-second gate): beaten down, he gives up.
    static func watchOutlaws(_ g: Game) {
        guard hunting, g.survival, TownLaw.state.prisoner == nil else { return }
        for m in g.mobs.mobs where m.posse == 1 && m.health > 0 {
            guard let n = m.customName, simd_length(m.pos - g.player.pos) < 24 else { continue }
            let full = m.spec.health * 3 / 2                            // (TownBoard spawns him at half again his health)
            guard m.health * 10 <= full * 3 else { continue }
            guard let hit = (TownLaw.state.jobs ?? [:]).first(where: { $0.value.kind == "outlaw" && $0.value.outlaw == n && $0.value.taken && !$0.value.done })
            else { continue }
            let k = hit.key
            g.mobs.mobs.removeAll { $0 === m }
            for o in g.mobs.mobs where o.posse == 2 && o.customName == "\(n)'s Gang" { o.aggro = false; o.panic = max(o.panic, 10) }
            TownLaw.state.prisoner = [n, k]
            caught += 1
            g.sfx(.villagerNo, 0.8, at: m.eye)
            g.onToast?("\(n): \"I give up! Don't shoot!\" He's in irons.")
            return
        }
    }

    // D24: use a roped outlaw (Lasso.swift) to hogtie him. The wanted man of a notice-board job you hold becomes your
    // prisoner in tow, worth double at a jail (TownLaw.state.prisoner gets a third "tied" mark); one of his gang is
    // trussed for two minutes. The lasso comes back to the pack either way.
    static func hogtie(_ g: Game, _ m: Mob) -> Bool {
        guard m.roped > 0, m.outlaw, m.health > 0 else { return false }
        func rope() {
            m.leashed = false; m.lassoed = false; m.knot = nil
            if g.survival { let r = g.inventory.add(ItemStack(Items.id(Lasso.key), 1)); if !r.isEmpty { g.dropItem(r) } }
        }
        g.swing = 1
        g.sfx(.armorEquip(0), 0.8, at: m.pos)
        if GangLeaders.isLeader(m) != nil {                                       // D26: a gang boss pays on the spot
            rope()
            if GangLeaders.captured(g, m) { hogties += 1; return true }
        }
        if m.posse == 1, TownLaw.state.prisoner == nil, let n = m.customName,
           let hit = (TownLaw.state.jobs ?? [:]).first(where: { $0.value.kind == "outlaw" && $0.value.outlaw == n && $0.value.taken && !$0.value.done }) {
            rope()
            g.mobs.mobs.removeAll { $0 === m }
            for o in g.mobs.mobs where o.posse == 2 && o.customName == "\(n)'s Gang" { o.aggro = false; o.panic = max(o.panic, 10) }
            TownLaw.state.prisoner = [n, hit.key, "tied"]
            caught += 1
            hogties += 1
            g.onToast?("\(n) is hogtied and slung over your saddle.")
            return true
        }
        rope()
        m.roped = 120
        m.aggro = false
        hogties += 1
        g.onToast?("Hogtied. He won't work loose for a good while")
        return true
    }
    static var hogties = 0

    // Once a second: a prisoner in tow is put in a cell when you reach a town with a jail.
    static func deliverPrisoner(_ g: Game) {
        guard let pr = TownLaw.state.prisoner, pr.count >= 2, g.alive, TownLaw.inTown != nil,
              let site = site(g, near: g.player.pos), !TownLaw.isHostile(site.town) else { return }
        let f = site.front
        guard simd_length(V3(Float(f.x) + 0.5, Float(f.y), Float(f.z) + 0.5) - g.player.pos) < 40 else { return }
        // The second cell when there is one (the first is kept for you); a one-cell jail takes him while you're out.
        let i = site.cellCount > 1 ? 1 : 0
        if i == 0 && term != nil { return }
        let s = site.spot(i)
        let m = Mob(.villager, at: V3(Float(s.x) + 0.5, Float(s.y), Float(s.z) + 0.5))
        var v = VillagerData()
        v.person = pr[0]
        v.town = site.town
        var h: UInt64 = 1469598103934665603
        for b in pr[0].utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        v.look = Int(h & 0xFFFF)
        m.villager = v
        m.home = m.pos
        m.persistent = true
        Townsfolk.setup(m, tag: "prisoner", game: g)
        g.mobs.mobs.append(m)
        setDoor(g, site.door(i), face: site.face, open: false)
        TownLaw.state.prisoner = nil
        if var j = TownLaw.state.jobs?[pr[1]] {
            j.done = true; j.progress = 1
            let tied = pr.count > 2                                     // D24: hogtied off the lasso pays double
            j.pay += tied ? j.pay : j.pay / 2
            TownLaw.state.jobs?[pr[1]] = j
            g.onToast?("\(pr[0]) is behind bars in \(site.town).")
        } else {
            g.onToast?("\(pr[0]) is behind bars in \(site.town).")
        }
        Honour.earn(g, 2, source: "outlaw", "an outlaw brought in alive")
    }

    // MARK: Hooks

    // TownLaw.opened: the strongbox stays locked while it holds your things.
    static func lockedBox(_ g: Game, _ p: IVec3) -> Bool {
        guard term != nil || !(TownLaw.state.impounded ?? [:]).isEmpty, let s = site(g, near: V3(Float(p.x), Float(p.y), Float(p.z))),
              s.box == p else { return false }
        return term?.town == s.town || !(TownLaw.state.impounded?[s.town] ?? []).isEmpty
    }

    // TownLaw.opened: in a cell, the pack opens the jail's ledger first (pay the fine, or wait); its "Open your pack"
    // lets the inventory through once.
    static func interceptPack(_ g: Game, _ m: Menu) -> Bool {
        guard term != nil, m is InventoryMenu else { return false }
        if passPack { passPack = false; return false }
        g.switchMenu(to: JailMenu(game: g))
        return true
    }

    // The HUD line under the wallet (Wallet.lines).
    static func status(_ g: Game) -> (String, V4)? {
        if let t = term {
            return ("JAIL \(clock(t.left))  Open your pack to pay \(Money.format(fineNow(t)))", V4(1, 0.55, 0.45, 1))
        }
        if let pr = TownLaw.state.prisoner, pr.count == 2 {
            return ("Prisoner: \(ShopMenu.fit(pr[0], 90)), take him to a town jail", V4(1, 0.86, 0.42, 1))
        }
        return nil
    }
}

// The cell's ledger: time left, the fine to walk free now, the pack, or sit tight.
final class JailMenu: ListMenu {
    init(game g: Game) {
        super.init("Jail", game: g)
        subtitle = Jail.term.map { "\($0.town) jail" } ?? ""
        say("Sit out your time, or pay the fine and walk free.", good: true)
    }
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        guard let t = Jail.term else { return [] }
        let fine = Jail.fineNow(t)
        let bars = Items.has("iron_bars") ? ItemStack(Items.id("iron_bars"), 1) : ItemStack.empty
        let coin = Items.has("gold_nugget") ? ItemStack(Items.id("gold_nugget"), 1) : ItemStack.empty
        return [
            Row(icon: bars, name: "Time left: \(Jail.clock(t.left))", detail: "Sit it out and the door opens", value: "", enabled: false),
            Row(icon: coin, name: "Pay the fine and walk free", detail: t.held.isEmpty ? "Paid to the law" : "Your \(t.held.count) confiscated item(s) handed back",
                value: Money.format(fine), enabled: game.money >= fine),
            Row(name: "Open your pack", detail: "Your inventory"),
            Row(name: "Sit tight", detail: "Close this and wait"),
        ]
    }
    override func pressed(_ i: Int) {
        switch i {
        case 1:
            let r = Jail.payFine(game)
            say(r.0, good: r.1)
            if r.1 { game.closeMenu() }
        case 2:
            Jail.passPack = true
            game.switchMenu(to: InventoryMenu(game: game))
        case 3: game.closeMenu()
        default: return
        }
    }
    override func tick() {
        super.tick()
        if Jail.term == nil && game.menu === self { game.closeMenu() }
    }
}

// MARK: The stone jail (R20 offices)

extension Village {
    static func jailLot(_ w: inout StructWriter, _ b: LB, _ m0: Mats) {
        let l = b.l
        let m = varied(m0, l)
        let geo = Jail.geometry(l)
        let wallH = geo.wallH
        house(&w, b, m0, wallH: wallH, roof: false)
        let stone = blk("stone_bricks", COBBLE)
        let corner = blk("chiseled_stone_bricks", blk("polished_andesite", stone))
        let bars = blk("iron_bars", m.fence)
        let floor = blk("cobblestone", COBBLE)
        let du = l.w / 2
        let bunkCols = Set(geo.cells.map { $0.0 })                 // each cell's far column: its bunk and window
        // Stone walls all round with barred windows (house() left planks and glass panes).
        for v in 0..<l.d { for u in 0..<l.w {
            let edgeU = u == 0 || u == l.w - 1, edgeV = v == 0 || v == l.d - 1
            guard edgeU || edgeV else { continue }
            let isCorner = edgeU && edgeV
            for dy in 0..<wallH {
                if v == 0 && u == du && dy < 2 { continue }       // the front door
                var k = isCorner ? corner : stone
                if !isCorner {
                    if v == 0 && dy == 1 && u % 2 == 0 && u < l.w - 3 { k = bars }                  // front windows
                    else if edgeU && !edgeV && dy == 2 && v < geo.cellV && v % 2 == 1 { k = bars } // the office's side windows
                    else if v == l.d - 1 && dy == 2 && bunkCols.contains(u) { k = bars }           // over each bunk
                }
                b.set(&w, u, dy, v, k)
            }
        } }
        // A flat stone roof with a parapet, and a raised board over the door with JAIL on it.
        b.fill(&w, 0, wallH, 0, l.w - 1, wallH, l.d - 1, stone)
        for v in 0..<l.d { for u in 0..<l.w where u == 0 || v == 0 || u == l.w - 1 || v == l.d - 1 {
            if (u + v) % 2 == 0 { b.set(&w, u, wallH + 1, v, stone) }
        } }
        for u in max(0, du - 1)...min(l.w - 1, du + 1) { b.set(&w, u, wallH + 1, 0, stone); b.set(&w, u, wallH + 2, 0, stone) }
        boardwalk(&w, b, m, wallH: wallH)
        sign(&w, b, u: du, dy: wallH + 1, v: -1, lines: ["", "JAIL", "", ""])
        sign(&w, b, u: du, dy: 2, v: -1, lines: ["", "JAIL", "Sheriff's Office", ""])
        sign(&w, b, u: l.w - 2, dy: 1, v: -1, lines: ["NOTICE", "No guns drawn", "in town", "- The Law"])
        // The front room: the sheriff's desk with a lamp and his chair, a light, the WANTED board, the strongbox.
        let desk = blk("stripped_\(Blocks.key(m.log).replacingOccurrences(of: "stripped_", with: ""))", m.planks)
        b.set(&w, 1, 0, 1, desk)
        if du > 2 { b.set(&w, 2, 0, 1, desk) }
        b.set(&w, 1, 1, 1, blk("lantern", AIR))
        if geo.cellV > 2 && !geo.doors.contains(1) { b.set(&w, 1, 0, 2, b.seat(m, "chair", back: 0)) }
        b.set(&w, 1, 3, 1, b.wallTorch(facing: 2))
        b.set(&w, l.w - 2, 3, geo.cellV - 1, b.wallTorch(facing: 3))
        func board(_ w: inout StructWriter, _ u: Int, _ dy: Int, _ lines: [String]) {
            let base = blk("spruce_sign", blk("oak_sign", AIR))
            guard base != AIR else { return }
            let (x, z) = world(l, u, 1)
            let y = l.y + dy
            guard w.inside(x, y, z) else { return }
            w.set(x, y, z, base + BlockID(4 + dir(l, 0)))            // on the front wall's inside, facing the room
            let be = BlockEntity(.sign)
            be.lines = lines
            w.entities.append((IVec3(x, y, z), be))
        }
        if l.w >= 7 {
            board(&w, l.w - 2, 2, TownBoard.oldPoster)               // (TownBoard.posters: your poster while you're wanted)
            board(&w, l.w - 2, 1, ["WANTED", "Slim Pike", "Horse thief", "$25"])
            board(&w, l.w - 3, 2, ["NOTICE", "Prisoners fed", "twice a day", "- Sheriff"])
        } else {
            board(&w, l.w - 2, 2, TownBoard.oldPoster)
        }
        if let bx = geo.box {
            let (x, z) = world(l, bx.0, bx.1)
            var rng = SRng(l.seed &+ 0x5E1F)
            w.chest(x, l.y, z, loot: "sheriff_locker", seed: rng.next(), facing: dir(l, 3))
        }
        // The cell block: a row of bars with a stone header over it, the partition wall, a shut iron door per cell.
        let ironDoor = blk("iron_door", m.door)
        let f = dir(l, 1)
        for u in 1...(l.w - 2) {
            for dy in 0..<wallH {
                var k = bars
                if geo.splits.contains(u) || dy >= 3 { k = stone }
                else if geo.doors.contains(u) && dy < 2 { k = ironDoor + BlockID(f + (dy == 1 ? 8 : 0)) }
                b.set(&w, u, dy, geo.cellV, k)
            }
            for v in (geo.cellV + 1)...(l.d - 2) {
                b.set(&w, u, -1, v, floor)
                for dy in 0..<wallH where !geo.splits.contains(u) { b.set(&w, u, dy, v, AIR) }
            }
        }
        for s in geo.splits { for v in (geo.cellV + 1)...(l.d - 2) { for dy in 0..<wallH { b.set(&w, s, dy, v, stone) } } }
        // In each cell: a bunk under the window with a chain over it, a bucket where the cell is deep enough, a light
        // by the door (a dark cell would breed monsters).
        for (i, c) in geo.cells.enumerated() {
            let u0 = c.0, door = geo.doors[i]
            b.set(&w, u0, 0, l.d - 2, m.slab)
            b.set(&w, u0, wallH - 1, l.d - 2, blk("chain", AIR))
            if geo.cellV + 1 < l.d - 2 && u0 != door { b.set(&w, u0, 0, geo.cellV + 1, blk("cauldron", AIR)) }
            if door != u0 { b.set(&w, door, 2, l.d - 2, b.wallTorch(facing: 1)) }
        }
    }
}
