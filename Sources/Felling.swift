import Foundation
import simd

// P298 (Oct 15 11:53-11:54, "break the base and the tree falls over, and carry the logs as whole objects").
//   the cut     breaking a log under a tree (logs above it with their leaves, resting on nothing else) fells it: the
//               trunk and crown come loose as one body (a Ship named Felled Tree, held upright by nothing) and topple
//               away from the woodsman with a creak, then land with a crash and a rustle of leaves.
//   the crown   once it lies still the leaves drop away (falling leaf bits, a sapling or a stick now and then, as a
//               decaying crown gives) and the bare trunk is left lying.
//   the trunk   a fallen trunk is chopped where it lies (each log mined drops a log), or, up to 24 logs, picked up
//               with an empty hand (use) and carried in front of you as a whole; use again sets it down (thrown a
//               little the way you look). Logs float.
// Small cuts (under 3 logs or no leaves: stumps, beams, a log cabin wall standing on its sill) don't fell anything.
enum Felling {
    static let name = "Felled Tree"
    static let maxLogs = 260, maxLeaves = 900
    static let carryMax = 24
    final class Fall {
        weak var ship: Ship?
        var age: Float = 0
        var still: Float = 0
        var landed = false
        var lastVel = V3(0, 0, 0)
        init(_ s: Ship) { ship = s }
    }
    static var falls: [Fall] = []
    static weak var carried: Ship?
    static var felled = 0                        // (counter)
    static var toppled = 0                       // (counter: P407's whole pieces)

    static func isFelled(_ s: Ship) -> Bool { s.root.name == name }

    // P297 (d): where the world draws trunks round and thin (ShapeTrunks: polygon and smooth worlds), a felled tree's
    // logs are too: its hull mesh leaves them out (ShipMesh.build) and Game.writeFelled draws them as bark cylinders of
    // the standing tree's girth. As cubes, a broken tree turned into a log far thicker than the tree it was.
    static var roundTrunks = false
    static func roundFor(_ w: World) -> Bool { Mesher.detailMeshes && (SmoothTerrain.enabled || w.fieldTerrain) }
    // Per felled ship: its log cells with the radius each is drawn at (rebuilt when its block count changes).
    static var trunkCells: [Int: (count: Int, cells: [(IVec3, BlockID, Float)])] = [:]
}

extension Game {
    // Game.breakBlock: a log was cut at p.
    func fellCheck(_ p: IVec3, _ cut: BlockID) {
        guard CapitalBase.isLog(cut), dim.dim == .overworld || dim.dim == .deep else { return }
        let start = IVec3(p.x, p.y + 1, p.z)
        guard CapitalBase.isLog(world.block(start.x, start.y, start.z)) else { return }
        // The trunk and limbs above the cut (26-connected logs, never below the cut).
        var logs: Set<IVec3> = [start]
        var queue = [start]
        while let c = queue.popLast() {
            for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0 && dz == 0) {
                let q = IVec3(c.x + dx, c.y + dy, c.z + dz)
                guard q.y > p.y, !logs.contains(q), CapitalBase.isLog(world.block(q.x, q.y, q.z)) else { continue }
                logs.insert(q); queue.append(q)
                if logs.count > Felling.maxLogs { return }
            } } }
        }
        guard logs.count >= 3 else { return }
        Felling.roundTrunks = Felling.roundFor(world)
        // Resting on anything else (another trunk of a 2x2 tree, a wall, the ground beside the cut): it stands.
        for c in logs {
            let below = IVec3(c.x, c.y - 1, c.z)
            if logs.contains(below) || below == p { continue }
            let b = world.block(below.x, below.y, below.z)
            if Blocks.collide[Int(b)] && !CapitalBase.isLog(b) && !CapitalBase.isLeaf(b) { return }
            if CapitalBase.isLog(b) && below.y <= p.y { return }
        }
        // The crown: leaves joined to the logs (6-connected through leaves, within 5 of a log).
        var leaves: Set<IVec3> = []
        var lq: [IVec3] = []
        for c in logs { for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
            let q = c + d
            if !leaves.contains(q) && CapitalBase.isLeaf(world.block(q.x, q.y, q.z)) { leaves.insert(q); lq.append(q) }
        } }
        guard leaves.count >= 4 else { return }
        var head = 0
        while head < lq.count && leaves.count < Felling.maxLeaves {
            let c = lq[head]; head += 1
            for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
                let q = c + d
                guard q.y > p.y, !leaves.contains(q), CapitalBase.isLeaf(world.block(q.x, q.y, q.z)) else { continue }
                guard logs.contains(where: { abs($0.x - q.x) + abs($0.y - q.y) + abs($0.z - q.z) <= 5 }) else { continue }
                leaves.insert(q); lq.append(q)
            }
        }
        // The body: its cells relative to the block above the cut, then out of the world.
        let bp = Blueprint()
        var lo = IVec3(Int.max, Int.max, Int.max)
        for c in logs.union(leaves) {
            bp.cells[ivSub(c, start)] = world.block(c.x, c.y, c.z)
            lo = IVec3(min(lo.x, c.x - start.x), min(lo.y, c.y - start.y), min(lo.z, c.z - start.z))
        }
        for c in leaves { world.setBlockAsync(c.x, c.y, c.z, AIR) }
        for c in logs { world.setBlockAsync(c.x, c.y, c.z, AIR) }
        let s = world.ships.spawn(bp, at: V3(Float(start.x), Float(start.y), Float(start.z)), yaw: 0, name: Felling.name, role: "")
        s.role = nil
        // Local cell (c - start - lo) sits where it stood: world = pos + (l - com).
        s.pos = V3(Float(start.x + lo.x), Float(start.y + lo.y), Float(start.z + lo.z)) + s.com
        s.prevPos = s.pos
        s.updateBounds()
        s.initialBlocks = s.blockCount
        // It goes over away from the woodsman (a nudge at the top; gravity does the rest).
        var away = V3(Float(p.x) + 0.5 - player.pos.x, 0, Float(p.z) + 0.5 - player.pos.z)
        if simd_length(away) < 0.1 { away = V3(-sinf(player.yaw), 0, -cosf(player.yaw)) }
        away = simd_normalize(away)
        s.angVel = simd_cross(V3(0, 1, 0), away) * 0.35
        s.vel = away * 0.4
        Felling.falls.append(Felling.Fall(s))
        Felling.felled += 1
        let mid = s.pos
        sfx(.hullCreak, 1.3, at: mid)
        sfx(.breakBlock(.wood), 1.2, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
    }

    // P407: a piece the load check found held by nothing (Structure.drop, Structure.loose) comes down whole: one body,
    // drawn with its own mesh the whole way (a tree keeps its leaf blobs and round trunk, a tower its walls), tipping
    // away from him. A tree takes its crown along and lies as a felled trunk once still; anything else lies where it lands.
    static let toppledName = "Toppled"
    func topple(_ cells: [IVec3]) {
        guard let start = cells.min(by: { ($0.y, $0.x, $0.z) < ($1.y, $1.x, $1.z) }) else { return }
        let logs = cells.filter { CapitalBase.isLog(world.block($0.x, $0.y, $0.z)) }
        var leaves: Set<IVec3> = []
        if !logs.isEmpty {
            let body = Set(cells)
            var lq: [IVec3] = []
            for c in logs { for d in World.allDirs {
                let q = c + d
                if !body.contains(q) && !leaves.contains(q) && CapitalBase.isLeaf(world.block(q.x, q.y, q.z)) { leaves.insert(q); lq.append(q) }
            } }
            var head = 0
            while head < lq.count && leaves.count < Felling.maxLeaves {
                let c = lq[head]; head += 1
                for d in World.allDirs {
                    let q = c + d
                    guard !leaves.contains(q), !body.contains(q), CapitalBase.isLeaf(world.block(q.x, q.y, q.z)) else { continue }
                    guard logs.contains(where: { abs($0.x - q.x) + abs($0.y - q.y) + abs($0.z - q.z) <= 5 }) else { continue }
                    leaves.insert(q); lq.append(q)
                }
            }
        }
        let bp = Blueprint()
        var lo = IVec3(Int.max, Int.max, Int.max)
        for c in leaves.union(cells) {
            bp.cells[ivSub(c, start)] = world.block(c.x, c.y, c.z)
            lo = IVec3(min(lo.x, c.x - start.x), min(lo.y, c.y - start.y), min(lo.z, c.z - start.z))
        }
        // (taken out quietly: what it leaves behind was checked already)
        world.restoring = true
        for c in leaves { world.setBlockAsync(c.x, c.y, c.z, AIR) }
        for c in cells { world.setBlockAsync(c.x, c.y, c.z, AIR) }
        world.restoring = false
        let tree = logs.count == cells.count
        let s = world.ships.spawn(bp, at: V3(Float(start.x), Float(start.y), Float(start.z)), yaw: 0,
                                  name: tree ? Felling.name : Game.toppledName, role: "")
        s.role = nil
        s.pos = V3(Float(start.x + lo.x), Float(start.y + lo.y), Float(start.z + lo.z)) + s.com
        s.prevPos = s.pos
        s.updateBounds()
        s.initialBlocks = s.blockCount
        var away = V3(s.pos.x - player.pos.x, 0, s.pos.z - player.pos.z)
        if simd_length(away) < 0.1 { away = V3(-sinf(player.yaw), 0, -cosf(player.yaw)) }
        away = simd_normalize(away)
        s.angVel = simd_cross(V3(0, 1, 0), away) * (tree ? 0.35 : 0.15)
        s.vel = away * 0.2
        Felling.falls.append(Felling.Fall(s))
        Felling.toppled += 1
        sfx(.hullCreak, tree ? 1.3 : 0.8, at: s.pos)
    }

    // Every frame (Game.advance): falling trees land and shed their leaves; a carried trunk follows the hands.
    func fellingTick(_ dt: Float) {
        guard dt > 0 else { return }
        Felling.roundTrunks = Felling.roundFor(world)
        let live = world.ships.list
        Felling.falls.removeAll { f in f.ship.map { s in !live.contains { $0 === s } } ?? true }
        for f in Felling.falls {
            guard let s = f.ship else { continue }
            f.age += dt
            let dv = simd_length(s.vel - f.lastVel)
            f.lastVel = s.vel
            if !f.landed && f.age > 0.4 && s.contacts > 0 && dv > 2.5 {
                f.landed = true
                sfx(.shipCollideHard, min(2, 0.8 + dv / 6), at: s.pos)
                sfx(.plantBrush, 1.4, at: s.pos)
                let d = simd_length(player.pos - s.pos)
                if d < 30 { addShake(0.35 * (1 - d / 30)) }
            }
            let resting = simd_length(s.vel) < 0.4 && simd_length(s.angVel) < 0.25
            f.still = resting ? f.still + dt : 0
            if (f.still > 1.5 && f.age > 2) || f.age > 9 { shedLeaves(f) }
        }
        Felling.falls.removeAll { $0.ship == nil || $0.age < 0 }
        // The carried trunk: held 2 blocks ahead at chest height, out of everyone's way.
        if let s = Felling.carried {
            guard alive, world.ships.list.contains(where: { $0 === s }) else { dropCarried(throwing: false); return }
            let flat = simd_normalize(V3(player.look.x, 0, player.look.z) + V3(0.0001, 0, 0))
            let want = player.eye + flat * 2.2 + V3(0, -0.7, 0)
            s.kinematic = true
            s.vel = (want - s.pos) * min(12, 1 / dt)
            // Turned across the view, lying level.
            let yaw = player.yaw + .pi / 2
            let target = Quat(angle: yaw, axis: V3(0, 1, 0)) * Felling.lying(s)
            s.rot = simd_slerp(s.rot, target, min(1, dt * 8))
            s.angVel = .zero
        }
    }

    // The crown falls away: the bare trunk (logs only) replaces the tree where it lies.
    private func shedLeaves(_ f: Felling.Fall) {
        f.age = -1                                           // (done with this fall)
        guard let s = f.ship else { return }
        let g = s.grid
        let bp = Blueprint()
        var lo = IVec3(Int.max, Int.max, Int.max)
        var leafCells: [(IVec3, BlockID)] = []
        for i in 0..<g.blocks.count where g.blocks[i] != AIR {
            let c = IVec3(i % g.sx, i / (g.sx * g.sz), (i / g.sx) % g.sz)
            if CapitalBase.isLeaf(g.blocks[i]) { leafCells.append((c, g.blocks[i])); continue }
            bp.cells[c] = g.blocks[i]
            lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z))
        }
        guard !leafCells.isEmpty else { return }
        // Leaf bits fluttering down, and what a decaying crown gives now and then.
        for (k, (c, b)) in leafCells.enumerated() {
            let at = s.toWorld(V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5)
            if k % 3 == 0 { particles.blockBreak(b, at: IVec3(Int(floor(at.x)), Int(floor(at.y)), Int(floor(at.z)))) }
            if survival { for st in Mining.drops(b, .empty) { drops.spawn(st, at: at) } }
        }
        sfx(.plantBrush, 1.2, at: s.pos)
        guard !bp.cells.isEmpty else { world.ships.remove(s); return }
        let t = world.ships.spawn(bp, at: s.pos, yaw: 0, name: Felling.name, role: "")
        t.role = nil
        t.rot = s.rot
        t.pos = s.pos + s.rot.act(V3(Float(lo.x), Float(lo.y), Float(lo.z)) - s.com + t.com)
        t.prevPos = t.pos; t.prevRot = t.rot
        t.vel = s.vel; t.angVel = s.angVel
        t.updateBounds()
        t.initialBlocks = t.blockCount
        world.ships.remove(s)
    }

    // Ship interaction (use) on a felled trunk: pick it up (empty hand or a non-block item), or set the carried one down.
    func fellUse(_ s: Ship, sneak: Bool) -> Bool {
        if let c = Felling.carried, c === s.root { dropCarried(throwing: true); return true }
        guard Felling.isFelled(s), !sneak, held.def.block == nil, Felling.carried == nil else { return false }
        let r = s.root
        guard !Felling.falls.contains(where: { $0.ship === r }) else { return false }      // (still falling)
        guard r.blockCount <= Felling.carryMax else {
            sfx(.hit(.wood), 0.8, at: r.pos)                  // too heavy: a dull knock (chop it down to size)
            return true
        }
        Felling.carried = r
        ShipManager.ghosts.insert(r.id)
        sfx(.hit(.wood), 1, at: r.pos)
        sfx(.place(.wood), 0.8, at: r.pos)
        return true
    }

    // P297 (d): felled trunks as round bark cylinders (entity pass, both renderers): each log cell a segment along its
    // axis, ring caps where the log ends, lit by the light where it lies.
    func writeFelled(_ wr: inout EntityWriter, eye: V3) {
        guard Felling.roundTrunks else { return }
        let ships = world.ships.list.filter { Felling.isFelled($0) }
        if ships.isEmpty { if !Felling.trunkCells.isEmpty { Felling.trunkCells.removeAll() }; return }
        let n = 8
        let texT = Blocks.tex
        for s in ships where simd_length(s.pos - eye) < 112 {
            let g = s.grid
            if Felling.trunkCells[s.id]?.count != s.blockCount {
                // The trunk (vertical runs of 3 or more) at the standing tree's girth, limbs as limbs.
                var cells: [(IVec3, BlockID, Float)] = []
                for i in 0..<g.blocks.count where ShapeTrunks.isTrunk[Int(g.blocks[i])] {
                    let c = IVec3(i % g.sx, i / (g.sx * g.sz), (i / g.sx) % g.sz)
                    let b = g.blocks[i]
                    var run = 1
                    if ShapeTrunks.axisOf[Int(b)] == 1 {
                        var y = c.y - 1
                        while y >= 0 && ShapeTrunks.isTrunk[Int(g.get(c.x, y, c.z))] && ShapeTrunks.axisOf[Int(g.get(c.x, y, c.z))] == 1 { run += 1; y -= 1 }
                        y = c.y + 1
                        while y < g.sy && ShapeTrunks.isTrunk[Int(g.get(c.x, y, c.z))] && ShapeTrunks.axisOf[Int(g.get(c.x, y, c.z))] == 1 { run += 1; y += 1 }
                    }
                    cells.append((c, b, run >= 3 ? ShapeTrunks.treeRadius(run + 1) : 0.13))
                }
                Felling.trunkCells[s.id] = (s.blockCount, cells)
            }
            guard let cells = Felling.trunkCells[s.id]?.cells else { continue }
            for (c, b, r) in cells {
                let ax = Int(ShapeTrunks.axisOf[Int(b)])
                let d = ax == 0 ? V3(1, 0, 0) : (ax == 1 ? V3(0, 1, 0) : V3(0, 0, 1))
                let u = ax == 1 ? V3(1, 0, 0) : V3(0, 1, 0), v = simd_cross(d, u)
                let mid = V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5
                let wc = s.toWorld(mid)
                let l = world.lightAt(Int(floor(wc.x)), Int(floor(wc.y)), Int(floor(wc.z)))
                let light = max(0.2, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
                let bark = Int(texT[Int(b) * 6 + (ax == 0 ? 2 : 0)]), ring = Int(texT[Int(b) * 6 + ax * 2])
                let a0 = mid - d * 0.5, a1 = mid + d * 0.5
                func w(_ p: V3) -> V3 { s.toWorld(p) - eye }
                for k in 0..<n {
                    let t0 = Float(k) / Float(n) * 2 * .pi, t1 = Float(k + 1) / Float(n) * 2 * .pi
                    let o0 = (u * cosf(t0) + v * sinf(t0)) * r, o1 = (u * cosf(t1) + v * sinf(t1)) * r
                    let nrm = s.rot.act(simd_normalize(o0 + o1))
                    let sh = light * (0.7 + 0.3 * nrm.y)
                    let col = V4(sh, sh, sh, 1)
                    let ua = Float(k) / Float(n), ub = Float(k + 1) / Float(n)
                    wr.quad4(w(a0 + o0), w(a0 + o1), w(a1 + o1), w(a1 + o0), V2(ua, 1), V2(ub, 1), V2(ub, 0), V2(ua, 0), bark, col)
                }
                // Ring caps where the log ends along its axis.
                for (end, sgn) in [(a0, Float(-1)), (a1, Float(1))] {
                    let nb = c + IVec3(ax == 0 ? Int(sgn) : 0, ax == 1 ? Int(sgn) : 0, ax == 2 ? Int(sgn) : 0)
                    let nbB = g.get(nb.x, nb.y, nb.z)
                    if ShapeTrunks.isTrunk[Int(nbB)] && ShapeTrunks.axisOf[Int(nbB)] == UInt8(ax) { continue }
                    let ny = s.rot.act(d * sgn).y
                    let sh = light * (0.7 + 0.3 * ny)
                    for k in 0..<n {
                        let t0 = Float(k) / Float(n) * 2 * .pi, t1 = Float(k + 1) / Float(n) * 2 * .pi
                        let o0 = u * cosf(t0) + v * sinf(t0), o1 = u * cosf(t1) + v * sinf(t1)
                        let c0 = V2(0.5, 0.5), p0 = V2(0.5 + 0.5 * cosf(t0), 0.5 + 0.5 * sinf(t0)), p1 = V2(0.5 + 0.5 * cosf(t1), 0.5 + 0.5 * sinf(t1))
                        wr.quad4(w(end), w(end + o0 * r), w(end + o1 * r), w(end), c0, p0, p1, c0, ring, V4(sh, sh, sh, 1))
                    }
                }
            }
        }
    }

    func dropCarried(throwing: Bool) {
        guard let s = Felling.carried else { return }
        Felling.carried = nil
        ShipManager.ghosts.remove(s.id)
        s.kinematic = false
        s.vel = throwing ? player.look * 3 + player.vel : .zero
        sfx(.place(.wood), 0.9, at: s.pos)
    }
}

extension Felling {
    // The turn that lays a trunk along its length, level (its longest side along x).
    static func lying(_ s: Ship) -> Quat {
        let e = s.localMax - s.localMin
        if e.y >= e.x && e.y >= e.z { return Quat(angle: .pi / 2, axis: V3(0, 0, 1)) }     // upright trunk: on its side
        if e.z > e.x { return Quat(angle: .pi / 2, axis: V3(0, 1, 0)) }
        return Quat(angle: 0, axis: V3(0, 1, 0))
    }
}

extension ShipManager {
    // Ships nothing collides with (a trunk being carried).
    static var ghosts = Set<Int>()
}
