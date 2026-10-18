import Foundation

// P360 (Oct 17 15:34: "the desert temple layout is too close to Minecraft's, redesign it"): on desert ground no save had
// generated before it (StructureCache.legacyP360) the desert temple is the Dust Mission, a sandstone mission church
// half-buried in the dunes. A walled forecourt with a well and a gate; the church a long nave under a pitched roof with
// holes fallen in (shafts of daylight), buttresses down both sides and a stepped mission gable over an arched door with
// a round window; one bell tower at the front corner with a ladder up to the belfry and its bell; inside, pews either side
// of the aisle, the altar under the back wall's niches, and beside the altar a stair down to the crypt: a vaulted
// passage of burial niches to the reliquary at its end (the chests, a husk's cage and lanterns). Keys and loot are the
// temple's ("desert_pyramid").
extension OverworldStructures {
    static func dustMission(_ w: inout StructWriter, _ cx: Int, _ gy: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let ss = SANDSTONE, cut = Blocks.id("cut_sandstone"), chis = Blocks.id("chiseled_sandstone"), smooth = Blocks.id("smooth_sandstone")
        func id(_ n: String, _ alt: BlockID) -> BlockID { Blocks.has(n) ? Blocks.id(n) : alt }
        let slab = id("smooth_sandstone_slab", id("sandstone_slab", cut))
        let stairN = id("sandstone_stairs", cut)
        let ladder = Blocks.id("ladder"), lantern = id("lantern", AIR), bell = id("bell", AIR)
        let pot = id("decorated_pot", Blocks.id("flower_pot")), plank = id("spruce_planks", cut), dead = id("dead_bush", AIR)
        let terra = id("orange_terracotta", cut)
        let y = gy
        func B(_ dx: Int, _ dy: Int, _ dz: Int, _ b: BlockID) { w.set(cx + dx, y + dy, cz + dz, b) }
        func F(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ b: BlockID) {
            w.fill(cx + x0, y + y0, cz + z0, cx + x1, y + y1, cz + z1, b)
        }
        // Foundation, the dunes cleared, the floor.
        for dz in -14...10 { for dx in -10...10 { w.groundDown(cx + dx, y - 1, cz + dz, ss, minY: y - 10) } }
        F(-10, 1, -14, 10, 15, 10, AIR)
        F(-10, 0, -14, 10, 0, 10, ss)

        // The forecourt (z -14...-7): a low wall with a smooth coping, a gate in the middle, a well to one side and a
        // paved walk to the door.
        for k in -10...10 {
            for dy in 1...2 { B(k, dy, -14, cut) }
            B(k, 3, -14, slab)
        }
        for k in -13...(-7) { for dx in [-10, 10] { for dy in 1...2 { B(dx, dy, k, cut) }; B(dx, 3, k, slab) } }
        F(-1, 1, -14, 1, 3, -14, AIR)
        for dx in [-2, 2] { for dy in 1...4 { B(dx, dy, -14, chis) } }
        F(-1, 0, -14, 1, 0, -7, smooth)
        F(-8, 1, -12, -5, 1, -9, cut); F(-7, 1, -11, -6, 1, -10, AIR); F(-7, 0, -11, -6, 0, -10, WATER)
        for (dx, dz) in [(-8, -12), (-5, -12), (-8, -9), (-5, -9)] { for dy in 2...3 { B(dx, dy, dz, plank) } }
        F(-8, 4, -12, -5, 4, -9, slab)
        for (dx, dz) in [(5, -12), (8, -10), (4, -9)] { B(dx, 1, dz, dead) }

        // The nave: x -5...5, z -6...10, walls 7 high, a buttress every four blocks, a pitched roof with holes fallen in.
        for dy in 1...7 {
            for k in -6...10 { B(-5, dy, k, dy == 1 ? cut : ss); B(5, dy, k, dy == 1 ? cut : ss) }
            for k in -5...5 { B(k, dy, 10, dy == 1 ? cut : ss) }
        }
        F(-4, 0, -5, 4, 0, 9, smooth)
        for k in stride(from: -4, through: 8, by: 4) {
            for dy in 1...5 { B(-6, dy, k, cut); B(6, dy, k, cut) }
            B(-6, 6, k, slab); B(6, 6, k, slab)
            // Tall narrow windows between the buttresses.
            if k < 8 { for dy in 3...5 { B(-5, dy, k + 2, AIR); B(5, dy, k + 2, AIR) } }
        }
        for (i, dy) in (8...13).enumerated() {
            let h = 6 - i
            for k in -7...11 {
                B(-h, dy, k, smooth); B(h, dy, k, smooth)
                if h == 1 { B(0, dy, k, cut) }
            }
            if h > 1 { F(-h + 1, dy, 10, h - 1, dy, 10, ss) }
        }
        // Holes in the roof where it fell in (a few, by the seed).
        for _ in 0..<3 {
            let hz = rng.int(12) - 3, side = rng.chance(0.5) ? -1 : 1
            for dz in 0...1 { B(side * 4, 10, hz + dz, AIR); B(side * 3, 11, hz + dz, AIR) }
            B(side * 2, 1, hz, ss)                                                        // the fallen block on the floor
        }

        // The gable over the door (z -6): stepped mission parapet, an arched door and a round window.
        for dy in 1...7 { for k in -5...5 { B(k, dy, -6, dy == 1 ? cut : ss) } }
        for (dy, h) in [(8, 5), (9, 5), (10, 4), (11, 3), (12, 2), (13, 1)] { F(-h, dy, -6, h, dy, -6, ss) }
        for (dy, h) in [(14, 1), (15, 0)] { F(-h, dy, -6, h, dy, -6, chis) }
        F(-1, 1, -6, 1, 3, -6, AIR); B(0, 4, -6, AIR)
        for dy in 1...4 { B(-2, dy, -6, chis); B(2, dy, -6, chis) }
        B(-1, 4, -6, cut); B(1, 4, -6, cut)
        for (dx, dy) in [(0, 7), (-1, 8), (1, 8), (0, 9), (-1, 6), (1, 6), (-2, 7), (2, 7), (-2, 8), (2, 8), (0, 10), (0, 6)] {
            B(dx, dy, -6, terra)
        }
        B(0, 8, -6, AIR)

        // The bell tower at the front right corner (x 6...9, z -6...-3), 14 high, a ladder up to an open belfry.
        F(6, 1, -6, 9, 14, -3, ss)
        F(7, 1, -5, 8, 13, -4, AIR)
        for dy in [5, 10] { for k in 6...9 { B(k, dy, -6, cut); B(k, dy, -3, cut) }; for k in -6...(-3) { B(6, dy, k, cut); B(9, dy, k, cut) } }
        for dy in 11...13 { for (dx, dz) in [(7, -6), (8, -6), (7, -3), (8, -3), (6, -5), (6, -4), (9, -5), (9, -4)] { B(dx, dy, dz, AIR) } }
        F(6, 14, -6, 9, 14, -3, cut)
        F(7, 15, -5, 8, 15, -4, slab)
        F(7, 10, -5, 8, 10, -4, plank)
        B(7, 11, -5, bell)
        for dy in 1...11 { B(8, dy, -4, ladder) }
        for dy in 1...2 { B(8, dy, -6, AIR) }                                            // the door from the forecourt

        // Inside: pews either side of the aisle facing the altar, the altar, niches and pots on the back wall.
        for dz in stride(from: -3, through: 5, by: 2) {
            for dx in -4...(-2) { B(dx, 1, dz, stairN) }
            if dz < -1 { for dx in 2...4 { B(dx, 1, dz, stairN) } }
        }
        F(-2, 1, 7, 2, 1, 7, chis); F(-1, 2, 7, 1, 2, 7, slab)
        B(-2, 2, 7, lantern); B(2, 2, 7, lantern)
        for dx in [-3, 0, 3] { B(dx, 4, 10, AIR); B(dx, 3, 9, slab) }
        B(0, 5, 10, chis); B(-3, 1, 9, pot); B(3, 1, 9, pot)
        for dz in [-2, 4] { B(-4, 4, dz, id("wall_torch[east]", AIR)); B(4, 4, dz, id("wall_torch[west]", AIR)) }

        // The crypt: solid sandstone round it, a stair down the right side of the nave from beside the pews to a passage
        // (x -1...4, z 6...9, floor at y -8), and the reliquary west of the passage under the altar.
        let fy = -7
        F(-6, fy - 2, -2, 6, -1, 11, ss)
        F(-1, fy, 6, 4, fy + 3, 9, AIR)
        F(-1, fy - 1, 6, 4, fy - 1, 9, cut)
        for i in 0...7 {
            let dz = i - 1
            if -i + 1 <= min(0, -i + 3) { F(3, -i + 1, dz, 4, min(0, -i + 3), dz, AIR) }
            F(3, -i, dz, 4, -i, dz, stairN)
        }
        for dz in -1...6 { B(2, 1, dz, slab) }
        // Burial niches along the passage walls: a slab shelf with a pot on it.
        for dx in [0, 2] { B(dx, fy + 1, 10, slab); B(dx, fy + 2, 10, pot) }
        // The reliquary: west of the passage, x -5...-2, with the chests, a lantern and a husk's cage.
        F(-5, fy, 6, -2, fy + 3, 9, AIR)
        F(-5, fy - 1, 6, -2, fy - 1, 9, chis)
        B(-1, fy + 2, 7, chis); B(-1, fy + 2, 8, chis)
        for (dx, dz, f) in [(-5, 7, 3), (-5, 8, 3), (-3, 9, 1)] {
            w.chest(cx + dx, y + fy, cz + dz, loot: "desert_pyramid", seed: rng.next(), facing: f)
        }
        B(-4, fy + 3, 6, id("lantern[hanging]", lantern)); B(2, fy + 3, 8, id("lantern[hanging]", lantern))
        w.spawner(cx - 3, y + fy, cz + 6, mob: "husk")
    }
}
