import AppKit
import MetalKit
import GameController

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

final class GameView: MTKView {
    var input: InputState!
    var onEscape: (() -> Void)?
    var onClickWhileFree: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with e: NSEvent) {
        if e.modifierFlags.contains(.command) { super.keyDown(with: e); return }
        if e.keyCode == Key.esc { if !e.isARepeat { onEscape?() }; return }
        if !e.isARepeat { input.pressed.insert(e.keyCode) }
        input.keys.insert(e.keyCode)
        if input.uiMode, let c = e.characters { input.typed += c.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0.isPunctuation || $0 == " " || $0.isSymbol) } }
        if input.uiMode && e.keyCode == 51 { input.typed += "\u{8}" }
    }
    override func keyUp(with e: NSEvent) { input.keys.remove(e.keyCode) }
    override func flagsChanged(with e: NSEvent) {
        input.shift = e.modifierFlags.contains(.shift)
        input.control = e.modifierFlags.contains(.control) || e.modifierFlags.contains(.option)
    }

    private func look(_ e: NSEvent) {
        guard input.captured else { return }
        input.mouseDX += Float(e.deltaX)
        input.mouseDY += Float(e.deltaY)
    }
    private func track(_ e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let sc = window?.backingScaleFactor ?? 2
        input.mouseX = Float(p.x * sc)
        input.mouseY = Float((bounds.height - p.y) * sc)
        input.mouseMoved = true
    }
    override func mouseMoved(with e: NSEvent) { track(e); look(e) }
    override func mouseDragged(with e: NSEvent) { track(e); look(e) }
    override func rightMouseDragged(with e: NSEvent) { look(e) }
    override func otherMouseDragged(with e: NSEvent) { look(e) }

    override func mouseDown(with e: NSEvent) {
        if !input.captured {
            if input.uiMode { track(e); input.leftDown = true; input.leftClicked = true; return }
            onClickWhileFree?()
            return
        }
        // Ctrl-click = right click for trackpad users
        if e.modifierFlags.contains(.control) { input.rightDown = true; input.rightClicked = true; return }
        input.leftDown = true
        input.leftClicked = true
    }
    override func mouseUp(with e: NSEvent) { input.leftDown = false; input.rightDown = false }
    override func rightMouseDown(with e: NSEvent) {
        if !input.captured {
            if input.uiMode { track(e); input.rightDown = true; input.rightClicked = true; return }
            onClickWhileFree?()
            return
        }
        input.rightDown = true
        input.rightClicked = true
    }
    override func rightMouseUp(with e: NSEvent) { input.rightDown = false }
    override func otherMouseDown(with e: NSEvent) { if input.captured { input.middleClicked = true } }

    override func scrollWheel(with e: NSEvent) {
        guard input.captured || input.uiMode else { return }
        let step: CGFloat = e.hasPreciseScrollingDeltas ? 12 : 1
        input.scrollAccum += e.scrollingDeltaY
        while input.scrollAccum >= step { input.scrollAccum -= step; input.scrollSteps += 1 }
        while input.scrollAccum <= -step { input.scrollAccum += step; input.scrollSteps -= 1 }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var view: GameView!
    var game: Game!
    var launched = false
    var renderer: Renderer!
    var save: SaveManager!
    var overlay: NSView!
    var rdButton: NSButton!
    var modeButton: NSButton!
    var labelTimer: Double = 0

    var device: MTLDevice!
    var worldsPanel: NSView?
    lazy var soundEngine: SoundEngine? = SoundEngine()

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        guard let dev = MTLCreateSystemDefaultDevice() else { fatalError("Metal not available") }
        device = dev
        let last = UserDefaults.standard.string(forKey: "lastWorld") ?? "World1"
        makeGame(name: arg("--world") ?? last, seed: UInt64(arg("--seed") ?? ""), survival: nil, difficulty: nil)

        // Load the area around the player up front so the first frame isn't empty.
        _ = game.world.loadSync(center: game.player.pos, radius: min(4, game.world.renderDistance))

        buildWindow()
    }

    // Creates (or loads) a world and its Game.
    func makeGame(name: String, seed: UInt64?, survival: Bool?, difficulty: Int?) {
        save = SaveManager(name: name)
        UserDefaults.standard.set(name, forKey: "lastWorld")
        let meta = save.loadMeta()
        let s = meta?.seed ?? seed ?? UInt64.random(in: 1...UInt64(Int64.max))
        let world = World(seed: s, device: device, save: save)
        game = Game(world: world, save: save, persistent: true)
        let rd = UserDefaults.standard.integer(forKey: "renderDistance")
        if rd >= 2 { world.renderDistance = rd }
        if let m = meta { game.apply(m) } else {
            game.player.pos = game.findSpawn()
            if let sv = survival { game.survival = sv }
            if let d = difficulty { game.difficulty = d }
        }
        game.sound = soundEngine
        game.sound?.volume = game.volumeSetting
        _ = game.world.loadSync(center: game.player.pos, radius: min(4, game.world.renderDistance))
    }

    // Switches to another world in place (saving the current one).
    func switchWorld(name: String, seed: UInt64?, survival: Bool?, difficulty: Int?) {
        game.saveNow()
        makeGame(name: name, seed: seed, survival: survival, difficulty: difficulty)
        view.input = game.input
        do { renderer = try Renderer(device: device, game: game, colorFormat: view.colorPixelFormat) } catch { fatalError("Renderer init failed: \(error)") }
        view.delegate = renderer
        hookGame()
        worldsPanel?.removeFromSuperview()
        worldsPanel = nil
        overlay.removeFromSuperview()
        buildOverlay()
        pauseChanged(true)
        window.title = "Blocksmith — \(name)"
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Blocksmith"
        window.collectionBehavior = [.fullScreenPrimary]
        window.acceptsMouseMovedEvents = true
        window.delegate = self
        window.center()

        view = GameView(frame: window.contentView!.bounds, device: device)
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.preferredFramesPerSecond = NSScreen.main?.maximumFramesPerSecond ?? 60
        view.input = game.input
        do {
            renderer = try Renderer(device: device, game: game, colorFormat: view.colorPixelFormat)
        } catch {
            fatalError("Renderer init failed: \(error)")
        }
        view.delegate = renderer
        window.contentView = view

        buildOverlay()
        hookGame()

        GCController.shouldMonitorBackgroundEvents = true
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            let name = (n.object as? GCController)?.vendorName ?? "Controller"
            self?.toast("\(name) connected")
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.view.isPaused = !self.window.occlusionState.contains(.visible)
        }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        pauseChanged(true)
    }

    func hookGame() {
        view.onEscape = { [weak self] in
            guard let self, let g = self.game else { return }
            if self.worldsPanel != nil { self.hideWorlds(); return }
            if let pm = g.menu as? PauseMenu { if !pm.backPressed() { g.closeMenu() } }
            else if g.menu != nil { g.closeMenu(); g.paused = false }
            else { g.paused = true }
        }
        game.appAction = { [weak self] id in
            guard let self else { return }
            switch id {
            case "fullscreen": self.toggleFS()
            case "quit": self.saveQuit()
            case "worlds": self.showWorlds()
            case _ where id.hasPrefix("play:"): self.switchWorld(name: String(id.dropFirst(5)), seed: nil, survival: nil, difficulty: nil)
            case "newworld": self.switchWorld(name: "World\(Int.random(in: 100...999))", seed: nil, survival: self.game.survival, difficulty: self.game.difficulty)
            case _ where id.hasPrefix("create:"):
                // create:<survival 0/1>:<difficulty>:<name>:<seed text>
                let parts = id.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 5 else { return }
                self.switchWorld(name: parts[3], seed: AppDelegate.seedValue(parts[4]), survival: parts[1] == "1", difficulty: Int(parts[2]) ?? 2)
            default: break
            }
        }
        game.onInventoryChanged = { [weak self] _ in
            guard let self else { return }
            self.game.input.releaseAll()
            self.setCapture(!self.game.paused && !self.game.inventoryOpen)
        }
        view.onClickWhileFree = { [weak self] in if let g = self?.game, g.menu == nil { g.paused = false; self?.setCapture(true) } }
        game.onPauseChanged = { [weak self] p in self?.pauseChanged(p) }
        game.onModeChanged = { [weak self] sv in self?.modeButton.title = sv ? "Mode: Survival" : "Mode: Creative" }
        game.onRenderDistanceChanged = { [weak self] rd in self?.rdButton.title = "Render Distance: \(rd)" }
        renderer.onFrame = { [weak self] dt in self?.frameTick(dt) }
    }

    // MARK: UI

    func label(size: CGFloat, mono: Bool) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: .medium) : NSFont.systemFont(ofSize: size, weight: .semibold)
        l.textColor = .white
        l.maximumNumberOfLines = 0
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.85)
        sh.shadowOffset = NSSize(width: 1, height: -1)
        sh.shadowBlurRadius = 1
        l.shadow = sh
        return l
    }

    func buildOverlay() {
        overlay = NSView(frame: view.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor

        let title = label(size: 40, mono: false)
        title.stringValue = "Blocksmith"
        func button(_ t: String, _ sel: Selector) -> NSButton {
            let b = NSButton(title: t, target: self, action: sel)
            b.bezelStyle = .rounded
            b.controlSize = .large
            b.widthAnchor.constraint(equalToConstant: 260).isActive = true
            return b
        }
        rdButton = button("Render Distance: \(game.world.renderDistance)", #selector(cycleRD))
        modeButton = button(game.survival ? "Mode: Survival" : "Mode: Creative", #selector(toggleMode))
        let hint = label(size: 12, mono: false)
        hint.alignment = .center
        hint.stringValue = """
        Keyboard: WASD move · Space jump (double-tap: fly) · Shift sneak/descend · Ctrl sprint · F fly
        Left click attack/mine · Right click use/place/eat · Middle click pick · 1–9 / scroll slot · E inventory · Q drop · L advancements · F3 debug · Esc pause
        Controller: LS move · RS look · A jump · B sneak · L3 sprint · RT attack/mine · LT use/place · LB/RB slot · Y / View inventory · X pick
        D-pad ↓ drop · ↑ fly · Menu pause   (paused: A resume · X game mode · D-pad ←→ render distance)
        Menus: click / right-click / shift-click (controller: A / X / Y) · number keys swap with the hotbar · B / E / Esc close
        """
        let stack = NSStackView(views: [title,
                                        button("Back to Game", #selector(resume)),
                                        rdButton,
                                        modeButton,
                                        button("Difficulty: \(Game.difficultyNames[game.difficulty])", #selector(cycleDifficulty)),
                                        button("FOV: \(Int(game.fovSetting))", #selector(cycleFOV)),
                                        button("Mouse Sensitivity: \(Int(game.sensitivity * 100))%", #selector(cycleSens)),
                                        button("Volume: \(Int(game.volumeSetting * 100))%", #selector(cycleVolume)),
                                        button("Advancements (L)", #selector(openAdvancements)),
                                        button("Worlds...", #selector(showWorlds)),
                                        button("Toggle Fullscreen", #selector(toggleFS)),
                                        button("Save and Quit", #selector(saveQuit)),
                                        hint])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(24, after: title)
        stack.setCustomSpacing(24, after: stack.views[11])
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])
        view.addSubview(overlay)
    }

    @objc func resume() { game.paused = false }
    @objc func cycleRD() { game.cycleRenderDistance() }
    @objc func toggleMode() { game.toggleMode() }
    @objc func toggleFS() { window.toggleFullScreen(nil) }
    @objc func cycleFOV(_ sender: NSButton) {
        let opts: [Float] = [60, 70, 80, 90, 100, 110]
        game.fovSetting = opts[((opts.firstIndex(of: game.fovSetting) ?? 1) + 1) % opts.count]
        sender.title = "FOV: \(Int(game.fovSetting))"
    }
    @objc func cycleSens(_ sender: NSButton) {
        let opts: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
        game.sensitivity = opts[((opts.firstIndex(of: game.sensitivity) ?? 2) + 1) % opts.count]
        sender.title = "Mouse Sensitivity: \(Int(game.sensitivity * 100))%"
    }
    @objc func cycleVolume(_ sender: NSButton) {
        let opts: [Float] = [0, 0.25, 0.5, 0.8, 1]
        game.volumeSetting = opts[((opts.firstIndex(of: game.volumeSetting) ?? 3) + 1) % opts.count]
        sender.title = "Volume: \(Int(game.volumeSetting * 100))%"
    }
    @objc func openAdvancements() {
        game.paused = false
        game.openMenu(AdvancementMenu(game: game))
    }
    @objc func cycleDifficulty(_ sender: NSButton) {
        game.difficulty = (game.difficulty + 1) % 4
        sender.title = "Difficulty: \(Game.difficultyNames[game.difficulty])"
    }

    // MARK: Worlds screen

    @objc func showWorlds() {
        worldsPanel?.removeFromSuperview()
        let panel = NSView(frame: overlay.bounds)
        panel.autoresizingMask = [.width, .height]
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        let title = label(size: 30, mono: false)
        title.stringValue = "Worlds"
        var views: [NSView] = [title]
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Blocksmith/Worlds")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        for n in names {
            let b = NSButton(title: "Play \(n)", target: self, action: #selector(playWorld(_:)))
            b.bezelStyle = .rounded; b.controlSize = .large
            b.identifier = NSUserInterfaceItemIdentifier(n)
            b.widthAnchor.constraint(equalToConstant: 320).isActive = true
            views.append(b)
        }
        let nameField = NSTextField(string: "World\(names.count + 1)")
        nameField.placeholderString = "World name"
        nameField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        nameField.identifier = NSUserInterfaceItemIdentifier("newName")
        let seedField = NSTextField(string: "")
        seedField.placeholderString = "Seed (blank = random, text is hashed)"
        seedField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        seedField.identifier = NSUserInterfaceItemIdentifier("newSeed")
        let mode = NSPopUpButton(frame: .zero, pullsDown: false)
        mode.addItems(withTitles: ["Survival", "Creative"])
        mode.identifier = NSUserInterfaceItemIdentifier("newMode")
        let diff = NSPopUpButton(frame: .zero, pullsDown: false)
        diff.addItems(withTitles: Game.difficultyNames)
        diff.selectItem(at: 2)
        diff.identifier = NSUserInterfaceItemIdentifier("newDifficulty")
        let create = NSButton(title: "Create New World", target: self, action: #selector(createWorld(_:)))
        create.bezelStyle = .rounded; create.controlSize = .large
        let back = NSButton(title: "Back", target: self, action: #selector(hideWorlds))
        back.bezelStyle = .rounded
        views += [nameField, seedField, mode, diff, create, back]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: panel.centerXAnchor), stack.centerYAnchor.constraint(equalTo: panel.centerYAnchor)])
        overlay.addSubview(panel)
        worldsPanel = panel
        overlay.isHidden = false
        setCapture(false)
    }
    @objc func hideWorlds() { worldsPanel?.removeFromSuperview(); worldsPanel = nil; overlay.isHidden = true }
    @objc func playWorld(_ sender: NSButton) {
        guard let n = sender.identifier?.rawValue else { return }
        switchWorld(name: n, seed: nil, survival: nil, difficulty: nil)
    }
    @objc func createWorld(_ sender: NSButton) {
        guard let panel = worldsPanel else { return }
        func find<T: NSView>(_ id: String) -> T? { panel.subviews.flatMap { ($0 as? NSStackView)?.views ?? [] }.first { $0.identifier?.rawValue == id } as? T }
        let fieldName = (find("newName") as NSTextField?)?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        let name = fieldName.isEmpty ? "World\(Int.random(in: 100...999))" : fieldName.replacingOccurrences(of: "/", with: "-")
        let seed = AppDelegate.seedValue((find("newSeed") as NSTextField?)?.stringValue ?? "")
        let survival = (find("newMode") as NSPopUpButton?)?.indexOfSelectedItem != 1
        let diff = (find("newDifficulty") as NSPopUpButton?)?.indexOfSelectedItem ?? 2
        switchWorld(name: name, seed: seed, survival: survival, difficulty: diff)
    }
    // Seed text -> seed: numbers as they are, other text via a stable 64-bit FNV-1a hash, empty = random.
    static func seedValue(_ text: String) -> UInt64? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if let v = UInt64(t) { return v }
        if let v = Int64(t) { return UInt64(bitPattern: v) }
        var h: UInt64 = 0xcbf29ce484222325
        for b in t.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }
    @objc func saveQuit() { game.saveNow(); NSApp.terminate(nil) }

    func pauseChanged(_ paused: Bool) {
        // The pause screen is drawn in-game (PauseMenu); the AppKit overlay only hosts the Worlds panel.
        overlay.isHidden = worldsPanel == nil
        if paused && game.menu == nil {
            let pm = PauseMenu(game: game)
            if !launched { pm.page = .title; pm.build(); launched = true }
            game.openMenu(pm)
        }
        setCapture(!paused && !game.inventoryOpen)
        view.preferredFramesPerSecond = paused ? 30 : (NSScreen.main?.maximumFramesPerSecond ?? 60)
        if paused { game.input.releaseAll() }
        window.makeFirstResponder(view)
    }

    func setCapture(_ on: Bool) {
        guard on != game.input.captured else { return }
        game.input.captured = on
        if on {
            let f = window.convertToScreen(view.convert(view.bounds, to: nil))
            let mainH = NSScreen.screens.first?.frame.height ?? f.maxY
            CGWarpMouseCursorPosition(CGPoint(x: f.midX, y: mainH - f.midY))
            CGAssociateMouseAndMouseCursorPosition(0)
            NSCursor.hide()
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
        }
        game.input.mouseDX = 0
        game.input.mouseDY = 0
    }

    func toast(_ s: String) { game.onToast?(s) }

    func frameTick(_ dt: Double) {}

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Blocksmith", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        let fs = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fs)
        viewItem.submenu = viewMenu
        NSApp.mainMenu = main
    }

    // MARK: Lifecycle

    func windowDidResignKey(_ notification: Notification) {
        if game != nil && !game.paused { game.paused = true }
    }
    func windowDidEnterFullScreen(_ notification: Notification) { window.makeFirstResponder(view) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        setCapture(false)
        game?.saveNow()
    }
}

extension Int {
    var mod4: Int { ((self % 4) + 4) % 4 }
}
