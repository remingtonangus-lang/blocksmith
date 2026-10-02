import Foundation
import simd

// Terrain and weather beds: streams and waterfalls (found by the block scan), wind by landform (mountain
// howl, thin tundra whistle), rain pattering on leaves, snow wind, distant thunder, ice creaks, rockfalls.

// Biome groups the ambient director tests every tick (static: no per-tick set building).
enum AmbientBiomes {
    static let snowy: Set<Biome> = [.snowyPlains, .iceSpikes, .snowyTaiga, .snowySlopes, .frozenPeaks, .jaggedPeaks, .grove, .snowyBeach, .frozenRiver, .frozenOcean, .deepFrozenOcean]
    static let dry: Set<Biome> = [.desert, .badlands, .erodedBadlands, .woodedBadlands]
    static let wooded: Set<Biome> = [.forest, .flowerForest, .birchForest, .oldGrowthBirchForest, .darkForest, .taiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga,
                                     .windsweptForest, .cherryGrove, .meadow, .plains, .sunflowerPlains, .savanna, .savannaPlateau, .river, .paleGarden]
    static let jungle: Set<Biome> = [.jungle, .sparseJungle, .bambooJungle]
    static let swamp: Set<Biome> = [.swamp, .mangroveSwamp]
    static let tundra: Set<Biome> = [.snowyPlains, .iceSpikes, .snowyTaiga, .frozenRiver, .frozenOcean, .deepFrozenOcean, .snowyBeach]
    static let peaks: Set<Biome> = [.jaggedPeaks, .frozenPeaks, .stonyPeaks, .snowySlopes, .grove, .windsweptHills, .windsweptGravellyHills]
}

enum TerrainAudio {
    static func render(_ g: inout Synth, _ s: Snd, p: Float) -> [Float] {
        switch s {
        case .riverLoop:
            // Babbling stream: many small bright bubbles over a soft rushing bed.
            let bed = g.wash(4.0, lp: 2200 * p, hp: 250, wobble: 0.8, rate: 3, gain: 0.35)
            let bub = g.bubbles(4.0, count: 60, fLo: 700 * p, fHi: 2600 * p, len: 0.03, gain: 0.25)
            let trickle = g.crackle(4.0, density: 120, f: 3200, q: 2, gain: 0.5)
            return Synth.loopify(Synth.mix(Synth.mix(bed, bub), trickle), fade: 0.4)
        case .waterfallLoop:
            // Waterfall: broadband roar with a low thunder underneath and spray hiss.
            let roar = g.wash(5.0, lp: 1800 * p, hp: 60, wobble: 0.5, rate: 2, gain: 1.0)
            let low = g.wash(5.0, lp: 140 * p, hp: 25, wobble: 0.7, rate: 1, gain: 1.6)
            let spray = g.wash(5.0, lp: 9000, hp: 3500, wobble: 0.8, rate: 4, gain: 0.15)
            return Synth.loopify(Synth.mix(Synth.mix(roar, low), spray), fade: 0.5)
        case .mountainWindLoop:
            // Deep howl: a resonant, slowly sweeping wind with gusty surges.
            var w = g.wash(6.0, lp: 500 * p, hp: 50, wobble: 2.0, rate: 0.35, gain: 1.0)
            w = Synth.mix(w, Synth.scaled(Synth.bandpass(g.wash(6.0, lp: 2000, hp: 200, wobble: 1.5, rate: 0.5, gain: 1.0), 380 * p, q: 6), 1.6))
            return Synth.loopify(w, fade: 0.8)
        case .tundraWindLoop:
            // Thin, cold whistle over powdery hiss.
            var w = g.wash(6.0, lp: 3500 * p, hp: 900, wobble: 1.5, rate: 0.5, gain: 0.35)
            w = Synth.mix(w, Synth.scaled(Synth.bandpass(g.wash(6.0, lp: 4000, hp: 500, wobble: 1.8, rate: 0.3, gain: 1.0), 1150 * p, q: 9), 1.8))
            return Synth.loopify(w, fade: 0.8)
        case .rainLeavesLoop:
            // Pattering on foliage: dense soft taps, a little dripping.
            let taps = g.crackle(3.0, density: 300, f: 2600 * p, q: 1.5, gain: 0.7)
            let bed = g.wash(3.0, lp: 4000, hp: 900, wobble: 0.3, rate: 3, gain: 0.2)
            let drips = g.bubbles(3.0, count: 8, fLo: 1200, fHi: 2400, len: 0.03, gain: 0.25)
            return Synth.loopify(Synth.mix(Synth.mix(taps, bed), drips), fade: 0.3)
        case .snowWindLoop:
            // Snowfall: a hushed, muffled wind with soft flurries.
            var w = g.wash(5.0, lp: 1200 * p, hp: 180, wobble: 1.6, rate: 0.4, gain: 0.55)
            w = Synth.mix(w, g.wash(5.0, lp: 6000, hp: 2500, wobble: 1.4, rate: 0.8, gain: 0.06))
            return Synth.loopify(w, fade: 0.6)
        case .swampInsectsLoop:
            // Swamp drone: a cloud of buzzing insects (detuned, beating) and the odd low croak.
            var o = [Float](repeating: 0, count: g.frames(4.0))
            for _ in 0..<5 {
                let f: Float = g.rnd(380, 620) * p
                o = Synth.mix(o, g.tone(4.0, f0: f, f1: f * g.rnd(0.98, 1.02), wave: .saw, attack: 0.5, release: 0.5, vib: 0.02, vibRate: g.rnd(5, 12), gain: 0.05))
            }
            o = Synth.bandpass(o, 700, q: 0.8)
            return Synth.loopify(Synth.scaled(o, 2.5), fade: 0.5)
        case .thunderFar:
            // A long, low, rolling rumble with no crack.
            var r = g.rumble(6.0, f: 38 * p, attack: 0.6, decay: 2.2, gain: 2.4)
            r = Synth.mix(r, Synth.decayEnv(Synth.rampIn(g.wash(6.0, lp: 260, hp: 25, wobble: 1.5, rate: 2, gain: 1.4), 0.8), 2.0))
            return Synth.echo(r, delay: 0.7, feedback: 0.3, mix: 0.3, tail: 1.5)
        case .iceCreak:
            let groan = g.tone(g.rnd(0.4, 0.9), f0: g.rnd(600, 1100) * p, f1: g.rnd(250, 500) * p, wave: .sine, attack: 0.02, release: 0.2, vib: 0.05, vibRate: 25, gain: 0.3)
            return Synth.mix(groan, g.crackle(0.8, density: 60, f: 3000, q: 5, gain: 1.0))
        default:  // rockfall: tumbling stones down a slope
            var o = g.rumble(1.6, f: 70, attack: 0.05, decay: 0.6, gain: 1.4)
            for k in 0..<14 { o = Synth.mix(o, g.material(.stone, pitch: g.rnd(0.6, 1.1), scale: 0.6, gain: 0.5), at: g.frames(Float(k) * 0.09 * g.rnd(0.6, 1.4))) }
            return o
        }
    }
}

extension Game {
    // Terrain beds for the surface (called from the ambient tick with the shared loop asker).
    func terrainAudioTick(_ dt: Float, open: Float, ask: (String, Snd, Float, V3?) -> Void) {
        let a = audio
        let p = player.pos
        let b = a.biomeHere
        let tundra = AmbientBiomes.tundra
        let peaks = AmbientBiomes.peaks
        let height = p.y - Float(SEA)
        if peaks.contains(b) || height > 60 {
            ask("mountainwind", .mountainWindLoop, min(0.9, 0.25 + max(0, height - 30) / 120) * open, nil)
            a.rockTimer -= dt
            if a.rockTimer <= 0 {
                a.rockTimer = Rand.float(in: 40...120)
                let ang = Rand.float(in: 0..<(2 * .pi))
                sfx(.rockfall, 0.8, at: player.eye + V3(cosf(ang) * 30, Rand.float(in: -6...14), sinf(ang) * 30))
            }
        }
        if tundra.contains(b) {
            ask("tundrawind", .tundraWindLoop, 0.45 * open, nil)
            if Rand.float(in: 0..<1) < dt / 25 { sfx(.iceCreak, 0.5, at: player.eye + V3(Rand.float(in: -10...10), -1, Rand.float(in: -10...10))) }
        }
        if b == .swamp || b == .mangroveSwamp { ask("swampbugs", .swampInsectsLoop, 0.3 * open, nil) }
    }

    // Streams and waterfalls, anywhere (surface rivers, cave springs, falls down cliffs).
    func movingWaterTick(ask: (String, Snd, Float, V3?) -> Void) {
        let a = audio
        if let e = a.emitters["river"] {
            let d = simd_length(e.pos - player.eye)
            ask("river", .riverLoop, min(0.8, 0.2 + 0.015 * Float(e.count)) * max(0, 1 - d / 16), e.pos)
        }
        if let e = a.emitters["waterfall"] {
            let d = simd_length(e.pos - player.eye)
            ask("waterfall", .waterfallLoop, min(1.2, 0.35 + 0.04 * Float(e.count)) * max(0, 1 - d / 24), e.pos)
        }
    }

    // Weather beds beyond plain rain: rain on leaves under trees, snow wind while it snows.
    func weatherAudioTick(_ dt: Float, ask: (String, Snd, Float, V3?) -> Void) {
        guard dim.dim == .overworld, weather.rain > 0.05 else { return }
        let a = audio
        let p = player.pos
        let x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
        let kind = precipitation(x, y, z)
        if kind == 2 {
            ask("snowwind", .snowWindLoop, weather.rain * 0.6 * (1 - a.cave), nil)
        } else if kind == 1 && a.leafCover > 0 {
            ask("rainleaves", .rainLeavesLoop, weather.rain * min(1, a.leafCover) * 0.7 * (1 - a.cave), nil)
        }
    }
}
