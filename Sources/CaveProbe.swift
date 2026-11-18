import Foundation

// Ledger 236 ("they won't be able to move around in the caves easily ... they'll be too narrow"): how tight the caves
// are. `--caveprobe SEED,X,Z,R`: the chunks within R chunks of (X, Z) of a world of SEED, and for each place to stand
// under ground (air over rock, 8 or more under the surface) its headroom and the passage's width there (the narrower
// of the two ways across, at feet and head). BS_OLDCAVES=1 gives the caves of before.
enum CaveProbe {
    static func run(_ a: String) -> Int32 {
        let v = a.split(separator: ",").map { String($0) }
        guard v.count >= 4 else { print("caveprobe: SEED,X,Z,R"); return 1 }
        let seed = UInt64(v[0]) ?? 1, x0 = Int(v[1]) ?? 0, z0 = Int(v[2]) ?? 0, r = Int(v[3]) ?? 3
        let gen = WorldGen(seed: seed)
        let c0x = floorDiv(x0, CS), c0z = floorDiv(z0, CS)
        var stand = 0, low = 0, air = 0, chunks = 0
        var widths = [Int](repeating: 0, count: 10)
        let t0 = CFAbsoluteTimeGetCurrent()
        for cz in (c0z - r)...(c0z + r) { for cx in (c0x - r)...(c0x + r) {
            let b = gen.generate(cx: cx, cz: cz)
            chunks += 1
            func open(_ x: Int, _ y: Int, _ z: Int) -> Bool { b[Chunk.index(x, y, z)] == AIR }
            for z in 4..<12 { for x in 4..<12 {
                var top = CH - 1
                while top > 0 && !Blocks.opaque[Int(b[Chunk.index(x, top, z)])] { top -= 1 }
                guard top > 24 else { continue }
                for y in 2..<(top - 8) where open(x, y, z) {
                    air += 1
                    guard Blocks.opaque[Int(b[Chunk.index(x, y - 1, z)])] else { continue }
                    stand += 1
                    guard open(x, y + 1, z) else { low += 1; continue }
                    func span(_ dx: Int, _ dz: Int) -> Int {
                        var n = 1
                        for s in [-1, 1] { for k in 1...4 {
                            let xx = x + dx * k * s, zz = z + dz * k * s
                            if open(xx, y, zz) && open(xx, y + 1, zz) { n += 1 } else { break }
                        } }
                        return n
                    }
                    widths[min(span(1, 0), span(0, 1))] += 1
                }
            } }
        } }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000 / Double(max(1, chunks))
        func pct(_ n: Int) -> String { String(format: "%.1f%%", 100 * Double(n) / Double(max(1, stand))) }
        let wide = widths[3...].reduce(0, +)
        print("caveprobe: \(chunks) chunks, \(air) cave air cells (\(air / max(1, chunks)) a chunk's middle), \(stand) places to stand")
        print("caveprobe: too low to stand \(pct(low)); one wide \(pct(widths[1])); two wide \(pct(widths[2])); three or wider \(pct(wide))")
        print(String(format: "caveprobe: %.1f ms a chunk", ms))
        return 0
    }
}
