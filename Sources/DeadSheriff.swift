import Foundation
import simd

// P483 (Remington, Oct 28 17:57: "to replace the skeleton, I'm thinking we should have some like zombified sheriff that
// just happens to have a six iron... Really inaccurate with it, but still, if he does hit you, it does as much damage.
// So it'll be annoying... It'll be like one out of every five zombies"): the Dead Sheriff. One walker in five that
// comes out at night still wears his hat and star and carries his six-iron. He shambles in like the rest; from 4 to 18
// blocks off, with a clear line, he raises the gun (a hammer click) and fires a moment later: a wild shot, many times a
// living lawman's spread, but a round that lands hits as a six-iron does (SixIron.damage: the iron rule). Six rounds,
// then a slow fumbling reload while he keeps coming. Skeletons no longer come out at night (Spawns.monsters).
// The six-iron's state rides in the townsfolk fields every mob carries (Mob.town: aim, aimAt, fired, reload; think is
// the time to the next shot, swing the recoil the model shows).
enum DeadSheriff {
    static let variant = 7
    static let share: Float = 0.2
    static let near: Float = 4, far: Float = 18
    static let aimTime: Float = 0.8
    static let cooldown: Float = 2.4
    static let reloadTime: Float = 5
    static var shots = 0, hits = 0                       // (checks)

    static func isOne(_ m: Mob) -> Bool { m.kind == .zombie && m.variant == variant }

    // From the walker's chase (Mob.update): nil keeps him shambling on; a speed (0) while he takes aim.
    static func step(_ m: Mob, _ dt: Float, _ g: Game, dist: Float) -> Float? {
        m.town.swing = max(0, m.town.swing - dt)
        m.town.think -= dt
        if m.town.reload > 0 {
            m.town.reload -= dt
            if m.town.reload <= 0 { m.town.fired = 0 }
            return nil
        }
        if m.town.aim > 0 {
            m.town.aim -= dt
            m.moving = false
            if m.town.aim <= 0 { fire(m, g) }
            return 0
        }
        guard g.survival, g.alive, m.town.think <= 0, dist > near, dist < far, abs(g.player.pos.y - m.pos.y) < 10 else { return nil }
        let chest = g.player.pos + V3(0, (g.player.eye.y - g.player.pos.y) * 0.72, 0)
        guard g.world.clearShot(muzzle(m), chest) else { return nil }
        m.town.aim = aimTime
        m.town.aimAt = chest
        m.moving = false
        g.sfx(.gunReload(WeaponAudio.sidearmSlot), 0.5, at: m.eye)                     // the hammer click
        return 0
    }

    static func muzzle(_ m: Mob) -> V3 { m.eye + m.forward * 0.7 + V3(0, -0.35, 0) }

    static func fire(_ m: Mob, _ g: Game) {
        m.town.think = cooldown * Rand.float(in: 0.8...1.3)
        m.town.swing = 0.3
        m.town.fired += 1
        if m.town.fired >= SixIron.rounds { m.town.reload = reloadTime; g.sfx(.gunReload(WeaponAudio.sidearmSlot), 0.6, at: m.eye) }
        let o = muzzle(m)
        g.sfx(.gun(WeaponAudio.sidearmSlot), 1, at: o)
        g.particles.smoke(at: o)
        shots += 1
        let to = m.town.aimAt - o
        let len = simd_length(to)
        guard len > 0.01 else { return }
        // A dead hand: about seven times the sheriff's spread (he hits about one shot in four or five at 10 blocks).
        let spread = 0.05 + 0.004 * len
        let d = simd_normalize(to / len + V3(Rand.float(in: -1...1), Rand.float(in: -1...1), Rand.float(in: -1...1)) * spread)
        guard let t = Armory.playerHit(g, o, d, len + 3), g.world.clearShot(o, o + d * max(0, t - 0.05)) else {
            if simd_length(simd_cross(g.player.eye - o, d)) < 2.5 { g.sfx(.bulletWhizz, 0.8, at: g.player.eye) }
            return
        }
        hits += 1
        g.sixIronHit(by: m, at: o + d * t)
    }

    // The look (WalkerModel): a black wide-brimmed hat, a tarnished star, the gun in his right hand.
    static let hat = V3(0.09, 0.08, 0.08), band = V3(0.3, 0.22, 0.14), star = V3(0.62, 0.52, 0.26), iron = V3(0.2, 0.2, 0.22)
}
