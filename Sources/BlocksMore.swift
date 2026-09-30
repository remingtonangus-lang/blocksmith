import Foundation

// More blocks: lush and deep-dark cave plants, the murk family, tuff variants, sea pickles, conduit,
// scaffolding, chains, lightning rods, campfires, beehives, rebirth anchor, lodestone, jukebox,
// frog lanterns, cocoa, turtle/snuffler eggs, frogspawn, frosted ice, tripwire hooks, archaeology blocks,
// proving spawners, vaults, the crafter, dense core.
extension BlockRegistry {
    func registerMoreBlocks() {
        func t6(_ s: String) -> [UInt16] { [UInt16](repeating: Tex.id(s), count: 6) }
        func cube(_ n: String, _ disp: String, _ tex: String? = nil, h: Float, tool: ToolType = .pickaxe, req: Bool = false, snd: SoundMat = .stone,
                  emit: UInt8 = 0, lvl: Int = 0) {
            guard !has(n) else { return }
            var d = BlockDef(n, disp)
            d.tex = [tex ?? n]; d.hardness = h; d.tool = tool; d.requiresTool = req; d.sound = snd; d.emit = emit; d.harvestLevel = lvl
            add(d)
        }
        func sided(_ n: String, _ disp: String, side: String, top: String, bottom: String, h: Float, tool: ToolType = .pickaxe, snd: SoundMat = .stone,
                   emit: UInt8 = 0, req: Bool = false) {
            guard !has(n) else { return }
            var d = BlockDef(n, disp)
            d.tex = [side, side, top, bottom, side, side]; d.hardness = h; d.tool = tool; d.sound = snd; d.emit = emit; d.requiresTool = req
            add(d)
        }
        func model(_ n: String, _ disp: String, _ tex: [String], _ boxes: [Box], h: Float, tool: ToolType = .pickaxe, snd: SoundMat = .stone,
                   emit: UInt8 = 0, collide: Bool = true, group: String? = nil, hidden: Bool = false, shape: String = "") {
            var d = BlockDef(n, disp)
            d.tex = tex; d.render = .model; d.layer = .cutout; d.opaque = false; d.boxes = boxes; d.hardness = h; d.tool = tool; d.sound = snd
            d.emit = emit; d.collide = collide; d.skyStop = false; d.group = group; d.hidden = hidden; d.shape = shape
            d.randomTicks = ["cocoa", "turtle_egg", "sniffer_egg"].contains(group ?? n)
            add(d)
        }
        func cross(_ n: String, _ disp: String, emit: UInt8 = 0, tex: String? = nil, group: String? = nil, hidden: Bool = false) {
            var d = BlockDef(n, disp)
            d.tex = [tex ?? n]; d.render = .cross; d.layer = .cutout; d.opaque = false; d.collide = false; d.hardness = 0; d.sound = .plant
            d.skyStop = false; d.emit = emit; d.group = group; d.hidden = hidden
            d.randomTicks = (group ?? n).hasSuffix("_crop")
            add(d)
        }

        // Lush caves.
        model("big_dripleaf", "Big Dripleaf", ["big_dripleaf_top", "big_dripleaf_top", "big_dripleaf_top", "big_dripleaf_top", "big_dripleaf_top", "big_dripleaf_top"],
              [Box(0, 15, 0, 16, 16, 16), Box(7, 0, 7, 9, 15, 9, tex: t6("big_dripleaf_stem"))], h: 0.1, tool: .axe, snd: .plant)
        cross("big_dripleaf_stem", "Big Dripleaf Stem", hidden: true)
        cross("small_dripleaf", "Small Dripleaf")
        cross("spore_blossom", "Spore Blossom")
        cross("hanging_roots", "Hanging Roots")
        var lichen = BlockDef("glow_lichen", "Glow Lichen")
        lichen.tex = ["glow_lichen"]; lichen.render = .model; lichen.layer = .cutout; lichen.opaque = false; lichen.collide = false
        lichen.boxes = [Box(0, 0, 0, 16, 1, 16)]; lichen.hardness = 0.2; lichen.sound = .plant; lichen.emit = 7; lichen.skyStop = false; lichen.replaceable = true
        add(lichen)
        // Murk family.
        var vein = BlockDef("sculk_vein", "Murk Vein")
        vein.tex = ["sculk_vein"]; vein.render = .model; vein.layer = .cutout; vein.opaque = false; vein.collide = false
        vein.boxes = [Box(0, 0, 0, 16, 1, 16)]; vein.hardness = 0.2; vein.tool = .hoe; vein.sound = .plant; vein.skyStop = false; vein.replaceable = true
        add(vein)
        for (n, disp) in [("sculk_sensor", "Murk Sensor"), ("calibrated_sculk_sensor", "Calibrated Murk Sensor")] {
            model(n, disp, ["sculk_sensor_side", "sculk_sensor_side", "sculk_sensor_top", "sculk_sensor_side", "sculk_sensor_side", "sculk_sensor_side"],
                  [Box(0, 0, 0, 16, 8, 16), Box(3, 8, 3, 5, 16, 5, tex: t6("sculk_tendril")), Box(11, 8, 11, 13, 16, 13, tex: t6("sculk_tendril"))], h: 1.5, tool: .hoe, emit: 1)
        }
        sided("sculk_catalyst", "Murk Catalyst", side: "sculk_catalyst_side", top: "sculk_catalyst_top", bottom: "sculk", h: 3, tool: .hoe, emit: 6)
        // Tuff variants (1.21).
        cube("polished_tuff", "Polished Tuff", h: 1.5, req: true)
        cube("tuff_bricks", "Tuff Bricks", h: 1.5, req: true)
        cube("chiseled_tuff", "Chiseled Tuff", h: 1.5, req: true)
        cube("chiseled_tuff_bricks", "Chiseled Tuff Bricks", h: 1.5, req: true)
        for (base, disp) in [("tuff", "Tuff"), ("polished_tuff", "Polished Tuff"), ("tuff_bricks", "Tuff Brick")] {
            let n = base == "tuff_bricks" ? "tuff_brick" : base
            if !has("\(n)_stairs") { family(base, n, disp, h: 1.5, tool: .pickaxe, req: true, snd: .stone, stairs: true, slab: true, fence: false, wall: true) }
        }
        // Ocean.
        for k in 0..<4 {
            model(k == 0 ? "sea_pickle" : "sea_pickle[\(k)]", "Sea Pickle", ["sea_pickle"],
                  [[Box(6, 0, 6, 10, 6, 10)], [Box(3, 0, 3, 7, 6, 7), Box(9, 0, 9, 13, 5, 13)],
                   [Box(3, 0, 3, 7, 6, 7), Box(9, 0, 5, 13, 5, 9), Box(5, 0, 10, 9, 4, 14)],
                   [Box(2, 0, 2, 6, 6, 6), Box(10, 0, 3, 14, 5, 7), Box(3, 0, 10, 7, 4, 14), Box(10, 0, 10, 14, 6, 14)]][k],
                  h: 0, snd: .plant, emit: UInt8(6 + 3 * k), collide: false, group: "sea_pickle", hidden: k != 0, shape: "pickle")
        }
        model("conduit", "Conduit", ["conduit"], [Box(5, 5, 5, 11, 11, 11)], h: 3, emit: 15)
        // Building / utility.
        model("scaffolding", "Scaffolding", ["scaffolding_top", "scaffolding_top", "scaffolding_top", "scaffolding_top", "scaffolding_top", "scaffolding_top"],
              [Box(0, 14, 0, 16, 16, 16), Box(0, 0, 0, 2, 14, 2, tex: t6("scaffolding_side")), Box(14, 0, 0, 16, 14, 2, tex: t6("scaffolding_side")),
               Box(0, 0, 14, 2, 14, 16, tex: t6("scaffolding_side")), Box(14, 0, 14, 16, 14, 16, tex: t6("scaffolding_side"))], h: 0, tool: .none, snd: .wood)
        model("chain", "Chain", ["chain"], [Box(7, 0, 7, 9, 16, 9)], h: 5)
        model("lightning_rod", "Lightning Rod", ["copper_block"], [Box(7, 0, 7, 9, 12, 9), Box(6, 12, 6, 10, 16, 10)], h: 3)
        for (n, disp, fire, emit) in [("campfire", "Campfire", "campfire_fire", UInt8(15)), ("soul_campfire", "Ghost Campfire", "soul_campfire_fire", UInt8(10))] {
            for lit in [false, true] {
                var d = BlockDef(lit ? n : "\(n)[off]", disp)
                d.group = n; d.hidden = !lit
                d.tex = ["campfire_log"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.hardness = 2; d.tool = .axe; d.sound = .wood
                d.emit = lit ? emit : 0; d.skyStop = false
                var logs = [Box(1, 0, 0, 5, 4, 16), Box(11, 0, 0, 15, 4, 16), Box(0, 3, 1, 16, 7, 5), Box(0, 3, 11, 16, 7, 15)]
                if lit { var f = Box(3, 1, 3, 13, 15, 13); f.tex = t6(fire); logs.append(f) }
                d.boxes = logs
                add(d)
            }
        }
        for (n, disp) in [("bee_nest", "Bee Nest"), ("beehive", "Beehive")] {
            for lvl in 0..<6 {
                var d = BlockDef(lvl == 0 ? n : "\(n)[\(lvl)]", disp)
                d.group = n; d.hidden = lvl != 0
                let front = lvl == 5 ? "\(n)_front_honey" : "\(n)_front"
                d.tex = ["\(n)_side", "\(n)_side", "\(n)_top", "\(n)_top", front, "\(n)_side"]
                d.hardness = n == "bee_nest" ? 0.3 : 0.6; d.tool = .axe; d.sound = .wood; d.randomTicks = true
                add(d)
            }
        }
        cube("honeycomb_block", "Honeycomb Block", h: 0.6, tool: .none, snd: .plant)
        pillar("bone_block", "Bone Block", side: "bone_block_side", top: "bone_block_top", h: 2, tool: .pickaxe, snd: .stone, req: true)
        sided("dried_kelp_block", "Dried Kelp Block", side: "dried_kelp_side", top: "dried_kelp_top", bottom: "dried_kelp_top", h: 0.5, tool: .hoe, snd: .plant)
        sided("lodestone", "Lodestone", side: "lodestone_side", top: "lodestone_top", bottom: "lodestone_top", h: 3.5, req: true)
        for c in 0...4 {
            var d = BlockDef(c == 0 ? "respawn_anchor" : "respawn_anchor[\(c)]", "Rebirth Anchor")
            d.group = "respawn_anchor"; d.hidden = c != 0
            d.tex = ["respawn_anchor_side", "respawn_anchor_side", c == 0 ? "respawn_anchor_top_off" : "respawn_anchor_top", "respawn_anchor_bottom", "respawn_anchor_side", "respawn_anchor_side"]
            d.hardness = 50; d.resistance = 1200; d.tool = .pickaxe; d.harvestLevel = 3; d.requiresTool = true; d.emit = UInt8([0, 3, 7, 11, 15][c])
            add(d)
        }
        sided("jukebox", "Jukebox", side: "jukebox_side", top: "jukebox_top", bottom: "jukebox_side", h: 2, tool: .axe, snd: .wood)
        for (n, disp) in [("ochre_froglight", "Ochre Frog Lantern"), ("verdant_froglight", "Verdant Frog Lantern"), ("pearlescent_froglight", "Pearlescent Frog Lantern")] {
            sided(n, disp, side: "\(n)_side", top: "\(n)_top", bottom: "\(n)_top", h: 0.3, tool: .none, snd: .plant, emit: 15)
        }
        for age in 0..<3 {
            let s = 4 + age * 2
            model(age == 0 ? "cocoa" : "cocoa[\(age)]", "Cocoa", ["cocoa_stage\(age)"], [Box(8 - s / 2, 12 - s - 2, 1, 8 + s / 2, 12, 1 + s)],
                  h: 0.2, tool: .axe, snd: .wood, collide: false, group: "cocoa", hidden: age != 0)
        }
        for k in 0..<4 {
            model(k == 0 ? "turtle_egg" : "turtle_egg[\(k)]", "Turtle Egg", ["turtle_egg"],
                  [[Box(5, 0, 4, 9, 7, 8)], [Box(3, 0, 3, 7, 7, 7), Box(9, 0, 8, 13, 6, 12)], [Box(3, 0, 3, 7, 7, 7), Box(9, 0, 8, 13, 6, 12), Box(8, 0, 2, 12, 5, 6)],
                   [Box(3, 0, 3, 7, 7, 7), Box(9, 0, 8, 13, 6, 12), Box(8, 0, 2, 12, 5, 6), Box(2, 0, 9, 6, 5, 13)]][k], h: 0.5, snd: .stone,
                  group: "turtle_egg", hidden: k != 0, shape: "egg")
        }
        model("sniffer_egg", "Snuffler Egg", ["sniffer_egg"], [Box(1, 0, 2, 15, 16, 14)], h: 0.5)
        var spawn = BlockDef("frogspawn", "Frogspawn")
        spawn.tex = ["frogspawn"]; spawn.render = .model; spawn.layer = .cutout; spawn.opaque = false; spawn.collide = false
        spawn.boxes = [Box(0, 0, 0, 16, 1, 16)]; spawn.hardness = 0; spawn.skyStop = false; spawn.randomTicks = true
        add(spawn)
        for age in 0..<4 {
            var fi = BlockDef(age == 0 ? "frosted_ice" : "frosted_ice[\(age)]", "Frosted Ice")
            fi.group = "frosted_ice"; fi.hidden = true
            fi.tex = ["frosted_ice_\(age)"]; fi.opaque = false; fi.layer = .translucent; fi.hardness = 0.5; fi.sound = .glass; fi.randomTicks = true
            add(fi)
        }
        // Tripwire hooks: facing = the way the hook points (string runs that way), +4 when pulled (powered).
        for st in 0..<8 {
            let f = st % 4, y: Int = st >= 4 ? 6 : 8
            let boxes: [[Box]] = [[Box(7, 2, 14, 9, 10, 16), Box(7, y, 10, 9, y + 2, 14)], [Box(7, 2, 0, 9, 10, 2), Box(7, y, 2, 9, y + 2, 6)],
                                  [Box(14, 2, 7, 16, 10, 9), Box(10, y, 7, 14, y + 2, 9)], [Box(0, 2, 7, 2, 10, 9), Box(2, y, 7, 6, y + 2, 9)]]
            model(st == 0 ? "tripwire_hook" : "tripwire_hook[\(st)]", "Tripwire Hook", ["tripwire_hook"], boxes[f], h: 0, tool: .none, snd: .wood,
                  collide: false, group: "tripwire_hook", hidden: st != 0, shape: "hook")
        }
        var wire = BlockDef("tripwire", "Tripwire")
        wire.tex = ["tripwire"]; wire.render = .model; wire.layer = .cutout; wire.opaque = false; wire.collide = false
        wire.boxes = [Box(0, 1, 7, 16, 2, 9)]; wire.hardness = 0; wire.hidden = true; wire.skyStop = false
        add(wire)
        // Plants of the snuffler era.
        cross("torchflower", "Torchflower")
        for s in 0..<2 { cross(s == 0 ? "torchflower_crop" : "torchflower_crop[1]", "Torchflower Crop", tex: "torchflower_crop\(s)", group: "torchflower_crop", hidden: true) }
        cross("pitcher_plant", "Pitcher Plant")
        for s in 0..<5 { cross(s == 0 ? "pitcher_crop" : "pitcher_crop[\(s)]", "Pitcher Crop", tex: "pitcher_crop\(min(s, 3))", group: "pitcher_crop", hidden: true) }
        // Archaeology and proving halls.
        for (n, disp, base) in [("suspicious_sand", "Suspicious Sand", "sand"), ("suspicious_gravel", "Suspicious Gravel", "gravel")] {
            var d = BlockDef(n, disp); d.tex = ["\(n)"]; d.hardness = 0.25; d.tool = .shovel; d.sound = .sand; add(d); _ = base
        }
        model("decorated_pot", "Decorated Pot", ["decorated_pot"], [Box(1, 0, 1, 15, 13, 15), Box(4, 13, 4, 12, 16, 12)], h: 0, tool: .none)
        for (n, disp) in [("trial_spawner", "Proving Spawner"), ("vault", "Vault")] {
            var d = BlockDef(n, disp)
            d.tex = ["\(n)_side", "\(n)_side", "\(n)_top", "\(n)_top", "\(n)_side", "\(n)_side"]; d.hardness = 50; d.opaque = false; d.layer = .cutout
            d.emit = 6; d.skyStop = false
            add(d)
        }
        var crafter = BlockDef("crafter", "Crafter")
        crafter.tex = ["crafter_side", "crafter_side", "crafter_top", "crafter_bottom", "crafter_side", "crafter_side"]; crafter.hardness = 1.5
        _ = addFacing(crafter, front: "crafter_front")
        model("heavy_core", "Dense Core", ["heavy_core"], [Box(4, 0, 4, 12, 8, 12)], h: 10)
    }
}

extension TextureGen {
    static func morePainters(_ p: inout [String: Painter]) {
        func spots(_ base: UInt32, _ spot: UInt32, _ k: Float, _ salt: Int) -> Painter {
            { x, y in hex(r(x / 2, y / 2, salt) < k ? spot : base, 0.88 + 0.18 * r(x, y, salt + 1)) }
        }
        p["big_dripleaf_top"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            if dx * dx + dy * dy > 64 { return clear }
            return hex(abs(x - 8) < 1 ? 0x5A8A2A : 0x6AA83A, 0.9 + 0.15 * r(x, y, 930))
        }
        p["big_dripleaf_stem"] = { x, y in (x == 7 || x == 8) ? hex(0x5A8A2A) : clear }
        p["small_dripleaf"] = { x, y in
            if (x == 7 || x == 8) && y > 6 { return hex(0x5A8A2A) }
            let dx = Float(x) - 7.5, dy = Float(y) - 4
            return dx * dx + dy * dy * 3 < 30 ? hex(0x6AA83A, 0.9 + 0.1 * r(x, y, 931)) : clear
        }
        p["spore_blossom"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            let d = dx * dx + dy * dy
            if d < 6 { return hex(0xE87AB0) }
            if d < 40 && (x + y) % 3 == 0 { return hex(0x5A8A2A) }
            return clear
        }
        p["hanging_roots"] = { x, y in (x % 4 == 1 && r(x, 0, 932) * 16 > Float(y) * 0.8) ? hex(0x9A6A4A) : clear }
        p["glow_lichen"] = { x, y in r(x / 2, y / 2, 933) < 0.45 ? hex(0x7ACAAA, 0.9 + 0.2 * r(x, y, 934)) : clear }
        p["sculk_vein"] = { x, y in r(x / 2, y / 2, 935) < 0.35 ? hex(0x0A3A48, 0.9 + 0.3 * r(x, y, 936)) : clear }
        p["sculk_sensor_side"] = { x, y in y < 8 ? clear : hex(0x0A2A38, 0.85 + 0.3 * r(x, y, 937)) }
        p["sculk_sensor_top"] = spots(0x0A2A38, 0x3AD8D8, 0.12, 938)
        p["sculk_tendril"] = { x, y in hex(0x3AB8C8, 0.9 + 0.2 * r(x, y, 939)) }
        p["sculk_catalyst_side"] = { x, y in y < 5 ? hex(0x0A2A38, 0.9) : hex(0xD8D0C0, 0.85 + 0.2 * r(x, y, 940)) }
        p["sculk_catalyst_top"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            if dx * dx + dy * dy < 10 { return hex(0x6AF0F0) }
            return hex(0x0A2A38, 0.85 + 0.2 * r(x, y, 941))
        }
        let tuff: UInt32 = 0x6D6D63
        p["polished_tuff"] = { x, y in (x == 0 || y == 0 || x == 15 || y == 15) ? hex(tuff, 0.75) : hex(tuff, 0.95 + 0.06 * r(x, y, 942)) }
        p["tuff_bricks"] = { x, y in (y % 8 == 0 || (x + (y / 8) * 8) % 16 == 0) ? hex(tuff, 0.65) : hex(tuff, 0.92 + 0.1 * r(x, y, 943)) }
        p["chiseled_tuff"] = { x, y in (y == 4 || y == 11) ? hex(tuff, 0.6) : hex(tuff, 0.95 + 0.06 * r(x, y, 944)) }
        p["chiseled_tuff_bricks"] = { x, y in (abs(x - 8) + abs(y - 8) == 5) ? hex(0x9A6A4A) : hex(tuff, 0.92 + 0.08 * r(x, y, 945)) }
        p["sea_pickle"] = { x, y in hex(0x6A8A3A, 0.85 + 0.25 * r(x, y, 946)) }
        p["conduit"] = { x, y in (x + y) % 5 == 0 ? hex(0xE8C040) : hex(0x6A5A40, 0.9 + 0.15 * r(x, y, 947)) }
        p["scaffolding_top"] = { x, y in (x < 2 || y < 2 || x > 13 || y > 13 || x == y || x == 15 - y) ? hex(0xD8B060) : clear }
        p["scaffolding_side"] = { x, y in hex(0xC8A050, 0.9 + 0.1 * r(x, y, 948)) }
        p["chain"] = { x, y in (x == 7 || x == 8) && (y % 4 != 3) ? hex(0x3A3E48) : clear }
        p["campfire_log"] = { x, y in (y % 5 == 0) ? hex(0x4A3A22) : hex(0x6B4F2C, 0.85 + 0.2 * r(x, y, 949)) }
        p["campfire_fire"] = { x, y in
            let h = 16 - Int(r(x, 0, 950) * 10) - 3
            return y > h ? V4(1, 0.55 + 0.4 * Float(16 - y) / 16, 0.1, 1) : clear
        }
        p["soul_campfire_fire"] = { x, y in
            let h = 16 - Int(r(x, 0, 951) * 10) - 3
            return y > h ? V4(0.3, 0.85 + 0.15 * Float(16 - y) / 16, 0.95, 1) : clear
        }
        for n in ["bee_nest", "beehive"] {
            let base: UInt32 = n == "bee_nest" ? 0xD8A840 : 0xB88A4A
            p["\(n)_side"] = { x, y in y % 4 == 0 ? hex(base, 0.75) : hex(base, 0.9 + 0.12 * r(x, y, 952)) }
            p["\(n)_top"] = { x, y in hex(base, 0.85 + 0.15 * r(x / 2, y / 2, 953)) }
            p["\(n)_front"] = { x, y in (abs(x - 8) < 2 && abs(y - 9) < 2) ? hex(0x2A1A0A) : hex(base, 0.9 + 0.12 * r(x, y, 954)) }
            p["\(n)_front_honey"] = { x, y in
                if abs(x - 8) < 2 && abs(y - 9) < 2 { return hex(0x2A1A0A) }
                if y > 10 && r(x, 0, 955) < 0.5 { return hex(0xF0A020) }
                return hex(base, 0.9 + 0.12 * r(x, y, 954))
            }
        }
        p["honeycomb_block"] = { x, y in (x % 4 == 0 || (y + (x / 4) * 2) % 4 == 0) ? hex(0xB87810) : hex(0xE8A020, 0.9 + 0.1 * r(x, y, 956)) }
        p["bone_block_side"] = { x, y in hex(0xE8E4D6, (x == 0 || x == 15) ? 0.8 : 0.95 + 0.05 * r(x, y, 957)) }
        p["bone_block_top"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            return hex(dx * dx + dy * dy < 20 ? 0xC8C4B6 : 0xE8E4D6)
        }
        p["dried_kelp_side"] = { x, y in hex(y % 3 == 0 ? 0x2A3A1A : 0x3A4A2A, 0.9 + 0.15 * r(x, y, 958)) }
        p["dried_kelp_top"] = { x, y in hex(0x3A4A2A, 0.85 + 0.2 * r(x, y, 959)) }
        p["lodestone_side"] = { x, y in (y < 3 || y > 12) ? hex(0x8A8A8A) : hex(0x5A5A5E, 0.9 + 0.15 * r(x, y, 960)) }
        p["lodestone_top"] = { x, y in (abs(x - 8) < 3 && abs(y - 8) < 3) ? hex(0x3A3A40) : hex(0x8A8A8A, 0.9 + 0.1 * r(x, y, 961)) }
        p["respawn_anchor_side"] = { x, y in (x < 2 || x > 13) ? hex(0x2A1A3A) : hex(0x1A1228, 0.8 + 0.3 * r(x, y, 962)) }
        p["respawn_anchor_top"] = { x, y in (abs(x - 8) < 5 && abs(y - 8) < 5) ? hex(0xB060F0, 0.8 + 0.3 * r(x, y, 963)) : hex(0x1A1228) }
        p["respawn_anchor_top_off"] = { x, y in (abs(x - 8) < 5 && abs(y - 8) < 5) ? hex(0x2A1A3A) : hex(0x1A1228) }
        p["respawn_anchor_bottom"] = { x, y in hex(0x1A1228, 0.8 + 0.3 * r(x, y, 964)) }
        p["jukebox_side"] = { x, y in (x < 2 || x > 13 || y < 2 || y > 13) ? hex(0x5A3A22) : hex(0x7A5230, 0.9 + 0.12 * r(x, y, 965)) }
        p["jukebox_top"] = { x, y in (abs(x - 8) < 5 && abs(y - 8) < 2) ? hex(0x1A1A1A) : hex(0x7A5230, 0.9 + 0.12 * r(x, y, 966)) }
        for (n, c) in [("ochre_froglight", 0xF8D880 as UInt32), ("verdant_froglight", 0xD8F0B0), ("pearlescent_froglight", 0xF0D8F0)] {
            p["\(n)_side"] = { x, y in (x % 5 == 0 || y % 5 == 0) ? hex(c, 0.85) : hex(c, 1.0 + 0.05 * r(x, y, 967)) }
            p["\(n)_top"] = { x, y in hex(c, 0.95 + 0.05 * r(x, y, 968)) }
        }
        for age in 0..<3 {
            let c: UInt32 = [0x6A8A2A, 0xA87A3A, 0x8A5A2A][age]
            p["cocoa_stage\(age)"] = { x, y in hex(c, (y % 3 == 0) ? 0.8 : 0.95 + 0.08 * r(x, y, 969)) }
        }
        p["turtle_egg"] = { x, y in r(x / 2, y / 2, 970) < 0.2 ? hex(0x6AA84A) : hex(0xE8E4C8, 0.95) }
        p["sniffer_egg"] = { x, y in r(x / 2, y / 2, 971) < 0.3 ? hex(0x6A3A2A) : hex(0xA84A3A, 0.9 + 0.12 * r(x, y, 972)) }
        p["frogspawn"] = { x, y in (x % 3 == 1 && y % 3 == 1) ? hex(0x1A1A1A) : ((x + y) % 3 == 0 ? V4(0.6, 0.6, 0.55, 0.4) : clear) }
        for age in 0..<4 { p["frosted_ice_\(age)"] = { x, y in V4(0.72, 0.85, 1, 0.6 + 0.1 * Float(age) + (r(x, y, 973 + age) < Float(age) * 0.15 ? 0.3 : 0)) } }
        p["tripwire_hook"] = { x, y in hex(0x9A9A9A) }
        p["tripwire"] = { x, y in (y == 7 || y == 8) ? V4(0.9, 0.9, 0.9, 0.8) : clear }
        p["torchflower"] = { x, y in
            if (x == 7 || x == 8) && y > 7 { return hex(0x5A8A2A) }
            let dx = Float(x) - 7.5, dy = Float(y) - 4.5
            return dx * dx + dy * dy < 10 ? hex(0xF08A2A, 0.9 + 0.1 * r(x, y, 977)) : clear
        }
        for s in 0..<2 { p["torchflower_crop\(s)"] = { x, y in ((x == 7 || x == 8) && y > 10 - s * 3) ? hex(0x5A8A2A) : clear } }
        p["pitcher_plant"] = { x, y in
            if (x == 7 || x == 8) && y > 8 { return hex(0x3A7A6A) }
            let dx = Float(x) - 7.5, dy = Float(y) - 5
            return dx * dx * 0.6 + dy * dy < 14 ? hex(0x5A7AC8, 0.9 + 0.1 * r(x, y, 978)) : clear
        }
        for s in 0..<4 { p["pitcher_crop\(s)"] = { x, y in ((x == 7 || x == 8) && y > 12 - s * 3) ? hex(0x3A7A6A) : clear } }
        p["suspicious_sand"] = { x, y in hex(r(x / 2, y / 2, 979) < 0.08 ? 0xA89A6A : 0xDBD3A0, 0.9 + 0.12 * r(x, y, 980)) }
        p["suspicious_gravel"] = { x, y in hex(r(x / 2, y / 2, 981) < 0.1 ? 0x6A6A60 : 0x8A8480, 0.85 + 0.2 * r(x, y, 982)) }
        p["decorated_pot"] = { x, y in (y == 3 || y == 10) ? hex(0x6A3A2A) : hex(0xA8583A, 0.9 + 0.1 * r(x, y, 983)) }
        for n in ["trial_spawner", "vault"] {
            let accent: UInt32 = n == "vault" ? 0x3A5A8A : 0xE8A040
            p["\(n)_side"] = { x, y in (x < 2 || x > 13 || y < 2 || y > 13) ? hex(0x4A4A50) : ((x + y) % 4 == 0 ? hex(accent) : clear) }
            p["\(n)_top"] = { x, y in (x < 2 || x > 13 || y < 2 || y > 13) ? hex(0x4A4A50) : hex(0x2A2A30) }
        }
        p["crafter_side"] = { x, y in (x < 2 || x > 13 || y < 3) ? hex(0x6A6A6A) : hex(0x9A7A4A, 0.9 + 0.1 * r(x, y, 984)) }
        p["crafter_top"] = { x, y in (x % 5 == 0 || y % 5 == 0) ? hex(0x5A5A5A) : hex(0x9A7A4A, 0.9 + 0.1 * r(x, y, 985)) }
        p["crafter_front"] = { x, y in (x < 2 || x > 13 || y < 2 || y > 13) ? hex(0x6A6A6A) : ((x > 5 && x < 10 && y > 5 && y < 10) ? hex(0x2A2A2A) : hex(0x9A7A4A, 0.9 + 0.1 * r(x, y, 988))) }
        p["crafter_bottom"] = { x, y in hex(0x6A6A6A, 0.9 + 0.1 * r(x, y, 986)) }
        p["heavy_core"] = { x, y in hex(0x4A4A52, 0.85 + 0.2 * r(x / 2, y / 2, 987)) }
    }
}
