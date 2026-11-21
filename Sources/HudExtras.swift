import Foundation
import simd

// Extra HUD text for couch play and accessibility: sound subtitles, contextual button prompts and the
// first-steps tutorial. Everything is laid out here as positioned text lines; the renderer only draws them.
// Menus: the hovered control and the open tab, the same in every screen (P72, Oct 12 playtest: the old hover blue and
// the light-grey open tab barely differed from grey on the headset).
enum MenuColors {
    static let hover = V4(0.26, 0.5, 0.98, 1)
    static let selected = V4(0.98, 0.76, 0.24, 1)
    // P481 (Oct 28, store look-alike review: docs/store/lookalike-review.md): Sunderfall's own container screens. The
    // panel was the reference game's exact light grey with a white and dark-grey bevel and a black rim, its slots the
    // same inset squares; now a warm canvas panel with a dark leather rim, a brass line and rounded corners, and dark
    // recessed slots with a soft shadow along the top. (Light enough that the menus' dark text still reads on it.)
    static let panel = V4(0.84, 0.79, 0.69, 1)
    static let rim = V4(0.2, 0.13, 0.08, 1)
    static let brass = V4(0.7, 0.53, 0.27, 1)
    static let title = V4(0.27, 0.18, 0.1, 1)
    static let slotRim = V4(0.33, 0.25, 0.18, 1)
    static let slot = V4(0.55, 0.48, 0.4, 1)
    static let slotShade = V4(0.43, 0.36, 0.29, 1)
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

// T05 (Nov 20 playtest: HUD hard to read on bright snow): shared dark translucent backing and crisp dark outline
// for HUD panels, text blocks, minimap, compass, and the hotbar frame. BS_OLDHUDCONTRAST=1 restores the old look.
enum HudContrast {
    static let old = Env.all["BS_OLDHUDCONTRAST"] == "1"

    static var baseAlpha: Float { min(0.92, max(0.76, 0.55 + Settings.shared.textBackground * 0.4)) }
    static func panelBg(_ alpha: Float = 1) -> V4 { V4(0.03, 0.04, 0.06, baseAlpha * max(0, min(1, alpha))) }
    static func borderColor(_ alpha: Float = 1) -> V4 { V4(0, 0, 0, min(0.96, 0.92 * max(0, min(1, alpha)))) }
    static func isDark(_ c: V4) -> Bool { max(c.x, c.y, c.z) <= 0.24 && c.w >= 0.35 }

    static func boostedAlpha(_ a: Float) -> Float {
        let target = baseAlpha
        if a >= target { return a }
        if a >= 0.38 { return target }
        return min(target, a * (target / 0.38))
    }

    // 4-edge non-overlapping outline outside (x, y, w, h).
    static func outline(_ x: Float, _ y: Float, _ w: Float, _ h: Float, scale s: Float,
                        thickness: Float? = nil, alpha: Float = 1) -> [HudLine] {
        guard w > 0, h > 0, alpha > 0.02 else { return [] }
        let b = thickness ?? max(1, s)
        let c = borderColor(alpha)
        return [
            HudLine(text: "", x: x - b, y: y - b, scale: s, bg: c, box: V2(w + 2 * b, b)),
            HudLine(text: "", x: x - b, y: y + h, scale: s, bg: c, box: V2(w + 2 * b, b)),
            HudLine(text: "", x: x - b, y: y, scale: s, bg: c, box: V2(b, h)),
            HudLine(text: "", x: x + w, y: y, scale: s, bg: c, box: V2(b, h)),
        ]
    }

    // Dark translucent backing panel with a strong dark outline.
    static func frame(_ x: Float, _ y: Float, _ w: Float, _ h: Float, scale s: Float,
                      alpha: Float = 1, border: Float? = nil) -> [HudLine] {
        guard w > 0, h > 0, alpha > 0.02 else { return [] }
        return [HudLine(text: "", x: x, y: y, scale: s, bg: panelBg(alpha), box: V2(w, h))]
            + outline(x, y, w, h, scale: s, thickness: border, alpha: alpha)
    }

    // Outer frame around the hotbar (drawn strictly outside the slots and selection border so icons stay crisp).
    static func hotbarFrame(_ L: HudLayout) -> [HudLine] {
        guard !old else { return [] }
        let s = L.s
        return outline(L.hotbarX0 - 1.5 * s, L.hotbarY0 - 1.5 * s, L.slot * 9 + 3 * s, L.slot + 3 * s,
                       scale: s, thickness: max(1.5, 1.5 * s), alpha: 1)
    }

    private struct Rect {
        var x0: Float, y0: Float, x1: Float, y1: Float
        var dark: Bool
        var alpha: Float
        var w: Float { x1 - x0 }
        var h: Float { y1 - y0 }
        func contains(_ x: Float, _ y: Float) -> Bool { x >= x0 && x <= x1 && y >= y0 && y <= y1 }
    }

    private static func bounds(_ l: HudLine) -> (Float, Float, Float, Float)? {
        if let box = l.box, box.x > 0, box.y > 0 { return (l.x, l.y, l.x + box.x, l.y + box.y) }
        if !l.text.isEmpty {
            let w = Float(Font.width(l.text)) * l.scale
            if w > 0 { return (l.x, l.y, l.x + w, l.y + 8 * l.scale) }
        }
        return nil
    }

    private static func cluster(_ items: [Rect], padX: Float, padY: Float) -> [Rect] {
        var groups = items
        var merged = true
        while merged {
            merged = false
            var i = 0
            while i < groups.count {
                var j = i + 1
                while j < groups.count {
                    let a = groups[i], b = groups[j]
                    if a.x0 - padX <= b.x1 && b.x0 - padX <= a.x1 && a.y0 - padY <= b.y1 && b.y0 - padY <= a.y1 {
                        groups[i] = Rect(x0: min(a.x0, b.x0), y0: min(a.y0, b.y0),
                                         x1: max(a.x1, b.x1), y1: max(a.y1, b.y1),
                                         dark: a.dark || b.dark, alpha: max(a.alpha, b.alpha))
                        groups.remove(at: j)
                        merged = true
                    } else {
                        j += 1
                    }
                }
                i += 1
            }
        }
        return groups
    }

    // Strengthen faint dark backings, outline panels, pill light text over bright surfaces, and frame bare text blocks.
    static func enhance(_ lines: [HudLine], _ L: HudLayout, frameWhole: Bool = false, strongBorder: Bool = false) -> [HudLine] {
        guard !old, !lines.isEmpty else { return lines }
        let s = L.s
        let border = strongBorder ? max(1.5, 1.5 * s) : max(1, s)
        let needsCoverCheck = lines.contains { !$0.text.isEmpty && $0.bg == nil }
        var drawn: [Rect] = []
        var panels: [Rect] = []
        var bareText: [Rect] = []
        var auxBoxes: [Rect] = []
        var minX = Float.greatestFiniteMagnitude, minY = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        var maxAlpha: Float = 0
        var out: [HudLine] = []
        out.reserveCapacity(lines.count + 16)

        for var l in lines {
            if let (x0, y0, x1, y1) = bounds(l) {
                minX = min(minX, x0); minY = min(minY, y0)
                maxX = max(maxX, x1); maxY = max(maxY, y1)
            }
            if l.text.isEmpty && l.item == nil, let bg = l.bg, let box = l.box, box.x > 0, box.y > 0 {
                let r = Rect(x0: l.x, y0: l.y, x1: l.x + box.x, y1: l.y + box.y, dark: isDark(bg), alpha: bg.w)
                maxAlpha = max(maxAlpha, bg.w)
                if max(bg.x, bg.y, bg.z) <= 0.22 && bg.w >= 0.2 && bg.w < 0.96 && box.x >= 12 * l.scale && box.y >= 8 * l.scale {
                    let na = boostedAlpha(bg.w)
                    l.bg = V4(bg.x, bg.y, bg.z, na)
                    let nested = panels.contains { p in
                        p.x0 <= r.x0 && p.y0 <= r.y0 && p.x1 >= r.x1 && p.y1 >= r.y1 && (p.w - r.w) <= 8 * l.scale && (p.h - r.h) <= 8 * l.scale
                    }
                    out.append(l)
                    if !nested { out += outline(l.x, l.y, box.x, box.y, scale: l.scale, thickness: border, alpha: min(1, na / 0.5)) }
                    let pr = Rect(x0: r.x0, y0: r.y0, x1: r.x1, y1: r.y1, dark: true, alpha: na)
                    panels.append(pr)
                    if needsCoverCheck { drawn.append(pr) }
                } else {
                    out.append(l)
                    if max(bg.x, bg.y, bg.z) <= 0.16 && bg.w >= 0.96 && box.x >= 24 * l.scale && box.y >= 24 * l.scale {
                        panels.append(r)
                    }
                    if needsCoverCheck { drawn.append(r) }
                    if box.x <= L.W * 0.5 && box.y <= 24 * l.scale { auxBoxes.append(r) }
                }
                continue
            }
            if l.item != nil, let box = l.box, box.x > 0, box.y > 0 {
                out.append(l)
                let r = Rect(x0: l.x, y0: l.y, x1: l.x + box.x, y1: l.y + box.y, dark: false, alpha: 1)
                if box.x <= 24 * l.scale && box.y <= 24 * l.scale { auxBoxes.append(r) }
                continue
            }
            if !l.text.isEmpty {
                maxAlpha = max(maxAlpha, l.color.w)
                if let bg = l.bg {
                    if max(bg.x, bg.y, bg.z) <= 0.22 && bg.w >= 0.2 && bg.w < 0.96 {
                        l.bg = V4(bg.x, bg.y, bg.z, boostedAlpha(bg.w))
                    }
                    out.append(l)
                    if needsCoverCheck, let (x0, y0, x1, y1) = bounds(l) {
                        drawn.append(Rect(x0: x0, y0: y0, x1: x1, y1: y1, dark: isDark(l.bg!), alpha: l.bg!.w))
                    }
                    continue
                }
                let textLum = 0.299 * l.color.x + 0.587 * l.color.y + 0.114 * l.color.z
                if textLum >= 0.32, let (x0, y0, x1, y1) = bounds(l) {
                    let cx = (x0 + x1) * 0.5, cy = (y0 + y1) * 0.5
                    if let top = drawn.last(where: { $0.contains(cx, cy) }) {
                        if !top.dark { l.bg = panelBg(l.color.w) }
                    } else {
                        bareText.append(Rect(x0: x0, y0: y0, x1: x1, y1: y1, dark: false, alpha: l.color.w))
                    }
                }
                out.append(l)
                continue
            }
            out.append(l)
        }

        if frameWhole && minX < maxX && minY < maxY {
            let tw = maxX - minX, th = maxY - minY
            if tw <= L.W * 0.75 && th <= L.H * 0.55 {
                let covered = panels.contains { p in
                    p.x0 <= minX + 4 * s && p.y0 <= minY + 4 * s && p.x1 >= maxX - 4 * s && p.y1 >= maxY - 4 * s
                }
                if !covered {
                    let pad = 3 * s
                    let a = maxAlpha > 0 ? min(1, maxAlpha) : 1
                    return frame(minX - pad, minY - pad, tw + 2 * pad, th + 2 * pad, scale: s, alpha: a, border: border) + out
                }
            }
        }

        if !bareText.isEmpty {
            var groups = cluster(bareText, padX: 14 * s, padY: 8 * s)
            for i in groups.indices {
                var g = groups[i]
                for a in auxBoxes {
                    if a.x0 - 8 * s <= g.x1 && g.x0 - 8 * s <= a.x1 && a.y0 - 6 * s <= g.y1 && g.y0 - 6 * s <= a.y1 {
                        g.x0 = min(g.x0, a.x0); g.y0 = min(g.y0, a.y0)
                        g.x1 = max(g.x1, a.x1); g.y1 = max(g.y1, a.y1)
                    }
                }
                groups[i] = g
            }
            var backs: [HudLine] = []
            for g in groups where g.w <= L.W * 0.85 && g.h <= L.H * 0.5 {
                backs += frame(g.x0 - 3 * s, g.y0 - 2 * s, g.w + 6 * s, g.h + 4 * s, scale: s, alpha: g.alpha, border: border)
            }
            if !backs.isEmpty { return backs + out }
        }
        return out
    }
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
        let nShown = shown.count
        for (i, e) in shown.reversed().enumerated() {
            let age = Float(g.clock - e.time)
            let a = age > 2.2 ? max(0.25, 1 - (age - 2.2) / 0.8) : 1
            let y = bottom - Float(i + 1) * 11 * s
            let tw = Float(Font.width(e.label)) * s
            if HudContrast.old {
                out.append(HudLine(text: "", x: x0, y: y - 2 * s, scale: s, bg: V4(0, 0, 0, 0.6 * a), box: V2(w, 11 * s)))
            } else {
                let b = max(1, s), bc = HudContrast.borderColor(a)
                out.append(HudLine(text: "", x: x0, y: y - 2 * s, scale: s, bg: HudContrast.panelBg(a), box: V2(w, 11 * s)))
                out.append(HudLine(text: "", x: x0 - b, y: y - 2 * s, scale: s, bg: bc, box: V2(b, 11 * s)))
                out.append(HudLine(text: "", x: x0 + w, y: y - 2 * s, scale: s, bg: bc, box: V2(b, 11 * s)))
                if i == 0 { out.append(HudLine(text: "", x: x0 - b, y: y + 9 * s, scale: s, bg: bc, box: V2(w + 2 * b, b))) }
                if i == nShown - 1 { out.append(HudLine(text: "", x: x0 - b, y: y - 2 * s - b, scale: s, bg: bc, box: V2(w + 2 * b, b))) }
            }
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
            let bg = HudContrast.old ? V4(0, 0, 0, 0.3 + Settings.shared.textBackground * 0.5) : HudContrast.panelBg()
            out.append(HudLine(text: t, x: L.W - L.insetX - w - 8 * s, y: bottom - Float(i + 1) * 12 * s, scale: s,
                               color: V4(1, 1, 1, 0.95), bg: bg))
        }
        return out
    }
}

// MARK: The clock in hand

// Ledger 259 (Nov 17 20:07:26, a clock in his hand: "it doesn't show me time or anything. Again, there's no interface
// support. It's useless."): a clock showed the time only as a needle on its hotbar icon on the Mac, and on the headset
// nothing at all. Held, it reads out the day and the time, over the hotbar, in both HUDs (HudExtras.lines); away from
// the sun (the Emberdeep, the Hollow) its hands spin. BS_OLDCLOCK=1: nothing.
enum ClockFace {
    static let old = Env.all["BS_OLDCLOCK"] == "1"
    static var cache: (Int, String) = (-1, "")
    static func text(_ g: Game) -> String? {
        guard !old, g.menu == nil, g.alive, Items.key(g.held.item) == "clock" else { return nil }
        guard g.dim.dim == .overworld else { return "The hands spin" }
        let (d, h, m) = g.journalStamp
        let key = (d * 24 + h) * 60 + m
        if key != cache.0 {
            let h12 = h % 12 == 0 ? 12 : h % 12
            cache = (key, "Day \(d)  \(h12):\(m < 10 ? "0" : "")\(m) \(h < 12 ? "AM" : "PM")")
        }
        return cache.1
    }
    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        guard let t = text(g) ?? HeldReadout.text(g) else { return [] }      // (ledger 334: every reading in hand)
        let s = L.s, w = Float(Font.width(t)) * s
        let x = (L.W - w) / 2, y = L.hotbarY0 - 30 * s
        let bg = HudContrast.old
            ? [HudLine(text: "", x: x - 4 * s, y: y - 3 * s, scale: s, bg: V4(0, 0, 0, 0.5), box: V2(w + 8 * s, 14 * s))]
            : HudContrast.frame(x - 4 * s, y - 3 * s, w + 8 * s, 14 * s, scale: s)
        return bg + [HudLine(text: t, x: x, y: y, scale: s, color: V4(1, 0.93, 0.7, 1))]
    }
}

// MARK: Readings in hand

// Ledger 334 (Nov 17 20:07:26, the clock: "Again, there's no interface support"; Fable's audit of every item whose point
// is information when held, in the headset view). Before, held:
//   compass, recovery compass  a needle on the hotbar icon (a few pixels on the headset's panel), no reading
//   clock                      the time over the hotbar (ledger 259)
//   filled map                 drawn over the hotbar, his place and its mark on it (both HUDs)
//   explorer and treasure maps nothing until used (then a filled map)
//   Hunter's Map               nothing until read (ledger 258: then a toast, the journal and the bar)
//   spyglass                   the zoomed view while raised, no reading of how far
//   goat horn                  its call only in the inventory's tooltip (the headset has none)
//   radar set                  a toast when used
//   Greywall Dispatch, Naval Orders, Chancellor's Ledger, Intercepted Orders: nothing until read (then a toast and the pages)
//   (tickets, contract and bounty papers are not items: contracts and bounties are the board's, on the bar and the map)
// Now each reads out over the hotbar, in both HUDs, the line the clock has: where its needle points and how far, where
// a map leads, the den a Hunter's Map has marked, the range to what the spyglass looks at, the horn's call, the radar's
// nearest contact, what the papers name. Never a hint: only the reading. BS_OLDREADOUTS=1: the clock alone.
enum HeldReadout {
    static let old = Env.all["BS_OLDREADOUTS"] == "1"
    // (the readings that search for places are kept a second, and while he stays within 8 blocks)
    static var cache: (key: String, cell: IVec3, t: Double, text: String?) = ("", IVec3(0, 0, 0), -9, nil)

    static func way(_ g: Game, _ x: Float, _ z: Float) -> String {
        let dx = x - g.player.pos.x, dz = z - g.player.pos.z
        let d = Int((dx * dx + dz * dz).squareRoot().rounded())
        if d < 3 { return "here" }
        return "\(fmt.string(from: NSNumber(value: d)) ?? "\(d)") blocks \(TownBoard.direction(dx, dz))"
    }
    static let fmt: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; return f }()

    static func text(_ g: Game) -> String? {
        guard !old, g.menu == nil, g.alive, !g.held.isEmpty else { return nil }
        let st = g.held, k = Items.key(st.item)
        // (each reading made a few times a second, not each frame; the searches once a second, or when he moves on)
        let every: Double, quickOne: Bool
        switch k {
        case "spyglass": every = 0.1; quickOne = true
        case "compass", "recovery_compass", "goat_horn", "hunters_map": every = 0.25; quickOne = true
        case "greywall_dispatch", "naval_orders", "chancellor_ledger", "intercepted_orders", "radar_set": every = 1; quickOne = false
        default:
            guard ExplorerMaps.kinds.contains(where: { $0.item == k }) else { return nil }
            every = 1; quickOne = false
        }
        let p = g.player.pos
        let cell = quickOne ? IVec3(st.tag, g.dim.dim == .overworld ? 0 : 1, 0)
                            : IVec3(Int(floor(p.x / 8)), g.dim.dim == .overworld ? 0 : 1, Int(floor(p.z / 8)))
        let age = g.clock - cache.t
        if cache.key == k && cache.cell == cell && age >= 0 && age < every { return cache.text }
        cache = (k, cell, g.clock, quickOne ? quick(g, st, k) : searched(g, k))
        return cache.text
    }

    // The readings that need no search (each frame).
    static func quick(_ g: Game, _ st: ItemStack, _ k: String) -> String? {
        switch k {
        case "compass":
            if g.dim.dim == .deep {
                if DeepGen.inHell(g.player.pos.y), let kp = g.nearestKeep() {
                    return "Brimstone Keep: " + way(g, Float(kp.anchor.x) + 0.5, Float(kp.anchor.z) + 0.5)
                }
                return "Ashguard citadel: " + way(g, 0.5, 0.5)
            }
            guard g.dim.dim == .overworld else { return "The needle spins" }
            let t = g.compassTarget(st)
            return "Spawn: " + way(g, t.x, t.z)
        case "recovery_compass":
            guard let d = g.lastDeath else { return "The needle rests: no fall to point to" }
            return "Where you fell: " + way(g, d.x, d.z)
        case "spyglass":
            let eye = g.player.eye, dir = g.player.look
            var t: Float = 1
            while t < 512 {
                let q = eye + dir * t
                if g.world.solidAt(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z))) { return "Range: \(Int(t.rounded())) blocks" }
                t += t < 64 ? 0.5 : 1
            }
            return "Range: past 512 blocks"
        case "goat_horn":
            return "Call: " + GoatHorns.names[max(0, min(7, st.tag))]
        default:                                                          // hunters_map
            let dens = Hunting.dens(g)
            let live = Hunting.state.revealed.filter { $0 < dens.count && !Hunting.state.killed.contains($0) }
            guard g.dim.dim == .overworld,
                  let i = live.min(by: { simd_length(V2(Float(dens[$0].x), Float(dens[$0].z)) - V2(g.player.pos.x, g.player.pos.z))
                                         < simd_length(V2(Float(dens[$1].x), Float(dens[$1].z)) - V2(g.player.pos.x, g.player.pos.z)) }) else {
                return "No den marked"
            }
            return "\(Hunting.legends[i].name.capitalizedFirst)'s den: " + way(g, Float(dens[i].x) + 0.5, Float(dens[i].z) + 0.5)
        }
    }

    // The readings that look for a place (once a second at most).
    static func searched(_ g: Game, _ k: String) -> String? {
        guard g.dim.dim == .overworld else { return "Its marks are of the surface" }
        switch k {
        case "greywall_dispatch":
            guard let t = Spine.dispatchTarget(g) else { return "Names no Greywall base within reach" }
            return "The \(t.name): " + way(g, Float(t.x), Float(t.z))
        case "naval_orders":
            guard let w = g.nearestWarship() else { return "The fleet is at sea, beyond this coast" }
            return "The \(w.name): " + way(g, Float(w.x), Float(w.z))
        case "chancellor_ledger":
            guard let t = Spine.capitalTarget(g) else { return "Names no citadel within reach" }
            return "A Capital citadel: " + way(g, Float(t.x), Float(t.z))
        case "intercepted_orders":
            return "Coded, seal unbroken"                                  // (what they name is chosen as they are read)
        case "radar_set":
            let p = V2(g.player.pos.x, g.player.pos.z)
            guard let c = g.radarContacts().min(by: { simd_length(V2(Float($0.x), Float($0.z)) - p) < simd_length(V2(Float($1.x), Float($1.z)) - p) }) else {
                return "No contacts"
            }
            return "\(c.name): " + way(g, Float(c.x), Float(c.z))
        default:
            guard let e = ExplorerMaps.kinds.first(where: { $0.item == k }), let sc = g.world.gen.structures,
                  let s = sc.nearest(e.structure, x: Int(floor(g.player.pos.x)), z: Int(floor(g.player.pos.z)), maxRegions: e.structure == "buried_treasure" ? 40 : 10) else {
                return "Shows nothing nearby"
            }
            let name = ["buried_treasure": "Buried treasure", "military_base": "Capital Citadel"][e.structure]
                ?? e.name.replacingOccurrences(of: " Explorer Map", with: "")
            return "\(name): " + way(g, Float(s.min.x + s.max.x) / 2, Float(s.min.z + s.max.z) / 2)
        }
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
        // (store review: each part timed, questcheck --framesoak: one of these took 77 ms of a frame flying new taiga)
        TickProf.mark("input")
        g.toastQueueTick()                                           // Q2c-console-12
        Goals.tick(g)
        Feedback.tick(g)
        Narrator.shared.tick(g)
        BugNotes.shared.tick(g)
        TickProf.mark("hud: goals, notes")
        MapCache.shared.tick(g)
        TickProf.mark("hud: map cache")
        g.liberationTick()                                           // O1: outlaw camps freed
        g.repHuntersTick()                                           // O3: hunters for a hunted player
        g.factionRaidsTick()                                         // O5: raids on your places
        TickProf.mark("hud: liberation, hunters, raids")
        Director.frame(g)                                            // P266: the Director's post-game events
        TickProf.mark("hud: director")                               // (Nov 18: the stage's 12.3 ms, split)
        g.baseSpecialtyTick()                                        // P242: specialty bases
        TickProf.mark("hud: specialty bases")
        g.trophiesTick()                                             // O6: trophy room and museum
        g.weatherWarTick()                                           // O7: weather that matters
        Wrecks.hintTick(g)                                           // P144: wreck and mast hints
        TickProf.mark("hud: trophies, weather war, wrecks")
        MapFog.shared.tick(g)                     // A5 (MapFog.swift)
        TickProf.mark("hud: map fog")
        TownLaw.tick(g)
        TickProf.mark("hud: town law")
        Hunting.tick(g)
        TickProf.mark("hud: hunting")                    // (store review: his savanna arrival's 7.5 ms, split)
        Countries.tick(g)
        TickProf.mark("hud: countries")
        ContextPrompts.tick(g)
        TickProf.mark("hud: hunting, countries, prompts")
    }
    private static var counterN = -1, counterLost = false, counterText = ""
    // All extra lines for this frame (drawn after the normal HUD, before the F3 overlay).
    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        var out = HudContrast.enhance(Goals.lines(g, L), L)
        // P98: the Reckoning's counter (top right) while war bands hunt the player.
        if Reckoning.stage == 2 && g.menu == nil && g.dim.dim == .overworld {
            let s = L.s, n = Reckoning.groupsLeft
            if n != counterN || Reckoning.underground != counterLost {          // (built when it changes, not every frame)
                counterN = n; counterLost = Reckoning.underground
                counterText = "\(n) war band\(n == 1 ? "" : "s") hunting you" + (Reckoning.underground ? " (trail lost)" : "")
            }
            let t = counterText
            let w = Float(Font.width(t)) * s, x = L.W - L.insetX - w - 6 * s, y = L.insetY + 4 * s
            if HudContrast.old {
                out.append(HudLine(text: "", x: x - 4 * s, y: y - 3 * s, scale: s, bg: V4(0, 0, 0, 0.6), box: V2(w + 8 * s, 14 * s)))
            } else {
                out += HudContrast.frame(x - 4 * s, y - 3 * s, w + 8 * s, 14 * s, scale: s)
            }
            out.append(HudLine(text: t, x: x, y: y, scale: s, color: V4(1, 0.6, 0.2, 1)))
        }
        let bn = BugNotes.shared
        if bn.listening {
            // Bug Notes mic dot: grey = listening, red = recording a note (top-left, inside the safe area).
            let s = L.s, x = L.insetX + 4 * s, y = L.insetY + 4 * s
            let pulse: Float = bn.recording ? 0.75 + 0.25 * sinf(Float(g.clock) * 8) : 1
            if HudContrast.old {
                out.append(HudLine(text: "", x: x - s, y: y - s, scale: s, bg: V4(0, 0, 0, 0.5), box: V2(8 * s, 8 * s)))
            } else {
                let bw = bn.recording ? 13 * s + Float(Font.width("Note")) * s : 8 * s
                out += HudContrast.frame(x - s, y - s, bw, 9 * s, scale: s)
            }
            out.append(HudLine(text: "", x: x, y: y, scale: s, bg: bn.recording ? V4(0.95, 0.15, 0.15, pulse) : V4(0.7, 0.7, 0.72, 0.8), box: V2(6 * s, 6 * s)))
            if bn.recording { out.append(HudLine(text: "Note", x: x + 10 * s, y: y, scale: s, color: V4(1, 0.6, 0.6, 1))) }
        }
        out += SaveBadge.lines(g, L, below: bn.listening)                 // Q2c-console-2
        out += ClockFace.lines(g, L)                                        // ledger 259
        out += NowPlaying.lines(g, L)                                       // Q2c-console-14
        // (Not on the headset: the grips step the hotbar there, and he wanted the labels gone: P85, Oct 12 playtest.)
        if ContextPrompts.shown && Prompt.pad && g.menu == nil && g.vrHead == nil && !g.drivingHUD {
            // LB / RB beside the hotbar.
            let s = L.s, y = L.hotbarY0 + L.slot / 2 - 4 * s
            let lb = PadMap.glyph(.lb), rb = PadMap.glyph(.rb)
            let pill: V4? = HudContrast.old ? nil : HudContrast.panelBg()
            out.append(HudLine(text: lb.s, x: L.hotbarX0 - Float(Glyphs.advance(Int(lb.rawValue))) * s - 4 * s, y: y, scale: s, bg: pill))
            out.append(HudLine(text: rb.s, x: L.hotbarX0 + L.slot * 9 + 5 * s, y: y, scale: s, bg: pill))
        }
        let prompts = ContextPrompts.lines(g, L)
        out += prompts
        let top = prompts.map { $0.y }.min() ?? (L.H - L.insetY - 6 * L.s)
        out += Subtitles.shared.lines(g, L, bottom: top - 4 * L.s)
        if g.menu is InventoryMenu && g.alive {
            out = HudContrast.enhance(Wallet.lines(g, L), L) + HudContrast.enhance(HonourHUD.lines(g, L), L) + out
        }
        if g.menu == nil && g.alive {
            let hotbar = g.drivingHUD ? [] : HudContrast.hotbarFrame(L)
            out = hotbar
                + HudContrast.enhance(Minimap.lines(g, L), L, frameWhole: true, strongBorder: true)
                + HudContrast.enhance(Wallet.lines(g, L), L)
                + HudContrast.enhance(HonourHUD.lines(g, L), L)
                + CombatHUD.shared.lines(g, L)
                + HudContrast.enhance(CompassHUD.lines(g, L), L, frameWhole: true)
                + HudContrast.enhance(glanceLines(g, L), L)
                + out
        }
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
        let bw = Float(Font.width(t)) * s + 13 * s
        let back = HudContrast.old
            ? [HudLine(text: "", x: x - s, y: y - s, scale: s, bg: V4(0, 0, 0, 0.45 * a), box: V2(bw, 9 * s))]
            : HudContrast.frame(x - s, y - s, bw, 9 * s, scale: s, alpha: a)
        return back + [
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
        let s = L.s, x = L.insetX + 4 * s, y = L.H - L.insetY - 10 * s
        if HudContrast.old {
            return [HudLine(text: title, x: x, y: y, scale: s, color: V4(0.9, 0.92, 1, a))]
        }
        return HudContrast.frame(x - 3 * s, y - 2 * s, Float(Font.width(title)) * s + 6 * s, 11 * s, scale: s, alpha: a)
            + [HudLine(text: title, x: x, y: y, scale: s, color: V4(0.94, 0.96, 1, min(1, a * 1.25)))]
    }
}
