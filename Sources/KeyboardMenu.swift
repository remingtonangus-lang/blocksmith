import Foundation

// On-screen keyboard for controller-only text entry (signs, book pages and titles, anvil names, commands).
// Shift turns the digit row into symbols (/ - ~ : ...).
// Press Y in a text screen to open it; A types the highlighted key, X deletes, Y adds a space, LT is Shift,
// Menu (or "Done") returns, B returns too.
final class KeyboardMenu: Menu {
    let target: Menu
    static let rowsLower = ["1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.?"]
    var upper = false
    var keys: [String] = []
    init(game: Game, target: Menu) {
        self.target = target
        super.init("", game: game)     // the preview label takes the title spot
        showInventoryLabel = false
        width = 176; height = 142
        build()
    }
    func build() {
        slots = []; keys = []
        for (r, row) in KeyboardMenu.rowsLower.enumerated() {
            for (c, ch) in row.enumerated() {
                let b = MenuSlot(8 + c * 16, 32 + r * 18, nil, 0, .button(keys.count)); b.w = 14; b.h = 16
                slots.append(b)
                let sym = Array("!/-~:;()+=")[c]
                keys.append(upper ? (r == 0 ? String(sym) : String(ch).uppercased()) : String(ch))
            }
        }
        for (i, (label, w)) in [("Shift", 30), ("Space", 62), ("Del", 30), ("Enter", 30)].enumerated() {
            let x = [8, 40, 104, 136][i]
            let b = MenuSlot(x, 108, nil, 0, .button(keys.count)); b.w = w; b.h = 16
            slots.append(b); keys.append(label)
        }
        let d = MenuSlot(8, 126, nil, 0, .button(keys.count)); d.w = 160; d.h = 12
        slots.append(d); keys.append("Done")
    }
    override func buttonPressed(_ i: Int) {
        guard i < keys.count else { return }
        switch keys[i] {
        case "Shift": toggleShift()
        case "Space": target.typed(" ")
        case "Del": target.typed("\u{8}")
        case "Enter":
            if let b = target as? BookMenu, !b.signing { b.typed("\n") } else if let s = target as? SignMenu { s.line = min(3, s.line + 1) }
            else if let cm = target as? CommandMenu { cm.run() }
            else if let pm = target as? PauseMenu { pm.editing = nil; pm.build(); finish() }
        case "Done": finish()
        default: target.typed(keys[i])
        }
        game.sfx(.click, 0.3)
    }
    // What is being typed, shown above the keys (the edited screen itself is hidden behind the keyboard).
    var preview: (label: String, text: String) {
        switch target {
        case let pm as PauseMenu:
            switch pm.editing {
            case 0?: return ("World name", pm.newName)
            case 1?: return ("Seed", pm.newSeed)
            default: return ("New name", pm.renameText)
            }
        case let sm as SignMenu: return ("Sign line \(sm.line + 1)", sm.line < sm.be.lines.count ? sm.be.lines[sm.line] : "")
        case let bm as BookMenu:
            if bm.signing { return ("Book title", bm.bookTitle) }
            let pg = bm.page < bm.pages.count ? bm.pages[bm.page] : ""
            return ("Page \(bm.page + 1)", pg.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? "")
        case let am as AnvilMenu: return ("Item name", am.name)
        case let cm as CommandMenu: return ("Command", cm.line)
        case let cr as CreativeMenu: return ("Search", cr.query)
        default: return ("Text", "")
        }
    }

    func toggleShift() {
        upper.toggle()
        let cur = game.menuCursor
        build()
        game.menuCursor = cur
        game.sfx(.click, 0.3)
    }
    // Closed outright (Esc, View, death) while typing: the screen it types into closes too, returning what it holds
    // (the anvil's two input items were lost when its name keyboard was closed).
    override func onClose() { target.onClose() }

    func finish() {
        game.menu = target
        game.menuCursor = 0
    }
    override func backPressed() -> Bool { finish(); return true }
}
