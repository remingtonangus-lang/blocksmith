import Foundation

// Block states are 16-bit IDs ("flattened" states: every variant of a block — each water level,
// each facing of a stair — gets its own ID). All per-state properties live in flat tables so
// hot loops (meshing, physics, lighting) index arrays instead of touching structs or strings.
//
// To add a block: register it in BlockRegistry.init (by name; textures by name, painted in
// Textures.swift) and, if code needs it, add a global `let NAME = Blocks.id("name")` below.

typealias BlockID = UInt16

enum RenderType: UInt8 { case none, cube, cross, liquid, model }
enum RenderLayer: UInt8 { case opaque, cutout, translucent }
enum ToolType: UInt8 { case none, pickaxe, axe, shovel, hoe, sword, shears }

// Axis-aligned box in 1/16 block units, with a texture per face (+X -X +Y -Y +Z -Z).
struct Box {
    var x0: UInt8, y0: UInt8, z0: UInt8, x1: UInt8, y1: UInt8, z1: UInt8
    var tex: [UInt16]
    init(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, tex: [UInt16] = []) {
        self.x0 = UInt8(x0); self.y0 = UInt8(y0); self.z0 = UInt8(z0)
        self.x1 = UInt8(x1); self.y1 = UInt8(y1); self.z1 = UInt8(z1)
        self.tex = tex
    }
    var minV: V3 { V3(Float(x0), Float(y0), Float(z0)) / 16 }
    var maxV: V3 { V3(Float(x1), Float(y1), Float(z1)) / 16 }
}

struct BlockDef {
    var name: String
    var display: String
    var render: RenderType = .cube
    var layer: RenderLayer = .opaque
    var tex: [String] = []           // 6 faces +X -X +Y -Y +Z -Z
    var opaque = true                // full opaque cube: hides neighbour faces, blocks light
    var skyStop: Bool? = nil         // stops the straight-down skylight column (default: !air-like)
    var emit: UInt8 = 0
    var collide = true
    var boxes: [Box] = []            // model geometry / collision for non-full blocks (1/16 units)
    var noCollideBoxes = false       // model boxes are visual only (e.g. carpets still collide; flowers don't)
    var hardness: Float = 1          // < 0 = unbreakable
    var tool: ToolType = .none
    var harvestLevel = 0             // 0 wood/gold, 1 stone, 2 iron, 3 diamond
    var requiresTool = false
    var cullSame = false
    var tint: UInt8 = 0              // 1 grass, 2 foliage, 3 grass overlay (tint only marked texels)
    var replaceable = false          // placing a block here overwrites it (air, plants, fluids, snow layer)
    var fluid: Int8 = -1             // -1 none, 0 source, 1...7 flowing, 8 falling
    var sound: SoundMat = .stone
    var aoOcc: Bool? = nil
    var hidden = false               // not offered in the creative inventory
    var group: String? = nil         // state group (defaults to name)

    init(_ name: String, _ display: String) { self.name = name; self.display = display }
}

final class TextureRegistry {
    private(set) var names: [String] = []
    private var index: [String: UInt16] = [:]
    func id(_ n: String) -> UInt16 {
        if let i = index[n] { return i }
        let i = UInt16(names.count)
        names.append(n)
        index[n] = i
        return i
    }
    var count: Int { names.count }
}

let Tex = TextureRegistry()

final class BlockRegistry {
    private(set) var defs: [BlockDef] = []
    private var byName: [String: BlockID] = [:]
    // Per-state tables
    var render: [UInt8] = []
    var layer: [UInt8] = []
    var opaque: [Bool] = []
    var sky: [Bool] = []            // stops the direct skylight column
    var lightOpaque: [Bool] = []
    var emit: [UInt8] = []
    var aoOcc: [Bool] = []
    var collide: [Bool] = []        // has any collision
    var fullCollide: [Bool] = []    // collision is the full cube
    var cullSame: [Bool] = []
    var tint: [UInt8] = []
    var replaceable: [Bool] = []
    var fluidLevel: [Int8] = []
    var hidden: [Bool] = []
    var hardness: [Float] = []
    var tool: [UInt8] = []
    var harvestLevel: [UInt8] = []
    var requiresTool: [Bool] = []
    var groupBase: [BlockID] = []   // first state of this state's group
    var tex: [UInt16] = []          // state*6 + face
    var boxes: [[Box]] = []

    var count: Int { defs.count }

    @discardableResult
    func add(_ d0: BlockDef) -> BlockID {
        var d = d0
        let id = BlockID(defs.count)
        precondition(byName[d.name] == nil, "duplicate block \(d.name)")
        byName[d.name] = id
        let g = d.group ?? d.name
        if let first = byName["#group:" + g] { groupBase.append(first) } else { byName["#group:" + g] = id; groupBase.append(id) }
        if d.tex.count == 1 { d.tex = Array(repeating: d.tex[0], count: 6) }
        if d.tex.isEmpty { d.tex = Array(repeating: "missing", count: 6) }
        defs.append(d)
        render.append(d.render.rawValue)
        layer.append(d.layer.rawValue)
        opaque.append(d.opaque)
        let airLike = d.render == .none || d.render == .cross
        sky.append(d.skyStop ?? !airLike)
        lightOpaque.append(d.opaque)
        emit.append(d.emit)
        aoOcc.append(d.aoOcc ?? (d.opaque || (d.render == .cube && d.layer == .cutout && !d.cullSame)))
        collide.append(d.collide)
        fullCollide.append(d.collide && (d.boxes.isEmpty || d.render == .cube))
        cullSame.append(d.cullSame)
        tint.append(d.tint)
        replaceable.append(d.replaceable)
        fluidLevel.append(d.fluid)
        hidden.append(d.hidden)
        hardness.append(d.hardness)
        tool.append(d.tool.rawValue)
        harvestLevel.append(UInt8(d.harvestLevel))
        requiresTool.append(d.requiresTool)
        for f in 0..<6 { tex.append(Tex.id(d.tex[f])) }
        var bx = d.boxes
        for i in 0..<bx.count where bx[i].tex.isEmpty { bx[i].tex = (0..<6).map { tex[Int(id) * 6 + $0] } }
        boxes.append(bx)
        return id
    }

    func id(_ name: String) -> BlockID {
        guard let i = byName[name] else { fatalError("unknown block \(name)") }
        return i
    }
    func has(_ name: String) -> Bool { byName[name] != nil }
    func name(_ id: BlockID) -> String { Int(id) < defs.count ? defs[Int(id)].display : "?" }
    func key(_ id: BlockID) -> String { Int(id) < defs.count ? defs[Int(id)].name : "?" }
    func def(_ id: BlockID) -> BlockDef { defs[Int(id)] }

    @inline(__always) func isPlant(_ id: BlockID) -> Bool { render[Int(id)] == RenderType.cross.rawValue }
    // Drawn as a flat sprite in the HUD rather than an isometric cube.
    func flatIcon(_ id: BlockID) -> Bool { isPlant(id) || id == Blocks.id("torch") }
    @inline(__always) func isLiquid(_ id: BlockID) -> Bool { fluidLevel[Int(id)] >= 0 }
    @inline(__always) func targetable(_ id: BlockID) -> Bool {
        let r = render[Int(id)]
        return r != RenderType.none.rawValue && r != RenderType.liquid.rawValue
    }

    // Blocks offered in the creative inventory (one per state group, visible ones).
    var placeable: [BlockID] {
        (1..<count).filter { !hidden[$0] && Int(groupBase[$0]) == $0 }.map { BlockID($0) }
    }

    // MARK: Definitions

    init() {
        func cube(_ n: String, _ disp: String, _ t: String, h: Float = 1.5, tool: ToolType = .pickaxe, lvl: Int = 0,
                  req: Bool = false, snd: SoundMat = .stone) {
            var d = BlockDef(n, disp)
            d.tex = [t]; d.hardness = h; d.tool = tool; d.harvestLevel = lvl; d.requiresTool = req; d.sound = snd
            add(d)
        }
        func column(_ n: String, _ disp: String, side: String, top: String, bottom: String? = nil, h: Float = 2,
                    tool: ToolType = .axe, snd: SoundMat = .wood) {
            var d = BlockDef(n, disp)
            let b = bottom ?? top
            d.tex = [side, side, top, b, side, side]; d.hardness = h; d.tool = tool; d.sound = snd
            add(d)
        }
        func leaves(_ n: String, _ disp: String, _ t: String, tint: UInt8) {
            var d = BlockDef(n, disp)
            d.tex = [t]; d.opaque = false; d.layer = .cutout; d.hardness = 0.2; d.tool = .hoe; d.sound = .plant; d.tint = tint
            add(d)
        }
        func plant(_ n: String, _ disp: String, _ t: String, tint: UInt8 = 0, emit: UInt8 = 0) {
            var d = BlockDef(n, disp)
            d.tex = [t]; d.render = .cross; d.layer = .cutout; d.opaque = false; d.collide = false
            d.hardness = 0; d.sound = .plant; d.replaceable = emit == 0; d.tint = tint; d.emit = emit
            add(d)
        }

        var air = BlockDef("air", "Air")
        air.render = .none; air.opaque = false; air.collide = false; air.replaceable = true; air.hidden = true; air.hardness = 0
        add(air)
        cube("stone", "Stone", "stone", h: 1.5, req: true)
        var grass = BlockDef("grass_block", "Grass Block")
        grass.tex = ["grass_block_side", "grass_block_side", "grass_block_top", "dirt", "grass_block_side", "grass_block_side"]
        grass.hardness = 0.6; grass.tool = .shovel; grass.sound = .dirt; grass.tint = 3
        add(grass)
        cube("dirt", "Dirt", "dirt", h: 0.5, tool: .shovel, snd: .dirt)
        cube("cobblestone", "Cobblestone", "cobblestone", h: 2, req: true)
        cube("oak_planks", "Oak Planks", "oak_planks", h: 2, tool: .axe, snd: .wood)
        cube("bedrock", "Bedrock", "bedrock", h: -1)
        cube("sand", "Sand", "sand", h: 0.5, tool: .shovel, snd: .sand)
        cube("gravel", "Gravel", "gravel", h: 0.6, tool: .shovel, snd: .dirt)
        column("oak_log", "Oak Log", side: "oak_log", top: "oak_log_top")
        leaves("oak_leaves", "Oak Leaves", "oak_leaves", tint: 2)
        var glass = BlockDef("glass", "Glass")
        glass.tex = ["glass"]; glass.opaque = false; glass.layer = .cutout; glass.cullSame = true
        glass.skyStop = false; glass.hardness = 0.3; glass.sound = .glass; glass.aoOcc = false
        add(glass)
        // Water: 9 states (source, flowing 1-7, falling). Only the source is placeable.
        for k in 0...8 {
            var w = BlockDef(k == 0 ? "water" : (k == 8 ? "water_falling" : "water_\(k)"), "Water")
            w.render = .liquid; w.layer = .translucent; w.tex = ["water"]; w.opaque = false; w.collide = false
            w.skyStop = true; w.replaceable = true; w.fluid = Int8(k); w.hardness = -1; w.hidden = k != 0
            w.group = "water"; w.sound = .snow
            add(w)
        }
        cube("coal_ore", "Coal Ore", "coal_ore", h: 3, req: true)
        cube("iron_ore", "Iron Ore", "iron_ore", h: 3, lvl: 1, req: true)
        cube("gold_ore", "Gold Ore", "gold_ore", h: 3, lvl: 2, req: true)
        cube("diamond_ore", "Diamond Ore", "diamond_ore", h: 3, lvl: 2, req: true)
        cube("bricks", "Bricks", "bricks", h: 2, req: true)
        var snowy = BlockDef("snowy_grass_block", "Snowy Grass Block")
        snowy.tex = ["grass_block_snow", "grass_block_snow", "snow", "dirt", "grass_block_snow", "grass_block_snow"]
        snowy.hardness = 0.6; snowy.tool = .shovel; snowy.sound = .snow; snowy.hidden = true
        add(snowy)
        var cactus = BlockDef("cactus", "Cactus")
        cactus.tex = ["cactus_side", "cactus_side", "cactus_top", "cactus_bottom", "cactus_side", "cactus_side"]
        cactus.render = .model; cactus.opaque = false; cactus.layer = .cutout; cactus.hardness = 0.4; cactus.sound = .plant
        cactus.boxes = [Box(1, 0, 1, 15, 16, 15)]
        add(cactus)
        cube("snow_block", "Snow Block", "snow", h: 0.2, tool: .shovel, snd: .snow)
        cube("stone_bricks", "Stone Bricks", "stone_bricks", h: 1.5, req: true)
        var sst = BlockDef("sandstone", "Sandstone")
        sst.tex = ["sandstone", "sandstone", "sandstone_top", "sandstone_bottom", "sandstone", "sandstone"]
        sst.hardness = 0.8; sst.tool = .pickaxe; sst.requiresTool = true
        add(sst)
        column("birch_log", "Birch Log", side: "birch_log", top: "birch_log_top")
        leaves("birch_leaves", "Birch Leaves", "birch_leaves", tint: 0)
        column("spruce_log", "Spruce Log", side: "spruce_log", top: "spruce_log_top")
        leaves("spruce_leaves", "Spruce Leaves", "spruce_leaves", tint: 0)
        plant("short_grass", "Short Grass", "short_grass", tint: 1)
        plant("poppy", "Poppy", "poppy")
        plant("dandelion", "Dandelion", "dandelion")
        plant("cornflower", "Cornflower", "cornflower")
        var torch = BlockDef("torch", "Torch")
        torch.tex = ["torch"]; torch.render = .model; torch.layer = .cutout; torch.opaque = false; torch.collide = false
        torch.emit = 14; torch.hardness = 0; torch.sound = .wood; torch.skyStop = false
        torch.boxes = [Box(7, 0, 7, 9, 10, 9, tex: [Tex.id("torch"), Tex.id("torch"), Tex.id("torch_top"), Tex.id("torch_bottom"), Tex.id("torch"), Tex.id("torch")])]
        add(torch)
        var glow = BlockDef("glowstone", "Glowstone")
        glow.tex = ["glowstone"]; glow.emit = 15; glow.hardness = 0.3; glow.sound = .glass
        add(glow)
        cube("deepslate", "Deepslate", "deepslate", h: 3, req: true)
        cube("cobbled_deepslate", "Cobbled Deepslate", "cobbled_deepslate", h: 3.5, req: true)
        cube("andesite", "Andesite", "andesite", h: 1.5, req: true)
        cube("diorite", "Diorite", "diorite", h: 1.5, req: true)
        cube("granite", "Granite", "granite", h: 1.5, req: true)
        cube("tuff", "Tuff", "tuff", h: 1.5, req: true)
        cube("clay", "Clay", "clay", h: 0.6, tool: .shovel, snd: .dirt)
        cube("obsidian", "Obsidian", "obsidian", h: 50, lvl: 3, req: true)
        cube("red_sand", "Red Sand", "red_sand", h: 0.5, tool: .shovel, snd: .sand)
        cube("terracotta", "Terracotta", "terracotta", h: 1.25, req: true)
        cube("lapis_ore", "Lapis Lazuli Ore", "lapis_ore", h: 3, lvl: 1, req: true)
        cube("redstone_ore", "Redstone Ore", "redstone_ore", h: 3, lvl: 2, req: true)
        cube("emerald_ore", "Emerald Ore", "emerald_ore", h: 3, lvl: 2, req: true)
        cube("copper_ore", "Copper Ore", "copper_ore", h: 3, lvl: 1, req: true)
        cube("deepslate_coal_ore", "Deepslate Coal Ore", "deepslate_coal_ore", h: 4.5, req: true)
        cube("deepslate_iron_ore", "Deepslate Iron Ore", "deepslate_iron_ore", h: 4.5, lvl: 1, req: true)
        cube("deepslate_gold_ore", "Deepslate Gold Ore", "deepslate_gold_ore", h: 4.5, lvl: 2, req: true)
        cube("deepslate_diamond_ore", "Deepslate Diamond Ore", "deepslate_diamond_ore", h: 4.5, lvl: 2, req: true)
        cube("deepslate_lapis_ore", "Deepslate Lapis Lazuli Ore", "deepslate_lapis_ore", h: 4.5, lvl: 1, req: true)
        cube("deepslate_redstone_ore", "Deepslate Redstone Ore", "deepslate_redstone_ore", h: 4.5, lvl: 2, req: true)
        cube("deepslate_copper_ore", "Deepslate Copper Ore", "deepslate_copper_ore", h: 4.5, lvl: 1, req: true)
        cube("mossy_cobblestone", "Mossy Cobblestone", "mossy_cobblestone", h: 2, req: true)
        cube("smooth_stone", "Smooth Stone", "smooth_stone", h: 2, req: true)
        column("oak_wood", "Oak Wood", side: "oak_log", top: "oak_log")
        cube("birch_planks", "Birch Planks", "birch_planks", h: 2, tool: .axe, snd: .wood)
        cube("spruce_planks", "Spruce Planks", "spruce_planks", h: 2, tool: .axe, snd: .wood)
        var slab = BlockDef("stone_slab", "Stone Slab")
        slab.tex = ["smooth_stone"]; slab.render = .model; slab.opaque = false; slab.hardness = 2; slab.tool = .pickaxe
        slab.requiresTool = true; slab.boxes = [Box(0, 0, 0, 16, 8, 16)]; slab.skyStop = true
        add(slab)
        var oslab = BlockDef("oak_slab", "Oak Slab")
        oslab.tex = ["oak_planks"]; oslab.render = .model; oslab.opaque = false; oslab.hardness = 2; oslab.tool = .axe
        oslab.sound = .wood; oslab.boxes = [Box(0, 0, 0, 16, 8, 16)]; oslab.skyStop = true
        add(oslab)
    }
}

let Blocks = BlockRegistry()

// Frequently used states (resolved once, lazily, by name).
let AIR: BlockID = 0
let STONE = Blocks.id("stone")
let GRASS = Blocks.id("grass_block")
let DIRT = Blocks.id("dirt")
let COBBLE = Blocks.id("cobblestone")
let PLANKS = Blocks.id("oak_planks")
let BEDROCK = Blocks.id("bedrock")
let SAND = Blocks.id("sand")
let GRAVEL = Blocks.id("gravel")
let LOG = Blocks.id("oak_log")
let LEAVES = Blocks.id("oak_leaves")
let GLASS = Blocks.id("glass")
let WATER = Blocks.id("water")
let WATER_FLOW: [BlockID] = [WATER] + (1...7).map { Blocks.id("water_\($0)") }
let WATER_FALL = Blocks.id("water_falling")
let COAL_ORE = Blocks.id("coal_ore")
let IRON_ORE = Blocks.id("iron_ore")
let GOLD_ORE = Blocks.id("gold_ore")
let DIAMOND_ORE = Blocks.id("diamond_ore")
let BRICKS = Blocks.id("bricks")
let SNOWY_GRASS = Blocks.id("snowy_grass_block")
let CACTUS = Blocks.id("cactus")
let SNOW = Blocks.id("snow_block")
let STONE_BRICKS = Blocks.id("stone_bricks")
let SANDSTONE = Blocks.id("sandstone")
let BIRCH_LOG = Blocks.id("birch_log")
let BIRCH_LEAVES = Blocks.id("birch_leaves")
let SPRUCE_LOG = Blocks.id("spruce_log")
let SPRUCE_LEAVES = Blocks.id("spruce_leaves")
let TALL_GRASS = Blocks.id("short_grass")
let RED_FLOWER = Blocks.id("poppy")
let YELLOW_FLOWER = Blocks.id("dandelion")
let BLUE_FLOWER = Blocks.id("cornflower")
let TORCH = Blocks.id("torch")
let LAMP = Blocks.id("glowstone")
let DEEPSLATE = Blocks.id("deepslate")
