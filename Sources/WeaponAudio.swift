import Foundation
import simd

// Firearm, fortress-gun and soldier audio (all synthesized). The `.gun(k)` slots keep the numbering the
// gun code uses (Guns.swift): 0 rifle, 1 chatter gun (SMG), 2 shotgun, 3 farsight (sniper), 4 rocket,
// 5 arc lance (energy heavy), 6 reload, 7 dry fire, 8 ricochet, 9 deck gun, 10 alarm, 11 radio call,
// 12 turret whine. The extra cases add per-weapon reloads, distant echoes, impacts, whizzes and voices.

enum Bark: Int, CaseIterable {
    case alert, attack, reload, grenade, hurt, death, idle, retreat
    var name: String { String(describing: self) }
}

enum WeaponAudio {
    static let fireSlots = 0...5
    static let heavySlot = 9
    static let sidearmSlot = 13      // the Capital Sidearm (Guns.pistol)
    static func hasDistant(_ k: Int) -> Bool { fireSlots.contains(k) || k == heavySlot || k == sidearmSlot }

    // MARK: Building blocks

    // A gunshot: a hard transient crack, a body thump and a filtered tail; `size` scales the body,
    // `bright` the crack, `tail` the room/barrel ring-out.
    static func shot(_ g: inout Synth, p: Float, size: Float, bright: Float, tail: Float, mech: Float) -> [Float] {
        let crack = g.burst(0.06, lp: 9000 * bright * p, hp: 1800, attack: 0.0004, decay: 0.006, gain: 3.2)
        let body = g.burst(0.35 * size, lp: 900 * p / size, hp: 45, attack: 0.0008, decay: 0.035 * size, gain: 3.4)
        let thump = g.modes(0.25 * size, [(85 * p / size, 1.0, 0.04 * size), (140 * p / size, 0.5, 0.025 * size)])
        var out = Synth.mix(Synth.mix(crack, body), thump)
        let ring = g.burst(tail, lp: 2400 * p, hp: 300, attack: 0.01, decay: tail * 0.3, gain: 0.5)
        out = Synth.mix(out, ring, at: g.frames(0.02))
        if mech > 0 {
            // The action cycling: a sci-fi servo chirp and a bolt clack.
            let servo = g.tone(0.07, f0: 2600 * p, f1: 1800 * p, wave: .tri, attack: 0.002, release: 0.03, gain: 0.25 * mech)
            let clack = g.modes(0.06, [(1700 * p, 0.35 * mech, 0.01), (3100 * p, 0.2 * mech, 0.006)])
            out = Synth.mix(out, Synth.mix(servo, clack, at: g.frames(0.03)), at: g.frames(0.07))
        }
        return out
    }

    // A spent casing hitting the ground a moment later.
    static func casing(_ g: inout Synth, p: Float, gain: Float) -> [Float] {
        let tink = g.modes(0.18, [(4200 * p * g.rnd(0.95, 1.05), 0.35, 0.05), (6900 * p, 0.15, 0.03)])
        let tink2 = g.modes(0.12, [(4000 * p, 0.2, 0.03)])
        return Synth.scaled(Synth.mix(tink, tink2, at: g.frames(0.07)), gain)
    }

    // Far-off version of a shot: no crack, a low muffled boom and a long rolling echo off the terrain.
    static func distant(_ g: inout Synth, p: Float, size: Float, roll: Float) -> [Float] {
        let boom = g.burst(0.5 * size, lp: 320 * p / size, hp: 30, attack: 0.004, decay: 0.08 * size, gain: 3)
        var out = Synth.lowpass(boom, 900)
        let tail = g.wash(roll, lp: 420, hp: 40, wobble: 0.6, rate: 4, gain: 0.35)
        out = Synth.mix(out, Synth.decayEnv(tail, roll * 0.35), at: g.frames(0.05))
        return Synth.echo(out, delay: 0.32, feedback: 0.35, mix: 0.35, tail: roll * 0.5)
    }

    // MARK: Renders

    static func gun(_ g: inout Synth, _ k: Int, p: Float) -> [Float] {
        switch k {
        case 0:   // rifle: punchy mid crack with a servo cycle and casing
            var o = shot(&g, p: p, size: 1.0, bright: 1.0, tail: 0.45, mech: 1)
            o = Synth.mix(o, casing(&g, p: p, gain: 0.35), at: g.frames(0.38))
            return o
        case 1:   // chatter gun: short, bright, light
            return shot(&g, p: p * 1.15, size: 0.65, bright: 1.15, tail: 0.25, mech: 0.5)
        case 2:   // shotgun: wide blast + pump
            var o = shot(&g, p: p * 0.85, size: 1.6, bright: 0.8, tail: 0.6, mech: 0)
            o = Synth.mix(o, g.burst(0.4, lp: 3500, hp: 300, attack: 0.002, decay: 0.05, gain: 1.4))
            let pump1 = Synth.mix(g.burst(0.06, lp: 2500, hp: 400, decay: 0.012, gain: 1.0), g.modes(0.08, [(800 * p, 0.4, 0.02)]))
            let pump2 = Synth.mix(g.burst(0.05, lp: 3000, hp: 500, decay: 0.01, gain: 1.0), g.modes(0.07, [(1300 * p, 0.4, 0.015)]))
            o = Synth.mix(o, pump1, at: g.frames(0.42))
            o = Synth.mix(o, pump2, at: g.frames(0.56))
            return o
        case 3:   // farsight: supersonic snap, deep long tail, bolt
            var o = shot(&g, p: p * 0.8, size: 1.4, bright: 1.3, tail: 1.2, mech: 0)
            let bolt1 = Synth.mix(g.modes(0.07, [(1200 * p, 0.4, 0.015)]), g.burst(0.05, lp: 3000, hp: 500, decay: 0.01, gain: 0.7))
            let bolt2 = Synth.mix(g.modes(0.07, [(1600 * p, 0.4, 0.012)]), g.burst(0.05, lp: 3500, hp: 600, decay: 0.008, gain: 0.7))
            o = Synth.mix(o, bolt1, at: g.frames(0.65))
            o = Synth.mix(o, bolt2, at: g.frames(0.82))
            o = Synth.mix(o, casing(&g, p: p * 0.9, gain: 0.3), at: g.frames(1.0))
            return o
        case 4:   // rocket launcher: ignition thump then a hissing whoosh leaving
            let ign = g.burst(0.35, lp: 700 * p, hp: 40, attack: 0.002, decay: 0.07, gain: 3.2)
            var hiss = g.wash(1.3, lp: 5500, hp: 900, wobble: 0.3, rate: 12, gain: 0.8)
            hiss = Synth.decayEnv(Synth.rampIn(hiss, 0.05), 0.5)
            let tone = g.tone(1.1, f0: 520 * p, f1: 240 * p, wave: .saw, attack: 0.03, release: 0.5, gain: 0.06)
            return Synth.mix(Synth.mix(ign, hiss, at: g.frames(0.02)), Synth.lowpass(tone, 2500), at: g.frames(0.03))
        case 5:   // arc lance (energy heavy): capacitor whine up, crackling discharge, zap tail
            let charge = g.tone(0.22, f0: 900 * p, f1: 3600 * p, wave: .sine, attack: 0.02, release: 0.02, gain: 0.25)
            let zap = g.fm(0.45, f: 330 * p, ratio: 7.3, index: 9, decay: 0.12, gain: 0.9)
            let arc = g.crackle(0.5, density: 900, f: 4200, q: 1.2, gain: 1.6)
            let thump = g.burst(0.3, lp: 300, hp: 40, attack: 0.002, decay: 0.06, gain: 2)
            var o = Synth.mix(charge, Synth.mix(Synth.mix(zap, Synth.decayEnv(arc, 0.12)), thump), at: g.frames(0.2))
            o = Synth.mix(o, g.tone(0.5, f0: 2400 * p, f1: 300 * p, wave: .sine, attack: 0.005, release: 0.3, gain: 0.15), at: g.frames(0.22))
            return o
        case 6:   // generic reload (soldiers)
            return reload(&g, 0, p: p)
        case 7:   // dry fire: hollow trigger click with a tiny electronic deny
            return Synth.mix(g.modes(0.06, [(2400 * p, 0.35, 0.006), (3700 * p, 0.12, 0.004)]),
                             g.tone(0.08, f0: 600, f1: 450, wave: .square, attack: 0.002, release: 0.03, gain: 0.06), at: g.frames(0.02))
        case 8:   // ricochet: spark tick + whining glide
            let tick = g.burst(0.05, lp: 7000, hp: 2000, attack: 0.0005, decay: 0.008, gain: 1.4)
            let glide = g.tone(0.35, f0: g.rnd(2400, 3600) * p, f1: g.rnd(900, 1400) * p, wave: .sine, attack: 0.004, release: 0.2, vib: 0.03, vibRate: 30, gain: 0.35)
            return Synth.mix(tick, glide, at: g.frames(0.01))
        case 9:   // deck gun: huge cannon boom, pressure thump and a long rolling tail
            var o = shot(&g, p: p * 0.55, size: 2.6, bright: 0.7, tail: 2.0, mech: 0)
            o = Synth.mix(o, g.rumble(2.5, f: 45, attack: 0.005, decay: 0.9, gain: 3))
            return Synth.echo(o, delay: 0.38, feedback: 0.3, mix: 0.3, tail: 0.8)
        case 10:  // alarm: two-tone klaxon sweep, twice
            var o: [Float] = []
            for k in 0..<2 {
                let up = Synth.lowpass(g.tone(0.9, f0: 520, f1: 880, wave: .saw, attack: 0.02, release: 0.08, gain: 0.35), 3200)
                o = Synth.mix(o, up, at: g.frames(Float(k) * 1.0))
            }
            return o
        case 11:  // radio call: squelch, a burst of filtered voice, squelch
            var o = g.burst(0.06, lp: 6000, hp: 2000, attack: 0.001, decay: 0.02, gain: 0.8)
            let v = SoldierVoice.phrase(&g, f0: 125 * p, syllables: 4, urgency: 0.6)
            o = Synth.mix(o, radio(v), at: g.frames(0.05))
            o = Synth.mix(o, g.burst(0.08, lp: 6000, hp: 2000, attack: 0.001, decay: 0.03, gain: 0.6), at: o.count)
            return o
        case 13:  // sidearm: a sharp, light crack with a quick slide cycle
            var o = shot(&g, p: p * 1.3, size: 0.5, bright: 1.25, tail: 0.3, mech: 0.35)
            o = Synth.mix(o, casing(&g, p: p * 1.2, gain: 0.25), at: g.frames(0.3))
            return o
        default:  // 12 turret whine: servo traverse
            let whine = g.tone(1.0, f0: 220 * p, f1: 760 * p, wave: .saw, attack: 0.05, release: 0.15, vib: 0.02, vibRate: 18, gain: 0.25)
            return Synth.mix(Synth.lowpass(whine, 2600), g.crackle(1.0, density: 40, f: 2200, q: 3, gain: 0.4))
        }
    }

    // Band-limited, slightly distorted "radio" colouring.
    static func radio(_ x: [Float]) -> [Float] {
        let band = Synth.bandpass(x, 1500, q: 0.9)
        return band.map { v in let d = v * 3; return d / (1 + abs(d)) * 0.7 }
    }

    // Per-weapon reloads: magazine out, magazine in, charge / bolt; heavy ones are slower.
    static func reload(_ g: inout Synth, _ w: Int, p: Float) -> [Float] {
        func click(_ g: inout Synth, _ f: Float, _ gain: Float) -> [Float] {
            Synth.mix(g.modes(0.08, [(f * p, 0.4 * gain, 0.015), (f * 1.9 * p, 0.15 * gain, 0.008)]), g.burst(0.04, lp: 4000, hp: 700, decay: 0.008, gain: 0.7 * gain))
        }
        func slide(_ g: inout Synth, _ d: Float) -> [Float] {
            Synth.window(g.wash(d, lp: 3000, hp: 600, wobble: 0.3, rate: 20, gain: 0.4))
        }
        var o: [Float] = []
        switch w {
        case 2:   // shotgun: three shells thumbed in, then the pump
            for k in 0..<3 { o = Synth.mix(o, Synth.mix(slide(&g, 0.12), click(&g, 900, 0.8), at: g.frames(0.1)), at: g.frames(Float(k) * 0.32)) }
            o = Synth.mix(o, click(&g, 800, 1), at: g.frames(1.1))
            o = Synth.mix(o, click(&g, 1300, 1), at: g.frames(1.24))
        case 3:   // farsight: bolt up/back, round, bolt forward/down
            o = Synth.mix(click(&g, 1200, 1), slide(&g, 0.15), at: g.frames(0.05))
            o = Synth.mix(o, click(&g, 1500, 0.7), at: g.frames(0.4))
            o = Synth.mix(o, slide(&g, 0.14), at: g.frames(0.65))
            o = Synth.mix(o, click(&g, 1600, 1), at: g.frames(0.82))
        case 4:   // launcher: heavy tube latch, rocket slides in, power-up chirp
            o = Synth.mix(click(&g, 600, 1.2), g.burst(0.2, lp: 500, hp: 50, decay: 0.05, gain: 1.5))
            o = Synth.mix(o, slide(&g, 0.45), at: g.frames(0.3))
            o = Synth.mix(o, click(&g, 700, 1.2), at: g.frames(0.8))
            o = Synth.mix(o, g.tone(0.25, f0: 600, f1: 1500, wave: .tri, attack: 0.01, release: 0.05, gain: 0.2), at: g.frames(0.95))
        case 5:   // arc lance: cell eject, new cell, capacitor charge whine
            o = Synth.mix(click(&g, 1100, 1), g.burst(0.25, lp: 6000, hp: 2000, attack: 0.01, decay: 0.06, gain: 0.5))
            o = Synth.mix(o, click(&g, 900, 1), at: g.frames(0.4))
            o = Synth.mix(o, g.tone(0.6, f0: 300 * p, f1: 2400 * p, wave: .sine, attack: 0.02, release: 0.05, gain: 0.3), at: g.frames(0.5))
        default:  // rifle (0), chatter gun (1), generic (6): mag out, mag in, charging handle
            let fast: Float = w == 1 ? 0.8 : 1
            o = Synth.mix(click(&g, 1400, 1), slide(&g, 0.1), at: g.frames(0.03))
            o = Synth.mix(o, click(&g, 900, 1.1), at: g.frames(0.45 * fast))
            o = Synth.mix(o, Synth.mix(slide(&g, 0.08), click(&g, 1700, 1), at: g.frames(0.07)), at: g.frames(0.8 * fast))
        }
        return o
    }

    // Bullet hitting a material: a sharp tick, a material-coloured burst and debris.
    static func impact(_ g: inout Synth, _ m: SoundMat, p: Float) -> [Float] {
        let tick = g.burst(0.04, lp: 8000, hp: 1500, attack: 0.0004, decay: 0.006, gain: 1.2)
        let body = g.material(m, pitch: p * 1.2, scale: 0.5, gain: 0.8)
        var o = Synth.mix(tick, body)
        if m == .metal { o = Synth.mix(o, g.modes(0.4, [(2300 * p, 0.35, 0.12), (3700 * p, 0.2, 0.08)])) }
        if m == .stone || m == .deepslate { o = Synth.mix(o, g.grains(5, spread: 0.12, lp: 3500, hp: 600, decay: 0.008, gain: 0.5), at: g.frames(0.03)) }
        return o
    }

    // A round passing close by: a supersonic snap with a doppler whizz.
    static func whizz(_ g: inout Synth, p: Float) -> [Float] {
        let snap = g.burst(0.03, lp: 9000, hp: 3000, attack: 0.0003, decay: 0.004, gain: 1.5)
        var w = g.wash(0.22, lp: 5200 * p, hp: 1800, wobble: 0.2, rate: 30, gain: 0.8)
        w = Synth.window(w)
        let doppler = g.tone(0.2, f0: 3200 * p, f1: 1700 * p, wave: .sine, attack: 0.02, release: 0.12, gain: 0.12)
        return Synth.mix(snap, Synth.mix(w, doppler), at: g.frames(0.01))
    }

    static func flesh(_ g: inout Synth, p: Float) -> [Float] {
        Synth.mix(g.burst(0.12, lp: 1100 * p, hp: 90, attack: 0.001, decay: 0.03, gain: 2.2), g.burst(0.05, lp: 4000, hp: 900, decay: 0.01, gain: 0.5))
    }

    static func grenadeBounce(_ g: inout Synth, p: Float) -> [Float] {
        Synth.mix(g.modes(0.15, [(1300 * p, 0.45, 0.03), (2900 * p, 0.2, 0.02)]), g.burst(0.05, lp: 3000, hp: 500, decay: 0.01, gain: 0.8))
    }
}

// MARK: - Soldier voices
// An original made-up military patter: consonant bursts + vowel formants, clipped and urgent, through a
// helmet comm filter. Rank sets the voice (recruit young and higher, ironclad deep with a mask hum).

enum SoldierVoice {
    static let vowels: [(Float, Float)] = [(730, 1090), (530, 1840), (270, 2290), (570, 840), (300, 870), (660, 1700)]

    static func syllable(_ g: inout Synth, f0: Float, dur: Float, vowel v: Int, consonant: Int, lift: Float) -> [Float] {
        let (f1, f2) = vowels[v % vowels.count]
        let voiced = g.formant(dur, f0: f0 * (1 + 0.15 * lift), f1: f0 * (1 - 0.05 * lift), formants: [(f1, 6, 1), (f2, 8, 0.6), (2600, 10, 0.2)],
                               breath: 0.12, vib: 0.02, vibRate: 6, attack: 0.012, release: 0.03, gain: 1.1)
        var c: [Float]
        switch consonant % 4 {
        case 0: c = g.burst(0.03, lp: 6000, hp: 2500, attack: 0.001, decay: 0.008, gain: 0.8)     // t/k
        case 1: c = g.burst(0.06, lp: 8000, hp: 3500, attack: 0.005, decay: 0.02, gain: 0.5)      // s
        case 2: c = g.burst(0.025, lp: 1500, hp: 200, attack: 0.001, decay: 0.006, gain: 1.0)     // b/d
        default: c = []
        }
        return Synth.mix(c, voiced, at: c.isEmpty ? 0 : g.frames(0.02))
    }

    static func phrase(_ g: inout Synth, f0: Float, syllables n: Int, urgency: Float) -> [Float] {
        var o: [Float] = []
        var t: Float = 0
        for k in 0..<n {
            let d: Float = g.rnd(0.07, 0.14) * (1.1 - urgency * 0.3)
            let lift: Float = (k == n - 1 ? urgency : 0.2 * g.noise())
            let s = syllable(&g, f0: f0, dur: d, vowel: Int(g.rnd() * 6), consonant: Int(g.rnd() * 4), lift: lift)
            o = Synth.mix(o, s, at: g.frames(t))
            t += d + g.rnd(0.01, 0.05)
            if k == n / 2 && n > 4 { t += 0.08 }
        }
        return o
    }

    // Rank 0 recruit, 1 trooper, 2 marksman, 3 ironclad.
    static func render(_ g: inout Synth, rank: Int, _ b: Bark, p: Float) -> [Float] {
        let f0s: [Float] = [150, 122, 112, 92]
        let f0 = f0s[max(0, min(3, rank))] * p
        var o: [Float]
        switch b {
        case .alert: o = phrase(&g, f0: f0 * 1.15, syllables: 3, urgency: 1)
        case .attack: o = phrase(&g, f0: f0 * 1.1, syllables: 4, urgency: 0.8)
        case .reload: o = phrase(&g, f0: f0, syllables: 3, urgency: 0.4)
        case .grenade: o = phrase(&g, f0: f0 * 1.25, syllables: 2, urgency: 1.2)
        case .retreat: o = phrase(&g, f0: f0 * 1.1, syllables: 5, urgency: 0.7)
        case .idle: o = phrase(&g, f0: f0 * 0.95, syllables: 5 + Int(g.rnd() * 3), urgency: 0)
        case .hurt:
            o = g.formant(0.22, f0: f0 * 1.6, f1: f0 * 1.1, formants: [(650, 6, 1), (1200, 8, 0.5)], breath: 0.25, vib: 0.05, attack: 0.005, release: 0.06, growl: 0.3, gain: 1.3)
        case .death:
            o = g.formant(0.7, f0: f0 * 1.5, f1: f0 * 0.7, formants: [(600, 5, 1), (1050, 7, 0.5), (2400, 9, 0.2)], breath: 0.3, vib: 0.06, vibRate: 5, attack: 0.01, release: 0.3, growl: 0.4, gain: 1.3)
            o = Synth.mix(o, g.material(rank == 3 ? .metal : .wool, pitch: 0.8, scale: 1.2, gain: 0.6), at: g.frames(0.55))
        }
        // Helmet comms on the shouted calls; the ironclad's mask adds a hum and a metallic edge.
        if b != .hurt && b != .death { o = Synth.mix(Synth.scaled(o, 0.5), Synth.scaled(WeaponAudio.radio(o), 0.6)) }
        if rank == 3 { o = Synth.mix(o, Synth.scaled(g.tone(Float(o.count) / Synth.sr, f0: 60, f1: 60, wave: .saw, attack: 0.01, release: 0.05, gain: 0.05), 1)) }
        return o
    }

    // Boots and kit: a heel strike, a gear rattle; ironclad plates clank.
    static func step(_ g: inout Synth, rank: Int, p: Float) -> [Float] {
        let heel = g.burst(0.1, lp: 900 * p, hp: 60, attack: 0.002, decay: 0.02, gain: 1.6)
        let kit = g.grains(4, spread: 0.06, lp: 5000, hp: 1500, decay: 0.006, gain: 0.35)
        var o = Synth.mix(heel, kit, at: g.frames(0.015))
        if rank == 3 { o = Synth.mix(o, g.modes(0.25, [(420 * p, 0.35, 0.06), (1130 * p, 0.25, 0.04), (2100 * p, 0.1, 0.02)])) }
        return o
    }
}
