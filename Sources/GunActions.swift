import Foundation
import simd

// D7 working actions. In the headset (swing play) three guns need their action worked between shots, by hand:
//   Kessel rifle      the bolt     the off hand to the gun and a grip: up, back, forward, down
//   Brecher shotgun   the pump     the off hand to the gun and a grip racks the fore-end
//   Sechser six-iron  the hammer   the off hand to the gun and a grip fans the hammer back
// A trigger on an unworked action clicks and says what it wants. The shotgun also loads shell by shell: each shell
// taken from the belt (the VR hip reach, or the timed reload one shell at a time) puts one in the tube, and a trigger
// pulled mid-reload fires what is loaded. Seated, Reclined and flat-screen play keep the self-working actions (the
// shortcut): `manual` is off there.
// P301 (Oct 15 12:03, 12:05: "the pistol, I should be able to cock it like a real gun"): pistols have a slide. Firing the
// last round locks it back (the drawn slide sits back, the trigger only clicks); a magazine from the hip goes into the
// locked gun (VRReload) and the off hand grabs the slide's rear serrations, pulls it back and lets go to chamber a round.
// Racked on an empty magazine it locks back again and the trigger still dry-clicks.
enum GunActions {
    enum Action { case none, bolt, pump, hammer, slide }
    static var manual = false                         // QuestControls: on in swing play
    static var cocked = true                          // the held gun's action is worked (a round up, the hammer back)
    static var cycles = 0                             // (tests)

    static func action(_ gi: Int) -> Action {
        switch gi {
        case Guns.kessel: return .bolt
        case Guns.shotgun: return .pump
        case Guns.revolver: return .hammer
        case Guns.pistol: return .slide                      // P301 (a): the self-loading pistols (the Falke; the Hagel is retired)
        default: return .none
        }
    }
    static func shellByShell(_ gi: Int) -> Bool { gi == Guns.shotgun }

    // A gun taken in hand comes up ready (the holster and the sling carry it worked); P301: an empty pistol comes up with
    // its slide locked back.
    static func drawn(_ gi: Int = -1, rounds: Int = 1) {
        cocked = !(manual && gi >= 0 && action(gi) == .slide && rounds <= 0)
        slideHeld = false; slidePull = 0
    }

    // After a shot (`left`: rounds still in the gun). P301: a pistol's slide cycles itself; only the last round locks it back.
    static func fired(_ gi: Int, left: Int = 1) {
        guard manual && action(gi) != .none else { return }
        if action(gi) != .slide || left <= 0 { cocked = false }
    }

    // Before a shot: false while the action wants working (a trigger press clicks and says so).
    static func ready(_ g: Game, _ gi: Int, pressed: Bool) -> Bool {
        if cocked || !manual || action(gi) == .none { cocked = true; return true }
        if pressed && action(gi) == .slide {
            // P301 (b): the slide is back, nothing chambered: a dry click and a dead tick in the hand (no words; the
            // drawn slide sits back).
            g.sfx(.gun(7), 0.8)
            dryAt = g.clock
            return false
        }
        if pressed {
            g.sfx(.gun(7), 0.5)              // P300 (b): the dead click is the cue; no how-to toast
        }
        return false
    }

    // The off hand worked the action. True when it did something.
    @discardableResult
    static func work(_ g: Game) -> Bool {
        guard let gi = g.heldGun, !cocked, action(gi) != .none, action(gi) != .slide else { return false }   // (a slide is pulled: rack)
        cocked = true
        cycles += 1
        g.sfx(.gun(14), action(gi) == .hammer ? 0.45 : 0.8)
        return true
    }

    // MARK: P301 the pistol slide, racked by hand

    enum SlideEvent { case none, grabbed, back, chambered, home }
    static var slideHeld = false                      // the off hand holds the slide
    static var slidePull: Float = 0                   // 0 home ... 1 fully back, while held
    static var slideMax: Float = 0                    // the furthest it went this grab
    static var slideFrom = V3(0, 0, 0)                // the hand where it took the slide
    static var dryAt: Double = -10                    // (b) the last dry click (the controls tick the gun hand)
    static var racks = 0                              // (tests)
    static let travel: Float = 0.055                  // m of hand pull for the full stroke (the drawn gun is 3.2x)
    static let grabLocked: Float = 0.13, grabHome: Float = 0.08     // m from the drawn serrations

    // How far back the slide is drawn (0 home, 1 back): locked back, or where the hand has it.
    static func slideDrawn(_ gi: Int) -> Float {
        guard action(gi) == .slide else { return 0 }
        if manual && !cocked { return 1 }
        return slideHeld ? slidePull : 0
    }

    // (a) The off hand at the slide: a grip press near the rear serrations (`serrations`, world) takes it, the pull is
    // measured back along the barrel (`forward`), and letting go past most of the stroke sends it home. A locked slide
    // takes a short tug (the slingshot release); a slide at home wants the full stroke. Racking a chambered pistol
    // just cycles it (no round is lost). Every handgun with a slide, in swing play only.
    static func slideTick(_ g: Game, hand: V3, grip: Bool, gripWas: Bool, serrations: V3?, forward: V3) -> SlideEvent {
        guard manual, let gi = g.heldGun, action(gi) == .slide, g.alive, !g.arms.magInHand, let at = serrations else {
            slideHeld = false; slidePull = 0
            return .none
        }
        if !slideHeld {
            let reach: Float = cocked ? grabHome : grabLocked
            guard grip && !gripWas && simd_length(hand - at) < reach else { return .none }
            slideHeld = true; slideFrom = hand; slidePull = cocked ? 0 : 1; slideMax = 0
            return .grabbed
        }
        let back: Float = simd_dot(slideFrom - hand, forward) / travel
        let wasFull = slideMax >= 1
        slideMax = max(slideMax, back)
        slidePull = cocked ? max(0, min(1, back)) : 1
        if grip {
            if !wasFull && slideMax >= 1 { g.sfx(.gun(15), 0.35); return .back }     // all the way back: the stop rings
            return .none
        }
        // Let go.
        slideHeld = false; slidePull = 0
        guard slideMax >= (cocked ? 0.8 : 0.3) else { return .none }               // not pulled far enough: nothing moves
        racks += 1
        if g.held.tag > 0 {
            cocked = true
            g.sfx(.gun(14), 0.7)                                                    // home on a round
            return .chambered
        }
        cocked = false                                                              // an empty magazine: it locks back again
        g.sfx(.gun(7), 0.45)
        return .home
    }
}
