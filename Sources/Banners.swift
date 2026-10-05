import Foundation
import simd

// Banners: 16 colours, standing (16 rotations) and wall (4 facings), up to 6 pattern layers applied at
// the loom (reference pattern list; the special charges need their banner pattern item). The cloth is
// drawn in the entity pass from two 16x16 mask textures per pattern (top and bottom half), tinted.
enum Banners {
    // key, display name, required pattern item (nil = always available)
    static let patterns: [(String, String, String?)] = [
        ("stripe_bottom", "Base", nil), ("stripe_top", "Chief", nil), ("stripe_left", "Pale Dexter", nil), ("stripe_right", "Pale Sinister", nil),
        ("stripe_center", "Pale", nil), ("stripe_middle", "Fess", nil), ("stripe_downright", "Bend", nil), ("stripe_downleft", "Bend Sinister", nil),
        ("small_stripes", "Paly", nil), ("cross", "Saltire", nil), ("straight_cross", "Cross", nil), ("diagonal_left", "Per Bend Sinister", nil),
        ("diagonal_right", "Per Bend", nil), ("diagonal_up_left", "Per Bend Inverted", nil), ("diagonal_up_right", "Per Bend Sinister Inverted", nil),
        ("half_vertical", "Per Pale", nil), ("half_vertical_right", "Per Pale Inverted", nil), ("half_horizontal", "Per Fess", nil),
        ("half_horizontal_bottom", "Per Fess Inverted", nil), ("square_bottom_left", "Base Dexter Canton", nil),
        ("square_bottom_right", "Base Sinister Canton", nil), ("square_top_left", "Chief Dexter Canton", nil),
        ("square_top_right", "Chief Sinister Canton", nil), ("triangle_bottom", "Chevron", nil), ("triangle_top", "Inverted Chevron", nil),
        ("triangles_bottom", "Base Indented", nil), ("triangles_top", "Chief Indented", nil), ("circle", "Roundel", nil), ("rhombus", "Lozenge", nil),
        ("border", "Bordure", nil), ("gradient", "Gradient", nil), ("gradient_up", "Base Gradient", nil),
        ("curly_border", "Bordure Indented", "bordure_indented_banner_pattern"), ("bricks", "Field Masoned", "field_masoned_banner_pattern"),
        ("creeper", "Hisser Charge", "creeper_banner_pattern"), ("skull", "Skull Charge", "skull_banner_pattern"),
        ("flower", "Flower Charge", "flower_banner_pattern"), ("thing", "Thing", "thing_banner_pattern"), ("globe", "Globe", "globe_banner_pattern"),
        ("piglin", "Snout", "piglin_banner_pattern"), ("flow", "Flow", "flow_banner_pattern"), ("guster", "Gust", "guster_banner_pattern"),
    ]
    static let colors: [String] = BlockRegistry.colors.map { $0.0 }      // built once (read per frame for captains' banners)
    static func encode(_ pattern: Int, _ color: Int) -> Int { pattern * 16 + color }
    static func decode(_ v: Int) -> (pattern: Int, color: Int) { (v / 16, v % 16) }
    static func tint(_ color: Int) -> V3 {
        let h = BlockRegistry.colorHex[colors[max(0, min(15, color))]] ?? 0xFFFFFF
        return V3(Float((h >> 16) & 255) / 255, Float((h >> 8) & 255) / 255, Float(h & 255) / 255)
    }
    static func baseColor(_ b: BlockID) -> Int {
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        return colors.firstIndex(of: String(k.dropLast("_banner".count))) ?? 0
    }
    static func colorIndex(ofDye key: String) -> Int? {
        guard key.hasSuffix("_dye") else { return nil }
        return colors.firstIndex(of: String(key.dropLast(4)))
    }

    // The omen banner carried by raid captains (reference layer list, white base).
    static let ominous: [Int] = {
        let p = { (k: String) in patterns.firstIndex { $0.0 == k } ?? 0 }
        let c = { (k: String) in colors.firstIndex(of: k) ?? 0 }
        return [encode(p("rhombus"), c("cyan")), encode(p("stripe_bottom"), c("light_gray")), encode(p("stripe_center"), c("gray")),
                encode(p("border"), c("light_gray")), encode(p("stripe_middle"), c("black")), encode(p("half_horizontal"), c("light_gray")),
                encode(p("circle"), c("light_gray")), encode(p("border"), c("black"))]
    }()

    // Pattern coverage at a cloth pixel (x 0..15, y 0..31 top-down): alpha 0...1.
    static func coverage(_ key: String, _ x: Int, _ y: Int) -> Float {
        let u = (Float(x) + 0.5) / 16, v = (Float(y) + 0.5) / 32
        func b(_ c: Bool) -> Float { c ? 1 : 0 }
        let dx = Float(x) - 7.5, dy = Float(y) - 15.5
        switch key {
        case "stripe_bottom": return b(v > 2 / 3)
        case "stripe_top": return b(v < 1 / 3)
        case "stripe_left": return b(u < 1 / 3)
        case "stripe_right": return b(u > 2 / 3)
        case "stripe_center": return b(u > 3 / 8 && u < 5 / 8)
        case "stripe_middle": return b(v > 0.42 && v < 0.58)
        case "stripe_downright": return b(abs(u - v) < 0.14)
        case "stripe_downleft": return b(abs(u + v - 1) < 0.14)
        case "small_stripes": return b((x / 2) % 2 == 0 && y < 29)
        case "cross": return b(abs(u - v) < 0.1 || abs(u + v - 1) < 0.1)
        case "straight_cross": return b((u > 0.4 && u < 0.6) || (v > 0.45 && v < 0.55))
        case "diagonal_left": return b(u + v < 1)
        case "diagonal_right": return b(u > v)
        case "diagonal_up_left": return b(u < v)
        case "diagonal_up_right": return b(u + v > 1)
        case "half_vertical": return b(u < 0.5)
        case "half_vertical_right": return b(u >= 0.5)
        case "half_horizontal": return b(v < 0.5)
        case "half_horizontal_bottom": return b(v >= 0.5)
        case "square_bottom_left": return b(u < 0.5 && v > 2 / 3)
        case "square_bottom_right": return b(u >= 0.5 && v > 2 / 3)
        case "square_top_left": return b(u < 0.5 && v < 1 / 3)
        case "square_top_right": return b(u >= 0.5 && v < 1 / 3)
        case "triangle_bottom": return b(v > 0.75 + abs(u - 0.5) * 0.5)
        case "triangle_top": return b(v < 0.25 - abs(u - 0.5) * 0.5)
        case "triangles_bottom":
            let t = (u * 4).truncatingRemainder(dividingBy: 1)
            return b(v > 0.94 - (0.5 - abs(t - 0.5)) * 0.2)
        case "triangles_top":
            let t = (u * 4).truncatingRemainder(dividingBy: 1)
            return b(v < 0.06 + (0.5 - abs(t - 0.5)) * 0.2)
        case "circle": return b(dx * dx + dy * dy < 22)
        case "rhombus": return b(abs(dx) / 6 + abs(dy) / 10 < 1)
        case "border": return b(x == 0 || x == 15 || y == 0 || y == 31)
        case "curly_border":
            let e = (x + y) % 4 < 2 ? 1 : 2
            return b(x < e || x > 15 - e || y < e || y > 31 - e)
        case "bricks":
            let row = y / 4
            return b(y % 4 == 0 || (x + (row % 2) * 4) % 8 == 0)
        case "gradient": return max(0, 1 - v * 1.15)
        case "gradient_up": return max(0, min(1, (v - 0.1) * 1.15))
        default:
            // Picture charges: 16 x 16 bitmaps centred on the cloth.
            guard let rows = charges[key], y >= 8, y < 24 else { return 0 }
            let r = Array(rows[y - 8])
            return x < r.count && r[x] == "#" ? 1 : 0
        }
    }

    // Original charge pictures.
    static let charges: [String: [String]] = [
        "creeper": [
            "................", "................", "..####....####..", "..####....####..", "..####....####..", "..####....####..",
            "......####......", "......####......", "....########....", "....########....", "....########....", "....##....##....",
            "....##....##....", "................", "................", "................",
        ],
        "skull": [
            "................", ".....######.....", "....########....", "...##########...", "...##..##..##...", "...##..##..##...",
            "...##########...", "....###..###....", ".....#.##.#.....", ".....######.....", "................", ".##..........##.",
            "..###......###..", "....###..###....", "..###......###..", ".##..........##.",
        ],
        "flower": [
            "................", "......####......", ".....######.....", "..##..####..##..", ".####..##..####.", ".######..######.",
            "..####.##.####..", "......####......", "......####......", "..####.##.####..", ".######..######.", ".####..##..####.",
            "..##..####..##..", ".....######.....", "......####......", "................",
        ],
        "thing": [
            "................", "....########....", "...##......##...", "..##..####..##..", "..#..##..##..#..", "..#..#....#..#..",
            "..#..#.##.#..#..", "..#..#.##....#..", "..#..##.....##..", "..##..#######...", "...##...........", "....#########...",
            "................", "..############..", "................", "................",
        ],
        "globe": [
            "................", ".....######.....", "...##########...", "..###..#######..", ".####...######..", ".#####...###.##.",
            ".######......##.", ".#######.....##.", ".##.####....###.", ".##..##....####.", "..#........###..", "..##......####..",
            "...###...####...", ".....######.....", "................", "................",
        ],
        "piglin": [
            "................", "................", "................", "................", "....########....", "...##########...",
            "...##########...", "...###.##.###...", "...###.##.###...", "...##########...", "....########....", "................",
            "..##........##..", "..###......###..", "................", "................",
        ],
        "flow": [
            "................", "....########....", "...#........#...", "..#..######..#..", "..#.#......#.#..", "..#.#..##..#.#..",
            "..#.#.#..#.#.#..", "..#.#.#.##.#.#..", "..#.#.#....#.#..", "..#.#..####..#..", "..#..#......#...", "...#..######....",
            "....#...........", ".....#########..", "................", "................",
        ],
        "guster": [
            "................", "......####......", ".....#....#.....", "....#.####.#....", "....#.#..#.#....", "....#.#.##.#....",
            "..###.#....###..", ".#....######...#.", ".#.##........#.#.", ".#.#.########..#.", "..#.#........##..", "...#.########....",
            "....#..........#", ".....##########.", "................", "................",
        ],
    ]
}

extension BlockRegistry {
    func registerBanners() {
        for (c, disp) in BlockRegistry.colors {
            for st in 0..<20 {
                var d = BlockDef(st == 0 ? "\(c)_banner" : "\(c)_banner[\(st)]", "\(disp) Banner")
                d.group = "\(c)_banner"; d.hidden = st != 0; d.shape = "banner"
                d.tex = ["oak_planks"]; d.render = .model; d.opaque = false; d.collide = false; d.hardness = 1; d.tool = .axe; d.sound = .wood
                d.skyStop = false
                // The mesher draws the lower pole / the wall bar; the rest of the pole, the crossbar and the cloth are entity geometry.
                d.boxes = st < 16 ? [Box(7, 0, 7, 9, 16, 9)] : [[Box(1, 14, 14, 15, 16, 16), Box(1, 14, 0, 15, 16, 2), Box(14, 14, 1, 16, 16, 15), Box(0, 14, 1, 2, 16, 15)][st - 16]]
                add(d)
            }
        }
        for (k, _, _) in Banners.patterns { _ = Tex.id("banner_pat_\(k)_t"); _ = Tex.id("banner_pat_\(k)_b") }
        _ = Tex.id("banner_cloth_t"); _ = Tex.id("banner_cloth_b")
    }
}

extension TextureGen {
    static func bannerPainters(_ p: inout [String: Painter]) {
        for (k, _, _) in Banners.patterns {
            p["banner_pat_\(k)_t"] = { x, y in let a = Banners.coverage(k, x, y); return a > 0 ? V4(1, 1, 1, a) : clear }
            p["banner_pat_\(k)_b"] = { x, y in let a = Banners.coverage(k, x, y + 16); return a > 0 ? V4(1, 1, 1, a) : clear }
        }
        // Plain cloth with a faint weave.
        p["banner_cloth_t"] = { x, y in V4(repeating: 0.9 + 0.1 * r(x, y, 1201)) + V4(0, 0, 0, 1 - (0.9 + 0.1 * r(x, y, 1201))) }
        p["banner_cloth_b"] = { x, y in V4(repeating: 0.9 + 0.1 * r(x, y + 16, 1201)) + V4(0, 0, 0, 1 - (0.9 + 0.1 * r(x, y + 16, 1201))) }
    }
}

extension EntityWriter {
    // Axis-aligned box with one texture on every face.
    mutating func texturedBox(_ mn: V3, _ mx: V3, layer: Int, color: V4) {
        let c = [V3(mn.x, mn.y, mn.z), V3(mx.x, mn.y, mn.z), V3(mx.x, mx.y, mn.z), V3(mn.x, mx.y, mn.z),
                 V3(mn.x, mn.y, mx.z), V3(mx.x, mn.y, mx.z), V3(mx.x, mx.y, mx.z), V3(mn.x, mx.y, mx.z)]
        let faces = [[1, 5, 6, 2], [4, 0, 3, 7], [3, 2, 6, 7], [4, 5, 1, 0], [5, 4, 7, 6], [0, 1, 2, 3]]
        let shade: [Float] = [0.8, 0.8, 1, 0.55, 0.68, 0.68]
        let uv = [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)]
        for (i, f) in faces.enumerated() {
            quad(f.map { c[$0] }, uv, layer, V4(V3(color.x, color.y, color.z) * shade[i], color.w))
        }
    }

    // Oriented box from its centre and three half-extent axes.
    mutating func orientedBox(_ c: V3, _ ax: V3, _ ay: V3, _ az: V3, layer: Int, color: V4) {
        var p: [V3] = []
        for i in 0..<8 {
            let sx: Float = i & 1 == 0 ? -1 : 1, sy: Float = i & 2 == 0 ? -1 : 1, sz: Float = i & 4 == 0 ? -1 : 1
            p.append(c + ax * sx + ay * sy + az * sz)
        }
        let faces = [[1, 5, 7, 3], [4, 0, 2, 6], [2, 3, 7, 6], [4, 5, 1, 0], [5, 4, 6, 7], [0, 1, 3, 2]]
        let shade: [Float] = [0.8, 0.8, 1, 0.55, 0.68, 0.68]
        let uv = [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)]
        for (i, f) in faces.enumerated() {
            quad(f.map { p[$0] }, uv, layer, V4(V3(color.x, color.y, color.z) * shade[i], color.w))
        }
    }

    // A banner's cloth: base colour then each pattern layer, both sides.
    mutating func bannerCloth(topLeft a: V3, right: V3, down: V3, base: Int, layers: [Int], light: Float) {
        let halfDown = down * 0.5
        for half in 0..<2 {
            let o = a + halfDown * Float(half)
            let pts = [o + halfDown, o + right + halfDown, o + right, o]
            let back = [o + right + halfDown, o + halfDown, o, o + right]
            let uv = [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)]
            let uvBack = [V2(1, 1), V2(0, 1), V2(0, 0), V2(1, 0)]
            let sfx = half == 0 ? "_t" : "_b"
            let tint = Banners.tint(base) * light
            quad(pts, uv, Int(Tex.id("banner_cloth" + sfx)), V4(tint, 1))
            quad(back, uvBack, Int(Tex.id("banner_cloth" + sfx)), V4(tint * 0.8, 1))
            for l in layers.prefix(16) {
                let (pi, ci) = Banners.decode(l)
                guard pi < Banners.patterns.count else { continue }
                let layer = Int(Tex.id("banner_pat_\(Banners.patterns[pi].0)" + sfx))
                let t = Banners.tint(ci) * light
                quad(pts, uv, layer, V4(t, 1))
                quad(back, uvBack, layer, V4(t * 0.8, 1))
            }
        }
    }
}

extension Game {
    // Banner placement: on a floor (16 rotations toward the player) or a wall.
    func bannerState(_ blockItem: BlockID, normal n: IVec3) -> BlockID? {
        if n.y == 1 {
            var a = (player.yaw + .pi) / (2 * .pi) * 16
            a = a.rounded()
            let rot = ((Int(a) % 16) + 16) % 16
            return blockItem + BlockID(rot)
        }
        guard n.y == 0 else { return nil }
        let f = n.z == -1 ? 0 : (n.z == 1 ? 1 : (n.x == -1 ? 2 : 3))
        return blockItem + BlockID(16 + f)
    }

    func writeBanners(_ wr: inout EntityWriter, eye: V3) {
        let planks = Int(Tex.id("oak_planks"))
        let wave = sinf(Float(clock) * 1.3)
        for (p, be) in world.blockEntities where be.kind == .banner {
            let c = V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5)
            guard simd_length(c - eye) < 64 else { continue }
            let b = world.block(p.x, p.y, p.z)
            guard Blocks.shape[Int(b)] == "banner" else { continue }
            let st = Int(b - Blocks.groupBase[Int(b)])
            let l = world.lightAt(p.x, p.y, p.z)
            let light = max(0.15, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            let base = Banners.baseColor(b)
            let lc = V4(light * 0.85, light * 0.72, light * 0.5, 1)
            if st < 16 {
                let yaw = Float(st) / 16 * 2 * .pi
                let right = V3(cosf(yaw), 0, -sinf(yaw))
                let fwd = V3(-sinf(yaw), 0, -cosf(yaw))
                let o = c - eye
                wr.texturedBox(o + V3(-0.0625, 1, -0.0625), o + V3(0.0625, 1.75, 0.0625), layer: planks, color: lc)
                let bar = o + V3(0, 1.72, 0)
                wr.orientedBox(bar, right * 0.62, V3(0, 0.06, 0), fwd * 0.06, layer: planks, color: lc)
                let sway = fwd * (0.04 * wave)
                let barL: V3 = bar - right * 0.58
                let tl: V3 = barL + fwd * 0.09 - V3(0, 0.04, 0)
                let dn: V3 = V3(0, -1.62, 0) + sway
                wr.bannerCloth(topLeft: tl, right: right * 1.16, down: dn,
                               base: base, layers: be.patterns, light: light)
            } else {
                let f = st - 16
                let n = [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0)][f]
                let right = V3(-n.z, 0, n.x) * -1
                let o = c - eye - n * 0.42
                let bar = o + V3(0, 0.94, 0)
                let barL: V3 = bar - right * 0.58
                let tl: V3 = barL + n * 0.06 - V3(0, 0.04, 0)
                let dn: V3 = V3(0, -1.62, 0) + n * (0.03 * wave)
                wr.bannerCloth(topLeft: tl, right: right * 1.16, down: dn,
                               base: base, layers: be.patterns, light: light)
            }
        }
    }
}

// Loom: banner + dye (+ optional pattern item) -> choose a pattern -> patterned banner (max 6 layers).
final class LoomMenu: Menu {
    let box = ItemContainer(3)       // banner, dye, pattern item
    let out = ItemContainer(1)
    var selected = -1
    var scroll = 0
    static let visible = 16
    init(game: Game) {
        super.init("Loom", game: game)
        slots.append(MenuSlot(13, 26, box, 0))
        slots.append(MenuSlot(33, 26, box, 1))
        slots.append(MenuSlot(23, 45, box, 2))
        for i in 0..<LoomMenu.visible {
            let b = MenuSlot(60 + (i % 4) * 14, 13 + (i / 4) * 14, nil, 0, .button(i))
            b.w = 14; b.h = 14
            slots.append(b)
        }
        let up = MenuSlot(118, 13, nil, 0, .button(100)); up.w = 12; up.h = 12; slots.append(up)
        let down = MenuSlot(118, 57, nil, 0, .button(101)); down.w = 12; down.h = 12; slots.append(down)
        slots.append(MenuSlot(143, 57, out, 0, .result))
        addPlayerInventory()
    }
    // Patterns offered: the plain ones, or just the item's charge when a pattern item is in its slot.
    var options: [Int] {
        let item = box[2].isEmpty ? nil : Items.key(box[2].item)
        return Banners.patterns.indices.filter { i in
            if let need = Banners.patterns[i].2 { return item == need }
            return item == nil
        }
    }
    override func buttonPressed(_ i: Int) {
        if i == 100 { scroll = max(0, scroll - 4); return }
        if i == 101 { scroll = min(max(0, options.count - LoomMenu.visible + 3) / 4 * 4, scroll + 4); return }
        let idx = scroll + i
        guard idx < options.count else { return }
        selected = options[idx]
        changed()
    }
    override func changed() {
        let banner = box[0], dye = box[1]
        guard !banner.isEmpty, Blocks.shape[Int(banner.def.block ?? 0)] == "banner", let ci = Banners.colorIndex(ofDye: Items.key(dye.item)),
              selected >= 0, options.contains(selected), (banner.pat?.count ?? 0) < 6 else { out[0] = .empty; return }
        var r = banner.with(count: 1)
        r.pat = (banner.pat ?? []) + [Banners.encode(selected, ci)]
        out[0] = r
    }
    override func takeResult(_ slot: MenuSlot) -> ItemStack? {
        guard !out[0].isEmpty else { return nil }
        let r = out[0]
        for i in 0..<2 { var s = box[i]; s.count -= 1; box[i] = s.count > 0 ? s : .empty }
        game.sfx(.shearsSnip, 0.5)
        changed()
        return r
    }
    override func onClose() {
        for i in 0..<3 where !box[i].isEmpty { let rest = game.inventory.add(box[i]); if !rest.isEmpty { game.dropItem(rest) }; box[i] = .empty }
    }
}
