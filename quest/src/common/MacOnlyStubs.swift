import Foundation

// The few GameController types Sources/Coop.swift (split-screen co-op) names, for the Quest where GameController
// doesn't exist: no extra controllers are ever connected, so co-op never starts (the Touch controllers are player 1).
final class GCControllerButtonInput {
    var isPressed: Bool { false }
    var value: Float { 0 }
}
final class GCControllerAxisInput { var value: Float { 0 } }
final class GCControllerDirectionPad {
    let xAxis = GCControllerAxisInput(), yAxis = GCControllerAxisInput()
    let up = GCControllerButtonInput(), down = GCControllerButtonInput()
    let left = GCControllerButtonInput(), right = GCControllerButtonInput()
}
final class GCExtendedGamepad {
    let leftThumbstick = GCControllerDirectionPad(), rightThumbstick = GCControllerDirectionPad(), dpad = GCControllerDirectionPad()
    let leftTrigger = GCControllerButtonInput(), rightTrigger = GCControllerButtonInput()
    let buttonA = GCControllerButtonInput(), buttonB = GCControllerButtonInput()
    let buttonX = GCControllerButtonInput(), buttonY = GCControllerButtonInput()
    let leftShoulder = GCControllerButtonInput(), rightShoulder = GCControllerButtonInput()
    let buttonMenu = GCControllerButtonInput()
    var leftThumbstickButton: GCControllerButtonInput? { nil }
    var rightThumbstickButton: GCControllerButtonInput? { nil }
    var buttonOptions: GCControllerButtonInput? { nil }
}
final class GCController {
    static var current: GCController? { nil }
    static func controllers() -> [GCController] { [] }
    var extendedGamepad: GCExtendedGamepad? { nil }
}

// Sources/CustomMusic.swift (the Mac's own-music folder through AVFoundation) has no Quest counterpart yet: the
// sound engine reports no folder, so the soundtrack is always the composed one.
final class CustomMusic {
    var playing: Bool { false }
    var available: Bool { false }
    var summary: String { "not on Quest" }
    var title: String? { nil }
    func scan(force: Bool = false) {}
    func playNext(shuffle: Bool) -> Bool { false }
    func stop() {}
    func restart() {}
}
