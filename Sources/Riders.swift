import Foundation
import simd

// P51 riders (see Roads.swift): now and then a traveller on horseback rides a road near the player, from one town
// toward the next. Point a gun at one (inside 16 blocks, in sight) and they rein in, put their hands up and throw
// down their satchel (cash and a few goods); killing one is murder. Either way it is a crime: honour falls, the
// nearest town puts a price on you and sends a posse of armed townsfolk after you (they ride off once the bounty is
// paid, as bounty hunters do: BountyHunters.leave). Riders are Mob.posse 5 (6 once robbed), the posse 3 like
// hunters, so killing either is no further crime (Honour.mobDied).
enum Riders {
    static let riding = 5, robbed = 6
    static var chancePerSecond: Float = 1.0 / 120   // near a road, about once every two minutes
    static let robHold: Float = 1.2                 // seconds of aim before the satchel comes down
    static let robBounty = 2500                     // $25 on your head in the nearest town
    static let murderBounty = 6000
    static var forceRoad: (Roads.Seg, Float)?       // the host check's road and spot
    static var along: ClosedRange<Float> = 50...80  // how far along the road from the player a rider turns up

    // The traveller (not their horse, which carries posse 5 too while ridden).
    static func isRider(_ m: Mob) -> Bool { m.kind == .villager && (m.posse == riding || m.posse == robbed) }

    // Once a second (TownLaw.tick's slot).
    static func tick(_ g: Game) {
        let p = g.player.pos
        // Riders out of range, or arrived, ride off.
        // A horse whose rider is gone is just a saddled horse (yours to take).
        for h in g.mobs.mobs where h.kind == .horse && h.posse == riding
            && !g.mobs.mobs.contains(where: { isRider($0) && $0.health > 0 && $0.mount === h }) { h.posse = 0 }
        g.mobs.mobs.removeAll { m in
            guard isRider(m) || (m.kind == .horse && m.posse == riding) else { return false }
            if simd_length(m.pos - p) > 160 { return true }
            // Unhorsed or without a destination (a reload drops both): nowhere to ride, so they leave once out of the way.
            if isRider(m) && (m.mount == nil || m.patrolGoal == nil) && simd_length(m.pos - p) > 40 { return true }
            if let goal = m.patrolGoal, simd_length(V2(goal.x - m.pos.x, goal.z - m.pos.z)) < 6, simd_length(m.pos - p) > 40 { return true }
            return false
        }
        guard Roads.on || forceRoad != nil, g.dim.dim == .overworld, g.difficulty > 0, TownLaw.inTown == nil,
              !g.mobs.mobs.contains(where: { isRider($0) && $0.mount != nil }), Rand.float(in: 0..<1) < chancePerSecond else { steer(g); return }
        _ = send(g)
        steer(g)
    }

    // Keeps mounted riders on the road's bends: a waypoint 10 blocks along it toward their goal (Mob.wanderGoal,
    // which riders don't otherwise use); off any road they head straight for the goal.
    static func steer(_ g: Game) {
        guard let gen = g.world.gen as? WorldGen else { return }
        for m in g.mobs.mobs where isRider(m) && m.mount != nil {
            guard let goal = m.patrolGoal else { m.wanderGoal = nil; continue }
            let road = forceRoad.map { f in (f.0, Roads.distance(f.0, V2(m.pos.x, m.pos.z))) }
                ?? Roads.nearest(gen, to: m.pos, range: 10).map { n in (n.0, Roads.distance(n.0, V2(m.pos.x, m.pos.z))) }
            guard let (s, (d, t)) = road, d < 10 else { m.wanderGoal = nil; continue }
            let ab = s.b - s.a, len = max(1, simd_length(ab))
            let sign: Float = simd_dot(V2(goal.x - m.pos.x, goal.z - m.pos.z), ab) >= 0 ? 1 : -1
            let tw = max(0, min(1, t + sign * 10 / len))
            let w = Roads.point(s, tw)
            m.wanderGoal = (tw == 0 || tw == 1) ? nil : V3(w.x, m.pos.y, w.y)
        }
    }

    // A rider on the nearest road 50-80 blocks along it from the player, heading for the end past the player.
    @discardableResult
    static func send(_ g: Game) -> Mob? {
        guard let gen = g.world.gen as? WorldGen else { return nil }
        let road: (Roads.Seg, Float)
        if let f = forceRoad { road = f }
        else if let n = Roads.nearest(gen, to: g.player.pos, range: 48) { road = (n.0, n.1) }
        else { return nil }
        let (s, t0) = road
        let len = max(1, simd_length(s.b - s.a))
        let ahead = Rand.bool()
        let t = max(0, min(1, t0 + (ahead ? 1 : -1) * Rand.float(in: along) / len))
        let at2 = Roads.point(s, t)
        let x = Int(floor(at2.x)), z = Int(floor(at2.y))
        guard g.world.isLoaded(x, z) else { return nil }
        let y = g.world.topY(x, z) + 1
        guard !Blocks.isLiquid(g.world.block(x, y - 1, z)) else { return nil }
        let at = g.world.freeSpawn(V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
        let horse = Mob(.horse, at: at)
        if horse.collides(horse.pos, g.world) { return nil }
        horse.saddled = true
        horse.posse = riding
        horse.persistent = true
        let r = Mob(.villager, at: at + V3(0, horse.height * 0.8, 0))
        r.home = at
        Townsfolk.setup(r, game: g)
        if var v = r.villager { v.role = "rider"; v.locked = true; v.profession = "none"; r.villager = v }
        r.posse = riding
        r.persistent = true
        r.mount = horse
        let end = t > t0 ? s.a : s.b                   // the end on the far side of the player
        let goalY = Float(g.world.gen.column(Int(end.x), Int(end.y)).height + 1)
        r.patrolGoal = V3(end.x, goalY, end.y)
        g.mobs.mobs.append(horse)
        g.mobs.mobs.append(r)
        return r
    }

    // The rider's own AI (Mob.update, villagers): ride for the goal; a gun on them stops them, and held long enough
    // they throw down the satchel and ride off the other way.
    static func step(_ m: Mob, _ dt: Float, _ g: Game) -> Float {
        m.town.handsUp = max(0, m.town.handsUp - dt)
        if m.posse == riding, aimedAt(m, g) {
            m.town.heldUp += dt
            m.town.handsUp = 1
            m.face(g.player.pos)
            if m.town.heldUp >= robHold { rob(m, g) }
            return 0
        }
        if m.town.handsUp > 0 { return 0 }
        m.town.heldUp = max(0, m.town.heldUp - dt)
        guard let goal = m.patrolGoal else { return 0 }
        // Follow the road toward the goal (the waypoint `steer` sets), else straight for it.
        if let w = m.wanderGoal, simd_length(V2(w.x - m.pos.x, w.z - m.pos.z)) > 2 { m.face(w) } else { m.face(goal) }
        return m.posse == robbed ? 4.5 : 2.6                    // a trot; robbed riders gallop off
    }

    static func aimedAt(_ m: Mob, _ g: Game) -> Bool {
        guard g.alive, Guns.index(g.held.item) != nil else { return false }
        // The line the gun points along: the hand's ray in VR, the view on a screen.
        let from = g.vrAim?.origin ?? g.player.eye, dir = simd_normalize(g.vrAim?.dir ?? g.player.look)
        let to = m.eye - from
        let d = simd_length(to)
        guard d > 0.5, d < 16 else { return false }
        return simd_dot(to / d, dir) > 0.995 && g.world.canSee(from, m.eye)
    }

    static func rob(_ m: Mob, _ g: Game) {
        m.posse = robbed
        m.town.handsUp = 1.5
        let cash = Rand.int(in: 8...30) * 100
        g.money += cash
        for (k, lo, hi) in [("bread", 1, 3), ("gold_nugget", 2, 7), ("arrow", 0, 6), ("apple", 0, 2)] where Items.has(k) {
            let n = Rand.int(in: lo...hi)
            if n > 0 { g.drops.spawn(ItemStack(Items.id(k), n), at: m.pos + V3(0, 0.5, 0)) }
        }
        TownVoice.speak(g, m, .handsup)
        g.onToast?("The rider throws down their satchel: \(Money.format(cash))")
        // Turn back the way they came.
        if let goal = m.patrolGoal, let h = m.mount { m.patrolGoal = h.pos * 2 - goal; m.wanderGoal = nil }
        crime(g, at: m.pos, bounty: robBounty, honour: -10, why: "robbed a rider")
    }

    // Honour.mobDied for a rider the player killed.
    static func killed(_ g: Game, _ m: Mob) {
        crime(g, at: m.pos, bounty: murderBounty, honour: -25, why: "murdered a rider")
    }

    static func crime(_ g: Game, at p: V3, bounty: Int, honour: Float, why: String) {
        guard g.survival else { return }
        let town = Townsfolk.town(g, at: p)
        Honour.change(g, honour, why)
        Honour.addBounty(g, town, bounty)
        sendPosse(g, from: town)
    }

    // A posse of three armed townsfolk from `town`, out of sight 26-34 blocks off, after the player.
    @discardableResult
    static func sendPosse(_ g: Game, from town: String) -> Int {
        let w = g.world
        var placed = 0
        for k in 0..<30 where placed < 3 {
            let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 26...34)
            let x = Int(floor(g.player.pos.x + sinf(a) * r)), z = Int(floor(g.player.pos.z + cosf(a) * r))
            guard w.isLoaded(x, z) else { continue }
            let y = w.topY(x, z) + 1
            guard !Blocks.isLiquid(w.block(x, y - 1, z)) else { continue }
            let at = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            if k < 20 && w.canSee(at + V3(0, 1.6, 0), g.player.eye) { continue }
            let m = gunman(g, at: w.freeSpawn(at), role: "posse", name: "\(town) Posse")
            if m.collides(m.pos, w) { continue }
            if var v = m.villager { v.town = town; m.villager = v }
            g.mobs.mobs.append(m)
            placed += 1
        }
        if placed > 0 { g.onToast?("\(town) has sent a posse after you"); g.sfx(.goatHorn, 0.6) }
        return placed
    }

    // An armed townsperson with a six-iron, angry at the player (bounty hunters and posses: posse 3).
    static func gunman(_ g: Game, at p: V3, role: String, name: String) -> Mob {
        let m = Mob(.villager, at: p)
        m.home = p
        Townsfolk.setup(m, game: g)
        if var v = m.villager { v.role = role; v.locked = true; v.profession = "none"; m.villager = v }
        m.customName = name
        m.posse = 3; m.posseSince = g.clock
        m.persistent = true
        m.town.anger = 30
        m.lockTime = 30
        m.health = m.spec.health * 5 / 4
        return m
    }
}
