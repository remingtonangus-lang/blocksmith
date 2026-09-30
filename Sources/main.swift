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
        }
        if CommandLine.arguments.contains("--debug") {
            game.showDebug = true
            game.onToast?("Grass Block")
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
        if CommandLine.arguments.contains("--mobs") {
            // A few animals standing in front of the camera, legs mid-stride.
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw)), r = V3(cosf(game.player.yaw), 0, -sinf(game.player.yaw))
            let spots: [(MobKind, Float, Float)] = [(.cow, 6, -2.5), (.sheep, 6, 1.5), (.chicken, 4, 0), (.cow, 10, 3), (.sheep, 9, -4), (.chicken, 5, 2.5)]
            for (i, spot) in spots.enumerated() {
                let p = pos + f * spot.1 + r * spot.2
                let x = Int(floor(p.x)), z = Int(floor(p.z))
                let y = game.mobs.grassSurface(world, x, z) ?? (world.gen.column(x, z).height + 1)
                let m = Mob(spot.0, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
                m.yaw = game.player.yaw + .pi + Float(i) * 0.9
                m.walkPhase = Float(i) * 0.8
                m.walkAmount = 1
                game.mobs.mobs.append(m)
            }
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
        for (_, c) in world.chunks { for sec in c.sections { quads += sec.opaqueQuads; water += sec.transQuads } }

        if let simSeconds = Double(arg("--sim") ?? "") {
            // Gameplay smoke test: scripted input through the real Game.tick (survival, walking, jumping,
            // breaking/placing, inventory, flowing water, mobs), timing the main-thread tick.
            game.player.flying = false
            game.paused = false
            game.survival = true
            let wx = Int(floor(pos.x)) + 3, wz = Int(floor(pos.z)) - 4
            world.setBlock(wx, world.gen.column(wx, wz).height + 1, wz, WATER)
            for k in 0..<5 {
                let kind = MobKind.allCases[k % 3]
                let x = Int(floor(pos.x)) + k * 2 - 4, z = Int(floor(pos.z)) - 6
                let y = game.mobs.grassSurface(world, x, z) ?? (world.gen.column(x, z).height + 1)
                game.mobs.mobs.append(Mob(kind, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)))
            }
            let dt = 1.0 / 60
            var worst = 0.0, total = 0.0
            let frames = Int(simSeconds / dt)
            let inp = game.input
            for f in 0..<frames {
                inp.keys = [Key.w]
                if f % 100 == 0 { inp.keys.insert(Key.space); inp.pressed.insert(Key.space) }
                if f % 30 == 10 { inp.leftClicked = true }
                if f % 45 == 20 { inp.rightClicked = true }
                if f == 300 { inp.pressed.insert(Key.e) }
                if f > 300 && f < 360 && f % 10 == 0 { inp.pressed.insert(Key.arrowRight); inp.pressed.insert(Key.arrowDown) }
                if f == 350 { inp.pressed.insert(Key.enter) }
                if f == 380 { inp.pressed.insert(Key.e) }
                game.player.yaw += 0.003
                let t0 = CFAbsoluteTimeGetCurrent()
                game.tick(dt)
                let el = CFAbsoluteTimeGetCurrent() - t0
                total += el
                worst = max(worst, el)
            }
            _ = world.loadSync(center: game.player.pos, radius: rd)
            let p = game.player.pos
            print(String(format: "sim %.1f s: tick avg %.2f ms, worst %.2f ms | pos %.1f %.1f %.1f | health %ld hunger %ld | mobs %ld | fluid pending %ld | hotbar[0] %@",
                         simSeconds, total / Double(max(1, frames)) * 1000, worst * 1000, p.x, p.y, p.z, game.health, game.hunger,
                         game.mobs.mobs.count, world.fluidPending.count, Blocks.name(game.hotbar[0])))
        }

        // Mesh benchmark: re-mesh the section at the camera a few times on one thread.
        let key = ChunkKey(x: floorDiv(Int(pos.x), CS), z: floorDiv(Int(pos.z), CS))
        var n9: [[BlockID]] = [], h9: [[Int16]] = []
        for dz in -1...1 { for dx in -1...1 {
            let c = world.chunks[ChunkKey(x: key.x + dx, z: key.z + dz)]!
            n9.append(c.blocks); h9.append(c.height)
        } }
        let sy = max(0, min(NSEC - 1, (world.topY(Int(pos.x), Int(pos.z))) >> 4))
        let m0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<5 { _ = Mesher.buildSection(n9, h9, sy: sy) }
        let meshMs = (CFAbsoluteTimeGetCurrent() - m0) / 5 * 1000

        let renderer: Renderer
        do { renderer = try Renderer(device: device, game: game, colorFormat: .bgra8Unorm) }
        catch { print("renderer init failed: \(error)"); return 1 }
        game.target = world.raycast(game.player.eye, game.player.look, maxDist: 5)
        _ = renderer.renderToPNG(path: out, width: w, height: h) // warm-up (pipeline + residency)
        let gpu = renderer.renderToPNG(path: out, width: w, height: h)

        print(String(format: "seed %llu  pos %.1f %.1f %.1f  rd %ld  chunks %ld  (drawn %ld)", seed, pos.x, pos.y, pos.z, rd, world.chunks.count, renderer.drawnChunks))
        print(String(format: "gen %.0f ms  mesh(all, parallel) %.0f ms  mesh(1 section) %.2f ms  quads %ld opaque / %ld water", t.gen * 1000, t.mesh * 1000, meshMs, quads, water))
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
