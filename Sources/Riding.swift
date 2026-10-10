import Foundation
import simd

// Taming, feeding, buckets and riding (horses, donkeys, mules, camels, pigs, magmastriders, llamas).
extension Game {
    // Right-click interactions with the new animals. Returns true when handled.
    func animalInteract(_ m: Mob) -> Bool {
        let key = Items.key(held.item)
        let pos = m.pos + V3(0, m.height, 0)
        // Taming with a chance per item (reference: 1 in 3).
        func tameTry(_ odds: Int = 3) {
            consumeHeld()
            if Rand.int(in: 0..<odds) == 0 {
                m.owner = true; m.persistent = true; m.aggro = false
                if m.kind == .wolf { m.health = 40 }
                particles.hearts(at: pos)
            } else { particles.smoke(at: pos) }
        }
        switch m.kind {
        case .wolf where !m.tamed && key == "bone": tameTry(); return true
        case .nautilus where !m.tamed && key == "pufferfish": tameTry(); return true
        case .cat where !m.tamed && (key == "cod" || key == "salmon"): tameTry(); return true
        case .ocelot where m.owner == nil && (key == "cod" || key == "salmon"):         // trusting ocelots breed on fish
            consumeHeld()
            if Rand.int(in: 0..<3) == 0 { m.owner = false; m.persistent = true; particles.hearts(at: pos) }        // trusting
            return true
        case .parrot where !m.tamed && key.hasSuffix("_seeds"): tameTry(10); return true          // reference: 1 in 10
        case .parrot where key == "cookie": consumeHeld(); m.health = 0; return true          // poisonous to parrots
        case .allay where key == "amethyst_shard" && m.sitting && m.breedCooldown <= 0:
            // Reference duplication: a dancing fetchling given an amethyst shard splits in two (5 min cooldown).
            consumeHeld()
            let twin = Mob(.allay, at: m.pos + V3(0.3, 0.2, 0))
            twin.breedCooldown = 300; m.breedCooldown = 300
            twin.persistent = true
            mobs.mobs.append(twin)
            particles.hearts(at: pos)
            return true
        case .allay:
            if !held.isEmpty && m.heldItem == 0 { m.heldItem = held.item; m.owner = true; m.persistent = true; particles.hearts(at: pos); return true }
            if held.isEmpty && m.heldItem != 0 { m.heldItem = 0; m.owner = nil; return true }
        case .mooshroom where key == "bowl":
            consumeHeld(); giveOrReplaceHeldAfterConsume(ItemStack(Items.id("mushroom_stew"), 1)); if !survival { _ = inventory.add(ItemStack(Items.id("mushroom_stew"), 1)) }
            return true
        case .mooshroom where key == "shears" && !m.baby:
            let cow = Mob(.cow, at: m.pos); cow.yaw = m.yaw; mobs.mobs.append(cow)
            let mush = m.variant == 1 ? "brown_mushroom" : "red_mushroom"
            if Items.has(mush) { drops.spawn(ItemStack(Items.id(mush), 5), at: pos) }
            m.health = -2000
            damageHeld(1)
            return true
        case .happyGhast where Cloudwailer.harnessColor[held.item] != nil && !m.saddled && !m.baby:
            m.saddled = true; m.collar = Cloudwailer.harnessColor[held.item] ?? 0; m.persistent = true; m.home = m.pos
            consumeHeld(); sfx(.place(.wood), 0.6); return true
        case .happyGhast where key == "shears" && m.saddled && riding !== m:
            if let h = Cloudwailer.harnessColor.first(where: { $0.value == m.collar })?.key { drops.spawn(ItemStack(h, 1), at: pos) }
            m.saddled = false; damageHeld(1); return true
        case .happyGhast where key == "snowball" && m.health < m.spec.health:
            m.health += 1; consumeHeld(); particles.hearts(at: pos); return true
        case .snowGolem where key == "shears" && m.variant == 0:
            // Sheared snow golems lose their pumpkin (reference).
            m.variant = 1
            if Items.has("carved_pumpkin") { drops.spawn(ItemStack(Items.id("carved_pumpkin"), 1), at: pos) }
            damageHeld(1); return true
        case .bogged where key == "shears" && m.variant == 0:
            m.variant = 1
            for n in ["red_mushroom", "brown_mushroom"] where Items.has(n) { drops.spawn(ItemStack(Items.id(n), 1), at: pos) }
            damageHeld(1); return true
        case .ironGolem where key == "iron_ingot" && m.health < m.spec.health:
            // Reference: an iron ingot repairs 25 health.
            m.health = min(m.spec.health, m.health + 25)
            if survival { consumeHeld() }
            sfx(.anvil, 0.5, at: pos)
            return true
        case .dolphin where key == "cod" || key == "salmon":
            // Fed raw fish, a dolphin leads the way to the nearest treasure, shipwreck or ocean ruin for a minute.
            consumeHeld()
            particles.hearts(at: pos)
            if let sc = world.gen.structures {
                let x = Int(floor(m.pos.x)), z = Int(floor(m.pos.z))
                var best: IVec3?
                var bd = Int.max
                for k in ["buried_treasure", "shipwreck", "ocean_ruin"] {
                    guard let s = sc.nearest(k, x: x, z: z) else { continue }
                    let dx = s.anchor.x - x, dz = s.anchor.z - z
                    let d = dx * dx + dz * dz
                    if d < bd { bd = d; best = s.anchor }
                }
                if let a = best {
                    m.home = V3(Float(a.x) + 0.5, Float(a.y), Float(a.z) + 0.5)
                    m.phaseTime = 60
                }
            }
            return true
        case .goat where key == "bucket" && !m.baby:
            consumeHeld(); giveOrReplaceHeldAfterConsume(ItemStack(Items.id("milk_bucket"), 1)); return true
        case .cod, .salmon, .tropicalFish, .pufferfish, .axolotl, .tadpole:
            guard key == "water_bucket" else { break }
            let name = "\(m.kind.key)_bucket"
            guard Items.has(name) else { break }
            inventory.held = ItemStack(Items.id(name), 1, damage: m.variant)
            m.health = -2000
            sfx(.breakBlock(.wood), 0.6)
            return true
        case .wanderingTrader:
            if m.villager == nil { m.villager = WanderingTrader.data() }
            openMenu(MerchantMenu(game: self, villager: m))
            return true
        default: break
        }
        // Pets: dye a wolf collar, sit / stand.
        if m.tamed && (m.kind == .wolf || m.kind == .cat) {
            if key.hasSuffix("_dye"), let i = BlockRegistry.colors.firstIndex(where: { "\($0.0)_dye" == key }) { m.collar = i; consumeHeld(); return true }
            // Reference: food heals a hurt pet (twice its nutrition), breeds a healthy adult one, and anything else
            // makes it sit or stand. (Food at full health toggled sitting, so tamed wolves and cats never bred.)
            let isFood = MobKind.animalFood[m.kind]?.contains(key) ?? false
            let maxHP = m.kind == .wolf ? 40 : m.spec.health
            if isFood && m.health < maxHP {
                let heal = 2 * (held.def.food?.hunger ?? 2)
                m.health = min(maxHP, m.health + heal); consumeHeld(); particles.hearts(at: pos); return true
            }
            if !isFood || (!m.baby && (m.breedCooldown > 0 || m.inLove > 0)) { m.sitting.toggle(); return true }
        }
        // Saddles and chests.
        let rideable: Set<MobKind> = [.horse, .donkey, .mule, .camel, .pig, .strider, .skeletonHorse, .zombieHorse, .nautilus]
        if key == "saddle" && rideable.contains(m.kind) && !m.saddled && !m.baby && (m.tamed || m.kind == .pig || m.kind == .strider) {
            m.saddled = true; m.persistent = true; consumeHeld(); sfx(.place(.wood), 0.6)
            onToast?("Saddled: you can steer it now"); return true
        }
        // A saddle on a wild horse: say how to tame it (then mount, below, or nothing when already riding it).
        if key == "saddle" && m.horseLike && rideable.contains(m.kind) && !m.saddled && !m.tamed && !m.baby {
            onToast?(riding === m ? "Not tamed yet: keep riding until hearts appear" : "Tame it first: ride it until hearts appear, then use the saddle")
            if riding === m { return true }
        }
        // Horse armour (leather/iron/gold/diamond) and wolf armour.
        // armorTier: 1 leather, 2 iron, 3 gold, 4 diamond, 6 copper, 7 duskium (5 is wolf armour).
        let horseArmor: [String: Int] = ["leather_horse_armor": 1, "iron_horse_armor": 2, "golden_horse_armor": 3, "diamond_horse_armor": 4,
                                         "copper_horse_armor": 6, "netherite_horse_armor": 7]
        if let t = horseArmor[key], m.kind == .horse, m.tamed, !m.baby, m.armorTier == 0 {
            m.armorTier = t; consumeHeld(); sfx(.place(.stone), 0.6); return true
        }
        if key == "wolf_armor" && m.kind == .wolf && m.tamed && !m.baby && m.armorTier == 0 {
            m.armorTier = 5; m.armorHP = 64; consumeHeld(); sfx(.place(.stone), 0.6); return true
        }
        if key == "shears" && m.kind == .wolf && m.tamed && m.armorTier == 5 {
            m.armorTier = 0
            var w = ItemStack(Items.id("wolf_armor"), 1); w.damage = 64 - m.armorHP
            drops.spawn(w, at: m.pos + V3(0, 0.6, 0))
            damageHeld(1); achieve("wolf_armor"); return true
        }
        if key == "chest" && [MobKind.donkey, .mule, .llama, .traderLlama].contains(m.kind) && m.tamed && !m.chested {
            m.chested = true; consumeHeld(); return true
        }
        // Horse treats (reference): temper toward taming, healing, growth; golden food breeds tamed horses.
        let treats: [String: (temper: Int, heal: Int, grow: Float)] = [
            "sugar": (3, 1, 30), "wheat": (3, 2, 20), "apple": (3, 3, 60), "golden_carrot": (5, 4, 60),
            "golden_apple": (10, 10, 240), "enchanted_golden_apple": (10, 10, 240), "hay_block": (0, 20, 180)]
        if [MobKind.horse, .donkey, .mule, .zombieHorse].contains(m.kind), let t = treats[key] {
            let golden = key == "golden_carrot" || key.hasSuffix("golden_apple")
            if golden && m.tamed && !m.baby && m.kind != .mule && m.breedCooldown <= 0 && m.inLove <= 0 {
                m.inLove = 30
            } else if m.health >= 30 && !m.baby && (m.tamed || t.temper == 0) {
                return false
            }
            m.health = min(30, m.health + t.heal)
            if m.baby { m.age += t.grow }
            if !m.tamed { m.temper = min(100, m.temper + t.temper) }
            consumeHeld()
            particles.hearts(at: pos)
            return true
        }
        // Feeding: breed or grow up.
        if let food = MobKind.animalFood[m.kind], food.contains(key) {
            // Reference: feeding a baby takes 10% off the time it still needs to grow up.
            if m.baby { m.age += max(1, (1200 - m.age) * 0.1); consumeHeld(); particles.hearts(at: pos); return true }
            let needsTame: Set<MobKind> = [.wolf, .cat, .horse, .donkey, .llama, .parrot]
            if needsTame.contains(m.kind) && !m.tamed {
                if m.horseLike { m.temper += 5; consumeHeld(); return true }
                return false
            }
            guard m.breedCooldown <= 0, m.inLove <= 0 else { return false }
            m.inLove = 30
            consumeHeld()
            particles.hearts(at: pos)
            return true
        }
        // Mount.
        if (m.horseLike && m.kind != .traderLlama) || ((m.kind == .pig || m.kind == .strider || m.kind == .happyGhast || m.kind == .nautilus) && m.saddled) {
            guard !m.baby, riding == nil else { return false }
            riding = m
            m.persistent = true
            player.pos = m.pos + V3(0, m.height * 0.75, 0)
            sfx(.armorEquip(0), 0.5, at: m.pos)
            return true
        }
        return false
    }
}

// MARK: The bonded horse (Quest round 4, like a ranch horse in an open-world western)
// The last tamed horse (donkey, mule) the player rode is theirs: unridden it keeps within ~10 blocks of them, and the fly
// button in survival (Quest: tap Y; pad: D-pad up; keys: the fly key) calls it: loaded within 64 blocks it gallops over;
// farther away, or stored with its chunk thousands of blocks off, it is brought to a spot ~14 blocks behind the player
// and runs up.
extension Game {
    func bondHorse(_ m: Mob) {
        // Any other horse loaded with an old bond is just a horse again.
        for o in mobs.mobs where o.bond != 0 && o !== m { o.bond = 0 }
        horseBond = Float(Rand.int(in: 1...16_000_000))
        m.bond = horseBond
        m.persistent = true
        onToast?("This is your horse now: \(Prompt.g(.fly)) calls it")
    }

    // Returns false when there is no bonded horse (the fly button keeps its "no flying" toast).
    func callHorse() -> Bool {
        guard horseBond != 0 else { return false }
        if riding?.bond == horseBond { return true }
        var horse = mobs.mobs.first { $0.bond == horseBond && $0.health > 0 }
        if horse == nil {
            for (k, list) in mobs.stored {
                guard let i = list.firstIndex(where: { $0.extra?["bond"] == horseBond }) else { continue }
                var l = list
                let r = l.remove(at: i)
                mobs.stored[k] = l.isEmpty ? nil : l
                if let m = Mob.from(r) { mobs.mobs.append(m); horse = m }
                break
            }
        }
        guard let h = horse else { onToast?("Your horse doesn't answer (it may have died)"); horseBond = 0; return true }
        let d = simd_length(h.pos - player.pos)
        if d > 64 || !world.isLoaded(Int(floor(h.pos.x)), Int(floor(h.pos.z))) {
            // Out of sight behind the player, on the ground, then it runs up.
            let back = V3(sinf(player.yaw), 0, cosf(player.yaw))
            var spot = player.pos + back * 14
            let x = Int(floor(spot.x)), z = Int(floor(spot.z))
            if world.isLoaded(x, z) { spot.y = Float(world.topY(x, z) + 1) } else { spot = player.pos }
            h.pos = world.freeSpawn(spot)
            h.vel = .zero
        }
        horseCall = 25
        sfx(.mob(h.kind, .ambient), 1.2, at: h.pos)
        onToast?("You call your horse")
        return true
    }
}

extension Mob {
    // Unridden, the bonded horse keeps near the player and gallops to them when called; nil = not the bonded horse.
    func bondedHorseAI(_ dt: Float, _ g: Game, dist: Float) -> Float? {
        guard bond != 0, bond == g.horseBond, tamed, g.riding !== self, g.alive else { return nil }
        if g.horseCall > 0 && dist < 3 { g.horseCall = 0 }
        let called = g.horseCall > 0
        if dist > 80 { return nil }                       // left far behind: it waits until called
        if called || dist > 10 {
            face(g.player.pos)
            return spec.speed * (called || dist > 18 ? 2.2 : 1.2)
        }
        wander()
        return moving ? spec.speed * 0.3 : 0
    }
}

extension Mob {
    // A mount carrying the player: WASD steers (horses, camels, donkeys, mules), pigs and magmastriders follow
    // the stick; untamed horses buck until tamed.
    func updateRidden(_ dt: Float, _ g: Game) {
        if kind == .happyGhast { rideCloudwailer(dt, g); return }
        if kind == .nautilus { rideNautilus(dt, g); return }
        let w = g.world
        let inp = g.rideInput
        var speed: Float = 0
        switch kind {
        case .pig:
            if Items.key(g.held.item) == "carrot_on_a_stick" { speed = 3.5 * stickBoost(dt); yaw = g.player.yaw }
        case .strider:
            if Items.key(g.held.item) == "warped_fungus_on_a_stick" { speed = 2.5 * stickBoost(dt); yaw = g.player.yaw }
        case .llama, .traderLlama:
            speed = 0            // llamas can't be steered
            // Taming by riding like a horse, against a temper of 30 (reference; they could never be tamed).
            if !tamed {
                jumpCharge += dt
                if jumpCharge > 1 {
                    jumpCharge = 0
                    if Rand.int(in: 0..<30) < temper { owner = true; g.particles.hearts(at: pos + V3(0, height, 0)) }
                    else { temper += 5; g.dismount(); vel.y = 4; g.sfx(.mob(kind, .hurt), 1, at: pos); return }
                }
            }
        default:
            // Untamed: buck the rider off unless the taming roll succeeds.
            if !tamed {
                jumpCharge += dt
                if jumpCharge > 1 {
                    jumpCharge = 0
                    if Rand.int(in: 0..<100) < temper { owner = true; g.particles.hearts(at: pos + V3(0, height, 0)) }
                    else { temper += 5; g.dismount(); vel.y = 4; g.sfx(.mob(kind, .hurt), 1, at: pos); return }
                }
            }
            if tamed && kind != .camel && bond != g.horseBond { g.bondHorse(self) }
            yaw = g.player.moveYaw ?? g.player.yaw          // VR: steer with the head, not the aiming hand
            let base: Float = kind == .camel ? 3.8 : (kind == .donkey || kind == .mule ? 7.5 : horseSpeed)
            speed = saddled || !tamed ? base * max(-0.25, inp.forward) : 0
            // Hold jump to charge, release to leap (horses); camels dash.
            if inp.jump { jumpCharge = min(1, jumpCharge + dt) }
            else if jumpCharge > 0.05 && onGround && tamed {
                if kind == .camel {
                    vel.y = 6 + 8 * jumpCharge * horseJump
                } else {
                    // Reference: power 0.4-0.84 below a 90 % charge, full above; the height follows the reference
                    // curve of the strength (1.0 -> 5.3 blocks, 0.4 -> 1.1), launched at the speed that reaches it.
                    // (6 + 8 x charge x strength topped out near 3.5.)
                    let power: Float = jumpCharge >= 0.9 ? 1 : 0.4 + 0.4 * jumpCharge / 0.9
                    let s: Float = horseJump * power
                    let s2: Float = s * s
                    let cubic: Float = -0.1817962 * s2 * s + 3.689713 * s2
                    let h: Float = max(0.3, cubic + 2.128599 * s - 0.343930)
                    vel.y = sqrtf(2 * 28 * h)
                }
                if kind == .camel { vel += forward * 12 * jumpCharge }
                jumpCharge = 0
            }
        }
        let target = forward * speed
        let k = 1 - expf(-(onGround ? 10 : 2) * dt)
        vel.x += (target.x - vel.x) * k
        vel.z += (target.z - vel.z) * k
        let feet = w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.2)), Int(floor(pos.z)))
        if kind == .strider && Blocks.fluidKind[Int(feet)] == 2 { vel.y = max(vel.y, 2) }
        else if Blocks.isLiquid(feet) { vel.y += 18 * dt; vel.y = min(vel.y, 1.6) }
        else { vel.y -= 28 * dt }
        let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 1.05, onGround: onGround)
        var landed = false
        if hit.y { if vel.y < 0 { landed = true }; vel.y = 0 }
        if hit.x { vel.x = 0 }
        if hit.z { vel.z = 0 }
        onGround = landed || (vel.y <= 0 && collides(pos - V3(0, 0.06, 0), w))
        let hs = simd_length(V2(vel.x, vel.z))
        walkPhase += hs * dt * 3
        walkAmount += (min(1, hs / 2) - walkAmount) * min(1, dt * 8)
        g.player.pos = pos + V3(0, height * 0.75, 0)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
    }

    // A stick boost's speed factor (reference: 1 + 1.15 sin(pi t / total) over 7-49 s), then it ends.
    func stickBoost(_ dt: Float) -> Float {
        guard boostTotal > 0 else { return 1 }
        boostTime += dt
        if boostTime >= boostTotal { boostTime = 0; boostTotal = 0; return 1 }
        return 1 + 1.15 * sinf(Float.pi * boostTime / boostTotal)
    }

    // Per-horse speed and jump strength from its variant bits: 4.8-16 b/s (reference 4.8-14.5; the best rolls go past
    // it so a good horse is genuinely fast). Unridden horses wander and bolt in proportion (Mob.update).
    var horseSpeed: Float { 4.8 + Float((variant >> 4) & 15) / 15 * 11.2 }
    var horseJump: Float { 0.4 + Float((variant >> 8) & 15) / 15 * 0.6 }
}

// Wandering trader offers (reference pool: 5 random from the common list + 1 rare).
enum WanderingTrader {
    static func data() -> VillagerData {
        var v = VillagerData()
        v.profession = "wandering_trader"
        v.locked = true
        let common: [(String, Int, Int)] = [
            ("sea_pickle", 2, 1), ("slime_ball", 4, 1), ("glowstone", 2, 1), ("nautilus_shell", 5, 1), ("fern", 1, 1), ("sugar_cane", 1, 1),
            ("pumpkin", 1, 1), ("kelp", 3, 1), ("cactus", 3, 1), ("dandelion", 1, 1), ("poppy", 1, 1), ("blue_orchid", 1, 1), ("allium", 1, 1),
            ("azure_bluet", 1, 1), ("red_tulip", 1, 1), ("orange_tulip", 1, 1), ("white_tulip", 1, 1), ("pink_tulip", 1, 1), ("oxeye_daisy", 1, 1),
            ("cornflower", 1, 1), ("lily_of_the_valley", 1, 1), ("wheat_seeds", 1, 1), ("beetroot_seeds", 1, 1), ("pumpkin_seeds", 1, 1),
            ("melon_seeds", 1, 1), ("acacia_sapling", 5, 1), ("birch_sapling", 5, 1), ("dark_oak_sapling", 5, 1), ("jungle_sapling", 5, 1),
            ("oak_sapling", 5, 1), ("spruce_sapling", 5, 1), ("cherry_sapling", 5, 1), ("mangrove_propagule", 5, 1), ("red_dye", 1, 3),
            ("white_dye", 1, 3), ("blue_dye", 1, 3), ("pink_dye", 1, 3), ("black_dye", 1, 3), ("green_dye", 1, 3), ("light_gray_dye", 1, 3),
            ("magenta_dye", 1, 3), ("yellow_dye", 1, 3), ("gray_dye", 1, 3), ("purple_dye", 1, 3), ("light_blue_dye", 1, 3), ("lime_dye", 1, 3),
            ("orange_dye", 1, 3), ("brown_dye", 1, 3), ("cyan_dye", 1, 3), ("brain_coral_block", 3, 1), ("bubble_coral_block", 3, 1),
            ("fire_coral_block", 3, 1), ("horn_coral_block", 3, 1), ("tube_coral_block", 3, 1), ("vine", 1, 1), ("brown_mushroom", 1, 1),
            ("red_mushroom", 1, 1), ("lily_pad", 1, 2), ("small_dripleaf", 1, 2), ("sand", 1, 8), ("red_sand", 1, 4), ("pointed_dripstone", 1, 2),
            ("rooted_dirt", 1, 2), ("moss_block", 1, 2),
        ].filter { Items.has($0.0) }
        let rare: [(String, Int, Int)] = [("tropical_fish_bucket", 5, 1), ("pufferfish_bucket", 5, 1), ("packed_ice", 3, 1), ("blue_ice", 6, 1),
                                          ("gunpowder", 1, 1), ("podzol", 3, 3)].filter { Items.has($0.0) }
        for e in common.shuffledRand().prefix(5) {
            v.offers.append(TradeOffer(buyA: ItemStack(Items.id("emerald"), e.1), buyB: .empty, sell: ItemStack(Items.id(e.0), e.2), maxUses: 12, xp: 1, priceMult: 0.05))
        }
        if let e = rare.pick() {
            v.offers.append(TradeOffer(buyA: ItemStack(Items.id("emerald"), e.1), buyB: .empty, sell: ItemStack(Items.id(e.0), e.2), maxUses: 6, xp: 1, priceMult: 0.05))
        }
        return v
    }
}

extension Mob {
    // Colour / breed variants and per-animal stats rolled at spawn (reference odds where they matter).
    func randomizeVariant() {
        switch kind {
        case .horse:
            variant = Rand.int(in: 0..<5) | (Rand.int(in: 0..<16) << 4) | (Rand.int(in: 0..<16) << 8)
            health = Rand.int(in: 15...30)
        case .donkey, .mule, .llama, .traderLlama:
            variant = Rand.int(in: 0..<4) | (Rand.int(in: 0..<16) << 4) | (Rand.int(in: 0..<16) << 8)
            health = Rand.int(in: 15...30)
        case .skeletonHorse, .zombieHorse: variant = (8 << 4) | (8 << 8)
        case .rabbit, .cat, .tropicalFish: variant = Rand.int(in: 0..<4)
        case .parrot: variant = Rand.int(in: 0..<5)
        case .axolotl: variant = Rand.int(in: 0..<1200) == 0 ? 4 : Rand.int(in: 0..<4)       // blue is 1 in 1200
        case .goat: variant = Rand.int(in: 0..<50) == 0 ? 1 : 0                                     // screaming goats: 2%
        case .frog: variant = Rand.int(in: 0..<3)
        case .soldierRecruit, .soldierTrooper, .soldierMarksman, .soldierIronclad, .soldierOfficer, .soldierCrew, .ashMarshal: variant = Soldier.pickGun(kind)
        case .panda: variant = Mob.pandaGene() | (Mob.pandaGene() << 3)
        default: break
        }
    }
}

// A mount's inventory (Quest v63: a saddle could never come off): the saddle slot, a horse's armour slot and a chested
// mount's pack, over the player's inventory. Opened with the inventory while riding a horse-like mount, or by
// sneak-using a tamed one. The mount's saddle and armour follow the slots when the screen closes.
final class MountMenu: Menu {
    static let saddleKinds: Set<MobKind> = [.horse, .donkey, .mule, .camel, .skeletonHorse, .zombieHorse]
    static let armorItems: [Int: String] = [1: "leather_horse_armor", 2: "iron_horse_armor", 3: "golden_horse_armor",
                                            4: "diamond_horse_armor", 6: "copper_horse_armor", 7: "netherite_horse_armor"]
    static func opens(_ m: Mob) -> Bool { saddleKinds.contains(m.kind) || (m.horseLike && m.chested) }
    static func armorTier(_ key: String) -> Int? { armorItems.first { $0.value == key }?.key }

    let mob: Mob
    let gear = ItemContainer(2)
    init(game: Game, mob m: Mob) {
        mob = m
        super.init(m.customName ?? m.kind.name, game: game)
        if MountMenu.saddleKinds.contains(m.kind) {
            if m.saddled { gear[0] = ItemStack(Items.id("saddle"), 1) }
            let s = MenuSlot(8, 18, gear, 0)
            s.filter = { Items.key($0.item) == "saddle" }
            s.limit = 1
            slots.append(s)
        }
        if m.kind == .horse {
            if let k = MountMenu.armorItems[m.armorTier], Items.has(k) { gear[1] = ItemStack(Items.id(k), 1) }
            let a = MenuSlot(8, 36, gear, 1)
            a.filter = { MountMenu.armorTier(Items.key($0.item)) != nil }
            a.limit = 1
            slots.append(a)
        }
        if m.chested {
            let c = game.packContainer(m)
            let rows = c.count >= 3 && c.count % 3 == 0 ? 3 : 1
            let cols = c.count / rows
            for r in 0..<rows { for col in 0..<cols { slots.append(MenuSlot(80 + col * 18, 18 + r * 18, c, col + r * cols)) } }
        }
        addPlayerInventory()
    }

    override func onClose() {
        if MountMenu.saddleKinds.contains(mob.kind) {
            let had = mob.saddled
            mob.saddled = Items.key(gear[0].item) == "saddle"
            if had && !mob.saddled && game.riding === mob && mob.tamed { game.onToast?("Saddle off: it won't steer") }
        }
        if mob.kind == .horse { mob.armorTier = gear[1].isEmpty ? 0 : (MountMenu.armorTier(Items.key(gear[1].item)) ?? 0) }
        if mob.saddled || mob.armorTier > 0 { mob.persistent = true }
    }
}
