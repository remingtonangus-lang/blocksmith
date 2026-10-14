import Foundation
import simd

// D4 stagecoaches and freight wagons. A coach is a horse (Mob.coach: 1 a stagecoach, 2 a covered freight wagon)
// drawing the box behind it, its driver riding postilion. Three ways to meet one:
//   on the road   about one in three of the travellers Riders sends is a coach. Held up at gunpoint the driver throws
//                 down the strongbox (three times a rider's satchel) or the wagon's freight; a bigger crime, too.
//   a contract    town boards post "stage" contracts: ride guard on the stage to another town. The coach waits while
//                 you fall behind; road agents hit it half way. Paid when it rolls into town with its driver alive.
//   robbed        road agents on a stage contract go for the coach.
// The driver of a contract coach is Mob.posse `guarded` (not a rider, so not robbable while you guard it).
enum Stagecoach {
    static let guarded = 7
    static var chance: Float = 0.33                  // of the riders Riders.send puts on the road
    static let waitBeyond: Float = 26                // the coach stops while the player is further off than this

    static func isDriver(_ m: Mob) -> Bool { m.kind == .villager && m.posse == guarded }

    // MARK: Spawning

    // A coach and its driver at `at`, bound for `goal`.
    @discardableResult
    static func spawn(_ g: Game, at: V3, goal: V3, coach: UInt8, posse: Int, name: String? = nil) -> Mob? {
        let horse = Mob(.horse, at: at)
        if horse.collides(horse.pos, g.world) { return nil }
        horse.coach = coach
        horse.posse = posse
        horse.persistent = true
        let r = Mob(.villager, at: at + V3(0, horse.height * 0.8, 0))
        r.home = at
        Townsfolk.setup(r, game: g)
        if var v = r.villager { v.role = "driver"; v.locked = true; v.profession = "none"; r.villager = v }
        r.posse = posse
        r.persistent = true
        r.mount = horse
        r.customName = name
        r.patrolGoal = goal
        g.mobs.mobs.append(horse)
        g.mobs.mobs.append(r)
        return r
    }

    // MARK: The road (Riders.rob)

    // What a held-up coach gives up; nil for a lone rider.
    static func robbed(_ g: Game, _ m: Mob) -> (cash: Int, bounty: Int)? {
        guard let h = m.mount, h.coach != 0 else { return nil }
        let at = m.pos + V3(0, 0.5, 0)
        if h.coach == 1 {
            let cash = Rand.int(in: 30...90) * 100
            for (k, lo, hi) in [("gold_nugget", 4, 12), ("gold_ingot", 0, 2), ("paper", 1, 3)] where Items.has(k) {
                let n = Rand.int(in: lo...hi)
                if n > 0 { g.drops.spawn(ItemStack(Items.id(k), n), at: at) }
            }
            g.onToast?("The driver throws down the strongbox: \(Money.format(cash))")
            return (cash, Riders.robBounty * 2)
        }
        let cash = Rand.int(in: 5...15) * 100
        for (k, lo, hi) in [("wheat", 4, 12), ("iron_ingot", 1, 4), ("leather", 1, 4), ("bread", 2, 6), ("barrel", 0, 1)] where Items.has(k) {
            let n = Rand.int(in: lo...hi)
            if n > 0 { g.drops.spawn(ItemStack(Items.id(k), n), at: at) }
        }
        g.onToast?("The teamster cuts the freight loose: \(Money.format(cash)) and the load")
        return (cash, Riders.robBounty + Riders.robBounty / 2)
    }

    // MARK: Contracts ("stage")

    static func take(_ g: Game, _ c: inout Contract) -> Bool {
        guard let t = c.destAt else { return false }
        let at = g.world.freeSpawn(g.player.pos + V3(3, 0, 3))
        let goal = V3(Float(t[0]) + 0.5, Float(g.world.gen.column(t[0], t[1]).height + 1), Float(t[1]) + 0.5)
        guard spawn(g, at: at, goal: goal, coach: 1, posse: guarded, name: c.who) != nil else { return false }
        c.count = Int(simd_length(V2(Float(t[0]) - g.player.pos.x, Float(t[1]) - g.player.pos.z)))
        c.spawned = true
        return true
    }

    // Contracts.tick, once a second.
    static func tick(_ g: Game, _ board: String, _ slot: Int, _ c0: Contract) {
        var c = c0
        guard let t = c.destAt else { return }
        guard let d = g.mobs.mobs.first(where: { isDriver($0) && $0.customName == c.who }) else { return }
        if d.health <= 0 { fail(g, board, slot, &c); return }
        let goal = V3(Float(t[0]) + 0.5, Float(g.world.topY(t[0], t[1]) + 1), Float(t[1]) + 0.5)
        // Waits for the guard.
        d.patrolGoal = simd_length(d.pos - g.player.pos) > waitBeyond ? nil : goal
        if d.mount == nil, let h = g.mobs.mobs.first(where: { $0.kind == .horse && $0.coach != 0 && $0.posse == guarded
                                                               && simd_length($0.pos - d.pos) < 6 }) { d.mount = h }
        let left = simd_length(V2(goal.x - d.pos.x, goal.z - d.pos.z))
        if !c.ambushed, c.count > 0, left < Float(c.count) * 0.55 {
            c.ambushed = true; Contracts.save(board, slot, c)
            let side = simd_normalize(V3(goal.z - d.pos.z, 0, d.pos.x - goal.x) + V3(0.001, 0, 0))
            Contracts.bandits(g, near: d.pos + side * 14 + simd_normalize(V3(goal.x - d.pos.x, 0, goal.z - d.pos.z)) * 10, 4, "Road Agent")
            g.onToast?("Road agents! Keep the stage rolling")
        }
        if left < 30 {
            // Into town: driver and coach go on their way (and off the books).
            d.customName = nil
            d.posse = Riders.riding
            d.mount?.posse = Riders.riding
            d.patrolGoal = goal
            Contracts.pay(g, board, slot, &c)
        }
    }

    static func fail(_ g: Game, _ board: String, _ slot: Int, _ c: inout Contract) {
        c.failed = true
        Contracts.save(board, slot, c)
        g.onToast?("The stage is lost. The contract's off")
    }

    // Honour.mobDied (via TownBoard.mobDied): the driver of a guarded coach.
    static func mobDied(_ g: Game, _ m: Mob) {
        guard isDriver(m), let st = TownLaw.state.contracts else { return }
        for (key, c0) in st where c0.kind == "stage" && c0.taken && !c0.paid && !c0.failed && c0.who == m.customName {
            guard let (board, slot) = Contracts.split(key) else { continue }
            var c = c0
            fail(g, board, slot, &c)
        }
    }

    // MARK: Model (horseParts): the box behind the horse, in the horse's model space (1/16 block, head toward -z).

    static func parts(_ m: Mob, bob: Float) -> [Part] {
        let wood = V3(0.36, 0.24, 0.14), dark = V3(0.12, 0.09, 0.07), iron = V3(0.22, 0.22, 0.24)
        var p: [Part] = []
        p.reserveCapacity(24)
        // Shafts to the harness, and a collar strap over the shoulders.
        p.append(box(-5.4, 12 + bob, 2, 0.9, 0.9, 20, wood)); p.append(box(4.5, 12 + bob, 2, 0.9, 0.9, 20, wood))
        p.append(box(-5.5, 13 + bob, -6, 11, 1.2, 1.4, dark))
        p.append(box(-9, 9, 20, 18, 1.2, 1.5, wood))                                // splinter bar
        if m.coach == 1 {
            let paint = V3(0.46, 0.13, 0.1), trim = V3(0.82, 0.66, 0.24)
            p.append(box(-9, 11, 22, 18, 23, 28, paint, 4))                          // the body
            p.append(box(-10, 34, 21, 20, 1.6, 30, dark))                           // roof
            p.append(box(-7, 35.6, 27, 14, 4, 16, V3(0.48, 0.34, 0.2), 4))           // luggage under a tarp
            p.append(box(-9.2, 18, 22, 18.4, 1, 28, trim))                          // waist stripe
            for z: Float in [27, 39] {
                p.append(box(-9.25, 22, z, 0.3, 8, 8, dark)); p.append(box(8.95, 22, z, 0.3, 8, 8, dark))       // windows
            }
            p.append(box(-8, 24, 15, 16, 1.5, 7, wood)); p.append(box(-8, 25.5, 21, 16, 5, 1.2, wood))      // driver's box
            p.append(box(-2, 10, 50, 4, 4, 4, iron))                                // boot strap
        } else {
            let canvas = V3(0.9, 0.87, 0.78)
            p.append(box(-9, 10, 21, 18, 6, 31, wood, 4))                            // the bed
            p.append(box(-9.6, 16, 23, 19.2, 15, 27, canvas, 4))                     // the cover
            p.append(box(-8.5, 31, 24, 17, 2, 25, canvas))
            for z: Float in [23, 36, 49] { p.append(box(-9.8, 16, z, 19.6, 17, 1, wood)) }   // hoops
            p.append(box(-7, 14, 16, 14, 1.5, 5, wood))                              // seat
        }
        // Wheels: two crossed boxes each, turning as it rolls.
        let roll: Float = -m.walkPhase * 0.55
        for (z, r) in [(Float(27), Float(6.5)), (Float(46), Float(8))] {
            for x: Float in [-11.2, 9.8] {
                let pv = V3(x + 0.7, r, z)
                for k in 0..<2 {
                    let a = roll + Float(k) * .pi / 4
                    p.append(Part(mn: V3(x, 0, z - r * 0.92), mx: V3(x + 1.4, r * 2, z + r * 0.92), pivot: pv, rotX: a, color: wood))
                }
                p.append(box(x - 0.3, r - 1.2, z - 1.2, 2, 2.4, 2.4, iron))          // hub
            }
        }
        p.append(box(-10, 6, 26.5, 20, 1, 1, iron)); p.append(box(-10, 7.5, 45.5, 20, 1, 1, iron))   // axles
        return p
    }
}
