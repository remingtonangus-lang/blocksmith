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
    // P507 (Nov 1 12:11:04, aboard a crawler: "Should also be a place to fill up the guns inside... like a battery"): a
    // Shell Hoist, the racked rounds by a war vessel's guns. Used, it takes every Shell Crate in his pack that the
    // magazine has room for (a crate in the hand goes in too, as anywhere aboard), and says what the magazine holds.
    static let hoistKey = "shell_hoist"

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

extension BlockRegistry {
    func registerShellHoist() {
        guard !has(ShipShells.hoistKey) else { return }
        var d = BlockDef(ShipShells.hoistKey, "Shell Hoist")
        d.tex = ["shell_hoist_side", "shell_hoist_side", "shell_hoist_top", "ship_metal", "shell_hoist_side", "shell_hoist_side"]
        d.hardness = 5; d.resistance = 8; d.tool = .pickaxe; d.requiresTool = true; d.sound = .metal
        add(d)
    }
}

extension TextureGen {
    static func shellHoistPainters(_ p: inout [String: Painter]) {
        // A dark steel cabinet with three racks of brass shells, their red tips out.
        p["shell_hoist_side"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x2A2E33) }
            if y % 5 == 0 { return hex(0x3C4248) }                                    // the rack shelves
            let col = (x - 1) % 3
            if col == 2 { return hex(0x1C1F22) }
            if y % 5 == 1 { return hex(0xA8322A) }                                    // the tips
            return hex(0xB89340, 0.85 + 0.15 * r(x, y, 5071))                         // brass
        }
        p["shell_hoist_top"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x2A2E33) }
            let dx = Float(x % 5) - 2, dy = Float(y % 5) - 2
            return dx * dx + dy * dy <= 2.5 ? hex(0xA8322A) : hex(0x3C4248)
        }
    }
}

extension Game {
    // P507: a shell hoist used aboard: the crates he carries go into the magazine while there's room.
    func useShellHoist(_ s: Ship) {
        let ships = world.ships, r = s.root
        guard r.kinematic && r.role != nil, let st = ships.capState[r.id] else { onToast?("This vessel has no magazine"); sfx(.click, 0.5); return }
        let full = ShipShells.full(ships, r)
        if st.rounds < 0 { st.rounds = full }
        let per = max(1, Int((Float(full) * ShipShells.share).rounded(.up)))
        var loaded = 0
        let crate = Items.id(ShipShells.key)
        for i in inventory.main.indices where inventory.main[i].item == crate && !inventory.main[i].isEmpty {
            while st.rounds < full && inventory.main[i].count > 0 {
                st.rounds = min(full, st.rounds + per)
                inventory.main[i].count -= 1
                loaded += 1
            }
            if inventory.main[i].count <= 0 { inventory.main[i] = .empty }
            if st.rounds >= full { break }
        }
        if loaded > 0 { sfx(.gun(6), 0.9) } else { sfx(.click, 0.5) }
        onToast?(loaded > 0 ? "Magazine: \(st.rounds) of \(full) rounds (\(loaded) crate\(loaded == 1 ? "" : "s") in)" : "Magazine: \(st.rounds) of \(full) rounds")
    }
}
