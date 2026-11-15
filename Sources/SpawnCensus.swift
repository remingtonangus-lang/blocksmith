import Foundation
import simd

// --spawncensus [--seed N --at X,Y,Z --secs S --rd R] (Nov 14 evening playtest, 21:17 in Elk Hollow: "Why are there so
// many horses spawning here?... Things are being spawned in clumps"): his world (pass --headset) played S seconds with
// him standing at X,Y,Z; every 30 s the animals within 64 and 128 blocks by kind, the tightest clump of one kind (most
// within 8 blocks of one of them), and at the end every pack the spawners put down and where.
enum SpawnCensus {
    static func run(_ g0: Game) -> Int32 {
        let args = CommandLine.arguments
        func arg(_ n: String) -> String? { args.firstIndex(of: n).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        let seed = UInt64(arg("--seed") ?? "") ?? 1898730827681550664
        let at = (arg("--at") ?? "-3208,67,343").split(separator: ",").compactMap { Float($0) }
        let secs = Int(arg("--secs") ?? "") ?? 300
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: seed, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = Int(arg("--rd") ?? "") ?? 8; w.activeDistance = w.renderDistance
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true; SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.survival = true
        g.time = 0.3 * DAY_LENGTH
        let home = V3(at[0], at[1], at[2])
        g.player.pos = home
        let t0 = Date()
        _ = w.loadSync(center: home, radius: min(8, w.renderDistance))
        let x = Int(floor(home.x)), z = Int(floor(home.z))
        g.player.pos = V3(home.x, Float(w.topY(x, z) + 1), home.z)
        print(String(format: "spawncensus: seed %llu at %d %d (%@), loaded in %.0f s", seed, x, z, w.gen.column(x, z).biome.name, Date().timeIntervalSince(t0)))
        MobManager.packLog = []
        defer { MobManager.packLog = nil }
        func census(_ label: String) {
            let p = g.player.pos
            var near: [String: Int] = [:], far: [String: Int] = [:]
            let animals = g.mobs.mobs.filter { $0.health > 0 && $0.kind.category == .creature }
            for m in animals {
                let d = simd_length(V2(m.pos.x - p.x, m.pos.z - p.z))
                let k = m.kind.spec.name + (m.tamed ? " (tame)" : (m.persistent ? " (kept)" : ""))
                if d < 64 { near[k, default: 0] += 1 }
                if d < 128 { far[k, default: 0] += 1 }
            }
            var clump = (0, "", V3(0, 0, 0))
            for m in animals where simd_length(V2(m.pos.x - p.x, m.pos.z - p.z)) < 128 {
                let n = animals.filter { $0.kind == m.kind && simd_length($0.pos - m.pos) < 8 }.count
                if n > clump.0 { clump = (n, m.kind.spec.name, m.pos) }
            }
            func list(_ d: [String: Int]) -> String { d.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") }
            print("spawncensus \(label): within 64: \(list(near))")
            print("spawncensus \(label): within 128: \(list(far))")
            print(String(format: "spawncensus %@: tightest clump %d %@ within 8 blocks at %.0f %.0f", label, clump.0, clump.1, clump.2.x, clump.2.z))
        }
        census("t0")
        let dt = 1.0 / 20
        for s in 1...secs {
            for _ in 0..<20 {
                g.player.vel = .zero
                g.tick(dt)
            }
            if s % 30 == 0 { census("t\(s)") }
        }
        print("spawncensus: packs put down in \(secs) s:")
        for p in MobManager.packLog ?? [] {
            let d = simd_length(V2(Float(p.x) - g.player.pos.x, Float(p.z) - g.player.pos.z))
            print(String(format: "  %@ %d %@ at %d %d (%.0f blocks off)", p.why, p.n, p.kind.spec.name, p.x, p.z, d))
        }
        return 0
    }
}
