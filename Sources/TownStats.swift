import Foundation
import simd

// Townsfolk variety (backlog B2; docs/status/townsfolk-variety.md): every townsperson's toughness, speed, strength and
// attack rate come from their role and age, plus their own roll, so a farmer goes down fast and can't outrun you, a
// blacksmith hits like a hammer and takes a beating, and a deputy runs you down. Nothing is saved: the roll is
// seeded by the person's name and look, so the same person is always the same.
//   toughness: damage they take is divided by it (Mob.hit), so 20 health in a 1.4 body takes 28 to bring down.
//   speed:     their walk and run (Mob.update, villager case).
//   strength:  their melee damage (Mob.townDefend; the sheriff's six-iron doesn't care).
//   rate:      their swings per second (attack cooldown divided by it).
// What they show: a broader or slighter build in the model (TownsfolkModel), the tool for the trade they carry, and
// a line under the crosshair when you look at one ("Silas Ridley, blacksmith: strong, tough").
struct TownStats: Equatable {
    var toughness: Float = 1, speed: Float = 1, strength: Float = 1, rate: Float = 1

    // (toughness, speed, strength, rate) before the person's own roll.
    static func base(_ v: VillagerData?, baby: Bool) -> TownStats {
        guard let v, !baby else { return TownStats(toughness: 0.5, speed: 1.15, strength: 0.3, rate: 1) }
        switch v.role ?? "worker" {
        case "child": return TownStats(toughness: 0.5, speed: 1.15, strength: 0.3, rate: 1)
        case "elder": return TownStats(toughness: 0.65, speed: 0.7, strength: 0.55, rate: 0.75)
        case "farmer": return TownStats(toughness: 0.85, speed: 0.82, strength: 0.85, rate: 0.8)
        case "deputy": return TownStats(toughness: 1.25, speed: 1.3, strength: 1.1, rate: 1.25)
        case "sheriff": return TownStats(toughness: 1.5, speed: 1.15, strength: 1.2, rate: 1)
        case "citizen": return TownStats(toughness: 0.95, speed: 1, strength: 0.9, rate: 1)
        case "craftsman":
            return ["armorer", "toolsmith", "weaponsmith", "mason"].contains(v.profession)
                ? TownStats(toughness: 1.3, speed: 0.92, strength: 1.4, rate: 0.9) : TownStats(toughness: 1.05, speed: 1, strength: 1.05, rate: 1)
        case "shopkeeper":
            switch v.shopKind {
            case .blacksmith?: return TownStats(toughness: 1.45, speed: 0.9, strength: 1.55, rate: 0.9)
            case .butcher?: return TownStats(toughness: 1.25, speed: 0.95, strength: 1.3, rate: 1)
            case .stable?: return TownStats(toughness: 1.15, speed: 1.05, strength: 1.15, rate: 1)
            case .doctor?, .tailor?: return TownStats(toughness: 0.85, speed: 1, strength: 0.75, rate: 1)
            default: return TownStats()
            }
        default: return TownStats()
        }
    }

    // The person's own roll on top: +-12% on each (+-8% for children and elders), seeded by name and look.
    static func roll(_ v: VillagerData?, baby: Bool) -> TownStats {
        var s = base(v, baby: baby)
        let role = baby ? "child" : (v?.role ?? "worker")
        let spread: Float = role == "child" || role == "elder" ? 0.08 : 0.12
        var h = UInt64(truncatingIfNeeded: v?.look ?? 0) &* 0x9E37_79B9_7F4A_7C15
        for c in (v?.person ?? "").utf8 { h = (h ^ UInt64(c)) &* 0x100_0000_01B3 }
        func next() -> Float {
            h ^= h >> 29; h = h &* 0xBF58_476D_1CE4_E5B9; h ^= h >> 32
            return Float(h & 0xFFFF) / 65535 * 2 - 1                      // -1 ... 1
        }
        s.toughness *= 1 + spread * next()
        s.speed *= 1 + spread * next()
        s.strength *= 1 + spread * next()
        s.rate *= 1 + spread * next()
        return s
    }

    // How broad they're built (the model's width and depth scale): slighter for the weak, broader for the strong.
    var build: Float { max(0.86, min(1.16, 0.86 + 0.3 * (strength + toughness - 1.1) / 1.9)) }

    // Words a glance tells you (the crosshair line): each stat far enough from an ordinary adult's, the biggest
    // difference first; at most three. (A farmer reads "weak, slow" most of the time, a deputy "quick, fast hands".)
    var traits: [String] {
        var t: [(Float, String)] = []
        func add(_ v: Float, _ hi: Float, _ lo: Float, _ up: String, _ down: String) {
            if v >= hi { t.append((v - 1, up)) } else if v <= lo { t.append((1 - v, down)) }
        }
        add(strength, 1.25, 0.88, "strong", "weak")
        add(toughness, 1.25, 0.8, "tough", "frail")
        add(speed, 1.15, 0.9, "quick", "slow")
        add(rate, 1.15, 0.85, "fast hands", "slow hands")
        return t.sorted { $0.0 > $1.0 }.prefix(3).map { $0.1 }
    }
}

extension Mob {
    // Cached per mob (TownState) and re-rolled when what it was rolled from changes: the role (a child grows up, a
    // sheriff is deputized), the trade (a craftsman losing his workstation and taking another) or the shop. Plain
    // compares, no string building, so a cache hit costs nothing per frame.
    var townStats: TownStats {
        let role = villager?.role ?? "", prof = villager?.profession ?? "", shop = villager?.shop ?? ""
        if let s = town.stats, town.statsRole == role, town.statsProf == prof, town.statsShop == shop, town.statsBaby == baby { return s }
        let s = TownStats.roll(villager, baby: baby)
        town.stats = s; town.statsRole = role; town.statsProf = prof; town.statsShop = shop; town.statsBaby = baby
        return s
    }
}

// The crosshair line: who you're looking at and what a glance tells you about them.
enum TownStatsHUD {
    static func lookedAt(_ g: Game) -> Mob? {
        let eye = g.player.eye, look = g.player.look
        var best: Mob?, bestDot: Float = 0.996                                   // within ~5 degrees
        for m in g.mobs.mobs where TownLaw.isTownsperson(m) {
            let c = m.pos + V3(0, m.baby ? 0.6 : 1.2, 0)
            let d = c - eye
            let l = simd_length(d)
            guard l > 0.5, l < 10 else { continue }
            let dot = simd_dot(d / l, look)
            if dot > bestDot { bestDot = dot; best = m }
        }
        guard let b = best, g.world.canSee(eye, b.eye) else { return nil }
        return b
    }

    static func describe(_ m: Mob) -> String {
        let v = m.villager
        let name = v?.person ?? "Townsperson"
        var job = m.baby ? "child" : (v?.role ?? "worker")
        if job == "shopkeeper", let k = v?.shopKind { job = k.keeper }
        if job == "craftsman", let p = v?.profession, !["none", "nitwit", ""].contains(p) { job = p }
        let t = m.townStats.traits
        return "\(name), \(job)" + (t.isEmpty ? "" : ": " + t.joined(separator: ", "))
    }

    // Shown once you've held your aim on someone for `settle` s, and kept `hold` s after you look away, so sweeping
    // a hand (the Quest aims with it) across a busy street doesn't flicker text in front of you.
    static let settle: Double = 0.3, hold: Double = 0.5
    static weak var aimed: Mob?
    static var aimedSince: Double = 0
    static weak var shown: Mob?
    static var shownUntil: Double = 0

    static func current(_ g: Game, now: Double? = nil) -> Mob? {
        let t = now ?? g.clock
        let m = lookedAt(g)
        if m !== aimed { aimed = m; aimedSince = t }
        if let m, t - aimedSince >= settle { shown = m; shownUntil = t + hold }
        guard let s = shown, s.health > 0, t <= shownUntil else { shown = nil; return nil }
        return s
    }

    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        guard HudExtras.enabled, !g.hideHUD, g.menu == nil, g.alive, TownLaw.inTown != nil,
              !Turrets.shared.active, !WeaponWheel.shared.open, let m = current(g) else { return [] }
        let s = L.s
        let t = describe(m)
        let w = Float(Font.width(t)) * s
        // Below the crosshair, clear of the damage ring and the deck-gun reload bar.
        return [HudLine(text: t, x: (L.W - w) / 2, y: L.H / 2 + 56 * s, scale: s, color: V4(0.95, 0.92, 0.82, 1), bg: V4(0, 0, 0, 0.5))]
    }
}
