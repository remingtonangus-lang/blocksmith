import Foundation

// First hour checks (Sources/Goals.swift; `questcheck --firsthour-only`, and part of every questcheck run): a fresh
// survival player past the tips always has one next goal, each step's goal moves on once it is met and never goes back,
// the path ends at the Blight, every goal names things by their Blocksmith names and fits the headset's HUD panel, the
// banner shows a new goal and fades, the inventory screen keeps it, and creative or hints off show nothing.
enum GoalTests {
    // What meets a step that isn't an advancement: carrying the thing.
    static let carry: [String: String] = ["wood": "oak_log", "pickaxe": "wooden_pickaxe", "furnace": "furnace", "eyes": "ender_eye"]

    static func run(game g: Game, check: (Bool, String) -> Void) {
        let st = Settings.shared
        let surv0 = g.survival, paused0 = g.paused, adv0 = g.advancements, step0 = st.tutorialStep, hints0 = st.tutorialHints, menu0 = g.menu
        let main0 = g.inventory.main.slots, armor0 = g.inventory.armor.slots, off0 = g.inventory.offhand.slots, en0 = HudExtras.enabled
        defer {
            g.survival = surv0; g.paused = paused0; g.advancements = adv0; st.tutorialStep = step0; st.tutorialHints = hints0
            for i in 0..<main0.count { g.inventory.main[i] = main0[i] }
            for i in 0..<armor0.count { g.inventory.armor[i] = armor0[i] }
            for i in 0..<off0.count { g.inventory.offhand[i] = off0[i] }
            if g.menu != nil && menu0 == nil { g.closeMenu() }
            HudExtras.enabled = en0
        }
        HudExtras.enabled = true
        st.tutorialHints = true; st.tutorialStep = Tutorial.steps
        g.survival = true; g.advancements = []; g.paused = false
        if g.menu != nil { g.closeMenu() }
        for i in 0..<g.inventory.main.slots.count { g.inventory.main[i] = .empty }
        for i in 0..<g.inventory.armor.slots.count { g.inventory.armor[i] = .empty }
        for i in 0..<g.inventory.offhand.slots.count { g.inventory.offhand[i] = .empty }

        // Names and fit.
        let raw = Goals.path.filter { $0.text.contains("_") }.map { $0.text }
        check(raw.isEmpty, "first hour: every goal names things by their game names (\(Goals.path.count) goals)\(raw.isEmpty ? "" : "; raw keys: " + raw.joined(separator: " | "))")
        var wide: [String] = []
        for (w, h) in [(Float(1024), Float(640)), (1280, 720), (1920, 1080)] {
            let L = HudLayout(w, h)
            for goal in Goals.path where Float(Font.width(goal.text)) * L.s + 16 * L.s > L.W { wide.append("\(Int(w))x\(Int(h)): \(goal.text)") }
        }
        check(wide.isEmpty, "first hour: every goal fits the HUD (headset panel 1024x640, 1280x720, 1080p)\(wide.isEmpty ? "" : ": " + wide.prefix(4).joined(separator: " | "))")
        let unknown = Goals.path.compactMap { goal -> String? in Advancements.index[goal.id] == nil && carry[goal.id] == nil ? goal.id : nil }
        check(unknown.isEmpty, "first hour: every goal is met by an advancement or by carrying an item\(unknown.isEmpty ? "" : ": " + unknown.joined(separator: ", "))")

        // Walk the path.
        var order: [String] = [], stuck: [String] = [], back: [String] = []
        for (i, goal) in Goals.path.enumerated() {
            guard let n = Goals.next(g) else { stuck.append("no goal before \(goal.id)"); break }
            order.append(n.id)
            if n.id != goal.id { stuck.append("\(n.id) instead of \(goal.id)"); break }
            if let k = carry[goal.id] { g.inventory.main[i % g.inventory.main.slots.count] = ItemStack(Items.id(k), 1) }
            else { g.advancements.insert(goal.id) }
            if let m = Goals.next(g), let j = Goals.path.firstIndex(where: { $0.id == m.id }), j <= i { back.append("\(goal.id) -> \(m.id)") }
        }
        check(stuck.isEmpty && back.isEmpty && order.count == Goals.path.count && Goals.next(g) == nil,
              "first hour: a next goal at every step of the path, each moves on once met (\(order.count)/\(Goals.path.count): \(order.first ?? "-") ... \(order.last ?? "-"), then none)"
              + (stuck.isEmpty ? "" : "; stuck: " + stuck.joined(separator: ", ")) + (back.isEmpty ? "" : "; went back: " + back.joined(separator: ", ")))
        // Carried items dropped after the next advancement: no step comes back.
        for i in 0..<g.inventory.main.slots.count { g.inventory.main[i] = .empty }
        check(Goals.next(g) == nil, "first hour: dropping the carried items later doesn't bring old goals back (next: \(Goals.next(g)?.id ?? "none"))")

        // The banner and the inventory line.
        g.advancements = ["root"]
        g.inventory.main[0] = .empty
        for _ in 0..<40 { g.tick(1.0 / 72) }
        let L = HudLayout(1280, 720)
        let shown = Goals.lines(g, L).map { $0.text }
        g.advancements.insert("mine_stone"); g.inventory.main[0] = ItemStack(Items.id("wooden_pickaxe"), 1)
        for _ in 0..<72 { g.tick(1.0 / 72) }
        let next = Goals.lines(g, L).map { $0.text }
        for _ in 0..<(72 * 9) { g.tick(1.0 / 72) }
        let faded = Goals.lines(g, L).isEmpty
        g.openInventory()
        let inv = Goals.lines(g, L).map { $0.text }
        g.closeMenu()
        check(shown.contains(where: { $0.contains(Goals.name("wooden_pickaxe")) })
              && next.contains(where: { $0.contains(Goals.name("stone_pickaxe")) }) && faded && inv.contains(where: { $0.contains(Goals.name("stone_pickaxe")) }),
              "first hour: a new goal shows in the HUD, fades after 8 s and stays on the inventory screen (shown '\(shown.last ?? "")', next '\(next.last ?? "")', faded \(faded), inventory '\(inv.last ?? "")')")

        // Creative and hints off: nothing.
        g.survival = false
        let creative = Goals.next(g) == nil
        g.survival = true
        st.tutorialHints = false
        let off = Goals.lines(g, L).isEmpty
        st.tutorialHints = true
        st.tutorialStep = 2
        for _ in 0..<40 { g.tick(1.0 / 72) }
        let tipsFirst = Goals.lines(g, L).isEmpty
        check(creative && off && tipsFirst, "first hour: no goals in creative (\(creative)), with the hints off (\(off)) or while the controls tips run (\(tipsFirst))")
    }
}
