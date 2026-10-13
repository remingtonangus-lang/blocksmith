import Foundation
import simd

// VR trigger attacks (Game.bufferAttacks), from the Mac --questbugs checks so the Linux host runs them too
// (`questcheck --trigger-only`).
enum TriggerSpamCheck {
    static func run(_ game: Game, check: (Bool, String) -> Void) {
        let p = game.player
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
            // A plain one: the Mac run rolls P55/P134 builds (MobVary.on; questcheck turns them off), and a tough roll
            // or a brute takes more than 4 blows (T3: "zombie not dead in 6 s" on the Mac only).
            z.vary = .plain
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
    }
}
