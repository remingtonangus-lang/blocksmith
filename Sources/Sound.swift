import Foundation
import AVFoundation
import simd

// Every sound is synthesized at launch (noise bursts, filters, damped sines) — no asset files.
// SoundBank is pure DSP (usable headless: `--sounds` writes WAVs); SoundEngine plays it with AVAudioEngine.

enum SoundMat: Int, CaseIterable { case stone, dirt, sand, wood, plant, glass, snow }

enum Snd: Hashable {
    case breakBlock(SoundMat)
    case place(SoundMat)
    case step(SoundMat)
    case splash, land, hurt, eat, click, open, mobCow, mobSheep, mobChicken, pickup, dig, attack, burp
    case mobPig, mobZombie, mobSkeleton, creeperHiss, mobSpider, mobVoidwalker, mobSlime, bow, explode, arrowHit, fizz, xp, levelUp
    case mobWailer, mobCinderwisp, mobBoarling, mobUndeadBoarling, fireball, mobVillager, mobGolem
    case anvil, brew, enchant, drink, glassBreak
    case mobBlight, witherSpawn, witherShoot, mobVex, mobRavager, evokerCast, bell, raidHorn, fangs, rain, thunder
    case mobWolf, mobCat, mobHorse, mobLlama, mobBee, mobWarden, goatHorn
    case fireworkLaunch, fireworkBlast, fireworkBlastLarge, fireworkTwinkle, caveAmbience
    case note(Int, Int)            // note block: instrument, pitch 0...24 (made on demand)
    case gun(Int)                  // firearms, deck guns, alarms (Guns.swift)
}

func soundMat(_ id: BlockID) -> SoundMat { Blocks.def(id).sound }

struct SoundBank {
    static let rate: Double = 44100
    static let variants = 3
    private(set) var clips: [Snd: [[Float]]] = [:]

    static var allSounds: [Snd] {
        var s: [Snd] = []
        for m in SoundMat.allCases { s += [.breakBlock(m), .place(m), .step(m)] }
        return s + [.splash, .land, .hurt, .eat, .click, .open, .mobCow, .mobSheep, .mobChicken, .pickup, .dig, .attack, .burp,
                    .mobPig, .mobZombie, .mobSkeleton, .creeperHiss, .mobSpider, .mobVoidwalker, .mobSlime, .bow, .explode, .arrowHit, .fizz, .xp, .levelUp,
                    .mobWailer, .mobCinderwisp, .mobBoarling, .mobUndeadBoarling, .fireball, .mobVillager, .mobGolem,
                    .anvil, .brew, .enchant, .drink, .glassBreak,
                    .mobBlight, .witherSpawn, .witherShoot, .mobVex, .mobRavager, .evokerCast, .bell, .raidHorn, .fangs, .rain, .thunder,
                    .mobWolf, .mobCat, .mobHorse, .mobLlama, .mobBee, .mobWarden, .goatHorn, .fireworkLaunch, .fireworkBlast, .fireworkBlastLarge, .fireworkTwinkle, .caveAmbience] + Guns.sounds
    }

    init() {
        for (k, snd) in SoundBank.allSounds.enumerated() {
            var vs: [[Float]] = []
            for v in 0..<SoundBank.variants {
                var g = Synth(seed: UInt64(v + 1) &* 0x9E3779B97F4A7C15 &+ UInt64(k) &* 0x2545F4914F6CDD1D)
                vs.append(g.render(snd, pitch: 1 + (Float(v) - 1) * 0.07))
            }
            clips[snd] = vs
        }
    }

    func clip(_ s: Snd, variant: Int) -> [Float] {
        guard let vs = clips[s], !vs.isEmpty else { return [] }
        return vs[variant % vs.count]
    }

    // 16-bit mono WAV (used by the headless harness to check the synth).
    static func writeWAV(_ samples: [Float], to path: String) {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let n = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + n)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(n)
        for x in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, x)) * 32767))) }
        try? d.write(to: URL(fileURLWithPath: path))
    }
}

// Tiny DSP toolkit.
struct Synth {
    var state: UInt64
    init(seed: UInt64) { state = seed | 1 }

    mutating func noise() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
    }

    static let sr = Float(SoundBank.rate)
    func frames(_ seconds: Float) -> Int { Int(seconds * Synth.sr) }

    // Noise burst through a one-pole low-pass (lp Hz) then high-pass (hp Hz), with attack/decay envelope.
    mutating func burst(_ dur: Float, lp: Float, hp: Float, attack: Float = 0.002, decay: Float, gain: Float = 1) -> [Float] {
        let n = frames(dur)
        var out = [Float](repeating: 0, count: n)
        let a = 1 - expf(-2 * .pi * lp / Synth.sr)
        let b = 1 - expf(-2 * .pi * hp / Synth.sr)
        var lpS: Float = 0, hpS: Float = 0
        for i in 0..<n {
            let t = Float(i) / Synth.sr
            let env = min(1, t / attack) * expf(-t / decay)
            lpS += a * (noise() - lpS)
            hpS += b * (lpS - hpS)
            out[i] = (lpS - hpS) * env * gain
        }
        return out
    }

    // Sum of exponentially damped sines (knocks, rings, pings).
    func modes(_ dur: Float, _ partials: [(freq: Float, amp: Float, decay: Float)]) -> [Float] {
        let n = frames(dur)
        var out = [Float](repeating: 0, count: n)
        for p in partials {
            let w = 2 * Float.pi * p.freq / Synth.sr
            for i in 0..<n {
                let t = Float(i) / Synth.sr
                out[i] += sinf(w * Float(i)) * p.amp * expf(-t / p.decay)
            }
        }
        return out
    }

    // Buzzy voiced tone with vibrato and a low-pass "mouth" (mob calls, hurt grunt).
    mutating func voice(_ dur: Float, f0: Float, f1: Float, vib: Float, lp: Float, gain: Float) -> [Float] {
        let n = frames(dur)
        var out = [Float](repeating: 0, count: n)
        var phase: Float = 0, y1: Float = 0, y2: Float = 0
        let a = 1 - expf(-2 * .pi * lp / Synth.sr)
        for i in 0..<n {
            let t = Float(i) / Synth.sr, k = t / dur
            let f = (f0 + (f1 - f0) * k) * (1 + vib * sinf(2 * .pi * 5.5 * t))
            phase += f / Synth.sr
            phase -= floorf(phase)
            let saw = phase * 2 - 1 + noise() * 0.08
            y1 += a * (saw - y1)
            y2 += a * (y1 - y2)
            let env = min(1, t / 0.03) * min(1, (dur - t) / 0.08)
            out[i] = y2 * env * gain
        }
        return out
    }

    static func mix(_ a: [Float], _ b: [Float], at offset: Int = 0) -> [Float] {
        var out = a
        if out.count < offset + b.count { out += [Float](repeating: 0, count: offset + b.count - out.count) }
        for i in 0..<b.count { out[offset + i] += b[i] }
        return out
    }

    // Crunchy material: several short grains spread over `spread` seconds.
    mutating func grains(_ count: Int, spread: Float, lp: Float, hp: Float, decay: Float, gain: Float) -> [Float] {
        var out = [Float](repeating: 0, count: frames(spread + decay * 6))
        for _ in 0..<count {
            let at = frames((noise() * 0.5 + 0.5) * spread)
            let g = burst(decay * 6, lp: lp * (0.8 + 0.4 * abs(noise())), hp: hp, attack: 0.001, decay: decay, gain: gain * (0.6 + 0.4 * abs(noise())))
            out = Synth.mix(out, g, at: at)
        }
        return out
    }

    mutating func material(_ m: SoundMat, pitch p: Float, scale: Float, gain: Float) -> [Float] {
        switch m {
        case .stone:
            return grains(Int(9 * scale), spread: 0.09 * scale, lp: 3200 * p, hp: 500, decay: 0.012, gain: gain * 1.6)
        case .dirt:
            return Synth.mix(burst(0.25 * scale, lp: 900 * p, hp: 60, decay: 0.05 * scale, gain: gain * 2.2),
                             grains(Int(5 * scale), spread: 0.08 * scale, lp: 1000 * p, hp: 120, decay: 0.01, gain: gain * 0.5))
        case .sand, .snow:
            let lp: Float = m == .sand ? 4200 : 2600
            return grains(Int(14 * scale), spread: 0.14 * scale, lp: lp * p, hp: 900, decay: 0.008, gain: gain * 0.9)
        case .wood:
            let knock = modes(0.3 * scale, [(190 * p, 0.7, 0.05), (410 * p, 0.45, 0.035), (870 * p, 0.2, 0.02)])
            return Synth.mix(knock.map { $0 * gain * 1.3 }, burst(0.05, lp: 3000, hp: 400, decay: 0.008, gain: gain * 0.6))
        case .plant:
            return grains(Int(16 * scale), spread: 0.16 * scale, lp: 6000 * p, hp: 1800, decay: 0.01, gain: gain * 0.9)
        case .glass:
            var out = burst(0.25, lp: 9000, hp: 2500, decay: 0.04, gain: gain * 0.8)
            for _ in 0..<Int(7 * scale) {
                let f = (2200 + 3800 * abs(noise())) * p
                let ping = modes(0.3, [(f, 0.25, 0.04 + 0.05 * abs(noise()))])
                out = Synth.mix(out, ping.map { $0 * gain }, at: frames(abs(noise()) * 0.08))
            }
            return out
        }
    }

    mutating func render(_ s: Snd, pitch p: Float) -> [Float] {
        var out: [Float]
        switch s {
        case .breakBlock(let m): out = material(m, pitch: p, scale: 1.4, gain: 0.55)
        case .place(let m): out = material(m, pitch: p * 1.05, scale: 0.8, gain: 0.45)
        case .step(let m): out = material(m, pitch: p * 0.95, scale: 0.45, gain: 0.25)
        case .splash:
            out = burst(0.55, lp: 1400 * p, hp: 150, attack: 0.01, decay: 0.15, gain: 1.2)
            out = Synth.mix(out, grains(20, spread: 0.3, lp: 5000, hp: 1500, decay: 0.01, gain: 0.3))
        case .land: out = burst(0.18, lp: 300 * p, hp: 30, decay: 0.04, gain: 3)
        case .hurt:
            out = Synth.mix(voice(0.22, f0: 260 * p, f1: 150 * p, vib: 0.03, lp: 1400, gain: 1.4),
                            burst(0.1, lp: 1200, hp: 200, decay: 0.03, gain: 0.5))
        case .eat:
            out = []
            for k in 0..<3 {
                out = Synth.mix(out, grains(6, spread: 0.04, lp: 2500 * p, hp: 300, decay: 0.012, gain: 0.9), at: frames(Float(k) * 0.16))
            }
        case .click: out = modes(0.05, [(1100 * p, 0.35, 0.008), (2200 * p, 0.1, 0.004)])
        case .pickup: out = Synth.mix(modes(0.09, [(1500 * p, 0.3, 0.02)]), modes(0.08, [(2100 * p, 0.25, 0.02)]), at: frames(0.03))
        case .dig: out = burst(0.06, lp: 2500 * p, hp: 300, decay: 0.012, gain: 0.8)
        case .attack: out = burst(0.12, lp: 1800 * p, hp: 200, decay: 0.03, gain: 1.4)
        case .burp: out = voice(0.3, f0: 120 * p, f1: 90 * p, vib: 0.1, lp: 900, gain: 0.8)
        case .mobPig: out = Synth.mix(voice(0.25, f0: 180 * p, f1: 140 * p, vib: 0.15, lp: 900, gain: 1), voice(0.2, f0: 200 * p, f1: 150 * p, vib: 0.1, lp: 800, gain: 0.8), at: frames(0.28))
        case .mobZombie: out = Synth.mix(voice(0.9, f0: 95 * p, f1: 70 * p, vib: 0.08, lp: 600, gain: 1.3), burst(0.9, lp: 700, hp: 80, attack: 0.1, decay: 0.4, gain: 0.3))
        case .mobSkeleton: out = grains(10, spread: 0.35, lp: 3500 * p, hp: 1200, decay: 0.006, gain: 1.2)
        case .creeperHiss: out = burst(1.5, lp: 7000, hp: 2500, attack: 0.3, decay: 1.2, gain: 1.4)
        case .mobSpider: out = Synth.mix(burst(0.5, lp: 4000 * p, hp: 1500, attack: 0.05, decay: 0.2, gain: 1), grains(8, spread: 0.4, lp: 2000, hp: 400, decay: 0.01, gain: 0.8))
        case .mobVoidwalker: out = voice(1.0, f0: 300 * p, f1: 120 * p, vib: 0.3, lp: 1500, gain: 1.1)
        case .mobSlime: out = burst(0.2, lp: 500 * p, hp: 60, decay: 0.06, gain: 2.5)
        case .bow: out = Synth.mix(modes(0.25, [(220 * p, 0.5, 0.05), (440 * p, 0.2, 0.03)]), burst(0.15, lp: 3000, hp: 800, decay: 0.03, gain: 0.5))
        case .explode: out = Synth.mix(burst(2.0, lp: 250 * p, hp: 20, attack: 0.003, decay: 0.5, gain: 4), burst(1.2, lp: 2500, hp: 200, decay: 0.2, gain: 1.2))
        case .arrowHit: out = Synth.mix(modes(0.15, [(160 * p, 0.6, 0.03)]), burst(0.05, lp: 2000, hp: 300, decay: 0.01, gain: 0.6))
        case .fizz: out = burst(0.6, lp: 8000, hp: 3000, attack: 0.02, decay: 0.25, gain: 0.9)
        case .xp: out = modes(0.2, [(1760 * p, 0.25, 0.05), (2637 * p, 0.12, 0.04)])
        case .levelUp: out = Synth.mix(Synth.mix(modes(0.5, [(523, 0.3, 0.15)]), modes(0.5, [(659, 0.3, 0.15)]), at: frames(0.1)), modes(0.8, [(784, 0.3, 0.3)]), at: frames(0.2))
        case .open: out = Synth.mix(modes(0.12, [(660 * p, 0.25, 0.03)]), modes(0.12, [(990 * p, 0.2, 0.03)]), at: frames(0.05))
        case .mobWailer: out = Synth.mix(voice(1.4, f0: 520 * p, f1: 260 * p, vib: 0.35, lp: 2400, gain: 1.0), burst(1.2, lp: 1800, hp: 400, attack: 0.2, decay: 0.8, gain: 0.25))
        case .mobCinderwisp: out = Synth.mix(burst(1.0, lp: 1200 * p, hp: 90, attack: 0.15, decay: 0.7, gain: 1.4), grains(14, spread: 0.8, lp: 3000, hp: 800, decay: 0.01, gain: 0.5))
        case .mobBoarling: out = Synth.mix(voice(0.35, f0: 210 * p, f1: 160 * p, vib: 0.2, lp: 1100, gain: 1), voice(0.3, f0: 240 * p, f1: 170 * p, vib: 0.15, lp: 900, gain: 0.8), at: frames(0.3))
        case .mobUndeadBoarling: out = Synth.mix(voice(0.8, f0: 160 * p, f1: 110 * p, vib: 0.25, lp: 800, gain: 1.2), burst(0.8, lp: 600, hp: 80, attack: 0.1, decay: 0.4, gain: 0.3))
        case .anvil:
            // Struck metal: inharmonic partials with a sharp attack.
            out = Synth.mix(modes(0.9, [(830 * p, 0.5, 0.35), (1970 * p, 0.3, 0.25), (3120 * p, 0.2, 0.12), (4410 * p, 0.12, 0.08)]),
                            burst(0.05, lp: 9000, hp: 2000, attack: 0.001, decay: 0.02, gain: 0.8))
        case .brew: out = grains(10, spread: 0.6, lp: 3000 * p, hp: 600, decay: 0.03, gain: 0.7)
        case .enchant: out = Synth.mix(modes(1.0, [(1320 * p, 0.2, 0.5), (1980 * p, 0.15, 0.4)]), modes(1.0, [(1760 * p, 0.15, 0.5)]), at: frames(0.12))
        case .drink: out = grains(6, spread: 0.5, lp: 900 * p, hp: 150, decay: 0.05, gain: 1.0)
        case .glassBreak: out = Synth.mix(burst(0.3, lp: 12000, hp: 3000, attack: 0.001, decay: 0.12, gain: 1.0), grains(12, spread: 0.25, lp: 10000, hp: 4000, decay: 0.01, gain: 0.6))
        case .mobBlight: out = Synth.mix(voice(1.2, f0: 140 * p, f1: 90 * p, vib: 0.4, lp: 900, gain: 1.2), burst(1.0, lp: 700, hp: 60, attack: 0.2, decay: 0.6, gain: 0.5))
        case .witherSpawn:
            out = Synth.mix(voice(3.0, f0: 80 * p, f1: 220 * p, vib: 0.5, lp: 1200, gain: 1.4), burst(3.0, lp: 400, hp: 30, attack: 1.5, decay: 1.4, gain: 0.8))
        case .witherShoot: out = Synth.mix(burst(0.4, lp: 1500 * p, hp: 100, attack: 0.01, decay: 0.2, gain: 1.2), voice(0.3, f0: 300 * p, f1: 120 * p, vib: 0.1, lp: 1200, gain: 0.5))
        case .mobVex: out = voice(0.4, f0: 900 * p, f1: 1300 * p, vib: 0.5, lp: 5000, gain: 0.7)
        case .mobRavager: out = Synth.mix(voice(0.9, f0: 110 * p, f1: 70 * p, vib: 0.3, lp: 700, gain: 1.4), burst(0.7, lp: 500, hp: 40, attack: 0.1, decay: 0.4, gain: 0.6))
        case .evokerCast: out = Synth.mix(modes(1.0, [(440 * p, 0.2, 0.5), (660 * p, 0.15, 0.4)]), grains(8, spread: 0.8, lp: 4000, hp: 1000, decay: 0.05, gain: 0.4))
        case .bell: out = modes(2.5, [(880, 0.5, 1.8), (2094.4, 0.25, 1.0), (2666.4, 0.15, 0.7), (440, 0.2, 1.5)])
        case .caveAmbience: out = Synth.mix(voice(4.5, f0: 55 * p, f1: 41 * p, vib: 0.3, lp: 300, gain: 0.9), burst(4.5, lp: 500, hp: 60, attack: 1.2, decay: 2.5, gain: 0.5))
        case .fireworkLaunch: out = Synth.mix(burst(1.1, lp: 3000, hp: 400, attack: 0.05, decay: 0.6, gain: 0.9), voice(0.9, f0: 900, f1: 1800, vib: 0, lp: 3000, gain: 0.25))
        case .fireworkBlast: out = Synth.mix(burst(1.4, lp: 600, hp: 40, attack: 0.002, decay: 0.35, gain: 3), burst(0.6, lp: 6000, hp: 1500, decay: 0.08, gain: 0.8))
        case .fireworkBlastLarge: out = Synth.mix(burst(2.4, lp: 350, hp: 25, attack: 0.002, decay: 0.7, gain: 4), burst(0.8, lp: 5000, hp: 1000, decay: 0.12, gain: 1))
        case .fireworkTwinkle: out = grains(40, spread: 1.4, lp: 9000, hp: 2500, decay: 0.03, gain: 0.8)
        case .goatHorn: out = Synth.mix(voice(2.6, f0: 220, f1: 196, vib: 0.12, lp: 2200, gain: 1.2), voice(2.6, f0: 330, f1: 294, vib: 0.1, lp: 2000, gain: 0.5))
        case .raidHorn: out = Synth.mix(voice(3.5, f0: 98, f1: 92, vib: 0.08, lp: 1400, gain: 1.4), voice(3.5, f0: 147, f1: 139, vib: 0.08, lp: 1400, gain: 0.8))
        case .fangs: out = Synth.mix(burst(0.25, lp: 3000 * p, hp: 300, attack: 0.005, decay: 0.08, gain: 1.2), modes(0.2, [(180 * p, 0.3, 0.08)]))
        case .rain: out = Synth.mix(burst(1.6, lp: 6000, hp: 1500, attack: 0.3, decay: 1.0, gain: 0.5), grains(60, spread: 1.5, lp: 9000, hp: 3000, decay: 0.004, gain: 0.35))
        case .thunder:
            out = Synth.mix(burst(0.15, lp: 8000, hp: 200, attack: 0.001, decay: 0.08, gain: 1.4), burst(4.0, lp: 220 * p, hp: 20, attack: 0.05, decay: 2.2, gain: 2.2))
        case .mobWolf: out = Synth.mix(voice(0.18, f0: 520 * p, f1: 380 * p, vib: 0.1, lp: 2500, gain: 1), voice(0.18, f0: 500 * p, f1: 360 * p, vib: 0.1, lp: 2500, gain: 0.9), at: frames(0.25))
        case .mobCat: out = voice(0.6, f0: 620 * p, f1: 820 * p, vib: 0.3, lp: 3500, gain: 0.8)
        case .mobHorse: out = Synth.mix(voice(0.9, f0: 700 * p, f1: 380 * p, vib: 0.6, lp: 2800, gain: 1), burst(0.5, lp: 1500, hp: 200, attack: 0.05, decay: 0.3, gain: 0.3))
        case .mobLlama: out = voice(0.5, f0: 330 * p, f1: 260 * p, vib: 0.2, lp: 1500, gain: 0.9)
        case .mobBee: out = modes(0.8, [(230 * p, 0.25, 0.8), (460 * p, 0.12, 0.8), (690 * p, 0.06, 0.8)])
        case .mobWarden: out = Synth.mix(voice(1.4, f0: 60 * p, f1: 45 * p, vib: 0.3, lp: 500, gain: 1.8), burst(1.2, lp: 300, hp: 20, attack: 0.3, decay: 0.8, gain: 1.0))
        case .note(let inst, let n):
            // Pitch 0 = F#3 for the harp family; bass instruments two octaves down, chimes two up.
            let f: Float = 185 * powf(2, Float(n) / 12)
            switch inst {
            case 1: out = modes(0.5, [(f / 4, 0.9, 0.25), (f / 2, 0.3, 0.12)])                                   // bass
            case 2: out = burst(0.18, lp: 5000, hp: 800, attack: 0.002, decay: 0.05, gain: 1.4)                  // snare
            case 3: out = burst(0.08, lp: 12000, hp: 6000, attack: 0.001, decay: 0.02, gain: 1.2)                // hat
            case 4: out = Synth.mix(modes(0.3, [(60 + f / 20, 1.2, 0.08)]), burst(0.05, lp: 800, hp: 40, decay: 0.02, gain: 1)) // bass drum
            case 5: out = modes(1.2, [(f * 2, 0.6, 0.6), (f * 2 * 2.76, 0.25, 0.3), (f * 2 * 5.4, 0.1, 0.15)])  // bell
            case 6: out = voice(0.6, f0: f * 2, f1: f * 2, vib: 0.02, lp: 3000, gain: 0.9)                       // flute
            case 7: out = modes(1.0, [(f * 4, 0.5, 0.5), (f * 4 * 2.4, 0.2, 0.3)])                              // chime
            case 8: out = modes(0.6, [(f / 2, 0.7, 0.3), (f, 0.35, 0.2), (f * 1.5, 0.15, 0.1)])                 // guitar
            case 9: out = modes(0.35, [(f * 4, 0.7, 0.08), (f * 4 * 3.9, 0.2, 0.04)])                           // xylophone
            case 10: out = modes(0.5, [(f, 0.7, 0.25), (f * 3.9, 0.25, 0.12)])                                  // iron xylophone
            case 11: out = modes(0.4, [(f, 0.7, 0.12), (f * 2, 0.35, 0.08), (f * 3, 0.2, 0.05)])                // banjo
            case 12: out = Synth.mix(modes(0.8, [(f, 0.6, 0.35)]), modes(0.8, [(f * 2.01, 0.3, 0.3)]))          // pling
            default: out = modes(0.7, [(f, 0.7, 0.3), (f * 2, 0.25, 0.15), (f * 3, 0.1, 0.08)])                 // harp
            }
        case .mobVillager: out = Synth.mix(voice(0.22, f0: 190 * p, f1: 240 * p, vib: 0.05, lp: 1200, gain: 1), voice(0.25, f0: 230 * p, f1: 170 * p, vib: 0.05, lp: 1100, gain: 0.9), at: frames(0.2))
        case .mobGolem: out = Synth.mix(burst(0.5, lp: 300 * p, hp: 40, attack: 0.05, decay: 0.3, gain: 2), modes(0.4, [(90 * p, 0.4, 0.2), (140 * p, 0.2, 0.15)]))
        case .fireball: out = Synth.mix(burst(0.8, lp: 900 * p, hp: 60, attack: 0.02, decay: 0.3, gain: 2.2), burst(0.5, lp: 5000, hp: 1500, attack: 0.01, decay: 0.2, gain: 0.5))
        case .mobCow: out = voice(0.85, f0: 150 * p, f1: 105 * p, vib: 0.02, lp: 700, gain: 1.3)
        case .mobSheep: out = voice(0.6, f0: 420 * p, f1: 380 * p, vib: 0.09, lp: 1800, gain: 0.9)
        case .gun(let k): out = gunSound(k, p)
        case .mobChicken:
            out = []
            for k in 0..<2 {
                out = Synth.mix(out, voice(0.09, f0: 1100 * p, f1: 800 * p, vib: 0.0, lp: 3500, gain: 0.7), at: frames(Float(k) * 0.13))
            }
        }
        // Normalize peaks to a sane level and de-click the tail.
        var peak: Float = 0
        for x in out { peak = max(peak, abs(x)) }
        if peak > 0.9 { let k = 0.9 / peak; out = out.map { $0 * k } }
        // Voiced sounds are dense; bring their loudness in line with the percussive block sounds.
        let loud: Float
        switch s {
        case .hurt: loud = 0.45
        case .mobCow, .mobSheep, .mobZombie, .mobVoidwalker, .mobPig: loud = 0.32
        case .mobChicken: loud = 0.55
        default: loud = 1
        }
        if loud != 1 { out = out.map { $0 * loud } }
        let fade = min(out.count, frames(0.01))
        for i in 0..<fade { out[out.count - 1 - i] *= Float(i) / Float(max(1, fade)) }
        return out
    }
}

final class SoundEngine {
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Snd: [AVAudioPCMBuffer]] = [:]
    private var next = 0
    private var variant = 0
    var volume: Float = 0.8

    init?() {
        guard let f = AVAudioFormat(standardFormatWithSampleRate: SoundBank.rate, channels: 1) else { return nil }
        format = f
        let bank = SoundBank()
        for s in SoundBank.allSounds {
            var list: [AVAudioPCMBuffer] = []
            for v in 0..<SoundBank.variants {
                let data = bank.clip(s, variant: v)
                guard !data.isEmpty, let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(data.count)),
                      let ch = b.floatChannelData else { continue }
                b.frameLength = AVAudioFrameCount(data.count)
                let dst = ch[0]
                for i in 0..<data.count { dst[i] = data[i] }
                list.append(b)
            }
            buffers[s] = list
        }
        for _ in 0..<12 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: f)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 1
        do { try engine.start() } catch { print("audio disabled: \(error)"); return nil }
        for p in players { p.play() }
    }

    // Plays a sound; with a world position it is attenuated with distance and panned by the listener.
    func play(_ s: Snd, volume v: Float = 1, at pos: V3? = nil, listener: V3 = .zero, yaw: Float = 0) {
        if buffers[s] == nil, case .note = s {
            var g = Synth(seed: 77)
            let data = g.render(s, pitch: 1)
            if let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count)), let ch = b.floatChannelData {
                b.frameLength = AVAudioFrameCount(data.count)
                for i in 0..<data.count { ch[0][i] = data[i] }
                buffers[s] = [b]
            }
        }
        guard let list = buffers[s], !list.isEmpty else { return }
        var gain = v * volume
        var pan: Float = 0
        if let p = pos {
            let rel = p - listener
            let d = simd_length(rel)
            gain *= max(0, 1 - d / 28)
            if gain <= 0.01 { return }
            if d > 0.5 {
                let right = V3(cosf(yaw), 0, -sinf(yaw))
                pan = simd_clamp(simd_dot(rel / d, right), -1, 1) * 0.8
            }
        }
        let node = players[next]
        next = (next + 1) % players.count
        variant += 1
        node.volume = gain
        node.pan = pan
        node.scheduleBuffer(list[variant % list.count], at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }
}
