import Foundation
import simd

// Status effects (reference game list, numbers and colours), shared by the player and mobs.
enum Effect: Int, CaseIterable {
    case speed, slowness, haste, miningFatigue, strength, instantHealth, instantDamage, jumpBoost, nausea
    case regeneration, resistance, fireResistance, waterBreathing, invisibility, blindness, nightVision
    case hunger, weakness, poison, wither, healthBoost, absorption, saturation, glowing, levitation
    case luck, badLuck, slowFalling, conduitPower, dolphinsGrace, badOmen, heroOfTheVillage, darkness
    case trialOmen, raidOmen, windCharged, weaving, oozing, infested

    var name: String {
        switch self {
        case .speed: return "Speed"
        case .slowness: return "Slowness"
        case .haste: return "Haste"
        case .miningFatigue: return "Mining Fatigue"
        case .strength: return "Strength"
        case .instantHealth: return "Instant Health"
        case .instantDamage: return "Instant Damage"
        case .jumpBoost: return "Jump Boost"
        case .nausea: return "Nausea"
        case .regeneration: return "Regeneration"
        case .resistance: return "Resistance"
        case .fireResistance: return "Fire Resistance"
        case .waterBreathing: return "Water Breathing"
        case .invisibility: return "Invisibility"
        case .blindness: return "Blindness"
        case .nightVision: return "Night Vision"
        case .hunger: return "Hunger"
        case .weakness: return "Weakness"
        case .poison: return "Poison"
        case .wither: return "Blight"
        case .healthBoost: return "Health Boost"
        case .absorption: return "Absorption"
        case .saturation: return "Saturation"
        case .glowing: return "Glowing"
        case .levitation: return "Levitation"
        case .luck: return "Luck"
        case .badLuck: return "Bad Luck"
        case .slowFalling: return "Slow Falling"
        case .conduitPower: return "Conduit Power"
        case .dolphinsGrace: return "Dolphin's Grace"
        case .badOmen: return "Ill Omen"
        case .heroOfTheVillage: return "Village Hero"
        case .darkness: return "Darkness"
        case .trialOmen: return "Proving Omen"
        case .raidOmen: return "Siege Omen"
        case .windCharged: return "Wind Charged"
        case .weaving: return "Weaving"
        case .oozing: return "Oozing"
        case .infested: return "Infested"
        }
    }
    var key: String { name.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "'", with: "") }

    var color: UInt32 {
        switch self {
        case .speed: return 0x33EBFF
        case .slowness: return 0x8BAFE0
        case .haste: return 0xD9C043
        case .miningFatigue: return 0x4A4217
        case .strength: return 0xFFC700
        case .instantHealth: return 0xF82423
        case .instantDamage: return 0xA9656A
        case .jumpBoost: return 0xFDFF84
        case .nausea: return 0x551D4A
        case .regeneration: return 0xCD5CAB
        case .resistance: return 0x9146F0
        case .fireResistance: return 0xFF9900
        case .waterBreathing: return 0x98DAC0
        case .invisibility: return 0xF6F6F6
        case .blindness: return 0x1F1F23
        case .nightVision: return 0xC2FF66
        case .hunger: return 0x587653
        case .weakness: return 0x484D48
        case .poison: return 0x87A363
        case .wither: return 0x736156
        case .healthBoost: return 0xF87D23
        case .absorption: return 0x2552A5
        case .saturation: return 0xF82423
        case .glowing: return 0x94A061
        case .levitation: return 0xCEFFFF
        case .luck: return 0x59C106
        case .badLuck: return 0xC0A44D
        case .slowFalling: return 0xF3CFB9
        case .conduitPower: return 0x1DC2D1
        case .dolphinsGrace: return 0x88A3BE
        case .badOmen: return 0x0B6138
        case .heroOfTheVillage: return 0x44FF44
        case .darkness: return 0x292721
        case .trialOmen: return 0x16A6A6
        case .raidOmen: return 0xDE4058
        case .windCharged: return 0xBDC9FF
        case .weaving: return 0x78695A
        case .oozing: return 0x99FFA3
        case .infested: return 0x8C9B8C
        }
    }

    var beneficial: Bool {
        switch self {
        case .slowness, .miningFatigue, .instantDamage, .nausea, .blindness, .hunger, .weakness, .poison, .wither,
             .levitation, .badLuck, .darkness, .glowing, .windCharged, .weaving, .oozing, .infested: return false
        default: return true
        }
    }
    var instant: Bool { self == .instantHealth || self == .instantDamage || self == .saturation }

    static func named(_ k: String) -> Effect? { allCases.first { $0.key == k } }

    static func roman(_ n: Int) -> String {
        ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][max(0, min(10, n))]
    }
}

struct ActiveEffect: Codable {
    var amp: Int           // amplifier: 0 = level I
    var time: Float        // seconds left (infinite = .greatestFiniteMagnitude)
    var tick: Float = 0    // periodic-effect timer
    var ambient = false    // from a beacon (no particles in the reference game)
}

// Fixed-size table of active effects (no allocation per tick).
final class EffectSet {
    var slots = [ActiveEffect?](repeating: nil, count: Effect.allCases.count)
    var any = false

    subscript(e: Effect) -> ActiveEffect? {
        get { slots[e.rawValue] }
        set { slots[e.rawValue] = newValue; if newValue != nil { any = true } }
    }
    func has(_ e: Effect) -> Bool { slots[e.rawValue] != nil }
    // Level (1-based) or 0 when absent.
    func level(_ e: Effect) -> Int { slots[e.rawValue].map { $0.amp + 1 } ?? 0 }

    // Reference rules: a stronger effect replaces a weaker one; the same strength keeps the longer time.
    @discardableResult
    func add(_ e: Effect, amp: Int, seconds: Float, ambient: Bool = false) -> Bool {
        if let cur = slots[e.rawValue] {
            if amp < cur.amp { return false }
            if amp == cur.amp && seconds <= cur.time { return false }
            slots[e.rawValue] = ActiveEffect(amp: amp, time: seconds, tick: cur.tick, ambient: ambient)
        } else {
            slots[e.rawValue] = ActiveEffect(amp: amp, time: seconds, ambient: ambient)
        }
        any = true
        return true
    }
    func remove(_ e: Effect) { slots[e.rawValue] = nil }
    func clear() { for i in slots.indices { slots[i] = nil }; any = false }

    var active: [(Effect, ActiveEffect)] {
        var out: [(Effect, ActiveEffect)] = []
        for (i, s) in slots.enumerated() { if let a = s { out.append((Effect(rawValue: i)!, a)) } }
        return out
    }

    // Mixed colour of all effects (potion swirl particles).
    var color: V3? {
        var c = V3.zero, n: Float = 0
        for (i, s) in slots.enumerated() {
            guard let a = s, !a.ambient else { continue }
            let k = Float(a.amp + 1)
            c += TextureGen.hex(Effect(rawValue: i)!.color).rgb3 * k
            n += k
        }
        return n > 0 ? c / n : nil
    }

    struct Saved: Codable { var e: String; var a: Int; var t: Float }
    var saved: [Saved] { active.map { Saved(e: $0.0.key, a: $0.1.amp, t: $0.1.time) } }
    func load(_ s: [Saved]?) {
        clear()
        for x in s ?? [] { if let e = Effect.named(x.e) { add(e, amp: x.a, seconds: x.t) } }
    }
}

extension V4 { var rgb3: V3 { V3(x, y, z) } }

// MARK: Player effects

extension Game {
    var maxHealth: Int { 20 + 4 * effects.level(.healthBoost) }

    // Applies an effect to the player (instant ones act immediately).
    func applyEffect(_ e: Effect, amp: Int, seconds: Float, ambient: Bool = false) {
        switch e {
        case .instantHealth:
            heal(4 << min(amp, 6))
        case .instantDamage:
            damage(6 << min(amp, 6), "was killed by magic", bypassArmor: true)
        case .saturation:
            hunger = min(20, hunger + amp + 1)
            saturation = min(Float(hunger), saturation + Float(2 * (amp + 1)))
        default:
            if !survival && !e.beneficial && e != .badOmen && e != .raidOmen && e != .trialOmen { return }
            let hadAbsorption = effects.level(.absorption)
            if effects.add(e, amp: amp, seconds: seconds, ambient: ambient) {
                if e == .absorption && amp + 1 >= hadAbsorption { absorption = Float(4 * (amp + 1)) }
                if e == .levitation { player.levitate = seconds }
            }
        }
    }

    func heal(_ n: Int) {
        guard n > 0 else { return }
        health = min(maxHealth, health + n)
    }

    // One step of every active effect on the player (runs every frame).
    func effectTick(_ dt: Float) {
        guard effects.any else { applyMovementEffects(); return }
        var anyLeft = false
        for i in effects.slots.indices {
            guard var a = effects.slots[i] else { continue }
            let e = Effect(rawValue: i)!
            a.time -= dt
            a.tick -= dt
            switch e {
            case .regeneration:
                // Every 50 >> amp ticks.
                if a.tick <= 0 { a.tick = Float(max(1, 50 >> a.amp)) / 20; if health < maxHealth { health += 1 } }
            case .poison:
                if a.tick <= 0 { a.tick = Float(max(1, 25 >> a.amp)) / 20; if health > 1 { damage(1, "was poisoned", bypassArmor: true) } }
            case .wither:
                if a.tick <= 0 { a.tick = Float(max(1, 40 >> a.amp)) / 20; damage(1, "withered away", bypassArmor: true) }
            case .hunger:
                if survival { exhaustion += 0.1 * Float(a.amp + 1) * dt }
            case .saturation:
                hunger = min(20, hunger + a.amp + 1)
            case .levitation:
                player.levitate = max(player.levitate, min(a.time, 0.1))
                player.levitateAmp = a.amp
            default: break
            }
            if a.time <= 0 {
                effects.slots[i] = nil
                if e == .absorption { absorption = 0 }
                if e == .healthBoost { health = min(health, maxHealth) }
            } else {
                effects.slots[i] = a
                anyLeft = true
            }
        }
        effects.any = anyLeft
        if absorption > 0 && !effects.has(.absorption) { absorption = 0 }
        applyMovementEffects()
    }

    // Movement multipliers the player physics reads.
    func applyMovementEffects() {
        var mul: Float = 1 + 0.2 * Float(effects.level(.speed)) - 0.15 * Float(effects.level(.slowness))
        mul = max(0, mul)
        player.speedMul = mul
        player.jumpBoost = effects.level(.jumpBoost)
        player.slowFalling = effects.has(.slowFalling)
        player.dolphinsGrace = effects.has(.dolphinsGrace)
        if !effects.has(.levitation) { player.levitateAmp = 0 }
        let feet = inventory.armor[3], legs = inventory.armor[2]
        player.depthStrider = Enchant.level(.depthStrider, feet)
        player.soulSpeed = Enchant.level(.soulSpeed, feet)
        player.swiftSneak = Enchant.level(.swiftSneak, legs)
    }

    // Break-time multiplier from haste / mining fatigue / conduit power.
    var miningSpeedMul: Float {
        var m: Float = 1
        let h = max(effects.level(.haste), effects.level(.conduitPower))
        if h > 0 { m *= 1 + 0.2 * Float(h) }
        let f = effects.level(.miningFatigue)
        if f > 0 { m *= powf(0.3, Float(min(f, 4))) }
        return m
    }

    // Night vision brightness for the renderer (fades out over the last 10 s like the reference game).
    var nightVision: Float {
        guard let a = effects[.nightVision] else { return 0 }
        if a.time > 10 { return 1 }
        return 0.7 + 0.3 * sinf(a.time * .pi * 0.2)
    }

    // Blindness / darkness fog distance (blocks), nil when clear.
    var blindFog: Float? {
        if effects.has(.blindness) { return 5 }
        if effects.has(.darkness) { return 15 + 5 * sinf(Float(clock) * 2) }
        return nil
    }

    // Drinks / eats with a status effect side (reference numbers).
    func foodEffects(_ key: String) {
        switch key {
        case "golden_apple":
            applyEffect(.regeneration, amp: 1, seconds: 5)
            applyEffect(.absorption, amp: 0, seconds: 120)
        case "enchanted_golden_apple":
            applyEffect(.regeneration, amp: 1, seconds: 20)
            applyEffect(.absorption, amp: 3, seconds: 120)
            applyEffect(.resistance, amp: 0, seconds: 300)
            applyEffect(.fireResistance, amp: 0, seconds: 300)
        case "rotten_flesh": if Float.random(in: 0..<1) < 0.8 { applyEffect(.hunger, amp: 0, seconds: 30) }
        case "chicken": if Float.random(in: 0..<1) < 0.3 { applyEffect(.hunger, amp: 0, seconds: 30) }
        case "spider_eye": applyEffect(.poison, amp: 0, seconds: 5)
        case "pufferfish":
            applyEffect(.hunger, amp: 2, seconds: 15)
            applyEffect(.nausea, amp: 0, seconds: 15)
            applyEffect(.poison, amp: 1, seconds: 60)
        case "poisonous_potato": if Float.random(in: 0..<1) < 0.6 { applyEffect(.poison, amp: 0, seconds: 5) }
        case "honey_bottle": effects.remove(.poison)
        case "milk_bucket":
            effects.clear(); absorption = 0; health = min(health, maxHealth)
        default:
            if key.hasPrefix("suspicious_stew") { if let e = SuspiciousStew.effect(key) { applyEffect(e.0, amp: 0, seconds: e.1) } }
        }
    }
}

// Suspicious stew: flower -> effect (reference table).
enum SuspiciousStew {
    static let flowers: [(String, Effect, Float)] = [
        ("allium", .fireResistance, 3), ("azure_bluet", .blindness, 11), ("blue_orchid", .saturation, 0.35),
        ("dandelion", .saturation, 0.35), ("cornflower", .jumpBoost, 5), ("lily_of_the_valley", .poison, 11),
        ("oxeye_daisy", .regeneration, 7), ("poppy", .nightVision, 5), ("red_tulip", .weakness, 7),
        ("orange_tulip", .weakness, 7), ("white_tulip", .weakness, 7), ("pink_tulip", .weakness, 7),
        ("wither_rose", .wither, 7), ("torchflower", .nightVision, 5), ("open_eyeblossom", .blindness, 11),
        ("closed_eyeblossom", .nausea, 7),
    ]
    static func effect(_ key: String) -> (Effect, Float)? {
        let f = key.replacingOccurrences(of: "suspicious_stew_", with: "")
        return flowers.first { $0.0 == f }.map { ($0.1, $0.2) }
    }
}

// MARK: Mob effects

extension Mob {
    static let undeadKeys: Set<String> = ["zombie", "skeleton", "zombified_piglin", "wither_skeleton", "husk", "stray", "drowned", "wither",
                                          "phantom", "zoglin", "skeleton_horse", "zombie_horse", "zombie_villager", "bogged"]
    static let arthropodKeys: Set<String> = ["spider", "cave_spider", "silverfish", "endermite", "bee"]
    var undead: Bool { Mob.undeadKeys.contains(kind.key) }
    var arthropod: Bool { Mob.arthropodKeys.contains(kind.key) }

    // Applies an effect to a mob (undead swap instant health and damage and ignore poison/regeneration).
    func applyEffect(_ e: Effect, amp: Int, seconds: Float, game g: Game) {
        // The wyrm (and its crystals) ignore every effect; the Blight ignores blight.
        if kind == .enderDragon || kind == .endCrystal || (kind == .wither && e == .wither) { return }
        var e = e
        if undead && e == .instantHealth { e = .instantDamage } else if undead && e == .instantDamage { e = .instantHealth }
        switch e {
        case .instantHealth: health = min(spec.health, health + (4 << min(amp, 6)))
        case .instantDamage:
            health -= 6 << min(amp, 6)
            hurt = 0.4
            aggro = true
        default:
            if undead && (e == .poison || e == .regeneration) { return }
            if kind.key == "wither" && e != .instantDamage && e != .instantHealth { return }
            if effects == nil { effects = EffectSet() }
            effects!.add(e, amp: amp, seconds: seconds)
        }
    }

    func effectTick(_ dt: Float, _ g: Game) {
        guard let fx = effects, fx.any else { return }
        var left = false
        for i in fx.slots.indices {
            guard var a = fx.slots[i] else { continue }
            let e = Effect(rawValue: i)!
            a.time -= dt
            a.tick -= dt
            switch e {
            case .regeneration: if a.tick <= 0 { a.tick = Float(max(1, 50 >> a.amp)) / 20; health = min(spec.health, health + 1) }
            case .poison: if a.tick <= 0 { a.tick = Float(max(1, 25 >> a.amp)) / 20; if health > 1 { health -= 1; hurt = 0.2 } }
            case .wither: if a.tick <= 0 { a.tick = Float(max(1, 40 >> a.amp)) / 20; health -= 1; hurt = 0.2 }
            case .levitation: vel.y += (0.9 * Float(a.amp + 1) - vel.y) * min(1, dt * 4)
            default: break
            }
            if a.time <= 0 { fx.slots[i] = nil } else { fx.slots[i] = a; left = true }
        }
        fx.any = left
    }

    // Speed factor from speed / slowness.
    var effectSpeed: Float {
        guard let fx = effects, fx.any else { return 1 }
        return max(0, 1 + 0.2 * Float(fx.level(.speed)) - 0.15 * Float(fx.level(.slowness)))
    }
    var invisible: Bool { effects?.has(.invisibility) ?? false }
}

// Extra saved state (key/value) for systems added later.
extension Game {
    func saveExtra() -> [String: String] {
        var d: [String: String] = [:]
        if let w = try? JSONEncoder().encode(weather), let s = String(data: w, encoding: .utf8) { d["weather"] = s }
        d["patrol"] = "\(patrolTimer)"
        d["rest"] = "\(timeSinceRest)"
        d["difficulty"] = "\(difficulty)"
        saveAdvancements(&d)
        d["eaten"] = eatenFoods.sorted().joined(separator: "|")
        if let e = try? JSONEncoder().encode(enderChest.slots), let str = String(data: e, encoding: .utf8) { d["ender"] = str }
        if let r = raid?.record, let e = try? JSONEncoder().encode(r), let str = String(data: e, encoding: .utf8) { d["raid"] = str }
        return d
    }
    func loadExtra(_ d: [String: String]) {
        if let s = d["weather"], let data = s.data(using: .utf8), let w = try? JSONDecoder().decode(Weather.self, from: data) { weather = w }
        if let p = d["patrol"], let v = Float(p) { patrolTimer = v }
        if let p = d["rest"], let v = Float(p) { timeSinceRest = v }
        if let p = d["difficulty"], let v = Int(p) { difficulty = max(0, min(3, v)) }
        loadAdvancements(d)
        eatenFoods = Set((d["eaten"] ?? "").split(separator: "|").map(String.init))
        if let str = d["ender"], let data = str.data(using: .utf8), let slots = try? JSONDecoder().decode([ItemStack].self, from: data) {
            for (i, st) in slots.prefix(27).enumerated() { enderChest[i] = st }
        }
        if let str = d["raid"], let data = str.data(using: .utf8), let rec = try? JSONDecoder().decode(RaidRecord.self, from: data) { raid = Raid(rec) }
    }
}
