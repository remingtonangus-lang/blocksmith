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

    enum Kind { case metal, gem, wood, stone, leather, chain, copper, dusk }
    struct Mat { var kind: Kind; var base: V3; var dark: V3; var light: V3 }

    static func hex(_ h: UInt32) -> V3 { V3(Float((h >> 16) & 255), Float((h >> 8) & 255), Float(h & 255)) / 255 }

    static let mats: [String: Mat] = [
        "wood": Mat(kind: .wood, base: hex(0xB98E58), dark: hex(0x6A4A26), light: hex(0xE6C690)),
        "handle": Mat(kind: .wood, base: hex(0x7A5530), dark: hex(0x3E2914), light: hex(0xB08250)),
        "stone": Mat(kind: .stone, base: hex(0x8C8C8E), dark: hex(0x4C4C50), light: hex(0xC4C4C6)),
        "iron": Mat(kind: .metal, base: hex(0xC9CED6), dark: hex(0x5E646E), light: hex(0xFFFFFF)),
        "golden": Mat(kind: .metal, base: hex(0xF0C33C), dark: hex(0x8A5A10), light: hex(0xFFF4B0)),
        "diamond": Mat(kind: .gem, base: hex(0x46D8E0), dark: hex(0x146A7A), light: hex(0xD8FFFF)),
        "netherite": Mat(kind: .dusk, base: hex(0x4A4450), dark: hex(0x18151C), light: hex(0xB59AD8)),
        "copper": Mat(kind: .copper, base: hex(0xDA7240), dark: hex(0x6E2E12), light: hex(0xFFC29A)),
        "leather": Mat(kind: .leather, base: hex(0x8E5430), dark: hex(0x4A2812), light: hex(0xC08458)),
        "grip": Mat(kind: .leather, base: hex(0x5A3A26), dark: hex(0x2A1A10), light: hex(0x8A6040)),
        "chainmail": Mat(kind: .chain, base: hex(0xA0A4AA), dark: hex(0x4A4C52), light: hex(0xE8EAEE)),
        "turtle": Mat(kind: .leather, base: hex(0x4FA046), dark: hex(0x1F4A1C), light: hex(0x9AD88A)),
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
        if src.allSatisfy({ $0.w < 0.5 }) { return nil }
        return { n, _ in var img = HDTex.Img(n); img.px = ItemHD.upscaled(src, n); return img }
    }

    // MARK: Signed distances (icon space 0...1, y down)

    final class Canvas {
        let n: Int
        var parts: [(d: [Float], t: [Float], mat: String)] = []
        init(_ n: Int) { self.n = n }
        @inline(__always) func p(_ i: Int) -> V2 { V2((Float(i % n) + 0.5) / Float(n), (Float(i / n) + 0.5) / Float(n)) }

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
        func add(_ d: [Float], _ t: [Float], _ mat: String) { parts.append((d, t, mat)) }
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

    static func shade(_ m: Mat, _ nrm: V3, _ p: V2, _ axisT: Float) -> V3 {
        let ndl = max(0, simd_dot(nrm, lightDir))
        let t = min(1, ndl * 1.25)
        var col: V3 = m.dark + (m.base - m.dark) * t
        let refl: V3 = nrm * (2 * simd_dot(nrm, lightDir)) - lightDir
        switch m.kind {
        case .metal, .copper, .dusk:
            let spec = powf(max(0, refl.z), m.kind == .copper ? 20 : 24)
            let bandK = max(0, 1 - abs(nrm.y * 3 + 0.4)) * 0.25
            let mixK: Float = spec * 0.9 + bandK
            col += (m.light - col) * mixK
            if m.kind == .copper && vnoise(p.x, p.y, 18, 11) > 0.78 {
                col = col * 0.5 + V3(0.25, 0.62, 0.55) * 0.5             // patina flecks
            }
            if m.kind == .dusk {
                // Duskium: a violet sheen along the lit rims.
                let rim = max(0, 1 - nrm.z) * max(0, -nrm.x - nrm.y)
                col += V3(0.45, 0.25, 0.7) * (rim * 0.9)
            }
        case .gem:
            let ang = atan2f(nrm.y, nrm.x)
            let q = (ang / (.pi / 3)).rounded()
            var facet = 0.55 + 0.45 * cosf(q * .pi / 3 + 2.2)
            if simd_length(V2(nrm.x, nrm.y)) < 0.15 { facet = 0.85 }
            col = m.dark + (m.light - m.dark) * (facet * 0.9)
            if vnoise(p.x, p.y, 40, 31) > 0.9 { col += (V3(1, 1, 1) - col) * 0.6 }     // sparkle
        case .wood:
            let g = 0.5 + 0.5 * sinf(axisT * 70 + vnoise(p.x, p.y, 8, 3) * 7)
            col *= 0.82 + 0.26 * g
            col += (m.light - col) * (max(0, ndl - 0.85) * 2)
        case .stone:
            col *= 0.8 + 0.4 * vnoise(p.x, p.y, 24, 7)
            col += (m.light - col) * (max(0, ndl - 0.8) * 2.5)
        case .leather:
            col *= 0.92 + 0.12 * vnoise(p.x, p.y, 32, 5)
            col += (m.light - col) * (max(0, ndl - 0.85) * 2)
        case .chain:
            let cx = p.x * 22, cy = p.y * 22 + 0.5 * floorf(p.x * 22).truncatingRemainder(dividingBy: 2)
            let rx = cx - floorf(cx) - 0.5, ry = cy - floorf(cy) - 0.5
            let ring = abs(simd_length(V2(rx, ry)) - 0.3) < 0.12
            col *= ring ? 1.15 : 0.45
        }
        return simd_clamp(col, V3(repeating: 0), V3(repeating: 1))
    }

    // Lights and composites a canvas: parts bottom to top, a dark outline round the union, a soft drop shadow.
    static func render(_ cv: Canvas, bevel: Float = 0.035) -> [V4] {
        let n = cv.n
        let aa: Float = 1 / Float(n)
        let ow: Float = max(1.6 / Float(n), 0.012)
        var col = [V3](repeating: V3(0, 0, 0), count: n * n)
        var uni = [Float](repeating: 9, count: n * n)
        var h = [Float](repeating: 0, count: n * n)
        for part in cv.parts {
            for i in 0..<(n * n) {
                let v = simd_clamp(-part.d[i] / bevel, 0, 1)
                h[i] = v * v * (3 - 2 * v)
            }
            let m = mats[part.mat] ?? mats["iron"]!
            for i in 0..<(n * n) {
                uni[i] = min(uni[i], part.d[i])
                let a = simd_clamp(0.5 - part.d[i] / aa, 0, 1)
                if a <= 0 { continue }
                let x = i % n, y = i / n
                let hl = h[y * n + max(0, x - 1)], hr = h[y * n + min(n - 1, x + 1)]
                let hu = h[max(0, y - 1) * n + x], hd = h[min(n - 1, y + 1) * n + x]
                let k: Float = 0.03 * Float(n)
                let nrm = simd_normalize(V3(-(hr - hl) * k, -(hd - hu) * k, 1))
                let c = shade(m, nrm, cv.p(i), part.t[i])
                col[i] = col[i] * (1 - a) + c * a
            }
        }
        let outline = V3(0.06, 0.05, 0.07)
        let sx = Int((0.02 * Float(n)).rounded()), sy = Int((0.03 * Float(n)).rounded())
        var out = [V4](repeating: V4(0, 0, 0, 0), count: n * n)
        for i in 0..<(n * n) {
            let x = i % n, y = i / n
            let alpha = simd_clamp(0.5 - (uni[i] - ow) / aa, 0, 1)
            let inner = simd_clamp(0.5 - uni[i] / aa, 0, 1)
            var shadowA: Float = 0
            let ox = x - sx, oy = y - sy
            if ox >= 0 && oy >= 0 {
                shadowA = simd_clamp(0.5 - (uni[oy * n + ox] - ow) / (aa * 3), 0, 1) * 0.35
            }
            if alpha > 0 {
                let rgb: V3 = outline * (1 - inner) + col[i] * inner
                let a = max(alpha, shadowA * (1 - alpha))
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

    static func handle(_ cv: Canvas, _ a: V2, _ b: V2, _ r: Float = 0.04, _ mat: String = "handle") {
        let (d, t) = cv.capsule(a, b, r)
        cv.add(d, t, mat)
    }

    static func tool(_ cv: Canvas, _ kind: String, _ head: String) {
        let accentForGuard = head == "diamond" || head == "netherite" ? "golden" : (head == "wood" ? "handle" : head)
        let fullerMat = head == "wood" || head == "stone" ? "iron" : head
        switch kind {
        case "sword":
            let tip = V2(0.9, 0.1), g0 = V2(0.355, 0.645)
            let dir = simd_normalize(tip - g0), len = simd_length(tip - g0)
            let nrm = V2(-dir.y, dir.x)
            let w: Float = 0.06
            let blade: [V2] = [g0 + nrm * w, g0 + dir * (len * 0.78) + nrm * (w * 0.9), tip, g0 + dir * (len * 0.78) - nrm * (w * 0.9), g0 - nrm * w]
            let t = cv.axis(g0, tip)
            handle(cv, V2(0.13, 0.87), V2(0.36, 0.64), 0.036, "grip")
            cv.add(cv.circle(V2(0.115, 0.885), 0.05), t, head == "wood" ? "handle" : head)
            let bd = cv.poly(blade)
            cv.add(bd, t, head)
            let fuller = cv.capsule(g0 + dir * 0.04, g0 + dir * (len * 0.7), 0.012).0
            cv.add(Canvas.intersect(fuller, Canvas.offset(bd, 0.02)), t, fullerMat)
            let (gd, gt) = cv.capsule(g0 - nrm * 0.12, g0 + nrm * 0.12, 0.034)
            cv.add(gd, gt, accentForGuard)
        case "pickaxe":
            handle(cv, V2(0.12, 0.9), V2(0.68, 0.34), 0.038)
            let top = V2(0.68, 0.33), perp = V2(0.707, 0.707), up = V2(0.707, -0.707)
            let e1 = top - perp * 0.38, e2 = top + perp * 0.38
            let ctrl = top + up * 0.17
            let thin = cv.poly(band(e1, ctrl, e2, 0.02, 0.02, 20))
            let fat = cv.poly(band(top - perp * 0.24 + up * 0.06, ctrl + up * 0.02, top + perp * 0.24 + up * 0.06, 0.1, 0.1, 16))
            let t = cv.axis(e1, e2)
            cv.add(Canvas.union(thin, fat), t, head)
            cv.add(cv.circle(top + up * 0.04, 0.05), t, head)
        case "axe":
            handle(cv, V2(0.16, 0.9), V2(0.62, 0.28), 0.04)
            let edge = bez(V2(0.70, 0.02), V2(1.0, 0.16), V2(0.84, 0.56), 12)
            let pts: [V2] = [V2(0.52, 0.26), V2(0.58, 0.18)] + edge + [V2(0.70, 0.44), V2(0.62, 0.40)]
            let d = cv.poly(pts)
            let t = cv.axis(V2(0.55, 0.3), V2(0.95, 0.3))
            cv.add(d, t, head)
            let inner = bez(V2(0.72, 0.07), V2(0.94, 0.18), V2(0.80, 0.50), 12)
            let strip = cv.poly(edge + inner.reversed())
            cv.add(Canvas.intersect(strip, Canvas.offset(d, 0.004)), t, fullerMat)     // the sharpened edge
            cv.add(cv.circle(V2(0.58, 0.32), 0.05), t, head)
        case "shovel":
            handle(cv, V2(0.13, 0.9), V2(0.62, 0.42), 0.036)
            handle(cv, V2(0.08, 0.84), V2(0.2, 0.96), 0.03)
            let c = V2(0.72, 0.29), u = V2(0.707, -0.707), nv = V2(0.707, 0.707)
            var pts: [V2] = [c - u * 0.12 + nv * 0.1]
            pts += bez(c + u * 0.02 + nv * 0.12, c + u * 0.16 + nv * 0.1, c + u * 0.22, 6)
            pts += bez(c + u * 0.22, c + u * 0.16 - nv * 0.1, c + u * 0.02 - nv * 0.12, 6)
            pts.append(c - u * 0.12 - nv * 0.1)
            cv.add(cv.poly(pts), cv.axis(V2(0.6, 0.4), V2(0.9, 0.1)), head)
        case "hoe":
            handle(cv, V2(0.14, 0.9), V2(0.64, 0.3), 0.036)
            let pts: [V2] = [V2(0.54, 0.28), V2(0.62, 0.16), V2(0.92, 0.2), V2(0.96, 0.4), V2(0.86, 0.42), V2(0.7, 0.32)]
            cv.add(cv.poly(pts), cv.axis(V2(0.56, 0.26), V2(0.92, 0.3)), head)
        default:                                                            // spear
            handle(cv, V2(0.07, 0.95), V2(0.72, 0.3), 0.03)
            let tip = V2(0.95, 0.05), b0 = V2(0.7, 0.3), u = V2(0.707, -0.707), nv = V2(0.707, 0.707)
            let pts: [V2] = [b0, b0 + u * 0.1 + nv * 0.07, tip, b0 + u * 0.1 - nv * 0.07]
            cv.add(cv.poly(pts), cv.axis(b0, tip), head)
            handle(cv, V2(0.64, 0.36), V2(0.7, 0.3), 0.04, "grip")
        }
    }

    static func armor(_ cv: Canvas, _ kind: String, _ m: String) {
        let ys = cv.axis(V2(0.5, 0), V2(0.5, 1)), xs = cv.axis(V2(0, 0.5), V2(1, 0.5))
        let soft = m == "leather" || m == "turtle"
        switch kind {
        case "helmet":
            // A dome cut flat at the brim, cheek guards, a visor slot (metal) and a crest ridge.
            let below: [Float] = (0..<(cv.n * cv.n)).map { cv.p($0).y - 0.62 }
            var d = Canvas.intersect(cv.circle(V2(0.5, 0.56), 0.36), below)
            let cheeks = Canvas.union(cv.poly([V2(0.14, 0.56), V2(0.3, 0.56), V2(0.3, 0.86), V2(0.2, 0.84)]),
                                      cv.poly([V2(0.7, 0.56), V2(0.86, 0.56), V2(0.8, 0.84), V2(0.7, 0.86)]))
            d = Canvas.union(d, cheeks)
            if !soft {
                let visor = cv.poly([V2(0.32, 0.56), V2(0.68, 0.56), V2(0.66, 0.64), V2(0.34, 0.64)])
                d = Canvas.intersect(d, visor.map { -$0 })
            }
            cv.add(d, ys, m)
            cv.add(Canvas.intersect(cv.capsule(V2(0.17, 0.54), V2(0.83, 0.54), 0.03).0, d), xs, m)
            if !soft { cv.add(cv.capsule(V2(0.5, 0.22), V2(0.5, 0.5), 0.022).0, ys, m) }
        case "chestplate":
            let torso = cv.poly([V2(0.26, 0.2), V2(0.4, 0.16), V2(0.5, 0.28), V2(0.6, 0.16), V2(0.74, 0.2), V2(0.76, 0.86), V2(0.5, 0.92), V2(0.24, 0.86)])
            cv.add(torso, ys, m)
            cv.add(cv.poly(band(V2(0.1, 0.42), V2(0.12, 0.16), V2(0.36, 0.16), 0.13, 0.11, 10)), xs, m)
            cv.add(cv.poly(band(V2(0.9, 0.42), V2(0.88, 0.16), V2(0.64, 0.16), 0.13, 0.11, 10)), xs, m)
            cv.add(Canvas.intersect(cv.capsule(V2(0.5, 0.34), V2(0.5, 0.86), 0.01).0, torso), ys, m)
            for yy: Float in [0.58, 0.72] {
                cv.add(Canvas.intersect(cv.capsule(V2(0.28, yy), V2(0.72, yy), 0.012).0, torso), xs, m)
            }
        case "leggings":
            let d = cv.poly([V2(0.22, 0.12), V2(0.78, 0.12), V2(0.82, 0.9), V2(0.6, 0.9), V2(0.5, 0.4), V2(0.4, 0.9), V2(0.18, 0.9)])
            cv.add(d, ys, m)
            cv.add(Canvas.intersect(cv.capsule(V2(0.22, 0.2), V2(0.78, 0.2), 0.035).0, d), xs, m)
        default:                                                            // boots
            for ox: Float in [0, 0.42] {
                let d = cv.poly([V2(0.1 + ox, 0.3), V2(0.32 + ox, 0.3), V2(0.32 + ox, 0.66), V2(0.5 + ox, 0.72), V2(0.5 + ox, 0.86), V2(0.08 + ox, 0.86)])
                cv.add(d, ys, m)
                cv.add(Canvas.intersect(cv.capsule(V2(0.1 + ox, 0.8), V2(0.5 + ox, 0.8), 0.035).0, d), xs, m)
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

    static func upscaled(_ src: [V4], _ n: Int) -> [V4] {
        var img = src
        var s = TextureGen.S
        while s * 2 <= n { img = scale2x(img, s); s *= 2 }
        if s != n {
            var o = [V4](repeating: V4(0, 0, 0, 0), count: n * n)
            for y in 0..<n { for x in 0..<n { o[y * n + x] = img[(y * s / n) * s + x * s / n] } }
            img = o; s = n
        }
        // Bevel light: a height field from the blurred coverage, lit from the upper left.
        var hgt = img.map { $0.w >= 0.5 ? Float(1) : 0 }
        let r = max(1, n / 32)
        for _ in 0..<2 {
            var tmp = hgt
            for y in 0..<n { for x in 0..<n {
                var acc: Float = 0
                for k in -r...r { acc += hgt[y * n + min(n - 1, max(0, x + k))] }
                tmp[y * n + x] = acc / Float(2 * r + 1)
            } }
            for y in 0..<n { for x in 0..<n {
                var acc: Float = 0
                for k in -r...r { acc += tmp[min(n - 1, max(0, y + k)) * n + x] }
                hgt[y * n + x] = acc / Float(2 * r + 1)
            } }
        }
        var out = [V4](repeating: V4(0, 0, 0, 0), count: n * n)
        let sx = max(1, Int((0.02 * Float(n)).rounded())), sy = max(1, Int((0.03 * Float(n)).rounded()))
        for y in 0..<n { for x in 0..<n {
            let i = y * n + x
            let c = img[i]
            if c.w >= 0.5 {
                let hl = hgt[y * n + max(0, x - 1)], hr = hgt[y * n + min(n - 1, x + 1)]
                let hu = hgt[max(0, y - 1) * n + x], hd = hgt[min(n - 1, y + 1) * n + x]
                let k: Float = Float(n) * 0.06
                let nrm = simd_normalize(V3(-(hr - hl) * k, -(hd - hu) * k, 1))
                let lit = simd_dot(nrm, lightDir) - simd_dot(V3(0, 0, 1), lightDir)
                let f: Float = 1 + lit * 0.9
                out[i] = V4(min(1, c.x * f), min(1, c.y * f), min(1, c.z * f), c.w)
            } else {
                let ox = x - sx, oy = y - sy
                if ox >= 0 && oy >= 0 && img[oy * n + ox].w >= 0.5 { out[i] = V4(0, 0, 0, 0.32) }
            }
        } }
        return out
    }
}
