import Foundation
import simd

// Reference mob conversions and special spawners:
// - Zombies (and zombie villagers) with their head under water for 30 s start converting and become
//   Sunken 15 s later; Dust Zombies become Zombies the same way. Skeletons stuck in powder snow for 7 s
//   become Frost Skeletons 15 s later. Boarlings, brutes and Tuskers outside the Emberdeep turn undead
//   after 15 s. Tadpoles grow into frogs after 20 minutes (variant by biome temperature).
// - Zombies on Hard call reinforcements when hurt (each zombie's own 0-10% chance).
// - Wandering trader: checked once a day (chance 25% -> 50% -> 75%, reset on success), then 1 in 10,
//   near the village bell or the player, with two trader llamas; leaves after 40 minutes.
// - Village cats: every minute, a spot 8-32 blocks from the player; in a village (5+ villager beds within
//   48 blocks) with fewer than 5 cats around, a stray cat moves in.
// - Skeleton traps: a thunderstorm bolt may leave a skeleton horse (effective difficulty x 1%); when a
//   player comes within 10 blocks lightning strikes and four skeleton horsemen appear.
extension Mob {
    // Returns true when this mob has just been replaced by its converted form.
    func conversionTick(_ dt: Float, _ g: Game) -> Bool {
        let w = g.world
        let target: MobKind?
        var progressing = false
        switch kind {
        case .zombie, .zombieVillager, .husk:
            let head = w.block(Int(floor(pos.x)), Int(floor(pos.y + height * 0.85)), Int(floor(pos.z)))
            progressing = Blocks.fluidKind[Int(head)] == 1
            target = kind == .husk ? .zombie : .drowned
        case .skeleton:
            progressing = convertTime > 7 || w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.3)), Int(floor(pos.z))) == PathFinder.powderSnow
                && PathFinder.powderSnow != AIR
            target = .stray
        case .piglin, .piglinBrute, .hoglin:
            progressing = w.dim != .nether
            target = kind == .hoglin ? .zoglin : .zombifiedPiglin
        case .tadpole:
            progressing = true
            target = .frog
        default:
            return false
        }
        guard let into = target else { return false }
        if !progressing && convertTime < (kind == .skeleton ? 7 : 30) { convertTime = 0; return false }
        convertTime += dt
        let needed: Float
        switch kind {
        case .tadpole: needed = 1200
        case .skeleton: needed = 22
        case .piglin, .piglinBrute, .hoglin: needed = 15
        default: needed = 45
        }
        if convertTime >= needed - 15 && kind != .tadpole && Rand.float(in: 0..<1) < dt * 3 {
            g.particles.smoke(at: pos + V3(0, height * 0.6, 0))
        }
        guard convertTime >= needed else { return false }
        let m = Mob(into, at: pos)
        m.yaw = yaw
        m.customName = customName
        m.persistent = persistent
        if into != .frog { m.equip = equip }
        if kind == .zombieVillager || kind == .zombie || kind == .husk { m.baby = baby; m.scale = scale }
        if into == .frog {
            let b = w.gen.column(Int(floor(pos.x)), Int(floor(pos.z))).biome
            let warm: Set<Biome> = [.desert, .warmOcean, .jungle, .sparseJungle, .bambooJungle, .mangroveSwamp, .savanna, .savannaPlateau,
                                    .windsweptSavanna, .badlands, .erodedBadlands, .woodedBadlands]
            m.variant = warm.contains(b) || w.dim == .nether ? 2 : (Spawns.snowy.contains(b) ? 1 : 0)
        }
        g.mobs.mobs.append(m)
        g.sfx(into == .frog ? .splash : .mobZombie, 0.8, at: pos)
        health = -2000
        return true
    }

    // Hard: a hurt zombie may call another zombie 7-40 blocks away (reference reinforcements).
    func callReinforcement(_ g: Game) {
        guard isZombie, kind != .zombieVillager, g.difficulty == 3, g.survival, Rand.float(in: 0..<1) < reinforceChance else { return }
        let w = g.world
        for _ in 0..<50 {
            let d = Rand.float(in: 7...40) * (Rand.bool() ? 1 : -1), e = Rand.float(in: 7...40) * (Rand.bool() ? 1 : -1)
            let x = Int(floor(pos.x + d)), z = Int(floor(pos.z + e))
            guard w.isLoaded(x, z) else { continue }
            var y = Int(floor(pos.y)) + 6
            while y > Int(floor(pos.y)) - 6 && !(Blocks.opaque[Int(w.block(x, y - 1, z))] && !Blocks.collide[Int(w.block(x, y, z))] && !Blocks.collide[Int(w.block(x, y + 1, z))]) { y -= 1 }
            guard y > Int(floor(pos.y)) - 6, w.lightAt(x, y, z).block < 10 else { continue }
            let at = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            if simd_length(at - g.player.pos) < 7 { continue }
            let z2 = Mob(kind, at: at)
            if z2.collides(at, w) { continue }
            z2.lockTime = 10
            z2.aggro = true
            reinforceChance -= 0.05                     // reference: each call lowers both zombies' chance
            z2.reinforceChance = max(0, reinforceChance)
            g.mobs.mobs.append(z2)
            return
        }
    }

    // Skeleton trap horse: springs when a player comes within 10 blocks.
    func trapTick(_ g: Game) {
        guard kind == .skeletonHorse, trap, g.alive, simd_length(g.player.pos - pos) < 10 else { return }
        trap = false
        g.lightningFlash = 1
        g.sfx(.thunder, 1.4, at: pos)
        var horses: [Mob] = [self]
        for _ in 0..<3 {
            let h = Mob(.skeletonHorse, at: pos + V3(Rand.float(in: -1.5...1.5), 0, Rand.float(in: -1.5...1.5)))
            horses.append(h)
            g.mobs.mobs.append(h)
        }
        for h in horses {
            h.owner = true
            h.persistent = true
            let s = Mob(.skeleton, at: h.pos + V3(0, h.height * 0.8, 0))
            s.mount = h
            s.jockey = true
            s.lockTime = 10
            var eq = [ItemStack](repeating: .empty, count: 5)
            if Items.has("iron_helmet") { eq[0] = ItemStack(Items.id("iron_helmet"), 1); eq[0].ench = Enchant.pack([(.protection, Rand.int(in: 1...3))]) }
            if Items.has("bow") { eq[4] = ItemStack(Items.id("bow"), 1); eq[4].ench = Enchant.pack([(.power, Rand.int(in: 1...3))]) }
            s.equip = eq
            g.mobs.mobs.append(s)
        }
    }
}

enum SpecialSpawners {
    static var traderTimer: Float = 60
    static var traderDelay: Float = 1200
    static var traderChance = 25
    static var catTimer: Float = 60
}

extension Game {
    // Called once a second (from patrolTick).
    func specialSpawnersTick(_ dt: Float) {
        guard dim.dim == .overworld else { return }
        SpecialSpawners.traderTimer -= dt
        if SpecialSpawners.traderTimer <= 0 {
            SpecialSpawners.traderTimer = 60
            SpecialSpawners.traderDelay -= 60
            if SpecialSpawners.traderDelay <= 0 {
                SpecialSpawners.traderDelay = 1200
                let chance = SpecialSpawners.traderChance
                SpecialSpawners.traderChance = min(75, max(25, chance + 25))
                if Rand.int(in: 0..<100) <= chance && Rand.int(in: 0..<10) == 0 {
                    var spawned = false
                    coop.withSeat(coop.active ? Rand.int(in: 0..<coop.seatCount) : 0, self) { spawned = self.spawnWanderingTrader() }   // any player
                    if spawned { SpecialSpawners.traderChance = 25 }
                }
            }
        }
        SpecialSpawners.catTimer -= dt
        if SpecialSpawners.catTimer <= 0 {
            SpecialSpawners.catTimer = 60
            spawnVillageCat()
        }
    }

    // Ground spot with room for a 2-high mob near (x, z), or nil.
    func groundSpot(_ x: Int, _ z: Int) -> V3? {
        guard world.isLoaded(x, z) else { return nil }
        let y = world.topY(x, z)
        guard y > 0, !Blocks.isLiquid(world.block(x, y, z)), Blocks.collide[Int(world.block(x, y, z))],
              !Blocks.collide[Int(world.block(x, y + 1, z))], !Blocks.collide[Int(world.block(x, y + 2, z))] else { return nil }
        return V3(Float(x) + 0.5, Float(y + 1), Float(z) + 0.5)
    }

    @discardableResult
    func spawnWanderingTrader() -> Bool {
        guard !mobs.mobs.contains(where: { $0.kind == .wanderingTrader }) else { return false }
        let center = nearVillage(player.pos) ?? player.pos
        for _ in 0..<10 {
            let x = Int(floor(center.x)) + Rand.int(in: -48...48), z = Int(floor(center.z)) + Rand.int(in: -48...48)
            guard let at = groundSpot(x, z), simd_length(at - player.pos) < 64 else { continue }
            let t = Mob(.wanderingTrader, at: at)
            t.villager = WanderingTrader.data()
            t.persistent = true
            mobs.mobs.append(t)
            for _ in 0..<2 {
                guard let lp = groundSpot(x + Rand.int(in: -4...4), z + Rand.int(in: -4...4)) else { continue }
                let l = Mob(.traderLlama, at: lp)
                l.target = t
                l.persistent = true
                mobs.mobs.append(l)
            }
            return true
        }
        return false
    }

    func spawnVillageCat() {
        let x = Int(floor(player.pos.x)) + Rand.int(in: 8...32) * (Rand.bool() ? 1 : -1)
        let z = Int(floor(player.pos.z)) + Rand.int(in: 8...32) * (Rand.bool() ? 1 : -1)
        guard let at = groundSpot(x, z) else { return }
        let beds = mobs.mobs.filter { $0.kind == .villager && $0.villager?.bed != nil && simd_length($0.pos - at) < 48 }.count
        guard beds > 4, mobs.mobs.filter({ $0.kind == .cat && simd_length($0.pos - at) < 48 }).count < 5 else { return }
        mobs.mobs.append(Mob(.cat, at: at))
    }

    // From a natural lightning strike during a thunderstorm.
    func lightningTrap(_ at: V3) {
        guard weather.thunder > 0.5, difficulty > 0, Rand.double(in: 0..<1) < Double(effectiveDifficulty) * 0.01 else { return }
        let h = Mob(.skeletonHorse, at: at)
        h.trap = true
        h.persistent = true
        mobs.mobs.append(h)
    }
}
