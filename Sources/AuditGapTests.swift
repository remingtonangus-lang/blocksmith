import Foundation
import simd

// Checks for the done-audit gaps of task 25b4zzza (docs/status/done-audit.md): `--questbugs --only gaps`, also part
// of the full `--questbugs` run.
enum AuditGapTests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        padSwell(game, check)
        // #5 The helm's speed vignette: none at sailing speeds, rising to about half at the frigate's 42 b/s.
        let v = [8, 12, 20, 30, 42, 60].map { ShipComfort.vignette(speed: Float($0)) }
        check(v[0] == 0 && v[1] == 0 && zip(v.dropFirst(), v.dropFirst(2)).allSatisfy { $0.0 < $0.1 || $0.1 == 0.55 } && abs(v[4] - 0.55) < 0.01,
              "ship helm speed vignette: \(v.map { String(format: "%.2f", $0) }) at 8/12/20/30/42/60 b/s (x the Comfort Vignette setting)")
        thinning(game, check)
        swamps(check)
        let pin = pinnedShore(WorldGen(seed: 12345))
        check(pin != nil, "the Quest water views' pinned seed-12345 shore exists (\(pin.map { "\($0.0)" } ?? "none"))")
    }

    // #2 The Quest water views' fallback shore (questcheck searches 8 directions from spawn first): seed 12345's
    // deepest sea within 3000 blocks of spawn is at (-2680, 680) (88, SEA 126); the nearest land from there along the
    // four axes is the beach, looking back out to sea.
    static func pinnedShore(_ gen: TerrainGenerator) -> ((Int, Int), (Float, Float))? {
        guard (gen as? WorldGen)?.seed == 12345 else { return nil }
        var best: ((Int, Int), (Float, Float), Int)? = nil
        for d in [(1, 0), (0, 1), (-1, 0), (0, -1)] {
            for r in stride(from: 0, through: 1600, by: 4) where gen.column(-2680 + d.0 * r, 680 + d.1 * r).height >= SEA {
                if best == nil || r < best!.2 { best = ((-2680 + d.0 * r, 680 + d.1 * r), (Float(-d.0), Float(-d.1)), r) }
                break
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    // #1 Lily pads ride the swell with the water: a pond 1-4 deep (a stone basin in the air, one section) with a pad on
    // every surface cell, meshed with the Quest's water depth AO; every pad corner must carry the same shore factor as
    // the water corner under it (chunk.vert lifts both by oceanWave * waveK[ao]).
    static func padSwell(_ game: Game, _ check: (Bool, String) -> Void) {
        let w = game.world, p0 = game.player.pos
        let x0 = ((Int(floorf(p0.x)) + 260) & ~15) + 3, z0 = ((Int(floorf(p0.z)) - 60) & ~15) + 3
        _ = w.loadSync(center: V3(Float(x0), p0.y, Float(z0)), radius: 2)
        let yS = min(CH - 40, ((w.topY(x0, z0) + 24) & ~15) + 10)          // the water surface row, mid-section
        let pad = Blocks.id("lily_pad")
        var placed: [IVec3] = []
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { w.setBlock(x, y, z, b); placed.append(IVec3(x, y, z)) }
        for dz in -1...9 { for dx in -1...9 {
            let inside = dx >= 0 && dx < 9 && dz >= 0 && dz < 9
            let depth = inside ? 1 + min(3, (dx + dz) / 4) : 0
            put(x0 + dx, yS - 5, z0 + dz, STONE)
            for y in (yS - 4)...yS { put(x0 + dx, y, z0 + dz, y > yS - depth && inside ? WATER : STONE) }
            if inside { put(x0 + dx, yS + 1, z0 + dz, pad) }
        } }
        defer { for q in placed.reversed() { w.setBlock(q.x, q.y, q.z, AIR) } }
        let was = Mesher.waterDepthAO
        Mesher.waterDepthAO = true
        defer { Mesher.waterDepthAO = was }
        guard let c = w.chunkAt(x0 + 4, z0 + 4), let nb = w.neighbourhood(c) else { check(false, "lily pad swell: mesh setup"); return }
        // The basin spans up to 4 chunks: mesh the one holding its middle and compare the corners it holds.
        let m = Mesher.buildSection(nb.0, nb.1, sy: yS >> 4)
        let ly = yS & 15
        var water: [Int: UInt32] = [:], pads: [(Int, UInt32)] = []
        for arr in [m.opaque, m.trans] {
            for i in stride(from: 0, to: arr.count, by: 2) {
                let w0 = arr[i], w1 = arr[i + 1]
                let x16 = Int(w0 & 511), y16 = Int((w0 >> 9) & 511), z16 = Int((w0 >> 18) & 511), tint = (w0 >> 30) & 3
                let ao = (w1 >> 20) & 3, key = x16 * 1024 + z16
                if tint == 3 && y16 == ly * 16 + 14 { water[key] = ao }
                if tint == 2 && y16 == ly * 16 + 15 { pads.append((key, ao)) }
            }
        }
        let matched = pads.filter { water[$0.0] == $0.1 }.count
        let kinds = Set(pads.map { $0.1 })
        check(pads.count >= 16 && matched == pads.count && kinds.count >= 2,
              "lily pad swell: \(matched)/\(pads.count) pad corners share the shore factor of the water under them (factors seen \(kinds.sorted()))")
    }

    // #3 Old saves' animal crowds: a format-3 world with 12 wild cows in one chunk, 8 penned cows (an oak fence) in
    // another and the player's own animals (named, leashed, baby, tamed, bred, saddled) in a third loads with a backup
    // made first, the wild crowd cut to the cap, everything else kept, and a second load changing nothing.
    static func thinning(_ game: Game, _ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-thin-\(UInt32.random(in: 0...UInt32.max))")
        let wdir = tmp.appendingPathComponent("Worlds/Herd World", isDirectory: true)
        try? fm.createDirectory(at: wdir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let sm = SaveManager(dir: wdir)
        var meta = game.meta
        meta.extra = ["format": "3"]
        try? JSONEncoder().encode(meta).write(to: sm.metaURL)
        // Chunk (1, 0): an oak fence post at local (8, 70, 8), beside the penned cows.
        let fy = 70
        var bytes: [UInt8] = []
        let names = ["air", "oak_fence"]
        bytes += [UInt8(names.count), 0, 0, 0]
        for n in names { let u = Array(n.utf8); bytes += [UInt8(u.count & 255), UInt8(u.count >> 8)] + u }
        var idx = [UInt16](repeating: 0, count: CSQ * CH)
        idx[Chunk.index(8, fy, 8)] = 1
        for v in idx { bytes += [UInt8(v & 255), UInt8(v >> 8)] }
        if let comp = try? (Data(bytes) as NSData).compressed(using: .lzfse) as Data { try? comp.write(to: sm.chunkURL(ChunkKey(x: 1, z: 0))) }
        func cow(_ x: Float, _ z: Float, _ edit: (inout MobRecord) -> Void = { _ in }) -> MobRecord {
            var r = MobRecord(k: "cow", p: [x, 70, z], yaw: 0, hp: 10)
            edit(&r)
            return r
        }
        var all: [String: [MobRecord]] = [:]
        all["0,0"] = (0..<12).map { cow(1 + Float($0), 5) }
        all["1,0"] = (0..<8).map { cow(16 + 6 + Float($0 % 4), 7 + Float($0 / 4)) }
        all["2,0"] = [cow(33, 3) { $0.name = "Daisy" }, cow(34, 3) { $0.knot = [] }, cow(35, 3) { $0.baby = true; $0.age = 0 },
                      MobRecord(k: "wolf", p: [36, 70, 3], yaw: 0, hp: 20, extra: ["owned": 1]), cow(37, 3) { $0.extra = ["bred": 1] },
                      MobRecord(k: "horse", p: [38, 70, 3], yaw: 0, hp: 20, extra: ["saddle": 1])] +
                     (0..<4).map { cow(40 + Float($0), 3) }
        try? JSONEncoder().encode(all).write(to: wdir.appendingPathComponent("mobs.json"))
        // As QuestApp/App open a world: the meta first (the backup), then the mobs.
        _ = SaveManager(dir: wdir).loadMeta()
        let backups = ((try? fm.contentsOfDirectory(atPath: tmp.appendingPathComponent("Backups").path)) ?? [])
        let backedMobs = backups.first.map { fm.fileExists(atPath: tmp.appendingPathComponent("Backups/\($0)/mobs.json").path) } ?? false
        let mm = MobManager()
        mm.load(from: sm)
        let n0 = mm.stored[ChunkKey(x: 0, z: 0)]?.count ?? 0, n1 = mm.stored[ChunkKey(x: 1, z: 0)]?.count ?? 0
        let n2 = mm.stored[ChunkKey(x: 2, z: 0)]?.count ?? 0
        let named = mm.stored[ChunkKey(x: 2, z: 0)]?.contains { $0.name == "Daisy" } ?? false
        check(backups.count == 1 && backups[0].hasPrefix("Herd World-before-f4-") && backedMobs,
              "animal thinning: the world is backed up first (\(backups), mobs.json copied \(backedMobs))")
        check(n0 == MobManager.thinCap && n1 == 8 && n2 == 10 && named,
              "animal thinning: wild crowd 12 -> \(n0) (cap \(MobManager.thinCap)), penned 8 -> \(n1), the player's own 6 + 4 wild -> \(n2) (want 10), named kept \(named)")
        mm.save(to: sm)
        let again = MobManager()
        again.load(from: sm)
        check(again.stored.values.reduce(0) { $0 + $1.count } == n0 + n1 + n2, "animal thinning runs once (second load keeps \(again.stored.values.reduce(0) { $0 + $1.count }))")
        // A bred calf keeps its mark through a save.
        let calf = Mob(.cow, at: V3(0, 70, 0)); calf.bred = true
        check(Mob.from(calf.record)?.bred == true, "a bred animal's mark survives a save")
    }

    // #10 Swamps have open water with lily pads: seeds 12345 and 777, 6x6 chunks around the middle of a swamp. Counts
    // the swamp columns whose surface (under trees and pads) is water, the pads on that water, and spills (a surface
    // water block beside air at its own level inside the chunk).
    static func swamps(_ check: (Bool, String) -> Void) {
        let g = Blocks.id
        let pad = g("lily_pad"), leafT = Mesher.leafT
        // The middles of the swamps `--find swamp` jumps to (Snapshot.findBiome is Mac-only; this also runs on Quest).
        for (seed, c): (UInt64, V3) in [(12345, V3(968, 0, 1784)), (777, V3(1448, 0, -664))] {
            let gen = WorldGen(seed: seed)
            let ccx = floorDiv(Int(c.x), CS), ccz = floorDiv(Int(c.z), CS)
            var cols = 0, wet = 0, pads = 0, spills = 0
            var pond: (Int, Int, Int)? = nil, best = 0       // the densest raft (pads in a 5x5): the lily pond shots' spot
            for cz in (ccz - 3)..<(ccz + 3) { for cx in (ccx - 3)..<(ccx + 3) {
                let b = gen.generate(cx: cx, cz: cz)
                for lz in 0..<CS { for lx in 0..<CS {
                    let wx = cx * CS + lx, wz = cz * CS + lz
                    let biome = gen.column(wx, wz).biome
                    guard biome == .swamp || biome == .mangroveSwamp else { continue }
                    var y = CH - 2
                    var sawPad = false
                    while y > 1 {
                        let id = b[Chunk.index(lx, y, lz)]
                        if id == pad { sawPad = true }
                        if id == WATER || (Blocks.opaque[Int(id)] && !leafT[Int(id)] && !Blocks.key(id).hasSuffix("_log")) { break }
                        y -= 1
                    }
                    cols += 1
                    guard b[Chunk.index(lx, y, lz)] == WATER else { continue }
                    wet += 1
                    if sawPad {
                        pads += 1
                        if lx >= 2 && lx < CS - 2 && lz >= 2 && lz < CS - 2 {
                            var n = 0
                            for dz in -2...2 { for dx in -2...2 where b[Chunk.index(lx + dx, y + 1, lz + dz)] == pad { n += 1 } }
                            if n > best { best = n; pond = (wx, y - YOFF, wz) }
                        }
                    }
                    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = lx + dx, nz = lz + dz
                        guard nx >= 0 && nx < CS && nz >= 0 && nz < CS else { continue }
                        if b[Chunk.index(nx, y, nz)] == AIR {
                            spills += 1
                            if spills <= 4 {
                                let c0 = gen.column(wx, wz), c1 = gen.column(wx + dx, wz + dz)
                                print("swamp spill at \(wx), \(y - YOFF), \(wz) -> \(dx),\(dz): biomes \(c0.biome.name)/\(c1.biome.name) heights \(c0.height)/\(c1.height) wl \(gen.terrain.column(wx, wz).wl)/\(gen.terrain.column(wx + dx, wz + dz).wl) stack \((y - 3...y + 1).map { Blocks.key(b[Chunk.index(lx, $0, lz)]) }) n \((y - 3...y + 1).map { Blocks.key(b[Chunk.index(nx, $0, nz)]) })")
                            }
                        }
                    }
                }}
            }}
            if let p = pond { print("swamp seed \(seed): lily pond at \(p.0), \(p.1), \(p.2) (\(best) pads in 5x5)") }
            let wf = cols > 0 ? Float(wet) / Float(cols) : 0
            let pf = wet > 0 ? Float(pads) / Float(wet) : 0
            check(cols > 2000 && wf >= 0.22 && pf >= 0.06 && spills == 0,
                  String(format: "swamp seed %llu at (%.0f, %.0f): %d swamp columns, open water %.0f%% (want >= 22%%), lily pads on %.0f%% of it (want >= 6%%), %d spills",
                         seed, c.x, c.z, cols, wf * 100, pf * 100, spills))
        }
    }
}
