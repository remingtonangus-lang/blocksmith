import Foundation
import simd

// `--questbugs`: checks for the Quest playtest bug list of 2026-10-06 (task 20): ore drop counts, sword damage against a
// zombie, climbing out of water onto a one-block bank, and skeletons holding a bow. Prints one line per check.
enum QuestBugTests {
    static func run(_ game: Game) -> Int {
        var fails = 0
        func check(_ ok: Bool, _ msg: String) {
            print("questbugs: \(ok ? "ok  " : "FAIL") \(msg)")
            if !ok { fails += 1 }
        }
        // Ore drops with an iron pickaxe, no Fortune (reference: lapis 4-9, sparkstone dust 4-5).
        let pick = ItemStack(Items.id("iron_pickaxe"), 1)
        for (ore, item, lo, hi) in [("lapis_ore", "lapis_lazuli", 4, 9), ("deepslate_lapis_ore", "lapis_lazuli", 4, 9),
                                    ("redstone_ore", "redstone", 4, 5), ("deepslate_redstone_ore", "redstone", 4, 5)] {
            var mn = 99, mx = 0
            for _ in 0..<400 {
                let n = Mining.drops(Blocks.id(ore), pick).filter { Items.key($0.item) == item }.reduce(0) { $0 + $1.count }
                mn = min(mn, n); mx = max(mx, n)
            }
            check(mn == lo && mx == hi, "\(ore) drops \(mn)...\(mx) \(item) (want \(lo)...\(hi))")
        }
        // Sword damage (reference Java values) and hits to kill a 20 HP zombie with full-strength swings.
        for (k, d) in [("wooden_sword", 4), ("stone_sword", 5), ("iron_sword", 6), ("diamond_sword", 7), ("netherite_sword", 8)] {
            guard Items.has(k) else { check(false, "\(k) missing"); continue }
            let a = ItemStack(Items.id(k), 1).def.attack
            let z = Mob(.zombie, at: game.player.pos + V3(0, 0, -3))
            z.equip = nil                                       // no random armour roll
            var hits = 0
            while z.health > 0 && hits < 20 {
                z.invulnerable = 0
                z.hit(from: game.player.pos, damage: max(1, Int(a.rounded())), knockback: 0, iframes: true)
                hits += 1
            }
            let want = (20 + d - 1) / d
            check(Int(a) == d && hits == want, "\(k): \(a) damage, zombie (20 HP) dies in \(hits) hits (want \(d), \(want))")
        }
        // Climbing out of water: a 3-deep pool with a bank one block above the surface, swim into it.
        let w = game.world
        let p = game.player
        let x0 = Int(floor(p.pos.x)), z0 = Int(floor(p.pos.z)), y0 = min(CH - 20, Int(p.pos.y) + 40)
        for x in (x0 - 3)...(x0 + 4) {
            for z in (z0 - 3)...(z0 + 3) {
                for y in (y0 - 4)...(y0 + 3) {
                    let wall = x == x0 - 3 || x == x0 + 4 || z == z0 - 3 || z == z0 + 3 || y == y0 - 4
                    let bank = x >= x0 + 2 && y <= y0
                    w.setBlock(x, y, z, wall || bank ? STONE : (y < y0 ? WATER : AIR))
                }
            }
        }
        let save = (p.pos, p.vel, p.yaw, p.flying, p.moveLook)
        p.flying = false
        p.moveLook = nil
        p.pos = V3(Float(x0) + 0.5, Float(y0) - 1.5, Float(z0) + 0.5)
        p.vel = .zero
        p.yaw = -.pi / 2                                    // facing +x
        var t: Float = 0
        while t < 6 && !(p.onGround && p.pos.y >= Float(y0) + 0.99) {
            p.update(dt: 1.0 / 60, input: MoveInput(forward: 1), world: w)
            t += 1.0 / 60
            if Int(t * 60) % 20 == 0 && CommandLine.arguments.contains("--verbose") {
                print(String(format: "questbugs:   t %.2f pos %.2f %.2f %.2f vel %.2f %.2f wet %d ground %d", t, p.pos.x - Float(x0), p.pos.y, p.pos.z - Float(z0), p.vel.x, p.vel.y, p.inWater ? 1 : 0, p.onGround ? 1 : 0))
            }
        }
        check(p.onGround && p.pos.y >= Float(y0) + 0.99, String(format: "swim out onto a 1-block bank: %.2f s, y %.2f (bank %d)", t, p.pos.y, y0 + 1))
        (p.pos, p.vel, p.yaw, p.flying, p.moveLook) = save
        // VR locomotion: with Player.moveYaw (the head) set, the aim yaw/pitch (the right hand, randomised every
        // tick here) must not change where the stick takes you: walking, flying, sprint-swimming and ladders.
        do {
            let head: Float = 0.7                                    // head yaw: forward = (-sin, -cos)
            let fwd = V3(-sinf(head), 0, -cosf(head))
            let save = (p.pos, p.vel, p.yaw, p.pitch, p.flying, p.moveLook, p.moveYaw, p.swimming)
            var seed: UInt32 = 12345
            func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) }
            func run(_ mode: String, input: MoveInput, start: V3, ticks: Int, handStill: Bool) -> V3 {
                p.pos = start; p.vel = .zero; p.flying = mode == "fly"; p.swimming = false
                p.inWater = false; p.headInWater = false; p.onGround = false
                p.moveYaw = head
                p.moveLook = V3(-sinf(head), 0, -cosf(head))
                p.yaw = 2.5; p.pitch = 0.4
                for _ in 0..<ticks {
                    if !handStill { p.yaw = (rnd() - 0.5) * 6.2; p.pitch = (rnd() - 0.5) * 3 }
                    p.update(dt: 1.0 / 60, input: input, world: w)
                }
                return p.pos - start
            }
            // Flat floor at y0+3 (over the pool area, which is sealed below), walls far away.
            for x in (x0 - 8)...(x0 + 8) { for z in (z0 - 8)...(z0 + 8) { for y in (y0 + 3)...(y0 + 9) { w.setBlock(x, y, z, y == y0 + 3 ? STONE : AIR) } } }
            let floorP = V3(Float(x0) + 0.5, Float(y0) + 4, Float(z0) + 0.5)
            for (mode, inp) in [("walk", MoveInput(forward: 1)), ("strafe", MoveInput(forward: 0, strafe: 1)), ("fly", MoveInput(forward: 1, sprint: true))] {
                let a = run(mode, input: inp, start: floorP, ticks: 60, handStill: true)
                let b = run(mode, input: inp, start: floorP, ticks: 60, handStill: false)
                let dir = simd_normalize(V3(b.x, 0, b.z))
                let want = mode == "strafe" ? V3(cosf(head), 0, -sinf(head)) : fwd
                check(simd_length(V3(a.x, 0, a.z)) > 1.5 && simd_length(a - b) < 1e-3 && simd_dot(dir, want) > 0.999,
                      String(format: "VR %@: moved %.2f along the head (dot %.4f), hand waving changes it by %.4f", mode, simd_length(V3(b.x, 0, b.z)), simd_dot(dir, want), simd_length(a - b)))
            }
            // Sprint-swimming in a deep pool: follows moveLook (the head), not the hand.
            for x in (x0 - 8)...(x0 + 8) { for z in (z0 - 8)...(z0 + 8) { for y in (y0 + 4)...(y0 + 8) { w.setBlock(x, y, z, WATER) } } }
            let deep = V3(Float(x0) + 0.5, Float(y0) + 5.5, Float(z0) + 0.5)
            var swim = MoveInput(forward: 1); swim.sprint = true
            let sa = run("swim", input: swim, start: deep, ticks: 90, handStill: true)
            let sb = run("swim", input: swim, start: deep, ticks: 90, handStill: false)
            let sdir = simd_normalize(V3(sb.x, 0, sb.z))
            check(p.swimming && simd_length(sa - sb) < 1e-3 && simd_dot(sdir, fwd) > 0.999 && simd_length(V3(sa.x, 0, sa.z)) > 2,
                  String(format: "VR swim: swimming %d, moved %.2f along the head (dot %.4f), hand waving changes it by %.4f", p.swimming ? 1 : 0, simd_length(V3(sb.x, 0, sb.z)), simd_dot(sdir, fwd), simd_length(sa - sb)))
            // Ladder: a wall straight ahead of the head with a ladder on it; pushing forward climbs whatever the hand does.
            for x in (x0 - 8)...(x0 + 8) { for z in (z0 - 8)...(z0 + 8) { for y in (y0 + 4)...(y0 + 9) { w.setBlock(x, y, z, AIR) } } }
            // The player stands in a vine shaft (climbable, no collision box, stone all round): pushing forward
            // presses into the wall ahead of the head and climbs, whatever the hand does.
            let vine = Blocks.id("vine")
            if vine != 0 {
                for dx in -1...1 { for dz in -1...1 { for y in (y0 + 4)...(y0 + 9) {
                    w.setBlock(x0 + dx, y, z0 + dz, dx == 0 && dz == 0 ? vine : STONE) } } }
                let la1 = run("ladder", input: MoveInput(forward: 1), start: floorP, ticks: 90, handStill: true)
                let la2 = run("ladder", input: MoveInput(forward: 1), start: floorP, ticks: 90, handStill: false)
                check(la1.y > 2.5 && abs(la1.y - la2.y) < 1e-3, String(format: "VR ladder: climbed %.2f with the hand still, %.2f waving", la1.y, la2.y))
                for dx in -1...1 { for dz in -1...1 { for y in (y0 + 4)...(y0 + 9) { w.setBlock(x0 + dx, y, z0 + dz, AIR) } } }
            } else { check(false, "vine block missing") }
            (p.pos, p.vel, p.yaw, p.pitch, p.flying, p.moveLook, p.moveYaw, p.swimming) = save
        }
        // Skeletons hold a bow (more parts than the bare biped), raised while drawing.
        let sk = Mob(.skeleton, at: p.pos)
        let idle = mobModelParts(sk).count
        sk.aimHold = 1
        let aimParts = mobModelParts(sk)
        check(idle >= 13 && aimParts.contains { abs($0.rotX - 1.45) < 0.01 && $0.color.x > 0.8 && $0.mx.z - $0.mn.z > 13 },
              "skeleton: \(idle) parts, bow string raised while aiming")
        // VR trigger attacks (Game.bufferAttacks): clicking every 0.25 s, each click waits for the cooldown and lands at
        // full strength, so an iron sword kills a 20 HP zombie in 4 hits (v63: ~8 weak, half-charged hits).
        do {
            let save = (game.inventory.held, p.yaw, p.pitch, game.paused, p.pos, p.flying)
            p.pos.y += 60; p.flying = true; p.vel = .zero                  // open air: nothing between the player and it
            game.inventory.held = ItemStack(Items.id("iron_sword"), 1)
            game.bufferAttacks = true
            game.paused = false
            let zp = p.pos + V3(0, 0, -1.6)
            let z = Mob(.husk, at: zp)                              // a zombie that does not burn in the sun
            z.equip = nil
            game.mobs.mobs.append(z)
            var hits = 0, last = z.health, t: Float = 0, sinceClick: Float = 1
            while z.health > 0 && t < 6 {
                p.yaw = 0; p.pitch = -0.4
                p.pos = save.4 + V3(0, 60, 0); p.vel = .zero
                z.pos = zp; z.vel = .zero
                sinceClick += 1.0 / 60
                if sinceClick >= 0.25 { game.input.leftClicked = true; sinceClick = 0 }
                game.tick(1.0 / 60)
                if z.health < last {
                    hits += 1; last = z.health
                    if CommandLine.arguments.contains("--verbose") { print(String(format: "questbugs:   hit %d at %.2f s: zombie %d HP", hits, t, z.health)) }
                }
                t += 1.0 / 60
            }
            check(z.health <= 0 && hits == 4, String(format: "VR trigger spam (iron sword, a click every 0.25 s): zombie dead %@ in %d hits, %.1f s (want 4)",
                                                   z.health <= 0 ? "yes" : "no", hits, t))
            game.mobs.mobs.removeAll { $0 === z }
            game.bufferAttacks = false
            (game.inventory.held, p.yaw, p.pitch, game.paused, p.pos, p.flying) = save
        }
        print("questbugs: \(fails) failures")
        return fails
    }
}
