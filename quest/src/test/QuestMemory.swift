import Foundation
import simd
import Metal
import CVulkan

// P401 (memory under the Quest 3 limit, a store requirement): what the headset's process holds at view 24, on the
// host, loaded as the headset loads it (QuestLaunch's path: a saved Polygons world, the active distance, shells and
// the disk mesh cache, the renderer with its textures, the sound engine), with the GPU's allocations in this process
// (lavapipe), as on the Quest's shared memory.
//   questcheck --memscene NAME DIR [--rd 24] [--seconds 60]   NAME: gulch (Stone Gulch), capital (the capital city
//                                                              nearest it), vault (the Ash Vault's biggest battle);
//                                                              the view filled, then 60 s standing and looking round
//   questcheck --memsim DIR [--minutes 20]                     20 minutes of play from the spawn (walking on and
//                                                              turning, digging and building, autosaves), resident
//                                                              memory each minute (a leak shows as growth)
// Peak resident memory is the kernel's high-water mark (VmHWM). Meta checks an app's PSS against its limit; for one
// process with nothing shared that is its resident set.
enum QuestMemory {
    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }
    // VmRSS / VmHWM / RssAnon / RssFile from /proc/self/status, in MB.
    static func status(_ key: String) -> Double {
        guard let t = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8),
              let l = t.split(separator: "\n").first(where: { $0.hasPrefix(key + ":") }) else { return 0 }
        return (Double(l.split(separator: " ").dropFirst().first ?? "0") ?? 0) / 1024
    }
    static func mb(_ n: Int) -> String { String(format: "%.0f", Double(n) / 1_048_576) }

    // The parts the game can count, MB.
    static func breakdown(_ g: Game) -> String {
        let w = g.world
        var blocks = 0, field = 0, light = 0, tint = 0, shells = 0, groundTris = 0
        for c in w.chunks.values {
            if c.hollow { shells += 1 }
            for s in c.sections { groundTris += s.ground?.bytes ?? 0 }
            blocks += c.blocks.storedBytes.blocks; field += c.blocks.storedBytes.field
            for l in c.light { light += l?.count ?? 0 }
            tint += c.tint.count * 4 + c.height.count * 2
        }
        var tex = 0, sz = TextureGen.size
        while sz >= 1 { tex += sz * sz * 4; sz /= 2 }
        tex *= Tex.count
        let audio = (g.sound?.bank.cachedBytes ?? 0) + (g.sound?.clipBytes ?? 0)
        let meshes = MeshArena.shared.slabBytes, free = MeshArena.shared.freeBytes, tints = MeshArena.tints.slabBytes
        let counted = blocks + field + light + tint + tex + audio + meshes + tints + groundTris
        return "resident \(String(format: "%.0f", status("VmRSS"))) MB (peak \(String(format: "%.0f", status("VmHWM"))) MB; anonymous \(String(format: "%.0f", status("RssAnon"))), files \(String(format: "%.0f", status("RssFile"))), shared (the GPU's buffers and images here) \(String(format: "%.0f", status("RssShmem")))); "
            + "\(w.fieldTerrain ? "Polygons" : "block") world, \(w.chunks.count) chunks (\(shells) shells, active \(w.activeDistance)): block layer \(mb(blocks)), field \(mb(field)), light \(mb(light)), heights+tints \(mb(tint)), ground triangles kept for bodies \(mb(groundTris)); "
            + "meshes \(mb(meshes)) (free in the slabs \(mb(free))), chunk tint slabs \(mb(tints)); textures \(mb(tex)) (\(Tex.count) layers at \(TextureGen.size) px); "
            + "audio \(mb(audio)) (\(g.sound?.clipCount ?? 0) sounds held); counted \(mb(counted)); \(g.mobs.mobs.count) mobs, \(g.drops.items.count) items; "
    }

    struct Frames {
        let game: Game, wr: WorldRenderer, scene: SceneRenderer, target: RenderTarget, proj: simd_float4x4, far: Float
        var yaw: Float = 0
        mutating func frame() {
            game.tick(1.0 / 72)
            let head = simd_quatf(angle: yaw, axis: V3(0, 1, 0))
            let vps = ([-0.032, 0.032] as [Float]).map { proj * XRMath.inversePose(head, head.act(V3($0, 0, 0))) }
            let cam = EyeCamera(center: game.player.eye, viewProj: vps, cullViewProj: proj * XRMath.inversePose(head, V3(0, 0, 0)), yaw: yaw, pitch: 0, far: far)
            let s = scene.beginFrame()
            wr.record(s, target, cam)
            vkCmdEndRenderPass(s.cmd)
            try? scene.submit(s)
        }
    }

    static func run(ctx: VkContext) -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        World.fluidSeconds = 0.002; World.handoverSeconds = 0.0015; World.lodNear = 99; World.leafNear = 99   // (QuestApp)
        SceneRenderer.skipGPU = true
        let rd = Int(arg("--rd") ?? "") ?? 24
        let sceneName = arg("--memscene"), simDir = arg("--memsim")
        var sceneDir: String? = nil
        if let i = CommandLine.arguments.firstIndex(of: "--memscene"), i + 2 < CommandLine.arguments.count { sceneDir = CommandLine.arguments[i + 2] }
        guard let dirPath = simDir ?? sceneDir else { print("FAIL memory: --memscene NAME DIR or --memsim DIR"); return 1 }
        let dir = URL(fileURLWithPath: dirPath, isDirectory: true)
        print("memory: start, resident \(String(format: "%.0f", status("VmRSS"))) MB")

        // QuestApp.load (the textures read from the cache beside the world, or painted and cached, and held until the
        // renderer uploads them, as the app does)
        TextureGen.registerAll()
        let cacheDir = dir.deletingLastPathComponent().appendingPathComponent("cache").path
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        var tex: [[UInt8]] = TextureCache.mipChain(dir: cacheDir)
        print("memory: textures read or painted, resident \(String(format: "%.0f", status("VmRSS"))) MB")
        let save = SaveManager(dir: dir)
        let meta = save.loadMeta()
        let world = World(seed: meta?.seed ?? QuestLaunch.seed, device: sharedSystemDevice, save: save)
        world.renderDistance = rd
        let game = Game(world: world, save: save, persistent: true)
        Game.oceanSwellDrawn = true
        var req = WorldRequest()
        req.seed = QuestLaunch.seed; req.smooth = true; req.survival = true
        req.setUp(game, meta: meta)
        game.world.renderDistance = rd
        game.world.activeDistance = Game.savedActiveDistance
        game.rdGovernor = RenderDistanceGovernor(chosen: game.world.activeDistance)
        // (the 20 minutes of play start at the world's spawn: a new world's first session)
        var place = sceneName == nil ? "the spawn" : "Stone Gulch"
        var stand = sceneName == nil ? game.player.pos : V3(6094.5, 88 + Float(YOFF), 688.5)
        if sceneName == "capital", let st = game.world.gen.structures?.nearest("capital_city", x: 6094, z: 688, maxRegions: 16) {
            stand = V3(Float((st.min.x + st.max.x) / 2) + 0.5, Float(YOFF + 120), Float((st.min.z + st.max.z) / 2) + 0.5)
            place = "the capital at \(Int(stand.x)), \(Int(stand.z))"
        }
        if sceneName == "vault" {
            stand = AshVaultGapTests.battleScene(game)
            game.world.renderDistance = rd
            _ = game.world.loadSync(center: stand, radius: rd)
            place = "the Ash Vault battle"
        } else {
            game.player.pos = stand
            game.player.flying = sceneName == "capital"
            _ = game.world.loadSync(center: stand, radius: 3)
            // (the rest of the view made and meshed at once on every core, as perfscenes does; streaming it in on a
            // survival world's frames took over 400 s by Stone Gulch's townsfolk)
            _ = game.world.loadSync(center: stand, radius: rd)
            if sceneName != "capital", let c = game.world.chunkAt(Int(stand.x), Int(stand.z)) {
                game.player.pos.y = Float(c.height[mod(Int(stand.x), CS) + mod(Int(stand.z), CS) * CS]) + 1
            }
        }
        HorizonRing.shared.request(game, eye: game.player.eye)
        FarRing.shared.request(game, eye: game.player.eye)
        print("memory: world loaded (\(place)), resident \(String(format: "%.0f", status("VmRSS"))) MB")

        // QuestApp.adoptLoaded
        let scene: SceneRenderer
        do {
            scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
            try scene.uploadTextures(pregenerated: tex)
        } catch { print("FAIL memory: renderer \(error)"); return 1 }
        tex = []
        print(String(format: "memory: textures uploaded, peak so far %.0f MB", status("VmHWM")))
        let panel = try? HudPanel(scene: scene, width: QuestControls.panelW, height: QuestControls.panelH)
        let wr = WorldRenderer(scene: scene, game: game)
        wr.landmarkHost = Renderer(game: game)
        game.paused = false
        game.hideHUD = false
        game.sound = SoundEngine()
        print("memory: renderer, textures and sound, resident \(String(format: "%.0f", status("VmRSS"))) MB")
        let size = 48
        guard let img = try? VkImg(ctx, width: size, height: size, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                                   usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue),
              let target = try? scene.makeTarget(image: img.image, width: size, height: size) else { print("FAIL memory: target"); return 1 }
        let t = tanf(52 * .pi / 180)
        let far = Float(rd * 16 + 96)
        var f = Frames(game: game, wr: wr, scene: scene, target: target,
                       proj: XRMath.projection(tanLeft: -t, tanRight: t, tanUp: t * 0.95, tanDown: -t * 0.95, near: 0.05, far: far), far: far)
        func hold() { if sceneName == "vault" { game.health = 20; game.alive = true; game.ashSpot = stand; game.ashSpotSeen = game.clock } }

        // The view filled (every chunk in it meshed), as in QuestLaunch.
        let pcx = floorDiv(Int(floor(game.player.pos.x)), CS), pcz = floorDiv(Int(floor(game.player.pos.z)), CS)
        func filled() -> Bool {
            for dz in -rd...rd { for dx in -rd...rd where game.world.inMeshRadius(dx, dz) {
                guard let c = game.world.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)], c.meshedOnce else { return false }
            } }
            return game.world.pendingJobs == 0
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        var n = 0
        while CFAbsoluteTimeGetCurrent() - t0 < 400 {
            hold(); f.yaw += 2 * .pi / 720; f.frame(); n += 1
            if n % 72 == 0 && filled() { break }
        }
        print(String(format: "memory: view %d filled in %.0f s", rd, CFAbsoluteTimeGetCurrent() - t0))
        print("memory: filled: " + breakdown(game))

        if sceneName != nil {
            let secs = Int(arg("--seconds") ?? "") ?? 60
            for _ in 0..<(secs * 72) { hold(); f.yaw += 2 * .pi / 720; f.frame() }
            print("memory: \(secs) s on: " + breakdown(game))
            print(String(format: "MEMSCENE %@ rd %d: peak %.0f MB, resident %.0f MB", sceneName!, rd, status("VmHWM"), status("VmRSS")))
        } else {
            // 20 minutes of play: walking on (the left stick forward, jumping when blocked) on a slow curve, so new land
            // streams in and old land leaves; a dig and a placed block every 10 s; the game's own autosave each minute.
            // A minute that got under 100 blocks (a cliff, the sea) ends with a step 200 blocks on.
            let minutes = Int(arg("--minutes") ?? "") ?? 20
            game.player.flying = false
            var samples: [Double] = []
            let dirt = Blocks.id("dirt")
            for m in 0..<minutes {
                let start = game.player.pos
                var last = game.player.pos
                for i in 0..<(60 * 72) {
                    var pad = PadSnapshot()
                    pad.ly = 1
                    if i % 72 == 0 { pad.a = simd_length(V2(game.player.pos.x - last.x, game.player.pos.z - last.z)) < 1; last = game.player.pos }
                    PadManager.shared.touch = pad
                    game.input.captured = true
                    game.player.yaw += 0.00005
                    f.yaw = game.player.yaw
                    if game.health < 10 { game.health = 20 }
                    if !game.alive { game.alive = true; game.health = 20 }
                    if i % 720 == 0 {
                        let p = game.player.pos
                        let x = Int(floor(p.x)) + 2, z = Int(floor(p.z)) + 2
                        if let c = game.world.chunkAt(x, z) {
                            let y = Int(c.height[mod(x, CS) + mod(z, CS) * CS])
                            game.world.setBlock(x, y, z, AIR)
                            game.world.setBlock(x + 1, y + 1, z, dirt)
                        }
                    }
                    f.frame()
                }
                if simd_length(V2(game.player.pos.x - start.x, game.player.pos.z - start.z)) < 100 {
                    let p = game.player.pos + V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw)) * 200
                    _ = game.world.loadSync(center: p, radius: 1)
                    if let c = game.world.chunkAt(Int(floor(p.x)), Int(floor(p.z))) {
                        game.player.pos = V3(p.x, Float(c.height[mod(Int(floor(p.x)), CS) + mod(Int(floor(p.z)), CS) * CS]) + 1.5, p.z)
                        game.player.vel = .zero
                    }
                }
                let r = status("VmRSS")
                samples.append(r)
                let p = game.player.pos
                print(String(format: "memory: minute %d at %.0f, %.0f: resident %.0f MB, peak %.0f MB, %d chunks, meshes %@ MB, audio %@ MB",
                             m + 1, p.x, p.z, r, status("VmHWM"), game.world.chunks.count, mb(MeshArena.shared.slabBytes),
                             mb((game.sound?.bank.cachedBytes ?? 0) + (game.sound?.clipBytes ?? 0))))
            }
            PadManager.shared.touch = nil
            print("memory: after \(minutes) minutes: " + breakdown(game))
            let tail = samples.suffix(max(1, samples.count / 2))
            print(String(format: "MEMSIM %d min: peak %.0f MB, resident %.0f MB; second half %.0f..%.0f MB", minutes, status("VmHWM"),
                         samples.last ?? 0, tail.min() ?? 0, tail.max() ?? 0))
        }
        withExtendedLifetime((img, target, panel)) {}
        scene.waitIdle()
        return 0
    }
}
