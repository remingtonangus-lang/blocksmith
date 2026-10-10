import Foundation
import Metal
import simd

// `--worldaudit [seeds] [--out snaps/world_audit.md] [--secs S]`: docs/STORE_QUALITY.md objective 7 over many seeds.
// Per seed: (1) structure starts of every type in a 2048 x 2048 square around the spawn origin, overlapping
// pieces (3D boxes) between different starts; (2) findability: distance from spawn to the nearest village, Capital
// citadel and Capital city; (3) a safe spawn: feet and head free, solid dry ground, no lava or water within 2 blocks;
// (4) spawn density: S seconds of Game.tick in survival at noon then at midnight, mobs counted by kind, biome and
// depth (surface or cave). Prints one line per seed and writes a summary table. Local tool (about 10 s per seed).
enum WorldAudit {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let device = MTLCreateSystemDefaultDevice() else { print("no Metal device"); return 1 }
        let n = Int(arg("--worldaudit") ?? "") ?? 50
        let out = arg("--out") ?? "snaps/world_audit.md"
        let secs = Double(arg("--secs") ?? "") ?? 30
        var overlapPairs: [String: Int] = [:], counts: [String: Int] = [:]
        var unsafe: [String] = [], far: [String: [Int]] = [:]
        var density: [String: [Int]] = [:]                 // "noon passive surface" -> per-seed counts
        var byBiome: [String: Int] = [:], byKind: [String: Int] = [:]
        var lines: [String] = []
        for i in 0..<n {
            let seed = UInt64(1000 + i * 7919)
            let world = World(seed: seed, device: device, save: nil)
            world.renderDistance = 4
            let game = Game(world: world, save: nil, persistent: false)
            guard let sc = world.gen.structures else { print("worldaudit: no structures"); return 1 }
            let o = Game.spawnOrigin(seed: seed)
            let ox = o.0 * 16 + 8, oz = o.1 * 16 + 8
            // 1. Starts and overlaps (footprints in x/z, inclusive).
            var starts: [StructureStart] = []
            for t in sc.types {
                let r = 64 / max(1, t.spacing) + 1
                let rx = floorDiv(o.0, t.spacing), rz = floorDiv(o.1, t.spacing)
                for dz in -r...r { for dx in -r...r {
                    guard let s = sc.start(t, regionX: rx + dx, regionZ: rz + dz),
                          abs(s.anchor.x - ox) <= 1024, abs(s.anchor.z - oz) <= 1024 else { continue }
                    starts.append(s); counts[s.kind, default: 0] += 1
                } }
            }
            var ov = 0
            for a in 0..<starts.count { for b in (a + 1)..<starts.count {
                let s = starts[a], t = starts[b]
                func hit(_ a: IVec3, _ b: IVec3, _ c: IVec3, _ d: IVec3) -> Bool { a.x <= d.x && c.x <= b.x && a.y <= d.y && c.y <= b.y && a.z <= d.z && c.z <= b.z }
                guard hit(s.min, s.max, t.min, t.max) else { continue }
                // Piece against piece (a city's bounding box is mostly empty ground between its buildings).
                if s.pieces.contains(where: { p in t.pieces.contains { q in hit(p.min, p.max, q.min, q.max) } }) {
                    ov += 1; overlapPairs[[s.kind, t.kind].sorted().joined(separator: " + "), default: 0] += 1
                }
            } }
            // 2. Findability from spawn.
            let spawn = game.spawnPoint             // the game's own path: findSpawn, then settleSpawn
            var dists: [String] = []
            for k in ["village", "military_base", "capital_city"] {
                let s = sc.nearest(k, x: Int(spawn.x), z: Int(spawn.z), maxRegions: 16)
                let d = s.map { Int(simd_length(SIMD2<Float>(Float($0.anchor.x) - spawn.x, Float($0.anchor.z) - spawn.z))) } ?? 99999
                far[k, default: []].append(d); dists.append("\(k) \(d)")
            }
            // 3. Safe spawn.
            _ = world.loadSync(center: spawn, radius: 4)
            let sx = Int(floor(spawn.x)), sy = Int(floor(spawn.y)), sz = Int(floor(spawn.z))
            var why: [String] = []
            if Blocks.collide[Int(world.block(sx, sy, sz))] { why.append("feet in a block") }
            if Blocks.collide[Int(world.block(sx, sy + 1, sz))] { why.append("head in a block") }
            if !Blocks.fullCollide[Int(world.block(sx, sy - 1, sz))] { why.append("no ground (\(Blocks.key(world.block(sx, sy - 1, sz))))") }
            hazard: for dy in -1...1 { for dz in -2...2 { for dx in -2...2 {
                let k = Blocks.key(world.block(sx + dx, sy + dy, sz + dz))
                if k.hasPrefix("lava") || (dy >= 0 && abs(dx) <= 1 && abs(dz) <= 1 && k.hasPrefix("water")) { why.append("\(k) at spawn"); break hazard }
            } } }
            if !why.isEmpty { unsafe.append("seed \(seed): " + why.joined(separator: ", ")) }
            // 4. Spawn density: survival, the player hovering 12 blocks up (out of reach), noon then midnight.
            game.survival = true
            game.paused = false
            game.player.flying = true
            let hover = V3(spawn.x, spawn.y + 12, spawn.z)
            var dline: [String] = []
            for (label, frac) in [("noon", 0.25), ("midnight", 0.75)] {
                game.time = frac * DAY_LENGTH
                for m in game.mobs.mobs where m.kind.hostile { m.health = 0 }
                var t = 0.0
                while t < secs {
                    game.player.pos = hover; game.player.vel = .zero; game.health = 20
                    game.tick(1.0 / 20); t += 1.0 / 20
                }
                var pas = [0, 0], hos = [0, 0]                 // [surface, cave]
                for m in game.mobs.mobs where m.health > 0 {
                    let mx = Int(floor(m.pos.x)), mz = Int(floor(m.pos.z))
                    let col = world.gen.column(mx, mz)
                    let cave = Int(m.pos.y) < col.height - 6 ? 1 : 0
                    if m.kind.hostile { hos[cave] += 1 } else { pas[cave] += 1 }
                    byKind["\(label) \(m.kind)", default: 0] += 1
                    byBiome["\(label) \(col.biome) \(m.kind.hostile ? "hostile" : "passive")\(cave == 1 ? " cave" : "")", default: 0] += 1
                }
                for (k, v) in [("passive surface", pas[0]), ("passive cave", pas[1]), ("hostile surface", hos[0]), ("hostile cave", hos[1])] {
                    density["\(label) \(k)", default: []].append(v)
                }
                dline.append("\(label) passive \(pas[0])+\(pas[1]) hostile \(hos[0])+\(hos[1])")
            }
            let line = "seed \(seed): \(starts.count) starts, \(ov) overlaps | \(dists.joined(separator: ", ")) | spawn \(why.isEmpty ? "safe" : why.joined(separator: ", ")) | \(dline.joined(separator: " | "))"
            print("worldaudit: " + line); lines.append(line)
        }
        func stats(_ xs: [Int]) -> String {
            let s = xs.sorted(); guard !s.isEmpty else { return "-" }
            return "min \(s[0]) median \(s[s.count / 2]) max \(s[s.count - 1])"
        }
        var md = "# World-gen audit (Blocksmith --worldaudit \(n))\n\nSeeds 1000 + i*7919, i < \(n); 2048-block square around each spawn origin; \(Int(secs)) s of survival ticks per time of day.\n\n"
        md += "## Summary\n\n"
        md += "- Unsafe spawns: \(unsafe.count)/\(n)\(unsafe.isEmpty ? "" : "\n  - " + unsafe.joined(separator: "\n  - "))\n"
        md += "- Structure overlaps (different starts whose footprints intersect): \(overlapPairs.values.reduce(0, +)) total\n"
        for (k, v) in overlapPairs.sorted(by: { $0.value > $1.value }) { md += "  - \(k): \(v)\n" }
        md += "- Distance from spawn to the nearest (blocks):\n"
        for (k, v) in far.sorted(by: { $0.key < $1.key }) { md += "  - \(k): \(stats(v)); over 2000: \(v.filter { $0 > 2000 }.count)\n" }
        // Oct 10 rules (WorldRules.swift, WildCamps.swift).
        let nearCities = (far["capital_city"] ?? []).filter { $0 < Int(WorldRules.capitalMinSpawn) }.count
        let nearCitadels = (far["military_base"] ?? []).filter { $0 < Int(WorldRules.citadelMinSpawn) }.count
        md += "- Capital city within \(Int(WorldRules.capitalMinSpawn)) blocks of the spawn: \(nearCities)/\(n) seeds; Capital citadel within \(Int(WorldRules.citadelMinSpawn)): \(nearCitadels)/\(n)\n"
        md += "- Ruined gates (retired): \(counts["ruined_portal", default: 0]) starts\n"
        let campCounts = counts.filter { $0.key.hasPrefix("camp_") }
        md += "- Wild camps per 2048^2 square (mean): " + String(format: "%.1f", Double(campCounts.values.reduce(0, +)) / Double(n)) + " ("
            + campCounts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + ")\n"
        md += "- Structure starts per 2048^2 square (mean): " + counts.sorted { $0.key < $1.key }.map { String(format: "%@ %.1f", $0.key, Double($0.value) / Double(n)) }.joined(separator: ", ") + "\n"
        md += "\n## Spawn density (mobs alive after \(Int(secs)) s, per seed)\n\n| time + group | per-seed counts |\n|---|---|\n"
        for (k, v) in density.sorted(by: { $0.key < $1.key }) { md += "| \(k) | \(stats(v)); zero on \(v.filter { $0 == 0 }.count) seeds |\n" }
        md += "\n### By biome (all seeds)\n\n| time biome group | mobs |\n|---|---|\n"
        for (k, v) in byBiome.sorted(by: { $0.value > $1.value }).prefix(40) { md += "| \(k) | \(v) |\n" }
        md += "\n### By kind (all seeds)\n\n" + byKind.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + "\n"
        md += "\n## Per seed\n\n" + lines.map { "- " + $0 }.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? md.write(toFile: out, atomically: true, encoding: .utf8)
        print("worldaudit: \(unsafe.count) unsafe spawns, \(overlapPairs.values.reduce(0, +)) overlaps -> \(out)")
        return 0
    }
}
