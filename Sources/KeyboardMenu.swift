import Foundation

// On-screen keyboard for controller-only text entry (signs, book pages and titles, anvil names).
// Press Y in a text screen to open it; A types the highlighted key, B (or "Done") returns.
final class KeyboardMenu: Menu {
    let target: Menu
    static let rowsLower = ["1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.?"]
    var upper = false
    var keys: [String] = []
    init(game: Game, target: Menu) {
        self.target = target
        super.init("Keyboard", game: game)
        showInventoryLabel = false
        width = 176; height = 128
        build()
    }
    func build() {
        slots = []; keys = []
        for (r, row) in KeyboardMenu.rowsLower.enumerated() {
            for (c, ch) in row.enumerated() {
                let b = MenuSlot(8 + c * 16, 18 + r * 18, nil, 0, .button(keys.count)); b.w = 14; b.h = 16
                slots.append(b)
                keys.append(upper ? String(ch).uppercased() : String(ch))
            }
        }
        for (i, (label, w)) in [("Shift", 30), ("Space", 62), ("Del", 30), ("Enter", 30)].enumerated() {
            let x = [8, 40, 104, 136][i]
            let b = MenuSlot(x, 94, nil, 0, .button(keys.count)); b.w = w; b.h = 16
            slots.append(b); keys.append(label)
        }
        let d = MenuSlot(8, 112, nil, 0, .button(keys.count)); d.w = 160; d.h = 12
        slots.append(d); keys.append("Done")
    }
    override func buttonPressed(_ i: Int) {
        guard i < keys.count else { return }
        switch keys[i] {
        case "Shift": upper.toggle(); let cur = game.menuCursor; build(); game.menuCursor = cur
        case "Space": target.typed(" ")
        case "Del": target.typed("\u{8}")
        case "Enter":
            if let b = target as? BookMenu, !b.signing { b.typed("\n") } else if let s = target as? SignMenu { s.line = min(3, s.line + 1) }
        case "Done": finish()
        default: target.typed(keys[i])
        }
        game.sfx(.click, 0.3)
    }
    func finish() {
        game.menu = target
        game.menuCursor = 0
    }
    override func backPressed() -> Bool { finish(); return true }
}
