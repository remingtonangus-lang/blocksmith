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
    private var spaceWarpPass: SpaceWarpPass?         // P381 step 9
    private var lastAppToWorld: (rotation: simd_quatf, translation: V3)?
    private var lastDisplayTime: XrTime = 0
    // P403 (the sub-pixel exception of P375): canopies past this many chunks are meshed "fast" (no faces between
    // leaf blocks). At 6 chunks (96 blocks) a leaf block is ~8 px tall on the Quest 3 and a leaf texture's holes are
    // under a pixel, so the inner faces could only show through holes the mip chain has already closed.
    static var leafNear = 4
    private(set) var dynRes = DynamicResolution()       // P403 7b
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
    private var loadTitle = ""                     // P293 (a): the world being opened (or saved), shown on the loading scene
    private var loadStart = CFAbsoluteTimeGetCurrent()
    let stats = FrameStats()
    var platformName = "Quest"
    static var debugClearOnly = ProcessInfo.processInfo.environment["QUEST_CLEAR_ONLY"] != nil

    init(xr: XRSession) throws {
        self.xr = xr
        handed = HandedInput(raw: xr)
        if QuestBuild.meshHash != "dev" { MeshCache.buildKey = QuestBuild.meshHash }     // (P400 step 2)
        setenv("BLOCKSMITH_TEXRES", "\(QuestSettings.textureRes)", 1)
        device = QuestDevice(xr.vk)
        sharedSystemDevice = device
        xr.resolutionScale = QuestSettings.resolutionScale
        try xr.createSwapchain()
        scene = try SceneRenderer(ctx: xr.vk, device: device, views: 2, colorFormat: xr.colorFormat, foveated: xr.foveated, spaceWarp: xr.spaceWarp)
        if xr.spaceWarp {
            spaceWarpPass = try SpaceWarpPass(scene: scene, mvImages: xr.mvImages, depthImages: xr.swDepthImages,
                                              width: xr.mvWidth, height: xr.mvHeight, depthFormat: xr.swDepthFormat)
        }
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
        // P339 (Remington, Oct 18 20:10: "everything out to the 24-chunk view looks exactly like the land near him... no
        // coarse 2-block-lattice LOD, no blur or compression"): every chunk in view is meshed at full detail (no far
        // level, no "fast" leaves). The cost is met by not simulating past the active distance, culling and merged
        // draws, not by lowering far detail; his headset captures decide if it holds 72 fps.
        World.lodNear = 99
        World.leafNear = QuestApp.leafNear
        PlaytestChecklist.spaceWarp = (get: { QuestSettings.spaceWarp ? (QuestSettings.spaceWarpActive ? "On" : "On (next launch)") : (QuestSettings.spaceWarpActive ? "Off (next launch)" : "Off") },
                                       toggle: { QuestSettings.spaceWarp.toggle() })        // P399 (7)
        PauseMenu.viewFixed = true                 // P339: the view distance is fixed (QuestSettings.viewDistance)
        stats.lowerRate = { [weak xr] in
            guard let x = xr, x.refreshRate > 72.5, x.setRefreshRate(72) else { return false }
            return true
        }
        stats.recordStages = { [weak self] in self?.worldRenderer?.takeStages() ?? "" }
        stats.dynResProbe = { [weak self] in self?.dynRes.lastProbe ?? 0 }
        stats.perfNotice = { [weak self] in self?.xr.perfNoticeLine ?? "" }
        startLoading()
    }

    // MARK: Loading

    private func status(_ s: String, _ p: Float) {
        loadLock.lock(); loadStatus = s; loadProgress = p; loadLock.unlock()
        print("load: \(s) (\(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - loadStart)) s)")
    }

    private func startLoading(_ req: WorldRequest = WorldRequest()) {
        loadStart = CFAbsoluteTimeGetCurrent()
        let old = savingGame
        // P293 (a): the loading scene names the world: the one being saved on a quit, else the one opening (a join's
        // name arrives with the host's welcome).
        let title = exitWhenSaved ? (old?.save?.dir.lastPathComponent ?? "")
            : req.join != nil ? "" : (req.name ?? UserDefaults.standard.string(forKey: "lastWorld") ?? "Quest World")
        loadLock.lock(); loadProgress = 0; loadStatus = "Starting"; loadTitle = title; loadLock.unlock()
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
                    g.world.meshCache?.flush()           // (P400: the view's meshes on disk for the next launch)
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
                game.rdGovernor = RenderDistanceGovernor(chosen: game.world.activeDistance)
                loadLock.lock(); loadTitle = gu.worldName; loadLock.unlock()
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
        world.renderDistance = QuestSettings.startView
        let game = Game(world: world, save: save, persistent: true)
        Game.oceanSwellDrawn = true                  // boats ride the drawn swell (Weather.swift OceanSwell)
        // The save's state or the new world's options, then the terrain option, before the first meshes (questcheck tests this).
        req.setUp(game, meta: meta)
        // The headset's own setting, not the save's (Game.apply restores the world's saved distance, which held the
        // comfort guard's session-only step-downs: the Oct 9 playtest reopened its world at render distance 5). On
        // game.world: a save made in another dimension reopens there, and `world` is the overworld. Auto Render
        // Distance steps the world below this choice for the session; the save and the options keep the choice.
        game.world.renderDistance = QuestSettings.startView          // P425: Auto View Distance starts where it settled last
        game.world.activeDistance = Game.savedActiveDistance
        game.rdGovernor = RenderDistanceGovernor(chosen: game.world.activeDistance)       // P339: Auto governs the active distance
        stats.viewGov = ViewGovernor(chosen: QuestSettings.renderDistance, current: game.world.renderDistance)
        status("Generating terrain", 0.55)
        _ = game.world.loadSync(center: game.player.pos, radius: min(3, game.world.renderDistance))
        // The horizon ring's first sampling (4225 terrain columns, ~0.1 s on a desktop core) here, not on the first
        // world frame (HorizonRing samples synchronously when it has no ring yet).
        HorizonRing.shared.request(game, eye: game.player.eye)
        // F4: the middle ring's first build (~17k terrain columns) here too, not on the first world frame.
        FarRing.shared.request(game, eye: game.player.eye)
        QuestWarmup.run()
        QuestWarmup.world(game)                      // (P400: the first ticks' rail and base plans)
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
    private var awayStart = 0.0                                          // Q2c-console-44: when the away pause began
    // Q2c-console-44: the pause for the headset taken off, the Meta menu or the session stopping, with its reason.
    private func awayPause(_ g: Game) {
        g.paused = true
        if PauseMenu.autoReason == nil || awayStart == 0 { awayStart = CFAbsoluteTimeGetCurrent() }
        PauseMenu.autoReason = "Paused while you were away"
        (g.menu as? PauseMenu)?.build()
    }
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
            switchWorld(WorldRequest(name: "World\(Rand.int(in: 100...999))", survival: game?.survival, difficulty: game?.diffLevel, smooth: true))   // (PG6: Polygons, even from a block world)
        case _ where id.hasPrefix("netjoin:"):
            switchWorld(WorldRequest(join: String(id.dropFirst(8))))
        case "netleave":
            if let g = game, let gu = g.netGuest { gu.detach(g); gu.clearMirrors(g); g.netGuest = nil }
            switchWorld(WorldRequest())
        case "workshop":
            switchWorld(WorldRequest(name: CircuitWorkshop.worldName, seed: CircuitWorkshop.seed, survival: false, difficulty: 2))
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
                if g.menu == nil && g.credits == nil { awayPause(g) }
                saveNow()
            }
            Thread.sleep(forTimeInterval: 0.02); return true
        }
        QuestEntitlement.poll()                                   // S5 (off until the store app ID is set)
        if QuestEntitlement.denied && !exitWhenSaved {
            game?.onToast?("This copy of Sunderfall isn't linked to your account. Buy it from the store to play.")
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
            // (P381 step 9: with space warp the game draws every other displayed frame, so its step is the time
            // between the frames it draws, not the display's period.)
            let step = xr.spaceWarp && lastDisplayTime > 0 && f.displayTime > lastDisplayTime
                ? Double(f.displayTime - lastDisplayTime) * 1e-9 : (f.period > 0 ? f.period : 1.0 / 72)
            let dt = min(0.1, max(1.0 / 120, step))
            // Ship physics steps once per displayed frame (60 Hz substeps at 72 Hz left one frame in six without a
            // step: the deck and the player riding it juddered against the world).
            let rate = Float(1 / dt)
            if abs(ShipManager.stepRate - rate) > 0.5 { ShipManager.stepRate = rate; ShipManager.stepSlack = 0.2 / rate }
            if f.shouldRender { rig.update(xr: xr, game: g) }
            controls?.update(dt: Float(dt))
            let a = CFAbsoluteTimeGetCurrent()
            // Input focus lost (headset off, the system menu or a dialog up): the world stops and the pause menu is up
            // when the user comes back, so nothing happens to them meanwhile.
            if !xr.focused && wasFocused && g.menu == nil && g.credits == nil { awayPause(g) }
            // Q2c-console-44: back to a game paused while he was away: how long, whether it was saved, and a chime.
            if xr.focused && !wasFocused && PauseMenu.autoReason != nil && awayStart > 0 {
                let secs = CFAbsoluteTimeGetCurrent() - awayStart
                PauseMenu.autoReason = "Paused while you were away" + (secs >= 60 ? " (\(Int(secs / 60)) min)" : "") + (savedAway ? " - your world is saved" : "")
                (g.menu as? PauseMenu)?.build()
                g.sfx(.click, 0.35)
                awayStart = 0
            }
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
                PauseMenu.autoReason = "Paused: the headset lost tracking (light the room or wipe its cameras)"   // Q2c-console-44
                (g.menu as? PauseMenu)?.build()
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
            QuestVideo.collect(began: s)               // P368: voice-note video pictures -> the encoder's queue
            let target = targets[f.imageIndex]
            // P403 7b: dynamic resolution against the drawn frame's budget (twice the display's with space warp); not
            // with foveation (its density map is laid over the whole image) or while the world loads.
            let budget = 1000.0 / Double(max(60, xr.refreshRate)) * (xr.spaceWarp ? 2 : 1)
            scene.viewScale = dynRes.observe(gpuMs: scene.gpuMs, budgetMs: budget,
                                             enabled: QuestSettings.dynamicResolution && !xr.foveated && game != nil && worldRenderer != nil,
                                             fps: Double(xr.refreshRate) / (xr.spaceWarp ? 2 : 1))
            let (viewW, viewH) = scene.viewExtent(target)
            xr.viewExtent = (viewW, viewH)
            let cam = rig.camera(xr: xr, far: farPlane)
            if QuestApp.debugClearOnly {
                scene.beginPass(s, target, clear: V3(0.2, 0.4, 0.8))
            } else if let wr = worldRenderer {
                wr.record(s, target, cam)
            } else {
                recordLoading(s, target, cam)
            }
            vkCmdEndRenderPass(s.cmd)
            if let sw = spaceWarpPass {
                // P381 step 9: this frame's depth and motion vectors for the runtime, and how far the tracking space
                // moved through the world since the last drawn frame (walking, turning, riding), in its own terms.
                sw.record(s, target, mvIndex: xr.mvIndex, depthIndex: xr.swDepthIndex)
                xr.swFar = cam.far > 0 ? cam.far : farPlane
                let now = rig.appToWorld
                if let was = lastAppToWorld {
                    let q = was.rotation.inverse * now.rotation, p = was.rotation.inverse.act(now.translation - was.translation)
                    xr.appSpaceDelta = XrPosef(orientation: XrQuaternionf(x: q.imag.x, y: q.imag.y, z: q.imag.z, w: q.real),
                                               position: XrVector3f(x: p.x, y: p.y, z: p.z))
                }
                lastAppToWorld = now
            }
            // Bug-note screenshot (if one is pending): left eye, HUD panel included, blitted small before release.
            QuestScreenshot.service(s, ctx: xr.vk, image: target.image, format: xr.colorFormat, width: viewW, height: viewH)
            QuestVideo.service(s, ctx: xr.vk, image: target.image, format: xr.colorFormat, width: xr.width, height: xr.height)
            do { try scene.submit(s) } catch { print("submit: \(error)") }
            recordMs = (CFAbsoluteTimeGetCurrent() - a) * 1000
        }
        do { try xr.endFrame(f) } catch { print("xr end frame: \(error)") }
        if f.shouldRender { lastDisplayTime = f.displayTime }
        let now = CFAbsoluteTimeGetCurrent()
        if firstWorldFrames > 0 && game != nil {
            firstWorldFrames -= 1
            print(String(format: "first world frame: cpu %.1f ms (tick %.1f, record %.1f)", (now - t0) * 1000, tickMs, recordMs))
        }
        // F1: a frame over 250 ms goes to hitches.log on the headset (time, split, the tick's slowest stages), so a
        // freeze can be matched to a voice note's timestamp.
        if now - lastFrameTime > 0.25 && game != nil && firstWorldFrames == 0 { logHitch(ms: (now - lastFrameTime) * 1000, tick: tickMs, record: recordMs) }
        // P420: the pause menu's Compute page shows the last moments of play (frozen while a menu is open).
        if let g = game, g.menu == nil, !g.paused, let wr = worldRenderer {
            ComputeCost.frame(frameMs: (now - lastFrameTime) * 1000, cpu: (now - t0) * 1000, tick: tickMs, record: recordMs,
                              gpu: scene.gpuMs, rate: Double(xr.refreshRate), stageNames: WorldRenderer.stageNames, stageMs: wr.stageFrame)
        }
        stats.add(frame: now - lastFrameTime, cpu: (now - t0) * 1000, tick: tickMs, record: recordMs, gpu: scene.gpuMs,
                  target: f.period * (xr.spaceWarp ? 2 : 1), scene: scene, game: game, rate: xr.refreshRate)   // (the drawn frame's budget: P403 7b)
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

    // P293 (Oct 14 19:19 "we need a better loading screen"; Oct 15 11:56 "all these weird blocks floating around"): a calm
    // dawn plain ringed by stepped blue hills, a stone pedestal 2.6 m ahead on which a grass block assembles itself
    // cubelet by cubelet as the load goes on, the game's name and the world's name above it, the bar and the stage
    // under it. No tips (NO TEXT). The whole scene is fixed in the room where he faced when the load began (nothing
    // head-locked, nothing moving but the settling cubelets and the pedestal's slow turn), and the bar eases forward
    // so nothing flickers or jumps back.
    private var loadAnchorFor = -1.0                     // loadStart of the load the anchor was taken for
    private var loadAnchor = V3(0, 0, 0)                 // tracking-space head x/z and eye height at that moment
    private var loadYaw: Float = 0
    private var loadShown: Float = 0                     // the bar's eased progress (never goes back within a load)
    private var loadShownFor = -1.0
    private var loadLastFrame = 0.0
    private var loadSettle = [Float](repeating: -1, count: 27)   // when each cubelet started settling (s into the load)
    private var loadVerts: [SimpleVert] = []

    private func recordLoading(_ s: SceneRenderer.Slot, _ t: RenderTarget, _ cam: EyeCamera) {
        let now = CFAbsoluteTimeGetCurrent()
        let time = Float(now - loadStart)
        // P293 (b): the anchor is taken once per load, on the first frame the head is tracked: where he stands, which
        // way he faces and his eye height then. Everything below is placed in that frame.
        if loadAnchorFor != loadStart && xr.headTracked {
            loadAnchorFor = loadStart
            loadAnchor = V3(rig.trackingHead.x, rig.floorEyeY(xr: xr), rig.trackingHead.z)
            loadYaw = rig.headYaw
        }
        if loadShownFor != loadStart {
            loadShownFor = loadStart
            loadShown = 0
            for i in 0..<loadSettle.count { loadSettle[i] = -1 }
        }
        loadLock.lock(); let p = max(0, min(1, loadProgress)); let what = loadStatus; let title = loadTitle; loadLock.unlock()
        // P293 (b): the shown progress eases toward the loader's (about a quarter second) and never steps back.
        let dt = Float(max(0, min(0.1, now - loadLastFrame)))
        loadLastFrame = now
        loadShown = max(loadShown, loadShown + (p - loadShown) * min(1, dt * 4))
        let shown = loadShown

        let fwd = V3(-sinf(loadYaw), 0, -cosf(loadYaw))
        let right = V3(cosf(loadYaw), 0, -sinf(loadYaw))
        let back = -fwd
        let up = V3(0, 1, 0)
        let headY = loadAnchor.y
        let floorY: Float = xr.floorSpace ? 0 : headY - 1.6
        // Camera-relative = tracking position - head.
        let origin = V3(loadAnchor.x, 0, loadAnchor.z) - rig.trackingHead
        func place(_ l: V3) -> V3 { origin + right * l.x + up * l.y + back * l.z }

        // A calm dawn: deep blue overhead, warm haze at the horizon, the low sun glowing behind the hills ahead.
        var u = FrameUniforms()
        u.viewProj = (cam.viewProj[0], cam.viewProj.count > 1 ? cam.viewProj[1] : cam.viewProj[0])
        u.invViewProj = (u.viewProj.0.inverse, u.viewProj.1.inverse)
        let haze = V3(0.84, 0.74, 0.64)
        u.fogColor = V4(haze, 1000)
        u.params = V4(2000, 0.7, Float(now.truncatingRemainder(dividingBy: 1000)), 0)
        u.sunDir = V4(simd_normalize(fwd * 0.97 + V3(0, 0.1, 0)), 1)
        u.zenith = V4(0.2, 0.33, 0.62, 0)
        u.horizon = V4(haze, 0.5)
        u.misc = V4(1, 1, scene.linearOutput ? 2.2 : 1, 0)
        scene.setUniforms(s, u)
        scene.resetScratch()
        scene.beginPass(s, t, clear: haze)

        var v: [SimpleVert] = []
        swap(&v, &loadVerts)
        v.removeAll(keepingCapacity: true)
        func tri(_ a: V3, _ b: V3, _ c: V3, _ ca: V4, _ cb: V4, _ cc: V4) {
            v.append(SimpleVert(pos: V4(place(a), 1), color: ca))
            v.append(SimpleVert(pos: V4(place(b), 1), color: cb))
            v.append(SimpleVert(pos: V4(place(c), 1), color: cc))
        }
        func quad(_ a: V3, _ b: V3, _ c: V3, _ d: V3, _ col: V4) {
            tri(a, b, c, col, col, col); tri(a, c, d, col, col, col)
        }
        func mixc(_ a: V3, _ b: V3, _ k: Float) -> V4 { V4(a + (b - a) * k, 1) }

        // The ground: a meadow disc fading into the haze toward the hills (which hide its edge).
        let meadow = V3(0.3, 0.45, 0.25)
        let radii: [Float] = [0, 4, 14, 34, 80]
        let segs = 48
        for r in 0..<(radii.count - 1) {
            let r0 = radii[r], r1 = radii[r + 1]
            let c0 = mixc(meadow, haze, r0 / 90), c1 = mixc(meadow, haze, r1 / 90)
            for k in 0..<segs {
                let a0 = Float(k) / Float(segs) * 2 * .pi, a1 = Float(k + 1) / Float(segs) * 2 * .pi
                let p00 = V3(sinf(a0) * r0, floorY, cosf(a0) * r0), p01 = V3(sinf(a1) * r0, floorY, cosf(a1) * r0)
                let p10 = V3(sinf(a0) * r1, floorY, cosf(a0) * r1), p11 = V3(sinf(a1) * r1, floorY, cosf(a1) * r1)
                tri(p00, p10, p11, c0, c1, c1)
                if r0 > 0 { tri(p00, p11, p01, c0, c1, c0) }
            }
        }

        // Two rings of stepped hills (2 m terraces, the blocky land he is about to walk into), the far one paler.
        let hillCols = 72
        for ring in 0..<2 {
            let far = ring == 1
            let radius: Float = far ? 96 : 60
            let depth: Float = far ? 14 : 8
            let tint = far ? mixc(V3(0.34, 0.42, 0.5), haze, 0.62) : mixc(V3(0.24, 0.36, 0.3), haze, 0.45)
            func height(_ k: Int) -> Float {
                let a = Float(k) / Float(hillCols) * 2 * .pi
                let w1: Float = 3 * sinf(a * 3 + (far ? 2.1 : 0.4))
                let w2: Float = 2 * sinf(a * 7 + (far ? 0.7 : 1.9))
                let w3: Float = 1.5 * sinf(a * 13 + 0.3)
                let raw: Float = (far ? 11 : 5) + w1 + w2 + w3
                let step: Float = (raw / 2).rounded() * 2
                return floorY + max(far ? 6 : 4, step)
            }
            let front = tint * V4(0.8, 0.8, 0.8, 1), side = tint * V4(0.68, 0.68, 0.68, 1)
            for k in 0..<hillCols {
                let a0 = Float(k) / Float(hillCols) * 2 * .pi, a1 = Float(k + 1) / Float(hillCols) * 2 * .pi
                let h = height(k), hl = height((k + hillCols - 1) % hillCols), hr = height((k + 1) % hillCols)
                let n0 = V3(sinf(a0), 0, cosf(a0)), n1 = V3(sinf(a1), 0, cosf(a1))
                let i0 = n0 * radius, i1 = n1 * radius, o0 = n0 * (radius + depth), o1 = n1 * (radius + depth)
                let lo = floorY - 1
                quad(V3(i0.x, lo, i0.z), V3(i1.x, lo, i1.z), V3(i1.x, h, i1.z), V3(i0.x, h, i0.z), front)
                quad(V3(i0.x, h, i0.z), V3(i1.x, h, i1.z), V3(o1.x, h, o1.z), V3(o0.x, h, o0.z), tint)
                // The terrace steps between neighbouring columns.
                if hl < h { quad(V3(i0.x, hl, i0.z), V3(o0.x, hl, o0.z), V3(o0.x, h, o0.z), V3(i0.x, h, i0.z), side) }
                if hr < h { quad(V3(i1.x, hr, i1.z), V3(o1.x, hr, o1.z), V3(o1.x, h, o1.z), V3(i1.x, h, i1.z), side) }
            }
        }

        // Boxes (the pedestal and the cubelets), turned by `spin` about a vertical axis through `pivot`.
        let shades: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
        let CT = Mesher.cornerTable
        func box(_ c: V3, _ half: V3, _ col: V4, pivot: V3 = V3(0, 0, 0), spin: Float = 0) {
            let cs = cosf(spin), sn = sinf(spin)
            var q = [V3](repeating: V3(0, 0, 0), count: 4)
            for f in 0..<6 {
                let sh = col * V4(shades[f], shades[f], shades[f], 1)
                for k in 0..<4 {
                    let ci = (f * 4 + k) * 3
                    let lx: Float = (Float(CT[ci]) * 2 - 1) * half.x
                    let ly: Float = (Float(CT[ci + 1]) * 2 - 1) * half.y
                    let lz: Float = (Float(CT[ci + 2]) * 2 - 1) * half.z
                    let d = c + V3(lx, ly, lz) - pivot
                    q[k] = pivot + V3(d.x * cs + d.z * sn, d.y, d.z * cs - d.x * sn)
                }
                quad(q[0], q[1], q[2], q[3], sh)
            }
        }
        // The pedestal: a stone column from the floor to just under eye level, a darker cap.
        let pz: Float = -2.6
        let top = headY - 0.5
        let colH = max(0.1, top - 0.05 - floorY)
        box(V3(0, floorY + colH / 2, pz), V3(0.22, colH / 2, 0.22), V4(0.56, 0.56, 0.58, 1))
        box(V3(0, top - 0.025, pz), V3(0.28, 0.025, 0.28), V4(0.42, 0.42, 0.45, 1))
        // P293 (a): the brand mark and the in-world progress: a grass block of 27 cubelets that sets itself together
        // bottom layer first, each one lowering gently onto the last as the load passes its share.
        let cell: Float = 0.14
        let spinA = time * 0.12
        let pivot = V3(0, top, pz)
        for i in 0..<27 {
            if shown * 27 >= Float(i) + 0.5 && loadSettle[i] < 0 { loadSettle[i] = time }
            let st = loadSettle[i]
            if st < 0 { continue }
            let x = i % 3, z = (i / 3) % 3, y = i / 9
            let d = min(1, (time - st) / 0.45)
            let e = 1 - d
            let drop: Float = 0.16 * e * e * e
            let tone: Float = 0.94 + 0.12 * Float((i * 37 + 11) % 13) / 13
            let base = y == 2 ? V3(0.36, 0.62, 0.25) : V3(0.52, 0.36, 0.22)
            let cx: Float = (Float(x) - 1) * cell, cz: Float = pz + (Float(z) - 1) * cell
            let cy: Float = top + (Float(y) + 0.5) * cell + drop
            box(V3(cx, cy, cz), V3(1, 1, 1) * (cell / 2 - 0.004), V4(base * tone, 1), pivot: pivot, spin: spinA)
        }

        // Words on a plane 2.3 m ahead, in the game's pixel font drawn as quads (no textures needed, so this shows on the
        // very first launch), white on a dark shadow just behind.
        let tz: Float = -2.3
        func rect(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ dz: Float, _ col: V4) {
            quad(V3(x0, y0, tz + dz), V3(x1, y0, tz + dz), V3(x1, y1, tz + dz), V3(x0, y1, tz + dz), col)
        }
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
        // P402 (3): the two controllers either side of the pedestal with pictures of what each control does (no words).
        for poly in ControllerPicture.build(centreY: headY - 0.12, leftHanded: QuestSettings.leftHanded) {
            let c = poly.pts[0]
            for k in 1..<(poly.pts.count - 1) {
                tri(V3(c.x, c.y, tz + poly.dz), V3(poly.pts[k].x, poly.pts[k].y, tz + poly.dz),
                    V3(poly.pts[k + 1].x, poly.pts[k + 1].y, tz + poly.dz), poly.col, poly.col, poly.col)
            }
        }
        // P293 (a): the game's name, then the world's.
        label("SUNDERFALL", headY + 0.34, 0.011, V4(1, 0.93, 0.74, 1))      // (P340: the game's name)
        if !title.isEmpty { label(title, headY + 0.2, 0.0065, V4(1, 1, 1, 1)) }
        // The bar and the stage with its percent under it.
        let by = headY - 0.62
        rect(-0.6, 0.6, by - 0.035, by + 0.035, 0, V4(0.1, 0.1, 0.12, 1))
        rect(-0.58, -0.58 + 1.16 * max(0.02, shown), by - 0.022, by + 0.022, 0.004, V4(0.45, 0.85, 0.4, 1))
        label("\(what)  \(Int((shown * 100).rounded()))%", by - 0.07, 0.006, V4(1, 1, 1, 1))

        if let off = scene.push(s, v) { scene.drawScratch(s, "simpleSolid", offset: off, count: v.count) }
        swap(&v, &loadVerts)
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

    // P339 (a) (Remington, Oct 16: "the game records its own performance... hey, we've got an issue"): two windows in a
    // row (10 s) missing more than 15% of frames outside menus save a capture beside the voice notes (vn-perf-*.txt:
    // where, distances, CPU/GPU split, the slowest tick stage, record stages, draws and quads, memory; both windows'
    // lines) and give one short sharp buzz on both hands. At most one a 2 minutes.
    private var badWindows = 0, lastCaptureAt = -1e9, prevLine = ""
    static let captureMissFrac = 0.15, captureGap = 120.0
    var viewGov: ViewGovernor?              // P425: Auto View Distance
    var dynResProbe: (() -> Double)?        // P403 step 2: DynamicResolution.lastProbe
    var perfNotice: (() -> String)?         // P403 step 1: XRSession.perfNoticeLine
    private func capture(game: Game?, target: Double, now: Double) {
        defer { prevLine = lastLine }
        guard let g = game, target > 0, frames > 0 else { badWindows = 0; return }
        let bad = Double(missed) > Double(frames) * FrameStats.captureMissFrac && busyFrames * 2 < frames
        badWindows = bad ? badWindows + 1 : 0
        guard badWindows >= 2, now - lastCaptureAt > FrameStats.captureGap else { return }
        let p = g.player.pos, w = g.world
        let biome = g.dim.dim == .overworld ? (w.gen as? WorldGen).map { "\($0.column(Int(p.x), Int(p.z)).biome)" } ?? "-" : "-"
        var t = "perf capture \(Date())\n"
        t += String(format: "where: %@ %.1f %.1f %.1f biome %@, view %d chunks, active %d (chosen %d), %@, riding %@\n",
                    "\(g.dim.dim)", p.x, p.y, p.z, biome, w.renderDistance, w.activeDistance, g.chosenActiveDistance,
                    g.survival ? "survival" : "creative", g.riding.map { "\($0.kind)" } ?? "no")
        t += "window: " + lastLine + "\nbefore: " + prevLine + "\n"
        guard BugNotes.shared.savePerfCapture(t) else { return }
        lastCaptureAt = now; badWindows = 0
        print("perf: capture saved (two slow windows)")
        PadManager.shared.haptic?(0.6, 0.25, 1)
    }

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
        lastLine += " | far ticking \(FarTicks.lastSecond)"                  // P376: things ticking past the active distance (0)
        lastLine += " | eye resolution \(Int((scene.viewScale * 100).rounded()))%"                        // P403 7b (dynamic resolution)
        if let p = dynResProbe?(), p > 0 {                                                                 // P403 step 2: triangles or pixels
            lastLine += String(format: " (10%% fewer pixels gave %.0f%% less gpu: %@)", (1 - p) * 100, p < 0.95 ? "pixel-bound" : "triangle-bound")
        }
        // P403 step 1: clocks and the hottest zone, and the runtime's own performance notices (a throttled headset).
        let clocks = DeviceClocks.line()
        if !clocks.isEmpty { lastLine += " | clocks: " + clocks }
        if let n = perfNotice?(), !n.isEmpty { lastLine += " | runtime performance notice: " + n }
        if let st = recordStages?(), !st.isEmpty { lastLine += " | record ms: " + st }
        print(lastLine)
        capture(game: game, target: target, now: now)
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
                // P339: Auto steps the ACTIVE distance (what moves and thinks); the view distance is never touched, and
                // nothing is said in play (NO TEXT).
                case .lower(let rd):
                    g.world.activeDistance = rd
                    print("perf: missed frames at the frame budget: active distance \(rd) for now (chosen \(gov.chosen))")
                case .raise(let rd):
                    g.world.activeDistance = rd
                    print("perf: frame headroom: active distance back up to \(rd) (chosen \(gov.chosen))")
                default: break
                }
                g.rdGovernor = gov
            } else if let gov = g.rdGovernor, gov.lowered {
                g.setActiveDistance(gov.chosen)          // the option was turned off: back to the player's choice
            }
            // P425: Auto View Distance: the view follows the GPU's frame time under the slider (ViewGovernor.swift).
            if QuestSettings.autoViewDistance, var vg = viewGov, target > 0 {
                if vg.chosen != QuestSettings.renderDistance { vg.setChosen(QuestSettings.renderDistance) }
                let w = ViewGovernor.Window(seconds: now - since, frames: frames, missed: missed, gpuMs: sumGPU / n, budgetMs: target * 1000,
                                            loading: genRate > FrameStats.loadingChunksPerSecond, excused: excused)
                switch vg.observe(w) {
                case .lower(let rd):
                    g.setRenderDistance(rd); g.setActiveDistance(Game.savedActiveDistance); QuestSettings.autoViewLast = rd
                    print(String(format: "perf: gpu %.1f ms at the budget: view distance %d for now (slider %d)", sumGPU / n, rd, vg.chosen))
                case .raise(let rd):
                    g.setRenderDistance(rd); g.setActiveDistance(Game.savedActiveDistance); QuestSettings.autoViewLast = rd
                    print(String(format: "perf: gpu %.1f ms, headroom: view distance up to %d (slider %d)", sumGPU / n, rd, vg.chosen))
                default: break
                }
                viewGov = vg
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
