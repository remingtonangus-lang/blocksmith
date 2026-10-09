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
    }
}
