import Foundation
import simd

// High-resolution textures (TextureGen.size, default 128 px per face). Every layer comes from either
//   an HD material generator (this file): procedural materials designed at full resolution (warped fractal noise,
//   Voronoi cells, palette ramps, relief lighting), so stone, dirt, wood, sand, gravel, leaves, ores... have real
//   detail instead of scaled-up pixels; or
//   the 16 px painter upscaled edge-preservingly with a little micro-detail and relief (everything without an
//   HD material yet), or nearest-neighbour for glyphs and HUD art that must stay crisp.
// All generators are tileable (noise wraps at the texture size) and deterministic. Prototypes: tools/matlab.py.
enum HDTex {
    // A float image n x n (RGBA, 0...1), row-major.
    struct Img {
        let n: Int
        var px: [V4]
        init(_ n: Int, _ fill: V4 = V4(0, 0, 0, 1)) { self.n = n; px = [V4](repeating: fill, count: n * n) }
        @inline(__always) subscript(_ x: Int, _ y: Int) -> V4 {
            get { px[(((y % n) + n) % n) * n + (((x % n) + n) % n)] }
            set { px[(((y % n) + n) % n) * n + (((x % n) + n) % n)] = newValue }
        }
    }

    // MARK: Noise (tileable at n)

    @inline(__always) static func h2(_ x: Int, _ y: Int, _ s: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ s &* -2048144789)
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        return Float(h & 0xFFFF) / 65535
    }

    // Value noise field n x n with cells of `cell` pixels (n must be a multiple of cell).
    static func vnoise(_ n: Int, _ cell: Int, _ s: Int) -> [Float] {
        let c = max(1, min(n, cell))
        let g = max(1, n / c)
        var out = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            let fy: Float = Float(y) / Float(c)
            let y0 = Int(fy)
            var ty: Float = fy - Float(y0)
            ty = ty * ty * (3 - 2 * ty)
            for x in 0..<n {
                let fx: Float = Float(x) / Float(c)
                let x0 = Int(fx)
                var tx: Float = fx - Float(x0)
                tx = tx * tx * (3 - 2 * tx)
                let a0 = h2(x0 % g, y0 % g, s), a1 = h2((x0 + 1) % g, y0 % g, s)
                let b0 = h2(x0 % g, (y0 + 1) % g, s), b1 = h2((x0 + 1) % g, (y0 + 1) % g, s)
                let a: Float = a0 + (a1 - a0) * tx
                let b: Float = b0 + (b1 - b0) * tx
                out[y * n + x] = a + (b - a) * ty
            }
        }
        return out
    }

    // Fractal sum of value noise from cell `base` down, halving each octave.
    static func fbm(_ n: Int, _ base: Int, _ octaves: Int, _ s: Int, gain: Float = 0.5) -> [Float] {
        var out = [Float](repeating: 0, count: n * n)
        var amp: Float = 1, tot: Float = 0
        var cell = max(1, base)
        for o in 0..<octaves {
            let v = vnoise(n, cell, s &+ o &* 17)
            for i in 0..<(n * n) { out[i] += v[i] * amp }
            tot += amp
            amp *= gain
            cell = max(1, cell / 2)
        }
        for i in 0..<(n * n) { out[i] /= tot }
        return out
    }

    // Field sampled through a displacement (domain warp), wrapping.
    static func warp(_ f: [Float], _ n: Int, _ dx: [Float], _ dy: [Float], _ amount: Float) -> [Float] {
        var out = [Float](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let sx = x + Int((dx[i] - 0.5) * amount), sy = y + Int((dy[i] - 0.5) * amount)
            out[i] = f[(((sy % n) + n) % n) * n + (((sx % n) + n) % n)]
        } }
        return out
    }

    // Voronoi: F1, F2 distances in pixels and a per-cell random value, tileable.
    static func voronoi(_ n: Int, _ cells: Int, _ s: Int, jitter: Float = 0.9) -> (f1: [Float], f2: [Float], id: [Float]) {
        let c: Float = Float(n) / Float(cells)
        var f1 = [Float](repeating: 1e9, count: n * n), f2 = f1, id = [Float](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n {
            let cx = Int(Float(x) / c), cy = Int(Float(y) / c)
            var d1: Float = 1e9, d2: Float = 1e9, best: Float = 0
            for dy in -1...1 { for dx in -1...1 {
                let gx = cx + dx, gy = cy + dy
                let wx = ((gx % cells) + cells) % cells, wy = ((gy % cells) + cells) % cells
                let jx: Float = (h2(wx, wy, s) - 0.5) * jitter
                let jy: Float = (h2(wx, wy, s &+ 1) - 0.5) * jitter
                let px: Float = (Float(gx) + 0.5 + jx) * c
                let py: Float = (Float(gy) + 0.5 + jy) * c
                let ex: Float = Float(x) - px, ey: Float = Float(y) - py
                let d: Float = (ex * ex + ey * ey).squareRoot()
                if d < d1 { d2 = d1; d1 = d; best = h2(wx, wy, s &+ 2) } else if d < d2 { d2 = d }
            } }
            let i = y * n + x
            f1[i] = d1; f2[i] = d2; id[i] = best
        } }
        return (f1, f2, id)
    }

    // Palette ramp: stops (position, hex colour).
    static func ramp(_ t: Float, _ stops: [(Float, UInt32)]) -> V3 {
        let tt = simd_clamp(t, 0, 1)
        func c(_ h: UInt32) -> V3 { V3(Float((h >> 16) & 255), Float((h >> 8) & 255), Float(h & 255)) / 255 }
        var prev = stops[0]
        for s in stops.dropFirst() {
            if tt <= s.0 {
                let k: Float = (tt - prev.0) / max(1e-5, s.0 - prev.0)
                return c(prev.1) * (1 - k) + c(s.1) * k
            }
            prev = s
        }
        return c(stops[stops.count - 1].1)
    }

    // Top-left relief lighting factor from a height field.
    static func light(_ h: [Float], _ n: Int, _ k: Float) -> [Float] {
        var out = [Float](repeating: 1, count: n * n)
        for y in 0..<n { for x in 0..<n {
            let l = h[y * n + (x + n - 1) % n], r = h[y * n + (x + 1) % n]
            let u = h[((y + n - 1) % n) * n + x], d = h[((y + 1) % n) * n + x]
            let g: Float = (r - l) + (d - u)
            out[y * n + x] = 1 - g * k
        } }
        return out
    }

    // MARK: Materials

    typealias Gen = (Int, Int) -> Img          // (size, seed) -> image

    static func stone(_ pal: [(Float, UInt32)], crackAmt: Float = 1) -> Gen {
        { n, s in
            let base = fbm(n, n / 2, 6, s)
            let wx = fbm(n, n / 4, 3, s &+ 9), wy = fbm(n, n / 4, 3, s &+ 7)
            let h = warp(base, n, wx, wy, Float(n) * 0.18)
            let mottle = fbm(n, n / 8, 3, s &+ 11)
            let grain = vnoise(n, max(1, n / 64), s &+ 5)
            let v = voronoi(n, 4, s &+ 3)
            let crackMask = fbm(n, n / 8, 2, s &+ 4)
            var hh = [Float](repeating: 0, count: n * n)
            var img = Img(n)
            for i in 0..<(n * n) {
                // Thin, broken cracks only where the mask is high (not a regular network).
                let edge: Float = v.f2[i] - v.f1[i]
                let crack: Float = (crackMask[i] > 0.6 ? max(0, 1 - edge / (Float(n) / 90)) : 0) * crackAmt
                let t0: Float = h[i] * 0.75 + (mottle[i] - 0.5) * 0.35
                let t1: Float = (grain[i] - 0.5) * 0.12 + 0.12 - crack * 0.25
                let t: Float = t0 + t1
                let hm: Float = h[i] * 0.5 + mottle[i] * 0.2
                hh[i] = hm - crack * 0.4
                let c = ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
            }
            let lt = light(hh, n, 1.6 * Float(n) / 128)
            for i in 0..<(n * n) { img.px[i] = V4(img.px[i].x * lt[i], img.px[i].y * lt[i], img.px[i].z * lt[i], 1) }
            return img
        }
    }

    static func soil(_ pal: [(Float, UInt32)], pebble: UInt32, pebbles: Int = 18) -> Gen {
        { n, s in
            let h = fbm(n, n / 4, 5, s)
            let fine = vnoise(n, max(1, n / 64), s &+ 1)
            let v = voronoi(n, pebbles, s &+ 3, jitter: 1)
            var hh = [Float](repeating: 0, count: n * n)
            var img = Img(n)
            let pr: Float = Float(n) / 64
            func c(_ hx: UInt32) -> V3 { V3(Float((hx >> 16) & 255), Float((hx >> 8) & 255), Float(hx & 255)) / 255 }
            for i in 0..<(n * n) {
                let isPebble = v.id[i] > 0.72 && v.f1[i] < pr * (1 + v.id[i] * 1.6)
                var col = ramp(h[i] + (fine[i] - 0.5) * 0.22, pal)
                hh[i] = h[i] * 0.4 + fine[i] * 0.15
                if isPebble {
                    let k: Float = 0.75 + v.id[i] * 0.35
                    col = c(pebble) * k
                    hh[i] += (pr * (1 + v.id[i] * 1.6) - v.f1[i]) / (pr * 3)
                }
                img.px[i] = V4(col.x, col.y, col.z, 1)
            }
            let lt = light(hh, n, 1.2 * Float(n) / 128)
            for i in 0..<(n * n) { img.px[i] = V4(img.px[i].x * lt[i], img.px[i].y * lt[i], img.px[i].z * lt[i], 1) }
            return img
        }
    }

    // Grey (biome-tinted at runtime) grass mat with thousands of short blades.
    static func grassTop(_ n: Int, _ s: Int) -> Img {
        let base = fbm(n, n / 8, 4, s)
        var g = [Float](repeating: 0, count: n * n)
        for i in 0..<(n * n) { g[i] = 0.5 + (base[i] - 0.5) * 0.25 }
        var rng = SRng(UInt64(truncatingIfNeeded: s) &* 7919 &+ 1)
        let blades = n * n / 6
        let len = max(2, n / 24)
        for _ in 0..<blades {
            let cx = rng.int(n), cy = rng.int(n)
            let ang: Float = rng.float() * .pi
            let v: Float = 0.6 + rng.float() * 0.4
            let L = rng.range(len, len * 2)
            for t in 0..<L {
                let px = Int(Float(cx) + cosf(ang) * Float(t)), py = Int(Float(cy) + sinf(ang) * Float(t))
                g[(((py % n) + n) % n) * n + (((px % n) + n) % n)] = v * (0.85 + 0.15 * Float(t) / Float(L))
            }
        }
        let lt = light(g.map { $0 * 0.5 }, n, Float(n) / 128)
        var img = Img(n)
        for i in 0..<(n * n) { let k = g[i] * lt[i]; img.px[i] = V4(k, k, k, 1) }
        return img
    }

    // Grey (tinted) leaves: overlapping leaf ellipses with gaps for the cutout.
    static func leaves(_ n: Int, _ s: Int) -> Img {
        var img = Img(n, V4(0, 0, 0, 0))
        var rng = SRng(UInt64(truncatingIfNeeded: s) &* 104729 &+ 3)
        let count = n * n / 40
        let scale: Float = Float(n) / 128
        for _ in 0..<count {
            let cx: Float = rng.float() * Float(n), cy: Float = rng.float() * Float(n)
            let ang: Float = rng.float() * .pi
            let L: Float = (5 + rng.float() * 4) * scale
            let W: Float = L * 0.45
            let v: Float = 0.45 + rng.float() * 0.55
            let r = Int(L) + 1
            let ca = cosf(ang), sa = sinf(ang)
            for dy in -r...r { for dx in -r...r {
                let fdx = Float(dx), fdy = Float(dy)
                let u: Float = fdx * ca + fdy * sa
                let w: Float = fdy * ca - fdx * sa
                let ue: Float = u / L, we: Float = w / W
                if ue * ue + we * we >= 1 { continue }
                let vein: Float = abs(w) < W * 0.12 ? 0.78 : 1
                let k: Float = v * (0.8 + 0.2 * ue) * vein
                img[Int(cx) + dx, Int(cy) + dy] = V4(k, k, k, 1)
            } }
        }
        return img
    }

    static func barkSide(_ pal: [(Float, UInt32)]) -> Gen {
        { n, s in
            // Vertical plates split by deep, wandering fissures.
            let w = fbm(n, n / 4, 3, s)
            let plates = vnoise(n, max(1, n / 16), s &+ 4)
            let fine = fbm(n, max(1, n / 32), 2, s &+ 2)
            var hh = [Float](repeating: 0, count: n * n)
            var img = Img(n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let wv: Float = (w[i] - 0.5) * Float(n) * 0.18
                let xs: Float = Float(x) + wv
                let stripe: Float = abs(sinf(xs / Float(n) * 2 * .pi * 7))
                let fissure: Float = stripe < 0.18 ? (0.18 - stripe) / 0.18 : 0
                let pv: Float = plates[(y / max(1, n / 8)) * n + x]
                let t0: Float = 0.55 + (pv - 0.5) * 0.25
                let t1: Float = (fine[i] - 0.5) * 0.3 - fissure * 0.45
                let t: Float = t0 + t1
                hh[i] = -fissure * 0.6 + fine[i] * 0.2
                let c = ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
            } }
            let lt = light(hh, n, 1.4 * Float(n) / 128)
            for i in 0..<(n * n) { img.px[i] = V4(img.px[i].x * lt[i], img.px[i].y * lt[i], img.px[i].z * lt[i], 1) }
            return img
        }
    }

    static func planks(_ pal: [(Float, UInt32)]) -> Gen {
        { n, s in
            let rows = 4
            let bh = n / rows
            var hh = [Float](repeating: 0, count: n * n)
            var img = Img(n)
            let grainW = fbm(n, n / 4, 3, s)
            let fine = vnoise(n, max(1, n / 64), s &+ 1)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let board = y / bh
                let off = Int(h2(board, 0, s) * Float(n / 2))
                let bx = (x + off) % (n / 2)
                let seam = bx < max(1, n / 64) || (y % bh) < max(1, n / 64)
                let boardTone: Float = h2(board &* 7 &+ (x + off) / (n / 2), 1, s) * 0.16
                let gy: Float = Float(y) + (grainW[i] - 0.5) * Float(bh) * 0.9
                let grain: Float = 0.5 + 0.5 * sinf(gy / Float(n) * 2 * .pi * 18)
                // A knot now and then.
                let kx = Float(Int(h2(board, 2, s) * Float(n))), ky = Float(board * bh + bh / 2)
                let kdx: Float = Float(x) - kx, kdy: Float = Float(y) - ky
                let kd2: Float = kdx * kdx * 0.6 + kdy * kdy * 2
                let kd: Float = kd2.squareRoot()
                let knot: Float = h2(board, 3, s) > 0.55 ? max(0, 1 - kd / (Float(n) / 24)) : 0
                let t0: Float = 0.35 + grain * 0.28 + (fine[i] - 0.5) * 0.1
                var t: Float = t0 + boardTone - knot * 0.45
                if seam { t -= 0.35 }
                hh[i] = (seam ? -0.25 : 0) + grain * 0.04 - knot * 0.1
                let c = ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
            } }
            let lt = light(hh, n, 0.8 * Float(n) / 128)
            for i in 0..<(n * n) { img.px[i] = V4(img.px[i].x * lt[i], img.px[i].y * lt[i], img.px[i].z * lt[i], 1) }
            return img
        }
    }

    static func cobble(_ pal: [(Float, UInt32)], mortar: UInt32, cells: Int = 5) -> Gen {
        { n, s in
            let v = voronoi(n, cells, s, jitter: 0.8)
            let tone = fbm(n, n / 4, 4, s &+ 2)
            let fine = vnoise(n, max(1, n / 64), s &+ 3)
            let mw: Float = Float(n) / 64
            var hh = [Float](repeating: 0, count: n * n)
            var img = Img(n)
            let mc = V3(Float((mortar >> 16) & 255), Float((mortar >> 8) & 255), Float(mortar & 255)) / 255
            for i in 0..<(n * n) {
                let edge: Float = v.f2[i] - v.f1[i]
                if edge < mw * 1.6 {
                    let k: Float = 0.85 + fine[i] * 0.3
                    img.px[i] = V4(mc.x * k, mc.y * k, mc.z * k, 1)
                    hh[i] = -0.15
                } else {
                    let dome: Float = min(1, (edge - mw * 1.6) / (Float(n) / 10))
                    let tc: Float = v.id[i] * 0.5 + tone[i] * 0.4
                    let c = ramp(tc + (fine[i] - 0.5) * 0.12, pal)
                    img.px[i] = V4(c.x, c.y, c.z, 1)
                    hh[i] = dome * 0.35 + tone[i] * 0.15
                }
            }
            let lt = light(hh, n, 1.2 * Float(n) / 128)
            for i in 0..<(n * n) { img.px[i] = V4(img.px[i].x * lt[i], img.px[i].y * lt[i], img.px[i].z * lt[i], 1) }
            return img
        }
    }

    static func sandLike(_ pal: [(Float, UInt32)]) -> Gen {
        { n, s in
            let w = fbm(n, n / 2, 3, s)
            let grain = vnoise(n, max(1, n / 128), s &+ 1)
            let blot = fbm(n, n / 4, 3, s &+ 2)
            var img = Img(n)
            var hh = [Float](repeating: 0, count: n * n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let wy: Float = Float(y) + (w[i] - 0.5) * Float(n) * 0.25
                let rip: Float = 0.5 + 0.5 * sinf(wy / Float(n) * 2 * .pi * 6)
                let t0: Float = 0.55 + (grain[i] - 0.5) * 0.24
                var t: Float = t0 + (rip - 0.5) * 0.10 + (blot[i] - 0.5) * 0.15
                if grain[i] > 0.93 { t -= 0.25 }               // dark grains
                hh[i] = rip * 0.06
                let c = ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
            } }
            let lt = light(hh, n, Float(n) / 128)
            for i in 0..<(n * n) { img.px[i] = V4(img.px[i].x * lt[i], img.px[i].y * lt[i], img.px[i].z * lt[i], 1) }
            return img
        }
    }

    static func gravel(_ pal: [(Float, UInt32)]) -> Gen {
        { n, s in
            let v = voronoi(n, 11, s, jitter: 1)
            let fine = fbm(n, max(1, n / 16), 2, s &+ 1)
            var img = Img(n)
            var hh = [Float](repeating: 0, count: n * n)
            for i in 0..<(n * n) {
                let edge: Float = v.f2[i] - v.f1[i]
                var c = ramp(v.id[i] * 0.7 + fine[i] * 0.3, pal)
                if edge < Float(n) / 100 { c *= 0.55 }
                hh[i] = min(1, edge / (Float(n) / 25)) * 0.6
                img.px[i] = V4(c.x, c.y, c.z, 1)
            }
            let lt = light(hh, n, 1.3 * Float(n) / 128)
            for i in 0..<(n * n) { img.px[i] = V4(img.px[i].x * lt[i], img.px[i].y * lt[i], img.px[i].z * lt[i], 1) }
            return img
        }
    }

    // Ore: crystal clusters (faceted Voronoi chips) set into a stone material, with a dark rim.
    static func ore(_ base: @escaping Gen, _ c0: UInt32, _ c1: UInt32, clusters: Int = 6) -> Gen {
        { n, s in
            var img = base(n, s &+ 31)
            let facets = voronoi(n, max(8, n / 6), s &+ 5, jitter: 1)
            var rng = SRng(UInt64(truncatingIfNeeded: s) &* 31337 &+ 7)
            let a = V3(Float((c0 >> 16) & 255), Float((c0 >> 8) & 255), Float(c0 & 255)) / 255
            let b = V3(Float((c1 >> 16) & 255), Float((c1 >> 8) & 255), Float(c1 & 255)) / 255
            let wob = fbm(n, max(1, n / 16), 2, s &+ 6)
            for _ in 0..<clusters {
                let cx: Float = Float(n) * (0.1 + rng.float() * 0.8), cy: Float = Float(n) * (0.1 + rng.float() * 0.8)
                let r: Float = Float(n) * (0.06 + rng.float() * 0.05)
                let ri = Int(r * 1.5) + 2
                for dy in -ri...ri { for dx in -ri...ri {
                    let x = Int(cx) + dx, y = Int(cy) + dy
                    let i = (((y % n) + n) % n) * n + (((x % n) + n) % n)
                    let d0: Float = Float(dx * dx + dy * dy).squareRoot()
                    let d: Float = d0 + (wob[i] - 0.5) * r * 0.8
                    if d < r {
                        let f: Float = facets.id[i]
                        var c = a * (1 - f) + b * f
                        if facets.f2[i] - facets.f1[i] < Float(n) / 128 { c *= 0.62 }       // facet edges
                        if dx < 0 && dy < 0 && f > 0.6 { c = simd_min(V3(1, 1, 1), c * 1.2) }  // glint
                        img.px[i] = V4(c.x, c.y, c.z, 1)
                    } else if d < r + Float(n) / 70 {
                        img.px[i] = V4(img.px[i].x * 0.68, img.px[i].y * 0.68, img.px[i].z * 0.68, 1)
                    }
                } }
            }
            return img
        }
    }

    // MARK: Registry

    static let stoneGrey: [(Float, UInt32)] = [(0, 0x5C5C60), (0.45, 0x7C7C80), (0.75, 0x929192), (1, 0xACAAA8)]
    static let deepslate: [(Float, UInt32)] = [(0, 0x2E2E34), (0.5, 0x48484E), (1, 0x64646A)]
    static let dirtPal: [(Float, UInt32)] = [(0, 0x4A3222), (0.5, 0x6E4E34), (1, 0x8C6646)]
    static let oakPlank: [(Float, UInt32)] = [(0, 0x7E5C34), (0.5, 0xA67E4C), (1, 0xC49C62)]
    static let oakBark: [(Float, UInt32)] = [(0, 0x3C2C1C), (0.5, 0x60482C), (1, 0x80623E)]

    static let table: [String: Gen] = [
        "stone": stone(stoneGrey),
        "andesite": stone([(0, 0x6E6E6E), (0.5, 0x8A8A8A), (1, 0xA6A6A4)], crackAmt: 0.3),
        "diorite": stone([(0, 0x9E9E9C), (0.5, 0xC6C6C4), (1, 0xE8E8E6)], crackAmt: 0.2),
        "granite": stone([(0, 0x7A4E40), (0.5, 0x9A6A58), (1, 0xB88A74)], crackAmt: 0.4),
        "tuff": stone([(0, 0x55564E), (0.5, 0x6C6D64), (1, 0x86877C)], crackAmt: 0.5),
        "deepslate": stone(deepslate, crackAmt: 0.8),
        "dirt": soil(dirtPal, pebble: 0x84786A),
        "coarse_dirt": soil([(0, 0x4C3626), (0.5, 0x6C5038), (1, 0x8A6A4C)], pebble: 0x7C7468, pebbles: 26),
        "grass_block_top": grassTop,
        "oak_leaves": leaves,
        "oak_log": barkSide(oakBark),
        "oak_planks": planks(oakPlank),
        "spruce_planks": planks([(0, 0x523A22), (0.5, 0x6E5034), (1, 0x8A6844)]),
        "birch_planks": planks([(0, 0xA89664), (0.5, 0xC4B07C), (1, 0xDCCA98)]),
        "cobblestone": cobble([(0, 0x585A5C), (0.5, 0x808082), (1, 0xA2A09E)], mortar: 0x3A3838),
        "mossy_cobblestone": cobble([(0, 0x4C5A40), (0.5, 0x6E7A58), (1, 0x8C9474)], mortar: 0x2E3A26),
        "sand": sandLike([(0, 0xC4B280), (0.5, 0xDCCC96), (1, 0xF0E4B4)]),
        "red_sand": sandLike([(0, 0x9E5222), (0.5, 0xB8662C), (1, 0xD0803C)]),
        "gravel": gravel([(0, 0x5C5654), (0.4, 0x7C7672), (0.7, 0x968C80), (1, 0xB0A8A0)]),
        "coal_ore": ore(stone(stoneGrey), 0x1E1E20, 0x46464A),
        "iron_ore": ore(stone(stoneGrey), 0xC4966E, 0xECCCAA),
        "copper_ore": ore(stone(stoneGrey), 0xB8683C, 0x6ECAA4),
        "gold_ore": ore(stone(stoneGrey), 0xD8A824, 0xFCE878),
        "redstone_ore": ore(stone(stoneGrey), 0x9A0E0E, 0xFF3C3C),
        "lapis_ore": ore(stone(stoneGrey), 0x1C3A9C, 0x4C7CEC),
        "diamond_ore": ore(stone(stoneGrey), 0x3CC8D2, 0xBEFAFA),
        "emerald_ore": ore(stone(stoneGrey), 0x12A04A, 0x7CF4A8),
        "deepslate_coal_ore": ore(stone(deepslate), 0x161618, 0x3A3A3E),
        "deepslate_iron_ore": ore(stone(deepslate), 0xB08660, 0xDEBC98),
        "deepslate_gold_ore": ore(stone(deepslate), 0xCC9C20, 0xF4DE70),
        "deepslate_diamond_ore": ore(stone(deepslate), 0x34B8C2, 0xAEF0F0),
        "deepslate_redstone_ore": ore(stone(deepslate), 0x8C0C0C, 0xF03232),
        "deepslate_lapis_ore": ore(stone(deepslate), 0x18348C, 0x446EDC),
        "deepslate_emerald_ore": ore(stone(deepslate), 0x0E9042, 0x6CE498),
        "deepslate_copper_ore": ore(stone(deepslate), 0xA85E36, 0x60BA96),
    ]

    // MARK: Upscale for textures without an HD material

    // Edge-preserving 16 -> n upscale: each output pixel blends the four nearest source texels weighted by colour
    // similarity to its own texel (hard edges between colours, soft gradients inside a colour), then a little
    // micro-detail and relief so big flat texels don't read as smeared squares.
    static func upscale(_ src: [V4], detail: Float, salt: Int, n: Int) -> Img {
        let S = TextureGen.S
        let k: Float = Float(n) / Float(S)
        var img = Img(n)
        let fineN = vnoise(n, max(1, n / 32), salt)
        let fineM = vnoise(n, max(1, n / 128), salt &+ 1)
        var hh = [Float](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n {
            let fx: Float = (Float(x) + 0.5) / k - 0.5, fy: Float = (Float(y) + 0.5) / k - 0.5
            let x0 = Int(floorf(fx)), y0 = Int(floorf(fy))
            let tx: Float = fx - Float(x0), ty: Float = fy - Float(y0)
            let own = src[((y * S / n) % S) * S + (x * S / n) % S]
            var acc = V4(0, 0, 0, 0)
            var ws: Float = 0
            for (dy, dx) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
                let c = src[(((y0 + dy) % S + S) % S) * S + (((x0 + dx) % S + S) % S)]
                let wx: Float = dx == 0 ? 1 - tx : tx
                let wy: Float = dy == 0 ? 1 - ty : ty
                let d: V4 = c - own
                let dd: Float = simd_length_squared(d)
                let w: Float = wx * wy * expf(-dd / 0.004)
                acc += c * w
                ws += w
            }
            var c = acc / max(ws, 1e-6)
            let i = y * n + x
            let fm: Float = (fineN[i] - 0.5) * 0.6 + (fineM[i] - 0.5) * 0.4
            let m: Float = 1 + fm * detail
            c = V4(c.x * m, c.y * m, c.z * m, c.w)
            hh[i] = (c.x + c.y + c.z) / 3
            img.px[i] = c
        } }
        if detail > 0 {
            let lt = light(hh, n, 0.5 * Float(n) / 128)
            for i in 0..<(n * n) { let c = img.px[i]; img.px[i] = V4(c.x * lt[i], c.y * lt[i], c.z * lt[i], c.w) }
        }
        return img
    }
}
