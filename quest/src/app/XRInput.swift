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
    var input: XRInput { xr }
    var fps: Double { stats.fps }
}
