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

enum T {
    static let stone = 0, grassTop = 1, grassSide = 2, dirt = 3, cobble = 4, planks = 5, bedrock = 6, sand = 7
    static let gravel = 8, logSide = 9, logTop = 10, leaves = 11, glass = 12, water = 13, coal = 14, iron = 15
    static let gold = 16, diamond = 17, brick = 18, snow = 19, snowSide = 20, cactusSide = 21, cactusTop = 22
    static let stoneBrick = 23, sandstoneSide = 24, sandstoneTop = 25
    static let count = 26
}

enum BlockKind: UInt8 { case air = 0, solid = 1, cutout = 2, liquid = 3 }

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
    var sky = [Bool](repeating: false, count: 256)
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
        add("Water", .liquid, all(T.water), sky: false)
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
    }

    func add(_ name: String, _ kind: BlockKind, _ tex: [Int], sky: Bool? = nil, cullSame: Bool = false) {
        let id = defs.count
        let blocksSky = sky ?? (kind == .solid || kind == .cutout)
        defs.append(BlockDef(name: name, kind: kind, tex: tex))
        self.kind[id] = kind.rawValue
        opaque[id] = kind == .solid
        self.sky[id] = blocksSky
        aoOcc[id] = kind == .solid || (kind == .cutout && !cullSame)
        collide[id] = kind == .solid || kind == .cutout
        self.cullSame[id] = cullSame
        for f in 0..<6 { self.tex[id * 6 + f] = UInt8(tex[f]) }
    }

    var placeable: [UInt8] { (1..<defs.count).map { UInt8($0) } }
    func name(_ id: UInt8) -> String { Int(id) < defs.count ? defs[Int(id)].name : "?" }
}

let Blocks = BlockTable()
