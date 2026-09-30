import Foundation
import simd

// The rest of the reference mob roster: animals (taming, riding, breeding foods), aquatic life,
// flying mobs, and the remaining monsters (nightwings, spikefishs, the deep stalker, gustlings, mire skeleton...).
// Health / size / drops follow the reference game (Normal difficulty).

extension MobKind {
    var animalSpec: Spec {
        func a(_ n: String, _ w: Float, _ h: Float, _ hp: Int, _ sp: Float, drops: [(String, Int, Int)] = [], xp: Int = 1,
               call: Snd = .mobCow, attack: Int = 0, flying: Bool = false, aquatic: Bool = false, beh: Behavior = .animal,
               fire: Bool = false, sun: Bool = false) -> Spec {
            Spec(name: n, halfW: w, height: h, health: hp, speed: sp, behavior: beh, attack: attack, burnsInSun: sun, drops: drops, xp: xp,
                 call: call, fireImmune: fire, flying: flying, aquatic: aquatic)
        }
        switch self {
        case .rabbit: return a("Rabbit", 0.2, 0.5, 3, 3, drops: [("rabbit", 0, 1), ("rabbit_hide", 0, 1)], xp: 2, call: .mobChicken)
        case .fox: return a("Fox", 0.3, 0.7, 10, 3.2, drops: [], xp: 2, call: .mobChicken, attack: 2)
        case .wolf: return a("Wolf", 0.3, 0.85, 8, 3.2, xp: 2, call: .mobWolf, attack: 4)
        case .cat: return a("Cat", 0.3, 0.7, 10, 3, drops: [("string", 0, 2)], xp: 2, call: .mobCat, attack: 3)
        case .ocelot: return a("Ocelot", 0.3, 0.7, 10, 3.4, xp: 2, call: .mobCat, attack: 3)
        case .horse: return a("Horse", 0.7, 1.6, 22, 3, drops: [("leather", 0, 2)], xp: 2, call: .mobHorse)
        case .donkey: return a("Donkey", 0.7, 1.5, 22, 3, drops: [("leather", 0, 2)], xp: 2, call: .mobHorse)
        case .mule: return a("Mule", 0.7, 1.6, 22, 3, drops: [("leather", 0, 2)], xp: 2, call: .mobHorse)
        case .llama, .traderLlama: return a(self == .llama ? "Llama" : "Trader Llama", 0.45, 1.87, 22, 2.5, drops: [("leather", 0, 2)], xp: 2, call: .mobLlama)
        case .camel: return a("Camel", 0.85, 2.375, 32, 2.2, xp: 2, call: .mobHorse)
        case .goat: return a("Goat", 0.45, 1.3, 10, 2.5, xp: 2, call: .mobSheep, attack: 2)
        case .panda: return a("Panda", 0.65, 1.25, 20, 1.8, drops: [("bamboo", 0, 1)], xp: 2, call: .mobPig, attack: 6)
        case .polarBear: return a("Polar Bear", 0.7, 1.4, 30, 3, drops: [("cod", 0, 2), ("salmon", 0, 2)], xp: 2, call: .mobRavager, attack: 6)
        case .turtle: return a("Turtle", 0.6, 0.4, 30, 1, drops: [("seagrass", 0, 2)], xp: 2, call: .mobSlime)
        case .frog: return a("Frog", 0.25, 0.5, 10, 2, xp: 2, call: .mobSlime)
        case .tadpole: return a("Tadpole", 0.2, 0.3, 6, 2, xp: 0, call: .mobSlime, aquatic: true)
        case .armadillo: return a("Armadillo", 0.35, 0.65, 12, 2.5, xp: 2, call: .mobPig)
        case .sniffer: return a("Snuffler", 0.95, 1.75, 14, 1.8, xp: 2, call: .mobCow)
        case .mooshroom: return a("Mushroom Cow", 0.45, 1.4, 10, 1, drops: [("beef", 1, 3), ("leather", 0, 2)], xp: 2, call: .mobCow)
        case .bee: return a("Bee", 0.35, 0.6, 10, 3, xp: 2, call: .mobBee, attack: 2, flying: true)
        case .parrot: return a("Parrot", 0.25, 0.9, 6, 3, drops: [("feather", 1, 2)], xp: 2, call: .mobChicken, flying: true)
        case .bat: return a("Bat", 0.25, 0.9, 6, 3, xp: 0, call: .mobVex, flying: true)
        case .allay: return a("Fetchling", 0.18, 0.6, 20, 3, xp: 0, call: .mobVex, flying: true)
        case .axolotl: return a("Axolotl", 0.38, 0.42, 14, 3, xp: 2, call: .mobSlime, attack: 2, aquatic: true)
        case .squid: return a("Squid", 0.4, 0.8, 10, 2, drops: [("ink_sac", 1, 3)], xp: 2, call: .splash, aquatic: true)
        case .glowSquid: return a("Glow Squid", 0.4, 0.8, 10, 2, drops: [("glow_ink_sac", 1, 3)], xp: 2, call: .splash, aquatic: true)
        case .dolphin: return a("Dolphin", 0.45, 0.6, 10, 8, drops: [("cod", 0, 1)], xp: 2, call: .splash, attack: 3, aquatic: true)
        case .cod: return a("Cod", 0.25, 0.3, 3, 3, drops: [("cod", 1, 1)], xp: 1, call: .splash, aquatic: true)
        case .salmon: return a("Salmon", 0.35, 0.4, 3, 3, drops: [("salmon", 1, 1)], xp: 1, call: .splash, aquatic: true)
        case .tropicalFish: return a("Tropical Fish", 0.25, 0.4, 3, 3, drops: [("tropical_fish", 1, 1)], xp: 1, call: .splash, aquatic: true)
        case .pufferfish: return a("Pufferfish", 0.35, 0.7, 3, 2, drops: [("pufferfish", 1, 1)], xp: 1, call: .splash, aquatic: true)
        case .wanderingTrader: return a("Wandering Trader", 0.3, 1.95, 20, 2.2, xp: 0, call: .mobVillager)
        case .skeletonHorse: return a("Skeleton Horse", 0.7, 1.6, 15, 3, drops: [("bone", 0, 2)], xp: 2, call: .mobSkeleton)
        case .happyGhast: return a("Cloudwailer", 2, 4, 20, 1.5, xp: 1, call: .mobWailer, flying: true)
        case .zombieHorse: return a("Zombie Horse", 0.7, 1.6, 15, 3, drops: [("rotten_flesh", 0, 2)], xp: 2, call: .mobZombie)
        case .illusioner: return a("Mirage Caster", 0.3, 1.95, 32, 2.5, drops: [], xp: 5, call: .mobVillager, beh: .ranged)
        case .phantom: return a("Nightwing", 0.45, 0.5, 20, 8, drops: [("phantom_membrane", 0, 1)], xp: 5, call: .mobVex, attack: 6, flying: true, beh: .monster, sun: true)
        case .guardian: return a("Spikefish", 0.43, 0.85, 30, 2.5, drops: [("prismarine_shard", 0, 2), ("cod", 0, 1)], xp: 10, call: .mobSlime, attack: 6, aquatic: true, beh: .monster)
        case .elderGuardian: return a("Elder Spikefish", 1, 2, 80, 1.5, drops: [("prismarine_shard", 0, 2), ("wet_sponge", 1, 1)], xp: 10, call: .mobRavager, attack: 8, aquatic: true, beh: .monster)
        case .endermite: return a("Voidmite", 0.2, 0.3, 8, 2.5, xp: 3, call: .mobSpider, attack: 2, beh: .monster)
        case .warden: return a("Deep Stalker", 0.45, 2.9, 500, 3, drops: [("sculk_catalyst", 1, 1)], xp: 5, call: .mobWarden, attack: 30, beh: .monster)
        case .breeze: return a("Gustling", 0.3, 1.77, 30, 3, drops: [("breeze_rod", 1, 2)], xp: 10, call: .mobVex, beh: .monster)
        case .bogged: return a("Mire Skeleton", 0.3, 1.99, 16, 2.5, drops: [("bone", 0, 2), ("arrow", 0, 2)], xp: 5, call: .mobSkeleton, beh: .ranged, sun: true)
        case .creaking: return a("Barkwraith", 0.45, 2.7, 100, 3.4, xp: 0, call: .mobSkeleton, attack: 3, beh: .monster, fire: true)
        case .zoglin: return a("Rot Tusker", 0.7, 1.4, 40, 2.5, drops: [("rotten_flesh", 1, 3)], xp: 5, call: .mobRavager, attack: 6, beh: .melee, fire: false)
        default: return a("?", 0.3, 1, 10, 1)
        }
    }

    // Breeding / taming foods (reference lists).
    static let animalFood: [MobKind: [String]] = [
        .rabbit: ["carrot", "golden_carrot", "dandelion"], .fox: ["sweet_berries", "glow_berries"], .wolf: ["beef", "cooked_beef", "porkchop", "cooked_porkchop", "chicken", "cooked_chicken", "mutton", "cooked_mutton", "rabbit", "cooked_rabbit", "rotten_flesh"],
        .cat: ["cod", "salmon"], .ocelot: ["cod", "salmon"], .horse: ["golden_apple", "golden_carrot"], .donkey: ["golden_apple", "golden_carrot"],
        .llama: ["hay_block"], .traderLlama: ["hay_block"], .camel: ["cactus"], .goat: ["wheat"], .panda: ["bamboo"], .turtle: ["seagrass"],
        .frog: ["slime_ball"], .armadillo: ["spider_eye"], .sniffer: ["torchflower_seeds"], .mooshroom: ["wheat"], .bee: ["dandelion", "poppy", "blue_orchid", "allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley", "sunflower"],
        .axolotl: ["tropical_fish_bucket"], .polarBear: [],
    ]
}

extension Mob {
    var tamed: Bool { owner == true }
    var horseLike: Bool { kind == .horse || kind == .donkey || kind == .mule || kind == .skeletonHorse || kind == .zombieHorse || kind == .llama || kind == .traderLlama || kind == .camel }

    // Common land-animal AI: follow food, breed, flee/panic, plus per-species behaviour.
    func animalAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool, inWater: Bool) -> Float {
        let w = g.world
        let player = g.player.pos
        // Being ridden: the rider steers (horses, camels, llamas with a carpet do not; pigs need the stick).
        if g.riding === self { return 0 }
        // Tamed pets follow the owner, sit on command, and fight what hurt the owner.
        if tamed && (kind == .wolf || kind == .cat || kind == .parrot) {
            if sitting { moving = false; return 0 }
            if kind == .wolf, let t = target, t.health > 0 {
                face(t.pos)
                if simd_length(t.pos - pos) < halfW + t.halfW + 1 && attackCooldown <= 0 {
                    attackCooldown = 1
                    t.hit(from: pos, damage: 4, knockback: 0.5)
                }
                return spec.speed * 1.2
            }
            target = nil
            if dist > 12 { pos = player + V3(Float.random(in: -1...1), 0, Float.random(in: -1...1)); vel = .zero; return 0 }
            if dist > 3 { face(player); return spec.speed }
            wander(); return moving ? spec.speed * 0.3 : 0
        }
        if kind == .panda, let sp = pandaAI(dt, g) { return sp }
        // Foxes sleep through the day unless disturbed (a player close by and not sneaking, danger, a hit).
        if kind == .fox {
            let day = g.dayFraction > 0.02 && g.dayFraction < 0.45 && !g.isRainingAt(pos)
            let disturbed = (g.alive && simd_length(player - pos) < 4 && !g.player.sneaking) || panic > 0 || aggro
            if day && !disturbed && onGround { sitting = true; return 0 }
            sitting = false
        }
        // Polar bear mothers attack players who come within 8 blocks of their cub.
        if kind == .polarBear && !baby && canTarget && dist < 8 && g.mobs.of(.polarBear).contains(where: { $0.baby && simd_length($0.pos - pos) < 16 }) {
            aggro = true
        }
        // Llamas spit (1 damage) at players who hurt them, every 2 s within 10 blocks.
        if (kind == .llama || kind == .traderLlama) && aggro && canTarget && dist < 10 && !tamed {
            face(player)
            if attackCooldown <= 0 && g.world.canSee(eye, g.player.eye) {
                attackCooldown = 2
                g.hurtPlayer(1, from: pos, cause: "was spat on by a Llama", knockback: 0.2, type: .projectile, attacker: self)
                g.sfx(.splash, 0.4, at: pos)
            }
            return 0
        }
        // Wolves: wild ones hunt sheep, rabbits, foxes, skeletons; angry at players who hit them.
        if kind == .wolf || kind == .polarBear || kind == .panda || kind == .goat || kind == .bee || kind == .fox || kind == .ocelot || kind == .cat {
            if aggro && canTarget {
                face(player)
                if dist < halfW + 1.2 && attackCooldown <= 0 {
                    attackCooldown = 1
                    g.hurtPlayer(spec.attack, from: pos, cause: "was slain by \(spec.name)", attacker: self)
                    if kind == .bee {
                        g.applyEffect(.poison, amp: 0, seconds: 10)
                        health = 0                                   // bees die after stinging
                    }
                    if kind == .goat { g.player.vel += simd_normalize(V3(player.x - pos.x, 0.3, player.z - pos.z)) * 10; aggro = false }
                }
                return spec.speed * 1.3
            }
            if kind == .wolf || kind == .fox || kind == .ocelot || kind == .cat {
                let prey: Set<MobKind> = kind == .wolf ? [.sheep, .rabbit, .fox, .skeleton, .stray] : (kind == .fox ? [.chicken, .rabbit, .cod, .salmon] : [.chicken])
                if let p = g.mobs.mobs.first(where: { prey.contains($0.kind) && !$0.baby && $0.health > 0 && simd_length($0.pos - pos) < 12 }), Float.random(in: 0..<1) < 0.5 {
                    face(p.pos)
                    if simd_length(p.pos - pos) < halfW + p.halfW + 0.8 && attackCooldown <= 0 { attackCooldown = 1; p.hit(from: pos, damage: max(2, spec.attack), knockback: 0.4) }
                    return spec.speed * 1.2
                }
            }
            // Goats ram at a random time.
            if kind == .goat && canTarget && dist < 10 && Float.random(in: 0..<1) < dt / 30 { aggro = true }
        }
        // Follow a player holding the right food; fall in love when fed (handled in useItemOnMob).
        if let food = MobKind.animalFood[kind], dist < 8, food.contains(Items.key(g.held.item)), !baby {
            face(player); moving = dist > 2
            return dist > 2 ? spec.speed * 0.8 : 0
        }
        if inLove > 0, let mate = g.mobs.mobs.first(where: { $0 !== self && breedsWith($0) && $0.inLove > 0 && simd_length($0.pos - pos) < 8 }) {
            face(mate.pos)
            return simd_length(mate.pos - pos) > halfW + 1 ? spec.speed : 0
        }
        if home == nil && kind == .turtle { home = pos }            // home beach: where it first appeared
        if layEgg(g) { return spec.speed * 0.8 }
        // Rabbits hop; frogs hop and eat small slimes; armadillos roll up near danger.
        switch kind {
        case .rabbit:
            if onGround && moving && aiTimer.truncatingRemainder(dividingBy: 0.6) < dt { vel.y = 5 }
        case .frog:
            if let s = g.mobs.mobs.first(where: { ($0.kind == .slime || $0.kind == .magmaCube) && $0.slimeSize == 1 && simd_length($0.pos - pos) < 5 }) {
                face(s.pos)
                if simd_length(s.pos - pos) < 3 {
                    s.health = -2000
                    let light = s.kind == .magmaCube ? ["ochre_froglight", "verdant_froglight", "pearlescent_froglight"][variant % 3] : "slime_ball"
                    if Items.has(light) { g.drops.spawn(ItemStack(Items.id(light), 1), at: s.pos) }
                }
            }
            if onGround && moving && Float.random(in: 0..<1) < dt * 1.5 { vel.y = 6 }
        case .armadillo:
            let danger = g.mobs.mobs.contains { $0.kind.hostile && simd_length($0.pos - pos) < 7 } || (g.player.sprinting && dist < 7) || panic > 0
            sitting = danger              // rolled up
            if danger { return 0 }
            scuteTimer -= dt
            if scuteTimer <= 0 { scuteTimer = Float.random(in: 300...600); if Items.has("armadillo_scute") { g.drops.spawn(ItemStack(Items.id("armadillo_scute"), 1), at: pos) } }
        case .turtle:
            // Babies drop a scute when they grow up (handled in growUp); adults head home to lay eggs.
            break
        case .sniffer:
            // Digs up ancient seeds on grass / dirt / moss.
            scuteTimer -= dt
            if scuteTimer <= 0 && onGround {
                scuteTimer = Float.random(in: 120...240)
                let under = Blocks.key(w.block(Int(floor(pos.x)), Int(floor(pos.y - 0.5)), Int(floor(pos.z))))
                if ["grass_block", "dirt", "podzol", "coarse_dirt", "rooted_dirt", "moss_block", "mud", "muddy_mangrove_roots"].contains(under) {
                    let seed = Bool.random() ? "torchflower_seeds" : "pitcher_pod"
                    if Items.has(seed) { g.drops.spawn(ItemStack(Items.id(seed), 1), at: pos + forward * 1.2) }
                }
            }
        case .bat:
            // Erratic flight; hangs from ceilings by day.
            if aiTimer <= 0 || flyTarget == nil { aiTimer = Float.random(in: 0.5...2); flyTarget = pos + V3(Float.random(in: -5...5), Float.random(in: -2...3), Float.random(in: -5...5)) }
            if let f = flyTarget { let d = f - pos; vel += (d * 0.8 - vel) * min(1, dt * 3) }
            return 0
        case .parrot:
            if aiTimer <= 0 || flyTarget == nil {
                aiTimer = Float.random(in: 2...5)
                let base = tamed ? player : pos
                flyTarget = base + V3(Float.random(in: -4...4), Float.random(in: 0...3), Float.random(in: -4...4))
            }
            if let f = flyTarget { let d = f - pos; vel += (d * 0.6 - vel) * min(1, dt * 2); vel.y -= 2 * dt }
            return 0
        case .bee:
            return beeAI(dt, g)
        case .allay where g.jukeboxes.contains(where: { simd_length(V3(Float($0.pos.x) + 0.5, Float($0.pos.y), Float($0.pos.z) + 0.5) - pos) < 10 }):
            // Dancing to a jukebox within 10 blocks (an amethyst shard now duplicates it).
            sitting = true
            vel *= expf(-3 * dt)
            walkPhase += dt * 6
            return 0
        case .allay:
            sitting = false
            // Follows the player who gave it an item and collects matching drops.
            if tamed {
                let want = heldItem
                if let it = g.drops.items.first(where: { !$0.stack.isEmpty && $0.stack.item == want && simd_length($0.pos - pos) < 32 }) {
                    let d = it.pos - pos
                    vel += (d / max(0.1, simd_length(d)) * 5 - vel) * min(1, dt * 2)
                    if simd_length(d) < 1 { carried += it.stack.count; it.stack = .empty }
                } else if carried > 0 && dist > 2 {
                    let d = g.player.eye - pos
                    vel += (d / max(0.1, simd_length(d)) * 5 - vel) * min(1, dt * 2)
                } else if carried > 0 {
                    g.drops.spawn(ItemStack(want, carried), at: pos)
                    carried = 0
                } else {
                    let d = g.player.eye + V3(0, 1, 0) - pos
                    vel += (d * 0.5 - vel) * min(1, dt * 2)
                }
            } else {
                if aiTimer <= 0 || flyTarget == nil { aiTimer = 3; flyTarget = pos + V3(Float.random(in: -4...4), Float.random(in: -1...2), Float.random(in: -4...4)) }
                if let f = flyTarget { let d = f - pos; vel += (d * 0.4 - vel) * min(1, dt * 2) }
            }
            return 0
        case .happyGhast:
            return cloudwailerAI(dt, g)
        case .traderLlama:
            // Follows its wandering trader and leaves with it.
            if let t = target {
                if t.health <= 0 { health = -2000; return 0 }
                if simd_length(t.pos - pos) > 4 { face(t.pos); moving = true; return spec.speed }
            }
        case .wanderingTrader:
            // Leaves after 40-60 minutes (despawn timer); drinks invisibility at night.
            age += dt
            if age > 2400 { health = -2000 }
        default: break
        }
        if panic <= 0 && followParent(g) { return spec.speed * 0.8 }
        wander()
        let base = spec.speed * (panic > 0 ? 1.8 : 0.6)
        return moving ? base : 0
    }

    func breedsWith(_ o: Mob) -> Bool {
        if o.kind == kind { return true }
        let equine: Set<MobKind> = [.horse, .donkey]
        return equine.contains(kind) && equine.contains(o.kind)
    }

    // Swimming mobs: stay in water, school, flop on land.
    func updateAquatic(_ dt: Float, _ g: Game, inWater: Bool) {
        let w = g.world
        if !inWater && kind != .axolotl && kind != .turtle {
            // Out of water: flop and suffocate (dolphins last longer).
            airTime += dt
            if airTime > (kind == .dolphin ? 120 : 15) { fireTick += dt; if fireTick > 1 { fireTick = 0; health -= 1; hurt = 0.2 } }
            vel.y -= 28 * dt
            if onGround && Float.random(in: 0..<1) < dt * 3 { vel = V3(Float.random(in: -2...2), 5, Float.random(in: -2...2)) }
        } else {
            airTime = 0
            // Swim target inside water.
            if aiTimer <= 0 || flyTarget == nil {
                aiTimer = Float.random(in: 1...4)
                var t = pos + V3(Float.random(in: -6...6), Float.random(in: -2...2), Float.random(in: -6...6))
                // Schooling fish follow a nearby member of their kind.
                if kind == .cod || kind == .salmon || kind == .tropicalFish,
                   let leader = g.mobs.mobs.first(where: { $0 !== self && $0.kind == kind && simd_length($0.pos - pos) < 8 }) {
                    t = leader.pos + V3(Float.random(in: -1.5...1.5), Float.random(in: -1...1), Float.random(in: -1.5...1.5))
                }
                if Blocks.fluidKind[Int(w.block(Int(floor(t.x)), Int(floor(t.y)), Int(floor(t.z))))] == 1 { flyTarget = t }
            }
            let player = g.player.pos
            let dist = simd_length(player - pos)
            // Spikefishs: charge a laser at the player for 2 s, then hit (6); thorns on melee.
            if spec.behavior == .monster && g.survival && g.alive && dist < 16 && w.canSee(eye, g.player.eye) {
                face(player)
                beam += dt
                if beam >= (kind == .elderGuardian ? 3 : 2) {
                    beam = 0
                    g.hurtPlayer(kind == .elderGuardian ? 8 : 6, from: pos, cause: "was killed by magic", knockback: 0, type: .magic)
                }
                flyTarget = pos
            } else { beam = 0 }
            if kind == .elderGuardian && dist < 50 && g.survival && Float.random(in: 0..<1) < dt / 60 {
                g.applyEffect(.miningFatigue, amp: 2, seconds: 300)
                g.sfx(.mobRavager, 0.8)
            }
            // Dolphins circle players and give Dolphin's Grace; pufferfish puff up and poison.
            // Leading the way to treasure: swim ahead toward it, staying below the surface.
            if kind == .dolphin && phaseTime > 0, let h = home {
                phaseTime -= dt
                var t = h - pos
                t.y = min(0, max(-2, t.y))
                if simd_length(t) > 1 { flyTarget = pos + simd_normalize(t) * 6 }
            } else if kind == .dolphin && dist < 8 && g.player.inWater { flyTarget = player + V3(Float.random(in: -2...2), 0, Float.random(in: -2...2)); g.applyEffect(.dolphinsGrace, amp: 0, seconds: 5) }
            if kind == .pufferfish {
                sitting = dist < 3
                if sitting && dist < 1.2 && attackCooldown <= 0 && g.survival { attackCooldown = 1; g.hurtPlayer(2, from: pos, cause: "was stung to death", knockback: 0.2); g.applyEffect(.poison, amp: 0, seconds: 6) }
            }
            // Axolotls play dead for 10 s when hurt (1 in 3), regenerating; nothing hunts them meanwhile.
            if kind == .axolotl && wasHit && health > 0 && Int.random(in: 0..<3) == 0 {
                sitting = true; phaseTime = 10
                applyEffect(.regeneration, amp: 0, seconds: 10, game: g)
            }
            if kind == .axolotl && sitting {
                phaseTime -= dt
                if phaseTime <= 0 { sitting = false }
                vel *= expf(-3 * dt)
                attackCooldown -= dt
                aiTimer -= dt
                wasHit = false
                let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0, onGround: onGround)
                if hit.y { vel.y = 0 }
                return
            }
            if kind == .axolotl { wasHit = false }
            if kind == .axolotl, let prey = g.mobs.mobs.first(where: { [.cod, .salmon, .tropicalFish, .pufferfish, .squid, .glowSquid, .drowned, .guardian].contains($0.kind) && simd_length($0.pos - pos) < 8 }) {
                flyTarget = prey.pos
                if simd_length(prey.pos - pos) < 1.2 && attackCooldown <= 0 { attackCooldown = 1; prey.hit(from: pos, damage: 2, knockback: 0.3) }
            }
            if panic > 0, flyTarget == nil || aiTimer > 0.5 { flyTarget = pos + simd_normalize(pos - player + V3(0.01, 0, 0)) * 6 }
            if let t = flyTarget {
                let d = t - pos
                let l = simd_length(d)
                if l > 0.3 { vel += (d / l * spec.speed * (panic > 0 ? 1.8 : 1) - vel) * min(1, dt * 2); face(t) } else { vel *= expf(-2 * dt) }
            }
            // Squid squirt ink when hurt.
            if (kind == .squid || kind == .glowSquid) && hurt > 0.35 { for _ in 0..<6 { g.particles.smoke(at: pos + V3(0, 0.4, 0)) } }
            aiTimer -= dt
            attackCooldown -= dt
        }
        let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0, onGround: onGround)
        if hit.x { vel.x = 0; flyTarget = nil }
        if hit.z { vel.z = 0; flyTarget = nil }
        if hit.y { if vel.y < 0 { onGround = true }; vel.y = 0 } else { onGround = false }
        // Keep swimmers under the surface.
        if inWater && Blocks.fluidKind[Int(w.block(Int(floor(pos.x)), Int(floor(pos.y + height + 0.2)), Int(floor(pos.z))))] != 1 { vel.y = min(vel.y, -0.5) }
        walkPhase += (simd_length(vel) + 0.5) * dt * 4
        walkAmount = 1
    }

    // Remaining monsters: nightwings swoop, voidmites chase, deep stalkers smell/hear, gustlings jump and shoot
    // wind charges.
    func monsterAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool, inWater: Bool) -> Float {
        let player = g.player.pos
        switch kind {
        case .phantom:
            // Circle high, then swoop through the player.
            circleAngle += dt * 0.8
            if canTarget && dist < 64 {
                if phase == 0 {
                    let c = player + V3(cosf(circleAngle) * 10, 14 + sinf(circleAngle * 2) * 2, sinf(circleAngle) * 10)
                    vel += (simd_normalize(c - pos) * spec.speed - vel) * min(1, dt * 2)
                    if Float.random(in: 0..<1) < dt / 6 { phase = 1 }
                } else {
                    let d = g.player.eye - pos
                    vel += (simd_normalize(d) * spec.speed * 1.4 - vel) * min(1, dt * 3)
                    if simd_length(d) < 1.2 {
                        if attackCooldown <= 0 { attackCooldown = 1; g.hurtPlayer(spec.attack, from: pos, cause: "was slain by Nightwing", attacker: self) }
                        phase = 0
                    }
                    if simd_length(d) > 40 { phase = 0 }
                }
                face(pos + vel)
            } else {
                vel += (V3(cosf(circleAngle), 0, sinf(circleAngle)) * spec.speed * 0.6 - vel) * min(1, dt)
            }
            // Cats scare nightwings.
            if g.mobs.mobs.contains(where: { $0.kind == .cat && simd_length($0.pos - pos) < 16 }) { phase = 0; vel.y += 4 * dt }
            return 0
        case .creaking:
            return barkwraithAI(dt, g, dist: dist, canTarget: canTarget)
        case .endermite:
            if canTarget {
                face(player)
                if dist < 1 && attackCooldown <= 0 { attackCooldown = 1; g.hurtPlayer(spec.attack, from: pos, cause: "was slain by Voidmite", attacker: self) }
                return spec.speed
            }
            age += dt
            if age > 120 { health = -2000 }
            wander(); return moving ? spec.speed * 0.5 : 0
        case .warden:
            // Blind: tracks the player by vibrations (moving, not sneaking) and anger; melee 30, sonic boom 10 at range.
            let noisy = g.survival && g.alive && dist < 16 && (!g.player.sneaking && simd_length(g.player.vel) > 0.5)
            if noisy { anger = min(150, anger + dt * 35) } else { anger = max(0, anger - dt * 2) }
            if dist < 20 && g.survival && Float.random(in: 0..<1) < dt / 6 { g.applyEffect(.darkness, amp: 0, seconds: 12) }
            if anger >= 80 && canTarget {
                face(player)
                attackCooldown -= 0
                if dist < 2.4 && attackCooldown <= 0 {
                    attackCooldown = 1.8
                    g.hurtPlayer(spec.attack, from: pos, cause: "was obliterated by a sonically-charged shriek", knockback: 1.5, attacker: self)
                } else if dist < 15 && dist > 4 && spellTimer <= 0 {
                    spellTimer = 5
                    g.hurtPlayer(10, from: pos, cause: "was obliterated by a sonically-charged shriek", knockback: 2.5, type: .void)
                    g.sfx(.mobWarden, 1.4, at: pos)
                }
                spellTimer -= dt
                return spec.speed * 1.2
            }
            // Digs back down after a minute without anything to track.
            if anger <= 0 { age += dt; if age > 60 { health = -2000 } } else { age = 0 }
            wander(); return moving ? spec.speed * 0.4 : 0
        case .breeze:
            // Hops around and fires wind charges (1 damage + big knockback).
            if canTarget && dist < 16 {
                face(player)
                if onGround && Float.random(in: 0..<1) < dt * 0.8 { vel = simd_normalize(V3(Float.random(in: -1...1), 0, Float.random(in: -1...1))) * 4 + V3(0, 9, 0) }
                attackCooldown -= 0
                if attackCooldown <= 0 {
                    attackCooldown = 2.5
                    if dist < 16 && g.world.canSee(eye, g.player.eye) {
                        g.hurtPlayer(1, from: pos, cause: "was blown away by a Gustling", knockback: 0, type: .projectile)
                        g.player.vel += simd_normalize(g.player.pos - pos + V3(0, 1, 0)) * 12
                        g.sfx(.fireball, 0.5, at: pos)
                    }
                }
                return 0
            }
            wander(); return moving ? spec.speed * 0.4 : 0
        default:
            wander(); return moving ? spec.speed * 0.5 : 0
        }
    }
}

// MARK: Models

func animalParts(_ m: Mob, swing: Float) -> [Part] {
    func leg(_ x: Float, _ z: Float, _ w: Float, _ h: Float, _ ph: Float, _ c: V3, _ pat: Float = 4) -> Part {
        Part(mn: V3(x - w / 2, 0, z - w / 2), mx: V3(x + w / 2, h, z + w / 2), pivot: V3(x, h, z), rotX: swing * ph, color: c, pattern: pat)
    }
    func eyes(_ y: Float, _ z: Float, _ sep: Float, _ size: Float = 1, _ c: V3 = V3(0.06, 0.06, 0.06)) -> [Part] {
        [box(-sep - size, y, z - 0.2, size, size, 0.2, c), box(sep, y, z - 0.2, size, size, 0.2, c)]
    }
    func quadruped(_ body: V3, _ size: V3, legH: Float, head: V3, headSize: V3, _ c: V3, _ hc: V3? = nil, legW: Float = 3) -> [Part] {
        let bw = size.x, bh = size.y, bd = size.z
        var p: [Part] = [box(-bw / 2, legH, -bd / 2, bw, bh, bd, c, 4)]
        p.append(Part(mn: head - V3(headSize.x / 2, 0, headSize.z), mx: head + V3(headSize.x / 2, headSize.y, 0), pivot: head, color: hc ?? c, pattern: 4))
        let lx = bw / 2 - legW / 2, lz = bd / 2 - legW / 2
        p += [leg(-lx, -lz, legW, legH, 1, c), leg(lx, -lz, legW, legH, -1, c), leg(-lx, lz, legW, legH, -1, c), leg(lx, lz, legW, legH, 1, c)]
        p += eyes(head.y + headSize.y * 0.6, head.z - headSize.z, headSize.x * 0.2)
        _ = body
        return p
    }
    switch m.kind {
    case .rabbit:
        let c = [V3(0.55, 0.42, 0.3), V3(0.9, 0.9, 0.88), V3(0.2, 0.18, 0.16), V3(0.8, 0.7, 0.5)][m.variant % 4]
        return [box(-2.5, 1, -3, 5, 5, 7, c, 4), box(-2, 4, -6, 4, 4, 4, c, 4), box(-1.5, 8, -4.5, 1, 4, 1, c), box(0.5, 8, -4.5, 1, 4, 1, c),
                leg(-1.5, 3, 1.5, 2, 1, c), leg(1.5, 3, 1.5, 2, -1, c), box(-0.5, 3, 3.5, 1, 1, 1, V3(0.95, 0.95, 0.95))] + eyes(6, -6, 0.8, 0.8)
    case .fox:
        let c = m.variant == 1 ? V3(0.95, 0.95, 0.95) : V3(0.9, 0.5, 0.2)
        var p = quadruped(.zero, V3(6, 6, 11), legH: 5, head: V3(0, 7, -5.5), headSize: V3(7, 6, 5), c)
        p.append(box(-1, 8, -12, 2, 2, 2, V3(0.95, 0.95, 0.95)))                                   // snout
        p.append(box(-3, 13, -8, 2, 2, 1, c)); p.append(box(1, 13, -8, 2, 2, 1, c))                 // ears
        p.append(Part(mn: V3(-2, 7, 5), mx: V3(2, 11, 14), pivot: V3(0, 9, 5), rotX: -0.3, color: c, pattern: 4))
        return p
    case .wolf:
        let base = Mob.wolfColors[m.variant % Mob.wolfColors.count]
        let c = m.aggro && !m.tamed ? base * 0.72 : base
        var p = quadruped(.zero, V3(6, 6, 10), legH: 8, head: V3(0, 9, -5), headSize: V3(6, 6, 4), c)
        p.append(box(-1.5, 9.5, -12, 3, 3, 3, c * 0.9))
        p.append(box(-3, 15, -7, 2, 2, 1, c)); p.append(box(1, 15, -7, 2, 2, 1, c))
        p.append(Part(mn: V3(-1, 10, 5), mx: V3(1, 12, 13), pivot: V3(0, 11, 5), rotX: m.tamed ? -0.6 : 0.4, color: c))
        if m.tamed { p.append(box(-3.2, 9, -5.5, 6.4, 1.2, 1, TextureGen.hex(BlockRegistry.colorHex[BlockRegistry.colors[m.collar % 16].0] ?? 0xA12722).rgb3)) }
        if m.armorTier == 5 { p.append(box(-3.4, 7.6, -5.4, 6.8, 6.8, 9, V3(0.62, 0.42, 0.36))) }
        if m.sitting { for i in 0..<p.count { p[i].mn.y -= 3; p[i].mx.y -= 3 } }
        return p
    case .cat, .ocelot:
        let c = m.kind == .ocelot ? V3(0.85, 0.72, 0.4) : [V3(0.2, 0.2, 0.22), V3(0.9, 0.6, 0.3), V3(0.55, 0.5, 0.45), V3(0.95, 0.95, 0.95)][m.variant % 4]
        var p = quadruped(.zero, V3(4, 5, 12), legH: 5, head: V3(0, 7, -6), headSize: V3(5, 4, 5), c, legW: 2)
        p.append(box(-2, 11, -9, 1.5, 1.5, 1, c)); p.append(box(0.5, 11, -9, 1.5, 1.5, 1, c))
        p.append(Part(mn: V3(-0.5, 8, 6), mx: V3(0.5, 9, 14), pivot: V3(0, 8.5, 6), rotX: -0.5, color: c))
        return p
    case .horse, .donkey, .mule, .skeletonHorse, .zombieHorse:
        let c = m.kind == .zombieHorse ? V3(0.33, 0.5, 0.3) : m.kind == .skeletonHorse ? V3(0.85, 0.85, 0.82) : (m.kind == .donkey ? V3(0.5, 0.45, 0.4) : (m.kind == .mule ? V3(0.35, 0.25, 0.18)
                : [V3(0.55, 0.36, 0.2), V3(0.9, 0.88, 0.82), V3(0.25, 0.18, 0.12), V3(0.62, 0.5, 0.36), V3(0.15, 0.15, 0.15)][m.variant % 5]))
        var p = quadruped(.zero, V3(10, 10, 22), legH: 12, head: V3(0, 20, -11), headSize: V3(5, 5, 11), c, legW: 4)
        p.append(Part(mn: V3(-3, 14, -13), mx: V3(3, 24, -7), pivot: V3(0, 16, -9), rotX: 0.5, color: c, pattern: 4))      // neck
        if m.kind == .donkey || m.kind == .mule { p.append(box(-3, 25, -9, 1.5, 5, 1, c)); p.append(box(1.5, 25, -9, 1.5, 5, 1, c)) }
        p.append(Part(mn: V3(-1.5, 16, 11), mx: V3(1.5, 20, 19), pivot: V3(0, 20, 11), rotX: 0.8, color: c * 0.7))              // tail
        if m.saddled { p.append(box(-5.2, 21.8, -4, 10.4, 1.5, 9, V3(0.35, 0.2, 0.1))) }
        if m.chested { p.append(box(-7, 14, 0, 2, 7, 7, V3(0.55, 0.38, 0.2))); p.append(box(5, 14, 0, 2, 7, 7, V3(0.55, 0.38, 0.2))) }
        if m.armorTier > 0 {
            let ac = [V3(0.55, 0.35, 0.2), V3(0.86, 0.86, 0.86), V3(0.95, 0.82, 0.25), V3(0.3, 0.88, 0.84)][min(3, m.armorTier - 1)]
            p.append(box(-5.4, 11.6, -10, 10.8, 10.2, 16, ac))
            p.append(Part(mn: V3(-3.4, 14, -13.4), mx: V3(3.4, 24.4, -6.6), pivot: V3(0, 16, -9), rotX: 0.5, color: ac))
        }
        return p
    case .llama, .traderLlama:
        let c = m.kind == .traderLlama ? V3(0.85, 0.8, 0.7) : [V3(0.85, 0.8, 0.7), V3(0.95, 0.95, 0.93), V3(0.5, 0.35, 0.25), V3(0.55, 0.52, 0.5)][m.variant % 4]
        var p = quadruped(.zero, V3(10, 10, 16), legH: 13, head: V3(0, 26, -9), headSize: V3(6, 5, 7), c, legW: 4)
        p.append(box(-2.5, 17, -10, 5, 10, 4, c, 4))
        p.append(box(-2.5, 31, -6, 1.5, 3, 1, c)); p.append(box(1, 31, -6, 1.5, 3, 1, c))
        if m.chested { p.append(box(-7, 14, 0, 2, 7, 7, V3(0.55, 0.38, 0.2))); p.append(box(5, 14, 0, 2, 7, 7, V3(0.55, 0.38, 0.2))) }
        if m.kind == .traderLlama { p.append(box(-5.2, 23, -8, 10.4, 1, 16, V3(0.2, 0.3, 0.7))) }
        return p
    case .camel:
        let c = V3(0.85, 0.68, 0.42)
        var p = quadruped(.zero, V3(14, 12, 26), legH: 20, head: V3(0, 34, -17), headSize: V3(6, 6, 10), c, legW: 4)
        p.append(box(-4, 32, -4, 8, 7, 10, c, 4))                          // hump
        p.append(box(-3, 24, -16, 6, 12, 5, c, 4))                          // neck
        if m.saddled { p.append(box(-6, 38.5, -3, 12, 1.5, 10, V3(0.35, 0.2, 0.1))) }
        return p
    case .goat:
        let c = V3(0.92, 0.9, 0.85)
        var p = quadruped(.zero, V3(8, 9, 14), legH: 10, head: V3(0, 16, -7), headSize: V3(5, 6, 6), c)
        p.append(box(-3, 22, -8, 1.5, 5, 1.5, V3(0.6, 0.55, 0.45))); p.append(box(1.5, 22, -8, 1.5, 5, 1.5, V3(0.6, 0.55, 0.45)))
        p.append(box(-1, 14, -13.5, 2, 3, 1, c))                           // beard
        return p
    case .panda:
        let brown = m.pandaPersonality == 4
        let w = brown ? V3(0.72, 0.58, 0.45) : V3(0.95, 0.95, 0.93), b = brown ? V3(0.35, 0.22, 0.14) : V3(0.12, 0.12, 0.12)
        var p = quadruped(.zero, V3(13, 12, 20), legH: 8, head: V3(0, 12, -10), headSize: V3(12, 10, 8), w, legW: 5)
        for i in 0..<4 { p[2 + i].color = b }
        p.append(box(-5, 16, -18.3, 3, 3, 0.3, b)); p.append(box(2, 16, -18.3, 3, 3, 0.3, b))
        p.append(box(-6, 21, -13, 3, 3, 2, b)); p.append(box(3, 21, -13, 3, 3, 2, b))
        return p
    case .polarBear:
        let c = V3(0.95, 0.95, 0.92)
        var p = quadruped(.zero, V3(14, 14, 22), legH: 10, head: V3(0, 14, -11), headSize: V3(8, 7, 7), c, legW: 5)
        p.append(box(-2, 14, -21, 4, 3, 3, c * 0.9))
        return p
    case .turtle:
        let shell = V3(0.25, 0.4, 0.2), skin = V3(0.45, 0.65, 0.35)
        return [box(-9, 2, -10, 18, 5, 20, shell, 4), box(-3, 1, -14, 6, 4, 5, skin, 4),
                leg(-7, -8, 3, 2, 1, skin), leg(7, -8, 3, 2, -1, skin), leg(-6, 8, 3, 2, -1, skin), leg(6, 8, 3, 2, 1, skin)] + eyes(3.5, -14, 1.2, 1)
    case .frog:
        let c = [V3(0.8, 0.5, 0.25), V3(0.45, 0.6, 0.35), V3(0.85, 0.85, 0.8)][m.variant % 3]
        return [box(-3.5, 2, -4.5, 7, 3, 9, c, 4), box(-3.5, 5, -4.5, 7, 2, 6, c, 4), box(-3.5, 7, -4, 2, 2, 2, c), box(1.5, 7, -4, 2, 2, 2, c),
                box(-3, 7.5, -4.2, 1, 1, 0.3, V3(0.06, 0.06, 0.06)), box(2, 7.5, -4.2, 1, 1, 0.3, V3(0.06, 0.06, 0.06)),
                leg(-3, 3, 2, 2, 1, c), leg(3, 3, 2, 2, -1, c), leg(-3, -3, 1.5, 2, -1, c), leg(3, -3, 1.5, 2, 1, c)]
    case .tadpole:
        return [box(-1.5, 0, -1.5, 3, 2, 3, V3(0.35, 0.28, 0.2)), Part(mn: V3(-0.2, 0.5, 1.5), mx: V3(0.2, 1.5, 5), pivot: V3(0, 1, 1.5), rotX: 0, rotZ: 0, color: V3(0.35, 0.28, 0.2))]
    case .armadillo:
        let c = V3(0.65, 0.42, 0.38)
        if m.sitting { return [box(-4, 0, -4, 8, 8, 8, c, 4)] }
        return [box(-4, 3, -5, 8, 6, 10, c, 4), box(-2, 3, -8, 4, 4, 3, V3(0.8, 0.55, 0.5)), box(-2.5, 7, -7, 1, 3, 1, c), box(1.5, 7, -7, 1, 3, 1, c),
                leg(-3, -3, 2, 3, 1, V3(0.5, 0.35, 0.3)), leg(3, -3, 2, 3, -1, V3(0.5, 0.35, 0.3)), leg(-3, 3, 2, 3, -1, V3(0.5, 0.35, 0.3)), leg(3, 3, 2, 3, 1, V3(0.5, 0.35, 0.3))] + eyes(5, -8, 1, 0.8)
    case .sniffer:
        let c = V3(0.55, 0.25, 0.2), moss = V3(0.35, 0.55, 0.25)
        var p = quadruped(.zero, V3(24, 16, 32), legH: 10, head: V3(0, 14, -16), headSize: V3(12, 10, 10), c, legW: 6)
        p.append(box(-12.2, 22, -16.2, 24.4, 4, 32.4, moss, 4))
        p.append(box(-4, 12, -28, 8, 5, 3, V3(0.35, 0.6, 0.3)))
        return p
    case .mooshroom:
        let c = m.variant == 1 ? V3(0.55, 0.42, 0.3) : V3(0.72, 0.15, 0.12)
        var p = quadruped(.zero, V3(12, 10, 18), legH: 12, head: V3(0, 16, -9), headSize: V3(8, 8, 6), c)
        p.append(box(-3, 22, 2, 3, 3, 3, V3(0.9, 0.2, 0.15))); p.append(box(1, 22, -4, 3, 3, 3, V3(0.9, 0.2, 0.15)))
        return p
    case .bee:
        let y = V3(0.95, 0.75, 0.2), b = V3(0.15, 0.1, 0.08)
        let flap = sinf(m.walkPhase * 4) * 0.8
        return [box(-3.5, 2, -5, 7, 7, 10, y, 4), box(-3.6, 2, -1, 7.2, 7.2, 1.5, b), box(-3.6, 2, 2.5, 7.2, 7.2, 1.5, b),
                box(-1.5, 9, -6, 1, 3, 1, b), box(0.5, 9, -6, 1, 3, 1, b),
                Part(mn: V3(-7, 9, -2), mx: V3(-1, 9.3, 3), pivot: V3(-1, 9, 0), rotZ: flap, color: V3(0.85, 0.9, 0.95)),
                Part(mn: V3(1, 9, -2), mx: V3(7, 9.3, 3), pivot: V3(1, 9, 0), rotZ: -flap, color: V3(0.85, 0.9, 0.95))] + eyes(5, -5, 1.5, 1.5)
    case .parrot:
        let c = [V3(0.9, 0.15, 0.1), V3(0.2, 0.4, 0.9), V3(0.3, 0.8, 0.2), V3(0.3, 0.8, 0.9), V3(0.6, 0.6, 0.6)][m.variant % 5]
        let flap: Float = m.onGround ? 0 : sinf(m.walkPhase * 5) * 0.9
        return [box(-1.5, 4, -2, 3, 6, 3, c, 3), box(-1.5, 10, -3, 3, 3, 3, c, 3), box(-0.5, 10.5, -4.5, 1, 2, 1.5, V3(0.25, 0.25, 0.25)),
                Part(mn: V3(-2.5, 5, -1.5), mx: V3(-1.5, 10, 1.5), pivot: V3(-1.5, 10, 0), rotZ: -flap, color: c, pattern: 3),
                Part(mn: V3(1.5, 5, -1.5), mx: V3(2.5, 10, 1.5), pivot: V3(1.5, 10, 0), rotZ: flap, color: c, pattern: 3),
                box(-1, 1, 1, 2, 3, 1, c * 0.8), leg(-0.8, 0, 0.6, 4, 0, V3(0.4, 0.4, 0.4)), leg(0.8, 0, 0.6, 4, 0, V3(0.4, 0.4, 0.4))] + eyes(11.5, -3, 1, 0.7)
    case .bat:
        let c = V3(0.3, 0.22, 0.16)
        let flap = sinf(m.walkPhase * 6) * 1.1
        return [box(-1.5, 3, -1.5, 3, 5, 3, c, 4), box(-1.5, 8, -1.5, 3, 3, 3, c, 4),
                Part(mn: V3(-8, 5, -0.2), mx: V3(-1.5, 10, 0.2), pivot: V3(-1.5, 8, 0), rotZ: flap, color: c * 0.8),
                Part(mn: V3(1.5, 5, -0.2), mx: V3(8, 10, 0.2), pivot: V3(1.5, 8, 0), rotZ: -flap, color: c * 0.8)]
    case .allay:
        let c = V3(0.35, 0.85, 0.95)
        let flap = sinf(m.walkPhase * 4) * 0.7
        return [box(-1.5, 3, -1, 3, 4, 2, c, 4), box(-2.5, 7, -2.5, 5, 5, 5, c * 1.1, 4),
                Part(mn: V3(-6, 4, 1), mx: V3(-1, 9, 1.3), pivot: V3(-1, 7, 1), rotZ: flap, color: V3(0.8, 0.95, 1)),
                Part(mn: V3(1, 4, 1), mx: V3(6, 9, 1.3), pivot: V3(1, 7, 1), rotZ: -flap, color: V3(0.8, 0.95, 1))] + eyes(9, -2.5, 0.8, 1, V3(0.1, 0.2, 0.3))
    case .axolotl:
        let c = [V3(0.95, 0.6, 0.7), V3(0.55, 0.35, 0.25), V3(0.95, 0.85, 0.3), V3(0.85, 0.85, 0.9), V3(0.3, 0.35, 0.8)][m.variant % 5]
        return [box(-2, 1, -4, 4, 3, 8, c, 4), box(-2.5, 1, -8, 5, 3, 4, c, 4), box(-4, 3, -7, 1.5, 3, 1, c * 0.8), box(2.5, 3, -7, 1.5, 3, 1, c * 0.8),
                Part(mn: V3(-0.2, 1.5, 4), mx: V3(0.2, 3.5, 11), pivot: V3(0, 2.5, 4), rotX: sinf(m.walkPhase) * 0.3, color: c),
                leg(-2, -2, 1, 1, 1, c), leg(2, -2, 1, 1, -1, c), leg(-2, 2, 1, 1, -1, c), leg(2, 2, 1, 1, 1, c)] + eyes(3, -8, 1.3, 0.7)
    case .squid, .glowSquid:
        let c = m.kind == .glowSquid ? V3(0.2, 0.75, 0.7) : V3(0.2, 0.3, 0.45)
        var p = [box(-6, 6, -6, 12, 16, 12, c, 4)]
        for i in 0..<8 {
            let a = Float(i) * .pi / 4
            let x = cosf(a) * 4.5, z = sinf(a) * 4.5
            p.append(Part(mn: V3(x - 1, -12, z - 1), mx: V3(x + 1, 6, z + 1), pivot: V3(x, 6, z), rotX: sinf(m.walkPhase + Float(i)) * 0.3, color: c * 0.9))
        }
        return p + eyes(14, -6, 2.5, 1.5)
    case .dolphin:
        let c = V3(0.45, 0.55, 0.65)
        return [box(-4, 0, -6, 8, 7, 13, c, 4), box(-3.5, 0.5, -11, 7, 6, 5, c, 4), box(-1, 1, -15, 2, 2, 4, c * 0.9), box(-0.5, 7, -2, 1, 5, 4, c),
                Part(mn: V3(-5, 1, 7), mx: V3(5, 2, 12), pivot: V3(0, 1.5, 7), rotX: sinf(m.walkPhase) * 0.3, color: c)] + eyes(4, -11, 1.5, 0.8)
    case .cod, .salmon, .tropicalFish, .pufferfish:
        let c: V3 = m.kind == .cod ? V3(0.7, 0.62, 0.5) : (m.kind == .salmon ? V3(0.65, 0.3, 0.28) : (m.kind == .pufferfish ? V3(0.9, 0.75, 0.25)
                : [V3(0.95, 0.5, 0.15), V3(0.3, 0.5, 0.95), V3(0.95, 0.9, 0.3), V3(0.9, 0.3, 0.6)][m.variant % 4]))
        if m.kind == .pufferfish {
            let s: Float = m.sitting ? 8 : 4
            return [box(-s / 2, 0, -s / 2, s, s, s, c, 4)] + eyes(s * 0.6, -s / 2, s * 0.15, 0.8)
        }
        let l: Float = m.kind == .salmon ? 11 : 8
        let tail = sinf(m.walkPhase * 3) * 0.6
        return [box(-1, 0, -l / 2, 2, 4, l, c, 4),
                Part(mn: V3(-0.2, 0, l / 2), mx: V3(0.2, 4, l / 2 + 3), pivot: V3(0, 2, l / 2), rotX: 0, rotZ: 0, color: c * 0.8),
                box(-0.2, 4, -1, 0.4, 1.5, 3, c * 0.8)] + eyes(2.5, -l / 2, 0.9, 0.6) + [Part(mn: V3(0, 0, 0), mx: V3(0, 0, 0), pivot: .zero, rotX: tail, color: c)]
    case .wanderingTrader:
        let robe = V3(0.2, 0.3, 0.6), skin = V3(0.72, 0.52, 0.42)
        return [
            Part(mn: V3(-4, 0, -3), mx: V3(-0.01, 12, 3), pivot: V3(-2, 12, 0), rotX: swing, color: robe, pattern: 4),
            Part(mn: V3(0.01, 0, -3), mx: V3(4, 12, 3), pivot: V3(2, 12, 0), rotX: -swing, color: robe, pattern: 4),
            box(-4, 12, -3, 8, 12, 6, robe, 4), box(-4, 24, -4, 8, 10, 8, skin, 4), box(-1, 26, -6, 2, 4, 2, skin * 0.9),
            box(-6, 17, -5, 12, 4, 3, robe, 4), box(-4.3, 30, -4.3, 8.6, 5, 8.6, robe * 0.8, 4),
        ] + eyes(28.5, -4, 1, 1.2, V3(0.2, 0.5, 0.2))
    case .phantom:
        let c = V3(0.25, 0.3, 0.55)
        let flap = sinf(m.walkPhase * 2) * 0.5
        return [box(-3, 0, -5, 6, 3, 10, c, 4), box(-3.5, 0, -8, 7, 3, 3, c, 4),
                Part(mn: V3(-16, 1.5, -3), mx: V3(-3, 2, 4), pivot: V3(-3, 2, 0), rotZ: flap, color: c * 0.8),
                Part(mn: V3(3, 1.5, -3), mx: V3(16, 2, 4), pivot: V3(3, 2, 0), rotZ: -flap, color: c * 0.8),
                box(-2, 0.5, -8.2, 1.5, 1, 0.3, V3(0.6, 1, 0.3)), box(0.5, 0.5, -8.2, 1.5, 1, 0.3, V3(0.6, 1, 0.3)),
                box(-1, 0.5, 5, 2, 1.5, 6, c)]
    case .guardian, .elderGuardian:
        let big = m.kind == .elderGuardian
        let k: Float = big ? 2.35 : 1
        let c = big ? V3(0.8, 0.78, 0.7) : V3(0.45, 0.62, 0.55)
        var p = [box(-6 * k, 0, -6 * k, 12 * k, 12 * k, 12 * k, c, 4), box(-2 * k, 5 * k, -6.3 * k, 4 * k, 3 * k, 0.3, V3(0.95, 0.95, 0.9)),
                 box(-1 * k, 5.5 * k, -6.5 * k, 2 * k, 2 * k, 0.3, V3(0.1, 0.1, 0.1))]
        for i in 0..<6 {
            let a = Float(i) * .pi / 3
            p.append(box(cosf(a) * 6 * k - 0.5, 6 * k + sinf(a) * 6 * k, -0.5, 1, 1, 1 + 4 * k, V3(0.85, 0.75, 0.6)))
        }
        p.append(Part(mn: V3(-1.5 * k, 4 * k, 6 * k), mx: V3(1.5 * k, 7 * k, 14 * k), pivot: V3(0, 5.5 * k, 6 * k), rotX: sinf(m.walkPhase) * 0.3, color: c))
        return p
    case .endermite:
        let c = V3(0.2, 0.15, 0.25)
        return [box(-2, 0, -3, 4, 3, 2, c), box(-1.5, 0, -1, 3, 3, 3, c), box(-1, 0, 2, 2, 2, 2, c), box(-0.5, 0, 4, 1, 1, 2, c)]
    case .warden:
        let c = V3(0.05, 0.22, 0.26), glow = V3(0.3, 0.95, 0.95)
        return [
            Part(mn: V3(-6, 0, -3), mx: V3(-1, 13, 3), pivot: V3(-3.5, 13, 0), rotX: swing, color: c, pattern: 4),
            Part(mn: V3(1, 0, -3), mx: V3(6, 13, 3), pivot: V3(3.5, 13, 0), rotX: -swing, color: c, pattern: 4),
            box(-9, 13, -5, 18, 21, 11, c, 4), box(-5.5, 34, -6, 11, 12, 11, c, 4),
            Part(mn: V3(-13, 14, -4), mx: V3(-9, 34, 4), pivot: V3(-11, 33, 0), rotX: -swing * 0.6, color: c, pattern: 4),
            Part(mn: V3(9, 14, -4), mx: V3(13, 34, 4), pivot: V3(11, 33, 0), rotX: swing * 0.6, color: c, pattern: 4),
            box(-4, 22, -5.3, 8, 6, 0.3, glow), box(-9, 42, -2, 3, 6, 1, glow * 0.8), box(6, 42, -2, 3, 6, 1, glow * 0.8),
        ]
    case .breeze:
        let c = V3(0.75, 0.8, 0.95)
        let spin = Float(m.walkPhase)
        return [box(-4, 14, -4, 8, 8, 8, c, 4), box(-1, 3, -1, 2, 11, 2, c * 0.9),
                Part(mn: V3(-5, 6, -5), mx: V3(5, 8, 5), pivot: V3(0, 7, 0), rotX: 0, rotZ: sinf(spin) * 0.2, color: c * 0.85),
                Part(mn: V3(-4, 0, -4), mx: V3(4, 2, 4), pivot: V3(0, 1, 0), rotX: cosf(spin) * 0.2, color: c * 0.85)] + eyes(18, -4, 1.2, 1.2, V3(0.2, 0.3, 0.6))
    case .creaking:
        return barkwraithParts(m, swing: swing)
    case .happyGhast:
        return cloudwailerParts(m)
    case .bogged, .zoglin:
        if m.kind == .zoglin {
            let c = V3(0.8, 0.55, 0.55)
            var p = quadruped(.zero, V3(16, 14, 24), legH: 8, head: V3(0, 12, -12), headSize: V3(12, 10, 12), c, legW: 6)
            p.append(box(-8, 14, -20, 2, 6, 2, V3(0.9, 0.88, 0.8))); p.append(box(6, 14, -20, 2, 6, 2, V3(0.9, 0.88, 0.8)))
            return p
        }
        let bone = V3(0.62, 0.66, 0.5), moss = V3(0.35, 0.5, 0.25)
        return [
            Part(mn: V3(-2, 0, -1), mx: V3(0, 12, 1), pivot: V3(-1, 12, 0), rotX: swing, color: bone, pattern: 5),
            Part(mn: V3(0, 0, -1), mx: V3(2, 12, 1), pivot: V3(1, 12, 0), rotX: -swing, color: bone, pattern: 5),
            box(-4, 12, -2, 8, 12, 4, bone, 5), box(-4, 24, -4, 8, 8, 8, bone, 5), box(-4.3, 30, -4.3, 8.6, 2, 8.6, moss, 4),
            Part(mn: V3(-6, 12, -1), mx: V3(-4, 24, 1), pivot: V3(-5, 23, 0), rotX: -1.4, color: bone, pattern: 5),
            Part(mn: V3(4, 12, -1), mx: V3(6, 24, 1), pivot: V3(5, 23, 0), rotX: -1.4, color: bone, pattern: 5),
        ] + eyes(27, -4, 1, 1.5)
    default:
        return [box(-4, 0, -4, 8, 8, 8, V3(1, 0, 1))]
    }
}
