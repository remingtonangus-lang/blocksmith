import Foundation
import simd

// Extra HUD text for couch play and accessibility: sound subtitles, contextual button prompts and the
// first-steps tutorial. Everything is laid out here as positioned text lines; the renderer only draws them.
struct HudLine {
    var text: String
    var x: Float
    var y: Float
    var scale: Float
    var color: V4 = V4(1, 1, 1, 1)
    var bg: V4? = nil
    var box: V2? = nil       // explicit background size (drawn at x, y); nil = fit the text with a small margin
    var item: ItemStack? = nil   // item icon drawn at x, y in a box-sized square (weapon wheel, map markers)
}

// MARK: Subtitles

final class Subtitles {
    static let shared = Subtitles()
    struct Entry { var label: String; var side: Int; var time: Double }
    private(set) var entries: [Entry] = []

    static func label(_ s: Snd) -> String? {
        switch s {
        case .breakBlock: return "Block broken"
        case .place: return "Block placed"
        case .step: return "Footsteps"
        case .splash: return "Splashing"
        case .eat: return "Eating"
        case .mobCow: return "Cow moos"
        case .mobSheep: return "Sheep baas"
        case .mobChicken: return "Chicken clucks"
        case .mobPig: return "Pig oinks"
        case .mobZombie: return "Zombie groans"
        case .mobSkeleton: return "Skeleton rattles"
        case .creeperHiss: return "Hisser hisses"
        case .mobSpider: return "Spider hisses"
        case .mobVoidwalker: return "Voidwalker warbles"
        case .mobSlime: return "Slime squishes"
        case .bow: return "Arrow fired"
        case .explode: return "Explosion"
        case .arrowHit: return "Arrow hits"
        case .fizz: return "Fizzing"
        case .xp: return "Experience gained"
        case .levelUp: return "Level up"
        case .mobWailer: return "Wailer wails"
        case .mobCinderwisp: return "Cinderwisp breathes"
        case .mobBoarling: return "Boarling snorts"
        case .mobUndeadBoarling: return "Undead Boarling grunts"
        case .fireball: return "Fireball"
        case .mobVillager: return "Villager mumbles"
        case .mobGolem: return "Golem clanks"
        case .anvil: return "Anvil used"
        case .brew: return "Potion brewing"
        case .enchant: return "Enchanting"
        case .drink: return "Drinking"
        case .glassBreak: return "Glass breaks"
        case .mobBlight: return "Blight growls"
        case .witherSpawn: return "Blight roars"
        case .witherShoot: return "Blight shoots"
        case .mobVex: return "Hexling shrieks"
        case .mobRavager: return "Siegebeast roars"
        case .evokerCast: return "Conjurer casts"
        case .bell: return "Bell rings"
        case .raidHorn: return "Raid horn blares"
        case .fangs: return "Fangs snap"
        case .thunder: return "Thunder"
        case .mobWolf: return "Wolf barks"
        case .mobCat: return "Cat meows"
        case .mobHorse: return "Horse neighs"
        case .mobLlama: return "Llama grunts"
        case .mobBee: return "Bee buzzes"
        case .mobWarden: return "Deep Stalker rumbles"
        case .goatHorn: return "Horn sounds"
        case .fireworkLaunch: return "Firework launches"
        case .fireworkBlast, .fireworkBlastLarge: return "Firework blasts"
        case .fireworkTwinkle: return "Firework twinkles"
        case .caveAmbience: return "Eerie noise"
        case .note: return "Note block plays"
        case .hurt: return "Damage taken"
        case .gun(let k): return k == 9 ? "Cannon fires" : (k == 7 || k == 12 ? nil : (k == 10 ? "Alarm sounds" : "Gunshot"))
        default: return nil          // UI clicks, pickups, rain loops...
        }
    }

    func add(_ g: Game, _ s: Snd, at pos: V3?) {
        guard Settings.shared.subtitles, let label = Subtitles.label(s) else { return }
        var side = 0
        if let p = pos {
            let d = V3(p.x - g.player.eye.x, 0, p.z - g.player.eye.z)
            let len = simd_length(d)
            // The player's own footsteps and blocks aren't worth a caption.
            if len < 1.2 && abs(p.y - g.player.eye.y) < 2.5 && s != .hurt { if case .step = s { return }; if case .breakBlock = s { return }; if case .place = s { return } }
            if len > 0.8 {
                let right = V3(cosf(g.player.yaw), 0, -sinf(g.player.yaw))
                let k = simd_dot(d / len, right)
                side = k > 0.35 ? 1 : (k < -0.35 ? -1 : 0)
            }
        }
        if let i = entries.firstIndex(where: { $0.label == label }) {
            entries[i].time = g.clock
            entries[i].side = side
        } else {
            entries.append(Entry(label: label, side: side, time: g.clock))
            if entries.count > 7 { entries.removeFirst() }
        }
    }

    func lines(_ g: Game, _ L: HudLayout, bottom: Float) -> [HudLine] {
        entries.removeAll { g.clock - $0.time > 3 || g.clock < $0.time }
        guard Settings.shared.subtitles, !entries.isEmpty else { return [] }
        let s = L.s
        let w = Float(entries.map { Font.width($0.label) }.max() ?? 0) * s + 24 * s
        let x0 = L.W - L.insetX - w - 4 * s
        var out: [HudLine] = []
        for (i, e) in entries.reversed().enumerated() {
            let age = Float(g.clock - e.time)
            let a = age > 2.2 ? max(0.25, 1 - (age - 2.2) / 0.8) : 1
            let y = bottom - Float(i + 1) * 11 * s
            let tw = Float(Font.width(e.label)) * s
            out.append(HudLine(text: "", x: x0, y: y - 2 * s, scale: s, bg: V4(0, 0, 0, 0.6 * a), box: V2(w, 11 * s)))
            out.append(HudLine(text: e.label, x: x0 + (w - tw) / 2, y: y, scale: s, color: V4(1, 1, 1, a)))
            if e.side < 0 { out.append(HudLine(text: "<", x: x0 + 3 * s, y: y, scale: s, color: V4(1, 1, 0.6, a))) }
            if e.side > 0 { out.append(HudLine(text: ">", x: x0 + w - 7 * s, y: y, scale: s, color: V4(1, 1, 0.6, a))) }
        }
        return out
    }
}

// MARK: Contextual prompts

enum ContextPrompts {
    // What the triggers and face buttons do right now (at most four), e.g. "RT Mine   LT Place".
    static func items(_ g: Game) -> [String] {
        // Vehicles and guns have their own layouts (VehicleControls.swift, Guns.swift).
        if let s = g.world.ships.pilot { return VehicleControls.prompts(g, s) }
        if Turrets.shared.active { return Turrets.shared.prompts() }
        var out: [(Prompt.Act, String)] = []
        if g.riding != nil { out.append((.sneak, "Dismount")) }
        let held = g.held
        if let gi = g.heldGun {
            out = [(.attack, "Fire"), (.use, "Aim"), (.reload, "Reload")]
            if Guns.all[gi].auto { out[0].1 = "Fire (hold)" }
            out.append((.wheel, "Weapons"))
            return out.map { Prompt.g($0.0) + " " + $0.1 }
        }
        if let hit = g.mobs.raycast(g.player.eye, g.player.look, maxDist: 4), Turrets.canMan(hit.0) {
            out.append((.use, "Man the gun"))
        }
        if let st = g.world.ships.target {
            let b = st.ship.grid.get(st.cell.x, st.cell.y, st.cell.z)
            if ShipParts.kinds[Int(b)] == .helm { out.append((.use, "Steer")); out.append((.sneak, "+ Use: Dock")) }
        } else if let t = g.target, ShipParts.kinds[Int(g.world.block(t.hit.x, t.hit.y, t.hit.z))] == .helm {
            out.append((.use, "Launch vehicle"))
        }
        if let t = g.target {
            out.append((.attack, g.survival ? "Mine" : "Break"))
            if g.isInteractive(t.hit) || g.isCircuitInteractive(t.hit) {
                let k = Blocks.key(Blocks.groupBase[Int(g.world.block(t.hit.x, t.hit.y, t.hit.z))])
                out.append((.use, k.contains("chest") || k.contains("barrel") || k.contains("box") ? "Open" : "Use"))
            } else if held.def.block != nil {
                out.append((.use, "Place"))
            } else if !held.isEmpty && held.def.food == nil {
                out.append((.use, "Use"))
            }
            out.append((.pick, "Pick Block"))
        } else if !held.isEmpty {
            if held.def.food != nil && g.survival && g.hunger < 20 { out.append((.use, "Eat")) }
            else if held.def.drink { out.append((.use, "Drink")) }
        }
        if g.player.flying { out.append((.jump, "Up")); out.append((.sneak, "Down")) }
        else if g.player.inWater { out.append((.jump, "Swim Up")) }
        return out.prefix(4).map { Prompt.g($0.0) + " " + $0.1 }
    }

    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        guard HudExtras.enabled, Settings.shared.buttonHints, g.menu == nil, g.alive else { return [] }
        let list = items(g)
        let s = L.s
        var out: [HudLine] = []
        let bottom = L.H - L.insetY - 6 * s
        for (i, t) in list.reversed().enumerated() {
            let w = Float(Font.width(t)) * s
            out.append(HudLine(text: t, x: L.W - L.insetX - w - 8 * s, y: bottom - Float(i + 1) * 12 * s, scale: s,
                               color: V4(1, 1, 1, 0.95), bg: V4(0, 0, 0, 0.3 + Settings.shared.textBackground * 0.5)))
        }
        return out
    }
}

// MARK: Tutorial

// First-steps tips: one at a time at the top of the screen until the player has done it.
enum Tutorial {
    static var lookAccum: Float = 0
    static var moveAccum: Float = 0
    static var lastYaw: Float = 0
    static var lastPitch: Float = 0
    static var lastPos = V3(0, 0, 0)
    static var shownAt: Double = -1
    static var doneFlash: Double = -10

    static let steps = 7
    static func text(_ step: Int) -> String {
        switch step {
        case 0: return "Look around with " + (Prompt.pad ? Glyph.rs.s : "the mouse")
        case 1: return "Move with " + Prompt.g(.move)
        case 2: return "Jump with " + Prompt.g(.jump)
        case 3: return "Hold " + Prompt.g(.attack) + " to break a block"
        case 4: return "Place a block with " + Prompt.g(.use)
        case 5: return "Open your inventory with " + Prompt.g(.inventory)
        case 6: return "Switch items with " + Prompt.g(.hotbar)
        default: return ""
        }
    }

    // Per frame (from Game.tick): advances when the current step's action is seen.
    static func tick(_ g: Game) {
        let st = Settings.shared
        guard HudExtras.enabled, st.tutorialHints, st.tutorialStep < steps else { return }
        let p = g.player
        let dLook = abs(p.yaw - lastYaw) + abs(p.pitch - lastPitch)
        if dLook < 1 { lookAccum += dLook }
        lastYaw = p.yaw; lastPitch = p.pitch
        let dMove = simd_length(V2(p.pos.x - lastPos.x, p.pos.z - lastPos.z))
        if dMove < 2 { moveAccum += dMove }
        lastPos = p.pos
        var done = false
        switch st.tutorialStep {
        case 0: done = lookAccum > 2.5
        case 1: done = moveAccum > 6
        case 2: done = !p.onGround && p.vel.y > 2 && !p.flying
        case 5: done = g.menu is InventoryMenu || g.menu is CreativeMenu
        default: break
        }
        if done { advance(g) }
    }

    // Sound hook: breaking / placing / switching items near the player completes those steps.
    static func sound(_ g: Game, _ s: Snd, near: Bool) {
        let st = Settings.shared
        guard HudExtras.enabled, st.tutorialHints, st.tutorialStep < steps, near else { return }
        if case .breakBlock = s, st.tutorialStep == 3 { advance(g) }
        if case .place = s, st.tutorialStep == 4 { advance(g) }
    }
    static func selected(_ g: Game) {
        if HudExtras.enabled && Settings.shared.tutorialHints && Settings.shared.tutorialStep == 6 { advance(g) }
    }

    static func advance(_ g: Game) {
        Settings.shared.tutorialStep += 1
        lookAccum = 0; moveAccum = 0
        doneFlash = g.clock
        g.sfx(.xp, 0.4)
        if Settings.shared.tutorialStep >= steps { g.onToast?("Tips done! Pause for options and the controls list.") }
    }

    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        let st = Settings.shared
        guard HudExtras.enabled, st.tutorialHints, st.tutorialStep < steps, g.menu == nil, g.alive else { return [] }
        let s = L.s
        let t = text(st.tutorialStep)
        let head = "Tip \(st.tutorialStep + 1)/\(steps)"
        let y = L.insetY + 34 * s
        let w = Float(max(Font.width(t), Font.width(head))) * s
        let x = floor((L.W - w) / 2)
        let flash = Float(max(0, 1 - (g.clock - doneFlash) * 2))
        return [HudLine(text: "", x: x - 8 * s, y: y - 4 * s, scale: s, bg: V4(0.08 + 0.3 * flash, 0.1 + 0.4 * flash, 0.16, 0.8), box: V2(w + 16 * s, 26 * s)),
                HudLine(text: head, x: floor((L.W - Float(Font.width(head)) * s) / 2), y: y, scale: s, color: V4(1, 0.85, 0.35, 1)),
                HudLine(text: t, x: floor((L.W - Float(Font.width(t)) * s) / 2), y: y + 12 * s, scale: s)]
    }
}

enum HudExtras {
    static var enabled = true       // the snapshot harness turns tips and prompts off unless --hints
    static var loading: String?     // full-screen "Loading..." while a world switch blocks the main thread

    // Per frame from Game.tick (also while a menu is open).
    static func tick(_ g: Game) {
        Tutorial.tick(g)
        Feedback.tick(g)
        Narrator.shared.tick(g)
        BugNotes.shared.tick(g)
    }
    // All extra lines for this frame (drawn after the normal HUD, before the F3 overlay).
    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        var out = Tutorial.lines(g, L)
        let bn = BugNotes.shared
        if bn.listening {
            // Bug Notes mic dot: grey = listening, red = recording a note (top-left, inside the safe area).
            let s = L.s, x = L.insetX + 4 * s, y = L.insetY + 4 * s
            let pulse: Float = bn.recording ? 0.75 + 0.25 * sinf(Float(g.clock) * 8) : 1
            out.append(HudLine(text: "", x: x - s, y: y - s, scale: s, bg: V4(0, 0, 0, 0.5), box: V2(8 * s, 8 * s)))
            out.append(HudLine(text: "", x: x, y: y, scale: s, bg: bn.recording ? V4(0.95, 0.15, 0.15, pulse) : V4(0.7, 0.7, 0.72, 0.8), box: V2(6 * s, 6 * s)))
            if bn.recording { out.append(HudLine(text: "Note", x: x + 10 * s, y: y, scale: s, color: V4(1, 0.6, 0.6, 1))) }
        }
        if enabled && Settings.shared.buttonHints && Prompt.pad && g.menu == nil {
            // LB / RB beside the hotbar.
            let s = L.s, y = L.hotbarY0 + L.slot / 2 - 4 * s
            let lb = PadMap.glyph(.lb), rb = PadMap.glyph(.rb)
            out.append(HudLine(text: lb.s, x: L.hotbarX0 - Float(Glyphs.advance(Int(lb.rawValue))) * s - 4 * s, y: y, scale: s))
            out.append(HudLine(text: rb.s, x: L.hotbarX0 + L.slot * 9 + 5 * s, y: y, scale: s))
        }
        let prompts = ContextPrompts.lines(g, L)
        out += prompts
        let top = prompts.map { $0.y }.min() ?? (L.H - L.insetY - 6 * L.s)
        out += Subtitles.shared.lines(g, L, bottom: top - 4 * L.s)
        if g.menu == nil && g.alive { out = CombatHUD.shared.lines(g, L) + out }
        return out
    }
}
