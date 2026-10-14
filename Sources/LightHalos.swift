import Foundation
import simd

// SH1 (light halos, ShaderFX.halos): a soft glow round the light sources near the eye (torches, lanterns, lamps, lava,
// glowing ores), camera-facing discs in the blended entity pass, pulled a little toward the eye so a lit block's own
// faces don't hide its glow, while rock in front of a buried one still does (depth test). The emitters within 20 blocks
// are found every half second by scanning only the sections that hold one (BlockStore.emitMask); the 48 nearest draw,
// fading with distance and in daylight.
final class LightHalos {
    static let shared = LightHalos()
    struct Halo { var pos: V3; var color: V3; var size: Float; var alpha: Float }
    private(set) var list: [Halo] = []
    private var at = -10.0
    private weak var world: World?

    // Per block state: the glow colour (warm flame by default; soul fire blue, lava orange, circuit red, sea light cyan).
    static let color: [V3] = (0..<Blocks.count).map { i in
        guard Blocks.emit[i] > 0 else { return .zero }
        let k = Blocks.key(Blocks.groupBase[i])
        if k.contains("soul") { return V3(0.45, 0.8, 1.0) }
        if k.contains("lava") || k.contains("magma") || k.contains("fire") { return V3(1.0, 0.5, 0.18) }
        if k.contains("redstone") || k.contains("signal") { return V3(1.0, 0.25, 0.15) }
        if k.contains("sea_lantern") || k.contains("prismarine") || k.contains("conduit") { return V3(0.6, 0.95, 1.0) }
        if k.contains("froglight") || k.contains("shroomlight") || k.contains("glowstone") { return V3(1.0, 0.85, 0.55) }
        return V3(1.0, 0.78, 0.45)
    }

    func scan(_ w: World, _ eye: V3) {
        var found: [(Float, Halo)] = []
        let r = 20, ex = Int(floor(eye.x)), ey = Int(floor(eye.y)), ez = Int(floor(eye.z))
        let emit = Blocks.emit, col = LightHalos.color
        let s0 = max(0, (ey - r) >> 4), s1 = min(NSEC - 1, (ey + r) >> 4)
        for cz in floorDiv(ez - r, CS)...floorDiv(ez + r, CS) { for cx in floorDiv(ex - r, CS)...floorDiv(ex + r, CS) {
            guard let c = w.chunks[ChunkKey(x: cx, z: cz)], s0 <= s1 else { continue }
            for sy in s0...s1 where c.blocks.emitMask & (1 << UInt32(sy)) != 0 {
                for y in (sy * 16)..<(sy * 16 + 16) { for lz in 0..<CS { for lx in 0..<CS {
                    let b = Int(c.blocks[Chunk.index(lx, y, lz)])
                    let e = emit[b]
                    guard e > 0 else { continue }
                    let p = V3(Float(cx * CS + lx) + 0.5, Float(y) + 0.5, Float(cz * CS + lz) + 0.5)
                    let d2 = simd_length_squared(p - eye)
                    guard d2 < Float(r * r) else { continue }
                    let ef = Float(e)
                    found.append((d2, Halo(pos: p, color: col[b], size: 0.35 + 0.05 * ef, alpha: 0.12 + 0.012 * ef)))
                } } }
            }
        } }
        if found.count > 48 { found.sort { $0.0 < $1.0 }; found.removeLast(found.count - 48) }
        list = found.map { $0.1 }
    }

    func update(_ g: Game, eye: V3) {
        if g.clock - at > 0.5 || world !== g.world { at = g.clock; world = g.world; scan(g.world, eye) }
    }
}

extension Game {
    func writeHalos(_ wr: inout EntityWriter, eye: V3, right: V3, up: V3) {
        guard ShaderFX.on(ShaderFX.halos) else { return }
        let h = LightHalos.shared
        h.update(self, eye: eye)
        guard !h.list.isEmpty else { return }
        let layer = Int(Tex.id("glow"))
        let day: Float = 1 - 0.7 * daylight
        for e in h.list {
            var c = e.pos - eye
            let d = simd_length(c)
            guard d > 0.8 else { continue }
            c -= c / d * 0.6
            let fade: Float = 1 - max(0, min(1, (d - 14) / 6))
            let a = e.alpha * fade * day
            guard a > 0.01 else { continue }
            let rx = right * e.size, uy = up * e.size
            wr.quad4(c - rx - uy, c + rx - uy, c + rx + uy, c - rx + uy, V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0), layer, V4(e.color, a))
        }
    }
}
