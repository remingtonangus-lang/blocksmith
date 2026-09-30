import Foundation
import simd

// Fancy graphics: soft blob shadows under mobs, dropped items and the third-person player.
// Each shadow is one blended quad just above the first collidable block below the entity,
// shrinking and fading with the drop (up to 4 blocks). Drawn in the blended entity pass.
extension Game {
    func writeShadows(_ wr: inout EntityWriter, eye: V3) {
        guard fancyGraphics else { return }
        let layer = Int(Tex.id("shadow"))
        let uvs = [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)]
        func shadow(_ p: V3, radius: Float, strength: Float) {
            let bx = Int(floor(p.x)), bz = Int(floor(p.z))
            var by = Int(floor(p.y + 0.01))
            var found = false
            for _ in 0..<5 {
                if Blocks.collide[Int(world.block(bx, by - 1, bz))] { found = true; break }
                by -= 1
            }
            guard found else { return }
            let drop = max(0, p.y - Float(by))
            let k = max(0, 1 - drop / 4)
            if k <= 0.02 { return }
            let r = radius * (0.7 + 0.3 * k)
            let c = V3(p.x, Float(by) + 0.015, p.z) - eye
            if simd_length_squared(c) > 48 * 48 { return }
            wr.quad([c + V3(-r, 0, r), c + V3(r, 0, r), c + V3(r, 0, -r), c + V3(-r, 0, -r)], uvs, layer, V4(0, 0, 0, strength * k))
        }
        for m in mobs.mobs where m.health > 0 {
            if m.spec.aquatic || m.kind == .boat { continue }
            shadow(m.pos, radius: max(0.25, m.halfW * 1.1), strength: 0.42)
        }
        for d in drops.items { shadow(d.pos, radius: 0.16, strength: 0.35) }
        if cameraMode != 0 && sleeping == 0 { shadow(player.pos, radius: 0.42, strength: 0.42) }
    }
}
