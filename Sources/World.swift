import Foundation
import Metal
import simd

// Owns all loaded chunks of one dimension. Generation and meshing run on a concurrent background
// queue; results are applied on the main thread in update(). Chunk block arrays are Swift
// copy-on-write values, so handing snapshots to worker threads is safe.
final class World {
    var damage: [IVec3: UInt8] = [:]      // progressive block damage (chip, damageList)
    var bites: [IVec3: [Bite]] = [:]      // realistic world: where blows struck a block (Craters.swift; biteList)
    let gen: TerrainGenerator
    let dim: Dim
    let seed: UInt64
    let device: MTLDevice
    let save: SaveManager?
    // PG1 rewrite: natural terrain is a density field, not blocks (FieldTerrain.swift). Decided once per world: a root
    // save made as a field world keeps a marker (terrain-field.txt); its dimensions follow it (Game.dimensionState).
    var fieldTerrain = false { didSet { save?.fieldWorld = fieldTerrain; (gen as? HollowGen)?.fieldTops = fieldTerrain; gradeRails() } }
    // P379 step 3: a field world's railways run on a gentle grade, in field worlds made since (railway-grade.txt; a
    // field world saved before keeps its stepped lines, so no line changes under explored ground).
    func gradeRails() { (gen as? WorldGen)?.fieldWorld = fieldTerrain && (save?.hasMarker("railway-grade.txt") ?? true) }
    var chunks: [ChunkKey: Chunk] = [:] { didSet { chunksEpoch &+= 1 } }
    private(set) var chunksEpoch = 0           // P385: bumped at every change of `chunks` (the Quest's cull table)
    var blockEntities: [IVec3: BlockEntity] = [:]
    static var lessWaterUnsaved = false      // H8 water, the same way
    static var fewerLakesUnsaved = false     // P44 water for worlds with no save (harness; a co-op guest takes the host's)
    var pendingMobs: [(String, V3)] = []
    var rainLevel: Float = 0                        // set by the game: rain puts out exposed fires
    var gravityQueue: [IVec3] = []                  // cells to check for sand/gravel/anvils that should fall
    var gravityScratch: [IVec3] = []                // Game.gravityTick's reused batch buffer
    static let fallingIDs: [Bool] = {
        var t = [Bool](repeating: false, count: Blocks.count)
        for i in 0..<Blocks.count {
            let k = Blocks.key(Blocks.groupBase[i])
            if ["sand", "red_sand", "gravel", "anvil", "chipped_anvil", "damaged_anvil", "dragon_egg", "suspicious_sand", "suspicious_gravel", "scaffolding"].contains(k)
                || k.hasSuffix("_concrete_powder") { t[i] = true }
        }
        return t
    }()          // structure mobs waiting for the game to spawn them
    lazy var redstone = Circuit(world: self)
    var portals = Set<IVec3>()
    lazy var ships = ShipManager(world: self)       // free-moving block structures (Ships.swift)
    var frame: Ship?                                // while set, block and collision queries are in this ship's space
    var renderDistance: Int = 8 {
        didSet {
            lastCenter = nil; rebuildOffsets()
            if renderDistance < oldValue { trimIn = 150 }         // P415: the far meshes' slabs go back a little later
        }
    }
    private var trimIn = 0
    // P339 (Remington, Oct 17: "you can see 24, but it would be the loading distance that matters"): the VIEW distance
    // above is what is generated, meshed and drawn; the ACTIVE distance (chunks, 4-16) is where mobs think and move,
    // crops grow, weather and seasons touch blocks and creatures spawn. Past it nothing ticks: mobs stand in their last
    // pose. The Auto governor lowers this one, never the view.
    var activeDistance: Int = 8
    var activeCenter = V3(0, 0, 0)                  // the player, as of the last update (FarTicks.swift)
    var shellClock = 0
    var parked: [ChunkKey: [(IVec3, UInt8)]] = [:]  // P376: fluid (1 water, 2 lava) and falling (0) cells past the active distance
    var hotZones: [(center: V3, r: Float, until: Double)] = []      // far strikes the world runs round for a while (FarTicks)
    var strikeRefills = Set<ChunkKey>()             // shells a far strike waits on: handed over first (World.dataReady)
    lazy var meshCache: MeshCache? = World.shells ? save.flatMap { MeshCache(saveDir: $0.chunkDir) } : nil      // P376 (ChunkShells)
    var collapseQueue: [(IVec3, Int)] = [] // P351: carves to check for loose ground (GroundCollapse)
    var batchShape = false                 // a blast opening its cells: the bowl carved after shapes them (Explosion)
    var tipQueue: [(IVec3, Int)] = []      // P503: blasts that broke built blocks, what stood over them weighed (StructureTip)
    var loadQueue: [IVec3] = []            // P388: structural changes whose piece carries its load next (Structure.tick)
    var loadQueued = Set<IVec3>()          // (4-cubes already queued)
    var restoring = false                  // P416: a base's crew putting its own plan back (sound as built: no load check)
    var collapsing = false
    // P338 step 8: free building pieces (FreeBuild.swift) and their collision boxes by cell.
    var pieces: [FreePiece] = []
    var pieceCells: [IVec3: [(V3, V3)]] = [:]
    var piecesDirty = false
    var strayPieces = false, strayTick = 0      // (P448: wall pieces of non-wall blocks left to turn back into blocks)
    // P389: struck objects, one piece each, cut where hit (WorldObjectsWorld.swift).
    let objectReg = WorldObjects.Registry()
    static let activeOptions = [4, 6, 8, 10, 12, 16]
    // Whether a point is inside the active distance of `p` (square, like the chunk rings).
    @inline(__always) func isActive(_ q: V3, from p: V3) -> Bool {
        let r = Float(min(activeDistance, renderDistance) * CS + CS / 2)
        return abs(q.x - p.x) <= r && abs(q.z - p.z) <= r
    }

    // Workers: maxJobs run at once; up to maxQueued jobs are handed over per frame so workers never sit
    // idle between frames (handing over only maxJobs capped streaming at ~maxJobs x 60 jobs per second;
    // 8 per worker covers a 16 ms frame of ~2 ms jobs).
    private let workQueue = JobPool.shared      // P283 (JobPool.swift): was an OperationQueue per world
    private var maxQueued: Int { maxJobs * 8 }
    private let lock = NSLock()
    private var genResults: [(ChunkKey, Produced)] = []
    private var meshResults: [(ChunkKey, [(Int, Int, SectionMesh)])] = []
    private var genInFlight = Set<ChunkKey>()
    private var jobs = 0
    var jobsOut: Int { jobs }                 // (harness: generation and mesh jobs not yet installed)
    private var frontOut = Set<ChunkKey>()     // P446: chunks with an edit's mesh job ahead of the queue
    static var frontAll = ProcessInfo.processInfo.environment["BS_FRONTALL"] == "1"     // (P446 before: every change, no cap)
    let maxJobs: Int
    private var lastCenter: ChunkKey?
    // P440 (Oct 24 evening, "performance, performance, performance"; "why is it rendering the caves underneath? As I'm
    // flying, I can see caves underground"): a Polygons world's sections wholly under the lowest ground surface of their
    // chunk and the eight round it (caves, solid rock) are not meshed past `buriedNear` chunks of the player while he is
    // above ground; they mesh when he comes near or goes underground (then out to `buriedNearUnder`). On his world's
    // seed about 70 % of the sections meshed and drawn were buried (questcheck --perfscenes taiga24/forest24/snowy24,
    // "under the lowest surface"), and meshing is most of the land's cost (297 chunks: gen 21 s, mesh 91 s on the
    // harness). BS_BURIED=0: off.
    static var deferBuried = ProcessInfo.processInfo.environment["BS_BURIED"] != "0"
    static var buriedNear = 3, buriedNearUnder = 8
    // P484: ground over his head 3 blocks off on two sides counts as under the ground (a shaft). BS_SHAFTUNDER=0: off.
    static var shaftUnder = ProcessInfo.processInfo.environment["BS_SHAFTUNDER"] != "0"
    // P446 (Oct 25, "in creative, I can't really travel anywhere"): flying well over the ground (more than 24 blocks over
    // it, back under 12), the rock under him is meshed only in his own chunk and the eight round it: the 49 chunks of the
    // usual ring each meshed their caves and rock as he flew over them, about a third of the meshing at view 10. They
    // mesh when he comes down. BS_HIGHRING=0: off.
    static var buriedNearHigh = ProcessInfo.processInfo.environment["BS_HIGHRING"] == "0" ? 3 : 1
    private(set) var flyingHigh = false
    // P487: flying high and fast (over settleFast), the chunks under him pass in a fraction of a second: none of their
    // buried rock is meshed (the nine round him each meshed their caves as they came under him, about a third of all
    // meshing at the dropship's 60 b/s at view 16); it meshes when he slows or comes down. BS_HIGHFAST=0: off.
    static var highFastNone = ProcessInfo.processInfo.environment["BS_HIGHFAST"] != "0"
    private(set) var flyingFast = false
    private(set) var underground = false
    private var eyeSection = 0                      // the section his eye is in (World.update), P404 (3)
    private var buriedCentre: ChunkKey?
    private var buriedExtra: ChunkKey?
    // P504 (Remington, Nov 1 08:07, flying over the Hell: "the Nether takes a long time to load"): the Deep stacks two
    // worlds, the Ash Vault (y 0-191) and the hell band (200-375), with the Sealrock between them that only Sunderite
    // breaks. Every chunk meshed both, so in the Hell the whole Ash Vault under the Sealrock (its woods, towns and
    // shell holes) was meshed and never seen: four times the surface's meshing for the same ground (questcheck --view
    // at his 08:07 spot, 193 chunks: 6.9 s against 1.6 s). Past the chunk he is in and the eight round it, the layer
    // he isn't in is left unmeshed; crossing over hands it back. BS_DEEPLAYER=0: off.
    static var deepLayerCut = ProcessInfo.processInfo.environment["BS_DEEPLAYER"] != "0"
    private var deepInHell: Bool?
    private var deepCentre: ChunkKey?
    private(set) var deferredTotal = 0          // (harness: sections deferred so far)
    // Split-screen co-op (Coop.swift): the second player's position, streamed around like the first (nil when alone).
    var extraCenter: V3?
    private var lastExtra: ChunkKey?
    private var scanExtra: ChunkKey?
    private var offsets: [(Int, Int, Int)] = []

    private(set) var meshedCount = 0
    var pendingJobs: Int { jobs }

    // Perf counters (--bench, F3). Worker totals are updated under `lock`; updateSeconds is the last
    // update() call on the main thread.
    struct PerfStats {
        var genChunks = 0, genSeconds = 0.0
        var meshJobs = 0, meshSections = 0, meshSeconds = 0.0
        var updateSeconds = 0.0
    }
    private var perfShared = PerfStats()
    private var lastUpdateSeconds = 0.0
    var perf: PerfStats {
        lock.lock(); var p = perfShared; lock.unlock()
        p.updateSeconds = lastUpdateSeconds
        return p
    }

    // Live World objects (leak check in --bench). A worker's job can hold the last reference, so a World can die on
    // a worker thread: hence the lock (as Chunk.alive).
    static let aliveLock = NSLock()
    private(set) static var alive = 0
    static let registry = NSHashTable<World>.weakObjects()
    deinit { World.aliveLock.lock(); World.alive -= 1; World.aliveLock.unlock() }
    var debugState: String {
        lock.lock(); let gr = genResults.count, mr = meshResults.count; lock.unlock()     // workers append under the lock
        return "jobs \(jobs), queue ops \(workQueue.pending), gen in flight \(genInFlight.count), results \(gr)/\(mr), chunks \(chunks.count)"
    }

    init(seed: UInt64, device: MTLDevice, save: SaveManager?, dim: Dim = .overworld) {
        World.aliveLock.lock(); World.alive += 1; World.aliveLock.unlock()
        self.seed = seed
        self.dim = dim
        switch dim {
        case .overworld: gen = WorldGen(seed: seed)
        case .nether: gen = EmberGen(seed: seed)
        case .end: gen = HollowGen(seed: seed)
        case .deep: gen = DeepGen(seed: seed)
        }
        self.device = device
        self.save = save
        if dim == .overworld {
            if let save { fieldTerrain = save.hasMarker("terrain-field.txt") }        // (made one: makeFieldWorld)
            else { fieldTerrain = FieldTerrain.unsaved }
        } else if save == nil { fieldTerrain = FieldTerrain.unsaved }
        save?.fieldWorld = fieldTerrain
        (gen as? HollowGen)?.fieldTops = fieldTerrain
        (gen as? WorldGen)?.fieldWorld = fieldTerrain && (save?.hasMarker("railway-grade.txt") ?? true)     // (gradeRails, in init)
        if let wg = gen as? WorldGen {
            wg.terrain.fewerLakes = save?.newTerrain("terrain-p44-water.txt") ?? World.fewerLakesUnsaved
            wg.terrain.lessWater = save?.newTerrain("terrain-h8-water.txt") ?? World.lessWaterUnsaved   // H8
            wg.railSites = save?.newTerrain("railway-sites.txt") ?? true     // P379 step 1 (a saved world's lines stay as laid)
        }
        maxJobs = workQueue.workers
        rebuildOffsets()
        blockEntities = save?.loadBlockEntities() ?? [:]
        portals = Set(save?.loadPortals() ?? [])
        if dim == .overworld, let save, let sc = (gen as? WorldGen)?.structures {
            sc.legacy = save.structureGuard()
            sc.legacyStations = save.structureGuard(file: "structure-guard-stations.txt")
            sc.explored = save.structureGuard(file: "structure-guard-oct10.txt")      // WorldRules.swift
            sc.legacyCapitalTowns = save.structureGuard(file: "structure-guard-capital-towns.txt")
            sc.legacyFrontier = save.structureGuard(file: "structure-guard-frontier.txt")
            sc.legacyTownsGap = save.structureGuard(file: "structure-guard-towns-gap.txt")
            sc.legacyL3 = save.structureGuard(file: "structure-guard-l3.txt")              // WorldRules.savedBeforeL3
            sc.legacyG12 = save.structureGuard(file: "structure-guard-g12.txt")            // WorldRules.savedBeforeG12
            sc.legacyP44 = save.structureGuard(file: "structure-guard-p44.txt")            // WorldRules.savedBeforeP44
            sc.legacyP95 = save.structureGuard(file: "structure-guard-p95.txt")            // WorldRules.savedBeforeP95
            sc.legacyGreywall = save.structureGuard(file: "structure-guard-greywall.txt")  // Greywall.swift
            sc.legacySkyIsle = save.structureGuard(file: "structure-guard-skyisle.txt")    // SkyIsle.swift
            sc.legacyPorts = save.structureGuard(file: "structure-guard-ports.txt")        // NavalPort.swift
            sc.legacySites = save.structureGuard(file: "structure-guard-sites.txt")        // FrontierSites.swift
            sc.legacyOverlap = save.structureGuard(file: "structure-guard-overlap.txt")    // StructureCache.yields
            sc.legacyC1 = save.structureGuard(file: "structure-guard-c1.txt")              // Railways.swift
            sc.legacyC12 = save.structureGuard(file: "structure-guard-c12.txt")            // MiningTowns.swift
            sc.legacyC13 = save.structureGuard(file: "structure-guard-c13.txt")            // TownSizes.swift
            sc.legacyR22 = save.structureGuard(file: "structure-guard-r22.txt")            // StructureCache.keepR22
        }
        // G20 on the surface (strongholds, monuments, mansions, trial chambers): its own snapshot, taken the first time a save
        // loads under G20 (the P44 one was taken earlier, so ground generated between the two would get half a new design).
        if dim == .overworld { G20Guard.overworld = save?.structureGuard(file: "structure-guard-g20-overworld.txt") ?? [] }
        // G20: the Emberdeep's and the Deep's fortresses are Ash Foundries on ground no save generated before them.
        if dim == .nether { G20Guard.nether = save?.structureGuard(file: "structure-guard-g20.txt") ?? [] }
        if dim == .deep { G20Guard.deep = save?.structureGuard(file: "structure-guard-g20.txt") ?? [] }
        // P292: Brand Chapterhouses and Searwing Roosts on ground no save generated before them (BrandChapterhouse.swift).
        if dim == .nether { P292Guard.nether = save?.structureGuard(file: "structure-guard-p292.txt") ?? [] }
        if dim == .deep { P292Guard.deep = save?.structureGuard(file: "structure-guard-p292.txt") ?? [] }
        if dim == .deep, let save, let dg = gen as? DeepGen {
            dg.keepGuard.chunks = save.structureGuard(file: "structure-guard-deep-keeps.txt")      // BrimstoneKeep.swift
            dg.vaultGuard.chunks = save.structureGuard(file: "structure-guard-vault.txt")          // AshVault.swift
            dg.ground.guardSet.chunks = save.structureGuard(file: "structure-guard-p326.txt")      // AshFront.swift
        }
        if dim == .deep { AshWar.setFront((gen as? DeepGen)?.ground.guardSet ?? DeepGuard()) }   // (P326's sites: off old ground)
        World.registry.add(self)
    }

    // Chunks to load: the meshed disc grown by one chunk (every meshed chunk needs its 8 neighbours).
    // A disc instead of the old square skips ~20% of the chunks (the corners were never drawn).
    private var scanCenter: ChunkKey?
    private var scanEpoch = -1

    private func rebuildOffsets() {
        scanEpoch = -1
        let r = renderDistance + 1
        var o: [(Int, Int, Int)] = []
        for dz in -r...r { for dx in -r...r where World.inDisc(dx, dz, renderDistance, grow: 1) { o.append((dx, dz, dx * dx + dz * dz)) } }
        o.sort { $0.2 < $1.2 }
        offsets = o
        scanHeading = -1
    }

    // P446 (Oct 25, "this is just not rendering fast enough at all"): the land he faces comes first. The scan walks the
    // chunks in this order: nearest first, those outside the 120 degree cone round his heading as if half as far again
    // (the headset shows about 100 degrees across), rebuilt when his heading turns into another eighth. It walked every
    // side alike, so what was in front of him waited on the land behind him. BS_FACINGFIRST=0: off.
    static var facingFirst = ProcessInfo.processInfo.environment["BS_FACINGFIRST"] != "0"
    var facing: Float? = nil                       // (Game.tickSeat: the player's heading, his head's on the headset)
    private var scanOrder: [(Int, Int, Int)] = []
    private var scanHeading = -1
    // P478 (Oct 27 19:18, flying: "instead of generating the stuff behind me as I'm flying, maybe the stuff in front of
    // me should get prioritized"): moving faster than a run (8 b/s), the way he travels leads, not the way he looks
    // (he looks round while he flies), and above 30 b/s the land behind him waits as if twice as far (it was half as far
    // again).
    private func orderedScan() -> [(Int, Int, Int)] {
        guard World.facingFirst, var yaw = facing else { return offsets }
        let speed = simd_length(V2(lead.x, lead.z))
        if speed > 8 { yaw = atan2f(-lead.x, -lead.z) }
        let fast = speed > 30
        let eighth = Float.pi / 4
        let h = (Int(((yaw.truncatingRemainder(dividingBy: 2 * .pi) + 2 * .pi) / eighth).rounded()) & 7) + (fast ? 8 : 0)
        if h == scanHeading { return scanOrder }
        scanHeading = h
        let a = Float(h & 7) * eighth
        let fx = -sinf(a), fz = -cosf(a)
        let behind = fast ? 16 : 9
        var keyed: [(Int, Int, Int, Int)] = offsets.map { (dx, dz, d2) in
            let len = sqrtf(Float(d2))
            let ahead = d2 <= 2 || (Float(dx) * fx + Float(dz) * fz) >= 0.5 * len
            return (dx, dz, d2, ahead ? d2 * 4 : d2 * behind)
        }
        keyed.sort { $0.3 != $1.3 ? $0.3 < $1.3 : $0.2 < $1.2 }
        scanOrder = keyed.map { ($0.0, $0.1, $0.2) }
        return scanOrder
    }

    // Whether (dx, dz) lies within `grow` chunks (Chebyshev) of the mesh disc of radius r.
    @inline(__always) static func inDisc(_ dx: Int, _ dz: Int, _ r: Int, grow: Int) -> Bool {
        let ax = max(0, abs(dx) - grow), az = max(0, abs(dz) - grow)
        return ax * ax + az * az <= r * r + r
    }

    // Chunks farther than 8 chunks are meshed at LOD 1.
    static var lodNear = 8                      // harness --nolod raises it (far detail off)
    // Deep in a dark cave (smoothed eye skylight `caveK` under 0.12) the fog closes before the far-detail ring: far
    // sections drop unlit cave walls (Mesher.farDarkCull), so from a cave the surface's trees showed through them
    // (Oct 11 Quest playtest P4). Nil: no limit.
    static func caveSight(caveK: Float) -> Float? {
        caveK >= 0 && caveK < 0.12 && lodNear < 40 ? Float(lodNear * 16 - 6) : nil
    }
    // Chunks farther than leafNear (and within lodNear) are meshed at full detail but with "fast" leaves (Mesher lod 2:
    // no faces between leaf blocks). Quest sets 2: the Oct 10 taiga village drew ~500k quads at rd 16, about half of
    // them leaves, and inner canopy faces 3-5 chunks away are hard to tell apart through the leaf holes.
    static var leafNear = 99
    @inline(__always) static func level(_ d: Int, slack: Int) -> Int {
        d > lodNear + slack ? 1 : (d > leafNear + slack ? 2 : 0)
    }
    @inline(__always) static func rank(_ lod: Int) -> Int { lod == 0 ? 0 : (lod == 2 ? 1 : 2) }      // near to far
    @inline(__always) func lodFor(_ dx: Int, _ dz: Int) -> Int { World.level(max(abs(dx), abs(dz)), slack: 0) }
    // With one chunk of hysteresis outwards: walking back and forth across a boundary doesn't re-mesh the ring each time.
    @inline(__always) func lodFor(_ dx: Int, _ dz: Int, current: Int) -> Int {
        let d = max(abs(dx), abs(dz))
        let exact = World.level(d, slack: 0)
        guard World.rank(exact) > World.rank(current) else { return exact }
        let out = World.level(d, slack: 1)
        return World.rank(out) > World.rank(current) ? out : current
    }

    // A chunk crossing a detail boundary: its meshed sections are redone at the new level. Between full detail (0) and
    // mid (2) only sections with faces between leaves mesh differently, so only those are redone.
    private func setLod(_ c: Chunk, _ want: Int) {
        let leavesOnly = c.lod != 1 && want != 1
        let farChange = (c.lod == 1) != (want == 1)
        c.lod = want
        c.lodRemeshLog = true
        World.backgroundEdits = true                      // (P446: a detail change meshes in the queue's order)
        defer { World.backgroundEdits = false }
        for s in c.sections where s.meshedVersion != -1 && (!leavesOnly || s.leafy) { s.version += 1 }
        // P283: a far neighbour's ground now meets this chunk the other way (Mesher.coarseGround's seams).
        if farChange && fieldTerrain && Mesher.farGround {
            for (dx, dz) in World.sides {
                guard let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)], n.lod == 1 else { continue }
                var bumped = false
                for s in n.sections where s.meshedVersion != -1 && s.groundQuads > 0 { s.version += 1; bumped = true }
                if bumped { dirtyChunks.append(n) }
            }
        }
    }
    static let sides = [(-1, 0), (1, 0), (0, -1), (0, 1)]          // (bit order of nearSides)

    // P283: which side neighbours of a far chunk (lod 1) of a field world are meshed nearer, as Mesher.coarseGround's
    // nearSides bits (0 -x, 1 +x, 2 -z, 3 +z).
    func nearSides(_ c: Chunk, lod: Int) -> Int {
        guard lod == 1, fieldTerrain, Mesher.farGround else { return 0 }
        var m = 0
        for (i, (dx, dz)) in World.sides.enumerated() {
            if let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)], n.lod != 1 { m |= 1 << i }
        }
        return m
    }

    // P404: for a chunk whose 3x3 has fine samples (its sections may draw half-block ground, Mesher.fineGround), per side
    // (World.sides order) the sections (bit = section) with fine samples in the three chunks two steps out on that side:
    // with the 3x3 that says which side neighbours draw from their cells. Empty when no section of the chunk can be fine.
    func fineBeyond(_ c: Chunk, _ n9: [BlockStore]) -> [UInt32] {
        guard fieldTerrain, FineField.enabled, n9.contains(where: { !$0.fine.isEmpty }) else { return [] }
        return World.sides.map { (dx, dz) in
            var bits: UInt32 = 0
            for k in -1...1 {
                guard let n = chunks[ChunkKey(x: c.cx + 2 * dx + (dz != 0 ? k : 0), z: c.cz + 2 * dz + (dx != 0 ? k : 0))] else { continue }
                for s in n.blocks.fine.keys where s >= 0 && s < 32 { bits |= 1 << UInt32(s) }
            }
            return bits
        }
    }

    @inline(__always) func inMeshRadius(_ dx: Int, _ dz: Int) -> Bool {
        dx * dx + dz * dz <= renderDistance * renderDistance + renderDistance
    }

    // P250 (c): how far round chunk `center` every chunk is meshed, as the squared chunk distance of the nearest chunk
    // in the mesh disc that is missing or not meshed yet (rd^2 + rd + 1 when the whole disc is in). The far ring
    // (FarRing, far.vert) sinks only inside this disc, so while chunks stream in it stays at its true height where
    // they are missing instead of showing a sunk pit. Walks the nearest-first offsets up to the first gap.
    func meshedReach(_ center: ChunkKey) -> Int {
        let full = renderDistance * renderDistance + renderDistance
        for (dx, dz, d2) in offsets {
            if d2 > full { break }
            guard let c = chunks[ChunkKey(x: center.x + dx, z: center.z + dz)], c.meshedOnce else { return d2 }
        }
        return full + 1
    }

    // MARK: Block access

    @inline(__always) func chunkAt(_ x: Int, _ z: Int) -> Chunk? {
        chunks[ChunkKey(x: floorDiv(x, CS), z: floorDiv(z, CS))]
    }

    func block(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        if let s = frame { return s.frameBlock(x, y, z, self) }
        return rawBlock(x, y, z)
    }

    // The world's own block, ignoring any ship frame.
    @inline(__always) func rawBlock(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        if y < 0 { return BEDROCK }
        if y >= CH { return AIR }
        guard let c = chunkAt(x, z) else { return AIR }
        if c.hollow { return y <= Int(c.height[mod(x, CS) + mod(z, CS) * CS]) ? STONE : AIR }   // P376: a shell's long sight lines
        return c.blocks[Chunk.index(mod(x, CS), y, mod(z, CS))]
    }

    func isLoaded(_ x: Int, _ z: Int) -> Bool { frame != nil || chunkAt(x, z) != nil }

    // P377 step 2: the block grid's view of a field world's ground (block()) is for nothing that asks where the ground
    // is; these read the two layers apart. The built layer alone (no ground; the same as block() in block worlds and
    // through a ship frame): searches for built things, emitters, what stands in a cell.
    @inline(__always) func builtBlock(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        if frame != nil || !fieldTerrain { return block(x, y, z) }
        if y < 0 || y >= CH { return y < 0 ? BEDROCK : AIR }
        guard let c = chunkAt(x, z), !c.hollow else { return AIR }
        return c.blocks.raw(Chunk.index(mod(x, CS), y, mod(z, CS)))
    }
    // The cell is inside the field's ground (its density > 0); never in block worlds.
    @inline(__always) func groundAt(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard fieldTerrain, frame == nil, y >= 0 && y < CH, let c = chunkAt(x, z) else { return false }
        if c.hollow { return y <= Int(c.height[mod(x, CS) + mod(z, CS) * CS]) }
        return c.blocks.ground(Chunk.index(mod(x, CS), y, mod(z, CS)))
    }
    // The cell holds something solid: a built block that collides, or the field's ground at the cell's sample (its
    // centre). For the searches that step by cells (where a mob may appear, which column a thing lands in); the body is
    // then set on the drawn surface.
    @inline(__always) func solidAt(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        Blocks.collide[Int(builtBlock(x, y, z))] || groundAt(x, y, z)
    }
    // Nothing in the cell: no built block and no ground (block(x, y, z) == AIR, read from the two layers).
    @inline(__always) func isAir(_ x: Int, _ y: Int, _ z: Int) -> Bool { builtBlock(x, y, z) == AIR && !groundAt(x, y, z) }
    @inline(__always) func opaqueAt(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        Blocks.opaque[Int(builtBlock(x, y, z))] || groundAt(x, y, z)
    }
    // What the cell is made of, for the material rules (grass creeping onto dirt, snow melting, what grows where): the
    // built block, else the ground's material where the cell is inside the ground (read from the field's material, not
    // the block grid). Never for where the ground's surface is or what is solid: that is the field (fieldDensity,
    // fieldBoxes).
    @inline(__always) func materialAt(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        if frame != nil || !fieldTerrain { return block(x, y, z) }
        if y < 0 || y >= CH { return y < 0 ? BEDROCK : AIR }
        guard let c = chunkAt(x, z) else { return AIR }
        if c.hollow { return y <= Int(c.height[mod(x, CS) + mod(z, CS) * CS]) ? STONE : AIR }
        return c.blocks.materialCell(Chunk.index(mod(x, CS), y, mod(z, CS)))
    }

    // Every block in the box c +- (r, ry, r) as body(id, x, y, z), chunk by chunk: one dictionary lookup per chunk
    // instead of per cell (a villager's 65x17x65 bell search through block() cost 7-14 ms: Quest bench, village).
    // Unloaded chunks and cells outside 0..<CH are skipped; through a ship frame every cell goes through block(). Built blocks
    // only (P377 step 2): a field world's ground reads as air (every caller looks for beds, bells, workstations, lamps).
    func forEachBlock(around c: IVec3, r: Int, ry: Int, _ body: (BlockID, Int, Int, Int) -> Void) {
        let y0 = max(0, c.y - ry), y1 = min(CH - 1, c.y + ry)
        guard y0 <= y1 else { return }
        if frame != nil {
            for y in y0...y1 { for z in (c.z - r)...(c.z + r) { for x in (c.x - r)...(c.x + r) { body(block(x, y, z), x, y, z) } } }
            return
        }
        for cz in floorDiv(c.z - r, CS)...floorDiv(c.z + r, CS) {
            for cx in floorDiv(c.x - r, CS)...floorDiv(c.x + r, CS) {
                guard let ch = chunks[ChunkKey(x: cx, z: cz)] else { continue }
                let bx = cx * CS, bz = cz * CS
                let xa = max(c.x - r, bx), xb = min(c.x + r, bx + CS - 1)
                let za = max(c.z - r, bz), zb = min(c.z + r, bz + CS - 1)
                let blocks = ch.blocks
                for y in y0...y1 { for z in za...zb { for x in xa...xb {
                    body(blocks.raw(Chunk.index(x - bx, y, z - bz)), x, y, z)
                } } }
            }
        }
    }

    // Light at a block: (sky 0-15, block 0-15). Uses the mesher's stored light when available,
    // otherwise approximates from the heightmap.
    func lightAt(_ x: Int, _ y: Int, _ z: Int) -> (sky: Int, block: Int) {
        if y >= CH { return (15, 0) }
        if y < 0 { return (0, 0) }
        guard let c = chunkAt(x, z) else { return (15, 0) }
        let lx = mod(x, CS), lz = mod(z, CS)
        if let sl = c.light[y >> 4] {
            let l = sl[lx + lz * CS + (y & 15) * CSQ]
            return (Int(l >> 4), Int(l & 15))
        }
        return (y > Int(c.height[lx + lz * CS]) ? 15 : 0, 0)
    }

    func topY(_ x: Int, _ z: Int) -> Int {
        guard let c = chunkAt(x, z) else { return -1 }
        return Int(c.height[mod(x, CS) + mod(z, CS) * CS])
    }

    // While set (Game.advance: mobs, random ticks, snow, falling blocks, fire, circuits...), setBlock leaves even the
    // sections around the block to the mesh workers, which redraw them a frame or two later. Those edits were each
    // up to eight sections meshed on the frame thread: the Oct 9 Quest playtest logged a ~60 ms tick in every 5 s
    // window (11.9 hitches a minute at every render distance). The player's own edits stay synchronous.
    var deferRemesh = false

    // Changes a block and remeshes: the sections around the block synchronously (no holes, correct
    // AO), everything its light could reach in the background.
    static var syncEdits = 0, asyncEdits = 0        // P283: block changes since start (questcheck --perfscenes)
    static var editTally: [UInt64: Int]? = nil      // P283: (async << 32 | old << 16 | new) -> count, when the harness asks
    static var editCells: [IVec3: Int] = [:]        // (and how often each cell changed in the background)
    // A fluid written over ground, or drained off it, under BlockStore.keepGround (World.setFluid, Game.pourFluid)
    // leaves the ground as it is: no fine samples are made for it. (They were: every section a flow ran onto shallow
    // ground got half-block samples, so it and the 3x3 chunks round it drew and meshed half-block ground, and the lava
    // tick that made them stalled 15 ms on the host each time new land's deep lava began to run.)
    @inline(__always) static func keepsGround(_ wasGround: Bool, _ id: BlockID) -> Bool {
        wasGround && BlockStore.keepGround && (id == AIR || Blocks.fluidKind[Int(id)] != 0)
    }

    func setBlock(_ x: Int, _ y: Int, _ z: Int, _ id0: BlockID) {
        guard y >= 0 && y < CH, let c0 = chunkAt(x, z) else { return }
        // P389: a struck object's cell changed by anything but the object itself (a blast, a bucket): the object is
        // forgotten and what is left of its cells draws as blocks again.
        if !objectReg.owner.isEmpty && !objectReg.editing, let o = objectReg.object(at: IVec3(x, y, z)) { objectReg.forget(self, o) }
        let c = editing(c0)
        World.syncEdits &+= 1
        if !damage.isEmpty { damage.removeValue(forKey: IVec3(x, y, z)) }
        if !bites.isEmpty { bites.removeValue(forKey: IVec3(x, y, z)) }
        let lx = mod(x, CS), lz = mod(z, CS)
        let oldH = Int(c.height[lx + lz * CS])
        let old = c.blocks.materialCell(Chunk.index(lx, y, lz))
        let id = World.storedState(id0, replacing: old)
        if World.editTally != nil { World.editTally![UInt64(old) << 16 | UInt64(id), default: 0] += 1 }
        let wasGround = fieldTerrain && c.blocks.ground(Chunk.index(lx, y, lz))
        if wasGround != (fieldTerrain && FieldMat.index[Int(id)] != 0) && !World.keepsGround(wasGround, id) { ensureFine(c, y >> 4) }     // P377 step 1 (before the write)
        c.blocks[Chunk.index(lx, y, lz)] = id
        var fbox: (lo: IVec3, hi: IVec3)? = nil
        if old != id { fbox = measureChanges { fieldBlockChanged(x, y, z, old, id, wasGround: wasGround) } }      // PG1 (TerrainField.swift)
        if !redstone.isBusy && !circuitQuiet && old != id { redstone.blockChanged(IVec3(x, y, z), old, id) }
        if old != id { queueSupportChecks(x, y, z, old, id); queueLoadCheck(x, y, z, old, id) }
        c.modified = true
        c.recomputeHeight(lx, lz)
        if wasGround && !c.blocks.ground(Chunk.index(lx, y, lz)) { groundOpened(c, y) }
        let newH = Int(c.height[lx + lz * CS])
        var sync: [(Chunk, Int)] = []
        // Smooth vertices move with blocks up to 2 away (relaxing carries it 1 more a pass: those sections remesh in the
        // background with the rest below, so a Quest edit doesn't mesh the whole ring on the frame).
        // P440 (Oct 24 20:55, "a five hundred millisecond freeze every time I place a block"): in a field world the frame
        // meshes the sections within a cell of the block or of a field sample it changed (usually its own section; a
        // neighbour only on their border); the rest follows on a worker ahead of the queue.
        let r = SmoothTerrain.enabled || fieldTerrain ? 2 : 1
        let cell = (lo: IVec3(x, y, z), hi: IVec3(x, y, z))
        for dz in -r...r {
            for dx in -r...r {
                for dy in -r...r {
                    let yy = y + dy
                    guard yy >= 0 && yy < CH, let n = chunkAt(x + dx, z + dz) else { continue }
                    let sy = yy >> 4
                    if !sync.contains(where: { $0.0 === n && $0.1 == sy }) { sync.append((n, sy)) }
                }
            }
        }
        editBatch {
            for (n, sy) in sync {
                n.sections[sy].version += 1
                guard !deferRemesh else { continue }
                if fieldTerrain && !World.near(n, sy, cell, grow: 1) && !(fbox.map { World.near(n, sy, $0, grow: 1) } ?? false) { continue }
                remeshSync(n, sy)
            }
        }
        let (lo, hi) = World.lightReach(y, oldH, newH)
        let cx = floorDiv(x, CS), cz = floorDiv(z, CS)
        for dz in -1...1 {
            for dx in -1...1 {
                guard let n = chunks[ChunkKey(x: cx + dx, z: cz + dz)] else { continue }
                for sy in lo...hi where !sync.contains(where: { $0.0 === n && $0.1 == sy }) {
                    n.sections[sy].version += 1
                }
            }
        }
        scheduleFluid(around: IVec3(x, y, z))
    }

    // The sections whose light a change at y can reach: those within 16 blocks of it (a section's mesh lights a 48-block
    // region round it), and, when the column's top moved, every one between the old and the new top (P172).
    // P446: with the top where it was, it still bumped every section from the cell up to the top: water settling in a
    // cave redrew the nine columns over it up to the surface, a few times a second.
    @inline(__always) static func lightReach(_ y: Int, _ oldH: Int, _ newH: Int) -> (Int, Int) {
        let a = oldH == newH && World.narrowLight ? y : min(y, oldH, newH), b = oldH == newH && World.narrowLight ? y : max(y, oldH, newH)
        return (max(0, (a - 16) >> 4), min(NSEC - 1, (b + 16) >> 4))
    }
    static var narrowLight = ProcessInfo.processInfo.environment["BS_NARROWLIGHT"] != "0"

    // Waterlogging rules for every write: a full cube (double slab) holds no water, and a waterlogged block that is
    // removed (broken, blown up, pushed away) leaves its water behind (reference).
    @inline(__always) static func storedState(_ id: BlockID, replacing old: BlockID) -> BlockID {
        if Blocks.wetInvalid[Int(id)] { return Blocks.dry[Int(id)] }
        if id == AIR && old != AIR && Blocks.isWaterlogged(old) { return WATER }
        return id
    }

    // Cells whose support may have changed: this one and the one above (falling blocks, standing plants), the one below
    // (hanging plants), and the four beside it when a solid block went (vines clinging to it). Game.gravityTick.
    @inline(__always) func queueSupportChecks(_ x: Int, _ y: Int, _ z: Int, _ old: BlockID, _ new: BlockID) {
        gravityQueue.append(IVec3(x, y, z)); gravityQueue.append(IVec3(x, y + 1, z)); gravityQueue.append(IVec3(x, y - 1, z))
        if Blocks.collide[Int(old)] && !Blocks.collide[Int(new)] {
            gravityQueue.append(IVec3(x + 1, y, z)); gravityQueue.append(IVec3(x - 1, y, z))
            gravityQueue.append(IVec3(x, y, z + 1)); gravityQueue.append(IVec3(x, y, z - 1))
        }
    }

    // Set by a bulk edit (a Tidebreaker crater) that checked no circuit part is within reach of its cells: each removed
    // conductor otherwise marks ~40 neighbours for the circuit pass (7 ms per 250 blocks on the host).
    var circuitQuiet = false

    // Bulk edits (fluids): no synchronous remesh; the surrounding sections re-mesh in the background.
    @discardableResult
    func setBlockAsync(_ x: Int, _ y: Int, _ z: Int, _ id0: BlockID) -> Bool {
        guard y >= 0 && y < CH, let c0 = chunkAt(x, z) else { return false }
        if !objectReg.owner.isEmpty && !objectReg.editing, let o = objectReg.object(at: IVec3(x, y, z)) { objectReg.forget(self, o) }   // (P389)
        let c = editing(c0)
        World.asyncEdits &+= 1
        if !damage.isEmpty { damage.removeValue(forKey: IVec3(x, y, z)) }
        if !bites.isEmpty { bites.removeValue(forKey: IVec3(x, y, z)) }
        let lx = mod(x, CS), lz = mod(z, CS)
        let old = c.blocks.materialCell(Chunk.index(lx, y, lz))
        let id = World.storedState(id0, replacing: old)
        if World.editTally != nil {
            World.editTally![1 << 32 | UInt64(old) << 16 | UInt64(id), default: 0] += 1
            World.editCells[IVec3(x, y, z), default: 0] += 1
        }
        let wasGround = fieldTerrain && c.blocks.ground(Chunk.index(lx, y, lz))
        if wasGround != (fieldTerrain && FieldMat.index[Int(id)] != 0) && !World.keepsGround(wasGround, id) { ensureFine(c, y >> 4) }     // P377 step 1 (before the write)
        c.blocks[Chunk.index(lx, y, lz)] = id
        if old != id { fieldBlockChanged(x, y, z, old, id, wasGround: wasGround) }      // PG1 (TerrainField.swift)
        if !redstone.isBusy && !circuitQuiet && old != id { redstone.blockChanged(IVec3(x, y, z), old, id) }
        if old != id { queueSupportChecks(x, y, z, old, id); queueLoadCheck(x, y, z, old, id) }
        c.modified = true
        let oldH = Int(c.height[lx + lz * CS])
        c.recomputeHeight(lx, lz)
        if wasGround && !c.blocks.ground(Chunk.index(lx, y, lz)) { groundOpened(c, y) }      // (a crater's cells: below)
        let newH = Int(c.height[lx + lz * CS])
        // P283: a change that leaves the light as it was (the same light-blocking and glow, the column's top where it
        // was) only redraws the sections within two blocks of it. Grass creeping onto dirt and dying back under cover,
        // about 26 changes a second round his homestead with nobody touching anything, each remeshed the 27 sections
        // round it, which kept two mesh workers busy all the time.
        // (Not when the cell joined or left the ground of a Polygons world: that reshaped the field round it.)
        if oldH == newH && TickProf.lighter && Blocks.lightOpaque[Int(old)] == Blocks.lightOpaque[Int(id)]
            && Blocks.emit[Int(old)] == Blocks.emit[Int(id)] && Blocks.sky[Int(old)] == Blocks.sky[Int(id)]
            && (!fieldTerrain || wasGround == c.blocks.ground(Chunk.index(lx, y, lz))) {
            // P363 (b): a fluid change reaches 3 (a field world's water surface reads its fluid 2 past a sample that is
            // itself 1 past the section), so a drained flow isn't left drawn in the next section.
            let r = Blocks.fluidKind[Int(old)] != 0 || Blocks.fluidKind[Int(id)] != 0 ? 3 : 2
            let s0 = max(0, (y - r) >> 4), s1 = min(NSEC - 1, (y + r) >> 4)
            for cz in floorDiv(z - r, CS)...floorDiv(z + r, CS) {
                for cx in floorDiv(x - r, CS)...floorDiv(x + r, CS) {
                    guard let n = chunkAt(cx * CS, cz * CS) else { continue }
                    for sy in s0...s1 { n.sections[sy].version += 1 }
                }
            }
            return true
        }
        // P172 (Oct 13: "dark patches where he digs"): the sky light below a column whose top moved changes all the way
        // between the old and the new top, as setBlock already remeshed; this only covered 16 blocks round the edit, so
        // a flow or fall that opened or closed a column left the sections further down lit as before (dark or bright
        // patches until something else touched them).
        let (lo, hi) = World.lightReach(y, oldH, newH)
        for dz in -1...1 {
            for dx in -1...1 {
                guard let n = chunkAt(x + dx * 16, z + dz * 16) else { continue }
                for sy in lo...hi { n.sections[sy].version += 1 }
            }
        }
        return true
    }

    // MARK: Collision (shared by the player, mobs and items)

    // World-space collision boxes of the block at a cell.
    @inline(__always) func collisionBoxes(_ x: Int, _ y: Int, _ z: Int, _ out: inout [(V3, V3)]) {
        var b: Int
        // PG2 rewrite: in a field world the ground is met as the field's own surface (fieldBoxes: quarter-block columns
        // cut where the density crosses zero), never as cells; built blocks in the cell keep their own shapes.
        // (P377 step 2: the cell is read through the built layer only, never first as a block.)
        if fieldTerrain && y >= 0 && y < CH, let c = chunkAt(x, z) {
            let i = Chunk.index(mod(x, CS), y, mod(z, CS))
            if fieldNear(c, x, y, z, i) { if fieldSplit { fieldBoxes(x, y, z, &fieldSink) } else { fieldBoxes(x, y, z, &out) } }
            b = Int(c.blocks.raw(i))
        } else { b = Int(block(x, y, z)) }
        if !pieceCells.isEmpty, let pb = pieceCells[IVec3(x, y, z)] { out.append(contentsOf: pb) }
        // P389: a struck object's cell is met as what is left of it there.
        if !objectReg.cellBoxes.isEmpty, let ob = objectReg.cellBoxes[IVec3(x, y, z)] { out.append(contentsOf: ob); return }
        if !Blocks.collide[b] { return }
        if foliageSoft && softFoliage(b, x, y, z) { return }
        let o = V3(Float(x), Float(y), Float(z))
        if fieldTerrain, let r = fallenLog(b, x, y, z) { out.append((r.0 + o, r.1 + o)); return }
        if Blocks.fullCollide[b] {
            // A chipped block gives up the whole layers it has lost (you sink into a block chipped from the top).
            if !damage.isEmpty && !World.realistic, let dv = damage[IVec3(x, y, z)] {
                let (mn, mx) = Mesher.chipBox(face: Int(dv >> 5), level: Int(dv & 31), x: x, y: y, z: z)
                out.append((o + mn, o + mx)); return
            }
            // PG2: natural ground is met at its drawn surface, not its block faces: walked on at the drawn top under open
            // air, and a roof over open air gives the headroom its drawn underside leaves.
            if SmoothTerrain.natural[b] && SmoothTerrain.enabled && SmoothTerrain.fromField && !fieldTerrain && y > 0 && y + 1 < CH,
               let g = gen as? WorldGen {
                let up = !Blocks.collide[Int(block(x, y + 1, z))], down = !Blocks.collide[Int(block(x, y - 1, z))]
                if up || down {
                    let lo = down ? ceilingBottom(g, x, y, z) : o.y, hi = up ? groundTop(g, x, y, z) : o.y + 1
                    if hi - lo > 0.1 { out.append((V3(o.x, lo, o.z), V3(o.x + 1, hi, o.z + 1))); return }
                }
            }
            out.append((o, o + 1)); return
        }
        for bx in shapeBoxes(x, y, z, BlockID(b), collision: true) { out.append((o + bx.minV, o + bx.maxV)) }
    }

    // Model boxes of a block, resolving connecting blocks (fences, panes, walls) from their neighbours.
    func shapeBoxes(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID, collision: Bool) -> [Box] {
        let ck = Blocks.connectKind[Int(b)]
        if ck == 0 { return collision ? Blocks.collBoxes[Int(b)] : Blocks.boxes[Int(b)] }
        // (P377 step 2: the neighbours as the mesher joins them: the ground beside as its material, the way it's drawn)
        return BlockRegistry.connectBoxes(ck, n: Blocks.connects(ck, materialAt(x, y, z - 1)), s: Blocks.connects(ck, materialAt(x, y, z + 1)),
                                          w: Blocks.connects(ck, materialAt(x - 1, y, z)), e: Blocks.connects(ck, materialAt(x + 1, y, z)), collision: collision)
    }

    // Scratch for collides (frame thread only): taken and handed back, so a call never allocates its box list
    // (questcheck's allocation trace; sweep keeps its own, sweepScratch).
    private var boxScratch: [(V3, V3)] = []

    // PG2 rewrite: collides and sweep take the field's boxes apart (fieldSink) and meet them as a body stands on ground:
    // on its centre, not its corners. Falling, only the field under the middle of the body holds it up (a box on a slope
    // otherwise hangs on its uphill corner, hovering up to half a block over the ground under its feet); the feet may
    // sink into a slope's uphill side up to half a block (collides ignores the field's ground in the body's lowest part).
    var fieldSplit = false
    var fieldSink: [(V3, V3)] = []
    // (P386 checks: the last sweep's move as the built boxes left it, and the drawn floor it found)
    var sweepBoxesDD: Float = 0, sweepFloorY: Float? = nil
    // PG2 rewrite: the last raycast's hit on the field's ground (its cell, the point on the drawn surface, the distance).
    var fieldHit: (cell: IVec3, at: V3, t: Float)?

    // P306 (Oct 15 12:13, "walk over bodies, not through them"): dead bodies lying on the ground as low boxes (about a
    // third of a block, so a walk steps up onto them), set each tick by MobManager.corpseTick. Only the player's own
    // move counts them (bodiesSolid around Player's moveBody), so bodies, mobs and items never catch on one.
    var bodyBoxes: [(V3, V3)] = []
    var bodiesSolid = false
    // P311 (a) (Oct 15 12:19, "he can't go through me, I can't go through him"): the player and the mobs are solid to
    // each other, sideways only (no one stands on a head or is lifted by one). The player's own moves (mobsSolid,
    // around Player's moveBody and the headset's room-scale steps) meet the living mobs near him (solidMobs, kept by
    // MobManager.separate; at least a block tall, so a step-up never carries him over a small one); each mob's move
    // meets the player's box (playerBox, set around Mob.update by MobManager), and a sweep cut short by it sets
    // touchedPlayer (a mob pressed against him neither hops nor counts as stuck).
    var solidMobs: [Mob] = []
    var mobsSolid = false
    // P417 (a) (Oct 23 21:06-21:12, "getting through a forest is a pain"; "you can crush through"): the player's own
    // moves (around Player's moveBody) pass through leaves and a tree's limbs (a log cell with no log or ground under
    // it); trunks still stop him. Mobs, items and every other query still meet them.
    var foliageSoft = false
    @inline(__always) func softFoliage(_ b: Int, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        switch ShapeClass.kind[b] {
        case .foliage: return true
        case .trunk:
            let u = Int(block(x, y - 1, z))
            return ShapeClass.kind[u] != .trunk && !Blocks.collide[u]
        default: return false
        }
    }
    // P447 (Oct 25 08:59: "the physics when I'm on top of a log is weird"): a log lying on natural ground with nothing
    // on it is drawn as a fallen trunk bedded in the ground, about half a block high and a tree's thickness across
    // (ShapeTrunks.timber), but was met as a whole block: he stood on air half a block over it and bumped into nothing
    // beside it. Met now as the trunk is drawn (the cell-local box), in field worlds where trunks are drawn round.
    @inline(__always) func fallenLog(_ b: Int, _ x: Int, _ y: Int, _ z: Int) -> (V3, V3)? {
        guard ShapeTrunks.isLog[b], Felling.roundTrunks else { return nil }
        let a = ShapeTrunks.axisOf[b]
        guard a != 1, SmoothTerrain.natural[Int(materialAt(x, y - 1, z))], !ShapeTrunks.isTrunk[Int(builtBlock(x, y + 1, z))] else { return nil }
        let r = ShapeTrunks.fallenRadius
        let top = min(1, r * 1.8 + 0.06)                    // (its centre r * 0.8 over the ground, the ground about at the cell's foot)
        return a == 0 ? (V3(0, -0.5, 0.5 - r), V3(1, top, 0.5 + r)) : (V3(0.5 - r, -0.5, 0), V3(0.5 + r, top, 1))
    }
    var playerBox: (V3, V3)?
    var touchedPlayer = false

    func collides(_ mn: V3, _ mx: V3) -> Bool {
        let eps: Float = 1e-4
        var boxes = boxScratch
        boxScratch = []
        defer { boxes.removeAll(keepingCapacity: true); boxScratch = boxes; fieldSplit = false }
        fieldSplit = fieldTerrain
        fieldSink.removeAll(keepingCapacity: true)
        for y in Int(floor(mn.y))...Int(floor(mx.y - eps)) {
            for z in Int(floor(mn.z))...Int(floor(mx.z - eps)) {
                for x in Int(floor(mn.x))...Int(floor(mx.x - eps)) {
                    boxes.removeAll(keepingCapacity: true)
                    collisionBoxes(x, y, z, &boxes)
                    for (a, b) in boxes where a.x < mx.x - eps && b.x > mn.x + eps && a.y < mx.y - eps && b.y > mn.y + eps && a.z < mx.z - eps && b.z > mn.z + eps {
                        return true
                    }
                }
            }
        }
        if !fieldSink.isEmpty {
            let lo = mn.y + min(0.5, (mx.y - mn.y) * 0.4)
            for (a, b) in fieldSink where a.x < mx.x - eps && b.x > mn.x + eps && a.y < mx.y - eps && b.y > lo + eps && a.z < mx.z - eps && b.z > mn.z + eps {
                return true
            }
        }
        if frame == nil && !ships.isEmpty && ships.overlaps(mn, mx) { return true }
        return false
    }

    // How far an AABB can move along one axis (0 x, 1 y, 2 z) before touching a collision box.
    private var sweepScratch: [(V3, V3)] = []
    // Chunks of this world that turned dirty since update last drained the list (main thread). The quiet-frame re-check
    // walks this instead of every loaded chunk (bench: update p50 0.015 -> 0.27 / 0.89 ms at rd 16 / 24, growing with
    // the chunk count, while random ticks and fluids touched a few blocks every frame). Per world: harness probes run
    // more than one world in a process.
    var dirtyChunks: [Chunk] = []
    // PG2: bumped by every terrain field change (TerrainField), so cached drawn ground heights (mobs, items) refresh.
    var fieldStamp = 0
    // PG2: drawn ground tops for collision (groundTop), direct-mapped by cell; an entry holds while fieldStamp does.
    // Main thread only, like sweep's scratch.
    var groundTopKey = [Int](repeating: Int.min, count: 4096)
    var groundTopVal = [Float](repeating: 0, count: 4096)
    // PG2 rewrite: the field's collision columns per cell (World.fieldBoxes), direct-mapped like groundTop: 16 (lo, hi).
    var fieldColKey = [Int](repeating: Int.min, count: 2048)
    var fieldColVal = [Float](repeating: 0, count: 2048 * 32)
    func sweep(_ mn: V3, _ mx: V3, axis a: Int, _ d: Float) -> Float {
        if d == 0 { return 0 }
        var lo = mn, hi = mx
        if d > 0 { hi[a] += d } else { lo[a] += d }
        let eps: Float = 1e-4
        // Main thread only (bodies, mobs, ships): the box list keeps its storage between calls (a new array per sweep,
        // several sweeps per walking mob per frame: bench mobs.per_mob_us 1.6 -> 7.8 us). Swapped out, so a nested
        // call can't share it.
        var boxes = sweepScratch
        sweepScratch = []
        boxes.removeAll(keepingCapacity: true)
        defer { sweepScratch = boxes; fieldSplit = false }
        fieldSplit = fieldTerrain
        fieldSink.removeAll(keepingCapacity: true)
        let y0 = Int(floor(lo.y - 0.5)), y1 = Int(floor(hi.y))     // -0.5: fences etc. poke up to 1.5
        let plain = frame == nil
        for z in Int(floor(lo.z))...Int(floor(hi.z - eps)) {
            for x in Int(floor(lo.x))...Int(floor(hi.x - eps)) {
                // One chunk lookup per column (it was a dictionary lookup per block); empty cells skip straight on.
                if plain {
                    guard let c = chunkAt(x, z) else {
                        if y0 < 0 { for y in y0...min(y1, -1) { collisionBoxes(x, y, z, &boxes) } }   // bedrock below 0
                        continue
                    }
                    let lx = mod(x, CS), lz = mod(z, CS)
                    let fieldC = fieldTerrain && c.blocks.isField
                    for y in y0...y1 {
                        if y >= 0 && y < CH {
                            let i = Chunk.index(lx, y, lz)
                            if fieldC { if !Blocks.collide[Int(c.blocks.raw(i))] && !fieldNear(c, x, y, z, i) { continue } }
                            else if !Blocks.collide[Int(c.blocks[i])] { continue }
                        }
                        collisionBoxes(x, y, z, &boxes)
                    }
                } else {
                    for y in y0...y1 { collisionBoxes(x, y, z, &boxes) }
                }
            }
        }
        if plain && !ships.isEmpty { ships.boxes(lo, hi, &boxes) }
        if plain && bodiesSolid {
            for b in bodyBoxes where b.0.x < hi.x && b.1.x > lo.x && b.0.y < hi.y && b.1.y > lo.y && b.0.z < hi.z && b.1.z > lo.z { boxes.append(b) }
        }
        if plain && mobsSolid && a != 1 {
            for m in solidMobs where m.health > 0 {
                let r = m.halfW, top: Float = m.pos.y + max(1, m.height)
                if m.pos.x - r < hi.x && m.pos.x + r > lo.x && m.pos.y < hi.y && top > lo.y && m.pos.z - r < hi.z && m.pos.z + r > lo.z {
                    boxes.append((V3(m.pos.x - r, m.pos.y, m.pos.z - r), V3(m.pos.x + r, top, m.pos.z + r)))
                }
            }
        }
        var dd = d
        let b1 = (a + 1) % 3, b2 = (a + 2) % 3
        for (bmn, bmx) in boxes {
            if bmn[b1] >= mx[b1] - eps || bmx[b1] <= mn[b1] + eps { continue }
            if bmn[b2] >= mx[b2] - eps || bmx[b2] <= mn[b2] + eps { continue }
            if dd > 0 && bmn[a] >= mx[a] - eps { dd = min(dd, bmn[a] - mx[a]) }
            if dd < 0 && bmx[a] <= mn[a] + eps { dd = max(dd, bmx[a] - mn[a]) }
        }
        // P311 (a): a mob's sideways move stops at the player's body.
        if plain && a != 1, let pb = playerBox, case let (bmn, bmx) = pb,
           bmn.x < hi.x && bmx.x > lo.x && bmn.y < hi.y && bmx.y > lo.y && bmn.z < hi.z && bmx.z > lo.z,
           !(bmn[b1] >= mx[b1] - eps || bmx[b1] <= mn[b1] + eps || bmn[b2] >= mx[b2] - eps || bmx[b2] <= mn[b2] + eps) {
            let was = dd
            if dd > 0 && bmn[a] >= mx[a] - eps { dd = min(dd, bmn[a] - mx[a]) }
            if dd < 0 && bmx[a] <= mn[a] + eps { dd = max(dd, bmx[a] - mn[a]) }
            if dd != was { touchedPlayer = true }
        }
        // P386: a body coming down on field ground stands on the drawn ground triangles under its middle (GroundFeet),
        // lifted out of them up to the part of its body the field's ground may sink into (collides), not on the field's
        // quarter-block columns. Where the section has no current drawn ground, the columns as before.
        var floorY: Float? = nil
        sweepBoxesDD = dd
        if a == 1 && d < 0 && plain && !fieldSink.isEmpty {
            let cx = (mn.x + mx.x) * 0.5, cz = (mn.z + mx.z) * 0.5
            let lift = min(0.5, (mx.y - mn.y) * 0.4)
            // (looked for a block further down than the move: drawn ground lower than the move reaches lets the body
            // fall on to it, instead of the columns catching it over the ground)
            floorY = drawnGround(cx, cz, lo: mn.y + min(d, -1) - 0.01, hi: mn.y + lift)
        }
        sweepFloorY = floorY
        if let g = floorY {
            dd = max(dd, g - mn.y)
        } else if !fieldSink.isEmpty {
            var fmn = mn, fmx = mx
            if a == 1 && d < 0 {
                let cx = (mn.x + mx.x) * 0.5, cz = (mn.z + mx.z) * 0.5
                let fr = min(0.05, (mx.x - mn.x) * 0.5, (mx.z - mn.z) * 0.5)
                fmn.x = cx - fr; fmx.x = cx + fr; fmn.z = cz - fr; fmx.z = cz + fr
            }
            for (bmn, bmx) in fieldSink {
                if bmn[b1] >= fmx[b1] - eps || bmx[b1] <= fmn[b1] + eps { continue }
                if bmn[b2] >= fmx[b2] - eps || bmx[b2] <= fmn[b2] + eps { continue }
                if dd > 0 && bmn[a] >= fmx[a] - eps { dd = min(dd, bmn[a] - fmx[a]) }
                if dd < 0 && bmx[a] <= fmn[a] + eps { dd = max(dd, bmx[a] - fmn[a]) }
            }
        }
        return dd
    }

    // The cells a body would push into at foot level are all natural ground (SmoothTerrain), with room above.
    func naturalStep(_ b: (V3, V3)) -> Bool {
        let y = Int(floor(b.0.y + 0.5))
        var hit = false
        for x in Int(floor(b.0.x))...Int(floor(b.1.x - 1e-4)) {
            for z in Int(floor(b.0.z))...Int(floor(b.1.z - 1e-4)) {
                let id = builtBlock(x, y, z), g = groundAt(x, y, z)       // (P377 step 2: the two layers apart)
                if !Blocks.collide[Int(id)] && !g { continue }
                if !g && !SmoothTerrain.natural[Int(id)] { return false }
                hit = true
            }
        }
        return hit
    }

    // Moves a body (feet-centred AABB) by delta with collision and optional step-up.
    // Returns which axes were blocked.
    func moveBody(_ pos: inout V3, halfW: Float, height: Float, _ delta: V3, step: Float, onGround: Bool) -> (x: Bool, y: Bool, z: Bool) {
        func box(_ p: V3) -> (V3, V3) { (V3(p.x - halfW, p.y, p.z - halfW), V3(p.x + halfW, p.y + height, p.z + halfW)) }
        func attempt(_ start: V3, _ d: V3) -> (V3, Bool, Bool, Bool) {
            var p = start
            var (mn, mx) = box(p)
            let dy = sweep(mn, mx, axis: 1, d.y)
            p.y += dy; (mn, mx) = box(p)
            let dx = sweep(mn, mx, axis: 0, d.x)
            p.x += dx; (mn, mx) = box(p)
            let dz = sweep(mn, mx, axis: 2, d.z)
            p.z += dz
            var hy = abs(dy - d.y) > 1e-5
            // P386: a body on field ground keeps its feet on the drawn ground as it walks: over a rise it is lifted at
            // once (not on the next fall), down a slope up to about 60 degrees it follows the ground (walking off a ledge
            // still falls).
            if fieldTerrain && frame == nil && onGround && d.y <= 0 && (dx != 0 || dz != 0) {
                let stick = (dx * dx + dz * dz).squareRoot() * 2 + 0.02
                (mn, mx) = box(p)
                let s = sweep(mn, mx, axis: 1, -stick)
                if s > -stick + 1e-4 { p.y += s; hy = true }
            }
            return (p, abs(dx - d.x) > 1e-5, hy, abs(dz - d.z) > 1e-5)
        }
        // Sub-step so the swept region stays small.
        let steps = max(1, Int(ceil(max(abs(delta.x), abs(delta.y), abs(delta.z)) / 0.9)))
        var bx = false, by = false, bz = false
        let sd = delta / Float(steps)
        for _ in 0..<steps {
            var (p, hx, hy, hz) = attempt(pos, sd)
            if step > 0 && (hx || hz) && (onGround || (hy && sd.y < 0)) {
                // Try stepping up (slabs, stairs): lift, move horizontally, drop back down.
                func tryStep(_ step: Float) -> Bool {
                    let up = sweep(box(pos).0, box(pos).1, axis: 1, step)
                    var lifted = pos
                    lifted.y += up
                    let (p2, hx2, _, hz2) = attempt(lifted, V3(sd.x, 0, sd.z))
                    let (mn2, mx2) = box(p2)
                    // (P386: on field ground, down to the drawn ground ahead as attempt's stick does: stepping over a
                    // knee-high bump on the way down a slope left the body hanging a tenth over the ground for a tick)
                    let stick: Float = fieldTerrain && frame == nil && onGround ? (sd.x * sd.x + sd.z * sd.z).squareRoot() * 2 + 0.02 : 0
                    let down = sweep(mn2, mx2, axis: 1, -up - max(0, -sd.y) - stick)
                    var p3 = p2
                    p3.y += down
                    let gain = simd_length(V2(p3.x - pos.x, p3.z - pos.z)) - simd_length(V2(p.x - pos.x, p.z - pos.z))
                    if gain > 1e-4 { p = p3; hx = hx2; hz = hz2; hy = true; return true }
                    return false
                }
                // Smooth terrain: a one-block step of natural ground is a slope, walked up without a jump.
                if !tryStep(step) && step < 1 && SmoothTerrain.enabled && naturalStep(box(pos + V3(sd.x, 0, sd.z))) { _ = tryStep(1.01) }
            }
            pos = p
            bx = bx || hx; by = by || hy; bz = bz || hz
        }
        return (bx, by, bz)
    }

    // MARK: Meshing

    // P376: a chunk about to change: a shell gets its blocks back at once, and its disk-cached meshes are stale.
    @inline(__always) func editing(_ c: Chunk) -> Chunk {
        if c.hollow { refillNow(c) }
        if !c.cacheDropped { c.cacheDropped = true; meshCache?.drop(ChunkKey(x: c.cx, z: c.cz)) }
        return c
    }

    func neighbourhood(_ c: Chunk) -> ([BlockStore], [[Int16]])? {
        // P376: a shell's blocks come back on a worker first (ChunkShells).
        var shells = false
        for dz in -1...1 { for dx in -1...1 {
            if let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)], n.hollow { requestRefill(ChunkKey(x: n.cx, z: n.cz)); shells = true }
        } }
        if shells { return nil }
        var n9: [BlockStore] = []
        var h9: [[Int16]] = []
        n9.reserveCapacity(9)
        h9.reserveCapacity(9)
        for dz in -1...1 {
            for dx in -1...1 {
                let nn: Chunk? = (dx == 0 && dz == 0) ? c : chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)]
                guard let n = nn else { return nil }
                n9.append(n.blocks)
                h9.append(n.height)
            }
        }
        return (n9, h9)
    }

    // Harness edits made with setBlockAsync over an area: remesh it now so its meshes and stored light are current
    // (a demo car built in a freshly dug pit was lit as if the pit were still rock: blind critic, run 385 ship_car).
    func remeshArea(x0: Int, z0: Int, x1: Int, z1: Int, y0: Int, y1: Int) {
        for cz in floorDiv(z0, CS)...floorDiv(z1, CS) { for cx in floorDiv(x0, CS)...floorDiv(x1, CS) {
            guard let c = chunks[ChunkKey(x: cx, z: cz)] else { continue }
            let lo = max(0, y0 >> 4), hi = min(NSEC - 1, y1 >> 4)
            guard lo <= hi else { continue }                    // wholly above or below the world: nothing to remesh
            for sy in lo...hi { remeshSync(c, sy) }
        } }
    }

    // Harness: a section meshed at full detail and at far detail, (opaque quads, cutout quads) each.
    func lodQuads(_ c: Chunk, _ sy: Int) -> [(Int, Int)] {
        guard let nb = neighbourhood(c) else { return [] }
        return [0, 1].map { lod in
            let m = Mesher.buildSection(nb.0, nb.1, sy: sy, lod: lod, site: smoothSite(c), chunk: (c.cx, c.cz), nearSides: nearSides(c, lod: lod), fineBeyond: fineBeyond(c, nb.0))
            let q = m.opaque.count / 8
            return (m.solidQuads, q - m.solidQuads)
        }
    }

    // Every loaded section meshes again (in the background), e.g. after the smooth terrain toggle.
    func remeshAll() {
        for c in chunks.values { for s in c.sections where s.meshedVersion != -1 { s.version += 1 } }
    }

    // P440: while an edit is measured, the cells whose field samples it changed (FieldTerrain, FineField, GroundMeet):
    // the frame meshes only the sections within a cell of them (a changed sample moves the dual cells round it).
    var changeBox: (lo: IVec3, hi: IVec3)?
    @inline(__always) func noteChange(_ x: Int, _ y: Int, _ z: Int) {
        guard let b = changeBox else { return }
        changeBox = (IVec3(min(b.lo.x, x), min(b.lo.y, y), min(b.lo.z, z)), IVec3(max(b.hi.x, x), max(b.hi.y, y), max(b.hi.z, z)))
    }
    // Runs f measuring its changes (merged into an outer measure too); nil when it changed no sample.
    func measureChanges(_ f: () -> Void) -> (lo: IVec3, hi: IVec3)? {
        let outer = changeBox
        changeBox = (IVec3(Int.max, Int.max, Int.max), IVec3(Int.min, Int.min, Int.min))
        f()
        let b = changeBox!
        changeBox = outer
        guard b.lo.x <= b.hi.x else { return nil }
        noteChange(b.lo.x, b.lo.y, b.lo.z); noteChange(b.hi.x, b.hi.y, b.hi.z)
        return b
    }
    // Does section sy of c lie within `grow` cells of the box?
    @inline(__always) static func near(_ c: Chunk, _ sy: Int, _ b: (lo: IVec3, hi: IVec3), grow g: Int) -> Bool {
        let x0 = c.cx * CS, z0 = c.cz * CS, y0 = sy * 16
        return b.hi.x + g >= x0 && b.lo.x - g < x0 + CS && b.hi.z + g >= z0 && b.lo.z - g < z0 + CS && b.hi.y + g >= y0 && b.lo.y - g < y0 + 16
    }

    // P440 (Oct 24 20:55, "a five hundred millisecond freeze every time I place a block"): edits made together (a placed
    // block, then the ground swelling to it) mesh each section once on the frame, at the end, not once an edit.
    // On the headset (World.editLane, QuestApp) they mesh off the frame on their own lane, every section of the edit in one
    // job and installed together a frame or two later (the old meshes stay up until then, so nothing opens or doubles):
    // a placed block costs the frame its data writes only, where meshing even one section took about a frame's budget.
    private var syncBatch: [(Chunk, Int)]?
    static var syncMeshes = 0                       // sections meshed on the frame since start (questcheck --edittime)
    static var editLane = false
    static let editQueue = DispatchQueue(label: "blocksmith.editmesh", qos: .userInteractive)
    // P475 (Oct 27 19:12, in a Greywall base under fire: "It took three seconds for the door to open"; "It took a minute
    // for those blocks to get destroyed in the base"): every edit's sections waited on the one lane behind all the
    // blasts before them, each meshed from its own snapshot. A section a later edit queues again is now skipped by the
    // earlier job (the later one meshes it from newer blocks), and a small edit (a door, a placed block) has a lane of
    // its own, so it never queues behind a battle's craters.
    static let quickQueue = DispatchQueue(label: "blocksmith.quickmesh", qos: .userInteractive)
    private var editTicket = 0
    private var editLatest: [Int64: Int] = [:]          // section -> the newest edit job that meshes it (under lock)
    static var editSkipped = 0                           // (harness: sections an older edit job left to a newer one)
    @inline(__always) static func sectionKey(_ k: ChunkKey, _ sy: Int) -> Int64 {
        (Int64(k.x & 0xFFFFFF) << 32) | (Int64(k.z & 0xFFFFFF) << 8) | Int64(sy & 0xFF)
    }
    func editBatch(_ f: () -> Void) {
        if syncBatch != nil { f(); return }
        syncBatch = []
        f()
        let list = syncBatch ?? []
        syncBatch = nil
        if World.editLane && !World.deterministic { remeshSoon(list) } else { for (c, sy) in list { remeshSync(c, sy) } }
    }

    // P440: the sections of one edit meshed together on the edit lane; their results go in with the next frame's.
    func remeshSoon(_ list: [(Chunk, Int)]) {
        var byChunk: [(Chunk, [Int])] = []
        for (c, sy) in list {
            if let i = byChunk.firstIndex(where: { $0.0 === c }) { if !byChunk[i].1.contains(sy) { byChunk[i].1.append(sy) } }
            else { byChunk.append((c, [sy])) }
        }
        var builds: [(_ live: (ChunkKey, Int) -> Bool) -> (ChunkKey, [(Int, Int, SectionMesh)])] = []
        // P474 (Oct 26 19:42, in the Capital citadel: "placing blocks inside the capital, blocks take a second to load"):
        // the lane drew each section's ground simplified (AdaptiveGround), nine tenths of its time: about 300 ms a
        // section on the cloud host, an edit's 4-8 sections one after another. It draws the ground exact, as the frame's
        // own remesh does, and a worker then redraws the touched sections simplified (the version bump below).
        let adapt = !fieldTerrain
        var redraw: [(Chunk, Int)] = []
        for (c, sys) in byChunk {
            guard let nb = neighbourhood(c) else { continue }           // (its regular job meshes it once the ring is in)
            let k = ChunkKey(x: c.cx, z: c.cz)
            let todo = sys.map { ($0, c.sections[$0].version) }
            let lod = c.lod, dl = damageList(c), bl = biteList(c), pl = pieceList(c), ol = objectReg.draws(c), site = smoothSite(c)
            let near = nearSides(c, lod: lod), beyond = fineBeyond(c, nb.0)
            let (n9, h9) = nb
            builds.append { live in
                (k, todo.filter { live(k, $0.0) }.map { (sy, v) in
                    (sy, v, Mesher.buildSection(n9, h9, sy: sy, lod: lod, damage: dl, bites: bl, pieces: pl, objects: ol, site: site,
                                                chunk: (k.x, k.z), nearSides: near, adaptive: adapt, fineBeyond: beyond)) })
            }
            c.meshInFlight = true
            c.meshJobsOut += 1
            for sy in sys { redraw.append((c, sy)) }
        }
        guard !builds.isEmpty else { return }
        if fieldTerrain && AdaptiveGround.enabled { for (c, sy) in redraw { c.sections[sy].version += 1 } }
        jobs += builds.count
        lock.lock()
        editTicket += 1
        let ticket = editTicket
        let edited = redraw.map { World.sectionKey(ChunkKey(x: $0.0.cx, z: $0.0.cz), $0.1) }
        for key in edited { editLatest[key] = ticket }
        lock.unlock()
        let lane = edited.count <= 4 ? World.quickQueue : World.editQueue
        lane.async { [weak self] in
            guard let self else { return }
            let out = builds.map { b in
                b { k, sy in
                    let key = World.sectionKey(k, sy)
                    self.lock.lock(); defer { self.lock.unlock() }
                    guard let t = self.editLatest[key], t > ticket else { return true }
                    World.editSkipped &+= 1
                    return false
                }
            }
            self.lock.lock()
            for key in edited where self.editLatest[key] == ticket { self.editLatest[key] = nil }
            self.meshResults.append(contentsOf: out)
            self.lock.unlock()
        }
    }

    func remeshSync(_ c: Chunk, _ sy: Int) {
        if syncBatch != nil {
            if !syncBatch!.contains(where: { $0.0 === c && $0.1 == sy }) { syncBatch!.append((c, sy)) }
            return
        }
        guard let nb = neighbourhood(c) else { return }
        World.syncMeshes &+= 1
        apply(Mesher.buildSection(nb.0, nb.1, sy: sy, lod: c.lod, damage: damageList(c), bites: biteList(c), pieces: pieceList(c), objects: objectReg.draws(c), site: smoothSite(c), chunk: (c.cx, c.cz),
                                  nearSides: nearSides(c, lod: c.lod), adaptive: !fieldTerrain, fineBeyond: fineBeyond(c, nb.0)), to: c, sy: sy, version: c.sections[sy].version)
        // P381 step 5: on the frame the edit draws the section's ground in full (no wait, exact), and a mesh worker then
        // redraws just the touched sections with the adaptive ground (AdaptiveGround.swift).
        if fieldTerrain && AdaptiveGround.enabled { c.sections[sy].version += 1 }
    }

    // P142: smooth sections of a world whose generator has continuous fields (the overworld) mesh those fields.
    func smoothSite(_ c: Chunk) -> SmoothSite? {
        guard SmoothTerrain.enabled && SmoothTerrain.fromField, !fieldTerrain, let g = gen as? WorldGen else { return nil }
        return SmoothSite(gen: g, cx: c.cx, cz: c.cz, edits: fieldEditSet(c))
    }

    // MARK: Progressive block damage

    // Chipped blocks: world cell -> face << 5 | level (1...7 of 8 chipped away). Cleared when the block changes;
    // not saved (a chipped block comes back whole after the chunk reloads).
    func damageLevel(_ p: IVec3) -> Int { Int((damage[p] ?? 0) & 31) }

    // The damaged blocks a chunk's sections need (its own and one chunk round), relative to its corner.
    func damageList(_ c: Chunk) -> [(Int, Int, Int, UInt8)] {
        if damage.isEmpty { return [] }
        let bx = c.cx * CS, bz = c.cz * CS
        var out: [(Int, Int, Int, UInt8)] = []
        for (p, v) in damage {
            let dx = p.x - bx, dz = p.z - bz
            if dx >= -16 && dx < 32 && dz >= -16 && dz < 32 { out.append((dx, p.y, dz, v)) }
        }
        return out
    }

    // Realistic world (docs/design/realistic-world.md 2): Polygons (Smooth) worlds on the Quest draw blows as craters
    // (bites) instead of chipped sub-cubes, and the block keeps its whole box for walking until it breaks.
    static var realistic: Bool { SmoothTerrain.enabled && Mesher.detailMeshes }

    // The bites a chunk's sections need (its own and one chunk round), relative to its corner.
    func biteList(_ c: Chunk) -> [(Int, Int, Int, Bite)] {
        if bites.isEmpty { return [] }
        let bx = c.cx * CS, bz = c.cz * CS
        var out: [(Int, Int, Int, Bite)] = []
        for (p, list) in bites {
            let dx = p.x - bx, dz = p.z - bz
            if dx >= -16 && dx < 32 && dz >= -16 && dz < 32 { for b in list { out.append((dx, p.y, dz, b)) } }
        }
        return out
    }

    // A blow struck block p at world point `at`, coming out of the block along `axis`: a bowl of rim radius r and depth d
    // is carved there (8 bites a block at most: the oldest goes; 4096 bitten blocks in all). sync remeshes now (the
    // player's own pickaxe), else in the background (bullets, blasts).
    func addBite(_ p: IVec3, at: V3, axis: V3, radius: Float, depth: Float, seed: UInt32, sync: Bool) {
        guard p.y >= 0 && p.y < CH else { return }
        if bites[p] == nil && bites.count >= 4096 { return }
        let c = SIMD3<Float>(at.x - Float(p.x), at.y - Float(p.y), at.z - Float(p.z))
        var list = bites[p] ?? []
        if list.count >= 8 { list.removeFirst() }
        list.append(Bite(c: simd_clamp(c, SIMD3<Float>(repeating: -0.5), SIMD3<Float>(repeating: 1.5)), n: axis, r: radius, d: depth, seed: seed))
        bites[p] = list
        let r = Int(ceil(radius * 1.4)) + 1
        if sync {
            // P446 (Oct 25 09:13, "it's freezing every time I break a block", fps 4 mining dirt): each crack level of a
            // block he mines carves a bite here, and its sections (up to 8) were meshed on the frame, outside the edit
            // lane P440 gave placed and broken blocks. Now on the lane: the bite shows a frame or two later.
            editBatch { remeshArea(x0: p.x - r, z0: p.z - r, x1: p.x + r, z1: p.z + r, y0: p.y - r, y1: p.y + r) }
        } else {
            for cz in floorDiv(p.z - r, CS)...floorDiv(p.z + r, CS) { for cx in floorDiv(p.x - r, CS)...floorDiv(p.x + r, CS) {
                guard let ch = chunks[ChunkKey(x: cx, z: cz)] else { continue }
                for sy in max(0, (p.y - r) >> 4)...min(NSEC - 1, (p.y + r) >> 4) { ch.sections[sy].version += 1 }
            } }
        }
    }

    // The same without the immediate remesh (explosions chip dozens at once): the sections remesh in the background.
    func chipAsync(_ p: IVec3, level: Int, face: Int) {
        let cur = damage[p]
        let lv = max(level, Int((cur ?? 0) & 31))
        guard lv > 0 && lv < 8, p.y >= 0 && p.y < CH else { return }
        if damage.count > 4096 && cur == nil { return }
        let f = cur.map { Int($0 >> 5) } ?? face
        damage[p] = UInt8((f & 7) << 5 | min(7, lv))
        for dz in -1...1 { for dx in -1...1 {
            guard let n = chunkAt(p.x + dx * 16, p.z + dz * 16) else { continue }
            for sy in max(0, (p.y - 16) >> 4)...min(NSEC - 1, (p.y + 16) >> 4) { n.sections[sy].version += 1 }
        } }
    }

    // Chips a block to `level` (keeps the face of the first hit); remeshes around it now.
    // remesh false only records the level (the realistic world draws the blow as a bite instead: addBite).
    func chip(_ p: IVec3, level: Int, face: Int, remesh: Bool = true) {
        guard p.y >= 0 && p.y < CH else { return }             // as chipAsync (the harness chipped above the world top)
        let cur = damage[p]
        let lv = max(level, Int((cur ?? 0) & 31))
        guard lv > 0 && lv < 8 else { return }
        if damage.count > 4096 && cur == nil { return }
        let f = cur.map { Int($0 >> 5) } ?? face
        let v = UInt8((f & 7) << 5 | min(7, lv))
        if cur == v { return }
        damage[p] = v
        if !remesh { return }
        editBatch { remeshArea(x0: p.x - 1, z0: p.z - 1, x1: p.x + 1, z1: p.z + 1, y0: p.y - 1, y1: p.y + 1) }     // (P446: the edit lane)
        // A chipped block also dents the smooth surface round it (as far as the relaxation reaches): in the background.
        if SmoothTerrain.enabled {
            let r = 3 + SmoothTerrain.relax
            for cz in floorDiv(p.z - r, CS)...floorDiv(p.z + r, CS) { for cx in floorDiv(p.x - r, CS)...floorDiv(p.x + r, CS) {
                guard let c = chunks[ChunkKey(x: cx, z: cz)] else { continue }
                for sy in max(0, (p.y - r) >> 4)...min(NSEC - 1, (p.y + r) >> 4) {
                    let near = cx >= floorDiv(p.x - 1, CS) && cx <= floorDiv(p.x + 1, CS) && cz >= floorDiv(p.z - 1, CS) && cz <= floorDiv(p.z + 1, CS)
                        && sy >= (p.y - 1) >> 4 && sy <= (p.y + 1) >> 4
                    if !near { c.sections[sy].version += 1 }
                }
            } }
        }
    }

    private func makeBuffer(_ words: [UInt32]) -> MeshSlice? {
        if words.isEmpty { return nil }
        return words.withUnsafeBytes { MeshArena.shared.alloc(device, $0) }
    }

    // P446 (Oct 25, new land: "it's literally trying to render it from the bottom up"; a village half drawn for 20 s): a
    // mesh made for a section that changed while it was made (water settling, grass, a neighbour's border, a door) was
    // thrown away and the section waited for its next turn. New land's surface changes all the time while it comes in
    // and the caves under it don't, so the surface was thrown away again and again while the rock under it showed. Now a
    // mesh newer than the one drawn is drawn, and the section stays out of date (it meshes again). BS_STALEMESH=0: old way.
    static var keepStale = ProcessInfo.processInfo.environment["BS_STALEMESH"] != "0"
    // P446: set while water and lava settle and random ticks run: the sections they change mesh in the queue's order,
    // not ahead of it (World.update's edited-chunk pass is for edits: a blast, a dug block, a door).
    static var backgroundEdits = false
    static var meshLog = ProcessInfo.processInfo.environment["BS_MESHLOG"] == "1"
    // P474 (Oct 26 19:28-20:14: "land doesn't like generating unless it's really forced to"; "I had to literally fly
    // into the void in order to get things to generate"): water and lava settling in the caves of new land (and random
    // ticks) changed the chunks round him every few frames, and each such chunk meshed again as soon as its last job was
    // done: standing still by a citadel, the workers spent three quarters of their time re-meshing settling fluid, and
    // new land waited behind it. A chunk more than two chunks off whose only change is such settling now meshes again
    // at most every settleGap seconds (lava moves a block in 1.5 s); an edit (a blast, a dug block, a door) still goes at
    // once. Within two chunks of him the gap is settleNear (water moves a block every quarter second), so what flows
    // in front of him still moves block by block. BS_SETTLEMESH=0: the old way.
    static var settleGap: Double = ProcessInfo.processInfo.environment["BS_SETTLEMESH"] == "0" ? 0 : 0.75
    static var settleNear: Double = Double(ProcessInfo.processInfo.environment["BS_SETTLENEAR"] ?? "") ?? 0.25
    private var held: [Chunk] = []
    private var heldCheck: Double = 0
    // P487: flying faster than settleFast (blocks a second), the chunks round him pass under him in a second or two
    // and he isn't watching their water flow block by block: they settle on the far gap too, and their workers' time
    // goes to the land coming up ahead (at the dropship's 60 b/s, re-meshing the settling caves of the chunks within
    // two of him was over two fifths of all meshing). BS_SETTLEFAST=0: the old way.
    static var settleFast: Float = ProcessInfo.processInfo.environment["BS_SETTLEFAST"] == "0" ? .infinity : 20
    @inline(__always) private var settleNearGap: Double {
        simd_length_squared(V2(lead.x, lead.z)) > World.settleFast * World.settleFast ? World.settleGap : World.settleNear
    }
    @inline(__always) private func holdBack(_ c: Chunk, _ dx: Int, _ dz: Int, _ now: Double) -> Bool {
        guard World.settleGap > 0 && c.meshedOnce && !c.urgent
              && now - c.meshAt < (max(abs(dx), abs(dz)) > 2 ? World.settleGap : settleNearGap) else { return false }
        if !c.held { c.held = true; held.append(c) }
        return true
    }
    static var staleMeshes = 0, staleDrawn = 0      // (harness --streamtest: meshes for a changed section; of them drawn)
    private func apply(_ m: SectionMesh, to c: Chunk, sy: Int, version: Int) {
        let s = c.sections[sy]
        if let l = m.light { c.light[sy] = l }
        if version != s.version {
            World.staleMeshes &+= 1
            guard World.keepStale && version > s.meshedVersion else { return }
            World.staleDrawn &+= 1
        }
        s.opaqueBuf = makeBuffer(m.farGround.isEmpty ? m.opaque : m.opaque + m.farGround)
        s.opaqueQuads = m.opaque.count / 8
        s.solidQuads = m.solidQuads
        s.farSkip = m.farGround.isEmpty ? 0 : m.farSkip; s.farExtra = m.farGround.count / 8
        s.farCut = m.farCut; s.farTail = m.farTail
        s.blobFarN = m.farGround.isEmpty ? 0 : Int(m.farParts[2]); s.blobFarAt = Int(m.farParts[0] + m.farParts[1])
        s.blobCutN = s.blobFarN > 0 ? max(0, m.farCut - Int(m.farParts[3])) : 0
        s.transBuf = makeBuffer(m.trans)
        s.transQuads = m.trans.count / 8
        s.meshedVersion = version
        s.vis = m.vis
        s.leafy = m.leafy
        s.detailBuf = makeBuffer(m.detailFar.isEmpty ? m.detail : m.detail + m.detailFar)
        s.detailQuads = m.detail.count / DetailMesh.wordsPerQuad
        s.detailFarSkip = m.detailFar.isEmpty ? 0 : m.detailFarSkip; s.detailFarExtra = m.detailFar.count / DetailMesh.wordsPerQuad
        s.detailSolid = m.detailSolid
        s.groundQuads = m.groundQuads; s.blobQuads = m.blobQuads; s.naturalCubes = m.naturalCubes; s.solidFull = m.solidFull
        s.kinds = m.kinds
        s.ground = m.ground
        if sy >= c.topSec { c.updateTopSec() }            // a mesh below the top section cannot move it
        if c.tintBuf == nil {
            c.tintBuf = c.tint.withUnsafeBytes { MeshArena.tints.alloc(device, $0) }
        }
    }

    private func dirtySections(_ c: Chunk) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (sy, s) in c.sections.enumerated() where s.needsMesh { out.append((sy, s.version)) }
        return out
    }

    // MARK: Streaming (call once per frame)

    // Agent runs / replays: wait for last frame's jobs and apply every result in chunk order, so streaming (and
    // the light that meshing computes) never depends on timing.
    static var deterministic = false
    // Frame-thread time for installing generated chunks and meshes (the rest wait a frame). 4 ms on the Mac (60 Hz);
    // QuestApp sets 1.5 ms: fast flight at rd 16 handed over results every frame, ~1 ms mean and 4-5 ms spikes on the
    // headset's slower cores, on top of a 9-10 ms CPU frame (Oct 10 playtest: frames missed while flying). 1.5 ms a
    // frame at 72 Hz is still ~108 ms a second, several times what the fastest flight produces.
    static var handoverSeconds = 0.004

    var lead = V3.zero          // P414: the player's horizontal velocity (Game.tickSeat), for the ground made first
    func update(center pos: V3) {
        let tUpdate = CFAbsoluteTimeGetCurrent()
        defer { lastUpdateSeconds = CFAbsoluteTimeGetCurrent() - tUpdate }
        let center = ChunkKey(x: floorDiv(Int(floor(pos.x)), CS), z: floorDiv(Int(floor(pos.z)), CS))
        activeCenter = pos
        eyeSection = max(0, min(NSEC - 1, (Int(floor(pos.y)) + 1) >> 4))
        buriedTick(pos, center, extraCenter.map { ChunkKey(x: floorDiv(Int(floor($0.x)), CS), z: floorDiv(Int(floor($0.z)), CS)) })

        if World.deterministic { workQueue.waitIdle() }
        lock.lock()
        // Taken by swap: copying then removeAll(keepingCapacity:) on the shared buffer allocated a fresh one of the full
        // capacity twice a frame, results or not, while the workers waited on this lock.
        var gr: [(ChunkKey, Produced)] = []
        var mr: [(ChunkKey, [(Int, Int, SectionMesh)])] = []
        if !genResults.isEmpty { swap(&gr, &genResults) }
        if !meshResults.isEmpty { swap(&mr, &meshResults) }
        lock.unlock()
        if World.deterministic {
            gr.sort { (a: (ChunkKey, Produced), b: (ChunkKey, Produced)) -> Bool in a.0.x != b.0.x ? a.0.x < b.0.x : a.0.z < b.0.z }
            mr.sort { (a: (ChunkKey, [(Int, Int, SectionMesh)]), b: (ChunkKey, [(Int, Int, SectionMesh)])) -> Bool in
                a.0.x != b.0.x ? a.0.x < b.0.x : a.0.z < b.0.z
            }
        }

        // Results are applied within a per-frame budget; the rest wait for the next frame. P430 (a): meshes of chunks
        // round the player (a blast's crater, a dug block) go in whatever the budget; behind the streaming's installs
        // they waited for a frame with budget to spare.
        let budget = World.handoverSeconds
        let nearMeshes = World.deterministic ? 0 : mr.partition { abs($0.0.x - center.x) > 6 || abs($0.0.z - center.z) > 6 }
        var gi = 0, mi = 0
        // (P500: a shot waiting where it struck in the shell band, its chunks' blocks go in ahead of new land.)
        if !strikeRefills.isEmpty && !World.deterministic && gr.count > 1 {
            let refills = strikeRefills
            _ = gr.partition { !refills.contains($0.0) }
        }
        while gi < gr.count && (gi == 0 || World.deterministic || CFAbsoluteTimeGetCurrent() - tUpdate < budget) {
            let (k, p) = gr[gi]; gi += 1
            genInFlight.remove(k)
            jobs -= 1
            let ti = World.resultsProfile ? CFAbsoluteTimeGetCurrent() : 0
            if !strikeRefills.isEmpty { strikeRefills.remove(k) }
            if let c = chunks[k] { if c.hollow { refill(c, p) }; World.noteResult(ti, "refill"); continue }
            if let e = p.cached { installShell(k, e); World.noteResult(ti, "shell from the cache"); continue }
            install(k, p)
            World.noteResult(ti, p.fromDisk ? "install (saved)" : "install (generated)")
        }
        while mi < mr.count && (mi <= nearMeshes || World.deterministic || CFAbsoluteTimeGetCurrent() - tUpdate < budget) {
            let (k, list) = mr[mi]; mi += 1
            jobs -= 1
            if !frontOut.isEmpty { frontOut.remove(k) }
            guard let c = chunks[k] else { continue }
            let ti = World.resultsProfile ? CFAbsoluteTimeGetCurrent() : 0
            c.meshJobsOut = max(0, c.meshJobsOut - 1)
            if c.meshJobsOut == 0 { c.meshInFlight = false }
            c.meshedOnce = true
            for (sy, version, mesh) in list { apply(mesh, to: c, sy: sy, version: version) }
            World.noteResult(ti, "meshes applied")
        }
        World.handoverSpent += CFAbsoluteTimeGetCurrent() - tUpdate; World.handedOver += gi + mi
        World.leftWaiting = gr.count - gi + mr.count - mi
        if gi < gr.count || mi < mr.count {
            lock.lock()
            genResults.insert(contentsOf: gr[gi...], at: 0)
            meshResults.insert(contentsOf: mr[mi...], at: 0)
            lock.unlock()
        }
        TickProf.mark("world.results")              // the rest of update() is charged to "world.update" (Game.tick)
        shellClock &+= 1
        if trimIn > 0 { trimIn -= 1; if trimIn == 0 { let b = MeshArena.shared.trim(); if b > 0 { print("world: view lowered, \(b >> 20) MB of mesh slabs given back") } } }
        if shellClock % 120 == 0 { reshell() }        // P376: chunks meshed since the last move become shells

        let extra: ChunkKey? = extraCenter.map { ChunkKey(x: floorDiv(Int(floor($0.x)), CS), z: floorDiv(Int(floor($0.z)), CS)) }
        // Offset of a chunk from the nearer centre (Chebyshev), for LOD.
        func nearOff(_ k: ChunkKey) -> (Int, Int) {
            let a = (k.x - center.x, k.z - center.z)
            guard let e = extra else { return a }
            let b = (k.x - e.x, k.z - e.z)
            return max(abs(b.0), abs(b.1)) < max(abs(a.0), abs(a.1)) ? b : a
        }
        if center != lastCenter || extra != lastExtra {
            lastCenter = center
            lastExtra = extra
            // Unload outside the load disc grown by one more chunk (hysteresis when walking back and forth).
            var gone: [ChunkKey] = []
            for (k, c) in chunks where !World.inDisc(k.x - center.x, k.z - center.z, renderDistance, grow: 2)
                && !(extra.map { World.inDisc(k.x - $0.x, k.z - $0.z, renderDistance, grow: 2) } ?? false) {
                if c.needsSave && !c.hollow { save?.saveChunkAsync(k, c.blocks) }
                if c.fieldDirty { save?.saveFieldEdits(k, c.fieldEdits); c.fieldDirty = false }
                cacheMeshes(k, c)                                   // P376 (ChunkShells)
                gone.append(k)
            }
            for k in gone { chunks.removeValue(forKey: k) }
            reshell()                                               // P376: drop the data of finished far chunks
            // Chunks crossing the LOD boundary get remeshed at their new detail level.
            for (k, c) in chunks {
                let (ox, oz) = nearOff(k)
                let want = lodFor(ox, oz, current: c.lod)
                if want != c.lod { setLod(c, want) }
            }
            TickProf.mark("world.unload+lod")
        }

        // P414: the ground under the player and where he will be in the next two seconds is made first, ahead of every
        // waiting job (flying fast at view 24 outran the nearest-first walk), so he rarely moves over ground not made yet.
        if Player.moveOverUnmade && (lead != .zero || chunks[center] == nil) {
            var ahead: [ChunkKey] = [center]
            for t in [0.5, 1.0, 2.0] as [Float] {
                let q = pos + lead * t
                let k = ChunkKey(x: floorDiv(Int(floor(q.x)), CS), z: floorDiv(Int(floor(q.z)), CS))
                if !ahead.contains(k) { ahead.append(k) }
            }
            for k in ahead where chunks[k] == nil && !genInFlight.contains(k) && World.inDisc(k.x - center.x, k.z - center.z, renderDistance, grow: 0) {
                startGen(k, urgent: true)
            }
        }

        // P430 (a) (Oct 24: a hit's crater "takes a while to form"): a chunk edited round the player (a blast, a dug block,
        // a door) is re-meshed ahead of every waiting job and past the queue limit. While the far land streamed in, its
        // job waited behind the full queue of far chunks (8 a worker) and the crater showed well after the flash.
        // P446 (Oct 25, new land: "in creative, I can't really travel anywhere"; a village half drawn for 20 s): only for
        // edits, and at most half the workers at a time. Water settling in the caves of new land marked the chunks round
        // him changed several times a second, each went ahead of every waiting job as soon as its last one finished, and
        // the workers did nothing else: on his New World (4) spot no new chunk was made or drawn for 40 s
        // (questcheck --streamtest).
        if !dirtyChunks.isEmpty {
            let cap = World.frontAll ? Int.max : max(1, maxJobs / 2)
            // P458 (Oct 25 16:29-16:56 and 19:51, bases: "the blocks aren't getting updated"; a door "looks closed even
            // though it's open... takes like five seconds"; "explosion pits need to render quicker"): a chunk round him
            // whose last job went to the back of the queue (the quiet pass, the scan) waited for it there, behind a full
            // queue of far land, before anything changed since could be drawn: what soldiers, blasts and falling pieces
            // changed round him showed up to 10 s late (questcheck --basecheck, the headset's settings). One within two
            // chunks of him gets a job ahead of the queue as well; the older one's mesh is dropped when it comes.
            for c in dirtyChunks where c.dirty && (c.urgent || World.frontAll) && c.meshedOnce && c.needsMesh
                && abs(c.cx - center.x) <= 6 && abs(c.cz - center.z) <= 6
                && (!c.meshInFlight || (c.meshJobsOut < 2 && abs(c.cx - center.x) <= 2 && abs(c.cz - center.z) <= 2 && !frontOut.contains(ChunkKey(x: c.cx, z: c.cz)))) {
                if frontOut.count >= cap { break }
                let k = ChunkKey(x: c.cx, z: c.cz)
                guard chunks[k] === c, let nb = neighbourhood(c) else { continue }
                c.dirty = false
                frontOut.insert(k)
                scheduleMesh(k, c, nb, front: true)
            }
        }

        // P474: settling changes held back long enough mesh now (marked dirty again: the quiet pass looks at them).
        let now = CFAbsoluteTimeGetCurrent()
        if !held.isEmpty && now - heldCheck > 0.05 {
            heldCheck = now
            var released = false
            func near(_ c: Chunk) -> Bool { max(abs(c.cx - center.x), abs(c.cz - center.z)) <= 2 }
            let nearGap = settleNearGap
            held.removeAll { c in
                guard now - c.meshAt >= nearGap && (now - c.meshAt >= World.settleGap || near(c)) else { return false }
                c.held = false
                if chunks[ChunkKey(x: c.cx, z: c.cz)] === c && c.needsMesh { c.dirty = true; released = true }
                return true
            }
            if released { scanEpoch &-= 1 }
        }

        // Nothing new since the last scan (same centre, no results, no invalidated sections): the scan
        // would schedule nothing, so skip it (it walks ~1000-2000 chunks at rd 16-24).
        let quiet = gr.isEmpty && mr.isEmpty && center == scanCenter && extra == scanExtra
        if quiet && MeshEpoch.value == scanEpoch { return }
        if quiet {
            // Only block or light edits since the last scan (flowing water, a placed block): re-check just the chunks
            // they touched instead of walking the whole disc (bench: 0.26 ms a frame at rd 16 while lava settled).
            // Only the chunks marked dirty since (dirtyChunks), not every loaded chunk.
            var list = dirtyChunks
            dirtyChunks = []
            var i = 0
            while i < list.count {
                let c = list[i]
                guard c.dirty else { i += 1; continue }
                let k = ChunkKey(x: c.cx, z: c.cz)
                guard chunks[k] === c else { c.dirty = false; i += 1; continue }   // unloaded since
                if jobs >= maxQueued {
                    // The rest stay dirty and listed; the epoch still differs, so next frame.
                    dirtyChunks.insert(contentsOf: list[i...], at: 0)
                    return
                }
                i += 1
                c.dirty = false
                guard !c.meshInFlight && c.needsMesh && !holdBack(c, k.x - center.x, k.z - center.z, now) else { continue }
                let near = inMeshRadius(k.x - center.x, k.z - center.z) || (extra.map { inMeshRadius(k.x - $0.x, k.z - $0.z) } ?? false)
                if near, let nb = neighbourhood(c) { scheduleMesh(k, c, nb, front: abs(k.x - center.x) <= 2 && abs(k.z - center.z) <= 2) }   // (P458)
            }
            list.removeAll()
            scanEpoch = MeshEpoch.value
            return
        }
        // Same centres as the last scan: no chunk's LOD can have changed, so once the job queue is full the rest of
        // the walk can't schedule anything (it walked ~1000-2000 offsets a frame while chunks streamed in at rd 16-24).
        let sameCentres = center == scanCenter && extra == scanExtra
        scanCenter = center
        scanExtra = extra

        // Nearest-first scheduling: generate missing chunks, mesh chunks whose 8 neighbours exist (round each centre).
        var meshed = 0
        var cutShort = false
        let centres: [ChunkKey] = extra.map { [center, $0] } ?? [center]
        scan: for (dx, dz, _) in orderedScan() {
        if sameCentres && jobs >= maxQueued { cutShort = true; break scan }
        for (ci, cen) in centres.enumerated() {
            let k = ChunkKey(x: cen.x + dx, z: cen.z + dz)
            if let c = chunks[k] {
                if c.meshedOnce && ci == 0 { meshed += 1 }
                let (ox, oz) = ci == 0 && extra == nil ? (dx, dz) : nearOff(k)
                let wantLod = lodFor(ox, oz, current: c.lod)
                if wantLod != c.lod && !c.meshInFlight { setLod(c, wantLod) }
                if jobs >= maxQueued { continue }
                if !c.meshInFlight && inMeshRadius(dx, dz) && c.needsMesh && !holdBack(c, ox, oz, now), let nb = neighbourhood(c) {
                    c.dirty = false
                    scheduleMesh(k, c, nb, front: ci == 0 && abs(dx) <= 2 && abs(dz) <= 2 && c.meshedOnce)          // (P458)
                }
            } else if jobs < maxQueued && !genInFlight.contains(k) {
                // P376: inside the view past the active distance, a chunk with cached meshes comes back as a shell.
                let (ox, oz) = ci == 0 && extra == nil ? (dx, dz) : nearOff(k)
                startGen(k, shell: World.shells && inShellBand(ox, oz) && (meshCache?.has(k) ?? false))
            }
        }
        }
        if !cutShort { meshedCount = meshed }   // (F3 only: a cut-short walk keeps the last full count)
        scanEpoch = MeshEpoch.value         // after the loop: its own LOD re-mesh bumps are already scheduled
        // The full scan handled what it could; keep only chunks still dirty and loaded listed (bounded by the chunk count,
        // and no unloaded chunk kept alive by the list).
        if !dirtyChunks.isEmpty {
            dirtyChunks.removeAll { c in !c.dirty || chunks[ChunkKey(x: c.cx, z: c.cz)] !== c }
        }
    }

    // P440: the buried sections of a far chunk are left unmeshed (an empty mesh, closed to the cave-culling walk);
    // the others are returned to mesh.
    private func deferringBuried(_ c: Chunk, _ todo: [(Int, Int)]) -> [(Int, Int)] {
        if dim == .deep { return deferringDeepLayer(c, todo) }
        guard World.deferBuried && fieldTerrain && dim != .deep else { return todo }
        let k = ChunkKey(x: c.cx, z: c.cz)
        if nearBuried(k) { return todo }
        let low = buriedLow(c)
        guard low > 16 else { return todo }
        var keep: [(Int, Int)] = []
        keep.reserveCapacity(todo.count)
        for (sy, v) in todo {
            if (sy + 1) * 16 <= low { deferSection(c, sy) } else { keep.append((sy, v)) }
        }
        return keep
    }

    // The lowest ground top over a chunk and its eight neighbours (an unloaded neighbour: the chunk's own).
    private func buriedLow(_ c: Chunk) -> Int {
        var low = c.groundLow
        for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 {
            if let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)], !n.hollow { low = min(low, n.groundLow) }
        } }
        return low
    }

    private func nearBuried(_ k: ChunkKey) -> Bool {
        let r = underground ? World.buriedNearUnder : flyingHigh ? (flyingFast ? -1 : World.buriedNearHigh) : World.buriedNear
        guard let c0 = buriedCentre else { return true }
        if max(abs(k.x - c0.x), abs(k.z - c0.z)) <= r { return true }
        if let e = buriedExtra, max(abs(k.x - e.x), abs(k.z - e.z)) <= r { return true }
        return false
    }

    private func deferSection(_ c: Chunk, _ sy: Int) {
        let s = c.sections[sy]
        var m = SectionMesh(opaque: [], trans: [], light: nil)
        m.vis = 0
        apply(m, to: c, sy: sy, version: s.version)
        if !s.deferred { s.deferred = true; c.deferredBuried += 1; deferredTotal += 1 }
    }

    // P440: ground taken out under the lowest surface opens the buried sections round it (World.setBlock,
    // setBlockAsync, fieldSphere). Store media (Oct 31): a Tidebreaker crater 60 blocks off stayed a hole to the sky
    // for good: a crater takes its cells out through setBlockAsync and its bowl through fieldSphere, which never
    // lowered the chunk's lowest ground, so the rock it laid open was taken for buried and its sections stayed unmeshed.
    func groundOpened(_ c: Chunk, _ y: Int) {
        guard y - 1 < c.groundLow else { return }
        c.lowerGround(to: y - 1)
        for dz in -1...1 { for dx in -1...1 { if let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)] { undeferBuried(n) } } }
    }

    // P504: the Deep's other layer (the Ash Vault under the Sealrock while he is in the Hell, the hell band over it while
    // he is in the Vault): a section wholly on the far side of the Sealrock (y 192-199) and the hell band's first cells.
    @inline(__always) static func deepOther(_ sy: Int, hell: Bool) -> Bool {
        hell ? (sy + 1) * 16 <= DeepGen.hellBase - 8 : sy * 16 >= DeepGen.hellBase + 8
    }

    private func deferringDeepLayer(_ c: Chunk, _ todo: [(Int, Int)]) -> [(Int, Int)] {
        guard World.deepLayerCut, let hell = deepInHell, let c0 = deepCentre else { return todo }
        if max(abs(c.cx - c0.x), abs(c.cz - c0.z)) <= 1 { return todo }
        var keep: [(Int, Int)] = []
        keep.reserveCapacity(todo.count)
        for (sy, v) in todo {
            if World.deepOther(sy, hell: hell) { deferSection(c, sy) } else { keep.append((sy, v)) }
        }
        return keep
    }

    // Each frame in the Deep: which layer he is in. Crossing over gives the deferred sections back and drops the meshes
    // of the layer he left; a new centre gives the nine chunks round him theirs.
    private func deepLayerTick(_ pos: V3, _ center: ChunkKey) {
        guard World.deepLayerCut else { deepInHell = nil; return }
        let hell = pos.y >= Float(DeepGen.hellBase - 8)
        if hell != deepInHell {
            deepInHell = hell; deepCentre = center
            for (k, c) in chunks where !c.hollow {
                undeferBuried(c)
                guard max(abs(k.x - center.x), abs(k.z - center.z)) > 1, c.meshedOnce, !c.meshInFlight else { continue }
                for sy in 0..<NSEC where World.deepOther(sy, hell: hell) && !c.sections[sy].deferred && !c.sections[sy].needsMesh
                    && c.sections[sy].meshedVersion >= 0 { deferSection(c, sy) }
            }
        } else if center != deepCentre {
            deepCentre = center
            for dz in -1...1 { for dx in -1...1 { if let c = chunks[ChunkKey(x: center.x + dx, z: center.z + dz)] { undeferBuried(c) } } }
        }
    }

    // A chunk's deferred sections mesh again (he came near, went underground, or the ground under them was opened).
    private func undeferBuried(_ c: Chunk) {
        guard c.deferredBuried > 0 else { return }
        // (P446: in the queue's order, not ahead of it: new land's surface comes before the rock under the land he nears.
        // A dig under the lowest surface undefers too; the dig's own edit marks its sections for the edit lane.)
        let was = World.backgroundEdits
        World.backgroundEdits = true
        defer { World.backgroundEdits = was }
        for s in c.sections where s.deferred { s.deferred = false; s.version += 1 }
        c.deferredBuried = 0
    }

    // Each frame: where the player is (above ground or under it) and, when that or his chunk changed, the near chunks'
    // deferred sections handed back to meshing, and the far chunks' buried meshes dropped (they cost the GPU too).
    private func buriedTick(_ pos: V3, _ center: ChunkKey, _ extra: ChunkKey?) {
        if dim == .deep { buriedCentre = nil; deepLayerTick(pos, center); return }
        guard World.deferBuried && fieldTerrain else { buriedCentre = nil; return }
        var under = false, high = flyingHigh
        // The top of the drawn ground in a column (nil: its chunk isn't loaded, or is a shell).
        func groundTop(_ x: Int, _ z: Int) -> Int? {
            guard let c = chunkAt(x, z), !c.hollow else { return nil }
            let col = mod(x, CS) + mod(z, CS) * CS
            var y = min(min(CH, c.blocks.storedCount / CSQ) - 1, Int(c.height[col]))
            while y > 0 && !c.blocks.ground(col + y * CSQ) { y -= 1 }
            return y
        }
        let px = Int(floor(pos.x)), pz = Int(floor(pos.z))
        if let y = groundTop(px, pz) {
            under = Float(y) > pos.y + 2.5             // ground over his head: in a cave, a mine
            // P484 (Oct 28 17:50, mining at -32 in survival: "Still got holes in the environment"): a shaft he dug down
            // (or fell down) is open to the sky over his own column, so he counted as above ground and only the three
            // chunks round him drew their caves and rock: the caves he broke into past 48 blocks were holes. Ground over
            // his head 3 blocks off on two sides of the four counts as under it too.
            if !under && World.shaftUnder {
                var covered = 0
                for (dx, dz) in [(3, 0), (-3, 0), (0, 3), (0, -3)] {
                    if let t = groundTop(px + dx, pz + dz), Float(t) > pos.y + 2.5 { covered += 1 }
                }
                under = covered >= 2
            }
            high = !under && pos.y - Float(y) > (flyingHigh ? 12 : 24)       // (P446)
        }
        let fast = World.highFastNone && simd_length_squared(V2(lead.x, lead.z)) > World.settleFast * World.settleFast
        guard center != buriedCentre || extra != buriedExtra || under != underground || high != flyingHigh || fast != flyingFast else { return }
        let wasUnder = underground
        underground = under; flyingHigh = high; flyingFast = fast; buriedCentre = center; buriedExtra = extra
        let r = under ? World.buriedNearUnder : high ? (fast ? -1 : World.buriedNearHigh) : World.buriedNear
        let rKeep = under ? World.buriedNearUnder : World.buriedNear       // (flying high doesn't give meshes back)
        for (k, c) in chunks where !c.hollow {
            let d = min(max(abs(k.x - center.x), abs(k.z - center.z)), extra.map { max(abs(k.x - $0.x), abs(k.z - $0.z)) } ?? Int.max)
            if d <= r { undeferBuried(c); continue }
            // Past the ring by two (not see-sawing at its edge), and only when the ring didn't just grow: buried
            // sections meshed while he was near give their meshes back.
            if d > rKeep + 1 && !wasUnder && !under && c.meshedOnce && !c.meshInFlight {
                let low = buriedLow(c)
                guard low > 16 else { continue }
                for sy in 0..<min(NSEC, low / 16) where !c.sections[sy].deferred && !c.sections[sy].needsMesh && c.sections[sy].meshedVersion >= 0 {
                    deferSection(c, sy)
                }
            }
        }
    }

    // Hands a chunk's out-of-date sections to a mesh worker.
    private func scheduleMesh(_ k: ChunkKey, _ c: Chunk, _ nb: ([BlockStore], [[Int16]]), front: Bool = false) {
        let (n9, h9) = nb
        let why = !c.meshedOnce ? "new" : (c.urgent ? "edit" : (c.lodRemeshLog ? "lod" : "settle"))
        c.lodRemeshLog = false
        let dist = max(abs(k.x - floorDiv(Int(floor(activeCenter.x)), CS)), abs(k.z - floorDiv(Int(floor(activeCenter.z)), CS)))
        let lowSec = c.groundLow >> 4
        c.urgent = false
        c.meshAt = CFAbsoluteTimeGetCurrent()
        let todo = deferringBuried(c, dirtySections(c))
        if todo.isEmpty { return }
        let lod = c.lod
        let dl = damageList(c), bl = biteList(c), pl = pieceList(c), ol = objectReg.draws(c)
        let site = smoothSite(c)
        let near = nearSides(c, lod: lod), beyond = fineBeyond(c, n9)
        func enqueue(_ list: [(Int, Int)], front: Bool) {
            c.meshInFlight = true
            c.meshJobsOut += 1
            jobs += 1
            // Weak: a finished operation can linger in a worker's autorelease pool and would keep the World alive.
            let job: () -> Void = { [weak self] in
                guard let self else { return }
                let t0 = CFAbsoluteTimeGetCurrent()
                var out: [(Int, Int, SectionMesh)] = []
                for (sy, v) in list { out.append((sy, v, Mesher.buildSection(n9, h9, sy: sy, lod: lod, damage: dl, bites: bl, pieces: pl, objects: ol, site: site, chunk: (k.x, k.z), nearSides: near, fineBeyond: beyond))) }
                let el = CFAbsoluteTimeGetCurrent() - t0
                if World.meshLog { print(String(format: "meshlog: %@ d%d lod%d low%d secs %@ %.1f ms", why, dist, lod, lowSec, list.map { String($0.0) }.joined(separator: ","), el * 1000)) }
                self.lock.lock()
                self.meshResults.append((k, out))
                self.perfShared.meshJobs += 1; self.perfShared.meshSections += list.count; self.perfShared.meshSeconds += el
                self.lock.unlock()
            }
            if front { workQueue.addFront(job) } else { workQueue.add(job) }
        }
        // P404 (3) (Oct 22 22:23, under the ground: "looks like the chunk's having trouble loading... we're underground,
        // this should be easy"): under the ground, a chunk round him meshes the sections at his level first, in a job
        // ahead of the queue, and the rest of its column after. Its whole column was one job in distance order with
        // every other chunk's, so the cave he stood in waited behind the surface and everything between.
        if underground, let c0 = buriedCentre, todo.count > 3, abs(k.x - c0.x) <= 2 && abs(k.z - c0.z) <= 2 {
            let band = todo.filter { abs($0.0 - eyeSection) <= 1 }
            if !band.isEmpty && band.count < todo.count {
                enqueue(band, front: true)
                enqueue(todo.filter { abs($0.0 - eyeSection) > 1 }, front: front)
                return
            }
        }
        enqueue(todo, front: front)
    }

    // Loads a chunk from disk or generates it (thread-safe).
    struct Produced {
        var blocks: [BlockID]
        var height: [Int16]
        var tint: [UInt32]
        var fromDisk: Bool
        var entities: [(IVec3, BlockEntity)]
        var mobs: [(String, V3)]
        var tracked: [IVec3] = []            // circuit components needing periodic work (found off the main thread)
        var emitMask: UInt32 = ~0            // sections holding light emitters (BlockStore.emitMask)
        var springs: [IVec3] = []            // fluid cells open to air (World.springs: flow once loaded)
        var field: [Int32: UInt16] = [:]     // PG1: saved terrain field edits (TerrainField.swift)
        var ground: FieldData? = nil         // PG1 rewrite: the chunk's density field (field worlds, FieldTerrain.swift)
        var cached: MeshCache.Entry? = nil   // P376: a shell's meshes read from the disk cache (ChunkShells)
    }

    // Fluid cells beside or over air: scheduled for a fluid update on install so underground sources spill into caves
    // as waterfalls (reference: aquifer fluid ticks on generation) instead of standing as a wall of water until something
    // touches them (gencheck leak, about 200 per 288 chunks). Since Quest v63 ("sometimes water doesn't flow") also saved
    // chunks, flowing cells, and up to just above the surface: a flow cut off by saving mid-spread, or generated water on
    // a ledge beside open air, stood still. Settled cells just tick once. Chunk interior only; at most 96 per chunk.
    static func springs(_ b: [BlockID], _ k: ChunkKey, _ h: [Int16]) -> [IVec3] {
        var out: [IVec3] = []
        var lavaN = 0, waterN = 0
        let fk = Blocks.fluidKind
        for c in 0..<CSQ {
            let lx = c & 15, lz = c >> 4
            let top = min(CH - 1, Int(h[c]) + 2)
            guard top > 2 else { continue }
            for y in 2..<top {
                let i = c + y * CSQ
                let kind = fk[Int(b[i])]
                guard kind != 0 else { continue }                          // lava pools spill into caves as lavafalls too
                // Water and lava each get 96: shore water filled the cap before a cave's lava was reached (P18).
                if kind == 2 ? lavaN >= 96 : waterN >= 96 { continue }
                let open = b[i - CSQ] == AIR || (lx > 0 && b[i - 1] == AIR) || (lx < 15 && b[i + 1] == AIR)
                    || (lz > 0 && b[i - CS] == AIR) || (lz < 15 && b[i + CS] == AIR)
                if open {
                    out.append(IVec3(k.x * CS + lx, y, k.z * CS + lz))
                    if kind == 2 { lavaN += 1 } else { waterN += 1 }
                    if lavaN >= 96 && waterN >= 96 { return out }
                }
            }
        }
        return out
    }

    // Fluid on one side of a chunk border with air on the other (World.springs sees one chunk's interior only): lava at
    // a chunk's edge facing a cave in the next chunk stood still for good (Oct 11 playtest P18 at 12:42: "lava that should
    // be spilling into me, but isn't"). Checked as each chunk joins its loaded neighbours, up to the taller column + 2.
    func borderSprings(_ c: Chunk) {
        let fk = Blocks.fluidKind
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            guard let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)] else { continue }
            for i in 0..<CS {
                // The facing columns: c's edge (lx, lz) and n's (nx, nz).
                let lx = dx == 1 ? 15 : (dx == -1 ? 0 : i), lz = dz == 1 ? 15 : (dz == -1 ? 0 : i)
                let nx = dx == 0 ? lx : 15 - lx, nz = dz == 0 ? lz : 15 - lz
                let top = min(CH - 1, max(Int(c.height[lx + lz * CS]), Int(n.height[nx + nz * CS])) + 2)
                guard top > 1 else { continue }
                for y in 1...top {
                    // (The built layer, and the field's ground as a filled cell: P377 step 2.)
                    let ia = Chunk.index(lx, y, lz), ib = Chunk.index(nx, y, nz)
                    let a = c.blocks.raw(ia), b = n.blocks.raw(ib)
                    let fa = fk[Int(a)], fb = fk[Int(b)]
                    guard fa != fb else { continue }
                    let openA = a == AIR && !c.blocks.ground(ia), openB = b == AIR && !n.blocks.ground(ib)
                    // P412 (d) (Oct 22 22:22, "lava and water crossing over... should turn into obsidian"): the generator
                    // hardens lava beside water inside a chunk (WorldGen.hardenLava); across a chunk border nothing did,
                    // so a lava lake and an aquifer meeting at the border stayed as they were. The same rule here.
                    if fa + fb == 3 {
                        let lavaInC = fa == 2
                        let q = lavaInC ? IVec3(c.cx * CS + lx, y, c.cz * CS + lz) : IVec3(n.cx * CS + nx, y, n.cz * CS + nz)
                        let lv = Blocks.fluidLevel[Int(lavaInC ? a : b)]
                        if setBlockAsync(q.x, q.y, q.z, lv == 0 ? OBSIDIAN : COBBLE) { scheduleFluid(around: q) }
                        continue
                    }
                    if fa != 0 && openB {
                        let q = IVec3(c.cx * CS + lx, y, c.cz * CS + lz)
                        if fa == 2 { lavaPending.insert(q) } else { fluidPending.insert(q) }
                    } else if fb != 0 && openA {
                        let q = IVec3(n.cx * CS + nx, y, n.cz * CS + nz)
                        if fb == 2 { lavaPending.insert(q) } else { fluidPending.insert(q) }
                    }
                }
            }
        }
    }

    // A worker generates (or loads) chunk k; with `shell`, reads its cached meshes instead (ChunkShells).
    // (P400 harness: the slowest single result handed over, and what it was)
    static var resultsProfile = false, resultsWorstMs = 0.0, resultsWorst = ""
    // (questcheck --streamtest: frame time spent handing results over, how many, and how many were left for later)
    static var handoverSpent = 0.0, handedOver = 0, leftWaiting = 0
    @inline(__always) static func noteResult(_ t0: Double, _ what: String) {
        guard resultsProfile else { return }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        if ms > resultsWorstMs { resultsWorstMs = ms; resultsWorst = what + String(format: " (slabs %d MB)", MeshArena.shared.slabBytes >> 20) }
    }

    func startGen(_ k: ChunkKey, shell: Bool = false, urgent: Bool = false) {
        guard !genInFlight.contains(k) else { return }
        genInFlight.insert(k)
        jobs += 1
        let mc = shell ? meshCache : nil
        let job: () -> Void = { [weak self] in
            guard let self else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            var r: Produced
            if let e = mc?.read(k) { r = Produced(blocks: [], height: [], tint: [], fromDisk: false, entities: [], mobs: []); r.cached = e }
            else { r = self.produce(k) }
            let el = CFAbsoluteTimeGetCurrent() - t0
            self.lock.lock()
            self.genResults.append((k, r))
            self.perfShared.genChunks += 1; self.perfShared.genSeconds += el
            self.lock.unlock()
        }
        if urgent { workQueue.addFront(job) } else { workQueue.add(job) }
    }
    func produceNow(_ k: ChunkKey) -> Produced { produce(k) }

    private func produce(_ k: ChunkKey) -> Produced {
        var fromDisk = false
        var blocks: [BlockID]
        var ents: [(IVec3, BlockEntity)] = []
        var mobs: [(String, V3)] = []
        var ground: FieldData? = nil
        if let saved = save?.loadChunk(k) {
            blocks = saved; fromDisk = true
            TreeRepair.tidy(&blocks)                                // P447: old second stems and kinks
            // PG1: the saved built layer and the saved ground. A lost ground file comes back from the seed under the saved
            // built layer (what was dug stays dug only where something was built there since).
            if fieldTerrain { ground = save?.loadField(k) ?? gen.generateField(cx: k.x, cz: k.z).ground }
            // P326 (e): a vault chunk saved before the Ash Vault's redesign takes the new ground's materials.
            if let dg = gen as? DeepGen, !dg.ground.guardSet.chunks.isEmpty, dg.ground.guardSet.chunks.contains(StructureCache.key(k.x, k.z)) {
                dg.ground.migrate(&blocks, &ground, cx: k.x, cz: k.z)
            }
        } else if fieldTerrain {
            // PG1: the generator makes the chunk as a field: the ground's density field, and what is built on and in it.
            let fc = gen.generateField(cx: k.x, cz: k.z)
            blocks = fc.built; ground = fc.ground; ents = fc.entities; mobs = fc.mobs
        } else {
            blocks = gen.generate(cx: k.x, cz: k.z)
            if let st = gen.structures { (ents, mobs) = st.place(into: &blocks, cx: k.x, cz: k.z) }
            WorldGen.settleGrass(&blocks)                   // (P474)
            ents += World.orphanEntities(blocks, k, have: ents)
        }
        let field = fromDisk && keepsField ? save?.loadFieldEdits(k) ?? [:] : [:]
        if let g = ground {
            // A field chunk: heights, springs and light emitters from the merged cells.
            var merged = blocks
            FieldTerrain.merge(&merged, g)
            let heights = Chunk.computeHeights(merged)
            return Produced(blocks: blocks, height: heights, tint: gen.tints(cx: k.x, cz: k.z),
                            fromDisk: fromDisk, entities: ents, mobs: mobs, tracked: Circuit.trackedCells(blocks, cx: k.x, cz: k.z),
                            emitMask: BlockStore.emitMask(of: merged), springs: World.springs(merged, k, heights), field: field,
                            ground: g)
        }
        _ = PlantSupport.dropFloating(&blocks)
        let heights = Chunk.computeHeights(blocks)
        let springs = World.springs(blocks, k, heights)
        let tracked = Circuit.trackedCells(blocks, cx: k.x, cz: k.z)
        if fieldTerrain {
            // PG1: the host's chunk (a co-op guest of a field world) becomes the field and the built layer.
            let merged = blocks
            let f = FieldTerrain.split(&blocks, cx: k.x, cz: k.z, gen: gen)
            return Produced(blocks: blocks, height: heights, tint: gen.tints(cx: k.x, cz: k.z),
                            fromDisk: fromDisk, entities: ents, mobs: mobs, tracked: tracked,
                            emitMask: BlockStore.emitMask(of: merged), springs: springs, field: field, ground: f)
        }
        return Produced(blocks: blocks, height: heights, tint: gen.tints(cx: k.x, cz: k.z),
                        fromDisk: fromDisk, entities: ents, mobs: mobs, tracked: tracked,
                        emitMask: BlockStore.emitMask(of: blocks), springs: springs, field: field)
    }

    // Generated spawners/chests without a block entity (dungeons): mob and loot come from the position.
    static func orphanEntities(_ blocks: [BlockID], _ k: ChunkKey, have: [(IVec3, BlockEntity)]) -> [(IVec3, BlockEntity)] {
        let spawner = Blocks.id("spawner"), chestBase = Blocks.id("chest")
        let known = Set(have.map { $0.0 })
        var out: [(IVec3, BlockEntity)] = []
        for i in 0..<blocks.count {
            let b = blocks[i]
            guard b == spawner || Blocks.groupBase[Int(b)] == chestBase else { continue }
            let x = i & 15, z = (i >> 4) & 15, y = i >> 8
            let p = IVec3(k.x * CS + x, y, k.z * CS + z)
            if known.contains(p) { continue }
            let h = hash3(p.x, p.y, p.z, 0xD06E)
            if b == spawner {
                let be = BlockEntity(.spawner)
                be.mob = ["zombie", "zombie", "skeleton", "spider"][Int(h % 4)]
                out.append((p, be))
            } else {
                let be = BlockEntity(.chest)
                var rng = SRng(UInt64(h) | 1)
                Loot.fill(be.container, table: "dungeon", rng: &rng)
                out.append((p, be))
            }
        }
        return out
    }

    private func install(_ k: ChunkKey, _ p: Produced) {
        if p.ground != nil { fieldStamp &+= 1 }              // (cached field collision at its border reads it now)
        let c = Chunk(cx: k.x, cz: k.z, blocks: p.blocks, height: p.height, tint: p.tint, field: p.ground)
        c.world = self
        c.blocks.emitMask = p.emitMask
        c.modified = p.fromDisk
        if p.fromDisk { c.markSaved() }
        c.fieldEdits = p.field
        if !p.fromDisk, let gd = p.ground { c.borderSeeds = gd.borderSeeds }     // P380 (2)
        chunks[k] = c
        GroundSettle.borderCheck(self, around: k)
        for t in p.tracked { redstone.tracked.insert(t) }
        // Lava springs go to the lava queue: the water tick skips lava, so generated lavafalls never started.
        for q in p.springs { if Blocks.fluidKind[Int(rawBlock(q.x, q.y, q.z))] == 2 { lavaPending.insert(q) } else { fluidPending.insert(q) } }
        borderSprings(c)
        // Generated chests/spawners; a regenerated chunk keeps any existing (already looted) entity.
        for (pos, be) in p.entities where blockEntities[pos] == nil { blockEntities[pos] = be }
        // Structure mobs (bastion boarlings...) appear once: the chunk is saved so it never regenerates.
        if !p.mobs.isEmpty {
            c.modified = true
            for (name, at) in p.mobs {
                // P458 (Oct 25 16:52, the Ash Vault: "A half truck on top of the base? How'd that get up there?"): a
                // vehicle whose spot was taken was lifted up to 4 blocks, onto the roof of the shed it was parked in;
                // vehicles look along the ground for room instead.
                let vehicle = ["ash_tank", "ash_halftrack", "ash_truck", "ash_artillery", "ash_behemoth"].contains { name.hasPrefix($0) }
                pendingMobs.append((name, freeSpawn(at, wide: name == "iron_golem" || name == "ravager", level: vehicle)))
            }
        }
    }

    // Blocking load of everything around a point (used by --snapshot and first spawn).
    func loadSync(center pos: V3, radius: Int) -> (gen: Double, mesh: Double) {
        let cx = floorDiv(Int(floor(pos.x)), CS), cz = floorDiv(Int(floor(pos.z)), CS)
        let r = radius + 1
        buriedCentre = ChunkKey(x: cx, z: cz); underground = false          // (P440: buriedTick decides on the next update)
        if dim == .deep && World.deepLayerCut { buriedCentre = nil; deepInHell = pos.y >= Float(DeepGen.hellBase - 8); deepCentre = ChunkKey(x: cx, z: cz) }
        var keys: [ChunkKey] = []
        for dz in -r...r { for dx in -r...r where World.inDisc(dx, dz, radius, grow: 1) {
            let k = ChunkKey(x: cx + dx, z: cz + dz)
            if chunks[k] == nil { keys.append(k) }
        } }
        let t0 = CFAbsoluteTimeGetCurrent()
        let res = UnsafeMutablePointer<Produced>.allocate(capacity: max(1, keys.count))
        defer { res.deallocate() }
        DispatchQueue.concurrentPerform(iterations: keys.count) { i in
            (res + i).initialize(to: produce(keys[i]))
        }
        for (i, k) in keys.enumerated() {
            install(k, (res + i).move())
        }
        let t1 = CFAbsoluteTimeGetCurrent()

        var toMesh: [(Chunk, Int, Int, [BlockStore], [[Int16]])] = []
        for dz in -radius...radius { for dx in -radius...radius where World.inDisc(dx, dz, radius, grow: 0) && inMeshRadius(dx, dz) {
            if let c = chunks[ChunkKey(x: cx + dx, z: cz + dz)], c.needsMesh, let nb = neighbourhood(c) {
                c.lod = lodFor(dx, dz)
                for (sy, v) in deferringBuried(c, dirtySections(c)) { toMesh.append((c, sy, v, nb.0, nb.1)) }
            }
        } }
        let dls = toMesh.map { damageList($0.0) }, bls = toMesh.map { biteList($0.0) }, pls = toMesh.map { pieceList($0.0) }
        let ols = toMesh.map { objectReg.draws($0.0) }
        let sites = toMesh.map { smoothSite($0.0) }
        let nears = toMesh.map { nearSides($0.0, lod: $0.0.lod) }          // (every chunk's level is set by now)
        let beyonds = toMesh.map { fineBeyond($0.0, $0.3) }
        let meshes = UnsafeMutablePointer<SectionMesh>.allocate(capacity: max(1, toMesh.count))
        defer { meshes.deallocate() }
        DispatchQueue.concurrentPerform(iterations: toMesh.count) { i in
            let t = toMesh[i]
            (meshes + i).initialize(to: Mesher.buildSection(t.3, t.4, sy: t.1, lod: t.0.lod, damage: dls[i], bites: bls[i], pieces: pls[i], objects: ols[i], site: sites[i],
                                                            chunk: (t.0.cx, t.0.cz), nearSides: nears[i], fineBeyond: beyonds[i]))
        }
        for (i, t) in toMesh.enumerated() {
            apply((meshes + i).move(), to: t.0, sy: t.1, version: t.2)
            t.0.meshedOnce = true
        }
        let t2 = CFAbsoluteTimeGetCurrent()
        return (t1 - t0, t2 - t1)
    }

    // A structure mob placed inside a wall, floor or furniture (structcheck mob_in_block) moves to the nearest
    // cell where a two-block body fits: straight up first, then one and two blocks around.
    // wide: a body over a block across (iron golems, siegebeasts) stands on a cell corner with all four cells round it
    // clear (a golem placed in a one-block gap between a house and the bank stood in both walls: behaviour sim, run 377).
    func freeSpawn(_ p: V3, wide: Bool = false, level: Bool = false) -> V3 {
        func clear(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            for k in 0...1 {
                if groundAt(x, y + k, z) { return false }                // (P377 step 2: the ground by its field)
                let b = Int(builtBlock(x, y + k, z))
                if Blocks.collide[b] && (Blocks.fullCollide[b] || !Blocks.boxes[b].isEmpty) {
                    var top: Float = 0
                    for bx in Blocks.boxes[b] { top = max(top, bx.maxV.y) }
                    if Blocks.fullCollide[b] || top > (k == 0 ? 0.2 : 0.01) { return false }
                }
            }
            return true
        }
        let x = Int(floor(p.x)), y = Int(floor(p.y + 0.01)), z = Int(floor(p.z))
        if wide {
            func clear4(_ cx: Int, _ cy: Int, _ cz: Int) -> Bool {
                clear(cx - 1, cy, cz - 1) && clear(cx, cy, cz - 1) && clear(cx - 1, cy, cz) && clear(cx, cy, cz)
                    && solidAt(cx - 1, cy - 1, cz - 1) && solidAt(cx, cy - 1, cz)
            }
            let rx = Int((p.x).rounded()), rz = Int((p.z).rounded())
            for r in 0...3 { for dy in [0, 1, -1, 2] { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                if clear4(rx + dx, y + dy, rz + dz) { return V3(Float(rx + dx), Float(y + dy), Float(rz + dz)) }
            } } } }
            return p
        }
        if clear(x, y, z) { return p }
        if level {
            for r in 1...8 { for dy in [0, 1, -1] { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                let fx = x + dx, fy = y + dy, fz = z + dz
                if clear(fx, fy, fz) && solidAt(fx, fy - 1, fz) { return V3(Float(fx) + 0.5, Float(fy), Float(fz) + 0.5) }
            } } } }
            return p
        }
        for dy in 1...4 where clear(x, y + dy, z) { return V3(p.x, Float(y + dy), p.z) }
        for r in 1...2 { for dy in -1...2 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
            let fx = x + dx, fy = y + dy, fz = z + dz
            if clear(fx, fy, fz) && solidAt(fx, fy - 1, fz) { return V3(Float(fx) + 0.5, Float(fy), Float(fz) + 0.5) }
        } } } }
        return p
    }

    // Generates and installs every chunk of a rectangle (chunk coordinates, inclusive) without meshing: the
    // structure, world-gen and bot checkers only need blocks.
    func loadBlocks(cx0: Int, cz0: Int, cx1: Int, cz1: Int) {
        var keys: [ChunkKey] = []
        for cz in cz0...cz1 { for cx in cx0...cx1 {
            let k = ChunkKey(x: cx, z: cz)
            if chunks[k] == nil { keys.append(k) }
        } }
        guard !keys.isEmpty else { return }
        let res = UnsafeMutablePointer<Produced>.allocate(capacity: keys.count)
        defer { res.deallocate() }
        DispatchQueue.concurrentPerform(iterations: keys.count) { i in
            (res + i).initialize(to: produce(keys[i]))
        }
        for (i, k) in keys.enumerated() { install(k, (res + i).move()) }
    }

    // Drops every chunk (after saving) — used when leaving a dimension.
    func unloadAll() {
        chunks.removeAll()
        lastCenter = nil
        fluidPending.removeAll(); lavaPending.removeAll()
    }

    var savingFalling: [(IVec3, BlockID)] = []       // (P395: Game.saveNow's falling blocks, for saveAll)
    func saveAll(background: Bool = false) {
        // Only chunks changed since their last save, written on the background save queue.
        // P395: blocks falling as entities (Game.falling) are saved in the cell each has reached; a save taken mid-fall
        // lost them (the cell they left was saved empty, and the entity isn't kept). The live chunk keeps them falling,
        // and stays unsaved so the next save writes where they land.
        var ghosts: [ChunkKey: [(Int, BlockID)]] = [:]
        for (p, b) in savingFalling where p.y >= 0 && p.y < CH && block(p.x, p.y, p.z) == AIR {
            ghosts[ChunkKey(x: floorDiv(p.x, CS), z: floorDiv(p.z, CS)), default: []].append((Chunk.index(mod(p.x, CS), p.y, mod(p.z, CS)), b))
        }
        for (k, c) in chunks where c.needsSave || ghosts[k] != nil && !c.hollow {
            if let gs = ghosts[k], !c.hollow {
                var b = c.blocks
                for (i, id) in gs { b[i] = id }
                save?.saveChunkAsync(k, b)
                continue
            }
            save?.saveChunkAsync(k, c.blocks)
            c.markSaved()
        }
        for (k, c) in chunks where c.fieldDirty { save?.saveFieldEdits(k, c.fieldEdits); c.fieldDirty = false }   // PG1
        savePieces()
        saveObjects()                                    // P389
        Trains.save(self)                                // P337 step 6
        save?.saveBlockEntities(blockEntities, background: background)
        redstone.save(background: background)            // W1: pending circuit ticks and edges (circuit.json)
        save?.savePortals(Array(portals))
        ships.save(background: background)
        saveMeshCache()                                  // P400 step 2 (ChunkShells)
    }

    // MARK: Raycast (voxel DDA + per-box tests for partial blocks)

    // Selection boxes (block-local, 0...1) of a block.
    func selectionBoxes(_ b: BlockID) -> [(V3, V3)] {
        let r = Blocks.render[Int(b)]
        if r == RenderType.cross.rawValue { return [(V3(0.125, 0, 0.125), V3(0.875, 0.8125, 0.875))] }
        // (P448, Oct 25 08:53: copper wire "is treating other copper blocks already placed as a block": wire and rails
        // were aimed at as full cubes, so a wire on the ground caught the look a block above it)
        if (r == RenderType.model.rawValue || r == RenderType.wire.rawValue || r == RenderType.rail.rawValue) && !Blocks.boxes[Int(b)].isEmpty {
            return Blocks.boxes[Int(b)].map { ($0.minV, $0.maxV) }
        }
        if r == RenderType.connect.rawValue {
            let ck = Blocks.connectKind[Int(b)]
            let bx = BlockRegistry.connectBoxes(ck, n: false, s: false, w: false, e: false, collision: false)
            return bx.map { ($0.minV, $0.maxV) }
        }
        return [(V3(0, 0, 0), V3(1, 1, 1))]
    }

    // Ray vs AABB: entry distance and the entry face normal.
    static func rayBox(_ o: V3, _ d: V3, _ mn: V3, _ mx: V3) -> (Float, IVec3)? {
        var t0: Float = -.greatestFiniteMagnitude, t1: Float = .greatestFiniteMagnitude
        var n = IVec3(0, 0, 0)
        for a in 0..<3 {
            if abs(d[a]) < 1e-9 {
                if o[a] < mn[a] || o[a] > mx[a] { return nil }
                continue
            }
            var ta = (mn[a] - o[a]) / d[a], tb = (mx[a] - o[a]) / d[a]
            var sign = -1
            if ta > tb { swap(&ta, &tb); sign = 1 }
            if ta > t0 {
                t0 = ta
                n = IVec3(a == 0 ? sign : 0, a == 1 ? sign : 0, a == 2 ? sign : 0)
            }
            t1 = min(t1, tb)
            if t0 > t1 { return nil }
        }
        if t1 < 0 { return nil }
        return (max(0, t0), n)
    }

    // Line of sight between two points (only full opaque blocks block it).
    func canSee(_ a: V3, _ b: V3) -> Bool {
        let d = b - a
        let len = simd_length(d)
        if len < 0.01 { return true }
        let steps = Int(len / 0.25) + 1
        for i in 1..<steps {
            let p = a + d * (Float(i) / Float(steps))
            if opaqueAt(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))) { return false }     // (P377 step 2: the ground by its field)
        }
        // P434 (a): a ship's hull (a frigate's deck and doors) hides what is behind it too.
        if !ships.list.isEmpty, ships.segmentHit(a, d / len, len, except: -1) != nil { return false }
        return true
    }

    /// Line of fire: like canSee, but any block with collision (glass, fences, slabs, stairs, bars, doors) blocks it,
    /// sampled every 0.2 blocks. NPC guns check it from the muzzle before every shot so nothing fires through a wall.
    func clearShot(_ a: V3, _ b: V3) -> Bool {
        let d = b - a
        let len = simd_length(d)
        if len < 0.01 { return true }
        let steps = Int(len / 0.2) + 1
        for i in 1..<steps {
            let p = a + d * (Float(i) / Float(steps))
            let id = Int(block(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))))
            if Blocks.collide[id] && Blocks.fluidKind[id] == 0 { return false }
        }
        if !ships.list.isEmpty, ships.segmentHit(a, d / len, len, except: -1) != nil { return false }      // (P434 a)
        return true
    }

    func raycast(_ origin: V3, _ dir: V3, maxDist: Float) -> (hit: IVec3, normal: IVec3)? {
        var x = Int(floor(origin.x)), y = Int(floor(origin.y)), z = Int(floor(origin.z))
        let sx = dir.x > 0 ? 1 : -1, sy = dir.y > 0 ? 1 : -1, sz = dir.z > 0 ? 1 : -1
        let inf = Float.greatestFiniteMagnitude
        let tdx = dir.x != 0 ? abs(1 / dir.x) : inf
        let tdy = dir.y != 0 ? abs(1 / dir.y) : inf
        let tdz = dir.z != 0 ? abs(1 / dir.z) : inf
        func first(_ o: Float, _ d: Float, _ i: Int) -> Float {
            if d == 0 { return inf }
            return d > 0 ? (Float(i + 1) - o) / d : (o - Float(i)) / -d
        }
        var tmx = first(origin.x, dir.x, x), tmy = first(origin.y, dir.y, y), tmz = first(origin.z, dir.z, z)
        var n = IVec3(0, 0, 0)
        var t: Float = 0
        fieldHit = nil
        // A field world's ground seen from inside (an eye in a tight tunnel's rounded ceiling) is drawn from behind, so
        // the ray looks past the ground it starts in, as the eye does.
        var fieldFrom: Float = 0
        if fieldTerrain && fieldDensity(at: origin) > 0 {
            while fieldFrom < maxDist && fieldDensity(at: origin + dir * fieldFrom) > 0 { fieldFrom += 0.05 }
        }
        while t <= maxDist {
            var b: BlockID = AIR
            // PG2 rewrite: in a field world the ray meets the ground where the field crosses zero (the drawn surface), and
            // the cell it names is the ground cell there; built blocks are targeted as blocks. (P377 step 2: the cell
            // is read through the built layer only.)
            if !fieldTerrain || y < 0 || y >= CH { b = block(x, y, z) }
            else if let c = chunkAt(x, z) {
                let i = Chunk.index(mod(x, CS), y, mod(z, CS))
                let end = min(tmx, tmy, tmz, maxDist)
                if fieldNear(c, x, y, z, i), max(t, fieldFrom) <= end, var h = fieldRaySegment(origin, dir, from: max(t, fieldFrom), to: end) {
                    // P386: the hit point on the drawn ground triangles near where the field crosses zero (they can sit
                    // a few tenths off it, more along a grazing ray), so digging and placing aim at the surface the eye sees.
                    if let r = drawnRay(origin, dir, from: max(fieldFrom, h.t - 1.5), to: min(maxDist, h.t + 1.5)) {
                        h = (fieldCell(r.at, along: dir), r.at, r.t)
                    }
                    fieldHit = h
                    let g = fieldGradient(h.at)
                    let a = simd_abs(g)
                    let nrm = a.x >= a.y && a.x >= a.z ? IVec3(g.x > 0 ? -1 : 1, 0, 0)
                        : (a.y >= a.z ? IVec3(0, g.y > 0 ? -1 : 1, 0) : IVec3(0, 0, g.z > 0 ? -1 : 1))
                    return (h.cell, nrm)
                }
                b = c.blocks.raw(i)
            } else { b = block(x, y, z) }
            // P389: a struck object's cell is met at its pieces there (passed where the blows took it away).
            if !objectReg.cellObj.isEmpty, let r = objectReg.rayCell(self, IVec3(x, y, z), origin, dir, maxDist: maxDist) {
                if let h = r { return (IVec3(x, y, z), h) }
            } else if Blocks.targetable(b) {
                if Blocks.render[Int(b)] == RenderType.cube.rawValue { return (IVec3(x, y, z), n) }
                let o = V3(Float(x), Float(y), Float(z))
                var best: (Float, IVec3)?
                for (mn, mx) in selectionBoxes(b) {
                    if let h = World.rayBox(origin, dir, o + mn, o + mx), h.0 <= maxDist, h.0 < (best?.0 ?? inf) { best = h }
                }
                if let h = best { return (IVec3(x, y, z), h.1) }
            }
            if tmx < tmy && tmx < tmz {
                x += sx; t = tmx; tmx += tdx; n = IVec3(-sx, 0, 0)
            } else if tmy < tmz {
                y += sy; t = tmy; tmy += tdy; n = IVec3(0, -sy, 0)
            } else {
                z += sz; t = tmz; tmz += tdz; n = IVec3(0, 0, -sz)
            }
            if y < -1 || y > CH { return nil }
        }
        return nil
    }

    // MARK: Fluids
    // Cellular fluids: sources (level 0) feed flowing levels 1...7 sideways, falling columns (8) downwards.
    // Water ticks every 0.2 s; lava every 1.5 s (0.5 s in the Emberdeep) and reaches 3 blocks in the
    // Surface (7 in the Emberdeep). Only cells near a change are simulated.

    // The player's block (Game.tick sets it): fluid cells within 24 blocks of it tick first (FluidQueue).
    static var focus: IVec3?
    var fluidPending = FluidQueue()
    var lavaPending = FluidQueue()
    private var fluidDone = 512, lavaDone = 512        // cells the last fluid tick got through (timed batch size)
    static let fluidBudget = 1024
    // Frame-thread time a fluid tick may take before the rest of its batch waits for the next one (infinite: the
    // whole batch, the Mac). The Quest sets 2 ms: streamed-in chunks queue up to 96 springs each, and a full
    // 1024-cell batch took ~20 ms on the M1 (the --quest bench's top tick spike on the plains and cave routes).
    static var fluidSeconds = Double.infinity
    private static let sideDirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
    static let lavaMeet = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(0, -1, 0), IVec3(0, 1, 0)]   // (P412 (d): and lava over it)
    static let allDirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
    var onFluidEvent: ((IVec3) -> Void)?     // lava/water reactions (sound)
    var onFuelLit: ((IVec3) -> Void)?        // P478: fuel caught alight (sound)

    // P478: fuel set alight: the cell burns as fire, and the fuel round it ticks soon, sees the fire and catches too,
    // so the flame runs through a pool or a tank a cell every quarter second.
    func igniteFuel(_ q: IVec3) {
        setBlockAsync(q.x, q.y, q.z, FIRE)
        fires[q] = 0
        scheduleFluid(around: q)
        onFuelLit?(q)
    }
    @inline(__always) static func burns(_ b: BlockID) -> Bool { b == FIRE || Blocks.fluidKind[Int(b)] == 2 || b == World.soulFireID }
    static let soulFireID: BlockID = Blocks.has("soul_fire") ? Blocks.id("soul_fire") : FIRE

    func scheduleFluid(around p: IVec3) {
        let fk = Blocks.fluidKind
        var water = false, lava = false
        for q in [p] + World.allDirs.map({ p + $0 }) {
            let k = fk[Int(builtBlock(q.x, q.y, q.z))]
            if k == 1 || k == 3 { water = true } else if k == 2 { lava = true }       // (fuel runs with the water: P478)
        }
        if water { fluidPending.insert(p); for d in World.allDirs { fluidPending.insert(p + d) } }
        if lava { lavaPending.insert(p); for d in World.allDirs { lavaPending.insert(p + d) } }
    }

    // Fluids may replace air, plants, torches, fire and thinner flowing fluid of the same kind.
    // P363 (d) "water not settling onto the beach": in a field world a fluid runs into a cell whose ground fills less
    // than its lower three quarters (the cell's centre at most a quarter block inside: a beach, a gentle bank), so it
    // lies on the drawn ground there instead of stopping a whole cell short of it. The ground stays (setFluid writes the
    // fluid over it, and takes it off again, without opening the cell: BlockStore.keepGround).
    func shallowGround(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard fieldTerrain, y >= 0 && y < CH, let c = chunkAt(x, z) else { return false }
        let i = Chunk.index(mod(x, CS), y, mod(z, CS))
        return c.blocks.raw(i) == AIR && c.blocks.ground(i) && c.blocks.density(i) <= 8
    }

    private func fluidCanEnter(_ id: BlockID, level: Int, kind: UInt8) -> Bool {
        let l = Int(Blocks.fluidLevel[Int(id)])
        if l >= 0 { return Blocks.fluidKind[Int(id)] == kind && l > 0 && l < 8 && l > level }
        return id == AIR || Blocks.replaceable[Int(id)] || id == TORCH
    }

    // Steps from q to the nearest spot fluid could fall from (a passable cell over a passable or flowing one), searching
    // passable cells up to `reach` away and never back through the source; 1000 when there is none.
    // P377 step 2: what a fluid meets in a cell. The built layer, and in a field world the ground as the field draws it:
    // a cell the ground fills past its lower quarter is solid rock to the fluid, a shallower one (a beach, a gentle
    // bank: shallowGround) is open, so it runs onto the drawn ground. Read from the field, never as cells of the ground.
    @inline(__always) func fluidCell(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        let b = builtBlock(x, y, z)
        guard b == AIR, groundAt(x, y, z) else { return b }
        return shallowGround(x, y, z) ? AIR : STONE
    }

    // The drawn ground's top under cell (x, y, z): where the field crosses zero in the cell's middle column, searched
    // from a block over it to a block under it in eighths; y - 1 when there is none that near. (`--cellflow`: the
    // harness's before for P378 step 4, the flow without the drawn slope.)
    static let drawnFlow = !CommandLine.arguments.contains("--cellflow")
    func drawnFloor(_ x: Int, _ y: Int, _ z: Int) -> Float {
        let px = Float(x) + 0.5, pz = Float(z) + 0.5
        var t = Float(y) + 1
        while t > Float(y) - 1 {
            if fieldDensity(at: V3(px, t, pz)) > 0 { return t }
            t -= 0.125
        }
        return Float(y) - 1
    }

    private func dropDistance(from q: IVec3, origin: IVec3, reach: Int, kind: UInt8) -> Int {
        func passable(_ c: IVec3) -> Bool {
            let id = fluidCell(c.x, c.y, c.z)
            let l = Int(Blocks.fluidLevel[Int(id)])
            if l >= 0 { return Blocks.fluidKind[Int(id)] == kind && l > 0 }
            return id == AIR || Blocks.replaceable[Int(id)] || id == TORCH || shallowGround(c.x, c.y, c.z)
        }
        func hole(_ c: IVec3) -> Bool { c.y > 0 && passable(IVec3(c.x, c.y - 1, c.z)) }
        if hole(q) { return 0 }
        var frontier = [q]
        var seen: [IVec3] = [q, origin]                         // at most ~41 cells: a list beats hashing
        for depth in 1...reach {
            var nextF: [IVec3] = []
            for c in frontier {
                for d in World.sideDirs {
                    let n = IVec3(c.x + d.x, c.y, c.z + d.z)
                    if seen.contains(n) { continue }
                    seen.append(n)
                    guard passable(n) else { continue }
                    if hole(n) { return depth }
                    nextF.append(n)
                }
            }
            if nextF.isEmpty { break }
            frontier = nextF
        }
        return 1000
    }

    private func setFluid(_ p: IVec3, _ id: BlockID) {
        BlockStore.keepGround = fieldTerrain
        defer { BlockStore.keepGround = false }
        if setBlockAsync(p.x, p.y, p.z, id) { scheduleFluid(around: p) }
    }

    // Waterlogged states whose shape closes the floor (bottom slabs and stairs): their water can't pour down.
    static let wetFloor: [Bool] = (0..<Blocks.count).map { i in
        Blocks.isWaterlogged(BlockID(i)) && Blocks.collBoxes[i].contains { $0.y0 == 0 && $0.x0 == 0 && $0.z0 == 0 && $0.x1 == 16 && $0.z1 == 16 }
    }

    static let basaltID: BlockID = Blocks.has("basalt") && Blocks.has("soul_soil") && Blocks.has("blue_ice") ? Blocks.id("basalt") : AIR
    static let soulSoilID: BlockID = Blocks.has("soul_soil") ? Blocks.id("soul_soil") : AIR
    static let blueIceID: BlockID = Blocks.has("blue_ice") ? Blocks.id("blue_ice") : AIR

    func fluidTick(lava: Bool = false) {
        if lava { if lavaPending.isEmpty { return } } else if fluidPending.isEmpty { return }
        World.backgroundEdits = true
        defer { World.backgroundEdits = false }
        let timed = World.fluidSeconds.isFinite && !World.deterministic
        // Timed (Quest): take about twice what the last tick got through, so little is handed back.
        let limit = timed ? min(World.fluidBudget, max(64, 2 * (lava ? lavaDone : fluidDone))) : World.fluidBudget
        let batch = lava ? lavaPending.take(limit) : fluidPending.take(limit)
        let lvT = Blocks.fluidLevel, fkT = Blocks.fluidKind
        var kind: UInt8 = lava ? 2 : 1
        var flow = lava ? LAVA_FLOW : WATER_FLOW, fall = lava ? LAVA_FALL : WATER_FALL
        let stepLevel = lava && !dim.ultrawarm ? 2 : 1
        let t0 = CFAbsoluteTimeGetCurrent()
        if lava { lavaDone = batch.count } else { fluidDone = batch.count }
        for (bi, p) in batch.enumerated() {
            // Out of time (Quest): the rest wait for the next fluid tick.
            if timed && CFAbsoluteTimeGetCurrent() - t0 > World.fluidSeconds {     // (P416: every cell: 16 lava cells ran 30-50 ms past the 2 ms)
                if lava { lavaPending.giveBack(batch.count - bi); lavaDone = bi } else { fluidPending.giveBack(batch.count - bi); fluidDone = bi }
                break
            }
            guard p.y >= 0 && p.y < CH && isLoaded(p.x, p.z) else { continue }
            if !activeHere(p) { park(fluid: p, lava: lava); continue }     // P376: waits for the player to come near
            FarTicks.note(self, V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5))
            let cur = fluidCell(p.x, p.y, p.z)
            let ck = fkT[Int(cur)]
            // P478: the water pass runs fuel too, each cell with its own kind's states.
            guard lava ? ck == 2 : (ck == 1 || ck == 3) else { continue }
            if !lava && ck != kind { kind = ck; flow = ck == 3 ? FUEL_FLOW : WATER_FLOW; fall = ck == 3 ? FUEL_FALL : WATER_FALL }
            var lv = Int(lvT[Int(cur)])
            if kind == 3 {
                // Fuel beside (or under) fire or lava catches.
                var lit = false
                for d in World.lavaMeet where World.burns(fluidCell(p.x + d.x, p.y + d.y, p.z + d.z)) { lit = true; break }
                if lit { igniteFuel(p); continue }
            }
            if kind == 1 {
                // R17 ("obsidian forms quickly"): water reaching lava hardens it now, not on the lava's own 1.5 s tick
                // after a wait in its queue: a source to obsidian, a flow to cobblestone.
                for d in World.lavaMeet {
                    let q = IVec3(p.x + d.x, p.y + d.y, p.z + d.z)
                    let nb = fluidCell(q.x, q.y, q.z)
                    guard fkT[Int(nb)] == 2 else { continue }
                    setBlockAsync(q.x, q.y, q.z, lvT[Int(nb)] == 0 ? OBSIDIAN : COBBLE)
                    scheduleFluid(around: q)
                    onFluidEvent?(q)
                }
            }
            if lava {
                // Lava touching water hardens: source -> obsidian, flowing -> cobblestone.
                var touching = false
                for d in World.lavaMeet where fkT[Int(fluidCell(p.x + d.x, p.y + d.y, p.z + d.z))] == 1 {   // (P412 (d): water under it too)
                    touching = true
                    break
                }
                if touching {
                    setBlockAsync(p.x, p.y, p.z, lv == 0 ? OBSIDIAN : COBBLE)
                    scheduleFluid(around: p)
                    onFluidEvent?(p)
                    continue
                }
                // P478: lava sets fuel it touches alight.
                for d in World.lavaMeet where fkT[Int(fluidCell(p.x + d.x, p.y + d.y, p.z + d.z))] == 3 { igniteFuel(p + d) }
                // Basalt generator (reference): lava over soul soil beside blue ice turns to basalt.
                if World.basaltID != AIR && materialAt(p.x, p.y - 1, p.z) == World.soulSoilID {
                    var ice = false
                    for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(0, 1, 0)] where fluidCell(p.x + d.x, p.y + d.y, p.z + d.z) == World.blueIceID {
                        ice = true
                        break
                    }
                    if ice {
                        setBlockAsync(p.x, p.y, p.z, World.basaltID)
                        scheduleFluid(around: p)
                        onFluidEvent?(p)
                        continue
                    }
                }
            }
            if lv > 0 {
                var want: Int
                if lvT[Int(fluidCell(p.x, p.y + 1, p.z))] >= 0 && fkT[Int(fluidCell(p.x, p.y + 1, p.z))] == kind {
                    want = 8
                } else {
                    var best = 99, sources = 0
                    for d in World.sideDirs {
                        let nb = fluidCell(p.x + d.x, p.y, p.z + d.z)
                        guard fkT[Int(nb)] == kind else { continue }
                        let n = Int(lvT[Int(nb)])
                        if n == 0 { sources += 1 }
                        best = min(best, n == 8 ? 0 : n)
                    }
                    let below = fluidCell(p.x, p.y - 1, p.z)
                    if kind == 1 && sources >= 2 && (Blocks.opaque[Int(below)] || (lvT[Int(below)] == 0 && fkT[Int(below)] == kind)) { want = 0 }
                    else if best + stepLevel > 7 { want = -1 }
                    else { want = best + stepLevel }
                }
                if want != lv {
                    setFluid(p, want < 0 ? AIR : (want == 8 ? fall : flow[want]))
                    if want < 0 { continue }
                    lv = want
                }
            }
            let below = fluidCell(p.x, p.y - 1, p.z)
            if lava && fkT[Int(below)] == 1 {
                // Lava pouring onto water makes stone.
                setBlockAsync(p.x, p.y - 1, p.z, STONE)
                scheduleFluid(around: IVec3(p.x, p.y - 1, p.z))
                onFluidEvent?(p)
                continue
            }
            if p.y > 0 && !World.wetFloor[Int(cur)]
                && (fluidCanEnter(below, level: 0, kind: kind) || shallowGround(p.x, p.y - 1, p.z) || (fkT[Int(below)] == kind && lvT[Int(below)] > 0 && lvT[Int(below)] < 8)) {
                setFluid(IVec3(p.x, p.y - 1, p.z), fall)
                continue
            }
            if lvT[Int(below)] >= 0 { continue }
            let next = (lv == 8 ? 0 : lv) + stepLevel
            if next > 7 { continue }
            // Reference spread: only toward the nearest drop within 4 blocks (lava 2, 4 in the Emberdeep); every side
            // when none is in reach. It went all four ways, so channels and farms flooded sideways.
            let reach = lava && !dim.ultrawarm ? 2 : 4
            // Sides it may run to: open ones, and ones its own flow already fills. The nearest drop is picked among
            // both (T3: once the flow toward the drop filled the side, that side no longer counted, the drop search
            // ran over the others and the spring spread every way: rulescheck "water heads for the drop").
            var openMask = 0, wayMask = 0
            for (i, d) in World.sideDirs.enumerated() {
                let nb = fluidCell(p.x + d.x, p.y, p.z + d.z)
                if fluidCanEnter(nb, level: next, kind: kind) || shallowGround(p.x + d.x, p.y, p.z + d.z) { openMask |= 1 << i; wayMask |= 1 << i }
                else if fkT[Int(nb)] == kind && Int(lvT[Int(nb)]) >= next && lvT[Int(nb)] < 8 { wayMask |= 1 << i }   // (downstream: not the cell it came from)
            }
            if openMask == 0 { continue }
            // With more than one way, keep only the open sides nearest a drop (one way needs no search).
            if wayMask.nonzeroBitCount > 1 {
                var dist = [Int](repeating: Int.max, count: 4)
                for (i, d) in World.sideDirs.enumerated() where wayMask & (1 << i) != 0 {
                    dist[i] = dropDistance(from: IVec3(p.x + d.x, p.y, p.z + d.z), origin: p, reach: reach, kind: kind)
                }
                let best = dist.min() ?? Int.max
                for i in 0..<4 where dist[i] != best { openMask &= ~(1 << i) }
            }
            // P378 step 4: in a field world the flow also follows the drawn ground's slope: of the sides left, only those
            // whose drawn floor lies lowest (within a tenth of a block) take it, so it runs down a bank or a gentle
            // slope the cells can't see (each cell's floor is where the field crosses zero under it).
            if fieldTerrain && World.drawnFlow && openMask.nonzeroBitCount > 1 {
                var fl = [Float](repeating: .infinity, count: 4), lo = Float.infinity
                for (i, d) in World.sideDirs.enumerated() where openMask & (1 << i) != 0 {
                    fl[i] = drawnFloor(p.x + d.x, p.y, p.z + d.z); lo = min(lo, fl[i])
                }
                for i in 0..<4 where fl[i] > lo + 0.1 { openMask &= ~(1 << i) }
            }
            for (i, d) in World.sideDirs.enumerated() where openMask & (1 << i) != 0 {
                setFluid(IVec3(p.x + d.x, p.y, p.z + d.z), flow[next])
            }
        }
    }

    // MARK: Fire
    // Scheduled (not random) ticks: fire ages and burns out, destroys flammable neighbours and spreads.

    private(set) var fires: [IVec3: Int] = [:]
    var onIgnite: ((IVec3, BlockID) -> Void)?   // flammable block destroyed (TNT gets primed by the game)

    func placeFire(_ p: IVec3) {
        guard Blocks.replaceable[Int(block(p.x, p.y, p.z))], !Blocks.isLiquid(block(p.x, p.y, p.z)) else { return }
        setBlock(p.x, p.y, p.z, FIRE)
        fires[p] = 0
    }
    // P504 (Nov 1 07:35, a forest after a shelling: "We got some hovering fire. That's not good"): fire set without its
    // tick (a crater's scorched rim, a burning wreck's ground) never burned out, and stood on in the air when the ground
    // under it went. Every fire is lit here (or placeFire), so it ages, spreads and goes out as fire does.
    func lightFire(_ p: IVec3) {
        setBlockAsync(p.x, p.y, p.z, FIRE)
        fires[p] = 0
    }
    // A fire cell met by a block check (Game.gravityTick: the cells round an edit or a blast) with nothing under it to
    // burn on goes out; one that was never ticking (an old save's) starts its tick. True when it went out.
    func fireCheck(_ p: IVec3) -> Bool {
        guard block(p.x, p.y, p.z) == FIRE else { return false }
        let below = block(p.x, p.y - 1, p.z)
        if !Blocks.opaque[Int(below)] && !Blocks.flammable[Int(below)] && !World.fireHeldBeside(self, p) {
            setBlockAsync(p.x, p.y, p.z, AIR)
            fires.removeValue(forKey: p)
            return true
        }
        if fires[p] == nil { fires[p] = 0 }
        return false
    }
    // A fire on the face of a burning block beside it (a wall, a trunk: whole flammable blocks, not leaves or plants).
    static func fireHeldBeside(_ w: World, _ p: IVec3) -> Bool {
        for d in World.allDirs where d.y == 0 {
            let b = Int(w.block(p.x + d.x, p.y, p.z + d.z))
            if Blocks.flammable[b] && Blocks.opaque[b] { return true }
        }
        return false
    }

    // Reference fire odds per block (FireBlock: ignite, burn). Logs catch slowly and last; leaves, wool and plants go
    // fast. Every flammable block burned at a flat 1 in 5 a fire tick.
    static let fireOdds: [(ignite: UInt8, burn: UInt8)] = {
        var out = [(ignite: UInt8, burn: UInt8)](repeating: (0, 0), count: Blocks.count)
        for i in 0..<Blocks.count where Blocks.flammable[i] && Int(Blocks.groupBase[i]) == i {
            let k = Blocks.key(Blocks.groupBase[i])
            var o: (UInt8, UInt8) = (5, 20)                                         // planks, stairs, slabs, fences...
            if k.hasSuffix("_log") || k.hasSuffix("_wood") || k.hasSuffix("_stem") || k.hasSuffix("_hyphae") || k == "coal_block" { o = (5, 5) }
            else if k.hasSuffix("_leaves") || k.hasSuffix("_wool") || k == "dried_kelp_block" || k.hasPrefix("azalea") { o = (30, 60) }
            else if k == "bookshelf" || k == "lectern" || k == "bee_nest" || k == "chiseled_bookshelf" { o = (30, 20) }
            else if k.hasSuffix("_carpet") || k == "hay_block" { o = (60, 20) }
            else if k == "target" { o = (15, 20) }                                     // composter, beehive: the (5, 20) default
            else if k == "tnt" { o = (15, 100) }
            else if k.hasSuffix("vine") || k.hasSuffix("vines") { o = (15, 100) }
            else if k == "scaffolding" { o = (60, 60) }
            else if Blocks.render[i] == RenderType.cross.rawValue { o = (60, 100) }       // grass, ferns, flowers, bushes
            for s in i..<Blocks.count where Int(Blocks.groupBase[s]) == i { out[s] = o }
        }
        return out
    }()

    func fireTick() {
        if fires.isEmpty { return }
        let fl = Blocks.flammable
        let odds = World.fireOdds
        for (p, age) in fires {
            let b = block(p.x, p.y, p.z)
            if b != FIRE { fires.removeValue(forKey: p); continue }
            if !isLoaded(p.x, p.z) || !activeHere(p) { continue }          // (P376: fire past the active distance waits)
            FarTicks.note(self, V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5))
            let below = block(p.x, p.y - 1, p.z)
            let eternal = below == NETHERRACK || below == BEDROCK || Blocks.key(below) == "magma_block"
            if rainLevel > 0.5 && !eternal, let c = chunks[ChunkKey(x: floorDiv(p.x, CS), z: floorDiv(p.z, CS))],
               p.y >= Int(c.height[mod(p.x, CS) + mod(p.z, CS) * CS]), Rand.int(in: 0..<3) == 0 {
                let b = gen.column(p.x, p.z).biome
                if !(b == .desert || b.isBadlands || b == .savanna || b == .savannaPlateau) {
                    setBlockAsync(p.x, p.y, p.z, AIR); fires.removeValue(forKey: p); continue
                }
            }
            var anyFlammable = false
            for d in World.allDirs {
                let q = p + d
                let nb = block(q.x, q.y, q.z)
                if Blocks.fluidKind[Int(nb)] == 3 { anyFlammable = true; igniteFuel(q); continue }     // P478: fuel catches at once
                // Blocks holding items (barrels, chiseled bookshelves, lecterns) don't burn away: their contents were
                // left behind with no block to open.
                guard fl[Int(nb)], blockEntities[q] == nil else { continue }
                anyFlammable = true
                // Burns away with burnOdds in 300 (250 above and below); the fire takes its place on 5 in age + 10.
                if Rand.int(in: 0..<(d.y != 0 ? 250 : 300)) < Int(odds[Int(nb)].burn) {
                    onIgnite?(q, nb)
                    if Rand.int(in: 0..<(age + 10)) < 5 { setBlockAsync(q.x, q.y, q.z, FIRE); fires[q] = 0 } else { setBlockAsync(q.x, q.y, q.z, AIR) }
                }
            }
            // Spread to air next to flammable blocks nearby.
            if anyFlammable && Rand.int(in: 0..<3) == 0 {
                let q = IVec3(p.x + Rand.int(in: -1...1), p.y + Rand.int(in: -1...2), p.z + Rand.int(in: -1...1))
                let qb = block(q.x, q.y - 1, q.z)
                if block(q.x, q.y, q.z) == AIR && (Blocks.opaque[Int(qb)] || Blocks.flammable[Int(qb)] || World.fireHeldBeside(self, q)) {
                    // Catches by the most flammable neighbour's ignite odds (reference (ignite + 40 + 7 x difficulty) /
                    // (age + 30) against 100, taking normal difficulty).
                    var ig = 0
                    for e in World.allDirs { ig = max(ig, Int(odds[Int(block(q.x + e.x, q.y + e.y, q.z + e.z))].ignite)) }
                    if ig > 0 && Rand.int(in: 0..<100) < (ig + 54) * 10 / (age + 30) {
                        setBlockAsync(q.x, q.y, q.z, FIRE); fires[q] = 0
                    }
                }
            }
            // (P504: a flame in the air beside leaves or grass was held up by them: it hung there, burning nothing under it)
            let supported = Blocks.opaque[Int(below)] || Blocks.flammable[Int(below)] || World.fireHeldBeside(self, p)
            // No age cap: fire on a log burns until the log is gone (it went out after 30 steps whatever it stood on).
            if !eternal && (!supported || (age > 6 && Rand.int(in: 0..<4) == 0 && !anyFlammable)) {
                setBlockAsync(p.x, p.y, p.z, AIR)
                fires.removeValue(forKey: p)
            } else {
                fires[p] = age + 1
            }
        }
    }
}



// Cells waiting for a fluid tick. New cells go into a set (no duplicates); a tick drains them in order from an array
// filled from the set when it runs dry. Taking each batch out of the set by `remove` cost 2-5 ms per 1024 cells on
// the M1 (linear-probing clusters from always emptying the table's front), more than the Quest's 2 ms fluid budget:
// the --quest bench's most frequent tick spike. A cell rescheduled while still queued may run twice (harmless).
struct FluidQueue {
    // P114 (Oct 12 PM: "lava flows only sometimes", "it takes forever to make obsidian"): cells near the player (World.focus)
    // jump the queue. Streamed-in chunks queue every spring of a cave's lava lake; a round of tens of thousands of far
    // cells, a few hundred per 1.5 s lava tick on the Quest, held back the lava he had just let out or poured water on.
    private var urgent = Set<IVec3>()
    private var incoming = Set<IVec3>()
    private var queue: [IVec3] = []
    private var head = 0
    var count: Int { hot.count + urgent.count + incoming.count + queue.count - head }
    var isEmpty: Bool { count == 0 }
    var urgentCount: Int { urgent.count }
    // R17 (Oct 13 evening, again: "lava flows only sometimes"): the urgent set also holds every cell of a cave's lava
    // lake within 24 blocks, handed out in hash order a few hundred per 1.5 s tick, so the block he had just broken
    // beside lava could wait several ticks. Cells within 6 blocks of him go first of all.
    private var hot = Set<IVec3>()
    mutating func insert(_ p: IVec3) {
        if let f = World.focus, abs(p.x - f.x) <= 24 && abs(p.z - f.z) <= 24 && abs(p.y - f.y) <= 24 {
            if abs(p.x - f.x) <= 6 && abs(p.z - f.z) <= 6 && abs(p.y - f.y) <= 6 { hot.insert(p) } else { urgent.insert(p) }
        } else { incoming.insert(p) }
    }
    mutating func removeAll() { hot.removeAll(); urgent.removeAll(); incoming.removeAll(); queue.removeAll(); head = 0; urgentTaken = 0 }
    private var urgentBatch: [IVec3] = []
    private(set) var urgentTaken = 0                 // cells the last take() handed out from the urgent set
    // Up to `limit` cells: the urgent ones first, then the oldest round.
    mutating func take(_ limit: Int) -> ArraySlice<IVec3> {
        if !hot.isEmpty || !urgent.isEmpty {
            urgentBatch.removeAll(keepingCapacity: true)
            for p in hot { if urgentBatch.count >= limit { break }; urgentBatch.append(p) }
            for p in urgentBatch { hot.remove(p) }
            let nHot = urgentBatch.count
            for p in urgent { if urgentBatch.count >= limit { break }; urgentBatch.append(p) }
            for p in urgentBatch[nHot...] { urgent.remove(p) }
            urgentTaken = urgentBatch.count
            return urgentBatch[...]
        }
        urgentTaken = 0
        if head >= queue.count {
            queue.removeAll(keepingCapacity: true); head = 0
            queue.append(contentsOf: incoming)
            // A set that grew to tens of thousands (streamed-in springs) is reallocated small once it empties.
            if incoming.capacity > 4096 { incoming = Set(minimumCapacity: 256) } else { incoming.removeAll(keepingCapacity: true) }
        }
        let end = min(queue.count, head + limit)
        defer { head = end }
        return queue[head..<end]
    }
    // The last `n` cells taken go back to the front (out of time).
    mutating func giveBack(_ n: Int) {
        if urgentTaken > 0 { for p in urgentBatch.suffix(n) { insert(p) }; return }
        head -= n
    }
}
