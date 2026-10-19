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
        // came back whenever he steered or manned a gun). P300: no lesson toasts either; the world teaches.
        if g.vrHead != nil { return [] }
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
                let k = Blocks.key(Blocks.groupBase[Int(g.world.materialAt(t.hit.x, t.hit.y, t.hit.z))])
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

    // P300 (b): the headset's one-time lessons (the basics, crafting, hunger, night, guns, mounts, towns...) and the
    // helm, deck gun and empty-gun how-to toasts are gone: players learn from the world (NO TEXT, P328).
    static var vrMirror = false                     // Dominant Hand: Left (set by the Quest controls each frame)
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

    // P53 (Oct 11 evening playtest: "players won't need to know that after they've been playing a while"): the
    // in-game button prompts showed for the first three hours of play. P328 (NO TEXT): none over play at all now, as on
    // the headset; the controls reference in the pause menu tells the buttons, and Button Hints keeps the menu legends.
    // `items` stays: what each layout offers (the pad checks).
    static let retireAfter: Float = 3 * 3600
    static var shown: Bool { false }
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
    }

    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        if g.vrHead != nil { return [] }
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

// P300 (b): the first-steps tips ("Look around with...", "Tip 1/7") are gone: the world and the controls reference in
// the pause menu teach the basics (NO TEXT, P328). What is left: whose half of a split screen the goal banner uses.
enum Tutorial {
    // Split screen: the goal banner belongs to player 1 (shown on their half).
    static func ownSeat(_ g: Game) -> Bool { !g.coop.active || g.coop.current == 0 }
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
        g.toastQueueTick()                                           // Q2c-console-12
        Goals.tick(g)
        Feedback.tick(g)
        Narrator.shared.tick(g)
        BugNotes.shared.tick(g)
        MapCache.shared.tick(g)
        g.liberationTick()                                           // O1: outlaw camps freed
        g.repHuntersTick()                                           // O3: hunters for a hunted player
        g.factionRaidsTick()                                         // O5: raids on your places
        Director.frame(g)                                            // P266: the Director's post-game events
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
        var out = Goals.lines(g, L)
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
        out += SaveBadge.lines(g, L, below: bn.listening)                 // Q2c-console-2
        out += NowPlaying.lines(g, L)                                       // Q2c-console-14
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

// Q2c-console-2 (store readiness, save safety): every save shows a small "Saved" badge with a disc icon in the HUD's
// top-left corner (inside the safe area, so on the headset's HUD panel too) for two seconds, fading, never flashing;
// a save problem reported by SaveIO (S2) turns it red, "Save failed", until a later save. The pause menu says how long
// ago the world was saved (PauseMenu: savedAgo).
// Q2c-console-51: free storage where the world is saved, measured off the frame thread when a world starts and every
// five minutes; under 300 MB he is told once (until it is freed), under 60 MB every two minutes with a red badge.
enum StorageCheck {
    private static let lock = NSLock()
    private static var measured: Int = -1                  // MB free at the last measure (-1: unknown)
    private static var askedAt: Double = -1000, warnedLow = false, warnedFullAt: Double = -1000
    private static var dir = ""
    static var freeMB: Int { lock.lock(); defer { lock.unlock() }; return measured }
    static var low: Bool { let f = freeMB; return f >= 0 && f < 300 }
    static var critical: Bool { let f = freeMB; return f >= 0 && f < 60 }
    static func tick(_ g: Game) {
        guard let path = g.save?.dir.path else { return }
        if path != dir || g.clock - askedAt > 300 || g.clock < askedAt {
            dir = path; askedAt = g.clock
            DispatchQueue.global(qos: .utility).async {
                let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path)
                let free = (attrs?[.systemFreeSize] as? NSNumber)?.int64Value
                lock.lock(); measured = free.map { Int($0 / 1_048_576) } ?? -1; lock.unlock()
            }
        }
        let f = freeMB
        guard f >= 0 else { return }
        if f >= 300 { warnedLow = false; return }
        if f < 60 {
            if g.clock - warnedFullAt > 120 || g.clock < warnedFullAt {
                warnedFullAt = g.clock
                SaveBadge.storageFullAt = g.clock
                g.onToast?("Storage full: your world may stop saving. Free some space")
            }
        } else if !warnedLow {
            warnedLow = true
            g.onToast?("Storage almost full (\(f) MB left): free some space so your world keeps saving")
        }
    }
}

enum SaveBadge {
    static var savedAt: Double = -100
    static var failedAt: Double = -100
    static var storageFullAt: Double = -100        // Q2c-console-51: shown as a red "Storage full" for 30 s
    static var failing: Bool { failedAt >= savedAt }

    static func savedAgo(_ g: Game) -> String? {
        guard savedAt > -100 else { return nil }
        let d = max(0, g.clock - savedAt)
        if d < 5 { return "saved just now" }
        if d < 60 { return "saved \(Int(d)) s ago" }
        return "saved \(Int(d / 60)) min ago"
    }

    static func lines(_ g: Game, _ L: HudLayout, below: Bool) -> [HudLine] {
        guard g.menu == nil, HudExtras.enabled else { return [] }
        let age = Float(g.clock - savedAt)
        let full = g.clock - storageFullAt < 30 && g.clock >= storageFullAt && StorageCheck.critical
        let bad = (failing && g.clock - failedAt < 30) || full
        guard bad || (age >= 0 && age < 2.2) else { return [] }
        let a: Float = bad ? 1 : min(1, (2.2 - age) / 0.7)
        let s = L.s, x = L.insetX + 4 * s, y = L.insetY + 4 * s + (below ? 12 * s : 0)
        let t = full && !(failing && g.clock - failedAt < 30) ? "Storage full" : (bad ? "Save failed" : "Saved")
        let body = bad ? V4(0.75, 0.16, 0.14, a) : V4(0.22, 0.36, 0.62, a)
        return [
            HudLine(text: "", x: x - s, y: y - s, scale: s, bg: V4(0, 0, 0, 0.45 * a), box: V2(Float(Font.width(t)) * s + 13 * s, 9 * s)),
            HudLine(text: "", x: x, y: y, scale: s, bg: body, box: V2(7 * s, 7 * s)),                         // the disc
            HudLine(text: "", x: x + 2 * s, y: y, scale: s, bg: V4(0.9, 0.92, 0.95, a), box: V2(3 * s, 2 * s)),  // its shutter
            HudLine(text: "", x: x + 1.5 * s, y: y + 4 * s, scale: s, bg: V4(0.95, 0.95, 0.9, a), box: V2(4 * s, 3 * s)),   // its label
            HudLine(text: t, x: x + 10 * s, y: y, scale: s, color: bad ? V4(1, 0.6, 0.55, a) : V4(0.92, 0.95, 1, a)),
        ]
    }
}

// Q2c-console-14: a new piece of music's title, a small faint line in the bottom-left corner for four seconds (it was a
// toast: it took the message line, could hide a real message and filled the journal). Options > Audio > Show Song
// Titles turns it off.
enum NowPlaying {
    static var title = ""
    static var at: Double = -100
    static func show(_ t: String, clock: Double) {
        guard !t.isEmpty else { return }
        title = "Now playing: " + t           // (the pixel font has no note sign)
        at = clock
    }
    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        let age = Float(g.clock - at)
        guard Settings.shared.songTitles, g.menu == nil, HudExtras.enabled, age >= 0, age < 4 else { return [] }
        let a = min(1, (4 - age) / 1, age / 0.4) * 0.75
        let s = L.s
        return [HudLine(text: title, x: L.insetX + 4 * s, y: L.H - L.insetY - 10 * s, scale: s, color: V4(0.9, 0.92, 1, a))]
    }
}
