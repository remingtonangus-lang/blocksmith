import Foundation

// Later reference-game blocks: resin (from Barkwraith hearts), bamboo planks and mosaic, and the
// newer ground plants: firefly bushes (glow, near water), leaf litter (forest floors), wildflowers
// (birch forests and meadows), bushes, short and tall dry grass (deserts, badlands) and cactus flowers.
extension BlockRegistry {
    func registerSpringBlocks() {
        func cube(_ n: String, _ disp: String, _ t: String? = nil, h: Float, tool: ToolType, snd: SoundMat, req: Bool = false) {
            var d = BlockDef(n, disp)
            d.tex = [t ?? n]; d.hardness = h; d.tool = tool; d.sound = snd; d.requiresTool = req
            add(d)
        }
        cube("resin_block", "Block of Resin", h: 0, tool: .none, snd: .plant)
        cube("resin_bricks", "Resin Bricks", h: 1.5, tool: .pickaxe, snd: .stone, req: true)
        cube("chiseled_resin_bricks", "Chiseled Resin Bricks", h: 1.5, tool: .pickaxe, snd: .stone, req: true)
        family("resin_bricks", "resin_brick", "Resin Brick", h: 1.5, tool: .pickaxe, req: true, snd: .stone, stairs: true, slab: true, fence: false, wall: true)
        cube("bamboo_planks", "Bamboo Planks", h: 2, tool: .axe, snd: .wood)
        family("bamboo_planks", "bamboo", "Bamboo", h: 2, tool: .axe, req: false, snd: .wood, stairs: true, slab: true, fence: true, wall: false)
        cube("bamboo_mosaic", "Bamboo Mosaic", h: 2, tool: .axe, snd: .wood)
        family("bamboo_mosaic", "bamboo_mosaic", "Bamboo Mosaic", h: 2, tool: .axe, req: false, snd: .wood, stairs: true, slab: true, fence: false, wall: false)

        func plant(_ n: String, _ disp: String, emit: UInt8 = 0, tint: UInt8 = 0) {
            var d = BlockDef(n, disp)
            d.tex = [n]; d.render = .cross; d.layer = .cutout; d.opaque = false; d.collide = false
            d.hardness = 0; d.sound = .plant; d.replaceable = emit == 0; d.emit = emit; d.skyStop = false; d.tint = tint
            add(d)
        }
        plant("firefly_bush", "Firefly Bush", emit: 2)
        plant("bush", "Bush", tint: 1)
        plant("short_dry_grass", "Short Dry Grass")
        plant("tall_dry_grass", "Tall Dry Grass")
        plant("cactus_flower", "Cactus Flower")
        // Flat ground cover (like petals): leaf litter and wildflowers.
        for (n, disp) in [("leaf_litter", "Leaf Litter"), ("wildflowers", "Wildflowers")] {
            var d = BlockDef(n, disp)
            d.tex = [n]; d.render = .model; d.layer = .cutout; d.opaque = false; d.collide = false
            d.boxes = [Box(0, 0, 0, 16, 1, 16)]; d.hardness = 0; d.sound = .plant; d.replaceable = true; d.skyStop = false
            add(d)
        }
    }
}

extension TextureGen {
    static func springPainters(_ p: inout [String: Painter]) {
        p["resin_block"] = { x, y in hex(0xD9701E, 0.85 + 0.25 * blot(x, y, 1801, 4) + 0.06 * r(x, y, 1802)) }
        p["resin_bricks"] = { x, y in
            let row = y / 4, off = row % 2 == 0 ? 0 : 4
            if y % 4 == 3 || (x + off) % 8 == 7 { return hex(0x8A4212, 0.9) }
            return hex(0xCC6420, 0.88 + 0.18 * r(x / 2, y, 1803))
        }
        p["chiseled_resin_bricks"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x8A4212) }
            let dx = abs(x - 8), dy = abs(y - 8)
            if dx + dy == 5 || dx + dy == 2 { return hex(0x9A4A16) }
            return hex(0xD06A22, 0.9 + 0.12 * r(x, y, 1804))
        }
        p["bamboo_mosaic"] = { x, y in
            let cell = (x / 8 + y / 4) % 2
            if y % 4 == 3 { return hex(0x9A8438) }
            let vertical = cell == 0 ? x % 8 == 7 : false
            return hex(0xC8B25A, vertical ? 0.75 : 0.92 + 0.1 * r(x / 2, y, 1805))
        }
        p["firefly_bush"] = { x, y in
            // Low dark bush with a few bright firefly specks.
            let stem = (x == 5 || x == 10) && y > 9
            if stem { return hex(0x4A3A22) }
            if r(x, y, 1806) < 0.05 && y < 9 { return hex(0xFFF27A) }
            let leaf = y > 3 && y < 12 && r(x, y, 1807) < 0.55 + 0.03 * Float(y)
            return leaf ? hex(0x3E5A2A, 0.8 + 0.3 * r(x, y, 1808)) : clear
        }
        p["bush"] = { x, y in
            let leaf = y > 5 && r(x, y, 1809) < 0.35 + 0.05 * Float(y - 5)
            let v: Float = 0.55 + 0.4 * r(x, y, 1810)
            return leaf ? V4(v, v, v, 1) : clear            // grass-tinted
        }
        func dryGrass(_ tall: Bool, _ salt: Int) -> Painter {
            { x, y in
                let blade = (x * 5 + 3) % 4 == 0 || (x * 3 + 1) % 7 == 0
                let top = tall ? 1 + Int(r(x, 0, salt) * 5) : 8 + Int(r(x, 0, salt) * 5)
                return blade && y >= top ? hex(0xC4A866, 0.8 + 0.3 * r(x, y, salt + 1)) : clear
            }
        }
        p["short_dry_grass"] = dryGrass(false, 1811)
        p["tall_dry_grass"] = dryGrass(true, 1813)
        p["cactus_flower"] = { x, y in
            let dx = x - 8, dy = y - 11
            if dx * dx + dy * dy <= 2 { return hex(0xF5E070) }
            if dx * dx + (dy + 1) * (dy + 1) <= 14 && y <= 13 && y >= 7 { return hex(0xF06AA0, 0.9 + 0.15 * r(x, y, 1815)) }
            return clear
        }
        p["leaf_litter"] = { x, y in r(x, y, 1816) < 0.45 ? hex([0xA06A2A, 0x8A5A22, 0xB8862E][Int(r(x, y, 1817) * 3) % 3], 0.9) : clear }
        p["wildflowers"] = { x, y in
            let f = r(x / 3, y / 3, 1818)
            if f < 0.3 && (x % 3 == 1) && (y % 3 == 1) { return hex(0xFFE04A) }
            if f < 0.3 && ((x % 3 == 1) != (y % 3 == 1)) { return hex(0xF4F0E0) }
            return y % 4 == 0 && r(x, y, 1819) < 0.3 ? hex(0x5A8A30) : clear
        }
    }
}

extension Recipes {
    static func springRecipes() -> [Recipe?] {
        var r: [Recipe?] = []
        r.append(shaped(["XXX", "XXX", "XXX"], ["X": "resin_clump"], "resin_block"))
        r.append(shapeless(["resin_block"], "resin_clump", 9))
        r.append(shaped(["XX", "XX"], ["X": "resin_brick"], "resin_bricks"))
        r.append(shaped(["X", "X"], ["X": "resin_brick_slab"], "chiseled_resin_bricks"))
        r.append(shaped(["X  ", "XX ", "XXX"], ["X": "resin_bricks"], "resin_brick_stairs", 4))
        r.append(shaped(["XXX"], ["X": "resin_bricks"], "resin_brick_slab", 6))
        r.append(shaped(["XXX", "XXX"], ["X": "resin_bricks"], "resin_brick_wall", 6))
        r.append(shaped(["X", "X"], ["X": "bamboo_slab"], "bamboo_mosaic"))
        r.append(shaped(["X  ", "XX ", "XXX"], ["X": "bamboo_planks"], "bamboo_stairs", 4))
        r.append(shaped(["XXX"], ["X": "bamboo_planks"], "bamboo_slab", 6))
        r.append(shaped(["X  ", "XX ", "XXX"], ["X": "bamboo_mosaic"], "bamboo_mosaic_stairs", 4))
        r.append(shaped(["XXX"], ["X": "bamboo_mosaic"], "bamboo_mosaic_slab", 6))
        r.append(shaped(["#S#", "#S#"], ["#": "bamboo_planks", "S": "stick"], "bamboo_fence", 3))
        r.append(shapeless(["wildflowers"], "yellow_dye", 1))
        r.append(shapeless(["cactus_flower"], "pink_dye", 1))
        return r
    }
}
