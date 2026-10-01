import Foundation
import ImageIO
import UniformTypeIdentifiers

// Headless terrain tools for CI:
//   Blocksmith --terrainmap DIR [--seed N] [--size BLOCKS] [--step BLOCKS] [--x X --z Z] [--strict]
//       top-down maps (biomes with hillshade, rivers and lakes; relief) and the implausible-neighbour check;
//   Blocksmith --genbench [--seed N]
//       chunk generation timing (same chunks and steps as the performance bench's gen scene) + water checks.
enum TerrainTools {
    static let palette: [Biome: UInt32] = [
        .ocean: 0x2846C8, .deepOcean: 0x14288C, .warmOcean: 0x3CBEDC, .lukewarmOcean: 0x328CDC, .deepLukewarmOcean: 0x1E64AA,
        .coldOcean: 0x283CAA, .deepColdOcean: 0x192378, .frozenOcean: 0x8282D2, .deepFrozenOcean: 0x5A5AAA, .beach: 0xF0E196,
        .snowyBeach: 0xF0F0DC, .stonyShore: 0x828282, .river: 0x3C6EFF, .frozenRiver: 0xAABEFF, .plains: 0x8CBE5A,
        .sunflowerPlains: 0xB4C850, .snowyPlains: 0xF5F5FA, .iceSpikes: 0xBEDCFA, .desert: 0xEBCD78, .swamp: 0x46643C,
        .mangroveSwamp: 0x3C7846, .forest: 0x328228, .flowerForest: 0x78A03C, .birchForest: 0x5AA050, .oldGrowthBirchForest: 0x64AA64,
        .darkForest: 0x1E5019, .taiga: 0x326450, .oldGrowthPineTaiga: 0x465A3C, .oldGrowthSpruceTaiga: 0x3C5546, .snowyTaiga: 0xC8DCDC,
        .savanna: 0xBEB45A, .savannaPlateau: 0xAAA050, .windsweptHills: 0x6E826E, .windsweptGravellyHills: 0x8C8C8C,
        .windsweptForest: 0x506E50, .windsweptSavanna: 0xAA9664, .jungle: 0x149614, .sparseJungle: 0x46AA28, .bambooJungle: 0x6EB41E,
        .badlands: 0xC86428, .erodedBadlands: 0xDC501E, .woodedBadlands: 0xAA6E3C, .meadow: 0x96D278, .cherryGrove: 0xF0AAC8,
        .grove: 0xB4D2C8, .snowySlopes: 0xE1E6F0, .frozenPeaks: 0xC8D2FF, .jaggedPeaks: 0xEBEBF5, .stonyPeaks: 0x968C82,
        .mushroomFields: 0xAA5AAA, .paleGarden: 0xAAAFA0,
    ]

    static func writePNG(_ path: String, _ w: Int, _ h: Int, _ rgba: [UInt8]) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: cs, bitmapInfo: info,
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { print("PNG encode failed: \(path)"); return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }

    // Top-down maps of one seed around (x, z). Returns the number of implausible neighbour pairs.
    static func map(dir: String, seed: UInt64, cx: Int, cz: Int, size: Int, step: Int) -> Int {
        let gen = WorldGen(seed: seed)
        let t = gen.terrain
        let n = size / step
        let s4 = max(1, step / 4)
        let gx0 = floorDiv(cx - size / 2, 4), gz0 = floorDiv(cz - size / 2, 4)
        var hs = [Float](repeating: 0, count: n * n)
        var water = [Bool](repeating: false, count: n * n)
        var bio = [Biome](repeating: .plains, count: n * n)
        var temp = [Float](repeating: 0, count: n * n), rain = [Float](repeating: 0, count: n * n)
        let t0 = CFAbsoluteTimeGetCurrent()
        hs.withUnsafeMutableBufferPointer { hp in
            water.withUnsafeMutableBufferPointer { wp in
                bio.withUnsafeMutableBufferPointer { bp in
                  temp.withUnsafeMutableBufferPointer { tp in
                    rain.withUnsafeMutableBufferPointer { rp in
                    let H = hp.baseAddress!, W = wp.baseAddress!, B = bp.baseAddress!, T = tp.baseAddress!, R = rp.baseAddress!
                    DispatchQueue.concurrentPerform(iterations: n) { row in
                        for col in 0..<n {
                            let nd = t.node(gx0 + col * s4, gz0 + row * s4)
                            let k = Terrain.blend(nd, nd, nd, nd, 0, 0)
                            let i = row * n + col
                            H[i] = nd.h
                            W[i] = nd.wl > nd.h + 0.5
                            B[i] = t.biome(k, k.h)
                            T[i] = t.temperature(k, max(k.h, SEA_D))
                            R[i] = k.w
                        }
                    }
                    }
                  }
                }
            }
        }
        let dt = CFAbsoluteTimeGetCurrent() - t0
        // Biome map with hillshade, relief map.
        var img = [UInt8](repeating: 255, count: n * n * 4)
        var rel = [UInt8](repeating: 255, count: n * n * 4)
        let lx: Float = -0.6, ly: Float = -0.6, lz: Float = 0.55
        let ll = (lx * lx + ly * ly + lz * lz).squareRoot()
        for row in 0..<n {
            for col in 0..<n {
                let i = row * n + col
                let hx = (hs[row * n + min(n - 1, col + 1)] - hs[row * n + max(0, col - 1)]) / Float(2 * step)
                let hz = (hs[min(n - 1, row + 1) * n + col] - hs[max(0, row - 1) * n + col]) / Float(2 * step)
                let nl = (hx * hx + hz * hz + 1).squareRoot()
                let dot = (-hx * lx - hz * ly + lz) / (nl * ll)
                let shade = max(0.2, min(1.3, 0.25 + dot))
                let c = palette[bio[i]] ?? 0xFF00FF
                var r = Float((c >> 16) & 255) * shade, g = Float((c >> 8) & 255) * shade, b = Float(c & 255) * shade
                if water[i] { r = r * 0.5 + 15; g = g * 0.5 + 30; b = b * 0.5 + 80 }
                img[i * 4] = UInt8(max(0, min(255, r))); img[i * 4 + 1] = UInt8(max(0, min(255, g))); img[i * 4 + 2] = UInt8(max(0, min(255, b)))
                let e = max(0, min(1, (hs[i] - 40) / 230))
                var rr = (e * 200 + 40) * shade, rg = (e * 170 + 60) * shade, rb = (e * 120 + 40) * shade
                if water[i] { rr = 40; rg = 80; rb = 200 }
                rel[i * 4] = UInt8(max(0, min(255, rr))); rel[i * 4 + 1] = UInt8(max(0, min(255, rg))); rel[i * 4 + 2] = UInt8(max(0, min(255, rb)))
            }
        }
        // Spawn-area marker.
        let mc = n / 2
        for d in -3...3 where mc + d >= 0 && mc + d < n {
            for (a, b) in [(mc + d, mc), (mc, mc + d)] { let i = a * n + b; img[i * 4] = 255; img[i * 4 + 1] = 0; img[i * 4 + 2] = 0 }
        }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        writePNG("\(dir)/terrain_\(seed).png", n, n, img)
        writePNG("\(dir)/relief_\(seed).png", n, n, rel)
        // Climate: red = warm, blue = cold (surface temperature with altitude), green = rainfall.
        var cli = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            let tt = max(0, min(1, (temp[i] + 1) / 2)), ww = max(0, min(1, (rain[i] + 1) / 2))
            cli[i * 4] = UInt8(tt * 255); cli[i * 4 + 1] = UInt8(40 + ww * 200); cli[i * 4 + 2] = UInt8((1 - tt) * 255)
            if water[i] { cli[i * 4] /= 3; cli[i * 4 + 1] /= 3; cli[i * 4 + 2] /= 3 }
        }
        writePNG("\(dir)/climate_\(seed).png", n, n, cli)
        // Implausible neighbours (right and down).
        var bad = 0
        var pairs: [String: Int] = [:]
        var example: [String: String] = [:]
        for row in 0..<n {
            for col in 0..<n {
                let a = bio[row * n + col]
                for (r2, c2) in [(row, col + 1), (row + 1, col)] where r2 < n && c2 < n {
                    let b = bio[r2 * n + c2]
                    if Terrain.implausible(a, b) {
                        bad += 1
                        let key = [a.name, b.name].sorted().joined(separator: "|")
                        pairs[key, default: 0] += 1
                        if example[key] == nil { example[key] = "\(gx0 * 4 + col * step),\(gz0 * 4 + row * step)" }
                    }
                }
            }
        }
        var counts: [Biome: Int] = [:]
        for b in bio { counts[b, default: 0] += 1 }
        let land = bio.filter { !$0.isOcean }.count
        let hist = counts.sorted { $0.value > $1.value }.map { String(format: "%@ %.1f%%", $0.key.name, Double($0.value) * 100 / Double(n * n)) }
        let skip: Set<Biome> = [.dripstoneCaves, .lushCaves, .deepDark, .netherWastes, .soulSandValley, .crimsonForest, .warpedForest, .basaltDeltas, .theEnd]
        let missing = Biome.allCases.filter { counts[$0] == nil && !skip.contains($0) }
        print(String(format: "terrainmap seed %llu: %ld x %ld blocks every %ld (%.1f s), land %.0f%%, max height %.0f", seed, size, size, step, dt,
                     Double(land) * 100 / Double(n * n), Double(hs.max() ?? 0)))
        print("  biomes: " + hist.joined(separator: ", "))
        if !missing.isEmpty { print("  not in this area: " + missing.map { $0.name }.joined(separator: " ")) }
        let worst = pairs.sorted { $0.value > $1.value }.prefix(10).map { "\($0.key) x\($0.value) (e.g. \(example[$0.key] ?? ""))" }
        let ri0 = floorDiv(gx0 * 4, Terrain.rs), rj0 = floorDiv(gz0 * 4, Terrain.rs)
        let ra = t.riverAudit(ri0, rj0, ri0 + size / Terrain.rs, rj0 + size / Terrain.rs)
        print("  rivers: \(ra.segments) segments, \(ra.uphill) flowing uphill, \(ra.lakes) lakes")
        bad += ra.uphill
        print("terraincheck seed \(seed): \(bad) problems (implausible neighbour pairs + uphill rivers)" + (worst.isEmpty ? "" : ": " + worst.joined(separator: ", ")))
        return bad
    }

    static func maps(_ dir: String) -> Int32 {
        let seeds: [UInt64] = arg("--seed").flatMap { UInt64($0) }.map { [$0] } ?? [12345, 777, 424242, 1, 98765]
        let size = Int(arg("--size") ?? "") ?? 8192
        let step = Int(arg("--step") ?? "") ?? 16
        let x = Int(arg("--x") ?? "") ?? 0, z = Int(arg("--z") ?? "") ?? 0
        var bad = 0
        for s in seeds { bad += map(dir: dir, seed: s, cx: x, cz: z, size: size, step: step) }
        print("terraincheck total: \(bad) problems over \(seeds.count) seeds")
        return CommandLine.arguments.contains("--strict") && bad > 0 ? 2 : 0
    }

    // Water plants (kelp, seagrass) must stay under water: count plant blocks with something other than water or
    // the same plant above them, over a square of chunks around --x/--z (the seed 777 aerial tour looks out to sea).
    static func kelpCheck() -> Int32 {
        let seed = UInt64(arg("--seed") ?? "") ?? 777
        let g = WorldGen(seed: seed)
        let x = Int(arg("--x") ?? "") ?? 600, z = Int(arg("--z") ?? "") ?? 300
        let r = Int(arg("--radius") ?? "") ?? 20
        let plants: Set<BlockID> = Set(["kelp", "seagrass", "tall_seagrass"].filter { Blocks.has($0) }.map { Blocks.id($0) })
        var plantBlocks = 0, exposed = 0, aboveSea = 0
        var samples: [String] = []
        let c0x = floorDiv(x, CS), c0z = floorDiv(z, CS)
        for cz in (c0z - r)...(c0z + r) { for cx in (c0x - r)...(c0x + r) {
            var b = g.generate(cx: cx, cz: cz)
            if let st = g.structures { _ = st.place(into: &b, cx: cx, cz: cz) }
            for lz in 0..<CS { for lx in 0..<CS {
                for y in 1..<(CH - 1) {
                    let id = b[Chunk.index(lx, y, lz)]
                    guard plants.contains(id) else { continue }
                    plantBlocks += 1
                    if y >= SEA { aboveSea += 1 }
                    let up = b[Chunk.index(lx, y + 1, lz)]
                    if up == WATER || Blocks.groupBase[Int(up)] == Blocks.groupBase[Int(id)] { continue }
                    exposed += 1
                    if samples.count < 12 {
                        var top = y + 1
                        while top < CH - 1 && b[Chunk.index(lx, top, lz)] != AIR { top += 1 }
                        var surf = CH - 2
                        while surf > 1 && b[Chunk.index(lx, surf, lz)] != WATER { surf -= 1 }
                        samples.append("\(Blocks.key(id)) at \(cx * CS + lx) \(y - YOFF) \(cz * CS + lz): above \(Blocks.key(up)), column top y \(top - 1 - YOFF), highest water y \(surf - YOFF), biome \(g.column(cx * CS + lx, cz * CS + lz).biome)")
                    }
                }
            } }
        } }
        for s in samples { print("kelpcheck   " + s) }
        print("kelpcheck seed \(seed) around \(x) \(z) (\((2 * r + 1) * (2 * r + 1)) chunks): \(plantBlocks) water-plant blocks, \(exposed) not under water, \(aboveSea) at or above sea level")
        return CommandLine.arguments.contains("--strict") && exposed > 0 ? 2 : 0
    }

    // Chunk generation timing on the same chunks as the performance bench (gen scene), plus water checks.
    static func genBench() -> Int32 {
        let seed = UInt64(arg("--seed") ?? "") ?? 12345
        let g = WorldGen(seed: seed)
        func now() -> Double { CFAbsoluteTimeGetCurrent() }
        var b0 = g.generate(cx: 0, cz: 0)
        if let st = g.structures { _ = st.place(into: &b0, cx: 0, cz: 0) }
        var times: [Double] = []
        var leaks = 0, waterBlocks = 0
        for i in 0..<24 {
            let cx = i * 7 - 80, cz = (i * 13) % 50 - 25
            let a = now()
            var b = g.generate(cx: cx, cz: cz)
            if let st = g.structures { _ = st.place(into: &b, cx: cx, cz: cz) }
            _ = g.tints(cx: cx, cz: cz)
            _ = Chunk.computeHeights(b)
            times.append((now() - a) * 1000)
            // Water next to air at the same height inside the chunk (would spill when touched).
            for y in (SEA - 40)..<(CH - 1) { for lz in 0..<CS { for lx in 0..<CS {
                let i = Chunk.index(lx, y, lz)
                guard b[i] == WATER else { continue }
                waterBlocks += 1
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = lx + dx, nz = lz + dz
                    if nx < 0 || nx >= CS || nz < 0 || nz >= CS { continue }
                    if b[Chunk.index(nx, y, nz)] == AIR { leaks += 1; break }
                }
            } } }
        }
        let sorted = times.sorted()
        let mean = times.reduce(0, +) / Double(times.count)
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        // Warm cache (same chunks again: terrain nodes and river graph already known).
        let a = now()
        for i in 0..<24 { _ = g.generate(cx: i * 7 - 80, cz: (i * 13) % 50 - 25) }
        let warm = (now() - a) * 1000 / 24
        // Breakdown on a fresh area: terrain fields (nodes + river graph) cold, then blocks with warm fields, then tints.
        var tNodes = 0.0, tBlocks = 0.0, tTints = 0.0
        for i in 0..<24 {
            let cx = 500 + i * 5, cz = 400 - i * 3
            var a = now()
            _ = g.chunkNodes(cx * CS, cz * CS)
            tNodes += now() - a
            a = now()
            _ = g.generate(cx: cx, cz: cz)
            tBlocks += now() - a
            a = now()
            _ = g.tints(cx: cx, cz: cz)
            tTints += now() - a
        }
        print(String(format: "genbench breakdown per chunk: terrain fields %.2f ms (cold), blocks %.2f ms, tints %.2f ms", tNodes * 1000 / 24, tBlocks * 1000 / 24, tTints * 1000 / 24))
        // Parallel throughput (fresh area).
        let n = 96
        let p0 = now()
        DispatchQueue.concurrentPerform(iterations: n) { i in
            let cx = 200 + i % 12, cz = -300 + i / 12
            var b = g.generate(cx: cx, cz: cz)
            if let st = g.structures { _ = st.place(into: &b, cx: cx, cz: cz) }
            _ = g.tints(cx: cx, cz: cz)
        }
        let rate = Double(n) / (now() - p0)
        print(String(format: "genbench seed %llu: %.2f ms/chunk mean (p95 %.2f, max %.2f) single-thread cold, %.2f ms warm, %.0f chunks/s parallel", seed, mean, p95, sorted.last ?? 0, warm, rate))
        print("genbench water: \(waterBlocks) water blocks above y \(SEA - 40 - YOFF), \(leaks) beside open air at the same level")
        return 0
    }
}
