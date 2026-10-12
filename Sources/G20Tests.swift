import Foundation
import simd

// G20 (the Oct 11 content audit): the original designs that replaced reference copies are built, and hold what each
// promises. Each is built chunk by chunk into scratch columns over its whole box, as the world generator does.
enum G20Tests {
    struct Built { var count: [String: Int] = [:]; var mobs: [String] = []; var spawners: [String] = [] }

    static func build(_ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int, _ f: (inout StructWriter) -> Void) -> Built {
        var out = Built()
        for cz in floorDiv(z0, CS)...floorDiv(z1, CS) { for cx in floorDiv(x0, CS)...floorDiv(x1, CS) {
            var b = [BlockID](repeating: STONE, count: CS * CS * CH)
            for i in (CS * CS * 120)..<(CS * CS * CH) { b[i] = AIR }      // stone to y 120, air above
            b.withUnsafeMutableBufferPointer { buf in
                var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
                f(&w)
                for (_, be) in w.entities where !be.mob.isEmpty { out.spawners.append(be.mob) }
                out.mobs += w.mobs.map { $0.0 }
            }
            for v in b { out.count[Blocks.key(Blocks.groupBase[Int(v)]), default: 0] += 1 }
        } }
        return out
    }

    static func run(_ check: (Bool, String) -> Void) {
        let a = build(-31, -16, 31, 16) { SealedArmoury.build(&$0, 0, 50, 0, 7) }
        check(a.spawners.count >= 5 && a.count["chest", default: 0] >= 4 && a.count["bulkhead_door", default: 0] >= 8 && a.count["target", default: 0] >= 4,
              "G20 \(SealedArmoury.name): \(a.spawners.count) spawners (\(Set(a.spawners).sorted().joined(separator: ", "))), \(a.count["chest", default: 0]) chests, \(a.count["bulkhead_door", default: 0] / 2) bulkhead doors, \(a.count["target", default: 0]) targets")
        let r = build(-23, -23, 23, 23) { BrigandRoost.build(&$0, 0, 130, 0, 7) }
        let gang = r.mobs.filter { ["vindicator", "pillager"].contains($0) }.count
        check(gang >= 6 && r.mobs.filter { $0 == "horse" }.count == 2 && r.count["chest", default: 0] >= 2 && r.count["ladder", default: 0] >= 10,
              "G20 \(BrigandRoost.name): a gang of \(gang), \(r.mobs.filter { $0 == "horse" }.count) horses, \(r.count["chest", default: 0]) chests, \(r.count["ladder", default: 0]) ladder blocks")
        let d = build(-31, -8, 31, 8) { SunkenDreadnought.build(&$0, 0, SEA - 26, 0, 7) }
        check(d.count["gold_block", default: 0] >= 4 && d.mobs.filter { $0 == "drowned" }.count >= 6 && !d.mobs.contains("elder_guardian") && d.count["chest", default: 0] >= 2,
              "G20 \(SunkenDreadnought.name): \(d.count["gold_block", default: 0]) gold blocks, \(d.mobs.filter { $0 == "drowned" }.count) drowned, no elder spikefish, \(d.count["chest", default: 0]) chests")
        var rng = SRng(99)
        let fs = Fortress.layout(&rng, originX: 8, originZ: 8, base: 0, foundry: true)
        var f = Built()
        for p in fs.pieces {
            let one = build(p.min.x, p.min.z, p.max.x, p.max.z) { p.build(&$0) }
            for (k, v) in one.count { f.count[k, default: 0] += v }
            f.spawners += one.spawners
        }
        check(f.count["steel_plating", default: 0] > 100 && f.count["nether_bricks", default: 0] == 0 && f.spawners.contains("blaze"),
              "G20 \(AshFoundry.name): \(fs.pieces.count) cells, \(f.count["steel_plating", default: 0]) steel plate, no ember brick (\(f.count["nether_bricks", default: 0])), cinderwisp cages (\(f.spawners.filter { $0 == "blaze" }.count))")
        let m = build(-22, -22, 22, 22) { BoarlingMound.build(&$0, ox: 0, oz: 0, y: 60, seed: 7) }
        check(m.count["gold_block", default: 0] >= 5 && m.mobs.contains("piglin_brute") && m.mobs.filter { $0 == "piglin" }.count >= 4 && m.count["chest", default: 0] >= 5,
              "G20 \(BoarlingMound.name): \(m.count["gold_block", default: 0]) gold blocks in the hoard, \(m.mobs.filter { $0 == "piglin" }.count) boarlings and brutes, \(m.count["chest", default: 0]) chests")
    }
}

extension G20Tests {
    // G5: an Ashguard sharpshooter's scope glints for 1.1 s before its first shot at a target, then fires as usual.
    static func glint(_ g: Game, _ check: (Bool, String) -> Void) {
        let p = g.player.pos
        let at = V3(p.x + 30, p.y + 40, p.z)                 // in the air, a clear line to a spot beside it
        let m = Mob(.soldierMarksman, at: at)
        m.faction = Faction.ashguard.rawValue
        let b = m.soldierBrain
        b.gun = Guns.kessel; b.mag = 10; b.react = 0; b.reload = 0; b.shotTimer = 0
        let gs = Guns.all[b.gun], target = at + V3(-20, 0, 0)
        var firstAt: Float = -1, t: Float = 0
        let arms0 = g.arms.slugs.count
        while t < 3 && firstAt < 0 {
            m.soldierFire(0.05, g, b, gs, rank: 2, dist: 20, target: target)
            t += 0.05
            if b.mag < 10 { firstAt = t }
        }
        let mag1 = b.mag
        b.shotTimer = 0
        m.soldierFire(0.05, g, b, gs, rank: 2, dist: 20, target: target)
        let second = b.mag < mag1
        g.arms.slugs.removeSubrange(arms0..<g.arms.slugs.count)
        check(firstAt >= 1.1 && firstAt < 1.4 && second && b.glinted,
              String(format: "G5 sharpshooter glint: the first shot after %.2f s of glint, the next with none (%@)", firstAt, second ? "fired" : "held"))
    }
}
