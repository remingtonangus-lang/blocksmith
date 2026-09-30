import Foundation
import Metal
import simd

// Performance benchmarks (headless, like --snapshot):
//   Blocksmith --bench snaps/bench.json [--scenes gen,mesh,...] [--seed N] [--quick]
// Scenes: gen (single-thread chunk generation + parallel throughput), mesh (single-thread section meshing,
// full and far LOD), startup (world + renderer init, first load, time to fill rd 12), frame (static view
// at rd 16 at 1280x800 / 1080p / 4K), edit (block break/place with synchronous remesh), mobs (tick cost
// with 150 mobs), save (chunk save/load), flight8/flight16/flight24 (flying at 20 blocks/s for 12 s at
// render distance 8/16/24, paced to 60 fps: per-frame tick / encode / GPU times, streaming coverage,
// gen/mesh throughput, memory).
// Every metric goes into one flat JSON object (times in ms, memory in MB) that CI compares against
// perf/baseline.json.
enum Bench {
    static var metrics: [String: Double] = [:]
    static var now: Double { CFAbsoluteTimeGetCurrent() }

    static func put(_ k: String, _ v: Double) { metrics[k] = (v * 1000).rounded() / 1000 }

    struct Dist { var mean = 0.0, p50 = 0.0, p95 = 0.0, p99 = 0.0, max = 0.0 }
    static func dist(_ xs: [Double]) -> Dist {
        if xs.isEmpty { return Dist() }
        let s = xs.sorted()
        func q(_ f: Double) -> Double { s[min(s.count - 1, Int(Double(s.count - 1) * f + 0.5))] }
        return Dist(mean: s.reduce(0, +) / Double(s.count), p50: q(0.5), p95: q(0.95), p99: q(0.99), max: s[s.count - 1])
    }
    static func put(_ k: String, _ d: Dist, _ which: String = "mean,p50,p95,p99,max") {
        for w in which.split(separator: ",") {
            switch w {
            case "mean": put("\(k)_mean", d.mean)
            case "p50": put("\(k)_p50", d.p50)
            case "p95": put("\(k)_p95", d.p95)
            case "p99": put("\(k)_p99", d.p99)
            default: put("\(k)_max", d.max)
            }
        }
    }
    static func f(_ v: Double, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", v) }

    static func run(_ out: String) -> Int32 {
        let t0 = now
        guard let device = MTLCreateSystemDefaultDevice() else { print("no Metal device"); return 1 }
        let seed = UInt64(arg("--seed") ?? "") ?? 12345
        let quick = CommandLine.arguments.contains("--quick")
        let all = "gen,mesh,startup,frame,edit,mobs,save,tnt,fluids,flight8,flight16,flight24"
        let scenes = (arg("--scenes") ?? all).split(separator: ",").map(String.init)
        print("bench: device \(device.name), \(ProcessInfo.processInfo.activeProcessorCount) cores, seed \(seed)\(quick ? ", quick" : "")")
        for s in scenes {
            let ts = now
            switch s {
            case "gen": gen(device, seed)
            case "mesh": mesh(device, seed)
            case "startup": startup(device, seed, t0)
            case "frame": frame(device, seed)
            case "edit": edit(device, seed)
            case "mobs": mobs(device, seed)
            case "save": save(device, seed)
            case "tnt": tnt(device, seed)
            case "fluids": fluids(device, seed)
            case "meshprof": meshLoop(device, seed, seconds: Double(arg("--secs") ?? "") ?? 12)
            case "genprof": genLoop(device, seed, seconds: Double(arg("--secs") ?? "") ?? 12)
            case let name where name.hasPrefix("flight"):
                flight(device, seed, rd: Int(name.dropFirst(6)) ?? 16, seconds: quick ? 5 : 12, speed: 20)
            default: print("bench: unknown scene \(s)")
            }
            print("bench: \(s) took \(f(now - ts, 1)) s")
        }
        usleep(1_500_000)                                   // queued worker jobs still hold their world briefly
        put("worlds_alive", Double(World.alive))           // every scene's world should be gone by now
        print("bench: worlds still alive after the scenes: \(World.alive)")
        put("total_s", now - t0)
        let dir = (out as NSString).deletingLastPathComponent
        if !dir.isEmpty { try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }
        if let d = try? JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: URL(fileURLWithPath: out))
            print("bench: wrote \(metrics.count) metrics to \(out)")
        }
        return 0
    }

    // A fresh world + game with the camera flying at the spawn point.
    static func setup(_ device: MTLDevice, _ seed: UInt64, rd: Int) -> (World, Game, V3) {
        let world = World(seed: seed, device: device, save: nil)
        world.renderDistance = rd
        let game = Game(world: world, save: nil, persistent: false)
        let pos = game.findSpawn()
        game.player.pos = pos
        game.player.flying = true
        game.paused = false
        game.time = 0.25 * DAY_LENGTH
        return (world, game, pos)
    }

    // Whether any chunk inside the render distance still has sections waiting to be (re-)meshed.
    static func unmeshed(_ w: World, _ p: V3) -> Bool {
        let cx = floorDiv(Int(floor(p.x)), CS), cz = floorDiv(Int(floor(p.z)), CS)
        let r = w.renderDistance
        for dz in -r...r { for dx in -r...r where w.inMeshRadius(dx, dz) {
            if let c = w.chunks[ChunkKey(x: cx + dx, z: cz + dz)], c.needsMesh { return true }
        } }
        return false
    }

    // Fraction of chunks inside the render distance that have a mesh.
    static func coverage(_ w: World, _ p: V3) -> Double {
        let cx = floorDiv(Int(floor(p.x)), CS), cz = floorDiv(Int(floor(p.z)), CS)
        let r = w.renderDistance
        var n = 0, ok = 0
        for dz in -r...r { for dx in -r...r where w.inMeshRadius(dx, dz) {
            n += 1
            if let c = w.chunks[ChunkKey(x: cx + dx, z: cz + dz)], c.meshedOnce { ok += 1 }
        } }
        return n == 0 ? 1 : Double(ok) / Double(n)
    }

    // Loaded chunk storage: block ids + light per chunk.
    static func chunkMB(_ w: World) -> Double {
        var b = 0
        let shared = Set([Mesher.dark, Mesher.fullSky].map { $0.withUnsafeBufferPointer { Int(bitPattern: $0.baseAddress) } })
        for c in w.chunks.values {
            b += c.blocks.storedCount * MemoryLayout<BlockID>.stride + c.height.count * 2 + c.tint.count * 4
            for l in c.light { if let l, !shared.contains(l.withUnsafeBufferPointer { Int(bitPattern: $0.baseAddress) }) { b += l.count } }
        }
        return Double(b) / 1_048_576
    }

    static func meshMB(_ w: World) -> Double {
        var b = 0
        for c in w.chunks.values { for s in c.sections { b += (s.opaqueBuf?.length ?? 0) + (s.transBuf?.length ?? 0) } }
        return Double(b) / 1_048_576
    }

    // MARK: Scenes

    static func gen(_ device: MTLDevice, _ seed: UInt64) {
        let world = World(seed: seed, device: device, save: nil)
        let g = world.gen
        _ = g.generate(cx: 0, cz: 0)                       // lazy tables
        var times: [Double] = []
        var hash: UInt64 = 0xcbf29ce484222325           // FNV-1a over every generated block: flags terrain changes
        for i in 0..<24 {
            let cx = i * 7 - 80, cz = (i * 13) % 50 - 25
            let a = now
            var b = g.generate(cx: cx, cz: cz)
            if let st = g.structures { _ = st.place(into: &b, cx: cx, cz: cz) }
            _ = g.tints(cx: cx, cz: cz)
            _ = Chunk.computeHeights(b)
            times.append((now - a) * 1000)
            for v in b { hash = (hash ^ UInt64(v)) &* 0x100000001b3 }
        }
        put("gen.terrain_hash", Double(hash >> 12))       // 52 bits: exact in a Double
        if let wg = g as? WorldGen {
            var bad = 0
            for i in 0..<6 { bad += wg.latticeRowMismatches(cx: i * 11 - 30, cz: i * 5 - 12) }
            put("gen.lattice_mismatches", Double(bad))
            print("bench gen: stone-fill interpolation vs Lattice.sample: \(bad) mismatching samples (must be 0)")
        }
        let d = dist(times)
        put("gen.chunk_ms", d, "mean,p95,max")
        // Parallel throughput over all cores (what streaming can reach at best).
        let n = 96
        let a = now
        DispatchQueue.concurrentPerform(iterations: n) { i in
            let cx = 200 + i % 12, cz = -300 + i / 12
            var b = g.generate(cx: cx, cz: cz)
            if let st = g.structures { _ = st.place(into: &b, cx: cx, cz: cz) }
            _ = g.tints(cx: cx, cz: cz)
        }
        let rate = Double(n) / (now - a)
        put("gen.parallel_chunks_per_s", rate)
        print("bench gen: \(f(d.mean)) ms/chunk (p95 \(f(d.p95)), max \(f(d.max))) single-thread | \(f(rate, 0)) chunks/s parallel")
    }

    static func mesh(_ device: MTLDevice, _ seed: UInt64) {
        let (world, game, pos) = setup(device, seed, rd: 4)
        defer { withExtendedLifetime(game) {} }
        _ = world.loadSync(center: pos, radius: 3)
        let cx = floorDiv(Int(pos.x), CS), cz = floorDiv(Int(pos.z), CS)
        for lod in 0...1 {
            var chunkMs: [Double] = [], secUs: [Double] = []
            var quads = 0, nonEmpty = 0
            for oz in -1...1 { for ox in -1...1 {
                var n9: [BlockStore] = [], h9: [[Int16]] = []
                for dz in -1...1 { for dx in -1...1 {
                    guard let c = world.chunks[ChunkKey(x: cx + ox + dx, z: cz + oz + dz)] else { continue }
                    n9.append(c.blocks); h9.append(c.height)
                } }
                if n9.count < 9 { continue }
                var total = 0.0
                for sy in 0..<NSEC {
                    let a = now
                    let m = Mesher.buildSection(n9, h9, sy: sy, lod: lod)
                    let el = now - a
                    total += el
                    secUs.append(el * 1e6)
                    let q = (m.opaque.count + m.trans.count) / 8
                    quads += q
                    if q > 0 { nonEmpty += 1 }
                }
                chunkMs.append(total * 1000)
            } }
            let d = dist(chunkMs), s = dist(secUs)
            let k = lod == 0 ? "mesh" : "mesh_lod1"
            put("\(k).chunk_ms", d, "mean,max")
            put("\(k).section_us", s, "mean,p95,max")
            put("\(k).quads_per_chunk", Double(quads) / Double(max(1, chunkMs.count)))
            print("bench \(k): \(f(d.mean)) ms/chunk (\(NSEC) sections, \(nonEmpty) non-empty), section mean \(f(s.mean, 0)) us p95 \(f(s.p95, 0)) us max \(f(s.max, 0)) us, \(quads / max(1, chunkMs.count)) quads/chunk")
        }
    }

    // Profiling loops (perf/profile.sh): single-thread meshing / generation for a fixed time.
    static func meshLoop(_ device: MTLDevice, _ seed: UInt64, seconds: Double) {
        let (world, game, pos) = setup(device, seed, rd: 4)
        defer { withExtendedLifetime(game) {} }
        _ = world.loadSync(center: pos, radius: 3)
        let cx = floorDiv(Int(pos.x), CS), cz = floorDiv(Int(pos.z), CS)
        var n9: [BlockStore] = [], h9: [[Int16]] = []
        for dz in -1...1 { for dx in -1...1 {
            guard let c = world.chunks[ChunkKey(x: cx + dx, z: cz + dz)] else { return }
            n9.append(c.blocks); h9.append(c.height)
        } }
        let a = now
        var n = 0
        while now - a < seconds { for sy in 0..<NSEC { _ = Mesher.buildSection(n9, h9, sy: sy) }; n += 1 }
        print("bench meshprof: \(n) chunks in \(f(seconds, 0)) s")
    }

    static func genLoop(_ device: MTLDevice, _ seed: UInt64, seconds: Double) {
        let world = World(seed: seed, device: device, save: nil)
        let a = now
        var n = 0
        while now - a < seconds {
            var b = world.gen.generate(cx: n % 17, cz: n / 17)
            if let st = world.gen.structures { _ = st.place(into: &b, cx: n % 17, cz: n / 17) }
            n += 1
        }
        print("bench genprof: \(n) chunks in \(f(seconds, 0)) s")
    }

    static func startup(_ device: MTLDevice, _ seed: UInt64, _ processT0: Double) {
        let a = now
        let (world, game, pos) = setup(device, seed, rd: 12)
        let tWorld = now - a
        let b = now
        _ = world.loadSync(center: pos, radius: 4)          // what the app does before the first frame
        let tFirst = now - b
        let c = now
        guard (try? Renderer(device: device, game: game, colorFormat: .bgra8Unorm)) != nil else { print("bench startup: renderer failed"); return }
        let tRenderer = now - c
        let c2 = now
        _ = try? Renderer(device: device, game: game, colorFormat: .bgra8Unorm)   // again: compiled shaders are cached
        put("startup.renderer_init_again_ms", (now - c2) * 1000)
        // Streaming the rest of render distance 12 in the background (update() once per 60 Hz frame).
        let d = now
        var full = -1.0
        while now - d < 60 {
            world.update(center: pos)
            if coverage(world, pos) >= 1 { full = now - d; break }
            usleep(16_000)
        }
        // Renderer init breakdown (each repeated here on its own).
        var e = now
        _ = TextureGen.mipChain()
        put("startup.textures_ms", (now - e) * 1000)
        e = now
        _ = try? device.makeLibrary(source: shaderSource, options: nil)
        put("startup.shader_compile_ms", (now - e) * 1000)
        put("startup.world_init_ms", tWorld * 1000)
        put("startup.first_load_ms", tFirst * 1000)
        put("startup.renderer_init_ms", tRenderer * 1000)
        put("startup.fill_rd12_s", full)
        put("startup.since_launch_s", now - processT0)
        print("bench startup: world+game init \(f(tWorld * 1000, 0)) ms, first load (r 4) \(f(tFirst * 1000, 0)) ms, renderer \(f(tRenderer * 1000, 0)) ms (textures \(f(metrics["startup.textures_ms"] ?? 0, 0)) ms, shaders \(f(metrics["startup.shader_compile_ms"] ?? 0, 0)) ms), fill rd 12 \(f(full, 2)) s")
    }

    static func frame(_ device: MTLDevice, _ seed: UInt64) {
        let (world, game, p0) = setup(device, seed, rd: 16)
        var pos = p0
        pos.y += 20
        game.player.pos = pos
        game.player.yaw = 200 * .pi / 180
        game.player.pitch = -8 * .pi / 180
        _ = world.loadSync(center: pos, radius: 16)
        guard let r = try? Renderer(device: device, game: game, colorFormat: .bgra8Unorm) else { return }
        for (w, h, name) in [(1280, 800, "800p"), (1920, 1080, "1080p"), (3840, 2160, "4k")] {
            guard let t = OffscreenTarget(device, w, h) else { continue }
            for _ in 0..<3 { _ = r.benchFrame(t) }
            var enc: [Double] = [], gpu: [Double] = []
            for _ in 0..<30 { let (e, g) = r.benchFrame(t); enc.append(e * 1000); gpu.append(g * 1000) }
            let e = dist(enc), g = dist(gpu)
            put("frame_\(name).encode_ms", e, "p50,max")
            put("frame_\(name).gpu_ms", g, "p50,max")
            print("bench frame \(name) rd 16: encode p50 \(f(e.p50)) ms, GPU p50 \(f(g.p50)) ms (max \(f(g.max))), \(r.drawnChunks) chunks drawn")
        }
        put("frame.drawn_chunks", Double(r.drawnChunks))
        put("frame.visible_sections", Double(r.visibleSections))
        put("frame.draw_calls", Double(r.drawCalls))
        put("frame.drawn_kquads", Double(r.drawnQuads) / 1000)
        print("bench frame: \(r.visibleSections) visible sections, \(r.drawCalls) draw calls, \(r.drawnQuads / 1000)k quads")
        put("frame.mesh_mb", meshMB(world))
    }

    static func edit(_ device: MTLDevice, _ seed: UInt64) {
        let (world, game, pos) = setup(device, seed, rd: 6)
        defer { withExtendedLifetime(game) {} }
        _ = world.loadSync(center: pos, radius: 6)
        let bx = Int(floor(pos.x)), bz = Int(floor(pos.z))
        var brk: [Double] = [], plc: [Double] = []
        for i in 0..<48 {
            let x = bx + i % 8 - 4, z = bz + i / 8 - 3
            let y = world.topY(x, z)
            guard y > 0 else { continue }
            let old = world.block(x, y, z)
            var a = now
            world.setBlock(x, y, z, AIR)
            brk.append((now - a) * 1000)
            a = now
            world.setBlock(x, y, z, old)
            plc.append((now - a) * 1000)
        }
        // Let the background re-meshes (light spread) settle.
        let s = now
        while world.pendingJobs > 0 && now - s < 10 { world.update(center: pos); usleep(2000) }
        let b = dist(brk), p = dist(plc)
        put("edit.break_ms", b, "mean,max")
        put("edit.place_ms", p, "mean,max")
        print("bench edit: break mean \(f(b.mean)) ms max \(f(b.max)) ms, place mean \(f(p.mean)) ms max \(f(p.max)) ms (synchronous remesh)")
    }

    static func mobs(_ device: MTLDevice, _ seed: UInt64) {
        let (world, game, pos) = setup(device, seed, rd: 6)
        _ = world.loadSync(center: pos, radius: 6)
        let dt = 1.0 / 60
        func run(_ n: Int) -> Dist {
            var t: [Double] = []
            for _ in 0..<n {
                game.player.pos = pos
                let a = now
                game.tick(dt)
                t.append((now - a) * 1000)
            }
            return dist(t)
        }
        _ = run(30)
        let base = run(120)
        let kinds: [MobKind] = [.cow, .sheep, .pig, .chicken, .zombie, .skeleton, .spider, .rabbit, .wolf, .horse]
        var spawned = 0
        for i in 0..<150 {
            let x = Int(floor(pos.x)) + (i % 15) * 2 - 15, z = Int(floor(pos.z)) + (i / 15) * 3 - 15
            let y = game.mobs.grassSurface(world, x, z) ?? (world.topY(x, z) + 1)
            game.mobs.mobs.append(Mob(kinds[i % kinds.count], at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)))
            spawned += 1
        }
        let loaded = run(180)
        put("mobs.tick_base_ms", base, "mean,p95")
        put("mobs.tick_150_ms", loaded, "mean,p95,max")
        put("mobs.per_mob_us", max(0, loaded.mean - base.mean) * 1000 / Double(spawned))
        print("bench mobs: tick \(f(base.mean)) ms empty, \(f(loaded.mean)) ms with \(spawned) mobs (p95 \(f(loaded.p95)), max \(f(loaded.max))), \(game.mobs.mobs.count) alive")
    }

    // Ten power-4 explosions on the surface: main-thread cost of each blast, then how long the background
    // re-mesh of everything they touched takes, with ticks running.
    static func tnt(_ device: MTLDevice, _ seed: UInt64) {
        let (world, game, pos) = setup(device, seed, rd: 6)
        _ = world.loadSync(center: pos, radius: 6)
        var blast: [Double] = []
        let bx = Int(floor(pos.x)), bz = Int(floor(pos.z))
        for i in 0..<10 {
            let x = bx + (i % 5) * 7 - 14, z = bz + (i / 5) * 9 - 4
            let c = V3(Float(x) + 0.5, Float(world.topY(x, z)) + 0.5, Float(z) + 0.5)
            let a = now
            Explosion.explode(at: c, power: 4, game: game)
            blast.append((now - a) * 1000)
        }
        let dt = 1.0 / 60
        var ticks: [Double] = []
        let s = now
        repeat {
            game.player.pos = pos
            let a = now
            game.tick(dt)
            ticks.append((now - a) * 1000)
            usleep(4000)
        } while (world.pendingJobs > 0 || unmeshed(world, pos)) && now - s < 15
        let settle = now - s
        let b = dist(blast), t = dist(ticks)
        put("tnt.blast_ms", b, "mean,max")
        put("tnt.tick_ms", t, "p50,p95,max")
        put("tnt.remesh_s", settle)
        print("bench tnt: blast mean \(f(b.mean)) ms max \(f(b.max)) ms (main thread) | re-mesh done in \(f(settle)) s, tick p95 \(f(t.p95)) max \(f(t.max)) ms")
    }

    // 16 water springs on the terrain around the player, 6 s of ticks: fluid spreading and re-mesh load.
    static func fluids(_ device: MTLDevice, _ seed: UInt64) {
        let (world, game, pos) = setup(device, seed, rd: 6)
        _ = world.loadSync(center: pos, radius: 6)
        let bx = Int(floor(pos.x)), bz = Int(floor(pos.z))
        for i in 0..<16 {
            let x = bx + (i % 4) * 6 - 9, z = bz + (i / 4) * 6 - 9
            world.setBlock(x, world.topY(x, z) + 1, z, WATER)
        }
        let dt = 1.0 / 60
        var ticks: [Double] = []
        let s0 = world.perf
        let start = now
        for i in 0..<360 {
            game.player.pos = pos
            let a = now
            game.tick(dt)
            ticks.append((now - a) * 1000)
            let slack = start + Double(i + 1) * dt - now
            if slack > 0 { usleep(useconds_t(slack * 1e6)) }
        }
        let s1 = world.perf
        let t = dist(ticks)
        let sections = Double(s1.meshSections - s0.meshSections)
        put("fluids.tick_ms", t, "p50,p95,max")
        put("fluids.remeshed_sections", sections)
        put("fluids.pending", Double(world.fluidPending.count))
        print("bench fluids: tick p50 \(f(t.p50)) p95 \(f(t.p95)) max \(f(t.max)) ms, \(Int(sections)) sections re-meshed in 6 s, \(world.fluidPending.count) cells still pending")
    }

    static func save(_ device: MTLDevice, _ seed: UInt64) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("blocksmith-bench-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sm = SaveManager(dir: dir)
        let world = World(seed: seed, device: device, save: sm)
        let pos = V3(8.5, 100, 8.5)
        _ = world.loadSync(center: pos, radius: 5)
        let keys = Array(world.chunks.keys)
        for k in keys { world.chunks[k]?.modified = true }
        var a = now
        world.saveAll()
        let tMain = now - a                                  // main-thread part (writes are queued)
        SaveIO.flush()
        let tSave = now - a
        a = now
        world.saveAll()                                      // nothing changed: should skip every chunk
        SaveIO.flush()
        let tResave = now - a
        var bytes = 0
        for k in keys { bytes += (try? FileManager.default.attributesOfItem(atPath: sm.chunkURL(k).path)[.size] as? Int) ?? 0 }
        a = now
        var ok = 0
        for k in keys where sm.loadChunk(k) != nil { ok += 1 }
        let tLoad = now - a
        let n = Double(max(1, keys.count))
        put("save.chunk_ms", tSave * 1000 / n)
        put("save.main_thread_ms", tMain * 1000)
        put("save.unchanged_resave_ms", tResave * 1000)
        put("save.load_chunk_ms", tLoad * 1000 / n)
        put("save.chunk_kb", Double(bytes) / 1024 / n)
        print("bench save: \(keys.count) chunks, save \(f(tSave * 1000 / n)) ms/chunk (main thread \(f(tMain * 1000, 1)) ms total, unchanged re-save \(f(tResave * 1000, 1)) ms), load \(f(tLoad * 1000 / n)) ms/chunk (\(ok) ok), \(f(Double(bytes) / 1024 / n, 1)) KB/chunk")
    }

    static func flight(_ device: MTLDevice, _ seed: UInt64, rd: Int, seconds: Double, speed: Float) {
        let (world, game, p0) = setup(device, seed, rd: rd)
        var pos = p0
        func alt(_ x: Float, _ z: Float) -> Float { Float(max(world.gen.column(Int(floor(x)), Int(floor(z))).height, SEA) + 24) }
        pos.y = alt(pos.x, pos.z)
        game.player.pos = pos
        game.player.yaw = -.pi / 2                                  // looking along +x, the flight direction
        game.player.pitch = -8 * .pi / 180
        let a = now
        _ = world.loadSync(center: pos, radius: rd)
        let preload = now - a
        guard let r = try? Renderer(device: device, game: game, colorFormat: .bgra8Unorm),
              let target = OffscreenTarget(device, 1280, 800) else { return }
        for _ in 0..<3 { _ = r.benchFrame(target) }
        let dt = 1.0 / 60
        let frames = Int(seconds / dt)
        var tick: [Double] = [], enc: [Double] = [], gpu: [Double] = [], upd: [Double] = [], est: [Double] = [], cov: [Double] = [], cull: [Double] = []
        tick.reserveCapacity(frames); enc.reserveCapacity(frames); gpu.reserveCapacity(frames); upd.reserveCapacity(frames); est.reserveCapacity(frames)
        var peak = residentMB()
        let s0 = world.perf
        let start = now
        for i in 0..<frames {
            pos.x += speed * Float(dt)
            let want = alt(pos.x, pos.z)
            pos.y = want > pos.y ? want : max(want, pos.y - 6 * Float(dt))
            game.player.pos = pos
            game.player.vel = .zero
            let b = now
            game.tick(dt)
            let tk = now - b
            let (e, g) = r.benchFrame(target)
            tick.append(tk * 1000); enc.append(e * 1000); gpu.append(g * 1000); cull.append(r.cullSeconds * 1000)
            upd.append(world.perf.updateSeconds * 1000)
            est.append(max(tk + e, g) * 1000)
            if i % 15 == 0 { cov.append(coverage(world, pos)); peak = max(peak, residentMB()) }
            let slack = start + Double(i + 1) * dt - now
            if slack > 0 { usleep(useconds_t(slack * 1e6)) }
        }
        let wall = now - start
        let s1 = world.perf
        let k = "flight\(rd)"
        let fe = dist(est), ft = dist(tick), fg = dist(gpu), fu = dist(upd), fc = dist(enc)
        let hitches = est.filter { $0 > 1000.0 / 60 * 1.5 }.count
        let covMin = cov.min() ?? 0, covMean = cov.isEmpty ? 0 : cov.reduce(0, +) / Double(cov.count)
        let genRate = Double(s1.genChunks - s0.genChunks) / wall
        let meshRate = Double(s1.meshSections - s0.meshSections) / wall
        let genMs = Double(s1.genChunks - s0.genChunks) > 0 ? (s1.genSeconds - s0.genSeconds) * 1000 / Double(s1.genChunks - s0.genChunks) : 0
        let meshUs = Double(s1.meshSections - s0.meshSections) > 0 ? (s1.meshSeconds - s0.meshSeconds) * 1e6 / Double(s1.meshSections - s0.meshSections) : 0
        put("\(k).preload_ms", preload * 1000)
        put("\(k).frame_ms", fe, "p50,p95,p99,max")
        put("\(k).tick_ms", ft, "p50,p95,max")
        put("\(k).update_ms", fu, "p50,p95,max")
        put("\(k).encode_ms", fc, "p50,p95")
        put("\(k).gpu_ms", fg, "p50,p95")
        put("\(k).hitches", Double(hitches))
        put("\(k).coverage_min", covMin)
        put("\(k).coverage_mean", covMean)
        put("\(k).gen_chunks_per_s", genRate)
        put("\(k).mesh_sections_per_s", meshRate)
        put("\(k).worker_gen_ms", genMs)
        put("\(k).worker_mesh_us", meshUs)
        put("\(k).realtime", Double(frames) * dt / wall)
        put("\(k).chunks", Double(world.chunks.count))
        put("\(k).draw_calls", Double(r.drawCalls))
        put("\(k).cull_walked_sections", Double(r.bfsVisited))
        put("\(k).cull_ms", dist(cull), "p50,p95")
        put("\(k).drawn_kquads", Double(r.drawnQuads) / 1000)
        put("\(k).chunk_mb", chunkMB(world))
        put("\(k).mesh_mb", meshMB(world))
        put("\(k).slab_mb", Double(MeshArena.shared.slabBytes) / 1_048_576)
        put("\(k).arena_free_mb", Double(MeshArena.shared.freeBytes) / 1_048_576)
        put("\(k).resident_peak_mb", peak)
        print("bench \(k): frame p50 \(f(fe.p50)) p95 \(f(fe.p95)) p99 \(f(fe.p99)) max \(f(fe.max)) ms, \(hitches) hitches >25 ms | tick p95 \(f(ft.p95)) (update p95 \(f(fu.p95)), max \(f(fu.max))) encode p95 \(f(fc.p95)) GPU p95 \(f(fg.p95)) ms")
        print("bench \(k): coverage min \(f(covMin * 100, 0))% mean \(f(covMean * 100, 0))% | gen \(f(genRate, 0)) chunks/s (\(f(genMs, 1)) ms each on a worker) mesh \(f(meshRate, 0)) sections/s (\(f(meshUs, 0)) us each) | realtime \(f(Double(frames) * dt / wall))x")
        print("bench \(k): \(world.chunks.count) chunks, chunk data \(f(chunkMB(world), 0)) MB, meshes \(f(meshMB(world), 0)) MB (slabs \(f(Double(MeshArena.shared.slabBytes) / 1_048_576, 0)) MB), resident peak \(f(peak, 0)) MB, preload \(f(preload * 1000, 0)) ms")
    }
}

// Offscreen colour + depth target for benchmark frames (no readback).
final class OffscreenTarget {
    let rpd = MTLRenderPassDescriptor()
    let w: Int, h: Int
    init?(_ device: MTLDevice, _ w: Int, _ h: Int) {
        self.w = w; self.h = h
        let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        cd.usage = [.renderTarget]; cd.storageMode = .private
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        dd.usage = .renderTarget; dd.storageMode = .private
        guard let color = device.makeTexture(descriptor: cd), let depth = device.makeTexture(descriptor: dd) else { return nil }
        rpd.colorAttachments[0].texture = color
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.depthAttachment.texture = depth
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1
    }
}

extension Renderer {
    // One frame into an offscreen target: CPU encode time and GPU execution time (seconds).
    func benchFrame(_ t: OffscreenTarget) -> (encode: Double, gpu: Double) {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: t.rpd) else { return (0, 0) }
        encode(enc, width: Float(t.w), height: Float(t.h))
        enc.endEncoding()
        cmd.commit()
        let t1 = CFAbsoluteTimeGetCurrent()
        cmd.waitUntilCompleted()
        return (t1 - t0, max(0, cmd.gpuEndTime - cmd.gpuStartTime))
    }
}
