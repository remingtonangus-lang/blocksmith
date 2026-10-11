import Foundation
import simd

// Fishing species, weights and the fight (backlog B3, docs/status/hunting.md). A bite you hook on a fish starts a
// fight: hold use to reel, ease off while the fish runs (it pulls hard, the controller rumbles and the water churns),
// reel again as it tires. Too much tension snaps the line; too long slack between runs and it shakes the hook; let it
// run out too far and it's gone. One button, so it plays the same on a pad, a mouse and the Touch controllers (the
// use trigger). Junk and treasure still come in at once (GameCombat.catchFish).

struct FishSpecies {
    let key: String                 // the item
    let name: String
    let minLb: Float, maxLb: Float
    let fight: Float                // how hard it pulls (x weight)
    let fresh: Bool, ocean: Bool
}

enum Fishing {
    static let species: [FishSpecies] = [
        FishSpecies(key: "perch", name: "Yellow Perch", minLb: 0.3, maxLb: 2.5, fight: 0.6, fresh: true, ocean: false),
        FishSpecies(key: "trout", name: "Rainbow Trout", minLb: 0.8, maxLb: 9, fight: 1.0, fresh: true, ocean: false),
        FishSpecies(key: "pike", name: "Northern Pike", minLb: 2, maxLb: 25, fight: 1.3, fresh: true, ocean: false),
        FishSpecies(key: "catfish", name: "Channel Catfish", minLb: 1.5, maxLb: 30, fight: 1.1, fresh: true, ocean: false),
        FishSpecies(key: "salmon", name: "Salmon", minLb: 3, maxLb: 24, fight: 1.2, fresh: true, ocean: true),
        FishSpecies(key: "cod", name: "Cod", minLb: 1.5, maxLb: 25, fight: 0.9, fresh: false, ocean: true),
        FishSpecies(key: "pufferfish", name: "Pufferfish", minLb: 0.3, maxLb: 3, fight: 0.5, fresh: false, ocean: true),
        FishSpecies(key: "tropical_fish", name: "Tropical Fish", minLb: 0.1, maxLb: 1, fight: 0.4, fresh: false, ocean: true),
    ]
    static func index(_ key: String) -> Int? { species.firstIndex { $0.key == key } }

    // Weights by water: rivers, lakes and swamps (fresh) or the sea; cold water favours trout and salmon, warm the
    // tropical fish, swamps and the night the catfish.
    static func pick(_ b: Biome, night: Bool) -> Int {
        let cold = [.frozenRiver, .frozenOcean, .deepFrozenOcean, .coldOcean, .deepColdOcean, .snowyBeach, .snowyPlains, .snowyTaiga,
                    .taiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga, .grove, .iceSpikes].contains(b)
        let warm = [.warmOcean, .lukewarmOcean, .deepLukewarmOcean, .jungle, .sparseJungle, .bambooJungle, .mangroveSwamp].contains(b)
        let swamp = b == .swamp || b == .mangroveSwamp
        let sea = b.isOcean || b == .beach || b == .snowyBeach || b == .stonyShore
        var w = [Int](repeating: 0, count: species.count)
        if sea {
            w[5] = 55; w[4] = cold ? 35 : 15; w[6] = 13; w[7] = warm ? 27 : 2
        } else {
            w[0] = 35; w[1] = cold ? 40 : 25; w[2] = 15; w[3] = 15 + (swamp ? 20 : 0) + (night ? 10 : 0); w[4] = cold ? 25 : 10
        }
        var r = Rand.int(in: 0..<max(1, w.reduce(0, +)))
        for (i, x) in w.enumerated() { r -= x; if r < 0 { return i } }
        return 0
    }
    static func weight(_ s: FishSpecies, luck: Float) -> Float {
        let r = powf(Rand.float(in: 0..<1), max(0.6, 1.6 - 0.2 * luck))
        return ((s.minLb + (s.maxLb - s.minLb) * r) * 10).rounded() / 10
    }
    static func big(_ s: FishSpecies, _ w: Float) -> Bool { w >= s.minLb + 0.8 * (s.maxLb - s.minLb) }

    final class Fight {
        let species: Int
        let weight: Float
        let power: Float            // 0.2 (a small perch) ... ~1.3 (a big pike)
        var line: Float             // blocks of line out
        var tension: Float = 0      // 1 snaps
        var run: Float = 0          // > 0 while the fish runs
        var rest: Float             // until its next run
        var slack: Float = 0        // s without reeling while it rests
        var time: Float = 0
        let dir: V3                 // horizontal, from you out to the fish
        init(species: Int, weight: Float, power: Float, line: Float, dir: V3) {
            self.species = species; self.weight = weight; self.power = power; self.line = line; self.dir = dir
            rest = Rand.float(in: 0.6...1.4)
        }
    }

    // Tuning (the tests play it with a bot that eases off on runs and one that reels non-stop).
    static let reelSpeed: Float = 5, runPull: Float = 3.2, restPull: Float = 0.3
    static let maxLine: Float = 32, landed: Float = 1.6, slackLimit: Float = 3
    static var reeling = false                  // use held this frame (fishingUse)
    static var landedCount = 0, snapped = 0, escaped = 0      // counters (HuntingTests)
    static var lastCatch: (String, Float)?      // species and weight of the last fish landed

    static func reset() { reeling = false; lastCatch = nil }

    // A hooked fish: the fight starts where the bobber is.
    static func start(_ g: Game, _ b: Bobber) -> Fight {
        let biome = g.world.gen.column(Int(floor(b.pos.x)), Int(floor(b.pos.z))).biome
        let night = g.daylight < 0.35
        let i = pick(biome, night: night)
        let s = species[i]
        let luck = Float(Enchant.level(.luckOfTheSea, g.held) + g.effects.level(.luck))
        let w = weight(s, luck: luck)
        let frac = (w - s.minLb) / max(0.1, s.maxLb - s.minLb)
        var d = b.pos - g.player.pos; d.y = 0
        let len = max(2, simd_length(d))
        return Fight(species: i, weight: w, power: s.fight * (0.4 + 0.6 * frac), line: len, dir: d / len)
    }

    enum Outcome { case fighting, landed, snapped, escaped }

    // One step of the fight. `reel`: use held.
    static func step(_ f: Fight, reel: Bool, dt: Float) -> Outcome {
        f.time += dt
        if f.run > 0 {
            f.run -= dt
            if f.run <= 0 { f.rest = Rand.float(in: 1.2...2.6) }
        } else {
            f.rest -= dt
            if f.rest <= 0 { f.run = Rand.float(in: 0.8...1.8) * (0.7 + 0.3 * f.power) }
        }
        let running = f.run > 0
        let pull = running ? runPull * f.power : restPull * f.power
        if reel {
            f.line -= (reelSpeed - pull) * dt
            // Against a run the line strains (hard for a big fish, hardly for a small one); against a tired fish it
            // settles to a low pull.
            if running { f.tension += (0.15 + 0.75 * powf(f.power, 1.5)) * dt }
            else { f.tension += (0.15 * f.power - f.tension) * min(1, 0.8 * dt) }
            f.slack = 0
        } else {
            f.line += pull * dt
            f.tension = max(0, f.tension - 0.7 * dt)
            if !running { f.slack += dt }
        }
        if !running && !reel { f.tension = max(0, f.tension - 0.2 * dt) }
        if f.tension >= 1 { return .snapped }
        if f.line > maxLine || f.slack > slackLimit { return .escaped }
        if f.line <= landed { return .landed }
        return .fighting
    }

    static func line(_ g: Game) -> (String, V4)? {
        guard let b = g.bobber, let f = b.fight else { return nil }
        let n = 10, k = Int(min(1, f.tension) * Float(n))
        let hint = f.run > 0 ? (reeling ? "ease off!" : "it's running") : (reeling ? "reeling" : "reel in")
        let t = species[f.species].name + " [" + String(repeating: "#", count: k) + String(repeating: "-", count: n - k) + "] " + hint
        let c = f.tension > 0.75 ? V4(1, 0.35, 0.3, 1) : (f.tension > 0.45 ? V4(1, 0.8, 0.35, 1) : V4(0.6, 0.95, 0.6, 1))
        return (t, c)
    }
}

extension Game {
    // Per frame while a fish is on (bobberTick). Moves the bobber with the fish and ends the fight.
    func fishFightTick(_ b: Bobber, _ f: Fishing.Fight, _ dt: Float) {
        let wasRunning = f.run > 0
        let r = Fishing.step(f, reel: Fishing.reeling && menu == nil, dt: dt)
        var at = player.pos + f.dir * f.line
        at.y = b.pos.y
        b.pos = at
        b.vel = .zero
        if f.run > 0 {
            if !wasRunning { sfx(.fishSplash, 0.7, at: b.pos); PadManager.shared.rumble(0.35 + 0.3 * min(1, f.power), 0.25) }
            if Rand.float(in: 0..<1) < dt * 14 { particles.smoke(at: b.pos + V3(Rand.float(in: -0.5...0.5), 0, Rand.float(in: -0.5...0.5)), dark: false) }
        }
        if Fishing.reeling && Int((f.time - dt) * 4) != Int(f.time * 4) { sfx(.fishReel, 0.25) }
        let s = Fishing.species[f.species]
        switch r {
        case .fighting: return
        case .snapped:
            Fishing.snapped += 1
            onToast?("The line snapped: the \(s.name.lowercased()) is gone")
            sfx(.itemBreak, 0.5)
            damageHeld(3)
        case .escaped:
            Fishing.escaped += 1
            onToast?("It got away")
            sfx(.fishSplash, 0.5, at: b.pos)
        case .landed:
            Fishing.landedCount += 1
            Fishing.lastCatch = (s.key, f.weight)
            achieve("fish")
            let n = Fishing.big(s, f.weight) ? 2 : 1
            if Items.has(s.key) {
                let dir = player.pos + V3(0, 1, 0) - b.pos
                drops.spawn(ItemStack(Items.id(s.key), n), at: b.pos + V3(0, 0.3, 0), vel: dir * 1.1 + V3(0, sqrtf(simd_length(dir)) * 1.6, 0))
            }
            let best = Hunting.state.records[s.key] ?? 0
            Hunting.state.records[s.key] = max(best, f.weight)
            Hunting.state.caught = (Hunting.state.caught ?? [:]).merging([s.key: 1], uniquingKeysWith: +)
            onToast?(String(format: "%@, %.1f lb%@", s.name, f.weight, f.weight > best && best > 0 ? ": a new record" : ""))
            addXP(Rand.int(in: 1...6) + (n > 1 ? 2 : 0))
            damageHeld(1)
            sfx(.fishSplash, 0.6, at: b.pos)
        }
        bobber = nil
    }
}
