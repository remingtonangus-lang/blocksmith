import Foundation
import simd

// P471 (Oct 26 19:42-20:14) checks, `questcheck --navalblow`: a crew's heavy naval shell bursting on and near the
// player takes a heavy share on Normal (up to 9 hearts, past the level's 5-heart cap on one blow) and its full share
// on Hard and Very Hard; a shell armed as the crews now arm theirs breaches a Capital stone wall as his own does.
enum NavalBlowCheck {
    static func crewShell(at p: V3) -> Slug {
        var s = Slug(pos: p, vel: V3(260, 0, 0), kind: .shell, damage: 0, fromPlayer: false, shooter: nil, by: "Capital Naval Gun", life: 3.5, gravity: 0)
        HeavyTurret.arm(&s)
        s.power = HeavyTurret.mannedPower; s.breach = HeavyTurret.mannedBreach      // (as Soldiers' crews arm a heavy shell)
        return s
    }

    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let a = PlaytestOct12Tests.arena(g, dx: -90, dz: 90, r: 12)
        defer { a.restore(); g.drops.items.removeAll(); g.arms.breaches.removeAll() }
        g.survival = true
        let feet = V3(Float(a.fx) + 0.5, Float(a.py) + 1, Float(a.fz) + 0.5)
        var taken: [Int: [Int]] = [:]
        for level in [3, 4, 5] {
            g.diffLevel = level
            for d: Float in [1, 4, 8] {
                g.health = 20; g.alive = true; g.player.pos = feet; g.player.vel = .zero
                g.levelSecond = -10
                g.lastHurtAt = -100; g.lastHurtAmount = 0      // (each burst a fresh hit, not the cooldown's remainder)
                g.arms.detonate(crewShell(at: feet + V3(d, 0.5, 0)), at: feet + V3(d, 0.5, 0), g)
                taken[level, default: []].append(g.alive ? 20 - g.health : 20)
                g.arms.breaches.removeAll()
            }
        }
        g.diffLevel = 3; g.health = 20; g.alive = true
        let n = taken[3] ?? [], h = taken[4] ?? [], vh = taken[5] ?? []
        print("navalblow: half-hearts taken at 1, 4, 8 blocks: Normal \(n), Hard \(h), Very Hard \(vh)")
        check(n.count == 3 && n[0] >= 16 && n[0] <= 18 && n[1] >= 12 && h[0] >= 20 && vh[0] >= 20 && n[2] < n[0] && h.indices.allSatisfy { h[$0] >= n[$0] } && vh.indices.allSatisfy { vh[$0] >= h[$0] },
              "P471: a crew's heavy shell takes \(n[0]) half-hearts at a block on Normal (cap 18), \(n[1]) at 4, \(n[2]) at 8; Hard \(h), Very Hard \(vh)")
        // Its breach through 3-thick Capital stone (the crews' shells used to bounce off their own walls).
        let w = g.world, stone = Blocks.has("capital_stone") ? Blocks.id("capital_stone") : STONE
        var placed: [IVec3] = []
        defer { for q in placed { w.setBlock(q.x, q.y, q.z, AIR) } }
        let x0 = a.fx + 2
        for z in (a.fz - 6)...(a.fz + 6) { for y in (a.py + 1)...(a.py + 5) { for x in x0...(x0 + 2) { w.setBlock(x, y, z, stone); placed.append(IVec3(x, y, z)) } } }
        g.player.pos = feet - V3(40, 0, 0)
        let at = V3(Float(x0) - 0.3, Float(a.py) + 3.5, Float(a.fz) + 0.5)
        g.arms.detonate(crewShell(at: at), at: at, g)
        var frames = 0
        while !g.arms.breaches.isEmpty && frames < 200 { NavalGuns.stepBreaches(g); frames += 1 }
        let gone = placed.filter { w.block($0.x, $0.y, $0.z) != stone }.count
        let through = (x0...(x0 + 2)).allSatisfy { w.block($0, a.py + 3, a.fz) != stone }
        check(gone >= 80 && through, "P471: a crew's heavy shell breaches Capital stone as his does: \(gone) of \(placed.count) blocks of a 3-thick wall, through \(through)")
    }
}
