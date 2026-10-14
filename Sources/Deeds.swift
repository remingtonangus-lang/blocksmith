import Foundation
import simd

// D21: townsfolk react to his deeds and how he looks.
// Objectives:
//  - Each kill bloodies him: a beast or monster a little, a person (townsfolk, soldier, outlaw, hunter) a lot. The
//    blood fades over 3 minutes, faster in rain or water.
//  - Townsfolk see it (TownLines keys "bloody" / "killer", urgent), his armour (2+ pieces of metal armour: "armoured")
//    and a bandana mask ("masked"), and say so.
enum Deeds {
    static var blood: Float = 0          // 0...1
    static var person: Float = 0         // the share of it from people
    static var lastClock: Double = 0

    static func killed(_ g: Game, _ m: Mob) {
        let human = m.kind == .villager || m.kind.steelhold || m.kind.ash || m.posse != 0 || m.kind == .pillager || m.kind == .vindicator
        blood = min(1, blood + (human ? 0.6 : (m.kind.hostile ? 0.15 : 0.25)))
        if human { person = min(1, person + 0.6) }
    }
    static func fade(_ g: Game) {
        let dt = Float(max(0, min(1, g.clock - lastClock)))
        lastClock = g.clock
        let wet: Float = g.player.inWater ? 12 : (g.isRainingAt(g.player.pos) ? 3 : 1)
        blood = max(0, blood - dt / 180 * wet)
        person = min(person, blood)
    }
    static func bloody(_ g: Game) -> Bool { fade(g); return g.survival && blood > 0.2 }
    static func killedPerson(_ g: Game) -> Bool { person > 0.3 }
    static func armoured(_ g: Game) -> Bool {
        g.inventory.armor.slots.filter { s in
            guard !s.isEmpty else { return false }
            let k = Items.key(s.item)
            return k.hasPrefix("iron_") || k.hasPrefix("diamond_") || k.hasPrefix("netherite_") || k.hasPrefix("chainmail_") || k.contains("plate") || k.contains("troop")
        }.count >= 2
    }
    static func masked(_ g: Game) -> Bool { Bandana.masked(g) }
}
