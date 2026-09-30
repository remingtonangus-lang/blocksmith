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
    var renderer: Renderer!
    var save: SaveManager!
    var overlay: NSView!
    var rdButton: NSButton!
    var modeButton: NSButton!
    var labelTimer: Double = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal not available") }

        save = SaveManager(name: arg("--world") ?? "World1")
        let meta = save.loadMeta()
        let seed = meta?.seed ?? UInt64(arg("--seed") ?? "") ?? UInt64.random(in: 1...UInt64(Int64.max))
        let world = World(seed: seed, device: device, save: save)
        game = Game(world: world, save: save, persistent: true)
        if let m = meta { game.apply(m) } else { game.player.pos = game.findSpawn() }
        game.sound = SoundEngine()

        // Load the area around the player up front so the first frame isn't empty.
        _ = game.world.loadSync(center: game.player.pos, radius: min(4, game.world.renderDistance))

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
        view.onEscape = { [weak self] in
            guard let g = self?.game else { return }
            if g.menu != nil && !g.paused { g.closeMenu() } else { g.paused.toggle() }
        }
        game.onInventoryChanged = { [weak self] _ in
            guard let self else { return }
            self.game.input.releaseAll()
            self.setCapture(!self.game.paused && !self.game.inventoryOpen)
        }
        view.onClickWhileFree = { [weak self] in self?.game.paused = false }
        game.onPauseChanged = { [weak self] p in self?.pauseChanged(p) }
        game.onModeChanged = { [weak self] sv in self?.modeButton.title = sv ? "Mode: Survival" : "Mode: Creative" }
        game.onRenderDistanceChanged = { [weak self] rd in self?.rdButton.title = "Render Distance: \(rd)" }
        renderer.onFrame = { [weak self] dt in self?.frameTick(dt) }

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
        Left click break · Right click place · Middle click pick · 1–9 / scroll slot · [ ] change block · F3 debug · Esc pause
        Controller: LS move · RS look · A jump · B sneak · L3 sprint · RT break · LT place · LB/RB slot
        D-pad ↑↓ change block · X pick · Y fly · View inventory · Menu pause   (paused: A resume · X game mode · D-pad ←→ render distance)
        Survival: hearts, hunger, fall damage, drowning; hold an Apple and right click / LT to eat
        Inventory (E / View): D-pad, left stick, arrows or mouse to choose · A / Enter / click puts it in the selected slot · LB/RB or 1–9 pick slot · B / E / Esc close
        """
        let stack = NSStackView(views: [title,
                                        button("Back to Game", #selector(resume)),
                                        rdButton,
                                        modeButton,
                                        button("Toggle Fullscreen", #selector(toggleFS)),
                                        button("Save and Quit", #selector(saveQuit)),
                                        hint])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(24, after: title)
        stack.setCustomSpacing(24, after: stack.views[5])
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
    @objc func saveQuit() { game.saveNow(); NSApp.terminate(nil) }

    func pauseChanged(_ paused: Bool) {
        overlay.isHidden = !paused
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
