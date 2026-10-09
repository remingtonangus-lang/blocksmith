import Foundation

// Mob voices: every MobKind maps to a voice family (grunt, moo, groan, rattle, ...) with a base pitch
// and a size; ambient / hurt / death are shaped from the family's call. Boss and one-off mob sounds
// (dragon, blight, warden, villager work sounds, ...) live in `special`.

enum MobVoice {
    enum Family {
        case silent, grunt, moo, bleat, cluck, groan, rattle, hiss, warble, squish, wail, crackle, hum, growl, bark, meow, neigh, buzz, chirp, roar
        case bubble, click, rumble, creak, trill, snort, wind, squeak, soldier, snow
    }
    struct Profile { var family: Family; var f0: Float; var size: Float }

    // Per-kind footstep data, computed once (a mob's spec is rebuilt on every access).
    struct StepInfo { var walks: Bool; var stride: Float; var volume: Float }
    static let stepInfo: [StepInfo] = MobKind.allCases.map { k in
        let sp = k.spec
        return StepInfo(walks: !sp.flying && !sp.aquatic && sp.behavior != .vehicle, stride: 0.9 + sp.halfW * 1.6, volume: min(0.9, 0.2 + sp.halfW * 0.5))
    }

    static let professions = ["armorer", "butcher", "cartographer", "cleric", "farmer", "fisherman", "fletcher", "leatherworker", "librarian", "mason", "shepherd", "toolsmith", "weaponsmith"]
    static func workIndex(_ profession: String) -> Int? { professions.firstIndex(of: profession) }

    static func profile(_ k: MobKind) -> Profile {
        switch k {
        case .cow: return Profile(family: .moo, f0: 150, size: 1)
        case .mooshroom: return Profile(family: .moo, f0: 140, size: 1.1)
        case .sniffer: return Profile(family: .snort, f0: 90, size: 1.6)
        case .sheep: return Profile(family: .bleat, f0: 420, size: 1)
        case .goat: return Profile(family: .bleat, f0: 360, size: 1.1)
        case .chicken: return Profile(family: .cluck, f0: 1100, size: 1)
        case .parrot: return Profile(family: .chirp, f0: 1600, size: 0.9)
        case .bat: return Profile(family: .chirp, f0: 2400, size: 0.5)
        case .rabbit: return Profile(family: .squeak, f0: 1400, size: 0.6)
        case .fox: return Profile(family: .squeak, f0: 900, size: 0.8)
        case .pig: return Profile(family: .grunt, f0: 180, size: 1)
        case .hoglin: return Profile(family: .grunt, f0: 120, size: 1.6)
        case .zoglin: return Profile(family: .growl, f0: 110, size: 1.6)
        case .piglin: return Profile(family: .grunt, f0: 210, size: 1.1)
        case .piglinBrute: return Profile(family: .grunt, f0: 150, size: 1.5)
        case .zombifiedPiglin: return Profile(family: .groan, f0: 160, size: 1.1)
        case .panda: return Profile(family: .grunt, f0: 140, size: 1.4)
        case .armadillo: return Profile(family: .grunt, f0: 260, size: 0.7)
        case .camel: return Profile(family: .snort, f0: 130, size: 1.4)
        case .zombie, .husk, .zombieVillager: return Profile(family: .groan, f0: 95, size: 1)
        case .drowned: return Profile(family: .groan, f0: 110, size: 1.05)
        case .skeleton, .stray, .bogged: return Profile(family: .rattle, f0: 3500, size: 1)
        case .witherSkeleton: return Profile(family: .rattle, f0: 2200, size: 1.4)
        case .skeletonHorse: return Profile(family: .rattle, f0: 1800, size: 1.6)
        case .creeper: return Profile(family: .hiss, f0: 4000, size: 1)
        case .spider: return Profile(family: .hiss, f0: 4000, size: 1)
        case .caveSpider: return Profile(family: .hiss, f0: 5200, size: 0.7)
        case .silverfish: return Profile(family: .click, f0: 3000, size: 0.5)
        case .endermite: return Profile(family: .click, f0: 3600, size: 0.4)
        case .enderman: return Profile(family: .warble, f0: 300, size: 1.2)
        case .vex: return Profile(family: .warble, f0: 900, size: 0.5)
        case .allay: return Profile(family: .trill, f0: 1400, size: 0.5)
        case .phantom: return Profile(family: .warble, f0: 1200, size: 0.8)
        case .breeze: return Profile(family: .wind, f0: 600, size: 1)
        case .slime: return Profile(family: .squish, f0: 500, size: 1)
        case .magmaCube: return Profile(family: .squish, f0: 300, size: 1.2)
        case .frog: return Profile(family: .squish, f0: 700, size: 0.5)
        case .tadpole: return Profile(family: .bubble, f0: 1200, size: 0.3)
        case .turtle: return Profile(family: .squish, f0: 400, size: 0.8)
        case .axolotl: return Profile(family: .bubble, f0: 900, size: 0.6)
        case .ghast: return Profile(family: .wail, f0: 520, size: 1.6)
        case .blaze: return Profile(family: .crackle, f0: 1200, size: 1)
        case .strider: return Profile(family: .squeak, f0: 600, size: 1.2)
        case .villager, .wanderingTrader: return Profile(family: .hum, f0: 190, size: 1)
        case .witch: return Profile(family: .hum, f0: 240, size: 0.9)
        case .pillager, .vindicator: return Profile(family: .hum, f0: 150, size: 1.2)
        case .evoker: return Profile(family: .hum, f0: 170, size: 1.1)
        case .ironGolem: return Profile(family: .rumble, f0: 90, size: 1.6)
        case .snowGolem: return Profile(family: .snow, f0: 900, size: 1)
        case .ravager: return Profile(family: .growl, f0: 110, size: 1.8)
        case .polarBear: return Profile(family: .growl, f0: 130, size: 1.5)
        case .wolf: return Profile(family: .bark, f0: 520, size: 1)
        case .cat, .ocelot: return Profile(family: .meow, f0: 620, size: 1)
        case .horse: return Profile(family: .neigh, f0: 700, size: 1)
        case .donkey, .mule: return Profile(family: .neigh, f0: 520, size: 1.2)
        case .llama, .traderLlama: return Profile(family: .snort, f0: 330, size: 1)
        case .bee: return Profile(family: .buzz, f0: 230, size: 1)
        case .squid, .glowSquid: return Profile(family: .bubble, f0: 400, size: 1)
        case .dolphin: return Profile(family: .chirp, f0: 2000, size: 1.1)
        case .cod, .salmon, .tropicalFish, .pufferfish: return Profile(family: .bubble, f0: 800, size: 0.6)
        case .guardian: return Profile(family: .bubble, f0: 300, size: 1.3)
        case .elderGuardian: return Profile(family: .bubble, f0: 180, size: 2)
        case .shulker: return Profile(family: .click, f0: 1500, size: 1)
        case .warden: return Profile(family: .roar, f0: 60, size: 2)
        case .enderDragon: return Profile(family: .roar, f0: 75, size: 2.5)
        case .wither: return Profile(family: .groan, f0: 140, size: 2)
        case .creaking: return Profile(family: .creak, f0: 220, size: 1.3)
        case .minecart, .boat, .armorStand, .endCrystal: return Profile(family: .silent, f0: 0, size: 1)
        case .zombieHorse: return Profile(family: .neigh, f0: 430, size: 1.2)
        case .illusioner: return Profile(family: .hum, f0: 165, size: 1.1)
        case .happyGhast: return Profile(family: .trill, f0: 700, size: 1.6)
        case .parched: return Profile(family: .rattle, f0: 2600, size: 1.05)
        case .camelHusk: return Profile(family: .snort, f0: 110, size: 1.4)
        case .nautilus: return Profile(family: .bubble, f0: 520, size: 0.8)
        case .zombieNautilus: return Profile(family: .bubble, f0: 320, size: 0.9)
        case .soldierRecruit: return Profile(family: .soldier, f0: 0, size: 1)
        case .soldierTrooper: return Profile(family: .soldier, f0: 1, size: 1)
        case .soldierMarksman: return Profile(family: .soldier, f0: 2, size: 1)
        case .soldierIronclad: return Profile(family: .soldier, f0: 3, size: 1.2)
        case .soldierOfficer: return Profile(family: .soldier, f0: 1, size: 1)
        case .soldierCrew: return Profile(family: .soldier, f0: 0, size: 1)
        case .deckGun, .ashTank, .ashHalftrack, .ashArtillery, .ashTruck: return Profile(family: .silent, f0: 0, size: 1)
        case .ashMarshal: return Profile(family: .soldier, f0: 3, size: 1.15)
        case .copperGolem: return Profile(family: .click, f0: 900, size: 0.7)
        }
    }

    // Duration / pitch shaping of a family call for each kind of sound.
    private static func shape(_ s: MobSound, dur: Float, f0: Float, f1: Float) -> (Float, Float, Float) {
        switch s {
        case .ambient: return (dur, f0, f1)
        case .hurt: return (dur * 0.45 + 0.08, f0 * 1.3, f1 * 1.15)
        case .death: return (dur * 1.5 + 0.3, f0 * 1.1, f1 * 0.55)
        }
    }

    // Hurt gets a sharp impact at the start; death a thud and a fade over its second half.
    private static func post(_ g: inout Synth, _ s: MobSound, _ x: [Float], size: Float) -> [Float] {
        var out = x
        switch s {
        case .ambient: break
        case .hurt: out = Synth.mix(out, g.burst(0.08, lp: 1500, hp: 200, decay: 0.03, gain: 0.5 * size))
        case .death:
            let n = out.count
            for i in 0..<n { let k = Float(i) / Float(max(1, n)); if k > 0.5 { out[i] *= 1 - (k - 0.5) * 1.6 } }
            out = Synth.mix(out, g.burst(0.3, lp: 350 * size, hp: 30, attack: 0.02, decay: 0.08 * size, gain: 1.5 * size), at: max(0, n - g.frames(0.3)))
        }
        return out
    }

    static func render(_ g: inout Synth, _ k: MobKind, _ s: MobSound, pitch p: Float) -> [Float] {
        let pr = profile(k)
        let f = pr.f0 * p / powf(pr.size, 0.35), sz = pr.size
        var out: [Float]
        // Quiet idle calls for two otherwise wordless mobs (the caller plays them softly).
        if s == .ambient && k == .creeper {
            // A faint dry rustle with a couple of fizzing ticks.
            let rustle = Synth.window(g.wash(0.45, lp: 3200 * p, hp: 900, wobble: 0.6, rate: 9, gain: 0.35))
            let ticks = g.grains(5, spread: 0.35, lp: 6000 * p, hp: 2200, decay: 0.004, gain: 0.6)
            return Synth.mix(rustle, ticks, at: g.frames(0.05))
        }
        if s == .ambient && k == .magmaCube {
            // A low wet squelch and a slow lava-ish bubble.
            let squelch = g.burst(0.22, lp: 380 * p, hp: 45, attack: 0.02, decay: 0.07, gain: 2.0)
            let pops = g.bubbles(0.5, count: 3, fLo: 110 * p, fHi: 260 * p, len: 0.09, gain: 0.7)
            return Synth.mix(squelch, pops, at: g.frames(0.08))
        }
        switch pr.family {
        case .snow:
            let (d, a, b) = shape(s, dur: 0.6 * sz, f0: f, f1: f * 0.8)
            switch s {
            case .ambient:
                // Airy hum over a soft packed-snow crunch.
                let air = Synth.window(g.wash(d, lp: 1500 * p, hp: 250, wobble: 0.7, rate: 3, gain: 0.45))
                let hum = g.tone(d, f0: a * 0.25, f1: b * 0.25, wave: .sine, attack: 0.12, release: 0.2, vib: 0.03, vibRate: 4, gain: 0.18)
                out = Synth.mix(Synth.mix(air, hum), g.material(.snow, pitch: p, scale: 0.6, gain: 0.35), at: g.frames(d * 0.3))
            case .hurt:
                // A crunchy packed-snow hit.
                let crunch = g.material(.snow, pitch: p * 1.15, scale: 0.9, gain: 0.8)
                out = Synth.mix(crunch, g.grains(7, spread: 0.12, lp: 4500 * p, hp: 1200, decay: 0.006, gain: 0.7))
            case .death:
                // Snow crumbling apart: three crunches settling into a soft fall of grains.
                let crunches = g.repeated({ g in g.material(.snow, pitch: p * 0.9, scale: 1.1, gain: 0.7) }, times: 3, interval: 0.16, jitter: 0.25)
                out = Synth.mix(crunches, g.grains(22, spread: 0.9, lp: 3500 * p, hp: 700, decay: 0.01, gain: 0.6), at: g.frames(0.1))
            }
        case .silent:
            out = g.modes(0.05, [(800, 0.2, 0.01)])
        case .soldier:
            // f0 holds the rank; idle chatter, a hurt grunt and a death cry from SoldierVoice.
            let bark: Bark = s == .ambient ? .idle : (s == .hurt ? .hurt : .death)
            return SoldierVoice.render(&g, rank: Int(pr.f0), bark, p: p)
        case .grunt:
            let (d, a, b) = shape(s, dur: 0.25 * sz, f0: f, f1: f * 0.75)
            let one = g.formant(d, f0: a, f1: b, formants: [(420, 5, 1), (950, 6, 0.6), (2300, 8, 0.2)], breath: 0.2, vib: 0.06, vibRate: 14, attack: 0.01, release: 0.05, growl: 0.35, gain: 1.2)
            out = s == .ambient ? Synth.mix(one, g.formant(d * 0.8, f0: a * 1.1, f1: b, formants: [(450, 5, 1), (1000, 6, 0.5)], breath: 0.2, vib: 0.05, vibRate: 14, growl: 0.3, gain: 1.0), at: g.frames(d + 0.05)) : one
        case .moo:
            let (d, a, b) = shape(s, dur: 0.85 * sz, f0: f, f1: f * 0.7)
            out = g.formant(d, f0: a, f1: b, formants: [(330, 5, 1), (720, 6, 0.5), (1800, 8, 0.15)], breath: 0.08, vib: 0.02, vibRate: 4, attack: 0.05, release: 0.15, gain: 1.3)
        case .bleat:
            let (d, a, b) = shape(s, dur: 0.6 * sz, f0: f, f1: f * 0.9)
            out = g.formant(d, f0: a, f1: b, formants: [(620, 6, 1), (1350, 7, 0.6), (2900, 9, 0.3)], breath: 0.12, vib: 0.09, vibRate: 9, attack: 0.03, release: 0.1, gain: 1.1)
        case .cluck:
            let (d, a, b) = shape(s, dur: 0.09, f0: f, f1: f * 0.7)
            let n = s == .ambient ? 2 : (s == .hurt ? 1 : 4)
            out = g.repeated({ g in g.formant(d, f0: a, f1: b, formants: [(1200, 6, 1), (2600, 8, 0.6), (4000, 10, 0.3)], breath: 0.25, attack: 0.005, release: 0.03, gain: 1.0) }, times: n, interval: 0.13)
        case .groan:
            let (d, a, b) = shape(s, dur: 0.9 * sz, f0: f, f1: f * 0.75)
            out = Synth.mix(g.formant(d, f0: a, f1: b, formants: [(300, 4, 1), (720, 5, 0.5), (1700, 7, 0.15)], breath: 0.3, vib: 0.08, vibRate: 3.5, attack: 0.08, release: 0.2, growl: 0.5, gain: 1.3),
                            g.burst(d, lp: 700, hp: 80, attack: 0.1, decay: d * 0.4, gain: 0.3))
        case .rattle:
            let n = s == .ambient ? 10 : (s == .hurt ? 5 : 16)
            let spread: Float = s == .ambient ? 0.35 : (s == .hurt ? 0.12 : 0.8)
            out = g.grains(n, spread: spread * sz, lp: f, hp: f * 0.35, decay: 0.006 * sz, gain: 1.2)
            if s != .ambient { out = Synth.mix(out, g.modes(0.2, [(520 / powf(sz, 0.5), 0.5, 0.03), (1330 / powf(sz, 0.5), 0.3, 0.02)])) }
        case .hiss:
            let (d, _, _) = shape(s, dur: 0.5 * sz, f0: f, f1: f)
            out = Synth.mix(g.burst(d, lp: f, hp: f * 0.35, attack: 0.05, decay: d * 0.4, gain: 1),
                            g.grains(8, spread: d * 0.8, lp: f * 0.5, hp: 400, decay: 0.01, gain: 0.8))
            if s != .ambient { out = Synth.mix(out, g.formant(d * 0.6, f0: f * 0.12, f1: f * 0.08, formants: [(800, 6, 1), (2000, 8, 0.5)], breath: 0.4, attack: 0.01, release: 0.05, gain: 0.8)) }
        case .warble:
            let (d, a, b) = shape(s, dur: 1.0 * sz, f0: f, f1: f * 0.4)
            out = g.formant(d, f0: a, f1: b, formants: [(700, 6, 1), (1600, 8, 0.6), (3000, 10, 0.3)], breath: 0.15, vib: 0.3, vibRate: 6.5, attack: 0.05, release: 0.15, gain: 1.1)
            out = Synth.echo(out, delay: 0.09, feedback: 0.35, mix: 0.35, tail: 0.3)
        case .squish:
            let (d, _, _) = shape(s, dur: 0.2 * sz, f0: f, f1: f)
            out = Synth.mix(g.burst(d, lp: f, hp: 60, attack: 0.01, decay: d * 0.3, gain: 2.5), g.bubbles(d, count: Int(3 * sz), fLo: f * 0.4, fHi: f * 1.2, len: 0.05, gain: 0.5))
        case .wail:
            let (d, a, b) = shape(s, dur: 1.4 * sz, f0: f, f1: f * 0.5)
            out = Synth.mix(g.formant(d, f0: a, f1: b, formants: [(900, 6, 1), (1800, 8, 0.5), (3200, 10, 0.25)], breath: 0.2, vib: 0.3, vibRate: 4.5, attack: 0.15, release: 0.4, gain: 1.1),
                            g.burst(d, lp: 1800, hp: 400, attack: 0.2, decay: d * 0.6, gain: 0.25))
            out = Synth.echo(out, delay: 0.15, feedback: 0.3, mix: 0.3, tail: 0.5)
        case .crackle:
            let (d, _, _) = shape(s, dur: 1.0 * sz, f0: f, f1: f)
            out = Synth.mix(g.burst(d, lp: f, hp: 90, attack: 0.15, decay: d * 0.7, gain: 1.4), g.crackle(d, density: 30, f: f * 2.5, q: 2.5, gain: 1.5))
            if s != .ambient { out = Synth.mix(out, g.formant(d * 0.5, f0: 220, f1: 140, formants: [(700, 6, 1), (1900, 8, 0.4)], breath: 0.5, attack: 0.01, release: 0.1, gain: 0.7)) }
        case .hum:
            let (d, a, b) = shape(s, dur: 0.25 * sz, f0: f, f1: f * 1.25)
            let one = g.formant(d, f0: a, f1: b, formants: [(280, 5, 1), (900, 7, 0.35), (2400, 9, 0.1)], breath: 0.05, vib: 0.03, attack: 0.03, release: 0.06, gain: 1.2)
            out = s == .ambient ? Synth.mix(one, g.formant(d, f0: b, f1: a * 0.9, formants: [(300, 5, 1), (950, 7, 0.35)], breath: 0.05, vib: 0.03, attack: 0.03, release: 0.08, gain: 1.1), at: g.frames(d - 0.02)) : one
        case .growl:
            let (d, a, b) = shape(s, dur: 0.9 * sz, f0: f, f1: f * 0.65)
            out = Synth.mix(g.formant(d, f0: a, f1: b, formants: [(250, 4, 1), (650, 5, 0.6), (1500, 7, 0.25)], breath: 0.25, vib: 0.05, vibRate: 3, attack: 0.05, release: 0.2, growl: 0.6, gain: 1.4),
                            g.rumble(d, f: 70, attack: 0.05, decay: d * 0.5, gain: 1.0))
        case .bark:
            let (d, a, b) = shape(s, dur: 0.18, f0: f, f1: f * 0.75)
            let n = s == .ambient ? 2 : (s == .hurt ? 1 : 3)
            out = g.repeated({ g in g.formant(d, f0: a, f1: b, formants: [(700, 6, 1), (1500, 7, 0.6), (2800, 9, 0.3)], breath: 0.2, attack: 0.01, release: 0.05, growl: 0.2, gain: 1.2) }, times: n, interval: 0.25)
        case .meow:
            let (d, a, b) = shape(s, dur: 0.6 * sz, f0: f, f1: f * 1.3)
            out = g.formant(d, f0: a, f1: b, formants: [(900, 7, 1), (2200, 9, 0.6), (3400, 11, 0.3)], breath: 0.1, vib: 0.05, vibRate: 6, attack: 0.04, release: 0.15, gain: 1.0)
        case .neigh:
            let (d, a, b) = shape(s, dur: 0.9 * sz, f0: f, f1: f * 0.55)
            out = Synth.mix(g.formant(d, f0: a, f1: b, formants: [(800, 6, 1), (1900, 8, 0.6), (3100, 10, 0.3)], breath: 0.25, vib: 0.35, vibRate: 12, attack: 0.05, release: 0.2, gain: 1.1),
                            g.burst(d * 0.5, lp: 1500, hp: 200, attack: 0.05, decay: d * 0.3, gain: 0.3))
        case .buzz:
            let (d, a, _) = shape(s, dur: 0.8 * sz, f0: f, f1: f)
            out = g.tone(d, f0: a, f1: a * 0.95, wave: .saw, attack: 0.05, release: 0.1, vib: 0.04, vibRate: 7, gain: 0.35)
            out = Synth.lowpass(out, 1800)
            out = Synth.mix(out, g.tone(d, f0: a * 2.02, f1: a * 1.9, wave: .saw, attack: 0.05, release: 0.1, vib: 0.05, vibRate: 9, gain: 0.12))
        case .chirp, .squeak:
            let (d, a, b) = shape(s, dur: 0.1 * sz, f0: f, f1: f * (pr.family == .chirp ? 1.4 : 0.8))
            let n = s == .ambient ? 3 : (s == .hurt ? 1 : 4)
            out = g.repeated({ g in g.tone(d, f0: a, f1: b, wave: .sine, attack: 0.005, release: 0.03, vib: 0.1, vibRate: 30, gain: 0.5) }, times: n, interval: 0.12, jitter: 0.3)
            if pr.family == .squeak { out = Synth.mix(out, g.burst(d * Float(n), lp: a, hp: a * 0.3, attack: 0.01, decay: d, gain: 0.3)) }
        case .roar:
            let (d, a, b) = shape(s, dur: 1.6 * sz, f0: f, f1: f * 0.7)
            out = Synth.mix(g.formant(d, f0: a, f1: b, formants: [(200, 4, 1), (500, 5, 0.6), (1200, 7, 0.3)], breath: 0.3, vib: 0.06, vibRate: 3, attack: 0.1, release: 0.4, growl: 0.7, gain: 1.6),
                            g.rumble(d, f: 45, attack: 0.1, decay: d * 0.5, gain: 2.0))
            out = Synth.mix(out, g.burst(d, lp: 2500, hp: 300, attack: 0.1, decay: d * 0.5, gain: 0.3))
        case .bubble:
            let (d, a, b) = shape(s, dur: 0.6 * sz, f0: f, f1: f)
            out = Synth.mix(g.bubbles(d, count: Int(6 * sz), fLo: a * 0.6, fHi: b * 1.4, len: 0.06 * sz, gain: 0.6), g.burst(d, lp: 900, hp: 100, attack: 0.05, decay: d * 0.4, gain: 0.4))
            if s != .ambient { out = Synth.mix(out, g.tone(d * 0.5, f0: a, f1: b * 0.6, wave: .sine, attack: 0.01, release: 0.1, gain: 0.3)) }
        case .click:
            let n = s == .ambient ? 3 : (s == .hurt ? 2 : 6)
            out = g.repeated({ g in Synth.mix(g.modes(0.06, [(f, 0.4, 0.008), (f * 1.7, 0.2, 0.005)]), g.burst(0.03, lp: f * 1.5, hp: f * 0.4, decay: 0.005, gain: 0.7)) }, times: n, interval: 0.09 * sz, jitter: 0.3)
            if s == .death { out = Synth.mix(out, g.burst(0.3, lp: 1200, hp: 200, attack: 0.02, decay: 0.08, gain: 0.8)) }
        case .rumble:
            let (d, a, _) = shape(s, dur: 0.5 * sz, f0: f, f1: f)
            out = Synth.mix(g.burst(d, lp: 300 * sz / 1.6, hp: 40, attack: 0.05, decay: d * 0.5, gain: 2), g.modes(d, [(a, 0.4, d * 0.4), (a * 1.55, 0.2, d * 0.3)]))
            if s != .ambient { out = Synth.mix(out, g.material(.metal, pitch: 0.7, scale: 1.2, gain: 0.5)) }
        case .creak:
            let (d, a, b) = shape(s, dur: 0.8 * sz, f0: f, f1: f * 0.7)
            out = Synth.lowpass(g.tone(d, f0: a, f1: b, wave: .saw, attack: 0.1, release: 0.2, vib: 0.15, vibRate: 2.5, gain: 0.3), 1200)
            out = Synth.mix(out, g.crackle(d, density: 25, f: 900, q: 4, gain: 1.0))
            out = Synth.mix(out, g.material(.wood, pitch: 0.7, scale: 1.0, gain: 0.4), at: g.frames(d * 0.5))
        case .trill:
            let (d, a, _) = shape(s, dur: 0.5 * sz, f0: f, f1: f)
            out = []
            for k in 0..<4 { out = Synth.mix(out, g.fm(0.3, f: a * powf(1.19, Float(k)), ratio: 2, index: 0.8, decay: 0.15, gain: 0.3), at: g.frames(Float(k) * d / 4)) }
            if s == .death { out = Synth.mix(out, g.tone(d, f0: a, f1: a * 0.5, wave: .sine, attack: 0.05, release: 0.2, gain: 0.3)) }
        case .snort:
            let (d, a, b) = shape(s, dur: 0.35 * sz, f0: f, f1: f * 0.8)
            out = Synth.mix(g.burst(d, lp: 1200, hp: 150, attack: 0.02, decay: d * 0.4, gain: 1.2), g.formant(d, f0: a, f1: b, formants: [(400, 5, 1), (1100, 6, 0.4)], breath: 0.5, vib: 0.1, vibRate: 20, attack: 0.02, release: 0.08, growl: 0.4, gain: 0.8))
        case .wind:
            let (d, a, b) = shape(s, dur: 0.9 * sz, f0: f, f1: f * 1.4)
            out = g.wash(d, lp: a, hp: 150, wobble: 1.2, rate: 6, gain: 0.8)
            for i in 0..<out.count { out[i] *= sinf(Float(i) / Float(max(1, out.count)) * .pi) }
            out = Synth.mix(out, g.tone(d, f0: a * 0.5, f1: b * 0.5, wave: .sine, attack: 0.1, release: 0.3, vib: 0.2, vibRate: 5, gain: 0.15))
        }
        return post(&g, s, out, size: sz)
    }

    // One-off mob sounds, bosses, villager work sounds.
    static func special(_ g: inout Synth, _ s: Snd, pitch p: Float) -> [Float] {
        switch s {
        case .creeperHiss: return g.burst(1.5, lp: 7000, hp: 2500, attack: 0.3, decay: 1.2, gain: 1.4)
        case .fireball: return Synth.mix(g.burst(0.8, lp: 900 * p, hp: 60, attack: 0.02, decay: 0.3, gain: 2.2), g.burst(0.5, lp: 5000, hp: 1500, attack: 0.01, decay: 0.2, gain: 0.5))
        case .evokerCast: return Synth.mix(g.modes(1.0, [(440 * p, 0.2, 0.5), (660 * p, 0.15, 0.4)]), g.grains(8, spread: 0.8, lp: 4000, hp: 1000, decay: 0.05, gain: 0.4))
        case .fangs: return Synth.mix(g.burst(0.25, lp: 3000 * p, hp: 300, attack: 0.005, decay: 0.08, gain: 1.2), g.modes(0.2, [(180 * p, 0.3, 0.08)]))
        case .raidHorn: return Synth.mix(g.formant(3.5, f0: 98, f1: 92, formants: [(300, 4, 1), (800, 6, 0.5), (1600, 8, 0.2)], breath: 0.05, vib: 0.08, vibRate: 5, attack: 0.1, release: 0.6, gain: 1.4), g.voice(3.5, f0: 147, f1: 139, vib: 0.08, lp: 1400, gain: 0.5))
        case .teleport:
            let up = g.tone(0.5, f0: 300 * p, f1: 1500 * p, wave: .sine, attack: 0.05, release: 0.2, vib: 0.1, vibRate: 12, gain: 0.3)
            return Synth.mix(Synth.echo(up, delay: 0.07, feedback: 0.4, mix: 0.4, tail: 0.3), Synth.window(g.wash(0.6, lp: 3500, hp: 500, wobble: 1.5, rate: 8, gain: 0.35)))
        case .dragonGrowl:
            return Synth.mix(g.formant(1.8, f0: 75 * p, f1: 52 * p, formants: [(190, 4, 1), (480, 5, 0.6), (1100, 7, 0.3)], breath: 0.3, vib: 0.05, vibRate: 3, attack: 0.15, release: 0.5, growl: 0.7, gain: 1.6), g.rumble(1.8, f: 40, attack: 0.1, decay: 0.9, gain: 2.2))
        case .dragonFlap:
            var w = g.wash(0.6, lp: 450, hp: 40, wobble: 0.5, rate: 5, gain: 1.5)
            for i in 0..<w.count { w[i] *= sinf(Float(i) / Float(w.count) * .pi) }
            return Synth.mix(w, g.burst(0.25, lp: 200, hp: 25, attack: 0.03, decay: 0.08, gain: 2), at: g.frames(0.25))
        case .dragonShoot:
            return Synth.mix(g.burst(1.0, lp: 1800 * p, hp: 100, attack: 0.02, decay: 0.35, gain: 2.0), g.formant(0.8, f0: 400 * p, f1: 150 * p, formants: [(600, 5, 1), (1500, 7, 0.5)], breath: 0.5, attack: 0.02, release: 0.3, growl: 0.5, gain: 0.8))
        case .dragonDeath:
            var out = g.formant(3.5, f0: 90 * p, f1: 40 * p, formants: [(200, 4, 1), (500, 5, 0.6), (1200, 7, 0.3)], breath: 0.35, vib: 0.08, vibRate: 2.5, attack: 0.2, release: 1.2, growl: 0.8, gain: 1.6)
            out = Synth.mix(out, g.rumble(3.5, f: 38, attack: 0.3, decay: 1.6, gain: 2.5))
            return Synth.mix(out, g.burst(2.0, lp: 250, hp: 20, attack: 0.003, decay: 0.5, gain: 3), at: g.frames(2.8))
        case .crystalBreak:
            return Synth.mix(Synth.mix(g.material(.glass, pitch: p * 0.8, scale: 1.5, gain: 0.7), g.fm(1.0, f: 660 * p, ratio: 2.5, index: 2, decay: 0.4, gain: 0.4)), g.burst(1.2, lp: 300, hp: 25, attack: 0.003, decay: 0.3, gain: 3))
        case .witherSpawn:
            return Synth.mix(g.formant(3.0, f0: 80 * p, f1: 220 * p, formants: [(300, 4, 1), (800, 6, 0.5), (1600, 8, 0.2)], breath: 0.3, vib: 0.5, vibRate: 4, attack: 0.5, release: 0.8, growl: 0.5, gain: 1.4), g.burst(3.0, lp: 400, hp: 30, attack: 1.5, decay: 1.4, gain: 0.8))
        case .witherShoot: return Synth.mix(g.burst(0.4, lp: 1500 * p, hp: 100, attack: 0.01, decay: 0.2, gain: 1.2), g.voice(0.3, f0: 300 * p, f1: 120 * p, vib: 0.1, lp: 1200, gain: 0.5))
        case .witherDeath:
            var out = g.formant(2.8, f0: 160 * p, f1: 60 * p, formants: [(300, 4, 1), (750, 5, 0.5), (1700, 7, 0.2)], breath: 0.4, vib: 0.2, vibRate: 3, attack: 0.1, release: 1.0, growl: 0.6, gain: 1.5)
            out = Synth.mix(out, g.burst(2.8, lp: 600, hp: 50, attack: 0.5, decay: 1.2, gain: 0.6))
            return Synth.mix(out, g.burst(2.0, lp: 250, hp: 20, attack: 0.003, decay: 0.5, gain: 3), at: g.frames(2.2))
        case .wardenHeartbeat:
            let lub = Synth.mix(g.modes(0.25, [(48 * p, 1.2, 0.09)]), g.burst(0.08, lp: 150, hp: 20, decay: 0.03, gain: 1.2))
            return Synth.mix(lub, Synth.scaled(lub, 0.7), at: g.frames(0.22))
        case .wardenRoar:
            return Synth.mix(Synth.mix(g.formant(2.2, f0: 60 * p, f1: 45 * p, formants: [(180, 4, 1), (450, 5, 0.6), (1100, 7, 0.3)], breath: 0.4, vib: 0.05, vibRate: 3, attack: 0.1, release: 0.6, growl: 0.8, gain: 1.7),
                                       g.rumble(2.2, f: 35, attack: 0.05, decay: 1.0, gain: 2.5)), g.burst(2.0, lp: 3000, hp: 400, attack: 0.1, decay: 0.8, gain: 0.35))
        case .wardenSonicCharge:
            var out: [Float] = []
            for k in 0..<5 {
                let kf: Float = Float(k)
                let dur: Float = 1.7 - 0.2 * kf
                let base: Float = 120 * powf(1.5, kf) * p
                let gain: Float = 0.25 / (kf + 1)
                let t = g.tone(dur, f0: base, f1: base * 2, wave: .sine, attack: 0.3, release: 0.2, vib: 0.03, vibRate: 8, gain: gain)
                out = Synth.mix(out, t, at: g.frames(0.2 * kf))
            }
            return Synth.mix(out, g.wash(1.7, lp: 2500, hp: 300, wobble: 1, rate: 6, gain: 0.3))
        case .wardenSonicBoom:
            return Synth.mix(Synth.mix(g.burst(1.2, lp: 300 * p, hp: 20, attack: 0.002, decay: 0.35, gain: 4), g.tone(0.8, f0: 90 * p, f1: 35 * p, wave: .sine, attack: 0.002, release: 0.5, gain: 0.8)), g.burst(0.5, lp: 6000, hp: 1500, decay: 0.1, gain: 0.8))
        case .wardenEmerge:
            var out = g.rumble(3.0, f: 55, attack: 0.3, decay: 1.4, gain: 2.0)
            out = Synth.mix(out, g.grains(30, spread: 2.5, lp: 1800, hp: 200, decay: 0.02, gain: 0.8))
            return Synth.mix(out, g.formant(1.2, f0: 55 * p, f1: 45 * p, formants: [(180, 4, 1), (450, 5, 0.5)], breath: 0.4, attack: 0.3, release: 0.5, growl: 0.8, gain: 1.2), at: g.frames(1.5))
        case .wardenDig: return Synth.mix(g.rumble(1.6, f: 60, attack: 0.1, decay: 0.7, gain: 1.6), g.grains(20, spread: 1.3, lp: 1500, hp: 200, decay: 0.02, gain: 0.8))
        case .wardenSniff: return g.repeated({ g in g.burst(0.3, lp: 1400, hp: 200, attack: 0.08, decay: 0.1, gain: 1.0) }, times: 2, interval: 0.4, jitter: 0.05)
        case .elderCurse:
            let v = g.formant(2.5, f0: 220 * p, f1: 80 * p, formants: [(500, 6, 1), (1200, 8, 0.5), (2600, 10, 0.2)], breath: 0.15, vib: 0.2, vibRate: 5, attack: 0.3, release: 1.0, gain: 1.1)
            return Synth.lowpass(Synth.echo(v, delay: 0.21, feedback: 0.5, mix: 0.45, tail: 1.5), 1500)
        case .guardianLaser:
            let t = g.tone(1.5, f0: 300 * p, f1: 2500 * p, wave: .sine, attack: 0.05, release: 0.3, vib: 0.08, vibRate: 15, gain: 0.35)
            return Synth.mix(t, g.wash(1.5, lp: 4000, hp: 600, wobble: 1.5, rate: 10, gain: 0.25))
        case .villagerYes:
            return Synth.mix(g.formant(0.18, f0: 190 * p, f1: 220 * p, formants: [(280, 5, 1), (900, 7, 0.35)], breath: 0.05, attack: 0.02, release: 0.05, gain: 1.1),
                             g.formant(0.3, f0: 240 * p, f1: 320 * p, formants: [(300, 5, 1), (950, 7, 0.35)], breath: 0.05, vib: 0.03, attack: 0.02, release: 0.1, gain: 1.2), at: g.frames(0.2))
        case .villagerNo:
            return Synth.mix(g.formant(0.2, f0: 230 * p, f1: 200 * p, formants: [(280, 5, 1), (900, 7, 0.35)], breath: 0.05, attack: 0.02, release: 0.05, gain: 1.1),
                             g.formant(0.3, f0: 200 * p, f1: 150 * p, formants: [(270, 5, 1), (850, 7, 0.35)], breath: 0.05, vib: 0.03, attack: 0.02, release: 0.12, gain: 1.2), at: g.frames(0.22))
        case .villagerTrade:
            return Synth.mix(g.formant(0.3, f0: 200 * p, f1: 260 * p, formants: [(280, 5, 1), (900, 7, 0.35)], breath: 0.05, vib: 0.03, attack: 0.02, release: 0.1, gain: 1.1), g.modes(0.25, [(1500, 0.3, 0.06), (2100, 0.2, 0.05)]), at: g.frames(0.25))
        case .villagerCelebrate:
            var out: [Float] = []
            for k in 0..<4 { out = Synth.mix(out, g.formant(0.25, f0: (200 + 40 * Float(k)) * p, f1: (240 + 40 * Float(k)) * p, formants: [(300, 5, 1), (950, 7, 0.35)], breath: 0.05, vib: 0.05, attack: 0.02, release: 0.08, gain: 1.1), at: g.frames(0.28 * Float(k))) }
            return out
        case .villagerWork(let prof):
            switch prof {
            case 0: return Synth.mix(g.modes(0.6, [(1240 * p, 0.5, 0.25), (2600 * p, 0.3, 0.15), (3900 * p, 0.15, 0.08)]), g.burst(0.04, lp: 8000, hp: 2000, decay: 0.015, gain: 0.8))                 // armorer: hammer on metal
            case 1: return Synth.mix(g.material(.wood, pitch: p * 0.8, scale: 1.0, gain: 0.6), g.burst(0.2, lp: 700, hp: 80, attack: 0.01, decay: 0.05, gain: 1.4))                                                 // butcher: chop
            case 2: return Synth.mix(g.burst(0.25, lp: 3500 * p, hp: 800, attack: 0.03, decay: 0.06, gain: 0.7), g.crackle(0.4, density: 90, f: 3000, q: 3, gain: 0.5), at: g.frames(0.2))                        // cartographer: paper + pen
            case 3: return Synth.mix(g.bubbles(0.7, count: 8, fLo: 500 * p, fHi: 1600 * p, len: 0.05, gain: 0.5), g.grains(6, spread: 0.5, lp: 3000, hp: 600, decay: 0.03, gain: 0.5))                           // cleric: brewing
            case 4: return Synth.mix(g.material(.dirt, pitch: p, scale: 1.2, gain: 0.6), g.material(.plant, pitch: p, scale: 0.8, gain: 0.4), at: g.frames(0.15))                                                  // farmer: hoe
            case 5: return Synth.mix(g.burst(0.35, lp: 1600 * p, hp: 200, attack: 0.005, decay: 0.08, gain: 1.1), g.bubbles(0.3, count: 5, fLo: 500, fHi: 1500, len: 0.04, gain: 0.4))                            // fisherman: splash
            case 6: return Synth.mix(g.modes(0.25, [(220 * p, 0.5, 0.05), (440 * p, 0.2, 0.03)]), g.material(.wood, pitch: p * 1.3, scale: 0.4, gain: 0.4), at: g.frames(0.12))                                  // fletcher: string + wood
            case 7: return g.repeated({ g in g.burst(0.2, lp: 1200, hp: 200, attack: 0.02, decay: 0.05, gain: 1.0) }, times: 3, interval: 0.16)                                                                     // leatherworker: leather rub
            case 8: return g.repeated({ g in g.burst(0.18, lp: 3500, hp: 800, attack: 0.03, decay: 0.05, gain: 0.7) }, times: 2, interval: 0.3)                                                                    // librarian: pages
            case 9: return g.repeated({ g in Synth.mix(g.grains(4, spread: 0.02, lp: 4000, hp: 900, decay: 0.008, gain: 1.0), g.modes(0.1, [(2400, 0.3, 0.02)])) }, times: 3, interval: 0.2)                        // mason: chisel
            case 10: return g.repeated({ g in Synth.mix(g.modes(0.12, [(2400, 0.4, 0.02), (4200, 0.2, 0.015)]), g.burst(0.06, lp: 6000, hp: 1500, decay: 0.01, gain: 0.7)) }, times: 2, interval: 0.22)             // shepherd: shears
            case 11: return g.repeated({ g in Synth.mix(g.modes(0.3, [(1100, 0.5, 0.08), (2300, 0.3, 0.06)]), g.burst(0.06, lp: 5000, hp: 900, decay: 0.012, gain: 0.7)) }, times: 2, interval: 0.3)              // toolsmith: hammer
            default: return Synth.mix(g.wash(0.45, lp: 3500 * p, hp: 800, wobble: 0.8, rate: 12, gain: 0.5), g.crackle(0.45, density: 60, f: 4000, q: 3, gain: 1.0))                                              // weaponsmith: grindstone
            }
        case .zombieBreakDoor: return Synth.mix(g.repeated({ g in g.material(.wood, pitch: 0.8, scale: 1.2, gain: 0.6) }, times: 3, interval: 0.2), g.formant(0.6, f0: 95 * p, f1: 70 * p, formants: [(300, 4, 1), (720, 5, 0.5)], breath: 0.3, growl: 0.5, gain: 0.8))
        case .zombieInfect: return Synth.mix(g.formant(0.7, f0: 110 * p, f1: 80 * p, formants: [(300, 4, 1), (720, 5, 0.5)], breath: 0.4, vib: 0.1, growl: 0.6, gain: 1.2), g.burst(0.5, lp: 4000, hp: 1200, attack: 0.05, decay: 0.2, gain: 0.5))
        case .zombieCure: return Synth.mix(g.tone(1.0, f0: 220 * p, f1: 660 * p, wave: .sine, attack: 0.1, release: 0.4, vib: 0.05, vibRate: 6, gain: 0.3), g.burst(1.0, lp: 7000, hp: 2500, attack: 0.1, decay: 0.4, gain: 0.5))
        case .phantomSwoop:
            var w = g.wash(0.8, lp: 2500, hp: 300, wobble: 0.8, rate: 8, gain: 0.7)
            for i in 0..<w.count { w[i] *= sinf(Float(i) / Float(w.count) * .pi) }
            return Synth.mix(w, g.formant(0.5, f0: 1300 * p, f1: 800 * p, formants: [(1500, 8, 1), (3000, 10, 0.5)], breath: 0.3, vib: 0.2, vibRate: 9, attack: 0.02, release: 0.15, gain: 0.8), at: g.frames(0.2))
        case .beeSting: return Synth.mix(Synth.lowpass(g.tone(0.25, f0: 260 * p, f1: 330 * p, wave: .saw, attack: 0.01, release: 0.05, vib: 0.1, vibRate: 12, gain: 0.5), 2000), g.modes(0.08, [(2600, 0.3, 0.015)]), at: g.frames(0.2))
        case .beePollinate: return Synth.lowpass(g.tone(0.9, f0: 230 * p, f1: 220 * p, wave: .saw, attack: 0.1, release: 0.2, vib: 0.08, vibRate: 3, gain: 0.3), 1500)
        case .allayItem:
            var out: [Float] = []
            for k in 0..<3 { out = Synth.mix(out, g.fm(0.35, f: 1400 * powf(1.26, Float(k)) * p, ratio: 2, index: 0.7, decay: 0.15, gain: 0.3), at: g.frames(Float(k) * 0.08)) }
            return out
        case .foxSniff: return g.repeated({ g in g.burst(0.12, lp: 2500, hp: 500, attack: 0.03, decay: 0.04, gain: 0.8) }, times: 2, interval: 0.15)
        case .catPurr:
            var out = Synth.lowpass(g.tone(1.2, f0: 25 * p, f1: 26 * p, wave: .square, attack: 0.1, release: 0.3, gain: 0.6), 500)
            out = Synth.mix(out, g.wash(1.2, lp: 700, hp: 100, wobble: 0.5, rate: 25, gain: 0.3))
            return out
        case .wolfPant: return g.repeated({ g in g.burst(0.16, lp: 1800, hp: 300, attack: 0.03, decay: 0.05, gain: 0.8) }, times: 4, interval: 0.2)
        case .parrotMimic:
            var out: [Float] = []
            for k in 0..<4 { let f = (1400 + 500 * Float(k % 3)) * p; out = Synth.mix(out, g.tone(0.09, f0: f, f1: f * 1.3, wave: .sine, attack: 0.005, release: 0.03, vib: 0.1, vibRate: 30, gain: 0.5), at: g.frames(Float(k) * 0.11)) }
            return out
        case .dolphinJump: return Synth.mix(g.burst(0.4, lp: 1600, hp: 200, attack: 0.01, decay: 0.1, gain: 1.2), g.tone(0.25, f0: 1800 * p, f1: 2600 * p, wave: .sine, attack: 0.01, release: 0.08, vib: 0.1, vibRate: 25, gain: 0.35), at: g.frames(0.1))
        case .turtleEggCrack: return Synth.mix(g.grains(5, spread: 0.05, lp: 4000 * p, hp: 900, decay: 0.008, gain: 1.0), g.burst(0.12, lp: 1500, hp: 300, decay: 0.03, gain: 0.5))
        case .frogTongue: return Synth.mix(g.burst(0.1, lp: 900 * p, hp: 100, attack: 0.005, decay: 0.03, gain: 2), g.bubbles(0.1, count: 1, fLo: 500, fHi: 800, len: 0.05, gain: 0.5))
        case .goatRam: return Synth.mix(g.burst(0.25, lp: 400, hp: 30, decay: 0.06, gain: 3), g.formant(0.3, f0: 360 * p, f1: 300 * p, formants: [(620, 6, 1), (1350, 7, 0.6)], breath: 0.15, vib: 0.09, vibRate: 9, attack: 0.01, release: 0.08, gain: 0.9), at: g.frames(0.05))
        case .breezeShoot:
            var w = g.wash(0.5, lp: 3000 * p, hp: 300, wobble: 1, rate: 10, gain: 1.0)
            for i in 0..<w.count { w[i] *= expf(-Float(i) / Synth.sr / 0.15) }
            return Synth.mix(w, g.tone(0.4, f0: 700 * p, f1: 200 * p, wave: .sine, attack: 0.005, release: 0.25, gain: 0.3))
        default: return g.modes(0.05, [(800, 0.3, 0.01)])
        }
    }
}
