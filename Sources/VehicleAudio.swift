import Foundation
import simd

// Sounds for free-moving block structures (Ships.swift): engines, propellers, airship rigging, wheels,
// water against the hull, creaks, collisions and splashes. Loops come in idle/full pairs that the game
// cross-fades by throttle and speed (no per-voice pitch control needed).

enum VehicleAudio {
    // A combustion engine: firing pulses at `rate` per second through a resonant exhaust, plus a mechanical hum.
    static func engine(_ g: inout Synth, dur: Float, rate: Float, p: Float, rough: Float) -> [Float] {
        let n = g.frames(dur)
        var pulses = [Float](repeating: 0, count: n)
        var t: Float = 0
        while t < dur {
            let at = g.frames(t)
            let len = min(n - at, g.frames(0.03))
            if len > 0 {
                let amp: Float = 0.8 + rough * g.noise() * 0.4
                for i in 0..<len { pulses[at + i] += amp * expf(-Float(i) / Synth.sr / 0.006) * (g.noise() * 0.6 + 0.6) }
            }
            t += (1 / rate) * (1 + rough * 0.08 * g.noise())
        }
        let exhaust = Synth.lowpass(Synth.bandpass(pulses, 140 * p, q: 1.4), 900, passes: 2)
        let hum = g.tone(dur, f0: rate * 2 * p, f1: rate * 2 * p, wave: .saw, attack: 0.2, release: 0.2, gain: 0.08)
        let whine = g.tone(dur, f0: rate * 9 * p, f1: rate * 9 * p, wave: .sine, attack: 0.2, release: 0.2, gain: 0.025)
        return Synth.mix(Synth.mix(Synth.scaled(exhaust, 2.2), Synth.lowpass(hum, 600)), whine)
    }

    // Propeller: blade-pass amplitude modulation of a wind band.
    static func prop(_ g: inout Synth, dur: Float, bladeRate: Float, p: Float) -> [Float] {
        let air = g.wash(dur, lp: 1200 * p, hp: 120, wobble: 0.2, rate: 3, gain: 0.8)
        var out = air
        for i in 0..<out.count {
            let t = Float(i) / Synth.sr
            let ph: Float = t * bladeRate
            let m: Float = 0.55 + 0.45 * powf(abs(sinf(Float.pi * ph)), 3)
            out[i] *= m
        }
        let buzz = g.tone(dur, f0: bladeRate * p, f1: bladeRate * p, wave: .tri, attack: 0.2, release: 0.2, gain: 0.1)
        return Synth.mix(out, Synth.lowpass(buzz, 700))
    }

    static func render(_ g: inout Synth, _ s: Snd, p: Float) -> [Float] {
        switch s {
        case .engineIdleLoop: return Synth.loopify(engine(&g, dur: 3.0, rate: 11, p: p, rough: 0.6), fade: 0.3)
        case .engineFullLoop: return Synth.loopify(engine(&g, dur: 3.0, rate: 34, p: p * 1.3, rough: 0.3), fade: 0.3)
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
            o = Synth.mix(o, engine(&g, dur: 1.2, rate: 9, p: p, rough: 1), at: g.frames(0.5))
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
