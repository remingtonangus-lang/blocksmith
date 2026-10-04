import Foundation

// The Quest's PadManager (the Mac's lives in Sources/Controller.swift behind canImport(GameController)): the
// Touch controllers arrive as a PadSnapshot (QuestInput maps them, see quest/src/xr/QuestInput.swift), so the
// game's controller code (Halo-style actions, menus, prompts, rumble feedback) runs unchanged. Rumble requests
// go to `haptic`, which the XR layer forwards to both controllers (xrApplyHapticFeedback).
final class PadManager {
    static let shared = PadManager()

    enum Style { case xbox, playstation, nintendo }
    private(set) var style: Style = .xbox
    var simulated: PadSnapshot?          // harness input; replaces the Touch controllers while set
    var touch: PadSnapshot?              // this frame's Touch-controller pad (set by the XR layer before Game.tick)
    private(set) var usingPad = true     // the Quest has no keyboard: prompts always show controller buttons
    var onConnect: ((String) -> Void)?
    var onDisconnect: ((String, Bool) -> Void)?
    var rumbleLog: [Float] = []
    var disconnectedAt: Double?
    var clock: () -> Double = { 0 }
    // (strength 0...1, seconds, sharpness 0...1) -> controllers. Set by the XR layer.
    var haptic: ((Float, Float, Float) -> Void)?

    var connected: Bool { simulated != nil || touch != nil }
    let hasSystemPad = true
    var name: String { simulated != nil ? "Test Pad" : "Touch Controllers" }
    var battery: Float? { nil }

    func start() {}

    private(set) var lastRaw = PadSnapshot()
    private(set) var prevRaw = PadSnapshot()
    private(set) var lastMapped: PadSnapshot?

    func read() -> PadSnapshot? {
        guard let raw = simulated ?? touch else { prevRaw = lastRaw; lastRaw = PadSnapshot(); lastMapped = nil; return nil }
        prevRaw = lastRaw
        lastRaw = raw
        lastMapped = PadMap.apply(raw)
        return lastMapped
    }

    func forcePad(_ on: Bool) { usingPad = true }

    func note(pad p: PadSnapshot?, input: InputState) { usingPad = true }

    private var lastRumble: Double = 0
    func rumble(_ strength: Float, _ duration: Float, sharpness: Float = 0.4) {
        let k = strength * Settings.shared.rumble
        guard k > 0.02 else { return }
        if simulated != nil { rumbleLog.append(k); if rumbleLog.count > 32 { rumbleLog.removeFirst() }; return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRumble < 0.05 && k < 0.6 { return }
        lastRumble = now
        haptic?(min(1, k), max(0.03, duration), sharpness)
    }
}
