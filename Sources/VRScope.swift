import Foundation
import simd

// G21 (from the Oct 11 playtest P32: "the Farsight has no VR scope"): raising the Farsight Rifle to the eye zooms the
// view 4x and closes it down to a round lens with a crosshair. The view stays on the head (turning the head turns the
// view, so the zoom doesn't fight the inner ear); the crosshair sits where the hand's ray, the line the round flies
// (P32/P43), meets the view, so it marks the impact exactly even when the rifle is held a little off the eye line.
// The Quest app eases it in and out (QuestControls.scopeT), narrows both eyes' projections (QuestRig.zoom) and draws the
// lens mask (QuestControls.drawScope).
enum VRScope {
    static let gun = "gun_sniper"
    static let zoom: Float = 4
    static let eyeReach: Float = 0.24          // the rifle's rear (the hand) within this of the head centre
    static let alignCos: Float = cosf(25 * .pi / 180)
    static let lensRadius: Float = 0.62        // the clear lens, in normalized device units (1 = the view's half width)

    // Is the rifle up at the eye: the aiming hand near the head and pointing roughly where the head looks.
    static func raised(heldKey: String, head: V3, headForward: V3, aimOrigin: V3, aimDir: V3) -> Bool {
        heldKey == gun && simd_length(aimOrigin - head) < eyeReach && simd_dot(simd_normalize(aimDir), simd_normalize(headForward)) > alignCos
    }

    // The zoom for an eased amount t (0 off ... 1 fully up).
    static func zoom(_ t: Float) -> Float { 1 + (zoom - 1) * max(0, min(1, t)) }

    // Where the round lands, in normalized device coordinates of a camera-relative view-projection (nil behind the eye).
    static func reticle(viewProj: float4x4, center: V3, aimOrigin: V3, aimDir: V3) -> V2? {
        let p = aimOrigin + simd_normalize(aimDir) * 400 - center
        let c = viewProj * V4(p, 1)
        guard c.w > 0.01 else { return nil }
        return V2(c.x / c.w, c.y / c.w)
    }
}
