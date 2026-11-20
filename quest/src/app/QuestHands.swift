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
        if QuestSettings.controlPreset == 2 && !HandedInput.oldOneHand && !lost[1] { oneHand(dt: dt, walk: walk) }
    }

    // Ledger 388 (Nov 20, Remington: "Build it properly now"; Neon's controls review: One Hand only remapped walking, so
    // use, the inventory, pause and reload stayed on the off controller). With One Hand the dominant controller alone
    // plays the game; its presses are given to the off hand's controls below QuestControls, so every reader sees them
    // (Dominant Hand: Left mirrors it like the rest). On top of the walking stick:
    //   grip       a tap steps the hotbar (as before); held 0.3 s it is the use trigger: place, eat, open, talk, board,
    //              nock and draw the bow (QuestControls.bowUpdate draws it with the hold), held as long as the grip is
    //   stick in   a tap (stick near the centre) is X: pick block / reload; held 0.3 s it is itself: the weapon wheel
    //   A + B      together: a tap pauses; held 0.5 s, the inventory (Y held)
    // A (jump; a double tap flies), B (tap: sneak / back; held: drop) and the trigger are as ever. In menus only A + B
    // is taken (the pause and the inventory close as they open). BS_OLDONEHAND=1: the stick alone, as before.
    static let oldOneHand = Env.all["BS_OLDONEHAND"] == "1"
    static let gripUseAfter: Float = 0.3, clickHoldAfter: Float = 0.3, chordHoldAfter: Float = 0.5
    private var gripT: Float = 0, gripPulse = 0
    private var clickT: Float = 0, clickPulse = 0, clickPushed = false
    private var chordT: Float = 0, chord = false, menuPulse = 0
    private(set) var gripUse = false                  // (QuestControls: the bow draws with this hold)
    private func oneHand(dt: Float, walk: Bool) {
        var d = hands[1], o = hands[0]
        // A + B together (either order): suppressed from A and B until both are let go.
        if d.button1 && d.button2 { chord = true }
        if chord {
            chordT += dt
            if chordT >= HandedInput.chordHoldAfter { o.button2 = true }
            if !d.button1 && !d.button2 {
                if chordT < HandedInput.chordHoldAfter { menuPulse = 3 }
                chord = false; chordT = 0
            }
            d.button1 = false; d.button2 = false
        }
        if menuPulse > 0 { o.menu = true; menuPulse -= 1 }
        if walk {
            // The grip: held back until it is a tap (given back as three frames of grip: the hotbar steps) or a hold (use).
            let g = d.squeeze > 0.5
            if g {
                gripT += dt
                if gripT >= HandedInput.gripUseAfter { gripUse = true }
            } else {
                if gripT > 0 && !gripUse { gripPulse = 3 }
                gripT = 0; gripUse = false
            }
            d.squeeze = gripPulse > 0 ? 1 : 0
            if gripPulse > 0 { gripPulse -= 1 }
            if gripUse { o.trigger = max(o.trigger, 1) }
            // The stick click: a tap near the centre is X; a click with the stick pushed (walking) or held is the click.
            if d.stickClick {
                if clickT == 0 { clickPushed = simd_length(raw.hands[physical(1)].stick) > 0.45 }
                clickT += dt
                if !clickPushed && clickT < HandedInput.clickHoldAfter { d.stickClick = false }
            } else {
                if clickT > 0 && !clickPushed && clickT < HandedInput.clickHoldAfter { clickPulse = 3 }
                clickT = 0
            }
            if clickPulse > 0 { o.button1 = true; clickPulse -= 1 }
        } else {
            gripT = 0; gripUse = false; gripPulse = 0; clickT = 0; clickPulse = 0
        }
        hands[1] = d; hands[0] = o
    }
}
