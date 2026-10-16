import Foundation

// P138 (Oct 12 PM, 17:55 "you can't just get upgrades. You have to find a recipe or blueprint first... anywhere that has
// chests"): in survival an upgrade line can be fitted at the Upgrade Bench only once its blueprint has been found and
// read. Blueprints turn up in chests everywhere (camps, wrecks, towns, bases, dungeons): about one chest in four holds
// one, of a random line (the advanced lines, like Mending, at a third the chance). Using one learns it for good (kept
// with the world, `Game.saveExtra` "blueprints"); a second copy of a known one sells to any general store. A world saved
// before blueprints knows every line already fitted to something the player carries. Creative fits anything.
enum Blueprints {
    static var on = true                            // (the host checks fit upgrades freely; the P138 check turns it on)
    static var known = Set<String>()                // Enchant keys
    static var seedPending = false                  // an older save: learn what the carried items already have
    static let chestChance = 0.25
    static var learned = 0

    static func key(_ e: Ench) -> String { Enchant.def(e).key }
    static func knows(_ g: Game, _ e: Ench) -> Bool {
        guard on, g.survival else { return true }
        if seedPending { seed(g) }
        return known.contains(key(e))
    }
    static func seed(_ g: Game) {
        seedPending = false
        for s in g.inventory.main.slots + g.inventory.armor.slots where !s.isEmpty {
            for (e, _) in Enchant.list(s) where Upgrades.isUpgrade(e) { known.insert(key(e)) }
        }
    }

    // A blueprint stack for line e.
    static func stack(_ e: Ench) -> ItemStack {
        var s = ItemStack(Items.id("upgrade_blueprint"), 1)
        s.tag = e.rawValue + 1
        s.label = "Blueprint: " + Enchant.def(e).name
        return s
    }
    static func line(_ s: ItemStack) -> Ench? {
        guard !s.isEmpty, Items.key(s.item) == "upgrade_blueprint", s.tag > 0 else { return nil }
        return Ench(rawValue: s.tag - 1)
    }

    // A random line for a chest (advanced lines a third as often).
    static func random(_ rng: inout SRng) -> Ench? {
        let lines = Upgrades.specs.values.sorted { $0.ench.rawValue < $1.ench.rawValue }
        let total = lines.reduce(0) { $0 + ($1.advanced ? 1 : 3) }
        guard total > 0 else { return nil }
        var r = rng.int(total)
        for l in lines { r -= l.advanced ? 1 : 3; if r < 0 { return l.ench } }
        return nil
    }

    // Loot.fill: one chest in four gains a blueprint (not the barrels' sundries, trial vaults, brushed sand or tills).
    static func addToChest(_ c: ItemContainer, table: String, rng: inout SRng) {
        guard table != "base_sundries", !table.hasPrefix("trial"), !table.hasPrefix("archaeology"), !table.hasPrefix("shop_register"),
              c.count > 1 else { return }
        guard rng.int(1000) < Int(chestChance * 1000), let e = random(&rng) else { return }
        let free = c.slots.indices.filter { c[$0].isEmpty }
        guard !free.isEmpty else { return }
        c[free[rng.int(free.count)]] = stack(e)
    }
}

extension Game {
    // Reading a blueprint learns its line.
    func blueprintUse() -> Bool {
        guard let e = Blueprints.line(held) else { return false }
        let k = Blueprints.key(e)
        if Blueprints.known.contains(k) && survival {
            onToast?("You already know the \(Enchant.def(e).name) blueprint")
            return true
        }
        Blueprints.known.insert(k)
        Blueprints.learned += 1
        if survival { consumeHeld() }
        sfx(.pageTurn, 0.8, at: player.pos)
        let part = Upgrades.specs[e]?.part.name ?? ""
        onToast?("Blueprint learned: \(Enchant.def(e).name) (\(part))")
        return true
    }
}
