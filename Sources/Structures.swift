import Foundation

// Structures: placed per region on a grid (like the reference game's spacing/separation), built from
// deterministic pieces. When a chunk generates, every piece overlapping it writes its blocks clipped
// to that chunk, so structures spanning many chunks come out seamless.

// Deterministic RNG for structure layout / loot.
struct SRng {
    var s: UInt64
    init(_ seed: UInt64) { s = seed ^ 0x9E3779B97F4A7C15; if s == 0 { s = 1 } }
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    mutating func range(_ a: Int, _ b: Int) -> Int { a + int(b - a + 1) }
    mutating func float() -> Float { Float(next() % 1_000_000) / 1_000_000 }
    mutating func chance(_ p: Float) -> Bool { float() < p }
}

// Writes blocks for one chunk; everything outside the chunk is ignored.
struct StructWriter {
    let bx: Int, bz: Int
    var blocks: UnsafeMutablePointer<BlockID>
    var entities: [(IVec3, BlockEntity)] = []
    var mobs: [(String, V3)] = []
    // Lowest solid block written per column of this chunk (for filling under a structure: StructureCache.place).
    // `off`: pieces built without the fill (the town row beside a citadel builds its own foundations, GarrisonTown).
    final class Low { var y = [Int](repeating: Int.max, count: CS * CS); var off = false }
    let low = Low()
    // PG6 field worlds: a mark per cell the structure built (set, fill, pillarDown), so its stone, sandstone and snow stay
    // blocks instead of joining the ground's field (FieldTerrain.split). The foundations, banks and roads that shape the
    // ground (fillUnder, berm, packed earth) are ground and are not marked.
    var mark: UnsafeMutablePointer<UInt8>? = nil
    @inline(__always) func note(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
        if Blocks.collide[Int(b)] && !low.off { let k = (z - bz) * CS + (x - bx); if y < low.y[k] { low.y[k] = y } }
    }

    @inline(__always) func inside(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        x >= bx && x < bx + CS && z >= bz && z < bz + CS && y >= 0 && y < CH
    }
    func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        inside(x, y, z) ? blocks[Chunk.index(x - bx, y, z - bz)] : AIR
    }
    func set(_ x: Int, _ y: Int, _ z: Int, _ b0: BlockID) {
        // PG5 ("roads on smooth ground blend into each other and into the terrain"): in a Polygons world the generators'
        // paths are laid as packed earth, natural ground the smooth surface runs straight through, instead of the
        // path block, a built shape the smooth ground had to stop at.
        let b = b0 == StructWriter.pathID && (SmoothTerrain.enabled || mark != nil) ? StructWriter.roadID : b0
        if inside(x, y, z) {
            let i = Chunk.index(x - bx, y, z - bz)
            blocks[i] = b; note(x, y, z, b); unplant(x, y, z, b)
            if let m = mark, b == b0 { m[i] = 1 }
        }
    }
    // Ground a structure lays as terrain (a sky isle's rock and turf: P377 step 2): written unmarked, so in a field world
    // it joins the field and is drawn as the ground's smooth surface, never as cubes.
    func setGround(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
        guard inside(x, y, z) else { return }
        let i = Chunk.index(x - bx, y, z - bz)
        blocks[i] = b; note(x, y, z, b); unplant(x, y, z, b)
        if let m = mark { m[i] = 0 }
    }
    static let pathID: BlockID = Blocks.has("dirt_path") ? Blocks.id("dirt_path") : AIR
    static let roadID: BlockID = Blocks.has("coarse_dirt") && SmoothTerrain.natural[Int(Blocks.id("coarse_dirt"))]
        ? Blocks.id("coarse_dirt") : pathID

    // Grass, flowers and saplings need soil: a structure block written under one (paths, foundations, wells)
    // removes it (gencheck plant_soil: grass and bushes standing on village cobblestone).
    static let soilPlant: [Bool] = (0..<Blocks.count).map { i in
        GenCheck.soils(Blocks.key(Blocks.groupBase[i])) == GenCheck.dirtLike
    }
    static let soil: [Bool] = (0..<Blocks.count).map { i in GenCheck.dirtLike.contains(Blocks.key(Blocks.groupBase[i])) }
    @inline(__always) func unplant(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
        guard b != AIR, !StructWriter.soil[Int(b)], Blocks.collide[Int(b)] else { return }
        var yy = y + 1
        while yy < CH, StructWriter.soilPlant[Int(blocks[Chunk.index(x - bx, yy, z - bz)])] {
            blocks[Chunk.index(x - bx, yy, z - bz)] = AIR
            yy += 1
        }
    }
    func fill(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ b: BlockID) {
        let xa = max(x0, bx), xb = min(x1, bx + CS - 1)
        let za = max(z0, bz), zb = min(z1, bz + CS - 1)
        let ya = max(0, y0), yb = min(CH - 1, y1)
        guard xa <= xb, za <= zb, ya <= yb else { return }
        for y in ya...yb { for z in za...zb { for x in xa...xb { blocks[Chunk.index(x - bx, y, z - bz)] = b } } }
        if let m = mark { for y in ya...yb { for z in za...zb { for x in xa...xb { m[Chunk.index(x - bx, y, z - bz)] = 1 } } } }
        for z in za...zb { for x in xa...xb { note(x, ya, z, b); unplant(x, yb, z, b) } }
    }

    // Fills open air / cave water under the lowest block each column of the structure wrote, down to the ground
    // (at most `depth`), so it doesn't hang over caves or slopes (structcheck "floating"; reference terrain
    // adaptation "beard"). Resets the per-column record for the next structure.
    func fillUnder(depth: Int, surface: BlockID, intoWater: Bool = true) {
        for k in 0..<(CS * CS) {
            let y0 = low.y[k]
            low.y[k] = Int.max
            guard y0 != Int.max && y0 > 1 else { continue }
            let x = bx + k % CS, z = bz + k / CS
            var y = y0 - 1
            // R22 ("pillars ending in air"): `depth` is the usual fill; a column over a ravine, cave mouth or cliff
            // carries on down to the ground (as StructWriter.groundDown), so nothing ends in mid-air.
            while y > max(0, y0 - max(depth, StructWriter.groundReach)) {
                let i = Chunk.index(x - bx, y, z - bz)
                let cur = blocks[i]
                // Through grass and flowers too (a Steelhold fill stopped on tall grass, leaving its base over air:
                // structcheck floating, run 364).
                let plant: Bool = Blocks.replaceable[Int(cur)] && Blocks.fluidKind[Int(cur)] == 0
                guard cur == AIR || plant || (intoWater && cur == WATER) else { break }
                blocks[i] = y < YOFF ? DEEPSLATE : (y < SEA - 12 ? STONE : surface)
                y -= 1
            }
        }
    }

    // P91 (playtest 09:40, "make the base bleed into the ground"): an earth bank round a levelled site, so a base
    // stands on a mound instead of a square plateau with block cliffs. Columns outside the square of half-size `half`
    // round (cx, cz), at ring distance d = 1...reach, are banked up to floor - d with the ground they stand on (grass,
    // sand or snowy grass on top, dirt or sand below), through air, plants and shallow water. Only from the plan and
    // the column itself, so neighbouring chunks agree; never over structure blocks (a solid block at the bank's top
    // means the land is already that high, or something was built there).
    func berm(_ cx: Int, _ cz: Int, half: Int, floor fy: Int, reach: Int) {
        let snowL = Blocks.has("snow") ? Blocks.id("snow") : AIR
        for lz in 0..<CS { for lx in 0..<CS {
            let x = bx + lx, z = bz + lz
            let d = max(abs(x - cx) - half, abs(z - cz) - half)
            guard d >= 1 && d <= reach else { continue }
            let top = fy - d
            guard top > 2 && top < CH - 2 else { continue }
            var y = top, wet = 0, layer = AIR
            while y > max(1, top - 40) {
                let b = blocks[Chunk.index(lx, y, lz)]
                if b == WATER { wet += 1 }
                else if b != AIR && !(Blocks.replaceable[Int(b)] && Blocks.fluidKind[Int(b)] == 0) { break }
                if b == snowL && snowL != AIR { layer = b }
                y -= 1
            }
            guard y < top, wet <= 3 else { continue }
            let g = blocks[Chunk.index(lx, y, lz)]
            guard Blocks.opaque[Int(g)] && Blocks.collide[Int(g)] && Blocks.fluidKind[Int(g)] == 0 else { continue }
            let sandy = g == SAND || g == SANDSTONE || wet > 0, snowy = !sandy && (g == SNOWY_GRASS || g == SNOW || layer != AIR)
            guard sandy || snowy || g == GRASS || g == DIRT || g == STONE || g == COBBLE else { continue }
            let cap = sandy ? SAND : (snowy ? SNOWY_GRASS : GRASS), fill = sandy ? SAND : DIRT
            if g == GRASS || g == SNOWY_GRASS { blocks[Chunk.index(lx, y, lz)] = DIRT }
            for yy in (y + 1)...top { blocks[Chunk.index(lx, yy, lz)] = yy == top ? cap : fill }
            let above = blocks[Chunk.index(lx, top + 1, lz)]
            if Blocks.replaceable[Int(above)] && Blocks.fluidKind[Int(above)] == 0 { blocks[Chunk.index(lx, top + 1, lz)] = snowy ? snowL : AIR }
        } }
    }

    // Pillar from y down until a solid block (inside this chunk only).
    func pillarDown(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID, minY: Int) {
        guard inside(x, y, z) else { return }
        var yy = y
        while yy >= minY {
            let cur = blocks[Chunk.index(x - bx, yy, z - bz)]
            // Ground that holds you stops the pillar; powder snow (opaque, but you sink) doesn't: an igloo's entrance
            // tunnel stood on it with no floor, so its room was unreachable (structcheck igloo, run 509).
            if Blocks.opaque[Int(cur)] && Blocks.collide[Int(cur)] && cur != b { break }
            blocks[Chunk.index(x - bx, yy, z - bz)] = b
            mark?[Chunk.index(x - bx, yy, z - bz)] = 1
            yy -= 1
        }
    }
    mutating func chest(_ x: Int, _ y: Int, _ z: Int, loot: String, seed: UInt64, facing: Int = 0) {
        guard inside(x, y, z) else { return }
        set(x, y, z, Blocks.id("chest") + BlockID(facing))
        let be = BlockEntity(.chest)
        var rng = SRng(seed)
        Loot.fill(be.container, table: loot, rng: &rng)
        entities.append((IVec3(x, y, z), be))
    }
    // A dispenser (or dropper) facing dir (dir6 index) loaded with the given items, one stack a slot.
    mutating func dispenser(_ x: Int, _ y: Int, _ z: Int, dir: Int, items: [ItemStack], key: String = "dispenser") {
        guard inside(x, y, z) else { return }
        set(x, y, z, Blocks.id(key) + BlockID(dir))
        let be = BlockEntity(.dispenser)
        let c = be.container
        for (i, it) in items.prefix(c.count).enumerated() { c[i] = it }
        entities.append((IVec3(x, y, z), be))
    }
    // Mob placed when this chunk generates (only if its position lies in this chunk).
    mutating func mob(_ kind: String, _ p: V3) {
        if inside(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))) { mobs.append((kind, p)) }
    }
    mutating func spawner(_ x: Int, _ y: Int, _ z: Int, mob: String) {
        guard inside(x, y, z) else { return }
        set(x, y, z, Blocks.id("spawner"))
        let be = BlockEntity(.spawner)
        be.mob = mob
        entities.append((IVec3(x, y, z), be))
    }
}

struct Piece {
    let min: IVec3
    let max: IVec3
    let build: (inout StructWriter) -> Void
    func overlaps(_ bx: Int, _ bz: Int) -> Bool { max.x >= bx && min.x < bx + CS && max.z >= bz && min.z < bz + CS }
}

final class StructureStart {
    let kind: String
    let pieces: [Piece]
    let min: IVec3
    let max: IVec3
    let anchor: IVec3                     // a representative walkable spot (start piece floor)
    var plan: AnyObject?                  // the layout a kind keeps for later queries (CapitalCity.Plan)
    var info: [String: Int] = [:]         // a few numbers a kind keeps (towns: size, lots, shops, deputies: TownSizes)
    init(kind: String, pieces: [Piece], anchor: IVec3) {
        self.kind = kind
        self.anchor = anchor
        self.pieces = pieces
        var a = IVec3(Int.max, Int.max, Int.max), b = IVec3(Int.min, Int.min, Int.min)
        for p in pieces {
            a = IVec3(Swift.min(a.x, p.min.x), Swift.min(a.y, p.min.y), Swift.min(a.z, p.min.z))
            b = IVec3(Swift.max(b.x, p.max.x), Swift.max(b.y, p.max.y), Swift.max(b.z, p.max.z))
        }
        min = a; max = b
    }
    func contains(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        x >= min.x && x <= max.x && y >= min.y && y <= max.y && z >= min.z && z <= max.z
    }
}

// A structure type: grid spacing/separation (chunks) and how to lay out a start in a region.
struct StructureType {
    let name: String
    let spacing: Int
    let separation: Int
    let salt: UInt64
    let reach: Int                        // max extent from the start chunk, in chunks
    let make: (_ seed: UInt64, _ chunkX: Int, _ chunkZ: Int) -> StructureStart?
}

final class StructureCache {
    private struct StartKey: Hashable { let name: String; let rx: Int; let rz: Int }
    private var cache: [StartKey: StructureStart?] = [:]
    // P124 (Oct 12 PM, "once in a while... it freezes for a second"): past 4096 starts the cache was emptied at once,
    // and every start asked for on the frame thread after that (the citadel watch, the map's discoveries, railways,
    // town law) was made again there: a citadel or a town plan each, 420 ms in one host tick (well over a second on the
    // headset). Now the least recently used quarter goes and the starts round the player stay.
    private var used: [StartKey: Int] = [:]
    private var useClock = 0
    static var cap = 4096
    private(set) static var evictions = 0
    // Bench gen: time spent computing structure starts, per kind (ms).
    static var startMs: [String: Double] = [:]
    private let lock = NSLock()
    let seed: UInt64
    let types: [StructureType]
    let fixed: [StructureStart]           // starts at precomputed positions (strongholds)
    // Drawn into each chunk after its structures (the overworld's roads: Roads.swift).
    var after: ((inout StructWriter, Int, Int) -> Void)?
    // Chunks a saved world had already generated before structures were added or moved (task 23: Capital cities,
    // denser citadels). New placements must keep clear of them, or they would appear cut off at the edge of explored
    // ground. Set once by World.init from SaveManager.structureGuard() before any chunk is generated.
    var legacy: Set<Int64> = []
    // The same guard taken again when Boreal Stations arrived (2026-10-09): chunks saved before that.
    var legacyStations: Set<Int64> = []
    // Chunks saved before the Oct 10 placement rules (WorldRules.swift: no Capital city near spawn, rarer cities, no
    // ruined gates): a retired placement stays wherever a save had already generated part of it.
    var explored: Set<Int64> = []
    // And when Capital cities got their market, flats and citizens (2026-10-10): a city with ground saved before that
    // keeps its old lot uses, or the new storefronts would be built against offices already saved in the next chunk.
    var legacyCapitalTowns: Set<Int64> = []
    // And when towns got their frontier fittings (2026-10-10, FrontierTown.swift): a town with ground saved before
    // that keeps its old lots, or a house half saved would be finished as a sheriff's office.
    var legacyFrontier: Set<Int64> = []
    // And when frontier towns got three street plans, a bank, street lamps and welcome signs (2026-10-11, the towns
    // gap pass): a town with ground saved before that keeps the crossroads plan and its old lots.
    var legacyTownsGap: Set<Int64> = []
    // And when L3 kept Capital cities apart and gave camps an alternate spot and a clear spawn (2026-10-11,
    // WorldRules.capitalApart, WildCamps): ground saved before that keeps its cities and camps as they were.
    var legacyL3: Set<Int64> = []
    // And when G12 made citadels and Capital cities rarer, kept citadels apart and gave each city its own size and
    // mix (2026-10-11, WorldRules.savedBeforeG12): ground saved before that keeps its citadels and cities as they were.
    var legacyG12: Set<Int64> = []
    var legacyP44: Set<Int64> = []                // WorldRules.savedBeforeP44
    var legacyP95: Set<Int64> = []                // WorldRules.savedBeforeP95
    var legacyGreywall: Set<Int64> = []           // ground saved before Greywall Command bases (A1, Greywall.swift)
    var legacySkyIsle: Set<Int64> = []            // ground saved before the sky isles (C7, SkyIsle.swift)
    var legacyPorts: Set<Int64> = []              // ground saved before the naval ports (D39, NavalPort.swift)
    var legacySites: Set<Int64> = []              // ground saved before the frontier sites (D48, FrontierSites.swift)
    var legacyOverlap: Set<Int64> = []            // ground saved before small starts gave way to big ones (Q2, below)
    var legacyC1: Set<Int64> = []                 // ground saved before railways (C1, Railways.swift)
    var legacyC12: Set<Int64> = []                // ground saved before mining towns (C12, MiningTowns.swift)
    var legacyC13: Set<Int64> = [] {              // ground saved before town sizes (C13, TownSizes.swift)
        // R20 (wide main streets and lanes, door walks, the stone jail: Village.layout) keeps its own guard, taken from
        // the same save as the C13 one (World.init reads that guard and assigns it here; SaveManager.guarding is it).
        didSet {
            legacyR20 = SaveManager.guarding?.structureGuard(file: "structure-guard-r20.txt") ?? []
            legacyP354 = SaveManager.guarding?.structureGuard(file: "structure-guard-p354.txt") ?? []
            legacyP360 = SaveManager.guarding?.structureGuard(file: "structure-guard-p360.txt") ?? []
            legacyP466 = SaveManager.guarding?.structureGuard(file: "structure-guard-p466.txt") ?? []
            legacyP456 = SaveManager.guarding?.structureGuard(file: "structure-guard-p456.txt") ?? []
            legacyP462 = SaveManager.guarding?.structureGuard(file: "structure-guard-p462.txt") ?? []
            legacyP470 = SaveManager.guarding?.structureGuard(file: "structure-guard-p470.txt") ?? []
            legacyP469 = SaveManager.guarding?.structureGuard(file: "structure-guard-p469.txt") ?? []
            legacyP474 = SaveManager.guarding?.structureGuard(file: "structure-guard-p474.txt") ?? []
            legacyP471 = SaveManager.guarding?.structureGuard(file: "structure-guard-p471.txt") ?? []
        }
    }
    var legacyR20: Set<Int64> = []               // ground saved before R20's streets and jails (Village.layout)
    var legacyP354: Set<Int64> = []              // ground saved before P354's homes, workshops and jail (TownHomes.swift)
    var legacyP466: Set<Int64> = []              // ground saved before P466 laid hamlets and villages out bigger (TownSizes.biggerSpec)
    var legacyP456: Set<Int64> = []              // ground saved before P456 laid large towns and cities out far bigger (TownSizes.biggerSpec)
    var legacyP462: Set<Int64> = []              // ground saved before P462 built Capital cities of glass and steel towers (CapitalCity.tower)
    var legacyP474: Set<Int64> = []              // ground saved before P474 drew bigger places more often, laid out bigger (TownSizes.biggestSpec)
    var legacyP471: Set<Int64> = []              // ground saved before P471's gun rooms (Greywall towers, Boreal blockhouses)
    var legacyP470: Set<Int64> = []              // ground saved before P470 let two stations make a line (Railways.plan)
    var legacyP469: Set<Int64> = []              // ground saved before P469 gave depot bases their compounds (Depots.swift)
    var legacyP360: Set<Int64> = []              // ground saved before the Dust Mission replaced the desert temple (DustMission.swift)
    var legacyR22: Set<Int64> = []                // ground saved before the R22 rarity pass (StructureCache.keepR22)

    // R22 (Oct 13 evening: "structure rarity everywhere; ships 8x rarer was P190, check all"): the share of regions that
    // keep their start, per kind, on ground not saved before. The reference's grid spacing is kept (moving a grid would
    // move every start, found ones included); a region simply stays empty. Towns, Capital places, citadels, Greywall
    // and stations already have their own rarity rules (WorldRules) and are not thinned again.
    static let keepR22: [String: Float] = [
        "ocean_ruin": 0.3, "ruined_portal": 0.3, "desert_well": 0.35, "fossil": 0.45, "pillager_outpost": 0.45,
        "temple": 0.5, "trail_ruins": 0.5, "great_ruin": 0.5, "mineshaft": 0.6, "wild_camp": 0.4, "sky_isle": 0.5,
        "monument": 0.6, "trial_chambers": 0.7, "ancient_city": 0.7,
    ]

    // Q2 (scorecard "world gen: no structure overlaps", 138 piece overlaps in 50 seeds): a small start gives way to a
    // bigger one whose pieces it would cut into, so a ruined portal never stands in a village street or a citadel wall,
    // a shipwreck never lies inside an ocean ruin, a mineshaft never tunnels through trial chambers. One way only (the
    // big kinds yield to nothing here), so the check never recurses. Ground saved before this keeps its old starts.
    static let yields: [String: [String]] = [
        "ruined_portal": ["village", "military_base", "capital_city", Greywall.kind, BorealStation.kind, "temple",
                          "pillager_outpost", "mansion", "trail_ruins", "great_ruin", "ocean_ruin", "monument"],
        "shipwreck": ["ocean_ruin", "monument", "village"],
        "mineshaft": ["trial_chambers", "ancient_city", "military_base", "monument", "mineshaft"],
        "desert_well": ["village", "temple", "military_base", "capital_city"],
        "fossil": ["trial_chambers", "ancient_city"],
        // R22 ("citadels built over pyramids"): a temple or an outpost gives way to a town whose pieces it would cut
        // into. Citadels, Greywall bases, Boreal stations and Capital cities move off temples and outposts themselves
        // (their site checks look these up), so listing them here would loop (start -> givesWay -> their start).
        "temple": ["village"],
        "pillager_outpost": ["village"],
    ]
    private func givesWay(_ s: StructureStart, _ t: StructureType, _ srx: Int, _ srz: Int) -> Bool {
        guard let big = StructureCache.yields[t.name] else { return false }
        @inline(__always) func hit(_ a: IVec3, _ b: IVec3, _ c: IVec3, _ d: IVec3) -> Bool {
            a.x <= d.x && c.x <= b.x && a.y <= d.y && c.y <= b.y && a.z <= d.z && c.z <= b.z
        }
        for name in big {
            // Its own kind: the start of the earlier region (by z, then x) keeps its place. Made raw, without its own
            // giving way, so the check never walks a chain of neighbours.
            if name == t.name {
                let cx0 = floorDiv(s.min.x, CS) - t.reach, cx1 = floorDiv(s.max.x, CS) + t.reach
                let cz0 = floorDiv(s.min.z, CS) - t.reach, cz1 = floorDiv(s.max.z, CS) + t.reach
                for rz in floorDiv(cz0, t.spacing)...floorDiv(cz1, t.spacing) { for rx in floorDiv(cx0, t.spacing)...floorDiv(cx1, t.spacing)
                    where rz < srz || (rz == srz && rx < srx) {
                    let (cx, cz) = candidate(t, rx, rz)
                    guard let b = t.make(seed &+ t.salt &+ UInt64(bitPattern: Int64(cx &* 31 &+ cz)), cx, cz), hit(s.min, s.max, b.min, b.max) else { continue }
                    if s.pieces.contains(where: { p in b.pieces.contains { q in hit(p.min, p.max, q.min, q.max) } }) { return true }
                } }
                continue
            }
            // (A kind that itself gives way may be a big one here too: the yields graph has no cycles, so its own
            // check ends; R22 made temples and outposts give way, and portals still give way to them.)
            guard let o = types.first(where: { $0.name == name }) else { continue }
            let cx0 = floorDiv(s.min.x, CS) - o.reach, cx1 = floorDiv(s.max.x, CS) + o.reach
            let cz0 = floorDiv(s.min.z, CS) - o.reach, cz1 = floorDiv(s.max.z, CS) + o.reach
            for rz in floorDiv(cz0, o.spacing)...floorDiv(cz1, o.spacing) { for rx in floorDiv(cx0, o.spacing)...floorDiv(cx1, o.spacing) {
                guard let b = start(o, regionX: rx, regionZ: rz), hit(s.min, s.max, b.min, b.max) else { continue }
                if s.pieces.contains(where: { p in b.pieces.contains { q in hit(p.min, p.max, q.min, q.max) } }) { return true }
            } }
        }
        return false
    }
    @inline(__always) static func key(_ cx: Int, _ cz: Int) -> Int64 { Int64(cx) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: cz))) }
    // True when no chunk within `reach` chunks of (cx, cz) was generated before the guard was taken.
    func clear(cx: Int, cz: Int, reach r: Int) -> Bool { clear(cx: cx, cz: cz, reach: r, guardSet: legacy) }
    func clear(cx: Int, cz: Int, reach r: Int, guardSet: Set<Int64>) -> Bool {
        if guardSet.isEmpty { return true }
        let side = 2 * r + 1
        if guardSet.count < side * side {                // (a small guard set and a wide reach: walk the set)
            for k in guardSet where abs(Int(k >> 32) - cx) <= r && abs(Int(Int32(truncatingIfNeeded: k)) - cz) <= r { return false }
            return true
        }
        for z in (cz - r)...(cz + r) { for x in (cx - r)...(cx + r) where guardSet.contains(StructureCache.key(x, z)) { return false } }
        return true
    }
    init(seed: UInt64, types: [StructureType], fixed: [StructureStart] = []) {
        self.seed = seed; self.types = types; self.fixed = fixed
    }

    // The structure start in the region containing chunk (rx, rz) for a type, if any.
    func start(_ t: StructureType, regionX rx: Int, regionZ rz: Int) -> StructureStart? {
        let key = StartKey(name: t.name, rx: rx, rz: rz)          // no string built per lookup (several hundred per chunk)
        lock.lock()
        if let c = cache[key] { useClock += 1; used[key] = useClock; lock.unlock(); return c }
        lock.unlock()
        let t0: Double = WorldGen.timing ? CFAbsoluteTimeGetCurrent() : 0
        let (cx, cz) = candidate(t, rx, rz)
        var s: StructureStart?
        if let keep = StructureCache.keepR22[t.name], WorldRules.p44,
           hashf(rx, 2207, rz, UInt32(truncatingIfNeeded: seed) ^ UInt32(truncatingIfNeeded: t.salt)) >= keep,
           clear(cx: cx, cz: cz, reach: t.reach + 1, guardSet: legacyR22) {
            s = nil                                                  // R22: this region stays empty on new ground
        } else {
            s = t.make(seed &+ t.salt &+ UInt64(bitPattern: Int64(cx &* 31 &+ cz)), cx, cz)
        }
        if let st = s, StructureCache.yields[t.name] != nil, clear(cx: cx, cz: cz, reach: t.reach, guardSet: legacyOverlap),
           givesWay(st, t, rx, rz) { s = nil }
        lock.lock()
        cache[key] = s
        useClock += 1; used[key] = useClock
        if cache.count > StructureCache.cap {
            let old = used.sorted { $0.value < $1.value }.prefix(cache.count / 4)
            for (k, _) in old { cache[k] = nil; used[k] = nil }
            StructureCache.evictions += 1
        }
        if WorldGen.timing {
            let ms: Double = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            WorldGen.timingLock.lock(); StructureCache.startMs[t.name, default: 0] += ms; WorldGen.timingLock.unlock()
        }
        lock.unlock()
        return s
    }

    // The region's first candidate chunk (where a start always stood before task 23's alternates).
    // Whether the region's start is already made (the P124 check).
    // P124 (Oct 12 PM, "a freeze of about a second"): the per-second base ticks asked for the nearest Greywall base,
    // Boreal Station and citadel on the frame thread, and a region nobody had looked at yet planned its start right
    // there (a Greywall start tries up to seven sites, each checking ten other kinds' starts nearby: 520 ms caught by
    // HitchProbe). `nearestIfReady` answers only from starts already made and has the missing ones made on a worker,
    // so the base ticks pick the site up a second later instead. (Off in the host checks, whose fixtures expect the
    // answer at once; HitchProbe turns it on.)
    static var plansOffThread = true
    private var planning = Set<StartKey>()
    func nearestIfReady(_ kind: String, x: Int, z: Int, maxRegions: Int = 1) -> StructureStart? {
        guard StructureCache.plansOffThread, fixed.isEmpty || !fixed.contains(where: { $0.kind == kind }),
              let t = types.first(where: { $0.name == kind }) else { return nearest(kind, x: x, z: z, maxRegions: maxRegions) }
        let rx = floorDiv(floorDiv(x, CS), t.spacing), rz = floorDiv(floorDiv(z, CS), t.spacing)
        var missing: [StartKey] = []
        lock.lock()
        for dz in -maxRegions...maxRegions { for dx in -maxRegions...maxRegions {
            let k = StartKey(name: t.name, rx: rx + dx, rz: rz + dz)
            if cache[k] == nil && !planning.contains(k) { missing.append(k); planning.insert(k) }
            else if cache[k] == nil { missing.append(StartKey(name: "", rx: 0, rz: 0)) }      // (already on its way)
        } }
        lock.unlock()
        if missing.isEmpty { return nearest(kind, x: x, z: z, maxRegions: maxRegions) }
        let todo = missing.filter { !$0.name.isEmpty }
        if !todo.isEmpty {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                for k in todo { _ = self.start(t, regionX: k.rx, regionZ: k.rz) }
                self.lock.lock(); for k in todo { self.planning.remove(k) }; StructureCache.offThreadPlans += todo.count; self.lock.unlock()
            }
        }
        return nil
    }
    static var offThreadPlans = 0

    func isCached(_ t: StructureType, regionX rx: Int, regionZ rz: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cache[StartKey(name: t.name, rx: rx, rz: rz)] != nil
    }

    func candidate(_ t: StructureType, _ rx: Int, _ rz: Int) -> (Int, Int) {
        var rng = SRng(seed &+ UInt64(bitPattern: Int64(rx)) &* 341873128712 &+ UInt64(bitPattern: Int64(rz)) &* 132897987541 &+ t.salt)
        let span = t.spacing - t.separation
        return (rx * t.spacing + rng.int(span), rz * t.spacing + rng.int(span))
    }

    func startsNear(cx: Int, cz: Int, _ t: StructureType) -> [StructureStart] {
        var out: [StructureStart] = []
        let r = t.reach
        let rx0 = floorDiv(cx - r, t.spacing), rx1 = floorDiv(cx + r, t.spacing)
        let rz0 = floorDiv(cz - r, t.spacing), rz1 = floorDiv(cz + r, t.spacing)
        for rz in rz0...rz1 { for rx in rx0...rx1 { if let s = start(t, regionX: rx, regionZ: rz) { out.append(s) } } }
        return out
    }

    // Kinds whose footprint is filled underneath (and how deep): buried ones over caves, hillside ones over slopes.
    static let fillDepth: [String: Int] = ["ancient_city": 12, "trial_chambers": 10, "stronghold": 10, "mansion": 8,
                                           "military_base": 24, "trail_ruins": 4,
                                           Greywall.kind: 20]     // Steelhold: hillside bases hung 8+ over slopes
    // Not villages: filling under each column's lowest block also filled under the roof eaves overhanging the
    // doorways, building cobblestone pillars in front of doors (structcheck door_needs_jump, run 349).

    // Harness (questcheck --notespots --trace, P377 step 2): the structure kinds built into each chunk.
    static var traceKinds = false
    static var kinds: [ChunkKey: Set<String>] = [:]
    static let kindsLock = NSLock()
    static func noteKind(_ cx: Int, _ cz: Int, _ k: String) {
        kindsLock.lock(); kinds[ChunkKey(x: cx, z: cz), default: []].insert(k); kindsLock.unlock()
    }

    // Builds every structure piece overlapping this chunk into `blocks`; returns block entities.
    // `mark` (field worlds): set for each cell a structure built (StructWriter.mark).
    func place(into blocks: inout [BlockID], cx: Int, cz: Int, mark: UnsafeMutablePointer<UInt8>? = nil)
        -> (entities: [(IVec3, BlockEntity)], mobs: [(String, V3)]) {
        var ents: [(IVec3, BlockEntity)] = []
        var mobs: [(String, V3)] = []
        blocks.withUnsafeMutableBufferPointer { buf in
            var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
            w.mark = mark
            for t in types {
                for s in startsNear(cx: cx, cz: cz, t) {
                    if StructureCache.traceKinds, s.pieces.contains(where: { $0.overlaps(cx * CS, cz * CS) }) { StructureCache.noteKind(cx, cz, s.kind) }
                    for p in s.pieces where p.overlaps(cx * CS, cz * CS) { p.build(&w) }
                    // Village houses on slopes get foundations; their paths and bridges never dam rivers.
                    if let d = StructureCache.fillDepth[s.kind] { w.fillUnder(depth: d, surface: COBBLE, intoWater: s.kind != "village") }
                    else { for k in 0..<(CS * CS) { w.low.y[k] = Int.max } }
                }
            }
            let bx = cx * CS, bz = cz * CS
            for s in fixed where s.max.x >= bx && s.min.x < bx + CS && s.max.z >= bz && s.min.z < bz + CS {
                if StructureCache.traceKinds { StructureCache.noteKind(cx, cz, s.kind) }
                for p in s.pieces where p.overlaps(bx, bz) { p.build(&w) }
            }
            after?(&w, cx, cz)
            ents = w.entities
            mobs = w.mobs
        }
        return (ents, mobs)
    }

    // P456 (Oct 25 14:03, intercepted orders: "the orders were not accurate. There's nothing here"). The middle of a
    // start's main piece (a citadel's own walls, not the garrison row trailing south of it), and whether the start really
    // lays blocks in the chunk there: its pieces built into an empty chunk, as place() does.
    func siteCentre(_ s: StructureStart) -> IVec3 {
        guard let p = s.pieces.first else { return IVec3((s.min.x + s.max.x) / 2, s.anchor.y, (s.min.z + s.max.z) / 2) }
        return IVec3((p.min.x + p.max.x) / 2, s.anchor.y, (p.min.z + p.max.z) / 2)
    }
    func builds(_ s: StructureStart, at c: IVec3) -> Int {
        let bx = floorDiv(c.x, CS) * CS, bz = floorDiv(c.z, CS) * CS
        var blocks = [BlockID](repeating: AIR, count: CSQ * CH)
        blocks.withUnsafeMutableBufferPointer { buf in
            var w = StructWriter(bx: bx, bz: bz, blocks: buf.baseAddress!)
            for p in s.pieces where p.overlaps(bx, bz) { p.build(&w) }
        }
        return blocks.reduce(0) { $0 + ($1 == AIR ? 0 : 1) }
    }

    // Nearest structure start of a kind (searching regions outward), for locating / the snapshot harness.
    func nearest(_ kind: String, x: Int, z: Int, maxRegions: Int = 6, accept: (StructureStart) -> Bool = { _ in true }) -> StructureStart? {
        let fx = fixed.filter { $0.kind == kind && accept($0) }
        if !fx.isEmpty {
            return fx.min { a, b in
                let da = (a.anchor.x - x) * (a.anchor.x - x) + (a.anchor.z - z) * (a.anchor.z - z)
                let db = (b.anchor.x - x) * (b.anchor.x - x) + (b.anchor.z - z) * (b.anchor.z - z)
                return da < db
            }
        }
        guard let t = types.first(where: { $0.name == kind }) else { return nil }
        let rx = floorDiv(floorDiv(x, CS), t.spacing), rz = floorDiv(floorDiv(z, CS), t.spacing)
        var best: StructureStart?, bd = Int.max
        for r in 0...maxRegions {
            for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                guard let s = start(t, regionX: rx + dx, regionZ: rz + dz), accept(s) else { continue }
                let cx = (s.min.x + s.max.x) / 2 - x, cz = (s.min.z + s.max.z) / 2 - z
                if cx * cx + cz * cz < bd { bd = cx * cx + cz * cz; best = s }
            } }
            if best != nil && r >= 1 { break }
        }
        return best
    }

    // Structure (of a kind) containing a world position — used for structure mob spawns.
    func structure(at x: Int, _ y: Int, _ z: Int, kind: String) -> StructureStart? {
        let cx = floorDiv(x, CS), cz = floorDiv(z, CS)
        for t in types where t.name == kind {
            for s in startsNear(cx: cx, cz: cz, t) where s.contains(x, y, z) { return s }
        }
        for s in fixed where s.kind == kind && s.contains(x, y, z) { return s }
        return nil
    }
}

// MARK: Loot tables (item, min, max, weight) with a number of rolls.

enum Loot {
    static let tables: [String: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)])] = [
        "fortress": (2...4, [("keepers_journal", 1, 1, 6), ("diamond", 1, 3, 5), ("iron_ingot", 1, 5, 5), ("gold_ingot", 1, 3, 15), ("golden_sword", 1, 1, 5),
                             ("golden_chestplate", 1, 1, 5), ("flint_and_steel", 1, 1, 5), ("nether_wart", 3, 7, 5),
                             ("saddle", 1, 1, 10), ("obsidian", 2, 4, 2), ("rib_armor_trim_smithing_template", 1, 1, 1)]),
        "dungeon": (1...3, [("saddle", 1, 1, 20), ("golden_apple", 1, 1, 15), ("enchanted_golden_apple", 1, 1, 2),
                            ("music_disc_otherside", 1, 1, 2), ("music_disc_13", 1, 1, 15), ("music_disc_cat", 1, 1, 15),
                            ("name_tag", 1, 1, 20), ("golden_horse_armor", 1, 1, 10), ("iron_horse_armor", 1, 1, 15),
                            ("diamond_horse_armor", 1, 1, 5), ("enchanted_book", 1, 1, 10)]),
        "stronghold_corridor": (2...3, [("ender_pearl", 1, 1, 10), ("diamond", 1, 3, 3), ("iron_ingot", 1, 5, 10), ("gold_ingot", 1, 3, 5),
                                        ("redstone", 4, 9, 5), ("bread", 1, 3, 15), ("apple", 1, 3, 15), ("iron_pickaxe", 1, 1, 5),
                                        ("iron_sword", 1, 1, 5), ("iron_chestplate", 1, 1, 5), ("iron_helmet", 1, 1, 5),
                                        ("iron_leggings", 1, 1, 5), ("iron_boots", 1, 1, 5), ("golden_apple", 1, 1, 1)]),
        "stronghold_library": (2...10, [("book", 1, 3, 20), ("paper", 2, 7, 20), ("map", 1, 1, 1), ("compass", 1, 1, 1),
                                         ("enchanted_book@30", 1, 1, 10)]),
        "end_city_treasure": (2...6, [("diamond", 2, 7, 5), ("iron_ingot", 4, 8, 10), ("gold_ingot", 2, 7, 15), ("emerald", 2, 6, 2),
                                        ("beetroot_seeds", 1, 10, 5), ("saddle", 1, 1, 3), ("diamond_sword@20-39", 1, 1, 3), ("diamond_pickaxe@20-39", 1, 1, 3),
                                        ("diamond_chestplate@20-39", 1, 1, 3), ("diamond_helmet@20-39", 1, 1, 3), ("diamond_leggings@20-39", 1, 1, 3),
                                        ("diamond_boots@20-39", 1, 1, 3), ("diamond_shovel@20-39", 1, 1, 3), ("iron_sword@20-39", 1, 1, 3),
                                        ("iron_pickaxe@20-39", 1, 1, 3), ("iron_helmet@20-39", 1, 1, 3), ("iron_chestplate@20-39", 1, 1, 3),
                                        ("iron_leggings@20-39", 1, 1, 3), ("iron_boots@20-39", 1, 1, 3), ("iron_shovel@20-39", 1, 1, 3)]),
        "end_ship_elytra": (1...1, [("jetpack", 1, 1, 1)]),          // P156: the jetpack replaces the glider wings
        "jungle_temple": (2...6, [("diamond", 1, 3, 3), ("iron_ingot", 1, 5, 10), ("gold_ingot", 2, 7, 15), ("emerald", 1, 3, 2),
                                  ("bone", 4, 6, 20), ("rotten_flesh", 3, 7, 16), ("saddle", 1, 1, 3), ("bamboo", 1, 3, 15),
                                  ("enchanted_book@30", 1, 1, 1), ("wild_armor_trim_smithing_template", 1, 1, 7)]),
        "igloo_chest": (2...8, [("apple", 1, 3, 15), ("coal", 1, 4, 15), ("gold_nugget", 1, 3, 10), ("stone_axe", 1, 1, 2),
                                ("rotten_flesh", 1, 1, 10), ("emerald", 1, 1, 1), ("wheat", 2, 3, 10)]),
        "pillager_outpost": (2...3, [("wheat", 3, 5, 7), ("potato", 2, 5, 5), ("carrot", 3, 5, 5), ("dark_oak_log", 2, 3, 10),
                                     ("experience_bottle", 0, 1, 7), ("string", 1, 6, 4), ("arrow", 2, 7, 4), ("tripwire_hook", 1, 3, 3),
                                     ("iron_ingot", 1, 3, 3), ("enchanted_book", 1, 1, 1), ("sentry_armor_trim_smithing_template", 1, 1, 2)]),
        "ruined_portal": (4...8, [("obsidian", 1, 2, 40), ("flint", 1, 4, 40), ("iron_nugget", 9, 18, 40), ("flint_and_steel", 1, 1, 40),
                                  ("fire_charge", 1, 1, 40), ("golden_apple", 1, 1, 15), ("gold_nugget", 4, 24, 15), ("golden_sword", 1, 1, 15),
                                  ("golden_axe", 1, 1, 15), ("golden_hoe", 1, 1, 15), ("golden_shovel", 1, 1, 15), ("golden_pickaxe", 1, 1, 15),
                                  ("golden_boots@0", 1, 1, 15), ("golden_chestplate@0", 1, 1, 15), ("golden_helmet", 1, 1, 15), ("golden_leggings", 1, 1, 15),
                                  ("glistering_melon_slice", 4, 12, 5), ("golden_carrot", 4, 12, 5), ("gold_ingot", 2, 8, 5), ("clock", 1, 1, 5),
                                  ("light_weighted_pressure_plate", 1, 1, 5), ("gold_block", 1, 2, 1)]),
        "shipwreck_supply": (3...10, [("paper", 1, 12, 8), ("potato", 2, 6, 7), ("carrot", 4, 8, 7), ("wheat", 8, 21, 7), ("coal", 2, 8, 6),
                                      ("rotten_flesh", 5, 24, 5), ("gunpowder", 1, 5, 3), ("leather_helmet", 1, 1, 3), ("leather_chestplate", 1, 1, 3),
                                      ("bamboo", 1, 3, 2), ("pumpkin", 1, 3, 2), ("tnt", 1, 2, 1)]),
        "shipwreck_treasure": (3...6, [("iron_ingot", 1, 5, 90), ("gold_ingot", 1, 5, 10), ("emerald", 1, 5, 40), ("diamond", 1, 1, 5),
                                       ("experience_bottle", 1, 1, 5)]),
        "shipwreck_map": (1...3, [("paper", 1, 10, 20), ("feather", 1, 5, 10), ("book", 1, 5, 5), ("clock", 1, 1, 1), ("compass", 1, 1, 1),
                                  ("map", 1, 1, 1)]),
        "buried_treasure": (1...1, [("heart_of_the_sea", 1, 1, 1)]),
        "sheriff_locker": (3...6, [("rifle_rounds", 4, 12, 10), ("shotgun_shells", 2, 6, 6), ("gold_nugget", 2, 8, 8), ("emerald", 1, 3, 6),
                                   ("lead", 1, 2, 4), ("paper", 1, 4, 6), ("compass", 1, 1, 2), ("iron_ingot", 1, 3, 4)]),
        "shop_register": (2...5, [("gold_nugget", 2, 9, 12), ("emerald", 1, 3, 8), ("iron_ingot", 1, 3, 6), ("gold_ingot", 1, 2, 4),
                                  ("paper", 1, 4, 6), ("bread", 1, 3, 4), ("diamond", 1, 1, 1)]),
        "shop_register_general": (3...6, [("gold_nugget", 3, 12, 12), ("emerald", 1, 5, 10), ("gold_ingot", 1, 3, 6), ("iron_ingot", 1, 4, 6),
                                          ("paper", 2, 6, 6), ("compass", 1, 1, 2), ("diamond", 1, 2, 2), ("town_pamphlet", 1, 1, 4)]),
        "village_house": (3...8, [("gold_nugget", 1, 3, 1), ("dandelion", 1, 1, 2), ("poppy", 1, 1, 1), ("potato", 1, 7, 10),
                                  ("bread", 1, 4, 10), ("apple", 1, 5, 10), ("book", 1, 1, 1), ("feather", 1, 1, 1), ("emerald", 1, 4, 2),
                                  ("oak_sapling", 1, 2, 5), ("wheat", 1, 7, 5), ("carrot", 1, 5, 5), ("town_pamphlet", 1, 1, 4)]),
        "village": (3...8, [("diamond", 1, 3, 3), ("iron_ingot", 1, 5, 10), ("gold_ingot", 1, 3, 5), ("bread", 1, 3, 15),
                            ("apple", 1, 3, 15), ("iron_pickaxe", 1, 1, 5), ("iron_sword", 1, 1, 5), ("obsidian", 3, 7, 5),
                            ("oak_sapling", 3, 7, 5), ("iron_helmet", 1, 1, 5)]),
        "desert_pyramid": (2...4, [("diamond", 1, 3, 5), ("iron_ingot", 1, 5, 15), ("gold_ingot", 2, 7, 15), ("emerald", 1, 3, 15),
                                   ("bone", 4, 6, 25), ("spider_eye", 1, 3, 25), ("rotten_flesh", 3, 7, 25), ("saddle", 1, 1, 20),
                                   ("iron_horse_armor", 1, 1, 15), ("golden_horse_armor", 1, 1, 10), ("diamond_horse_armor", 1, 1, 5),
                                   ("golden_apple", 1, 1, 20), ("enchanted_book", 1, 1, 20), ("enchanted_golden_apple", 1, 1, 2),
                                   ("empty", 0, 0, 15), ("dune_armor_trim_smithing_template", 1, 1, 4)]),
        "mineshaft": (1...1, [("golden_apple", 1, 1, 20), ("enchanted_golden_apple", 1, 1, 1), ("name_tag", 1, 1, 30),
                              ("enchanted_book", 1, 1, 10), ("iron_pickaxe", 1, 1, 5), ("empty", 0, 0, 5)]),
        "mansion": (1...3, [("lead", 1, 1, 20), ("golden_apple", 1, 1, 15), ("enchanted_golden_apple", 1, 1, 2), ("music_disc_13", 1, 1, 15),
                             ("name_tag", 1, 1, 20), ("chainmail_chestplate", 1, 1, 10), ("diamond_hoe", 1, 1, 15), ("diamond_chestplate", 1, 1, 5),
                             ("enchanted_book", 1, 1, 10), ("iron_ingot", 1, 4, 10), ("redstone", 1, 4, 15), ("bread", 1, 1, 20),
                             ("vex_armor_trim_smithing_template", 1, 1, 10)]),
        "ancient_city": (5...10, [("enchanted_golden_apple", 1, 2, 1), ("disc_fragment_5", 1, 3, 2), ("amethyst_shard", 1, 15, 3),
                                  ("echo_shard", 1, 3, 4), ("diamond_hoe@30-50", 1, 1, 3), ("diamond_leggings@30-50", 1, 1, 2),
                                  ("enchanted_book", 1, 1, 5), ("sculk_catalyst", 1, 2, 3), ("candle", 1, 4, 3), ("bone", 1, 15, 5),
                                  ("soul_torch", 1, 15, 2), ("sculk", 4, 10, 3), ("experience_bottle", 1, 3, 3), ("glow_berries", 1, 15, 3),
                                  ("iron_leggings@20-39", 1, 1, 3), ("ward_armor_trim_smithing_template", 1, 1, 4),
                                  ("silence_armor_trim_smithing_template", 1, 1, 1), ("recovery_compass", 1, 1, 2)]),
        "trial_chambers_corridor": (1...3, [("iron_axe@0", 1, 1, 1), ("honeycomb", 1, 8, 1), ("stone_axe", 1, 1, 2), ("stone_pickaxe", 1, 1, 2),
                                            ("ender_pearl", 1, 2, 2), ("bamboo_hanging_sign", 1, 4, 2), ("bamboo_planks", 3, 6, 2), ("scaffolding", 2, 10, 2),
                                            ("torch", 3, 6, 2), ("tuff", 8, 20, 3)]),
        "trial_vault": (1...3, [("emerald", 2, 4, 5), ("arrow", 2, 8, 4), ("iron_ingot", 1, 2, 4), ("wind_charge", 4, 12, 4),
                                ("honey_bottle", 1, 2, 3), ("ominous_bottle", 1, 1, 2), ("diamond", 1, 2, 2), ("golden_apple", 1, 1, 2),
                                ("enchanted_book", 1, 1, 3), ("crossbow@5-15", 1, 1, 2), ("iron_axe@0", 1, 1, 2), ("diamond_axe@0", 1, 1, 1),
                                ("heavy_core", 1, 1, 1), ("flow_armor_trim_smithing_template", 1, 1, 1), ("bolt_armor_trim_smithing_template", 1, 1, 1)]),
        "trial_spawner": (1...2, [("trial_key", 1, 1, 5), ("emerald", 1, 2, 3), ("arrow", 3, 6, 3), ("bread", 1, 3, 3), ("baked_potato", 1, 3, 3),
                                  ("cooked_chicken", 1, 2, 2), ("honey_bottle", 1, 1, 1), ("glow_berries", 2, 10, 1)]),
        "ocean_ruin_big": (2...8, [("coal", 1, 4, 10), ("gold_nugget", 1, 3, 10), ("emerald", 1, 1, 1), ("wheat", 2, 3, 10), ("golden_apple", 1, 1, 1),
                                   ("enchanted_book", 1, 1, 5), ("leather_chestplate", 1, 1, 1), ("golden_helmet", 1, 1, 1), ("fishing_rod@0", 1, 1, 5), ("map", 1, 1, 10)]),
        "ocean_ruin_small": (2...8, [("coal", 1, 4, 10), ("stone_axe", 1, 1, 2), ("rotten_flesh", 1, 1, 5), ("emerald", 1, 1, 1), ("wheat", 2, 3, 10),
                                     ("leather_chestplate", 1, 1, 1), ("golden_helmet", 1, 1, 1), ("fishing_rod@0", 1, 1, 5), ("map", 1, 1, 5)]),
        "archaeology_desert": (1...1, [("archer_pottery_sherd", 1, 1, 1), ("miner_pottery_sherd", 1, 1, 1), ("prize_pottery_sherd", 1, 1, 1),
                                       ("skull_pottery_sherd", 1, 1, 1), ("diamond", 1, 1, 1), ("tnt", 1, 1, 1), ("gunpowder", 1, 1, 1), ("emerald", 1, 1, 1)]),
        "archaeology_trail": (1...1, [("burn_pottery_sherd", 1, 1, 1), ("danger_pottery_sherd", 1, 1, 1), ("friend_pottery_sherd", 1, 1, 1),
                                      ("heart_pottery_sherd", 1, 1, 1), ("heartbreak_pottery_sherd", 1, 1, 1), ("howl_pottery_sherd", 1, 1, 1),
                                      ("sheaf_pottery_sherd", 1, 1, 1), ("wayfinder_armor_trim_smithing_template", 1, 1, 1),
                                      ("raiser_armor_trim_smithing_template", 1, 1, 1), ("shaper_armor_trim_smithing_template", 1, 1, 1),
                                      ("host_armor_trim_smithing_template", 1, 1, 1), ("emerald", 1, 1, 2), ("wheat", 1, 1, 2),
                                      ("wooden_hoe", 1, 1, 2), ("coal", 1, 1, 2), ("gold_nugget", 1, 1, 2), ("brick", 1, 1, 2)]),
        "archaeology_ocean": (1...1, [("angler_pottery_sherd", 1, 1, 1), ("shelter_pottery_sherd", 1, 1, 1), ("snort_pottery_sherd", 1, 1, 1),
                                      ("sniffer_egg", 1, 1, 1), ("iron_axe", 1, 1, 1), ("emerald", 1, 1, 2), ("wheat", 1, 1, 2), ("coal", 1, 1, 2)]),
        "bastion": (3...5, [("gold_ingot", 3, 9, 10), ("gold_block", 1, 2, 5), ("netherite_scrap", 1, 1, 3), ("diamond", 1, 3, 3),
                            ("crying_obsidian", 3, 8, 10), ("spectral_arrow", 10, 22, 6), ("golden_carrot", 6, 17, 10),
                            ("iron_ingot", 2, 6, 10), ("obsidian", 4, 6, 10), ("magma_cream", 2, 6, 4),
                            ("diamond_sword@20-39", 1, 1, 3), ("diamond_chestplate@20-39", 1, 1, 3), ("diamond_helmet@20-39", 1, 1, 3),
                            ("diamond_boots@20-39", 1, 1, 3), ("enchanted_golden_apple", 1, 1, 2),
                            ("netherite_upgrade_smithing_template", 1, 1, 6), ("snout_armor_trim_smithing_template", 1, 1, 2)]),
        // Steelhold fortresses (MilitaryBase.swift): guns, ammunition and supplies.
        "steelhold_armory": (3...6, [("gun_rifle", 1, 1, 12), ("gun_shotgun", 1, 1, 6), ("gun_sniper", 1, 1, 3),
                                     ("capital_rounds", 16, 48, 20), ("shotgun_shells", 6, 18, 12), ("heavy_rounds", 4, 12, 8), ("rocket_ammo", 1, 3, 4),
                                     ("arc_cell", 2, 8, 4), ("iron_chestplate", 1, 1, 4), ("iron_helmet", 1, 1, 4), ("shield", 1, 1, 3),
                                     ("firing_mechanism", 1, 2, 7)]),
        "steelhold_supply": (4...8, [("capital_ration", 2, 6, 14), ("bread", 2, 6, 15), ("cooked_beef", 2, 5, 10), ("baked_potato", 2, 6, 10), ("iron_ingot", 2, 6, 10),
                                     ("copper_ingot", 4, 12, 8), ("gunpowder", 2, 8, 10), ("capital_rounds", 8, 32, 12), ("redstone", 4, 12, 6),
                                     ("tnt", 1, 3, 3), ("golden_apple", 1, 1, 2), ("compass", 1, 1, 2), ("map", 1, 1, 2), ("capital_duty_log", 1, 1, 5)]),
        "steelhold_command": (4...7, [("capital_ration", 2, 4, 6), ("diamond", 2, 6, 8), ("emerald", 3, 8, 6), ("gun_sniper", 1, 1, 6), ("gun_launcher", 1, 1, 5),
                                      ("gun_arc", 1, 1, 5), ("heavy_rounds", 6, 15, 8), ("rocket_ammo", 2, 6, 6), ("arc_cell", 4, 12, 6),
                                      ("diamond_chestplate@20-30", 1, 1, 3), ("golden_apple", 1, 2, 5), ("enchanted_golden_apple", 1, 1, 1),
                                      ("experience_bottle", 3, 8, 6), ("firing_mechanism", 1, 2, 6), ("targeting_optic", 1, 1, 5),
                                      ("radar_module", 1, 1, 4), ("intercepted_orders", 1, 2, 7), ("capital_signal_log", 1, 1, 6)]),
        // The Meridian frigate's hold and bridge locker (CapitalFrigate.swift): post-game spoils.
        "meridian_hold": (4...7, [("diamond", 3, 8, 10), ("gun_launcher", 1, 1, 6), ("gun_arc", 1, 1, 6), ("gun_sniper", 1, 1, 5),
                                  ("rocket_ammo", 4, 10, 8), ("heavy_rounds", 8, 16, 8), ("arc_cell", 6, 14, 6),
                                  ("firing_mechanism", 1, 3, 8), ("targeting_optic", 1, 2, 6), ("radar_module", 1, 1, 4),
                                  ("netherite_scrap", 1, 3, 4), ("enchanted_golden_apple", 1, 1, 2), ("experience_bottle", 4, 10, 6)]),
        // Capital cities (CapitalCity.swift): offices and homes; the odd base component or patrol orders.
        "capital_city": (3...6, [("bread", 2, 5, 14), ("cookie", 3, 8, 8), ("apple", 2, 5, 10), ("paper", 3, 9, 10), ("book", 1, 3, 8),
                                 ("emerald", 1, 4, 8), ("gold_ingot", 1, 4, 6), ("clock", 1, 1, 3), ("compass", 1, 1, 3),
                                 ("rifle_rounds", 8, 24, 6), ("glass_bottle", 2, 4, 4), ("white_wool", 2, 6, 5), ("capital_recruiting_pamphlet", 1, 1, 6), ("town_pamphlet", 1, 1, 4)]),
        // Brimstone Keeps (BrimstoneKeep.swift): the hell band's strongholds and the Sunderite strongroom under each keep.
        "brimstone_keep": (3...6, [("keepers_journal", 1, 1, 4), ("raw_sunderite", 1, 2, 5), ("gold_ingot", 2, 6, 12), ("netherite_scrap", 1, 2, 4), ("blaze_rod", 2, 6, 10),
                                   ("rifle_rounds", 12, 32, 10), ("heavy_rounds", 4, 10, 6), ("golden_apple", 1, 1, 4), ("diamond", 1, 3, 6),
                                   ("tnt", 1, 3, 6)]),
        "brimstone_strongroom": (4...7, [("raw_sunderite", 1, 3, 14), ("netherite_scrap", 1, 3, 6), ("diamond", 2, 4, 8), ("gold_block", 1, 2, 6),
                                         ("enchanted_golden_apple", 1, 1, 1), ("experience_bottle", 3, 8, 6), ("blaze_powder", 2, 6, 8)]),
        // The Ashguard's sites in the Deep (AshSites.swift): what an army at war keeps in its depots.
        "ash_armory": (3...6, [("gun_kessel", 1, 1, 10), ("gun_sturmwind", 1, 1, 10), ("gun_hagel", 1, 1, 8),
                               ("gun_launcher", 1, 1, 4), ("gun_faust", 1, 1, 10), ("faust_warhead", 1, 4, 12), ("rifle_rounds", 16, 48, 20),
                               ("heavy_rounds", 6, 16, 10), ("rocket_ammo", 2, 6, 12), ("shotgun_shells", 6, 18, 6), ("tnt", 2, 6, 8),
                               ("iron_chestplate", 1, 1, 4), ("iron_helmet", 1, 1, 4), ("golden_apple", 1, 1, 3)]),
        "ash_supply": (4...8, [("aero_spares", 1, 1, 2), ("track_spares", 1, 2, 4), ("ashguard_journal", 1, 1, 5), ("bread", 3, 8, 15), ("cooked_beef", 2, 6, 12), ("baked_potato", 3, 8, 10), ("iron_ingot", 3, 8, 10),
                               ("gold_ingot", 2, 6, 8), ("gunpowder", 3, 9, 10), ("rifle_rounds", 12, 40, 12), ("rocket_ammo", 1, 4, 8), ("faust_warhead", 1, 3, 6),
                               ("coal", 4, 12, 8), ("golden_apple", 1, 1, 3), ("potion_healing", 1, 2, 4)]),
        "ash_fuel": (3...6, [("coal_block", 1, 4, 12), ("blaze_powder", 2, 6, 8), ("gunpowder", 4, 12, 12), ("tnt", 2, 6, 8),
                             ("fire_charge", 2, 6, 8), ("rocket_ammo", 2, 4, 6), ("iron_ingot", 2, 6, 8)]),
        // P346: what the bomber's crew had aboard, and the spares that put a crashed fighter back in the air.
        "ash_bomber": (3...5, [("aero_spares", 1, 2, 14), ("rifle_rounds", 8, 24, 6), ("bread", 1, 3, 4), ("paper", 2, 6, 3),
                               ("compass", 1, 1, 2), ("iron_ingot", 2, 5, 4)]),
        "ash_command": (5...9, [("aero_spares", 1, 1, 3), ("track_spares", 1, 2, 3), ("ashguard_journal", 1, 1, 5), ("diamond", 3, 8, 10), ("gold_ingot", 6, 16, 10), ("emerald", 4, 12, 6), ("gun_launcher", 1, 1, 6),
                                ("gun_sturmwind", 1, 1, 8),
                                ("gun_arc", 1, 1, 6), ("rocket_ammo", 4, 10, 10), ("arc_cell", 6, 14, 6), ("netherite_scrap", 1, 3, 4),
                                ("diamond_chestplate@25-35", 1, 1, 3), ("enchanted_golden_apple", 1, 1, 2), ("experience_bottle", 4, 10, 6),
                                ("hannibal_armour_set", 1, 1, 2)]),   // P350: the flight suit, findable
        "steelhold_vault": (5...9, [("diamond", 3, 8, 10), ("gold_ingot", 6, 16, 10), ("emerald", 4, 12, 8), ("gun_launcher", 1, 1, 6),
                                    ("gun_arc", 1, 1, 6), ("rocket_ammo", 4, 8, 8), ("arc_cell", 8, 16, 8), ("netherite_scrap", 1, 2, 3),
                                    ("diamond_sword@25-35", 1, 1, 3), ("enchanted_golden_apple", 1, 1, 2), ("targeting_optic", 1, 2, 6),
                                    ("radar_module", 1, 1, 5), ("intercepted_orders", 1, 2, 6), ("hannibal_armour_set", 1, 1, 3)]),   // P350
    ]

    // "name@a-b": enchant with a-b levels (treasure allowed); "name@0": enchant randomly (50%);
    // "enchanted_book": one random enchantment.
    static func stack(_ name: String, _ n: Int, rng: inout SRng) -> ItemStack {
        let parts = name.split(separator: "@")
        let base = String(parts[0])
        var st = ItemStack(Items.id(base), n)
        if base == "enchanted_book" && parts.count == 1 {
            st.ench = Enchant.pack(Enchant.randomly(Items.id("book")))
        } else if parts.count == 2 {
            let r = parts[1].split(separator: "-").compactMap { Int($0) }
            if r.first == 0 {
                if rng.chance(0.5) { st.ench = Enchant.pack(Enchant.randomly(st.item)) }
            } else if let lo = r.first {
                let lv = rng.range(lo, r.count > 1 ? r[1] : lo)
                let e = Enchant.withLevels(base == "enchanted_book" ? Items.id("book") : st.item, lv, treasure: true)
                st.ench = e.ench
            }
        }
        return st
    }

    // Further pools rolled after a table's own (the reference tables have several; one merged weighted pool made a
    // buried treasure chest five Hearts of the Sea and left dungeons with 1-3 items). "empty" entries roll nothing.
    static let extraPools: [String: [(rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)])]] = [
        "dungeon": [(1...4, [("iron_ingot", 1, 4, 10), ("gold_ingot", 1, 4, 5), ("bread", 1, 1, 20), ("wheat", 1, 4, 20), ("bucket", 1, 1, 10),
                              ("redstone", 1, 4, 15), ("coal", 1, 4, 15), ("melon_seeds", 2, 4, 10), ("pumpkin_seeds", 2, 4, 10),
                              ("beetroot_seeds", 2, 4, 10)]),
                    (3...3, [("bone", 1, 8, 10), ("gunpowder", 1, 8, 10), ("rotten_flesh", 1, 8, 10), ("string", 1, 8, 10)])],
        "buried_treasure": [(5...8, [("iron_ingot", 1, 4, 20), ("gold_ingot", 1, 4, 10), ("tnt", 1, 2, 5)]),
                            (1...3, [("emerald", 4, 8, 5), ("diamond", 1, 2, 5), ("prismarine_crystals", 1, 5, 5)]),
                            (0...1, [("leather_chestplate", 1, 1, 1), ("iron_sword", 1, 1, 1)]),
                            (2...2, [("cooked_cod", 2, 4, 1), ("cooked_salmon", 2, 4, 1)])],
        "desert_pyramid": [(4...4, [("bone", 1, 8, 10), ("gunpowder", 1, 8, 10), ("rotten_flesh", 1, 8, 10), ("string", 1, 8, 10), ("sand", 1, 8, 10)])],
        "mineshaft": [(2...4, [("iron_ingot", 1, 5, 10), ("gold_ingot", 1, 3, 5), ("redstone", 4, 9, 5), ("lapis_lazuli", 4, 9, 5),
                               ("diamond", 1, 2, 3), ("coal", 3, 8, 10), ("bread", 1, 3, 15), ("glow_berries", 3, 6, 15),
                               ("melon_seeds", 2, 4, 10), ("pumpkin_seeds", 2, 4, 10), ("beetroot_seeds", 2, 4, 10)]),
                      (3...3, [("rail", 4, 8, 20), ("powered_rail", 1, 4, 5), ("detector_rail", 1, 4, 5), ("activator_rail", 1, 4, 5),
                               ("torch", 1, 16, 15)])],
        "igloo_chest": [(1...1, [("golden_apple", 1, 1, 1)])],
        // The way into hell is base loot (HellGate.swift): every command chest holds an Ember Charge, a vault one or two.
        // Outlaws rob Capital couriers, a dead courier's pack lies in an abandoned camp and traders sell what they find:
        // these camps always hold intercepted orders (the first citadel's map, G6).
        "camp_outlaws": [(1...1, [("intercepted_orders", 1, 2, 1)])],
        "camp_abandoned": [(1...1, [("intercepted_orders", 1, 1, 1)])],
        "camp_traders": [(1...1, [("intercepted_orders", 1, 1, 1)])],
        "steelhold_command": [(1...1, [("ember_charge", 1, 1, 1)])],
        // Greywall Command (Greywall.swift): every command chest holds a radar module (the radar network), every vault gold.
        "greywall_command": [(1...1, [("radar_module", 1, 1, 1)]), (1...1, [("greywall_keycard", 1, 1, 1)])],   // (+ D35 keycard)
        "greywall_vault": [(1...1, [("gold_block", 1, 2, 1)])],
        // D33: each army's armour kit, one armoury chest in three (FactionArmour.swift).
        "greywall_armory": [(1...1, [("greywall_armour_kit", 1, 1, 1), ("empty", 1, 1, 2)])],
        "steelhold_armory": [(1...1, [("capital_armour_kit", 1, 1, 1), ("empty", 1, 1, 2)])],
        "ash_armory": [(1...1, [("ashguard_armour_kit", 1, 1, 1), ("empty", 1, 1, 2)])],
        "steelhold_vault": [(1...1, [("ember_charge", 1, 2, 1)])],
        "shipwreck_treasure": [(2...5, [("iron_nugget", 1, 10, 50), ("gold_nugget", 1, 10, 10), ("lapis_lazuli", 1, 10, 20)])],
    ]

    static func fill(_ c: ItemContainer, table: String, rng: inout SRng) {
        if table == "base_sundries" { roll(c, BaseSundries.barrel.rolls, BaseSundries.barrel.entries, rng: &rng); return }
        if table == BaseMaterials.loot { roll(c, BaseMaterials.table.rolls, BaseMaterials.table.entries, rng: &rng); return }   // P254
        if table == BaseSafes.loot || table == BaseSafes.greyLoot {     // P248
            // P256: Greywall's safe swaps the Capital's Fernblick for its own Slate Repeater.
            let entries = table == BaseSafes.greyLoot ? BaseSafes.table.entries.map { $0.0 == "gun_sniper" ? ("gun_repeater", $0.1, $0.2, $0.3) : $0 }
                                                      : BaseSafes.table.entries
            roll(c, BaseSafes.table.rolls, entries, rng: &rng)
            Loot.matchGuns(c, rng: &rng)
            GunGrade.gradeChest(c, table: "steelhold_vault", rng: &rng)
            return
        }
        guard let t = tables[table] ?? WildCamps.loot[table] ?? Greywall.loot[table] ?? Depots.loot[table] ?? SkyIsle.loot[table] ?? MiningTowns.loot[table] ?? NavalPort.loot[table] ?? FrontierSites.loot[table] else { return }
        roll(c, t.rolls, t.entries, rng: &rng)
        for pool in extraPools[table] ?? [] { roll(c, pool.rolls, pool.entries, rng: &rng) }
        if BaseSundries.supplyTables.contains(table) { roll(c, BaseSundries.supplyPool.rolls, BaseSundries.supplyPool.entries, rng: &rng) }
        Blueprints.addToChest(c, table: table, rng: &rng)                // P138
        VehiclePresets.addToChest(c, table: table, rng: &rng)            // D43
        Loot.matchGuns(c, rng: &rng)                                     // P216/P217
        GunGrade.gradeChest(c, table: table, rng: &rng)                  // T7
    }

    // P216: a chest with a gun in it also holds a magazine or two of that gun's ammunition (loot that matches the guns
    // found with it).
    static func matchGuns(_ c: ItemContainer, rng: inout SRng) {
        var need: [String] = []
        for i in 0..<c.count where !c[i].isEmpty {
            let k = Items.key(c[i].item)
            if let gi = Guns.index(c[i].item) { need.append(Guns.all[gi].ammo) }
        }
        for a in Set(need) where Items.has(a) {
            guard !(0..<c.count).contains(where: { Items.key(c[$0].item) == a }) else { continue }
            guard let slot = (0..<c.count).first(where: { c[$0].isEmpty }) else { return }
            let gi = Guns.all.firstIndex { $0.ammo == a } ?? 0
            let mag = Guns.all[gi].mag
            c[slot] = ItemStack(Items.id(a), min(Items.def(Items.id(a)).maxStack, max(2, mag * rng.range(1, 2))))
        }
    }

    private static func roll(_ c: ItemContainer, _ rolls: ClosedRange<Int>, _ all: [(String, Int, Int, Int)], rng: inout SRng) {
        let entries = all.filter { $0.0 == "empty" || Items.has(String($0.0.split(separator: "@")[0])) }
        let total = entries.reduce(0) { $0 + $1.3 }
        guard total > 0, c.count > 0 else { return }
        let n = rng.range(rolls.lowerBound, rolls.upperBound)
        for _ in 0..<n {
            var r = rng.int(total)
            for e in entries {
                r -= e.3
                if r < 0 {
                    if e.0 == "empty" { break }
                    var slot = rng.int(c.count)
                    for _ in 0..<c.count where !c[slot].isEmpty { slot = (slot + 1) % c.count }
                    if !c[slot].isEmpty { return }                       // chest full
                    c[slot] = stack(e.0, rng.range(e.1, e.2), rng: &rng)
                    break
                }
            }
        }
    }
}

// A value computed on first use and kept, thread-safe (structure layouts share parts their pieces need only when built).
final class LazyValue<T> {
    private var v: T?
    private let make: () -> T
    private let lock = NSLock()
    init(_ make: @escaping () -> T) { self.make = make }
    var value: T {
        lock.lock(); defer { lock.unlock() }
        if let v = v { return v }
        let x = make()
        v = x
        return x
    }
}
