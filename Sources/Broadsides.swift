import Foundation
import simd

// D41: broadside battles and boarding by grapple.
//   broadsides  a sea vessel with guns along its sides (corsair sloops now carry two a side) that has a target in range
//               no longer just circles: it turns to bring the target abeam, holding off 22 to 45 blocks, and lets the
//               side that bears fire as one broadside. Your own hull's side guns do the same in your crew's hands
//               (GunCrew.swift).
//   boarding    hook an enemy vessel with a Grapple Line (SkyIsle.swift) and she's grappled: for 40 seconds her helm is
//               lashed, she drifts alongside you (or your ship), her guns can't depress onto you and you reel across.
//               Clear her crew and take her helm, and she's yours (captured, as before).
enum Broadsides {
    static let lashTime: Float = 40
    static var lashed: [Int: Float] = [:]          // ship id -> seconds of lashing left
    static var boarded = Set<Int>()                 // vessels whose deck you've set foot on (one toast each)
    static var volleys = 0, grapples = 0            // (harness)

    static func sideGuns(_ s: Ship) -> Bool { s.cannons.contains { abs($0.1.x) > 0.7 } }
    static func seaVessel(_ s: Ship) -> Bool { s.role == "sloop" || s.role == NavalPatrol.role }

    // Game.grappleUse: a hook set in a vessel's hull.
    static func hooked(_ g: Game, _ s: Ship) {
        guard s.isVessel, !s.captured, !s.wrecked, s.parent == nil else { return }
        if lashed[s.id] == nil {
            grapples += 1
            g.onToast?("Grappled! The \(s.name) is lashed: get aboard, clear her crew and take her helm.")
        }
        lashed[s.id] = lashTime
    }
}

extension ShipManager {
    // crewTick, per vessel: a grappled vessel drifts with you; true while it is held (no orders, no guns).
    func lashedTick(_ s: Ship, _ dt: Float, game g: Game) -> Bool {
        guard let left = Broadsides.lashed[s.id] else { return false }
        if left <= dt || s.wrecked || s.captured { Broadsides.lashed[s.id] = nil; return false }
        Broadsides.lashed[s.id] = left - dt
        s.autopilot = nil
        s.throttle = 0; s.steer = 0
        // Toward your ship (or you) until alongside, then with it.
        let mine = list.first { isYours($0) && simd_length($0.pos - s.pos) < 40 }
        let anchor = mine?.pos ?? g.player.pos
        let carry = mine?.vel ?? V3(0, 0, 0)
        var to = anchor - s.pos
        to.y = 0
        let d = simd_length(to)
        let close: V3 = d > 7 ? to / d * min(3, (d - 7) * 0.4) : V3(0, 0, 0)
        let want = V3(carry.x + close.x, s.vel.y, carry.z + close.z)
        s.vel += (want - s.vel) * min(1, dt * 1.5)
        for t in turrets(of: s) { t.aimAt = nil }
        if aboard === s && !Broadsides.boarded.contains(s.id) {
            Broadsides.boarded.insert(s.id)
            g.onToast?("Boarders away!")
        }
        return true
    }

    // crewTick: steer to bring the target abeam (nil: no broadside to fight, the circling steer stands).
    func broadsideSteer(_ s: Ship, target p: V3) -> Float? {
        guard Broadsides.seaVessel(s), Broadsides.sideGuns(s) else { return nil }
        let to = V2(p.x - s.pos.x, p.z - s.pos.z)
        let d = simd_length(to)
        guard d > 6 && d < 95 else { return nil }
        let f = s.dirToWorld(s.fwd)
        let fh = simd_normalize(V2(f.x, f.z) + V2(1e-5, 0))
        // Land ahead: the circling steer (which puts the helm over) knows better.
        let ahead = s.pos + V3(fh.x, 0, fh.y) * 26
        let ax = Int(floor(ahead.x)), az = Int(floor(ahead.z))
        if world.isLoaded(ax, az) && !Blocks.isLiquid(world.rawBlock(ax, world.topY(ax, az), az)) { return nil }
        let u = to / d
        let a = V2(-u.y, u.x), b = V2(u.y, -u.x)
        var want = simd_dot(a, fh) >= simd_dot(b, fh) ? a : b
        if d > 45 { want = simd_normalize(want + u * 0.8) } else if d < 22 { want = simd_normalize(want - u * 0.8) }
        let cross = fh.x * want.y - fh.y * want.x
        return max(-1, min(1, cross * 2))
    }

    // crewTick, on a volley: the side guns that bear at the target fire together.
    func broadside(_ s: Ship, target p: V3, game g: Game) {
        guard Broadsides.seaVessel(s), s.reload <= 0 else { return }
        for (c, dir) in s.cannons where abs(dir.x) > 0.7 {
            let muzzle = s.toWorld(c)
            let d = p - muzzle
            let horiz = simd_length(V2(d.x, d.z))
            guard horiz >= 10 else { continue }
            let md = s.dirToWorld(dir)
            let a = simd_normalize(V2(md.x, md.z) + V2(1e-5, 0)), b = simd_normalize(V2(d.x, d.z) + V2(1e-5, 0))
            if acosf(max(-1, min(1, simd_dot(a, b)))) < 0.25 {
                if fireHull(s, pitch: ShipManager.elevation(horiz, d.y), game: g) > 0 { Broadsides.volleys += 1 }
                return
            }
        }
    }
}
