import Foundation
import simd

// Vector item designs by sprite family (Remington's TV playtest item art): every item drawn from the same 16 px mask
// ("ingot", "gem", "dust", "fish", "bucket"...) gets one design coloured by its sprite's base / extra colours, so a
// design covers a whole family (16 dyes, 7 ingots, 20 music discs...). Overlay pairs (potion bottles + liquid, spawn
// eggs + shell, tipped arrows + head) are drawn on one canvas and split: the tinted part becomes the overlay layer.
// Mirrored by tools/itemlab.py (preview without a Mac). Original designs, all procedural.
extension ItemHD {
    // MARK: Helpers

    static let spriteByItem: [String: Sprite] = {
        var m: [String: Sprite] = [:]
        for d in Items.defs { if let s = d.sprite, m[d.name] == nil { m[d.name] = s } }
        return m
    }()

    static let metalByName: [String: String] = ["iron": "iron", "gold": "golden", "copper": "copper", "netherite": "netherite"]

    // A material from "kind:RRGGBB" (dark and light derived from the base colour), or a named one.
    static func material(_ name: String) -> Mat {
        if let m = mats[name] { return m }
        let p = name.split(separator: ":")
        guard p.count == 2, let h = UInt32(p[1], radix: 16) else { return mats["iron"]! }
        let kinds: [Substring: Kind] = ["metal": .metal, "gem": .gem, "wood": .wood, "stone": .stone, "leather": .leather, "soft": .soft]
        let base = hex(h)
        let dark: V3 = base * 0.42 + V3(0.01, 0, 0.03)
        let light: V3 = base + (V3(1, 1, 1) - base) * 0.6
        return Mat(kind: kinds[p[0]] ?? .soft, base: base, dark: dark, light: light)
    }

    static func M(_ kind: String, _ h: UInt32) -> String { kind + ":" + String(format: "%06X", h & 0xFFFFFF) }

    static func darker(_ h: UInt32, _ k: Float) -> UInt32 {
        let r = UInt32(Float((h >> 16) & 255) * k), g = UInt32(Float((h >> 8) & 255) * k), b = UInt32(Float(h & 255) * k)
        return (r << 16) | (g << 8) | b
    }

    static func lighter(_ h: UInt32, _ k: Float) -> UInt32 {
        func f(_ c: UInt32) -> UInt32 { UInt32(Float(c) + (255 - Float(c)) * k) }
        return (f((h >> 16) & 255) << 16) | (f((h >> 8) & 255) << 8) | f(h & 255)
    }

    static func smin(_ a: [Float], _ b: [Float], _ k: Float) -> [Float] {
        zip(a, b).map { x, y in
            let h = simd_clamp(0.5 + 0.5 * (y - x) / k, 0, 1)
            return y * (1 - h) + x * h - k * h * (1 - h)
        }
    }
    static func smax(_ a: [Float], _ b: [Float], _ k: Float) -> [Float] { neg(smin(neg(a), neg(b), k)) }
    static func neg(_ a: [Float]) -> [Float] { a.map { -$0 } }
    static func ring(_ a: [Float], _ w: Float) -> [Float] { a.map { abs($0) - w } }
    static func ellipse(_ cv: Canvas, _ c: V2, _ a: Float, _ b: Float) -> [Float] {
        (0..<(cv.n * cv.n)).map { i in
            let p = cv.p(i)
            return (simd_length(V2((p.x - c.x) / a, (p.y - c.y) / b)) - 1) * min(a, b)
        }
    }
    static func cap(_ cv: Canvas, _ a: V2, _ b: V2, _ r: Float) -> [Float] { cv.capsule(a, b, r).0 }

    // A closed blob of k points round c (radius r, wobble w at phase a).
    static func blob(_ c: V2, _ r: Float, _ k: Int, wobble w: Float = 0, phase a: Float = 0, squash: Float = 1) -> [V2] {
        (0..<k).map { i in
            let t = Float(i) / Float(k) * 2 * .pi
            let rr = r * (1 + w * sinf(t * 2 + a))
            return c + V2(cosf(t + a) * rr, sinf(t + a) * rr * squash)
        }
    }

    // MARK: Families

    static func family(_ cv: Canvas, _ name: String, _ s: Sprite) -> Bool {
        let ys = cv.axis(V2(0.5, 0), V2(0.5, 1)), xs = cv.axis(V2(0, 0.5), V2(1, 0.5))
        let base = s.base, ex = s.extras
        let zero = [Float](repeating: 0, count: cv.n * cv.n)
        func soft(_ h: UInt32) -> String { M("soft", h) }
        switch s.mask {
        case "ingot":
            let brick = name.contains("brick")
            let m = metalByName[String(name.split(separator: "_")[0])] ?? M(brick ? "stone" : "metal", base)
            // A bar in three-quarter view: a sloped top, a front, an end, all tapering (critic: the flat-topped
            // version read as a lidded box).
            let top = cv.poly([V2(0.28, 0.38), V2(0.68, 0.29), V2(0.8, 0.36), V2(0.42, 0.46)])
            let front = cv.poly([V2(0.42, 0.46), V2(0.8, 0.36), V2(0.92, 0.56), V2(0.44, 0.72)])
            let end = cv.poly([V2(0.28, 0.38), V2(0.42, 0.46), V2(0.44, 0.72), V2(0.12, 0.56)])
            cv.add(end, xs, m, r: 0.03, chamfer: true)
            cv.add(front, xs, m, r: 0.03, chamfer: true)
            cv.add(top, xs, m, r: 0.03, chamfer: true)
            if !brick { cv.add(cv.poly(band(V2(0.4, 0.38), V2(0.52, 0.35), V2(0.68, 0.33), 0.022, 0.01, 8)), xs, M("soft", 0xFFFFFF), r: 0.01) }
        case "nugget":
            let m = metalByName[String(name.split(separator: "_")[0])] ?? M("metal", base)
            for (c, r) in [(V2(0.36, 0.6), Float(0.15)), (V2(0.62, 0.66), 0.13), (V2(0.52, 0.4), 0.12)] {
                cv.add(cv.poly(blob(c, r, 8, wobble: 0.15, phase: c.x * 9)), ys, m, r: 0.08, chamfer: true)
            }
        case "lump":
            let d = cv.poly([V2(0.22, 0.34), V2(0.4, 0.2), V2(0.62, 0.22), V2(0.8, 0.36), V2(0.84, 0.58), V2(0.7, 0.8), V2(0.42, 0.84), V2(0.2, 0.68)])
            if name == "coal" {
                cv.add(d, ys, M("gem", 0x2A2E36), r: 0.2, chamfer: true)            // faceted, with a blue-grey sheen
            } else if name == "charcoal" {
                cv.add(d, ys, M("wood", 0x4A3426), r: 0.2, chamfer: true)           // a burnt wood chunk, its grain showing
            } else {
                cv.add(d, ys, M("stone", base), r: 0.2, chamfer: true)
            }
            if name.hasPrefix("raw_") {
                let mm = metalByName[String(name.dropFirst(4))] ?? M("metal", base)
                for (c, r, a) in [(V2(0.4, 0.42), Float(0.08), Float(0.3)), (V2(0.63, 0.58), 0.07, 1.2), (V2(0.38, 0.67), 0.06, 2.0)] {
                    cv.add(Canvas.intersect(cv.poly(blob(c, r, 7, wobble: 0.3, phase: a, squash: 0.8)), Canvas.offset(d, 0.03)), ys, mm, r: 0.05, chamfer: true)
                }
            }
        case "gem":
            gem(cv, name, base, ys)
        case "dust":
            let m = soft(base)
            // A lumpy heap of three mounds (critic: white grain speckle read as mould at a distance).
            let mound = smin(smin(cv.circle(V2(0.36, 0.78), 0.22), cv.circle(V2(0.62, 0.76), 0.24), 0.08), cv.circle(V2(0.5, 0.6), 0.2), 0.08)
            cv.add(Canvas.intersect(mound, cv.below(0.84)), ys, m, r: 0.12)
        case "ball":
            let d = cv.circle(V2(0.5, 0.54), 0.31)
            cv.add(d, ys, M(name == "heart_of_the_sea" ? "gem" : "soft", base), r: 0.31)
            if name == "slime_ball" { cv.add(cv.circle(V2(0.55, 0.6), 0.13), ys, soft(darker(base, 0.6)), r: 0.13) }
            if name == "magma_cream" {
                cv.add(Canvas.intersect(cv.poly(band(V2(0.28, 0.56), V2(0.5, 0.3), V2(0.72, 0.56), 0.06, 0.06, 12)), d), ys, soft(0xF8C030), r: 0.03)
            }
            if name == "wind_charge" {
                cv.add(Canvas.intersect(cv.poly(band(V2(0.3, 0.64), V2(0.5, 0.2), V2(0.72, 0.5), 0.05, 0.02, 12)), Canvas.offset(d, 0.02)), ys, soft(0xF4F8FF), r: 0.03)
            }
        case "pearl":
            cv.add(cv.circle(V2(0.5, 0.52), 0.32), ys, "pearl", r: 0.32)
            cv.add(ellipse(cv, V2(0.5, 0.52), 0.14, 0.09), ys, M("gem", 0x2AB89A), r: 0.06)
        case "seeds":
            for (x, y, a) in [(Float(0.32), Float(0.36), Float(0.5)), (0.58, 0.3, -0.4), (0.7, 0.56, 0.9), (0.42, 0.6, -0.2), (0.28, 0.78, 0.3), (0.58, 0.8, -0.8)] {
                let pts: [V2] = (0..<12).map { i in
                    let t = Float(i) / 12 * 2 * .pi
                    let ox = cosf(t) * 0.09, oy = sinf(t) * 0.055
                    return V2(x + ox * cosf(a) - oy * sinf(a), y + ox * sinf(a) + oy * cosf(a))
                }
                cv.add(cv.poly(pts), ys, soft(base), r: 0.05)
            }
        case "wheat":
            // A sheaf: stalks gathered at a tie low down and fanning out to the ears (critic: three posts and a bar
            // read as an easel).
            let foot = V2(0.5, 0.92), tie = V2(0.5, 0.68)
            for tip in [V2(0.24, 0.16), V2(0.38, 0.1), V2(0.52, 0.08), V2(0.66, 0.1), V2(0.8, 0.16)] {
                let a: V2 = foot + (tie - foot) * 0.0
                cv.add(cap(cv, a, tie, 0.018), zero, soft(darker(base, 0.85)), r: 0.018)
                cv.add(cap(cv, tie, tip, 0.016), zero, soft(darker(base, 0.85)), r: 0.016)
                for j in 0..<4 {
                    let t: Float = 0.06 + Float(j) * 0.08
                    cv.add(ellipse(cv, tip + (tie - tip) * t, 0.035, 0.05), zero, "wheat", r: 0.035)
                }
            }
            cv.add(cap(cv, V2(0.42, 0.68), V2(0.58, 0.68), 0.035), zero, "stem", r: 0.035)
        case "egg":
            cv.add(ellipse(cv, V2(0.5, 0.55), 0.27, 0.35), ys, soft(base), r: 0.3)
            let dots = darker(base, 0.75)
            for c in [V2(0.42, 0.4), V2(0.6, 0.5), V2(0.46, 0.66), V2(0.62, 0.72), V2(0.36, 0.56)] {
                cv.add(Canvas.intersect(cv.circle(c, 0.026), ellipse(cv, V2(0.5, 0.55), 0.24, 0.32)), ys, soft(dots), r: 0.02)
            }
        case "bucket":
            bucket(cv, name, ex, xs)
        case "bottle":
            let glass = "glass"
            let body = Canvas.union(cv.circle(V2(0.5, 0.62), 0.27), cap(cv, V2(0.5, 0.2), V2(0.5, 0.45), 0.08))
            cv.add(body, ys, glass, r: 0.25)
            if let liquid = ex["c"] {
                cv.add(Canvas.intersect(cv.circle(V2(0.5, 0.62), 0.23), neg(cv.below(0.52))), ys, soft(liquid), r: 0.2)
            }
            cv.add(cap(cv, V2(0.42, 0.22), V2(0.58, 0.22), 0.03), ys, glass, r: 0.03)
            cv.add(cv.poly([V2(0.43, 0.08), V2(0.57, 0.08), V2(0.56, 0.2), V2(0.44, 0.2)]), ys, M("wood", 0xA87A4A), r: 0.04)
            cv.add(Canvas.intersect(cv.poly(band(V2(0.34, 0.74), V2(0.3, 0.56), V2(0.4, 0.44), 0.04, 0.02, 10)), Canvas.offset(body, 0.03)), ys, "white", r: 0.02)
        case "fish":
            let m = soft(base)
            cv.add(cv.poly([V2(0.34, 0.42), V2(0.48, 0.26), V2(0.62, 0.4)]), xs, soft(darker(base, 0.8)), r: 0.03)
            cv.add(cv.poly([V2(0.72, 0.52), V2(0.92, 0.34), V2(0.88, 0.52), V2(0.92, 0.7)]), xs, m, r: 0.05)
            let body = ellipse(cv, V2(0.46, 0.52), 0.3, 0.17)
            cv.add(body, xs, m, r: 0.17)
            cv.add(cv.circle(V2(0.27, 0.48), 0.035), xs, soft(0x18181C), r: 0.03)
            cv.add(Canvas.intersect(cap(cv, V2(0.3, 0.6), V2(0.64, 0.58), 0.012), Canvas.offset(body, 0.03)), xs, soft(lighter(base, 0.4)), r: 0.01)
        default:
            return food(cv, name, s, ys, xs, zero) || gear(cv, name, s, ys, xs, zero)
        }
        return true
    }

    static func gem(_ cv: Canvas, _ name: String, _ base: UInt32, _ ys: [Float]) {
        let m = M("gem", base)
        switch name {
        case "diamond":
            cv.add(cv.poly([V2(0.28, 0.2), V2(0.72, 0.2), V2(0.9, 0.4), V2(0.5, 0.9), V2(0.1, 0.4)]), ys, "diamond", r: 0.1, chamfer: true)
            cv.add(cv.poly([V2(0.28, 0.2), V2(0.72, 0.2), V2(0.62, 0.4), V2(0.38, 0.4)]), ys, "diamond", r: 0.06, chamfer: true)
        case "emerald":
            cv.add(cv.poly([V2(0.5, 0.08), V2(0.78, 0.26), V2(0.78, 0.7), V2(0.5, 0.92), V2(0.22, 0.7), V2(0.22, 0.26)]), ys, "emerald", r: 0.12, chamfer: true)
            cv.add(cv.poly([V2(0.5, 0.24), V2(0.64, 0.34), V2(0.64, 0.62), V2(0.5, 0.74), V2(0.36, 0.62), V2(0.36, 0.34)]), ys, "emerald", r: 0.06, chamfer: true)
        case "lapis_lazuli":
            let d = cv.poly([V2(0.24, 0.3), V2(0.5, 0.18), V2(0.8, 0.32), V2(0.78, 0.66), V2(0.5, 0.84), V2(0.2, 0.68)])
            cv.add(d, ys, M("stone", base), r: 0.14, chamfer: true)
            for c in [V2(0.4, 0.4), V2(0.6, 0.6), V2(0.38, 0.64)] {
                cv.add(Canvas.intersect(cv.circle(c, 0.035), Canvas.offset(d, 0.05)), ys, "golden", r: 0.03)
            }
        default:
            // Crystal shards: pointed prisms.
            for (a, b, w) in [(V2(0.3, 0.86), V2(0.42, 0.14), Float(0.13)), (V2(0.56, 0.86), V2(0.76, 0.3), 0.11), (V2(0.3, 0.86), V2(0.18, 0.42), 0.08)] {
                let dr = simd_normalize(b - a), nr = V2(-dr.y, dr.x), ln = simd_length(b - a)
                let mid: V2 = a + dr * (ln * 0.78)
                let pts: [V2] = [a + nr * (w / 2), mid + nr * (w / 2), b, mid - nr * (w / 2), a - nr * (w / 2)]
                cv.add(cv.poly(pts), cv.axis(a, b), m, r: w / 2, chamfer: true)
            }
        }
    }

    static func bucket(_ cv: Canvas, _ name: String, _ ex: [Character: UInt32], _ xs: [Float]) {
        let body = cv.poly([V2(0.2, 0.38), V2(0.8, 0.38), V2(0.72, 0.86), V2(0.28, 0.86)])
        cv.add(Canvas.intersect(ring(ellipse(cv, V2(0.5, 0.38), 0.33, 0.3), 0.014), cv.below(0.38)), xs, "iron", r: 0.014)   // the handle
        cv.add(body, xs, "iron", r: 0.22)
        for yy: Float in [0.52, 0.74] { cv.add(Canvas.intersect(cap(cv, V2(0.18, yy), V2(0.82, yy), 0.012), body), xs, "iron", r: 0.012) }
        let surface = ellipse(cv, V2(0.5, 0.38), 0.29, 0.065)
        let c = ex["c"] ?? 0x5A5A5A
        switch name {
        case "bucket": cv.add(surface, xs, M("soft", 0x3A3A40), r: 0.03)
        case "water_bucket", "lava_bucket", "milk_bucket", "powder_snow_bucket": cv.add(surface, xs, M("soft", c), r: 0.03)
        default:                                                            // a bucket of fish / axolotl / tadpole
            cv.add(surface, xs, M("soft", 0x3F76E4), r: 0.03)
            // The fish pokes out above the rim (critic: it was tiny).
            let fish = Canvas.union(ellipse(cv, V2(0.46, 0.26), 0.17, 0.1), cv.poly([V2(0.6, 0.26), V2(0.76, 0.12), V2(0.74, 0.36)]))
            cv.add(Canvas.intersect(fish, cv.below(0.4)), xs, M("soft", c), r: 0.08)
            cv.add(cv.circle(V2(0.36, 0.23), 0.022), xs, M("soft", 0x101014), r: 0.02)
        }
        cv.add(ring(ellipse(cv, V2(0.5, 0.38), 0.3, 0.075), 0.016), xs, "iron", r: 0.016)
    }

    // MARK: Food

    static func food(_ cv: Canvas, _ name: String, _ s: Sprite, _ ys: [Float], _ xs: [Float], _ zero: [Float]) -> Bool {
        let base = s.base, ex = s.extras
        func soft(_ h: UInt32) -> String { M("soft", h) }
        switch s.mask {
        case "apple_shape":
            let m = name.contains("golden") ? "golden" : soft(base)
            var body = smin(cv.circle(V2(0.38, 0.58), 0.27), cv.circle(V2(0.62, 0.58), 0.27), 0.12)
            body = smax(body, neg(cv.circle(V2(0.5, 0.29), 0.07)), 0.05)
            cv.add(body, ys, m, r: 0.27)
            cv.add(cap(cv, V2(0.5, 0.36), V2(0.55, 0.15), 0.028), ys, "stem", r: 0.028)
            let leaf = band(V2(0.55, 0.23), V2(0.68, 0.09), V2(0.84, 0.18), 0.02, 0.02, 8) + band(V2(0.84, 0.18), V2(0.7, 0.3), V2(0.55, 0.23), 0.02, 0.02, 8)
            cv.add(cv.poly(leaf), xs, "leaf", r: 0.04)
        case "carrot":
            let m = name.contains("golden") ? "golden" : soft(base)
            let d = cv.poly(band(V2(0.3, 0.3), V2(0.5, 0.5), V2(0.84, 0.86), 0.2, 0.02, 14))
            cv.add(d, xs, m, r: 0.1)
            for (a, b) in [(V2(0.42, 0.42), V2(0.48, 0.36)), (V2(0.56, 0.6), V2(0.63, 0.55)), (V2(0.68, 0.72), V2(0.73, 0.68))] {
                cv.add(Canvas.intersect(cap(cv, a, b, 0.01), Canvas.offset(d, 0.02)), xs, soft(darker(base, 0.7)), r: 0.01)
            }
            let root = V2(0.31, 0.31)
            for a in [V2(0.12, 0.1), V2(0.22, 0.05), V2(0.08, 0.24), V2(0.3, 0.08)] {
                let mid: V2 = (root + a) * 0.5 + V2(0.02, -0.02)
                cv.add(cv.poly(band(root, mid, a, 0.06, 0.01, 8)), xs, "leaf", r: 0.03)
            }
        case "potato":
            let m = soft(base)
            if name == "beetroot" {
                cv.add(cv.poly(band(V2(0.5, 0.3), V2(0.56, 0.62), V2(0.5, 0.92), 0.5, 0.02, 14)), ys, m, r: 0.2)
                for a in [V2(0.36, 0.06), V2(0.5, 0.04), V2(0.64, 0.08)] {
                    cv.add(cv.poly(band(V2(0.5, 0.26), V2(0.5, 0.16), a, 0.06, 0.02, 8)), ys, "leaf", r: 0.03)
                }
            } else {
                let d = ellipse(cv, V2(0.5, 0.54), 0.34, 0.26)
                cv.add(d, xs, m, r: 0.24)
                for c in [V2(0.36, 0.48), V2(0.58, 0.44), V2(0.5, 0.64), V2(0.7, 0.6)] {
                    cv.add(Canvas.intersect(cv.circle(c, 0.022), Canvas.offset(d, 0.03)), xs, soft(darker(base, 0.6)), r: 0.02)
                }
                if name == "baked_potato" {
                    cv.add(Canvas.intersect(cv.poly(band(V2(0.3, 0.46), V2(0.5, 0.36), V2(0.72, 0.46), 0.08, 0.06, 12)), Canvas.offset(d, 0.02)), xs, soft(0xF8E8A0), r: 0.03)
                }
            }
        case "berries":
            if name.contains("chorus") {
                // A lumpy, segmented fruit (critic: a smooth ball read as a bowling ball).
                var d = cv.circle(V2(0.5, 0.56), 0.22)
                for k in 0..<6 {
                    let a = Float(k) * .pi / 3 + 0.3
                    d = smin(d, cv.circle(V2(0.5, 0.56) + V2(cosf(a), sinf(a)) * 0.16, 0.13), 0.04)
                }
                cv.add(d, ys, M("leather", base), r: 0.3)
                for c in [V2(0.38, 0.46), V2(0.6, 0.48), V2(0.5, 0.68)] {
                    cv.add(Canvas.intersect(cv.circle(c, 0.07), Canvas.offset(d, 0.03)), ys, soft(lighter(base, 0.3)), r: 0.05)
                }
            } else {
                cv.add(cap(cv, V2(0.5, 0.14), V2(0.36, 0.46), 0.018), ys, "stem", r: 0.018)
                cv.add(cap(cv, V2(0.5, 0.14), V2(0.62, 0.44), 0.018), ys, "stem", r: 0.018)
                for c in [V2(0.36, 0.5), V2(0.6, 0.48), V2(0.48, 0.7), V2(0.7, 0.7), V2(0.3, 0.72)] { cv.add(cv.circle(c, 0.12), ys, soft(base), r: 0.12) }
                cv.add(cv.poly(band(V2(0.5, 0.16), V2(0.66, 0.08), V2(0.78, 0.18), 0.08, 0.01, 8)), xs, "leaf", r: 0.03)
            }
        case "steak", "chop":
            let fat = soft(ex["c"] ?? 0xF0E0D0)
            var d: [Float]
            if s.mask == "steak" {
                d = smin(ellipse(cv, V2(0.42, 0.5), 0.3, 0.26), ellipse(cv, V2(0.66, 0.6), 0.22, 0.2), 0.1)
                d = smax(d, neg(ellipse(cv, V2(0.6, 0.2), 0.14, 0.1)), 0.06)          // the kidney notch
            } else {
                d = smin(ellipse(cv, V2(0.56, 0.6), 0.32, 0.25), cv.circle(V2(0.74, 0.46), 0.14), 0.1)       // a rib chop
            }
            for i in 0..<d.count {                                                  // a cut, uneven edge
                let p = cv.p(i)
                d[i] += (vnoise(p.x, p.y, 9, 21) - 0.5) * 0.02
            }
            cv.add(d, ys, fat, r: 0.1)
            cv.add(Canvas.offset(d, 0.04), ys, soft(base), r: 0.16)
            if s.mask == "chop" {
                // The rib bone runs out of the top-left of the cut (critic: the low-left bone read as a drumstick).
                cv.add(cap(cv, V2(0.4, 0.48), V2(0.14, 0.16), 0.04), ys, "bone", r: 0.04)
                cv.add(cv.circle(V2(0.12, 0.13), 0.055), ys, "bone", r: 0.05)
                cv.add(Canvas.intersect(cv.circle(V2(0.62, 0.6), 0.07), Canvas.offset(d, 0.07)), ys, fat, r: 0.05)
            } else {
                for (p0, c0, p1) in [(V2(0.24, 0.44), V2(0.36, 0.36), V2(0.5, 0.46)), (V2(0.5, 0.62), V2(0.62, 0.52), V2(0.78, 0.6)),
                                     (V2(0.3, 0.6), V2(0.38, 0.68), V2(0.48, 0.64))] {
                    cv.add(Canvas.intersect(cv.poly(band(p0, c0, p1, 0.022, 0.012, 10)), Canvas.offset(d, 0.06)), ys, fat, r: 0.012)
                }
            }
        case "drumstick":
            let bone = soft(ex["c"] ?? 0xF0E8E0)
            cv.add(cap(cv, V2(0.3, 0.7), V2(0.12, 0.88), 0.045), ys, bone, r: 0.045)
            cv.add(cv.circle(V2(0.1, 0.84), 0.05), ys, bone, r: 0.05)
            cv.add(cv.circle(V2(0.15, 0.9), 0.05), ys, bone, r: 0.05)
            cv.add(Canvas.union(ellipse(cv, V2(0.58, 0.42), 0.3, 0.24), cap(cv, V2(0.5, 0.5), V2(0.3, 0.7), 0.1)), xs, soft(base), r: 0.22)
        case "bread":
            let d = cap(cv, V2(0.2, 0.6), V2(0.8, 0.44), 0.2)
            cv.add(d, xs, soft(base), r: 0.2)
            for k in 0..<3 {
                let cx: Float = 0.34 + Float(k) * 0.16, cy: Float = 0.56 - Float(k) * 0.04
                cv.add(Canvas.intersect(cap(cv, V2(cx - 0.05, cy - 0.12), V2(cx + 0.03, cy + 0.06), 0.02), Canvas.offset(d, 0.03)), xs, soft(lighter(base, 0.4)), r: 0.02)
            }
        case "cookie":
            let d = cv.circle(V2(0.5, 0.52), 0.32)
            cv.add(d, ys, soft(base), r: 0.1)
            for c in [V2(0.4, 0.4), V2(0.62, 0.46), V2(0.46, 0.64), V2(0.66, 0.66), V2(0.32, 0.56)] {
                cv.add(Canvas.intersect(cv.circle(c, 0.04), Canvas.offset(d, 0.04)), ys, soft(0x4A2A14), r: 0.03)
            }
        case "melon":
            cv.add(cv.poly([V2(0.12, 0.34), V2(0.88, 0.34), V2(0.5, 0.9)]), xs, soft(name.contains("glister") ? 0xE8B830 : 0x3A8A2A), r: 0.08)
            cv.add(cv.poly([V2(0.2, 0.34), V2(0.8, 0.34), V2(0.5, 0.8)]), xs, soft(base), r: 0.1, chamfer: true)
            for c in [V2(0.38, 0.44), V2(0.6, 0.44), V2(0.5, 0.58)] { cv.add(ellipse(cv, c, 0.018, 0.03), xs, soft(0x1A1A1A), r: 0.02) }
        case "stew", "bowl":
            cv.add(Canvas.intersect(ellipse(cv, V2(0.5, 0.5), 0.4, 0.34), neg(cv.below(0.5))), xs, M("wood", 0x8A6435), r: 0.2)
            if s.mask == "stew" {
                cv.add(ellipse(cv, V2(0.5, 0.5), 0.36, 0.09), xs, soft(name == "beetroot_soup" ? base : (ex["d"] ?? base)), r: 0.05)
                for c in [V2(0.38, 0.49), V2(0.56, 0.47), V2(0.64, 0.52)] {
                    cv.add(ellipse(cv, c, 0.05, 0.025), xs, soft(ex["c"] ?? lighter(base, 0.3)), r: 0.02)
                }
            } else {
                cv.add(ellipse(cv, V2(0.5, 0.5), 0.34, 0.08), xs, M("wood", 0x5A3D1F), r: 0.04)
            }
            cv.add(ring(ellipse(cv, V2(0.5, 0.5), 0.38, 0.1), 0.015), xs, M("wood", 0xA07A48), r: 0.015)
        case "pie":
            let dish = Canvas.intersect(ellipse(cv, V2(0.5, 0.52), 0.42, 0.3), neg(cv.below(0.5)))
            cv.add(Canvas.union(dish, ellipse(cv, V2(0.5, 0.5), 0.42, 0.16)), xs, soft(0xC8883E), r: 0.12)
            let top = ellipse(cv, V2(0.5, 0.5), 0.36, 0.12)
            cv.add(top, xs, soft(base), r: 0.06)
            for x: Float in [0.36, 0.5, 0.64] {
                cv.add(Canvas.intersect(cap(cv, V2(x - 0.04, 0.4), V2(x + 0.04, 0.6), 0.014), top), xs, soft(0xE8B060), r: 0.012)
            }
        case "rotten":
            let d = cv.poly([V2(0.16, 0.44), V2(0.36, 0.26), V2(0.68, 0.24), V2(0.86, 0.42), V2(0.8, 0.68), V2(0.52, 0.8), V2(0.22, 0.7)])
            cv.add(d, ys, soft(base), r: 0.15)
            for c in [V2(0.4, 0.42), V2(0.64, 0.56), V2(0.42, 0.64)] { cv.add(Canvas.intersect(cv.circle(c, 0.06), Canvas.offset(d, 0.03)), ys, soft(0x4A6A2A), r: 0.04) }
        default:
            return false
        }
        return true
    }
}
