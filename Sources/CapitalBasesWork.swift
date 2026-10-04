import Foundation
import simd

// Citadel patrols and rebuilding (CapitalBases.swift has the alert states and the noise bus).

extension BaseWatch {
    // The citadel's original blocks in the blast spheres: its chunks regenerated exactly as world generation made
    // them (terrain, then the structure pass). Runs on a worker thread.
    static func blueprint(_ gen: TerrainGenerator, _ spheres: [[Float]]) -> [(IVec3, BlockID)] {
        var chunks = Set<ChunkKey>()
        for s in spheres {
            let r = s[3] + 1
            for cz in floorDiv(Int(floor(s[2] - r)), CS)...floorDiv(Int(floor(s[2] + r)), CS) {
                for cx in floorDiv(Int(floor(s[0] - r)), CS)...floorDiv(Int(floor(s[0] + r)), CS) { chunks.insert(ChunkKey(x: cx, z: cz)) }
            }
        }
        var out: [(IVec3, BlockID)] = []
        var seen = Set<IVec3>()
        for k in chunks {
            var blocks = gen.generate(cx: k.x, cz: k.z)
            if let st = gen.structures { _ = st.place(into: &blocks, cx: k.x, cz: k.z) }
            for s in spheres {
                let r = s[3], r2 = r * r
                let x0 = max(k.x * CS, Int(floor(s[0] - r))), x1 = min(k.x * CS + CS - 1, Int(floor(s[0] + r)))
                let z0 = max(k.z * CS, Int(floor(s[2] - r))), z1 = min(k.z * CS + CS - 1, Int(floor(s[2] + r)))
                let y0 = max(0, Int(floor(s[1] - r))), y1 = min(CH - 1, Int(floor(s[1] + r)))
                guard x0 <= x1, z0 <= z1, y0 <= y1 else { continue }
                for y in y0...y1 { for z in z0...z1 { for x in x0...x1 {
                    let dx = Float(x) + 0.5 - s[0], dy = Float(y) + 0.5 - s[1], dz = Float(z) + 0.5 - s[2]
                    guard dx * dx + dy * dy + dz * dz <= r2 else { continue }
                    let p = IVec3(x, y, z)
                    guard !seen.contains(p) else { continue }
                    seen.insert(p)
                    out.append((p, blocks[Chunk.index(x - k.x * CS, y, z - k.z * CS)]))
                } } }
            }
        }
        return out
    }
}

extension Game {
    // A floor to stand on near (x, z): the first open two-high gap over solid ground, scanning down from `fromY`.
    func standY(_ x: Float, _ z: Float, from fromY: Float) -> Float {
        let ix = Int(floor(x)), iz = Int(floor(z))
        func solid(_ y: Int) -> Bool { Blocks.collide[Int(world.block(ix, y, iz))] }
        let top = Int(floor(fromY)) + 6
        for y in stride(from: top, through: top - 24, by: -1) where solid(y - 1) && !solid(y) && !solid(y + 1) { return Float(y) }
        return Float(world.gen.column(ix, iz).height + 1)
    }

    // MARK: Patrol

    func basePatrol(_ r: inout BaseRecord, _ b: BaseWatch, _ dt: Float) {
        guard var pt = r.patrol else { return }
        let target = V3(pt.target[0], pt.target[1], pt.target[2])
        pt.t += dt
        var team = b.patrols[r.key]
        if team == nil {
            if pt.phase >= 3 { r.patrol = nil; return }            // reloaded on the way home: they walk home anyway
            team = formPatrol(r, b, size: pt.size)
            b.patrols[r.key] = team
            b.note("\(r.key) patrol formed: \(team!.map { $0.kind.key }.joined(separator: " "))")
        }
        var members = team!.filter { $0.health > 0 }
        if members.isEmpty {
            b.note("\(r.key) patrol lost")
            b.patrols[r.key] = nil
            r.patrol = nil
            raise(&r, .alert)
            return
        }
        // Fighting members: a sighting puts the citadel on alert; a long-lost target is given up and the patrol goes on.
        for m in members where m.aggro {
            guard let br = m.brain else { continue }
            if br.sees { r.calm = 0; raise(&r, .alert) } else if br.seenAgo > 20 { m.aggro = false; br.lastSeen = nil }
        }
        let leader = members[0]
        let heading: V3 = {
            let d = V3(target.x - leader.pos.x, 0, target.z - leader.pos.z)
            let l = simd_length(d)
            return l > 0.1 ? d / l : V3(0, 0, 1)
        }()
        let side = V3(-heading.z, 0, heading.x)
        func slot(_ i: Int) -> V3 {
            if i == 0 { return .zero }
            let row = Float((i + 1) / 2), lr: Float = i % 2 == 1 ? -1 : 1
            return -heading * (2.2 * row) + side * (1.5 * lr)
        }
        func ground(_ p: V3) -> V3 { V3(p.x, standY(p.x, p.z, from: max(p.y, leader.pos.y)), p.z) }
        switch pt.phase {
        case 0:
            // Muster at the gate.
            var all = true
            for (i, m) in members.enumerated() {
                let at = r.gate + V3(Float(i % 3) * 1.6 - 1.6, 0, Float(i / 3) * 1.8 + 2)
                m.soldierBrain.order = V3(at.x, Float(r.y0 + 1), at.z)
                if simd_length(V2(m.pos.x - at.x, m.pos.z - at.z)) > 4 { all = false }
            }
            if all || pt.t > 25 { pt.phase = 1; pt.t = 0; b.note("\(r.key) patrol marching") }
        case 1:
            // Out: the leader walks waypoint to waypoint (the path finder reaches about 48 blocks), the rest follow
            // in a wedge.
            let to = V3(target.x - leader.pos.x, 0, target.z - leader.pos.z)
            let dist = simd_length(to)
            let wp = dist < 18 ? target : leader.pos + to / dist * 18
            leader.soldierBrain.order = ground(wp)
            for (i, m) in members.enumerated() where i > 0 { m.soldierBrain.order = ground(leader.pos + slot(i)) }
            if dist < 5 { pt.phase = 2; pt.t = 0; b.note("\(r.key) patrol reached the noise") }
            else if pt.t > 200 { pt.phase = 2; pt.t = 0; b.note("\(r.key) patrol stopped short (\(Int(dist)) blocks)") }
        case 2:
            // Search round the spot.
            if Int(pt.t) % 6 == 0 {
                for m in members {
                    let a = Rand.float(in: 0..<(2 * .pi)), d = Rand.float(in: 2...8)
                    m.soldierBrain.order = ground(target + V3(cosf(a) * d, 0, sinf(a) * d))
                }
            }
            if pt.t > 30 { pt.phase = 3; pt.t = 0; b.note("\(r.key) patrol returning") }
        default:
            // Back to their posts, each on its own.
            for m in members {
                let post = b.posts[ObjectIdentifier(m)] ?? r.gate
                let to = V3(post.x - m.pos.x, 0, post.z - m.pos.z)
                let dist = simd_length(to)
                if dist < 2.5 && abs(post.y - m.pos.y) < 3 {
                    let br = m.soldierBrain
                    br.order = nil; br.ready = false
                    m.home = post
                    b.posts.removeValue(forKey: ObjectIdentifier(m))
                    members.removeAll { $0 === m }
                    continue
                }
                let wp = dist < 18 ? post : m.pos + to / dist * 18
                m.soldierBrain.order = dist < 18 ? post : ground(wp)
            }
            if members.isEmpty || pt.t > 240 {
                b.note("\(r.key) patrol back (\(Int(pt.t)) s)")
                for m in members { m.soldierBrain.order = nil; m.soldierBrain.ready = false }
                b.patrols[r.key] = nil
                r.patrol = nil
                return
            }
        }
        if pt.phase < 3 { for m in members { m.soldierBrain.ready = true; m.soldierBrain.orderRun = pt.phase == 1 } }
        b.patrols[r.key] = members
        r.patrol = pt
    }

    // An officer and the soldiers nearest the gate; fresh ones march out of the barracks if the garrison is thin.
    private func formPatrol(_ r: BaseRecord, _ b: BaseWatch, size: Int) -> [Mob] {
        var gar = garrison(r, b).filter { !$0.aggro && $0.kind != .soldierMarksman && $0.kind != .soldierIronclad && ($0.brain?.station ?? .none) == .none }
        gar.sort { simd_length($0.pos - r.gate) < simd_length($1.pos - r.gate) }
        var team: [Mob] = []
        if let i = gar.firstIndex(where: { $0.kind == .soldierOfficer }) { team.append(gar.remove(at: i)) }
        while team.count < size, !gar.isEmpty { team.append(gar.removeFirst()) }
        if !team.contains(where: { $0.kind == .soldierOfficer }) || team.count < 3 {
            let kinds: [MobKind] = team.contains(where: { $0.kind == .soldierOfficer }) ? [.soldierRecruit, .soldierTrooper] : [.soldierOfficer, .soldierRecruit, .soldierTrooper]
            for k in kinds where team.count < max(3, min(size, 4)) || k == .soldierOfficer {
                let m = Mob(k, at: world.freeSpawn(r.gate + V3(0, 0, -6)))
                m.persistent = true
                m.home = m.pos
                mobs.mobs.append(m)
                if k == .soldierOfficer { team.insert(m, at: 0) } else { team.append(m) }
            }
        }
        // The officer leads.
        if let i = team.firstIndex(where: { $0.kind == .soldierOfficer }), i != 0 { team.swapAt(0, i) }
        for m in team {
            if b.posts[ObjectIdentifier(m)] == nil { b.posts[ObjectIdentifier(m)] = m.home ?? m.pos }
            let br = m.soldierBrain
            br.ready = true
            br.station = .none; br.orderStation = .none
        }
        return team
    }

    private func raise(_ r: inout BaseRecord, _ a: BaseAlert) {
        if a.rawValue > r.alert.rawValue { r.alert = a; bases.note("\(r.key) \(a.name) (patrol)") }
    }

    // MARK: Rebuild

    func baseRebuild(_ r: inout BaseRecord, _ b: BaseWatch, _ dt: Float, away: Float) {
        guard !r.damage.isEmpty else {
            dismissWorkers(r, b)
            return
        }
        if r.alert.rawValue >= BaseAlert.alert.rawValue || (r.alert == .suspicious && r.calm < 20 * BaseWatch.calmScale) { return }
        let fire = Blocks.has("fire") ? Blocks.id("fire") : AIR
        func open(_ id: BlockID) -> Bool { id == AIR || id == fire || Blocks.isLiquid(id) }
        guard var q = b.queue[r.key] else {
            if let cells = b.takeReady(r.key) {
                b.pending.remove(r.key)
                var list = cells.filter { (p, orig) in
                    let cur = world.block(p.x, p.y, p.z)
                    return orig != AIR && cur != orig && open(cur)          // wrecks, debris and builds are left alone
                }
                list.sort { $0.0.y != $1.0.y ? $0.0.y < $1.0.y : ($0.0.x != $1.0.x ? $0.0.x < $1.0.x : $0.0.z < $1.0.z) }
                b.queue[r.key] = list
                b.note("\(r.key) rebuild: \(list.count) blocks to restore")
            } else if !b.pending.contains(r.key) {
                b.pending.insert(r.key)
                let spheres = r.damage, key = r.key, gen = world.gen
                DispatchQueue.global(qos: .utility).async { b.setReady(key, BaseWatch.blueprint(gen, spheres)) }
            }
            return
        }
        // Two pilots do the work; each sets about a block a second (time away from the citadel is caught up at once).
        var crew = (b.workers[r.key] ?? []).filter { $0.health > 0 }
        while crew.count < 2 && !q.isEmpty {
            let m = Mob(.soldierCrew, at: world.freeSpawn(r.gate + V3(Float(crew.count) * 1.5, 0, -4)))
            m.persistent = true
            m.variant = Guns.pistol
            m.home = m.pos
            mobs.mobs.append(m)
            b.posts[ObjectIdentifier(m)] = r.gate
            crew.append(m)
        }
        var budget = Int((dt * Float(max(1, crew.count)) * 0.9).rounded()) + (away > 5 ? Int(away * 1.8) : 0)
        var skipped: [(IVec3, BlockID)] = []
        while budget > 0, !q.isEmpty {
            let (p, id) = q.removeFirst()
            let cur = world.block(p.x, p.y, p.z)
            guard open(cur) else { continue }
            // Not into the player.
            let pp = player.pos
            if abs(pp.x - (Float(p.x) + 0.5)) < 0.9 && abs(pp.z - (Float(p.z) + 0.5)) < 0.9 && Float(p.y) + 1 > pp.y && Float(p.y) < pp.y + 1.8 {
                skipped.append((p, id)); continue
            }
            world.setBlock(p.x, p.y, p.z, id)
            if away <= 5 {
                particles.blockBreak(id, at: p)
                sfx(.place(soundMat(id)), 0.7, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
            }
            r.rebuilt += 1
            budget -= 1
        }
        q += skipped
        // The pilots stand by the next block, working at it.
        if let next = q.first {
            let c = V3(Float(next.0.x) + 0.5, Float(next.0.y), Float(next.0.z) + 0.5)
            for (i, m) in crew.enumerated() {
                let a = Float(i) * Float.pi + 0.6
                let at = c + V3(cosf(a) * 2.2, 0, sinf(a) * 2.2)
                let br = m.soldierBrain
                br.order = V3(at.x, standY(at.x, at.z, from: min(c.y, m.pos.y + 4)), at.z)
                br.orderStation = .console
                br.orderFace = c
                br.ready = false
            }
        }
        b.workers[r.key] = crew
        if q.isEmpty {
            b.note("\(r.key) rebuilt (\(r.rebuilt) blocks so far)")
            r.damage = []
            b.queue[r.key] = nil
            for m in crew { let br = m.soldierBrain; br.orderStation = .none; br.station = .none; br.order = r.gate }
        } else {
            b.queue[r.key] = q
        }
    }

    // Pilots back at the gate when the work is done go inside (are removed).
    private func dismissWorkers(_ r: BaseRecord, _ b: BaseWatch) {
        guard let crew = b.workers[r.key], !crew.isEmpty else { return }
        var left: [Mob] = []
        for m in crew where m.health > 0 {
            if simd_length(V2(m.pos.x - r.gate.x, m.pos.z - r.gate.z)) < 3 || m.aggro {
                if !m.aggro { mobs.mobs.removeAll { $0 === m } } else { left.append(m) }
            } else {
                m.soldierBrain.order = r.gate
                left.append(m)
            }
        }
        b.workers[r.key] = left.isEmpty ? nil : left
    }
}

extension Game {
    // MARK: Crawler patrol

    // The citadel's crawler (a Capital-crewed Crawler from CapitalShips) drives out to a distant blast or cannon fire,
    // holds there a while, drives back to the motor pool south of the gate and goes back in (is removed).
    func baseCrawler(_ r: inout BaseRecord, _ b: BaseWatch, _ dt: Float) {
        guard let g3 = r.crawlerGoal else { return }
        let goal = V3(g3[0], g3[1], g3[2])
        r.crawlerT += dt
        let pool = r.motorPool
        let ships = world.ships
        let mine = ships.capitals.first { $0.role == "crawler" && $0.faction == Faction.steelhold.rawValue && simd_length(V2(($0.home ?? $0.pos).x - pool.x, ($0.home ?? $0.pos).z - pool.z)) < 4 }
        if r.crawlerPhase == 0 {
            guard world.isLoaded(Int(pool.x), Int(pool.z)) else { return }
            let yaw = atan2f(-(goal.x - pool.x), -(goal.z - pool.z))
            ships.spawnCapital("crawler", home: IVec3(Int(floor(pool.x)), 0, Int(floor(pool.z))), yaw: yaw, region: nil, faction: .steelhold)
            r.crawlerPhase = 1; r.crawlerT = 0
            return
        }
        guard let s = mine, let st = ships.capState[s.id] else {
            if r.crawlerT > 30 { b.note("\(r.key) crawler lost"); r.crawlerGoal = nil }      // never built, or destroyed
            return
        }
        let d = simd_length(V2(s.pos.x - goal.x, s.pos.z - goal.z)), dh = simd_length(V2(s.pos.x - pool.x, s.pos.z - pool.z))
        switch r.crawlerPhase {
        case 1:
            st.goal = goal
            if d < 18 { r.crawlerPhase = 2; r.crawlerT = 0; b.note("\(r.key) crawler reached the noise") }
            else if r.crawlerT > 300 { r.crawlerPhase = 3; r.crawlerT = 0; b.note("\(r.key) crawler turned back (\(Int(d)) blocks short)") }
        case 2:
            st.goal = goal                                        // within 12 of it: it waits there
            if r.crawlerT > 40 { r.crawlerPhase = 3; r.crawlerT = 0; b.note("\(r.key) crawler returning") }
        default:
            st.goal = pool
            if dh < 14 || r.crawlerT > 400 {
                for m in st.crewMobs.values { mobs.mobs.removeAll { $0 === m } }
                ships.remove(s)
                ships.capState.removeValue(forKey: s.id)
                b.note("\(r.key) crawler back in the motor pool (\(Int(r.crawlerT)) s)")
                r.crawlerGoal = nil
            }
        }
    }
}
