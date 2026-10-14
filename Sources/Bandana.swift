import Foundation
import simd

// D22: a bandana mask, so masked crimes cannot be pinned on the player.
// Objectives:
//  - A Bandana (cloth worn in the head slot; 2 string and a red or black dye... made from any wool and a string).
//  - Masked, a witnessed crime still sets the town on him in the moment (heat, hostility, lawmen), but no honour is
//    lost and no bounty is posted: the town doesn't know who it was. What it would have cost is held for that town.
//  - Taking the mask off where townsfolk of a town still hot about it can see him (within 24 blocks, in sight) pins
//    it on him at once: the held honour and bounty land, with a toast. Once the town has calmed down (no heat, no
//    hostility) the held cost is dropped: he got away with it.
enum Bandana {
    static var held: [String: (honour: Float, bounty: Int)] = [:]
    static var wasMasked = false
    static var pinned = 0, escaped = 0
    static let key = "bandana"

    static func masked(_ g: Game) -> Bool {
        let h = g.inventory.armor[ArmorSlot.head.rawValue]
        return !h.isEmpty && Items.key(h.item) == key
    }
    static func hold(_ town: String, honour: Float, bounty: Int) {
        var e = held[town] ?? (0, 0)
        e.honour += honour; e.bounty += bounty
        held[town] = e
    }

    // Once a second (TownLaw.tick).
    static func tick(_ g: Game) {
        let now = masked(g)
        defer { wasMasked = now }
        guard !held.isEmpty else { return }
        for (town, _) in held where TownLaw.heat(town) <= 0.01 && !TownLaw.isHostile(town) {
            held[town] = nil; escaped += 1
        }
        guard wasMasked && !now else { return }
        // Unmasked: anyone of a town still hot about it who can see him knows him now.
        for m in g.mobs.mobs where TownLaw.isTownsperson(m) && m.health > 0 && simd_length(m.pos - g.player.pos) < 24 {
            let town = TownLaw.town(of: m, g)
            guard let e = held[town], g.world.canSee(m.eye, g.player.eye) else { continue }
            held[town] = nil
            pinned += 1
            Honour.change(g, -e.honour, "unmasked in \(town)")
            Honour.addBounty(g, town, e.bounty)
            m.face(g.player.pos)
            g.onToast?("They saw your face: \(town) knows it was you")
        }
    }
}
