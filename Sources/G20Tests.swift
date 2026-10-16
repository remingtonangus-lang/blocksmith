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

    // G16: a Powderwight that starts to swell is killed by an iron sword swung at its own pace before it
    // goes off. G14: the first emerald carried says where it sells.
    static func powderwightAndEmerald(_ g: Game, _ check: (Bool, String) -> Void) {
        let m = Mob(.creeper, at: g.player.pos + V3(2, 0, 0))
        let sword = Items.def(Items.id("iron_sword")), blow = sword.attack
        var t: Float = 0, next: Float = 0, blows = 0
        m.fuse = 0
        while m.health > 0 && m.fuse < Mob.hisserFuse && t < 6 {
            if t >= next { m.hit(from: g.player.pos, damage: Int(blow)); blows += 1; next += 1 / sword.attackSpeed }
            m.fuse += 0.05                                      // swelling all the while (it never backs off)
            t += 0.05
        }
        // (Each blow also sets its fuse back, so the fuse alone can't fail: the kill must come within one plain fuse.)
        check(m.health <= 0 && m.fuse < Mob.hisserFuse && t < Mob.hisserFuse && blows <= 3,
              String(format: "G16 Powderwight: %d iron-sword blows of %.0f kill it at %.2f s with its fuse at %.2f of %.2f s", blows, blow, t, m.fuse, Mob.hisserFuse))
        let survival0 = g.survival, tip0 = TownLaw.state.exchangeTip, held0 = g.inventory.main[g.selected], toast0 = g.onToast
        let town0 = TownLaw.inTown
        var said: [String] = []
        g.onToast = { said.append($0) }
        defer { g.survival = survival0; TownLaw.state.exchangeTip = tip0; g.inventory.main[g.selected] = held0; g.onToast = toast0; TownLaw.inTown = town0 }
        g.survival = true; TownLaw.state.exchangeTip = nil
        TownLaw.inTown = "Test Town"                      // (R20: the hint waits until you carry emeralds in a town)
        g.inventory.main[g.selected] = ItemStack(Items.id("emerald"), 1)
        TownLaw.emeraldTip(g); TownLaw.emeraldTip(g)
        // P328 (NO TEXT): the tip is never said now; the counters' Exchange rows and the EXCHANGE sign show it.
        check(said.isEmpty && TownLaw.state.exchangeTip == true,
              "G14 emeralds: the first one carried in a town says nothing (\"\(said.first ?? "nothing")\") and marks the tip seen")
    }

    // T1: an angry townsperson's swing reaches the player's real body (Game.meleeGap) like a monster's: level ground and a
    // one-block step yes; a player on a pillar over them or up a two-block step, no.
    static func townsMelee(_ g: Game, _ check: (Bool, String) -> Void) {
        let p0 = g.player.pos, alive0 = g.alive, survival0 = g.survival, health0 = g.health, mobs0 = g.mobs.mobs
        let force0 = TownLaw.forceTown, head0 = g.vrHead, menu0 = g.menu
        defer {
            g.player.pos = p0; g.alive = alive0; g.survival = survival0; g.health = health0; g.mobs.mobs = mobs0
            TownLaw.forceTown = force0; g.vrHead = head0; g.menu = menu0
        }
        g.alive = true; g.survival = true; g.vrHead = nil; TownLaw.forceTown = true
        let base = V3(p0.x, p0.y + 30, p0.z)
        let m = Mob(.villager, at: base); m.home = base
        Townsfolk.setup(m, tag: "shop_blacksmith", game: g)
        g.mobs.mobs = [m]
        func swings(_ off: V3) -> Bool {
            g.player.pos = base + off; g.health = 20
            m.pos = base; m.attackCooldown = 0; m.town.anger = 5; m.town.foe = nil; m.town.think = 1
            _ = m.townDefend(0.05, g)
            return m.attackCooldown > 0
        }
        let level = swings(V3(1.6, 0, 0)), step1 = swings(V3(1.2, 1, 0)), pillar = swings(V3(0.3, 2.2, 0)), step2 = swings(V3(1.2, 2, 0))
        check(m.townWeapon != .none && level && step1 && !pillar && !step2,
              "T1 townsfolk melee: a \(m.townWeapon.name) swing reaches the player on level ground (\(level)) and a one-block step (\(step1)), not on a pillar over them (\(pillar)) or up a two-block step (\(step2))")
    }
}
