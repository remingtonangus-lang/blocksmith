import Foundation
import simd

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

extension Game {
    // P205: a death's belongings in one or two chests side by side at the nearest open spot by `p` (up to 6 blocks
    // around, out of liquids), with a map pin. Returns false when no spot was found (the items drop as before).
    func deathChests(_ items: [ItemStack], near p: V3) -> Bool {
        guard netGuest == nil, Blocks.has("chest") else { return false }
        let chest = Blocks.id("chest")
        let need = (items.count + 26) / 27
        let bx = Int(floor(p.x)), by = max(-60, min(CH - YOFF - 3, Int(floor(p.y)))), bz = Int(floor(p.z))
        func open(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            guard world.isLoaded(x, z) else { return false }
            let b = world.block(x, y, z)
            return (b == AIR || (Blocks.replaceable[Int(b)] && !Blocks.isLiquid(b))) && !Blocks.isLiquid(world.block(x, y - 1, z))
        }
        var spot: IVec3?
        search: for r in 0...6 {
            for dy in [0, 1, -1, 2, 3, 4, 5, 6] {
                for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                    let x = bx + dx, y = by + dy, z = bz + dz
                    if open(x, y, z) && (need == 1 || open(x + 1, y, z)) { spot = IVec3(x, y, z); break search }
                } }
            }
        }
        guard let at = spot else { return false }
        var left = items[...]
        for k in 0..<need {
            let q = IVec3(at.x + k, at.y, at.z)
            world.setBlock(q.x, q.y, q.z, chest)
            let be = BlockEntity(.chest)
            for i in 0..<min(27, be.container.count) { guard let st = left.popFirst() else { break }; be.container[i] = st }
            world.blockEntities[q] = be
        }
        MapCache.shared.pinDeath(self, x: at.x, z: at.z)
        deathStash = DeathStash(x: at.x, y: at.y, z: at.z, n: need, dim: dim.dim.rawValue)     // (the death screen says where)
        return true
    }
}

// Q2c-console-4 (store readiness: a death explains itself and points the way back). The death screen says where his
// things are; after Respawn the stash is tracked (HUD bearing, beacon) unless he follows something else; emptied or
// broken, its pin leaves the map and tracking goes back. Saved with the world extras ("deathStash").
struct DeathStash: Codable {
    var x: Int, y: Int, z: Int
    var n: Int
    var dim: String
}

extension Game {
    // The death screen's words about his things (and his experience).
    func deathDetail(lost: Bool, stashed: Bool) -> String {
        var d = ""
        if stashed, let s = deathStash {
            d = "Your things are in a chest where you fell, at \(s.x), \(s.z)" + (s.dim == Dim.overworld.rawValue ? ", on your map." : ".")
        } else if lost {
            d = "Your things are on the ground where you fell: about five minutes before they are gone."
        }
        return d + (d.isEmpty ? "" : " ") + "You keep your experience."
    }

    // After Respawn: follow the stash and say how far it is.
    func stashHint() {
        guard let s = deathStash, s.dim == dim.dim.rawValue else { return }
        let off = V2(Float(s.x) + 0.5 - player.pos.x, Float(s.z) + 0.5 - player.pos.z)
        let d = Int(simd_length(off))
        if dim.dim == .overworld && Waymarks.trackedKey == nil {
            Waymarks.trackedKey = "pin|\(s.x),\(s.z)"
            Waymarks.cache = (-1e9, nil)
        }
        onToast?(d > 8 ? "Your things are \(d) blocks \(TownBoard.direction(off.x, off.y))" + (dim.dim == .overworld ? ": follow the beacon" : "")
                       : "Your things are in the chest beside you")
    }

    // Once a second (Waymarks.tick): the stash emptied or broken closes the loop.
    func stashTick() {
        guard let s = deathStash, s.dim == dim.dim.rawValue, world.isLoaded(s.x, s.z) else { return }
        var present = false, left = 0
        for k in 0..<max(1, s.n) {
            let p = IVec3(s.x + k, s.y, s.z)
            let b = world.block(p.x, p.y, p.z)
            guard Blocks.key(Blocks.groupBase[Int(b)]) == "chest" else { continue }
            present = true
            left += world.blockEntities[p]?.container.slots.reduce(0) { $0 + ($1.isEmpty ? 0 : 1) } ?? 0
        }
        guard !present || left == 0 else { return }
        deathStash = nil
        MapCache.shared.unpinDeath(self)
        if Waymarks.trackedKey == "pin|\(s.x),\(s.z)" { Waymarks.trackedKey = nil; Waymarks.cache = (-1e9, nil) }
        onToast?("You have your things back")
        sfx(.xp, 0.6)
    }
}
