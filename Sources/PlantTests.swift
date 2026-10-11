import Foundation
import simd

// L3 ground (docs/status/ground-l3.md): which plants bend in the wind, how the mesher marks them for the Quest shaders,
// the rustle when walking through them. The look itself (sway, turned grass tops) is checked on the Quest renderer
// (quest/src/test/PlantRenderTest.swift). Shared: questcheck runs it.
enum PlantTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let w = g.world
        // 1. The sway table: ground plants yes (a tall plant's upper half only), stacked, hanging and non-plants no.
        let yes = ["short_grass", "fern", "poppy", "dandelion", "tall_grass[upper]", "large_fern[upper]", "rose_bush[upper]"]
        let no = ["tall_grass", "large_fern", "sugar_cane", "vine", "cobweb", "fire", "grass_block", "oak_leaves", "kelp", "seagrass", "big_dripleaf_stem"]
        let wrongYes = yes.filter { Blocks.has($0) && !Blocks.sway[Int(Blocks.id($0))] }
        let wrongNo = no.filter { Blocks.has($0) && Blocks.sway[Int(Blocks.id($0))] }
        let swaying = (0..<Blocks.count).filter { Blocks.sway[$0] && Blocks.groupBase[$0] == BlockID($0) }.count
        check(wrongYes.isEmpty && wrongNo.isEmpty && swaying >= 20,
              "plants: \(swaying) plants bend in the wind; stems that stack or hang stay still (wrong: \(wrongYes + wrongNo))")

        // 2. The mesher: a poppy and a tall grass on a pad far above the ground, meshed; the poppy's corners and the
        // upper half's carry the sway bit, the lower half's don't, and every swaying corner's phase is 0-3.
        let p0 = g.player.pos
        // Inside one section (4 in from its corner, rows y0 + 1 and + 2 in the same section) so one mesh holds them.
        let x0 = ((Int(floorf(p0.x)) + 220) & ~15) + 4, z0 = ((Int(floorf(p0.z)) + 40) & ~15) + 4
        _ = w.loadSync(center: V3(Float(x0), p0.y, Float(z0)), radius: 2)
        let y0 = min(CH - 32, ((w.topY(x0, z0) + 16) & ~15) + 4)
        let grass = Blocks.id("grass_block")
        var placed: [IVec3] = []
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { w.setBlock(x, y, z, b); placed.append(IVec3(x, y, z)) }
        for dx in 0..<4 { for dz in 0..<4 { put(x0 + dx, y0, z0 + dz, grass) } }
        put(x0, y0 + 1, z0, Blocks.id("poppy"))
        put(x0 + 2, y0 + 1, z0 + 2, Blocks.id("tall_grass"))
        put(x0 + 2, y0 + 2, z0 + 2, Blocks.id("tall_grass[upper]"))
        defer { for q in placed.reversed() { w.setBlock(q.x, q.y, q.z, AIR) } }
        if let c = w.chunkAt(x0, z0), let nb = w.neighbourhood(c) {
            let m = Mesher.buildSection(nb.0, nb.1, sy: (y0 + 1) >> 4)
            let lx = x0 & 15, ly = (y0 + 1) & 15
            var poppy = (0, 0), lower = (0, 0), upper = (0, 0), badPhase = 0     // (swaying, still) corners
            for i in stride(from: 0, to: m.opaque.count, by: 2) {
                let w0 = m.opaque[i], w1 = m.opaque[i + 1]
                guard (w0 >> 27) & 7 == 6 else { continue }
                let x16 = Int(w0 & 511), y16 = Int((w0 >> 9) & 511), v = Int((w1 >> 5) & 31)
                let on = (w1 >> 30) & 1 == 1
                if on && (w1 >> 20) & 3 > 3 { badPhase += 1 }
                func add(_ t: inout (Int, Int)) { if on { t.0 += 1 } else { t.1 += 1 } }
                if x16 < (lx + 2) * 16 { add(&poppy) }
                else if y16 > (ly + 1) * 16 || (y16 == (ly + 1) * 16 && v == 16) { add(&upper) } else { add(&lower) }
            }
            let want = Mesher.plantSway ? (poppy == (16, 0) && upper == (16, 0) && lower == (0, 16)) : (poppy.0 + upper.0 == 0)
            check(want && badPhase == 0,
                  "plants: the mesher marks swaying plants for the shader (poppy \(poppy.0) swaying / \(poppy.1) still corners, tall grass upper \(upper.0) / \(upper.1), lower \(lower.0) / \(lower.1))")
        } else { check(false, "plants: mesh setup (chunk not loaded)") }

        // 3. The rustle: 16 blocks of short grass walked through rustle about every 1.2 blocks; bare ground doesn't.
        let saved = (g.player.pos, g.player.onGround, g.player.flying, g.player.sneaking)
        let row = y0 + 1
        for dx in 0..<20 { put(x0 + dx, y0, z0 + 6, grass); put(x0 + dx, row, z0 + 6, Blocks.id("short_grass")) }
        for dx in 0..<20 { put(x0 + dx, y0, z0 + 8, grass) }
        func walk(_ z: Int) -> Int {
            g.plantBrushes = 0; g.plantBrushDist = 0.9
            g.player.flying = false; g.player.onGround = true; g.player.sneaking = false
            var prev = V3(Float(x0) + 2.5, Float(row), Float(z) + 0.5)
            for i in 1...64 {
                let p = V3(Float(x0) + 2.5 + Float(i) * 0.25, Float(row), Float(z) + 0.5)
                g.player.pos = p
                g.audioTick(from: prev)
                prev = p
            }
            return g.plantBrushes
        }
        let inGrass = walk(z0 + 6), bare = walk(z0 + 8)
        (g.player.pos, g.player.onGround, g.player.flying, g.player.sneaking) = saved
        check(inGrass >= 11 && inGrass <= 15 && bare == 0, "plants: walking 16 blocks through grass rustles \(inGrass) times, bare ground \(bare)")

        // 4. The rustle sound itself: in the bank, a short leafy swish (not silent, not clipped).
        let clip = SoundBank.render(.plantBrush, variant: 0)
        let secs = Float(clip.count) / Synth.sr, peak = clip.map { abs($0) }.max() ?? 0
        check(SoundBank.allSounds.contains { $0.name == Snd.plantBrush.name } && secs > 0.1 && secs < 0.8 && peak > 0.05 && peak <= 1,
              "plants: the rustle sound is in the bank (" + String(format: "%.2f s, peak %.2f)", secs, peak))
    }
}
