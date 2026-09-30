import Foundation

// Brewing stand, enchanting table, beacon, anvils (3 wear stages), filled cauldrons.
//   brewing_stand: bottles bitmask (8)      water_cauldron: level 1-3 (3)
extension BlockRegistry {
    func registerMagicBlocks() {
        func model(_ n: String, _ disp: String, _ tex: [String], _ boxes: [Box], h: Float, tool: ToolType = .pickaxe, snd: SoundMat = .stone,
                   emit: UInt8 = 0, req: Bool = false, group: String? = nil, hidden: Bool = false) {
            var d = BlockDef(n, disp)
            d.tex = tex; d.render = .model; d.layer = .cutout; d.opaque = false; d.boxes = boxes; d.hardness = h; d.tool = tool
            d.sound = snd; d.emit = emit; d.requiresTool = req; d.skyStop = false; d.group = group; d.hidden = hidden
            add(d)
        }
        func t6(_ s: String) -> [UInt16] { [UInt16](repeating: Tex.id(s), count: 6) }

        // Brewing stand: stone base, blaze rod, up to three bottles (bit per slot).
        for m in 0..<8 {
            var boxes = [Box(1, 0, 1, 7, 2, 7, tex: t6("brewing_stand_base")), Box(9, 0, 5, 15, 2, 11, tex: t6("brewing_stand_base")),
                         Box(1, 0, 9, 7, 2, 15, tex: t6("brewing_stand_base")), Box(7, 0, 7, 9, 14, 9, tex: t6("brewing_stand_rod"))]
            let spots = [Box(10, 2, 6, 14, 8, 10), Box(2, 2, 2, 6, 8, 6), Box(2, 2, 10, 6, 8, 14)]
            for i in 0..<3 where m & (1 << i) != 0 {
                var b = spots[i]; b.tex = t6("brewing_bottle"); boxes.append(b)
            }
            model(m == 0 ? "brewing_stand" : "brewing_stand[\(m)]", "Brewing Stand", ["brewing_stand_base"], boxes, h: 0.5, emit: 1,
                  group: "brewing_stand", hidden: m != 0)
        }
        var et = BlockDef("enchanting_table", "Enchanting Table")
        et.tex = ["enchanting_table_side", "enchanting_table_side", "enchanting_table_top", "enchanting_table_bottom", "enchanting_table_side", "enchanting_table_side"]
        et.render = .model; et.opaque = false; et.boxes = [Box(0, 0, 0, 16, 12, 16)]; et.hardness = 5; et.resistance = 1200
        et.tool = .pickaxe; et.requiresTool = true; et.emit = 7; et.skyStop = true
        add(et)
        var bc = BlockDef("beacon", "Beacon")
        bc.tex = ["beacon_glass"]; bc.render = .model; bc.layer = .cutout; bc.opaque = false; bc.emit = 15; bc.hardness = 3
        bc.boxes = [Box(0, 0, 0, 16, 16, 16), Box(2, 0, 2, 14, 3, 14, tex: t6("obsidian")), Box(3, 3, 3, 13, 13, 13, tex: t6("beacon_core"))]
        bc.skyStop = false; bc.sound = .glass
        add(bc)
        for (n, d) in [("chipped_anvil", "Chipped Anvil"), ("damaged_anvil", "Damaged Anvil")] {
            model(n, d, [n], [Box(2, 0, 2, 14, 4, 14), Box(4, 4, 3, 12, 5, 13), Box(6, 5, 4, 10, 10, 12), Box(3, 10, 0, 13, 16, 16)], h: 5, req: true)
        }
        // Mob heads: 4 floor facings (0-3) + 4 wall facings (4-7). Face texture on the facing side.
        let heads: [(String, String, String)] = [("skeleton_skull", "Skeleton Skull", "skull_skeleton"), ("wither_skeleton_skull", "Wither Skeleton Skull", "skull_wither"),
                                                 ("zombie_head", "Zombie Head", "head_zombie"), ("creeper_head", "Creeper Head", "head_creeper"),
                                                 ("piglin_head", "Piglin Head", "head_piglin"), ("dragon_head", "Dragon Head", "head_dragon"),
                                                 ("player_head", "Player Head", "head_player")]
        for (n, disp, t) in heads {
            for st in 0..<8 {
                let f = st % 4
                let faceIdx = [5, 4, 1, 0][f]            // facing north shows its face on -Z, south +Z, west -X, east +X
                var tex = [UInt16](repeating: Tex.id(t + "_side"), count: 6)
                tex[faceIdx] = Tex.id(t + "_face")
                tex[2] = Tex.id(t + "_top")
                let big = n == "dragon_head" || n == "piglin_head"
                let r = big ? 5 : 4
                var b: Box
                if st < 4 { b = Box(8 - r, 0, 8 - r, 8 + r, 2 * r, 8 + r) }
                else {
                    // On a wall: pushed against the side opposite the facing.
                    switch f {
                    case 0: b = Box(8 - r, 4, 16 - 2 * r, 8 + r, 4 + 2 * r, 16)
                    case 1: b = Box(8 - r, 4, 0, 8 + r, 4 + 2 * r, 2 * r)
                    case 2: b = Box(16 - 2 * r, 4, 8 - r, 16, 4 + 2 * r, 8 + r)
                    default: b = Box(0, 4, 8 - r, 2 * r, 4 + 2 * r, 8 + r)
                    }
                }
                b.tex = tex
                var d = BlockDef(st == 0 ? n : "\(n)[\(st)]", disp)
                d.tex = [t + "_side"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.boxes = [b]; d.hardness = 1
                d.sound = .stone; d.skyStop = false; d.group = n; d.hidden = st != 0; d.shape = "skull"
                add(d)
            }
        }
        var nb = BlockDef("netherite_block", "Block of Netherite")
        nb.tex = ["netherite_block"]; nb.hardness = 50; nb.resistance = 1200; nb.tool = .pickaxe; nb.harvestLevel = 3; nb.requiresTool = true
        add(nb)
        // Carved pumpkin / jack o'lantern (facing the player who placed them).
        for (n, disp, face, emit) in [("carved_pumpkin", "Carved Pumpkin", "carved_pumpkin_face", UInt8(0)), ("jack_o_lantern", "Jack o'Lantern", "jack_o_lantern_face", UInt8(15))] {
            var d = BlockDef(n, disp)
            d.tex = ["pumpkin_side", "pumpkin_side", "pumpkin_top", "pumpkin_top", "pumpkin_side", "pumpkin_side"]
            d.hardness = 1; d.tool = .axe; d.sound = .wood; d.emit = emit
            addFacing(d, front: face)
        }
        // Cauldrons holding water (levels 1-3) and lava.
        let walls = [Box(0, 3, 0, 16, 5, 16), Box(0, 5, 0, 2, 16, 16), Box(14, 5, 0, 16, 16, 16), Box(2, 5, 0, 14, 16, 2),
                     Box(2, 5, 14, 14, 16, 16), Box(0, 0, 0, 4, 3, 2), Box(0, 0, 0, 2, 3, 4), Box(12, 0, 0, 16, 3, 2), Box(14, 0, 0, 16, 3, 4),
                     Box(0, 0, 14, 4, 3, 16), Box(0, 0, 12, 2, 3, 16), Box(12, 0, 14, 16, 3, 16), Box(14, 0, 12, 16, 3, 16)]
        for lvl in 1...3 {
            let top = [9, 12, 15][lvl - 1]
            model(lvl == 1 ? "water_cauldron" : "water_cauldron[\(lvl)]", "Water Cauldron", ["cauldron"],
                  walls + [Box(2, 5, 2, 14, top, 14, tex: t6("cauldron_water"))], h: 2, req: true, group: "water_cauldron", hidden: true)
        }
        model("lava_cauldron", "Lava Cauldron", ["cauldron"], walls + [Box(2, 5, 2, 14, 15, 14, tex: t6("lava"))], h: 2, emit: 15, req: true, hidden: true)
        model("powder_snow_cauldron", "Powder Snow Cauldron", ["cauldron"], walls + [Box(2, 5, 2, 14, 15, 14, tex: t6("snow"))], h: 2, req: true, hidden: true)
    }
}

extension TextureGen {
    static func magicPainters(_ p: inout [String: Painter]) {
        p["brewing_stand_base"] = { x, y in hex(0x6A6A6A, 0.85 + 0.25 * r(x, y, 800)) }
        p["brewing_stand_rod"] = { x, y in hex(0xF7C23A, 0.85 + 0.25 * r(x, y, 801)) }
        p["brewing_bottle"] = { x, y in V4(0.75, 0.8, 0.95, 0.8) }
        p["enchanting_table_top"] = { x, y in
            // Red cloth with a gold border and a dark diamond pattern.
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x2A1A40) }
            let dx = abs(x * 2 - 15), dy = abs(y * 2 - 15)
            if dx + dy < 10 && (dx + dy) % 4 < 2 { return hex(0x1A1A28) }
            return hex(0xB02A28, 0.85 + 0.2 * r(x, y, 802))
        }
        p["enchanting_table_side"] = { x, y in
            if y < 4 { return hex(0xB02A28, 0.85 + 0.2 * r(x, y, 803)) }
            if y == 4 { return hex(0x6A1A18) }
            // Obsidian with gold diamond studs.
            if (x + y) % 6 == 0 && y > 6 && y < 14 { return hex(0x4AEDD9) }
            return hex(0x1A1228, 0.8 + 0.3 * r(x, y, 804))
        }
        p["enchanting_table_bottom"] = { x, y in hex(0x1A1228, 0.8 + 0.3 * r(x, y, 805)) }
        p["beacon_glass"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return V4(0.75, 0.95, 0.95, 0.9) }
            return V4(0.8, 0.95, 1, 0.18)
        }
        p["beacon_core"] = { x, y in
            let dx = abs(Float(x) - 7.5), dy = abs(Float(y) - 7.5)
            let k = max(0, 1 - (dx * dx + dy * dy) / 60)
            return V4(0.6 + 0.4 * k, 0.95, 0.9 + 0.1 * k, 1)
        }
        for (n, cracks) in [("chipped_anvil", 3), ("damaged_anvil", 7)] {
            p[n] = { x, y in
                let crack = (0..<cracks).contains { c in
                    let cx = Int(r(c, 1, 806) * 14) + 1, cy = Int(r(c, 2, 807) * 14) + 1
                    return abs(x - cx) + abs(y - cy) < 2 && (x + y + c) % 2 == 0
                }
                return crack ? hex(0x1A1A1A) : hex(0x3E3E42, 0.85 + 0.2 * r(x, y, 633))
            }
        }
        // Heads: pixel faces (original art).
        func headTex(_ base: UInt32, _ face: [String], _ colors: [Character: UInt32], salt: Int) -> (Painter, Painter) {
            let rows = face.map { Array($0) }
            let side: Painter = { x, y in hex(base, 0.85 + 0.2 * r(x / 2, y / 2, salt)) }
            let front: Painter = { x, y in
                let fx = x / 2, fy = y / 2
                if fy < rows.count, fx < rows[fy].count, let c = colors[rows[fy][fx]] { return hex(c) }
                return side(x, y)
            }
            return (side, front)
        }
        let faces: [(String, UInt32, [String], [Character: UInt32])] = [
            ("skull_skeleton", 0xC8C8C4, ["........", "........", ".##..##.", ".##..##.", "........", "...##...", ".#.##.#.", "........"], ["#": 0x2A2A2A]),
            ("skull_wither", 0x2E2E30, ["........", "........", ".##..##.", ".##..##.", "........", "...##...", ".#.##.#.", "........"], ["#": 0x0A0A0A]),
            ("head_zombie", 0x5A8A4A, ["........", "........", ".##..##.", ".#o..o#.", "........", "..####..", "..#..#..", "........"], ["#": 0x2A4A2A, "o": 0x1A1A1A]),
            ("head_creeper", 0x5AB84A, ["........", "........", ".##..##.", ".##..##.", "...##...", "..####..", "..####..", "..#..#.."], ["#": 0x0A1A0A]),
            ("head_piglin", 0xE8A090, ["........", "........", ".##..##.", ".w....w.", "..pppp..", "..p##p..", "..pppp..", "........"], ["#": 0x5A2A2A, "w": 0xF8F8F8, "p": 0xF0B8A8]),
            ("head_dragon", 0x1A1A1E, ["........", ".m....m.", "........", ".pp..pp.", "........", "########", "#......#", "########"], ["#": 0x2A2A30, "m": 0xB050E0, "p": 0xE070F8]),
            ("head_player", 0xB8805A, ["########", "#......#", "........", ".ww..ww.", ".wb..bw.", "...ee...", "..mmmm..", "........"], ["#": 0x4A3020, "w": 0xF8F8F8, "b": 0x3A4AA8, "e": 0x9A6040, "m": 0x6A3A2A]),
        ]
        for (i, f) in faces.enumerated() {
            let (side, front) = headTex(f.1, f.2, f.3, salt: 810 + i)
            p[f.0 + "_side"] = side
            p[f.0 + "_top"] = f.0 == "head_player" ? { x, y in hex(0x4A3020, 0.85 + 0.2 * r(x / 2, y / 2, 820)) } : side
            p[f.0 + "_face"] = front
        }
        p["netherite_block"] = { x, y in
            let edge = x == 0 || y == 0 || x == 15 || y == 15
            return hex(edge ? 0x2E2A2E : 0x4D494D, 0.85 + 0.25 * r(x / 2, y / 2, 840))
        }
        func carved(_ lit: Bool) -> Painter {
            { x, y in
                let eye = (y >= 4 && y <= 6) && ((x >= 3 && x <= 5) || (x >= 10 && x <= 12)) && (y - 4 <= min(abs(x - 4), abs(x - 11)) + 1)
                let mouth = (y >= 9 && y <= 11) && x >= 3 && x <= 12 && !((y == 9) && (x == 6 || x == 9)) && !(y == 11 && (x == 3 || x == 12))
                if eye || mouth { return lit ? hex(0xF8D040, 0.9 + 0.1 * r(x, y, 830)) : hex(0x3A2408) }
                return hex(x % 4 == 0 ? 0xB86A0E : 0xE38A1D, 0.9 + 0.15 * r(x, y, 467))
            }
        }
        p["carved_pumpkin_face"] = carved(false)
        p["jack_o_lantern_face"] = carved(true)
        p["cauldron_water"] = { x, y in hex(0x3F76E4, 0.9 + 0.15 * r(x / 2, y, 808)) }
        Potions.painters(&p)
        effectPainters(&p)
    }

    // Effect icons: a coloured orb with a small glyph (arrow, heart, shield, eye...) per effect.
    static func effectPainters(_ p: inout [String: Painter]) {
        let glyphs: [Effect: [String]] = [
            .speed: ["..#..", "...#.", "#####", "...#.", "..#.."], .slowness: ["..#..", ".#...", "#####", ".#...", "..#.."],
            .haste: ["###..", "#.#..", "###..", "..#..", "..#.."], .miningFatigue: ["..#..", "..#..", "###..", "#.#..", "###.."],
            .strength: ["#...#", "##.##", ".###.", "..#..", "..#.."], .instantHealth: [".#.#.", "#####", "#####", ".###.", "..#.."],
            .instantDamage: [".#.#.", "#.#.#", "#...#", ".#.#.", "..#.."], .jumpBoost: ["..#..", ".###.", "#.#.#", "..#..", "..#.."],
            .nausea: ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"], .regeneration: [".#.#.", "#####", "#.#.#", ".###.", "..#.."],
            .resistance: ["#####", "#...#", "#...#", ".#.#.", "..#.."], .fireResistance: ["..#..", ".##..", ".###.", "#####", ".###."],
            .waterBreathing: [".#...", "#.#..", ".#.#.", "...#.", "..#.#"], .invisibility: [".###.", "#...#", "#.#.#", "#...#", ".###."],
            .blindness: [".###.", "#####", "#####", "#####", ".###."], .nightVision: [".###.", "#...#", "#.#.#", "#...#", ".###."],
            .hunger: ["#.#.#", "#.#.#", "#####", "..#..", "..#.."], .weakness: ["..#..", "..#..", "..#..", ".....", "..#.."],
            .poison: [".###.", "#.#.#", "#####", ".#.#.", ".#.#."], .wither: [".###.", "#.#.#", "#####", ".###.", "#.#.#"],
            .healthBoost: ["..#..", "..#..", "#####", "..#..", "..#.."], .absorption: [".#.#.", "#####", "#####", ".###.", "..#.."],
            .saturation: [".###.", "#####", "#####", "#####", ".###."], .glowing: ["#.#.#", ".###.", "##.##", ".###.", "#.#.#"],
            .levitation: ["..#..", ".###.", "#####", "..#..", "..#.."], .luck: ["#.#..", "###..", ".####", "..###", "..#.#"],
            .badLuck: ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"], .slowFalling: [".###.", "#####", "..#..", "..#..", "..#.."],
            .conduitPower: [".###.", "#...#", "#.#.#", "#...#", ".###."], .dolphinsGrace: ["...#.", "..##.", "####.", ".####", "#...#"],
            .badOmen: ["#####", "#.#.#", "#####", ".#.#.", "#####"], .heroOfTheVillage: ["..#..", ".###.", "#####", "#.#.#", "#...#"],
            .darkness: ["#####", "##.##", "#...#", "##.##", "#####"], .trialOmen: ["#####", "#...#", "#.#.#", "#...#", "#####"],
            .raidOmen: ["#####", "#.#.#", "##.##", "#.#.#", "#####"], .windCharged: ["####.", "....#", ".###.", "#....", ".####"],
            .weaving: ["#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#"], .oozing: [".###.", "#####", "#.#.#", "#####", ".###."],
            .infested: ["#...#", ".###.", "#####", ".###.", "#...#"],
        ]
        for e in Effect.allCases {
            let c = hex(e.color)
            let g = (glyphs[e] ?? ["#####", "#...#", "#...#", "#...#", "#####"]).map { Array($0) }
            p["effect_" + e.key] = { x, y in
                let dx = Float(x) - 7.5, dy = Float(y) - 7.5
                let d = (dx * dx + dy * dy).squareRoot()
                if d > 7.8 { return clear }
                if d > 6.6 { return V4(c.x * 0.35, c.y * 0.35, c.z * 0.35, 1) }
                // 5x5 glyph scaled x2 in the centre.
                let gx = (x - 3) / 2, gy = (y - 3) / 2
                if x >= 3 && y >= 3 && gx < 5 && gy < 5 && g[gy][gx] == "#" { return V4(1, 1, 1, 1) }
                let k = 0.75 + 0.25 * (1 - d / 7)
                return V4(c.x * k, c.y * k, c.z * k, 1)
            }
        }
    }
}
