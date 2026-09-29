import AppKit
import Metal

// Headless test harness. Renders one frame offscreen to a PNG and prints timings, e.g.
//   Blocksmith --snapshot /tmp/shot.png --seed 42 --yaw 45 --pitch -20 --time 0.25 --up 30 --rd 8
// Angles in degrees; --time is a day fraction (0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight);
// --x/--z pick a world position (default: spawn); --up raises the camera above the terrain;
// --find <biome> (forest, desert, snowy, ...) spirals out from spawn to the middle of that biome.
enum Snapshot {
    static func findBiome(_ gen: WorldGen, _ want: String) -> V3? {
        var x = 0, z = 0, dx = 0, dz = -1
        for _ in 0..<40000 {
            let wx = x * 16 + 8, wz = z * 16 + 8
            var ok = true
            for (ox, oz) in [(0, 0), (24, 0), (-24, 0), (0, 24), (0, -24)] where "\(gen.column(wx + ox, wz + oz).biome)" != want {
                ok = false
                break
            }
            if ok {
                let h = gen.column(wx, wz).height
                return V3(Float(wx) + 0.5, Float(max(h, SEA) + 1), Float(wz) + 0.5)
            }
            if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
            x += dx; z += dz
        }
        print("biome \(want) not found")
        return nil
    }

    static func run(_ out: String) -> Int32 {
        guard let device = MTLCreateSystemDefaultDevice() else { print("no Metal device"); return 1 }
        let seed = UInt64(arg("--seed") ?? "") ?? 12345
        let rd = Int(arg("--rd") ?? "") ?? 8
        let w = Int(arg("--w") ?? "") ?? 1280
        let h = Int(arg("--h") ?? "") ?? 800
        let world = World(seed: seed, device: device, save: nil)
        world.renderDistance = rd
        let game = Game(world: world, save: nil, persistent: false)
        var pos = game.findSpawn()
        if let x = Float(arg("--x") ?? ""), let z = Float(arg("--z") ?? "") {
            let hgt = world.gen.column(Int(floor(x)), Int(floor(z))).height
            pos = V3(x, Float(max(hgt, SEA) + 1), z)
        }
        if let want = arg("--find"), let p = findBiome(world.gen, want) { pos = p }
        pos.y += Float(arg("--up") ?? "") ?? 0
        game.player.pos = pos
        game.player.yaw = (Float(arg("--yaw") ?? "") ?? 30) * .pi / 180
        game.player.pitch = (Float(arg("--pitch") ?? "") ?? -15) * .pi / 180
        game.player.flying = true
        game.time = (Double(arg("--time") ?? "") ?? 0.2) * DAY_LENGTH
        if let s = arg("--slot") { game.selected = Int(s) ?? 0 }
        if let hp = arg("--survival") {
            game.survival = true
            game.health = Int(hp) ?? 20
            game.hunger = 13
            game.air = 7
            game.hotbar[8] = APPLE
        }
        if let c = arg("--inventory") { game.inventoryOpen = true; game.invCursor = Int(c) ?? 0 }

        var t = world.loadSync(center: pos, radius: rd)
        if CommandLine.arguments.contains("--flood") {
            // Fluid test: a spring on the ground and one hanging in the air, then simulate 12 s of flow.
            let bx = Int(floor(pos.x)), bz = Int(floor(pos.z)) - 8
            let h1 = world.gen.column(bx, bz).height
            world.setBlock(bx, h1 + 1, bz, WATER)
            let h2 = world.gen.column(bx + 6, bz + 2).height
            world.setBlock(bx + 6, h2 + 5, bz + 2, WATER)
            for _ in 0..<60 { world.fluidTick() }
            let t2 = world.loadSync(center: pos, radius: rd)
            t.mesh += t2.mesh
            print("fluid cells pending after 60 ticks: \(world.fluidPending.count)")
        }
        if CommandLine.arguments.contains("--torches") {
            // Light test: a ring of torches plus a lamp around the camera, then remesh what changed.
            for k in 0..<10 {
                let a = Float(k) / 10 * 2 * .pi
                let x = Int(floor(pos.x + cosf(a) * 7)), z = Int(floor(pos.z + sinf(a) * 7))
                let h = world.gen.column(x, z).height
                if h >= SEA { world.setBlock(x, h + 1, z, TORCH) }
            }
            let lx = Int(floor(pos.x)) + 3, lz = Int(floor(pos.z))
            world.setBlock(lx, world.gen.column(lx, lz).height + 1, lz, LAMP)
            let t2 = world.loadSync(center: pos, radius: rd)
            t.mesh += t2.mesh
        }
        var quads = 0, water = 0
        for (_, c) in world.chunks { quads += c.opaqueQuads; water += c.waterQuads }

        // Mesh benchmark: re-mesh the spawn chunk a few times on one thread.
        let key = ChunkKey(x: floorDiv(Int(pos.x), CS), z: floorDiv(Int(pos.z), CS))
        var n9: [[UInt8]] = []
        for dz in -1...1 { for dx in -1...1 { n9.append(world.chunks[ChunkKey(x: key.x + dx, z: key.z + dz)]!.blocks) } }
        let m0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<5 { _ = Mesher.build(n9) }
        let meshMs = (CFAbsoluteTimeGetCurrent() - m0) / 5 * 1000

        let renderer: Renderer
        do { renderer = try Renderer(device: device, game: game, colorFormat: .bgra8Unorm) }
        catch { print("renderer init failed: \(error)"); return 1 }
        game.target = world.raycast(game.player.eye, game.player.look, maxDist: 5)
        _ = renderer.renderToPNG(path: out, width: w, height: h) // warm-up (pipeline + residency)
        let gpu = renderer.renderToPNG(path: out, width: w, height: h)

        print(String(format: "seed %llu  pos %.1f %.1f %.1f  rd %ld  chunks %ld  (drawn %ld)", seed, pos.x, pos.y, pos.z, rd, world.chunks.count, renderer.drawnChunks))
        print(String(format: "gen %.0f ms  mesh(all, parallel) %.0f ms  mesh(1 chunk) %.2f ms  quads %ld opaque / %ld water", t.gen * 1000, t.mesh * 1000, meshMs, quads, water))
        print(String(format: "frame (encode+GPU, offscreen) %.2f ms  biome %@", gpu * 1000, "\(world.gen.column(Int(pos.x), Int(pos.z)).biome)"))
        print("wrote \(out)")
        return 0
    }
}

if let dir = arg("--sounds") {
    // Synth check: render every sound effect (variant 0) to a WAV file.
    let t0 = CFAbsoluteTimeGetCurrent()
    let bank = SoundBank()
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var total = 0
    for s in SoundBank.allSounds {
        let c = bank.clip(s, variant: 0)
        total += c.count
        let name = String("\(s)".replacingOccurrences(of: "Blocksmith.SoundMat.", with: "").map { $0.isLetter || $0.isNumber ? $0 : "_" })
        SoundBank.writeWAV(c, to: "\(dir)/\(name).wav")
    }
    print(String(format: "synthesized %ld sounds (%.1f s of audio) in %.0f ms", SoundBank.allSounds.count, Double(total) / SoundBank.rate, (CFAbsoluteTimeGetCurrent() - t0) * 1000))
    exit(0)
}

if let out = arg("--snapshot") {
    exit(Snapshot.run(out))
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
