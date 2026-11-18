import Foundation
import simd

// Ledger 335 (Fable's queue, job 12): a Greywall troop train could not be destroyed. Its engine and troop cars took
// every round, rocket and shell and were made whole again each frame (Trains.drive); their hit box was a 4-block square
// at each car's middle, so most of a 13-block car let rounds through; only the guard car could be shot down, and then
// it went from the world as any dead mob and the train was built again whole the next second.
// Now on a troop train:
//   Damage    (a troop train's cars only) the engine (240), each troop car (160) and the guard car (160) keep what guns, rockets and shells take,
//             struck over the car's whole length and height (Mob.rayHit, Explosion: the blast reaches the car's nearest
//             point), never killed outright by a blast's inner half (plate); fists and blades glance off. Soldiers
//             riding a car are shielded by its plate from blasts outside it (an eighth of the blast, never outright).
//   Wrecked   a car brought to 0 is uncoupled: out of the train, off the rails a yard to one side, slewed and sunk on
//             its wheels, smoking for a minute and a half; its body (hull) stays where it lies, solid, its rounds and
//             blasts still stopped by it. Used, a wreck is searched once: the Greywall armoury's loot. It goes when its
//             chunk unloads.
//   Troops    those still aboard a wrecked car pile out on their own side of it, clear of its body, and fight.
//   The train any car wrecked stops it for good where it stands (the wreck lies across the line: no part of the train
//             runs on past it, nor back through it), the engine's too; no train runs that line again until the next day
//             (kept in the world's save).
// BS_OLDTROOPWRECK=1: as before.
enum TroopWrecks {
    static let old = Env.all["BS_OLDTROOPWRECK"] == "1"
    static var wrecks: [Mob] = []
    private static var ids: Set<ObjectIdentifier> = []
    private static var madeAt: [ObjectIdentifier: Double] = [:]
    static var down: [Int64: Int] = [:]          // a line's id -> the day its troop train was stopped for good
    static var made = 0, troopsOut = 0, stuckOut = 0, searched = 0      // (checks)
    static var outList: [Mob] = [], recordOut = false                  // (checks: the soldiers who climbed out)
    static var lastWreckMs: Double = 0                                  // (checks: the cost of the frame a car is wrecked)

    static func on(_ tr: Trains.Train) -> Bool { !old && MilitaryTrain.isTroopTrain(tr) }
    @inline(__always) static func isWreck(_ m: Mob) -> Bool { !ids.isEmpty && ids.contains(ObjectIdentifier(m)) }
    static func blocked(_ id: Int64, day: Int) -> Bool { !old && down[id] == day }

    // A troop train's car strength (Trains.buildBig).
    static func strength(_ v: Int) -> Int { v == Trains.armouredLoco ? 240 : 160 }

    // A real-size car of a train (or a wreck) is its armour: what Mob.hit and the blast take as plate.
    static func plated(_ m: Mob) -> Bool {
        guard !old, m.kind == .minecart, Trains.isBig(m), Trains.isCar(m) else { return false }
        if isWreck(m) { return true }
        guard let (tr, _) = Trains.carOf[ObjectIdentifier(m)] else { return false }
        return MilitaryTrain.isTroopTrain(tr)
    }

    // A rider of a troop train's car, inside its plate (Explosion: shielded from blasts outside it).
    static func shielded(_ m: Mob) -> Bool {
        guard !old, let mt = m.mount, Trains.isCar(mt), Trains.isBig(mt), let (tr, _) = Trains.carOf[ObjectIdentifier(mt)] else { return false }
        return MilitaryTrain.isTroopTrain(tr)
    }

    // A car's own frame: across (x, right), up (y) and along (z, toward its back).
    @inline(__always) static func local(_ m: Mob, _ p: V3) -> V3 {
        let w = p - m.pos, cy = cosf(m.yaw), sy = sinf(m.yaw)
        return V3(cy * w.x - sy * w.z, w.y, sy * w.x + cy * w.z)
    }
    @inline(__always) static func toWorld(_ m: Mob, _ u: V3) -> V3 {
        let cy = cosf(m.yaw), sy = sinf(m.yaw)
        return m.pos + V3(cy * u.x + sy * u.z, u.y, -sy * u.x + cy * u.z)
    }
    static func box(_ m: Mob) -> (V3, V3) {
        let hw = Trains.halfWidth(m), hl = Trains.halfLength(m)
        return (V3(-hw, -0.2, -hl), V3(hw, Trains.roofTop(m), hl))
    }

    // Mob.rayHit for a real-size car: its whole body, turned with it (a segment starting inside the car passes it).
    static func rayHit(_ m: Mob, _ o: V3, _ d: V3, maxDist: Float) -> Float? {
        let (mn, mx) = box(m)
        let lo = local(m, o)
        if lo.x > mn.x && lo.x < mx.x && lo.y > mn.y && lo.y < mx.y && lo.z > mn.z && lo.z < mx.z { return nil }
        let cy = cosf(m.yaw), sy = sinf(m.yaw)
        let ld = V3(cy * d.x - sy * d.z, d.y, sy * d.x + cy * d.z)
        guard let h = World.rayBox(lo, ld, mn, mx), h.0 >= 0, h.0 <= maxDist else { return nil }
        return h.0
    }

    // Explosion: the point of a car's body nearest a blast (its base: the blast measures from the middle of its height).
    static func nearest(_ m: Mob, to c: V3) -> V3 {
        let (mn, mx) = box(m)
        let l = local(m, c)
        let q = V3(max(mn.x, min(mx.x, l.x)), 0, max(mn.z, min(mx.z, l.z)))
        return toWorld(m, q)
    }

    // MARK: Wrecking

    // Mob.update for a rider whose mount is at 0: a troop train's car about to be wrecked (catchDeaths) keeps them.
    static func holdsRiders(_ mt: Mob) -> Bool {
        guard !old, mt.kind == .minecart, Trains.isBig(mt), let (tr, _) = Trains.carOf[ObjectIdentifier(mt)] else { return false }
        return on(tr)
    }

    // MobManager.update, before the deaths: a troop train's car brought to 0 is wrecked, not killed.
    static func catchDeaths(_ g: Game) {
        guard !old else { return }
        if !ids.isEmpty { for m in wrecks where m.health <= 0 { m.health = 1000 } }
        guard !Trains.carOf.isEmpty else { return }
        var hit: [(Trains.Train, Mob)] = []
        for m in g.mobs.mobs where m.health <= 0 && m.kind == .minecart && Trains.isBig(m) {
            if let (tr, _) = Trains.carOf[ObjectIdentifier(m)], on(tr) { hit.append((tr, m)) }
        }
        for (tr, m) in hit { wreck(g, tr, m) }
    }

    static func wreck(_ g: Game, _ tr: Trains.Train, _ m: Mob) {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer { lastWreckMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000 }
        guard let k = tr.cars.firstIndex(where: { $0 === m }) else { return }
        let id = ObjectIdentifier(m)
        let wasRider = g.riding === m
        if TrainGun.shared.car === m { TrainGun.shared.leave(g) }
        if wasRider { g.dismount() }
        // Uncoupled: out of the train (its other cars keep their places along it).
        tr.cars.remove(at: k)
        if k < tr.layout.count { tr.layout.remove(at: k) }
        if k < tr.carS.count { tr.carS.remove(at: k) }
        Trains.carOf[id] = nil
        for (j, c) in tr.cars.enumerated() { Trains.carOf[ObjectIdentifier(c)] = (tr, j) }
        // The train stops for good: no train on its line until the next day.
        tr.halted = true; tr.heldBy = true; tr.heldWay = 0; tr.brake = 1; tr.rate = 0; tr.driveV = 0; tr.roused = true
        let day = Int(g.time / DAY_LENGTH)
        down[tr.track.id] = day
        for (line, th) in Trains.throughOut where th == tr.track.id { down[line] = day }
        // Off the rails: away from him (or to the side its hash says), slewed and sunk on its wheels.
        let right = V3(cosf(m.yaw), 0, -sinf(m.yaw))
        let toHim = simd_dot(g.player.pos - m.pos, right)
        let side: Float = abs(toHim) > 0.5 ? (toHim > 0 ? -1 : 1) : (hash3(Int(m.pos.x), Int(m.pos.z), k, 0x3EC) & 1 == 0 ? 1 : -1)
        m.pos += right * side * 0.9 + V3(0, -0.35, 0)
        m.yaw += side * 0.1
        m.trainPitch *= 0.5
        m.vel = .zero
        m.health = 1000; m.hurt = 0
        m.walkPhase = 0
        if let s = TrainHulls.hull(m) {
            TrainHulls.pose(s, m, ahead: 0)
            s.prevPos = s.pos; s.prevRot = s.rot
            s.vel = .zero; s.angVel = .zero
            s.updateBounds()
        }
        wrecks.append(m); ids.insert(id); madeAt[id] = g.clock
        made += 1
        // Those still aboard climb out on their own side, clear of its body, and fight.
        for s in tr.troops where s.mount === m && s.health > 0 {
            let off = s.mountOffset ?? V3(1, 1.3, 0)
            let sd: Float = off.x < 0 ? -1 : 1
            let out = toWorld(m, V3(sd * (Trains.halfWidth(m) + 1.3), 0.4, max(-Trains.halfLength(m) + 1, min(Trains.halfLength(m) - 1, off.z))))
            s.mount = nil
            s.mountOffset = nil
            s.pos = g.world.freeSpawn(out)
            s.vel = .zero
            s.home = s.pos
            s.aggro = true
            s.persistent = true             // (out on the ground they are a fight, not passers-by: day's light cleared them in a second)
            troopsOut += 1
            if recordOut { outList.append(s) }
            if g.world.collides(V3(s.pos.x - s.halfW, s.pos.y, s.pos.z - s.halfW), V3(s.pos.x + s.halfW, s.pos.y + s.height, s.pos.z + s.halfW)) { stuckOut += 1 }
        }
        tr.troops.removeAll { $0.health <= 0 && $0.mount == nil }
        // He was aboard: beside it on the ground, out of its body.
        if wasRider || g.world.collides(V3(g.player.pos.x - 0.3, g.player.pos.y, g.player.pos.z - 0.3), V3(g.player.pos.x + 0.3, g.player.pos.y + 1.8, g.player.pos.z + 0.3)) {
            let near = simd_length(g.player.pos - m.pos) < Trains.halfLength(m) + 4
            if wasRider || near {
                let sd: Float = simd_dot(g.player.pos - m.pos, right) < 0 ? -1 : 1
                g.player.pos = g.world.freeSpawn(toWorld(m, V3(sd * (Trains.halfWidth(m) + 1.4), 0.4, 0)))
                g.player.vel = .zero
                g.player.airPeak = g.player.pos.y
            }
        }
        // The blow: fire and smoke at its middle, a crash of plate.
        let mid = m.pos + V3(0, 2, 0)
        g.sfx(.explodeSmall, 1.2, at: mid)
        g.sfx(.anvilLand, 0.7, at: mid)
        for _ in 0..<6 { g.particles.smoke(at: mid + V3(Rand.float(in: -1.5...1.5), Rand.float(in: 0...1.5), Rand.float(in: -1.5...1.5)), dark: true) }
        for _ in 0..<4 { g.particles.flame(at: mid + V3(Rand.float(in: -1...1), 0, Rand.float(in: -1...1))) }
        // (every car down: nothing left of the train to run)
        if tr.cars.isEmpty { Trains.remove(g, tr) }
    }

    // Mob.update for a wreck: it lies where it fell.
    @inline(__always) static func hold(_ m: Mob) {
        m.vel = .zero
        m.health = 1000
        m.hurt = 0
        m.onGround = true
    }

    // Once a second (Trains.tick): smoke while fresh; a wreck whose chunk unloaded goes, its body with it.
    static func tick(_ g: Game) {
        guard !ids.isEmpty else { return }
        var gone: [Mob] = []
        for m in wrecks {
            let id = ObjectIdentifier(m)
            let inWorld = g.mobs.mobs.contains { $0 === m }
            if !inWorld || !g.world.isLoaded(Int(floor(m.pos.x)), Int(floor(m.pos.z))) { gone.append(m); continue }
            if let t = madeAt[id], g.clock - t < 90, simd_length(m.pos - g.player.pos) < 160 {
                g.particles.smoke(at: m.pos + V3(Rand.float(in: -2...2), 3.2, Rand.float(in: -3...3)), dark: true)
            }
        }
        for m in gone { remove(g, m) }
    }

    static func remove(_ g: Game, _ m: Mob) {
        let id = ObjectIdentifier(m)
        ids.remove(id); madeAt[id] = nil
        wrecks.removeAll { $0 === m }
        if let s = TrainHulls.hullOf.removeValue(forKey: id) { g.world.ships.remove(s) }
        g.mobs.mobs.removeAll { $0 === m }
    }

    // A new world: none of the old one's wrecks.
    static func reset(_ g: Game?) {
        if let g { for m in wrecks { remove(g, m) } }
        wrecks = []; ids = []; madeAt = [:]
    }

    // Used: searched once (the Greywall armoury's loot), then a box like any other.
    static func search(_ g: Game, _ m: Mob) -> Bool {
        guard isWreck(m) else { return false }
        if m.cargo == nil {
            let c = ItemContainer(27)
            var rng = SRng(UInt64(hash3(Int(m.pos.x), Int(m.pos.y), Int(m.pos.z), UInt32(truncatingIfNeeded: m.variant &* 31 &+ Int(g.time / DAY_LENGTH)))))
            Loot.fill(c, table: DirectorEvents.lootTable(.greywall), rng: &rng)
            m.cargo = c
            searched += 1
        }
        g.sfx(.armorEquip(0), 0.6, at: m.pos)
        g.openMenu(ChestMenu(game: g, container: m.cargo!, title: "Wrecked " + (m.customName ?? "Car")))
        return true
    }
}
