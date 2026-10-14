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
enum GunActions {
    enum Action { case none, bolt, pump, hammer }
    static var manual = false                         // QuestControls: on in swing play
    static var cocked = true                          // the held gun's action is worked (a round up, the hammer back)
    static var cycles = 0                             // (tests)
    static var lastHint: Double = -10

    static func action(_ gi: Int) -> Action {
        switch gi {
        case Guns.kessel: return .bolt
        case Guns.shotgun: return .pump
        case Guns.revolver: return .hammer
        default: return .none
        }
    }
    static func shellByShell(_ gi: Int) -> Bool { gi == Guns.shotgun }

    // A gun taken in hand comes up ready (the holster and the sling carry it worked).
    static func drawn() { cocked = true }

    // After a shot.
    static func fired(_ gi: Int) { if manual && action(gi) != .none { cocked = false } }

    // Before a shot: false while the action wants working (a trigger press clicks and says so).
    static func ready(_ g: Game, _ gi: Int, pressed: Bool) -> Bool {
        if cocked || !manual || action(gi) == .none { cocked = true; return true }
        if pressed {
            g.sfx(.gun(7), 0.5)
            if g.clock - lastHint > 4 {
                lastHint = g.clock
                switch action(gi) {
                case .bolt: g.onToast?("Work the bolt: off hand to the rifle and grip")
                case .pump: g.onToast?("Rack it: off hand to the fore-end and grip")
                default: g.onToast?("Cock the hammer: off hand to the gun and grip")
                }
            }
        }
        return false
    }

    // The off hand worked the action. True when it did something.
    @discardableResult
    static func work(_ g: Game) -> Bool {
        guard let gi = g.heldGun, !cocked, action(gi) != .none else { return false }
        cocked = true
        cycles += 1
        g.sfx(.gun(14), action(gi) == .hammer ? 0.45 : 0.8)
        return true
    }
}
