import Foundation
import simd
import Metal

// P414 step 4: flying flat out at view 24 with the headset's world settings, in real time, for 60 s from a new world's
// spawn. The player's speed must never drop because the world is loading; reports how often he was over ground not
// made yet and over ground not drawn yet (what he would see as unloaded).
//   questcheck --flytest DIR [--rd 24] [--seconds 60] [--walk]   (--walk: on foot, sprinting, instead of flying)
enum QuestFlyTest {
    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        World.fluidSeconds = 0.002; World.handoverSeconds = 0.0015; World.lodNear = 99; World.leafNear = 99   // (QuestApp)
        guard let dirPath = arg("--flytest") else { print("FAIL flytest: --flytest DIR"); return 1 }
        let rd = Int(arg("--rd") ?? "") ?? 24
        let secs = Int(arg("--seconds") ?? "") ?? 60
        let walk = CommandLine.arguments.contains("--walk")
        TextureGen.registerAll()
        let save = SaveManager(dir: URL(fileURLWithPath: dirPath, isDirectory: true))
        let world = World(seed: QuestLaunch.seed, device: sharedSystemDevice, save: save)
        world.renderDistance = rd
        let game = Game(world: world, save: save, persistent: true)
        var req = WorldRequest()
        req.seed = QuestLaunch.seed; req.smooth = true; req.survival = false
        req.setUp(game, meta: nil)
        game.world.renderDistance = rd
        game.world.activeDistance = Game.savedActiveDistance
        _ = game.world.loadSync(center: game.player.pos, radius: 3)
        game.paused = false                            // (a new Game starts paused)
        let p = game.player
        p.flying = !walk; p.fastFlight = true
        if !walk { p.pos.y += 30 }
        let dt = 1.0 / 72
        var frames = 0, unmade = 0, undrawn = 0
        var slowSeconds = 0, worstSpeed: Float = .greatestFiniteMagnitude, speeds: [Float] = []
        var secStart = p.pos
        let t0 = CFAbsoluteTimeGetCurrent()
        for f in 0..<(secs * 72) {
            if game.menu != nil { game.closeMenu() }  // (nothing in the way of the controls)
            game.cine.active = false
            var pad = PadSnapshot()
            pad.ly = 1                                 // the left stick full forward, sprinting (as perfscenes flies)
            PadManager.shared.touch = pad
            game.input.keys.removeAll(keepingCapacity: true)
            game.input.control = true
            game.input.captured = true
            p.flying = !walk
            // Flying: kept 30 blocks over the land 24 blocks ahead (the land as generated, made or not), so a hill
            // ahead never stops him and the speed measured is the loading's alone.
            if !walk {
                let f = V3(-sinf(p.yaw), 0, -cosf(p.yaw)) * 24
                let h = game.world.gen.column(Int(floor(p.pos.x + f.x)), Int(floor(p.pos.z + f.z))).height
                p.pos.y = max(p.pos.y, Float(max(h, SEA) + 30))
            }
            game.tick(dt)
            frames += 1
            let x = Int(floor(p.pos.x)), z = Int(floor(p.pos.z))
            if let c = game.world.chunkAt(x, z) { if !c.meshedOnce { undrawn += 1 } } else { unmade += 1; undrawn += 1 }
            if (f + 1) % 72 == 0 {
                let s = simd_length(V2(p.pos.x - secStart.x, p.pos.z - secStart.z))
                speeds.append(s)
                secStart = p.pos
            }
            // real time: the workers make the land at their own pace while the player moves on at his
            let due = t0 + Double(f + 1) * dt
            let now = CFAbsoluteTimeGetCurrent()
            if due > now { usleep(useconds_t((due - now) * 1_000_000)) }
        }
        PadManager.shared.touch = nil
        let steady = speeds.dropFirst(2)               // (the first two seconds speed up)
        let top = steady.max() ?? 0
        for s in steady { worstSpeed = min(worstSpeed, s); if s < top * 0.9 { slowSeconds += 1 } }
        let late = CFAbsoluteTimeGetCurrent() - t0 - Double(secs)
        print(String(format: "flytest: %@ %d s at view %d: speed %.1f..%.1f blocks/s (seconds under 90%% of top: %d); over ground not made yet %d of %d frames (%.1f%%), not drawn yet %d (%.1f%%); %.0f blocks; ran %.1f s late",
                     walk ? "walking" : "flying", secs, rd, worstSpeed, top, slowSeconds, unmade, frames, Double(unmade) * 100 / Double(frames),
                     undrawn, Double(undrawn) * 100 / Double(frames), speeds.reduce(0, +), late))
        print("flytest: per second " + speeds.map { String(format: "%.0f", $0) }.joined(separator: " "))
        if slowSeconds > 0 { print("FAIL flytest: the speed dropped in \(slowSeconds) seconds"); return 1 }
        return 0
    }
}
