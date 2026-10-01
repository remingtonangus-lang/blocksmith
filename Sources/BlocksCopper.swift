import Foundation

// Copper: four oxidation stages (unaffected, exposed, weathered, oxidized) × waxed / unwaxed for the
// block, cut copper (+ stairs, slabs), chiseled copper, grates and bulbs. Unwaxed copper ages on random
// ticks; an axe scrapes a stage (or the wax) off; honeycomb waxes it.
enum Copper {
    static let stages: [(prefix: String, disp: String, hex: UInt32)] = [
        ("", "", 0xC06B4F), ("exposed_", "Exposed ", 0xA17E68), ("weathered_", "Weathered ", 0x6C9A6C), ("oxidized_", "Oxidized ", 0x52A284),
    ]
    static let forms = ["block", "cut_copper", "chiseled_copper", "copper_grate", "copper_bulb", "cut_copper_stairs", "cut_copper_slab"]

    static func name(_ form: String, stage: Int, waxed: Bool) -> String {
        let w = waxed ? "waxed_" : ""
        let p = stages[stage].prefix
        if form == "block" { return stage == 0 ? (waxed ? "waxed_copper_block" : "copper_block") : "\(w)\(p)copper" }
        return "\(w)\(p)\(form)"
    }

    // (form, stage, waxed) for a block group key, or nil.
    static let index: [String: (String, Int, Bool)] = {
        var m: [String: (String, Int, Bool)] = [:]
        for waxed in [false, true] { for s in 0..<4 { for f in forms { m[name(f, stage: s, waxed: waxed)] = (f, s, waxed) } } }
        return m
    }()

    // Same form and state offset at another stage / wax setting.
    static func convert(_ b: BlockID, stage: Int, waxed: Bool) -> BlockID? {
        let base = Blocks.groupBase[Int(b)]
        guard case let (f, _, _)? = index[Blocks.key(base)] else { return nil }
        let n = name(f, stage: stage, waxed: waxed)
        guard Blocks.has(n) else { return nil }
        return Blocks.id(n) + (b - base)
    }
}

extension BlockRegistry {
    func registerCopperBlocks() {
        for waxed in [false, true] {
            for (s, st) in Copper.stages.enumerated() {
                let w = waxed ? "Waxed " : ""
                let tex = s == 0 ? "copper_block" : "\(st.prefix)copper"
                let blockName = Copper.name("block", stage: s, waxed: waxed)
                if !has(blockName) {
                    var d = BlockDef(blockName, s == 0 ? "\(w)Block of Copper" : "\(w)\(st.disp)Copper")
                    d.tex = [tex]; d.hardness = 3; d.tool = .pickaxe; d.harvestLevel = 1; d.requiresTool = true; d.randomTicks = !waxed && s < 3
                    add(d)
                }
                let cutTex = "\(st.prefix)cut_copper"
                var cut = BlockDef(Copper.name("cut_copper", stage: s, waxed: waxed), "\(w)\(st.disp)Cut Copper")
                cut.tex = [cutTex]; cut.hardness = 3; cut.tool = .pickaxe; cut.harvestLevel = 1; cut.requiresTool = true; cut.randomTicks = !waxed && s < 3
                add(cut)
                family(cutTex, Copper.name("cut_copper", stage: s, waxed: waxed), "\(w)\(st.disp)Cut Copper", h: 3, tool: .pickaxe, req: true, snd: .stone,
                       stairs: true, slab: true, fence: false, wall: false)
                var ch = BlockDef(Copper.name("chiseled_copper", stage: s, waxed: waxed), "\(w)\(st.disp)Chiseled Copper")
                ch.tex = ["\(st.prefix)chiseled_copper"]; ch.hardness = 3; ch.tool = .pickaxe; ch.requiresTool = true; ch.randomTicks = !waxed && s < 3
                add(ch)
                var gr = BlockDef(Copper.name("copper_grate", stage: s, waxed: waxed), "\(w)\(st.disp)Copper Grate")
                gr.tex = ["\(st.prefix)copper_grate"]; gr.hardness = 3; gr.tool = .pickaxe; gr.requiresTool = true; gr.opaque = false
                gr.layer = .cutout; gr.skyStop = false; gr.randomTicks = !waxed && s < 3
                add(gr)
                // Bulb: off / lit (light 15, 12, 8, 4 by stage).
                for lit in [false, true] {
                    let n = Copper.name("copper_bulb", stage: s, waxed: waxed)
                    var b = BlockDef(lit ? "\(n)[lit]" : n, "\(w)\(st.disp)Copper Bulb")
                    b.group = n; b.hidden = lit
                    b.tex = [lit ? "\(st.prefix)copper_bulb_lit" : "\(st.prefix)copper_bulb"]; b.hardness = 3; b.tool = .pickaxe; b.requiresTool = true
                    b.emit = lit ? UInt8([15, 12, 8, 4][s]) : 0; b.randomTicks = !waxed && s < 3
                    add(b)
                }
            }
        }
    }
}

extension TextureGen {
    static func copperPainters(_ p: inout [String: Painter]) {
        for (s, st) in Copper.stages.enumerated() {
            let c = st.hex
            let blockTex = s == 0 ? "copper_block" : "\(st.prefix)copper"
            // Keep an existing copper_block painter; the others are drawn here.
            if p[blockTex] == nil || s > 0 {
                p[blockTex] = { x, y in
                    let spot = r(x / 3, y / 3, 920 + s) < 0.25 * Float(s) / 3
                    return hex(spot ? 0x3E8E74 : c, 0.88 + 0.18 * r(x, y, 921))
                }
            }
            p["\(st.prefix)cut_copper"] = { x, y in
                if x % 8 == 0 || y % 8 == 0 { return hex(c, 0.7) }
                return hex(c, 0.9 + 0.15 * r(x, y, 922))
            }
            p["\(st.prefix)chiseled_copper"] = { x, y in
                let e = x == 0 || y == 0 || x == 15 || y == 15
                let inner = (x == 4 || x == 11 || y == 4 || y == 11) && x >= 4 && x <= 11 && y >= 4 && y <= 11
                return hex(c, e || inner ? 0.7 : 0.95 + 0.08 * r(x, y, 923))
            }
            p["\(st.prefix)copper_grate"] = { x, y in
                if (x % 4 == 1 || x % 4 == 2) && (y % 4 == 1 || y % 4 == 2) { return clear }
                return hex(c, 0.85 + 0.15 * r(x, y, 924))
            }
            for lit in [false, true] {
                p["\(st.prefix)copper_bulb\(lit ? "_lit" : "")"] = { x, y in
                    let e = x < 2 || y < 2 || x > 13 || y > 13
                    if e { return hex(c, 0.8) }
                    let dx = Float(x) - 7.5, dy = Float(y) - 7.5
                    if dx * dx + dy * dy < 12 { return lit ? hex(0xF8E0A0) : hex(0x6A5A40) }
                    return hex(c, 0.6)
                }
            }
        }
    }
}

extension Game {
    // Axe scraping / honeycomb waxing (right-click). Returns true when it changed the block.
    func copperInteract(_ p: IVec3, key: String) -> Bool {
        let b = world.block(p.x, p.y, p.z)
        guard case let (_, stage, waxed)? = Copper.index[Blocks.key(Blocks.groupBase[Int(b)])] else { return false }
        var target: BlockID?
        if key == "honeycomb" && !waxed { target = Copper.convert(b, stage: stage, waxed: true); if target != nil { consumeHeld(); achieve("wax") } }
        else if key.hasSuffix("_axe") {
            if waxed { target = Copper.convert(b, stage: stage, waxed: false) }
            else if stage > 0 { target = Copper.convert(b, stage: stage - 1, waxed: false) }
            if target != nil { damageHeld(1) }
        }
        guard let t = target else { return false }
        world.setBlock(p.x, p.y, p.z, t)
        sfx(key == "honeycomb" ? .waxOn : (waxed ? .waxOff : .scrape), 0.8, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
        swing = 1
        return true
    }

    // Random-tick oxidation (roughly one stage per hour of loaded time, like the reference average).
    func copperAge(_ p: IVec3, _ b: BlockID) {
        guard case let (_, stage, waxed)? = Copper.index[Blocks.key(Blocks.groupBase[Int(b)])], !waxed, stage < 3 else { return }
        guard Float.random(in: 0..<1) < 0.02 else { return }
        if let t = Copper.convert(b, stage: stage + 1, waxed: false) { world.setBlock(p.x, p.y, p.z, t) }
    }
}
