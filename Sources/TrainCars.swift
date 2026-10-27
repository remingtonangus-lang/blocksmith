import Foundation
import simd

// P470 part 2 (Oct 26 18:35 and 20:14: "make big train tracks and make it so there is a train that can be boarded. Have a
// civilian version, a cargo version, and then a ... train version with troops inside"; "we need a large variant that
// would be real-life sized ... the engine should look like a damn train engine ... powered by coal"; 19:36: "the engine
// stopped and the car's not oriented the correct way"):
//   Size       the railways' trains are built at real size: a model unit is a quarter block, so a car is 3 blocks wide
//              (the bed's width, the platform's edge beside it), about 4 tall and 10 to 14 long, on wheels that run on
//              the main-line rails 1.44 apart (ShapeRails.mainGauge). The Ash Vault's armoured trains keep their size.
//   Engines    a coal-fired steam locomotive and its tender at each end of the train, the rear pair turned round, so the
//              train runs either way with an engine leading and no car ever runs backwards at a terminus.
//   Kinds      by the line and the day: a passenger train (two coaches you can walk through and sit in, the express
//              car with the strongbox), a freight train (boxcars, a tank wagon, a flatcar of logs; a held-up train's
//              boxcars can be opened), or a Greywall troop train (armoured engines, two troop cars with soldiers at their
//              firing slits and a gun car). The soldiers ride the train; stop it, or shoot at it, and they pile out.
//   Placing    the whole train stays on the line: its middle runs the timetable and is held in from the line's ends
//              by half its length, each car sits on the track where it is and points along its chord (bogie to
//              bogie), tilted up and down the grade.
extension Trains {
    static let bigScale: Float = 4
    static let tender = 15, boxcar = 16, tankWagon = 17, flatcar = 18, troopCar = 19
    static let coupler: Float = 0.8                    // blocks between two cars' ends
    enum Kind: Int { case passenger, cargo, troop, bullion }
    static var forceKind: Kind?                        // (checks)

    static func kind(_ t: Track, day: Int) -> Kind {
        if let k = forceKind { return k }
        let h = hashf(Int(truncatingIfNeeded: t.id), Int(truncatingIfNeeded: t.id >> 32), day, 0x7470)
        return h < 0.45 ? .passenger : (h < 0.75 ? .cargo : .troop)
    }

    // Cars from the end of the line's higher cells to its lower: (variant, turned round).
    static func consist(_ k: Kind) -> [(Int, Bool)] {
        switch k {
        case .passenger: return [(loco, false), (tender, false), (coach, false), (coach, false), (express, false), (tender, true), (loco, true)]
        case .cargo: return [(loco, false), (tender, false), (boxcar, false), (tankWagon, false), (flatcar, false), (boxcar, false), (tender, true), (loco, true)]
        case .troop: return [(armouredLoco, false), (troopCar, false), (gunCar, false), (troopCar, false), (armouredLoco, true)]
        case .bullion: return [(armouredLoco, false), (gunCar, false), (express, false), (troopCar, false), (armouredLoco, true)]
        }
    }

    // A car's half length in model units (a quarter block each at bigScale).
    static func halfUnits(_ v: Int) -> Float {
        switch v {
        case loco, armouredLoco: return 24
        case tender: return 13
        case coach: return 28
        case express, gunCar: return 22
        case boxcar, flatcar: return 22
        case tankWagon: return 20
        case troopCar: return 26
        default: return 13
        }
    }
    static func isBig(_ m: Mob) -> Bool { m.scale > 3 }
    static func halfLength(_ m: Mob) -> Float { isBig(m) ? halfUnits(m.variant) * m.scale / 16 : carHalfLength }
    static func halfWidth(_ m: Mob) -> Float { isBig(m) ? 1.45 : carHalfWidth }
    // The top of a car's roof (or load) above the rail.
    static func roofTop(_ m: Mob) -> Float {
        guard isBig(m) else { return roofHeight[m.variant] ?? 2 }
        switch m.variant {
        case loco: return 3.7
        case tender: return 3.1
        case coach: return 4.1
        case express, boxcar: return 4.0
        case armouredLoco: return 4.1
        case gunCar: return 2.9
        case tankWagon: return 3.5
        case flatcar: return 2.95
        case troopCar: return 4.0
        default: return 2
        }
    }
    // The floor of a car you walk about in (the coaches and troop cars), above the rail.
    static func floorTop(_ m: Mob) -> Float? { isBig(m) && (m.variant == coach || m.variant == troopCar) ? 1.25 : nil }

    // A point of a car's model (units) in the world: its tilt, its heading and its size.
    static func world(_ m: Mob, _ u: V3) -> V3 {
        let cp = cosf(m.trainPitch), sp = sinf(m.trainPitch)
        let q = V3(u.x, cp * u.y - sp * u.z, sp * u.y + cp * u.z) * (m.scale / 16)
        let cy = cosf(m.yaw), sy = sinf(m.yaw)
        return m.pos + V3(cy * q.x + sy * q.z, q.y, -sy * q.x + cy * q.z)
    }
    // Where a rider stands: a coach's aisle, a locomotive's footplate.
    static func seat(_ m: Mob) -> V3 {
        guard isBig(m) else { return m.pos + V3(0, 1.0, 0) }
        if m.variant == loco { return world(m, V3(1.5, 6.9, 15)) }
        return world(m, V3(0, 5.1, 0))
    }
    // The driver's cab (a gun on it holds the train up) and the chimney (its smoke).
    static func cabPoint(_ m: Mob) -> V3 { isBig(m) ? world(m, V3(0, 11, 14)) : m.pos + V3(0, 2.2, 0) - m.forward * 0.9 }
    static func chimney(_ m: Mob) -> V3 {
        guard isBig(m) else { return m.pos + V3(0, 3.6, 0) + m.forward * 1.4 }
        return m.variant == armouredLoco ? world(m, V3(0, 18.2, 7)) : world(m, V3(0, 18, -20.4))
    }
    // The locomotive at the front of the train, the way it runs now.
    static func lead(_ tr: Train) -> Mob? { tr.layout.isEmpty || tr.dir > 0 ? tr.cars.first : tr.cars.last }
    static func isEngine(_ m: Mob) -> Bool { m.variant == loco || m.variant == armouredLoco }

    // MARK: Building a real-size train

    static func buildBig(_ g: Game, _ tr: Train, day: Int) {
        tr.kind = tr.bullion ? .bullion : kind(tr.track, day: day)
        var cars = consist(tr.kind)
        // A short line: cars come out of the middle until the train fits between the buffers.
        let room = Float(tr.track.cells.count) - 8
        func length(_ c: [(Int, Bool)]) -> Float { c.reduce(0) { $0 + 2 * halfUnits($1.0) * bigScale / 16 } + coupler * Float(c.count - 1) }
        while cars.count > 2 && length(cars) > room { cars.remove(at: cars.count / 2) }
        if length(cars) > room { cars = [cars[0]] }
        tr.length = length(cars)
        var off = tr.length / 2
        tr.layout = []
        let name = tr.track.name
        for (k, (v, back)) in cars.enumerated() {
            let h = halfUnits(v) * bigScale / 16
            off -= h
            tr.layout.append((v, back, off))
            off -= h + coupler
            let m = Mob(.minecart, at: tr.track.point(0))
            m.variant = v
            m.scale = bigScale
            m.persistent = false
            m.livery = tr.kind == .cargo ? 1 : 0
            let troops = tr.kind == .troop || tr.kind == .bullion
            m.customName = troops ? [armouredLoco: tr.kind == .bullion ? "\(name) Bullion Train" : "Greywall Troop Train", gunCar: "Guard Car",
                                     troopCar: "Troop Car", express: "Bullion Car"][v]
                : [loco: tr.kind == .cargo ? "\(name) Freight Locomotive" : "\(name) Locomotive", tender: "Tender", coach: "\(name) Coach",
                   express: "\(name) Express Car", boxcar: "Boxcar", tankWagon: "Tank Wagon", flatcar: "Flatcar"][v]
            if troops { m.health = v == gunCar ? 160 : (v == express ? m.spec.health : 240) }
            carOf[ObjectIdentifier(m)] = (tr, k)
            tr.cars.append(m)
            g.mobs.mobs.append(m)
        }
        tr.carS = Array(repeating: 0, count: tr.cars.count)
        place(g, tr, dt: 0)
        // The soldiers: four to a troop car, at its firing slits.
        guard tr.kind == .troop || tr.kind == .bullion else { return }
        for car in tr.cars where car.variant == troopCar {
            for (x, z) in [(-0.9, -3.0), (0.9, -1.0), (-0.9, 1.0), (0.9, 3.0)] as [(Float, Float)] {
                guard let s = Mob.structureMob("soldier_trooper@grey", at: car.pos) else { continue }
                s.persistent = false
                s.mount = car
                s.mountOffset = V3(x, 1.3, z)
                s.pos = car.pos + V3(0, 1.3, 0)
                tr.troops.append(s)
                g.mobs.mobs.append(s)
            }
        }
    }

    // Trains.place for a real-size train: its middle at s (held in from the line's ends), each car on the track.
    static func placeBig(_ tr: Train, _ s: Float, _ dir: Float, _ dt: Float) -> Float {
        let t = tr.track
        let n = Float(t.cells.count), half = tr.length / 2
        let lo = half + 3, hi = n - 4 - half
        let sc = lo <= hi ? max(lo, min(hi, s)) : (n - 1) / 2
        let moving = abs(sc - tr.lastS)
        tr.lastS = sc
        tr.dir = dir
        for (k, m) in tr.cars.enumerated() where k < tr.layout.count {
            let (_, back, off) = tr.layout[k]
            let sk = sc + off
            let b = halfLength(m) * 0.7
            var d = t.point(sk + b) - t.point(sk - b)
            if back { d = -d }
            let p = t.point(sk)
            let along = simd_length(V2(d.x, d.z))
            m.vel = dt > 0 ? simd_normalize(t.point(sk + dir * 0.7) - t.point(sk - dir * 0.7)) * (moving / max(dt, 1e-4)) : .zero
            m.pos = p
            if along > 0.01 { m.yaw = atan2f(-d.x, -d.z); m.trainPitch = atan2f(d.y, along) }
            m.walkPhase += moving * dir * (back ? -1 : 1)           // (blocks run forward: the wheels turn by it)
            m.onGround = true
            tr.carS[k] = sk
        }
        return moving
    }

    // Once a second: the troops get off a train the player stopped or fired on, near him, and fight on foot.
    static func troopTick(_ g: Game, _ tr: Train) {
        tr.troops.removeAll { $0.health <= 0 && $0.mount == nil }
        let aboard = tr.troops.filter { $0.mount != nil && $0.health > 0 }
        guard !aboard.isEmpty else { return }
        let near = tr.cars.contains { simd_length($0.pos - g.player.pos) < 40 }
        let shot = tr.troops.contains { $0.health < $0.spec.health } || tr.cars.contains { $0.variant == gunCar && $0.health < 160 }
        let stood = tr.blocksPerSec < 0.3 && tr.track.at(tr.time).stop == nil
        guard near && (shot || tr.heldBy || stood) else { return }
        tr.roused = true
        for s in aboard {
            guard let car = s.mount else { continue }
            let side: Float = (s.mountOffset?.x ?? 1) < 0 ? -1 : 1
            let right = V3(cosf(car.yaw), 0, -sinf(car.yaw))
            s.mount = nil
            s.mountOffset = nil
            s.pos = g.world.freeSpawn(s.pos + right * side * 2.6 + V3(0, -1, 0))
            s.vel = .zero
            s.home = s.pos
        }
        g.onToast?("Troops pile out of the \(tr.cars.first?.customName ?? "train")")
    }

    // Use a boxcar of a held-up freight train: its doors slide open on the goods.
    static func openBoxcar(_ g: Game, _ tr: Train, _ m: Mob) -> Bool {
        guard tr.brake > 0.8 else { g.onToast?("The boxcar's doors are sealed for the run"); return true }
        if m.cargo == nil {
            let c = ItemContainer(27)
            let goods: [(String, ClosedRange<Int>)] = [("coal", 8...32), ("iron_ingot", 2...12), ("wheat", 6...24), ("oak_planks", 8...32),
                                                       ("copper_ingot", 2...10), ("leather", 2...8), ("bread", 3...10), ("gunpowder", 1...6)]
            for (k, r) in goods where Items.has(k) && Rand.float(in: 0..<1) < 0.6 { c.add(ItemStack(Items.id(k), Rand.int(in: r))) }
            m.cargo = c
            if g.survival {
                Honour.change(g, robHonour / 3, "broke into a boxcar on the \(tr.track.name)")
                Honour.addBounty(g, Townsfolk.town(g, at: m.pos), robBounty / 4)
            }
        }
        g.sfx(.armorEquip(0), 0.6, at: m.pos)
        g.openMenu(ChestMenu(game: g, container: m.cargo!, title: m.customName ?? "Boxcar"))
        return true
    }

    // MARK: Real-size models (units a quarter block at bigScale; the car faces -Z; rail top at y 0, the rails 2.9 out)

    static func bigParts(_ m: Mob) -> [Part] {
        let iron = V3(0.16, 0.16, 0.17), brass = V3(0.85, 0.66, 0.3), red = V3(0.55, 0.1, 0.08), black = V3(0.07, 0.07, 0.075)
        let freight = m.livery == 1
        var p: [Part] = []
        let run = m.walkPhase
        func wheel(_ z: Float, _ r: Float, _ c: V3) {
            for x: Float in [-3.4, 2.4] {
                p.append(Part(mn: V3(x, 0.05, z - r), mx: V3(x + 1, 0.05 + 2 * r, z + r), pivot: V3(x, 0.05 + r, z), rotX: -run * 4 / r, color: c, pattern: 8))
            }
        }
        func bogie(_ z: Float) {
            wheel(z - 2.6, 1.7, iron); wheel(z + 2.6, 1.7, iron)
            p.append(box(-3.9, 1.6, z - 4, 7.8, 1.6, 8, iron, 8))
        }
        func underframe(_ h: Float) {
            p.append(box(-5.6, 3.2, -h, 11.2, 1.4, 2 * h, iron, 8))
            for e in [-h - 0.8, h - 0.2] { p.append(box(-5.2, 3.4, e, 1.2, 1.2, 1, black, 8)); p.append(box(4, 3.4, e, 1.2, 1.2, 1, black, 8)) }   // buffers
        }
        switch m.variant {
        case loco:
            let body = freight ? V3(0.09, 0.09, 0.1) : V3(0.1, 0.24, 0.15), smoke = V3(0.08, 0.08, 0.09), steel = V3(0.72, 0.72, 0.75)
            p.append(box(-2.4, 2.6, -23, 4.8, 2.4, 44, iron, 8))                    // the frame between the wheels
            p.append(box(-6, 3, -24, 12, 3, 1.2, red, 7))                          // the buffer beam
            p.append(box(-5.2, 3.6, -25, 1.4, 1.4, 1, black, 8)); p.append(box(3.8, 3.6, -25, 1.4, 1.4, 1, black, 8))
            p.append(box(-4.5, 0.4, -25.4, 9, 2.6, 1.6, red, 7))                   // the cowcatcher
            wheel(-19, 1.7, iron)                                                   // the leading truck
            for z: Float in [-9, -1.5, 6] { wheel(z, 3.4, red) }                    // the driving wheels
            wheel(16, 2, iron)                                                      // under the cab
            for x: Float in [-6.2, 4] { p.append(box(x, 3.2, -21, 2.2, 3.4, 5, body, 7)) }   // the cylinders
            // The rods: they run round with the drivers.
            let a = -run * 4 / 3.4, r = sinf(a) * 1.5, q = cosf(a) * 1.5
            for x: Float in [-4.4, 3.8] {
                p.append(box(x, 2.9 + q, -9 + r, 0.6, 0.9, 15.5, steel, 8))
                p.append(box(x, 4.4, -18, 0.5, 0.6, 8 + r, steel, 8))
            }
            p.append(box(-6, 7.2, -22, 12, 0.6, 30, body, 7))                       // the running boards
            p.append(box(-3.8, 7.8, -21, 7.6, 7, 28, body, 7))                      // the boiler
            p.append(box(-2.8, 14.8, -21, 5.6, 0.7, 28, body, 7))
            for z: Float in [-14, -6, 2] { p.append(box(-3.9, 7.8, z, 7.8, 7.1, 0.5, brass, 8)) }       // its bands
            p.append(box(-3.9, 7.6, -23.4, 7.8, 7.4, 3, smoke, 8))                 // the smokebox
            p.append(box(-2.8, 8.6, -23.8, 5.6, 5.6, 0.5, V3(0.12, 0.12, 0.13), 8))
            p.append(box(-0.3, 11, -24.1, 0.6, 0.6, 0.4, brass, 8))
            p.append(box(-1, 15, -23.2, 2, 1.8, 1.6, iron, 8))                      // the headlamp
            p.append(box(-0.7, 15.3, -23.45, 1.4, 1.2, 0.3, V3(1, 0.95, 0.7), 9))
            p.append(box(-1.4, 14.6, -21.8, 2.8, 2.6, 2.8, smoke, 8))              // the chimney
            p.append(box(-1.8, 17.2, -22.2, 3.6, 0.6, 3.6, smoke, 8))
            p.append(box(-1.6, 14.8, -10, 3.2, 1.8, 3.2, brass, 8))                // the steam dome
            p.append(box(-1.4, 14.8, -3, 2.8, 1.4, 2.8, body, 7))                  // the sand dome
            p.append(box(-0.6, 14.8, 4, 1.2, 1.4, 1.2, brass, 8))                  // the safety valves
            p.append(box(-0.4, 15.6, 6.8, 0.8, 1.8, 0.8, brass, 8))                // the whistle
            // The cab: open behind, windows each side, the fire's door glowing on the backhead.
            p.append(box(-6, 6.4, 8, 12, 0.5, 12, V3(0.3, 0.22, 0.14), 7))          // the footplate
            for x: Float in [-6, 5.4] {
                p.append(box(x, 6.9, 8, 0.6, 4.2, 12, body, 7))
                p.append(box(x, 11.1, 8, 0.6, 4.5, 1.4, body, 7)); p.append(box(x, 11.1, 18.6, 0.6, 4.5, 1.4, body, 7))
            }
            p.append(box(-6, 6.9, 8, 12, 8.7, 0.6, body, 7))                        // the spectacle plate
            for x: Float in [-4.6, 2.2] { p.append(box(x, 12.4, 7.7, 2.4, 2, 0.3, V3(0.05, 0.06, 0.07), 11)) }
            p.append(box(-6.4, 15.6, 7.6, 12.8, 0.8, 13, black, 7))                 // the roof
            p.append(box(-3, 6.9, 8.6, 6, 7, 0.8, smoke, 8))                        // the backhead
            p.append(box(-1.2, 8.2, 9.42, 2.4, 1.8, 0.2, V3(1, 0.5, 0.15), 9))      // the firebox door
            for x: Float in [-2, 1] { p.append(box(x, 12.2, 9.42, 1, 1, 0.2, brass, 8)) }        // the gauges
            p.append(box(-0.3, 13.4, 9.42, 2.2, 0.4, 0.4, brass, 8))                // the regulator
            p.append(box(-1, 3.4, 20, 2, 1.2, 4, iron, 8))                          // the drawbar
            p.append(box(-6, 3, 22.8, 12, 3, 1.2, red, 7))
        case tender:
            let body = freight ? V3(0.09, 0.09, 0.1) : V3(0.1, 0.24, 0.15), coal = V3(0.05, 0.05, 0.055)
            p.append(box(-5.6, 3, -13, 11.2, 1.6, 26, iron, 8))
            for z: Float in [-9, -4.5, 4.5, 9] { wheel(z, 1.7, iron) }
            p.append(box(-5.6, 4.6, -12.6, 11.2, 7.8, 25.2, body, 7))              // the tank
            p.append(box(-6, 12.4, -12.6, 12, 0.6, 14, body, 7))                   // the coal space's flare
            p.append(box(-5.65, 8, -12.6, 11.3, 0.4, 25.2, brass, 8))              // its lining
            p.append(box(-4.8, 12.4, -12, 9.6, 1.6, 12, coal, 4))                  // the coal
            p.append(box(-3.6, 14, -11, 7.2, 1, 8, coal, 4))
            p.append(box(-1.5, 12.4, 5, 3, 0.8, 3, iron, 8))                       // the water hatch
        case coach:
            let lower = V3(0.38, 0.1, 0.08), upper = V3(0.84, 0.76, 0.58), roof = V3(0.2, 0.2, 0.21), seat = V3(0.42, 0.12, 0.1)
            bogie(-20); bogie(20)
            underframe(28)
            p.append(box(-6, 4.6, -28, 12, 0.4, 56, V3(0.35, 0.26, 0.17), 7))      // the floor
            for x: Float in [-6, 5.5] {
                p.append(box(x, 5, -28, 0.5, 4, 56, lower, 7))                    // the side, below the windows
                p.append(box(x, 13, -28, 0.5, 2.6, 56, upper, 7))                 // and above
                for z in stride(from: Float(-27), to: 27, by: 7) { p.append(box(x, 9, z, 0.5, 4, 2, upper, 7)) }   // between windows
                p.append(box(x < 0 ? x - 0.05 : x + 0.45, 8.6, -28, 0.1, 0.4, 56, brass, 8))   // the lining
            }
            for e: Float in [-28, 27.5] {                                          // the ends, a door in each
                p.append(box(-6, 5, e, 4.5, 10.6, 0.5, lower, 7)); p.append(box(1.5, 5, e, 4.5, 10.6, 0.5, lower, 7))
                p.append(box(-1.5, 13, e, 3, 2.6, 0.5, lower, 7))
            }
            p.append(box(-6.3, 15.6, -28.2, 12.6, 0.8, 56.4, roof, 7))
            p.append(box(-3, 16.4, -27, 6, 0.8, 54, roof, 7))                      // the clerestory
            for z in stride(from: Float(-24), through: 20, by: 7) {               // the seats, an aisle between
                for x: Float in [-5.5, 1.7] {
                    p.append(box(x, 5, z, 3.8, 1.8, 2.4, seat, 10))
                    p.append(box(x, 6.8, z + 2.2, 3.8, 3, 0.5, seat, 10))
                }
            }
            for z: Float in [-14, 0, 14] { p.append(box(-0.5, 15.1, z, 1, 0.5, 1, V3(1, 0.85, 0.55), 9)) }      // the lamps
        case express:
            let side = m.customName?.hasPrefix("Bullion") == true ? V3(0.22, 0.23, 0.2) : V3(0.14, 0.18, 0.34), trim = V3(0.9, 0.78, 0.35)
            bogie(-15); bogie(15)
            underframe(22)
            p.append(box(-6, 4.6, -22, 12, 11, 44, side, 7))
            p.append(box(-6.3, 15.6, -22.2, 12.6, 0.8, 44.4, V3(0.2, 0.2, 0.21), 7))
            for x: Float in [-6.25, 5.95] {
                p.append(box(x, 5, -4, 0.3, 9.5, 8, side * 0.7, 7))                // the sliding door
                for z: Float in [-17, 13] { p.append(box(x, 11, z, 0.3, 2, 3, V3(0.05, 0.05, 0.06), 11)) }   // barred windows
                p.append(box(x, 12.5, -1.5, 0.3, 1.2, 3, trim, 8))                 // the brass plate
            }
        case boxcar:
            let side = V3(0.42, 0.17, 0.1), rib = V3(0.3, 0.12, 0.07)
            bogie(-15); bogie(15)
            underframe(22)
            p.append(box(-6, 4.6, -22, 12, 11, 44, side, 7))
            p.append(box(-6.2, 15.6, -22.2, 12.4, 0.6, 44.4, V3(0.25, 0.25, 0.26), 8))
            p.append(box(-1, 16.2, -22, 2, 0.3, 44, V3(0.4, 0.3, 0.2), 7))         // the roof walk
            for x: Float in [-6.15, 5.95] {
                for z in stride(from: Float(-21), through: 20, by: 6) where abs(z) > 5 { p.append(box(x, 4.6, z, 0.2, 11, 0.6, rib, 7)) }
                p.append(box(x < 0 ? -6.3 : 6, 5, -5, 0.3, 10, 10, rib, 7))       // the door
                p.append(box(x < 0 ? -6.4 : 6.1, 9.5, -0.3, 0.3, 1, 0.6, iron, 8))
            }
        case tankWagon:
            let tank = V3(0.12, 0.12, 0.13)
            bogie(-13); bogie(13)
            underframe(20)
            p.append(box(-6, 4.6, -20, 12, 0.3, 40, V3(0.35, 0.26, 0.17), 7))      // the walkway
            p.append(box(-5, 5.4, -18, 10, 7.6, 36, tank, 7))                      // the tank
            p.append(box(-4, 13, -18, 8, 0.8, 36, tank, 7)); p.append(box(-4, 4.8, -18, 8, 0.6, 36, tank, 7))
            for e: Float in [-19, 18] { p.append(box(-4, 6.4, e, 8, 5.6, 1, tank, 7)) }
            p.append(box(-1.8, 13.8, -1.8, 3.6, 1.6, 3.6, tank, 7))                // the dome
            for z: Float in [-12, 12] { p.append(box(-5.4, 5.6, z, 10.8, 0.5, 0.8, iron, 8)) }                // the straps
        case flatcar:
            let log = V3(0.36, 0.25, 0.15), cut = V3(0.72, 0.58, 0.38)
            bogie(-15); bogie(15)
            underframe(22)
            p.append(box(-6, 4.6, -22, 12, 0.8, 44, V3(0.38, 0.28, 0.18), 7))      // the deck
            for z: Float in [-20, -8, 4, 16] { for x: Float in [-6, 5.4] { p.append(box(x, 5.4, z, 0.6, 6, 0.6, iron, 8)) } }   // the stakes
            for (x, y) in [(-5.2, 5.4), (-1.6, 5.4), (2.0, 5.4), (-3.4, 8.6), (0.2, 8.6)] as [(Float, Float)] {
                p.append(box(x, y, -20, 3.2, 3.2, 40, log, 4))                     // the logs
                p.append(box(x + 0.3, y + 0.3, -20.1, 2.6, 2.6, 0.2, cut, 4)); p.append(box(x + 0.3, y + 0.3, 19.9, 2.6, 2.6, 0.2, cut, 4))
            }
        case troopCar:
            let plate = V3(0.3, 0.31, 0.27), band = V3(0.62, 0.6, 0.52)
            bogie(-18); bogie(18)
            underframe(26)
            p.append(box(-6, 4.6, -26, 12, 0.4, 52, V3(0.2, 0.2, 0.19), 8))        // the floor
            for x: Float in [-6, 5.3] {
                p.append(box(x, 5, -26, 0.7, 5, 52, plate, 8))                    // the armour, below the slits
                p.append(box(x, 12.4, -26, 0.7, 2.8, 52, plate, 8))               // and above
                for z in stride(from: Float(-26), to: 24, by: 6) { p.append(box(x, 10, z, 0.7, 2.4, 3, plate, 8)) }   // between the slits
                p.append(box(x < 0 ? x - 0.05 : x + 0.65, 13.4, -26, 0.1, 0.8, 52, band, 7))
                p.append(box(x < 0 ? -5.3 : 3.3, 5, -22, 2, 1.8, 44, V3(0.32, 0.24, 0.16), 7))      // the benches
            }
            for e: Float in [-26, 25.3] {
                p.append(box(-6, 5, e, 4.5, 10.2, 0.7, plate, 8)); p.append(box(1.5, 5, e, 4.5, 10.2, 0.7, plate, 8))
                p.append(box(-1.5, 13, e, 3, 2.2, 0.7, plate, 8))
            }
            p.append(box(-6.3, 15.2, -26.3, 12.6, 0.8, 52.6, plate, 8))
        case armouredLoco:
            let plate = V3(0.3, 0.31, 0.27), dark = V3(0.15, 0.15, 0.14), band = V3(0.62, 0.6, 0.52)
            for z: Float in [-14, -5, 4, 13] { wheel(z, 3, dark) }
            p.append(box(-2.4, 2.6, -23, 4.8, 2.6, 46, dark, 8))
            for x: Float in [-6.2, 5.6] { p.append(box(x, 1.4, -23, 0.6, 5, 46, plate, 8)) }      // the wheel skirts
            p.append(box(-6, 6, -22, 12, 7, 44, plate, 8))                          // the hull
            p.append(box(-6, 4, -24.6, 12, 5, 2.6, dark, 8))                       // the ram
            p.append(box(-5.4, 9, -24, 10.8, 3.4, 2, plate, 8))                    // the glacis
            p.append(box(-5, 13, -18, 10, 3.6, 30, plate, 8))                      // the casemate
            p.append(box(-4, 15, -18.3, 8, 0.6, 0.4, V3(0.03, 0.03, 0.03), 11))    // the vision slit
            p.append(box(-6.1, 10, -22, 12.2, 0.8, 44, band, 7))                   // the band
            p.append(box(-1.2, 16.6, 6, 2.4, 1.6, 2.4, dark, 8))                   // the exhaust
            p.append(box(-1, 9.6, -24.7, 2, 1.4, 0.4, V3(1, 0.95, 0.7), 9))       // the headlamp
        case gunCar:
            let plate = V3(0.3, 0.31, 0.27), dark = V3(0.15, 0.15, 0.14), band = V3(0.62, 0.6, 0.52)
            bogie(-15); bogie(15)
            underframe(22)
            for x: Float in [-6.2, 5.6] { p.append(box(x, 1.4, -21, 0.6, 3.4, 42, plate, 8)) }
            p.append(box(-6, 4.6, -22, 12, 7, 44, plate, 8))
            p.append(box(-6.1, 8, -22, 12.2, 0.8, 44, band, 7))
            // The turret turns to its target (Mob.jobTimer holds its yaw relative to the car).
            let ty = m.jobTimer
            p.append(Part(mn: V3(-4.5, 11.6, -4.5), mx: V3(4.5, 16, 4.5), pivot: V3(0, 11.6, 0), color: plate, pattern: 8, rotY: ty))
            p.append(Part(mn: V3(-0.6, 13.2, -16), mx: V3(0.6, 14.4, -4.5), pivot: V3(0, 11.6, 0), color: dark, pattern: 8, rotY: ty))
            p.append(Part(mn: V3(-2.2, 12.6, -5.2), mx: V3(2.2, 15, -4.2), pivot: V3(0, 11.6, 0), color: dark, pattern: 8, rotY: ty))
        default: break
        }
        return p
    }
}
