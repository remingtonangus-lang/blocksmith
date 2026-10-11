import Foundation
import simd

// Tool upgrades (backlog B5; docs/status/upgrades.md). Enchanting is gone: every old enchantment is now a physical
// upgrade fitted to a part of the item at the Upgrade Bench (the old enchanting table's block), paid with experience
// levels plus the item's own material and a part-specific one. Storage and effects are the enchantment machinery's
// (ItemStack.ench, Enchant.level), so balance and old saves carry over: an enchanted item loads as the same
// upgrades, curses dropped (`convert`). Upgrades show on the model: guns grow a scope, a longer magazine and a band
// for special rounds (Guns.writeFirstPerson), tools and weapons get coloured accents on the held model (`accents`),
// and inventory icons get pips instead of the old glint.

enum UpgradePart: String {
    case edge, head, bit, grip, limbs, string, lining, plates, soles, visor, mag, loader, scope, rounds, tines, line, core, kit
    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

struct UpgradeSpec {
    let ench: Ench
    let part: UpgradePart
    let extra: String?          // part-specific material (one per level x `extraN`)
    let extraN: Int
    let advanced: Bool          // +3 experience levels a step
    let accent: V3              // its colour on the model
}

enum Upgrades {
    static let specs: [Ench: UpgradeSpec] = {
        func s(_ e: Ench, _ p: UpgradePart, _ x: String?, _ n: Int = 1, adv: Bool = false, _ c: V3) -> (Ench, UpgradeSpec) {
            (e, UpgradeSpec(ench: e, part: p, extra: x, extraN: n, advanced: adv, accent: c))
        }
        let steel = V3(0.85, 0.9, 0.98), gold = V3(1, 0.82, 0.3), leather = V3(0.45, 0.28, 0.15), iron = V3(0.72, 0.72, 0.75)
        return Dictionary(uniqueKeysWithValues: [
            s(.sharpness, .edge, "flint", 1, steel), s(.smite, .edge, "gold_nugget", 2, V3(1, 0.95, 0.75)),
            s(.baneOfArthropods, .edge, "spider_eye", 1, V3(0.45, 0.85, 0.35)), s(.knockback, .grip, "iron_nugget", 2, iron),
            s(.fireAspect, .edge, "blaze_powder", 1, V3(1, 0.45, 0.1)), s(.looting, .grip, "leather", 1, leather),
            s(.sweepingEdge, .edge, "flint", 2, V3(0.7, 0.85, 1)),
            s(.efficiency, .bit, "copper_ingot", 1, V3(0.95, 0.55, 0.3)), s(.silkTouch, .bit, "amethyst_shard", 2, V3(0.75, 0.5, 0.95)),
            s(.unbreaking, .head, "iron_ingot", 1, iron), s(.fortune, .bit, "lapis_lazuli", 3, V3(0.2, 0.35, 0.95)),
            s(.power, .limbs, "string", 2, V3(0.3, 0.2, 0.12)), s(.punch, .limbs, "iron_nugget", 2, iron),
            s(.flame, .string, "coal", 2, V3(1, 0.45, 0.1)), s(.infinity, .string, "leather", 4, adv: true, leather),
            s(.luckOfTheSea, .line, "gold_nugget", 2, gold), s(.lure, .line, "spider_eye", 1, V3(0.85, 0.3, 0.3)),
            s(.loyalty, .tines, "string", 4, V3(0.9, 0.9, 0.85)), s(.impaling, .tines, "flint", 2, steel),
            s(.riptide, .tines, "prismarine_shard", 2, V3(0.35, 0.75, 0.7)), s(.channeling, .tines, "copper_ingot", 4, adv: true, V3(0.95, 0.55, 0.3)),
            s(.multishot, .string, "iron_ingot", 2, iron), s(.quickCharge, .grip, "iron_ingot", 1, iron), s(.piercing, .string, "flint", 2, steel),
            s(.mending, .kit, "ender_pearl", 1, adv: true, V3(0.3, 0.9, 0.55)),
            s(.density, .core, "iron_ingot", 2, V3(0.35, 0.35, 0.4)), s(.breach, .head, "flint", 3, steel),
            s(.windBurst, .core, "breeze_rod", 1, adv: true, V3(0.75, 0.8, 1)), s(.lunge, .grip, "leather", 1, leather),
            s(.extendedMag, .mag, "iron_ingot", 2, iron), s(.quickReload, .loader, "iron_ingot", 1, iron),
            s(.stability, .scope, "glass", 1, V3(0.25, 0.3, 0.35)), s(.penetration, .rounds, "steel_ingot", 1, V3(0.9, 0.85, 0.4)),
            s(.incendiary, .rounds, "blaze_powder", 2, V3(1, 0.4, 0.1)),
            s(.protection, .lining, "white_wool", 2, V3(0.9, 0.9, 0.85)), s(.fireProtection, .lining, "clay_ball", 2, V3(1, 0.5, 0.2)),
            s(.blastProtection, .plates, "iron_ingot", 1, iron), s(.projectileProtection, .plates, "leather", 2, leather),
            s(.featherFalling, .soles, "white_wool", 2, V3(0.9, 0.9, 0.85)), s(.respiration, .visor, "glass", 1, V3(0.6, 0.85, 1)),
            s(.aquaAffinity, .visor, "glass", 1, V3(0.4, 0.7, 1)), s(.thorns, .plates, "cactus", 2, V3(0.3, 0.6, 0.25)),
            s(.depthStrider, .soles, "prismarine_shard", 2, V3(0.35, 0.75, 0.7)), s(.frostWalker, .soles, "packed_ice", 2, adv: true, V3(0.7, 0.85, 1)),
            s(.soulSpeed, .soles, "soul_sand", 2, adv: true, V3(0.45, 0.35, 0.3)), s(.swiftSneak, .soles, "white_wool", 2, adv: true, V3(0.9, 0.9, 0.85)),
        ])
    }()

    static func isUpgrade(_ e: Ench) -> Bool { specs[e] != nil }

    // Old saves: the same storage, minus the curses (and anything that isn't an upgrade).
    static func convert(_ v: UInt64) -> UInt64 {
        guard v != 0 else { return 0 }
        let l = Enchant.list(v)
        let kept = l.filter { isUpgrade($0.0) }
        return kept.count == l.count ? v : Enchant.pack(kept)
    }

    // The upgrade lines an item takes (its tree), in the order the bench lists them.
    static func tree(_ item: ItemID) -> [Ench] {
        let k = Items.key(item)
        guard k != "book" && k != "enchanted_book" else { return [] }
        return Ench.allCases.filter { isUpgrade($0) && Enchant.applies($0, item, table: false) }
    }

    // The item's own material for a step (nil: none needed) and how many.
    static func base(_ item: ItemID, level: Int) -> (String, Int)? {
        let k = Items.key(item)
        var m = Enchant.repairMaterial(item)
        if m == nil {
            switch k {
            case "bow", "fishing_rod": m = "string"
            case "crossbow": m = "iron_ingot"
            case "trident": m = "prismarine_shard"
            default: m = nil
            }
        }
        guard let mat = m, Items.has(mat) else { return nil }
        switch mat {
        case "diamond", "netherite_ingot", "breeze_rod": return (mat, max(1, (level + 1) / 2))
        case "oak_planks", "cobblestone", "string", "leather": return (mat, 2 * level)
        default: return (mat, level)
        }
    }

    struct Cost { var xp: Int; var items: [(ItemID, Int)] }
    static func cost(_ item: ItemID, _ e: Ench, level: Int) -> Cost {
        let sp = specs[e]
        var items: [(ItemID, Int)] = []
        if let (m, n) = base(item, level: level) { items.append((Items.id(m), n)) }
        if let x = sp?.extra, Items.has(x) {
            let id = Items.id(x)
            let n = (sp?.extraN ?? 1) * level
            if let i = items.firstIndex(where: { $0.0 == id }) { items[i].1 += n } else { items.append((id, n)) }
        }
        return Cost(xp: level + 1 + (sp?.advanced == true ? 3 : 0), items: items)
    }
    static func costText(_ c: Cost) -> String {
        c.items.map { "\($0.1) \(ItemStack($0.0, 1).def.display)" }.joined(separator: ", ")
    }

    // Can this item take the next level of `e`? (nil: yes; else why not)
    static func blocker(_ s: ItemStack, _ e: Ench) -> String? {
        let lv = Enchant.level(e, s)
        if lv >= Enchant.def(e).max { return "Fully upgraded" }
        let have = Enchant.list(s)
        if let c = have.first(where: { $0.0 != e && !Enchant.compatible($0.0, e) }) { return "Can't fit with \(Enchant.def(c.0).name)" }
        if lv == 0 && have.count >= 7 { return "No room for another part" }
        return nil
    }

    // Fits the next level of `e` to the stack in `c[i]`; charges experience and materials (not in creative).
    @discardableResult
    static func fit(_ g: Game, _ c: ItemContainer, _ i: Int, _ e: Ench) -> (String, Bool) {
        var s = c[i]
        guard !s.isEmpty, tree(s.item).contains(e) else { return ("That doesn't fit this item.", false) }
        if let why = blocker(s, e) { return (why + ".", false) }
        let lv = Enchant.level(e, s) + 1
        let k = cost(s.item, e, level: lv)
        if g.survival {
            if g.xpLevel < k.xp { return ("Needs \(k.xp) levels of experience (you have \(g.xpLevel)).", false) }
            for (it, n) in k.items where g.inventory.main.countOf(it) < n {
                return ("Needs \(n) \(ItemStack(it, 1).def.display) (you have \(g.inventory.main.countOf(it))).", false)
            }
            g.xpLevel -= k.xp
            for (it, n) in k.items { g.inventory.main.remove(it, n) }
            s = c[i]                            // (the materials never share the item's slot, but read it again)
        }
        var l = Enchant.list(s).filter { $0.0 != e }
        l.append((e, lv))
        s.ench = Enchant.pack(l)
        c[i] = s
        fitted += 1
        g.achieve("enchant")
        g.sfx(.smithing, 0.8)
        return ("\(Enchant.displayLine(e, lv)) fitted to the \(s.def.display).", true)
    }
    static var fitted = 0

    // MARK: On the model

    // Accents in the held sprite's own square (-1...1 both ways; the handle at bottom left, the head top right):
    // segments with a width and a colour, one per upgraded part.
    struct Accent { var a: V2; var b: V2; var w: Float; var color: V3 }
    static func accents(_ s: ItemStack) -> [Accent] {
        guard s.ench != 0 else { return [] }
        var out: [Accent] = []
        var seen = Set<String>()
        for (e, lv) in Enchant.list(s) {
            guard let sp = specs[e], !seen.contains(sp.part.rawValue) else { continue }
            seen.insert(sp.part.rawValue)
            let w: Float = 0.06 + 0.012 * Float(lv)
            switch sp.part {
            case .edge: out.append(Accent(a: V2(-0.15, 0.05), b: V2(0.6, 0.8), w: w * 0.6, color: sp.accent))
            case .grip: out.append(Accent(a: V2(-0.72, -0.48), b: V2(-0.48, -0.72), w: w * 1.6, color: sp.accent))
            case .head, .core: out.append(Accent(a: V2(0.22, 0.62), b: V2(0.62, 0.22), w: w, color: sp.accent))
            case .bit, .tines: out.append(Accent(a: V2(0.45, 0.75), b: V2(0.75, 0.45), w: w, color: sp.accent))
            case .limbs: out.append(Accent(a: V2(-0.7, 0.55), b: V2(-0.45, 0.75), w: w, color: sp.accent))
                         out.append(Accent(a: V2(0.55, -0.7), b: V2(0.75, -0.45), w: w, color: sp.accent))
            case .string, .line: out.append(Accent(a: V2(-0.2, 0.2), b: V2(0.2, -0.2), w: w * 0.6, color: sp.accent))
            case .kit: out.append(Accent(a: V2(-0.35, -0.15), b: V2(-0.15, -0.35), w: w * 1.2, color: sp.accent))
            default: continue
            }
        }
        return out
    }

    // Writes the accents as thin quads on both faces of a held sprite (centre c, half size h, right r, up u, the
    // face normal n, `t` the sprite's half thickness).
    static func writeAccents(_ wr: inout EntityWriter, _ s: ItemStack, center c: V3, half h: Float, right r: V3, up u: V3,
                             normal n: V3, thick t: Float, light: Float) {
        let ac = accents(s)
        guard !ac.isEmpty else { return }
        let solid = Int(Tex.id("smoke"))
        let uv = [V2(0.4, 0.4), V2(0.6, 0.4), V2(0.6, 0.6), V2(0.4, 0.6)]
        for a in ac {
            let pa: V3 = c + r * (a.a.x * h) + u * (a.a.y * h)
            let pb: V3 = c + r * (a.b.x * h) + u * (a.b.y * h)
            let d: V3 = pb - pa
            let side: V3 = simd_normalize(simd_cross(d, n)) * (a.w * h)
            let col = V4(a.color * light, 1)
            for f: Float in [-1, 1] {
                let o: V3 = n * (t * f)
                wr.quad([pa - side + o, pb - side + o, pb + side + o, pa + side + o], uv, solid, col)
            }
        }
    }

    // Extra gun parts for its upgrades, in the gun model's pixel space (its parts' bounds).
    static func gunParts(_ parts: [Part], mag: Set<Int>, _ ench: UInt64) -> [Part] {
        guard ench != 0, !parts.isEmpty else { return [] }
        var lo = parts[0].mn, hi = parts[0].mx
        for p in parts { lo = simd_min(lo, p.mn); hi = simd_max(hi, p.mx) }
        var out: [Part] = []
        let l = Enchant.list(ench)
        func lv(_ e: Ench) -> Int { l.first { $0.0 == e }?.1 ?? 0 }
        let midX = (lo.x + hi.x) / 2
        let len = hi.z - lo.z
        if lv(.stability) > 0 {                     // a scope on two rings, longer with each level
            let sl: Float = len * (0.22 + 0.06 * Float(lv(.stability)))
            let z0: Float = lo.z + len * 0.3
            out.append(Part(mn: V3(midX - 1.1, hi.y + 1, z0), mx: V3(midX + 1.1, hi.y + 3.2, z0 + sl), color: V3(0.12, 0.13, 0.15), pattern: 8))
            out.append(Part(mn: V3(midX - 0.9, hi.y + 1.4, z0 - 0.3), mx: V3(midX + 0.9, hi.y + 2.8, z0), color: V3(0.3, 0.55, 0.75), pattern: 11))
            for zr: Float in [0.25, 0.75] {
                out.append(Part(mn: V3(midX - 0.6, hi.y, z0 + sl * zr - 0.4), mx: V3(midX + 0.6, hi.y + 1, z0 + sl * zr + 0.4), color: V3(0.2, 0.2, 0.22)))
            }
        }
        if lv(.extendedMag) > 0 {                   // the magazine grows down
            for i in mag where i < parts.count {
                var m = parts[i]
                let d: Float = (m.mx.y - m.mn.y) * 0.35 * Float(lv(.extendedMag))
                m.mx.y = m.mn.y; m.mn.y -= d
                m.color = m.color * 0.85
                out.append(m)
            }
        }
        if lv(.penetration) > 0 || lv(.incendiary) > 0 {     // a band near the muzzle: brass for piercing, red-orange for incendiary
            let c = lv(.incendiary) > 0 ? V3(1, 0.4, 0.1) : V3(0.9, 0.8, 0.35)
            let z: Float = lo.z + len * 0.08
            out.append(Part(mn: V3(midX - 1.2, (lo.y + hi.y) / 2 + 0.5, z), mx: V3(midX + 1.2, hi.y - 0.5, z + 1.2), color: c, pattern: 9))
        }
        if lv(.quickReload) > 0 {                   // a loader lever by the grip
            let z: Float = lo.z + len * 0.62
            out.append(Part(mn: V3(hi.x - 0.2, lo.y + 2, z), mx: V3(hi.x + 0.8, lo.y + 3, z + 2.5), color: V3(0.75, 0.75, 0.78), pattern: 8))
        }
        return out
    }

    // MARK: Icons

    // Pips along an inventory icon's top edge, one per upgraded part (up to four), in the parts' colours.
    static func pips(_ s: ItemStack) -> [V3] {
        guard s.ench != 0 else { return [] }
        return Enchant.list(s).compactMap { specs[$0.0]?.accent }.prefix(4).map { $0 }
    }
}

// MARK: The Upgrade Bench screen

// The old enchanting table's block: pick an item you carry or wear, then buy the next level of a part.
final class UpgradeBenchMenu: ListMenu {
    var pick = 0                                // index into `items`
    var items: [(ItemContainer, Int)] {
        var out: [(ItemContainer, Int)] = []
        let inv = game.inventory
        let order = [inv.selected] + (0..<36).filter { $0 != inv.selected }
        for j in order where !inv.main[j].isEmpty && !Upgrades.tree(inv.main[j].item).isEmpty { out.append((inv.main, j)) }
        for j in 0..<4 where !inv.armor[j].isEmpty && !Upgrades.tree(inv.armor[j].item).isEmpty { out.append((inv.armor, j)) }
        return out
    }

    init(game g: Game) {
        super.init("Upgrade Bench", game: g)
        subtitle = "Fit parts with experience and materials"
        say(items.isEmpty ? "Bring a tool, weapon or armour to upgrade." : "Pick an upgrade.", good: true)
    }

    var current: (ItemContainer, Int)? {
        let its = items
        guard !its.isEmpty else { return nil }
        return its[min(pick, its.count - 1)]
    }

    override var rows: [Row] {
        corner = game.survival ? "Level \(game.xpLevel)" : "Creative"
        let its = items
        guard let (c, i) = current else { return [] }
        let s = c[i]
        let where_ = c === game.inventory.armor ? "worn" : (i == game.inventory.selected ? "in hand" : "carried")
        var out = [Row(icon: s, name: s.def.display, detail: its.count > 1 ? "\(where_): press for the next item (\(min(pick, its.count - 1) + 1) of \(its.count))" : where_,
                       value: "", enabled: its.count > 1)]
        for e in Upgrades.tree(s.item) {
            let lv = Enchant.level(e, s)
            let part = Upgrades.specs[e]?.part.name ?? ""
            if let why = Upgrades.blocker(s, e) {
                out.append(Row(icon: .empty, name: lv > 0 ? Enchant.displayLine(e, lv) : Enchant.def(e).name, detail: "\(part): \(why)", value: "", enabled: false))
                continue
            }
            let k = Upgrades.cost(s.item, e, level: lv + 1)
            let afford = !game.survival || (game.xpLevel >= k.xp && k.items.allSatisfy { game.inventory.main.countOf($0.0) >= $0.1 })
            let mats = Upgrades.costText(k)
            out.append(Row(icon: k.items.first.map { ItemStack($0.0, 1) } ?? .empty, name: Enchant.displayLine(e, lv + 1),
                           detail: "\(part)" + (mats.isEmpty ? "" : ": " + mats), value: "\(k.xp) lv", enabled: afford, good: afford))
        }
        return out
    }

    override func pressed(_ index: Int) {
        let its = items
        if index == 0 {
            guard its.count > 1 else { return }
            pick = (min(pick, its.count - 1) + 1) % its.count
            scroll = 0
            game.sfx(.click, 0.4)
            say("Working on the \(current.map { $0.0[$0.1].def.display } ?? "item").", good: true)
            return
        }
        guard let (c, i) = current else { return }
        let tree = Upgrades.tree(c[i].item)
        guard index - 1 < tree.count else { return }
        let r = Upgrades.fit(game, c, i, tree[index - 1])
        say(r.0, good: r.1)
    }
}
