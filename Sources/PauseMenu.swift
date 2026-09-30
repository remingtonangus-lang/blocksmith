import Foundation

// In-game pause and options screens (drawn with the HUD, so a controller can drive them: D-pad /
// stick to move, A to choose or step a setting forward, X to step it back, B to go back).
final class PauseMenu: Menu {
    enum Page { case main, options, worlds }
    var page: Page = .main
    // (label, action id); settings show their current value in the label.
    var rows: [(String, String)] = []

    init(game: Game) {
        super.init("Game Paused", game: game)
        showInventoryLabel = false
        build()
    }

    func build() {
        let g = game
        switch page {
        case .main:
            title = "Game Paused"
            rows = [("Back to Game", "resume"), ("Options…", "options"), ("Advancements", "advancements"),
                    ("Mode: \(g.survival ? "Survival" : "Creative")", "mode"),
                    ("Difficulty: \(Game.difficultyNames[g.difficulty])", "difficulty"),
                    ("Load World…", "load"), ("New World (random seed)", "newworld"), ("Create World… (keyboard)", "worlds"),
                    ("Toggle Fullscreen", "fullscreen"), ("Save and Quit", "quit")]
        case .options:
            title = "Options"
            let gui = HudLayout.userScale == 0 ? "Auto" : "\(HudLayout.userScale)"
            rows = [("FOV: \(Int(g.fovSetting))", "fov"), ("Sensitivity: \(Int(g.sensitivity * 100))%", "sens"),
                    ("Invert Y: \(g.invertY ? "On" : "Off")", "invert"), ("Stick Dead Zone: \(Int(g.deadZone * 100))%", "dead"),
                    ("Render Distance: \(g.world.renderDistance)", "rd"), ("GUI Scale: \(gui)", "gui"),
                    ("Couch Mode (TV): \(HudLayout.couch ? "On" : "Off")", "couch"), ("Volume: \(Int(g.volumeSetting * 100))%", "volume"), ("Music: \(Int(g.musicVolume * 100))%", "music"),
                    ("Done", "back")]
        case .worlds:
            title = "Load World"
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Blocksmith/Worlds")
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
            rows = names.prefix(10).map { ("Play \($0)", "play:" + $0) } + [("Back", "back")]
        }
        slots = []
        width = 220
        height = 30 + rows.count * 22 + 8
        for i in rows.indices {
            let b = MenuSlot(10, 26 + i * 22, nil, 0, .button(i))
            b.w = 200; b.h = 18
            slots.append(b)
        }
    }

    // A = forward, X / right-click = back one step.
    override func click(_ slot: MenuSlot, button: Int, shift: Bool) {
        guard case .button(let i) = slot.kind, i < rows.count else { return }
        act(rows[i].1, back: button == 1)
    }
    override func buttonPressed(_ i: Int) { if i < rows.count { act(rows[i].1, back: false) } }

    func act(_ id: String, back: Bool) {
        let g = game
        func step<T: Equatable>(_ opts: [T], _ cur: T) -> T {
            let i = opts.firstIndex(of: cur) ?? 0
            return opts[(i + (back ? opts.count - 1 : 1)) % opts.count]
        }
        switch id {
        case "resume": g.closeMenu()
        case "options": page = .options
        case "back": page = .main
        case "load": page = .worlds
        case _ where id.hasPrefix("play:"): g.appAction?(id)
        case "advancements": g.closeMenu(); g.openMenu(AdvancementMenu(game: g))
        case "mode": g.toggleMode(); g.onModeChanged?(g.survival)
        case "difficulty": g.difficulty = step([0, 1, 2, 3], g.difficulty)
        case "fov": g.fovSetting = step([60, 70, 80, 90, 100, 110], g.fovSetting)
        case "sens": g.sensitivity = step([0.5, 0.75, 1, 1.25, 1.5, 2, 3], g.sensitivity)
        case "invert": g.invertY.toggle()
        case "dead": g.deadZone = step([0.05, 0.1, 0.15, 0.2, 0.25, 0.3], g.deadZone)
        case "rd":
            let opts = [4, 6, 8, 10, 12, 16, 20, 24]
            g.world.renderDistance = step(opts, g.world.renderDistance)
            g.onRenderDistanceChanged?(g.world.renderDistance)
            UserDefaults.standard.set(g.world.renderDistance, forKey: "renderDistance")
        case "gui": HudLayout.userScale = step([0, 1, 2, 3, 4, 5, 6], HudLayout.userScale)
        case "couch": HudLayout.couch.toggle()
        case "volume": g.volumeSetting = step([0, 0.25, 0.5, 0.8, 1], g.volumeSetting)
        case "music": g.musicVolume = step([0, 0.25, 0.5, 0.75, 1], g.musicVolume)
        default: g.appAction?(id)
        }
        g.sfx(.click, 0.5)
        if g.menu === self {
            let cur = g.menuCursor
            build()
            g.menuCursor = min(cur, slots.count - 1)
            if id == "options" || id == "back" || id == "load" { g.menuCursor = 0 }
        }
    }

    override func backPressed() -> Bool {
        guard page != .main else { return false }
        act("back", back: false)
        return true
    }
    override func onClose() { game.paused = false }
}
