import Foundation

// P354 (Oct 16 20:06: "houses are too small (the stores are big and great), the jail is too small, and some tiny
// buildings have no clear purpose"): in towns on ground no save had generated before it (StructureCache.legacyP354),
//   homes      as big as the stores: a cottage 9 x 7 (a kitchen-parlour and a back bedroom), a family house 11 x 9
//              (kitchen, dining table, two bedrooms), a big house 13 x 10 on two floors (parlour, kitchen, dining room;
//              three bedrooms upstairs);
//   workshops  the tiny job huts are gone: every trade has a 9 x 7 workshop that shows what it is from the door (the
//              butcher's smokers and meat hooks, the cartographer's tables and shelves of charts, the fletcher's targets
//              and staves, the shepherd's looms and wool, the mason's cutter and stone, the leatherworker's vats and
//              hides, the armourer's furnace and anvil, the fisherman's barrels and nets, the toolsmith's bench and
//              grindstone), a counter for customers and the tradesman's bed in the back corner;
//   the jail   on the big house's 13 x 10 lot, a front office five deep and three cells behind it (TownJail.geometry).
extension Village {
    static func sizeP354(_ k: Kind) -> (Int, Int)? {
        switch k {
        case .smallHouse, .jobHut: return (9, 7)
        case .mediumHouse: return (11, 9)
        case .bigHouse: return (13, 10)
        default: return nil
        }
    }

    private static func table(_ w: inout StructWriter, _ b: LB, _ m: Mats, _ u0: Int, _ u1: Int, v: Int, chairs: Bool = true) {
        let top = blk("oak_pressure_plate", AIR)
        for u in u0...u1 {
            b.set(&w, u, 0, v, m.fence); b.set(&w, u, 1, v, top)
            if chairs { b.set(&w, u, 0, v + 1, b.seat(m, "chair", back: 0)) }
        }
    }

    static func homeLot(_ w: inout StructWriter, _ b: LB, _ m: Mats) {
        let l = b.l
        var rng = SRng(l.seed)
        let stove = blk("furnace", m.planks), smoker = blk("smoker", stove), barrel = blk("barrel", m.planks)
        let shelf = blk("bookshelf", m.planks), pot = blk("flower_pot", AIR)
        let du = l.w / 2
        func chest(_ u: Int, _ v: Int, dy: Int = 0) {
            let c = world(l, u, v)
            w.chest(c.0, l.y + dy, c.1, loot: "village_house", seed: rng.next(), facing: dir(l, 1))
        }
        func wall(_ u0: Int, _ v0: Int, _ u1: Int, _ v1: Int, h: Int, door: [(Int, Int)], dy: Int = 0) {
            b.fill(&w, u0, dy, v0, u1, dy + h - 1, v1, m.planks)
            for (u, v) in door { b.fill(&w, u, dy, v, u, dy + 1, v, AIR) }
        }
        switch l.kind {
        case .smallHouse:
            house(&w, b, m, wallH: 4)
            // Front: the kitchen-parlour (stove, barrel, a table for two); back: the bedroom.
            wall(1, 3, l.w - 2, 3, h: 3, door: [(du, 3)])
            b.set(&w, 1, 0, 1, stove); b.set(&w, 1, 0, 2, barrel)
            table(&w, b, m, 6, 7, v: 1)
            b.set(&w, 2, 2, 2, b.wallTorch(facing: 1))
            bed(&w, b, m, u: 1, v: 4)
            chest(l.w - 2, l.d - 2)
            b.set(&w, l.w - 3, 0, l.d - 2, pot)
            b.set(&w, du, 2, l.d - 2, b.wallTorch(facing: 1))
            villager(&w, b, u: 3, v: 2)
        case .mediumHouse:
            house(&w, b, m, wallH: 4)
            // Front: the kitchen (stove, smoker, barrels) and the dining table; back: two bedrooms either side of a wall.
            wall(1, 4, l.w - 2, 4, h: 3, door: [(2, 4), (l.w - 3, 4)])
            wall(du, 5, du, l.d - 2, h: 3, door: [])
            b.set(&w, 1, 0, 1, stove); b.set(&w, 2, 0, 1, smoker); b.set(&w, 1, 0, 3, barrel); b.set(&w, 1, 1, 3, barrel)
            table(&w, b, m, 6, 8, v: 2)
            b.set(&w, l.w - 2, 0, 1, shelf)
            b.set(&w, du - 1, 2, 3, b.wallTorch(facing: 1)); b.set(&w, du + 1, 2, 3, b.wallTorch(facing: 1))
            bed(&w, b, m, u: 1, v: 5); bed(&w, b, m, u: 3, v: 5)
            bed(&w, b, m, u: l.w - 2, v: 5)
            chest(du - 1, l.d - 2); chest(du + 1, l.d - 2)
            b.set(&w, 2, 2, l.d - 2, b.wallTorch(facing: 1)); b.set(&w, l.w - 3, 2, l.d - 2, b.wallTorch(facing: 1))
            villager(&w, b, u: 4, v: 2); villager(&w, b, u: l.w - 3, v: 6)
        default:   // .bigHouse
            house(&w, b, m, wallH: 8)
            // Ground floor: the parlour to the left (shelves, armchairs by the fire), the kitchen and dining room right.
            wall(du + 2, 1, du + 2, l.d - 2, h: 3, door: [(du + 2, 2), (du + 2, l.d - 3)])
            b.fill(&w, 1, 0, l.d - 2, 3, 2, l.d - 2, shelf)
            b.set(&w, 1, 0, 2, b.seat(m, "chair", back: 2)); b.set(&w, 1, 0, 4, b.seat(m, "chair", back: 2))
            b.set(&w, 2, 0, 3, blk("campfire", stove))
            b.set(&w, l.w - 2, 0, l.d - 2, stove); b.set(&w, l.w - 3, 0, l.d - 2, smoker); b.set(&w, l.w - 4, 0, l.d - 2, barrel)
            table(&w, b, m, du + 4, l.w - 3, v: 3)
            b.set(&w, 2, 2, 1, b.wallTorch(facing: 0)); b.set(&w, l.w - 3, 2, 1, b.wallTorch(facing: 0))
            // The upper floor, a ladder up by the door; three bedrooms along the back.
            b.fill(&w, 1, 4, 1, l.w - 2, 4, l.d - 2, m.floor)
            for dy in 0...4 { b.set(&w, du - 2, dy, 1, blk("ladder", AIR) + BlockID(dir(l, 0))) }
            wall(4, 6, 4, l.d - 2, h: 3, door: [], dy: 5); wall(8, 6, 8, l.d - 2, h: 3, door: [], dy: 5)
            for u in [1, 5, 9] {
                bedUp(&w, b, m, u: u + 1, v: l.d - 3)
                let c = world(l, u, l.d - 2)
                w.chest(c.0, l.y + 5, c.1, loot: "village_house", seed: rng.next(), facing: dir(l, 1))
                b.set(&w, u + 2, 7, l.d - 2, b.wallTorch(facing: 1))
            }
            villager(&w, b, u: 3, v: 3); villager(&w, b, u: l.w - 3, v: 4); villager(&w, b, u: 6, v: 3, dy: 5)
        }
    }

    // A bed on the upper floor (foot toward the street).
    static func bedUp(_ w: inout StructWriter, _ b: LB, _ m: Mats, u: Int, v: Int) {
        let d = dir(b.l, 0)
        let facing = [1, 0, 3, 2][d]
        b.set(&w, u, 5, v, Blocks.id(m.bed) + BlockID(facing))
        b.set(&w, u, 5, v + 1, Blocks.id(m.bed + "_head") + BlockID(facing))
    }

    // A tradesman's workshop: his station, his stock along the walls, a counter by the door, his bed in the corner.
    static func workshopLot(_ w: inout StructWriter, _ b: LB, _ m: Mats) {
        let l = b.l
        house(&w, b, m, wallH: 5)
        let g = { (n: String) in blk(n, blk("barrel", m.planks)) }
        let station: [String: String] = ["butcher": "smoker", "cartographer": "cartography_table", "fletcher": "fletching_table",
                                         "shepherd": "loom", "mason": "stonecutter", "leatherworker": "cauldron", "armorer": "blast_furnace",
                                         "fisherman": "barrel", "toolsmith": "smithing_table"]
        // Stock: (u, dy, v, block) inside u 1...7, v 1...5 (the door's column, u 4, kept clear).
        let stock: [String: [(Int, Int, Int, String)]] = [
            "butcher": [(1, 0, 5, "smoker"), (3, 0, 5, "barrel"), (1, 0, 4, "barrel"), (1, 3, 2, "chain"), (2, 3, 2, "chain"), (3, 3, 2, "chain"),
                        (1, 2, 2, "red_wool"), (3, 2, 2, "red_wool"), (1, 0, 3, "hay_block")],
            "cartographer": [(1, 0, 5, "bookshelf"), (1, 1, 5, "bookshelf"), (3, 0, 5, "bookshelf"), (3, 1, 5, "bookshelf"), (1, 0, 4, "lectern"),
                             (1, 0, 2, "white_wool"), (1, 0, 3, "cartography_table")],
            "fletcher": [(1, 0, 5, "target"), (3, 0, 5, "hay_block"), (1, 0, 4, "barrel"), (1, 0, 3, "target"), (3, 1, 5, "hay_block"),
                         (1, 1, 4, "barrel")],
            "shepherd": [(1, 0, 5, "white_wool"), (1, 1, 5, "white_wool"), (3, 0, 5, "gray_wool"), (3, 1, 5, "brown_wool"), (1, 0, 4, "loom"),
                         (1, 0, 3, "black_wool"), (1, 0, 2, "white_wool")],
            "mason": [(1, 0, 5, "stone_bricks"), (1, 1, 5, "stone_bricks"), (3, 0, 5, "chiseled_stone_bricks"), (1, 0, 4, "smooth_stone"),
                      (1, 0, 3, "stonecutter"), (3, 1, 5, "stone_brick_slab")],
            "leatherworker": [(1, 0, 5, "cauldron"), (3, 0, 5, "cauldron"), (1, 0, 4, "barrel"), (1, 2, 3, "brown_wool"), (1, 2, 2, "brown_wool"),
                              (1, 0, 2, "oak_fence"), (1, 1, 2, "oak_fence")],
            "armorer": [(1, 0, 5, "blast_furnace"), (3, 0, 5, "anvil"), (1, 0, 4, "iron_block"), (1, 1, 5, "chain"), (1, 0, 3, "barrel"),
                        (3, 2, 5, "chain")],
            "fisherman": [(1, 0, 5, "barrel"), (1, 1, 5, "barrel"), (3, 0, 5, "barrel"), (1, 0, 4, "composter"), (1, 2, 2, "cobweb"),
                          (1, 2, 3, "cobweb"), (1, 0, 3, "water_cauldron")],
            "toolsmith": [(1, 0, 5, "anvil"), (3, 0, 5, "grindstone"), (1, 0, 4, "crafting_table"), (1, 0, 3, "barrel"), (3, 1, 5, "chain")],
        ]
        b.set(&w, 2, 0, 5, g(station[l.job] ?? "barrel"))
        for (u, dy, v, n) in stock[l.job] ?? [] { b.set(&w, u, dy, v, g(n)) }
        // The counter across the right of the room, a gap to walk behind it; the bed in the back corner.
        for u in 5...6 { b.set(&w, u, 0, 2, m.log) }
        b.set(&w, 6, 1, 2, blk("lantern", AIR))
        bed(&w, b, m, u: 7, v: 4)
        b.set(&w, 6, 0, 5, blk("barrel", m.planks))
        b.set(&w, 2, 3, 1, b.wallTorch(facing: 0)); b.set(&w, 6, 3, 5, b.wallTorch(facing: 1))
        villager(&w, b, u: 6, v: 3)
    }
}
