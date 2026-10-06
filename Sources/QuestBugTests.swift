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
        // Skeletons hold a bow (more parts than the bare biped), raised while drawing.
        let sk = Mob(.skeleton, at: p.pos)
        let idle = mobModelParts(sk).count
        sk.aimHold = 1
        let aimParts = mobModelParts(sk)
        check(idle >= 13 && aimParts.contains { abs($0.rotX - 1.45) < 0.01 && $0.color.x > 0.8 && $0.mx.z - $0.mn.z > 13 },
              "skeleton: \(idle) parts, bow string raised while aiming")
        print("questbugs: \(fails) failures")
        return fails
    }
}
