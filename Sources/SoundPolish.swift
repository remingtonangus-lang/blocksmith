import Foundation

// Second-generation patches for the sounds heard most: wind and rain beds, songbirds, explosions,
// weapon swings, the player's hurt grunts, pickups and the interface. Same toolkit as SoundSynth /
// SoundFoley (resonators, textures, saturation); render() routes the roster here.

extension Synth {
    // MARK: Helpers

    // A resonator whose centre follows fc(t) (recomputed every 32 samples), driven by white noise.
    mutating func sweptNoise(_ dur: Float, decay: Float, gain: Float, fc: (Float) -> Float, amp: (Float) -> Float) -> [Float] {
        let n = frames(dur)
        var out = [Float](repeating: 0, count: n)
        var y1: Float = 0, y2: Float = 0, c1: Float = 0, c2: Float = 0, g: Float = 0
        let r = expf(-1 / (decay * Synth.sr))
        for i in 0..<n {
            if i % 32 == 0 {
                let t = Float(i) / Synth.sr
                let w = 2 * Float.pi * min(fc(t), Synth.sr * 0.45) / Synth.sr
                c1 = 2 * r * cosf(w); c2 = -r * r; g = sinf(w) * (1 - r) * 8
            }
            let y = g * noise() + c1 * y1 + c2 * y2
            y2 = y1; y1 = y
            out[i] = y * amp(Float(i) / Synth.sr) * gain
        }
        return out
    }

    // A periodic gust curve (0...1-ish) that repeats exactly every `dur`, so loops stay seamless.
    mutating func gustCurve(_ dur: Float) -> (Float) -> Float {
        // Several harmonics of the loop length with random phases and falling, jittered weights:
        // irregular swells rather than one obvious cycle.
        var parts: [(Float, Float, Float)] = []
        for k in [1, 2, 3, 4, 6, 7, 9] { parts.append((Float(k), rnd(0, 6.28), 0.16 / powf(Float(k), 0.6) * rnd(0.4, 1.0))) }
        return { t in
            let x = 2 * Float.pi * t / dur
            var v: Float = 0.6
            for (k, ph, a) in parts { v += a * sinf(k * x + ph) }
            return max(0.15, v)
        }
    }

    // MARK: Weather and nature

    // Wind: a low body that swells with gusts, a howl whose pitch rides the gusts, a faint whistle.
    mutating func windBed(_ dur: Float, lp: Float, gain: Float) -> [Float] {
        let gust = gustCurve(dur)
        let gust2 = gustCurve(dur)
        let low = Synth.highpass(Synth.lowpass(wash(dur, lp: lp * 0.7, hp: 40, wobble: 0.3, rate: 1.5, gain: 1), lp * 0.9), 45)
        var out = [Float](repeating: 0, count: low.count)
        for i in 0..<low.count { let t = Float(i) / Synth.sr; out[i] = low[i] * gust(t) }
        let howl = sweptNoise(dur, decay: 0.012, gain: 0.5, fc: { t in lp * (0.6 + 0.7 * gust(t)) }, amp: { t in powf(gust(t), 2) })
        let whistle = sweptNoise(dur, decay: 0.06, gain: 0.08, fc: { t in lp * 2.6 * (0.85 + 0.35 * gust2(t)) }, amp: { t in powf(gust2(t), 3) })
        out = Synth.mix(Synth.mix(out, howl), whistle)
        // Leaves and grass stirring in the gusts.
        var rustle = swishNoise(dur, lo: 1800, hi: 7000, attack: 0.01, decay: 1000, gain: 0.35)
        for i in 0..<rustle.count { rustle[i] *= powf(gust(Float(i) / Synth.sr), 3) }
        out = Synth.mix(out, rustle)
        return Synth.loopify(Synth.scaled(out, gain), fade: 0.8)
    }

    // Rain: a soft bed, thousands of tiny drop impacts and some bubble chirps (drops into puddles).
    // Under a roof: dull thuds on the boards and drips.
    mutating func rainBed(_ dur: Float, roof: Bool) -> [Float] {
        let n = frames(dur)
        // Far: the hiss of rain over the whole landscape.
        var out = Synth.scaled(wash(dur, lp: roof ? 900 : 3000, hp: roof ? 90 : 250, wobble: 0.25, rate: 1.2, gain: 1), roof ? 0.45 : 0.2)
        if !roof { out = Synth.mix(out, Synth.scaled(wash(dur, lp: 800, hp: 120, wobble: 0.3, rate: 0.8, gain: 1), 0.14)) }
        var click = [Float](repeating: 0, count: 24)
        if roof {
            for _ in 0..<Int(dur * 160) {
                let at = Int(rnd() * Float(n - 1))
                Synth.resonate(Synth.contactPulse(0.0012), at: at, f: rnd(250, 900), decay: 0.008, amp: powf(rnd(), 2.2) * 1.6, into: &out)
            }
            for _ in 0..<Int(dur * 3) { out = Synth.mix(out, modes(0.12, [(rnd(900, 1600), 0.12, 0.02)]), at: Int(rnd() * Float(n - frames(0.15)))) }
            return Synth.loopify(Array(out.prefix(n)), fade: 0.4)
        }
        // Mid: a dense patter of small drops on leaves and ground.
        for _ in 0..<Int(dur * 1400) {
            let at = Int(rnd() * Float(n - 1))
            for i in 0..<click.count { click[i] = noise() * expf(-Float(i) / 3) }
            Synth.resonate(click, at: at, f: rnd(1800, 5500), decay: 0.0005, amp: powf(rnd(), 2) * 0.35, into: &out)
        }
        // Near: sparse, distinct big drops (lower, ringing a little) and puddle plinks.
        for _ in 0..<Int(dur * 90) {
            let at = Int(rnd() * Float(n - 1))
            let big = rnd()
            for i in 0..<click.count { click[i] = noise() * expf(-Float(i) / 4) }
            Synth.resonate(click, at: at, f: 4200 - 2800 * big, decay: 0.0005 + 0.0012 * big, amp: (0.15 + 0.4 * big) * powf(rnd(), 2), into: &out)
            if rnd() < 0.15 {
                let f0 = rnd(1400, 3600)
                let len = frames(rnd(0.006, 0.014))
                var ph: Float = 0
                for i in 0..<len where at + i < n {
                    let k = Float(i) / Float(len)
                    ph += f0 * (1 + 0.6 * k) / Synth.sr
                    out[at + i] += sinf(2 * .pi * ph) * (1 - k) * 0.25
                }
            }
        }
        return Synth.loopify(Synth.lowpass(Array(out.prefix(n)), 6500), fade: 0.4)
    }

    // Songbirds: one of four species per take (whistler, warbler trill, two-note call, chirrup).
    mutating func songbird(pitch p: Float) -> [Float] {
        var out: [Float] = []
        func note(_ s: inout Synth, _ len: Float, _ f0: Float, _ f1: Float, curve: Float, am: Float, gain: Float) -> [Float] {
            let n = s.frames(len)
            var o = [Float](repeating: 0, count: n)
            var ph: Float = 0
            let amRate = s.rnd(60, 110)
            let fmRate = s.rnd(25, 70), fmDepth = s.rnd(0, 0.06)
            let chevron = s.rnd() < 0.4
            for i in 0..<n {
                let k = Float(i) / Float(n)
                let kk: Float = chevron ? 1 - abs(1 - 2 * k) : k
                let f = (f0 + (f1 - f0) * powf(kk, curve)) * (1 + fmDepth * sinf(2 * .pi * fmRate * Float(i) / Synth.sr))
                ph += f / Synth.sr
                let env = sinf(.pi * min(1, k * 1.15)) * min(1, k * 25)
                let trem: Float = 1 - am * (0.5 + 0.5 * sinf(2 * .pi * amRate * Float(i) / Synth.sr))
                o[i] = (sinf(2 * .pi * ph) + 0.08 * sinf(4 * .pi * ph)) * env * trem * gain
            }
            return o
        }
        var t: Float = 0
        switch Int(rnd() * 4) {
        case 0:   // whistler: 2-4 smooth glides
            let base = rnd(2000, 3200) * p
            for _ in 0..<(2 + Int(rnd() * 3)) {
                let len = rnd(0.12, 0.3)
                let f0 = base * rnd(0.85, 1.2)
                out = Synth.mix(out, note(&self, len, f0, f0 * rnd(0.75, 1.35), curve: rnd(0.5, 2), am: 0, gain: 0.5), at: frames(t))
                t += len + rnd(0.05, 0.14)
            }
        case 1:   // warbler: an accelerating trill of falling chirps
            let n = 8 + Int(rnd() * 7)
            let base = rnd(3800, 5600) * p
            var gap: Float = 0.07
            for k in 0..<n {
                let len = rnd(0.025, 0.04)
                let rise = sinf(.pi * Float(k) / Float(n))
                out = Synth.mix(out, note(&self, len, base * 1.35, base * 0.75, curve: 0.6, am: 0, gain: 0.3 + 0.3 * rise), at: frames(t))
                t += len + gap
                gap = max(0.012, gap * 0.85)
            }
        case 2:   // two-note call ("fee-bee"), sometimes twice
            let f = rnd(2800, 3900) * p
            for r in 0..<(rnd() < 0.5 ? 1 : 2) {
                out = Synth.mix(out, note(&self, 0.24, f, f * 0.97, curve: 1, am: 0, gain: 0.5), at: frames(t + Float(r) * 0.75))
                out = Synth.mix(out, note(&self, 0.26, f * 0.84, f * 0.8, curve: 1, am: 0.15, gain: 0.45), at: frames(t + 0.3 + Float(r) * 0.75))
            }
        default:  // chirrup: short buzzy "tsip" notes
            let base = rnd(4500, 6500) * p
            for _ in 0..<(3 + Int(rnd() * 3)) {
                let len = rnd(0.03, 0.07)
                out = Synth.mix(out, note(&self, len, base, base * rnd(0.6, 0.8), curve: 0.5, am: 0.5, gain: 0.45), at: frames(t))
                t += len + rnd(0.04, 0.1)
            }
        }
        // A bird in a tree some way off: air absorption, a little canopy reflection.
        return Synth.echo(Synth.highpass(Synth.lowpass(out, 8000), 1200), delay: 0.09, feedback: 0.1, mix: 0.1, tail: 0.25)
    }

    // MARK: Explosions

    // size: 0.6 small, 1 normal, 1.8 large. Pressure crack, chest-thump body, roar, debris, rolling tail.
    mutating func explosion(size: Float, p: Float) -> [Float] {
        let sr = Synth.sr
        func norm(_ x: [Float], _ to: Float) -> [Float] {
            let pk = x.reduce(0) { max($0, abs($1)) }
            return pk > 0 ? x.map { $0 / pk * to } : x
        }
        // The detonation: pressure crack (N-wave + hot noise, saturated), a pitch-dropping concussion
        // with a punch an octave up, a mid roar and a long low body.
        var blast = [Float](repeating: 0, count: frames(0.4 * size))
        let tauN: Float = 0.004 * size
        for i in blast.indices {
            let t = Float(i) / sr
            let rise: Float = min(1, t / 0.0004)
            blast[i] = rise * (expf(-t / tauN) * 1.4 - 0.4 * expf(-t / (tauN * 4)) * min(1, t / 0.004)) + noise() * expf(-t / (0.035 * size)) * rise
        }
        blast = Synth.lowpass(blast, 7000 * p).map { tanhf($0 * 3) }
        var kick = [Float](repeating: 0, count: frames(1.4 * size))
        var ph: Float = 0, ph2: Float = 0
        let f0: Float = 58 * p / sqrtf(size)
        for i in kick.indices {
            let t = Float(i) / sr
            let sweep: Float = 1 + 1.5 * expf(-t / 0.035)
            ph += f0 * sweep / sr
            ph2 += f0 * 2 * sweep / sr
            kick[i] = (sinf(2 * .pi * ph) * expf(-t / (0.3 * size)) + 0.5 * sinf(2 * .pi * ph2) * expf(-t / (0.08 * size))) * min(1, t / 0.002)
        }
        let roar = burst(1.6 * size, lp: 1500 * p, hp: 60, attack: 0.003, decay: 0.3 * size, gain: 1)
        let low = burst(2.6 * size, lp: 160 * p, hp: 18, attack: 0.01, decay: 0.7 * size, gain: 1)
        let crack = burst(0.02, lp: 14000, hp: 2500, attack: 0.0002, decay: 0.004, gain: 1).map { tanhf($0 * 4) }
        var main = Synth.mix(Synth.mix(Synth.mix(norm(blast, 1), norm(kick, 0.9)), norm(roar, 0.55)), norm(low, 0.6))
        main = Synth.mix(main, norm(crack, 0.6))
        if size > 1.4 {
            // A big blast: a deeper sub-boom, a second pressure wave off the ground and a long rolling rumble.
            main = Synth.mix(main, norm(rumble(3.5 * size / 1.8, f: 34, attack: 0.02, decay: 1.2, gain: 1), 0.55), at: frames(0.03))
            main = Synth.mix(main, norm(Synth.lowpass(blast, 900), 0.5), at: frames(0.06))
        }
        main = norm(main, 1)
        // Debris raining down (it starts as the roar peaks, so it reads as caused by it).
        var debris = [Float](repeating: 0, count: frames(2.2 * size))
        var piece = FoleyMat.of(.stone)
        piece.thump = 0.2; piece.modes = piece.modes.map { ($0.f * 1.5, $0.decay * 0.6, $0.amp) }
        for _ in 0..<Int(18 * size) {
            let t = 0.1 + powf(rnd(), 1.6) * 1.6 * size
            debris = Synth.mix(debris, foleyContact(piece, p: p * rnd(0.8, 1.6), force: rnd(0.3, 1) * max(0.1, 1 - t / (2 * size)), ring: 0.6, texLen: 0.03, texScale: 0.8), at: frames(t))
        }
        debris = Synth.mix(debris, texture(1.6 * size, rate: 1600, lo: 500, hi: 4500, grain: 0.0025, gain: 1) { x in min(1, x * 8) * (1 - x) * (1 - x) }, at: frames(0.06))
        var out = Synth.mix(main, norm(debris, 0.22))
        // The landscape answering: a diffuse tail and rolling slapbacks off hills.
        let src = Synth.lowpass(Synth.mix(blast, roar), 1000)
        out = Synth.mix(out, norm(Synth.reverb(src, size: 1.8, damp: 0.6, mix: 1, tail: 1.6 * size), 0.3))
        let slaps: [(Float, Float)] = size > 1.4 ? [(0.2, 0.3), (0.45, 0.24), (0.8, 0.18), (1.25, 0.12), (1.8, 0.08)] : [(0.2, 0.28), (0.5, 0.18), (0.95, 0.1)]
        for (d, g) in slaps {
            out = Synth.mix(out, norm(Synth.lowpass(main, 420, passes: 2), g), at: frames(d * size * rnd(0.85, 1.15)))
        }
        let peak = out.reduce(0) { max($0, abs($1)) }
        return peak > 0 ? Synth.highpass(out.map { tanhf($0 / peak * 1.5) / tanhf(1.5) }, 20) : out
    }

    // MARK: Combat and the player

    // A blade/arm swing: band-passed air sweeping up then down, loudest mid-swing.
    mutating func swoosh(_ dur: Float, lo: Float, hi: Float, gain: Float) -> [Float] {
        sweptNoise(dur, decay: 0.0025, gain: gain, fc: { t in
            let k = t / dur
            return lo + (hi - lo) * sinf(.pi * min(1, k * 1.1))
        }, amp: { t in
            let k = t / dur
            return powf(sinf(.pi * k), 2) * (1 - 0.3 * k)
        })
    }

    // A hit landing on a body: a dull thud plus a short cloth/flesh slap.
    mutating func bodyHit(force: Float, p: Float) -> [Float] {
        var o = [Float](repeating: 0, count: frames(0.2))
        Synth.resonate(Synth.contactPulse(0.004), f: 115 * p * rnd(0.9, 1.1), decay: 0.03, amp: 2.4 * force, into: &o)
        o = Synth.mix(o, burst(0.1, lp: 1400 * p, hp: 120, attack: 0.0006, decay: 0.012, gain: 1.1 * force))
        return Synth.mix(o, burst(0.04, lp: 5000, hp: 1500, attack: 0.0003, decay: 0.004, gain: 0.35 * force))
    }

    // A short exhaled grunt: breath noise through vowel formants with a quiet voiced core.
    mutating func grunt(_ dur: Float, f0: Float, vowel: (Float, Float), voiced: Float, gain: Float) -> [Float] {
        let v = formant(dur, f0: f0, f1: f0 * 0.8, formants: [(vowel.0, 5, 1), (vowel.1, 7, 0.55), (2700, 9, 0.18)], breath: 0.35, vib: 0.01, vibRate: 5,
                        attack: 0.012, release: dur * 0.6, gain: voiced)
        var air = burst(dur, lp: 3000, hp: 250, attack: 0.01, decay: dur * 0.35, gain: 1)
        air = Synth.mix(Synth.scaled(Synth.bandpass(air, vowel.0, q: 2.5), 1.4), Synth.scaled(Synth.bandpass(air, vowel.1, q: 3), 0.8))
        return Synth.scaled(Synth.lowpass(Synth.mix(v, air), 4500), gain)
    }

    // MARK: Pickups and the interface (soft, rounded, a little glassy; never shrill)

    mutating func pickupPop(p: Float) -> [Float] {
        let body = tone(0.07, f0: 480 * p, f1: 900 * p, wave: .sine, attack: 0.004, release: 0.05, gain: 0.5)
        let shine = modes(0.12, [(1800 * p, 0.12, 0.03), (2700 * p, 0.06, 0.02)])
        return Synth.mix(Synth.mix(body, shine, at: frames(0.02)), burst(0.02, lp: 6000, hp: 2000, attack: 0.001, decay: 0.003, gain: 0.15))
    }

    mutating func uiTick(f: Float, gain: Float) -> [Float] {
        let tick = burst(0.015, lp: 7000, hp: 1800, attack: 0.0003, decay: 0.0018, gain: 0.5 * gain)
        let body = modes(0.06, [(f, 0.3 * gain, 0.012), (f * 2.76, 0.08 * gain, 0.005)])
        return Synth.room(Synth.mix(body, tick), mix: 0.08)
    }

    // A soft glassy chime (toasts, unlocks): bell partials with a slow shimmer tail.
    mutating func chime(_ f: Float, gain: Float, len: Float = 0.9) -> [Float] {
        let c = modes(len, [(f, 0.3 * gain, len * 0.4), (f * 2.0, 0.12 * gain, len * 0.25), (f * 2.76, 0.08 * gain, len * 0.18), (f * 5.4, 0.03 * gain, len * 0.08)])
        return Synth.mix(c, Synth.scaled(tone(len, f0: f * 1.003, f1: f * 1.003, wave: .sine, attack: 0.02, release: len * 0.7, gain: 0.06 * gain), 1))
    }

    mutating func uiSound(_ s: Snd, p: Float) -> [Float] {
        switch s {
        case .click: return uiTick(f: 1250 * p, gain: 1)
        case .uiHover: return uiTick(f: 1700 * p, gain: 0.45)
        case .uiBack: return Synth.mix(uiTick(f: 950 * p, gain: 0.9), uiTick(f: 760 * p, gain: 0.6), at: frames(0.035))
        case .open: return Synth.mix(uiTick(f: 880 * p, gain: 0.8), chime(1320 * p, gain: 0.5, len: 0.3), at: frames(0.03))
        case .toast:
            let a = chime(1046 * p, gain: 0.8)
            return Synth.reverb(Synth.mix(a, chime(1568 * p, gain: 0.7), at: frames(0.09)), size: 1.2, damp: 0.5, mix: 0.25, tail: 0.6)
        case .xp: return Synth.mix(chime(2093 * p, gain: 0.45, len: 0.3), burst(0.03, lp: 9000, hp: 4000, attack: 0.001, decay: 0.005, gain: 0.1))
        default:  // levelUp: a rising major arpeggio with a bright shimmer on top
            var o: [Float] = []
            for (k, f) in [523.25, 659.25, 783.99, 1046.5].enumerated() {
                o = Synth.mix(o, chime(Float(f), gain: 0.75, len: 1.0), at: frames(Float(k) * 0.075))
            }
            o = Synth.mix(o, Synth.decayEnv(wash(1.0, lp: 12000, hp: 5000, wobble: 0.5, rate: 20, gain: 0.05), 0.35), at: frames(0.25))
            return Synth.reverb(o, size: 1.3, damp: 0.45, mix: 0.3, tail: 0.8)
        }
    }
}
