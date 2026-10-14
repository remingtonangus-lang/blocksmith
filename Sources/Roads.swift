import Foundation
import simd

// P51 (Oct 11 evening playtest): roads between towns, riders on them you can rob, a town's posse after a robber, and
// bounty hunters with guns.
//   Roads    a dirt road from each town square to the squares of the towns in the next village regions east and
//            south (and the diagonals), when they are less than `maxLen` apart. Gently winding, three blocks wide, only
//            over natural ground (grass, dirt, sand, snow) with open air above, never through a building or water.
//            Only on ground first generated with them (WorldRules.savedBeforeP44 all along the road, the P44 guard),
//            so no road ends at the edge of explored land.
//   Riders   now and then a traveller on horseback rides a road near the player (Riders, below).
enum Roads {
    static let maxLen: Float = 720
    static let halfWidth: Float = 1.3

    struct Seg { let a: V2; let b: V2; let phase: Float }

    private static var cache: [Int64: Seg?] = [:]
    private static var cacheGen: ObjectIdentifier?  // the generator the cache was filled for (another world clears it)
    private static let lock = NSLock()
    static var on: Bool { WorldRules.p44 }

    // The village region's town square (nil: no town there).
    static func square(_ gen: WorldGen, _ rx: Int, _ rz: Int) -> V2? {
        guard let sc = gen.structures, let t = sc.types.first(where: { $0.name == "village" }),
              let s = sc.start(t, regionX: rx, regionZ: rz) else { return nil }
        return V2(Float(s.anchor.x), Float(s.anchor.z))
    }

    // The road from region (rx, rz) to its neighbour (rx + dx, rz + dz), if one runs.
    static func segment(_ gen: WorldGen, _ rx: Int, _ rz: Int, _ dx: Int, _ dz: Int) -> Seg? {
        let key = (Int64(rx & 0xFFFFF) << 44) | (Int64(rz & 0xFFFFF) << 24) | Int64((dx + 1) * 3 + dz + 1)
        let gid = ObjectIdentifier(gen)
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
            if fresh { seg = Seg(a: a, b: b, phase: hashf(rx, rz, dx * 7 + dz, UInt32(truncatingIfNeeded: gen.seed) ^ 0x80AD) * 6.28) }
        }
        lock.lock(); if cacheGen == gid { cache[key] = seg }; if cache.count > 4096 { cache.removeAll() }; lock.unlock()
        return seg
    }

    // Roads that may pass within `pad` blocks of the box (x0...x1, z0...z1).
    static func near(_ gen: WorldGen, x0: Int, z0: Int, x1: Int, z1: Int, pad: Float = 8) -> [Seg] {
        guard on else { return [] }
        let span = 34 * CS
        let rx0 = floorDiv(x0, span) - 2, rx1 = floorDiv(x1, span) + 1
        let rz0 = floorDiv(z0, span) - 2, rz1 = floorDiv(z1, span) + 1
        var out: [Seg] = []
        for rz in rz0...rz1 { for rx in rx0...rx1 {
            for (dx, dz) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
                guard let s = segment(gen, rx, rz, dx, dz) else { continue }
                let lo = simd_min(s.a, s.b) - V2(repeating: pad + 12), hi = simd_max(s.a, s.b) + V2(repeating: pad + 12)
                if Float(x1) < lo.x || Float(x0) > hi.x || Float(z1) < lo.y || Float(z0) > hi.y { continue }
                out.append(s)
            }
        } }
        return out
    }

    // The road's centre line at t (0...1): a straight line with a gentle bend that vanishes at both ends.
    static func point(_ s: Seg, _ t: Float) -> V2 {
        let d = s.b - s.a, len = max(1, simd_length(d))
        let n = V2(-d.y, d.x) / len
        let bend = sinf(t * len / 90 + s.phase) * 7 * min(1, t * (1 - t) * 8)
        return s.a + d * t + n * bend
    }
    // Distance from p to the road and the t of the nearest point.
    static func distance(_ s: Seg, _ p: V2) -> (Float, Float) {
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
        for lz in 0..<CS { for lx in 0..<CS {
            let x = bx + lx, z = bz + lz
            let p = V2(Float(x) + 0.5, Float(z) + 0.5)
            guard segs.contains(where: { distance($0, p).0 <= halfWidth }) else { continue }
            // The ground under plants, snow and air.
            var y = CH - 2
            while y > 1 {
                let b = w.get(x, y, z)
                if Blocks.collide[Int(b)] && !CapitalBase.isLeaf(b) { break }
                y -= 1
            }
            let top = w.get(x, y, z)
            guard y > SEA - 1, Int(top) < natural.count, natural[Int(top)] else { continue }
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
