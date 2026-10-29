import Foundation
import simd

// P292 (b): hell's own looks. The Emberdeep's ground, trees and plants were the reference nether's (red rack, crimson
// and teal mushroom forests, soul sand, a glowstone ceiling); its blocks keep their save keys but draw as hell's own
// lands (HellLands.swift):
//   Cinderstone (netherrack)     charcoal-umber rock split by hairline seams that glow like a dying fire
//   Pale Ash / Ash Silt          the Ash Dunes' drifts (soul sand) and the packed ash under them (soul soil)
//   Ember Moss / Gloam Moss      rust moss threads with glowing tips; violet lichen (the two forests' turf)
//   Charwood                     charred black bark with cracks that still glow, dark smoky planks
//   Gloamwood                    pale lilac bark veined with violet light, lilac-grey planks
//   Ember Frond / Gloam Frond    the trees' foliage: layered feathery fronds (not lumps of wart)
//   Ember Pod                    a ribbed seed pod glowing from inside (shroomlight)
//   Lumenstone                   amber crystal clusters (glowstone)
//   Brimroot                     a gnarled root crown (the crop on Pale Ash: nether wart)
//   Sulfur Crust                 the Sulfur Flats' yellow crust, cracked into plates
// They are painted from these generators even where an imported picture exists (TextureGen.painted).
enum HellLooks {
    static let painted: Set<String> = [
        "netherrack", "nether_gold_ore", "nether_quartz_ore", "soul_sand", "soul_soil",
        "crimson_nylium", "crimson_nylium_side", "warped_nylium", "warped_nylium_side",
        "crimson_stem", "crimson_stem@r", "crimson_stem_top", "warped_stem", "warped_stem@r", "warped_stem_top",
        "stripped_crimson_log", "stripped_crimson_log@r", "stripped_crimson_log_top",
        "stripped_warped_log", "stripped_warped_log@r", "stripped_warped_log_top",
        "crimson_planks", "warped_planks", "crimson_door_top", "crimson_door_bottom", "crimson_trapdoor",
        "warped_door_top", "warped_door_bottom", "warped_trapdoor",
        "nether_wart_block", "warped_wart_block", "shroomlight", "glowstone",
        "crimson_fungus", "warped_fungus", "crimson_roots", "warped_roots", "weeping_vines", "twisting_vines",
        "nether_wart_stage0", "nether_wart_stage1", "nether_wart_stage2", "item_nether_wart", "sulfur_crust",
    ]

    typealias Gen = HDTex.Gen
    static func col(_ h: UInt32) -> V3 { HDTex.col(h) }

    // MARK: Ground

    static let cinderRock: Gen = HDTex.stone([(0, 0x15100D), (0.35, 0x241C17), (0.7, 0x362B23), (1, 0x4B3D32)], veins: 0.35, strata: 0.03)
    static let cinderstone: Gen = seams(cinderRock, cells: 5, share: 0.42, hot: 0xFF6A1A)
    static let ashSilt: Gen = HDTex.soil([(0, 0x4E4842), (0.5, 0x645C55), (1, 0x7C736A)], pebble: 0x2E2A26, pebbles: 10, clods: 6)
    static let paleAsh: Gen = rippled(HDTex.soil([(0, 0x847E74), (0.5, 0xA29C90), (1, 0xC0BAAE)], pebble: 0x4A4640, pebbles: 16, clods: 4))
    static let emberMoss: Gen = fibres(HDTex.soil([(0, 0x150D0A), (0.5, 0x241410), (1, 0x341C14)], pebble: 0xC04A1A, pebbles: 14, clods: 8),
                                       colour: 0x7A3218, tip: 0xFF8A34, count: 150, salt: 11)
    static let gloamMoss: Gen = fibres(HDTex.soil([(0, 0x110F18), (0.5, 0x1C1828), (1, 0x2A2438)], pebble: 0x6A5AB0, pebbles: 10, clods: 8),
                                       colour: 0x4A3E86, tip: 0xB4A2FF, count: 150, salt: 13)
    static let sulfurCrust: Gen = sulfur()

    // A rock's hairline seams glowing: the edges of a warped cell net, only where a mask lets them through.
    static func seams(_ base: @escaping Gen, cells: Int, share: Float, hot: UInt32) -> Gen {
        { n, s in
            var img = base(n, s)
            let v = HDTex.voronoi(n, cells, s &+ 91, jitter: 0.95)
            let mask = HDTex.fbm(n, n / 4, 3, s &+ 92)
            let hc = col(hot)
            let w: Float = Float(n) / 110
            for i in 0..<(n * n) {
                let edge: Float = v.f2[i] - v.f1[i]
                guard edge < w * 2.4, mask[i] > 1 - share else { continue }
                let k: Float = HDTex.cl(1 - edge / (w * 2.4))
                let m: Float = HDTex.cl((mask[i] - (1 - share)) / 0.12)
                let glow: Float = k * k * m
                let core: Float = edge < w * 0.7 ? 0.35 * m : 0
                let p = img.px[i]
                let c: V3 = V3(p.x, p.y, p.z) * (1 - glow) + hc * glow + V3(core, core * 0.6, core * 0.2)
                img.px[i] = V4(min(1, c.x), min(1, c.y), min(1, c.z), p.w)
            }
            return img
        }
    }

    // Wind ripples over a drift (soft bright and dark bands along a wandering direction).
    static func rippled(_ base: @escaping Gen) -> Gen {
        { (n: Int, s: Int) -> HDTex.Img in
            var img = base(n, s)
            let w = HDTex.fbm(n, n / 4, 2, s &+ 41)
            let fn = Float(n)
            for y in 0..<n { for x in 0..<n {
                let i = y * n + x
                let ph: Float = (Float(y) + Float(x) * 0.25) / fn * 2 * Float.pi * 6 + (w[i] - 0.5) * 5
                let k: Float = 0.94 + 0.09 * sinf(ph)
                let p = img.px[i]
                img.px[i] = V4(min(1, p.x * k), min(1, p.y * k), min(1, p.z * k), p.w)
            } }
            return img
        }
    }

    // Moss or lichen: short curved threads laid over a ground, brightening to their tips (wrapping, so it tiles).
    static func fibres(_ base: @escaping Gen, colour: UInt32, tip: UInt32, count: Int, salt: Int) -> Gen {
        { n, s in
            var img = base(n, s)
            let fn = Float(n)
            let c0 = col(colour), c1 = col(tip)
            for f in 0..<count {
                func r(_ k: Int) -> Float { HDTex.h2(f, k, salt &+ s) }
                var x: Float = r(0) * fn, y: Float = r(1) * fn
                var a: Float = r(2) * 2 * Float.pi
                let len: Float = fn * (0.05 + 0.08 * r(3))
                let bend: Float = (r(4) - 0.5) * 0.25
                let tone: Float = 0.8 + 0.4 * r(5)
                let steps = Int(len)
                for k in 0..<max(1, steps) {
                    let t: Float = Float(k) / Float(max(1, steps))
                    let c: V3 = (c0 * (1 - t * t) + c1 * (t * t)) * tone
                    img[Int(x), Int(y)] = V4(min(1, c.x), min(1, c.y), min(1, c.z), 1)
                    if t < 0.5 { img[Int(x) + 1, Int(y)] = V4(c.x * 0.7, c.y * 0.7, c.z * 0.7, 1) }
                    x += cosf(a); y += sinf(a); a += bend
                }
            }
            return img
        }
    }

    // Yellow crust in plates, darker cracks between them, pale bloom at the plate edges, a few dark vent pits.
    static func sulfur() -> Gen {
        { n, s in
            let fn = Float(n)
            var img = HDTex.Img(n)
            let v = HDTex.voronoi(n, 6, s &+ 7, jitter: 0.95)
            let pits = HDTex.voronoi(n, 3, s &+ 9, jitter: 0.9)
            let f = HDTex.fbm(n, n / 4, 4, s)
            let fine = HDTex.vnoise(n, max(1, n / 64), s &+ 2)
            var hh = [Float](repeating: 0, count: n * n)
            let pal: [(Float, UInt32)] = [(0, 0x6A5A12), (0.35, 0xA88E1C), (0.7, 0xD4B830), (1, 0xF0DC6A)]
            for i in 0..<(n * n) {
                let edge: Float = v.f2[i] - v.f1[i]
                let crack: Bool = edge < fn / 70
                let rim: Float = HDTex.cl(1 - edge / (fn / 18))
                var t: Float = 0.45 + (f[i] - 0.5) * 0.5 + (v.id[i] - 0.5) * 0.2 + (fine[i] - 0.5) * 0.12 + rim * 0.25
                if crack { t = 0.05 }
                let pit: Bool = pits.id[i] > 0.6 && pits.f1[i] < fn / 28
                if pit { t = 0.0 }
                var c = HDTex.ramp(t, pal)
                if pit { c = col(0x2A2410) }
                img.px[i] = V4(c.x, c.y, c.z, 1)
                hh[i] = crack || pit ? -0.4 : rim * 0.15 + f[i] * 0.1
            }
            HDTex.shade(&img, hh, 1.0)
            return img
        }
    }

    // MARK: Wood

    static let charBark: [(Float, UInt32)] = [(0, 0x0B0806), (0.5, 0x1C1410), (1, 0x2E221A)]
    static let gloamBark: [(Float, UInt32)] = [(0, 0x363046), (0.5, 0x524A66), (1, 0x726886)]

    // Bark with thin glowing cracks running up it (wandering, broken lines).
    static func glowCracks(_ base: @escaping Gen, hot: UInt32, lines: Int, strength: Float) -> Gen {
        { n, s in
            var img = base(n, s)
            let fn = Float(n)
            let hc = col(hot)
            let gate = HDTex.vnoise(n, max(1, n / 8), s &+ 77)
            for l in 0..<lines {
                let x0: Float = (Float(l) + HDTex.h2(l, 1, s)) / Float(lines) * fn
                let ph: Float = HDTex.h2(l, 2, s) * 6.28
                for y in 0..<n {
                    let g: Float = gate[y * n + Int(x0) % n]
                    guard g > 0.45 else { continue }
                    let cx: Float = x0 + sinf(Float(y) / fn * 2 * Float.pi * 2 + ph) * fn * 0.02
                    let k: Float = HDTex.cl((g - 0.45) / 0.15) * strength
                    for dx in -1...1 {
                        let x = Int(cx) + dx
                        let p = img[x, y]
                        let w: Float = dx == 0 ? k : k * 0.4
                        let c: V3 = V3(p.x, p.y, p.z) * (1 - w) + hc * w
                        img[x, y] = V4(min(1, c.x), min(1, c.y), min(1, c.z), 1)
                    }
                }
            }
            return img
        }
    }

    // An end grain with a glowing heart (charwood still burns inside).
    static func heart(_ base: @escaping Gen, hot: UInt32, radius: Float) -> Gen {
        { n, s in
            var img = base(n, s)
            let fn = Float(n), hc = col(hot)
            for y in 0..<n { for x in 0..<n {
                let dx: Float = Float(x) + 0.5 - fn / 2, dy: Float = Float(y) + 0.5 - fn / 2
                let d: Float = (dx * dx + dy * dy).squareRoot() / (fn * radius)
                guard d < 1 else { continue }
                let k: Float = (1 - d) * (1 - d) * 0.9
                let p = img.px[y * n + x]
                let c: V3 = V3(p.x, p.y, p.z) * (1 - k) + hc * k
                img.px[y * n + x] = V4(min(1, c.x), min(1, c.y), min(1, c.z), 1)
            } }
            return img
        }
    }

    // MARK: Foliage, pods, crystal

    // Layered feathery fronds packed into a block (wrapping), darker deep in, bright at the tips.
    static func fronds(dark: UInt32, mid: UInt32, tip: UInt32, salt: Int) -> Gen {
        { (n: Int, s: Int) -> HDTex.Img in
            let fn = Float(n)
            var img = HDTex.Img(n, V4(col(dark).x, col(dark).y, col(dark).z, 1))
            let cd = col(dark), cm = col(mid), ct = col(tip)
            for f in 0..<70 {
                func r(_ k: Int) -> Float { HDTex.h2(f, k, salt &+ s) }
                let cx: Float = r(0) * fn, cy: Float = r(1) * fn
                let len: Float = fn * (0.14 + 0.1 * r(2))
                let ang: Float = r(3) * 2 * Float.pi
                let depth: Float = Float(f) / 70                      // later fronds lie on top
                let base: V3 = cd * (1 - depth) + cm * depth
                let ca = cosf(ang), sa = sinf(ang)
                let rr = Int(len) + 2
                for y in (Int(cy) - rr)...(Int(cy) + rr) { for x in (Int(cx) - rr)...(Int(cx) + rr) {
                    let dx: Float = Float(x) + 0.5 - cx, dy: Float = Float(y) + 0.5 - cy
                    let along: Float = (dx * ca + dy * sa) / len, across: Float = (-dx * sa + dy * ca) / (len * 0.3)
                    let t: Float = along * 0.5 + 0.5
                    guard t >= 0 && t <= 1 else { continue }
                    let wdt: Float = sinf(t * Float.pi) * (0.75 + 0.25 * sinf(t * 40))       // serrated edge
                    guard abs(across) <= wdt else { continue }
                    let rib: Float = abs(across) < 0.1 ? 0.75 : 1
                    let c: V3 = (base * (1 - t * 0.5) + ct * (t * t * 0.6)) * rib * (0.85 + 0.2 * (1 - abs(across)))
                    img[x, y] = V4(min(1, c.x), min(1, c.y), min(1, c.z), 1)
                } }
            }
            return img
        }
    }

    // A ribbed pod lit from inside (shroomlight): vertical ribs, a hot core showing between them.
    static func pod() -> Gen {
        { n, s in
            let fn = Float(n)
            var img = HDTex.Img(n)
            let fine = HDTex.vnoise(n, max(1, n / 32), s)
            for y in 0..<n { for x in 0..<n {
                let u: Float = Float(x) / fn, v: Float = Float(y) / fn
                let rib: Float = abs(sinf(u * Float.pi * 6 + sinf(v * 6.28) * 0.4))
                let core: Float = 1 - rib
                let shell: V3 = col(0x6A2A10) * (0.7 + 0.5 * rib)
                let hot: V3 = col(0xFFB050) * (0.85 + 0.3 * fine[y * n + x])
                let k: Float = HDTex.cl(core * 1.6 - 0.2)
                let c: V3 = shell * (1 - k) + hot * k
                img.px[y * n + x] = V4(min(1, c.x), min(1, c.y), min(1, c.z), 1)
            } }
            return img
        }
    }

    // Amber crystal facets (lumenstone): Voronoi facets shaded as flat planes, bright edges.
    static func crystal() -> Gen {
        { n, s in
            let fn = Float(n)
            var img = HDTex.Img(n)
            let v = HDTex.voronoi(n, 7, s &+ 3, jitter: 1)
            let pal: [(Float, UInt32)] = [(0, 0x7A4A10), (0.4, 0xC8862A), (0.75, 0xF4C46A), (1, 0xFFF0C8)]
            for i in 0..<(n * n) {
                let edge: Float = v.f2[i] - v.f1[i]
                var t: Float = 0.3 + v.id[i] * 0.55
                if edge < fn / 60 { t = 0.95 } else if edge < fn / 30 { t += 0.12 }
                let c = HDTex.ramp(t, pal)
                img.px[i] = V4(c.x, c.y, c.z, 1)
            }
            return img
        }
    }

    // Plants (cutout sprites).
    // A sprout: a dark curled stem with buds (charwood) or a cluster of thin crystal shoots (gloam).
    static func sprout(stem: UInt32, bud: UInt32, crystalShoots: Bool, salt: Int) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = HDTex.Img(n, V4(0, 0, 0, 0))
            let sc = col(stem), bc = col(bud)
            let shoots = crystalShoots ? 5 : 3
            for k in 0..<shoots {
                func r(_ j: Int) -> Float { HDTex.h2(k, j, salt) }
                let bx: Float = fn * (0.3 + 0.4 * r(0))
                let h: Float = fn * (crystalShoots ? 0.35 + 0.45 * r(1) : 0.4 + 0.3 * r(1))
                let lean: Float = (r(2) - 0.5) * fn * 0.3
                for y in 0..<Int(h) {
                    let t: Float = Float(y) / h
                    let cx: Float = bx + lean * t * t
                    let w: Float = crystalShoots ? fn / 30 * (1 - t) + 0.7 : fn / 40 + 0.6
                    for x in Int(cx - w)...Int(cx + w) {
                        let c: V3 = crystalShoots ? sc * (0.8 + 0.6 * t) + bc * (t * t * 0.5) : sc * (0.9 - 0.2 * t)
                        HDTex.plot(&img, x, n - 1 - y, c)
                    }
                }
                if !crystalShoots {
                    let tx: Float = bx + lean, ty: Float = fn - h
                    for b in 0..<3 {
                        let a: Float = Float(b) * 2.1 + r(4) * 3
                        HDTex.leafBlob(&img, tx + cosf(a) * fn * 0.05, ty + sinf(a) * fn * 0.04, fn * 0.07, a, bc)
                    }
                }
            }
            return img
        }
    }

    // Curled fern fronds (ember fern) or straight thin spines (gloam spines).
    static func fern(colour: UInt32, tip: UInt32, spines: Bool, salt: Int) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = HDTex.Img(n, V4(0, 0, 0, 0))
            let c0 = col(colour), c1 = col(tip)
            let count = spines ? 9 : 5
            for k in 0..<count {
                func r(_ j: Int) -> Float { HDTex.h2(k, j, salt) }
                let bx: Float = fn * (0.2 + 0.6 * r(0))
                let len: Float = fn * (spines ? 0.4 + 0.45 * r(1) : 0.45 + 0.35 * r(1))
                let lean: Float = (r(2) - 0.5) * (spines ? 0.6 : 2.4)
                let steps = Int(len)
                var x: Float = bx, y: Float = fn - 1
                var a: Float = -Float.pi / 2 + lean * 0.3
                for j in 0..<steps {
                    let t: Float = Float(j) / Float(steps)
                    let c: V3 = c0 * (1 - t) + c1 * t
                    let w: Float = spines ? fn / 70 * (1 - t) + 0.5 : fn / 60 + 0.5
                    for dx in Int(-w)...Int(w) { HDTex.plot(&img, Int(x) + dx, Int(y), c) }
                    if !spines && j % max(1, steps / 7) == 0 && t > 0.2 {
                        HDTex.leafBlob(&img, x + fn * 0.04, y, fn * 0.05, a + 1.2, c * 1.1)
                        HDTex.leafBlob(&img, x - fn * 0.04, y, fn * 0.05, a - 1.2 + Float.pi, c * 1.1)
                    }
                    x += cosf(a); y += sinf(a)
                    if !spines && t > 0.7 { a += 0.18 * (lean >= 0 ? 1 : -1) }      // the curl at the tip
                }
            }
            return img
        }
    }

    // Hanging (ember) or rising (gloam) tendrils: two cords with glowing beads; tile vertically.
    static func tendril(colour: UInt32, bead: UInt32, salt: Int) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = HDTex.Img(n, V4(0, 0, 0, 0))
            let c = col(colour), b = col(bead)
            for strand in 0..<2 {
                let ox: Float = fn * (strand == 0 ? 0.38 : 0.62)
                let ph: Float = Float(strand) * 2.4 + HDTex.h2(strand, 1, salt) * 3
                for y in 0..<n {
                    let cx: Float = ox + sinf(Float(y) / fn * 2 * Float.pi * 2 + ph) * fn * 0.05
                    let w: Float = fn / 48 + 0.5
                    for x in Int(cx - w)...Int(cx + w) { HDTex.plot(&img, x, y, c * (1.0 - 0.3 * abs((Float(x) - cx) / w))) }
                    if y % (n / 4) == (strand * n / 8) {
                        let r: Float = fn / 28
                        for yy in Int(Float(y) - r)...Int(Float(y) + r) { for xx in Int(cx - r)...Int(cx + r) {
                            let dx: Float = Float(xx) - cx, dy: Float = Float(yy - y)
                            if dx * dx + dy * dy <= r * r { HDTex.plot(&img, xx, (yy + n) % n, b * (1.1 - 0.3 * (dx * dx + dy * dy) / (r * r))) }
                        } }
                    }
                }
            }
            return img
        }
    }

    // Brimroot (crop stages 0...2): a knot of twisting orange roots with a pale crown, bigger each stage.
    static func brimroot(stage: Int) -> Gen {
        { n, s in
            let fn = Float(n)
            var img = HDTex.Img(n, V4(0, 0, 0, 0))
            let k: Float = 0.45 + 0.27 * Float(stage)
            let root = col(0xB0501C), dark = col(0x5A2410), crown = col(0xF0B070)
            let roots = 3 + stage * 2
            for j in 0..<roots {
                func r(_ q: Int) -> Float { HDTex.h2(j, q, 301 + stage) }
                let bx: Float = fn * (0.35 + 0.3 * r(0))
                let h: Float = fn * k * (0.6 + 0.4 * r(1))
                let ph: Float = r(2) * 6.28
                for y in 0..<Int(h) {
                    let t: Float = Float(y) / h
                    let cx: Float = bx + sinf(t * 7 + ph) * fn * 0.05
                    let w: Float = fn / 34 * (1.2 - t) + 0.6
                    for x in Int(cx - w)...Int(cx + w) {
                        let c: V3 = dark * (1 - t) + root * t
                        HDTex.plot(&img, x, n - 1 - y, c * (1.05 - 0.3 * abs((Float(x) - cx) / w)))
                    }
                }
            }
            if stage >= 1 {
                let cy: Float = fn - fn * k, r: Float = fn * (0.05 + 0.04 * Float(stage))
                for y in Int(cy - r)...Int(cy + r) { for x in Int(fn / 2 - r * 1.6)...Int(fn / 2 + r * 1.6) {
                    let dx: Float = (Float(x) - fn / 2) / 1.6, dy: Float = Float(y) - cy
                    if dx * dx + dy * dy <= r * r { HDTex.plot(&img, x, y, crown * (0.8 + 0.3 * (1 - (dx * dx + dy * dy) / (r * r)))) }
                } }
            }
            return img
        }
    }

    // The generator for a hell look, nil for anything else (HDTex.generator asks here first).
    static func gen(_ name: String) -> Gen? {
        switch name {
        case "netherrack": return cinderstone
        case "nether_gold_ore": return HDTex.ore(cinderRock, 0xD8A824, 0xFCE878, clusters: 5, shape: .nugget)
        case "nether_quartz_ore": return HDTex.ore(cinderRock, 0xCFC6B8, 0xFFFFFF, clusters: 7, shape: .prism)
        case "soul_sand": return paleAsh
        case "soul_soil": return ashSilt
        case "crimson_nylium": return emberMoss
        case "crimson_nylium_side": return HDTex.topped(emberMoss, depth: 0.22, over: cinderstone)
        case "warped_nylium": return gloamMoss
        case "warped_nylium_side": return HDTex.topped(gloamMoss, depth: 0.22, over: cinderstone)
        case "crimson_stem": return glowCracks(HDTex.barkSide(charBark), hot: 0xE85A16, lines: 6, strength: 0.85)
        case "crimson_stem_top": return heart(HDTex.ringsTop(bark: charBark, wood: [(0, 0x24140E), (0.5, 0x3A2216), (1, 0x52301E)]), hot: 0xFF7A26, radius: 0.16)
        case "stripped_crimson_log": return HDTex.barkSide([(0, 0x24170F), (0.5, 0x382418), (1, 0x4E3222)])
        case "stripped_crimson_log_top": return HDTex.ringsTop(bark: [(0, 0x24170F), (0.5, 0x382418), (1, 0x4E3222)], wood: [(0, 0x3A2216), (0.5, 0x52301E), (1, 0x6A4028)])
        case "warped_stem": return glowCracks(HDTex.barkSide(gloamBark), hot: 0xA478FF, lines: 4, strength: 0.6)
        case "warped_stem_top": return HDTex.ringsTop(bark: gloamBark, wood: [(0, 0x463A62), (0.5, 0x625486), (1, 0x8272AA)])
        case "stripped_warped_log": return HDTex.barkSide([(0, 0x625878), (0.5, 0x7C7294), (1, 0x988EB0)])
        case "stripped_warped_log_top": return HDTex.ringsTop(bark: [(0, 0x625878), (0.5, 0x7C7294), (1, 0x988EB0)], wood: [(0, 0x6A5E8A), (0.5, 0x8476A6), (1, 0x9E90C0)])
        case "crimson_planks": return HDTex.planks([(0, 0x1E140E), (0.5, 0x36261A), (1, 0x503828)])
        case "warped_planks": return HDTex.planks([(0, 0x4A4260), (0.5, 0x625A7A), (1, 0x7C7296)])
        case "nether_wart_block": return fronds(dark: 0x2A0C04, mid: 0xA43A12, tip: 0xFF9A40, salt: 21)
        case "warped_wart_block": return fronds(dark: 0x140E2A, mid: 0x4E3A9A, tip: 0xC8B4FF, salt: 23)
        case "shroomlight": return pod()
        case "glowstone": return crystal()
        case "crimson_fungus": return sprout(stem: 0x1A100C, bud: 0xF07A2A, crystalShoots: false, salt: 31)
        case "warped_fungus": return sprout(stem: 0x6A58B8, bud: 0xD8C8FF, crystalShoots: true, salt: 33)
        case "crimson_roots": return fern(colour: 0x5A2210, tip: 0xE0682A, spines: false, salt: 35)
        case "warped_roots": return fern(colour: 0x3A3070, tip: 0xB8A8FF, spines: true, salt: 37)
        case "weeping_vines": return tendril(colour: 0x3A1A0E, bead: 0xFF8A30, salt: 39)
        case "twisting_vines": return tendril(colour: 0x403470, bead: 0xC0B0FF, salt: 41)
        case "sulfur_crust": return sulfurCrust
        default:
            if name.hasPrefix("nether_wart_stage"), let st = Int(name.dropFirst("nether_wart_stage".count)) { return brimroot(stage: st) }
            return nil
        }
    }
}

extension TextureGen {
    // The 16 px art of hell's own looks (the small texture setting, map colours, break particles), matching the HD
    // generators above.
    static func hellLandPainters(_ p: inout [String: Painter]) {
        func noisy(_ c: UInt32, _ salt: Int, _ k: Float = 0.3) -> Painter { { x, y in hex(c, 0.82 + k * r(x, y, salt)) } }
        let rock: Painter = { x, y in
            let seam = r(x / 2, y, 4401) > 0.86 && r(x, y / 2, 4402) > 0.5
            return seam ? hex(0xE8641C, 0.85 + 0.3 * r(x, y, 4403)) : hex(0x2C231D, 0.75 + 0.45 * r(x, y, 4404))
        }
        p["netherrack"] = rock
        p["soul_sand"] = noisy(0xA49E92, 4405)
        p["soul_soil"] = noisy(0x665E56, 4406)
        let ember: Painter = { x, y in r(x, y, 4407) > 0.8 ? hex(0xE8742C) : hex(0x3A1C12, 0.8 + 0.4 * r(x, y, 4408)) }
        let gloam: Painter = { x, y in r(x, y, 4409) > 0.82 ? hex(0xA894F0) : hex(0x241E36, 0.8 + 0.4 * r(x, y, 4410)) }
        p["crimson_nylium"] = ember
        p["warped_nylium"] = gloam
        p["crimson_nylium_side"] = { x, y in y < 3 + Int(r(x, 0, 4411) * 2) ? ember(x, y) : rock(x, y) }
        p["warped_nylium_side"] = { x, y in y < 3 + Int(r(x, 0, 4412) * 2) ? gloam(x, y) : rock(x, y) }
        p["crimson_stem"] = { x, y in x % 5 == 2 && r(x, y / 3, 4413) > 0.5 ? hex(0xD8581A) : hex(0x1A130F, 0.8 + 0.4 * r(x, y / 2, 4414)) }
        p["warped_stem"] = { x, y in x % 6 == 3 && r(x, y / 3, 4415) > 0.6 ? hex(0x9A74F0) : hex(0x564E68, 0.8 + 0.35 * r(x, y / 2, 4416)) }
        p["crimson_planks"] = noisy(0x36261A, 4417)
        p["warped_planks"] = noisy(0x625A7A, 4418)
        p["nether_wart_block"] = { x, y in hex(r(x, y, 4419) > 0.7 ? 0xE8782C : 0x8A3010, 0.8 + 0.35 * r(x / 2, y / 2, 4420)) }
        p["warped_wart_block"] = { x, y in hex(r(x, y, 4421) > 0.7 ? 0xB4A2F8 : 0x4A3A90, 0.8 + 0.35 * r(x / 2, y / 2, 4422)) }
        p["shroomlight"] = { x, y in hex(x % 4 == 1 ? 0x7A3214 : 0xFFAE4C, 0.9 + 0.2 * r(x, y, 4423)) }
        p["glowstone"] = { x, y in hex(r(x / 3, y / 3, 4424) > 0.5 ? 0xF4C46A : 0xC0822A, 0.85 + 0.3 * r(x, y, 4425)) }
        p["sulfur_crust"] = { x, y in r(x / 3, y / 3, 4426) > 0.85 ? hex(0x6A5A12) : hex(0xC8AC28, 0.8 + 0.35 * r(x, y, 4427)) }
    }
}
