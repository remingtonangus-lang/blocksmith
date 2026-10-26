import Foundation
import simd

// P459's check (questcheck --gunwreck): a gun mount destroyed comes apart: the Capital's heavy gun, a light gun and a
// Greywall tower gun each burst into pieces of their model flying off as debris.
enum GunWreckCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let at = g.player.pos + V3(6, 0, 0)
        for (name, key) in [("the Capital's heavy gun", "deck_gun"), ("a light gun", "deck_gun:light"), ("a Greywall gun", "deck_gun@grey")] {
            guard let m = Mob.structureMob(key, at: at) else { check(false, "gunwreck: \(key) makes a gun"); continue }
            g.debris.tick(1 / 60, world: g.world)            // (a new frame: the field takes 64 new pieces a frame)
            let d0 = g.debris.bodies.count, w0 = AshArmy.gunsWrecked
            m.health = 0
            g.mobDied(m)
            let pieces = g.debris.bodies.count - d0
            check(AshArmy.gunsWrecked == w0 + 1 && pieces >= 8, "gunwreck: \(name) destroyed comes apart in \(pieces) pieces (\(m.factionValue.name))")
        }
    }
}
