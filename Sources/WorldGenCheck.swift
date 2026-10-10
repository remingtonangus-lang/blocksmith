import Foundation
import simd

// `--worldgencheck [seeds]`: regression check for the Oct 10 world-gen rules (docs/status/worldgen-oct10.md), over
// seeds 1000 + i*7919 (default 24) plus Remington's Quest seed. Generator only (no chunks, no Game): about 1 s a seed.
// Per seed, around the world spawn (WorldRules.spawnCentre, the game's own terrain-only spawn search):
//   capital   nearest Capital city at least WorldRules.capitalMinSpawn out, and one within 4,000 (still findable);
//             cities per 4096^2 square
//   citadel   no Capital citadel within WorldRules.citadelMinSpawn, one within 1,500 (findable: the worst seed
//             before these rules was 1,458 out)
//   portals   no ruined gate starts at all
//   camps     wild camps per 2048^2 square by kind; each on dry land at least 2 above sea, outlaws away from spawn,
//             clear of the other surface structures; every loot entry an existing item
//   volcanoes every volcano in the 8192^2 square on warm-enough land with dry ground right round its foothills
// Prints one line per seed and a summary; exit 1 on any failure.
enum WorldGenCheck {
    // `--volcanosites SEED X Z`: every volcano cell within 3 cells of a point, with its verdict, its macro temperature
    // and the biomes round its foot (for checking a reported cone).
    static func volcanoSites() -> Int32 {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--volcanosites"), a.count > i + 3, let seed = UInt64(a[i + 1]), let x = Int(a[i + 2]), let z = Int(a[i + 3]) else {
            print("usage: --volcanosites SEED X Z"); return 1
        }
        let gen = WorldGen(seed: seed), c = Terrain.volcanoCell
        for cz in (floorDiv(z, c) - 3)...(floorDiv(z, c) + 3) { for cx in (floorDiv(x, c) - 3)...(floorDiv(x, c) + 3) {
            let s = gen.terrain.volcanoSite(cell: cx, cz)
            if s.why == "no roll" { continue }
            let mx = cx * c + c / 2, mz = cz * c + c / 2
            let ts = gen.terrain.macroLerp(mx, mz).ts
            var line = "cell \(cx),\(cz) ts \(String(format: "%.2f", ts)): " + (s.why.isEmpty ? "volcano at \(Int(s.v.x)),\(Int(s.v.z)) r \(Int(s.v.r))" : s.why)
            if s.v.exists {
                var feet: [String: Int] = [:]
                for k in 0..<12 {
                    let ang = Float(k) * Float.pi / 6
                    feet["\(gen.column(Int(s.v.x + cosf(ang) * s.v.r * 1.15), Int(s.v.z + sinf(ang) * s.v.r * 1.15)).biome)", default: 0] += 1
                }
                line += "; foot " + feet.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            }
            print("volcanosites: " + line)
        } }
        return 0
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        let n = Int(arg("--worldgencheck") ?? "") ?? 24
        var seeds = (0..<n).map { UInt64(1000 + $0 * 7919) }
        seeds.append(2943808052895834412)                          // Remington's Quest world (playtest Oct 10)
        var fails: [String] = []
        var capD: [Int] = [], capCount = 0, citD: [Int] = [], portals = 0, vols = 0, volsBefore = 0
        var volWhy: [String: Int] = [:], cells = 0
        var camps: [String: Int] = [:]
        func fail(_ s: String) { fails.append(s); print("worldgencheck: FAIL " + s) }
        for (k, table) in WildCamps.loot { for e in table.entries where e.0 != "empty" && !Items.has(e.0) { fail("loot \(k): no item \(e.0)") } }
        for seed in seeds {
            let gen = WorldGen(seed: seed)
            guard let sc = gen.structures else { print("worldgencheck: no structures"); return 1 }
            let c = WorldRules.spawnCentre(gen)
            let cx = Int(c.x), cz = Int(c.y)
            func dist(_ s: StructureStart) -> Int { Int(simd_length(V2(Float(s.anchor.x), Float(s.anchor.z)) - c)) }
            // Starts of a type whose anchor lies in the square of half-size `half` round the centre.
            func starts(_ name: String, half: Int) -> [StructureStart] {
                guard let t = sc.types.first(where: { $0.name == name }) else { return [] }
                let sp = t.spacing * CS
                var out: [StructureStart] = []
                for rz in floorDiv(cz - half, sp)...floorDiv(cz + half, sp) { for rx in floorDiv(cx - half, sp)...floorDiv(cx + half, sp) {
                    guard let s = sc.start(t, regionX: rx, regionZ: rz), abs(s.anchor.x - cx) <= half, abs(s.anchor.z - cz) <= half else { continue }
                    out.append(s)
                } }
                return out
            }
            // Capital cities.
            let cities = starts("capital_city", half: 2048)
            capCount += cities.count
            let nearCity = cities.map(dist).min() ?? (sc.nearest("capital_city", x: cx, z: cz, maxRegions: 5).map(dist) ?? 99999)
            capD.append(nearCity)
            if nearCity < Int(WorldRules.capitalMinSpawn) { fail("seed \(seed): Capital city \(nearCity) blocks from spawn") }
            if nearCity > 4000 { fail("seed \(seed): no Capital city within 4,000 blocks (\(nearCity))") }
            // Citadels.
            let cit = sc.nearest("military_base", x: cx, z: cz, maxRegions: 4).map(dist) ?? 99999
            citD.append(cit)
            if cit < Int(WorldRules.citadelMinSpawn) { fail("seed \(seed): Capital citadel \(cit) blocks from spawn") }
            if cit > 1500 { fail("seed \(seed): nearest Capital citadel \(cit) blocks out (findability)") }
            // Ruined gates.
            if sc.types.contains(where: { $0.name == "ruined_portal" }) { fail("ruined gates still generate") }
            for t in sc.types { for s in starts(t.name, half: 1024) where s.kind == "ruined_portal" { portals += 1; _ = s } }
            // Camps.
            var line: [String: Int] = [:]
            for s in starts("wild_camp", half: 1024) {
                camps[s.kind, default: 0] += 1; line[s.kind, default: 0] += 1
                let col = gen.column(s.anchor.x, s.anchor.z)
                if col.height <= SEA + 1 || col.biome.isOcean || col.biome == .river { fail("seed \(seed): \(s.kind) at \(s.anchor.x),\(s.anchor.z) on \(col.biome) h \(col.height - YOFF)") }
                if gen.terrain.column(s.anchor.x, s.anchor.z).vol > 0.02 { fail("seed \(seed): \(s.kind) on a volcano at \(s.anchor.x),\(s.anchor.z)") }
                if s.kind == "camp_outlaws" && dist(s) < Int(WildCamps.outlawMinSpawn) { fail("seed \(seed): outlaw camp \(dist(s)) from spawn") }
                for k in ["village", "military_base", "capital_city", "pillager_outpost", "temple", "mansion"] {
                    guard let o = sc.nearest(k, x: s.anchor.x, z: s.anchor.z, maxRegions: 1) else { continue }
                    let hit = o.pieces.contains { p in p.max.x >= s.min.x && p.min.x <= s.max.x && p.max.z >= s.min.z && p.min.z <= s.max.z }
                    if hit { fail("seed \(seed): \(s.kind) at \(s.anchor.x),\(s.anchor.z) overlaps a \(k)") }
                }
            }
            // Volcanoes.
            var vline: [String] = []
            let cell = Terrain.volcanoCell
            for vz in floorDiv(cz - 4096, cell)...floorDiv(cz + 4096, cell) { for vx in floorDiv(cx - 4096, cell)...floorDiv(cx + 4096, cell) {
                cells += 1
                let site = gen.terrain.volcanoSite(cell: vx, vz)
                if site.why != "no roll" && site.why != "sea, coast or range" { volsBefore += 1 }   // passed the old rules
                if !site.why.isEmpty { volWhy[site.why, default: 0] += 1 }
                let v = gen.terrain.volcano(cell: vx, vz)
                guard v.exists else { continue }
                vols += 1; vline.append("\(Int(v.x)),\(Int(v.z))")
                for k in 0..<12 {
                    let a = Float(k) * Float.pi / 6
                    let px = Int(v.x + cosf(a) * v.r * 1.2), pz = Int(v.z + sinf(a) * v.r * 1.2)
                    let col = gen.column(px, pz)
                    if col.height <= SEA || col.biome.isOcean { fail("seed \(seed): volcano at \(Int(v.x)),\(Int(v.z)) has \(col.biome) at its foot (\(px),\(pz))"); break }
                    if [.snowyTaiga, .snowyPlains, .snowySlopes, .frozenPeaks, .iceSpikes, .grove, .snowyBeach, .frozenRiver].contains(col.biome) {
                        fail("seed \(seed): volcano at \(Int(v.x)),\(Int(v.z)) stands in \(col.biome) (\(px),\(pz))"); break
                    }
                }
            } }
            let campLine = line.sorted { $0.key < $1.key }.map { "\($0.key.dropFirst(5)) \($0.value)" }.joined(separator: ", ")
            print("worldgencheck: seed \(seed): spawn \(cx),\(cz), capital \(nearCity) (\(cities.count) in 4096^2), citadel \(cit), camps [\(campLine)], volcanoes in 8192^2 [\(vline.joined(separator: " "))]")
        }
        let s = seeds.count
        func stats(_ xs: [Int]) -> String { let v = xs.sorted(); return "min \(v[0]) median \(v[v.count / 2]) max \(v[v.count - 1])" }
        let total = camps.values.reduce(0, +)
        func f2(_ a: Int) -> String { String(format: "%.2f", Double(a) / Double(s)) }
        let campList: String = camps.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        let whyList: String = volWhy.filter { $0.key != "no roll" }.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print("worldgencheck: \(s) seeds | nearest Capital city \(stats(capD)); \(f2(capCount)) per 4096^2 | nearest citadel \(stats(citD))")
        print("worldgencheck: ruined gates \(portals) | camps \(f2(total)) per 2048^2 (\(campList))")
        let pct: String = String(format: "%.1f %% of cells; old rules %d, %.1f %%", 100 * Double(vols) / Double(max(1, cells)), volsBefore, 100 * Double(volsBefore) / Double(max(1, cells)))
        print("worldgencheck: volcanoes \(vols) in \(cells) cells of 1280^2 (\(pct)); turned down: \(whyList)")
        let perSeed = Double(total) / Double(s)
        if perSeed < 2 || perSeed > 14 { fail("camps per 2048^2 square \(perSeed) outside 2...14") }
        for k in WildCamps.kinds where camps[k, default: 0] == 0 { fail("no \(k) on any seed") }
        print(fails.isEmpty ? "worldgencheck: all checks passed" : "worldgencheck: \(fails.count) FAILED")
        return fails.isEmpty ? 0 : 1
    }
}
