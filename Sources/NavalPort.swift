import Foundation
import simd

// D39: naval ports and dockyards. Here and there on a coast, where the land drops straight into deep water, the
// Meridian Navy keeps a dockyard (structure "naval_port", rare: one region of 36 x 36 chunks in a few has the coast for
// one): a paved yard on the shore, a quay wall, a long timber pier out into deep water, a crane, two stone storehouses
// (Navy stores: "port_stores") and the harbour office (the port's strongbox: "port_armory"). Come within 72 blocks:
//   the garrison   six Meridian marines turn up once (saved: TownLaw.state.portsMet); while the Navy is not your ally
//                  they shoot, and the stores are there for the taking. Clear them and the port is taken (portsTaken).
//   the office     a harbourmaster keeps the office. He'll deal with an ally of the Navy, or with whoever cleared the
//                  garrison (HarbourMenu): repair the hull of your vessel lying off the pier (every chip made good, a
//                  foundering hull afloat again), a sloop hull launched at the pier's end, a submarine or sky skiff kit,
//                  ship cannons and engines.
// The port goes on the map ("D").
enum NavalPort {
    static let kind = "naval_port"
    static let spacing = 36, separation = 10
    static let showUp: Float = 72
    static let marine = "Meridian Marine"
    static var spawnedHere = Set<IVec3>()                // (also saved: portsMet)
    static var seen: [IVec3: Int] = [:]                  // seconds the port's ground has been loaded with the player near
    static var bought = 0, repaired = 0                  // (harness)

    static let loot: [String: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)])] = [
        "port_stores": (4...7, [("iron_ingot", 2, 6, 16), ("gunpowder", 2, 6, 14), ("rope", 2, 6, 10), ("string", 2, 6, 10), ("white_wool", 2, 6, 10),
                                ("dark_oak_planks", 6, 16, 12), ("bread", 2, 6, 12), ("cooked_cod", 2, 6, 10), ("coal", 4, 12, 12),
                                ("ship_propeller", 1, 1, 3), ("ship_cannon", 1, 1, 2), ("ship_engine", 1, 1, 2), ("compass", 1, 1, 3)]),
        "port_armory": (3...5, [("gold_ingot", 1, 4, 12), ("emerald", 2, 6, 12), ("gold_nugget", 4, 14, 14), ("map", 1, 1, 6),
                                ("spyglass", 1, 1, 6), ("experience_bottle", 1, 3, 8), ("diamond", 1, 2, 3), ("submarine_kit", 1, 1, 1),
                                ("sky_skiff_kit", 1, 1, 1)]),
    ]

    static func b(_ n: String, _ f: String) -> BlockID { Blocks.has(n) ? Blocks.id(n) : Blocks.id(f) }

    // MARK: Placement

    // A port frame: u across the shore, v out to sea (forward fx, fz); dy from the deck.
    struct Frame {
        let x: Int, z: Int, fx: Int, fz: Int
        func p(_ u: Int, _ v: Int) -> (Int, Int) { (x - u * fz + v * fx, z + u * fx + v * fz) }
    }

    static func type(_ gen: WorldGen) -> StructureType {
        StructureType(name: kind, spacing: spacing, separation: separation, salt: 39182447, reach: 7) { [unowned gen] seed, cx0, cz0 in
            // Ground saved before the ports keeps its coast (a pier half over saved chunks would be cut off).
            if let sc = gen.structures, !sc.clear(cx: cx0, cz: cz0, reach: 7, guardSet: sc.legacyPorts) { return nil }
            let o = Game.spawnOrigin(seed: gen.seed)
            guard simd_length(V2(Float(cx0 * CS + 8 - o.0), Float(cz0 * CS + 8 - o.1))) >= 300 else { return nil }
            // The region's chunk, or one near it, on a coast that drops into deep water.
            for dz in stride(from: -4, through: 4, by: 2) { for dx in stride(from: -4, through: 4, by: 2) {
                let x = (cx0 + dx) * CS + 8, z = (cz0 + dz) * CS + 8
                guard let (fx, fz) = coast(gen, x, z) else { continue }
                if crowded(gen, x, z) { return nil }
                let f = Frame(x: x, z: z, fx: fx, fz: fz)
                let q = SEA + 2
                var lo = IVec3(Int.max, q - 24, Int.max), hi = IVec3(Int.min, q + 14, Int.min)
                for (u, v) in [(-13, -19), (13, -19), (-13, 31), (13, 31)] {
                    let (wx, wz) = f.p(u, v)
                    lo.x = min(lo.x, wx); lo.z = min(lo.z, wz); hi.x = max(hi.x, wx); hi.z = max(hi.z, wz)
                }
                let (ax, az) = f.p(0, -6)
                let st = StructureStart(kind: kind, pieces: [Piece(min: lo, max: hi) { w in build(&w, f, q, seed) }], anchor: IVec3(ax, q + 1, az))
                st.info = ["fx": fx, "fz": fz, "q": q, "x": x, "z": z]
                return st
            } }
            return nil
        }
    }

    // The seaward direction from (x, z) when it is low shore with land behind and deep water ahead; nil otherwise.
    static func coast(_ gen: WorldGen, _ x: Int, _ z: Int) -> (Int, Int)? {
        let c0 = gen.column(x, z)
        guard c0.height > SEA && c0.height <= SEA + 5, !c0.biome.isOcean, c0.biome != .river, c0.biome != .frozenRiver else { return nil }
        for (fx, fz) in [(0, 1), (1, 0), (0, -1), (-1, 0)] {
            let f = Frame(x: x, z: z, fx: fx, fz: fz)
            var ok = true
            for (u, v) in [(0, 10), (0, 18), (0, 26), (-4, 26), (4, 26)] {
                let (wx, wz) = f.p(u, v)
                if gen.column(wx, wz).height >= SEA - 3 { ok = false; break }
            }
            guard ok else { continue }
            for (u, v) in [(0, -8), (0, -16), (-11, -12), (11, -12), (-11, -4), (11, -4)] {
                let (wx, wz) = f.p(u, v)
                let h = gen.column(wx, wz).height
                if h <= SEA || h > SEA + 8 { ok = false; break }
            }
            if ok { return (fx, fz) }
        }
        return nil
    }

    // Older finds near the spot keep it.
    static func crowded(_ gen: WorldGen, _ x: Int, _ z: Int) -> Bool {
        guard let sc = gen.structures else { return false }
        let keep: [(String, Int)] = [("village", 96), ("military_base", 170), ("capital_city", 240), ("boreal_station", 80),
                                     (Greywall.kind, 120), ("temple", 48), ("wild_camp", 48), ("shipwreck", 40)]
        for (k, m) in keep {
            guard let o = sc.nearest(k, x: x, z: z, maxRegions: 1) else { continue }
            if o.max.x >= x - m && o.min.x <= x + m && o.max.z >= z - m && o.min.z <= z + m { return true }
        }
        return false
    }

    // MARK: Building

    static func build(_ w: inout StructWriter, _ f: Frame, _ q: Int, _ seed: UInt64) {
        var rng = SRng(seed &+ 0xD0C4)
        let brick = b("stone_bricks", "cobblestone"), cobble = b("cobblestone", "stone"), plank = b("spruce_planks", "oak_planks")
        let log = b("spruce_log", "oak_log"), fence = b("spruce_fence", "oak_fence"), slab = b("spruce_slab", "oak_slab")
        let dark = b("dark_oak_planks", "oak_planks"), lantern = b("lantern", "torch")
        func S(_ u: Int, _ dy: Int, _ v: Int, _ bl: BlockID) { let (x, z) = f.p(u, v); w.set(x, q + dy, z, bl) }
        func down(_ u: Int, _ dy: Int, _ v: Int, _ bl: BlockID) { let (x, z) = f.p(u, v); w.groundDown(x, q + dy, z, bl, minY: q - 20) }

        // The yard: paved, filled under, cleared above.
        for v in -18...(-1) { for u in -12...12 {
            down(u, -1, v, cobble)
            S(u, 0, v, (u + v) % 7 == 0 ? cobble : brick)
            for dy in 1...12 { S(u, dy, v, AIR) }
        } }
        // The quay wall, down into the water, a coping of bricks.
        for v in 0...2 { for u in -12...12 {
            down(u, -1, v, brick)
            S(u, 0, v, brick)
            for dy in 1...12 { S(u, dy, v, AIR) }
        } }
        // Bollards along the quay edge.
        for u in stride(from: -11, through: 11, by: 4) where abs(u) > 4 { S(u, 1, 2, log) }
        // The pier: a plank deck on log piles, rails with lanterns.
        for v in 3...28 { for u in -3...3 {
            S(u, 0, v, abs(u) == 3 ? dark : plank)
            for dy in 1...6 { S(u, dy, v, AIR) }
            if abs(u) == 3 && v % 4 == 3 { down(u, -1, v, log) }
            if abs(u) == 3 && v % 6 != 0 { S(u, 1, v, fence) }
        } }
        for v in stride(from: 6, through: 24, by: 6) { S(-3, 1, v, fence); S(-3, 2, v, lantern); S(3, 1, v, fence); S(3, 2, v, lantern) }
        for u in -3...3 { down(u, -1, 28, log) }

        // Storehouses, one each side: stone walls five high, a plank roof, the door facing the quay.
        for side in [-1, 1] {
            let u0 = side < 0 ? -11 : 5, u1 = side < 0 ? -5 : 11
            for v in -16...(-8) { for u in u0...u1 {
                let wall = u == u0 || u == u1 || v == -16 || v == -8
                if wall { for dy in 1...5 { S(u, dy, v, (u == u0 || u == u1) && (v == -16 || v == -8) ? log : brick) } }
                S(u, 6, v, plank)
                S(u, 0, v, plank)
            } }
            let door = (u0 + u1) / 2
            S(door, 1, -8, AIR); S(door, 2, -8, AIR)
            S(door, 4, -9, lantern)
            for (k, u) in [u0 + 1, u1 - 1].enumerated() {
                let (x, z) = f.p(u, -15)
                w.chest(x, q + 1, z, loot: "port_stores", seed: rng.next() &+ UInt64(k))
            }
            for u in (u0 + 2)...(u1 - 2) where rng.chance(0.5) { S(u, 1, -15, b("barrel", "oak_planks")) }
        }
        // The harbour office: plank walls under a slab roof, a window on the quay, the strongbox in the back.
        for v in -17...(-11) { for u in -3...3 {
            let wall = abs(u) == 3 || v == -17 || v == -11
            if wall { for dy in 1...4 { S(u, dy, v, abs(u) == 3 && (v == -17 || v == -11) ? log : plank) } }
            S(u, 5, v, slab)
            S(u, 0, v, dark)
        } }
        S(0, 1, -11, AIR); S(0, 2, -11, AIR)
        if Blocks.has("glass_pane") { S(-2, 2, -11, Blocks.id("glass_pane")); S(2, 2, -11, Blocks.id("glass_pane")) }
        S(0, 4, -14, lantern)
        if Blocks.has("crafting_table") { S(-2, 1, -16, Blocks.id("crafting_table")) }
        let (sx, sz) = f.p(2, -16)
        w.chest(sx, q + 1, sz, loot: "port_armory", seed: rng.next())

        // The crane on the quay: a log mast, a jib out over the water, a rope of fence posts.
        S(-8, 1, 1, cobble)
        for dy in 2...9 { S(-8, dy, 1, log) }
        for v in 1...6 { S(-8, 10, v, plank) }
        for dy in 6...9 { S(-8, dy, 6, fence) }
        // Lamps on the yard.
        for u in [-12, 12] { S(u, 1, -1, fence); S(u, 2, -1, lantern) }
    }

    // MARK: The garrison and the office (TownLaw.tick, once a second)

    static func key(_ a: IVec3) -> String { "\(a.x),\(a.z)" }
    static func taken(_ a: IVec3) -> Bool { TownLaw.state.portsTaken?.contains(key(a)) ?? false }

    static func ports(_ g: Game, near p: V3) -> [StructureStart] {
        guard let sc = g.world.gen.structures, let t = sc.types.first(where: { $0.name == kind }) else { return [] }
        return sc.startsNear(cx: floorDiv(Int(floor(p.x)), CS), cz: floorDiv(Int(floor(p.z)), CS), t)
    }

    // The office's door step inside, in the world.
    static func office(_ s: StructureStart) -> V3? {
        guard let fx = s.info["fx"], let fz = s.info["fz"], let q = s.info["q"], let x = s.info["x"], let z = s.info["z"] else { return nil }
        let (ox, oz) = Frame(x: x, z: z, fx: fx, fz: fz).p(0, -14)
        return V3(Float(ox) + 0.5, Float(q + 1), Float(oz) + 0.5)
    }
    // Deep water off the pier's end (where a hull is launched and a vessel to repair lies), and the yaw to face the sea.
    static func berth(_ s: StructureStart) -> (V3, Float)? {
        guard let fx = s.info["fx"], let fz = s.info["fz"], let x = s.info["x"], let z = s.info["z"] else { return nil }
        let (bx, bz) = Frame(x: x, z: z, fx: fx, fz: fz).p(0, 36)
        return (V3(Float(bx) + 0.5, Float(SEA + 1), Float(bz) + 0.5), atan2f(Float(-fx), Float(-fz)))
    }

    static func marines(_ g: Game, _ s: StructureStart) -> [Mob] {
        let c = V3(Float(s.anchor.x), Float(s.anchor.y), Float(s.anchor.z))
        return g.mobs.mobs.filter { $0.customName == marine && $0.health > 0 && simd_length($0.pos - c) < 80 }
    }

    // Whether the harbourmaster deals with you: an ally of the Navy, or the port's garrison is gone.
    static func open(_ g: Game, _ s: StructureStart) -> Bool {
        FactionRep.of(.meridian) >= FactionRep.allyAt || marines(g, s).isEmpty
    }

    static func tick(_ g: Game) {
        guard g.dim.dim == .overworld else { return }
        let p = g.player.pos
        for s in ports(g, near: p) {
            let a = s.anchor
            guard simd_length(V2(p.x - Float(a.x), p.z - Float(a.z))) < showUp, g.world.isLoaded(a.x, a.z), let off = office(s) else {
                seen[a] = nil; continue
            }
            seen[a, default: 0] += 1
            let met = spawnedHere.contains(a) || (TownLaw.state.portsMet?.contains(key(a)) ?? false)
            if !met {
                spawnedHere.insert(a)
                var m = TownLaw.state.portsMet ?? []; m.append(key(a)); TownLaw.state.portsMet = m
                MapCache.shared.discover(g, kind: kind, x: a.x, z: a.z, name: "Meridian dockyard")
                if g.survival && g.difficulty > 0 { garrison(g, s) }
                g.onToast?(FactionRep.of(.meridian) >= FactionRep.allyAt ? "A Meridian Navy dockyard. The harbourmaster deals with friends of the Navy."
                                                                          : "A Meridian Navy dockyard, its marines on guard. Clear them and the harbour is yours to deal with.")
            } else if !taken(a), seen[a, default: 0] >= 5, marines(g, s).isEmpty, g.survival {
                var t = TownLaw.state.portsTaken ?? []; t.append(key(a)); TownLaw.state.portsTaken = t
                g.sfx(.levelUp, 0.7)
                g.onToast?("The dockyard's garrison is gone. The harbourmaster will deal with you now.")
            }
            // The harbourmaster in his office.
            if !g.mobs.mobs.contains(where: { isHarbourmaster($0) && $0.health > 0 && simd_length($0.pos - off) < 40 }) {
                let m = Mob(.villager, at: g.world.freeSpawn(off))
                Townsfolk.setup(m, tag: "camper", game: g)
                if var v = m.villager { v.role = "harbourmaster"; m.villager = v }
                m.persistent = true
                m.home = m.pos
                g.mobs.mobs.append(m)
            }
        }
    }

    static func garrison(_ g: Game, _ s: StructureStart) {
        guard let fx = s.info["fx"], let fz = s.info["fz"], let q = s.info["q"], let x = s.info["x"], let z = s.info["z"] else { return }
        let f = Frame(x: x, z: z, fx: fx, fz: fz)
        let posts: [(Int, Int, MobKind)] = [(-6, -5, .soldierTrooper), (6, -5, .soldierTrooper), (0, -3, .soldierMarksman),
                                            (-8, -10, .soldierTrooper), (0, 14, .soldierMarksman), (0, 24, .soldierTrooper)]
        for (u, v, k) in posts {
            let (px, pz) = f.p(u, v)
            let m = Mob(k, at: g.world.freeSpawn(V3(Float(px) + 0.5, Float(q + 1), Float(pz) + 0.5)))
            m.faction = Faction.meridian.rawValue
            if k == .soldierTrooper { m.variant = Guns.rifle }
            m.customName = marine
            m.persistent = true
            m.home = m.pos
            g.mobs.mobs.append(m)
            if m.troop < 0 { m.troop = 0 }
            m.soldierBrain.mag = Guns.all[m.soldierBrain.gun].mag
        }
    }

    static func isHarbourmaster(_ m: Mob) -> Bool { m.kind == .villager && m.villager?.role == "harbourmaster" }

    // talkToTownsperson: the harbourmaster's book.
    static func talk(_ g: Game, _ m: Mob) -> Bool {
        guard isHarbourmaster(m) else { return false }
        guard let s = ports(g, near: m.pos).min(by: { simd_length($0.anchorV - m.pos) < simd_length($1.anchorV - m.pos) }) else {
            Townsfolk.say(g, m, "No ships to deal in here, friend."); return true
        }
        guard open(g, s) else {
            Townsfolk.say(g, m, ["The Navy's yard doesn't deal with the likes of you.", "Marines! We've a visitor.", "Off my quay."][Int(g.clock) % 3])
            return true
        }
        g.openMenu(HarbourMenu(game: g, port: s))
        return true
    }

    // MARK: The book

    struct Offer { let name: String; let detail: String; let price: Int }
    static let offers: [Offer] = [
        Offer(name: "Sloop Hull", detail: "A sound sloop, launched off the pier's end", price: 30000),
        Offer(name: "Submarine Kit", detail: "Build a submarine where you like", price: 40000),
        Offer(name: "Sky Skiff Kit", detail: "A small airship, crated", price: 35000),
        Offer(name: "Ship Cannon", detail: "One cannon for your own hull", price: 6000),
        Offer(name: "Ship Engine", detail: "One engine for your own hull", price: 4000),
    ]
    static let chipPrice = 150, repairMin = 1000
    static let hullRole = "hull"                         // a hull bought here: no faction, no crew orders

    // Your vessel lying near the port: the nearest hull you have taken, built or bought.
    static func yourVessel(_ g: Game, _ s: StructureStart) -> Ship? {
        let c = berth(s)?.0 ?? s.anchorV
        let ships = g.world.ships
        return ships.list.filter { sh in
            sh.parent == nil && (sh.captured || (sh.factionValue == .none && (sh.role == nil || sh.role == hullRole || sh === ships.pilot)))
                && simd_length(sh.pos - c) < 70
        }.min { simd_length($0.pos - c) < simd_length($1.pos - c) }
    }

    static func repairCost(_ s: Ship) -> Int { max(repairMin, s.damage.count * chipPrice) }
    static func needsRepair(_ s: Ship) -> Bool { !s.damage.isEmpty || (s.wrecked && s.helm != nil) }

    static func repair(_ g: Game, _ s: StructureStart) -> (String, Bool) {
        guard let v = yourVessel(g, s) else { return ("Bring your vessel alongside the pier and I'll see to her.", false) }
        guard needsRepair(v) else { return ("The \(v.name) is sound. Nothing for the shipwrights.", false) }
        let cost = repairCost(v)
        guard g.money >= cost else { return ("That's \(Money.format(cost)) of work. You have \(Money.format(g.money)).", false) }
        g.money -= cost
        let cells = Array(v.damage.keys)
        v.damage.removeAll()
        if !cells.isEmpty { v.mesh.rebuildAround(v, cells, device: g.world.device, queue: g.world.ships.meshQueue) }
        if v.wrecked && v.helm != nil { v.wrecked = false; v.initialBlocks = v.blockCount }
        repaired += 1
        g.sfx(.anvil, 0.6)
        return ("The shipwrights have made the \(v.name) good.", true)
    }

    static func buy(_ g: Game, _ s: StructureStart, _ i: Int) -> (String, Bool) {
        let o = offers[i]
        guard g.money >= o.price else { return ("That's \(Money.format(o.price)). You have \(Money.format(g.money)).", false) }
        let r: (String, Bool)
        switch i {
        case 0:
            guard let (at, yaw) = berth(s) else { return ("There's no berth here.", false) }
            if g.world.ships.list.contains(where: { simd_length($0.pos - at) < 9 }) { return ("Clear the berth off the pier first.", false) }
            g.world.ships.spawn(Corsairs.sloop(), at: at, yaw: yaw, name: "Sloop", role: hullRole)
            r = ("Your sloop is afloat off the pier's end. She's yours.", true)
        case 1: r = Quartermaster.give(g, [(Submarine.kitKey, 1)])
        case 2: r = Quartermaster.give(g, [(SkySkiff.key, 1)])
        case 3: r = Quartermaster.give(g, [("ship_cannon", 1)])
        default: r = Quartermaster.give(g, [("ship_engine", 1)])
        }
        if r.1 { g.money -= o.price; bought += 1; g.sfx(.villagerTrade, 0.7) }
        return r
    }
}

extension StructureStart {
    var anchorV: V3 { V3(Float(anchor.x) + 0.5, Float(anchor.y), Float(anchor.z) + 0.5) }
}

final class HarbourMenu: ListMenu {
    let port: StructureStart
    init(game g: Game, port: StructureStart) {
        self.port = port
        super.init("Harbourmaster", game: g)
        subtitle = "Hulls, kits and the shipwrights"
    }
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        var out: [Row] = []
        if let v = NavalPort.yourVessel(game, port) {
            let need = NavalPort.needsRepair(v)
            let cost = NavalPort.repairCost(v)
            out.append(Row(name: "Repair the \(v.name)", detail: need ? "\(v.damage.count) damaged blocks made good" : "Her hull is sound",
                           value: need ? Money.format(cost) : "", enabled: need && game.money >= cost, good: need))
        } else {
            out.append(Row(name: "Repair a vessel", detail: "Bring yours alongside the pier", value: "", enabled: false, good: false))
        }
        for o in NavalPort.offers {
            out.append(Row(name: o.name, detail: o.detail, value: Money.format(o.price), enabled: game.money >= o.price, good: true))
        }
        return out
    }
    override func pressed(_ i: Int) {
        let r = i == 0 ? NavalPort.repair(game, port) : (i - 1 < NavalPort.offers.count ? NavalPort.buy(game, port, i - 1) : ("", false))
        if !r.0.isEmpty { say(r.0, good: r.1) }
    }
}
