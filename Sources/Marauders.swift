import Foundation
import simd

// P366 (b) (Oct 17: "the bandits at the watchtower camp are underdeveloped: poor AI and poor looks, bring them up to the
// soldier standard"): the watchtower camp's marauders are gunmen on the soldier rig and the soldier AI (cover, ranks,
// flanking, reloads, the officer's calls), as the bounty hunters are: a dusty canvas coat, a wide-brimmed hat and a red
// bandana over the face, frontier arms. They belong to no faction and fight the player (Mob.posse = Marauders.posse,
// saved). The camp's leader is an officer with a six-iron.
enum Marauders {
    static let posse = 8
    static let name = "Marauder"
    // Rank by roll: a recruit (six-iron or carbine), a trooper (scattergun), a marksman (bolt rifle); one leader per camp.
    static func kind(_ roll: Int) -> MobKind { [MobKind.soldierRecruit, .soldierTrooper, .soldierRecruit, .soldierMarksman][roll & 3] }

    static func isMarauder(_ m: Mob) -> Bool { m.posse == posse }

    static func dress(_ m: Mob) {
        m.posse = posse
        m.customName = name
        m.spec.name = name
        m.spec.drops = [("bread", 0, 1), ("leather", 0, 1), ("gold_nugget", 0, 2)]
        if Soldier.rank(m.kind) != nil {
            switch m.kind {
            case .soldierOfficer: m.variant = Guns.revolver
            case .soldierTrooper: m.variant = Guns.shotgun
            case .soldierMarksman: m.variant = Guns.kessel
            default: m.variant = m.coatRoll(5) < 0.5 ? Guns.revolver : Guns.sturmwind
            }
            if let b = m.brain { b.gun = m.variant; b.mag = Guns.all[m.variant].mag }
        }
    }

    static func make(_ kind: MobKind, at p: V3) -> Mob {
        let m = Mob(kind, at: p)
        dress(m)
        m.home = p
        return m
    }
}
