import Foundation
import simd

// Extra HUD text for couch play and accessibility: sound subtitles, contextual button prompts and the
// first-steps tutorial. Everything is laid out here as positioned text lines; the renderer only draws them.
// Menus: the hovered control and the open tab, the same in every screen (P72, Oct 12 playtest: the old hover blue and
// the light-grey open tab barely differed from grey on the headset).
enum MenuColors {
    static let hover = V4(0.26, 0.5, 0.98, 1)
    static let selected = V4(0.98, 0.76, 0.24, 1)
}

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
    // `side` is for the player who was live when the sound played; `pos` lets each split-screen half work out its own
    // arrow (and skip sounds far from that player) when it draws.
    struct Entry { var label: String; var side: Int; var time: Double; var pos: V3? = nil }
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
        case .creeperHiss: return "Powderwight fuse sizzles"
        case .mobSpider: return "Something skitters"
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
        case .mobVillager: return "Townsperson mumbles"
        case .mobGolem: return "Golem clanks"
        case .anvil: return "Anvil used"
        case .brew: return "Potion brewing"
        case .enchant: return "Upgrade fitted"
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
        // The audio workstream's captions first (they know every mob voice), then our own table.
        guard AudioSettings.subtitles else { return }
        var caption = s.caption(positional: pos != nil)
        if caption == nil || caption == "Creature calls" { caption = Subtitles.label(s) ?? caption }     // ours names the creature
        guard let label = caption else { return }
        let side = Subtitles.side(g, pos)
        if let p = pos {
            let d = V3(p.x - g.player.eye.x, 0, p.z - g.player.eye.z)
            let len = simd_length(d)
            // The player's own footsteps and blocks aren't worth a caption.
            if len < 1.2 && abs(p.y - g.player.eye.y) < 2.5 && s != .hurt { if case .step = s { return }; if case .breakBlock = s { return }; if case .place = s { return } }
        }
        if let i = entries.firstIndex(where: { $0.label == label }) {
            entries[i].time = g.clock
            entries[i].side = side
            entries[i].pos = pos
        } else {
            entries.append(Entry(label: label, side: side, time: g.clock, pos: pos))
            if entries.count > 7 { entries.removeFirst() }
        }
    }

    // -1 left, 1 right, 0 ahead / behind / not positional, for the live player.
    static func side(_ g: Game, _ pos: V3?) -> Int {
        guard let p = pos else { return 0 }
        let d = V3(p.x - g.player.eye.x, 0, p.z - g.player.eye.z)
        let len = simd_length(d)
        guard len > 0.8 else { return 0 }
        let right = V3(cosf(g.player.yaw), 0, -sinf(g.player.yaw))
        let k = simd_dot(d / len, right)
        return k > 0.35 ? 1 : (k < -0.35 ? -1 : 0)
    }

    func lines(_ g: Game, _ L: HudLayout, bottom: Float) -> [HudLine] {
        entries.removeAll { g.clock - $0.time > 3 || g.clock < $0.time }
        guard AudioSettings.subtitles, !entries.isEmpty else { return [] }
        // Split screen: each half draws with its own player live (arrows from that player; sounds far from them skipped).
        var shown = entries
        if g.coop.active {
            shown = entries.compactMap { e in
                var e = e
                if let p = e.pos {
                    if simd_length(p - g.player.eye) > 40 { return nil }
                    e.side = Subtitles.side(g, p)
                }
                return e
            }
            if shown.isEmpty { return [] }
        }
        let s = L.s
        let w = Float(shown.map { Font.width($0.label) }.max() ?? 0) * s + 24 * s
        let x0 = L.W - L.insetX - w - 4 * s
        var out: [HudLine] = []
        for (i, e) in shown.reversed().enumerated() {
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
        // R2 (Oct 13, sixth report after P53/P85/P108/P143/P160): in the headset no control hint is drawn in play at
        // all, not at a helm or a deck gun either (those returned before the headset check, so the right-hand stack
        // came back whenever he steered or manned a gun). The controls are taught by the tutorial and one-time toasts.
        if g.vrHead != nil { vrLessons(g); return [] }
        // Vehicles and guns have their own layouts (VehicleControls.swift, Guns.swift).
        if let s = g.world.ships.pilot { return VehicleControls.prompts(g, s) }
        if Turrets.shared.active { return Turrets.shared.prompts() }
        var out: [(Prompt.Act, String)] = []
        if g.riding != nil { out.append((.sneak, "Dismount")) }
        let held = g.held
        if let gi = g.heldGun {
            out = g.vrAim != nil ? [(.attack, "Fire"), (.use, "Aim")] : [(.attack, "Fire"), (.use, "Aim"), (.reload, "Reload")]
            if Guns.all[gi].auto { out[0].1 = "Fire (hold)" }
            out.append((.wheel, "Weapons"))
            return out.map { Prompt.g($0.0) + " " + $0.1 }
        }
        if let hit = g.mobs.raycast(g.player.eye, g.player.look, maxDist: 4), Turrets.canMan(hit.0), !(g.survival && hit.0.soldierBrain.crewed) {
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

    // The headset's one-time lessons in place of the prompts: guns (P143), an empty gun's rounds (P158, once per gun
    // kind a session), the helm and deck guns.
    // S6: the headset's lessons replace the flat-screen tips (Tutorial): the basics once the first-launch setup is
    // closed, then one short line the first time each part of the game comes up: a gun in hand, a horse ridden, honour
    // changing (a crime seen, a good deed), a town (shops and money), a notice board's contracts. Each once ever
    // (UserDefaults "vrLessons", a bit per lesson), the button named as the player holds the controllers.
    private static var emptyTold = Set<Int>(), helmTold = false, turretTold = false
    static var vrMirror = false                     // Dominant Hand: Left (set by the Quest controls each frame)
    private static var lessonBits = -1
    private static var boardSeen = false
    private static var honourSeenAt: Double = 0
    enum VRLesson: Int { case basics = 0, horse, honour, town, contracts }
    static func lessonDone(_ l: VRLesson) -> Bool {
        if lessonBits < 0 { lessonBits = UserDefaults.standard.integer(forKey: "vrLessons") }
        return lessonBits & (1 << l.rawValue) != 0
    }
    private static func teach(_ g: Game, _ l: VRLesson, _ text: String) {
        _ = lessonDone(l)                           // (loads the saved bits first)
        lessonBits |= 1 << l.rawValue
        UserDefaults.standard.set(lessonBits, forKey: "vrLessons")
        g.onToast?(vrMirror ? mirrorHands(text) : text)
    }
    // "Right" <-> "Left", "R" <-> "L", A <-> X and B <-> Y as whole words: what a left-handed player presses.
    static func mirrorHands(_ s: String) -> String {
        var out = "", word = ""
        func flush() {
            switch word {
            case "Right": out += "Left"
            case "Left": out += "Right"
            case "right": out += "left"
            case "left": out += "right"
            case "R": out += "L"
            case "L": out += "R"
            case "A": out += "X"
            case "X": out += "A"
            case "B": out += "Y"
            case "Y": out += "B"
            default: out += word
            }
            word = ""
        }
        for c in s { if c.isLetter { word.append(c) } else { flush(); out.append(c) } }
        flush()
        return out
    }
    static func vrLessons(_ g: Game) {
        // The contracts lesson follows a notice board's screen (read once it closes, not under the open panel).
        if g.menu is NoticeBoardMenu || g.menu is BaseContractsMenu { boardSeen = true }
        guard g.menu == nil, !g.paused, g.alive else { return }
        if !lessonDone(.basics) {
            teach(g, .basics, "Left stick walks, right stick turns. A jumps. Right trigger mines, left trigger places and uses. Grips step the hotbar, hold Y for the inventory, Menu pauses")
            return
        }
        if boardSeen && !lessonDone(.contracts) {
            teach(g, .contracts, "Contracts: point at one on the board and pull the trigger to take it. Taken ones wait in your Journal (right hand to the chest pocket, grip). Each pays money and honour")
            return
        }
        if let h = g.riding, h.kind == .horse, !lessonDone(.horse) {
            teach(g, .horse, "Riding: the left stick steers; click it while pushing to spur up a gait. B gets off. Reach behind the saddle and grip for the saddlebags")
            return
        }
        if Honour.changedAt > honourSeenAt && g.clock - Honour.changedAt < 6 && !lessonDone(.honour) {
            honourSeenAt = Honour.changedAt
            teach(g, .honour, "Honour: good deeds raise it; stealing or hurting townsfolk lowers it and calls the sheriff. Low honour raises prices and puts a bounty on you")
            return
        }
        if TownLaw.inTown != nil && !lessonDone(.town) {
            teach(g, .town, "A town: point at a shopkeeper and pull the left trigger to buy and sell. Your money and honour show on the HUD while you're here")
            return
        }
        if let gi = g.heldGun {
            if !Settings.shared.gunLesson {
                Settings.shared.gunLesson = true
                let t = "Guns: right trigger fires, left trigger aims. Hold the left hand on the front grip to steady it. Bring a magazine to the gun to load. Click the right stick: weapon wheel"
                g.onToast?(vrMirror ? mirrorHands(t) : t)
            }
            if g.held.tag <= 0 && Guns.all[gi].mag > 0 && !emptyTold.contains(gi) {
                emptyTold.insert(gi)
                let a = Guns.all[gi].ammo
                let name = Items.has(a) ? Items.def(Items.id(a)).display : a
                let have = Items.has(a) && g.inventory.main.countOf(Items.id(a)) > 0
                g.onToast?("Empty: bring \(name) from your hip to the gun" + (have ? "" : " (none on you: " + Guns.ammoSource(a) + ")"))
            }
        }
        if let s = g.world.ships.pilot, !helmTold {
            helmTold = true
            g.onToast?(VehicleControls.prompts(g, s).joined(separator: ", "))
        }
        if Turrets.shared.active && !turretTold {
            turretTold = true
            g.onToast?(Turrets.shared.prompts().joined(separator: ", "))
        }
    }

    // P53 (Oct 11 evening playtest: "players won't need to know that after they've been playing a while"): the
    // in-game button prompts show for the first three hours of play, then retire (once, with a toast). Button Hints
    // in Options turns them off sooner, or on again for another three hours. Menu legends are unaffected.
    static let retireAfter: Float = 3 * 3600
    static var shown: Bool { HudExtras.enabled && Settings.shared.buttonHints && Settings.shared.hintSeconds < retireAfter }
    private static var pending: Float = 0, lastClock: Double = -1
    static func tick(_ g: Game) {
        let dt = lastClock < 0 ? 0 : Float(max(0, min(1, g.clock - lastClock)))
        lastClock = g.clock
        guard shown, g.menu == nil, !g.paused, g.alive else { return }
        pending += dt
        guard pending >= 30 else { return }                // UserDefaults written twice a minute, not every frame
        let st = Settings.shared
        st.hintSeconds += pending
        pending = 0
        if st.hintSeconds >= retireAfter { g.onToast?("Button prompts are now hidden (Options > Button Hints brings them back)") }
    }

    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        if g.vrHead != nil { if g.alive { vrLessons(g) }; return [] }       // (vrLessons: in play only, and the board's screen)
        guard shown, g.menu == nil, g.alive else { return [] }
        let list = items(g)
        let s = L.s
        var out: [HudLine] = []
        var bottom = L.H - L.insetY - 6 * s
        // P108 (Oct 12 PM, "the UI on my right is still bleeding into the bar where all my items are"): at a bigger HUD
        // scale (the headset panel at scale 3) the right-aligned prompts reached over the hotbar's right end; then the
        // stack sits above the hotbar instead of beside it.
        let widest = list.map { Float(Font.width($0)) * s }.max() ?? 0
        if L.W - L.insetX - widest - 8 * s < L.hotbarX0 + L.slot * 9 + 4 * s { bottom = min(bottom, L.hotbarY0 - 4 * s) }
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
        // S6: no flat-screen tips in the headset (its lessons replace them: ContextPrompts.vrLessons); the tips count
        // as done so the next-goal line (Goals) comes up as it does after them on the Mac.
        if g.vrHead != nil { st.tutorialStep = steps; return }
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
        guard HudExtras.enabled, st.tutorialHints, st.tutorialStep < steps, near, ownSeat(g) else { return }
        if case .breakBlock = s, st.tutorialStep == 3 { advance(g) }
        if case .place = s, st.tutorialStep == 4 { advance(g) }
    }
    // Split screen: the tips (one saved step, Settings.tutorialStep) belong to player 1: shown on their half and moved
    // on by what they do (player 2's block breaks used to tick player 1's tip over, and both halves showed it).
    static func ownSeat(_ g: Game) -> Bool { !g.coop.active || g.coop.current == 0 }
    static func selected(_ g: Game) {
        if HudExtras.enabled && Settings.shared.tutorialHints && Settings.shared.tutorialStep == 6 && ownSeat(g) { advance(g) }
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
        guard ownSeat(g) else { return [] }
        guard HudExtras.enabled, st.tutorialHints, st.tutorialStep < steps, g.menu == nil, g.alive, !WeaponWheel.shared.open, g.vrHead == nil else { return [] }
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
    // The line under the crosshair: a townsperson's glance, else hunting (studying game, skinning, a fish fight).
    static func glanceLines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        if let a = Hunting.actionLines(g, L) { return a }
        let t = TownStatsHUD.lines(g, L)
        return t.isEmpty ? Hunting.lines(g, L) : t
    }
    static var enabled = true       // the snapshot harness turns tips and prompts off unless --hints
    static var loading: String?     // full-screen "Loading..." while a world switch blocks the main thread

    // Per frame from Game.tick (also while a menu is open).
    static func tick(_ g: Game) {
        Tutorial.tick(g)
        Goals.tick(g)
        Feedback.tick(g)
        Narrator.shared.tick(g)
        BugNotes.shared.tick(g)
        MapCache.shared.tick(g)
        g.liberationTick()                                           // O1: outlaw camps freed
        g.repHuntersTick()                                           // O3: hunters for a hunted player
        g.factionRaidsTick()                                         // O5: raids on your places
        g.baseSpecialtyTick()                                        // P242: specialty bases
        g.trophiesTick()                                             // O6: trophy room and museum
        g.weatherWarTick()                                           // O7: weather that matters
        Wrecks.hintTick(g)                                           // P144: wreck and mast hints
        MapFog.shared.tick(g)                     // A5 (MapFog.swift)
        TownLaw.tick(g)
        Hunting.tick(g)
        Countries.tick(g)
        ContextPrompts.tick(g)
    }
    private static var counterN = -1, counterLost = false, counterText = ""
    // All extra lines for this frame (drawn after the normal HUD, before the F3 overlay).
    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        var out = Tutorial.lines(g, L) + Goals.lines(g, L)
        // P98: the Reckoning's counter (top right) while war bands hunt the player.
        if Reckoning.stage == 2 && g.menu == nil && g.dim.dim == .overworld {
            let s = L.s, n = Reckoning.groupsLeft
            if n != counterN || Reckoning.underground != counterLost {          // (built when it changes, not every frame)
                counterN = n; counterLost = Reckoning.underground
                counterText = "\(n) war band\(n == 1 ? "" : "s") hunting you" + (Reckoning.underground ? " (trail lost)" : "")
            }
            let t = counterText
            let w = Float(Font.width(t)) * s, x = L.W - L.insetX - w - 6 * s, y = L.insetY + 4 * s
            out.append(HudLine(text: "", x: x - 4 * s, y: y - 3 * s, scale: s, bg: V4(0, 0, 0, 0.6), box: V2(w + 8 * s, 14 * s)))
            out.append(HudLine(text: t, x: x, y: y, scale: s, color: V4(1, 0.6, 0.2, 1)))
        }
        let bn = BugNotes.shared
        if bn.listening {
            // Bug Notes mic dot: grey = listening, red = recording a note (top-left, inside the safe area).
            let s = L.s, x = L.insetX + 4 * s, y = L.insetY + 4 * s
            let pulse: Float = bn.recording ? 0.75 + 0.25 * sinf(Float(g.clock) * 8) : 1
            out.append(HudLine(text: "", x: x - s, y: y - s, scale: s, bg: V4(0, 0, 0, 0.5), box: V2(8 * s, 8 * s)))
            out.append(HudLine(text: "", x: x, y: y, scale: s, bg: bn.recording ? V4(0.95, 0.15, 0.15, pulse) : V4(0.7, 0.7, 0.72, 0.8), box: V2(6 * s, 6 * s)))
            if bn.recording { out.append(HudLine(text: "Note", x: x + 10 * s, y: y, scale: s, color: V4(1, 0.6, 0.6, 1))) }
        }
        // (Not on the headset: the grips step the hotbar there, and he wanted the labels gone: P85, Oct 12 playtest.)
        if ContextPrompts.shown && Prompt.pad && g.menu == nil && g.vrHead == nil {
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
        if g.menu is InventoryMenu && g.alive { out = Wallet.lines(g, L) + HonourHUD.lines(g, L) + out }
        if g.menu == nil && g.alive { out = Minimap.lines(g, L) + Wallet.lines(g, L) + HonourHUD.lines(g, L) + CombatHUD.shared.lines(g, L) + CompassHUD.lines(g, L) + glanceLines(g, L) + out }
        return out
    }
}
