import Foundation
import simd

// P471 (Oct 26 20:14: "pretty well everywhere, whether or not the enemy shot at me was hit and miss, making it somewhat
// frustrating") probe, `questcheck --fireprobe`: a hostile soldier of each rank and side, unaware, with the player
// standing in the open in front of him or behind his back, 12 and 35 blocks off: does he fire, how soon, does it land.
enum FireProbeCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let home = g.player.pos
        _ = w.loadSync(center: home, radius: 4)
        let mobs0 = g.mobs.mobs, pos0 = g.player.pos, fly0 = g.player.flying, surv0 = g.survival
        let px = Int(floor(home.x)), pz = Int(floor(home.z))
        var top = 0
        for dz in stride(from: -12, through: 12, by: 4) { for dx in stride(from: -6, through: 44, by: 4) { top = max(top, w.topY(px + dx, pz + dz)) } }
        let y = min(CH - 12, top + 20)
        var placed: [(IVec3, BlockID)] = []
        for dz in -12...12 { for dx in -6...44 {
            for yy in y...(y + 4) {
                let want = yy == y ? STONE : AIR
                let b = w.block(px + dx, yy, pz + dz)
                if b != want { placed.append((IVec3(px + dx, yy, pz + dz), b)); w.setBlock(px + dx, yy, pz + dz, want) }
            }
        } }
        defer {
            for (p, b) in placed.reversed() { w.setBlock(p.x, p.y, p.z, b) }
            g.mobs.mobs = mobs0; g.mobs.rebuildIndex(); g.arms.slugs.removeAll(); g.player.pos = pos0; g.player.flying = fly0
            g.survival = surv0; Game.onDamage = nil
        }
        g.survival = true; g.alive = true; g.paused = false; g.menu = nil
        let stand = V3(Float(px) + 0.5, Float(y + 1), Float(pz) + 0.5)
        var misses: [String] = []
        var rows = 0
        for side in ["", "@grey", "@ash"] {
            for rank in ["soldier_recruit", "soldier_trooper", "soldier_marksman", "soldier_ironclad", "soldier_officer"] {
                for dist in [12, 35] {
                    for facing in [true, false] {
                        let at = stand + V3(Float(dist), 0, 0)
                        guard let m = Mob.structureMob(rank + side, at: at) else { continue }
                        m.yaw = facing ? -.pi / 2 + .pi : -.pi / 2         // (yaw -pi/2 looks +x: away from him)
                        m.home = at
                        g.mobs.mobs = [m]; g.mobs.rebuildIndex()
                        g.arms.slugs.removeAll()
                        let b = m.soldierBrain
                        var fired = 0, first: Float = -1, hurt = 0, seen = 0, mag = b.mag
                        Game.onDamage = { amt, _ in hurt += amt }
                        g.player.flying = false
                        for i in 0..<(10 * 60) {
                            g.player.pos = stand; g.player.vel = .zero
                            g.health = 20; g.alive = true
                            g.tick(1.0 / 60)
                            if b.mag < mag { fired += mag - b.mag; if first < 0 { first = Float(i) / 60 } }
                            mag = b.mag
                            if b.sees { seen += 1 }
                        }
                        Game.onDamage = nil
                        let allied = g.repAllied(m)
                        let line = String(format: "fireprobe: %@%@ at %d, %@: fired %d (first at %.1f s), %d damage, saw him %d/600, aggro %@, allied %@, at %.1f %.1f",
                                          rank, side.isEmpty ? "@capital" : side, dist, facing ? "facing him" : "back turned",
                                          fired, first, hurt, seen, m.aggro ? "y" : "n", allied ? "y" : "n", m.pos.x - stand.x, m.pos.y - stand.y)
                        print(line)
                        rows += 1
                        if !allied && (first < 0 || first > 6) { misses.append("\(rank)\(side) \(dist) \(facing ? "front" : "back")") }
                    }
                }
            }
        }
        check(misses.isEmpty, "fireprobe: every hostile soldier of \(rows) fires on him in the open within 6 s (\(misses.count) didn't: \(misses.joined(separator: "; ")))")
    }
}
