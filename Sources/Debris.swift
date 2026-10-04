import Foundation
import simd

// Falling debris (Destruction.swift): world blocks cut loose into free-moving bodies, their crashes, and laying them
// back into the world once they rest. Also the capital hulls' full split check (a frigate cut in two).
extension ShipManager {
    var debrisCount: Int { list.reduce(0) { $0 + ($1.debris ? 1 : 0) } }

    // Runs the support analysis round cells just emptied (an explosion's holes, a block a falling piece broke) and sets
    // whatever fails moving. Returns the number of bodies made.
    @discardableResult
    func collapse(around holes: [IVec3], game: Game?, from blast: V3? = nil) -> Int {
        guard !holes.isEmpty else { return 0 }
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = Collapse.analyze(world, around: holes)
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
        collapseMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        if made > 0 { collapses += 1 }
        return made
    }

    // Holes to check next frame: every blast of a frame is checked together, at most one check a frame (a salvo on a
    // big building can't stack up a dozen 6000-cell searches in one frame).
    func queueCollapse(_ holes: [IVec3], from: V3?) {
        if collapseQueue.count < 64 { collapseQueue.append((holes, from)) }
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
            var n = 0
            while n < collapseQueue.count && holes.count < 4000 {
                holes += collapseQueue[n].0
                from = from ?? collapseQueue[n].1
                n += 1
            }
            collapseQueue.removeFirst(n)
            collapse(around: holes, game: game, from: from)
        }
        for s in list where s.kinematic && s.parent == nil && s.splitCheck >= 0 {
            s.splitCheck -= dt
            if s.splitCheck < 0 { splitHull(s, game: game) }
        }
        for s in list where s.debris && s.parent == nil {
            s.age += dt
            s.hitCD -= dt
            let speed = simd_length(s.vel), spin = simd_length(s.angVel)
            if speed < 0.3 && spin < 0.2 { s.restTime += dt } else { s.restTime = 0 }
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
    func bake(_ s: Ship, game: Game?) -> Int {
        for t in list where t.parent === s { bake(t, game: game) }
        let w = world
        let g = s.grid
        var place: [IVec3: BlockID] = [:]
        var bePlace: [IVec3: BlockEntity] = [:]
        for y in 0..<g.sy { for z in 0..<g.sz { for x in 0..<g.sx {
            let b = g.blocks[g.index(x, y, z)]
            if b == AIR { continue }
            let p = s.toWorld(V3(Float(x), Float(y), Float(z)) + 0.5)
            let c = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
            if place[c] == nil { place[c] = b }
            if let be = s.blockEntities[IVec3(x, y, z)] { bePlace[c] = be }
        } } }
        let lo = s.worldMin, hi = s.worldMax
        let cells = (Int(ceilf(hi.x - lo.x)) + 1) * (Int(ceilf(hi.y - lo.y)) + 1) * (Int(ceilf(hi.z - lo.z)) + 1)
        if cells < 3_000_000 {
            for y in Int(floor(lo.y))...Int(floor(hi.y)) { for z in Int(floor(lo.z))...Int(floor(hi.z)) { for x in Int(floor(lo.x))...Int(floor(hi.x)) {
                let c = IVec3(x, y, z)
                if place[c] != nil { continue }
                let l = s.toLocal(V3(Float(x), Float(y), Float(z)) + 0.5)
                let b = g.get(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z)))
                if b != AIR && Blocks.collide[Int(b)] { place[c] = b }
            } } }
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
        var n = 0
        for (c, b) in place {
            if c.y < 0 || c.y >= CH || !w.isLoaded(c.x, c.z) { continue }
            if !Blocks.replaceable[Int(w.rawBlock(c.x, c.y, c.z))] { continue }
            let mn = V3(Float(c.x), Float(c.y), Float(c.z)), mx = mn + 1
            if Blocks.collide[Int(b)] && bodies.contains(where: { $0.0.x < mx.x && $0.1.x > mn.x && $0.0.y < mx.y && $0.1.y > mn.y && $0.0.z < mx.z && $0.1.z > mn.z }) { continue }
            let nb: BlockID = upright ? ShipParts.rotate(b, turns) : Blocks.groupBase[Int(b)]
            _ = w.setBlockAsync(c.x, c.y, c.z, nb)
            if let be = bePlace[c] { w.blockEntities[c] = be }
            n += 1
        }
        remove(s)
        ghosts.append((s, 0.6))                 // drawn where it lies until the world's new meshes are in
        bakedBlocks += n
        return n
    }

    // A capital hull cut through (its spine shot away): every part not joined to the largest one comes away as a
    // free-moving body (the hull grid is labelled once, a while after the last blast on it).
    func splitHull(_ s: Ship, game: Game?) {
        let g = s.grid
        let sx = g.sx, sy = g.sy, sz = g.sz
        let n = sx * sy * sz
        var comp = [Int32](repeating: -1, count: n)
        var sizes: [Int] = []
        var queue: [Int32] = []
        queue.reserveCapacity(4096)
        for start in 0..<n where g.blocks[start] != AIR && comp[start] < 0 {
            let id = Int32(sizes.count)
            comp[start] = id
            queue.removeAll(keepingCapacity: true)
            queue.append(Int32(start))
            var head = 0
            while head < queue.count {
                let i = Int(queue[head]); head += 1
                let y = i / (sx * sz), rem = i - y * sx * sz, z = rem / sx, x = rem - z * sx
                if x > 0 { let j = i - 1; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
                if x < sx - 1 { let j = i + 1; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
                if z > 0 { let j = i - sx; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
                if z < sz - 1 { let j = i + sx; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
                if y > 0 { let j = i - sx * sz; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
                if y < sy - 1 { let j = i + sx * sz; if comp[j] < 0 && g.blocks[j] != AIR { comp[j] = id; queue.append(Int32(j)) } }
            }
            sizes.append(queue.count)
        }
        guard sizes.count > 1, var keep = sizes.indices.max(by: { sizes[$0] < sizes[$1] }) else { return }
        // The part with the helm stays the vessel (its AI flies it, or brings it down if its engines went with the other
        // part); the rest falls.
        if let h = s.helm, g.inside(h.x, h.y, h.z) {
            let k = Int(comp[g.index(h.x, h.y, h.z)])
            if k >= 0 && sizes[k] * 5 >= sizes[keep] { keep = k }
        }
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
            part.debris = true
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
