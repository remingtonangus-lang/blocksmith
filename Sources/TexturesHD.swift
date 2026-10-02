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

    @inline(__always) static func cl(_ v: Float) -> Float { max(0, min(1, v)) }
    @inline(__always) static func col(_ h: UInt32) -> V3 { V3(Float((h >> 16) & 255), Float((h >> 8) & 255), Float(h & 255)) / 255 }
    static func hexOf(_ c: V3) -> UInt32 {
        let r = UInt32(cl(c.x) * 255), g = UInt32(cl(c.y) * 255), b = UInt32(cl(c.z) * 255)
        return (r << 16) | (g << 8) | b
    }
    // A three-stop palette around a colour (derived materials).
    static func pal(_ c: V3, lo: Float = 0.72, hi: Float = 1.2) -> [(Float, UInt32)] {
        [(0, hexOf(c * lo)), (0.5, hexOf(c)), (1, hexOf(c * hi))]
    }
    static func shade(_ img: inout Img, _ hh: [Float], _ k: Float) {
        let lt = light(hh, img.n, k * Float(img.n) / 128)
        for i in 0..<(img.n * img.n) { let c = img.px[i]; img.px[i] = V4(c.x * lt[i], c.y * lt[i], c.z * lt[i], c.w) }
    }

    // Stone: warped fbm with soft mottling, faint strata, patchy cells, granular speckle and a few soft veins (wandering
    // ridges of a warped fbm, colour only: carved cracks read as scratches). `streak` adds deepslate's vertical grain.
    static func stone(_ pal: [(Float, UInt32)], veins: Float = 1, strata: Float = 0.04, streak: Float = 0) -> Gen {
        { n, s in
            let fn = Float(n)
            let base = fbm(n, n / 2, 6, s)
            let wx = fbm(n, n / 4, 3, s &+ 9), wy = fbm(n, n / 4, 3, s &+ 7)
            let h = warp(base, n, wx, wy, fn * 0.18)
            let mottle = fbm(n, n / 8, 3, s &+ 11)
            let grain = vnoise(n, max(1, n / 64), s &+ 5)
            let fine2 = vnoise(n, max(1, n / 32), s &+ 51)
            let rf = warp(fbm(n, n / 4, 4, s &+ 20), n, wy, wx, fn * 0.1)
            let mask = fbm(n, n / 4, 2, s &+ 4)
            let cells = voronoi(n, 6, s &+ 50, jitter: 1)
            let row = vnoise(n, max(1, n / 32), s &+ 30)
            var stripes = [Float](repeating: 0, count: n * n)
            for y in 0..<n { for x in 0..<n { stripes[y * n + x] = row[x] } }
            let st = warp(stripes, n, wx, wy, fn * 0.08)
            var hh = [Float](repeating: 0, count: n * n)
            var img = Img(n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let yy: Float = Float(y) + (wx[i] - 0.5) * fn * 0.4
                let band: Float = sinf(yy / fn * 2 * .pi * 3) * strata
                let ridge: Float = 1 - abs(2 * rf[i] - 1)
                let r0: Float = cl((ridge - 0.9) / 0.1)
                let v: Float = r0 * r0 * cl((mask[i] - 0.55) * 5) * veins
                let edge: Float = cl((cells.f2[i] - cells.f1[i]) / (fn / 24))
                let patch: Float = (cells.id[i] - 0.5) * 0.1 * edge
                let t0: Float = h[i] * 0.7 + (mottle[i] - 0.5) * 0.3 + (grain[i] - 0.5) * 0.14
                let t1: Float = (fine2[i] - 0.5) * 0.16 + 0.14 + band - v * 0.1
                var t: Float = t0 + t1 + (st[i] - 0.5) * streak + patch
                if grain[i] > 0.97 { t += 0.07 }
                let h0: Float = h[i] * 0.5 + mottle[i] * 0.2 + st[i] * streak * 0.6
                hh[i] = h0 + fine2[i] * 0.15 + patch
                let c = ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
            } }
            shade(&img, hh, 1.4)
            return img
        }
    }

    // Soil: fbm earth in soft clods with dark specks and a few small irregular pebbles (not raised studs).
    static func soil(_ pal: [(Float, UInt32)], pebble: UInt32, pebbles: Int = 9, clods: Int = 7) -> Gen {
        { n, s in
            let h = fbm(n, n / 4, 5, s)
            let fine = vnoise(n, max(1, n / 64), s &+ 1)
            let cd = voronoi(n, clods, s &+ 7, jitter: 1)
            let v = voronoi(n, pebbles, s &+ 3, jitter: 1)
            var hh = [Float](repeating: 0, count: n * n)
            var img = Img(n)
            let pr: Float = Float(n) / 64
            let pc = col(pebble)
            for i in 0..<(n * n) {
                let rad: Float = pr * (1 + v.id[i] * 1.2)
                let isPebble = v.id[i] > 0.8 && v.f1[i] < rad * (0.6 + 0.7 * fine[i])
                var t: Float = h[i] + (fine[i] - 0.5) * 0.18 + (cd.id[i] - 0.5) * 0.1
                if fine[i] < 0.04 { t -= 0.18 }
                var c = ramp(t, pal)
                let clodEdge: Float = cl(1 - (cd.f2[i] - cd.f1[i]) / (Float(n) / 40))
                hh[i] = h[i] * 0.4 + fine[i] * 0.12 - clodEdge * 0.03
                if isPebble {
                    let k: Float = (0.82 + v.id[i] * 0.18) * (0.92 + fine[i] * 0.1)
                    c = pc * k
                    hh[i] += 0.12
                }
                img.px[i] = V4(c.x, c.y, c.z, 1)
            }
            shade(&img, hh, 1.0)
            return img
        }
    }

    // Per-column depth of a hanging fringe (grass blades, snow lips): a wavy edge with tapered spikes.
    static func fringe(_ n: Int, _ s: Int, depth: Float, spikes: Int, spikeH: Float, width: Float) -> [Float] {
        let fn = Float(n)
        let wav = vnoise(n, max(1, n / 8), s)
        var d = [Float](repeating: 0, count: n)
        for x in 0..<n { d[x] = depth * fn + (wav[x] - 0.5) * fn * 0.05 }
        var rng = SRng(UInt64(truncatingIfNeeded: s) &* 6151 &+ 11)
        for _ in 0..<spikes {
            let c = rng.int(n)
            let w: Float = width * fn * (0.5 + rng.float())
            let hgt: Float = spikeH * fn * (0.3 + rng.float() * 0.7)
            for x in 0..<n {
                let a = abs(x - c)
                let dx = Float(min(a, n - a))
                let f: Float = max(0, 1 - dx / max(w, 0.5))
                d[x] = max(d[x], depth * fn + hgt * f * f.squareRoot())
            }
        }
        return d
    }

    static let dirtGen: Gen = soil(dirtPal, pebble: 0x8A7662)

    // Grass side: dirt with a hanging fringe of grey (biome-tinted, alpha 0.9 = overlay) blades and a soft shadow.
    static func grassSide(_ n: Int, _ s: Int) -> Img {
        var img = dirtGen(n, s)
        let top = grassTop(n, s &+ 3)
        let d = fringe(n, s &+ 5, depth: 0.14, spikes: n / 2, spikeH: 0.18, width: 0.012)
        let fn = Float(n)
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let fy = Float(y)
            if fy < d[x] {
                let g: Float = top.px[i].x * (1 - 0.25 * min(1, fy / max(d[x], 1)))
                img.px[i] = V4(g, g, g, 0.9)
            } else {
                let k: Float = 1 - 0.35 * cl(1 - (fy - d[x]) / (fn * 0.04))
                let c = img.px[i]
                img.px[i] = V4(c.x * k, c.y * k, c.z * k, 1)
            }
        } }
        return img
    }

    // Snow: soft blue-shaded drifts with sparkles.
    static func snow(_ n: Int, _ s: Int) -> Img {
        let sh = fbm(n, n / 2, 5, s)
        let fine = vnoise(n, max(1, n / 64), s &+ 1)
        let sp = vnoise(n, 1, s &+ 2)
        let a = col(0xC9D6EA), b = col(0xF6F9FF)
        var img = Img(n)
        var hh = [Float](repeating: 0, count: n * n)
        for i in 0..<(n * n) {
            let t: Float = cl((sh[i] - 0.3) * 1.4)
            let c: V3 = a * (1 - t) + b * t
            hh[i] = sh[i] * 0.6 + fine[i] * 0.08
            img.px[i] = V4(c.x, c.y, c.z, 1)
        }
        shade(&img, hh, 0.9)
        for i in 0..<(n * n) where sp[i] > 0.995 { img.px[i] = V4(1, 1, 1, 1) }
        return img
    }

    static func grassSnow(_ n: Int, _ s: Int) -> Img {
        var img = dirtGen(n, s)
        let sn = snow(n, s &+ 1)
        let d = fringe(n, s &+ 5, depth: 0.2, spikes: n / 10, spikeH: 0.12, width: 0.05)
        let fn = Float(n)
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let fy = Float(y)
            if fy < d[x] {
                let k: Float = 1 - 0.18 * cl(1 - (d[x] - fy) / (fn * 0.03))
                let c = sn.px[i]
                img.px[i] = V4(c.x * k, c.y * k, c.z * k, 1)
            } else {
                let k: Float = 1 - 0.35 * cl(1 - (fy - d[x]) / (fn * 0.04))
                let c = img.px[i]
                img.px[i] = V4(c.x * k, c.y * k, c.z * k, 1)
            }
        } }
        return img
    }

    // Masonry: blocks in courses (rows x perRow, odd rows shifted by `offset` of the width) with per-block tone, a
    // rounded bevel, eroded corners and grainy mortar. clay: mottled fired brick with sandy specks; else stone.
    static func masonry(rows: Int, perRow: Int, offset: Float, mortarW: Float, _ pal: [(Float, UInt32)], mortar: UInt32,
                        clay: Bool = false, chips: Float = 1, bevel: Float = 0.03, tone: Float = 0.18) -> Gen {
        { n, s in
            let fn = Float(n)
            let wob = fbm(n, max(1, n / 16), 3, s &+ 40)
            let ero = fbm(n, max(1, n / 8), 3, s &+ 41)
            let inner = clay ? fbm(n, n / 8, 4, s &+ 2) : fbm(n, n / 4, 5, s &+ 2)
            let fine = clay ? vnoise(n, max(1, n / 128), s &+ 3) : vnoise(n, max(1, n / 64), s &+ 3)
            let mf = vnoise(n, max(1, n / 64), s &+ 9)
            let rh: Float = fn / Float(rows), bw: Float = fn / Float(perRow)
            let mc = col(mortar)
            var hh = [Float](repeating: 0, count: n * n)
            var img = Img(n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let row = Int(Float(y) / rh)
                let xo: Float = (Float(x) + Float(row % 2) * offset * fn).truncatingRemainder(dividingBy: fn)
                let c0 = Int(xo / bw)
                let lx: Float = xo - Float(c0) * bw, ly: Float = Float(y) - Float(row) * rh
                let mw: Float = mortarW * fn * (0.9 + (wob[i] - 0.5) * 0.4)
                let ex: Float = min(lx, bw - 1 - lx), ey: Float = min(ly, rh - 1 - ly)
                var de: Float = min(ex, ey) - mw / 2
                let er: Float = (ero[i] - 0.5) * fn * 0.018 * chips
                de += er * cl(1 - de / (fn * 0.05))
                if de < 0 {
                    let k: Float = 0.85 + mf[i] * 0.3
                    img.px[i] = V4(mc.x * k, mc.y * k, mc.z * k, 1)
                    hh[i] = -0.3
                    continue
                }
                let bid = h2(c0 &+ row &* 31, row, s)
                var t: Float = 0.5 + (bid - 0.5) * tone + (fine[i] - 0.5) * (clay ? 0.15 : 0.12)
                t += (inner[i] - 0.5) * (clay ? 0.35 : 0.45)
                if clay && fine[i] > 0.93 { t += 0.15 }
                hh[i] = cl(de / (bevel * fn)) * 0.5 + inner[i] * 0.1
                let c = ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
            } }
            shade(&img, hh, 0.8)
            return img
        }
    }

    // Moss creeping over a base material: clumps where a low-frequency mask is high, fuzzy edges, darker near the
    // clump border.
    static func mossy(_ base: @escaping Gen, amount: Float = 0.5) -> Gen {
        { n, s in
            var img = base(n, s)
            let m = fbm(n, n / 4, 4, s &+ 60)
            let fine = vnoise(n, max(1, n / 64), s &+ 61)
            let pal: [(Float, UInt32)] = [(0, 0x3A4A22), (0.5, 0x5A7032), (1, 0x7C9446)]
            let th: Float = 1 - amount
            for i in 0..<(n * n) {
                let k: Float = m[i] + (fine[i] - 0.5) * 0.12
                if k < th { continue }
                let e: Float = cl((k - th) / 0.08)
                let c = ramp(0.4 + (fine[i] - 0.5) * 0.6 + e * 0.2, pal)
                let p = img.px[i]
                img.px[i] = V4(p.x + (c.x - p.x) * e, p.y + (c.y - p.y) * e, p.z + (c.z - p.z) * e, 1)
            }
            return img
        }
    }

    // Polished face: the base material calmed toward its mean (contrast * `calm`) with a fine sheen, inside a
    // bevelled rim (lit top/left, shaded bottom/right) about a sixteenth of the face wide.
    static func polished(_ base: @escaping Gen, calm: Float = 0.62, rim: Float = 1 / 16) -> Gen {
        { n, s in
            var img = base(n, s)
            var mean = V3(0, 0, 0)
            for p in img.px { mean += V3(p.x, p.y, p.z) }
            mean /= Float(n * n)
            let sheen = fbm(n, n / 4, 3, s &+ 80)
            let w: Float = max(1, Float(n) * rim)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let p = img.px[i]
                let c0 = V3(p.x, p.y, p.z)
                var c: V3 = mean + (c0 - mean) * calm
                c *= 0.96 + sheen[i] * 0.08
                let fx = Float(x), fy = Float(y), fe = Float(n - 1)
                if fx < w || fy < w { c *= 1.12 }
                else if fe - fx < w || fe - fy < w { c *= 0.8 }
                else if fx < w + 1 || fy < w + 1 { c *= 0.92 }
                img.px[i] = V4(min(1, c.x), min(1, c.y), min(1, c.z), p.w)
            } }
            return img
        }
    }

    // Lava: darker cooling plates (warped Voronoi cells) split by bright molten seams, with hot swirls inside.
    static func lava(_ n: Int, _ s: Int) -> Img {
        lavaLike([(0, 0x8A2A0C), (0.35, 0xC4501A), (0.6, 0xEC8A22), (0.82, 0xFFC44A), (1, 0xFFF0A8)], cells: 5)(n, s)
    }
    static func lavaLike(_ pal: [(Float, UInt32)], cells nc: Int, seamW: Float = 14) -> Gen { { n, s in
        let fn = Float(n)
        let wx = fbm(n, n / 4, 3, s &+ 1), wy = fbm(n, n / 4, 3, s &+ 2)
        let cells = voronoi(n, nc, s &+ 3, jitter: 1)
        let swirl = warp(fbm(n, n / 4, 5, s &+ 4), n, wx, wy, fn * 0.25)
        var gap = [Float](repeating: 0, count: n * n)
        for i in 0..<(n * n) { gap[i] = cells.f2[i] - cells.f1[i] }
        let edgeW = warp(gap, n, wx, wy, fn * 0.06)
        var img = Img(n)
        for i in 0..<(n * n) {
            let seam: Float = 1 - cl(edgeW[i] / (fn / seamW))
            let plate: Float = (cells.id[i] - 0.5) * 0.12
            let t: Float = 0.3 + (swirl[i] - 0.5) * 0.5 + plate + seam * seam * 0.65
            let c = ramp(t, pal)
            img.px[i] = V4(c.x, c.y, c.z, 1)
        }
        return img
    } }

    // Bookshelf: oak plank bands top, middle and bottom, two rows of book spines between them (varied widths, heights
    // and leather colours, a few leaning), dark gaps behind, a lit bevel along each spine.
    static func bookshelf(_ n: Int, _ s: Int) -> Img {
        var img = planks(oakPlank)(n, s)
        let fn = Float(n)
        let band: Float = fn / 8
        let colours: [UInt32] = [0x7A2620, 0x2E4A7A, 0x3E6A34, 0x6A4A2A, 0x5A2A5A, 0x8A6A24, 0x2A2A2E, 0x9A3A2A, 0x3A5A6A]
        let grain = fbm(n, max(1, n / 16), 3, s &+ 90)
        var rng = SRng(UInt64(truncatingIfNeeded: s) &* 7919 &+ 3)
        for row in 0..<2 {
            let rowH: Float = fn / 2 - band / 2
            let y0f: Float = band + Float(row) * rowH
            let y0 = Int(y0f), y1 = Int(y0f + rowH - band)
            for y in y0..<y1 { for x in 0..<n { img[x, y] = V4(0.07, 0.05, 0.04, 1) } }
            var x = 0
            while x < n {
                let w = max(2, Int(fn / 22 + rng.float() * fn / 18))
                let gap = rng.float() < 0.15 ? max(1, n / 48) : 0
                let top = y0 + Int(rng.float() * Float(y1 - y0) * 0.22)
                let c = col(colours[rng.int(colours.count)]) * (0.85 + rng.float() * 0.3)
                for xx in x..<min(n, x + w) {
                    let u: Float = Float(xx - x) / Float(w)
                    let shadeK: Float = 0.75 + 0.35 * sinf(u * .pi)                      // round spine
                    for y in top..<y1 {
                        let k: Float = shadeK * (0.92 + grain[y * n + xx] * 0.16)
                        let bandMark = (y - top) == (y1 - top) / 4 || (y - top) == (y1 - top) * 3 / 4
                        let m: Float = bandMark ? 1.25 : 1
                        let km: Float = k * m
                        let cc: V3 = simd_min(c * km, V3(repeating: 1))
                        img[xx, y] = V4(cc.x, cc.y, cc.z, 1)
                    }
                }
                x += w + gap
            }
        }
        return img
    }

    // Metal sheet: fine horizontal brushing, sparse pits, `tiles` x `tiles` plates split by thin seams with a lit
    // top-left bevel, and verdigris patches (`patina` 0...1 of the face) for weathering copper.
    static func metal(_ base: UInt32, patina: Float = 0, tiles: Int = 1, shine: Float = 0.12) -> Gen {
        { n, s in
            let fn = Float(n)
            let brush = vnoise(n, max(1, n / 64), s &+ 1)
            let blot = fbm(n, n / 4, 4, s &+ 2)
            let fine = vnoise(n, max(1, n / 128), s &+ 3)
            let c0 = col(base)
            let green = col(0x4FA48A)
            let tw: Float = fn / Float(tiles)
            var img = Img(n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                // Brushing: the noise stretched 8x along x.
                let b: Float = brush[y * n + (x / 8)]
                var k: Float = 0.9 + (b - 0.5) * shine + (blot[i] - 0.5) * 0.08
                if fine[i] > 0.97 { k *= 0.82 }
                let lx: Float = Float(x).truncatingRemainder(dividingBy: tw), ly: Float = Float(y).truncatingRemainder(dividingBy: tw)
                let seam: Float = max(1, fn / 64)
                if tiles > 1 && (lx < seam || ly < seam) { k *= 0.55 }
                else if tiles > 1 && (lx < seam * 2 || ly < seam * 2) { k *= 1.15 }
                else if lx > tw - seam * 2 || ly > tw - seam * 2 { k *= 0.85 }
                var c: V3 = c0 * k
                if patina > 0 {
                    let m: Float = blot[i] + (fine[i] - 0.5) * 0.15
                    let th: Float = 1 - patina
                    let e: Float = cl((m - th) / 0.07)
                    let gk: Float = 0.85 + fine[i] * 0.3
                    let target: V3 = green * gk
                    c += (target - c) * e
                }
                img.px[i] = V4(min(1, c.x), min(1, c.y), min(1, c.z), 1)
            } }
            return img
        }
    }

    // Glass (cutout): a thin pale frame with a lit inner edge, two soft diagonal glints in the upper left and a
    // corner sparkle; everything else fully clear.
    static func glass(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        var img = Img(n, V4(0.8, 0.9, 0.95, 0))
        let w = max(1, n / 16)
        let fine = vnoise(n, max(1, n / 32), s &+ 1)
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let edge = min(min(x, y), min(n - 1 - x, n - 1 - y))
            if edge < w {
                let k: Float = 0.82 + fine[i] * 0.16
                img.px[i] = edge == 0 ? V4(0.62 * k, 0.74 * k, 0.8 * k, 1) : V4(0.78 * k, 0.88 * k, 0.94 * k, 1)
                continue
            }
            let fx = Float(x), fy = Float(y)
            let d1: Float = abs(fx - fy)                         // the main glint along the diagonal
            let d2: Float = abs(fx - fy - fn * 0.18)
            let inGlint1: Bool = d1 < fn * 0.035 && fx > fn * 0.16 && fx < fn * 0.5
            let inGlint2: Bool = d2 < fn * 0.02 && fx > fn * 0.36 && fx < fn * 0.56
            if inGlint1 || inGlint2 { img.px[i] = V4(0.93, 0.97, 1, 1) }
        } }
        let sx = Int(fn * 0.82), sy = Int(fn * 0.14), r = max(1, n / 64)
        for y in (sy - r)...(sy + r) { for x in (sx - r)...(sx + r) { img[x, y] = V4(1, 1, 1, 1) } }
        return img
    }

    // Hay bale side: vertical straw fibres (noise stretched 12x along y) in golden tones, two dark binding bands with a
    // lit upper edge. Top: chopped straw ends as short random strokes.
    static func haySide(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        let fib = vnoise(n, max(1, n / 64), s &+ 1)
        let blot = fbm(n, n / 4, 3, s &+ 2)
        let pal: [(Float, UInt32)] = [(0, 0x8A6A1C), (0.45, 0xB8962E), (0.8, 0xD8B848), (1, 0xEED870)]
        var img = Img(n)
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let f: Float = fib[(y / 12) * n + x]
            var t: Float = 0.25 + f * 0.6 + (blot[i] - 0.5) * 0.25
            let fy = Float(y)
            for b in [fn * 0.22, fn * 0.72] {
                let d: Float = fy - b
                if d >= 0 && d < fn * 0.07 { t = 0.08 + f * 0.12 + (d < 1.5 ? 0.15 : 0) }
            }
            let c = ramp(t, pal)
            img.px[i] = V4(c.x, c.y, c.z, 1)
        } }
        return img
    }
    static func hayTop(_ n: Int, _ s: Int) -> Img {
        let pal: [(Float, UInt32)] = [(0, 0x7A5C18), (0.5, 0xB09030), (1, 0xE4C860)]
        let base = fbm(n, n / 4, 4, s &+ 1)
        var img = Img(n)
        for i in 0..<(n * n) { let c = ramp(0.3 + base[i] * 0.4, pal); img.px[i] = V4(c.x, c.y, c.z, 1) }
        var rng = SRng(UInt64(truncatingIfNeeded: s) &* 31 &+ 7)
        for _ in 0..<(n * 3) {
            let x0 = rng.int(n), y0 = rng.int(n), len = 2 + rng.int(max(2, n / 16))
            let a: Float = rng.float() * .pi
            let k: Float = 0.6 + rng.float() * 0.5
            let c = ramp(k, pal)
            for j in 0..<len {
                let fx = Float(x0) + cosf(a) * Float(j), fy = Float(y0) + sinf(a) * Float(j)
                img[Int(fx), Int(fy)] = V4(c.x, c.y, c.z, 1)
            }
        }
        return img
    }

    // Leaf litter (cutout overlay on the ground): scattered small fallen leaves, pointed ellipses in muted browns and
    // ochres with a darker midrib, overlapping; clear between them (the 16 px version was saturated orange noise).
    // Grass and fern sprites (cutout, greyscale for the biome tint): tapered blades rising from the ground, each
    // curving with its own lean, darker at the base, lit from the left. Lengths are in tiles (1 = one block); a tall
    // plant's top half draws the same blades (fixed salt) from height 1 up, so they continue across the seam. Ferns:
    // fronds arching out from the centre with alternating leaflets.
    static func blades(salt: Int, count: Int, len lmin: Float, _ lmax: Float, from y0: Float = 0, fern: Bool = false,
                       lean leanAmt: Float = 0.9, colour: UInt32? = nil) -> Gen {
        { n, _ in
            let fn = Float(n)
            var img = Img(n, V4(0, 0, 0, 0))
            func plot(_ x: Int, _ yy: Int, _ v: Float, _ a: Float) {
                guard x >= 0 && x < n && yy >= 0 && yy < n, a > 0 else { return }
                let i = yy * n + x
                let o = img.px[i]
                if a >= o.w || v > o.x { img.px[i] = V4(v, v, v, max(a, o.w)) }
            }
            for b in 0..<count {
                func r(_ k: Int) -> Float { h2(b, k, salt) }
                let bx: Float = fern ? fn / 2 + (r(0) - 0.5) * fn * 0.3 : (Float(b) + r(0)) / Float(count) * fn
                let len: Float = (lmin + (lmax - lmin) * r(1)) * fn
                let lean: Float = (r(2) - 0.5) * (fern ? 3.6 : leanAmt)
                let w0: Float = fern ? fn / 64 : fn / 26 * (0.7 + 0.6 * r(3))
                let tone: Float = (r(4) - 0.5) * 0.16
                for yy in 0..<n {
                    let h: Float = y0 * fn + Float(n - 1 - yy) + 0.5
                    let t: Float = h / len
                    if t < 0 || t > 1 { continue }
                    let cx: Float = bx + lean * t * t * len * 0.5
                    let w: Float = w0 * powf(1 - t, 0.7) + 0.6
                    for x in Int(cx - w / 2 - 1)...Int(cx + w / 2 + 2) {
                        let u: Float = (Float(x) + 0.5 - cx) / (w / 2)
                        let cov: Float = cl((1 - abs(u)) * w / 2 + 0.5)
                        let v: Float = (0.5 + 0.42 * t + tone) * (0.9 - 0.1 * u)
                        plot(x, yy, v, cov)
                    }
                }
                guard fern else { continue }
                // Leaflets every 1/24 of the tile, alternating sides, shorter toward the tip.
                let step: Float = fn / 24
                var hh: Float = step
                var k = 0
                while hh < len * 0.95 {
                    let t: Float = hh / len
                    let cx: Float = bx + lean * t * t * len * 0.5
                    let side: Float = k % 2 == 0 ? 1 : -1
                    let ll: Float = powf(1 - t, 0.6) * fn / 5.5 * (0.7 + 0.3 * r(10 + k))
                    let steps = Int(ll) + 2
                    for j in 0...steps {
                        let sj: Float = Float(j) / Float(steps)
                        let px: Float = cx + side * sj * ll
                        let ph: Float = hh + sj * ll * 0.45
                        let yy = Int(fn - 1 - (ph - y0 * fn))
                        let ww: Float = max(1, (1 - sj) * fn / 48 + 0.8)
                        let v: Float = 0.55 + 0.4 * t + 0.05 * sj + tone
                        for x in Int(px - ww / 2)...Int(px + ww / 2) { for dy in 0...Int(ww / 2) { plot(x, yy + dy, v, 1) } }
                    }
                    hh += step; k += 1
                }
            }
            if let c = colour {
                // Untinted plants (seagrass): the grey ramp coloured around this colour.
                let k: V3 = col(c) / 0.7
                for i in 0..<(n * n) { let p = img.px[i]; img.px[i] = V4(p.x * k.x, p.y * k.y, p.z * k.z, p.w) }
            }
            return img
        }
    }

    // Kelp (cutout, tiles vertically: kelp stacks): a gently waving stalk with three broad leaves per block on
    // alternating sides, each lit along its midrib.
    static func kelpHD(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        var img = Img(n, V4(0, 0, 0, 0))
        let dark = col(0x3A6418), light = col(0x6E9E30)
        func cx(_ y: Float) -> Float { fn / 2 + sinf(y / fn * 2 * .pi) * fn / 24 }
        for i in 0..<3 {
            let side: Float = i % 2 == 0 ? 1 : -1
            let by: Float = (Float(i) + 0.5) * fn / 3
            let len: Float = fn * 0.34, wid: Float = fn * 0.09
            let ang: Float = -.pi / 2 + side * 0.9
            let ox: Float = cx(by) + cosf(ang) * len * 0.5, oy: Float = by + sinf(ang) * len * 0.5
            let ca = cosf(ang), sa = sinf(ang)
            for y in Int(oy - len)...Int(oy + len) { for x in Int(ox - len)...Int(ox + len) {
                let dx: Float = Float(x) + 0.5 - ox, dy: Float = Float(y) + 0.5 - oy
                let u: Float = (dx * ca + dy * sa) / (len * 0.5), v: Float = (-dx * sa + dy * ca) / wid
                let edge: Float = 1 - u * u
                guard edge > 0, abs(v) < edge.squareRoot() else { continue }
                let k: Float = 0.45 + 0.4 * (1 - abs(v)) + 0.1 * u
                let c: V3 = dark + (light - dark) * k
                img[x, y] = V4(c.x, c.y, c.z, 1)
            } }
        }
        let w: Float = fn / 22
        for y in 0..<n {
            let c0: Float = cx(Float(y))
            for x in Int(c0 - w)...Int(c0 + w) {
                let u: Float = (Float(x) + 0.5 - c0) / w
                guard abs(u) <= 1 else { continue }
                let k: Float = 0.55 - 0.35 * u
                let c: V3 = dark + (light - dark) * k
                img[x, y] = V4(c.x, c.y, c.z, 1)
            }
        }
        return img
    }

    // Sugar cane (cutout, greyscale for the tint, tiles vertically): three round stalks with darker joints and a
    // pale band above each, lit from the left.
    static func caneHD(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        var img = Img(n, V4(0, 0, 0, 0))
        for (i, xc) in [Float(0.24), 0.58, 0.84].enumerated() {
            let w: Float = fn / 15 * (i == 1 ? 1.15 : 0.95)
            let off: Float = h2(i, 1, 77) * fn
            for y in 0..<n {
                let seg: Float = (Float(y) + off).truncatingRemainder(dividingBy: fn / 2) / (fn / 2)
                var k: Float = 0.82
                if seg < 0.05 { k = 0.58 } else if seg < 0.11 { k = 0.95 }
                for x in Int(xc * fn - w)...Int(xc * fn + w) {
                    let u: Float = (Float(x) + 0.5 - xc * fn) / w
                    guard abs(u) <= 1 else { continue }
                    let side: Float = 0.92 - 0.18 * u
                    let grain: Float = 0.97 + 0.06 * h2(x, y / 6, 78)
                    let v: Float = k * side * grain
                    img[x, y] = V4(v, v, v, 1)
                }
            }
        }
        return img
    }

    // Flower sprites (cutout): a slightly swaying stem, two lance leaves at the base and a head by kind: ring (petals
    // radiating around a disc: poppy, dandelion, daisy, cornflower...), cup (three upright petals: tulips), ball (a
    // sphere of florets: allium), bells (small bells hanging from an arched stalk: lily of the valley). `top` and
    // `size` are in 16 px units like the small painters (head centre height from the top, head radius).
    enum FlowerKind { case ring, cup, ball, bells }
    static func flowerHD(_ petal: UInt32, _ centre: UInt32, _ kind: FlowerKind, top: Float, size: Float, salt: Int) -> Gen {
        { n, _ in
            let fn = Float(n)
            var img = Img(n, V4(0, 0, 0, 0))
            func plot(_ x: Int, _ y: Int, _ c: V3) {
                guard x >= 0 && x < n && y >= 0 && y < n else { return }
                img.px[y * n + x] = V4(c.x, c.y, c.z, 1)
            }
            func ellipse(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, _ ang: Float, _ colour: (Float, Float, Float) -> V3) {
                let ca = cosf(ang), sa = sinf(ang)
                let r = Int(max(rx, ry)) + 2
                for y in (Int(cy) - r)...(Int(cy) + r) { for x in (Int(cx) - r)...(Int(cx) + r) {
                    let dx: Float = Float(x) + 0.5 - cx, dy: Float = Float(y) + 0.5 - cy
                    let u: Float = (dx * ca + dy * sa) / rx, v: Float = (-dx * sa + dy * ca) / ry
                    let d: Float = u * u + v * v
                    if d <= 1 { plot(x, y, colour(u, v, d)) }
                } }
            }
            let hx: Float = fn / 2, hy: Float = top / 16 * fn, rr: Float = size / 16 * fn
            let g0 = col(0x2E5E1E), g1 = col(0x5A9A3A)
            let sway: Float = Float(salt % 7)
            // Stem.
            for y in Int(hy)..<n {
                let t: Float = (Float(y) - hy) / (fn - hy)
                let x: Float = hx + sinf(t * 2.2 + sway) * fn / 40
                let w: Float = fn / 48 + 0.8
                for xx in Int(x - w)...Int(x + w) {
                    let u: Float = (Float(xx) + 0.5 - x) / w
                    let k: Float = 0.6 - 0.4 * u
                    plot(xx, y, g0 + (g1 - g0) * k)
                }
            }
            // Leaves.
            for side: Float in [-1, 1] {
                let len: Float = fn * 0.32
                let ang: Float = -.pi / 2 + side * 0.75
                let cx: Float = hx + cosf(ang) * len / 2, cy: Float = fn * 0.93 + sinf(ang) * len / 2
                ellipse(cx, cy, len / 2, fn / 26, ang) { (u: Float, v: Float, _: Float) -> V3 in
                    let k: Float = 0.5 - 0.4 * v
                    let mid: V3 = g0 + (g1 - g0) * k
                    let edge: Float = 0.85 + 0.15 * (1 - abs(u))
                    return mid * edge
                }
            }
            let pc = col(petal), cc = col(centre)
            switch kind {
            case .ring:
                let k = size > 2.5 ? 8 : 6
                for i in 0..<k {
                    let a: Float = Float(i) / Float(k) * 2 * .pi + sway
                    let px: Float = hx + cosf(a) * rr * 0.55, py: Float = hy + sinf(a) * rr * 0.55
                    ellipse(px, py, rr * 0.55, rr * 0.26, a) { (u: Float, _: Float, d: Float) -> V3 in
                        let along: Float = 0.78 + 0.15 * (u + 1)
                        let fall: Float = 1 - 0.12 * d
                        return pc * (along * fall)
                    }
                }
                ellipse(hx, hy, rr * 0.32, rr * 0.32, 0) { (u: Float, v: Float, d: Float) -> V3 in
                    let lit: Float = 1.05 - 0.15 * (u + v)
                    let dome: Float = 0.85 + 0.15 * (1 - d)
                    return cc * (lit * dome)
                }
            case .cup:
                for (dx, k) in [(Float(-0.45), Float(0.85)), (0.45, 0.85), (0, 1)] {
                    ellipse(hx + dx * rr, hy, rr * 0.5, rr * 0.95, dx * 0.35) { (_: Float, v: Float, d: Float) -> V3 in
                        let up: Float = 0.8 - 0.25 * v
                        let fall: Float = 1 - 0.1 * d
                        return pc * (k * up * fall)
                    }
                }
            case .ball:
                for i in 0..<60 {
                    let a: Float = h2(i, 1, salt) * 2 * .pi
                    let r: Float = rr * h2(i, 2, salt).squareRoot()
                    let x: Float = hx + cosf(a) * r, y: Float = hy + sinf(a) * r
                    let sh: Float = 0.75 + 0.35 * (1 - (y - hy + rr) / (2 * rr))
                    let fr: Float = fn / 40 + 1
                    ellipse(x, y, fr, fr, 0) { (_: Float, _: Float, d: Float) -> V3 in
                        let dome: Float = 1.1 - 0.3 * d
                        return pc * (sh * dome)
                    }
                }
            case .bells:
                // An arched stalk from the stem top out to the right, bells hanging under it.
                for i in 0..<24 {
                    let t: Float = Float(i) / 23
                    let x: Float = hx + t * rr * 3
                    let y: Float = hy - sinf(t * .pi * 0.8) * rr * 0.9
                    let sr: Float = fn / 90 + 0.7
                    ellipse(x, y, sr, sr, 0) { (_: Float, _: Float, _: Float) -> V3 in g1 }
                }
                for i in 0..<4 {
                    let t: Float = 0.2 + Float(i) * 0.25
                    let x: Float = hx + t * rr * 3
                    let y: Float = hy - sinf(t * .pi * 0.8) * rr * 0.9 + rr * 0.55
                    ellipse(x, y, rr * 0.36, rr * 0.42, 0) { (u: Float, v: Float, _: Float) -> V3 in
                        let k: Float = 0.82 - 0.2 * v + 0.05 * u
                        return pc * k
                    }
                }
            }
            return img
        }
    }

    // Vines (cutout, greyscale for the tint, tiles both ways): four meandering stems with pointed leaves on
    // alternating sides, each leaf lit along one half.
    static func vineHD(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        var img = Img(n, V4(0, 0, 0, 0))
        for st in 0..<4 {
            let bx: Float = (Float(st) + h2(st, 1, 91)) / 4 * fn
            let ph: Float = h2(st, 2, 91) * 2 * .pi
            let amp: Float = fn / 18
            func cx(_ y: Float) -> Float { bx + sinf(y / fn * 2 * .pi + ph) * amp }
            for y in 0..<n {
                let c0 = cx(Float(y))
                for x in Int(c0 - 1.2)...Int(c0 + 1.2) { img[x, y] = V4(0.48, 0.48, 0.48, 1) }
            }
            for i in 0..<8 {
                let side: Float = (i + st) % 2 == 0 ? 1 : -1
                let ly: Float = (Float(i) + h2(st, 10 + i, 91) * 0.5) * fn / 8
                let len: Float = fn / 9 * (0.8 + 0.4 * h2(st, 20 + i, 91)), wid: Float = fn / 22
                let ang: Float = side > 0 ? -0.5 : .pi + 0.5
                let ox: Float = cx(ly) + cosf(ang) * len * 0.5, oy: Float = ly + sinf(ang) * len * 0.5
                let ca = cosf(ang), sa = sinf(ang)
                for y in Int(oy - len)...Int(oy + len) { for x in Int(ox - len)...Int(ox + len) {
                    let dx: Float = Float(x) + 0.5 - ox, dy: Float = Float(y) + 0.5 - oy
                    let u: Float = (dx * ca + dy * sa) / (len * 0.5), v: Float = (-dx * sa + dy * ca) / wid
                    let e: Float = 1 - u * u
                    guard e > 0, abs(v) < e else { continue }
                    let lit: Float = v * side < 0 ? 0.78 : 0.62
                    let mid: Float = 0.1 * (1 - abs(u))
                    let k: Float = lit + mid + 0.08 * h2(st, 30 + i, 91)
                    img[x, y] = V4(k, k, k, 1)
                } }
            }
        }
        return img
    }

    // Lily pad (cutout, greyscale for the tint, seen from above): a round pad with a notch, veins from the centre and
    // a lighter rim.
    static func lilyPadHD(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        var img = Img(n, V4(0, 0, 0, 0))
        let rr: Float = fn * 0.44
        let fine = fbm(n, n / 8, 3, s)
        for y in 0..<n { for x in 0..<n {
            let dx: Float = Float(x) + 0.5 - fn / 2, dy: Float = Float(y) + 0.5 - fn / 2
            let d: Float = (dx * dx + dy * dy).squareRoot()
            let wob: Float = 1 + sinf(atan2f(dy, dx) * 5) * 0.02
            guard d < rr * wob else { continue }
            let a: Float = atan2f(dy, dx)
            if abs(a) < 0.16 && dx > 0 { continue }                                     // the notch
            let veinW: Float = 0.09 * (1 + d / rr)
            let onVein = abs(sinf(a * 7)) < veinW && d > fn * 0.04
            let vein: Float = onVein ? 0.82 : 1
            let rim: Float = d > rr * wob - fn / 40 ? 1.12 : 1
            let mott: Float = (fine[y * n + x] - 0.5) * 0.12
            let base: Float = 0.55 + 0.22 * (d / rr) + mott
            let k: Float = base * vein * rim
            img.px[y * n + x] = V4(k, k, k, 1)
        } }
        return img
    }

    // Ice (translucent): clear blue with frosty patches, fracture lines along cell edges (paler, more opaque) and a
    // few trapped bubbles.
    static func iceHD(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        var img = Img(n)
        let frost = fbm(n, n / 4, 4, s)
        let cells = voronoi(n, 5, s &+ 3)
        let fine = vnoise(n, max(1, n / 64), s &+ 5)
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let edge: Float = cl(1 - (cells.f2[i] - cells.f1[i]) / (fn / 90))
            let fr: Float = cl((frost[i] - 0.45) * 2.5)
            let tone: Float = 0.94 + fine[i] * 0.08
            var c: V3 = V3(0.62, 0.78, 1.0) * tone
            let pale: Float = max(fr * 0.5, edge * 0.8)
            c += (V3(0.9, 0.95, 1.0) - c) * pale
            let bubble = h2(x / max(1, n / 32), y / max(1, n / 32), s &+ 9) > 0.985
            let bub: Float = bubble ? 0.2 : 0
            let a: Float = 0.58 + fr * 0.14 + edge * 0.3 + bub
            img.px[i] = V4(min(1, c.x), min(1, c.y), min(1, c.z), min(1, a))
        } }
        return img
    }

    // Gourds and cactus.
    // Ribbed side (pumpkin): `ribs` rounded lobes across the face, dark grooves between them, faint vertical streaks.
    static func ribbedSide(_ pal: [(Float, UInt32)], ribs: Int) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = Img(n)
            let streak = vnoise(n, max(1, n / 32), s)
            let blot = fbm(n, n / 4, 4, s &+ 1)
            var hh = [Float](repeating: 0, count: n * n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let w: Float = Float(x) + sinf(Float(y) / fn * 2 * .pi) * fn / 64
                let u: Float = (w / fn * Float(ribs)).truncatingRemainder(dividingBy: 1)
                let prof: Float = sinf(.pi * (u < 0 ? u + 1 : u))
                let st: Float = streak[(y / 8) * n + x]
                let t: Float = 0.2 + 0.62 * powf(prof, 0.6) + (st - 0.5) * 0.12 + (blot[i] - 0.5) * 0.12
                let c = ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
                hh[i] = prof * 0.6
            } }
            shade(&img, hh, 0.7)
            return img
        }
    }
    // Radial top (pumpkin, melon): lobes or stripes converging on a stem scar in the middle.
    static func radialTop(_ pal: [(Float, UInt32)], lobes: Int, stem: UInt32, stripes: Bool = false) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = Img(n)
            let blot = fbm(n, n / 4, 4, s)
            let wob = fbm(n, n / 8, 3, s &+ 4)
            var hh = [Float](repeating: 0, count: n * n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let dx: Float = Float(x) + 0.5 - fn / 2, dy: Float = Float(y) + 0.5 - fn / 2
                let d: Float = (dx * dx + dy * dy).squareRoot()
                let a: Float = atan2f(dy, dx) + (wob[i] - 0.5) * 0.5
                let f: Float = (a / (2 * .pi) * Float(lobes) + 8).truncatingRemainder(dividingBy: 1)
                let prof: Float = stripes ? (f < 0.35 ? 0 : 1) : sinf(.pi * f)
                var t: Float = 0.25 + 0.55 * prof + (blot[i] - 0.5) * 0.15
                t *= 0.8 + 0.2 * min(1, d / (fn * 0.25))
                var c = ramp(t, pal)
                if d < fn / 11 {
                    let k: Float = 0.8 + 0.3 * (1 - d / (fn / 11)) + (blot[i] - 0.5) * 0.2
                    c = col(stem) * k
                }
                img.px[i] = V4(c.x, c.y, c.z, 1)
                hh[i] = stripes ? 0 : prof * 0.5 * min(1, d / (fn * 0.2)) + (d < fn / 11 ? 0.6 : 0)
            } }
            shade(&img, hh, 0.7)
            return img
        }
    }
    // Melon side: irregular dark green stripes over a mottled pale rind.
    static func melonSide(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        var img = Img(n)
        let blot = fbm(n, n / 4, 5, s)
        let wob = fbm(n, n / 4, 3, s &+ 2)
        let pale = [(Float(0), UInt32(0x7EA82A)), (0.5, 0x9AC23A), (1, 0xB4D452)]
        let dark = [(Float(0), UInt32(0x3E6A12)), (0.5, 0x52801A), (1, 0x689622)]
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let w: Float = Float(x) + (wob[i] - 0.5) * fn / 8
            let u: Float = (w / fn * 4 + 8).truncatingRemainder(dividingBy: 1)
            let inStripe = u < 0.38 + (blot[i] - 0.5) * 0.25
            let t: Float = 0.3 + blot[i] * 0.5
            let c = ramp(t, inStripe ? dark : pale)
            img.px[i] = V4(c.x, c.y, c.z, 1)
        } }
        return img
    }
    // Cactus: the model is inset a sixteenth on every side, so those texels stay clear as in the small painter.
    static func cactusSide(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        var img = Img(n, V4(0, 0, 0, 0))
        let blot = fbm(n, n / 4, 4, s)
        let edge = max(1, n / 16)
        let pal = [(Float(0), UInt32(0x1E5A22)), (0.5, 0x2F7F32), (1, 0x4A9E44)]
        var hh = [Float](repeating: 0, count: n * n)
        let inner: Float = fn - 2 * Float(edge)
        for y in 0..<n { for x in edge..<(n - edge) {
            let i = y * n + x
            let u: Float = ((Float(x - edge) + 0.5) / inner * 4).truncatingRemainder(dividingBy: 1)
            let prof: Float = sinf(.pi * u)
            let t: Float = 0.15 + 0.7 * prof + (blot[i] - 0.5) * 0.15
            let c = ramp(t, pal)
            img.px[i] = V4(c.x, c.y, c.z, 1)
            hh[i] = prof * 0.6
        } }
        shade(&img, hh, 0.6)
        // Spine tufts on the rib crests.
        let sp = max(1, n / 64)
        for rib in 0..<4 {
            let cx: Float = Float(edge) + (Float(rib) + 0.5) * inner / 4
            for k in 0..<6 {
                let cy: Float = (Float(k) + 0.3 + h2(rib, k, s) * 0.4) / 6 * fn
                for dy in -sp...sp { for dx in -sp...sp {
                    let x = Int(cx) + dx, y = Int(cy) + dy
                    guard x >= edge && x < n - edge else { continue }
                    let k2: Float = 0.85 + 0.15 * h2(x, y, s &+ 1)
                    img[x, y] = V4(0.9 * k2, 0.9 * k2, 0.7 * k2, 1)
                } }
            }
        }
        return img
    }
    static func cactusEnd(_ top: Bool) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = Img(n, V4(0, 0, 0, 0))
            let blot = fbm(n, n / 4, 4, s)
            let e = max(1, n / 16)
            for y in e..<(n - e) { for x in e..<(n - e) {
                let i = y * n + x
                let border = x < 2 * e || y < 2 * e || x >= n - 2 * e || y >= n - 2 * e
                let dx: Float = Float(x) + 0.5 - fn / 2, dy: Float = Float(y) + 0.5 - fn / 2
                let d: Float = (dx * dx + dy * dy).squareRoot() / (fn / 2)
                var c: V3
                if top {
                    let k: Float = (border ? 0.68 : 0.9 + 0.12 * (1 - d)) + (blot[i] - 0.5) * 0.12
                    c = col(0x55A043) * k
                } else {
                    c = col(0xC3C586) * (0.88 + blot[i] * 0.16)
                }
                img.px[i] = V4(c.x, c.y, c.z, 1)
            } }
            return img
        }
    }

    // Lumpy masses (wart blocks, glowstone, shroomlight, sculk): packed rounded lumps, each a Voronoi cell shaded as
    // a bulge, with its own tone.
    static func lumps(_ pal: [(Float, UInt32)], cells: Int = 10, gloss: Float = 0) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = Img(n)
            let v = voronoi(n, cells, s, jitter: 0.95)
            let fine = vnoise(n, max(1, n / 64), s &+ 2)
            let size: Float = fn / Float(cells)
            var hh = [Float](repeating: 0, count: n * n)
            for i in 0..<(n * n) {
                let bulge: Float = cl(1 - v.f1[i] / (size * 0.75))
                let seam: Float = cl((v.f2[i] - v.f1[i]) / (fn / 48))
                let t0: Float = 0.12 + 0.55 * bulge * seam + (v.id[i] - 0.5) * 0.25
                let t: Float = t0 + (fine[i] - 0.5) * 0.08 + gloss * (bulge > 0.75 ? 0.2 : 0)
                let c = ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
                hh[i] = bulge * seam
            }
            shade(&img, hh, 0.9)
            return img
        }
    }
    static let netherrackGen: Gen = stone([(0, 0x3E1414), (0.35, 0x642424), (0.7, 0x8A3838), (1, 0xAC5656)], veins: 0.9, strata: 0)
    static let crimsonNylium: Gen = soil([(0, 0x5A0E10), (0.5, 0x8A1A1C), (1, 0xB0302A)], pebble: 0xC04A3A, pebbles: 14, clods: 10)
    static let warpedNylium: Gen = soil([(0, 0x0E4A44), (0.5, 0x16706A), (1, 0x2A9A8A)], pebble: 0x40C0A8, pebbles: 14, clods: 10)

    // Huge mushroom blocks: a cap with soft round spots (red) or a mottled velvet (brown), a fibrous stem, and the
    // pale porous inside.
    static func mushroomCap(_ pal: [(Float, UInt32)], spots: Int) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = Img(n)
            let blot = fbm(n, n / 4, 5, s)
            let fine = vnoise(n, max(1, n / 64), s &+ 1)
            var cs: [(Float, Float, Float)] = []
            for k in 0..<spots { cs.append((h2(k, 1, s) * fn, h2(k, 2, s) * fn, fn * (0.07 + 0.06 * h2(k, 3, s)))) }
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let t: Float = 0.3 + blot[i] * 0.5 + (fine[i] - 0.5) * 0.08
                var c = ramp(t, pal)
                for (sx, sy, r) in cs {
                    var dx: Float = abs(Float(x) - sx), dy: Float = abs(Float(y) - sy)
                    dx = min(dx, fn - dx); dy = min(dy, fn - dy)
                    let d: Float = (dx * dx + dy * dy).squareRoot() + (blot[i] - 0.5) * r * 0.5
                    if d < r {
                        let k: Float = 0.86 + 0.14 * (1 - d / r) + (fine[i] - 0.5) * 0.06
                        c = V3(0.93, 0.9, 0.86) * k
                    }
                }
                img.px[i] = V4(c.x, c.y, c.z, 1)
            } }
            return img
        }
    }
    static func mushroomStem(_ n: Int, _ s: Int) -> Img {
        var img = Img(n)
        let fib = vnoise(n, max(1, n / 32), s)
        let blot = fbm(n, n / 4, 4, s &+ 1)
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let f: Float = fib[(y / 10) * n + x]
            let k: Float = 0.84 + (f - 0.5) * 0.16 + (blot[i] - 0.5) * 0.1
            let c = col(0xD8D0BC) * k
            img.px[i] = V4(c.x, c.y, c.z, 1)
        } }
        return img
    }
    static func mushroomInside(_ n: Int, _ s: Int) -> Img {
        var img = Img(n)
        let blot = fbm(n, n / 4, 4, s)
        let pores = vnoise(n, max(1, n / 48), s &+ 3)
        for i in 0..<(n * n) {
            var k: Float = 0.88 + (blot[i] - 0.5) * 0.14
            if pores[i] > 0.72 { k *= 0.86 }
            let c = col(0xD8B898) * k
            img.px[i] = V4(c.x, c.y, c.z, 1)
        }
        return img
    }

    // Storage blocks (diamond, emerald, lapis, redstone, coal): a bevelled frame around a field of flat cut facets,
    // each with its own tone and a lit top-left edge; `flecks` adds gold pyrite specks (lapis).
    static func gemBlock(_ pal: [(Float, UInt32)], cells: Int = 5, flecks: Bool = false) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = Img(n)
            let v = voronoi(n, cells, s, jitter: 0.85)
            let fine = vnoise(n, max(1, n / 64), s &+ 2)
            let bevel: Float = fn / 16
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let fx = Float(x), fy = Float(y)
                let edgeD: Float = min(min(fx, fy), min(fn - 1 - fx, fn - 1 - fy))
                var t: Float = 0.3 + v.id[i] * 0.45 + (fine[i] - 0.5) * 0.06
                let seam: Float = v.f2[i] - v.f1[i]
                if seam < fn / 96 { t -= 0.22 } else if seam < fn / 48 { t += 0.12 }
                if edgeD < bevel {
                    // Lit on the top / left bevel, shaded on the bottom / right one.
                    let dTL: Float = min(fx, fy), dBR: Float = min(fn - 1 - fx, fn - 1 - fy)
                    t = dTL <= dBR ? 0.92 : 0.18
                }
                var c = ramp(t, pal)
                if flecks && edgeD >= bevel && h2(x / max(1, n / 64), y / max(1, n / 64), s &+ 7) > 0.975 { c = col(0xE8C860) }
                img.px[i] = V4(c.x, c.y, c.z, 1)
            } }
            return img
        }
    }

    // Crying obsidian: obsidian with glowing violet tears running down from a few seeps (the tears are what the
    // emissive mask picks up).
    static func cryingObsidian(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        var img = stone([(0, 0x0E0A16), (0.5, 0x1C1428), (0.85, 0x2E2240), (1, 0x4A3A64)], veins: 0.8, strata: 0)(n, s)
        let glow = col(0x9A3AF0), core = col(0xE8A0FF)
        for k in 0..<9 {
            let x0: Float = h2(k, 1, s) * fn, y0: Float = h2(k, 2, s) * fn
            let len: Float = fn * (0.12 + 0.3 * h2(k, 3, s))
            let w: Float = fn / 48 + 1
            var y: Float = 0
            while y < len {
                let t: Float = y / len
                let x: Float = x0 + sinf(y / fn * 9 + Float(k)) * fn / 90
                let ww: Float = w * (t > 0.85 ? 1.6 : 1)                     // a drop at the end
                for dx in Int(-ww - 1)...Int(ww + 1) {
                    let u: Float = abs(Float(dx)) / ww
                    guard u <= 1 else { continue }
                    let c: V3 = core + (glow - core) * u
                    img[Int(x) + dx, Int(y0 + y)] = V4(c.x, c.y, c.z, 1)
                }
                y += 1
            }
        }
        return img
    }
    // Pillar side (violite pillar): vertical fluting between a lit and a shaded edge, capped top and bottom.
    static func pillarSide(_ pal: [(Float, UInt32)]) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = Img(n)
            let blot = fbm(n, n / 4, 4, s)
            var hh = [Float](repeating: 0, count: n * n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let u: Float = (Float(x) / fn * 4).truncatingRemainder(dividingBy: 1)
                let flute: Float = sinf(.pi * u)
                let cap: Bool = y < n / 16 || y >= n - n / 16
                let t: Float = cap ? 0.75 : 0.3 + 0.4 * flute + (blot[i] - 0.5) * 0.12
                let c = ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
                hh[i] = cap ? 0.6 : flute * 0.5
            } }
            shade(&img, hh, 0.7)
            return img
        }
    }
    // Pillar end: concentric rings around a square boss.
    static func pillarTop(_ pal: [(Float, UInt32)]) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = Img(n)
            let blot = fbm(n, n / 4, 4, s)
            var hh = [Float](repeating: 0, count: n * n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let d: Float = max(abs(Float(x) + 0.5 - fn / 2), abs(Float(y) + 0.5 - fn / 2)) / (fn / 2)
                let ring: Float = 0.5 + 0.5 * cosf(d * .pi * 4)
                let t: Float = 0.3 + 0.4 * ring + (blot[i] - 0.5) * 0.12
                let c = ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
                hh[i] = ring * 0.4
            } }
            shade(&img, hh, 0.7)
            return img
        }
    }

    // Wooden storage. Chests: planks inside a dark banded frame (rivets at the corners), a lid seam band on the sides,
    // a metal latch on the front. Barrels: vertical staves with two riveted iron hoops; the top a planked lid with a bung.
    static let chestPlank: [(Float, UInt32)] = [(0, 0x7A5222), (0.5, 0xA2702F), (1, 0xC08A44)]
    static func chestFace(_ kind: Int) -> Gen {          // 0 top, 1 side, 2 front
        { n, s in
            var img = planks(chestPlank)(n, s)
            let trim = col(0x4E3414)
            let fine = vnoise(n, max(1, n / 64), s &+ 4)
            let b = n / 8
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let rimX: Bool = x < b || x >= n - b
                let rimTop: Bool = kind == 0 ? (y < b || y >= n - b) : (y < n * 3 / 16 || y >= n - n / 16)
                let seam: Bool = kind != 0 && y >= n * 7 / 16 && y < n * 9 / 16
                let frame = rimX || rimTop || seam
                guard frame else { continue }
                var k: Float = 0.9 + (fine[i] - 0.5) * 0.2
                // Bevel: lit along the band's top / left pixels.
                let lx = x % b, ly = y % b
                if lx == 0 || ly == 0 { k *= 1.25 } else if lx == b - 1 || ly == b - 1 { k *= 0.7 }
                img.px[i] = V4(trim.x * k, trim.y * k, trim.z * k, 1)
            } }
            // Rivets in the frame corners.
            let rv = max(1, n / 48)
            for (cx, cy) in [(b / 2, b / 2), (n - b / 2, b / 2), (b / 2, n - b / 2), (n - b / 2, n - b / 2)] {
                for dy in -rv...rv { for dx in -rv...rv where dx * dx + dy * dy <= rv * rv {
                    let k: Float = dx + dy < 0 ? 0.85 : 0.6
                    img[cx + dx, cy + dy] = V4(k, k * 0.95, k * 0.85, 1)
                } }
            }
            if kind == 2 {
                // Latch: a small steel plate with a dark keyhole.
                let x0 = n * 7 / 16 - n / 32, x1 = n * 9 / 16 + n / 32, y0 = n * 6 / 16, y1 = n * 10 / 16
                for y in y0..<y1 { for x in x0..<x1 {
                    let edge = x == x0 || y == y0
                    let low = x == x1 - 1 || y == y1 - 1
                    var k: Float = 0.72 + 0.1 * fine[y * n + x]
                    if edge { k = 0.95 } else if low { k = 0.45 }
                    let hole = abs(x - n / 2) < max(1, n / 64) && y > y0 + (y1 - y0) / 3 && y < y1 - (y1 - y0) / 4
                    if hole { k = 0.12 }
                    img[x, y] = V4(k, k, k * 1.02, 1)
                } }
            }
            return img
        }
    }
    static func barrelSide(_ n: Int, _ s: Int) -> Img {
        let src = planks([(0, 0x5A4022), (0.5, 0x7A5A30), (1, 0x9A7444)])(n, s)
        var img = Img(n)
        for y in 0..<n { for x in 0..<n { img.px[y * n + x] = src.px[x * n + y] } }     // vertical staves
        let iron = col(0x3A3A3C)
        let fine = vnoise(n, max(1, n / 64), s &+ 5)
        for band in [n / 8, n * 13 / 16] {
            let h = max(2, n / 14)
            for y in band..<min(n, band + h) { for x in 0..<n {
                var k: Float = 0.9 + (fine[y * n + x] - 0.5) * 0.25
                if y == band { k *= 1.3 } else if y == band + h - 1 { k *= 0.6 }
                if x % (n / 4) == n / 8 && y > band && y < band + h - 1 { k *= 1.5 }    // rivet
                img.px[y * n + x] = V4(iron.x * k, iron.y * k, iron.z * k, 1)
            } }
        }
        return img
    }
    static func barrelTop(_ n: Int, _ s: Int) -> Img {
        var img = planks([(0, 0x6A4A26), (0.5, 0x8A6A3A), (1, 0xA6844E)])(n, s)
        let fn = Float(n)
        let rim = n / 12
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let edge = min(min(x, y), min(n - 1 - x, n - 1 - y))
            let dx: Float = Float(x) + 0.5 - fn / 2, dy: Float = Float(y) + 0.5 - fn / 2
            let bung = max(abs(dx), abs(dy)) < fn * 0.14
            if edge < rim {
                let k: Float = edge == 0 ? 0.55 : (edge == rim - 1 ? 0.8 : 0.68)
                img.px[i] = V4(0.24 * k / 0.68, 0.24 * k / 0.68, 0.25 * k / 0.68, 1)
            } else if bung {
                let k: Float = max(abs(dx), abs(dy)) > fn * 0.12 ? 0.6 : 0.85
                let c = col(0x4A3A20) * k
                img.px[i] = V4(c.x, c.y, c.z, 1)
            }
        } }
        return img
    }

    // Dead bush (cutout): dry twigs forking up and out from one root, thinning toward the tips.
    static func deadBushHD(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        var img = Img(n, V4(0, 0, 0, 0))
        let dark = col(0x5A3E1C), light = col(0x9A7442)
        var seq = 0
        func branch(_ x: Float, _ y: Float, _ ang: Float, _ len: Float, _ w: Float, _ depth: Int) {
            let steps = Int(len) + 1
            var px = x, py = y
            for i in 0..<steps {
                let t: Float = Float(i) / Float(steps)
                px = x + sinf(ang) * len * t
                py = y - cosf(ang) * len * t
                let ww: Float = max(0.6, w * (1 - t * 0.5))
                for dy in Int(-ww)...Int(ww) { for dx in Int(-ww)...Int(ww) {
                    let fx = Float(dx), fy = Float(dy)
                    guard fx * fx + fy * fy <= ww * ww + 0.3 else { continue }
                    let xx = Int(px) + dx, yy = Int(py) + dy
                    guard xx >= 0 && xx < n && yy >= 0 && yy < n else { continue }
                    let c: V3 = dark + (light - dark) * (dx < 0 ? 0.75 : 0.35)
                    img.px[yy * n + xx] = V4(c.x, c.y, c.z, 1)
                } }
            }
            guard depth > 0 else { return }
            for side: Float in [-1, 1] {
                seq += 1
                let spread: Float = 0.35 + 0.35 * h2(seq, 1, s)
                let k: Float = 0.55 + 0.25 * h2(seq, 2, s)
                branch(px, py, ang + side * spread, len * k, w * 0.65, depth - 1)
            }
        }
        branch(fn / 2, fn - 1, 0, fn * 0.3, fn / 40 + 0.8, 4)
        return img
    }

    // Crops (cutout, untinted). Wheat: thin stalks growing with the stage, turning gold near the end, the last stage
    // with grain heads (kernels and awns). Root crops: broad leafy tufts; ripe, the root's top shows at the soil.
    static func cropHD(stage: Int, max maxStage: Int, young: UInt32, ripe: UInt32, head: UInt32?, wheat: Bool, salt: Int) -> Gen {
        { n, _ in
            let fn = Float(n)
            var img = Img(n, V4(0, 0, 0, 0))
            let k: Float = Float(stage) / Float(maxStage)
            let cy = col(young), cr = col(ripe)
            let ripeK: Float = cl((k - 0.55) / 0.45)
            let base: V3 = cy + (cr - cy) * ripeK
            let count = wheat ? 9 : 6
            let height: Float = (0.19 + 0.75 * k) * fn
            func plot(_ x: Int, _ y: Int, _ c: V3) {
                guard x >= 0 && x < n && y >= 0 && y < n else { return }
                img.px[y * n + x] = V4(min(1, c.x), min(1, c.y), min(1, c.z), 1)
            }
            for i in 0..<count {
                let bx: Float = (Float(i) + 0.5 + (h2(i, 1, salt) - 0.5) * 0.6) / Float(count) * fn
                let h: Float = height * (0.8 + 0.2 * h2(i, 2, salt))
                let lean: Float = (h2(i, 3, salt) - 0.5) * (wheat ? 0.25 : 0.9)
                let w0: Float = wheat ? fn / 44 + 0.6 : fn / 16 * (0.7 + 0.5 * k)
                let headLen: Float = wheat && stage == maxStage ? h * 0.26 : 0
                for yy in 0..<n {
                    let up: Float = Float(n - 1 - yy) + 0.5
                    guard up < h else { continue }
                    let t: Float = up / h
                    let cx: Float = bx + lean * t * t * h * 0.5
                    let inHead = headLen > 0 && up > h - headLen
                    var w: Float = wheat ? w0 : w0 * sinf(.pi * min(1, t * 1.15 + 0.05))
                    if inHead { w = fn / 30 + 1 }
                    for x in Int(cx - w - 1)...Int(cx + w + 1) {
                        let u: Float = (Float(x) + 0.5 - cx) / max(0.5, w)
                        guard abs(u) <= 1 else { continue }
                        let upK: Float = 0.7 + 0.35 * t
                        let sideK: Float = 0.92 - 0.12 * u
                        var c: V3 = base * (upK * sideK)
                        if inHead, let hc = head {
                            let kern: Float = 0.82 + 0.25 * abs(sinf(up / fn * 70 + (u > 0 ? 1.2 : 0)))
                            let side: Float = 0.95 - 0.1 * u
                            c = col(hc) * (kern * side)
                        }
                        plot(x, yy, c)
                    }
                    // Awns: thin bristles off the grain head.
                    if inHead, let hc = head, Int(up) % max(2, n / 32) == 0 {
                        for a in 1...max(2, n / 28) {
                            for side in [-1, 1] { plot(Int(cx) + side * (Int(w) + a), yy - a, col(hc) * 1.05) }
                        }
                    }
                }
            }
            // Ripe root crops: the top of the root at the soil line.
            if !wheat, stage == maxStage, let hc = head {
                for i in 0..<3 {
                    let rx: Float = (Float(i) + 0.5) / 3 * fn + (h2(i, 9, salt) - 0.5) * fn * 0.1
                    let rr: Float = fn / 13
                    for y in Int(fn - rr * 1.2)..<n { for x in Int(rx - rr)...Int(rx + rr) {
                        let dx: Float = (Float(x) + 0.5 - rx) / rr, dy: Float = (Float(y) + 0.5 - (fn - rr * 0.3)) / rr
                        let d: Float = dx * dx + dy * dy
                        guard d < 1 else { continue }
                        let shadeK: Float = 0.75 + 0.35 * (1 - d) - 0.1 * dx
                        plot(x, y, col(hc) * shadeK)
                    } }
                }
            }
            return img
        }
    }

    static func leafLitter(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        var img = Img(n, V4(0.45, 0.32, 0.18, 0))
        let cols: [UInt32] = [0x7A5426, 0x8C6430, 0x6A4A22, 0x9A7438, 0x5E4A26]
        var rng = SRng(UInt64(truncatingIfNeeded: s) &* 977 &+ 13)
        for _ in 0..<(n / 3) {
            let cx = rng.float() * fn, cy = rng.float() * fn
            let len: Float = fn * (0.05 + rng.float() * 0.04), wid: Float = len * 0.45
            let a: Float = rng.float() * .pi
            let ca = cosf(a), sa = sinf(a)
            let c = col(cols[rng.int(cols.count)]) * (0.85 + rng.float() * 0.25)
            let r = Int(len) + 1
            for dy in -r...r { for dx in -r...r {
                let u: Float = Float(dx) * ca + Float(dy) * sa, v: Float = -Float(dx) * sa + Float(dy) * ca
                let taper: Float = 1 - min(0.9, abs(u) / len)          // pointed tips
                let eu: Float = (u * u) / (len * len)
                let ev: Float = (v * v) / (wid * wid * taper)
                let e: Float = eu + ev
                if e > 1 { continue }
                let rib: Float = abs(v) < 0.8 ? 0.75 : 1
                let k: Float = rib * (0.9 + 0.1 * (1 - e))
                img[Int(cx) + dx, Int(cy) + dy] = V4(c.x * k, c.y * k, c.z * k, 1)
            } }
        }
        return img
    }

    // A soil face under a band of another material along the top edge (podzol, mycelium, path sides), with a
    // wavy lower edge and a soft shadow under it.
    static func topped(_ top: @escaping Gen, depth: Float = 0.16, over base: Gen? = nil) -> Gen {
        { n, s in
            var img = (base ?? dirtGen)(n, s)
            let t = top(n, s &+ 3)
            let d = fringe(n, s &+ 5, depth: depth, spikes: n / 8, spikeH: 0.06, width: 0.03)
            let fn = Float(n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let fy = Float(y)
                if fy < d[x] { img.px[i] = t.px[i] } else {
                    let k: Float = 1 - 0.3 * cl(1 - (fy - d[x]) / (fn * 0.03))
                    let c = img.px[i]
                    img.px[i] = V4(c.x * k, c.y * k, c.z * k, 1)
                }
            } }
            return img
        }
    }

    // Cracks across a base material: a few long wandering dark lines with a lit lower lip.
    static func cracked(_ base: @escaping Gen) -> Gen {
        { n, s in
            var img = base(n, s)
            let fn = Float(n)
            let wx = fbm(n, n / 4, 3, s &+ 70), wy = fbm(n, n / 4, 3, s &+ 71)
            let rf = warp(fbm(n, n / 2, 4, s &+ 72), n, wx, wy, fn * 0.15)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let ridge: Float = 1 - abs(2 * rf[i] - 1)
                if ridge > 0.965 {
                    let p = img.px[i]
                    img.px[i] = V4(p.x * 0.35, p.y * 0.35, p.z * 0.35, 1)
                } else if ridge > 0.94 {
                    let j = ((y + 1) % n) * n + x
                    let r2: Float = 1 - abs(2 * rf[j] - 1)
                    let k: Float = r2 > 0.965 ? 1.12 : 0.85
                    let p = img.px[i]
                    img.px[i] = V4(min(1, p.x * k), min(1, p.y * k), min(1, p.z * k), 1)
                }
            } }
            return img
        }
    }

    // Sandstone side: wavy sediment layers, a darker band and a weathered lower edge.
    static func sandstoneSide(_ pal: [(Float, UInt32)]) -> Gen {
        { n, s in
            let fn = Float(n)
            let w = fbm(n, n / 4, 3, s)
            let fine = vnoise(n, max(1, n / 128), s &+ 1)
            var hh = [Float](repeating: 0, count: n * n)
            var img = Img(n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let yy: Float = Float(y) + (w[i] - 0.5) * fn * 0.06
                let l1: Float = sinf(yy / fn * 2 * .pi * 5) * 0.06
                let layers: Float = l1 + sinf(yy / fn * 2 * .pi * 13) * 0.03
                let band: Float = abs(yy - fn * 0.25) < fn * 0.035 ? -0.12 : 0
                let low: Float = Float(y) > fn * 0.84 ? -0.06 : 0
                let t: Float = 0.55 + layers + band + low + (fine[i] - 0.5) * 0.16
                hh[i] = layers * 2 + band
                let c = ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
            } }
            shade(&img, hh, 1)
            return img
        }
    }

    // Log end: irregular growth rings (thin late-wood lines), one drying crack, a wavy bark rim.
    static func ringsTop(bark: [(Float, UInt32)], wood: [(Float, UInt32)]) -> Gen {
        { n, s in
            let fn = Float(n)
            let w = fbm(n, n / 4, 3, s)
            let rv = vnoise(n, max(1, n / 8), s &+ 6)
            let fine = vnoise(n, max(1, n / 64), s &+ 1)
            let rimN = vnoise(n, max(1, n / 16), s &+ 3)
            let a0: Float = h2(1, 2, s) * 2 * .pi
            var hh = [Float](repeating: 0, count: n * n)
            var img = Img(n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let dx: Float = Float(x) - fn / 2 + 0.5, dy: Float = Float(y) - fn / 2 + 0.5
                let ang: Float = atan2f(dy, dx)
                let r: Float = (dx * dx + dy * dy).squareRoot()
                let d: Float = r + (w[i] - 0.5) * fn * 0.03 + sinf(ang * 3 + 1.3) * fn * 0.008
                let ph: Float = d / fn * 13 + (rv[i] - 0.5) * 0.5
                let fr: Float = ph - floorf(ph)
                let ring: Float = 1 - cl((fr - 0.72) / 0.12) * cl((1 - fr) / 0.08)
                var t: Float = 0.62 + (ring - 0.5) * 0.4 - d / fn * 0.3 + (fine[i] - 0.5) * 0.08
                let a: Float = ang - a0 + (w[i] - 0.5) * 0.3 + .pi
                let da: Float = abs(a - 2 * .pi * floorf(a / (2 * .pi)) - .pi)
                let crack = da * d < fn * 0.002 + d * 0.02 && d < fn * 0.3 && d > fn * 0.06
                if crack { t -= 0.45 }
                let edge = Float(min(min(x, n - 1 - x), min(y, n - 1 - y)))
                let rimw: Float = fn * 0.07 + (rimN[i] - 0.5) * fn * 0.04
                let c: V3
                if edge < rimw {
                    c = ramp(0.4 + (fine[i] - 0.5) * 0.4 + (w[i] - 0.5) * 0.3, bark)
                    hh[i] = 0.3 + fine[i] * 0.2
                } else {
                    c = ramp(t, wood)
                    hh[i] = ring * 0.12
                }
                if crack { hh[i] -= 0.15 }
                img.px[i] = V4(c.x, c.y, c.z, 1)
            } }
            shade(&img, hh, 1.1)
            return img
        }
    }

    // Birch bark: chalky white with soft blotches and short dark horizontal lenticels.
    static func birchLog(_ n: Int, _ s: Int) -> Img {
        let fn = Float(n)
        let w = fbm(n, n / 4, 3, s)
        let fine = vnoise(n, max(1, n / 64), s &+ 1)
        let blot = fbm(n, n / 8, 3, s &+ 2)
        let pal: [(Float, UInt32)] = [(0, 0xBEB8AA), (0.5, 0xDCD8CC), (1, 0xF0EEE6)]
        var img = Img(n)
        var hh = [Float](repeating: 0, count: n * n)
        for i in 0..<(n * n) {
            let c = ramp(0.7 + (blot[i] - 0.5) * 0.25 + (fine[i] - 0.5) * 0.08, pal)
            img.px[i] = V4(c.x, c.y, c.z, 1)
        }
        var rng = SRng(UInt64(truncatingIfNeeded: s) &* 7741 &+ 5)
        let dk = col(0x2E2B26)
        for _ in 0..<(n / 6) {
            let cx = rng.int(n), cy = rng.int(n)
            let L: Float = fn * (0.03 + rng.float() * 0.1)
            let hgt = max(1, Int(fn * (0.012 + rng.float() * 0.02)))
            let li = Int(L) + 1
            for dy in -2...(hgt + 2) { for dx in -li...li {
                let x = ((cx + dx) % n + n) % n, y = ((cy + dy) % n + n) % n
                let i = y * n + x
                let wv = Int((w[i] - 0.5) * fn * 0.02)
                let yy = dy + wv
                if Float(abs(dx)) < L * (0.6 + 0.4 * fine[i]) && yy >= 0 && yy < hgt {
                    let k: Float = 0.8 + fine[i] * 0.4
                    img.px[i] = V4(dk.x * k, dk.y * k, dk.z * k, 1)
                    hh[i] = -0.2
                }
            } }
        }
        shade(&img, hh, 1)
        return img
    }

    // Wool: knitted loops under fuzzy fibres.
    static func wool(_ c: V3) -> Gen {
        { n, s in
            let fn = Float(n)
            let k: Float = fn / 16
            let f1 = vnoise(n, 1, s), f2 = vnoise(n, 2, s &+ 1)
            let blot = fbm(n, n / 4, 3, s &+ 2)
            var hh = [Float](repeating: 0, count: n * n)
            var img = Img(n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let shift: Float = floorf(Float(y) / k).truncatingRemainder(dividingBy: 2) * k * 0.5
                let u: Float = (Float(x) + shift) / k, v: Float = Float(y) / k
                let fu: Float = u - floorf(u) - 0.5, fv: Float = v - floorf(v) - 0.5
                let e: Float = (fu / 0.38) * (fu / 0.38) + (fv / 0.6) * (fv / 0.6)
                let loop: Float = expf(-e)
                let fuzz: Float = f1[i] * 0.5 + f2[i] * 0.5
                let t: Float = 0.5 + loop * 0.14 + (fuzz - 0.5) * 0.3 + (blot[i] - 0.5) * 0.12
                hh[i] = loop * 0.25 + fuzz * 0.25
                let m: Float = 0.62 + t * 0.55
                img.px[i] = V4(c.x * m, c.y * m, c.z * m, 1)
            } }
            shade(&img, hh, 0.8)
            return img
        }
    }

    // Concrete: smooth with faint trowel blotches.
    static func concrete(_ c: V3) -> Gen {
        { n, s in
            let b = fbm(n, n / 2, 4, s)
            let fine = vnoise(n, max(1, n / 128), s &+ 1)
            var img = Img(n)
            for i in 0..<(n * n) {
                let m: Float = 0.97 + (b[i] - 0.5) * 0.08 + (fine[i] - 0.5) * 0.03
                img.px[i] = V4(c.x * m, c.y * m, c.z * m, 1)
            }
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
    // Leaves (cutout, greyscale for biome tint): leaves grouped into a dozen clumps that share a brightness and are
    // lit from the top-left (darker toward each clump's lower right), larger and fewer than before; ~400 tiny leaves
    // with random brightness read as photographic speckle next to the stylised ground (both critics).
    static func leaves(_ n: Int, _ s: Int) -> Img {
        var img = Img(n, V4(0.5, 0.5, 0.5, 0))
        var rng = SRng(UInt64(truncatingIfNeeded: s) &* 104729 &+ 3)
        let fn = Float(n)
        let scale: Float = fn / 128
        // Clump centres (wrapping) and their base brightness.
        var clumps: [(Float, Float, Float)] = []
        for _ in 0..<12 { clumps.append((rng.float() * fn, rng.float() * fn, 0.55 + rng.float() * 0.35)) }
        let clumpR: Float = fn * 0.2
        let count = n * n / 70
        for _ in 0..<count {
            let cx: Float = rng.float() * fn, cy: Float = rng.float() * fn
            // Nearest clump (wrap-aware).
            var best: Float = 1e9, base: Float = 0.7, ox: Float = 0, oy: Float = 0
            for (kx, ky, kb) in clumps {
                var dx: Float = cx - kx, dy: Float = cy - ky
                if dx > fn / 2 { dx -= fn } else if dx < -fn / 2 { dx += fn }
                if dy > fn / 2 { dy -= fn } else if dy < -fn / 2 { dy += fn }
                let d2: Float = dx * dx + dy * dy
                if d2 < best { best = d2; base = kb; ox = dx; oy = dy }
            }
            let side: Float = max(-1, min(1, (ox + oy) / (clumpR * 1.4)))   // -1 top-left (lit) ... 1 bottom-right
            let v: Float = base * (1 - 0.22 * side) * (0.92 + rng.float() * 0.12)
            let ang: Float = rng.float() * .pi
            let L: Float = (7 + rng.float() * 5) * scale
            let W: Float = L * 0.48
            let r = Int(L) + 1
            let ca = cosf(ang), sa = sinf(ang)
            for dy in -r...r { for dx in -r...r {
                let fdx = Float(dx), fdy = Float(dy)
                let u: Float = fdx * ca + fdy * sa
                let w: Float = fdy * ca - fdx * sa
                let ue: Float = u / L, we: Float = w / W
                let e: Float = ue * ue + we * we
                if e >= 1 { continue }
                let vein: Float = abs(w) < W * 0.1 ? 0.85 : 1
                let k: Float = min(1, v * (0.86 + 0.14 * ue) * vein * (1 - 0.1 * e))
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
    static let dirtPal: [(Float, UInt32)] = [(0, 0x58402C), (0.5, 0x7E5A3C), (1, 0x9C7450)]   // lighter: terrace step sides read as near-black dashes from above
    static let oakPlank: [(Float, UInt32)] = [(0, 0x7E5C34), (0.5, 0xA67E4C), (1, 0xC49C62)]
    static let oakBark: [(Float, UInt32)] = [(0, 0x3C2C1C), (0.5, 0x60482C), (1, 0x80623E)]
    static let stoneBricks: Gen = masonry(rows: 2, perRow: 1, offset: 0.5, mortarW: 1 / 22, [(0, 0x5E5E60), (0.5, 0x7E7E80), (1, 0x9C9C9C)], mortar: 0x48484A)
    static let sandstonePal: [(Float, UInt32)] = [(0, 0xB8A878), (0.5, 0xD9CE9E), (1, 0xEEE4BC)]
    static let podzolTop: Gen = soil([(0, 0x4A3218), (0.5, 0x6A4A26), (1, 0x8A6A3A)], pebble: 0x7A5A30, pebbles: 6, clods: 9)
    static let myceliumTop: Gen = soil([(0, 0x5E5262), (0.5, 0x786A7C), (1, 0x948698)], pebble: 0xB4A4B4, pebbles: 12, clods: 8)
    static let pathTop: Gen = soil([(0, 0x7A5E36), (0.5, 0x947446), (1, 0xAE8E5A)], pebble: 0x9A8A70, pebbles: 12, clods: 6)
    static let redSandstonePal: [(Float, UInt32)] = [(0, 0x9A4E1E), (0.5, 0xB8662C), (1, 0xCE8040)]

    // Families without a hand-made entry get an HD material coloured from their 16 px painter: every wood's planks,
    // bark and log ends, leaves, wool, concrete, concrete powder and terracotta.
    // Crop stages (generated names, so not in the literal table).
    static func crop(_ name: String) -> Gen? {
        func stage(_ prefix: String) -> Int? { name.hasPrefix(prefix) ? Int(name.dropFirst(prefix.count)) : nil }
        if let st = stage("wheat_stage") { return cropHD(stage: st, max: 7, young: 0x3F9A2C, ripe: 0xB8A340, head: 0xDCBC52, wheat: true, salt: 122) }
        if let st = stage("carrots_stage") { return cropHD(stage: st, max: 3, young: 0x3F9A2C, ripe: 0x48A832, head: 0xF08A1A, wheat: false, salt: 125) }
        if let st = stage("potatoes_stage") { return cropHD(stage: st, max: 3, young: 0x3F9A2C, ripe: 0x4AA034, head: 0xD8B060, wheat: false, salt: 128) }
        if let st = stage("beetroots_stage") { return cropHD(stage: st, max: 3, young: 0x3F9A2C, ripe: 0x3A8A30, head: 0xA02838, wheat: false, salt: 131) }
        return nil
    }

    static func derived(_ name: String, _ src: [V4]) -> Gen? {
        let S = TextureGen.S
        var sum = V3(0, 0, 0), rim = V3(0, 0, 0), mid = V3(0, 0, 0)
        var cnt: Float = 0, rc: Float = 0, mc: Float = 0
        for y in 0..<S { for x in 0..<S {
            let p = src[y * S + x]
            if p.w < 0.5 { continue }
            let c = V3(p.x, p.y, p.z)
            sum += c; cnt += 1
            if x == 0 || y == 0 || x == S - 1 || y == S - 1 { rim += c; rc += 1 }
            if x >= S / 4 && x < S * 3 / 4 && y >= S / 4 && y < S * 3 / 4 { mid += c; mc += 1 }
        } }
        guard cnt > 0 else { return nil }
        let avg = sum / cnt
        if name.hasSuffix("_planks") { return planks(pal(avg, lo: 0.75, hi: 1.18)) }
        if name.hasSuffix("_log_top") || name.hasSuffix("_stem_top") {
            guard rc > 0, mc > 0 else { return nil }
            return ringsTop(bark: pal(rim / rc, lo: 0.7, hi: 1.25), wood: pal(mid / mc, lo: 0.8, hi: 1.12))
        }
        if (name.hasSuffix("_log") && !name.hasPrefix("stripped_")) || name == "crimson_stem" || name == "warped_stem" { return barkSide(pal(avg, lo: 0.62, hi: 1.25)) }
        if name.hasSuffix("_leaves") {
            return { n, s in
                var img = leaves(n, s)
                let k: V3 = avg / 0.72
                for i in 0..<(n * n) { let p = img.px[i]; img.px[i] = V4(p.x * k.x, p.y * k.y, p.z * k.z, p.w) }
                return img
            }
        }
        if name.hasSuffix("_wool") { return wool(avg / 0.9) }
        if name.hasSuffix("_concrete_powder") { return sandLike(pal(avg, lo: 0.85, hi: 1.12)) }
        if name.hasSuffix("_concrete") { return concrete(avg) }
        if (name.hasSuffix("_terracotta") && !name.contains("glazed")) || name == "terracotta" {
            return stone(pal(avg, lo: 0.84, hi: 1.12), veins: 0, strata: 0.02)
        }
        return nil
    }

    static let table: [String: Gen] = [
        "stone": stone(stoneGrey),
        "lava": lava,
        "leaf_litter": leafLitter,
        // Flowers.
        "poppy": flowerHD(0xDB2420, 0x331F0D, .ring, top: 5, size: 2.8, salt: 40),
        "dandelion": flowerHD(0xFAD733, 0xE68C1A, .ring, top: 5, size: 2.8, salt: 42),
        "cornflower": flowerHD(0x5A80F2, 0xF2E680, .ring, top: 5, size: 2.8, salt: 44),
        "allium": flowerHD(0xB070E0, 0x9A50C8, .ball, top: 4, size: 3.2, salt: 430),
        "azure_bluet": flowerHD(0xF2F2F2, 0xE8D040, .ring, top: 7, size: 2.4, salt: 432),
        "red_tulip": flowerHD(0xD83A2A, 0xB82A1A, .cup, top: 5, size: 2.2, salt: 434),
        "orange_tulip": flowerHD(0xF0842A, 0xD06A1A, .cup, top: 5, size: 2.2, salt: 436),
        "white_tulip": flowerHD(0xF0F0F0, 0xD8D8D8, .cup, top: 5, size: 2.2, salt: 438),
        "pink_tulip": flowerHD(0xF0A8C8, 0xE088B0, .cup, top: 5, size: 2.2, salt: 440),
        "oxeye_daisy": flowerHD(0xF4F4F4, 0xE8C83A, .ring, top: 5, size: 3, salt: 442),
        "lily_of_the_valley": flowerHD(0xF8F8F8, 0xE8F0E0, .bells, top: 6, size: 1.8, salt: 444),
        "blue_orchid": flowerHD(0x2AA8F0, 0x1A78C8, .ring, top: 5, size: 2.8, salt: 446),
        "short_grass": blades(salt: 101, count: 26, len: 0.3, 0.9),
        "seagrass": blades(salt: 105, count: 12, len: 0.55, 1.0, lean: 1.6, colour: 0x3A8A2A),
        "kelp": kelpHD,
        "dead_bush": deadBushHD,
        "vine": vineHD,
        "lily_pad": lilyPadHD,
        "sugar_cane": caneHD,
        "tall_grass_bottom": blades(salt: 102, count: 14, len: 1.3, 1.9),
        "tall_grass_top": blades(salt: 102, count: 14, len: 1.3, 1.9, from: 1),
        "fern": blades(salt: 103, count: 7, len: 0.55, 0.95, fern: true),
        "large_fern_bottom": blades(salt: 104, count: 7, len: 1.2, 1.9, fern: true),
        "large_fern_top": blades(salt: 104, count: 7, len: 1.2, 1.9, from: 1, fern: true),
        "hay_block_side": haySide,
        "hay_block_top": hayTop,
        "glass": glass,
        // Metals: copper through its oxidation stages (plain and cut), iron and gold.
        "copper_block": metal(0xC06B4F, shine: 0.16),
        "exposed_copper": metal(0xA87A62, patina: 0.12),
        "weathered_copper": metal(0x8A8A6A, patina: 0.55),
        "oxidized_copper": metal(0x52A284, patina: 0.95, shine: 0.06),
        "cut_copper": metal(0xC06B4F, tiles: 2, shine: 0.16),
        "exposed_cut_copper": metal(0xA87A62, patina: 0.12, tiles: 2),
        "weathered_cut_copper": metal(0x8A8A6A, patina: 0.55, tiles: 2),
        "oxidized_cut_copper": metal(0x52A284, patina: 0.95, tiles: 2, shine: 0.06),
        "iron_block": metal(0xD8D8D8, tiles: 2, shine: 0.1),
        "gold_block": metal(0xF2CC3A, tiles: 2, shine: 0.18),
        "bookshelf": bookshelf,
        "magma": lavaLike([(0, 0x2E0E06), (0.4, 0x4E1A0C), (0.62, 0x8A3414), (0.85, 0xE8742A), (1, 0xFFB050)], cells: 4, seamW: 18),
        // Soils and ground covers.
        "podzol_top": podzolTop,
        "podzol_side": topped(podzolTop),
        "mycelium_top": myceliumTop,
        "mycelium_side": topped(myceliumTop),
        "dirt_path_top": pathTop,
        "dirt_path_side": topped(pathTop, depth: 0.1),
        "rooted_dirt": soil([(0, 0x5E4230), (0.5, 0x7E5C40), (1, 0x9A7A58)], pebble: 0xB49A78, pebbles: 16, clods: 9),
        "moss_block": soil([(0, 0x3A5220), (0.5, 0x56762E), (1, 0x729842)], pebble: 0x48662A, pebbles: 6, clods: 10),
        "farmland": soil([(0, 0x4A3220), (0.5, 0x624430), (1, 0x7C5A40)], pebble: 0x6A5440, pebbles: 5, clods: 12),
        "farmland_moist": soil([(0, 0x2E1E12), (0.5, 0x3E2A1C), (1, 0x52382A)], pebble: 0x48362A, pebbles: 5, clods: 12),
        "soul_sand": soil([(0, 0x3A2A20), (0.5, 0x52402E), (1, 0x6A5440)], pebble: 0x2A1E16, pebbles: 10, clods: 8),
        "soul_soil": soil([(0, 0x3E3024), (0.5, 0x54442F), (1, 0x6A5840)], pebble: 0x4A3A2A, pebbles: 4, clods: 7),
        "ice": iceHD,
        "pumpkin_side": ribbedSide([(0, 0x9A520A), (0.5, 0xD8801A), (1, 0xF0A030)], ribs: 4),
        "pumpkin_top": radialTop([(0, 0x9A520A), (0.5, 0xD8801A), (1, 0xF0A030)], lobes: 8, stem: 0x5A6A1A),
        "melon_side": melonSide,
        "chest_top": chestFace(0),
        "chest_side": chestFace(1),
        "chest_front": chestFace(2),
        "barrel_side": barrelSide,
        "barrel_top": barrelTop,
        "barrel_bottom": barrelTop,
        "diamond_block": gemBlock([(0, 0x2A9A9A), (0.5, 0x6ADCD8), (1, 0xD0FFFA)]),
        "emerald_block": gemBlock([(0, 0x0E6A30), (0.5, 0x2AB85A), (1, 0x9AF0B8)]),
        "lapis_block": gemBlock([(0, 0x142A78), (0.5, 0x2A4EB0), (1, 0x6A8AE0)], cells: 7, flecks: true),
        "redstone_block": gemBlock([(0, 0x6A0806), (0.5, 0xB01810), (1, 0xF05040)], cells: 6),
        "coal_block": gemBlock([(0, 0x101012), (0.5, 0x222226), (1, 0x3E3E44)], cells: 7),
        "red_mushroom_block": mushroomCap([(0, 0x8A1410), (0.5, 0xB82420), (1, 0xD43A30)], spots: 7),
        "brown_mushroom_block": mushroomCap([(0, 0x6A4A32), (0.5, 0x8A6448), (1, 0xA27C5C)], spots: 0),
        "mushroom_stem": mushroomStem,
        "mushroom_block_inside": mushroomInside,
        "melon_top": radialTop([(0, 0x52801A), (0.5, 0x7EA82A), (1, 0x9AC23A)], lobes: 8, stem: 0x6A7A2A, stripes: true),
        "cactus_side": cactusSide,
        "cactus_top": cactusEnd(true),
        "cactus_bottom": cactusEnd(false),
        "packed_ice": stone([(0, 0x7C9ED8), (0.5, 0x94B2E6), (1, 0xB0C8F2)], veins: 0.5, strata: 0),
        "blue_ice": stone([(0, 0x5A86D8), (0.5, 0x74A0EC), (1, 0x96BCF8)], veins: 0.5, strata: 0),
        "prismarine": stone([(0, 0x4A8A80), (0.5, 0x62A898), (1, 0x86C4B0)], veins: 0.7, strata: 0),
        "dark_prismarine": masonry(rows: 2, perRow: 2, offset: 0, mortarW: 1 / 30, [(0, 0x24443A), (0.5, 0x335A4C), (1, 0x467060)], mortar: 0x16302A, chips: 0.6),
        "amethyst_block": cobble([(0, 0x6A4AA0), (0.5, 0x8A66C4), (1, 0xB08EE4)], mortar: 0x4A3274, cells: 6),
        // Polished and smooth stones (bevelled rim, calmed grain).
        "polished_andesite": polished(stone([(0, 0x6E6E6E), (0.5, 0x8A8A8A), (1, 0xA6A6A4)], veins: 0)),
        "polished_diorite": polished(stone([(0, 0x9E9E9C), (0.5, 0xC6C6C4), (1, 0xE8E8E6)], veins: 0)),
        "polished_granite": polished(stone([(0, 0x7A4E40), (0.5, 0x9A6A58), (1, 0xB88A74)], veins: 0)),
        "polished_tuff": polished(stone([(0, 0x55564E), (0.5, 0x6C6D64), (1, 0x86877C)], veins: 0)),
        "polished_deepslate": polished(stone(deepslate, veins: 0, strata: 0, streak: 0.2), calm: 0.55),
        "polished_blackstone": polished(stone([(0, 0x221E24), (0.5, 0x342E36), (1, 0x4A424C)], veins: 0, strata: 0), calm: 0.6),
        "smooth_stone": polished(stone([(0, 0x8E8E8E), (0.5, 0xA2A2A2), (1, 0xB4B4B4)], veins: 0, strata: 0), calm: 0.35, rim: 1 / 20),
        "smooth_sandstone": polished(stone(sandstonePal, veins: 0, strata: 0), calm: 0.5, rim: 1 / 32),
        "smooth_red_sandstone": polished(stone(redSandstonePal, veins: 0, strata: 0), calm: 0.5, rim: 1 / 32),
        "cut_sandstone": masonry(rows: 2, perRow: 1, offset: 0, mortarW: 1 / 40, sandstonePal, mortar: 0xA89868, chips: 0.4, tone: 0.06),
        "cut_red_sandstone": masonry(rows: 2, perRow: 1, offset: 0, mortarW: 1 / 40, redSandstonePal, mortar: 0x8A4A20, chips: 0.4, tone: 0.06),
        "red_sandstone": sandstoneSide(redSandstonePal),
        "red_sandstone_top": stone(redSandstonePal, veins: 0, strata: 0),
        "calcite": stone([(0, 0xC8C8C2), (0.5, 0xDEDED8), (1, 0xF2F2EC)], veins: 0.3, strata: 0),
        "dripstone_block": stone([(0, 0x6A5444), (0.5, 0x86705C), (1, 0xA48C76)], veins: 0.2, strata: 0.04, streak: 0.18),
        "clay": stone([(0, 0x8C929E), (0.5, 0xA0A6B2), (1, 0xB4BAC4)], veins: 0, strata: 0.01),
        "packed_mud": soil([(0, 0x7A5A42), (0.5, 0x8E6A4E), (1, 0xA27C5C)], pebble: 0x6A4E3A, pebbles: 5, clods: 9),
        "mud": soil([(0, 0x2E2628), (0.5, 0x3C3236), (1, 0x4E4246)], pebble: 0x5A4E50, pebbles: 3, clods: 6),
        // Emberdeep and the Hollow.
        "netherrack": netherrackGen,
        "nether_gold_ore": ore(netherrackGen, 0xD8A824, 0xFCE878, clusters: 9),
        "nether_quartz_ore": ore(netherrackGen, 0xCFC6B8, 0xFFFFFF, clusters: 8),
        "crimson_nylium": crimsonNylium,
        "crimson_nylium_side": topped(crimsonNylium, depth: 0.2, over: netherrackGen),
        "warped_nylium": warpedNylium,
        "warped_nylium_side": topped(warpedNylium, depth: 0.2, over: netherrackGen),
        "nether_wart_block": lumps([(0, 0x4A0608), (0.5, 0x7E0E10), (1, 0xA82A22)]),
        "warped_wart_block": lumps([(0, 0x0A4A48), (0.5, 0x127068), (1, 0x2A988A)]),
        "glowstone": lumps([(0, 0x7A4A18), (0.35, 0xB88430), (0.7, 0xF0C860), (1, 0xFFF4C0)], cells: 8, gloss: 1),
        "shroomlight": lumps([(0, 0xA04A10), (0.5, 0xF09030), (1, 0xFFD890)], cells: 7, gloss: 1),
        "sculk": lumps([(0, 0x041820), (0.5, 0x0A2C34), (1, 0x16505A)], cells: 12),
        "ancient_debris_side": stone([(0, 0x3A2A26), (0.5, 0x5E443A), (1, 0x7E6050)], veins: 0.4, strata: 0.14),
        "ancient_debris_top": stone([(0, 0x3A2A26), (0.5, 0x5E443A), (1, 0x7E6050)], veins: 0.6, strata: 0),
        "basalt_top": stone([(0, 0x3A3A3E), (0.5, 0x505056), (1, 0x68686E)], veins: 0, strata: 0),
        "smooth_basalt": polished(stone([(0, 0x34343A), (0.5, 0x48484E), (1, 0x5E5E64)], veins: 0, strata: 0)),
        "blackstone": stone([(0, 0x1E1A20), (0.5, 0x2E2830), (1, 0x443C46)], veins: 0.3, strata: 0.05),
        "basalt_side": stone([(0, 0x3A3A3E), (0.5, 0x4E4E54), (1, 0x66666C)], veins: 0, strata: 0, streak: 0.8),
        "end_stone": stone([(0, 0xC8C88E), (0.5, 0xDCDCA2), (1, 0xEEEEBC)], veins: 0, strata: 0),
        "end_stone_bricks": masonry(rows: 4, perRow: 2, offset: 0.25, mortarW: 1 / 22, [(0, 0xC8C890), (0.5, 0xDADAA6), (1, 0xEAEABC)], mortar: 0xA6A676, chips: 0.8),
        "purpur_block": masonry(rows: 4, perRow: 4, offset: 0, mortarW: 1 / 30, [(0, 0x8A5E8A), (0.5, 0xA678A6), (1, 0xC096C0)], mortar: 0x6C486C, chips: 0.5, tone: 0.1),
        "crying_obsidian": cryingObsidian,
        "purpur_pillar": pillarSide([(0, 0x7A507A), (0.5, 0xA678A6), (1, 0xC69CC6)]),
        "purpur_pillar_top": pillarTop([(0, 0x7A507A), (0.5, 0xA678A6), (1, 0xC69CC6)]),
        "bedrock": stone([(0, 0x141416), (0.3, 0x2E2E32), (0.6, 0x55555A), (1, 0x8A8A90)], veins: 1.4, strata: 0),
        "obsidian": stone([(0, 0x0E0A16), (0.5, 0x1C1428), (0.85, 0x2E2240), (1, 0x4A3A64)], veins: 0.8, strata: 0),
        "red_nether_bricks": masonry(rows: 4, perRow: 2, offset: 0.25, mortarW: 1 / 20, [(0, 0x480A0C), (0.5, 0x5E1214), (1, 0x7A1C1E)], mortar: 0x260406, clay: true, chips: 1.2),
        "polished_blackstone_bricks": masonry(rows: 4, perRow: 2, offset: 0.25, mortarW: 1 / 24, [(0, 0x262228), (0.5, 0x363038), (1, 0x4A424C)], mortar: 0x141216, chips: 1.4),
        "tuff_bricks": masonry(rows: 4, perRow: 2, offset: 0.25, mortarW: 1 / 24, [(0, 0x55564E), (0.5, 0x6C6D64), (1, 0x86877C)], mortar: 0x3E3F38, chips: 1),
        "prismarine_bricks": masonry(rows: 4, perRow: 2, offset: 0.25, mortarW: 1 / 24, [(0, 0x4E9A88), (0.5, 0x66B4A0), (1, 0x86CCB8)], mortar: 0x3A6E64, chips: 0.6),
        "andesite": stone([(0, 0x6E6E6E), (0.5, 0x8A8A8A), (1, 0xA6A6A4)], veins: 0.3),
        "diorite": stone([(0, 0x9E9E9C), (0.5, 0xC6C6C4), (1, 0xE8E8E6)], veins: 0.2),
        "granite": stone([(0, 0x7A4E40), (0.5, 0x9A6A58), (1, 0xB88A74)], veins: 0.4),
        "tuff": stone([(0, 0x55564E), (0.5, 0x6C6D64), (1, 0x86877C)], veins: 0.5),
        "deepslate": stone(deepslate, veins: 0.4, strata: 0.03, streak: 0.35),
        "dirt": dirtGen,
        "coarse_dirt": soil([(0, 0x4C3626), (0.5, 0x6C5038), (1, 0x8A6A4C)], pebble: 0x7C7468, pebbles: 16),
        "grass_block_top": grassTop,
        "grass_block_side": grassSide,
        "grass_block_snow": grassSnow,
        "snow": snow,
        "snow_block": snow,
        "stone_bricks": stoneBricks,
        "mossy_stone_bricks": mossy(stoneBricks, amount: 0.45),
        "cracked_stone_bricks": cracked(stoneBricks),
        "mossy_cobblestone": mossy(cobble([(0, 0x585A5C), (0.5, 0x808082), (1, 0xA2A09E)], mortar: 0x3A3838), amount: 0.5),
        "bricks": masonry(rows: 4, perRow: 2, offset: 0.25, mortarW: 1 / 18, [(0, 0x7A3A2C), (0.5, 0x985040), (1, 0xB4705A)], mortar: 0xB0AAA0, clay: true, chips: 1.4),
        "deepslate_bricks": masonry(rows: 4, perRow: 2, offset: 0.25, mortarW: 1 / 26, [(0, 0x343436), (0.5, 0x4A4A4C), (1, 0x626264)], mortar: 0x202022, chips: 1.2),
        "deepslate_tiles": masonry(rows: 4, perRow: 4, offset: 0, mortarW: 1 / 26, [(0, 0x262628), (0.5, 0x363638), (1, 0x4C4C4E)], mortar: 0x161618, chips: 0.8),
        "nether_bricks": masonry(rows: 4, perRow: 2, offset: 0.25, mortarW: 1 / 20, [(0, 0x2A1014), (0.5, 0x3E181C), (1, 0x5A2428)], mortar: 0x1A0A0C, clay: true, chips: 1.2),
        "mud_bricks": masonry(rows: 4, perRow: 2, offset: 0.25, mortarW: 1 / 18, [(0, 0x6E5240), (0.5, 0x89684F), (1, 0xA48262)], mortar: 0x5A4234, clay: true, chips: 0.8),
        "cobbled_deepslate": cobble([(0, 0x2E2E34), (0.5, 0x48484E), (1, 0x5E5E64)], mortar: 0x18181C),
        "sandstone": sandstoneSide(sandstonePal),
        "sandstone_top": stone(sandstonePal, veins: 0, strata: 0),
        "sandstone_bottom": stone(sandstonePal, veins: 0, strata: 0.02),
        "oak_log_top": ringsTop(bark: oakBark, wood: [(0, 0x8A6C40), (0.5, 0xB0915B), (1, 0xC8AA72)]),
        "birch_log": birchLog,
        "oak_leaves": leaves,
        "oak_log": barkSide(oakBark),
        "oak_planks": planks(oakPlank),
        "spruce_planks": planks([(0, 0x523A22), (0.5, 0x6E5034), (1, 0x8A6844)]),
        "birch_planks": planks([(0, 0xA89664), (0.5, 0xC4B07C), (1, 0xDCCA98)]),
        "cobblestone": cobble([(0, 0x585A5C), (0.5, 0x808082), (1, 0xA2A09E)], mortar: 0x3A3838),
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

    // Detail transfer (every texture without an HD material): the edge-preserving upscale keeps the 16 px design, then
    // each source texel's material class lays 128 px detail over it, so its flat 8x8 squares read as material at the
    // same density as the HD blocks (critics: furnace, crafting table, barrel... looked pixelated next to them).
    // Classes: grey (stone, metal: mottling and grain), brown (wood: streaks along the dominant grain direction of the
    // wood texels), other (soft fine mottling). Alpha comes from the upscale untouched.
    static func detailed(_ src: [V4], salt: Int, n: Int) -> Img {
        let S = TextureGen.S
        var img = upscale(src, detail: 0, salt: salt, n: n)
        var cls = [Int](repeating: 2, count: S * S)
        for i in 0..<(S * S) {
            let c = src[i]
            let mx: Float = max(c.x, max(c.y, c.z)), mn: Float = min(c.x, min(c.y, c.z))
            let sat: Float = mx > 0.001 ? (mx - mn) / mx : 0
            var hue: Float = 0
            if mx - mn > 0.001 {
                if mx == c.x { hue = (c.y - c.z) / (mx - mn) / 6 }
                else if mx == c.y { hue = (2 + (c.z - c.x) / (mx - mn)) / 6 }
                else { hue = (4 + (c.x - c.y) / (mx - mn)) / 6 }
                if hue < 0 { hue += 1 }
            }
            if sat < 0.16 { cls[i] = 0 } else if hue > 0.03 && hue < 0.14 && sat < 0.8 && mx < 0.9 { cls[i] = 1 }
        }
        // Grain direction: luminance steps between neighbouring wood texels, across x vs across y.
        var gx: Float = 0, gy: Float = 0
        for y in 0..<S { for x in 0..<S where cls[y * S + x] == 1 {
            let l: Float = (src[y * S + x].x + src[y * S + x].y + src[y * S + x].z) / 3
            if x + 1 < S && cls[y * S + x + 1] == 1 {
                let r = src[y * S + x + 1]
                gx += abs((r.x + r.y + r.z) / 3 - l)
            }
            if y + 1 < S && cls[(y + 1) * S + x] == 1 {
                let d = src[(y + 1) * S + x]
                gy += abs((d.x + d.y + d.z) / 3 - l)
            }
        } }
        let alongX = gy >= gx * 0.8
        let grain = vnoise(n, 2, salt &+ 3)
        let blot = fbm(n, n / 4, 5, salt)
        let rows = vnoise(n, 2, salt &+ 5)
        let soft = fbm(n, n / 8, 3, salt &+ 6)
        let mott = fbm(n, n / 8, 4, salt &+ 8)
        var hh = [Float](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let k = cls[(y * S / n) * S + x * S / n]
            var d: Float
            if k == 0 {
                d = 1 + (blot[i] - 0.5) * 0.34 + (grain[i] - 0.5) * 0.14
            } else if k == 1 {
                let st: Float = alongX ? rows[y * n + x / 8] : rows[(y / 8) * n + x]
                d = 1 + (st - 0.5) * 0.30 + (soft[i] - 0.5) * 0.12
            } else {
                d = 1 + (mott[i] - 0.5) * 0.18 + (grain[i] - 0.5) * 0.08
            }
            let c = img.px[i]
            let o = V4(c.x * d, c.y * d, c.z * d, c.w)
            img.px[i] = o
            hh[i] = (o.x + o.y + o.z) / 3
        } }
        shade(&img, hh, 0.5)
        return img
    }


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
