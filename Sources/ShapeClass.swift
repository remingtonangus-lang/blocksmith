import Foundation

// Realistic world, layer 1 (docs/design/realistic-world.md): what form every block state takes in a polygon world,
// derived from its definition (render type, material, tool, axis states, textures, whether a recipe makes it), never
// from a list of blocks. New blocks are covered with no work.
enum ShapeKind: UInt8 {
    case none       // air and invisible blocks
    case liquid     // water, lava: a continuous surface
    case plant      // crossed plants standing on the drawn ground
    case foliage    // leaves: canopy masses
    case trunk      // logs, wood, stems: round tapered trunks and limbs grown from the log graph
    case terrain    // natural ground and rock: the smooth surface from the generator's fields
    case organic    // other natural full blocks: a rounded primitive (OrganicFamily)
    case built      // man-made full blocks: crisp with bevelled exposed edges
    case model      // everything drawn from boxes (stairs, slabs, fences, torches, workblocks...)
}

// Organic primitives, picked from the definition (docs/design/realistic-world.md 1.1).
enum OrganicFamily: UInt8 {
    case blob       // a soft lumpy superellipsoid (sponge, moss, wart blocks, coral blocks...)
    case gourd      // a ribbed oblate spheroid with its own cap texture (pumpkins, melons)
    case bale       // a rounded drum along its axis (hay, bone, dried kelp)
    case cap        // a domed cap (mushroom caps); a stalk under another cap block
}

enum ShapeClass {
    // Materials the ground is made of (by the block's sound material: what it is, as the game already says).
    static let earthy: Set<SoundMat> = [.stone, .dirt, .sand, .gravel, .snow, .mud, .netherrack, .deepslate, .grass, .soul,
                                        .sculk, .amethyst]
    // Living or once-living matter.
    static let living: Set<SoundMat> = [.wood, .plant, .wool, .slime, .bone, .leaves]
    // Words that mark a worked material (dressed, fired, cut or cast by people): never the natural ground.
    static let worked = ["brick", "polished", "cut_", "chiseled", "tile", "concrete", "glazed", "pillar", "cobble", "smooth_stone",
                         "lamp", "planks", "carved", "lantern", "shelf", "table", "bench", "crate", "barrel", "plating", "panel",
                         "reinforced", "lit_", "chest", "furnace", "spawner", "trapdoor"]

    // Block group names a crafting recipe makes (shaped or shapeless; smelting not counted: stone and terracotta come
    // out of a furnace and are still natural ground).
    static let crafted: Set<String> = {
        var s = Set<String>()
        for r in Recipes.all {
            let d = Items.defs[Int(r.result.item)]
            guard let b = d.block else { continue }
            s.insert(group(b))
        }
        return s
    }()

    // The ground the polygon worlds smoothed before the census (the round-2 cave survey): kept so caves stay exactly as
    // they are even where the census samples miss a rare biome (badlands, mushroom fields, frozen peaks).
    static let legacyGroundNames: Set<String> = [
        "stone", "dirt", "grass_block", "snowy_grass_block", "coarse_dirt", "rooted_dirt", "podzol", "mycelium", "mud",
        "clay", "sand", "red_sand", "gravel", "sandstone", "red_sandstone", "snow_block", "deepslate", "emberslate",
        "andesite", "diorite", "granite", "tuff", "calcite", "dripstone_block", "moss_block", "smooth_basalt",
        "terracotta", "netherrack", "soul_soil", "blackstone", "end_stone",
        "basalt", "magma_block", "amethyst_block", "budding_amethyst", "sculk", "packed_ice", "blue_ice",
        "infested_stone", "infested_deepslate", "soul_sand", "crimson_nylium", "warped_nylium",
    ]
    static let legacyGround: [Bool] = (0..<Blocks.count).map { i in
        guard Blocks.opaque[i] && Blocks.render[i] == RenderType.cube.rawValue else { return false }
        let n = Blocks.key(BlockID(i))
        if legacyGroundNames.contains(n) || n.hasSuffix("_ore") { return true }
        return n.hasSuffix("_terracotta") && !n.contains("glazed")
    }

    static func group(_ b: BlockID) -> String { Blocks.key(Blocks.groupBase[Int(b)]) }

    // A 3-state axis pillar (BlockRegistry.pillar: base, "[x]", "[z]").
    static func isPillar(_ b: BlockID) -> Bool {
        let g = group(b)
        return Blocks.has(g + "[x]") && Blocks.has(g + "[z]")
    }

    static func isWorked(_ name: String) -> Bool { worked.contains { name.contains($0) } }

    // The form of every block state.
    static let kind: [ShapeKind] = (0..<Blocks.count).map { classify(BlockID($0)) }
    static let family: [OrganicFamily] = (0..<Blocks.count).map { organicFamily(BlockID($0)) }

    static func classify(_ b: BlockID) -> ShapeKind {
        let i = Int(b)
        let d = Blocks.def(b)
        let rt = RenderType(rawValue: Blocks.render[i]) ?? .none
        if b == AIR || rt == .none { return .none }
        if rt == .liquid { return .liquid }
        if rt == .cross { return .plant }
        if Mesher.leafT[i] { return .foliage }
        guard rt == .cube && Blocks.opaque[i] else { return .model }
        let n = Blocks.key(b)
        if isPillar(b) && d.sound == .wood && d.tool == .axe { return .trunk }   // logs, wood, stems (cut ones too)
        // Natural: the generators lay it down themselves (NaturalCensus), and it is not a worked material (a dungeon's
        // cobblestone, a road's polished stone).
        if NaturalCensus.natural[i] && !isWorked(n) || legacyGround[i] {
            if n.hasSuffix("_ore") || earthy.contains(d.sound) { return .terrain }
            if NaturalCensus.bulkShare[i] >= 0.6 { return .terrain }      // in masses: moss carpets, ice, wart canopies
            return .organic                                               // on its own: pumpkins, nests, mushroom caps
        }
        // Made from a natural object and still looking like it from above (a carved or lit pumpkin): the same form.
        if organicTops.contains(Blocks.tex[i * 6 + 2]) { return .organic }
        return .built
    }

    // End textures of the natural organic objects (what a made copy of one keeps).
    static let organicTops: Set<UInt16> = {
        var s = Set<UInt16>()
        for i in 0..<Blocks.count where NaturalCensus.natural[i] && Blocks.opaque[i] && Blocks.render[i] == RenderType.cube.rawValue {
            let b = BlockID(i), d = Blocks.def(b), n = Blocks.key(b)
            if Mesher.leafT[i] || isWorked(n) || n.hasSuffix("_ore") || earthy.contains(d.sound) || NaturalCensus.bulkShare[i] >= 0.6 { continue }
            if isPillar(b) && d.sound == .wood { continue }
            s.insert(Blocks.tex[i * 6 + 2])
        }
        return s
    }()

    static func organicFamily(_ b: BlockID) -> OrganicFamily {
        let i = Int(b)
        guard kind[i] == .organic else { return .blob }
        let d = Blocks.def(b)
        if isPillar(b) { return .bale }
        let t = Blocks.tex
        let side = t[i * 6], top = t[i * 6 + 2]
        // Four alike sides (or a face on one of them) under a different top: a gourd, cut with an axe.
        if d.tool == .axe && side != top {
            if d.sound == .wood && t[i * 6 + 3] == top { return .gourd }
            return .cap
        }
        if d.tool == .axe && d.sound == .wood { return .cap }
        if t[i * 6 + 3] != top && side != top { return .bale }       // a drum seen end-on (dried kelp)
        return .blob
    }

    // Start-up census (BLOCKSMITH_SHAPECENSUS=1): states per class and, for terrain, how the rule compares with the
    // hand list the polygon thread used before (SmoothTerrain.naturalNames).
    static func census() -> String {
        var counts = [Int](repeating: 0, count: 9)
        var groups = [[String]](repeating: [], count: 9)
        var seen = Set<String>()
        for i in 0..<Blocks.count {
            let k = Int(kind[i].rawValue)
            counts[k] += 1
            let g = group(BlockID(i))
            if seen.insert(g + "#\(k)").inserted { groups[k].append(g) }
        }
        let names = ["none", "liquid", "plant", "foliage", "trunk", "terrain", "organic", "built", "model"]
        var out = "shape census: " + (0..<9).map { "\(names[$0]) \(counts[$0])" }.joined(separator: ", ") + "\n"
        for k in [4, 5, 6, 7] { out += "  \(names[k]) (\(groups[k].count) groups): " + groups[k].sorted().joined(separator: " ") + "\n" }
        let old = Set((0..<Blocks.count).filter { legacyGround[$0] }.map { group(BlockID($0)) })
        let now = Set(groups[5])
        out += "  terrain vs old natural list: lost [" + old.subtracting(now).sorted().joined(separator: " ") + "], new [" +
            now.subtracting(old).sorted().joined(separator: " ") + "]\n"
        for i in 0..<Blocks.count where kind[i] == .organic {
            out += "  organic \(Blocks.key(BlockID(i))): \(family[i])\n"
        }
        return out
    }
}
