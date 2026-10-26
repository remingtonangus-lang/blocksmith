import Foundation
import simd

// P460's check (questcheck --brigandcheck): Falke Pistol rounds (4 damage) at a Brigand facing the player 6 blocks
// off, chest high, from the front: they wound him and a magazine drops him (his guard turned every one).
enum BrigandRoundsCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let home = g.player.pos
        _ = w.loadSync(center: home, radius: 2)
        let mobs0 = g.mobs.mobs
        defer { g.mobs.mobs = mobs0; g.mobs.rebuildIndex(); g.arms.slugs.removeAll() }
        let px = Int(floor(home.x)), pz = Int(floor(home.z))
        let eye = V3(home.x, Float(w.topY(px, pz) + 1) + 1.6, home.z)
        let m = Mob(.vindicator, at: V3(home.x + 6, Float(w.topY(px + 6, pz) + 1), home.z))
        m.persistent = true
        m.face(eye)
        g.mobs.mobs = [m]; g.mobs.rebuildIndex()
        let h0 = m.health
        var rounds = 0
        while m.health > 0 && rounds < 40 {
            m.face(eye); m.vel = .zero
            let aim = m.pos + V3(0, m.height * 0.55, 0)
            let dir = simd_normalize(aim - eye)
            g.arms.slugs.removeAll()
            g.arms.spawn(Slug(pos: eye, vel: dir * 120, kind: .bullet, damage: 4, fromPlayer: true, shooter: nil, by: "Player", life: 2, gravity: 0))
            for _ in 0..<30 where !g.arms.slugs.isEmpty { g.arms.update(1.0 / 60, g) }
            rounds += 1
        }
        check(m.health <= 0 && rounds <= 12,
              "brigandcheck: Falke rounds from the front drop a Brigand (\(h0) health) in \(rounds) (his guard turned every one)")
    }
}
