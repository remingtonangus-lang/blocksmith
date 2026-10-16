import Foundation
import simd

// `--structscan [seeds]`: structure counts over many seeds in a 4096 x 4096 block square centred on each seed's spawn
// search origin (Game.spawnOrigin). Proves Capital citadels ("military_base") keep generating on every seed and
// measures how rare the rare buildings are. Fails (exit 1) if any seed has no citadel in its square.
enum StructScan {
    static let kinds = ["military_base", "village", "mansion", "great_ruin", "temple", "pillager_outpost", "trial_chambers",
                        "trail_ruins", "monument", "ancient_city"]

    // `--structnear SEED X Z`: the nearest Capital citadels (and Capital cities) to a point in one seed's world, with
    // distances, so a saved world's bases can be checked without loading it.
    static func near(seed: UInt64, x: Int, z: Int) -> Int {
        let gen = WorldGen(seed: seed)
        guard let sc = gen.structures else { return 1 }
        for k in ["military_base", "capital_city"] {
            guard let t = sc.types.first(where: { $0.name == k }) else { continue }
            let rx = floorDiv(floorDiv(x, CS), t.spacing), rz = floorDiv(floorDiv(z, CS), t.spacing)
            var found: [(Int, IVec3)] = []
            for dz in -3...3 { for dx in -3...3 {
                guard let s = sc.start(t, regionX: rx + dx, regionZ: rz + dz) else { continue }
                let d = Int(sqrt(Double((s.anchor.x - x) * (s.anchor.x - x) + (s.anchor.z - z) * (s.anchor.z - z))))
                found.append((d, s.anchor))
            } }
            found.sort { $0.0 < $1.0 }
            print("structnear: \(k): " + found.prefix(5).map { "\($0.1.x),\($0.1.z) (\($0.0) blocks)" }.joined(separator: ", "))
        }
        return 0
    }

    static func run(seeds n: Int) -> Int {
        var totals: [String: Int] = [:], minBase = Int.max, spawnBiomes: [String: Int] = [:]
        let halfChunks = 128
        for i in 0..<n {
            let seed = UInt64(1000 + i * 7919)
            let gen = WorldGen(seed: seed)
            guard let sc = gen.structures else { print("structscan: no structures"); return 1 }
            let o = Game.spawnOrigin(seed: seed)
            let ccx = o.0, ccz = o.1                     // spawn origin cell = chunk
            spawnBiomes["\(gen.column(ccx * 16 + 8, ccz * 16 + 8).biome)", default: 0] += 1
            var line: [String] = []
            for k in kinds {
                guard let t = sc.types.first(where: { $0.name == k }) else { continue }
                var c = 0
                let rx0 = floorDiv(ccx - halfChunks, t.spacing), rx1 = floorDiv(ccx + halfChunks, t.spacing)
                let rz0 = floorDiv(ccz - halfChunks, t.spacing), rz1 = floorDiv(ccz + halfChunks, t.spacing)
                for rz in rz0...rz1 { for rx in rx0...rx1 {
                    guard let s = sc.start(t, regionX: rx, regionZ: rz) else { continue }
                    let ax = floorDiv(s.anchor.x, 16), az = floorDiv(s.anchor.z, 16)
                    if abs(ax - ccx) <= halfChunks && abs(az - ccz) <= halfChunks { c += 1 }
                } }
                totals[k, default: 0] += c
                if k == "military_base" { minBase = min(minBase, c) }
                line.append("\(k) \(c)")
            }
            print("structscan: seed \(seed) origin \(ccx * 16),\(ccz * 16): " + line.joined(separator: ", "))
        }
        print("structscan: per 4096x4096 square, mean over \(n) seeds: " + kinds.map { String(format: "%@ %.1f", $0, Double(totals[$0] ?? 0) / Double(n)) }.joined(separator: ", "))
        print("structscan: spawn biomes: " + spawnBiomes.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        let ok = minBase >= 1
        print("structscan: \(ok ? "ok  " : "FAIL") every seed has a Capital citadel in its square (min \(minBase))")
        return ok ? 0 : 1
    }
}
