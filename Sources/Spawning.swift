import Foundation
import simd

// Natural spawning and despawning, following the reference NaturalSpawner:
// - Categories with caps (for the 17x17 chunks around a player): monster 24 (reference 70), creature 10, ambient 15,
//   water creature 5, water ambient 20, underground water creature 5, axolotls 5. Persistent mobs
//   (named, structure, raid...) don't count.
// - Monsters: a random column in a chunk within 8 chunks, a random height up to the surface, then up to
//   3 packs that wander +-5 blocks from there; each spot needs a solid floor, room for the body, at
//   least 24 blocks to the player, block light 0 and a dark enough sky (light <= random 0...7).
//   Per-biome weighted lists and pack sizes (husks and strays need open sky, drowned need water).
// - Slimes: slime chunks below y 40 in any light, swamps between y 51 and 69 on dark nights by moon phase.
// - Animals: a pack in 10% of newly generated chunks (biome creature lists), then a creature attempt
//   every 20 s under the cap; grass-like ground with light above 8.
// - Water creatures near the sea surface, glow squid in dark deep water, axolotls in lush-cave water on
//   clay, bats in dark caves below sea level.
// - Despawning: gone at once beyond 128 blocks (fish: 64), after 30 s beyond 32 blocks a 1/800 chance
//   per tick; animals, villagers and golems are persistent.
enum SpawnCategory: Int, CaseIterable {
    case monster, creature, ambient, waterCreature, waterAmbient, undergroundWater, axolotls, misc
    // Monsters 24 (reference 70): Quest round 4 found the surface crowded even after round 3, so a third of it.
    // Creatures 5 (reference 10): Remington found the world crowded with animals (store-quality pass).
    var cap: Int { [24, 5, 15, 5, 20, 5, 5, 0][rawValue] }
    var despawns: Bool { self != .creature && self != .misc }
    var farDistance: Float { self == .waterAmbient ? 64 : 128 }
}

typealias SpawnEntry = (kind: MobKind, weight: Int, min: Int, max: Int)

extension MobKind {
    var category: SpawnCategory {
        switch self {
        case .bat: return .ambient
        case .squid, .dolphin: return .waterCreature
        case .glowSquid: return .undergroundWater
        case .camelHusk, .zombieNautilus: return .monster
        case .nautilus: return .waterCreature
        case .cod, .salmon, .tropicalFish, .pufferfish: return .waterAmbient
        case .axolotl: return .axolotls
        case .villager, .ironGolem, .snowGolem, .wanderingTrader, .traderLlama, .minecart, .boat, .armorStand, .endCrystal,
             .enderDragon, .wither, .allay, .tadpole, .copperGolem: return .misc
        default: return hostile ? .monster : .creature
        }
    }
}

enum Spawns {
    static let snowy: Set<Biome> = [.snowyPlains, .iceSpikes, .snowyTaiga, .snowyBeach, .frozenRiver, .frozenOcean, .deepFrozenOcean,
                                    .snowySlopes, .frozenPeaks, .jaggedPeaks, .grove]

    // Reference monster spawn lists (weight, pack min, pack max).
    static func monsters(_ b: Biome) -> [SpawnEntry] {
        switch b {
        case .mushroomFields, .deepDark: return []
        default: break
        }
        var zombie: [SpawnEntry] = [(.zombie, 95, 4, 4), (.zombieVillager, 5, 1, 1)]
        var skeleton: [SpawnEntry] = [(.skeleton, 100, 4, 4)]
        if b == .desert {
            zombie = [(.zombie, 19, 4, 4), (.zombieVillager, 1, 1, 1), (.husk, 80, 4, 4), (.camelHusk, 1, 1, 1)]
            skeleton = [(.skeleton, 50, 4, 4), (.parched, 50, 4, 4)]
        }
        if b == .dripstoneCaves { zombie = [(.drowned, 95, 4, 4), (.zombieVillager, 5, 1, 1)] }
        if snowy.contains(b) { skeleton = [(.skeleton, 20, 4, 4), (.stray, 80, 4, 4)] }
        if b == .swamp || b == .mangroveSwamp { skeleton = [(.skeleton, 70, 4, 4), (.bogged, 50, 4, 4)] }
        var list: [SpawnEntry] = [(.spider, 100, 4, 4)] + zombie + skeleton
            + [(.creeper, 100, 4, 4), (.slime, 100, 4, 4), (.enderman, 10, 1, 4), (.witch, 5, 1, 1)]
        if b.isRiver { list.append((.drowned, 100, 1, 1)) }
        else if b.isOcean { list.append((.drowned, 5, 1, 1)) }
        return list
    }

    // Water creature / ambient lists by biome.
    static func water(_ b: Biome) -> [SpawnEntry] {
        switch b {
        case .warmOcean: return [(.squid, 10, 4, 4), (.pufferfish, 15, 1, 3), (.tropicalFish, 25, 8, 8), (.nautilus, 2, 1, 1)]
        case .lukewarmOcean, .deepLukewarmOcean: return [(.squid, 10, 1, 2), (.dolphin, 2, 1, 2), (.cod, 15, 3, 6), (.pufferfish, 5, 1, 3), (.tropicalFish, 25, 8, 8), (.nautilus, 2, 1, 1)]
        case .ocean, .deepOcean: return [(.squid, 1, 1, 4), (.dolphin, 1, 1, 2), (.cod, 10, 3, 6)]
        case .coldOcean, .deepColdOcean: return [(.squid, 3, 1, 4), (.cod, 15, 3, 6), (.salmon, 15, 1, 5)]
        case .frozenOcean, .deepFrozenOcean: return [(.squid, 1, 1, 4), (.salmon, 15, 1, 5)]
        case .river: return [(.squid, 2, 1, 4), (.salmon, 5, 1, 5)]
        case .frozenRiver: return [(.squid, 2, 1, 4), (.salmon, 5, 1, 5)]
        case .mangroveSwamp: return [(.tropicalFish, 25, 8, 8)]
        default: return []
        }
    }

    static func pick(_ list: [SpawnEntry]) -> SpawnEntry? {
        let total = list.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var r = Rand.int(in: 0..<total)
        for e in list { r -= e.weight; if r < 0 { return e } }
        return nil
    }

    // Biome at a block: the cave biomes underground (same climate rule as the generator), else the surface one.
    static func biome(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> Biome {
        let surface = w.gen.column(x, z).biome
        guard w.dim == .overworld, y < SEA - 10, y < w.topY(x, z) - 8, let wg = w.gen as? WorldGen else { return surface }
        let k = wg.climate(x, z)
        if k.e < -0.6 && y < YOFF { return .deepDark }
        if k.h > 0.55 { return .lushCaves }
        if k.c > 0.75 { return .dripstoneCaves }
        return surface
    }

    // Reference moon brightness for slime nights (full moon 1 ... new moon 0).
    static func moon(_ g: Game) -> Float { [1, 0.75, 0.5, 0.25, 0, 0.25, 0.5, 0.75][Int(g.time / DAY_LENGTH) & 7] }

    // One chunk in ten, chosen per world seed (they were the same chunks in every world).
    static func slimeChunk(_ x: Int, _ z: Int, seed: UInt64) -> Bool {
        let s = UInt32(truncatingIfNeeded: seed ^ (seed >> 32)) ^ 0x51113
        return hash3(floorDiv(x, 16), 0, floorDiv(z, 16), s) % 10 == 0
    }
}

extension MobManager {
    // Mobs of a category counting toward its cap (non-persistent, near the player).
    func count(_ c: SpawnCategory, near p: V3) -> Int {
        var n = 0
        for m in mobs where m.kind.category == c && !m.persistent && m.customName == nil && m.health > 0 {
            if abs(m.pos.x - p.x) < 136 && abs(m.pos.z - p.z) < 136 { n += 1 }
        }
        return n
    }

    // Hostile monsters within `r` blocks (3D), persistent or not: the local crowding check for cave spawns.
    func monstersNear(_ p: V3, _ r: Float) -> Int {
        var n = 0
        for m in mobs where m.kind.hostile && m.health > 0 && simd_length_squared(m.pos - p) < r * r { n += 1 }
        return n
    }

    // Called every tick from update: spawning on timers, chunk population once a second.
    func spawnTick(_ dt: Float, _ game: Game) {
        let w = game.world
        let p = game.player.pos
        passiveTimer -= dt
        if passiveTimer <= 0 {
            passiveTimer = 20
            if w.dim == .overworld && count(.creature, near: p) < cap(.creature, w) { trySpawnPassive(game) }
        }
        populateTimer -= dt
        if populateTimer <= 0 { populateTimer = 1; populateChunks(game) }
        hostileTimer -= dt
        if hostileTimer <= 0 {
            hostileTimer = 0.25
            if game.difficulty == 0 { mobs.removeAll { $0.kind.hostile && !$0.persistent && $0.kind.category == .monster } }
            if game.survival && game.difficulty > 0 && count(.monster, near: p) < cap(.monster, w) {
                for _ in 0..<4 { trySpawnHostile(game) }
            }
            trySpawnWaterAndAmbient(game)
        }
    }

    // Reference mob caps scale with the spawnable area: (2 x render distance + 1)^2 chunks out of the 17 x 17 at 8 (a flat
    // 70 monsters crowded into a small area at low render distances).
    func cap(_ c: SpawnCategory, _ w: World) -> Int {
        let rd = max(1, min(8, w.renderDistance))
        return max(1, c.cap * (2 * rd + 1) * (2 * rd + 1) / 289)
    }

    // Despawn rules for one mob (true = remove). `d` is the distance to the nearest player (3D).
    func shouldDespawn(_ m: Mob, _ d: Float, _ dt: Float, _ game: Game) -> Bool {
        let c = m.kind.category
        guard c.despawns, !m.persistent, m.customName == nil, !m.leashed, !m.raider, m.mount == nil, game.riding !== m else { return false }
        if d > c.farDistance { return true }
        if m.patrolling { return false }                  // patrols only vanish beyond 128 blocks (reference)
        if d > 32 {
            m.farTime += dt
            return m.farTime > 30 && Rand.float(in: 0..<1) < dt * 20 / 800
        }
        m.farTime = 0
        return false
    }

    // MARK: Animals

    // A creature pack in 3.5% of chunks the first time they load (the reference generation-time spawns put one in 10%;
    // about a third as many reads as a countryside, not a farmyard).
    func populateChunks(_ game: Game) {
        let w = game.world
        guard w.dim == .overworld else { return }
        let nest = Blocks.has("bee_nest") ? Blocks.id("bee_nest") : AIR
        var budget = 12                                  // chunks per pass (keeps first loads from hitching)
        for (k, c) in w.chunks where !populated.contains(k) {
            if budget <= 0 { populateTimer = 0.1; break }
            budget -= 1
            populated.insert(k)
            // Tree nests come with 2-3 bees inside (reference generation).
            if nest != AIR {
                // Read the chunk's own arrays (a world lookup per block cost ~3300 dictionary finds per chunk: profile).
                let base = Blocks.groupBase
                for lz in 0..<CS { for lx in 0..<CS {
                    let x = c.cx * CS + lx, z = c.cz * CS + lz
                    let top = min(CH - 1, Int(c.height[lx + lz * CS]))
                    for y in max(1, top - 12)...max(1, top) where base[Int(c.blocks[Chunk.index(lx, y, lz)])] == nest {
                        let h = IVec3(x, y, z)
                        if hives[h] == nil { hives[h] = (0..<Rand.int(in: 2...3)).map { _ in (nectar: false, time: 0) } }
                    }
                } }
            }
            var rng = SRng(UInt64(hash3(k.x, 7, k.z, 0xA41A1)) | 1)
            guard rng.float() < 0.035 else { continue }
            let x = c.cx * CS + rng.int(16), z = c.cz * CS + rng.int(16)
            guard case let (kind, lo, hi)? = MobManager.pickAnimal(w.gen.column(x, z).biome) else { continue }
            spawnAnimalPack(w, kind, x, z, Rand.int(in: lo...hi), chunk: k)
        }
    }

    func spawnAnimalPack(_ w: World, _ kind: MobKind, _ x: Int, _ z: Int, _ n: Int, chunk: ChunkKey? = nil) {
        let biome = w.gen.column(x, z).biome
        var placed = 0
        for _ in 0..<(n * 4) where placed < n {
            var sx = x + Rand.int(in: -4...4), sz = z + Rand.int(in: -4...4)
            if let k = chunk { sx = k.x * CS + mod(sx, CS); sz = k.z * CS + mod(sz, CS) }
            guard let y = animalSurface(w, sx, sz, kind), w.lightAt(sx, y, sz).sky > 8 || w.lightAt(sx, y, sz).block > 8 else { continue }
            let m = Mob(kind, at: V3(Float(sx) + 0.5, Float(y), Float(sz) + 0.5))
            if m.collides(m.pos, w) { continue }
            if kind == .fox && [.snowyTaiga, .grove, .snowySlopes].contains(biome) { m.variant = 1 }
            if kind == .wolf { m.variant = Mob.wolfVariant(biome) }
            if kind == .mooshroom && Rand.int(in: 0..<10) == 0 { m.variant = 1 }
            // Reference group data: after the first, 5% of a pack are young.
            if placed > 0 && Rand.float(in: 0..<1) < 0.05 { m.baby = true; m.scale = 0.5 }
            mobs.append(m)
            placed += 1
        }
    }

    func trySpawnPassive(_ game: Game) {
        let w = game.world
        let rd = min(w.renderDistance, 8)
        guard rd >= 3 else { return }
        let pcx = floorDiv(Int(floor(game.player.pos.x)), CS), pcz = floorDiv(Int(floor(game.player.pos.z)), CS)
        let dx = Rand.int(in: -rd...rd), dz = Rand.int(in: -rd...rd)
        if max(abs(dx), abs(dz)) < 2 { return }
        guard let c = w.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)] else { return }
        let x = c.cx * CS + Rand.int(in: 0..<CS), z = c.cz * CS + Rand.int(in: 0..<CS)
        guard case let (kind, lo, hi)? = MobManager.pickAnimal(w.gen.column(x, z).biome) else { return }
        spawnAnimalPack(w, kind, x, z, Rand.int(in: lo...hi), chunk: ChunkKey(x: c.cx, z: c.cz))
    }

    // MARK: Monsters

    // Floor below (x, y, z): walks down to the first spot with a solid top below and room above.
    private func floorBelow(_ w: World, _ x: Int, _ y0: Int, _ z: Int, minY: Int) -> Int? {
        var y = y0
        while y > minY {
            let below = w.block(x, y - 1, z)
            if Blocks.opaque[Int(below)] && !Blocks.collide[Int(w.block(x, y, z))] && !Blocks.collide[Int(w.block(x, y + 1, z))] { return y }
            y -= 1
        }
        return nil
    }

    // Reference isDarkEnoughToSpawn for the overworld.
    func darkEnough(_ w: World, _ x: Int, _ y: Int, _ z: Int, _ game: Game) -> Bool {
        let l = w.lightAt(x, y, z)
        if l.sky > Rand.int(in: 0..<32) { return false }
        if l.block > 0 { return false }
        return rawLight(l, game) <= Rand.int(in: 0...7)
    }

    // Reference raw brightness: block light or sky light less the sky darkening (0 at noon ... 11 at midnight);
    // a thunderstorm darkens by 10, so storms spawn monsters by day.
    func rawLight(_ l: (sky: Int, block: Int), _ game: Game) -> Int {
        var darken = max(0, min(11, Int(((1 - (game.daylight - 0.12) / 0.88) * 11).rounded())))
        if game.weather.thundering { darken = max(darken, 10) }
        return max(l.block, l.sky - darken)
    }

    func trySpawnHostile(_ game: Game) {
        let w = game.world
        if w.dim == .nether { trySpawnEmberdeep(game); return }
        if w.dim == .end { trySpawnEnd(game); return }
        let pp = game.player.pos
        guard count(.monster, near: pp) < cap(.monster, w) else { return }
        let rd = min(w.renderDistance, 8)
        let pcx = floorDiv(Int(floor(pp.x)), CS), pcz = floorDiv(Int(floor(pp.z)), CS)
        let x0 = (pcx + Rand.int(in: -rd...rd)) * CS + Rand.int(in: 0..<CS)
        let z0 = (pcz + Rand.int(in: -rd...rd)) * CS + Rand.int(in: 0..<CS)
        guard w.isLoaded(x0, z0) else { return }
        let top = w.topY(x0, z0)
        guard top > 2 else { return }
        // Structure spawns (reference overrides): marauders at watchtowers in any light, spikefish around sea temples.
        if let sc = w.gen.structures, trySpawnInStructure(sc, game, x0, z0, top) { return }
        // Half the attempts try the surface; the rest an exact random height that only counts when it is already an
        // open spot (cave air). Walking down from any random y turned every sample inside rock into a cave-floor spawn,
        // so caves got most of the mobs and the surface few (Quest round 3).
        let y: Int
        if Rand.int(in: 0..<2) == 0 {
            guard let ys = floorBelow(w, x0, top + 1, z0, minY: max(1, top - 8)) else { return }
            y = ys
        } else {
            let yr = Rand.int(in: 2...(top + 1))
            guard Blocks.opaque[Int(w.block(x0, yr - 1, z0))] && !Blocks.collide[Int(w.block(x0, yr, z0))]
                    && !Blocks.collide[Int(w.block(x0, yr + 1, z0))] else { return }
            y = yr
        }
        if w.block(x0, y - 1, z0) == BEDROCK { return }
        // Underground spots: one attempt in four, at most 2 a pack, and none while 6 monsters are already within 32
        // blocks (a cave let ~50 converge on the player, Quest round 4).
        let underground = y < top - 8
        if underground {
            guard Rand.int(in: 0..<4) == 0, monstersNear(pp, 32) < 6 else { return }
        }
        var spawned = 0
        for _ in 0..<3 {
            var x = x0, z = z0
            var entry: SpawnEntry?
            var groupSize = 4
            for _ in 0..<4 {
                x += Rand.int(in: 0..<6) - Rand.int(in: 0..<6)
                z += Rand.int(in: 0..<6) - Rand.int(in: 0..<6)
                guard w.isLoaded(x, z) else { continue }
                let at = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
                let d = simd_length(at - pp)
                if d < 24 || d > 128 { continue }
                let b = Spawns.biome(w, x, y, z)
                if entry == nil {
                    guard let e = Spawns.pick(Spawns.monsters(b)) else { break }
                    entry = e
                    groupSize = Rand.int(in: e.min...e.max)
                }
                guard let e = entry, canSpawnMonster(e.kind, w, x, y, z, b, game) else { continue }
                let m = Mob(e.kind, at: at)
                if e.kind == .slime { m.makeSlime(size: slimeSize(game)) }
                if m.collides(at, w) { continue }
                finishMonster(m, game)
                spawned += 1
                if spawned >= (underground ? 2 : 4) { return }  // reference cluster cap: 4 a spawn attempt (it ran to 12)
                groupSize -= 1
                if groupSize <= 0 { break }
            }
            if count(.monster, near: pp) >= cap(.monster, w) { return }
        }
    }

    func trySpawnInStructure(_ sc: StructureCache, _ game: Game, _ x: Int, _ z: Int, _ top: Int) -> Bool {
        let w = game.world
        let pp = game.player.pos
        if sc.structure(at: x, top, z, kind: "pillager_outpost") != nil {
            guard let y = floorBelow(w, x, top + 1, z, minY: top - 24), !Blocks.isLiquid(w.block(x, y, z)) else { return true }
            let at = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            if simd_length(at - pp) < 24 || mobs.filter({ $0.kind == .pillager && simd_length($0.pos - at) < 48 }).count >= 6 { return true }
            let m = Mob(.pillager, at: at)
            if m.collides(at, w) { return true }
            m.applyRaidBuffs(wave: 0, level: 0)
            mobs.append(m)
            return true
        }
        let y = Rand.int(in: max(1, SEA - 50)...SEA)
        if Blocks.fluidKind[Int(w.block(x, y, z))] == 1, sc.structure(at: x, y, z, kind: "monument") != nil {
            let at = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            guard simd_length(at - pp) >= 24, Rand.int(in: 0..<20) == 0 || w.lightAt(x, y, z).sky == 0,
                  mobs.filter({ $0.kind == .guardian && simd_length($0.pos - at) < 64 }).count < 12 else { return true }
            for _ in 0..<Rand.int(in: 2...4) {
                let q = at + V3(Rand.float(in: -2...2), Rand.float(in: -1...1), Rand.float(in: -2...2))
                if Blocks.fluidKind[Int(w.block(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z))))] == 1 { mobs.append(Mob(.guardian, at: q)) }
            }
            return true
        }
        return false
    }

    private func slimeSize(_ game: Game) -> Int {
        var i = Rand.int(in: 0..<3)
        if i < 2 && Rand.float(in: 0..<1) < 0.5 * game.regionalDifficulty { i += 1 }
        return 1 << i
    }

    // Per-kind placement rules on top of the category's floor check.
    func canSpawnMonster(_ k: MobKind, _ w: World, _ x: Int, _ y: Int, _ z: Int, _ b: Biome, _ game: Game) -> Bool {
        let feet = w.block(x, y, z)
        let wet = Blocks.fluidKind[Int(feet)] == 1
        // Every pack member needs its own valid spot: a solid top below and room for the body (water for drowned).
        if !wet {
            let below = w.block(x, y - 1, z)
            if !Blocks.opaque[Int(below)] || below == BEDROCK || Blocks.collide[Int(feet)] || Blocks.collide[Int(w.block(x, y + 1, z))] { return false }
        }
        switch k {
        case .drowned:
            // In water only: rivers 1/15, elsewhere 1/40, at least 5 below sea level; dark enough.
            guard wet, Blocks.fluidKind[Int(w.block(x, y - 1, z))] == 1 || Blocks.opaque[Int(w.block(x, y - 1, z))] else { return false }
            // Rivers 1/15 at any depth; elsewhere 1/40 and at least 5 below sea level (reference).
            guard b.isRiver ? Rand.int(in: 0..<15) == 0 : (Rand.int(in: 0..<40) == 0 && y < SEA - 5) else { return false }
            return darkEnough(w, x, y, z, game)
        case .slime:
            if wet { return false }
            if (b == .swamp || b == .mangroveSwamp) && y - YOFF > 50 && y - YOFF < 70 && Rand.float(in: 0..<1) < 0.5
                && Rand.float(in: 0..<1) < Spawns.moon(game) && rawLight(w.lightAt(x, y, z), game) <= Rand.int(in: 0..<8) {
                return true
            }
            return Spawns.slimeChunk(x, z, seed: w.seed) && y - YOFF < 40 && Rand.int(in: 0..<10) == 0
        default:
            if wet || Blocks.isLiquid(feet) { return false }
            if !darkEnough(w, x, y, z, game) { return false }
            if (k == .husk || k == .stray || k == .parched || k == .camelHusk) && w.topY(x, z) >= y { return false }      // need open sky
            return true
        }
    }

    // Babies, jockeys, armour and door breaking for a naturally spawned monster.
    // The deeper, the tougher: surface monsters from displayed y -16 down to the old floor (x1.6), the Deep tougher still (DeepGen).
    static func depthPower(_ d: Dim, _ y: Float) -> Float {
        guard d == .overworld else { return 1 }
        let yd = y - Float(YOFF)
        return yd < -16 ? 1 + min(0.6, (-16 - yd) / 80) : 1
    }

    func finishMonster(_ m: Mob, _ game: Game) {
        let w = game.world
        m.power = MobManager.depthPower(w.dim, m.pos.y)
        m.rollEquipment(difficulty: game.difficulty, regional: game.regionalDifficulty)
        m.canPickUp = ArmorLook.fits(m.kind) && Rand.float(in: 0..<1) < 0.55 * game.regionalDifficulty
        // Sunken: 10% hold something - 10 in 16 a trident, else a fishing rod; 3% a nautilus shell.
        if m.kind == .drowned && Rand.float(in: 0..<1) > 0.9 {
            let n = Rand.int(in: 0..<16) < 10 ? "trident" : "fishing_rod"
            if Items.has(n) { var eq = m.equip ?? [ItemStack](repeating: .empty, count: 5); eq[4] = ItemStack(Items.id(n), 1); m.equip = eq }
        }
        if m.isZombie {
            if Rand.float(in: 0..<1) < 0.05 { m.baby = true; m.scale = 0.5 }
            m.breaksDoors = m.kind != .drowned && Rand.float(in: 0..<1) < game.regionalDifficulty * 0.1
        }
        mobs.append(m)
        // Chicken jockey: 5% of baby zombies ride a chicken.
        if m.baby && m.isZombie && Rand.float(in: 0..<1) < 0.05 {
            let c: Mob
            if let near = mobs.first(where: { $0.kind == .chicken && !$0.baby && simd_length($0.pos - m.pos) < 5 }) { c = near }
            else { c = Mob(.chicken, at: m.pos); mobs.append(c) }
            c.persistent = true
            m.mount = c
            m.jockey = true
        }
        // Dust camels carry a dust zombie and a sunscorched skeleton; 5% of ocean sunken ride a sunken nautilus.
        if m.kind == .camelHusk {
            for rk in [MobKind.husk, .parched] {
                let r = Mob(rk, at: m.pos + V3(0, m.height, 0)); r.mount = m; r.jockey = true
                r.rollEquipment(difficulty: game.difficulty, regional: game.regionalDifficulty)
                mobs.append(r)
            }
        }
        if m.kind == .drowned && Rand.float(in: 0..<1) < 0.05 && w.gen.column(Int(floor(m.pos.x)), Int(floor(m.pos.z))).biome.isOcean {
            let n = Mob(.zombieNautilus, at: m.pos)
            mobs.append(n)
            m.mount = n
            m.jockey = true
        }
        // Spider jockey: 1% of spiders carry a skeleton.
        if m.kind == .spider && Rand.int(in: 0..<100) == 0 {
            let s = Mob(.skeleton, at: m.pos + V3(0, m.height, 0))
            s.mount = m
            s.jockey = true
            mobs.append(s)
        }
        _ = w
    }

    // The Hollow: voidwalkers (groups of up to 4) on hollow stone 24+ blocks out.
    func trySpawnEnd(_ game: Game) {
        let w = game.world
        let pp = game.player.pos
        let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 24...96)
        let x = Int(floor(pp.x + cosf(a) * r)), z = Int(floor(pp.z + sinf(a) * r))
        guard w.isLoaded(x, z) else { return }
        let top = w.topY(x, z)
        guard top > 0, Blocks.key(w.block(x, top, z)) == "end_stone" else { return }
        for _ in 0..<Rand.int(in: 1...4) {
            let sx = x + Rand.int(in: -2...2), sz = z + Rand.int(in: -2...2)
            let ty = w.topY(sx, sz)
            guard ty > 0, Blocks.key(w.block(sx, ty, sz)) == "end_stone" else { continue }
            let m = Mob(.enderman, at: V3(Float(sx) + 0.5, Float(ty + 1), Float(sz) + 0.5))
            if m.collides(m.pos, w) { continue }
            mobs.append(m)
        }
    }

    // MARK: Water and ambient

    func trySpawnWaterAndAmbient(_ game: Game) {
        let w = game.world
        guard w.dim == .overworld else { return }
        let pp = game.player.pos
        let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 24...96)
        let x = Int(floor(pp.x + cosf(a) * r)), z = Int(floor(pp.z + sinf(a) * r))
        guard w.isLoaded(x, z) else { return }
        let top = w.topY(x, z)
        guard top > 2 else { return }
        let y = Rand.int(in: 1...(top + 1))
        let id = w.block(x, y, z)
        let water = Blocks.fluidKind[Int(id)] == 1 && Blocks.fluidKind[Int(w.block(x, y + 1, z))] == 1
        if water {
            let b = Spawns.biome(w, x, y, z)
            if y >= SEA - 13 && y <= SEA {
                // Surface water: squid / dolphins (water creature) or fish (water ambient).
                guard let e = Spawns.pick(Spawns.water(b)) else { return }
                let cat = e.kind.category
                guard count(cat, near: pp) < cap(cat, w) else { return }
                spawnSwimmers(w, e.kind, x, y, z, Rand.int(in: e.min...e.max))
            } else if y <= SEA - 33 && w.lightAt(x, y, z).sky == 0 && w.lightAt(x, y, z).block == 0 {
                if b == .lushCaves && Blocks.key(w.block(x, y - 1, z)) == "clay" && count(.axolotls, near: pp) < cap(.axolotls, w) {
                    spawnSwimmers(w, .axolotl, x, y, z, Rand.int(in: 4...6))
                } else if count(.undergroundWater, near: pp) < cap(.undergroundWater, w) {
                    spawnSwimmers(w, .glowSquid, x, y, z, Rand.int(in: 2...4))
                }
            } else if b == .lushCaves && count(.waterAmbient, near: pp) < cap(.waterAmbient, w) {
                spawnSwimmers(w, .tropicalFish, x, y, z, 8)
            }
            return
        }
        // Bats: below sea level, a coin flip, then light <= random 0...3 (reference Halloween rule not modelled).
        if id == AIR && y < SEA && Rand.bool() && count(.ambient, near: pp) < cap(.ambient, w) {
            let l = w.lightAt(x, y, z)
            if max(l.block, l.sky) <= Rand.int(in: 0..<4) && !Blocks.collide[Int(w.block(x, y + 1, z))] {
                let bat = Mob(.bat, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
                if !bat.collides(bat.pos, w) { mobs.append(bat) }
            }
        }
        // Nightwings over a player who hasn't slept for 3+ days (reference PhantomSpawner): one check every 60-119 s
        // (this runs every 0.25 s), passing a local-difficulty roll and insomnia odds (t - 3 days) / t; 1 to
        // 1 + difficulty of them, no cap. It rolled every 0.25 s: about ten times too many.
        phantomTimer -= 0.25
        let rest = Float(game.timeSinceRest)
        if phantomTimer <= 0 { phantomTimer = Rand.float(in: 60..<120) } else { return }
        if game.survival && game.daylight < 0.3 && rest > 3600 && game.effectiveDifficulty > Rand.float(in: 0..<3)
            && Rand.float(in: 0..<1) < (rest - 3600) / rest,
           game.skyExposed(Int(floor(pp.x)), Int(floor(pp.y + 1)), Int(floor(pp.z))), pp.y > Float(SEA) {
            let n = 1 + Rand.int(in: 0...max(0, game.difficulty))
            for _ in 0..<n {
                mobs.append(Mob(.phantom, at: pp + V3(Rand.float(in: -10...10), 20 + Rand.float(in: 0...14), Rand.float(in: -10...10))))
            }
        }
    }

    private func spawnSwimmers(_ w: World, _ kind: MobKind, _ x: Int, _ y: Int, _ z: Int, _ n: Int) {
        for _ in 0..<n {
            let sx = x + Rand.int(in: -2...2), sy = y + Rand.int(in: -1...1), sz = z + Rand.int(in: -2...2)
            guard Blocks.fluidKind[Int(w.block(sx, sy, sz))] == 1 else { continue }
            let m = Mob(kind, at: V3(Float(sx) + 0.5, Float(sy) + 0.1, Float(sz) + 0.5))
            if kind == .tropicalFish || kind == .axolotl { m.variant = Rand.int(in: 0..<(kind == .axolotl ? 4 : 8)) }
            if kind == .axolotl && Rand.int(in: 0..<1200) == 0 { m.variant = 4 }       // the rare blue one
            if m.collides(m.pos, w) { continue }
            mobs.append(m)
        }
    }

    // MARK: Chunk population bookkeeping (saved next to mobs.json)

    func savePopulated(to s: SaveManager?) {
        guard let s = s else { return }
        let flat = populated.flatMap { [$0.x, $0.z] }
        if let d = try? JSONEncoder().encode(flat) { try? d.write(to: s.dir.appendingPathComponent("populated.json"), options: .atomic) }
    }

    func loadPopulated(from s: SaveManager?) {
        guard let s = s, let d = try? Data(contentsOf: s.dir.appendingPathComponent("populated.json")),
              let flat = try? JSONDecoder().decode([Int].self, from: d) else { return }
        var i = 0
        while i + 1 < flat.count { populated.insert(ChunkKey(x: flat[i], z: flat[i + 1])); i += 2 }
    }
}
