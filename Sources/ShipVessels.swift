import Foundation
import simd

// Huge vehicles built on the ship system, and their rare world encounters:
// - Skyward Frigate: a 48-block flying warship under a lift envelope, two cannon turrets and broadside guns,
//   crewed by Steelhold soldiers; it patrols in slow circles and shells players who come close.
// - Ironstride Siege Carriage: a six-wheeled armoured gun platform with a giant turret, roaming open land.
// Both are original designs. Blueprints build ships straight into their grids (no world assembly); an encounter
// is decided per 2048-block region from the world seed, so they are rare and always in the same place.

final class Blueprint {
    var cells: [IVec3: BlockID] = [:]
    var turrets: [(ring: IVec3, bp: Blueprint)] = []     // turret cells are relative to the cell above the ring
    var chests: [(IVec3, String)] = []                   // chest cell, loot table
    var crew: [V3] = []                                  // crew stations (ship space of the blueprint)

    func set(_ x: Int, _ y: Int, _ z: Int, _ name: String) {
        let b = Blocks.has(name) ? Blocks.id(name) : PLANKS
        cells[IVec3(x, y, z)] = b
    }
    func clear(_ x: Int, _ y: Int, _ z: Int) { cells.removeValue(forKey: IVec3(x, y, z)) }
    func box(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ z0: Int, _ z1: Int, _ name: String, hollow: Bool = false) {
        for y in y0...y1 { for z in z0...z1 { for x in x0...x1 {
            if hollow && x > x0 && x < x1 && y > y0 && y < y1 && z > z0 && z < z1 { continue }
            set(x, y, z, name)
        } } }
    }
}

extension ShipManager {
    // A ship (and its turrets) from a blueprint, its centre of mass at `at`, heading `yaw`.
    @discardableResult
    func spawn(_ bp: Blueprint, at: V3, yaw: Float, name: String, role: String) -> Ship {
        func grid(_ cells: [IVec3: BlockID]) -> (ShipGrid, IVec3) {
            var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
            for c in cells.keys {
                lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z))
                hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z))
            }
            let g = ShipGrid(sx: hi.x - lo.x + 1, sy: hi.y - lo.y + 1, sz: hi.z - lo.z + 1)
            for (c, b) in cells { g.set(c.x - lo.x, c.y - lo.y, c.z - lo.z, b) }
            return (g, lo)
        }
        let (g, lo) = grid(bp.cells)
        let s = Ship(id: newId(), grid: g)
        s.name = name
        s.role = role
        s.rebuild()
        s.rot = Quat(angle: yaw, axis: V3(0, 1, 0))
        s.pos = at
        s.prevPos = s.pos; s.prevRot = s.rot
        for (c, table) in bp.chests {
            let be = BlockEntity(.chest)
            var rng = SRng(UInt64(bitPattern: Int64(c.x * 73856093 ^ c.z * 19349663 ^ s.id)) | 1)
            Loot.fill(be.container, table: table, rng: &rng)
            s.blockEntities[ivSub(c, lo)] = be
        }
        s.updateBounds()
        add(s)
        s.mesh.rebuildAll(s, device: world.device, queue: meshQueue)
        for (ring, tb) in bp.turrets {
            let (tg, tlo) = grid(tb.cells)
            let t = Ship(id: newId(), grid: tg)
            t.name = name + " turret"
            t.rebuild()
            t.parent = s
            t.parentId = s.id
            t.mountLocal = V3(Float(ring.x - lo.x) + 0.5, Float(ring.y - lo.y) + 1, Float(ring.z - lo.z) + 0.5)
            t.pivot = V3(0.5 - Float(tlo.x), -Float(tlo.y), 0.5 - Float(tlo.z))
            t.followParent(0)
            t.prevPos = t.pos; t.prevRot = t.rot
            add(t)
            t.mesh.rebuildAll(t, device: world.device, queue: meshQueue)
        }
        s.crewStations = bp.crew.map { $0 - V3(Float(lo.x), Float(lo.y), Float(lo.z)) }
        return s
    }
}

enum Vessels {
    // MARK: Skyward Frigate (bow toward -Z, keel at y 0, centreline x 0)

    static func frigate() -> Blueprint {
        let b = Blueprint()
        let L = 48
        func half(_ z: Int) -> Float {
            let zf = Float(z)
            if zf < 10 { return 1.2 + zf * 0.42 }
            if zf > 40 { return 5.4 - (zf - 40) * 0.25 }
            return 5.4
        }
        // Hull cross-section narrows toward the keel.
        func inside(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            if z < 0 || z >= L || y < 0 || y > 4 { return false }
            let w = y == 4 ? half(z) : max(0.6, half(z) - Float(3 - y) * 0.9)
            return Float(abs(x)) <= w.rounded()
        }
        for z in 0..<L { for y in 0...4 { for x in -7...7 where inside(x, y, z) {
            let edge = y == 0 || y == 4 || !inside(x + 1, y, z) || !inside(x - 1, y, z) || !inside(x, y, z + 1) || !inside(x, y, z - 1)
            if !edge { continue }
            if y == 4 { b.set(x, y, z, abs(x) == Int(half(z).rounded()) ? "dark_oak_planks" : "oak_planks") }
            else { b.set(x, y, z, y == 0 || y == 3 ? "dark_oak_planks" : "spruce_planks") }
        } } }
        // Railing round the deck.
        for z in 0..<L { for x in -7...7 where inside(x, 4, z) && (!inside(x + 1, 4, z) || !inside(x - 1, 4, z) || !inside(x, 4, z + 1) || !inside(x, 4, z - 1)) {
            b.set(x, 5, z, "spruce_fence")
        } }
        // Bridge with windows, helm and the captain's chest.
        b.box(-3, 3, 5, 8, 36, 42, "spruce_planks", hollow: true)
        for x in -2...2 { b.set(x, 7, 36, "glass_pane") }
        for z in 37...41 { b.set(-3, 7, z, "glass_pane"); b.set(3, 7, z, "glass_pane") }
        b.box(-3, 3, 9, 9, 36, 42, "spruce_slab")
        b.clear(0, 5, 42); b.clear(0, 6, 42)                      // door
        b.set(0, 5, 38, "ship_helm[south]")
        b.set(-2, 5, 41, "chest")
        b.chests.append((IVec3(-2, 5, 41), "end_city_treasure"))
        b.set(2, 6, 40, "lantern")
        // Engine room and stern propellers.
        for x in -2...2 { b.set(x, 1, 44, "ship_engine") }
        for x in [-3, -1, 1, 3] { b.set(x, 2, L, "ship_propeller[south]") }
        // Two more on outriggers beside the stern.
        for x in [-6, 6] { b.set(x, 3, 40, "spruce_planks"); b.set(x, 3, 41, "ship_propeller[south]") }
        // Lift envelope on posts.
        for z in 4..<44 { for y in 11...16 { for x in -6...6 {
            let ex = Float(x) / 6.2, ey = (Float(y) - 13.5) / 3.2, ez = (Float(z) - 24) / 20.5
            if ex * ex + ey * ey + ez * ez <= 1 { b.set(x, y, z, "ship_balloon") }
        } } }
        for (x, z) in [(-2, 16), (2, 16), (-2, 24), (2, 24), (-2, 32), (2, 32), (0, 14), (0, 34)] {
            for y in 5...12 where b.cells[IVec3(x, y, z)] == nil { b.set(x, y, z, "oak_log") }
        }
        // Broadside guns (muzzles out: west side faces east, east side faces west).
        for z in [13, 20, 27] { b.set(-4, 5, z, "ship_cannon[east]"); b.set(4, 5, z, "ship_cannon[west]") }
        // Fore and aft turrets.
        for rz in [9, 29] {
            b.set(0, 5, rz, "ship_turret_ring")
            let t = Blueprint()
            t.box(-1, 1, 0, 0, -1, 1, "iron_block")
            t.box(-1, 1, 1, 1, -1, 1, "polished_blackstone")
            t.set(-1, 1, -2, "ship_cannon[south]"); t.set(1, 1, -2, "ship_cannon[south]")
            b.turrets.append((IVec3(0, 5, rz), t))
        }
        b.crew = [V3(0.5, 5, 20.5), V3(-2.5, 5, 26.5), V3(2.5, 5, 12.5), V3(0.5, 5, 40.5)]
        return b
    }

    // MARK: Ironstride Siege Carriage (bow toward -Z)

    static func carriage() -> Blueprint {
        let b = Blueprint()
        // Armoured hull on six big wheels.
        b.box(-5, 5, 3, 6, 0, 22, "stone_bricks", hollow: true)
        b.box(-5, 5, 6, 6, 0, 22, "polished_blackstone")
        for x in [-5, 5] { for z in stride(from: 1, to: 22, by: 3) { b.set(x, 5, z, "iron_block") } }
        // Rail round the top deck so the crew stays aboard.
        for z in 0...22 { b.set(-5, 7, z, "nether_brick_fence"); b.set(5, 7, z, "nether_brick_fence") }
        for x in -4...4 { b.set(x, 7, 0, "nether_brick_fence") }
        for zc in [4, 11, 18] {
            for x in [-7, -6, 6, 7] { for y in 0...4 { for z in (zc - 2)...(zc + 2) {
                let dy = Float(y) - 2, dz = Float(z - zc)
                if dy * dy + dz * dz <= 6.3 { b.set(x, y, z, "ship_wheel") }
            } } }
        }
        for x in -2...2 { b.set(x, 4, 20, "ship_engine") }
        b.set(0, 4, 2, "ship_engine")
        // Cab at the stern with the helm.
        b.box(-2, 2, 7, 9, 18, 22, "stone_bricks", hollow: true)
        for x in -1...1 { b.set(x, 8, 18, "glass_pane") }
        b.box(-2, 2, 10, 10, 18, 22, "polished_blackstone_slab")
        b.clear(0, 7, 22); b.clear(0, 8, 22)
        b.set(0, 7, 20, "ship_helm[south]")
        b.set(1, 7, 21, "chest")
        b.chests.append((IVec3(1, 7, 21), "bastion"))
        // Giant turret: armoured housing, long barrel, three guns at the muzzle.
        b.set(0, 7, 9, "ship_turret_ring")
        let t = Blueprint()
        t.box(-3, 3, 0, 3, -3, 3, "polished_blackstone", hollow: true)
        t.box(-3, 3, 4, 4, -3, 3, "iron_block")
        for z in -13 ... -4 { t.set(0, 2, z, "iron_block") }
        t.box(-1, 1, 1, 3, -15, -14, "iron_block")
        t.set(0, 2, -16, "ship_cannon[south]"); t.set(-1, 2, -16, "ship_cannon[south]"); t.set(1, 2, -16, "ship_cannon[south]")
        b.turrets.append((IVec3(0, 7, 9), t))
        b.crew = [V3(-3.5, 7, 3.5), V3(3.5, 7, 15.5)]
        return b
    }

    // MARK: Encounters

    static let region = 2048
    // The encounter of a region (deterministic from the seed): kind and home point, or nil (most regions).
    static func encounter(seed: UInt64, rx: Int, rz: Int, gen: TerrainGenerator) -> (String, IVec3)? {
        let h = hashf(rx, rz, 4111, UInt32(truncatingIfNeeded: seed))
        if h > 0.235 { return nil }
        let x = rx * region + 256 + Int(hashf(rx, rz, 4112, UInt32(truncatingIfNeeded: seed)) * Float(region - 512))
        let z = rz * region + 256 + Int(hashf(rx, rz, 4113, UInt32(truncatingIfNeeded: seed)) * Float(region - 512))
        let col = gen.column(x, z)
        if h < 0.08 { return ("frigate", IVec3(x, max(col.height, SEA) + 45, z)) }
        // Capital ships (CapitalShips.swift): 3 % of regions a Stormwarden Frigate, 3 % an Ironback Crawler on land,
        // 1.5 % the two of them already fighting.
        if h >= 0.16 && h < 0.19 { return ("warfrigate", IVec3(x, max(col.height, SEA), z)) }
        if col.biome.isOcean || col.height < SEA { return nil }
        if h >= 0.22 { return ("battle", IVec3(x, col.height + 1, z)) }
        if h >= 0.19 { return ("crawler", IVec3(x, col.height + 1, z)) }
        return ("carriage", IVec3(x, col.height + 1, z))
    }
}

extension Ship {
    var isVessel: Bool { role == "frigate" || role == "carriage" || role == "warfrigate" || role == "crawler" || role == "capfrigate" }
}

extension ShipManager {
    // Spawns the region's vessel when the player comes near its home (once per world), and runs crews.
    func encounterTick(_ dt: Float, game g: Game) {
        guard world.dim == .overworld else { return }
        encounterTimer -= dt
        if encounterTimer <= 0 {
            encounterTimer = 5
            // Round every player (split screen: vessels and frigates appeared only where player 1 went).
            for seat in 0..<max(1, g.coop.seatCount) {
            let p = g.coop.seatPlayer(seat, g).pos
            stationFrigates(g, near: p)
            let rx = floorDiv(Int(p.x), Vessels.region), rz = floorDiv(Int(p.z), Vessels.region)
            for dz in -1...1 { for dx in -1...1 {
                let key = "\(rx + dx),\(rz + dz)"
                if spawnedRegions.contains(key) || capitalPending.contains(key) { continue }
                guard let e = Vessels.encounter(seed: world.seed, rx: rx + dx, rz: rz + dz, gen: world.gen) else { continue }
                let (kind, home) = e
                let d = V2(Float(home.x) - p.x, Float(home.z) - p.z)
                // Capital ships are built while the player is still far off (they are seen from far away).
                // The "frigate" encounter is now the Capital frigate (a capital ship; the Skyward Frigate airship only
                // survives in old saves).
                let capital = kind == "warfrigate" || kind == "crawler" || kind == "battle" || kind == "frigate"
                if capital {
                    if simd_length(d) > (kind == "crawler" ? 320 : 520) { continue }
                    spawnedRegions.insert(key)
                    let yaw = Float(abs(home.x * 7 + home.z * 3) % 628) / 100
                    if kind == "battle" {
                        spawnCapital("warfrigate", home: home, yaw: yaw, region: key)
                        let ch = world.gen.column(home.x + 260, home.z)
                        if ch.height > SEA { spawnCapital("crawler", home: IVec3(home.x + 260, ch.height + 1, home.z), yaw: yaw + 1.6, region: key) }
                    } else {
                        spawnCapital(kind == "frigate" ? "capfrigate" : kind, home: home, yaw: yaw, region: key)
                    }
                    continue
                }
                if simd_length(d) > 150 || !world.isLoaded(home.x, home.z) { continue }
                spawnedRegions.insert(key)
                spawnVessel(kind, home: home, game: g)
            } }
            }
        }
        crewTick(dt, game: g)
    }

    // A Capital frigate is stationed over every Capital citadel (military_base): built when the player comes within
    // 600 blocks, once per citadel (the key is saved with the vessel regions).
    func stationFrigates(_ g: Game, near at: V3? = nil) {
        guard let sc = world.gen.structures else { return }
        let p = at ?? g.player.pos
        guard let base = sc.nearest("military_base", x: Int(p.x), z: Int(p.z), maxRegions: 1) else { return }
        let cx = (base.min.x + base.max.x) / 2, cz = (base.min.z + base.max.z) / 2
        let key = "citadel:\(cx),\(cz)"
        if spawnedRegions.contains(key) || capitalPending.contains(key) { return }
        guard simd_length(V2(Float(cx) - p.x, Float(cz) - p.z)) < 600 else { return }
        spawnedRegions.insert(key)
        spawnCapital("capfrigate", home: IVec3(cx, 0, cz), yaw: Float(abs(cx * 3 + cz) % 628) / 100, region: key)
    }

    @discardableResult
    func spawnVessel(_ kind: String, home: IVec3, game g: Game?) -> Ship {
        let homeV = V3(Float(home.x) + 0.5, Float(home.y), Float(home.z) + 0.5)
        let s: Ship
        if kind == "frigate" {
            s = spawn(Vessels.frigate(), at: homeV + V3(0, 6, 0), yaw: Float(home.x % 7), name: "Skyward Frigate", role: kind)
            s.hoverY = s.pos.y
        } else {
            let x = home.x, z = home.z
            var top = home.y
            var rd = ShipBlockReader(world)
            while top > 1 && !Blocks.collide[Int(rd.get(x, top, z))] { top -= 1 }
            s = spawn(Vessels.carriage(), at: V3(homeV.x, Float(top) + 1, homeV.z), yaw: Float(home.z % 5), name: "Ironstride Siege Carriage", role: kind)
            // Lift so the lowest wheels touch the ground.
            let lift = Float(top + 1) + 0.6 - s.toWorld(V3(0, s.localMin.y, 0)).y
            s.pos.y += lift
            s.updateBounds()
        }
        s.home = homeV
        s.initialBlocks = s.blockCount
        if let g {
            // Steelhold soldiers crew the vessels (they hold their stations aboard, Animals.swift): marksmen and troopers
            // on the frigate's decks, a trooper and an ironclad on the carriage.
            let ranks: [MobKind] = kind == "frigate" ? [.soldierMarksman, .soldierTrooper, .soldierTrooper, .soldierMarksman]
                                                     : [.soldierTrooper, .soldierIronclad]
            for (i, st) in s.crewStations.enumerated() {
                let m = Mob(ranks[i % ranks.count], at: s.toWorld(st + V3(0, 0.1, 0)))
                if m.kind == .soldierTrooper { m.variant = Guns.rifle }      // stations fight at range: no shotguns
                if m.kind == .soldierIronclad { m.variant = Guns.arc }       // no rockets bursting on their own rails
                m.persistent = true
                g.mobs.mobs.append(m)
            }
        }
        return s
    }

    // Whether a vessel's guns engage the player: a survival player in range who is not aboard (boarders are the
    // crew's business; the guns won't shell their own deck).
    func gunsEngage(_ s: Ship, _ g: Game) -> Bool {
        let pp = g.player.pos + V3(0, 1, 0)
        guard g.alive && g.survival && g.difficulty > 0 && simd_length(pp - s.pos) < (s.role == "frigate" ? 64 : 80) else { return false }
        if aboard?.root === s || standing(on: g.player.pos)?.root === s { return false }
        return true
    }

    // The nearest player the vessel's guns engage (split screen: either one; they only ever shot at player 1).
    func gunsTarget(_ s: Ship, _ g: Game) -> V3? {
        var best: V3?
        var bd = Float.greatestFiniteMagnitude
        for i in 0..<max(1, g.coop.seatCount) {
            g.coop.withSeat(i, g) {
                guard self.gunsEngage(s, g) else { return }
                let pp: V3 = g.player.pos + V3(0, 1, 0)
                let d = simd_length(pp - s.pos)
                if d < bd { bd = d; best = pp }
            }
        }
        return best
    }

    // Vessel crews: patrol around home, turrets track a nearby player and fire.
    func crewTick(_ dt: Float, game g: Game) {
        for s in list where s.isVessel && !s.kinematic && s !== pilot && s.parent == nil {
            // A vessel the player has taken (steered) keeps no crew orders.
            if s.captured { s.autopilot = nil; continue }
            // Lose the helm or most of the hull and the vessel founders: the crew gives up, guns fall silent.
            if !s.wrecked && (s.helm == nil || s.blockCount * 100 < s.initialBlocks * 45) {
                s.wrecked = true
                if simd_length(s.pos - g.player.pos) < 160 {
                    g.onToast?("The \(s.name) is going down!")
                    if g.survival { g.achieve("wreck_vessel") }
                }
                g.sfx(.explode, 1, at: s.pos)
            }
            if s.wrecked {
                s.autopilot = nil
                for t in turrets(of: s) { t.aimAt = nil }
                continue
            }
            let home = s.home ?? s.pos
            let toHome = V2(home.x - s.pos.x, home.z - s.pos.z)
            let f = s.dirToWorld(s.fwd)
            let fh = simd_normalize(V2(f.x, f.z) + V2(1e-5, 0))
            // Circle the home point (steer toward a point ahead on the circle).
            let r: Float = s.role == "frigate" ? 70 : 30
            let dist = simd_length(toHome)
            let tangent = V2(-toHome.y, toHome.x) / max(1, dist)
            let pull: Float = (dist - r) / (r * max(1, dist))
            let want: V2 = simd_normalize(tangent + toHome * pull)
            var cross = fh.x * want.y - fh.y * want.x
            // Look ahead: the frigate climbs over high ground, the carriage turns home before water.
            let ahead = s.pos + V3(fh.x, 0, fh.y) * 30
            let ax = Int(floor(ahead.x)), az = Int(floor(ahead.z))
            if world.isLoaded(ax, az) {
                let top = world.topY(ax, az)
                if s.role == "frigate", let base = s.home?.y {
                    s.hoverY = max(base + 6, Float(top) + 25)        // never below its spawn altitude (home + 6)
                } else if s.role == "carriage" && Blocks.isLiquid(world.rawBlock(ax, top, az)) {
                    let back = simd_normalize(toHome + V2(1e-3, 0))
                    cross = fh.x * back.y - fh.y * back.x + (cross >= 0 ? 0.5 : -0.5)
                }
            }
            let steer = max(-1, min(1, cross * 2))
            s.autopilot = V3(s.role == "frigate" ? 0.7 : 0.5, steer, 0)
            // Guns: the player, or else an enemy faction's vessel or crawler in range (CapitalShips.swift).
            var pp = g.player.pos + V3(0, 1, 0)
            var seen = false
            if let t = gunsTarget(s, g) { pp = t; seen = true }
            if !seen, let foe = nearestFoe(of: s.factionValue, near: s.pos, range: s.role == "frigate" ? 90 : 110, game: g), foe.ship != nil {
                pp = foe.point
                seen = true
            }
            for t in turrets(of: s) {
                t.aimAt = seen ? pp : nil
                if !seen { t.aimYaw = 0; t.gunPitch *= max(0, 1 - dt) }
            }
            s.fireTimer -= dt
            if seen {
                let volley = s.fireTimer <= 0
                if volley { s.fireTimer = s.role == "frigate" ? 3.5 : 6 }
                for t in turrets(of: s) {
                    let muzzle = t.toWorld(t.pivot)
                    let d = pp - muzzle
                    let horiz = simd_length(V2(d.x, d.z))
                    if horiz < 10 { continue }                  // too close: the shell would burst on the gunners
                    // Elevation to land a 45 b/s shell at the player under gravity 20 (low arc), ignoring drag.
                    let v: Float = 45, gr: Float = 20
                    let disc = v * v * v * v - gr * (gr * horiz * horiz + 2 * d.y * v * v)
                    let elev = disc > 0 ? atanf((v * v - sqrtf(disc)) / (gr * horiz)) : 0.6
                    t.gunPitch += (max(-0.2, min(0.6, elev)) - t.gunPitch) * min(1, dt * 3)     // barrels follow the aim
                    // Only when the turret points at the target.
                    let tf = t.dirToWorld(V3(0, 0, -1))
                    let aimErr = acosf(max(-1, min(1, simd_dot(simd_normalize(V2(tf.x, tf.z) + V2(1e-5, 0)), simd_normalize(V2(d.x, d.z) + V2(1e-5, 0))))))
                    if volley && aimErr < 0.15 { fire(t, pitch: elev, game: g) }
                }
            }
        }
    }
}
