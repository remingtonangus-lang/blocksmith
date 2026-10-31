import Foundation
import simd
import Metal

// The Oct 31 afternoon freezes (0.129 b0d800c0): at the Field Hospital on his seed 8775627479714902329 (about -481 130
// -1252) he manned its deck gun and "shot a bunch of shit": the game thread ran on in CraterJob.step -> fieldCarve ->
// fieldSphere until the ANR (16:19:45), and a second time for good. A Polygons world there with the base as the game
// spawns it; the gun manned, swung round and fired as fast as it reloads into the buildings and ground near it, frame by
// frame at 72 Hz. Reports the worst and average tick, the slowest stage, the open breaches and the blocks falling.
//   questcheck --turretfreeze [--rd 6] [--seconds 45]
enum QuestTurretFreeze {
    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        World.fluidSeconds = 0.002; World.handoverSeconds = 0.0015; World.lodNear = 99; World.leafNear = 99   // (QuestApp)
        StructureCache.plansOffThread = true
        defer { StructureCache.plansOffThread = false }
        let rd = Int(arg("--rd") ?? "") ?? 6
        let seconds = Double(arg("--seconds") ?? "") ?? 45
        TextureGen.registerAll()
        let w = World(seed: 8775627479714902329, device: sharedSystemDevice, save: nil)
        FieldTerrain.newWorlds = true; w.makeFieldWorld()
        w.renderDistance = rd
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true
        SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.menu = nil
        g.survival = true
        g.input.captured = true
        g.time = 0.4 * DAY_LENGTH
        g.player.pos = V3(-483.2, Float(126 + YOFF), -1259.8)
        _ = w.loadSync(center: g.player.pos, radius: rd)
        for _ in 0..<72 { g.tick(1.0 / 72) }                 // (the garrison comes in as the game admits it)
        // The cause (P502): a shell fired above the horizon times out hundreds of blocks over the world's top and its
        // breach's bowl looped (an inverted row range, counted up through every Int on the unchecked build). Bursts over
        // the top, under the bottom and at a point that isn't one finish at once.
        for (name, at) in [("over the top", V3(-483, Float(CH + 200), -1260)), ("under the bottom", V3(-483, -60, -1260)),
                           ("at a non-point", V3(.nan, 200, .infinity)), ("just over the top", V3(-483, Float(CH) + 5.2, -1260))] {
            let job = CraterJob(at: at, radius: NavalGuns.breachRadius, cap: NavalGuns.breachCap, game: g, quiet: true, depth: Int(NavalGuns.breachRadius))
            let t0 = CFAbsoluteTimeGetCurrent()
            var steps = 0
            while !job.done && steps < 400 && CFAbsoluteTimeGetCurrent() - t0 < 5 { job.step(g, blocks: 150); steps += 1 }
            _ = w.carve(at: at, radius: 4.7, mode: .shape)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print(String(format: "turretfreeze: a breach %@: done %@ in %d steps, %.1f ms", name, job.done ? "yes" : "no", steps, ms))
            if !job.done || ms > 250 { print("FAIL turretfreeze: a breach \(name) did not finish"); return 1 }
        }
        // The gun he manned (his 16:18:41 note stood at -481 130.5 -1252, on it): up to 10 s more for the base's mobs.
        let spot = V3(-481, Float(127 + YOFF), -1252)
        func guns() -> [Mob] { g.mobs.mobs.filter { $0.kind == .deckGun && $0.health > 0 }.sorted { simd_length($0.pos - spot) < simd_length($1.pos - spot) } }
        var wait = 0
        while wait < 720 && (guns().first.map { simd_length($0.pos - spot) > 20 } ?? true) { g.tick(1.0 / 72); wait += 1 }
        let all = guns()
        print("turretfreeze: rd \(rd), \(g.mobs.mobs.count) mobs after \(72 + wait) ticks, deck guns at " + all.prefix(6).map { String(format: "%.0f %.0f %.0f", $0.pos.x, $0.pos.y - Float(YOFF), $0.pos.z) }.joined(separator: "; "))
        guard let gun = all.first, simd_length(gun.pos - spot) < 80 else { print("FAIL turretfreeze: no deck gun within 80 blocks of the note's spot"); return 1 }
        if simd_length(gun.pos - spot) > 20 { print(String(format: "turretfreeze: (his gun not here: the nearest, %.0f blocks off)", simd_length(gun.pos - spot))) }
        g.player.pos = gun.pos + V3(0, 2, 0)
        Turrets.shared.mount(g, gun)
        let yaw0 = gun.yaw
        let spheres0 = World.sphereCalls, refills0 = World.refilledAtOnce
        var worst = 0.0, sum = 0.0, n = 0, over = 0, worstStage = "-", maxBreaches = 0, maxFalling = 0
        var slowBy: [String: Int] = [:]
        let outside0 = CraterJob.outside, tips0 = StructureTip.checks, tipped0 = StructureTip.tipped, toppled0 = Felling.toppled
        let frames = Int(seconds * 72)
        for f in 0..<frames {
            g.menu = nil
            g.health = 20; g.alive = true
            // Swung back and forth over 120 degrees, a little down: into the base's buildings and the ground by it; from
            // 20 s raised 8 to 20 degrees (at the towers and the sky over them: his shells that timed out up there).
            let t = Float(f) / 72
            g.player.yaw = yaw0 + sinf(t * 0.35) * 1.05
            // (Then the last 14 s with the trigger let go: the raised shells' 12 s run out, over the world's top.)
            let raised = f >= frames * 4 / 9
            g.player.pitch = raised ? 0.24 + 0.1 * sinf(t * 0.9) : -0.08 - 0.06 * sinf(t * 0.9)
            g.input.leftClicked = f < frames - 14 * 72
            let a = CFAbsoluteTimeGetCurrent()
            g.tick(1.0 / 72)
            let ms = (CFAbsoluteTimeGetCurrent() - a) * 1000
            sum += ms; n += 1
            maxBreaches = max(maxBreaches, g.arms.breaches.count); maxFalling = max(maxFalling, g.falling.count)
            if ms > 20 {
                over += 1
                let lead = TickProf.summary()
                slowBy[String(lead.prefix(while: { !$0.isNumber }).trimmingCharacters(in: .whitespaces)), default: 0] += 1
            }
            if ms > worst { worst = ms; worstStage = TickProf.summary() }
            if f % (72 * 5) == 72 * 5 - 1 {
                print(String(format: "turretfreeze: %.0f s: %d shots, %d breaches open, %d blocks falling, worst so far %.1f ms", t + 1 / 72,
                             Turrets.shared.shots, g.arms.breaches.count, g.falling.count, worst))
            }
            if Turrets.shared.manned == nil { print("turretfreeze: off the gun at \(f) frames"); break }
        }
        print(String(format: "turretfreeze: %d shots; worst %.1f ms (%@), average %.1f ms, %d of %d frames over 20 ms; at most %d breaches open, %d blocks falling",
                     Turrets.shared.shots, worst, worstStage, sum / Double(max(1, n)), over, n, maxBreaches, maxFalling))
        print("turretfreeze: \(World.sphereCalls - spheres0) field spheres, \(World.refilledAtOnce - refills0) chunks refilled on the frame thread, \(CraterJob.outside - outside0) breaches outside the world")
        print(String(format: "turretfreeze: %d tip checks (worst %.1f ms), %d pieces tipped, %d toppled bodies", StructureTip.checks - tips0, StructureTip.worstMs, StructureTip.tipped - tipped0, Felling.toppled - toppled0))
        let slow = slowBy.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key) x\($0.value)" }
        if !slow.isEmpty { print("turretfreeze:   slow frames led by " + slow.joined(separator: ", ")) }
        if seconds >= 45 && CraterJob.outside == outside0 { print("FAIL turretfreeze: no shell burst over the world's top (the freeze's case not met)"); return 1 }
        let limit = ProcessInfo.processInfo.environment["BS_FREEZE_MS"].flatMap { Double($0) } ?? 250
        if worst > limit { print(String(format: "FAIL turretfreeze: a frame took %.1f ms on the gun (limit %.0f)", worst, limit)); return 1 }
        print("turretfreeze: passed")
        return 0
    }
}
