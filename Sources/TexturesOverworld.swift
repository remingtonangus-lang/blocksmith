import Foundation

// Procedural painters for the surface block expansion (original art; colours chosen to read like
// the materials they stand for).
extension TextureGen {
    static func overworldPainters(_ p: inout [String: Painter]) {
        // Grey-scale grass-like blades (tinted by biome colour in the shader).
        func blades(_ salt: Int, minH: Int, maxH: Int, fern: Bool = false) -> Painter {
            { x, y in
                let bladeH = minH + Int(r(x, 0, salt) * Float(maxH - minH))
                if 15 - y >= bladeH || r(x, 1, salt + 1) < (fern ? 0.1 : 0.25) { return clear }
                if fern && (x + y) % 3 == 0 && y < 12 { return clear }
                let k: Float = 0.6 + 0.4 * Float(15 - y) / 15 + 0.12 * r(x, y, salt + 2)
                return V4(k * 0.8, k * 0.8, k * 0.8, 1)
            }
        }
        // A flower: green stem + a blob of petals with a centre.
        func flower(_ petal: UInt32, _ center: UInt32, _ salt: Int, top: Int = 5, size: Float = 2.8) -> Painter {
            { x, y in
                let dx = Float(x) - 7.5, dy = Float(y) - Float(top)
                let d = (dx * dx + dy * dy).squareRoot()
                if d < 1.1 { return hex(center) }
                if d < size && r(x, y, salt) > 0.1 { return hex(petal, 0.85 + 0.25 * r(x, y, salt + 1)) }
                if (x == 7 || x == 8) && y > top { return hex(0x3E7A2A, 0.9 + 0.2 * r(x, y, salt + 2)) }
                if y > 11 && abs(x - 7) == Int(Float(15 - y) * 0.8) + 1 { return hex(0x4A8A30) }
                return clear
            }
        }
        func speckle(_ base: UInt32, _ dot: UInt32, _ amount: Float, _ salt: Int) -> Painter {
            { x, y in
                // Dots gather in clumps (blotch-weighted), the base gets soft two-scale mottling.
                let clump: Float = blot(x, y, salt + 3, 4)
                if r(x, y, salt) < amount * (0.4 + 1.2 * clump) { return hex(dot, 0.9 + 0.2 * r(x, y, salt + 1)) }
                let m: Float = (blot(x, y, salt + 4, 8) - 0.5) * 0.12 + (r(x, y, salt + 2) - 0.5) * 0.12
                return hex(base, 0.96 + m)
            }
        }
        func bricks(_ c: UInt32, _ mortar: UInt32, rowH: Int = 4, len: Int = 8, _ salt: Int) -> Painter {
            { x, y in
                let row = y / rowH, ly = y % rowH
                let lx = (x + (row % 2) * len / 2) % len
                if ly == rowH - 1 || lx == len - 1 { return hex(mortar) }
                // Per-brick tone, lit top edge and left end, shaded bottom edge, fine grain.
                let brick = (x + (row % 2) * len / 2) / len
                var k: Float = 0.94 + (r(row, brick, salt + 7) - 0.5) * 0.12 + (r(x, y, salt) - 0.5) * 0.1
                if ly == 0 || lx == 0 { k += 0.08 } else if ly == rowH - 2 { k -= 0.07 }
                return hex(c, k)
            }
        }
        func tallPlant(_ bottom: Bool, _ stem: UInt32, _ bloom: UInt32, _ salt: Int) -> Painter {
            { x, y in
                if bottom {
                    if (x == 7 || x == 8) { return hex(stem, 0.9 + 0.2 * r(x, y, salt)) }
                    if (y > 4 && abs(x - 7) == (15 - y) / 3 + 1) { return hex(stem, 0.85) }
                    return clear
                }
                let dx = Float(x) - 7.5, dy = Float(y) - 7
                if dx * dx + dy * dy < 16 && r(x, y, salt + 1) > 0.15 { return hex(bloom, 0.85 + 0.25 * r(x, y, salt + 2)) }
                if (x == 7 || x == 8) && y > 9 { return hex(stem) }
                return clear
            }
        }

        // Woods: bark, end grain, leaves, planks, saplings.
        let woods: [(String, UInt32, UInt32, UInt32, UInt32)] = [
            // name, bark, wood/plank, leaves (grey = tinted), sapling leaf colour
            ("acacia", 0x676157, 0xAD5D32, 0, 0x6E8A2A), ("dark_oak", 0x3C2E1A, 0x4F3218, 0, 0x2E5A1E),
            ("jungle", 0x564419, 0xA07351, 0, 0x3E8A1E), ("mangrove", 0x544130, 0x773631, 0, 0x4E8A3A),
            ("cherry", 0x36202A, 0xE2B2AC, 0xE9A5C4, 0xE9A5C4),
            ("pale_oak", 0x5E5652, 0xE4DAD3, 0xA3AB97, 0xA3AB97),
        ]
        for (i, w) in woods.enumerated() {
            let s = 300 + i * 10
            p["\(w.0)_log"] = bark(w.1, salt: s)
            p["\(w.0)_log_top"] = rings(w.1, w.2)
            p["\(w.0)_planks"] = planks(w.2, salt: s + 3)
            if w.3 == 0 {
                p["\(w.0)_leaves"] = leafy(nil, holes: w.0 == "jungle" ? 0.1 : 0.2, salt: s + 4)
            } else {
                p["\(w.0)_leaves"] = foliage(w.3, holes: 0.15, salt: s + 4)
            }
            let sapName = w.0 == "mangrove" ? "mangrove_propagule" : "\(w.0)_sapling"
            p[sapName] = ItemTextures.painter(Sprite(mask: "sapling", base: w.4, extras: ["a": w.1, "b": w.2]))
        }
        p["mangrove_roots"] = { x, y in
            let root = (x + y / 2) % 5 == 0 || (x - y / 3 + 20) % 6 == 0
            return root ? hex(0x4A3A28, 0.85 + 0.25 * r(x, y, 350)) : clear
        }
        p["bamboo_planks"] = planks(0xC8B25A, salt: 351)

        // Ground.
        p["podzol_top"] = speckle(0x5A3D1E, 0x7A5A2A, 0.3, 360)
        p["podzol_side"] = { x, y in y < 4 - Int(r(x, 0, 361) * 2) ? hex(0x5A3D1E, 0.9 + 0.2 * r(x, y, 362)) : hex(0x866043, 0.88 + 0.2 * r(x, y, 363)) }
        p["coarse_dirt"] = speckle(0x77553A, 0x5A4030, 0.3, 364)
        p["rooted_dirt"] = { x, y in (x * 7 + y * 3) % 11 == 0 ? hex(0x9A7A5A) : hex(0x866043, 0.88 + 0.2 * r(x, y, 365)) }
        p["mycelium_top"] = speckle(0x6F6265, 0x9A8A9A, 0.25, 366)
        p["mycelium_side"] = { x, y in y < 3 - Int(r(x, 0, 367) * 2) ? hex(0x6F6265, 0.9 + 0.2 * r(x, y, 368)) : hex(0x866043, 0.88 + 0.2 * r(x, y, 369)) }
        p["mud"] = rock(0x3C3837, grain: 0.18, blotch: 0.2, salt: 370)
        p["packed_mud"] = rock(0x8E6B50, grain: 0.2, blotch: 0.15, salt: 371)
        p["mud_bricks"] = bricks(0x89684F, 0x6A4E3A, 372)
        p["ice"] = { x, y in
            let crack = (x * 3 + y * 7) % 13 == 0
            return V4(0.62, 0.78, 1.0, crack ? 0.9 : 0.62 + 0.08 * r(x, y, 373))
        }
        // Packed / blue ice: frosty mottling, pale fracture lines and a few bright crystal glints.
        func iceP(_ c: UInt32, _ salt: Int) -> Painter {
            { x, y in
                var k: Float = 0.94 + (blot(x, y, salt, 4) - 0.5) * 0.14 + (r(x, y, salt + 1) - 0.5) * 0.05
                let w1: Float = sinf(Float(y) * 0.8) * 1.2
                let e1: Float = Float(x) - Float(y) * 0.6 - 4 + w1
                let f1 = abs(e1) < 0.55
                let e2: Float = Float(y) - Float(x) * 0.35 - 9
                let f2 = abs(e2) < 0.5 && x > 4
                if f1 || f2 { k += 0.16 }
                if r(x, y, salt + 2) > 0.985 { k += 0.25 }
                return hex(c, k)
            }
        }
        p["packed_ice"] = iceP(0x8DB4FA, 374)
        p["blue_ice"] = iceP(0x74A8FB, 375)
        p["calcite"] = speckle(0xDFE0DC, 0xC8C8C0, 0.12, 376)
        p["dripstone_block"] = { x, y in hex(0x866B5C, (x + Int(r(0, y / 3, 377) * 4)) % 4 == 0 ? 0.8 : 0.95 + 0.1 * r(x, y, 378)) }
        p["pointed_dripstone"] = { x, y in
            let w = max(0, 6 - y / 3)
            return abs(x - 7) <= w / 2 + (y < 3 ? 2 : 0) ? hex(0x866B5C, 0.85 + 0.25 * r(x, y, 379)) : clear
        }
        p["moss_block"] = speckle(0x5A7A2A, 0x6E9A34, 0.35, 380)
        p["red_sandstone"] = { x, y in hex(y < 3 ? 0xB5621F : 0xBA6522, 0.9 + 0.12 * r(x, y / 2, 381)) }
        p["red_sandstone_top"] = { x, y in hex(0xB9642A, 0.92 + 0.1 * r(x, y, 382)) }
        let terracotta: [(String, UInt32)] = [("white", 0xD1B2A1), ("orange", 0xA15325), ("yellow", 0xBA8523), ("brown", 0x4D3323),
                                              ("red", 0x8F3D2E), ("light_gray", 0x876A61)]
        for (i, t) in terracotta.enumerated() { p["\(t.0)_terracotta"] = rock(t.1, grain: 0.1, blotch: 0.08, salt: 383 + i) }
        p["smooth_basalt"] = rock(0x48484E, grain: 0.12, blotch: 0.1, salt: 390)
        p["amethyst_block"] = { x, y in hex((x + y) % 5 == 0 ? 0xC8A0F0 : 0x8A5ACA, 0.85 + 0.25 * r(x, y, 391)) }
        p["budding_amethyst"] = { x, y in r(x / 2, y / 2, 392) < 0.12 ? hex(0x5A2A8A) : hex(0x8A5ACA, 0.85 + 0.25 * r(x, y, 393)) }
        p["amethyst_cluster"] = { x, y in
            let spikes = [(4, 6), (8, 2), (11, 5)]
            for (sx, top) in spikes where y >= top && abs(x - sx) <= (y - top) / 4 { return hex(0xC89AF5, 0.8 + 0.3 * r(x, y, 394)) }
            return clear
        }
        p["sculk"] = { x, y in
            if r(x, y, 395) < 0.06 { return hex(0x29DFEB) }
            return hex(0x0D1E24, 0.8 + 0.5 * r(x / 2, y / 2, 396))
        }
        p["sculk_shrieker_top"] = { x, y in abs(x - 7) < 4 && abs(y - 7) < 4 ? hex(0xD8D0A8, 0.9 + 0.1 * r(x, y, 397)) : hex(0x0D1E24) }
        p["sculk_shrieker_side"] = { x, y in y > 7 ? hex(0x0D1E24, 0.8 + 0.4 * r(x, y, 398)) : hex(0x3A5A5A, 0.9 + 0.2 * r(x, y, 399)) }
        p["reinforced_deepslate"] = { x, y in
            if x < 2 || x > 13 || y < 2 || y > 13 { return hex(0x6A6A5A, 0.85 + 0.2 * r(x, y, 400)) }
            return hex(0x2A2A2E, 0.85 + 0.2 * r(x, y, 401))
        }
        p["polished_deepslate"] = { x, y in x == 0 || y == 0 || x == 15 || y == 15 ? hex(0x2E2E30) : hex(0x48484A, 0.92 + 0.12 * r(x, y, 402)) }
        p["deepslate_bricks"] = bricks(0x4A4A4C, 0x262628, 403)
        p["deepslate_tiles"] = bricks(0x363638, 0x1E1E20, rowH: 8, len: 8, 404)
        p["soul_lantern"] = { x, y in abs(x - 7) < 4 && y > 3 && y < 13 ? hex(0x6AE0F0, 0.8 + 0.3 * r(x, y, 405)) : hex(0x3A3A40) }

        // Plants.
        p["fern"] = blades(410, minH: 8, maxH: 14, fern: true)
        p["tall_grass_bottom"] = blades(412, minH: 14, maxH: 16)
        p["tall_grass_top"] = blades(414, minH: 6, maxH: 14)
        p["large_fern_bottom"] = blades(416, minH: 14, maxH: 16, fern: true)
        p["large_fern_top"] = blades(418, minH: 6, maxH: 14, fern: true)
        p["sunflower_bottom"] = tallPlant(true, 0x4A8A30, 0, 420)
        p["sunflower_top"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 6.5
            let d = (dx * dx + dy * dy).squareRoot()
            if d < 2.5 { return hex(0x5A3A12) }
            if d < 6 { return hex(0xF5C52A, 0.85 + 0.25 * r(x, y, 421)) }
            if (x == 7 || x == 8) && y > 12 { return hex(0x4A8A30) }
            return clear
        }
        p["lilac_bottom"] = tallPlant(true, 0x4A7A30, 0, 422)
        p["lilac_top"] = tallPlant(false, 0x4A7A30, 0xC89AD8, 423)
        p["rose_bush_bottom"] = tallPlant(true, 0x2E6A22, 0, 424)
        p["rose_bush_top"] = tallPlant(false, 0x2E6A22, 0xC81E1E, 425)
        p["peony_bottom"] = tallPlant(true, 0x4A7A30, 0, 426)
        p["peony_top"] = tallPlant(false, 0x4A7A30, 0xE8B0D8, 427)
        p["allium"] = flower(0xB070E0, 0x9A50C8, 430, top: 4, size: 3.2)
        p["azure_bluet"] = flower(0xF2F2F2, 0xE8D040, 432, top: 7, size: 2.4)
        p["red_tulip"] = flower(0xD83A2A, 0xB82A1A, 434, top: 5, size: 2.2)
        p["orange_tulip"] = flower(0xF0842A, 0xD06A1A, 436, top: 5, size: 2.2)
        p["white_tulip"] = flower(0xF0F0F0, 0xD8D8D8, 438, top: 5, size: 2.2)
        p["pink_tulip"] = flower(0xF0A8C8, 0xE088B0, 440, top: 5, size: 2.2)
        p["oxeye_daisy"] = flower(0xF4F4F4, 0xE8C83A, 442, top: 5, size: 3)
        p["lily_of_the_valley"] = flower(0xF8F8F8, 0xE8F0E0, 444, top: 6, size: 1.8)
        p["blue_orchid"] = flower(0x2AA8F0, 0x1A78C8, 446, top: 5, size: 2.8)
        p["pink_petals"] = { x, y in y > 11 && r(x, y, 448) < 0.5 ? hex(0xF0A0C8) : (y > 13 && x % 3 == 0 ? hex(0x4A8A30) : clear) }
        p["dead_bush"] = { x, y in
            let branch = (x == 7 && y > 6) || (abs(x - 7) == (13 - y) && y > 4 && y < 13) || (abs(x - 7) == (y - 2) / 2 && y < 7 && y > 2)
            return branch ? hex(0x7A5A2A, 0.85 + 0.25 * r(x, y, 449)) : clear
        }
        p["brown_mushroom"] = { x, y in
            if y >= 6 && y <= 8 && abs(x - 7) < 5 { return hex(0x9A6A4A, 0.9 + 0.2 * r(x, y, 450)) }
            if y > 8 && (x == 7 || x == 8) { return hex(0xD8D0C0) }
            return clear
        }
        p["red_mushroom"] = { x, y in
            if y >= 5 && y <= 8 && abs(x - 7) < 4 + (y - 5) / 2 { return r(x, y, 451) < 0.15 ? hex(0xF0F0F0) : hex(0xC82A1E) }
            if y > 8 && (x == 7 || x == 8) { return hex(0xE0D8C8) }
            return clear
        }
        for st in 0...3 {
            p["sweet_berry_bush_stage\(st)"] = { x, y in
                if 15 - y > 6 + st * 2 { return clear }
                if st >= 2 && r(x, y, 452) < 0.08 * Float(st) { return hex(0xC01E3A) }
                return r(x, y, 453) < 0.35 ? clear : hex(0x3A6A2A, 0.8 + 0.3 * r(x, y, 454))
            }
        }
        p["mushroom_stem"] = speckle(0xD8D0C0, 0xC8C0B0, 0.2, 455)
        p["mushroom_block_inside"] = speckle(0xD8C8A8, 0xC8B898, 0.2, 456)
        p["brown_mushroom_block"] = speckle(0x956F51, 0x7A5A40, 0.2, 457)
        p["red_mushroom_block"] = { x, y in r(x / 3, y / 3, 458) < 0.18 ? hex(0xF0E8E0) : hex(0xC0281E, 0.9 + 0.15 * r(x, y, 459)) }
        p["lily_pad"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            if dx * dx + dy * dy > 56 || (dx > 0 && abs(dy) < 1) { return clear }
            let v: Float = 0.55 + 0.35 * r(x, y, 460)
            return V4(v, v, v, 1)
        }
        p["vine"] = { x, y in
            let strand = (x + Int(r(0, y / 4, 461) * 3)) % 4 == 0 || r(x, y, 462) < 0.25
            let v: Float = 0.5 + 0.4 * r(x, y, 463)
            return strand ? V4(v, v, v, 1) : clear
        }
        p["bamboo_stalk"] = { x, y in y % 6 == 0 ? hex(0x5A8A1A) : hex(0x7AAA2A, 0.9 + 0.15 * r(x, y, 464)) }
        p["melon_side"] = { x, y in hex(x % 4 < 2 ? 0x6A9A1E : 0x8AB82E, 0.9 + 0.15 * r(x, y, 465)) }
        p["melon_top"] = { x, y in
            let d = abs(Float(x) - 7.5) + abs(Float(y) - 7.5)
            return hex(Int(d) % 3 == 0 ? 0x6A9A1E : 0x8AB82E, 0.9 + 0.15 * r(x, y, 466))
        }
        p["pumpkin_side"] = { x, y in hex(x % 4 == 0 ? 0xB86A0E : 0xE38A1D, 0.9 + 0.15 * r(x, y, 467)) }
        p["pumpkin_top"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            if dx * dx + dy * dy < 3 { return hex(0x5A6A1A) }
            return hex(0xD8801A, 0.88 + 0.15 * r(x, y, 468))
        }
        p["azalea_top"] = speckle(0x6A8A2A, 0x5A7A22, 0.3, 469)
        p["azalea_side"] = { x, y in y < 8 ? hex(0x6A8A2A, 0.85 + 0.25 * r(x, y, 470)) : ((x == 7 || x == 8) ? hex(0x6A5030) : clear) }
        p["cave_vines"] = { x, y in
            if (x == 7 || x == 8) { return hex(0x4A7A2A, 0.85 + 0.25 * r(x, y, 471)) }
            if r(x, y, 472) < 0.12 && y % 5 == 3 { return hex(0xF5A83A) }
            if abs(x - 7) < 3 && r(x, y, 473) < 0.3 { return hex(0x5A8A30) }
            return clear
        }
        p["seagrass"] = { x, y in
            let blade = (x % 4 == 1 && y > Int(r(x, 0, 474) * 6)) || (x % 5 == 3 && y > 4)
            return blade ? hex(0x3A8A2A, 0.8 + 0.3 * r(x, y, 475)) : clear
        }
        p["kelp"] = { x, y in
            if x == 7 || x == 8 { return hex(0x4A7A1E, 0.85 + 0.2 * r(x, y, 476)) }
            if abs(x - 7) < 4 && (y + x) % 5 < 2 { return hex(0x5A8A28, 0.85 + 0.2 * r(x, y, 477)) }
            return clear
        }
        let corals: [(String, UInt32)] = [("tube", 0x3050D0), ("brain", 0xD050A0), ("bubble", 0xA020B0), ("fire", 0xD03030), ("horn", 0xE0C030)]
        for (i, c) in corals.enumerated() {
            p["\(c.0)_coral_block"] = speckle(c.1, c.1 & 0xDFDFDF, 0.3, 480 + i * 2)
            p["\(c.0)_coral"] = { x, y in
                let branch = (x == 7 && y > 3) || (abs(x - 7) == (12 - y) / 2 && y > 2 && y < 12) || (abs(x - 7) == 5 && y < 6 && y > 1)
                return branch ? hex(c.1, 0.85 + 0.3 * r(x, y, 481 + i * 2)) : clear
            }
        }
        p["sea_lantern"] = { x, y in (x + y) % 4 == 0 || (x - y + 16) % 4 == 0 ? hex(0xF0F8F0) : hex(0xB8D8D0, 0.95 + 0.1 * r(x, y, 490)) }
        p["prismarine"] = { x, y in hex(r(x / 3, y / 3, 491) < 0.5 ? 0x63A598 : 0x5A9A8C, 0.9 + 0.2 * r(x, y, 492)) }
        p["prismarine_bricks"] = bricks(0x63AB9E, 0x4A8A7E, 493)
        p["dark_prismarine"] = bricks(0x335B4B, 0x223E32, rowH: 8, len: 8, 494)
        p["sponge"] = { x, y in r(x, y, 495) < 0.15 ? hex(0x9A9A2A) : hex(0xC8C84A, 0.9 + 0.15 * r(x, y, 496)) }
        p["wet_sponge"] = { x, y in r(x, y, 497) < 0.15 ? hex(0x7A7A1A) : hex(0xA8A83A, 0.9 + 0.15 * r(x, y, 498)) }
    }
}
