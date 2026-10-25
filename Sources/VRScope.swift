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
    static func zoom(_ t: Float, full: Float) -> Float { 1 + (full - 1) * max(0, min(1, t)) }

    // P270 (Oct 14 19:25, 19:45: "only zooms when held one-handed; with both hands it won't zoom"). The test used the drawn
    // eyepiece, half a metre behind the grip on the 3.2x model: with one arm out it reached the eye, but with both hands
    // the rear hand sits at the cheek and the eyepiece fell behind the head. Now every scoped gun follows one rule:
    // braced with both hands (the line between the hands is the barrel), the rear hand or the eyepiece at the eye, and
    // the barrel along the look. One-handed it never zooms.
    static let cheekReach: Float = 0.34
    static func scopeZoom(_ held: ItemStack) -> Float? {
        guard !held.isEmpty else { return nil }
        if Items.key(held.item) == gun { return zoom }
        if Guns.ironSightsOnly.contains(Items.key(held.item)) { return nil }       // P454: iron sights only
        let lv = Enchant.level(.stability, held)                    // a scope fitted at the gunsmith (Upgrades)
        return lv > 0 ? min(3, 1.5 + 0.5 * Float(lv)) : nil
    }
    static func raisedBraced(held: ItemStack, braced: Bool, head: V3, headForward: V3, rearHand: V3, eyepiece: V3, barrel: V3) -> Bool {
        guard braced, scopeZoom(held) != nil else { return false }
        let near = min(simd_length(rearHand - head), simd_length(eyepiece - head)) < cheekReach
        return near && simd_dot(simd_normalize(barrel), simd_normalize(headForward)) > alignCos
    }

    // Where the round lands, in normalized device coordinates of a camera-relative view-projection (nil behind the eye).
    static func reticle(viewProj: float4x4, center: V3, aimOrigin: V3, aimDir: V3) -> V2? {
        let p = aimOrigin + simd_normalize(aimDir) * 400 - center
        let c = viewProj * V4(p, 1)
        guard c.w > 0.01 else { return nil }
        return V2(c.x / c.w, c.y / c.w)
    }
}
