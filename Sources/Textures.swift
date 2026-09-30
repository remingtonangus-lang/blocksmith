import Foundation
import simd

// All textures are procedurally painted 16x16 pixel art (original, no external assets).
// Textures are registered by name (Tex.id) by the block/item registries; this file holds a painter
// for each name. Unknown names render as a magenta/black checker so they are easy to spot.
enum TextureGen {
    static let S = 16
    typealias Painter = (Int, Int) -> V4

    // Textures used only by the HUD (registered up front so they exist before the atlas is built).
    static let hudNames = ["heart", "heart_half", "heart_empty", "heart_gold", "heart_gold_half", "heart_poison", "heart_poison_half",
                           "heart_wither", "heart_wither_half", "rain_drop", "snow_flake", "food", "food_half", "food_empty", "bubble",
                           "destroy_0", "destroy_1", "destroy_2", "destroy_3", "destroy_4",
                           "destroy_5", "destroy_6", "destroy_7", "destroy_8", "destroy_9",
                           "armor", "armor_half", "armor_empty", "xp_bar", "smoke"]

    // Makes sure every texture that may be referenced exists in the registry.
    static func registerAll() {
        _ = Blocks.count
        _ = Items.count
        for n in hudNames { _ = Tex.id(n) }
        for n in Font.names { _ = Tex.id(n) }
        for e in Effect.allCases { _ = Tex.id("effect_" + e.key) }
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
        p["iron_bars"] = { x, y in
            let bar = x % 5 == 2 || x % 5 == 3
            let rail = y == 1 || y == 14
            if bar || (rail && x > 0 && x < 15) {
                let v: Float = (x % 5 == 2 ? 0.62 : 0.46) + 0.08 * r(x, y, 77)
                return V4(v, v, v * 1.02, 1)
            }
            return clear
        }
        p["spawner"] = { x, y in
            // Dark iron cage: a grid of bars with rivets, see-through between them.
            let edge = x == 0 || y == 0 || x == 15 || y == 15
            let bar = x % 4 == 0 || y % 4 == 0
            if edge || bar {
                let v: Float = edge ? 0.2 : 0.14 + 0.08 * r(x, y, 78)
                let rivet = x % 4 == 0 && y % 4 == 0
                return rivet ? V4(0.32, 0.34, 0.4, 1) : V4(v, v * 1.05, v * 1.2, 1)
            }
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
        p["snow_block"] = snowC
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
        p["farmland"] = { x, y in
            if y % 4 == 0 { return hex(0x6B4A2E, 0.85 + 0.1 * r(x, y, 120)) }
            return hex(0x8A6242, 0.85 + 0.2 * r(x, y, 121))
        }
        p["farmland_moist"] = { x, y in
            if y % 4 == 0 { return hex(0x3E2A18, 0.85 + 0.1 * r(x, y, 120)) }
            return hex(0x55391F, 0.85 + 0.2 * r(x, y, 121))
        }
        // Crops: stalks growing taller and changing colour with the stage.
        func cropPainter(_ stage: Int, _ maxStage: Int, young: UInt32, ripe: UInt32, head: UInt32?, salt: Int) -> Painter {
            { x, y in
                let k = Float(stage) / Float(maxStage)
                let h = 3 + Int(k * 12)
                let col = x % 3 == 1 || (x % 5 == 3 && r(x, 0, salt) > 0.4)
                if !col || 15 - y >= h { return clear }
                let top = 15 - y >= h - 3
                if let hd = head, stage == maxStage && top { return hex(hd, 0.85 + 0.25 * r(x, y, salt + 1)) }
                let c = k > 0.8 ? ripe : young
                return hex(c, 0.75 + 0.35 * r(x, y, salt + 2))
            }
        }
        for st in 0..<8 { p["wheat_stage\(st)"] = cropPainter(st, 7, young: 0x3F9A2C, ripe: 0xB8A340, head: 0xDCBC52, salt: 122) }
        for st in 0..<4 {
            p["carrots_stage\(st)"] = cropPainter(st, 3, young: 0x3F9A2C, ripe: 0x48A832, head: st == 3 ? 0xF08A1A : nil, salt: 125)
            p["potatoes_stage\(st)"] = cropPainter(st, 3, young: 0x3F9A2C, ripe: 0x4AA034, head: st == 3 ? 0xD8B060 : nil, salt: 128)
            p["beetroots_stage\(st)"] = cropPainter(st, 3, young: 0x3F9A2C, ripe: 0x3A8A30, head: st == 3 ? 0xA02838 : nil, salt: 131)
        }
        for (n, _) in BlockRegistry.colors {
            let c = BlockRegistry.colorHex[n] ?? 0xFFFFFF
            p["\(n)_wool"] = { x, y in
                let weave = ((x + y) % 4 == 0 ? 0.9 : 1.0) as Float
                return hex(c, weave * (0.9 + 0.12 * r(x, y, 140)))
            }
            p["\(n)_bed_side"] = { x, y in
                if y >= 10 { return y >= 13 && (x < 3 || x > 12) ? hex(0x6B4F2C) : clear }
                if y >= 7 { return hex(0xA2824E, 0.9 + 0.1 * r(x, y, 141)) }
                return hex(c, 0.9 + 0.1 * r(x, y, 142))
            }
            p["\(n)_bed_top_foot"] = { x, y in hex(c, (x == 0 || x == 15 ? 0.8 : 1) * (0.9 + 0.1 * r(x, y, 143))) }
            p["\(n)_bed_top_head"] = { x, y in
                if y < 7 && x > 1 && x < 14 { return hex(0xF2F2F2, 0.93 + 0.07 * r(x, y, 144)) }
                return hex(c, (x == 0 || x == 15 ? 0.8 : 1) * (0.9 + 0.1 * r(x, y, 143)))
            }
        }
        p["tnt_side"] = { x, y in
            if y >= 5 && y <= 10 {
                if y >= 6 && y <= 9 && (x % 4 == 1 || (y == 6 && x % 4 != 0)) { return hex(0x2A2A2A) }
                return hex(0xEAEAEA)
            }
            return hex(0xC23A28, (x % 4 == 0 ? 0.8 : 1) * (0.9 + 0.1 * r(x, y, 150)))
        }
        p["tnt_top"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            if dx * dx + dy * dy < 4 { return hex(0x3A3A3A) }
            return hex(0xB8B0A0, 0.9 + 0.1 * r(x, y, 151))
        }
        p["tnt_bottom"] = { x, y in hex(0xB8B0A0, 0.85 + 0.1 * r(x, y, 152)) }
        // Nether
        let netherrack: Painter = { x, y in
            let v = blot(x, y, 170, 4) * 0.6 + r(x, y, 171) * 0.4
            return hex(v > 0.62 ? 0x8B3A3A : (v < 0.35 ? 0x5A1E1E : 0x6F2A2A), 0.92 + 0.12 * r(x, y, 172))
        }
        p["netherrack"] = netherrack
        p["nether_quartz_ore"] = ore(netherrack, 0xEDE6DE, 0xC8BEB0, salt: 173)
        p["nether_gold_ore"] = ore(netherrack, 0xF8D23C, 0xE09A20, salt: 174)
        p["ancient_debris_side"] = { x, y in
            let band = (y / 3) % 2 == 0
            return hex(band ? 0x5E4A45 : 0x4A3A36, 0.85 + 0.25 * r(x / 2, y, 175))
        }
        p["ancient_debris_top"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            return hex((dx * dx + dy * dy) < 20 ? 0x6E5650 : 0x4E3E3A, 0.85 + 0.2 * r(x, y, 176))
        }
        p["soul_sand"] = { x, y in
            let face = ((x % 8 == 2 || x % 8 == 5) && (y % 8 == 3)) || (x % 8 == 3 && y % 8 == 5) || (x % 8 == 4 && y % 8 == 5)
            return face ? hex(0x2E221A) : hex(0x5A4434, 0.85 + 0.25 * r(x, y, 177))
        }
        p["soul_soil"] = { x, y in hex(0x4B3A2E, 0.8 + 0.3 * r(x, y, 178)) }
        p["basalt_side"] = { x, y in hex(x % 4 == 0 ? 0x3E3E42 : 0x575759, 0.9 + 0.15 * r(x, y / 3, 179)) }
        p["basalt_top"] = { x, y in
            let dx = abs(Float(x) - 7.5), dy = abs(Float(y) - 7.5)
            return hex(max(dx, dy) > 6.5 ? 0x3E3E42 : 0x626265, 0.9 + 0.12 * r(x, y, 180))
        }
        p["blackstone"] = rock(0x2A2429, grain: 0.3, blotch: 0.25, salt: 181)
        p["polished_blackstone"] = { x, y in
            if x == 0 || y == 0 { return hex(0x2E2A30) }
            if x == 15 || y == 15 { return hex(0x1A171C) }
            return hex(0x3A353C, 0.92 + 0.12 * r(x, y, 190))
        }
        func pbBricks(_ cracked: Bool) -> Painter {
            { x, y in
                let row = y / 4
                let off = row % 2 == 0 ? 0 : 4
                if y % 4 == 3 || (x + off) % 8 == 7 { return hex(0x19161A) }
                if cracked && (abs((x * 3 + y * 5) % 17 - 8) == 0 || (x == 5 + y / 3 && y > 4 && y < 12)) { return hex(0x121013) }
                return hex(0x39333B, 0.88 + 0.2 * r(x, y, 191))
            }
        }
        p["polished_blackstone_bricks"] = pbBricks(false)
        p["cracked_polished_blackstone_bricks"] = pbBricks(true)
        p["chiseled_polished_blackstone"] = { x, y in
            let dx = abs(Float(x) - 7.5), dy = abs(Float(y) - 7.5)
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x1A171C) }
            if max(dx, dy) < 2.5 || (dx + dy > 4.5 && dx + dy < 5.6) { return hex(0x4A444C) }
            return hex(0x332E35, 0.9 + 0.12 * r(x, y, 192))
        }
        p["gilded_blackstone"] = { x, y in
            if r(x / 2, y / 2, 193) < 0.3 && r(x, y, 194) < 0.8 { return hex(r(x, y, 195) > 0.5 ? 0xF4C53A : 0xC98E1E) }
            return hex(0x2A2429, 0.85 + 0.3 * r(x, y, 196))
        }
        p["magma"] = { x, y in
            let crack = blot(x, y, 182, 4) > 0.6 && r(x, y, 183) < 0.7
            return crack ? hex(0xF08A1A, 0.9 + 0.2 * r(x, y, 184)) : hex(0x6A2A10, 0.8 + 0.3 * r(x, y, 185))
        }
        p["nether_bricks"] = { x, y in
            let row = y / 4
            if y % 4 == 3 || x == (row % 2 == 0 ? 7 : 15) { return hex(0x1E0E10) }
            return hex(0x3A1A1E, 0.85 + 0.3 * r(x, y, 186))
        }
        p["red_nether_bricks"] = { x, y in
            let row = y / 4
            if y % 4 == 3 || x == (row % 2 == 0 ? 7 : 15) { return hex(0x2A0808) }
            return hex(0x5A0E10, 0.85 + 0.3 * r(x, y, 187))
        }
        func nylium(_ c: UInt32) -> Painter { { x, y in hex(c, 0.8 + 0.35 * r(x, y, 188)) } }
        p["crimson_nylium"] = nylium(0x952020)
        p["warped_nylium"] = nylium(0x2B8A7A)
        p["crimson_nylium_side"] = { x, y in y < 3 + Int(r(x, 0, 189) * 2) ? nylium(0x952020)(x, y) : netherrack(x, y) }
        p["warped_nylium_side"] = { x, y in y < 3 + Int(r(x, 0, 189) * 2) ? nylium(0x2B8A7A)(x, y) : netherrack(x, y) }
        p["crimson_stem"] = { x, y in hex(x % 3 == 0 ? 0x5C1D2C : 0x7B2D3F, 0.85 + 0.25 * r(x, y / 2, 190)) }
        p["warped_stem"] = { x, y in hex(x % 3 == 0 ? 0x3A2A4A : 0x3E5A5A, 0.85 + 0.25 * r(x, y / 2, 191)) }
        p["crimson_stem_top"] = rings(0x5C1D2C, 0x8A3A48)
        p["warped_stem_top"] = rings(0x3A2A4A, 0x2E8A7A)
        p["nether_wart_block"] = rock(0x7A0A0C, grain: 0.35, blotch: 0.2, salt: 192)
        p["warped_wart_block"] = rock(0x167A7A, grain: 0.35, blotch: 0.2, salt: 193)
        p["shroomlight"] = { x, y in hex(blot(x, y, 194, 4) > 0.5 ? 0xFFC87A : 0xF0923A, 0.9 + 0.2 * r(x, y, 195)) }
        p["crimson_planks"] = planks(0x7E3A56, salt: 196)
        p["warped_planks"] = planks(0x2B6963, salt: 197)
        p["crying_obsidian"] = { x, y in
            if r(x, y, 198) < 0.12 || (blot(x, y, 199, 4) > 0.7 && r(x, y, 200) < 0.4) { return hex(0x8A2AE0) }
            return hex(0x14101E, 0.8 + 0.4 * r(x, y, 75))
        }
        func fungus(_ cap: UInt32, _ stem: UInt32) -> Painter {
            { x, y in
                if y >= 9 && (x == 7 || x == 8) { return hex(stem) }
                let dx = Float(x) - 7.5, dy = Float(y) - 6
                if dx * dx * 0.5 + dy * dy < 9 && y <= 8 { return hex(cap, 0.85 + 0.25 * r(x, y, 201)) }
                return clear
            }
        }
        p["crimson_fungus"] = fungus(0xB02A2A, 0xE8C080)
        p["warped_fungus"] = fungus(0x1E8A7A, 0xE89060)
        func roots(_ c: UInt32) -> Painter {
            { x, y in
                let h = 4 + Int(r(x, 0, 202) * 10)
                if 15 - y >= h || r(x, 1, 203) < 0.35 { return clear }
                return hex(c, 0.75 + 0.35 * r(x, y, 204))
            }
        }
        p["crimson_roots"] = roots(0x8E1E2E)
        p["warped_roots"] = roots(0x16A08A)
        p["weeping_vines"] = { x, y in (x == 7 || x == 8 || (x == 6 && y % 5 == 2)) && r(x, y, 205) > 0.15 ? hex(0x8E1E2E, 0.8 + 0.3 * r(x, y, 206)) : clear }
        p["twisting_vines"] = { x, y in (x == 7 || x == 8 || (x == 9 && y % 5 == 2)) && r(x, y, 207) > 0.15 ? hex(0x16A08A, 0.8 + 0.3 * r(x, y, 208)) : clear }
        for st in 0..<3 {
            p["nether_wart_stage\(st)"] = { x, y in
                let h = 4 + st * 4
                if 15 - y >= h || !(x % 4 == 1 || x % 4 == 2) { return clear }
                return hex(0x8A1A1A, 0.75 + 0.35 * r(x, y, 209))
            }
        }
        p["lava"] = { x, y in
            let v = blot(x, y, 210, 4) * 0.7 + r(x, y, 211) * 0.3
            return v > 0.65 ? hex(0xFFD25A) : (v > 0.4 ? hex(0xF08A1A) : hex(0xC8501A))
        }
        func firePainter(_ hot: UInt32, _ mid: UInt32, _ cool: UInt32) -> Painter {
            { x, y in
                let flame = blot(x, y + 3, 212, 4) * 0.6 + r(x, y, 213) * 0.4
                let h = Float(15 - y) / 15
                if flame < h * 0.9 { return clear }
                return h < 0.3 ? hex(hot) : (h < 0.6 ? hex(mid) : hex(cool))
            }
        }
        p["fire"] = firePainter(0xFFF2A0, 0xFFA020, 0xE04010)
        p["soul_fire"] = firePainter(0xC8FFFF, 0x40E0E8, 0x2090A0)
        p["nether_portal"] = { x, y in
            let v = sinf(Float(x) * 0.8 + Float(y) * 0.4) * 0.3 + r(x, y, 214) * 0.4
            return V4(0.45 + v * 0.3, 0.1, 0.85 + v * 0.1, 0.75)
        }
        p["end_stone"] = { x, y in
            if r(x, y, 215) < 0.08 { return hex(0xC8C088) }
            return hex(0xDDDFA5, 0.9 + 0.12 * r(x, y, 216))
        }
        p["end_stone_bricks"] = { x, y in
            let row = y / 4
            if y % 4 == 3 || (x + (row % 2) * 4) % 8 == 7 { return hex(0xB9B77E) }
            return hex(0xE2E4AE, 0.93 + 0.1 * r(x, y, 217))
        }
        p["purpur_block"] = { x, y in
            if x % 8 == 0 || y % 8 == 0 { return hex(0x8A5E8A) }
            return hex(0xA97BA9, 0.92 + 0.12 * r(x, y, 218))
        }
        p["purpur_pillar"] = { x, y in hex(x % 4 == 0 ? 0x8E628E : 0xAB7FAB, 0.93 + 0.1 * r(x, y / 4, 219)) }
        p["purpur_pillar_top"] = { x, y in
            let dx = abs(Float(x) - 7.5), dy = abs(Float(y) - 7.5)
            return hex(Int(max(dx, dy)) % 3 == 0 ? 0x8E628E : 0xAB7FAB, 0.95 + 0.08 * r(x, y, 220))
        }
        let stoneBricks = p["stone_bricks"]!
        p["mossy_stone_bricks"] = { x, y in
            r(x / 2, y / 2, 221) < 0.35 + 0.2 * Float(y) / 15 ? hex(0x5A7A3A, 0.85 + 0.25 * r(x, y, 222)) : stoneBricks(x, y)
        }
        p["cracked_stone_bricks"] = { x, y in
            if (x == 3 + y / 2 && y < 10) || (x == 12 - (y - 6) / 3 && y > 6) { return hex(0x3E3E3E) }
            return stoneBricks(x, y)
        }
        p["chiseled_stone_bricks"] = { x, y in
            let dx = abs(Float(x) - 7.5), dy = abs(Float(y) - 7.5)
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x525252) }
            let m = max(dx, dy)
            if (m > 5.5 && m < 6.5) || (m < 2.5 && m > 1.5) { return hex(0x5E5E5E) }
            return hex(0x7A7A7A, 0.95 + 0.08 * r(x, y, 223))
        }
        p["bookshelf"] = { x, y in
            if y == 0 || y == 15 || y == 7 || y == 8 { return hex(0xA2824E, 0.9 + 0.1 * r(x, y, 224)) }
            let book = x / 2
            let colors: [UInt32] = [0x8A2A2A, 0x2A4A8A, 0x3A6A2A, 0x6A4A2A, 0x7A2A6A, 0x2A6A6A, 0x8A6A2A, 0x4A2A2A]
            let c = colors[Int(r(book, y / 8, 225) * 8) % 8]
            if x % 2 == 1 && r(book, y / 8, 226) < 0.3 { return hex(0x2A1E12) }
            let edge = y % 8 == 1 || y % 8 == 6
            return hex(c, edge ? 1.2 : 0.95)
        }
        p["cobweb"] = { x, y in
            let ring = max(abs(x - 8), abs(y - 8))
            if x == y || x == 15 - y || x == 8 || y == 8 { return V4(0.9, 0.9, 0.92, r(x, y, 227) < 0.2 ? 0 : 1) }
            if ring == 3 || ring == 6 { return V4(0.85, 0.85, 0.88, r(x, y, 228) < 0.4 ? 0 : 1) }
            return clear
        }
        p["sugar_cane"] = { x, y in
            let stalk = x == 3 || x == 4 || x == 9 || x == 10 || x == 13
            if !stalk { return clear }
            let v: Float = (y + x) % 6 == 0 ? 0.65 : 0.8
            return V4(v, v, v, 1)
        }
        p["end_portal_frame_top"] = { x, y in
            let dx = abs(Float(x) - 7.5), dy = abs(Float(y) - 7.5)
            if max(dx, dy) < 4 { return hex(0x2A4A3A, 0.9 + 0.2 * r(x, y, 229)) }
            return hex(0x3E6A5A, 0.85 + 0.2 * r(x, y, 230))
        }
        p["end_portal_frame_side"] = { x, y in
            if y < 3 { return hex(0x3E6A5A, 0.85 + 0.2 * r(x, y, 231)) }
            return hex(0xDDDFA5, 0.85 + 0.15 * r(x, y, 232))
        }
        p["end_portal_frame_eye"] = { x, y in
            let dx = abs(Float(x) - 7.5), dy = abs(Float(y) - 7.5)
            if dx < 1.5 && dy < 3 { return hex(0x0E2A12) }
            return hex(max(dx, dy) > 6 ? 0x1E5A3A : 0x3E9A5A, 0.9 + 0.2 * r(x, y, 233))
        }
        p["end_portal"] = { x, y in
            if r(x, y, 234) > 0.93 {
                let stars: [UInt32] = [0x2A8A7A, 0x5AB0A0, 0x9AD0E0, 0x3A5AA0]
                return hex(stars[Int(r(x, y, 235) * 4) % 4])
            }
            return hex(0x060A10, 0.8 + 0.4 * r(x / 2, y / 2, 236))
        }
        p["dragon_egg"] = { x, y in
            if r(x, y, 237) > 0.9 { return hex(0x5A1A6A) }
            return hex(0x0E0A14, 0.8 + 0.4 * r(x, y, 238))
        }
        p["chorus_plant"] = { x, y in
            let dx = abs(Float(x) - 7.5), dy = abs(Float(y) - 7.5)
            if max(dx, dy) > 6.5 { return hex(0x5A3A6A) }
            return hex(0x8A6A9A, 0.85 + 0.25 * r(x, y, 240))
        }
        p["chorus_flower"] = { x, y in
            let dx = abs(Float(x) - 7.5), dy = abs(Float(y) - 7.5)
            if max(dx, dy) < 3 { return hex(0xD8C0E0, 0.9 + 0.2 * r(x, y, 241)) }
            return hex(0x9A7AAA, 0.85 + 0.25 * r(x, y, 242))
        }
        p["end_rod"] = { x, y in hex(x < 8 ? 0xF4EEE0 : 0xE0D6C8, 0.95 + 0.05 * r(x, y, 239)) }
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
        p["rain_drop"] = { x, y in (x == 7 || x == 8) ? V4(0.8, 0.85, 1, 0.8) : clear }
        p["snow_flake"] = { x, y in
            let dx = abs(x * 2 - 15), dy = abs(y * 2 - 15)
            if dx + dy < 14 && (dx < 3 || dy < 3 || abs(dx - dy) < 3) { return V4(1, 1, 1, 0.95) }
            return clear
        }
        // Recoloured hearts: absorption (gold), poison (green), wither (black).
        for (name, tint) in [("gold", V3(1.0, 0.8, 0.15)), ("poison", V3(0.55, 0.72, 0.2)), ("wither", V3(0.28, 0.24, 0.22))] {
            for (suffix, fill) in [("", 2), ("_half", 1)] {
                p["heart_\(name)\(suffix)"] = { x, y in
                    let c = heart(x, y, fill)
                    guard c.w > 0, c.x > c.y * 1.4 else { return c }
                    let b = min(1, c.x * 1.25)
                    return V4(tint.x * b, tint.y * b, tint.z * b, c.w)
                }
            }
        }
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
        p["smoke"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            let d = (dx * dx + dy * dy).squareRoot()
            if d > 7 || r(x / 2, y / 2, 160) < 0.25 { return clear }
            return V4(0.8, 0.8, 0.8, 1)
        }
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
        overworldPainters(&p)
        buildingPainters(&p)
        redstonePainters(&p)
        magicPainters(&p)
        for (k, v) in ItemTextures.painters() { p[k] = v }
        for (k, v) in Font.painters() { p[k] = v }
        return p
    }

    static func base() -> [UInt8] {
        registerAll()
        let count = Tex.count
        let table = painters()
        var data = [UInt8](repeating: 0, count: S * S * 4 * count)
        let missing = Tex.names.filter { table[$0] == nil }
        if !missing.isEmpty { print("textures without a painter: \(missing.joined(separator: ", "))") }
        if count > 1024 { print("warning: \(count) texture layers exceed the 10-bit layer index") }
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
