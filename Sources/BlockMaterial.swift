import Foundation

// Structural materials: what a block is made of, how far it can span unsupported, how much it weighs and how much
// weight it bears. One shared table (Destruction.swift reads it for collapses and falling debris; material damage,
// scorching and shattering can read it too). Public API:
//   BlockMaterial.kind(id)      MaterialKind (stone, brick, wood, metal, glass, earth, plant, cloth, ice, other, none)
//   BlockMaterial.strength(id)  the longest unsupported reach in blocks (a beam held at one end, or half a span held at
//                               both): stone 5, brick 6, wood 6, metal 14, glass 1, earth 1...
//   BlockMaterial.mass(id)      tonnes per block (the ship physics' mass table: one block is a cubic metre)
//   BlockMaterial.load(id)      blocks of weight one block of it bears when what is above it rests on a narrowed section
//   BlockMaterial.anchors(id)   terrain and the like: it holds up what is built on it and never falls itself
enum MaterialKind: Int, CaseIterable {
    case none = 0, stone, brick, wood, metal, glass, earth, plant, cloth, ice, other
    var name: String { String(describing: self) }
}

enum BlockMaterial {
    struct Info {
        var kind: MaterialKind
        var strength: Float
        var load: Float
    }

    static func kind(_ b: BlockID) -> MaterialKind { table[Int(b)].kind }
    static func strength(_ b: BlockID) -> Float { table[Int(b)].strength }
    static func load(_ b: BlockID) -> Float { table[Int(b)].load }
    static func mass(_ b: BlockID) -> Float { ShipParts.mass[Int(b)] }
    static func anchors(_ b: BlockID) -> Bool { anchor[Int(b)] }

    // Per kind: reach (blocks) and bearing (blocks of weight per block of section).
    static let byKind: [MaterialKind: (Float, Float)] = [
        .none: (0, 0), .stone: (5, 30), .brick: (6, 40), .wood: (6, 20), .metal: (14, 150), .glass: (1, 4),
        .earth: (1, 15), .plant: (2, 2), .cloth: (1, 3), .ice: (3, 20), .other: (4, 20),
    ]

    static let table: [Info] = {
        var t: [Info] = []
        t.reserveCapacity(Blocks.count)
        for i in 0..<Blocks.count {
            let b = BlockID(i)
            var k: MaterialKind = .other
            if b == AIR || Blocks.isLiquid(b) || !Blocks.collide[i] { k = .none }
            else {
                let key = Blocks.key(Blocks.groupBase[i])
                switch Blocks.def(b).sound {
                case .wood: k = .wood
                case .glass: k = key.contains("glass") ? .glass : .ice
                case .metal: k = .metal
                case .wool: k = .cloth
                case .plant: k = .plant
                case .dirt, .sand, .gravel, .mud, .snow, .soul: k = .earth
                case .stone, .deepslate, .netherrack, .bone, .amethyst, .sculk, .slime: k = .stone
                }
                if key.contains("brick") || key.contains("tile") { k = .brick }
                if key.hasPrefix("iron_") || key.hasPrefix("steel_") || key.hasPrefix("warship_") || key.hasPrefix("capital_")
                    || key.contains("copper") || key.hasSuffix("_block") && ["iron_block", "gold_block", "netherite_block"].contains(key) {
                    k = key.contains("glass") ? .glass : .metal
                }
                if key.hasSuffix("_leaves") { k = .plant }
                if key.contains("ice") && k != .glass { k = .ice }
            }
            let (reach, bear) = byKind[k] ?? (4, 20)
            t.append(Info(kind: k, strength: reach, load: bear))
        }
        return t
    }()

    static let anchor: [Bool] = {
        var t = [Bool](repeating: false, count: Blocks.count)
        for i in 0..<Blocks.count where i != Int(AIR) && Blocks.collide[i] && !Blocks.isLiquid(BlockID(i)) {
            let k = Blocks.key(Blocks.groupBase[i])
            // Trees and other growths hold themselves up (a branch is no beam to check).
            let growth = k.hasSuffix("_log") || k.hasSuffix("_wood") || k.hasSuffix("_stem") || k.hasSuffix("_hyphae")
                || k.contains("mushroom_block") || k == "bamboo" || k == "cactus" || k.hasSuffix("_roots")
            t[i] = ShipParts.natural[i] || Blocks.hardness[i] < 0 || growth
        }
        return t
    }()
}
