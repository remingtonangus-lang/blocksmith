import Foundation
import simd

// D1: the lasso. A coil of rope (string and a lead) thrown with use at a creature up to 16 blocks away:
//   - a wild horse (or donkey, mule, camel, llama) is caught on the rope like a lead, and fights it less the longer
//     it is held: every two seconds on the rope settles its temper a step, so the calm-down ride that tames it
//     (HorseLife.tameStep) starts calmer; it can't bolt off while you hold it.
//   - an outlaw (a wanted man or his gang, TownBoard/BountyHunters posse marks) is roped: arms pinned, he can't fight or
//     run for 12 seconds and is dragged along on the rope; then he works his way out and the rope falls.
//   - any other animal a lead would hold is led like on a lead.
// The lasso comes back to the pack when the rope is taken off (use the creature again) or falls when it snaps.
enum Lasso {
    static let key = "lasso"
    static let reach: Float = 16
    static let ropeTime: Float = 12
    static var catches = 0
}

extension ItemRegistry {
    func registerLasso() {
        guard !has(Lasso.key) else { return }
        var d = ItemDef(Lasso.key, "Lasso")
        d.sprite = Sprite(mask: "lead", base: 0xC8A46A, extras: [:])
        d.maxStack = 1
        add(d)
    }
}

extension Mob {
    var outlaw: Bool { posse == 1 || posse == 2 }
}

extension Game {
    // Use with the lasso in hand: throw it at the creature in the line of sight.
    func throwLasso() -> Bool {
        guard Items.key(held.item) == Lasso.key else { return false }
        swing = 1
        sfx(.throwItem, 0.8, at: player.eye)
        if let (m, d) = mobs.raycast(player.eye, player.look, maxDist: 4), d < 4, m.leashed, m.roped > 0, Jail.hogtie(self, m) { return true }  // D24
        guard let (m, _) = mobs.raycast(player.eye, player.look, maxDist: Lasso.reach), m.health > 0, !m.leashed, riding !== m else {
            sfx(.fishReel, 0.5, at: player.eye)
            return true
        }
        let horse = m.horseLike && !m.tamed && !m.baby
        guard horse || m.outlaw || m.leashable else { onToast?("The loop slides off"); return true }
        m.leashed = true
        m.lassoed = true
        m.leashSeat = Coop.liveSeat
        m.knot = nil
        m.lassoCalm = 0
        if m.outlaw {
            m.roped = Lasso.ropeTime
            m.aggro = false
            onToast?("Roped! He can't fight or run while the rope holds")
        } else if horse {
            m.panic = max(m.panic, 2)
            onToast?("Caught!")             // P300 (b)
        }
        Lasso.catches += 1
        if survival { consumeHeld() }
        sfx(.armorEquip(0), 0.7, at: m.pos)
        return true
    }
}

extension Mob {
    // From leashTick while on the lasso.
    func lassoTick(_ dt: Float, _ g: Game) {
        if horseLike && !tamed {
            lassoCalm += dt
            if lassoCalm >= 2 {
                lassoCalm = 0
                temper = min(100, temper + 3)
                if temper >= 60 && temper - 3 < 60 { g.onToast?("It's settling on the rope: mount it now") }
            }
        }
    }

    // A roped outlaw's time on the rope (from the behaviour switch: no fighting, no running).
    func ropedTick(_ dt: Float, _ g: Game) {
        roped -= dt
        aggro = false
        if roped <= 0 {
            roped = 0
            if leashed && lassoed { breakLeash(g) }
            g.onToast?("The outlaw worked his way out of the rope")
        }
    }
}
