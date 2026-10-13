import Foundation

// P133 (Oct 12 PM, 15:19 "it'd be funny if these barrels had stuff... something that might be considered useful to a
// base, but not really to you"): base sundries. About half the supply chests of Steelhold, Greywall and Ashguard sites
// carry one or two, and the barrels in base mess halls, yards, generator rooms and stores are no longer empty: they hold sundries
// with the odd field ration or baked potato. Sundries do nothing for the player; using one reads its little note, and a
// general store buys them for pennies.
enum BaseSundries {
    struct Sundry { let key: String; let name: String; let mask: String; let color: UInt32; let extras: [Character: UInt32]; let note: String }
    static let all: [Sundry] = [
        Sundry(key: "requisition_form", name: "Requisition Form", mask: "paper", color: 0xE8E4D4, extras: [:],
               note: "Form 7-B, in triplicate: one crate of pencils, to replace the pencils used filling in Form 7-B"),
        Sundry(key: "duty_roster", name: "Duty Roster", mask: "orders", color: 0xDCD8C4, extras: ["c": 0x3A5A9A, "d": 0x3A3A3A],
               note: "Latrine duty: every name crossed out but one, written in twice"),
        Sundry(key: "boot_polish", name: "Tin of Boot Polish", mask: "ball", color: 0x2A2420, extras: [:],
               note: "Black, half used. The inspection is at dawn"),
        Sundry(key: "radio_valve", name: "Spare Radio Valve", mask: "nugget", color: 0xA8B4BC, extras: [:],
               note: "A glass valve for a set you don't have. Marked: DO NOT DROP"),
        Sundry(key: "typewriter_ribbon", name: "Typewriter Ribbon", mask: "lump", color: 0x2A2A30, extras: [:],
               note: "Black and red, for orders and for very important orders"),
        Sundry(key: "rubber_stamp", name: "Rubber Stamp", mask: "mechanism", color: 0x6A3A20, extras: ["c": 0xA02A20],
               note: "It says APPROVED. Someone has stamped it on the handle as well"),
        Sundry(key: "empty_sandbag", name: "Empty Sandbag", mask: "leather", color: 0xB8A47A, extras: [:],
               note: "Fill with sand. Sand not issued"),
        Sundry(key: "tent_pegs", name: "Tent Pegs", mask: "stick", color: 0x8A8A90, extras: [:],
               note: "Bent, every one. The ground here is rock"),
        Sundry(key: "mess_tin", name: "Mess Tin", mask: "bowl", color: 0x9AA0A6, extras: [:],
               note: "Scratched with a soldier's name and a tally of thirty-one stews"),
        Sundry(key: "spent_casings", name: "Spent Casings", mask: "nugget", color: 0xC8A24A, extras: [:],
               note: "Brass from the range, kept for counting. Somebody is short by three"),
    ]
    static let keys = Set(all.map { $0.key })
    static func note(_ key: String) -> String? { all.first { $0.key == key }?.note }

    // The pool added to supply chests, and the barrels' own table (sundries, with rations and potatoes kept).
    static let supplyPool: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)]) =
        (1...2, all.map { ($0.key, 1, $0.key == "spent_casings" ? 12 : 2, 1) } + [("empty", 1, 1, 14)])     // about half the chests
    static let barrel: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)]) =
        (2...4, all.map { ($0.key, 1, $0.key == "spent_casings" ? 16 : 3, 4) }
            + [("capital_ration", 1, 3, 6), ("baked_potato", 2, 5, 6), ("bread", 1, 3, 3), ("coal", 2, 6, 3), ("empty", 1, 1, 4)])
    static let supplyTables = ["steelhold_supply", "greywall_supply", "ash_supply"]
}

extension StructWriter {
    // A barrel holding base sundries (P133).
    mutating func sundryBarrel(_ x: Int, _ y: Int, _ z: Int, seed s: UInt64) {
        guard inside(x, y, z) else { return }
        let seed = UInt64(hash3(x, y, z, UInt32(truncatingIfNeeded: s ^ (s >> 32)) ^ 0x5B1D)) | 1
        set(x, y, z, Blocks.id("barrel"))
        let be = BlockEntity(.chest)
        var rng = SRng(seed)
        Loot.fill(be.container, table: "base_sundries", rng: &rng)
        entities.append((IVec3(x, y, z), be))
    }
}

extension Game {
    // Using a sundry reads its note.
    func sundryUse() -> Bool {
        let k = Items.key(held.item)
        guard let n = BaseSundries.note(k) else { return false }
        onToast?("\(Items.name(held.item)): \(n)")
        return true
    }
}
