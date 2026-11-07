import Foundation
import simd

// FAILURES.md entry 1, rebuilt (Nov 2). Nov 1 12:33:06 at an ammo depot's magazines: "There should be like garage doors
// here"; Nov 1 evening at -2512.8 72.0 26.2: "the garage door was not made... lazy replacement that doesn't even let you
// through", "I can't even get through... an actual garage door." The P507 "roller shutter" was cells, each rolling up to
// a strip at the top of its own cell, and the opening never came clear.
//
// A Garage Door is one up-and-over door across the opening: its cells (the block keyed "roller_shutter", the save key
// kept) joined in one upright plane are one panel. Used (the panel, the stowed panel overhead, or a button beside the
// opening), the whole panel comes away as one body: it swings up and in about its top edge, lies level under the ceiling
// inside, and the opening is clear from sill to lintel and side to side, wide and high enough for a vehicle. Used again
// it swings back down and shuts. The moving panel is a kinematic body (a Ship, as a felled tree is: Felling.hold) taken
// out of the world when it starts and written back when it stops, so it is drawn and collides the whole way.
//
// States of the group: 0 the old full-cell shutter, 1 the old rolled strip (both from P507 saves: used, they swing like
// the rest), 2...5 the panel upright in its opening, its quarter-block thickness at the cell's inner face (inside toward
// +x, -x, +z, -z), 6...9 the panel stowed level under the ceiling, its thickness at the cell's bottom (inside +x...-z).
enum GarageDoors {
    static let shipName = "Garage Door"
    static let dirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
    static let seconds: Float = 2.6                      // a whole opening or closing
    static let maxCells = 96
    static var opened = 0, closed = 0, refused = 0         // (checks)

    static func dirIndex(_ n: IVec3) -> Int { dirs.firstIndex(of: n) ?? 0 }
    static func upright(_ n: IVec3) -> BlockID { Blocks.id(Depots.shutter) + BlockID(2 + dirIndex(n)) }
    static func stowed(_ n: IVec3) -> BlockID { Blocks.id(Depots.shutter) + BlockID(6 + dirIndex(n)) }
    static func isDoor(_ b: BlockID) -> Bool { Blocks.has(Depots.shutter) && Blocks.groupBase[Int(b)] == Blocks.id(Depots.shutter) }
    static func state(_ b: BlockID) -> Int { Int(b) - Int(Blocks.id(Depots.shutter)) }

    // The block states (Depots.register calls this after the base and its old strip).
    static func register(_ r: BlockRegistry, base d0: BlockDef) {
        for (i, n) in dirs.enumerated() {
            var d = d0
            d.name = Depots.shutter + "[\(2 + i)]"; d.hidden = true; d.skyStop = false
            d.boxes = [n.x == 1 ? Box(12, 0, 0, 16, 16, 16) : n.x == -1 ? Box(0, 0, 0, 4, 16, 16)
                       : n.z == 1 ? Box(0, 0, 12, 16, 16, 16) : Box(0, 0, 0, 16, 16, 4)]
            r.add(d)
        }
        for i in 0..<4 {
            var d = d0
            d.name = Depots.shutter + "[\(6 + i)]"; d.hidden = true; d.skyStop = false
            d.boxes = [Box(0, 0, 0, 16, 4, 16)]
            r.add(d)
        }
    }

    // MARK: The door's shape

    struct Door {
        var plane: [IVec3]            // the opening's cells, sill row to top row
        var n: IVec3                  // into the building (the side it stows on)
        var y0: Int, y1: Int          // sill row and top row of the opening
        var stow: [IVec3]             // where it lies open: the row over the top, 1...H in from the plane
        var open: Bool                // lying stowed now
        var H: Int { y1 - y0 + 1 }
    }

    // The joined door cells round p (any state), and the door they make, or nil when they make none or it has no room
    // to swing (refused: a clunk).
    static func door(_ w: World, at p: IVec3, from: V3) -> Door? {
        guard isDoor(w.block(p.x, p.y, p.z)) else { return nil }
        var seen: Set<IVec3> = [p], queue = [p]
        while let c = queue.popLast() {
            for d in World.allDirs {
                let q = c + d
                guard !seen.contains(q), isDoor(w.block(q.x, q.y, q.z)) else { continue }
                seen.insert(q); queue.append(q)
                if seen.count > maxCells { return nil }
            }
        }
        let cells = Array(seen)
        let states = cells.map { state(w.block($0.x, $0.y, $0.z)) }
        if states.allSatisfy({ $0 >= 6 }) {
            // Stowed: level cells, all at one height; the hinge row is the one with no door cell on its wall side.
            let n = dirs[states[0] - 6]
            guard let ys = cells.first?.y, cells.allSatisfy({ $0.y == ys }) else { return nil }
            let hinge = cells.filter { !seen.contains($0 - n) }
            guard !hinge.isEmpty else { return nil }
            var H = 0
            while seen.contains(IVec3(hinge[0].x + n.x * H, ys, hinge[0].z + n.z * H)) { H += 1 }
            guard H >= 1, cells.count == hinge.count * H else { return nil }
            var plane: [IVec3] = []
            for h in hinge { for y in (ys - H)...(ys - 1) { plane.append(IVec3(h.x - n.x, y, h.z - n.z)) } }
            return Door(plane: plane, n: n, y0: ys - H, y1: ys - 1, stow: cells, open: true)
        }
        guard states.allSatisfy({ $0 < 6 }) else { return nil }
        // Upright: one plane across x or across z.
        let xs = Set(cells.map { $0.x }), zs = Set(cells.map { $0.z })
        let axisX: Bool                                    // true: the plane is at one x (its normal along x)
        if xs.count == 1 && zs.count > 1 { axisX = true }
        else if zs.count == 1 && xs.count > 1 { axisX = false }
        else if xs.count == 1 && zs.count == 1 {
            // One column wide: the plane runs the way the wall beside it does.
            let c = cells[0]
            axisX = Blocks.collide[Int(w.block(c.x, c.y, c.z + 1))] || Blocks.collide[Int(w.block(c.x, c.y, c.z - 1))]
        } else { return nil }
        let y0 = cells.map { $0.y }.min()!, y1 = cells.map { $0.y }.max()!
        let H = y1 - y0 + 1
        func stowCells(_ n: IVec3) -> [IVec3] {
            var out: [IVec3] = []
            for c in cells where c.y == y1 { for k in 1...H { out.append(IVec3(c.x + n.x * k, y1 + 1, c.z + n.z * k)) } }
            return out
        }
        func room(_ n: IVec3) -> Bool {
            stowCells(n).allSatisfy { c in
                let b = w.block(c.x, c.y, c.z)
                return (b == AIR || Blocks.replaceable[Int(b)]) && Blocks.fluidKind[Int(b)] == 0 && !w.groundAt(c.x, c.y, c.z)
            }
        }
        // The inside: the side its upright cells say, else the side with room under a roof (the nearer the roof, the
        // more it is a building), else the side away from him.
        let options = axisX ? [IVec3(1, 0, 0), IVec3(-1, 0, 0)] : [IVec3(0, 0, 1), IVec3(0, 0, -1)]
        if let s = states.first(where: { $0 >= 2 && $0 <= 5 }), options.contains(dirs[s - 2]) {
            let n = dirs[s - 2]
            return room(n) ? Door(plane: cells, n: n, y0: y0, y1: y1, stow: stowCells(n), open: false) : nil
        }
        func cover(_ n: IVec3) -> Int {
            var k = 0
            for c in stowCells(n) {
                for y in (c.y + 1)...(c.y + 8) where Blocks.collide[Int(w.block(c.x, y, c.z))] { k += 1; break }
            }
            return k
        }
        let fits = options.filter(room)
        guard !fits.isEmpty else { return nil }
        var sum = V3(0, 0, 0)
        for c in cells { sum += V3(Float(c.x), Float(c.y), Float(c.z)) }
        let mid: V3 = sum / Float(cells.count) + V3(0.5, 0.5, 0.5)
        let toward: V3 = mid - from
        func away(_ n: IVec3) -> Float { Float(n.x) * toward.x + Float(n.z) * toward.z }
        let n = fits.max { a, b in
            let ca = cover(a), cb = cover(b)
            if ca != cb { return ca < cb }
            return away(a) < away(b)
        }!
        return Door(plane: cells, n: n, y0: y0, y1: y1, stow: stowCells(n), open: false)
    }

    // MARK: Moving

    final class Move {
        @WeakLink var ship: Ship?
        let door: Door
        let opening: Bool
        var t: Float                                     // 0 shut, 1 stowed
        var pivot = V3(0, 0, 0), axis = V3(0, 0, 1), slide = V3(0, 0, 0), pos0 = V3(0, 0, 0)
        var write: [(IVec3, BlockID)] = []               // what the world gets when it stops
        var wait: [(Chunk, Int, Int)] = []               // sections to be redrawn before the body shows (or goes)
        var phase = 0                                    // 0 held hidden, 1 moving, 2 written back, waiting to go
        var held: Float = 0
        init(door: Door, opening: Bool) { self.door = door; self.opening = opening; t = opening ? 0 : 1 }

        // The panel's pose at t: a quarter turn about the hinge (its top edge, on the panel's outer face) for the first
        // 85%, then a quarter-block slide in to where its stowed cells lie.
        func pose(_ t: Float) -> (V3, Quat) {
            let turn = min(1, t / 0.85), sl = max(0, (t - 0.85) / 0.15)
            let e = turn * turn * (3 - 2 * turn)
            let r = Quat(angle: e * .pi / 2, axis: axis)
            let arm: V3 = r.act(pos0 - pivot)
            let at: V3 = pivot + arm + slide * sl
            return (at, r)
        }
    }
    static var moves: [Move] = []

    static func busy(_ c: IVec3) -> Bool {
        moves.contains { m in m.door.plane.contains(c) || m.door.stow.contains(c) }
    }

    // His use of a door cell (Game.openBlock) or a button by one: the whole door opens or shuts.
    static func use(_ g: Game, _ p: IVec3) {
        let w = g.world
        let at = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        if busy(p) { return }
        // An old P507 strip, rolled up: the shutter comes down shut first (it is a door again), then works as one.
        let b = w.block(p.x, p.y, p.z)
        if state(b) == 1 {
            var seen: Set<IVec3> = [p], queue = [p]
            while let c = queue.popLast(), seen.count < maxCells {
                for d in World.allDirs where !seen.contains(c + d) && isDoor(w.block(c.x + d.x, c.y + d.y, c.z + d.z)) { seen.insert(c + d); queue.append(c + d) }
            }
            for c in seen where state(w.block(c.x, c.y, c.z)) == 1 { w.setBlock(c.x, c.y, c.z, Blocks.id(Depots.shutter)) }
            g.sfx(.pistonContract, 0.9, at: at)
            return
        }
        widen(w, p)
        guard let d = door(w, at: p, from: g.player.pos) else {
            refused += 1
            g.sfx(.ironDoorClose, 0.5, at: at)
            return
        }
        start(g, d, opening: !d.open)
    }

    static func start(_ g: Game, _ d: Door, opening: Bool) {
        let w = g.world
        let m = Move(door: d, opening: opening)
        // The body is always the upright panel; shutting, it starts at the stowed pose.
        let bp = Blueprint()
        let origin = d.plane.min { ($0.y, $0.x, $0.z) < ($1.y, $1.x, $1.z) }!
        var lo = IVec3(Int.max, Int.max, Int.max)
        for c in d.plane {
            bp.cells[ivSub(c, origin)] = upright(d.n)
            lo = IVec3(min(lo.x, c.x - origin.x), min(lo.y, c.y - origin.y), min(lo.z, c.z - origin.z))
        }
        let taken = opening ? d.plane : d.stow
        w.restoring = true
        for c in taken { w.setBlock(c.x, c.y, c.z, AIR) }
        w.restoring = false
        let s = w.ships.spawn(bp, at: V3(Float(origin.x), Float(origin.y), Float(origin.z)), yaw: 0, name: shipName, role: "")
        s.role = nil
        m.pos0 = V3(Float(origin.x + lo.x), Float(origin.y + lo.y), Float(origin.z + lo.z)) + s.com
        // Hinge: the top of the opening, on the panel's outer face (a quarter block in from the plane's middle).
        let nf = V3(Float(d.n.x), 0, Float(d.n.z))
        let c0 = d.plane[0]
        let mid = V3(Float(c0.x) + 0.5, 0, Float(c0.z) + 0.5)
        let face: Float = simd_dot(mid, nf) + 0.25
        let px: Float = abs(nf.x) > 0 ? face * nf.x : 0, pz: Float = abs(nf.z) > 0 ? face * nf.z : 0
        m.pivot = V3(px, Float(d.y1 + 1), pz)
        m.axis = simd_cross(V3(0, -1, 0), nf)
        m.slide = nf * 0.25
        let (p0, r0) = m.pose(m.t)
        s.pos = p0; s.rot = r0; s.prevPos = p0; s.prevRot = r0
        s.vel = .zero; s.angVel = .zero
        s.kinematic = true; s.hidden = true
        s.updateBounds()
        m.ship = s
        m.wait = sections(w, taken)
        m.write = opening ? d.stow.map { ($0, stowed(d.n)) } : d.plane.map { ($0, upright(d.n)) }
        moves.append(m)
        g.sfx(.ironDoorOpen, 1.1, at: p0)
        g.sfx(opening ? .pistonExtend : .pistonContract, 0.8, at: p0)
        if opening { opened += 1 } else { closed += 1 }
    }

    static func sections(_ w: World, _ cells: [IVec3]) -> [(Chunk, Int, Int)] {
        var out: [(Chunk, Int, Int)] = [], seen = Set<Int64>()
        for c in cells {
            guard let ch = w.chunkAt(c.x, c.z), c.y >= 0 && c.y < CH else { continue }
            let sy = c.y >> 4
            let key = Int64(ch.cx) << 40 ^ Int64(ch.cz) << 16 ^ Int64(sy)
            if seen.insert(key).inserted { out.append((ch, sy, ch.sections[sy].version)) }
        }
        return out
    }
    static func drawn(_ w: World, _ wait: [(Chunk, Int, Int)]) -> Bool {
        wait.allSatisfy { $0.0.sections[$0.1].meshedVersion >= $0.2 || w.chunks[ChunkKey(x: $0.0.cx, z: $0.0.cz)] !== $0.0 }
    }

    // Every frame (Game.advance, after the ships moved): the doors swing.
    static func tick(_ g: Game, _ dt: Float) {
        let w = g.world
        // A door body with no move (a save taken mid-swing): it settles where it is, its cells written to the world.
        for s in w.ships.list where s.name == shipName && !moves.contains(where: { $0.ship === s }) {
            for y in 0..<s.grid.sy { for z in 0..<s.grid.sz { for x in 0..<s.grid.sx {
                let b = s.grid.get(x, y, z)
                guard b != AIR else { continue }
                let p = s.toWorld(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))
                let c = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
                if w.block(c.x, c.y, c.z) == AIR { w.setBlock(c.x, c.y, c.z, Blocks.id(Depots.shutter)) }
            } } }
            w.ships.remove(s)
        }
        guard !moves.isEmpty else { return }
        let live = w.ships.list
        moves.removeAll { m in m.ship.map { s in !live.contains { $0 === s } } ?? true }
        for m in moves {
            guard let s = m.ship else { continue }
            m.held += dt
            switch m.phase {
            case 0:
                // Held hidden until the world has redrawn without the cells it took (and its own mesh is in), as a
                // felled tree is (P441), so neither the old cells nor a gap shows.
                let built = !s.mesh.busy && !s.mesh.sections.isEmpty
                if !(drawn(w, m.wait) && built) && m.held < 1.5 { s.vel = .zero; s.angVel = .zero; continue }
                s.hidden = false
                m.phase = 1
                fallthrough
            case 1:
                m.t = max(0, min(1, m.t + (m.opening ? dt : -dt) / seconds))
                let (p, r) = m.pose(m.t)
                if (m.opening && m.t >= 1) || (!m.opening && m.t <= 0) {
                    s.pos = p; s.rot = r; s.vel = .zero; s.angVel = .zero
                    s.updateBounds()
                    w.restoring = true
                    for (c, b) in m.write { w.setBlock(c.x, c.y, c.z, b) }
                    w.restoring = false
                    m.wait = sections(w, m.write.map { $0.0 })
                    m.phase = 2; m.held = 0
                    g.sfx(.ironDoorClose, 1.2, at: p)
                    continue
                }
                // Kinematic: the velocity and turn that put it at this frame's pose by the next.
                let h = max(dt, 1.0 / 120)
                s.vel = (p - s.pos) / h
                let q = r * s.rot.inverse
                let ang = q.angle
                s.angVel = ang > 1e-5 ? q.axis * ((ang > .pi ? ang - 2 * .pi : ang) / h) : .zero
            default:
                s.vel = .zero; s.angVel = .zero
                if drawn(w, m.wait) || m.held > 1.5 { w.ships.remove(s) }
            }
        }
        moves.removeAll { m in m.ship.map { s in !w.ships.list.contains { $0 === s } } ?? true }
    }

    // His World's depots (P507 saves): a magazine's shutter was three by three, too small for a vehicle. Used, an old
    // shutter of full cells three wide and three high set in a depot headwall's concrete takes the concrete round it to
    // be five wide and four high, as new depots are built; a ceiling light in the way it swings to moves to the wall.
    static func widen(_ w: World, _ p: IVec3) {
        guard Blocks.has("bunker_concrete"), state(w.block(p.x, p.y, p.z)) == 0 else { return }
        let con = Blocks.id("bunker_concrete"), base = Blocks.id(Depots.shutter)
        var seen: Set<IVec3> = [p], queue = [p]
        while let c = queue.popLast(), seen.count <= 9 {
            for d in World.allDirs where !seen.contains(c + d) && isDoor(w.block(c.x + d.x, c.y + d.y, c.z + d.z)) { seen.insert(c + d); queue.append(c + d) }
        }
        guard seen.count == 9, seen.allSatisfy({ state(w.block($0.x, $0.y, $0.z)) == 0 }) else { return }
        let xs = Set(seen.map { $0.x }), zs = Set(seen.map { $0.z }), ys = seen.map { $0.y }
        guard (xs.count == 1) != (zs.count == 1), let y0 = ys.min(), let y1 = ys.max(), y1 - y0 == 2 else { return }
        let u = xs.count == 1 ? IVec3(0, 0, 1) : IVec3(1, 0, 0), n0 = xs.count == 1 ? IVec3(1, 0, 0) : IVec3(0, 0, -1)
        let lo = seen.min { $0.x + $0.z < $1.x + $1.z }!
        func at(_ k: Int, _ y: Int) -> IVec3 { IVec3(lo.x + u.x * k, y, lo.z + u.z * k) }     // k -1...3 across, the old door 0...2
        var ring: [IVec3] = []
        for k in -1...3 { for y in y0...(y1 + 1) where !(k >= 0 && k <= 2 && y <= y1) { ring.append(at(k, y)) } }
        guard ring.allSatisfy({ w.block($0.x, $0.y, $0.z) == con }) else { return }
        // The inside: the side with room for it lying four in under the row over the new top (a light allowed).
        let light = Blocks.has("light_panel") ? Blocks.id("light_panel") : AIR
        for n in [n0, IVec3(-n0.x, 0, -n0.z)] {
            var cells: [IVec3] = [], ok = true
            for k in -1...3 { for d in 1...4 {
                let c = at(k, y1 + 2) + IVec3(n.x * d, 0, n.z * d)
                let b = w.block(c.x, c.y, c.z)
                if b != AIR && b != light { ok = false }
                cells.append(c)
            } }
            // (and a roof over it: the inside of a building, not the yard)
            guard ok, cells.allSatisfy({ c in (1...4).contains { Blocks.collide[Int(w.block(c.x, c.y + $0, c.z))] } }) else { continue }
            for c in cells where w.block(c.x, c.y, c.z) == light {
                w.setBlock(c.x, c.y, c.z, AIR)
                // (to the vault's side, in the concrete just past where the door lies)
                var q = c
                while cells.contains(q) { q = q + u }
                if w.block(q.x, q.y, q.z) == con { w.setBlock(q.x, q.y, q.z, light) }
                else if w.block(q.x, q.y - 1, q.z) == con { w.setBlock(q.x, q.y - 1, q.z, light) }
            }
            for c in ring { w.setBlock(c.x, c.y, c.z, base) }
            return
        }
    }

    // A button pressed beside a door (within 3 blocks of one of its cells): the door works as if used.
    static func button(_ g: Game, _ p: IVec3) {
        let w = g.world
        guard Blocks.has(Depots.shutter) else { return }
        var best: IVec3?, bd = Int.max
        for y in (p.y - 3)...(p.y + 5) { for z in (p.z - 3)...(p.z + 3) { for x in (p.x - 3)...(p.x + 3) where isDoor(w.block(x, y, z)) {
            let d = abs(x - p.x) + abs(y - p.y) + abs(z - p.z)
            if d < bd { bd = d; best = IVec3(x, y, z) }
        } } }
        if let c = best { use(g, c) }
    }
}

