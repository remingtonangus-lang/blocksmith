import Foundation

// First hour and spine checks (Sources/Goals.swift, Spine.swift; `questcheck --firsthour-only`, and part of every
// questcheck run): a fresh survival player past the tips always has one next goal, each step's goal moves on once it is
// met and never goes back, the path walks the spine's six stages in order (iron, a town, Greywall, the fleet, hell, the
// Capital) with none of the reference chain on it, every goal names things by their Blocksmith names and fits the
// headset's HUD panel, the fleet sails once a Greywall Fortress falls, the banner shows a new goal and fades, the
// inventory screen keeps it, and creative or hints off show nothing.
enum GoalTests {
    // What meets a step that isn't an advancement: carrying the thing.
    static let carry: [String: String] = ["wood": "oak_log", "pickaxe": "wooden_pickaxe", "furnace": "furnace"]

    static func run(game g: Game, check: (Bool, String) -> Void) {
        let st = Settings.shared
        let pos0 = g.player.pos, fly0 = g.player.flying, time0 = g.time, surv0 = g.survival, paused0 = g.paused, adv0 = g.advancements, step0 = st.tutorialStep, hints0 = st.tutorialHints, menu0 = g.menu
        let main0 = g.inventory.main.slots, armor0 = g.inventory.armor.slots, off0 = g.inventory.offhand.slots, en0 = HudExtras.enabled
        let dragon0 = g.dragonKilled, ash0 = g.ashVictory
        Spine.paused = true                // (the walk sets advancements by hand; the world's own state stays out of it)
        defer {
            Spine.paused = false; g.dragonKilled = dragon0; g.ashVictory = ash0
            g.survival = surv0; g.paused = paused0; g.advancements = adv0; st.tutorialStep = step0; st.tutorialHints = hints0
            for i in 0..<main0.count { g.inventory.main[i] = main0[i] }
            for i in 0..<armor0.count { g.inventory.armor[i] = armor0[i] }
            for i in 0..<off0.count { g.inventory.offhand[i] = off0[i] }
            if g.menu is DeathMenu { g.menu = nil } else if g.menu != nil { g.closeMenu() }
            g.menu = menu0; g.player.pos = pos0; g.player.vel = .zero; g.player.flying = fly0; g.time = time0
            HudExtras.enabled = en0
        }
        HudExtras.enabled = true
        st.tutorialHints = true
        g.survival = true; g.advancements = []; g.paused = false
        // Hovering at noon, healthy: the banner check ticks the game for ten seconds.
        g.player.flying = true; g.player.vel = .zero; g.time = DAY_LENGTH * 0.25; g.health = 20; g.alive = true
        if g.menu is DeathMenu { g.menu = nil } else if g.menu != nil { g.closeMenu() }
        for i in 0..<g.inventory.main.slots.count { g.inventory.main[i] = .empty }
        for i in 0..<g.inventory.armor.slots.count { g.inventory.armor[i] = .empty }
        for i in 0..<g.inventory.offhand.slots.count { g.inventory.offhand[i] = .empty }

        // Names and fit.
        let raw = Goals.all.filter { $0.text.contains("_") || $0.text.range(of: "\\b(a [AEIOU]|an [^AEIOUaeiou ])", options: .regularExpression) != nil }.map { $0.text }
        check(raw.isEmpty, "first hour: every goal names things by their game names, with the right article (\(Goals.all.count) goals)\(raw.isEmpty ? "" : "; raw keys: " + raw.joined(separator: " | "))")
        var wide: [String] = []
        for (w, h) in [(Float(1024), Float(640)), (1280, 720), (1920, 1080)] {
            let L = HudLayout(w, h)
            for goal in Goals.all where Float(Font.width(goal.text)) * L.s + 16 * L.s > L.W { wide.append("\(Int(w))x\(Int(h)): \(goal.text)") }
        }
        check(wide.isEmpty, "first hour: every goal fits the HUD (headset panel 1024x640, 1280x720, 1080p)\(wide.isEmpty ? "" : ": " + wide.prefix(4).joined(separator: " | "))")
        let unknown = Goals.all.compactMap { goal -> String? in Advancements.index[goal.id] == nil && carry[goal.id] == nil ? goal.id : nil }
        check(unknown.isEmpty, "first hour: every goal is met by an advancement or by carrying an item\(unknown.isEmpty ? "" : ": " + unknown.joined(separator: ", "))")

        // Walk the path.
        g.advancements = []
        for i in 0..<g.inventory.main.slots.count { g.inventory.main[i] = .empty }
        let path = Goals.path(g)
        var order: [String] = [], stuck: [String] = [], back: [String] = []
        for (i, goal) in path.enumerated() {
            guard let n = Goals.next(g) else { stuck.append("no goal before \(goal.id)"); break }
            order.append(n.id)
            if n.id != goal.id { stuck.append("\(n.id) instead of \(goal.id)"); break }
            if let k = carry[goal.id] { g.inventory.main[i % g.inventory.main.slots.count] = ItemStack(Items.id(k), 1) }
            else { g.advancements.insert(goal.id) }
            if let m = Goals.next(g), let j = path.firstIndex(where: { $0.id == m.id }), j <= i { back.append("\(goal.id) -> \(m.id)") }
        }
        check(stuck.isEmpty && back.isEmpty && order.count == path.count && Goals.next(g) == nil,
              "first hour: a next goal at every step, each moves on once met (\(order.count)/\(path.count): \(order.first ?? "-") ... \(order.last ?? "-"), then none)"
              + (stuck.isEmpty ? "" : "; stuck: " + stuck.joined(separator: ", ")) + (back.isEmpty ? "" : "; went back: " + back.joined(separator: ", ")))
        // Carried items dropped after the next advancement: no step comes back.
        for i in 0..<g.inventory.main.slots.count { g.inventory.main[i] = .empty }
        check(Goals.next(g) == nil, "first hour: dropping the carried items later doesn't bring old goals back (next: \(Goals.next(g)?.id ?? "none"))")

        // Y1: the spine's six stages in order, each with a step, the reference chain off the main path.
        let stages = path.map { $0.stage }
        let ordered = zip(stages, stages.dropFirst()).allSatisfy { $0 <= $1 } && Set(stages) == Set(0..<Spine.stages.count)
        let chain = ["nether/find_fortress", "nether/obtain_blaze_rod", "eyes", "follow_ender_eye", "enter_the_end", "end/kill_dragon",
                     "enter_the_nether", "form_obsidian"]
        let onPath = path.filter { chain.contains($0.id) }.map { $0.id }
        let lastStage = path.last.map { Spine.stages[$0.stage] } ?? "-"
        check(ordered && onPath.isEmpty && lastStage == "The Capital",
              "spine: the goals walk \(Spine.stages.joined(separator: ", ")) in order (ends at \(lastStage)), no reference-chain step on the path\(onPath.isEmpty ? "" : ": " + onPath.joined(separator: ", "))")
        // Y2: each stage's goal names the key it hands over; Y3: the fleet sails once a Greywall Fortress falls.
        func text(_ id: String) -> String { path.first { $0.id == id }?.text ?? "" }
        let keys = text("spine/greywall_base").contains("dispatch") && text("spine/greywall_top").contains("orders")
            && text("spine/flagship").contains(Goals.name("ember_charge"))
        g.dragonKilled = false; g.ashVictory = false
        g.advancements = ["spine/greywall_base"]
        let before = g.fleetSails
        g.advancements.insert("spine/greywall_top")
        let after = g.fleetSails
        let items = ["greywall_dispatch", "naval_orders", "chancellor_ledger"].filter { Items.has($0) }.count
        check(keys && !before && after && items == 3,
              "spine: each stage hands over the next key (dispatch, naval orders, Ember Charge: \(keys); \(items)/3 items), the fleet sails once a Fortress falls (before \(before), after \(after))")
        g.advancements = []

        // The banner and the inventory line, with nothing left around from earlier checks that could kill the player
        // during the ten seconds (the full run: a DeathMenu took the banner).
        let mobs0 = g.mobs.mobs, riding0 = g.riding, credits0 = g.credits, creditsAsh0 = g.creditsAsh
        defer { g.mobs.mobs = mobs0; g.riding = riding0; g.credits = credits0; g.creditsAsh = creditsAsh0 }
        g.credits = nil; g.creditsAsh = false
        g.mobs.mobs.removeAll(); g.world.pendingMobs.removeAll(); g.riding = nil
        g.effects.clear(); g.onFire = 0; g.air = 15; g.hunger = 20; g.health = 20; g.alive = true
        g.lastDeath = nil
        Goals.shownID = nil; Goals.current = nil; Goals.lastCheck = -100
        g.advancements = ["root"]
        g.inventory.main[0] = .empty
        for _ in 0..<40 { g.tick(1.0 / 72) }
        let L = HudLayout(1280, 720)
        let shown = Goals.lines(g, L).map { $0.text }
        let state = "menu \(g.menu.map { "\(type(of: $0))" } ?? "none"), died \(g.lastDeath.map { "at \($0)" } ?? "no"), health \(g.health), alive \(g.alive), paused \(g.paused), coop \(g.coop.active), wheel \(WeaponWheel.shared.open), goal \(Goals.current?.id ?? "none")"
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
              "first hour: a new goal shows in the HUD, fades after 8 s and stays on the inventory screen (shown '\(shown.last ?? "")', next '\(next.last ?? "")', faded \(faded), inventory '\(inv.last ?? "")'; \(state))")

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
