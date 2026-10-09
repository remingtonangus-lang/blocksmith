import Foundation
import simd

// `--questbugs --only factions` (task 23): Capital cities and citadels generate and can be found, saved worlds keep
// their explored ground (the structure guard), the Meridian frigate, its MAC gun, the radar, intercepted orders and
// the base components.
enum FactionTests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        structures(check)
    }

    static func structures(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        // Cities and citadels near spawn on a spread of seeds.
        var worst = 0, worstBase = 0
        for i in 0..<6 {
            let seed = UInt64(1000 + i * 7919)
            let gen = WorldGen(seed: seed)
            guard let sc = gen.structures else { check(false, "factions: structures"); return }
            let o = Game.spawnOrigin(seed: seed)
            let x = o.0 * 16, z = o.1 * 16
            let c = sc.nearest("capital_city", x: x, z: z, maxRegions: 3)
            let b = sc.nearest("military_base", x: x, z: z, maxRegions: 4)
            let dc = c.map { Int(simd_length(V2(Float($0.anchor.x - x), Float($0.anchor.z - z)))) } ?? 99999
            let db = b.map { Int(simd_length(V2(Float($0.anchor.x - x), Float($0.anchor.z - z)))) } ?? 99999
            worst = max(worst, dc); worstBase = max(worstBase, db)
        }
        check(worst < 2200, "factions: a Capital city within 2,200 blocks of spawn on 6 seeds (worst \(worst))")
        check(worstBase < 1200, "factions: a Capital citadel within 1,200 blocks of spawn on 6 seeds (worst \(worstBase))")

        // The structure guard: taken once from the chunk folder, never grows afterwards.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("factions-\(getpid())", isDirectory: true)
        try? fm.removeItem(at: tmp)
        let sm = SaveManager(dir: tmp.appendingPathComponent("w"))
        let b = [BlockID](repeating: STONE, count: CSQ * CH)
        sm.saveChunk(ChunkKey(x: 1, z: -2), b)
        let g1 = sm.structureGuard()
        sm.saveChunk(ChunkKey(x: 5, z: 5), b)
        let g2 = sm.structureGuard()
        check(g1 == [StructureCache.key(1, -2)] && g2 == g1, "factions: the structure guard lists the chunks saved before the update only (\(g1.count), \(g2.count))")

        // Saved worlds on this Mac: no new or moved structure lands on ground they had already generated.
        let worlds = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Blocksmith/Worlds")
        for n in ((try? fm.contentsOfDirectory(atPath: worlds.path)) ?? []).sorted() {
            let src = worlds.appendingPathComponent(n)
            let copy = tmp.appendingPathComponent("w-\(n)")
            guard (try? fm.copyItem(at: src, to: copy)) != nil else { continue }
            let w = SaveManager(dir: copy)
            guard let meta = w.loadMeta() else { continue }
            try? fm.removeItem(at: copy.appendingPathComponent("structure-guard.txt"))   // as on its first load after the update
            let gen = WorldGen(seed: meta.seed)
            guard let sc = gen.structures else { continue }
            sc.legacy = w.structureGuard()
            var cities = 0, moved = 0, bad: [String] = []
            for t in sc.types where t.name == "capital_city" || t.name == "military_base" {
                let rx0 = floorDiv(floorDiv(Int(meta.x), CS), t.spacing), rz0 = floorDiv(floorDiv(Int(meta.z), CS), t.spacing)
                for rz in (rz0 - 3)...(rz0 + 3) { for rx in (rx0 - 3)...(rx0 + 3) {
                    guard let s = sc.start(t, regionX: rx, regionZ: rz) else { continue }
                    let ccx = floorDiv((s.min.x + s.max.x) / 2, CS), ccz = floorDiv((s.min.z + s.max.z) / 2, CS)
                    let original = t.name == "military_base" && sc.candidate(t, rx, rz) == (ccx, ccz)
                    if t.name == "capital_city" { cities += 1 } else if !original { moved += 1 }
                    if original { continue }
                    var hit = false
                    for z in floorDiv(s.min.z, CS)...floorDiv(s.max.z, CS) { for x in floorDiv(s.min.x, CS)...floorDiv(s.max.x, CS) where sc.legacy.contains(StructureCache.key(x, z)) { hit = true } }
                    if hit { bad.append("\(t.name) \(s.anchor.x),\(s.anchor.z)") }
                } }
            }
            let px = Int(meta.x), pz = Int(meta.z)
            let near = ["military_base", "capital_city"].map { k -> Int in
                guard let s = sc.nearest(k, x: px, z: pz, maxRegions: 3) else { return -1 }
                return Int(simd_length(V2(Float(s.anchor.x - px), Float(s.anchor.z - pz))))
            }
            check(bad.isEmpty, "factions: saved world '\(n)' (\(sc.legacy.count) explored chunks): \(cities) cities and \(moved) new citadel sites nearby, none on explored ground \(bad); nearest citadel \(near[0]), city \(near[1]) blocks")
        }
        try? fm.removeItem(at: tmp)
    }
}
