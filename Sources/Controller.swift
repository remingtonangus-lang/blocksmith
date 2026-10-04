import Foundation
#if canImport(GameController)
import GameController
import CoreHaptics
#endif
import simd

#if canImport(GameController)      // the Quest port's PadManager reads the Touch controllers (quest/src)
// Game controller hub: hotplugging (connect / disconnect toasts, pausing when the pad drops out mid-game),
// which device the player used last (so prompts show pad glyphs or key caps), rumble, and a simulated pad
// that the test harness drives.
final class PadManager {
    static let shared = PadManager()

    enum Style { case xbox, playstation, nintendo }
    private(set) var controller: GCController?
    private(set) var style: Style = .xbox          // which button art prompts use
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

    var connected: Bool { simulated != nil || controller != nil || USBGamepads.shared.active }
    // A pad macOS drives itself (GameController); the USB GIP fallback (USBGamepad.swift) stays out of its way.
    // (Set on the main thread in pick(); the USB queue only reads it.)
    private(set) var hasSystemPad = false
    var name: String {
        if simulated != nil { return "Test Pad" }
        if controller == nil && USBGamepads.shared.active { return USBGamepads.shared.deviceName }
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
        // Wired Xbox One / Series pads no macOS driver claims (vendor class 0xFF, e.g. PowerA 20D6:2074).
        let usb = USBGamepads.shared
        usb.onConnect = { [weak self] n in
            guard let self else { return }
            if self.controller == nil { self.usingPad = true }
            self.onConnect?(n)
        }
        usb.onDisconnect = { [weak self] n in
            guard let self, self.controller == nil else { return }
            let wasUsing = self.usingPad
            self.disconnectedAt = self.clock()
            self.onDisconnect?(n, wasUsing)
        }
        usb.start()
    }

    private func pick() {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        hasSystemPad = !pads.isEmpty
        let cur = GCController.current
        let next = (cur?.extendedGamepad != nil ? cur : nil) ?? pads.first
        if next !== controller {
            if controller == nil && next != nil { usingPad = true }   // a pad just arrived: show its buttons
            controller = next
            if let g = next?.extendedGamepad, g is GCDualSenseGamepad || g is GCDualShockGamepad { style = .playstation }
            else if let c = next, (c.productCategory.contains("Switch") || c.productCategory.contains("Joy-Con")) { style = .nintendo }
            else { style = .xbox }
            haptics = nil
            hapticsFailed = false
            controller?.playerIndex = .index1
        }
        if controller == nil { usingPad = false }
    }

    private(set) var lastRaw = PadSnapshot()   // physical buttons this frame / last frame (button mapping capture)
    private(set) var prevRaw = PadSnapshot()
    private(set) var lastMapped: PadSnapshot?   // this frame's mapped pad (nil = none); for code outside Game.tick's p/q

    // This frame's pad state with the button mapping applied (nil when no pad).
    func read() -> PadSnapshot? {
        guard let raw = readRaw() else { prevRaw = lastRaw; lastRaw = PadSnapshot(); lastMapped = nil; return nil }
        prevRaw = lastRaw
        lastRaw = raw
        lastMapped = PadMap.apply(raw)
        return lastMapped
    }

    private func readRaw() -> PadSnapshot? {
        if let s = simulated { return s }
        if !started, controller == nil { controller = GCController.current ?? GCController.controllers().first }
        guard let c = controller ?? GCController.current, let g = c.extendedGamepad else {
            guard var u = USBGamepads.shared.snapshot() else { return nil }
            if Settings.shared.southpaw { (u.lx, u.rx, u.ly, u.ry) = (u.rx, u.lx, u.ry, u.ly) }
            return u
        }
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
        if controller == nil && USBGamepads.shared.active { USBGamepads.shared.rumble(k, max(0.03, duration)); return }
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
#endif

// Right-stick look with separate X/Y speeds, a response curve, edge acceleration and aim friction.
final class PadLook {
    private var edgeTime: Float = 0

    // Returns (yaw delta, pitch delta) in radians for this frame. Modelled on Halo Infinite's default controller
    // feel: look sensitivity 1-10 per axis (default 3), a power response curve, a centre dead zone and a max input
    // threshold (outer dead zone) on the look stick, and look acceleration 0-5 (default 3) that ramps the turn rate up
    // while the stick is held at its edge.
    func update(rx: Float, ry: Float, dead: Float, sensitivity: Float, invert: Bool, friction: Float, dt: Float) -> V2 {
        let st = Settings.shared
        let raw = V2(rx, ry), m0 = simd_length(raw)
        let live = max(0.05, 1 - st.lookDead - st.lookOuter)
        guard m0 >= st.lookDead else { edgeTime = max(0, edgeTime - dt * 4); return .zero }
        let n = min(1, (m0 - st.lookDead) / live)
        let curved: Float
        switch st.lookCurve {
        case 1: curved = n                                   // linear
        case 2: curved = n * n * n                           // precise (cubic)
        default: curved = n * n                              // default: power curve, fine aim near the centre
        }
        let v = raw / m0 * curved
        // Acceleration: once the stick reaches its outer edge, the turn rate climbs after a short delay.
        if n >= 0.99 { edgeTime += dt } else { edgeTime = max(0, edgeTime - dt * 4) }
        let ramp = min(1, max(0, (edgeTime - 0.1) / 0.5))
        let boost = 1 + st.lookAccel * 0.2 * ramp
        let k = sensitivity * friction
        let yawRate = PadLook.rate(st.lookX)               // radians per second at full deflection
        let pitchRate = PadLook.rate(st.lookY) * 0.75
        let yaw = -v.x * yawRate * dt * k * boost
        let pitch = v.y * pitchRate * dt * k * (invert ? -1 : 1) * (1 + (boost - 1) * 0.3)
        return V2(yaw, pitch)
    }

    // Sensitivity 1-10 to a full-deflection turn rate: 3 (the default) is about 170 degrees per second.
    static func rate(_ sens: Float) -> Float { (50 + 40 * max(0.5, sens)) * .pi / 180 }
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
        case .explode:
            // Felt out to ~40 blocks (cannon fire, distant blasts), strongest close by.
            let d = pos.map { simd_length($0 - g.player.eye) } ?? 0
            if d < 40 { pm.rumble(max(0.2, 1 - d / 16) * min(1, 0.5 + v * 0.5), 0.45, sharpness: 0.2) }
        case .thunder: pm.rumble(0.35, 0.5, sharpness: 0.1)
        case .breakBlock: if near > 0.55 { pm.rumble(0.35, 0.06, sharpness: 0.7) }
        case .place: if near > 0.55 { pm.rumble(0.14, 0.035, sharpness: 0.8) }
        case .attack: pm.rumble(0.3, 0.05, sharpness: 0.8)
        case .bow: pm.rumble(0.4, 0.08, sharpness: 0.6)
        case .land: pm.rumble(0.5 * v, 0.1, sharpness: 0.3)
        case .levelUp: pm.rumble(0.4, 0.25, sharpness: 0.5)
        case .gun(let k):
            // Own shots (at the player) by gun: rifle, chatter, shotgun, farsight, launcher, arc; 9 = deck gun boom.
            let mine = pos == nil || near > 0.9
            let table: [Int: (Float, Float, Float)] = [0: (0.35, 0.05, 0.8), 1: (0.25, 0.035, 0.9), 2: (0.85, 0.12, 0.35), 3: (0.9, 0.14, 0.4),
                                                      4: (0.8, 0.22, 0.2), 5: (0.5, 0.12, 0.7), 7: (0.12, 0.03, 1), 9: (0.9, 0.3, 0.15)]
            if let t = table[k] { pm.rumble(mine ? t.0 : t.0 * near * 0.6, t.1, sharpness: t.2) }
        case .gunReload: if pos == nil || near > 0.9 { pm.rumble(0.18, 0.04, sharpness: 0.9) }   // magazine seated
        case .bulletWhizz: if near > 0.7 { pm.rumble(0.15, 0.04, sharpness: 0.9) }               // a near miss
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
    static var lastShipVel: [Int: V3] = [:]
    static var lastShipBlocks: [Int: Int] = [:]
    static var lastClock: Double = 0
    // Vehicle impacts: a sudden change of the ship's velocity while aboard (crash, landing, ramming), and
    // hull hits (the vessel losing blocks to shells or explosions).
    static func vehicleTick(_ g: Game) {
        guard let s = g.world.ships.aboard ?? g.world.ships.pilot else { lastShipVel.removeAll(); lastShipBlocks.removeAll(); return }
        let dt = max(0.004, Float(g.clock - lastClock))
        lastClock = g.clock
        if let v0 = lastShipVel[s.id] {
            let accel = simd_length(s.vel - v0) / dt
            if accel > 18 { PadManager.shared.rumble(min(1, (accel - 18) / 50 + 0.3), 0.18, sharpness: 0.25) }
        }
        if let b0 = lastShipBlocks[s.id], s.blockCount < b0 {
            let lost = Float(b0 - s.blockCount)
            PadManager.shared.rumble(min(1, 0.35 + lost / 20), 0.25, sharpness: 0.3)
        }
        lastShipVel = [s.id: s.vel]
        lastShipBlocks = [s.id: s.blockCount]
    }
    // Per frame: a heartbeat pulse while health is low in survival.
    static func tick(_ g: Game) {
        if PadManager.shared.usingPad && Settings.shared.rumble > 0 { vehicleTick(g) }
        guard g.survival, g.alive, g.health <= 4, g.menu == nil, !g.paused else { heartTimer = 0; return }
        if g.clock - heartTimer > 1.1 {
            heartTimer = g.clock
            let pm = PadManager.shared
            guard pm.usingPad else { return }
            pm.rumble(0.35, 0.07, sharpness: 0.2)
        }
    }
}
