import Foundation
import simd

// D10 guards, parries, kicks and shoves. Bandits, outlaws, road agents and Steelhold soldiers raise a guard (rifle
// across the chest, blade up) when you close in with a blade facing them. Blows that land on that guard from the front
// mostly glance off (a fifth of the damage, a clang), and a blow into a guard just raised is parried: no damage, and you
// are knocked back off balance. Break a guard with the off hand: a kick (sneak and attack) on the flat screen and the
// pad, or a shove (the free hand pushed hard into them) in the headset. A broken guard stays down for 2.5 s.
// Any creature can be shoved: a knock back, no damage.
enum Guards {
    static let parryWindow: Float = 0.3
    static let raiseChance: Float = 1.3              // per second, while threatened
    static let holdFor: Float = 1.3
    static let brokenFor: Float = 2.5
    static let chip: Float = 0.2
    static var parries = 0, blocks = 0, kicks = 0, shoves = 0      // (tests)
    static var shoveCD: Double = 0
    static var stagger = false

    static func canGuard(_ m: Mob) -> Bool {
        guard m.health > 0 else { return false }
        return m.kind.steelhold || m.posse == 1 || m.posse == 2 || m.posse == Contracts.banditPosse
    }
    static func guarding(_ m: Mob) -> Bool { m.guardUp > 0 && m.guardBroken <= 0 }

    // Once a frame (Game.interact): raise and drop guards near the player.
    static func tick(_ g: Game, dt: Float) {
        let p = g.player.pos, look = g.player.look
        let blade = !g.held.isEmpty && g.heldGun == nil
        for m in g.mobs.mobs where (m.guardUp > 0 || m.guardBroken > 0 || m.guardCD > 0 || canGuard(m)) {
            if m.guardBroken > 0 { m.guardBroken -= dt; m.guardUp = 0; continue }
            if m.guardUp > 0 { m.guardUp -= dt; m.guardAge += dt; continue }
            if m.guardCD > 0 { m.guardCD -= dt; continue }
            guard blade, canGuard(m) else { continue }
            let to = m.pos - p
            let d = simd_length(to)
            guard d < 4.5, d > 0.1, simd_dot(to / d, look) > 0.75, Rand.float(in: 0..<1) < raiseChance * dt else { continue }
            m.guardUp = holdFor
            m.guardAge = 0
            m.guardCD = holdFor + Rand.float(in: 1.5...3.5)
            m.face(p)
        }
    }

    // A melee blow from the player on `m`: nil when it isn't guarding (the blow lands as usual), true when the guard
    // took it (glanced, parried, or kicked open).
    static func meet(_ g: Game, _ m: Mob, kick: Bool, damage: Float) -> Bool? {
        guard guarding(m) else { return nil }
        let away = simd_normalize(V3(m.pos.x - g.player.pos.x, 0, m.pos.z - g.player.pos.z) + V3(1e-4, 0, 0))
        // From behind or the side, no guard.
        let facing = V3(-sinf(m.yaw), 0, -cosf(m.yaw))
        guard simd_dot(facing, -away) > 0.2 else { return nil }
        if kick {
            breakGuard(g, m, push: away)
            kicks += 1
            g.onToast?("Kicked their guard open")
            return true
        }
        if m.guardAge < parryWindow {
            g.player.vel += -away * 7 + V3(0, 2.5, 0)
            stagger = true                              // off balance (Game resets its swing)
            m.riposte = SwordPlay.riposteFor; m.attackCooldown = 0      // P308: and it counters
            g.sfx(.shieldBlock, 1, at: m.pos)
            parries += 1
            return true
        }
        g.sfx(.shieldBlock, 0.8, at: m.pos)
        m.riposte = SwordPlay.riposteFor                // P308: a turned blow invites the counter
        Mob.playerMelee = true
        m.hit(from: g.player.pos, damage: max(0, Int((damage * chip).rounded())), knockback: 0.4)
        Mob.playerMelee = false
        blocks += 1
        return true
    }

    static func breakGuard(_ g: Game, _ m: Mob, push: V3) {
        m.guardUp = 0
        m.guardBroken = brokenFor
        m.hit(from: m.pos - push, damage: 1, knockback: 1.6)
        g.sfx(.attackKnockback, 1, at: m.pos)
    }

    // VR: the free hand thrust hard (`vel`, m/s) from `hand` into a creature.
    static func shove(_ g: Game, hand: V3, vel: V3) -> Bool {
        let sp = simd_length(vel)
        guard sp > 2.2, g.clock > shoveCD, g.alive else { return false }
        let dir = vel / sp
        for m in g.mobs.mobs where m.health > 0 && m !== g.riding && g.isCreature(m) {
            let c = m.pos + V3(0, m.height * 0.5, 0)
            let to = c - hand
            let d = simd_length(to)
            guard d < 0.9 + m.halfW, d > 0.01, simd_dot(to / d, dir) > 0.5 else { continue }
            shoveCD = g.clock + 0.6
            let push = simd_normalize(V3(dir.x, 0, dir.z) + V3(1e-4, 0, 0))
            if guarding(m) { breakGuard(g, m, push: push) } else { m.hit(from: m.pos - push, damage: 0, knockback: 1.1) }
            shoves += 1
            return true
        }
        return false
    }
}
