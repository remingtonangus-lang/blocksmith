import Foundation
import simd

// Nov 12 playtest (06:36:53-06:37:04, aboard an Ironback Crawler he had shot to a standstill: "I'm not able to man this
// gun, but I should be able to... There's still an operational gun here, but I can't use it"). Every gun of a capital
// hull has its station inside, a Command Console with a chair (GunStations.swift, P512), worked by the crew and his
// companions. Now he works one too: the console of a gun's station, used on a hull he holds or one whose crew can no
// longer stop him (its driver dead, or the hull disabled), seats him in its chair, and that one gun follows his look
// and fires on the trigger from the hull's magazine, the hull disabled or not; sneak leaves, standing at the chair.
// BS_OLDGUNSTATION=1: the console does nothing, as before.
enum GunStationPlay {
    static let old = ProcessInfo.processInfo.environment["BS_OLDGUNSTATION"] == "1"
    struct Seat { @WeakLink var hull: Ship?; @WeakLink var turret: Ship?; var chair: IVec3; var settled = false }
    static var cur: Seat?
    static var shots = 0                          // (harness: rounds he fired from stations)
}

extension Game {
    // The use button on a console of hull `hit` at `cell`. True when it was a gun station's (taken, or refused aloud).
    func takeGunStation(_ hit: Ship, _ cell: IVec3) -> Bool {
        let ships = world.ships
        guard !GunStationPlay.old, GunStationPlay.cur == nil, ships.pilot == nil, Turrets.shared.manned == nil else { return false }
        let v = hit.root
        guard hit === v, v.kinematic, v.role != nil else { return false }
        var found: (Ship, IVec3)?
        for t in ships.turrets(of: v) {
            if let st = VehicleGunners.station(t, on: v, ships), st.console == cell { found = (t, st.chair); break }
        }
        guard let (t, chair) = found else { return false }
        let at = v.toWorld(V3(Float(cell.x) + 0.5, Float(cell.y) + 0.5, Float(cell.z) + 0.5))
        guard v.captured || v.wrecked || ships.canCommandeer(v) else {
            sfx(.click, 0.6, at: at)
            onToast?("Gun Control: the \(v.name)'s crew hold this gun")
            return true
        }
        guard !t.cannons.isEmpty else {
            sfx(.click, 0.6, at: at)
            onToast?("Gun Control: this gun is out of action")
            return true
        }
        v.captured = true                            // (hers to him now: her own crew no longer lay it)
        ChairSeat.shared.release()
        GunStationPlay.cur = GunStationPlay.Seat(hull: v, turret: t, chair: chair)
        sfx(.helmTake, 0.6, at: at)
        onToast?("Gun Control: the \(v.name)'s gun, worked from here")
        return true
    }

    func leaveGunStation() {
        guard let c = GunStationPlay.cur else { return }
        GunStationPlay.cur = nil
        c.turret?.aimAt = nil
        guard let v = c.hull else { return }
        // On his feet at the chair (its seat is under a block high: he steps off it).
        player.pos = v.toWorld(V3(Float(c.chair.x) + 0.5, Float(c.chair.y) + 0.7, Float(c.chair.z) + 0.5))
        player.vel = v.velocity(at: player.pos)
        world.ships.aboard = v
    }

    // In the chair, each tick: held there as the hull moves, the gun laid on his look. False when he no longer sits.
    func gunStationTick(_ mi: MoveInput, _ dt: Float) -> Bool {
        guard var c = GunStationPlay.cur else { return false }
        let ships = world.ships
        guard alive, let v = c.hull, let t = c.turret, t.parent === v, ships.list.contains(where: { $0 === t }), !t.cannons.isEmpty else {
            leaveGunStation(); return false
        }
        let seat = v.toWorld(V3(Float(c.chair.x) + 0.5, Float(c.chair.y) + 0.1, Float(c.chair.z) + 0.5))
        // Teleported, respawned or knocked away (after the first tick, which brings him to the chair), or sneak: up.
        if mi.sneak || (c.settled && simd_length(seat - player.pos) > 4) { leaveGunStation(); return false }
        c.settled = true
        GunStationPlay.cur = c
        player.pos = seat
        player.vel = v.velocity(at: seat)
        player.onGround = true
        player.airPeak = seat.y
        player.flying = false
        ships.aboard = v
        t.gunPitch = max(t.pitchMin, min(t.pitchMax, player.pitch + 0.05))
        var rel = player.yaw - v.yaw
        while rel > .pi { rel -= 2 * .pi }
        while rel < -.pi { rel += 2 * .pi }
        t.aimAt = nil
        t.aimYaw = rel
        return true
    }

    // The trigger in the chair: the gun fires as it reloads while held, from the hull's magazine.
    func gunStationFire(breakNow: Bool, breakHeld: Bool) {
        guard let c = GunStationPlay.cur, let v = c.hull, let t = c.turret, breakNow || breakHeld, t.reload <= 0 else { return }
        let ships = world.ships
        let st = ships.capState[v.id]
        if let st, st.rounds < 0 { st.rounds = Capital.magazine(v, barrels: ([v] + ships.turrets(of: v)).reduce(0) { $0 + $1.cannons.count }) }
        if let st, st.rounds <= 0 {
            if breakNow { onToast?("The magazine is empty"); sfx(.click, 0.5) }
            return
        }
        let fired = ships.fire(t, pitch: t.gunPitch, game: self, laid: true)
        if fired > 0 { swing = 1; GunStationPlay.shots += fired }
        if let st { st.rounds = max(0, st.rounds - fired) }
    }
}

// questcheck --gunstation: on an Ironback Crawler shot to a standstill (wrecked), he takes a gun's station by its
// console, the gun swings onto his look and fires on the trigger; sneak leaves; a live crew's hull refuses him.
enum GunStationCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, ships = w.ships
        let n1 = ships.list.count
        let home = g.player.pos + V3(0, 0, 140)
        ships.spawnCapital("crawler", home: IVec3(Int(home.x), 0, Int(home.z)), yaw: 0, region: nil, sync: true)
        guard let v = ships.list.dropFirst(n1).first(where: { $0.role == "crawler" }), let st = ships.capState[v.id] else {
            check(false, "gunstation: a crawler spawns"); return
        }
        let p0 = g.player.pos, survival0 = g.survival
        defer { if GunStationPlay.cur != nil { g.leaveGunStation() }; ships.remove(v); ships.capState.removeValue(forKey: v.id); g.player.pos = p0; g.survival = survival0 }
        _ = w.loadSync(center: v.pos, radius: 3)
        let guns = ships.turrets(of: v).filter { !$0.cannons.isEmpty }
        guard let (t, seat) = guns.lazy.compactMap({ t in VehicleGunners.station(t, on: v, ships).map { (t, $0) } }).first else {
            check(false, "gunstation: a crawler gun has a station (\(guns.count) guns)"); return
        }
        g.survival = true; g.alive = true
        // A live crew's hull (its driver at the helm): refused.
        let crewed = !ships.canCommandeer(v)
        let refused = crewed && g.takeGunStation(v, seat.console) && GunStationPlay.cur == nil
        let dt: Float = 1.0 / 72
        // Shot to a standstill, with him 70 blocks off in the open: it fights on with the guns its gunners hold.
        v.wrecked = true; st.disabledWhy = "engines destroyed"
        let fx = Int(floor(v.pos.x)) + 70, fz = Int(floor(v.pos.z))
        g.player.pos = V3(Float(fx) + 0.5, Float(w.topY(fx, fz)) + 1, Float(fz) + 0.5)
        let ids = Set(ships.turrets(of: v).map { $0.id })
        var volleys = 0
        for _ in 0..<(72 * 10) {
            let n0 = ships.shells.count
            ships.update(dt, game: g)
            volleys += ships.shells.dropFirst(min(n0, ships.shells.count)).filter { ids.contains($0.owner) }.count
        }
        print("gunstation: a stopped crawler's guns fired \(volleys) rounds at him in 10 s")
        check(volleys > 0 || ShipManager.oldWreckGuns, "gunstation: a crawler stopped where it stands fights on with its manned guns (\(volleys) rounds in 10 s)")
        // Then he boards her and takes a gun's station.
        let taken = g.takeGunStation(v, seat.console) && GunStationPlay.cur != nil
        // He looks 90 degrees off the gun's present bearing, a little up.
        let f0 = t.dirToWorld(V3(0, 0, -1))
        let want = atan2f(-f0.x, -f0.z) + .pi / 2
        g.player.yaw = want; g.player.pitch = 0.1
        var sat = 0
        for _ in 0..<(72 * 4) {
            if g.gunStationTick(MoveInput(), dt) { sat += 1 }
            ships.update(dt, game: g)
        }
        let f = t.dirToWorld(V3(0, 0, -1))
        var off = atan2f(-f.x, -f.z) - want
        while off > .pi { off -= 2 * .pi }
        while off < -.pi { off += 2 * .pi }
        let seatW = v.toWorld(V3(Float(seat.chair.x) + 0.5, Float(seat.chair.y) + 0.1, Float(seat.chair.z) + 0.5))
        let inChair = simd_length(g.player.pos - seatW) < 0.2
        let shots0 = GunStationPlay.shots, shells0 = ships.shells.count
        for _ in 0..<(72 * 6) {
            _ = g.gunStationTick(MoveInput(), dt)
            g.gunStationFire(breakNow: false, breakHeld: true)
            ships.update(dt, game: g)
        }
        let fired = GunStationPlay.shots - shots0
        var sneak = MoveInput(); sneak.sneak = true
        let left = !g.gunStationTick(sneak, dt) && GunStationPlay.cur == nil
        print("gunstation: driver alive \(crewed), refused \(refused), taken wrecked \(taken), sat \(sat) ticks in the chair (\(inChair)), gun \(String(format: "%.2f", abs(off))) rad off his look, fired \(fired) (shells \(ships.shells.count - shells0) in the air), left \(left)")
        check(refused && taken, "gunstation: a crewed crawler's gun station refuses him; a disabled one's takes him (\(refused), \(taken))")
        check(inChair && abs(off) < 0.1, String(format: "gunstation: in the gun's chair (%@) the gun swings onto his look (%.2f rad off)", inChair ? "yes" : "no", abs(off)))
        check(fired >= 2 && left, "gunstation: the gun fires as it reloads on the held trigger (\(fired)) and sneak leaves the chair (\(left))")
    }
}
