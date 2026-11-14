import Foundation
import simd

// Remington, Nov 14 12:55 AST: "I want a playground made of pretty builds that AI agents placed block by block themselves
// to prove that it's easy, and it must be done on varieties of natural terrain that is currently vulnerable to the
// procedural reshaping."
//
// The Builders' Grounds: six builds, each on its own kind of natural ground in a Polygons (smooth, field) world:
//   Hillside Cottage   dug into a slope, a cobble footing on the low side, a pitched spruce roof and a chimney
//   Beach Lighthouse   striped, on the sand by the water, a glass lantern room on a railed gallery
//   Ridge Watchtower   stone brick on a hilltop, battlements, lanterns at the corners
//   Lakeside Boathouse a deck out over the water on log posts down to the bed, a hut on the shore
//   Forest Stilt Cabin up among the trees on four log stilts
//   Stone Gate         an arch with hanging lanterns on rocky ground
// BuilderBot builds each one through the player's own controls only (fly, turn, aim at a face, the break and place
// buttons, the hotbar): no block is written any other way. BuildersCheck (questcheck --builds) has it build all six,
// lets the world settle (load checks, the ground's own weighing and reshaping), then checks every block and the ground
// round each build. The Builders' Grounds world (Worlds menu) lays the same builds out in the order the agent placed
// them, a few blocks a tick, so he watches them go up.
enum BuildersGrounds {
    static let worldName = "Builders' Grounds"
    static let seed: UInt64 = UInt64(ProcessInfo.processInfo.environment["BS_BUILDSEED"] ?? "") ?? 632461258612199693

    // MARK: Blueprints

    enum Footing { case terrace, stilts(Int), dock }
    struct Blueprint {
        let key: String
        let title: [String]
        let ground: String                 // the kind of ground it wants (Site.kind)
        let footing: Footing
        let draft: Draft
    }

    // A build relative to its origin: x east, z south, y 0 the floor layer. `posts` run down from y -1 to the ground
    // (or the bed under water); `footprint` cells are filled down to the ground under the floor; `air` cells are kept
    // clear (a room, a doorway): anything natural in them is dug out first.
    struct Draft {
        var cells: [IVec3: BlockID] = [:]
        var posts: [(x: Int, z: Int, key: String)] = []
        var footprint: [(x: Int, z: Int)] = []
        var footKey = "cobblestone"
        var air: Set<IVec3> = []
        static func id(_ k: String, _ fallback: String = "stone") -> BlockID { Blocks.has(k) ? Blocks.id(k) : Blocks.id(fallback) }
        mutating func put(_ x: Int, _ y: Int, _ z: Int, _ k: String, _ off: Int = 0, or fb: String = "stone") {
            cells[IVec3(x, y, z)] = Draft.id(k, fb) + BlockID(off)
        }
        mutating func box(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ k: String, _ off: Int = 0) {
            for y in y0...y1 { for z in z0...z1 { for x in x0...x1 { put(x, y, z, k, off) } } }
        }
        mutating func clear(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int) {
            for y in y0...y1 { for z in z0...z1 { for x in x0...x1 { let p = IVec3(x, y, z); cells[p] = nil; air.insert(p) } } }
        }
        // A pillar along y: the log's up state.
        mutating func log(_ x: Int, _ y: Int, _ z: Int, _ k: String) { put(x, y, z, k) }
        // Stairs: dir 0 north, 1 south, 2 west, 3 east is the way they climb (the high step's side); top: upside down.
        mutating func stairs(_ x: Int, _ y: Int, _ z: Int, _ k: String, _ dir: Int, top: Bool = false) {
            put(x, y, z, k + "_stairs", dir + (top ? 4 : 0), or: k + "_slab")
        }
        mutating func slab(_ x: Int, _ y: Int, _ z: Int, _ k: String, top: Bool = false) { put(x, y, z, k + "_slab", top ? 1 : 0) }
        // A pitched roof over walls x0...x1, z0...z1 whose top course is at y: eaves one out all round, the ridge along x.
        // Gable ends filled with `gable`.
        mutating func roofX(_ x0: Int, _ x1: Int, _ z0: Int, _ z1: Int, _ y: Int, _ k: String, gable: String) {
            let w = z1 - z0 + 3                                       // rows from the north eave to the south eave
            for i in 0..<((w + 1) / 2) {
                let zn = z0 - 1 + i, zs = z1 + 1 - i, yy = y + i
                for x in (x0 - 1)...(x1 + 1) {
                    if zn == zs { slab(x, yy, zn, k) }
                    else { stairs(x, yy, zn, k, 1); stairs(x, yy, zs, k, 0) }
                }
                if i >= 1 && zn + 1 <= zs - 1 {
                    for z in (zn + 1)...(zs - 1) { put(x0, yy, z, gable); put(x1, yy, z, gable) }
                }
            }
        }
    }

    static func blueprints() -> [Blueprint] {
        var out: [Blueprint] = []

        // Hillside Cottage: 9 x 7, cut into the slope.
        do {
            var d = Draft()
            d.footKey = "cobblestone"
            d.box(0, 0, 0, 8, 0, 6, "cobblestone")
            d.box(1, 0, 1, 7, 0, 5, "spruce_planks")
            for y in 1...3 {
                for x in 0...8 { d.put(x, y, 0, "birch_planks"); d.put(x, y, 6, "birch_planks") }
                for z in 1...5 { d.put(0, y, z, "birch_planks"); d.put(8, y, z, "birch_planks") }
                for (x, z) in [(0, 0), (8, 0), (0, 6), (8, 6), (4, 0), (4, 6), (0, 3), (8, 3)] { d.log(x, y, z, "spruce_log") }
            }
            for x in [2, 6] { d.put(x, 2, 0, "glass_pane"); d.put(x, 2, 6, "glass_pane") }
            for z in [2, 4] { d.put(0, 2, z, "glass_pane"); d.put(8, 2, z, "glass_pane") }
            d.clear(1, 1, 1, 7, 3, 5)
            d.cells[IVec3(4, 1, 6)] = nil; d.cells[IVec3(4, 2, 6)] = nil     // the doorway (a log post's place)
            d.put(4, 1, 6, "spruce_door", 1); d.put(4, 2, 6, "spruce_door", 1 + 8)
            d.roofX(0, 8, 0, 6, 3, "spruce", gable: "spruce_planks")
            for y in 1...8 { d.put(7, y, 1, "bricks") }                      // the chimney, up through the roof
            d.cells[IVec3(7, 9, 1)] = nil
            for x in [2, 6] { d.put(x, 1, 7, "spruce_fence"); d.put(x, 2, 7, "lantern") }
            d.box(3, 0, 7, 5, 0, 8, "cobblestone")                           // the step out of the door
            for z in 0...6 { d.footprint.append((-1, z)) }
            for x in 0...8 { for z in 0...6 { d.footprint.append((x, z)) } }
            for x in 3...5 { for z in 7...8 { d.footprint.append((x, z)) } }
            out.append(Blueprint(key: "cottage", title: ["Hillside Cottage", "cut into the slope"], ground: "slope", footing: .terrace, draft: d))
        }

        // Beach Lighthouse: a round tower of radius 3, white with red bands, a gallery and a glass lantern room.
        do {
            var d = Draft()
            d.footKey = "stone_bricks"
            let c = 4
            func ring(_ r0: Float, _ r1: Float, _ body: (Int, Int) -> Void) {
                for z in -5...5 { for x in -5...5 {
                    let r = (Float(x * x + z * z)).squareRoot()
                    if r >= r0 && r < r1 { body(x + c, z + c) }
                } }
            }
            ring(0, 3.5) { x, z in d.put(x, 0, z, "stone_bricks") }
            for y in 1...14 {
                let band = (y - 1) / 3 % 2 == 1
                ring(2.4, 3.5) { x, z in d.put(x, y, z, band ? "red_concrete" : "white_concrete", or: band ? "red_wool" : "white_wool") }
                ring(0, 2.4) { x, z in d.air.insert(IVec3(x, y, z)) }
            }
            d.cells[IVec3(c, 1, c + 3)] = nil; d.cells[IVec3(c, 2, c + 3)] = nil
            d.put(c, 1, c + 3, "spruce_door", 1); d.put(c, 2, c + 3, "spruce_door", 1 + 8)
            for y in [5, 9, 12] { d.put(c + 3, y, c, "glass_pane"); d.put(c - 3, y, c, "glass_pane") }
            ring(0, 4.6) { x, z in d.put(x, 15, z, "stone_brick_slab", 1) }          // the gallery floor (top half)
            ring(3.6, 4.6) { x, z in d.put(x, 16, z, "spruce_fence") }
            ring(0, 2.4) { x, z in d.put(x, 16, z, "stone_bricks") }
            d.put(c, 17, c, "lantern")
            ring(1.4, 2.4) { x, z in for y in 17...18 { d.put(x, y, z, "glass") } }
            ring(0, 2.4) { x, z in d.put(x, 19, z, "stone_brick_slab") }
            d.put(c, 19, c, "stone_bricks"); d.put(c, 20, c, "lightning_rod", or: "spruce_fence")
            ring(0, 3.5) { x, z in d.footprint.append((x, z)) }
            out.append(Blueprint(key: "lighthouse", title: ["Beach Lighthouse", "on the sand"], ground: "beach", footing: .terrace, draft: d))
        }

        // Ridge Watchtower: 5 x 5 stone brick, 11 high, battlements, lanterns.
        do {
            var d = Draft()
            d.footKey = "stone_bricks"
            d.box(0, 0, 0, 4, 0, 4, "stone_bricks")
            for y in 1...9 {
                for x in 0...4 { d.put(x, y, 0, y % 4 == 2 ? "mossy_stone_bricks" : "stone_bricks"); d.put(x, y, 4, "stone_bricks") }
                for z in 1...3 { d.put(0, y, z, "stone_bricks"); d.put(4, y, z, y % 3 == 0 ? "mossy_stone_bricks" : "stone_bricks") }
            }
            d.clear(1, 1, 1, 3, 9, 3)
            d.cells[IVec3(2, 1, 4)] = nil; d.cells[IVec3(2, 2, 4)] = nil
            d.air.insert(IVec3(2, 1, 4)); d.air.insert(IVec3(2, 2, 4))         // the way in
            for (x, z) in [(2, 0), (0, 2), (4, 2)] { for y in [4, 7] { d.cells[IVec3(x, y, z)] = nil; d.air.insert(IVec3(x, y, z)) } }   // slits
            d.box(1, 9, 1, 3, 9, 3, "spruce_planks")                         // the top floor
            d.box(-1, 10, -1, 5, 10, 5, "stone_bricks")                      // a course jutting out
            for x in -1...5 { for z in -1...5 where x == -1 || x == 5 || z == -1 || z == 5 {
                if (x + z) % 2 == 0 { d.put(x, 11, z, "stone_brick_wall", or: "stone_bricks") }
            } }
            for (x, z) in [(0, 0), (4, 0), (0, 4), (4, 4)] { d.put(x, 11, z, "lantern") }
            for x in 0...4 { for z in 0...4 { d.footprint.append((x, z)) } }
            out.append(Blueprint(key: "watchtower", title: ["Ridge Watchtower", "on the hilltop"], ground: "hilltop", footing: .terrace, draft: d))
        }

        // Lakeside Boathouse: a deck 11 long running out over the water (south), log posts to the bed, a hut on the shore.
        do {
            var d = Draft()
            d.footKey = "spruce_planks"
            d.box(0, 0, 0, 4, 0, 10, "spruce_planks")
            for (x, z) in [(0, 4), (4, 4), (0, 7), (4, 7), (0, 10), (4, 10)] { d.posts.append((x, z, "spruce_log")) }
            for z in 5...10 { d.put(0, 1, z, "spruce_fence"); d.put(4, 1, z, "spruce_fence") }
            d.put(0, 2, 10, "lantern"); d.put(4, 2, 10, "lantern")
            for y in 1...3 {
                for x in 0...4 { d.put(x, y, 0, "oak_planks") }
                for z in 1...3 { d.put(0, y, z, "oak_planks"); d.put(4, y, z, "oak_planks") }
                d.put(0, y, 3, "oak_log"); d.put(4, y, 3, "oak_log"); d.put(0, y, 0, "oak_log"); d.put(4, y, 0, "oak_log")
            }
            d.put(2, 2, 0, "glass_pane")
            d.clear(1, 1, 1, 3, 3, 3)
            d.air.insert(IVec3(1, 1, 4)); d.air.insert(IVec3(2, 1, 4)); d.air.insert(IVec3(3, 1, 4))
            for i in 0..<3 {
                for z in (-1)...4 { d.stairs(-1 + i, 3 + i, z, "oak", 3); d.stairs(5 - i, 3 + i, z, "oak", 2) }
            }
            for z in (-1)...4 { d.slab(2, 6, z, "oak") }
            for z in [0, 3] { for x in 1...3 { d.put(x, 4, z, "oak_planks") }; d.put(2, 5, z, "oak_planks") }   // the gable ends
            for x in 0...4 { for z in 0...3 { d.footprint.append((x, z)) } }
            out.append(Blueprint(key: "boathouse", title: ["Lakeside Boathouse", "out over the water"], ground: "shore", footing: .dock, draft: d))
        }

        // Forest Stilt Cabin: 7 x 7 on four log stilts, 4 over the forest floor.
        do {
            var d = Draft()
            d.footKey = "spruce_log"
            d.box(0, 0, 0, 6, 0, 6, "birch_planks")
            for (x, z) in [(0, 0), (6, 0), (0, 6), (6, 6), (3, 0), (3, 6)] { d.posts.append((x, z, "spruce_log")) }
            for y in 1...3 {
                for x in 0...6 { d.put(x, y, 0, "spruce_planks"); d.put(x, y, 6, "spruce_planks") }
                for z in 1...5 { d.put(0, y, z, "spruce_planks"); d.put(6, y, z, "spruce_planks") }
                for (x, z) in [(0, 0), (6, 0), (0, 6), (6, 6)] { d.log(x, y, z, "spruce_log") }
            }
            for x in [2, 4] { d.put(x, 2, 0, "glass_pane"); d.put(x, 2, 6, "glass_pane") }
            d.put(0, 2, 3, "glass_pane"); d.put(6, 2, 3, "glass_pane")
            d.clear(1, 1, 1, 5, 3, 5)
            d.cells[IVec3(3, 1, 6)] = nil; d.cells[IVec3(3, 2, 6)] = nil
            d.put(3, 1, 6, "spruce_door", 1); d.put(3, 2, 6, "spruce_door", 1 + 8)
            d.box(2, 0, 7, 4, 0, 8, "birch_planks")                          // the porch
            d.posts.append((2, 8, "spruce_log")); d.posts.append((4, 8, "spruce_log"))
            for x in [2, 4] { d.put(x, 1, 8, "birch_fence") }
            d.put(2, 2, 8, "lantern")
            d.roofX(0, 6, 0, 6, 3, "oak", gable: "oak_planks")
            out.append(Blueprint(key: "stiltcabin", title: ["Forest Stilt Cabin", "up among the trees"], ground: "forest", footing: .stilts(4), draft: d))
        }

        // Stone Gate: two pillars, an arch of upside-down stairs, lanterns hung under the lintel.
        do {
            var d = Draft()
            d.footKey = "stone_bricks"
            for x in [0, 1, 7, 8] { for z in 0...1 { d.put(x, 0, z, "stone_bricks") } }
            for y in 1...6 { for x in [0, 1, 7, 8] { for z in 0...1 { d.put(x, y, z, y == 3 ? "chiseled_stone_bricks" : "stone_bricks", or: "stone_bricks") } } }
            for x in 0...8 { for z in 0...1 { d.put(x, 7, z, "stone_bricks") } }
            for z in 0...1 { d.stairs(2, 6, z, "stone_brick", 2, top: true); d.stairs(6, 6, z, "stone_brick", 3, top: true) }
            for x in 3...5 { for z in 0...1 { d.slab(x, 6, z, "stone_brick", top: true) } }
            for x in -1...9 { for z in -1...2 where x == -1 || x == 9 || z == -1 || z == 2 { d.slab(x, 8, z, "stone_brick") } }
            d.put(4, 5, 0, "lantern", 1); d.put(4, 5, 1, "lantern", 1)
            for x in 2...6 { for y in 0...5 { for z in 0...1 { if d.cells[IVec3(x, y, z)] == nil { d.air.insert(IVec3(x, y, z)) } } } }
            for x in [0, 1, 7, 8] { for z in 0...1 { d.footprint.append((x, z)) } }
            out.append(Blueprint(key: "gate", title: ["Stone Gate", "on the rocks"], ground: "rocky", footing: .terrace, draft: d))
        }
        return out
    }

    // MARK: Sites

    struct Site { let kind: String; let origin: IVec3 }

    // The ground under a column: the top cell of the field's ground (or, in a block world, the top natural block),
    // under trees, plants and water.
    static func groundY(_ w: World, _ x: Int, _ z: Int) -> Int {
        var y = min(CH - 2, w.topY(x, z) + 1)
        while y > 1 {
            if w.fieldTerrain ? w.groundAt(x, y, z) : (SmoothTerrain.natural[Int(w.block(x, y, z))] && Blocks.collide[Int(w.block(x, y, z))]) { return y }
            y -= 1
        }
        return y
    }
    static func surface(_ w: World, _ x: Int, _ z: Int) -> String {
        let y = groundY(w, x, z)
        return Blocks.key(Blocks.groupBase[Int(w.materialAt(x, y, z))])
    }
    static func water(_ w: World, _ x: Int, _ z: Int) -> Bool {
        let y = groundY(w, x, z)
        return Blocks.isLiquid(w.block(x, y + 1, z))
    }

    static func maybe(_ w: World, _ x0: Int, _ z0: Int, kinds: [String]) -> Bool {
        var hs: [Int] = [], wet = 0, beach = 0, wood = 0, rock = 0
        for z in stride(from: 0, through: 10, by: 2) { for x in stride(from: 0, through: 10, by: 2) {
            let c = w.gen.column(x0 + x, z0 + z)
            hs.append(c.height)
            if c.height < SEA { wet += 1 }
            switch c.biome {
            case .beach, .snowyBeach: beach += 1
            case .stonyShore, .windsweptHills, .windsweptGravellyHills, .stonyPeaks, .jaggedPeaks, .grove, .snowySlopes: rock += 1
            case .forest, .flowerForest, .birchForest, .oldGrowthBirchForest, .darkForest, .taiga, .oldGrowthPineTaiga,
                 .oldGrowthSpruceTaiga, .snowyTaiga, .windsweptForest, .jungle, .sparseJungle, .paleGarden, .cherryGrove: wood += 1
            default: break
            }
        } }
        let lo = hs.min() ?? 0, hi = hs.max() ?? 0, n = hs.count
        for k in kinds {
            switch k {
            case "slope": if wet == 0 && hi - lo >= 3 && hi - lo <= 10 { return true }
            case "beach": if (beach > 0 || wet > 0) && wet <= n / 2 && hi - lo <= 5 { return true }
            case "shore": if wet >= n / 5 && wet <= n * 3 / 5 && hi - lo <= 8 { return true }
            case "forest": if wet == 0 && wood > n / 2 && hi - lo <= 5 { return true }
            case "rocky": if wet == 0 && hi - lo <= 7 && (rock > 0 || lo > SEA + 30) { return true }
            case "hilltop":
                if wet == 0 && hi - lo <= 4 && lo > SEA + 10 {
                    var top = true
                    for (ox, oz) in [(-14, 5), (24, 5), (5, -14), (5, 24)] where top { if w.gen.column(x0 + ox, z0 + oz).height > lo - 3 { top = false } }
                    if top { return true }
                }
            default: return true
            }
        }
        return false
    }

    // Each kind of ground, the nearest spot to `centre` that fits it (a grid 12 apart, 600 out), each 40 or more from
    // the others. Loads what it reads.
    static func findSites(_ w: World, centre: V3, kinds: [String]) -> [String: IVec3] {
        var found: [String: IVec3] = [:]
        var cand: [(Int, Int)] = []
        let step = 12, reach = 600
        for r in stride(from: 0, through: reach, by: step) {
            if r == 0 { cand.append((0, 0)); continue }
            for i in stride(from: -r, to: r, by: step) {
                cand.append((i, -r)); cand.append((r, i)); cand.append((-i, r)); cand.append((-r, -i))
            }
        }
        let cx = Int(centre.x), cz = Int(centre.z)
        for (dx, dz) in cand {
            if kinds.allSatisfy({ found[$0] != nil }) { break }
            let x0 = cx + dx, z0 = cz + dz
            if found.values.contains(where: { abs($0.x - x0) < 40 && abs($0.z - z0) < 40 }) { continue }
            // A first look from the generator's own columns (no chunk made): only a spot that could be one of the kinds
            // still wanted is loaded and read cell by cell.
            if !maybe(w, x0, z0, kinds: kinds.filter { found[$0] == nil }) { continue }
            _ = w.loadSync(center: V3(Float(x0), 100, Float(z0)), radius: 1)
            var hs: [Int] = [], sand = 0, wet = 0, rock = 0, snow = 0, grass = 0
            for z in stride(from: 0, through: 10, by: 2) { for x in stride(from: 0, through: 10, by: 2) {
                hs.append(groundY(w, x0 + x, z0 + z))
                let s = surface(w, x0 + x, z0 + z)
                if water(w, x0 + x, z0 + z) { wet += 1 }
                if s.contains("sand") { sand += 1 } else if s == "stone" || s == "andesite" || s == "granite" || s == "diorite" || s == "tuff" { rock += 1 }
                else if s.contains("snow") { snow += 1 } else if s.contains("grass") || s == "dirt" { grass += 1 }
            } }
            let lo = hs.min() ?? 0, hi = hs.max() ?? 0, n = hs.count
            var trunks = 0
            for z in stride(from: -6, through: 16, by: 1) { for x in stride(from: -6, through: 16, by: 1) {
                let t = w.topY(x0 + x, z0 + z)
                let b = Blocks.key(Blocks.groupBase[Int(w.block(x0 + x, groundY(w, x0 + x, z0 + z) + 1, z0 + z))])
                if b.hasSuffix("_log") && t > groundY(w, x0 + x, z0 + z) + 4 { trunks += 1 }
            } }
            func take(_ k: String) { if found[k] == nil && kinds.contains(k) { found[k] = IVec3(x0, 0, z0) } }
            if wet == 0 && grass > n / 2 && hi - lo >= 4 && hi - lo <= 8 { take("slope") }
            if sand > n / 2 && wet >= 2 && wet <= n / 3 && lo >= SEA - 2 { take("beach") }
            if wet >= n / 4 && wet <= n / 2 && hi - lo <= 6 { take("shore") }
            if wet == 0 && trunks >= 5 && hi - lo <= 3 { take("forest") }
            if wet == 0 && rock > n / 2 && hi - lo <= 5 { take("rocky") }
            if wet == 0 && hi - lo <= 3 && lo > SEA + 12 {
                // a hilltop: higher than the ground 14 out all round
                var top = true
                for (ox, oz) in [(-14, 5), (24, 5), (5, -14), (5, 24), (-10, -10), (20, 20), (-10, 20), (20, -10)] where top {
                    _ = w.loadSync(center: V3(Float(x0 + ox), 100, Float(z0 + oz)), radius: 0)
                    if groundY(w, x0 + ox, z0 + oz) > lo - 3 { top = false }
                }
                if top { take("hilltop") }
            }
        }
        return found
    }

    // Where a blueprint goes on its site: the floor's height and the jobs (cells to dig, then blocks to place, in the
    // order the builder works).
    struct Job { let cell: IVec3; let want: BlockID }     // want AIR: dig
    struct Placement { let bp: Blueprint; let origin: IVec3; let jobs: [Job]; let lo: IVec3; let hi: IVec3 }

    static func place(_ bp: Blueprint, on w: World, at site: IVec3) -> Placement {
        let d = bp.draft
        var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
        for p in Array(d.cells.keys) + Array(d.air) { lo = IVec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)); hi = IVec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)) }
        // The floor: terrace = the middle of the ground under the footprint; stilts = its top plus the stilts' height;
        // dock = one over the water (or the shore's ground, whichever is higher, under the hut).
        var gs: [Int] = []
        for (x, z) in (d.footprint.isEmpty ? d.posts.map { ($0.x, $0.z) } : d.footprint) { gs.append(groundY(w, site.x + x, site.z + z)) }
        gs.sort()
        let mid = gs.isEmpty ? SEA : gs[gs.count / 2]
        var fy: Int
        switch bp.footing {
        case .terrace: fy = mid + 1
        case .stilts(let h): fy = (gs.last ?? mid) + h + 1
        case .dock:
            var surf = SEA
            for z in 0...10 { for x in 0...4 where Blocks.isLiquid(w.block(site.x + x, groundY(w, site.x + x, site.z + z) + 1, site.z + z)) {
                var y = groundY(w, site.x + x, site.z + z) + 1
                while Blocks.isLiquid(w.block(site.x + x, y + 1, site.z + z)) { y += 1 }
                surf = max(surf, y)
            } }
            fy = max(surf + 1, mid + 1)
        }
        let o = IVec3(site.x, fy, site.z)
        var digs: [IVec3] = [], places: [(IVec3, BlockID)] = []
        func natural(_ q: IVec3) -> Bool {
            let b = w.block(q.x, q.y, q.z)
            if Blocks.isLiquid(b) { return false }
            return (w.fieldTerrain && w.groundAt(q.x, q.y, q.z)) || (b != AIR)
        }
        // What has to go: anything in the build's cells and its kept-clear cells (trees, plants, ground), and the trees
        // over it; dug from the top down.
        var dig = Set<IVec3>()
        for p in Array(d.cells.keys) + Array(d.air) {
            let q = o + p
            if natural(q) { dig.insert(q) }
        }
        // (a tree's trunk and crown over the build come down too, up to 12 above it)
        for x in lo.x...hi.x { for z in lo.z...hi.z { for y in (hi.y + 1)...(hi.y + 12) {
            let q = o + IVec3(x, y, z)
            let k = Blocks.key(Blocks.groupBase[Int(w.block(q.x, q.y, q.z))])
            if k.hasSuffix("_log") || k.hasSuffix("_leaves") { dig.insert(q) }
        } } }
        digs = dig.sorted { $0.y != $1.y ? $0.y > $1.y : ($0.x, $0.z) < ($1.x, $1.z) }
        // Footing: under each footprint cell down to the ground; posts down to the ground or the bed.
        var foot: [IVec3: BlockID] = [:]
        let fk = Draft.id(d.footKey)
        for (x, z) in d.footprint {
            var y = fy - 1
            while y > fy - 24 && !(w.fieldTerrain ? w.groundAt(o.x + x, y, o.z + z) : SmoothTerrain.natural[Int(w.block(o.x + x, y, o.z + z))]) {
                foot[IVec3(o.x + x, y, o.z + z)] = fk; y -= 1
            }
        }
        for post in d.posts {
            var y = fy - 1
            while y > fy - 40 && !(w.fieldTerrain ? w.groundAt(o.x + post.x, y, o.z + post.z) : SmoothTerrain.natural[Int(w.block(o.x + post.x, y, o.z + post.z))]) {
                foot[IVec3(o.x + post.x, y, o.z + post.z)] = Draft.id(post.key); y -= 1
            }
        }
        for (p, b) in foot { places.append((p, b)) }
        for (p, b) in d.cells { places.append((o + p, b)) }
        // Bottom up; in a course, the middle first (a room's lantern before its walls, a wall before its eaves); a door's
        // upper half after its lower.
        let mx = Float(o.x) + Float(lo.x + hi.x) / 2, mz = Float(o.z) + Float(lo.z + hi.z) / 2
        places.sort { a, b in
            if a.0.y != b.0.y { return a.0.y < b.0.y }
            let da = (Float(a.0.x) - mx) * (Float(a.0.x) - mx) + (Float(a.0.z) - mz) * (Float(a.0.z) - mz)
            let db = (Float(b.0.x) - mx) * (Float(b.0.x) - mx) + (Float(b.0.z) - mz) * (Float(b.0.z) - mz)
            return da != db ? da < db : (a.0.x, a.0.z) < (b.0.x, b.0.z)
        }
        // (a door is placed once, from its lower half: the game sets both)
        places.removeAll { Blocks.shape[Int($0.1)] == "door" && Int($0.1 - Blocks.groupBase[Int($0.1)]) & 8 != 0 }
        let jobs = digs.map { Job(cell: $0, want: AIR) } + places.map { Job(cell: $0.0, want: $0.1) }
        return Placement(bp: bp, origin: o, jobs: jobs, lo: o + lo, hi: o + hi)
    }

    // Whether a cell holds what was wanted: the same state, or for a fence, a pane or a wall (whose state follows its
    // neighbours) the same block. A dig: nothing solid left in the cell.
    static func holds(_ w: World, _ j: Job) -> Bool {
        let b = w.block(j.cell.x, j.cell.y, j.cell.z)
        if j.want == AIR {
            if Blocks.isLiquid(b) { return true }
            return !(w.fieldTerrain && w.groundAt(j.cell.x, j.cell.y, j.cell.z)) && (b == AIR || Blocks.isLiquid(b))
        }
        if b == j.want { return true }
        guard Blocks.groupBase[Int(b)] == Blocks.groupBase[Int(j.want)] else { return false }
        if Blocks.connectKind[Int(j.want)] != 0 { return true }
        if Blocks.shape[Int(j.want)] == "door" { return Int(b - Blocks.groupBase[Int(b)]) & 3 == Int(j.want - Blocks.groupBase[Int(j.want)]) & 3 && Int(b - Blocks.groupBase[Int(b)]) & 8 == 0 }
        return false
    }
}
