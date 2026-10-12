import Foundation
import simd

// First hour (Q2, scorecard "First hour: a new player always knows a next goal"): once the controls tips are done, a
// survival player always has one next goal, the first unmet step of the story path (wood, a workbench, tools, a night
// in a bed, iron, titanium, the Emberdeep, the Hollow, the Blight). A new goal shows for a few seconds in the tips slot
// and stays at the top of the inventory screen. Steps are met by the saved advancements, or by what is carried for the
// first few; the goal is the step after the furthest one met, so it never goes backwards. Off with the tips (Options > Accessibility > Tutorial Hints) and in
// creative. `questcheck --firsthour-only` and the scripted playthrough check the path (Sources/GoalTests.swift).
enum Goals {
    struct Goal {
        let id: String
        let text: String
        let done: (Game) -> Bool
    }
    static func carries(_ g: Game, _ f: (String) -> Bool) -> Bool {
        for s in g.inventory.main.slots + g.inventory.armor.slots + g.inventory.offhand.slots where !s.isEmpty && f(Items.key(s.item)) { return true }
        return false
    }
    static func adv(_ id: String) -> (Game) -> Bool { { $0.advancements.contains(id) } }
    static func name(_ k: String) -> String { Items.has(k) ? Items.def(Items.id(k)).display : k }

    static let path: [Goal] = [
        Goal(id: "wood", text: "Break a tree trunk for wood") { g in g.advancements.contains("root") || carries(g) { $0.hasSuffix("_log") || $0.hasSuffix("_planks") || $0.hasSuffix("_stem") } },
        Goal(id: "root", text: "Turn the wood into planks and make a \(name("crafting_table"))", done: adv("root")),
        Goal(id: "pickaxe", text: "Make a \(name("wooden_pickaxe")) at the \(name("crafting_table"))") { g in g.advancements.contains("mine_stone") || carries(g) { $0.hasSuffix("_pickaxe") } },
        Goal(id: "mine_stone", text: "Dig down to stone with the pickaxe", done: adv("mine_stone")),
        Goal(id: "upgrade_tools", text: "Make a \(name("stone_pickaxe"))", done: adv("upgrade_tools")),
        Goal(id: "adventure/sleep_in_bed", text: "Before dark: make a bed from wool and planks and sleep in it", done: adv("adventure/sleep_in_bed")),
        Goal(id: "furnace", text: "Make a \(name("furnace")) from eight \(name("cobblestone"))") { g in g.advancements.contains("smelt_iron") || carries(g) { $0 == "furnace" } },
        Goal(id: "smelt_iron", text: "Mine iron ore and smelt it in the \(name("furnace"))", done: adv("smelt_iron")),
        Goal(id: "iron_tools", text: "Make an \(name("iron_pickaxe"))", done: adv("iron_tools")),
        Goal(id: "obtain_armor", text: "Make a piece of iron armour", done: adv("obtain_armor")),
        Goal(id: "mine_diamond", text: "Dig deep for \(name("diamond"))", done: adv("mine_diamond")),
        Goal(id: "form_obsidian", text: "Get \(name("obsidian")): water over still lava, then the \(name("diamond")) pickaxe", done: adv("form_obsidian")),
        Goal(id: "enter_the_nether", text: "Build an Ember Gate frame of \(name("obsidian")), light it and step through", done: adv("enter_the_nether")),
        Goal(id: "nether/find_fortress", text: "Find an Ash Foundry in the Emberdeep", done: adv("nether/find_fortress")),
        Goal(id: "nether/obtain_blaze_rod", text: "Take a \(name("blaze_rod")) from a Cinderwisp", done: adv("nether/obtain_blaze_rod")),
        Goal(id: "eyes", text: "Make an \(name("ender_eye")) from a \(name("ender_pearl")) and \(name("blaze_powder"))") { g in g.advancements.contains("follow_ender_eye") || carries(g) { $0 == "ender_eye" } },
        Goal(id: "follow_ender_eye", text: "Throw the eye and follow it to the Stronghold", done: adv("follow_ender_eye")),
        Goal(id: "enter_the_end", text: "Fill the Hollow Gate with eyes and step in", done: adv("enter_the_end")),
        Goal(id: "end/kill_dragon", text: "Defeat the Hollow Wyrm", done: adv("end/kill_dragon")),
        Goal(id: "nether/summon_wither", text: "Summon the Blight, if you dare", done: adv("nether/summon_wither")),
    ]

    static var on: Bool { HudExtras.enabled && Settings.shared.tutorialHints && Settings.shared.tutorialStep >= Tutorial.steps }
    // The next goal: the step after the furthest one met, so a skipped step (no night in a bed) never holds the goal
    // back once the player is past it (nil in creative or with the path walked).
    static func next(_ g: Game) -> Goal? {
        guard g.survival else { return nil }
        let last = path.lastIndex { $0.done(g) } ?? -1
        return last + 1 < path.count ? path[last + 1] : nil
    }

    // The banner: a new goal (or the first one after the tips, or after loading a world) shows for 8 s.
    static var shownID: String?
    static var shownAt: Double = -100
    static var lastCheck: Double = -100
    static var current: Goal?
    static weak var shownGame: Game?
    static func tick(_ g: Game) {
        if g !== shownGame { shownGame = g; shownID = nil; current = nil; lastCheck = -100 }     // a world loaded: show it again
        guard on, g.clock - lastCheck >= 0.5 else { return }
        lastCheck = g.clock
        let n = next(g)
        if n?.id != shownID {
            if shownID != nil, n != nil { g.sfx(.xp, 0.3) }
            shownID = n?.id; current = n; shownAt = g.clock
        }
    }
    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        guard on, Tutorial.ownSeat(g), let n = current, g.alive, !WeaponWheel.shared.open else { return [] }
        let inv = g.menu is InventoryMenu
        guard inv || (g.menu == nil && g.clock - shownAt < 8) else { return [] }
        let s = L.s
        let head = "Next goal", t = n.text
        let y = inv ? L.insetY + 4 * s : L.insetY + 34 * s
        let w = Float(max(Font.width(t), Font.width(head))) * s
        let x = floor((L.W - w) / 2)
        let a: Float = inv ? 1 : Float(min(1, (8 - (g.clock - shownAt)) * 2))
        return [HudLine(text: "", x: x - 8 * s, y: y - 4 * s, scale: s, bg: V4(0.08, 0.1, 0.16, 0.8 * a), box: V2(w + 16 * s, 26 * s)),
                HudLine(text: head, x: floor((L.W - Float(Font.width(head)) * s) / 2), y: y, scale: s, color: V4(1, 0.85, 0.35, a)),
                HudLine(text: t, x: floor((L.W - Float(Font.width(t)) * s) / 2), y: y + 12 * s, scale: s, color: V4(1, 1, 1, a))]
    }
}
