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
}
