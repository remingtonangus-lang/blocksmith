import AppKit
import GameController
import simd

enum Key {
    static let a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2, f: UInt16 = 3, w: UInt16 = 13, e: UInt16 = 14, q: UInt16 = 12
    static let enter: UInt16 = 36, arrowLeft: UInt16 = 123, arrowRight: UInt16 = 124, arrowDown: UInt16 = 125, arrowUp: UInt16 = 126
    static let space: UInt16 = 49, esc: UInt16 = 53, f3: UInt16 = 99
    static let leftBracket: UInt16 = 33, rightBracket: UInt16 = 30
    static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1...9
}

// Written by GameView's event handlers, read and cleared by Game.tick once per frame.
final class InputState {
    var keys = Set<UInt16>()
    var pressed = Set<UInt16>()
    var typed = ""                 // printable characters typed this frame (text fields)
    var mouseDX: Float = 0
    var mouseDY: Float = 0
    var leftDown = false
    var rightDown = false
    var leftClicked = false
    var rightClicked = false
    var middleClicked = false
    var scrollSteps = 0
    var scrollAccum: CGFloat = 0
    var shift = false
    var control = false
    var captured = false
    var uiMode = false          // a menu (inventory) owns the mouse: clicks/moves go to the HUD
    var mouseX: Float = 0       // drawable pixels, origin top-left
    var mouseY: Float = 0
    var mouseMoved = false

    func down(_ k: UInt16) -> Bool { keys.contains(k) }
    func tapped(_ k: UInt16) -> Bool { pressed.contains(k) }

    func endFrame() {
        pressed.removeAll(keepingCapacity: true)
        if !typed.isEmpty { typed = "" }
        mouseDX = 0
        mouseDY = 0
        leftClicked = false
        rightClicked = false
        middleClicked = false
        scrollSteps = 0
        mouseMoved = false
    }

    func releaseAll() {
        keys.removeAll()
        leftDown = false
        rightDown = false
        shift = false
        control = false
    }
}

struct PadSnapshot {
    var lx: Float = 0, ly: Float = 0, rx: Float = 0, ry: Float = 0
    var lt: Float = 0, rt: Float = 0
    var a = false, b = false, x = false, y = false
    var lb = false, rb = false, l3 = false, r3 = false
    var menu = false, view = false
    var up = false, down = false, left = false, right = false
}

func readPad() -> PadSnapshot? {
    guard let c = GCController.current ?? GCController.controllers().first,
          let g = c.extendedGamepad else { return nil }
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
    return p
}

// Radial deadzone with a gentle response curve for fine aiming.
func stick(_ x: Float, _ y: Float, dead: Float = 0.15) -> V2 {
    let v = V2(x, y)
    let m = simd_length(v)
    if m < dead { return .zero }
    let n = min(1, (m - dead) / (1 - dead))
    return v / m * (n * n * 0.6 + n * 0.4)
}
