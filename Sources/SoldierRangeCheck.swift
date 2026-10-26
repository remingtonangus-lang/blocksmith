import Foundation
import simd

// P460's range check (questcheck --soldierrange; Oct 25 17:01, Stormwarden marines while he hovered over them on a
// jetpack: "They need to come at me from a greater range"): a rifleman already in the fight, the player hanging 30
// blocks over him and 28 off (41 away), for 12 s: it should keep shooting at him. Run twice: with the rank's sight
// alone (as it was) and with the gun's reach.
enum SoldierRangeCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let home = g.player.pos
        _ = w.loadSync(center: home, radius: 3)
        let mobs0 = g.mobs.mobs, pos0 = g.player.pos, fly0 = g.player.flying, surv0 = g.survival
        defer {
            g.mobs.mobs = mobs0; g.mobs.rebuildIndex(); g.arms.slugs.removeAll(); g.player.pos = pos0; g.player.flying = fly0
            g.survival = surv0; Soldier.reachOff = false
        }
        let px = Int(floor(home.x)), pz = Int(floor(home.z))
        let ground = Float(w.topY(px, pz) + 1)
        g.survival = true; g.alive = true
        func trial(_ off: Bool) -> (Int, Int, Float) {
            Soldier.reachOff = off
            let m = Mob(.soldierTrooper, at: V3(home.x + 28, Float(w.topY(px + 28, pz) + 1), home.z))
            m.variant = Guns.rifle
            m.persistent = true
            m.aggro = true; m.lockTime = 20
            g.mobs.mobs = [m]; g.mobs.rebuildIndex()
            let b = m.soldierBrain
            g.player.flying = true
            var fired = 0, seen = 0, mag = b.mag
            for _ in 0..<(12 * 60) {
                g.player.pos = V3(home.x, ground + 30, home.z); g.player.vel = .zero
                g.health = 20; g.alive = true
                m.update(1.0 / 60, game: g)
                g.arms.update(1.0 / 60, g)
                if b.mag < mag { fired += mag - b.mag }
                mag = b.mag
                if b.sees { seen += 1 }
            }
            g.arms.slugs.removeAll()
            return (fired, seen, simd_length(g.player.eye - m.eye))
        }
        let (f0, s0, _) = trial(true), (f1, s1, d1) = trial(false)
        check(f1 >= 6 && f1 > f0,
              String(format: "soldierrange: a rifleman in the fight with him hovering 30 up (%.0f blocks off at the end) fired %d rounds in 12 s, seeing him %d of 720 ticks (with the rank's sight alone: %d rounds, %d ticks)",
                     d1, f1, s1, f0, s0))
    }
}
