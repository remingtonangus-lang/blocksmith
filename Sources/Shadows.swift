import Foundation
import simd

// Fancy graphics: soft blob shadows under mobs, dropped items and the third-person player. Fast graphics: dropped items
// only (a hovering 3D item with no shadow read as floating in the air: item art critic).
// Each shadow is one blended quad just above the first collidable block below the entity,
// shrinking and fading with the drop (up to 4 blocks). Drawn in the blended entity pass.
extension Game {
    func writeShadows(_ wr: inout EntityWriter, eye: V3) {
        let layer = Int(Tex.id("shadow"))
        let uv = EntityWriter.fullUV
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
            wr.quad4(c + V3(-r, 0, r), c + V3(r, 0, r), c + V3(r, 0, -r), c + V3(-r, 0, -r), uv.0, uv.1, uv.2, uv.3, layer, V4(0, 0, 0, strength * k))
        }
        // Dropped items: the shadow about the size of the item at rest.
        for d in drops.items { shadow(d.pos, radius: 0.22, strength: 0.35) }
        guard fancyGraphics else { return }
        for m in mobs.mobs where m.health > 0 {
            if m.spec.aquatic || m.kind == .boat { continue }
            shadow(m.pos, radius: max(0.25, m.halfW * 1.1), strength: 0.42)
        }
        if cameraMode != 0 && sleeping == 0 { shadow(player.pos, radius: 0.42, strength: 0.42) }
    }
}

// Dynamic light flashes (Fancy): short-lived point lights that light terrain in the HDR shader
// (explosions, lightning, fireworks, muzzle flashes...). Up to 8 at a time, nearest to the camera win.
struct LightFlash { var pos: V3; var color: V3; var radius: Float; var life: Float; var maxLife: Float }

extension Game {
    /// Adds a brief point light at `pos` (world). `color` is HDR (values above 1 bloom), `radius` in blocks.
    func addFlash(at pos: V3, color: V3, radius: Float, life: Float) {
        if flashes.count >= 32 { flashes.removeFirst() }
        flashes.append(LightFlash(pos: pos, color: color, radius: radius, life: life, maxLife: life))
    }

    func updateFlashes(_ dt: Float) {
        if flashes.isEmpty { return }
        for i in flashes.indices { flashes[i].life -= dt }
        flashes.removeAll { $0.life <= 0 }
    }

    // Packs up to 8 lights, camera-relative: [pos.xyz, radius] [color * fade, 0].
    func packFlashes(eye: V3, into out: inout [V4]) -> Int {
        out.removeAll(keepingCapacity: true)
        let sorted = flashes.sorted { simd_length_squared($0.pos - eye) < simd_length_squared($1.pos - eye) }
        var n = 0
        for f in sorted.prefix(8) {
            let k = max(0, f.life / f.maxLife)
            out.append(V4(f.pos - eye, f.radius))
            out.append(V4(f.color * (k * k), 0))
            n += 1
        }
        while out.count < 16 { out.append(V4(0, 0, 0, 0)) }
        return n
    }
}
