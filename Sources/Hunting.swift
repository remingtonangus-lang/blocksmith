import Foundation
import simd

// Hunting (backlog B3, docs/status/hunting.md): game animals have a pelt quality (poor, good, perfect) you can study
// down the sights; a clean kill with the right weapon keeps it; the body stays where it fell and you skin it by holding
// use on it; pelts sell to the butcher by quality and craft into fur, satchels and saddles. Four legendary animals
// den at seeded spots (a Hunter's Map from the butcher marks them). Fishing catches are species with weights
// (Fishing.swift).

enum GameSize: Int { case small, medium, large }

// The weapon class of a hit, from what the player held when it landed.
enum HuntWeapon: Int {
    case none, arrow, pistol, rifle, shotgun, heavy, spear, melee

    static func of(_ s: ItemStack) -> HuntWeapon {
        let k = Items.key(s.item)
        switch k {
        case "bow", "crossbow": return .arrow
        case "gun_sidearm", "gun_revolver", "gun_smg": return .pistol
        case "gun_rifle", "gun_sniper": return .rifle
        case "gun_shotgun": return .shotgun
        case "gun_launcher", "gun_arc": return .heavy
        case "trident": return .spear
        default: return k.hasSuffix("_spear") ? .spear : .melee
        }
    }
    // Quality steps lost for this weapon on game of a size (0 = the right tool).
    func loss(_ s: GameSize) -> Int {
        switch (self, s) {
        case (.arrow, _), (.rifle, .medium), (.pistol, .small), (.pistol, .medium), (.spear, .medium), (.rifle, .large): return 0
        case (.heavy, .small), (.heavy, .medium), (.shotgun, .small), (.none, _): return 2
        default: return 1
        }
    }
}

struct GameAnimal {
    let kind: MobKind
    let key: String            // item keys: "<key>_pelt_poor" ...
    let name: String
    let pelt: String           // "Fox Pelt"
    let size: GameSize
    let hits: Int              // hits a clean kill takes at most
    let meat: String
    let trophy: String?, trophyChance: Float
    let value: Int             // a good pelt, in cents
    let color: UInt32
    var stack: Int { size == .small ? 16 : (size == .medium ? 8 : 4) }
    var skinTime: Float { size == .small ? 0.8 : (size == .medium ? 1.2 : 1.8) }
    var tools: String { size == .small ? "bow or a pistol" : (size == .medium ? "bow, pistol or rifle" : "bow, rifle or the Farsight") }
}

struct Legend {
    let name: String           // "the Ashen Wolf"
    let kind: MobKind
    let scale: Float
    let health: Int
    let habitat: Set<Biome>
    let pelt: String, peltName: String
    let trophy: String, trophyName: String
    let mask: String           // trophy sprite
    let color: UInt32
}

enum Hunting {
    static let animals: [GameAnimal] = [
        GameAnimal(kind: .rabbit, key: "rabbit", name: "Rabbit", pelt: "Rabbit Pelt", size: .small, hits: 1, meat: "rabbit",
                   trophy: "rabbit_foot", trophyChance: 0.1, value: 30, color: 0xC8A078),
        GameAnimal(kind: .fox, key: "fox", name: "Fox", pelt: "Fox Pelt", size: .small, hits: 2, meat: "game_meat",
                   trophy: nil, trophyChance: 0, value: 90, color: 0xD87A30),
        GameAnimal(kind: .wolf, key: "wolf", name: "Wolf", pelt: "Wolf Pelt", size: .medium, hits: 2, meat: "game_meat",
                   trophy: "wolf_fang", trophyChance: 0.35, value: 140, color: 0x9A9890),
        GameAnimal(kind: .goat, key: "goat", name: "Goat", pelt: "Goat Hide", size: .medium, hits: 2, meat: "game_meat",
                   trophy: nil, trophyChance: 0, value: 80, color: 0xD8D0C0),
        GameAnimal(kind: .polarBear, key: "bear", name: "Bear", pelt: "Bear Pelt", size: .large, hits: 5, meat: "game_meat",
                   trophy: "bear_claw", trophyChance: 0.5, value: 300, color: 0xE8E4D8),
    ]
    static let legends: [Legend] = [
        Legend(name: "the Ashen Wolf", kind: .wolf, scale: 1.6, health: 60,
               habitat: [.taiga, .snowyTaiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga, .grove, .forest],
               pelt: "legend_pelt_wolf", peltName: "Ashen Wolf Pelt", trophy: "ashen_fang", trophyName: "Ashen Fang", mask: "tear", color: 0x6A6A70),
        Legend(name: "Old Frostjaw", kind: .polarBear, scale: 1.4, health: 160,
               habitat: [.snowyPlains, .iceSpikes, .snowySlopes, .frozenPeaks, .snowyTaiga, .frozenRiver, .snowyBeach],
               pelt: "legend_pelt_bear", peltName: "Frostjaw Pelt", trophy: "frostjaw_claw", trophyName: "Frostjaw Claw", mask: "tear", color: 0xF4F4FA),
        Legend(name: "the Crag Ram", kind: .goat, scale: 1.5, health: 70,
               habitat: [.meadow, .grove, .snowySlopes, .jaggedPeaks, .stonyPeaks, .windsweptHills, .windsweptGravellyHills],
               pelt: "legend_pelt_goat", peltName: "Crag Ram Hide", trophy: "crag_horn", trophyName: "Crag Ram Horn", mask: "horn", color: 0x8A8070),
        Legend(name: "the Ember Fox", kind: .fox, scale: 1.4, health: 40,
               habitat: [.taiga, .snowyTaiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga, .grove, .windsweptForest],
               pelt: "legend_pelt_fox", peltName: "Ember Fox Pelt", trophy: "ember_tail", trophyName: "Ember Fox Tail", mask: "feather", color: 0xE85A18),
    ]
    static let words = ["", "Poor", "Good", "Perfect"]
    static let stars = ["", "*", "**", "***"]
    static let valueMult: [Float] = [0, 0.3, 1, 2.5]
    static let legendValue = 2500                           // a legendary pelt, cents
    static let bodyTime: Double = 180                        // a carcass lies this long
    static let maxBodies = 12

    static func animal(_ k: MobKind) -> GameAnimal? {
        switch k {
        case .rabbit: return animals[0]
        case .fox: return animals[1]
        case .wolf: return animals[2]
        case .goat: return animals[3]
        case .polarBear: return animals[4]
        default: return nil
        }
    }
    static func peltKey(_ a: GameAnimal, _ q: Int) -> String { "\(a.key)_pelt_\(words[max(1, min(3, q))].lowercased())" }
    static func peltColor(_ a: GameAnimal, _ q: Int) -> UInt32 {
        // Poor pelts are dull and dark, perfect ones a touch richer.
        let k: Float = q == 1 ? 0.72 : (q == 3 ? 1.08 : 1)
        func ch(_ s: Int) -> UInt32 { UInt32(min(255, Float((a.color >> UInt32(s)) & 0xFF) * k)) << UInt32(s) }
        return ch(16) | ch(8) | ch(0)
    }
    // Sale values for the shop table (Economy.value merges these).
    static let values: [String: Int] = {
        var v: [String: Int] = ["game_meat": 24, "cooked_game_meat": 40, "wolf_fang": 60, "bear_claw": 120, "hunters_map": 4000,
                                "perch": 12, "trout": 24, "pike": 30, "catfish": 26, "cooked_fish": 30, "pufferfish": 15, "tropical_fish": 20,
                                "fur_helmet": 500, "fur_chestplate": 800, "fur_leggings": 700, "fur_boots": 400,
                                "hunters_satchel": 1500, "legend_satchel": 6000]
        for a in animals { for q in 1...3 { v[peltKey(a, q)] = max(1, Int(Float(a.value) * valueMult[q])) } }
        for l in legends { v[l.pelt] = legendValue; v[l.trophy] = 1500 }
        return v
    }()
    static let pelts: [String] = animals.flatMap { a in (1...3).map { peltKey(a, $0) } }
    static let buys: [String] = pelts + legends.flatMap { [$0.pelt, $0.trophy] } + ["game_meat", "wolf_fang", "bear_claw", "perch", "trout", "pike", "catfish"]

    // MARK: Quality

    // Wild adult game you can hunt (a tamed wolf, a baby, a named pet are not game; legends are).
    static func isGame(_ m: Mob) -> Bool {
        animal(m.kind) != nil && !m.baby && m.owner == nil && !m.carcass && m.health > 0 && (m.customName == nil || m.legend >= 0)
    }
    static func quality(_ m: Mob) -> Int {
        if m.legend >= 0 { return 3 }
        if m.peltQ == 0 {
            let r = Rand.float(in: 0..<1)
            m.peltQ = r < 0.3 ? 1 : (r < 0.8 ? 2 : 3)
        }
        return Int(m.peltQ)
    }

    // A hit of the player's on an animal (Mob.provoke: melee, arrows, bullets, spears).
    static func hit(_ g: Game, _ m: Mob) {
        guard let a = animal(m.kind), !m.carcass else { return }
        _ = quality(m)
        m.huntHits = m.huntHits < 250 ? m.huntHits + 1 : m.huntHits
        m.huntLoss = max(m.huntLoss, UInt8(HuntWeapon.of(g.held).loss(a.size)))
        lastWeapon = HuntWeapon.of(g.held)
    }
    static var lastWeapon: HuntWeapon = .none

    // Quality left after the kill.
    static func kept(_ m: Mob) -> Int {
        guard let a = animal(m.kind) else { return 1 }
        if m.legend >= 0 { return 3 }
        if m.huntHits == 0 { return 1 }                                   // nothing of yours landed: blasts, fire, falls
        let allow = a.hits
        let extra = Int(m.huntHits) > 2 * allow ? 2 : (Int(m.huntHits) > allow ? 1 : 0)
        return max(1, quality(m) - Int(m.huntLoss) - extra)
    }

    // MARK: Bodies

    struct Body { let mob: Mob; let quality: Int; let legend: Int; let until: Double; let dim: Dim }
    static var bodies: [Body] = []
    static var bodyMobs: [Mob] = []                    // those in this dimension, for the renderer (no array built per frame)
    static func refresh(_ g: Game) { bodyMobs = bodies.filter { $0.dim == g.world.dim }.map { $0.mob } }
    static var skinned = 0, carcasses = 0, legendsKilled = 0       // counters (HuntingTests)

    // Game.mobDied: a game animal you killed leaves its body (no loot yet). True when it did.
    static func died(_ g: Game, _ m: Mob) -> Bool {
        guard animal(m.kind) != nil, m.killedByPlayer, !m.baby, m.owner == nil, !m.carcass,
              m.customName == nil || m.legend >= 0 else { return false }
        let q = kept(m)
        let b = Mob(m.kind, at: m.pos)
        b.carcass = true
        b.yaw = m.yaw
        b.variant = m.variant
        b.scale = m.scale
        b.legend = m.legend
        b.health = 1
        // Down to the ground (a body shot off a ledge lies where it lands).
        var y = m.pos.y
        let bx = Int(floor(m.pos.x)), bz = Int(floor(m.pos.z))
        for _ in 0..<24 where !Blocks.collide[Int(g.world.block(bx, Int(floor(y - 0.05)), bz))] && y > 1 { y -= 1 }
        b.pos.y = Blocks.collide[Int(g.world.block(bx, Int(floor(y - 0.05)), bz))] ? floor(y - 0.05) + 1 : y
        if m.legend >= 0 {
            legendsKilled += 1                               // gone for good once skinned (or its body's loot dropped)
            g.onToast?("You brought down \(legends[Int(m.legend)].name)")
            g.sfx(.goatHorn, 0.6, at: m.pos)
        }
        if bodies.count >= maxBodies { bodies.removeFirst() }
        bodies.append(Body(mob: b, quality: q, legend: Int(m.legend), until: g.clock + bodyTime, dim: g.world.dim))
        refresh(g)
        carcasses += 1
        return true
    }

    static func body(_ g: Game, under eye: V3, _ look: V3, reach: Float = 3.5) -> Int? {
        var best: Int?, bestT = reach
        for (i, b) in bodies.enumerated() where b.dim == g.world.dim {
            let m = b.mob
            // Lying on its side: as wide as it is tall.
            let r = max(m.halfW, m.height * 0.5) + 0.15
            let mn = V3(m.pos.x - r, m.pos.y, m.pos.z - r), mx = V3(m.pos.x + r, m.pos.y + max(0.35, m.halfW * 2), m.pos.z + r)
            if let h = World.rayBox(eye, look, mn, mx), h.0 < bestT { bestT = h.0; best = i }
        }
        return best
    }

    // Skinning: hold use on a body. Progress is per body; looking away or letting go resets it.
    // Per seat (split-screen co-op skins on each side).
    static var skinningBy: [ObjectIdentifier?] = [nil, nil]
    static var progressBy: [Float] = [0, 0]
    static var needBy: [Float] = [1, 1]
    static func seat(_ g: Game) -> Int { g.coop.active ? min(1, max(0, g.coop.current)) : 0 }
    static var skinProgress: Float { progressBy[0] }

    // What a skinned body gives.
    static func yield(_ b: Body) -> [ItemStack] {
        guard let a = animal(b.mob.kind) else { return [] }
        var out: [ItemStack] = []
        func add(_ k: String, _ n: Int) { if n > 0 && Items.has(k) { out.append(ItemStack(Items.id(k), n)) } }
        if b.legend >= 0 {
            let l = legends[b.legend]
            add(l.pelt, 1); add(l.trophy, 1); add(a.meat, 4)
            return out
        }
        add(peltKey(a, b.quality), 1)
        add(a.meat, b.quality)
        if let t = a.trophy, Rand.float(in: 0..<1) < a.trophyChance * (b.quality == 3 ? 1.5 : 1) { add(t, 1) }
        return out
    }

    // MARK: Per-second upkeep (bodies expire, legends at their dens)

    static var lastTick: Double = -10
    static func tick(_ g: Game) {
        guard g.clock - lastTick >= 1 || g.clock < lastTick else { return }      // (a new Game's clock starts at 0)
        lastTick = g.clock
        // A world of its own: a new world starts clean (a saved one loads its state in Game.loadExtra).
        if state.seed == nil { state.seed = g.world.seed } else if state.seed != g.world.seed { reset(); state.seed = g.world.seed }
        let p = g.player.pos
        // Bodies go after 3 minutes, or once you're 160 blocks off, in their own dimension. A legend's body leaves its
        // pelt and trophy on the ground rather than vanish (a legend is gone for good once its loot is out).
        var gone: [Body] = []
        bodies.removeAll { b in
            // A legend's body stays until its ground is loaded, so its loot lands somewhere real.
            let here = b.dim == g.world.dim && (b.legend < 0 || g.world.isLoaded(Int(floor(b.mob.pos.x)), Int(floor(b.mob.pos.z))))
            let out = here && (b.until < g.clock || (b.legend < 0 && simd_length(b.mob.pos - p) > 160))
            if out { gone.append(b) }
            return out
        }
        for b in gone where b.legend >= 0 {
            for s in yield(b) { g.drops.spawn(s, at: b.mob.pos + V3(0, 0.5, 0)) }
            state.killed.insert(b.legend)
        }
        refresh(g)
        guard g.world.dim == .overworld else { return }
        legendTick(g)
    }

    // MARK: Saved state (world extra "hunting")

    struct Saved: Codable {
        var killed = Set<Int>()
        var revealed = Set<Int>()
        var dens: [[Int]]? = nil
        var records: [String: Float] = [:]           // heaviest fish per species, lb
        var caught: [String: Int]? = nil            // fish landed per species
        var seed: UInt64? = nil                     // the world it belongs to
    }
    static var state = Saved()
    static func save(_ d: inout [String: String]) {
        if let e = try? JSONEncoder().encode(state), let s = String(data: e, encoding: .utf8) { d["hunting"] = s }
    }
    static func load(_ d: [String: String]) {
        reset()
        if let s = d["hunting"], let data = s.data(using: .utf8), let st = try? JSONDecoder().decode(Saved.self, from: data) { state = st }
    }
    static func reset() {
        state = Saved(); bodies = []; bodyMobs = []; skinningBy = [nil, nil]; progressBy = [0, 0]; lastTick = -10
        denCache = nil; denSeed = nil; Fishing.reset()
    }

    // MARK: Legends

    static var denCache: [IVec3]?
    static var denSeed: UInt64?
    // Den columns: a seeded bearing and range (700-1600 blocks) from the world's centre, then the nearest column of a
    // fitting biome within 320 blocks (on a 64-block grid), else the seeded spot itself. Saved once found.
    static func dens(_ g: Game) -> [IVec3] {
        let seed = g.world.seed
        if let d = denCache, denSeed == seed { return d }
        if let s = state.dens, s.count == legends.count, s.allSatisfy({ $0.count == 2 }) {
            denCache = s.map { IVec3($0[0], 0, $0[1]) }; denSeed = seed
            return denCache!
        }
        var out: [IVec3] = []
        for (i, l) in legends.enumerated() {
            let ang = hashf(7_331 + i, 91, 17, UInt32(truncatingIfNeeded: seed ^ (seed >> 32))) * 2 * .pi
            let r: Float = 700 + 300 * Float(i)
            let cx = Int(cosf(ang) * r), cz = Int(sinf(ang) * r)
            var pick = IVec3(cx, 0, cz)
            search: for ring in 0...5 {
                let n = ring * 64
                for dz in stride(from: -n, through: n, by: 64) {
                    for dx in stride(from: -n, through: n, by: 64) where max(abs(dx), abs(dz)) == n {
                        if l.habitat.contains(g.world.gen.column(cx + dx, cz + dz).biome) { pick = IVec3(cx + dx, 0, cz + dz); break search }
                    }
                }
            }
            out.append(pick)
        }
        state.dens = out.map { [$0.x, $0.z] }
        denCache = out; denSeed = seed
        return out
    }

    static func live(_ g: Game, _ i: Int) -> Mob? { g.mobs.mobs.first { $0.legend == Int8(i) && $0.health > 0 } }

    static func legendTick(_ g: Game) {
        let p = g.player.pos
        let d = dens(g)
        for (i, l) in legends.enumerated() where !state.killed.contains(i) && !bodies.contains(where: { $0.legend == i }) {
            let den = d[i]
            let dx = Float(den.x) + 0.5 - p.x, dz = Float(den.z) + 0.5 - p.z
            let far = dx * dx + dz * dz
            if let m = live(g, i) {
                // It keeps to its den, and the hunters among them come for you.
                // Strayed far from its den with you well away: it's back there (out of sight).
                if simd_length(V2(m.pos.x - Float(den.x), m.pos.z - Float(den.z))) > 64 && simd_length(m.pos - p) > 40 && !m.aggro {
                    let y = g.world.topY(den.x, den.z)
                    if y > 0 { m.pos = V3(Float(den.x) + 0.5, Float(y + 1), Float(den.z) + 0.5); m.vel = .zero }
                }
                let near = g.survival && simd_length(m.pos - p) < (l.kind == .fox ? 20 : 14) && g.world.canSee(m.eye, g.player.eye)
                if near && l.kind == .fox { m.panic = max(m.panic, 3) }           // the Ember Fox runs
                else if near { m.aggro = true }
                continue
            }
            // Spawned when you come within 80 blocks and its den is loaded.
            guard far < 80 * 80, g.world.isLoaded(den.x, den.z) else { continue }
            let y = g.world.topY(den.x, den.z)
            guard y > 0 else { continue }
            spawnLegend(g, i, at: V3(Float(den.x) + 0.5, Float(y + 1), Float(den.z) + 0.5))
        }
    }

    @discardableResult
    static func spawnLegend(_ g: Game, _ i: Int, at: V3) -> Mob {
        let l = legends[i]
        let m = Mob(l.kind, at: at)
        m.legend = Int8(i)
        m.scale = l.scale
        m.health = l.health
        m.customName = l.name.prefix(4) == "the " ? String(l.name.dropFirst(4)).capitalizedFirst : l.name
        m.peltQ = 3
        g.mobs.mobs.append(m)
        return m
    }

    // A Hunter's Map: marks the next legend's den you haven't been shown (and haven't killed).
    static func readMap(_ g: Game) -> Bool {
        guard g.world.dim == .overworld else { g.onToast?("This map only charts the land above"); return false }
        let d = dens(g)
        guard let i = legends.indices.first(where: { !state.revealed.contains($0) && !state.killed.contains($0) }) else {
            g.onToast?("This map shows nothing you haven't hunted"); return false
        }
        state.revealed.insert(i)
        MapCache.shared.discover(g, kind: "legend", x: d[i].x, z: d[i].z, name: "\(legends[i].name.capitalizedFirst)'s den")
        return true
    }

    // MARK: Study line (the crosshair line, like the townsfolk glance: steady aim 0.4 s, lingers 0.5 s)

    static let settle: Double = 0.4, hold: Double = 0.5
    static weak var aimed: Mob?
    static var aimedSince: Double = 0
    static weak var shown: Mob?
    static var shownUntil: Double = 0

    static func lookedAt(_ g: Game) -> Mob? {
        let eye = g.player.eye, look = g.player.look
        let range: Float = (g.fovScale < 0.5 && Items.key(g.held.item) == "spyglass") ? 96 : 32
        var best: Mob?, bestDot: Float = 0.994
        for m in g.mobs.mobs where isGame(m) {
            let c = m.pos + V3(0, m.height * 0.5, 0)
            let d = c - eye
            let l = simd_length(d)
            guard l > 0.5, l < range else { continue }
            // Small game is a small target: allow a little more off-centre up close.
            let dot = simd_dot(d / l, look) + min(0.004, m.halfW / l * 0.02)
            if dot > bestDot { bestDot = dot; best = m }
        }
        guard let b = best, g.world.canSee(eye, b.pos + V3(0, b.height * 0.6, 0)) else { return nil }
        return b
    }

    static func current(_ g: Game, now: Double? = nil) -> Mob? {
        let t = now ?? g.clock
        let m = lookedAt(g)
        if m !== aimed { aimed = m; aimedSince = t }
        if let m, t - aimedSince >= settle { shown = m; shownUntil = t + hold }
        guard let s = shown, s.health > 0, t <= shownUntil else { shown = nil; return nil }
        return s
    }

    static func describe(_ m: Mob) -> String {
        guard let a = animal(m.kind) else { return "" }
        if m.legend >= 0 { return "\(legends[Int(m.legend)].name.capitalizedFirst): legendary" }
        let q = quality(m)
        return "\(a.name): \(words[q].lowercased()) \(stars[q]) (\(a.tools))"
    }

    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        guard HudExtras.enabled, !g.hideHUD, g.menu == nil, g.alive, !Turrets.shared.active, !WeaponWheel.shared.open else { return [] }
        let s = L.s
        var out: [HudLine] = []
        if let a = actionLines(g, L) { return a }
        guard Tutorial.ownSeat(g), let m = current(g) else { return [] }
        let t = describe(m)
        let w = Float(Font.width(t)) * s
        let q = quality(m)
        let col = m.legend >= 0 ? V4(1, 0.6, 0.25, 1) : (q == 3 ? V4(1, 0.88, 0.4, 1) : (q == 2 ? V4(0.92, 0.92, 0.85, 1) : V4(0.75, 0.68, 0.6, 1)))
        out.append(HudLine(text: t, x: (L.W - w) / 2, y: L.H / 2 + 56 * s, scale: s, color: col, bg: V4(0, 0, 0, 0.5)))
        return out
    }

    // Skinning progress or the fish fight (any seat), in the line's place; ahead of a townsperson's glance.
    static func actionLines(_ g: Game, _ L: HudLayout) -> [HudLine]? {
        guard HudExtras.enabled, !g.hideHUD, g.menu == nil, g.alive, let t = skinLine(g) ?? Fishing.line(g) else { return nil }
        let s = L.s, w = Float(Font.width(t.0)) * s
        return [HudLine(text: t.0, x: (L.W - w) / 2, y: L.H / 2 + 56 * s, scale: s, color: t.1, bg: V4(0, 0, 0, 0.5))]
    }

    static func skinLine(_ g: Game) -> (String, V4)? {
        let i = seat(g)
        guard skinningBy[i] != nil, progressBy[i] > 0 else { return nil }
        let n = 10, f = Int(min(1, progressBy[i] / max(0.1, needBy[i])) * Float(n))
        return ("Skinning " + String(repeating: "|", count: f) + String(repeating: ".", count: n - f), V4(0.95, 0.85, 0.75, 1))
    }
}

// MARK: Items

extension Hunting {
    static let furPieces: [(String, String, ArmorSlot, Int, Int)] = [("fur_helmet", "Fur Hood", .head, 2, 11), ("fur_chestplate", "Fur Coat", .chest, 4, 16),
                                                                    ("fur_leggings", "Fur Trousers", .legs, 3, 15), ("fur_boots", "Fur Boots", .feet, 1, 13)]
    static let satchels: [String: Int] = ["hunters_satchel": 256, "legend_satchel": 512]     // bundle room (a bundle holds 64)

    static func register(_ r: ItemRegistry) {
        func item(_ n: String, _ disp: String, _ mask: String, _ color: UInt32, stack: Int = 64, food: FoodInfo? = nil) {
            var d = ItemDef(n, disp)
            d.sprite = Sprite(mask: mask, base: color, extras: [:])
            d.maxStack = stack
            d.food = food
            r.add(d)
        }
        for a in animals { for q in 1...3 { item(peltKey(a, q), "\(words[q]) \(a.pelt)", "leather", peltColor(a, q), stack: a.stack) } }
        for l in legends {
            item(l.pelt, l.peltName, "leather", l.color, stack: 1)
            item(l.trophy, l.trophyName, l.mask, l.color, stack: 1)
        }
        item("wolf_fang", "Wolf Fang", "tear", 0xE8E0C8)
        item("bear_claw", "Bear Claw", "tear", 0x3A3430)
        item("game_meat", "Gamey Meat", "steak", 0xB83030, food: FoodInfo(hunger: 3, saturation: 1.8))
        item("cooked_game_meat", "Cooked Game Meat", "steak", 0x7A4228, food: FoodInfo(hunger: 8, saturation: 12.8))
        item("perch", "Yellow Perch", "fish", 0xC8B040, food: FoodInfo(hunger: 2, saturation: 0.4))
        item("trout", "Rainbow Trout", "fish", 0xA8B0A0, food: FoodInfo(hunger: 2, saturation: 0.4))
        item("pike", "Northern Pike", "fish", 0x6A8A4A, food: FoodInfo(hunger: 2, saturation: 0.4))
        item("catfish", "Channel Catfish", "fish", 0x7A7468, food: FoodInfo(hunger: 2, saturation: 0.4))
        item("cooked_fish", "Cooked Fish", "fish", 0xD8B888, food: FoodInfo(hunger: 6, saturation: 7.2))
        item("hunters_map", "Hunter's Map", "map", 0xB89868, stack: 1)
        item("hunters_satchel", "Hunter's Satchel", "bundle", 0x8A5A30, stack: 1)
        item("legend_satchel", "Legend's Satchel", "bundle", 0x5A4A3A, stack: 1)
        for (n, disp, slot, pts, dur) in furPieces {
            var d = ItemDef(n, disp)
            d.sprite = Sprite(mask: ["helmet", "chestplate", "leggings", "boots"][slot.rawValue], base: 0x8A6A4A, extras: [:])
            d.maxStack = 1
            d.armorSlot = slot
            d.armor = pts
            d.durability = dur * 9
            r.add(d)
        }
    }
    // Recipes (Recipes.build): fur from good or perfect pelts, satchels, a saddle.
    static func recipes() -> [Recipe?] {
        var out: [Recipe?] = []
        let fine = "#fine_pelts"
        out.append(Recipes.shaped(["PPP", "P P"], ["P": fine], "fur_helmet"))
        out.append(Recipes.shaped(["P P", "PPP", "PPP"], ["P": fine], "fur_chestplate"))
        out.append(Recipes.shaped(["PPP", "P P", "P P"], ["P": fine], "fur_leggings"))
        out.append(Recipes.shaped(["P P", "P P"], ["P": fine], "fur_boots"))
        out.append(Recipes.shaped(["SLS", "LPL", "LLL"], ["S": "string", "L": "leather", "P": "#perfect_pelts"], "hunters_satchel"))
        out.append(Recipes.shaped(["SLS", "LPL", "LLL"], ["S": "string", "L": "leather", "P": "#legend_pelts"], "legend_satchel"))
        out.append(Recipes.shaped(["LPL", "P P", "I I"], ["L": "leather", "P": fine, "I": "iron_ingot"], "saddle"))
        // A poor pelt is only good for leather.
        for a in animals { out.append(Recipes.shapeless([peltKey(a, 1)], "leather")) }
        return out
    }
    static var tags: [String: [String]] {
        ["fine_pelts": animals.flatMap { [peltKey($0, 2), peltKey($0, 3)] },
         "perfect_pelts": animals.map { peltKey($0, 3) },
         "legend_pelts": legends.map { $0.pelt }]
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension Game {
    // Holding use on a body you're aiming at skins it (before guns, which also take the use button to aim).
    func skinUse(_ useHeld: Bool, _ dt: Float) -> Bool {
        let seat = Hunting.seat(self)
        func stop() -> Bool { Hunting.skinningBy[seat] = nil; Hunting.progressBy[seat] = 0; return false }
        guard useHeld, !Hunting.bodies.isEmpty, let i = Hunting.body(self, under: player.eye, player.look) else { return stop() }
        let b = Hunting.bodies[i]
        // A block in the way (aiming past the body at a wall) wins only when it's nearer.
        if let t = target, let bt = World.rayBox(player.eye, player.look, b.mob.pos - V3(1, 0, 1), b.mob.pos + V3(1, 1, 1)),
           simd_length(V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5 - player.eye) + 0.5 < bt.0 { return stop() }
        let id = ObjectIdentifier(b.mob)
        if Hunting.skinningBy[seat] != id {
            Hunting.skinningBy[seat] = id; Hunting.progressBy[seat] = 0
            Hunting.needBy[seat] = b.legend >= 0 ? 2.4 : (Hunting.animal(b.mob.kind)?.skinTime ?? 1)
        }
        let before = Hunting.progressBy[seat]
        Hunting.progressBy[seat] += dt
        let progress = Hunting.progressBy[seat]
        swing = max(swing, 0.6)
        if Int(before / 0.3) != Int(progress / 0.3) {
            sfx(.shearsSnip, 0.5, at: b.mob.pos)
            particles.crit(at: b.mob.pos + V3(0, 0.3, 0))
            PadManager.shared.rumble(0.15, 0.05)
        }
        guard progress >= Hunting.needBy[seat] else { return true }
        // Done: the pelt, meat and any trophy go to your pack (what doesn't fit drops at your feet).
        let got = Hunting.yield(b)
        for s in got {
            let rest = inventory.add(s)
            if !rest.isEmpty { dropItem(rest, thrown: false) }
        }
        if let p = got.first { onToast?("Skinned: \(p.displayName)") }
        sfx(.pickup, 0.6)
        Hunting.bodies.remove(at: i)
        Hunting.refresh(self)
        if b.legend >= 0 { Hunting.state.killed.insert(b.legend) }
        Hunting.skinned += 1
        _ = stop()
        achieve("skin")
        return true
    }
}
