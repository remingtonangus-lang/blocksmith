import Foundation
import simd
import Metal
import CVulkan
import COpenXR

// The Quest app: the OpenXR frame loop driving the shared Game and the Vulkan renderer. The world loads on a
// background thread (textures painted, world generated and meshed around the spawn) while a small loading scene
// keeps the compositor fed; then every display frame runs Game.tick with the Touch controllers, streams chunks,
// and renders both eyes in one multiview pass.
final class QuestApp {
    let xr: XRSession
    let device: QuestDevice
    let scene: SceneRenderer
    private var targets: [RenderTarget] = []
    private(set) var game: Game?
    private var worldRenderer: WorldRenderer?
    private var save: SaveManager?
    let rig = QuestRig()
    var controls: QuestControls?
    private var loadThread: Thread?
    private var hudPanel: HudPanel?
    private let loadLock = NSLock()
    private var loaded: (Game, SaveManager, [[UInt8]])?
    private var loadStatus = "Starting"
    private var loadProgress: Float = 0
    private var loadStart = CFAbsoluteTimeGetCurrent()
    let stats = FrameStats()
    var platformName = "Quest"
    static var debugClearOnly = ProcessInfo.processInfo.environment["QUEST_CLEAR_ONLY"] != nil

    init(xr: XRSession) throws {
        self.xr = xr
        setenv("BLOCKSMITH_TEXRES", "\(QuestSettings.textureRes)", 1)
        device = QuestDevice(xr.vk)
        sharedSystemDevice = device
        xr.resolutionScale = QuestSettings.resolutionScale
        try xr.createSwapchain()
        scene = try SceneRenderer(ctx: xr.vk, device: device, views: 2, colorFormat: xr.colorFormat, foveated: xr.foveated)
        scene.linearOutput = SceneRenderer.isSRGB(xr.colorFormat)
        for (i, img) in xr.swapImages.enumerated() {
            let dm = xr.foveated && i < xr.densityMaps.count ? xr.densityMaps[i] : nil
            targets.append(try scene.makeTarget(image: img, width: xr.width, height: xr.height, densityMap: dm))
        }
        xr.onRecenter = { [weak self] in self?.rig.needsRecenter = true }
        startLoading()
    }

    // MARK: Loading

    private func status(_ s: String, _ p: Float) {
        loadLock.lock(); loadStatus = s; loadProgress = p; loadLock.unlock()
        print("load: \(s) (\(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - loadStart)) s)")
    }

    struct WorldRequest { var name: String?; var seed: UInt64?; var survival: Bool?; var difficulty: Int? }

    private func startLoading(_ req: WorldRequest = WorldRequest()) {
        loadStart = CFAbsoluteTimeGetCurrent()
        loadLock.lock(); loadProgress = 0; loadStatus = "Starting"; loadLock.unlock()
        let t = Thread { [weak self] in self?.load(req) }
        t.stackSize = 8 << 20
        t.qualityOfService = .userInitiated
        t.name = "blocksmith.load"
        loadThread = t
        t.start()
    }

    private var texturesUploaded = false

    private func load(_ req: WorldRequest) {
        var tex: [[UInt8]] = []
        if !texturesUploaded {
            status("Painting textures", 0.05)
            TextureGen.registerAll()
            tex = TextureCache.mipChain(dir: QuestPaths.root + "/cache")
        }
        status("Opening the world", 0.4)
        let name = req.name ?? UserDefaults.standard.string(forKey: "lastWorld") ?? "Quest World"
        let save = SaveManager(name: name)
        UserDefaults.standard.set(name, forKey: "lastWorld")
        let meta = save.loadMeta()
        let seed = meta?.seed ?? req.seed ?? Rand.u64(in: 1...UInt64(Int64.max))
        let world = World(seed: seed, device: device, save: save)
        world.renderDistance = QuestSettings.renderDistance
        let game = Game(world: world, save: save, persistent: true)
        Game.oceanSwellDrawn = true                  // boats ride the drawn swell (Weather.swift OceanSwell)
        if let m = meta { game.apply(m) } else {
            game.player.pos = game.spawnPoint
            if let sv = req.survival { game.survival = sv }
            if let d = req.difficulty { game.difficulty = d }
        }
        status("Generating terrain", 0.55)
        _ = world.loadSync(center: game.player.pos, radius: min(3, world.renderDistance))
        // The horizon ring's first sampling (4225 terrain columns, ~0.1 s on a desktop core) here, not on the first
        // world frame (HorizonRing samples synchronously when it has no ring yet).
        HorizonRing.shared.request(game, eye: game.player.eye)
        QuestWarmup.run()
        status("Ready", 1)
        loadLock.lock(); loaded = (game, save, tex); loadLock.unlock()
    }

    // Takes the loaded game on the frame thread: textures to the GPU, renderer, sound, controls.
    // One step per frame (the loading scene keeps rendering in between, so the hand-over never freezes the view):
    // textures, then the HUD panel, then the game itself. Each step's time is logged.
    private var adoptStep = 0
    private var wasFocused = false
    private var firstWorldFrames = 0

    private func adoptLoaded() {
        loadLock.lock(); let ready = loaded != nil; loadLock.unlock()
        guard ready else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        func took(_ what: String) { print(String(format: "adopt: %@ %.1f ms", what, (CFAbsoluteTimeGetCurrent() - t0) * 1000)) }
        if adoptStep == 0 {
            adoptStep = 1
            if !texturesUploaded {
                loadLock.lock(); let tex = loaded?.2 ?? []; loaded?.2 = []; loadLock.unlock()
                do { try scene.uploadTextures(pregenerated: tex); texturesUploaded = true } catch { print("textures: \(error)") }
                took("textures uploaded")
                return
            }
        }
        if adoptStep == 1 {
            adoptStep = 2
            if hudPanel == nil {
                do { hudPanel = try HudPanel(scene: scene, width: QuestControls.panelW, height: QuestControls.panelH) }
                catch { print("hud panel: \(error)") }
                took("HUD panel")
                return
            }
        }
        adoptStep = 0
        loadLock.lock(); let l = loaded; loaded = nil; loadLock.unlock()
        guard let (game, save, _) = l else { return }
        defer { took("game, renderer, sound, controls"); firstWorldFrames = 4 }
        self.save = save
        self.game = game
        game.paused = false
        game.hideHUD = false
        game.sound = SoundEngine()
        game.sound?.volume = game.volumeSetting
        QuestAudioOutput.shared.start(game.sound)
        let wr = WorldRenderer(scene: scene, game: game)
        worldRenderer = wr
        let ctl = QuestControls(app: self, game: game, panel: hudPanel)
        controls = ctl
        wr.extraOpaque = { [weak ctl] s, eye in ctl?.drawOpaque(s, eye: eye) }
        wr.extraOverlay = { [weak ctl] s, eye in ctl?.drawOverlay(s, eye: eye) }
        wr.prePass = { [weak ctl] s in ctl?.recordPanel(s) }
        wr.landmarkHost = ctl.hudHost
        let xrs = xr
        QuestOptions.install(QuestOptions.Hooks(
            recenter: { [weak self] in self?.rig.needsRecenter = true },
            rates: { xrs.availableRates }, currentRate: { xrs.refreshRate },
            setRate: { r in if xrs.setRefreshRate(r) { print("xr: refresh rate \(xrs.refreshRate) Hz") } },
            foveated: { xrs.foveated }, setFoveation: { xrs.applyFoveation(level: $0) }))
        PadManager.shared.haptic = { [weak self] k, secs, sharp in
            guard let self else { return }
            let f: Float = 80 + 240 * sharp
            self.xr.haptic(0, amplitude: k, seconds: secs, frequency: f)
            self.xr.haptic(1, amplitude: k, seconds: secs, frequency: f)
        }
        game.appAction = { [weak self] id in self?.appAction(id) }
        rig.needsRecenter = true
        rig.bodyYaw = game.player.yaw
        print(String(format: "load: world ready in %.1f s (seed %llu, render distance %d)", CFAbsoluteTimeGetCurrent() - loadStart,
                     game.world.seed, game.world.renderDistance))
    }

    // The pause menu's app-level actions (App.swift on the Mac).
    private func appAction(_ id: String) {
        switch id {
        case "quit":
            saveNow()
            xr.requestExit()
        case _ where id.hasPrefix("play:"):
            switchWorld(WorldRequest(name: String(id.dropFirst(5))))
        case "newworld":
            switchWorld(WorldRequest(name: "World\(Rand.int(in: 100...999))", survival: game?.survival, difficulty: game?.difficulty))
        case _ where id.hasPrefix("create:"):
            let parts = id.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 5 else { return }
            switchWorld(WorldRequest(name: parts[3], seed: QuestApp.seedValue(parts[4]), survival: parts[1] == "1", difficulty: Int(parts[2]) ?? 2))
        default: break
        }
    }

    // The seed field's text as a seed (AppDelegate.seedValue on the Mac): a number, else FNV-1a of the text.
    static func seedValue(_ text: String) -> UInt64? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if let v = UInt64(t) { return v }
        if let v = Int64(t) { return UInt64(bitPattern: v) }
        var h: UInt64 = 0xcbf29ce484222325
        for b in t.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    // Saves and closes the current world, then loads another behind the loading scene.
    private func switchWorld(_ req: WorldRequest) {
        print("world: switching to \(req.name ?? "?")")
        saveNow()
        scene.waitIdle()
        game?.sound?.stopAll()
        QuestAudioOutput.shared.stop()
        PadManager.shared.touch = nil
        controls = nil
        worldRenderer = nil
        game = nil
        save = nil
        startLoading(req)
    }

    // MARK: Frame loop

    private var lastFrameTime = CFAbsoluteTimeGetCurrent()

    // One display frame. Returns false when the app should exit.
    func frame() -> Bool {
        guard xr.pollEvents() else { return false }
        guard xr.running else { Thread.sleep(forTimeInterval: 0.02); return true }
        if game == nil { adoptLoaded() }
        let f: XRSession.Frame
        do { f = try xr.beginFrame() } catch { print("xr frame: \(error)"); return !xr.exitRequested }
        let t0 = CFAbsoluteTimeGetCurrent()
        xr.pollInput()
        var tickMs = 0.0, recordMs = 0.0
        if game == nil, f.shouldRender { rig.updateLoading(xr: xr) }
        if let g = game {
            let dt = min(0.1, max(1.0 / 120, f.period > 0 ? f.period : 1.0 / 72))
            // Ship physics steps once per displayed frame (60 Hz substeps at 72 Hz left one frame in six without a
            // step: the deck and the player riding it juddered against the world).
            let rate = Float(1 / dt)
            if abs(ShipManager.stepRate - rate) > 0.5 { ShipManager.stepRate = rate; ShipManager.stepSlack = 0.2 / rate }
            if f.shouldRender { rig.update(xr: xr, game: g) }
            controls?.update(dt: Float(dt))
            let a = CFAbsoluteTimeGetCurrent()
            // Input focus lost (headset off, the system menu or a dialog up): the world stops and the pause menu is up
            // when the user comes back, so nothing happens to them meanwhile.
            if !xr.focused && wasFocused && g.menu == nil && g.credits == nil { g.paused = true }
            wasFocused = xr.focused
            // Game.tick streams the world first thing; unfocused, keep chunks arriving without ticking.
            if xr.focused { g.tick(dt) } else { g.world.update(center: g.player.pos) }
            controls?.afterTick(dt: Float(dt))
            tickMs = (CFAbsoluteTimeGetCurrent() - a) * 1000
        }
        if f.shouldRender, f.imageIndex >= 0, f.imageIndex < targets.count {
            let a = CFAbsoluteTimeGetCurrent()
            let s = scene.beginFrame()
            QuestScreenshot.collect(began: s)          // a capture whose frame has completed -> PNG on a utility queue
            let target = targets[f.imageIndex]
            let cam = rig.camera(xr: xr, far: farPlane)
            if QuestApp.debugClearOnly {
                scene.beginPass(s, target, clear: V3(0.2, 0.4, 0.8))
            } else if let wr = worldRenderer {
                wr.record(s, target, cam)
            } else {
                recordLoading(s, target, cam)
            }
            vkCmdEndRenderPass(s.cmd)
            // Bug-note screenshot (if one is pending): left eye, HUD panel included, blitted small before release.
            QuestScreenshot.service(s, ctx: xr.vk, image: target.image, format: xr.colorFormat, width: xr.width, height: xr.height)
            do { try scene.submit(s) } catch { print("submit: \(error)") }
            recordMs = (CFAbsoluteTimeGetCurrent() - a) * 1000
        }
        do { try xr.endFrame(f) } catch { print("xr end frame: \(error)") }
        let now = CFAbsoluteTimeGetCurrent()
        if firstWorldFrames > 0 && game != nil {
            firstWorldFrames -= 1
            print(String(format: "first world frame: cpu %.1f ms (tick %.1f, record %.1f)", (now - t0) * 1000, tickMs, recordMs))
        }
        stats.add(frame: now - lastFrameTime, cpu: (now - t0) * 1000, tick: tickMs, record: recordMs, gpu: scene.gpuMs,
                  target: f.period, scene: scene, game: game, rate: xr.refreshRate)
        lastFrameTime = now
        return !xr.exitRequested
    }

    var farPlane: Float {
        let rd = Float(game?.world.renderDistance ?? 4)
        let ships = game?.world.ships.list.contains { $0.kinematic } ?? false
        return max(rd * 16 + 96, ships ? 1000 : 0)
    }

    // Saves the world (activity paused / exiting).
    func saveNow() {
        guard let g = game else { return }
        g.saveNow()
        SaveIO.flush()
        print("save: world saved")
    }

    func shutdown() {
        saveNow()
        QuestAudioOutput.shared.stop()
        scene.waitIdle()
    }

    // MARK: Loading scene

    // Sky gradient, a ring of slowly turning blocks at eye height and a progress bar in front of the user.
    private func recordLoading(_ s: SceneRenderer.Slot, _ t: RenderTarget, _ cam: EyeCamera) {
        var u = FrameUniforms()
        u.viewProj = (cam.viewProj[0], cam.viewProj.count > 1 ? cam.viewProj[1] : cam.viewProj[0])
        u.invViewProj = (u.viewProj.0.inverse, u.viewProj.1.inverse)
        u.fogColor = V4(0.52, 0.72, 0.96, 1000)
        u.params = V4(2000, 1, Float(CFAbsoluteTimeGetCurrent().truncatingRemainder(dividingBy: 1000)), 0)
        u.sunDir = V4(simd_normalize(V3(0.3, 0.8, -0.5)), 1)
        u.zenith = V4(0.22, 0.4, 0.8, 0)
        u.horizon = V4(0.52, 0.72, 0.96, 0.2)
        u.misc = V4(1, 1, scene.linearOutput ? 2.2 : 1, 0)
        scene.setUniforms(s, u)
        scene.resetScratch()
        scene.beginPass(s, t, clear: V3(0.52, 0.72, 0.96))
        loadLock.lock(); let p = loadProgress; loadLock.unlock()
        var v: [SimpleVert] = []
        let time = Float(CFAbsoluteTimeGetCurrent() - loadStart)
        let headY = rig.floorEyeY(xr: xr)
        let colors: [V4] = [V4(0.36, 0.62, 0.25, 1), V4(0.55, 0.38, 0.22, 1), V4(0.6, 0.6, 0.62, 1), V4(0.85, 0.75, 0.45, 1),
                            V4(0.25, 0.45, 0.8, 1), V4(0.8, 0.3, 0.25, 1), V4(0.95, 0.85, 0.3, 1), V4(0.4, 0.3, 0.6, 1)]
        let shades: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
        let CT = Mesher.cornerTable
        // The ring is placed in tracking space around the head's starting point: camera-relative = trackingPos - head.
        for i in 0..<8 {
            let a = Float(i) / 8 * 2 * .pi + time * 0.15
            let c = V3(sinf(a) * 3, headY - 0.2 + 0.25 * sinf(time * 1.3 + Float(i)), -cosf(a) * 3) - rig.trackingHead
            let spin = simd_quatf(angle: time * 0.6 + Float(i), axis: simd_normalize(V3(0.3, 1, 0.2)))
            for f in 0..<6 {
                for k in [0, 1, 2, 0, 2, 3] {
                    let ci = (f * 4 + k) * 3
                    let lp = V3(Float(CT[ci]) - 0.5, Float(CT[ci + 1]) - 0.5, Float(CT[ci + 2]) - 0.5) * 0.45
                    let col = colors[i] * V4(shades[f], shades[f], shades[f], 1)
                    v.append(SimpleVert(pos: V4(spin.act(lp) + c, 1), color: col))
                }
            }
        }
        // Progress bar 2 m ahead (in the direction the user faced at start).
        let bar = V3(0, headY - 0.35, -2) - rig.trackingHead
        func rect(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ z: Float, _ col: V4) {
            let q = [V3(x0, y0, z), V3(x1, y0, z), V3(x1, y1, z), V3(x0, y1, z)].map { $0 + bar }
            for k in [0, 1, 2, 0, 2, 3] { v.append(SimpleVert(pos: V4(q[k], 1), color: col)) }
        }
        rect(-0.6, 0.6, -0.04, 0.04, 0, V4(0.1, 0.1, 0.12, 0.85))
        rect(-0.58, -0.58 + 1.16 * max(0.02, min(1, p)), -0.025, 0.025, 0.005, V4(0.45, 0.85, 0.4, 1))
        if let off = scene.push(s, v) { scene.drawScratch(s, "simpleSolid", offset: off, count: v.count) }
        scene.drawSky(s)
    }
}

// Rolling frame statistics, logged every 5 s (adb logcat -s Blocksmith).
final class FrameStats {
    // Resident memory of the process (VmRSS from /proc, Linux and Android), MB; 0 where unavailable.
    static func residentMB() -> Int {
        guard let t = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8),
              let line = t.split(separator: "\n").first(where: { $0.hasPrefix("VmRSS:") }) else { return 0 }
        let kb = Int(line.split(separator: " ").dropFirst().first { Int($0) != nil } ?? "") ?? 0
        return kb >> 10
    }
    private var frames = 0, missed = 0
    private var sumCPU = 0.0, sumTick = 0.0, sumRecord = 0.0, sumGPU = 0.0, worstFrame = 0.0
    // The worst frame's own split (where a hitch went): cpu, game tick, world streaming within it, record, gpu.
    private var worstCPU = 0.0, worstTick = 0.0, worstWorld = 0.0, worstRecord = 0.0, worstGPU = 0.0
    private var since = CFAbsoluteTimeGetCurrent()
    private var lastLowered = 0.0
    private(set) var lastLine = ""
    private(set) var fps = 0.0
    private(set) var gpuAvg = 0.0, cpuAvg = 0.0

    func add(frame: Double, cpu: Double, tick: Double, record: Double, gpu: Double, target: Double, scene: SceneRenderer, game: Game?, rate: Float) {
        frames += 1
        sumCPU += cpu; sumTick += tick; sumRecord += record; sumGPU += gpu
        if frame * 1000 > worstFrame {
            worstFrame = frame * 1000
            worstCPU = cpu; worstTick = tick; worstRecord = record; worstGPU = gpu
            worstWorld = (game?.world.perf.updateSeconds ?? 0) * 1000
        }
        if target > 0 && frame > target * 1.5 { missed += 1 }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - since >= 5 else { return }
        let n = Double(max(1, frames))
        fps = Double(frames) / (now - since)
        BugNotes.shared.frameTime = fps > 0 ? 1 / fps : 0
        gpuAvg = sumGPU / n; cpuAvg = sumCPU / n
        let w = game?.world
        lastLine = String(format: "perf: %.1f fps (display %.0f Hz), missed %d, worst %.1f ms (cpu %.1f: tick %.1f incl. world %.1f, record %.1f; gpu %.1f) | cpu %.2f ms (tick %.2f, record %.2f) | gpu %.2f ms | sections %d, draws %d, quads %d, cull %.2f ms | chunks %d, jobs %d, mobs %d | mesh slabs %d MB, resident %d MB",
                          fps, rate, missed, worstFrame, worstCPU, worstTick, worstWorld, worstRecord, worstGPU, sumCPU / n, sumTick / n, sumRecord / n, sumGPU / n,
                          scene.visibleCount, scene.drawCalls, scene.drawnQuads, scene.cullMs,
                          w?.chunks.count ?? 0, w?.pendingJobs ?? 0, game?.mobs.mobs.count ?? 0, MeshArena.shared.slabBytes >> 20,
                          FrameStats.residentMB())
        print(lastLine)
        // Comfort guard (VR page option): frames missed in this window with the GPU or CPU near the frame budget
        // (not a loading hitch) lower the render distance one step, not below 4, for this session.
        let budget = target * 1000
        if QuestSettings.autoRenderDistance, let g = game, budget > 0, Double(missed) > n * 0.05,
           sumGPU / n > budget * 0.8 || sumCPU / n > budget * 0.8, g.world.renderDistance > 4, now - lastLowered > 15 {
            g.world.renderDistance -= 1
            lastLowered = now
            print("perf: missed frames at the frame budget: render distance lowered to \(g.world.renderDistance) for this session")
            g.onToast?("Render distance \(g.world.renderDistance) to keep the frame rate (VR Comfort & Controls)")
        }
        frames = 0; missed = 0; sumCPU = 0; sumTick = 0; sumRecord = 0; sumGPU = 0; worstFrame = 0
        since = now
    }
}
