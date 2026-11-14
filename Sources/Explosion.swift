import Foundation
import simd

// Explosions like the reference game: 16x16x16 rays from the centre lose strength by each block's
// blast resistance; blocks the rays get through are destroyed (dropping with chance 1/power);
// entities take damage scaled by distance and exposure and are knocked back.
enum Explosion {
    // A breaching shell's view of a block's blast resistance (P70 `resistCap`). Stone-class blocks count at most the
    // cap. R10 (Oct 13: "naval guns do nothing to crawlers and the Capital tower"): armour plate (resistance 600: steel
    // plating, the crawlers' hulls and the Capital tower's cladding) stayed whole against every shell; it now counts
    // three times the cap, so a manned gun's burst bites a few plates where stone opens a hole. Obsidian, vaults
    // (over 600) and unbreakable blocks stay.
    // P476: obsidian-grade armour (Armour.grade) shrugs off every other blast but a heavy gun's shell and the main gun
    // count it as Armour.breach: a few plates bitten off where steel would open a hole.
    static func capped(_ id: BlockID, _ r0: Float, _ cap: Float) -> Float {
        // P504 (Nov 1 07:52:13-07:52:21, flying a dropship's guns at his frigate: "guns break through armor as if it's
        // not armor at all... The only reason the armor matters is when someone tries to break through with a pickaxe"):
        // armour plate (a frigate's skins, a base's plate) stands to a blast as plain steel does; it mines like obsidian.
        // (P507: and no breach makes it less: his rockets' and steered guns' cap leaves armour at steel's.)
        if Armour.isGrade(id) { return Armour.blast }
        guard cap.isFinite else { return r0 }
        if r0 <= 12 { return min(cap, r0) }
        if r0 <= 600 && Blocks.hardness[Int(id)] >= 0 { return min(r0, cap * 3) }
        return r0
    }

    // P452 (Remington, Oct 25 13:34: "if an explosion happens, any of the stuff it destroys is destroyed. There's no
    // block left to pick up. Unless it's a very valuable block. Like a weapon upgrades block thing."): the fight at the
    // surface left the ground strewn with blasted blocks to pick up and it lagged. What a blast (or a crater, a shell
    // through a ship, a vehicle smashing through, a collapse crushing what it lands on) breaks is gone; only a very
    // valuable block drops: one made with something precious (the Upgrade Bench's diamonds and obsidian, a beacon's
    // star, the precious storage blocks, an anvil's iron blocks) or a gun or vehicle workshop. What a chest or furnace
    // held still drops (his things, not the block).
    static let precious = ["diamond", "emerald", "gold_ingot", "netherite_ingot", "netherite_scrap", "nether_star", "obsidian",
                           "iron_block", "ender_eye", "ender_pearl", "shulker_shell", "heart_of_the_sea", "echo_shard", "totem"]
    static let valuable: [Bool] = {
        var v = [Bool](repeating: false, count: Blocks.count)
        func mark(_ b: BlockID) {
            let base = Int(Blocks.groupBase[Int(b)])
            var i = base
            while i < Blocks.count && Int(Blocks.groupBase[i]) == base { v[i] = true; i += 1 }
        }
        for r in Recipes.all {
            guard let b = Items.defs[Int(r.result.item)].block else { continue }
            let parts = r.shapeless.isEmpty ? r.cells.compactMap { $0 } : r.shapeless
            if parts.contains(where: { p in precious.contains { p.contains($0) } }) { mark(b) }
        }
        for k in [WeaponPrinter.key, GunsmithBench.key, VehicleWorks.key, "beacon", "conduit", "enchanting_table"] where Blocks.has(k) { mark(Blocks.id(k)) }
        return v
    }()
    // A blasted block's drops: only a valuable one's, and then always.
    static func blastDrops(_ b: BlockID) -> [ItemStack] {
        guard valuable[Int(b)] else { return [] }
        return Mining.drops(b, ItemStack(Items.id("netherite_pickaxe"), 1))
    }

    // `decay` (blocks dropping with chance 1/power, TNT dropping everything) is gone with P452: a blast drops only
    // valuable blocks (blastDrops).
    // P471: the blast is a heavy naval shell's (Armory.detonate): Game.hurtPlayer lets it hit harder than the level's
    // cap on one blow.
    static var heavyShell = false
    static var onExplode: ((V3, Float) -> Void)?             // (host checks: where blasts go off)
    static let heavyPlayerReach: Float = 14         // P501: how far a heavy shell's burst reaches him (Explosion.explode)
    // P472: a crash's own blasts spare whoever rides the crashing ship (CapitalShips.hullContact, VehicleDamage).
    static var sparePlayer = false
    // (--turretfreeze: the slowest blast, stage by stage; nested blasts count in the outer one)
    static let batchShape = ProcessInfo.processInfo.environment["BS_BLASTSHAPE"] != "1"
    static var lapT = 0.0, lapT0 = 0.0, lapDepth = 0, laps = "", worstMs = 0.0, worstLaps = ""
    // (Nov 9: the thread's own CPU time too: a lap whose wall time is well over it was the host's scheduler taking the
    // core, as when a mesh job queued wakes a worker, not the game's work; such laps say "own" and their CPU time)
    static var lapC = 0.0
    @inline(__always) static func threadMs() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1e6
    }
    static func lapStart() { lapDepth += 1; if lapDepth == 1 { lapT = CFAbsoluteTimeGetCurrent(); lapT0 = lapT; lapC = threadMs(); laps = "" } }
    static func lap(_ s: String) {
        guard lapDepth == 1 else { return }
        let t = CFAbsoluteTimeGetCurrent(), c = threadMs()
        let ms = (t - lapT) * 1000, own = c - lapC
        laps += ms - own > 0.5 ? String(format: "%@ %.1f (own %.1f), ", s, ms, own) : String(format: "%@ %.1f, ", s, ms)
        lapT = t; lapC = c
    }
    static var totalMs = 0.0                        // (every outer blast's time, for Armory's slowest update)
    static func lapEnd(_ s: String) {
        lap(s); lapDepth -= 1
        guard lapDepth == 0 else { return }
        let ms = (lapT - lapT0) * 1000
        totalMs += ms
        if ms > worstMs { worstMs = ms; worstLaps = laps }
    }

    static func explode(at c: V3, power: Float, game g: Game, fire: Bool = false, except: Mob? = nil, breakBlocks: Bool = true,
                        decay: Bool = true, resistCap: Float = .infinity, along: V3? = nil) {
        let w = g.world
        Explosion.onExplode?(c, power)
        Explosion.lapStart()
        defer { Explosion.lapEnd("entities") }
        // P357 (e) (Oct 16 20:14: "a shell crater follows the angle of the shot"): a shell's blast carries on the way it
        // was flying: rays along the shot reach further, those back toward the gun less, so a plunging shot leaves a
        // slanted bowl and a flat one a gouge running on from where it struck.
        let shot: V3? = along.flatMap { simd_length($0) > 1e-3 ? simd_normalize($0) : nil }
        // No friendly fire on troops: the Capital's own shells (bases.quiet) leave its troops alone. (P510, Nov 1 20:16-20:22:
        // "no damage happens... to the building around my naval gun", "The capital guns don't do any damage to the capital
        // blocks, which isn't right. They should do damage": a shell breaks what it hits, its own side's walls too.)
        let own = g.bases.quiet
        let lying = g.drops.items.count                    // (what this blast spills itself is thrown, not burnt: P452)
        g.baseNoise(at: c, kind: .explosion, power: power)  // citadels hear it (CapitalBases.swift)
        Explosion.lap("heard")
        w.ships.blast(at: c, power: power, game: g, resistCap: resistCap)          // ship blocks (ShipCombat.swift)
        Explosion.lap("ships")
        var destroyed = Set<IVec3>()
        var shaken: [IVec3: Float] = [:]                    // blocks that stopped a ray: share of their cost it carried
        // (Nov 4, the worst-case soak's profile: the rays' block reads were a third of a blast, each one looking its
        // chunk up in the world's table; nearly every step is in the chunk the last one read. As World.block.)
        var rayKey = (Int.min, Int.min), rayChunk: Chunk? = nil
        @inline(__always) func rayBlock(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
            if w.frame != nil { return w.block(x, y, z) }
            if y < 0 { return BEDROCK }
            if y >= CH { return AIR }
            let kx = x >> 4, kz = z >> 4
            if kx != rayKey.0 || kz != rayKey.1 { rayKey = (kx, kz); rayChunk = w.chunkAt(x, z) }
            guard let c = rayChunk else { return AIR }
            if c.hollow { return y <= Int(c.height[(x & 15) + (z & 15) * CS]) ? STONE : AIR }
            return c.blocks[Chunk.index(x & 15, y, z & 15)]
        }
        // (The rays only find blocks to break or chip: a blast that breaks none skips them, 17 ms at power 8.)
        if breakBlocks { for i in 0..<16 { for j in 0..<16 { for k in 0..<16 {
            if !(i == 0 || i == 15 || j == 0 || j == 15 || k == 0 || k == 15) { continue }
            var d = V3(Float(i) / 15 * 2 - 1, Float(j) / 15 * 2 - 1, Float(k) / 15 * 2 - 1)
            d = simd_normalize(d)
            var intensity = power * (0.7 + Rand.float(in: 0..<0.6))
            if let shot { intensity *= 1 + 0.6 * simd_dot(d, shot) }
            var p = c
            while intensity > 0 {
                let b = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
                let id = rayBlock(b.x, b.y, b.z)
                if id != AIR {
                    let fluid = Blocks.isLiquid(id)
                    let r0 = Blocks.resistance[Int(id)]
                    let res = fluid ? 100 : Explosion.capped(id, r0, resistCap)
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
        Explosion.lap("rays")
        var tnt: [IVec3] = []
        let tntID = Blocks.id("tnt")
        // Realistic world: bodies lying round (ragdolls, MobRagdoll.swift) are thrown too.
        if g.mobs.corpses.contains(where: { $0.ragdoll != nil }) {      // (R15: every world)
            let rw = g.debris.ragdolls, reach = power * 2.5
            for d in g.mobs.corpses {
                guard let r = d.ragdoll, rw.isLive(r.id) else { continue }
                let at = rw.pose(r.id, 0).position, away = at - c, dl = simd_length(away)
                guard dl < reach else { continue }
                let dir = dl > 1e-3 ? away / dl : V3(0, 1, 0)
                rw.push(r.id, at: at, impulse: (dir * (power * 3) + V3(0, power, 0)) * (1 - dl / reach))
            }
        }
        // P465: bodies with no ragdoll (an Ash Vault fallen one, a body lying flat) are thrown as well.
        AshFallen.blast(g, at: c, power: power)
        if !g.mobs.corpses.isEmpty {
            let reach = power * 2.5
            for d in g.mobs.corpses where d.ragdoll == nil && !d.carcass && !HandGrab.holds(d) {
                let away = d.pos + V3(0, 0.3, 0) - c, dl = simd_length(away)
                guard dl < reach else { continue }
                let k = 1 - dl / reach
                let dir = dl > 1e-3 ? away / dl : V3(0, 1, 0)
                d.vel += V3(dir.x, 0, dir.z) * (power * 2.2 * k) + V3(0, 3 + power * 1.6 * k, 0)
                d.onGround = false
            }
        }
        // Realistic world: the blocks it breaks split on the spot and fly out as pieces (the nearest ones, within the
        // debris budget: 16 blocks of 4 pieces), and pieces already lying round fly again.
        if World.realistic && !destroyed.isEmpty {
            g.debris.blast(at: c, radius: power * 2.5, speed: power * 3)
            let near = destroyed.sorted { simd_length_squared(V3(Float($0.x), Float($0.y), Float($0.z)) + 0.5 - c)
                                          < simd_length_squared(V3(Float($1.x), Float($1.y), Float($1.z)) + 0.5 - c) }
            for b in near.prefix(16) {
                let id = w.block(b.x, b.y, b.z)
                guard id != tntID, Blocks.render[Int(id)] == RenderType.cube.rawValue, Blocks.collide[Int(id)] else { continue }
                let mid = V3(Float(b.x), Float(b.y), Float(b.z)) + 0.5
                let away = mid - c
                let dl = simd_length(away)
                let k = max(0.2, 1 - dl / (power * 2))
                g.debris.shatter(id, cell: b, impact: c, direction: dl > 1e-3 ? away / dl : V3(0, 1, 0), count: 4,
                                 speed: power * 2.2 * k + 1, seed: hash3(b.x, b.y, b.z, 0xB1A5), crowding: 0.3)
            }
        }
        Explosion.lap("bodies")
        // A blast's ground cells are opened without each one's own round hollow (a field sphere a cell, about a third
        // of a millisecond each on the host: a heavy shell's 450 cells were a 170 ms frame); the bowl carved below
        // shapes the hole as a whole, and only the cells past it get their own. BS_BLASTSHAPE=1: a hollow a cell.
        w.batchShape = Explosion.batchShape && w.fieldTerrain
        // Ledger 45: each removed block marked the circuit cells round it (Circuit.blockChanged, about 17k instructions a
        // block: 28% of the taiga24 battle's block clearing under callgrind, build 213), circuit or none. With no circuit
        // part within reach of the cells and the crater's shaping, the removal and the shaping go without the marks, as
        // a naval gun's crater already did (CraterJob).
        let quiet0 = w.circuitQuiet
        let calm = Explosion.circuitCalm && !destroyed.isEmpty && !w.circuitNear(destroyed, margin: 6)
        if calm { w.circuitQuiet = true }
        var opened: [IVec3] = []
        for b in destroyed {
            let id = w.block(b.x, b.y, b.z)
            if id == tntID { tnt.append(b); w.setBlockAsync(b.x, b.y, b.z, AIR); continue }
            for s in Explosion.blastDrops(id) {                                                  // (P452)
                g.drops.spawn(s, at: V3(Float(b.x) + 0.5, Float(b.y) + 0.5, Float(b.z) + 0.5))
            }
            if let be = w.blockEntities.removeValue(forKey: b) {
                for s in be.container.slots where !s.isEmpty { g.drops.spawn(s, at: V3(Float(b.x) + 0.5, Float(b.y) + 0.5, Float(b.z) + 0.5)) }
                be.container.slots = Array(repeating: .empty, count: be.container.slots.count)   // an open screen shares it
            }
            if w.batchShape && w.isGround(b) { opened.append(b) }
            w.setBlockAsync(b.x, b.y, b.z, AIR)
        }
        w.batchShape = false
        w.circuitQuiet = quiet0
        Explosion.lap("removal \(destroyed.count)" + (calm ? " (no circuit near)" : ""))
        for b in destroyed { w.scheduleFluid(around: b) }
        // P507 (Nov 1 12:20:36, "shooting one of the fuel pylons should cause the thing to explode"): a blast lights the fuel
        // in its reach (a holed storage tank, a pool, a drum's spill); the fire runs on through the rest (World.igniteFuel).
        if FUEL != AIR {
            let fr = Int(ceilf(power * 1.2)), ci = IVec3(Int(floorf(c.x)), Int(floorf(c.y)), Int(floorf(c.z)))
            var lit = 0
            for dy in -fr...fr { for dz in -fr...fr { for dx in -fr...fr where lit < 24 && dx * dx + dy * dy + dz * dz <= fr * fr {
                let q = IVec3(ci.x + dx, ci.y + dy, ci.z + dz)
                guard q.y > 0 && q.y < CH, Blocks.fluidKind[Int(w.builtBlock(q.x, q.y, q.z))] == 3 else { continue }
                w.igniteFuel(q); lit += 1
            } } }
        }
        Explosion.lap("fluids, fuel")
        // P503: what stood over the hole is weighed (StructureTip): a top shot out from under it tips and falls.
        if !destroyed.isEmpty {
            let far = destroyed.reduce(Float(1)) { max($0, simd_length(V3(Float($1.x), Float($1.y), Float($1.z)) + 0.5 - c)) }
            w.queueTipCheck(IVec3(Int(floor(c.x)), Int(floor(c.y)), Int(floor(c.z))), Int(ceil(far)))
        }
        // PG1: the crater is a bowl in the terrain field, not the blocks the rays took: its walls are bounded by a ball
        // the size of most of what broke (TerrainField.swift).
        if (w.keepsField || w.fieldTerrain) && !destroyed.isEmpty {
            let ds = destroyed.map { simd_length(V3(Float($0.x), Float($0.y), Float($0.z)) + 0.5 - c) }.sorted()
            let r = ds[min(ds.count - 1, ds.count * 3 / 4)] + 0.3
            var balls: [(V3, Float)] = [(c, r)]
            if let shot {                                       // (the bowl leans and runs on along the shot)
                balls = [(c + shot * (r * 0.3), r * 0.9), (c + shot * (r * 0.95), r * 0.6)]
            }
            // P507 (Nov 1 12:14:11-12:14:44, in his rocket crater: "I can't place blocks down in this crater... That's a bug",
            // "a lot of my clicks are just getting ignored"): the bowl only moved the surface, so the ground cells inside
            // it the rays happened to miss stayed whole blocks under a dot of drawn rock (the boulders in the bowl): the
            // aim went past them to the bowl's face and the block went into one of them, which refused it without a sound.
            // The ground inside the bowl goes with it (its valuable blocks drop, as the broken ones do).
            // Ledger 42: the bowl, the rim passes and the opened cells' shaping are a job (BlastShape); on the headset it
            // runs on the next frames within the carving allowance, here and in the checks at once.
            let job = BlastShape(world: w, balls: balls, opened: opened, quiet: calm)
            if BlastShape.deferred && CraterJob.inTick { BlastShape.queue.append(job) } else { while !job.step(g, until: .infinity) {} }
        } else {
            for b in opened { w.fieldShape(b.x, b.y, b.z, opened: true) }
        }
        Explosion.lap("rim, opened")
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
                if World.realistic {
                    // A bowl blown out of the side facing the blast (where the line to it leaves the block).
                    let mid = V3(Float(b.x), Float(b.y), Float(b.z)) + 0.5
                    let dl = simd_length(d)
                    let toC = dl > 1e-3 ? d / dl : V3(0, 1, 0)
                    let at = mid + toC * (0.5 / max(abs(toC.x), max(abs(toC.y), abs(toC.z))))
                    w.addBite(b, at: at, axis: toC, radius: 0.25 + 0.25 * min(1, share), depth: 0.1 + 0.3 * min(1, share),
                              seed: hash3(b.x, b.y, b.z, 0xC4A7), sync: false)
                }
                bits += 1
                if bits <= 30 {
                    let nrm = [V3(1, 0, 0), V3(-1, 0, 0), V3(0, 1, 0), V3(0, -1, 0), V3(0, 0, 1), V3(0, 0, -1)][face]
                    g.particles.chipBits(id, at: V3(Float(b.x), Float(b.y), Float(b.z)) + 0.5 + nrm * 0.5, normal: nrm, face: face, count: 2)
                }
            }
        }
        for b in tnt { g.tnts.prime(at: b, fuse: Rand.float(in: 0.5...1.5)) }
        Explosion.lap("chips")

        // Entities.
        let radius = power * 2
        // P465 (Oct 25 19:50, "That grenade should have hurt me"): a grenade at rest on the drawn ground lies inside the
        // cell the field counts as ground whenever the surface is in that cell's upper half, so every line from it
        // started blocked and nothing beside it was hurt. Its lines of sight start from the open cell above.
        var from = c
        for _ in 0..<2 where w.groundAt(Int(floorf(from.x)), Int(floorf(from.y)), Int(floorf(from.z))) { from.y = floorf(from.y) + 1.05 }
        // P459 (Oct 25 16:39-16:43, his dropship's autocannon on a village: "To the village it does nothing", "Should be
        // one-shotting villagers"): a shell bursts a little inside the wall, floor or path block it struck, and only
        // the drawn ground lifted the sight lines out (above), so a burst in a placed block saw nobody and hurt nobody
        // beside it. The lines start back along the shot, in the open air it came through (or above the block).
        if let shot { for _ in 0..<8 where w.opaqueAt(Int(floorf(from.x)), Int(floorf(from.y)), Int(floorf(from.z))) { from -= shot * 0.25 } }
        for _ in 0..<2 where w.opaqueAt(Int(floorf(from.x)), Int(floorf(from.y)), Int(floorf(from.z))) { from.y = floorf(from.y) + 1.05 }
        func impact(_ p: V3, _ height: Float, reach: Float? = nil) -> (Float, V3)? {
            let center = p + V3(0, height * 0.5, 0)
            let d = simd_length(center - c)
            let r = reach ?? radius
            if d > r { return nil }
            let exposure: Float = w.canSee(from, center) ? 1 : (w.canSee(from, p + V3(0, height, 0)) ? 0.5 : 0)
            let k = (1 - d / r) * exposure
            let dir = d > 0.01 ? (center - c) / d : V3(0, 1, 0)
            return (k, dir)
        }
        // Every split-screen player in reach (typed closure and split arithmetic: the inferred form timed out the
        // type checker on CI).
        // P501 (Oct 31 09:53, a Boreal station's 42 cm gun, his armour off: hits of 1 and 2, "That should have taken me
        // down about six hearts... That should have killed me... the naval gun needs to be way more devastating"): a heavy
        // shell's burst reached him within its own blast radius (10 blocks for a crew's shell, 4.8 for the light-armed
        // ones); now out to 14 blocks whatever its power, on the same curve (on Normal the level's 9-heart cap within
        // about 12).
        let heavyReach: Float = Explosion.heavyShell ? max(radius, Explosion.heavyPlayerReach) : radius
        let hitPlayer: () -> Void = {
            guard !Explosion.sparePlayer, let im = impact(g.player.pos, 1.8, reach: heavyReach), im.0 > 0 else { return }
            let k: Float = im.0
            let dir: V3 = im.1
            let base: Float = (k * k + k) / 2
            let naval: Float = Explosion.heavyShell ? 4 : 1           // P475: a naval gun's burst, four times as hard on him
            let raw: Float = base * 7 * max(radius, heavyReach * 0.72) * naval + 1
            g.hurtPlayer(Int(raw.rounded()), from: c, cause: "blew up", knockback: 0, type: .explosion)
            let push: V3 = dir * (k * 12)
            if g.survival { g.player.vel += push * g.knockbackScale }       // (PG7: a blast doesn't throw a creative player about either; Q2c-console-60)
        }
        g.coop.eachSeat(g, hitPlayer)
        // P499 (Oct 30 14:57, at a taken gun: "this guy has fired the flak cannon at me like 10 times... no damage to my
        // gun"): a gun the player mans is his, not its old side's: their bursts no longer spare it.
        let mannedGun = Turrets.shared.manned
        for m in g.mobs.mobs where m !== except && (m === mannedGun || !(own && m.kind.steelhold && m.factionValue == .steelhold) && !(g.ashQuiet && m.factionValue == .ashguard)
            && !(g.blastSpares != .none && m.factionValue == g.blastSpares)) {
            if let im = impact(m.pos, m.height), im.0 > 0 {
                let (k, dir) = im
                var dmg = ((k * k + k) / 2 * 7 * radius + 1).rounded()
                // A soldier's vest takes the blast first (TroopClasses.swift, T7): its plate soaks a share and wears.
                if m.troop > 0 && m.shield <= 0 && Soldier.rank(m.kind) != nil { dmg = m.troopArmourHit(dmg, seg: 1, g).rounded() }
                // P221 (Oct 13 21:29, "nobody walks out of a rocket or shell hit"): inside the inner half of the blast,
                // in the open, a body is killed outright, plate or not. Bosses and armour (tanks, golems, the Behemoth,
                // the wyrm...) still only take the damage.
                let lethal = power * 1.1
                if power >= 2, simd_length(m.pos + V3(0, m.height * 0.5, 0) - c) <= lethal, w.canSee(from, m.pos + V3(0, m.height * 0.5, 0)),
                   !Explosion.blastProof(m.kind) {
                    dmg = max(dmg, 9999)                                   // (past shields, plate and difficulty scaling)
                }
                m.hit(from: c, damage: Int(dmg), knockback: 0)
                m.vel += dir * k * 12
                // P423 (b) (Oct 23 21:30: "that should launch the guy"): a blast lifts a body off its feet as well, so it
                // flies instead of being pulled back to a walk on the ground at once (heavy things barely, per Mob.knockbackTaken).
                m.vel.y = max(m.vel.y, k * 10 * min(1, m.knockbackTaken))
            }
        }
        let star: ItemID = Items.has("nether_star") ? Items.id("nether_star") : ItemID.max
        for it in g.drops.items.prefix(lying) {
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
    // Who survives standing in a blast's heart (P221): bosses, armoured vehicles, golems and deck guns.
    static func blastProof(_ k: MobKind) -> Bool {
        k.ashVehicle || k == .ironGolem || k == .deckGun || k == .enderDragon || k == .wither || k == .warden || k == .elderGuardian
            || k == .ashMarshal || k == .ashChancellor
    }

    // A Tidebreaker slug's impact (task 23; MainGun.swift): a bowl-shaped crater of radius r (ragged rim) through every
    // breakable block, citadel walls included; ship hulls in reach torn (ShipManager.blast); a few drops; a power-8
    // blast for damage, sound and flash without its own block breaking. At most `cap` blocks go: cells are taken
    // nearest first, so a capped crater is still a round bowl, only shallower. All at once here (harness); the game
    // carves it over a few frames with CraterJob (blocksPerFrame). Returns the number of blocks removed.
    @discardableResult
    static func crater(at c: V3, radius r: Float, cap: Int = .max, game g: Game, depth: Int? = nil, along: V3? = nil) -> Int {
        let job = CraterJob(at: c, radius: r, cap: cap, game: g, depth: depth, along: along)
        while !job.step(g, blocks: .max) {}
        return job.removed
    }

    // Offsets of the cells of a bowl of radius ri reaching `depth` down, nearest first by the bowl's metric (built once
    // per shape). The default depth is the old bowl's, two thirds of its radius.
    private static var craterOffsetCache: [Int: [SIMD3<Int16>]] = [:]
    private static let craterOffsetLock = NSLock()      // (a charging Tidebreaker builds them on a worker: MainGun)
    static func craterOffsets(_ ri: Int, depth: Int? = nil) -> [SIMD3<Int16>] {
        let dn = depth ?? Int(ceilf(Float(ri) / 1.5))
        let key = ri * 1000 + dn
        craterOffsetLock.lock()
        defer { craterOffsetLock.unlock() }
        if let o = craterOffsetCache[key] { return o }
        let down = Float(ri) / Float(max(1, dn))
        var o: [(Float, SIMD3<Int16>)] = []
        o.reserveCapacity((2 * ri + 1) * (2 * ri + 1) * (ri + dn + 1))
        for dy in -dn...ri { for dz in -ri...ri { for dx in -ri...ri {
            let dyf = Float(dy) * (dy < 0 ? down : 1)
            o.append((Float(dx * dx + dz * dz) + dyf * dyf, SIMD3<Int16>(Int16(dx), Int16(dy), Int16(dz))))
        } } }
        o.sort { $0.0 < $1.0 }
        let out = o.map { $0.1 }
        craterOffsetCache[key] = out
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
    let depth: Int                           // how far down the bowl reaches (P99: the Tidebreaker's goes 22 deep)
    private var shear = V2(0, 0)             // P357 (e): blocks each layer down shifts along the shot
    // P499 (Oct 30 20:28, the Tidebreaker at a Capital citadel: "I literally shot through a building and made a crater
    // in the ground as if I was shooting vertically downwards"): a shot flatter than 25 degrees down drives its bowl
    // along the shot (the bowl's depth axis is the shot's heading), into the wall it struck, instead of a pit down
    // through the floors under the impact. Rows of the bowl-space basis (side, up, ahead); nil: a plunging shot.
    private var axes: (V3, V3, V3)?
    private let down: Float
    private let offsets: [SIMD3<Int16>]
    private var next = 0
    private(set) var removed = 0
    private var rim: [IVec3] = []
    private(set) var done = false
    static let blocksPerFrame = 250
    static var frameSeconds = 0.0016           // (about 2.7 ms of the headset's frame; see step)
    // Store review (citadel soak, build 94): each bowl and each naval breach opening took its own `frameSeconds` a
    // frame (the breaches in the arms stage, the bowls in the shockwaves: up to 9.8 ms of one tick), on top of 3-5 ms
    // of soldiers. Every crater job now draws on one allowance a frame: `frameSeconds`, less what the rest of the last
    // tick took past `tickTarget` (host seconds; about 9.4 ms of the headset's 13.9), never under `floorSeconds`. A
    // frame heavy with soldiers carves less; the bowl opens over a few more frames.
    // (Only inside the game's tick, Game.tickSeat: a check driving the shockwaves or breaches itself, frame after frame
    // with no tick, gets `frameSeconds` a call as before; the shared allowance never came back for it.)
    static var tickTarget = 0.0055, floorSeconds = 0.0004
    static var inTick = false
    private static var allowTick = -1, allow = 0.0, used = 0.0, usedPrev = 0.0
    static func allowance() -> Double {
        guard inTick else { return frameSeconds }
        if allowTick != TickProf.tick {
            allowTick = TickProf.tick
            usedPrev = used; used = 0
            let rest = max(0, TickProf.prevTotal - usedPrev)
            allow = max(floorSeconds, min(frameSeconds, tickTarget - rest))
        }
        // (and what this tick has left of `tickTarget` by now: carving run late in the tick, after the mobs, waits
        // when they ran long. Never under the floor a tick, so a bowl always goes on.)
        let own = min(allow - used, max(floorSeconds - used, tickTarget - TickProf.elapsed))
        // (ledger 126: and what the frame has left by its own clock, FrameGovernor: with frames to spare the carving
        // takes up to three times its slice, in a full frame its floor)
        guard FrameGovernor.armed else { return own }
        let room = FrameGovernor.left
        let k = max(0, min(1, (FrameGovernor.spare - 0.25) / 0.5))
        return max(floorSeconds - used, min(frameSeconds * (1 + 2 * k) - used, room))
    }
    // Other ground carving drawing on the same allowance (the crawler's ruts).
    static func spend(_ seconds: Double) { if inTick { _ = allowance(); used += seconds; FrameGovernor.charge(.carve, seconds) } }
    static var initCost = ""                 // (MainGunTests)
    static var worstStepMs = 0.0, worstStep = ""   // (the soak: the slowest timed step and where its time went)
    static var outside = 0                   // (P502: breaches burst outside the world, questcheck --turretfreeze)
    private var circuitsNear: Bool?
    private var waitFrames = 0
    private var fineFrames = 0
    private var leanFetch = true
    // (the soak's count of fine sections a bowl step made beyond its one prefetched section)
    static var finesUnfetched = 0, stepsUnfetched = 0, unfetchedPhases: [String: Int] = [:]
    static let oldFetch = ProcessInfo.processInfo.environment["BS_OLDBOWLFETCH"] == "1"
    private var scanY = Int.min
    static let scanLayers = 6                // circuit scan: y layers per frame (47 x 47 cells each)
    // (Nov 12, Remington on the trailer's main-gun strike: "the crater took too long to form"): the frames a bowl took to
    // open, by what each went on (MainGun.stepBowls tallies them; MainGunTests prints them).
    var stepPhase: String?
    private(set) var phaseFrames: [String: Int] = [:]
    private(set) var frames = 0
    private(set) var takenAt = -1            // the frame its last block went
    func tally(_ p: String) {
        let k = p.hasPrefix("field ball: fine") ? "ball prefetch" : p.hasPrefix("field ball") ? "field ball" : p.hasSuffix("scorch") ? "scorch"
            : p.hasPrefix("carving") ? "carving" : p
        phaseFrames[k, default: 0] += 1; frames += 1
        if carved && takenAt < 0 { takenAt = frames }
    }
    var openSummary: String {
        let order = ["starved", "wait", "fine prefetch", "circuit scan", "carving", "ball prefetch", "field ball", "scorch"]
        let parts = order.compactMap { k in phaseFrames[k].map { "\(k) \($0)" } }
        let carve = phaseFrames["carving"] ?? 0
        return String(format: "%ld frames (%.2f s at 72 Hz): ", frames, Double(frames) / 72) + parts.joined(separator: ", ")
            + String(format: "; %ld blocks, %.0f a carving frame, all taken by frame %ld", removed, carve > 0 ? Double(removed) / Double(carve) : 0, takenAt)
    }

    // `quiet`: only the carving (a crater dug when its ground loads, long after the blast: MainGun pending craters).
    init(at c: V3, radius r: Float, cap: Int, game g: Game, quiet: Bool = false, depth: Int? = nil, along: V3? = nil) {
        center = c; self.r = r; self.cap = cap
        // P357 (e): the bowl's depth leans along the shot (each layer down shifted on along its level heading, up to
        // 1.2 blocks a layer for a flat shot); a shot straight down digs straight down as before.
        if let a = along, simd_length(a) > 1e-3 {
            let n = simd_normalize(a)
            let hz = V2(n.x, n.z), hl = simd_length(hz)
            if n.y > -0.42 && hl > 1e-3 {              // (flatter than 25 degrees: a 30-degree shot still leans, P357 e)
                let side = simd_normalize(V3(-n.z, 0, n.x))
                axes = (side, -n, simd_cross(side, -n))
            } else {
                let lean = hl > 1e-3 ? min(1.2, hl / max(0.2, abs(n.y))) : 0
                shear = hl > 1e-3 ? hz / hl * lean : V2(0, 0)
            }
        }
        let ri = Int(ceilf(r))
        self.depth = depth ?? Int(ceilf(Float(ri) / 1.5))
        down = r / Float(max(1, self.depth))
        // (Turned: every cell within the bowl's longest reach, nearest first, each tested in the bowl's own space.)
        let reach = max(ri, self.depth)
        offsets = axes == nil ? Explosion.craterOffsets(ri, depth: self.depth) : Explosion.craterOffsets(reach, depth: reach)
        if quiet { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        g.world.ships.blast(at: c, power: 14, game: g, resistCap: Armour.heavyCap)
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
        // P502: a breach burst wholly over the world's top (a deck gun's shell timed out in the sky) or under it, or at
        // a point that isn't one, has nothing to carve, scorch or wait for.
        guard World.reachesWorld(center, max(r * 1.5, Float(depth)) + 4) else { done = true; CraterJob.outside &+= 1; return true }
        // (the frame's shared carving: none left, it waits a frame; the harness's whole-crater calls are untimed)
        let timed = blocks != .max
        if timed && CraterJob.allowance() <= 0 { return false }
        let began = CFAbsoluteTimeGetCurrent()
        var phase = "wait", removed0 = removed
        let refills0 = World.refilledAtOnce          // (Nov 4: a shell chunk refilled on the frame thread by an edit)
        let fine0 = World.fineMade
        if World.fineWhy { World.fineLog.removeAll(keepingCapacity: true) }
        var fetchedNow = false                       // (a lean prefetch beside this step's carving)
        // (Nov 12, the worst-case soak on build 356: one "carving" step of 59 blocks took 9.2 ms against a 1.6 ms
        // allowance looked at every 2 blocks; where its time went: before the loop, and the slowest span between looks.)
        var carveAt = 0.0, slowSpan = 0.0, slowIds = ""
        defer {
            if stepPhase == nil { stepPhase = phase }     // (the innermost call's: a scan that finds nothing carves at once)
            let took = CFAbsoluteTimeGetCurrent() - began
            if timed && CraterJob.inTick { CraterJob.used += took; FrameGovernor.charge(.carve, took) }
            // (sections given their fine samples by a step that was not a prefetch: one at a time or not, a frame's cost)
            if timed && World.fineMade - fine0 > (phase.hasSuffix("fine prefetch") || fetchedNow ? 1 : 0) {
                CraterJob.finesUnfetched += World.fineMade - fine0; CraterJob.stepsUnfetched += 1
                CraterJob.unfetchedPhases[phase, default: 0] += World.fineMade - fine0
                if World.fineWhy {
                    let ccx = floorDiv(Int(floor(center.x)), CS), ccz = floorDiv(Int(floor(center.z)), CS), csy = Int(floor(center.y)) >> 4
                    let made = World.fineLog.map { "(\(Int($0.x) - ccx),\(Int($0.y) - csy),\(Int($0.z) - ccz))" }.joined(separator: " ")
                    print(String(format: "fine why: %@ at %.0f %.0f %.0f r %.1f depth %d shear %.2f %.2f turned %@ prefetch frames %d: made %@ (chunk dx, section dy, chunk dz)",
                                 phase, center.x, center.y, center.z, r, depth, shear.x, shear.y, axes == nil ? "no" : "yes", fineFrames, made))
                }
            }
            if timed && took * 1000 > CraterJob.worstStepMs {
                CraterJob.worstStepMs = took * 1000
                CraterJob.worstStep = String(format: "%@, %ld blocks taken, r %.1f, %ld chunks refilled at once, %ld fine sections made", phase, removed - removed0, r, World.refilledAtOnce - refills0, World.fineMade - fine0)
                    + (carveAt > 0 ? String(format: "; %.1f ms before the carving, slowest span between looks at the clock %.1f ms (", (carveAt - began) * 1000, slowSpan * 1000) + slowIds + ")" : "")
            }
        }
        let cx = Int(floor(center.x)), cy = Int(floor(center.y)), cz = Int(floor(center.z))
        // (Oct 31: a far strike) The bowl and its scorch reach shell chunks round the impact (ChunkShells: blocks
        // dropped past the active distance): they come back on the workers first and the bowl opens under the dust
        // once they have (an edit refilled each one on the frame thread, 12-30 ms apiece); after 2 s it goes on anyway.
        if waitFrames >= 0 {
            if blocks != .max && waitFrames < 144 && !w.dataReady(around: center, reach: Int(ceilf(max(r * 1.5, Float(depth)))) + 3) {
                waitFrames += 1
                return false
            }
            waitFrames = -1
        }
        // (Nov 4, the worst-case soak: a carving step that took 2 blocks took 10.6 ms: each block of field ground taken
        // first gives its section its fine samples, 1-2 ms a section. The sections the bowl and its field balls reach
        // get theirs first, one a frame under the fireball, as the crawler's ruts do: World.prefetchFine.)
        if blocks != .max && fineFrames < 48 {
            if w.prefetchFine(center, radius: max(r, Float(depth))) { fineFrames += 1; phase = "fine prefetch"; return false }
            fineFrames = 48
        }
        // (Nov 8, the citadel and worst-case soaks with BS_FINEWHY=1: the crawler's deep bowls (26 down, leaning 1.2 blocks
        // a layer along the shot) still made 13 sections a scene during the carving, two chunks along the shot and one or
        // two sections down, past the box above. A leaning or turned bowl's sections down its axis get theirs one a step
        // beside the carving, which takes the nearest cells first and reaches those last; waiting for them first held the
        // bowl back over a second. BS_OLDBOWLFETCH=1 for before.)
        if blocks != .max && leanFetch && !CraterJob.oldFetch && (axes != nil || shear.x != 0 || shear.y != 0) {
            let dir: V3 = axes.map { -$0.1 } ?? V3(shear.x, -1, shear.y)
            var made = false
            for k in 1...4 where !made { made = w.prefetchFine(center + dir * (Float(depth) * Float(k) / 4), radius: r) }
            if made { fetchedNow = true } else { leanFetch = false }
        }
        if circuitsNear == nil {
            phase = "circuit scan"
            // Any circuit part within reach of the bowl or its scorch (a changed block marks neighbours up to 2 away)?
            // None: carve without the per-block circuit marks. 100k cells, straight through each chunk's array and
            // spread over the first few frames (one pass was a 30-40 ms frame); the carving waits for it (under the
            // fireball, unseen).
            let R = max(Int(ceilf(r * 1.5)), axes == nil ? 0 : depth) + 3     // (the scorch reaches 1.5 radii; a turned bowl its depth)
            let y0 = max(0, cy - max(R, depth + 3)), y1 = min(CH - 1, cy + R)
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
            // (Nov 12, "the crater took too long to form": the carving waited the scan's 9-10 frames. It starts now with the
            // circuit marks on, as if parts were near, and goes quiet once the scan has found none. BS_OLDCRATERWARM=1: waits.)
            if found { circuitsNear = true } else if scanY > y1 { circuitsNear = false } else if blocks != .max && MainGun.oldWarm { return false }
            if circuitsNear == nil && blocks == .max { return step(g, blocks: blocks) }   // (all at once: the harness's Explosion.crater)
        }
        phase = "carving"; removed0 = removed
        let quiet0 = w.circuitQuiet
        w.circuitQuiet = circuitsNear == false
        defer { w.circuitQuiet = quiet0 }
        var budget = blocks
        // Store review (Nov 2, VRC.Quest.Performance.1; questcheck --framesoak citadel: a main gun's bowl in a citadel's
        // walls cost 20-37 ms of tick a frame for 4 s, each of the 250 blocks a frame tipping, lighting and remeshing what
        // was built on it): a frame's carving also stops at `frameSeconds` of work (checked every 2 blocks), so the
        // bowl opens over more frames instead of the frame rate falling under the dust. (The harness's whole-crater
        // calls, blocks .max, are untimed.)
        let deadline = blocks == .max ? Double.infinity : CFAbsoluteTimeGetCurrent() + max(0, CraterJob.allowance() - (CFAbsoluteTimeGetCurrent() - began))
        var sinceCheck = 0
        carveAt = CFAbsoluteTimeGetCurrent()
        var lastLook = carveAt, spanA = AIR, spanB = AIR
        while next < offsets.count && budget > 0 && removed < cap {
            sinceCheck += 1
            if sinceCheck >= 2 {
                sinceCheck = 0
                let now = CFAbsoluteTimeGetCurrent()
                if timed && now - lastLook > slowSpan { slowSpan = now - lastLook; slowIds = Blocks.key(spanA) + ", " + Blocks.key(spanB) }
                lastLook = now; spanA = AIR; spanB = AIR
                if now > deadline { break }
            }   // (build 110: 19 citadel blocks took 3.8 ms, 0.2 ms each, so 8 between looks overran the allowance by 1.6 ms)
            let o = offsets[next]
            next += 1
            let dx = Int(o.x), dy = Int(o.y), dz = Int(o.z)
            let y = cy + dy
            guard y > 0 && y < CH - 1 else { continue }
            let d2: Float
            if let (ax, ay, az) = axes {
                let o3 = V3(Float(dx), Float(dy), Float(dz))
                if simd_length_squared(o3) > Float(max(r * r, Float(depth * depth))) + 1 { next = offsets.count; break }
                let ly = simd_dot(o3, ay), lx = simd_dot(o3, ax), lz = simd_dot(o3, az)
                let lyf = ly * (ly < 0 ? down : 1)
                d2 = lx * lx + lz * lz + lyf * lyf
                if d2 > r * r { continue }
            } else {
                let dyf = Float(dy) * (dy < 0 ? down : 1)        // a bowl (the old one shallower than wide, P99's deep)
                d2 = Float(dx * dx + dz * dz) + dyf * dyf
                if d2 > r * r { next = offsets.count; break }     // nearest first: nothing further can be inside
            }
            let edge: Float = r * (0.8 + 0.2 * hashf(cx + dx, y, cz + dz, 911))
            guard d2 <= edge * edge else { continue }
            let sx = dy < 0 ? Int((shear.x * Float(-dy)).rounded()) : 0, sz = dy < 0 ? Int((shear.y * Float(-dy)).rounded()) : 0
            let x = cx + dx + sx, z = cz + dz + sz
            let id = w.block(x, y, z)
            if id == AIR || Blocks.isLiquid(id) || Blocks.hardness[Int(id)] < 0 { continue }
            let b = IVec3(x, y, z)
            if let be = w.blockEntities.removeValue(forKey: b) {
                for s in be.container.slots where !s.isEmpty { g.drops.spawn(s, at: V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)) }
                be.container.slots = Array(repeating: .empty, count: be.container.slots.count)
            }
            for s in Explosion.blastDrops(id) { g.drops.spawn(s, at: V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)) }      // (P452)
            w.setBlockAsync(x, y, z, AIR)
            if spanA == AIR { spanA = id } else { spanB = id }
            removed += 1
            budget -= 1
            if d2 > (edge - 1.5) * (edge - 1.5) { rim.append(b) }
        }
        if (next >= offsets.count || removed >= cap) && !carved {
            carved = true
            phase = "carving, then the tip check and rim fluids"
            w.queueTipCheck(IVec3(cx, cy, cz), Int(ceil(r)) + 1)        // (P503: what stood over the breach weighed)
            for b in rim { w.scheduleFluid(around: b) }
            rim.removeAll()
        }
        // P476 (Oct 27 19:17, "Some of the ground didn't quite disappear after the frigate's shot damage"): in a field
        // world each block taken opened only a ball under a block across round its centre, which left slivers and fins
        // of drawn ground standing in the bowl; the bowl is carved out of the field as a whole too, one ball a frame
        // down its axis (as a plain blast's bowl is: Explosion.explode).
        if carved && bowlNext < 6 && (w.fieldTerrain || w.keepsField) {
            // (Store review, build 96's citadel soak: the ball ran after the frame's carving had already used the
            // allowance, 6.7 ms of one frame; it waits for the next frame's now, with the blocks all taken by then.)
            if timed && CFAbsoluteTimeGetCurrent() > deadline { return done }
            let t = Float(bowlNext) * Float(depth) / 6
            let k = t / Float(max(1, depth))
            let rr = 0.85 * r * sqrtf(max(0.05, 1 - k * k))
            phase = "field ball"
            let along: V3 = axes.map { -$0.1 * t } ?? V3(shear.x * t, -t, shear.y * t)
            // (Nov 8, every soak scene on build 245: a citadel ball took 5.1 ms of one frame, giving 3 sections their
            // fine samples at once: the prefetch under the fireball covers a box of the bowl's radius or depth and
            // stops after 48 frames, and the lower balls reach past it. Each ball's own sections get theirs first,
            // one a frame, as the prefetch's do.)
            if timed && w.prefetchFine(center + along, radius: rr) { phase = "field ball: fine prefetch"; return done }
            _ = w.carve(at: center + along, radius: rr, mode: .shape)
            bowlNext += 1
            return done
        }
        if carved && budget > 0 && CFAbsoluteTimeGetCurrent() < deadline { phase += " + scorch"; scorch(g, columns: max(1, budget / 3), until: deadline) }      // (up to ~3 block changes a column)
        return done
    }
    private var bowlNext = 0

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
    // (Nov 4, the worst-case soak: one step's scorch took 15.2 ms of a frame, its columns never looking at the clock;
    // it stops at the frame's carving deadline now, every 4 columns, as the carving does every 2 blocks.)
    private func scorch(_ g: Game, columns: Int, until deadline: Double = .infinity) {
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
        let coarse = Blocks.id("coarse_dirt"), snowLayer = Blocks.has("snow") ? Blocks.id("snow") : AIR
        let grass = Blocks.id("grass_block"), podzol = Blocks.id("podzol"), dirt = Blocks.id("dirt")
        var n = columns, sinceCheck = 0
        while n > 0 && scorchNext < cols.count {
            sinceCheck += 1
            if sinceCheck >= 4 { sinceCheck = 0; if CFAbsoluteTimeGetCurrent() > deadline { break } }
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
            let floorY = max(1, cy - max(Int(r), depth) - 1)          // (P99: the deep bowl's floor too)
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
            if h > r * 0.7 && hashf(x, y, z, 917) < 0.05 * fade && w.isAir(x, y + 1, z) && to != magma {
                w.lightFire(IVec3(x, y + 1, z))
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
            if !g.world.activeHere(t.pos) { continue }            // P376: a lit block past the active distance waits
            FarTicks.note(g.world, t.pos)
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
        // (The code reader's Nov 10 batch, 2: a big stack went off all in one frame, a full explosion for every block
        // whose fuse ran out, and a chain primes everything in reach with 0.5-1.5 s fuses: the frame rate dropped for
        // about a second. Now the blasts of a frame stop once 3 ms have gone (always one); the rest, fuse spent, go off
        // in the next frames in the order they were lit. BS_OLDTNT=1: all at once.)
        if TNTManager.oldAll || boom.count <= 1 {
            list.removeAll { $0.fuse <= 0 }
            for p in boom { Explosion.explode(at: p, power: 4, game: g, decay: false) }
            return
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        var gone = 0
        for t in list where t.fuse <= 0 && g.world.activeHere(t.pos) {
            if gone > 0 && (CFAbsoluteTimeGetCurrent() - t0) * 1000 > TNTManager.frameMs { break }
            t.fuse = -.infinity                                    // (marked: gone)
            gone += 1
            Explosion.explode(at: t.pos + V3(0, 0.49, 0), power: 4, game: g, decay: false)
        }
        list.removeAll { $0.fuse == -.infinity }
        TNTManager.deferred += boom.count - gone
    }
    static let oldAll = ProcessInfo.processInfo.environment["BS_OLDTNT"] == "1"
    static var frameMs = 3.0
    static var deferred = 0                                        // (harness: blasts moved to a later frame)

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

// Ledger 42 (Nov 6, the taiga24 battle: a shell's crater 16-22 ms of one tick on the host, two in a tick 32-50 ms): about
// half of it was shaping the ground (the bowl's field balls, three passes over the rim for dots of rock left standing,
// the opened cells past the bowl). That part is this job: in the game (deferred, set by QuestApp.headsetWorld) it runs
// a piece at a time on the frames after the blast, within the carving allowance (CraterJob), under the fireball; the
// host checks run it at once. The steps are the old code's, in its order (BS_OLDBLAST=1: at once on the headset too).
extension Circuit {
    static let takesOnly: Set<K> = [.lamp, .piston, .stickyPiston, .pistonHead, .dispenser, .dropper, .hopper, .note, .door, .trapdoor,
                                    .gate, .tnt, .bell, .ironDoor, .ironTrapdoor, .rail, .poweredRail, .activatorRail, .copperBulb, .crafter]
    static let drives: [Bool] = kinds.map { $0 != .none && !takesOnly.contains($0) }
}

extension Explosion {
    static var circuitCalm = ProcessInfo.processInfo.environment["BS_OLDCIRCUIT"] != "1"
}

extension World {
    // Any circuit part that makes or carries power (Circuit.drives) in the box round these cells, `margin` wider: a chunk
    // at a time (scanBuilt). Parts that only take power (doors, gates, rails, lamps, pistons...) change only through a
    // part that makes or carries it beside them, so a box with none of those needs no marks (build 214: the taiga24
    // battle's craters near a railway and a camp's gates were still marked cell by cell).
    func circuitNear<S: Sequence>(_ cells: S, margin: Int) -> Bool where S.Element == IVec3 {
        var it = cells.makeIterator()
        guard let f = it.next() else { return false }
        var lo = f, hi = f
        for c in cells { lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)); hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z)) }
        var found = false
        scanBuilt(lo.x - margin, lo.y - margin, lo.z - margin, hi.x + margin, hi.y + margin, hi.z + margin,
                  want: { Circuit.drives[Int($0)] }) { _, _, _ in found = true; return false }
        return found
    }
}

final class BlastShape {
    static var deferred = false
    static var queue: [BlastShape] = []
    static var worstStepMs = 0.0, worstStep = ""             // (perf scenes)
    @WeakLink var world: World? = nil
    let balls: [(V3, Float)]
    let opened: [IVec3]
    private var carved = Set<IVec3>()
    private var stage = 0                                     // 0..<balls: a ball; then the rim passes
    private var pass = 0, scanned = false, dots: [IVec3] = [], next = 0, openedDone = false
    let quiet: Bool                                           // (no circuit part near: ledger 45)

    init(world: World, balls: [(V3, Float)], opened: [IVec3], quiet: Bool = false) {
        self.world = world; self.balls = balls; self.opened = opened; self.quiet = quiet
    }

    // Does pieces until `deadline` (at least one); true when the crater is shaped.
    func step(_ g: Game, until deadline: Double) -> Bool {
        guard let w = world, w === g.world else { return true }        // (left for another dimension: dropped)
        let quiet0 = w.circuitQuiet
        if quiet { w.circuitQuiet = true }
        defer { w.circuitQuiet = quiet0 }
        var first = true
        while first || CFAbsoluteTimeGetCurrent() < deadline {
            first = false
            if stage < balls.count {
                let (at, rr) = balls[stage]
                w.carve(at: at, radius: rr, mode: .dig) { [self] p, b in
                    carved.insert(p)
                    for s in Explosion.blastDrops(b) { g.drops.spawn(s, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)) }
                }
                stage += 1
                if stage == balls.count { Explosion.lap("bowl") }
                continue
            }
            // P508 (questcheck craterplace: 3 to 6 a crater, as the rays fell): round the bowls' edge the field drew some
            // ground cells as a dot of rock (their middle barely inside it), each a block the eye sees past and a click
            // refuses; they open as the bowl did.
            // Nov 4 (bug hunt, the render suite's craterplace: 5 left where qc120 left 2): one scan missed the dots the
            // shaping made after it (each opened dot's and blasted cell's own hollow thins the field round it), so the
            // scan runs again over what the last pass shaped, a block wider each time, until none is left (three passes
            // at most). A dot drops what it holds, as the bowl's cells do.
            if pass >= 3 { return true }
            if !scanned {
                dots.removeAll(keepingCapacity: true)
                let reach = 1.5 + Float(pass)
                for (at, rr) in balls {
                    let R = Int(ceil(rr + reach)), ax = Int(floor(at.x)), ay = Int(floor(at.y)), az = Int(floor(at.z))
                    for y in (ay - R)...(ay + R) { for z in (az - R)...(az + R) { for x in (ax - R)...(ax + R) {
                        let q = IVec3(x, y, z), mid = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
                        guard !carved.contains(q), simd_length(mid - at) < rr + reach, w.groundAt(x, y, z),
                              Blocks.hardness[Int(w.block(x, y, z))] >= 0, w.fieldDensity(at: mid) < 0.12 else { continue }
                        carved.insert(q); dots.append(q)
                    } } }
                }
                Explosion.lap("rim scan \(dots.count)")
                if pass > 0 && dots.isEmpty { pass = 3; return true }
                scanned = true; next = 0
                continue
            }
            if next < dots.count {
                let q = dots[next]; next += 1
                for s in Explosion.blastDrops(w.block(q.x, q.y, q.z)) { g.drops.spawn(s, at: V3(Float(q.x) + 0.5, Float(q.y) + 0.5, Float(q.z) + 0.5)) }
                w.setBlockAsync(q.x, q.y, q.z, AIR); w.fieldShape(q.x, q.y, q.z, opened: true)
                if next == dots.count { Explosion.lap("dots shaped") }
                continue
            }
            // (the opened cells the bowl doesn't reach their own round hollow, as every one had: a bowl's ball pulls the
            // surface in to a block and a half past its radius)
            if pass == 0 && !openedDone {
                if next - dots.count < opened.count {
                    let b = opened[next - dots.count]; next += 1
                    let q = V3(Float(b.x), Float(b.y), Float(b.z)) + 0.5
                    if !balls.contains(where: { simd_length(q - $0.0) < $0.1 + 1 }) { w.fieldShape(b.x, b.y, b.z, opened: true) }
                    continue
                }
                openedDone = true
                Explosion.lap("opened shaped")
            }
            pass += 1; scanned = false
        }
        return false
    }

    // The game's tick: the queued craters' pieces, oldest first, while the frame's carving allowance lasts (one piece a
    // tick at least, so a long battle's craters never wait on each other for ever).
    static func tick(_ g: Game) {
        var first = true
        while let j = queue.first {
            let left = CraterJob.allowance()
            if !first && left <= 0 { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            let done = j.step(g, until: t0 + max(0, left))
            let took = CFAbsoluteTimeGetCurrent() - t0
            CraterJob.spend(took)
            if took * 1000 > worstStepMs { worstStepMs = took * 1000; worstStep = "\(queue.count) craters queued" }
            first = false
            if done { queue.removeFirst() } else { return }
        }
    }
}
