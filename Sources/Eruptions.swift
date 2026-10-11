import Foundation
import simd

// L3 (docs/status/l3-part3.md): rare small volcano eruptions. While the player is within reach of a volcano
// (Landmarks.swift), a roll every 10 s (a hash of the time slot and the volcano, so a world replays the same) starts
// one about every 20 minutes spent near it. An eruption lasts 18-30 s: every 2-5 s a burst throws glowing lava bombs and
// dark ash out of the crater, and its boom reaches the player at the speed of sound (a low rumble and, within 600
// blocks, a little screen shake; a ridden horse within 150 rears). Past the loaded terrain the impostor's plume swells and throws
// sparks (LandmarkRender). Nothing is placed or burnt: a small eruption is a show, it never edits the world or a save.
struct Eruption {
    var v: Volcano
    var start: Double
    var length: Float
    var nextBurst: Double
    var bursts = 0
    // 0...1 over the eruption: rises over 3 s, holds, fades over the last 5 s (the impostor plume reads it).
    func strength(_ clock: Double) -> Float {
        let t = Float(clock - start)
        return max(0, min(1, t / 3, (length - t) / 5))
    }
}

extension Game {
    static let eruptionReach: Float = 1100      // the player within this of the cone's centre (the impostor shows to 2600)
    static let eruptionMeanGap: Double = 1200   // seconds near a volcano between eruptions, on average
    static let eruptionSlot: Double = 10        // one roll per 10 s
    static let eruptionShakeRange: Float = 600

    // The roll for one 10-s slot at one volcano: true about once every eruptionMeanGap seconds.
    static func eruptionRoll(_ v: Volcano, slot: Int, seed: UInt32) -> Bool {
        hashf(slot, Int(v.x), Int(v.z), seed ^ 0xE2A7) < Float(eruptionSlot / eruptionMeanGap)
    }

    func startEruption(_ v: Volcano) {
        let h = hashf(Int(clock), Int(v.x), Int(v.z), 0xE2A8)
        eruption = Eruption(v: v, start: clock, length: 18 + 12 * h, nextBurst: clock + 0.5)
    }

    func eruptionTick(_ dt: Float) {
        // Booms on their way (sound travels 343 blocks a second).
        if !eruptionBooms.isEmpty {
            for (at, vol, shk, spook) in eruptionBooms where clock >= at {
                sfx(.volcanoRumble, vol)
                if shk > 0 { addShake(shk) }
                // A ridden horse within 150 blocks startles when the boom reaches it (not by horseHears' blast radius).
                if spook, let r = riding, r.gaited, r.tamed, r.health > 0 { r.spook(self) }
            }
            eruptionBooms.removeAll { clock >= $0.0 }
        }
        guard dim.dim == .overworld, let wg = world.gen as? WorldGen else { eruption = nil; return }
        let eye = player.eye
        if var e = eruption {
            if clock - e.start > Double(e.length) { eruption = nil; return }
            if clock >= e.nextBurst {
                eruptionBurst(e)
                e.bursts += 1
                e.nextBurst = clock + Double(2 + 3 * hashf(e.bursts, Int(e.v.x), Int(e.v.z), 0xE2A9))
                eruption = e
            }
            return
        }
        let slot = Int(floor(clock / Game.eruptionSlot))
        guard slot != eruptionSlotDone else { return }
        eruptionSlotDone = slot
        for v in wg.terrain.volcanoes(near: eye.x, eye.z, reach: Game.eruptionReach)
        where simd_length(V2(v.x - eye.x, v.z - eye.z)) < Game.eruptionReach && Game.eruptionRoll(v, slot: slot, seed: wg.terrain.s32) {
            startEruption(v)
            return
        }
    }

    // One burst: lava bombs and ash from the crater when it is near enough to see them as particles, the boom on its way.
    func eruptionBurst(_ e: Eruption) {
        let v = e.v
        let vent = V3(v.x, Float(YOFF) + v.lavaLevel + 1, v.z)
        let d = simd_length(vent - player.eye)
        let s = e.strength(clock)
        if d < Float(world.renderDistance * CS) + 160 {
            let smoke = Int(Tex.id("smoke"))
            let spread = v.crater * 0.35
            for _ in 0..<Int(14 + 18 * s) {
                let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 0...spread)
                let out = V3(cosf(a), 0, sinf(a))
                particles.add(Particle(pos: vent + out * r, vel: out * Rand.float(in: 3...11) + V3(0, Rand.float(in: 18...34), 0),
                                       life: Rand.float(in: 3.5...6), maxLife: 6, layer: smoke, uv0: V2(0, 0), uvSize: 1,
                                       size: Rand.float(in: 0.9...1.8), gravity: 12, color: V3(1.0, Rand.float(in: 0.35...0.6), 0.12),
                                       collide: false, glow: true))
            }
            for _ in 0..<Int(8 + 10 * s) {
                let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 0...spread)
                let out = V3(cosf(a), 0, sinf(a))
                let g = Rand.float(in: 0.16...0.3)
                particles.add(Particle(pos: vent + out * r + V3(0, 4, 0), vel: out * Rand.float(in: 1...3) + V3(0, Rand.float(in: 7...13), 0),
                                       life: Rand.float(in: 6...9), maxLife: 9, layer: smoke, uv0: V2(0, 0), uvSize: 1,
                                       size: Rand.float(in: 4...8), gravity: 0.6, color: V3(g, g * 0.95, g * 0.92), collide: false))
            }
        }
        // The boom: louder near, never silent inside the reach; shake only within 600 blocks.
        let vol: Float = max(0.25, 1.3 - d / 700) * (0.5 + 0.5 * s)
        let shk: Float = d < Game.eruptionShakeRange ? 0.45 * (1 - d / Game.eruptionShakeRange) * (0.5 + 0.5 * s) : 0
        eruptionBooms.append((clock + Double(d / 343), vol, shk, d < 150))
    }
}
