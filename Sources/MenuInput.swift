import Foundation

// Controller + keyboard + mouse input for open screens. D-pad and left stick move the cursor between
// slots/buttons (held directions repeat), A/X/Y click, B goes back, LB/RB switch tabs or pages, the right
// stick and triggers scroll long lists, RT drops the held stack.
final class MenuNav {
    static let shared = MenuNav()
    var timer: Double = 0
    var heldDir = (0, 0)
    var scrollTimer: Double = 0
}

extension Game {
    // Directional repeat: first step at once, then after 0.32 s every 0.085 s.
    private func navStep(_ dx: Int, _ dy: Int, _ dt: Double) -> (Int, Int) {
        let n = MenuNav.shared
        if dx == 0 && dy == 0 { n.heldDir = (0, 0); n.timer = 0; return (0, 0) }
        if n.heldDir != (dx, dy) { n.heldDir = (dx, dy); n.timer = 0.32; return (dx, dy) }
        n.timer -= dt
        if n.timer <= 0 { n.timer = 0.085; return (dx, dy) }
        return (0, 0)
    }

    func tickMenu(_ p: PadSnapshot, _ q: PadSnapshot, _ dt: Double) {
        guard let m = menu else { return }
        let L = HudLayout(screen.x, screen.y).fitted(m)
        // Held direction from the D-pad or left stick (pad), one-shot from the arrow keys.
        var hx = 0, hy = 0
        if p.left { hx -= 1 }
        if p.right { hx += 1 }
        if p.up { hy -= 1 }
        if p.down { hy += 1 }
        let ls = stick(p.lx, p.ly, dead: deadZone)
        if hx == 0 && hy == 0 && max(abs(ls.x), abs(ls.y)) > 0.45 {
            if abs(ls.x) > abs(ls.y) { hx = ls.x > 0 ? 1 : -1 } else { hy = ls.y > 0 ? -1 : 1 }
        }
        var (mx, my) = navStep(hx, hy, dt)
        if !m.capturesText || m is KeyboardMenu || m is PauseMenu {
            if input.tapped(Key.arrowLeft) { mx -= 1 }
            if input.tapped(Key.arrowRight) { mx += 1 }
            if input.tapped(Key.arrowUp) { my -= 1 }
            if input.tapped(Key.arrowDown) { my += 1 }
        }
        let creative = m as? CreativeMenu
        var padMoved = false
        // Left / right on a settings row steps the value instead of moving.
        if let pm = m as? PauseMenu, mx != 0, my == 0, pm.adjust(mx) { mx = 0; padMoved = true }
        if mx != 0 || my != 0 {
            let before = menuCursor
            menuCursor = m.neighbour(of: menuCursor, dx: mx == 0 ? 0 : (mx > 0 ? 1 : -1), dy: mx != 0 ? 0 : (my > 0 ? 1 : -1))
            // Scroll the creative palette when pushing past its top/bottom row.
            if let c = creative, menuCursor == before, my != 0, before < c.rows * 9 { c.scrollBy(my) }
            // Long pause/options lists scroll when the cursor pushes past the first/last visible row.
            if let pm = m as? PauseMenu, menuCursor == before, my != 0 { pm.scrollList(my > 0 ? 1 : -1) }
            padMoved = true
            if menuCursor != before { sfx(.click, 0.25) }
        }

        // Right stick / triggers scroll lists; LB / RB switch tabs and pages.
        let rs = stick(p.rx, p.ry)
        var scroll = -input.scrollSteps
        let nav = MenuNav.shared
        if abs(rs.y) > 0.5 {
            nav.scrollTimer -= dt
            if nav.scrollTimer <= 0 { scroll += rs.y > 0 ? -1 : 1; nav.scrollTimer = abs(rs.y) > 0.9 ? 0.06 : 0.14 }
        } else { nav.scrollTimer = 0 }
        let tab = (p.rb && !q.rb ? 1 : 0) - (p.lb && !q.lb ? 1 : 0)
        if let c = creative {
            if scroll != 0 { c.scrollBy(scroll) }
            if tab != 0 { c.scrollBy(tab * c.rows) }
        }
        if let mm = m as? MerchantMenu, scroll != 0 {
            mm.scroll = max(0, min(max(0, mm.offers.count - MerchantMenu.visible), mm.scroll + scroll))
        }
        if let am = m as? AdvancementMenu {
            if scroll != 0 { am.scroll = max(0, min(max(0, am.list.count - AdvancementMenu.rows), am.scroll + scroll)) }
            if tab != 0 { am.tab = (am.tab + tab + Advancements.tabs.count) % Advancements.tabs.count; am.scroll = 0; sfx(.click, 0.4) }
        }
        if let pm = m as? PauseMenu {
            if tab != 0 { pm.switchTab(tab) }
            if scroll != 0 { pm.scrollList(scroll) }
        }
        if let hb = m as? HasRecipeBook, hb.book.open, tab != 0 {
            _ = hb.recipeBookButton(tab > 0 ? 492 : 491, hb.book, grid: hb.craftGrid) { hb.rebuildBook() }
        }

        let mouse = V2(input.mouseX, input.mouseY)
        if input.mouseMoved, let s = m.slotAt(mouse, L), let i = m.slots.firstIndex(where: { $0 === s }) { menuCursor = i }
        menuHover = menuCursor < m.slots.count ? m.slots[menuCursor] : nil
        if padMoved { input.mouseX = -1 }

        let shift = input.shift
        if input.leftClicked || input.rightClicked {
            let b = input.leftClicked ? 0 : 1
            if let s = m.slotAt(mouse, L) { m.click(s, button: b, shift: shift) }
            else if !m.inside(mouse, L) && !carried.isEmpty {
                if b == 0 { dropItem(carried); carried = .empty }
                else { dropItem(carried.with(count: 1)); carried.count -= 1; if carried.count <= 0 { carried = .empty } }
            }
        }

        // On-screen keyboard shortcuts: X delete, Y space, LT shift, Menu done.
        let keyboard = m as? KeyboardMenu
        if let km = keyboard {
            if p.x && !q.x { km.target.typed("\u{8}"); sfx(.click, 0.3) }
            if p.y && !q.y { km.target.typed(" "); sfx(.click, 0.3) }
            if p.lt > 0.5 && q.lt <= 0.5 { km.toggleShift() }
            if p.menu && !q.menu { km.finish(); return }
        }
        if let s = menuHover {
            if p.a && !q.a { m.click(s, button: 0, shift: false) }
            if keyboard == nil && p.x && !q.x { m.click(s, button: 1, shift: false) }
            if keyboard == nil && p.y && !q.y && !m.capturesText { m.click(s, button: 0, shift: true) }
            // Number keys swap the hovered slot with a hotbar slot.
            for (i, k) in Key.digits.enumerated() where input.tapped(k) && !m.capturesText {
                if case .normal = s.kind, s.container != nil {
                    let a = s.stack
                    s.stack = inventory.main[i]
                    inventory.main[i] = a
                    m.changed()
                }
            }
        }
        // RT drops the held stack (or one item from the hovered slot), like dropping outside the panel.
        if p.rt > 0.5 && q.rt <= 0.5 && !(m is PauseMenu) && !(m is KeyboardMenu) {
            if !carried.isEmpty { dropItem(carried); carried = .empty }
            else if let s = menuHover, !s.isButton, !s.stack.isEmpty {
                if case .palette = s.kind {} else if case .result = s.kind {} else {
                    var st = s.stack
                    dropItem(st.with(count: 1))
                    st.count -= 1
                    s.stack = st.count > 0 ? st : .empty
                    m.changed()
                }
            }
        }
        m.tick()
        guard menu === m else { return }
        if !input.typed.isEmpty { m.typed(input.typed) }
        if (p.b && !q.b) && m.backPressed() { m.tick(); return }
        if m.capturesText && p.y && !q.y && !(m is KeyboardMenu) {
            menu = KeyboardMenu(game: self, target: m)
            menuCursor = 0
            return
        }
        if (input.tapped(Key.e) && !m.capturesText) || input.tapped(Key.esc) || (p.b && !q.b) || (p.view && !q.view) { closeMenu() }
    }
}
