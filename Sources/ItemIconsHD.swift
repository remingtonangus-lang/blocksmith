import Foundation
import simd

// P316 (Oct 15 18:30, "some items look really realistic in inventory, others really don't, like field rations"):
// most item icons come from the painted art in Resources/Textures (soft volume, dark contour, painterly grain), but an
// item without a picture fell back to its 16 px sprite blown up pixel for pixel, so the hotbar, crafting grid and chest
// mixed two styles. Every item layer without imported art now goes through `painted`, which renders the sprite the way
// the painted icons look: a rounded silhouette with a dark contour, smooth colour, relief lighting from the top left
// with a soft highlight, and a fine grain. The field ration, which he named, has its own painter (`ration`). All views
// (hotbar, inventory, crafting, chests, held and dropped items) draw the same texture layer, so one fix covers them.
enum ItemIconsHD {
    // The layers that are an item's icon on their own. Overlay pairs (potion liquid over its bottle, spawn egg spots...)
    // keep the plain upscale so the two halves stay registered with each other.
    static let layers: Set<String> = {
        var s = Set<String>()
        for d in Items.defs where d.overlay == nil {
            if let k = d.texKey { s.insert(k) } else if d.sprite != nil { s.insert("item_" + d.name) }
        }
        return s
    }()

    static func generator(_ name: String, _ src: [V4]) -> HDTex.Gen? {
        if name == "item_capital_ration" { return { n, _ in ration(n) } }
        guard layers.contains(name), src.contains(where: { $0.w > 0.5 }) else { return nil }
        return { n, s in painted(src, n: n, seed: s) }
    }

    @inline(__always) static func ss(_ e0: Float, _ e1: Float, _ v: Float) -> Float {
        let t = max(0, min(1, (v - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    static let nbrs: [(Int, Int, Float)] = [(-1, 0, 1), (0, -1, 1), (1, 0, 1), (0, 1, 1),
                                           (-1, -1, 1.41), (1, -1, 1.41), (1, 1, 1.41), (-1, 1, 1.41)]

    // P316 (b): a 16 px sprite as a painted n px icon.
    static func painted(_ src: [V4], n: Int, seed: Int) -> HDTex.Img {
        let S = TextureGen.S
        // Distance (16 px units) from each opaque texel to the nearest clear one: how far in from the rim it sits.
        var d = [Float](repeating: 0, count: S * S)
        for i in 0..<(S * S) where src[i].w > 0.5 { d[i] = 99 }
        for _ in 0..<2 {
            for pass in 0..<2 {
                for yy in 0..<S {
                    for xx in 0..<S {
                        let x = pass == 0 ? xx : S - 1 - xx
                        let y = pass == 0 ? yy : S - 1 - yy
                        if d[y * S + x] == 0 { continue }
                        var best = d[y * S + x]
                        for (dx, dy, w) in nbrs {
                            let nx = x + dx, ny = y + dy
                            let v: Float = (nx < 0 || ny < 0 || nx >= S || ny >= S) ? 0 : d[ny * S + nx]
                            best = min(best, v + w)
                        }
                        d[y * S + x] = best
                    }
                }
            }
        }
        let f = Float(n) / Float(S)
        var cov = [Float](repeating: 0, count: n * n), ol = cov, h = cov
        var col = [V3](repeating: V3(0, 0, 0), count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let u: Float = (Float(x) + 0.5) / f - 0.5
                let v: Float = (Float(y) + 0.5) / f - 0.5
                let x0 = Int(floorf(u)), y0 = Int(floorf(v))
                let fx: Float = u - Float(x0), fy: Float = v - Float(y0)
                let sx = ss(0, 1, fx), sy = ss(0, 1, fy)
                var acc = V3(0, 0, 0)
                var wa: Float = 0, aa: Float = 0, dd: Float = 0
                for k in 0..<4 {
                    let tx = x0 + (k & 1), ty = y0 + (k >> 1)
                    guard tx >= 0, ty >= 0, tx < S, ty < S else { continue }
                    let w: Float = ((k & 1) == 1 ? fx : 1 - fx) * ((k >> 1) == 1 ? fy : 1 - fy)
                    let ws: Float = ((k & 1) == 1 ? sx : 1 - sx) * ((k >> 1) == 1 ? sy : 1 - sy)
                    let p = src[ty * S + tx]
                    aa += w * p.w
                    acc += V3(p.x, p.y, p.z) * (ws * p.w)
                    wa += ws * p.w
                    dd += w * min(d[ty * S + tx], 3)
                }
                let i = y * n + x
                cov[i] = ss(0.28, 0.55, aa)                   // rounded silhouette instead of square pixels
                ol[i] = ss(0.06, 0.22, aa)                    // the dark contour just outside it
                col[i] = wa > 1e-4 ? acc / wa : V3(0, 0, 0)
                h[i] = dd
            }
        }
        // Relief: a dome that rounds off within ~2 sprite pixels of the rim, lit from the top left.
        let R: Float = 2.2
        var hh = [Float](repeating: 0, count: n * n)
        for i in 0..<(n * n) { let t = min(1, h[i] / R); hh[i] = (1 - (1 - t) * (1 - t)) * R }
        let L = simd_normalize(V3(-0.45, -0.55, 0.70))
        let H = simd_normalize(L + V3(0, 0, 1))
        let coarse = HDTex.vnoise(n, 8, seed)
        var img = HDTex.Img(n, V4(0, 0, 0, 0))
        for y in 0..<n {
            for x in 0..<n {
                let i = y * n + x
                let a = max(cov[i], ol[i])
                if a <= 0 { continue }
                let xl = max(0, x - 1), xr = min(n - 1, x + 1), yu = max(0, y - 1), yd = min(n - 1, y + 1)
                let gx: Float = (hh[y * n + xr] - hh[y * n + xl]) / Float(max(1, xr - xl)) * f
                let gy: Float = (hh[yd * n + x] - hh[yu * n + x]) / Float(max(1, yd - yu)) * f
                let nrm = simd_normalize(V3(-gx * 0.6, -gy * 0.6, 1))
                let ndl: Float = simd_dot(nrm, L)
                let sp: Float = powf(max(0, simd_dot(nrm, H)), 24)
                let fine: Float = HDTex.h2(x, y, seed &+ 1)
                let diag: Float = Float(x + y) / Float(2 * n)
                let k1: Float = 0.78 + 0.36 * ndl
                let k2: Float = 0.07 * (coarse[i] - 0.5) + 0.03 * (fine - 0.5) + 0.10 * (0.5 - diag)
                let c0 = col[i]
                let lum: Float = (c0.x + c0.y + c0.z) / 3
                var c = c0 * (k1 + k2) + V3(repeating: sp * 0.30 * (0.4 + lum))
                c *= 0.72 + 0.28 * ss(0, 0.9, h[i])           // contact shade at the rim
                c = c * cov[i] + c0 * 0.22 * (1 - cov[i])
                img.px[i] = V4(min(1, max(0, c.x)), min(1, max(0, c.y)), min(1, max(0, c.z)), a)
            }
        }
        return img
    }

    // P316 (b): the Capital's field ration as a painted icon: a foil-wrapped bar tilted up to the right, crinkled foil
    // facets catching the light, crimped and ridged ends, a lit top edge over a darker side, and the Capital's blue
    // band printed with a white ring mark.
    static func ration(_ n: Int) -> HDTex.Img {
        let foil = V3(0xA8, 0xB2, 0xBA) / 255, band = V3(0x2E, 0x5F, 0xA8) / 255, ink = V3(0.12, 0.12, 0.14)
        let ang: Float = 0.22, ca = cosf(ang), sa = sinf(ang)
        let len: Float = 0.32, wid: Float = 0.16, top: Float = 0.06, tab: Float = 0.105
        func local(_ u: Float, _ v: Float) -> (Float, Float) {
            let x = u - 0.5, y = v - 0.5
            return (x * ca - y * sa, x * sa + y * ca)
        }
        func part(_ a: Float, _ b: Float) -> Int {
            let aa = abs(a)
            if aa <= len {
                let r: Float = 0.035
                let dx = max(0, aa - (len - r)), dy = max(0, abs(b) - (wid - r))
                return (dx * dx + dy * dy).squareRoot() <= r ? 1 : 0
            }
            let t = aa - len
            guard t <= tab else { return 0 }
            let half: Float = wid - 0.02 + 0.02 * t / tab
            let saw: Float = abs((b * 34).truncatingRemainder(dividingBy: 2) + (b < 0 ? 2 : 0) - 1)
            let tip: Float = tab - 0.008 - 0.010 * saw
            return abs(b) <= half && t <= tip ? 2 : 0
        }
        func voronoi(_ x: Float, _ y: Float) -> (Float, Float, Float) {
            let xi = Int(floorf(x)), yi = Int(floorf(y))
            var f1: Float = 9, f2: Float = 9, idv: Float = 0
            for j in -1...1 {
                for i in -1...1 {
                    let cx = xi + i, cy = yi + j
                    let px: Float = Float(cx) + HDTex.h2(cx, cy, 5), py: Float = Float(cy) + HDTex.h2(cx, cy, 6)
                    let dd: Float = ((px - x) * (px - x) + (py - y) * (py - y)).squareRoot()
                    if dd < f1 { f2 = f1; f1 = dd; idv = HDTex.h2(cx, cy, 7) } else if dd < f2 { f2 = dd }
                }
            }
            return (f1, f2, idv)
        }
        func shade(_ a: Float, _ b: Float, _ k: Int) -> V3 {
            if k == 2 {                                       // crimped end: fine ridges across it, darker to the tip
                let t = abs(a) - len
                let rid: Float = 0.5 + 0.5 * sinf(b * 150)
                var c = foil * ((0.50 + 0.26 * rid) * (1 - 0.25 * t / tab))
                if b > top { c *= 0.75 }
                return c
            }
            var sh: Float
            if b < top {                                      // the pillowed top of the bar
                let p = max(0, min(1, (b + wid) / (top + wid)))
                let prof: Float = powf(sinf(.pi * p), 0.6)
                sh = (0.62 + 0.48 * prof) * (0.78 + 0.22 * ss(0, 1, (len - abs(a)) / 0.07))
            } else {                                          // the side facing the viewer, in shade
                let q = (b - top) / (wid - top)
                sh = (0.50 - 0.18 * q) * (0.85 + 0.15 * ss(0, 1, (len - abs(a)) / 0.05))
            }
            if b > top - 0.012 && b < top { sh += 0.20 }     // the lit edge between top and side
            if abs(a) < 0.085 {                               // the printed band
                var c = band * (sh * 1.05)
                if abs(abs(a) - 0.085) < 0.009 { c *= 0.6 }
                if b < top {
                    let du = a / 0.05, dv = (b + 0.045) / 0.05
                    let r = (du * du + dv * dv).squareRoot()
                    if (r > 0.6 && r < 1) || (abs(dv) < 0.17 && r < 1) { c = V3(0.90, 0.91, 0.93) * sh }
                } else if abs(b - (top + 0.045)) < 0.010 && abs(a) < 0.055 {
                    c = V3(0.78, 0.82, 0.90) * sh
                }
                return c
            }
            let (f1, f2, idv) = voronoi((a + 0.5) * 13, (b + 0.5) * 13)
            let edge = ss(0.06, 0, f2 - f1)
            var c = foil * (sh * (0.86 + 0.26 * idv)) + V3(repeating: 0.14 * edge * sh)
            if b < top {
                let streak = ss(0.10, 0, abs(b - (-wid + 0.30 * (top + wid))))
                c += V3(repeating: streak * 0.30 * (0.6 + 0.4 * idv))
            }
            return c
        }
        var img = HDTex.Img(n, V4(0, 0, 0, 0))
        let ring: Float = 1.3 / Float(n) * max(1, Float(n) / 64)
        for y in 0..<n {
            for x in 0..<n {
                var acc = V3(0, 0, 0)
                var cover: Float = 0
                for s in 0..<4 {
                    let u: Float = (Float(x) + 0.25 + 0.5 * Float(s & 1)) / Float(n)
                    let v: Float = (Float(y) + 0.25 + 0.5 * Float(s >> 1)) / Float(n)
                    let (a, b) = local(u, v)
                    let k = part(a, b)
                    if k > 0 {
                        let c = shade(a, b, k)
                        acc += V3(min(1, max(0, c.x)), min(1, max(0, c.y)), min(1, max(0, c.z)))
                        cover += 1
                        continue
                    }
                    for i in 0..<8 {                          // the dark contour around the wrapper
                        let t = Float(i) * .pi / 4
                        let (a2, b2) = local(u + ring * cosf(t), v + ring * sinf(t))
                        if part(a2, b2) > 0 { acc += ink; cover += 1; break }
                    }
                }
                if cover > 0 { let c = acc / cover; img.px[y * n + x] = V4(c.x, c.y, c.z, cover / 4) }
            }
        }
        return img
    }
}
