import Foundation

// Block states are 16-bit IDs ("flattened" states: every variant of a block — each water level,
// each facing of a stair — gets its own ID). All per-state properties live in flat tables so
// hot loops (meshing, physics, lighting) index arrays instead of touching structs or strings.
//
// To add a block: register it in BlockRegistry.init (by name; textures by name, painted in
// Textures.swift) and, if code needs it, add a global `let NAME = Blocks.id("name")` below.

typealias BlockID = UInt16

enum RenderType: UInt8 { case none, cube, cross, liquid, model, connect, wire, rail }   // connect: fences/panes/walls; wire: sparkstone dust
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
    var resistance: Float? = nil     // blast resistance (default: hardness)
    var flammable = false
    var randomTicks = false          // receives random ticks (crops, saplings, grass...)
    var tool: ToolType = .none
    var harvestLevel = 0             // 0 wood/gold, 1 stone, 2 iron, 3 diamond
    var requiresTool = false
    var cullSame = false
    var tint: UInt8 = 0              // 1 grass, 2 foliage, 3 grass overlay (tint only marked texels)
    var replaceable = false          // placing a block here overwrites it (air, plants, fluids, snow layer)
    var fluid: Int8 = -1             // -1 none, 0 source, 1...7 flowing, 8 falling
    var fluidKind: UInt8 = 0         // 1 water, 2 lava
    var damage: UInt8 = 0            // contact damage per second (cactus, magma, fire, lava)
    var connect: UInt8 = 0           // 1 fence, 2 pane/bars, 3 wall (render .connect)
    var shape: String = ""           // "stairs", "slab" (placement rules)
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
    var untextured: [String] = []   // visible blocks registered without textures (drawn with "missing")
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
    var fluidKind: [UInt8] = []
    var contactDamage: [UInt8] = []
    var connectKind: [UInt8] = []
    var shape: [String] = []
    var hidden: [Bool] = []
    var hardness: [Float] = []
    var resistance: [Float] = []
    // Flammable in the reference though neither wooden-sounding, leaves nor a plant (World.fireOdds gives their odds).
    static let extraFlammable: Set<String> = ["hay_block", "dried_kelp_block", "scaffolding", "target", "coal_block", "composter", "beehive", "bee_nest"]
    // Blast resistance where it differs from hardness (the reference keeps them apart: stone 1.5 hard but 6 against
    // blasts, planks 2 / 3, end stone 3 / 9). Before this every block used its hardness, so a creeper cratered
    // stone, brick and deepslate builds about four times deeper than it should.
    static func refResistance(_ d: BlockDef) -> Float? {
        let n = d.name
        if n.contains("infested") { return nil }
        if n.hasSuffix("_ore") { return 3 }
        if n.contains("end_stone") { return 9 }
        if n == "reinforced_deepslate" || n == "netherite_block" || n == "ancient_debris" || n.contains("anvil")
            || n == "enchanting_table" || n == "respawn_anchor" { return 1200 }
        if n == "ender_chest" { return 600 }
        if n == "obsidian" { return 1200 }
        if n.hasSuffix("_block") && ["coal", "iron", "gold", "diamond", "emerald", "redstone"].contains(where: { n.hasPrefix($0) }) { return 6 }
        if n.contains("copper") && d.hardness >= 3 { return 6 }
        if n == "iron_bars" || n == "jukebox" { return 6 }
        if n.contains("mud_brick") { return 3 }
        if n.contains("basalt") || (n.contains("terracotta") && !n.contains("glazed")) { return 4.2 }
        if d.tool == .axe && ["planks", "_stairs", "_slab", "_fence", "_fence_gate"].contains(where: { n.hasSuffix($0) }) { return 3 }
        if d.tool == .pickaxe && !n.contains("sandstone") && !n.contains("glowstone") && !n.contains("redstone")
            && !n.hasSuffix("_button") && !n.hasSuffix("pressure_plate") && !n.contains("dripstone") && !n.contains("stonecutter")
            && ["stone", "cobble", "brick", "andesite", "diorite", "granite", "deepslate", "purpur", "prismarine", "tuff"].contains(where: { n.contains($0) }) {
            return max(6, d.hardness)              // never weaker than a hardened original block
        }
        return nil
    }
    var flammable: [Bool] = []
    var randomTicks: [Bool] = []
    var tool: [UInt8] = []
    var harvestLevel: [UInt8] = []
    var requiresTool: [Bool] = []
    var groupBase: [BlockID] = []   // first state of this state's group
    // Waterlogging (reference block-state property): a waterloggable state has a twin holding a water source. The
    // twin keeps the dry state's name (key(), so every key and shape test treats it alike) and the same state order
    // in a group of its own (so `b - groupBase[b]` arithmetic holds); it registers and saves as "<name>~wl".
    var dry: [BlockID] = []         // the dry state of a twin (itself otherwise)
    var wet: [BlockID] = []         // the twin of a waterloggable dry state (AIR when none)
    var wetInvalid: [Bool] = []     // a twin of a full-cube state (double slab): stored dry
    private(set) var saveNames: [String] = []
    var tex: [UInt16] = []          // state*6 + face
    var boxes: [[Box]] = []
    var collBoxes: [[Box]] = []      // collision shape per state (render boxes unless collisionShape overrides)

    var count: Int { defs.count }

    // Reference collision shapes where the model's decorative parts would otherwise form a staircase the 0.6
    // step-up climbs (collisiontest walk_through: dragon egg layers, brewing stand bottles, lantern chains, the
    // bell's rim, the stonecutter blade).
    static func collisionShape(_ d: BlockDef) -> [Box]? {
        if d.shape == "lantern" && d.name.hasSuffix("[hanging]") { return Array(d.boxes.prefix(2)) }
        let g = d.group ?? String(d.name.split(separator: "[").first ?? "")
        // Statues and ship fittings: one box around the whole model.
        if (g.hasSuffix("copper_golem_statue") || g == "ship_helm" || g == "ship_cannon"), let f = d.boxes.first {
            var b = Box(Int(f.x0), Int(f.y0), Int(f.z0), Int(f.x1), Int(f.y1), Int(f.z1))
            for x in d.boxes {
                b.x0 = min(b.x0, x.x0); b.y0 = min(b.y0, x.y0); b.z0 = min(b.z0, x.z0)
                b.x1 = max(b.x1, x.x1); b.y1 = max(b.y1, x.y1); b.z1 = max(b.z1, x.z1)
            }
            return [b]
        }
        switch g {
        case "sculk_sensor", "calibrated_sculk_sensor": return [Box(0, 0, 0, 16, 8, 16)]
        case "campfire", "soul_campfire": return [Box(0, 0, 0, 16, 7, 16)]
        case "dragon_egg": return [Box(1, 0, 1, 15, 16, 15)]
        case "brewing_stand": return [Box(1, 0, 1, 15, 2, 15), Box(7, 0, 7, 9, 14, 9)]
        case "stonecutter": return [Box(0, 0, 0, 16, 9, 16)]
        case "bell": return [Box(4, 3, 4, 12, 13, 12), Box(7, 13, 7, 9, 16, 9)]
        // Solid for walking: the hollow tub trapped anything that stepped in (village bot, seed 424242; farmers work at
        // composters) and path finding already treated it as a full block.
        case "composter": return [Box(0, 0, 0, 16, 16, 16)]
        default: return nil
        }
    }

    @discardableResult
    func add(_ d0: BlockDef, as regName: String? = nil, groupKey: String? = nil) -> BlockID {
        let rn = regName ?? d0.name
        if byName[rn] != nil { print("warning: duplicate block \(rn)") }
        var d = d0
        let id = BlockID(defs.count)
        precondition(byName[rn] == nil, "duplicate block \(rn)")
        byName[rn] = id
        saveNames.append(rn)
        dry.append(id)
        wet.append(AIR)
        wetInvalid.append(false)
        let g = groupKey ?? d.group ?? d.name
        if let first = byName["#group:" + g] { groupBase.append(first) } else { byName["#group:" + g] = id; groupBase.append(id) }
        if d.tex.count == 1 { d.tex = Array(repeating: d.tex[0], count: 6) }
        if d.tex.isEmpty {
            d.tex = Array(repeating: "missing", count: 6)
            if d.render != .none { untextured.append(d.name) }
        }
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
        fullCollide.append(d.collide && (d.render == .cube || (d.render != .model && d.render != .connect && d.boxes.isEmpty)))
        cullSame.append(d.cullSame)
        tint.append(d.tint)
        replaceable.append(d.replaceable)
        fluidLevel.append(d.fluid)
        fluidKind.append(d.fluid >= 0 ? (d.fluidKind == 0 ? 1 : d.fluidKind) : 0)
        contactDamage.append(d.damage)
        connectKind.append(d.connect)
        shape.append(d.shape)
        hidden.append(d.hidden)
        hardness.append(d.hardness)
        resistance.append(d.resistance ?? (d.hardness < 0 ? 3_600_000 : (BlockRegistry.refResistance(d) ?? d.hardness)))
        let n = d.name
        let naturallyFlammable = (d.sound == .wood && !n.hasPrefix("crimson") && !n.hasPrefix("warped") && n != "torch" && d.render != .model)
            || n.hasSuffix("leaves") || (d.render == .cross && n != "fire" && n != "soul_fire" && !n.hasPrefix("crimson") && !n.hasPrefix("warped"))
        flammable.append(d.flammable || naturallyFlammable || BlockRegistry.extraFlammable.contains(d.group ?? n))
        randomTicks.append(d.randomTicks)
        tool.append(d.tool.rawValue)
        harvestLevel.append(UInt8(d.harvestLevel))
        requiresTool.append(d.requiresTool)
        for f in 0..<6 { tex.append(Tex.id(d.tex[f])) }
        var bx = d.boxes
        for i in 0..<bx.count where bx[i].tex.isEmpty { bx[i].tex = (0..<6).map { tex[Int(id) * 6 + $0] } }
        boxes.append(bx)
        collBoxes.append(BlockRegistry.collisionShape(d) ?? d.boxes)
        return id
    }

    static let colors: [(String, String)] = [
        ("white", "White"), ("orange", "Orange"), ("magenta", "Magenta"), ("light_blue", "Light Blue"),
        ("yellow", "Yellow"), ("lime", "Lime"), ("pink", "Pink"), ("gray", "Gray"), ("light_gray", "Light Gray"),
        ("cyan", "Cyan"), ("purple", "Purple"), ("blue", "Blue"), ("brown", "Brown"), ("green", "Green"),
        ("red", "Red"), ("black", "Black"),
    ]
    static let colorHex: [String: UInt32] = [
        "white": 0xE9ECEC, "orange": 0xF07613, "magenta": 0xBD44B3, "light_blue": 0x3AAFD9, "yellow": 0xF8C627,
        "lime": 0x70B919, "pink": 0xED8DAC, "gray": 0x3E4447, "light_gray": 0x8E8E86, "cyan": 0x158991,
        "purple": 0x792AAC, "blue": 0x35399D, "brown": 0x724728, "green": 0x546D1B, "red": 0xA12722, "black": 0x141519,
    ]

    // Registers 4 horizontal-facing states (north, south, west, east = front on -Z, +Z, -X, +X).
    // `d.tex` gives side textures; `front` replaces the facing face. Returns the first state.
    @discardableResult
    func addFacing(_ d: BlockDef, front: String, boxes: [Box] = [], boxesFor: ((Int) -> [Box])? = nil) -> BlockID {
        var first: BlockID = 0
        let faceFor = [5, 4, 1, 0]
        for (k, dir) in ["north", "south", "west", "east"].enumerated() {
            var s = d
            s.name = k == 0 ? d.name : "\(d.name)[\(dir)]"
            s.group = d.name
            if s.tex.count == 1 { s.tex = Array(repeating: s.tex[0], count: 6) }
            s.tex[faceFor[k]] = front
            s.hidden = d.hidden || k != 0
            s.boxes = boxesFor?(k) ?? boxes.map { var b = $0; b.tex = []; return b }
            let id = add(s)
            if k == 0 { first = id }
        }
        return first
    }

    // Facing index (0 north, 1 south, 2 west, 3 east) so the front looks at a viewer with this yaw.
    static func facingToward(yaw: Float) -> Int {
        let lx = -sinf(yaw), lz = -cosf(yaw)   // look direction
        if abs(lx) > abs(lz) { return lx > 0 ? 2 : 3 }   // looking +X -> front faces -X (west)
        return lz > 0 ? 0 : 1                             // looking +Z -> front faces -Z (north)
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
    func flatIcon(_ id: BlockID) -> Bool { isPlant(id) || shape[Int(id)] == "torch" }
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
            pillar(n, disp, side: side, top: top, bottom: bottom, h: h, tool: tool, snd: snd, req: tool == .pickaxe)   // stone pillars need a pickaxe
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
        grass.hardness = 0.6; grass.tool = .shovel; grass.sound = .dirt; grass.tint = 3; grass.randomTicks = true
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
            w.group = "water"; w.sound = .snow; w.fluidKind = 1
            add(w)
        }
        cube("coal_ore", "Coal Ore", "coal_ore", h: 3, req: true)
        cube("iron_ore", "Iron Ore", "iron_ore", h: 3, lvl: 1, req: true)
        cube("gold_ore", "Gold Ore", "gold_ore", h: 3, lvl: 2, req: true)
        cube("diamond_ore", "Titanium Ore", "diamond_ore", h: 3, lvl: 2, req: true)
        cube("bricks", "Bricks", "bricks", h: 2, req: true)
        var snowy = BlockDef("snowy_grass_block", "Snowy Grass Block")
        snowy.tex = ["grass_block_snow", "grass_block_snow", "snow", "dirt", "grass_block_snow", "grass_block_snow"]
        snowy.hardness = 0.6; snowy.tool = .shovel; snowy.sound = .snow; snowy.hidden = true
        add(snowy)
        var cactus = BlockDef("cactus", "Cactus")
        cactus.tex = ["cactus_side", "cactus_side", "cactus_top", "cactus_bottom", "cactus_side", "cactus_side"]
        cactus.render = .model; cactus.opaque = false; cactus.layer = .cutout; cactus.hardness = 0.4; cactus.sound = .plant
        cactus.boxes = [Box(1, 0, 1, 15, 16, 15)]; cactus.randomTicks = true
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
        // Torches: standing (0) and on walls (1+f, f = the side the torch faces), soul torches the same.
        for kind in 0..<3 {
            let soul = kind == 1, copper = kind == 2                          // torch, ghost torch, copper torch (green flame)
            let n = ["torch", "soul_torch", "copper_torch"][kind]
            for st in 0..<5 {
                var torch = BlockDef(st == 0 ? n : "\(n)[\(st)]", ["Torch", "Ghost Torch", "Copper Torch"][kind])
                torch.group = n; torch.hidden = st != 0; torch.shape = "torch"
                torch.tex = [n]; torch.render = .model; torch.layer = .cutout; torch.opaque = false; torch.collide = false
                torch.emit = soul ? 10 : 14; torch.hardness = 0; torch.sound = .wood; torch.skyStop = false
                if st == 0 {
                    let topTex = Tex.id(copper ? "copper_torch_top" : "torch_top")
                    torch.boxes = [Box(7, 0, 7, 9, 10, 9, tex: [Tex.id(n), Tex.id(n), topTex, Tex.id("torch_bottom"), Tex.id(n), Tex.id(n)])]
                } else {
                    let w = Tex.id(n + "_wall"), top = Tex.id(n + "_top_full"), bot = Tex.id("torch_bottom")
                    // Leaning against the wall: the foot sits against it, the head steps out 1 px per third
                    // (boxes are whole 1/16 units, so the tilt is stepped).
                    let base = [Box(7, 3, 12, 9, 13, 14), Box(7, 3, 2, 9, 13, 4), Box(12, 3, 7, 14, 13, 9), Box(2, 3, 7, 4, 13, 9)][st - 1]
                    let out: (Int, Int) = [(0, -1), (0, 1), (-1, 0), (1, 0)][st - 1]       // away from the wall
                    var parts: [Box] = []
                    for (k, (y0, y1)) in [(3, 6), (6, 10), (10, 13)].enumerated() {
                        let sx = out.0 * (k - 1), sz = out.1 * (k - 1)
                        parts.append(Box(Int(base.x0) + sx, y0, Int(base.z0) + sz, Int(base.x1) + sx, y1, Int(base.z1) + sz,
                                         tex: [w, w, k == 2 ? top : w, k == 0 ? bot : w, w, w]))
                    }
                    torch.boxes = parts
                }
                add(torch)
            }
        }
        var glow = BlockDef("glowstone", "Lumenstone")
        glow.tex = ["glowstone"]; glow.emit = 15; glow.hardness = 0.3; glow.sound = .glass
        add(glow)
        var sap = BlockDef("oak_sapling", "Oak Sapling")
        for (n, d) in [("oak_sapling", "Oak Sapling"), ("birch_sapling", "Birch Sapling"), ("spruce_sapling", "Spruce Sapling")] {
            sap = BlockDef(n, d)
            sap.tex = [n]; sap.render = .cross; sap.layer = .cutout; sap.opaque = false; sap.collide = false
            sap.hardness = 0; sap.sound = .plant
            add(sap)
        }
        cube("deepslate", "Deeprock", "deepslate", h: 3, req: true)
        // Hot rock of the world's depths: below displayed y -24 it creeps into the deeprock; the Deep is made of it.
        cube("emberslate", "Emberslate", "emberslate", h: 3.5, req: true)
        // Lava: 9 states like water; opaque, bright, hurts.
        for k in 0...8 {
            var l = BlockDef(k == 0 ? "lava" : (k == 8 ? "lava_falling" : "lava_\(k)"), "Lava")
            l.render = .liquid; l.layer = .opaque; l.tex = ["lava"]; l.opaque = false; l.collide = false
            l.skyStop = true; l.replaceable = true; l.fluid = Int8(k); l.fluidKind = 2; l.hardness = -1
            l.hidden = k != 0; l.group = "lava"; l.emit = 15; l.damage = 4; l.sound = .stone
            add(l)
        }
        var fire = BlockDef("fire", "Fire")
        fire.tex = ["fire"]; fire.render = .cross; fire.layer = .cutout; fire.opaque = false; fire.collide = false
        fire.emit = 15; fire.hardness = 0; fire.replaceable = true; fire.randomTicks = true; fire.hidden = true; fire.damage = 1
        add(fire)
        var soulFire = fire
        soulFire.name = "soul_fire"; soulFire.display = "Ghost Fire"; soulFire.tex = ["soul_fire"]; soulFire.emit = 10; soulFire.damage = 2
        add(soulFire)
        // Emberdeep portal (x-axis and z-axis sheets).
        for (n, bx) in [("nether_portal", Box(0, 0, 6, 16, 16, 10)), ("nether_portal_z", Box(6, 0, 0, 10, 16, 16))] {
            var p = BlockDef(n, "Ember Gate")
            p.tex = ["nether_portal"]; p.render = .model; p.layer = .translucent; p.opaque = false; p.collide = false
            p.boxes = [bx]; p.emit = 11; p.hardness = -1; p.hidden = true; p.group = "nether_portal"; p.skyStop = false
            add(p)
        }
        cube("netherrack", "Cinderstone", "netherrack", h: 0.4, req: true)
        cube("nether_quartz_ore", "Ember Quartz Ore", "nether_quartz_ore", h: 3, req: true)
        cube("nether_gold_ore", "Ember Gold Ore", "nether_gold_ore", h: 3, req: true)
        var ad = BlockDef("ancient_debris", "Dusk Relic")
        ad.tex = ["ancient_debris_side", "ancient_debris_side", "ancient_debris_top", "ancient_debris_top", "ancient_debris_side", "ancient_debris_side"]
        ad.hardness = 30; ad.resistance = 1200; ad.tool = .pickaxe; ad.harvestLevel = 3; ad.requiresTool = true
        add(ad)
        var ss = BlockDef("soul_sand", "Ghost Sand")
        ss.tex = ["soul_sand"]; ss.render = .model; ss.opaque = false; ss.boxes = [Box(0, 0, 0, 16, 14, 16)]
        ss.hardness = 0.5; ss.tool = .shovel; ss.sound = .sand; ss.skyStop = true
        add(ss)
        cube("soul_soil", "Ghost Soil", "soul_soil", h: 0.5, tool: .shovel, snd: .sand)
        column("basalt", "Basalt", side: "basalt_side", top: "basalt_top", h: 1.25, tool: .pickaxe, snd: .stone)
        cube("blackstone", "Onyxstone", "blackstone", h: 1.5, req: true)
        cube("polished_blackstone", "Polished Onyxstone", "polished_blackstone", h: 2, req: true)
        cube("polished_blackstone_bricks", "Polished Onyxstone Bricks", "polished_blackstone_bricks", h: 1.5, req: true)
        cube("cracked_polished_blackstone_bricks", "Cracked Polished Onyxstone Bricks", "cracked_polished_blackstone_bricks", h: 1.5, req: true)
        cube("chiseled_polished_blackstone", "Chiseled Polished Onyxstone", "chiseled_polished_blackstone", h: 1.5, req: true)
        cube("gilded_blackstone", "Gilded Onyxstone", "gilded_blackstone", h: 1.5, req: true)
        var magma = BlockDef("magma_block", "Magma Block")
        magma.tex = ["magma"]; magma.emit = 3; magma.hardness = 0.5; magma.tool = .pickaxe; magma.requiresTool = true; magma.damage = 1
        add(magma)
        cube("nether_bricks", "Ember Bricks", "nether_bricks", h: 2, req: true)
        cube("red_nether_bricks", "Red Ember Bricks", "red_nether_bricks", h: 2, req: true)
        var cn = BlockDef("crimson_nylium", "Rustcap Fungal Turf")
        cn.tex = ["crimson_nylium_side", "crimson_nylium_side", "crimson_nylium", "netherrack", "crimson_nylium_side", "crimson_nylium_side"]
        cn.hardness = 0.4; cn.tool = .pickaxe; cn.requiresTool = true
        add(cn)
        var wn = cn
        wn.name = "warped_nylium"; wn.display = "Tealcap Fungal Turf"
        wn.tex = ["warped_nylium_side", "warped_nylium_side", "warped_nylium", "netherrack", "warped_nylium_side", "warped_nylium_side"]
        add(wn)
        column("crimson_stem", "Rustcap Stem", side: "crimson_stem", top: "crimson_stem_top")
        column("warped_stem", "Tealcap Stem", side: "warped_stem", top: "warped_stem_top")
        cube("nether_wart_block", "Ember Wart Block", "nether_wart_block", h: 1, tool: .hoe, snd: .plant)
        cube("warped_wart_block", "Tealcap Wart Block", "warped_wart_block", h: 1, tool: .hoe, snd: .plant)
        var shroom = BlockDef("shroomlight", "Fungal Lamp")
        shroom.tex = ["shroomlight"]; shroom.emit = 15; shroom.hardness = 1; shroom.tool = .hoe; shroom.sound = .plant
        add(shroom)
        plant("crimson_fungus", "Rustcap Fungus", "crimson_fungus")
        plant("warped_fungus", "Tealcap Fungus", "warped_fungus")
        plant("crimson_roots", "Rustcap Roots", "crimson_roots")
        plant("warped_roots", "Tealcap Roots", "warped_roots")
        plant("weeping_vines", "Weeping Vines", "weeping_vines")
        plant("twisting_vines", "Twisting Vines", "twisting_vines")
        cube("crimson_planks", "Rustcap Planks", "crimson_planks", h: 2, tool: .axe, snd: .wood)
        cube("warped_planks", "Tealcap Planks", "warped_planks", h: 2, tool: .axe, snd: .wood)
        var co = BlockDef("crying_obsidian", "Weeping Obsidian")
        co.tex = ["crying_obsidian"]; co.emit = 10; co.hardness = 50; co.resistance = 1200; co.tool = .pickaxe; co.harvestLevel = 3; co.requiresTool = true
        add(co)
        // Emberdeep wart (4 stages, grows on ghost sand).
        for st in 0..<4 {
            var c = BlockDef(st == 0 ? "nether_wart" : "nether_wart_\(st)", "Ember Wart")
            c.tex = ["nether_wart_stage\(min(2, st == 3 ? 2 : (st == 0 ? 0 : 1)))"]; c.render = .model; c.layer = .cutout; c.opaque = false; c.collide = false
            c.boxes = [Box(4, 0, 0, 4, 16, 16), Box(12, 0, 0, 12, 16, 16), Box(0, 0, 4, 16, 16, 4), Box(0, 0, 12, 16, 16, 12)]
            c.hardness = 0; c.sound = .plant; c.skyStop = false; c.group = "nether_wart"; c.hidden = true; c.randomTicks = true
            add(c)
        }
        cube("end_stone", "Hollow Stone", "end_stone", h: 3, req: true)
        cube("end_stone_bricks", "Hollow Stone Bricks", "end_stone_bricks", h: 3, req: true)
        cube("purpur_block", "Violite Block", "purpur_block", h: 1.5, req: true)
        column("purpur_pillar", "Violite Pillar", side: "purpur_pillar", top: "purpur_pillar_top", h: 1.5, tool: .pickaxe, snd: .stone)
        cube("mossy_stone_bricks", "Mossy Stone Bricks", "mossy_stone_bricks", h: 1.5, req: true)
        cube("cracked_stone_bricks", "Cracked Stone Bricks", "cracked_stone_bricks", h: 1.5, req: true)
        cube("chiseled_stone_bricks", "Chiseled Stone Bricks", "chiseled_stone_bricks", h: 1.5, req: true)
        var infested = BlockDef("infested_stone_bricks", "Infested Stone Bricks")
        infested.tex = ["stone_bricks"]; infested.hardness = 0.75; infested.sound = .stone
        add(infested)
        var shelf = BlockDef("bookshelf", "Bookshelf")
        shelf.tex = ["bookshelf", "bookshelf", "oak_planks", "oak_planks", "bookshelf", "bookshelf"]; shelf.hardness = 1.5
        shelf.tool = .axe; shelf.sound = .wood; shelf.flammable = true
        add(shelf)
        var web = BlockDef("cobweb", "Cobweb")
        web.tex = ["cobweb"]; web.render = .cross; web.layer = .cutout; web.opaque = false; web.collide = false
        web.hardness = 4; web.tool = .sword; web.requiresTool = true; web.skyStop = false
        add(web)
        var cane = BlockDef("sugar_cane", "Sugar Cane")
        cane.tex = ["sugar_cane"]; cane.render = .cross; cane.layer = .cutout; cane.opaque = false; cane.collide = false
        cane.hardness = 0; cane.sound = .plant; cane.tint = 1; cane.randomTicks = true; cane.skyStop = false
        add(cane)
        // End portal frame: empty and with an seeker eye; unbreakable.
        for eye in [false, true] {
            var f = BlockDef(eye ? "end_portal_frame[eye]" : "end_portal_frame", "Hollow Gate Frame")
            f.tex = ["end_portal_frame_side", "end_portal_frame_side", "end_portal_frame_top", "end_stone", "end_portal_frame_side", "end_portal_frame_side"]
            f.render = .model; f.opaque = false; f.hardness = -1; f.emit = 1; f.group = "end_portal_frame"; f.hidden = eye
            f.boxes = [Box(0, 0, 0, 16, 13, 16)]
            if eye { f.boxes.append(Box(4, 13, 4, 12, 16, 12, tex: Array(repeating: Tex.id("end_portal_frame_eye"), count: 6))) }
            f.skyStop = true
            add(f)
        }
        var ep = BlockDef("end_portal", "Hollow Gate")
        ep.tex = ["end_portal"]; ep.render = .model; ep.opaque = false; ep.collide = false; ep.hardness = -1; ep.emit = 15
        ep.boxes = [Box(0, 11, 0, 16, 12, 16)]; ep.hidden = true; ep.skyStop = false
        add(ep)
        var gw = BlockDef("end_gateway", "Hollow Rift")
        gw.tex = ["end_portal"]; gw.opaque = false; gw.collide = false; gw.hardness = -1; gw.emit = 15; gw.hidden = true
        add(gw)
        var egg = BlockDef("dragon_egg", "Wyrm Egg")
        egg.tex = ["dragon_egg"]; egg.render = .model; egg.opaque = false; egg.hardness = 3; egg.emit = 1
        egg.boxes = [Box(6, 15, 6, 10, 16, 10), Box(5, 14, 5, 11, 15, 11), Box(4, 13, 4, 12, 14, 12), Box(3, 11, 3, 13, 13, 13),
                     Box(2, 8, 2, 14, 11, 14), Box(1, 3, 1, 15, 8, 15), Box(2, 1, 2, 14, 3, 14), Box(3, 0, 3, 13, 1, 13)]
        add(egg)
        var chorusP = BlockDef("chorus_plant", "Spiral Plant")
        chorusP.tex = ["chorus_plant"]; chorusP.render = .model; chorusP.opaque = false; chorusP.hardness = 0.4
        chorusP.tool = .axe; chorusP.sound = .wood; chorusP.boxes = [Box(3, 0, 3, 13, 16, 13)]; chorusP.skyStop = false
        add(chorusP)
        var chorusF = BlockDef("chorus_flower", "Spiral Flower")
        chorusF.tex = ["chorus_flower"]; chorusF.render = .model; chorusF.opaque = false; chorusF.hardness = 0.4
        chorusF.tool = .axe; chorusF.sound = .wood; chorusF.boxes = [Box(1, 0, 1, 15, 14, 15)]; chorusF.skyStop = false
        add(chorusF)
        var rod = BlockDef("end_rod", "Glow Rod")
        rod.tex = ["end_rod"]; rod.render = .model; rod.opaque = false; rod.hardness = 0; rod.emit = 14; rod.layer = .cutout
        rod.boxes = [Box(7, 1, 7, 9, 16, 9), Box(6, 0, 6, 10, 1, 10)]; rod.skyStop = false
        add(rod)
        // Hardness per the reference (gold, lapis and copper are softer: 3); blast resistance from refResistance.
        for (n, d, lvl, h) in [("coal_block", "Block of Coal", 0, 5), ("iron_block", "Block of Iron", 1, 5), ("gold_block", "Block of Gold", 2, 3),
                               ("diamond_block", "Block of Titanium", 2, 5), ("emerald_block", "Block of Emerald", 2, 5),
                               ("lapis_block", "Block of Lapis Lazuli", 1, 3), ("redstone_block", "Copper Battery", 0, 5),
                               ("copper_block", "Block of Copper", 1, 3)] as [(String, String, Int, Float)] {
            cube(n, d, n, h: h, lvl: lvl, req: true, snd: .stone)
        }
        // Farming
        var farm = BlockDef("farmland", "Farmland")
        farm.tex = ["dirt", "dirt", "farmland", "dirt", "dirt", "dirt"]; farm.render = .model; farm.opaque = false
        farm.boxes = [Box(0, 0, 0, 16, 15, 16)]; farm.hardness = 0.6; farm.tool = .shovel; farm.sound = .dirt
        farm.skyStop = true; farm.randomTicks = true; farm.hidden = true
        add(farm)
        var farmWet = farm
        farmWet.name = "farmland_moist"; farmWet.group = "farmland"; farmWet.tex = ["dirt", "dirt", "farmland_moist", "dirt", "dirt", "dirt"]
        add(farmWet)
        func crop(_ n: String, _ disp: String, stages: Int, texStages: [Int]) {
            for st in 0..<stages {
                var c = BlockDef(st == 0 ? n : "\(n)_\(st)", disp)
                let t = "\(n)_stage\(texStages[st])"
                c.tex = [t]; c.render = .model; c.layer = .cutout; c.opaque = false; c.collide = false
                c.boxes = [Box(4, 0, 0, 4, 16, 16), Box(12, 0, 0, 12, 16, 16), Box(0, 0, 4, 16, 16, 4), Box(0, 0, 12, 16, 16, 12)]
                c.hardness = 0; c.sound = .plant; c.skyStop = false; c.group = n; c.hidden = true; c.randomTicks = true
                add(c)
            }
        }
        crop("wheat", "Wheat Crops", stages: 8, texStages: [0, 1, 2, 3, 4, 5, 6, 7])
        crop("carrots", "Carrots", stages: 8, texStages: [0, 0, 1, 1, 2, 2, 2, 3])
        crop("potatoes", "Potatoes", stages: 8, texStages: [0, 0, 1, 1, 2, 2, 2, 3])
        crop("beetroots", "Beetroots", stages: 4, texStages: [0, 1, 2, 3])
        // Wool (16 colours)
        for (n, d) in BlockRegistry.colors {
            var w = BlockDef("\(n)_wool", "\(d) Wool")
            w.tex = ["\(n)_wool"]; w.hardness = 0.8; w.tool = .shears; w.sound = .plant; w.flammable = true
            add(w)
        }
        // TNT
        var tnt = BlockDef("tnt", "TNT")
        tnt.tex = ["tnt_side", "tnt_side", "tnt_top", "tnt_bottom", "tnt_side", "tnt_side"]; tnt.hardness = 0; tnt.sound = .plant
        tnt.flammable = true; tnt.resistance = 0
        add(tnt)
        // Beds: foot + head parts, 4 facings each (facing = direction from foot to head).
        for (n, d) in BlockRegistry.colors {
            for part in ["foot", "head"] {
                var b = BlockDef(part == "foot" ? "\(n)_bed" : "\(n)_bed_head", "\(d) Bed")
                b.tex = ["\(n)_bed_side", "\(n)_bed_side", part == "foot" ? "\(n)_bed_top_foot" : "\(n)_bed_top_head", "oak_planks", "\(n)_bed_side", "\(n)_bed_side"]
                b.render = .model; b.opaque = false; b.hardness = 0.2; b.sound = .wood; b.skyStop = true
                b.hidden = part == "head"
                // Model (Remington, v61: beds looked flat): a wooden frame with a tall headboard and a low footboard,
                // a quilted mattress in the bed's colour and a white pillow. Drawn for facing 0 (head toward +Z) and
                // turned for the others, each box with its own textures.
                let wood = Tex.id("spruce_planks"), wool = Tex.id("\(n)_wool"), quilt = Tex.id("\(n)_bed_top_foot"), white = Tex.id("white_wool")
                let W = [UInt16](repeating: wood, count: 6), P = [UInt16](repeating: white, count: 6)
                let M: [UInt16] = [wool, wool, quilt, wood, wool, wool]
                let base: [Box] = part == "head"
                    ? [Box(0, 0, 14, 16, 13, 16, tex: W), Box(0, 3, 0, 16, 6, 14, tex: W), Box(1, 6, 0, 15, 9, 14, tex: M),
                       Box(2, 9, 8, 14, 11, 13, tex: P)]
                    : [Box(0, 0, 0, 16, 8, 2, tex: W), Box(0, 3, 2, 16, 6, 16, tex: W), Box(1, 6, 2, 15, 9, 16, tex: M)]
                addFacing(b, front: "\(n)_bed_side", boxesFor: { k in
                    base.map { bx in
                        func turn(_ x: Int, _ z: Int) -> (Int, Int) {
                            switch k { case 1: return (16 - x, 16 - z); case 2: return (z, 16 - x); case 3: return (16 - z, x); default: return (x, z) }
                        }
                        let a = turn(Int(bx.x0), Int(bx.z0)), c = turn(Int(bx.x1), Int(bx.z1))
                        return Box(min(a.0, c.0), Int(bx.y0), min(a.1, c.1), max(a.0, c.0), Int(bx.y1), max(a.1, c.1), tex: bx.tex)
                    }
                })
            }
        }
        var ct = BlockDef("crafting_table", "Crafting Table")
        ct.tex = ["crafting_table_front", "crafting_table_side", "crafting_table_top", "oak_planks", "crafting_table_front", "crafting_table_side"]
        ct.hardness = 2.5; ct.tool = .axe; ct.sound = .wood
        add(ct)
        var fur = BlockDef("furnace", "Furnace")
        fur.tex = ["furnace_body", "furnace_body", "furnace_plate", "furnace_plate", "furnace_body", "furnace_body"]
        fur.hardness = 3.5; fur.tool = .pickaxe; fur.requiresTool = true
        addFacing(fur, front: "furnace_front")
        var furLit = fur
        furLit.name = "lit_furnace"; furLit.display = "Furnace"; furLit.emit = 13; furLit.hidden = true
        addFacing(furLit, front: "furnace_front_on")
        var chest = BlockDef("chest", "Chest")
        chest.tex = ["chest_side", "chest_side", "chest_top", "chest_top", "chest_side", "chest_side"]
        chest.render = .model; chest.opaque = false; chest.hardness = 2.5; chest.tool = .axe; chest.sound = .wood
        chest.skyStop = true
        addFacing(chest, front: "chest_front", boxes: [Box(1, 0, 1, 15, 14, 15)])
        cube("cobbled_deepslate", "Cobbled Deeprock", "cobbled_deepslate", h: 3.5, req: true)
        cube("andesite", "Andesite", "andesite", h: 1.5, req: true)
        cube("diorite", "Diorite", "diorite", h: 1.5, req: true)
        cube("granite", "Granite", "granite", h: 1.5, req: true)
        cube("tuff", "Tuff", "tuff", h: 1.5, req: true)
        cube("clay", "Clay", "clay", h: 0.6, tool: .shovel, snd: .dirt)
        cube("obsidian", "Obsidian", "obsidian", h: 50, lvl: 3, req: true)
        cube("red_sand", "Red Sand", "red_sand", h: 0.5, tool: .shovel, snd: .sand)
        cube("terracotta", "Terracotta", "terracotta", h: 1.25, req: true)
        cube("lapis_ore", "Lapis Lazuli Ore", "lapis_ore", h: 3, lvl: 1, req: true)
        cube("emerald_ore", "Emerald Ore", "emerald_ore", h: 3, lvl: 2, req: true)
        cube("copper_ore", "Copper Ore", "copper_ore", h: 3, lvl: 1, req: true)
        cube("deepslate_coal_ore", "Deeprock Coal Ore", "deepslate_coal_ore", h: 4.5, req: true)
        cube("deepslate_iron_ore", "Deeprock Iron Ore", "deepslate_iron_ore", h: 4.5, lvl: 1, req: true)
        cube("deepslate_gold_ore", "Deeprock Gold Ore", "deepslate_gold_ore", h: 4.5, lvl: 2, req: true)
        cube("deepslate_diamond_ore", "Deeprock Titanium Ore", "deepslate_diamond_ore", h: 4.5, lvl: 2, req: true)
        cube("deepslate_lapis_ore", "Deeprock Lapis Lazuli Ore", "deepslate_lapis_ore", h: 4.5, lvl: 1, req: true)
        cube("deepslate_copper_ore", "Deeprock Copper Ore", "deepslate_copper_ore", h: 4.5, lvl: 1, req: true)
        cube("mossy_cobblestone", "Mossy Cobblestone", "mossy_cobblestone", h: 2, req: true)
        cube("smooth_stone", "Smooth Stone", "smooth_stone", h: 2, req: true)
        column("oak_wood", "Oak Wood", side: "oak_log", top: "oak_log")
        cube("birch_planks", "Birch Planks", "birch_planks", h: 2, tool: .axe, snd: .wood)
        cube("spruce_planks", "Spruce Planks", "spruce_planks", h: 2, tool: .axe, snd: .wood)
        registerOverworldBlocks()
        registerBuildingBlocks()
        registerCircuitBlocks()
        registerMagicBlocks()
        registerColoredBlocks()
        registerCopperBlocks()
        registerMoreBlocks()
        registerDecorBlocks()
        registerBanners()
        registerWoodExtras()
        registerShelf()
        registerAshenGrove()
        registerSpringBlocks()
        registerShipBlocks()
        registerMilitaryBlocks()
        registerCapitalBlocks()
        registerCapitalArchitecture()
        // Building families: stairs, slabs, fences, walls for each material.
        let woods: [(String, String)] = [("oak", "Oak"), ("birch", "Birch"), ("spruce", "Spruce"), ("crimson", "Rustcap"), ("warped", "Tealcap")]
            + BlockRegistry.extraWoods
        for (w, d) in woods {
            family("\(w)_planks", "\(w)", d, h: 2, tool: .axe, req: false, snd: .wood, stairs: true, slab: true, fence: true, wall: false)
        }
        let stones: [(String, String, String, Bool)] = [
            ("cobblestone", "cobblestone", "Cobblestone", true), ("stone", "stone", "Stone", false),
            ("stone_bricks", "stone_brick", "Stone Brick", true), ("bricks", "brick", "Brick", true),
            ("sandstone", "sandstone", "Sandstone", true), ("nether_bricks", "nether_brick", "Ember Brick", true),
            ("red_nether_bricks", "red_nether_brick", "Red Ember Brick", true), ("blackstone", "blackstone", "Onyxstone", true),
            ("cobbled_deepslate", "cobbled_deepslate", "Cobbled Deeprock", true), ("mossy_cobblestone", "mossy_cobblestone", "Mossy Cobblestone", true),
            ("andesite", "andesite", "Andesite", true), ("diorite", "diorite", "Diorite", true), ("granite", "granite", "Granite", true),
            ("smooth_stone", "smooth_stone", "Smooth Stone", false),
            ("polished_blackstone", "polished_blackstone", "Polished Onyxstone", true),
            ("polished_blackstone_bricks", "polished_blackstone_brick", "Polished Onyxstone Brick", true),
            ("end_stone_bricks", "end_stone_brick", "Hollow Stone Brick", true), ("purpur_block", "purpur", "Violite", false),
            ("mossy_stone_bricks", "mossy_stone_brick", "Mossy Stone Brick", true),
            ("red_sandstone", "red_sandstone", "Red Sandstone", true), ("mud_bricks", "mud_brick", "Mud Brick", true),
            ("prismarine", "prismarine", "Tidestone", true), ("deepslate_bricks", "deepslate_brick", "Deeprock Brick", true),
            ("deepslate_tiles", "deepslate_tile", "Deeprock Tile", true), ("polished_deepslate", "polished_deepslate", "Polished Deeprock", true),
        ]
        for (tex, n, d, wall) in stones {
            family(tex, n, d, h: 2, tool: .pickaxe, req: true, snd: .stone, stairs: n != "smooth_stone", slab: true, fence: n == "nether_brick", wall: wall)
        }
        var pane = BlockDef("glass_pane", "Glass Pane")
        pane.tex = ["glass"]; pane.render = .connect; pane.connect = 2; pane.layer = .cutout; pane.opaque = false
        pane.hardness = 0.3; pane.sound = .glass; pane.skyStop = false
        add(pane)
        var bars = BlockDef("iron_bars", "Iron Bars")
        bars.tex = ["iron_bars"]; bars.render = .connect; bars.connect = 2; bars.layer = .cutout; bars.opaque = false
        bars.hardness = 5; bars.tool = .pickaxe; bars.requiresTool = true; bars.skyStop = false
        add(bars)
        var spawner = BlockDef("spawner", "Monster Spawner")
        spawner.tex = ["spawner"]; spawner.opaque = false; spawner.layer = .cutout; spawner.hardness = 5; spawner.tool = .pickaxe
        spawner.requiresTool = true; spawner.aoOcc = false; spawner.skyStop = true
        add(spawner)
        registerWaterlogged()
    }

    // Twins for every state of the waterloggable groups: stairs, slabs, fences, walls, panes, bars, ladders, lanterns.
    // Registered last, after every other block, group by group in the dry order.
    private func registerWaterlogged() {
        let n = defs.count
        var i = 1
        while i < n {
            let base = Int(groupBase[i])
            var end = i + 1
            while end < n && Int(groupBase[end]) == base { end += 1 }
            let d0 = defs[i]
            let shp = d0.shape
            let ok = i == base && fluidLevel[i] < 0 && (shp == "stairs" || shp == "slab" || shp == "ladder" || shp == "lantern"
                || d0.render == .connect)
            if ok {
                let gk = (d0.group ?? d0.name) + "~wl"
                for s in i..<end {
                    var t = defs[s]
                    t.fluid = 0; t.fluidKind = 1; t.hidden = true; t.skyStop = true
                    let tid = add(t, as: saveNames[s] + "~wl", groupKey: gk)
                    dry[Int(tid)] = BlockID(s)
                    wet[s] = tid
                    wetInvalid[Int(tid)] = defs[s].name.hasSuffix("[double]")
                }
            }
            i = end
        }
    }

    @inline(__always) func isWaterlogged(_ id: BlockID) -> Bool { dry[Int(id)] != id }
    func saveKey(_ id: BlockID) -> String { Int(id) < saveNames.count ? saveNames[Int(id)] : "?" }

    // Stairs (8 states: 4 facings x bottom/top), slabs (bottom/top/double), fence, wall for one material.
    func family(_ tex: String, _ n: String, _ disp: String, h: Float, tool: ToolType, req: Bool, snd: SoundMat,
                stairs: Bool, slab: Bool, fence: Bool, wall: Bool) {
        let t = (tex == "sandstone") ? ["sandstone", "sandstone", "sandstone_top", "sandstone_bottom", "sandstone", "sandstone"] : [tex]
        // Reference hardness: stairs, walls and fences take the full block's; slabs are 2 or the block's if harder
        // (deeprock 3.5, hollow stone brick 3). Every stone family used 2.
        let full: Float = has(tex) ? def(id(tex)).hardness : h
        let slabH: Float = max(h, full)
        func base(_ name: String, _ display: String, _ hh: Float) -> BlockDef {
            var d = BlockDef(name, display)
            d.tex = t; d.render = .model; d.opaque = false; d.hardness = hh; d.tool = tool; d.requiresTool = req; d.sound = snd
            d.skyStop = true
            return d
        }
        if stairs {
            let steps = [Box(0, 8, 0, 16, 16, 8), Box(0, 8, 8, 16, 16, 16), Box(0, 8, 0, 8, 16, 16), Box(8, 8, 0, 16, 16, 16)]
            for top in [false, true] {
                for (k, dir) in ["north", "south", "west", "east"].enumerated() {
                    let name = !top && k == 0 ? "\(n)_stairs" : "\(n)_stairs[\(dir)\(top ? ",top" : "")]"
                    var d = base(name, "\(disp) Stairs", full)
                    d.group = "\(n)_stairs"; d.hidden = top || k != 0; d.shape = "stairs"
                    var st = steps[k]
                    if top { st.y0 = 0; st.y1 = 8 }
                    d.boxes = [top ? Box(0, 8, 0, 16, 16, 16) : Box(0, 0, 0, 16, 8, 16), st]
                    add(d)
                }
            }
        }
        if slab {
            for (k, part) in ["bottom", "top", "double"].enumerated() {
                var d = base(k == 0 ? "\(n)_slab" : "\(n)_slab[\(part)]", "\(disp) Slab", slabH)
                d.group = "\(n)_slab"; d.hidden = k != 0; d.shape = "slab"
                d.boxes = [k == 0 ? Box(0, 0, 0, 16, 8, 16) : (k == 1 ? Box(0, 8, 0, 16, 16, 16) : Box(0, 0, 0, 16, 16, 16))]
                add(d)
            }
        }
        if fence {
            var d = BlockDef(n == "nether_brick" ? "nether_brick_fence" : "\(n)_fence", "\(disp) Fence")
            d.tex = t; d.render = .connect; d.connect = 1; d.opaque = false; d.hardness = full; d.tool = tool; d.sound = snd
            d.requiresTool = req; d.skyStop = false
            add(d)
        }
        if wall {
            var d = BlockDef("\(n)_wall", "\(disp) Wall")
            d.tex = t; d.render = .connect; d.connect = 3; d.opaque = false; d.hardness = full; d.tool = tool; d.sound = snd
            d.requiresTool = req; d.skyStop = true
            add(d)
        }
    }

    // Geometry of a connecting block given which sides connect (n = -Z, s = +Z, w = -X, e = +X).
    static func connectBoxes(_ kind: UInt8, n: Bool, s: Bool, w: Bool, e: Bool, collision: Bool) -> [Box] {
        var out: [Box] = []
        switch kind {
        case 1:
            let top = collision ? 24 : 16
            out.append(Box(6, 0, 6, 10, top, 10))
            if collision {
                if n { out.append(Box(6, 0, 0, 10, 24, 6)) }
                if s { out.append(Box(6, 0, 10, 10, 24, 16)) }
                if w { out.append(Box(0, 0, 6, 6, 24, 10)) }
                if e { out.append(Box(10, 0, 6, 16, 24, 10)) }
            } else {
                for (y0, y1) in [(6, 9), (12, 15)] {
                    if n { out.append(Box(7, y0, 0, 9, y1, 6)) }
                    if s { out.append(Box(7, y0, 10, 9, y1, 16)) }
                    if w { out.append(Box(0, y0, 7, 6, y1, 9)) }
                    if e { out.append(Box(10, y0, 7, 16, y1, 9)) }
                }
            }
        case 2:
            out.append(Box(7, 0, 7, 9, 16, 9))
            if n { out.append(Box(7, 0, 0, 9, 16, 7)) }
            if s { out.append(Box(7, 0, 9, 9, 16, 16)) }
            if w { out.append(Box(0, 0, 7, 7, 16, 9)) }
            if e { out.append(Box(9, 0, 7, 16, 16, 9)) }
        default:
            let top = collision ? 24 : 16, arm = collision ? 24 : 14
            out.append(Box(4, 0, 4, 12, top, 12))
            if n { out.append(Box(5, 0, 0, 11, arm, 4)) }
            if s { out.append(Box(5, 0, 12, 11, arm, 16)) }
            if w { out.append(Box(0, 0, 5, 4, arm, 11)) }
            if e { out.append(Box(12, 0, 5, 16, arm, 11)) }
        }
        return out
    }

    // Whether a connecting block of `kind` joins the neighbour `nb`.
    @inline(__always) func connects(_ kind: UInt8, _ nb: BlockID) -> Bool {
        let k = connectKind[Int(nb)]
        if k != 0 { return k == kind || (kind == 3 && k == 1) || (kind == 1 && k == 3) }
        return opaque[Int(nb)]
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
let MYCELIUM = Blocks.id("mycelium")
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
let EMBERSLATE = Blocks.id("emberslate")
let LAVA = Blocks.id("lava")
let LAVA_FLOW: [BlockID] = [LAVA] + (1...7).map { Blocks.id("lava_\($0)") }
let LAVA_FALL = Blocks.id("lava_falling")
let FIRE = Blocks.id("fire")
let OBSIDIAN = Blocks.id("obsidian")
let NETHERRACK = Blocks.id("netherrack")
let PORTAL_X = Blocks.id("nether_portal")
let PORTAL_Z = Blocks.id("nether_portal_z")
