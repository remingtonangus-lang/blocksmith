import Foundation

// Controller + keyboard + mouse input for open screens. D-pad and left stick move the cursor between
// slots/buttons (held directions repeat), A/X/Y click, B goes back, LB/RB switch tabs or pages, the right
// stick and triggers scroll long lists, RT drops the held stack.
final class MenuNav {
    static var shared = MenuNav()      // var: split-screen seats swap it (Coop.swift)
    var timer: Double = 0
    var heldDir = (0, 0)
    var scrollTimer: Double = 0
    weak var autoOpened: Menu?
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
        // Button Mapping capture: the pad belongs to the capture until a button is chosen.
        if let pm = m as? PauseMenu, pm.padBinding != nil { pm.tick(); return }
        // A sign opened by a pad player goes straight to the on-screen keyboard (it is all text).
        if m is SignMenu && Prompt.pad && MenuNav.shared.autoOpened !== m {
            MenuNav.shared.autoOpened = m          // once per sign, so closing the keyboard doesn't reopen it
            menu = KeyboardMenu(game: self, target: m)
            menuCursor = 0
            return
        }
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
        if !m.capturesText || m is KeyboardMenu || (m as? PauseMenu).map({ $0.binding == nil }) == true {
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
            if let sm = m as? ShopMenu, menuCursor == before, my != 0 { sm.scrollBy(my > 0 ? 1 : -1) }
            padMoved = true
            if menuCursor != before { sfx(.uiHover, 0.3) }
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
            if tab != 0 { c.switchTab(tab) }
            let page = (p.rt > 0.5 && q.rt <= 0.5 ? 1 : 0) - (p.lt > 0.5 && q.lt <= 0.5 ? 1 : 0)
            if page != 0 { c.scrollBy(page * c.rows) }
        }
        if let sm = m as? ShopMenu {
            if scroll != 0 { sm.scrollBy(scroll) }
            if tab != 0 { sm.buttonPressed(sm.selling ? ShopMenu.tabBuy : ShopMenu.tabSell) }
        }
        if let mm = m as? MerchantMenu, scroll != 0 {
            mm.scroll = max(0, min(max(0, mm.offers.count - MerchantMenu.visible), mm.scroll + scroll))
        }
        if let sc = m as? StonecutterMenu, tab != 0, sc.pages > 1 {
            sc.page = (sc.page + tab + sc.pages) % sc.pages; sc.selected = -1; sc.changed(); sfx(.click, 0.4)
        }
        if let am = m as? AdvancementMenu {
            if scroll != 0 { am.scroll = max(0, min(max(0, am.list.count - AdvancementMenu.rows), am.scroll + scroll)) }
            if tab != 0 { am.tab = (am.tab + tab + Advancements.tabs.count) % Advancements.tabs.count; am.scroll = 0; sfx(.click, 0.4) }
        }
        if let pm = m as? PauseMenu {
            if tab != 0 { pm.switchTab(tab) }
            if scroll != 0 { pm.scrollList(scroll) }
        }
        if let bm = m as? BookMenu, tab != 0, !bm.signing { bm.buttonPressed(tab > 0 ? 1 : 0); sfx(.click, 0.4) }
        if let cb = m as? CraftingBookMenu {
            if tab != 0 { cb.switchTab(tab) }
            let page = (p.rt > 0.5 && q.rt <= 0.5 ? 1 : 0) - (p.lt > 0.5 && q.lt <= 0.5 ? 1 : 0)
            if page != 0 { cb.flip(page) }
            if scroll != 0 { cb.flip(scroll) }
            cb.padHold(p.a, dt)
        }
        // LB/RB in the inventory open its crafting book (2x2), whose grid button comes back.
        if m is InventoryMenu, tab != 0 { switchMenu(to: CraftingBookMenu(game: self, size: 2)); sfx(.click, 0.4); return }
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
            if let s = m.slotAt(mouse, L), !carried.isEmpty, !shift, s.container != nil, case .normal = s.kind, creative == nil {
                // A press with a stack on the cursor may start a drag: decided on release (one slot = a plain click).
                menuDrag = [s]; menuDragButton = b
            } else if let s = m.slotAt(mouse, L) { m.mouseClick = true; m.click(s, button: b, shift: shift); m.mouseClick = false }
            else if !m.inside(mouse, L) && !carried.isEmpty {
                if b == 0 { dropItem(carried); carried = .empty }
                else { dropItem(carried.with(count: 1)); carried.count -= 1; if carried.count <= 0 { carried = .empty } }
            }
        }

        // Mouse drag over slots (reference): left splits the cursor stack evenly (rounding down, the rest stays on the
        // cursor), right places one in each. It was click-only.
        if !menuDrag.isEmpty {
            let held = menuDragButton == 0 ? input.leftDown : input.rightDown
            if held {
                if let s = m.slotAt(mouse, L), !menuDrag.contains(where: { $0 === s }), s.container != nil, case .normal = s.kind,
                   s.accepts(carried), s.stack.isEmpty || s.stack.stacks(with: carried), menuDrag.count < carried.count {
                    menuDrag.append(s)
                }
            } else {
                let set = menuDrag
                menuDrag = []
                if set.count == 1 {
                    m.mouseClick = true; m.click(set[0], button: menuDragButton, shift: false); m.mouseClick = false
                } else if !carried.isEmpty {
                    let per = menuDragButton == 0 ? max(1, carried.count / set.count) : 1
                    var c = carried
                    for s in set where c.count > 0 {
                        var st = s.stack
                        let room = m.slotLimit(s, c) - (st.isEmpty ? 0 : st.count)
                        let n = min(per, c.count, max(0, room))
                        guard n > 0 else { continue }
                        if st.isEmpty { st = c.with(count: n) } else { st.count += n }
                        s.stack = st
                        c.count -= n
                    }
                    carried = c.count > 0 ? c : .empty
                    m.changed()
                }
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
            if p.a && !q.a {
                let wasText = m.capturesText
                m.click(s, button: 0, shift: false)
                // A pad user who just activated a text field (anvil name, creative search) gets the keyboard at once.
                // (Not the pause menu: it opens the keyboard itself for its text rows, and key capture isn't typing.)
                if keyboard == nil && !wasText && m.capturesText && menu === m && Prompt.pad && !(m is PauseMenu) {
                    menu = KeyboardMenu(game: self, target: m)
                    menuCursor = 0
                    return
                }
            }
            if keyboard == nil && p.x && !q.x { m.click(s, button: 1, shift: false) }
            if keyboard == nil && p.y && !q.y && !m.capturesText {
                // On the pause menu Y is Next Track (CustomMusic.swift); elsewhere a quick move / shift-click.
                if let pm = m as? PauseMenu, pm.page == .main { skipMusicTrack() } else { m.click(s, button: 0, shift: true) }
            }
            // Number keys swap the hovered slot with a hotbar slot.
            for (i, k) in Key.digits.enumerated() where input.tapped(k) && !m.capturesText {
                // The hotbar stack goes in only where the slot takes it whole (it skipped `accepts` and the slot limit:
                // a stack of books swapped into the enchanting slot was used up as one).
                let h = inventory.main[i]
                var swappable = false
                switch s.kind {
                case .normal, .fuel: swappable = true
                case .armor: swappable = !(survival && !s.stack.isEmpty && Enchant.level(.bindingCurse, s.stack) > 0)
                case .output:
                    // An output moves into an empty hotbar slot (reference; number keys skipped outputs).
                    if h.isEmpty && !s.stack.isEmpty { inventory.main[i] = s.stack; s.stack = .empty; m.tookOutput(s); m.changed() }
                case .result:
                    if h.isEmpty && !s.stack.isEmpty, let r = m.takeResult(s) { inventory.main[i] = r; m.changed() }
                default: break
                }
                if swappable, s.container != nil, h.isEmpty || (s.accepts(h) && h.count <= m.slotLimit(s, h)) {
                    let a = s.stack
                    s.stack = h
                    inventory.main[i] = a
                    m.changed()
                }
            }
        }
        // Keyboard-only: Enter presses the highlighted button (arrow keys move, left/right change settings).
        if input.tapped(Key.enter) && !m.capturesText && keyboard == nil, let s = menuHover, s.isButton {
            m.click(s, button: 0, shift: false)
            if menu !== m { return }
        }
        // LT in a container screen: take everything from the container (hovering it), or store every stack of the
        // hovered item (hovering the inventory). Console-style "Take all / Store all".
        if p.lt > 0.5 && q.lt <= 0.5 && creative == nil && keyboard == nil && !(m is PauseMenu) && !(m is InventoryMenu) && !(m is CraftingBookMenu), let h = menuHover,
           !h.isButton, case .normal = h.kind, h.container != nil, m.slots.contains(where: { !$0.isPlayerInv && $0.container != nil && !$0.isButton }) {
            let fromPlayer = h.isPlayerInv
            let want = h.stack.item
            var moved = false
            for src in m.slots where src.isPlayerInv == fromPlayer && !src.isButton && src.container != nil && !src.stack.isEmpty {
                guard case .normal = src.kind, !fromPlayer || src.stack.item == want else { continue }
                let before = src.stack.count
                src.stack = m.moveInto(src.stack, m.quickMoveTargets(from: src))
                if src.stack.count != before { moved = true }
            }
            if moved { m.changed(); sfx(.pickup, 0.4) }
        }
        // The drop key (Q) over a slot drops one item, Ctrl+Q the whole stack (reference; it did nothing in menus).
        if input.tapped(KeyBinds.key(.drop)) && !m.capturesText && keyboard == nil && creative == nil, carried.isEmpty,
           let s = menuHover, !s.isButton, s.container != nil, !s.stack.isEmpty {
            if case .palette = s.kind {} else if case .result = s.kind {} else {
                var st = s.stack
                let n = input.control ? st.count : 1
                dropItem(st.with(count: n))
                st.count -= n
                s.stack = st.count > 0 ? st : .empty
                if case .output = s.kind { m.tookOutput(s) }
                m.changed()
            }
        }
        // RT drops the held stack (or one item from the hovered slot), like dropping outside the panel.
        if p.rt > 0.5 && q.rt <= 0.5 && !(m is PauseMenu) && !(m is KeyboardMenu) && creative == nil && !(m is CraftingBookMenu) {
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
        if m.capturesText && p.y && !q.y && !(m is KeyboardMenu) && (m as? PauseMenu)?.binding == nil {
            menu = KeyboardMenu(game: self, target: m)
            menuCursor = 0
            return
        }
        if (input.tapped(KeyBinds.key(.inventory)) && !m.capturesText) || input.tapped(Key.esc) || (p.b && !q.b) || (p.view && !q.view) { closeMenu() }
    }
}
