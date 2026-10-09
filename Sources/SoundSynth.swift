import Foundation

// Tiny DSP toolkit (pure Swift, no Accelerate) and the renderer for every non-mob sound.
// All generators return mono Float arrays at SoundBank.rate; render() normalizes and de-clicks.

struct Synth {
    var state: UInt64
    init(seed: UInt64) { state = seed | 1 }

    static let sr = Float(SoundBank.rate)
    func frames(_ seconds: Float) -> Int { max(1, Int(seconds * Synth.sr)) }

    mutating func noise() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
    }
    mutating func rnd() -> Float { noise() * 0.5 + 0.5 }                     // 0...1
    mutating func rnd(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * rnd() }

    // MARK: Envelopes / array helpers

    static func mix(_ a: [Float], _ b: [Float], at offset: Int = 0, gain: Float = 1) -> [Float] {
        var out = a
        let off = max(0, offset)
        if out.count < off + b.count { out += [Float](repeating: 0, count: off + b.count - out.count) }
        for i in 0..<b.count { out[off + i] += b[i] * gain }
        return out
    }
    static func scaled(_ a: [Float], _ g: Float) -> [Float] { a.map { $0 * g } }

    static func fadeIn(_ x: inout [Float], _ seconds: Float) {
        let n = min(x.count, Int(seconds * sr))
        for i in 0..<n { x[i] *= Float(i) / Float(max(1, n)) }
    }
    static func fadeOut(_ x: inout [Float], _ seconds: Float) {
        let n = min(x.count, Int(seconds * sr))
        for i in 0..<n { x[x.count - 1 - i] *= Float(i) / Float(max(1, n)) }
    }
    // Trims silence-ish tail below a threshold (keeps at least `keep` seconds).
    static func trimTail(_ x: [Float], below t: Float = 0.003, keep: Float = 0.02) -> [Float] {
        var end = x.count
        while end > Int(keep * sr) && abs(x[end - 1]) < t { end -= 1 }
        return Array(x[0..<min(x.count, end + Int(keep * sr))])
    }
    // Makes a seamless loop: the last `fade` seconds are cross-faded into the head and dropped.
    static func loopify(_ x: [Float], fade: Float) -> [Float] {
        let f = min(x.count / 3, Int(fade * sr))
        guard f > 1 else { return x }
        var out = Array(x[0..<(x.count - f)])
        for i in 0..<f {
            let k = Float(i) / Float(f)
            out[i] = out[i] * k + x[x.count - f + i] * (1 - k)
        }
        return out
    }

    // Envelope shapes applied over a whole buffer.
    static func window(_ x: [Float]) -> [Float] {
        var out = x
        let n = Float(max(1, x.count))
        for i in 0..<out.count { let k: Float = Float(i) / n; out[i] *= sinf(k * Float.pi) }
        return out
    }
    static func decayEnv(_ x: [Float], _ tau: Float) -> [Float] {
        var out = x
        let k: Float = expf(-1 / (tau * sr))
        var e: Float = 1
        for i in 0..<out.count { out[i] *= e; e *= k }
        return out
    }
    static func rampIn(_ x: [Float], _ seconds: Float) -> [Float] {
        var out = x
        let n: Float = max(1, seconds * sr)
        for i in 0..<out.count { let k: Float = Float(i) / n; out[i] *= min(1, k) }
        return out
    }

    // MARK: Filters (applied to whole buffers)

    static func lowpass(_ x: [Float], _ hz: Float, passes: Int = 1) -> [Float] {
        var out = x
        let a = 1 - expf(-2 * .pi * hz / sr)
        for _ in 0..<passes { var s: Float = 0; for i in 0..<out.count { s += a * (out[i] - s); out[i] = s } }
        return out
    }
    static func highpass(_ x: [Float], _ hz: Float) -> [Float] {
        var out = x
        let a = 1 - expf(-2 * .pi * hz / sr)
        var s: Float = 0
        for i in 0..<out.count { s += a * (out[i] - s); out[i] = out[i] - s }
        return out
    }
    // Resonant band-pass (RBJ biquad, 0 dB peak).
    static func bandpass(_ x: [Float], _ f: Float, q: Float) -> [Float] {
        let w = 2 * Float.pi * min(f, sr * 0.45) / sr
        let alpha = sinf(w) / (2 * max(0.1, q))
        let a0 = 1 + alpha
        let b0 = alpha / a0, b2 = -alpha / a0, a1 = -2 * cosf(w) / a0, a2 = (1 - alpha) / a0
        var out = [Float](repeating: 0, count: x.count)
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        for i in 0..<x.count {
            let y = b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = y
            out[i] = y
        }
        return out
    }
    // Feedback delay (echoes / crude reverb tail).
    static func echo(_ x: [Float], delay: Float, feedback: Float, mix m: Float, tail: Float = 1) -> [Float] {
        let d = max(1, Int(delay * sr))
        var out = x + [Float](repeating: 0, count: Int(tail * sr))
        if d < out.count { for i in d..<out.count { out[i] += out[i - d] * feedback } }
        for i in 0..<out.count { out[i] = (i < x.count ? x[i] : 0) * (1 - m) + out[i] * m }
        return out
    }
    // Simple 4-comb + 2-allpass reverb for offline atmospheres.
    static func reverb(_ x: [Float], size: Float, damp: Float, mix m: Float, tail: Float) -> [Float] {
        let n = x.count + Int(tail * sr)
        var acc = [Float](repeating: 0, count: n)
        for (k, base) in [1116, 1188, 1277, 1356].enumerated() {
            let d = max(1, Int(Float(base) * size))
            var buf = [Float](repeating: 0, count: n)
            var lp: Float = 0
            let fb: Float = 0.75 + 0.03 * Float(k)
            for i in 0..<n {
                let inp = i < x.count ? x[i] : 0
                let fbv = i >= d ? buf[i - d] : 0
                lp += (1 - damp) * (fbv - lp)
                buf[i] = inp + lp * fb
                acc[i] += buf[i] * 0.25
            }
        }
        for d in [225, 556] {
            var out = [Float](repeating: 0, count: n)
            for i in 0..<n {
                let xd = i >= d ? acc[i - d] : 0
                let yd = i >= d ? out[i - d] : 0
                out[i] = -0.5 * acc[i] + xd + 0.5 * yd
            }
            acc = out
        }
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = (i < x.count ? x[i] : 0) * (1 - m) + acc[i] * m }
        return out
    }

    // MARK: Generators

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

    // Steady filtered noise with a slow random wobble (wind, hiss, water beds).
    mutating func wash(_ dur: Float, lp: Float, hp: Float, wobble: Float, rate: Float, gain: Float) -> [Float] {
        let n = frames(dur)
        var out = [Float](repeating: 0, count: n)
        let b = 1 - expf(-2 * .pi * hp / Synth.sr)
        var lpS: Float = 0, hpS: Float = 0, mod: Float = 0, target: Float = 0
        var count = 0
        let step = max(1, Int(Synth.sr / max(0.1, rate)))
        for i in 0..<n {
            if count == 0 { target = noise(); count = step }
            count -= 1
            mod += (target - mod) * 0.0005
            let hz: Float = max(20, lp * (1 + wobble * mod))   // big wobble must not drive the cutoff negative
            let a: Float = 1 - expf(-2 * Float.pi * hz / Synth.sr)
            lpS += a * (noise() - lpS)
            hpS += b * (lpS - hpS)
            out[i] = (lpS - hpS) * gain * max(0, 1 + 0.5 * wobble * mod)
        }
        return out
    }

    // Sum of exponentially damped sines (knocks, rings, pings).
    func modes(_ dur: Float, _ partials: [(freq: Float, amp: Float, decay: Float)]) -> [Float] {
        let n = frames(dur)
        var out = [Float](repeating: 0, count: n)
        for p in partials {
            let w = 2 * Float.pi * p.freq / Synth.sr
            let k = expf(-1 / (p.decay * Synth.sr))
            var env = p.amp
            for i in 0..<n {
                out[i] += sinf(w * Float(i)) * env
                env *= k
            }
        }
        return out
    }

    enum Wave { case sine, tri, saw, square }
    // Oscillator with pitch glide, vibrato and an attack/release envelope.
    mutating func tone(_ dur: Float, f0: Float, f1: Float, wave: Wave = .sine, attack: Float = 0.01, release: Float = 0.05, vib: Float = 0, vibRate: Float = 5.5, gain: Float = 1) -> [Float] {
        let n = frames(dur)
        var out = [Float](repeating: 0, count: n)
        var phase: Float = 0
        for i in 0..<n {
            let t = Float(i) / Synth.sr, k = t / dur
            let f = (f0 + (f1 - f0) * k) * (1 + vib * sinf(2 * .pi * vibRate * t))
            phase += f / Synth.sr
            phase -= floorf(phase)
            let v: Float
            switch wave {
            case .sine: v = sinf(2 * .pi * phase)
            case .tri: v = 4 * abs(phase - 0.5) - 1
            case .saw: v = phase * 2 - 1
            case .square: v = phase < 0.5 ? 1 : -1
            }
            let env = min(1, t / max(0.0005, attack)) * min(1, (dur - t) / max(0.0005, release))
            out[i] = v * env * gain
        }
        return out
    }

    // FM bell / metal: carrier f, modulator ratio, index decaying with the note.
    func fm(_ dur: Float, f: Float, ratio: Float, index: Float, decay: Float, gain: Float) -> [Float] {
        let n = frames(dur)
        var out = [Float](repeating: 0, count: n)
        let wc = 2 * Float.pi * f / Synth.sr, wm = wc * ratio
        for i in 0..<n {
            let t = Float(i) / Synth.sr
            let env: Float = expf(-t / decay)
            let fi: Float = Float(i)
            let modv: Float = index * env * sinf(wm * fi)
            let atk: Float = min(1, t / 0.002)
            out[i] = sinf(wc * fi + modv) * env * gain * atk
        }
        return out
    }

    // Karplus–Strong plucked string.
    mutating func pluck(_ dur: Float, f: Float, damp: Float = 0.996, bright: Float = 0.5, gain: Float) -> [Float] {
        let n = frames(dur)
        let len = max(2, Int(Synth.sr / max(20, f)))
        var buf = [Float](repeating: 0, count: len)
        for i in 0..<len { buf[i] = noise() }
        buf = Synth.lowpass(buf, 400 + 8000 * bright)
        let mean = buf.reduce(0, +) / Float(len)
        for i in 0..<len { buf[i] -= mean }
        var out = [Float](repeating: 0, count: n)
        var idx = 0
        for i in 0..<n {
            let nxt = (idx + 1) % len
            let v = buf[idx]
            buf[idx] = (v + buf[nxt]) * 0.5 * damp
            out[i] = v * gain * min(1, (dur - Float(i) / Synth.sr) / 0.05)
            idx = nxt
        }
        return out
    }

    // Random impulses through a resonant band (fire crackle, static, rattles).
    mutating func crackle(_ dur: Float, density: Float, f: Float, q: Float, gain: Float) -> [Float] {
        let n = frames(dur)
        var imp = [Float](repeating: 0, count: n)
        let p = density / Synth.sr
        for i in 0..<n { if rnd() < p { imp[i] = noise() } }
        return Synth.scaled(Synth.bandpass(imp, f, q: q), gain)
    }

    // Short rising sine chirps (bubbles, drips, pops).
    mutating func bubbles(_ dur: Float, count: Int, fLo: Float, fHi: Float, len: Float, gain: Float) -> [Float] {
        var out = [Float](repeating: 0, count: frames(dur))
        for _ in 0..<count {
            let f = rnd(fLo, fHi), l = len * rnd(0.6, 1.4)
            let b = tone(l, f0: f, f1: f * 1.6, wave: .sine, attack: 0.002, release: l * 0.7, gain: gain * rnd(0.5, 1))
            out = Synth.mix(out, b, at: frames(rnd() * max(0.001, dur - l)))
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

    // Formant voice: glottal pulse train (with breath noise) through parallel resonant band-passes.
    // The pitch follows f0 -> f1 with vibrato; `formants` are (Hz, Q, amp) vowel resonances.
    mutating func formant(_ dur: Float, f0: Float, f1: Float, formants: [(Float, Float, Float)], breath: Float = 0.1, vib: Float = 0.02, vibRate: Float = 5.5,
                          attack: Float = 0.03, release: Float = 0.08, growl: Float = 0, gain: Float) -> [Float] {
        let n = frames(dur)
        var src = [Float](repeating: 0, count: n)
        var phase: Float = 0, gPhase: Float = 0
        for i in 0..<n {
            let t = Float(i) / Synth.sr, k = t / dur
            var f = (f0 + (f1 - f0) * k) * (1 + vib * sinf(2 * .pi * vibRate * t))
            if growl > 0 {
                gPhase += 28 / Synth.sr
                let sq: Float = gPhase - floorf(gPhase) < 0.5 ? 1 : -1
                f *= 1 + growl * sq * 0.5
            }
            phase += f / Synth.sr
            if phase >= 1 { phase -= 1 }
            // Glottal pulse: a sharp rise then a soft fall, plus aspiration noise.
            let p = phase < 0.3 ? sinf(phase / 0.3 * .pi) : 0
            src[i] = p - 0.2 + noise() * breath
        }
        var out = [Float](repeating: 0, count: n)
        for (f, q, a) in formants {
            let band = Synth.bandpass(src, f, q: q)
            for i in 0..<n { out[i] += band[i] * a }
        }
        for i in 0..<n {
            let t = Float(i) / Synth.sr
            out[i] *= min(1, t / attack) * min(1, (dur - t) / release) * gain
        }
        return out
    }

    // Low rumble: filtered noise band around f.
    mutating func rumble(_ dur: Float, f: Float, attack: Float, decay: Float, gain: Float) -> [Float] {
        let raw = burst(dur, lp: f * 2, hp: f * 0.3, attack: attack, decay: decay, gain: gain)
        return Synth.bandpass(raw, f, q: 0.7).map { $0 * 3 }
    }

    // Crunchy material: several short grains spread over `spread` seconds.
    mutating func grains(_ count: Int, spread: Float, lp: Float, hp: Float, decay: Float, gain: Float) -> [Float] {
        var out = [Float](repeating: 0, count: frames(spread + decay * 6))
        for _ in 0..<count {
            let at = frames(rnd() * spread)
            let g = burst(decay * 6, lp: lp * (0.8 + 0.4 * rnd()), hp: hp, attack: 0.001, decay: decay, gain: gain * (0.6 + 0.4 * rnd()))
            out = Synth.mix(out, g, at: at)
        }
        return out
    }

    // Repeats a sub-sound `times` times, `interval` apart with timing/level jitter.
    mutating func repeated(_ make: (inout Synth) -> [Float], times: Int, interval: Float, jitter: Float = 0.1) -> [Float] {
        var out: [Float] = []
        for k in 0..<times {
            let sub = make(&self)
            out = Synth.mix(out, sub, at: frames(Float(k) * interval * (1 + jitter * noise())), gain: 0.8 + 0.2 * rnd())
        }
        return out
    }

    // MARK: Block materials

    mutating func material(_ m: SoundMat, pitch p: Float, scale: Float, gain: Float) -> [Float] {
        switch m {
        case .stone:
            return grains(Int(9 * scale), spread: 0.09 * scale, lp: 3200 * p, hp: 500, decay: 0.012, gain: gain * 1.6)
        case .dirt, .grass:
            return Synth.mix(burst(0.25 * scale, lp: 900 * p, hp: 60, decay: 0.05 * scale, gain: gain * 2.2),
                             grains(Int(5 * scale), spread: 0.08 * scale, lp: 1000 * p, hp: 120, decay: 0.01, gain: gain * 0.5))
        case .gravel:
            return Synth.mix(grains(Int(14 * scale), spread: 0.12 * scale, lp: 2400 * p, hp: 300, decay: 0.014, gain: gain * 1.2),
                             burst(0.2 * scale, lp: 700 * p, hp: 80, decay: 0.05 * scale, gain: gain * 1.0))
        case .sand, .snow, .soul:
            let lp: Float = m == .sand ? 4200 : (m == .snow ? 2600 : 1800)
            var g = grains(Int(14 * scale), spread: 0.14 * scale, lp: lp * p, hp: 900, decay: 0.008, gain: gain * 0.9)
            if m == .soul { g = Synth.mix(g, burst(0.3 * scale, lp: 500 * p, hp: 80, attack: 0.02, decay: 0.08 * scale, gain: gain * 1.4)) }
            return g
        case .mud:
            return Synth.mix(burst(0.3 * scale, lp: 600 * p, hp: 60, attack: 0.01, decay: 0.07 * scale, gain: gain * 2.0),
                             bubbles(0.25 * scale, count: Int(4 * scale), fLo: 300 * p, fHi: 900 * p, len: 0.04, gain: gain * 0.5))
        case .wood:
            let knock = modes(0.3 * scale, [(190 * p, 0.7, 0.05), (410 * p, 0.45, 0.035), (870 * p, 0.2, 0.02)])
            return Synth.mix(Synth.scaled(knock, gain * 1.3), burst(0.05, lp: 3000, hp: 400, decay: 0.008, gain: gain * 0.6))
        case .plant, .leaves:
            return grains(Int(16 * scale), spread: 0.16 * scale, lp: 6000 * p, hp: 1800, decay: 0.01, gain: gain * 0.9)
        case .wool:
            return Synth.mix(burst(0.18 * scale, lp: 1400 * p, hp: 200, attack: 0.005, decay: 0.05 * scale, gain: gain * 1.3),
                             grains(Int(6 * scale), spread: 0.1 * scale, lp: 2500 * p, hp: 600, decay: 0.012, gain: gain * 0.4))
        case .glass, .amethyst:
            var out = burst(0.25, lp: 9000, hp: 2500, decay: 0.04, gain: gain * (m == .glass ? 0.8 : 0.4))
            for _ in 0..<Int(7 * scale) {
                let f = (m == .glass ? 2200 + 3800 * rnd() : 1800 + 2600 * rnd()) * p
                let ping = m == .glass ? modes(0.3, [(f, 0.25, 0.04 + 0.05 * rnd())]) : fm(0.5, f: f, ratio: 3.01, index: 1.5, decay: 0.12 + 0.1 * rnd(), gain: 0.25)
                out = Synth.mix(out, ping, at: frames(rnd() * 0.08), gain: gain)
            }
            return out
        case .metal:
            let ring = modes(0.5 * scale, [(620 * p, 0.5, 0.12 * scale), (1480 * p, 0.35, 0.08 * scale), (2330 * p, 0.2, 0.05), (3900 * p, 0.1, 0.03)])
            return Synth.mix(Synth.scaled(ring, gain * 1.2), burst(0.06, lp: 7000, hp: 1200, decay: 0.01, gain: gain * 0.7))
        case .slime:
            let squish = burst(0.22 * scale, lp: 900 * p, hp: 90, attack: 0.015, decay: 0.06 * scale, gain: gain * 2.0)
            return Synth.mix(squish, bubbles(0.2 * scale, count: Int(3 * scale), fLo: 200 * p, fHi: 600 * p, len: 0.06, gain: gain * 0.6))
        case .bone:
            let knock = modes(0.25 * scale, [(520 * p, 0.6, 0.03), (1330 * p, 0.35, 0.02), (2600 * p, 0.15, 0.012)])
            return Synth.mix(Synth.scaled(knock, gain * 1.3), grains(Int(4 * scale), spread: 0.06 * scale, lp: 4000 * p, hp: 800, decay: 0.008, gain: gain * 0.6))
        case .netherrack:
            // Brittle and dull: many short low grains with a soft thud.
            return Synth.mix(grains(Int(12 * scale), spread: 0.1 * scale, lp: 1800 * p, hp: 250, decay: 0.01, gain: gain * 1.5),
                             burst(0.15 * scale, lp: 500 * p, hp: 60, decay: 0.03 * scale, gain: gain * 1.2))
        case .deepslate:
            // Denser than stone: fewer, lower grains and a knock.
            return Synth.mix(grains(Int(7 * scale), spread: 0.08 * scale, lp: 2300 * p, hp: 300, decay: 0.014, gain: gain * 1.6),
                             modes(0.15 * scale, [(310 * p, 0.35, 0.03), (720 * p, 0.2, 0.02)]))
        case .sculk:
            let squelch = burst(0.3 * scale, lp: 500 * p, hp: 50, attack: 0.02, decay: 0.09 * scale, gain: gain * 2.2)
            return Synth.mix(squelch, tone(0.25 * scale, f0: 180 * p, f1: 90 * p, wave: .sine, attack: 0.02, release: 0.1, gain: gain * 0.5))
        }
    }

    // MARK: Loops and ambience

    mutating func fireLoop(_ dur: Float, size: Float, pitch p: Float) -> [Float] {
        let bed = wash(dur, lp: 900 * size, hp: 120, wobble: 0.6, rate: 3, gain: 0.5)
        let pops = crackle(dur, density: 18 * size, f: 2600 * p, q: 2.5, gain: 2.2)
        let hiss = wash(dur, lp: 6000, hp: 2500, wobble: 0.8, rate: 5, gain: 0.08)
        return Synth.loopify(Synth.mix(Synth.mix(bed, pops), hiss), fade: 0.25)
    }

    mutating func waterLoop(_ dur: Float, pitch p: Float) -> [Float] {
        let bed = wash(dur, lp: 2600 * p, hp: 300, wobble: 0.9, rate: 4, gain: 0.45)
        let bub = bubbles(dur, count: Int(dur * 6), fLo: 500 * p, fHi: 1800 * p, len: 0.05, gain: 0.35)
        return Synth.loopify(Synth.mix(bed, bub), fade: 0.3)
    }

    mutating func lavaLoop(_ dur: Float, pitch p: Float) -> [Float] {
        let bed = wash(dur, lp: 260 * p, hp: 40, wobble: 0.7, rate: 1.5, gain: 1.6)
        let bub = bubbles(dur, count: Int(dur * 2), fLo: 70 * p, fHi: 160 * p, len: 0.18, gain: 0.7)
        let sizzle = wash(dur, lp: 5000, hp: 2000, wobble: 1, rate: 2, gain: 0.05)
        return Synth.loopify(Synth.mix(Synth.mix(bed, bub), sizzle), fade: 0.4)
    }

    mutating func portalLoop(_ dur: Float) -> [Float] {
        var out = [Float](repeating: 0, count: frames(dur))
        for k in 0..<5 {
            let f: Float = 55 * powf(1.5, Float(k)) * (1 + 0.01 * noise())
            out = Synth.mix(out, tone(dur, f0: f, f1: f * 1.02, wave: .sine, attack: 0.3, release: 0.3, vib: 0.03, vibRate: 0.3 + 0.2 * Float(k), gain: 0.25 / Float(k + 1)))
        }
        out = Synth.mix(out, wash(dur, lp: 1800, hp: 400, wobble: 1.2, rate: 0.7, gain: 0.18))
        return Synth.loopify(out, fade: 0.6)
    }

    mutating func windLoop(_ dur: Float, lp: Float, gain: Float) -> [Float] {
        Synth.loopify(wash(dur, lp: lp, hp: 60, wobble: 1.5, rate: 0.4, gain: gain), fade: 0.8)
    }

    mutating func rainLoop(_ dur: Float, roof: Bool) -> [Float] {
        let bed = wash(dur, lp: roof ? 1500 : 6000, hp: roof ? 200 : 1200, wobble: 0.3, rate: 2, gain: roof ? 0.5 : 0.35)
        let drops = crackle(dur, density: roof ? 60 : 140, f: roof ? 900 : 4500, q: roof ? 3 : 1.5, gain: roof ? 1.2 : 0.8)
        return Synth.loopify(Synth.mix(bed, drops), fade: 0.4)
    }

    mutating func underwaterLoop(_ dur: Float) -> [Float] {
        let bed = wash(dur, lp: 400, hp: 40, wobble: 1.2, rate: 0.5, gain: 1.2)
        let bub = bubbles(dur, count: Int(dur * 1.5), fLo: 200, fHi: 700, len: 0.12, gain: 0.3)
        return Synth.loopify(Synth.mix(bed, bub), fade: 0.5)
    }

    // A slow drone of detuned sines with a noise bed (biome ambience beds).
    mutating func droneLoop(_ dur: Float, f: Float, partials: Int, detune: Float, noiseLP: Float, noiseGain: Float, gain: Float) -> [Float] {
        var out = [Float](repeating: 0, count: frames(dur))
        for k in 0..<partials {
            let fk = f * Float(k + 1) * (1 + detune * noise())
            out = Synth.mix(out, tone(dur, f0: fk, f1: fk, wave: .sine, attack: 0.5, release: 0.5, vib: 0.01, vibRate: 0.2 + 0.3 * rnd(), gain: gain / Float(k + 1)))
        }
        if noiseGain > 0 { out = Synth.mix(out, wash(dur, lp: noiseLP, hp: 50, wobble: 1, rate: 0.5, gain: noiseGain)) }
        return Synth.loopify(out, fade: 0.8)
    }

    // A songbird phrase: 2-6 FM chirps with pitch sweeps, sometimes a trill.
    mutating func birdCall(pitch p: Float) -> [Float] {
        var out: [Float] = []
        let n = 2 + Int(rnd() * 5)
        let base: Float = rnd(2200, 4200) * p
        var t: Float = 0
        let trill = rnd() < 0.3
        for k in 0..<n {
            let len: Float = trill ? 0.04 : rnd(0.05, 0.16)
            let f0: Float = base * rnd(0.85, 1.2)
            let up: Bool = rnd() < 0.5
            let f1: Float = up ? f0 * rnd(1.1, 1.5) : f0 * rnd(0.6, 0.9)
            let c = tone(len, f0: f0, f1: f1, wave: .sine, attack: 0.006, release: len * 0.5, vib: trill ? 0 : 0.03, vibRate: 40, gain: 0.5)
            out = Synth.mix(out, c, at: frames(t))
            t += len + (trill ? 0.015 : rnd(0.03, 0.12))
            if k == n - 1 && rnd() < 0.4 { t += 0.05 }
        }
        return Synth.echo(out, delay: 0.13, feedback: 0.15, mix: 0.2, tail: 0.3)
    }

    // Several crickets: pulse trains (~30 pulses/s) of a 4-5 kHz tone, each cricket with its own rhythm.
    mutating func cricketsLoop(_ dur: Float, voices: Int = 3) -> [Float] {
        let n = frames(dur)
        var out = [Float](repeating: 0, count: n)
        for _ in 0..<voices {
            let f: Float = rnd(3800, 5200)
            let pulse: Float = rnd(25, 40)
            let chirpLen: Float = rnd(0.12, 0.3), gap: Float = rnd(0.25, 0.7)
            let pan: Float = rnd(0.4, 1)
            var t: Float = rnd(0, gap)
            while t < dur - chirpLen {
                let c = tone(chirpLen, f0: f, f1: f, wave: .sine, attack: 0.01, release: 0.03, gain: 0.25 * pan)
                var gated = c
                for i in 0..<gated.count {
                    let ph: Float = Float(i) / Synth.sr * pulse
                    let gate: Float = ph - floorf(ph) < 0.45 ? 1 : 0
                    gated[i] *= gate
                }
                let at = frames(t)
                for i in 0..<gated.count where at + i < n { out[at + i] += gated[i] }
                t += chirpLen + gap * rnd(0.8, 1.2)
            }
        }
        out = Synth.bandpass(out, 4500, q: 1.2)
        return Synth.loopify(out, fade: 0.3)
    }

    // Waves: slow swells of filtered noise with a hiss on each break.
    mutating func oceanLoop(_ dur: Float) -> [Float] {
        let n = frames(dur)
        let low = wash(dur, lp: 700, hp: 60, wobble: 0.5, rate: 0.5, gain: 1.2)
        let high = wash(dur, lp: 5000, hp: 1500, wobble: 0.8, rate: 1, gain: 0.25)
        var out = [Float](repeating: 0, count: n)
        let period: Float = dur / 2
        for i in 0..<n {
            let t: Float = Float(i) / Synth.sr
            let ph: Float = (t / period).truncatingRemainder(dividingBy: 1)
            let swell: Float = 0.35 + 0.65 * powf(sinf(ph * Float.pi), 2)
            let brk: Float = ph > 0.45 && ph < 0.75 ? sinf((ph - 0.45) / 0.3 * Float.pi) : 0
            out[i] = low[i] * swell + high[i] * brk
        }
        return Synth.loopify(out, fade: 0.4)
    }

    // Frogs: low throaty croaks in loose rhythm.
    mutating func frogs(_ dur: Float) -> [Float] {
        var out = [Float](repeating: 0, count: frames(dur))
        for _ in 0..<3 {
            let f0: Float = rnd(90, 180)
            var t: Float = rnd(0, 0.8)
            while t < dur - 0.4 {
                let croaks = 1 + Int(rnd() * 3)
                for k in 0..<croaks {
                    let c = formant(0.12, f0: f0, f1: f0 * 0.9, formants: [(300, 5, 1), (900, 7, 0.4)], breath: 0.2, attack: 0.01, release: 0.04, growl: 0.4, gain: 0.8)
                    out = Synth.mix(out, c, at: frames(t + Float(k) * 0.16))
                }
                t += 0.5 + rnd(0.4, 1.6)
            }
        }
        return out
    }

    // MARK: Post

    // Normalizes, level-matches families and de-clicks both ends.
    static func finish(_ s: Snd, _ x: [Float]) -> [Float] {
        var out = x
        var peak: Float = 0
        for v in out where v.isFinite { peak = max(peak, abs(v)) }
        if peak > 0.9 { let k = 0.9 / peak; for i in 0..<out.count { out[i] *= k } }
        if peak > 0 && peak < 0.3 { let k = 0.6 / peak; for i in 0..<out.count { out[i] *= k } }
        let loud: Float
        switch s {
        case .hurt, .hurtFall, .hurtFire, .hurtDrown: loud = 0.5
        case .mob(_, .ambient), .babyMob(_, .ambient): loud = 0.55
        case .mob(_, .hurt), .mob(_, .death), .babyMob: loud = 0.6
        case .mobCow, .mobSheep, .mobZombie, .mobVoidwalker, .mobPig, .mobChicken, .mobVillager: loud = 0.5
        case .click, .uiHover, .uiBack: loud = 0.7
        case _ where s.isLoop: loud = 0.8
        default: loud = 1
        }
        if loud != 1 { for i in 0..<out.count { out[i] *= loud } }
        for i in 0..<out.count where !out[i].isFinite { out[i] = 0 }
        if !s.isLoop {
            fadeIn(&out, 0.002)
            fadeOut(&out, 0.012)
        }
        return out
    }

    // MARK: The roster

    mutating func render(_ s: Snd, pitch p: Float) -> [Float] {
        var out: [Float]
        switch s {
        // Blocks
        case .breakBlock(let m): out = foleyBreak(m, p: p)
        case .place(let m): out = foleyPlace(m, p: p)
        case .step(let m): out = foleyStep(m, p: p)
        case .hit(let m): out = foleyHit(m, p: p)
        case .fall(let m): out = foleyFall(m, p: p)

        // Player
        case .splash:
            out = burst(0.55, lp: 1400 * p, hp: 150, attack: 0.01, decay: 0.15, gain: 1.2)
            out = Synth.mix(out, grains(20, spread: 0.3, lp: 5000, hp: 1500, decay: 0.01, gain: 0.3))
        case .swim: out = Synth.mix(burst(0.35, lp: 1800 * p, hp: 300, attack: 0.03, decay: 0.09, gain: 0.8), bubbles(0.3, count: 4, fLo: 600, fHi: 1500, len: 0.04, gain: 0.3))
        case .land: out = burst(0.18, lp: 300 * p, hp: 30, decay: 0.04, gain: 3)
        case .hurt:
            out = Synth.mix(formant(0.22, f0: 260 * p, f1: 150 * p, formants: [(600, 6, 1), (1100, 8, 0.6), (2500, 10, 0.25)], breath: 0.15, vib: 0.03, gain: 1.4),
                            burst(0.1, lp: 1200, hp: 200, decay: 0.03, gain: 0.5))
        case .hurtFall: out = Synth.mix(formant(0.3, f0: 240 * p, f1: 130 * p, formants: [(550, 6, 1), (1000, 8, 0.6)], breath: 0.2, gain: 1.3), burst(0.2, lp: 400, hp: 40, decay: 0.05, gain: 2.5))
        case .hurtDrown: out = Synth.mix(formant(0.35, f0: 220 * p, f1: 160 * p, formants: [(400, 5, 1), (800, 6, 0.5)], breath: 0.3, gain: 1.0), bubbles(0.4, count: 8, fLo: 300, fHi: 900, len: 0.05, gain: 0.5))
        case .hurtFire: out = Synth.mix(formant(0.28, f0: 300 * p, f1: 200 * p, formants: [(700, 6, 1), (1400, 8, 0.6), (2800, 10, 0.3)], breath: 0.2, vib: 0.08, vibRate: 9, gain: 1.3), burst(0.25, lp: 3000, hp: 800, attack: 0.01, decay: 0.08, gain: 0.4))
        case .playerDeath:
            out = formant(0.9, f0: 230 * p, f1: 90 * p, formants: [(550, 5, 1), (1000, 7, 0.6), (2400, 9, 0.2)], breath: 0.25, vib: 0.05, vibRate: 4, attack: 0.02, release: 0.4, gain: 1.4)
            out = Synth.mix(out, burst(0.4, lp: 500, hp: 40, attack: 0.1, decay: 0.15, gain: 1.5))
        case .eat:
            out = []
            for k in 0..<3 { out = Synth.mix(out, grains(6, spread: 0.04, lp: 2500 * p, hp: 300, decay: 0.012, gain: 0.9), at: frames(Float(k) * 0.16)) }
        case .burp: out = formant(0.3, f0: 120 * p, f1: 90 * p, formants: [(400, 4, 1), (900, 5, 0.5)], breath: 0.2, vib: 0.1, vibRate: 12, gain: 1.0)
        case .drink: out = Synth.mix(grains(6, spread: 0.5, lp: 900 * p, hp: 150, decay: 0.05, gain: 1.0), bubbles(0.5, count: 5, fLo: 200, fHi: 500, len: 0.06, gain: 0.5))
        case .pickup: out = Synth.mix(modes(0.09, [(1500 * p, 0.3, 0.02)]), modes(0.08, [(2100 * p, 0.25, 0.02)]), at: frames(0.03))
        case .dig: out = burst(0.06, lp: 2500 * p, hp: 300, decay: 0.012, gain: 0.8)
        case .attack: out = burst(0.12, lp: 1800 * p, hp: 200, decay: 0.03, gain: 1.4)
        case .attackSweep: out = Synth.window(wash(0.28, lp: 2600 * p, hp: 500, wobble: 0.2, rate: 30, gain: 0.8))
        case .attackCrit: out = Synth.mix(burst(0.15, lp: 2200 * p, hp: 300, decay: 0.03, gain: 1.4), modes(0.3, [(2600 * p, 0.3, 0.06), (3900 * p, 0.2, 0.05)]))
        case .attackKnockback: out = Synth.mix(burst(0.2, lp: 800 * p, hp: 60, decay: 0.05, gain: 2.5), burst(0.1, lp: 3000, hp: 500, decay: 0.02, gain: 0.6))
        case .attackWeak: out = burst(0.07, lp: 1200 * p, hp: 200, decay: 0.015, gain: 0.9)
        case .shieldBlock: out = Synth.mix(modes(0.3, [(240 * p, 0.7, 0.05), (520 * p, 0.4, 0.04), (1100 * p, 0.2, 0.02)]), burst(0.06, lp: 2500, hp: 300, decay: 0.012, gain: 0.8))
        case .shieldBreak: out = Synth.mix(material(.wood, pitch: p * 0.9, scale: 1.6, gain: 0.6), grains(8, spread: 0.2, lp: 4000, hp: 800, decay: 0.01, gain: 0.5))
        case .armorEquip(let t):
            switch t {
            case 0: out = Synth.mix(burst(0.2, lp: 1200 * p, hp: 200, attack: 0.01, decay: 0.06, gain: 1.2), burst(0.15, lp: 900, hp: 150, attack: 0.01, decay: 0.05, gain: 0.8), at: frames(0.1))  // leather
            case 1: out = grains(12, spread: 0.25, lp: 5000 * p, hp: 1500, decay: 0.006, gain: 1.1)                       // chain
            case 3: out = Synth.mix(modes(0.35, [(1900 * p, 0.4, 0.1), (2900 * p, 0.3, 0.08)]), burst(0.05, lp: 6000, hp: 1500, decay: 0.01, gain: 0.6))   // gold
            case 4: out = Synth.mix(modes(0.4, [(2600 * p, 0.4, 0.15), (4100 * p, 0.3, 0.1), (5200 * p, 0.15, 0.06)]), burst(0.05, lp: 8000, hp: 2500, decay: 0.01, gain: 0.5))   // diamond
            case 5: out = Synth.mix(modes(0.4, [(480 * p, 0.6, 0.12), (1240 * p, 0.3, 0.08)]), burst(0.08, lp: 2500, hp: 300, decay: 0.02, gain: 0.8))    // duskium
            default: out = Synth.mix(modes(0.3, [(1100 * p, 0.5, 0.08), (2300 * p, 0.3, 0.06)]), burst(0.06, lp: 5000, hp: 900, decay: 0.012, gain: 0.7))   // iron
            }
        case .itemBreak: out = Synth.mix(grains(6, spread: 0.08, lp: 3500 * p, hp: 600, decay: 0.01, gain: 1.0), modes(0.2, [(900 * p, 0.4, 0.04)]))
        case .bucketFill: out = Synth.mix(bubbles(0.45, count: 9, fLo: 400 * p, fHi: 1400 * p, len: 0.06, gain: 0.7), burst(0.4, lp: 1500, hp: 300, attack: 0.02, decay: 0.12, gain: 0.5))
        case .bucketEmpty: out = Synth.mix(burst(0.5, lp: 1200 * p, hp: 200, attack: 0.03, decay: 0.15, gain: 1.0), bubbles(0.4, count: 6, fLo: 300, fHi: 900, len: 0.05, gain: 0.4))
        case .bucketFillLava: out = Synth.mix(bubbles(0.5, count: 4, fLo: 70 * p, fHi: 160 * p, len: 0.15, gain: 1.0), burst(0.5, lp: 400, hp: 40, attack: 0.02, decay: 0.15, gain: 1.4))
        case .bucketEmptyLava: out = Synth.mix(burst(0.6, lp: 350 * p, hp: 30, attack: 0.05, decay: 0.2, gain: 1.8), wash(0.5, lp: 4000, hp: 1500, wobble: 1, rate: 3, gain: 0.08))
        case .fishCast: out = Synth.mix(Synth.decayEnv(wash(0.25, lp: 3000, hp: 600, wobble: 0.2, rate: 20, gain: 0.5), 0.08), modes(0.1, [(1400 * p, 0.3, 0.02)]))
        case .fishSplash: out = Synth.mix(burst(0.3, lp: 1600 * p, hp: 200, attack: 0.005, decay: 0.08, gain: 1.2), bubbles(0.3, count: 5, fLo: 500, fHi: 1500, len: 0.04, gain: 0.4))
        case .fishReel: out = Synth.mix(burst(0.3, lp: 2000 * p, hp: 300, attack: 0.005, decay: 0.08, gain: 1.0), grains(6, spread: 0.2, lp: 3000, hp: 800, decay: 0.008, gain: 0.5))
        case .xp: out = modes(0.2, [(1760 * p, 0.25, 0.05), (2637 * p, 0.12, 0.04)])
        case .levelUp: out = Synth.mix(Synth.mix(modes(0.5, [(523, 0.3, 0.15)]), modes(0.5, [(659, 0.3, 0.15)]), at: frames(0.1)), modes(0.8, [(784, 0.3, 0.3)]), at: frames(0.2))
        case .totem:
            out = []
            for (k, f) in [392, 523, 659, 784, 1047].enumerated() { out = Synth.mix(out, fm(1.2, f: Float(f), ratio: 2, index: 1.2, decay: 0.5, gain: 0.3), at: frames(Float(k) * 0.09)) }
            out = Synth.mix(out, Synth.window(wash(1.4, lp: 4000, hp: 800, wobble: 0.5, rate: 6, gain: 0.15)))
        case .gasp: out = Synth.mix(burst(0.35, lp: 2500 * p, hp: 400, attack: 0.15, decay: 0.12, gain: 0.7), formant(0.3, f0: 200 * p, f1: 260 * p, formants: [(700, 6, 0.6), (1500, 8, 0.4)], breath: 0.6, gain: 0.5))
        case .throwItem: out = Synth.window(wash(0.2, lp: 2400 * p, hp: 500, wobble: 0.2, rate: 20, gain: 0.6))
        case .pearlThrow: out = Synth.mix(tone(0.25, f0: 900 * p, f1: 1500 * p, wave: .sine, attack: 0.01, release: 0.1, gain: 0.3), wash(0.2, lp: 3000, hp: 600, wobble: 0.2, rate: 20, gain: 0.4))
        case .potionThrow: out = Synth.mix(modes(0.15, [(1800 * p, 0.3, 0.03), (2700 * p, 0.2, 0.02)]), wash(0.2, lp: 2400, hp: 500, wobble: 0.2, rate: 20, gain: 0.4))
        case .potionSplash: out = Synth.mix(burst(0.25, lp: 9000, hp: 2500, decay: 0.05, gain: 0.8), bubbles(0.3, count: 8, fLo: 800, fHi: 2400, len: 0.03, gain: 0.3))
        case .snowballHit: out = burst(0.12, lp: 1800 * p, hp: 300, decay: 0.03, gain: 1.0)
        case .eggCrack: out = Synth.mix(grains(4, spread: 0.04, lp: 4000 * p, hp: 900, decay: 0.008, gain: 1.0), burst(0.1, lp: 1500, hp: 300, decay: 0.03, gain: 0.5))
        case .bowDraw: out = Synth.mix(Synth.rampIn(wash(0.4, lp: 1200 * p, hp: 200, wobble: 0.3, rate: 15, gain: 0.5), 0.3), tone(0.4, f0: 90 * p, f1: 140 * p, wave: .saw, attack: 0.05, release: 0.05, gain: 0.08))
        case .bow: out = Synth.mix(modes(0.25, [(220 * p, 0.5, 0.05), (440 * p, 0.2, 0.03)]), burst(0.15, lp: 3000, hp: 800, decay: 0.03, gain: 0.5))
        case .arrowHit: out = Synth.mix(modes(0.15, [(160 * p, 0.6, 0.03)]), burst(0.05, lp: 2000, hp: 300, decay: 0.01, gain: 0.6))
        case .crossbowLoad: out = repeated({ g in g.grains(3, spread: 0.03, lp: 3000, hp: 600, decay: 0.008, gain: 0.9) }, times: 5, interval: 0.11)
        case .crossbowShoot: out = Synth.mix(modes(0.2, [(170 * p, 0.6, 0.04), (340 * p, 0.3, 0.03)]), burst(0.12, lp: 4000, hp: 1000, decay: 0.03, gain: 0.8))
        case .tridentThrow: out = Synth.mix(Synth.window(wash(0.35, lp: 2600 * p, hp: 400, wobble: 0.2, rate: 20, gain: 0.7)), modes(0.3, [(1200 * p, 0.2, 0.08)]))
        case .tridentHit: out = Synth.mix(modes(0.4, [(900 * p, 0.5, 0.1), (1900 * p, 0.3, 0.06)]), burst(0.06, lp: 6000, hp: 1200, decay: 0.012, gain: 0.7))
        case .tridentReturn: out = Synth.mix(tone(0.4, f0: 600 * p, f1: 1400 * p, wave: .sine, attack: 0.02, release: 0.15, gain: 0.3), wash(0.35, lp: 3000, hp: 600, wobble: 0.2, rate: 20, gain: 0.4))
        case .riptide: out = Synth.mix(burst(0.8, lp: 1500 * p, hp: 200, attack: 0.05, decay: 0.25, gain: 1.2), bubbles(0.7, count: 12, fLo: 400, fHi: 1400, len: 0.05, gain: 0.4))
        case .windCharge: out = Synth.mix(burst(0.4, lp: 2500 * p, hp: 300, attack: 0.005, decay: 0.12, gain: 1.4), tone(0.3, f0: 500 * p, f1: 120 * p, wave: .sine, attack: 0.005, release: 0.2, gain: 0.4))
        case .shearsSnip: out = Synth.mix(modes(0.12, [(2400 * p, 0.4, 0.02), (4200 * p, 0.2, 0.015)]), burst(0.06, lp: 6000, hp: 1500, decay: 0.01, gain: 0.7))
        case .ignite: out = Synth.mix(grains(3, spread: 0.03, lp: 5000 * p, hp: 1200, decay: 0.006, gain: 1.0), burst(0.3, lp: 3000, hp: 600, attack: 0.03, decay: 0.1, gain: 0.5), at: frames(0.05))
        case .spyglass: out = Synth.mix(modes(0.15, [(1300 * p, 0.3, 0.03)]), burst(0.08, lp: 3000, hp: 500, decay: 0.02, gain: 0.5))
        case .goatHorn: out = Synth.mix(formant(2.6, f0: 220, f1: 196, formants: [(500, 4, 1), (1200, 6, 0.6), (2400, 8, 0.3)], breath: 0.05, vib: 0.12, vibRate: 5, attack: 0.08, release: 0.4, gain: 1.2), voice(2.6, f0: 330, f1: 294, vib: 0.1, lp: 2000, gain: 0.4))

        // Interface
        case .click: out = modes(0.05, [(1100 * p, 0.35, 0.008), (2200 * p, 0.1, 0.004)])
        case .uiHover: out = modes(0.03, [(1600 * p, 0.2, 0.005)])
        case .uiBack: out = modes(0.06, [(800 * p, 0.35, 0.01), (1600 * p, 0.1, 0.005)])
        case .toast: out = Synth.mix(modes(0.3, [(1320 * p, 0.3, 0.08)]), modes(0.35, [(1760 * p, 0.3, 0.1)]), at: frames(0.08))
        case .open: out = Synth.mix(modes(0.12, [(660 * p, 0.25, 0.03)]), modes(0.12, [(990 * p, 0.2, 0.03)]), at: frames(0.05))

        // Doors and containers
        case .doorOpen: out = Synth.mix(tone(0.22, f0: 320 * p, f1: 520 * p, wave: .saw, attack: 0.02, release: 0.08, gain: 0.12), material(.wood, pitch: p * 1.1, scale: 0.7, gain: 0.5), at: frames(0.12))
        case .doorClose: out = Synth.mix(tone(0.15, f0: 480 * p, f1: 300 * p, wave: .saw, attack: 0.02, release: 0.05, gain: 0.1), material(.wood, pitch: p * 0.9, scale: 1.0, gain: 0.6), at: frames(0.1))
        case .ironDoorOpen: out = Synth.mix(tone(0.3, f0: 900 * p, f1: 1300 * p, wave: .saw, attack: 0.02, release: 0.1, gain: 0.08), material(.metal, pitch: p, scale: 0.8, gain: 0.6), at: frames(0.15))
        case .ironDoorClose: out = Synth.mix(material(.metal, pitch: p * 0.8, scale: 1.2, gain: 0.7), burst(0.2, lp: 500, hp: 40, decay: 0.05, gain: 1.5))
        case .trapdoorOpen: out = Synth.mix(tone(0.15, f0: 400 * p, f1: 600 * p, wave: .saw, attack: 0.01, release: 0.05, gain: 0.1), material(.wood, pitch: p * 1.2, scale: 0.6, gain: 0.5), at: frames(0.08))
        case .trapdoorClose: out = material(.wood, pitch: p * 0.85, scale: 1.1, gain: 0.6)
        case .ironTrapdoorOpen: out = Synth.mix(tone(0.2, f0: 1100 * p, f1: 1500 * p, wave: .saw, attack: 0.01, release: 0.05, gain: 0.07), material(.metal, pitch: p * 1.1, scale: 0.6, gain: 0.5), at: frames(0.1))
        case .ironTrapdoorClose: out = material(.metal, pitch: p * 0.9, scale: 1.0, gain: 0.7)
        case .gateOpen: out = Synth.mix(tone(0.25, f0: 260 * p, f1: 420 * p, wave: .saw, attack: 0.03, release: 0.08, gain: 0.1), material(.wood, pitch: p, scale: 0.5, gain: 0.45), at: frames(0.15))
        case .gateClose: out = Synth.mix(tone(0.12, f0: 380 * p, f1: 260 * p, wave: .saw, attack: 0.02, release: 0.04, gain: 0.08), material(.wood, pitch: p * 0.95, scale: 0.9, gain: 0.55), at: frames(0.08))
        case .chestOpen: out = Synth.mix(tone(0.35, f0: 180 * p, f1: 260 * p, wave: .saw, attack: 0.04, release: 0.1, gain: 0.12), material(.wood, pitch: p * 0.8, scale: 0.6, gain: 0.4), at: frames(0.02))
        case .chestClose: out = Synth.mix(tone(0.2, f0: 240 * p, f1: 170 * p, wave: .saw, attack: 0.02, release: 0.05, gain: 0.1), material(.wood, pitch: p * 0.75, scale: 1.2, gain: 0.6), at: frames(0.12))
        case .enderChestOpen: out = Synth.mix(tone(0.5, f0: 220 * p, f1: 440 * p, wave: .sine, attack: 0.05, release: 0.2, vib: 0.05, vibRate: 8, gain: 0.3), wash(0.5, lp: 2500, hp: 400, wobble: 1, rate: 4, gain: 0.25))
        case .enderChestClose: out = Synth.mix(tone(0.4, f0: 440 * p, f1: 200 * p, wave: .sine, attack: 0.02, release: 0.2, vib: 0.05, vibRate: 8, gain: 0.3), burst(0.2, lp: 800, hp: 100, decay: 0.05, gain: 1.0), at: frames(0.2))
        case .barrelOpen: out = Synth.mix(material(.wood, pitch: p * 1.1, scale: 0.6, gain: 0.5), tone(0.2, f0: 300 * p, f1: 380 * p, wave: .saw, attack: 0.02, release: 0.06, gain: 0.08))
        case .barrelClose: out = material(.wood, pitch: p * 0.9, scale: 1.1, gain: 0.6)
        case .shulkerOpen: out = Synth.mix(tone(0.4, f0: 300 * p, f1: 520 * p, wave: .tri, attack: 0.05, release: 0.15, gain: 0.25), burst(0.3, lp: 1500, hp: 200, attack: 0.05, decay: 0.1, gain: 0.5))
        case .shulkerClose: out = Synth.mix(tone(0.3, f0: 520 * p, f1: 280 * p, wave: .tri, attack: 0.02, release: 0.1, gain: 0.25), burst(0.15, lp: 900, hp: 100, decay: 0.04, gain: 1.0), at: frames(0.18))

        // Mechanisms
        case .pistonExtend: out = Synth.mix(Synth.rampIn(wash(0.3, lp: 1400 * p, hp: 200, wobble: 0.3, rate: 30, gain: 0.6), 0.05), material(.stone, pitch: p * 0.8, scale: 0.7, gain: 0.5), at: frames(0.22))
        case .pistonContract: out = Synth.mix(wash(0.25, lp: 1200 * p, hp: 200, wobble: 0.3, rate: 30, gain: 0.6), material(.wood, pitch: p * 0.8, scale: 0.7, gain: 0.5), at: frames(0.18))
        case .lever: out = Synth.mix(modes(0.08, [(1500 * p, 0.4, 0.015), (700 * p, 0.3, 0.02)]), burst(0.04, lp: 4000, hp: 800, decay: 0.008, gain: 0.8))
        case .buttonWood: out = Synth.mix(modes(0.07, [(900 * p, 0.5, 0.015)]), burst(0.03, lp: 3000, hp: 600, decay: 0.006, gain: 0.7))
        case .buttonStone: out = Synth.mix(modes(0.06, [(1600 * p, 0.4, 0.01)]), burst(0.03, lp: 5000, hp: 900, decay: 0.006, gain: 0.8))
        case .plateOn: out = Synth.mix(modes(0.08, [(600 * p, 0.5, 0.02)]), burst(0.04, lp: 2500, hp: 400, decay: 0.008, gain: 0.7))
        case .plateOff: out = Synth.mix(modes(0.08, [(720 * p, 0.4, 0.02)]), burst(0.04, lp: 2500, hp: 400, decay: 0.008, gain: 0.5))
        case .dispense: out = Synth.mix(burst(0.12, lp: 2000 * p, hp: 300, decay: 0.03, gain: 1.2), modes(0.1, [(400 * p, 0.4, 0.03)]))
        case .dispenseFail: out = repeated({ g in g.modes(0.06, [(500, 0.4, 0.015)]) }, times: 2, interval: 0.09, jitter: 0)
        case .tripwire: out = Synth.mix(modes(0.1, [(2800 * p, 0.3, 0.02)]), burst(0.03, lp: 6000, hp: 1500, decay: 0.005, gain: 0.6))
        case .fizz: out = burst(0.6, lp: 8000, hp: 3000, attack: 0.02, decay: 0.25, gain: 0.9)
        case .railClick: out = Synth.mix(modes(0.08, [(2200 * p, 0.3, 0.015)]), burst(0.03, lp: 5000, hp: 1200, decay: 0.006, gain: 0.5))
        case .anvil:
            out = Synth.mix(modes(0.9, [(830 * p, 0.5, 0.35), (1970 * p, 0.3, 0.25), (3120 * p, 0.2, 0.12), (4410 * p, 0.12, 0.08)]),
                            burst(0.05, lp: 9000, hp: 2000, attack: 0.001, decay: 0.02, gain: 0.8))
        case .anvilLand: out = Synth.mix(modes(0.6, [(410 * p, 0.6, 0.25), (980 * p, 0.3, 0.15)]), burst(0.2, lp: 400, hp: 30, decay: 0.05, gain: 2.5))
        case .anvilBreak: out = Synth.mix(modes(0.5, [(620 * p, 0.5, 0.12), (1300 * p, 0.3, 0.08)]), grains(10, spread: 0.2, lp: 2500, hp: 300, decay: 0.012, gain: 1.2))
        case .brew: out = Synth.mix(grains(10, spread: 0.6, lp: 3000 * p, hp: 600, decay: 0.03, gain: 0.7), bubbles(0.7, count: 8, fLo: 500, fHi: 1600, len: 0.05, gain: 0.35))
        case .enchant: out = Synth.mix(modes(1.0, [(1320 * p, 0.2, 0.5), (1980 * p, 0.15, 0.4)]), modes(1.0, [(1760 * p, 0.15, 0.5)]), at: frames(0.12))
        case .grindstone: out = Synth.mix(wash(0.45, lp: 3500 * p, hp: 800, wobble: 0.8, rate: 12, gain: 0.5), crackle(0.45, density: 60, f: 4000, q: 3, gain: 1.0))
        case .smithing: out = Synth.mix(modes(0.4, [(1100 * p, 0.5, 0.08), (2300 * p, 0.3, 0.06)]), burst(0.06, lp: 6000, hp: 1200, decay: 0.012, gain: 0.8))
        case .pageTurn: out = burst(0.18, lp: 3500 * p, hp: 800, attack: 0.03, decay: 0.05, gain: 0.7)
        case .composterFill: out = Synth.mix(grains(8, spread: 0.15, lp: 1200 * p, hp: 150, decay: 0.02, gain: 0.9), burst(0.15, lp: 600, hp: 80, decay: 0.04, gain: 1.0))
        case .composterReady: out = Synth.mix(grains(6, spread: 0.2, lp: 1000 * p, hp: 120, decay: 0.03, gain: 0.8), modes(0.3, [(500 * p, 0.3, 0.06)]), at: frames(0.15))
        case .itemFrameAdd: out = Synth.mix(material(.wood, pitch: p * 1.2, scale: 0.4, gain: 0.5), modes(0.1, [(1800 * p, 0.2, 0.03)]))
        case .itemFrameRemove: out = Synth.mix(material(.wood, pitch: p * 1.1, scale: 0.4, gain: 0.5), burst(0.08, lp: 2500, hp: 400, decay: 0.02, gain: 0.5))
        case .itemFrameRotate: out = Synth.mix(modes(0.06, [(1300 * p, 0.3, 0.012)]), burst(0.03, lp: 3000, hp: 600, decay: 0.006, gain: 0.5))
        case .paintingPlace: out = Synth.mix(material(.wool, pitch: p, scale: 0.7, gain: 0.5), material(.wood, pitch: p * 1.1, scale: 0.4, gain: 0.3), at: frames(0.04))
        case .paintingBreak: out = Synth.mix(material(.wool, pitch: p * 0.9, scale: 1.2, gain: 0.6), grains(4, spread: 0.1, lp: 2500, hp: 400, decay: 0.01, gain: 0.5))
        case .honeySlide: out = Synth.mix(wash(0.5, lp: 700 * p, hp: 80, wobble: 0.5, rate: 6, gain: 0.7), bubbles(0.5, count: 4, fLo: 200, fHi: 500, len: 0.08, gain: 0.4))
        case .amethystChime:
            out = []
            for _ in 0..<3 { let f = rnd(1400, 3200) * p; out = Synth.mix(out, fm(0.9, f: f, ratio: 2.76, index: 1.4, decay: 0.35, gain: 0.3), at: frames(rnd() * 0.15)) }
        case .waxOn: out = Synth.mix(burst(0.3, lp: 2000 * p, hp: 300, attack: 0.03, decay: 0.08, gain: 0.8), grains(4, spread: 0.2, lp: 3000, hp: 800, decay: 0.01, gain: 0.4))
        case .waxOff: out = Synth.mix(burst(0.25, lp: 3500 * p, hp: 600, attack: 0.01, decay: 0.07, gain: 0.9), modes(0.15, [(1500 * p, 0.2, 0.03)]))
        case .scrape: out = Synth.mix(wash(0.3, lp: 4000 * p, hp: 1000, wobble: 0.5, rate: 10, gain: 0.6), crackle(0.3, density: 80, f: 3500, q: 2, gain: 0.8))
        case .bulbOn: out = Synth.mix(modes(0.2, [(1900 * p, 0.35, 0.05), (2800 * p, 0.2, 0.04)]), burst(0.04, lp: 6000, hp: 1500, decay: 0.008, gain: 0.5))
        case .bulbOff: out = Synth.mix(modes(0.2, [(1500 * p, 0.35, 0.05), (2200 * p, 0.2, 0.03)]), burst(0.04, lp: 5000, hp: 1200, decay: 0.008, gain: 0.5))
        case .crafterCraft: out = Synth.mix(grains(5, spread: 0.12, lp: 3000 * p, hp: 500, decay: 0.01, gain: 0.9), modes(0.25, [(700 * p, 0.3, 0.06)]), at: frames(0.1))
        case .crafterFail: out = repeated({ g in g.modes(0.07, [(420, 0.4, 0.02)]) }, times: 2, interval: 0.1, jitter: 0)
        case .vaultOpen: out = Synth.mix(tone(0.6, f0: 200 * p, f1: 400 * p, wave: .tri, attack: 0.05, release: 0.2, gain: 0.3), material(.metal, pitch: p * 0.7, scale: 1.2, gain: 0.5), at: frames(0.3))
        case .vaultEject: out = Synth.mix(modes(0.4, [(1200 * p, 0.4, 0.08), (2400 * p, 0.2, 0.06)]), burst(0.1, lp: 3000, hp: 500, decay: 0.03, gain: 0.7))
        case .vaultReject: out = Synth.mix(modes(0.3, [(300 * p, 0.5, 0.08)]), burst(0.1, lp: 1500, hp: 200, decay: 0.03, gain: 0.7))
        case .spawnerSpawn: out = Synth.mix(tone(0.5, f0: 160 * p, f1: 400 * p, wave: .saw, attack: 0.05, release: 0.15, gain: 0.15), burst(0.5, lp: 2500, hp: 300, attack: 0.1, decay: 0.15, gain: 0.8))
        case .potBreak: out = Synth.mix(material(.stone, pitch: p * 1.3, scale: 1.2, gain: 0.5), modes(0.3, [(1800 * p, 0.3, 0.05), (2900 * p, 0.2, 0.04)]))
        case .potInsert: out = Synth.mix(modes(0.2, [(1100 * p, 0.4, 0.04), (2300 * p, 0.2, 0.03)]), burst(0.05, lp: 3000, hp: 600, decay: 0.01, gain: 0.5))
        case .bundleInsert: out = burst(0.2, lp: 1500 * p, hp: 250, attack: 0.01, decay: 0.05, gain: 1.0)
        case .bundleRemove: out = burst(0.18, lp: 1800 * p, hp: 300, attack: 0.02, decay: 0.04, gain: 0.9)
        case .bedEnter: out = Synth.mix(material(.wool, pitch: p * 0.9, scale: 1.0, gain: 0.5), burst(0.3, lp: 500, hp: 60, attack: 0.02, decay: 0.08, gain: 1.0))
        case .candleOut: out = burst(0.3, lp: 5000, hp: 1500, attack: 0.02, decay: 0.1, gain: 0.7)
        case .lanternHang: out = Synth.mix(material(.metal, pitch: p * 1.2, scale: 0.6, gain: 0.5), modes(0.4, [(2100 * p, 0.2, 0.1)]))
        case .respawnAnchorCharge: out = Synth.mix(tone(0.7, f0: 120 * p, f1: 360 * p, wave: .sine, attack: 0.05, release: 0.25, gain: 0.4), wash(0.7, lp: 2000, hp: 300, wobble: 1, rate: 3, gain: 0.25))
        case .respawnAnchorSet: out = Synth.mix(fm(1.0, f: 440 * p, ratio: 1.5, index: 1.5, decay: 0.4, gain: 0.4), fm(1.0, f: 660 * p, ratio: 1.5, index: 1.2, decay: 0.4, gain: 0.3), at: frames(0.12))
        case .sculkClick: out = Synth.mix(modes(0.12, [(900 * p, 0.4, 0.03), (1500 * p, 0.2, 0.02)]), burst(0.08, lp: 2000, hp: 300, decay: 0.02, gain: 0.7))
        case .sculkShriek: out = Synth.mix(formant(1.2, f0: 700 * p, f1: 1100 * p, formants: [(1200, 8, 1), (2600, 10, 0.7), (3800, 12, 0.4)], breath: 0.4, vib: 0.2, vibRate: 11, attack: 0.05, release: 0.3, gain: 1.2), wash(1.2, lp: 5000, hp: 1200, wobble: 1, rate: 8, gain: 0.3))
        case .sculkBloom: out = Synth.mix(tone(0.6, f0: 300 * p, f1: 120 * p, wave: .sine, attack: 0.05, release: 0.3, gain: 0.5), bubbles(0.6, count: 6, fLo: 150, fHi: 450, len: 0.08, gain: 0.4))
        case .sculkSpread: out = Synth.mix(burst(0.35, lp: 600 * p, hp: 60, attack: 0.03, decay: 0.1, gain: 1.6), tone(0.3, f0: 200 * p, f1: 80 * p, wave: .sine, attack: 0.02, release: 0.15, gain: 0.4))
        case .bell: out = modes(2.5, [(880, 0.5, 1.8), (2094.4, 0.25, 1.0), (2666.4, 0.15, 0.7), (440, 0.2, 1.5)])
        case .bellResonate: out = Synth.mix(modes(3.5, [(880, 0.3, 2.5), (1760, 0.15, 1.5), (440, 0.25, 2.2)]), wash(3.5, lp: 3000, hp: 600, wobble: 1, rate: 3, gain: 0.1))
        case .tntFuse: out = Synth.mix(wash(4.0, lp: 7000, hp: 2500, wobble: 0.5, rate: 8, gain: 0.5), crackle(4.0, density: 30, f: 5000, q: 2, gain: 0.5))
        case .explode: out = Synth.mix(burst(2.0, lp: 250 * p, hp: 20, attack: 0.003, decay: 0.5, gain: 4), burst(1.2, lp: 2500, hp: 200, decay: 0.2, gain: 1.2))
        case .glassBreak: out = Synth.mix(burst(0.3, lp: 12000, hp: 3000, attack: 0.001, decay: 0.12, gain: 1.0), grains(12, spread: 0.25, lp: 10000, hp: 4000, decay: 0.01, gain: 0.6))
        case .iceCrack: out = Synth.mix(crackle(0.4, density: 90, f: 3000 * p, q: 4, gain: 1.5), modes(0.3, [(1400 * p, 0.2, 0.05)]))
        case .portalTravel: out = Synth.mix(tone(1.2, f0: 200 * p, f1: 900 * p, wave: .sine, attack: 0.1, release: 0.5, vib: 0.1, vibRate: 7, gain: 0.35), wash(1.2, lp: 3000, hp: 300, wobble: 1.5, rate: 3, gain: 0.35))
        case .portalTrigger: out = Synth.mix(tone(0.8, f0: 300 * p, f1: 500 * p, wave: .tri, attack: 0.2, release: 0.3, vib: 0.08, vibRate: 6, gain: 0.25), wash(0.8, lp: 2500, hp: 400, wobble: 1, rate: 4, gain: 0.3))
        case .endPortalOpen:
            out = Synth.mix(rumble(2.5, f: 60, attack: 0.3, decay: 1.2, gain: 2.0), tone(2.5, f0: 110, f1: 55, wave: .sine, attack: 0.5, release: 1.0, gain: 0.4))
            for k in 0..<4 { out = Synth.mix(out, fm(1.5, f: 220 * powf(1.5, Float(k)), ratio: 2.01, index: 1.5, decay: 0.6, gain: 0.2), at: frames(0.4 + 0.15 * Float(k))) }
        case .endPortalFrame: out = Synth.mix(modes(0.6, [(1200 * p, 0.4, 0.2), (1800 * p, 0.3, 0.15)]), burst(0.3, lp: 2000, hp: 300, attack: 0.05, decay: 0.1, gain: 0.6))
        case .beaconActivate:
            out = []
            for (k, f) in [220, 330, 440, 660, 880].enumerated() { out = Synth.mix(out, fm(1.6, f: Float(f) * p, ratio: 2, index: 0.8, decay: 0.7, gain: 0.25), at: frames(Float(k) * 0.15)) }
            out = Synth.mix(out, wash(2.0, lp: 3000, hp: 500, wobble: 0.5, rate: 3, gain: 0.15))
        case .beaconPower: out = Synth.mix(fm(0.8, f: 660 * p, ratio: 2, index: 1.0, decay: 0.35, gain: 0.35), fm(0.8, f: 990 * p, ratio: 2, index: 0.8, decay: 0.35, gain: 0.25), at: frames(0.1))
        case .beaconDeactivate: out = Synth.mix(tone(1.0, f0: 660 * p, f1: 220 * p, wave: .sine, attack: 0.05, release: 0.5, gain: 0.35), wash(1.0, lp: 2000, hp: 300, wobble: 0.5, rate: 3, gain: 0.15))
        case .fireExtinguish: out = Synth.mix(burst(0.5, lp: 7000, hp: 2500, attack: 0.01, decay: 0.18, gain: 1.0), bubbles(0.3, count: 4, fLo: 600, fHi: 1500, len: 0.03, gain: 0.3))
        case .lavaPop: out = Synth.mix(bubbles(0.25, count: 1, fLo: 60 * p, fHi: 120 * p, len: 0.2, gain: 1.2), burst(0.15, lp: 500, hp: 40, decay: 0.04, gain: 1.6))
        case .boatPaddle: out = Synth.mix(burst(0.3, lp: 1400 * p, hp: 200, attack: 0.02, decay: 0.08, gain: 0.9), bubbles(0.3, count: 3, fLo: 400, fHi: 1000, len: 0.05, gain: 0.3))

        // Loops
        case .fireLoop: out = fireLoop(3.0, size: 1, pitch: p)
        case .campfireLoop: out = fireLoop(3.5, size: 1.3, pitch: p * 0.8)
        case .furnaceLoop: out = Synth.loopify(Synth.mix(fireLoop(3.0, size: 0.7, pitch: p), wash(3.0, lp: 300, hp: 60, wobble: 0.3, rate: 2, gain: 0.6)), fade: 0.05)
        case .lavaLoop: out = lavaLoop(4.0, pitch: p)
        case .waterLoop: out = waterLoop(3.0, pitch: p)
        case .portalLoop: out = portalLoop(4.0)
        case .beaconLoop: out = droneLoop(4.0, f: 220, partials: 4, detune: 0.004, noiseLP: 2500, noiseGain: 0.05, gain: 0.3)
        case .minecartLoop: out = Synth.loopify(Synth.mix(wash(2.5, lp: 900, hp: 80, wobble: 0.4, rate: 6, gain: 0.8), crackle(2.5, density: 40, f: 1800, q: 3, gain: 0.6)), fade: 0.3)
        case .elytraLoop: out = windLoop(3.0, lp: 1500, gain: 0.9)
        case .underwaterLoop: out = underwaterLoop(4.0)
        case .rain: out = rainLoop(3.0, roof: false)
        case .rainRoof: out = rainLoop(3.0, roof: true)
        case .respawnAnchorLoop: out = droneLoop(4.0, f: 110, partials: 3, detune: 0.01, noiseLP: 600, noiseGain: 0.2, gain: 0.35)
        case .spawnerLoop: out = Synth.loopify(Synth.mix(fireLoop(3.0, size: 0.5, pitch: p * 1.3), tone(3.0, f0: 330, f1: 330, wave: .sine, attack: 0.3, release: 0.3, vib: 0.05, vibRate: 3, gain: 0.08)), fade: 0.05)
        case .netherWastesLoop: out = Synth.loopify(Synth.mix(windLoop(5.0, lp: 500, gain: 1.0), droneLoop(5.0, f: 55, partials: 2, detune: 0.02, noiseLP: 0, noiseGain: 0, gain: 0.25)), fade: 0.05)
        case .soulValleyLoop: out = Synth.loopify(Synth.mix(windLoop(5.0, lp: 900, gain: 0.7), droneLoop(5.0, f: 82, partials: 3, detune: 0.03, noiseLP: 0, noiseGain: 0, gain: 0.2)), fade: 0.05)
        case .crimsonLoop: out = Synth.loopify(Synth.mix(droneLoop(5.0, f: 65, partials: 3, detune: 0.01, noiseLP: 400, noiseGain: 0.4, gain: 0.25), bubbles(5.0, count: 6, fLo: 100, fHi: 250, len: 0.15, gain: 0.25)), fade: 0.05)
        case .warpedLoop: out = Synth.loopify(Synth.mix(droneLoop(5.0, f: 98, partials: 4, detune: 0.02, noiseLP: 1200, noiseGain: 0.15, gain: 0.2), bubbles(5.0, count: 8, fLo: 500, fHi: 1400, len: 0.12, gain: 0.15)), fade: 0.05)
        case .basaltLoop: out = Synth.loopify(Synth.mix(windLoop(5.0, lp: 2500, gain: 0.5), crackle(5.0, density: 6, f: 1200, q: 4, gain: 1.0)), fade: 0.05)
        case .endLoop: out = droneLoop(6.0, f: 73, partials: 5, detune: 0.03, noiseLP: 2000, noiseGain: 0.12, gain: 0.22)
        case .deepDarkLoop: out = Synth.loopify(Synth.mix(droneLoop(6.0, f: 41, partials: 2, detune: 0.01, noiseLP: 200, noiseGain: 0.5, gain: 0.3), bubbles(6.0, count: 3, fLo: 80, fHi: 200, len: 0.3, gain: 0.2)), fade: 0.05)
        case .lushLoop: out = Synth.loopify(Synth.mix(windLoop(5.0, lp: 1200, gain: 0.35), bubbles(5.0, count: 8, fLo: 1200, fHi: 3000, len: 0.05, gain: 0.25)), fade: 0.05)
        case .dripstoneLoop: out = Synth.loopify(Synth.mix(windLoop(5.0, lp: 700, gain: 0.5), Synth.echo(bubbles(5.0, count: 5, fLo: 1500, fHi: 3500, len: 0.03, gain: 0.5), delay: 0.23, feedback: 0.4, mix: 0.4, tail: 0)), fade: 0.05)

        // Overworld biome ambience
        case .birdCall: out = birdCall(pitch: p)
        case .owlHoot:
            out = []
            for (k, d) in [(0, 0.35), (1, 0.25), (2, 0.6)] as [(Int, Float)] {
                let t = formant(d, f0: 390 * p, f1: 350 * p, formants: [(400, 8, 1), (800, 10, 0.2)], breath: 0.15, vib: 0.01, attack: 0.04, release: 0.12, gain: 0.9)
                out = Synth.mix(out, t, at: frames(Float(k) * 0.45))
            }
            out = Synth.echo(out, delay: 0.21, feedback: 0.3, mix: 0.3, tail: 0.6)
        case .cricketsLoop: out = cricketsLoop(4.0)
        case .fireflyLoop:
            // Soft glassy twinkles over a faint shimmer.
            var ff = wash(4.0, lp: 7000, hp: 3000, wobble: 0.5, rate: 2, gain: 0.03)
            for _ in 0..<14 {
                let f: Float = rnd(2600, 5200)
                ff = Synth.mix(ff, fm(0.35, f: f, ratio: 2.4, index: 0.8, decay: 0.08, gain: 0.18), at: frames(rnd(0, 3.6)))
            }
            out = Synth.loopify(Array(ff.prefix(frames(4.0))), fade: 0.3)
        case .hiveLoop:
            // Many bees in a box: detuned buzzing saws, muffled by the wood.
            var h = [Float](repeating: 0, count: frames(4.0))
            for _ in 0..<6 {
                let f: Float = rnd(200, 260)
                h = Synth.mix(h, tone(4.0, f0: f, f1: f * rnd(0.97, 1.03), wave: .saw, attack: 0.3, release: 0.3, vib: 0.03, vibRate: rnd(4, 9), gain: 0.08))
            }
            out = Synth.loopify(Synth.lowpass(h, 900, passes: 2), fade: 0.4)
        case .dryGrassRustle: out = Synth.window(Synth.mix(wash(1.2, lp: 5000 * p, hp: 1500, wobble: 1.2, rate: 8, gain: 0.5), grains(10, spread: 1.0, lp: 6000, hp: 2000, decay: 0.008, gain: 0.4)))
        case .heartCreak:
            let c = Synth.lowpass(tone(0.9, f0: 160 * p, f1: 120 * p, wave: .saw, attack: 0.15, release: 0.3, vib: 0.2, vibRate: 3, gain: 0.35), 900)
            out = Synth.mix(Synth.mix(c, crackle(0.9, density: 30, f: 700, q: 4, gain: 1.2)), modes(0.4, [(70 * p, 0.8, 0.12)]), at: frames(0.5))
        case .oceanLoop: out = oceanLoop(7.0)
        case .swampLoop: out = Synth.loopify(Synth.mix(frogs(5.0), Synth.scaled(cricketsLoop(5.0, voices: 2), 0.4)), fade: 0.05)
        case .windLoop: out = windLoop(6.0, lp: 700, gain: 0.8)
        case .jungleLoop:
            var j = Synth.scaled(cricketsLoop(5.0, voices: 4), 0.5)
            for _ in 0..<5 { j = Synth.mix(j, Synth.scaled(birdCall(pitch: rnd(0.8, 1.3)), 0.35), at: frames(rnd(0, 4.0))) }
            out = Synth.loopify(Array(j.prefix(frames(5.3))), fade: 0.3)

        // Ambience stings
        case .caveAmbience: out = Synth.reverb(Synth.mix(voice(4.5, f0: 55 * p, f1: 41 * p, vib: 0.3, lp: 300, gain: 0.9), burst(4.5, lp: 500, hp: 60, attack: 1.2, decay: 2.5, gain: 0.5)), size: 1.4, damp: 0.3, mix: 0.4, tail: 1.5)
        case .caveDrip: out = Synth.echo(Synth.mix(modes(0.15, [(2400 * p, 0.4, 0.02)]), bubbles(0.1, count: 1, fLo: 1800 * p, fHi: 2600 * p, len: 0.03, gain: 0.5)), delay: 0.19, feedback: 0.45, mix: 0.5, tail: 0.8)
        case .caveWind: out = Synth.reverb(Synth.window(wash(4.0, lp: 600 * p, hp: 80, wobble: 1.5, rate: 0.5, gain: 0.6)), size: 1.5, damp: 0.4, mix: 0.3, tail: 1.0)
        case .netherMood: out = Synth.reverb(Synth.mix(formant(3.0, f0: 90 * p, f1: 60 * p, formants: [(300, 4, 1), (800, 6, 0.4)], breath: 0.3, vib: 0.1, vibRate: 3, attack: 0.8, release: 1.2, growl: 0.3, gain: 0.8), rumble(3.0, f: 70, attack: 0.5, decay: 1.2, gain: 1.5)), size: 1.3, damp: 0.5, mix: 0.35, tail: 1.5)
        case .underwaterMood: out = Synth.lowpass(Synth.mix(formant(3.5, f0: 140 * p, f1: 110 * p, formants: [(350, 5, 1), (700, 6, 0.4)], breath: 0.2, vib: 0.05, vibRate: 2, attack: 1.0, release: 1.5, gain: 0.6), bubbles(3.5, count: 10, fLo: 150, fHi: 500, len: 0.15, gain: 0.3)), 800)
        case .thunder:
            out = Synth.mix(burst(0.15, lp: 8000, hp: 200, attack: 0.001, decay: 0.08, gain: 1.4), burst(4.0, lp: 220 * p, hp: 20, attack: 0.05, decay: 2.2, gain: 2.2))
            out = Synth.mix(out, rumble(4.0, f: 45, attack: 0.3, decay: 1.5, gain: 2.0), at: frames(0.6))
        case .lightning: out = Synth.mix(burst(0.25, lp: 12000, hp: 600, attack: 0.001, decay: 0.1, gain: 1.6), burst(1.8, lp: 400, hp: 30, attack: 0.01, decay: 0.7, gain: 2.5))
        case .windGust: out = Synth.window(wash(2.5, lp: 1200 * p, hp: 100, wobble: 1.2, rate: 1, gain: 0.6))

        // Mobs and specials (SoundMobs.swift)
        case .mob(let k, let m): out = MobVoice.render(&self, k, m, pitch: p)
        case .babyMob(let k, let m): out = MobVoice.render(&self, k, m, pitch: p * 1.45)
        case .mobCow: out = MobVoice.render(&self, .cow, .ambient, pitch: p)
        case .mobSheep: out = MobVoice.render(&self, .sheep, .ambient, pitch: p)
        case .mobChicken: out = MobVoice.render(&self, .chicken, .ambient, pitch: p)
        case .mobPig: out = MobVoice.render(&self, .pig, .ambient, pitch: p)
        case .mobZombie: out = MobVoice.render(&self, .zombie, .ambient, pitch: p)
        case .mobSkeleton: out = MobVoice.render(&self, .skeleton, .ambient, pitch: p)
        case .mobSpider: out = MobVoice.render(&self, .spider, .ambient, pitch: p)
        case .mobSlime: out = MobVoice.render(&self, .slime, .ambient, pitch: p)
        case .mobWailer: out = MobVoice.render(&self, .ghast, .ambient, pitch: p)
        case .mobCinderwisp: out = MobVoice.render(&self, .blaze, .ambient, pitch: p)
        case .mobBoarling: out = MobVoice.render(&self, .piglin, .ambient, pitch: p)
        case .mobUndeadBoarling: out = MobVoice.render(&self, .zombifiedPiglin, .ambient, pitch: p)
        case .mobVillager: out = MobVoice.render(&self, .villager, .ambient, pitch: p)
        case .mobGolem: out = MobVoice.render(&self, .ironGolem, .ambient, pitch: p)
        case .mobBlight: out = MobVoice.render(&self, .wither, .ambient, pitch: p)
        case .mobVex: out = MobVoice.render(&self, .vex, .ambient, pitch: p)
        case .mobRavager: out = MobVoice.render(&self, .ravager, .ambient, pitch: p)
        case .mobWolf: out = MobVoice.render(&self, .wolf, .ambient, pitch: p)
        case .mobCat: out = MobVoice.render(&self, .cat, .ambient, pitch: p)
        case .mobHorse: out = MobVoice.render(&self, .horse, .ambient, pitch: p)
        case .mobLlama: out = MobVoice.render(&self, .llama, .ambient, pitch: p)
        case .mobBee: out = MobVoice.render(&self, .bee, .ambient, pitch: p)
        case .mobWarden: out = MobVoice.render(&self, .warden, .ambient, pitch: p)
        case .mobVoidwalker: out = MobVoice.render(&self, .enderman, .ambient, pitch: p)
        case .creeperHiss, .fireball, .evokerCast, .fangs, .raidHorn, .teleport,
             .dragonGrowl, .dragonFlap, .dragonShoot, .dragonDeath, .crystalBreak, .witherSpawn, .witherShoot, .witherDeath,
             .wardenHeartbeat, .wardenRoar, .wardenSonicCharge, .wardenSonicBoom, .wardenEmerge, .wardenDig, .wardenSniff,
             .elderCurse, .guardianLaser, .villagerYes, .villagerNo, .villagerTrade, .villagerWork, .villagerCelebrate, .zombieBreakDoor, .zombieInfect, .zombieCure,
             .phantomSwoop, .beeSting, .beePollinate, .allayItem, .foxSniff, .catPurr, .wolfPant, .parrotMimic, .dolphinJump, .turtleEggCrack, .frogTongue, .goatRam, .breezeShoot:
            out = MobVoice.special(&self, s, pitch: p)

        case .fireworkLaunch: out = Synth.mix(burst(1.1, lp: 3000, hp: 400, attack: 0.05, decay: 0.6, gain: 0.9), voice(0.9, f0: 900, f1: 1800, vib: 0, lp: 3000, gain: 0.25))
        case .fireworkBlast: out = Synth.mix(burst(1.4, lp: 600, hp: 40, attack: 0.002, decay: 0.35, gain: 3), burst(0.6, lp: 6000, hp: 1500, decay: 0.08, gain: 0.8))
        case .fireworkBlastLarge: out = Synth.mix(burst(2.4, lp: 350, hp: 25, attack: 0.002, decay: 0.7, gain: 4), burst(0.8, lp: 5000, hp: 1000, decay: 0.12, gain: 1))
        case .fireworkTwinkle: out = grains(40, spread: 1.4, lp: 9000, hp: 2500, decay: 0.03, gain: 0.8)

        case .note(let inst, let n): out = MusicSynth.noteBlock(&self, inst: inst, pitch: n)
        case .gun(let k): out = WeaponAudio.gun(&self, k, p: p)
        case .explodeSmall:
            out = Synth.mix(burst(1.0, lp: 600 * p, hp: 35, attack: 0.002, decay: 0.2, gain: 3.4), burst(0.5, lp: 4500, hp: 700, decay: 0.06, gain: 1.4))
            out = Synth.mix(out, modes(0.3, [(70 * p, 0.8, 0.08)]))
        case .explodeLarge:
            out = Synth.mix(burst(3.0, lp: 200 * p, hp: 18, attack: 0.003, decay: 0.8, gain: 4.5), burst(1.0, lp: 2800, hp: 250, decay: 0.15, gain: 1.6))
            out = Synth.mix(out, rumble(4.0, f: 32, attack: 0.05, decay: 1.4, gain: 3), at: frames(0.1))
            out = Synth.echo(out, delay: 0.45, feedback: 0.3, mix: 0.3, tail: 1.2)
        case .debrisRain:
            out = Synth.mix(grains(28, spread: 1.4, lp: 3000 * p, hp: 300, decay: 0.012, gain: 0.9), grains(10, spread: 1.2, lp: 1200, hp: 100, decay: 0.03, gain: 0.8), at: frames(0.1))
        case .rocketFlightLoop:
            // Rocket motor: a hissing roar with crackle.
            let roar = wash(2.0, lp: 2600 * p, hp: 300, wobble: 0.4, rate: 14, gain: 0.8)
            out = Synth.loopify(Synth.mix(roar, crackle(2.0, density: 200, f: 1800, q: 1.5, gain: 0.8)), fade: 0.2)
        case .shellFlightLoop:
            // Heavy shell overhead: a tearing, whistling whoosh.
            let tear = wash(2.0, lp: 1500 * p, hp: 200, wobble: 0.6, rate: 9, gain: 0.8)
            let whistle = Synth.bandpass(wash(2.0, lp: 5000, hp: 400, wobble: 0.3, rate: 3, gain: 1.0), 1250 * p, q: 10)
            out = Synth.loopify(Synth.mix(tear, Synth.scaled(whistle, 2.0)), fade: 0.2)
        case .riverLoop, .waterfallLoop, .mountainWindLoop, .tundraWindLoop, .rainLeavesLoop, .snowWindLoop, .swampInsectsLoop, .thunderFar, .iceCreak, .rockfall:
            out = TerrainAudio.render(&self, s, p: p)
        case .engineIdleLoop, .engineFullLoop, .propSlowLoop, .propFastLoop, .airshipWindLoop, .wheelRollLoop, .hullWaterLoop,
             .wingRushLoop, .frigateDroneLoop, .carriageTreadLoop,
             .hullCreak, .shipCollide, .shipCollideHard, .shipSplash, .helmTake, .engineStart:
            out = VehicleAudio.render(&self, s, p: p)
        case .shipCannon:
            // Ship cannon: a big black-powder bang with a wooden hull shudder and a smoky tail.
            var o = WeaponAudio.shot(&self, p: p * 0.6, size: 2.0, bright: 0.7, tail: 1.2, mech: 0)
            o = Synth.mix(o, material(.wood, pitch: p * 0.6, scale: 1.4, gain: 0.5), at: frames(0.03))
            out = Synth.echo(o, delay: 0.3, feedback: 0.25, mix: 0.25, tail: 0.6)
        case .turretTraverseLoop:
            // Turret ring turning: geared rumble with a servo whine.
            let gear = Synth.lowpass(tone(3.0, f0: 55 * p, f1: 55 * p, wave: .square, attack: 0.2, release: 0.2, gain: 0.25), 400)
            let whine = tone(3.0, f0: 640 * p, f1: 660 * p, wave: .saw, attack: 0.2, release: 0.2, vib: 0.01, vibRate: 7, gain: 0.05)
            out = Synth.loopify(Synth.mix(Synth.mix(gear, Synth.lowpass(whine, 2000)), crackle(3.0, density: 50, f: 1500, q: 3, gain: 0.5)), fade: 0.3)
        case .gunReload(let k): out = WeaponAudio.reload(&self, k, p: p)
        case .gunDistant(let k):
            let size: Float = k == 9 ? 2.6 : (k == 2 ? 1.5 : (k == 3 ? 1.3 : (k == 1 ? 0.7 : 1)))
            out = WeaponAudio.distant(&self, p: p * (k == 5 ? 1.4 : 1), size: size, roll: k == 9 ? 3.5 : 1.8)
        case .bulletImpact(let m): out = WeaponAudio.impact(&self, m, p: p)
        case .bulletWhizz: out = WeaponAudio.whizz(&self, p: p)
        case .bulletFlesh: out = WeaponAudio.flesh(&self, p: p)
        case .grenadeBounce: out = WeaponAudio.grenadeBounce(&self, p: p)
        case .soldier(let r, let b): out = SoldierVoice.render(&self, rank: r, b, p: p)
        case .soldierStep(let r): out = SoldierVoice.step(&self, rank: r, p: p)
        }
        if !s.isLoop { out = Synth.trimTail(out) }
        return Synth.finish(s, out)
    }
}
