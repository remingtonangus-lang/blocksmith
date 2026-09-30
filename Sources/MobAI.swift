import Foundation
import simd

// Shared AI goals in the style of the reference goal selectors:
// - Target acquisition: a monster notices the player within its follow range only with line of sight
//   (checked twice a second) and remembers them for 3 s out of sight; being hit locks on for 10 s.
//   Sneaking shortens the range to 80%, a matching mob head halves it, invisibility cuts it to 7 blocks.
// - Avoidance: hissers keep away from cats and ocelots, skeletons from wolves, rabbits and foxes from
//   players and predators, wolves from llamas, ocelots from untrusted players; fleeing beats attacking.
// - Babies follow the nearest adult of their kind; tamed or not, a hurt wolf rallies its pack.
extension MobKind {
    // Reference follow ranges (blocks).
    var followRange: Float {
        switch self {
        case .zombie, .husk, .drowned, .zombieVillager, .zombifiedPiglin: return 35
        case .enderman: return 64
        case .ghast: return 64
        case .blaze: return 48
        case .pillager, .vindicator, .evoker, .ravager: return 32
        case .phantom: return 64
        case .warden: return 24
        default: return 16
        }
    }

    // Head that disguises the player from this kind (reference: halves detection range).
    var disguiseHead: String? {
        switch self {
        case .zombie, .husk, .drowned, .zombieVillager: return "zombie_head"
        case .skeleton, .stray, .bogged: return "skeleton_skull"
        case .creeper: return "creeper_head"
        case .piglin, .piglinBrute: return "piglin_head"
        case .witherSkeleton: return "wither_skeleton_skull"
        default: return nil
        }
    }
}

extension Mob {
    // Whether this mob may go after the player right now (updates the sight memory).
    func senseTarget(_ g: Game, dist: Float, _ dt: Float) -> Bool {
        lockTime -= dt
        sightTimer -= dt
        guard g.survival && g.alive else { lockTime = 0; return false }
        var range = kind.followRange
        if g.player.sneaking { range *= 0.8 }
        if let h = kind.disguiseHead, Items.key(g.inventory.armor[0].item) == h { range *= 0.5 }
        if g.effects.has(.invisibility) { range = min(range, 7) }
        guard dist < range else { return false }
        if sightTimer <= 0 {
            sightTimer = 0.5
            if g.world.canSee(eye, g.player.eye) { lockTime = max(lockTime, 3) }
        }
        return lockTime > 0
    }

    // Something this mob should keep away from, if any (position of the threat).
    func threat(_ g: Game) -> V3? {
        let player = g.player.pos
        let alive = g.alive && g.survival
        func near(_ kinds: Set<MobKind>, _ r: Float, tamedOnly: Bool = false) -> V3? {
            var best: V3?
            var bd = r
            for k in kinds { for o in g.mobs.of(k) where o !== self && o.health > 0 {
                if tamedOnly && !o.tamed { continue }
                let d = simd_length(o.pos - pos)
                if d < bd { bd = d; best = o.pos }
            } }
            return best
        }
        switch kind {
        case .creeper:
            return near([.cat, .ocelot], 6)
        case .skeleton, .stray, .bogged:
            return near([.wolf], 6)
        case .rabbit:
            if alive && simd_length(player - pos) < 8 && !["carrot", "golden_carrot", "dandelion"].contains(Items.key(g.held.item)) { return player }
            return near([.wolf, .fox, .ocelot, .cat], 10)
        case .fox:
            if tamed { return near([.wolf, .polarBear], 8) }
            if alive && !g.player.sneaking && simd_length(player - pos) < 16 { return player }
            return near([.wolf, .polarBear], 8)
        case .ocelot:
            if !tamed && alive && !g.player.sneaking && simd_length(player - pos) < 16
                && !["cod", "salmon"].contains(Items.key(g.held.item)) { return player }
            return nil
        case .wolf:
            if tamed || aggro { return nil }
            return near([.llama, .traderLlama], 8)
        case .piglin:
            return near([.zombifiedPiglin, .zoglin], 6)
        default:
            return nil
        }
    }

    // Babies trail an adult of their kind; returns true when it set a walk target.
    func followParent(_ g: Game) -> Bool {
        guard baby, !spec.aquatic, !spec.flying, kind != .villager, spec.behavior == .passive || spec.behavior == .animal else { return false }
        var best: Mob?
        var bd: Float = 8
        for o in g.mobs.of(kind) where o !== self && !o.baby {
            let d = simd_length(o.pos - pos)
            if d < bd { bd = d; best = o }
        }
        guard let p = best, bd > 3 else { return false }
        face(p.pos)
        moving = true
        return true
    }

    // A hurt wolf's wild pack (or a hurt undead boarling's group) joins in.
    func rallyPack(_ g: Game) {
        if kind == .wolf && !tamed {
            for o in g.mobs.mobs where o !== self && o.kind == .wolf && !o.tamed && simd_length(o.pos - pos) < 16 { o.aggro = true; o.lockTime = 10 }
        }
        if kind == .zombifiedPiglin { provoke(g) }
        callReinforcement(g)
    }

    // Mirage caster (reference illusioner): every 9 s either blinds its target for 20 s or, when the
    // target is already blind, turns itself invisible for a minute (its mirror-image spell).
    func illusionerSpells(_ dt: Float, _ g: Game) {
        spellTimer -= dt
        guard spellTimer <= 0 else { return }
        spellTimer = 9
        if !g.effects.has(.blindness) {
            g.applyEffect(.blindness, amp: 0, seconds: 20)
        } else if !(effects?.has(.invisibility) ?? false) {
            applyEffect(.invisibility, amp: 0, seconds: 60, game: g)
        }
        g.sfx(.evokerCast, 0.9, at: pos)
    }

    // Frost skeletons shoot slowness arrows, mire skeletons poison ones (reference tipped effects).
    func tipArrow(_ a: Arrow) {
        switch kind {
        case .stray: a.tip = Potions.item(3, "slowness") ?? 0
        case .bogged: a.tip = Potions.item(3, "poison") ?? 0
        default: break
        }
        a.pickup = false
    }

    // Sunken with a trident throw it (8 damage) at targets 3-10 blocks away every 2 s.
    func drownedThrow(_ g: Game, dist: Float) -> Bool {
        guard kind == .drowned, let eq = equip, eq.count > 4, Items.key(eq[4].item) == "trident",
              dist > 3, dist < 10, attackCooldown <= 0, g.world.canSee(eye, g.player.eye) else { return false }
        attackCooldown = 2
        var d = g.player.eye - eye
        d.y += simd_length(V2(d.x, d.z)) * 0.12
        let a = g.projectiles.shoot(from: eye + forward * 0.4, dir: simd_normalize(d), speed: 32, fromPlayer: false, damage: 5)
        a.pickup = false
        g.sfx(.bow, 0.8, at: pos)
        return true
    }

    static let voidwalkerHoldable: Set<String> = [
        "grass_block", "dirt", "coarse_dirt", "podzol", "rooted_dirt", "mycelium", "sand", "red_sand", "gravel", "clay", "pumpkin",
        "carved_pumpkin", "melon", "tnt", "cactus", "dandelion", "poppy", "blue_orchid", "allium", "azure_bluet", "oxeye_daisy",
        "cornflower", "lily_of_the_valley", "red_mushroom", "brown_mushroom", "netherrack", "crimson_nylium", "warped_nylium",
        "crimson_fungus", "warped_fungus", "mud", "moss_block", "muddy_mangrove_roots"]

    static func carryColor(_ b: BlockID) -> V3 {
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        if k.contains("grass") || k.contains("moss") || k == "cactus" || k == "melon" { return V3(0.4, 0.62, 0.3) }
        if k.contains("sand") { return V3(0.86, 0.8, 0.6) }
        if k.contains("pumpkin") { return V3(0.85, 0.5, 0.12) }
        if k == "tnt" || k.contains("nylium") || k == "netherrack" { return V3(0.7, 0.2, 0.2) }
        if k == "gravel" || k == "clay" { return V3(0.6, 0.6, 0.62) }
        return V3(0.5, 0.36, 0.24)
    }

    // Voidwalker extras (reference): picks up a holdable block now and then (1/20 per tick at a random
    // nearby spot), sets it down again (1/2000 per tick), and hurts + teleports in rain.
    func voidwalkerTick(_ dt: Float, _ g: Game) {
        let w = g.world
        let c = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
        if g.isRainingAt(pos) && w.lightAt(c.x, c.y + 2, c.z).sky >= 15 {
            fireTick += dt
            if fireTick >= 1 { fireTick = 0; health -= 1; hurt = 0.3; teleport(w) }
        }
        let ticks = dt * 20
        if carriedBlock == 0 {
            guard Float.random(in: 0..<1) < ticks / 20 else { return }
            let q = IVec3(c.x + Int.random(in: -2...2), c.y + Int.random(in: 0...2), c.z + Int.random(in: -2...2))
            let b = w.block(q.x, q.y, q.z)
            guard b != AIR, Mob.voidwalkerHoldable.contains(Blocks.key(Blocks.groupBase[Int(b)])) else { return }
            carriedBlock = Blocks.groupBase[Int(b)]
            w.setBlock(q.x, q.y, q.z, AIR)
        } else {
            guard Float.random(in: 0..<1) < ticks / 2000 else { return }
            let q = IVec3(c.x + Int.random(in: -1...1), c.y + Int.random(in: 0...2), c.z + Int.random(in: -1...1))
            guard w.block(q.x, q.y, q.z) == AIR, Blocks.opaque[Int(w.block(q.x, q.y - 1, q.z))] else { return }
            w.setBlock(q.x, q.y, q.z, carriedBlock)
            carriedBlock = 0
        }
    }

    // Reference eat-grass goal: 1/1000 per tick (1/50 for lambs) a sheep eats the grass at its feet or
    // turns the grass block below to dirt; that regrows its wool and speeds a lamb up by a minute.
    func sheepGraze(_ dt: Float, _ g: Game) {
        guard onGround, panic <= 0, Float.random(in: 0..<1) < dt * 20 / (baby ? 50 : 1000) else { return }
        let w = g.world
        let x = Int(floor(pos.x)), y = Int(floor(pos.y)), z = Int(floor(pos.z))
        if w.block(x, y, z) == TALL_GRASS {
            w.setBlock(x, y, z, AIR)
        } else if w.block(x, y - 1, z) == GRASS {
            w.setBlock(x, y - 1, z, Blocks.id("dirt"))
        } else { return }
        sheared = false
        if baby { age += 60 }
        g.sfx(.step(.plant), 0.5, at: pos)
    }

    // Reference wolf variants by biome: pale, woods, ashen, black, chestnut, rusty, spotted, striped, snowy.
    static let wolfColors: [V3] = [V3(0.8, 0.78, 0.74), V3(0.55, 0.43, 0.32), V3(0.62, 0.62, 0.64), V3(0.18, 0.17, 0.17),
                                   V3(0.5, 0.33, 0.22), V3(0.72, 0.42, 0.2), V3(0.76, 0.62, 0.42), V3(0.6, 0.5, 0.36), V3(0.95, 0.95, 0.95)]
    static func wolfVariant(_ b: Biome) -> Int {
        switch b {
        case .forest: return 1
        case .snowyTaiga: return 2
        case .oldGrowthPineTaiga: return 3
        case .oldGrowthSpruceTaiga: return 4
        case .sparseJungle: return 5
        case .savannaPlateau: return 6
        case .woodedBadlands: return 7
        case .grove: return 8
        default: return 0
        }
    }

    // Reference breeding inheritance: horse stats average both parents and a random roll; pets of a
    // tamed pair are born tame; colour variants come from either parent.
    func inheritFrom(_ a: Mob, _ b: Mob) {
        if horseLike && kind != .llama && kind != .traderLlama && kind != .camel {
            func bits(_ v: Int, _ s: Int) -> Int { (v >> s) & 15 }
            let sp = (bits(a.variant, 4) + bits(b.variant, 4) + Int.random(in: 0...15)) / 3
            let jp = (bits(a.variant, 8) + bits(b.variant, 8) + Int.random(in: 0...15)) / 3
            let colour = (Bool.random() ? a.variant : b.variant) & 15
            variant = colour | (sp << 4) | (jp << 8)
            health = (a.health + b.health + Int.random(in: 15...30)) / 3
        } else if a.kind == b.kind {
            variant = Bool.random() ? a.variant : b.variant
        }
        if a.tamed || b.tamed, [.wolf, .cat, .parrot].contains(kind) { owner = true; persistent = true }
        if kind == .fox { owner = false }                       // trusts the player who bred it
    }

    // Carrying an egg: returns true while it is busy laying (from animalAI).
    func layEgg(_ g: Game) -> Bool {
        guard hasEgg else { return false }
        let w = g.world
        let c = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
        switch kind {
        case .turtle:
            let h = home ?? pos
            if simd_length(V2(h.x - pos.x, h.z - pos.z)) > 2 { face(h); moving = true; return true }
            let below = Blocks.key(w.block(c.x, c.y - 1, c.z))
            if (below == "sand" || below == "red_sand") && w.block(c.x, c.y, c.z) == AIR && Blocks.has("turtle_egg") {
                w.setBlock(c.x, c.y, c.z, Blocks.id("turtle_egg") + BlockID(Int.random(in: 0...3)))
                hasEgg = false
            } else if Float.random(in: 0..<1) < 0.02 { hasEgg = false }
            return true
        case .frog:
            guard let spot = findNearby(w, radius: 8, where: { q in
                Blocks.fluidKind[Int(w.block(q.x, q.y - 1, q.z))] == 1 && w.block(q.x, q.y, q.z) == AIR }) else { return false }
            let t = V3(Float(spot.x) + 0.5, Float(spot.y), Float(spot.z) + 0.5)
            if simd_length(t - pos) > 1.5 { face(t); moving = true; return true }
            if Blocks.has("frogspawn") { w.setBlock(spot.x, spot.y, spot.z, Blocks.id("frogspawn")) }
            hasEgg = false
            return true
        default:
            if Items.has("sniffer_egg") { g.drops.spawn(ItemStack(Items.id("sniffer_egg"), 1), at: pos + V3(0, 0.5, 0)) }
            hasEgg = false
            return false
        }
    }
}

extension Game {
    // Tamed wolves go after what their owner hits and whatever hurts the owner (never hissers, Wailers
    // or other pets).
    func petsAttack(_ t: Mob) {
        guard t.health > 0, !(t.tamed && (t.kind == .wolf || t.kind == .cat || t.kind == .parrot)), t.kind != .creeper, t.kind != .ghast else { return }
        if t.kind.category == .misc && t.kind != .ironGolem && t.kind != .villager { return }
        for w in mobs.of(.wolf) where w.tamed && !w.sitting && simd_length(w.pos - player.pos) < 16 { w.target = t }
    }

    // Morning gifts: a tamed cat near the sleeping player leaves one 70% of the time (reference morning
    // gift table: rabbit hide / rabbit foot / raw chicken / feather / rotten flesh / string, rarely a membrane).
    func catGifts() {
        for c in mobs.of(.cat) where c.tamed && simd_length(c.pos - player.pos) < 16 && Float.random(in: 0..<1) < 0.7 {
            let table: [(String, Float)] = [("rabbit_hide", 0.1613), ("rabbit_foot", 0.3226), ("chicken", 0.4839), ("feather", 0.6452),
                                             ("rotten_flesh", 0.8065), ("string", 0.9677), ("phantom_membrane", 1)]
            let r = Float.random(in: 0..<1)
            let name = table.first { r < $0.1 }?.0 ?? "string"
            if Items.has(name) { drops.spawn(ItemStack(Items.id(name), 1), at: player.pos + V3(0, 0.5, 0)) }
            c.pos = player.pos + V3(Float.random(in: -1...1), 0, Float.random(in: -1...1))
        }
    }
}
