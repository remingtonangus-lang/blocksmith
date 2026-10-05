import Foundation
import simd

// HD item art (Remington's TV playtest: "the tools and every item's inventory look are bad"). Every `item_` texture
// layer at the GPU resolution (128 px by default) instead of the 16 px pixel art upscaled nearest:
//   tools and armour (7 tiers x sword, pickaxe, axe, shovel, hoe, spear; 7 sets x helmet, chestplate, leggings,
//   boots) are drawn from vector designs: signed-distance shapes, a bevel lit from the upper left like the block
//   textures, per-material shading (wood grain, speckled stone, polished steel / gold / copper with a specular band,
//   faceted diamond, duskium with a violet sheen, chain rings, stitched leather), a crisp dark outline that reads at TV
//   distance and a soft drop shadow kept under the 0.5 cutout (so the 3D item models ignore it);
//   every other item: its 16 px art scaled up with Scale2x (smooth diagonals, the colours kept), then the same bevel
//   light and drop shadow.
// Original art, all procedural (no external assets).
enum ItemHD {
    // MARK: Materials

    enum Kind { case metal, gem, wood, stone, leather, chain, copper, dusk, soft }
    struct Mat { var kind: Kind; var base: V3; var dark: V3; var light: V3 }

    static func hex(_ h: UInt32) -> V3 { V3(Float((h >> 16) & 255), Float((h >> 8) & 255), Float(h & 255)) / 255 }

    static let mats: [String: Mat] = [
        "wood": Mat(kind: .wood, base: hex(0xB98E58), dark: hex(0x6A4A26), light: hex(0xE6C690)),
        "handle": Mat(kind: .wood, base: hex(0x7A5530), dark: hex(0x3E2914), light: hex(0xB08250)),
        "stone": Mat(kind: .stone, base: hex(0x767C86), dark: hex(0x363A44), light: hex(0xAEB4BE)),
        "iron": Mat(kind: .metal, base: hex(0xC9CED6), dark: hex(0x5E646E), light: hex(0xFFFFFF)),
        "golden": Mat(kind: .metal, base: hex(0xF0C33C), dark: hex(0x8A5A10), light: hex(0xFFF4B0)),
        "diamond": Mat(kind: .gem, base: hex(0x46D8E0), dark: hex(0x146A7A), light: hex(0xD8FFFF)),
        "netherite": Mat(kind: .dusk, base: hex(0x4A4450), dark: hex(0x18151C), light: hex(0xB59AD8)),
        "copper": Mat(kind: .copper, base: hex(0xDA7240), dark: hex(0x6E2E12), light: hex(0xFFC29A)),
        "leather": Mat(kind: .leather, base: hex(0x8E5430), dark: hex(0x4A2812), light: hex(0xC08458)),
        "grip": Mat(kind: .leather, base: hex(0x5A3A26), dark: hex(0x2A1A10), light: hex(0x8A6040)),
        "chainmail": Mat(kind: .chain, base: hex(0xA0A4AA), dark: hex(0x4A4C52), light: hex(0xE8EAEE)),
        "turtle": Mat(kind: .leather, base: hex(0x4FA046), dark: hex(0x1F4A1C), light: hex(0x9AD88A)),
        // Common items (soft: smooth diffuse with a gentle highlight).
        "apple": Mat(kind: .soft, base: hex(0xD8282A), dark: hex(0x6A0E12), light: hex(0xFF9A8A)),
        "leaf": Mat(kind: .soft, base: hex(0x52A63A), dark: hex(0x1E4A16), light: hex(0xA8E08A)),
        "stem": Mat(kind: .wood, base: hex(0x6A4A2A), dark: hex(0x2E1E10), light: hex(0x9A7448)),
        "crust": Mat(kind: .soft, base: hex(0xC8883E), dark: hex(0x6A3A12), light: hex(0xF0C27A)),
        "emerald": Mat(kind: .gem, base: hex(0x2ECC5A), dark: hex(0x0A5A22), light: hex(0xC8FFD8)),
        "coal": Mat(kind: .stone, base: hex(0x34343A), dark: hex(0x101012), light: hex(0x8A8A96)),
        "bone": Mat(kind: .soft, base: hex(0xE8E2CC), dark: hex(0x8A8270), light: hex(0xFFFFF4)),
        "white": Mat(kind: .soft, base: hex(0xEDEDED), dark: hex(0x9A9AA4), light: hex(0xFFFFFF)),
        "flint": Mat(kind: .stone, base: hex(0x4C4C54), dark: hex(0x1A1A1E), light: hex(0x9A9AA8)),
        "water": Mat(kind: .soft, base: hex(0x3A6EE0), dark: hex(0x142A70), light: hex(0xA8C8FF)),
        "lava": Mat(kind: .soft, base: hex(0xFF7A1A), dark: hex(0xA02A08), light: hex(0xFFE07A)),
        "milk": Mat(kind: .soft, base: hex(0xF4F4F0), dark: hex(0xB0B0AA), light: hex(0xFFFFFF)),
        "meat": Mat(kind: .soft, base: hex(0xC8383A), dark: hex(0x6A1416), light: hex(0xF29A90)),
        "cooked": Mat(kind: .soft, base: hex(0x8A4A24), dark: hex(0x3A1C0A), light: hex(0xC8885A)),
        "fat": Mat(kind: .soft, base: hex(0xF0D8C8), dark: hex(0xA08878), light: hex(0xFFF4EE)),
        "pearl": Mat(kind: .gem, base: hex(0x1E8A7A), dark: hex(0x0A3A34), light: hex(0x9AF0DA)),
        "redstone": Mat(kind: .soft, base: hex(0xE01818), dark: hex(0x700808), light: hex(0xFF8A70)),
        "glow": Mat(kind: .soft, base: hex(0xF8D040), dark: hex(0xA07010), light: hex(0xFFF8C0)),
        "gunpowder": Mat(kind: .stone, base: hex(0x6A6A6E), dark: hex(0x2A2A2E), light: hex(0xB4B4BA)),
        "sugar": Mat(kind: .soft, base: hex(0xF4F4F8), dark: hex(0xB8B8C4), light: hex(0xFFFFFF)),
        "paper": Mat(kind: .soft, base: hex(0xF2EEDC), dark: hex(0xB4AC94), light: hex(0xFFFFFF)),
        "book": Mat(kind: .leather, base: hex(0x8A3A26), dark: hex(0x3E160C), light: hex(0xC8705A)),
        "wheat": Mat(kind: .soft, base: hex(0xDCB850), dark: hex(0x7A5A1A), light: hex(0xFFF0A0)),
        "carrot": Mat(kind: .soft, base: hex(0xF07A1A), dark: hex(0x8A3A08), light: hex(0xFFC07A)),
        "egg": Mat(kind: .soft, base: hex(0xE8DCC4), dark: hex(0x9A8A6E), light: hex(0xFFFFF8)),
        "slime": Mat(kind: .soft, base: hex(0x6ACC4A), dark: hex(0x2A6A1A), light: hex(0xD0FFB0)),
        "blaze": Mat(kind: .soft, base: hex(0xF8B02A), dark: hex(0xA0520A), light: hex(0xFFF4B0)),
        "string": Mat(kind: .soft, base: hex(0xE4E4E8), dark: hex(0x8A8A94), light: hex(0xFFFFFF)),
        // Overlay pairs: the tinted part (drawn white, tinted per item) and bottle glass.
        "tint": Mat(kind: .soft, base: hex(0xF2F2F2), dark: hex(0x8A8A8A), light: hex(0xFFFFFF)),
        "glass": Mat(kind: .soft, base: hex(0xD4E2F2), dark: hex(0x7A8AA0), light: hex(0xFFFFFF)),
    ]

    static let tiers = ["wooden", "stone", "iron", "golden", "diamond", "netherite", "copper"]
    static let toolKinds = ["sword", "pickaxe", "axe", "shovel", "hoe", "spear"]
    static let armorSets = ["leather", "chainmail", "iron", "golden", "diamond", "netherite", "copper"]
    static let armorKinds = ["helmet", "chestplate", "leggings", "boots"]

    // The vector design for an item name: (kind, material), nil for items drawn from their pixel art.
    static func design(_ item: String) -> (String, String)? {
        if item == "turtle_helmet" { return ("helmet", "turtle") }
        for t in tiers { for k in toolKinds where item == "\(t)_\(k)" { return (k, t == "wooden" ? "wood" : t) } }
        for a in armorSets { for k in armorKinds where item == "\(a)_\(k)" { return (k, a) } }
        return nil
    }

    // Texture generator for an item layer (HDTex.generator calls this first for every `item_` name).
    static func generator(_ name: String, _ src: [V4]) -> HDTex.Gen? {
        guard name.hasPrefix("item_") else { return nil }
        let item = String(name.dropFirst(5))
        if let (k, m) = design(item) {
            return { n, _ in var img = HDTex.Img(n); img.px = ItemHD.vector(k, m, n); return img }
        }
        if gunKeys.contains(item) {
            return { n, _ in var img = HDTex.Img(n); img.px = ItemHD.render(ItemHD.gunCanvas(item, n)); return img }
        }
        if let (key, overlay) = pairKeys[name] {
            return { n, _ in var img = HDTex.Img(n); img.px = ItemHD.render(ItemHD.pairCanvas(key, n), split: overlay ? 2 : 1); return img }
        }
        if let sp = spriteByItem[item] {
            let probe = Canvas(4)
            if family(probe, item, sp) {
                return { n, _ in
                    let cv = Canvas(n)
                    _ = ItemHD.family(cv, item, sp)
                    var img = HDTex.Img(n); img.px = ItemHD.render(cv); return img
                }
            }
        }
        if src.allSatisfy({ $0.w < 0.5 }) { return nil }
        let decor = !overlayNames.contains(name)
        return { n, _ in var img = HDTex.Img(n); img.px = ItemHD.upscaled(src, n, outlined: decor); return img }
    }

    // MARK: Signed distances (icon space 0...1, y down)

    final class Canvas {
        let n: Int
        var parts: [(d: [Float], t: [Float], mat: String, r: Float, chamfer: Bool)] = []
        let pts: [V2]
        // Design space seen through a turn (radians, positive lifts the right side) and a zoom about the centre.
        init(_ n: Int, tilt: Float = 0, zoom: Float = 1) {
            self.n = n
            let co = cosf(tilt), si = sinf(tilt)
            pts = (0..<(n * n)).map { i in
                let dx = ((Float(i % n) + 0.5) / Float(n) - 0.5) / zoom, dy = ((Float(i / n) + 0.5) / Float(n) - 0.5) / zoom
                return V2(0.5 + dx * co - dy * si, 0.5 + dx * si + dy * co)
            }
        }
        @inline(__always) func p(_ i: Int) -> V2 { pts[i] }

        static func seg(_ p: V2, _ a: V2, _ b: V2) -> (Float, Float) {
            let ab = b - a
            let t = simd_clamp(simd_dot(p - a, ab) / max(1e-9, simd_dot(ab, ab)), 0, 1)
            return (simd_length(p - (a + ab * t)), t)
        }
        func capsule(_ a: V2, _ b: V2, _ r0: Float, _ r1: Float? = nil) -> ([Float], [Float]) {
            var d = [Float](repeating: 9, count: n * n), t = [Float](repeating: 0, count: n * n)
            let r1v = r1 ?? r0
            for i in 0..<(n * n) {
                let (dd, tt) = Canvas.seg(p(i), a, b)
                d[i] = dd - (r0 + (r1v - r0) * tt); t[i] = tt
            }
            return (d, t)
        }
        func circle(_ c: V2, _ r: Float) -> [Float] {
            var d = [Float](repeating: 9, count: n * n)
            for i in 0..<(n * n) { d[i] = simd_length(p(i) - c) - r }
            return d
        }
        func poly(_ pts: [V2]) -> [Float] {
            var d = [Float](repeating: 9, count: n * n)
            let m = pts.count
            for i in 0..<(n * n) {
                let q = p(i)
                var best: Float = 9
                var inside = false
                for e in 0..<m {
                    let a = pts[e], b = pts[(e + 1) % m]
                    best = min(best, Canvas.seg(q, a, b).0)
                    if (a.y > q.y) != (b.y > q.y) {
                        let xi = (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x
                        if q.x < xi { inside.toggle() }
                    }
                }
                d[i] = inside ? -best : best
            }
            return d
        }
        func axis(_ a: V2, _ b: V2) -> [Float] {
            var t = [Float](repeating: 0, count: n * n)
            for i in 0..<(n * n) { t[i] = Canvas.seg(p(i), a, b).1 }
            return t
        }
        // r: the radius of the part's rounded body (a handle's own radius: a cylinder); chamfer: a linear profile up
        // to r instead (flat facets meeting at the medial axis: a blade's ridge).
        func add(_ d: [Float], _ t: [Float], _ mat: String, r: Float = 0.06, chamfer: Bool = false) { parts.append((d, t, mat, r, chamfer)) }
        func below(_ y: Float) -> [Float] { (0..<(n * n)).map { p($0).y - y } }
        static func union(_ a: [Float], _ b: [Float]) -> [Float] { zip(a, b).map { min($0, $1) } }
        static func intersect(_ a: [Float], _ b: [Float]) -> [Float] { zip(a, b).map { max($0, $1) } }
        static func offset(_ a: [Float], _ k: Float) -> [Float] { a.map { $0 + k } }
    }

    static func bez(_ p0: V2, _ c: V2, _ p1: V2, _ k: Int) -> [V2] {
        (0..<k).map { i in
            let t = Float(i) / Float(k - 1), u = 1 - t
            let a: V2 = p0 * (u * u)
            let b: V2 = c * (2 * u * t)
            return a + b + p1 * (t * t)
        }
    }

    // A curved band (quadratic Bezier spine) as a polygon, its width tapering w0 -> w1.
    static func band(_ p0: V2, _ c: V2, _ p1: V2, _ w0: Float, _ w1: Float, _ k: Int = 14) -> [V2] {
        let pts = bez(p0, c, p1, k)
        var left: [V2] = [], right: [V2] = []
        for i in 0..<k {
            let q = pts[min(i + 1, k - 1)], o = pts[max(i - 1, 0)]
            var tg = q - o
            let len = simd_length(tg)
            tg = len > 1e-6 ? tg / len : V2(1, 0)
            let nrm = V2(-tg.y, tg.x)
            let w = (w0 + (w1 - w0) * Float(i) / Float(k - 1)) / 2
            left.append(pts[i] + nrm * w); right.append(pts[i] - nrm * w)
        }
        return left + right.reversed()
    }

    // MARK: Noise

    static func vnoise(_ x: Float, _ y: Float, _ s: Float, _ seed: UInt32) -> Float {
        let fx = x * s, fy = y * s
        let x0 = Int(floorf(fx)), y0 = Int(floorf(fy))
        var tx = fx - Float(x0), ty = fy - Float(y0)
        tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
        let a = hashf(x0, y0, 0, seed), b = hashf(x0 + 1, y0, 0, seed)
        let c = hashf(x0, y0 + 1, 0, seed), d = hashf(x0 + 1, y0 + 1, 0, seed)
        let top = a + (b - a) * tx, bottom = c + (d - c) * tx
        return top + (bottom - top) * ty
    }

    // MARK: Shading

    static let lightDir: V3 = simd_normalize(V3(-0.55, -0.7, 0.75))      // from the upper left, toward the viewer

    // The studio a polished surface reflects (y down: ry < 0 looks up): bright sky, a dark horizon line just above the
    // middle, mid ground. This is what makes steel, gold and copper read as metal rather than paint.
    static func env(_ ry: Float) -> Float {
        let hor: Float = 1 - expf(-((ry + 0.08) * (ry + 0.08)) / 0.012)
        let v: Float = ry < -0.08 ? 0.55 + 0.45 * powf(min(1, -ry), 0.6) : 0.42 + 0.18 * max(0, ry)
        return v * (1 - 0.55 * hor)
    }

    // nrm: the surface normal (y down); p: icon position; axisT: position along the part's axis (wood grain); hn: the
    // part's normalised height (raised parts read a touch nearer).
    static func shade(_ m: Mat, _ nrm: V3, _ p: V2, _ axisT: Float, _ hn: Float) -> V3 {
        let ndl = max(0, simd_dot(nrm, lightDir))
        let lam: Float = min(1.2, ndl * 0.85 + 0.15 + 0.12 * hn)
        let refl: V3 = nrm * (2 * simd_dot(nrm, lightDir)) - lightDir
        let viewR: V3 = nrm * (2 * nrm.z) - V3(0, 0, 1)
        var col: V3 = m.dark + (m.base - m.dark) * min(lam, 1)
        col += (m.light - m.base) * (max(0, lam - 1) * 2)
        switch m.kind {
        case .metal, .copper, .dusk:
            let e = env(viewR.y)
            let reflCol: V3 = m.dark + (m.light - m.dark) * e
            col = col * 0.35 + reflCol * 0.65
            let spec = powf(max(0, refl.z), m.kind == .dusk ? 30 : 40)
            col += (V3(1, 1, 1) - col) * (spec * 0.9)
            if m.kind == .copper {
                let pat: Float = vnoise(p.x, p.y, 7, 11) * 0.7 + vnoise(p.x, p.y, 23, 12) * 0.3
                let k: Float = simd_clamp((pat - 0.66) * 6, 0, 1) * 0.75                // verdigris patches
                col = col * (1 - k) + V3(0.33, 0.7, 0.6) * ((0.6 + 0.4 * lam) * k)
            }
            if m.kind == .dusk {
                // Duskium: a violet sheen along the lit rims.
                let rim = simd_clamp(1 - nrm.z, 0, 1) * max(0, -nrm.x - nrm.y)
                col += V3(0.5, 0.28, 0.8) * (rim * 1.1)
            }
        case .gem:
            // Crystal: flat facets (quantised normal angle plus a cell field), each its own brightness, and sparkles.
            let cell = floorf(vnoise(p.x, p.y, 9, 31) * 6) / 6
            let q = (atan2f(nrm.y, nrm.x) / (.pi / 3)).rounded()
            var facet: Float = 0.5 + 0.35 * cosf(q * .pi / 3 + 2.2) + (cell - 0.5) * 0.35
            if simd_length(V2(nrm.x, nrm.y)) < 0.2 { facet = 0.72 + (cell - 0.5) * 0.4 }
            col = m.dark + (m.light - m.dark) * simd_clamp(facet * (0.6 + 0.5 * lam), 0, 1)
            let spec = powf(max(0, refl.z), 30)
            col += (V3(1, 1, 1) - col) * (spec * 0.9)
            if vnoise(p.x, p.y, 48, 33) > 0.93 { col += (V3(1, 1, 1) - col) * 0.7 }
        case .wood:
            let g = 0.5 + 0.5 * sinf(axisT * 70 + vnoise(p.x, p.y, 8, 3) * 7)
            col *= 0.84 + 0.22 * g
            col += (m.light - col) * (powf(max(0, refl.z), 12) * 0.35)
        case .stone:
            let nn: Float = vnoise(p.x, p.y, 22, 7) * 0.65 + vnoise(p.x, p.y, 60, 8) * 0.35
            col *= 0.78 + 0.42 * nn
            if vnoise(p.x, p.y, 14, 9) > 0.8 { col *= 0.8 }
        case .leather:
            col *= 0.9 + 0.14 * vnoise(p.x, p.y, 40, 5)
            col += (m.light - col) * (powf(max(0, refl.z), 10) * 0.25)
        case .soft:
            col += (m.light - col) * (powf(max(0, refl.z), 18) * 0.7)
        case .chain:
            let cx = p.x * 13, cy = p.y * 13 + 0.5 * floorf(p.x * 13).truncatingRemainder(dividingBy: 2)
            let rx = cx - floorf(cx) - 0.5, ry = cy - floorf(cy) - 0.5
            let ring = simd_clamp(1 - abs(simd_length(V2(rx, ry)) - 0.3) / 0.13, 0, 1)
            let metal: V3 = m.dark + (m.light - m.dark) * env(viewR.y)
            col = col * 0.45 + metal * 0.55
            let lit: Float = ry < -0.1 ? ring * 0.3 : 0
            col = col * (0.62 + 0.5 * ring) + (m.light - col) * lit
            col *= 0.55 + 0.55 * lam
        }
        return simd_clamp(col, V3(repeating: 0), V3(repeating: 1))
    }

    // Lights and composites a canvas: parts bottom to top (each throwing a soft contact shadow on what is under it,
    // with a thin seam where it overlaps), a dark outline round the union, a soft drop shadow.
    // split: 0 the whole icon; 1 the base layer of an overlay pair (without the parts drawn in "tint"); 2 the overlay
    // layer (only those parts, white-shaded for the per-item tint, no outline).
    static func render(_ cv: Canvas, bevel: Float = 0.03, split: Int = 0) -> [V4] {
        let n = cv.n, nn = n * n
        var tint = [Float](repeating: 0, count: nn)
        let aa: Float = 1 / Float(n)
        let ow: Float = max(1.6 / Float(n), 0.012)
        var col = [V3](repeating: V3(0, 0, 0), count: nn)
        var cov = [Float](repeating: 0, count: nn)
        var uni = [Float](repeating: 9, count: nn)
        var h = [Float](repeating: 0, count: nn), hn = [Float](repeating: 0, count: nn)
        let so = max(1, Int((0.018 * Float(n)).rounded()))
        for part in cv.parts {
            let r = part.r
            for i in 0..<nn {
                let v = simd_clamp(-part.d[i] / bevel, 0, 1)
                let hb = v * v * (3 - 2 * v)
                let w = simd_clamp(-part.d[i] / r, 0, 1)
                let hr: Float = part.chamfer ? w : sqrtf(max(0, 1 - (1 - w) * (1 - w)))
                h[i] = hb * 0.45 * bevel + hr * 0.55 * r
                hn[i] = hb * 0.5 + hr * 0.5
            }
            let m = material(part.mat)
            let isTint = part.mat == "tint"
            let k: Float = Float(n) * 0.5 * 1.6
            var next = col
            for i in 0..<nn {
                let x = i % n, y = i / n
                // Contact shadow from this part (offset down-right) on what is already drawn.
                if x >= so && y >= so {
                    let sd = part.d[(y - so) * n + (x - so)]
                    let sa = simd_clamp(0.5 - sd / (aa * 5), 0, 1) * 0.45 * cov[i]
                    next[i] *= 1 - sa
                }
                let a = simd_clamp(0.5 - part.d[i] / aa, 0, 1)
                if a > 0 {
                    let hl = h[y * n + max(0, x - 1)], hr = h[y * n + min(n - 1, x + 1)]
                    let hu = h[max(0, y - 1) * n + x], hd = h[min(n - 1, y + 1) * n + x]
                    let nrm = simd_normalize(V3(-(hr - hl) * k, -(hd - hu) * k, 1))
                    let c = shade(m, nrm, cv.p(i), part.t[i], hn[i])
                    next[i] = next[i] * (1 - a) + c * a
                }
                let seam = simd_clamp(1 - abs(part.d[i] + 0.6 * aa) / (1.1 * aa), 0, 1) * cov[i] * 0.55
                next[i] *= 1 - seam
                tint[i] = tint[i] * (1 - a) + (isTint ? a : 0)
            }
            col = next
            for i in 0..<nn {
                cov[i] = max(cov[i], simd_clamp(0.5 - part.d[i] / aa, 0, 1))
                uni[i] = min(uni[i], part.d[i])
            }
        }
        let outline = V3(0.05, 0.04, 0.06)
        let sx = Int((0.02 * Float(n)).rounded()), sy = Int((0.03 * Float(n)).rounded())
        var out = [V4](repeating: V4(0, 0, 0, 0), count: nn)
        for i in 0..<nn {
            let x = i % n, y = i / n
            let alpha = simd_clamp(0.5 - (uni[i] - ow) / aa, 0, 1)
            let inner = simd_clamp(0.5 - uni[i] / aa, 0, 1)
            var shadowA: Float = 0
            let ox = x - sx, oy = y - sy
            if ox >= 0 && oy >= 0 {
                shadowA = simd_clamp(0.5 - (uni[oy * n + ox] - ow) / (aa * 3), 0, 1) * 0.35
            }
            if split == 2 {
                out[i] = V4(col[i].x, col[i].y, col[i].z, tint[i] * inner)
            } else if alpha > 0 {
                let rgb: V3 = outline * (1 - inner) + col[i] * inner
                let a = split == 1 ? alpha * (1 - tint[i] * inner) : max(alpha, shadowA * (1 - alpha))
                out[i] = V4(rgb.x, rgb.y, rgb.z, a)
            } else if shadowA > 0 {
                out[i] = V4(0, 0, 0, shadowA)
            }
        }
        return out
    }

    // MARK: Vector designs

    static func vector(_ kind: String, _ mat: String, _ n: Int) -> [V4] {
        let cv = Canvas(n)
        if toolKinds.contains(kind) { tool(cv, kind, mat) } else { armor(cv, kind, mat) }
        return render(cv)
    }

    static func handle(_ cv: Canvas, _ a: V2, _ b: V2, _ r0: Float = 0.04, _ mat: String = "handle") {
        let r = r0 * 1.2                                            // (critic: handles were 2-3 px wide on a TV)
        let (d, t) = cv.capsule(a, b, r)
        cv.add(d, t, mat, r: r)
    }

    // A leather-wrapped grip: k bands across the a -> b handle.
    static func wraps(_ cv: Canvas, _ a: V2, _ b: V2, _ r: Float, _ k: Int, _ mat: String = "grip") {
        let dr = simd_normalize(b - a), nr = V2(-dr.y, dr.x), ln = simd_length(b - a)
        for i in 0..<k {
            let c: V2 = a + dr * (ln * (Float(i) + 0.5) / Float(k))
            let s: V2 = dr * (ln / Float(k) * 0.18)
            let (d, t) = cv.capsule(c - nr * (r * 0.9) - s, c + nr * (r * 0.9) + s, r * 0.62)
            cv.add(d, t, mat, r: r * 0.6)
        }
    }

    static func tool(_ cv: Canvas, _ kind: String, _ head: String) {
        let accent = head == "diamond" || head == "netherite" ? "golden" : (head == "wood" ? "handle" : head)
        let edgeMat = head == "wood" || head == "stone" ? "iron" : head
        let up = V2(0.707, -0.707), rt = V2(0.707, 0.707)          // along the handle (toward the head), across it
        switch kind {
        case "sword":
            let tip = V2(0.9, 0.1), g0 = V2(0.36, 0.64)
            let dir = simd_normalize(tip - g0), len = simd_length(tip - g0)
            let nrm = V2(-dir.y, dir.x)
            let w: Float = 0.072
            let blade: [V2] = [g0 + nrm * w, g0 + dir * (len * 0.74) + nrm * (w * 0.92), tip, g0 + dir * (len * 0.74) - nrm * (w * 0.92), g0 - nrm * w]
            let t = cv.axis(g0, tip)
            handle(cv, V2(0.15, 0.85), V2(0.37, 0.63), 0.036, "grip")
            wraps(cv, V2(0.16, 0.84), V2(0.34, 0.66), 0.036, 3)
            cv.add(cv.circle(V2(0.12, 0.88), 0.052), t, accent, r: 0.05)
            cv.add(tierShape(cv, cv.poly(blade), head), t, head, r: 0.09, chamfer: true)
            guardFor(cv, head, accent, g0, dir, nrm)
        case "pickaxe":
            let top = V2(0.66, 0.34)
            handle(cv, V2(0.12, 0.9), top + up * 0.02, 0.038)
            let root: V2 = top + up * 0.02
            let c1: V2 = top - rt * 0.2 + up * 0.1, c2: V2 = top + rt * 0.2 + up * 0.1
            let e1: V2 = top - rt * 0.42 - up * 0.06, e2: V2 = top + rt * 0.42 - up * 0.06
            let d = Canvas.union(cv.poly(band(root, c1, e1, 0.16, 0.03, 16)), cv.poly(band(root, c2, e2, 0.16, 0.03, 16)))
            let t = cv.axis(e1, e2)
            cv.add(tierShape(cv, d, head), t, head, r: 0.06, chamfer: true)
            let (cd, ct) = cv.capsule(root - rt * 0.05, root + rt * 0.05, 0.06)
            cv.add(cd, ct, accent, r: 0.06)
            adorn(cv, head, root, up, rt)
        case "axe":
            let top = V2(0.62, 0.3)
            handle(cv, V2(0.16, 0.9), top + up * 0.06, 0.04)
            let edge = bez(V2(0.70, 0.02), V2(1.0, 0.16), V2(0.84, 0.56), 12)
            let pts: [V2] = [V2(0.52, 0.24), V2(0.6, 0.16)] + edge + [V2(0.7, 0.44), V2(0.6, 0.38)]
            let d = tierShape(cv, cv.poly(pts), head)
            let t = cv.axis(V2(0.55, 0.3), V2(0.95, 0.3))
            cv.add(d, t, head, r: 0.05, chamfer: true)
            let inner = bez(V2(0.73, 0.08), V2(0.93, 0.19), V2(0.81, 0.48), 12)
            let strip = cv.poly(edge + inner.reversed())
            cv.add(Canvas.intersect(strip, Canvas.offset(d, 0.004)), t, edgeMat, r: 0.03, chamfer: true)     // the sharpened edge
            // The butt behind the handle and the eye ring.
            cv.add(cv.poly([V2(0.44, 0.22), V2(0.52, 0.14), V2(0.6, 0.22), V2(0.52, 0.3)]), t, head, r: 0.04)
            cv.add(cv.circle(V2(0.565, 0.255), 0.05), t, accent, r: 0.05)
            adorn(cv, head, V2(0.565, 0.255), up, rt)
        case "shovel":
            handle(cv, V2(0.13, 0.9), V2(0.62, 0.42), 0.036)
            handle(cv, V2(0.07, 0.86), V2(0.19, 0.97), 0.032)
            let c = V2(0.72, 0.29)
            var pts: [V2] = [c - up * 0.13 + rt * 0.12]
            pts += bez(c + rt * 0.16, c + up * 0.2 + rt * 0.15, c + up * 0.28, 7)
            pts += bez(c + up * 0.28, c + up * 0.2 - rt * 0.15, c - rt * 0.16, 7)
            pts.append(c - up * 0.13 - rt * 0.12)
            let bd = tierShape(cv, cv.poly(pts), head)
            let t = cv.axis(V2(0.6, 0.4), V2(0.9, 0.1))
            cv.add(bd, t, head, r: 0.08)
            cv.add(Canvas.intersect(cv.capsule(c - up * 0.12, c + up * 0.14, 0.012).0, Canvas.offset(bd, 0.02)), t, head, r: 0.012)
            let (cd, ct) = cv.capsule(c - up * 0.17, c - up * 0.1, 0.045)
            cv.add(cd, ct, accent, r: 0.045)
            adorn(cv, head, c - up * 0.135, up, rt)
        case "hoe":
            let top = V2(0.68, 0.26)
            handle(cv, V2(0.14, 0.9), top, 0.036)
            let (bd, bt) = cv.capsule(top + V2(0.02, -0.01), V2(0.42, 0.14), 0.04)
            cv.add(bd, bt, head, r: 0.04)
            let blade = tierShape(cv, cv.poly([V2(0.27, 0.06), V2(0.48, 0.09), V2(0.46, 0.25), V2(0.32, 0.52), V2(0.16, 0.46), V2(0.25, 0.22)]), head)
            cv.add(blade, cv.axis(V2(0.38, 0.08), V2(0.26, 0.45)), head, r: 0.06, chamfer: true)
            cv.add(Canvas.intersect(cv.capsule(V2(0.16, 0.46), V2(0.32, 0.52), 0.035).0, Canvas.offset(blade, 0.004)), bt, edgeMat, r: 0.02, chamfer: true)
            cv.add(cv.circle(top, 0.05), bt, accent, r: 0.05)
            adorn(cv, head, top, up, rt)
        default:                                                            // spear: a long leaf head with lugs
            let tip = V2(0.95, 0.05)
            handle(cv, V2(0.07, 0.95), V2(0.68, 0.32), 0.03)
            let b0 = V2(0.6, 0.4)
            let s1 = bez(b0, b0 + up * 0.1 + rt * 0.16, tip, 10)
            let s2 = bez(tip, b0 + up * 0.1 - rt * 0.16, b0, 10)
            cv.add(tierShape(cv, cv.poly(s1 + Array(s2[1..<(s2.count - 1)])), head), cv.axis(b0, tip), head, r: 0.06, chamfer: true)
            let lug = cv.capsule(b0 - rt * 0.07, b0 + rt * 0.07, 0.022)
            cv.add(lug.0, lug.1, accent, r: 0.02)
            wraps(cv, b0 - up * 0.14, b0 - up * 0.02, 0.032, 3)
        }
    }

    // Tier silhouettes: stone heads knapped (a rough, chipped outline); the others clean.
    static func tierShape(_ cv: Canvas, _ d: [Float], _ head: String) -> [Float] {
        guard head == "stone" else { return d }
        return (0..<d.count).map { i in
            let p = cv.p(i)
            return d[i] + (vnoise(p.x, p.y, 13, 5) - 0.5) * 0.024
        }
    }

    // Tier details at a head's socket c: stone lashed on with cord, gold set with a ruby, copper riveted, duskium spiked.
    static func adorn(_ cv: Canvas, _ head: String, _ c: V2, _ up: V2, _ rt: V2) {
        let zero = [Float](repeating: 0, count: cv.n * cv.n)
        switch head {
        case "stone":
            for o: Float in [-0.022, 0.022] {
                let a: V2 = c - rt * 0.07 + up * (o - 0.03), b: V2 = c + rt * 0.07 + up * (o + 0.03)
                cv.add(cv.capsule(a, b, 0.017).0, zero, M("leather", 0xA88A5A), r: 0.017)
            }
        case "golden":
            cv.add(cv.circle(c, 0.032), zero, M("gem", 0xE0303A), r: 0.03)
        case "copper":
            for o: Float in [-0.045, 0.045] { cv.add(cv.circle(c + rt * o, 0.016), zero, "iron", r: 0.016) }
        case "netherite":
            let tip: V2 = c - up * 0.02 - rt * 0.17
            cv.add(cv.poly([c - rt * 0.05 + up * 0.03, tip, c - rt * 0.05 - up * 0.05]), zero, head, r: 0.03, chamfer: true)
        default:
            break
        }
    }

    // A sword's crossguard, shaped by tier (dr along the blade, nr across it).
    static func guardFor(_ cv: Canvas, _ head: String, _ accent: String, _ g0: V2, _ dr: V2, _ nr: V2) {
        let zero = [Float](repeating: 0, count: cv.n * cv.n)
        switch head {
        case "wood":
            let (d, t) = cv.capsule(g0 - nr * 0.11, g0 + nr * 0.11, 0.032)
            cv.add(d, t, "handle", r: 0.03)
        case "stone":
            let d = cv.poly([g0 - nr * 0.14 - dr * 0.04, g0 + nr * 0.14 - dr * 0.04, g0 + nr * 0.14 + dr * 0.035, g0 - nr * 0.14 + dr * 0.035])
            cv.add(tierShape(cv, d, "stone"), zero, "stone", r: 0.04, chamfer: true)
            adorn(cv, "stone", g0 - dr * 0.08, dr, nr)
        case "golden":
            for sg: Float in [-1, 1] {
                cv.add(cv.poly(band(g0, g0 + nr * (0.12 * sg), g0 + nr * (0.17 * sg) + dr * 0.08, 0.06, 0.025, 10)), zero, "golden", r: 0.03)
            }
            cv.add(cv.circle(g0, 0.045), zero, "golden", r: 0.04)
            cv.add(cv.circle(g0, 0.026), zero, M("gem", 0xE0303A), r: 0.025)
        case "diamond":
            cv.add(cv.poly([g0 - nr * 0.18, g0 - dr * 0.05, g0 + nr * 0.18, g0 + dr * 0.06]), zero, "golden", r: 0.04, chamfer: true)
            cv.add(cv.poly([g0 - nr * 0.05, g0 - dr * 0.025, g0 + nr * 0.05, g0 + dr * 0.03]), zero, "diamond", r: 0.02, chamfer: true)
        case "netherite":
            for sg: Float in [-1, 1] {
                cv.add(cv.poly([g0 - dr * 0.035, g0 + nr * (0.2 * sg) + dr * 0.07, g0 + dr * 0.035]), zero, "netherite", r: 0.03, chamfer: true)
            }
            cv.add(cv.circle(g0, 0.04), zero, "golden", r: 0.04)
        case "copper":
            cv.add(cv.circle(g0, 0.1), zero, "copper", r: 0.05)
            cv.add(cv.circle(g0, 0.03), zero, "iron", r: 0.03)
        default:
            let bar = cv.capsule(g0 - nr * 0.15, g0 + nr * 0.15, 0.03), gt = bar.1
            let gd = Canvas.union(bar.0, Canvas.union(cv.circle(g0 - nr * 0.15, 0.042), cv.circle(g0 + nr * 0.15, 0.042)))
            cv.add(gd, gt, accent, r: 0.04)
            cv.add(cv.circle(g0, 0.04), gt, accent, r: 0.04)
        }
    }

    static func armor(_ cv: Canvas, _ kind: String, _ m: String) {
        let ys = cv.axis(V2(0.5, 0), V2(0.5, 1)), xs = cv.axis(V2(0, 0.5), V2(1, 0.5))
        let soft = m == "leather" || m == "turtle"
        let trim = m == "diamond" || m == "netherite" ? "golden" : m
        switch kind {
        case "helmet":
            // A dome cut flat at the brim, cheek guards, a visor slot, nasal and crest (metal) or a stitched seam.
            var d = Canvas.intersect(cv.circle(V2(0.5, 0.58), 0.37), cv.below(0.64))
            let cheeks = Canvas.union(cv.poly([V2(0.13, 0.56), V2(0.31, 0.56), V2(0.31, 0.88), V2(0.19, 0.86)]),
                                      cv.poly([V2(0.69, 0.56), V2(0.87, 0.56), V2(0.81, 0.86), V2(0.69, 0.88)]))
            d = Canvas.union(d, cheeks)
            if !soft {
                let visor = cv.poly([V2(0.33, 0.58), V2(0.67, 0.58), V2(0.65, 0.66), V2(0.35, 0.66)])
                d = Canvas.intersect(d, visor.map { -$0 })
            }
            cv.add(d, ys, m, r: 0.3)
            cv.add(Canvas.intersect(cv.capsule(V2(0.15, 0.56), V2(0.85, 0.56), 0.032).0, d), xs, trim, r: 0.03)
            if !soft {
                cv.add(cv.capsule(V2(0.5, 0.2), V2(0.5, 0.52), 0.026).0, ys, trim, r: 0.026)
                cv.add(cv.capsule(V2(0.5, 0.56), V2(0.5, 0.74), 0.03).0, ys, m, r: 0.03)
                for x: Float in [0.22, 0.78] { cv.add(cv.circle(V2(x, 0.7), 0.022), ys, trim, r: 0.02) }
            } else if m == "turtle" {
                for c in [V2(0.5, 0.36), V2(0.34, 0.44), V2(0.66, 0.44)] {
                    let hexp: [V2] = (0..<6).map { (k: Int) -> V2 in c + V2(cosf(Float(k) * .pi / 3), sinf(Float(k) * .pi / 3)) * 0.09 }
                    cv.add(Canvas.intersect(ring(cv.poly(hexp), 0.012), Canvas.offset(d, 0.02)), ys, M("leather", 0x2A5A22), r: 0.012)
                }
            } else {
                cv.add(Canvas.intersect(cv.capsule(V2(0.2, 0.4), V2(0.8, 0.4), 0.006).0, Canvas.offset(d, 0.03)), xs, "grip", r: 0.006)
                cv.add(cv.capsule(V2(0.1, 0.58), V2(0.9, 0.58), 0.035).0, xs, M("leather", 0x6A3E20), r: 0.035)
                cv.add(cv.capsule(V2(0.24, 0.6), V2(0.4, 0.9), 0.016).0, ys, "grip", r: 0.016)
                cv.add(cv.circle(V2(0.4, 0.9), 0.025), ys, "iron", r: 0.02)
            }
        case "chestplate":
            let torso = cv.poly([V2(0.26, 0.2), V2(0.4, 0.16), V2(0.5, 0.28), V2(0.6, 0.16), V2(0.74, 0.2), V2(0.76, 0.86), V2(0.5, 0.92), V2(0.24, 0.86)])
            if soft { cv.add(torso, ys, m, r: 0.3) } else { cv.add(torso, ys, m, r: 0.12, chamfer: true) }
            cv.add(cv.poly(band(V2(0.1, 0.44), V2(0.11, 0.16), V2(0.36, 0.16), 0.14, 0.11, 10)), xs, m, r: 0.07)
            cv.add(cv.poly(band(V2(0.9, 0.44), V2(0.89, 0.16), V2(0.64, 0.16), 0.14, 0.11, 10)), xs, m, r: 0.07)
            cv.add(Canvas.intersect(cv.poly(band(V2(0.36, 0.17), V2(0.5, 0.4), V2(0.64, 0.17), 0.04, 0.04, 12)), torso), xs, trim, r: 0.03)
            if !soft { cv.add(Canvas.intersect(cv.capsule(V2(0.5, 0.36), V2(0.5, 0.86), 0.012).0, Canvas.offset(torso, 0.03)), ys, m, r: 0.012) }
            for yy: Float in [0.62, 0.76] {
                cv.add(Canvas.intersect(cv.capsule(V2(0.24, yy), V2(0.76, yy), 0.016).0, torso), xs, soft ? "grip" : trim, r: 0.016)
            }
        case "leggings":
            let d = cv.poly([V2(0.22, 0.14), V2(0.78, 0.14), V2(0.82, 0.9), V2(0.6, 0.9), V2(0.5, 0.42), V2(0.4, 0.9), V2(0.18, 0.9)])
            if soft { cv.add(d, ys, m, r: 0.2) } else { cv.add(d, ys, m, r: 0.1, chamfer: true) }
            cv.add(Canvas.intersect(cv.capsule(V2(0.2, 0.2), V2(0.8, 0.2), 0.045).0, d), xs, soft ? "grip" : trim, r: 0.04)
            if !soft {
                for c in [V2(0.3, 0.6), V2(0.7, 0.6)] { cv.add(Canvas.intersect(ellipse(cv, c, 0.08, 0.07), Canvas.offset(d, 0.02)), ys, trim, r: 0.06) }
            }
        default:                                                            // boots: a pair, the near one lower right
            for o in [V2(0, 0), V2(0.3, 0.1)] {
                let shaft = cv.poly([V2(0.14, 0.18) + o, V2(0.38, 0.18) + o, V2(0.38, 0.56) + o, V2(0.14, 0.62) + o])
                let foot = Canvas.union(cv.capsule(V2(0.2, 0.7) + o, V2(0.5, 0.7) + o, 0.1).0,
                                        cv.poly([V2(0.14, 0.5) + o, V2(0.38, 0.5) + o, V2(0.4, 0.78) + o, V2(0.12, 0.8) + o]))
                let d = Canvas.union(shaft, Canvas.intersect(foot, cv.below(0.8 + o.y)))
                cv.add(d, ys, m, r: 0.12)
                cv.add(Canvas.intersect(cv.capsule(V2(0.1, 0.78) + o, V2(0.62, 0.78) + o, 0.03).0, Canvas.offset(d, 0.01)), xs, soft ? "grip" : trim, r: 0.02)
                cv.add(Canvas.intersect(cv.capsule(V2(0.12, 0.22) + o, V2(0.4, 0.22) + o, 0.04).0, Canvas.offset(d, 0.015)), xs, soft ? "grip" : trim, r: 0.035)
            }
        }
    }

    // MARK: Pixel art upscale

    @inline(__always) static func same(_ a: V4, _ b: V4) -> Bool {
        if a.w < 0.5 && b.w < 0.5 { return true }
        if (a.w < 0.5) != (b.w < 0.5) { return false }
        let d = simd_abs(a - b)
        return d.x + d.y + d.z < 0.09
    }

    // Scale2x (EPX): doubles the art, rounding stair-stepped diagonals while keeping every colour.
    static func scale2x(_ s: [V4], _ n: Int) -> [V4] {
        var o = [V4](repeating: V4(0, 0, 0, 0), count: 4 * n * n)
        let m = 2 * n
        for y in 0..<n { for x in 0..<n {
            let p = s[y * n + x]
            let a = y > 0 ? s[(y - 1) * n + x] : V4(0, 0, 0, 0)
            let b = x < n - 1 ? s[y * n + x + 1] : V4(0, 0, 0, 0)
            let c = x > 0 ? s[y * n + x - 1] : V4(0, 0, 0, 0)
            let d = y < n - 1 ? s[(y + 1) * n + x] : V4(0, 0, 0, 0)
            o[(2 * y) * m + 2 * x] = same(c, a) && !same(c, d) && !same(a, b) ? a : p
            o[(2 * y) * m + 2 * x + 1] = same(a, b) && !same(a, c) && !same(b, d) ? b : p
            o[(2 * y + 1) * m + 2 * x] = same(d, c) && !same(d, b) && !same(c, a) ? c : p
            o[(2 * y + 1) * m + 2 * x + 1] = same(b, d) && !same(b, a) && !same(d, c) ? d : p
        } }
        return o
    }

    // Two-pass chamfer distance (pixels) from every pixel to the nearest pixel outside `inside`.
    static func chamfer(_ inside: [Bool], _ n: Int) -> [Float] {
        var d = inside.map { $0 ? Float(1e4) : 0 }
        let a: Float = 1, b: Float = 1.4142
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            var v = d[i]
            if x > 0 { v = min(v, d[i - 1] + a) }
            if y > 0 {
                v = min(v, d[i - n] + a)
                if x > 0 { v = min(v, d[i - n - 1] + b) }
                if x < n - 1 { v = min(v, d[i - n + 1] + b) }
            }
            d[i] = v
        } }
        for y in stride(from: n - 1, through: 0, by: -1) { for x in stride(from: n - 1, through: 0, by: -1) {
            let i = y * n + x
            var v = d[i]
            if x < n - 1 { v = min(v, d[i + 1] + a) }
            if y < n - 1 {
                v = min(v, d[i + n] + a)
                if x > 0 { v = min(v, d[i + n - 1] + b) }
                if x < n - 1 { v = min(v, d[i + n + 1] + b) }
            }
            d[i] = v
        } }
        return d
    }

    // Pixel art without a vector design: Scale2x up to the layer size, the big pixel blocks softened inside the shape,
    // then the same treatment as the vector icons (a signed distance from the silhouette gives a bevel and a rounded
    // body lit from the upper left, a dark outline and a soft drop shadow).
    // Tinted layers drawn over an item's base icon (potion liquid, spawn egg shells...): lit, but no outline or shadow.
    static let overlayNames: Set<String> = ["item_potion_liquid", "item_tipped_arrow_head", "item_spawn_egg_shell", "item_harness_band",
                                            "item_explorer_mark"]

    static func upscaled(_ src: [V4], _ n: Int, outlined: Bool = true) -> [V4] {
        var img = src
        var s = TextureGen.S
        while s * 2 <= n { img = scale2x(img, s); s *= 2 }
        if s != n {
            var o = [V4](repeating: V4(0, 0, 0, 0), count: n * n)
            for y in 0..<n { for x in 0..<n { o[y * n + x] = img[(y * s / n) * s + x * s / n] } }
            img = o; s = n
        }
        let nn = n * n
        let inside = img.map { $0.w >= 0.5 }
        // Masked box blur, mixed in half.
        let rr = max(1, n / 48)
        var soft = img
        for y in 0..<n { for x in 0..<n where inside[y * n + x] {
            var acc = V3(0, 0, 0), w: Float = 0
            for dy in -rr...rr { for dx in -rr...rr {
                let xx = x + dx, yy = y + dy
                if xx < 0 || yy < 0 || xx >= n || yy >= n || !inside[yy * n + xx] { continue }
                let c = img[yy * n + xx]
                acc += V3(c.x, c.y, c.z); w += 1
            } }
            let c = img[y * n + x]
            let m: V3 = V3(c.x, c.y, c.z) * 0.5 + acc * (0.5 / w)
            soft[y * n + x] = V4(m.x, m.y, m.z, c.w)
        } }
        let din = chamfer(inside, n), dout = chamfer(inside.map { !$0 }, n)
        var sd = [Float](repeating: 0, count: nn)
        for i in 0..<nn { sd[i] = (inside[i] ? -(din[i] - 0.5) : dout[i] - 0.5) / Float(n) }
        let bevel: Float = 0.03, r: Float = 0.07
        var h = [Float](repeating: 0, count: nn)
        for i in 0..<nn {
            let v = simd_clamp(-sd[i] / bevel, 0, 1)
            let w = simd_clamp(-sd[i] / r, 0, 1)
            h[i] = v * v * (3 - 2 * v) * 0.45 * bevel + sqrtf(max(0, 1 - (1 - w) * (1 - w))) * 0.55 * r
        }
        let k: Float = Float(n) * 0.5 * 1.6
        let flat: Float = lightDir.z * 0.85 + 0.15
        let aa: Float = 1 / Float(n), ow: Float = max(1.6 / Float(n), 0.012)
        let outline = V3(0.05, 0.04, 0.06)
        let sx = Int((0.02 * Float(n)).rounded()), sy = Int((0.03 * Float(n)).rounded())
        var out = [V4](repeating: V4(0, 0, 0, 0), count: nn)
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let alpha = simd_clamp(0.5 - (sd[i] - (outlined ? ow : 0)) / aa, 0, 1)
            var shadowA: Float = 0
            if outlined && x >= sx && y >= sy { shadowA = simd_clamp(0.5 - (sd[(y - sy) * n + x - sx] - ow) / (aa * 3), 0, 1) * 0.35 }
            if alpha <= 0 {
                if shadowA > 0 { out[i] = V4(0, 0, 0, shadowA) }
                continue
            }
            let hl = h[y * n + max(0, x - 1)], hr = h[y * n + min(n - 1, x + 1)]
            let hu = h[max(0, y - 1) * n + x], hd = h[min(n - 1, y + 1) * n + x]
            let nrm = simd_normalize(V3(-(hr - hl) * k, -(hd - hu) * k, 1))
            let ndl = max(0, simd_dot(nrm, lightDir))
            let f = simd_clamp((ndl * 0.85 + 0.15) / flat, 0.5, 1.35)
            let refl: V3 = nrm * (2 * simd_dot(nrm, lightDir)) - lightDir
            let spec = powf(max(0, refl.z), 18) * 0.3
            let c = soft[i]
            let lit = simd_clamp(V3(c.x, c.y, c.z) * f + V3(repeating: spec), V3(repeating: 0), V3(repeating: 1))
            let inner = outlined ? simd_clamp(0.5 - sd[i] / aa, 0, 1) : 1
            let rgb: V3 = outline * (1 - inner) + lit * inner
            out[i] = V4(rgb.x, rgb.y, rgb.z, max(alpha, shadowA * (1 - alpha)))
        } }
        return out
    }
}
