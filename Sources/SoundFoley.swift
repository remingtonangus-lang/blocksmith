import Foundation

// Foley: block sounds by material (footsteps, breaking, placing, mining taps, landings).
// Built like recorded foley rather than from plain noise bursts: a contact pulse (its width is
// the material's hardness) drives 2-pole resonators, so modes ring like an object; surfaces add a
// granular texture whose grain loudness follows a power law (real crunch is a few loud grains in
// many quiet ones); steps are a heel strike plus a softer toe roll; breaks add a fracture crack
// and falling debris. Takes vary tuning, timing and grain scatter by seed.

struct FoleyMat {
    var thump: Float = 0.6, thumpF: Float = 110, contact: Float = 0.0006   // low hit of foot/block, contact time (s)
    var click: Float = 0.3, clickF: Float = 3000                             // hard contact transient
    var modes: [(f: Float, decay: Float, amp: Float)] = []
    var tex: Float = 0, texLo: Float = 800, texHi: Float = 4000, texRate: Float = 800, texGrain: Float = 0.003, texLen: Float = 0.06
    var swish: Float = 0, swishLo: Float = 400, swishHi: Float = 3000
    var squelch: Float = 0
    var shatter: Float = 0
    var debris: Float = 0.5
    var body: Float = 0.8, bodyF: Float = 170            // the block's own mass (place/break): low-mid weight

    static func of(_ m: SoundMat) -> FoleyMat {
        var f = FoleyMat()
        switch m {
        case .stone:
            f.thump = 0.45; f.thumpF = 125; f.click = 0.6; f.clickF = 3400
            f.modes = [(520, 0.014, 0.3), (1240, 0.009, 0.22), (2450, 0.006, 0.16)]
            f.tex = 0.5; f.texLo = 1200; f.texHi = 6500; f.texRate = 900; f.texGrain = 0.0018; f.texLen = 0.05; f.debris = 0.9
        case .deepslate:
            f.thump = 0.55; f.thumpF = 105; f.click = 0.4; f.clickF = 2400
            f.modes = [(380, 0.018, 0.36), (910, 0.011, 0.26), (1950, 0.007, 0.16)]
            f.tex = 0.4; f.texLo = 900; f.texHi = 4800; f.texRate = 800; f.texGrain = 0.002; f.texLen = 0.05; f.debris = 0.9
        case .netherrack:
            f.thump = 0.5; f.thumpF = 110; f.click = 0.35; f.clickF = 2200; f.contact = 0.001
            f.modes = [(430, 0.008, 0.18)]
            f.tex = 0.75; f.texLo = 600; f.texHi = 3600; f.texRate = 1500; f.texGrain = 0.0028; f.texLen = 0.08; f.debris = 1.1
        case .dirt:
            f.thump = 0.9; f.thumpF = 92; f.click = 0.08; f.clickF = 1500; f.contact = 0.003
            f.tex = 0.5; f.texLo = 300; f.texHi = 2400; f.texRate = 1100; f.texGrain = 0.0035; f.texLen = 0.07; f.debris = 0.55
        case .grass:
            f.thump = 0.75; f.thumpF = 96; f.click = 0.04; f.clickF = 1500; f.contact = 0.003
            f.tex = 0.4; f.texLo = 500; f.texHi = 3200; f.texRate = 900; f.texGrain = 0.003; f.texLen = 0.08
            f.swish = 0.55; f.swishLo = 1800; f.swishHi = 8000; f.debris = 0.35
        case .plant, .leaves:
            f.thump = 0.12; f.thumpF = 130; f.click = 0.05; f.clickF = 3000; f.contact = 0.002
            f.tex = 0.6; f.texLo = 1500; f.texHi = 9000; f.texRate = 1600; f.texGrain = 0.0022; f.texLen = 0.12
            f.swish = 0.8; f.swishLo = 2000; f.swishHi = 9500; f.debris = 0.25
            if m == .leaves { f.texLo = 2000; f.texRate = 2200; f.texGrain = 0.0016 }
        case .gravel:
            f.thump = 0.6; f.thumpF = 100; f.click = 0.3; f.clickF = 3000; f.contact = 0.0015
            f.tex = 1.0; f.texLo = 600; f.texHi = 5200; f.texRate = 2200; f.texGrain = 0.0026; f.texLen = 0.14; f.debris = 1.2
        case .sand:
            f.thump = 0.38; f.thumpF = 88; f.click = 0; f.contact = 0.004
            f.tex = 0.7; f.texLo = 1600; f.texHi = 9000; f.texRate = 2600; f.texGrain = 0.0022; f.texLen = 0.12
            f.swish = 0.4; f.swishLo = 1200; f.swishHi = 7000; f.debris = 0.3
        case .snow:
            f.thump = 0.5; f.thumpF = 84; f.click = 0; f.contact = 0.004
            f.tex = 1.0; f.texLo = 450; f.texHi = 3200; f.texRate = 2000; f.texGrain = 0.0045; f.texLen = 0.12
            f.swish = 0.15; f.swishLo = 800; f.swishHi = 4000; f.debris = 0.3
        case .soul:
            f.thump = 0.45; f.thumpF = 80; f.click = 0; f.contact = 0.004
            f.tex = 0.6; f.texLo = 600; f.texHi = 4200; f.texRate = 1800; f.texGrain = 0.003; f.texLen = 0.12
            f.squelch = 0.25; f.debris = 0.3
        case .mud:
            f.thump = 0.8; f.thumpF = 78; f.click = 0; f.contact = 0.005
            f.tex = 0.15; f.texLo = 300; f.texHi = 1500; f.squelch = 1.0; f.debris = 0.2
        case .slime:
            f.thump = 0.5; f.thumpF = 115; f.click = 0; f.contact = 0.005
            f.modes = [(210, 0.06, 0.3)]; f.squelch = 1.0; f.debris = 0
        case .sculk:
            f.thump = 0.6; f.thumpF = 88; f.click = 0; f.contact = 0.004
            f.modes = [(150, 0.06, 0.2)]; f.tex = 0.2; f.texLo = 300; f.texHi = 1500; f.squelch = 0.6; f.debris = 0.2
        case .wood:
            f.thump = 0.45; f.thumpF = 110; f.click = 0.45; f.clickF = 2500; f.contact = 0.0008
            f.modes = [(150, 0.05, 0.5), (275, 0.04, 0.45), (490, 0.03, 0.34), (860, 0.02, 0.2), (1520, 0.012, 0.1)]
            f.tex = 0.15; f.texLo = 1000; f.texHi = 4000; f.texLen = 0.03; f.debris = 0.6
        case .metal:
            f.thump = 0.3; f.thumpF = 110; f.click = 0.7; f.clickF = 5000; f.contact = 0.0003
            f.modes = [(410, 0.22, 0.32), (985, 0.17, 0.3), (1735, 0.13, 0.24), (2615, 0.1, 0.2), (3830, 0.07, 0.14), (5310, 0.05, 0.1)]
            f.tex = 0.1; f.texLo = 2000; f.texHi = 7000; f.texLen = 0.03; f.debris = 0.5
        case .glass:
            f.thump = 0.2; f.thumpF = 150; f.click = 0.9; f.clickF = 6000; f.contact = 0.0002
            f.modes = [(1900, 0.05, 0.3), (3420, 0.04, 0.25), (5230, 0.03, 0.2)]; f.shatter = 1.0; f.debris = 0.2
        case .amethyst:
            f.thump = 0.2; f.thumpF = 150; f.click = 0.5; f.clickF = 5000; f.contact = 0.0003
            f.modes = [(1250, 0.4, 0.3), (2210, 0.3, 0.25), (3490, 0.22, 0.2), (4870, 0.15, 0.1)]; f.shatter = 0.5; f.debris = 0.2
        case .wool:
            f.thump = 0.5; f.thumpF = 140; f.click = 0; f.contact = 0.007
            f.tex = 0.1; f.texLo = 300; f.texHi = 1200; f.swish = 0.4; f.swishLo = 300; f.swishHi = 1500; f.debris = 0
        case .bone:
            f.thump = 0.3; f.thumpF = 120; f.click = 0.7; f.clickF = 3000; f.contact = 0.0005
            f.modes = [(640, 0.03, 0.35), (1460, 0.02, 0.3), (2900, 0.012, 0.15)]; f.debris = 0.6
        }
        switch m {
        case .stone: f.bodyF = 175
        case .deepslate: f.bodyF = 150; f.body = 0.9
        case .netherrack: f.bodyF = 160
        case .dirt, .grass, .mud, .soul: f.bodyF = 125; f.body = 0.7
        case .gravel: f.bodyF = 150
        case .sand, .snow: f.bodyF = 120; f.body = 0.55
        case .wood: f.bodyF = 195; f.body = 0.9
        case .metal: f.bodyF = 230; f.body = 0.7
        case .glass, .amethyst: f.bodyF = 260; f.body = 0.35
        case .wool: f.bodyF = 140; f.body = 0.5
        case .plant, .leaves: f.body = 0.1
        case .slime, .sculk: f.bodyF = 130; f.body = 0.6
        case .bone: f.bodyF = 210; f.body = 0.5
        }
        return f
    }
}

extension Synth {
    // MARK: Foley primitives

    // Adds a 2-pole resonator (f Hz, 1/e decay seconds) driven by x into out.
    static func resonate(_ x: [Float], at off: Int = 0, f: Float, decay: Float, amp: Float, into out: inout [Float]) {
        let w = 2 * Float.pi * min(f, sr * 0.45) / sr
        let r = expf(-1 / (max(0.0005, decay) * sr))
        let c1 = 2 * r * cosf(w), c2 = -r * r
        let g = amp * sinf(w)
        var y1: Float = 0, y2: Float = 0
        let end = min(out.count, off + x.count + Int(decay * 7 * sr))
        var i = off
        while i < end {
            let k = i - off
            let inp: Float = k < x.count ? x[k] : 0
            let y = g * inp + c1 * y1 + c2 * y2
            y2 = y1; y1 = y
            out[i] += y
            i += 1
        }
    }

    // Half-sine contact pulse (area normalised to 1): wider = softer material, fewer highs.
    static func contactPulse(_ width: Float) -> [Float] {
        let n = max(2, Int(width * sr))
        var p = [Float](repeating: 0, count: n)
        var sum: Float = 0
        for i in 0..<n { p[i] = sinf(Float.pi * (Float(i) + 0.5) / Float(n)); sum += p[i] }
        return p.map { $0 / sum }
    }

    // Granular surface texture: grains at a rate following `shape(t/len)`, each a tiny noise burst
    // through a resonator tuned log-uniformly in lo...hi; loudness ~ rnd^3.
    mutating func texture(_ len: Float, rate: Float, lo: Float, hi: Float, grain: Float, gain: Float, shape: (Float) -> Float) -> [Float] {
        var out = [Float](repeating: 0, count: frames(len + grain * 10 + 0.01))
        var t: Float = 0
        let gl = max(8, Int(grain * 3 * Synth.sr))
        var ex = [Float](repeating: 0, count: gl)
        while t < len {
            t += -logf(max(1e-4, rnd())) / max(1, rate)
            guard t < len else { break }
            let s = shape(t / len)
            if rnd() > s { continue }
            let fc = lo * powf(hi / lo, rnd())
            let a = powf(rnd(), 3) * gain
            for i in 0..<gl { ex[i] = noise() * expf(-Float(i) / (grain * Synth.sr)) }
            Synth.resonate(ex, at: frames(t), f: fc, decay: max(0.0006, 3 / fc), amp: a * 4, into: &out)
        }
        return out
    }

    // Band-limited noise swish (rustle / fabric / hiss) with an attack and decay.
    mutating func swishNoise(_ dur: Float, lo: Float, hi: Float, attack: Float, decay: Float, gain: Float) -> [Float] {
        var out = burst(dur, lp: hi, hp: lo, attack: attack, decay: decay, gain: gain)
        // Rustle: random amplitude flutter.
        var m: Float = 1, cnt = 0
        for i in 0..<out.count {
            if cnt == 0 { m = 0.35 + 0.65 * rnd(); cnt = Int(0.004 * Synth.sr * (0.5 + rnd())) }
            cnt -= 1
            out[i] *= m
        }
        return out
    }

    // Wet squelch: noise through a resonator sweeping up (suction), plus a small pop.
    mutating func squelchNoise(_ dur: Float, f0: Float, f1: Float, gain: Float) -> [Float] {
        let n = frames(dur)
        var out = [Float](repeating: 0, count: n)
        var y1: Float = 0, y2: Float = 0
        for i in 0..<n {
            let k = Float(i) / Float(n)
            let f = f0 * powf(f1 / f0, k)
            let w = 2 * Float.pi * f / Synth.sr
            let r: Float = 0.992
            let y = sinf(w) * noise() + 2 * r * cosf(w) * y1 - r * r * y2
            y2 = y1; y1 = y
            out[i] = y * gain * min(1, k * 12) * (1 - k) * (1 - k)
        }
        return Synth.mix(out, tone(0.035, f0: f1 * 0.4, f1: f1 * 0.7, wave: .sine, attack: 0.003, release: 0.02, gain: gain * 0.25), at: frames(dur * 0.7))
    }

    // Glass/crystal shatter: a crash of high noise plus many short pings scattered in time.
    mutating func shatterLayer(_ gain: Float, crystal: Bool) -> [Float] {
        var out = burst(0.3, lp: 12000, hp: 2800, attack: 0.001, decay: 0.05, gain: gain * 0.7)
        let n = crystal ? 10 : 22
        for _ in 0..<n {
            let f = (crystal ? rnd(1400, 5200) : rnd(2300, 9000))
            let at = frames(powf(rnd(), 1.6) * 0.22)
            let ping = modes(0.25, [(f, gain * (0.1 + 0.25 * rnd()), crystal ? rnd(0.06, 0.18) : rnd(0.008, 0.05))])
            out = Synth.mix(out, ping, at: at)
        }
        return out
    }

    // Stick-slip creak (wood fibres, hinges): a jittery pulse train f0 -> f1 Hz through wood-like bands.
    mutating func creak(_ dur: Float, f0: Float, f1: Float, gain: Float) -> [Float] {
        let n = frames(dur)
        var ex = [Float](repeating: 0, count: n)
        var t: Float = 0
        while t < dur {
            let k = t / dur
            let f = f0 + (f1 - f0) * k
            let i = frames(t)
            if i < n { ex[i] = (0.6 + 0.4 * rnd()) * sinf(.pi * k) }
            t += (1 / f) * (1 + 0.25 * noise())
        }
        var out = [Float](repeating: 0, count: n + frames(0.05))
        for (fc, a) in [(420 as Float, 1 as Float), (980, 0.7), (1900, 0.4), (3100, 0.2)] {
            Synth.resonate(ex, f: fc * rnd(0.9, 1.1), decay: 0.006, amp: a * gain * 6, into: &out)
        }
        return out
    }

    // Short early reflections (a small space around the listener), low-passed.
    static func room(_ x: [Float], mix m: Float) -> [Float] {
        let taps: [(Float, Float)] = [(0.0071, 0.5), (0.0113, 0.38), (0.0167, 0.3), (0.0229, 0.22), (0.0313, 0.15), (0.043, 0.1)]
        var wet = [Float](repeating: 0, count: x.count + Int(0.06 * sr))
        for (d, g) in taps {
            let o = Int(d * sr)
            for i in 0..<x.count { wet[o + i] += x[i] * g }
        }
        wet = lowpass(wet, 3500)
        var out = wet.map { $0 * m }
        for i in 0..<x.count { out[i] += x[i] }
        return out
    }

    // MARK: Foley events

    // One contact: thump + click + driven modes + texture/swish/squelch layers.
    mutating func foleyContact(_ f: FoleyMat, p: Float, force: Float, ring: Float, texLen: Float, texScale: Float) -> [Float] {
        let n = frames(0.5)
        var out = [Float](repeating: 0, count: n)
        // Body thump: a wide pulse into a low resonator, plus a little low noise.
        if f.thump > 0 {
            let wide = Synth.contactPulse(0.006)
            Synth.resonate(wide, f: f.thumpF * p * rnd(0.92, 1.08), decay: 0.022, amp: f.thump * force * 2.2, into: &out)
            out = Synth.mix(out, burst(0.08, lp: 260 * p, hp: 35, attack: 0.002, decay: 0.018, gain: f.thump * force * 0.5))
        }
        // Click: a short high-passed burst through a band around clickF.
        if f.click > 0 {
            let c = burst(0.012, lp: min(16000, f.clickF * 2.2), hp: f.clickF * 0.45, attack: 0.0002, decay: 0.0018, gain: f.click * force * 0.9)
            out = Synth.mix(out, c)
        }
        // Modes, driven by a contact pulse of the material's width.
        if !f.modes.isEmpty {
            var ex = Synth.contactPulse(f.contact)
            for i in 0..<ex.count { ex[i] *= 1 + 0.3 * noise() }
            for md in f.modes {
                Synth.resonate(ex, f: md.f * p * (1 + 0.035 * noise()), decay: md.decay * ring * rnd(0.85, 1.15),
                               amp: md.amp * force * rnd(0.75, 1.2) * 3, into: &out)
            }
        }
        if f.tex > 0 && texScale > 0 {
            let t = texture(texLen, rate: f.texRate, lo: f.texLo * p, hi: f.texHi * p, grain: f.texGrain, gain: f.tex * force * texScale) { x in
                min(1, x * 12) * (1 - x) * (1 - x) + 0.15
            }
            out = Synth.mix(out, t)
        }
        if f.swish > 0 && texScale > 0 {
            out = Synth.mix(out, swishNoise(texLen + 0.05, lo: f.swishLo * p, hi: f.swishHi * p, attack: 0.008, decay: texLen * 0.45, gain: f.swish * force * texScale * 0.6))
        }
        if f.squelch > 0 {
            out = Synth.mix(out, squelchNoise(0.12 + 0.05 * rnd(), f0: 260 * p, f1: rnd(700, 1100) * p, gain: f.squelch * force * 0.6))
        }
        return out
    }

    // The block's own mass: a low-mid resonance pair and a short low noise chunk (weight of a cube).
    mutating func blockBody(_ f: FoleyMat, p: Float, force: Float) -> [Float] {
        var out = [Float](repeating: 0, count: frames(0.35))
        let pulse = Synth.contactPulse(0.004)
        Synth.resonate(pulse, f: f.bodyF * p * rnd(0.94, 1.06), decay: 0.05, amp: f.body * force * 2.6, into: &out)
        Synth.resonate(pulse, f: f.bodyF * 2.3 * p * rnd(0.94, 1.06), decay: 0.028, amp: f.body * force * 1.1, into: &out)
        return Synth.mix(out, burst(0.15, lp: 650 * p, hp: 60, attack: 0.001, decay: 0.028, gain: f.body * force * 0.7))
    }

    // Footstep: heel strike, then a softer toe roll 45-75 ms later.
    mutating func foleyStep(_ m: SoundMat, p: Float) -> [Float] {
        let f = FoleyMat.of(m)
        let ring: Float = m == .metal ? 0.25 : 0.5
        let heel = foleyContact(f, p: p, force: 1, ring: ring, texLen: f.texLen, texScale: 1)
        let toe = foleyContact(f, p: p * 1.06, force: rnd(0.45, 0.62), ring: ring * 0.8, texLen: f.texLen * 0.8, texScale: 0.8)
        let out = Synth.mix(heel, toe, at: frames(rnd(0.045, 0.075)))
        return Synth.trimTail(Synth.room(out, mix: 0.12), below: 0.002)
    }

    // Mining tap: a light, short contact (it repeats ~4 times a second, so it must not tire the ear).
    mutating func foleyHit(_ m: SoundMat, p: Float) -> [Float] {
        let f = FoleyMat.of(m)
        var g = f
        g.thump *= 0.4; g.squelch *= 0.5; g.swish *= 0.6; g.click *= 0.6
        if m != .metal && m != .amethyst { g.modes = f.modes.map { ($0.f * 0.85, $0.decay * 0.5, $0.amp * 0.4) }; g.tex *= 1.4 }
        var tap = foleyContact(g, p: p * 0.95, force: 0.7, ring: 0.3, texLen: 0.035, texScale: 0.6)
        // A short knock of the block's mass (no ring: taps overlap at 4 a second).
        Synth.resonate(Synth.contactPulse(0.003), f: f.bodyF * p, decay: 0.014, amp: f.body * 1.2, into: &tap)
        tap = Array(tap.prefix(frames(0.14)))
        Synth.fadeOut(&tap, 0.04)
        return tap
    }

    // Placing a block: a firm set-down plus a small settle.
    mutating func foleyPlace(_ m: SoundMat, p: Float) -> [Float] {
        let f = FoleyMat.of(m)
        var g = f
        g.thumpF *= 0.92; g.swish *= 0.6; g.click *= 0.45
        var out = Synth.mix(foleyContact(g, p: p, force: 0.8, ring: 0.8, texLen: max(0.04, f.texLen * 0.6), texScale: 0.6), blockBody(f, p: p, force: 1))
        if [.stone, .deepslate, .netherrack, .gravel, .bone].contains(m) {   // settle: grit scraping as it seats
            out = Synth.mix(out, texture(0.16, rate: 1400, lo: 700 * p, hi: 3800 * p, grain: 0.0025, gain: 0.32) { x in (1 - x) * (1 - x) }, at: frames(0.02))
        } else if m == .wood {
            out = Synth.mix(out, creak(0.05, f0: 160, f1: 120, gain: 0.12), at: frames(0.03))
        }
        if f.tex > 0 {
            out = Synth.mix(out, texture(0.05, rate: f.texRate * 0.6, lo: f.texLo * p, hi: f.texHi * p, grain: f.texGrain, gain: f.tex * 0.3) { _ in 1 }, at: frames(0.025))
        }
        return Synth.trimTail(Synth.room(out, mix: 0.14), below: 0.002)
    }

    // Breaking a block: impact, fracture crack, then debris falling and settling.
    mutating func foleyBreak(_ m: SoundMat, p: Float) -> [Float] {
        let f = FoleyMat.of(m)
        var g = f
        g.click *= 0.5
        var out = Synth.mix(foleyContact(g, p: p * 0.95, force: 1.0, ring: 1.2, texLen: max(0.08, f.texLen * 1.5), texScale: 1.1), blockBody(f, p: p * 0.95, force: 1.1))
        if f.tex > 0.3 && f.texLo < 1300 {   // crunch: a dense low-mid grain burst as the block gives way
            out = Synth.mix(out, texture(0.07, rate: 3500, lo: 280 * p, hi: 2400 * p, grain: 0.003, gain: 0.9 * f.tex) { x in 1 - x }, at: frames(0.006))
        }
        // Fracture: brittle materials crack (a broadband snap plus a couple of after-cracks).
        let brittle: Float = [.stone, .deepslate, .netherrack, .wood, .bone, .glass, .amethyst, .gravel].contains(m) ? 1 : 0.25
        let crack = burst(0.02, lp: 6000, hp: 700, attack: 0.0006, decay: 0.003, gain: 0.45 * brittle)
        out = Synth.mix(out, crack, at: frames(0.004))
        for _ in 0..<Int(2 * brittle) {
            out = Synth.mix(out, burst(0.015, lp: 9000, hp: 1200, attack: 0.0002, decay: 0.0025, gain: rnd(0.12, 0.28) * brittle), at: frames(rnd(0.01, 0.045)))
        }
        if m == .wood {   // the axe's bite, then fibres tearing: a creak into a crackle of splinters
            out = Synth.mix(out, burst(0.02, lp: 4500, hp: 1800, attack: 0.0003, decay: 0.003, gain: 0.55))
            var trunk = [Float](repeating: 0, count: frames(0.25))
            Synth.resonate(Synth.contactPulse(0.003), f: rnd(100, 125) * p, decay: 0.045, amp: 2.2, into: &trunk)
            out = Synth.mix(out, trunk)
            out = Synth.mix(out, creak(rnd(0.07, 0.11), f0: rnd(90, 140), f1: rnd(220, 320), gain: 0.35), at: frames(0.0))
            out = Synth.mix(out, texture(0.16, rate: 900, lo: 700, hi: 5000, grain: 0.0035, gain: 0.7) { x in x < 0.3 ? x / 0.3 : (1 - x) / 0.7 }, at: frames(0.02))
        }
        if [.stone, .deepslate, .netherrack].contains(m) {   // the block splits: a low crack
            var split = [Float](repeating: 0, count: frames(0.2))
            Synth.resonate(Synth.contactPulse(0.002), f: rnd(85, 120) * p, decay: 0.03, amp: 1.6, into: &split)
            out = Synth.mix(out, split, at: frames(0.004))
        }
        // Debris: smaller pieces (higher tuned) landing with falling density.
        if f.debris > 0 {
            var piece = f
            piece.thump *= 0.25; piece.swish = 0; piece.squelch *= 0.3
            piece.modes = f.modes.map { ($0.f * 1.7, $0.decay * 0.6, $0.amp) }
            let count = 3 + Int(4 * f.debris)
            for _ in 0..<count {
                let t = 0.06 + powf(rnd(), 1.3) * 0.3
                let hit = foleyContact(piece, p: p * rnd(1.0, 1.5), force: f.debris * rnd(0.12, 0.32) * (1 - t * 1.5), ring: 0.6, texLen: 0.03, texScale: 0.6)
                out = Synth.mix(out, hit, at: frames(t))
            }
            if f.tex > 0 {
                out = Synth.mix(out, texture(0.35, rate: f.texRate * 0.4, lo: f.texLo * 0.7 * p, hi: min(3500, f.texHi) * p, grain: f.texGrain * 1.4, gain: f.tex * f.debris * 0.25) { x in (1 - x) * (1 - x) }, at: frames(0.05))
            }
        }
        if f.shatter > 0 { out = Synth.mix(out, shatterLayer(f.shatter, crystal: m == .amethyst), at: frames(0.012)) }
        return Synth.trimTail(Synth.room(out, mix: 0.16), below: 0.002)
    }

    // Landing from a fall: a heavy body thud plus a hard step on the surface.
    mutating func foleyFall(_ m: SoundMat, p: Float) -> [Float] {
        let f = FoleyMat.of(m)
        var g = f
        g.squelch *= 0.4
        let hard: Float = f.texLo >= 900 ? 0.4 : 1
        var out = foleyContact(g, p: p * 0.9, force: 1.2, ring: 0.6, texLen: f.texLen * 1.2, texScale: hard)
        var body = [Float](repeating: 0, count: frames(0.3))
        Synth.resonate(Synth.contactPulse(0.012), f: 85 * p, decay: 0.024, amp: 3.2, into: &body)
        out = Synth.mix(out, body)
        out = Synth.mix(out, burst(0.12, lp: 300, hp: 40, attack: 0.002, decay: 0.025, gain: 1.0))
        if [.grass, .dirt, .sand, .snow, .wool, .plant, .leaves, .soul].contains(m) { out = Synth.lowpass(out, 3200) }
        return Synth.trimTail(Synth.room(out, mix: 0.1), below: 0.002)
    }
}
