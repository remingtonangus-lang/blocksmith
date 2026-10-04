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
    private(set) var heightOffset: Float = 1.62
    private(set) var trackingHead = V3(0, 1.6, 0)
    private(set) var headRot = simd_quatf()
    private(set) var feet = V3.zero
    private(set) var headWorld = V3.zero
    private(set) var headYaw: Float = 0
    private(set) var headPitch: Float = 0
    static let eyeHeight: Float = 1.62

    var yawRot: simd_quatf { simd_quatf(angle: bodyYaw, axis: V3(0, 1, 0)) }

    // Tracking-space point -> world.
    func toWorld(_ p: V3) -> V3 { feet + yawRot.act(V3(p.x - anchor.x, p.y + heightOffset, p.z - anchor.z)) }
    func toWorldDir(_ d: V3) -> V3 { yawRot.act(d) }
    func toWorldRot(_ q: simd_quatf) -> simd_quatf { yawRot * q }

    // The loading scene works in raw tracking space: the head's floor-relative eye height.
    func floorEyeY(xr: XRInput) -> Float { xr.floorSpace ? max(1.0, trackingHead.y) : 0 }

    // Per frame, before the game ticks: new head pose, recentre when asked, and the game's look angles follow the head.
    func update(xr: XRInput, game: Game) {
        trackingHead = xr.headPos
        headRot = xr.headRot
        if needsRecenter {
            needsRecenter = false
            anchor = V3(trackingHead.x, 0, trackingHead.z)
            // Standing or seated, the current head height becomes the game's eye height (ducking still lowers the view).
            let h = trackingHead.y
            heightOffset = QuestRig.eyeHeight - h
            print(String(format: "rig: recentred, head %.2f m above the %@, eye offset %.2f", h, xr.floorSpace ? "floor" : "origin", heightOffset))
        }
        feet = game.player.pos
        headWorld = toWorld(trackingHead)
        (headYaw, headPitch) = XRMath.yawPitch(toWorldRot(headRot))
    }

    // After the player moved (roomscale, Game.tick): the camera follows the feet.
    func refresh(game: Game) {
        feet = game.player.pos
        headWorld = toWorld(trackingHead)
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
