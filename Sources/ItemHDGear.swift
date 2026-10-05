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
            for yy: Float in [0.3, 0.42, 0.54, 0.66] {
                cv.add(cap(cv, V2(0.3, yy), V2(yy < 0.6 ? 0.7 : 0.56, yy), 0.012), ys, soft(ex["a"] ?? 0x9A9488), r: 0.01)
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
            cv.add(cap(cv, V2(0.2, 0.12), V2(0.86, 0.84), 0.01), zero, "string", r: 0.01)
            wraps(cv, V2(0.66, 0.3), V2(0.76, 0.4), 0.05, 2)
        case "crossbow":
            handle(cv, V2(0.16, 0.86), V2(0.7, 0.32), 0.05)
            cv.add(cv.poly(band(V2(0.36, 0.1), V2(0.68, 0.18), V2(0.92, 0.64), 0.07, 0.07, 18)), xs, "iron", r: 0.035)
            cv.add(cap(cv, V2(0.38, 0.12), V2(0.56, 0.5), 0.01), zero, "string", r: 0.01)
            cv.add(cap(cv, V2(0.9, 0.62), V2(0.56, 0.5), 0.01), zero, "string", r: 0.01)
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
                cv.add(cap(cv, V2(0.86, 0.1), V2(0.86, 0.66), 0.006), zero, "string", r: 0.006)
                cv.add(cv.circle(V2(0.86, 0.7), 0.045), zero, soft(bait), r: 0.04)
            } else {
                cv.add(cap(cv, V2(0.86, 0.1), V2(0.82, 0.5), 0.006), zero, "string", r: 0.006)
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
            cv.add(ring(ellipse(cv, V2(0.36, 0.42), 0.2, 0.14), 0.04), xs, "iron", r: 0.04)
            cv.add(cv.poly([V2(0.5, 0.52), V2(0.72, 0.46), V2(0.86, 0.66), V2(0.7, 0.86), V2(0.5, 0.78)]), ys, "flint", r: 0.08, chamfer: true)
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
            let hull = cv.poly([V2(0.06, 0.46), V2(0.94, 0.46), V2(0.8, 0.76), V2(0.2, 0.76)])
            cv.add(hull, xs, M("wood", base), r: 0.08)
            for yy: Float in [0.56, 0.66] { cv.add(Canvas.intersect(cap(cv, V2(0.06, yy), V2(0.94, yy), 0.008), hull), xs, M("wood", darker(base, 0.6)), r: 0.008) }
            cv.add(cap(cv, V2(0.06, 0.46), V2(0.94, 0.46), 0.03), xs, M("wood", darker(base, 0.8)), r: 0.03)
            if s.mask == "chest_boat" {
                cv.add(cv.poly([V2(0.36, 0.22), V2(0.64, 0.22), V2(0.64, 0.46), V2(0.36, 0.46)]), ys, M("wood", ex["c"] ?? 0x9A6A2A), r: 0.04)
                cv.add(cv.poly([V2(0.47, 0.3), V2(0.53, 0.3), V2(0.53, 0.38), V2(0.47, 0.38)]), ys, "iron", r: 0.02)
            }
            cv.add(cap(cv, V2(0.62, 0.18), V2(0.86, 0.86), 0.022), zero, "handle", r: 0.022)
            cv.add(ellipse(cv, V2(0.84, 0.82), 0.05, 0.09), zero, "handle", r: 0.04)
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
            cv.add(cv.circle(c, 0.13), ys, soft(ex["c"] ?? 0xC03030), r: 0.04)
            cv.add(cv.circle(c, 0.025), ys, soft(0x08080A), r: 0.02)
        case "sherd":
            let d = cv.poly([V2(0.16, 0.24), V2(0.56, 0.14), V2(0.86, 0.3), V2(0.8, 0.74), V2(0.4, 0.86), V2(0.14, 0.66)])
            cv.add(d, ys, M("stone", base), r: 0.1, chamfer: true)
            cv.add(Canvas.intersect(ring(cv.circle(V2(0.5, 0.5), 0.14), 0.025), Canvas.offset(d, 0.06)), ys, M("stone", ex["c"] ?? 0x6A3A2A), r: 0.02)
        case "template":
            cv.add(cv.poly([V2(0.2, 0.12), V2(0.8, 0.12), V2(0.8, 0.88), V2(0.2, 0.88)]), ys, M("stone", base), r: 0.06, chamfer: true)
            cv.add(cv.poly([V2(0.5, 0.26), V2(0.68, 0.5), V2(0.5, 0.74), V2(0.32, 0.5)]), ys, M("metal", ex["c"] ?? 0x6A8AAA), r: 0.06, chamfer: true)
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
            let body = smin(cv.circle(V2(0.5, 0.62), 0.28), cap(cv, V2(0.5, 0.18), V2(0.5, 0.45), key == "lingering" ? 0.07 : 0.085), 0.06)
            cv.add(body, ys, "glass", r: 0.26)
            cv.add(Canvas.intersect(cv.circle(V2(0.5, 0.62), 0.235), neg(cv.below(0.5))), ys, "tint", r: 0.22)
            if key == "splash" { cv.add(cap(cv, V2(0.38, 0.3), V2(0.62, 0.3), 0.03), ys, "glass", r: 0.03) }
            cv.add(cap(cv, V2(0.4, 0.2), V2(0.6, 0.2), 0.032), ys, "glass", r: 0.03)
            cv.add(cv.poly([V2(0.42, 0.05), V2(0.58, 0.05), V2(0.57, 0.19), V2(0.43, 0.19)]), ys, M("wood", key == "lingering" ? 0xB080C8 : 0xA87A4A), r: 0.04)
            cv.add(Canvas.intersect(cv.poly(band(V2(0.33, 0.74), V2(0.3, 0.56), V2(0.4, 0.44), 0.045, 0.02, 10)), Canvas.offset(body, 0.03)), ys, "white", r: 0.02)
        case "egg":
            let d = ellipse(cv, V2(0.5, 0.55), 0.29, 0.37)
            cv.add(d, ys, "tint", r: 0.32)
            for (c, r) in [(V2(0.42, 0.38), Float(0.035)), (V2(0.62, 0.5), 0.042), (V2(0.44, 0.66), 0.032), (V2(0.64, 0.74), 0.028), (V2(0.34, 0.54), 0.025)] {
                cv.add(Canvas.intersect(cv.circle(c, r), Canvas.offset(d, 0.03)), ys, M("soft", 0x3A3436), r: 0.03)
            }
        default:
            arrow(cv, xs, head: "tint")
        }
        return cv
    }
}
