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

// --wearprobe X,Y,Z [--from X,Y,Z --seed N --gun KEY --secs S] (Nov 14 evening, 20:49:21 at a Greywall Outpost: "I
// can't break through that? Should be able to break through that block", the Slatefall Carbine held, looking at Dark
// Station Concrete at -2833 92 167): his world (pass --headset); the block at X,Y,Z (shown y) and what it is (key,
// hardness, resistance, the rounds it takes, seconds by hand and by an iron pickaxe), then him at --from holding the gun
// with the trigger held on it for S seconds: rounds fired, what they struck, its wear and whether it went.
enum WearProbe {
    static func run(_ g0: Game) -> Int32 {
        let args = CommandLine.arguments
        func arg(_ n: String) -> String? { args.firstIndex(of: n).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        func v3(_ s: String?) -> V3? {
            guard let p = s?.split(separator: ",").compactMap({ Float($0) }), p.count == 3 else { return nil }
            return V3(p[0], p[1] + Float(YOFF), p[2])
        }
        let seed = UInt64(arg("--seed") ?? "") ?? 1898730827681550664
        guard let at = v3(arg("--wearprobe")) else { print("wearprobe: --wearprobe X,Y,Z"); return 2 }
        let from = v3(arg("--from")) ?? V3(-2828.2, 92.2, 164.9) + V3(0, Float(YOFF), 0)
        let gun = arg("--gun") ?? "gun_slatefall"
        let secs = Double(arg("--secs") ?? "") ?? 6
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: seed, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 6; w.activeDistance = 6
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true; SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.survival = true
        g.time = 0.3 * DAY_LENGTH
        g.player.pos = from
        _ = w.loadSync(center: from, radius: 5)
        for _ in 0..<40 { g.tick(1.0 / 20) }                  // (structures and their mobs settle)
        let b = IVec3(Int(floor(at.x)), Int(floor(at.y)), Int(floor(at.z)))
        let id = w.block(b.x, b.y, b.z)
        let i = Int(id)
        let hand = Mining.breakSeconds(id, .empty, onGround: true, inWater: false)
        let pick = Mining.breakSeconds(id, ItemStack(Items.id("iron_pickaxe"), 1), onGround: true, inWater: false)
        print(String(format: "wearprobe: %d %d %d is %@ (%@): hardness %.1f, resistance %.0f, rounds' hp %.0f, block entity %@, by hand %.1f s, iron pickaxe %.1f s",
                     b.x, b.y - YOFF, b.z, Blocks.key(id), Blocks.name(id), Blocks.hardness[i], Blocks.resistance[i], BlockWear.hp(id),
                     w.blockEntities[b] == nil ? "no" : "yes", hand, pick))
        for (n, d) in [("above", IVec3(0, 1, 0)), ("below", IVec3(0, -1, 0)), ("x+", IVec3(1, 0, 0)), ("x-", IVec3(-1, 0, 0)), ("z+", IVec3(0, 0, 1)), ("z-", IVec3(0, 0, -1))] {
            print("wearprobe:   \(n): \(Blocks.key(w.block(b.x + d.x, b.y + d.y, b.z + d.z)))")
        }
        guard Items.has(gun) else { print("wearprobe: no gun \(gun)"); return 1 }
        g.inventory.selected = 0
        g.inventory.main[0] = ItemStack(Items.id(gun), 1)
        if let gi = Guns.index(Items.id(gun)), Items.has(Guns.all[gi].ammo) { let spec = Guns.all[gi]; g.inventory.main[1] = ItemStack(Items.id(spec.ammo), 64); g.inventory.main[2] = ItemStack(Items.id(spec.ammo), 64) }
        let c = V3(Float(b.x) + 0.5, Float(b.y) + 0.5, Float(b.z) + 0.5)
        var t = 0.0, fired0 = BlockWear.shotOut, broke = false
        var hitCells: [IVec3: Int] = [:]
        g.input.leftDown = true
        while t < secs && !broke {
            g.player.pos = from; g.player.vel = .zero
            let d = c - g.player.eye
            g.player.yaw = atan2f(-d.x, -d.z); g.player.pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
            g.tick(1.0 / 72); t += 1.0 / 72
            for (k, _) in BlockWear.marks { hitCells[k, default: 0] += 1 }
            broke = w.block(b.x, b.y, b.z) != id
        }
        g.input.leftDown = false
        let worn = BlockWear.marks[b]?.dealt ?? 0
        print(String(format: "wearprobe: %.1f s on the trigger with %@: %@; its wear %.0f of %.0f; %d blocks shot out; worn cells %@; the gun's state: %@",
                     t, gun, broke ? "IT WENT" : "it stands", worn, BlockWear.hp(id), BlockWear.shotOut - fired0,
                     hitCells.keys.map { "\($0.x) \($0.y - YOFF) \($0.z) \(Blocks.key(w.block($0.x, $0.y, $0.z)))" }.prefix(6).joined(separator: "; "),
                     "shots \(g.arms.shotsFired), reload \(g.arms.reload)"))
        return 0
    }
}
