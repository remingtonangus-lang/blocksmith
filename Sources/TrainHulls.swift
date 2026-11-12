import Foundation
import simd

// FAILURES 3 (Nov 2 08:40-08:41, a passenger train at Gold Valley: "can get in the passenger carts here, but... there's
// no passengers, and I am glitching through this section"; "I should be able to jump on top of this section"; "I can't
// seem to drive the train now"): a real-size train's cars were drawn models with a roof and an aisle floor faked under
// him (TrainRoofs): he walked through their sides and ends, fell through a roof he came down on from above, and with a
// gun in his hand the use press on the engine fired it.
// Now every real-size car carries a body: a kinematic hull of invisible blocks shaped to its model (the coach's and
// troop car's floor, sides, ends with their doorways and roof; the engine's boiler, running boards and open-backed cab;
// the other cars solid to their roof or load), held to the car's place on the track every frame. He walks in it, stands
// on its roofs and is carried, through the ship frame as aboard any vehicle; bullets, sight and blasts pass it (the cars'
// own models take the hits as before). The engine answers the use press with a gun out. The coaches carry townsfolk.
// BS_TRAINHULLS=0: the old way.
enum TrainHulls {
    static let on = ProcessInfo.processInfo.environment["BS_TRAINHULLS"] != "0"
    static let role = "traincar"
    static var hullOf: [ObjectIdentifier: Ship] = [:]
    static var built = 0                                     // (checks)

    // MARK: Cells (a code per cell: a slab of a height, or the parts of a walk-in car's cell)

    static let F: UInt16 = 1, W: UInt16 = 2, E: UInt16 = 4, N: UInt16 = 8, S: UInt16 = 16, LN: UInt16 = 32, LS: UInt16 = 64
    static let R: UInt16 = 128, F2: UInt16 = 256
    static let slab: UInt16 = 0x8000                         // | height in sixteenths (16: the full block)

    // The boxes (sixteenths) of a code: F the floor (a quarter block), F2 the cab's footplate, W and E the sides (x),
    // N and S the ends (z), LN and LS a doorway's lintel, R the roof at the top of the cell.
    static func boxes(_ c: UInt16) -> [Box] {
        if c & slab != 0 { return [Box(0, 0, 0, 16, Int(c & 31), 16)] }
        var b: [Box] = []
        if c & F != 0 { b.append(Box(0, 0, 0, 16, 4, 16)) }
        if c & F2 != 0 { b.append(Box(0, 0, 0, 16, 11, 16)) }
        if c & W != 0 { b.append(Box(0, 0, 0, 2, 16, 16)) }
        if c & E != 0 { b.append(Box(14, 0, 0, 16, 16, 16)) }
        if c & N != 0 { b.append(Box(0, 0, 0, 16, 16, 2)) }
        if c & S != 0 { b.append(Box(0, 0, 14, 16, 16, 16)) }
        if c & LN != 0 { b.append(Box(0, 4, 0, 16, 16, 2)) }
        if c & LS != 0 { b.append(Box(0, 4, 14, 16, 16, 16)) }
        if c & R != 0 { b.append(Box(0, 14, 0, 16, 16, 16)) }
        return b
    }

    static let variants = [Trains.loco, Trains.tender, Trains.coach, Trains.express, Trains.boxcar, Trains.tankWagon, Trains.flatcar,
                           Trains.troopCar, Trains.armouredLoco, Trains.gunCar]

    // A car's cells: 3 across (x, the model's -1.5 ... 1.5), its length (z, the model's front at 0), rows up from the
    // rail's top. Index x + z * 3 + y * 3 * sz.
    static func cells(_ v: Int) -> (sz: Int, sy: Int, codes: [UInt16]) {
        let half = Trains.halfUnits(v) * Trains.bigScale / 16
        let sz = max(2, Int((2 * half).rounded(.up)))
        let top = Trains.roofTop(variant: v)
        let rows = Int(top), frac = Int(((top - Float(rows)) * 16).rounded())
        let sy = rows + (frac > 0 ? 1 : 0)
        var c = [UInt16](repeating: 0, count: 3 * sz * max(sy, 5))
        func set(_ x: Int, _ y: Int, _ z: Int, _ code: UInt16) { c[x + z * 3 + y * 3 * sz] = code }
        func solidTo(_ top: Float, x: ClosedRange<Int> = 0...2, z: ClosedRange<Int>) {
            let r = Int(top), f = Int(((top - Float(r)) * 16).rounded())
            for zz in z { for xx in x {
                for y in 0..<r { set(xx, y, zz, slab | 16) }
                if f > 0 { set(xx, r, zz, slab | UInt16(f)) }
            } }
        }
        switch v {
        case Trains.coach, Trains.troopCar:
            // Floor 1.25 over the underframe, sides the full height, an end at each end with its doorway in the middle,
            // the roof over it all (the coach's on top of the fourth row, the troop car's in it).
            solidTo(1, z: 0...(sz - 1))
            for z in 0..<sz {
                let end: UInt16 = z == 0 ? N : (z == sz - 1 ? S : 0), lintel: UInt16 = z == 0 ? LN : (z == sz - 1 ? LS : 0)
                let roof: UInt16 = v == Trains.troopCar ? R : 0
                for y in 1...3 {
                    let fl: UInt16 = y == 1 ? F : 0, rf: UInt16 = y == 3 ? roof : 0
                    set(0, y, z, fl | W | end | rf)
                    set(2, y, z, fl | E | end | rf)
                    set(1, y, z, fl | (y == 3 ? lintel : 0) | rf)
                }
                if v == Trains.coach { for x in 0...2 { set(x, 4, z, slab | 2) } }
            }
            return (sz, v == Trains.coach ? 5 : 4, Array(c[0..<(3 * sz * (v == Trains.coach ? 5 : 4))]))
        case Trains.loco:
            // The boiler down the middle to 3.9 with the running boards each side of it (1.95); the cab (the model's
            // 2 ... 5 blocks back of the middle) on its footplate, sides and roof, open behind onto the tender.
            let cab0 = sz / 2 + 2, cab1 = min(sz - 2, sz / 2 + 4)
            solidTo(1, z: 0...(sz - 1))
            for z in 0..<cab0 {
                for y in 1...2 { set(1, y, z, slab | 16) }
                set(1, 3, z, slab | 14)
                for x in [0, 2] { set(x, 1, z, slab | 15) }
            }
            for z in cab0...cab1 {
                set(0, 1, z, F2 | W); set(1, 1, z, F2); set(2, 1, z, F2 | E)
                set(0, 2, z, W); set(2, 2, z, E)
                set(0, 3, z, W | R); set(1, 3, z, R); set(2, 3, z, E | R)
            }
            for z in (cab1 + 1)..<sz { for x in 0...2 { set(x, 1, z, F2) } }
            return (sz, 4, Array(c[0..<(3 * sz * 4)]))
        default:
            solidTo(top, z: 0...(sz - 1))
            return (sz, sy, Array(c[0..<(3 * sz * sy)]))
        }
    }

    // Every code any car uses (the blocks registered for them).
    static let codes: [UInt16] = {
        var set = Set<UInt16>()
        for v in variants { for k in cells(v).codes where k != 0 { set.insert(k) } }
        return set.sorted()
    }()
    static func key(_ code: UInt16) -> String { "train_hull_\(code)" }
    static var blockOf: [UInt16: BlockID] = [:]

    static func grid(_ v: Int) -> ShipGrid? {
        guard variants.contains(v) else { return nil }
        let (sz, sy, cs) = cells(v)
        let g = ShipGrid(sx: 3, sy: sy, sz: sz)
        for y in 0..<sy { for z in 0..<sz { for x in 0..<3 {
            let k = cs[x + z * 3 + y * 3 * sz]
            guard k != 0 else { continue }
            if blockOf[k] == nil { blockOf[k] = Blocks.has(key(k)) ? Blocks.id(key(k)) : AIR }
            g.set(x, y, z, blockOf[k]!)
        } } }
        return g
    }

    // MARK: The hulls

    static func has(_ tr: Trains.Train) -> Bool { on && !tr.layout.isEmpty && tr.cars.contains { hullOf[ObjectIdentifier($0)] != nil } }
    static func hull(_ m: Mob) -> Ship? { hullOf.isEmpty ? nil : hullOf[ObjectIdentifier(m)] }

    // A car, or someone riding one (troops, passengers): the ship code leaves them to the train.
    static func bound(_ m: Mob) -> Bool {
        guard !hullOf.isEmpty else { return false }
        if Trains.isCar(m) { return true }
        if let mt = m.mount, Trains.isCar(mt) { return true }
        return false
    }

    // Trains.buildBig: a hull for each car, and the coaches' passengers.
    static func build(_ g: Game, _ tr: Trains.Train) {
        guard on, !tr.layout.isEmpty else { return }
        let ships = g.world.ships
        for m in tr.cars where hullOf[ObjectIdentifier(m)] == nil {
            guard let gr = grid(m.variant) else { continue }
            let s = Ship(id: ships.newId(), grid: gr)
            s.name = m.customName ?? "Train"
            s.role = role
            s.kinematic = true
            s.captured = true
            s.trainCar = m
            s.rebuild()
            pose(s, m, ahead: 0)
            s.prevPos = s.pos; s.prevRot = s.rot
            s.updateBounds()
            ships.add(s)
            hullOf[ObjectIdentifier(m)] = s
            built += 1
        }
        guard tr.kind == .passenger || tr.kind == .cargo else { return }
        // Nov 12 playtest (06:16:36, at a line's train: "There's no one driving the train"): the engine's driver on
        // the footplate, at the regulator's other side from where he stands to drive it (his fireman then).
        if !Trains.oldCab, let eng = tr.cars.first(where: { Trains.isEngine($0) && $0.variant == Trains.loco }) {
            let off = V3(-1.5, 6.9, 15) * (eng.scale / 16)
            let cy = cosf(eng.yaw), sy = sinf(eng.yaw)
            let m = Mob(.villager, at: eng.pos + V3(cy * off.x + sy * off.z, off.y, -sy * off.x + cy * off.z))
            m.home = m.pos + V3(Float(Int(truncatingIfNeeded: tr.track.id % 89)), 0, 7)
            Townsfolk.setup(m, tag: "", game: g)
            m.home = m.pos
            m.persistent = false
            m.mount = eng
            m.mountOffset = off
            m.yaw = eng.yaw
            tr.passengers.append(m)
            g.mobs.mobs.append(m)
        }
        // Townsfolk on their way somewhere, standing in the coaches' aisles.
        for (k, car) in tr.cars.enumerated() where car.variant == Trains.coach {
            let h = hash3(Int(truncatingIfNeeded: tr.track.id), k, Int(g.time / DAY_LENGTH), 0x7A55)
            let n = 2 + Int(h % 4)
            var rows = [-5.2, -3.4, -1.6, 0.2, 2.0, 3.8, 5.4] as [Float]
            for i in 0..<n where !rows.isEmpty {
                let z = rows.remove(at: Int((h >> UInt32(8 + i * 3)) % UInt32(rows.count)))
                let off = V3(i % 2 == 0 ? -0.12 : 0.12, 1.27, z)
                let cy = cosf(car.yaw), sy = sinf(car.yaw)
                let m = Mob(.villager, at: car.pos + V3(cy * off.x + sy * off.z, off.y, -sy * off.x + cy * off.z))
                m.home = m.pos + V3(Float(k * 31 + i * 7), 0, Float(Int(truncatingIfNeeded: tr.track.id % 97)))
                Townsfolk.setup(m, tag: "", game: g)                  // (the name from that point: not the same in every car)
                m.home = m.pos
                m.persistent = false
                m.mount = car
                m.mountOffset = off
                m.yaw = car.yaw + (i % 3 == 0 ? .pi : 0)
                tr.passengers.append(m)
                g.mobs.mobs.append(m)
            }
        }
    }

    // Trains.remove: the hulls and the passengers still aboard go with the train.
    static func remove(_ g: Game, _ tr: Trains.Train) {
        for m in tr.cars { if let s = hullOf.removeValue(forKey: ObjectIdentifier(m)) { g.world.ships.remove(s) } }
        let aboard = Set(tr.passengers.filter { $0.mount != nil }.map { ObjectIdentifier($0) })
        if !aboard.isEmpty { g.mobs.mobs.removeAll { aboard.contains(ObjectIdentifier($0)) } }
        tr.passengers = []
    }

    // The hull at its car's place: the car's middle at the rail's top, turned with it and tilted up its grade.
    @inline(__always) static func pose(_ s: Ship, _ m: Mob, ahead dt: Float) {
        let rot = simd_normalize(Quat(angle: m.yaw, axis: V3(0, 1, 0)) * Quat(angle: m.trainPitch, axis: V3(1, 0, 0)))
        let p0 = V3(1.5, 0, Float(s.grid.sz) * 0.5)
        s.rot = rot
        s.pos = m.pos + m.vel * dt + rot.act(s.com - p0)
    }

    // ShipManager.update, after the physics step and before riders are carried: each hull goes where its car will be
    // drawn this frame (the cars move after the ships: a frame of the car's speed ahead), its speed and turn the step's.
    static func follow(_ ships: ShipManager, _ dt: Float, _ g: Game?) {
        guard !hullOf.isEmpty else { return }
        var gone: [Ship] = []
        for s in ships.list {
            guard let m = s.trainCar else { continue }
            if m.health <= 0 || Trains.carOf[ObjectIdentifier(m)] == nil { gone.append(s); continue }
            pose(s, m, ahead: dt)
            s.vel = dt > 0 ? (s.pos - s.prevPos) / dt : .zero
            var dy = s.yaw - s.prevYaw
            if dy > .pi { dy -= 2 * .pi } else if dy < -.pi { dy += 2 * .pi }
            s.angVel = V3(0, dt > 0 ? dy / dt : 0, 0)
            s.updateBounds()
            if let g, ships.aboard === s, let (tr, _) = Trains.carOf[ObjectIdentifier(m)] { tr.roofAt = g.clock; Trains.roofAt = g.clock }
        }
        for s in gone {
            if let m = s.trainCar { hullOf[ObjectIdentifier(m)] = nil }
            ships.remove(s)
        }
    }

    // The top of a car's hull over the middle of its length near world point p (TrainRoofs.climbRoof).
    static func roofPoint(_ m: Mob, near p: V3) -> V3? {
        guard let s = hull(m) else { return nil }
        let l = s.toLocal(p)
        let z = max(0, min(s.grid.sz - 1, Int(floor(l.z))))
        for y in stride(from: s.grid.sy - 1, through: 0, by: -1) {
            let b = s.grid.get(1, y, z)
            guard Blocks.collide[Int(b)] else { continue }
            let top = Blocks.boxes[Int(b)].map { Float($0.y1) / 16 }.max() ?? 1
            return s.toWorld(V3(1.5, Float(y) + top + 0.02, Float(z) + 0.5))
        }
        return nil
    }

    // Where he gets down from a car (Game.dismount): where he sat, when he fits there; else on its roof.
    static func exitPoint(_ g: Game, _ m: Mob) -> V3? {
        guard let s = hull(m) else { return nil }
        let seat = Trains.seat(m) + V3(0, 0.02, 0)
        let w = g.world, f0 = w.frame
        w.frame = s
        let fits = !g.player.collides(at: s.toLocal(seat), w)
        w.frame = f0
        return fits ? seat : roofPoint(m, near: m.pos)
    }

    // Each frame (Trains.drive, after the train moved): the passengers face the way their car runs.
    static func seatPassengers(_ tr: Trains.Train) {
        for (i, p) in tr.passengers.enumerated() {
            guard let car = p.mount else { continue }
            p.yaw = car.yaw + (i % 3 == 0 && !Trains.isEngine(car) ? .pi : 0)       // (the driver faces ahead)
        }
    }
}

extension BlockRegistry {
    // FAILURES 3: the invisible blocks of the trains' hulls (never placed in the world).
    func registerTrainHulls() {
        for code in TrainHulls.codes {
            var d = BlockDef(TrainHulls.key(code), "Train Hull")
            d.render = .none
            d.opaque = false
            d.skyStop = false
            d.aoOcc = false
            d.collide = true
            d.boxes = TrainHulls.boxes(code)
            d.hidden = true
            d.hardness = -1
            d.resistance = 0
            d.sound = .wood
            add(d)
        }
    }
}

// The trains' hulls' check (RailwayTests.trains, at a station with a passenger train standing): a hull a car; townsfolk
// in the coaches; he stands in a coach's aisle while it pulls out and is carried, between its sides (pushing into one
// for a second leaves him inside); on its roof he rides it; got down from the engine he is free in its cab.
enum TrainHullCheck {
    static func run(_ g: Game, _ tr: Trains.Train, _ check: (Bool, String) -> Void) {
        guard TrainHulls.on, !tr.layout.isEmpty else { return }
        let hulls = tr.cars.filter { TrainHulls.hull($0) != nil }.count
        let people = tr.passengers.filter { p in p.mount != nil && g.mobs.mobs.contains(where: { $0 === p }) }.count
        check(hulls == tr.cars.count && (tr.kind != .passenger || people >= 2),
              "FAILURES 3 train: \(hulls) of \(tr.cars.count) cars have a body, \(people) townsfolk ride the coaches")
        if !Trains.oldCab && tr.cars.contains(where: { $0.variant == Trains.loco }) {
            let driver = tr.passengers.first { p in p.mount.map { Trains.isEngine($0) } ?? false }
            let onPlate = driver.map { d in d.mount.map { simd_length(d.pos - Trains.seat($0)) < 4 && simd_length(d.pos - Trains.seat($0)) > 0.5 } ?? false } ?? false
            check(driver != nil && onPlate, "Nov 12 trains: someone drives the engine, on its footplate beside where he would stand (\(driver == nil ? "no driver" : onPlate ? "there" : "elsewhere"))")
        }
        guard let coach = tr.cars.first(where: { $0.variant == Trains.coach }), let s = TrainHulls.hull(coach) else { return }
        let p = g.player, w = g.world
        let pos0 = p.pos, fly0 = p.flying, yaw0 = p.yaw, my0 = p.moveYaw, ml0 = p.moveLook
        // (the train goes back to where it stood: the checks after this one start from the station)
        let t0 = g.time, st0 = (tr.delay, tr.rate, tr.throttle, tr.cabBrake, tr.brake, tr.blocksPerSec, tr.heldBy, tr.stoppedFor)
        defer {
            p.pos = pos0; p.flying = fly0; p.yaw = yaw0; p.moveYaw = my0; p.moveLook = ml0; p.vel = .zero; w.ships.aboard = nil
            if g.riding != nil { g.dismount(); p.pos = pos0 }
            g.time = t0
            (tr.delay, tr.rate, tr.throttle, tr.cabBrake, tr.brake, tr.blocksPerSec, tr.heldBy, tr.stoppedFor) = st0
            tr.time = g.time - tr.delay
            Trains.place(g, tr, dt: 0)
            w.ships.update(0, game: g)
        }
        if g.riding != nil { g.dismount() }
        p.flying = false; p.moveYaw = nil; p.moveLook = nil
        let dt: Float = 1.0 / 30
        func frames(_ n: Int, _ inp: MoveInput) {
            for _ in 0..<n {
                g.time += Double(dt)
                g.shipPlayerUpdate(dt, inp)
                w.ships.update(dt, game: g)
                Trains.drive(tr.cars[0], dt, g)
            }
        }
        func inside() -> (Bool, V3) {
            let l = s.toLocal(p.pos)
            let ok = l.x > 0.2 && l.x < 2.8 && l.z > 0.2 && l.z < Float(s.grid.sz) - 0.2 && l.y > 1.15 && l.y < 1.6
            return (ok, l)
        }
        // In the aisle, while it pulls out (up to 40 s).
        p.pos = Trains.seat(coach) + V3(0, 0.05, 0)
        p.vel = .zero
        p.yaw = coach.yaw
        let start = coach.pos
        var rode = 0, outside = 0
        for _ in 0..<40 {
            frames(30, MoveInput())
            if inside().0 { rode += 1 } else { outside += 1 }
            if simd_length(coach.pos - start) > 30 { break }
        }
        let moved = simd_length(coach.pos - start)
        let (inAisle, l1) = inside()
        check(moved > 20 && inAisle && outside == 0,
              String(format: "FAILURES 3 train: standing in a coach's aisle he rides it %.0f blocks, carried (%d s in, %d out; at %.2f %.2f %.2f in it)",
                     moved, rode, outside, l1.x, l1.y, l1.z))
        // Into its side for a second, on the move.
        var push = MoveInput(); push.strafe = 1
        frames(30, push)
        let (kept, l2) = inside()
        check(kept && l2.x < 2.9, String(format: "FAILURES 3 train: pushing into the coach's side on the move he stays in it (across %.2f of 3)", l2.x))
        // On its roof.
        if let top = TrainHulls.roofPoint(coach, near: coach.pos) {
            p.pos = top
            p.vel = .zero
            frames(90, MoveInput())
            let l = s.toLocal(p.pos)
            let onRoof = abs(l.y - 4.125) < 0.2 && l.x > 0 && l.x < 3 && l.z > 0 && l.z < Float(s.grid.sz)
            check(onRoof && moved > 20, String(format: "FAILURES 3 train: on the coach's roof he rides it (%.2f over the rail, %.1f along it)", l.y, l.z))
        } else { check(false, "FAILURES 3 train: no roof on the coach's body") }
        // Down from the engine: free in its cab.
        if let eng = tr.cars.first(where: { Trains.isEngine($0) && $0.variant == Trains.loco }), let es = TrainHulls.hull(eng) {
            _ = Trains.use(g, eng)
            let rode = g.riding === eng
            g.dismount()
            let ep = p.pos
            w.frame = es
            let stuck = p.collides(at: es.toLocal(ep), w)
            w.frame = nil
            check(rode && !stuck, String(format: "FAILURES 3 train: got down from the engine's footplate he stands free in its cab (rode %@, %.2f over the rail)",
                                         rode ? "yes" : "no", es.toLocal(ep).y))
        }
    }
}
