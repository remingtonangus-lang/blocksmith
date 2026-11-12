import Foundation
import simd

// C1 trains (Railways.swift lays the lines):
//   Timetable  one steam train per line shuttles end to end, stopping `dwell` seconds at every station, on a
//              timetable of world time (Game.time), so it is wherever the clock says even while nobody watches.
//              Near the player (and loaded) it is three cars, a locomotive, a coach and an express car, moved along
//              the track every frame (minecart mobs, variant 10+, never saved: a reload rebuilds them).
//   Riding     use the coach to take a seat (sneak to get off); it carries you down the line.
//   Tickets    the TICKETS sign at a station sells a fare to every other station on the line: the journey passes
//              in a fade (the clock moves on by the trip) and you step off on that platform. Fast travel.
//   Robbery    hold up the driver (a gun on the locomotive, 20 blocks or nearer, for 1.5 s) or block the track ahead
//              and the train brakes to a stop; crack the express car's strongbox (use it five times, or once with
//              TNT in hand) for the line's takings. A crime: honour down, a bounty in the nearest town and a posse of
//              five rides out (outrun them, or pay up as for any bounty). The train runs again once you are 48 blocks
//              off or a minute has passed; that train carries no money for the rest of the day.
//   The Vault  armoured trains (an armoured locomotive and a gun car) shuttle the Ash Vault's four lines between the
//              citadel halt and each garrison town; the gun car's turret fires on you; explosives wreck it.
enum Trains {
    static let ticketWord = "TICKETS"
    static var speed: Float = 7                 // average blocks a second between stops
    static let dwell: Double = 24
    static let gap: Float = 3.6                 // between car centres
    static let carScale: Float = 2
    static let loco = 10, coach = 11, express = 12, armouredLoco = 13, gunCar = 14
    static let crackUses = 5
    static let robBounty = 8000, robHonour: Float = -15
    static let holdUpTime: Float = 1.5
    static let fareCentsPerBlock = 2           // a fare: 2 cents a block of track, at least $1

    static func isCar(_ m: Mob) -> Bool { m.kind == .minecart && m.variant >= loco }
    static var placed: [IVec3: Double] = [:]    // P510: blocks he placed lately (Game.placedReactions), by world time
    static var cleared = 0                      // (checks: strays a train cleared off its rail)

    // A track a train runs: rail cells in order, the y of each cell's rail top, the stops (cell indices) and names.
    final class Track {
        let id: Int64
        let name: String
        let cells: [IVec3]
        let ys: [Float]
        let stops: [Int]
        let stopNames: [String]
        let armoured: Bool
        let dim: Dim
        var shapes: [Int]? = nil                // (a line's rail shapes: P510, a stray block on the line is cleared and the rail put back)
        var parts: [Railways.Line] = []         // P510: the lines and links it runs, west to east (a through train's: several)
        var through = false
        var cyclic = false                      // P511 (RailLoops.swift): a circuit, round and round, never turning
        var source = 0                          // (the line's cell count it was made from: the cache's check)
        // The timetable: (start, duration, from, to) over one period; from == to is a dwell.
        let legs: [(Double, Double, Float, Float)]
        let period: Double
        let phase: Double
        init(id: Int64, name: String, cells: [IVec3], slopes: [Bool], stops: [Int], stopNames: [String], armoured: Bool, dim: Dim,
             heights: [Float]? = nil, cyclic: Bool = false) {
            self.id = id; self.name = name; self.cells = cells; self.stops = stops; self.stopNames = stopNames
            self.armoured = armoured; self.dim = dim; self.cyclic = cyclic
            // (P379 step 3: a field world's line runs at its planned heights, the drawn track's.)
            ys = heights?.map { $0 + 0.0625 } ?? cells.indices.map { Float(cells[$0].y) + (slopes[$0] ? 0.5 : 0) + 0.0625 }
            var legs: [(Double, Double, Float, Float)] = [], t: Double = 0
            // A line runs out and back (its ends turn it round); a circuit runs on round (the last stop's leg ends at
            // the first stop a lap on).
            let order = cyclic ? stops : stops + stops.reversed().dropFirst().dropLast()
            for k in 0..<order.count {
                let a = order[k]
                let b = cyclic && k + 1 == order.count ? order[0] + cells.count : order[(k + 1) % order.count]
                legs.append((t, Trains.dwell, Float(a), Float(a))); t += Trains.dwell
                let d = Double(abs(b - a)) / Double(Trains.speed * (armoured ? 1.3 : 1))
                legs.append((t, d, Float(a), Float(b))); t += d
            }
            self.legs = legs
            period = max(1, t)
            phase = Double(hashf(Int(truncatingIfNeeded: id), Int(truncatingIfNeeded: id >> 32), 0x7A1, 0x5EED)) * max(1, t)
        }
        // Where the train's head is at timetable time t: its cell position, its heading (+1 up the cells, -1 down)
        // and the stop it stands at, if any.
        func at(_ t: Double) -> (s: Float, dir: Float, stop: Int?) {
            var u = (t + phase).truncatingRemainder(dividingBy: period)
            if u < 0 { u += period }
            var i = legs.firstIndex { u < $0.0 + $0.1 } ?? (legs.count - 1)
            let (t0, d, a, b) = legs[i]
            if a == b {
                // A dwell: heading for the next leg (the locomotive runs round at the terminus in the first second).
                i = (i + 1) % legs.count
                let n = legs[i]
                return (a, n.3 > n.2 ? 1 : -1, stops.firstIndex(of: Int(a)))
            }
            // Ease in and out of each stop (no speed at either end).
            let f = Float(max(0, min(1, (u - t0) / d)))
            let e = f - sinf(2 * .pi * f) / (2 * .pi)
            return (wrap(a + (b - a) * e), b > a ? 1 : -1, nil)
        }
        // A circuit's place taken round to [0, cells): a lap on is the same place.
        func wrap(_ s: Float) -> Float {
            guard cyclic else { return s }
            let n = Float(cells.count)
            let r = s.truncatingRemainder(dividingBy: n)
            return r < 0 ? r + n : r
        }
        // The change in place from a to b (on a circuit, the short way round past its seam).
        func delta(_ a: Float, _ b: Float) -> Float {
            var d = b - a
            if cyclic { let n = Float(cells.count); if d > n / 2 { d -= n } else if d < -n / 2 { d += n } }
            return d
        }
        func cell(_ s: Float) -> IVec3 {
            let n = cells.count
            if cyclic { return cells[min(n - 1, Int(wrap(s.rounded())))] }
            return cells[max(0, min(n - 1, Int(s.rounded())))]
        }
        func point(_ s: Float) -> V3 {
            let n = cells.count
            if cyclic {
                let w = wrap(s)
                let i = min(n - 1, Int(w)), f = w - Float(i), k = (i + 1) % n
                let a = cells[i], b = cells[k]
                let pa = V3(Float(a.x) + 0.5, ys[i], Float(a.z) + 0.5), pb = V3(Float(b.x) + 0.5, ys[k], Float(b.z) + 0.5)
                return pa + (pb - pa) * f
            }
            let s = max(0, min(Float(n - 1), s))
            let i = min(n - 2, Int(s)), f = s - Float(i)
            let a = cells[i], b = cells[i + 1]
            let pa = V3(Float(a.x) + 0.5, ys[i], Float(a.z) + 0.5), pb = V3(Float(b.x) + 0.5, ys[i + 1], Float(b.z) + 0.5)
            return pa + (pb - pa) * f
        }
    }

    final class Train {
        var track: Track                        // (P510: a through train moves on to a longer track as it runs on)
        var delay: Double = 0                   // seconds the train has stood still off its timetable
        var brake: Float = 0                    // 0 running ... 1 stopped (a hold-up or a blocked track)
        var throttle: Float = 1                 // P337: the cab's regulator, -1 (backing) ... 2 (twice the timetable)
        var cabBrake: Float = 0                 // P379 step 2: the driver's brake, 0 off ... 1 full on
        var rate: Float = 1                     // P379: the pace the train runs its timetable at (the regulator and the
                                                // brake change it gradually: a train has weight)
        var blocksPerSec: Float = 0             // (the cab's speed gauge)
        var stoppedFor: Float = 0
        var holdUp: Float = 0
        var heldBy = false                      // the player stopped it (a hold-up or a block on the line)
        var heldWay: Float = 0                  // driven: the way it was going when his block stopped it (0: both ways)
        var cars: [Mob] = []
        var cracks = 0
        var robbedDay = -1
        var wrecked = false
        var gunCool: Float = 2
        var bullion = false                     // D47: today's run is a bullion train (VaultObjectives.swift)
        var gunSilenced = false                 // Q2: the guard car's fall was announced
        var raid: [Mob] = []                    // D50 (TrainRoofs.swift): robbers holding the train up
        var raidT: Float = 0
        var raidedDay = -1
        var roofAt: Double = -1e9               // when the player last stood on one of its roofs
        var chuff: Float = 0
        var lastS: Float = 0
        // P470 part 2 (TrainCars.swift): a real-size train's kind, its cars' places along it (variant, turned round,
        // offset of the car's middle from the train's, blocks along the track), its length, the way it runs, each
        // car's place on the track this frame, and the soldiers riding it.
        var kind: Kind = .passenger
        var layout: [(Int, Bool, Float)] = []
        var length: Float = 0
        var dir: Float = 1
        var carS: [Float] = []
        var troops: [Mob] = []
        var passengers: [Mob] = []              // FAILURES 3 (TrainHulls.swift): townsfolk riding the coaches
        var roused = false
        var facing: Float = 1                   // P508: the way the one engine faces (layout mirrored when -1)
        var fresh = true                        // (just built: it takes the timetable's heading at once)
        var taken = false                       // P510 (MilitaryTrain.swift): a troop train he cleared and took
        // Nov 12 playtest (Trains.driveCab): driven from the cab the train is his, off the timetable: where it is on
        // the track, the way the engine faces along it (+1 up the cells), its speed that way (blocks a second; less
        // than 0 backing) and the coal in its tender (lumps).
        var driven = false
        var driveS: Float = 0
        var driveFwd: Float = 1
        var driveV: Float = 0
        var coal: Float = Trains.tenderStart
        init(_ t: Track) {
            track = t
            if let st = Trains.saved[t.id] { delay = st.delay; robbedDay = st.robbedDay; wrecked = st.wrecked }
        }
        var time: Double = 0                    // timetable time (Game.time less the delay), set each frame
    }
    static var trains: [Int64: Train] = [:]
    static var carOf: [ObjectIdentifier: (Train, Int)] = [:]

    // MARK: Tracks

    static func track(_ l: Railways.Line) -> Track {
        let slopes = l.cells.indices.map { (2...5).contains(l.shape($0)) }
        let t = Track(id: l.id, name: l.name, cells: l.cells, slopes: slopes, stops: l.stations.map { $0.index },
                      stopNames: l.stations.map { $0.name + " Station" }, armoured: false, dim: .overworld, heights: l.heights)
        t.shapes = l.cells.indices.map { l.shape($0) }
        t.parts = [l]
        t.source = l.cells.count
        return t
    }
    private static var tracks: [Int64: Track] = [:]
    // P511: with a loop planned at each end (RailLoops.swift), the line's track is its circuit (gen: nil, the line as
    // laid). A loop still being planned leaves the line's own track until it is.
    static func cachedTrack(_ l: Railways.Line, gen: WorldGen? = nil) -> Track {
        let loops = gen.map { Railways.loops($0, l, wait: false) }
        let want = loops?.west != nil && loops?.east != nil
        if let t = tracks[l.id], t.source == l.cells.count, t.cyclic == want { return t }
        var t = track(l)
        if want, let lw = loops?.west, let le = loops?.east, let c = cyclicTrack(l, west: lw, east: le) { t = c }
        tracks[l.id] = t
        if tracks.count > 64 { tracks.removeAll(); tracks[l.id] = t }
        return t
    }
    // The Ash Vault's four lines, citadel halt to town (AshVault.swift runs 0-3, flat at the vault floor).
    static let vaultTracks: [Track] = (0..<4).map { ri in
        let r = AshWar.railRuns[ri]
        let cells = (r.a...r.b).map { t -> IVec3 in let c = AshWar.cell(r, t); return IVec3(c.x, AshWar.ground + 1, c.z) }
        let hs = AshWar.halts.filter { $0.run == ri }
        let stops = hs.map { h in h.from + h.dir * (AshWar.haltLength / 2) - r.a }.map { max(4, min(cells.count - 5, $0)) }.sorted()
        let names = stops.map { s in hs.min { abs($0.from + $0.dir * (AshWar.haltLength / 2) - r.a - s) < abs($1.from + $1.dir * (AshWar.haltLength / 2) - r.a - s) }!.name }
        return Track(id: Int64(-1 - ri), name: "Ashguard Rail", cells: cells, slopes: cells.map { _ in false }, stops: stops,
                     stopNames: names, armoured: true, dim: .deep)
    }

    // Tracks within `r` blocks of p in this dimension.
    static func tracksNear(_ g: Game, _ p: V3, _ r: Int) -> [Track] {
        switch g.dim.dim {
        case .overworld:
            guard let gen = g.world.gen as? WorldGen else { return [] }
            let x = Int(floor(p.x)), z = Int(floor(p.z))
            return Railways.near(gen, x0: x - r, z0: z - r, x1: x + r, z1: z + r, pad: r, wait: false).map { cachedTrack($0, gen: gen) }   // (P440: never plans on the frame)
        case .deep:
            guard DeepGen.inVault(p.y) else { return [] }
            return vaultTracks.filter { t in
                let a = t.cells.first!, b = t.cells.last!
                return p.x > Float(min(a.x, b.x) - r) && p.x < Float(max(a.x, b.x) + r) && p.z > Float(min(a.z, b.z) - r) && p.z < Float(max(a.z, b.z) + r)
            }
        default: return []
        }
    }

    // P337 step 6: what a world's save keeps of its trains (trains.json): how far each runs behind its timetable (a
    // driven or held train), the day it was last robbed and whether it was wrecked. The rest follows the world's clock.
    struct SavedTrain: Codable { var id: Int64; var delay: Double; var robbedDay: Int; var wrecked: Bool }
    static var saved: [Int64: SavedTrain] = [:]
    static func load(_ w: World) {
        // (Opening the overworld, a new world or back from another dimension: the trains start over from its save.)
        if w.dim == .overworld { saved.removeAll(); trains.removeAll(); carOf.removeAll() }
        guard let s = w.save, let d = try? Data(contentsOf: s.dir.appendingPathComponent("trains.json")),
              let list = try? JSONDecoder().decode([SavedTrain].self, from: d) else { return }
        for t in list {
            saved[t.id] = t
            if let tr = trains[t.id] { tr.delay = t.delay; tr.robbedDay = t.robbedDay; tr.wrecked = t.wrecked }
        }
    }
    static func save(_ w: World, background: Bool = false) {
        guard let s = w.save else { return }
        for tr in trains.values where tr.track.dim == w.dim && !tr.track.through {
            saved[tr.track.id] = SavedTrain(id: tr.track.id, delay: tr.delay, robbedDay: tr.robbedDay, wrecked: tr.wrecked)
        }
        let mine = saved.values.filter { v in trains[v.id].map { $0.track.dim == w.dim } ?? true }
            .filter { $0.delay != 0 || $0.robbedDay >= 0 || $0.wrecked }
        if mine.isEmpty && !FileManager.default.fileExists(atPath: s.dir.appendingPathComponent("trains.json").path) { return }
        SaveIO.write(mine.sorted { $0.id < $1.id }, to: s.dir.appendingPathComponent("trains.json"), background: SaveIO.queued(background))
    }

    // MARK: Ticking

    // Once a second: trains near the player are built as cars, far ones taken away; strays (a reload) go too.
    // Week item 71 (no pop-in): how far off a train is made and taken away: past the fog's end at his view (render
    // distance x 16 less 12), 128 at least. At 128 a train came into being in plain sight at any view past 8 (the
    // headset's auto view runs 8 to 16: the fog ends 148 to 244 out).
    static let fogReach = ProcessInfo.processInfo.environment["BS_TRAINREACH"] != "0"      // (the check's before: =0)
    static func reach(_ g: Game) -> Float { fogReach ? max(128, Float(g.world.renderDistance * CS) + 4) : 128 }
    static func tick(_ g: Game) {
        let p = g.player.pos
        var want: Set<Int64> = []
        let R = reach(g)
        let nearTracks = tracksNear(g, p, Int(R) + 12)
        TrainArrivals.tick(g, near: nearTracks)          // P508: one in ten every ten minutes, a train comes his way
        // P510: a through train he rides runs on, line after line; the line it left has no train of its own meanwhile.
        if let r = g.riding, isCar(r), let (tr, _) = carOf[ObjectIdentifier(r)] { through(g, tr) }
        for (id, tr) in trains where tr.track.through && !tr.cars.isEmpty {
            let aboard = g.riding.map { r in tr.cars.contains { $0 === r } } ?? false
            if aboard || simd_length(tr.track.point(tr.lastS) - p) < R + 32 { want.insert(id) }
        }
        for t in nearTracks {
            if let o = throughOut[t.id], trains[o]?.cars.isEmpty == false {
                if let own = trains[t.id], !own.cars.isEmpty { remove(g, own) }
                continue
            }
            let tr = trains[t.id] ?? Train(t)
            trains[t.id] = tr
            // P511: the line's track became its circuit (its loops planned): the train runs that from now on.
            if tr.track !== t && !tr.track.through {
                if !tr.cars.isEmpty { remove(g, tr) }
                tr.track = t; tr.fresh = true; tr.carS = []
            }
            if tr.wrecked { continue }
            tr.time = g.time - tr.delay
            let at = now(tr)
            let head = t.point(at.s)
            // (and a built train stays while its tail is still in reach: one running away from him went with its last
            // cars in sight when its head passed the line)
            let tail = t.point(at.s - at.dir * tr.length)
            guard simd_length(head - p) < R || (!tr.cars.isEmpty && simd_length(tail - p) < R) else { continue }
            // Only where the track was laid (ground a save had generated before keeps no rails).
            let c0 = t.cells[max(0, min(t.cells.count - 1, Int(at.s)))]
            guard g.world.isLoaded(c0.x, c0.z), Rails.isRail(g.world.block(c0.x, c0.y, c0.z)) else { continue }
            want.insert(t.id)
            if tr.cars.isEmpty || tr.cars.contains(where: { $0.health <= 0 && !t.armoured && !tr.bullion && tr.kind != .troop }) || !tr.cars.allSatisfy({ m in g.mobs.mobs.contains { $0 === m } }) {
                build(g, tr)
            }
        }
        for (id, tr) in trains where !want.contains(id) && !tr.cars.isEmpty {
            remove(g, tr)
            if tr.track.through { trains[id] = nil; throughOut = throughOut.filter { $0.value != id } }
        }
        // Cars not in a train (a save's leftovers) go.
        g.mobs.mobs.removeAll { isCar($0) && carOf[ObjectIdentifier($0)] == nil }
        // A held train with the player gone, or a minute on, runs again.
        for tr in trains.values where !tr.cars.isEmpty { raidTick(g, tr); troopTick(g, tr) }       // D50: hold-ups of the train you ride
        for tr in trains.values where tr.heldBy && tr.raid.isEmpty {
            tr.stoppedFor += 1
            let far = lead(tr).map { simd_length($0.pos - p) > 48 } ?? true
            if far || tr.stoppedFor > 60 { tr.heldBy = false; tr.brake = 0; tr.stoppedFor = 0; tr.holdUp = 0 }
        }
        if trains.count > 48 { for (id, tr) in trains where tr.cars.isEmpty && !want.contains(id) { trains[id] = nil } }
    }

    // MARK: P510 through trains

    // P510 (Nov 1 20:38:50: "this whole thing where it stops, I don't like that. It can't stop... The train doesn't stop.
    // It goes on forever"): the train he rides runs on past its line's end. Within 200 blocks of the end of its track,
    // heading that way, where the line runs on by a link (Railways.link) to the next line along the row, the train moves
    // onto a longer track: the lines and links it runs, the next ones added ahead and those well behind dropped. Its
    // timetable is the longer track's, taken up at the place and heading it has, so it runs on without a jolt and stops
    // at the stations ahead; the line it left builds no train of its own while this one is out.
    static var throughOut: [Int64: Int64] = [:]       // a line's id -> the through train out on it
    static var nextThrough: Int64 = 1 << 61
    static var splices = 0                            // (checks)
    static func through(_ g: Game, _ tr: Train) {
        guard let gen = g.world.gen as? WorldGen, !tr.track.armoured, !tr.track.cyclic, tr.track.dim == .overworld, !tr.track.parts.isEmpty else { return }
        let t = tr.track
        let n = t.cells.count
        let s = tr.lastS, d = now(tr).dir
        var parts = t.parts
        var shift = 0                                  // cells the new track starts east (+) or west (-) of the old
        if d > 0 && Float(n - 1) - s < 200 {
            let last = parts[parts.count - 1]
            if Railways.isLink(last.id) {
                guard let b = Railways.linkTarget(gen, last, wait: false) else { return }
                parts.append(b)
            } else {
                let (row, st) = Railways.rowStretch(last.id)
                guard let lk = Railways.link(gen, row: row, stretch: st, wait: false), let b = Railways.linkTarget(gen, lk, wait: false) else { return }
                parts += [lk, b]
            }
            while parts.count > 2 && shift + parts[0].cells.count < Int(s) - 300 { shift += parts[0].cells.count; parts.removeFirst() }
        } else if d < 0 && s < 200 {
            let first = parts[0]
            let (row, st) = Railways.rowStretch(first.id)
            var prev: [Railways.Line] = []
            if Railways.isLink(first.id) {
                guard let a = Railways.line(gen, row: row, stretch: st, wait: false) else { return }
                prev = [a]
            } else {
                // (the line and link that run into its west end: from its own row, or south from the row north)
                guard let (a, lk) = Railways.incoming(gen, row, st, wait: false) else { return }
                prev = [a, lk]
            }
            let add = prev.reduce(0) { $0 + $1.cells.count }
            parts = prev + parts
            shift = -add
            var total = parts.reduce(0) { $0 + $1.cells.count }
            while parts.count > 2 && total - parts[parts.count - 1].cells.count > Int(s) + add + 300 {
                total -= parts[parts.count - 1].cells.count; parts.removeLast()
            }
        } else { return }
        let cells = parts.flatMap { $0.cells }
        let heights: [Float]? = parts.allSatisfy { $0.heights != nil } ? parts.flatMap { $0.heights! } : nil
        var stops: [Int] = [], names: [String] = [], off = 0
        for p in parts {
            for st in p.stations { stops.append(off + st.index); names.append(st.name + " Station") }
            off += p.cells.count
        }
        guard stops.count >= 2 else { return }
        let whole = Railways.Line(id: 0, name: t.name, cells: cells, stations: [], heights: heights)
        let shapes = cells.indices.map { whole.shape($0) }
        nextThrough += 1
        let t2 = Track(id: nextThrough, name: t.name, cells: cells, slopes: shapes.map { (2...5).contains($0) }, stops: stops,
                       stopNames: names, armoured: false, dim: .overworld, heights: heights)
        t2.shapes = shapes; t2.parts = parts; t2.through = true
        // Its timetable taken up where it is: the moment the longer track's train is at s, heading d (or standing at the
        // same stop).
        let s2 = s - Float(shift)
        let atStop = now(tr).stop.map { t.stops[$0] - shift }
        var bestU = -1.0, bestErr = Float.infinity
        var u = 0.0
        while u < t2.period {
            let a = t2.at(u - t2.phase)
            let ok = atStop != nil ? a.stop.map { t2.stops[$0] == atStop! } ?? false : (a.stop == nil && a.dir == d)
            if ok { let e = abs(a.s - s2); if e < bestErr { bestErr = e; bestU = u } }
            u += 0.1
        }
        guard bestU >= 0, bestErr < 6 || tr.driven else { return }
        var delay = (g.time - (bestU - t2.phase)).truncatingRemainder(dividingBy: t2.period)
        if delay < 0 { delay += t2.period }
        let oldId = t.id
        trains[oldId] = nil
        for (k, v) in throughOut where v == oldId { throughOut[k] = t2.id }
        for p in parts where !Railways.isLink(p.id) { throughOut[p.id] = t2.id }
        tr.track = t2
        tr.delay = delay
        tr.time = g.time - delay
        tr.lastS = s2
        tr.driveS -= Float(shift)                      // (driven: his place on the longer track)
        tr.carS = tr.carS.map { $0 - Float(shift) }
        trains[t2.id] = tr
        splices += 1
    }

    static func build(_ g: Game, _ tr: Train) {
        remove(g, tr)
        // D47: one day in three the line runs a bullion train (VaultObjectives.swift).
        let day = Int(g.time / DAY_LENGTH)
        let wasBullion = tr.bullion
        tr.bullion = !tr.track.armoured && tr.track.dim == .overworld && VaultObjectives.bullionDay(tr.track.id, day) && tr.robbedDay != day
            && forceKind == nil                // (checks: the kind they ask for, whatever the day)
            && TrainArrivals.kindFor(tr.track.id) == nil          // (P508: an arriving train is the kind that was rolled)
        if tr.bullion && !wasBullion {
            g.onToast?("A bullion train runs the \(tr.track.name) today: armoured, guarded, and carrying the bank's gold")
        }
        tr.layout = []
        if !tr.track.armoured { buildBig(g, tr, day: day); return }       // P470 part 2: the railways' trains at real size
        let kinds = tr.track.armoured ? [armouredLoco, gunCar] : (tr.bullion ? [armouredLoco, gunCar, express] : [loco, coach, express])
        for (k, v) in kinds.enumerated() {
            let m = Mob(.minecart, at: tr.track.point(0))
            m.variant = v
            m.scale = carScale
            m.persistent = false
            m.customName = tr.track.armoured ? (v == gunCar ? "Ashguard Gun Car" : "Ashguard Armoured Train")
                : (tr.bullion ? ["\(tr.track.name) Bullion Train", "Guard Car", "Bullion Car"][k]
                              : ["\(tr.track.name) Locomotive", "\(tr.track.name) Coach", "\(tr.track.name) Express Car"][k])
            if tr.track.armoured || tr.bullion { m.health = v == gunCar ? 160 : (v == express ? m.spec.health : 240) }
            carOf[ObjectIdentifier(m)] = (tr, k)
            tr.cars.append(m)
            g.mobs.mobs.append(m)
        }
        place(g, tr, dt: 0)
    }

    static func remove(_ g: Game, _ tr: Train) {
        if let r = g.riding, tr.cars.contains(where: { $0 === r }) { g.dismount() }
        // (soldiers still aboard go with it; those who got off stay and fight)
        let riders = Set(tr.troops.filter { $0.mount != nil }.map { ObjectIdentifier($0) })
        if !riders.isEmpty { g.mobs.mobs.removeAll { riders.contains(ObjectIdentifier($0)) } }
        tr.troops = []
        TrainHulls.remove(g, tr)                                  // FAILURES 3
        for m in tr.cars { carOf[ObjectIdentifier(m)] = nil }
        let gone = Set(tr.cars.map { ObjectIdentifier($0) })
        g.mobs.mobs.removeAll { gone.contains(ObjectIdentifier($0)) }
        tr.cars = []
    }

    // Mob.update for a car: the train's head car moves the whole train; every car keeps its pose.
    static func drive(_ m: Mob, _ dt: Float, _ g: Game) {
        guard let (tr, k) = carOf[ObjectIdentifier(m)] else { m.health = -1; return }
        let guards = tr.layout.isEmpty ? (tr.bullion && k == 1) : ((tr.bullion || tr.kind == .troop) && m.variant == gunCar)
        if !tr.track.armoured && !guards { m.health = m.spec.health; m.hurt = 0 }
        if k == 0 { place(g, tr, dt: dt); if !tr.passengers.isEmpty { TrainHulls.seatPassengers(tr) } }
        if g.riding === m {
            g.player.pos = seat(m)
            g.player.vel = .zero
            g.player.airPeak = g.player.pos.y
            // ... and the leaves and limbs round his head on the footplate, once the train has moved (the nose ahead can
            // be over ground not loaded yet when he rides the engine at the back; a trunk stood in the cab's window where
            // a tree beside the line had grown after the line was drawn).
            if !tr.layout.isEmpty {
                let e = g.player.eye
                let ex = Int(floor(e.x)), ey = Int(floor(e.y)), ez = Int(floor(e.z))
                for y in (ey - 1)...(ey + 1) { for dz in -1...1 { for dx in -1...1 where Railways.clearable[Int(g.world.block(ex + dx, y, ez + dz))] {
                    g.world.setBlock(ex + dx, y, ez + dz, AIR)
                } } }
            }
        }
    }

    // P470: a real-size train's nose brushes off the leaves of trees leaning over the line (a crown over the bed stood
    // in the cab's window: the ride check's driver had his head in spruce leaves).
    static func brushFoliage(_ g: Game, _ c: IVec3) {
        for y in (c.y + 1)...(c.y + 8) { for dz in -2...2 { for dx in -2...2 where CapitalBase.isLeaf(g.world.block(c.x + dx, y, c.z + dz)) {
            g.world.setBlock(c.x + dx, y, c.z + dz, AIR)
        } } }
    }

    static func place(_ g: Game, _ tr: Train, dt: Float) {
        let t = tr.track
        // Blocked line: a solid block on the rail just ahead of the locomotive stops the train (the player's doing).
        // P379: the cell ahead is the track's own (a point straight ahead of the locomotive dipped into the bed where the
        // line climbs a grade, and into a cutting's side on a curve, and read as a blocked line).
        if dt > 0, tr.cars.first != nil {
            let (s0, dir0, _) = now(tr)
            let ahead = tr.layout.isEmpty ? s0 + dir0 * (gap * 0.75 + 1.2) : tr.lastS + dir0 * (tr.length / 2 + 1.5)    // (P470: the front's nose)
            let c = t.cell(ahead)
            let b = g.world.block(c.x, c.y, c.z)
            if Blocks.collide[Int(b)] && !Rails.isRail(b) && now(tr).stop == nil && !t.armoured {
                // P510 (Nov 1 20:39, "Why isn't it moving?... Train's broken for some reason. Fix it"): only a block he
                // put there stops it. Anything else on the rail (a structure, a road or a tree drawn over the line after
                // it, ground that grew back) held the train for good: it let go a minute later or once he was 48 blocks
                // off, then met the same block at once. The train clears it and the rail is put back.
                if placed[c] != nil {
                    if !tr.heldBy { tr.heldBy = true; tr.heldWay = tr.driven && tr.driveV < 0 ? -1 : 1; tr.stoppedFor = 0; whistle(g, tr) }
                } else if let sh = t.shapes, Blocks.has("rail") {
                    let i = t.cyclic ? Int(t.wrap(ahead.rounded())) % t.cells.count : max(0, min(t.cells.count - 1, Int(ahead.rounded())))
                    g.world.setBlock(c.x, c.y, c.z, Blocks.id("rail") + BlockID(sh[i]))
                    cleared += 1
                } else { g.world.setBlock(c.x, c.y, c.z, AIR); cleared += 1 }
            } else if tr.heldBy && tr.driven && tr.heldWay != 0 && !Blocks.collide[Int(b)] {
                tr.heldBy = false; tr.brake = 0; tr.stoppedFor = 0      // (driven: his block taken away, or backed off it)
            }
            holdUpTick(g, tr, dt)
            if !tr.layout.isEmpty {
                brushFoliage(g, c)
            }
        }
        tr.brake += ((tr.heldBy ? 1 : 0) - tr.brake) * min(1, dt * 1.2)
        // P337 step 3: riding the locomotive is driving it. Forward opens the regulator, back closes it, through stop
        // into reverse; the train runs its timetable's track at that rate (late or early: the timetable's time is the
        // train's own). Left alone it eases back to the timetable's pace.
        // P379 step 2: the brake is its own control (jump: the pad's A, the space bar), held to apply it, let go to
        // release; the regulator stays where it was left. The regulator pulls the train's pace toward its setting at
        // steam's pace; the brake pulls it to a stand whatever the regulator says.
        let drives = dt > 0 && !oldCab && g.riding.map { r in isEngine(r) && tr.cars.contains { $0 === r } } == true
        if drives { driveCab(g, tr, dt) } else if tr.driven { leaveCab(g, tr) }
        if drives {
        } else if dt > 0, let r = g.riding, tr.cars.contains(where: { $0 === r }), isEngine(r) {
            let f = g.rideInput.forward
            if abs(f) > 0.1 { tr.throttle = max(-1, min(2, tr.throttle + f * 0.7 * dt)) }
            let on: Float = g.rideInput.jump ? 1 : 0
            tr.cabBrake += (on - tr.cabBrake) * min(1, dt * (on > 0 ? 1.5 : 2.5))
        } else if dt > 0 {
            tr.throttle += (1 - tr.throttle) * min(1, dt * 0.3)
            tr.cabBrake = max(0, tr.cabBrake - dt * 2)
        }
        if dt > 0 && !tr.driven {
            tr.rate += (tr.throttle - tr.rate) * min(1, dt * 0.6)
            let bite: Float = tr.cabBrake * 1.4 * dt
            tr.rate = tr.rate > 0 ? max(0, tr.rate - bite) : min(0, tr.rate + bite)
        }
        if !tr.driven {
            let rate = tr.rate * (1 - tr.brake)
            tr.delay += Double(dt * (1 - rate))
        }
        tr.time = g.time - tr.delay
        let (s, dir, stop) = now(tr)
        let before = tr.cars.map { ($0.pos, $0.yaw) }
        let big = !tr.layout.isEmpty
        // P508 (one engine): the train turns to run the other way only where he can't see it happen (at a terminus,
        // 96 blocks off or out of his view); in sight it backs out and turns later.
        if big && dir != tr.facing && !tr.driven {
            let to = t.point(tr.lastS) - g.player.eye
            let d = simd_length(to)
            let looking = d > 1 && simd_dot(to / d, g.player.look) > 0.2
            if tr.fresh || d > 96 || !looking { tr.facing = dir }
        }
        tr.fresh = false
        let moving = big ? placeBig(tr, s, dir, dt) : abs(t.delta(tr.lastS, s))
        if !big { tr.lastS = s }
        if dt > 0 { tr.blocksPerSec += (moving / dt - tr.blocksPerSec) * min(1, dt * 4) }
        for (k, m) in tr.cars.enumerated() where !big {
            let sk = s - dir * gap * Float(k)
            let p = t.point(sk)
            let d = t.point(sk + dir * 0.7) - t.point(sk - dir * 0.7)
            m.pos = p
            m.vel = dt > 0 ? d * (moving / max(dt, 1e-4) / 1.4) : .zero
            if simd_length(V2(d.x, d.z)) > 0.01 { m.yaw = atan2f(-d.x, -d.z) }
            m.walkPhase += moving * 1.6
            m.onGround = true
        }
        if dt > 0 { carryRoofRider(g, tr, before: before) }                // D50: a rider on the roofs
        // Steam: chuffs with speed, a whistle leaving each stop.
        guard dt > 0, let lead = lead(tr), simd_length(lead.pos - g.player.pos) < 96 else { return }
        let sp = moving / max(dt, 1e-4)
        tr.chuff -= dt * (0.6 + sp * 0.5)
        if tr.chuff <= 0 {
            tr.chuff = 1
            let top = chimney(lead)
            let steam = !tr.track.armoured && lead.variant == loco
            if steam { g.particles.smoke(at: top, dark: true); g.particles.smoke(at: top + V3(0, 0.4, 0), dark: false) }
            if sp > 0.3 || stop != nil { g.sfx(.steamChuff, steam ? 0.7 : 0.5, at: top) }
        }
        if let st = stop, t.at(tr.time + 2).stop == nil, t.at(tr.time - Double(dt)).stop == st, tr.brake < 0.1 { whistle(g, tr) }
        if t.armoured || tr.bullion || tr.kind == .troop { gunCar(g, tr, dt) }
    }

    // Where the train is: its place on the track, the way it runs and the stop it stands at. Its timetable's, or
    // driven from the cab, where he has it.
    static func now(_ tr: Train) -> (s: Float, dir: Float, stop: Int?) {
        guard tr.driven else { return tr.track.at(tr.time) }
        // (a small train's cars hang behind its head along `dir`: backing, they keep their order)
        return (tr.driveS, tr.driveV < 0 && !tr.layout.isEmpty ? -tr.driveFwd : tr.driveFwd, nil)
    }

    // MARK: Nov 12: the cab is his

    // Nov 12 playtest (06:16:36-06:17:47, at the regulator of a line's train: "There's no one driving the train", "I
    // should be able to speed the train up to like 100... That'll make you use more coal", "I'm forced to stop the train
    // at the village. I can't make it go anymore", "me pressing on the pedal doesn't do anything... Like a toy ride that
    // kids get to use at the carnival that, like, they think they're driving, but they're actually not"): the cab ran
    // the timetable's track at a pace the regulator nudged (at most twice the timetable's, ~50 km/h), stood its 24 s at
    // every station whatever he did, and the pad's triggers did nothing. Riding the engine now drives it: the train
    // leaves its timetable and goes as he sets it. The regulator (the stick forward, or the right trigger held: the
    // pedal) sets the speed it pulls toward, up to 28 blocks a second (100 km/h) at full; the brake (A / space, or the
    // left trigger) stops it; it runs through the stations unless he stops there, and on past the line's end where a
    // link runs on (P510's through trains). Steam costs coal: the tender starts with 24 lumps and burns more the wider
    // the regulator (a lump every 20 s at full, 80 s at the timetable's pace; creative burns none); coal used on the
    // engine from the cab tops it up; with none the fire dies and the train rolls to a stand. When he leaves the cab the
    // timetable takes the train up where it is. BS_OLDCAB=1: the old regulator over the timetable.
    static let oldCab = ProcessInfo.processInfo.environment["BS_OLDCAB"] == "1"
    static let topSpeed: Float = 28, backSpeed: Float = 7       // blocks a second at full regulator, ahead and backing
    static let tractive: Float = 2.2, coast: Float = 0.35, brakeRate: Float = 5      // blocks a second, each second
    static let tenderStart: Float = 24, tenderMax: Float = 64
    static var coalBurned: Float = 0                             // (checks)

    static func driveCab(_ g: Game, _ tr: Train, _ dt: Float) {
        let t = tr.track
        if !tr.driven {
            let a = t.at(tr.time)
            tr.driven = true
            tr.driveS = tr.layout.isEmpty ? a.s : tr.lastS
            tr.driveFwd = tr.layout.isEmpty ? a.dir : (tr.facing < 0 ? -1 : 1)
            tr.driveV = tr.blocksPerSec * (a.dir == tr.driveFwd ? 1 : -1)
            tr.throttle = max(0, tr.throttle)
        }
        // The regulator: the stick, or the pedal held (the right trigger, his hands free of a gun); the brake: jump or
        // the left trigger.
        let pad = g.heldGun == nil ? g.seatPad : nil
        let f = g.rideInput.forward + (pad.map { $0.rt > 0.15 ? $0.rt : 0 } ?? 0)
        if abs(f) > 0.1 { tr.throttle = max(-1, min(2, tr.throttle + f * 0.7 * dt)) }
        let on: Float = g.rideInput.jump || (pad?.lt ?? 0) > 0.3 ? 1 : 0
        tr.cabBrake += (on - tr.cabBrake) * min(1, dt * (on > 0 ? 1.5 : 2.5))
        // Steam: the fire burns with the regulator's opening.
        let open = max(0, tr.throttle)
        if g.survival && tr.coal > 0 && open > 0 {
            let burn = min(tr.coal, open * open * 0.0125 * dt)
            tr.coal -= burn; coalBurned += burn
            if tr.coal <= 0 { g.onToast?("The firebox is out of coal") }
        }
        let fired = tr.coal > 0 || !g.survival
        let want: Float = !fired ? 0 : tr.throttle >= 0 ? topSpeed * tr.throttle / 2 : backSpeed * tr.throttle
        var v = tr.driveV
        if (want > 0 && v < want) || (want < 0 && v > want) {
            let a = tractive * (1 - min(0.6, abs(v) / topSpeed * 0.6))         // (steam pulls hardest from a stand)
            v += want > v ? min(want - v, a * dt) : -min(v - want, a * dt)
        } else {
            let drag = coast + abs(v) * 0.01
            v = v > 0 ? max(want > 0 ? want : 0, v - drag * dt) : min(want < 0 ? want : 0, v + drag * dt)
        }
        let stopping = brakeRate * max(tr.cabBrake, tr.brake) * dt
        v = v > 0 ? max(0, v - stopping) : min(0, v + stopping)
        // A block he put on the rail ahead (place: heldBy) stops it there, backing or not; he can still pull away from
        // it the other way.
        if tr.heldBy && (tr.heldWay == 0 || v * tr.heldWay > 0) { v = 0 }
        // The track's ends (where no link runs on) and a real-size train's own length hold it off the buffers.
        var s = tr.driveS + tr.driveFwd * v * dt
        if !t.cyclic {
            let n = Float(t.cells.count)
            let half = tr.layout.isEmpty ? 0 : tr.length / 2
            let lo = tr.layout.isEmpty ? Float(0) : half + 3, hi = tr.layout.isEmpty ? n - 1 : n - 4 - half
            if lo <= hi && (s < lo || s > hi) { s = max(lo, min(hi, s)); v = 0 }
        } else { s = t.wrap(s) }
        tr.driveS = s
        tr.driveV = v
        tr.rate = 1
        tr.delay += Double(dt)                          // (its timetable waits: taken up again where it is when he leaves)
    }

    // He left the cab: the timetable's moment the train is at s heading dir (P510's search), from then on.
    static func leaveCab(_ g: Game, _ tr: Train) {
        guard tr.driven else { return }
        tr.driven = false
        let t = tr.track
        let s = tr.driveS, d: Float = tr.driveV < 0 ? -tr.driveFwd : tr.driveFwd
        var bestU = -1.0, bestErr = Float.infinity
        var u = 0.0
        while u < t.period {
            let a = t.at(u - t.phase)
            if a.stop == nil && a.dir == d { let e = abs(t.delta(a.s, s)); if e < bestErr { bestErr = e; bestU = u } }
            u += 0.1
        }
        if bestU < 0 {
            // (no leg runs that way here: the nearest moment it stands or runs here at all)
            u = 0
            while u < t.period { let e = abs(t.delta(t.at(u - t.phase).s, s)); if e < bestErr { bestErr = e; bestU = u }; u += 0.1 }
        }
        guard bestU >= 0 else { return }
        var delay = (g.time - (bestU - t.phase)).truncatingRemainder(dividingBy: t.period)
        if delay < 0 { delay += t.period }
        tr.delay = delay
        tr.time = g.time - delay
        tr.throttle = 1
        tr.rate = abs(tr.driveV) / max(1, speed)
    }

    // Coal used on the engine he drives: into the tender, as much of the stack as it takes.
    static func feedCoal(_ g: Game, _ tr: Train) -> Bool {
        var h = g.inventory.held
        guard !h.isEmpty else { return false }
        let k = Items.key(h.item)
        guard k == "coal" || k == "charcoal" || k == "coal_block" else { return false }
        let per: Float = k == "coal_block" ? 9 : 1
        let room = Int((tenderMax - tr.coal) / per)
        guard room > 0 else { g.onToast?("The tender is full"); return true }
        let n = min(room, h.count)
        tr.coal += Float(n) * per
        if g.survival { h.count -= n; g.inventory.held = h.count > 0 ? h : .empty }
        g.sfx(.place(.stone), 0.7, at: g.player.pos)
        g.onToast?(String(format: "Tender: %.0f coal", tr.coal))
        return true
    }

    // The train whose locomotive the player rides (drives), if any.
    static func cab(_ g: Game) -> Train? {
        guard let r = g.riding, isCar(r), let (tr, k) = carOf[ObjectIdentifier(r)], tr.layout.isEmpty ? k == 0 : isEngine(r) else { return nil }
        return tr
    }

    static func whistle(_ g: Game, _ tr: Train) {
        guard let lead = lead(tr) else { return }
        g.sfx(.trainWhistle, tr.track.armoured ? 0.7 : 1, at: chimney(lead))
    }

    // MARK: Hold-ups and robbery

    static func holdUpTick(_ g: Game, _ tr: Train, _ dt: Float) {
        guard !tr.track.armoured, !tr.bullion, tr.kind != .troop, !tr.heldBy, let lead = lead(tr), g.alive, g.survival, Guns.index(g.held.item) != nil else { tr.holdUp = 0; return }
        let from = g.vrAim?.origin ?? g.player.eye, dir = simd_normalize(g.vrAim?.dir ?? g.player.look)
        let cab = cabPoint(lead)
        let to = cab - from, d = simd_length(to)
        guard d > 1, d < 20, simd_dot(to / d, dir) > 0.985, g.world.canSee(from, cab) else { tr.holdUp = max(0, tr.holdUp - dt); return }
        tr.holdUp += dt
        if tr.holdUp >= holdUpTime {
            tr.heldBy = true; tr.heldWay = 0; tr.stoppedFor = 0
            whistle(g, tr)
            g.onToast?("The driver throws on the brakes")
        }
    }

    // Use a car: the coach seats you; the express car's strongbox cracks (a held-up train only).
    static func use(_ g: Game, _ m: Mob) -> Bool {
        guard isCar(m), let (tr, k) = carOf[ObjectIdentifier(m)] else { return false }
        _ = k
        if climbRoof(g, tr, m) { return true }                              // D50: sneak-use climbs onto the roof
        switch m.variant {
        case boxcar:
            return openBoxcar(g, tr, m)
        case coach, loco:
            if g.riding === m { return m.variant == loco && !oldCab && feedCoal(g, tr) }
            if g.riding != nil { g.dismount() }
            g.riding = m
            g.player.pos = seat(m)
            g.sfx(.armorEquip(0), 0.5, at: m.pos)
            g.onToast?("Riding the \(tr.track.name)")         // P300 (b)
            return true
        case express:
            return crack(g, tr, m)
        case troopCar, armouredLoco, gunCar:
            return MilitaryTrain.use(g, tr, m)
        default:
            return false
        }
    }

    static func crack(_ g: Game, _ tr: Train, _ m: Mob) -> Bool {
        let day = Int(g.time / DAY_LENGTH)
        guard tr.brake > 0.8 else { g.onToast?("The strongbox won't budge"); return true }
        guard tr.robbedDay != day else { g.onToast?("The strongbox is empty"); return true }
        // Q2: a bullion car's guards keep you off it while their gun still fires (D47).
        if tr.bullion, let gc = tr.cars.first(where: { $0.variant == gunCar }), gc.health > 0 {
            g.onToast?("The guard car's gun covers the bullion car")
            return true
        }
        let tnt = Items.key(g.held.item) == "tnt"
        if tnt {
            tr.cracks = crackUses
            if g.survival { g.consumeHeld() }
            Explosion.explode(at: m.pos + V3(0, 1, 0) + m.forward * 0.6, power: 1.2, game: g, except: m)
        } else {
            tr.cracks += 1
            g.sfx(.anvil, 0.6, at: m.pos)
            g.swing = 1
        }
        if tr.cracks < crackUses { g.onToast?("Cracking the strongbox (\(tr.cracks) of \(crackUses))"); return true }
        // Open: the line's takings.
        tr.cracks = 0
        tr.robbedDay = day
        let cash = Rand.int(in: 40...120) * 100 * (tr.bullion ? 3 : 1)      // D47: bullion
        g.money += cash
        for (k, lo, hi) in [("gold_ingot", 2, 5), ("gold_nugget", 4, 12), ("emerald", 1, 3), ("paper", 1, 4)] where Items.has(k) {
            let n = Rand.int(in: lo...hi)
            if n > 0 { g.drops.spawn(ItemStack(Items.id(k), n), at: m.pos + V3(0, 1, 0)) }
        }
        g.onToast?(tr.bullion ? "The bullion car gives up \(Money.format(cash)) and its gold" : "The strongbox gives up \(Money.format(cash))")
        if tr.bullion { for _ in 0..<2 { if Items.has("gold_ingot") { g.drops.spawn(ItemStack(Items.id("gold_ingot"), Rand.int(in: 4...8)), at: m.pos + V3(0, 1, 0)) } } }
        Trains.robbed += 1
        if g.survival {
            let town = Townsfolk.town(g, at: m.pos)
            Honour.change(g, robHonour, "robbed the \(tr.track.name)")
            Honour.addBounty(g, town, robBounty * (tr.bullion ? 2 : 1))
            _ = Riders.sendPosse(g, from: town)
            _ = Riders.sendPosse(g, from: town)
        }
        return true
    }
    static var robbed = 0

    // MARK: The armoured gun car

    static func gunCar(_ g: Game, _ tr: Train, _ dt: Float) {
        guard tr.cars.count > 1, let gun = tr.cars.first(where: { $0.variant == gunCar }) else { return }
        // Wrecked: both cars down (explosives and heavy rounds). A bullion train's guard car just falls silent (D47).
        if tr.track.armoured && (tr.cars.allSatisfy({ $0.health <= 0 }) || tr.cars[0].health <= 0) {
            for c in tr.cars { Explosion.explode(at: c.pos + V3(0, 1, 0), power: 2.5, game: g, except: c) }
            tr.wrecked = true
            g.onToast?("The armoured train is wrecked")
            remove(g, tr)
            return
        }
        // Q2: the guard car going quiet is a moment: a bang at its turret and a word on what's next.
        if !tr.track.armoured && gun.health <= 0 && !tr.gunSilenced {
            tr.gunSilenced = true
            g.sfx(.explodeSmall, 0.9, at: gun.pos + V3(0, 2.6, 0))
            g.sfx(.levelUp, 0.6)
            g.onToast?("The guard car falls silent")
        }
        guard gun.health > 0, g.alive, g.survival, !tr.taken, tr.bullion || tr.kind == .troop || !g.ashVictory else { return }
        // P508: a military arrival in his town shells it, its troops roused from the start.
        if TrainArrivals.wreckers.contains(tr.track.id) {
            tr.roused = true
            TrainArrivals.wreck(g, tr, gun: gun, muzzle: isBig(gun) ? gun.pos + V3(0, 3.45, 0) : gun.pos + V3(0, 2.6, 0))
        }
        // P470: a troop train's gun opens up once its troops are roused (the train stopped or fired on).
        if tr.kind == .troop && !tr.roused && gun.health >= 160 { return }
        let muzzle = isBig(gun) ? gun.pos + V3(0, 3.45, 0) : gun.pos + V3(0, 2.6, 0)
        let to = g.player.eye - muzzle, d = simd_length(to)
        tr.gunCool -= dt
        // The turret turns to the player (yaw kept in the gun car's jobTimer for the model).
        let want = atan2f(-to.x, -to.z) - gun.yaw
        gun.jobTimer += (atan2f(sinf(want - gun.jobTimer), cosf(want - gun.jobTimer))) * min(1, dt * 2)
        guard d < 48, tr.gunCool <= 0, g.world.canSee(muzzle, g.player.eye) else { return }
        tr.gunCool = Float([1.6, 1.2, 0.9, 0.7][max(0, min(3, g.difficulty))])
        for k in 0..<3 {
            let dir = Guns.scatter(simd_normalize(to), 0.03)
            let dmg: Float = 1.5 * Soldier.difficultyScale(g.difficulty) + 0.5
            g.arms.spawn(Slug(pos: muzzle + dir * 1.2, vel: dir * 140, kind: .bullet, damage: dmg, fromPlayer: false, shooter: ObjectIdentifier(gun),
                              by: tr.bullion ? "a bullion train's Guard Car" : (tr.kind == .troop ? "a troop train's Guard Car" : "an Ashguard Gun Car"), life: 0.6 + Float(k) * 0.02, gravity: 1.5))
        }
        g.addFlash(at: muzzle + simd_normalize(to) * 1.2, color: V3(6, 3.5, 1.6), radius: 5, life: 0.06)
        g.sfx(.gun(1), 1, at: muzzle)
    }

    // MARK: Tickets

    static func isTicketSign(_ be: BlockEntity) -> Bool { be.kind == .sign && be.lines.first == ticketWord }

    static func openTickets(_ g: Game, at p: IVec3) -> Bool {
        guard let gen = g.world.gen as? WorldGen,
              let (l, st) = Railways.station(gen, near: V3(Float(p.x), Float(p.y), Float(p.z)), within: 20) else { return false }
        g.openMenu(TicketMenu(game: g, line: l, from: st))
        return true
    }

    static func fare(_ a: Railways.Station, _ b: Railways.Station) -> Int { max(100, abs(a.index - b.index) * fareCentsPerBlock) }

    // Travel: the trip's time passes, you step off on the platform at `to` (the town side of the track).
    static func travel(_ g: Game, line l: Railways.Line, from a: Railways.Station, to b: Railways.Station) -> (String, Bool) {
        let cost = fare(a, b)
        guard g.money >= cost || !g.survival else { return ("You need \(Money.format(cost)) for that fare.", false) }
        if g.survival { g.money -= cost }
        if g.riding != nil { g.dismount() }
        let c = l.cells[b.index]
        let trip = Double(abs(b.index - a.index)) / Double(speed * 1.6)
        g.time += trip
        g.player.pos = V3(Float(c.x) + 0.5, Float(c.y), Float(c.z - 2) + 0.5)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
        g.sfx(.trainWhistle, 0.8)
        g.closeMenu()
        Trains.journeys += 1
        g.onToast?("You arrive at \(b.name) Station")
        return ("", true)
    }
    static var journeys = 0

    // The network (P132): found stations on other lines, nearest first (twelve at most).
    static func networkStops(_ g: Game, line l: Railways.Line, from a: Railways.Station) -> [MapCache.Mark] {
        let own = Set(l.stations.map { "\($0.x),\($0.z)" })
        let marks = MapCache.shared.marks.filter { m in m.kind == "station" && !own.contains("\(m.x),\(m.z)")
            && !l.stations.contains(where: { s in abs(s.x - m.x) < 24 && abs(s.z - m.z) < 24 }) }
        return Array(marks.sorted { crowFlies(a, $0) < crowFlies(a, $1) }.prefix(12))
    }
    static func crowFlies(_ a: Railways.Station, _ m: MapCache.Mark) -> Int {
        let dx = Float(m.x - a.x), dz = Float(m.z - a.z)
        return Int((dx * dx + dz * dz).squareRoot())
    }
    static let changeFare = 300
    static func networkFare(_ blocks: Int) -> Int { max(100, blocks * fareCentsPerBlock * 5 / 4) + changeFare }

    static func travelNetwork(_ g: Game, from a: Railways.Station, to m: MapCache.Mark) -> (String, Bool) {
        guard let gen = g.world.gen as? WorldGen,
              let (l, b) = Railways.station(gen, near: V3(Float(m.x), 64, Float(m.z)), within: 24) else {
            return ("That line isn't running.", false)
        }
        let d = crowFlies(a, m), cost = networkFare(d)
        guard g.money >= cost || !g.survival else { return ("You need \(Money.format(cost)) for that fare.", false) }
        if g.survival { g.money -= cost }
        if g.riding != nil { g.dismount() }
        let c = l.cells[b.index]
        g.time += Double(d) * 1.3 / Double(speed * 1.6)            // the trip, with the wait for the connection
        g.player.pos = V3(Float(c.x) + 0.5, Float(c.y), Float(c.z - 2) + 0.5)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
        g.sfx(.trainWhistle, 0.8)
        g.closeMenu()
        Trains.journeys += 1
        g.onToast?("You change trains and arrive at \(b.name) Station")
        return ("", true)
    }

    // Finding a station puts the whole line on the map (once a second).
    static func discover(_ g: Game) {
        guard g.dim.dim == .overworld, let gen = g.world.gen as? WorldGen, let (l, _) = Railways.station(gen, near: g.player.pos, within: 40, wait: false) else { return }
        guard !MapCache.shared.marked(kind: "station", x: l.stations[0].x, z: l.stations[0].z) else { return }
        for s in l.stations { MapCache.shared.discover(g, kind: "station", x: s.x, z: s.z, name: "\(s.name) Station") }
        g.onToast?("You found the \(l.name): \(l.stations.count) stations, marked on your map")
    }

    // MARK: Models (units 1/16 at scale 2: one unit is an eighth of a block; the car faces -Z)

    // A round wheel turning about the axle (x across, at height cy, place z along the car): the regular octagon of
    // radius r across its flats is the union of four slabs 2r long and 2r tan(22.5 deg) wide, an eighth of a turn apart.
    static let squareWheels = ProcessInfo.processInfo.environment["BS_SQUAREWHEELS"] == "1"
    static func roundWheel(_ p: inout [Part], x: Float, w: Float, cy: Float, z: Float, r: Float, spin: Float, color: V3) {
        if squareWheels {
            p.append(Part(mn: V3(x, cy - r, z - r), mx: V3(x + w, cy + r, z + r), pivot: V3(x, cy, z), rotX: spin, color: color, pattern: 8))
            return
        }
        let h: Float = r * 0.41421356
        for k in 0..<4 {
            p.append(Part(mn: V3(x, cy - h, z - r), mx: V3(x + w, cy + h, z + r), pivot: V3(x, cy, z), rotX: spin + Float(k) * .pi / 4, color: color, pattern: 8))
        }
    }

    static func parts(_ m: Mob) -> [Part] {
        if isBig(m) { return bigParts(m) }                      // P470 part 2 (TrainCars.swift)
        let iron = V3(0.16, 0.16, 0.17), brass = V3(0.85, 0.66, 0.3), red = V3(0.55, 0.12, 0.1)
        var p: [Part] = []
        func wheels(_ zs: [Float], _ c: V3) {
            let spin = m.walkPhase
            for z in zs { for x: Float in [-6.6, 5.6] { roundWheel(&p, x: x, w: 1, cy: 2, z: z, r: 2, spin: spin, color: c) } }
        }
        switch m.variant {
        case loco:
            let body = V3(0.12, 0.13, 0.14), cab = V3(0.42, 0.1, 0.09)
            p.append(box(-6, 2, -13, 12, 2, 26, iron, 8))                         // the frame
            p.append(box(-6.1, 2.5, -13, 12.2, 1, 26, red, 7))                    // its red stripe
            wheels([-8, -2.5, 3, 9], red)
            p.append(box(-4.5, 4, -13, 9, 8, 15, body, 7))                        // the boiler
            p.append(box(-4, 4.5, -14, 8, 7, 1, V3(0.22, 0.22, 0.23), 8))        // the smokebox door
            p.append(box(-1, 9, -14.6, 2, 2, 0.8, V3(1, 0.95, 0.7), 9))           // the headlamp
            p.append(box(-1.5, 12, -11, 3, 5, 3, body, 7))                        // the chimney
            p.append(box(-2.1, 16.5, -11.6, 4.2, 1.2, 4.2, body, 7))
            p.append(box(-2, 12, -5, 4, 2.5, 4, brass, 8))                         // the steam dome
            p.append(box(-1.2, 12, -1.5, 2.4, 1.6, 2, brass, 8))                   // the whistle
            for z: Float in [-12, -7, -2] { p.append(box(-4.7, 4, z, 9.4, 8.2, 0.6, brass, 8)) }    // boiler bands
            p.append(box(-6, 4, 2, 12, 12, 9, cab, 7))                             // the cab
            p.append(box(-6.1, 10, 3.5, 0.3, 4, 6, V3(0.05, 0.05, 0.06), 11))      // cab windows
            p.append(box(5.8, 10, 3.5, 0.3, 4, 6, V3(0.05, 0.05, 0.06), 11))
            p.append(box(-6.6, 16, 1.4, 13.2, 1, 10.2, body, 7))                  // its roof
            p.append(box(-5, 0.6, -15.6, 10, 2.6, 2, red, 7))                     // the cowcatcher
            p.append(box(-5.4, 4, 11, 10.8, 1, 2, iron, 8))                         // the drawbar
            // Connecting rods on the drivers (they run with the wheels).
            let r = sinf(m.walkPhase) * 1.2, q = cosf(m.walkPhase) * 1.2
            p.append(box(-7.2, 1.6 + q, -8 + r, 0.5, 0.8, 11.5, V3(0.75, 0.75, 0.78), 8))
            p.append(box(6.7, 1.6 + q, -8 + r, 0.5, 0.8, 11.5, V3(0.75, 0.75, 0.78), 8))
        case coach, express:
            let side = m.variant == coach ? V3(0.2, 0.33, 0.22) : V3(0.16, 0.2, 0.36)
            let trim = m.variant == coach ? V3(0.85, 0.72, 0.42) : V3(0.9, 0.78, 0.35)
            p.append(box(-6, 2, -13, 12, 2, 26, iron, 8))
            wheels([-9, -5, 5, 9], iron)
            p.append(box(-6, 4, -13, 12, 11, 26, side, 7))                        // the body
            p.append(box(-6.1, 6, -13, 12.2, 0.6, 26, trim, 8))                   // a lined stripe
            p.append(box(-6.6, 15, -13.5, 13.2, 1.4, 27, V3(0.2, 0.18, 0.17), 7))  // the roof
            p.append(box(-1.5, 16.4, -13, 3, 0.8, 26, V3(0.24, 0.22, 0.2), 7))
            if m.variant == coach {
                for z: Float in stride(from: -11, through: 9, by: 4) {           // windows, lit warm
                    p.append(box(-6.15, 9, z, 0.3, 4, 2.6, V3(0.95, 0.82, 0.5), 9))
                    p.append(box(5.85, 9, z, 0.3, 4, 2.6, V3(0.95, 0.82, 0.5), 9))
                }
            } else {
                // The express car: barred little windows and a heavy sliding door on each side, the strongbox inside.
                for z: Float in [-10, 8] {
                    p.append(box(-6.15, 11, z, 0.3, 2, 2, V3(0.05, 0.05, 0.06), 11))
                    p.append(box(5.85, 11, z, 0.3, 2, 2, V3(0.05, 0.05, 0.06), 11))
                }
                p.append(box(-6.3, 4.5, -4, 0.5, 10, 8, V3(0.12, 0.14, 0.24), 7))
                p.append(box(5.8, 4.5, -4, 0.5, 10, 8, V3(0.12, 0.14, 0.24), 7))
                p.append(box(-6.4, 12, -1.5, 0.3, 1.2, 3, trim, 8))                 // a brass plate
                p.append(box(6.1, 12, -1.5, 0.3, 1.2, 3, trim, 8))
            }
            for e: Float in [-13.5, 12.5] { p.append(box(-4, 4, e, 8, 9, 1, V3(0.1, 0.09, 0.08), 7)) }   // end platforms
        case armouredLoco:
            let plate = V3(0.24, 0.25, 0.22), dark = V3(0.13, 0.13, 0.12)
            p.append(box(-6.4, 1, -14, 12.8, 3, 28, dark, 8))
            wheels([-9, -3, 3, 9], dark)
            p.append(box(-6, 4, -13, 12, 9, 26, plate, 8))                         // the armoured box
            p.append(box(-5, 13, -11, 10, 3, 18, plate, 8))                        // its upper casemate
            p.append(box(-6.6, 1, -15.4, 13.2, 6, 1.6, dark, 8))                   // the ram plate
            p.append(box(-4.5, 13.2, -11.2, 9, 0.6, 0.4, V3(0.05, 0.05, 0.05), 11))  // the vision slit
            p.append(box(-1.4, 16, 3, 2.8, 3, 2.8, dark, 8))                        // the exhaust
            p.append(box(-6.2, 8, -13, 12.4, 0.6, 26, V3(0.5, 0.12, 0.08), 7))   // the Ashguard red band
        case gunCar:
            let plate = V3(0.24, 0.25, 0.22), dark = V3(0.13, 0.13, 0.12)
            p.append(box(-6.4, 1, -14, 12.8, 3, 28, dark, 8))
            wheels([-9, -3, 3, 9], dark)
            p.append(box(-6, 4, -13, 12, 7, 26, plate, 8))
            p.append(box(-6.2, 8, -13, 12.4, 0.6, 26, V3(0.5, 0.12, 0.08), 7))
            // The turret turns to its target (Mob.jobTimer holds its yaw relative to the car).
            let ty = m.jobTimer
            p.append(Part(mn: V3(-4.5, 11, -4.5), mx: V3(4.5, 16, 4.5), pivot: V3(0, 11, 0), color: plate, pattern: 8, rotY: ty))
            p.append(Part(mn: V3(-0.8, 13, -14), mx: V3(0.8, 14.6, -4), pivot: V3(0, 11, 0), color: dark, pattern: 8, rotY: ty))
            p.append(Part(mn: V3(-2.2, 12.6, -5.2), mx: V3(2.2, 15, -4.2), pivot: V3(0, 11, 0), color: dark, pattern: 8, rotY: ty))
        default: break
        }
        return p
    }
}

// The station's ticket board: a fare to every other station on the line.
final class TicketMenu: ListMenu {
    let line: Railways.Line
    let from: Railways.Station
    // P132: the network. Stations you have found on other lines (the map's station marks) are sold too, priced by the
    // distance as the crow flies plus a change of trains; the trip runs to the far line's station.
    let network: [MapCache.Mark]
    init(game g: Game, line l: Railways.Line, from st: Railways.Station) {
        line = l; from = st
        network = Trains.networkStops(g, line: l, from: st)
        super.init(l.name, game: g)
        subtitle = "\(st.name) Station: tickets"
        say(network.isEmpty ? "Pick a station. The trip passes on the train."
                            : "Pick a station. Stations on other lines you have found are sold too, with a change.", good: true)
    }
    var others: [Railways.Station] { line.stations.filter { $0.index != from.index } }
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        let icon = Items.has("rail") ? ItemStack(Items.id("rail"), 1) : .empty
        let own = others.map { s -> Row in
            let f = Trains.fare(from, s)
            let km = abs(s.index - from.index)
            return Row(icon: icon, name: "\(s.name) Station",
                       detail: "\(km) blocks of track", value: Money.format(f), enabled: !game.survival || game.money >= f)
        }
        let far = network.map { m -> Row in
            let d = Trains.crowFlies(from, m), f = Trains.networkFare(d)
            return Row(icon: icon, name: m.name ?? "Station", detail: "\(d) blocks away, change trains", value: Money.format(f),
                       enabled: !game.survival || game.money >= f)
        }
        return own + far
    }
    override func pressed(_ i: Int) {
        let o = others
        if i < o.count {
            let r = Trains.travel(game, line: line, from: from, to: o[i])
            if !r.1 { say(r.0, good: false) }
            return
        }
        let j = i - o.count
        guard j < network.count else { return }
        let r = Trains.travelNetwork(game, from: from, to: network[j])
        if !r.1 { say(r.0, good: false) }
    }
}
