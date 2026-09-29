import Foundation

// Block IDs. To add a block: add an ID here, a texture layer in T (paint it in Textures.swift),
// then register it in BlockTable.init. Registration order must match the ID values.
let AIR: UInt8 = 0
let STONE: UInt8 = 1
let GRASS: UInt8 = 2
let DIRT: UInt8 = 3
let COBBLE: UInt8 = 4
let PLANKS: UInt8 = 5
let BEDROCK: UInt8 = 6
let SAND: UInt8 = 7
let GRAVEL: UInt8 = 8
let LOG: UInt8 = 9
let LEAVES: UInt8 = 10
let GLASS: UInt8 = 11
let WATER: UInt8 = 12
let COAL_ORE: UInt8 = 13
let IRON_ORE: UInt8 = 14
let GOLD_ORE: UInt8 = 15
let DIAMOND_ORE: UInt8 = 16
let BRICKS: UInt8 = 17
let SNOWY_GRASS: UInt8 = 18
let CACTUS: UInt8 = 19
let SNOW: UInt8 = 20
let STONE_BRICKS: UInt8 = 21
let SANDSTONE: UInt8 = 22
let BIRCH_LOG: UInt8 = 23
let BIRCH_LEAVES: UInt8 = 24
let SPRUCE_LOG: UInt8 = 25
let SPRUCE_LEAVES: UInt8 = 26
let TALL_GRASS: UInt8 = 27
let RED_FLOWER: UInt8 = 28
let YELLOW_FLOWER: UInt8 = 29
let BLUE_FLOWER: UInt8 = 30
let TORCH: UInt8 = 31
let LAMP: UInt8 = 32
// Flowing water: WATER_FLOW[k] for k = 1...7 (index 0 = the source, WATER). WATER_FALL is a falling column.
let WATER_FLOW: [UInt8] = [WATER, 33, 34, 35, 36, 37, 38, 39]
let WATER_FALL: UInt8 = 40

enum T {
    static let stone = 0, grassTop = 1, grassSide = 2, dirt = 3, cobble = 4, planks = 5, bedrock = 6, sand = 7
    static let gravel = 8, logSide = 9, logTop = 10, leaves = 11, glass = 12, water = 13, coal = 14, iron = 15
    static let gold = 16, diamond = 17, brick = 18, snow = 19, snowSide = 20, cactusSide = 21, cactusTop = 22
    static let stoneBrick = 23, sandstoneSide = 24, sandstoneTop = 25
    static let birchSide = 26, birchTop = 27, spruceSide = 28, spruceTop = 29, birchLeaves = 30, spruceLeaves = 31
    static let tallGrass = 32, redFlower = 33, yellowFlower = 34, blueFlower = 35
    static let torch = 36, lamp = 37
    static let count = 38
}

// plant = cross-shaped cutout sprite (two diagonal quads), no collision, doesn't block light.
enum BlockKind: UInt8 { case air = 0, solid = 1, cutout = 2, liquid = 3, plant = 4 }

struct BlockDef {
    var name: String
    var kind: BlockKind
    var tex: [Int] // face order: +X -X +Y -Y +Z -Z
}

// Flat lookup tables so hot loops (meshing, physics) never touch structs or strings.
final class BlockTable {
    var defs: [BlockDef] = []
    var kind = [UInt8](repeating: 0, count: 256)
    var opaque = [Bool](repeating: false, count: 256)
    var sky = [Bool](repeating: false, count: 256)        // stops the straight-down 15 skylight column
    var lightOpaque = [Bool](repeating: false, count: 256) // light can't enter (solid blocks)
    var emit = [UInt8](repeating: 0, count: 256)          // block light emitted (0-15)
    var fluidLevel = [Int8](repeating: -1, count: 256)    // -1 not water, 0 source, 1-7 flowing, 8 falling
    var hidden = [Bool](repeating: false, count: 256)     // internal states, not offered to the player
    var aoOcc = [Bool](repeating: false, count: 256)
    var collide = [Bool](repeating: false, count: 256)
    var cullSame = [Bool](repeating: false, count: 256)
    var tex = [UInt8](repeating: 0, count: 256 * 6)

    init() {
        func all(_ t: Int) -> [Int] { [t, t, t, t, t, t] }
        func column(_ side: Int, _ top: Int, _ bottom: Int) -> [Int] { [side, side, top, bottom, side, side] }
        add("Air", .air, all(0))
        add("Stone", .solid, all(T.stone))
        add("Grass Block", .solid, column(T.grassSide, T.grassTop, T.dirt))
        add("Dirt", .solid, all(T.dirt))
        add("Cobblestone", .solid, all(T.cobble))
        add("Oak Planks", .solid, all(T.planks))
        add("Bedrock", .solid, all(T.bedrock))
        add("Sand", .solid, all(T.sand))
        add("Gravel", .solid, all(T.gravel))
        add("Oak Log", .solid, column(T.logSide, T.logTop, T.logTop))
        add("Oak Leaves", .cutout, all(T.leaves))
        add("Glass", .cutout, all(T.glass), sky: false, cullSame: true)
        add("Water", .liquid, all(T.water), sky: true)
        add("Coal Ore", .solid, all(T.coal))
        add("Iron Ore", .solid, all(T.iron))
        add("Gold Ore", .solid, all(T.gold))
        add("Diamond Ore", .solid, all(T.diamond))
        add("Bricks", .solid, all(T.brick))
        add("Snowy Grass", .solid, column(T.snowSide, T.snow, T.dirt))
        add("Cactus", .solid, column(T.cactusSide, T.cactusTop, T.cactusTop))
        add("Snow Block", .solid, all(T.snow))
        add("Stone Bricks", .solid, all(T.stoneBrick))
        add("Sandstone", .solid, column(T.sandstoneSide, T.sandstoneTop, T.sandstoneTop))
        add("Birch Log", .solid, column(T.birchSide, T.birchTop, T.birchTop))
        add("Birch Leaves", .cutout, all(T.birchLeaves))
        add("Spruce Log", .solid, column(T.spruceSide, T.spruceTop, T.spruceTop))
        add("Spruce Leaves", .cutout, all(T.spruceLeaves))
        add("Tall Grass", .plant, all(T.tallGrass))
        add("Red Flower", .plant, all(T.redFlower))
        add("Yellow Flower", .plant, all(T.yellowFlower))
        add("Blue Flower", .plant, all(T.blueFlower))
        add("Torch", .plant, all(T.torch), emit: 14)
        add("Lamp", .solid, all(T.lamp), emit: 15)
        for k in 1...7 { add("Flowing Water \(k)", .liquid, all(T.water), sky: true, hidden: true); fluidLevel[defs.count - 1] = Int8(k) }
        add("Falling Water", .liquid, all(T.water), sky: true, hidden: true)
        fluidLevel[Int(WATER)] = 0
        fluidLevel[Int(WATER_FALL)] = 8
    }

    func add(_ name: String, _ kind: BlockKind, _ tex: [Int], sky: Bool? = nil, cullSame: Bool = false, emit: UInt8 = 0, hidden: Bool = false) {
        let id = defs.count
        let blocksSky = sky ?? (kind == .solid || kind == .cutout)
        defs.append(BlockDef(name: name, kind: kind, tex: tex))
        self.kind[id] = kind.rawValue
        opaque[id] = kind == .solid
        self.sky[id] = blocksSky
        lightOpaque[id] = kind == .solid
        self.emit[id] = emit
        self.hidden[id] = hidden
        aoOcc[id] = kind == .solid || (kind == .cutout && !cullSame)
        collide[id] = kind == .solid || kind == .cutout
        self.cullSame[id] = cullSame
        for f in 0..<6 { self.tex[id * 6 + f] = UInt8(tex[f]) }
    }

    @inline(__always) func isPlant(_ id: UInt8) -> Bool { kind[Int(id)] == BlockKind.plant.rawValue }
    // Blocks the crosshair can target (everything except air and liquids).
    @inline(__always) func targetable(_ id: UInt8) -> Bool {
        let k = kind[Int(id)]
        return k != BlockKind.air.rawValue && k != BlockKind.liquid.rawValue
    }

    @inline(__always) func isLiquid(_ id: UInt8) -> Bool { kind[Int(id)] == BlockKind.liquid.rawValue }

    var placeable: [UInt8] { (1..<defs.count).filter { !hidden[$0] }.map { UInt8($0) } }
    func name(_ id: UInt8) -> String { Int(id) < defs.count ? defs[Int(id)].name : "?" }
}

let Blocks = BlockTable()
