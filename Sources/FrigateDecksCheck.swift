import Foundation

// P450 + P461's check (questcheck --frigatedecks): the Stormwarden Frigate's hull with its decks against the bare shell it
// was: blocks, ladders, stairs, the quads its mesh draws, and a walk from the hangar floor (on foot: steps of one block,
// falls, no ladders) to the bridge, the top deck in the bow, the keel and the engine hall, and onto every deck.
enum FrigateDecksCheck {
    static func run(_ check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        Capital.decksOff = true
        let old = Capital.frigate()
        Capital.decksOff = false
        let hb = Capital.frigate()
        let built = CFAbsoluteTimeGetCurrent() - t0
        func census(_ h: HullBuilder) -> (blocks: Int, ladders: Int, stairs: Int) {
            var n = 0, l = 0, st = 0
            let ladder = Blocks.groupBase[Int(Blocks.id("ladder"))], stair = Blocks.groupBase[Int(Blocks.id("steel_plating_stairs"))]
            for b in h.blocks where b != AIR {
                n += 1
                let g = Blocks.groupBase[Int(b)]
                if g == ladder { l += 1 } else if g == stair { st += 1 }
            }
            return (n, l, st)
        }
        // All the quads, and those drawn from outside the hull (its outer copy: the sealed decks filled in).
        var outerTime: Double = 0
        func quads(_ h: HullBuilder) -> (Int, Int, Int) {
            let secs = ShipMesh.build(sx: h.sx, sy: h.sy, sz: h.sz, blocks: h.blocks, only: nil)
            let tf = CFAbsoluteTimeGetCurrent()
            let outer = ShipMesh.outerBuild(sx: h.sx, sy: h.sy, sz: h.sz, blocks: h.blocks) ?? secs
            outerTime = CFAbsoluteTimeGetCurrent() - tf
            func n(_ l: [(Int, SectionMesh, V3)]) -> Int { l.reduce(0) { $0 + ($1.1.opaque.count + $1.1.trans.count) / 8 } }
            return (n(secs), n(outer), secs.count)
        }
        let c0 = census(old), c1 = census(hb)
        let t1 = CFAbsoluteTimeGetCurrent()
        let (q0, _, n0) = quads(old), (q1, qo, n1) = quads(hb)
        let meshed = CFAbsoluteTimeGetCurrent() - t1

        // The walk (builder coordinates: x from the centre line).
        let collide = Blocks.collide
        func solid(_ x: Int, _ y: Int, _ z: Int) -> Bool { let b = Int(hb.get(x, y, z)); return collide[b] && Blocks.shape[b] != "door" }   // (he opens doors)
        func stand(_ x: Int, _ y: Int, _ z: Int) -> Bool { !solid(x, y, z) && !solid(x, y + 1, z) && solid(x, y - 1, z) }
        let W = hb.ox
        func key(_ x: Int, _ y: Int, _ z: Int) -> Int { (x + W) + z * hb.sx + y * hb.sx * hb.sz }
        var seen = Set<Int>(), queue: [(Int, Int, Int)] = [(0, 27, 250)]
        seen.insert(key(0, 27, 250))
        var head = 0
        while head < queue.count {
            let (x, y, z) = queue[head]; head += 1
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, nz = z + dz
                guard nx >= -W && nx <= W && nz >= 0 && nz < hb.sz else { continue }
                var to: Int? = nil
                if stand(nx, y + 1, nz) && !solid(x, y + 2, z) { to = y + 1 }
                else if !solid(nx, y, nz) && !solid(nx, y + 1, nz) {
                    for dy in 0...6 where y - dy > 0 {
                        if stand(nx, y - dy, nz) { to = y - dy; break }
                        if solid(nx, y - dy - 1, nz) { break }
                    }
                }
                guard let ty = to, seen.insert(key(nx, ty, nz)).inserted else { continue }
                queue.append((nx, ty, nz))
            }
        }
        func reached(_ x: Int, _ y: Int, _ z: Int) -> Bool { seen.contains(key(x, y, z)) }
        var levels: [String] = [], missed = 0
        for f in Capital.frigateLevels {
            var all = 0, got = 0
            for z in stride(from: 0, to: hb.sz, by: 2) { for x in stride(from: -W, through: W, by: 2) where stand(x, f + 1, z) && hb.get(x, f, z) == Blocks.id("steel_grating") {
                all += 1; if reached(x, f + 1, z) { got += 1 }
            } }
            if all > 0 { levels.append("\(f): \(got)/\(all)"); if got * 10 < all * 9 { missed += 1 } }
        }
        let spots = [("bridge", reached(0, 77, 322)), ("bow top deck", reached(10, 77, 100)), ("keel", reached(0, 12, 250)), ("engine hall", reached(0, 21, 420))]
        check(c1.ladders == 0 && c1.stairs > 0 && spots.allSatisfy { $0.1 } && missed == 0,
              String(format: "frigatedecks: Stormwarden Frigate %d blocks (bare shell %d), ladders %d (were %d), stair blocks %d; walking from the hangar floor reaches %@; decks reached (floor cells, every second): %@; built in %.1f s",
                     c1.blocks, c0.blocks, c1.ladders, c0.ladders, c1.stairs, spots.map { "\($0.0) \($0.1 ? "yes" : "NO")" }.joined(separator: ", "), levels.joined(separator: ", "), built))
        // Where outside air gets into the decks, if it does: a path from the grid's edge to a hallway, with the blocks
        // it passes (see-through ones) and where it crosses into the hull.
        func leak(_ h: HullBuilder, to t: (Int, Int, Int)) -> String {
            let sx = h.sx, sy = h.sy, sz = h.sz, layer = sx * sz, n = sx * sy * sz
            var from = [Int32](repeating: -2, count: n)
            var q: [Int32] = []
            q.reserveCapacity(1 << 20)
            func pass(_ i: Int) -> Bool {
                let b = Int(h.blocks[i]), sh = Blocks.shape[b]
                return !Blocks.opaque[b] && sh != "door" && sh != "trapdoor" && sh != "gate"
            }
            for y in 0..<sy { for z in 0..<sz { for x in 0..<sx where x == 0 || x == sx - 1 || y == 0 || y == sy - 1 || z == 0 || z == sz - 1 {
                let i = x + z * sx + y * layer
                if pass(i) { from[i] = -1; q.append(Int32(i)) }
            } } }
            var head = 0
            while head < q.count {
                let i = Int(q[head]); head += 1
                let y = i / layer, r = i - y * layer, z = r / sx, x = r - z * sx
                var nb: [Int] = []
                if x > 0 { nb.append(i - 1) }; if x < sx - 1 { nb.append(i + 1) }
                if z > 0 { nb.append(i - sx) }; if z < sz - 1 { nb.append(i + sx) }
                if y > 0 { nb.append(i - layer) }; if y < sy - 1 { nb.append(i + layer) }
                for j in nb where from[j] == -2 && pass(j) { from[j] = Int32(i); q.append(Int32(j)) }
            }
            let ti = (t.0 + h.ox) + t.2 * sx + t.1 * layer
            guard from[ti] != -2 else { return "sealed" }
            var path: [Int] = []
            var c = ti
            while c >= 0 { path.append(c); c = Int(from[c]) }
            var notes: [String] = [], wasIn = false
            for i in path.reversed() {
                let y = i / layer, r = i - y * layer, z = r / sx, x = r - z * sx - h.ox
                let inside = Capital.frigateInside(x, y, z)
                if inside && !wasIn { notes.append("into the hull at \(x),\(y),\(z)") }
                wasIn = inside
                let b = h.blocks[i]
                if b != AIR { notes.append("\(Blocks.key(b)) at \(x),\(y),\(z)") }
            }
            var trail: [String] = []
            for (k, i) in path.reversed().enumerated() where k % 6 == 0 {
                let y = i / layer, r = i - y * layer, z = r / sx, x = r - z * sx - h.ox
                trail.append("\(x),\(y),\(z)")
            }
            return "\(path.count) cells: " + notes.prefix(14).joined(separator: ", ") + "; by " + trail.joined(separator: " ")
        }
        print("frigatedecks: outside air to the hallway at deck 21: " + leak(hb, to: (0, 22, 250)))
        print("frigatedecks: outside air to the hallway at deck 51: " + leak(hb, to: (0, 52, 100)))
        // Drawn from outside: the decks sealed behind the hull and its doors are left out.
        check(qo * 2 <= q0 * 3,
              String(format: "frigatedecks: mesh quads %d in %d sections (bare shell %d in %d, x%.2f); drawn from outside the hull %d (x%.2f the shell; its outer copy built in %.1f s); meshed both in %.1f s",
                     q1, n1, q0, n0, Float(q1) / Float(max(1, q0)), qo, Float(qo) / Float(max(1, q0)), outerTime, meshed))
    }
}
