import Foundation
import simd

// Remington's Quest v78 playtest (2026-10-09): reach, riding (B / dismount, pickups), creeper fuse, spawning, plants.
// Run with --questbugs (or `--questbugs --only v78`). Sprint is checked in QuestBugTests and QuestSim.
enum PlaytestV78Tests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        let p = game.player, w = game.world
        let save = (p.pos, p.yaw, p.pitch, p.flying, game.paused, game.riding)
        defer {
            game.input.releaseAll()
            (p.pos, p.yaw, p.pitch, p.flying, game.paused, game.riding) = save
            p.vel = .zero
        }
        // An open-air test pad high above the spawn: stone floor, nothing in the way.
        let bx = Int(floor(p.pos.x)), by = Int(floor(p.pos.y)) + 60, bz = Int(floor(p.pos.z))
        for x in (bx - 9)...(bx + 9) { for z in (bz - 9)...(bz + 9) { for y in (by - 1)...(by + 5) { w.setBlock(x, y, z, y == by - 1 ? STONE : AIR) } } }
        defer { for x in (bx - 9)...(bx + 9) { for z in (bz - 9)...(bz + 9) { for y in (by - 1)...(by + 5) { w.setBlock(x, y, z, AIR) } } } }
        let floorP = V3(Float(bx) + 0.5, Float(by), Float(bz) + 0.5)
        func frames(_ n: Int) { for _ in 0..<n { game.tick(1.0 / 60); game.input.endFrame() } }
        game.paused = false
        p.flying = false

        // Reach: a block 5.6 blocks ahead of the eye is targeted (was 4.5 in survival).
        p.pos = floorP; p.vel = .zero; p.yaw = 0; p.pitch = 0
        frames(2)
        let eye = p.eye
        let tz = Int(floor(eye.z - 5.6)), ty = Int(floor(eye.y))
        w.setBlock(bx, ty, tz, STONE)
        frames(1)
        check(game.target?.hit == IVec3(bx, ty, tz), String(format: "reach: a block %.1f blocks ahead is targeted (got %@)", eye.z - Float(tz) - 0.5, game.target.map { "\($0.hit)" } ?? "nothing"))
        w.setBlock(bx, ty, tz, AIR)

        // Riding: the B / sneak that closes the mount screen doesn't dismount; a fresh press does.
        let h = Mob(.horse, at: floorP + V3(0, 0, 3))
        h.owner = true; h.saddled = true; h.persistent = true
        game.mobs.mobs.append(h)
        defer { game.mobs.mobs.removeAll { $0 === h } }
        game.riding = h
        frames(3)
        game.openMenu(MountMenu(game: game, mob: h))
        game.input.shift = true
        game.closeMenu()
        frames(10)
        check(game.riding === h, "riding: the press that closed the mount screen, still held, keeps you on the horse")
        game.input.shift = false
        frames(3)
        // Mounted pickup: an item at the horse's feet is picked up from the saddle.
        let before = game.inventory.main.countOf(Items.id("iron_ingot"))
        game.drops.spawn(ItemStack(Items.id("iron_ingot"), 3), at: h.pos + V3(0.6, 0.1, 0), vel: .zero, delay: 0, deliberate: true)
        frames(12)
        let got = game.inventory.main.countOf(Items.id("iron_ingot")) - before
        check(got == 3, String(format: "riding: an item at the horse's feet (%.1f below the rider) is picked up (%d of 3)", p.pos.y - h.pos.y, got))
        game.input.shift = true
        frames(2)
        check(game.riding == nil, "riding: a fresh sneak / B press dismounts")
        game.input.shift = false
        frames(1)
        // Hisser: left alone it blows after ~1.75 s; an iron-sword hit every cooldown (0.625 s) kills it first.
        let hs = (game.survival, game.difficulty, game.health)
        game.survival = true; game.difficulty = 2
        for hitting in [false, true] {
            p.pos = floorP; p.vel = .zero; p.yaw = 0; p.pitch = 0
            game.health = 20
            let c = Mob(.creeper, at: floorP + V3(0, 0, -2.5))
            game.mobs.mobs.append(c)
            var t: Float = 0, nextHit: Float = 0.3, hits = 0
            while t < 4 && c.health > 0 {
                if hitting && t >= nextHit { c.hit(from: p.eye, damage: 6, iframes: true); hits += 1; nextHit += 0.625 }
                frames(1); t += 1.0 / 60
            }
            let blew = c.health <= -1000
            game.mobs.mobs.removeAll { $0 === c }
            if hitting { check(!blew && c.health <= 0, String(format: "hisser: steady sword hits kill it before it blows (%d hits, %.2f s, blew %@)", hits, t, blew ? "yes" : "no")) }
            else { check(blew && t > 1.6, String(format: "hisser: left alone it blows after %.2f s (want > 1.6)", t)) }
            for x in (bx - 9)...(bx + 9) { for z in (bz - 9)...(bz + 9) { for y in (by - 1)...(by + 5) { w.setBlock(x, y, z, y == by - 1 ? STONE : AIR) } } }
        }
        (game.survival, game.difficulty, game.health) = hs
        p.pos = save.0
        // Plants (v78: "too noisy"): fresh ground has no tall grass and short grass on few grass blocks; drawn smaller.
        var grassTops = 0, short = 0, tall = 0
        let sx = Int(floor(p.pos.x)), sz = Int(floor(p.pos.z))
        let tallID = Blocks.id("tall_grass")
        for x in (sx - 40)...(sx + 40) { for z in (sz - 40)...(sz + 40) where w.isLoaded(x, z) {
            let y = w.topY(x, z)
            for yy in (y - 2)...(y + 1) where w.block(x, yy, z) == Blocks.id("grass_block") {
                grassTops += 1
                let a = w.block(x, yy + 1, z)
                if a == TALL_GRASS { short += 1 }
                if a == tallID { tall += 1 }
            }
        } }
        check(grassTops > 500 && tall == 0 && Float(short) / Float(max(1, grassTops)) < 0.15,
              String(format: "plants: %d grass blocks, %.1f%% short grass, %d tall grass (want < 15%% and none)", grassTops, Float(short) * 100 / Float(max(1, grassTops)), tall))
        check(Blocks.crossSize[Int(TALL_GRASS)] < 12 && Blocks.crossSize[Int(Blocks.id("poppy"))] < 16, "plants: short grass and flowers draw smaller than a block")
        spawning(game, check)
    }

    // Monster spawning at night (playtest v78: "no mobs on the ground or in caves at all"): 60 s of the spawner's own
    // attempts (no mob AI, nothing despawns) at a Quest-like render distance, on the surface and in a cave.
    static func spawning(_ game: Game, _ check: (Bool, String) -> Void) {
        let w = game.world, p = game.player
        let save = (game.survival, game.difficulty, game.time, w.renderDistance, p.pos, game.mobs.mobs)
        defer { (game.survival, game.difficulty, game.time, w.renderDistance, p.pos, game.mobs.mobs) = save }
        game.survival = true; game.difficulty = 2; game.time = 0.75 * DAY_LENGTH
        w.renderDistance = 6
        func run(_ at: V3) -> (all: Int, near: Int, close: Int, under: Int) {
            p.pos = at
            game.mobs.mobs.removeAll { $0.kind.category == .monster }
            for _ in 0..<(60 * 4) { game.mobs.hostileAttempts(game) }
            let ms = game.mobs.mobs.filter { $0.kind.category == .monster }
            let under = ms.filter { Int(floor($0.pos.y)) < w.topY(Int(floor($0.pos.x)), Int(floor($0.pos.z))) - 8 }.count
            let near = ms.filter { simd_length($0.pos - at) < 48 }.count
            let close = ms.filter { simd_length($0.pos - at) < 32 }.count
            return (ms.count, near, close, under)
        }
        let sx = Int(floor(save.4.x)), sz = Int(floor(save.4.z))
        let surf = run(V3(Float(sx) + 0.5, Float(w.topY(sx, sz) + 1), Float(sz) + 0.5))
        check(surf.all - surf.under >= 4, "spawning: night surface, 60 s: \(surf.all - surf.under) on the ground, \(surf.under) underground (want >= 4 on the ground)")
        // A cave near the spawn: dark open floor at least 12 below the surface.
        var cave: V3?
        search: for r in stride(from: 0, through: 40, by: 4) { for dx in stride(from: -r, through: r, by: 4) { for dz in [-r, r] {
            let x = sx + dx, z = sz + dz, top = w.topY(x, z)
            guard top > 20 else { continue }
            for y in stride(from: top - 12, to: 8, by: -1) where Blocks.opaque[Int(w.block(x, y - 1, z))] && w.block(x, y, z) == AIR && w.block(x, y + 1, z) == AIR && w.lightAt(x, y, z).sky == 0 {
                cave = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5); break search
            }
        } } }
        if let c = cave {
            let r = run(c)
            check(r.under >= 3 && r.near >= 2, String(format: "spawning: in a cave at y %d, 60 s: %d underground, %d within 48 blocks (want >= 3 and >= 2)", Int(c.y) - 64, r.under, r.near))
            check(r.close <= 8, "spawning: in a cave, no swarm: \(r.close) monsters within 32 blocks (want <= 8)")
        } else { check(false, "spawning: no cave found near the spawn to test") }
    }
}
