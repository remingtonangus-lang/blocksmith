import Foundation
import simd

// Nov 4 (week item 71, no pop-in; bug ledger 13, 15, 16): things made near him to come at him (trains, vessels,
// dropships, the Reckoning's warship and crawler) were made at fixed distances, inside the fog past view 8 (it ends
// 16 x view - 12 out), so they appeared out of nothing in plain sight.
extension World {
    // How far off a thing `size` blocks from its middle to its near end is made so all of it is past the fog at his view.
    func pastFog(_ least: Float, size: Float = 0) -> Float { max(least, Float(renderDistance * CS) - 4 + size) }
}

extension Game {
    // Where he looks across: the headset's yaw in VR, else the body's.
    var lookYaw: Float { vrHeadYaw ?? player.yaw }
    // Could he see a thing at `at` reaching `halfWidth` to each side from where he stands? Within 70 degrees of his
    // look either way (Quest 3 shows about 55 each side; the rest for a turn of the head while it's made) plus its width.
    func inSight(_ at: V2, halfWidth: Float = 0) -> Bool {
        let p = V2(player.pos.x, player.pos.z), to = at - p, d = simd_length(to)
        if d < 1 { return true }
        let look = V2(-sinf(lookYaw), -cosf(lookYaw))
        let off = acosf(max(-1, min(1, simd_dot(look, to / d))))
        return off < 70 * .pi / 180 + atanf(halfWidth / d)
    }
}
