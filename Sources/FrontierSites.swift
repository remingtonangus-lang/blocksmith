import Foundation
import simd

// D48: landmarks of the open country and settlements that belong to their biome. The canyons themselves are the
// big landforms of Landmarks.swift; these are the places people built (or left) across the land:
//   ghost_town    dry or open country away from spawn: a dusty street of four wind-wrecked plank buildings (a saloon,
//                 a store, a bank and a house), holes in their walls and roofs, cobwebs and dead brush, a dry well and
//                 a gallows. A strongbox chest in the bank, odds and ends in the others. After dark the dead walk its
//                 street (zombies, husks in the desert) once a night.
//   homestead     farm country: a family's log cabin (the wood of the land: spruce in the north, acacia on the savanna,
//                 birch in birch woods), a fenced paddock of cows, sheep and chickens, a watered wheat field, a hay
//                 lean-to and the homesteader at the porch, who sells bread, milk and meat to a passing rider.
//   stilt_hamlet  swamps and mangroves: three huts on log stilts over the water, joined by plank walks with ladders down,
//                 lanterns on posts, lily pads; two fishers live there.
//   pueblo        badlands: stacked terracotta houses in three tiers stepping back, ladders up the faces, flat roofs,
//                 a shaded plaza with a well; two potters live there.
// Structure type "frontier_site" (a 60 % chance per 28 x 28-chunk region; the kind is the biome's). Each goes on the
// map when you come within 64 blocks. Ground saved before these keeps its land (structure-guard-sites.txt).
enum FrontierSites {
    static let kind = "frontier_site"
    static let spacing = 28, separation = 8
    static let chance: Float = 0.6
    static let reachBlocks = 18
    static let ghostMinSpawn: Float = 500

    static let ghostLand: Set<Biome> = [.desert, .badlands, .woodedBadlands, .erodedBadlands, .savanna, .windsweptSavanna, .plains, .snowyPlains]
    static let farmLand: Set<Biome> = [.plains, .sunflowerPlains, .meadow, .forest, .flowerForest, .birchForest, .taiga, .snowyTaiga,
                                       .savanna, .snowyPlains, .cherryGrove]
    static let swampLand: Set<Biome> = [.swamp, .mangroveSwamp]
    static let mesaLand: Set<Biome> = [.badlands, .woodedBadlands, .erodedBadlands, .savannaPlateau]

    static let names: [String: String] = ["ghost_town": "Ghost town", "homestead": "Homestead", "stilt_hamlet": "Stilt hamlet", "pueblo": "Pueblo"]

    static let loot: [String: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)])] = [
        "ghost_bank": (3...5, [("gold_nugget", 4, 14, 20), ("gold_ingot", 1, 3, 10), ("emerald", 1, 4, 10), ("iron_nugget", 3, 9, 12),
                               ("paper", 1, 4, 10), ("name_tag", 1, 1, 3), ("map", 1, 1, 4), ("empty", 1, 1, 10)]),
        "ghost_town": (2...4, [("bone", 1, 4, 16), ("rotten_flesh", 1, 3, 12), ("string", 1, 3, 12), ("glass_bottle", 1, 3, 10),
                               ("leather", 1, 3, 10), ("iron_nugget", 1, 6, 10), ("torch", 2, 6, 10), ("saddle", 1, 1, 3),
                               ("compass", 1, 1, 2), ("empty", 1, 1, 14)]),
        "homestead": (3...6, [("wheat", 2, 8, 20), ("bread", 1, 4, 16), ("wheat_seeds", 2, 8, 14), ("egg", 1, 4, 10), ("leather", 1, 3, 10),
                              ("milk_bucket", 1, 1, 4), ("apple", 1, 4, 10), ("iron_hoe", 1, 1, 3), ("lead", 1, 1, 4), ("bucket", 1, 1, 4)]),
        "stilt_hamlet": (3...5, [("cod", 1, 4, 18), ("salmon", 1, 3, 12), ("fishing_rod", 1, 1, 6), ("string", 1, 4, 12), ("slime_ball", 1, 3, 8),
                                 ("lily_pad", 1, 3, 10), ("clay_ball", 2, 6, 10), ("bowl", 1, 2, 8), ("emerald", 1, 2, 4)]),
        "pueblo": (3...5, [("clay_ball", 2, 8, 18), ("brick", 2, 6, 14), ("flower_pot", 1, 2, 8), ("dried_kelp", 1, 4, 6), ("bread", 1, 3, 12),
                           ("gold_nugget", 2, 8, 10), ("red_dye", 1, 3, 8), ("orange_dye", 1, 3, 8), ("emerald", 1, 3, 6), ("leather", 1, 2, 8)]),
    ]

    static func b(_ name: String, _ fallback: String = "oak_planks") -> BlockID { WildCamps.b(name, fallback) }

    // MARK: Placement

    static func type(_ gen: WorldGen) -> StructureType {
        StructureType(name: kind, spacing: spacing, separation: separation, salt: 52719133, reach: 2) { [unowned gen] seed, cx, cz in
            if let sc = gen.structures, !sc.clear(cx: cx, cz: cz, reach: 2, guardSet: sc.legacySites) { return nil }
            var rng = SRng(seed &+ 0xF207)
            guard rng.chance(chance) else { return nil }
            let x = cx * CS + 8, z = cz * CS + 8
            let col = gen.column(x, z)
            let k = gen.terrain.column(x, z)
            guard k.vol < 0.02, k.cyn < 0.05 else { return nil }
            let bio = col.biome
            let spawnD = simd_length(V2(Float(x), Float(z)) - WorldRules.spawnCentre(gen))
            guard spawnD > 160 else { return nil }
            var options: [String] = []
            if swampLand.contains(bio) { options += ["stilt_hamlet", "stilt_hamlet"] }
            if mesaLand.contains(bio) { options += ["pueblo", "pueblo"] }
            if farmLand.contains(bio) { options += ["homestead", "homestead"] }
            if ghostLand.contains(bio) && spawnD > ghostMinSpawn { options.append("ghost_town") }
            guard !options.isEmpty else { return nil }
            let site = options[rng.int(options.count)]
            let r = reachBlocks - 1
            let y: Int
            if site == "stilt_hamlet" {
                // Low, wet ground: no column far above or below the water.
                for (dx, dz) in [(0, 0), (-12, -12), (12, -12), (-12, 12), (12, 12), (0, -14), (0, 14), (-14, 0), (14, 0)] {
                    let c = gen.column(x + dx, z + dz)
                    if c.height > SEA + 4 || c.height < SEA - 5 || c.biome.isOcean { return nil }
                }
                y = SEA + 3
            } else {
                y = gen.groundY(x, z)
                guard y > SEA else { return nil }
                let q = 12
                for (dx, dz) in [(-q, -q), (q, -q), (-q, q), (q, q), (0, -r), (0, r), (-r, 0), (r, 0), (-6, -6), (6, 6), (-6, 6), (6, -6)] {
                    let c = gen.column(x + dx, z + dz)
                    if abs(c.height - y) > 4 || c.height <= SEA || c.biome.isOcean || c.biome == .river || c.biome == .frozenRiver { return nil }
                }
            }
            if crowded(gen, x, z) { return nil }
            let s = rng.next(), rot = rng.int(4)
            let st = StructureStart(kind: site, pieces: [Piece(min: IVec3(x - reachBlocks, y - 10, z - reachBlocks),
                                                               max: IVec3(x + reachBlocks, y + 12, z + reachBlocks)) { w in
                build(&w, site, bio, x, y, z, rot, s)
            }], anchor: IVec3(x, y + 1, z))
            return st
        }
    }

    // Every older surface find keeps its ground.
    static func crowded(_ gen: WorldGen, _ x: Int, _ z: Int) -> Bool {
        guard let sc = gen.structures else { return false }
        let keep: [(String, Int)] = [("village", 110), ("pillager_outpost", 80), ("temple", 50), ("military_base", 180), ("capital_city", 250),
                                     ("boreal_station", 90), ("mansion", 100), ("trail_ruins", 50), ("great_ruin", 120), ("desert_well", 36),
                                     ("wild_camp", 50), (Greywall.kind, 130), (NavalPort.kind, 80), ("shipwreck", 40)]
        for (k, m) in keep {
            guard let o = sc.nearest(k, x: x, z: z, maxRegions: 1) else { continue }
            if o.max.x >= x - m && o.min.x <= x + m && o.max.z >= z - m && o.min.z <= z + m { return true }
        }
        return false
    }

    // MARK: Building

    static func wood(_ bio: Biome) -> String {
        switch bio {
        case .taiga, .snowyTaiga, .snowyPlains: return "spruce"
        case .savanna, .windsweptSavanna, .savannaPlateau: return "acacia"
        case .birchForest: return "birch"
        case .cherryGrove: return Blocks.has("cherry_planks") ? "cherry" : "oak"
        case .mangroveSwamp: return Blocks.has("mangrove_planks") ? "mangrove" : "oak"
        case .desert, .badlands, .woodedBadlands, .erodedBadlands: return "dark_oak"
        default: return "oak"
        }
    }

    static func build(_ w: inout StructWriter, _ site: String, _ bio: Biome, _ x: Int, _ y: Int, _ z: Int, _ rot: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let f = WildCamps.Frame(x: x, y: y + 1, z: z, rot: rot)
        let s32 = UInt32(truncatingIfNeeded: seed)
        if site != "stilt_hamlet" { WildCamps.level(&w, x, y, z, seed, r: reachBlocks - 1, flatR: Float(reachBlocks) - 4.5) }
        func put(_ dx: Int, _ dy: Int, _ dz: Int, _ blk: BlockID) { let (px, pz) = f.p(dx, dz); w.set(px, f.y + dy, pz, blk) }
        func get(_ dx: Int, _ dy: Int, _ dz: Int) -> BlockID { let (px, pz) = f.p(dx, dz); return w.get(px, f.y + dy, pz) }
        func down(_ dx: Int, _ dy: Int, _ dz: Int, _ blk: BlockID) { let (px, pz) = f.p(dx, dz); w.groundDown(px, f.y + dy, pz, blk, minY: f.y - 16) }
        func chest(_ dx: Int, _ dy: Int, _ dz: Int, _ table: String) {
            let (px, pz) = f.p(dx, dz)
            w.chest(px, f.y + dy, pz, loot: table, seed: rng.next(), facing: Int(f.north))
        }
        func mob(_ m: String, _ dx: Int, _ dy: Int, _ dz: Int) { let (px, pz) = f.p(dx, dz); w.mob(m, V3(Float(px) + 0.5, Float(f.y + dy), Float(pz) + 0.5)) }
        func holed(_ a: Int, _ b2: Int, _ c: Int, _ p: Float) -> Bool { hashf(a &+ x, b2, c &+ z, s32) < p }
        // A box of walls (x0...x1, z0...z1), `h` high, with a doorway on one side (local -x side when doorX, at z = doorZ).
        func shell(_ x0: Int, _ x1: Int, _ z0: Int, _ z1: Int, _ h: Int, wall: BlockID, corner: BlockID, floor: BlockID, roof: BlockID,
                   door: (Int, Int), ruin: Float, roofRuin: Float) {
            for dz in z0...z1 { for dx in x0...x1 {
                put(dx, -1, dz, floor)
                let edge = dx == x0 || dx == x1 || dz == z0 || dz == z1
                let cornerP = (dx == x0 || dx == x1) && (dz == z0 || dz == z1)
                for dy in 0..<h {
                    if !edge { put(dx, dy, dz, AIR); continue }
                    if dx == door.0 && dz == door.1 && dy < 2 { put(dx, dy, dz, AIR); continue }
                    if !cornerP && holed(dx, dy * 7 + 1, dz, ruin * Float(dy + 1) / Float(h)) { put(dx, dy, dz, AIR); continue }
                    put(dx, dy, dz, cornerP ? corner : (dy == 1 && (dx + dz) % 3 == 0 && ruin < 0.05 ? b("glass_pane", "glass") : wall))
                }
                if !holed(dx, 91, dz, roofRuin) { put(dx, h, dz, roof) }
            } }
        }

        switch site {
        case "ghost_town":
            let wd = wood(bio)
            let plank = b("\(wd)_planks"), log = b("\(wd)_log", "oak_log"), slab = b("\(wd)_slab", "oak_slab"), fence = b("\(wd)_fence", "oak_fence")
            let path = b("coarse_dirt", "dirt"), web = b("cobweb", "air"), brush = b("dead_bush", "air")
            // The street along local z, packed earth and wheel ruts.
            for dz in -15...15 { for dx in -2...2 where !holed(dx, 3, dz, 0.25) { put(dx, -1, dz, path) } }
            // Four buildings, two a side, their doorways on the street.
            let lots: [(Int, Int, String)] = [(-9, -8, "saloon"), (-9, 6, "store"), (4, -8, "bank"), (4, 6, "house")]
            for (ox, oz, what) in lots {
                let x0 = ox, x1 = ox + 5, z0 = oz - 3, z1 = oz + 3
                let doorX = ox < 0 ? x1 : x0
                let tall = what == "saloon" ? 5 : 4
                shell(x0, x1, z0, z1, tall, wall: plank, corner: log, floor: plank, roof: slab, door: (doorX, oz),
                      ruin: what == "bank" ? 0.12 : 0.3, roofRuin: 0.35)
                // A false front over the street for the saloon and store.
                if what == "saloon" || what == "store" { for dz in z0...z1 { for dy in tall...(tall + 1) where !holed(doorX, dy, dz, 0.2) { put(doorX, dy, dz, plank) } } }
                // Porch posts and boards.
                let px = ox < 0 ? x1 + 1 : x0 - 1
                for dz in z0...z1 { put(px, -1, dz, plank) }
                for dz in [z0, z1] { put(px, 0, dz, fence); put(px, 1, dz, fence); put(px, 2, dz, slab) }
                let ix = ox < 0 ? x0 + 1 : x1 - 1
                put(ix, 0, z0 + 1, web); put(ix, tall - 1, z1 - 1, web)
                switch what {
                case "saloon":
                    for dz in (z0 + 1)...(z1 - 2) { put(ix, 0, dz, b("\(wd)_planks")) }       // the bar
                    put(ix + (ox < 0 ? 1 : -1), 0, z1 - 1, b("barrel")); chest(ix, 0, z1 - 1, "ghost_town")
                case "store":
                    put(ix, 0, z0 + 1, b("barrel")); put(ix, 1, z0 + 1, b("barrel")); chest(ix, 0, z1 - 1, "ghost_town")
                case "bank":
                    for dz in (z0 + 1)...(z1 - 1) { put(ix + (ox < 0 ? 1 : -1), 0, dz, b("iron_bars", "oak_fence")) }   // the teller's grille
                    chest(ix, 0, z0 + 1, "ghost_bank")
                default:
                    put(ix, 0, z0 + 1, b("crafting_table")); put(ix, 0, z1 - 1, b("white_wool")); chest(ix, 0, oz, "ghost_town")
                }
            }
            // A dry well in the street, a gallows at the far end, tumbleweed brush and fallen boards.
            for (dx, dz) in [(-1, 0), (1, 0), (0, -1), (0, 1)] { put(dx, 0, dz, b("cobblestone", "stone")) }
            put(0, -1, 0, AIR); put(0, -2, 0, AIR); put(0, -3, 0, b("gravel"))
            for dy in 0...3 { put(-1, dy, -1, fence); put(1, dy, 1, fence) }
            put(-1, 4, -1, slab); put(0, 4, 0, slab); put(1, 4, 1, slab)
            for dy in 0...3 { put(-2, dy, 14, log); put(2, dy, 14, log) }
            for dx in -2...2 { put(dx, 4, 14, log) }
            put(0, 3, 14, b("chain", "oak_fence"))
            for i in 0..<10 {
                let dx = Int(hashf(i, 1, 7, s32) * 30) - 15, dz = Int(hashf(i, 2, 7, s32) * 30) - 15
                if get(dx, 0, dz) == AIR && Blocks.collide[Int(get(dx, -1, dz))] { put(dx, 0, dz, i % 3 == 0 ? slab : brush) }
            }

        case "homestead":
            let wd = wood(bio)
            let plank = b("\(wd)_planks"), log = b("\(wd)_log", "oak_log"), fence = b("\(wd)_fence", "oak_fence"), slab = b("\(wd)_slab", "oak_slab")
            let stairs = b("\(wd)_stairs", "oak_stairs")
            // The cabin: logs, a plank floor and a pitched slab roof, the door to the yard.
            shell(-10, -3, -12, -6, 3, wall: log, corner: log, floor: plank, roof: plank, door: (-3, -9), ruin: 0, roofRuin: 0)
            for dx in -10...(-3) { for (dz, dy) in [(-12, 3), (-11, 4), (-10, 4), (-9, 5), (-8, 4), (-7, 4), (-6, 3)] { put(dx, dy, dz, dy == 5 ? slab : plank) } }
            for dz in -11...(-7) { put(-11, 3, dz, stairs) }
            put(-9, 0, -11, b("furnace")); put(-8, 0, -11, b("crafting_table")); chest(-4, 0, -11, "homestead")
            put(-9, 0, -7, b("red_wool", "white_wool")); put(-8, 0, -7, b("red_wool", "white_wool"))      // the cot
            put(-6, 2, -11, b("lantern", "torch"))
            for dz in -12...(-6) { put(-2, -1, dz, plank) }                                    // the porch
            put(-2, 0, -12, fence); put(-2, 0, -6, fence); put(-2, 1, -12, fence); put(-2, 1, -6, fence)
            put(-2, 0, -8, b("barrel"))
            mob("villager:camper", -1, 0, -9)                                                 // the homesteader on the porch
            // The paddock: a fence ring with a gate gap and stock.
            for dx in 2...12 { for dz in -12...(-4) where dx == 2 || dx == 12 || dz == -12 || dz == -4 {
                if dx == 2 && dz == -8 { continue }
                put(dx, 0, dz, fence)
            } }
            put(10, 0, -10, b("hay_block")); put(4, 0, -6, b("water_cauldron", "cauldron"))
            mob("cow", 6, 0, -8); mob("cow", 9, 0, -6); mob("sheep", 8, 0, -10); mob("chicken", 5, 0, -10); mob("chicken", 10, 0, -7)
            // The field: watered farmland with wheat at every stage, a log border.
            for dz in 2...10 { for dx in -10...(-1) {
                let edge = dx == -10 || dx == -1 || dz == 2 || dz == 10
                if edge { put(dx, -1, dz, f.log(wd == "dark_oak" ? "oak" : wd, alongX: dz == 2 || dz == 10)) }
                else if dx == -6 { put(dx, -1, dz, WATER) }
                else { put(dx, -1, dz, b("farmland_moist", "farmland")); put(dx, 0, dz, b("wheat", "air") + BlockID(rng.int(8))) }
            } }
            put(-1, 0, 2, b("composter", "barrel"))
            // The hay lean-to.
            for dz in 4...8 { put(4, 0, dz, log); put(4, 1, dz, log); put(4, 2, dz, slab); put(6, 2, dz, slab); put(5, 2, dz, slab) }
            for dz in 5...7 { put(5, 0, dz, b("hay_block")); put(6, 0, dz, b("hay_block")) }
            put(5, 1, 6, b("hay_block"))

        case "stilt_hamlet":
            let wd = wood(bio)
            let plank = b("\(wd)_planks"), log = b("\(wd)_log", "oak_log"), fence = b("\(wd)_fence", "oak_fence"), slab = b("\(wd)_slab", "oak_slab")
            let deck = 2                                             // deck height above f.y (y + 1): sea + 6
            // Three huts on stilts, joined by walks.
            let huts: [(Int, Int)] = [(-8, -7), (7, -6), (0, 8)]
            for (hx, hz) in huts {
                for dz in (hz - 2)...(hz + 2) { for dx in (hx - 2)...(hx + 2) {
                    put(dx, deck - 1, dz, plank)
                    let edge = abs(dx - hx) == 2 || abs(dz - hz) == 2
                    let cornerP = abs(dx - hx) == 2 && abs(dz - hz) == 2
                    if cornerP { down(dx, deck - 2, dz, log) }
                    for dy in 0...2 {
                        if !edge { put(dx, deck + dy, dz, AIR); continue }
                        if dz == hz + (hz < 0 ? 2 : -2) && dx == hx && dy < 2 { put(dx, deck + dy, dz, AIR); continue }   // doorway toward the middle
                        put(dx, deck + dy, dz, cornerP ? log : plank)
                    }
                    put(dx, deck + 3, dz, slab)
                } }
                put(hx, deck + 2, hz, b("lantern", "torch"))
                put(hx - 1, deck, hz + (hz < 0 ? -1 : 1), b("barrel"))
            }
            chest(-8, deck, -8, "stilt_hamlet")
            mob("villager:camper", 7, deck, -6)
            mob("villager:camper", 0, deck, 8)
            // Walks from each hut to a central landing, railed, with a ladder down to the water.
            for dz in -2...2 { for dx in -2...2 { put(dx, deck - 1, dz, plank) } }
            down(-2, deck - 2, -2, log); down(2, deck - 2, 2, log); down(-2, deck - 2, 2, log); down(2, deck - 2, -2, log)
            func walk(_ ax: Int, _ az: Int, _ bx: Int, _ bz: Int) {
                let n = max(abs(bx - ax), abs(bz - az))
                guard n > 0 else { return }
                for i in 0...n {
                    let px = ax + (bx - ax) * i / n, pz = az + (bz - az) * i / n
                    put(px, deck - 1, pz, plank)
                    if i % 4 == 2 { down(px, deck - 2, pz, fence) }
                }
            }
            walk(0, 0, -8, -4); walk(0, 0, 7, -3); walk(0, 0, 0, 5)
            for dy in -6...(deck - 1) where get(3, dy, 0) == AIR || get(3, dy, 0) == WATER { put(3, dy, 0, b("ladder") + f.north) }
            for (dx, dz) in [(-2, -2), (2, 2)] { put(dx, deck, dz, fence); put(dx, deck + 1, dz, b("lantern", "torch")) }
            // Lily pads on open water round about.
            for i in 0..<16 {
                let dx = Int(hashf(i, 5, 3, s32) * 32) - 16, dz = Int(hashf(i, 6, 3, s32) * 32) - 16
                let (px, pz) = f.p(dx, dz)
                if w.inside(px, SEA, pz) && w.get(px, SEA, pz) == WATER && w.get(px, SEA + 1, pz) == AIR { w.set(px, SEA + 1, pz, b("lily_pad", "air")) }
            }

        case "pueblo":
            let walls = [b("terracotta", "sandstone"), b("orange_terracotta", "sandstone"), b("white_terracotta", "smooth_sandstone")]
            let roof = b("smooth_sandstone", "sandstone"), beam = b("dark_oak_log", "oak_log"), ladder = b("ladder")
            // Three tiers stepping back from the plaza (toward local -z): each a row of rooms over the one before.
            let tiers: [(Int, Int, Int, Int)] = [(-12, 12, -12, -4), (-10, 10, -12, -7), (-7, 7, -12, -10)]   // x0, x1, z0, z1
            for (t, (x0, x1, z0, z1)) in tiers.enumerated() {
                let base = t * 3
                for dz in z0...z1 { for dx in x0...x1 {
                    let edge = dx == x0 || dx == x1 || dz == z0 || dz == z1
                    for dy in 0...2 {
                        let room = (dx - x0) % 5 == 0
                        if edge || room { put(dx, base + dy, dz, walls[(t + (dx - x0) / 5) % 3]) } else { put(dx, base + dy, dz, AIR) }
                    }
                    put(dx, base + 3, dz, roof)
                    if t == 0 { put(dx, -1, dz, b("terracotta", "sandstone")) }
                } }
                // Doorways onto the plaza or the roof below, beam ends poking out, a ladder up each face.
                for dx in stride(from: x0 + 2, to: x1, by: 5) { put(dx, base, z1, AIR); put(dx, base + 1, z1, AIR) }
                for dx in stride(from: x0 + 1, to: x1, by: 3) { put(dx, base + 2, z1 + 1, beam) }
                if t < 2 { for dy in 0...3 { put(x0 + 3, base + dy, z1 + 1, ladder + f.north) } }
                // Clear the step-back terrace: the roof below stays open.
                for dz in (z1 + 1)...(z1 + 2) where t > 0 { for dx in x0...x1 { put(dx, base, dz, AIR) } }
            }
            chest(-9, 0, -6, "pueblo")
            put(9, 0, -6, b("furnace")); put(8, 0, -6, b("flower_pot", "air"))
            // The plaza: packed earth, a well and a shade ramada.
            for dz in -3...10 { for dx in -10...10 where holed(dx, 11, dz, 0.4) { put(dx, -1, dz, b("coarse_dirt", "dirt")) } }
            for (dx, dz) in [(-1, 4), (1, 4), (0, 3), (0, 5)] { put(dx, 0, dz, b("terracotta", "sandstone")) }
            put(0, -1, 4, WATER)
            for (dx, dz) in [(5, 2), (9, 2), (5, 7), (9, 7)] { for dy in 0...2 { put(dx, dy, dz, beam) } }
            for dz in 2...7 { for dx in 5...9 where (dx + dz) % 2 == 0 { put(dx, 3, dz, b("dark_oak_slab", "oak_slab")) } }
            put(7, 0, 4, b("barrel")); put(-6, 0, 6, b("hay_block")); put(-7, 0, 6, b("barrel"))
            mob("villager:camper", 4, 0, 0)
            mob("villager:camper", -3, 3, -6)
            mob("donkey", -6, 0, 8)

        default: break
        }
    }

    // MARK: In play (TownLaw.tick, once a second)

    static var marked = Set<IVec3>()
    static var nightOf: [IVec3: Int] = [:]
    static var risen = 0                                   // (harness)

    static func sites(_ g: Game, near p: V3) -> [StructureStart] {
        guard let sc = g.world.gen.structures, let t = sc.types.first(where: { $0.name == kind }) else { return [] }
        return sc.startsNear(cx: floorDiv(Int(floor(p.x)), CS), cz: floorDiv(Int(floor(p.z)), CS), t)
    }

    static func tick(_ g: Game) {
        guard g.dim.dim == .overworld else { return }
        let p = g.player.pos
        for s in sites(g, near: p) {
            let a = s.anchor
            let d = simd_length(V2(p.x - Float(a.x), p.z - Float(a.z)))
            guard d < 64 else { continue }
            if !marked.contains(a) {
                marked.insert(a)
                MapCache.shared.discover(g, kind: s.kind, x: a.x, z: a.z, name: names[s.kind])
            }
            // The ghost town's dead, once a night, when you're in its street after dark.
            if s.kind == "ghost_town", g.survival, g.difficulty > 0, d < 40, g.daylight < 0.3, g.world.isLoaded(a.x, a.z) {
                let night = Int((g.time + DAY_LENGTH * 0.3) / DAY_LENGTH)
                guard nightOf[a] != night else { continue }
                nightOf[a] = night
                let dry = [Biome.desert, .badlands, .woodedBadlands, .erodedBadlands].contains(g.world.gen.column(a.x, a.z).biome)
                for i in 0..<4 {
                    let off = V3(Float(i % 2 == 0 ? -1 : 1) * Float(1 + i), 0, Float(i * 6 - 9))
                    let m = Mob(dry ? .husk : .zombie, at: g.world.freeSpawn(V3(Float(a.x) + 0.5, Float(a.y), Float(a.z) + 0.5) + off))
                    m.persistent = false
                    g.mobs.mobs.append(m)
                    risen += 1
                }
                g.onToast?("Something stirs in the empty street")
            }
        }
    }

    // Townsfolk.talkToTownsperson: a homesteader sells food to a rider passing by.
    static let farePrice = 300
    static func talk(_ g: Game, _ m: Mob) -> Bool {
        guard m.villager?.role == "camper",
              let s = sites(g, near: m.pos).first(where: { $0.kind == "homestead" && simd_length(V3(Float($0.anchor.x), Float($0.anchor.y), Float($0.anchor.z)) - m.pos) < 24 })
        else { return false }
        _ = s
        if g.survival && g.money < farePrice {
            Townsfolk.say(g, m, "Bread, milk and a cut of beef for \(Money.format(farePrice)), when you've the money."); return true
        }
        if g.survival { g.money -= farePrice }
        for (k, n) in [("bread", 3), ("cooked_beef", 2), ("milk_bucket", 1)] where Items.has(k) {
            g.drops.spawn(ItemStack(Items.id(k), n), at: g.player.pos + V3(0, 0.5, 0))
        }
        Townsfolk.say(g, m, ["Fresh this morning. Safe riding.", "Take it, it's a long way to town.", "The cow's been generous."][Int(g.clock) % 3])
        return true
    }
}
