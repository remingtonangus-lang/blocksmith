import Foundation
import simd

// Ground navigation for mobs: A* over block cells (walk, step or jump up one block, drop up to three,
// swim), avoiding lava, fire, cactus and fence tops. A mob that faces a target while walking (chasing,
// following food, going to its bed or job site) follows the path instead of pushing straight into
// walls; the path refreshes when the target moves or every few seconds, with a small per-tick budget.
struct PathState {
    var nodes: [IVec3] = []
    var index = 0
    var goal = V3(0, -9999, 0)
    var timer: Float = 0
}

enum PathFinder {
    static var budget = 0                    // searches left this tick (reset by MobManager.update)
    static var boxes: [(V3, V3)] = []        // scratch for collision boxes (main thread only)

    // Height of the collision inside a cell: 0 empty ... 1 full block, up to 1.5 for fences and walls.
    static func solidTop(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> Float {
        let b = Int(w.block(x, y, z))
        if !Blocks.collide[b] { return 0 }
        if Blocks.fullCollide[b] { return 1 }
        boxes.removeAll(keepingCapacity: true)
        w.collisionBoxes(x, y, z, &boxes)
        var top: Float = 0
        for (_, hi) in boxes { top = max(top, hi.y - Float(y)) }
        return top
    }

    @inline(__always) static func danger(_ id: BlockID) -> Bool {
        Blocks.fluidKind[Int(id)] == 2 || Blocks.contactDamage[Int(id)] > 0
    }

    // Cost of standing with feet in cell (x, y, z) for a mob `tall` cells high, or nil if it can't.
    static func standCost(_ w: World, _ x: Int, _ y: Int, _ z: Int, tall: Int) -> Float? {
        for k in 0..<tall {
            let id = w.block(x, y + k, z)
            if danger(id) { return nil }
            if solidTop(w, x, y + k, z) > (k == 0 ? 0.2 : 0.01) { return nil }   // carpets / snow layers are fine underfoot
        }
        let feet = w.block(x, y, z)
        if Blocks.fluidKind[Int(feet)] == 1 { return 4 }                          // swimming: allowed, not preferred
        let below = w.block(x, y - 1, z)
        if danger(below) { return nil }
        let t = solidTop(w, x, y - 1, z)
        if t > 1.01 { return nil }                                                 // fence / wall tops can't be jumped onto
        return t > 0.4 ? 1 : nil
    }

    // Column (x, z) is open from y0 up to y1 (exclusive).
    static func open(_ w: World, _ x: Int, _ z: Int, _ y0: Int, _ y1: Int) -> Bool {
        var y = y0
        while y < y1 {
            if solidTop(w, x, y, z) > 0.01 || danger(w.block(x, y, z)) { return false }
            y += 1
        }
        return true
    }

    @inline(__always) static func key(_ p: IVec3) -> Int { (p.x & 0xFFFFF) | ((p.z & 0xFFFFF) << 20) | ((p.y & 0x3FF) << 40) }

    // Path from `from` to `to` (feet positions). Returns the waypoints after the start cell, heading to
    // the goal or, if it can't be reached within the node limit, to the reachable cell closest to it.
    static func find(_ w: World, from: V3, to: V3, tall: Int, maxNodes: Int = 600) -> [IVec3]? {
        let start = IVec3(Int(floor(from.x)), Int(floor(from.y + 0.01)), Int(floor(from.z)))
        let goal = IVec3(Int(floor(to.x)), Int(floor(to.y + 0.01)), Int(floor(to.z)))
        if abs(goal.x - start.x) + abs(goal.z - start.z) > 48 { return nil }
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
        var best = 0, bestH = h(start)
        var expanded = 0
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        while let e = pop() {
            let i = e.1
            if closed[i] { continue }
            closed[i] = true
            let p = pts[i]
            let hp = h(p)
            if hp < bestH { bestH = hp; best = i }
            if p.x == goal.x && p.z == goal.z && abs(p.y - goal.y) <= 1 { best = i; break }
            expanded += 1
            if expanded > maxNodes { break }
            for (dx, dz) in dirs {
                let qx = p.x + dx, qz = p.z + dz
                var found: (IVec3, Float)? = nil
                for dy in [0, 1, -1, -2, -3] {
                    let q = IVec3(qx, p.y + dy, qz)
                    if dy == 1 && !open(w, p.x, p.z, p.y + tall, p.y + tall + 1) { continue }        // headroom to jump
                    if dy < 0 && !open(w, qx, qz, q.y + tall, p.y + tall) { continue }              // clear drop column
                    guard let c = standCost(w, qx, q.y, qz, tall: tall) else { continue }
                    found = (q, c + (dy > 0 ? 0.5 : 0) + (dy < 0 ? Float(-dy) * 0.4 : 0))
                    break
                }
                guard let f = found else { continue }
                let (q, c) = f
                let ng = gCost[i] + c
                let k = key(q)
                if let j = index[k] {
                    if closed[j] || ng >= gCost[j] { continue }
                    gCost[j] = ng; parent[j] = i
                    push((ng + h(q), j))
                } else {
                    let j = pts.count
                    pts.append(q); gCost.append(ng); parent.append(i); closed.append(false)
                    index[k] = j
                    push((ng + h(q), j))
                }
            }
        }
        guard best != 0 else { return nil }
        var out: [IVec3] = []
        var j = best
        while j > 0 { out.append(pts[j]); j = parent[j] }
        return out.reversed()
    }
}

extension Mob {
    // Called after the AI picked a walk target (via face) and a positive speed: turn towards the next
    // waypoint of a path to it instead of the target itself.
    func steerAlongPath(_ target: V3, _ dt: Float, _ w: World) {
        path.timer -= dt
        let dx = target.x - pos.x, dz = target.z - pos.z
        if dx * dx + dz * dz < 2.25 && abs(target.y - pos.y) < 1.2 { path.nodes.removeAll(keepingCapacity: true); return }
        let moved = simd_length(target - path.goal) > 1.5
        let done = path.index >= path.nodes.count
        if path.timer <= 0 && (moved || done || path.timer < -3) && PathFinder.budget > 0 {
            PathFinder.budget -= 1
            path.timer = Float.random(in: 0.7...1.3)
            path.goal = target
            path.nodes = PathFinder.find(w, from: pos, to: target, tall: max(1, min(3, Int(ceilf(height - 0.05))))) ?? []
            path.index = 0
        }
        while path.index < path.nodes.count {
            let n = path.nodes[path.index]
            let cx = Float(n.x) + 0.5 - pos.x, cz = Float(n.z) + 0.5 - pos.z
            let near: Float = path.index + 1 < path.nodes.count && path.nodes[path.index + 1].y == n.y ? 0.6 : 0.35
            if cx * cx + cz * cz < near * near && abs(Float(n.y) - pos.y) < 1.2 { path.index += 1 } else { break }
        }
        guard path.index < path.nodes.count else { return }
        let n = path.nodes[path.index]
        let cx = Float(n.x) + 0.5 - pos.x, cz = Float(n.z) + 0.5 - pos.z
        if cx * cx + cz * cz > 1e-4 { yaw = atan2f(-cx, -cz) }
    }
}
