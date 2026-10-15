import Foundation
import simd

// Textures for material-aware damage (Wear.swift) and the weather blocks: crack, scorch and dent decal stages, glass
// shards, charcoal and smouldering charcoal. Each is painted at any resolution from the same continuous pattern, so
// the 16 px painters (Fast lane, BLOCKSMITH_TEXRES=16) and the 128 px HD layers (HDTex.generator) agree.
enum WearArt {
    static let names: [String] = (1...4).map { "wear_crack_\($0)" } + (1...3).map { "wear_scorch_\($0)" }
        + (1...3).map { "wear_dent_\($0)" } + ["fx_shard", "charcoal_block", "smoldering_charcoal"]

    // 16 px painters (TextureGen.painters).
    static func painters(_ p: inout [String: TextureGen.Painter]) {
        for name in names {
            guard let px = paint(name, 16) else { continue }
            p[name] = { x, y in px[y * 16 + x] }
        }
    }

    // HD generator for these names (TexturesHD), nil for every other name.
    static func hd(_ name: String) -> HDTex.Gen? {
        guard names.contains(name) else { return nil }
        return { n, _ in
            var img = HDTex.Img(n)
            if let px = paint(name, n) { img.px = px }
            return img
        }
    }

    // MARK: Patterns

    private static func stage(_ name: String, _ prefix: String) -> Int? {
        name.hasPrefix(prefix) ? Int(name.dropFirst(prefix.count)) : nil
    }

    static func paint(_ name: String, _ n: Int) -> [V4]? {
        if let s = stage(name, "wear_crack_") { return cracks(n, stage: s) }
        if let s = stage(name, "wear_scorch_") { return scorch(n, stage: s) }
        if let s = stage(name, "wear_dent_") { return dents(n, stage: s) }
        switch name {
        case "fx_shard": return shard(n)
        case "charcoal_block": return charcoal(n, glow: false)
        case "smoldering_charcoal": return charcoal(n, glow: true)
        default: return nil
        }
    }

    // Tileable value noise on the unit square (period `cells`).
    private static func vnoise(_ u: Float, _ v: Float, cells: Int, salt: UInt32) -> Float {
        let fx = u * Float(cells), fy = v * Float(cells)
        let x0 = Int(floorf(fx)), y0 = Int(floorf(fy))
        let tx = fx - Float(x0), ty = fy - Float(y0)
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        func g(_ a: Int, _ b: Int) -> Float { hashf(((a % cells) + cells) % cells, ((b % cells) + cells) % cells, 0, salt) }
        let a = g(x0, y0) + (g(x0 + 1, y0) - g(x0, y0)) * sx
        let b = g(x0, y0 + 1) + (g(x0 + 1, y0 + 1) - g(x0, y0 + 1)) * sx
        return a + (b - a) * sy
    }

    private static func fbm(_ u: Float, _ v: Float, salt: UInt32) -> Float {
        let a = vnoise(u, v, cells: 3, salt: salt) * 0.5
        let b = vnoise(u, v, cells: 6, salt: salt &+ 1) * 0.3
        let c = vnoise(u, v, cells: 12, salt: salt &+ 2) * 0.2
        return a + b + c
    }

    // Distance from p to the segment ab, and which side of it p lies on (sign of the cross product).
    private static func segDist(_ p: V2, _ a: V2, _ b: V2) -> (Float, Float) {
        let ab = b - a
        let t = simd_clamp(simd_dot(p - a, ab) / max(1e-6, simd_dot(ab, ab)), 0, 1)
        let q = a + ab * t
        let side = ab.x * (p.y - a.y) - ab.y * (p.x - a.x)
        return (simd_length(p - q), side)
    }

    // Fracture lines: zigzag walkers holding a rough heading branch from a few impact points, more and longer at each
    // stage, tapering toward their tips; a dark core with a faint lit lip on one side (relief) at 32 px and up.
    private static func cracks(_ n: Int, stage s: Int) -> [V4] {
        struct Seg { var a: V2; var b: V2; var birth: Int; var order: Int; var total: Int }
        var rng = SRng(0xC4AC)
        var segs: [Seg] = []
        let starts: [(V2, Int)] = [(V2(0.42, 0.47), 1), (V2(0.62, 0.3), 2), (V2(0.25, 0.72), 3), (V2(0.74, 0.7), 4)]
        for (st, birth) in starts {
            let arms = birth == 1 ? 3 : 2
            for k in 0..<arms {
                var p = st
                var heading = Float(k) / Float(arms) * 2 * .pi + rng.float() * 1.2
                let steps = 10 + rng.int(8)
                for i in 0..<steps {
                    let ang = heading + (rng.float() - 0.5) * 1.3
                    heading += (rng.float() - 0.5) * 0.35
                    let len: Float = 0.025 + rng.float() * 0.025
                    let q = p + V2(cosf(ang), sinf(ang)) * len
                    segs.append(Seg(a: p, b: q, birth: birth, order: i, total: steps))
                    if rng.float() < 0.16 && i > 1 {
                        // A short side branch.
                        var bp = q
                        let bh = heading + (rng.float() < 0.5 ? 1 : -1) * (0.6 + rng.float() * 0.6)
                        let nb = 2 + rng.int(4)
                        for j in 0..<nb {
                            let ba = bh + (rng.float() - 0.5) * 1.2
                            let bq = bp + V2(cosf(ba), sinf(ba)) * 0.025
                            segs.append(Seg(a: bp, b: bq, birth: birth, order: i + j + 3, total: i + nb + 3))
                            bp = bq
                        }
                    }
                    p = q
                }
            }
        }
        // A stage shows walkers born by then; each grows over two stages (the first eight steps at birth).
        let visible = segs.filter { seg in
            guard seg.birth <= s else { return false }
            return s - seg.birth + 1 >= 2 || seg.order < 8
        }
        let lip: Float = n >= 32 ? 1.3 / Float(n) : 0
        let minW: Float = 0.5 / Float(n)
        var px = [V4](repeating: V4(0, 0, 0, 0), count: n * n)
        for y in 0..<n { for x in 0..<n {
            let p = V2((Float(x) + 0.5) / Float(n), (Float(y) + 0.5) / Float(n))
            var best: Float = 9, side: Float = 0, bw: Float = 1
            for seg in visible {
                let (d, sd) = segDist(p, seg.a, seg.b)
                let taper: Float = 1 - 0.7 * Float(seg.order) / Float(max(1, seg.total))
                let wdt = max(minW, (0.016 + 0.002 * Float(s)) * taper)
                if d - wdt < best { best = d - wdt; side = sd; bw = wdt }
            }
            if best < 0 {
                let k = min(1, -best / (bw * 0.5))
                px[y * n + x] = V4(0.05, 0.045, 0.04, 0.5 + 0.4 * k)
            } else if best < lip && side > 0 {
                px[y * n + x] = V4(0.92, 0.9, 0.86, 0.22)
            }
        } }
        return px
    }

    // Soot and char: noisy patches that spread and darken per stage; the last stage cracks into charred checks.
    private static func scorch(_ n: Int, stage s: Int) -> [V4] {
        let t: Float = [0.6, 0.44, 0.24][max(0, min(2, s - 1))]
        let maxA: Float = [0.6, 0.78, 0.92][max(0, min(2, s - 1))]
        var px = [V4](repeating: V4(0, 0, 0, 0), count: n * n)
        for y in 0..<n { for x in 0..<n {
            let u = (Float(x) + 0.5) / Float(n), v = (Float(y) + 0.5) / Float(n)
            let f = fbm(u, v, salt: 0x5C07) + (1 - v) * 0.12          // flames lick upward: more soot toward the top
            guard f > t else { continue }
            var a = min(1, (f - t) * 5) * maxA
            var c = V3(0.07, 0.05, 0.04)
            if s >= 3 {
                // Alligator checks: cell borders black, cell faces a little sheen.
                let cu = u * 5, cv = v * 6
                var d1: Float = 9, d2: Float = 9
                let ix = Int(floorf(cu)), iy = Int(floorf(cv))
                for oy in -1...1 { for ox in -1...1 {
                    let gx = ix + ox, gy = iy + oy
                    let jx = hashf((gx % 5 + 5) % 5, (gy % 6 + 6) % 6, 1, 0xA11) * 0.8 + 0.1
                    let jy = hashf((gx % 5 + 5) % 5, (gy % 6 + 6) % 6, 2, 0xA11) * 0.8 + 0.1
                    let d = simd_length(V2(cu - (Float(gx) + jx), cv - (Float(gy) + jy)))
                    if d < d1 { d2 = d1; d1 = d } else if d < d2 { d2 = d }
                } }
                let edge = d2 - d1
                if edge < 0.09 { c = V3(0.015, 0.012, 0.01); a = max(a, 0.95) } else { c += V3(0.05, 0.05, 0.05) * min(1, edge * 2) }
            }
            px[y * n + x] = V4(c.x, c.y, c.z, a)
        } }
        return px
    }

    // Dents in plate: shallow dishes lit from the upper left (shadowed near rim facing the light, bright far wall),
    // with scratches from the second stage.
    private static func dents(_ n: Int, stage s: Int) -> [V4] {
        var rng = SRng(0xDE47)
        var dents: [(V2, Float, Int)] = []
        for i in 0..<9 {
            let c = V2(0.12 + rng.float() * 0.76, 0.12 + rng.float() * 0.76)
            let r: Float = 0.07 + rng.float() * 0.08
            dents.append((c, r, i < 2 ? 1 : (i < 5 ? 2 : 3)))
        }
        var scratches: [(V2, V2)] = []
        for _ in 0..<6 {
            let a = V2(rng.float(), rng.float())
            let ang = rng.float() * .pi
            scratches.append((a, a + V2(cosf(ang), sinf(ang)) * (0.15 + rng.float() * 0.2)))
        }
        let L = simd_normalize(V2(-0.7, -0.7))
        var px = [V4](repeating: V4(0, 0, 0, 0), count: n * n)
        for y in 0..<n { for x in 0..<n {
            let p = V2((Float(x) + 0.5) / Float(n), (Float(y) + 0.5) / Float(n))
            var out = V4(0, 0, 0, 0)
            for (c, r, born) in dents where born <= s {
                let d = p - c
                let l = simd_length(d) / r
                guard l < 1 else { continue }
                let dir = l > 1e-4 ? d / (l * r) : V2(0, 0)
                let shade = simd_dot(dir, L) * sinf(l * .pi)
                if shade > 0 { out = V4(0.02, 0.02, 0.025, max(out.w, 0.15 + 0.45 * shade)) }
                else { out = V4(0.95, 0.95, 0.92, max(out.w, 0.4 * -shade)) }
            }
            if s >= 2 && out.w < 0.1 {
                for (i, sc) in scratches.enumerated() where i < (s == 2 ? 3 : 6) {
                    let (d, _) = segDist(p, sc.0, sc.1)
                    if d < max(0.008, 0.5 / Float(n)) { out = V4(0.85, 0.85, 0.82, 0.3) }
                }
            }
            px[y * n + x] = out
        } }
        return px
    }

    // A glass shard sprite: a slim bright triangle with a lit edge.
    private static func shard(_ n: Int) -> [V4] {
        let a = V2(0.2, 0.9), b = V2(0.85, 0.75), c = V2(0.45, 0.08)
        func edge(_ p: V2, _ q: V2, _ r: V2) -> Float { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        var px = [V4](repeating: V4(0, 0, 0, 0), count: n * n)
        for y in 0..<n { for x in 0..<n {
            let p = V2((Float(x) + 0.5) / Float(n), (Float(y) + 0.5) / Float(n))
            let e0 = edge(a, b, p), e1 = edge(b, c, p), e2 = edge(c, a, p)
            let inside = (e0 >= 0 && e1 >= 0 && e2 >= 0) || (e0 <= 0 && e1 <= 0 && e2 <= 0)
            guard inside else { continue }
            let (dEdge, _) = segDist(p, c, a)
            let lit: Float = dEdge < 0.08 ? 1 : 0.78 + 0.1 * p.y
            px[y * n + x] = V4(0.8 * lit + 0.15, 0.92 * lit + 0.06, 1.0 * lit, 1)
        } }
        return px
    }

    // Charcoal: charred wood with deep alligator cracks; smouldering charcoal glows orange in the cracks.
    private static func charcoal(_ n: Int, glow: Bool) -> [V4] {
        var px = [V4](repeating: V4(0, 0, 0, 1), count: n * n)
        for y in 0..<n { for x in 0..<n {
            let u = (Float(x) + 0.5) / Float(n), v = (Float(y) + 0.5) / Float(n)
            let cu = u * 4, cv = v * 5
            let ix = Int(floorf(cu)), iy = Int(floorf(cv))
            var d1: Float = 9, d2: Float = 9
            var cellH: Float = 0
            for oy in -1...1 { for ox in -1...1 {
                let gx = ((ix + ox) % 4 + 4) % 4, gy = ((iy + oy) % 5 + 5) % 5
                let jx = hashf(gx, gy, 3, 0xC4A2) * 0.7 + 0.15, jy = hashf(gx, gy, 4, 0xC4A2) * 0.7 + 0.15
                let d = simd_length(V2(cu - (Float(ix + ox) + jx), cv - (Float(iy + oy) + jy)))
                if d < d1 { d2 = d1; d1 = d; cellH = hashf(gx, gy, 5, 0xC4A2) } else if d < d2 { d2 = d }
            } }
            let edge = d2 - d1
            let grain = vnoise(u * 0.4, v, cells: 8, salt: 0x6A1) * 0.06
            let shade: Float = 0.8 + cellH * 0.4
            var c: V3 = V3(0.11, 0.095, 0.085) * shade
            c += V3(repeating: grain)
            // Sheen on the upper face of each check (convex blisters).
            let sheen: Float = max(0, 1 - d1 * 2.2) * (1 - v * 0.5)
            c += V3(0.06, 0.06, 0.065) * sheen
            if edge < 0.1 {
                let k = 1 - edge / 0.1
                if glow {
                    let hot = 0.6 + 0.4 * vnoise(u, v, cells: 6, salt: 0xE3B)
                    c = simd_mix(c, V3(1.0, 0.42 * hot, 0.08) * hot, V3(repeating: k))
                } else {
                    c *= 1 - 0.85 * k
                }
            }
            px[y * n + x] = V4(c.x, c.y, c.z, 1)
        } }
        return px
    }
}
