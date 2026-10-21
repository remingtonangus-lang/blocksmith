import Foundation
import simd

// Realistic world (docs/design/realistic-world.md 1.5): every organic-class block (ShapeClass.organic: pumpkins, melons,
// mushroom caps, hay, wart blocks, glowstone, sponges, froglights...) is drawn as one rounded form instead of a cube.
//
// One primitive covers them all: a soft box. Each side of the block is rounded with its own radius where the block is
// exposed there and stays flat and full where a block of the same kind continues it, so a lone pumpkin comes out as a
// ribbed ball, a stack of hay as one drum, a mushroom cap layer as a domed sheet and a wart canopy as one lumpy mass.
// The family (ShapeClass.family) only picks the radii, the ribs and the noise. Each side is textured with that face's own
// texture, projected straight from the block face it came from, so a carved pumpkin keeps its face and a melon its
// stripes, wrapped round the curve.
enum ShapeOrganic {
    static let isOrganic: [Bool] = ShapeClass.kind.map { $0 == .organic }

    struct Form {
        var r: [Float]          // rounding radius per side (+X -X +Y -Y +Z -Z), 0 where it continues
        var ribs: Float = 0     // gourds: ribs round the vertical axis
        var ribDepth: Float = 0
        var bump: Float = 0     // world-stable lumps along the normal
        var squash: Float = 0   // gourds: the top sinks a little
    }

    static func emit(_ ctx: DetailContext) {
        var any = false
        scan: for y in 0..<16 { for z in 0..<16 { for x in 0..<16 where isOrganic[Int(ctx.R[ctx.ri(x, y, z)])] { any = true; break scan } } }
        guard any else { return }
        let grid = ctx.lod == 1 ? 3 : (ctx.lod == 2 ? 4 : 5)
        for y in 0..<16 { for z in 0..<16 { for x in 0..<16 {
            let b = ctx.block(x, y, z)                  // (P389: a struck object's cell reads as air)
            guard isOrganic[Int(b)] else { continue }
            block(ctx, b, x, y, z, grid: grid)
        } } }
    }

    // Sides (+X -X +Y -Y +Z -Z) as offsets.
    static let dirs: [SIMD3<Int>] = [SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)]

    // The soft box a block is drawn as, from its neighbours (`block` reads a cell): the form, the sides that continue
    // into the next block, the sides covered by an opaque one. (P389: WorldObjects builds a struck pumpkin's or bale's
    // pieces from the same form.)
    static func formAt(_ b: BlockID, _ x: Int, _ y: Int, _ z: Int, block: (Int, Int, Int) -> BlockID) -> (Form, [Bool], [Bool]) {
        let i = Int(b)
        let fam = ShapeClass.family[i]
        let g = Blocks.groupBase[i]
        let opaqueT = Blocks.opaque
        // Same kind beside it: that side continues (flat, no face). Any other opaque block: no face either, but the form
        // still rounds there unless it rests on it (a gourd sits flat on the ground).
        var cont = [Bool](repeating: false, count: 6), covered = [Bool](repeating: false, count: 6)
        for f in 0..<6 {
            let d = dirs[f]
            let nb = block(x + d.x, y + d.y, z + d.z)
            cont[f] = Blocks.groupBase[Int(nb)] == g || (fam == .blob && isOrganic[Int(nb)] && ShapeClass.family[Int(nb)] == .blob)
            // A bale continues only end to end along its own axis (a stack of hay drums, not a fused corner).
            if fam == .bale && cont[f] {
                let a = Int(ShapeTrunks.axisOf[i])
                cont[f] = f / 2 == a && ShapeTrunks.axisOf[Int(nb)] == UInt8(a)
            }
            covered[f] = !cont[f] && opaqueT[Int(nb)] && !Mesher.detailT[Int(nb)]
        }
        var form = Form(r: [Float](repeating: 0, count: 6))
        switch fam {
        case .gourd:
            form.r = [0.47, 0.47, 0.45, covered[3] ? 0.14 : 0.35, 0.47, 0.47]
            form.ribs = 10; form.ribDepth = 0.035; form.squash = 0.09; form.bump = 0.01
        case .bale:
            let a = Int(ShapeTrunks.axisOf[i])
            for f in 0..<6 { form.r[f] = f / 2 == a ? 0.07 : 0.46 }
            form.bump = 0.012
        case .cap:
            form.r = [0.38, 0.38, 0.45, 0.08, 0.38, 0.38]
            form.bump = 0.025
        case .blob:
            form.r = [0.3, 0.3, 0.3, covered[3] ? 0.1 : 0.3, 0.3, 0.3]
            form.bump = 0.045
        }
        for f in 0..<6 where cont[f] { form.r[f] = 0 }
        // Sides resting on the ground below stay flat so the object sits.
        if covered[3] && fam != .bale { form.r[3] = min(form.r[3], 0.1) }
        return (form, cont, covered)
    }

    static func block(_ ctx: DetailContext, _ b: BlockID, _ x: Int, _ y: Int, _ z: Int, grid: Int) {
        let i = Int(b)
        let (form, cont, covered) = formAt(b, x, y, z) { ctx.block($0, $1, $2) }

        var base = SIMD3<Float>(Float(x), Float(y), Float(z))
        // P297 (a) ("a log and a pumpkin floating"): a lone form on natural ground (a pumpkin in the grass, a melon) sits
        // on the drawn surface, which dips below the block's foot between the cells it was rounded from.
        // P365 (e, "pumpkins still don't sit in the ground well"): one ground height at the block's corner left the
        // downhill side floating on a slope. The ground is read at all four corners of the footprint and the form settles
        // into it: a little under the average, and never with its foot over the lowest corner.
        if covered[3] && !cont[2] && SmoothTerrain.natural[Int(ctx.block(x, y - 1, z))] {
            var sum: Float = 0, n: Float = 0, lo: Float = .greatestFiniteMagnitude
            for (ox, oz) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                guard let g = ctx.groundTop(x + ox, y - 1, z + oz, reach: 2) else { continue }
                sum += g; n += 1; lo = min(lo, g)
            }
            if n > 0 {
                let settle = min(sum / n - 0.1, lo + 0.03)
                base.y = max(Float(y) - 0.8, min(Float(y), settle))
            }
        }
        let tint = Int(Blocks.tint[i] == 3 ? 1 : Blocks.tint[i])
        for f in 0..<6 where !cont[f] && !covered[f] {
            face(ctx, form, base: base, f: f, layer: Int(Blocks.tex[i * 6 + f]), tint: tint, grid: grid, cont: cont)
        }
    }

    // A point on the block's surface (block-local 0...1) moved onto the soft box: pulled to the inner box (shrunk by the
    // radius on each rounded side), then out again by the radius along the way it came. Same point, same result, from
    // whichever face asks (so the faces close up).
    @inline(__always) static func soft(_ q: SIMD3<Float>, _ form: Form) -> SIMD3<Float> {
        var inner = q
        for a in 0..<3 {
            let lo = form.r[a * 2 + 1], hi = 1 - form.r[a * 2]
            inner[a] = min(max(q[a], lo), hi)
        }
        let d = q - inner
        let len = simd_length(d)
        guard len > 1e-6 else { return q }
        // Each axis out by its own side's radius (an elliptical corner where two radii meet: continuous across them).
        var p = inner
        for a in 0..<3 where d[a] != 0 { p[a] += d[a] / len * (d[a] > 0 ? form.r[a * 2] : form.r[a * 2 + 1]) }
        return p
    }

    static func shape(_ ctx: DetailContext, _ q: SIMD3<Float>, _ form: Form, base: SIMD3<Float>) -> SIMD3<Float> {
        var p = soft(q, form)
        let c = SIMD3<Float>(0.5, 0.5, 0.5)
        if form.ribs > 0 {
            let o = p - c
            let th = atan2f(o.z, o.x)
            let rib = 1 - form.ribDepth * (1 - abs(cosf(th * form.ribs * 0.5))) * 2
            let k = min(1, max(0, (0.5 - abs(o.y)) * 3))            // ribs fade toward the stem and the base
            p.x = c.x + o.x * (1 - (1 - rib) * k); p.z = c.z + o.z * (1 - (1 - rib) * k)
            p.y -= form.squash * max(0, o.y) * 2
        }
        if form.bump > 0 {
            // Lumps only where the form is free (not on a side that continues into the next block).
            let o = p - c
            let w = simd_length(SIMD3<Float>(form.r[o.x > 0 ? 0 : 1] > 0 ? 1 : 0, form.r[o.y > 0 ? 2 : 3] > 0 ? 1 : 0,
                                             form.r[o.z > 0 ? 4 : 5] > 0 ? 1 : 0))
            if w > 0 {
                var edge: Float = 1
                for a in 0..<3 {
                    if form.r[a * 2] == 0 { edge = min(edge, (1 - q[a]) * 4) }
                    if form.r[a * 2 + 1] == 0 { edge = min(edge, q[a] * 4) }
                }
                let n = simd_normalize(o + SIMD3(0, 1e-4, 0))
                p += n * form.bump * ctx.noise(base + p, 2.3, 0x0B60) * max(0, edge)
            }
        }
        return base + p
    }

    static func face(_ ctx: DetailContext, _ form: Form, base: SIMD3<Float>, f: Int, layer: Int, tint: Int, grid: Int, cont: [Bool]) {
        let a = f / 2, a1 = (a + 1) % 3, a2 = (a + 2) % 3
        let side: Float = f & 1 == 0 ? 1 : 0
        // Grid lines along each tangent axis, gathered near the rounded edges (where the curve is).
        func ticks(_ ax: Int) -> [Float] {
            let lo = form.r[ax * 2 + 1], hi = form.r[ax * 2]
            var t: [Float] = [0]
            if lo > 0.02 { t.append(lo * 0.5); t.append(lo) }
            let mid = max(1, grid - 2)
            let a0 = lo, a1v = 1 - hi
            for k in 1..<mid { t.append(a0 + (a1v - a0) * Float(k) / Float(mid)) }
            if hi > 0.02 { t.append(1 - hi); t.append(1 - hi * 0.5) }
            t.append(1)
            var out: [Float] = []
            for v in t.sorted() where out.isEmpty || v - out.last! > 0.01 { out.append(v) }
            return out
        }
        let tu = ticks(a1), tv = ticks(a2)
        let nu = tu.count, nv = tv.count
        var pos = [SIMD3<Float>](repeating: .zero, count: nu * nv), nrm = pos
        var qs = pos
        let eps: Float = 0.01
        for j in 0..<nv { for k in 0..<nu {
            var q = SIMD3<Float>(0, 0, 0)
            q[a] = side; q[a1] = tu[k]; q[a2] = tv[j]
            let p = shape(ctx, q, form, base: base)
            // Normal from the surface itself (finite differences across the face), so ribs and lumps shade.
            var qa = q, qb = q
            qa[a1] = min(1, q[a1] + eps); qb[a2] = min(1, q[a2] + eps)
            var qa0 = q, qb0 = q
            qa0[a1] = max(0, q[a1] - eps); qb0[a2] = max(0, q[a2] - eps)
            let du = shape(ctx, qa, form, base: base) - shape(ctx, qa0, form, base: base)
            let dv = shape(ctx, qb, form, base: base) - shape(ctx, qb0, form, base: base)
            var n = simd_cross(du, dv)
            var out = SIMD3<Float>(0, 0, 0); out[a] = side * 2 - 1
            if simd_dot(n, out) < 0 { n = -n }
            let l = simd_length(n)
            n = l > 1e-8 ? n / l : out
            pos[k + j * nu] = p; nrm[k + j * nu] = n; qs[k + j * nu] = q
        } }
        // Planar texture of the block face (the mesher's projection, chunk.vert faces 0-5), from the unrounded point.
        func uv(_ q: SIMD3<Float>) -> SIMD2<Float> {
            switch f {
            case 0: return SIMD2(-q.z, -q.y)
            case 1: return SIMD2(q.z, -q.y)
            case 2: return SIMD2(q.x, q.z)
            case 3: return SIMD2(q.x, -q.z)
            case 4: return SIMD2(q.x, -q.y)
            default: return SIMD2(-q.x, -q.y)
            }
        }
        // Winding: counter-clockwise seen from outside. (a1, a2) is right-handed with +a, so +a faces go (u,v) order.
        let flip = f & 1 == 1
        for j in 0..<(nv - 1) { for k in 0..<(nu - 1) {
            let i00 = k + j * nu, i10 = k + 1 + j * nu, i11 = k + 1 + (j + 1) * nu, i01 = k + (j + 1) * nu
            let order = flip ? [i00, i01, i11, i10] : [i00, i10, i11, i01]
            for o in order { ctx.vertex(pos[o], nrm[o], uv(qs[o]), layer: layer, tint: tint) }
        } }
    }
}
