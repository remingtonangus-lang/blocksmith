import Foundation
import simd

// P504 (Nov 1 07:55:57, at a Capital Dropship's helm: "Ship also needs a place to refill ammunition that you craft"): a war
// vessel's guns draw on her magazine (P483: a dropship's 600 rounds, a frigate's 40 a barrel, a crawler's 30), and an
// empty one stayed empty. A Shell Crate (two iron, two gunpowder, a copper ingot) used anywhere aboard her goes into
// the magazine: a quarter of a full load a crate, never past full.
enum ShipShells {
    static let key = "shell_crate"
    static let name = "Shell Crate"
    static let share: Float = 0.25

    static func register(_ reg: ItemRegistry) {
        guard !reg.has(key) else { return }
        var d = ItemDef(key, name)
        d.texKey = "item_" + key
        d.maxStack = 16
        _ = reg.add(d)
    }

    static func recipe() -> Recipe? { Recipes.shapeless(["iron_ingot", "iron_ingot", "gunpowder", "gunpowder", "copper_ingot"], key, 1) }

    static let icon = ["................", "................", "....b...b...b...", "...bbb.bbb.bbb..", "...yyy.yyy.yyy..",
                       "...yyy.yyy.yyy..", ".11111111111111.", ".1aaaaaaaaaaaa1.", ".1a1aaaaaaaa1a1.", ".1aa1aaaaaa1aa1.",
                       ".1dddddddddddd1.", ".1aa1aaaaaa1aa1.", ".1a1aaaaaaaa1a1.", ".1aaaaaaaaaaaa1.", ".11111111111111.", "................"]

    // The magazine's full load, and what a crate puts in.
    static func full(_ ships: ShipManager, _ r: Ship) -> Int {
        Capital.magazine(r, barrels: ([r] + ships.turrets(of: r)).reduce(0) { $0 + $1.cannons.count })
    }
}

extension Game {
    // True when the use was taken (a war vessel under him); a full magazine or a hull that has none says so.
    func loadShells(_ s: Ship) -> Bool {
        let ships = world.ships, r = s.root
        guard r.kinematic && r.role != nil, let st = ships.capState[r.id] else {
            onToast?("This vessel has no magazine"); sfx(.click, 0.5); return true
        }
        let full = ShipShells.full(ships, r)
        if st.rounds < 0 { st.rounds = full }
        guard st.rounds < full else { onToast?("The magazine is full: \(st.rounds) rounds"); sfx(.click, 0.5); return true }
        st.rounds = min(full, st.rounds + max(1, Int((Float(full) * ShipShells.share).rounded(.up))))
        consumeHeld()
        sfx(.gun(6), 0.9)                                  // (the reload's clack: the crate's shells go in)
        onToast?("Magazine: \(st.rounds) rounds")
        return true
    }
}
