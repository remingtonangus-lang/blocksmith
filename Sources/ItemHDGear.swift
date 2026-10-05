import Foundation
import simd

// Vector designs for materials, tools, carts and keepsakes by sprite family (see ItemHDFamilies.swift), and the
// overlay pairs (potion bottles + liquid, spawn eggs + shell, tipped arrows + head). Mirrored by tools/itemlab.py.
extension ItemHD {
    static func gear(_ cv: Canvas, _ name: String, _ s: Sprite, _ ys: [Float], _ xs: [Float], _ zero: [Float]) -> Bool {
        let base = s.base, ex = s.extras
        func soft(_ h: UInt32) -> String { M("soft", h) }
        let up = V2(0.707, -0.707), rt = V2(0.707, 0.707)
        switch s.mask {
        case "stick":
            handle(cv, V2(0.2, 0.84), V2(0.8, 0.16), 0.045)
            cv.add(cap(cv, V2(0.48, 0.52), V2(0.62, 0.54), 0.025), zero, "handle", r: 0.025)
        case "rod":
            let (d, t) = cv.capsule(V2(0.22, 0.82), V2(0.78, 0.18), 0.055)
            cv.add(d, t, soft(base), r: 0.055)
            for k in 0..<4 {
                let c: V2 = V2(0.22, 0.82) + V2(0.56, -0.64) * (0.15 + Float(k) * 0.23)
                cv.add(cap(cv, c + V2(-0.07, -0.06), c + V2(0.07, 0.06), 0.022), t, soft(darker(base, 0.75)), r: 0.02)
            }
        case "bone":
            let shaft = cap(cv, V2(0.26, 0.74), V2(0.74, 0.26), 0.06)
            let k1 = smin(cv.circle(V2(0.2, 0.73), 0.075), cv.circle(V2(0.27, 0.8), 0.075), 0.03)
            let k2 = smin(cv.circle(V2(0.73, 0.2), 0.075), cv.circle(V2(0.8, 0.27), 0.075), 0.03)
            cv.add(smin(smin(shaft, k1, 0.04), k2, 0.04), zero, "bone", r: 0.08)
        case "string":
            let a = cv.poly(band(V2(0.12, 0.82), V2(0.28, 0.14), V2(0.5, 0.5), 0.06, 0.06, 18))
            let b = cv.poly(band(V2(0.5, 0.5), V2(0.72, 0.86), V2(0.88, 0.18), 0.06, 0.06, 18))
            cv.add(Canvas.union(a, b), xs, "string", r: 0.03)
        case "feather":
            let vane = cv.poly(band(V2(0.22, 0.82), V2(0.3, 0.26), V2(0.84, 0.12), 0.22, 0.02, 18))
            cv.add(vane, xs, "white", r: 0.1)
            let spine = bez(V2(0.22, 0.82), V2(0.3, 0.26), V2(0.84, 0.12), 20)
            for k in 0..<5 {
                let p0 = spine[Int((0.2 + Float(k) * 0.14) * 19)]
                cv.add(Canvas.intersect(cap(cv, p0, p0 + V2(0.1, 0.06), 0.006), Canvas.offset(vane, 0.01)), xs, soft(0xB8B8C4), r: 0.006)
            }
            cv.add(cv.poly(band(V2(0.14, 0.92), V2(0.3, 0.4), V2(0.82, 0.14), 0.026, 0.008, 18)), xs, "bone", r: 0.013)
        case "leather":
            cv.add(cv.poly([V2(0.2, 0.2), V2(0.42, 0.28), V2(0.6, 0.18), V2(0.82, 0.26), V2(0.74, 0.5), V2(0.84, 0.78), V2(0.56, 0.72),
                            V2(0.36, 0.84), V2(0.18, 0.72), V2(0.26, 0.48)]), ys, M("leather", base), r: 0.06)
        case "paper":
            cv.add(cv.poly([V2(0.2, 0.12), V2(0.8, 0.12), V2(0.8, 0.88), V2(0.2, 0.88)]), ys, "paper", r: 0.03)
            if name.hasSuffix("banner_pattern") {
                emblem(cv, name, V2(0.5, 0.5), 0.2, soft(ex["a"] ?? 0x5A5040))
            } else {
                for yy: Float in [0.3, 0.42, 0.54, 0.66] {
                    cv.add(cap(cv, V2(0.3, yy), V2(yy < 0.6 ? 0.7 : 0.56, yy), 0.012), ys, soft(ex["a"] ?? 0x9A9488), r: 0.01)
                }
            }
        case "book":
            cv.add(cv.poly([V2(0.24, 0.16), V2(0.84, 0.16), V2(0.84, 0.84), V2(0.24, 0.84)]), ys, "paper", r: 0.03)
            cv.add(cv.poly([V2(0.16, 0.12), V2(0.78, 0.12), V2(0.78, 0.8), V2(0.16, 0.8)]), ys, M("leather", base), r: 0.05)
            cv.add(cv.poly([V2(0.14, 0.12), V2(0.26, 0.12), V2(0.26, 0.88), V2(0.14, 0.88)]), ys, M("leather", darker(base, 0.7)), r: 0.05)
            if let acc = ex["c"] {
                cv.add(cv.poly([V2(0.38, 0.3), V2(0.66, 0.3), V2(0.66, 0.42), V2(0.38, 0.42)]), ys, name == "writable_book" ? soft(acc) : M("metal", acc), r: 0.02)
            }
            if name == "writable_book" { cv.add(cv.poly(band(V2(0.92, 0.06), V2(0.8, 0.3), V2(0.62, 0.62), 0.1, 0.01, 10)), xs, "white", r: 0.04) }
        case "compass":
            let m = name == "clock" ? "golden" : M("metal", base)
            let c = V2(0.5, 0.53)
            cv.add(cv.circle(c, 0.36), ys, m, r: 0.12)
            cv.add(cv.circle(c, 0.27), ys, name == "recovery_compass" ? soft(0x2A3A3A) : soft(0xE8E4D8), r: 0.06)
            cv.add(cv.circle(V2(0.5, 0.15), 0.06), ys, m, r: 0.04)
            for k in 0..<4 {
                let a = Float(k) * .pi / 2, dv = V2(cosf(a), sinf(a))
                cv.add(cap(cv, c + dv * 0.22, c + dv * 0.25, 0.01), ys, soft(0x4A4A4A), r: 0.01)
            }
        case "eye":
            if name == "ender_eye" {
                cv.add(cv.circle(V2(0.5, 0.52), 0.32), ys, M("gem", 0x2A9A6A), r: 0.32)
                cv.add(ellipse(cv, V2(0.5, 0.52), 0.2, 0.12), ys, soft(0xD8F070), r: 0.1)
                cv.add(ellipse(cv, V2(0.5, 0.52), 0.05, 0.12), ys, soft(0x101810), r: 0.04)
            } else {
                cv.add(ellipse(cv, V2(0.5, 0.54), 0.32, 0.28), ys, soft(base), r: 0.28)
                for c in [V2(0.38, 0.46), V2(0.6, 0.44), V2(0.5, 0.64)] {
                    cv.add(cv.circle(c, 0.06), ys, soft(ex["d"] ?? 0x200808), r: 0.05)
                    cv.add(cv.circle(c + V2(-0.02, -0.02), 0.018), ys, "white", r: 0.01)
                }
            }
        case "arrow":
            arrow(cv, xs, head: "flint")
        case "bow":
            cv.add(cv.poly(band(V2(0.18, 0.1), V2(0.94, 0.16), V2(0.88, 0.84), 0.07, 0.07, 22)), xs, "handle", r: 0.035)
            cv.add(cap(cv, V2(0.2, 0.12), V2(0.86, 0.84), 0.017), zero, "string", r: 0.017)
            wraps(cv, V2(0.66, 0.3), V2(0.76, 0.4), 0.05, 2)
        case "crossbow":
            handle(cv, V2(0.16, 0.86), V2(0.7, 0.32), 0.05)
            cv.add(cv.poly(band(V2(0.36, 0.1), V2(0.68, 0.18), V2(0.92, 0.64), 0.07, 0.07, 18)), xs, "iron", r: 0.035)
            cv.add(cap(cv, V2(0.38, 0.12), V2(0.56, 0.5), 0.015), zero, "string", r: 0.015)
            cv.add(cap(cv, V2(0.9, 0.62), V2(0.56, 0.5), 0.015), zero, "string", r: 0.015)
            cv.add(cv.circle(V2(0.62, 0.38), 0.06), zero, "iron", r: 0.05)
            cv.add(cap(cv, V2(0.34, 0.68), V2(0.42, 0.74), 0.03), zero, "iron", r: 0.03)
        case "shield":
            var pts: [V2] = [V2(0.16, 0.12), V2(0.84, 0.12), V2(0.84, 0.5)]
            pts += Array(bez(V2(0.84, 0.5), V2(0.82, 0.8), V2(0.5, 0.94), 8).dropFirst())
            pts += Array(bez(V2(0.5, 0.94), V2(0.18, 0.8), V2(0.16, 0.5), 8).dropFirst().dropLast())
            let d = cv.poly(pts)
            cv.add(d, ys, "iron", r: 0.04)
            cv.add(Canvas.offset(d, 0.05), ys, M("wood", base), r: 0.12)
            for x: Float in [0.38, 0.62] {
                cv.add(Canvas.intersect(cap(cv, V2(x, 0.12), V2(x, 0.94), 0.006), Canvas.offset(d, 0.05)), ys, M("wood", darker(base, 0.6)), r: 0.006)
            }
            cv.add(cv.circle(V2(0.5, 0.48), 0.09), ys, "iron", r: 0.08)
        case "trident":
            let tm = M("metal", base)
            handle(cv, V2(0.1, 0.92), V2(0.66, 0.36), 0.03, tm)
            let c = V2(0.68, 0.34)
            cv.add(cap(cv, c - rt * 0.14, c + rt * 0.14, 0.03), zero, tm, r: 0.03)
            for (o, l) in [(Float(-0.14), Float(0.2)), (0, 0.3), (0.14, 0.2)] {
                let b: V2 = c + rt * o, tip: V2 = b + up * l
                cv.add(cap(cv, b, tip - up * 0.04, 0.024), zero, tm, r: 0.024)
                cv.add(cv.poly([tip + up * 0.06, tip - up * 0.02 + rt * 0.05, tip - up * 0.02 - rt * 0.05]), zero, tm, r: 0.03, chamfer: true)
            }
        case "fishing_rod":
            cv.add(cv.poly(band(V2(0.12, 0.9), V2(0.4, 0.4), V2(0.86, 0.1), 0.06, 0.02, 18)), xs, "handle", r: 0.03)
            wraps(cv, V2(0.13, 0.88), V2(0.22, 0.75), 0.04, 2)
            let bait = ex["c"] ?? 0xD03030
            if name == "fishing_rod" {
                cv.add(cap(cv, V2(0.86, 0.1), V2(0.86, 0.66), 0.017), zero, "string", r: 0.017)
                cv.add(cv.circle(V2(0.86, 0.7), 0.045), zero, soft(bait), r: 0.04)
            } else {
                cv.add(cap(cv, V2(0.86, 0.1), V2(0.82, 0.5), 0.017), zero, "string", r: 0.017)
                cv.add(cv.poly(band(V2(0.82, 0.48), V2(0.86, 0.66), V2(0.8, 0.86), 0.12, 0.02, 10)), ys, soft(bait), r: 0.06)
            }
        case "shears":
            let piv = V2(0.52, 0.48)
            for tip in [V2(0.9, 0.16), V2(0.84, 0.1)] {
                let dr = simd_normalize(tip - piv), nr = V2(-dr.y, dr.x)
                let back: V2 = piv - dr * 0.06
                cv.add(cv.poly([back + nr * 0.05, tip, back - nr * 0.04]), cv.axis(piv, tip), "iron", r: 0.04, chamfer: true)
            }
            for c in [V2(0.24, 0.58), V2(0.42, 0.78)] {
                cv.add(cap(cv, piv, c, 0.03), zero, "iron", r: 0.03)
                cv.add(ring(cv.circle(c, 0.1), 0.035), zero, soft(ex["d"] ?? 0x5A3D1F), r: 0.035)
            }
            cv.add(cv.circle(piv, 0.035), zero, "iron", r: 0.03)
        case "flint_steel":
            // A C-shaped steel striker with a grip, a big knapped flint and sparks.
            let open = neg(cv.poly([V2(0.5, 0.4), V2(0.9, 0.2), V2(0.9, 0.6)]))
            cv.add(Canvas.intersect(ring(ellipse(cv, V2(0.38, 0.4), 0.26, 0.2), 0.045), open), xs, "iron", r: 0.045)
            cv.add(cv.circle(V2(0.18, 0.4), 0.06), xs, "grip", r: 0.05)
            cv.add(cv.poly([V2(0.46, 0.56), V2(0.7, 0.46), V2(0.9, 0.62), V2(0.8, 0.9), V2(0.52, 0.86)]), ys, "flint", r: 0.1, chamfer: true)
            for c in [V2(0.62, 0.42), V2(0.68, 0.36), V2(0.58, 0.34)] { cv.add(cv.circle(c, 0.018), xs, soft(0xFFD060), r: 0.015) }
        case "minecart":
            if name != "minecart" {
                cv.add(cv.poly([V2(0.24, 0.12), V2(0.76, 0.12), V2(0.76, 0.4), V2(0.24, 0.4)]), ys, M(name.contains("chest") ? "wood" : "soft", ex["c"] ?? 0x4A4A50), r: 0.05)
            }
            cv.add(cv.poly([V2(0.12, 0.34), V2(0.88, 0.34), V2(0.8, 0.72), V2(0.2, 0.72)]), xs, M("metal", base), r: 0.08)
            cv.add(cv.poly([V2(0.16, 0.38), V2(0.84, 0.38), V2(0.82, 0.46), V2(0.18, 0.46)]), xs, M("metal", darker(base, 0.6)), r: 0.02)
            for x: Float in [0.3, 0.7] {
                cv.add(cv.circle(V2(x, 0.76), 0.1), ys, M("metal", 0x3A3A40), r: 0.08)
                cv.add(cv.circle(V2(x, 0.76), 0.035), ys, "iron", r: 0.03)
            }
        case "boat", "chest_boat":
            // The paddle behind the hull (critic: it crowded the boat).
            cv.add(cap(cv, V2(0.7, 0.12), V2(0.5, 0.6), 0.022), zero, "handle", r: 0.022)
            cv.add(ellipse(cv, V2(0.72, 0.14), 0.05, 0.08), zero, "handle", r: 0.04)
            // A hull with a raised bow and stern (critic: the flat-topped one read as a basket).
            let hull = cv.poly([V2(0.02, 0.32), V2(0.2, 0.46), V2(0.8, 0.46), V2(0.98, 0.32), V2(0.84, 0.78), V2(0.16, 0.78)])
            cv.add(hull, xs, M("wood", base), r: 0.08)
            for yy: Float in [0.56, 0.66] { cv.add(Canvas.intersect(cap(cv, V2(0.06, yy), V2(0.94, yy), 0.008), hull), xs, M("wood", darker(base, 0.6)), r: 0.008) }
            cv.add(cap(cv, V2(0.06, 0.46), V2(0.94, 0.46), 0.03), xs, M("wood", darker(base, 0.8)), r: 0.03)
            if s.mask == "chest_boat" {
                cv.add(cv.poly([V2(0.28, 0.14), V2(0.66, 0.14), V2(0.66, 0.46), V2(0.28, 0.46)]), ys, M("wood", ex["c"] ?? 0x9A6A2A), r: 0.05)
                cv.add(cap(cv, V2(0.28, 0.25), V2(0.66, 0.25), 0.012), ys, M("wood", 0x5A3A1A), r: 0.012)
                cv.add(cv.poly([V2(0.44, 0.22), V2(0.5, 0.22), V2(0.5, 0.32), V2(0.44, 0.32)]), ys, "iron", r: 0.02)
            }
        case "horse_armor":
            let soft2 = name.hasPrefix("leather") || name == "wolf_armor"
            let m = metalByName[String(name.split(separator: "_")[0])] ?? M(soft2 ? "leather" : (name.contains("diamond") ? "gem" : "metal"), base)
            let head = cv.poly([V2(0.36, 0.1), V2(0.6, 0.14), V2(0.84, 0.54), V2(0.8, 0.7), V2(0.6, 0.64), V2(0.42, 0.9), V2(0.18, 0.86), V2(0.2, 0.4)])
            cv.add(head, ys, m, r: 0.2)
            cv.add(cv.circle(V2(0.48, 0.36), 0.05), ys, soft(0x101014), r: 0.04)
            cv.add(Canvas.intersect(cap(cv, V2(0.2, 0.62), V2(0.6, 0.62), 0.03), head), xs, m, r: 0.03)
            cv.add(cv.poly([V2(0.36, 0.1), V2(0.44, 0.0), V2(0.48, 0.14)]), ys, m, r: 0.03)
        case "bundle":
            let m = M("leather", base)
            cv.add(smin(ellipse(cv, V2(0.5, 0.62), 0.34, 0.28), cv.poly([V2(0.36, 0.3), V2(0.64, 0.3), V2(0.6, 0.44), V2(0.4, 0.44)]), 0.06), ys, m, r: 0.25)
            cv.add(cv.poly([V2(0.34, 0.16), V2(0.66, 0.16), V2(0.6, 0.32), V2(0.4, 0.32)]), ys, m, r: 0.05)
            cv.add(cap(cv, V2(0.36, 0.33), V2(0.64, 0.33), 0.025), xs, "string", r: 0.02)
        case "disc":
            let c = V2(0.5, 0.5)
            cv.add(cv.circle(c, 0.4), ys, soft(0x16161A), r: 0.06)
            for r: Float in [0.3, 0.34, 0.24] { cv.add(ring(cv.circle(c, r), 0.004), ys, soft(0x34343C), r: 0.004) }
            cv.add(cv.circle(c, 0.19), ys, soft(ex["c"] ?? 0xC03030), r: 0.05)
            cv.add(ring(cv.circle(c, 0.12), 0.008), ys, soft(lighter(ex["c"] ?? 0xC03030, 0.45)), r: 0.008)
            cv.add(cv.circle(c, 0.025), ys, soft(0x08080A), r: 0.02)
        case "sherd":
            let d = cv.poly([V2(0.16, 0.24), V2(0.56, 0.14), V2(0.86, 0.3), V2(0.8, 0.74), V2(0.4, 0.86), V2(0.14, 0.66)])
            cv.add(d, ys, M("stone", base), r: 0.1, chamfer: true)
            emblem(cv, name, V2(0.5, 0.5), 0.19, M("stone", darker(ex["c"] ?? 0x6A3A2A, 0.6)))
        case "template":
            cv.add(cv.poly([V2(0.2, 0.12), V2(0.8, 0.12), V2(0.8, 0.88), V2(0.2, 0.88)]), ys, M("stone", base), r: 0.06, chamfer: true)
            emblem(cv, name, V2(0.5, 0.5), 0.22, M("metal", lighter(ex["c"] ?? 0x6A8AAA, 0.55)))    // (critic: low contrast)
        case "key":
            let km = M("metal", base)
            cv.add(ring(cv.circle(V2(0.32, 0.32), 0.15), 0.045), zero, km, r: 0.045)
            cv.add(cap(cv, V2(0.42, 0.42), V2(0.82, 0.82), 0.045), zero, km, r: 0.045)
            cv.add(cap(cv, V2(0.7, 0.7), V2(0.6, 0.8), 0.04), zero, km, r: 0.04)
            cv.add(cap(cv, V2(0.8, 0.8), V2(0.7, 0.9), 0.04), zero, km, r: 0.04)
        case "star":
            let pts: [V2] = (0..<10).map { k in
                let a = -Float.pi / 2 + Float(k) * .pi / 5
                let r: Float = k % 2 == 0 ? 0.42 : 0.18
                return V2(0.5 + cosf(a) * r, 0.54 + sinf(a) * r)
            }
            cv.add(cv.poly(pts), ys, M("gem", base), r: 0.2, chamfer: true)
        case "totem":
            let gemM = M("gem", ex["c"] ?? 0x2A8A3A)
            cv.add(cv.poly([V2(0.3, 0.42), V2(0.7, 0.42), V2(0.64, 0.92), V2(0.36, 0.92)]), ys, "golden", r: 0.1)
            cv.add(cv.poly([V2(0.1, 0.44), V2(0.3, 0.42), V2(0.3, 0.6), V2(0.14, 0.62)]), ys, "golden", r: 0.05)
            cv.add(cv.poly([V2(0.9, 0.44), V2(0.7, 0.42), V2(0.7, 0.6), V2(0.86, 0.62)]), ys, "golden", r: 0.05)
            cv.add(ellipse(cv, V2(0.5, 0.26), 0.2, 0.18), ys, "golden", r: 0.15)
            for x: Float in [0.42, 0.58] { cv.add(cv.circle(V2(x, 0.26), 0.035), ys, gemM, r: 0.03) }
            cv.add(cv.poly([V2(0.4, 0.5), V2(0.6, 0.5), V2(0.5, 0.64)]), ys, gemM, r: 0.04, chamfer: true)
        case "spyglass":
            let a = V2(0.16, 0.84), b = V2(0.84, 0.16)
            let (d, t) = cv.capsule(a, b, 0.05, 0.085)
            cv.add(d, t, M("metal", base), r: 0.08)
            let dir = simd_normalize(b - a)
            for (k, r) in [(Float(0), Float(0.07)), (0.45, 0.085), (1, 0.1)] {
                let c: V2 = a + (b - a) * k
                cv.add(cap(cv, c - dir * 0.03, c + dir * 0.03, r), t, "golden", r: 0.06)
            }
        case "mace":
            handle(cv, V2(0.16, 0.88), V2(0.6, 0.44), 0.035, "grip")
            wraps(cv, V2(0.18, 0.86), V2(0.36, 0.68), 0.035, 3)
            let c = V2(0.68, 0.34)
            var hd = cv.circle(c, 0.18)
            for k in 0..<6 {
                let a = Float(k) * .pi / 3
                let dv = V2(cosf(a), sinf(a)), pv = V2(-sinf(a), cosf(a))
                let sc: V2 = c + dv * 0.2
                hd = Canvas.union(hd, cv.poly([sc + dv * 0.08, sc + pv * 0.05, sc - pv * 0.05]))
            }
            cv.add(hd, ys, M("metal", base), r: 0.12, chamfer: true)
        case "brush":
            handle(cv, V2(0.14, 0.88), V2(0.56, 0.46), 0.04)
            cv.add(cv.poly([V2(0.5, 0.42), V2(0.62, 0.3), V2(0.92, 0.2), V2(0.8, 0.5)]), cv.axis(V2(0.56, 0.44), V2(0.86, 0.3)), M("wood", base), r: 0.05)
            cv.add(cap(cv, V2(0.5, 0.4), V2(0.6, 0.5), 0.04), zero, "copper", r: 0.04)
        case "lead":
            cv.add(cv.poly(band(V2(0.2, 0.2), V2(0.9, 0.4), V2(0.4, 0.86), 0.05, 0.05, 20)), xs, M("leather", base), r: 0.025)
            cv.add(ring(cv.circle(V2(0.24, 0.22), 0.1), 0.03), zero, M("leather", base), r: 0.03)
        case "crystal":
            if name == "end_crystal" {
                cv.add(cv.poly([V2(0.5, 0.08), V2(0.82, 0.46), V2(0.5, 0.9), V2(0.18, 0.46)]), ys, M("gem", base), r: 0.16, chamfer: true)
                cv.add(ring(ellipse(cv, V2(0.5, 0.48), 0.4, 0.14), 0.03), xs, M("metal", 0x8A8A9A), r: 0.03)
            } else {
                for (a, b, w) in [(V2(0.36, 0.86), V2(0.5, 0.12), Float(0.16)), (V2(0.58, 0.86), V2(0.78, 0.38), 0.12)] {
                    let dr = simd_normalize(b - a), nr = V2(-dr.y, dr.x), ln = simd_length(b - a)
                    let mid: V2 = a + dr * (ln * 0.7)
                    cv.add(cv.poly([a + nr * (w / 2), mid + nr * (w / 2), b, mid - nr * (w / 2), a - nr * (w / 2)]), cv.axis(a, b), M("gem", base), r: w / 2, chamfer: true)
                }
            }
        case "tear":
            cv.add(smin(cv.circle(V2(0.5, 0.62), 0.24), cv.poly([V2(0.5, 0.1), V2(0.7, 0.5), V2(0.3, 0.5)]), 0.08), ys, M("gem", base), r: 0.24)
        case "membrane":
            cv.add(cv.poly([V2(0.12, 0.3), V2(0.88, 0.2), V2(0.78, 0.5), V2(0.86, 0.8), V2(0.56, 0.66), V2(0.3, 0.84), V2(0.3, 0.56)]), ys, M("leather", base), r: 0.05)
            for (a, b) in [(V2(0.14, 0.31), V2(0.56, 0.66)), (V2(0.5, 0.26), V2(0.56, 0.66)), (V2(0.84, 0.22), V2(0.56, 0.66))] {
                cv.add(cap(cv, a, b, 0.012), ys, M("leather", darker(base, 0.7)), r: 0.012)
            }
        case "kelp":
            for k in 0..<3 {
                let o = V2(0.1 * Float(k) - 0.1, 0.04 * Float(k))
                cv.add(cv.poly(band(V2(0.3, 0.88) + o, V2(0.62, 0.5) + o, V2(0.44, 0.12) + o, 0.12, 0.05, 14)), xs, M("leather", darker(base, 1 - 0.12 * Float(k))), r: 0.05)
            }
        case "foot":
            cv.add(smin(ellipse(cv, V2(0.46, 0.62), 0.2, 0.26), ellipse(cv, V2(0.64, 0.3), 0.12, 0.16), 0.12), ys, M("leather", base), r: 0.2)
            for c in [V2(0.56, 0.16), V2(0.68, 0.16), V2(0.76, 0.24)] { cv.add(ellipse(cv, c, 0.035, 0.05), ys, soft(0x3A3030), r: 0.03) }
            cv.add(cap(cv, V2(0.36, 0.84), V2(0.56, 0.84), 0.04), ys, soft(ex["c"] ?? 0xE8D8C0), r: 0.04)
        case "rocket":
            let a = V2(0.3, 0.74), b = V2(0.66, 0.34)
            let (d, t) = cv.capsule(a, b, 0.1)
            cv.add(cap(cv, V2(0.1, 0.94), a, 0.018), zero, "handle", r: 0.018)
            cv.add(d, t, "paper", r: 0.1)
            for k: Float in [0.3, 0.6] {
                let c: V2 = a + (b - a) * k
                cv.add(Canvas.intersect(cap(cv, c - V2(0.08, 0.08), c + V2(0.08, 0.08), 0.035), d), t, soft(base), r: 0.03)
            }
            cv.add(cv.poly([V2(0.6, 0.26), V2(0.84, 0.16), V2(0.74, 0.4)]), t, soft(base), r: 0.05, chamfer: true)
        case "firework_star", "charge":
            let d = cv.circle(V2(0.5, 0.52), 0.3)
            let star = s.mask == "firework_star"
            cv.add(d, ys, star ? M("stone", base) : soft(0x3A2A1A), r: 0.3)
            for c in [V2(0.41, 0.43), V2(0.59, 0.51), V2(0.45, 0.63)] {
                cv.add(Canvas.intersect(cv.circle(c, star ? 0.05 : 0.07), Canvas.offset(d, 0.03)), ys, soft(star ? (ex["c"] ?? 0x9A9AA0) : 0xF8A030), r: 0.045)
            }
        case "scute":
            let d = cv.poly([V2(0.5, 0.12), V2(0.82, 0.3), V2(0.78, 0.7), V2(0.5, 0.88), V2(0.22, 0.7), V2(0.18, 0.3)])
            cv.add(d, ys, M("leather", base), r: 0.14, chamfer: true)
            let inner = cv.poly([V2(0.5, 0.3), V2(0.66, 0.4), V2(0.64, 0.6), V2(0.5, 0.7), V2(0.36, 0.6), V2(0.34, 0.4)])
            cv.add(Canvas.intersect(ring(inner, 0.012), Canvas.offset(d, 0.04)), ys, M("leather", darker(base, 0.7)), r: 0.012)
        case "sac":
            let d = smin(ellipse(cv, V2(0.5, 0.6), 0.3, 0.26), ellipse(cv, V2(0.5, 0.3), 0.1, 0.12), 0.1)
            cv.add(d, ys, soft(base), r: 0.25)
            cv.add(Canvas.intersect(cv.circle(V2(0.42, 0.56), 0.08), d), ys, soft(lighter(base, 0.25)), r: 0.06)
        case "shell":
            if name == "nautilus_shell" {
                let d = cv.circle(V2(0.5, 0.54), 0.36)
                cv.add(d, ys, soft(0xE8D8C4), r: 0.3)
                for k in 0..<4 {
                    cv.add(Canvas.intersect(ring(cv.circle(V2(0.56 - 0.03 * Float(k), 0.56), 0.08 + Float(k) * 0.08), 0.012), Canvas.offset(d, 0.02)), ys, soft(0xA0583A), r: 0.012)
                }
            } else {
                let d = Canvas.intersect(ellipse(cv, V2(0.5, 0.6), 0.4, 0.34), cv.below(0.66))
                cv.add(d, ys, M("leather", base), r: 0.2)
                for x: Float in [0.3, 0.5, 0.7] {
                    cv.add(Canvas.intersect(cap(cv, V2(x, 0.3), V2(x, 0.66), 0.012), Canvas.offset(d, 0.02)), ys, M("leather", darker(base, 0.7)), r: 0.012)
                }
            }
        case "honeycomb":
            for c in [V2(0.36, 0.38), V2(0.64, 0.38), V2(0.5, 0.62), V2(0.22, 0.62), V2(0.78, 0.62)] {
                let hexAt: (Float) -> [V2] = { r in (0..<6).map { (k: Int) -> V2 in
                    let a = Float(k) * .pi / 3 + .pi / 6
                    return c + V2(cosf(a), sinf(a)) * r
                } }
                cv.add(cv.poly(hexAt(0.14)), ys, soft(base), r: 0.06, chamfer: true)
                cv.add(cv.poly(hexAt(0.07)), ys, soft(ex["c"] ?? 0xF8C850), r: 0.03)
            }
        case "horn":
            let p0 = V2(0.84, 0.24), c0 = V2(0.5, 0.92), p1 = V2(0.14, 0.4)
            cv.add(cv.poly(band(p0, c0, p1, 0.2, 0.04, 18)), xs, soft(base), r: 0.08)
            let spine = bez(p0, c0, p1, 18)
            for k in 0..<4 { cv.add(cv.circle(spine[3 + k * 3], 0.02), xs, soft(darker(base, 0.75)), r: 0.015) }
        case "name_tag":
            cv.add(cv.poly([V2(0.12, 0.36), V2(0.68, 0.36), V2(0.88, 0.5), V2(0.68, 0.64), V2(0.12, 0.64)]), xs, "paper", r: 0.04)
            cv.add(cv.circle(V2(0.72, 0.5), 0.03), xs, soft(0x2A2A2A), r: 0.02)
            cv.add(cap(cv, V2(0.74, 0.5), V2(0.94, 0.2), 0.014), zero, "string", r: 0.014)
            for x: Float in [0.2, 0.32, 0.44] { cv.add(cap(cv, V2(x, 0.5), V2(x + 0.07, 0.5), 0.014), xs, soft(0x5A5048), r: 0.012) }
        case "pufferfish":
            let c = V2(0.48, 0.54)
            var d = cv.circle(c, 0.28)
            for k in 0..<10 {
                let a = Float(k) * .pi / 5
                let dv = V2(cosf(a), sinf(a)), pv = V2(-sinf(a), cosf(a))
                let sc: V2 = c + dv * 0.28
                d = Canvas.union(d, cv.poly([sc + dv * 0.08, sc + pv * 0.04, sc - pv * 0.04]))
            }
            cv.add(d, ys, soft(base), r: 0.25)
            cv.add(cv.circle(V2(0.34, 0.46), 0.04), ys, soft(0x18181C), r: 0.03)
        case "map":
            let d = cv.poly([V2(0.14, 0.14), V2(0.86, 0.14), V2(0.86, 0.86), V2(0.14, 0.86)])
            cv.add(d, ys, soft(ex["c"] ?? 0xE8E0C0), r: 0.04)
            if name == "filled_map" {
                cv.add(Canvas.intersect(ellipse(cv, V2(0.44, 0.5), 0.2, 0.16), Canvas.offset(d, 0.08)), ys, soft(ex["d"] ?? 0x6A9A5A), r: 0.05)
                cv.add(Canvas.intersect(ellipse(cv, V2(0.66, 0.66), 0.12, 0.1), Canvas.offset(d, 0.08)), ys, soft(0x5A8ACA), r: 0.03)
            }
            cv.add(ring(Canvas.offset(d, 0.06), 0.01), ys, soft(0xA08A60), r: 0.01)
        case "chestplate" where name == "elytra":
            for sg: Float in [-1, 1] {
                var pts: [V2] = [V2(0.5 + 0.04 * sg, 0.16), V2(0.5 + 0.38 * sg, 0.12), V2(0.5 + 0.44 * sg, 0.3)]
                pts += Array(bez(V2(0.5 + 0.44 * sg, 0.3), V2(0.5 + 0.36 * sg, 0.7), V2(0.5 + 0.2 * sg, 0.9), 8).dropFirst())
                pts.append(V2(0.5 + 0.06 * sg, 0.6))
                let w = cv.poly(pts)
                cv.add(w, ys, M("leather", base), r: 0.1)
                for k in 0..<3 {
                    let y0: Float = 0.3 + Float(k) * 0.16
                    cv.add(Canvas.intersect(cap(cv, V2(0.5 + 0.08 * sg, y0 - 0.06), V2(0.5 + 0.4 * sg, y0 + 0.04), 0.008), Canvas.offset(w, 0.03)),
                           ys, M("leather", darker(base, 0.7)), r: 0.008)
                }
            }
        case "armor_stand":
            let wd = M("wood", base)
            cv.add(rect(cv, 0.2, 0.86, 0.8, 0.94), xs, M("stone", 0x9A9A9C), r: 0.03)
            cv.add(cap(cv, V2(0.5, 0.18), V2(0.5, 0.88), 0.03), ys, wd, r: 0.03)
            cv.add(cap(cv, V2(0.24, 0.3), V2(0.76, 0.3), 0.03), xs, wd, r: 0.03)
            cv.add(cap(cv, V2(0.32, 0.56), V2(0.68, 0.56), 0.028), xs, wd, r: 0.028)
            for x: Float in [0.42, 0.58] { cv.add(cap(cv, V2(x, 0.56), V2(x, 0.86), 0.022), ys, wd, r: 0.022) }
            cv.add(ellipse(cv, V2(0.5, 0.14), 0.08, 0.08), ys, wd, r: 0.06)
        case "saddle":
            var seatPts = bez(V2(0.12, 0.3), V2(0.5, 0.62), V2(0.86, 0.36), 12)
            seatPts += [V2(0.88, 0.5), V2(0.7, 0.62), V2(0.3, 0.62), V2(0.12, 0.46)]
            cv.add(cv.poly(seatPts), xs, M("leather", base), r: 0.12)
            cv.add(cv.poly([V2(0.36, 0.56), V2(0.64, 0.56), V2(0.6, 0.84), V2(0.4, 0.84)]), ys, M("leather", darker(base, 0.8)), r: 0.06)
            cv.add(cap(cv, V2(0.5, 0.6), V2(0.5, 0.84), 0.016), zero, M("leather", darker(base, 0.6)), r: 0.015)
            cv.add(ring(ellipse(cv, V2(0.5, 0.88), 0.07, 0.05), 0.018), zero, "iron", r: 0.018)
        default:
            return false
        }
        return true
    }

    static func rect(_ cv: Canvas, _ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> [Float] {
        cv.poly([V2(x0, y0), V2(x1, y0), V2(x1, y1), V2(x0, y1)])
    }

    // A small motif picked by the item's name (pottery sherds, trim templates, banner patterns): one of eight shapes,
    // so a family of look-alike items tells its members apart.
    static func emblem(_ cv: Canvas, _ name: String, _ c: V2, _ r: Float, _ m: String) {
        var h = 0
        for (i, ch) in name.unicodeScalars.enumerated() { h += Int(ch.value) * (i + 1) }
        let zero = [Float](repeating: 0, count: cv.n * cv.n)
        switch h % 8 {
        case 0: cv.add(ring(cv.circle(c, r), r * 0.22), zero, m, r: r * 0.2)
        case 1: cv.add(cv.poly([c + V2(0, -r), c + V2(r, 0), c + V2(0, r), c + V2(-r, 0)]), zero, m, r: r * 0.4, chamfer: true)
        case 2:
            let pts: [V2] = (0..<10).map { (i: Int) -> V2 in
                let a = Float(i) * .pi / 5 - .pi / 2, rr = i % 2 == 0 ? r : r * 0.45
                return c + V2(cosf(a), sinf(a)) * rr
            }
            cv.add(cv.poly(pts), zero, m, r: r * 0.4, chamfer: true)
        case 3: cv.add(Canvas.union(cap(cv, c - V2(r, 0), c + V2(r, 0), r * 0.25), cap(cv, c - V2(0, r), c + V2(0, r), r * 0.25)), zero, m, r: r * 0.2)
        case 4: cv.add(cv.poly([c + V2(0, -r), c + V2(r, r * 0.8), c + V2(-r, r * 0.8)]), zero, m, r: r * 0.4, chamfer: true)
        case 5:
            let lobes = smin(cv.circle(c + V2(-r * 0.45, -r * 0.2), r * 0.5), cv.circle(c + V2(r * 0.45, -r * 0.2), r * 0.5), 0.02)
            cv.add(smin(lobes, cv.poly([c + V2(-r * 0.9, 0), c + V2(r * 0.9, 0), c + V2(0, r)]), 0.02), zero, m, r: r * 0.4)
        case 6: cv.add(cv.poly(band(c + V2(-r, r * 0.5), c + V2(0, -r * 1.2), c + V2(r, r * 0.5), r * 0.4, r * 0.4, 10)), zero, m, r: r * 0.2)
        default:
            for dx: Float in [-0.5, 0.5] { cv.add(cv.circle(c + V2(dx * r, 0), r * 0.42), zero, m, r: r * 0.3) }
        }
    }

    static func arrow(_ cv: Canvas, _ xs: [Float], head: String) {
        handle(cv, V2(0.18, 0.82), V2(0.74, 0.26), 0.022)
        for sgn: Float in [-1, 1] {
            let o: V2 = V2(0.707, 0.707) * (0.07 * sgn)
            cv.add(cv.poly([V2(0.14, 0.86), V2(0.3, 0.7), V2(0.36, 0.64) + o, V2(0.2, 0.8) + o * 1.3]), xs, "white", r: 0.03)
        }
        cv.add(cv.poly([V2(0.64, 0.18), V2(0.94, 0.06), V2(0.82, 0.36)]), cv.axis(V2(0.7, 0.3), V2(0.9, 0.1)), head, r: 0.06, chamfer: true)
    }

    // MARK: Overlay pairs

    // The texture keys drawn as a base + tinted overlay pair, and which half each is.
    static let pairKeys: [String: (String, Bool)] = [
        "item_potion_bottle": ("potion", false), "item_splash_bottle": ("splash", false), "item_lingering_bottle": ("lingering", false),
        "item_potion_liquid": ("potion", true), "item_spawn_egg": ("egg", false), "item_spawn_egg_shell": ("egg", true),
        "item_tipped_arrow": ("arrow", false), "item_tipped_arrow_head": ("arrow", true),
    ]

    static func pairCanvas(_ key: String, _ n: Int) -> Canvas {
        let cv = Canvas(n)
        let ys = cv.axis(V2(0.5, 0), V2(0.5, 1)), xs = cv.axis(V2(0, 0.5), V2(1, 0.5))
        switch key {
        case "potion", "splash", "lingering":
            let tall = key == "lingering"
            let body = smin(cv.circle(V2(0.5, 0.62), 0.28), cap(cv, V2(0.5, tall ? 0.1 : 0.18), V2(0.5, 0.45), tall ? 0.055 : 0.085), 0.06)
            cv.add(body, ys, "glass", r: 0.26)
            cv.add(Canvas.intersect(cv.circle(V2(0.5, 0.62), 0.235), neg(cv.below(0.5))), ys, "tint", r: 0.22)
            // Splash: a grip ring round the neck and a loop handle; lingering: a tall narrow neck (critic: the three
            // forms differed only by a cap tint).
            if key == "splash" {
                cv.add(cap(cv, V2(0.36, 0.3), V2(0.64, 0.3), 0.035), ys, "glass", r: 0.035)
                cv.add(Canvas.intersect(ring(ellipse(cv, V2(0.78, 0.48), 0.1, 0.14), 0.025), neg(cv.circle(V2(0.5, 0.62), 0.27))), ys, "glass", r: 0.025)
            }
            let lip: Float = tall ? 0.12 : 0.2
            cv.add(cap(cv, V2(0.4, lip), V2(0.6, lip), 0.032), ys, "glass", r: 0.03)
            cv.add(cv.poly([V2(0.42, lip - (tall ? 0.1 : 0.15)), V2(0.58, lip - (tall ? 0.1 : 0.15)), V2(0.57, lip - 0.01), V2(0.43, lip - 0.01)]), ys,
                   M("wood", tall ? 0xB080C8 : 0xA87A4A), r: 0.04)
            cv.add(Canvas.intersect(cv.poly(band(V2(0.33, 0.74), V2(0.3, 0.56), V2(0.4, 0.44), 0.045, 0.02, 10)), Canvas.offset(body, 0.03)), ys, "white", r: 0.02)
        case "egg":
            let d = ellipse(cv, V2(0.5, 0.55), 0.29, 0.37)
            cv.add(d, ys, "tint", r: 0.32)
            // Spots: pale with a dark seam, so they read on every shell colour (critic: dark dots vanished on dark eggs).
            for (c, r) in [(V2(0.42, 0.36), Float(0.05)), (V2(0.63, 0.5), 0.058), (V2(0.42, 0.66), 0.045), (V2(0.63, 0.74), 0.04), (V2(0.32, 0.52), 0.035)] {
                cv.add(Canvas.intersect(cv.circle(c, r), Canvas.offset(d, 0.03)), ys, M("soft", 0xE6DCC8), r: 0.035)
            }
        default:
            arrow(cv, xs, head: "tint")
        }
        return cv
    }
}

// MARK: Steelhold guns and ammunition

extension ItemHD {
    // Long guns are drawn level, then seen tilted and enlarged so they fill the slot like the tools (critic: the
    // pixel-art guns were the one part of the sheet in another style).
    static let gunPose: [String: (Float, Float)] = ["gun_rifle": (0.42, 1.12), "gun_smg": (0.3, 1.15), "gun_shotgun": (0.45, 1.1),
                                                     "gun_sniper": (0.45, 1.08), "gun_launcher": (0.45, 1.05), "gun_arc": (0.42, 1.1),
                                                     "gun_sidearm": (0.15, 1.1)]
    static let gunKeys: Set<String> = ["gun_rifle", "gun_smg", "gun_shotgun", "gun_sniper", "gun_launcher", "gun_arc", "gun_sidearm",
                                       "rifle_rounds", "shotgun_shells", "heavy_rounds", "rocket_ammo", "arc_cell"]

    static func gunCanvas(_ key: String, _ n: Int) -> Canvas {
        let pose = gunPose[key] ?? (0, 1)
        let cv = Canvas(n, tilt: pose.0, zoom: pose.1)
        let ys = cv.axis(V2(0.5, 0), V2(0.5, 1)), xs = cv.axis(V2(0, 0.5), V2(1, 0.5))
        let steel = M("metal", 0x4A4E56), dark = M("metal", 0x2A2C32), wood = M("wood", 0x8A5A30), poly = M("leather", 0x34363A)
        func grip(_ x: Float, _ y: Float, _ m: String) {
            cv.add(cv.poly([V2(x, y), V2(x + 0.06, y), V2(x + 0.04, y + 0.14), V2(x - 0.03, y + 0.14)]), ys, m, r: 0.03)
        }
        switch key {
        case "gun_rifle":
            cv.add(cv.poly([V2(0.04, 0.46), V2(0.3, 0.42), V2(0.32, 0.56), V2(0.08, 0.66)]), xs, wood, r: 0.05)
            cv.add(cv.poly(band(V2(0.44, 0.56), V2(0.48, 0.7), V2(0.42, 0.82), 0.09, 0.08, 10)), ys, dark, r: 0.04)
            cv.add(rect(cv, 0.28, 0.4, 0.62, 0.56), xs, steel, r: 0.06, chamfer: true)
            grip(0.33, 0.55, wood)
            cv.add(rect(cv, 0.6, 0.42, 0.82, 0.53), xs, wood, r: 0.04)
            cv.add(cap(cv, V2(0.8, 0.46), V2(0.97, 0.46), 0.018), xs, dark, r: 0.018)
            cv.add(rect(cv, 0.36, 0.34, 0.5, 0.4), xs, dark, r: 0.02)
            cv.add(cv.poly([V2(0.84, 0.44), V2(0.86, 0.38), V2(0.88, 0.44)]), xs, dark, r: 0.01)
        case "gun_smg":
            cv.add(cap(cv, V2(0.08, 0.5), V2(0.26, 0.48), 0.018), xs, dark, r: 0.018)
            cv.add(cap(cv, V2(0.08, 0.5), V2(0.1, 0.62), 0.018), xs, dark, r: 0.018)
            cv.add(rect(cv, 0.42, 0.56, 0.52, 0.86), ys, dark, r: 0.04)
            cv.add(rect(cv, 0.24, 0.38, 0.72, 0.56), xs, steel, r: 0.07, chamfer: true)
            cv.add(cv.poly([V2(0.28, 0.55), V2(0.36, 0.55), V2(0.33, 0.74), V2(0.25, 0.74)]), ys, poly, r: 0.03)
            cv.add(cap(cv, V2(0.7, 0.45), V2(0.86, 0.45), 0.03), xs, dark, r: 0.03)
            cv.add(rect(cv, 0.6, 0.56, 0.66, 0.66), ys, poly, r: 0.02)
        case "gun_shotgun":
            cv.add(cv.poly([V2(0.03, 0.48), V2(0.28, 0.44), V2(0.3, 0.56), V2(0.06, 0.68)]), xs, wood, r: 0.05)
            cv.add(rect(cv, 0.27, 0.42, 0.46, 0.56), xs, steel, r: 0.06, chamfer: true)
            grip(0.3, 0.55, wood)
            cv.add(cap(cv, V2(0.44, 0.45), V2(0.96, 0.45), 0.026), xs, dark, r: 0.026)
            cv.add(cap(cv, V2(0.44, 0.52), V2(0.9, 0.52), 0.022), xs, steel, r: 0.022)
            let pump = rect(cv, 0.56, 0.48, 0.74, 0.58)
            cv.add(pump, xs, wood, r: 0.04)
            for x: Float in [0.6, 0.64, 0.68] { cv.add(Canvas.intersect(cap(cv, V2(x, 0.48), V2(x, 0.58), 0.006), pump), ys, M("wood", 0x5A3A1A), r: 0.006) }
        case "gun_sniper":
            cv.add(cv.poly([V2(0.02, 0.5), V2(0.26, 0.46), V2(0.28, 0.58), V2(0.04, 0.68)]), xs, wood, r: 0.05)
            cv.add(rect(cv, 0.24, 0.45, 0.52, 0.58), xs, steel, r: 0.06, chamfer: true)
            grip(0.3, 0.57, wood)
            cv.add(rect(cv, 0.5, 0.47, 0.7, 0.56), xs, wood, r: 0.04)
            cv.add(cap(cv, V2(0.68, 0.5), V2(0.98, 0.5), 0.015), xs, dark, r: 0.015)
            cv.add(cap(cv, V2(0.3, 0.37), V2(0.56, 0.37), 0.04), xs, dark, r: 0.04)
            cv.add(cv.circle(V2(0.56, 0.37), 0.045), xs, dark, r: 0.045)
            cv.add(ellipse(cv, V2(0.575, 0.37), 0.012, 0.03), xs, M("gem", 0x3A8AE0), r: 0.01)
            cv.add(rect(cv, 0.38, 0.4, 0.44, 0.46), xs, dark, r: 0.02)
            for sg: Float in [-1, 1] { cv.add(cap(cv, V2(0.66, 0.56), V2(0.66 + 0.06 * sg, 0.72), 0.012), ys, dark, r: 0.012) }
        case "gun_launcher":
            let olive = M("leather", 0x5A6A3A)
            cv.add(cap(cv, V2(0.06, 0.46), V2(0.94, 0.46), 0.075), xs, olive, r: 0.075)
            cv.add(rect(cv, 0.0, 0.38, 0.08, 0.54), xs, dark, r: 0.03)
            cv.add(rect(cv, 0.9, 0.37, 0.98, 0.55), xs, dark, r: 0.03)
            for x: Float in [0.34, 0.56] { cv.add(cv.poly([V2(x, 0.52), V2(x + 0.07, 0.52), V2(x + 0.05, 0.7), V2(x - 0.02, 0.7)]), ys, poly, r: 0.03) }
            cv.add(rect(cv, 0.44, 0.3, 0.58, 0.39), xs, dark, r: 0.02)
            cv.add(Canvas.intersect(cap(cv, V2(0.2, 0.46), V2(0.8, 0.46), 0.08), rect(cv, 0.7, 0.3, 0.74, 0.6)), xs, M("soft", 0xC8A030), r: 0.02)
        case "gun_arc":
            let white = M("soft", 0xD8DCE4), glow = M("soft", 0x4AE8F0)
            cv.add(cv.poly([V2(0.04, 0.5), V2(0.24, 0.44), V2(0.26, 0.58), V2(0.06, 0.62)]), xs, white, r: 0.05)
            cv.add(cv.poly([V2(0.22, 0.4), V2(0.64, 0.38), V2(0.7, 0.46), V2(0.64, 0.58), V2(0.22, 0.58)]), xs, white, r: 0.08, chamfer: true)
            grip(0.3, 0.57, poly)
            cv.add(cap(cv, V2(0.66, 0.48), V2(0.96, 0.48), 0.02), xs, steel, r: 0.02)
            for x: Float in [0.72, 0.8, 0.88] { cv.add(ring(ellipse(cv, V2(x, 0.48), 0.018, 0.05), 0.01), xs, "copper", r: 0.01) }
            cv.add(rect(cv, 0.32, 0.44, 0.58, 0.5), xs, glow, r: 0.02)
            cv.add(cv.circle(V2(0.96, 0.48), 0.03), xs, glow, r: 0.03)
        case "gun_sidearm":
            cv.add(rect(cv, 0.22, 0.34, 0.82, 0.48), xs, steel, r: 0.05, chamfer: true)
            cv.add(cv.poly([V2(0.24, 0.47), V2(0.46, 0.47), V2(0.42, 0.84), V2(0.24, 0.84), V2(0.2, 0.6)]), ys, poly, r: 0.06)
            cv.add(ring(ellipse(cv, V2(0.52, 0.56), 0.07, 0.07), 0.014), ys, dark, r: 0.014)
            for x: Float in [0.6, 0.66, 0.72] { cv.add(cap(cv, V2(x, 0.36), V2(x, 0.46), 0.006), ys, dark, r: 0.006) }
        case "rifle_rounds":
            for k in 0..<3 {
                let x: Float = 0.26 + Float(k) * 0.22
                cv.add(rect(cv, x - 0.07, 0.42, x + 0.07, 0.86), xs, "golden", r: 0.07)
                cv.add(cv.poly(band(V2(x, 0.43), V2(x, 0.3), V2(x, 0.16), 0.13, 0.02, 10)), xs, "copper", r: 0.06)
            }
        case "shotgun_shells":
            for k in 0..<2 {
                let x: Float = 0.34 + Float(k) * 0.3
                cv.add(rect(cv, x - 0.11, 0.16, x + 0.11, 0.68), xs, M("soft", 0xC8282A), r: 0.11)
                cv.add(rect(cv, x - 0.12, 0.66, x + 0.12, 0.86), xs, "golden", r: 0.06)
            }
        case "heavy_rounds":
            for k in 0..<2 {
                let x: Float = 0.34 + Float(k) * 0.3
                cv.add(rect(cv, x - 0.09, 0.4, x + 0.09, 0.92), xs, "golden", r: 0.09)
                cv.add(cv.poly(band(V2(x, 0.41), V2(x, 0.22), V2(x, 0.06), 0.16, 0.02, 10)), xs, dark, r: 0.07)
            }
        case "rocket_ammo":
            let a = V2(0.14, 0.86), b = V2(0.86, 0.14)
            let ab: V2 = b - a
            let (d, t) = cv.capsule(a + ab * 0.15, a + ab * 0.62, 0.09)
            cv.add(d, t, M("leather", 0x5A6A3A), r: 0.09)
            cv.add(cv.poly(band(a + ab * 0.6, a + ab * 0.8, b, 0.2, 0.02, 10)), t, dark, r: 0.08)
            for sg: Float in [-1, 1] {
                let nrm: V2 = V2(0.707, 0.707) * sg
                cv.add(cv.poly([a + ab * 0.12, a + ab * 0.3 + nrm * 0.08, a + ab * 0.05 + nrm * 0.16]), t, dark, r: 0.03)
            }
        default:                                                            // arc cell
            cv.add(rect(cv, 0.26, 0.16, 0.74, 0.88), ys, M("metal", 0x6A707A), r: 0.08, chamfer: true)
            cv.add(rect(cv, 0.4, 0.08, 0.6, 0.17), ys, "copper", r: 0.03)
            cv.add(rect(cv, 0.34, 0.28, 0.66, 0.78), ys, M("soft", 0x4AE8F0), r: 0.06)
            for y: Float in [0.4, 0.53, 0.66] { cv.add(cap(cv, V2(0.36, y), V2(0.64, y), 0.01), ys, M("soft", 0x1A6A7A), r: 0.01) }
        }
        return cv
    }
}
