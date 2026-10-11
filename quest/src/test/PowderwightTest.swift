import Foundation
import simd

// L1 part 2 (docs/status/look-upgrade.md): the Powderwight replaces the genre's exploding mob in the same role, with its
// own look, telegraph and counterplay. Logic checks on the shared game (no explosion is let off: every run stops
// before the fuse burns down) plus, with a Vulkan device, portraits for the screenshot sheet.
enum PowderwightTest {
    static func run(game: Game, check: (Bool, String) -> Void) {
        let p = game.player
        let saved = (p.pos, p.flying, game.weather, game.survival, game.health, game.mobs.mobs, p.sneaking, game.inventory.armor[0], game.alive)
        defer {
            (p.pos, p.flying, game.weather, game.survival, game.health, game.mobs.mobs, p.sneaking, game.inventory.armor[0], game.alive) = saved
            game.mobs.rebuildIndex()
        }
        // What the fuse rule senses, forced: a live, unhidden, standing player in plain sight with no cats about
        // (invisibility is not set by any earlier check).
        game.mobs.mobs = []; game.mobs.rebuildIndex()
        p.sneaking = false
        game.inventory.armor[0] = .empty
        game.alive = true
        game.health = 20
        p.flying = false
        let w = game.world
        // Name, save key, drops: the mob keeps its save key ("creeper"), so old saves' mobs load as Powderwights.
        check(MobKind.creeper.spec.name == "Powderwight" && MobKind.creeper.key == "creeper",
              "powderwight: shown as Powderwight, saved under the old key (old saves convert)")
        // A pre-change save's record ({"k": "creeper"}, written before the rename) comes back as the new mob.
        let oldJSON = #"{"k":"creeper","p":[1.5,70,2.5],"yaw":0.5,"hp":20}"#
        let rec = try? JSONDecoder().decode(MobRecord.self, from: Data(oldJSON.utf8))
        let back = rec.flatMap { Mob.from($0) }
        check(back?.kind == .creeper && back?.spec.name == "Powderwight", "powderwight: an old save's mob record loads as a Powderwight")
        // Model: the keg and the spark. No spark until the fuse is struck; then a bright emissive part on top of the keg.
        let m = Mob(.creeper, at: p.pos)
        let idle = mobModelParts(m)
        m.fuse = 0.6
        let litParts = mobModelParts(m)
        let spark = litParts.filter { $0.pattern == 9 && $0.mn.y > 24 && $0.mn.z > 3 }
        check(litParts.count == idle.count + 1 && spark.count == 1 && (spark.first.map { max($0.color.x, max($0.color.y, $0.color.z)) } ?? 0) > 0.7,
              "powderwight: the lit fuse adds a bright spark on its keg (\(idle.count) parts idle, \(litParts.count) lit)")
        let top = idle.map { $0.mx.y }.max() ?? 0
        check(top > 28 && top < 32, String(format: "powderwight: model is %.1f px tall (1.7-block mob, cap on top)", top))
        // Fuse behaviour on open level ground near the spawn: struck within 3 blocks in sight, a hit makes it flinch.
        var sp = game.findSpawn()
        _ = w.loadSync(center: sp, radius: 3)
        // Dry, level ground: the player's column and the one two blocks east both solid (no liquid) at the same height.
        func dry(_ x: Int, _ z: Int) -> Int? {
            let y = w.topY(x, z)
            return Blocks.isLiquid(w.block(x, y, z)) || Blocks.isLiquid(w.block(x, y + 1, z)) ? nil : y
        }
        search: for r in 0..<24 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
            let x = Int(floor(sp.x)) + dx, z = Int(floor(sp.z)) + dz
            if let a = dry(x, z), let b = dry(x + 2, z), a == b, w.block(x + 1, a + 1, z) == AIR {
                sp = V3(Float(x) + 0.5, Float(a + 1), Float(z) + 0.5); break search
            }
        } } }
        p.pos = sp
        let wight = Mob(.creeper, at: sp + V3(2, 0, 0))
        game.survival = true
        game.weather = Weather(); game.weather.rain = 0; game.weather.raining = false
        func run(_ secs: Float) { var t: Float = 0; while t < secs && wight.health > 0 { wight.update(0.05, game: game); t += 0.05 } }
        run(1.0)
        let dry = wight.fuse
        if dry == 0 {
            print(String(format: "powderwight: debug alive %d survival %d dist %.2f see %d difficulty %d hp %d pos %.1f %.1f %.1f player %.1f %.1f %.1f",
                         game.alive ? 1 : 0, game.survival ? 1 : 0, simd_length(wight.pos - p.pos), w.canSee(wight.eye, p.eye) ? 1 : 0,
                         game.difficulty, wight.health, wight.pos.x, wight.pos.y, wight.pos.z, p.pos.x, p.pos.y, p.pos.z))
        }
        check(dry > 0.6 && wight.health > 0, String(format: "powderwight: strikes its fuse beside the player (%.2f s burnt of %.2f)", dry, Mob.hisserFuse))
        let sparks = game.particles.list.filter { $0.glow && simd_length($0.pos - wight.kegSpark) < 1.5 }.count
        let sparkUp = wight.kegSpark.y - wight.pos.y
        check(sparks >= 3 && sparkUp > 1.4 && sparkUp < 2.1, String(format: "powderwight: the lit fuse spits sparks off its keg (%d live, %.2f blocks up)", sparks, sparkUp))
        wight.flinch = 0.6
        let before = wight.fuse
        run(0.3)
        check(wight.fuse <= before + 0.01, "powderwight: a hit stops the fuse (flinch)")
        // Water douses it and a soaked fuse can't be struck for a while.
        let feet = IVec3(Int(floor(wight.pos.x)), Int(floor(wight.pos.y)), Int(floor(wight.pos.z)))
        let old = w.block(feet.x, feet.y, feet.z)
        w.setBlock(feet.x, feet.y, feet.z, WATER)
        wight.flinch = 0
        wight.fuse = 1.0
        wight.update(0.05, game: game)
        let doused = wight.fuse
        w.setBlock(feet.x, feet.y, feet.z, old)
        wight.pos = V3(Float(feet.x) + 0.5, Float(feet.y), Float(feet.z) + 0.5)
        wight.vel = .zero
        run(1.5)
        check(doused == 0 && wight.fuse == 0, String(format: "powderwight: water douses the fuse and it stays out while soaked (fuse %.2f after 1.5 s dry)", wight.fuse))
        run(3.2)                                                   // dried out: it strikes again
        check(wight.fuse > 0 && wight.health > 0, String(format: "powderwight: once dry it strikes again (%.2f s)", wight.fuse))
        wight.fuse = 0
    }
}
