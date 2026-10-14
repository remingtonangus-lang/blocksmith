import Foundation
import simd

// D13 saloon brawls. Throw a punch (an empty hand) at a townsperson in a saloon and it's a fist fight, not a crime:
// they put their fists up and come at you, and a regular or two at the bar may join in. Nobody draws, the law stays
// out of it and no honour is lost. Fists only, both ways, and nobody dies of it:
//   a brawler beaten to the floor is knocked out cold for 20 s (they lie there, then get up sore but fine)
//   you, beaten down to two hearts, are laid out yourself: the brawl ends and they go back to their drinks
// A blade or a gun turns it into an assault like anywhere else (TownLaw). The fight is over when nobody is left on
// their feet against you, or after 40 s of nobody landing a blow.
enum Brawls {
    static let length: Float = 40
    static let outFor: Float = 20
    static let joinChance: Float = 0.35
    static let playerFloor = 4                        // the player is laid out at two hearts
    static var started = 0, knockouts = 0             // (tests)

    // Near a barkeep: inside a saloon (or right outside it).
    static func inSaloon(_ g: Game, _ p: V3) -> Bool {
        g.mobs.mobs.contains { $0.kind == .villager && $0.villager?.shop == ShopKind.saloon.rawValue && simd_length($0.pos - p) < 14 }
    }

    static func fighter(_ m: Mob) -> Bool {
        m.kind == .villager && m.health > 0 && !m.baby && m.villager?.role != "child" && !TownLaw.isLaw(m)
            && m.villager?.shop != ShopKind.saloon.rawValue
    }

    // townAlarm: a punch thrown in a saloon starts (or carries on) a brawl instead of an assault.
    static func start(_ g: Game, _ victim: Mob) -> Bool {
        guard g.held.isEmpty, simd_length(victim.pos - g.player.pos) < 4.5, fighter(victim), victim.town.anger <= 0,
              inSaloon(g, victim.pos) else { return false }
        if victim.town.out > 0 { return true }                      // (a punch at a man out cold: no harm done)
        if victim.town.brawl <= 0 {
            started += 1
            g.onToast?("A brawl! Fists only")
            TownVoice.speak(g, victim, .angry)
            for o in g.mobs.mobs where o !== victim && fighter(o) && o.town.brawl <= 0 && o.town.out <= 0
                && simd_length(o.pos - victim.pos) < 6 && Rand.float(in: 0..<1) < joinChance {
                o.town.brawl = length
                if o.lying { o.wake(g) }
            }
        }
        victim.town.brawl = length
        if victim.lying { victim.wake(g) }
        return true
    }

    // Mob.hit: a blow that would finish a brawler knocks them out instead. True when the blow was absorbed.
    static func absorb(_ m: Mob, _ damage: Int) -> Bool {
        if m.town.out > 0 { return Mob.playerMelee }                // nobody kicks a man when he's down (fists or not)
        guard m.town.brawl > 0, Mob.playerMelee, m.health - damage <= 0 else { return false }
        m.health = max(1, m.health / 2 + 1)
        m.town.brawl = 0
        m.town.out = outFor
        m.sitting = true
        m.lying = true
        m.vel = .zero
        knockouts += 1
        if let g = Mob.meleeGame { g.onToast?("\(m.villager?.person ?? "They")'s out cold"); g.sfx(.attackKnockback, 0.8, at: m.pos) }
        return true
    }

    // Mob.update (townsfolk), before the routine: the brawl and the knock out. nil when neither applies.
    static func step(_ m: Mob, _ dt: Float, _ g: Game) -> Float? {
        if m.town.out > 0 {
            m.town.out -= dt
            m.vel.x = 0; m.vel.z = 0
            if m.town.out <= 0 { m.lying = false; m.sitting = false; m.pos.y += 0.1 }
            return 0
        }
        guard m.town.brawl > 0 else { return nil }
        m.town.brawl -= dt
        m.town.swing = max(0, m.town.swing - dt)
        guard g.alive, simd_length(m.pos - g.player.pos) < 24 else { m.town.brawl = 0; return nil }
        m.face(g.player.pos)
        let d = simd_length(V2(g.player.pos.x - m.pos.x, g.player.pos.z - m.pos.z))
        if d > 1.3 { return 3.0 }
        m.town.punch -= dt
        if m.town.punch <= 0 {
            m.town.punch = Rand.float(in: 0.9...1.4)
            m.town.swing = 0.35
            if g.survival && g.health > playerFloor {
                g.hurtPlayer(1, from: m.pos, cause: "was knocked cold in a saloon brawl", knockback: 0.5)
                if g.health <= playerFloor { laidOut(g) }
            }
            g.sfx(.attackWeak, 0.7, at: m.pos)
        }
        return 0
    }

    static func laidOut(_ g: Game) {
        for o in g.mobs.mobs where o.town.brawl > 0 { o.town.brawl = 0 }
        g.onToast?("You're laid out on the boards. The brawl's over")
    }
}
