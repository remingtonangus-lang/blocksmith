import Foundation
import simd

// Taming, feeding, buckets and riding (horses, donkeys, mules, camels, pigs, magmastriders, llamas).
extension Game {
    // Right-click interactions with the new animals. Returns true when handled.
    func animalInteract(_ m: Mob) -> Bool {
        let key = Items.key(held.item)
        let pos = m.pos + V3(0, m.height, 0)
        // A downed horse: only a Saddle Salve helps (HorseLife.swift).
        if m.downed > 0 {
            if useReviver(on: m) { return true }
            onToast?("\(m.customName ?? "This horse") is badly hurt")
            return true
        }
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
        case .wolf where !m.tamed && m.legend < 0 && key == "bone": tameTry(); return true
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
        case .mooshroom where key == "shears" && !m.baby && !m.sheared:
            // P280 (c): shearing a Shellback takes its shell moss (and a bloom); it regrows while it grazes.
            m.sheared = true
            if Items.has("moss_carpet") { drops.spawn(ItemStack(Items.id("moss_carpet"), Rand.int(in: 2...3)), at: pos) }
            let bloom = m.variant == 1 ? "dandelion" : "pink_petals"
            if Items.has(bloom) { drops.spawn(ItemStack(Items.id(bloom), 1), at: pos) }
            damageHeld(1)
            sfx(.shearsSnip, 1, at: m.pos)
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
            onToast?("Saddled"); return true
        }
        // A saddle on a wild horse: not yet (then mount, below, or nothing when already riding it).
        if key == "saddle" && m.horseLike && rideable.contains(m.kind) && !m.saddled && !m.tamed && !m.baby {
            onToast?("Not tamed yet")
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
            } else if m.health >= m.horseMaxHealth && !m.baby && (m.tamed || t.temper == 0) {
                // Full health: a tamed horse still takes it for its wind (stamina, HorseFeel.swift) and its cores (H10).
                let cores = m.gaited && m.tamed && m.feedCores(HorseCores.food[key]?.0 ?? 0, HorseCores.food[key]?.1 ?? 0)
                guard horseTreat(m, key) || cores else { return false }
                consumeHeld(); particles.hearts(at: pos); return true
            }
            _ = horseTreat(m, key)
            if m.gaited && m.tamed { m.feedCores(HorseCores.food[key]?.0 ?? 0, HorseCores.food[key]?.1 ?? 0) }
            m.health = min(m.horseMaxHealth, m.health + t.heal)
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
        // A brush grooms a tamed horse (bond, HorseFeel.swift).
        if key == "brush" && m.gaited && m.tamed && !m.baby { horseBrush(m); return true }
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
struct HorseGrave: Codable {
    var name: String
    var x: Int, z: Int
    var day: Int
    var place: String
    var dim: String
}

extension Game {
    // (The gap pass: other horses of yours keep their bond and id; this one becomes the one that's called.)
    func bondHorse(_ m: Mob) { makeCurrentHorse(m) }

    // P259 (Oct 14 12:14): the bonded horse died: remember it (the call says so, the map marks the spot).
    func horseDied(_ m: Mob) {
        let x = Int(floor(m.pos.x)), z = Int(floor(m.pos.z))
        let name = m.customName ?? "Your horse"
        let place = dim.dim == .overworld ? journalPlace() : dim.dim.displayName
        horseGrave = HorseGrave(name: name, x: x, z: z, day: Int(time / DAY_LENGTH), place: place, dim: dim.dim.rawValue)
        Waymarks.marksAt = -1e9
    }

    // Returns false when there is no bonded horse (the fly button keeps its "no flying" toast).
    func callHorse() -> Bool {
        guard horseBond != 0 else {
            // P259 (a): a dead horse can't come; say which, when and where (the spot is on the map).
            guard let gr = horseGrave else { return false }
            let ago = Int(time / DAY_LENGTH) - gr.day
            let when = ago <= 0 ? "today" : (ago == 1 ? "yesterday" : "\(ago) days ago")
            onToast?("\(gr.name) died \(when) at \(gr.place) (\(gr.x), \(gr.z)). Where it fell is marked on your map")
            sfx(.mob(.horse, .ambient), 0.25, at: player.pos + V3(0, 2, 0))
            return true
        }
        if riding?.bond == horseBond { return true }
        // P117 (Oct 12 PM: "the horse must not come when called from underground"): below ground the call doesn't
        // carry; a call already answered is dropped too (bondedHorseAI).
        if BountyHunters.below(self) {
            let nm = mobs.mobs.first { $0.bond == horseBond }?.customName ?? "Your horse"
            onToast?("\(nm) can't hear you down here")
            horseCall = 0
            return true
        }
        var horse = mobs.mobs.first { $0.bond == horseBond && $0.health > 0 }
        if horse == nil {
            for (k, list) in mobs.stored {
                guard let i = list.firstIndex(where: { $0.extra?["bond"] == horseBond }) else { continue }
                if (list[i].extra?["down"] ?? 0) > 0 {               // down out there: it stays where it lies
                    onToast?("\(list[i].name ?? "Your horse") is down and can't come")
                    return true
                }
                var l = list
                let r = l.remove(at: i)
                mobs.stored[k] = l.isEmpty ? nil : l
                if let m = Mob.from(r) { mobs.mobs.append(m); horse = m }
                break
            }
        }
        if horse == nil, let s = Stable.kept.first(where: { $0.rec.extra?["bond"] == horseBond }) {
            onToast?("\(Stable.name(s)) is in the stable at \(s.town)")
            return true
        }
        guard let h = horse else { onToast?("Your horse doesn't answer (it may have died)"); horseBond = 0; return true }
        // P259 (e): how far and which way it is, while it runs to him.
        let off = h.pos - player.pos
        let far = simd_length(V2(off.x, off.z))
        if h.downed > 0 { onToast?("\(h.customName ?? "Your horse") is down and can't come"); return true }
        let d = simd_length(h.pos - player.pos)
        if h.hitched { unhitch(h) }                             // D3: a call unties it
        h.stayAt = nil
        h.hs.callStuck = 0; h.hs.callWas = h.pos
        if d > 160 || !world.isLoaded(Int(floor(h.pos.x)), Int(floor(h.pos.z))) {
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
        let wayOff = far > 160 ? " (it was \(Int(far / 10) * 10) blocks \(TownBoard.direction(off.x, off.z)), it's catching up)"
                               : (far > 12 ? " (\(Int(far)) blocks, \(Waymarks.side(self, h.pos)))" : "")
        onToast?("You call \(h.customName ?? "your horse")" + wayOff)
        return true
    }
}

extension Mob {
    // Unridden, a horse of yours waits where it was left (grazing, wandering a few blocks: HorseLife.waitWhereLeft);
    // the one you rode last comes when called, along a path (Pathfinding: 160-block reach for it), and if it makes no
    // headway for 6 s it is brought round behind you out of sight. nil = not a horse of yours.
    func bondedHorseAI(_ dt: Float, _ g: Game, dist: Float) -> Float? {
        guard bond != 0, tamed, g.riding !== self, g.alive else { return nil }
        let current = bond == g.horseBond
        // Called, it pulls up beside you (it ran on to 3 blocks, centre to centre, and walked into him: P26).
        if current && g.horseCall > 0 && dist < 4.5 { g.horseCall = 0; stayAt = pos; vel.x = 0; vel.z = 0 }
        if current && g.horseCall > 0 && BountyHunters.below(g) { g.horseCall = 0; stayAt = pos }       // P117
        if current && g.horseCall > 0 {
            let h = hs
            if simd_length(pos - h.callWas) > 2 { h.callWas = pos; h.callStuck = 0 } else { h.callStuck += dt }
            if h.callStuck > 6 && dist > 8 {
                h.callStuck = 0
                // Behind you, on ground at your level (never off a cliff edge onto the ground below); with no such ground,
                // beside you.
                let back = V3(sinf(g.player.yaw), 0, cosf(g.player.yaw))
                var spot = g.player.pos
                for d: Float in [10, 7, 4, 2] {
                    let p = g.player.pos + back * d
                    let x = Int(floor(p.x)), z = Int(floor(p.z))
                    guard g.world.isLoaded(x, z) else { continue }
                    let y = Float(g.world.topY(x, z) + 1)
                    guard abs(y - g.player.pos.y) < 3 else { continue }
                    spot = V3(p.x, y, p.z)
                    break
                }
                pos = g.world.freeSpawn(spot); vel = .zero; h.callWas = pos; HorseLife.broughtRound += 1
            }
            face(g.player.pos)
            return spec.speed * (dist > 18 ? 2.2 : 1.4)
        }
        // A horse of yours you walk up to knows you: it turns to you and nickers now and then.
        if dist < 5 && Rand.float(in: 0..<1) < dt * 0.15 { face(g.player.pos); g.sfx(.mob(kind, .ambient), 0.5, at: pos); HorseLife.greetings += 1 }
        return waitWhereLeft(dt, g)
    }
}

extension Mob {
    // A mount carrying the player: WASD steers (horses, camels, donkeys, mules), pigs and magmastriders follow
    // the stick; untamed horses buck until tamed.
    func updateRidden(_ dt: Float, _ g: Game) {
        stayAt = nil                                        // ridden: where it waits is wherever you get off next
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
            // Untamed: the calm-down minigame (HorseLife.tameStep): sit still through the bucks, pat it as it settles.
            if !tamed {
                if !tameStep(dt, g, inp) { return }
            }
            // (bond 0 too: with no horse bonded yet, horseBond is 0 as well, so the first tamed horse never bonded.)
            if tamed && kind != .camel && (bond == 0 || bond != g.horseBond) { g.bondHorse(self) }
            if gaited && tamed {
                gaitStep(dt, g, inp)                        // gaits, momentum, stamina, nerves, footing (HorseFeel.swift)
                if g.riding !== self { return }             // thrown
            } else {
                yaw = g.player.moveYaw ?? g.player.yaw      // VR: steer with the head, not the aiming hand
                let base: Float = kind == .camel ? 3.8 : (kind == .donkey || kind == .mule ? 7.5 : horseSpeed)
                speed = tamed && saddled ? base * max(-0.25, inp.forward) : 0          // (a wild horse goes its own way)
            }
            // Hold jump to charge, release to leap (horses); camels dash. P49: a swimming horse can jump too (out of
            // the water onto a bank).
            let swimming = Blocks.isLiquid(w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.2)), Int(floor(pos.z))))
            if inp.jump { jumpCharge = min(1, jumpCharge + dt) }
            else if jumpCharge > 0.05 && (onGround || swimming) && tamed {
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
                    if gaited { stamina -= 5 }
                }
                if kind == .camel { vel += forward * 12 * jumpCharge }
                jumpCharge = 0
            }
        }
        let gaitedRide = gaited && tamed
        if !gaitedRide {
            let target = forward * speed
            let k = 1 - expf(-(onGround ? 10 : 2) * dt)
            vel.x += (target.x - vel.x) * k
            vel.z += (target.z - vel.z) * k
        }
        let start = pos
        let feet = w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.2)), Int(floor(pos.z)))
        if kind == .strider && Blocks.fluidKind[Int(feet)] == 2 { vel.y = max(vel.y, 2) }
        else if Blocks.isLiquid(feet) { if vel.y < 3 { vel.y += 18 * dt; vel.y = min(vel.y, 1.6) } else { vel.y -= 28 * dt } }   // (above 3: a leap out of the water, P49, falling off as a jump does)
        else { vel.y -= 28 * dt }
        // P49: a swimming horse steps up onto a bank level with the water (its feet float below the surface, so the
        // 1.05 step fell short), and a ridden horse is a little narrower so it squeezes between close trunks.
        let swim = Blocks.isLiquid(feet)
        // P164 (Oct 13): a ridden horse squeezes through a 1-block gap (0.35 each side, was 0.45).
        let bodyW = g.riding === self && gaited ? min(halfW, 0.35) : halfW
        let groundedBefore = onGround
        // P164: at a canter or faster it runs straight through low bushes (leaf blocks within two blocks of the
        // ground, no log among them) instead of stopping at them: they are trampled.
        // R14: at any pace (a walk too): small bushes give way to a horse pushing into them.
        if gaitedRide && self.hs.speed > 0.6 { trampleBushes(g, bodyW) }
        let hit = w.moveBody(&pos, halfW: bodyW, height: height, vel * dt, step: swim ? 1.6 : 1.05, onGround: onGround || swim)
        // P49: riding into a canopy put the rider's eyes inside the leaves (a black screen): leaves at head height stop
        // the horse like a wall.
        if g.riding === self {
            func leafy(_ p: V3) -> Bool {
                let e = p + V3(0, height * 0.75 + 1.62, 0)
                return CapitalBase.isLeaf(w.block(Int(floor(e.x)), Int(floor(e.y)), Int(floor(e.z))))
            }
            if leafy(pos) && !leafy(start) {             // (already in leaves: let it ride out)
                pos.x = start.x; pos.z = start.z; vel.x = 0; vel.z = 0
            }
        }
        // R14 (Oct 13: "climb out of water onto equal-height land"): a swimming horse pressing into a bank whose top is
        // within two blocks of its back lunges up onto it (a floating horse's feet sit deeper than the 1.6 step).
        if swim && (hit.x || hit.z) && g.riding === self {
            let ahead = pos + V3(forward.x, 0, forward.z) * (halfW + 0.6)
            for up in 0...2 {
                let y = Int(floor(pos.y)) + up
                let b = w.block(Int(floor(ahead.x)), y, Int(floor(ahead.z)))
                let above = w.block(Int(floor(ahead.x)), y + 1, Int(floor(ahead.z))), above2 = w.block(Int(floor(ahead.x)), y + 2, Int(floor(ahead.z)))
                if Blocks.collide[Int(b)] && !Blocks.collide[Int(above)] && !Blocks.collide[Int(above2)] && !Blocks.isLiquid(above) {
                    vel.y = max(vel.y, sqrtf(2 * 28 * (Float(y + 1) - pos.y + 0.3)))
                    vel.x += forward.x * 1.5; vel.z += forward.z * 1.5
                    break
                }
            }
        }
        var landed = false
        if hit.y { if vel.y < 0 { landed = true }; vel.y = 0 }
        if hit.x { vel.x = 0 }
        if hit.z { vel.z = 0 }
        onGround = landed || (vel.y <= 0 && collides(pos - V3(0, 0.06, 0), w))
        // P147/P166 (the gallop "like a one-cylinder engine"): running off a one-block step it left the ground and fell
        // for a quarter of a second, then thumped down, every step down a hillside. A ridden horse follows the ground
        // down a step of up to 1.1 blocks instead (not a jump, not swimming); the drawn horse and the view ease the
        // drop like a step up (ViewStep), so the ride stays level.
        if gaitedRide && groundedBefore && !onGround && vel.y <= 0 && !swim {
            var p = pos
            let down = w.moveBody(&p, halfW: bodyW, height: height, V3(0, -1.1, 0), step: 0, onGround: false)
            if down.y { pos = p; vel.y = 0; onGround = true }
        }
        if gaitedRide { gaitAfterMove(g, moved: pos - start, hitWall: hit.x || hit.z, dt: dt) }
        let hs = simd_length(V2(vel.x, vel.z))
        // R13: the real cause of the "one-cylinder" gallop: a ridden mount stepped its stride at 3 x speed (a gallop at
        // 14 b/s ran 6.7 strides a second, legs, body and hooves buzzing). A ridden horse keeps a horse's rhythm, about
        // one stride a second at the walk up to ~2.3 at the gallop (Mob.update's free-roaming rate).
        let fam = kind == .horse || kind == .donkey || kind == .mule || kind == .skeletonHorse || kind == .zombieHorse
        if fam { walkPhase += 2 * .pi * min(2.3, 0.85 + 0.105 * hs) * dt * min(1, hs / 0.6) } else { walkPhase += hs * dt * 3 }
        walkAmount += (min(1, hs / 2) - walkAmount) * min(1, dt * 8)
        // P164: under a low overhang (a 2-block-high passage) the rider leans down over the neck instead of putting
        // their head into the block above.
        if gaited {
            let headY = pos.y + height * 0.75 + 1.62 + 0.15
            var want: Float = 0
            for dy: Float in [0, -0.5, -1.0] where Blocks.collide[Int(w.block(Int(floor(pos.x)), Int(floor(headY + dy)), Int(floor(pos.z))))] {
                want = min(1.2, headY - floor(headY + dy) + 0.05); break
            }
            self.hs.duck += (want - self.hs.duck) * min(1, dt * (want > self.hs.duck ? 14 : 4))
        }
        // R13: the saddle rises and falls with the stride (horseBob, 1/16 block), so the rider moves with the horse.
        let lift: Float = fam ? horseBob(self) / 16 : 0
        g.player.pos = pos + V3(0, height * 0.75 - (gaited ? self.hs.duck : 0) + lift, 0)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
    }

    // Leaf blocks just ahead at the horse's legs and chest (feet level and one up): a bush, not a tree (no log in
    // that column within three blocks down). Trampled: removed with a rustle, no drops.
    func trampleBushes(_ g: Game, _ bodyW: Float) {
        let w = g.world
        let f = forward
        let base = Int(floor(pos.y + 0.01))
        for side: Float in [-1, 0, 1] {
            let p = pos + f * (bodyW + 0.45) + V3(-f.z, 0, f.x) * (side * bodyW * 0.9)
            let x = Int(floor(p.x)), z = Int(floor(p.z))
            for y in base...(base + 1) {
                let b = w.block(x, y, z)
                guard CapitalBase.isLeaf(b) else { continue }
                var tree = false
                for d in 0...3 where CapitalBase.isLog(w.block(x, y - d, z)) || CapitalBase.isLog(w.block(x, y + d, z)) { tree = true; break }
                if tree || CapitalBase.isLeaf(w.block(x, base + 3, z)) { continue }      // a canopy reaching down, not a bush
                w.setBlockAsync(x, y, z, AIR)                   // (remeshed off the frame: a gallop through a hedge must not hitch, P169)
                g.particles.blockBreak(b, at: IVec3(x, y, z))
                hs.trampled += 1
            }
        }
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
    // 8 to 17 b/s (was 4.8 to 16: the slow rolls were slower than sprinting on foot, "his horse felt very slow",
    // Oct 11 playtest P26).
    var horseSpeed: Float { 8 + Float((variant >> 4) & 15) / 15 * 9 }
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
            HorseLife.roll(self)                             // a breed: its speed, jump and coat (HorseLife.swift)
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
        case .soldierRecruit, .soldierTrooper, .soldierMarksman, .soldierIronclad, .soldierOfficer, .soldierCrew, .ashMarshal, .ashChancellor: variant = Soldier.pickGun(kind)
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
    static func opens(_ m: Mob) -> Bool { saddleKinds.contains(m.kind) || (m.horseLike && m.chested) || m.saddlebags }
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
        if m.chested || m.saddlebags {
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
            if had && !mob.saddled && game.riding === mob && mob.tamed { game.onToast?("Saddle off") }
        }
        if mob.kind == .horse { mob.armorTier = gear[1].isEmpty ? 0 : (MountMenu.armorTier(Items.key(gear[1].item)) ?? 0) }
        if mob.saddled || mob.armorTier > 0 { mob.persistent = true }
    }
}
