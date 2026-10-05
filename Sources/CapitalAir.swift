import Foundation
import simd

// Citadel air patrols (reactive citadels + the flight model): when a citadel goes to alert over a noise outside its
// walls, or on lockdown, a Capital Kestrel (Aircraft.swift) with a Capital pilot and two troops lifts off the landing
// pad on the tower's setback terrace, climbs to a cruise height clear of the ground on its route, flies out and
// circles the noise (lockdown: circles the citadel while it lasts), then flies back, lets down onto the pad and is
// stowed. Everything is flown by the real flight model's autopilot (FlightModel.hold), set once a second here.
// Kill the pilot and the autopilot goes too: the Kestrel falls. The phase, goal and ship id are saved with the
// citadel; after a reload the crew still sitting at the seats is buckled back in.
//   airPhase  1 climb over the pad, 2 out, 3 circle, 4 back over the pad, 5 let down, 6 landed
extension BaseRecord {
    // The landing pad's surface (where skids rest), cantilevered north off the tower's terrace (CapitalBase.swift:
    // terrace floor P2 + 30 = y0 + 41, centre 21 north of the tower).
    var pad: V3 { V3(Float(cx) + 0.5, Float(y0 + 42), Float(cz - 21) + 0.5) }
}

extension Game {
    // A launch: called by the citadel when it sends its Kestrel up (no-op while one is up).
    func baseCallAir(_ r: inout BaseRecord, _ b: BaseWatch, to goal: V3) {
        guard r.air == nil else {
            if (r.airPhase ?? 0) <= 3 { r.air = [goal.x, goal.y, goal.z] }       // a newer noise redirects it
            return
        }
        guard (r.airCD ?? 0) <= 0 else { return }
        r.air = [goal.x, goal.y, goal.z]; r.airPhase = 0; r.airT = 0; r.airShip = nil
    }

    // Cruise height for a leg from a to b: 22 over the highest ground or building on the way, at least 12 over the
    // citadel's crown.
    // `clear` over the ground; the crown floor only for legs that cross the citadel (circling a noise outside at 74 over
    // the citadel's base put the door gunners far out of sight of anyone on the ground).
    private func airCruise(_ r: BaseRecord, _ a: V3, _ c: V3, clear: Float = 22) -> Float {
        var top: Float = 0
        let n = max(1, Int(simd_length(V2(c.x - a.x, c.z - a.z)) / 8))
        let reach: Float = 40                               // the towers (main and side) stand within ~35 of the centre
        for k in 0...n {
            let p = a + (c - a) * (Float(k) / Float(n))
            let x = Int(floor(p.x)), z = Int(floor(p.z))
            let h = world.isLoaded(x, z) ? world.topY(x, z) : world.gen.column(x, z).height
            top = max(top, Float(max(h, SEA)) + clear)
            if simd_length(V2(p.x - Float(r.cx), p.z - Float(r.cz))) < reach { top = max(top, Float(r.y0 + 74)) }
        }
        return min(top, Float(CH - 30))
    }

    // What keeps the Kestrel on the ground: nil when the pad is there and clear (not blasted away, nothing on it).
    private func padProblem(_ r: BaseRecord) -> String? {
        let p = r.pad
        let x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
        guard world.isLoaded(x, z) else { return "not loaded" }
        for dz in -3...3 { for dx in -2...2 where !Blocks.collide[Int(world.block(x + dx, y - 1, z + dz))] {
            return "a hole at \(x + dx),\(y - 1),\(z + dz): \(Blocks.key(world.block(x + dx, y - 1, z + dz)))"
        } }
        for dy in 0...5 { for dz in -3...3 where Blocks.collide[Int(world.block(x, y + dy, z + dz))] {
            return "\(Blocks.key(world.block(x, y + dy, z + dz))) at \(x),\(y + dy),\(z + dz)"
        } }
        return nil
    }

    func baseAir(_ r: inout BaseRecord, _ b: BaseWatch, _ dt: Float) {
        if let cd = r.airCD, cd > 0 { r.airCD = cd - dt }
        guard let ga = r.air, ga.count == 3 else { return }
        let goal = V3(ga[0], ga[1], ga[2])
        var ph = r.airPhase ?? 0
        var t = (r.airT ?? 0) + dt
        defer { r.airPhase = ph; r.airT = t }
        let pad = r.pad
        let ships = world.ships
        func done(_ why: String, cooldown: Float = 60) {
            b.note("\(r.key) kestrel \(why)")
            b.aircraft[r.key] = nil
            r.air = nil; r.airShip = nil; r.airCD = cooldown
            ph = 0; t = 0
        }
        // The aircraft: built on the pad for a launch, else the one in flight (after a reload, found by its id).
        var s = b.aircraft[r.key].flatMap { a in ships.list.contains { $0 === a } ? a : nil }
        if s == nil, let id = r.airShip { s = ships.list.first { $0.id == id && $0.role == "kestrel" } }
        if s == nil {
            guard ph == 0 else { done("lost"); return }
            if let why = padProblem(r) { done("grounded (pad: \(why))", cooldown: 120); return }
            let tb = CFAbsoluteTimeGetCurrent()
            let k = Aircraft.spawn("kestrel", at: pad + V3(0, 3, 0), yaw: Float.pi, game: self, troops: 2)
            let builtMs = (CFAbsoluteTimeGetCurrent() - tb) * 1000
            k.home = pad
            r.airShip = k.id
            ph = 1; t = 0
            b.note(String(format: "%@ kestrel lifts off the pad (built in %.1f ms: %@)", r.key, builtMs, Aircraft.timing))
            if simd_length(player.pos - pad) < 160 { onToast?("A Capital Kestrel lifts off") }
            s = k
        }
        guard let k = s, let fm = k.flight else { done("lost"); return }
        b.aircraft[r.key] = k
        if k.faction == 0 { k.faction = Faction.steelhold.rawValue }
        // Taken by the player: it is theirs now, the citadel stops flying it.
        if ships.pilot === k {
            fm.hold = nil; fm.holdYaw = nil
            raiseAlert(&r, b)
            done("taken by the player")
            return
        }
        // The pilot: buckled in (after a reload: the Capital pilot sitting nearest the controls is buckled back in).
        if !FlightCrew.seats.contains(where: { $0.ship === k }) { FlightCrew.relink(self, k) }
        let pilot = FlightCrew.seats.first { $0.ship === k && $0.mob?.station == .seated }?.mob
        if pilot == nil || pilot!.health <= 0 || k.wrecked {
            let seated = FlightCrew.seats.filter { $0.ship === k }.map { st -> String in
                guard let m = st.mob else { return "gone" }
                return "\(m.kind.key) \(m.station) hp \(Int(m.health))\(m.deck === k ? "" : " off the deck")"
            }
            let why = k.wrecked ? "wrecked" : (seated.isEmpty ? "no crew seats" : seated.joined(separator: ", "))
            fm.hold = nil; fm.holdYaw = nil                       // nobody at the controls: it falls
            raiseAlert(&r, b)
            // Still on the pad: stowed (nobody to fly it); in the air it comes down where it may.
            if simd_length(V2(k.pos.x - pad.x, k.pos.z - pad.z)) < 4 && k.worldMin.y < pad.y + 1.5 {
                for st in FlightCrew.seats where st.ship === k { if let m = st.mob { mobs.mobs.removeAll { $0 === m } } }
                FlightCrew.seats.removeAll { $0.ship === k }
                ships.remove(k)
            }
            done("lost its pilot (\(why))")
            return
        }
        let flat = simd_length(V2(k.pos.x - goal.x, k.pos.z - goal.z))
        let overPad = simd_length(V2(k.pos.x - pad.x, k.pos.z - pad.z))
        let lockdown = r.alert == .lockdown
        fm.holdYaw = nil
        switch ph {
        case 1:
            let cruise = airCruise(r, pad, goal)
            fm.hold = V3(pad.x, cruise, pad.z); fm.holdSpeed = 6
            if k.pos.y > cruise - 4 || t > 40 { ph = 2; t = 0; b.note("\(r.key) kestrel out to \(Int(goal.x)),\(Int(goal.z))") }
        case 2:
            fm.hold = V3(goal.x, airCruise(r, k.pos, goal), goal.z); fm.holdSpeed = 14
            if flat < 14 { ph = 3; t = 0; b.note("\(r.key) kestrel over the noise") }
            else if t > 120 { ph = 4; t = 0; b.note("\(r.key) kestrel turned back (\(Int(flat)) blocks short)") }
        case 3:
            // Circles the spot (the citadel itself on lockdown) for 40 s, as long as the lockdown lasts.
            let centre = lockdown ? r.centre : goal
            // Low and tight over a noise (the door gunners' rifles reach about 26 blocks); wide over the citadel.
            let radius: Float = lockdown ? 50 : 14
            let a = t * (lockdown ? 0.22 : 0.3)
            let p = centre + V3(cosf(a) * radius, 0, sinf(a) * radius)
            fm.hold = V3(p.x, airCruise(r, k.pos, p, clear: lockdown ? 22 : 14), p.z); fm.holdSpeed = 9
            if t > 40 && !lockdown { ph = 4; t = 0; b.note("\(r.key) kestrel heading back") }
        case 4:
            fm.hold = V3(pad.x, airCruise(r, k.pos, pad), pad.z); fm.holdSpeed = overPad < 30 ? 6 : 14
            if overPad < 2 && simd_length(k.vel) < 1.2 { ph = 5; t = 0; b.note("\(r.key) kestrel over the pad") }
            else if t > 150 {
                // Stowed where it is rather than left hanging in the sky without a citadel flying it.
                for st in FlightCrew.seats where st.ship === k { if let m = st.mob { mobs.mobs.removeAll { $0 === m } } }
                FlightCrew.seats.removeAll { $0.ship === k }
                ships.remove(k)
                done("never made it back (\(Int(overPad)) blocks off)")
                return
            }
        case 5:
            let skids = k.pos.y - k.worldMin.y
            fm.hold = pad + V3(0, skids - 1, 0); fm.holdSpeed = 3      // under the pad: it settles on its skids
            if k.worldMin.y < pad.y + 0.3 && abs(k.vel.y) < 0.3 { ph = 6; t = 0; b.note("\(r.key) kestrel down on the pad") }
            else if t > 60 { ph = 6; t = 0; b.note("\(r.key) kestrel let down slowly") }
        default:
            fm.hold = nil                                         // engine off, the rotor runs down
            if t > 8 {
                // Stowed: the aircraft and its crew go inside.
                for st in FlightCrew.seats where st.ship === k { if let m = st.mob { mobs.mobs.removeAll { $0 === m } } }
                FlightCrew.seats.removeAll { $0.ship === k }
                ships.remove(k)
                done("stowed", cooldown: 30)
            }
        }
    }

    private func raiseAlert(_ r: inout BaseRecord, _ b: BaseWatch) {
        if r.alert.rawValue < BaseAlert.alert.rawValue { r.alert = .alert; r.calm = 0 }
    }
}

extension FlightCrew {
    // After a reload: the Capital soldiers sitting at an aircraft's crew stations take their seats again (the pilot
    // at the first, at the controls).
    static func relink(_ g: Game, _ s: Ship) {
        var taken = Set<ObjectIdentifier>()
        for (i, seat) in s.crewStations.enumerated() {
            let at = s.toWorld(seat)
            guard let m = g.mobs.mobs.first(where: { m in
                m.kind.steelhold && m.kind != .deckGun && m.health > 0 && !taken.contains(ObjectIdentifier(m)) && simd_length(m.pos - at) < 2.5
                    && (i > 0 || m.kind == .soldierCrew)
            }) else { if i == 0 { return } else { continue } }
            taken.insert(ObjectIdentifier(m))
            m.deck = s
            m.persistent = true
            m.station = i == 0 ? .seated : .passenger
            m.stationSeat = 0.45
            seats.append(Seat(mob: m, ship: s, local: seat))
        }
        // Back from a save in the air: the rotor was turning (its speed isn't saved) and it hovers where it is until
        // the citadel's next update sends it on (a reloaded Kestrel dropped out of the sky spinning up, basetest reload).
        if let fm = s.flight, seats.contains(where: { $0.ship === s }), fm.hold == nil {
            let x = Int(floor(s.pos.x)), z = Int(floor(s.pos.z))
            if g.world.isLoaded(x, z) && s.worldMin.y > Float(g.world.topY(x, z) + 3) {
                fm.rpm = 1
                fm.hold = s.pos
            }
        }
    }
}
