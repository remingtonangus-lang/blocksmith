import simd

// All textures are procedurally painted 16x16 pixel art (original, no external assets).
// Textures are registered by name (Tex.id) by the block/item registries; this file holds a painter
// for each name. Unknown names render as a magenta/black checker so they are easy to spot.
enum TextureGen {
    static let S = 16
    typealias Painter = (Int, Int) -> V4

    // Textures used only by the HUD (registered up front so they exist before the atlas is built).
    static let hudNames = ["heart", "heart_half", "heart_empty", "food", "food_half", "food_empty", "bubble",
                           "destroy_0", "destroy_1", "destroy_2", "destroy_3", "destroy_4",
                           "destroy_5", "destroy_6", "destroy_7", "destroy_8", "destroy_9",
                           "armor", "armor_half", "armor_empty", "xp_bar"]

    // Makes sure every texture that may be referenced exists in the registry.
    static func registerAll() {
        _ = Blocks.count
        _ = Items.count
        for n in hudNames { _ = Tex.id(n) }
        for n in Font.names { _ = Tex.id(n) }
    }

    static func r(_ x: Int, _ y: Int, _ salt: Int) -> Float { hashf(x, y, salt, 777) }
    static func rgb(_ r: Float, _ g: Float, _ b: Float, _ k: Float, _ a: Float = 1) -> V4 { V4(r * k, g * k, b * k, a) }
    static func hex(_ h: UInt32, _ k: Float = 1, _ a: Float = 1) -> V4 {
        V4(Float((h >> 16) & 255) / 255 * k, Float((h >> 8) & 255) / 255 * k, Float(h & 255) / 255 * k, a)
    }
    static let clear = V4(0, 0, 0, 0)

    // Smooth-ish value noise on the 16x16 tile (wraps), for blotchy stone-like textures.
    static func blot(_ x: Int, _ y: Int, _ salt: Int, _ cell: Int) -> Float {
        let fx = Float(x) / Float(cell), fy = Float(y) / Float(cell)
        let x0 = Int(floorf(fx)), y0 = Int(floorf(fy))
        let tx = fx - Float(x0), ty = fy - Float(y0)
        let n = 16 / cell
        func g(_ a: Int, _ b: Int) -> Float { r(((a % n) + n) % n, ((b % n) + n) % n, salt) }
        let a = g(x0, y0) + (g(x0 + 1, y0) - g(x0, y0)) * tx
        let b = g(x0, y0 + 1) + (g(x0 + 1, y0 + 1) - g(x0, y0 + 1)) * tx
        return a + (b - a) * ty
    }

    // Generic "rock": base colour with per-pixel grain and blotches.
    static func rock(_ base: UInt32, grain: Float, blotch: Float, salt: Int) -> Painter {
        { x, y in
            let k = 1 + (r(x, y, salt) - 0.5) * grain + (blot(x, y, salt + 1, 4) - 0.5) * blotch
            return hex(base, k)
        }
    }

    // Ore: clusters of coloured specks over a base painter.
    static func ore(_ base: @escaping Painter, _ c: UInt32, _ c2: UInt32, salt: Int) -> Painter {
        { x, y in
            let cx = x / 3, cy = y / 3
            if r(cx, cy, salt) < 0.42 && r(x, y, salt + 1) < 0.62 {
                let hi = r(x, y, salt + 2) > 0.55
                return hex(hi ? c2 : c, 0.9 + 0.2 * r(x, y, salt + 3))
            }
            return base(x, y)
        }
    }

    static func planks(_ c: UInt32, salt: Int) -> Painter {
        { x, y in
            let row = y / 4
            let seam = (row * 7 + 3) % 16
            var k: Float = 0.9 + 0.1 * r(x / 4, y, salt) + (r(x, row, salt + 1) - 0.5) * 0.08
            if y % 4 == 3 { k = 0.62 } else if x == seam { k = 0.7 }
            return hex(c, k)
        }
    }

    static func bark(_ c: UInt32, salt: Int) -> Painter {
        { x, y in
            let stripe = (x + Int(r(0, y / 5, salt) * 2)) % 4 == 0
            return hex(c, stripe ? 0.72 : 0.9 + 0.14 * r(x, y, salt + 1))
        }
    }

    static func rings(_ barkC: UInt32, _ wood: UInt32) -> Painter {
        { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            let d = (dx * dx + dy * dy).squareRoot()
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(barkC, 0.85) }
            let ring = Int(d * 1.15) % 2 == 0
            return hex(wood, ring ? 1 : 0.86)
        }
    }

    static func foliage(_ c: UInt32, holes: Float, salt: Int) -> Painter {
        { x, y in
            if r(x, y, salt) < holes { return clear }
            return hex(c, 0.72 + 0.45 * r(x, y, salt + 1))
        }
    }

    static func painters() -> [String: Painter] {
        var p: [String: Painter] = [:]
        let stone = rock(0x7F7F7F, grain: 0.14, blotch: 0.12, salt: 1)
        let deepslate: Painter = { x, y in
            var k: Float = 1 + (r(x, y, 60) - 0.5) * 0.12
            if (y + Int(r(x / 4, 0, 61) * 3)) % 4 == 0 { k *= 0.85 }
            return hex(0x4D4D52, k)
        }
        func dirt(_ x: Int, _ y: Int) -> V4 {
            let speck: Float = r(x, y, 31) < 0.1 ? 0.78 : 1
            return hex(0x866043, (0.84 + 0.28 * r(x, y, 3)) * speck)
        }
        // Grass/leaf textures are greyscale and tinted per biome in the shader.
        func grayGrass(_ x: Int, _ y: Int) -> V4 { let v: Float = 0.62 + 0.3 * r(x, y, 2); return V4(v, v, v, 1) }
        func snowC(_ x: Int, _ y: Int) -> V4 { hex(0xF2F7FF, 0.94 + 0.06 * r(x, y, 19)) }
        func edge(_ x: Int, _ base: Int) -> Int { base + (r(x, 0, 21) > 0.5 ? 1 : 0) + (r(x, 0, 22) > 0.8 ? 1 : 0) }

        p["stone"] = stone
        p["grass_block_top"] = grayGrass
        // Overlay texels (alpha 0.9) are tinted by biome; the dirt below stays as is.
        p["grass_block_side"] = { x, y in
            if y < edge(x, 3) { var g = grayGrass(x, y); g.w = 0.9; return g }
            return dirt(x, y)
        }
        p["dirt"] = dirt
        var pts: [V2] = []
        for k in 0..<8 { pts.append(V2(r(k, 0, 5) * 16, r(k, 1, 5) * 16)) }
        func cobble(_ base: UInt32, _ mortar: UInt32, _ salt: Int) -> Painter {
            { x, y in
                let q = V2(Float(x) + 0.5, Float(y) + 0.5)
                var d1: Float = 1e9, d2: Float = 1e9, k1 = 0
                for (k, c) in pts.enumerated() {
                    for oy in -1...1 {
                        for ox in -1...1 {
                            let d = simd_distance(q, c + V2(Float(ox * 16), Float(oy * 16)))
                            if d < d1 { d2 = d1; d1 = d; k1 = k } else if d < d2 { d2 = d }
                        }
                    }
                }
                if d2 - d1 < 1.2 { return hex(mortar) }
                return hex(base, 0.85 + r(k1, 9, salt) * 0.3 + (r(x, y, salt + 1) - 0.5) * 0.08)
            }
        }
        p["cobblestone"] = cobble(0x7A7A7A, 0x444444, 9)
        p["mossy_cobblestone"] = { x, y in
            if blot(x, y, 70, 4) > 0.55 && r(x, y, 71) < 0.8 { return hex(0x5A7A3A, 0.8 + 0.3 * r(x, y, 72)) }
            return cobble(0x7A7A7A, 0x444444, 9)(x, y)
        }
        p["cobbled_deepslate"] = cobble(0x505055, 0x2A2A2E, 62)
        p["oak_planks"] = planks(0xA2824E, salt: 41)
        p["birch_planks"] = planks(0xC5B57A, salt: 43)
        p["spruce_planks"] = planks(0x735531, salt: 45)
        p["bedrock"] = { x, y in let v: Float = 0.12 + r(x, y, 6) * 0.45; return V4(v, v, v, 1) }
        p["sand"] = { x, y in hex(0xDBD3A0, 0.93 + 0.12 * r(x, y, 7)) }
        p["red_sand"] = { x, y in hex(0xBE6621, 0.9 + 0.14 * r(x, y, 8)) }
        p["gravel"] = { x, y in
            let n = r(x, y, 8)
            let v: Float = n < 0.33 ? 0.4 : (n < 0.66 ? 0.53 : 0.64)
            return V4(v, v * 0.97, v * 0.95, 1)
        }
        p["oak_log"] = bark(0x6B5332, salt: 9)
        p["oak_log_top"] = rings(0x6B5332, 0xB0915B)
        p["spruce_log"] = bark(0x3B2A18, salt: 12)
        p["spruce_log_top"] = rings(0x3B2A18, 0x7A5A3A)
        p["birch_log_top"] = rings(0xDDDAD0, 0xC8B27D)
        p["birch_log"] = { x, y in
            let dash = y % 5 == 2 && r(x / 3, y, 26) < 0.55
            if dash || r(x, y, 27) < 0.05 { return hex(0x2E2B26, 0.9 + 0.2 * r(x, y, 28)) }
            return hex(0xE3E0D6, 0.92 + 0.08 * r(x, y, 29))
        }
        p["oak_leaves"] = { x, y in
            if r(x, y, 12) < 0.2 { return clear }
            let v: Float = 0.5 + 0.45 * r(x, y, 13)
            return V4(v, v, v, 1)
        }
        p["birch_leaves"] = foliage(0x80A755, holes: 0.22, salt: 32)
        p["spruce_leaves"] = foliage(0x619961, holes: 0.12, salt: 34)
        p["glass"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return V4(0.75, 0.86, 0.92, 1) }
            if (x == y || x == y + 1) && x > 3 && x < 8 { return V4(0.95, 0.98, 1, 1) }
            return clear
        }
        p["water"] = { x, y in
            let v: Float = 0.8 + 0.2 * r(x / 2, y, 14)
            return V4(v, v, v, 0.72)
        }
        p["coal_ore"] = ore(stone, 0x1E1E1E, 0x3A3A3A, salt: 50)
        p["iron_ore"] = ore(stone, 0xD8AF93, 0xAF8E77, salt: 51)
        p["gold_ore"] = ore(stone, 0xFCEE4B, 0xE0A423, salt: 52)
        p["diamond_ore"] = ore(stone, 0x5DECF5, 0x2BC7AC, salt: 53)
        p["lapis_ore"] = ore(stone, 0x2749A8, 0x1B3A90, salt: 54)
        p["redstone_ore"] = ore(stone, 0xFF0000, 0xAA0000, salt: 55)
        p["emerald_ore"] = ore(stone, 0x17DD62, 0x0B8B3A, salt: 56)
        p["copper_ore"] = ore(stone, 0xE0724A, 0x57B892, salt: 57)
        p["deepslate_coal_ore"] = ore(deepslate, 0x1E1E1E, 0x3A3A3A, salt: 50)
        p["deepslate_iron_ore"] = ore(deepslate, 0xD8AF93, 0xAF8E77, salt: 51)
        p["deepslate_gold_ore"] = ore(deepslate, 0xFCEE4B, 0xE0A423, salt: 52)
        p["deepslate_diamond_ore"] = ore(deepslate, 0x5DECF5, 0x2BC7AC, salt: 53)
        p["deepslate_lapis_ore"] = ore(deepslate, 0x2749A8, 0x1B3A90, salt: 54)
        p["deepslate_redstone_ore"] = ore(deepslate, 0xFF0000, 0xAA0000, salt: 55)
        p["deepslate_copper_ore"] = ore(deepslate, 0xE0724A, 0x57B892, salt: 57)
        p["deepslate"] = deepslate
        p["andesite"] = rock(0x888889, grain: 0.18, blotch: 0.2, salt: 63)
        p["diorite"] = { x, y in
            let v = r(x, y, 64)
            return v < 0.25 ? hex(0x9A9A9A) : hex(0xD8D8D8, 0.92 + 0.1 * r(x, y, 65))
        }
        p["granite"] = { x, y in
            let v = r(x, y, 66)
            return v < 0.2 ? hex(0x7F4F3F) : (v > 0.85 ? hex(0xC9A08E) : hex(0x9A6B58, 0.94 + 0.1 * r(x, y, 67)))
        }
        p["tuff"] = rock(0x6C6D66, grain: 0.18, blotch: 0.14, salt: 68)
        p["clay"] = rock(0xA0A6B3, grain: 0.06, blotch: 0.06, salt: 69)
        p["obsidian"] = { x, y in
            let hl = blot(x, y, 73, 4) > 0.7 && r(x, y, 74) < 0.5
            return hl ? hex(0x3B2754) : hex(0x14101E, 0.8 + 0.4 * r(x, y, 75))
        }
        p["terracotta"] = rock(0x985E43, grain: 0.06, blotch: 0.05, salt: 76)
        p["smooth_stone"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x8E8E8E) }
            return hex(0xA0A0A0, 0.97 + 0.05 * r(x, y, 77))
        }
        p["bricks"] = { x, y in
            let row = y / 4
            if y % 4 == 3 || x == (row % 2 == 0 ? 7 : 15) { return hex(0xB5B0A8, 0.9 + 0.1 * r(x, y, 16)) }
            return hex(0x96503E, 0.85 + 0.3 * r(x, y, 15))
        }
        p["snow"] = snowC
        p["grass_block_snow"] = { x, y in y < edge(x, 2) ? snowC(x, y) : dirt(x, y) }
        p["cactus_side"] = { x, y in
            if x == 0 || x == 15 { return clear }
            if r(x, y, 17) < 0.06 { return hex(0xE6E6B3) }
            return hex(0x2F7F32, x % 4 == 1 ? 0.72 : 0.92 + 0.1 * r(x, y, 18))
        }
        p["cactus_top"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return clear }
            let border = x == 1 || y == 1 || x == 14 || y == 14
            return hex(0x55A043, border ? 0.7 : 0.95 + 0.08 * r(x, y, 20))
        }
        p["cactus_bottom"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return clear }
            return hex(0xC3C586, 0.9 + 0.1 * r(x, y, 78))
        }
        p["stone_bricks"] = { x, y in
            let row = y / 8
            if y % 8 == 7 || x == (row == 0 ? 15 : 7) { return hex(0x525252) }
            var v: Float = 0.93 + (r(x, y, 23) - 0.5) * 0.08
            if y % 8 == 0 { v = 1.08 }
            return hex(0x7A7A7A, v)
        }
        p["sandstone"] = { x, y in
            var k: Float = 0.96 + 0.06 * r(x, y, 24)
            if y == 3 || y == 4 { k *= 0.86 }
            if y >= 13 { k *= 0.93 }
            return hex(0xD9CE9E, k)
        }
        p["sandstone_top"] = { x, y in hex(0xE0D6A8, 0.95 + 0.07 * r(x, y, 25)) }
        p["sandstone_bottom"] = { x, y in hex(0xD4C996, 0.94 + 0.08 * r(x, y, 79)) }
        p["short_grass"] = { x, y in
            let bladeH = 5 + Int(r(x, 0, 36) * 10)
            if 15 - y >= bladeH || r(x, 1, 37) < 0.25 { return clear }
            let k: Float = 0.62 + 0.4 * Float(15 - y) / 15 + 0.12 * r(x, y, 38)
            return V4(k * 0.8, k * 0.8, k * 0.8, 1)
        }
        func flower(_ petal: UInt32, _ center: UInt32, _ salt: Int) -> Painter {
            { x, y in
                let dx = Float(x) - 7.5, dy = Float(y) - 5.5
                let d2 = dx * dx + dy * dy
                if d2 < 2.2 { return hex(center) }
                if d2 < 9.5 && r(x, y, salt) > 0.08 { return hex(petal, 0.8 + 0.25 * r(x, y, salt + 1)) }
                if (x == 7 || x == 8) && y > 7 { return hex(0x3F852E, 0.9) }
                if (x == 5 && y == 11) || (x == 6 && y >= 10 && y <= 12) || (x == 9 && y >= 11 && y <= 12) || (x == 10 && y == 12) {
                    return hex(0x4A9432)
                }
                return clear
            }
        }
        p["poppy"] = flower(0xDB2420, 0x331F0D, 40)
        p["dandelion"] = flower(0xFAD733, 0xE68C1A, 42)
        p["cornflower"] = flower(0x5A80F2, 0xF2E680, 44)
        p["torch"] = { x, y in
            guard x == 7 || x == 8 else { return clear }
            if y == 6 { return hex(0xFFF6C8) }
            if y == 7 { return hex(0xFFC43A) }
            if y >= 8 { return hex(0x6B4F2C, 0.85 + 0.2 * r(x, y, 46)) }
            return clear
        }
        p["torch_top"] = { x, y in
            guard x >= 7 && x <= 8 && y >= 7 && y <= 8 else { return clear }
            return hex(0xFFE27A)
        }
        p["torch_bottom"] = { x, y in hex(0x6B4F2C) }
        p["glowstone"] = { x, y in
            let v = blot(x, y, 80, 4) + r(x, y, 81) * 0.4
            return v > 0.9 ? hex(0xFFF3C4) : (v > 0.6 ? hex(0xE8B55A) : hex(0x9A6A30, 0.9 + 0.2 * r(x, y, 82)))
        }

        let plank = planks(0xA2824E, salt: 41)
        p["crafting_table_top"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x5A4020) }
            if x == 7 || y == 7 { return hex(0x6B4F2C) }
            return hex(0xB08850, 0.9 + 0.12 * r(x, y, 101))
        }
        p["crafting_table_side"] = { x, y in
            if y < 3 { return hex(0x5A4020, 0.9 + 0.1 * r(x, y, 102)) }
            if (x == 2 || x == 13) && y >= 3 { return hex(0x3E2C16) }
            return plank(x, y)
        }
        p["crafting_table_front"] = { x, y in
            if y < 3 { return hex(0x5A4020, 0.9 + 0.1 * r(x, y, 102)) }
            // A saw and a hammer hanging on the front.
            if y >= 5 && y <= 12 && x >= 3 && x <= 6 && (x - 3) + (12 - y) <= 6 { return hex(0xB8B8B8, 0.9 + 0.2 * r(x, y, 103)) }
            if x >= 9 && x <= 13 && y == 5 { return hex(0x8A8A8A) }
            if x == 11 && y > 5 && y < 13 { return hex(0x6B4F2C) }
            return plank(x, y)
        }
        let cobbleP = cobble(0x7A7A7A, 0x444444, 9)
        let furnaceSide: Painter = { x, y in
            if y == 0 || y == 15 || x == 0 || x == 15 { return hex(0x555555) }
            return hex(0x7E7E7E, 0.9 + 0.12 * r(x, y, 104))
        }
        p["furnace_side"] = furnaceSide
        p["furnace_top"] = { x, y in cobbleP(x, y) }
        func furnaceFront(_ lit: Bool) -> Painter {
            { x, y in
                if x >= 4 && x <= 11 && y >= 9 && y <= 13 {
                    if !lit { return hex(0x1A1A1A) }
                    let fl = r(x, y, 105)
                    return y >= 11 ? hex(fl > 0.5 ? 0xFFD040 : 0xFF8A1A) : hex(fl > 0.6 ? 0xFF6A10 : 0x3A1A0A)
                }
                if (x == 3 || x == 12) && y >= 8 && y <= 14 { return hex(0x3A3A3A) }
                if y == 8 && x >= 3 && x <= 12 { return hex(0x3A3A3A) }
                if y >= 3 && y <= 5 && x >= 4 && x <= 11 { return hex(0x4A4A4A) }
                return furnaceSide(x, y)
            }
        }
        p["furnace_front"] = furnaceFront(false)
        p["furnace_front_on"] = furnaceFront(true)
        func chestWood(_ x: Int, _ y: Int) -> V4 { hex(0xA2702F, 0.88 + 0.14 * r(x / 3, y, 106)) }
        p["chest_top"] = { x, y in
            if x <= 1 || y <= 1 || x >= 14 || y >= 14 { return hex(0x4E3414) }
            return chestWood(x, y)
        }
        p["chest_side"] = { x, y in
            if x <= 1 || x >= 14 || y <= 2 || y >= 15 || y == 7 || y == 8 { return hex(0x4E3414) }
            return chestWood(x, y)
        }
        p["chest_front"] = { x, y in
            if x >= 7 && x <= 8 && y >= 6 && y <= 9 { return hex(0xC8C8C8) }
            if x <= 1 || x >= 14 || y <= 2 || y >= 15 || y == 7 || y == 8 { return hex(0x4E3414) }
            return chestWood(x, y)
        }
        func storage(_ c: UInt32, _ salt: Int) -> Painter {
            { x, y in
                if x == 0 || y == 0 { return hex(c, 1.25) }
                if x == 15 || y == 15 { return hex(c, 0.65) }
                if (x == 1 || y == 1) { return hex(c, 1.1) }
                return hex(c, 0.93 + 0.1 * r(x, y, salt))
            }
        }
        p["coal_block"] = storage(0x1E1E1E, 110)
        p["iron_block"] = storage(0xDCDCDC, 111)
        p["gold_block"] = storage(0xF8D84A, 112)
        p["diamond_block"] = storage(0x62EDE0, 113)
        p["emerald_block"] = storage(0x2ADB6A, 114)
        p["lapis_block"] = storage(0x2A5BC8, 115)
        p["redstone_block"] = storage(0xB01010, 116)
        p["copper_block"] = storage(0xC8704A, 117)
        p["oak_sapling"] = ItemTextures.painter(Sprite(mask: "sapling", base: 0x4A8A2A, extras: ["a": 0x6B4F2C, "b": 0x8A6435]))
        p["birch_sapling"] = ItemTextures.painter(Sprite(mask: "sapling", base: 0x7AA850, extras: ["a": 0xD8D4C8, "b": 0xB0ACA0]))
        p["spruce_sapling"] = ItemTextures.painter(Sprite(mask: "sapling", base: 0x3A6A3A, extras: ["a": 0x4A3420, "b": 0x6A4A2A]))

        // HUD
        func heart(_ x: Int, _ y: Int, _ fill: Int) -> V4 {
            let nx = (Float(x) - 7.5) / 7.2, ny = -(Float(y) - 8.2) / 7.2
            let a = nx * nx + ny * ny - 0.62
            let f = a * a * a - nx * nx * ny * ny * ny * 0.8
            let g = nx * nx * 0.8 + ny * ny * 0.8 - 0.5
            let inner = g * g * g - nx * nx * ny * ny * ny * 0.8 * 0.5
            if f > 0 { return clear }
            if inner > 0 && f > -0.02 { return V4(0.08, 0.02, 0.02, 1) }
            let filled = fill == 2 || (fill == 1 && x < 8)
            if !filled { return V4(0.2, 0.08, 0.08, 0.95) }
            if x >= 4 && x <= 6 && y >= 5 && y <= 6 { return V4(1, 0.75, 0.75, 1) }
            return V4(0.86, 0.1, 0.12, 1)
        }
        p["heart"] = { heart($0, $1, 2) }
        p["heart_half"] = { heart($0, $1, 1) }
        p["heart_empty"] = { heart($0, $1, 0) }
        func food(_ x: Int, _ y: Int, _ fill: Int) -> V4 {
            let dx = Float(x) - 6, dy = Float(y) - 6
            let meat = dx * dx + dy * dy < 24
            let t = Float(x + y) / 2
            let bone = abs(x - y) <= 1 && t >= 9 && t <= 13
            let knob = (x >= 12 && x <= 14 && y >= 12 && y <= 14) && !(x == 12 && y == 12)
            if !(meat || bone || knob) { return clear }
            let edgeP = dx * dx + dy * dy > 17 && meat
            let filled = fill == 2 || (fill == 1 && x < 8)
            if !filled { return V4(0.16, 0.12, 0.1, 0.9) }
            if bone || knob { return V4(0.92, 0.88, 0.8, 1) }
            if edgeP { return rgb(0.45, 0.22, 0.1, 1) }
            return rgb(0.72, 0.38, 0.18, 0.9 + 0.15 * r(x, y, 50))
        }
        p["food"] = { food($0, $1, 2) }
        p["food_half"] = { food($0, $1, 1) }
        p["food_empty"] = { food($0, $1, 0) }
        func armor(_ x: Int, _ y: Int, _ fill: Int) -> V4 {
            let dx: Float = abs(Float(x) - 7.5)
            let halfWidth: Float = y < 5 ? 6.5 : 5.5 - Float(y - 5) * 0.35
            let notch = y < 5 && dx < 2
            if y < 2 || y > 13 || dx >= halfWidth || notch { return clear }
            let filled = fill == 2 || (fill == 1 && x < 8)
            return filled ? hex(0xC6C6C6, 0.85 + 0.2 * r(x, y, 83)) : V4(0.15, 0.15, 0.15, 0.9)
        }
        p["armor"] = { armor($0, $1, 2) }
        p["armor_half"] = { armor($0, $1, 1) }
        p["armor_empty"] = { armor($0, $1, 0) }
        p["bubble"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            let d = (dx * dx + dy * dy).squareRoot()
            if d > 6.5 { return clear }
            if d > 5.2 { return V4(0.75, 0.9, 1, 1) }
            if dx < -1 && dy < -1 && d > 2 && d < 4 { return V4(1, 1, 1, 1) }
            return V4(0.3, 0.55, 0.95, 0.55)
        }
        p["xp_bar"] = { _, _ in hex(0x80FF20) }
        // Block-breaking cracks: progressively more dark crack pixels.
        for stage in 0..<10 {
            p["destroy_\(stage)"] = { x, y in
                let thr = Float(stage + 1) / 10
                let c = r(x / 2, y / 2, 90) * 0.6 + r(x, y, 91) * 0.4
                let fx: Float = Float(x) - 7.5, fy: Float = Float(y) - 7.5
                let skew: Float = r(y / 4, 0, 92) - 0.5
                let l1: Bool = abs(fx - fy * skew) < 1
                let l2: Bool = abs(fy + fx * 0.4) < 0.8
                let line = l1 || l2
                if (line && c < thr * 1.4) || c < thr * 0.35 { return V4(0.05, 0.05, 0.05, 0.75) }
                return clear
            }
        }
        for (k, v) in ItemTextures.painters() { p[k] = v }
        for (k, v) in Font.painters() { p[k] = v }
        return p
    }

    static func base() -> [UInt8] {
        registerAll()
        let count = Tex.count
        let table = painters()
        var data = [UInt8](repeating: 0, count: S * S * 4 * count)
        for (layer, name) in Tex.names.enumerated() {
            let f: Painter = table[name] ?? { x, y in ((x / 4 + y / 4) % 2 == 0) ? V4(1, 0, 1, 1) : V4(0, 0, 0, 1) }
            for y in 0..<S {
                for x in 0..<S {
                    let c = simd_clamp(f(x, y), V4(repeating: 0), V4(repeating: 1))
                    let i = ((layer * S + y) * S + x) * 4
                    data[i] = UInt8(c.x * 255)
                    data[i + 1] = UInt8(c.y * 255)
                    data[i + 2] = UInt8(c.z * 255)
                    data[i + 3] = UInt8(c.w * 255)
                }
            }
        }
        return data
    }

    // Alpha-weighted box-filter mip chain (keeps leaves/glass from darkening at distance).
    static func mipChain() -> [[UInt8]] {
        var levels = [base()]
        let count = Tex.count
        var size = S
        let taps = [(0, 0), (1, 0), (0, 1), (1, 1)]
        while size > 1 {
            let prev = levels[levels.count - 1]
            let ns = size / 2
            var next = [UInt8](repeating: 0, count: ns * ns * 4 * count)
            for l in 0..<count {
                for y in 0..<ns {
                    for x in 0..<ns {
                        var acc = V3(repeating: 0)
                        var aSum: Float = 0
                        for (dx, dy) in taps {
                            let i = ((l * size + y * 2 + dy) * size + x * 2 + dx) * 4
                            let a = Float(prev[i + 3]) / 255
                            acc += V3(Float(prev[i]), Float(prev[i + 1]), Float(prev[i + 2])) * a
                            aSum += a
                        }
                        let o = ((l * ns + y) * ns + x) * 4
                        if aSum > 0 {
                            next[o] = UInt8(min(255, acc.x / aSum))
                            next[o + 1] = UInt8(min(255, acc.y / aSum))
                            next[o + 2] = UInt8(min(255, acc.z / aSum))
                        }
                        next[o + 3] = UInt8(min(255, aSum / 4 * 255))
                    }
                }
            }
            levels.append(next)
            size = ns
        }
        return levels
    }
}
