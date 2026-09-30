import Foundation

// Doors, trapdoors, fence gates, ladders, paths, lanterns, bells, workstations, carpets and the
// sandstone family — what villages (and players) build with.
//
// State layouts (offset from the group's first state):
//   door:     facing + open*4 + upper*8        (16)
//   trapdoor: facing + open*4 + top*8          (16)
//   gate:     facing + open*4                  (8)
//   ladder:   facing                           (4)
//   lantern:  hanging                          (2)
// facing: 0 north, 1 south, 2 west, 3 east (the side facing the player who placed it).
extension BlockRegistry {
    static let doorWoods = ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "crimson", "warped"]

    // Thin panel on one side of the block: 0 -Z side, 1 +Z, 2 -X, 3 +X.
    static func panel(_ side: Int, t: Int = 3) -> Box {
        switch side {
        case 0: return Box(0, 0, 0, 16, 16, t)
        case 1: return Box(0, 0, 16 - t, 16, 16, 16)
        case 2: return Box(0, 0, 0, t, 16, 16)
        default: return Box(16 - t, 0, 0, 16, 16, 16)
        }
    }

    func registerBuildingBlocks() {
        func cube(_ n: String, _ disp: String, _ t: String? = nil, h: Float = 2, tool: ToolType = .axe, snd: SoundMat = .wood, req: Bool = false) {
            var d = BlockDef(n, disp)
            d.tex = [t ?? n]; d.hardness = h; d.tool = tool; d.sound = snd; d.requiresTool = req
            add(d)
        }
        func sided(_ n: String, _ disp: String, side: String, top: String, bottom: String, h: Float = 2.5, tool: ToolType = .axe, snd: SoundMat = .wood, req: Bool = false) {
            var d = BlockDef(n, disp)
            d.tex = [side, side, top, bottom, side, side]; d.hardness = h; d.tool = tool; d.sound = snd; d.requiresTool = req
            add(d)
        }
        func model(_ n: String, _ disp: String, _ tex: [String], _ boxes: [Box], h: Float = 2, tool: ToolType = .pickaxe, snd: SoundMat = .stone,
                   emit: UInt8 = 0, cutout: Bool = false, req: Bool = false) {
            var d = BlockDef(n, disp)
            d.tex = tex; d.render = .model; d.opaque = false; d.boxes = boxes; d.hardness = h; d.tool = tool; d.sound = snd
            d.emit = emit; d.requiresTool = req; d.skyStop = false
            if cutout { d.layer = .cutout }
            add(d)
        }

        var path = BlockDef("dirt_path", "Dirt Path")
        path.tex = ["dirt_path_side", "dirt_path_side", "dirt_path_top", "dirt", "dirt_path_side", "dirt_path_side"]
        path.render = .model; path.opaque = false; path.boxes = [Box(0, 0, 0, 16, 15, 16)]; path.hardness = 0.65
        path.tool = .shovel; path.sound = .dirt; path.skyStop = true
        add(path)

        // Doors, trapdoors, gates.
        let metal: [(String, String)] = [("iron", "Iron")]
        for w in BlockRegistry.doorWoods + metal.map({ $0.0 }) {
            let iron = w == "iron"
            let disp = iron ? "Iron" : w.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
            for upper in [false, true] { for open in [false, true] { for f in 0..<4 {
                let k = f + (open ? 4 : 0) + (upper ? 8 : 0)
                var d = BlockDef(k == 0 ? "\(w)_door" : "\(w)_door[\(k)]", "\(disp) Door")
                d.tex = [upper ? "\(w)_door_top" : "\(w)_door_bottom"]; d.render = .model; d.layer = .cutout; d.opaque = false
                let side = open ? [2, 3, 1, 0][f] : [0, 1, 2, 3][f]
                d.boxes = [BlockRegistry.panel(side)]
                d.hardness = iron ? 5 : 3; d.tool = iron ? .pickaxe : .axe; d.requiresTool = iron; d.sound = iron ? .stone : .wood
                d.group = "\(w)_door"; d.hidden = k != 0; d.shape = "door"; d.skyStop = false
                add(d)
            } } }
            for top in [false, true] { for open in [false, true] { for f in 0..<4 {
                let k = f + (open ? 4 : 0) + (top ? 8 : 0)
                var d = BlockDef(k == 0 ? "\(w)_trapdoor" : "\(w)_trapdoor[\(k)]", "\(disp) Trapdoor")
                d.tex = ["\(w)_trapdoor"]; d.render = .model; d.layer = .cutout; d.opaque = false
                d.boxes = [open ? BlockRegistry.panel([1, 0, 3, 2][f]) : (top ? Box(0, 13, 0, 16, 16, 16) : Box(0, 0, 0, 16, 3, 16))]
                d.hardness = iron ? 5 : 3; d.tool = iron ? .pickaxe : .axe; d.requiresTool = iron; d.sound = iron ? .stone : .wood
                d.group = "\(w)_trapdoor"; d.hidden = k != 0; d.shape = "trapdoor"; d.skyStop = false
                add(d)
            } } }
            if iron { continue }
            for open in [false, true] { for f in 0..<4 {
                let k = f + (open ? 4 : 0)
                var d = BlockDef(k == 0 ? "\(w)_fence_gate" : "\(w)_fence_gate[\(k)]", "\(disp) Fence Gate")
                d.tex = ["\(w)_planks"]; d.render = .model; d.opaque = false
                let alongX = f <= 1
                if alongX {
                    d.boxes = [Box(0, 5, 7, 2, 16, 9), Box(14, 5, 7, 16, 16, 9)]
                    d.boxes += open ? [Box(0, 6, 9, 2, 15, 16), Box(14, 6, 9, 16, 15, 16)] : [Box(2, 6, 7, 14, 9, 9), Box(2, 12, 7, 14, 15, 9)]
                } else {
                    d.boxes = [Box(7, 5, 0, 9, 16, 2), Box(7, 5, 14, 9, 16, 16)]
                    d.boxes += open ? [Box(9, 6, 0, 16, 15, 2), Box(9, 6, 14, 16, 15, 16)] : [Box(7, 6, 2, 9, 9, 14), Box(7, 12, 2, 9, 15, 14)]
                }
                d.collide = !open; d.hardness = 2; d.tool = .axe; d.sound = .wood; d.group = "\(w)_fence_gate"; d.hidden = k != 0
                d.shape = "gate"; d.skyStop = false
                add(d)
            } }
        }
        for f in 0..<4 {
            var d = BlockDef(f == 0 ? "ladder" : "ladder[\(f)]", "Ladder")
            d.tex = ["ladder"]; d.render = .model; d.layer = .cutout; d.opaque = false
            d.boxes = [BlockRegistry.panel([1, 0, 3, 2][f], t: 2)]
            d.hardness = 0.4; d.tool = .axe; d.sound = .wood; d.group = "ladder"; d.hidden = f != 0; d.shape = "ladder"; d.skyStop = false
            add(d)
        }
        for soul in [false, true] {
            for hanging in [false, true] {
                let n = soul ? "soul_lantern" : "lantern"
                var d = BlockDef(hanging ? "\(n)[hanging]" : n, soul ? "Soul Lantern" : "Lantern")
                d.tex = [soul ? "soul_lantern" : "lantern"]; d.render = .model; d.layer = .cutout; d.opaque = false
                d.boxes = hanging ? [Box(5, 1, 5, 11, 8, 11), Box(6, 8, 6, 10, 10, 10), Box(7, 10, 7, 9, 16, 9)] : [Box(5, 0, 5, 11, 7, 11), Box(6, 7, 6, 10, 9, 10)]
                d.emit = soul ? 10 : 15; d.hardness = 3.5; d.tool = .pickaxe; d.sound = .stone; d.group = n; d.hidden = hanging; d.skyStop = false
                d.shape = "lantern"
                add(d)
            }
        }
        model("bell", "Bell", ["bell"], [Box(4, 4, 4, 12, 13, 12), Box(3, 3, 3, 13, 4, 13), Box(7, 13, 7, 9, 16, 9)], h: 5, emit: 0)
        sided("hay_block", "Hay Bale", side: "hay_block_side", top: "hay_block_top", bottom: "hay_block_top", h: 0.5, tool: .hoe, snd: .plant)
        model("composter", "Composter", ["composter_side", "composter_side", "composter_top", "composter_side", "composter_side", "composter_side"],
              [Box(0, 0, 0, 16, 2, 16), Box(0, 2, 0, 2, 16, 16), Box(14, 2, 0, 16, 16, 16), Box(2, 2, 0, 14, 16, 2), Box(2, 2, 14, 14, 16, 16)], h: 0.6, tool: .axe, snd: .wood)
        sided("barrel", "Barrel", side: "barrel_side", top: "barrel_top", bottom: "barrel_bottom", tool: .axe, snd: .wood)
        sided("smoker", "Smoker", side: "smoker_front", top: "smoker_top", bottom: "smoker_top", h: 3.5, tool: .pickaxe, snd: .stone, req: true)
        sided("blast_furnace", "Blast Furnace", side: "blast_furnace_front", top: "blast_furnace_top", bottom: "blast_furnace_top", h: 3.5, tool: .pickaxe, snd: .stone, req: true)
        sided("cartography_table", "Cartography Table", side: "cartography_table_side", top: "cartography_table_top", bottom: "dark_oak_planks")
        sided("fletching_table", "Fletching Table", side: "fletching_table_side", top: "fletching_table_top", bottom: "birch_planks")
        sided("smithing_table", "Smithing Table", side: "smithing_table_side", top: "smithing_table_top", bottom: "smithing_table_top")
        sided("loom", "Loom", side: "loom_side", top: "loom_top", bottom: "oak_planks")
        model("stonecutter", "Stonecutter", ["stonecutter_side", "stonecutter_side", "stonecutter_top", "stonecutter_side", "stonecutter_side", "stonecutter_side"],
              [Box(0, 0, 0, 16, 9, 16), Box(1, 9, 7, 15, 16, 9)], h: 3.5)
        model("grindstone", "Grindstone", ["grindstone"], [Box(4, 4, 2, 12, 16, 14), Box(2, 0, 6, 4, 10, 10), Box(12, 0, 6, 14, 10, 10)], h: 2)
        model("lectern", "Lectern", ["lectern_side", "lectern_side", "lectern_top", "oak_planks", "lectern_side", "lectern_side"],
              [Box(0, 0, 0, 16, 2, 16), Box(4, 2, 4, 12, 13, 12), Box(0, 13, 0, 16, 15, 16)], h: 2.5, tool: .axe, snd: .wood)
        model("anvil", "Anvil", ["anvil"], [Box(2, 0, 2, 14, 4, 14), Box(4, 4, 3, 12, 5, 13), Box(6, 5, 4, 10, 10, 12), Box(3, 10, 0, 13, 16, 16)], h: 5, req: true)
        model("cauldron", "Cauldron", ["cauldron"], [Box(0, 3, 0, 16, 5, 16), Box(0, 5, 0, 2, 16, 16), Box(14, 5, 0, 16, 16, 16), Box(2, 5, 0, 14, 16, 2),
                                                      Box(2, 5, 14, 14, 16, 16), Box(0, 0, 0, 4, 3, 4), Box(12, 0, 0, 16, 3, 4), Box(0, 0, 12, 4, 3, 16), Box(12, 0, 12, 16, 3, 16)], h: 2, req: true)
        model("flower_pot", "Flower Pot", ["flower_pot"], [Box(5, 0, 5, 11, 6, 11)], h: 0, tool: .none)
        for (c, d) in BlockRegistry.colors {
            var carpet = BlockDef("\(c)_carpet", "\(d) Carpet")
            carpet.tex = ["\(c)_wool"]; carpet.render = .model; carpet.opaque = false; carpet.boxes = [Box(0, 0, 0, 16, 1, 16)]
            carpet.hardness = 0.1; carpet.sound = .plant; carpet.skyStop = false; carpet.flammable = true
            add(carpet)
        }
        sided("smooth_sandstone", "Smooth Sandstone", side: "sandstone_top", top: "sandstone_top", bottom: "sandstone_top", h: 2, tool: .pickaxe, snd: .stone, req: true)
        sided("cut_sandstone", "Cut Sandstone", side: "cut_sandstone", top: "sandstone_top", bottom: "sandstone_top", h: 0.8, tool: .pickaxe, snd: .stone, req: true)
        sided("chiseled_sandstone", "Chiseled Sandstone", side: "chiseled_sandstone", top: "sandstone_top", bottom: "sandstone_top", h: 0.8, tool: .pickaxe, snd: .stone, req: true)
        sided("smooth_red_sandstone", "Smooth Red Sandstone", side: "red_sandstone_top", top: "red_sandstone_top", bottom: "red_sandstone_top", h: 2, tool: .pickaxe, snd: .stone, req: true)
        sided("cut_red_sandstone", "Cut Red Sandstone", side: "cut_red_sandstone", top: "red_sandstone_top", bottom: "red_sandstone_top", h: 0.8, tool: .pickaxe, snd: .stone, req: true)
        cube("white_concrete", "White Concrete", h: 1.8, tool: .pickaxe, snd: .stone, req: true)
    }
}
