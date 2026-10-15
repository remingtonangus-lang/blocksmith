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
    let handed: HandedInput                        // S7/S8: the hands as the controls read them (QuestHands.swift)
    var controls: QuestControls?
    private var loadThread: Thread?
    private var hudPanel: HudPanel?
    private let loadLock = NSLock()
    private var loaded: (Game, SaveManager?, [[UInt8]])?
    private var joinFailed: String?
    // F3: a world being saved behind the loading scene ("Saving the world"), and a quit waiting for that save.
    private var savingGame: Game?
    private var exitWhenSaved = false
    private var saveDone = false
    private var loadStatus = "Starting"
    private var loadProgress: Float = 0
    private var loadStart = CFAbsoluteTimeGetCurrent()
    let stats = FrameStats()
    var platformName = "Quest"
    static var debugClearOnly = ProcessInfo.processInfo.environment["QUEST_CLEAR_ONLY"] != nil

    init(xr: XRSession) throws {
        self.xr = xr
        handed = HandedInput(raw: xr)
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
        // S8: the runtime moved the reference space (a recentre from the system button, the boundary redrawn): the rig
        // re-anchors on the next frame and the HUD and menus re-place themselves (QuestControls watches rig.recenters).
        xr.onRecenter = { [weak self] in
            self?.rig.needsRecenter = true
            self?.game?.onToast?(QuestSettings.reclined ? "View levelled to your gaze" : "View recentred")
        }
        World.fluidSeconds = 0.002                 // fluid ticks yield after 2 ms (World.fluidSeconds)
        World.handoverSeconds = 0.0015             // streamed chunks/meshes installed within 1.5 ms a frame
        // Far detail (merged faces, no grass/flowers, fast leaves) from 5 chunks out instead of 8: rd 16 Quest-proxy
        // bench 17-23% fewer terrain quads, screenshots at 80+ blocks differ in 0.01% of pixels.
        World.lodNear = 5
        // "Fast" leaves (no faces between leaf blocks) from 3 chunks out: the Oct 10 taiga village drew ~500k quads at
        // rd 16, about half of them leaves (docs/status/performance.md).
        World.leafNear = 2
        stats.lowerRate = { [weak xr] in
            guard let x = xr, x.refreshRate > 72.5, x.setRefreshRate(72) else { return false }
            return true
        }
        stats.recordStages = { [weak self] in self?.worldRenderer?.takeStages() ?? "" }
        startLoading()
    }

    // MARK: Loading

    private func status(_ s: String, _ p: Float) {
        loadLock.lock(); loadStatus = s; loadProgress = p; loadLock.unlock()
        print("load: \(s) (\(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - loadStart)) s)")
    }

    private func startLoading(_ req: WorldRequest = WorldRequest()) {
        loadStart = CFAbsoluteTimeGetCurrent()
        loadLock.lock(); loadProgress = 0; loadStatus = "Starting"; loadLock.unlock()
        let old = savingGame
        savingGame = nil
        let quitting = exitWhenSaved
        let t = Thread { [weak self] in
            // F3 (Oct 13 evening: quit and world switches froze the view while the save flushed): the old world, no
            // longer ticked or drawn, is saved here with the loading scene up and saying so.
            // P223 (Oct 13 21:37, "a very long wait to get onto my world"): on a switch the old world is saved the
            // autosave's way (snapshots now, the files written on the save queue) while the new world opens and
            // generates; the new world is handed over once the old one is on disk. A quit still saves first.
            if let g = old {
                self?.status("Saving the world", 0.02)
                let a = CFAbsoluteTimeGetCurrent()
                if quitting {
                    g.saveNow()
                    SaveIO.flush()
                } else {
                    g.saveNow(background: true)
                    MapFog.shared.save(g, background: true)
                    // Reopening the same world (leaving a co-op game, a restore): its files are read first, so on disk now.
                    let target = req.name ?? UserDefaults.standard.string(forKey: "lastWorld") ?? ""
                    if req.join == nil && WorldStore.url(target).lastPathComponent == g.save?.dir.lastPathComponent { SaveIO.flush() }
                }
                print(String(format: "save: world snapshot %.2f s", CFAbsoluteTimeGetCurrent() - a))
            }
            if quitting { self?.loadLock.lock(); self?.saveDone = true; self?.loadLock.unlock(); return }
            self?.load(req, before: {
                let a = CFAbsoluteTimeGetCurrent()
                SaveIO.flush()
                print(String(format: "save: old world on disk (waited %.2f s at the hand-over)", CFAbsoluteTimeGetCurrent() - a))
            })
        }
        t.stackSize = 8 << 20
        t.qualityOfService = .userInitiated
        t.name = "blocksmith.load"
        loadThread = t
        t.start()
    }

    private var texturesUploaded = false

    private func load(_ req: WorldRequest, before handOver: () -> Void = {}) {
        var tex: [[UInt8]] = []
        if !texturesUploaded {
            status("Painting textures", 0.05)
            TextureGen.registerAll()
            tex = TextureCache.mipChain(dir: QuestPaths.root + "/cache")
        }
        if let ip = req.join {
            status("Joining \(ip)", 0.4)
            if let gu = NetGuest(ip: ip, name: "Quest player"), gu.waitWelcome(seconds: 6) {
                let game = WorldRequest.guestGame(gu, device: device, renderDistance: min(QuestSettings.renderDistance, 8))
                Game.oceanSwellDrawn = true
                game.rdGovernor = RenderDistanceGovernor(chosen: game.world.renderDistance)
                status("Receiving \(gu.worldName)", 0.55)
                _ = game.world.loadSync(center: game.player.pos, radius: min(2, game.world.renderDistance))
                HorizonRing.shared.request(game, eye: game.player.eye)
                FarRing.shared.request(game, eye: game.player.eye)
                status("Ready", 1)
                loadLock.lock(); loaded = (game, nil, tex); loadLock.unlock()
                return
            }
            joinFailed = "Couldn't join \(ip): is the host's world open with hosting on?"
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
        // The save's state or the new world's options, then the terrain option, before the first meshes (questcheck tests this).
        req.setUp(game, meta: meta)
        // The headset's own setting, not the save's (Game.apply restores the world's saved distance, which held the
        // comfort guard's session-only step-downs: the Oct 9 playtest reopened its world at render distance 5). On
        // game.world: a save made in another dimension reopens there, and `world` is the overworld. Auto Render
        // Distance steps the world below this choice for the session; the save and the options keep the choice.
        game.rdGovernor = RenderDistanceGovernor(chosen: QuestSettings.renderDistance)
        game.world.renderDistance = QuestSettings.renderDistance
        status("Generating terrain", 0.55)
        _ = game.world.loadSync(center: game.player.pos, radius: min(3, game.world.renderDistance))
        // The horizon ring's first sampling (4225 terrain columns, ~0.1 s on a desktop core) here, not on the first
        // world frame (HorizonRing samples synchronously when it has no ring yet).
        HorizonRing.shared.request(game, eye: game.player.eye)
        // F4: the middle ring's first build (~17k terrain columns) here too, not on the first world frame.
        FarRing.shared.request(game, eye: game.player.eye)
        QuestWarmup.run()
        handOver()
        status("Ready", 1)
        loadLock.lock(); loaded = (game, save, tex); loadLock.unlock()
    }

    // Takes the loaded game on the frame thread: textures to the GPU, renderer, sound, controls.
    // One step per frame (the loading scene keeps rendering in between, so the hand-over never freezes the view):
    // textures, then the HUD panel, then the game itself. Each step's time is logged.
    private var adoptStep = 0
    private var wasFocused = false
    private var awayFor = 0.0, savedAway = false, headLostFor = 0.0      // S8
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
            foveated: { xrs.foveated }, setFoveation: { xrs.applyFoveation(level: $0) },
            headHeight: { xrs.floorSpace && xrs.headTracked ? xrs.headPos.y : nil },
            finishSetup: { [weak self] in
                guard let g = self?.game else { return }
                if g.menu is PauseMenu { g.closeMenu() }
                g.paused = false
            },
            toast: { [weak self] t in self?.game?.onToast?(t) },
            game: { [weak self] in self?.game }))
        PadManager.shared.haptic = { [weak self] k, secs, sharp in
            guard let self else { return }
            let f: Float = 80 + 240 * sharp
            self.xr.haptic(0, amplitude: k, seconds: secs, frequency: f)
            self.xr.haptic(1, amplitude: k, seconds: secs, frequency: f)
        }
        game.appAction = { [weak self] id in self?.appAction(id) }
        if let why = joinFailed { joinFailed = nil; game.onToast?(why) }
        rig.needsRecenter = true
        rig.bodyYaw = game.player.yaw
        // S6: the first launch opens the setup panel (play position, comfort, dominant hand, controls, height) over the
        // world, once; VR Comfort & Controls > First-Launch Setup opens it again.
        if !QuestSettings.setupShown {
            QuestSettings.setupShown = true
            game.paused = true
            if let pm = game.menu as? PauseMenu { pm.hostPageID = "setup"; pm.build() }
        }
        print(String(format: "load: world ready in %.1f s (seed %llu, render distance %d)", CFAbsoluteTimeGetCurrent() - loadStart,
                     game.world.seed, game.world.renderDistance))
    }

    // The pause menu's app-level actions (App.swift on the Mac).
    private func appAction(_ id: String) {
        switch id {
        case "quit":
            exitWhenSaved = true
            switchWorld(WorldRequest())
        case "restorebackup":
            // S4: the open world is closed without saving (it is what crashed), its newest backup copied back, reopened.
            guard let g = game, let dir = g.save?.dir else { break }
            let name = dir.lastPathComponent
            savingGame = nil
            if let gu = g.netGuest { gu.detach(g); g.netGuest = nil }
            g.netHost?.stop(g); g.netHost = nil
            scene.waitIdle()
            g.sound?.stopAll()
            QuestAudioOutput.shared.stop()
            PadManager.shared.touch = nil
            controls = nil; worldRenderer = nil; game = nil; save = nil
            SaveIO.flush()
            let ok = CrashGuard.restore(dir: dir)
            print("restore backup of \(name): \(ok)")
            if !ok { joinFailed = "No backup copy of this world yet" }
            startLoading(WorldRequest(name: name))
        case _ where id.hasPrefix("play:"):
            switchWorld(WorldRequest(name: String(id.dropFirst(5))))
        case "newworld":
            switchWorld(WorldRequest(name: "World\(Rand.int(in: 100...999))", survival: game?.survival, difficulty: game?.difficulty, smooth: true))   // (PG6: Polygons, even from a block world)
        case _ where id.hasPrefix("netjoin:"):
            switchWorld(WorldRequest(join: String(id.dropFirst(8))))
        case "netleave":
            if let g = game, let gu = g.netGuest { gu.detach(g); gu.clearMirrors(g); g.netGuest = nil }
            switchWorld(WorldRequest())
        case "workshop":
            switchWorld(WorldRequest(name: CircuitWorkshop.worldName, seed: CircuitWorkshop.seed, survival: false, difficulty: 1))
        case _ where id.hasPrefix("create:"):
            if let req = WorldRequest.create(action: id) { switchWorld(req) }
        default: break
        }
    }

    // Saves and closes the current world, then loads another behind the loading scene.
    private func switchWorld(_ req: WorldRequest) {
        print("world: switching to \(req.name ?? req.join ?? "?")")
        let t0 = CFAbsoluteTimeGetCurrent()
        defer { print(String(format: "world: switch took %.1f ms on the frame thread", (CFAbsoluteTimeGetCurrent() - t0) * 1000)) }
        savingGame = game                    // saved on the loading thread (startLoading), behind "Saving the world"
        if let g = game { g.netHost?.stop(g); g.netHost = nil; if let gu = g.netGuest { gu.detach(g); g.netGuest = nil } }
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
        guard xr.running else {
            // S8: the session stopped (headset off long enough to sleep, the app sent to the background, Quit from the
            // system menu): the world is paused and saved once, before anything else can end the process.
            if let g = game, !savedAway {
                savedAway = true
                if g.menu == nil && g.credits == nil { g.paused = true }
                saveNow()
            }
            Thread.sleep(forTimeInterval: 0.02); return true
        }
        QuestEntitlement.poll()                                   // S5 (off until the store app ID is set)
        if QuestEntitlement.denied && !exitWhenSaved {
            game?.onToast?("This copy of Blocksmith isn't linked to your account. Buy it from the store to play.")
            exitWhenSaved = true
            switchWorld(WorldRequest())
        }
        if exitWhenSaved {
            loadLock.lock(); let done = saveDone; loadLock.unlock()
            if done { xr.requestExit() }
        } else if game == nil { adoptLoaded() }
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
            // Q2c-console-37: silent while away; the world and its music ducked while paused (not at the title, not
            // while he sets volumes on Options > Audio).
            let pm = g.menu as? PauseMenu
            let audioPage = pm.map { $0.page == .options && $0.cat == .audio } ?? false
            g.sound?.setAway(!xr.focused, duck: g.paused && !(pm?.cameFromTitle ?? false) && !audioPage)
            // S8: away (the boundary or the system menu up, the headset taken off) for two seconds: saved once.
            awayFor = xr.focused ? 0 : awayFor + dt
            if xr.focused { savedAway = false } else if awayFor > 2 && !savedAway { savedAway = true; saveNow() }
            // S8: head tracking lost (XRSession.headTracked; the view holds the last tracked pose): no ticks, and after
            // a moment the pause menu, so nothing happens to the player in the dark.
            headLostFor = xr.headTracked ? 0 : headLostFor + dt
            if headLostFor > 0.3 && !g.paused && g.menu == nil && g.credits == nil {
                g.paused = true
                g.onToast?("Headset tracking lost: paused")
            }
            // Game.tick streams the world first thing; unfocused, keep chunks arriving without ticking.
            if xr.focused && xr.headTracked { g.tick(dt) } else { g.world.update(center: g.player.pos) }
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
        // F1: a frame over 250 ms goes to hitches.log on the headset (time, split, the tick's slowest stages), so a
        // freeze can be matched to a voice note's timestamp.
        if now - lastFrameTime > 0.25 && game != nil && firstWorldFrames == 0 { logHitch(ms: (now - lastFrameTime) * 1000, tick: tickMs, record: recordMs) }
        stats.add(frame: now - lastFrameTime, cpu: (now - t0) * 1000, tick: tickMs, record: recordMs, gpu: scene.gpuMs,
                  target: f.period, scene: scene, game: game, rate: xr.refreshRate)
        lastFrameTime = now
        return !xr.exitRequested
    }

    private func logHitch(ms: Double, tick: Double, record: Double) {
        let stage = TickProf.summary()
        let split = String(format: "frame %.0f ms (tick %.1f, record %.1f)", ms, tick, record)
        let line = ISO8601DateFormatter().string(from: Date()) + " " + split + " slowest: " + stage + "\n"
        print("hitch: " + line, terminator: "")
        let path = QuestPaths.root + "/hitches.log"
        DispatchQueue.global(qos: .utility).async {
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile(); h.write(line.data(using: .utf8) ?? Data()); h.closeFile()
            } else {
                try? line.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    var farPlane: Float {
        let rd = Float(game?.world.renderDistance ?? 4)
        let ships = game?.world.ships.list.contains { $0.kinematic } ?? false
        // F4: the middle ring (Sources/FarRing.swift) reaches FarRing.outer in the overworld; the horizon shell and the
        // landmark impostors sit just inside the far plane, behind it.
        let ring: Float = FarRing.enabled && game?.dim.dim == .overworld ? FarRing.outer + 96 : 0
        return max(rd * 16 + 96, ships ? 1000 : 0, ring)
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
        CrashGuard.mark(false)
        QuestAudioOutput.shared.stop()
        scene.waitIdle()
    }

    // MARK: Loading scene

    // Q2c-console-3: tips while the world loads (one every 8 s).
    static let loadingTips = [
        "Tip: grip your chest pocket with your right hand to open the journal.",
        "Tip: in survival, Y calls your horse to you.",
        "Tip: pause menu, Track a Target, puts a beacon over what you follow.",
        "Tip: VR Comfort & Controls has snap turns, teleport and the vignette.",
        "Tip: your world saves itself every minute; look for the Saved badge.",
        "Tip: grips step through your hotbar; click the right stick for the weapon wheel.",
        "Tip: with a gun out, reach to your hip and grip to take a magazine.",
        "Tip: sneak by clicking the left stick; pushed hard, the click sprints.",
        "Tip: beat the story and the Director keeps the land busy (Options, Director).",
        "Tip: crouch to pass under low gaps and through tight caves.",
    ]

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
        // Q2c-console-3: what is happening and a tip, in the game's pixel font drawn as quads (no textures needed, so
        // it shows on the very first launch): 6 mm a font pixel, white on a dark shadow, centred under the bar.
        loadLock.lock(); let what = loadStatus; loadLock.unlock()
        func label(_ str: String, _ y: Float, _ px: Float, _ col: V4) {
            let w = Float(Font.width(str)) * px
            var x = -w / 2
            for u in str.unicodeScalars {
                let code = Int(u.value)
                guard code >= 32 && code < 127 else { x += 6 * px; continue }
                let g = Font.glyphs[code - 32]
                for r in 0..<(g.count - 1) {
                    let bits = g[r + 1]
                    if bits == 0 { continue }
                    for c in 0..<g[0] where bits & (1 << c) != 0 {
                        let x0 = x + Float(c) * px, y0 = y - Float(r) * px
                        rect(x0 + px * 0.45, x0 + px * 1.45, y0 - px * 1.45, y0 - px * 0.45, 0.002, V4(0.05, 0.06, 0.1, 0.9))
                        rect(x0, x0 + px, y0 - px, y0, 0.006, col)
                    }
                }
                x += Float(g[0] + 1) * px
            }
        }
        label("\(what)  \(Int((max(0, min(1, p)) * 100).rounded()))%", -0.08, 0.006, V4(1, 1, 1, 1))
        let tips = QuestApp.loadingTips
        let tip = tips[Int(time / 8) % tips.count]
        let words = tip.split(separator: " ")
        if Font.width(tip) > 230, words.count > 3 {
            // Two lines, split at the word nearest the middle.
            var best = 1, bestD = Int.max
            for k in 1..<words.count {
                let d = abs(Font.width(words[..<k].joined(separator: " ")) - Font.width(words[k...].joined(separator: " ")))
                if d < bestD { bestD = d; best = k }
            }
            label(words[..<best].joined(separator: " "), -0.16, 0.0055, V4(0.85, 0.9, 1, 1))
            label(words[best...].joined(separator: " "), -0.21, 0.0055, V4(0.85, 0.9, 1, 1))
        } else {
            label(tip, -0.16, 0.0055, V4(0.85, 0.9, 1, 1))
        }
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
    private var tickStage: StaticString = "-", tickStageMs = 0.0, worstTickAny = 0.0
    private var since = CFAbsoluteTimeGetCurrent()
    private var loggedRD = -1
    // Auto Render Distance inputs besides the timings: a menu or pause in the window, a save, a dimension change,
    // and the chunks generated (a loading burst: fast flight, a raise's new ring).
    private var busyFrames = 0, lastSaves = -1, lastGen = -1
    private weak var lastWorld: World?
    // Set by QuestApp: asks the runtime for 72 Hz; true when the rate changed.
    var lowerRate: (() -> Bool)?
    // Set by QuestApp: the world renderer's record split since the last line (WorldRenderer.takeStages).
    var recordStages: (() -> String)?
    private(set) var lastLine = ""
    // Chunks generated a second above which a window is a loading burst (walking at rd 16 generates ~12 a second,
    // normal flight ~22, fast flight 150+).
    static let loadingChunksPerSecond = 40.0
    private(set) var fps = 0.0
    private(set) var gpuAvg = 0.0, cpuAvg = 0.0

    func add(frame: Double, cpu: Double, tick: Double, record: Double, gpu: Double, target: Double, scene: SceneRenderer, game: Game?, rate: Float) {
        frames += 1
        PerfOverlay.shared.add(frameMs: frame * 1000)
        if let g = game { MainGunPerf.record(frameMs: frame * 1000, budget: target * 1000, clock: g.clock) }   // "perf: main gun blast" after an impact
        sumCPU += cpu; sumTick += tick; sumRecord += record; sumGPU += gpu
        if frame * 1000 > worstFrame {
            worstFrame = frame * 1000
            worstCPU = cpu; worstTick = tick; worstRecord = record; worstGPU = gpu
            worstWorld = (game?.world.perf.updateSeconds ?? 0) * 1000
        }
        // The slowest tick of the window and its slowest stage (TickProf), whether or not it made the worst frame.
        if tick > worstTickAny { worstTickAny = tick; (tickStage, tickStageMs) = TickProf.top() }
        if target > 0 && frame > target * 1.5 { missed += 1 }
        if let g = game, g.menu != nil || g.paused { busyFrames += 1 }
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
        // The window's slowest game tick and its slowest stage (TickProf): what a tick hitch was.
        lastLine += " | slowest tick \(String(format: "%.1f", worstTickAny)) ms: \(tickStage) \(String(format: "%.1f", tickStageMs)) ms"
        if let st = recordStages?(), !st.isEmpty { lastLine += " | record ms: " + st }
        print(lastLine)
        // Auto Render Distance (VR page option; RenderDistanceGovernor.swift): a window missing frames (P240)
        // with the CPU or GPU near the budget first drop a refresh rate above 72 Hz to 72 (the Oct 9 playtest at 90 Hz
        // ran ~10 ms CPU frames against 11.1 ms), then the render distance one step (not below 4); sustained headroom
        // brings it back a step at a time to the player's choice. Loading bursts, menus and saves count neither way
        // (Oct 10 playtest: fast flight stepped 16 -> 13 and it never came back).
        if let g = game {
            let gen = g.world.perf.genChunks, saves = g.saveCount
            let newWorld = lastWorld !== g.world
            let genRate = newWorld || lastGen < 0 ? 0 : Double(gen - lastGen) / max(0.001, now - since)
            // A menu glance doesn't excuse the window (Oct 11 P15: map and pause menus every few seconds kept 22 fps at
            // distance 22 from ever counting); a window mostly in menus does.
            let excused = busyFrames * 2 > frames || newWorld || (lastSaves >= 0 && saves != lastSaves)
            lastGen = gen; lastSaves = saves; lastWorld = g.world
            if QuestSettings.autoRenderDistance, var gov = g.rdGovernor, target > 0 {
                let w = RenderDistanceGovernor.Window(seconds: now - since, frames: frames, missed: missed, cpuMs: sumCPU / n,
                                                      gpuMs: sumGPU / n, budgetMs: target * 1000,
                                                      loading: genRate > FrameStats.loadingChunksPerSecond, excused: excused)
                var act = gov.observe(w, canLowerRate: rate > 72.5 && lowerRate != nil)
                if act == .lowerRate {
                    if let lower = lowerRate, lower() {
                        print("perf: missed frames at the frame budget: refresh rate lowered to 72 Hz for this session")
                        g.onToast?("72 Hz to keep the frame rate (VR Comfort & Controls)")
                    } else { act = gov.rateUnavailable() }
                }
                switch act {
                case .lower(let rd):
                    g.world.renderDistance = rd
                    print("perf: missed frames at the frame budget: render distance \(rd) for now (chosen \(gov.chosen))")
                    g.onToast?("Render distance \(rd) for now, to keep the frame rate")
                case .raise(let rd):
                    g.world.renderDistance = rd
                    print("perf: frame headroom: render distance back up to \(rd) (chosen \(gov.chosen))")
                    g.onToast?(rd == gov.chosen ? "Render distance back to \(rd)" : "Render distance back up to \(rd)")
                default: break
                }
                g.rdGovernor = gov
            } else if let gov = g.rdGovernor, gov.lowered {
                g.setRenderDistance(gov.chosen)          // the option was turned off: back to the player's choice
            }
        }
        // Render distance changes (pause menu, the guard) are logged so a device log can be split by distance.
        if let g = game, g.world.renderDistance != loggedRD {
            loggedRD = g.world.renderDistance
            print("perf: render distance \(loggedRD)")
        }
        frames = 0; missed = 0; busyFrames = 0; sumCPU = 0; sumTick = 0; sumRecord = 0; sumGPU = 0; worstFrame = 0; worstTickAny = 0
        since = now
    }
}
