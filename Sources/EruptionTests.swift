import Foundation
import simd

// L3 volcano eruptions (Sources/Eruptions.swift, docs/status/l3-part3.md): how rare they are, what a burst throws near
// and far, the boom arriving at the speed of sound with its shake, the end, and the sound in the bank. The impostor's
// eruption look is checked on the Quest renderer (quest/src/headless/main.swift, the 700-block volcano view).
enum EruptionTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        guard g.dim.dim == .overworld, g.world.gen is WorldGen else { check(false, "eruption: the test runs in the overworld"); return }
        // 1. Rarity: five volcanoes over 60 hours of 10-s rolls: about one eruption per 20 minutes near one.
        var hits = 0
        let slots = Int(60 * 3600 / Game.eruptionSlot)
        for k in 0..<5 {
            var v = Volcano(); v.x = Float(1000 + 1777 * k); v.z = Float(-500 - 913 * k); v.exists = true
            for s in 0..<slots where Game.eruptionRoll(v, slot: s, seed: 0x1234 &+ UInt32(k)) { hits += 1 }
        }
        let gapMin = Double(5 * slots) * Game.eruptionSlot / Double(max(1, hits)) / 60
        check(gapMin > 15 && gapMin < 25, "eruption: one about every " + String(format: "%.1f", gapMin) + " minutes spent near a volcano (\(hits) in 5 x 60 h)")

        // A volcano 150 blocks off (synthetic: the logic doesn't need its terrain).
        let saved = (g.eruption, g.eruptionBooms, g.shake, g.audio.record, g.particles.list)
        defer { g.eruption = saved.0; g.eruptionBooms = saved.1; g.shake = saved.2; g.audio.record = saved.3; g.particles.list = saved.4 }
        func volcano(_ d: Float) -> Volcano {
            var v = Volcano()
            let e = g.player.eye
            v.x = e.x + d; v.z = e.z; v.base = e.y - Float(YOFF) - 100; v.peak = 120; v.r = 180; v.crater = 30; v.depth = 20
            v.exists = true
            return v
        }
        // 2. The strength curve: rises over 3 s, holds, fades over the last 5.
        g.startEruption(volcano(150))
        guard var e = g.eruption else { check(false, "eruption: startEruption starts one"); return }
        let c0 = e.start
        let curve = [0, 1.5, 10, Double(e.length) - 2.5, Double(e.length)].map { e.strength(c0 + $0) }
        check(curve[0] == 0 && abs(curve[1] - 0.5) < 0.01 && curve[2] == 1 && abs(curve[3] - 0.5) < 0.01 && curve[4] == 0
              && e.length >= 18 && e.length <= 30,
              "eruption: lasts " + String(format: "%.0f s", e.length) + ", strength " + curve.map { String(format: "%.2f", $0) }.joined(separator: " "))

        // 3. A burst 150 blocks off: glowing lava bombs and ash, the boom on its way (arriving in 150/343 s) with a shake.
        g.particles.list.removeAll(); g.eruptionBooms.removeAll(); g.shake = 0
        e.start = g.clock - 8; e.nextBurst = g.clock; g.eruption = e
        g.eruptionTick(0.05)
        let bombs = g.particles.list.filter { $0.glow }.count, ash = g.particles.list.filter { !$0.glow }.count
        let boom = g.eruptionBooms.first
        let delay = boom.map { $0.0 - g.clock } ?? -1
        check(bombs >= 14 && ash >= 8 && g.eruption?.bursts == 1 && abs(delay - 150.0 / 343) < 0.05 && (boom?.2 ?? 0) > 0 && g.shake == 0,
              "eruption: a burst 150 blocks away throws \(bombs) lava bombs and \(ash) ash puffs; its boom arrives in " + String(format: "%.2f s", delay) + " (shake waits for it)")
        // 4. The boom arrives: the rumble plays and the view shakes.
        g.audio.record = [:]
        g.eruptionBooms = g.eruptionBooms.map { (g.clock, $0.1, $0.2) }
        g.eruptionTick(0.05)
        let heard = g.audio.record?[Snd.volcanoRumble.name] ?? 0
        check(heard == 1 && g.shake > 0.1 && g.eruptionBooms.isEmpty,
              "eruption: the boom plays the rumble (\(heard)) and shakes the view (" + String(format: "%.2f", g.shake) + ")")
        // 5. Next bursts come 2-5 s apart.
        let gap = (g.eruption?.nextBurst ?? 0) - g.clock
        check(gap >= 1.9 && gap <= 5.1, "eruption: the next burst in " + String(format: "%.1f s", gap))

        // 6. Far (900 blocks): no particles past the loaded terrain (the impostor shows it), a quieter boom, no shake.
        g.particles.list.removeAll(); g.eruptionBooms.removeAll(); g.shake = 0
        var far = Eruption(v: volcano(900), start: g.clock - 8, length: 25, nextBurst: g.clock)
        if g.world.renderDistance * CS + 160 >= 900 { far.v = volcano(Float(g.world.renderDistance * CS + 400)) }
        g.eruption = far
        g.eruptionTick(0.05)
        let fb = g.eruptionBooms.first
        check(g.particles.list.isEmpty && fb != nil && (fb?.1 ?? 0) >= 0.25 && (fb?.2 ?? 1) == 0,
              "eruption: far away, no particles and a boom of " + String(format: "%.2f", fb?.1 ?? 0) + " with no shake")

        // 7. The end: past its length the eruption is over.
        far.start = g.clock - Double(far.length) - 1; g.eruption = far
        g.eruptionTick(0.05)
        check(g.eruption == nil, "eruption: over after its length")

        // 8. The sound: in the bank (a long low rumble, not silent or clipped) with a subtitle.
        let clip = SoundBank.render(.volcanoRumble, variant: 0)
        let sc = SoundBank.check(.volcanoRumble, clip)
        check(SoundBank.allSounds.contains { $0.name == Snd.volcanoRumble.name } && sc.ok,
              "eruption: the rumble is in the bank (" + String(format: "%.1f s, peak %.2f", sc.seconds, sc.peak) + (sc.ok ? ")" : ", " + sc.problems.joined(separator: ", ") + ")"))
    }
}
