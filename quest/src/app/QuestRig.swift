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
    func toWorldRot(_ q: simd_quatf) -> simd_quatf { fullRot * q }

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
            let h = trackingHead.y
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
        feet = game.player.pos + V3(0, stepOffset, 0)
        headWorld = toWorld(trackingHead)
        (headYaw, headPitch) = XRMath.yawPitch(toWorldRot(headRot))
    }

    /// Per frame with the frame's dt: smooths the level head yaw (tracking space) the stick is relative to.
    func updateMoveYaw(dt: Float) {
        let ty = XRMath.levelYaw(headRot)
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
        feet = game.player.pos + V3(0, stepOffset, 0)
        headWorld = toWorld(trackingHead)
    }

    // Steps up and down (stairs, slabs, a block stepped onto) move the player in one tick; the camera follows over
    // ~0.1 s instead, so the world doesn't jump under the user. Falls, jumps, teleports, riding and ship decks snap.
    private var lastFeetY: Float?
    private(set) var stepOffset: Float = 0
    func smoothSteps(game: Game, dt: Float) {
        let p = game.player
        let y = p.pos.y
        if let ly = lastFeetY {
            let d = y - ly
            if p.onGround && !p.flying && game.riding == nil && game.world.ships.aboard == nil && game.world.ships.pilot == nil
                && abs(d) > 0.05 && abs(d) <= 1.1 {
                stepOffset -= d
            }
        }
        stepOffset *= expf(-dt * 16)
        if abs(stepOffset) < 0.002 || abs(stepOffset) > 1.2 { stepOffset = 0 }
        lastFeetY = y
    }

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
        var minL: Float = 0, maxR: Float = 0, maxU: Float = 0, minD: Float = 0
        for i in 0..<2 {
            let (p, q) = xr.eyePose(i)
            let (l, r, u, d) = xr.fovTangents(i)
            minL = min(minL, l); maxR = max(maxR, r); maxU = max(maxU, u); minD = min(minD, d)
            let proj = XRMath.projection(tanLeft: l, tanRight: r, tanUp: u, tanDown: d, near: 0.05, far: far)
            let rel = toWorld(p) - center
            vps.append(proj * XRMath.inversePose(toWorldRot(q), rel))
        }
        // Culling frustum: the union of both eyes' fields of view from 10 cm behind the centre.
        let hq = toWorldRot(headRot)
        let back = hq.act(V3(0, 0, 0.1))
        let cullProj = XRMath.projection(tanLeft: minL * 1.05, tanRight: maxR * 1.05, tanUp: maxU * 1.05, tanDown: minD * 1.05, near: 0.05, far: far)
        let cull = cullProj * XRMath.inversePose(hq, back)
        return EyeCamera(center: center, viewProj: vps, cullViewProj: cull, yaw: headYaw, pitch: headPitch, far: far)
    }
}
