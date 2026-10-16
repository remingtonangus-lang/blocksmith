import Foundation

// P292 (b): hell's own lands voiced (HellLands.swift). Each bed is a 6 s seamless loop:
//   0 Cinder Plains     a deep ground rumble, rock ticking and cracking as it cools, a low smoky wind
//   1 Ash Dunes         a dry hissing wind carrying grains of ash, a hollow low moan under it
//   2 Charwood Thicket  burning wood: crackle, the odd snap and creak of a charred limb, an ember-hot low hum
//   3 Gloamwood         glassy chimes from the violet spires (a pentatonic handful), a soft high wind
//   4 Sulfur Flats      the vents: thick bubbling mud, a steam hiss that swells and falls, a sour low drone
extension Synth {
    mutating func hellBed(_ land: Int) -> [Float] {
        let d: Float = 6
        var out: [Float]
        switch land {
        case 1:
            out = Synth.mix(windLoop(d, lp: 1700, gain: 0.75), crackle(d, density: 55, f: 4200, q: 1.2, gain: 0.12))
            out = Synth.mix(out, droneLoop(d, f: 73, partials: 2, detune: 0.03, noiseLP: 0, noiseGain: 0, gain: 0.12))
        case 2:
            out = Synth.mix(crackle(d, density: 14, f: 1600, q: 2, gain: 0.7), crackle(d, density: 2, f: 380, q: 5, gain: 0.9))
            out = Synth.mix(out, droneLoop(d, f: 52, partials: 3, detune: 0.01, noiseLP: 300, noiseGain: 0.35, gain: 0.2))
            // Creaks: slow falling tones, two or three in the loop.
            for _ in 0..<3 {
                let f0 = rnd(140, 220), l = rnd(0.35, 0.7)
                let c = tone(l, f0: f0, f1: f0 * 0.7, wave: .saw, attack: 0.05, release: l * 0.5, vib: 0.08, vibRate: 11, gain: 0.05)
                out = Synth.mix(out, Synth.lowpass(c, 900), at: frames(rnd(0.2, d - l - 0.2)))
            }
        case 3:
            out = Synth.mix(windLoop(d, lp: 2600, gain: 0.35), droneLoop(d, f: 98, partials: 2, detune: 0.01, noiseLP: 0, noiseGain: 0, gain: 0.1))
            let notes: [Float] = [784, 880, 1047, 1175, 1319, 1568]
            for _ in 0..<7 {
                let f = notes[Int(rnd(0, Float(notes.count) - 0.01))]
                let c = modes(1.8, [(f, 0.1, 0.9), (f * 2.76, 0.035, 0.4), (f * 5.4, 0.015, 0.2)])
                out = Synth.mix(out, c, at: frames(rnd(0, d - 1.8)), gain: rnd(0.5, 1))
            }
        case 4:
            out = Synth.mix(bubbles(d, count: 22, fLo: 70, fHi: 190, len: 0.22, gain: 0.45), windLoop(d, lp: 4200, gain: 0.3))
            out = Synth.mix(out, droneLoop(d, f: 46, partials: 3, detune: 0.02, noiseLP: 220, noiseGain: 0.3, gain: 0.18))
            // Steam: a hiss burst that swells and dies, twice in the loop.
            for _ in 0..<2 {
                let l = rnd(1.2, 2)
                var h = crackle(l, density: 4000, f: 5200, q: 0.8, gain: 0.25)
                let n = h.count
                for i in 0..<n { let t = Float(i) / Float(n); h[i] *= sinf(t * Float.pi) }
                out = Synth.mix(out, h, at: frames(rnd(0.1, d - l - 0.1)))
            }
        default:
            out = Synth.mix(droneLoop(d, f: 38, partials: 3, detune: 0.015, noiseLP: 160, noiseGain: 0.55, gain: 0.3), windLoop(d, lp: 320, gain: 0.55))
            out = Synth.mix(out, crackle(d, density: 3, f: 760, q: 3, gain: 0.55))
        }
        return Synth.loopify(out, fade: 0.4)
    }
}
