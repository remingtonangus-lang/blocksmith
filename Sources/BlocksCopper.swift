import Foundation

// Copper: four oxidation stages (unaffected, exposed, weathered, oxidized) × waxed / unwaxed for the
// block, cut copper (+ stairs, slabs), chiseled copper, grates and bulbs. Unwaxed copper ages on random
// ticks; an axe scrapes a stage (or the wax) off; honeycomb waxes it.
enum Copper {
    static let stages: [(prefix: String, disp: String, hex: UInt32)] = [
        ("", "", 0xC06B4F), ("exposed_", "Exposed ", 0xA17E68), ("weathered_", "Weathered ", 0x6C9A6C), ("oxidized_", "Oxidized ", 0x52A284),
    ]
    static let forms = ["block", "cut_copper", "chiseled_copper", "copper_grate", "copper_bulb", "cut_copper_stairs", "cut_copper_slab",
                        "copper_chest", "copper_golem_statue", "copper_lantern", "copper_bars", "copper_chain",
                        "copper_door", "copper_trapdoor", "lightning_rod"]

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
                // Copper chest (CopperGolem.swift: golems carry items out of these into ordinary chests); ages like copper.
                var cc = BlockDef(Copper.name("copper_chest", stage: s, waxed: waxed), "\(w)\(st.disp)Copper Chest")
                cc.tex = ["\(st.prefix)copper_chest_side", "\(st.prefix)copper_chest_side", "\(st.prefix)copper_chest_top",
                          "\(st.prefix)copper_chest_top", "\(st.prefix)copper_chest_side", "\(st.prefix)copper_chest_side"]
                cc.render = .model; cc.opaque = false; cc.hardness = 3; cc.tool = .axe; cc.skyStop = true
                cc.randomTicks = !waxed && s < 3
                addFacing(cc, front: "\(st.prefix)copper_chest_front", boxes: [Box(1, 0, 1, 15, 14, 15)])
                // Copper golem statue: what an oxidized golem becomes (an axe scrapes it back to life).
                var gs = BlockDef(Copper.name("copper_golem_statue", stage: s, waxed: waxed), "\(w)\(st.disp)Copper Golem Statue")
                gs.tex = [tex]; gs.render = .model; gs.opaque = false; gs.hardness = 3; gs.tool = .pickaxe; gs.skyStop = false
                gs.boxes = [Box(5, 0, 7, 7, 3, 10), Box(9, 0, 7, 11, 3, 10), Box(4, 3, 6, 12, 8, 11), Box(2, 4, 7, 4, 8, 10),
                            Box(12, 4, 7, 14, 8, 10), Box(3, 8, 5, 13, 13, 12), Box(7, 13, 8, 9, 15, 10), Box(6, 15, 7, 10, 16, 11)]
                add(gs)
                // Copper lantern (green flame; standing / hanging), copper bars and copper chain.
                let ln = Copper.name("copper_lantern", stage: s, waxed: waxed)
                for hanging in [false, true] {
                    var d = BlockDef(hanging ? "\(ln)[hanging]" : ln, "\(w)\(st.disp)Copper Lantern")
                    d.tex = ["\(st.prefix)copper_lantern"]; d.render = .model; d.layer = .cutout; d.opaque = false
                    d.boxes = hanging ? [Box(5, 1, 5, 11, 8, 11), Box(6, 8, 6, 10, 10, 10), Box(7, 10, 7, 9, 16, 9)] : [Box(5, 0, 5, 11, 7, 11), Box(6, 7, 6, 10, 9, 10)]
                    d.emit = 15; d.hardness = 3.5; d.tool = .pickaxe; d.group = ln; d.hidden = hanging; d.skyStop = false
                    d.shape = "lantern"; d.randomTicks = !waxed && s < 3
                    add(d)
                }
                var bars = BlockDef(Copper.name("copper_bars", stage: s, waxed: waxed), "\(w)\(st.disp)Copper Bars")
                bars.tex = ["\(st.prefix)copper_bars"]; bars.render = .connect; bars.connect = 2; bars.layer = .cutout; bars.opaque = false
                bars.hardness = 5; bars.tool = .pickaxe; bars.requiresTool = true; bars.skyStop = false; bars.randomTicks = !waxed && s < 3
                add(bars)
                var chain = BlockDef(Copper.name("copper_chain", stage: s, waxed: waxed), "\(w)\(st.disp)Copper Chain")
                chain.tex = ["\(st.prefix)copper_chain"]; chain.render = .model; chain.layer = .cutout; chain.opaque = false; chain.boxes = [Box(7, 0, 7, 9, 16, 9)]
                chain.hardness = 5; chain.tool = .pickaxe; chain.skyStop = false; chain.randomTicks = !waxed && s < 3
                add(chain)
                // Lightning rod: draws strikes within 64 blocks (Weather.swift); a strike scrapes its copper clean.
                var rod = BlockDef(Copper.name("lightning_rod", stage: s, waxed: waxed), "\(w)\(st.disp)Lightning Rod")
                rod.tex = [tex]; rod.render = .model; rod.layer = .cutout; rod.opaque = false; rod.skyStop = false
                rod.boxes = [Box(7, 0, 7, 9, 12, 9), Box(6, 12, 6, 10, 16, 10)]; rod.hardness = 3; rod.tool = .pickaxe
                rod.randomTicks = !waxed && s < 3
                add(rod)
                // Copper door and trapdoor: open by hand like wooden ones.
                let dn = Copper.name("copper_door", stage: s, waxed: waxed), tn = Copper.name("copper_trapdoor", stage: s, waxed: waxed)
                for upper in [false, true] { for open in [false, true] { for f in 0..<4 {
                    let k = f + (open ? 4 : 0) + (upper ? 8 : 0)
                    var d = BlockDef(k == 0 ? dn : "\(dn)[\(k)]", "\(w)\(st.disp)Copper Door")
                    d.tex = [upper ? "\(st.prefix)copper_door_top" : "\(st.prefix)copper_door_bottom"]; d.render = .model; d.layer = .cutout; d.opaque = false
                    d.boxes = [BlockRegistry.panel(open ? [2, 3, 1, 0][f] : [0, 1, 2, 3][f])]
                    d.hardness = 3; d.tool = .pickaxe; d.group = dn; d.hidden = k != 0; d.shape = "door"; d.skyStop = false
                    d.randomTicks = !waxed && s < 3
                    add(d)
                } } }
                for top in [false, true] { for open in [false, true] { for f in 0..<4 {
                    let k = f + (open ? 4 : 0) + (top ? 8 : 0)
                    var d = BlockDef(k == 0 ? tn : "\(tn)[\(k)]", "\(w)\(st.disp)Copper Trapdoor")
                    d.tex = ["\(st.prefix)copper_trapdoor"]; d.render = .model; d.layer = .cutout; d.opaque = false
                    d.boxes = [open ? BlockRegistry.panel([1, 0, 3, 2][f]) : (top ? Box(0, 13, 0, 16, 16, 16) : Box(0, 0, 0, 16, 3, 16))]
                    d.hardness = 3; d.tool = .pickaxe; d.group = tn; d.hidden = k != 0; d.shape = "trapdoor"; d.skyStop = false
                    d.randomTicks = !waxed && s < 3
                    add(d)
                } } }
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
            p["\(st.prefix)copper_lantern"] = { x, y in
                if y < 3 || y > 13 || x < 3 || x > 12 { return hex(c, 0.7) }
                return hex(0x9CF07A, 0.85 + 0.25 * r(x, y, 928))
            }
            p["\(st.prefix)copper_bars"] = { x, y in
                let bar = x % 5 == 2 || x % 5 == 3
                let rail = y == 1 || y == 14
                if bar || (rail && x > 0 && x < 15) { return hex(c, (x % 5 == 2 ? 1.0 : 0.78) + 0.08 * r(x, y, 929)) }
                return clear
            }
            p["\(st.prefix)copper_chain"] = { x, y in (x == 7 || x == 8) && (y % 4 != 3) ? hex(c, 0.75) : clear }
            // Copper door (two windows up top) and trapdoor (four-pane grille).
            p["\(st.prefix)copper_door_top"] = { x, y in
                if x <= 1 || x >= 14 || y <= 1 { return hex(c, 0.7) }
                if (x == 7 || x == 8) || y == 8 { return hex(c, 0.75) }
                if y < 8 { return clear }
                return hex(c, 0.9 + 0.12 * r(x, y, 930))
            }
            p["\(st.prefix)copper_door_bottom"] = { x, y in
                if x <= 1 || x >= 14 || y >= 14 { return hex(c, 0.7) }
                if x == 11 && (y == 2 || y == 3) { return hex(0x2A2A2A) }
                return hex(c, y % 5 == 0 ? 0.78 : 0.9 + 0.12 * r(x, y, 931))
            }
            p["\(st.prefix)copper_trapdoor"] = { x, y in
                if x <= 1 || x >= 14 || y <= 1 || y >= 14 || x == 7 || x == 8 || y == 7 || y == 8 { return hex(c, 0.75 + 0.1 * r(x, y, 932)) }
                return (x + y) % 3 == 0 ? hex(c, 0.6) : clear
            }
            // Copper chest: riveted plates with a dark band and a latch.
            p["\(st.prefix)copper_chest_top"] = { x, y in
                if x <= 1 || y <= 1 || x >= 14 || y >= 14 { return hex(c, 0.62) }
                if (x == 3 || x == 12) && (y == 3 || y == 12) { return hex(c, 1.2) }
                return hex(c, 0.9 + 0.12 * r(x, y, 925))
            }
            p["\(st.prefix)copper_chest_side"] = { x, y in
                if x <= 1 || x >= 14 || y <= 2 || y >= 15 || y == 7 || y == 8 { return hex(c, 0.62) }
                return hex(c, 0.88 + 0.14 * r(x, y, 926))
            }
            p["\(st.prefix)copper_chest_front"] = { x, y in
                if x >= 6 && x <= 9 && y >= 5 && y <= 10 { return x >= 7 && x <= 8 && y >= 7 && y <= 8 ? hex(0x2A2A2A) : hex(0xD8B070) }
                if x <= 1 || x >= 14 || y <= 2 || y >= 15 || y == 7 || y == 8 { return hex(c, 0.62) }
                return hex(c, 0.88 + 0.14 * r(x, y, 927))
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

    // Lightning striking copper (a rod, a roof) clears the struck block's oxidation and knocks a stage off
    // a few copper blocks around it. Wax is kept.
    func scrapeCopperByLightning(_ p: IVec3) {
        func clean(_ q: IVec3, to stage: (Int) -> Int) {
            let b = world.block(q.x, q.y, q.z)
            guard case let (_, st, waxed)? = Copper.index[Blocks.key(Blocks.groupBase[Int(b)])], st > 0,
                  let t = Copper.convert(b, stage: stage(st), waxed: waxed) else { return }
            world.setBlock(q.x, q.y, q.z, t)
        }
        guard Copper.index[Blocks.key(Blocks.groupBase[Int(world.block(p.x, p.y, p.z))])] != nil else { return }
        clean(p) { _ in 0 }
        for _ in 0..<5 {
            let q = IVec3(p.x + Int.random(in: -3...3), p.y + Int.random(in: -3...1), p.z + Int.random(in: -3...3))
            clean(q) { $0 - 1 }
        }
    }

    // Random-tick oxidation (roughly one stage per hour of loaded time, like the reference average).
    func copperAge(_ p: IVec3, _ b: BlockID) {
        guard case let (_, stage, waxed)? = Copper.index[Blocks.key(Blocks.groupBase[Int(b)])], !waxed, stage < 3 else { return }
        guard Float.random(in: 0..<1) < 0.02 else { return }
        if let t = Copper.convert(b, stage: stage + 1, waxed: false) { world.setBlock(p.x, p.y, p.z, t) }
    }
}
