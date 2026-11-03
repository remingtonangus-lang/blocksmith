import Foundation
import simd

// P159 (Oct 13: "two-handed aiming: put the left hand on the gun's front grip and hold the left trigger to aim it like
// a real gun"). With a long gun (rifle, carbine, shotgun, machine gun: CapitalArms.models[gi].shouldered) in the
// aiming hand, the other hand held out ahead of it along the barrel (15-75 cm in front, within 12 cm of the barrel
// line) with its trigger held braces the gun: the aim runs from the rear hand through the front hand, as a real
// rifle points between the hands, and the kick halves. Lowering either hand or letting go of the trigger ends it.
enum VRTwoHand {
    // P504 (Nov 1 07:41:52, "it's too hard to grab onto this gun with my other hand for aiming purposes"; 08:03:22,
    // "Can't seem to grab the Donnerkeil service weapon with my left hand to help aim"): the front hand had to close
    // within 12 cm of the rear hand's ray, while a hand round a foregrip sits under the barrel; it takes the gun within
    // 26 cm of that line now, anywhere from 12 cm to 95 cm ahead, on a half squeeze of the grip or the trigger (and the
    // aim keeps the offset it was taken at, so the gun doesn't jump: QuestControls).
    static let near: Float = 0.12, far: Float = 0.95, offLine: Float = 0.26

    // The braced aim direction, or nil when the front hand isn't on the barrel line or its trigger is up.
    static func braced(rear: V3, rearForward: V3, front: V3, frontTrigger: Float, shouldered: Bool) -> V3? {
        guard shouldered, frontTrigger > 0.4 else { return nil }
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
