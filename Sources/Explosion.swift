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
        guard cap.isFinite else { return r0 }
        if r0 <= 12 { return min(cap, r0) }
        if r0 <= 600 && Blocks.hardness[Int(id)] >= 0 { return min(r0, cap * 3) }
        if Armour.isGrade(id) { return Armour.breach }
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
    static let heavyPlayerReach: Float = 14         // P501: how far a heavy shell's burst reaches him (Explosion.explode)
    // P472: a crash's own blasts spare whoever rides the crashing ship (CapitalShips.hullContact, VehicleDamage).
    static var sparePlayer = false
    // (--turretfreeze: the slowest blast, stage by stage; nested blasts count in the outer one)
    static var lapT = 0.0, lapT0 = 0.0, lapDepth = 0, laps = "", worstMs = 0.0, worstLaps = ""
    static func lapStart() { lapDepth += 1; if lapDepth == 1 { lapT = CFAbsoluteTimeGetCurrent(); lapT0 = lapT; laps = "" } }
    static func lap(_ s: String) {
        guard lapDepth == 1 else { return }
        let t = CFAbsoluteTimeGetCurrent(); laps += String(format: "%@ %.1f, ", s, (t - lapT) * 1000); lapT = t
    }
    static func lapEnd(_ s: String) {
        lap(s); lapDepth -= 1
        guard lapDepth == 0 else { return }
        let ms = (lapT - lapT0) * 1000
        if ms > worstMs { worstMs = ms; worstLaps = laps }
    }

    static func explode(at c: V3, power: Float, game g: Game, fire: Bool = false, except: Mob? = nil, breakBlocks: Bool = true,
                        decay: Bool = true, resistCap: Float = .infinity, along: V3? = nil) {
        let w = g.world
        Explosion.lapStart()
        defer { Explosion.lapEnd("entities") }
        // P357 (e) (Oct 16 20:14: "a shell crater follows the angle of the shot"): a shell's blast carries on the way it
        // was flying: rays along the shot reach further, those back toward the gun less, so a plunging shot leaves a
        // slanted bowl and a flat one a gouge running on from where it struck.
        let shot: V3? = along.flatMap { simd_length($0) > 1e-3 ? simd_normalize($0) : nil }
        // No friendly fire: the Capital's own shells (bases.quiet) leave its citadels' blocks and its troops alone.
        let own = g.bases.quiet
        let lying = g.drops.items.count                    // (what this blast spills itself is thrown, not burnt: P452)
        let breakBlocks = breakBlocks && !(own && g.bases.inAnyBase(c))
        g.baseNoise(at: c, kind: .explosion, power: power)  // citadels hear it (CapitalBases.swift)
        w.ships.blast(at: c, power: power, game: g, resistCap: resistCap)          // ship blocks (ShipCombat.swift)
        Explosion.lap("ships")
        var destroyed = Set<IVec3>()
        var shaken: [IVec3: Float] = [:]                    // blocks that stopped a ray: share of their cost it carried
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
                let id = w.block(b.x, b.y, b.z)
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
            w.setBlockAsync(b.x, b.y, b.z, AIR)
        }
        Explosion.lap("bodies, removal")
        for b in destroyed { w.scheduleFluid(around: b) }
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
            if let shot {                                       // (the bowl leans and runs on along the shot)
                w.carve(at: c + shot * (r * 0.3), radius: r * 0.9, mode: .shape)
                w.carve(at: c + shot * (r * 0.95), radius: r * 0.6, mode: .shape)
            } else {
                w.carve(at: c, radius: r, mode: .shape)
            }
        }
        Explosion.lap("fluids, carve")
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
    static var initCost = ""                 // (MainGunTests)
    static var outside = 0                   // (P502: breaches burst outside the world, questcheck --turretfreeze)
    private var circuitsNear: Bool?
    private var waitFrames = 0
    private var scanY = Int.min
    static let scanLayers = 6                // circuit scan: y layers per frame (47 x 47 cells each)

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
        if circuitsNear == nil {
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
            removed += 1
            budget -= 1
            if d2 > (edge - 1.5) * (edge - 1.5) { rim.append(b) }
        }
        if (next >= offsets.count || removed >= cap) && !carved {
            carved = true
            w.queueTipCheck(IVec3(cx, cy, cz), Int(ceil(r)) + 1)        // (P503: what stood over the breach weighed)
            for b in rim { w.scheduleFluid(around: b) }
            rim.removeAll()
        }
        // P476 (Oct 27 19:17, "Some of the ground didn't quite disappear after the frigate's shot damage"): in a field
        // world each block taken opened only a ball under a block across round its centre, which left slivers and fins
        // of drawn ground standing in the bowl; the bowl is carved out of the field as a whole too, one ball a frame
        // down its axis (as a plain blast's bowl is: Explosion.explode).
        if carved && bowlNext < 6 && (w.fieldTerrain || w.keepsField) {
            let t = Float(bowlNext) * Float(depth) / 6
            let k = t / Float(max(1, depth))
            let rr = 0.85 * r * sqrtf(max(0.05, 1 - k * k))
            let along: V3 = axes.map { -$0.1 * t } ?? V3(shear.x * t, -t, shear.y * t)
            _ = w.carve(at: center + along, radius: rr, mode: .shape)
            bowlNext += 1
            return done
        }
        if carved && budget > 0 { scorch(g, columns: max(1, budget / 3)) }      // (up to ~3 block changes a column)
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
