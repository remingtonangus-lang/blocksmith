import Foundation

// Title screen, pause menu, options (six pages switched with LB/RB), worlds list (play / rename / copy /
// delete with confirmation) and world creation. Drawn with the HUD so a controller drives everything:
// D-pad / stick to move, A to choose or step a setting forward, X (or D-pad left/right) to step it,
// B to go back. The list scrolls when it is longer than the panel.
final class PauseMenu: Menu {
    enum Page { case title, main, options, controls, keys, padmap, worlds, world, confirm, create, rename }
    enum Cat: Int, CaseIterable {
        case controls, controller, video, audio, interface, accessibility
        var name: String { ["Keyboard & Mouse", "Controller", "Video", "Audio", "Interface", "Accessibility"][rawValue] }
    }
    var page: Page = .main
    var cat: Cat = .controller
    var stack: [Page] = []
    // (label, action id); settings show their current value in the label.
    var rows: [(String, String)] = []
    var scroll = 0
    static let visible = 9
    var subtitle = ""                // small line under the title (page hint, confirmation text)
    var cameFromTitle: Bool { stack.first == .title || page == .title }
    // Create World page (controller-friendly: the text fields use the on-screen keyboard).
    var newName = "New World"
    var newSeed = ""
    var newSurvival = true
    var newDifficulty = 2
    var editing: Int? = nil        // 0 name, 1 seed, 2 rename
    var selWorld = ""              // world picked on the worlds page
    var renameText = ""
    var worlds: [WorldStore.Info] = []
    var confirmReset = false              // the confirm page is asking about options, not a world
    var padBinding: Int? = nil             // Button Mapping: logical button waiting for a physical press
    var padBindArmed: Double = 0
    var binding: KeyBinds.Action? = nil   // waiting for a key press on the Key Bindings page

    init(game: Game) {
        super.init("Game Paused", game: game)
        showInventoryLabel = false
        build()
    }

    var currentWorld: String { game.save?.dir.lastPathComponent ?? "" }

    static let valueIDs: Set<String> = ["sens", "invert", "autojump", "fov", "lookx", "looky", "accel", "dead", "aim", "rumble", "southpaw",
                                        "sneaktoggle", "autosprint", "glyphs", "rd", "fullscreen", "launchfs", "vsync", "fps", "rscale",
                                        "gui", "couch", "safe", "hints", "textbg", "volume", "music", "subtitles", "colorblind", "tutorial",
                                        "mode", "difficulty", "new_mode", "new_diff", "hidehud", "debug", "crosshair", "flashes", "curve", "narrator", "display", "bugnotes"]

    static let help: [String: String] = [
        "resume": "Return to the game.",
        "worlds": "Play, create, rename, copy or delete worlds.",
        "options": "Controls, controller, video, audio, interface and accessibility.",
        "sens": "How fast the mouse turns the view.",
        "lookx": "How fast the right stick turns left and right.",
        "looky": "How fast the right stick looks up and down.",
        "accel": "Turns faster the longer the right stick is held at its edge.",
        "curve": "Classic eases in gently, Linear follows the stick exactly, Precise is slow near the centre.",
        "dead": "Stick movement ignored around the centre. Raise it if the view drifts.",
        "aim": "Controller only: the view slows over hostile mobs and while mining.",
        "rumble": "Controller vibration when you are hit, mine, attack or something explodes.",
        "southpaw": "Southpaw swaps the sticks: look with the left, move with the right.",
        "sneaktoggle": "Toggle: press B / right stick once to crouch, again to stand.",
        "autosprint": "Push the left stick fully forward for a moment to sprint.",
        "glyphs": "Which buttons prompts show. Auto follows the last device you touched.",
        "padinfo": "Press A to test vibration.",
        "rd": "How many chunks around you are drawn. Lower is smoother.",
        "fullscreen": "Switch between a window and the full screen.",
        "display": "Which screen to play on when the Mac is connected to a TV. Remembered for next time.",
        "launchfs": "Open Blocksmith straight into full screen, ready for the TV.",
        "vsync": "Sync frames to the display. Off can lower input lag but may tear.",
        "fps": "Frame rate cap. 30 or 60 keeps a laptop cooler.",
        "rscale": "Renders fewer pixels and scales up. 75% helps a lot on a 4K TV.",
        "gui": "Size of menus and the HUD. Auto picks the largest that fits.",
        "couch": "Bigger HUD and menus for playing from the sofa.",
        "safe": "Keeps the HUD away from the screen edges on TVs that crop them.",
        "hints": "Control legends under menus and button prompts in the game.",
        "textbg": "Dark boxes behind HUD text for readability.",
        "subtitles": "Shows captions for sounds, with the direction they come from.",
        "colorblind": "Uses blue and orange instead of green and red for cues.",
        "tutorial": "First-steps tips while you play.",
        "resethints": "Show the first-steps tips again from the start.",
        "controls": "Every control for keyboard, mouse and controller.",
        "keys": "Choose which keys walk, jump, open the inventory and more.",
        "padmap": "Move actions to other controller buttons. Prompts follow your layout.",
        "pbindreset": "Put every controller button back to the standard layout.",
        "bindreset": "Put every key back to the default layout.",
        "volume": "Overall sound volume.",
        "music": "Background music volume.",
        "mode": "Survival: health, hunger, mining. Creative: fly and build freely.",
        "difficulty": "How much damage mobs do and whether hunger can kill.",
        "crosshair": "Bold is thicker with a dark edge, easy to see on a TV. Dot is a small square.",
        "narrator": "Reads the highlighted menu item and messages aloud with the system voice.",
        "bugnotes": "Speak bugs while playing; they are saved to Documents/Blocksmith/BugNotes with a screenshot.",
        "flashes": "Reduced makes the red damage flash and portal tint faint.",
        "resetask": "Put every option and key binding back to its default.",
        "hidehud": "Hide the hotbar and crosshair (screenshots). F1 on the keyboard.",
        "debug": "Position, biome, frame rate and chunk details (F3).",
        "quit": "Save the world and close Blocksmith.",
        "totitle": "Save the world and return to the title screen.",
        "create": "Choose a name, seed, game mode and difficulty.",
        "newworld": "Start a new world with a random seed straight away.",
        "w_play": "Load this world.",
        "w_rename": "Give this world a new name.",
        "w_copy": "Make a copy of this world (a backup before big changes).",
        "w_delete": "Move this world to the Trash.",
    ]

    func build() {
        let g = game
        let st = Settings.shared
        func on(_ b: Bool) -> String { b ? "On" : "Off" }
        func pct(_ f: Float) -> String { "\(Int((f * 100).rounded()))%" }
        subtitle = ""
        switch page {
        case .title:
            title = ""
            let last = UserDefaults.standard.string(forKey: "lastWorld") ?? "World1"
            rows = [("Play: \(last)", "resume"), ("Worlds...", "worlds"), ("Options...", "options"), ("Quit Game", "quit")]
        case .main:
            title = "Game Paused"
            if let t = PadManager.shared.disconnectedAt, g.clock - t < 600, !PadManager.shared.connected {
                subtitle = "Controller disconnected - reconnect it or use the keyboard"
            } else if !currentWorld.isEmpty {
                subtitle = "\(currentWorld) - day \(Int(g.time / DAY_LENGTH) + 1)"
            }
            rows = [("Back to Game", "resume"), ("Options...", "options"), ("Advancements", "advancements"), ("Commands...", "commands"),
                    ("Mode: \(g.survival ? "Survival" : "Creative")", "mode"),
                    ("Difficulty: \(Game.difficultyNames[g.difficulty])", "difficulty"),
                    ("Worlds...", "worlds"), ("Save and Quit to Title", "totitle"), ("Save and Quit Game", "quit")]
        case .options:
            title = "Options: \(cat.name)"
            subtitle = "Page \(cat.rawValue + 1) of \(Cat.allCases.count)"
            let gui = HudLayout.userScale == 0 ? "Auto" : "\(HudLayout.userScale)"
            switch cat {
            case .controls:
                rows = [("Mouse Sensitivity: \(pct(g.sensitivity))", "sens"), ("Invert Y: \(on(g.invertY))", "invert"),
                        ("Auto-Jump: \(on(g.autoJump))", "autojump"), ("Field of View: \(Int(g.fovSetting))", "fov"),
                        ("Key Bindings...", "keys"), ("Controls Reference...", "controls"), ("Reset Tutorial Hints", "resethints")]
            case .controller:
                let pm = PadManager.shared
                let info = pm.connected ? pm.name + (pm.battery.map { " (\(Int($0 * 100))%)" } ?? "") : "No controller"
                rows = [("\(info)", "padinfo"),
                        ("Look Speed X: \(pct(st.lookX))", "lookx"), ("Look Speed Y: \(pct(st.lookY))", "looky"),
                        ("Look Acceleration: \(st.lookAccel == 0 ? "Off" : pct(st.lookAccel))", "accel"),
                        ("Look Response: \(["Classic", "Linear", "Precise"][max(0, min(2, st.lookCurve))])", "curve"),
                        ("Invert Y: \(on(g.invertY))", "invert"), ("Stick Dead Zone: \(pct(g.deadZone))", "dead"),
                        ("Aim Assist: \(on(st.aimAssist))", "aim"), ("Vibration: \(st.rumble == 0 ? "Off" : pct(st.rumble))", "rumble"),
                        ("Stick Layout: \(st.southpaw ? "Southpaw" : "Standard")", "southpaw"),
                        ("Sneak: \(st.sneakToggle ? "Toggle" : "Hold")", "sneaktoggle"), ("Auto-Sprint: \(on(st.autoSprint))", "autosprint"),
                        ("Button Prompts: \(["Auto", "Controller", "Keyboard"][max(0, min(2, st.glyphStyle))])", "glyphs"),
                        ("Button Mapping...", "padmap")]
            case .video:
                rows = [("Render Distance: \(g.world.renderDistance)", "rd"), ("Fullscreen: \(on(VideoState.fullscreen))", "fullscreen"),
                        ("Display: \(VideoState.current.isEmpty ? "Main" : VideoState.current)", "display"),
                        ("Start in Fullscreen: \(on(st.launchFullscreen))", "launchfs"), ("VSync: \(on(st.vsync))", "vsync"),
                        ("Max Frame Rate: \(st.fpsCap == 0 ? "Display" : "\(st.fpsCap)")", "fps"),
                        ("Resolution: \(pct(st.renderScale))", "rscale"), ("Field of View: \(Int(g.fovSetting))", "fov"), ("GUI Scale: \(gui)", "gui")]
            case .audio:
                rows = audioRows()          // one slider per sound category, subtitles, test sound (AudioMenu.swift)
            case .interface:
                rows = [("GUI Scale: \(gui)", "gui"), ("Couch Mode (TV): \(on(HudLayout.couch))", "couch"),
                        ("Safe Area: \(st.safeArea)%", "safe"), ("Button Hints: \(on(st.buttonHints))", "hints"),
                        ("Text Background: \(st.textBackground == 0 ? "Off" : pct(st.textBackground))", "textbg"),
                        ("Crosshair: \(["Classic", "Bold", "Dot"][max(0, min(2, st.crosshair))])", "crosshair"),
                        ("Hide HUD: \(on(g.hideHUD))", "hidehud"), ("Debug Info: \(on(g.showDebug))", "debug"),
                        ("Bug Notes: " + (BugNotes.denied ? "No mic access" : BugNotes.names[max(0, min(2, st.bugNotes))]), "bugnotes"),
                        ("Reset Options...", "resetask")]
            case .accessibility:
                rows = [("Subtitles: \(on(st.subtitles))", "subtitles"), ("Narrator: \(on(st.narrator))", "narrator"),
                        ("Colorblind-Safe Colors: \(on(st.colorblind))", "colorblind"),
                        ("Text Background: \(st.textBackground == 0 ? "Off" : pct(st.textBackground))", "textbg"),
                        ("Tutorial Hints: \(on(st.tutorialHints))", "tutorial"),
                        ("Screen Flashes: \(st.screenEffects ? "Full" : "Reduced")", "flashes"),
                        ("Crosshair: \(["Classic", "Bold", "Dot"][max(0, min(2, st.crosshair))])", "crosshair"),
                        ("Button Prompts: \(["Auto", "Controller", "Keyboard"][max(0, min(2, st.glyphStyle))])", "glyphs"),
                        ("Vibration: \(st.rumble == 0 ? "Off" : pct(st.rumble))", "rumble")]
            }
            rows.append(("Done", "back"))
        case .padmap:
            title = "Button Mapping"
            subtitle = padBinding.map { "Press the button for \(PadMap.actions[$0]) (Menu cancels)" } ?? "Pick an action, then press its new button"
            rows = (0..<PadMap.count).map { i in
                ("\(PadMap.actions[i]): " + (padBinding == i ? "> ? <" : PadMap.names[PadMap.map[i]]), "pbind:\(i)")
            } + [("Reset to Defaults", "pbindreset"), ("Done", "back")]
        case .keys:
            title = "Key Bindings"
            subtitle = binding == nil ? "Shift sneaks and Ctrl sprints on every layout" : "Press a key for \(binding!.title) (Esc cancels)"
            rows = KeyBinds.Action.allCases.map { a in
                ("\(a.title): " + (binding == a ? "> ? <" : KeyBinds.name(KeyBinds.key(a))), "bind:" + a.rawValue)
            } + [("Reset to Defaults", "bindreset"), ("Done", "back")]
        case .controls:
            title = "Controls"
            rows = ControlsReference.rows().map { ($0, "noop") } + [("Done", "back")]
        case .worlds:
            title = "Worlds"
            worlds = WorldStore.list()
            rows = [("Create New World...", "create"), ("Quick New World (random seed)", "newworld")]
                + worlds.map { ($0.name == currentWorld ? "\($0.name)  (open)" : $0.name, "world:" + $0.name) }
                + [("Back", "back")]
        case .world:
            title = selWorld
            let info = worlds.first { $0.name == selWorld }
            subtitle = info.map { WorldStore.describe($0) } ?? ""
            rows = [(selWorld == currentWorld ? "Continue" : "Play", "w_play"), ("Rename...", "w_rename"), ("Copy", "w_copy"),
                    ("Delete...", "w_delete"), ("Back", "back")]
        case .confirm where confirmReset:
            title = "Reset Options?"
            subtitle = "Every option and key binding goes back to its default."
            rows = [("Cancel", "back"), ("Reset", "reset_yes")]
        case .confirm:
            title = "Delete World?"
            subtitle = "\"\(selWorld)\" will be moved to the Trash."
            rows = [("Cancel", "back"), ("Delete", "w_delete_yes")]
        case .rename:
            title = "Rename World"
            let caret = Int(g.clock * 2) % 2 == 0 ? "_" : " "
            rows = [("Name: \(renameText)\(editing == 2 ? caret : "")", "edit_rename"), ("Save", "w_rename_yes"), ("Cancel", "back")]
        case .create:
            title = "Create New World"
            let caret = Int(g.clock * 2) % 2 == 0 ? "_" : " "
            rows = [("Name: \(newName)\(editing == 0 ? caret : "")", "edit_name"),
                    ("Seed: \(newSeed.isEmpty && editing != 1 ? "(random)" : newSeed)\(editing == 1 ? caret : "")", "edit_seed"),
                    ("Game Mode: \(newSurvival ? "Survival" : "Creative")", "new_mode"),
                    ("Difficulty: \(Game.difficultyNames[newDifficulty])", "new_diff"),
                    ("Create World", "new_create"), ("Back", "back")]
        }
        layout()
    }

    // One column of buttons; only `visible` rows at a time, scrolled with the cursor / right stick.
    func layout() {
        let n = min(rows.count, PauseMenu.visible)
        scroll = max(0, min(scroll, rows.count - n))
        slots = []
        let top = subtitle.isEmpty ? 22 : 32
        width = 244
        height = top + n * 21 + 22 + (rows.count > n ? 4 : 0)   // + help line
        for i in 0..<n {
            let b = MenuSlot(10, top + i * 21, nil, 0, .button(i))
            b.w = 224; b.h = 18
            slots.append(b)
        }
    }

    func row(forSlot i: Int) -> (String, String)? {
        let k = scroll + i
        return k >= 0 && k < rows.count ? rows[k] : nil
    }
    var hoveredID: String? {
        guard let h = game.menuHover, let i = slots.firstIndex(where: { $0 === h }) else { return nil }
        return row(forSlot: i)?.1
    }
    var helpText: String {
        guard let id = hoveredID else { return "" }
        if id.hasPrefix("world:") {
            let n = String(id.dropFirst(6))
            return worlds.first { $0.name == n }.map { WorldStore.describe($0) } ?? ""
        }
        return PauseMenu.help[id] ?? ""
    }

    var legend: String {
        var items: [(Prompt.Act, String)] = [(.select, "Select")]
        let value = hoveredID.map { PauseMenu.valueIDs.contains($0) } ?? false
        if value && !Prompt.pad { items.append((.alt, "Previous")) }
        if page == .options { items.append((.tabs, "Page")) }
        if page != .title && page != .main { items.append((.back, "Back")) } else if page == .main { items.append((.back, "Resume")) }
        var s = Prompt.line(items)
        if value && Prompt.pad { s = Prompt.g(.select) + " / " + Glyph.dpadH.s + " Change   " + Prompt.line(Array(items.dropFirst())) }
        return s
    }

    // A = forward, X / right-click = back one step.
    override func click(_ slot: MenuSlot, button: Int, shift: Bool) {
        guard case .button(let i) = slot.kind, let r = row(forSlot: i) else { return }
        // Mouse: clicking the "<" end of a setting steps it back, like right-click.
        var back = button == 1
        if !back && PauseMenu.valueIDs.contains(r.1) && game.input.mouseX >= 0 {
            let L = HudLayout(game.screen.x, game.screen.y).fitted(self)
            let x0 = origin(L).x + Float(slot.x) * L.s
            if game.input.mouseX < x0 + Float(slot.w) * L.s * 0.2 { back = true }
        }
        act(r.1, back: back)
    }
    override func buttonPressed(_ i: Int) { if let r = row(forSlot: i) { act(r.1, back: false) } }

    // D-pad left/right on a setting steps it; returns false when the hovered row isn't a setting.
    func adjust(_ dx: Int) -> Bool {
        guard let id = hoveredID, PauseMenu.valueIDs.contains(id) else { return false }
        act(id, back: dx < 0)
        return true
    }
    func switchTab(_ d: Int) {
        guard page == .options else { return }
        let n = Cat.allCases.count
        cat = Cat(rawValue: (cat.rawValue + d + n) % n) ?? .controller
        scroll = 0
        build()
        game.menuCursor = 0
        game.sfx(.click, 0.4)
    }
    func scrollList(_ d: Int) {
        let before = scroll
        scroll = max(0, min(rows.count - min(rows.count, PauseMenu.visible), scroll + d))
        if scroll != before { build() }
    }

    func go(_ p: Page) {
        stack.append(page)
        page = p
        scroll = 0
    }

    func act(_ id: String, back: Bool) {
        let g = game
        let st = Settings.shared
        func step<T: Equatable>(_ opts: [T], _ cur: T) -> T {
            let i = opts.firstIndex(of: cur) ?? 0
            return opts[(i + (back ? opts.count - 1 : 1)) % opts.count]
        }
        var resetCursor = false
        switch id {
        case "noop": return
        case _ where id.hasPrefix("vol:") || id == "audio_test" || id == "audio_subs": audioAct(id, back: back)
        case "resume":
            if page == .title { g.paused = false } else { g.closeMenu() }
        case "options": go(.options); resetCursor = true
        case "controls": go(.controls); resetCursor = true
        case "keys": go(.keys); binding = nil; resetCursor = true
        case "padmap": go(.padmap); padBinding = nil; resetCursor = true
        case _ where id.hasPrefix("pbind:"):
            padBinding = Int(id.dropFirst(6))
            padBindArmed = g.clock
        case "pbindreset": PadMap.reset(); g.onToast?("Buttons reset to defaults")
        case _ where id.hasPrefix("bind:"):
            binding = KeyBinds.Action(rawValue: String(id.dropFirst(5)))
        case "bindreset": KeyBinds.reset(); g.onToast?("Keys reset to defaults")
        case "worlds": go(.worlds); resetCursor = true
        case "back":
            confirmReset = false
            page = stack.popLast() ?? (page == .title ? .title : .main)
            editing = nil
            scroll = 0
            resetCursor = true
        case "create": go(.create); editing = nil; resetCursor = true
        case "newworld": g.appAction?("newworld")
        case "edit_name", "edit_seed", "edit_rename":
            editing = id == "edit_name" ? 0 : (id == "edit_seed" ? 1 : 2)
            if Prompt.pad || HudLayout.couch { g.openMenu(KeyboardMenu(game: g, target: self)) }
        case "new_mode": newSurvival.toggle()
        case "new_diff": newDifficulty = step([0, 1, 2, 3], newDifficulty)
        case "new_create":
            let name = WorldStore.unique(WorldStore.clean(newName))
            g.appAction?("create:\(newSurvival ? 1 : 0):\(newDifficulty):\(name):\(newSeed)")
        case _ where id.hasPrefix("world:"):
            selWorld = String(id.dropFirst(6))
            go(.world); resetCursor = true
        case "w_play":
            if selWorld == currentWorld { if cameFromTitle { g.paused = false } else { g.closeMenu() } }
            else { g.appAction?("play:" + selWorld) }
        case "w_rename":
            if selWorld == currentWorld { g.onToast?("Load another world before renaming this one"); break }
            renameText = selWorld
            go(.rename); resetCursor = true
            editing = 2
            if Prompt.pad || HudLayout.couch { g.openMenu(KeyboardMenu(game: g, target: self)) }
        case "w_rename_yes":
            editing = nil
            if let n = WorldStore.rename(selWorld, to: renameText) {
                selWorld = n
                worlds = WorldStore.list()
                page = stack.popLast() ?? .worlds
                g.onToast?("Renamed to \(n)")
            } else { g.onToast?("A world with that name already exists") }
            resetCursor = true
        case "w_copy":
            if selWorld == currentWorld { g.saveNow() }
            if let n = WorldStore.copy(selWorld) { g.onToast?("Copied to \(n)"); page = stack.popLast() ?? .worlds; resetCursor = true }
            else { g.onToast?("Couldn't copy the world") }
        case "w_delete":
            if selWorld == currentWorld { g.onToast?("Load another world before deleting this one"); break }
            go(.confirm); resetCursor = true
        case "w_delete_yes":
            let ok = WorldStore.delete(selWorld)
            g.onToast?(ok ? "Moved \(selWorld) to the Trash" : "Couldn't delete \(selWorld)")
            // Back to the worlds list (skip the world page).
            while let p = stack.popLast() { page = p; if p == .worlds { break } }
            if page != .worlds { page = .worlds }
            resetCursor = true
        case "totitle":
            g.saveNow()
            stack = []
            page = .title
            resetCursor = true
        case "advancements": g.closeMenu(); g.openMenu(AdvancementMenu(game: g))
        case "commands": g.closeMenu(); g.openMenu(CommandMenu(game: g))
        case "mode": g.toggleMode(); g.onModeChanged?(g.survival)
        case "difficulty": g.difficulty = step([0, 1, 2, 3], g.difficulty)
        case "fov": g.fovSetting = step([50, 60, 70, 80, 90, 100, 110], g.fovSetting)
        case "sens": g.sensitivity = step([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3], g.sensitivity)
        case "invert": g.invertY.toggle()
        case "autojump": g.autoJump.toggle()
        case "dead": g.deadZone = step([0.05, 0.1, 0.15, 0.2, 0.25, 0.3], g.deadZone)
        case "lookx": st.lookX = step([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3], st.lookX)
        case "looky": st.lookY = step([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3], st.lookY)
        case "accel": st.lookAccel = step([0, 0.25, 0.5, 0.75, 1], st.lookAccel)
        case "aim": st.aimAssist.toggle()
        case "curve": st.lookCurve = step([0, 1, 2], st.lookCurve)
        case "rumble": st.rumble = step([0, 0.35, 0.7, 1], st.rumble); PadManager.shared.rumble(0.8, 0.15)
        case "padinfo": PadManager.shared.rumble(1, 0.3)
        case "southpaw": st.southpaw.toggle()
        case "sneaktoggle": st.sneakToggle.toggle()
        case "autosprint": st.autoSprint.toggle()
        case "glyphs": st.glyphStyle = step([0, 1, 2], st.glyphStyle)
        case "rd":
            let opts = [2, 4, 6, 8, 10, 12, 16, 20, 24]
            g.world.renderDistance = step(opts, g.world.renderDistance)
            g.onRenderDistanceChanged?(g.world.renderDistance)
            UserDefaults.standard.set(g.world.renderDistance, forKey: "renderDistance")
        case "fullscreen": g.appAction?("fullscreen")
        case "launchfs": st.launchFullscreen.toggle()
        case "display":
            let list = VideoState.displays
            if list.count > 1 {
                let cur = list.firstIndex(of: VideoState.current) ?? 0
                st.display = list[(cur + (back ? list.count - 1 : 1)) % list.count]
                g.appAction?("display")
            } else { g.onToast?("Only one display is connected") }
        case "vsync": st.vsync.toggle(); g.appAction?("video")
        case "fps": st.fpsCap = step(Settings.fpsOptions, st.fpsCap); g.appAction?("video")
        case "rscale": st.renderScale = step(Settings.renderScaleOptions, st.renderScale); g.appAction?("video")
        case "gui": HudLayout.userScale = step([0, 1, 2, 3, 4, 5, 6], HudLayout.userScale)
        case "couch": HudLayout.couch.toggle()
        case "safe": st.safeArea = step([0, 2, 4, 6, 8, 10], st.safeArea)
        case "hints": st.buttonHints.toggle()
        case "textbg": st.textBackground = step([0, 0.25, 0.5, 0.75], st.textBackground)
        case "bugnotes":
            if BugNotes.denied {
                g.onToast?("Allow Microphone and Speech Recognition for Blocksmith in System Settings > Privacy & Security")
            } else if BugNotes.authorized || st.bugNotes != 0 {
                st.bugNotes = step([0, 1, 2], st.bugNotes)
                if st.bugNotes == 2 { g.onToast?("Hold F7 or click both sticks (L3 + R3) and speak") }
                if st.bugNotes == 1 { g.onToast?("Listening: just say the bug, pause to finish") }
            } else {
                let next = back ? 2 : 1
                BugNotes.requestPermission { [weak self] ok in
                    if ok { st.bugNotes = next; g.onToast?(next == 1 ? "Listening: just say the bug, pause to finish" : "Hold F7 or click both sticks (L3 + R3) and speak") }
                    else { g.onToast?("Bug Notes needs microphone and speech permission (System Settings > Privacy & Security)") }
                    self?.build()
                }
            }
        case "flashes": st.screenEffects.toggle()
        case "narrator": st.narrator.toggle(); if st.narrator { Narrator.shared.say("Narrator on", clock: g.clock) }
        case "resetask": go(.confirm); confirmReset = true; resetCursor = true
        case "reset_yes":
            st.resetAll(g)
            g.appAction?("video")
            confirmReset = false
            page = stack.popLast() ?? .options
            g.onToast?("Options reset to defaults")
            resetCursor = true
        case "crosshair": st.crosshair = step([0, 1, 2], st.crosshair)
        case "hidehud": g.hideHUD.toggle()
        case "debug": g.showDebug.toggle()
        case "subtitles": st.subtitles.toggle()
        case "colorblind": st.colorblind.toggle()
        case "tutorial": st.tutorialHints.toggle()
        case "resethints": st.tutorialStep = 0; st.tutorialHints = true; g.onToast?("Tutorial hints will show again")
        case "volume": g.volumeSetting = step([0, 0.1, 0.25, 0.5, 0.8, 1], g.volumeSetting)
        case "music": g.musicVolume = step([0, 0.25, 0.5, 0.75, 1], g.musicVolume)
        case "quit": g.appAction?("quit")
        default: g.appAction?(id)
        }
        g.sfx(.click, 0.5)
        if g.menu === self {
            let cur = g.menuCursor
            build()
            g.menuCursor = resetCursor ? 0 : min(cur, max(0, slots.count - 1))
        }
    }

    override var capturesText: Bool { ((page == .create || page == .rename) && editing != nil) || binding != nil }
    override func typed(_ str: String) {
        guard let e = editing else { return }
        for c in str {
            if c == "\u{8}" {
                if e == 0 { if !newName.isEmpty { newName.removeLast() } }
                else if e == 1 { if !newSeed.isEmpty { newSeed.removeLast() } }
                else if !renameText.isEmpty { renameText.removeLast() }
            }
            else if e == 0 { if newName.count < 32 && c != "/" && c != ":" { newName.append(c) } }
            else if e == 1 { if newSeed.count < 32 { newSeed.append(c) } }
            else if renameText.count < 32 && c != "/" && c != ":" { renameText.append(c) }
        }
        build()
    }
    override func tick() {
        if let i = padBinding {
            // The first physical button pressed after arming (not the press that armed it) takes the action.
            let pm = PadManager.shared
            if game.clock > padBindArmed, let phys = PadMap.newlyPressed(pm.lastRaw, pm.prevRaw) {
                PadMap.assign(i, phys)
                padBinding = nil
                game.sfx(.click, 0.5)
                let cur = game.menuCursor
                build()
                game.menuCursor = cur
            } else if pm.lastRaw.menu && !pm.prevRaw.menu || game.clock - padBindArmed > 8 {
                padBinding = nil
                build()
            }
            return
        }
        if let a = binding {
            // First key pressed (that isn't reserved) becomes the binding.
            if let k = game.input.pressed.first(where: { !KeyBinds.reserved.contains($0) }) {
                KeyBinds.set(a, k)
                binding = nil
                game.sfx(.click, 0.5)
                let cur = game.menuCursor
                build()
                game.menuCursor = cur
            }
            return
        }
        if page == .create || page == .rename {
            if editing != nil && game.input.tapped(Key.enter) { editing = nil }
            build()            // blinking caret
        }
        if page == .options && cat == .controller && Int(game.clock * 4) % 4 == 0 { build() }   // live controller name / battery
    }

    override func backPressed() -> Bool {
        if binding != nil { binding = nil; build(); return true }
        if padBinding != nil { padBinding = nil; build(); return true }
        if editing != nil { editing = nil; build(); return true }
        guard page != .main && page != .title else { return page == .title }
        act("back", back: false)
        return true
    }
    override func onClose() { game.paused = false }
}

// Fullscreen state mirrored from the window (AppDelegate keeps it current).
enum VideoState {
    static var fullscreen = false
    static var displays: [String] = []     // connected screens by name (AppDelegate keeps it current)
    static var current = ""                // the screen the window is on
}

// Text for the Controls Reference page.
enum ControlsReference {
    static func rows() -> [String] {
        func k(_ a: Prompt.Act) -> String { Prompt.keyGlyph(a) }
        return [
            Glyph.ls.s + " / " + k(.move) + " Move",
            Glyph.rs.s + " / mouse Look",
            PadMap.glyph(.a).s + " / " + k(.jump) + " Jump (twice: fly)",
            PadMap.glyph(.b).s + " " + PadMap.glyph(.r3).s + " / " + Glyphs.key("Shift") + " Sneak",
            PadMap.glyph(.l3).s + " / " + Glyphs.key("Ctrl") + " Sprint",
            Glyph.rt.s + " / " + Glyph.mouseL.s + " Attack, mine",
            Glyph.lt.s + " / " + Glyph.mouseR.s + " Use, place, eat",
            PadMap.glyph(.lb).s + PadMap.glyph(.rb).s + " / " + Glyphs.key("1-9") + " Hotbar",
            PadMap.glyph(.y).s + " / " + k(.inventory) + " Inventory",
            PadMap.glyph(.x).s + " / " + Glyph.mouseM.s + " Pick block",
            PadMap.glyph(.ddown).s + " / " + k(.drop) + " Drop (hold: stack)",
            PadMap.glyph(.dright).s + " / " + k(.offhand) + " Swap off hand",
            PadMap.glyph(.dleft).s + " / " + k(.chat) + " Commands",
            PadMap.glyph(.dup).s + " / " + k(.fly) + " Fly (creative)",
            PadMap.glyph(.view).s + " / " + k(.camera) + " Camera",
            Glyph.menu.s + " / " + Glyphs.key("Esc") + " Pause",
            Glyph.share.s + " / " + Glyphs.key("F2") + " Screenshot",
        ]
    }
}
