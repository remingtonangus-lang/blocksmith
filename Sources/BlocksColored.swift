import Foundation

// The sixteen-colour families: terracotta, concrete, concrete powder, stained glass (+ panes),
// glazed terracotta (4 facings), candles (1-4, lit), shellsentry boxes.
extension BlockRegistry {
    // Reference terracotta colours (muted versions of the dyes).
    static let terracottaHex: [String: UInt32] = [
        "white": 0xD1B2A1, "orange": 0xA15325, "magenta": 0x95576C, "light_blue": 0x706C8A, "yellow": 0xBA8523, "lime": 0x677535,
        "pink": 0xA14E4E, "gray": 0x392A23, "light_gray": 0x876B62, "cyan": 0x575B5B, "purple": 0x764656, "blue": 0x4A3B5B,
        "brown": 0x4D3323, "green": 0x4C532A, "red": 0x8F3D2E, "black": 0x251610,
    ]

    func registerColoredBlocks() {
        for (c, d) in BlockRegistry.colors {
            if !has("\(c)_terracotta") {
                var t = BlockDef("\(c)_terracotta", "\(d) Terracotta")
                t.tex = ["\(c)_terracotta"]; t.hardness = 1.25; t.tool = .pickaxe; t.requiresTool = true
                add(t)
            }
            if !has("\(c)_concrete") {
                var k = BlockDef("\(c)_concrete", "\(d) Concrete")
                k.tex = ["\(c)_concrete"]; k.hardness = 1.8; k.tool = .pickaxe; k.requiresTool = true
                add(k)
            }
            var pw = BlockDef("\(c)_concrete_powder", "\(d) Concrete Powder")
            pw.tex = ["\(c)_concrete_powder"]; pw.hardness = 0.5; pw.tool = .shovel; pw.sound = .sand
            add(pw)
            var g = BlockDef("\(c)_stained_glass", "\(d) Stained Glass")
            g.tex = ["\(c)_stained_glass"]; g.hardness = 0.3; g.sound = .glass; g.opaque = false; g.layer = .translucent; g.cullSame = true
            g.skyStop = false
            add(g)
            var pane = BlockDef("\(c)_stained_glass_pane", "\(d) Stained Glass Pane")
            pane.tex = ["\(c)_stained_glass"]; pane.render = .connect; pane.connect = 2; pane.layer = .translucent; pane.opaque = false
            pane.hardness = 0.3; pane.sound = .glass; pane.skyStop = false
            add(pane)
            var gl = BlockDef("\(c)_glazed_terracotta", "\(d) Glazed Terracotta")
            gl.tex = ["\(c)_glazed_terracotta"]; gl.hardness = 1.4; gl.tool = .pickaxe; gl.requiresTool = true
            addFacing(gl, front: "\(c)_glazed_terracotta")
            // Candles: count 1-4, lit or not (8 states).
            for st in 0..<8 {
                let n = st % 4 + 1, lit = st >= 4
                var cd = BlockDef(st == 0 ? "\(c)_candle" : "\(c)_candle[\(st)]", "\(d) Candle")
                cd.group = "\(c)_candle"; cd.hidden = st != 0
                cd.tex = ["\(c)_candle"]; cd.render = .model; cd.layer = .cutout; cd.opaque = false; cd.hardness = 0.1; cd.sound = .plant
                cd.emit = lit ? UInt8(3 * n) : 0; cd.skyStop = false; cd.collide = false; cd.shape = "candle"
                let spots = [[(7, 7)], [(5, 7), (9, 7)], [(5, 6), (9, 6), (7, 9)], [(5, 5), (9, 5), (5, 9), (9, 9)]][n - 1]
                cd.boxes = spots.map { Box($0.0, 0, $0.1, $0.0 + 2, 6, $0.1 + 2) }
                add(cd)
            }
            var sb = BlockDef("\(c)_shulker_box", "\(d) Shell Box")
            sb.tex = ["\(c)_shulker_box_side", "\(c)_shulker_box_side", "\(c)_shulker_box_top", "\(c)_shulker_box_top", "\(c)_shulker_box_side", "\(c)_shulker_box_side"]
            sb.hardness = 2; sb.tool = .pickaxe
            add(sb)
        }
        var sb = BlockDef("shulker_box", "Shell Box")
        sb.tex = ["shulker_box_side", "shulker_box_side", "shulker_box_top", "shulker_box_top", "shulker_box_side", "shulker_box_side"]
        sb.hardness = 2; sb.tool = .pickaxe
        add(sb)
        for st in 0..<8 {
            let n = st % 4 + 1, lit = st >= 4
            var cd = BlockDef(st == 0 ? "candle" : "candle[\(st)]", "Candle")
            cd.group = "candle"; cd.hidden = st != 0
            cd.tex = ["candle"]; cd.render = .model; cd.layer = .cutout; cd.opaque = false; cd.hardness = 0.1; cd.sound = .plant
            cd.emit = lit ? UInt8(3 * n) : 0; cd.skyStop = false; cd.collide = false; cd.shape = "candle"
            let spots = [[(7, 7)], [(5, 7), (9, 7)], [(5, 6), (9, 6), (7, 9)], [(5, 5), (9, 5), (5, 9), (9, 9)]][n - 1]
            cd.boxes = spots.map { Box($0.0, 0, $0.1, $0.0 + 2, 6, $0.1 + 2) }
            add(cd)
        }
        // Ender chest: 4 facings, shared inventory; trapped chest.
        var ec = BlockDef("ender_chest", "Void Chest")
        ec.tex = ["ender_chest_side", "ender_chest_side", "ender_chest_top", "ender_chest_top", "ender_chest_side", "ender_chest_side"]
        ec.render = .model; ec.opaque = false; ec.boxes = [Box(1, 0, 1, 15, 14, 15)]; ec.hardness = 22.5; ec.resistance = 600
        ec.tool = .pickaxe; ec.requiresTool = true; ec.emit = 7; ec.skyStop = true
        addFacing(ec, front: "ender_chest_front", boxes: [Box(1, 0, 1, 15, 14, 15)])
        var tc = BlockDef("trapped_chest", "Trapped Chest")
        tc.tex = ["chest_side", "chest_side", "chest_top", "chest_top", "chest_side", "chest_side"]
        tc.render = .model; tc.opaque = false; tc.hardness = 2.5; tc.tool = .axe; tc.sound = .wood; tc.skyStop = true
        addFacing(tc, front: "trapped_chest_front", boxes: [Box(1, 0, 1, 15, 14, 15)])
        // Cake: 7 bite states.
        for bite in 0..<7 {
            var ck = BlockDef(bite == 0 ? "cake" : "cake[\(bite)]", "Cake")
            ck.group = "cake"; ck.hidden = bite != 0
            ck.tex = ["cake_side", "cake_side", "cake_top", "cake_bottom", "cake_side", "cake_side"]
            if bite > 0 { ck.tex[1] = "cake_inner" }
            ck.render = .model; ck.opaque = false; ck.boxes = [Box(1 + 2 * bite, 0, 1, 15, 8, 15)]; ck.hardness = 0.5; ck.sound = .plant
            ck.skyStop = false
            add(ck)
        }
    }
}

extension TextureGen {
    static func coloredPainters(_ p: inout [String: Painter]) {
        for (c, _) in BlockRegistry.colors {
            let dye = BlockRegistry.colorHex[c] ?? 0xFFFFFF
            let tc = BlockRegistry.terracottaHex[c] ?? 0x985E43
            // Terracotta: fired clay, soft mottling with faint horizontal strata and fine grain.
            if p["\(c)_terracotta"] == nil { p["\(c)_terracotta"] = { x, y in
                let strata: Float = (y + Int(r(x / 5, 0, 911) * 2)) % 5 == 0 ? -0.04 : 0
                let k: Float = 0.96 + (blot(x, y, 910, 4) - 0.5) * 0.1 + (r(x, y, 900) - 0.5) * 0.05 + strata
                return hex(tc, k)
            } }
            // Concrete: smooth with faint trowel blotches; powder: grainy with light and dark specks.
            p["\(c)_concrete"] = { x, y in hex(dye, 0.96 + (blot(x, y, 908, 8) - 0.5) * 0.06 + (r(x, y, 901) - 0.5) * 0.03) }
            p["\(c)_concrete_powder"] = { x, y in
                let n = r(x, y, 902)
                let k: Float = n < 0.12 ? 0.82 : (n > 0.9 ? 1.12 : 0.95 + (blot(x, y, 909, 4) - 0.5) * 0.1)
                return hex(dye, k)
            }
            p["\(c)_stained_glass"] = { x, y in
                let edge = x == 0 || y == 0 || x == 15 || y == 15
                let k = hex(dye)
                return V4(k.x, k.y, k.z, edge ? 0.85 : 0.45)
            }
            // Glazed terracotta: a four-fold swirl in the dye colour and a lighter tint.
            p["\(c)_glazed_terracotta"] = { x, y in
                let fx = x < 8 ? x : 15 - x, fy = y < 8 ? y : 15 - y
                let q = (x < 8) == (y < 8)
                let a = q ? fx : fy, b = q ? fy : fx
                let ring = (a + b) % 5 == 0 || (a == b && a > 2)
                let dot = abs(a - 3) + abs(b - 5) < 2
                if ring { return hex(dye, 0.7) }
                if dot { return hex(0xF0E8D8) }
                return hex(dye, 1.05 + 0.1 * r(x, y, 903))
            }
            p["\(c)_candle"] = { x, y in
                if y < 2 && (x == 7 || x == 8) { return hex(0x2A2A2A) }
                return hex(dye, 0.9 + 0.1 * r(x, y, 904))
            }
            p["\(c)_shulker_box_side"] = { x, y in
                if y == 7 || y == 8 { return hex(dye, 0.6) }
                return hex(dye, 0.85 + 0.15 * r(x / 2, y / 2, 905))
            }
            p["\(c)_shulker_box_top"] = { x, y in
                let e = x == 0 || y == 0 || x == 15 || y == 15
                return hex(dye, e ? 0.6 : 0.9 + 0.1 * r(x, y, 906))
            }
        }
        p["shulker_box_side"] = { x, y in (y == 7 || y == 8) ? hex(0x6A4A6A) : hex(0x9A6A9A, 0.85 + 0.15 * r(x / 2, y / 2, 907)) }
        p["shulker_box_top"] = { x, y in hex(0x9A6A9A, (x == 0 || y == 0 || x == 15 || y == 15) ? 0.6 : 0.95) }
        p["candle"] = { x, y in (y < 2 && (x == 7 || x == 8)) ? hex(0x2A2A2A) : hex(0xE8D8B0, 0.9 + 0.1 * r(x, y, 908)) }
        p["ender_chest_side"] = { x, y in
            if y == 6 || y == 7 { return hex(0x1A3A3A) }
            return hex(0x1A2228, 0.8 + 0.3 * r(x, y, 909))
        }
        p["ender_chest_top"] = { x, y in hex(0x1A2228, 0.8 + 0.3 * r(x, y, 910)) }
        p["ender_chest_front"] = { x, y in
            if (x == 7 || x == 8) && y >= 5 && y <= 9 { return hex(0x3AE8C8) }
            if y == 6 || y == 7 { return hex(0x1A3A3A) }
            return hex(0x1A2228, 0.8 + 0.3 * r(x, y, 911))
        }
        let chestFront = p["chest_front"] ?? p["chest_side"]
        p["trapped_chest_front"] = { x, y in
            if y >= 5 && y <= 7 && x >= 6 && x <= 9 { return hex(0xB02020) }
            return chestFront?(x, y) ?? hex(0x9A6A30)
        }
        p["cake_top"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0xF0E8E0) }
            return r(x, y, 912) < 0.08 ? hex(0xD02020) : hex(0xF8F4F0, 0.95 + 0.05 * r(x, y, 913))
        }
        p["cake_side"] = { x, y in y < 8 ? clear : (y < 10 ? hex(0xF8F4F0) : hex(0xB07040, 0.9 + 0.1 * r(x, y, 914))) }
        p["cake_inner"] = { x, y in y < 8 ? clear : (y < 10 ? hex(0xF8F4F0) : hex(0xC89060, 0.9 + 0.1 * r(x, y, 915))) }
        p["cake_bottom"] = { x, y in hex(0xB07040) }
    }
}
