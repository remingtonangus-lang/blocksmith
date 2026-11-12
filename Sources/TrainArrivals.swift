import Foundation
import simd

// P508 (Remington, Nov 1 16:26: "for the trains, make sure we can see them in motion once in a while. make there be military
// trains with guns that are hostile and will obliterate the village you are at if it spawns, civilian with passengers you
// can rob, and cargo trains, and there is a 1/10 chance of one spawning every 10 minutes you are in a rail network area").
// Every line keeps its timetabled train, but a line is long and its one train is mostly somewhere else, so he never met
// one running. Now every ten minutes spent within 140 blocks of a line is a roll: one in ten, a train comes down that
// line toward him, its head 170 blocks up the track from the nearest point on it (the timetable moved to put it there,
// so it runs on from there as any train does). What comes is one of three, a third each:
//   civilian   the passenger train (coaches to ride, the express car's strongbox to rob)
//   cargo      the freight train (boxcars a held-up train opens)
//   military   a Greywall troop train, out for blood: its troops are roused from the start, its guard car fires on him,
//              and if he is in a town it halts there, puts its troops off and shells the buildings round him (a shell
//              every 2.5 s while its gun stands) until he has gone 120 blocks or the gun is silenced.
// The arrival lasts until the train is 240 blocks off; the line then runs its own kind again.
// P508 (same list, "one engine"): every railway train runs with one engine at its head (Trains.facing), not one at each end.
enum TrainArrivals {
    static let every: Double = 600
    static var chance: Float = 0.1
    static let approach: Float = 170
    static var near: Double = 0                       // seconds within reach of a line since the last roll
    static var kinds: [Int64: Trains.Kind] = [:]      // a line's arriving train's kind
    static var wreckers: Set<Int64> = []              // a military arrival, out to wreck the town he is in
    static var shellAt: [Int64: Double] = [:]
    static var rolls = 0, arrivals = 0, shells = 0    // (harness)

    static func kindFor(_ id: Int64) -> Trains.Kind? { kinds[id] }

    // Once a second (Trains.tick): the roll, and arrivals ended.
    static func tick(_ g: Game, near tracks: [Trains.Track]) {
        let p = g.player.pos
        for id in Array(kinds.keys) {
            guard let tr = Trains.trains[id] else { kinds[id] = nil; wreckers.remove(id); continue }
            let head = tr.track.point(Trains.now(tr).s)
            if simd_length(head - p) > max(240, Trains.reach(g) + 40) || tr.wrecked { kinds[id] = nil; wreckers.remove(id); shellAt[id] = nil }
        }
        guard g.dim.dim == .overworld, !tracks.isEmpty, g.alive else { return }
        near += 1
        guard near >= every else { return }
        near = 0
        rolls += 1
        guard Rand.float(in: 0..<1) < chance else { return }
        let k = [Trains.Kind.passenger, .cargo, .troop][Rand.int(in: 0..<3)]
        _ = arrive(g, tracks, kind: k)
    }

    static func alongFor(_ g: Game) -> Float { Trains.fogReach ? max(approach, Trains.reach(g) + 24) : approach }
    // Puts a train of `kind` on the nearest line, `approach` blocks up the track and running toward him.
    @discardableResult
    static func arrive(_ g: Game, _ tracks: [Trains.Track], kind: Trains.Kind) -> Trains.Train? {
        let p = g.player.pos
        var best: (Trains.Track, Int, Float)? = nil
        for t in tracks where !t.armoured {
            for (i, c) in t.cells.enumerated() where i % 2 == 0 {
                let d = simd_length(V2(Float(c.x) + 0.5 - p.x, Float(c.z) + 0.5 - p.z))
                if best == nil || d < best!.2 { best = (t, i, d) }
            }
        }
        guard let (t, i0, _) = best else { return nil }
        let n = t.cells.count
        // Up the line on the side with more track, so it has room to come.
        let up: Float = n - 1 - i0 >= i0 ? 1 : -1
        // (Week item 71: from past where trains are made at his view, so it comes into being out of his sight.)
        let along = alongFor(g)
        let target = max(0, min(Float(n - 1), Float(i0) + up * along))
        let wantDir: Float = -up
        // The timetable moment its head is there, running his way (not standing at a stop).
        var bestU = -1.0, bestErr = Float.infinity
        var u = 0.0
        while u < t.period {
            let a = t.at(u - t.phase)
            if a.stop == nil && a.dir == wantDir {
                let e = abs(a.s - target)
                if e < bestErr { bestErr = e; bestU = u }
            }
            u += 0.5
        }
        guard bestU >= 0 else { return nil }
        let tr = Trains.trains[t.id] ?? Trains.Train(t)
        Trains.trains[t.id] = tr
        // tr.time = g.time - delay must land on bestU - phase in the timetable's period.
        var delay = (g.time - (bestU - t.phase)).truncatingRemainder(dividingBy: t.period)
        if delay < 0 { delay += t.period }
        tr.delay = delay
        tr.time = g.time - tr.delay
        tr.wrecked = false
        tr.heldBy = false; tr.brake = 0; tr.stoppedFor = 0
        kinds[t.id] = kind
        if kind == .troop { wreckers.insert(t.id) } else { wreckers.remove(t.id) }
        arrivals += 1
        Trains.remove(g, tr)                           // (built afresh as the kind that comes)
        return tr
    }

    // A military arrival in a town: it halts by him, its troops get off, its gun shells the buildings round him.
    static func wreck(_ g: Game, _ tr: Trains.Train, gun: Mob, muzzle: V3) {
        let id = tr.track.id
        guard wreckers.contains(id), gun.health > 0, g.survival, g.alive else { return }
        let p = g.player.pos
        guard let lead = Trains.lead(tr), simd_length(lead.pos - p) < 120, inTown(g, p) else { return }
        tr.roused = true
        if simd_length(lead.pos - p) < 60 && !tr.heldBy { tr.heldBy = true; tr.stoppedFor = 0; Trains.whistle(g, tr) }
        tr.stoppedFor = 0                              // (held while he is in reach: the shelling goes on)
        let now = g.clock
        guard now - (shellAt[id] ?? -100) >= 2.5 else { return }
        shellAt[id] = now
        // A building block near him: something built (not ground, leaves or plants), out of the blast's reach of him.
        let w = g.world
        for _ in 0..<24 {
            let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 7..<30)
            let x = Int(floor(p.x + cosf(a) * r)), z = Int(floor(p.z + sinf(a) * r))
            for dy in stride(from: 8, through: -3, by: -1) {
                let y = Int(floor(p.y)) + dy
                let b = w.block(x, y, z)
                guard b != AIR, Blocks.collide[Int(b)], !SmoothTerrain.natural[Int(b)], !Blocks.isLiquid(b),
                      !Rails.isRail(b), !Blocks.key(Blocks.groupBase[Int(b)]).hasSuffix("_leaves") else { continue }
                let c = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
                g.addFlash(at: muzzle, color: V3(7, 4, 1.8), radius: 7, life: 0.08)
                g.sfx(.explodeSmall, 1, at: muzzle)
                Explosion.explode(at: c, power: 3.2, game: g, fire: Rand.float(in: 0..<1) < 0.3)
                shells += 1
                return
            }
        }
    }

    static func inTown(_ g: Game, _ p: V3) -> Bool {
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        if CapitalTown.city(g, x: x, z: z) != nil { return true }
        guard let sc = g.world.gen.structures, let s = sc.nearest("village", x: x, z: z, maxRegions: 1) else { return false }
        return abs(s.anchor.x - x) < 90 && abs(s.anchor.z - z) < 90
    }
}
