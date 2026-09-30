import Foundation

// Axis-oriented pillars (logs, wood, stems, basalt, violite, hay, bone...: base = Y axis, "[x]", "[z]"),
// the full wood set for every tree (bark "wood", stripped logs and wood, hyphae, bamboo blocks)
// and axe stripping.
enum Woods {
    // name, bark/log texture, plank colour (stripped wood colour), log word, wood word
    static let all: [(String, UInt32, String, String)] = [
        ("oak", 0xB08C58, "log", "wood"), ("spruce", 0x7A5A35, "log", "wood"), ("birch", 0xD2C28A, "log", "wood"),
        ("jungle", 0xAA7C58, "log", "wood"), ("acacia", 0xB8663A, "log", "wood"), ("dark_oak", 0x5A3A1E, "log", "wood"),
        ("mangrove", 0x803A34, "log", "wood"), ("cherry", 0xE6BAB2, "log", "wood"),
        ("crimson", 0x8A3A5E, "stem", "hyphae"), ("warped", 0x3A7A72, "stem", "hyphae"),
    ]
    static func logKey(_ w: String, _ word: String) -> String { "\(w)_\(word)" }
}

extension BlockRegistry {
    // Three states: vertical, along X, along Z (side texture rotated for the horizontal ones).
    func pillar(_ n: String, _ disp: String, side: String, top: String, bottom: String? = nil, h: Float = 2, tool: ToolType = .axe,
                snd: SoundMat = .wood, req: Bool = false) {
        let b = bottom ?? top
        let r = side + "@r"
        for (i, sfx) in ["", "[x]", "[z]"].enumerated() {
            var d = BlockDef(n + sfx, disp)
            d.group = n; d.hidden = i != 0
            switch i {
            case 1: d.tex = [top, b, r, r, r, r]
            case 2: d.tex = [r, r, side, side, top, b]
            default: d.tex = [side, side, top, b, side, side]
            }
            d.hardness = h; d.tool = tool; d.sound = snd; d.requiresTool = req
            add(d)
        }
    }

    func registerWoodExtras() {
        for (w, _, logW, woodW) in Woods.all {
            let disp = BlockRegistry.woodName(w)
            let lw = logW.capitalized, ww = woodW.capitalized
            if !has("\(w)_\(woodW)") { pillar("\(w)_\(woodW)", "\(disp) \(ww)", side: "\(w)_\(logW)", top: "\(w)_\(logW)") }
            pillar("stripped_\(w)_\(logW)", "Stripped \(disp) \(lw)", side: "stripped_\(w)_log", top: "stripped_\(w)_log_top")
            pillar("stripped_\(w)_\(woodW)", "Stripped \(disp) \(ww)", side: "stripped_\(w)_log", top: "stripped_\(w)_log")
        }
        pillar("bamboo_block", "Block of Bamboo", side: "bamboo_block", top: "bamboo_block_top")
        pillar("stripped_bamboo_block", "Block of Stripped Bamboo", side: "stripped_bamboo_block", top: "stripped_bamboo_block_top")
        pillar("quartz_pillar", "Quartz Pillar", side: "quartz_pillar", top: "quartz_pillar_top", h: 0.8, tool: .pickaxe, snd: .stone, req: true)
    }
}

extension TextureGen {
    static func woodPainters(_ p: inout [String: Painter]) {
        for (i, (w, c, _, _)) in Woods.all.enumerated() {
            p["stripped_\(w)_log"] = { x, y in hex(c, (x + Int(r(0, y / 6, 1300 + i) * 3)) % 5 == 0 ? 0.88 : 0.95 + 0.08 * r(x, y, 1310 + i)) }
            p["stripped_\(w)_log_top"] = rings(c, c)
        }
        p["bamboo_block"] = { x, y in hex(0x7A9A2A, x % 4 == 0 ? 0.8 : (y % 8 == 0 ? 0.85 : 0.95 + 0.08 * r(x, y, 1330))) }
        p["bamboo_block_top"] = { x, y in (x % 4 == 1 || x % 4 == 2) && (y % 4 == 1 || y % 4 == 2) ? hex(0xD8C88A) : hex(0x7A9A2A, 0.9) }
        p["stripped_bamboo_block"] = { x, y in hex(0xD8C06A, x % 4 == 0 ? 0.85 : 0.95 + 0.06 * r(x, y, 1331)) }
        p["stripped_bamboo_block_top"] = { x, y in (x % 4 == 1 || x % 4 == 2) && (y % 4 == 1 || y % 4 == 2) ? hex(0xF0E0A0) : hex(0xD8C06A, 0.9) }
        if p["quartz_pillar"] == nil { p["quartz_pillar"] = { x, y in hex(0xEAE4DA, x == 1 || x == 14 ? 0.85 : 0.97 + 0.03 * r(x, y, 1332)) } }
        if p["quartz_pillar_top"] == nil { p["quartz_pillar_top"] = { x, y in hex(0xEAE4DA, x == 0 || y == 0 || x == 15 || y == 15 ? 0.85 : 0.98) } }
    }

    // Rotated variants ("name@r") of any texture, derived from the base painter.
    static func rotatedPainters(_ p: inout [String: Painter]) {
        for n in Tex.names where n.hasSuffix("@r") && p[n] == nil {
            if let f = p[String(n.dropLast(2))] { p[n] = { x, y in f(y, 15 - x) } }
        }
    }
}

extension Game {
    // Axe on a log / wood / stem / hyphae / bamboo block: strip it (keeping the axis).
    func stripLog(_ t: (hit: IVec3, normal: IVec3)) -> Bool {
        guard held.def.tool == .axe else { return false }
        let b = world.block(t.hit.x, t.hit.y, t.hit.z)
        let base = Blocks.groupBase[Int(b)]
        let k = Blocks.key(base)
        guard !k.hasPrefix("stripped_"), Blocks.has("stripped_" + k) else { return false }
        world.setBlock(t.hit.x, t.hit.y, t.hit.z, Blocks.id("stripped_" + k) + (b - base))
        sfx(.place(.wood), 0.9, at: V3(Float(t.hit.x) + 0.5, Float(t.hit.y) + 0.5, Float(t.hit.z) + 0.5))
        damageHeld(1)
        swing = 1
        return true
    }
}
