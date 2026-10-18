import Foundation
import simd

// Town law: stealing, vandalism and assault in a town, the town's anger, and the sheriff.
//
// Offences only count in survival, when a townsperson sees it (within 20 blocks, a clear line of sight from their
// eyes) and the thing belongs to the town: inside one of the village's generated pieces (its houses, farms, square
// and roads, down to 4 blocks under the floor, so dungeon and mineshaft chests below don't count), not placed by the
// player (blocks the player places in towns are remembered, oldest forgotten first), and for a container, not what
// the player put in it (deposits are counted per chest). Each offence adds heat to that town (taking from a town
// chest or barrel 1-3 by how much, breaking town property 1, or a town container as much as taking what's in it,
// hurting a townsperson 2); heat cools by 1 every 90 s.
//   heat < 2: the witness warns you ("Hey! That's not yours."), the witnesses think a little less of you.
//   heat 2-4: the law warns you (the sheriff or a deputy calls out and comes over), more lost standing.
//   heat >= 4: the town turns on you for 150 s: big loss of standing with everyone near (prices up to +25%, keepers
//              refuse to serve while it lasts), everyone armed fights, the rest run, and the sheriff calls his
//              challenge and draws 2.5 s later.
// The sheriff (role "sheriff", save key "villager:sheriff") replaces the iron golem as the town protector: new towns
// get him on the square instead of a golem, older towns get one sent the first time you're there (and a new one three
// days after he falls). He patrols the square day and night, fights monsters and the player with his six-iron
// (SixIron.swift: against the player, the iron rule; a telegraphed, dodgeable shot), and can be fought and killed. Townsfolk no longer summon golems; golems already in old
// towns stay (removing mobs from a save would be destructive) and keep defending as before.
enum TownLaw {
    static var golemsAllowed = false                 // the old golem summoning (MobTests turns it on to keep its rule covered)
    static let hostileHeat: Float = 4
    static let hostileSeconds: Float = 150

    // Per-world state (reset and loaded by Game.loadExtra; saved by saveExtra as extra["townLaw"]).
    struct Saved: Codable {
        var heat: [String: Float] = [:]
        var hostile: [String: Float] = [:]          // seconds of open hostility left
        var appointed: [String: Int] = [:]          // town -> the day its sheriff was last seen or sent
        var placed: [[Int]] = []                    // player-placed blocks in towns (newest last, capped)
        var deposits: [String: [String: Int]]? = nil  // "x,y,z" of a town chest -> item key -> what the player put in
        var sheriffs: [String: String]? = nil       // town -> its one sheriff (person name)
        // Honour.swift: the player's honour, today's capped gains ("day:source"), bounties (cents) and the day each
        // town's bounty last grew.
        var honour: Float? = nil
        var honourGains: [String: Float]? = nil
        var bounty: [String: Int]? = nil
        var bountyDay: [String: Int]? = nil
        // The gap pass (docs/status/cloud-gap-pass.md): every honour change ("day|amount|why", newest last, capped),
        // each town's notice-board jobs, the day bounty hunters last rode, the towns that already gave you a gift
        // today ("day:town") and your name as townsfolk say it.
        var honourLog: [String]? = nil
        var outlawAt: [Float]? = nil                // P96: (x, z) of the last deed that kept you an outlaw (Honour.outlawKnown)
        var jobs: [String: TownJob]? = nil
        var huntersDay: Int? = nil
        var trackers: [Float]? = nil                // O8: a hunting party out after you [x, z, seconds left] (BountyHunters)
        var gifts: [String]? = nil
        var playerName: String? = nil
        // Town services (TownServices.swift): the bank balance (cents) and the day interest was last paid; the day of
        // each town's last night raid (TownRaids.swift).
        var bank: Int? = nil
        var bankDay: Int? = nil
        var raidDay: [String: Int]? = nil
        // TownConquest: the towns you took (town -> [anchor x, anchor z, day taken, day tribute last paid]).
        var owned: [String: [Int]]? = nil
        var contracts: [String: Contract]? = nil    // C11: contracts on the boards (Contracts.swift)
        var nation: Nation.Saved? = nil             // C3: your nation (Nation.swift)
        var minesSpent: [String]? = nil             // C12: gas pockets that have gone up (MiningTowns.swift)
        var stabled: [StabledHorse]? = nil          // horses kept in town stables (HorseStable.swift)
        var horseSold: [String: Int]? = nil         // town -> the day its stable last bought a horse from you
        var emeraldTip: Bool? = nil                 // the one-time "emeralds sell at a bank" tip was shown (G14)
        // R20 (TownJail.swift, TownServices.swift): a jail term being served, weapons a jailbreak left locked up (town ->
        // items), an outlaw in tow ([name, job key]), and the one-time exchange hint given in a town.
        var jail: Jail.Term? = nil
        var impounded: [String: [ItemStack]]? = nil
        var prisoner: [String]? = nil
        var exchangeTip: Bool? = nil
        // D20 strangers (Strangers.swift): story -> chapter * 10 + taken, kills / visits, ridge spots, last day seen.
        var strangers: [String: Int]? = nil
        var strangerCount: [String: Int]? = nil
        var strangerAt: [String: [Int]]? = nil
        var strangerDay: Int? = nil
        // D26 gang leaders (GangLeaders.swift): bosses beaten, hideouts whose gang has turned up.
        var gangsBeaten: [String]? = nil
        var gangsMet: [String]? = nil
        // D27 (Fence.swift): stolen units per item key, and the day of the last theft.
        var hot: [String: Int]? = nil
        var hotDay: Int? = nil
        var property: [[Int]]? = nil                 // D28 (Property.swift): your houses and homesteads
        var orders: [[String]]? = nil                // D29 (MailOrder.swift): catalog orders [key, count, due day]
        var ordersToasted: Bool? = nil
        var baseObj: [String: Int]? = nil            // D34 (BaseObjectives.swift): base key -> objectives done
        var loudBases: [String]? = nil               // D36 (Bodies.swift): bases whose alarm has sounded
        var alarms: [String]? = nil                  // D38 (BaseCounter.swift): bases whose alarm was up at the save
        var counter: [String: Int]? = nil            // D38: base key -> the day it fell or was last counter-attacked
        var portsMet: [String]? = nil                // D39 (NavalPort.swift): dockyards whose garrison has turned up
        var portsTaken: [String]? = nil              // D39: dockyards whose garrison you cleared
        var vehicleFuel: [String: Float]? = nil      // D44 (VehicleDepot.swift): ship id -> tank level
        var garage: [String]? = nil                  // D44: garaged vehicles ("name|ships json, base64#fuel")
        var vaultObj: [String: Int]? = nil           // D47: Vault side objectives
        var tracked: String? = nil                   // D51: the one target the HUD marker and beacon follow ("kind|key")
        var beds: [[Int]]? = nil                     // P284 (a): both halves of every bed that is yours (placed or bought)
        var innRoom: [Int]? = nil                    // P284 (c): the hotel room paid for [x, y, z of the inn, night]
    }
    static var state = Saved()
    static var placedSet = Set<IVec3>()
    static var placedOrder: [IVec3] = []            // oldest first (may hold stale entries until compacted)

    // Live (not saved).
    static var inTown: String?                      // the town the player is in (townsfolk within 48), every second
    static var forceTown: Bool?                     // tests: treat every spot as town (true) or none (false)
    static var lastTick: Double = -1
    static var lastAmbient: Double = -100
    static var openPos: IVec3?
    static var openKey = ""                         // the chest's deposit key (both halves of a double chest share one)
    static var openItems: [ItemID: Int]?            // what the open town container held at the last check (nil: not a town container)
    static var openStart: Double = 0
    static var pending: [(Mob, Double)] = []        // sheriffs about to draw (after their challenge)
    static var offences = 0                         // counted (TownTests)
    static var robberies = 0                        // P366 (g): tills handed over at gunpoint or knifepoint

    static func reset() {
        state = Saved(); placedSet = []; placedOrder = []; inTown = nil; pending = []; openPos = nil; openItems = nil
        Honour.challengedVisit = nil; Honour.changedAt = -100; Honour.delta = 0; Honour.lastToast = -100
        Honour.lastWhy = ""; Honour.outlawSpotted = nil
        offences = 0; lastTick = -1; sleptBeds = [:]
        ownBeds = []; builtBed = [:]                    // P284
        lastShot = nil; Jail.passPack = false; TownLines.forget()          // R20
        TownConquest.reset(); TownConquest.wary = []
        GangLeaders.spawnedHere = []                    // D26
    }
    // Keeps the newest `n` remembered blocks that are still the player's.
    static func compactPlaced(_ n: Int) {
        var seen = Set<IVec3>(), out: [IVec3] = []
        for p in placedOrder.reversed() where placedSet.contains(p) && seen.insert(p).inserted {
            out.append(p)
            if out.count >= n { break }
        }
        placedOrder = out.reversed()
        placedSet = seen
    }
    static func save(_ d: inout [String: String]) {
        compactPlaced(4096)
        state.placed = placedOrder.map { [$0.x, $0.y, $0.z] }
        state.beds = ownBeds.isEmpty ? nil : ownBeds.map { [$0.x, $0.y, $0.z] }          // P284 (a)
        if let e = try? JSONEncoder().encode(state), let s = String(data: e, encoding: .utf8) { d["townLaw"] = s }
    }
    static var worldSeed: UInt64?                  // the world this state belongs to (a new world starts clean)
    static func load(_ d: [String: String], seed: UInt64) {
        reset()
        worldSeed = seed
        if let s = d["townLaw"], let data = s.data(using: .utf8), let st = try? JSONDecoder().decode(Saved.self, from: data) {
            state = st
            placedOrder = st.placed.compactMap { $0.count == 3 ? IVec3($0[0], $0[1], $0[2]) : nil }
            placedSet = Set(placedOrder)
            ownBeds = Set((st.beds ?? []).compactMap { $0.count == 3 ? IVec3($0[0], $0[1], $0[2]) : nil })     // P284 (a)
        }
    }

    // MARK: Where and who

    static func isTownSpot(_ g: Game, _ p: IVec3) -> Bool {
        if let f = forceTown { return f }
        if Property.owns(p) { return false }                                    // D28: your own house or homestead
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures,
              let s = sc.nearest("village", x: p.x, z: p.z, maxRegions: 1) else { return false }
        return abs(s.anchor.x - p.x) < 72 && abs(s.anchor.z - p.z) < 72
    }

    // The town owns this block: it lies in one of the nearest village's generated pieces (houses and their lots,
    // farms, the square, roads), no deeper than 4 blocks under a lot's floor.
    static func isTownOwned(_ g: Game, _ p: IVec3) -> Bool {
        if let f = forceTown { return f }
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures,
              let s = sc.nearest("village", x: p.x, z: p.z, maxRegions: 1),
              abs(s.anchor.x - p.x) < 200 && abs(s.anchor.z - p.z) < 200 else { return false }
        if let m = s.plan as? Mine, m.underground(p) { return false }          // C12: the mine's workings are company ground
        return s.pieces.contains { pc in
            p.x >= pc.min.x && p.x <= pc.max.x && p.z >= pc.min.z && p.z <= pc.max.z
                && p.y <= pc.max.y && p.y >= max(pc.min.y, pc.max.y - 18)
        }
    }

    static func isTownsperson(_ m: Mob) -> Bool { m.kind == .villager && m.health > 0 && m.villager?.person != nil }
    static func isLaw(_ m: Mob) -> Bool { m.villager?.role == "sheriff" || m.villager?.role == "deputy" }

    // Townsfolk who see the player do something: awake, within 20 blocks, a clear line of sight from their eyes to the
    // player's (walls hide you; windows don't).
    static func witnesses(_ g: Game, at p: V3) -> [Mob] {
        var out: [Mob] = []
        for o in g.mobs.mobs where isTownsperson(o) && !o.lying {
            if simd_length(o.eye - g.player.eye) < 20 && g.world.canSee(o.eye, g.player.eye) { out.append(o) }
        }
        return out.sorted { simd_length($0.pos - g.player.pos) < simd_length($1.pos - g.player.pos) }
    }

    static func town(of m: Mob, _ g: Game) -> String { m.villager?.town ?? Townsfolk.town(g, at: m.home ?? m.pos) }
    static func heat(_ town: String) -> Float { state.heat[town] ?? 0 }
    static func isHostile(_ town: String) -> Bool { (state.hostile[town] ?? 0) > 0 }
    static func isHostile(_ g: Game, _ m: Mob) -> Bool { isHostile(town(of: m, g)) }

    // MARK: Hooks from the game

    // Game.interact after placing a block: the player's own, never theft.
    static func placed(_ g: Game, _ p: IVec3) {
        guard isTownSpot(g, p) else { return }
        placedSet.insert(p)
        placedOrder.append(p)
        if placedOrder.count > 6000 { compactPlaced(4096) }
    }

    // What counts as town property (crops, buildings, fittings, containers), per block state.
    static let property: [Bool] = (0..<Blocks.count).map { i in
        let k = Blocks.key(Blocks.groupBase[i])
        if ["wheat", "carrots", "potatoes", "beetroots", "melon", "pumpkin", "hay_block", "farmland", "bell", "dirt_path"].contains(k) { return true }
        let words = ["planks", "door", "glass", "_bed", "chest", "barrel", "fence", "lantern", "torch", "sign", "wool", "carpet", "terracotta",
                     "cobblestone", "stairs", "slab", "bookshelf", "furnace", "smoker", "composter", "lectern", "loom", "cauldron",
                     "_table", "stand", "stonecutter", "grindstone", "anvil", "bricks", "wall", "pane", "bars", "flower_pot",
                     "jukebox", "iron_block", "stripped_", "smooth_stone", "chain"]
        return words.contains { k.contains($0) }
    }

    // P59: sleeping in a town bed that isn't yours (not one you placed, not a town you own) costs honour, once a night
    // per bed; taking the bed is already an offence (property, broke()).
    // P284 (Oct 14 19:38, "I slept in my own bed, and they didn't like that"): placing a bed never told the town it was
    // yours (Game.placeBed skipped TownLaw.placed), so a bed he set down in town was charged as someone else's.
    // (a) Beds remember their owner: both halves of a bed you place are yours (saved with the world, never forgotten
    // like the capped placed-block list), as are beds in a house you bought (Property). (b) Only a bed the town built
    // costs honour. (c) The saloon bed in the town where you paid for a room is yours that night. (d) Old saves never
    // recorded placed beds: a bed the village did not generate at that spot is yours (TownLaw.townBuiltBed), and it is
    // claimed the first time you sleep in it.
    static var sleptBeds: [IVec3: Int] = [:]
    static let bedHonour: Float = -3
    static var ownBeds = Set<IVec3>()
    static var builtBed: [IVec3: Bool] = [:]        // townBuiltBed answers (generation never changes)

    // Both halves of the bed at p (just p when the block there is not a bed, or when `b` names it).
    static func bedHalves(_ g: Game, _ p: IVec3, _ b0: BlockID? = nil) -> [IVec3] {
        let b = b0 ?? g.world.block(p.x, p.y, p.z)
        guard Int(b) < VillageLife.bedAny.count, VillageLife.bedAny[Int(b)] else { return [p] }
        let facing = Int(b - Blocks.groupBase[Int(b)])
        let dirs = [IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(1, 0, 0), IVec3(-1, 0, 0)]
        guard facing >= 0 && facing < 4 else { return [p] }
        return [p, VillageLife.bedHead[Int(b)] ? p - dirs[facing] : p + dirs[facing]]
    }
    // P284 (a): the player set this bed down (Game.placeBed) or it came with something he paid for.
    static func claimBed(_ g: Game, _ p: IVec3) {
        for h in bedHalves(g, p) { ownBeds.insert(h) }
    }
    static func bedIsYours(_ g: Game, _ p: IVec3) -> Bool {
        var halves = bedHalves(g, p)
        if halves.count == 1 { halves += [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)].map { p + $0 } }  // not loaded: either side
        if halves.contains(where: { ownBeds.contains($0) || placedSet.contains($0) || Property.owns($0) }) { return true }
        // (c) The room you paid for: the bed in that saloon (the keeper's back corner) is yours until sunrise.
        if let r = state.innRoom, r.count == 4, r[3] == Int(g.time / DAY_LENGTH) {
            let dx = Float(p.x - r[0]), dz = Float(p.z - r[2])
            if abs(dx) <= 12 && abs(dz) <= 12 && abs(p.y - r[1]) <= 6 { return true }
        }
        // (d) Not a bed the town built here: one you set down (an old save that never wrote it down).
        if !halves.contains(where: { townBuiltBed(g, $0) }) { claimBed(g, p); return true }
        return false
    }
    // The village generated a bed at p: rebuild its pieces over p's chunk into a scratch column and look.
    static func townBuiltBed(_ g: Game, _ p: IVec3) -> Bool {
        if let f = forceTown { return f }                                   // tests: every spot is the town's
        if let known = builtBed[p] { return known }
        guard p.y >= 0 && p.y < CH, let sc = g.world.gen.structures,
              let s = sc.nearest("village", x: p.x, z: p.z, maxRegions: 1) else { return false }
        let cx = floorDiv(p.x, CS), cz = floorDiv(p.z, CS)
        var scratch = [BlockID](repeating: AIR, count: CS * CS * CH)
        var built = false
        scratch.withUnsafeMutableBufferPointer { buf in
            var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
            for pc in s.pieces where pc.overlaps(cx * CS, cz * CS) { pc.build(&w) }
            built = VillageLife.bedAny[Int(w.get(p.x, p.y, p.z))]
        }
        builtBed[p] = built
        return built
    }
    static func sleptIn(_ g: Game, _ p: IVec3) {
        guard g.survival, isTownOwned(g, p) else { return }
        guard !TownConquest.owns(Townsfolk.town(g, at: V3(Float(p.x), Float(p.y), Float(p.z)))) else { return }
        guard !bedIsYours(g, p) else { return }                             // P284 (b)
        let night = Int(g.time / DAY_LENGTH)
        guard sleptBeds[p] != night else { return }
        sleptBeds[p] = night
        Honour.change(g, bedHonour, "you slept in someone else's bed")
    }

    // P63 (Oct 11 evening playtest): gunfire in a town draws people. The sheriff and deputies within 48 blocks, and the
    // four nearest grown townsfolk within 32, walk over to where the shot came from and look about (law 20 s, others
    // 12 s). Nobody already fighting, asleep or a child.
    static var shotsHeard = 0
    static var lastShot: (at: V3, clock: Double)?   // R20: the last gunfire in a town (townsfolk talk about it: TownLines)
    static func gunfire(_ g: Game, at p: V3) {
        if let gu = g.netGuest { gu.gunfire(at: p); return }                   // C14: the host's townsfolk hear it
        MiningTowns.spark(g, at: p)                                            // C12: a muzzle flash in mine gas
        guard g.dim.dim == .overworld, isTownSpot(g, IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))) else { return }
        lastShot = (p, g.clock)
        var folk: [(Mob, Float)] = []
        for m in g.mobs.mobs where isTownsperson(m) && !m.lying && !m.baby && m.town.anger <= 0 && m.villager?.role != "child" {
            let d = simd_length(m.pos - p)
            guard d > 3 else { continue }
            if isLaw(m) {
                if d < 48 { if m.town.investigate == nil { shotsHeard += 1 }; m.town.investigate = p; m.town.investigateT = 20 }
            } else if d < 32 { folk.append((m, d)) }
        }
        for (m, _) in folk.sorted(by: { $0.1 < $1.1 }).prefix(4) {
            if m.town.investigate == nil { shotsHeard += 1 }
            m.town.investigate = p; m.town.investigateT = 12
        }
    }

    // Game.breakBlock (the player broke b at p).
    // A town container costs what taking its contents would (less what the player put in), at least 1.
    static func broke(_ g: Game, _ p: IVec3, _ b: BlockID) {
        guard Int(b) < property.count, property[Int(b)] else { return }
        if VillageLife.bedAny[Int(b)] {                                     // P284 (a): a bed you took up is no longer yours
            let halves = bedHalves(g, p, b)
            if halves.contains(where: { ownBeds.contains($0) }) {
                for h in halves { ownBeds.remove(h); placedSet.remove(h) }
                return
            }
        }
        if placedSet.remove(p) != nil { return }
        guard g.survival, isTownOwned(g, p) else { return }
        var heat: Float = 1
        if let be = g.world.blockEntities[p], !be.items.isEmpty {
            var have: [ItemID: Int] = [:]
            for s in be.items where !s.isEmpty { have[s.item, default: 0] += s.count }
            let key = chestKey(g, p)
            heat = takingHeat(settle(key, from: have, to: [:]))
            state.deposits?[key] = nil
        }
        offence(g, heat: heat, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
    }
    static func takingHeat(_ n: Int) -> Float { n > 0 ? 1 + min(2, Float(n) / 16) : 1 }

    // One key per chest; a double chest's halves share the smaller position's.
    static func chestKey(_ g: Game, _ p: IVec3) -> String {
        let b = g.world.block(p.x, p.y, p.z)
        var k = p
        if Blocks.key(Blocks.groupBase[Int(b)]).hasSuffix("chest") {
            for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
                let q = p + d
                if Blocks.groupBase[Int(g.world.block(q.x, q.y, q.z))] == Blocks.groupBase[Int(b)], (q.x, q.z) < (k.x, k.z) { k = q }
            }
        }
        return "\(k.x),\(k.y),\(k.z)"
    }
    // A container's contents went from `a` to `b`: additions are the player's deposits, removals come out of the
    // deposits first. Returns how many of the town's own items were taken.
    static func settle(_ key: String, from a: [ItemID: Int], to b: [ItemID: Int]) -> Int {
        var dep = state.deposits?[key] ?? [:]
        var taken = 0
        for id in Set(a.keys).union(b.keys) {
            let d = (b[id] ?? 0) - (a[id] ?? 0)
            let k = Items.key(id)
            if d > 0 { dep[k, default: 0] += d }
            else if d < 0 {
                let own = min(-d, dep[k] ?? 0)
                let left = (dep[k] ?? 0) - own
                dep[k] = left > 0 ? left : nil
                taken += -d - own
                if -d - own > 0 { Fence.mark(k, -d - own, day: Fence.today) }   // D27: hot goods
            }
        }
        if state.deposits == nil { state.deposits = [:] }
        state.deposits?[key] = dep.isEmpty ? nil : dep
        return taken
    }

    // Game.openBlock: remember which block's menu is about to open (chests, barrels).
    static func opening(_ g: Game, _ p: IVec3) {
        openPos = p; openStart = g.clock; openItems = nil
    }
    // Game.openMenu: a container menu from a town chest or barrel: count what's inside.
    static func opened(_ g: Game, _ m: Menu) {
        if Jail.interceptPack(g, m) { return }                                 // R20: in a cell, the pack opens the jail's ledger
        if let p = openPos, g.clock - openStart < 0.5, m is ChestMenu || m is DoubleChestMenu, Jail.lockedBox(g, p) {
            openPos = nil
            g.closeMenu()
            g.onToast?("Locked")
            return
        }
        guard let p = openPos, g.clock - openStart < 0.5, m is ChestMenu || m is DoubleChestMenu,
              !placedSet.contains(p), isTownOwned(g, p) else { openPos = nil; return }
        openKey = chestKey(g, p)
        openItems = containerItems(g, m)
    }
    // Per second while the menu is open, and when it closes: items gone from the container are theft.
    static func checkTaking(_ g: Game, _ m: Menu) {
        guard let p = openPos, let before = openItems else { return }
        let now = containerItems(g, m)
        let n = settle(openKey, from: before, to: now)
        openItems = now
        guard n > 0 && g.survival else { return }
        let at = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        // P366 (g): robbing a trader's own stock or till in front of him is a robbery, not pilfering: the town turns.
        let keeper = witnesses(g, at: at).first { $0.villager?.shop != nil && simd_length($0.pos - at) < 10 }
        offence(g, heat: keeper != nil ? hostileHeat : takingHeat(n), at: at, victim: keeper)
    }
    static func closed(_ g: Game, _ m: Menu) {
        if openPos != nil { checkTaking(g, m) }
        openPos = nil
    }
    static func containerItems(_ g: Game, _ m: Menu) -> [ItemID: Int] {
        var n: [ItemID: Int] = [:]
        for s in m.slots where !s.isPlayerInv && !s.isHotbar {
            guard let c = s.container, s.index < c.count, c !== g.inventory.main, !c[s.index].isEmpty else { continue }
            n[c[s.index].item, default: 0] += c[s.index].count
        }
        return n
    }

    // townAlarm: the player hurt a townsperson (the victim always notices).
    static func assault(_ g: Game, _ victim: Mob) {
        offence(g, heat: 2, at: victim.eye, victim: victim, speak: false)
    }

    // MARK: Escalation

    static func offence(_ g: Game, heat add: Float, at p: V3, victim: Mob? = nil, speak: Bool = true) {
        guard g.dim.dim == .overworld, g.survival else { return }      // creative: no theft, no warnings
        if let gu = g.netGuest { gu.crime(heat: add, at: p, speak: speak); return }   // C14: the host's town answers
        if TownConquest.owns(Townsfolk.town(g, at: p)) { return }        // your own town: its things are yours
        var ws = witnesses(g, at: p)
        if let v = victim, !ws.contains(where: { $0 === v }) { ws.insert(v, at: 0) }
        // Unseen, it still costs honour (a third of what a witness would make it): stealing is stealing.
        guard let first = ws.first else { Honour.unseenTheft(g, 0.5 * add); return }
        let town = town(of: first, g)
        if heat(town) + add < hostileHeat, Witnesses.start(g, witness: first, town: town, heat: add, at: p, victim: victim) { return }   // D23
        let masked = Bandana.masked(g)                   // D22: a masked crime is held, not pinned on him
        if !masked { Countries.crime(g, town: town, at: p, heat: add) }
        let h = heat(town) + add
        state.heat[town] = h
        offences += 1
        if masked { Bandana.hold(town, honour: victim != nil ? 3 : 1.5 * add, bounty: 0) }
        else { Honour.crime(g, heat: add, assault: victim != nil) }
        let law = g.mobs.mobs.filter { isTownsperson($0) && isLaw($0) && simd_length($0.pos - g.player.pos) < 40 }
            .min { simd_length($0.pos - g.player.pos) < simd_length($1.pos - g.player.pos) }
        if h >= hostileHeat {
            turnHostile(g, town, at: p, witness: first)
            return
        }
        for w in ws { if var v = w.villager { v.addGossip(.minorNeg, h >= 2 ? 12 : 6); w.villager = v } }
        guard speak else { return }
        if h >= 2, let l = law {
            if simd_length(l.pos - g.player.pos) > 4 { l.wanderGoal = g.player.pos; l.moving = true; l.aiTimer = 4 }
            l.face(g.player.pos)
            Townsfolk.townLastLine = -100
            TownVoice.speak(g, l, isLawWithin(l, g, 14) ? .theft : .challenge)
        } else {
            first.face(g.player.pos)
            Townsfolk.townLastLine = -100
            TownVoice.speak(g, first, .theft)
        }
    }
    static func isLawWithin(_ m: Mob, _ g: Game, _ r: Float) -> Bool { simd_length(m.pos - g.player.pos) < r }

    static func turnHostile(_ g: Game, _ town: String, at p: V3, witness: Mob) {
        let fresh = !isHostile(town)
        state.hostile[town] = hostileSeconds
        state.heat[town] = hostileHeat
        for o in g.mobs.mobs where isTownsperson(o) && simd_length(o.pos - p) < 64 {
            if var v = o.villager, fresh { v.addGossip(.majorNeg, 12); o.villager = v }
            if o.villager?.role == "sheriff" {
                if fresh {
                    // He calls you out and draws (SixIron: the gun comes out with a click; he fights 2.5 s later).
                    o.face(g.player.pos); pending.append((o, g.clock + 2.5)); o.town.drawn = 3; o.town.warned = false
                    g.sfx(.gunReload(WeaponAudio.sidearmSlot), 0.6, at: o.eye)
                    Townsfolk.townLastLine = -100; TownVoice.speak(g, o, .challenge)
                }
                else { o.town.anger = max(o.town.anger, hostileSeconds) }
            } else if o.townWeapon != .none && !o.baby {
                o.town.anger = max(o.town.anger, 60)
            } else {
                o.panic = max(o.panic, 8)
            }
        }
        if fresh {
            if Bandana.masked(g) { Bandana.hold(town, honour: 5, bounty: 500) }      // D22
            else {
                Honour.townTurned(g, town)
                Countries.townTurned(g, town: town, at: p)
            }
            if witness.villager?.role != "sheriff" { Townsfolk.townLastLine = -100; TownVoice.speak(g, witness, .angry) }
            g.onToast?("\(town) has turned on you!")
        }
    }

    // MARK: Every frame (from HudExtras.tick); real work once a second.

    // G14, R20: the exchange, once, the first time you carry emeralds in a town. P328 (NO TEXT): nothing said; every shop
    // counter leads with an Exchange row while you carry emeralds, and the bank and store have the EXCHANGE sign.
    static func emeraldTip(_ g: Game) {
        guard g.survival, inTown != nil, state.exchangeTip != true, Items.has("emerald"), g.inventory.main.countOf(Items.id("emerald")) > 0 else { return }
        state.exchangeTip = true
        state.emeraldTip = true
    }

    static func tick(_ g: Game) {
        if worldSeed != g.world.seed { reset(); worldSeed = g.world.seed }
        Jail.watchOutlaws(g)                             // R20: a beaten outlaw gives up (per frame while one is out)
        Bandana.tick(g)                                  // D22
        Witnesses.tick(g)                                // D23
        // Sheriffs draw after their challenge.
        if !pending.isEmpty {
            pending.removeAll { (m, t) in
                guard g.clock >= t else { return false }
                if m.health > 0 { m.town.anger = max(m.town.anger, hostileSeconds) }
                return true
            }
        }
        guard g.clock - lastTick >= 1 || lastTick < 0 else { return }
        let dt = Float(lastTick < 0 ? 1 : min(5, g.clock - lastTick))
        lastTick = g.clock
        // Once a second:
        Legendaries.tick(g)                              // C10: worn and held perks, the gallery
        Seasons.tick(g)                                  // C9: the season, herds and festival nights
        Nation.tick(g)                                   // C3: your provinces' days, settlers and buildings
        if let m = g.menu, openPos != nil { checkTaking(g, m) }
        emeraldTip(g)
        Strangers.tick(g)                                // D20
        GangLeaders.tick(g)                              // D26: gang bosses at their hideouts
        Fence.tick(g)                                    // D27: hot goods cool off
        MailOrder.tick(g)                                // D29: parcels come in
        FactionArmour.tick(g)                            // D33: a full faction set's edge
        Disguise.tick(g, dt)                             // D37: a close look through a disguise
        NavalPort.tick(g)                                // D39: dockyard garrisons and harbourmasters
        FrontierSites.tick(g)                            // D48: frontier sites on the map, the ghost town's dead
        Waymarks.tick(g)                                 // D51: the tracked target's beacon, moving map marks
        Tracking.tick(g)                                 // D46: tracks, blood trails, the wind
        Fence.today = Int(g.time / DAY_LENGTH)
        Saloon.tick(g)                                   // D17: the piano player
        Jail.tick(g, dt)                                 // R20: the jail term, a prisoner in tow
        // Heat cools; hostility runs out.
        let cool = Honour.coolRate(Honour.value)
        for (t, h) in state.heat where !isHostile(t) {
            let n = h - dt * cool / 90
            state.heat[t] = n > 0 ? n : nil
        }
        for (t, s) in state.hostile {
            let n = s - dt
            if n <= 0 {
                state.hostile[t] = nil
                state.heat[t] = 1
                g.onToast?("\(t) has calmed down.")
            } else {
                state.hostile[t] = n
            }
        }
        // Which town the player is in.
        guard g.dim.dim == .overworld, g.alive else { inTown = nil; return }
        TownBoard.tick(g)
        Contracts.tick(g)                                // C11
        MiningTowns.tick(g)                              // C12: mine gas
        BountyHunters.tick(g)
        TownRaids.tick(g)                                  // night raids (TownRaids.swift)
        var nearest: Mob?
        var nd: Float = 48
        var sheriffs: [String: [Mob]] = [:]
        for o in g.mobs.mobs where isTownsperson(o) {
            let d = simd_length(o.pos - g.player.pos)
            if d < nd && !o.baby { nd = d; nearest = o }
            if o.villager?.role == "sheriff" { sheriffs[town(of: o, g), default: []].append(o) }
        }
        oneSheriff(g, sheriffs)
        guard let near = nearest else {
            inTown = nil; Honour.tick(g, town: nil); TownConquest.tick(g, town: nil); TownBoard.posters(g, town: nil); return
        }
        let here = town(of: near, g)
        inTown = here
        TownBoard.posters(g, town: here)
        Honour.tick(g, town: here)
        TownConquest.tick(g, town: here)
        let day = Int(g.time / DAY_LENGTH)
        if sheriffs[here] != nil { state.appointed[here] = day }
        else if day - (state.appointed[here] ?? -99) >= 3, squareLoaded(g, near) {
            appointSheriff(g, here, near: near)
        }
        // Outlaws are fought on sight (Honour.outlawSeen); the WANTED boards show your poster; outlaws from jobs.
        // (Not at a man serving his time in the cell.)
        if g.survival && Jail.term == nil && Honour.outlawKnown(g) && !isHostile(here) && !TownConquest.owns(here) { Honour.outlawSeen(g, here) }
        // A hostile town keeps its armed folk on you while you're about.
        if isHostile(here) {
            for o in g.mobs.mobs where isTownsperson(o) && o.townWeapon != .none && !o.baby && simd_length(o.pos - g.player.pos) < 32 {
                o.town.anger = max(o.town.anger, 3)
            }
        }
        ambientChatter(g)
    }

    // One sheriff per town (Saved.sheriffs names him): another one loaded in the same town (a cured zombie sheriff,
    // or the square's own sheriff turning up after one was sent) serves as a deputy.
    static func oneSheriff(_ g: Game, _ byTown: [String: [Mob]]) {
        for (t, list) in byTown {
            let named = state.sheriffs?[t]
            let keep = list.first { $0.villager?.person == named } ?? list[0]
            if state.sheriffs == nil { state.sheriffs = [:] }
            state.sheriffs?[t] = keep.villager?.person
            for o in list where o !== keep {
                if var v = o.villager { v.role = "deputy"; o.villager = v }
            }
        }
    }
    // Only a real town whose square has loaded gets a sheriff sent (its own may be standing there).
    static func squareLoaded(_ g: Game, _ near: Mob) -> Bool {
        if let f = forceTown { return f }
        let c = IVec3(Int(floor(near.pos.x)), Int(floor(near.pos.y)), Int(floor(near.pos.z)))
        guard isTownSpot(g, c), let sc = g.world.gen.structures, let s = sc.nearest("village", x: c.x, z: c.z, maxRegions: 1) else { return false }
        return g.world.isLoaded(s.anchor.x, s.anchor.z)
    }

    // A sheriff for a town that has none (older towns, or three days after the last one fell): next to the deputy
    // or a townsperson, on open ground.
    static func appointSheriff(_ g: Game, _ town: String, near: Mob) {
        let anchor = g.mobs.mobs.first { isTownsperson($0) && $0.villager?.role == "deputy" && TownLaw.town(of: $0, g) == town } ?? near
        let c = anchor.home ?? anchor.pos
        let w = g.world
        // Open ground round the anchor; failing that (a square crowded with trees, or ground not meshed yet), where the
        // anchor itself stands, so a town is never left without its sheriff.
        for k in 0..<33 {
            let m: Mob
            if k < 32 {
                let a = Float(k) * 2.4
                let r: Float = 2 + Float(k % 7)
                let x = Int(floor(c.x + cosf(a) * r)), z = Int(floor(c.z + sinf(a) * r))
                var y = Int(floor(c.y)) + 3
                while y > Int(floor(c.y)) - 4 && !(Blocks.collide[Int(w.block(x, y - 1, z))] && !Blocks.collide[Int(w.block(x, y, z))]) { y -= 1 }
                guard y > Int(floor(c.y)) - 4, !Blocks.isLiquid(w.block(x, y, z)) else { continue }
                m = Mob(.villager, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
                if m.collides(m.pos, w) { continue }
            } else {
                m = Mob(.villager, at: anchor.pos)
            }
            m.home = anchor.home ?? m.pos
            m.persistent = true
            Townsfolk.setup(m, tag: "sheriff", game: g)
            if var v = m.villager { v.town = town; m.villager = v }
            g.mobs.mobs.append(m)
            state.appointed[town] = Int(g.time / DAY_LENGTH)
            if state.sheriffs == nil { state.sheriffs = [:] }
            state.sheriffs?[town] = m.villager?.person
            return
        }
    }

    // Unprompted lines (chatter and the hello as you pass) share one budget: at most one every `ambientGap` seconds
    // town-wide, ~2-3 a minute in a busy town; each person greets you at most every `greetGap` seconds.
    static let ambientGap: Double = 20
    static let greetGap: Float = 240
    static func ambientOK(_ g: Game) -> Bool { g.clock - Townsfolk.townLastLine > ambientGap }

    // Now and then a townsperson near the player says something.
    static func ambientChatter(_ g: Game) {
        guard g.menu == nil, ambientOK(g), g.clock - lastAmbient > 30, Rand.float(in: 0..<1) < 0.06 else { return }
        let cands = g.mobs.mobs.filter {
            isTownsperson($0) && !$0.lying && $0.town.anger <= 0 && $0.panic <= 0 && simd_length($0.pos - g.player.pos) < 14
                && simd_length($0.pos - g.player.pos) > 3 && g.world.canSee($0.eye, g.player.eye)
        }
        guard let m = cands.randomElement() else { return }
        lastAmbient = g.clock
        if let inT = inTown, isHostile(inT) { TownVoice.speak(g, m, .angry); return }
        TownVoice.speak(g, m, g.dayFraction > 0.5 ? .night : .chatter)
    }

    // The sheriff's role (Townsfolk.setup with the "sheriff" tag): a man's name, so his voice fits.
    static func deputize(_ v: inout VillagerData) {
        v.role = "sheriff"; v.locked = true; v.profession = "none"
        if Townsfolk.isWoman(v), let p = v.person {
            let men = Townsfolk.firstNames.filter { !Townsfolk.women.contains($0) }
            let last = p.split(separator: " ").last.map(String.init) ?? "Hale"
            v.person = "\(men[(v.look ?? 0) % men.count]) \(last)"
        }
    }

    // MARK: The sheriff's six-iron at monsters (from townDefend; at the player: SixIron.duel)

    static func shoot(_ m: Mob, _ g: Game) {
        guard let foe = m.town.foe else { return }
        let target = foe.eye
        let muzzle = SixIron.muzzle(m)
        g.sfx(.gun(WeaponAudio.sidearmSlot), 1, at: muzzle)
        g.particles.smoke(at: muzzle)
        guard g.world.canSee(muzzle, target) else { return }
        let d = simd_length(target - muzzle)
        let chance: Float = d < 6 ? 0.85 : 0.7
        guard Rand.float(in: 0..<1) < chance else { return }
        foe.hit(from: m.pos, damage: 8, knockback: 0.3)
    }
}

extension Mob {
    // Every villager is a townsperson: one without a name or town (made by a path that doesn't set one up: breeding,
    // a cure, an egg, a raid, a pre-town save) becomes one the first frame it's updated (MobManager.update), before
    // it's drawn or talked to, instead of at its first job check up to 5 s later.
    func becomeTownsperson(_ g: Game) {
        if villager == nil {
            var v = VillagerData()
            v.type = Villagers.type(for: g.world.gen.column(Int(floor(pos.x)), Int(floor(pos.z))).biome)
            if !baby && Rand.float(in: 0..<1) < 0.12 { v.profession = "nitwit" }
            villager = v
        }
        Townsfolk.setup(self, game: g)
    }
}

extension Game {
    // Spoken greeting (TownVoice) for the proximity hello and a tap: always a recorded line (the older text greeting
    // only for a voice without one).
    func townGreet(_ m: Mob, _ v: VillagerData) {
        if TownConquest.greet(self, m, v) { return }    // your own town: they call you boss
        if TownLaw.isHostile(self, m) || v.reputation <= -60 { TownVoice.speak(self, m, .angry); return }
        if Honour.greet(self, m, v) { return }          // the standing's own words: warnings, tips, gifts, your name
        let ctx: TownVoice.Ctx = raid != nil ? .raid : dayFraction > 0.5 ? .night : (Rand.float(in: 0..<1) < 0.55 ? .greet : .chatter)
        if TownVoice.speak(self, m, ctx) == nil { Townsfolk.say(self, m, VillagerMinds.current.greeting(m, VillagerMinds.context(m, self), self)) }
    }
}
