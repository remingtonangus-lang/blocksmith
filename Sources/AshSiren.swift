import Foundation
import simd

// P319 (Oct 15 18:53, the Ash Vault's alarm: "I like it", but make it a proper air-raid siren). Original synthesis.
//   sound      a motor siren: the rotor spins up for about four seconds into a howl, holds a moment and runs down
//              over five, rising and falling for as long as the alarm lasts (one 10 s cycle, looped seamlessly).
//   posts      every garrison that sends squads (HQ, staging, motor pools, fuel depots, supply, the towns, the
//              airfield) has a siren on a mast over its centre; the two nearest wail together, heard across the
//              base and fading out by about 380 blocks.
//   on / off   they run while the vault stands at Alarm or Total War; a garrison the player has cleared
//              (Game.ashCleared) winds its siren down, and all of them stop when the alarm falls back or the
//              vault is won.

enum AshSiren {
    static let cycle: Float = 10
    static let reach: Float = 380

    // Rotor speed over the cycle, 0 (nearly stopped) ... 1 (full howl). Periodic: g(cycle) == g(0), so the
    // loop's pitch never jumps at the join.
    static func speed(_ t: Float) -> Float {
        let rest: Float = 0.04
        let t = t - floorf(t / cycle) * cycle
        let rise: Float = 4.5
        let peak: Float = rest + (1 - rest) * (1 - expf(-rise / 1.1))
        if t < rise { return rest + (1 - rest) * (1 - expf(-t / 1.1)) }
        let tau: Float = (cycle - rise) / logf(peak / rest)
        return peak * expf(-(t - rise) / tau)
    }

    // One cycle plus the cross-fade overlap, rendered straight through so the overlap is the real continuation.
    static func render(_ s: inout Synth, p: Float) -> [Float] {
        let fade: Float = 0.5
        let n = s.frames(cycle + fade)
        var out = [Float](repeating: 0, count: n)
        var phase: Float = 0, phase2: Float = 0
        var air: Float = 0
        let lo: Float = 110 * p, hi: Float = 455 * p
        for i in 0..<n {
            let t = Float(i) / Synth.sr
            let g = speed(t)
            let wob: Float = 1 + 0.004 * sinf(2 * .pi * 0.7 * t)
            let f: Float = (lo + (hi - lo) * g) * wob
            phase += f / Synth.sr
            phase -= floorf(phase)
            phase2 += f * 2.003 / Synth.sr
            phase2 -= floorf(phase2)
            // The rotor ports chop the air: a driven sine, hollow and rich in odd harmonics, with a weaker
            // octave from the second ring of ports.
            let a = sinf(2 * .pi * phase)
            let body: Float = tanhf(2.6 * a) * 0.8 + 0.18 * sinf(2 * .pi * phase2)
            // The rush of air through the housing, louder as it spins up.
            let w = s.noise()
            air += (w - air) * 0.18
            let loud: Float = 0.2 + 0.8 * powf(g, 0.7)
            out[i] = (body + air * 0.35 * g) * loud
        }
        out = Synth.lowpass(out, 3200)
        return Synth.loopify(out, fade: fade)
    }
}

extension Game {
    // The siren posts sounding now, nearest first (at most two), with their volume at the listener.
    func ashSirens(_ eye: V3) -> [(String, V3, Float)] {
        guard dim.dim == .deep, !ashVictory, ashAlarmLevel >= 2, DeepGen.inVault(eye.y) else { return [] }
        var near: [(String, V3, Float)] = []
        for s in AshWar.sites where AshArmy.senders.contains(s.kind) {
            let key = AshArmy.siteKey(s)
            guard !ashCleared.contains(key) else { continue }
            let mast: Float = s.kind == "hq" ? 26 : 14
            let pos = V3(Float(s.x) + 0.5, Float(AshWar.ground) + mast, Float(s.z) + 0.5)
            let d = simd_length(pos - eye)
            guard d < AshSiren.reach else { continue }
            let k = 1 - d / AshSiren.reach
            let v: Float = (ashAlarmLevel == 3 ? 1.35 : 1.1) * k * k
            near.append(("ashsiren:" + key, pos, v))
        }
        near.sort { $0.2 > $1.2 }
        return Array(near.prefix(2))
    }
}
