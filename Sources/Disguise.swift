import Foundation
import simd

// D37: disguise in a looted uniform. A full faction armour kit (FactionArmour.swift: Greywall field kit, Capital
// officer's kit, Ashguard ember kit) passes you for one of that army's own: its calm soldiers don't mark you, so you
// can walk through their bases, garrison towns and patrols. What gives you away:
//   a close look   standing within 3 blocks of one of them for 3 seconds: "You're not one of ours!"
//   anything loud  a shot, a blow or the base's alarm: whoever is already after you stays after you (a soldier that
//                  has turned on you is no longer fooled).
// Once blown, that army knows your face for two minutes, kit or no kit.
enum Disguise {
    static let inspect: Float = 3, near: Float = 3
    static let blownFor: Double = 120
    static var blownAt: [Int: Double] = [:]               // faction -> when it saw through you (not saved)
    static var close: Float = 0
    static var blows = 0                                  // (harness)

    static func faction(of kit: String) -> Faction? {
        switch kit {
        case "greywall": return .greywall
        case "capital": return .steelhold
        case "ashguard": return .ashguard
        default: return nil
        }
    }
    static func wearing(_ g: Game) -> Faction? { FactionArmour.worn(g).flatMap { faction(of: $0.key) } }

    // soldierAI's canTarget: this soldier takes you for one of his own.
    static func covers(_ g: Game, _ m: Mob) -> Bool {
        guard !m.aggro, let f = wearing(g), m.factionValue == f else { return false }
        if let t = blownAt[Int(f.rawValue)], g.clock - t < blownFor { return false }
        return true
    }

    // Once a second (TownLaw.tick): a close look.
    static func tick(_ g: Game, _ dt: Float) {
        guard let f = wearing(g) else { close = 0; return }
        let looking = g.mobs.mobs.contains { $0.factionValue == f && $0.health > 0 && Soldier.rank($0.kind) != nil
            && simd_length($0.pos - g.player.pos) < near && g.world.canSee($0.eye, g.player.eye) }
        close = looking ? close + dt : 0
        guard close >= inspect else { return }
        close = 0
        blownAt[Int(f.rawValue)] = g.clock
        blows += 1
        for m in g.mobs.mobs where m.factionValue == f && m.health > 0 && simd_length(m.pos - g.player.pos) < 24 {
            m.aggro = true; m.lockTime = max(m.lockTime, 20)
        }
        g.onToast?("\"Hey! You're not one of ours!\" Your disguise is blown")
    }
}
