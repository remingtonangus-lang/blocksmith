import Foundation
import simd

// Ground navigation for mobs: A* over block cells in 8 directions (no corner cutting), stepping or
// jumping up one block, dropping as far as the mob's fall limit (3, more for a monster chasing at high
// health), climbing ladders / vines / scaffolding, swimming (penalised for land mobs, reference water
// malus 8), avoiding lava, fire, cactus, magma, powder snow and fence tops, with a penalty next to fire
// and lava. Mobs wider than a block path with a 2x2 footprint. A mob that faces a target while walking
// (chasing, following food, going to its bed or job site) follows the path instead of pushing straight
// into walls; the path refreshes when the target moves or every few seconds, with a small per-tick budget.
struct PathState {
    var nodes: [IVec3] = []
    var index = 0
    var goal = V3(0, -9999, 0)
    var timer: Float = 0
    var door: IVec3?                          // a door this mob opened and will close behind itself
    var climbUp = false                       // next waypoint is straight up a ladder / vine
    var span = 1                              // footprint of the current path (cells per side)
    var breakTime: Float = 0                  // zombie hammering at a door (12 s on Hard)
    var partial = false                       // the last search ended short of the goal (unreachable)
    var stallPos = V3(0, -9999, 0)            // watchdog: where the mob was when it last made progress
    var stallTime: Float = 0
}

// How one mob moves: body height and footprint in cells, how far it may drop, what water costs it,
// whether it goes through wooden doors and climbs ladders.
struct PathProfile {
    var tall = 2
    var span = 1
    var maxDrop = 3
    var waterCost: Float = 8
    var doors = false
    var climbs = true
}

enum PathFinder {
    static var budget = 0                    // searches left this tick (reset by MobManager.update)
    static var spent: Double = 0             // seconds spent searching this tick (capped at 1.5 ms)
    static var boxes: [(V3, V3)] = []        // scratch for collision boxes (main thread only)
    static var doors = false                 // the current search may walk through wooden doors
    static var lastExpanded = 0              // nodes expanded by the last search (harness)

    // Block reads during one search remember the last chunk (a search reads hundreds of cells in one to four chunks;
    // each read was a dictionary lookup: bench profile, mobs scene). Only while find() runs (main thread); elsewhere
    // blk is World.block.
    private static var cursorOn = false
    private static var cKey = ChunkKey(x: Int.min, z: Int.min)
    private static var cChunk: Chunk?
    @inline(__always) static func blk(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> BlockID {
        guard cursorOn, w.frame == nil, y >= 0, y < CH else { return w.block(x, y, z) }
        let k = ChunkKey(x: floorDiv(x, CS), z: floorDiv(z, CS))
        if k != cKey { cKey = k; cChunk = w.chunkAt(x, z) }
        guard let c = cChunk else { return AIR }
        return c.blocks[Chunk.index(mod(x, CS), y, mod(z, CS))]
    }

    static let climbIds: Set<BlockID> = {
        var s = Set<BlockID>()
        for i in 0..<Blocks.count {
            let base = Int(Blocks.groupBase[i])
            let k = Blocks.key(BlockID(base))
            if Blocks.shape[i] == "ladder" || ["vine", "cave_vines", "cave_vines_plant", "scaffolding", "twisting_vines", "twisting_vines_plant",
                                               "weeping_vines", "weeping_vines_plant"].contains(k) { s.insert(BlockID(i)) }
        }
        return s
    }()
    @inline(__always) static func climbable(_ b: BlockID) -> Bool { climbIds.contains(b) }

    // Height of the collision inside a cell: 0 empty ... 1 full block, up to 1.5 for fences and walls.
    static func solidTop(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> Float {
        let b = Int(blk(w, x, y, z))
        if !Blocks.collide[b] { return 0 }
        if Blocks.fullCollide[b] { return 1 }
        if doors && isWoodDoor(BlockID(b)) { return 0 }
        if climbIds.contains(BlockID(b)) && Blocks.shape[b] == "ladder" { return 0 }     // thin board against the wall
        boxes.removeAll(keepingCapacity: true)
        w.collisionBoxes(x, y, z, &boxes)
        var top: Float = 0
        for (_, hi) in boxes { top = max(top, hi.y - Float(y)) }
        return top
    }

    // A door (open or shut) in the cell at feet or head height.
    // Per block state (string compares on the shape and key ran for every cell a search or a walking mob looked at).
    static let doorTable: [Bool] = (0..<Blocks.count).map { Blocks.shape[$0] == "door" }
    static let woodDoorTable: [Bool] = (0..<Blocks.count).map {
        Blocks.shape[$0] == "door" && !Blocks.key(Blocks.groupBase[$0]).hasPrefix("iron_")
    }
    @inline(__always) static func isDoor(_ b: BlockID) -> Bool { Int(b) < doorTable.count && doorTable[Int(b)] }

    @inline(__always) static func hasDoor(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        isDoor(blk(w, x, y, z)) || isDoor(blk(w, x, y + 1, z))
    }

    // Where to aim inside a door cell: the middle of the gap beside an open door's panel (the cell centre left
    // 1/80 of a block to spare, so villagers coming in a little off-centre clipped the panel and stood in the
    // doorway: behaviour-sim traces, run 374). (0.5, 0.5) for any other cell.
    static func doorAim(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> (Float, Float) {
        guard hasDoor(w, x, y, z) else { return (0.5, 0.5) }
        var fx: Float = 0.5, fz: Float = 0.5
        for yy in y...(y + 1) where isDoor(blk(w, x, yy, z)) {
            boxes.removeAll(keepingCapacity: true)
            w.collisionBoxes(x, yy, z, &boxes)
            for (lo, hi) in boxes {
                let x0 = lo.x - Float(x), x1 = hi.x - Float(x), z0 = lo.z - Float(z), z1 = hi.z - Float(z)
                if x1 - x0 < 0.5 { fx = x0 > 1 - x1 ? x0 / 2 : (x1 + 1) / 2 }
                if z1 - z0 < 0.5 { fz = z0 > 1 - z1 ? z0 / 2 : (z1 + 1) / 2 }
            }
            break
        }
        return (fx, fz)
    }

    static func isWoodDoor(_ b: BlockID) -> Bool { Int(b) < woodDoorTable.count && woodDoorTable[Int(b)] }

    static let powderSnow: BlockID = Blocks.has("powder_snow") ? Blocks.id("powder_snow") : AIR

    @inline(__always) static func danger(_ id: BlockID) -> Bool {
        Blocks.fluidKind[Int(id)] == 2 || Blocks.contactDamage[Int(id)] > 0 || (id == powderSnow && id != AIR)
    }
    @inline(__always) static func burning(_ id: BlockID) -> Bool { Blocks.fluidKind[Int(id)] == 2 || id == FIRE }

    // Cost of standing with the footprint's corner cell at (x, y, z), or nil if the mob can't.
    // Returns (cost, swimming, climbing).
    static func standCost(_ w: World, _ x: Int, _ y: Int, _ z: Int, _ pr: PathProfile) -> Float? {
        var supported = false, wet = false, climb = false
        var cost: Float = 1
        for i in 0..<pr.span { for j in 0..<pr.span {
            let cx = x + i, cz = z + j
            for k in 0..<pr.tall {
                let id = blk(w, cx, y + k, cz)
                if danger(id) { return nil }
                if solidTop(w, cx, y + k, cz) > (k == 0 ? 0.2 : 0.01) { return nil }   // carpets / snow layers are fine underfoot
            }
            let feet = blk(w, cx, y, cz)
            if Blocks.fluidKind[Int(feet)] == 1 { wet = true; supported = true; continue }
            if pr.climbs && pr.span == 1 && climbable(feet) { climb = true; supported = true }
            let below = blk(w, cx, y - 1, cz)
            if danger(below) { return nil }
            let t = solidTop(w, cx, y - 1, cz)
            if t > 1.01 { return nil }                                                   // fence / wall tops can't be jumped onto
            if t > 0.4 { supported = true }
            // Reference DANGER_FIRE / DAMAGE_OTHER malus: cells next to lava, fire or cactus.
            if cost < 9 {
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let n = blk(w, cx + dx, y, cz + dz)
                    if burning(n) || Blocks.contactDamage[Int(n)] > 0 || burning(blk(w, cx + dx, y - 1, cz + dz)) { cost = 9; break }
                }
            }
        } }
        if !supported { return nil }
        if wet { cost += pr.waterCost }
        if climb { cost += 0.5 }
        return cost
    }

    // Column (x, z) (whole footprint) is open from y0 up to y1 (exclusive).
    static func open(_ w: World, _ x: Int, _ z: Int, _ y0: Int, _ y1: Int, span: Int = 1) -> Bool {
        for i in 0..<span { for j in 0..<span {
            var y = y0
            while y < y1 {
                if solidTop(w, x + i, y, z + j) > 0.01 || danger(blk(w, x + i, y, z + j)) { return false }
                y += 1
            }
        } }
        return true
    }

    @inline(__always) static func key(_ p: IVec3) -> Int { (p.x & 0xFFFFF) | ((p.z & 0xFFFFF) << 20) | ((p.y & 0x3FF) << 40) }

    // Compatibility wrapper (harness, simple callers).
    static func find(_ w: World, from: V3, to: V3, tall: Int, maxNodes: Int = 400) -> [IVec3]? {
        var pr = PathProfile()
        pr.tall = tall
        pr.doors = doors
        return find(w, from: from, to: to, profile: pr, maxNodes: maxNodes)
    }

    // Footprint corner cell for a body centred at p.
    static func anchor(_ p: V3, span: Int) -> IVec3 {
        let off: Float = span == 2 ? 1 : 0.5
        return IVec3(Int(floor(p.x - off + 0.5)), Int(floor(p.y + 0.01)), Int(floor(p.z - off + 0.5)))
    }

    // Path from `from` to `to` (feet positions). Returns the waypoints (footprint corner cells) after the
    // start, heading to the goal or, if it can't be reached within the node limit, to the reachable cell
    // closest to it.
    static func find(_ w: World, from: V3, to: V3, profile pr: PathProfile, maxNodes: Int = 400) -> [IVec3]? {
        let start = anchor(from, span: pr.span)
        let goal = anchor(to, span: pr.span)
        if abs(goal.x - start.x) + abs(goal.z - start.z) > 48 { return nil }
        let saveDoors = doors
        doors = pr.doors
        let saveCursor = cursorOn
        cursorOn = true
        cKey = ChunkKey(x: Int.min, z: Int.min); cChunk = nil
        defer { doors = saveDoors; cursorOn = saveCursor; cChunk = nil; cKey = ChunkKey(x: Int.min, z: Int.min) }
        func h(_ p: IVec3) -> Float {
            let dx = Float(p.x - goal.x), dy = Float(p.y - goal.y), dz = Float(p.z - goal.z)
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }
        var pts: [IVec3] = [start]
        var gCost: [Float] = [0]
        var parent: [Int] = [-1]
        var closed: [Bool] = [false]
        var index: [Int: Int] = [key(start): 0]
        var heap: [(Float, Int)] = [(h(start), 0)]
        func push(_ e: (Float, Int)) {
            heap.append(e)
            var i = heap.count - 1
            while i > 0 { let p = (i - 1) / 2; if heap[p].0 <= heap[i].0 { break }; heap.swapAt(p, i); i = p }
        }
        func pop() -> (Float, Int)? {
            guard let top = heap.first else { return nil }
            let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last
                var i = 0
                while true {
                    let l = i * 2 + 1, r = l + 1
                    var m = i
                    if l < heap.count && heap[l].0 < heap[m].0 { m = l }
                    if r < heap.count && heap[r].0 < heap[m].0 { m = r }
                    if m == i { break }
                    heap.swapAt(m, i); i = m
                }
            }
            return top
        }
        func add(_ i: Int, _ q: IVec3, _ c: Float) {
            let ng = gCost[i] + c
            let k = key(q)
            if let j = index[k] {
                if closed[j] || ng >= gCost[j] { return }
                gCost[j] = ng; parent[j] = i
                push((ng + h(q), j))
            } else {
                let j = pts.count
                pts.append(q); gCost.append(ng); parent.append(i); closed.append(false)
                index[k] = j
                push((ng + h(q), j))
            }
        }
        var best = 0, bestH = h(start)
        var expanded = 0
        // A goal one can't stand in (a job site, a bed, a bell): arrive beside it, never on top (behaviour-sim trace,
        // run 361: a fletcher's path ended standing on its fletching table, so it climbed onto it every morning).
        let blocked = pr.span == 1 && standCost(w, goal.x, goal.y, goal.z, pr) == nil
            && !open(w, goal.x, goal.z, goal.y, goal.y + 1, span: 1)
        func arrived(_ p: IVec3) -> Bool {
            if blocked { return abs(p.x - goal.x) + abs(p.z - goal.z) == 1 && abs(p.y - goal.y) <= 1 }
            return p.x == goal.x && p.z == goal.z && abs(p.y - goal.y) <= 1
        }
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let diags = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        var drops: [Int] = [0, 1]
        for d in 1...max(1, pr.maxDrop) { drops.append(-d) }
        while let e = pop() {
            let i = e.1
            if closed[i] { continue }
            closed[i] = true
            let p = pts[i]
            let hp = h(p)
            if hp < bestH { bestH = hp; best = i }
            if arrived(p) { best = i; break }
            expanded += 1
            if expanded > maxNodes { break }
            var flat = [Bool](repeating: false, count: 4)          // orthogonal neighbour reachable on the same level
            for (di, (dx, dz)) in dirs.enumerated() {
                let qx = p.x + dx, qz = p.z + dz
                if blocked && qx == goal.x && qz == goal.z { continue }        // not over the goal block
                for dy in drops {
                    let q = IVec3(qx, p.y + dy, qz)
                    if dy == 1 && !open(w, p.x, p.z, p.y + pr.tall, p.y + pr.tall + 1, span: pr.span) { continue }      // headroom to jump
                    if dy < 0 && !open(w, qx, qz, q.y + pr.tall, p.y + pr.tall, span: pr.span) { continue }             // clear drop column
                    guard let c = standCost(w, qx, q.y, qz, pr) else {
                        // A solid cell at this level ends the search downwards (can't drop through it).
                        if dy < 0 && !open(w, qx, qz, q.y, q.y + 1, span: pr.span) { break }
                        continue
                    }
                    if dy == 0 { flat[di] = true }
                    add(i, q, c + (dy > 0 ? 0.5 : 0) + (dy < 0 ? Float(-dy) * 0.4 : 0))
                    break
                }
            }
            // Diagonals on the same level only when both orthogonal cells are walkable (no corner cutting).
            for (dx, dz) in diags {
                let a = dx > 0 ? 0 : 1, b = dz > 0 ? 2 : 3
                guard flat[a] && flat[b], let c = standCost(w, p.x + dx, p.y, p.z + dz, pr) else { continue }
                // Never diagonally into or out of a doorway (the body clips the frame or an open panel).
                if hasDoor(w, p.x, p.y, p.z) || hasDoor(w, p.x + dx, p.y, p.z + dz) { continue }
                add(i, IVec3(p.x + dx, p.y, p.z + dz), c * 1.4142)
            }
            // Ladders / vines straight up and down; swimming up and down.
            if pr.span == 1 {
                let feet = blk(w, p.x, p.y, p.z)
                let wet = Blocks.fluidKind[Int(feet)] == 1
                if pr.climbs && climbable(feet) || wet {
                    if open(w, p.x, p.z, p.y + pr.tall, p.y + pr.tall + 1), let c = standCost(w, p.x, p.y + 1, p.z, pr) { add(i, IVec3(p.x, p.y + 1, p.z), c) }
                    let down = blk(w, p.x, p.y - 1, p.z)
                    if (pr.climbs && climbable(down)) || Blocks.fluidKind[Int(down)] == 1, let c = standCost(w, p.x, p.y - 1, p.z, pr) { add(i, IVec3(p.x, p.y - 1, p.z), c) }
                }
            }
        }
        lastExpanded = expanded
        guard best != 0 else { return nil }
        var out: [IVec3] = []
        var j = best
        while j > 0 { out.append(pts[j]); j = parent[j] }
        return out.reversed()
    }
}

extension Mob {
    // How this mob paths: monsters chasing at high health accept longer drops (reference getMaxFallDistance).
    func pathProfile(_ g: Game) -> PathProfile {
        var pr = PathProfile()
        pr.tall = max(1, min(3, Int(ceilf(height - 0.05))))
        pr.span = halfW > 0.5 ? 2 : 1
        pr.doors = opensDoors || (breaksDoors && g.difficulty == 3)
        pr.climbs = pr.span == 1
        if kind == .drowned || kind == .guardian || kind == .elderGuardian || kind == .axolotl || kind == .turtle || kind == .frog { pr.waterCost = 0 }
        // Calm garrison soldiers keep the ordinary drop limit with the player near (citadel behaviour sim: a recruit
        // strolling on a tower floor took a 5-block drop down the ladder shaft with the observer overhead).
        let disciplined = kind.steelhold && !aggro
        if kind.hostile && aggro || kind.hostile && !disciplined && simd_length(g.player.pos - pos) < 24 {
            let lost = Int(Float(health) - Float(spec.health) * 0.33) - (3 - g.difficulty) * 4
            pr.maxDrop = 3 + max(0, lost)
        }
        if kind == .chicken || spec.fireImmune && kind == .magmaCube { pr.maxDrop = 16 }   // flutters down / bounces
        return pr
    }

    // Called after the AI picked a walk target (via face) and a positive speed: turn towards the next
    // waypoint of a path to it instead of the target itself.
    func steerAlongPath(_ target: V3, _ dt: Float, _ g: Game, repath: Bool) {
        let w = g.world
        path.timer -= dt
        path.climbUp = false
        let dx = target.x - pos.x, dz = target.z - pos.z
        // Stall watchdog (also in the last 1.5 blocks, where the mob walks straight at the target: a step, a corner or
        // the bed / job block itself kept it pushing there forever). Not while a zombie hammers at a door.
        // Horizontal progress only: hopping in place at a step bobbed 0.8 up and down and reset a 3D check every hop.
        let progress: Float = simd_length(V2(pos.x - path.stallPos.x, pos.z - path.stallPos.z))
        if progress > 0.75 || path.breakTime > 0 { path.stallPos = pos; path.stallTime = 0 } else {
            path.stallTime += dt
            if path.stallTime > 4 { path.stallTime = 0; path.nodes.removeAll(keepingCapacity: true); path.timer = 0; giveUp(target); return }
        }
        if dx * dx + dz * dz < 2.25 && abs(target.y - pos.y) < 1.2 { path.nodes.removeAll(keepingCapacity: true); return }
        let moved = simd_length(target - path.goal) > 1.5
        let done = path.index >= path.nodes.count
        let climbing = PathFinder.climbable(w.block(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z))))
        if (repath || climbing) && path.timer <= 0 && (moved || done || path.timer < -3) && PathFinder.budget > 0 && (Rand.deterministic || PathFinder.spent < 0.0015) {
            PathFinder.budget -= 1
            let t0 = Date.timeIntervalSinceReferenceDate
            defer { PathFinder.spent += Date.timeIntervalSinceReferenceDate - t0 }
            path.timer = Rand.float(in: 0.7...1.3)
            path.goal = target
            let pr = pathProfile(g)
            path.span = pr.span
            // Villagers route around houses and through doors to job sites, beds and the bell 20+ blocks away: 400
            // expanded cells ran out there (they gave up on job sites inside houses over and over).
            path.nodes = PathFinder.find(w, from: pos, to: target, profile: pr, maxNodes: kind == .villager ? 1500 : 400) ?? []
            path.index = 0
            // Partial: the closest reachable cell isn't next to the goal (beds and job sites themselves aren't
            // standable, so a neighbouring cell counts as arriving).
            let ga = PathFinder.anchor(target, span: pr.span)
            if let last = path.nodes.last {
                path.partial = max(abs(last.x - ga.x), abs(last.z - ga.z)) > 1 || abs(last.y - ga.y) > 1
            } else {
                let here = PathFinder.anchor(pos, span: pr.span)
                path.partial = max(abs(here.x - ga.x), abs(here.z - ga.z)) > 1 || abs(here.y - ga.y) > 1
            }
        }
        let off: Float = path.span == 2 ? 1 : 0.5
        while path.index < path.nodes.count {
            let n = path.nodes[path.index]
            let (ax, az) = path.span == 2 ? (off, off) : PathFinder.doorAim(w, n.x, n.y, n.z)
            let cx = Float(n.x) + ax - pos.x, cz = Float(n.z) + az - pos.z
            // Cut ahead early only on straight runs; at turns walk to the cell centre so the body clears corners.
            var straight = false
            if path.index + 1 < path.nodes.count && path.index > 0 {
                let a = path.nodes[path.index - 1], b = path.nodes[path.index + 1]
                straight = b.y == n.y && a.y == n.y && b.x - n.x == n.x - a.x && b.z - n.z == n.z - a.z
            }
            let near: Float = straight ? 0.6 : 0.25
            let vertical = Float(n.y) - pos.y
            if cx * cx + cz * cz < near * near && vertical < 0.6 && vertical > -1.2 { path.index += 1 } else { break }
        }
        if opensDoors || breaksDoors { handleDoors(g, dt) }
        // Can't reach it: at the end of a partial path (or making no progress for 4 s) the mob gives the goal up
        // for a while instead of pushing into the wall in front of it (reference: cant_reach_walk_target memory;
        // behaviour sim: villagers stood stuck against house walls most of the day).
        let sameGoal = simd_length(target - path.goal) < 1.5
        if sameGoal && path.partial && path.index >= path.nodes.count { giveUp(target); return }
        guard path.index < path.nodes.count else { return }
        let n = path.nodes[path.index]
        let (ax, az) = path.span == 2 ? (off, off) : PathFinder.doorAim(w, n.x, n.y, n.z)
        let cx = Float(n.x) + ax - pos.x, cz = Float(n.z) + az - pos.z
        if Float(n.y) > pos.y + 0.3 && cx * cx + cz * cz < 0.36 { path.climbUp = true }
        if cx * cx + cz * cz > 1e-4 { yaw = atan2f(-cx, -cz) }
    }
}

extension Mob {
    // Calm walkers (strolls, villager schedules) skip a goal they couldn't reach for 15 s, then try again.
    func giveUp(_ target: V3) {
        unreachable = target
        unreachableTimer = 15
    }
    func gaveUp(_ p: V3) -> Bool {
        guard unreachableTimer > 0, let u = unreachable else { return false }
        return simd_length(V2(u.x - p.x, u.z - p.z)) < 2 && abs(u.y - p.y) < 3
    }
}

extension Mob {
    // Villagers and illagers open wooden doors on their path and shut them again once through.
    var opensDoors: Bool { [.villager, .wanderingTrader, .pillager, .vindicator, .evoker, .witch, .illusioner].contains(kind) }

    func handleDoors(_ g: Game, _ dt: Float = 0.05) {
        let w = g.world
        if let d = path.door {
            let dx = Float(d.x) + 0.5 - pos.x, dz = Float(d.z) + 0.5 - pos.z
            if dx * dx + dz * dz > 2.6 {
                // Not on someone standing in the doorway (a shut door boxed them in: behaviour sim in_wall, and the
                // village bot pressed against a door a villager closed on it).
                let c = V3(Float(d.x) + 0.5, Float(d.y), Float(d.z) + 0.5)
                func inDoorway(_ p: V3) -> Bool { abs(p.x - c.x) < 0.9 && abs(p.z - c.z) < 0.9 && p.y > c.y - 2 && p.y < c.y + 1.5 }
                let blocked = inDoorway(g.player.pos) || g.mobs.mobs.contains { $0 !== self && inDoorway($0.pos) }
                if !blocked {
                    let b = w.block(d.x, d.y, d.z)
                    if PathFinder.isWoodDoor(b) && Int(b - Blocks.groupBase[Int(b)]) & 4 != 0 { g.toggleOpenable(d) }
                    path.door = nil
                } else if dx * dx + dz * dz > 36 {
                    path.door = nil                         // walked on: leave it open, handle the next door
                }
            }
        }
        guard path.door == nil, path.index < path.nodes.count else { path.breakTime = 0; return }
        let n = path.nodes[path.index]
        let dx = Float(n.x) + 0.5 - pos.x, dz = Float(n.z) + 0.5 - pos.z
        guard dx * dx + dz * dz < 2.3 else { path.breakTime = 0; return }
        for y in [n.y, n.y + 1] {
            let b = w.block(n.x, y, n.z)
            guard PathFinder.isWoodDoor(b) else { continue }
            guard Int(b - Blocks.groupBase[Int(b)]) & 4 == 0 else { break }
            if opensDoors {
                g.toggleOpenable(IVec3(n.x, y, n.z)); path.door = IVec3(n.x, y, n.z)
            } else if breaksDoors && g.difficulty == 3 {
                // Reference: zombies hammer a closed wooden door for 12 s on Hard, then it breaks (no drop).
                let before = Int(path.breakTime)
                path.breakTime += dt
                if Int(path.breakTime) != before { g.sfx(.attack, 0.8, at: V3(Float(n.x) + 0.5, Float(y), Float(n.z) + 0.5)) }
                if path.breakTime >= 12 {
                    path.breakTime = 0
                    for yy in (y - 1)...(y + 1) where PathFinder.isWoodDoor(w.block(n.x, yy, n.z)) { w.setBlock(n.x, yy, n.z, AIR) }
                    g.sfx(.breakBlock(.wood), 1, at: V3(Float(n.x) + 0.5, Float(y), Float(n.z) + 0.5))
                }
            }
            break
        }
    }
}
