import Foundation
import simd

// FAILURES 3 / P511 (Nov 2 08:40:06 at -8365 128 5109: "Oh, look, a train. And it stops... That shouldn't be there";
// 12:13: "The railway was good but there was still a 'start' to it"): a line whose end doesn't run on by a link (most
// don't: the next line is seldom in reach) ended at buffer stops, its train standing there and turning back. Now such
// an end turns round in a loop, as real lines do at a terminus: past the end station the track runs on, turns away from
// the town, back along behind the line and into it again a little short of its end, so the train comes round and runs
// back without stopping or reversing. A line with a loop at each end is a circuit its train runs round for ever
// (Trains.cyclicTrack). Only on ground no save had before P511 (structure-guard-p511.txt); where no loop fits (a
// structure, the sea, a cliff, saved ground) the buffers stay.
//
//   east end E, the town north of the line:     ===J=====E----+        (J: the junction, loopBack short of E)
//                                                  |          |
//                                                  +----------+        (loopDeep south, loopOut past E)
extension Railways {
    static let loopOut = 12, loopDeep = 16, loopBack = 14
    // (out past the end, deep to the side): P511's, then the wider and deeper ones for an end it doesn't fit (Nov 4)
    static let loopShapes: [(Int, Int)] = [(loopOut, loopDeep), (26, loopDeep), (loopOut, 28), (34, 28), (loopOut, 10)]
    static let loopReach = loopShapes.map { $0.0 + $0.1 }.max()!
    static let loopFlipE: Int64 = 1 << 61, loopFlipW: Int64 = 1 << 62      // (a loop's id: its line's with bit 61 / 62 flipped)
    static var loopsOn = true
    static func loopKey(_ row: Int, _ s: Int, east: Bool) -> Int64 { key(row, s) ^ (east ? loopFlipE : loopFlipW) }

    // The loop at line (row, s)'s east or west end, if one is laid. Its cells run from beside the end to beside the
    // junction; `joins` is the line's cell it comes back into.
    static func loop(_ gen: WorldGen, row: Int, stretch s: Int, east: Bool, wait: Bool = true) -> Line? {
        guard on, loopsOn else { return nil }
        return cached(gen, loopKey(row, s, east: east), wait: wait) { planLoop(gen, row: row, stretch: s, east: east) }
    }
    static func loops(_ gen: WorldGen, _ l: Line, wait: Bool = true) -> (west: Line?, east: Line?) {
        guard on, loopsOn, !isLink(l.id), l.id != 0 else { return (nil, nil) }
        let (row, s) = rowStretch(l.id)
        return (loop(gen, row: row, stretch: s, east: false, wait: wait), loop(gen, row: row, stretch: s, east: true, wait: wait))
    }

    static var loopNote: ((String) -> Void)?                // (checks: why an end keeps its buffers)

    static func planLoop(_ gen: WorldGen, row: Int, stretch s: Int, east: Bool) -> Line? {
        guard hasLine(gen, row, s), let l = line(gen, row: row, stretch: s), let sc = gen.structures, l.cells.count > 40 else { return nil }
        if east ? link(gen, row: row, stretch: s) != nil : incoming(gen, row, s) != nil { return nil }   // (it runs on)
        let n = l.cells.count
        let e = east ? l.cells[n - 1] : l.cells[0], inner = east ? l.cells[n - 2] : l.cells[1]
        guard inner.z == e.z, inner.x == e.x + (east ? -1 : 1) else { loopNote?("loop: end not on a straight"); return nil }
        guard let st = east ? l.stations.last : l.stations.first else { return nil }
        let dx = east ? 1 : -1
        // The junction: loopBack short of the end, clear of the end station's platform, house and the walk to it.
        let clear = st.halt ? 7 : 13
        let room = east ? (n - 1 - st.index) - clear : st.index - clear
        let back = min(loopBack, room)
        guard back >= 3 else { loopNote?("loop: the end station too near the end"); return nil }
        let j = east ? n - 1 - back : back
        guard l.cells[j].z == e.z else { loopNote?("loop: no straight for the junction"); return nil }
        for k in thru(min(j, east ? n - 1 : 0), max(j, east ? n - 1 : 0)) where l.cells[k].z != e.z { loopNote?("loop: no straight for the junction"); return nil }
        let xj = e.x - dx * back
        var cells: [(Int, Int)]? = nil, shaped = 0
        // Away from the town first (it stands north of the line), else the other way.
        // (Nov 4, bug hunt: 9 of 256 line ends kept their buffers, the loop "blocked both ways" by a structure or the
        // sea, and the train stopped there (FAILURES 3). The first shape is P511's; where it fits nowhere, wider and
        // deeper ones are tried, round whatever stood in the first's way, on ground no save had before them.)
        shapes: for (si, (out, deep)) in loopShapes.enumerated() { for side in [1, -1] {
            let xo = e.x + dx * out
            let zd = e.z + side * deep
            if blocked(gen, sc, x0: min(xj, xo), z0: min(e.z + side, zd), x1: max(xj, xo), z1: max(e.z + side, zd), except: []) { continue }
            var c: [(Int, Int)] = []
            for x in stride(from: e.x + dx, through: xo, by: dx) { c.append((x, e.z)) }
            for z in stride(from: e.z + side, through: zd, by: side) { c.append((xo, z)) }
            for x in stride(from: xo - dx, through: xj, by: -dx) { c.append((x, zd)) }
            for z in stride(from: zd - side, through: e.z + side, by: -side) { c.append((xj, z)) }
            if stride(from: 0, to: c.count, by: 3).contains(where: { gen.column(c[$0].0, c[$0].1).biome.isOcean }) { continue }
            cells = c; shaped = si
            break shapes
        } }
        guard let run = cells else { loopNote?("loop: blocked both ways"); return nil }
        if shaped > 0 { loopNote?("loop: shape \(shaped)") }
        for (i, c) in run.enumerated() where i % 6 == 0 || i == run.count - 1 {
            let cx = floorDiv(c.0, CS), cz = floorDiv(c.1, CS)
            for gs in [sc.legacyC1, sc.legacyP510, sc.legacyP511, shaped > 0 ? sc.legacyP512 : []] where !gs.isEmpty && !sc.clear(cx: cx, cz: cz, reach: 3, guardSet: gs) {
                loopNote?("loop: old ground"); return nil
            }
        }
        let flat = run.map { IVec3($0.0, 0, $0.1) }
        let key = loopKey(row, s, east: east)
        if gen.fieldWorld, let hs = l.heights {
            guard let h = gentleProfile(gen, flat, [], ends: (hs[east ? n - 1 : 0], hs[j]), floatCurves: true) else { loopNote?("loop: field grade"); return nil }
            let lp = Line(id: key, name: l.name, cells: flat.indices.map { IVec3(flat[$0].x, Int(h[$0].rounded()), flat[$0].z) }, stations: [], heights: h)
            lp.joins = j
            return lp
        }
        guard let lv = profile(gen, flat, [], ends: (e.y, l.cells[j].y)) else { loopNote?("loop: block profile"); return nil }
        let lp = Line(id: key, name: l.name, cells: flat.indices.map { IVec3(flat[$0].x, lv[$0], flat[$0].z) }, stations: [])
        lp.joins = j
        return lp
    }

    // Loops whose track may pass within `pad` blocks of the box (drawn with the lines).
    static func loopsNear(_ gen: WorldGen, x0: Int, z0: Int, x1: Int, z1: Int, pad: Int = 2, wait: Bool = true) -> [Line] {
        guard on, loopsOn else { return [] }
        let reach = loopReach + 4
        var out: [Line] = []
        for l in near(gen, x0: x0 - reach, z0: z0 - reach, x1: x1 + reach, z1: z1 + reach, pad: pad, wait: wait) {
            let (w, e) = loops(gen, l, wait: wait)
            for lp in [w, e].compactMap({ $0 }) {
                if lp.maxX + pad < x0 || lp.minX - pad > x1 || lp.maxZ + pad < z0 || lp.minZ - pad > z1 { continue }
                out.append(lp)
            }
        }
        return out
    }
}

extension Trains {
    // A line with a loop at each end as one circuit, east along the line from the west junction, round the east loop,
    // west along the line, round the west loop and back (each cell of the line twice, once each way). Its train calls
    // at every station each way, at an end station once (after coming round its loop), and never turns round.
    static func cyclicTrack(_ l: Railways.Line, west lw: Railways.Line, east le: Railways.Line) -> Track? {
        let n = l.cells.count
        let jw = lw.joins, je = le.joins
        guard jw >= 0, je < n, jw < je, let first = l.stations.first, let last = l.stations.last,
              l.stations.allSatisfy({ $0.index > jw && $0.index < je }) else { return nil }
        // Rail heights (the drawn track's: a block line's slopes are half a block up).
        func base(_ ln: Railways.Line, _ i: Int) -> Float {
            if let h = ln.heights { return h[i] }
            return Float(ln.cells[i].y) + ((2...5).contains(ln.shape(i)) ? 0.5 : 0)
        }
        var cells: [IVec3] = [], ys: [Float] = []
        for i in jw..<n { cells.append(l.cells[i]); ys.append(base(l, i)) }
        for k in le.cells.indices { cells.append(le.cells[k]); ys.append(base(le, k)) }
        let back0 = cells.count
        for i in stride(from: je, through: 0, by: -1) { cells.append(l.cells[i]); ys.append(base(l, i)) }
        for k in lw.cells.indices { cells.append(lw.cells[k]); ys.append(base(lw, k)) }
        var stops: [(Int, String)] = []
        for st in l.stations where st.index != last.index || l.stations.count == 1 { stops.append((st.index - jw, st.name + " Station")) }
        for st in l.stations where st.index != first.index { stops.append((back0 + (je - st.index), st.name + " Station")) }
        stops.sort { $0.0 < $1.0 }
        guard stops.count >= 2 else { return nil }
        let t = Track(id: l.id, name: l.name, cells: cells, slopes: cells.map { _ in false }, stops: stops.map { $0.0 },
                      stopNames: stops.map { $0.1 }, armoured: false, dim: .overworld, heights: ys, cyclic: true)
        // The rails to put back on a cleared cell: the drawn shapes (the line's own at the junctions, not the turn).
        var shapes: [Int] = []
        for i in jw..<n { shapes.append(l.shape(i)) }
        for k in le.cells.indices { shapes.append(le.shape(k)) }
        for i in stride(from: je, through: 0, by: -1) { shapes.append(l.shape(i)) }
        for k in lw.cells.indices { shapes.append(lw.shape(k)) }
        t.shapes = shapes
        t.parts = [l]
        t.source = n
        return t
    }
}

// The loops' check (--rail-only): over twelve field-world seeds, how a line's ends go on (a link, a loop or buffers,
// and why a loop didn't fit); for the smallest line with a loop at each end: its circuit joined step to step at the
// rails' heights, the timetable calling at each station each way and only ever running forward; drawn, the loop's rails
// laid and no buffers past the end; and ridden from the end station, the train goes round the loop and back along the
// line without turning or standing.
enum RailLoopCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        var ends = 0, linked = 0, looped = 0, bad: [String] = []
        var why: [String: Int] = [:]
        let lock = NSLock()
        let note0 = Railways.loopNote
        Railways.loopNote = { k in lock.lock(); why[k, default: 0] += 1; lock.unlock() }
        defer { Railways.loopNote = note0 }
        var pick: (UInt64, Railways.Line, Railways.Line, Railways.Line)?
        for k in 0..<12 {
            let seed = UInt64(1000 + k * 7919)
            let gen = WorldGen(seed: seed)
            gen.fieldWorld = true
            for l in Railways.near(gen, x0: -6000, z0: -6000, x1: 6000, z1: 6000, pad: 0) {
                let o = Railways.openEnds(gen, l), lp = Railways.loops(gen, l)
                ends += 2
                linked += (o.west ? 1 : 0) + (o.east ? 1 : 0)
                looped += (lp.west != nil ? 1 : 0) + (lp.east != nil ? 1 : 0)
                for x in [lp.west, lp.east].compactMap({ $0 }) {
                    // Each loop: from beside the end, a step at a time, into beside its junction.
                    let end = x === lp.east ? l.cells.last! : l.cells.first!
                    let chain = [end] + x.cells + [l.cells[x.joins]]
                    for i in 1..<chain.count where abs(chain[i].x - chain[i - 1].x) + abs(chain[i].z - chain[i - 1].z) != 1 {
                        bad.append("seed \(seed) \(l.name): loop step \(i) not adjacent"); break
                    }
                }
                if let w = lp.west, let e = lp.east, pick == nil || l.cells.count < pick!.1.cells.count { pick = (seed, l, w, e) }
            }
        }
        let whyText = why.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print("rail loops: \(ends) line ends: \(linked) run on by links, \(looped) turn in loops, \(ends - linked - looped) buffers; \(whyText)")
        check(ends > 0 && (linked + looped) * 10 >= ends * 8 && bad.isEmpty,
              "P511 loops: of \(ends) line ends \(linked) run on and \(looped) turn in a loop, \(ends - linked - looped) keep buffers (\(whyText))"
              + (bad.isEmpty ? "" : ": " + bad.prefix(3).joined(separator: "; ")))
        guard let (seed, l, lw, le) = pick, let t = Trains.cyclicTrack(l, west: lw, east: le) else { check(false, "P511 loops: no line with a loop at each end"); return }
        // The circuit: every step to the next one cell on (round the seam too), the rail heights a grade's step apart.
        let n = t.cells.count
        var gaps = 0, jumps = 0
        for i in 0..<n {
            let a = t.cells[i], b = t.cells[(i + 1) % n]
            if abs(a.x - b.x) + abs(a.z - b.z) != 1 { gaps += 1 }
            if abs(t.ys[i] - t.ys[(i + 1) % n]) > Railways.grade + 0.02 { jumps += 1 }
        }
        // The timetable over a lap: forward only, no jumps, calling at every station both ways but the end ones once.
        // (from where the walk starts: t.at(0) is the timetable at phase, a leap and a backing step from the first sample)
        var back = 0, leaps = 0, calls = Set<Int>(), lastS = t.at(-t.phase).s
        var inEast = false, inWest = false
        let eastFrom = l.cells.count - lw.joins, eastTo = eastFrom + le.cells.count
        let westFrom = n - lw.cells.count
        var u = 0.0
        while u < t.period {
            let a = t.at(u - t.phase)
            if a.dir < 0 { back += 1 }
            let d = t.delta(lastS, a.s)
            if d < -0.01 { back += 1 }
            if abs(d) > Trains.speed * 2 { leaps += 1 }
            if let st = a.stop { calls.insert(st) }
            if Int(a.s) >= eastFrom && Int(a.s) < eastTo { inEast = true }
            if Int(a.s) >= westFrom { inWest = true }
            lastS = a.s
            u += 0.25
        }
        check(gaps == 0 && jumps == 0 && back == 0 && leaps == 0 && calls.count == t.stops.count && t.stops.count == 2 * l.stations.count - 2 && inEast && inWest,
              String(format: "P511 loops: %@ (seed %llu) runs as a circuit of %d cells (%d gaps, %d height jumps); a %.0f s lap calls at %d of %d stops, round both loops (%@, %@), backing %d, leaps %d",
                     l.name, seed, n, gaps, jumps, t.period, calls.count, t.stops.count, inEast ? "east" : "-", inWest ? "west" : "-", back, leaps))
        // Drawn: the east loop's rails laid, no buffer stop past the line's east end.
        let world = World(seed: seed, device: g0.world.device, save: nil)
        world.makeFieldWorld()
        world.renderDistance = 3; world.activeDistance = 3
        let g = Game(world: world, save: nil, persistent: false)
        g.paused = false; g.survival = false
        let e = l.cells.last!
        _ = world.loadSync(center: V3(Float(e.x), Float(e.y), Float(e.z + 8)), radius: 3)
        let laid = le.cells.filter { Rails.isRail(world.block($0.x, $0.y, $0.z)) }.count
        let buffer = world.block(e.x + 1, e.y + 1, e.z) == Blocks.id("red_wool")
        check(laid * 10 >= le.cells.count * 9 && !buffer && Rails.isRail(world.block(e.x + 1, e.y, e.z)),
              "P511 loops: past \(l.name)'s east end its loop is laid (\(laid) of \(le.cells.count) rails), no buffer stop (\(buffer))")
        // Ridden from the end station: round the loop and back west along the line, never standing or turning.
        guard let last = l.stations.last else { return }
        let sc = l.cells[last.index]
        g.player.pos = V3(Float(sc.x) + 0.5, Float(sc.y), Float(sc.z - 3) + 0.5)
        _ = world.loadSync(center: g.player.pos, radius: 7)
        Trains.trains.removeAll(); Trains.throughOut.removeAll()
        // (the clock 10 s before the train reaches the end station eastbound: it runs straight into the loop)
        let lastEast = last.index - lw.joins
        var at = g.time
        var v = 0.0
        while v < t.period { let a = t.at(g.time + v); if a.stop == nil && Float(lastEast) - a.s > 60 && Float(lastEast) - a.s < 90 { at = g.time + v; break }; v += 0.5 }
        g.time = at
        Trains.forceKind = .passenger
        defer { Trains.forceKind = nil }
        // (its loops planned: the first ticks plan them on a worker)
        var ready = 0
        while ready < 200 { Trains.tick(g); if Trains.trains[l.id]?.track.cyclic == true && Trains.trains[l.id]?.cars.isEmpty == false { break }; usleep(10_000); ready += 1 }
        guard let tr = Trains.trains[l.id], tr.track.cyclic, !tr.cars.isEmpty else {
            check(false, "P511 loops: no train on \(l.name)'s circuit (\(Trains.trains[l.id].map { $0.track.cyclic ? "cyclic, no cars" : "not cyclic" } ?? "none"))"); return
        }
        let dt: Float = 1.0 / 60
        var frames = 0, maxS = tr.lastS, rounded = false, home = false, stood = 0, worstStood = 0, turned = 0
        let s0 = tr.lastS
        var prev = tr.lastS
        while frames < 60 * 240 && !home {
            g.tick(Double(dt))
            frames += 1
            let s = tr.lastS
            let d = tr.track.delta(prev, s)
            if d < -0.05 { turned += 1 }
            prev = s
            if Int(s) >= eastFrom && Int(s) < eastTo { rounded = true }
            if rounded && Int(s) >= eastTo + 30 && Int(s) < westFrom { home = true }
            if tr.blocksPerSec < 0.05 && Trains.now(tr).stop == nil { stood += 1; worstStood = max(worstStood, stood) } else { stood = 0 }
            maxS = max(maxS, s)
            // (he keeps by the train, as riding it: left at the station, the loop's far side was out past the
            // check world's active ground and the train stood there)
            if frames % 90 == 0, let head = tr.cars.first?.pos {
                g.player.pos = head + V3(0, 6, 0); g.player.flying = true
                _ = world.loadSync(center: head, radius: 3)
            }
        }
        check(rounded && home && turned == 0 && worstStood < 60 * 3,
              String(format: "P511 loops: the train from %.0f went round the east loop (%@) and back along the line westbound (%@) in %.0f s, backing %d frames, longest stand off a stop %.1f s",
                     s0, rounded ? "yes" : "no", home ? "yes" : "no", Float(frames) * dt, turned, Float(worstStood) * dt))
        Trains.trains.removeAll(); Trains.throughOut.removeAll()
    }
}
