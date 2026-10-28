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
    var power: Float
    var gravity: Float = 20
    var kind = 0                     // 0 cannon shell, 1 rail slug (capital main guns), 2 missile, 3 Tidebreaker slug (craters),
                                     // 4 torpedo (a cannon fired under water), 5 depth charge (bursts at fuseY: Submarines.swift),
                                     // 6 a calibre gun's shell (P477: CannonCalibre)
    var fuseY: Float = -1000
    var life: Float = 10
    // Missiles steer toward their target (a ship, a mob or the player) and burst near it.
    weak var seekShip: Ship?
    weak var seekMob: Mob?
    var seekPlayer = false
    var seekPoint: V3?
    var gentle = false               // hurts, breaks no blocks (an auto-turret's shell: Wrecks.swift)
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
    // laid: each turret fires at its own elevation (gunPitch), as the tank sight laid it (P477: guns of different shells).
    func fire(_ s: Ship, pitch: Float, game: Game?, laid: Bool = false) -> Int {
        var fired = 0
        for t in [s] + turrets(of: s) where t.reload <= 0 && !t.cannons.isEmpty {
            let elev = max(t.pitchMin, min(t.pitchMax, laid && t !== s ? t.gunPitch : pitch))
            var longest = 0
            var calReload: Float = 0                     // (P477: the slowest calibre gun's reload, if any fired)
            for (i, (c, d)) in t.cannons.enumerated() {
                // P459: Gun Barrels on from the muzzle: a harder, faster shell from the far end of the tube.
                let tubes = i < t.cannonLength.count ? t.cannonLength[i] : 0
                longest = max(longest, tubes)
                let muzzle = t.toWorld(c + d * (0.9 + Float(tubes)))
                var dir = t.dirToWorld(d)
                let horiz = simd_normalize(V3(dir.x, 0, dir.z) + V3(1e-5, 0, 0))
                dir = simd_normalize(horiz * cosf(elev) + V3(0, sinf(elev), 0))
                if t.gunScatter > 0 { dir = Guns.scatter(dir, t.gunScatter) }
                // P455 (Oct 25 14:24-14:25, a captured crawler's guns: "not doing enough damage... more damage from the
                // guns on this crawler and related guns"): a war vessel's guns fired from its helm by him hit half again
                // as hard (its crew's stay as they were).
                let his = game != nil && pilot?.root === t.root && t.root.role != nil
                let long: Float = 1 + 0.4 * Float(tubes), quick: Float = 1 + 0.12 * Float(tubes)
                let sh = Shell(pos: muzzle, vel: dir * (t.gunSpeed * quick) + t.velocity(at: muzzle), owner: t.root.id, power: t.gunPower * (his ? 1.5 : 1) * long)
                sh.gravity = t.gunGravity
                // P477: a gun with a calibre barrel fires a shell flat and fast, its punch and reload by bore.
                if i < t.cannonCalibre.count, t.cannonCalibre[i] > 0 {
                    let spec = CannonCalibre.spec(t.cannonCalibre[i])
                    let extra = Float(max(0, tubes - 1))
                    var cdir = dir
                    if spec.scatter > 0 { cdir = Guns.scatter(cdir, spec.scatter) }
                    sh.vel = cdir * (spec.speed * (1 + 0.06 * extra)) + t.velocity(at: muzzle)
                    sh.gravity = spec.gravity
                    sh.kind = 6
                    // P477: a vessel the world built (a Capital warship, a patrol, a corsair) keeps its mount's own punch and
                    // reload (the crews' guns as tuned; half again from his helm); the barrels give its shell's flight.
                    if t.root.role?.isEmpty == false {
                        sh.power = t.gunPower * (his ? 1.5 : 1)
                        calReload = max(calReload, t.reloadTime)
                    } else {
                        sh.power = min(CannonCalibre.maxPower, spec.power * (1 + 0.15 * extra) * (his ? 1.5 : 1))
                        calReload = max(calReload, spec.reload * (1 + 0.05 * extra))
                    }
                }
                // A cannon under water looses a torpedo: level, self-driven, no drop (C8, Submarines.swift).
                if Blocks.fluidKind[Int(world.rawBlock(Int(floor(muzzle.x)), Int(floor(muzzle.y)), Int(floor(muzzle.z))))] == 1 {
                    sh.kind = 4; sh.gravity = 0; sh.life = Submarine.torpedoLife
                    sh.vel = horiz * Submarine.torpedoSpeed + t.velocity(at: muzzle)
                    if let g = game { Submarine.lastShot = g.clock }
                }
                shells.append(sh)
                fired += 1
                if let g = game {
                    // Naval guns (fast, heavy shells) boom louder and further.
                    g.sfx(.shipCannon, t.gunPower > 3 ? 1.6 : 1, at: muzzle)
                    g.particles.smoke(at: muzzle)
                    g.baseNoise(at: muzzle, kind: .cannon, hostile: s.factionValue != .steelhold)   // the Capital's own guns don't alarm it
                }
            }
            t.reload = calReload > 0 ? calReload : t.reloadTime * (1 + 0.1 * Float(longest))
        }
        return fired
    }

    // Shells as small dark cubes; rail slugs as glowing bolts, missiles as pale darts.
    func writeShells(_ wr: inout EntityWriter, eye: V3) {
        if shells.isEmpty { return }
        let b = Blocks.has("coal_block") ? Blocks.id("coal_block") : STONE
        let slug = Blocks.has("magma_block") ? Blocks.id("magma_block") : b
        let dart = Blocks.has("iron_block") ? Blocks.id("iron_block") : b
        let mac = Blocks.has("frigate_thruster") ? Blocks.id("frigate_thruster") : slug
        for sh in shells {
            switch sh.kind {
            case 1:
                // A streak: a few cubes back along the flight path.
                let d = simd_length(sh.vel) > 0.01 ? simd_normalize(sh.vel) : V3(0, 0, -1)
                for k in 0..<4 { wr.cube(center: sh.pos - d * Float(k) * 0.9 - eye, half: 0.45 - Float(k) * 0.08, yaw: sh.age * 9, block: slug, light: 1) }
            case 2: wr.cube(center: sh.pos - eye, half: 0.16, yaw: sh.age * 14, block: dart, light: 1)
            case 4:
                let d = simd_length(sh.vel) > 0.01 ? simd_normalize(sh.vel) : V3(0, 0, -1)
                for k in 0..<3 { wr.cube(center: sh.pos - d * Float(k) * 0.3 - eye, half: 0.17, yaw: 0, block: dart, light: 1) }
            case 5: wr.cube(center: sh.pos - eye, half: 0.3, yaw: sh.age * 3, block: b, light: 1)
            case 6:
                // P477: a calibre gun's shell: a steel body sized by its punch with a glowing tracer behind.
                let d = simd_length(sh.vel) > 0.01 ? simd_normalize(sh.vel) : V3(0, 0, -1)
                let h = min(0.3, 0.07 + sh.power * 0.012)
                wr.cube(center: sh.pos - eye, half: h, yaw: 0, block: dart, light: 1)
                wr.cube(center: sh.pos - d * h * 2 - eye, half: h * 0.9, yaw: 0, block: dart, light: 1)
                wr.cube(center: sh.pos - d * h * 4.5 - eye, half: h * 0.6, yaw: sh.age * 9, block: slug, light: 1)
            case 3:
                // The Tidebreaker's slug: a long white-blue streak.
                let d = simd_length(sh.vel) > 0.01 ? simd_normalize(sh.vel) : V3(0, 0, -1)
                for k in 0..<8 { wr.cube(center: sh.pos - d * Float(k) * 1.2 - eye, half: 0.6 - Float(k) * 0.06, yaw: sh.age * 9, block: mac, light: 1) }
            default: wr.cube(center: sh.pos - eye, half: sh.power > 3 ? 0.26 : 0.18, yaw: sh.age * 9, block: b, light: 1)
            }
        }
    }

    // Moves shells and detonates them (call once per frame).
    func updateShells(_ dt: Float, game: Game?) {
        for s in list { s.reload = max(0, s.reload - dt) }
        if let g = game { updateShockwaves(dt, game: g); TickProf.mark("ships.shockwaves") }
        if shells.isEmpty { return }
        var reader = ShipBlockReader(world)
        var keep: [Shell] = []
        var blasts: [(V3, Float, Int, Bool, Int, Bool, V3)] = []
        for sh in shells {
            sh.age += dt
            let start = sh.pos
            // Missiles: track the target and turn toward it (2.5 rad/s), smoking; a proximity fuse.
            var near = false
            if sh.kind == 2 {
                var aim: V3? = sh.seekPoint
                if let t = sh.seekShip { aim = t.pos }
                if let m = sh.seekMob { aim = m.health > 0 ? m.pos + V3(0, m.height * 0.5, 0) : aim }
                if sh.seekPlayer, let g = game { aim = g.coop.nearestPlayerPos(sh.pos, g) + V3(0, 1, 0) }   // the nearer player (split screen)
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
            // The Tidebreaker's slug leaves a glowing wake that hangs in the air for a moment.
            if sh.kind == 3, let g = game {
                let layer = Int(Tex.id("puff"))
                for k in 0..<3 {
                    let at = start + sh.vel * (dt * Float(k) / 3)
                    g.particles.add(Particle(pos: at, vel: V3(Rand.float(in: -0.3...0.3), Rand.float(in: 0...0.5), Rand.float(in: -0.3...0.3)),
                                             life: 0.7, maxLife: 0.7, layer: layer, uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 0.5...0.8),
                                             gravity: 0, color: V3(0.6, 0.85, 1), collide: false, glow: true))
                }
            }
            sh.vel.y -= sh.gravity * dt
            // Torpedoes run level under water and drop once out of it; depth charges sink slowly in it and burst at depth.
            if sh.kind == 4 || sh.kind == 5 {
                let wet = Blocks.fluidKind[Int(reader.get(Int(floor(start.x)), Int(floor(start.y)), Int(floor(start.z))))] == 1
                if sh.kind == 4 && !wet { sh.vel.y -= 20 * dt }
                if sh.kind == 5 { sh.vel.y = wet ? max(sh.vel.y - 8 * dt, -Submarine.chargeSink) : sh.vel.y - 20 * dt }
                if wet, let g = game, Int(sh.age * 20) % 3 == 0 { g.particles.bubble(at: start) }
                if sh.kind == 5 && start.y <= sh.fuseY { near = true }
                // P278: a charge passing close by a hull goes off beside it.
                if sh.kind == 5 && wet && sh.age > 0.4 && nearHull(start, except: sh.owner, reach: DepthCharge.proximity) { near = true }
            }
            let end = start + sh.vel * dt
            let len = simd_length(end - start)
            let n = max(1, Int(ceil(len / 0.4)))
            var hit: V3?
            var onHull = false
            for i in 1...n {
                let p = start + (end - start) * (Float(i) / Float(n))
                let bx = Int(floor(p.x)), bz = Int(floor(p.z))
                if Blocks.collide[Int(reader.get(bx, Int(floor(p.y)), bz))] { hit = p; break }
                // A Tidebreaker slug past the loaded world lands on the generator's ground (it flew on through it,
                // unseen: the far end of a long shot from the helm).
                if sh.kind == 3 && !reader.loaded(bx, bz) && p.y <= Float(world.gen.column(bx, bz).height) + 1 { hit = p; break }
                if shipBlock(at: p, except: sh.owner) { hit = p; onHull = true; break }
                if let g = game, sh.age > 0.25 {                   // (clear of the gun crew first)
                    if let m = g.mobs.mobs.first(where: { $0.health > 0 && simd_length($0.pos + V3(0, $0.height * 0.5, 0) - p) < max(0.8, $0.halfW + 0.4) }) {
                        // P345: nobody survives a cannon round to the body (a deck gun or a vehicle still only takes the blast).
                        if !sh.gentle && !m.kind.shellProof {
                            if g.world.ships.pilot?.root.id == sh.owner { m.killedByPlayer = true; m.playerHurtAt = g.clock }
                            m.hit(from: p - simd_normalize(sh.vel + V3(0, 1e-4, 0)) * 2, damage: m.health + 1000, knockback: 1.2)
                        }
                        hit = p; break
                    }
                    // Any player's body (split screen: shells passed through player 2); the shooter's own helmsman aside.
                    var bodyHit = false
                    for i in 0..<max(1, g.coop.seatCount) {
                        let pr = g.coop.seatPlayer(i, g).pos + V3(0, 0.9, 0)
                        if simd_length(pr - p) < 0.8 { bodyHit = true }
                    }
                    if bodyHit && g.world.ships.pilot?.root.id != sh.owner { hit = p; break }
                }
            }
            if near && hit == nil { hit = start }
            if let p = hit { blasts.append((p, sh.power, sh.owner, onHull, sh.kind, sh.gentle, sh.vel)); continue }
            sh.pos = end
            if sh.age < sh.life && sh.pos.y > -64 { keep.append(sh) }
        }
        shells = keep
        for (p, power, owner, onHull, kind, gentle, vel) in blasts {
            if kind == 3, let g = game {
                let hit = onHull ? list.first(where: { $0.root.id != owner && shipBlock(in: $0, at: p) }) : nil
                mainGunImpact(at: p, owner: owner, game: g, along: vel)
                mainGunHullDamage(at: p, owner: owner, direct: hit, game: g)
                continue
            }
            if let g = game {
                // The Capital's own guns don't alarm its citadels (CapitalBases.swift).
                let from = list.first { $0.id == owner }
                // A side's ship guns spare its own soldiers (marines boarding beside the impact), as their shells do.
                // (Not a hull the player steers: a captured frigate's guns hit its old side.)
                let steered = from != nil && g.world.ships.pilot?.root.id == from?.root.id
                // P459 (Oct 25 16:39-16:40, flying a taken Capital Dropship over the Capital: "There's nothing to the
                // Capitol building", "nothing's happening to the capital when it's hit"): the Capital's own guns leave
                // its citadels standing (bases.quiet), and a Capital hull he flew still counted as theirs, so his
                // autocannon broke nothing inside a base and spared its garrison. Steered by him, it's his gun.
                g.bases.quiet = from?.factionValue == .steelhold && !steered
                g.blastSpares = steered ? .none : (from?.factionValue ?? .none)
                if kind == 5 { g.depthChargeBurst(at: p, power: power, owner: owner) }     // P278: boom, plume, pressure wave
                Explosion.explode(at: p, power: power, game: g, breakBlocks: !gentle, along: onHull ? nil : vel)   // (P357 e)
                g.bases.quiet = false; g.blastSpares = .none
                // War vessels' guns bite much deeper into another hull than the plain burst (crawler duels barely
                // scratched paint, Quest round 4).
                if onHull && from?.root.kinematic == true { blast(at: p, power: power * 1.5, game: g) }
            } else if !gentle { blast(at: p, power: power, game: nil) }
        }
    }

    // The first solid ship block along a segment (0.4-block steps), skipping the root `except`: hand-held rockets
    // and heavy gun shells (Armory) flew straight through hulls.
    func segmentHit(_ o: V3, _ d: V3, _ len: Float, except: Int) -> (Float, Ship)? {
        let lo = simd_min(o, o + d * len), hi = simd_max(o, o + d * len)
        for s in list where s.root.id != except && hi.x > s.worldMin.x && lo.x < s.worldMax.x && hi.y > s.worldMin.y
            && lo.y < s.worldMax.y && hi.z > s.worldMin.z && lo.z < s.worldMax.z {
            let n = max(1, Int(ceil(len / 0.4)))
            for i in 0...n {
                let t = len * Float(i) / Float(n)
                let l = s.toLocal(o + d * t)
                if Blocks.collide[Int(s.grid.get(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z))))] { return (t, s) }
            }
        }
        return nil
    }

    // A 42 cm shell striking a Capital vessel (Quest round 4: hits barely scratched them): the drive engines are
    // knocked out (a frigate goes down, a crawler stops: CapitalShips' disable check) and the hull is torn open.
    // P464 (Oct 25 20:16, "Was the base shooting this thing? ... That's what brought down the engines"): only a heavy
    // gun's shell (one whose burst breaks blocks) fired by him stops the drive, and never on a vessel he has taken;
    // flak bursts at its own strength (every base shell was striking as his 42 cm shell and stopping them: a base's
    // guns wear a frigate down block by block now, its drive failing as they shoot its engines away).
    func heavyHit(_ s: Ship, at p: V3, game: Game, power: Float = 6, resistCap: Float = .infinity, stopsEngines: Bool = true) {
        let r = s.root
        blast(at: p, power: power, game: game, resistCap: resistCap)
        if stopsEngines && !r.captured && r.kinematic && r.parent == nil && r.role != nil { r.engines = 0 }   // after the blast (its rebuild recounts them)
    }

    // Whether a world point is inside a solid block of ship s.
    func shipBlock(in s: Ship, at p: V3) -> Bool {
        guard p.x > s.worldMin.x && p.x < s.worldMax.x && p.y > s.worldMin.y && p.y < s.worldMax.y && p.z > s.worldMin.z && p.z < s.worldMax.z else { return false }
        let l = s.toLocal(p)
        return Blocks.collide[Int(s.grid.get(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z))))]
    }

    // Whether any ship is about, and whether a world point is inside a ship's solid block (drops and debris resting on
    // decks: P70).
    var any: Bool { !list.isEmpty }
    func solid(at p: V3) -> Bool { !list.isEmpty && shipBlock(at: p, except: -1) }

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
    func blast(at c: V3, power: Float, game: Game?, resistCap: Float = .infinity) {
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
                        let cost: Float = (Explosion.capped(b, Blocks.resistance[Int(b)], resistCap) + 0.3) * 0.3
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
            removeCells(s, destroyed, chipped: chipped, center: c, power: power, game: game)
        }
    }

    // Removes a blast's destroyed cells from ship s (drops, counts, remesh; a free ship is pushed, rebuilt and split).
    func removeCells(_ s: Ship, _ destroyed: Set<IVec3>, chipped: [IVec3], center c: V3, power: Float, game: Game?, detach: Bool = true) {
        let g = s.grid
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
                for st in Explosion.blastDrops(b) { game.drops.spawn(st, at: at) }                 // (P452)
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
            if detach { detachLoose(s, around: Array(destroyed)) }
            return
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
        if s.blockCount == 0 { remove(s, turrets: false); return }
        s.mesh.rebuildAround(s, Array(destroyed), device: world.device, queue: meshQueue)
        splitIfNeeded(s)
    }

    // The Tidebreaker's slug through a hull: every breakable cell within `radius` of c is torn out, whatever its
    // resistance (capital plate and light panels shrug off ordinary blasts), so a hit leaves a hole you can see.
    // What a Tidebreaker slug does to vessels (Oct 11 playtest, G13: "against a crawler it should tear off a huge chunk
    // or destroy it outright"). Into a hull: a hole MainGun.hullTear blocks across torn through it and the drive
    // knocked out (a Capital vessel goes down, a crawler is wrecked). A near miss on the ground beside a vessel still
    // tears the side nearest the blast, smaller with distance, and one within MainGun.disableMiss blocks wrecks it too.
    func mainGunHullDamage(at p: V3, owner: Int, direct: Ship?, game g: Game) {
        func disable(_ r: Ship) { if r.kinematic && r.parent == nil && r.role != nil { r.engines = 0; MainGun.disabled += 1 } }
        if let hit = direct {
            MainGun.lastTorn = tear(at: p, radius: MainGun.hullTear, except: owner, game: g)
            disable(hit.root)
            MainGun.shipHits += 1
            return
        }
        var torn = 0
        for s in capitals where s.id != owner && !s.wrecked {
            let q = simd_clamp(p, s.worldMin, s.worldMax)       // the nearest point of its bounds
            let d = simd_length(q - p)
            guard d < MainGun.nearMiss else { continue }
            // Toward the hull from that point: the first hull block along the line from the blast to its centre.
            let mid = (s.worldMin + s.worldMax) * 0.5
            var at = q
            let step = simd_normalize(mid - q + V3(1e-4, 0, 0))
            var n = Int(simd_length(mid - q))
            while n > 0 && !shipBlock(in: s, at: at) { at += step; n -= 1 }
            torn += tear(at: at, radius: MainGun.hullTear - d * 0.6, except: owner, game: g)
            if d < MainGun.disableMiss { disable(s) }
        }
        if torn > 0 { MainGun.lastTorn = torn; MainGun.shipHits += 1 }
    }

    func tear(at c: V3, radius: Float, except: Int, game: Game?) -> Int {
        var total = 0
        for s in list where s.root.id != except && c.x > s.worldMin.x - radius && c.x < s.worldMax.x + radius && c.y > s.worldMin.y - radius
            && c.y < s.worldMax.y + radius && c.z > s.worldMin.z - radius && c.z < s.worldMax.z + radius {
            let lc = s.toLocal(c)
            let ri = Int(ceilf(radius))
            var destroyed = Set<IVec3>()
            for dz in -ri...ri { for dy in -ri...ri { for dx in -ri...ri {
                let o = V3(Float(dx), Float(dy), Float(dz))
                guard simd_length(o) <= radius * (0.8 + 0.2 * hashf(dx, dy, dz, 977)) else { continue }
                let cell = IVec3(Int(floor(lc.x)) + dx, Int(floor(lc.y)) + dy, Int(floor(lc.z)) + dz)
                let b = s.grid.get(cell.x, cell.y, cell.z)
                if b != AIR && Blocks.hardness[Int(b)] >= 0 { destroyed.insert(cell) }
            } } }
            if destroyed.isEmpty { continue }
            total += destroyed.count
            removeCells(s, destroyed, chipped: [], center: c, power: 14, game: game)
        }
        return total
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
        // P473: a hull drawn as its model (a Salvaged Fighter, a taken truck or sidecar) sheds its broken-off pieces as
        // debris of their plate, not as hulls of blocks.
        if AshWrecks.skinned(s), let game = Hulks.game {
            var seed = UInt32(truncatingIfNeeded: s.id &* 2654435761)
            for (pi, cells) in parts.enumerated() where pi != keep && !cells.isEmpty {
                var c = V3.zero
                for i in cells {
                    let y = i / (sx * sz), rem = i - y * sx * sz, z = rem / sx, x = rem - z * sx
                    c += V3(Float(x), Float(y), Float(z))
                }
                let at = s.toWorld(c / Float(cells.count) + V3(0.5, 0.5, 0.5))
                let b = g.blocks[cells[0]]
                let e = Float(min(cells.count, 8)).squareRoot() * 0.45
                seed = seed &* 1664525 &+ 1013904223
                let out = at - s.pos
                game.debris.bits(b, at: at, size: SIMD3(e, e * 0.6, e), direction: simd_length(out) > 1e-3 ? simd_normalize(out) : V3(0, 1, 0),
                              count: 2, speed: 5, seed: seed)
                for i in cells {
                    let y = i / (sx * sz), rem = i - y * sx * sz, z = rem / sx, x = rem - z * sx
                    s.blockEntities.removeValue(forKey: IVec3(x, y, z))
                    g.set(x, y, z, AIR)
                }
            }
            let wasPiloted = pilot === s
            s.rebuild()
            s.mesh.rebuildAll(s, device: world.device, queue: meshQueue)
            if wasPiloted && s.helm == nil { pilot = nil; s.piloted = false }
            return
        }
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
            // (P441, Oct 24 20:50: "this log turned into a square": a felled trunk chopped in two left a "wreck" that drew
            // as cube logs; a felled tree's pieces are felled trees, round, and fall on their own)
            part.name = Felling.isFelled(s) ? Felling.name : s.name + " wreck"
            if Felling.isFelled(s) { Felling.inherit(s, part) }
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
