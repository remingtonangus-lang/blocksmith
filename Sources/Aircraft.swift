import Foundation
import simd

// The Capital's aircraft (original designs, white alloy with grey trim and smoked canopies), flown on the real
// flight model (FlightModel.swift) and crewed by Capital pilots seated at the controls (StationPose.seated):
//   Capital Kestrel  a light utility helicopter: skids, a glazed cabin for a pilot and four troops, a rotor head on
//                    the cabin roof, a tail boom with a tail rotor (a sideways propeller) and fin
//   Capital Heron    a twin-propeller liaison aircraft: a slim fuselage with a canopy, straight wings with the
//                    propellers ahead of them, a tailplane and fin, wheels for the runway (role "capplane")
// Bows face -Z (the helm faces south), like every other vessel blueprint.
enum Aircraft {
    static func kestrel() -> Blueprint {
        let b = Blueprint()
        let frame = "capital_airframe", trim = Blocks.has("capital_stone_trim") ? "capital_stone_trim" : "light_gray_concrete"
        let glass = Blocks.has("capital_glass") ? "capital_glass" : "glass"
        // Skids.
        for x in [-2, 2] { b.box(x, x, 0, 0, -4, 4, trim) }
        for z in [-3, 3] { b.box(-1, 1, 0, 0, z, z, trim) }
        // Cabin: floor, walls, roof; canopy glass round the nose and windows down the sides.
        b.box(-2, 2, 1, 1, -5, 4, frame)
        b.box(-2, 2, 2, 3, -5, 4, frame, hollow: false)
        for z in -4...3 { for y in 2...3 { for x in -1...1 { b.clear(x, y, z) } } }
        b.box(-2, 2, 4, 4, -4, 4, frame)
        for x in -1...1 { b.set(x, 2, -5, glass); b.set(x, 3, -5, glass); b.set(x, 4, -5, glass) }
        for z in [-4, -3, 0, 1] { b.set(-2, 3, z, glass); b.set(2, 3, z, glass) }
        // Door gaps on both sides behind the cockpit.
        for y in 2...3 { b.clear(-2, y, -1); b.clear(2, y, -1) }
        b.box(-2, 2, 3, 3, 4, 4, trim)                         // grey band across the back
        // A rounded nose: the corners cut back, a glazed chin.
        for y in 1...4 { b.clear(-2, y, -5); b.clear(2, y, -5) }
        b.clear(-2, 4, -4); b.clear(2, 4, -4)
        for x in -1...1 { b.set(x, 1, -5, glass) }
        // Controls and the engine (engine and rotor drive the flight model).
        b.set(0, 2, -4, "ship_helm[south]")
        b.set(0, 4, 2, "ship_engine")
        b.set(0, 5, 0, "ship_rotor")
        b.set(0, 4, 0, trim)
        // Engine cowling behind the rotor head (under the blades).
        b.box(-1, 1, 5, 5, 1, 3, trim)
        // Tail boom, fin, tail rotor.
        b.box(0, 0, 3, 3, 5, 13, frame)
        b.box(0, 0, 4, 5, 12, 13, frame)
        b.set(1, 4, 13, "ship_propeller[east]")
        b.box(-1, 1, 3, 3, 12, 12, trim)
        b.box(-2, 2, 3, 3, 10, 10, frame)                      // tailplane
        // Crew: the pilot in the cockpit, four seats in the cabin.
        b.crew = [V3(0.5, 2, -2.5), V3(-0.5, 2, 1.5), V3(1.5, 2, 1.5), V3(-0.5, 2, 2.5), V3(1.5, 2, 2.5)]
        return b
    }

    static func heron() -> Blueprint {
        let b = Blueprint()
        let frame = "capital_airframe", trim = Blocks.has("capital_stone_trim") ? "capital_stone_trim" : "light_gray_concrete"
        let glass = Blocks.has("capital_glass") ? "capital_glass" : "glass"
        // Fuselage z -8...10, a cabin y 1...3 (floor 1, roof 4) over the front half.
        b.box(-1, 1, 1, 1, -8, 10, frame)
        b.box(-1, 1, 2, 3, -7, 4, frame)
        for z in -6...3 { for y in 2...3 { b.clear(0, y, z) } }
        b.box(-1, 1, 4, 4, -6, 4, frame)
        for z in -6 ... -3 { b.set(0, 4, z, glass); b.set(-1, 3, z, glass); b.set(1, 3, z, glass) }
        b.box(-1, 1, 2, 2, 5, 10, frame)
        b.set(0, 2, -8, trim); b.set(0, 1, -9, trim)          // nose cone
        b.box(-1, 1, 1, 1, 2, 2, trim)
        // Wings (airfoils) across the fuselage's middle, propellers ahead of them, engines inside.
        for x in -10...10 where abs(x) > 1 { for z in -1...1 { b.set(x, 1, z, "ship_wing") } }
        for x in [-4, 4] { b.set(x, 1, -2, "ship_propeller[south]"); b.set(x, 2, -1, frame); b.set(x, 2, 0, frame) }
        b.set(0, 1, -2, "ship_engine"); b.set(0, 1, -1, "ship_engine")
        // Tailplane and fin.
        for x in -4...4 where abs(x) > 1 { for z in 9...10 { b.set(x, 2, z, "ship_wing") } }
        b.box(0, 0, 3, 5, 9, 10, frame)
        b.set(0, 5, 10, trim)
        // Wheels: two under the wings, one under the tail.
        b.set(-2, 0, -1, "ship_wheel"); b.set(2, 0, -1, "ship_wheel"); b.set(0, 0, 8, "ship_wheel")
        b.set(0, 2, -5, "ship_helm[south]")
        b.crew = [V3(0.5, 2, -3.5), V3(0.5, 2, 0.5)]
        return b
    }

    static var timing = ""                    // the last spawn's cost by part (the citadel log shows it)

    // An aircraft with its crew: a Capital pilot seated at the controls (and troops in the seats for the Kestrel).
    @discardableResult
    static func spawn(_ kind: String, at: V3, yaw: Float, game g: Game, troops: Int = 0, crewed: Bool = true) -> Ship {
        let heli = kind != "heron"
        let t0 = CFAbsoluteTimeGetCurrent()
        let bp = heli ? kestrel() : heron()
        let t1 = CFAbsoluteTimeGetCurrent()
        let s = g.world.ships.spawn(bp, at: at, yaw: yaw, name: heli ? "Capital Kestrel" : "Capital Heron", role: heli ? "kestrel" : "capplane")
        let t2 = CFAbsoluteTimeGetCurrent()
        defer { timing = String(format: "blueprint %.1f ms, ship %.1f ms, crew %.1f ms", (t1 - t0) * 1000, (t2 - t1) * 1000, (CFAbsoluteTimeGetCurrent() - t2) * 1000) }
        s.faction = Faction.steelhold.rawValue
        s.initialBlocks = s.blockCount
        FlightModel.attach(s)
        let seats = s.crewStations
        for (i, seat) in seats.prefix(crewed ? 1 + troops : 0).enumerated() {
            let m = Mob(i == 0 ? .soldierCrew : (i % 3 == 0 ? .soldierOfficer : .soldierRecruit), at: s.toWorld(seat + V3(0, 0.05, 0)))
            m.faction = Faction.steelhold.rawValue
            m.persistent = true
            m.deck = s
            m.station = i == 0 ? .seated : .passenger
            m.stationSeat = 0.45
            if i == 0 { m.variant = Guns.pistol; m.soldierBrain.gun = Guns.pistol }
            g.mobs.mobs.append(m)
            FlightCrew.seats.append(FlightCrew.Seat(mob: m, ship: s, local: seat))
        }
        return s
    }
}

// Seated crews ride exactly in their seats (the deck carry lets walking riders slide in a fast turn).
enum FlightCrew {
    struct Seat { weak var mob: Mob?; weak var ship: Ship?; var local: V3 }
    static var seats: [Seat] = []

    static func tick(_ g: Game) {
        guard !seats.isEmpty else { return }
        seats.removeAll { $0.mob == nil || $0.ship == nil || ($0.mob?.health ?? 0) <= 0 }
        for st in seats {
            guard let m = st.mob, let s = st.ship, m.station == .seated || m.station == .passenger else { continue }
            m.pos = s.toWorld(st.local + V3(0, 0.02, 0))
            m.vel = s.velocity(at: m.pos)
            m.yaw = s.yaw
            m.onGround = true
        }
    }
}
