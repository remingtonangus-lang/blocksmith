import Foundation

// Which blocks are natural (realistic world, docs/design/realistic-world.md 1.1): the ones the world generators lay
// down on their own, measured by running them. Every dimension's generator makes a fixed set of sample chunks (one per
// overworld biome, a ring in each other dimension) with a fixed seed; a block is natural if any sample holds it. "Bulk"
// is how often an occurrence sits in a mass (4+ of its 6 neighbours opaque): moss carpets and rock are bulk, a
// pumpkin on the grass is not. Structures are not part of the generators' chunks, so their blocks (bases, towns,
// ships) never count as natural. Cached on disk per block registry (a few hundred ms to compute on the Quest).
enum NaturalCensus {
    static let version = 1
    struct Result { var count: [Int32]; var bulk: [Int32] }

    static let result: Result = load() ?? { let r = compute(); save(r); return r }()
    // Per block state (its whole state group counts together: a pumpkin facing any way is one pumpkin).
    static let natural: [Bool] = {
        var g = [String: Int32]()
        for i in 0..<Blocks.count { g[ShapeClass.group(BlockID(i)), default: 0] += result.count[i] }
        return (0..<Blocks.count).map { g[ShapeClass.group(BlockID($0))]! > 0 }
    }()
    static let bulkShare: [Float] = {
        var c = [String: Int32](), b = [String: Int32]()
        for i in 0..<Blocks.count {
            let k = ShapeClass.group(BlockID(i))
            c[k, default: 0] += result.count[i]; b[k, default: 0] += result.bulk[i]
        }
        return (0..<Blocks.count).map { i in
            let k = ShapeClass.group(BlockID(i))
            return c[k]! > 0 ? Float(b[k]!) / Float(c[k]!) : 0
        }
    }()

    static func registryKey() -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for i in 0..<Blocks.count { for u in Blocks.key(BlockID(i)).utf8 { h = (h ^ UInt64(u)) &* 0x100000001b3 }; h = (h ^ 0x7C) &* 0x100000001b3 }
        return "v\(version)-\(Blocks.count)-\(String(h, radix: 16))"
    }
    static var cacheURL: URL { WorldStore.base.deletingLastPathComponent().appendingPathComponent("natural-census.txt") }

    static func load() -> Result? {
        guard let s = try? String(contentsOf: cacheURL, encoding: .utf8) else { return nil }
        let lines = s.split(separator: "\n")
        guard lines.count == 3, lines[0] == registryKey() else { return nil }
        let c = lines[1].split(separator: ",").compactMap { Int32($0) }, b = lines[2].split(separator: ",").compactMap { Int32($0) }
        guard c.count == Blocks.count && b.count == Blocks.count else { return nil }
        return Result(count: c, bulk: b)
    }
    static func save(_ r: Result) {
        let s = registryKey() + "\n" + r.count.map(String.init).joined(separator: ",") + "\n" + r.bulk.map(String.init).joined(separator: ",") + "\n"
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? s.write(to: cacheURL, atomically: true, encoding: .utf8)
    }

    // The sample chunks: one per overworld biome (spiralling out from 0,0 in 64-block steps), plus rings in the
    // Emberdeep, the Hollow (centre and outer islands) and the Deep.
    static func samples() -> [(TerrainGenerator, Int, Int)] {
        let seed: UInt64 = 0x5EED_B10C
        var out: [(TerrainGenerator, Int, Int)] = []
        let ow = WorldGen(seed: seed)
        var seen = Set<Int>()
        var x = 0, z = 0, dx = 0, dz = -1
        for _ in 0..<6000 {
            let wx = x * 64, wz = z * 64
            let b = ow.column(wx, wz).biome
            if seen.insert(b.rawValue).inserted { out.append((ow, floorDiv(wx, CS), floorDiv(wz, CS))) }
            if seen.count == Biome.allCases.count { break }
            if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
            x += dx; z += dz
        }
        let ember = EmberGen(seed: seed), hollow = HollowGen(seed: seed), deep = DeepGen(seed: seed)
        for k in 0..<6 {
            let a = Float(k) * .pi / 3
            out.append((ember, Int(cosf(a) * 12), Int(sinf(a) * 12)))
            out.append((deep, Int(cosf(a) * 20), Int(sinf(a) * 20)))
        }
        out.append((hollow, 0, 0)); out.append((hollow, 2, 1))
        for k in 0..<4 { let a = Float(k) * .pi / 2; out.append((hollow, Int(cosf(a) * 80), Int(sinf(a) * 80))) }
        return out
    }

    static func compute() -> Result {
        let t0 = CFAbsoluteTimeGetCurrent()
        let list = samples()
        let n = Blocks.count
        let lock = NSLock()
        var count = [Int32](repeating: 0, count: n), bulk = [Int32](repeating: 0, count: n)
        let opaqueT = Blocks.opaque
        DispatchQueue.concurrentPerform(iterations: list.count) { k in
            let (g, cx, cz) = list[k]
            let b = g.generate(cx: cx, cz: cz)
            var c = [Int32](repeating: 0, count: n), bk = [Int32](repeating: 0, count: n)
            b.withUnsafeBufferPointer { p in
                for y in 1..<(CH - 1) { for lz in 1..<(CS - 1) { for lx in 1..<(CS - 1) {
                    let i = Chunk.index(lx, y, lz)
                    let s = Int(p[i])
                    if s == Int(AIR) { continue }
                    c[s] += 1
                    var o = 0
                    for j in [i + 1, i - 1, i + CS, i - CS, i + CSQ, i - CSQ] where opaqueT[Int(p[j])] { o += 1 }
                    if o >= 4 { bk[s] += 1 }
                } } }
            }
            lock.lock()
            for i in 0..<n where c[i] != 0 { count[i] += c[i]; bulk[i] += bk[i] }
            lock.unlock()
        }
        print(String(format: "natural census: %d sample chunks in %.0f ms", list.count, (CFAbsoluteTimeGetCurrent() - t0) * 1000))
        return Result(count: count, bulk: bulk)
    }
}
