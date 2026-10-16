import Foundation
import simd

// Sounds for free-moving block structures (Ships.swift): engines, propellers, airship rigging, wheels,
// water against the hull, creaks, collisions and splashes. Loops come in idle/full pairs that the game
// cross-fades by throttle and speed (no per-voice pitch control needed).

enum VehicleAudio {
    // A combustion engine: four cylinders firing `rate` times a second (each with its own strength and
    // timbre, which gives the lumpy idle), pulses ringing an exhaust (pipe modes + a comb for the pipe
    // length), a crank hum, valve-train ticks and a little saturation to fuse it.
    static func engine(_ g: inout Synth, dur: Float, rate: Float, p: Float, rough: Float) -> [Float] {
        let n = g.frames(dur)
        var ex = [Float](repeating: 0, count: n)
        var ticks = [Float](repeating: 0, count: n)
        let cyl: [Float] = (0..<4).map { _ in g.rnd(0.75, 1.15) }
        let pulse = Synth.contactPulse(0.0018 + 0.004 / max(1, rate / 10))
        var t: Float = 0, k = 0
        while t < dur {
            let at = g.frames(t)
            let a = cyl[k % 4] * (1 + rough * 0.25 * g.noise())
            for i in 0..<pulse.count where at + i < n { ex[at + i] += pulse[i] * a }
            // Exhaust pop: a short hot noise burst per firing (the bark you hear from the pipe).
            let popN = min(n - at, g.frames(0.012))
            if popN > 0 { for i in 0..<popN { ex[at + i] += g.noise() * 0.004 * a * expf(-Float(i) / (0.0025 * Synth.sr)) } }
            let tk = at + g.frames(0.25 / rate)
            if k % 2 == 0, tk < n { ticks[tk] += g.rnd(0.5, 1) }
            t += (1 / rate) * (1 + rough * 0.03 * g.noise())
            k += 1
        }
        var out = [Float](repeating: 0, count: n)
        let e1: Float = 105 * p
        let ring: Float = min(0.016, 0.5 / rate)    // each firing rings out before the next one
        Synth.resonate(ex, f: e1, decay: ring, amp: 3.2, into: &out)
        Synth.resonate(ex, f: e1 * 2.6, decay: ring * 0.6, amp: 1.8, into: &out)
        Synth.resonate(ex, f: e1 * 4.7, decay: 0.006, amp: 0.7, into: &out)
        Synth.resonate(ex, f: 1400 * p, decay: 0.002, amp: 0.25, into: &out)
        // Pipe length: a short feedback comb.
        let d = max(1, Int(Synth.sr / (180 * p)))
        if d < n { for i in d..<n { out[i] += out[i - d] * 0.35 } }
        let hum = Synth.lowpass(g.tone(dur, f0: rate * 0.5 * p, f1: rate * 0.5 * p, wave: .tri, attack: 0.2, release: 0.2, gain: 0.08), 300)
        var valves = [Float](repeating: 0, count: n)
        Synth.resonate(ticks, f: 3800 * p, decay: 0.0015, amp: 0.012, into: &valves)
        out = Synth.mix(Synth.mix(out, hum), valves)
        // Chassis and intake: a rattle band that throbs with the firing, more of it as revs rise.
        var rattle = g.wash(dur, lp: 2600 * p, hp: 500, wobble: 0.3, rate: 8, gain: 0.05 + 0.002 * rate)
        for i in 0..<n { rattle[i] *= 0.4 + 0.6 * powf(abs(sinf(Float.pi * Float(i) / Synth.sr * rate * 0.5)), 6) }
        out = Synth.mix(out, rattle)
        let peak = out.reduce(0) { max($0, abs($1)) }
        return peak > 0 ? Synth.highpass(out.map { tanhf($0 / peak * 1.6) * 0.8 }, 30) : out
    }

    // Propeller: tonal blade-pass harmonics (with slow beating), plus the chopped air through them.
    static func prop(_ g: inout Synth, dur: Float, bladeRate: Float, p: Float) -> [Float] {
        let f = bladeRate * p
        let n = g.frames(dur)
        var out = [Float](repeating: 0, count: n)
        for h in 1...10 {
            let fh = f * Float(h)
            guard fh < 3000 else { break }
            let a = 0.2 / powf(Float(h), 1.1)
            let ph0 = g.rnd(0, 6.28)
            for i in 0..<n {
                let t = Float(i) / Synth.sr
                out[i] += sinf(2 * .pi * fh * t + ph0) * a * (0.85 + 0.15 * sinf(2 * .pi * 0.7 * t * Float(h)))
            }
        }
        var air = g.wash(dur, lp: min(1600, 500 + f * 12), hp: 90, wobble: 0.2, rate: 3, gain: 0.7)
        for i in 0..<n {
            let ph = Float(i) / Synth.sr * f
            air[i] *= 0.45 + 0.55 * powf(abs(sinf(Float.pi * ph)), 4)
        }
        return Synth.mix(Synth.lowpass(out, 1800), air)
    }

    static func render(_ g: inout Synth, _ s: Snd, p: Float) -> [Float] {
        switch s {
        case .engineIdleLoop: return Synth.loopify(engine(&g, dur: 3.0, rate: 26, p: p, rough: 0.6), fade: 0.3)
        case .engineFullLoop: return Synth.loopify(engine(&g, dur: 3.0, rate: 74, p: p * 1.25, rough: 0.25), fade: 0.3)
        case .propSlowLoop: return Synth.loopify(prop(&g, dur: 3.0, bladeRate: 9, p: p), fade: 0.3)
        case .propFastLoop: return Synth.loopify(prop(&g, dur: 3.0, bladeRate: 38, p: p * 1.5), fade: 0.3)
        case .airshipWindLoop:
            // Wind in rigging: a breathy band with whistling lines and slow canvas flaps.
            var w = g.wash(5.0, lp: 1400 * p, hp: 150, wobble: 1.4, rate: 0.6, gain: 0.7)
            w = Synth.mix(w, g.tone(5.0, f0: 640 * p, f1: 700 * p, wave: .sine, attack: 1, release: 1, vib: 0.02, vibRate: 0.4, gain: 0.03))
            for _ in 0..<4 { w = Synth.mix(w, Synth.window(g.burst(0.4, lp: 500, hp: 60, attack: 0.05, decay: 0.12, gain: 0.8)), at: g.frames(g.rnd(0, 4.4))) }
            return Synth.loopify(Array(w.prefix(g.frames(5.0))), fade: 0.5)
        case .wheelRollLoop:
            // Wheels on terrain: low rumble with gravelly crunch.
            let r = g.wash(3.0, lp: 260 * p, hp: 35, wobble: 0.6, rate: 5, gain: 1.6)
            let crunch = g.crackle(3.0, density: 70, f: 1400, q: 2, gain: 0.7)
            return Synth.loopify(Synth.mix(r, crunch), fade: 0.3)
        case .hullWaterLoop:
            // Water slapping the hull: lapping swells and splashy bursts.
            var o = g.wash(4.0, lp: 1100 * p, hp: 120, wobble: 1.2, rate: 1.4, gain: 0.5)
            for _ in 0..<7 { o = Synth.mix(o, g.burst(0.35, lp: 1600, hp: 200, attack: 0.03, decay: 0.08, gain: 0.7), at: g.frames(g.rnd(0, 3.6))) }
            o = Synth.mix(o, g.bubbles(4.0, count: 12, fLo: 400, fHi: 1200, len: 0.04, gain: 0.25))
            return Synth.loopify(Array(o.prefix(g.frames(4.0))), fade: 0.4)
        case .wingRushLoop:
            // Fast flight: a hard broadband rush with buffeting over the wings and a thin edge whistle.
            var w = g.wash(4.0, lp: 2600 * p, hp: 180, wobble: 0.9, rate: 2.5, gain: 0.9)
            w = Synth.mix(w, g.wash(4.0, lp: 300 * p, hp: 40, wobble: 1.2, rate: 6, gain: 1.4))
            w = Synth.mix(w, Synth.scaled(Synth.bandpass(g.wash(4.0, lp: 6000, hp: 1500, wobble: 0.6, rate: 1, gain: 1.0), 2300 * p, q: 8), 0.8))
            return Synth.loopify(w, fade: 0.5)
        case .frigateDroneLoop:
            // A flying warship: several big slow engines beating against each other, felt more than heard,
            // with a deep throb from the lift fans.
            var o = engine(&g, dur: 6.0, rate: 7, p: p * 0.6, rough: 0.4)
            o = Synth.mix(o, engine(&g, dur: 6.0, rate: 7.6, p: p * 0.55, rough: 0.4))
            o = Synth.mix(o, g.tone(6.0, f0: 41 * p, f1: 41 * p, wave: .saw, attack: 0.5, release: 0.5, vib: 0.03, vibRate: 0.5, gain: 0.12))
            let fans = prop(&g, dur: 6.0, bladeRate: 4.5, p: p * 0.6)
            o = Synth.mix(Synth.lowpass(o, 700), Synth.scaled(fans, 0.6))
            return Synth.loopify(o, fade: 0.6)
        case .carriageTreadLoop:
            // Armoured carriage: a laboured heavy engine, squealing drive gear and clanking track plates.
            var o = engine(&g, dur: 4.0, rate: 15, p: p * 0.7, rough: 0.7)
            o = Synth.mix(o, Synth.scaled(g.wash(4.0, lp: 220 * p, hp: 30, wobble: 0.5, rate: 4, gain: 1.4), 0.8))
            var t: Float = 0
            while t < 3.9 {
                o = Synth.mix(o, g.material(.metal, pitch: p * g.rnd(0.45, 0.6), scale: 0.5, gain: 0.35), at: g.frames(t))
                t += 0.16 * g.rnd(0.9, 1.1)
            }
            o = Synth.mix(o, Synth.lowpass(g.tone(4.0, f0: 1150 * p, f1: 1100 * p, wave: .saw, attack: 1, release: 1, vib: 0.03, vibRate: 0.7, gain: 0.015), 3000))
            return Synth.loopify(Array(o.prefix(g.frames(4.0))), fade: 0.4)
        case .hullCreak:
            // Timber under load: a slow, grainy pitched groan.
            let base: Float = g.rnd(90, 160) * p
            let groan = Synth.lowpass(g.tone(g.rnd(0.6, 1.2), f0: base, f1: base * g.rnd(0.8, 1.15), wave: .saw, attack: 0.1, release: 0.25, vib: 0.08, vibRate: 7, gain: 0.35), 1300)
            return Synth.mix(groan, g.crackle(1.0, density: 50, f: 900, q: 4, gain: 0.8))
        case .shipCollide:
            return Synth.mix(g.material(.wood, pitch: p * 0.7, scale: 1.6, gain: 0.8), g.burst(0.4, lp: 300, hp: 30, attack: 0.002, decay: 0.09, gain: 2.5))
        case .shipCollideHard:
            var o = Synth.mix(g.material(.wood, pitch: p * 0.55, scale: 2.2, gain: 0.9), g.rumble(1.2, f: 50, attack: 0.002, decay: 0.4, gain: 2.5))
            o = Synth.mix(o, g.grains(18, spread: 0.6, lp: 3000, hp: 400, decay: 0.015, gain: 0.7), at: g.frames(0.05))
            return Synth.mix(o, g.material(.metal, pitch: p * 0.6, scale: 1.2, gain: 0.4))
        case .shipSplash:
            return Synth.mix(g.burst(1.2, lp: 1100 * p, hp: 80, attack: 0.01, decay: 0.3, gain: 1.8), g.bubbles(1.0, count: 20, fLo: 300, fHi: 1400, len: 0.06, gain: 0.5))
        case .helmTake:
            return Synth.mix(g.material(.wood, pitch: p * 1.1, scale: 0.6, gain: 0.5), g.modes(0.25, [(880 * p, 0.25, 0.08), (1320 * p, 0.15, 0.06)]), at: g.frames(0.05))
        default:   // engineStart: starter whirr, a few uneven catches, settling idle
            var o = Synth.lowpass(g.tone(0.6, f0: 40 * p, f1: 70 * p, wave: .saw, attack: 0.05, release: 0.1, vib: 0.1, vibRate: 12, gain: 0.3), 900)
            o = Synth.mix(o, engine(&g, dur: 1.2, rate: 22, p: p, rough: 1), at: g.frames(0.5))
            return o
        }
    }
}

final class ShipAudioState {
    var lastVel = V3.zero
    var lastSubmerged: Float = 0
    var creak: Float = 3
    var running = false
}

extension Game {
    // Per-tick ship sounds for the nearest few ships within 64 blocks.
    func vehicleAudioTick(_ dt: Float, ask: (String, Snd, Float, V3?) -> Void) {
        let list = world.ships.list
        guard !list.isEmpty else { return }
        audioWarm("vehicles", SoundBank.vehicleSounds)
        let eye = player.eye
        // Vessels (the flying frigate, the siege carriage) are heard from far off while they run.
        for s in list where (s.isVessel || s.role == "dropship") && s.parent == nil {
            let d = simd_length(s.pos - eye)
            // Capital ships: heard from much further, from the nearest point of the hull (a 480-block frigate's
            // centre can be far off while its bow passes overhead).
            if s.kinematic && !s.wrecked {
                let c = simd_clamp(eye, s.worldMin, s.worldMax)
                let dc = simd_length(c - eye)
                if s.isFlyingCapital && dc < 400 { ask("vessel\(s.id)", .frigateDroneLoop, 1.0, c) }
                if s.role == "crawler" && dc < 220 { ask("vessel\(s.id)", .carriageTreadLoop, 1.0, c) }
                if s.role == "dropship" && dc < 140 { ask("vessel\(s.id)", .frigateDroneLoop, 0.55, c) }
                continue
            }
            if s.role == "frigate" && d < 180 && !s.grounded {
                ask("vessel\(s.id)", .frigateDroneLoop, 0.9, s.pos)
            } else if s.role == "carriage" && d < 110 && (simd_length(s.vel) > 0.3 || s.autopilot != nil || s.piloted) {
                ask("vessel\(s.id)", .carriageTreadLoop, min(1, 0.5 + simd_length(s.vel) / 6), s.pos)
            }
        }
        let near = list.filter { simd_length($0.pos - eye) < 64 }
            .sorted { simd_length($0.pos - eye) < simd_length($1.pos - eye) }.prefix(3)
        var seen = Set<Int>()
        for s in near {
            seen.insert(s.id)
            let st = audio.ships[s.id] ?? ShipAudioState()
            audio.ships[s.id] = st
            let speed = simd_length(s.vel)
            let key = "ship\(s.id)"
            let thr = abs(s.throttle)
            let powered = s.engines > 0 || !s.props.isEmpty
            // Engine: idle while piloted, full layer grows with throttle.
            if s.engines > 0 && (s.piloted || thr > 0.01 || s.autopilot != nil) {
                if !st.running { st.running = true; sfx(.engineStart, 0.8, at: s.pos) }
                ask(key + "eng0", .engineIdleLoop, 0.55 * (1 - thr * 0.7), s.pos)
                ask(key + "eng1", .engineFullLoop, 0.7 * thr, s.pos)
            } else { st.running = false }
            if !s.props.isEmpty && (thr > 0.01 || speed > 1) {
                let spin = max(thr, min(1, speed / 20))
                ask(key + "prop0", .propSlowLoop, 0.45 * (1 - spin), s.pos)
                ask(key + "prop1", .propFastLoop, 0.6 * spin, s.pos)
            }
            if !s.wings.isEmpty && s.submerged <= 0 && !s.grounded && speed > 6 {
                ask(key + "rush", .wingRushLoop, min(1, (speed - 6) / 24), s.pos)
            }
            if s.balloons > 0 && s.submerged <= 0 && !s.grounded {
                ask(key + "wind", .airshipWindLoop, 0.25 + min(0.5, speed / 30), s.pos)
            }
            if !s.wheels.isEmpty && s.grounded && speed > 0.5 {
                ask(key + "wheel", .wheelRollLoop, min(0.9, 0.2 + speed / 12), s.pos)
            }
            if s.submerged > 0 && speed > 0.3 {
                ask(key + "water", .hullWaterLoop, min(0.8, 0.2 + speed / 10), s.pos)
            }
            // Collisions: a sudden loss of speed while touching something.
            let dv = simd_length(s.vel - st.lastVel)
            if s.contacts > 0 && dv > 3 {
                sfx(dv > 9 ? .shipCollideHard : .shipCollide, min(2, dv / 6), at: s.pos)
            }
            // Splash: touching water while falling.
            if st.lastSubmerged <= 0 && s.submerged > 0 && st.lastVel.y < -3 { sfx(.shipSplash, min(2, -st.lastVel.y / 8), at: s.pos) }
            // Creaks: more often when rolling, turning or driving through water.
            st.creak -= dt * (0.3 + simd_length(s.angVel) * 3 + (s.submerged > 0 ? speed / 8 : 0))
            if st.creak <= 0 {
                st.creak = Rand.float(in: 3...8)
                if s.blockCount > 6 && (s.submerged > 0 || s.balloons > 0 || powered) { sfx(.hullCreak, 0.6, at: s.pos) }
            }
            // Turrets turning on their rings.
            for t in world.ships.turrets(of: s) where simd_length(t.angVel - s.angVel) > 0.15 {
                ask(key + "turret\(t.id)", .turretTraverseLoop, 0.6, t.pos)
            }
            st.lastVel = s.vel
            st.lastSubmerged = s.submerged
        }
        if audio.ships.count > seen.count { audio.ships = audio.ships.filter { seen.contains($0.key) } }
    }
}
