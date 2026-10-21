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
    struct Mat { let weight: Float; let bond: Float; let reach: Int; var fixture = false }
    // (BS_MATS="planks=6/60/5,concrete=24/400/10": a material's numbers for this run, to try others in the checks)
    static func mat(_ name: String, _ weight: Float, _ bond: Float, _ reach: Int) -> Mat {
        for e in (ProcessInfo.processInfo.environment["BS_MATS"] ?? "").split(separator: ",") {
            let kv = e.split(separator: "="), v = kv.count == 2 ? kv[1].split(separator: "/") : []
            if kv.first.map(String.init) == name, v.count == 3, let a = Float(v[0]), let b = Float(v[1]), let c = Int(v[2]) { return Mat(weight: a, bond: b, reach: c) }
        }
        return Mat(weight: weight, bond: bond, reach: reach)
    }
    // BS_LOAD=0: no load checks (before/after).
    static let enabled = ProcessInfo.processInfo.environment["BS_LOAD"] != "0"

    // (1) Weight is tenths of a tonne per block (a block is a cubic metre: the material's density in g/cm3 x 10). Bond is
    // in the same units: what one face joint carries hanging or reaching out. Reach is in blocks.
    static let wool = mat("wool", 1, 30, 2)         // felted fibre, 0.1 t/m3: light, so it carries thirty of itself; two blocks out and it sags off
    static let glass = mat("glass", 25, 120, 1)      // 2.5 t/m3, brittle: carries a lintel's share in its frame, but reaches one block out from it
    static let framed = mat("framed", 25, 2000, 1)  // a modern window: laminated panes in a steel frame tied into the walls, carrying the floor over it
    static let soil = mat("soil", 16, 5, 1)         // dirt, clay, snow packed by hand: crumbles at an overhang
    static let snow = mat("snow", 4, 20, 4)         // snow blocks: 0.4 t/m3, cut and packed hard: an igloo's dome closes over its room
    static let planks = mat("planks", 6, 200, 8)      // sawn softwood 0.6 t/m3; boards nailed and lapped carry thirty of themselves
    static let logs = mat("logs", 8, 800, 10)       // whole timber 0.8 t/m3 green: a jointed beam, seven times the boards (a frame's posts and beams)
    static let stone = mat("stone", 25, 1500, 5)     // 2.5 t/m3 dressed masonry; mortar and bond (1.5 MPa over a square metre) hold
                                                      // sixty of itself, and a course corbels or vaults five out
    static let ice = mat("ice", 9, 30, 2)
    static let mushroom = mat("mushroom", 2, 100, 8)    // a giant mushroom's cap: light, fibrous flesh spreading wide off its stem
    static let concrete = mat("concrete", 24, 10000, 24) // 2.4 t/m3 with steel bars through it: modern slabs and walls span a hall
    static let metal = mat("metal", 78, 12000, 8)    // steel 7.8 t/m3 and stronger than reinforced concrete (iron, steel plate, copper)
    static let titanium = mat("titanium", 45, 15000, 10) // 4.5 t/m3, stronger still for its weight
    static let gold = mat("gold", 193, 300, 3)      // 19.3 t/m3 and soft: heavy and weak for a metal

    // Per block state: its material, or nil when it is not part of a structure.
    // (a slab weighs half a block, stairs three quarters: a block's weight is its material's times how much of the cell
    // it fills)
    static let table: [Mat?] = (0..<Blocks.count).map { i in
        guard let m = material(i) else { return nil }
        if Blocks.fullCollide[i] { return m }
        let v = Blocks.boxes[i].reduce(Float(0)) { $0 + Float(max(0, Int($1.x1) - Int($1.x0)) * max(0, Int($1.y1) - Int($1.y0)) * max(0, Int($1.z1) - Int($1.z0))) } / 4096
        // (under half a cell: a fitting, as a lantern, a carpet, a rail, a pane or a fence: its reach counts from the
        // sound blocks it's fixed to)
        return Mat(weight: m.weight * min(1, max(0.1, v)), bond: m.bond, reach: m.reach, fixture: v < 0.5)
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
        var reachBreaks = 0, jointBreaks = 0
        var why: [(IVec3, Int, Bool)] = []   // (collect: each block that broke, its reach, hanging from nothing)
        var dists: [Int] = []                // (collect: each block's reach in the first round, in the order of `all`)
        var joints: [(IVec3, Float, Float)] = []   // (collect: each joint that failed: the block, the load it handed on, what the joint holds)
    }
    static var checks = 0, fallen = 0, worstMs: Double = 0, totalMs: Double = 0, crushed = 0      // (harness tallies)

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

    // (the fill's index of each cell near the check, a box `gridR` round it, reused: a dictionary costs ten times as much)
    static let gridR = 32, gridW = 2 * gridR + 1
    static var grid = [Int32](repeating: -1, count: gridW * gridW * gridW)

    // The piece of built blocks at or beside p, and what of it falls. limit/out bound the fill (past them: held).
    static func analyse(_ w: World, at p: IVec3, limit: Int = 4096, out: Int = 24, collect: Bool = false) -> Result {
        var res = Result()
        let useGrid = out < gridR
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
        for d in [IVec3(0, 0, 0)] + nbrs {
            let q = p + d
            if find(q) == nil, let m = part(w, q.x, q.y, q.z) { add(q, m) }
        }
        // Breadth first, nearest blocks first; where the fill stops (more than `limit` blocks, or `out` away) the blocks it
        // didn't get past are taken as held: a big building's far walls stand, so the check is of what's near the change.
        var head = 0
        while head < cells.count {
            let c = cells[head]
            if cells.count > limit || abs(c.x - p.x) > out || abs(c.y - p.y) > out || abs(c.z - p.z) > out { break }
            head += 1
            for d in nbrs {
                let q = c + d
                if find(q) != nil { continue }
                guard w.isLoaded(q.x, q.z) else { if collect { res.all = cells }; return res }
                if let m = part(w, q.x, q.y, q.z) { add(q, m) }
            }
        }
        guard !cells.isEmpty else { return res }
        res.cells = cells.count
        if collect { res.all = cells }
        let n = cells.count, K = nbrs.count
        var alive = [Bool](repeating: true, count: n)
        var root = [Bool](repeating: false, count: n)
        // Each block's neighbours in the piece, once (-1: none), in the order of `nbrs`.
        var nb = [Int32](repeating: -1, count: n * K)
        for i in 0..<n {
            let c = cells[i]
            if helm[Int(w.builtBlock(c.x, c.y, c.z))] { res.cells = 0; return res }
            if i >= head { root[i] = true }
            else { for d in World.allDirs where anchor(w, c.x + d.x, c.y + d.y, c.z + d.z) { root[i] = true; break } }
            for k in 0..<K { if let j = find(c + nbrs[k]) { nb[i * K + k] = Int32(j) } }
        }
        // What a joint holds against a face joint: along an edge `edgeJoint` sideways, `slopeJoint` on a slope.
        let jf: [Float] = nbrs.map { abs($0.x) + abs($0.y) + abs($0.z) == 1 ? 1 : $0.y == 0 ? edgeJoint : slopeJoint }
        // 0-1 breadth first from `from`: a step that climbs costs nothing, any other one.
        func reachFrom(_ from: [Bool]) -> [Int] {
            var dist = [Int](repeating: Int.max, count: n)
            var dq: [Int] = [], front: [Int] = []
            for i in 0..<n where alive[i] && from[i] { dist[i] = 0; front.append(i) }
            var h = 0
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
            return dist
        }
        // What carrying `b` on `a` costs over the step itself.
        @inline(__always) func weakCost(_ a: Int, _ b: Int) -> Int {
            (mats[a].bond * 2 < mats[b].bond || mats[a].fixture && !mats[b].fixture) ? weakStep : 0
        }
        // The cheapest way down from each block (buckets by cost: steps cost 0, 1, weakStep or weakStep + 1).
        func routeFrom(_ from: [Bool]) -> [Int] {
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
        // (the cascade: what broke goes, the rest is checked again; a few rounds at most)
        var fell: [Int] = []
        var to: [Int] = [], tk: [Int] = []
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
            var reaches = Array(Set((0..<n).filter { alive[$0] && dist[$0] != Int.max }.map { mats[$0].reach }))
            reaches.sort(by: >)
            for r in reaches {
                let dr = reachFrom(sound)
                for i in 0..<n where alive[i] && dist[i] != Int.max && mats[i].reach == r && !sound[i] && !mats[i].fixture {
                    var rests = false
                    for k in 0..<K where backCost[k] == 0 { let j = Int(nb[i * K + k]); if j >= 0, alive[j], dr[j] == dr[i] { rests = true; break } }
                    if rests || dr[i] <= r { sound[i] = true } else { broke.append(i); res.reachBreaks += 1; if collect { res.why.append((cells[i], dr[i] == Int.max ? dist[i] : dr[i], false)) } }
                }
            }
            // Fittings last, their reach counted from any sound block (a lantern hung from a roof, a fence on a deck).
            if (0..<n).contains(where: { alive[$0] && mats[$0].fixture }) {
                let dr = reachFrom(sound)
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
                order.sort { route[$0] != route[$1] ? route[$0] > route[$1] : cells[$0].y > cells[$1].y }
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
    static func tick(_ g: Game) {
        let w = g.world
        guard enabled, !w.loadQueue.isEmpty else { return }
        var budget = 1
        while budget > 0, !w.loadQueue.isEmpty {
            let p = w.loadQueue.removeFirst()
            w.loadQueued.remove(IVec3(floorDiv(p.x, 4), floorDiv(p.y, 4), floorDiv(p.z, 4)))
            guard w.activeHere(p) else { continue }
            budget -= 1
            let t0 = CFAbsoluteTimeGetCurrent()
            let r = analyse(w, at: p)
            checks += 1
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            worstMs = max(worstMs, ms); totalMs += ms
            if !r.falls.isEmpty { drop(g, r.falls) }
            if !w.pieces.isEmpty { pieces(g, near: V3(Float(p.x), Float(p.y), Float(p.z))) }
        }
    }

    // (3) What broke off falls, block by block, lowest first (P380's falling blocks); a few chips fly where it broke.
    static func drop(_ g: Game, _ cells: [IVec3]) {
        let w = g.world
        for c in cells {
            let b = w.builtBlock(c.x, c.y, c.z)
            guard member[Int(b)] else { continue }
            w.setBlock(c.x, c.y, c.z, AIR)
            g.falling.append(FallingBlock(V3(Float(c.x) + 0.5, Float(c.y), Float(c.z) + 0.5), b))
        }
        if let c = cells.first {
            let b = g.falling.last?.block ?? STONE
            g.sfx(.place(soundMat(b)), 1, at: V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 0.5))
        }
        fallen += cells.count
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
        }
        w.piecesChanged(at: p)
        fallen += dead.count
    }
}

extension World {
    // P388 (2): a structural block placed or taken away: the piece round it is checked (Structure.tick), once per 4-cube.
    @inline(__always) func queueLoadCheck(_ x: Int, _ y: Int, _ z: Int, _ old: BlockID, _ new: BlockID) {
        guard Structure.enabled, frame == nil, Structure.member[Int(old)] || Structure.member[Int(new)] else { return }
        // (one state of a block for another of the same material carries the same load: a door opening, a lamp lit)
        if let a = Structure.table[Int(old)], let b = Structure.table[Int(new)], a.weight == b.weight && a.bond == b.bond && a.reach == b.reach { return }
        let key = IVec3(floorDiv(x, 4), floorDiv(y, 4), floorDiv(z, 4))
        if loadQueued.insert(key).inserted { loadQueue.append(IVec3(x, y, z)) }
    }
}
