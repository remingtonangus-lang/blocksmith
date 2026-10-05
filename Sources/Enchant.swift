import Foundation
import simd

// Enchantments: the reference game's list, weights, level cost windows, anvil costs and item
// categories; enchanting-table selection; anvil combining. Stored packed in ItemStack.ench
// (7 slots x 9 bits: id+1 in 6 bits, level in 3 bits).
enum Ench: Int, CaseIterable {
    case protection, fireProtection, featherFalling, blastProtection, projectileProtection, respiration, aquaAffinity
    case thorns, depthStrider, frostWalker, bindingCurse, soulSpeed, swiftSneak
    case sharpness, smite, baneOfArthropods, knockback, fireAspect, looting, sweepingEdge
    case efficiency, silkTouch, unbreaking, fortune
    case power, punch, flame, infinity
    case luckOfTheSea, lure
    case loyalty, impaling, riptide, channeling
    case multishot, quickCharge, piercing
    case mending, vanishingCurse
    case density, breach, windBurst
    case lunge
}

// What an item is, for enchantment purposes.
struct ECat: OptionSet {
    let rawValue: Int
    static let sword = ECat(rawValue: 1), axe = ECat(rawValue: 2), digger = ECat(rawValue: 4)
    static let head = ECat(rawValue: 8), chest = ECat(rawValue: 16), legs = ECat(rawValue: 32), feet = ECat(rawValue: 64)
    static let bow = ECat(rawValue: 128), crossbow = ECat(rawValue: 256), trident = ECat(rawValue: 512), rod = ECat(rawValue: 1024)
    static let mace = ECat(rawValue: 2048), durable = ECat(rawValue: 4096), wearable = ECat(rawValue: 8192)
    static let vanishable = ECat(rawValue: 16384), shears = ECat(rawValue: 32768)
    static let spear = ECat(rawValue: 65536)
    static let armor: ECat = [.head, .chest, .legs, .feet]
    static let mining: ECat = [.digger, .axe]
}

struct EnchDef {
    let key: String
    let name: String
    let max: Int
    let weight: Int
    let primary: ECat          // enchanting table
    let supported: ECat       // anvil
    let minBase: Int, minPer: Int, maxBase: Int, maxPer: Int
    let anvil: Int
    var treasure = false
    var curse = false
    var group = 0             // mutually exclusive group
    func minCost(_ l: Int) -> Int { minBase + (l - 1) * minPer }
    func maxCost(_ l: Int) -> Int { maxBase + (l - 1) * maxPer }
}

enum Enchant {
    static let defs: [EnchDef] = {
        func d(_ k: String, _ n: String, _ max: Int, _ w: Int, _ p: ECat, _ s: ECat? = nil, _ mn: (Int, Int), _ mx: (Int, Int), anvil: Int,
               treasure: Bool = false, curse: Bool = false, group: Int = 0) -> EnchDef {
            EnchDef(key: k, name: n, max: max, weight: w, primary: p, supported: s ?? p, minBase: mn.0, minPer: mn.1, maxBase: mx.0, maxPer: mx.1,
                    anvil: anvil, treasure: treasure, curse: curse, group: group)
        }
        return [
            d("protection", "Protection", 4, 10, .armor, nil, (1, 11), (12, 11), anvil: 1, group: 1),
            d("fire_protection", "Fire Protection", 4, 5, .armor, nil, (10, 8), (18, 8), anvil: 2, group: 1),
            d("feather_falling", "Feather Falling", 4, 5, .feet, nil, (5, 6), (11, 6), anvil: 2),
            d("blast_protection", "Blast Protection", 4, 2, .armor, nil, (5, 8), (13, 8), anvil: 4, group: 1),
            d("projectile_protection", "Projectile Protection", 4, 5, .armor, nil, (3, 6), (9, 6), anvil: 2, group: 1),
            d("respiration", "Respiration", 3, 2, .head, nil, (10, 10), (40, 10), anvil: 4),
            d("aqua_affinity", "Aqua Affinity", 1, 2, .head, nil, (1, 0), (41, 0), anvil: 4),
            d("thorns", "Thorns", 3, 1, .chest, .armor, (10, 20), (60, 20), anvil: 8),
            d("depth_strider", "Deep Stride", 3, 2, .feet, nil, (10, 10), (25, 10), anvil: 4, group: 5),
            d("frost_walker", "Frost Walker", 2, 2, .feet, nil, (10, 10), (25, 10), anvil: 4, treasure: true, group: 5),
            d("binding_curse", "Curse of Binding", 1, 1, .wearable, nil, (25, 0), (50, 0), anvil: 8, treasure: true, curse: true),
            d("soul_speed", "Ghost Stride", 3, 1, .feet, nil, (10, 10), (25, 10), anvil: 8, treasure: true),
            d("swift_sneak", "Swift Sneak", 3, 1, .legs, nil, (25, 25), (75, 25), anvil: 8, treasure: true),
            d("sharpness", "Sharpness", 5, 10, [.sword, .spear], [.sword, .axe, .spear], (1, 11), (21, 11), anvil: 1, group: 2),
            d("smite", "Smite", 5, 5, [.sword, .spear], [.sword, .axe, .mace, .spear], (5, 8), (25, 8), anvil: 2, group: 2),
            d("bane_of_arthropods", "Bane of Arthropods", 5, 5, [.sword, .spear], [.sword, .axe, .mace, .spear], (5, 8), (25, 8), anvil: 2, group: 2),
            d("knockback", "Knockback", 2, 5, [.sword, .spear], nil, (5, 20), (55, 20), anvil: 2),
            d("fire_aspect", "Fire Aspect", 2, 2, [.sword, .spear], [.sword, .mace, .spear], (10, 20), (60, 20), anvil: 4),
            d("looting", "Looting", 3, 2, [.sword, .spear], nil, (15, 9), (65, 9), anvil: 4),
            d("sweeping_edge", "Sweeping Edge", 3, 2, .sword, nil, (5, 9), (20, 9), anvil: 4),
            d("efficiency", "Efficiency", 5, 10, .mining, [.digger, .axe, .shears], (1, 10), (51, 10), anvil: 1),
            d("silk_touch", "Silk Touch", 1, 1, .mining, nil, (15, 0), (65, 0), anvil: 8, group: 3),
            d("unbreaking", "Unbreaking", 3, 5, .durable, nil, (5, 8), (55, 8), anvil: 2),
            d("fortune", "Fortune", 3, 2, .mining, nil, (15, 9), (65, 9), anvil: 4, group: 3),
            d("power", "Power", 5, 10, .bow, nil, (1, 10), (16, 10), anvil: 1),
            d("punch", "Punch", 2, 2, .bow, nil, (12, 20), (37, 20), anvil: 4),
            d("flame", "Flame", 1, 2, .bow, nil, (20, 0), (50, 0), anvil: 4),
            d("infinity", "Infinity", 1, 1, .bow, nil, (20, 0), (50, 0), anvil: 8, group: 4),
            d("luck_of_the_sea", "Luck of the Sea", 3, 2, .rod, nil, (15, 9), (65, 9), anvil: 4),
            d("lure", "Lure", 3, 2, .rod, nil, (15, 9), (65, 9), anvil: 4),
            d("loyalty", "Loyalty", 3, 5, .trident, nil, (12, 7), (50, 0), anvil: 1),
            d("impaling", "Impaling", 5, 2, .trident, nil, (1, 8), (21, 8), anvil: 4),
            d("riptide", "Riptide", 3, 2, .trident, nil, (17, 7), (50, 0), anvil: 4),
            d("channeling", "Channeling", 1, 1, .trident, nil, (25, 0), (50, 0), anvil: 8),
            d("multishot", "Multishot", 1, 2, .crossbow, nil, (20, 0), (50, 0), anvil: 4, group: 7),
            d("quick_charge", "Quick Charge", 3, 5, .crossbow, nil, (12, 20), (50, 0), anvil: 2),
            d("piercing", "Piercing", 4, 10, .crossbow, nil, (1, 10), (50, 0), anvil: 1, group: 7),
            d("mending", "Mending", 1, 2, .durable, nil, (25, 25), (75, 25), anvil: 4, treasure: true, group: 4),
            d("vanishing_curse", "Curse of Vanishing", 1, 1, .vanishable, nil, (25, 0), (50, 0), anvil: 8, treasure: true, curse: true),
            d("density", "Density", 5, 5, .mace, nil, (5, 8), (25, 8), anvil: 2, group: 2),
            d("breach", "Breach", 4, 2, .mace, nil, (15, 9), (65, 9), anvil: 4, group: 2),
            d("wind_burst", "Wind Burst", 3, 2, .mace, nil, (15, 9), (65, 9), anvil: 4, treasure: true),
            d("lunge", "Lunge", 3, 5, .spear, nil, (5, 8), (25, 8), anvil: 2),          // spears: the jab carries the player forward
        ]
    }()
    static func def(_ e: Ench) -> EnchDef { defs[e.rawValue] }
    static func named(_ k: String) -> Ench? { defs.firstIndex { $0.key == k }.map { Ench(rawValue: $0)! } }

    static func compatible(_ a: Ench, _ b: Ench) -> Bool {
        if a == b { return false }
        let ga = def(a).group, gb = def(b).group
        if ga != 0 && ga == gb {
            // Smite/bane/sharpness on a mace mix with density? No: all of group 2 exclude each other.
            return false
        }
        if (a == .riptide && (b == .loyalty || b == .channeling)) || (b == .riptide && (a == .loyalty || a == .channeling)) { return false }
        return true
    }

    // MARK: Packing

    static func list(_ s: ItemStack) -> [(Ench, Int)] { list(s.ench) }
    static func list(_ v: UInt64) -> [(Ench, Int)] {
        var out: [(Ench, Int)] = []
        for i in 0..<7 {
            let w = Int((v >> UInt64(i * 9)) & 0x1FF)
            if w == 0 { continue }
            if let e = Ench(rawValue: (w >> 3) - 1) { out.append((e, w & 7)) }
        }
        return out
    }
    static func pack(_ l: [(Ench, Int)]) -> UInt64 {
        var v: UInt64 = 0
        for (i, (e, lv)) in l.prefix(7).enumerated() {
            v |= UInt64(((e.rawValue + 1) << 3) | min(7, max(1, lv))) << UInt64(i * 9)
        }
        return v
    }
    static func level(_ e: Ench, _ s: ItemStack) -> Int {
        if s.ench == 0 { return 0 }
        var v = s.ench
        while v != 0 {
            let w = Int(v & 0x1FF)
            if w != 0 && (w >> 3) - 1 == e.rawValue { return w & 7 }
            v >>= 9
        }
        return 0
    }
    static func encode(_ v: UInt64) -> [String] { list(v).map { "\(def($0.0).key):\($0.1)" } }
    static func decode(_ a: [String]) -> UInt64 {
        pack(a.compactMap { s in
            let p = s.split(separator: ":")
            guard p.count == 2, let e = named(String(p[0])), let l = Int(p[1]) else { return nil }
            return (e, l)
        })
    }

    static func displayLine(_ e: Ench, _ l: Int) -> String {
        let d = def(e)
        return d.max == 1 ? d.name : d.name + " " + Effect.roman(l)
    }

    // MARK: Item categories

    static func category(_ item: ItemID) -> ECat {
        let d = Items.def(item)
        let k = d.name
        var c: ECat = []
        switch d.tool {
        case .sword: c.insert(.sword)
        case .axe: c.insert(.axe)
        case .pickaxe, .shovel, .hoe: c.insert(.digger)
        case .shears: c.insert(.shears)
        default: break
        }
        if let a = d.armorSlot, k != "elytra" {
            c.insert([ECat.head, .chest, .legs, .feet][a.rawValue])
        }
        if k == "bow" { c.insert(.bow) }
        if k == "crossbow" { c.insert(.crossbow) }
        if k == "trident" { c.insert(.trident) }
        if k == "fishing_rod" { c.insert(.rod) }
        if k == "mace" { c.insert(.mace) }
        if k.hasSuffix("_spear") { c.insert(.spear) }                     // spears: the melee enchantments (no sweep) + Lunge
        if d.durability > 0 { c.insert(.durable); c.insert(.vanishable) }
        if d.armorSlot != nil || k == "carved_pumpkin" || k.hasSuffix("_skull") || k.hasSuffix("_head") { c.insert(.wearable); c.insert(.vanishable) }
        if k == "compass" || k == "recovery_compass" { c.insert(.vanishable) }
        return c
    }

    static func assignEnchantability(_ reg: ItemRegistry) {
        let tools: [(String, Int)] = [("wooden", 15), ("stone", 5), ("iron", 14), ("golden", 22), ("diamond", 10), ("netherite", 15), ("copper", 13)]
        for (m, v) in tools { for t in ["sword", "shovel", "pickaxe", "axe", "hoe", "spear"] { reg.setEnchantability("\(m)_\(t)", v) } }
        let armor: [(String, Int)] = [("leather", 15), ("chainmail", 12), ("iron", 9), ("golden", 25), ("diamond", 10), ("netherite", 15), ("copper", 8)]
        for (m, v) in armor { for p in ["helmet", "chestplate", "leggings", "boots"] { reg.setEnchantability("\(m)_\(p)", v) } }
        reg.setEnchantability("turtle_helmet", 9)
        for n in ["book", "bow", "crossbow", "trident", "fishing_rod"] { reg.setEnchantability(n, 1) }
        reg.setEnchantability("mace", 15)
    }

    // Can `e` go on this item at the table (primary) or anvil (supported)?
    static func applies(_ e: Ench, _ item: ItemID, table: Bool) -> Bool {
        let k = Items.key(item)
        if k == "book" || k == "enchanted_book" { return true }
        let c = category(item)
        let d = def(e)
        return !c.intersection(table ? d.primary : d.supported).isEmpty
    }

    // MARK: Enchanting table

    struct Option { var cost: Int; var ench: [(Ench, Int)] }

    // Displayed level costs for the three slots (reference formula).
    static func tableCosts(bookshelves b0: Int, rng: inout SRng) -> [Int] {
        let b = min(15, b0)
        var out: [Int] = []
        for slot in 0..<3 {
            let base = rng.int(1...8) + b / 2 + rng.int(0...b)
            let c: Int
            switch slot {
            case 0: c = max(base / 3, 1)
            case 1: c = base * 2 / 3 + 1
            default: c = max(base, b * 2)
            }
            out.append(c)
        }
        return out
    }

    static func select(item: ItemID, level: Int, rng: inout SRng, treasure: Bool = false) -> [(Ench, Int)] {
        let ability = Items.def(item).enchantability
        guard ability > 0 else { return [] }
        var lvl = level + 1 + rng.int(0...(ability / 4)) + rng.int(0...(ability / 4))
        let bonus = (rng.float() + rng.float() - 1) * 0.15
        lvl = max(1, Int((Float(lvl) * (1 + bonus)).rounded()))
        func candidates(_ lvl: Int) -> [(Ench, Int, Int)] {
            var c: [(Ench, Int, Int)] = []
            for e in Ench.allCases {
                let d = def(e)
                if (d.treasure && !treasure) || !applies(e, item, table: true) { continue }
                for l in stride(from: d.max, through: 1, by: -1) where lvl >= d.minCost(l) && lvl <= d.maxCost(l) {
                    c.append((e, l, d.weight)); break
                }
            }
            return c
        }
        var pool = candidates(lvl)
        var out: [(Ench, Int)] = []
        func pick() {
            let total = pool.reduce(0) { $0 + $1.2 }
            guard total > 0 else { return }
            var r = rng.int(0...(total - 1))
            for (i, c) in pool.enumerated() {
                r -= c.2
                if r < 0 { out.append((c.0, c.1)); pool.remove(at: i); break }
            }
        }
        pick()
        while rng.int(0...49) <= lvl {
            pool.removeAll { c in out.contains { !compatible($0.0, c.0) } }
            if pool.isEmpty { break }
            pick()
            lvl /= 2
        }
        return out
    }

    // Bookshelves around a table: 2 blocks out, same level or one up, with air between.
    static func countBookshelves(_ w: World, _ p: IVec3) -> Int {
        var n = 0
        for dz in -2...2 { for dx in -2...2 where max(abs(dx), abs(dz)) == 2 {
            for dy in 0...1 {
                let mid = w.block(p.x + dx / 2, p.y, p.z + dz / 2)       // truncating halves, like the reference
                guard mid == AIR || Blocks.replaceable[Int(mid)] else { continue }
                if Blocks.key(w.block(p.x + dx, p.y + dy, p.z + dz)) == "bookshelf" { n += 1 }
            }
        } }
        return n
    }

    // Random enchantment for loot ("enchant_randomly": any applicable level, treasure included).
    static func randomly(_ item: ItemID, treasure: Bool = true) -> [(Ench, Int)] {
        let opts = Ench.allCases.filter { (treasure || !def($0).treasure) && applies($0, item, table: false) }
        guard let e = opts.pick() else { return [] }
        return [(e, Rand.int(in: 1...def(e).max))]
    }

    // "enchant_with_levels" for loot tables and mob gear.
    static func withLevels(_ item: ItemID, _ levels: Int, treasure: Bool = false) -> ItemStack {
        var rng = SRng(Rand.u64(in: 0...UInt64.max))
        let isBook = Items.key(item) == "book"
        let l = select(item: isBook ? Items.id("book") : item, level: levels, rng: &rng, treasure: treasure)
        var s = ItemStack(isBook && !l.isEmpty ? Items.id("enchanted_book") : item, 1)
        s.ench = pack(l)
        return s
    }

    // MARK: Anvil

    struct AnvilResult { var out: ItemStack; var cost: Int; var rightUsed: Int }

    static func combine(_ left: ItemStack, _ right: ItemStack, rename: String?, creative: Bool) -> AnvilResult? {
        guard !left.isEmpty else { return nil }
        var out = left
        // A rename alone takes the whole stack (64 renamed diamonds); combining works on one item.
        out.count = right.isEmpty ? left.count : 1
        var cost = 0
        var rightUsed = 0
        let ld = left.def
        if !right.isEmpty {
            let rk = Items.key(right.item)
            let isBook = rk == "enchanted_book"
            if ld.durability > 0, let mat = repairMaterial(left.item), rk == mat, left.damage > 0 {
                // Material repair: 25% of max durability per unit.
                var dmg = left.damage
                var used = 0
                while dmg > 0 && used < right.count {
                    dmg = max(0, dmg - ld.durability / 4)
                    used += 1
                    cost += 1
                }
                out.damage = dmg
                rightUsed = used
            } else {
                guard isBook || right.item == left.item else { return nil }
                if !isBook && ld.durability > 0 && left.damage > 0 {
                    let remain = (ld.durability - left.damage) + (ld.durability - right.damage) + ld.durability * 12 / 100
                    out.damage = max(0, ld.durability - remain)
                    cost += 2
                }
                var cur = Enchant.list(left)
                var anyApplied = false, anyBlocked = false
                for (e, lv) in Enchant.list(right) {
                    let d = def(e)
                    let ok = Items.key(left.item) == "enchanted_book" || applies(e, left.item, table: false) || creative
                    if !ok { anyBlocked = true; continue }
                    if cur.contains(where: { $0.0 != e && !compatible($0.0, e) }) { cost += 1; anyBlocked = true; continue }
                    let have = cur.first { $0.0 == e }?.1 ?? 0
                    var nl = have == lv ? lv + 1 : max(have, lv)
                    nl = min(nl, d.max)
                    cur.removeAll { $0.0 == e }
                    cur.append((e, nl))
                    anyApplied = true
                    cost += (isBook ? max(1, d.anvil / 2) : d.anvil) * nl
                }
                if !anyApplied && anyBlocked && out.damage == left.damage { return nil }
                out.ench = pack(cur)
                rightUsed = 1
            }
        }
        var renameCost = 0
        if let r = rename, !r.isEmpty, r != left.displayName {
            out.label = r
            renameCost = 1
            cost += 1
        }
        if right.isEmpty && renameCost == 0 { return nil }
        let prior = left.repairCost + (right.isEmpty ? 0 : right.repairCost)
        cost += prior
        if right.isEmpty { cost = min(cost, 39) }
        if !right.isEmpty { out.repairCost = max(left.repairCost, right.repairCost) * 2 + 1 }
        if cost <= 0 { return nil }
        if cost >= 40 && !creative { return AnvilResult(out: .empty, cost: cost, rightUsed: 0) }
        return AnvilResult(out: out, cost: cost, rightUsed: rightUsed)
    }

    static func repairMaterial(_ item: ItemID) -> String? {
        let k = Items.key(item)
        for (pre, mat) in [("wooden_", "oak_planks"), ("stone_", "cobblestone"), ("iron_", "iron_ingot"), ("golden_", "gold_ingot"),
                           ("diamond_", "diamond"), ("netherite_", "netherite_ingot"), ("leather_", "leather"), ("chainmail_", "iron_ingot"), ("copper_", "copper_ingot")] where k.hasPrefix(pre) {
            return mat
        }
        if k == "turtle_helmet" { return "turtle_scute" }
        if k == "elytra" { return "phantom_membrane" }
        if k == "mace" { return "breeze_rod" }
        if k.hasPrefix("gun_") { return k == "gun_arc" ? "copper_ingot" : "iron_ingot" }     // Steelhold guns
        return nil
    }

    // MARK: Effects used by combat / mining

    // Extra melee damage against `m` (sharpness / smite / bane).
    static func damageBonus(_ s: ItemStack, against m: Mob) -> Float {
        guard s.ench != 0 else { return 0 }
        var b: Float = 0
        let sh = level(.sharpness, s)
        if sh > 0 { b += 0.5 * Float(sh) + 0.5 }
        if m.undead { b += 2.5 * Float(level(.smite, s)) }
        if m.arthropod { b += 2.5 * Float(level(.baneOfArthropods, s)) }
        return b
    }

    // Protection points (EPF) from all worn armor for a damage type (capped at 20, 4% each).
    static func protection(_ armor: ItemContainer, _ type: DamageType) -> Int {
        var epf = 0
        for s in armor.slots where !s.isEmpty && s.ench != 0 {
            epf += level(.protection, s)
            switch type {
            case .fire: epf += 2 * level(.fireProtection, s)
            case .explosion: epf += 2 * level(.blastProtection, s)
            case .projectile: epf += 2 * level(.projectileProtection, s)
            case .fall: epf += 3 * level(.featherFalling, s)
            default: break
            }
        }
        return min(20, epf)
    }

    // Unbreaking: chance that a use doesn't cost durability.
    static func wearSkipped(_ s: ItemStack) -> Bool {
        let u = level(.unbreaking, s)
        guard u > 0 else { return false }
        if s.def.armorSlot != nil { return Rand.float(in: 0..<1) >= 0.6 + 0.4 / Float(u + 1) }
        return Rand.int(in: 0...u) > 0
    }
}

enum DamageType { case generic, fire, explosion, projectile, fall, magic, drown, starve, void }

extension SRng {
    mutating func int(_ r: ClosedRange<Int>) -> Int { range(r.lowerBound, r.upperBound) }
}
