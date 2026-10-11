import Foundation
import simd

// Screenshot sheet for the mob look work (docs/status/look-upgrade.md): each named kind (MobKind.key) stands on a
// floating stone pad above the spawn, seen three-quarter from 3 blocks at noon and at night (and lit, for a mob with a
// fuse). `questcheck --render X --mob-shots DIR --mob-kinds creeper,zombie`.
enum MobPortraits {
    static func run(game: Game, ctx: VkContext, dir: String, kinds: [String]) throws {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let p = game.player
        let saved = (p.pos, p.flying, game.time, game.mobs.mobs)
        defer { (p.pos, p.flying, game.time, game.mobs.mobs) = saved; game.mobs.rebuildIndex() }
        p.flying = true
        let w = game.world
        let base = game.findSpawn() + V3(0, 24, 0)
        let pad = IVec3(Int(floor(base.x)), Int(floor(base.y)) - 1, Int(floor(base.z)))
        var restore: [(IVec3, BlockID)] = []
        for dx in -3...3 { for dz in -3...3 {
            let q = IVec3(pad.x + dx, pad.y, pad.z + dz)
            restore.append((q, w.block(q.x, q.y, q.z)))
            w.setBlock(q.x, q.y, q.z, STONE)
        } }
        defer { for (q, b) in restore { w.setBlock(q.x, q.y, q.z, b) } }
        for key in kinds {
            guard let k = MobKind.allCases.first(where: { $0.key == key }) else { print("mobshots: no kind \(key)"); continue }
            // night20: the readability shot, 20 blocks off in the dark (backlog: hostile silhouettes read at 20 blocks).
            for (tag, t, fuse, far) in [("day", 0.22, Float(0), Float(1)), ("night", 0.75, Float(0), Float(1)), ("lit", 0.22, Float(0.9), Float(1)),
                                        ("night20", 0.75, Float(0), Float(6.5)), ("lit_night20", 0.75, Float(0.9), Float(6.5)),
                                        ("look", 0.22, Float(-1), Float(1)), ("fall", 0.22, Float(-2), Float(1.3))] {
                if fuse > 0 && k != .creeper { continue }
                if (tag == "night20" || tag == "lit_night20") && !(arg("--mob-far") != nil || k == .creeper) { continue }
                let m = Mob(k, at: V3(Float(pad.x) + 0.5, Float(pad.y + 1), Float(pad.z) + 0.5))
                m.yaw = -0.22 * .pi                                       // three-quarter, face toward the camera
                m.fuse = max(0, fuse)
                if fuse == -1 { m.headYaw = -0.75; m.headPitch = 0.25 }        // part 4: head turned toward the camera side, looking up
                if fuse == -2 { m.deathT = 0.32 }                              // part 4: mid-fall
                game.mobs.mobs = [m]; game.mobs.rebuildIndex()
                game.time = t * DAY_LENGTH
                // Camera 3 blocks off toward -z / +x, eye a little above the mob's middle, looking at it.
                let target = m.pos + V3(0, m.height * 0.55, 0)
                let eye = target + V3(1.6, 0.5, -2.6) * max(1, m.height / 1.7) * far
                p.pos = eye - V3(0, p.eyeHeight, 0)
                let f = simd_normalize(target - eye)
                try RenderTest.render(game: game, ctx: ctx, path: "\(dir)/mob_\(key)_\(tag).png", width: 360, height: 360,
                                      yaw: atan2f(-f.x, -f.z), pitch: asinf(f.y), fovDeg: far > 1 ? 40 : 55)
            }
        }
    }
}
