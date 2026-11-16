import Foundation
import simd

// What the rig and the controls read from the headset each frame. XRSession provides it on the Quest; SimXR (the
// headless controls test, quest/src/test/QuestSim.swift) scripts it.
protocol XRInput: AnyObject {
    var hands: [XRHand] { get }
    var headPos: V3 { get }
    var headRot: simd_quatf { get }
    var floorSpace: Bool { get }
    func eyePose(_ i: Int) -> (V3, simd_quatf)
    func fovTangents(_ i: Int) -> (Float, Float, Float, Float)
    func haptic(_ hand: Int, amplitude: Float, seconds: Float, frequency: Float)
}

extension XRSession: XRInput {}

// What QuestControls needs from the app (QuestApp on the headset, the sim harness in tests).
protocol QuestHost: AnyObject {
    var input: XRInput { get }
    var rig: QuestRig { get }
    var scene: SceneRenderer { get }
    var fps: Double { get }
}

extension QuestApp: QuestHost {
    var input: XRInput { handed }                 // S7/S8: the swapped / tracking-filtered hands (QuestHands.swift)
    var fps: Double { stats.fps }
}

// P303 (Oct 15 12:09, 18:13, 18:28-18:42: "the grip sticks: the game acts as if I'm still holding it", "sometimes can't
// grip left, sometimes can't grip right"). The grips and triggers are analog; a fixed 0.6 cut with no hysteresis read a
// relaxed hand whose fingers still rest on the grip (0.6-0.7) as held forever, so a held creature or body stayed in the
// hand and the next squeeze never counted (no release came between), and a value hovering round the cut flickered.
// A button now goes down past 0.55 (and 0.3 above the lowest value since it last let go, so a squeeze from a resting
// hand counts), and lets go 0.3 under its peak (at most 0.3): a released grip always releases.
struct VRButton {
    static let pressAt: Float = 0.55, releaseAt: Float = 0.3, travel: Float = 0.3, pressCap: Float = 0.9
    private(set) var down = false
    private(set) var pressed = false              // went down this frame
    private(set) var released = false             // let go this frame
    private var peak: Float = 0, trough: Float = 0
    var value: Float = 0

    mutating func update(_ raw: Float) {
        let v = raw.isFinite ? min(1, max(0, raw)) : 0
        value = v
        pressed = false; released = false
        if down {
            peak = max(peak, v)
            if v < max(VRButton.releaseAt, peak - VRButton.travel) { down = false; released = true; trough = v }
        } else {
            trough = min(trough, v)
            if v > max(VRButton.pressAt, min(VRButton.pressCap, trough + VRButton.travel)) { down = true; pressed = true; peak = v }
        }
    }
    // The analog value as the game's 0.5 cut should see it (a trigger fed to the pad).
    var padValue: Float { down ? max(value, 0.6) : min(value, 0.45) }
}

// Ledger 190 (Nov 15 20:39:04: "the waypoint ... gets dropped like a ways under where it's pointing"; 20:40:44 "the
// waypoints aren't easy to set"): pulling a trigger tips the controller down, so by the time the pull passes
// VRButton.pressAt the laser has dropped below what he aimed at. A press aims where the laser was when the pull began:
// the newest frame with the trigger under startBelow, at most maxBack frames back (~0.2 s), unless the laser moved more
// than maxShift px in between (a sweep he meant). The shift holds while the trigger stays down, so a held press doesn't
// count the dip as a drag either.
struct PullAim {
    static let startBelow: Float = 0.15, maxBack = 15, maxShift: Float = 90
    private var at = [V2](repeating: V2(-1, -1), count: 16), trig = [Float](repeating: 0, count: 16)
    private var head = 0, count = 0
    private(set) var shift = V2.zero

    mutating func record(_ p: V2, trigger v: Float) {
        head = (head + 1) % 16; at[head] = p; trig[head] = v; count = min(count + 1, 16)
    }
    mutating func reset() { count = 0; shift = .zero }

    // The press frame (just recorded): where the pull began, and the shift from the laser now to it.
    mutating func press() -> V2? {
        guard count > 0 else { return nil }
        let now = at[head]
        var start = now
        for k in 1..<min(count, PullAim.maxBack + 1) {
            let i = (head - k + 16) % 16
            start = at[i]
            if trig[i] < PullAim.startBelow { break }
        }
        let d = start - now
        shift = abs(d.x) + abs(d.y) > PullAim.maxShift ? .zero : d
        return now + shift
    }
    mutating func release() { shift = .zero }
}
