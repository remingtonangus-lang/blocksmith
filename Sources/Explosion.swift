import Foundation
import simd

// Explosions like the reference game: 16x16x16 rays from the centre lose strength by each block's
// blast resistance; blocks the rays get through are destroyed (dropping with chance 1/power);
// entities take damage scaled by distance and exposure and are knocked back.
enum Explosion {
    // `decay`: blocks drop with chance 1/power (creepers, fireballs, beds...); primed blocks of TNT drop everything
    // (reference: the TNT drop-decay rule is off by default).
    static func explode(at c: V3, power: Float, game g: Game, fire: Bool = false, except: Mob? = nil, breakBlocks: Bool = true,
                        decay: Bool = true, resistCap: Float = .infinity) {
        let w = g.world
        // No friendly fire: the Capital's own shells (bases.quiet) leave its citadels' blocks and its troops alone.
        let own = g.bases.quiet
        let breakBlocks = breakBlocks && !(own && g.bases.inAnyBase(c))
        g.baseNoise(at: c, kind: .explosion, power: power)  // citadels hear it (CapitalBases.swift)
        w.ships.blast(at: c, power: power, game: g)          // ship blocks (ShipCombat.swift)
        var destroyed = Set<IVec3>()
        var shaken: [IVec3: Float] = [:]                    // blocks that stopped a ray: share of their cost it carried
        // (The rays only find blocks to break or chip: a blast that breaks none skips them, 17 ms at power 8.)
        if breakBlocks { for i in 0..<16 { for j in 0..<16 { for k in 0..<16 {
            if !(i == 0 || i == 15 || j == 0 || j == 15 || k == 0 || k == 15) { continue }
            var d = V3(Float(i) / 15 * 2 - 1, Float(j) / 15 * 2 - 1, Float(k) / 15 * 2 - 1)
            d = simd_normalize(d)
            var intensity = power * (0.7 + Rand.float(in: 0..<0.6))
            var p = c
            while intensity > 0 {
                let b = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
                let id = w.block(b.x, b.y, b.z)
                if id != AIR {
                    let fluid = Blocks.isLiquid(id)
                    let r0 = Blocks.resistance[Int(id)]
                    let res = fluid ? 100 : (r0 < 1000 ? min(resistCap, r0) : r0)      // (bedrock and the like stay)
                    let cost: Float = (res + 0.3) * 0.3
                    if intensity <= cost && !fluid && breakBlocks && intensity > 0 {
                        shaken[b] = max(shaken[b] ?? 0, intensity / cost)
                    }
                    intensity -= cost
                    if intensity > 0 && !fluid && b.y >= 0 && b.y < CH && breakBlocks { destroyed.insert(b) }
                }
                p += d * 0.3
                intensity -= 0.225
            }
        } } } }
        var tnt: [IVec3] = []
        let tntID = Blocks.id("tnt")
        for b in destroyed {
            let id = w.block(b.x, b.y, b.z)
            if id == tntID { tnt.append(b); w.setBlockAsync(b.x, b.y, b.z, AIR); continue }
            if !decay || Rand.float(in: 0..<1) < 1 / power {
                for s in Mining.drops(id, ItemStack(Items.id("netherite_pickaxe"), 1)) {
                    g.drops.spawn(s, at: V3(Float(b.x) + 0.5, Float(b.y) + 0.5, Float(b.z) + 0.5))
                }
            }
            if let be = w.blockEntities.removeValue(forKey: b) {
                for s in be.container.slots where !s.isEmpty { g.drops.spawn(s, at: V3(Float(b.x) + 0.5, Float(b.y) + 0.5, Float(b.z) + 0.5)) }
                be.container.slots = Array(repeating: .empty, count: be.container.slots.count)   // an open screen shares it
            }
            w.setBlockAsync(b.x, b.y, b.z, AIR)
        }
        for b in destroyed { w.scheduleFluid(around: b) }
        // Progressive block damage: blocks the blast couldn't break lose pieces on the side facing it.
        if Settings.shared.chipping {
            var bits = 0
            for (b, share) in shaken where !destroyed.contains(b) && share > 0.15 {
                let id = w.block(b.x, b.y, b.z)
                guard Blocks.render[Int(id)] == RenderType.cube.rawValue, Blocks.hardness[Int(id)] >= 0 else { continue }
                let d = c - (V3(Float(b.x), Float(b.y), Float(b.z)) + 0.5)
                let ad = simd_abs(d)
                let face = ad.x >= ad.y && ad.x >= ad.z ? (d.x > 0 ? 0 : 1) : (ad.y >= ad.z ? (d.y > 0 ? 2 : 3) : (d.z > 0 ? 4 : 5))
                w.chipAsync(b, level: max(1, min(6, Int(share * 7))), face: face)
                bits += 1
                if bits <= 30 {
                    let nrm = [V3(1, 0, 0), V3(-1, 0, 0), V3(0, 1, 0), V3(0, -1, 0), V3(0, 0, 1), V3(0, 0, -1)][face]
                    g.particles.chipBits(id, at: V3(Float(b.x), Float(b.y), Float(b.z)) + 0.5 + nrm * 0.5, normal: nrm, face: face, count: 2)
                }
            }
        }
        for b in tnt { g.tnts.prime(at: b, fuse: Rand.float(in: 0.5...1.5)) }

        // Entities.
        let radius = power * 2
        func impact(_ p: V3, _ height: Float) -> (Float, V3)? {
            let center = p + V3(0, height * 0.5, 0)
            let d = simd_length(center - c)
            if d > radius { return nil }
            let exposure: Float = w.canSee(c, center) ? 1 : (w.canSee(c, p + V3(0, height, 0)) ? 0.5 : 0)
            let k = (1 - d / radius) * exposure
            let dir = d > 0.01 ? (center - c) / d : V3(0, 1, 0)
            return (k, dir)
        }
        // Every split-screen player in reach (typed closure and split arithmetic: the inferred form timed out the
        // type checker on CI).
        let hitPlayer: () -> Void = {
            guard let im = impact(g.player.pos, 1.8), im.0 > 0 else { return }
            let k: Float = im.0
            let dir: V3 = im.1
            let base: Float = (k * k + k) / 2
            let raw: Float = base * 7 * radius + 1
            g.hurtPlayer(Int(raw.rounded()), from: c, cause: "blew up", knockback: 0, type: .explosion)
            let push: V3 = dir * (k * 12)
            g.player.vel += push
        }
        g.coop.eachSeat(g, hitPlayer)
        for m in g.mobs.mobs where m !== except && !(own && m.kind.steelhold && m.factionValue == .steelhold) && !(g.ashQuiet && m.factionValue == .ashguard)
            && !(g.blastSpares != .none && m.factionValue == g.blastSpares) {
            if let im = impact(m.pos, m.height), im.0 > 0 {
                let (k, dir) = im
                m.hit(from: c, damage: Int(((k * k + k) / 2 * 7 * radius + 1).rounded()), knockback: 0)
                m.vel += dir * k * 12
            }
        }
        let star: ItemID = Items.has("nether_star") ? Items.id("nether_star") : ItemID.max
        for it in g.drops.items {
            if let im = impact(it.pos, 0.25), im.0 > 0 {
                let (k, dir) = im
                // The Blight Star survives blasts (the Blight's own skulls keep landing around its drop).
                if it.stack.item != star && Rand.float(in: 0..<1) < k * 0.5 { it.stack = .empty } else { it.vel += dir * k * 10 }
            }
        }
        // Grenade-sized blasts crack, TNT-sized ones boom, big ones (charged hissers, shells, beds) shake the ground.
        g.sfx(power < 2.5 ? .explodeSmall : (power >= 5 ? .explodeLarge : .explode), 1, at: c)
        if power >= 3 && breakBlocks { g.sfx(.debrisRain, 0.7, at: c + V3(0, 1, 0)) }
        g.particles.explosion(at: c, power: power)
        g.addFlash(at: c + V3(0, 0.5, 0), color: V3(6, 3.6, 1.6) * min(2, power / 3), radius: 6 + power * 2.5, life: 0.45)
    }
}

extension Explosion {
    // A Tidebreaker slug's impact (task 23; MainGun.swift): a bowl-shaped crater of radius r (ragged rim) through every
    // breakable block, citadel walls included; ship hulls in reach torn (ShipManager.blast); a few drops; a power-8
    // blast for damage, sound and flash without its own block breaking. At most `cap` blocks go: cells are taken
    // nearest first, so a capped crater is still a round bowl, only shallower. All at once here (harness); the game
    // carves it over a few frames with CraterJob (blocksPerFrame). Returns the number of blocks removed.
    @discardableResult
    static func crater(at c: V3, radius r: Float, cap: Int = .max, game g: Game) -> Int {
        let job = CraterJob(at: c, radius: r, cap: cap, game: g)
        while !job.step(g, blocks: .max) {}
        return job.removed
    }

    // Offsets of the cube of radius ri, nearest first by the bowl's metric (built once per radius).
    private static var craterOffsetCache: [Int: [SIMD3<Int16>]] = [:]
    private static let craterOffsetLock = NSLock()      // (a charging Tidebreaker builds them on a worker: MainGun)
    static func craterOffsets(_ ri: Int) -> [SIMD3<Int16>] {
        craterOffsetLock.lock()
        defer { craterOffsetLock.unlock() }
        if let o = craterOffsetCache[ri] { return o }
        var o: [(Float, SIMD3<Int16>)] = []
        o.reserveCapacity((2 * ri + 1) * (2 * ri + 1) * (2 * ri + 1))
        for dy in -ri...ri { for dz in -ri...ri { for dx in -ri...ri {
            let dyf = Float(dy) * (dy < 0 ? 1.5 : 1)
            o.append((Float(dx * dx + dz * dz) + dyf * dyf, SIMD3<Int16>(Int16(dx), Int16(dy), Int16(dz))))
        } } }
        o.sort { $0.0 < $1.0 }
        let out = o.map { $0.1 }
        craterOffsetCache[ri] = out
        return out
    }
}

// A crater carved outward from its centre a slice at a time (the remesh, support and fluid work it causes stays
// within a frame's budget: 2 454 blocks at once cost 19 ms of one host frame, about 50 ms on the headset). The blast,
// the ship damage and the flash happen at once; the bowl opens over the next few frames behind the flash and dust.
final class CraterJob {
    let center: V3
    let r: Float
    let cap: Int
    private let offsets: [SIMD3<Int16>]
    private var next = 0
    private(set) var removed = 0
    private var rim: [IVec3] = []
    private(set) var done = false
    static let blocksPerFrame = 250
    static var initCost = ""                 // (MainGunTests)
    private var circuitsNear: Bool?
    private var scanY = Int.min
    static let scanLayers = 6                // circuit scan: y layers per frame (47 x 47 cells each)

    // `quiet`: only the carving (a crater dug when its ground loads, long after the blast: MainGun pending craters).
    init(at c: V3, radius r: Float, cap: Int, game g: Game, quiet: Bool = false) {
        center = c; self.r = r; self.cap = cap
        offsets = Explosion.craterOffsets(Int(ceilf(r)))
        if quiet { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        g.world.ships.blast(at: c, power: 14, game: g)
        let t1 = CFAbsoluteTimeGetCurrent()
        Explosion.explode(at: c, power: 8, game: g, breakBlocks: false)
        let t2 = CFAbsoluteTimeGetCurrent()
        CraterJob.initCost = String(format: "ship blast %.1f, explosion %.1f", (t1 - t0) * 1000, (t2 - t1) * 1000)
        g.particles.explosion(at: c + V3(0, 2, 0), power: 8)
        g.sfx(.debrisRain, 1, at: c + V3(0, 2, 0))
        g.addFlash(at: c + V3(0, 1, 0), color: V3(5, 5.5, 7), radius: 40, life: 0.6)
    }

    // Removes up to `blocks` more; true when the crater is finished.
    @discardableResult
    func step(_ g: Game, blocks: Int) -> Bool {
        if done { return true }
        let w = g.world
        let cx = Int(floor(center.x)), cy = Int(floor(center.y)), cz = Int(floor(center.z))
        if circuitsNear == nil {
            // Any circuit part within reach of the bowl or its scorch (a changed block marks neighbours up to 2 away)?
            // None: carve without the per-block circuit marks. 100k cells, straight through each chunk's array and
            // spread over the first few frames (one pass was a 30-40 ms frame); the carving waits for it (under the
            // fireball, unseen).
            let R = Int(ceilf(r * 1.5)) + 3                   // (the scorch reaches 1.5 radii)
            let y0 = max(0, cy - R), y1 = min(CH - 1, cy + R)
            if scanY < y0 { scanY = y0 }
            if scanY > y1 { circuitsNear = false; return step(g, blocks: blocks) }   // (a blast above or below the world)
            let yEnd = min(y1, scanY + CraterJob.scanLayers - 1)
            var found = false
            scan: for qz in floorDiv(cz - R, CS)...floorDiv(cz + R, CS) { for qx in floorDiv(cx - R, CS)...floorDiv(cx + R, CS) {
                guard let c = w.chunkAt(qx * CS, qz * CS) else { continue }
                let lx0 = max(0, cx - R - qx * CS), lx1 = min(CS - 1, cx + R - qx * CS)
                let lz0 = max(0, cz - R - qz * CS), lz1 = min(CS - 1, cz + R - qz * CS)
                for y in scanY...yEnd { for lz in lz0...lz1 { for lx in lx0...lx1 where Circuit.kinds[Int(c.blocks[Chunk.index(lx, y, lz)])] != .none {
                    found = true; break scan
                } } }
            } }
            scanY = yEnd + 1
            if found { circuitsNear = true } else if scanY > y1 { circuitsNear = false } else if blocks != .max { return false }
            if circuitsNear == nil { return step(g, blocks: blocks) }   // (all at once: the harness's Explosion.crater)
        }
        let quiet0 = w.circuitQuiet
        w.circuitQuiet = circuitsNear == false
        defer { w.circuitQuiet = quiet0 }
        var budget = blocks
        while next < offsets.count && budget > 0 && removed < cap {
            let o = offsets[next]
            next += 1
            let dx = Int(o.x), dy = Int(o.y), dz = Int(o.z)
            let y = cy + dy
            guard y > 0 && y < CH - 1 else { continue }
            let dyf = Float(dy) * (dy < 0 ? 1.5 : 1)         // a bowl: shallower than wide
            let d2: Float = Float(dx * dx + dz * dz) + dyf * dyf
            if d2 > r * r { next = offsets.count; break }     // nearest first: nothing further can be inside
            let edge: Float = r * (0.8 + 0.2 * hashf(cx + dx, y, cz + dz, 911))
            guard d2 <= edge * edge else { continue }
            let x = cx + dx, z = cz + dz
            let id = w.block(x, y, z)
            if id == AIR || Blocks.isLiquid(id) || Blocks.hardness[Int(id)] < 0 { continue }
            let b = IVec3(x, y, z)
            if let be = w.blockEntities.removeValue(forKey: b) {
                for s in be.container.slots where !s.isEmpty { g.drops.spawn(s, at: V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)) }
                be.container.slots = Array(repeating: .empty, count: be.container.slots.count)
            }
            if Rand.float(in: 0..<1) < 0.02 {
                for s in Mining.drops(id, ItemStack(Items.id("netherite_pickaxe"), 1)) { g.drops.spawn(s, at: V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)) }
            }
            w.setBlockAsync(x, y, z, AIR)
            removed += 1
            budget -= 1
            if d2 > (edge - 1.5) * (edge - 1.5) { rim.append(b) }
        }
        if (next >= offsets.count || removed >= cap) && !carved {
            carved = true
            for b in rim { w.scheduleFluid(around: b) }
            rim.removeAll()
        }
        if carved && budget > 0 { scorch(g, columns: max(1, budget / 3)) }      // (up to ~3 block changes a column)
        return done
    }

    // After the carving: the bowl's floor burnt to blackstone and basalt with a few glowing magma blocks, a ring of
    // scorched earth round the rim fading out to 1.5 radii (grass and podzol to coarse dirt, plants and snow burnt
    // off, a few fires), so the crater reads as a blast and not a dig. Columns in a ring order, nearest first.
    private var carved = false
    private var scorchNext = 0
    private(set) var scorched = 0
    // Ground the scorch may burn: terrain, never anything built.
    static let natural: Set<BlockID> = Set(["grass_block", "dirt", "podzol", "mycelium", "coarse_dirt", "rooted_dirt", "mud", "clay",
                                            "stone", "granite", "diorite", "andesite", "tuff", "deepslate", "sand", "red_sand", "gravel",
                                            "sandstone", "red_sandstone", "snow_block", "terracotta", "calcite", "blackstone", "basalt"]
                                            .filter { Blocks.has($0) }.map { Blocks.id($0) })
    private static var scorchCache: [Int: [SIMD2<Int16>]] = [:]     // columns within 1.5 radii, nearest first
    private func scorch(_ g: Game, columns: Int) {
        let w = g.world
        let R = r * 1.5
        let ri = Int(ceilf(R))
        let cols: [SIMD2<Int16>]
        if let c = CraterJob.scorchCache[ri] { cols = c } else {
            var all: [(Float, SIMD2<Int16>)] = []
            for dz in -ri...ri { for dx in -ri...ri { all.append((Float(dx * dx + dz * dz), SIMD2(Int16(dx), Int16(dz)))) } }
            cols = all.sorted { $0.0 < $1.0 }.map { $0.1 }
            CraterJob.scorchCache[ri] = cols
        }
        let cx = Int(floor(center.x)), cy = Int(floor(center.y)), cz = Int(floor(center.z))
        let blackstone = Blocks.id("blackstone"), basalt = Blocks.id("basalt"), magma = Blocks.id("magma_block")
        let coarse = Blocks.id("coarse_dirt"), fire = Blocks.id("fire"), snowLayer = Blocks.has("snow") ? Blocks.id("snow") : AIR
        let grass = Blocks.id("grass_block"), podzol = Blocks.id("podzol"), dirt = Blocks.id("dirt")
        var n = columns
        while n > 0 && scorchNext < cols.count {
            let o = cols[scorchNext]
            scorchNext += 1
            n -= 1
            let dx = Int(o.x), dz = Int(o.y)
            let h = Float(dx * dx + dz * dz).squareRoot()
            if h > R { continue }
            let x = cx + dx, z = cz + dz
            guard w.chunkAt(x, z) != nil else { continue }
            // The exposed surface: the first solid block down from above the rim (plants and snow on it burnt off).
            var y = min(CH - 2, cy + Int(r) + 2)
            let floorY = max(1, cy - Int(r))
            var top: BlockID = AIR
            while y > floorY {
                let id = w.block(x, y, z)
                if id != AIR {
                    if Blocks.isLiquid(id) { top = AIR; break }
                    if !Blocks.collide[Int(id)] {
                        // Plants and snow cover burn off; torches, wire, rails and the like are left (no drops here).
                        if Blocks.isPlant(id) || Blocks.groupBase[Int(id)] == snowLayer { w.setBlockAsync(x, y, z, AIR); scorched += 1 }
                        y -= 1; continue
                    }
                    if !Blocks.opaque[Int(id)] { top = AIR; break }          // leaves, glass, fences: left standing
                    top = id
                    break
                }
                y -= 1
            }
            // Natural ground only: a trunk, wall or roof met first (trees and houses round the rim) is left alone.
            guard top != AIR, CraterJob.natural.contains(Blocks.groupBase[Int(top)]), w.blockEntities[IVec3(x, y, z)] == nil else { continue }
            let roll = hashf(x, y, z, 913)
            let fade = 1 - max(0, h - r * 0.85) / (R - r * 0.85)       // 1 in the bowl, falling to 0 at 1.5 radii
            var to: BlockID = AIR
            if h < r * 0.85 {
                to = roll < 0.06 ? magma : roll < 0.5 ? blackstone : roll < 0.68 ? basalt : AIR
            } else if roll < 0.95 * fade, top == grass || top == podzol || top == dirt {
                to = coarse
            } else if roll < 0.35 * fade {
                to = blackstone
            }
            if to != AIR && to != top { w.setBlockAsync(x, y, z, to); scorched += 1 }
            if h > r * 0.7 && hashf(x, y, z, 917) < 0.05 * fade && w.block(x, y + 1, z) == AIR && to != magma {
                w.setBlockAsync(x, y + 1, z, fire)
            }
        }
        if scorchNext >= cols.count { done = true }
    }
}

// Primed TNT: falls, flashes, explodes (power 4) after its fuse.
final class PrimedTNT {
    var pos: V3
    var vel = V3(0, 3, 0)
    var fuse: Float
    var hissed = false
    init(_ p: V3, fuse: Float) { pos = p; self.fuse = fuse }
}

final class TNTManager {
    var list: [PrimedTNT] = []

    func prime(at b: IVec3, fuse: Float = 4) {
        let t = PrimedTNT(V3(Float(b.x) + 0.5, Float(b.y), Float(b.z) + 0.5), fuse: fuse)
        t.vel = V3(Rand.float(in: -0.4...0.4), 4, Rand.float(in: -0.4...0.4))
        list.append(t)
    }

    func update(_ dt: Float, game g: Game) {
        var boom: [V3] = []
        for t in list {
            if !t.hissed { t.hissed = true; g.sfx(.tntFuse, 1, at: t.pos + V3(0, 0.5, 0)) }
            t.fuse -= dt
            t.vel.y -= 16 * dt
            t.vel.x *= expf(-2 * dt); t.vel.z *= expf(-2 * dt)
            let hit = g.world.moveBody(&t.pos, halfW: 0.49, height: 0.98, t.vel * dt, step: 0, onGround: false)
            if hit.y { t.vel.y = 0 }
            if hit.x { t.vel.x = 0 }
            if hit.z { t.vel.z = 0 }
            if t.fuse <= 0 { boom.append(t.pos + V3(0, 0.49, 0)) }
        }
        list.removeAll { $0.fuse <= 0 }
        for p in boom { Explosion.explode(at: p, power: 4, game: g, decay: false) }
    }

    func write(_ wr: inout EntityWriter, eye: V3, world: World, daylight: Float) {
        let tnt = Blocks.id("tnt")
        for t in list {
            let flash = Int(t.fuse * 5) % 2 == 0
            let s: Float = t.fuse < 0.5 ? 1 + (0.5 - t.fuse) * 0.3 : 1
            let l = world.lightAt(Int(floor(t.pos.x)), Int(floor(t.pos.y + 0.5)), Int(floor(t.pos.z)))
            let light = flash ? 1.6 : max(0.1, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            wr.cube(center: t.pos + V3(0, 0.5, 0) - eye, half: 0.5 * s, yaw: 0, block: tnt, light: light)
        }
    }
}
