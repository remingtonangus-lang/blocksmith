import Foundation
import simd

// P159 (Oct 13: "two-handed aiming: put the left hand on the gun's front grip and hold the left trigger to aim it like
// a real gun"). With a long gun (rifle, carbine, shotgun, machine gun: CapitalArms.models[gi].shouldered) in the
// aiming hand, the other hand held out ahead of it along the barrel (15-75 cm in front, within 12 cm of the barrel
// line) with its trigger held braces the gun: the aim runs from the rear hand through the front hand, as a real
// rifle points between the hands, and the kick halves. Lowering either hand or letting go of the trigger ends it.
enum VRTwoHand {
    static let near: Float = 0.15, far: Float = 0.75, offLine: Float = 0.12

    // The braced aim direction, or nil when the front hand isn't on the barrel line or its trigger is up.
    static func braced(rear: V3, rearForward: V3, front: V3, frontTrigger: Float, shouldered: Bool) -> V3? {
        guard shouldered, frontTrigger > 0.5 else { return nil }
        let d = front - rear
        let along = simd_dot(d, rearForward)
        guard along > near && along < far else { return nil }
        guard simd_length(d - rearForward * along) < offLine else { return nil }
        return simd_normalize(d)
    }
}

extension Game {
    // Recoil scale for the held gun: halved while braced with both hands (Ballistics fireHeldGun).
    var twoHandRecoil: Float { vrTwoHanded ? 0.5 : 1 }
}
