import Foundation
import simd

// Ledger 212 (Fable's E, Nov 16): ghost towns laid out within 3 chunks of their site (FrontierSites.typeReach) on new
// ground only. A world saved on the build before (reach 2, no structure-guard-l212.txt), opened on this one, lists the
// same ghost town sites, plans the ones beside its saved ground as it did, and its saved chunks read back as they were.
extension Nov15EveningChecks {
    static func ghostReachGuard(_ g0: Game, _ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("l212-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.removeItem(at: tmp)
        let reach0 = FrontierSites.typeReach
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = false
        defer { FrontierSites.typeReach = reach0; FieldTerrain.newWorlds = field0; try? fm.removeItem(at: tmp) }
        let seed = g0.world.seed, dev = g0.world.device
        // Every ghost town in the regions round the origin: its region and its plan (each piece's box).
        func towns(_ w: World) -> [String: String] {
            guard let sc = w.gen.structures, let ft = sc.types.first(where: { $0.name == FrontierSites.kind }) else { return [:] }
            var out: [String: String] = [:]
            for rz in -14...14 { for rx in -14...14 {
                guard let s = sc.start(ft, regionX: rx, regionZ: rz), s.kind == "ghost_town" else { continue }
                out["\(rx),\(rz)"] = "\(s.anchor.x),\(s.anchor.z): " + s.pieces.map { "\($0.min.x),\($0.min.z)-\($0.max.x),\($0.max.z)" }.joined(separator: ";")
            } }
            return out
        }
        func anchor(_ plan: String) -> (Int, Int) {
            let f = plan.split(separator: ":")[0].split(separator: ",")
            return (Int(f[0]) ?? 0, Int(f[1]) ?? 0)
        }
        FrontierSites.typeReach = 2
        let before = towns(World(seed: seed, device: dev, save: nil))
        FrontierSites.typeReach = 3
        let after = towns(World(seed: seed, device: dev, save: nil))
        // The towns a reach of 3 lays out otherwise, nearest the origin first: two have their ground saved at reach 2.
        let moved = before.keys.filter { after[$0] != before[$0] }.sorted {
            let a = anchor(before[$0]!), b = anchor(before[$1]!)
            return a.0 * a.0 + a.1 * a.1 < b.0 * b.0 + b.1 * b.1
        }
        guard moved.count >= 1 else {
            check(false, "Ledger 212 ghost town reach: no ghost town round the origin laid out otherwise at 3 (\(before.count) towns)"); return
        }
        let savedTowns = Array(moved.prefix(2))
        // The build before: reach 2, the towns' chunks made and saved.
        FrontierSites.typeReach = 2
        let sm1 = SaveManager(dir: tmp)
        let w1 = World(seed: seed, device: dev, save: sm1)
        var saved: [ChunkKey: [BlockID]] = [:]
        for k in savedTowns {
            let (ax, az) = anchor(before[k]!)
            _ = w1.loadSync(center: V3(Float(ax), 100, Float(az)), radius: 1)
            let cx = floorDiv(ax, CS), cz = floorDiv(az, CS)
            for dz in -1...1 { for dx in -1...1 {
                guard let c = w1.chunks[ChunkKey(x: cx + dx, z: cz + dz)] else { continue }
                let raw = c.blocks.rawFull()
                sm1.saveChunk(ChunkKey(x: cx + dx, z: cz + dz), raw)
                saved[ChunkKey(x: cx + dx, z: cz + dz)] = raw
            } }
        }
        SaveIO.flush()
        // (as on its first load on this build: the guard taken then)
        try? fm.removeItem(at: tmp.appendingPathComponent("structure-guard-l212.txt"))
        // The same save opened on the build before (a copy, reach 2): what loading alone does to its chunks (a load's own
        // repairs: the overworld's floor, Emberdeep gates) is the same on both builds.
        let ctl = tmp.deletingLastPathComponent().appendingPathComponent(tmp.lastPathComponent + "-ctl", isDirectory: true)
        try? fm.removeItem(at: ctl)
        try? fm.copyItem(at: tmp, to: ctl)
        defer { try? fm.removeItem(at: ctl) }
        FrontierSites.typeReach = 2
        let wc = World(seed: seed, device: dev, save: SaveManager(dir: ctl))
        var control: [ChunkKey: [BlockID]] = [:]
        for k in saved.keys {
            _ = wc.loadSync(center: V3(Float(k.x * CS + 8), 100, Float(k.z * CS + 8)), radius: 0)
            if let c = wc.chunks[k] { control[k] = c.blocks.rawFull() }
        }
        // This build: reach 3, the same save opened.
        FrontierSites.typeReach = 3
        let w2 = World(seed: seed, device: dev, save: SaveManager(dir: tmp))
        let again = towns(w2)
        let sameSites = Set(again.keys) == Set(before.keys)
        let keptPlans = savedTowns.filter { again[$0] == before[$0] }.count
        let newGround = before.keys.filter { !savedTowns.contains($0) }
        let grown = newGround.filter { again[$0] == after[$0] }.count
        var differ = 0, read = 0, repaired = 0
        for (k, raw) in saved {
            _ = w2.loadSync(center: V3(Float(k.x * CS + 8), 100, Float(k.z * CS + 8)), radius: 0)
            guard let c = w2.chunks[k] else { continue }
            read += 1
            let now = c.blocks.rawFull()
            if now != raw { repaired += 1 }
            if now != control[k] {
                differ += 1
                if let i = (0..<min(now.count, raw.count)).first(where: { now[$0] != raw[$0] }) {
                    print("ghost reach guard: chunk \(k.x),\(k.z) cell \(i % CS),\(i / CSQ),\((i / CS) % CS): saved \(Blocks.key(raw[i])), reach 3 \(Blocks.key(now[i])), reach 2 \(control[k].map { Blocks.key($0[i]) } ?? "none")")
                }
            }
        }
        for k in Set(again.keys).symmetricDifference(before.keys) { print("ghost reach guard: region \(k): reach 2 \(before[k] ?? "none"); now \(again[k] ?? "none")") }
        check(sameSites && keptPlans == savedTowns.count && read == saved.count && differ == 0 && grown == newGround.count,
              "Ledger 212 ghost town reach 3 on new ground only: a world saved at reach 2 lists the same \(again.count) ghost town sites (\(sameSites ? "same" : "NOT the same") as \(before.count)), its \(savedTowns.count) towns by saved ground keep their plans (\(keptPlans) of \(savedTowns.count); without the guard \(savedTowns.count) of \(savedTowns.count) would change), \(read) of \(saved.count) saved chunks read back, \(differ) changed (as the build before reads them; \(repaired) mended by any load); \(grown) of \(newGround.count) towns on new ground laid out at 3 (\(moved.count) of \(before.count) plans differ between 2 and 3)")
    }
}
