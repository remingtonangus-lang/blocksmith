import Foundation
import simd

// First hour and the game's spine (Q2, then Y1: "the Goals path follows THE GAME'S SPINE"): once the controls tips are
// done, a survival player always has one next goal, the first unmet step of the spine's six stages (Spine.swift):
//   1 Iron              wood, a workbench, tools, a night in a bed, iron, a full iron set (the iron rule)
//   2 Take a town       find one, then outgun its sheriff and deputies until it surrenders (a Greywall Dispatch)
//   3 Greywall Command  take a base, then a Fortress (its war room: the Naval Orders; the fleet sails)
//   4 The Meridian fleet read the orders, sink or seize a fleet frigate (her Ember Charge)
//   5 Hell              the charge through the Wardstone, the hell band, a Brimstone Keep, the Sealrock, the Ash Vault,
//                       the Ash Chancellor (his ledger names the Capital's citadels)
//   6 The Capital       storm a citadel, then break the Capital (three citadels cleared, or one by the Tidebreaker)
// The reference chain (Ember Gate, Foundry, rods, eyes, the Stronghold, the Hollow, the Blight) is side content now.
// A new goal chimes; it shows at the top of the inventory screen as a bare name (P328, NO TEXT: what, never how) with
// its stage and, where the target is known, a bearing to it (the world map carries it as the "Next objective"); P300: never as a banner over play. Steps are met by the
// saved advancements (the spine's own are granted by Spine.tick), or by what is carried for the first few; the goal is
// the step after the furthest one met, so it never goes backwards. Off with Options > Accessibility > Goals, and in
// creative. `questcheck --firsthour-only` and the scripted playthrough check the path
// (Sources/GoalTests.swift).
enum Goals {
    struct Goal {
        let id: String
        let stage: Int                     // 0...5: Spine.stages
        let text: String
        let done: (Game) -> Bool
        init(id: String, stage: Int, text: String, done: @escaping (Game) -> Bool) { self.id = id; self.stage = stage; self.text = text; self.done = done }
    }
    static func carries(_ g: Game, _ f: (String) -> Bool) -> Bool {
        for c in [g.inventory.main, g.inventory.armor, g.inventory.offhand] {
            for s in c.slots where !s.isEmpty && f(Items.key(s.item)) { return true }
        }
        return false
    }
    static func adv(_ id: String) -> (Game) -> Bool { { $0.advancements.contains(id) } }
    static func any(_ ids: [String]) -> (Game) -> Bool { { g in ids.contains { g.advancements.contains($0) } } }
    static func name(_ k: String) -> String { Items.has(k) ? Items.def(Items.id(k)).display : k }
    static func a(_ k: String) -> String { let n = name(k); return ("AEIOU".contains(n.first ?? "x") ? "an " : "a ") + n }

    // P328 (NO TEXT): each goal is a bare name, what the step is about, never how to do it.
    static let all: [Goal] = [
        // 1. Iron.
        Goal(id: "wood", stage: 0, text: "Wood") { g in g.advancements.contains("root") || carries(g) { $0.hasSuffix("_log") || $0.hasSuffix("_planks") || $0.hasSuffix("_stem") } },
        Goal(id: "root", stage: 0, text: name("crafting_table"), done: adv("root")),
        Goal(id: "pickaxe", stage: 0, text: name("wooden_pickaxe")) { g in g.advancements.contains("mine_stone") || carries(g) { $0.hasSuffix("_pickaxe") } },
        Goal(id: "mine_stone", stage: 0, text: "Stone", done: adv("mine_stone")),
        Goal(id: "upgrade_tools", stage: 0, text: name("stone_pickaxe"), done: adv("upgrade_tools")),
        Goal(id: "adventure/sleep_in_bed", stage: 0, text: "A Night's Sleep", done: adv("adventure/sleep_in_bed")),
        Goal(id: "furnace", stage: 0, text: name("furnace")) { g in g.advancements.contains("smelt_iron") || carries(g) { $0 == "furnace" } },
        Goal(id: "smelt_iron", stage: 0, text: name("iron_ingot"), done: adv("smelt_iron")),
        Goal(id: "iron_tools", stage: 0, text: name("iron_pickaxe"), done: adv("iron_tools")),
        Goal(id: "spine/iron_set", stage: 0, text: "Iron Armour", done: adv("spine/iron_set")),
        // 2. Take a town.
        Goal(id: "spine/find_town", stage: 1, text: "A Frontier Town", done: adv("spine/find_town")),
        Goal(id: "spine/take_town", stage: 1, text: "The Town's Sheriff", done: adv("spine/take_town")),
        // 3. Greywall Command, the proving ground.
        Goal(id: "spine/greywall_base", stage: 2, text: "A Greywall Base", done: adv("spine/greywall_base")),
        Goal(id: "spine/greywall_top", stage: 2, text: "A Greywall Fortress", done: adv("spine/greywall_top")),
        // 4. The Meridian fleet (it sails once a Fortress falls).
        Goal(id: "spine/fleet", stage: 3, text: name("naval_orders"), done: adv("spine/fleet")),
        // P139 (Oct 12 PM, "I'm not entirely sure what I'm supposed to be doing here"): the Ember Charge is a step of its
        // own; a fleet frigate carries one (a Capital vault's does as well, so carrying one meets the step).
        Goal(id: "spine/flagship", stage: 3, text: name("ember_charge")) { g in
            g.advancements.contains("spine/flagship") || carries(g) { $0 == HellGate.chargeKey }
        },
        // 5. Hell, down to the war below the world.
        Goal(id: "adventure/break_ward", stage: 4, text: "The Wardstone", done: any(["adventure/break_ward", "adventure/deep", "enter_the_nether"])),
        Goal(id: "adventure/deep_hell", stage: 4, text: "The Fire Band", done: adv("adventure/deep_hell")),
        Goal(id: "adventure/keep_warden", stage: 4, text: "The Keep Castellan", done: adv("adventure/keep_warden")),
        Goal(id: "adventure/break_seal", stage: 4, text: "The Sealrock", done: adv("adventure/break_seal")),
        Goal(id: "adventure/ash_vault", stage: 4, text: "The Ash Vault", done: adv("adventure/ash_vault")),
        Goal(id: "adventure/ash_victory", stage: 4, text: "The Ash Chancellor", done: adv("adventure/ash_victory")),
        // 6. The Capital, the enemy over everything.
        Goal(id: "spine/capital_citadel", stage: 5, text: "A Capital Citadel", done: adv("spine/capital_citadel")),
        Goal(id: "spine/capital_fall", stage: 5, text: "The Capital", done: any(["spine/capital_fall", "adventure/break_citadel"])),
    ]
    // The path for this world (every world walks the same spine now; kept for the callers).
    static func path(_ g: Game) -> [Goal] { all }
    // The stage (0...5) of a goal, nil for an unknown id.
    static func stage(_ id: String) -> Int? { all.first { $0.id == id }?.stage }

    static var on: Bool { HudExtras.enabled && Settings.shared.tutorialHints }
    // The next goal: the step after the furthest one met, so a skipped step (no night in a bed) never holds the goal
    // back once the player is past it (nil in creative or with the path walked).
    static func next(_ g: Game) -> Goal? {
        guard g.survival else { return nil }
        let p = path(g)
        let last = p.lastIndex { met($0, g) } ?? -1
        return last + 1 < p.count ? p[last + 1] : nil
    }

    // A step met by carrying something (wood, the first pickaxe, a furnace, an eye) stays met once seen: a furnace
    // set down or an eye thrown doesn't take the goal back (kept with the saved advancements as "goal/<id>").
    static func met(_ goal: Goal, _ g: Game) -> Bool {
        if Advancements.index[goal.id] != nil { return goal.done(g) }
        if g.advancements.contains("goal/" + goal.id) { return true }
        guard goal.done(g) else { return false }
        g.advancements.insert("goal/" + goal.id)
        return true
    }

    // The banner: a new goal (or the first one after the tips, or after loading a world) shows for 8 s.
    static var shownID: String?
    static var shownAt: Double = -100
    static var lastCheck: Double = -100
    static var current: Goal?
    static weak var shownGame: Game?
    static var bars = 0                    // boss / alarm bars on screen last frame (Renderer)
    static func tick(_ g: Game) {
        if g !== shownGame { shownGame = g; shownID = nil; current = nil; lastCheck = -100 }     // a world loaded: show it again
        Spine.tick(g)                      // (the spine's milestones and keys count with the hints off too)
        guard on, g.clock - lastCheck >= 0.5 else { return }
        lastCheck = g.clock
        let n = next(g)
        if n?.id != shownID {
            if shownID != nil, n != nil { g.sfx(.xp, 0.3) }
            shownID = n?.id; current = n; shownAt = g.clock
            head = n.map { "Next goal - \(Spine.stages[$0.stage]) (\($0.stage + 1) of \(Spine.stages.count))" } ?? "Next goal"
        }
    }
    static var head = "Next goal"      // with the stage, built when the goal changes (not every frame)
    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        guard on, Tutorial.ownSeat(g), let n = current, g.alive, !WeaponWheel.shared.open else { return [] }
        // P300 (b, d): no goal banner over play; the goal waits at the top of the inventory screen (a new one still
        // chimes in Goals.tick).
        let inv = g.menu is InventoryMenu
        guard inv else { return [] }
        // In the inventory: above its panel if there is room, else below it (the panel fills the headset's screen from
        // the top); the banner sits under any boss and alarm bars (Renderer: 19 px a bar from insetY + 12).
        let F = inv ? L.fitted(g.menu!) : L
        let s = F.s
        let head = Goals.head, t = n.text
        let b = Spine.targetGoal == n.id ? Spine.bearing : nil         // where the target is, when it is known
        var y = L.insetY + 34 * s + Float(bars) * 19 * s
        if inv, let m = g.menu {
            let top = floor((F.H - Float(m.height) * s) / 2), bottom = top + Float(m.height) * s
            let room: Float = b == nil ? 30 : 41
            if top - room * s >= F.insetY { y = top - (room - 2) * s }
            else if bottom + room * s <= F.H - F.insetY { y = bottom + 8 * s }
            else { return [] }
        }
        let w = Float(max(Font.width(t), Font.width(head), b.map { Font.width($0) } ?? 0)) * s
        let x = floor((L.W - w) / 2)
        let a: Float = inv ? 1 : Float(min(1, (8 - (g.clock - shownAt)) * 2))
        var out = [HudLine(text: "", x: x - 8 * s, y: y - 4 * s, scale: s, bg: V4(0.08, 0.1, 0.16, 0.8 * a), box: V2(w + 16 * s, (b == nil ? 26 : 37) * s)),
                   HudLine(text: head, x: floor((L.W - Float(Font.width(head)) * s) / 2), y: y, scale: s, color: V4(1, 0.85, 0.35, a)),
                   HudLine(text: t, x: floor((L.W - Float(Font.width(t)) * s) / 2), y: y + 12 * s, scale: s, color: V4(1, 1, 1, a))]
        if let b { out.append(HudLine(text: b, x: floor((L.W - Float(Font.width(b)) * s) / 2), y: y + 23 * s, scale: s, color: V4(0.6, 0.85, 1, a))) }
        return out
    }
}
