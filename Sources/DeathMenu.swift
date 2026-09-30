import Foundation

// "You Died!" screen: the death message and score, then Respawn or Title Screen (controller: A / D-pad).
final class DeathMenu: Menu {
    let message: String
    init(game: Game, message: String) {
        self.message = message
        super.init("", game: game)
        showInventoryLabel = false
        width = 220; height = 110
        let r = MenuSlot(10, 58, nil, 0, .button(0)); r.w = 200; r.h = 18; slots.append(r)
        let t = MenuSlot(10, 82, nil, 0, .button(1)); t.w = 200; t.h = 18; slots.append(t)
    }
    override func buttonPressed(_ i: Int) {
        game.menu = nil
        game.respawn()
        if i == 1 { game.paused = true; if let pm = game.menu as? PauseMenu { pm.page = .title; pm.build() } }   // "Title Screen"
        game.sfx(.click, 0.5)
    }
    override func backPressed() -> Bool { true }   // can't be dismissed without choosing
}
