import Foundation
import simd

// Ledger 230, 237: `--planmap SEED,X,Z,R,STEP OUT.ppm`: the land within R blocks of (X, Z) on a field world of SEED
// from straight above (one pixel a STEP blocks: height shaded, water blue), with its railways (black; stations red),
// roads (yellow) and town squares (white) drawn over it. For judging how tracks and roads lie on the land.
enum PlanMap {
    static func run(_ a: String, _ out: String) -> Int32 {
        let v = a.split(separator: ",").map { String($0) }
        guard v.count >= 5 else { print("planmap: SEED,X,Z,R,STEP OUT.ppm"); return 1 }
        let seed = UInt64(v[0]) ?? 1, px = Int(v[1]) ?? 0, pz = Int(v[2]) ?? 0, r = Int(v[3]) ?? 2000, step = max(1, Int(v[4]) ?? 4)
        let p440 = WorldRules.p44
        WorldRules.p44 = true
        defer { WorldRules.p44 = p440 }
        let gen = WorldGen(seed: seed)
        gen.fieldWorld = true
        gen.terrain.fewerLakes = World.fewerLakesUnsaved; gen.terrain.lessWater = World.lessWaterUnsaved
        let n = 2 * r / step
        var px3 = [UInt8](repeating: 0, count: n * n * 3)
        func put(_ x: Int, _ z: Int, _ c: (UInt8, UInt8, UInt8), fat: Int = 0) {
            let i0 = (x - (px - r)) / step, j0 = (z - (pz - r)) / step
            for j in (j0 - fat)...(j0 + fat) { for i in (i0 - fat)...(i0 + fat) where i >= 0 && j >= 0 && i < n && j < n {
                let k = (j * n + i) * 3
                px3[k] = c.0; px3[k + 1] = c.1; px3[k + 2] = c.2
            } }
        }
        for j in 0..<n { for i in 0..<n {
            let x = px - r + i * step, z = pz - r + j * step
            let c = gen.columnData(x, z)
            if c.wl > c.h + 0.3 { put(x, z, (60, 110, UInt8(max(120, min(220, 220 - (c.wl - c.h) * 6))))); continue }
            // (low green to high grey-white, with a slope shade from the column to the west)
            let h = max(0, min(1, (c.h - Float(SEA - YOFF)) / 200))
            let w = gen.columnData(x - step, z).h
            let shade = max(0.6, min(1.25, 1 + (c.h - w) / Float(step) * 0.35))
            let rr = (90 + 150 * h) * shade, gg = (150 + 80 * h) * shade, bb = (80 + 160 * h) * shade
            put(x, z, (UInt8(max(0, min(255, rr))), UInt8(max(0, min(255, gg))), UInt8(max(0, min(255, bb)))))
        } }
        let x0 = px - r, z0 = pz - r, x1 = px + r, z1 = pz + r
        var roads = 0, lines = 0, stations = 0
        for s in Roads.near(gen, x0: x0, z0: z0, x1: x1, z1: z1, pad: 0) {
            roads += 1
            let m = max(2, Int(Roads.length(s) / Float(step)))
            for i in 0...m { let q = Roads.point(s, Float(i) / Float(m)); put(Int(q.x), Int(q.y), (250, 220, 40)) }
        }
        for l in Railways.near(gen, x0: x0, z0: z0, x1: x1, z1: z1, pad: 0, wild: true) + Railways.linksNear(gen, x0: x0, z0: z0, x1: x1, z1: z1, pad: 0) {
            lines += 1
            for c in l.cells { put(c.x, c.z, (10, 10, 10), fat: step >= 4 ? 0 : 1) }
            for st in l.stations { stations += 1; put(st.x, st.z, (230, 30, 30), fat: 3) }
        }
        let span = 34 * CS
        var towns = 0
        for rz in floorDiv(z0, span)...floorDiv(z1, span) { for rx in floorDiv(x0, span)...floorDiv(x1, span) {
            if let q = Roads.square(gen, rx, rz) { towns += 1; put(Int(q.x), Int(q.y), (255, 255, 255), fat: 2) }
        } }
        var data = Data("P6\n\(n) \(n)\n255\n".utf8)
        data.append(contentsOf: px3)
        do { try data.write(to: URL(fileURLWithPath: out)) } catch { print("planmap: could not write \(out)"); return 1 }
        print("planmap: \(n) x \(n) at \(step) blocks a pixel: \(towns) towns, \(roads) roads, \(lines) lines and links, \(stations) stations -> \(out)")
        return 0
    }

    // Ledger 239: `--towncensus SEED,X,Z,R`: every town within R blocks of (X, Z) on a field world of SEED by size,
    // and how many of each have a station (one within 320 blocks of the town's square); the track there is; and the
    // columns two different lines or links both lie in (none is right).
    static func census(_ a: String) -> Int32 {
        let v = a.split(separator: ",").map { String($0) }
        guard v.count >= 4 else { print("towncensus: SEED,X,Z,R"); return 1 }
        let seed = UInt64(v[0]) ?? 1, px = Int(v[1]) ?? 0, pz = Int(v[2]) ?? 0, r = Int(v[3]) ?? 4000
        let p440 = WorldRules.p44
        WorldRules.p44 = true
        defer { WorldRules.p44 = p440 }
        let gen = WorldGen(seed: seed)
        gen.fieldWorld = true
        gen.terrain.fewerLakes = World.fewerLakesUnsaved; gen.terrain.lessWater = World.lessWaterUnsaved
        let t0 = CFAbsoluteTimeGetCurrent()
        let c = count(gen, px, pz, r)
        let by = (0..<5).map { "\(TownSizes.names[$0]) \(c.served[$0]) of \(c.total[$0])" }.joined(separator: ", ")
        print(String(format: "towncensus: %d of %d towns have a station (%@); towns and bigger %d of %d; %d lines and links, %d cells, %d columns shared by two; %.1f s",
                     c.served.reduce(0, +), c.total.reduce(0, +), by, c.served[2...].reduce(0, +), c.total[2...].reduce(0, +), c.lines, c.cells, c.shared,
                     CFAbsoluteTimeGetCurrent() - t0))
        if !c.missed.isEmpty { print("towncensus: no station: " + c.missed.prefix(12).joined(separator: "; ")) }
        return 0
    }
    static func count(_ gen: WorldGen, _ px: Int, _ pz: Int, _ r: Int) -> (total: [Int], served: [Int], lines: Int, cells: Int, shared: Int, missed: [String]) {
        var total = [Int](repeating: 0, count: 5), served = [Int](repeating: 0, count: 5)
        var missed: [String] = []
        guard let sc = gen.structures, let vt = sc.types.first(where: { $0.name == "village" }) else { return (total, served, 0, 0, 0, missed) }
        let x0 = px - r, z0 = pz - r, x1 = px + r, z1 = pz + r
        let lines = Railways.near(gen, x0: x0 - 400, z0: z0 - 400, x1: x1 + 400, z1: z1 + 400, pad: 0, wild: true)
            + Railways.linksNear(gen, x0: x0 - 400, z0: z0 - 400, x1: x1 + 400, z1: z1 + 400, pad: 0)
        var stations: [(Int, Int)] = [], cells = 0
        var owner: [Int64: Int64] = [:], shared = 0
        for l in lines {
            cells += l.cells.count
            for st in l.stations { stations.append((st.x, st.z)) }
            for c in l.cells.dropFirst(2).dropLast(2) {
                let k = Railways.colKey(c.x, c.z)
                if let o = owner[k], o != l.id { shared += 1 } else { owner[k] = l.id }
            }
        }
        let span = 34 * CS
        for rz in floorDiv(z0, span)...floorDiv(z1, span) { for rx in floorDiv(x0, span)...floorDiv(x1, span) {
            guard let t = sc.start(vt, regionX: rx, regionZ: rz), t.max.y >= SEA else { continue }
            guard t.anchor.x >= x0 && t.anchor.x <= x1 && t.anchor.z >= z0 && t.anchor.z <= z1 else { continue }
            let size = min(4, max(0, t.info["size"] ?? 1))
            total[size] += 1
            if stations.contains(where: { abs($0.0 - t.anchor.x) <= 320 && abs($0.1 - t.anchor.z) <= 320 }) { served[size] += 1 }
            else if size >= 2 { missed.append("\(TownSizes.names[size]) \(t.anchor.x) \(t.anchor.z) (row \(rz))") }
        } }
        return (total, served, lines.count, cells, shared, missed)
    }
}
