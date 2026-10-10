import Foundation
import simd

// Wild camps (Remington, Oct 10): small, varied camps you stumble on in open country, each with a loot chest.
// Structure type "wild_camp" (an 85 % chance per 20 x 20-chunk region); the start's kind is the variant:
//   camp_hunters      forests and taigas: hide tent, campfire with log seats, a drying rack hung with hides, crates
//   camp_prospectors  hill country: a timber headframe over a test pit, an ore cart on a short track, ore and gravel
//                     heaps, a canvas lean-to, a grindstone
//   camp_traders      plains and savanna: a covered wagon on log wheels, a hitched donkey, hay, barrels and a trader
//   camp_abandoned    anywhere the others go: a collapsed tent, a cold fire, cobwebs, a looted crate
//   camp_outlaws      wooded or dry country away from spawn: two dark tents, a lookout platform, a Brigand and a
//                     Marauder on guard
// Placed on natural, fairly level dry ground in its biome, never on a volcano or in a canyon, and clear of every
// other surface structure. The camp ground is levelled (cut and filled) to its centre's height; trees keep out of
// its footprint (TreePlacer). `--campcheck` (WorldGenCheck.swift) counts and checks them over many seeds.
enum WildCamps {
    static let spacing = 20, separation = 5
    static let chance: Float = 0.85
    static let radius = 11                                 // ground worked out to here (flat to `flat`, then eased)
    static let flat: Float = 8.7
    static let kinds = ["camp_hunters", "camp_prospectors", "camp_traders", "camp_abandoned", "camp_outlaws"]

    static let woods: Set<Biome> = [.forest, .flowerForest, .birchForest, .oldGrowthBirchForest, .darkForest, .taiga,
                                    .oldGrowthPineTaiga, .oldGrowthSpruceTaiga, .snowyTaiga, .windsweptForest, .grove, .cherryGrove]
    static let hills: Set<Biome> = [.windsweptHills, .windsweptGravellyHills, .savannaPlateau, .badlands, .woodedBadlands, .meadow]
    static let open: Set<Biome> = [.plains, .sunflowerPlains, .savanna, .windsweptSavanna, .meadow, .snowyPlains, .desert]
    static let outlawLand: Set<Biome> = [.forest, .darkForest, .taiga, .oldGrowthSpruceTaiga, .savanna, .windsweptSavanna,
                                         .badlands, .woodedBadlands, .plains, .birchForest]
    static let outlawMinSpawn: Float = 400

    // Loot tables (Loot.fill falls back to these).
    static let loot: [String: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)])] = [
        "camp_hunters": (3...6, [("leather", 1, 4, 20), ("rabbit_hide", 1, 3, 12), ("cooked_beef", 1, 3, 12), ("cooked_porkchop", 1, 3, 10),
                                 ("cooked_rabbit", 1, 2, 8), ("arrow", 4, 12, 14), ("string", 1, 4, 12), ("feather", 2, 6, 10),
                                 ("bow", 1, 1, 4), ("lead", 1, 1, 4), ("leather_boots", 1, 1, 3), ("spyglass", 1, 1, 1)]),
        "camp_prospectors": (3...6, [("raw_iron", 2, 6, 18), ("raw_copper", 3, 9, 16), ("coal", 3, 10, 18), ("raw_gold", 1, 3, 6),
                                     ("torch", 4, 12, 14), ("bread", 1, 3, 12), ("iron_pickaxe", 1, 1, 3), ("stone_pickaxe", 1, 1, 6),
                                     ("rail", 2, 8, 8), ("diamond", 1, 1, 1), ("amethyst_shard", 1, 4, 4)]),
        "camp_traders": (3...6, [("emerald", 1, 4, 14), ("bread", 2, 5, 14), ("sugar", 2, 6, 10), ("cocoa_beans", 1, 4, 8), ("paper", 2, 6, 10),
                                 ("white_wool", 1, 4, 8), ("red_dye", 1, 3, 6), ("blue_dye", 1, 3, 6), ("apple", 2, 5, 10), ("map", 1, 1, 3),
                                 ("compass", 1, 1, 2), ("name_tag", 1, 1, 2)]),
        "camp_abandoned": (1...3, [("bone", 1, 4, 20), ("rotten_flesh", 1, 4, 20), ("string", 1, 3, 15), ("stick", 2, 5, 15),
                                   ("iron_nugget", 2, 7, 10), ("paper", 1, 3, 8), ("map", 1, 1, 3), ("name_tag", 1, 1, 2), ("empty", 1, 1, 15)]),
        "camp_outlaws": (4...7, [("gold_nugget", 3, 12, 16), ("emerald", 1, 5, 12), ("iron_ingot", 1, 4, 12), ("gold_ingot", 1, 2, 6),
                                 ("arrow", 4, 12, 12), ("gunpowder", 1, 4, 10), ("crossbow", 1, 1, 4), ("saddle", 1, 1, 4),
                                 ("golden_apple", 1, 1, 2), ("compass", 1, 1, 3), ("experience_bottle", 1, 2, 4)]),
    ]

    static func b(_ name: String, _ fallback: String = "oak_planks") -> BlockID { Blocks.has(name) ? Blocks.id(name) : Blocks.id(fallback) }

    // MARK: Placement

    static func type(_ gen: WorldGen) -> StructureType {
        StructureType(name: "wild_camp", spacing: spacing, separation: separation, salt: 61733021, reach: 1) { [unowned gen] seed, cx, cz in
            var rng = SRng(seed)
            guard rng.chance(chance) else { return nil }
            let x = cx * CS + 8, z = cz * CS + 8
            let col = gen.column(x, z)
            guard col.height > SEA + 1 else { return nil }
            let k = gen.terrain.column(x, z)
            guard k.vol < 0.02, k.cyn < 0.05 else { return nil }
            // Variant by country (the abandoned camp can be any of them).
            let bio = col.biome
            let spawnD = simd_length(V2(Float(x), Float(z)) - WorldRules.spawnCentre(gen))
            var options: [String] = []
            // Weights: the camp of the country 3, abandoned 1, outlaws 1.
            if woods.contains(bio) { options += Array(repeating: "camp_hunters", count: 3) }
            if hills.contains(bio) || (col.height > SEA + 24 && !woods.contains(bio)) { options += Array(repeating: "camp_prospectors", count: 3) }
            if open.contains(bio) { options += Array(repeating: "camp_traders", count: 3) }
            guard !options.isEmpty else { return nil }
            options.append("camp_abandoned")
            if outlawLand.contains(bio) && spawnD > outlawMinSpawn { options.append("camp_outlaws") }
            let kind = options[rng.int(options.count)]
            // Level, dry ground across the camp: column heights within 3 of the centre's, none under water.
            let y = gen.groundY(x, z)
            guard y > SEA else { return nil }
            let r = radius, q = 9
            for (dx, dz) in [(-q, -q), (q, -q), (-q, q), (q, q), (0, -r), (0, r), (-r, 0), (r, 0), (-4, -4), (4, 4), (-4, 4), (4, -4)] {
                let c = gen.column(x + dx, z + dz)
                if abs(c.height - y) > 3 || c.height <= SEA || c.biome.isOcean || c.biome == .river || c.biome == .frozenRiver { return nil }
            }
            // Clear of every other surface structure (camps are the newest finds: they give way).
            if let sc = gen.structures {
                let keep: [(String, Int)] = [("village", 96), ("pillager_outpost", 80), ("temple", 48), ("military_base", 170), ("capital_city", 240),
                                             ("boreal_station", 80), ("mansion", 96), ("trail_ruins", 48), ("great_ruin", 120), ("desert_well", 32)]
                for (kd, m) in keep {
                    guard let o = sc.nearest(kd, x: x, z: z, maxRegions: 1) else { continue }
                    if o.max.x >= x - m && o.min.x <= x + m && o.max.z >= z - m && o.min.z <= z + m { return nil }
                }
            }
            let s = rng.next()
            let rot = rng.int(4)
            return StructureStart(kind: kind, pieces: [Piece(min: IVec3(x - r - 1, y - 6, z - r - 1), max: IVec3(x + r + 1, y + 9, z + r + 1)) { w in
                build(&w, kind, x, y, z, rot, s)
            }], anchor: IVec3(x, y + 1, z))
        }
    }

    // MARK: Building

    // A camp-local frame: (dx, dz) rotated by rot quarter turns around the centre; dy from the camp floor (y + 1).
    struct Frame {
        let x: Int, y: Int, z: Int, rot: Int
        func p(_ dx: Int, _ dz: Int) -> (Int, Int) {
            switch rot {
            case 1: return (x - dz, z + dx)
            case 2: return (x - dx, z - dz)
            case 3: return (x + dz, z - dx)
            default: return (x + dx, z + dz)
            }
        }
        // The facing offset (north, south, west, east = 0...3) of a block facing local north (-z).
        var north: BlockID { BlockID([0, 3, 1, 2][rot]) }
        // A log lying along the local x axis (true) or z axis.
        func log(_ wood: String, alongX: Bool) -> BlockID {
            let ax = alongX == (rot % 2 == 0) ? "x" : "z"
            return WildCamps.b("\(wood)_log[\(ax)]", "\(wood)_log")
        }
    }

    static func build(_ w: inout StructWriter, _ kind: String, _ x: Int, _ y: Int, _ z: Int, _ rot: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let f = Frame(x: x, y: y + 1, z: z, rot: rot)
        level(&w, x, y, z, seed)
        func put(_ dx: Int, _ dy: Int, _ dz: Int, _ blk: BlockID) { let (px, pz) = f.p(dx, dz); w.set(px, f.y + dy, pz, blk) }
        func chest(_ dx: Int, _ dz: Int, _ table: String) {
            let (px, pz) = f.p(dx, dz)
            w.chest(px, f.y, pz, loot: table, seed: rng.next(), facing: Int(f.north))
        }
        func mob(_ m: String, _ dx: Int, _ dz: Int) { let (px, pz) = f.p(dx, dz); w.mob(m, V3(Float(px) + 0.5, Float(f.y), Float(pz) + 0.5)) }
        // A-frame tent along local z: 5 long, peak 3 high, open at both ends, ridge pole on top.
        func tent(_ ox: Int, _ oz: Int, wool: BlockID, ridge: String, len: Int = 5, collapsed: Bool = false) {
            for k in 0..<len {
                let dz = oz + k - len / 2
                if collapsed {
                    if hashf(ox, k, oz, UInt32(truncatingIfNeeded: seed)) < 0.7 { put(ox - 1, 0, dz, wool) }
                    if hashf(ox, k, oz, UInt32(truncatingIfNeeded: seed) ^ 9) < 0.5 { put(ox + 1, 0, dz, wool) }
                    if k % 2 == 0 { put(ox, 0, dz, wool) }
                    continue
                }
                put(ox - 2, 0, dz, wool); put(ox + 2, 0, dz, wool)
                put(ox - 1, 1, dz, wool); put(ox + 1, 1, dz, wool)
                put(ox, 2, dz, wool)
                put(ox, 3, dz, f.log(ridge, alongX: false))
            }
        }
        // A fire on a stone hearth with two log seats (either side along local x, or along z).
        func campfire(_ dx: Int, _ dz: Int, lit: Bool, seatsX: Bool = true) {
            put(dx, -1, dz, COBBLE)
            put(dx, 0, dz, lit ? b("campfire") : b("campfire[off]", "campfire"))
            let seat = f.log("stripped_spruce", alongX: !seatsX)
            for k in [-2, 2] { put(dx + (seatsX ? k : 0), 0, dz + (seatsX ? 0 : k), seat) }
        }
        func barrels(_ dx: Int, _ dz: Int, _ n: Int) {
            for i in 0..<n { put(dx + i % 2, 0, dz + i / 2, i == 2 ? b("hay_block") : b("barrel")) }
        }
        switch kind {
        case "camp_hunters":
            let hide = rng.chance(0.5) ? b("brown_wool") : b("green_wool")
            tent(-4, -1, wool: hide, ridge: "spruce")
            campfire(2, 1, lit: true)
            // Drying rack: two posts with a fence bar, hides hanging from it.
            let fence = b("spruce_fence", "oak_fence")
            for dz in [-4, 0] { put(4, 0, dz, fence); put(4, 1, dz, fence) }
            for dz in -3...(-1) { put(4, 1, dz, fence) }
            put(4, 0, -3, b("brown_wool")); put(4, 0, -1, b("light_gray_wool", "white_wool"))
            barrels(-1, 4, 3)
            chest(1, 5, "camp_hunters")
            put(-6, 0, 3, b("spruce_log"))                   // chopping block
            if rng.chance(0.5) { put(5, 0, 4, b("oak_log")) }
        case "camp_prospectors":
            // Headframe over a fenced test pit.
            let post = b("spruce_log"), beam = f.log("spruce", alongX: true)
            for dx in [-5, -1] { for dy in 0...3 { put(dx, dy, -3, post) } }
            for dx in -5...(-1) { put(dx, 4, -3, beam) }
            put(-3, 3, -3, b("chain", "spruce_fence")); put(-3, 2, -3, b("lantern[hanging]", "lantern"))
            for dz in -4...(-2) { for dx in -4...(-2) where !(dx == -3 && dz == -3) { put(dx, -1, dz, b("gravel")) } }
            put(-3, -1, -3, AIR); put(-3, -2, -3, AIR); put(-3, -3, -3, b("water", "air"))
            // Ore cart: a short track ending in a barrel heaped with ore.
            for dz in 0...4 { put(1, 0, dz, b("rail", "air")) }
            put(1, 0, 5, b("barrel")); put(1, 1, 5, b("raw_iron_block", "iron_ore"))
            // Spoil heaps.
            for (dx, dz) in [(4, -2), (5, -2), (4, -1), (5, -3)] { put(dx, 0, dz, b("gravel")) }
            put(4, 1, -2, b("gravel")); put(5, 0, -1, b("coal_ore")); put(4, 0, -3, b("iron_ore")); put(5, 1, -3, b("copper_ore", "iron_ore"))
            // Lean-to: canvas sloping from a row of posts down to the ground, a work table under it.
            let canvas = b("light_gray_wool", "white_wool")
            for dz in 2...4 { put(-6, 0, dz, b("spruce_fence", "oak_fence")); put(-6, 1, dz, b("spruce_fence", "oak_fence")); put(-6, 2, dz, canvas); put(-5, 1, dz, canvas) }
            put(-5, 0, 3, b("crafting_table"))
            put(3, 0, 3, b("grindstone", "crafting_table"))
            campfire(-2, 2, lit: rng.chance(0.6), seatsX: false)
            chest(-3, 5, "camp_prospectors")
        case "camp_traders":
            // Covered wagon along local z: plank bed on log wheels, wool canopy on fence hoops.
            let bed = b("spruce_planks"), canopy = b("white_wool"), hoop = b("spruce_fence", "oak_fence")
            for dz in [-3, 1] { put(-3, 0, dz, f.log("oak", alongX: true)); put(1, 0, dz, f.log("oak", alongX: true)) }
            for dz in -4...2 { for dx in -2...0 { put(dx, 1, dz, bed) } }
            for dz in -3...1 {
                put(-2, 2, dz, hoop); put(0, 2, dz, hoop)
                put(-2, 3, dz, canopy); put(0, 3, dz, canopy); put(-1, 4, dz, canopy)
            }
            put(-1, 2, -2, b("barrel")); put(-1, 2, 0, b("hay_block"))
            put(-1, 1, 3, b("spruce_fence", "oak_fence"))        // the tongue
            put(-1, 0, -5, b("hay_block"))                        // a step up onto the tail of the bed
            // Hitching post, hay and goods round a small fire.
            put(3, 0, 4, b("oak_fence")); put(3, 1, 4, b("oak_fence"))
            put(4, 0, 4, b("hay_block"))
            barrels(3, -4, 3)
            campfire(4, 0, lit: true)
            chest(2, -2, "camp_traders")
            mob("donkey", 3, 3)
            if rng.chance(0.7) { mob("wandering_trader", 2, 1) }
        case "camp_outlaws":
            let dark = rng.chance(0.5) ? b("black_wool") : b("red_wool")
            tent(-4, -2, wool: dark, ridge: "dark_oak")
            tent(4, -2, wool: b("brown_wool"), ridge: "dark_oak", len: 3)
            campfire(0, 2, lit: true)
            // Lookout: a plank platform on posts with a ladder.
            let post = b("dark_oak_log", "oak_log"), plank = b("dark_oak_planks"), rail = b("dark_oak_fence", "oak_fence")
            for (dx, dz) in [(4, 4), (6, 4), (4, 6), (6, 6), (5, 4)] { for dy in 0...2 { put(dx, dy, dz, post) } }
            for dz in 4...6 { for dx in 4...6 { put(dx, 3, dz, plank) } }
            for (dx, dz) in [(4, 4), (6, 4), (4, 6), (6, 6), (5, 6), (6, 5)] { put(dx, 4, dz, rail) }
            for dy in 0...3 { put(5, dy, 3, b("ladder") + f.north) }       // on the post's north face
            put(-6, 0, 4, b("target", "hay_block")); put(-6, 1, 4, b("pumpkin", "hay_block"))
            barrels(-2, 5, 3)
            chest(2, 5, "camp_outlaws")
            mob("vindicator", -1, 0)
            mob("pillager", 5, 5)
        default:                                             // camp_abandoned
            tent(-3, 0, wool: rng.chance(0.5) ? b("white_wool") : b("brown_wool"), ridge: "spruce", collapsed: true)
            campfire(2, 1, lit: false)
            put(-3, 1, 2, b("cobweb", "air")); put(3, 0, -3, b("cobweb", "air"))
            put(4, 0, 3, b("barrel")); put(5, 0, 2, b("spruce_slab", "oak_slab"))
            put(-5, 0, -4, b("bone_block", "gravel"))
            chest(4, 4, "camp_abandoned")
        }
    }

    // Levels the camp ground to the centre's height y (top solid block): soil cut down or built up, its surface kept as the column had it (grass, podzol, sand...), plants and snow cleared above; a worn
    // ring of coarse dirt and path round the middle.
    static func level(_ w: inout StructWriter, _ x: Int, _ y: Int, _ z: Int, _ seed: UInt64) {
        let r = radius, s32 = UInt32(truncatingIfNeeded: seed)
        let grass = Blocks.id("grass_block"), path = b("dirt_path", "coarse_dirt"), coarse = b("coarse_dirt", "dirt")
        for dz in -r...r { for dx in -r...r {
            let px = x + dx, pz = z + dz
            guard w.inside(px, y, pz) else { continue }
            let d2 = dx * dx + dz * dz
            guard d2 <= r * r + 1 else { continue }
            // The natural top within 6 blocks of y.
            var top = y + 6, natural: BlockID = grass
            while top > y - 6 {
                let cur = w.get(px, top, pz)
                if Blocks.collide[Int(cur)] && Blocks.opaque[Int(cur)] { natural = cur; break }
                top -= 1
            }
            if !StructWriter.soil[Int(natural)] && natural != Blocks.id("sand") && natural != Blocks.id("red_sand") { natural = grass }
            // Flat out to `flat`, then eased back to the natural top by the radius (a hard-edged plateau stood out of
            // terraced hills: camp_prospectors, Oct 10).
            let d: Float = Float(d2).squareRoot()
            let t: Float = max(0, min(1, (d - flat) / (Float(r) + 0.5 - flat)))
            let gy: Int = y + Int((Float(top - y) * t).rounded())
            for yy in (gy + 1)...(y + 8) { w.set(px, yy, pz, AIR) }
            w.pillarDown(px, gy - 1, pz, DIRT, minY: gy - 14)          // down to solid ground (caves, ledges: structcheck floating)
            var surf = natural
            let wear = hashf(px, 3, pz, s32)
            if d2 <= 16 && wear < 0.55 { surf = wear < 0.3 ? path : coarse }
            else if d2 <= 36 && wear < 0.18 { surf = coarse }
            w.set(px, gy, pz, surf)
        } }
    }
}
