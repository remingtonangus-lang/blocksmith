import Foundation
import simd

// P337 step 2 ("rails look wrong, gravel drawn over them"): in a Polygons world a plain rail is track, not a textured
// card: two steel rails on timber sleepers, following the rail's shape (straight, up a slope, round a curve), sitting
// on the bed under it (the ballast's top: FieldTerrain.split keeps a structure's ground to its faces). The block stays
// for gameplay (minecarts, trains, breaking, saves); powered, detector and activator rails keep their cards.
enum ShapeRails {
    static let isRail: [Bool] = (0..<Blocks.count).map { i in
        Blocks.render[i] == RenderType.rail.rawValue && Circuit.kinds[i] == .rail
    }
    static let steel: BlockID = Blocks.has("iron_block") ? Blocks.id("iron_block") : STONE
    static let timber: BlockID = Blocks.has("dark_oak_planks") ? Blocks.id("dark_oak_planks") : PLANKS
    static let gauge: Float = 0.3                   // rails this far each side of the centre line

    static func emit(_ ctx: DetailContext) {
        var any = false
        scan: for y in 0..<16 { for z in 0..<16 { for x in 0..<16 where isRail[Int(ctx.R[ctx.ri(x, y, z)])] { any = true; break scan } } }
        guard any else { return }
        let steelL = Int(Blocks.tex[Int(steel) * 6 + 2]), woodL = Int(Blocks.tex[Int(timber) * 6 + 2])
        let curveSegs = ctx.lod == 0 ? 4 : 2
        for y in 0..<16 { for z in 0..<16 { for x in 0..<16 {
            let b = ctx.R[ctx.ri(x, y, z)]
            guard isRail[Int(b)] else { continue }
            let shape = Int(b - Blocks.groupBase[Int(b)])
            let o = SIMD3<Float>(Float(x), Float(y), Float(z))
            // The centre line through the block, as points.
            var pts: [SIMD3<Float>]
            switch shape {
            case 1: pts = [SIMD3(0, 0, 0.5), SIMD3(1, 0, 0.5)]
            case 2: pts = [SIMD3(0, 0, 0.5), SIMD3(1, 1, 0.5)]
            case 3: pts = [SIMD3(0, 1, 0.5), SIMD3(1, 0, 0.5)]
            case 4: pts = [SIMD3(0.5, 0, 1), SIMD3(0.5, 1, 0)]
            case 5: pts = [SIMD3(0.5, 0, 0), SIMD3(0.5, 1, 1)]
            case 6, 7, 8, 9:
                // Quarter circles of radius 0.5 round the corner the curve turns about.
                let c: SIMD2<Float> = [SIMD2(1, 1), SIMD2(0, 1), SIMD2(0, 0), SIMD2(1, 0)][shape - 6]
                // From the north or south edge's middle (0.5, c.y) to the east or west edge's (c.x, 0.5).
                let a0 = atan2f(0, 0.5 - c.x), a1 = atan2f(0.5 - c.y, 0)
                var d = a1 - a0
                if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
                pts = (0...curveSegs).map { k in
                    let a = a0 + d * Float(k) / Float(curveSegs)
                    return SIMD3(c.x + 0.5 * cosf(a), 0, c.y + 0.5 * sinf(a))
                }
            default: pts = [SIMD3(0.5, 0, 0), SIMD3(0.5, 0, 1)]
            }
            for k in 0..<(pts.count - 1) {
                let p0 = o + pts[k], p1 = o + pts[k + 1]
                let a = simd_normalize(p1 - p0)
                let s = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), a))
                let h = simd_cross(a, s)
                let len = simd_length(p1 - p0)
                // Sleepers: across the line every half block.
                let n = max(1, Int((len / 0.5).rounded()))
                for j in 0..<n {
                    let c = p0 + (p1 - p0) * ((Float(j) + 0.5) / Float(n)) + h * 0.06
                    box(ctx, c, a, s, h, 0.09, 0.46, 0.05, woodL)
                }
                // The two rails, on the sleepers.
                for side: Float in [-1, 1] {
                    let c = (p0 + p1) * 0.5 + s * (side * gauge) + h * 0.16
                    box(ctx, c, a, s, h, len * 0.5 + 0.01, 0.035, 0.05, steelL)
                }
            }
        } } }
    }

    // A box round c with half-sizes along a, s and h (a x s = h), counter-clockwise faces seen from outside.
    static func box(_ ctx: DetailContext, _ c: SIMD3<Float>, _ a: SIMD3<Float>, _ s: SIMD3<Float>, _ h: SIMD3<Float>,
                    _ ha: Float, _ hs: Float, _ hh: Float, _ layer: Int) {
        let A = a * ha, S = s * hs, H = h * hh
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, Float, Float)] = [
            (A, S, H, hs, hh), (-A, H, S, hh, hs), (S, H, A, hh, ha), (-S, A, H, ha, hh), (H, A, S, ha, hs), (-H, S, A, hs, ha),
        ]
        for (n, u, v, lu, lv) in faces {
            let nn = simd_normalize(n)
            for (su, sv) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
                let p = c + n + u * su + v * sv
                ctx.vertex(p, nn, SIMD2((su + 1) * lu, (1 - sv) * lv), layer: layer)
            }
        }
    }
}
