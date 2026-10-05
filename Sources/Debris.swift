import Foundation
import simd

// Falling debris (Destruction.swift): world blocks cut loose into free-moving bodies, their crashes, and laying them
// back into the world once they rest. Also the capital hulls' full split check (a frigate cut in two).
extension ShipManager {
    var debrisCount: Int { list.reduce(0) { $0 + ($1.debris ? 1 : 0) } }

    // Runs the support analysis round cells just emptied (an explosion's holes, a block a falling piece broke) and sets
    // whatever fails moving. Returns the number of bodies made.
    @discardableResult
    // `asBuilt`: what already stood unsupported before the damage (as the world generated it: a monument's hall roofs,
    // an end city's overhangs, a ruin's arches) stands on; only what the damage cut from its support falls. Off for the
    // gaps a settle check leaves (what rested on falling debris goes with it).
    func collapse(around holes: [IVec3], game: Game?, from blast: V3? = nil, seeds: [IVec3] = [], only: Set<IVec3>? = nil,
                  asBuilt: Bool = true) -> Int {
        guard !holes.isEmpty || !seeds.isEmpty else { return 0 }
        let t0 = CFAbsoluteTimeGetCurrent()
        var r = Collapse.analyze(world, around: holes, seeds: seeds)
        if asBuilt && only == nil && !holes.isEmpty && !r.falling.isEmpty {
            // The same search with the holes filled back in: pieces that fail then too were never held, and stay.
            let falling = r.falling.flatMap { $0 }
            // Cells already found standing unsupported as built skip the second search (mining on through a big old
            // hall would otherwise search it twice a block).
            var pre = Set<IVec3>()
            if falling.allSatisfy({ asBuiltCells.get($0) != nil }) {
                pre = Set(falling)
            } else {
                let before = Collapse.analyze(world, around: [], seeds: falling, restore: Collapse.standIns(world, holes))
                for p in before.falling { for c in p { pre.insert(c) } }
                if asBuiltCells.count + pre.count > 200_000 { asBuiltCells = Collapse.CellTable(capacity: 4096) }
                for c in pre { _ = asBuiltCells.insert(c, 0) }
            }
            if !pre.isEmpty {
                var now = falling.filter { !pre.contains($0) }
                // As-built pieces stay unless the damage cut what joined them to the rest (the pillar under an old
                // overhang mined away): one that touched what now falls, or a hole that met the ground or the standing
                // structure, and touches neither any longer, goes with the rest. (A generated hulk that never touched
                // anything, mined into, keeps standing as it stood.)
                let fallingSet = Set(falling), gone = Set(now), holeSet = Set(holes)
                func holds(_ n: IVec3) -> Bool {
                    if holeSet.contains(n) || gone.contains(n) { return false }
                    let b = world.rawBlock(n.x, n.y, n.z)
                    return BlockMaterial.anchors(b) || (Collapse.built(b) && !fallingSet.contains(n))
                }
                var linkHoles = Set<IVec3>()
                for h in holes where Collapse.dirs6.contains(where: { holds(h + $0) }) { linkHoles.insert(h) }
                let stay = falling.filter { pre.contains($0) }
                for piece in Collapse.pieces(stay) {
                    var cut = false, joined = false
                    for c in piece {
                        for d in Collapse.dirs6 {
                            let n = c + d
                            if gone.contains(n) || linkHoles.contains(n) { cut = true } else if holds(n) { joined = true }
                        }
                        if joined { break }
                    }
                    if cut && !joined { now += piece } else { asBuiltKept += piece.count }
                }
                r.falling = now.isEmpty ? [] : Collapse.pieces(now)
            }
        }
        if let keep = only {
            // A settle check cuts only the blocks just laid down, never the structure they came to rest on.
            var kept: [[IVec3]] = []
            for piece in r.falling {
                let mine = piece.filter { c in keep.contains(c) }
                if !mine.isEmpty { kept += Collapse.pieces(mine) }
            }
            r.falling = kept
            r.tip = []
        }
        var made = 0
        for p in r.falling {
            // A piece knocked loose by a blast gets a shove away from it.
            var push = V3(0, 0, 0)
            if let b = blast, let c = p.first {
                let away = V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5 - b
                push = simd_normalize(away + V3(0, 0.01, 0)) * min(3, 12 / max(1, simd_length(away)))
            }
            if cutLoose(p, game: game, push: push) != nil { made += 1 }
        }
        for t in r.tip {
            if cutLoose(t.cells, game: game, spin: t.axis * 0.3) != nil { made += 1 }
        }
        // A settle check's cut can leave blocks laid down earlier hanging from nothing (they rested on what fell): the
        // gaps it left get the ordinary check next frame (collapse check tower: 6 bricks left floating).
        if only != nil && !r.falling.isEmpty {
            var gaps: [IVec3] = []
            for p in r.falling { gaps += p }
            queueCollapse(gaps, from: nil, asBuilt: false)
        }
        collapseMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        spentMs["support", default: 0] += collapseMs
        if made > 0 { collapses += 1 }
        return made
    }

    // Holes to check next frame: every blast of a frame is checked together, at most one check a frame (a salvo on a
    // big building can't stack up a dozen 6000-cell searches in one frame).
    func queueCollapse(_ holes: [IVec3], from: V3?, asBuilt: Bool = true) {
        if collapseQueue.count < 64 { collapseQueue.append((holes, from, asBuilt)) }
    }

    // World cells into a free-moving body (keeps their place; pieces under Collapse.minPiece blocks just break).
    @discardableResult
    func cutLoose(_ cells: [IVec3], game: Game?, push: V3 = .zero, spin: V3 = .zero) -> Ship? {
        let w = world
        var solid: [(IVec3, BlockID)] = []
        solid.reserveCapacity(cells.count)
        for c in cells {
            let b = w.rawBlock(c.x, c.y, c.z)
            if b != AIR && !Blocks.isLiquid(b) { solid.append((c, b)) }
        }
        if solid.isEmpty { return nil }
        if solid.count < Collapse.minPiece {
            for (c, b) in solid { breakBlock(c, b, game: game) }
            return nil
        }
        var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
        for (c, _) in solid { lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)); hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z)) }
        let g = ShipGrid(sx: hi.x - lo.x + 1, sy: hi.y - lo.y + 1, sz: hi.z - lo.z + 1)
        let s = Ship(id: newId(), grid: g)
        for (c, b) in solid {
            g.set(c.x - lo.x, c.y - lo.y, c.z - lo.z, b)
            if let be = w.blockEntities.removeValue(forKey: c) { s.blockEntities[ivSub(c, lo)] = be }
        }
        for (c, _) in solid { _ = w.setBlockAsync(c.x, c.y, c.z, AIR) }
        for (c, _) in solid { w.scheduleFluid(around: c) }          // water flows into the gap it left
        s.name = "Debris"
        s.debris = true
        s.rebuild()
        s.pos = V3(Float(lo.x), Float(lo.y), Float(lo.z)) + s.com
        s.prevPos = s.pos; s.prevRot = s.rot
        s.gridOrigin = lo
        s.vel = push
        s.angVel = spin
        s.updateBounds()
        add(s)
        s.mesh.rebuildAll(s, device: w.device, queue: meshQueue)
        // Over the cap: the oldest pieces are laid down where they are.
        var bodies = list.filter { $0.debris }
        while bodies.count > Collapse.maxDebris {
            guard let oldest = bodies.max(by: { $0.age < $1.age }) else { break }
            bake(oldest, game: game)
            bodies.removeAll { $0 === oldest }
        }
        return s
    }

    // A block shattered by debris or too small a piece: gone, a drop now and then, a puff.
    func breakBlock(_ c: IVec3, _ b: BlockID, game: Game?) {
        _ = world.setBlockAsync(c.x, c.y, c.z, AIR)
        world.scheduleFluid(around: c)
        guard let g = game else { return }
        let at = V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5
        if Rand.float(in: 0..<1) < 0.35 { for st in Mining.drops(b, .empty) { g.drops.spawn(st, at: at) } }
        g.particles.smoke(at: at, dark: false)
    }

    // Every frame after the physics step: rest detection and laying down, hits on bodies, the capital split checks.
    func debrisTick(_ dt: Float, game: Game?) {
        if !collapseQueue.isEmpty {
            // This frame's blasts together (holes of later frames wait).
            var holes: [IVec3] = []
            var from: V3?
            var n = 0, asBuilt = true
            while n < collapseQueue.count && holes.count < 4000 {
                holes += collapseQueue[n].0
                from = from ?? collapseQueue[n].1
                asBuilt = asBuilt && collapseQueue[n].2
                n += 1
            }
            collapseQueue.removeFirst(n)
            collapse(around: holes, game: game, from: from, asBuilt: asBuilt)
        } else if !settleQueue.isEmpty {
            // Pieces just laid down: whatever of them overhangs further than it spans breaks off and falls again (a
            // toppled tower lying across its own stump).
            let cells = settleQueue
            settleQueue.removeAll(keepingCapacity: true)
            collapse(around: [], game: game, seeds: cells, only: Set(cells))
        }
        for s in list where s.kinematic && s.parent == nil && s.splitCheck >= 0 {
            s.splitCheck -= dt
            if s.splitCheck < 0 { splitHull(s, game: game) }
        }
        if let j = bakeJobs.first { bakeStep(j, game: game) }
        for s in list where s.debris && s.parent == nil && !s.baking {
            s.age += dt
            s.hitCD -= dt
            let speed = simd_length(s.vel), spin = simd_length(s.angVel)
            if speed < 0.3 && spin < 0.2 { s.restTime += dt } else { s.restTime = 0 }
            // A crash: dust along its underside and a thud, louder the harder it hit.
            let drop = s.lastSpeed - speed
            s.lastSpeed = speed
            if drop > 4, let g = game {
                let lo = s.worldMin, hi = s.worldMax
                let n = min(12, 2 + s.blockCount / 40)
                for _ in 0..<n {
                    let at = V3(Rand.float(in: lo.x...max(lo.x, hi.x)), lo.y + 0.5, Rand.float(in: lo.z...max(lo.z, hi.z)))
                    g.particles.smoke(at: at, dark: false)
                }
                g.sfx(.shipCollideHard, min(2, 0.5 + drop * 0.1), at: V3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5))
            }
            // (Asleep over ground that isn't loaded, it waits where it is: laid down there it would hang in the air.)
            let groundIn = world.isLoaded(Int(floor(s.pos.x)), Int(floor(s.pos.z)))
            if (s.restTime > 1.2 && groundIn) || (s.age > 40 && groundIn) || (s.asleep && s.age > 1 && groundIn) {
                // A big section of a capital hull stays as a wreck (salvage, overgrowth); other debris just lies there.
                if s.blockCount > 200 && s.name.hasSuffix(" section") { makeWreck(s, kind: "section", game: game) } else { bake(s, game: game) }
                continue
            }
            if let g = game, speed > 3, s.hitCD <= 0 { debrisHits(s, g) }
        }
        // Blocks the debris smashed this frame (ShipPhysics.step collects them) and what they brought down.
        if !smashed.isEmpty {
            let cells = smashed
            smashed.removeAll(keepingCapacity: true)
            var holes: [IVec3] = []
            for c in cells.prefix(32) {
                let b = world.rawBlock(c.x, c.y, c.z)
                if b == AIR { continue }
                breakBlock(c, b, game: game)
                holes.append(c)
            }
            if let g = game, let c = holes.first { g.sfx(.shipCollideHard, 1, at: V3(Float(c.x), Float(c.y), Float(c.z))) }
            collapse(around: holes, game: game)
        }
    }

    // A fast-moving piece hurts the bodies it runs into (the player, mobs): by how fast it hits them.
    private func debrisHits(_ s: Ship, _ g: Game) {
        func touches(_ p: V3, _ hw: Float, _ h: Float) -> Bool {
            if p.x + hw < s.worldMin.x || p.x - hw > s.worldMax.x || p.z + hw < s.worldMin.z || p.z - hw > s.worldMax.z
                || p.y + h < s.worldMin.y || p.y > s.worldMax.y { return false }
            for dy in [Float(0.2), h * 0.5, h - 0.2] {
                let l = s.toLocal(p + V3(0, dy, 0))
                for (dx, dz) in [(Float(0), Float(0)), (hw + 0.3, 0), (-hw - 0.3, 0), (0, hw + 0.3), (0, -hw - 0.3)] {
                    let lp = l + s.dirToLocal(V3(dx, 0, dz))
                    if Blocks.collide[Int(s.grid.get(Int(floor(lp.x)), Int(floor(lp.y)), Int(floor(lp.z))))] { return true }
                }
            }
            return false
        }
        var hit = false
        let pl = g.player
        if g.alive && touches(pl.pos, pl.halfW, pl.height) {
            let rel = simd_length(s.velocity(at: pl.pos) - pl.vel)
            if rel > 3 {
                g.hurtPlayer(min(18, Int((rel - 2) * 2)), from: s.pos, cause: "was crushed by falling debris")
                hit = true
            }
        }
        for m in g.mobs.mobs where m.health > 0 && touches(m.pos, m.halfW, m.height) {
            let v = s.velocity(at: m.pos)
            let rel = simd_length(v - m.vel)
            if rel > 3 {
                m.health -= min(18, Int((rel - 2) * 2))
                m.hurt = 0.3
                m.vel += v * 0.5
                hit = true
            }
        }
        if hit { s.hitCD = 0.5 }
    }

    // Lays a body into the world as ordinary blocks at its pose (each block to the cell its centre is in, then the
    // cells whose centre falls inside a block, so a turned shell stays closed); cells holding the player or a mob, or a
    // block that isn't replaceable, are left (crushed). Upright bodies keep their blocks' facings (turned to the nearest
    // quarter); tipped ones fall back to each block's plain state.
    @discardableResult
    func bake(_ s: Ship, game: Game?, settle: Bool = true) -> Int {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            worstBakeMs = max(worstBakeMs, ms)
            if s.parent == nil { spentMs["laying down", default: 0] += ms }
        }
        for t in list where t.parent === s { bake(t, game: game, settle: settle) }
        let w = world
        let g = s.grid
        // Cell tables and flat arrays, not [IVec3: BlockID] / Set<IVec3> (a 10k-block frigate hull took 70 ms to lay down).
        var tab = Collapse.CellTable(capacity: s.blockCount + 64)
        var pc: [IVec3] = []
        var pb: [BlockID] = []
        pc.reserveCapacity(s.blockCount)
        pb.reserveCapacity(s.blockCount)
        var bePlace: [IVec3: BlockEntity] = [:]
        for y in 0..<g.sy { for z in 0..<g.sz { for x in 0..<g.sx {
            let b = g.blocks[g.index(x, y, z)]
            if b == AIR { continue }
            let p = s.toWorld(V3(Float(x), Float(y), Float(z)) + 0.5)
            let c = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
            if tab.insert(c, Int32(pc.count)) { pc.append(c); pb.append(b) }
            if let be = s.blockEntities[IVec3(x, y, z)] { bePlace[c] = be }
        } } }
        let lo = s.worldMin, hi = s.worldMax
        // Cells whose centre falls inside a block of a turned body but that no block's centre landed in: they lie next to
        // cells that one did (a scan of the whole bounding box cost a 5M-cell sweep for a long hull, and was skipped).
        let splat = pc.count
        for k in 0..<splat {
            for d in Collapse.dirs6 {
                let c = pc[k] + d
                if tab.get(c) != nil { continue }
                let l = s.toLocal(V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5)
                let b = g.get(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z)))
                if b != AIR && Blocks.collide[Int(b)] && tab.insert(c, Int32(pc.count)) { pc.append(c); pb.append(b) }
            }
        }
        let up = s.dirToWorld(V3(0, 1, 0))
        let upright = up.y > 0.9
        let turns = Int((s.yaw / (.pi / 2)).rounded())
        var bodies: [(V3, V3)] = []
        if let gm = game {
            let p = gm.player
            bodies.append((V3(p.pos.x - p.halfW, p.pos.y, p.pos.z - p.halfW), V3(p.pos.x + p.halfW, p.pos.y + p.height, p.pos.z + p.halfW)))
            for m in gm.mobs.mobs where m.health > 0 && m.pos.x > lo.x - 2 && m.pos.x < hi.x + 2 && m.pos.z > lo.z - 2 && m.pos.z < hi.z + 2 {
                bodies.append((V3(m.pos.x - m.halfW, m.pos.y, m.pos.z - m.halfW), V3(m.pos.x + m.halfW, m.pos.y + m.height, m.pos.z + m.halfW)))
            }
        }
        let reader = BlockReader(w)
        func blocked(_ c: IVec3, _ b: BlockID) -> Bool {
            if c.y < 0 || c.y >= CH || !reader.loaded(c) { return true }
            if !Blocks.replaceable[Int(reader.block(c))] { return true }
            guard Blocks.collide[Int(b)], !bodies.isEmpty else { return false }
            let mn = V3(Float(c.x), Float(c.y), Float(c.z)), mx = mn + 1
            for (a, z) in bodies where a.x < mx.x && z.x > mn.x && a.y < mx.y && z.y > mn.y && a.z < mx.z && z.z > mn.z { return true }
            return false
        }
        let count = pc.count
        var alive = [Bool](repeating: true, count: count)
        for i in 0..<count where blocked(pc[i], pb[i]) { alive[i] = false }
        // Islands: a tumbled body's turned blocks can land joined only edge to edge, and a part laid down where it was
        // can rest on nothing. A piece touching nothing solid below or beside it drops straight down onto what is under
        // it (a few blocks at most), so no fragment is left hanging (collapse check: floating leftovers).
        var label = [Int32](repeating: -1, count: count)
        func mate(_ q: IVec3, _ l: Int32) -> Bool {
            guard let j = tab.get(q) else { return false }
            return alive[Int(j)] && label[Int(j)] == l
        }
        var occ = Collapse.CellTable(capacity: count + 64)
        var sc: [IVec3] = []
        var sb: [BlockID] = []
        sc.reserveCapacity(count)
        sb.reserveCapacity(count)
        var piece: [Int] = []
        var next: Int32 = 0
        for s0 in 0..<count where alive[s0] && label[s0] < 0 {
            let pl = next
            next += 1
            label[s0] = pl
            piece.removeAll(keepingCapacity: true)
            piece.append(s0)
            var k = 0
            while k < piece.count {
                let c = pc[piece[k]]
                k += 1
                for d in Collapse.dirs6 {
                    guard let j = tab.get(c + d), alive[Int(j)], label[Int(j)] < 0 else { continue }
                    label[Int(j)] = pl
                    piece.append(Int(j))
                }
            }
            var held = false
            for i in piece where !held {
                let c = pc[i]
                for d in Collapse.dirs6 where d.y <= 0 {
                    let q = c + d
                    if mate(q, pl) { continue }
                    if Blocks.collide[Int(reader.block(q))] { held = true; break }
                }
            }
            var drop = 0
            if !held {
                fall: while drop < 48 {
                    for i in piece {
                        let c = pc[i]
                        if mate(IVec3(c.x, c.y - 1, c.z), pl) { continue }        // rests on its own piece
                        let q = IVec3(c.x, c.y - drop - 1, c.z)
                        if q.y < 1 || Blocks.collide[Int(reader.block(q))] || occ.get(q) != nil { break fall }
                    }
                    drop += 1
                }
            }
            for i in piece {
                let c = pc[i]
                let to = IVec3(c.x, c.y - drop, c.z)
                if occ.insert(to, Int32(sc.count)) { sc.append(to); sb.append(pb[i]) }
                if drop > 0, let be = bePlace.removeValue(forKey: c) { bePlace[to] = be }
            }
        }
        var n = 0
        var putC: [IVec3] = []
        var putB: [BlockID] = []
        putC.reserveCapacity(sc.count)
        putB.reserveCapacity(sc.count)
        for k in 0..<sc.count where !blocked(sc[k], sb[k]) {
            let c = sc[k], b = sb[k]
            let nb: BlockID = upright ? ShipParts.rotate(b, turns) : Blocks.groupBase[Int(b)]
            putC.append(c)
            putB.append(nb)
            if let be = bePlace[c] { w.blockEntities[c] = be }
            n += 1
            if settle && settleQueue.count < 20000 && Collapse.built(nb) { settleQueue.append(c) }
        }
        w.setBlocksBulk(putC, putB)
        remove(s)
        ghosts.append((s, 0.6))                 // drawn where it lies until the world's new meshes are in
        bakedBlocks += n
        return n
    }

    // A capital hull cut through (its spine shot away): every part not joined to the largest one comes away as a
    // free-moving body (the hull grid is labelled once, a while after the last blast on it).
    func splitHull(_ s: Ship, game: Game?) {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            worstSplitMs = max(worstSplitMs, ms)
            spentMs["hull split", default: 0] += ms
        }
        let g = s.grid
        let sx = g.sx, sy = g.sy, sz = g.sz
        let n = sx * sy * sz
        var comp = [Int32](repeating: -1, count: n)
        var sizes: [Int] = []
        var drives: [Int] = []          // drive engines in each part
        let engineKind = ShipParts.kinds
        var queue: [Int32] = []
        queue.reserveCapacity(4096)
        for start in 0..<n where g.blocks[start] != AIR && comp[start] < 0 {
            let id = Int32(sizes.count)
            comp[start] = id
            queue.removeAll(keepingCapacity: true)
            queue.append(Int32(start))
            var head = 0
            var eng = 0
            while head < queue.count {
                let i = Int(queue[head]); head += 1
                if engineKind[Int(g.blocks[i])] == .engine { eng += 1 }
                let y = i / (sx * sz), rem = i - y * sx * sz, z = rem / sx, x = rem - z * sx
                if x > 0 { let j = i - 1; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
                if x < sx - 1 { let j = i + 1; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
                if z > 0 { let j = i - sx; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
                if z < sz - 1 { let j = i + sx; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
                if y > 0 { let j = i - sx * sz; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
                if y < sy - 1 { let j = i + sx * sz; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
            }
            sizes.append(queue.count)
            drives.append(eng)
        }
        // The part with the most drive engines stays the vessel (then the larger); the rest comes away. (Keeping the
        // part with the helm dropped a Stormwarden frigate's 150k-block hull with all 900 engines when shell holes cut
        // its bridge tower off: capitaltest.) A vessel left without its helm goes down below.
        guard sizes.count > 1, let keep = sizes.indices.max(by: { (drives[$0], sizes[$0]) < (drives[$1], sizes[$1]) }) else { return }
        var parts = [[Int]](repeating: [], count: sizes.count)
        for i in 0..<n where comp[i] >= 0 && Int(comp[i]) != keep { parts[Int(comp[i])].append(i) }
        let kinds = ShipParts.kinds
        var changed: [IVec3] = []
        let mounted = turrets(of: s)
        for cells in parts where !cells.isEmpty {
            var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
            for i in cells {
                let y = i / (sx * sz), rem = i - y * sx * sz, z = rem / sx, x = rem - z * sx
                lo = IVec3(min(lo.x, x), min(lo.y, y), min(lo.z, z)); hi = IVec3(max(hi.x, x), max(hi.y, y), max(hi.z, z))
            }
            let small = cells.count < 20
            // A big section of a flying capital comes down as the vessel itself would (kinematic, crash-landing, then a
            // wreck): as a free rigid body a 150k-block section cost 24 ms a frame of contacts (capitaltest).
            let section = s.isFlyingCapital && cells.count >= 3000
            let ng = ShipGrid(sx: hi.x - lo.x + 1, sy: hi.y - lo.y + 1, sz: hi.z - lo.z + 1)
            let part = Ship(id: newId(), grid: ng)
            for i in cells {
                let y = i / (sx * sz), rem = i - y * sx * sz, z = rem / sx, x = rem - z * sx
                let c = IVec3(x, y, z)
                let b = g.blocks[i]
                if kinds[Int(b)] == .engine { s.engines -= 1 }
                if s.helm == c { s.helm = nil }
                if !small { ng.set(x - lo.x, y - lo.y, z - lo.z, b) }
                if let be = s.blockEntities.removeValue(forKey: c), !small { part.blockEntities[ivSub(c, lo)] = be }
                s.damage.removeValue(forKey: c)
                g.set(x, y, z, AIR)
                changed.append(c)
            }
            s.blockCount -= cells.count
            if small {
                if let gm = game { gm.particles.explosion(at: s.toWorld(V3(Float(lo.x), Float(lo.y), Float(lo.z)) + 0.5), power: 1) }
                continue
            }
            let off = V3(Float(lo.x), Float(lo.y), Float(lo.z))
            part.name = s.name + " section"
            part.debris = !section
            part.kinematic = section
            if section { part.role = s.role; part.wrecked = true }
            part.faction = s.faction
            part.rebuild()
            part.rot = s.rot
            part.pos = s.toWorld(off + part.com)
            part.prevPos = part.pos; part.prevRot = part.rot
            part.vel = s.velocity(at: part.pos)
            part.angVel = s.angVel
            part.updateBounds()
            for t in mounted {
                let ring = t.mountLocal - V3(0.5, 1, 0.5)
                let rc = IVec3(Int(floor(ring.x + 0.01)), Int(floor(ring.y + 0.01)), Int(floor(ring.z + 0.01)))
                if rc.x >= lo.x && rc.x <= hi.x && rc.y >= lo.y && rc.y <= hi.y && rc.z >= lo.z && rc.z <= hi.z && ng.get(rc.x - lo.x, rc.y - lo.y, rc.z - lo.z) != AIR {
                    t.parent = part; t.parentId = part.id
                    t.mountLocal -= off
                }
            }
            add(part)
            part.mesh.rebuildAll(part, device: world.device, queue: meshQueue)
            if section {
                let st = CapitalState()
                st.groundOffset = part.com.y - part.localMin.y
                st.crewless = true
                st.disabledWhy = "cut away"
                capState[part.id] = st
            }
            hullSplits += 1
        }
        s.mesh.rebuildAround(s, changed, device: world.device, queue: meshQueue)
        // What is left of a vessel with no helm (its bridge went with the other part) goes down too.
        if s.helm == nil && !s.wrecked, let st = capState[s.id] {
            s.wrecked = true
            st.disabledWhy = "cut in two"
            for m in st.crewMobs.values where m.deck === s && m.health > 0 { m.crewFree = true; m.home = m.pos; m.aggro = true }
        }
    }
}

extension World {
    // Many blocks at once (debris laid down): one chunk lookup a block, each touched column's height and each touched
    // section's version once, gravity checks only for blocks that can fall (setBlockAsync per block: ~10 chunk lookups,
    // 27 version bumps and two gravity checks, each a string compare for concrete; a 10k-block hull took 37 ms).
    func setBlocksBulk(_ cells: [IVec3], _ ids: [BlockID]) {
        guard !cells.isEmpty else { return }
        let reader = BlockReader(self)
        var cols = Collapse.CellTable(capacity: 256)
        var colList: [(Chunk, Int, Int)] = []
        var secs = Collapse.CellTable(capacity: 256)
        var secList: [IVec3] = []
        let falling = World.fallingIDs
        for k in 0..<cells.count {
            let c = cells[k], id = ids[k]
            guard c.y >= 0 && c.y < CH, let ch = chunkAt(c.x, c.z) else { continue }
            if !damage.isEmpty { damage.removeValue(forKey: c) }
            let lx = mod(c.x, CS), lz = mod(c.z, CS)
            let i = Chunk.index(lx, c.y, lz)
            let old = ch.blocks[i]
            if old == id { continue }
            ch.blocks[i] = id
            ch.modified = true
            if !redstone.isBusy { redstone.blockChanged(c, old, id) }
            if falling[Int(id)] { gravityQueue.append(c) }
            if falling[Int(reader.block(IVec3(c.x, c.y + 1, c.z)))] { gravityQueue.append(IVec3(c.x, c.y + 1, c.z)) }
            if cols.insert(IVec3(c.x, 0, c.z), Int32(colList.count)) { colList.append((ch, lx, lz)) }
            let sk = IVec3(floorDiv(c.x, CS), c.y >> 4, floorDiv(c.z, CS))
            if secs.insert(sk, Int32(secList.count)) { secList.append(sk) }
        }
        for (ch, lx, lz) in colList { ch.recomputeHeight(lx, lz) }
        // Each touched section and its neighbours (light and faces reach across the border) remesh.
        var bumped = Collapse.CellTable(capacity: secList.count * 8 + 64)
        for sk in secList {
            for dz in -1...1 { for dx in -1...1 { for dy in -1...1 {
                let q = IVec3(sk.x + dx, sk.y + dy, sk.z + dz)
                guard q.y >= 0 && q.y < NSEC, bumped.insert(q, 0), let n = chunks[ChunkKey(x: q.x, z: q.z)] else { continue }
                n.sections[q.y].version += 1
            } } }
        }
    }
}
