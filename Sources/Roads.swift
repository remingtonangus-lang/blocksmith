import Foundation
import simd

// P51 (Oct 11 evening playtest): roads between towns, riders on them you can rob, a town's posse after a robber, and
// bounty hunters with guns.
//   Roads    a dirt road from each town square to the squares of the towns in the next village regions east and
//            south (and the diagonals), when they are less than `maxLen` apart. Gently winding, three blocks wide, only
//            over natural ground (grass, snowy grass, dirt, sand, snow) with open air above, never through a building or water.
//            Only on ground first generated with them (WorldRules.savedBeforeP44 all along the road, the P44 guard),
//            so no road ends at the edge of explored land.
//   Riders   now and then a traveller on horseback rides a road near the player (Riders, below).
enum Roads {
    static let maxLen: Float = 720
    static let halfWidth: Float = 1.3

    // `way` (ledger 237, new worlds): the road's own winding way over the land, a point every few blocks from a to b,
    // and `cum` the length along it to each point. Nil: the straight road with a gentle bend, as before.
    struct Seg { let a: V2; let b: V2; let phase: Float; var bridges: [Bridge] = []; var way: [V2]? = nil; var cum: [Float] = [] }
    // P510 (Nov 1 20:40, "roads and also bridges where needed for the roads"): a road met a river or a lake and simply
    // stopped at its bank. Where its line crosses water (up to `bridgeMax` across), it goes over on a stone bridge: a
    // deck clear of the water by a block or more, as high as the higher bank, stepping down a block a cell onto the
    // lower bank, with a parapet each side and a pier into the bed every seventh cell. `ys`: the deck block's y at road
    // cells j0, j0 + 1, ... (a cell is 1 / n of the road).
    struct Bridge { let j0: Int; let ys: [Int]; let n: Int }
    static let bridgeMax = 96
    static var bridgesPlanned = 0                    // (checks)

    struct Key: Hashable { let kind: Int8; let rx: Int32; let rz: Int32; let d: Int8 }   // kind 0 road, 1 far road, 2 site road
    private static var cache: [Key: Seg?] = [:]
    private static var cacheGen: Int?               // the generator the cache was filled for (another world clears it; by
                                                    // its plan serial: a freed generator's address comes back for the next, P510)
    private static let lock = NSLock()
    static var on: Bool { WorldRules.p44 }
    static func forget() { lock.lock(); cache.removeAll(); lock.unlock() }      // (the checks: the same ground laid both ways)

    // The village region's town square (nil: no town there).
    static func square(_ gen: WorldGen, _ rx: Int, _ rz: Int) -> V2? {
        guard let sc = gen.structures, let t = sc.types.first(where: { $0.name == "village" }),
              let s = sc.start(t, regionX: rx, regionZ: rz) else { return nil }
        return V2(Float(s.anchor.x), Float(s.anchor.z))
    }

    // The road from region (rx, rz) to its neighbour (rx + dx, rz + dz), if one runs.
    static func segment(_ gen: WorldGen, _ rx: Int, _ rz: Int, _ dx: Int, _ dz: Int) -> Seg? {
        let key = Key(kind: 0, rx: Int32(truncatingIfNeeded: rx), rz: Int32(truncatingIfNeeded: rz), d: Int8((dx + 1) * 3 + dz + 1))
        let gid = gen.planSerial
        lock.lock()
        if cacheGen != gid { cache.removeAll(); cacheGen = gid }
        if let c = cache[key] { lock.unlock(); return c }
        lock.unlock()
        var seg: Seg?
        if let a = square(gen, rx, rz), let b = square(gen, rx + dx, rz + dz), simd_length(b - a) < maxLen {
            // The whole road on new ground (sample every 8 chunks).
            let n = Int(simd_length(b - a) / 128) + 1
            var fresh = true
            for i in 0...n where fresh {
                let p = a + (b - a) * (Float(i) / Float(n))
                if WorldRules.savedBeforeP44(gen, floorDiv(Int(p.x), CS), floorDiv(Int(p.y), CS), reach: 5) { fresh = false }
            }
            if fresh {
                seg = Seg(a: a, b: b, phase: hashf(rx, rz, dx * 7 + dz, UInt32(truncatingIfNeeded: gen.seed) ^ 0x80AD) * 6.28)
                wind(gen, &seg!); seg!.bridges = bridges(gen, seg!)
            }
        }
        lock.lock(); if cacheGen == gid { cache[key] = seg }; if cache.count > 16384 { cache.removeAll() }; lock.unlock()
        return seg
    }

    // P510: ground no save had before this build (structure-guard-p510.txt) along a road (sampled every 4 chunks):
    // the roads and bridges P510 added go only there, so none ends at the edge of explored land.
    static func freshP510(_ gen: WorldGen, _ a: V2, _ b: V2, reach: Int = 3) -> Bool {
        guard let sc = gen.structures, !sc.legacyP510.isEmpty else { return true }
        let n = Int(simd_length(b - a) / 64) + 1
        for i in 0...n {
            let p = a + (b - a) * (Float(i) / Float(n))
            if !sc.clear(cx: floorDiv(Int(p.x), CS), cz: floorDiv(Int(p.y), CS), reach: reach, guardSet: sc.legacyP510) { return false }
        }
        return true
    }

    // P510 (Nov 1 16:26, "roads everywhere"; 20:40, "now we need some roads... assuming those haven't been added
    // yet"): a road ran only between towns in neighbouring regions, so a town whose neighbours were empty (half the
    // small places are left out on new ground, P499) had none, and he flew hundreds of blocks of open country without
    // meeting one. Past an empty neighbour a road now runs on to the town in the region beyond (up to `farLen`), and
    // each of the major sites (the Capital's citadels and cities, Greywall bases, Boreal stations) has a road to its
    // nearest town (up to `siteLen`). Both only on ground no save had before this build.
    static let farLen: Float = 1300, siteLen: Float = 1100
    static func farSegment(_ gen: WorldGen, _ rx: Int, _ rz: Int, _ dx: Int, _ dz: Int) -> Seg? {
        let key = Key(kind: 1, rx: Int32(truncatingIfNeeded: rx), rz: Int32(truncatingIfNeeded: rz), d: Int8((dx + 1) * 3 + dz + 1))
        let gid = gen.planSerial
        lock.lock()
        if cacheGen != gid { cache.removeAll(); cacheGen = gid }
        if let c = cache[key] { lock.unlock(); return c }
        lock.unlock()
        var seg: Seg?
        if square(gen, rx + dx, rz + dz) == nil, let a = square(gen, rx, rz), let b = square(gen, rx + 2 * dx, rz + 2 * dz),
           simd_length(b - a) < farLen, freshP510(gen, a, b) {
            seg = Seg(a: a, b: b, phase: hashf(rx, rz, dx * 7 + dz + 50, UInt32(truncatingIfNeeded: gen.seed) ^ 0x80AD) * 6.28)
            wind(gen, &seg!); seg!.bridges = bridges(gen, seg!)
        }
        lock.lock(); if cacheGen == gid { cache[key] = seg }; if cache.count > 16384 { cache.removeAll() }; lock.unlock()
        return seg
    }
    static let siteKinds = ["military_base", "capital_city", Greywall.kind, BorealStation.kind]
    static func siteSegment(_ gen: WorldGen, _ t: StructureType, _ ti: Int, _ rx: Int, _ rz: Int) -> Seg? {
        let key = Key(kind: 2, rx: Int32(truncatingIfNeeded: rx), rz: Int32(truncatingIfNeeded: rz), d: Int8(ti))
        let gid = gen.planSerial
        lock.lock()
        if cacheGen != gid { cache.removeAll(); cacheGen = gid }
        if let c = cache[key] { lock.unlock(); return c }
        lock.unlock()
        // (a site's start is a heavy plan: never made on the frame thread, where riders ask; the chunks' workers make it)
        if Thread.isMainThread, let sc = gen.structures, !sc.isCached(t, regionX: rx, regionZ: rz) { return nil }
        var seg: Seg?
        if let sc = gen.structures, let o = sc.start(t, regionX: rx, regionZ: rz), o.max.y >= SEA {
            // From the site's edge nearest the town (its gate side) to the town's square.
            let mid = V2(Float(o.min.x + o.max.x) / 2, Float(o.min.z + o.max.z) / 2)
            let span = 34 * CS
            var best: V2?, bd = siteLen
            let vx = floorDiv(Int(mid.x), span), vz = floorDiv(Int(mid.y), span)
            for z in (vz - 2)...(vz + 2) { for x in (vx - 2)...(vx + 2) {
                guard let q = square(gen, x, z) else { continue }
                let d = simd_length(q - mid)
                if d < bd { bd = d; best = q }
            } }
            if let b = best {
                let dir = simd_normalize(b - mid)
                let half = V2(Float(o.max.x - o.min.x), Float(o.max.z - o.min.z)) * 0.5
                let out = min(abs(dir.x) > 0.01 ? half.x / abs(dir.x) : 1e9, abs(dir.y) > 0.01 ? half.y / abs(dir.y) : 1e9) + 4
                let a = mid + dir * out
                if simd_length(b - a) > 40 && freshP510(gen, a, b) {
                    seg = Seg(a: a, b: b, phase: hashf(rx, rz, ti + 90, UInt32(truncatingIfNeeded: gen.seed) ^ 0x80AD) * 6.28)
                    wind(gen, &seg!); seg!.bridges = bridges(gen, seg!)
                }
            }
        }
        lock.lock(); if cacheGen == gid { cache[key] = seg }; if cache.count > 16384 { cache.removeAll() }; lock.unlock()
        return seg
    }

    // The bridges a road needs: its water crossings (from the generator's columns, so every chunk agrees).
    static func bridges(_ gen: WorldGen, _ s: Seg) -> [Bridge] {
        let n = max(2, Int(length(s)))
        var wet = [Bool](repeating: false, count: n + 1), land = [Int](repeating: 0, count: n + 1), top = [Int](repeating: 0, count: n + 1)
        for i in 0...n {
            let p = point(s, Float(i) / Float(n))
            let k = gen.columnData(Int(floor(p.x)), Int(floor(p.y)))
            land[i] = YOFF + Int(floorf(k.h))
            wet[i] = k.wl > k.h + 0.3
            top[i] = YOFF + Int(ceilf(k.wl)) - 1
        }
        var out: [Bridge] = []
        var i = 0
        while i <= n {
            guard wet[i] else { i += 1; continue }
            var e = i
            while e + 1 <= n && wet[e + 1] { e += 1 }
            defer { i = e + 1 }
            guard i > 0, e < n, e - i + 1 <= bridgeMax else { continue }
            // (only on ground no save had before this build, ramps and all: a road there keeps its old gap)
            let pa = point(s, Float(max(0, i - 12)) / Float(n)), pb = point(s, Float(min(n, e + 12)) / Float(n))
            guard freshP510(gen, pa, pb, reach: 1) else { continue }
            let water = (i...e).reduce(Int.min) { max($0, top[$1]) }
            let deck = max(land[i - 1], land[e + 1], water + 2)
            // Out over each bank until the deck, stepping down a block a cell, meets the ground.
            var a = i - 1, b = e + 1
            while a > 0 && deck - (i - a) > land[a] && i - a < 12 { a -= 1 }
            while b < n && deck - (b - e) > land[b] && b - e < 12 { b += 1 }
            let ys = (a...b).map { j in j < i ? max(land[j], deck - (i - j)) : (j > e ? max(land[j], deck - (j - e)) : deck) }
            out.append(Bridge(j0: a, ys: ys, n: n))
            bridgesPlanned += 1
        }
        return out
    }

    // Roads that may pass within `pad` blocks of the box (x0...x1, z0...z1).
    static func near(_ gen: WorldGen, x0: Int, z0: Int, x1: Int, z1: Int, pad: Float = 8) -> [Seg] {
        guard on else { return [] }
        let span = 34 * CS
        let rx0 = floorDiv(x0, span) - 2, rx1 = floorDiv(x1, span) + 1
        let rz0 = floorDiv(z0, span) - 2, rz1 = floorDiv(z1, span) + 1
        var out: [Seg] = []
        func take(_ s: Seg) {
            let box = bounds(s)
            let lo = box.0 - V2(repeating: pad + 12), hi = box.1 + V2(repeating: pad + 12)
            if Float(x1) < lo.x || Float(x0) > hi.x || Float(z1) < lo.y || Float(z0) > hi.y { return }
            out.append(s)
        }
        for rz in (rz0 - 1)...(rz1 + 1) { for rx in (rx0 - 1)...rx1 {
            for (dx, dz) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
                let inner = rz >= rz0 && rz <= rz1 && rx >= rx0
                if inner, let s = segment(gen, rx, rz, dx, dz) { take(s) }
                if let s = farSegment(gen, rx, rz, dx, dz) { take(s) }
            }
        } }
        // Each major site's road to its town (a site's region; the road reaches siteLen past it).
        if let sc = gen.structures {
            for (ti, name) in siteKinds.enumerated() {
                guard let t = sc.types.first(where: { $0.name == name }) else { continue }
                let sp = t.spacing * CS, r = Int(siteLen) + Int(pad) + t.reach * CS
                for rz in floorDiv(z0 - r, sp)...floorDiv(z1 + r, sp) { for rx in floorDiv(x0 - r, sp)...floorDiv(x1 + r, sp) {
                    if let s = siteSegment(gen, t, ti, rx, rz) { take(s) }
                } }
            }
        }
        return out
    }

    // Ledger 237 (Nov 17 evening: "the roads are too straight", "path of least resistance", and on a mountainside at
    // -4794 163 -1642 "road cannot go through here"): a road was the straight line between its two ends with a seven
    // block wiggle, whatever lay between, so it ran up cliffs and over peaks. In a new world it finds its own way over
    // 16-block squares of land: a climb costs it far more than distance, water more still (a short crossing is
    // bridged as before), and a slow field of easier and harder going bends it on flat land too. Its way is thinned to
    // its turns and rounded. Old worlds keep their roads as laid (the ledger 230 guard); BS_OLDROADS=1: as before.
    static let oldRoads = Env.all["BS_OLDROADS"] == "1"
    static var windOn = true                         // (a var so the checks can lay the same ground both ways)
    static func winding(_ gen: WorldGen) -> Bool { windOn && !oldRoads && (gen.structures?.legacyL230.isEmpty ?? false) }
    static func wind(_ gen: WorldGen, _ s: inout Seg) {
        guard winding(gen) else { return }
        let G = 16
        let pad = 12
        let gx0 = floorDiv(Int(min(s.a.x, s.b.x)), G) - pad, gx1 = floorDiv(Int(max(s.a.x, s.b.x)), G) + pad
        let gz0 = floorDiv(Int(min(s.a.y, s.b.y)), G) - pad, gz1 = floorDiv(Int(max(s.a.y, s.b.y)), G) + pad
        let nx = gx1 - gx0 + 1, nz = gz1 - gz0 + 1
        guard nx * nz <= 40_000 else { return }
        let si = floorDiv(Int(s.a.x), G) - gx0, sj = floorDiv(Int(s.a.y), G) - gz0
        let ei = floorDiv(Int(s.b.x), G) - gx0, ej = floorDiv(Int(s.b.y), G) - gz0
        guard si != ei || sj != ej else { return }
        // Each square's land (looked up once, as the search reaches it) and whether it is under water.
        var high = [Float](repeating: .nan, count: nx * nz), wet = [Bool](repeating: false, count: nx * nz)
        func land(_ k: Int) -> Float {
            if high[k].isNaN {
                let c = gen.columnData((gx0 + k % nx) * G + G / 2, (gz0 + k / nx) * G + G / 2)
                wet[k] = c.wl > c.h + 0.3
                high[k] = wet[k] ? c.wl : c.h
            }
            return high[k]
        }
        let fa = s.phase, fb = s.phase * 1.7 + 1
        func going(_ k: Int) -> Float {
            let x = Float((gx0 + k % nx) * G), z = Float((gz0 + k / nx) * G)
            let wide: Float = 0.5 + 0.5 * sinf(x * 0.012 + fa) * cosf(z * 0.015 + fb)
            let close: Float = 0.5 + 0.5 * sinf(x * 0.031 + fb) * cosf(z * 0.027 + fa)
            return wide * 14 + close * 8 + (wet[k] ? 70 : 0)
        }
        var cost = [Float](repeating: .infinity, count: nx * nz), from = [Int32](repeating: -1, count: nx * nz)
        var done = [Bool](repeating: false, count: nx * nz)
        var heap: [(Float, Int)] = []
        func push(_ e: (Float, Int)) {
            heap.append(e)
            var i = heap.count - 1
            while i > 0, heap[(i - 1) / 2].0 > heap[i].0 { heap.swapAt(i, (i - 1) / 2); i = (i - 1) / 2 }
        }
        func pop() -> (Float, Int) {
            let top = heap[0]
            let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var m = i
                    if l < heap.count && heap[l].0 < heap[m].0 { m = l }
                    if r < heap.count && heap[r].0 < heap[m].0 { m = r }
                    if m == i { break }
                    heap.swapAt(i, m); i = m
                }
            }
            return top
        }
        let start = si + sj * nx, end = ei + ej * nx
        func ahead(_ k: Int) -> Float {
            let dx = Float(k % nx - ei), dz = Float(k / nx - ej)
            return (dx * dx + dz * dz).squareRoot() * Float(G)
        }
        cost[start] = 0
        push((ahead(start), start))
        var found = false
        while !heap.isEmpty {
            let (_, k) = pop()
            if done[k] { continue }
            done[k] = true
            if k == end { found = true; break }
            let i = k % nx, j = k / nx, h = land(k)
            for dj in -1...1 { for di in -1...1 where di != 0 || dj != 0 {
                let ni = i + di, nj = j + dj
                guard ni >= 0, nj >= 0, ni < nx, nj < nz else { continue }
                let q = ni + nj * nx
                if done[q] { continue }
                let step: Float = di != 0 && dj != 0 ? 22.6 : 16
                let climb = abs(land(q) - h)
                // (a block up in sixteen is nothing; a block in four is a hard road; steeper than one in two is a cliff)
                let steep: Float = climb > 8 ? (climb - 8) * 40 : 0
                let c = cost[k] + step + climb * 6 + steep + going(q) * step / 16
                if c < cost[q] { cost[q] = c; from[q] = Int32(k); push((c + ahead(q), q)) }
            } }
        }
        guard found else { return }
        var sq: [Int] = []
        var k = end
        while k != start { sq.append(k); k = Int(from[k]); if k < 0 { return } }
        sq.reverse()
        var raw: [V2] = [s.a]
        for q in sq.dropLast() { raw.append(V2(Float((gx0 + q % nx) * G + G / 2), Float((gz0 + q / nx) * G + G / 2))) }
        raw.append(s.b)
        // Thinned to its turns (anything within 9 blocks of the line between two kept points goes), then each corner cut
        // round three times, then a point every 5 blocks or so.
        var keep = [Bool](repeating: false, count: raw.count)
        keep[0] = true; keep[raw.count - 1] = true
        var stack = [(0, raw.count - 1)]
        while let (i0, i1) = stack.popLast() {
            guard i1 > i0 + 1 else { continue }
            let p = raw[i0], d = raw[i1] - p, l2 = max(1, simd_length_squared(d))
            var far: Float = 0, at = -1
            for i in (i0 + 1)..<i1 {
                let t = max(0, min(1, simd_dot(raw[i] - p, d) / l2))
                let e = simd_length(raw[i] - (p + d * t))
                if e > far { far = e; at = i }
            }
            if far > 9, at > 0 { keep[at] = true; stack.append((i0, at)); stack.append((at, i1)) }
        }
        var poly = raw.indices.filter { keep[$0] }.map { raw[$0] }
        for _ in 0..<3 {
            guard poly.count > 2 else { break }
            var out: [V2] = [poly[0]]
            for i in 0..<(poly.count - 1) {
                let p = poly[i], q = poly[i + 1]
                if i > 0 { out.append(p + (q - p) * 0.25) }
                if i < poly.count - 2 { out.append(p + (q - p) * 0.75) }
            }
            out.append(poly[poly.count - 1])
            poly = out
        }
        var way: [V2] = [poly[0]], cum: [Float] = [0]
        var total: Float = 0
        for i in 1..<poly.count {
            let p = poly[i - 1], d = poly[i] - p, l = simd_length(d)
            guard l > 0.01 else { continue }
            let parts = max(1, Int((l / 5).rounded()))
            for m in 1...parts {
                way.append(p + d * (Float(m) / Float(parts)))
                total += l / Float(parts)
                cum.append(total)
            }
        }
        guard way.count > 2 else { return }
        s.way = way; s.cum = cum
    }
    // A road's length along its way, and the box it lies in.
    static func length(_ s: Seg) -> Float { s.cum.last ?? simd_length(s.b - s.a) }
    static func bounds(_ s: Seg) -> (V2, V2) {
        guard let w = s.way else { return (simd_min(s.a, s.b), simd_max(s.a, s.b)) }
        var lo = w[0], hi = w[0]
        for p in w { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return (lo, hi)
    }

    // The road's centre line at t (0...1): a straight line with a gentle bend that vanishes at both ends (or, with a
    // way of its own, the point that share of the way along it).
    static func point(_ s: Seg, _ t: Float) -> V2 {
        if let w = s.way {
            let want = max(0, min(1, t)) * s.cum[s.cum.count - 1]
            var lo = 0, hi = w.count - 1
            while hi - lo > 1 { let m = (lo + hi) / 2; if s.cum[m] <= want { lo = m } else { hi = m } }
            let l = s.cum[hi] - s.cum[lo]
            return l > 0 ? w[lo] + (w[hi] - w[lo]) * ((want - s.cum[lo]) / l) : w[lo]
        }
        let d = s.b - s.a, len = max(1, simd_length(d))
        let n = V2(-d.y, d.x) / len
        let bend = sinf(t * len / 90 + s.phase) * 7 * min(1, t * (1 - t) * 8)
        return s.a + d * t + n * bend
    }
    // Distance from p to the road and the t of the nearest point.
    static func distance(_ s: Seg, _ p: V2) -> (Float, Float) {
        if let w = s.way {
            var best = (Float.greatestFiniteMagnitude, Float(0))
            let total = s.cum[s.cum.count - 1]
            for i in 0..<(w.count - 1) {
                let a = w[i], d = w[i + 1] - a
                // (a point every 5 blocks: a leg whose start is 40 or more past the best so far can't be nearer)
                let off = p - a
                if abs(off.x) - 6 > best.0 || abs(off.y) - 6 > best.0 { continue }
                let l2 = max(0.0001, simd_length_squared(d))
                let u = max(0, min(1, simd_dot(off, d) / l2))
                let e = simd_length(off - d * u)
                if e < best.0 { best = (e, (s.cum[i] + (s.cum[i + 1] - s.cum[i]) * u) / total) }
            }
            return best
        }
        let d = s.b - s.a, len2 = max(1, simd_length_squared(d))
        let t0 = max(0, min(1, simd_dot(p - s.a, d) / len2))
        // The bend moves the line by up to 7 blocks: refine near t0.
        var best = (Float.greatestFiniteMagnitude, t0)
        let step = 1 / max(1, sqrtf(len2))
        for k in -12...12 {
            let t = max(0, min(1, t0 + Float(k) * step))
            let e = simd_length(point(s, t) - p)
            if e < best.0 { best = (e, t) }
        }
        return best
    }

    static let natural: [Bool] = {
        var t = [Bool](repeating: false, count: Blocks.count)
        for k in ["grass_block", "dirt", "coarse_dirt", "podzol", "rooted_dirt", "mycelium", "sand", "red_sand", "snow_block", "gravel"] where Blocks.has(k) {
            t[Int(Blocks.id(k))] = true
        }
        return t
    }()

    // Lays the roads through this chunk (StructureCache.place, after the structures).
    static func draw(_ gen: WorldGen, _ w: inout StructWriter, _ cx: Int, _ cz: Int) {
        let bx = cx * CS, bz = cz * CS
        let mid = V2(Float(bx + CS / 2), Float(bz + CS / 2))
        let segs = near(gen, x0: bx, z0: bz, x1: bx + CS - 1, z1: bz + CS - 1).filter { distance($0, mid).0 < 14 }
        guard !segs.isEmpty, Blocks.has("dirt_path") else { return }
        let path = Blocks.id("dirt_path")
        // (PG5: Polygons worlds pave with natural ground, so the smooth surface runs on along the road: StructWriter.set
        // turns the path into packed earth; a sand road is sandstone, not the cut stone a block world's road gets.)
        let sandPath = SmoothTerrain.enabled && Blocks.has("sandstone") ? Blocks.id("sandstone")
            : (Blocks.has("smooth_sandstone") ? Blocks.id("smooth_sandstone") : path)
        // P499: a road runs on across snowy grass (it stopped at the snow line: 34 of 48 columns of a taiga road bare).
        // New ground only: a road already drawn on saved ground keeps its gap rather than ending at a chunk seam.
        let snowy = gen.structures.map { $0.clear(cx: cx, cz: cz, reach: 2, guardSet: $0.legacyP499) } ?? true
        let deck = Blocks.has("stone_bricks") ? Blocks.id("stone_bricks") : STONE
        let parapet = Blocks.has("stone_brick_wall") ? Blocks.id("stone_brick_wall") : deck
        for lz in 0..<CS { for lx in 0..<CS {
            let x = bx + lx, z = bz + lz
            let p = V2(Float(x) + 0.5, Float(z) + 0.5)
            // A bridge's deck and parapets (over the water and its ramps onto the banks).
            var onBridge = false
            for sg in segs where !sg.bridges.isEmpty {
                let (d, t) = distance(sg, p)
                guard d <= halfWidth + 1.2 else { continue }
                for br in sg.bridges {
                    let j = Int((t * Float(br.n)).rounded()) - br.j0
                    guard j >= 0 && j < br.ys.count else { continue }
                    let y = br.ys[j]
                    onBridge = true
                    guard y > 1 && y < CH - 5 else { break }
                    w.set(x, y, z, deck)
                    for dy in 1...4 where !Blocks.isLiquid(w.get(x, y + dy, z)) { w.set(x, y + dy, z, AIR) }
                    if d > halfWidth { w.set(x, y + 1, z, parapet) }
                    // Under it: the bank built up to it, and a pier into the bed every seventh cell.
                    let pier = (j + br.j0) % 7 == 0 && d <= 0.9
                    let floorY = max(1, y - 40)
                    var below = y - 1
                    while below > floorY, !Blocks.isLiquid(w.get(x, below, z)), !(Blocks.collide[Int(w.get(x, below, z))] && !CapitalBase.isLeaf(w.get(x, below, z))) { below -= 1 }
                    let overWater = Blocks.isLiquid(w.get(x, below, z))
                    if !overWater || pier {
                        var yy = y - 1
                        while yy > floorY {
                            let b = w.get(x, yy, z)
                            if Blocks.collide[Int(b)] && !CapitalBase.isLeaf(b) { break }
                            w.set(x, yy, z, deck)
                            yy -= 1
                        }
                    }
                    break
                }
                if onBridge { break }
            }
            if onBridge { continue }
            guard segs.contains(where: { distance($0, p).0 <= halfWidth }) else { continue }
            // The ground under plants, snow and air.
            var y = CH - 2
            while y > 1 {
                let b = w.get(x, y, z)
                if Blocks.collide[Int(b)] && !CapitalBase.isLeaf(b) { break }
                y -= 1
            }
            let top = w.get(x, y, z)
            guard y > SEA - 1, Int(top) < natural.count, natural[Int(top)] || (snowy && top == SNOWY_GRASS) else { continue }
            let above = w.get(x, y + 1, z)
            guard !Blocks.isLiquid(above), !Blocks.collide[Int(above)] else { continue }
            let k = Blocks.key(top)
            w.set(x, y, z, k == "sand" || k == "red_sand" ? sandPath : path)
            for dy in 1...2 where !Blocks.collide[Int(w.get(x, y + dy, z))] && !Blocks.isLiquid(w.get(x, y + dy, z)) { w.set(x, y + dy, z, AIR) }
        } }
    }

    // The nearest road point to p within `range` (and the road and its t).
    static func nearest(_ gen: WorldGen, to p: V3, range: Float) -> (Seg, Float, V2)? {
        let x = Int(floor(p.x)), z = Int(floor(p.z)), r = Int(range)
        var best: (Seg, Float, V2)?
        var bd = range
        for s in near(gen, x0: x - r, z0: z - r, x1: x + r, z1: z + r, pad: range) {
            let (d, t) = distance(s, V2(p.x, p.z))
            if d < bd { bd = d; best = (s, t, point(s, t)) }
        }
        return best
    }
}
