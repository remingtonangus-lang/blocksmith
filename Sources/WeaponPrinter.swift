import Foundation
import simd

// H5: the Capital weapon printer. The Capital prints its arms from three machine parts no one else makes, and each of
// its bases keeps one in its workshop: a Printer Frame, a Feed Assembly or a Barrel Die (which one is fixed by the
// base). Take a base (a Greywall base taken, a Capital citadel cleared) and walk into it to collect its part; it takes
// several bases to hold all three. The three parts, a block of iron and a crafting table make the printer. Using it
// lists the Capital guns and the components the crafting recipes ask for (Firing Mechanism, Targeting Optic): each
// prints from ingots, redstone and gunpowder, no looted components needed.
enum WeaponPrinter {
    static let key = "weapon_printer"
    static let parts: [(key: String, name: String)] = [("printer_frame", "Printer Frame"), ("printer_feed", "Feed Assembly"),
                                                       ("printer_die", "Barrel Die")]

    // The part a base keeps (deterministic, like BaseSpecialties.of, with its own salt).
    static func part(of base: String) -> Int {
        var h: UInt64 = 1469598103934665603 ^ 0x9E3779B97F4A7C15
        for b in base.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int((h >> 7) % 3)
    }

    struct Job { let out: String; let count: Int; let cost: [(String, Int)] }
    static let jobs: [Job] = [
        Job(out: "gun_sidearm", count: 1, cost: [("steel_ingot", 3), ("redstone", 2)]),
        Job(out: "gun_rifle", count: 1, cost: [("steel_ingot", 6), ("redstone", 3), ("gunpowder", 2)]),
        Job(out: "gun_shotgun", count: 1, cost: [("steel_ingot", 4), ("iron_ingot", 3), ("redstone", 2)]),
        Job(out: "gun_sniper", count: 1, cost: [("steel_ingot", 6), ("glass", 2), ("redstone", 4)]),
        Job(out: "gun_launcher", count: 1, cost: [("steel_ingot", 8), ("tnt", 2), ("redstone", 4)]),
        Job(out: "gun_arc", count: 1, cost: [("steel_ingot", 4), ("gold_ingot", 2), ("redstone", 8)]),
        Job(out: "firing_mechanism", count: 1, cost: [("steel_ingot", 2), ("redstone", 2), ("gold_nugget", 3)]),
        Job(out: "targeting_optic", count: 1, cost: [("steel_ingot", 1), ("glass", 2), ("copper_ingot", 2)]),
        Job(out: "capital_rounds", count: 32, cost: [("steel_ingot", 2), ("copper_ingot", 2), ("gunpowder", 4)]),
    ]

    static func recipes() -> [Recipe?] {
        [Recipes.shapeless(parts.map { $0.key } + ["iron_block", "crafting_table"], key)]
    }
}

extension ItemRegistry {
    func registerPrinterParts() {
        let looks: [(String, UInt32, [Character: UInt32])] = [("module", 0x6A7078, ["c": 0xC8A24A, "d": 0x2A2E32]),
                                                              ("mechanism", 0x5A6068, ["c": 0x58A0D8]),
                                                              ("optic", 0x3A3E44, ["c": 0xD8742A])]
        for (i, p) in WeaponPrinter.parts.enumerated() where !has(p.key) {
            var d = ItemDef(p.key, p.name)
            d.sprite = Sprite(mask: looks[i].0, base: looks[i].1, extras: looks[i].2)
            d.maxStack = 16
            add(d)
        }
    }
}

extension BlockRegistry {
    func registerWeaponPrinter() {
        guard !has(WeaponPrinter.key) else { return }
        var d = BlockDef(WeaponPrinter.key, "Weapon Printer")
        d.tex = ["ship_engine_side", "ship_engine_side", "weapon_printer_top", "ship_metal", "ship_engine_side", "ship_engine_side"]
        d.hardness = 3.5; d.resistance = 6; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone
        add(d)
    }
}

extension TextureGen {
    // A steel bed with a print head on its gantry and a half-printed receiver under it.
    static func weaponPrinterPainters(_ p: inout [String: Painter]) {
        p["weapon_printer_top"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x2E3236) }
            if y == 4 && x > 1 && x < 14 { return hex(0xC9A23A) }                          // the gantry
            if (x == 7 || x == 8) && (y == 5 || y == 6) { return hex(0x58A0D8) }          // the head
            if y >= 8 && y <= 11 && x >= 3 && x <= 12 && !(y >= 10 && x > 6) { return hex(0x4A4F55, 0.9 + 0.1 * r(x, y, 3301)) }   // the part
            return hex(0x7A8088, 0.9 + 0.12 * r(x, y, 3302))
        }
    }
}

extension Game {
    // H5: a base of yours hands over its printer part when you walk into it (once a base). From baseSpecialtyTick.
    func printerPartTick(_ base: String, _ c: V3) {
        let tag = "part:" + base
        guard !BaseSpecialties.given.contains(tag) else { return }
        let pp = player.pos
        guard simd_length(V2(c.x - pp.x, c.z - pp.z)) < BaseSpecialties.reach, abs(c.y - pp.y) < 24 else { return }
        let k = WeaponPrinter.part(of: base)
        let pk = WeaponPrinter.parts[k].key
        guard Items.has(pk) else { return }
        BaseSpecialties.given.insert(tag)
        let rest = inventory.add(ItemStack(Items.id(pk), 1))
        if !rest.isEmpty { dropItem(rest) }
        var kinds = Set<Int>()
        for g in BaseSpecialties.given where g.hasPrefix("part:") { kinds.insert(WeaponPrinter.part(of: String(g.dropFirst(5)))) }
        sfx(.levelUp, 0.6, at: pp)
        onToast?(kinds.count >= 3 ? "Workshop: you take its \(WeaponPrinter.parts[k].name). That's all three printer parts: craft the Weapon Printer"
                                  : "Workshop: you take its \(WeaponPrinter.parts[k].name) (\(kinds.count) of 3 printer parts; other bases keep the rest)")
    }
}

// The printer's screen: one row a job; a press prints it if the materials are in the pack (free in creative).
final class WeaponPrinterMenu: ListMenu {
    init(game g: Game) {
        super.init("Weapon Printer", game: g)
        subtitle = "Prints Capital arms from raw materials"
        say("Pick something to print.", good: true)
    }

    func affordable(_ j: WeaponPrinter.Job) -> Bool {
        !game.survival || j.cost.allSatisfy { Items.has($0.0) && game.inventory.main.countOf(Items.id($0.0)) >= $0.1 }
    }

    override var rows: [Row] {
        corner = game.survival ? "" : "Creative"
        return WeaponPrinter.jobs.filter { Items.has($0.out) }.map { j in
            let s = ItemStack(Items.id(j.out), j.count)
            let cost = j.cost.map { "\($0.1) \(Items.has($0.0) ? Items.def(Items.id($0.0)).display : $0.0)" }.joined(separator: ", ")
            return Row(icon: s, name: j.count > 1 ? "\(s.def.display) x\(j.count)" : s.def.display, detail: cost,
                       value: affordable(j) ? "Print" : "Short", enabled: true, good: affordable(j))
        }
    }

    override func pressed(_ index: Int) {
        let js = WeaponPrinter.jobs.filter { Items.has($0.out) }
        guard index < js.count else { return }
        let j = js[index]
        guard affordable(j) else {
            let short = j.cost.filter { !Items.has($0.0) || game.inventory.main.countOf(Items.id($0.0)) < $0.1 }
                .map { "\($0.1) \(Items.has($0.0) ? Items.def(Items.id($0.0)).display : $0.0)" }
            say("Not enough: needs " + short.joined(separator: ", ") + ".", good: false)
            game.sfx(.villagerNo, 0.4)
            return
        }
        if game.survival { for (k, n) in j.cost { _ = game.inventory.main.remove(Items.id(k), n) } }
        var out = ItemStack(Items.id(j.out), j.count)
        if Guns.index(out.item) != nil { out.tag = Guns.magSize(out) }        // printed with a full magazine
        let rest = game.inventory.add(out)
        if !rest.isEmpty { game.dropItem(rest) }
        game.sfx(.anvil, 0.6)
        say("Printed the \(out.def.display).", good: true)
    }
}
