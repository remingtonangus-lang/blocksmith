import Foundation
import simd

// Crew firing from aboard (ridecheck ride: a disabled crawler's 22 crew all had the enemy soldiers beside the wreck as
// their foe and none fired a shot: every one stood in a room of the hull, pushing at its wall towards them). A disabled
// vehicle's crew (Mob.crewFree) with a foe it can't see from where it stands walks the hull to the nearest spot it can
// see the foe from: a deck edge, a hatch, the roof walkway, the lowered ramp. The way there is a path search in the
// hull's own frame (World.frame: the search reads its cells), never off its edge.
enum CrewLookout {
    static var nextSearch = 0.0                 // one search at a time across all crew (seconds, CFAbsoluteTime)
    static var found = 0, failed = 0            // (counters: ridecheck)
    static var spots = 0, hullClear = 0, worldClear = 0, noPath = 0
    static var lastMiss = ""                    // (ridecheck: the last search that found nothing, where it looked)
    static var ready: Bool { CFAbsoluteTimeGetCurrent() >= nextSearch }
    private static let reach = 22               // how far along the deck a spot is looked for (blocks, each way)
    static let oldRanges = ProcessInfo.processInfo.environment["BS_OLDLOOKOUT"] == "1"

    // The code reader's Nov 10 batch, 1 (questcheck --lookout, and the full suite): a crewman standing on a hull's top
    // layer, one on a torn-off piece two blocks high, and one 30 blocks off the grid each search and come back.
    static func check(_ g: Game, _ check: (Bool, String) -> Void) {
        let next0 = nextSearch
        defer { nextSearch = next0 }
        let plank = Blocks.id("oak_planks")
        func ship(_ sx: Int, _ sy: Int, _ sz: Int) -> Ship {
            let gr = ShipGrid(sx: sx, sy: sy, sz: sz)
            for z in 0..<sz { for x in 0..<sx { gr.set(x, 0, z, plank) } }
            let s = Ship(id: -77, grid: gr)
            s.rebuild()
            s.pos = g.player.pos + V3(0, 40, 0)
            return s
        }
        var lines: [String] = []
        var ok = true
        for (what, s, at) in [("on the top layer of a 6-high hull", ship(12, 6, 12), V3(6.5, 6.0, 6.5)),
                              ("on a torn-off piece 2 blocks high", ship(5, 2, 5), V3(2.5, 1.0, 2.5)),
                              ("30 blocks off the grid", ship(8, 4, 8), V3(40.5, 1.0, 40.5))] {
            let m = Mob(.soldierTrooper, at: s.toWorld(at))
            nextSearch = 0
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = walk(m, s, to: s.toWorld(at) + V3(60, 0, 0), g)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            ok = ok && ms < 500
            lines.append(String(format: "%@ %.1f ms", what, ms))
        }
        check(ok, "crew lookout: a crewman's search for a spot to fire from comes back (" + lines.joined(separator: "; ") + ")")
    }

    /// Sends `m` (aboard `s`) to a spot of the hull it can see `foe` from. True: it is on its way.
    static func walk(_ m: Mob, _ s: Ship, to foe: V3, _ g: Game) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        guard now >= nextSearch else { return false }
        nextSearch = now + 0.2
        let w = g.world
        let gr = s.grid
        let l = s.toLocal(m.pos)
        let fl = s.toLocal(foe)
        let fx = Int(floor(l.x)), fy = Int(floor(l.y + 0.05)), fz = Int(floor(l.z))
        let collide = Blocks.collide
        @inline(__always) func solid(_ x: Int, _ y: Int, _ z: Int) -> Bool { collide[Int(gr.get(x, y, z))] }
        // Standable cells on its own deck (a step up or down), nearest first.
        var cands: [(Int, IVec3)] = []
        // (thru: on a hull's top layer (fy >= sy - 1), on a piece 2 or fewer high (a torn-off part) or more than `reach`
        // off the grid, these ranges came out backwards: lo...hi with hi < lo ran on forever on the headset, a freeze.
        // BS_OLDLOOKOUT=1: the old height range, for the check's before.)
        let ys: AnySequence<Int> = oldRanges ? AnySequence(max(1, fy - 1)...min(gr.sy - 2, fy + 1)) : AnySequence(thru(max(1, fy - 1), min(gr.sy - 2, fy + 1)))
        for y in ys {
            for z in thru(max(0, fz - reach), min(gr.sz - 1, fz + reach)) {
                for x in thru(max(0, fx - reach), min(gr.sx - 1, fx + reach)) {
                    guard solid(x, y - 1, z), !solid(x, y, z), !solid(x, y + 1, z) else { continue }
                    let dx = x - fx, dz = z - fz, dy = y - fy
                    cands.append((dx * dx + dz * dz + dy * dy * 4, IVec3(x, y, z)))
                }
            }
        }
        cands.sort { $0.0 < $1.0 }
        spots += cands.count
        // A spot sees the foe when the line from its eye leaves the hull without meeting a block, then meets nothing
        // in the world (the ground, other hulls) on the rest of the way.
        let eyeH = m.height * 0.9
        var tried = 0, rays = 0
        for (_, c) in cands {
            if rays >= 400 || tried >= 3 { break }       // (hull rays are grid reads: 400 about 0.1 ms)
            rays += 1
            let e = V3(Float(c.x) + 0.5, Float(c.y) + eyeH, Float(c.z) + 0.5)
            let d = fl - e
            let len = simd_length(d)
            if len < 1 { continue }
            let dir = d / len
            var t: Float = 0.3, clear = true
            while t < len {
                let p = e + dir * t
                let ix = Int(floor(p.x)), iy = Int(floor(p.y)), iz = Int(floor(p.z))
                if !gr.inside(ix, iy, iz) { break }
                if solid(ix, iy, iz) { clear = false; break }
                t += 0.3
            }
            guard clear else { continue }
            hullClear += 1
            guard w.canSee(s.toWorld(e), foe) else { continue }
            worldClear += 1
            tried += 1
            let goal = V3(Float(c.x) + 0.5, Float(c.y), Float(c.z) + 0.5)
            if c.x == fx && c.z == fz && abs(c.y - fy) <= 1 { m.crewRoute = [goal]; m.crewLookout = true; found += 1; return true }
            // The way there: a path in the hull's frame (no ladders: a mob climbs them only in the world's frame).
            var pr = m.pathProfile(g)
            pr.climbs = false; pr.doors = false; pr.maxDrop = 1; pr.span = 1
            let was = w.frame
            w.frame = s
            let path = PathFinder.find(w, from: l, to: goal, profile: pr, maxNodes: 700)
            w.frame = was
            guard let p = path, let last = p.last, last.x == c.x, last.z == c.z, abs(last.y - c.y) <= 1 else { noPath += 1; continue }
            m.crewRoute = p.map { V3(Float($0.x) + 0.5, Float($0.y), Float($0.z) + 0.5) }
            m.crewLookout = true
            found += 1
            return true
        }
        failed += 1
        lastMiss = String(format: "from %ld,%ld,%ld (grid %ldx%ldx%ld) to the foe at %.1f,%.1f,%.1f: %ld spots, %ld rays", fx, fy, fz, gr.sx, gr.sy, gr.sz,
                          fl.x, fl.y, fl.z, cands.count, rays)
        return false
    }
}
