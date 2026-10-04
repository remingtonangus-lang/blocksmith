import Foundation
import simd

// Turrets, cannons and explosions on ships.
// - A Turret Ring under a structure makes it a turret when the ship is assembled: a child ship that turns on
//   the ring (vertical axis) and is carried by its parent. The pilot's view aims turrets; crews aim with aimAt.
// - Cannons fire shells along their muzzle, raised to the pilot's view pitch (crews: to reach the target).
//   Shells fly under gravity and explode on terrain, ships, mobs or the player.
// - Explosions (TNT, hissers, shells) blow blocks out of ships with the same ray model as the world.

final class Shell {
    var pos: V3
    var vel: V3
    var age: Float = 0
    let owner: Int                   // firing ship (its turrets and parent are ignored)
    let power: Float
    var gravity: Float = 20
    var kind = 0                     // 0 cannon shell, 1 rail slug (capital main guns), 2 missile
    var life: Float = 10
    // Missiles steer toward their target (a ship, a mob or the player) and burst near it.
    weak var seekShip: Ship?
    weak var seekMob: Mob?
    var seekPlayer = false
    var seekPoint: V3?
    init(pos: V3, vel: V3, owner: Int, power: Float) { self.pos = pos; self.vel = vel; self.owner = owner; self.power = power }
}

extension Ship {
    // Root ship of a turret chain.
    var root: Ship { var s = self; while let p = s.parent { s = p }; return s }

    // Places a turret on its parent's bearing (called every substep after the parent moved).
    func followParent(_ h: Float) {
        guard let p = parent else { return }
        if let a = aimAt {
            let d = a - toWorld(pivot)
            if d.x * d.x + d.z * d.z > 0.01 { aimYaw = atan2f(-d.x, -d.z) - p.yaw }
        }
        if let target = aimYaw {
            var d = target - turretYaw
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            let rate: Float = 0.9
            turretYaw += max(-rate * h, min(rate * h, d))
            if turretYaw > .pi { turretYaw -= 2 * .pi }
            if turretYaw < -.pi { turretYaw += 2 * .pi }
        }
        rot = simd_normalize(p.rot * Quat(angle: turretYaw, axis: V3(0, 1, 0)))
        pos = p.toWorld(mountLocal) - rot.act(pivot - com)
        vel = p.velocity(at: pos)
        angVel = p.angVel
        updateBounds()
    }
}

extension ShipManager {
    // Ships carried by s (turrets, recursively one level at a time).
    func turrets(of s: Ship) -> [Ship] { list.filter { $0.parent === s } }

    // Fires every loaded cannon on s and its turrets. Pitch: barrel elevation in radians (clamped).
    @discardableResult
    func fire(_ s: Ship, pitch: Float, game: Game?) -> Int {
        var fired = 0
        for t in [s] + turrets(of: s) where t.reload <= 0 && !t.cannons.isEmpty {
            let elev = max(t.pitchMin, min(t.pitchMax, pitch))
            for (c, d) in t.cannons {
                let muzzle = t.toWorld(c + d * 0.9)
                var dir = t.dirToWorld(d)
                let horiz = simd_normalize(V3(dir.x, 0, dir.z) + V3(1e-5, 0, 0))
                dir = simd_normalize(horiz * cosf(elev) + V3(0, sinf(elev), 0))
                if t.gunScatter > 0 { dir = Guns.scatter(dir, t.gunScatter) }
                let sh = Shell(pos: muzzle, vel: dir * t.gunSpeed + t.velocity(at: muzzle), owner: t.root.id, power: t.gunPower)
                sh.gravity = t.gunGravity
                shells.append(sh)
                fired += 1
                if let g = game {
                    // Naval guns (fast, heavy shells) boom louder and further.
                    g.sfx(.shipCannon, t.gunPower > 3 ? 1.6 : 1, at: muzzle)
                    g.particles.smoke(at: muzzle)
                    g.baseNoise(at: muzzle, kind: .cannon, hostile: s.factionValue != .steelhold)   // the Capital's own guns don't alarm it
                }
            }
            t.reload = t.reloadTime
        }
        return fired
    }

    // Shells as small dark cubes; rail slugs as glowing bolts, missiles as pale darts.
    func writeShells(_ wr: inout EntityWriter, eye: V3) {
        if shells.isEmpty { return }
        let b = Blocks.has("coal_block") ? Blocks.id("coal_block") : STONE
        let slug = Blocks.has("magma_block") ? Blocks.id("magma_block") : b
        let dart = Blocks.has("iron_block") ? Blocks.id("iron_block") : b
        for sh in shells {
            switch sh.kind {
            case 1:
                // A streak: a few cubes back along the flight path.
                let d = simd_length(sh.vel) > 0.01 ? simd_normalize(sh.vel) : V3(0, 0, -1)
                for k in 0..<4 { wr.cube(center: sh.pos - d * Float(k) * 0.9 - eye, half: 0.45 - Float(k) * 0.08, yaw: sh.age * 9, block: slug, light: 1) }
            case 2: wr.cube(center: sh.pos - eye, half: 0.16, yaw: sh.age * 14, block: dart, light: 1)
            default: wr.cube(center: sh.pos - eye, half: sh.power > 3 ? 0.26 : 0.18, yaw: sh.age * 9, block: b, light: 1)
            }
        }
    }

    // Moves shells and detonates them (call once per frame).
    func updateShells(_ dt: Float, game: Game?) {
        for s in list { s.reload = max(0, s.reload - dt) }
        if shells.isEmpty { return }
        var reader = ShipBlockReader(world)
        var keep: [Shell] = []
        var blasts: [(V3, Float)] = []
        for sh in shells {
            sh.age += dt
            let start = sh.pos
            // Missiles: track the target and turn toward it (2.5 rad/s), smoking; a proximity fuse.
            var near = false
            if sh.kind == 2 {
                var aim: V3? = sh.seekPoint
                if let t = sh.seekShip { aim = t.pos }
                if let m = sh.seekMob { aim = m.health > 0 ? m.pos + V3(0, m.height * 0.5, 0) : aim }
                if sh.seekPlayer, let g = game { aim = g.player.pos + V3(0, 1, 0) }
                if let a = aim {
                    sh.seekPoint = a
                    let speed = max(1, simd_length(sh.vel))
                    let want = simd_normalize(a - start + V3(1e-4, 0, 0))
                    let cur = sh.vel / speed
                    let ang = acosf(max(-1, min(1, simd_dot(cur, want))))
                    let k = ang > 1e-3 ? min(1, 2.5 * dt / ang) : 1
                    sh.vel = simd_normalize(cur + (want - cur) * k + V3(1e-5, 0, 0)) * speed
                    // Near the target: burst (missiles chasing a 480-block hull aim at its centre, so a hull hit fuses first).
                    if simd_length(a - start) < 2.5 { near = true }
                }
                if let g = game, Int(sh.age * 30) % 3 == 0 { g.particles.smoke(at: start, dark: false) }
            }
            sh.vel.y -= sh.gravity * dt
            let end = start + sh.vel * dt
            let len = simd_length(end - start)
            let n = max(1, Int(ceil(len / 0.4)))
            var hit: V3?
            for i in 1...n {
                let p = start + (end - start) * (Float(i) / Float(n))
                if Blocks.collide[Int(reader.get(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))))] { hit = p; break }
                if shipBlock(at: p, except: sh.owner) { hit = p; break }
                if let g = game, sh.age > 0.25 {                   // (clear of the gun crew first)
                    if g.mobs.mobs.contains(where: { $0.health > 0 && simd_length($0.pos + V3(0, $0.height * 0.5, 0) - p) < max(0.8, $0.halfW + 0.4) }) { hit = p; break }
                    let pr = g.player.pos + V3(0, 0.9, 0)
                    if simd_length(pr - p) < 0.8 && g.world.ships.pilot?.root.id != sh.owner { hit = p; break }
                }
            }
            if near && hit == nil { hit = start }
            if let p = hit { blasts.append((p, sh.power)); continue }
            sh.pos = end
            if sh.age < sh.life && sh.pos.y > -64 { keep.append(sh) }
        }
        shells = keep
        for (p, power) in blasts {
            if let g = game { Explosion.explode(at: p, power: power, game: g) } else { blast(at: p, power: power, game: nil) }
        }
    }

    // Whether a world point is inside a solid block of a ship other than the root `except`.
    func shipBlock(at p: V3, except: Int) -> Bool {
        for s in list where s.root.id != except && p.x > s.worldMin.x && p.x < s.worldMax.x && p.y > s.worldMin.y && p.y < s.worldMax.y
            && p.z > s.worldMin.z && p.z < s.worldMax.z {
            let l = s.toLocal(p)
            if Blocks.collide[Int(s.grid.get(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z))))] { return true }
        }
        return false
    }

    // Explosion damage to ships near c (Explosion.explode calls this): rays lose strength by blast resistance
    // like in the world; blocks they get through are destroyed (dropping with chance 1/power); the hull is pushed.
    func blast(at c: V3, power: Float, game: Game?) {
        let reach = power * 2 + 1
        for s in list where c.x > s.worldMin.x - reach && c.x < s.worldMax.x + reach && c.y > s.worldMin.y - reach
            && c.y < s.worldMax.y + reach && c.z > s.worldMin.z - reach && c.z < s.worldMax.z + reach {
            let lc = s.toLocal(c)
            let g = s.grid
            var destroyed = Set<IVec3>()
            var shaken: [IVec3: Float] = [:]                // cells that stopped a ray: share of their cost it carried
            for i in 0..<16 { for j in 0..<16 { for k in 0..<16 {
                if !(i == 0 || i == 15 || j == 0 || j == 15 || k == 0 || k == 15) { continue }
                let d = simd_normalize(V3(Float(i) / 15 * 2 - 1, Float(j) / 15 * 2 - 1, Float(k) / 15 * 2 - 1))
                var intensity = power * (0.7 + Rand.float(in: 0..<0.6))
                var p = lc
                while intensity > 0 {
                    let cell = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
                    let b = g.get(cell.x, cell.y, cell.z)
                    if b != AIR {
                        let cost: Float = (Blocks.resistance[Int(b)] + 0.3) * 0.3
                        if intensity <= cost && intensity > 0 { shaken[cell] = max(shaken[cell] ?? 0, intensity / cost) }
                        intensity -= cost
                        if intensity > 0 && Blocks.hardness[Int(b)] >= 0 { destroyed.insert(cell) }
                    }
                    p += d * 0.3
                    intensity -= 0.225
                }
            } } }
            // Progressive damage on capital hulls: plates the blast couldn't break lose pieces on the side facing it
            // (their grid never re-crops, so the chip map stays valid in grid space).
            var chipped: [IVec3] = []
            if s.kinematic && Settings.shared.chipping {
                for (cell, share) in shaken where !destroyed.contains(cell) && share > 0.15 {
                    let b = g.get(cell.x, cell.y, cell.z)
                    guard b != AIR, Blocks.render[Int(b)] == RenderType.cube.rawValue, Blocks.hardness[Int(b)] >= 0 else { continue }
                    let d = lc - (V3(Float(cell.x), Float(cell.y), Float(cell.z)) + 0.5)
                    let ad = simd_abs(d)
                    let face = ad.x >= ad.y && ad.x >= ad.z ? (d.x > 0 ? 0 : 1) : (ad.y >= ad.z ? (d.y > 0 ? 2 : 3) : (d.z > 0 ? 4 : 5))
                    let cur = s.damage[cell]
                    let lv = min(7, max(Int((cur ?? 0) & 31), 1 + Int(share * 6)))
                    let f = cur.map { Int($0 >> 5) } ?? face
                    if cur == nil && s.damage.count > 6000 { continue }
                    s.damage[cell] = UInt8(f << 5 | lv)
                    chipped.append(cell)
                }
            }
            if destroyed.isEmpty {
                if !chipped.isEmpty { s.mesh.rebuildAround(s, chipped, device: world.device, queue: meshQueue) }
                continue
            }
            let kinds = ShipParts.kinds
            for cell in destroyed {
                let b = g.get(cell.x, cell.y, cell.z)
                // Capital hulls keep their counts up to date here (no full-grid rebuild per blast).
                if s.kinematic {
                    if kinds[Int(b)] == .engine { s.engines -= 1 }
                    if s.helm == cell { s.helm = nil }
                }
                let at = s.toWorld(V3(Float(cell.x), Float(cell.y), Float(cell.z)) + 0.5)
                if let game {
                    if Rand.float(in: 0..<1) < 1 / max(1, power) {
                        for st in Mining.drops(b, ItemStack(Items.id("netherite_pickaxe"), 1)) { game.drops.spawn(st, at: at) }
                    }
                    if let be = s.blockEntities[cell] { for st in be.container.slots where !st.isEmpty { game.drops.spawn(st, at: at) } }
                }
                s.blockEntities.removeValue(forKey: cell)
                s.damage.removeValue(forKey: cell)
                g.set(cell.x, cell.y, cell.z, AIR)
            }
            if pilot === s, let h = s.helm, destroyed.contains(h) { pilot = nil; s.piloted = false }
            if s.kinematic {
                // A 7-million-cell grid can't be rebuilt or flood-filled per blast: count, remesh the touched sections.
                s.blockCount -= destroyed.count
                s.mesh.rebuildAround(s, Array(destroyed) + chipped, device: world.device, queue: meshQueue)
                detachLoose(s, around: Array(destroyed))
                continue
            }
            // Push: an impulse away from the blast, applied at the blast point.
            let away = s.pos - c
            let dist = max(1, simd_length(away))
            let j = simd_normalize(away + V3(0, 0.2, 0)) * (power * 6 / dist)
            if s.parent == nil {
                s.vel += j / s.mass
                s.angVel += s.invInertiaWorld * simd_cross(c - s.pos, j) * 0.3
            }
            s.rebuild()
            if s.blockCount == 0 { remove(s, turrets: false); continue }
            s.mesh.rebuildAround(s, Array(destroyed), device: world.device, queue: meshQueue)
            splitIfNeeded(s)
        }
    }
}

// MARK: Hull splitting

extension ShipManager {
    // After blocks were removed: every part no longer connected to the largest one becomes its own ship,
    // keeping its place, motion, block entities and the turrets mounted on it.
    func splitIfNeeded(_ s: Ship) {
        let g = s.grid
        let sx = g.sx, sy = g.sy, sz = g.sz
        let n = sx * sy * sz
        if s.blockCount < 2 { return }
        var comp = [Int32](repeating: -1, count: n)
        var sizes: [Int] = []
        var queue = [Int32]()
        queue.reserveCapacity(1024)
        let dirs: [(Int, Int, Int)] = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
        for start in 0..<n where g.blocks[start] != AIR && comp[start] < 0 {
            let id = Int32(sizes.count)
            comp[start] = id
            queue.removeAll(keepingCapacity: true)
            queue.append(Int32(start))
            var head = 0
            while head < queue.count {
                let i = Int(queue[head]); head += 1
                let y = i / (sx * sz), rem = i - y * sx * sz, z = rem / sx, x = rem - z * sx
                for (dx, dy, dz) in dirs {
                    let nx = x + dx, ny = y + dy, nz = z + dz
                    if nx < 0 || ny < 0 || nz < 0 || nx >= sx || ny >= sy || nz >= sz { continue }
                    let j = nx + nz * sx + ny * sx * sz
                    if comp[j] >= 0 || g.blocks[j] == AIR { continue }
                    comp[j] = id
                    queue.append(Int32(j))
                }
            }
            sizes.append(queue.count)
        }
        if sizes.count < 2 { return }
        let keep = sizes.indices.max { sizes[$0] < sizes[$1] }!
        var parts = [[Int]](repeating: [], count: sizes.count)
        for i in 0..<n where comp[i] >= 0 && Int(comp[i]) != keep { parts[Int(comp[i])].append(i) }
        let mounted = turrets(of: s)
        for (pi, cells) in parts.enumerated() where pi != keep && !cells.isEmpty {
            var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
            for i in cells {
                let y = i / (sx * sz), rem = i - y * sx * sz, z = rem / sx, x = rem - z * sx
                lo = IVec3(min(lo.x, x), min(lo.y, y), min(lo.z, z)); hi = IVec3(max(hi.x, x), max(hi.y, y), max(hi.z, z))
            }
            let ng = ShipGrid(sx: hi.x - lo.x + 1, sy: hi.y - lo.y + 1, sz: hi.z - lo.z + 1)
            let part = Ship(id: newId(), grid: ng)
            for i in cells {
                let y = i / (sx * sz), rem = i - y * sx * sz, z = rem / sx, x = rem - z * sx
                let c = IVec3(x, y, z)
                ng.set(x - lo.x, y - lo.y, z - lo.z, g.blocks[i])
                if let be = s.blockEntities.removeValue(forKey: c) { part.blockEntities[ivSub(c, lo)] = be }
                g.set(x, y, z, AIR)
            }
            let off = V3(Float(lo.x), Float(lo.y), Float(lo.z))
            part.name = s.name + " wreck"
            part.rebuild()
            part.rot = s.rot
            part.pos = s.toWorld(off + part.com)
            part.prevPos = part.pos; part.prevRot = part.rot
            part.vel = s.velocity(at: part.pos)
            part.angVel = s.angVel
            part.updateBounds()
            // Turrets whose ring went with this part.
            for t in mounted {
                let ring = t.mountLocal - V3(0.5, 1, 0.5)
                let rc = IVec3(Int(floor(ring.x + 0.01)), Int(floor(ring.y + 0.01)), Int(floor(ring.z + 0.01)))
                if rc.x >= lo.x && rc.x <= hi.x && rc.y >= lo.y && rc.y <= hi.y && rc.z >= lo.z && rc.z <= hi.z
                    && ng.get(rc.x - lo.x, rc.y - lo.y, rc.z - lo.z) != AIR {
                    t.parent = part; t.parentId = part.id
                    t.mountLocal -= off
                }
            }
            add(part)
            part.mesh.rebuildAll(part, device: world.device, queue: meshQueue)
        }
        // Turrets whose ring is gone fall free.
        for t in mounted where t.parent === s {
            let ring = t.mountLocal - V3(0.5, 1, 0.5)
            if s.grid.get(Int(floor(ring.x + 0.01)), Int(floor(ring.y + 0.01)), Int(floor(ring.z + 0.01))) == AIR { t.parent = nil; t.parentId = nil }
        }
        let wasPiloted = pilot === s
        s.rebuild()
        s.mesh.rebuildAll(s, device: world.device, queue: meshQueue)
        if wasPiloted && s.helm == nil { pilot = nil; s.piloted = false }
    }
}
