import Foundation
import simd

// Maps the headset's tracking space onto the game world. The player entity stays the authority for position and
// collision: the tracking-space point `anchor` (on the floor under the head at the last recentre) sits at the
// player's feet, the tracking space is turned by `bodyYaw` (snap/smooth turning), and the head's height above the
// floor is shifted so a normally standing user sees from the game's eye height (1.62 blocks) while ducking still
// lowers the view. Physically walking moves the player through the game's collision (QuestControls.roomScale).
final class QuestRig {
    var bodyYaw: Float = 0
    var anchor = V3.zero
    var shake = V3.zero                         // eye jolt (Game.shakeVR: the Tidebreaker), set each frame by the app
    var zoom: Float = 1                         // G21: the Farsight scope narrows both eyes' views (VRScope)
    // P100: the chase view while driving (Game.chaseOffset): the whole tracking space (head, hands, panels) eased out
    // behind the vehicle; zero on foot. The view never turns on its own: only where it sits moves.
    private(set) var chase = V3.zero
    private(set) var chaseSpeed: Float = 0         // m/s the chase offset moved last frame (the vignette rises with it)
    func chaseTick(_ target: V3, dt: Float) {
        let before = chase
        chase += (target - chase) * min(1, dt * 2.5)
        if simd_length(target - chase) < 0.01 { chase = target }
        chaseSpeed = simd_length(chase - before) / max(dt, 1e-3)
    }
    private(set) var lastCam: EyeCamera?        // the last frame's eye cameras (the scope's crosshair projects with them)
    var needsRecenter = true
    private(set) var recenters = 0              // counts recentres (panels re-place themselves after one)
    private(set) var heightOffset: Float = 1.62
    private(set) var trackingHead = V3(0, 1.6, 0)
    private(set) var headRot = simd_quatf()
    private(set) var feet = V3.zero
    private(set) var headWorld = V3.zero
    private(set) var headYaw: Float = 0
    /// Locomotion yaw: the head's level yaw (XRMath.levelYaw, pitch/roll-proof) in tracking space, smoothed over
    /// ~80 ms, plus bodyYaw (snap / smooth turns and ship carry apply instantly). Head position never enters it.
    private(set) var moveYaw: Float = 0
    private var moveYawT: Float = 0
    private var moveYawSet = false
    private(set) var headPitch: Float = 0
    static let eyeHeight: Float = 1.62
    // Reclined play: the tracking space is also tilted so the gaze at the last recentre becomes the level, forward
    // direction (world, horizon, HUD and panels all follow). Identity when standing or seated upright.
    private(set) var tilt = simd_quatf()
    private var tiltAxis = V3(1, 0, 0)
    private var tiltBase: Float = 0
    private(set) var pitchOffset: Float = 0        // reclined look up/down in steps (right stick), reset by a recentre
    private(set) var pivotY: Float = 1.6

    var yawRot: simd_quatf { simd_quatf(angle: bodyYaw, axis: V3(0, 1, 0)) }

    // Tracking-space point -> world.
    private var fullRot: simd_quatf { yawRot * tilt }
    func toWorld(_ p: V3) -> V3 { feet + V3(0, QuestRig.eyeHeight, 0) + fullRot.act(V3(p.x - anchor.x, p.y - pivotY, p.z - anchor.z)) }
    func toWorldDir(_ d: V3) -> V3 { fullRot.act(d) }
    // P381 step 9: the tracking space's place in the world (toWorld(p) = rotation.act(p) + translation).
    var appToWorld: (rotation: simd_quatf, translation: V3) {
        (fullRot, feet + V3(0, QuestRig.eyeHeight, 0) - fullRot.act(V3(anchor.x, pivotY, anchor.z)))
    }
    func toWorldRot(_ q: simd_quatf) -> simd_quatf { fullRot * q }
    // Level space: tracking space turned by the reclined tilt (identity upright), about the recentre's pivot height.
    // Panels (HUD, menus) are placed here, so lying down they sit in front of the levelled gaze, not in the room's
    // horizontal plane (which the tilt would swing below the view). Upright it is tracking space shifted by pivotY.
    func toLevel(_ p: V3) -> V3 { tilt.act(V3(p.x, p.y - pivotY, p.z)) }
    func levelToWorld(_ l: V3) -> V3 { feet + V3(0, QuestRig.eyeHeight, 0) + yawRot.act(l - tilt.act(V3(anchor.x, 0, anchor.z))) }
    var levelHead: V3 { toLevel(trackingHead) }

    // Reclined look up (+) / down (-): the levelled world tips by a step about the recentre's right axis.
    func stepPitch(_ delta: Float) {
        pitchOffset = max(-80 * .pi / 180, min(80 * .pi / 180, pitchOffset + delta))
        tilt = simd_quatf(angle: tiltBase + pitchOffset, axis: tiltAxis)
    }

    // The loading scene works in raw tracking space: the head's floor-relative eye height.
    func floorEyeY(xr: XRInput) -> Float { xr.floorSpace ? max(1.0, trackingHead.y) : 0 }

    // Per frame, before the game ticks: new head pose, recentre when asked, and the game's look angles follow the head.
    func update(xr: XRInput, game: Game) {
        trackingHead = xr.headPos
        headRot = xr.headRot
        if needsRecenter {
            needsRecenter = false
            recenters += 1
            anchor = V3(trackingHead.x, 0, trackingHead.z)
            // Standing or seated, the current head height becomes the game's eye height (ducking still lowers the view).
            // S6: standing with a measured height (first-launch setup), that height is the eye height instead, so a
            // recentre made crouched or leaning doesn't leave the view low. Seated and lying down keep the head as it is
            // now: the view is raised to a standing player's eyes.
            let cal = QuestSettings.standHeight
            let standing = !QuestSettings.seated && !QuestSettings.reclined
            let h: Float = standing && xr.floorSpace && cal > 1.0 ? cal : trackingHead.y
            heightOffset = QuestRig.eyeHeight - h
            pivotY = h
            if QuestSettings.reclined {
                let (ty, gp) = XRMath.yawPitch(headRot)
                tiltAxis = V3(cosf(ty), 0, -sinf(ty))
                tiltBase = -gp
            } else { tiltBase = 0 }
            pitchOffset = 0
            tilt = simd_quatf(angle: tiltBase, axis: tiltAxis)
            print(String(format: "rig: recentred, head %.2f m above the %@, eye offset %.2f", h, xr.floorSpace ? "floor" : "origin", heightOffset))
        }
        feet = game.player.pos + V3(0, stepOffset, 0) + chase
        headWorld = toWorld(trackingHead)
        (headYaw, headPitch) = XRMath.yawPitch(toWorldRot(headRot))
        shake = game.shakeVR
    }

    /// Per frame with the frame's dt: smooths the level head yaw (tracking space) the stick is relative to.
    func updateMoveYaw(dt: Float) {
        let ty = XRMath.levelYaw(tilt * headRot)          // reclined: the levelled gaze, not the room's
        if !moveYawSet { moveYawT = ty; moveYawSet = true }
        var d = ty - moveYawT
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        moveYawT += d * min(1, dt / 0.08)
        moveYawT = moveYawT.truncatingRemainder(dividingBy: 2 * .pi)
        moveYaw = moveYawT + bodyYaw
    }

    // After the player moved (roomscale, Game.tick): the camera follows the feet.
    func refresh(game: Game) {
        feet = game.player.pos + V3(0, stepOffset, 0) + chase
        headWorld = toWorld(trackingHead)
    }

    // Steps up and down (stairs, slabs, a block stepped onto, a mount or wheeled vehicle climbing a block) move the
    // body in one tick; the camera follows the shared eased offset (ViewStep.swift, Game.updateViewStep), the same one
    // the Mac camera and the drawn mount/rider use, so the world never jumps under the user.
    private(set) var stepOffset: Float = 0
    func smoothSteps(game: Game, dt: Float, aboard: Bool = false) {
        stepOffset = game.player.viewDY
        // P261: aboard a moving hull the deck's up-and-down jolts (bumps, a keel scraping ground, swell) reach the eyes
        // smoothed (about 0.17 s), at most 0.35 blocks off; slow climbs and the deck itself are followed.
        let y = game.player.pos.y
        if aboard, let hy = heaveY, abs(y - hy) < 3 {
            let nh = hy + (y - hy) * min(1, dt * 6)
            heaveY = nh
            stepOffset += max(-0.35, min(0.35, nh - y))
        } else {
            heaveY = aboard ? y : nil
        }
        // P367: crouched on foot the view eases 0.3 blocks lower (about a quarter second each way), so sneaking shows.
        let pl = game.player
        let want: Float = pl.sneaking && !pl.flying && !pl.inWater && game.riding == nil && game.world.frame == nil ? -0.3 : 0
        crouchDip += (want - crouchDip) * min(1, dt * 10)
        stepOffset += crouchDip
    }
    private var heaveY: Float?
    private var crouchDip: Float = 0

    // Loading scene: raw tracking space (no player yet).
    func updateLoading(xr: XRInput) {
        trackingHead = xr.headPos
        headRot = xr.headRot
        feet = .zero; anchor = .zero; heightOffset = 0; bodyYaw = 0
        headWorld = trackingHead
        (headYaw, headPitch) = XRMath.yawPitch(headRot)
    }

    // Moves the anchor so the current head position maps onto the player's feet again (after roomscale movement
    // was handed to the player through collision).
    func absorbHeadOffset() {
        anchor.x = trackingHead.x
        anchor.z = trackingHead.z
    }

    // Both eyes' camera-relative view-projections around the head centre.
    func camera(xr: XRInput, far: Float) -> EyeCamera {
        var vps: [float4x4] = []
        let center = headWorld
        let jolt = shake
        var minL: Float = 0, maxR: Float = 0, maxU: Float = 0, minD: Float = 0
        for i in 0..<2 {
            let (p, q) = xr.eyePose(i)
            var (l, r, u, d) = xr.fovTangents(i)
            minL = min(minL, l); maxR = max(maxR, r); maxU = max(maxU, u); minD = min(minD, d)   // (culling: the unzoomed view)
            if zoom > 1.001 { l /= zoom; r /= zoom; u /= zoom; d /= zoom }
            let proj = XRMath.projection(tanLeft: l, tanRight: r, tanUp: u, tanDown: d, near: 0.05, far: far)
            let rel = toWorld(p) - center + jolt
            vps.append(proj * XRMath.inversePose(toWorldRot(q), rel))
        }
        // Culling frustum: the union of both eyes' fields of view from 10 cm behind the centre.
        let hq = toWorldRot(headRot)
        let back = hq.act(V3(0, 0, 0.1))
        let cullProj = XRMath.projection(tanLeft: minL * 1.05, tanRight: maxR * 1.05, tanUp: maxU * 1.05, tanDown: minD * 1.05, near: 0.05, far: far)
        let cull = cullProj * XRMath.inversePose(hq, back)
        let cam = EyeCamera(center: center, viewProj: vps, cullViewProj: cull, yaw: headYaw, pitch: headPitch, far: far)
        lastCam = cam
        return cam
    }
}
