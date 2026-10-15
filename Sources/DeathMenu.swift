import Foundation

// "You Died!" screen: the death message and score, then Respawn or Title Screen (controller: A / D-pad).
final class DeathMenu: Menu {
    let message: String
    let detailLines: [String]          // Q2c-console-4: where his things are, wrapped to the panel
    init(game: Game, message: String, detail: String = "") {
        self.message = message
        detailLines = detail.isEmpty ? [] : Journal.wrap(detail, width: 204)
        super.init("", game: game)
        showInventoryLabel = false
        let extra = detailLines.count * 9 + (detailLines.isEmpty ? 0 : 4)
        width = 220; height = 110 + extra
        let r = MenuSlot(10, 58 + extra, nil, 0, .button(0)); r.w = 200; r.h = 18; slots.append(r)
        let t = MenuSlot(10, 82 + extra, nil, 0, .button(1)); t.w = 200; t.h = 18; slots.append(t)
    }
    override func buttonPressed(_ i: Int) {
        game.menu = nil
        game.respawn()
        if i == 1 { game.paused = true; if let pm = game.menu as? PauseMenu { pm.page = .title; pm.build() } }   // "Title Screen"
        game.sfx(.click, 0.5)
    }
    override func backPressed() -> Bool { true }   // can't be dismissed without choosing
}
