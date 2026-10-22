import Foundation
import simd
import Metal
import CVulkan

// P400 (cold launch under 15 s, a store requirement): the headset's launch path, timed stage by stage on the host
// (QuestApp.load on its loading thread, then QuestApp.adoptLoaded on the frame thread), from the process start to the
// first world frame the player can move in, then on until the whole view is meshed (the far land filling in behind).
//   questcheck --launch DIR [--rd 24]           open (or, when DIR holds no world, create) the world saved in DIR
//   questcheck --launch-prepare DIR [--rd 24]   make a world in DIR as he would leave it: the view filled, a dug-out
//                                               pit, a built hut and a carved tunnel by the spawn, saved and quit
// The texture cache lives beside the world (DIR/../cache), as QuestPaths.root/cache does on the headset: the first
// launch of a build paints the textures, the next ones read them. XR start-up and the GPU are headset-only.
enum QuestLaunch {
    static let seed: UInt64 = 13480747113613945685          // (his seed: Stone Gulch's world)

    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    // Seconds since this process started (/proc: its start in clock ticks since boot, against the uptime).
    static func sinceProcessStart() -> Double {
        guard let st = try? String(contentsOfFile: "/proc/self/stat", encoding: .utf8),
              let up = try? String(contentsOfFile: "/proc/uptime", encoding: .utf8),
              let close = st.lastIndex(of: ")") else { return 0 }
        let f = st[st.index(after: close)...].split(separator: " ")
        guard f.count > 19, let ticks = Double(f[19]), let uptime = Double(up.split(separator: " ").first ?? "") else { return 0 }
        return max(0, uptime - ticks / Double(sysconf(Int32(_SC_CLK_TCK))))
    }

    final class Clock {
        private var t = CFAbsoluteTimeGetCurrent()
        let start = CFAbsoluteTimeGetCurrent()
        var marks: [(String, Double)] = []
        func mark(_ name: String) {
            let n = CFAbsoluteTimeGetCurrent()
            marks.append((name, n - t)); t = n
            print(String(format: "launch: %@ %.2f s", name, marks.last!.1))
        }
        var total: Double { CFAbsoluteTimeGetCurrent() - start }
    }

    static func run(ctx: VkContext) -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        World.fluidSeconds = 0.002; World.handoverSeconds = 0.0015; World.lodNear = 99; World.leafNear = 99   // (QuestApp)
        SceneRenderer.skipGPU = true
        RandomTickRng.profile = true
        World.resultsProfile = true
        let rd = Int(arg("--rd") ?? "") ?? 24
        let prepare = arg("--launch-prepare")
        guard let dirPath = prepare ?? arg("--launch") else { return 1 }
        let dir = URL(fileURLWithPath: dirPath, isDirectory: true)
        let cacheDir = dir.deletingLastPathComponent().appendingPathComponent("cache").path
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let before = sinceProcessStart()
        let clock = Clock()
        print(String(format: "launch: process start to here %.2f s (questcheck's own start-up, not the app's)", before))

        // QuestApp.load (the loading thread)
        TextureGen.registerAll()
        let tex = TextureCache.mipChain(dir: cacheDir)
        clock.mark("textures (painted, or read from the cache)")
        let save = SaveManager(dir: dir)
        let meta = save.loadMeta()
        let world = World(seed: meta?.seed ?? seed, device: sharedSystemDevice, save: save)
        world.renderDistance = rd
        let game = Game(world: world, save: save, persistent: true)
        Game.oceanSwellDrawn = true
        var req = WorldRequest()
        req.seed = seed; req.smooth = true; req.survival = true
        req.setUp(game, meta: meta)
        game.world.renderDistance = rd
        game.world.activeDistance = Game.savedActiveDistance
        game.rdGovernor = RenderDistanceGovernor(chosen: game.world.activeDistance)
        clock.mark(meta == nil ? "new world made (spawn found, meta saved)" : "saved world opened")
        let near = game.world.loadSync(center: game.player.pos, radius: min(3, game.world.renderDistance))
        clock.mark(String(format: "near ring (radius 3: %d chunks; gen %.2f s, mesh %.2f s)", game.world.chunks.count, near.gen, near.mesh))
        HorizonRing.shared.request(game, eye: game.player.eye)
        FarRing.shared.request(game, eye: game.player.eye)
        clock.mark("horizon and middle rings")
        QuestWarmup.run()
        QuestWarmup.world(game)
        clock.mark("warm-up tables, rails and bases")

        // QuestApp.adoptLoaded (the frame thread)
        let scene: SceneRenderer, wr: WorldRenderer
        do {
            scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
            try scene.uploadTextures(pregenerated: tex)
        } catch { print("FAIL launch: renderer \(error)"); return 1 }
        clock.mark("renderer and textures uploaded")
        let panel = try? HudPanel(scene: scene, width: QuestControls.panelW, height: QuestControls.panelH)
        clock.mark("HUD panel")
        wr = WorldRenderer(scene: scene, game: game)
        wr.landmarkHost = Renderer(game: game)
        game.paused = false
        game.hideHUD = false
        game.sound = SoundEngine()
        clock.mark("game, renderer, sound")

        let size = 48
        guard let img = try? VkImg(ctx, width: size, height: size, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                                   usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue),
              let target = try? scene.makeTarget(image: img.image, width: size, height: size) else { print("FAIL launch: target"); return 1 }
        let t = tanf(52 * .pi / 180)
        let far = Float(rd * 16 + 96)
        let proj = XRMath.projection(tanLeft: -t, tanRight: t, tanUp: t * 0.95, tanDown: -t * 0.95, near: 0.05, far: far)
        var yaw: Float = 0
        var lastTick = 0.0, lastRecord = 0.0
        func frame() -> Double {
            let a = CFAbsoluteTimeGetCurrent()
            game.tick(1.0 / 72)
            lastTick = (CFAbsoluteTimeGetCurrent() - a) * 1000
            let head = simd_quatf(angle: yaw, axis: V3(0, 1, 0))
            let vps = ([-0.032, 0.032] as [Float]).map { proj * XRMath.inversePose(head, head.act(V3($0, 0, 0))) }
            let cam = EyeCamera(center: game.player.eye, viewProj: vps, cullViewProj: proj * XRMath.inversePose(head, V3(0, 0, 0)), yaw: yaw, pitch: 0, far: far)
            let s = scene.beginFrame()
            wr.record(s, target, cam)
            vkCmdEndRenderPass(s.cmd)
            try? scene.submit(s)
            let total = (CFAbsoluteTimeGetCurrent() - a) * 1000
            lastRecord = total - lastTick
            return total
        }
        _ = frame()
        clock.mark("first world frame")
        let interactive = clock.total
        print(String(format: "launch: FIRST INTERACTIVE FRAME %.2f s after the load began (%@ world, view %d)", interactive,
                     meta == nil ? "new" : "saved", rd))

        // The far land filling in: frames on until every chunk in the view is meshed (the player standing, looking round).
        var want = 0
        for dz in -rd...rd { for dx in -rd...rd where game.world.inMeshRadius(dx, dz) { want += 1 } }
        let pcx = floorDiv(Int(floor(game.player.pos.x)), CS), pcz = floorDiv(Int(floor(game.player.pos.z)), CS)
        func meshed() -> Int {
            var n = 0
            for dz in -rd...rd { for dx in -rd...rd where game.world.inMeshRadius(dx, dz) {
                if let c = game.world.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)], c.meshedOnce { n += 1 }
            } }
            return n
        }
        if let mc = game.world.meshCache {
            var band = 0, have = 0
            for dz in -rd...rd { for dx in -rd...rd where game.world.inMeshRadius(dx, dz) && game.world.inShellBand(dx, dz) {
                band += 1; if mc.has(ChunkKey(x: pcx + dx, z: pcz + dz)) { have += 1 }
            } }
            print("launch: mesh cache: \(mc.count) files; shell band (past \(game.world.keepDataDistance) chunks, active \(game.world.activeDistance)): \(band) chunks, \(have) of them cached")
        }
        var worst = 0.0, slow = 0, frames = 0
        var worstTick = 0.0, worstRecord = 0.0, slowTick = 0, slowRecord = 0, worstTickWhy = "", worstRecordWhy = ""
        var worstTickAt = 0.0, worstRecordAt = 0.0
        var slowWhy: [String: Int] = [:]                               // (the slowest stage of each slow tick)
        _ = wr.takeStages()
        var halfAt = 0.0
        let fill0 = CFAbsoluteTimeGetCurrent()
        var done = 0
        while CFAbsoluteTimeGetCurrent() - fill0 < 300 {
            yaw += 2 * .pi / 720                                       // (a slow look round: 10 s a turn)
            let ms = frame()
            frames += 1; worst = max(worst, ms); if ms > 13.9 { slow += 1 }
            if lastTick > worstTick { worstTick = lastTick; worstTickWhy = TickProf.summary(); worstTickAt = CFAbsoluteTimeGetCurrent() - fill0 }
            let st = wr.takeStages()                                  // (this frame's record stages)
            if lastRecord > worstRecord { worstRecord = lastRecord; worstRecordWhy = st; worstRecordAt = CFAbsoluteTimeGetCurrent() - fill0 }
            if lastTick > 13.9 { slowTick += 1; slowWhy[TickProf.top().0.description, default: 0] += 1 }; if lastRecord > 13.9 { slowRecord += 1 }
            if frames % 36 == 0 {
                done = meshed()
                if halfAt == 0 && done * 2 >= want { halfAt = CFAbsoluteTimeGetCurrent() - fill0 }
                if done >= want && game.world.pendingJobs == 0 { break }
            }
        }
        let fill = CFAbsoluteTimeGetCurrent() - fill0
        print(String(format: "launch: view %d filled (%d of %d chunks meshed) %.1f s after the first frame (half in %.1f s); %d frames, worst %.1f ms (tick + record), %d over 13.9 ms; %d chunks from the mesh cache",
                     rd, done, want, fill, halfAt, frames, worst, slow, World.fromCache))
        if let mc = game.world.meshCache { print("launch: mesh cache reads \(mc.reads), refused \(mc.refused)") }
        print(String(format: "launch: while filling: worst tick %.1f ms (%d over 13.9), worst record %.1f ms (%d over 13.9)", worstTick, slowTick, worstRecord, slowRecord))
        print(String(format: "launch: worst tick's stages (%.1f s in): ", worstTickAt) + worstTickWhy)
        print(String(format: "launch: worst record's stages (%.1f s in): ", worstRecordAt) + worstRecordWhy)
        print(String(format: "launch: slowest random tick %.1f ms (%@)", RandomTickRng.worstMs, RandomTickRng.worstWhat))
        print("launch: slow ticks by their slowest stage: " + slowWhy.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        print(String(format: "launch: slowest result handed over %.1f ms (%@); mesh slabs: %d new, worst %.1f ms, %.0f ms in all",
                     World.resultsWorstMs, World.resultsWorst, MeshArena.shared.slabCount, MeshArena.shared.slabMsWorst, MeshArena.shared.slabMsTotal))
        print("launch: stages " + clock.marks.map { String(format: "%@ %.2f", $0.0, $0.1) }.joined(separator: "; "))
        print(String(format: "launch: resident %.0f MB", QuestPerf.rssMB()))

        if prepare != nil {
            // His edits by the spawn: a pit dug, a hut built, a tunnel carved; then saved and quit as the app does.
            let p = game.player.pos
            let gx = Int(floor(p.x)) + 6, gz = Int(floor(p.z)) + 6
            let top = Int(game.world.chunkAt(gx, gz)?.height[mod(gx, CS) + mod(gz, CS) * CS] ?? Int16(p.y))
            if game.world.fieldTerrain {
                for k in 0..<6 { _ = game.world.fieldSphere(V3(Float(gx) + Float(k), Float(top) - 1, Float(gz)), radius: 2.5, carve: true, material: nil, remesh: true) }
                for k in 0..<12 { _ = game.world.fieldSphere(V3(Float(gx) - 8, Float(top) - 4, Float(gz) - Float(k)), radius: 1.6, carve: true, material: nil, remesh: true) }
            }
            let plank = Blocks.id("oak_planks")
            for y in 0..<4 { for x in 0..<5 { for z in 0..<5 where x == 0 || x == 4 || z == 0 || z == 4 || y == 3 {
                game.world.setBlock(gx + 10 + x, top + 1 + y, gz + z, plank)
            } } }
            for _ in 0..<72 { _ = frame() }
            let a = CFAbsoluteTimeGetCurrent()
            game.saveNow()
            game.world.saveMeshCache()
            SaveIO.flush()
            game.world.meshCache?.flush()
            print(String(format: "launch: saved and quit in %.2f s (%@)", CFAbsoluteTimeGetCurrent() - a, dir.path))
        }
        withExtendedLifetime((img, target, panel)) {}
        scene.waitIdle()
        return 0
    }
}
