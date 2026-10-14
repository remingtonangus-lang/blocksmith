import Foundation
import simd

// P248 (Oct 13 22:01, "safes in the military bases, like that spy film game"): ground military bases (the Capital's
// citadels and the Greywall fortresses) keep a Steel Safe in the command rooms with really good loot. It can't be mined
// or blasted open. Its key (a Safe Key, used up in the lock) lies in a chest of the same base, well within 100 blocks;
// about one base in a hundred hides a Safecracker's Kit in that chest instead of nothing, and the kit opens any safe and
// is kept. An opened safe stays open.
enum BaseSafes {
    static let block = "base_safe"
    static let key = "safe_key"
    static let cracker = "safe_breaker"
    static let loot = "base_safe"
    static let opened = "open"                        // BlockEntity.mob of a safe that has been unlocked

    // Really good loot (Loot.fill rolls it; graded guns and their rounds as in any chest).
    static let table: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)]) = (5...8, [
        ("diamond", 3, 8, 16), ("gold_block", 1, 3, 12), ("emerald", 3, 8, 10),                 // (diamond is the Titanium Ingot)
        ("netherite_scrap", 1, 2, 4), ("gun_sniper", 1, 1, 4), ("gun_sturmwind", 1, 1, 4), ("gun_kessel", 1, 1, 3),
        ("enchanted_golden_apple", 1, 1, 3), ("experience_bottle", 4, 12, 8), ("ember_charge", 1, 1, 3), ("radar_module", 1, 1, 3),
        ("gold_ingot", 4, 12, 10), ("name_tag", 1, 1, 2),
    ])
}

extension BlockRegistry {
    func registerSafeBlocks() {
        guard !has(BaseSafes.block) else { return }
        var d = BlockDef(BaseSafes.block, "Steel Safe")
        d.tex = ["base_safe_side", "base_safe_side", "base_safe_top", "base_safe_top", "base_safe_side", "base_safe_side"]
        d.hardness = -1; d.resistance = 3_600_000; d.tool = .pickaxe; d.requiresTool = true; d.sound = .metal
        addFacing(d, front: "base_safe_front")
    }
}

extension ItemRegistry {
    func registerSafeItems() {
        if !has(BaseSafes.key) {
            var d = ItemDef(BaseSafes.key, "Safe Key")
            d.sprite = Sprite(mask: "key", base: 0x8A6A2A, extras: ["c": 0xE8C060])
            d.maxStack = 16
            add(d)
        }
        if !has(BaseSafes.cracker) {
            var d = ItemDef(BaseSafes.cracker, "Safecracker's Kit")
            d.sprite = Sprite(mask: "safecracker", base: 0x3A3C40, extras: ["c": 0x9CD6FF, "d": 0x23252A])
            d.maxStack = 1
            add(d)
        }
    }
}

extension TextureGen {
    static func safePainters(_ p: inout [String: Painter]) {
        // Dark gunmetal with a bevelled edge, rivets in the corners.
        p["base_safe_side"] = { x, y in
            if x == 0 || y == 0 { return hex(0x5E646C) }
            if x == 15 || y == 15 { return hex(0x23262A) }
            if (x == 2 || x == 13) && (y == 2 || y == 13) { return hex(0x8A9098) }
            return hex(0x3E434A, 0.93 + 0.05 * r(x, y, 4801) + 0.03 * r(0, y, 4802))
        }
        p["base_safe_top"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x2A2D32) }
            return hex(0x454A52, 0.94 + 0.05 * r(x, y, 4803))
        }
        // The door: a recessed panel, a brass combination dial (ring and pointer), a spoked handle and the hinges.
        p["base_safe_front"] = { x, y in
            if x == 0 || y == 0 { return hex(0x5E646C) }
            if x == 15 || y == 15 { return hex(0x23262A) }
            if x == 1 && (y == 3 || y == 4 || y == 11 || y == 12) { return hex(0x9AA0A8) }        // hinges
            if x == 2 || x == 14 || y == 2 || y == 13 { return hex(0x2C3035) }                    // the door's seam
            let dx = Float(x) - 6.5, dy = Float(y) - 7.5
            let d2 = dx * dx + dy * dy
            if d2 < 3.2 { return hex(dx > 0.4 && abs(dy) < 0.6 ? 0x2A2010 : 0xD8B460) }        // the dial and its pointer
            if d2 < 9.5 { return hex(Int(atan2f(dy, dx) * 3 + 20) % 2 == 0 ? 0xA8843A : 0x7A5E26) }   // the numbered ring
            if (x == 11 && y >= 5 && y <= 10) || (y == 7 && x >= 10 && x <= 12) || (y == 8 && x >= 10 && x <= 12) {
                return hex(0xB8BEC6)                                                               // the handle
            }
            return hex(0x40454C, 0.93 + 0.05 * r(x, y, 4804))
        }
    }
}

extension StructWriter {
    // A Steel Safe facing `facing` (0 north ... 3 east) holding the safe loot.
    mutating func safe(_ x: Int, _ y: Int, _ z: Int, seed: UInt64, facing: Int) {
        guard inside(x, y, z), Blocks.has(BaseSafes.block) else { return }
        set(x, y, z, Blocks.id(BaseSafes.block) + BlockID(facing))
        let be = BlockEntity(.chest)
        var rng = SRng(seed)
        Loot.fill(be.container, table: BaseSafes.loot, rng: &rng)
        entities.append((IVec3(x, y, z), be))
    }

    // The base's key goes in the chest just written at (x, y, z) (when that chest is in this chunk): the Safe Key, and
    // in about one base in a hundred a Safecracker's Kit beside it (decided by the base's seed, the same in every chunk).
    mutating func safeKey(_ x: Int, _ y: Int, _ z: Int, baseSeed: UInt64) {
        guard inside(x, y, z), let e = entities.last(where: { $0.0 == IVec3(x, y, z) }) else { return }
        let c = e.1.container
        var put = [ItemStack(Items.id(BaseSafes.key), 1)]
        if baseSeed % 100 == 37 { put.append(ItemStack(Items.id(BaseSafes.cracker), 1)) }
        for s in put {
            if let i = (0..<c.count).first(where: { c[$0].isEmpty }) { c[i] = s } else { c[c.count - 1] = s }
        }
    }
}

extension Game {
    func useSafe(_ p: IVec3) {
        let be = world.entity(p, .chest)
        world.blockEntities[p] = be
        let at = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        func open() {
            let m = ChestMenu(game: self, entity: be)
            m.title = "Steel Safe"
            openMenu(m)
        }
        if be.mob == BaseSafes.opened { open(); return }
        let inv = inventory.main
        if (0..<inv.count).contains(where: { !inv[$0].isEmpty && Items.key(inv[$0].item) == BaseSafes.cracker }) {
            be.mob = BaseSafes.opened
            sfx(.anvil, 0.35, at: at); sfx(.ironDoorOpen, 1, at: at)
            onToast?("The Safecracker's Kit works the dial: the safe swings open")
            open()
            return
        }
        if let i = (0..<inv.count).first(where: { !inv[$0].isEmpty && Items.key(inv[$0].item) == BaseSafes.key }) {
            var s = inv[i]; s.count -= 1; inv[i] = s
            be.mob = BaseSafes.opened
            sfx(.ironDoorOpen, 1, at: at)
            onToast?("The key turns in the lock: the safe is open")
            open()
            return
        }
        sfx(.ironDoorClose, 0.6, at: at)
        onToast?("Locked. Its Safe Key is kept in a chest somewhere in this base")
    }
}
