import Foundation
import simd

// The sheriff's six-iron and the iron rule (backlog B1; docs/status/six-iron.md).
//
// Every sheriff carries a six-iron. Against the player it is the iron rule made physical: below iron armour one round
// kills, in iron it takes several, in titanium (the diamond tier) and above it barely scratches. So the game's spine
// holds: play by the rules until you're in iron, ideally titanium, and only then can a town be taken.
//
// The duel is readable and fair in VR:
//   draw:    on his challenge he draws (the gun comes out of the holster, a hammer click) and only fights 2.5 s later.
//   warning: his first round in a fight goes over your head (a whizz and "That's your warning.").
//   aim:     each shot is telegraphed: he raises his arm level at you with a click and fires `aimTime` later at where
//            you were when he took aim. Step aside, duck or get behind cover in that window and it misses; stand still
//            and it hits (a small spread that grows with range keeps long shots honest).
//   reload:  after six rounds he reloads for `reloadTime` (the window to close in).
// Damage bypasses the ordinary armour formula and uses the table below instead (difficulty still matters: none on
// peaceful). A raised shield still blocks a round (and wears for it).
enum SixIron {
    static let reach: Float = 22                 // blocks: deadly at range
    static let aimTime: Float = 0.65             // seconds from the telegraph to the shot
    static let cooldown: Float = 1.1             // seconds between a shot and the next telegraph
    static let reloadTime: Float = 2.4
    static let rounds = 6
    static let lethal = 999                      // "one shot": past every reduction (only a totem saves you)
    static let chase: Float = 64                 // an angry sheriff comes for a player he can see this far off
    static let calmReset: Double = 45            // seconds without a duel before the next fight opens with a warning

    // MARK: The iron rule

    // How protective the worn armour is, on a scale where a full iron set is 1.0 and a full titanium set ~2.3. Each
    // piece counts its points against an iron piece in the same slot, plus half its toughness, weighted by how much of
    // the body the slot covers. Generic, so any armour (steel, copper, Duskium, a turtle shell) lands where it belongs.
    static let ironPoints: [Float] = [2, 6, 5, 2]          // head, chest, legs, feet
    static let slotWeight: [Float] = [0.2, 0.35, 0.3, 0.15]
    static func armourScore(_ pieces: [ItemStack]) -> Float {
        var s: Float = 0
        for (i, p) in pieces.prefix(4).enumerated() where !p.isEmpty && p.def.armorSlot != nil {
            s += slotWeight[i] * (Float(p.def.armor) / ironPoints[i] + 0.5 * p.def.toughness)
        }
        return s
    }

    enum Tier: String { case soft = "below iron", iron = "iron", hard = "titanium and up" }
    static let ironFrom: Float = 0.9             // a full iron set with leather boots still counts as iron
    static let hardFrom: Float = 1.9             // titanium missing its helmet is still the iron tier
    static func tier(_ score: Float) -> Tier { score < ironFrom ? .soft : score < hardFrom ? .iron : .hard }

    // Half-hearts one round takes off (before a shield or the Resistance effect), by armour and difficulty
    // (0 peaceful ... 3 hard). Normal difficulty, 20 half-hearts of health:
    //   below iron:        dead in one shot
    //   iron (1.0):        8   -> 3 shots
    //   steel (~1.5):      6   -> 4 shots
    //   titanium (~2.3):   1   -> 20 shots (chip damage)
    static func damage(score: Float, difficulty: Int) -> Int {
        guard difficulty > 0 else { return 0 }
        switch tier(score) {
        case .soft: return lethal
        case .iron:
            let k = (score - ironFrom) / (hardFrom - ironFrom)          // 0 at the bottom of iron, 1 at the top
            let base = 8.5 - 5.5 * k                                     // 8.5 -> 3
            let m: Float = difficulty == 1 ? 0.65 : difficulty == 3 ? 1.35 : 1
            return max(2, Int((base * m).rounded()))
        case .hard:
            return difficulty == 3 ? 2 : 1
        }
    }

    // The table the docs quote (normal difficulty), from the code itself.
    static func table() -> [(String, Float, Int)] {
        let sets: [(String, String?)] = [("no armour", nil), ("leather", "leather"), ("golden", "golden"), ("chainmail", "chainmail"),
                                         ("copper", "copper"), ("iron", "iron"), ("steel", "steel"), ("titanium", "diamond"), ("Duskium", "netherite")]
        return sets.map { (name, mat) in
            let s = mat.map { armourScore(fullSet($0)) } ?? 0
            return (name, s, damage(score: s, difficulty: 2))
        }
    }
    static func fullSet(_ mat: String) -> [ItemStack] {
        ["helmet", "chestplate", "leggings", "boots"].map { p in
            let k = mat == "leather" && p == "helmet" ? "leather_helmet" : "\(mat)_\(p)"
            return Items.has(k) ? ItemStack(Items.id(k), 1) : .empty
        }
    }

    // MARK: The duel (Mob.townDefend, a sheriff fighting the player)

    // Returns the walk speed while engaged.
    static func duel(_ m: Mob, _ dt: Float, _ g: Game) -> Float {
        let target = g.player.pos
        let dist = simd_length(V2(target.x - m.pos.x, target.z - m.pos.z))
        m.face(target)
        // A fight after a long calm starts with a warning again; a short break (ducking out of sight) doesn't.
        if g.clock - m.town.lastDuel > calmReset { m.town.warned = false }
        m.town.lastDuel = g.clock
        // Reloading: stands and thumbs rounds in.
        if m.town.reload > 0 {
            m.town.reload -= dt
            if m.town.reload <= 0 { m.town.fired = 0 }
            m.moving = dist > reach * 0.7
            return m.moving ? m.spec.speed * 1.2 : 0
        }
        if m.town.aim > 0 {
            m.town.aim -= dt
            m.moving = false
            if m.town.aim <= 0 { fire(m, g) }
            return 0
        }
        // Closes to a comfortable range, then holds (he comes for a player sniping from further off, up to `chase`).
        m.moving = dist > reach * 0.6
        let chest = g.player.pos + V3(0, (g.player.eye.y - g.player.pos.y) * 0.72, 0)
        if m.attackCooldown <= 0 && dist < reach && abs(target.y - m.pos.y) < 20 && g.world.clearShot(muzzle(m), chest) {
            m.town.aim = aimTime
            // He leads a moving target most of the way (75-100% of where your run takes you in the aim time): running
            // steadily one way gets you hit, changing direction or stopping in the window makes him miss.
            var v = g.player.vel; v.y = 0
            m.town.aimAt = chest + v * aimTime * Rand.float(in: 0.75...1.0)
            m.moving = false
            g.sfx(.gunReload(WeaponAudio.sidearmSlot), 0.55, at: m.eye)                             // the hammer click
            telegraphs += 1
            return 0
        }
        return m.moving ? m.spec.speed * 1.35 : 0
    }

    static func muzzle(_ m: Mob) -> V3 { m.eye + m.forward * 0.5 + V3(0, -0.2, 0) }

    static func fire(_ m: Mob, _ g: Game) {
        m.attackCooldown = cooldown
        m.town.swing = 0.3                                                   // the recoil kick (TownsfolkModel)
        m.town.fired += 1
        if m.town.fired >= rounds { m.town.reload = reloadTime; g.sfx(.gunReload(WeaponAudio.sidearmSlot), 0.7, at: m.eye) }
        let o = muzzle(m)
        g.sfx(.gun(WeaponAudio.sidearmSlot), 1, at: o)
        g.particles.smoke(at: o)
        shots += 1
        var aim = m.town.aimAt
        if !m.town.warned {
            // The warning shot: a round over your head.
            m.town.warned = true
            aim.y += 1.6
            g.sfx(.bulletWhizz, 0.9, at: g.player.eye)
            Townsfolk.townLastLine = -100
            Townsfolk.say(g, m, ["That's your warning.", "Next one won't miss.", "Hands where I can see 'em!"][Int(m.villager?.look ?? 0) % 3])
            warnings += 1
            return
        }
        let to = aim - o
        let len = simd_length(to)
        guard len > 0.01 else { return }
        let spread = 0.006 + 0.0009 * len                                   // radians: tight up close, looser far off
        var d = to / len + V3(Rand.float(in: -1...1), Rand.float(in: -1...1), Rand.float(in: -1...1)) * spread
        d = simd_normalize(d)
        let reachLen = len + 3
        guard let t = Armory.playerHit(g, o, d, reachLen), g.world.clearShot(o, o + d * max(0, t - 0.05)) else {
            // A miss: the round cracks past if it went near.
            let closest = simd_length(simd_cross(g.player.eye - o, d))
            if closest < 2.5 { g.sfx(.bulletWhizz, 0.8, at: g.player.eye) }
            misses += 1
            return
        }
        g.sixIronHit(by: m, at: o + d * t)
    }

    // Tests and the perf overlay.
    static var shots = 0, misses = 0, warnings = 0, telegraphs = 0
}

extension Game {
    // A six-iron round that found the player.
    func sixIronHit(by m: Mob, at p: V3) {
        guard survival, alive, health > 0 else { return }
        let amount = SixIron.damage(score: SixIron.armourScore(inventory.armor.slots), difficulty: difficulty)
        guard amount > 0 else { return }
        CombatHUD.shared.hurt(self, from: m.pos, amount: min(amount, 20))
        petsAttack(m)
        if shieldBlocks(min(amount, 20), from: m.pos, type: .projectile, attacker: m) { return }
        bulletHit = true
        sfx(.bulletFlesh, 0.9)
        let title = m.villager?.role == "deputy" ? "Deputy" : "Sheriff"
        let who = m.villager?.person.map { "\(title) \($0)" } ?? "the \(title.lowercased())"
        if amount == SixIron.lethal {
            // Below iron: no enchantment, Resistance or golden hearts soften it; only a totem pulls you through.
            Game.onDamage?(health, "was shot by \(who)")
            hurtFlash = 0.35
            sfx(.hurt, 1)
            health = 0
            absorption = 0
            if !useTotem() { die("was shot by \(who)") }
        } else {
            damage(amount, "was shot by \(who)", bypassArmor: true, type: .projectile, attacker: m)
        }
        bulletHit = false
        // Armour still takes the round's wear (the ordinary formula, skipped above, is where it would have).
        for i in 0..<4 where !inventory.armor[i].isEmpty && inventory.armor[i].def.durability > 0
            && !["elytra", "jetpack"].contains(Items.key(inventory.armor[i].item)) {
            var s = inventory.armor[i]
            if Enchant.wearSkipped(s) { continue }
            let was = s
            s.damage += 2
            wearNote(was, s, uses: false)                           // Q2c-console-36
            inventory.armor[i] = s.damage >= s.def.durability ? .empty : s
        }
        var k = player.pos - m.pos
        k.y = 0
        let l = simd_length(k)
        if l > 0.01 { player.vel += k / l * 1.6 + V3(0, 1, 0) }
    }
}
