import Foundation
import simd

// Potions: every brewable type in normal / extended / strong form, as drinkable, splash and
// lingering items plus tipped arrows (reference durations and amplifiers).
struct PotionType {
    let key: String                     // "healing", "long_swiftness", "strong_poison"
    let display: String                 // "Healing"
    let effects: [(Effect, Float, Int)] // effect, seconds, amplifier
    let color: UInt32
}

enum Potions {
    static let types: [PotionType] = {
        var t: [PotionType] = []
        func add(_ k: String, _ d: String, _ fx: [(Effect, Float, Int)], color: UInt32? = nil) {
            let c = color ?? fx.first.map { $0.0.color } ?? 0x385DC6
            t.append(PotionType(key: k, display: d, effects: fx, color: c))
        }
        add("water", "Water Bottle", [], color: 0x385DC6)
        add("mundane", "Mundane Potion", [], color: 0x385DC6)
        add("thick", "Thick Potion", [], color: 0x385DC6)
        add("awkward", "Awkward Potion", [], color: 0x385DC6)
        func trio(_ k: String, _ d: String, _ e: Effect, _ n: Float, _ long: Float?, _ strong: (Float, Int)?) {
            add(k, d, [(e, n, 0)])
            if let l = long { add("long_" + k, d, [(e, l, 0)]) }
            if let s = strong { add("strong_" + k, d, [(e, s.0, s.1)]) }
        }
        trio("night_vision", "Night Vision", .nightVision, 180, 480, nil)
        trio("invisibility", "Invisibility", .invisibility, 180, 480, nil)
        trio("leaping", "Leaping", .jumpBoost, 180, 480, (90, 1))
        trio("fire_resistance", "Fire Resistance", .fireResistance, 180, 480, nil)
        trio("swiftness", "Swiftness", .speed, 180, 480, (90, 1))
        trio("slowness", "Slowness", .slowness, 90, 240, (20, 3))
        add("turtle_master", "the Tortoise", [(.slowness, 20, 3), (.resistance, 20, 2)])
        add("long_turtle_master", "the Tortoise", [(.slowness, 40, 3), (.resistance, 40, 2)])
        add("strong_turtle_master", "the Tortoise", [(.slowness, 20, 5), (.resistance, 20, 3)])
        trio("water_breathing", "Water Breathing", .waterBreathing, 180, 480, nil)
        trio("healing", "Healing", .instantHealth, 0, nil, (0, 1))
        trio("harming", "Harming", .instantDamage, 0, nil, (0, 1))
        trio("poison", "Poison", .poison, 45, 90, (21.6, 1))
        trio("regeneration", "Regeneration", .regeneration, 45, 90, (22.5, 1))
        trio("strength", "Strength", .strength, 180, 480, (90, 1))
        trio("weakness", "Weakness", .weakness, 90, 240, nil)
        trio("slow_falling", "Slow Falling", .slowFalling, 90, 240, nil)
        add("luck", "Luck", [(.luck, 300, 0)])
        add("wind_charged", "Wind Charging", [(.windCharged, 180, 0)])
        add("weaving", "Weaving", [(.weaving, 180, 0)])
        add("oozing", "Oozing", [(.oozing, 180, 0)])
        add("infested", "Infestation", [(.infested, 180, 0)])
        return t
    }()
    static let byKey: [String: Int] = Dictionary(uniqueKeysWithValues: types.enumerated().map { ($0.element.key, $0.offset) })

    // Item forms: (prefix, display pattern, duration factor)
    static let forms: [(String, String, Float)] = [("potion", "Potion of %@", 1), ("splash_potion", "Splash Potion of %@", 1),
                                                   ("lingering_potion", "Lingering Potion of %@", 0.25), ("tipped_arrow", "Arrow of %@", 0.125)]

    static func itemName(_ form: String, _ type: String) -> String { "\(form)_\(type)" }

    // Reverse lookup filled at registration: item -> (form index, type index).
    static var info: [ItemID: (Int, Int)] = [:]

    static func potion(of item: ItemID) -> (form: Int, type: PotionType)? {
        guard let i = info[item] else { return nil }
        return (i.0, types[i.1])
    }
    static func item(_ form: Int, _ type: String) -> ItemID? {
        let n = itemName(forms[form].0, type)
        return Items.has(n) ? Items.id(n) : nil
    }

    static func displayName(_ form: Int, _ t: PotionType) -> String {
        if t.effects.isEmpty {
            let f = ["", "Splash ", "Lingering ", ""][form]
            if form == 3 { return "Tipped Arrow" }
            return t.key == "water" ? f + "Water Bottle" : f + t.display
        }
        var name = String(format: forms[form].1, t.display)
        if t.key.hasPrefix("strong_") { name += " II" }
        return name
    }

    // Tooltip lines: "Speed II (1:30)".
    static func lines(_ form: Int, _ t: PotionType) -> [String] {
        if t.effects.isEmpty { return ["No Effects"] }
        return t.effects.map { e in
            var s = e.0.name
            if e.2 > 0 { s += " " + Effect.roman(e.2 + 1) }
            if !e.0.instant {
                let secs = Int((e.1 * forms[form].2).rounded())
                s += String(format: " (%d:%02d)", secs / 60, secs % 60)
            }
            return s
        }
    }

    // MARK: Brewing (reference recipe table)

    // Base conversions from water / awkward.
    static let mixes: [(from: String, ingredient: String, to: String)] = {
        var m: [(String, String, String)] = []
        m.append(("water", "nether_wart", "awkward"))
        for i in ["redstone", "sugar", "ghast_tear", "rabbit_foot", "blaze_powder", "glistering_melon_slice", "spider_eye", "magma_cream"] {
            m.append(("water", i, "mundane"))
        }
        m.append(("water", "glowstone_dust", "thick"))
        m.append(("water", "fermented_spider_eye", "weakness"))
        let awk: [(String, String)] = [("golden_carrot", "night_vision"), ("rabbit_foot", "leaping"), ("magma_cream", "fire_resistance"),
                                       ("sugar", "swiftness"), ("turtle_helmet", "turtle_master"), ("pufferfish", "water_breathing"),
                                       ("glistering_melon_slice", "healing"), ("spider_eye", "poison"), ("ghast_tear", "regeneration"),
                                       ("blaze_powder", "strength"), ("phantom_membrane", "slow_falling"), ("breeze_rod", "wind_charged"),
                                       ("cobweb", "weaving"), ("slime_block", "oozing"), ("stone", "infested")]
        for (i, to) in awk { m.append(("awkward", i, to)) }
        // Corruption with a fermented spider eye.
        let fse: [(String, String)] = [("night_vision", "invisibility"), ("long_night_vision", "long_invisibility"),
                                       ("swiftness", "slowness"), ("long_swiftness", "long_slowness"), ("leaping", "slowness"),
                                       ("long_leaping", "long_slowness"), ("strong_swiftness", "strong_slowness"),
                                       ("healing", "harming"), ("strong_healing", "strong_harming"), ("poison", "harming"),
                                       ("long_poison", "harming"), ("strong_poison", "strong_harming")]
        for (a, b) in fse { m.append((a, "fermented_spider_eye", b)) }
        // Sparkstone extends, lumenstone strengthens.
        for t in types where t.key.hasPrefix("long_") { m.append((String(t.key.dropFirst(5)), "redstone", t.key)) }
        for t in types where t.key.hasPrefix("strong_") { m.append((String(t.key.dropFirst(7)), "glowstone_dust", t.key)) }
        return m
    }()

    static func isIngredient(_ item: ItemID) -> Bool {
        let k = Items.key(item)
        return k == "gunpowder" || k == "dragon_breath" || mixes.contains { $0.ingredient == k }
    }

    // Result of brewing `ingredient` into one bottle, or nil.
    static func brew(_ bottle: ItemID, _ ingredient: ItemID) -> ItemID? {
        guard case let (form, t)? = potion(of: bottle), form < 3 else { return nil }
        let ing = Items.key(ingredient)
        if ing == "gunpowder" { return form == 0 ? item(1, t.key) : nil }
        if ing == "dragon_breath" { return form == 1 ? item(2, t.key) : nil }
        guard let m = mixes.first(where: { $0.from == t.key && $0.ingredient == ing }) else { return nil }
        return item(form, m.to)
    }

    // MARK: Item registration

    static func register(_ reg: ItemRegistry) {
        for (fi, f) in forms.enumerated() {
            for (ti, t) in types.enumerated() {
                if fi == 3 && t.effects.isEmpty { continue }        // plain tipped arrows don't exist
                var d = ItemDef(itemName(f.0, t.key), displayName(fi, t))
                d.maxStack = fi == 3 ? 64 : 1
                d.drink = fi == 0
                d.texKey = fi == 3 ? "item_tipped_arrow" : (fi == 0 ? "item_potion_bottle" : (fi == 1 ? "item_splash_bottle" : "item_lingering_bottle"))
                d.overlay = fi == 3 ? "item_tipped_arrow_head" : "item_potion_liquid"
                d.overlayColor = t.color
                let id = reg.add(d)
                info[id] = (fi, ti)
            }
        }
    }

    // Bottle and liquid sprites (original pixel art).
    static func painters(_ p: inout [String: TextureGen.Painter]) {
        let bottle: [String] = [
            "................",
            "......1111......",
            "......1551......",
            ".......15.......",
            ".......15.......",
            "......1..1......",
            ".....1....1.....",
            "....1......1....",
            "...1........1...",
            "...1........1...",
            "...1........1...",
            "...1........1...",
            "....1......1....",
            ".....111111.....",
            "................",
            "................",
        ]
        let liquid: [String] = [
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "......4444......",
            ".....444444.....",
            "....44454444....",
            "....44544444....",
            "....44444444....",
            "....44444444....",
            ".....444444.....",
            "................",
            "................",
            "................",
        ]
        func mask(_ rows: [String], _ colors: [Character: V4]) -> TextureGen.Painter {
            let r = rows.map { Array($0) }
            return { x, y in
                guard y < r.count, x < r[y].count, let c = colors[r[y][x]] else { return TextureGen.clear }
                return c
            }
        }
        let glass = V4(0.82, 0.86, 0.95, 1), cork = V4(0.55, 0.38, 0.2, 1)
        p["item_potion_bottle"] = mask(bottle, ["1": glass, "5": cork])
        var splash = bottle
        splash[1] = ".....111111....."
        splash[2] = ".....155551....."
        p["item_splash_bottle"] = mask(splash, ["1": glass, "5": V4(0.65, 0.65, 0.7, 1)])
        var ling = bottle
        ling[1] = "......1111......"
        ling[2] = ".....155551....."
        p["item_lingering_bottle"] = mask(ling, ["1": glass, "5": V4(0.75, 0.55, 0.85, 1)])
        p["item_potion_liquid"] = mask(liquid, ["4": V4(1, 1, 1, 1), "5": V4(1, 1, 1, 0.55)])
        let arrow: [String] = [
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "........1.......",
            ".....a.1........",
            "......a.........",
            "....aa.a........",
            "...ff...........",
            "..ff............",
            ".f..............",
            "................",
        ]
        let head: [String] = [
            "................",
            "................",
            "................",
            "...........444..",
            "..........4444..",
            ".........44444..",
            "..........444...",
            "...........4....",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
        ]
        p["item_tipped_arrow"] = mask(arrow, ["1": V4(0.55, 0.55, 0.55, 1), "a": V4(0.42, 0.31, 0.17, 1), "f": V4(0.93, 0.93, 0.93, 1)])
        p["item_tipped_arrow_head"] = mask(head, ["4": V4(1, 1, 1, 1)])
    }
}

// MARK: Brewing stand block entity logic

extension BlockEntity {
    // Slots 0-2 bottles, 3 ingredient, 4 cinder powder. 20 s per brew; one powder = 20 brews.
    // Returns true when the bottle slots changed (for the block's bottle display).
    func tickBrewing() -> Bool {
        let c = container
        if fuel <= 0, !c[4].isEmpty, Items.key(c[4].item) == "blaze_powder" {
            fuel = 20
            var f = c[4]; f.count -= 1; c[4] = f
        }
        let ing = c[3]
        let can = !ing.isEmpty && (0..<3).contains { !c[$0].isEmpty && Potions.brew(c[$0].item, ing.item) != nil }
        if brewTime > 0 {
            if !can || ing.item != brewIngredient { brewTime = 0; return false }
            brewTime -= 1
            if brewTime == 0 {
                for i in 0..<3 where !c[i].isEmpty {
                    if let r = Potions.brew(c[i].item, ing.item) { c[i] = ItemStack(r, 1) }
                }
                var n = ing
                n.count -= 1
                let k = Items.key(ing.item)
                if n.count <= 0 { n = k == "dragon_breath" ? ItemStack(Items.id("glass_bottle"), 1) : .empty }
                c[3] = n
                return true
            }
        } else if can && fuel > 0 {
            fuel -= 1
            brewTime = 400
            brewIngredient = ing.item
        }
        return false
    }
}
