import Foundation
import simd

// P388 (Remington, Oct 19: "materials have weight and bond strength; sand and gravel already fall; wool breaks off
// easily, logs are strong, and a pile of heavy blocks (a bunch of titanium) on a wooden house makes it collapse"). P380
// only dropped built pieces resting on nothing. Now every built piece near a change carries its own weight:
//   (1) the table below: per material, its weight per block, the load one of its joints carries, and how far it reaches
//       out from what holds it up.
//   (2) after a block is placed, broken or blasted (any World.setBlock of a structural block: the player, a blast, a
//       falling block landing, pistons...), the built piece round it is checked, a few a frame: its blocks are flood-
//       filled (joined at faces and edges, up to 4,096 blocks and 24 out: a larger piece is held by the world, as P380's are); the
//       ones on the ground (or into it at a side, or on bedrock) hold it up; each block's reach is the number of
//       sideways or hanging steps to the nearest of them (resting on a block below, or climbing, costs none). Weight then flows from
//       the farthest blocks toward the ground: a block resting on the one below hands it all down, a block that hangs
//       or reaches out shares it among the neighbours one step nearer the ground. A block out past its material's
//       reach, or one handing a neighbour more than the weaker of the two bonds (1000 x the bond straight down: what
//       stands on it presses, which wood and stone take far better than they hold sideways), breaks off.
//   (3) what broke off, and everything that then hangs from nothing, falls (P380's falling blocks, lowest first); a
//       falling block landing hard on a weaker one breaks it (weight x height fallen over twice its bond) and falls on.
//   (4) cost: only near changes (the check's queue), 1 a frame (2 ms worst measured on the host, P388 note), each
//       bounded by the 4,096-block fill.
//   (5) generation: questcheck --loadcheck runs it over every structure type the generator builds; what would fall
//       there was fixed by the numbers, not exempted.
//   (6) loading checks nothing: only a change queues a check, so a saved build stands until something near it changes.
// Free building pieces (FreeBuild) are checked the same way after a piece is set down or taken away, as one graph of
// pieces that touch (a piece is 2 blocks across: each step out is 2 blocks of reach).
// Leaves (a tree holds them, Leaves decay), plants, liquids and unbreakable blocks are not part of it. In a block world
// the natural terrain (stone, dirt...) is the ground, and in a field world so is the soil and moss a structure laid on its
// own floor (a roof garden, a planter: FieldTerrain.split keeps them as blocks); a block on water floats (a raft); a piece with a ship's helm is a
// docked vessel and left to the ships.
enum Structure {
    struct Mat {
        let weight: Float; let bond: Float; let reach: Int; var fixture = false
        // (Nov 13, StructureFlow: what a block of it bears pressed straight down before it crushes, in weight units;
        // 0 = its bond times `crushK`)
        var crush: Float = 0
        var crushCap: Float { (crush > 0 ? crush : bond * Structure.crushK) * Structure.crushScale }
    }
    static let crushK: Float = Float(ProcessInfo.processInfo.environment["BS_CRUSHK"] ?? "") ?? 3
    // (BS_CRUSH=0.5: every material's crushing strength times that, to try in the checks)
    static var crushScale: Float = Float(ProcessInfo.processInfo.environment["BS_CRUSH"] ?? "") ?? 1
    // (BS_MATS="planks=6/60/5,concrete=24/400/10": a material's numbers for this run, to try others in the checks)
    static func mat(_ name: String, _ weight: Float, _ bond: Float, _ reach: Int, crush: Float = 0) -> Mat {
        for e in (ProcessInfo.processInfo.environment["BS_MATS"] ?? "").split(separator: ",") {
            let kv = e.split(separator: "="), v = kv.count == 2 ? kv[1].split(separator: "/") : []
            if kv.first.map(String.init) == name, v.count == 3, let a = Float(v[0]), let b = Float(v[1]), let c = Int(v[2]) { return Mat(weight: a, bond: b, reach: c) }
        }
        return Mat(weight: weight, bond: bond, reach: reach, crush: crush)
    }
    // BS_LOAD=0: no load checks (before/after).
    static let enabled = ProcessInfo.processInfo.environment["BS_LOAD"] != "0"

    // (Nov 13, StructureFlow) crush: what a block bears pressed straight down, in the same units. Every material bears
    // far more pressed than hung (masonry sixty times its bond in the real thing; here enough for a wall of it 240
    // high, a timber frame 100, packed earth 25), so a sound building never crushes its own footings; what brings a
    // big one down is too little left under too much: a storey shot out to a few columns.
    // (Concrete and steel are held to a wall of themselves some 300 high, well under the real thing: on the real
    // numbers three concrete posts carried the whole top of a gutted citadel tower, his Nov 12 18:28 note.)
    // (1) Weight is tenths of a tonne per block (a block is a cubic metre: the material's density in g/cm3 x 10). Bond is
    // in the same units: what one face joint carries hanging or reaching out. Reach is in blocks.
    static let wool = mat("wool", 1, 30, 2, crush: 200)         // felted fibre, 0.1 t/m3: light, so it carries thirty of itself; two blocks out and it sags off
    static let glass = mat("glass", 25, 120, 1, crush: 1500)      // 2.5 t/m3, brittle: carries a lintel's share in its frame, but reaches one block out from it
    static let framed = mat("framed", 25, 2000, 1, crush: 3000)  // a modern window: laminated panes in a steel frame tied into the walls, carrying the floor over it
    static let soil = mat("soil", 16, 5, 1, crush: 400)         // dirt, clay, snow packed by hand: crumbles at an overhang
    static let snow = mat("snow", 4, 20, 4, crush: 150)         // snow blocks: 0.4 t/m3, cut and packed hard: an igloo's dome closes over its room
    static let planks = mat("planks", 6, 200, 8, crush: 800)      // sawn softwood 0.6 t/m3; boards nailed and lapped carry thirty of themselves
    static let logs = mat("logs", 8, 800, 10, crush: 3000)       // whole timber 0.8 t/m3 green: a jointed beam, seven times the boards (a frame's posts and beams)
    static let stone = mat("stone", 25, 1500, 5, crush: 6000)     // 2.5 t/m3 dressed masonry; mortar and bond (1.5 MPa over a square metre) hold
                                                      // sixty of itself, and a course corbels or vaults five out
    static let ice = mat("ice", 9, 30, 2, crush: 300)
    static let mushroom = mat("mushroom", 2, 100, 8, crush: 300)    // a giant mushroom's cap: light, fibrous flesh spreading wide off its stem
    static let concrete = mat("concrete", 24, 10000, 24, crush: 7500) // 2.4 t/m3 with steel bars through it: modern slabs and walls span a hall
    static let metal = mat("metal", 78, 12000, 8, crush: 20000)    // steel 7.8 t/m3 and stronger than reinforced concrete (iron, steel plate, copper)
    static let titanium = mat("titanium", 45, 15000, 10, crush: 20000) // 4.5 t/m3, stronger still for its weight
    static let gold = mat("gold", 193, 300, 3, crush: 3000)      // 19.3 t/m3 and soft: heavy and weak for a metal

    // Per block state: its material, or nil when it is not part of a structure.
    // (a slab weighs half a block, stairs three quarters: a block's weight is its material's times how much of the cell
    // it fills)
    static let table: [Mat?] = (0..<Blocks.count).map { i in
        guard let m = material(i) else { return nil }
        if Blocks.fullCollide[i] { return m }
        let v = Blocks.boxes[i].reduce(Float(0)) { $0 + Float(max(0, Int($1.x1) - Int($1.x0)) * max(0, Int($1.y1) - Int($1.y0)) * max(0, Int($1.z1) - Int($1.z0))) } / 4096
        // (under half a cell: a fitting, as a lantern, a carpet, a rail, a pane or a fence: its reach counts from the
        // sound blocks it's fixed to)
        return Mat(weight: m.weight * min(1, max(0.1, v)), bond: m.bond, reach: m.reach, fixture: v < 0.5, crush: m.crush)
    }
    static func material(_ i: Int) -> Mat? {
        let b = BlockID(i)
        guard b != AIR, Blocks.collide[i], !Blocks.isLiquid(b), !CapitalBase.isLeaf(b), Blocks.hardness[i] >= 0 else { return nil }
        let k = Blocks.key(Blocks.groupBase[i])
        if k.hasSuffix("mushroom_block") { return mushroom }
        if k == "diamond_block" { return titanium }
        if k.hasPrefix("steel_") { return metal }
        if k.hasPrefix("capital_") || k.hasPrefix("bunker_") || k.contains("armored_glass") { if soundMat(b) == .glass { return framed } }
        if (k.hasPrefix("capital_") || k.hasPrefix("bunker_") || k.contains("concrete") || k.hasPrefix("light_panel")) && soundMat(b) != .glass { return concrete }   // (a light panel is cast into its slab)
        if k == "gold_block" || k == "raw_gold_block" { return gold }
        if CapitalBase.isLog(b) || k.hasSuffix("_log") || k.hasSuffix("_wood") || k.hasSuffix("_stem") || k.hasSuffix("_hyphae") || k.contains("beam") { return logs }
        switch soundMat(b) {
        case .wool: return wool
        case .glass: return k.contains("ice") ? ice : glass
        case .wood: return planks
        case .metal: return metal
        case .snow: return snow
        case .dirt, .grass, .sand, .gravel, .mud, .soul: return soil
        case .leaves, .plant: return wool
        default: return stone
        }
    }
    static let member: [Bool] = table.map { $0 != nil }
    static let grows: [Bool] = (0..<Blocks.count).map { i in
        ["bamboo", "bamboo_sapling", "sugar_cane", "cactus", "kelp", "kelp_plant"].contains(Blocks.key(Blocks.groupBase[i]))
    }
    static var skippedGround = 0                            // (harness: dug ground touching no building, no check queued)
    // A docked vessel (a piece with a helm) is the ships' business: it is put back as blocks where it docked, in the
    // water or the air, and lifts off again (Ships.swift); never checked.
    static let helm: [Bool] = (0..<Blocks.count).map { Blocks.key(Blocks.groupBase[$0]).hasPrefix("ship_helm") }

    // MARK: (2) The check

    // A block's neighbours: its 6 faces and 12 edges. Blocks touching along an edge are joined: a stair or slab roof
    // climbs in diagonal steps, a tent's sides too, and each step rests on the one below it (a step straight up costs no
    // reach: a wall carries down itself).
    static let nbrs: [IVec3] = {
        var out = World.allDirs
        for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where abs(dx) + abs(dy) + abs(dz) == 2 { out.append(IVec3(dx, dy, dz)) } } }
        return out
    }()

    // What a joint carries pressed straight down, over what it holds sideways: stone and timber take crushing far better
    // than shear or bending (masonry about 30 MPa in compression against 1 in shear; a stone column could stand
    // kilometres high), so a wall or column fails sideways long before it is crushed.
    static let downFactor: Float = 1000
    // Joints along an edge: half a face joint sideways (a corner overlap, half the bearing), a full one on a slope
    // (stairs and a pitched roof sit on the edge below them), and a diagonal step up costs a block of reach like any
    // other step (a stair roof leans on its eaves; a heavy load can't climb a roof's edges for free).
    // (BS_LOADTUNE="climb=1,edge=0.5,vedge=1,downedge=1,weak=4": the joint rules for this run, to try others in the
    // checks: what a diagonal step up costs in reach, what an edge joint holds against a face joint sideways and on a
    // slope, resting diagonally, and what carrying a block on a much weaker one costs the load's way down)
    static func tune(_ key: String, _ def: Float) -> Float {
        for e in (ProcessInfo.processInfo.environment["BS_LOADTUNE"] ?? "").split(separator: ",") {
            let kv = e.split(separator: "="); if kv.count == 2, kv[0] == key, let v = Float(kv[1]) { return v }
        }
        return def
    }
    static let diagClimb = Int(tune("climb", 1)), edgeJoint = tune("edge", 0.5), downEdge = tune("downedge", 1), slopeJoint = tune("vedge", 1),
                      weakStep = Int(tune("weak", 4))
    // What a step along nbrs[k] costs in reach: straight up nothing, diagonally up `diagClimb`, any other 1.
    static let stepCost: [Int] = nbrs.map { $0.y == 1 ? ($0.x == 0 && $0.z == 0 ? 0 : diagClimb) : 1 }
    // What the step from the neighbour at nbrs[k] to the block costs (0: the block stands on it).
    static let backCost: [Int] = nbrs.map { o in stepCost[nbrs.firstIndex(of: IVec3(-o.x, -o.y, -o.z))!] }

    struct Result {
        var cells = 0            // blocks in the piece (0: held by the world, not checked)
        var all: [IVec3] = []    // (collect: the piece's blocks)
        var falls: [IVec3] = []  // what breaks off or hangs from nothing, lowest first
        var capped = false       // the fill stopped at its bound (the far blocks were taken as held)
        var reachBreaks = 0, jointBreaks = 0
        var why: [(IVec3, Int, Bool)] = []   // (collect: each block that broke, its reach, hanging from nothing)
        var dists: [Int] = []                // (collect: each block's reach in the first round, in the order of `all`)
        var joints: [(IVec3, Float, Float)] = []   // (collect: each joint that failed: the block, the load it handed on, what the joint holds)
    }
    static var checks = 0, fallen = 0, worstMs: Double = 0, totalMs: Double = 0, crushed = 0      // (harness tallies)
    static var tally: [String: Int]? = nil      // (harness: what queued the checks, old -> new)
    static let snowLoad = ProcessInfo.processInfo.environment["BS_SNOWLOAD"] == "1"     // (P508 before/after: snow queues checks)

    // Is the cell ground or something a structure stands on (not part of one)?
    @inline(__always) static func anchor(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        if y <= 0 { return true }
        if w.groundAt(x, y, z) { return true }
        let b = w.builtBlock(x, y, z)
        if b == AIR { return false }
        if Blocks.isLiquid(b) { return true }                                                   // (a raft floats)
        if Blocks.hardness[Int(b)] < 0 && Blocks.collide[Int(b)] { return true }                // bedrock, barriers
        // a block world's terrain; in a field world, soil a structure laid on its floor (a garden: FieldTerrain.split)
        return SmoothTerrain.natural[Int(b)] && (!w.fieldTerrain || FieldTerrain.gardenSoil[Int(b)])
    }
    @inline(__always) static func part(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> Mat? {
        let b = w.builtBlock(x, y, z)
        guard b != AIR, let m = table[Int(b)] else { return nil }
        if SmoothTerrain.natural[Int(b)] && (!w.fieldTerrain || FieldTerrain.gardenSoil[Int(b)]) { return nil }
        return m
    }
    // (the same two through a chunk cursor: the fills below, CellSet.swift)
    @inline(__always) static func part(_ k: inout ChunkCursor, _ x: Int, _ y: Int, _ z: Int) -> Mat? {
        let b = k.built(x, y, z)
        guard b != AIR, let m = table[Int(b)] else { return nil }
        if SmoothTerrain.natural[Int(b)] && (!k.w.fieldTerrain || FieldTerrain.gardenSoil[Int(b)]) { return nil }
        return m
    }
    @inline(__always) static func anchor(_ k: inout ChunkCursor, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        if y <= 0 { return true }
        if k.ground(x, y, z) { return true }
        let b = k.built(x, y, z)
        if b == AIR { return false }
        if Blocks.isLiquid(b) { return true }
        if Blocks.hardness[Int(b)] < 0 && Blocks.collide[Int(b)] { return true }
        return SmoothTerrain.natural[Int(b)] && (!k.w.fieldTerrain || FieldTerrain.gardenSoil[Int(b)])
    }

    // (the fill's index of each cell near the check, a box `gridR` round it, reused: a dictionary costs ten times as much)
    static let gridR = 44, gridW = 2 * gridR + 1                // (P510: StructureTip's towers reach 42 up)
    // (Store review, callgrind of the citadel soak: as an array each read and write of it went through the global's
    // lazy start and a uniqueness check, 14 million calls in 134 checks; a buffer allocated once, read through a local)
    static let grid: UnsafeMutablePointer<Int32> = {
        let n = gridW * gridW * gridW
        let b = UnsafeMutablePointer<Int32>.allocate(capacity: n)
        b.initialize(repeating: -1, count: n)
        return b
    }()

    // The piece of built blocks at or beside p, and what of it falls. limit/out bound the fill (past them: held).
    // P416 (Oct 23, "mining in the base 22 fps", "the doors drop it to 6-12"): the bound was 4,096 blocks 24 out; in a
    // Greywall fortress every check filled to it and ran its reach passes over all of it (85-125 ms a check in a debug
    // build, one a frame while anything in the base changed). 1,536 blocks 16 out still reaches past every material's
    // reach (log 6) and its load path to the ground nearby; the far walls are held, as before.
    // Nov 9 (callgrind of the worst soak's load checks, 2.6-4.6 ms in its slow frames): a round searched the piece
    // afresh for every material's reach, from the ground and then from the blocks found sound so far; the first of those
    // is the search from the ground again, and each later one only adds blocks to start from, so each is now the last
    // one carried on from the blocks newly found sound (the same distances: a search that lowers a block's distance
    // puts it back in the queue, so it settles on the shortest way whatever order it goes in). The load's order is
    // sorted on one number a block. (BS_LOADOLD=1: as before; BS_LOADVERIFY=1: each check run both ways and compared)
    static var loadOld = ProcessInfo.processInfo.environment["BS_LOADOLD"] == "1"
    static let loadVerify = ProcessInfo.processInfo.environment["BS_LOADVERIFY"] == "1"
    static var loadVerified = 0, loadVerifyDiffs = 0, loadVerifyOldMs = 0.0, loadVerifyNewMs = 0.0
    static var verifyLine: String {
        let n = Double(max(1, loadVerified))
        return String(format: "load checks run both ways (BS_LOADVERIFY): %d, differing %d; %.3f ms a check before, %.3f now",
                      loadVerified, loadVerifyDiffs, loadVerifyOldMs / n, loadVerifyNewMs / n)
    }
    static func analyse(_ w: World, at p: IVec3, limit: Int = 1536, out: Int = 16, collect: Bool = false) -> Result {
        guard loadVerify else { return analyseOnce(w, at: p, limit: limit, out: out, collect: collect) }
        let was = loadOld
        defer { loadOld = was }
        func run(_ old: Bool) -> (Result, Double) {
            loadOld = old
            let t0 = CFAbsoluteTimeGetCurrent()
            let r = analyseOnce(w, at: p, limit: limit, out: out, collect: true)
            return (r, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }
        // (alternate which goes first: the second runs on warm caches)
        let first = loadVerified % 2 == 0
        let (a, ta) = run(first), (b, tb) = run(!first)
        let (o, n) = first ? (a, b) : (b, a)
        loadVerified += 1
        loadVerifyOldMs += first ? ta : tb; loadVerifyNewMs += first ? tb : ta
        let same = o.cells == n.cells && o.all == n.all && o.falls == n.falls && o.capped == n.capped && o.reachBreaks == n.reachBreaks
            && o.jointBreaks == n.jointBreaks && o.dists == n.dists && o.why.map { "\($0.0) \($0.1) \($0.2)" } == n.why.map { "\($0.0) \($0.1) \($0.2)" }
            && o.joints.map { "\($0.0) \($0.1) \($0.2)" } == n.joints.map { "\($0.0) \($0.1) \($0.2)" }
        if !same { loadVerifyDiffs += 1; print("loadverify: DIFFERS at \(p): \(o.cells) vs \(n.cells) cells, \(o.falls.count) vs \(n.falls.count) falls, breaks \(o.reachBreaks)/\(o.jointBreaks) vs \(n.reachBreaks)/\(n.jointBreaks)") }
        var r = n
        if !collect { r.all = []; r.why = []; r.dists = []; r.joints = [] }
        return r
    }
    private static func analyseOnce(_ w: World, at p: IVec3, limit: Int, out: Int, collect: Bool) -> Result {
        var res = Result()
        let old = loadOld
        let useGrid = out < gridR
        // (the tables as locals: each use of a global in the fill's loops went through its lazy start)
        let grid = Structure.grid, nbrs = Structure.nbrs, stepCost = Structure.stepCost, backCost = Structure.backCost
        let helm = Structure.helm, allDirs = World.allDirs, weakStep = Structure.weakStep
        var dict: [IVec3: Int] = [:]
        var cells: [IVec3] = [], mats: [Mat] = []
        @inline(__always) func slot(_ q: IVec3) -> Int { (q.x - p.x + gridR) + (q.y - p.y + gridR) * gridW + (q.z - p.z + gridR) * gridW * gridW }
        @inline(__always) func find(_ q: IVec3) -> Int? {
            if useGrid {
                guard abs(q.x - p.x) <= gridR, abs(q.y - p.y) <= gridR, abs(q.z - p.z) <= gridR else { return nil }
                let v = grid[slot(q)]; return v < 0 ? nil : Int(v)
            }
            return dict[q]
        }
        @inline(__always) func add(_ q: IVec3, _ m: Mat) {
            if useGrid { grid[slot(q)] = Int32(cells.count) } else { dict[q] = cells.count }
            cells.append(q); mats.append(m)
        }
        defer { if useGrid { for q in cells { grid[slot(q)] = -1 } } }
        var cur = ChunkCursor(w)
        let K = nbrs.count
        for d in [IVec3(0, 0, 0)] + nbrs {
            let q = p + d
            if find(q) == nil, let m = part(&cur, q.x, q.y, q.z) { add(q, m) }
        }
        // Breadth first, nearest blocks first; where the fill stops (more than `limit` blocks, or `out` away) the blocks it
        // didn't get past are taken as held: a big building's far walls stand, so the check is of what's near the change.
        // (Nov 9, the per-instruction profile: two fifths of a check went in `find`'s bounds checks and slot sums for
        // each block's 18 neighbours. Every block the fill reaches is within out + 1 of p and its neighbours within
        // out + 2: inside the grid when that's within gridR, so a neighbour's slot is its block's plus a fixed offset.)
        let quick = !old && useGrid && out + 2 <= gridR
        let off: [Int] = nbrs.map { $0.x + $0.y * gridW + $0.z * gridW * gridW }
        var head = 0
        while head < cells.count {
            let c = cells[head]
            if cells.count > limit || abs(c.x - p.x) > out || abs(c.y - p.y) > out || abs(c.z - p.z) > out { break }
            head += 1
            let base = quick ? slot(c) : 0
            for k in 0..<K {
                let q = c + nbrs[k]
                if quick { if grid[base + off[k]] >= 0 { continue } } else if find(q) != nil { continue }
                guard cur.loaded(q.x, q.z) else { if collect { res.all = cells }; return res }
                if let m = part(&cur, q.x, q.y, q.z) { add(q, m) }
            }
        }
        guard !cells.isEmpty else { return res }
        res.cells = cells.count
        res.capped = head < cells.count
        if collect { res.all = cells }
        let n = cells.count
        var alive = [Bool](repeating: true, count: n)
        var root = [Bool](repeating: false, count: n)
        // Each block's neighbours in the piece, once (-1: none), in the order of `nbrs`.
        var nb = [Int32](repeating: -1, count: n * K)
        for i in 0..<n {
            let c = cells[i]
            if helm[Int(cur.built(c.x, c.y, c.z))] { res.cells = 0; return res }
            if i >= head { root[i] = true }
            else { for d in allDirs where anchor(&cur, c.x + d.x, c.y + d.y, c.z + d.z) { root[i] = true; break } }
            if quick {
                let base = slot(c)
                for k in 0..<K { nb[i * K + k] = grid[base + off[k]] }      // (-1 where none, as the table starts)
            } else {
                for k in 0..<K { if let j = find(c + nbrs[k]) { nb[i * K + k] = Int32(j) } }
            }
        }
        // What a joint holds against a face joint: along an edge `edgeJoint` sideways, `slopeJoint` on a slope.
        let jf: [Float] = nbrs.map { abs($0.x) + abs($0.y) + abs($0.z) == 1 ? 1 : $0.y == 0 ? edgeJoint : slopeJoint }
        // 0-1 breadth first from `from`: a step that climbs costs nothing, any other one.
        // (each block whose distance drops goes back in the queue: the search settles on the shortest ways from the
        // blocks in `front`, whatever it starts from in `dist` as long as each is the length of some way there)
        func spread(_ dist: inout [Int], _ front: inout [Int]) {
            var dq: [Int] = [], h = 0
            while !front.isEmpty || h < dq.count {
                let i: Int
                if let f = front.popLast() { i = f } else { i = dq[h]; h += 1 }
                let di = dist[i]
                for k in 0..<K {
                    let j = Int(nb[i * K + k])
                    guard j >= 0, alive[j] else { continue }
                    let cost = stepCost[k]
                    if di + cost < dist[j] { dist[j] = di + cost; if cost == 0 { front.append(j) } else { dq.append(j) } }
                }
            }
        }
        func reachFrom(_ from: [Bool]) -> [Int] {
            var dist = [Int](repeating: Int.max, count: n)
            var front: [Int] = []
            for i in 0..<n where alive[i] && from[i] { dist[i] = 0; front.append(i) }
            spread(&dist, &front)
            return dist
        }
        // What carrying `b` on `a` costs over the step itself.
        @inline(__always) func weakCost(_ a: Int, _ b: Int) -> Int {
            (mats[a].bond * 2 < mats[b].bond || mats[a].fixture && !mats[b].fixture) ? weakStep : 0
        }
        // The cheapest way down from each block (buckets by cost: steps cost 0, 1, weakStep or weakStep + 1).
        func routeFrom(_ from: [Bool]) -> [Int] {
            if !old { return routeQuick(from) }
            var d = [Int](repeating: Int.max, count: n)
            var buckets = [[Int]](repeating: [], count: weakStep + 2)
            var left = 0
            for i in 0..<n where alive[i] && from[i] { d[i] = 0; buckets[0].append(i); left += 1 }
            var c = 0
            while left > 0 {
                let slot = c % buckets.count
                while let i = buckets[slot].popLast() {
                    left -= 1
                    guard d[i] == c else { continue }
                    for k in 0..<K {
                        let j = Int(nb[i * K + k])
                        guard j >= 0, alive[j] else { continue }
                        let nd = c + stepCost[k] + weakCost(i, j)
                        if nd < d[j] { d[j] = nd; buckets[nd % buckets.count].append(j); left += 1 }
                    }
                }
                c += 1
            }
            return d
        }
        // (the same search: the buckets as lists in one pool, not an array of arrays checked for sharing at every
        // push (a sixth of the check in the profile), and the bucket a step lands in without a division)
        func routeQuick(_ from: [Bool]) -> [Int] {
            var d = [Int](repeating: Int.max, count: n)
            let B = (stepCost.max() ?? 1) + weakStep + 1     // (a step lands at most this far on: its bucket is free again)
            var top = [Int](repeating: -1, count: B)       // each bucket's last entry in the pool
            var pv: [Int] = [], pn: [Int] = []              // the pool: a block, the entry under it
            pv.reserveCapacity(2 * n); pn.reserveCapacity(2 * n)
            var left = 0
            for i in 0..<n where alive[i] && from[i] { d[i] = 0; pv.append(i); pn.append(top[0]); top[0] = pv.count - 1; left += 1 }
            var c = 0, s = 0
            while left > 0 {
                while top[s] >= 0 {
                    let e = top[s]; top[s] = pn[e]
                    let i = pv[e]
                    left -= 1
                    guard d[i] == c else { continue }
                    for k in 0..<K {
                        let j = Int(nb[i * K + k])
                        guard j >= 0, alive[j] else { continue }
                        let step = stepCost[k] + weakCost(i, j), nd = c + step
                        if nd < d[j] {
                            d[j] = nd
                            var t = s + step; if t >= B { t -= B }
                            pv.append(j); pn.append(top[t]); top[t] = pv.count - 1; left += 1
                        }
                    }
                }
                c += 1; s += 1; if s == B { s = 0 }
            }
            return d
        }
        // (the cascade: what broke goes, the rest is checked again; a few rounds at most)
        var fell: [Int] = []
        var to: [Int] = [], tk: [Int] = [], fresh: [Int] = [], keys: [UInt64] = []
        for _ in 0..<6 {
            // Reach from the ground.
            let dist = reachFrom(root)
            if collect && res.dists.isEmpty { res.dists = dist }
            var broke: [Int] = []
            for i in 0..<n where alive[i] && dist[i] == Int.max { broke.append(i); if collect { res.why.append((cells[i], -1, true)) } }   // hangs from nothing
            // Out past its reach: a block's reach counts from the ground or from the nearest sound block at least as
            // strong as it (a glass panel set in a slab is held by the slab round it, not by the far walls), the
            // longest-reaching materials first. A block resting on one at its own reach is carried by that one.
            var sound = root
            var reaches: [Int] = []
            if old {
                reaches = Array(Set((0..<n).filter { alive[$0] && dist[$0] != Int.max }.map { mats[$0].reach }))
            } else {
                for i in 0..<n where alive[i] && dist[i] != Int.max { let r = mats[i].reach; if !reaches.contains(r) { reaches.append(r) } }
            }
            reaches.sort(by: >)
            // (the search from the sound blocks, carried on from those found sound since: at first that's the ground)
            var dr = old ? [] : dist
            fresh.removeAll(keepingCapacity: true)
            for r in reaches {
                if old { dr = reachFrom(sound) } else if !fresh.isEmpty { for i in fresh { dr[i] = 0 }; spread(&dr, &fresh) }
                for i in 0..<n where alive[i] && dist[i] != Int.max && mats[i].reach == r && !sound[i] && !mats[i].fixture {
                    var rests = false
                    for k in 0..<K where backCost[k] == 0 { let j = Int(nb[i * K + k]); if j >= 0, alive[j], dr[j] == dr[i] { rests = true; break } }
                    if rests || dr[i] <= r { sound[i] = true; if !old { fresh.append(i) } } else { broke.append(i); res.reachBreaks += 1; if collect { res.why.append((cells[i], dr[i] == Int.max ? dist[i] : dr[i], false)) } }
                }
            }
            // Fittings last, their reach counted from any sound block (a lantern hung from a roof, a fence on a deck).
            if (0..<n).contains(where: { alive[$0] && mats[$0].fixture }) {
                if old { dr = reachFrom(sound) } else if !fresh.isEmpty { for i in fresh { dr[i] = 0 }; spread(&dr, &fresh) }
                for i in 0..<n where alive[i] && dist[i] != Int.max && mats[i].fixture && !sound[i] {
                    if dr[i] <= mats[i].reach { sound[i] = true } else { broke.append(i); res.reachBreaks += 1; if collect { res.why.append((cells[i], dr[i] == Int.max ? dist[i] : dr[i], false)) } }
                }
            }
            if broke.isEmpty {
                // Load: each block hands its load on toward the ground along its cheapest way there, where a step onto
                // a block less than half as strong as it (or from a block onto a fitting) costs `weakStep` more: a slab
                // spans over the light or the window set in it, a roof over the carpet under it, and a weak block
                // carries a strong one only when there's no other way down (a stone wall on a wool course).
                let route = routeFrom(root)
                var load = [Float](repeating: 0, count: n)
                var order = (0..<n).filter { alive[$0] && route[$0] != Int.max }
                // (furthest from the ground first, then highest, then in the fill's order: one number a block, sorted)
                var rMax = 0, yLo = Int.max, yHi = Int.min
                for i in order { rMax = max(rMax, route[i]); yLo = min(yLo, cells[i].y); yHi = max(yHi, cells[i].y) }
                // (ledger 68: with every block fallen there is nothing to order, and yHi - yLo, Int.min - Int.max, trapped
                // the checked build; on the headset it wrapped)
                if !old && !order.isEmpty && n < 1 << 24 && rMax < 1 << 24 && yHi - yLo < 1 << 16 {
                    keys.removeAll(keepingCapacity: true)
                    for i in order {
                        let kr = UInt64(rMax - route[i]) << 40, ky = UInt64(yHi - cells[i].y) << 24
                        keys.append(kr | ky | UInt64(i))
                    }
                    keys.sort()
                    for (o, key) in keys.enumerated() { order[o] = Int(key & 0xFF_FFFF) }
                } else {
                    order.sort { route[$0] != route[$1] ? route[$0] > route[$1] : cells[$0].y > cells[$1].y }
                }
                for i in order {
                    load[i] += mats[i].weight
                    if root[i] { continue }
                    // Resting: all of it down on the blocks under it on its way (shared by strength: the stronger take
                    // more); else on the neighbours it hangs from, by strength and joint.
                    to.removeAll(keepingCapacity: true); tk.removeAll(keepingCapacity: true)
                    var down = false
                    for k in 0..<K {
                        let j = Int(nb[i * K + k])
                        guard j >= 0, alive[j], route[j] != Int.max, route[j] + backCost[k] + weakCost(j, i) == route[i] else { continue }
                        if backCost[k] == 0 && !down { down = true; to.removeAll(keepingCapacity: true); tk.removeAll(keepingCapacity: true) }
                        if down && backCost[k] != 0 { continue }
                        to.append(j); tk.append(k)
                    }
                    guard !to.isEmpty else { broke.append(i); continue }
                    var sum: Float = 0
                    for (j, k) in zip(to, tk) { sum += mats[j].bond * (down ? 1 : jf[k]) }
                    var over = false
                    for (j, k) in zip(to, tk) {
                        let f = down ? 1 : jf[k]
                        let share = load[i] * mats[j].bond * f / sum
                        let cap = (down ? downFactor * (nbrs[k].x == 0 && nbrs[k].z == 0 ? 1 : downEdge) : f) * min(mats[i].bond, mats[j].bond)
                        load[j] += share
                        if share > cap { over = true; if collect { res.joints.append((cells[i], share, cap)) } }
                    }
                    if over { broke.append(i); res.jointBreaks += 1 }
                }
            }
            if broke.isEmpty { break }
            for i in broke where alive[i] { alive[i] = false; fell.append(i) }
        }
        res.falls = fell.map { cells[$0] }.sorted { $0.y < $1.y }
        return res
    }

    // The queue: World.setBlock notes structural changes; a few are checked a frame.
    // Store review (build 111's citadel soak: a load check, up to 4.8 ms, ran beside the soldiers' 3-6 ms): in the
    // game's tick a check waits for a frame with the carving allowance left (CraterJob.allowance, which goes by what the
    // tick has left), at most `maxWait` frames; it spends the allowance. Seeded runs and harnesses check as before.
    static var wantSeconds = 0.0012, maxWait = 3          // (one check a frame was all it ever ran: a short wait)
    private static var waited = 0
    static func tick(_ g: Game) {
        let w = g.world
        guard enabled, !w.loadQueue.isEmpty else { return }
        let paced = CraterJob.inTick && !(World.deterministic || Rand.deterministic)
        if paced {
            if CraterJob.allowance() < wantSeconds && waited < maxWait { waited += 1; return }
            waited = 0
        }
        let began = CFAbsoluteTimeGetCurrent()
        defer { if paced { CraterJob.spend(CFAbsoluteTimeGetCurrent() - began) } }
        var budget = 1
        while budget > 0, !w.loadQueue.isEmpty {
            let p = w.loadQueue.removeFirst()
            w.loadQueued.remove(IVec3(floorDiv(p.x, 4), floorDiv(p.y, 4), floorDiv(p.z, 4)))
            // P430 (b) (Oct 24 10:25, "the radar dish, I destroyed the tower. It should be falling"): a check past the
            // active distance waits for it (FarTicks.park) instead of being dropped: the mast shelled from the roof gun
            // lost the checks that would have brought its dish down.
            guard w.activeHere(p) else { w.park(load: p); continue }
            budget -= 1
            let t0 = CFAbsoluteTimeGetCurrent()
            // P437 (Oct 24 16:01-16:03, the Ash Vault: "putting a block there really made it struggle", "really big lag
            // when I break a block here", 32 fps): the vault is one built piece, so every change there filled the check
            // to its 1,536 blocks (40-150 ms a check in a debug build). Where the changed block and each built block
            // beside it rest on the ground, nothing can fall or lose its reach (every way through the cell starts at a
            // block that is itself held, and what sits on such a block hands its weight straight down to it), so the
            // fill is skipped.
            let more = oldSeeds ? [] : rimSeeds(w, p)
            if more.isEmpty && grounded(w, p) {
                checks += 1
                if !w.pieces.isEmpty { pieces(g, near: V3(Float(p.x), Float(p.y), Float(p.z))) }
                continue
            }
            for s in [p] + more {
                let r = analyse(w, at: s)
                checks += 1
                let cut = r.capped ? looseAll(w, near: s) : []
                if !cut.isEmpty { for piece in cut { g.topple(piece) } }     // P407: a tower cut from its footing
                // (Nov 13: a piece too big for this check, still joined to the ground: weighed whole, off the frame.
                // What this check would drop waits for that, StructureCollapse.hold.)
                else if !r.falls.isEmpty { if !(r.capped && StructureCollapse.hold(w, at: s)) { drop(g, r.falls) } }
                if r.capped && cut.isEmpty { StructureCollapse.request(w, at: s) }
            }
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            worstMs = max(worstMs, ms); totalMs += ms
            if !w.pieces.isEmpty { pieces(g, near: V3(Float(p.x), Float(p.y), Float(p.z))) }
        }
    }

    // Nov 12 playtest (06:21:17, a Boreal tower shot through from the roof gun: "that helipad's hovering", its top,
    // penthouse and mast, hung over the shot-out floors): a change queues one check a 4-cube, from the first cell changed
    // there. A shell's blast takes out a whole cube or more, so by the time the check ran its cell was in the middle of
    // the hole, nothing built beside it, and the blocks at the hole's rim, what was left holding the top, were never
    // checked. Where nothing is built beside the changed cell, the check now starts from the built blocks round the cube that
    // face an open cell inside it (one for each piece they belong to there, up to four). BS_OLDLOADSEED=1: from the first cell only, as before.
    static let oldSeeds = ProcessInfo.processInfo.environment["BS_OLDLOADSEED"] == "1"
    static var rimChecks = 0                                  // (harness: checks started from a hole's rim)
    static func rimSeeds(_ w: World, _ p: IVec3) -> [IVec3] {
        // (only where the check from the changed cell itself finds nothing built beside it: a dug block, a placed one,
        // costs what it did)
        for d in [IVec3(0, 0, 0)] + nbrs where part(w, p.x + d.x, p.y + d.y, p.z + d.z) != nil { return [] }
        let b = IVec3(floorDiv(p.x, 4) * 4, floorDiv(p.y, 4) * 4, floorDiv(p.z, 4) * 4)
        @inline(__always) func inCube(_ q: IVec3) -> Bool { q.x >= b.x && q.x < b.x + 4 && q.y >= b.y && q.y < b.y + 4 && q.z >= b.z && q.z < b.z + 4 }
        // Built blocks in the cube and the shell round it with an open (not built, not ground) face into the cube.
        var rim: [IVec3] = []
        for y in (b.y - 1)...(b.y + 4) { for z in (b.z - 1)...(b.z + 4) { for x in (b.x - 1)...(b.x + 4) {
            let q = IVec3(x, y, z)
            guard abs(q.x - p.x) > 1 || abs(q.y - p.y) > 1 || abs(q.z - p.z) > 1, part(w, x, y, z) != nil else { continue }
            for d in World.allDirs {
                let o = q + d
                if inCube(o) && part(w, o.x, o.y, o.z) == nil && !anchor(w, o.x, o.y, o.z) { rim.append(q); break }
            }
        } } }
        guard !rim.isEmpty else { return [] }
        // One start a piece (joined by faces and edges inside the box).
        var left = Set(rim), out: [IVec3] = []
        for c in rim where left.contains(c) {
            left.remove(c)
            var comp = [c], h = 0
            while h < comp.count {
                let q = comp[h]; h += 1
                for d in nbrs where left.contains(q + d) { left.remove(q + d); comp.append(q + d) }
            }
            if out.count < 4 { out.append(c) }
        }
        rimChecks += out.count
        return out
    }

    // The changed cell and every built block beside it stand on a straight column of built blocks down to the ground (or
    // nothing is built there).
    static func grounded(_ w: World, _ p: IVec3) -> Bool {
        for d in [IVec3(0, 0, 0)] + nbrs {
            let q = p + d
            guard part(w, q.x, q.y, q.z) != nil else { continue }
            if helm[Int(w.builtBlock(q.x, q.y, q.z))] { return false }
            // Held: it, or a block of the straight column of built blocks it stands on, touches the ground (a block
            // laid on a floor, the floor on the vault's packed soil, the soil on the rock).
            var u = q, held = false
            for _ in 0..<24 {
                if touchesGround(w, u) { held = true; break }
                u.y -= 1
                guard part(w, u.x, u.y, u.z) != nil, !helm[Int(w.builtBlock(u.x, u.y, u.z))] else { break }
            }
            if !held { return false }
        }
        return true
    }
    @inline(__always) static func touchesGround(_ w: World, _ q: IVec3) -> Bool {
        for e in World.allDirs where anchor(w, q.x + e.x, q.y + e.y, q.z + e.z) { return true }
        return false
    }

    // (3) What broke off falls, block by block, lowest first (P380's falling blocks); a few chips fly where it broke.
    // P407 (Oct 22 22:06, "it turned into square blocks there when I broke it, and it fell"): a tree, or a piece of
    // `wholeMin` blocks or more, comes down whole, as one body drawn with its own mesh (Game.topple); crumbs fall block by block.
    static let wholeMin = 12
    static var dropWorstMs = 0.0, dropWorst = ""         // (the soak: the slowest drop and its parts)
    static var crumbMs = 0.0, crumbN = 0                  // (the soak: the crumbs' clearing, all of it)
    static func drop(_ g: Game, _ all: [IVec3]) {
        let w = g.world
        let t0 = CFAbsoluteTimeGetCurrent()
        var tSplit = t0, tWhole = t0, wholes = 0, nCrumbs = 0
        defer {
            let t3 = CFAbsoluteTimeGetCurrent(), ms = (t3 - t0) * 1000
            crumbMs += (t3 - tWhole) * 1000
            if ms > dropWorstMs {
                dropWorstMs = ms
                dropWorst = String(format: "%d blocks: pieces %.1f, %d whole %.1f, %d crumbs %.1f", all.count, (tSplit - t0) * 1000, wholes,
                                   (tWhole - tSplit) * 1000, nCrumbs, (t3 - tWhole) * 1000)
            }
        }
        var crumbs = Set<IVec3>()
        let comps = components(all)
        tSplit = CFAbsoluteTimeGetCurrent()
        for comp in comps {
            let tree = comp.contains { CapitalBase.isLog(w.builtBlock($0.x, $0.y, $0.z)) }
            if comp.count >= wholeMin || tree && comp.count >= 2 { g.topple(comp); wholes += 1 } else { crumbs.formUnion(comp) }
        }
        tWhole = CFAbsoluteTimeGetCurrent()
        let cells = all.filter { crumbs.contains($0) }
        nCrumbs = cells.count
        // (item 61, ledger 45's bloom: with no circuit part near, the crumbs go without the circuit's marks round each
        // cell, as a blast's crater, a felled tree and dropped ground do)
        let quiet0 = w.circuitQuiet
        if Explosion.circuitCalm && !cells.isEmpty && !w.circuitNear(cells, margin: 3) { w.circuitQuiet = true }
        defer { w.circuitQuiet = quiet0 }
        w.editBatch {                                  // (ledger 44: one remesh for all the crumbs)
            for c in cells {
                let b = w.builtBlock(c.x, c.y, c.z)
                guard member[Int(b)] else { continue }
                w.setBlock(c.x, c.y, c.z, AIR)
                g.falling.append(FallingBlock(V3(Float(c.x) + 0.5, Float(c.y), Float(c.z) + 0.5), b))
                crumbN += 1
            }
        }
        if let c = cells.first {
            let b = g.falling.last?.block ?? STONE
            g.sfx(.place(soundMat(b)), 1, at: V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 0.5))
        }
        fallen += all.count
    }

    // The joined groups (faces and edges, as the check joins them) of a set of cells.
    static func components(_ cells: [IVec3]) -> [[IVec3]] {
        var left = Set(cells), out: [[IVec3]] = []
        for c in cells where left.contains(c) {
            left.remove(c)
            var comp = [c], h = 0
            while h < comp.count {
                let q = comp[h]; h += 1
                for d in nbrs where left.contains(q + d) { left.remove(q + d); comp.append(q + d) }
            }
            out.append(comp)
        }
        return out
    }

    // P407 (Oct 22 22:13, the Boreal Station tower: "that should fall 'cause I just destroyed the structure for it. It
    // didn't fall"): the check's fill stops at 1,536 blocks and takes the rest as held, so a big piece never came down.
    // When it stopped, each piece beside the change is followed whole (up to `limit` blocks, faces and edges): one that
    // nothing holds (no block of it on the ground, bedrock or water) is returned to fall as one body. The fill ends at the
    // first block on the ground, so a standing building costs only the way to its nearest footing.
    private static let looseSeen = CellSet(capacity: 8192), looseHeld = CellSet(capacity: 8192)
    static func loose(_ w: World, near p: IVec3, limit: Int = 24_000) -> [IVec3]? { looseAll(w, near: p, limit: limit).first }
    // Nov 12 playtest (06:21:17, a Boreal tower shot through from the roof gun: its top, penthouse and mast, stayed up):
    // the search above returned the first piece it found loose, and what was taken out with it was taken out quietly (no
    // check after), so a second piece beside the same change, cut loose by the same shot, hung on. Every loose piece
    // beside the change is returned now. (BS_OLDLOOSE=1: the first only, as before)
    static let oldLoose = ProcessInfo.processInfo.environment["BS_OLDLOOSE"] == "1"
    static func looseAll(_ w: World, near p: IVec3, limit: Int = 24_000) -> [[IVec3]] {
        let held = looseHeld, seen = looseSeen
        held.removeAll()
        var cur = ChunkCursor(w)
        let K = nbrs.count
        var found: [[IVec3]] = [], taken = Set<IVec3>()
        for d in [IVec3(0, 0, 0)] + nbrs {
            let s0 = p + d
            guard !held.contains(s0), !taken.contains(s0), part(&cur, s0.x, s0.y, s0.z) != nil else { continue }
            seen.removeAll(); seen.insert(s0)
            var comp = [s0], h = 0, anchored = false
            fill: while h < comp.count {
                let c = comp[h]; h += 1
                if helm[Int(cur.built(c.x, c.y, c.z))] { anchored = true; break }
                for e in World.allDirs where anchor(&cur, c.x + e.x, c.y + e.y, c.z + e.z) { anchored = true; break fill }
                for e in nbrs {
                    let q = c + e
                    if seen.contains(q) { continue }
                    guard cur.loaded(q.x, q.z), comp.count < limit else { anchored = true; break fill }
                    // (a piece that reaches one an earlier side found held is held: it is the same piece)
                    if held.contains(q) { anchored = true; break fill }
                    if part(&cur, q.x, q.y, q.z) != nil { seen.insert(q); comp.append(q) }
                }
            }
            if anchored { for q in comp { held.insert(q) }; continue }
            found.append(comp)
            if oldLoose { return found }
            for q in comp { taken.insert(q) }
        }
        return found
    }

    // (3) A falling block meeting built block `onto` after falling `fell` blocks: does it break through?
    static func crushes(_ falling: BlockID, fell: Float, onto: BlockID) -> Bool {
        guard enabled, fell > 1, let a = table[Int(falling)], let b = table[Int(onto)] else { return false }
        return a.weight * fell > 2 * b.bond
    }

    // MARK: Free building pieces

    // The pieces round p (24 blocks): those touching are joined; one standing on the ground or a built block holds;
    // the reach and load rules as for blocks, a step from piece to piece counting 2 blocks. What fails comes down as
    // debris of its material.
    static func pieces(_ g: Game, near p: V3) {
        let w = g.world
        guard enabled, w.fieldTerrain, !w.pieces.isEmpty else { return }
        var ids: [Int] = []
        for (i, pc) in w.pieces.enumerated() where simd_length(pc.origin - p) < 24 { ids.append(i) }
        guard !ids.isEmpty else { return }
        let n = ids.count
        var boxes: [(V3, V3)] = [], mats: [Mat] = [], vol: [Float] = []
        for i in ids {
            let pc = w.pieces[i]
            var lo = V3(repeating: .greatestFiniteMagnitude), hi = V3(repeating: -.greatestFiniteMagnitude)
            var v: Float = 0
            for (a, b) in FreeBuild.collision(pc) { lo = simd_min(lo, a); hi = simd_max(hi, b); let s = b - a; v += s.x * s.y * s.z }
            boxes.append((lo, hi)); mats.append(table[Int(pc.mat)] ?? planks); vol.append(v)
        }
        func touch(_ a: Int, _ b: Int) -> Bool {
            let (l1, h1) = boxes[a], (l2, h2) = boxes[b], e: Float = 0.06
            return l1.x <= h2.x + e && l2.x <= h1.x + e && l1.y <= h2.y + e && l2.y <= h1.y + e && l1.z <= h2.z + e && l2.z <= h1.z + e
        }
        var root = [Bool](repeating: false, count: n)
        for k in 0..<n {
            let (lo, hi) = boxes[k]
            let y = lo.y - 0.15
            for q in [V3(lo.x, y, lo.z), V3(hi.x, y, lo.z), V3(lo.x, y, hi.z), V3(hi.x, y, hi.z), V3((lo.x + hi.x) / 2, y, (lo.z + hi.z) / 2)] {
                let x = Int(floor(q.x)), yy = Int(floor(q.y)), z = Int(floor(q.z))
                if w.fieldDensity(at: q) > 0 || Blocks.collide[Int(w.builtBlock(x, yy, z))] { root[k] = true; break }
            }
        }
        // Reach: steps from piece to piece (onto one below: none), 2 blocks each.
        var dist = [Int](repeating: Int.max, count: n)
        var queue: [Int] = (0..<n).filter { root[$0] }
        for k in queue { dist[k] = 0 }
        var h = 0
        while h < queue.count {
            let a = queue[h]; h += 1
            for b in 0..<n where b != a && touch(a, b) {
                let up = boxes[b].0.y >= boxes[a].1.y - 0.1                      // b stands on a
                let nd = dist[a] + (up ? 0 : 2)
                if nd < dist[b] { dist[b] = nd; queue.append(b) }
            }
        }
        var gone: [Int] = []
        for k in 0..<n where dist[k] == Int.max || dist[k] > mats[k].reach { gone.append(k) }
        if gone.isEmpty {
            // Load toward the ground, as for blocks.
            var load = [Float](repeating: 0, count: n)
            let order = (0..<n).sorted { dist[$0] != dist[$1] ? dist[$0] > dist[$1] : boxes[$0].0.y > boxes[$1].0.y }
            for a in order {
                load[a] += mats[a].weight * vol[a]
                if root[a] { continue }
                // (toward the ground: a piece nearer it, or the one this stands on)
                var to: [Int] = []
                for b in 0..<n where b != a && touch(a, b) {
                    if dist[b] < dist[a] || dist[b] == dist[a] && boxes[b].1.y <= boxes[a].0.y + 0.1 { to.append(b) }
                }
                guard !to.isEmpty else { gone.append(a); continue }
                let share = load[a] / Float(to.count)
                for b in to { load[b] += share; if share > min(mats[a].bond, mats[b].bond) * 2 { gone.append(a) } }
            }
        }
        guard !gone.isEmpty else { return }
        let dead = Set(gone.map { ids[$0] })
        for i in dead.sorted(by: >) {
            let pc = w.pieces.remove(at: i)
            let (lo, hi) = boxes[ids.firstIndex(of: i)!]
            g.debris.bits(pc.mat, at: (lo + hi) * 0.5, size: hi - lo, direction: V3(0, -1, 0), count: 6, speed: 0.3, seed: UInt32(truncatingIfNeeded: i &* 2654435761))
            // P484 (Oct 28 18:18, his planks roof: "the block just breaks... It should fall... fall onto the ground and
            // not despawn"): the piece comes down as its block and lands, to be picked up again.
            let c = (lo + hi) * 0.5
            if Blocks.collide[Int(pc.mat)] { g.falling.append(FallingBlock(V3(floor(c.x) + 0.5, floor(c.y), floor(c.z) + 0.5), pc.mat)) }
            else if let it = Items.item(forBlock: pc.mat) { g.drops.spawn(ItemStack(it, 1), at: c) }
        }
        w.piecesChanged(at: p)
        fallen += dead.count
    }
}

extension World {
    // P388 (2): a structural block placed or taken away: the piece round it is checked (Structure.tick), once per 4-cube.
    @inline(__always) func queueLoadCheck(_ x: Int, _ y: Int, _ z: Int, _ old: BlockID, _ new: BlockID) {
        guard Structure.enabled, frame == nil, Structure.member[Int(old)] || Structure.member[Int(new)] else { return }
        // (Nov 13, StructureCollapse: a piece being read whole starts over when one of its blocks changes)
        if StructureCollapse.tracking { if structChanged.count < 512 { structChanged.append(IVec3(x, y, z)) } else { structFlood = true } }
        guard !restoring else { return }
        // (one state of a block for another of the same material carries the same load: a door opening, a lamp lit)
        if let a = Structure.table[Int(old)], let b = Structure.table[Int(new)], a.weight == b.weight && a.bond == b.bond && a.reach == b.reach { return }
        // P416 (Oct 23, the Greywall base: 20 checks a second with nobody building): grass dying back to dirt under
        // snow, lava eating the rock. Ground turning into other ground (or a liquid) is no structure's business: in a
        // block world both are ground under a building, in a Polygons world neither is part of one.
        // (a garden's soil for soil carries the same)
        if SmoothTerrain.natural[Int(old)] && (SmoothTerrain.natural[Int(new)] || Blocks.isLiquid(new)) { return }
        // P508 (Nov 1 15:50, digging by Boreal Station, fps 44 while it snowed): snow settling out of the sky (air to a
        // snow layer) or melting off (a layer to air) carries nothing: each one queued a check of the station's piece.
        // (Store review, the jungle soak: bamboo shooting up queued 335 checks in 30 s. A plant growing into air
        // carries nothing.)
        if old == AIR && Structure.grows[Int(new)] { return }
        let sl = BlockID(SmoothTerrain.snowLayer)
        if ((old == AIR && new == sl) || (old == sl && new == AIR)) && !Structure.snowLoad { return }
        // P510 (his dirt freeze by Boreal Station, measured: 34 of 42 checks queued by dug dirt, 3 ms each on the host,
        // the worst 9-12): ground or a loose natural block dug out of the way holds up something only when a building's
        // block touches it. With none of its six neighbours a built structural block, there is nothing to check.
        if SmoothTerrain.natural[Int(old)] && new == AIR {
            var touches = false
            for (dx, dy, dz) in [(0, 1, 0), (1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0, -1, 0)] {
                let b = Int(block(x + dx, y + dy, z + dz))
                if Structure.member[b] && !SmoothTerrain.natural[b] { touches = true; break }
            }
            if !touches { Structure.skippedGround += 1; return }
        }
        structLoud &+= 1                                     // (a change a check is queued for: StructureCollapse's quiet)
        let key = IVec3(floorDiv(x, 4), floorDiv(y, 4), floorDiv(z, 4))
        if Structure.tally != nil { Structure.tally![Blocks.key(old) + " -> " + Blocks.key(new), default: 0] += 1 }
        if loadQueued.insert(key).inserted { loadQueue.append(IVec3(x, y, z)) }
    }
    // (a check held for the whole weigh, StructureCollapse.hold, run again)
    func requeueLoadCheck(_ p: IVec3) {
        guard Structure.enabled, frame == nil else { return }
        if loadQueued.insert(IVec3(floorDiv(p.x, 4), floorDiv(p.y, 4), floorDiv(p.z, 4))).inserted { loadQueue.append(p) }
    }
}
