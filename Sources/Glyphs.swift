import Foundation

// Controller button glyphs and keyboard key caps inside HUD text. Each glyph is one private-use
// Unicode scalar (so it can never collide with typed text); Font.advance knows their widths and the
// renderer's text() draws them as pixel-art badges in the same style as the 5x7 font.
enum Glyph: UInt32 {
    case a = 0xE000, b, x, y, lb, rb, lt, rt, ls, rs, l3, r3, menu, view, share
    case dpad, dup, ddown, dleft, dright, dpadH, dpadV
    case mouseL, mouseR, mouseM
    var s: String { String(Character(Unicode.Scalar(rawValue)!)) }
}

enum Glyphs {
    static let first = 0xE000, last = 0xE0FF
    static let capOpen = 0xE0F0, capClose = 0xE0F1
    static func isGlyph(_ code: Int) -> Bool { code >= first && code <= last }
    // A keyboard key cap around a label, e.g. key("Esc").
    static func key(_ label: String) -> String { "\u{E0F0}\(label)\u{E0F1}" }

    // Platform labels for the shoulder buttons and triggers (the Quest names its Touch grips and triggers); nil = the pad's.
    static var labelOverride: ((Glyph) -> String?)?

    static func pillLabel(_ g: Glyph) -> String? {
        if let o = labelOverride, let l = o(g) { return l }
        let st = PadManager.shared.style
        switch g {
        case .lb: return st == .playstation ? "L1" : (st == .nintendo ? "L" : "LB")
        case .rb: return st == .playstation ? "R1" : (st == .nintendo ? "R" : "RB")
        case .lt: return st == .playstation ? "L2" : (st == .nintendo ? "ZL" : "LT")
        case .rt: return st == .playstation ? "R2" : (st == .nintendo ? "ZR" : "RT")
        default: return nil
        }
    }

    // Advance in font pixels (drawn width + 1 spacing), matching Font.advance for normal glyphs.
    static func advance(_ code: Int) -> Int {
        // A pixel more inside the cap on each side (labels touched the cap edges: blind UI critic, keycaps).
        if code == capOpen { return 3 }
        if code == capClose { return 4 }       // inner padding + two pixels after the cap (one left "Shift" touching the mouse glyph)
        guard let g = Glyph(rawValue: UInt32(code)) else { return 6 }
        if let l = pillLabel(g) { return Font.width(l) + 5 }
        switch g {
        case .mouseL, .mouseR, .mouseM: return 8
        default: return 10
        }
    }

    typealias Rect = (Float, Float, Float, Float, V4) -> Void
    typealias Text = (String, Float, Float, Float, V4, Bool) -> Void

    static func tone(_ g: Glyph) -> (V4, V4) {        // (badge, label)
        let dark = V4(0.16, 0.16, 0.18, 1), white = V4(1, 1, 1, 1)
        switch PadManager.shared.style {
        case .playstation:
            // Dark buttons with coloured symbols (drawn as shapes in draw()).
            switch g {
            case .a: return (dark, V4(0.5, 0.65, 1, 1))
            case .b: return (dark, V4(1, 0.4, 0.4, 1))
            case .x: return (dark, V4(0.95, 0.55, 0.85, 1))
            case .y: return (dark, V4(0.35, 0.85, 0.7, 1))
            default: break
            }
        case .nintendo:
            if g == .a || g == .b || g == .x || g == .y { return (dark, white) }
        case .xbox: break
        }
        switch g {
        case .a: return (V4(0.24, 0.68, 0.26, 1), white)
        case .b: return (V4(0.82, 0.2, 0.2, 1), white)
        case .x: return (V4(0.2, 0.45, 0.92, 1), white)
        case .y: return (V4(0.95, 0.78, 0.15, 1), dark)
        case .l3, .r3: return (V4(0.88, 0.88, 0.9, 1), dark)
        default: return (dark, white)
        }
    }

    // Draws glyph `code` with its left edge at x and the font's top row at y (badges are 9 font px tall,
    // one pixel above and below the text line).
    static func draw(_ code: Int, _ x: Float, _ y: Float, _ u: Float, _ alpha: Float, rect: Rect, text: Text) {
        guard let g = Glyph(rawValue: UInt32(code)) else { return }
        let y0 = y - u
        var (bg, fg) = tone(g)
        bg.w *= alpha; fg.w *= alpha
        let shadow = V4(0, 0, 0, 0.45 * alpha)
        func disc(_ ox: Float, _ oy: Float, _ c: V4) {
            rect(ox + 2 * u, oy, 5 * u, u, c)
            rect(ox + u, oy + u, 7 * u, u, c)
            rect(ox, oy + 2 * u, 9 * u, 5 * u, c)
            rect(ox + u, oy + 7 * u, 7 * u, u, c)
            rect(ox + 2 * u, oy + 8 * u, 5 * u, u, c)
        }
        // Dark badges get a light rim instead of a drop shadow so they read on the dark world too.
        let dark = bg.x < 0.3 && bg.y < 0.3
        let rim = V4(0.86, 0.86, 0.9, 0.9 * alpha)
        func bigDisc(_ ox: Float, _ oy: Float, _ c: V4) {
            rect(ox + 3 * u, oy, 5 * u, u, c)
            rect(ox + u, oy + u, 9 * u, 2 * u, c)
            rect(ox, oy + 3 * u, 11 * u, 5 * u, c)
            rect(ox + u, oy + 8 * u, 9 * u, 2 * u, c)
            rect(ox + 3 * u, oy + 10 * u, 5 * u, u, c)
        }
        func back() { if dark { bigDisc(x - u, y0 - u, rim) } else { disc(x + u, y0 + u, shadow) } }
        func letter(_ l: String, _ ox: Float) { text(l, ox, y, u, fg, false) }
        if let label = pillLabel(g) {
            let w = Float(Font.width(label) + 4) * u
            let trigger = g == .lt || g == .rt
            if dark {
                rect(x, y0 - u, w, 11 * u, rim)
                rect(x - u, y0 + (trigger ? u : 0), w + 2 * u, (trigger ? 9 : 9) * u, rim)
            }
            for (ox, oy, c) in (dark ? [(Float(0), Float(0), bg)] : [(u, u, shadow), (Float(0), Float(0), bg)]) {
                if trigger {
                    rect(x + ox + 2 * u, y0 + oy, w - 4 * u, u, c)
                    rect(x + ox + u, y0 + oy + u, w - 2 * u, u, c)
                    rect(x + ox, y0 + oy + 2 * u, w, 7 * u, c)
                } else {
                    rect(x + ox + u, y0 + oy, w - 2 * u, u, c)
                    rect(x + ox, y0 + oy + u, w, 7 * u, c)
                    rect(x + ox + u, y0 + oy + 8 * u, w - 2 * u, u, c)
                }
            }
            letter(label, x + 2 * u)
            return
        }
        switch g {
        case .a, .b, .x, .y:
            back(); disc(x, y0, bg)
            switch PadManager.shared.style {
            case .playstation:
                // Cross, circle, square, triangle.
                func px(_ cx: Int, _ cy: Int) { rect(x + Float(cx) * u, y0 + Float(cy) * u, u, u, fg) }
                switch g {
                case .a: for i in 0..<5 { px(2 + i, 2 + i); px(6 - i, 2 + i) }
                case .b: for i in 3...5 { px(i, 2); px(i, 6); px(2, i); px(6, i) }
                case .x: for i in 2...6 { px(i, 2); px(i, 6); px(2, i); px(6, i) }
                default: px(4, 2); px(3, 3); px(5, 3); px(3, 4); px(5, 4); for i in 2...6 { px(i, 5) }
                }
            case .nintendo:
                // Same positions, Nintendo letters: bottom B, right A, left Y, top X.
                letter(g == .a ? "B" : g == .b ? "A" : g == .x ? "Y" : "X", x + 2 * u)
            case .xbox:
                letter(g == .a ? "A" : g == .b ? "B" : g == .x ? "X" : "Y", x + 2 * u)
            }
        case .ls, .rs, .l3, .r3:
            back(); disc(x, y0, bg)
            let ring = V4(0.55, 0.55, 0.6, alpha)
            rect(x + 2 * u, y0 + u, 5 * u, u * 0.5, ring)
            letter(g == .ls || g == .l3 ? "L" : "R", x + 2 * u)
            if g == .l3 || g == .r3 { rect(x + 3 * u, y0 + 8 * u, 3 * u, u, fg) }
        case .menu:
            back(); disc(x, y0, bg)
            for r in [2, 4, 6] { rect(x + 2 * u, y0 + Float(r) * u, 5 * u, u, fg) }
        case .view:
            back(); disc(x, y0, bg)
            rect(x + 2 * u, y0 + 2 * u, 4 * u, 3 * u, V4(0.7, 0.7, 0.72, alpha))
            rect(x + 3 * u, y0 + 4 * u, 4 * u, 3 * u, fg)
        case .share:
            back(); disc(x, y0, bg)
            rect(x + 3 * u, y0 + 3 * u, 3 * u, 3 * u, fg)
        case .dpad, .dup, .ddown, .dleft, .dright, .dpadH, .dpadV:
            // Grey cross with the used arm(s) white and a dark hub, readable on light panels and the dark world alike.
            let base = V4(0.42, 0.42, 0.46, alpha), hi = V4(1, 1, 1, alpha)
            let all = g == .dpad
            func arm(_ ax: Float, _ ay: Float, _ w: Float, _ h: Float, _ lit: Bool) { rect(x + ax * u, y0 + ay * u, w * u, h * u, lit ? hi : base) }
            rect(x + 3 * u + u, y0 + u, 3 * u, 9 * u, shadow)
            rect(x + u, y0 + 3 * u + u, 9 * u, 3 * u, shadow)
            arm(3, 0, 3, 3, all || g == .dup || g == .dpadV)
            arm(3, 6, 3, 3, all || g == .ddown || g == .dpadV)
            arm(0, 3, 3, 3, all || g == .dleft || g == .dpadH)
            arm(6, 3, 3, 3, all || g == .dright || g == .dpadH)
            rect(x + 3 * u, y0 + 3 * u, 3 * u, 3 * u, V4(0.16, 0.16, 0.18, alpha))
        case .mouseL, .mouseR, .mouseM:
            let body = V4(0.88, 0.88, 0.9, alpha), line = V4(0.3, 0.3, 0.33, alpha), hi = V4(1, 0.62, 0.12, alpha)
            rect(x + u + u, y0 + u, 5 * u, 9 * u, shadow)
            rect(x + u, y0, 5 * u, 9 * u, body)
            rect(x, y0 + u, 7 * u, 7 * u, body)
            if g == .mouseL { rect(x + u, y0 + u, 2 * u, 3 * u, hi) }
            if g == .mouseR { rect(x + 4 * u, y0 + u, 2 * u, 3 * u, hi) }
            rect(x + 3 * u, y0, u, 4 * u, g == .mouseM ? hi : line)
            rect(x, y0 + 4 * u, 7 * u, u * 0.5, line)
        default: break
        }
    }

    // Key cap behind a label that is `w` screen px wide in total (from capOpen to capClose).
    static func cap(_ x: Float, _ y: Float, _ w: Float, _ u: Float, _ alpha: Float, rect: Rect) {
        // A row of face above the label: its top row sat on the dark edge, so "Tab" read as "Iab" (creative shot, run 362).
        let y0 = y - 2 * u
        let edge = V4(0.12, 0.12, 0.14, alpha), face = V4(0.9, 0.9, 0.92, alpha), low = V4(0.62, 0.62, 0.66, alpha)
        rect(x + u, y0, w - 2 * u, 10 * u, edge)
        rect(x, y0 + u, w, 8 * u, edge)
        rect(x + u, y0 + u, w - 2 * u, 8 * u, face)
        rect(x + u, y0 + 8 * u, w - 2 * u, u, low)
    }
    static let capInk = V4(0.1, 0.1, 0.12, 1)
}

// What to show for an action: the controller glyph when the player is on a pad, else the key or mouse button.
enum Prompt {
    enum Act {
        case jump, sneak, sprint, attack, use, pick, drop, inventory, hotbar, fly, camera, pause, offhand, chat, screenshot
        case select, back, alt, quick, tabs, scroll, keyboard, delete, space, shift, done, move
        case reload, wheel, map
    }

    static var pad: Bool {
        switch Settings.shared.glyphStyle {
        case 1: return true
        case 2: return false
        default: return PadManager.shared.usingPad
        }
    }

    static func g(_ a: Act) -> String { g(a, pad: pad) }
    static func g(_ a: Act, pad usePad: Bool) -> String {
        if usePad {
            func m(_ g: Glyph) -> String { PadMap.glyph(g).s }   // follows Options > Controller > Button Mapping
            switch a {
            case .jump, .select: return m(.a)
            case .sneak, .back: return m(.b)
            case .sprint: return m(.l3)
            case .attack: return m(.rt)
            case .use: return m(.lt)
            case .pick, .alt, .delete: return m(.x)
            case .drop: return m(.ddown)
            case .inventory, .quick, .keyboard, .space: return m(.y)
            case .hotbar, .tabs: return m(.lb) + m(.rb)
            case .fly: return m(.dup)
            case .camera: return m(.view)
            case .pause, .done: return m(.menu)
            case .offhand: return m(.dright)
            case .chat: return m(.dleft)
            case .screenshot: return m(.share)
            case .scroll: return m(.rs)
            case .shift: return m(.lt)
            case .move: return m(.ls)
            case .reload: return m(.x)
            case .wheel: return m(.rb) + "(hold)"
            case .map: return m(.view) + "(hold)"
            }
        }
        switch a {
        case .jump: return Glyphs.key(KeyBinds.name(KeyBinds.key(.jump)))
        case .space: return Glyphs.key("Space")
        case .sneak, .shift: return Glyphs.key("Shift")
        case .sprint: return Glyphs.key("Ctrl")
        case .attack, .select: return Glyph.mouseL.s
        case .use, .alt: return Glyph.mouseR.s
        case .pick: return Glyph.mouseM.s
        case .drop: return Glyphs.key(KeyBinds.name(KeyBinds.key(.drop)))
        case .inventory: return Glyphs.key(KeyBinds.name(KeyBinds.key(.inventory)))
        case .hotbar: return Glyphs.key("1-9")
        case .fly: return Glyphs.key(KeyBinds.name(KeyBinds.key(.fly)))
        case .camera: return Glyphs.key(KeyBinds.name(KeyBinds.key(.camera)))
        case .pause, .back: return Glyphs.key("Esc")
        case .offhand: return Glyphs.key(KeyBinds.name(KeyBinds.key(.offhand)))
        case .chat: return Glyphs.key(KeyBinds.name(KeyBinds.key(.chat)))
        case .screenshot: return Glyphs.key("F2")
        case .quick: return Glyphs.key("Shift") + Glyph.mouseL.s
        case .tabs: return Glyphs.key("Tab")
        case .scroll: return Glyph.mouseM.s
        case .keyboard: return ""
        case .delete: return Glyphs.key("Del")
        case .done: return Glyphs.key("Enter")
        case .move: return Glyphs.key([KeyBinds.Action.forward, .left, .back, .right].map { KeyBinds.name(KeyBinds.key($0)) }.joined())
        case .reload: return Glyphs.key(KeyBinds.name(KeyBinds.key(.reload)))
        case .wheel: return Glyphs.key(KeyBinds.name(KeyBinds.key(.weapons))) + "(hold)"
        case .map: return Glyphs.key(KeyBinds.name(KeyBinds.key(.map)))
        }
    }

    // The keyboard/mouse glyph for an action whatever device is in use.
    static func keyGlyph(_ a: Act) -> String { g(a, pad: false) }

    // "glyph label   glyph label ..." for a legend line.
    static func line(_ items: [(Act, String)]) -> String {
        items.compactMap { item -> String? in
            let gl = g(item.0)
            return gl.isEmpty ? nil : gl + " " + item.1
        }.joined(separator: "   ")
    }

    // The control legend drawn under an open screen; changes with what the cursor is over.
    static func menuLegend(_ m: Menu, _ game: Game) -> String {
        if m is KeyboardMenu {
            return pad ? line([(.select, "Type"), (.delete, "Delete"), (.space, "Space"), (.shift, "Shift"), (.done, "Done"), (.back, "Back")])
                       : line([(.done, "Done"), (.back, "Back")])
        }
        if m is DeathMenu { return line([(.select, "Select")]) }
        if let pm = m as? PauseMenu { return pm.legend }
        if let cm = m as? CustomDrawnMenu { return cm.legend }
        if m.capturesText && !(m is CreativeMenu) {
            return pad ? line([(.keyboard, "Keyboard"), (.select, "Select"), (.back, "Close")]) : line([(.select, "Select"), (.back, "Close")])
        }
        let hover = game.menuHover
        if let h = hover, h.isButton, !(m is CreativeMenu) { return line([(.select, "Select"), (.back, "Close")]) }
        if m is CreativeMenu {
            var items: [(Act, String)] = []
            if let h = hover, case .palette = h.kind {
                items = game.carried.isEmpty ? [(.select, "Take stack"), (.alt, "Take one"), (.quick, "To inventory")] : [(.select, "Drop held")]
            } else if hover != nil {
                items = game.carried.isEmpty ? [(.select, "Pick up"), (.quick, "Clear slot")] : [(.select, "Place"), (.alt, "Place one")]
            }
            if let c = m as? CreativeMenu, c.tab == .search, pad { items.insert((.keyboard, "Type"), at: 0) }
            items.append((.tabs, "Next tab"))          // "[Tab] Tab" said nothing (blind UI critic, creative)
            items.append((.scroll, "Scroll"))
            items.append((.back, "Close"))
            return line(items)
        }
        var items: [(Act, String)] = []
        let carried = game.carried
        if let h = hover {
            let s = h.stack
            if case .result = h.kind {
                if !s.isEmpty { items = [(.select, "Craft"), (.quick, "Craft all")] }
            } else if carried.isEmpty {
                if !s.isEmpty { items = [(.select, "Pick up"), (.alt, "Pick up half"), (.quick, "Quick move")] }
            } else if s.isEmpty || s.stacks(with: carried) {
                items = [(.select, "Place all"), (.alt, "Place one")]
            } else {
                items = [(.select, "Swap")]
            }
        }
        if pad, let h = hover, !h.isButton, h.container != nil, case .normal = h.kind,
           m.slots.contains(where: { !$0.isPlayerInv && $0.container != nil && !$0.isButton }) && !(m is InventoryMenu) {
            items.append((.use, h.isPlayerInv ? "Store all" : "Take all"))
        }
        items.append((.back, "Close"))
        return line(items)
    }
}
