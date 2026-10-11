import Foundation

// A list screen in the shop's look (dark text on the beige panel, legible at headset distance): a sub-title line, up
// to six rows (icon, name, a detail line, a value on the right) that are buttons, scroll buttons and a status line.
// Subclasses give the rows and act on a press. Used by the town notice board, the bank, the saloon's dice table and
// the stable (TownBoard.swift, TownServices.swift, HorseStable.swift).
class ListMenu: Menu, CustomDrawnMenu {
    struct Row {
        var icon: ItemStack = .empty
        var name: String
        var detail: String = ""
        var value: String = ""
        var enabled = true
        var good = true                     // the value's colour: green (true) or red
    }
    var scroll = 0
    var status = ""
    var statusGood = true
    var subtitle = ""
    var corner = ""                         // top right (the wallet, by default)

    static let visible = 6
    static let rowY = 30, rowH = 22, rowX = 8, rowW = 252
    static let scrollUp = 100, scrollDown = 101
    static var nameWidth: Int { rowW - 24 - 52 }

    override init(_ title: String, game: Game) {
        super.init(title, game: game)
        showInventoryLabel = false
        width = 284; height = 180
        for i in 0..<ListMenu.visible {
            let b = MenuSlot(ListMenu.rowX, ListMenu.rowY + ListMenu.rowH * i, nil, 0, .button(i))
            b.w = ListMenu.rowW; b.h = ListMenu.rowH - 2
            slots.append(b)
        }
        let up = MenuSlot(264, ListMenu.rowY, nil, 0, .button(ListMenu.scrollUp)); up.w = 14; up.h = 40; slots.append(up)
        let dn = MenuSlot(264, ListMenu.rowY + ListMenu.rowH * ListMenu.visible - 42, nil, 0, .button(ListMenu.scrollDown)); dn.w = 14; dn.h = 40
        slots.append(dn)
        corner = "Wallet " + Money.format(game.money)
    }

    // Overridden by each screen.
    var rows: [Row] { [] }
    func pressed(_ index: Int) {}

    func say(_ s: String, good: Bool) { status = s; statusGood = good }

    override func buttonPressed(_ i: Int) {
        switch i {
        case ListMenu.scrollUp: scrollBy(-1)
        case ListMenu.scrollDown: scrollBy(1)
        default:
            let rs = rows
            guard i >= 0 && i < ListMenu.visible, scroll + i < rs.count else { return }
            guard rs[scroll + i].enabled else { game.sfx(.villagerNo, 0.4); return }
            pressed(scroll + i)
            scroll = max(0, min(scroll, rows.count - ListMenu.visible))
        }
    }

    func scrollBy(_ d: Int) {
        let n = max(0, rows.count - ListMenu.visible)
        let s = max(0, min(n, scroll + d))
        if s != scroll { scroll = s; game.sfx(.click, 0.3) }
    }

    func drawLines(_ L: HudLayout, _ o: V2) -> [HudLine] {
        let s = L.s
        var out: [HudLine] = []
        let dark = V4(0.12, 0.1, 0.09, 1), mid = V4(0.25, 0.22, 0.19, 1)
        func at(_ x: Int, _ y: Int) -> (Float, Float) { (o.x + Float(x) * s, o.y + Float(y) * s) }
        func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: V4) {
            let (px, py) = at(x, y)
            out.append(HudLine(text: "", x: px, y: py, scale: s, bg: c, box: V2(Float(w) * s, Float(h) * s)))
        }
        func label(_ t: String, _ x: Int, _ y: Int, _ c: V4) {
            let (px, py) = at(x, y)
            out.append(HudLine(text: t, x: px, y: py, scale: s, color: c))
        }
        func right(_ t: String, _ x: Int, _ y: Int, _ c: V4) { label(t, x - Font.width(t), y, c) }
        if !subtitle.isEmpty { label(ShopMenu.fit(subtitle, width - 24 - Font.width(corner)), 8, 17, mid) }
        if !corner.isEmpty { right(corner, width - 8, 6, V4(0.1, 0.38, 0.12, 1)) }
        let hover = game.menuHover
        let rs = rows
        if rs.isEmpty { label("Nothing here.", 16, ListMenu.rowY + 8, mid) }
        for i in 0..<ListMenu.visible {
            let idx = scroll + i
            guard idx < rs.count else { break }
            let r = rs[idx]
            let x = ListMenu.rowX, y = ListMenu.rowY + ListMenu.rowH * i
            let hot = hover === slots[i]
            box(x, y, ListMenu.rowW, ListMenu.rowH - 2, V4(0.22, 0.2, 0.18, 1))
            box(x + 1, y + 1, ListMenu.rowW - 2, ListMenu.rowH - 4, hot && r.enabled ? V4(0.86, 0.82, 0.72, 1) : V4(0.7, 0.67, 0.6, 1))
            let textX = r.icon.isEmpty ? x + 5 : x + 24
            if !r.icon.isEmpty { let (px, py) = at(x + 3, y + 2); out.append(HudLine(text: "", x: px, y: py, scale: s, item: r.icon)) }
            let valueW = r.value.isEmpty ? 0 : Font.width(r.value) + 8
            label(ShopMenu.fit(r.name, ListMenu.rowW - (textX - x) - valueW - 4), textX, y + 2, r.enabled ? dark : V4(0.32, 0.3, 0.28, 1))
            label(ShopMenu.fit(r.detail, ListMenu.rowW - (textX - x) - valueW - 4), textX, y + 11, mid)
            if !r.value.isEmpty { right(r.value, x + ListMenu.rowW - 5, y + 6, r.good ? V4(0.08, 0.34, 0.1, 1) : V4(0.55, 0.16, 0.12, 1)) }
            if hot && Prompt.pad { box(x - 1, y - 1, ListMenu.rowW + 2, 1, V4(1, 0.85, 0.2, 1)); box(x - 1, y + ListMenu.rowH - 2, ListMenu.rowW + 2, 1, V4(1, 0.85, 0.2, 1)) }
        }
        for (id, t) in [(ListMenu.scrollUp, "^"), (ListMenu.scrollDown, "v")] {
            guard let sl = slots.first(where: { if case .button(let b) = $0.kind { return b == id }; return false }) else { continue }
            let can = id == ListMenu.scrollUp ? scroll > 0 : scroll + ListMenu.visible < rs.count
            box(sl.x, sl.y, sl.w, sl.h, hover === sl ? V4(0.75, 0.72, 0.66, 1) : V4(0.5, 0.48, 0.45, 1))
            label(t, sl.x + (sl.w - Font.width(t)) / 2, sl.y + sl.h / 2 - 3, can ? dark : V4(0.4, 0.38, 0.36, 1))
        }
        if !status.isEmpty { label(ShopMenu.fit(status, width - 16), 8, height - 13, statusGood ? V4(0.1, 0.3, 0.12, 1) : V4(0.55, 0.14, 0.1, 1)) }
        return out
    }

    var legend: String {
        if Prompt.pad { return Prompt.line([(.select, "Choose"), (.scroll, "Scroll"), (.back, "Leave")]) }
        return Glyph.mouseL.s + " Choose   Wheel Scroll   " + Glyphs.key("Esc") + " Leave"
    }

    // Tests: every line and box drawn, at every scroll position, stays inside the panel (the shop UI's check).
    func overflow() -> [String] {
        var bad: [String] = []
        let L = HudLayout(1280, 800).fitted(self)
        let o = origin(L)
        let keep = scroll
        defer { scroll = keep }
        for sc in 0...max(0, rows.count - ListMenu.visible) {
            scroll = sc
            for l in drawLines(L, o) {
                let w = l.box?.x ?? Float(Font.width(l.text)) * l.scale
                let x1 = l.x + w, y1 = l.y + (l.box?.y ?? 8 * l.scale)
                if l.x < o.x - 0.5 || x1 > o.x + Float(width) * L.s + 0.5 || l.y < o.y - 0.5 || y1 > o.y + Float(height) * L.s + 0.5 {
                    bad.append("'\(l.text)'")
                }
            }
        }
        return bad
    }
}
