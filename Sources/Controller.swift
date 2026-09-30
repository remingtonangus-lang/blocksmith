import Foundation
import GameController
import CoreHaptics
import simd

// Game controller hub: hotplugging (connect / disconnect toasts, pausing when the pad drops out mid-game),
// which device the player used last (so prompts show pad glyphs or key caps), rumble, and a simulated pad
// that the test harness drives.
final class PadManager {
    static let shared = PadManager()

    private(set) var controller: GCController?
    var simulated: PadSnapshot?          // harness input; replaces the real pad while set
    private(set) var usingPad = false    // the last input came from a controller
    var onConnect: ((String) -> Void)?
    var onDisconnect: ((String, Bool) -> Void)?   // name, whether the player was using it
    private var started = false
    private var haptics: CHHapticEngine?
    private var hapticsFailed = false
    private var lastRumble: Double = 0
    var rumbleLog: [Float] = []
    var disconnectedAt: Double?          // game clock when the active pad dropped out (pause-menu notice)
    var clock: () -> Double = { 0 }          // harness: strengths of requested rumbles (kept short)

    var connected: Bool { simulated != nil || controller != nil }
    var name: String {
        if simulated != nil { return "Test Pad" }
        return controller?.vendorName ?? "Controller"
    }
    // 0...1, nil when unknown (wired pads, older systems).
    var battery: Float? {
        guard let b = controller?.battery, b.batteryState != .unknown else { return nil }
        return b.batteryLevel
    }

    func start() {
        guard !started else { return }
        started = true
        GCController.shouldMonitorBackgroundEvents = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            guard let self, let c = n.object as? GCController, c.extendedGamepad != nil else { return }
            let had = self.controller != nil
            self.pick()
            if !had || self.controller === c { self.onConnect?(c.vendorName ?? "Controller") }
        }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] n in
            guard let self, let c = n.object as? GCController else { return }
            let wasActive = self.controller === c, wasUsing = self.usingPad
            self.pick()
            if wasActive {
                self.haptics = nil
                self.disconnectedAt = self.clock()
                self.onDisconnect?(c.vendorName ?? "Controller", wasUsing)
            }
        }
        nc.addObserver(forName: .GCControllerDidBecomeCurrent, object: nil, queue: .main) { [weak self] _ in self?.pick() }
        pick()
    }

    private func pick() {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        let cur = GCController.current
        let next = (cur?.extendedGamepad != nil ? cur : nil) ?? pads.first
        if next !== controller {
            if controller == nil && next != nil { usingPad = true }   // a pad just arrived: show its buttons
            controller = next
            haptics = nil
            hapticsFailed = false
            controller?.playerIndex = .index1
        }
        if controller == nil { usingPad = false }
    }

    private(set) var lastRaw = PadSnapshot()   // physical buttons this frame / last frame (button mapping capture)
    private(set) var prevRaw = PadSnapshot()

    // This frame's pad state with the button mapping applied (nil when no pad).
    func read() -> PadSnapshot? {
        guard let raw = readRaw() else { prevRaw = lastRaw; lastRaw = PadSnapshot(); return nil }
        prevRaw = lastRaw
        lastRaw = raw
        return PadMap.apply(raw)
    }

    private func readRaw() -> PadSnapshot? {
        if let s = simulated { return s }
        if !started, controller == nil { controller = GCController.current ?? GCController.controllers().first }
        guard let c = controller ?? GCController.current, let g = c.extendedGamepad else { return nil }
        var p = PadSnapshot()
        p.lx = g.leftThumbstick.xAxis.value
        p.ly = g.leftThumbstick.yAxis.value
        p.rx = g.rightThumbstick.xAxis.value
        p.ry = g.rightThumbstick.yAxis.value
        p.lt = g.leftTrigger.value
        p.rt = g.rightTrigger.value
        p.a = g.buttonA.isPressed
        p.b = g.buttonB.isPressed
        p.x = g.buttonX.isPressed
        p.y = g.buttonY.isPressed
        p.lb = g.leftShoulder.isPressed
        p.rb = g.rightShoulder.isPressed
        p.l3 = g.leftThumbstickButton?.isPressed ?? false
        p.r3 = g.rightThumbstickButton?.isPressed ?? false
        p.menu = g.buttonMenu.isPressed
        p.view = g.buttonOptions?.isPressed ?? false
        p.up = g.dpad.up.isPressed
        p.down = g.dpad.down.isPressed
        p.left = g.dpad.left.isPressed
        p.right = g.dpad.right.isPressed
        if let x = g as? GCXboxGamepad { p.share = x.buttonShare?.isPressed ?? false }
        if Settings.shared.southpaw { (p.lx, p.rx, p.ly, p.ry) = (p.rx, p.lx, p.ry, p.ly) }
        return p
    }

    func forcePad(_ on: Bool) { usingPad = on }

    // Called once per frame with this frame's input: decides whether prompts should show pad glyphs.
    func note(pad p: PadSnapshot?, input: InputState) {
        if let p = p, p.anyActivity { usingPad = true }
        if !input.keys.isEmpty || !input.pressed.isEmpty || input.leftClicked || input.rightClicked || input.mouseMoved
            || abs(input.mouseDX) + abs(input.mouseDY) > 2 || input.scrollSteps != 0 { usingPad = false }
        if p == nil { usingPad = false }
    }

    // Vibrates the active controller: strength 0...1 (scaled by the Rumble option), duration in seconds.
    func rumble(_ strength: Float, _ duration: Float, sharpness: Float = 0.4) {
        let k = strength * Settings.shared.rumble
        guard k > 0.02 else { return }
        if simulated != nil { rumbleLog.append(k); if rumbleLog.count > 32 { rumbleLog.removeFirst() }; return }
        guard let c = controller, !hapticsFailed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRumble < 0.05 && k < 0.6 { return }
        lastRumble = now
        if haptics == nil {
            guard let e = c.haptics?.createEngine(withLocality: .default) else { hapticsFailed = true; return }
            e.isAutoShutdownEnabled = true
            e.resetHandler = { [weak e] in try? e?.start() }
            haptics = e
            do { try e.start() } catch { hapticsFailed = true; haptics = nil; return }
        }
        guard let e = haptics else { return }
        let ev = CHHapticEvent(eventType: .hapticContinuous,
                               parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, k)),
                                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)],
                               relativeTime: 0, duration: TimeInterval(max(0.03, duration)))
        do {
            let pattern = try CHHapticPattern(events: [ev], parameters: [])
            let player = try e.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            try? e.start()
        }
    }
}

// Right-stick look with separate X/Y speeds, a response curve, edge acceleration and aim friction.
final class PadLook {
    private var edgeTime: Float = 0

    // Returns (yaw delta, pitch delta) in radians for this frame.
    func update(rx: Float, ry: Float, dead: Float, sensitivity: Float, invert: Bool, friction: Float, dt: Float) -> V2 {
        let st = Settings.shared
        let v = stick(rx, ry, dead: dead)
        let m = simd_length(v)
        if m > 0.92 { edgeTime += dt } else { edgeTime = max(0, edgeTime - dt * 4) }
        let ramp = min(1, max(0, (edgeTime - 0.25) / 0.6))
        let boost = 1 + st.lookAccel * ramp * 1.2
        let k = sensitivity * friction
        let yaw = -v.x * 3.4 * dt * k * st.lookX * boost
        let pitch = v.y * 2.6 * dt * k * st.lookY * (invert ? -1 : 1) * (0.5 + 0.5 * boost)
        return V2(yaw, pitch)
    }
}

// Maps game sounds to controller rumble, so every hit, explosion and broken block is felt as well as heard.
enum Feedback {
    static func sound(_ g: Game, _ s: Snd, _ v: Float, at pos: V3?) {
        var near: Float = 1
        if let p = pos {
            let d = simd_length(p - g.player.eye)
            near = max(0, 1 - d / 12)
        }
        Subtitles.shared.add(g, s, at: pos)
        Tutorial.sound(g, s, near: near > 0.55)
        let pm = PadManager.shared
        guard pm.connected && pm.usingPad && Settings.shared.rumble > 0 else { return }
        switch s {
        case .hurt: pm.rumble(0.8, 0.18, sharpness: 0.6)
        case .explode: pm.rumble(max(0.25, near), 0.45, sharpness: 0.2)
        case .thunder: pm.rumble(0.35, 0.5, sharpness: 0.1)
        case .breakBlock: if near > 0.55 { pm.rumble(0.35, 0.06, sharpness: 0.7) }
        case .attack: pm.rumble(0.3, 0.05, sharpness: 0.8)
        case .bow: pm.rumble(0.4, 0.08, sharpness: 0.6)
        case .land: pm.rumble(0.5 * v, 0.1, sharpness: 0.3)
        case .levelUp: pm.rumble(0.4, 0.25, sharpness: 0.5)
        case .dig: if near > 0.55 { pm.rumble(0.15, 0.03, sharpness: 0.9) }
        case .pickup: pm.rumble(0.1, 0.03, sharpness: 0.9)
        case .eat: pm.rumble(0.12, 0.05, sharpness: 0.3)
        case .fireworkBlastLarge, .witherSpawn, .raidHorn: pm.rumble(0.5 * max(0.3, near), 0.4, sharpness: 0.2)
        default: break
        }
    }
}

extension Feedback {
    static var heartTimer: Double = 0
    // Per frame: a heartbeat pulse while health is low in survival.
    static func tick(_ g: Game) {
        guard g.survival, g.alive, g.health <= 4, g.menu == nil, !g.paused else { heartTimer = 0; return }
        if g.clock - heartTimer > 1.1 {
            heartTimer = g.clock
            let pm = PadManager.shared
            guard pm.usingPad else { return }
            pm.rumble(0.35, 0.07, sharpness: 0.2)
        }
    }
}
