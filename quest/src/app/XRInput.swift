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
