import Foundation
import simd

// Spears: one per tool tier (wooden ... duskium), crafted from the tier material and two sticks in a diagonal.
// - Jab (attack): a longer reach than a sword (4.5 blocks against 3.5), a little less damage and a slower swing.
// - Charge (hold use): after a short wind-up the spear is levelled for a few seconds; any mob it meets while the
//   player (or their mount) closes on it at 4+ blocks/s takes damage that grows with the closing speed and is
//   knocked back. Later in the hold the arm tires and the spear only shoves; after that it does nothing until
//   the use button is let go. Each mob can be struck once per half second.
enum Spear {
    // Per tier, in Items' tier order: wooden, stone, iron, golden, diamond, duskium, copper.
    static let jabDamage: [Float] = [3, 4, 5, 3, 6, 7, 4]          // ... copper last (Items' tier list)
    static let jabSpeed: [Float] = [1.1, 1.1, 1.0, 1.2, 1.0, 1.0, 1.1]
    static let reach: Float = 4.5
    static let windUp: Float = 0.25
    static let engaged: Float = 3.25      // charge deals damage until here (seconds of holding)
    static let tired: Float = 7.25        // then only knocks back until here
    static let minSpeed: Float = 4

    static func isSpear(_ item: ItemID) -> Bool { item != 0 && Items.key(item).hasSuffix("_spear") }

    // Damage of a charge hit at closing speed `v` (blocks/s) for a spear with jab damage `jab`.
    static func chargeDamage(jab: Float, speed v: Float) -> Int {
        let k: Float = 0.45 + 0.09 * min(v, 16)
        return max(1, Int((jab * k).rounded()))
    }
}

extension Game {
    // Hold use with a spear: the charge attack. Returns true while it owns the use button.
    func spearUse(_ useHeld: Bool, _ dt: Float) -> Bool {
        guard Spear.isSpear(held.item) else {
            if spearCharge > 0 { spearCharge = 0; spearHitAt.removeAll(keepingCapacity: true) }
            return false
        }
        guard useHeld else {
            if spearCharge > 0 { spearCharge = 0; spearHitAt.removeAll(keepingCapacity: true) }
            return false
        }
        if spearCharge == 0 { sfx(.tridentThrow, 0.35) }              // levelled
        spearCharge += dt
        let t = spearCharge
        guard t >= Spear.windUp && t < Spear.tired else { return true }
        let look = player.look
        let myVel = riding?.vel ?? player.vel
        let jab = held.def.attack
        for m in mobs.mobs where m.health > 0 && m !== riding && m.kind != .villager && m.kind.spec.behavior != .vehicle {
            let c = m.pos + V3(0, m.height * 0.5, 0)
            let to = c - player.eye
            let d = simd_length(to)
            guard d > 0.3, d < Spear.reach + m.spec.halfW else { continue }
            let dir = to / d
            guard simd_dot(dir, look) > 0.9 else { continue }                       // within ~25 degrees of the point
            let closing = simd_dot(myVel - m.vel, dir)
            guard closing >= Spear.minSpeed else { continue }
            let id = ObjectIdentifier(m)
            if let last = spearHitAt[id], t - last < 0.5 { continue }
            guard world.canSee(player.eye, c) else { continue }
            spearHitAt[id] = t
            if t < Spear.engaged {
                var dmg = Spear.chargeDamage(jab: jab, speed: closing)
                dmg += Int(Enchant.damageBonus(held, against: m).rounded())
                m.hit(from: player.pos, damage: dmg, knockback: 1 + min(closing, 16) * 0.08)
                m.killedByPlayer = true
                m.lootingLevel = Enchant.level(.looting, held)
                particles.crit(at: c)
                sfx(.attackKnockback, 0.9, at: c)
                damageHeld(1)
            } else {
                m.hit(from: player.pos, damage: 0, knockback: 1.1)                  // tired: a shove
                sfx(.attackWeak, 0.6, at: c)
            }
            m.provoke(self)
            swing = 1
            if survival { exhaustion += 0.1 }
        }
        return true
    }
}
