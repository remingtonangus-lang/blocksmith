import Foundation
import simd

// S7/S8: the hands as the game sees them. Every reader of the controllers (QuestControls, the bow, reloads, grabs, the
// drawn hands and laser) goes through this layer (QuestHost.input), so:
//  - Dominant Hand: Left swaps the two controllers here: hands[1] (the aiming / gun / laser hand, A and B, the turn
//    stick) is the physical left controller, hands[0] (moving stick, X and Y, the off hand at the hip) the physical
//    right. The Menu button exists only on the physical left controller and stays the logical left hand's. Haptics
//    are sent back to the physical controller of the logical hand.
//  - Controller preset One Hand: the dominant stick also walks (forward / back) while its sideways push still turns,
//    so the game can be played with the dominant controller alone.
//  - Tracking loss: a controller with neither its aim nor its grip pose valid for longer than `lostGrace` is "lost":
//    its buttons, triggers and stick read as released (a controller put down or out of view can't fire, walk or
//    open menus), and QuestControls hides its laser and held item until it is tracked again.
// Allocation-free per frame (the controls are measured by AllocCount in the sim).
final class HandedInput: XRInput {
    let raw: XRInput
    private(set) var hands = [XRHand(), XRHand()]
    private var lostFor: [Float] = [0, 0]           // per physical controller, seconds without a pose
    private(set) var lost = [false, false]           // per logical hand
    static let lostGrace: Float = 0.5
    // Ledger 268 (Nov 17 19:49:32-19:50:33, Creative, his right controller "lost" and "back" every few seconds while he
    // played with the left: "Why is it still breaking stuff?", "Left controller is still hitting shit", sinking 67 -> 59
    // into a dug pit): a controller put down out of view comes back into view lying on something, its trigger pressed
    // by the cushion or the couch, and mined wherever it pointed. A controller back from lost now counts no trigger,
    // grip or button until all of them have been seen let go (a hand picking it up again lets go and presses anew).
    // BS_OLDLOSTARM=1: its inputs count again the moment it is seen.
    static let oldLostArm = Env.all["BS_OLDLOSTARM"] == "1"
    private var mustLetGo = [false, false]          // per physical controller

    init(raw: XRInput) { self.raw = raw }

    var headPos: V3 { raw.headPos }
    var headRot: simd_quatf { raw.headRot }
    var floorSpace: Bool { raw.floorSpace }
    func eyePose(_ i: Int) -> (V3, simd_quatf) { raw.eyePose(i) }
    func fovTangents(_ i: Int) -> (Float, Float, Float, Float) { raw.fovTangents(i) }
    var swapped: Bool { QuestSettings.leftHanded }
    func physical(_ logical: Int) -> Int { swapped ? 1 - logical : logical }
    func haptic(_ hand: Int, amplitude: Float, seconds: Float, frequency: Float) {
        guard hand >= 0 && hand < 2, !lost[hand] else { return }
        // Q2c-console-35: Options' Vibration scales every Touch buzz (0.7, its default, leaves them as tuned; Off stops them).
        let k = amplitude * Settings.shared.rumble / 0.7
        guard k > 0.01 else { return }
        raw.haptic(physical(hand), amplitude: min(1, k), seconds: seconds, frequency: frequency)
    }

    // Once per frame, before anything reads `hands` (QuestControls.update). `walk`: the One Hand remap may take the
    // dominant stick's forward push (not in menus or the weapon wheel, where that stick scrolls and picks).
    func refresh(dt: Float, walk: Bool = true) {
        let src = raw.hands
        guard src.count >= 2 else { return }
        let swap = swapped
        for p in 0..<2 {
            let tracked = src[p].aimValid || src[p].gripValid
            lostFor[p] = tracked ? 0 : lostFor[p] + dt
            if lostFor[p] > HandedInput.lostGrace && !HandedInput.oldLostArm { mustLetGo[p] = true }
            if mustLetGo[p] && tracked {
                let h = src[p]
                if h.trigger < 0.1 && h.squeeze < 0.1 && !h.button1 && !h.button2 && !h.stickClick { mustLetGo[p] = false }
            }
        }
        for l in 0..<2 {
            let p = swap ? 1 - l : l
            var h = src[p]
            h.menu = l == 0 && lostFor[0] <= HandedInput.lostGrace ? src[0].menu : false   // (on the physical left only)
            let gone = lostFor[p] > HandedInput.lostGrace
            if gone {
                h.stick = .zero; h.trigger = 0; h.squeeze = 0; h.stickClick = false
                h.button1 = false; h.button2 = false; h.thumbRest = false
            } else if mustLetGo[p] {
                h.trigger = 0; h.squeeze = 0; h.stickClick = false; h.button1 = false; h.button2 = false
            }
            lost[l] = gone
            hands[l] = h
        }
        // One Hand: the dominant stick walks too (its forward / back push; sideways stays the turn), unless the off-hand
        // stick is in use.
        if walk && QuestSettings.controlPreset == 2 && !lost[1] {
            let d = hands[1].stick
            if simd_length(hands[0].stick) < 0.2 && abs(d.y) > 0.2 && abs(d.y) > abs(d.x) {
                hands[0].stick = V2(0, d.y)
                hands[1].stick = V2(0, 0)
            }
        }
    }
}
