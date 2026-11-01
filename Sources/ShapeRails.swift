import Foundation
import simd

// P337 step 2 ("rails look wrong, gravel drawn over them"): in a Polygons world a plain rail is track, not a textured
// card: two steel rails on timber sleepers, following the rail's shape (straight, up a slope, round a curve), sitting
// on the bed under it (the ballast's top: FieldTerrain.split keeps a structure's ground to its faces). The block stays
// for gameplay (minecarts, trains, breaking, saves); powered, detector and activator rails keep their cards.
enum ShapeRails {
    // P504 (Nov 1 08:01:32-08:02:55, the Ash Vault's yard: "still using the small rails... we should have the bigger rail
    // system"): a powered rail is drawn as track too (a copper strip down its sleepers), so a line keeps one size.
    static let isRail: [Bool] = (0..<Blocks.count).map { i in
        Blocks.render[i] == RenderType.rail.rawValue && (Circuit.kinds[i] == .rail || Circuit.kinds[i] == .poweredRail)
    }
    static let isPowered: [Bool] = (0..<Blocks.count).map { i in isRail[i] && Circuit.kinds[i] == .poweredRail }
    static let strip: BlockID = Blocks.has("gold_block") ? Blocks.id("gold_block") : STONE
    static let steel: BlockID = Blocks.has("iron_block") ? Blocks.id("iron_block") : STONE
    static let timber: BlockID = Blocks.has("dark_oak_planks") ? Blocks.id("dark_oak_planks") : PLANKS
    static let gauge: Float = 0.3                   // rails this far each side of the centre line
    // P470 ("make big train tracks"): a railway's track (a rail on the line's three-wide ballast or trestle deck, open
    // either side) is drawn at main-line size: rails 1.44 apart on heavy sleepers the bed's width, the trains' own
    // scale. A rail laid anywhere else keeps the light track.
    static let mainGauge: Float = 0.72
    static let bedKinds: [Bool] = (0..<Blocks.count).map { i in
        ["gravel", "stone_bricks", "spruce_planks", "polished_blackstone"].contains(Blocks.key(Blocks.groupBase[i]))   // (P504: the Ash Vault's yards)
    }

    static func emit(_ ctx: DetailContext) {
        var any = false
        scan: for y in 0..<16 { for z in 0..<16 { for x in 0..<16 where isRail[Int(ctx.R[ctx.ri(x, y, z)])] { any = true; break scan } } }
        guard any else { return }
        let steelL = Int(Blocks.tex[Int(steel) * 6 + 2]), woodL = Int(Blocks.tex[Int(timber) * 6 + 2]), stripL = Int(Blocks.tex[Int(strip) * 6 + 2])
        let curveSegs = ctx.lod == 0 ? 4 : 2
        for y in 0..<16 { for z in 0..<16 { for x in 0..<16 {
            let b = ctx.R[ctx.ri(x, y, z)]
            guard isRail[Int(b)] else { continue }
            let powered = isPowered[Int(b)]
            let shape = Int(b - Blocks.groupBase[Int(b)]) % (powered ? 6 : 100)     // (a powered rail's lit states: +6)
            let o = SIMD3<Float>(Float(x), Float(y), Float(z))
            let big = mainline(ctx, x, y, z, shape)
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
            // P379 step 3: in a field world the track lies on the drawn bed (Railways.shapeBed shapes it to the line's
            // gentle grade): the centre's height is the bed's top under it, each edge's the mean of the two cells'.
            if let hc = bedTop(ctx, x, y, z) {
                if shape >= 6 { pts = pts.map { SIMD3($0.x, hc, $0.z) } }
                else {
                    let ax = shape == 1 || shape == 2 || shape == 3
                    func edge(_ d: Int) -> Float {
                        for dy in [0, 1, -1] {
                            let nx = x + (ax ? d : 0), nz = z + (ax ? 0 : d)
                            guard isRail[Int(ctx.block(nx, y + dy, nz))], let h = bedTop(ctx, nx, y + dy, nz) else { continue }
                            return (hc + h + Float(dy)) * 0.5
                        }
                        return hc
                    }
                    pts = ax ? [SIMD3(0, edge(-1), 0.5), SIMD3(0.5, hc, 0.5), SIMD3(1, edge(1), 0.5)]
                             : [SIMD3(0.5, edge(-1), 0), SIMD3(0.5, hc, 0.5), SIMD3(0.5, edge(1), 1)]
                }
            }
            for k in 0..<(pts.count - 1) {
                let p0 = o + pts[k], p1 = o + pts[k + 1]
                let a = simd_normalize(p1 - p0)
                let s = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), a))
                let h = simd_cross(a, s)
                let len = simd_length(p1 - p0)
                // Sleepers: across the line every half block (a main line's: heavier, the bed's width).
                let n = max(1, Int((len / 0.5).rounded()))
                for j in 0..<n {
                    let c = p0 + (p1 - p0) * ((Float(j) + 0.5) / Float(n)) + h * (big ? 0.07 : 0.06)
                    box(ctx, c, a, s, h, big ? 0.12 : 0.09, big ? 1.22 : 0.46, big ? 0.06 : 0.05, woodL)
                }
                // The two rails, on the sleepers.
                for side: Float in [-1, 1] {
                    let c = (p0 + p1) * 0.5 + s * (side * (big ? mainGauge : gauge)) + h * (big ? 0.21 : 0.16)
                    box(ctx, c, a, s, h, len * 0.5 + 0.01, big ? 0.055 : 0.035, big ? 0.08 : 0.05, steelL)
                }
                if powered {
                    let c = (p0 + p1) * 0.5 + h * (big ? 0.15 : 0.11)
                    box(ctx, c, a, s, h, len * 0.5, big ? 0.09 : 0.05, 0.02, stripL)
                }
            }
        } } }
    }

    // A railway's rail (P470): on the line's bed, the bed cells either side of it open above.
    static func mainline(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int, _ shape: Int) -> Bool {
        let sides: [(Int, Int)]
        switch shape {
        case 1, 2, 3: sides = [(0, -1), (0, 1)]
        case 0, 4, 5: sides = [(-1, 0), (1, 0)]
        default: sides = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        }
        var open = 0
        for (dx, dz) in sides {
            let at = ctx.block(x + dx, y, z + dz), under = ctx.block(x + dx, y - 1, z + dz)
            if !Blocks.collide[Int(at)] && (bedKinds[Int(under)] || isRail[Int(at)]) { open += 1 }
        }
        return shape >= 6 ? open >= 2 : open == 2
    }

    // The drawn bed's top under a rail at section-local (x, y, z), relative to the rail's cell (-0.5 ... 0.5): where the
    // field's density crosses zero between the cell under the rail and the rail's own. Nil off a field (or over a deck).
    static func bedTop(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int) -> Float? {
        guard let field = ctx.field else { return nil }
        let cx = (x + 16) >> 4, cz = (z + 16) >> 4, wy = ctx.sy * 16 + y
        guard cx >= 0 && cz >= 0 && cx < 3 && cz < 3, wy >= 1 && wy < CH else { return nil }
        let st = field[cx + cz * 3]
        let i = ((x + 16) & 15) + ((z + 16) & 15) * CS + wy * CSQ
        let a = FieldTerrain.f(st.density(i - CSQ)), b = FieldTerrain.f(st.density(i))
        guard a > 0, b <= 0, a - b > 1e-3 else { return nil }
        return max(-0.5, min(0.5, a / (a - b) - 0.5))
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
