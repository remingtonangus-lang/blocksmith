import Foundation
import simd

// D12 silent knife takedowns. Crouched behind someone who hasn't seen you (a guard on watch, a bandit at the fire, a
// creature going about its business), a knife or a blade in hand: the attack is a takedown. One quiet kill, no
// knockback, no cry and no gunshot for anyone to hear. It works on anything a man could put down that way (up to
// 40 health: no bosses, golems or the big beasts), from behind (inside 60 degrees of their back), within 2.2 blocks.
// Soldiers who see you, and creatures already after you, can't be taken down: fight them.
enum Takedowns {
    static let reach: Float = 2.2
    static let behind: Float = 0.5                    // cos of the cone off their back
    static let maxHealth = 40
    static var done = 0                               // (tests)

    static func blade(_ s: ItemStack) -> Bool {
        guard !s.isEmpty else { return false }
        let k = Items.key(s.item)
        return k == ThrownBlades.knife || k.hasSuffix("_sword") || k == "machete" || k.hasSuffix("_knife")
    }

    static func unaware(_ m: Mob) -> Bool {
        if m.kind.steelhold { return !m.soldierBrain.sees && !m.aggro }
        return !m.aggro && m.panic <= 0
    }

    static func can(_ g: Game, _ m: Mob, sneaking: Bool) -> Bool {
        guard sneaking, blade(g.held), m.health > 0, m.spec.health <= maxHealth, g.isCreature(m), unaware(m) else { return false }
        let to = V3(g.player.pos.x - m.pos.x, 0, g.player.pos.z - m.pos.z)
        let d = simd_length(to)
        guard d < reach + m.halfW, d > 0.05 else { return false }
        let facing = V3(-sinf(m.yaw), 0, -cosf(m.yaw))
        return simd_dot(facing, to / d) < -behind
    }

    // The attack, when it is a takedown. True when it was.
    static func attempt(_ g: Game, _ m: Mob, sneaking: Bool) -> Bool {
        guard can(g, m, sneaking: sneaking) else { return false }
        Mob.playerMelee = true
        Mob.meleeGame = g
        m.hit(from: m.pos, damage: max(1, m.health) + 20, knockback: 0)
        Mob.playerMelee = false
        g.sfx(.attackWeak, 0.35, at: m.pos)
        done += 1
        return true
    }
}
