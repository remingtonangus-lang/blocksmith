import Foundation

// Title screen, pause menu, options (six pages switched with LB/RB), worlds list (play / rename / copy /
// delete with confirmation) and world creation. Drawn with the HUD so a controller drives everything:
// D-pad / stick to move, A to choose or step a setting forward, X (or D-pad left/right) to step it,
// B to go back. The list scrolls when it is longer than the panel.
final class PauseMenu: Menu {
    // Controller option steps (Halo Infinite-style scales: sensitivity 1-10, dead zones in percent).
    static let sens: [Float] = [1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 6, 7, 8, 9, 10]
    static let zones: [Float] = [0, 0.02, 0.04, 0.06, 0.08, 0.1, 0.12, 0.15, 0.2, 0.25]
    static let outers: [Float] = [0, 0.02, 0.05, 0.08, 0.1, 0.15, 0.2]
    enum Page { case title, main, options, controls, keys, padmap, worlds, world, confirm, create, rename, shortcuts, net, stats, checklist, compute, messages }
    enum Cat: Int, CaseIterable {
        // Video first: render distance and graphics are what players look for (Remington, playtest 2: "no render
        // distance setting" - it sat on page 3 behind the input pages).
        case video, controls, controller, audio, interface, accessibility, director
        var name: String { ["Video", "Keyboard & Mouse", "Controller", "Audio", "Interface", "Accessibility", "Director"][rawValue] }
    }
    var page: Page = .main
    var cat: Cat = .video
    var stack: [Page] = []
    // (label, action id); settings show their current value in the label.
    var rows: [(String, String)] = []
    var scroll = 0
    static let visible = 10          // the main page has ten rows (at 9 the last leave row hid below a scrollbar: blind UI critic)
    var subtitle = ""                // small line under the title (page hint, confirmation text)
    var cameFromTitle: Bool { stack.first == .title || page == .title }
    // Create World page (controller-friendly: the text fields use the on-screen keyboard).
    var newName = "New World"
    var newSeed = ""
    var newSurvival = true
    var newDifficulty = 3                           // P302: a level (0 Peaceful ... 3 Normal ... 5 Very Hard)
    var newSmooth = true                            // Q2: every new world is the polygon world (PG6; no block option)
    var editing: Int? = nil        // 0 name, 1 seed, 2 rename, 3 host address
    private var slotsKept: [MenuSlot] = []   // the last layout's buttons (P201)
    var netAddr = ""                // C14 Play Together: a host typed by address
    static var found: [(ip: String, port: UInt16, world: String)] = []
    static var searching = false
    static let foundLock = NSLock()
    var selWorld = ""              // world picked on the worlds page
    var renameText = ""
    var worlds: [WorldStore.Info] = []
    var confirmReset = false              // the confirm page is asking about options, not a world
    var confirmMode = false               // Q2c-console-5: ... or about switching the game mode
    var confirmQuit = false               // Q2c-console-54: ... or about quitting the game
    var confirmAt: Double = 0             // wall clock when that page opened (a pull in the first 0.4 s doesn't quit)
    var padBinding: Int? = nil             // Button Mapping: logical button waiting for a physical press
    var padBindArmed: Double = 0
    var binding: KeyBinds.Action? = nil   // waiting for a key press on the Key Bindings page
    // Host pages (the Quest's VR comfort options; nil on the Mac): an entry row on the main page opens a page whose
    // rows come from the host and whose actions go back to it. Ids in `hostValues` step left / right like settings.
    static var hostEntry: (String, String)?
    static var hostPage: ((String) -> (title: String, subtitle: String, rows: [(String, String)])?)?
    static var hostAct: ((String, Bool) -> Void)?
    static var hostValues: Set<String> = []
    static var hostHelp: [String: String] = [:]
    // Q2c-console-44: why the host paused the game by itself (the headset: away, tracking lost, controllers put down);
    // the pause screen's subtitle until he resumes (Game.paused clears it).
    static var autoReason: String?
    // Q2c-console-10: the one-time notes and the button prompts (Accessibility). P300: the tips and lessons are gone.
    // P328 (NO TEXT): the prompts and notes are gone over play too; what is left to reset is the goals.
    static func resetHints(_ g: Game) {
        let st = Settings.shared
        st.tutorialStep = 0; st.tutorialHints = true; st.hintSeconds = 0
        st.wreckHint = false; st.mastHint = false; st.chestJoinTold = false
        g.journalTold = false
        g.onToast?("Goals reset")
    }
    // Q2: the Track a Target row names what is followed now.
    static func trackLabel(_ g: Game) -> String {
        guard let t = Waymarks.current(g) else { return "Track a Target..." }
        let name = t.name.split(separator: ":").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? t.name
        return "Track a Target (\(name.count > 22 ? String(name.prefix(21)) + "." : name))..."
    }
    static var hostHidden: Set<String> = []     // rows the host has no use for (the Quest: window and photo options)
    // Q2c-console-1: option pages the host has no use for (the Quest: Keyboard & Mouse) and pages it names its own way
    // (the Quest: Touch Controls).
    static var hostHiddenCats: Set<Cat> = []
    static var savedNote: String?                 // Q2c-console-2: the title screen's "World1 saved" after Save and Quit
    static var hostVideoRows: (() -> [(String, String)])?   // Q2c-console-26: the host's own rows on the Video page
    static var hostCatNames: [Cat: String] = [:]
    static var shownCats: [Cat] { Cat.allCases.filter { !hostHiddenCats.contains($0) } }
    static func catName(_ c: Cat) -> String { hostCatNames[c] ?? c.name }
    var hostPageID: String?

    init(game: Game) {
        super.init("Game Paused", game: game)
        showInventoryLabel = false
        build()
    }

    var currentWorld: String { game.save?.dir.lastPathComponent ?? "" }

    // P339: the view distance (everything drawn) and the active distance (where things move and think); while Auto
    // holds the active distance below the player's choice, the current one too.
    static var viewFixed = false                    // the headset: the view distance is fixed (QuestSettings.viewDistance)
    static func rdLabel(_ g: Game) -> String { "Render Distance: \(g.chosenRenderDistance)" }
    // P440 (Oct 24 20:49, "Active distance slider is doing nothing"): the active distance never passes the view distance,
    // so at view 8 its row stepped to 10 and was put straight back to 8. It now steps the player's choice (kept), and
    // says when the view distance holds it lower.
    static func activeChoice(_ g: Game) -> Int { max(g.chosenActiveDistance, Game.savedActiveDistance) }
    static func adLabel(_ g: Game) -> String {
        let c = activeChoice(g), w = g.world.activeDistance
        if w < c && w >= g.world.renderDistance { return "Active Distance: \(c) (\(w) now: view distance)" }
        return w < c ? "Active Distance: \(c) (auto \(w) now)" : "Active Distance: \(c)"
    }
    // P440: on the headset the pause menu's distance row is the view distance (what loads and is drawn) when the host
    // gives one; the active distance stays on the Video page.
    static var hostViewRow: ((Game) -> (String, String))?
    static var distanceID: String { viewFixed ? (hostViewRow != nil ? "q_view" : "ad") : "rd" }
    static func distanceRow(_ g: Game) -> (String, String) {
        if viewFixed, let r = hostViewRow?(g) { return r }
        return viewFixed ? (adLabel(g), "ad") : (rdLabel(g), "rd")
    }
    static func brightnessName(_ b: Float) -> String {
        b <= 0.01 ? "Moody" : (abs(b - 0.5) < 0.01 ? "Default" : (b >= 0.99 ? "Bright" : "\(Int((b * 100).rounded()))%"))
    }
    static let valueIDs: Set<String> = ["sens", "invert", "autojump", "fov", "lookx", "looky", "accel", "dead", "aim", "rumble", "southpaw",
                                        "sneaktoggle", "autosprint", "glyphs", "rd", "ad", "chipping", "smooth", "new_terrain", "fullscreen", "launchfs", "vsync", "fps", "rscale", "wscale", "graphics",
                                        "gui", "couch", "safe", "hints", "textbg", "volume", "music", "subtitles", "colorblind", "tutorial",
                                        "mode", "difficulty", "new_mode", "new_diff", "hidehud", "debug", "crosshair", "flashes", "curve", "narrator", "display", "bugnotes", "flight", "minimap", "splitlayout", "brightness",
                                        "dir_on", "dir_backend", "dir_freq", "dir_early", "devtools"]

    static func isValue(_ id: String) -> Bool {
        valueIDs.contains(id) || id.hasPrefix("vol:") || id.hasPrefix("fx") || id == "audio_subs" || ["audio_music_src", "audio_music_shuffle", "audio_music_vol", "audio_music_titles"].contains(id)
            || hostValues.contains(id) || id.hasPrefix("cl:") || id == "cl_view" || id == "cl_sw"     // P399
    }

    static let help: [String: String] = [
        "resume": "Return to the game.",
        "worlds": "Play, create, rename, copy or delete worlds.",
        "options": "Controls, controller, video, audio, interface and accessibility.",
        "sens": "How fast the mouse turns the view.",
        "lookx": "How fast the right stick turns left and right.",
        "looky": "How fast the right stick looks up and down.",
        "accel": "Turns faster the longer the right stick is held at its edge.",
        "curve": "Default eases in like a shooter (fine aim near the centre), Linear follows the stick exactly, Precise is slower still near the centre.",
        "dead": "Move stick: movement ignored around the centre. Raise it if you creep without touching the stick.",
        "lookdead": "Look stick: movement ignored around the centre. Raise it if the view drifts.",
        "lookouter": "Look stick: how far before the edge the stick already counts as fully pushed.",
        "moveouter": "Move stick: how far before the edge the stick already counts as fully pushed.",
        "aim": "Controller only: the view slows over hostile mobs and while mining.",
        "rumble": "How strongly the controllers vibrate: when you are hit, mine, attack, draw a bow, run low on health or something explodes, and in menus. Off stops it all.",
        "southpaw": "Southpaw swaps the sticks: look with the left, move with the right.",
        "sneaktoggle": "Toggle: press B / right stick once to crouch, again to stand.",
        "splitlayout": "How the screen divides for two players: top and bottom (wide views) or side by side (menus stay bigger on a TV).",
        "looknames": "Rest your aim on a block or creature for a moment to see its name (and, for a block, the tool it needs).",
        "targetbar": "After you hit a creature, its name and health show at the top of the view for a few seconds.",
        "minimap": "A small biome map in the corner with nearby bases and villages. M or hold View for the full map.",
        "brightness": "How much you see without light: Moody keeps caves near black, Bright lifts every shadow. Torches stay brighter either way.",
        "fov": "How wide the view is. Wider shows more at the sides; narrower looks closer.",
        "invert": "Moving the mouse or stick up looks down.",
        "autojump": "Walk into a one-block step to climb it without jumping.",
        "advancements": "Goals you have reached and the ones still ahead.",
        "stats": "What you have done in this world: time, distance, mining, building, fighting, crafting.",
        "messages": "The last 50 messages shown on screen, newest first, with the day and time.",
        "compute": "What each part of the game costs a frame where you stand (playtest builds): drawing by system, the game tick, the GPU.",
        "commands": "Type a command (time, weather, teleport, give...).",
        "new_mode": "Survival: health, hunger, mining. Creative: fly and build freely. You can switch later from the pause menu.",
        "new_diff": "How much damage mobs do and whether hunger can kill.",
        "edit_name": "The name shown in the worlds list.",
        "edit_seed": "Leave empty for a random world; the same seed always makes the same world.",
        "coop": "Split screen: a second controller joins (or press Menu on it while playing); player 2 leaves from their pause menu.",
        "netmenu": "Play together over Wi-Fi: host this world for a friend, or join theirs.",
        "photo": "A free camera with the HUD hidden: keyframe paths and depth of field (F6).",
        "worldmap": "Biomes around you and the Capital citadels and villages you have found.",
        "flight": "Aircraft pitch on the left stick: pull back to climb (like a plane) or push up to climb.",
        "autosprint": "Push the left stick fully forward for a moment to sprint.",
        "glyphs": "Which buttons prompts show. Auto follows the last device you touched.",
        "padinfo": "Press A to test vibration.",
        "rd": "How many chunks around you are drawn. Lower is smoother.",
        "ad": "How many chunks around you are alive: creatures, crops and machines. Lower is smoother.",
        "fullscreen": "Switch between a window and the full screen.",
        "display": "Which screen to play on when the Mac is connected to a TV. Remembered for next time.",
        "launchfs": "Open Sunderfall straight into full screen, ready for the TV.",
        "vsync": "Sync frames to the display. Off can lower input lag but may tear.",
        "fps": "Frame rate cap. 30 or 60 keeps a laptop cooler.",
        "smooth": "This world was made with block terrain. On: its natural ground becomes the smooth polygon world, as every new world is.",
        "new_terrain": "Polygons: the natural ground is one smooth surface you dig, blast and build on, instead of cubes. Kept for the life of the world.",
        "chipping": "On: mining and blasts break pieces off a block until it gives way. Off: the classic cracks.",
        "fx1": "Headset: leaves, vines and crops sway in the wind.", "fx2": "Headset: low mist settles in valleys at dawn, dusk and night.",
        "fx4": "Headset: a soft glow round torches, lamps, lava and glowing ores.", "fx8": "Headset: colours warm at sunrise and sunset, cool at night, and follow the biome.",
        "fx16": "Headset: metal, ice and wet surfaces catch the sun.",
        "graphics": "Fancy: sky gradient, water reflections, shadows and more effects. Fast: the plain renderer.",
        "wscale": "Fancy graphics only: draws the world at fewer pixels and scales it up; menus and the HUD stay sharp.",
        "rscale": "Renders fewer pixels and scales up. 75% helps a lot on a 4K TV.",
        "gui": "Size of menus and the HUD. Auto picks the largest that fits.",
        "couch": "Bigger HUD and menus for playing from the sofa.",
        "safe": "Keeps the HUD away from the screen edges on TVs that crop them.",
        "hints": "Control legends under menus.",
        "textbg": "Dark boxes behind HUD text for readability.",
        "subtitles": "Shows captions for sounds, with the direction they come from.",
        "colorblind": "Uses blue and orange instead of green and red for cues.",
        "tutorial": "Names the next goal on the inventory screen.",
        "resethints": "Starts the goals again from the first one.",
        "controls": "Every control for keyboard, mouse and controller.",
        "keys": "Choose which keys walk, jump, open the inventory and more.",
        "about": "Who made Sunderfall, and the open source parts it is built on with their licences.",
        "padmap": "Move actions to other controller buttons. Prompts follow your layout.",
        "pbindreset": "Put every controller button back to the standard layout.",
        "playout": "Shooter: Y switches to your last hotbar slot, hold Y for the inventory. Classic: Y opens the inventory.",
        "bindreset": "Put every key back to the default layout.",
        "volume": "Overall sound volume.",
        "audio_subs": "Shows captions for sounds, with the direction they come from (same as Accessibility > Subtitles).",
        "audio_test": "Plays a sound in front of you at the current volumes.",
        "audio_music_src": "Built-in: the game's own music. My Music: your files from ~/Library/Application Support/Blocksmith/Music. Mixed: they take turns.",
        "audio_music_folder": "Audio files (mp3, m4a, wav, aiff) in ~/Library/Application Support/Blocksmith/Music. Select to look again after adding some.",
        "audio_music_shuffle": "Plays your music in a random order (off: by file name).",
        "audio_music_titles": "Shows each new piece's title for a few seconds in the bottom-left corner of the view.",
        "audio_music_vol": "How loud your own music plays, on top of the Music volume.",
        "audio_music_skip": "Ends the piece that is playing and starts the next. Also Y on the pause menu, or the Skip Music Track key (N).",
        "music": "Background music volume.",
        "mode": "Survival: health, hunger, mining. Creative: fly and build freely.",
        "difficulty": "Set when the world was made: how hard blows land, how much armour helps, enemy speed, aim and numbers, and hunger.",
        "crosshair": "Bold is thicker with a dark edge, easy to see on a TV. Dot is a small square.",
        "narrator": "Reads the highlighted menu item and messages aloud with the system voice.",
        "dir_on": "After the story the Director keeps the land alive: raids, outlaws, wrecks, storms, traders, announced by radio and marked on your map.",
        "dir_backend": "Who plans the events. Built-in Rules always work. On-Device AI: a small model on this device that thinks only while you are paused. Cloud AI: a server; only a summary of the world is sent.",
        "dir_freq": "How much play time passes between events.",
        "dir_early": "Lets the Director start before the story is finished (for trying it out).",
        "dir_cloud": "For testing (Cheats & Shortcuts): the Cloud AI's server. Test: a built-in stand-in that uses no network.",
        // Q2c-console-6: rows that had no help.
        "journal": "Every order, log, note, pamphlet, message and Director event you have received, to read again.",
        "shortcuts": "Teleport to the nearest place of a kind (testing).",
        "restorebackup": "The game closed unexpectedly: put back the newest rolling backup of this world.",
        "new_create": "Make the world with these settings and start playing.",
        "reset_yes": "Yes: every option and key binding back to its default.",
        "w_rename_yes": "Give the world the name above.",
        "w_delete_yes": "Yes, delete this world.",
        "mode_yes": "Yes, switch the game mode now.",
        "net_host": "Let a friend on the same network join this world.",
        "net_stop": "Stop letting others join (anyone here is sent home).",
        "net_leave": "Leave the host's world and go back to your own.",
        "net_addr": "Join the world at the address typed above.",
        "dir_journal": "Every Director event, under way and finished, with its outcome: the journal's Events shelf.",
        "bugnotes": BugNotes.hint,
        "flashes": "Reduced makes the red damage flash and portal tint faint.",
        "resetask": "Put every option and key binding back to its default.",
        "hidehud": "Hide the hotbar and crosshair (screenshots). F1 on the keyboard.",
        "debug": "Shows your position, the biome, the frame rate and chunk details in the corner (F3 on the keyboard).",
        "devtools": "Shows Commands (time, weather, items, mode) and Shortcuts (teleport) in the pause menu in survival. Creative always has them.",
        "perf": "Frame rate, frame times (average and worst of the last second), render distance and chunk jobs in the corner of the view.",
        "quit": "Save the world and close Sunderfall (asks first).",
        "quit_yes": "Saves your world, then closes Sunderfall.",
        "totitle": "Save the world and return to the title screen.",
        "create": "Choose a name, seed, game mode and difficulty.",
        "newworld": "Start a new world with a random seed straight away.",
        "workshop": "A creative test world with the standard circuits built and signed: clocks, a toggle, a piston door, a sorter.",
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
        func num(_ f: Float) -> String { f == f.rounded() ? "\(Int(f))" : String(format: "%.1f", f) }
        subtitle = ""
        if let hp = hostPageID, let r = PauseMenu.hostPage?(hp) {
            title = r.title; subtitle = r.subtitle
            // (A page that ends in its own finishing row, the Quest's first-launch setup, has no extra Done.)
            rows = r.rows + (r.rows.last?.1.hasSuffix("_done") == true ? [] : [("Done", "back")])
            layout()
            return
        }
        switch page {
        case .title:
            title = ""
            if let n = PauseMenu.savedNote { subtitle = n }                 // Q2c-console-2: "World1 saved"
            let last = UserDefaults.standard.string(forKey: "lastWorld") ?? "World1"
            // Q2c-console-32: what Play continues (the world loaded behind the title), comfort first on the headset.
            let day = Int(g.time / DAY_LENGTH) + 1
            let played = day > 1 || g.time > DAY_LENGTH * 0.1
            let play = played ? "Continue: \(last) (\(g.survival ? "Survival" : "Creative"), day \(day))" : "Play: \(last)"
            rows = [(play, "resume"), ("Worlds...", "worlds"), ("Options...", "options"), ("Quit Game", "quit")]
            if let e = PauseMenu.hostEntry { rows.insert(e, at: 1) }
            if PauseMenu.savedNote == nil {
                subtitle = "\(Difficulty.name(g.diffLevel)), \(g.smoothTerrain ? "polygon" : "block") terrain"
            }
        case .main:
            title = "Game Paused"
            if let t = PadManager.shared.disconnectedAt, g.clock - t < 600, !PadManager.shared.connected {
                subtitle = "Controller disconnected - reconnect it or use the keyboard"
            } else if let r = PauseMenu.autoReason {
                subtitle = r
            } else if !currentWorld.isEmpty {
                subtitle = "\(currentWorld) - day \(Int(g.time / DAY_LENGTH) + 1) - \(Difficulty.name(g.diffLevel))"
                    + (SaveBadge.savedAgo(g).map { " - " + $0 } ?? "")   // Q2c-console-2, -16
                    + (StorageCheck.low ? " - storage low" : "")         // Q2c-console-51
            }
            rows = [("Back to Game", "resume"), ("Options...", "options"), PauseMenu.distanceRow(g), ("World Map", "worldmap"), (PauseMenu.trackLabel(g), "track"), ("Advancements", "advancements"), ("Statistics", "stats"), ("Messages", "messages"), ("Commands...", "commands"), ("Shortcuts...", "shortcuts"),
                    ("Mode: \(g.survival ? "Survival" : "Creative")", "mode"),
                    ("Difficulty: \(Difficulty.name(g.diffLevel))", "difficulty"),   // P369: changeable for the life of the world
                    ("Worlds...", "worlds"), ("Photo Mode", "photo"), (g.coop.active ? "End Split Screen" : "Split Screen (2 players)", "coop"),
                    ("Play Together...", "netmenu"),
                    ("Save and Quit", "totitle")]   // P330: one leave row (the title screen has Quit Game)
            if g.coop.current > 0 {
                // Player 2's pause menu: their own screens, and leaving (the world itself belongs to player 1).
                subtitle = "Player 2"
                rows = [("Back to Game", "resume"), ("World Map", "worldmap"), (PauseMenu.trackLabel(g), "track"), ("Advancements", "advancements"), ("Leave Split Screen", "coop")]
            } else if g.coop.active {
                rows.removeAll { $0.1 == "photo" || $0.1 == "worlds" }
            }
            if let e = PauseMenu.hostEntry, g.coop.current == 0 { rows.insert(e, at: 2) }
            if !g.cheatsAllowed { rows.removeAll { $0.1 == "commands" || $0.1 == "shortcuts" } }    // Q2c-console-15
            // P399: the device checklist, playtest builds only (above Shortcuts; the store build has no row).
            if Playtest.enabled && g.coop.current == 0, let at = rows.firstIndex(where: { $0.1 == "shortcuts" || $0.1 == "mode" }) {
                rows.insert(("Playtest Checklist...", "checklist"), at: at)
                rows.insert(("What Is Using the Compute", "compute"), at: at + 1)   // P420
            }
            // S4: after a crash, the newest rolling backup of this world can be put back.
            if CrashGuard.crashed && g.coop.current == 0 { rows.insert(("Restore Last Backup (after a crash)", "restorebackup"), at: 1) }
        case .options:
            // Q2c-console-1: the host's own page list (the Quest leaves out Keyboard & Mouse) and page names.
            let shown = PauseMenu.shownCats
            if !shown.contains(cat) { cat = shown.first ?? .video }
            let at = shown.firstIndex(of: cat) ?? 0
            let next = shown[(at + 1) % shown.count]
            title = "Options: \(PauseMenu.catName(cat))"
            subtitle = "Page \(at + 1) of \(shown.count) - next page: \(PauseMenu.catName(next))"
            let gui = HudLayout.userScale == 0 ? "Auto" : "\(HudLayout.userScale)"
            switch cat {
            case .controls:
                rows = [("Mouse Sensitivity: \(pct(g.sensitivity))", "sens"), ("Invert Y: \(on(g.invertY))", "invert"),
                        ("Auto-Jump: \(on(g.autoJump))", "autojump"), ("Field of View: \(Int(g.fovSetting))", "fov"),
                        ("Key Bindings...", "keys"), ("Controls Reference...", "controls"), ("Reset Goals", "resethints")]
            case .controller:
                let pm = PadManager.shared
                let info = pm.connected ? pm.name + (pm.battery.map { " (\(Int($0 * 100))%)" } ?? "") : "No controller"
                rows = [("\(info)", "padinfo"),
                        ("Look Sensitivity Horizontal: \(num(st.lookX))", "lookx"), ("Look Sensitivity Vertical: \(num(st.lookY))", "looky"),
                        ("Look Acceleration: \(st.lookAccel == 0 ? "Off" : num(st.lookAccel))", "accel"),
                        ("Look Response: \(["Default", "Linear", "Precise"][max(0, min(2, st.lookCurve))])", "curve"),
                        ("Invert Y: \(on(g.invertY))", "invert"),
                        ("Look Center Dead Zone: \(pct(st.lookDead))", "lookdead"), ("Look Max Input Threshold: \(pct(st.lookOuter))", "lookouter"),
                        ("Move Center Dead Zone: \(pct(g.deadZone))", "dead"), ("Move Max Input Threshold: \(pct(st.moveOuter))", "moveouter"),
                        ("Aim Assist: \(on(st.aimAssist))", "aim"), ("Vibration: \(st.rumble == 0 ? "Off" : pct(st.rumble))", "rumble"),
                        ("Stick Layout: \(st.southpaw ? "Southpaw" : "Standard")", "southpaw"),
                        ("Sneak: \(st.sneakToggle ? "Toggle" : "Hold")", "sneaktoggle"), ("Auto-Sprint: \(on(st.autoSprint))", "autosprint"),
                        ("Flight Stick: \(st.flightInverted ? "Pull Back to Climb" : "Push Up to Climb")", "flight"),
                        ("Auto-Jump: \(on(g.autoJump))", "autojump"),                     // Q2c-console-1
                        ("Button Prompts: \(["Auto", "Controller", "Keyboard"][max(0, min(2, st.glyphStyle))])", "glyphs"),
                        ("Button Mapping...", "padmap")]
            case .video:
                // (P84: the polygon terrain option second from the top, named the way players ask for it; it sat last
                // as "Smooth Terrain (Test, This World)" and Remington never found it.)
                rows = (PauseMenu.viewFixed ? [] : [(PauseMenu.rdLabel(g), "rd")]) + [(PauseMenu.adLabel(g), "ad"), ("Polygon Terrain (This World): \(on(g.smoothTerrain))", "smooth"),   // (old block worlds only, below)
                        ("Graphics: \(g.fancyGraphics ? "Fancy" : "Fast")", "graphics"),
                        ("Fullscreen: \(on(VideoState.fullscreen))", "fullscreen"),
                        ("Display: \(VideoState.current.isEmpty ? "Main" : VideoState.current)", "display"),
                        ("Start in Fullscreen: \(on(st.launchFullscreen))", "launchfs"), ("VSync: \(on(st.vsync))", "vsync"),
                        ("Max Frame Rate: \(st.fpsCap == 0 ? "Display" : "\(st.fpsCap)")", "fps"),
                        ("Resolution: \(pct(st.renderScale))", "rscale"), ("World Scale (Fancy): \(pct(g.renderScale))", "wscale"),
                        ("Brightness: \(PauseMenu.brightnessName(st.brightness))", "brightness"),
                        ("Field of View: \(Int(g.fovSetting))", "fov"), ("GUI Scale: \(gui)", "gui"),
                        ("Block Chipping: \(on(st.chipping))", "chipping")]
                rows += PauseMenu.hostVideoRows?() ?? []                                              // Q2c-console-26
                rows += ShaderFX.names.map { ("\($0.1): \(on(ShaderFX.on($0.0)))", "fx\($0.0)") }      // SH1 (headset shaders)
            case .audio:
                // One slider per sound category, subtitles and a test sound (AudioMenu.swift); its own Done row is ours.
                rows = audioRows().filter { $0.1 != "audio_back" }
            case .interface:
                rows = [("GUI Scale: \(gui)", "gui"), ("Couch Mode (TV): \(on(HudLayout.couch))", "couch"),
                        ("Safe Area: \(st.safeArea)%", "safe"), ("Button Hints: \(on(st.buttonHints))", "hints"),
                        ("Text Background: \(st.textBackground == 0 ? "Off" : pct(st.textBackground))", "textbg"),
                        ("Crosshair: \(["Classic", "Bold", "Dot"][max(0, min(2, st.crosshair))])", "crosshair"),
                        ("Minimap: \(on(st.minimap))", "minimap"),
                        ("Target Health Bar: \(on(st.targetBar))", "targetbar"),                                  // Q2c-console-52
                        ("Look-at Names: \(on(st.lookNames))", "looknames"),                                      // Q2c-console-55
                        ("Split Screen: \(st.splitSideBySide ? "Side by Side" : "Top / Bottom")", "splitlayout"),
                        ("Hide HUD: \(on(g.hideHUD))", "hidehud"), ("Coordinates & Details: \(on(g.showDebug))", "debug"),
                        ("Performance Overlay: \(on(st.perfOverlay))", "perf"),
                        ("Cheats & Shortcuts: \(on(st.devTools))", "devtools"),          // Q2c-console-15
                        ("About and Licences...", "about"), ("Reset Options...", "resetask")]
                if BugNotes.available {
                    rows.insert(("Bug Notes: " + (BugNotes.denied ? "No mic access" : BugNotes.names[max(0, min(2, st.bugNotes))]), "bugnotes"), at: rows.count - 1)
                    if BugNotes.hasVideo { rows.insert(("Bug Note Video: \(on(st.bugNoteVideo))", "bugvideo"), at: rows.count - 1) }   // P368
                }
            case .accessibility:
                rows = [("Subtitles: \(on(st.subtitles))", "subtitles"), ("Narrator: \(on(st.narrator))", "narrator"),
                        ("Colorblind-Safe Colors: \(on(st.colorblind))", "colorblind"),
                        ("Text Background: \(st.textBackground == 0 ? "Off" : pct(st.textBackground))", "textbg"),
                        ("Goals: \(on(st.tutorialHints))", "tutorial"), ("Reset Goals", "resethints"),
                        ("Flashes & Shake: \(st.screenEffects ? "Full" : "Reduced")", "flashes"),
                        ("Crosshair: \(["Classic", "Bold", "Dot"][max(0, min(2, st.crosshair))])", "crosshair"),
                        ("Button Prompts: \(["Auto", "Controller", "Keyboard"][max(0, min(2, st.glyphStyle))])", "glyphs"),
                        ("Vibration: \(st.rumble == 0 ? "Off" : pct(st.rumble))", "rumble")]
            case .director:
                // P266 (h, n): the Director's switches, and what it is doing now (the hover help says it in full).
                rows = [("Director: \(on(st.directorOn))", "dir_on"),
                        ("Planner: \(Director.backendNames[Director.effectiveBackend])", "dir_backend"),
                        ("Event Frequency: \(Director.freqNames[max(0, min(2, st.directorFreq))])", "dir_freq"),
                        ("Before the Story Ends: \(on(st.directorEarly))", "dir_early"),       // (Q2c-console-16: testing; below)
                        (Director.shortStatus(g), "dir_status"), (Director.shortPlanner(), "dir_model"),
                        ("Cloud Server: \(DirectorPlanner.shared.cloud.endpoint == "mock" ? "Test (built in)" : "Custom")", "dir_cloud"),
                        ("Director Events (Journal)...", "dir_journal")]
                if !st.devTools && !st.directorEarly { rows.removeAll { $0.1 == "dir_early" } }     // Q2c-console-16
                // Q2c-console-45: only planners that can work here; the cloud's server is a testing row.
                if Director.plannerChoices().count < 2 { rows.removeAll { $0.1 == "dir_backend" || $0.1 == "dir_model" } }
                if !st.devTools { rows.removeAll { $0.1 == "dir_cloud" } }
            }
            rows.append(("Done", "back"))
        case .padmap:
            title = "Button Mapping"
            subtitle = padBinding.map { "Press the button for \(PadMap.actions[$0]) (Menu cancels)" } ?? "Pick an action, then press its new button"
            rows = (0..<PadMap.count).map { i in
                ("\(PadMap.actions[i]): " + (padBinding == i ? "> ? <" : PadMap.names[PadMap.map[i]]), "pbind:\(i)")
            } + [("Layout: \(PadMap.layoutName)", "playout"), ("Reset to Defaults", "pbindreset"), ("Done", "back")]
        case .keys:
            title = "Key Bindings"
            subtitle = binding == nil ? "Shift sneaks and Ctrl sprints on every layout" : "Press a key for \(binding!.title) (Esc cancels)"
            rows = KeyBinds.Action.allCases.map { a in
                ("\(a.title): " + (binding == a ? "> ? <" : KeyBinds.name(KeyBinds.key(a))), "bind:" + a.rawValue)
            } + [("Reset to Defaults", "bindreset"), ("Done", "back")]
        case .controls:
            title = "Controls"
            rows = ControlsReference.rows().map { ($0, "noop") } + [("Done", "back")]
        case .stats:                                                    // Q2c-console-57 (Stats.swift)
            title = "Statistics"
            subtitle = currentWorld.isEmpty ? "This world" : currentWorld
            rows = Stats.rows(g).map { ($0, "noop") } + [("Back", "back")]
        case .messages:                                                 // P421: the last 50 on-screen messages
            title = "Messages"
            let msgs = g.journal.filter { $0.pages == nil }.suffix(50).reversed()
            subtitle = msgs.isEmpty ? "No messages yet" : "The last \(msgs.count), newest first"
            rows = []
            for e in msgs {
                let stamp = String(format: "Day %d %02d:%02d  ", e.day, e.hour, e.minute)
                for (i, l) in Journal.wrap(stamp + e.text, width: style.width - 24).enumerated() { rows.append(((i > 0 ? "    " : "") + l, "noop")) }
            }
            rows += [("Open Journal...", "journal"), ("Back", "back")]
        case .compute:                                                  // P420 (ComputeCost.swift)
            title = "What Is Using the Compute"
            let c = ComputeCost.rows(g)
            subtitle = c.0
            rows = c.1.map { ($0, "noop") } + [("Back", "back")]
        case .checklist:                                                // P399 (PlaytestChecklist.swift)
            title = "Playtest Checklist"
            let c = PlaytestChecklist.rows(g, width: style.width)
            subtitle = c.subtitle
            rows = c.rows
        case .shortcuts:
            title = "Shortcuts"
            subtitle = "Teleport to the nearest one"
            rows = Game.shortcutList.map { ($0.1, "sc:" + $0.0) } + [("Back to Spawn", "sc:spawn"), ("Back", "back")]
        case .worlds:
            title = "Worlds"
            if StorageCheck.low { subtitle = "Storage almost full: \(StorageCheck.freeMB) MB free" }      // Q2c-console-51
            worlds = WorldStore.list()
            rows = [("Create New World...", "create"), ("Quick New World (random seed)", "newworld"),
                    ("Sparkstone Workshop (circuits)", "workshop")].filter { $0.1 != "workshop" || st.devTools }   // Q2c-console-25
                + worlds.map { (WorldStore.rowLabel($0, open: $0.name == currentWorld), "world:" + $0.name) }   // Q2c-console-8
                + [("Back", "back")]
        case .world:
            title = selWorld
            let info = worlds.first { $0.name == selWorld }
            subtitle = info.map { WorldStore.describe($0) } ?? ""
            rows = [(selWorld == currentWorld ? "Continue" : "Play", "w_play"), ("Rename...", "w_rename"), ("Copy", "w_copy"),
                    ("Delete...", "w_delete"), ("Back", "back")]
        case .confirm where confirmMode:
            // Q2c-console-5: a stray click on the Mode row no longer flips the world's mode.
            title = g.survival ? "Switch to Creative?" : "Switch to Survival?"
            subtitle = g.survival ? "No damage or hunger, fly freely, every block to hand. You can switch back here."
                                  : "Health, hunger and gathering again. You can switch back here."
            rows = [("Cancel", "back"), (g.survival ? "Switch to Creative" : "Switch to Survival", "mode_yes")]
        case .confirm where confirmQuit:
            // Q2c-console-54: one stray pull no longer closes the app.
            title = "Quit Sunderfall?"
            subtitle = "Your world is saved first and waits on the title screen next time."
            rows = [("Cancel", "back"), ("Save and Quit", "quit_yes")]
        case .confirm where confirmReset:
            title = "Reset Options?"
            subtitle = "Every option and key binding goes back to its default."
            rows = [("Cancel", "back"), ("Reset", "reset_yes")]
        case .confirm:
            title = "Delete World?"
            // Q2c-console-5: the headset has no Trash: a deleted world is gone for good.
            subtitle = WorldStore.useTrash ? "\"\(selWorld)\" will be moved to the Trash." : "\"\(selWorld)\" will be deleted for good: this can't be undone."
            rows = [("Cancel", "back"), ("Delete", "w_delete_yes")]
        case .rename:
            title = "Rename World"
            let caret = Int(g.clock * 2) % 2 == 0 ? "_" : " "
            rows = [("Name: \(renameText)\(editing == 2 ? caret : "")", "edit_rename"), ("Save", "w_rename_yes"), ("Cancel", "back")]
        case .net:
            title = "Play Together"
            let caret = Int(g.clock * 2) % 2 == 0 ? "_" : " "
            if let gu = g.netGuest {
                subtitle = "In \(gu.worldName): the host's world"
                rows = [("Leave and go back to my world", "net_leave"), ("Back", "back")]
            } else {
                if let h = g.netHost {
                    subtitle = "Hosting at \(NetSock.localIP() ?? "?"): \(h.joined ? "your friend is here" : "waiting for a friend")"
                    rows = [("Stop Hosting", "net_stop")]
                } else {
                    subtitle = "A friend on the same Wi-Fi can join this world"
                    rows = [("Host This World", "net_host")]
                }
                PauseMenu.foundLock.lock()
                let found = PauseMenu.found, searching = PauseMenu.searching
                PauseMenu.foundLock.unlock()
                rows.append((searching ? "Searching the network..." : "Search for Friends' Worlds", "net_search"))
                rows += found.map { ("Join \($0.world) (\($0.ip))", "net_join:\($0.ip)") }
                rows += [("Address: \(netAddr)\(editing == 3 ? caret : "")", "edit_addr"), ("Join Address", "net_addr"), ("Back", "back")]
            }
        case .create:
            title = "Create New World"
            // Q2c-console-17: what is about to be made.
            subtitle = "A \(newSurvival ? "Survival" : "Creative") world on \(Difficulty.name(newDifficulty)), " + (newSeed.isEmpty ? "random seed" : "seed \(newSeed)")
            let caret = Int(g.clock * 2) % 2 == 0 ? "_" : " "
            rows = [("Name: \(newName)\(editing == 0 ? caret : "")", "edit_name"),
                    ("Seed: \(newSeed.isEmpty && editing != 1 ? "(random)" : newSeed)\(editing == 1 ? caret : "")", "edit_seed"),
                    ("Game Mode: \(newSurvival ? "Survival" : "Creative")", "new_mode"),
                    ("Difficulty: \(Difficulty.name(newDifficulty))", "new_diff"),
                    ("Create World", "new_create"), ("Back", "back")]
        }
        if !PauseMenu.hostHidden.isEmpty { rows.removeAll { PauseMenu.hostHidden.contains($0.1) } }
        if g.smoothTerrain { rows.removeAll { $0.1 == "smooth" } }   // Q2: the polygon world has no way back to blocks
        layout()
    }

    // P304 (Oct 15 12:09, "the world menu is too dense: I try to hit Achievements and hit Statistics instead"): the
    // pause, title, world and confirm pages lay their buttons out in groups instead of one tight column. Each group
    // starts a new line of up to `cols` buttons that share the width, groups sit 12 apart with a thin rule between
    // them, and the buttons are 30 tall with 6-12 between them (the old column was 18 tall, 3 apart: a laser pointer
    // that wobbled a few pixels landed on the next row). Long settings pages keep the scrolling column.
    struct Style {
        var width = 244, btnH = 18, gapX = 0, gapY = 3, groupGap = 0, cols = 1, lines = PauseMenu.visible
        var groups: [(ids: [String], cols: Int)] = []        // action ids per group (cols 0: as many as fit)
        static let list = Style()
    }
    var style: Style {
        if hostPageID != nil { return .list }
        let vr = PauseMenu.hostEntry?.1 ?? "host:vr"
        switch page {
        case .main:
            // P410 (Oct 22 22:06, "I can't hardly read what's in the main menu"): seven lines of 30 (since P369's
            // Difficulty row, Oct 18) made the page taller than half the headset's panel, so it was fitted at scale 1:
            // letters half a degree high (questcheck --vrtext-only). Lines of 24 with tighter gaps keep it at scale 2
            // (P421: 22 with gaps of 3 and 8, room for an eighth line with Messages).
            return Style(width: 440, btnH: 22, gapX: 12, gapY: 3, groupGap: 8, cols: 4, lines: 8, groups: [
                (["resume", "restorebackup"], 0),
                (["options", vr, PauseMenu.distanceID, "mode"], 0),                              // settings
                (["worldmap", "track", "advancements", "stats", "messages"], 0),             // map and progress
                (["worlds", "netmenu", "coop", "photo", "commands", "checklist", "compute", "shortcuts"], 0),
                (["totitle"], 0)])                                                // leaving, apart from the rest
        case .title:
            return Style(width: 440, btnH: 30, gapX: 12, gapY: 6, groupGap: 12, cols: 4, lines: 6, groups: [
                (["resume"], 0), ([vr, "worlds", "options"], 0), (["quit"], 0)])
        case .world:
            // (b) the per-world buttons: Play alone and widest, Rename / Copy / Delete together, Back apart.
            // (Kept short enough to stay at the headset's larger menu scale.)
            return Style(width: 300, btnH: 30, gapX: 10, gapY: 6, groupGap: 10, cols: 3, lines: 4, groups: [
                (["w_play"], 0), (["w_rename", "w_copy", "w_delete"], 0), (["back"], 0)])
        case .worlds:
            // New-world buttons side by side on top, then one wide button per world, Back apart at the end.
            return Style(width: 320, btnH: 24, gapX: 10, gapY: 5, groupGap: 10, cols: 3, lines: 7, groups: [
                (["create", "newworld", "workshop"], 0),
                (rows.map { $0.1 }.filter { $0.hasPrefix("world:") }, 1),
                (["back"], 0)])
        case .confirm:
            // Cancel and the action side by side, well apart.
            return Style(width: 300, btnH: 30, gapX: 24, gapY: 6, groupGap: 12, cols: 2, lines: 2, groups: [
                (rows.map { $0.1 }, 2)])
        case .checklist, .messages:
            return Style(width: 440, btnH: 20, lines: 12)                 // P399: long item lines
        default:
            return .list
        }
    }
    // The laid-out lines: each a run of row indices, with its group and top (units from the first line).
    private var lines: [(rows: [Int], group: Int, y: Int)] = []
    private var slotRow: [Int] = []             // slot index -> row index
    var dividers: [Int] = []                    // y of the rules between groups on the page (P304), panel units
    var lineCount: Int { lines.count }
    private(set) var shownLines = 0             // lines on screen at once (set by layout)
    private var grouped = false                 // this page uses the grouped layout

    // The buttons; only `style.lines` lines at a time, scrolled a line at a time with the cursor / right stick.
    func layout() {
        let st = style
        // Rows in group order (rows no group names keep their order, in a last group).
        var lineRows: [[Int]] = [], lineGroup: [Int] = []
        if st.groups.isEmpty {
            for i in rows.indices { lineRows.append([i]); lineGroup.append(0) }
        } else {
            var ordered: [[(String, String)]] = []
            var used = Set<String>()
            for gr in st.groups {
                let rs = gr.ids.compactMap { id in rows.first { $0.1 == id } }
                used.formUnion(gr.ids)
                ordered.append(rs)
            }
            let rest = rows.filter { !used.contains($0.1) }
            var cols = st.groups.map { $0.cols }
            if !rest.isEmpty { ordered.append(rest); cols.append(1) }
            rows = ordered.flatMap { $0 }
            var k = 0
            for (gi, grp) in ordered.enumerated() where !grp.isEmpty {
                let n = grp.count
                // Auto: one line when they fit, else as even as possible (6 -> 3 + 3, 5 -> 3 + 2).
                let auto = n <= st.cols ? n : min(st.cols, (n + 1) / 2)
                let per = max(1, cols[gi] > 0 ? cols[gi] : auto)
                var j = 0
                while j < n {
                    let m = min(per, n - j)
                    lineRows.append(Array(k + j ..< k + j + m)); lineGroup.append(gi)
                    j += m
                }
                k += n
            }
        }
        var ys: [Int] = []
        for i in lineRows.indices {
            let gap = i == 0 ? 0 : (lineGroup[i] == lineGroup[i - 1] ? st.gapY : st.groupGap)
            ys.append(i == 0 ? 0 : ys[i - 1] + st.btnH + gap)
        }
        lines = lineRows.indices.map { (rows: lineRows[$0], group: lineGroup[$0], y: ys[$0]) }
        let n = min(lines.count, st.lines)
        shownLines = n
        grouped = !st.groups.isEmpty
        scroll = max(0, min(scroll, lines.count - n))
        // The tallest window of n lines (the panel keeps one height while it scrolls).
        var span = 0
        if n > 0 { for s0 in 0...(lines.count - n) { span = max(span, lines[s0 + n - 1].y - lines[s0].y + st.btnH) } }
        // Q2c-console-53: a subtitle too long for one line wraps onto two smaller ones (Renderer), with room for them.
        let top = subtitle.isEmpty ? 22 : (Font.width(subtitle) > st.width - 16 ? 38 : 32)
        width = st.width
        height = top + span + st.gapY + 22 + (lines.count > n ? 4 : 0)   // + help line
        // Buttons of the visible lines, each line's buttons sharing the inner width.
        var geo: [(x: Int, y: Int, w: Int, row: Int)] = []
        dividers = []
        if n > 0 {
            let y0 = lines[scroll].y
            let inner = st.width - 20
            for li in scroll ..< scroll + n {
                let ln = lines[li]
                let y = top + ln.y - y0
                if li > scroll && ln.group != lines[li - 1].group { dividers.append(y - st.groupGap / 2) }
                let c = ln.rows.count
                let w = (inner - (c - 1) * st.gapX) / c
                for (j, r) in ln.rows.enumerated() {
                    // The last button takes the rounding so every line ends at the same edge.
                    let x = 10 + j * (w + st.gapX)
                    geo.append((x: x, y: y, w: j == c - 1 ? 10 + inner - x : w, row: r))
                }
            }
        }
        slotRow = geo.map { $0.row }
        // P201 (Oct 13 18:33, "on the Create New World page nothing shows which button is selected"): the create,
        // rename and controller pages rebuild every frame (blinking caret, live battery), and fresh slot objects left
        // the hovered one (game.menuHover) pointing at a slot no longer on the page, so nothing drew as hovered.
        // The same buttons in the same places keep their slots.
        let same = slotsKept.count == geo.count
            && zip(slotsKept, geo).allSatisfy { $0.x == $1.x && $0.y == $1.y && $0.w == $1.w && $0.h == st.btnH }
        if same { slots = slotsKept; return }
        defer { slotsKept = slots }
        slots = []
        for (i, gm) in geo.enumerated() {
            let b = MenuSlot(gm.x, gm.y, nil, 0, .button(i))
            b.w = gm.w; b.h = st.btnH
            slots.append(b)
        }
    }

    func row(forSlot i: Int) -> (String, String)? {
        guard i >= 0 && i < slotRow.count else { return nil }
        let k = slotRow[i]
        return k >= 0 && k < rows.count ? rows[k] : nil
    }
    // P304: on the grouped pages left / right stay on the line, and up / down go to the next line's nearest button.
    override func neighbour(of cur: Int, dx: Int, dy: Int) -> Int {
        guard grouped, cur < slots.count else { return super.neighbour(of: cur, dx: dx, dy: dy) }
        let a = slots[cur]
        let ac = a.x * 2 + a.w
        var best = cur, bestScore = Int.max
        for (i, s) in slots.enumerated() where i != cur && !s.hidden {
            let score: Int
            if dx != 0 {
                let along = (s.x - a.x) * dx
                guard s.y == a.y, along > 0 else { continue }
                score = along
            } else {
                let along = (s.y - a.y) * dy
                guard along > 0 else { continue }
                score = along * 10_000 + abs(s.x * 2 + s.w - ac)
            }
            if score < bestScore { bestScore = score; best = i }
        }
        return best
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
        if id.hasPrefix("vol:"), let raw = Int(id.dropFirst(4)), let c = SoundCategory(rawValue: raw) {
            // Volume rows (AudioMenu.swift).
            return c == .master ? "Volume of every sound and the music together."
                                : "Volume of \(c.label.lowercased()) sounds, on top of Master."
        }
        if id == "dir_status" || id == "dir_model" { return Director.statusLines(game).prefix(2).joined(separator: ". ") }   // P266 (n)
        if id == "w_delete" && !WorldStore.useTrash { return "Delete this world for good (there is no Trash on this device): Copy it first to keep a backup." }   // Q2c-console-5
        if let h = PlaytestChecklist.help(id) { return h }               // P399
        if id == "mode" { return "Survival: health, hunger, mining. Creative: fly and build freely. Asks before switching." }
        if id == "new_diff" { return Difficulty.help[Difficulty.clamp(newDifficulty)] }     // Q2c-console-17 (P302: per level)
        if id == "difficulty" || id == "q_firstdiff" { return Difficulty.help[Difficulty.clamp(game.diffLevel)] }   // P302 (c): the level in play
        return PauseMenu.help[id] ?? PauseMenu.hostHelp[id] ?? ""
    }

    var legend: String {
        if let id = hoveredID, id.hasPrefix("cl:") {                  // P399: tick, or a voice note about the item
            return Prompt.line([(.select, "Tick"), (.alt, "Voice Note"), (.back, "Back")])
        }
        var items: [(Prompt.Act, String)] = [(.select, "Select")]
        let value = hoveredID.map { PauseMenu.isValue($0) } ?? false
        if value && !Prompt.pad { items.append((.alt, "Previous")) }
        if page == .options { items.append((.tabs, "Page")) }
        if page != .title && page != .main { items.append((.back, "Back")) } else if page == .main { items.append((.back, "Resume")) }
        if page == .main && Prompt.pad { items.append((.quick, "Next Track")) }
        var s = Prompt.line(items)
        if value && Prompt.pad { s = Prompt.g(.select) + " / " + Glyph.dpadH.s + " Change   " + Prompt.line(Array(items.dropFirst())) }
        return s
    }

    // A = forward, X / right-click = back one step.
    override func click(_ slot: MenuSlot, button: Int, shift: Bool) {
        guard case .button(let i) = slot.kind, let r = row(forSlot: i) else { return }
        // Mouse: clicking the "<" end of a setting steps it back, like right-click.
        var back = button == 1
        if !back && PauseMenu.isValue(r.1) && game.input.mouseX >= 0 {
            let L = HudLayout(game.screen.x, game.screen.y).fitted(self)
            let x0 = origin(L).x + Float(slot.x) * L.s
            if game.input.mouseX < x0 + Float(slot.w) * L.s * 0.2 { back = true }
        }
        act(r.1, back: back)
    }
    override func buttonPressed(_ i: Int) { if let r = row(forSlot: i) { act(r.1, back: false) } }

    // D-pad left/right on a setting steps it; returns false when the hovered row isn't a setting.
    func adjust(_ dx: Int) -> Bool {
        guard let id = hoveredID, PauseMenu.isValue(id) else { return false }
        act(id, back: dx < 0)
        return true
    }
    func switchTab(_ d: Int) {
        guard page == .options else { return }
        let shown = PauseMenu.shownCats, n = shown.count
        let at = shown.firstIndex(of: cat) ?? 0
        cat = shown[(at + d + n) % n]
        scroll = 0
        build()
        game.menuCursor = 0
        game.sfx(.click, 0.4)
    }
    func scrollList(_ d: Int) {
        let before = scroll
        scroll = max(0, min(lines.count - shownLines, scroll + d))     // P304: a line at a time
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
        case _ where id.hasPrefix("host:"):
            hostPageID = String(id.dropFirst(5)); scroll = 0; resetCursor = true
        case _ where hostPageID != nil && id != "back":
            PauseMenu.hostAct?(id, back)
        case _ where id.hasPrefix("q_") && PauseMenu.hostValues.contains(id):        // Q2c-console-26: a host row on our page
            PauseMenu.hostAct?(id, back)
        case _ where id.hasPrefix("vol:") || id.hasPrefix("audio_music_") || id == "audio_test" || id == "audio_subs": audioAct(id, back: back)
        case "resume":
            if page == .title { g.paused = false } else { g.closeMenu() }
        case "options":
            // Controller players land on the Controller page, everyone else on Video (render distance first).
            cat = PadManager.shared.usingPad && PauseMenu.hostHiddenCats.isEmpty ? .controller : .video   // (the Quest: Video)
            go(.options); resetCursor = true
        case "controls": go(.controls); resetCursor = true
        case "shortcuts": go(.shortcuts); resetCursor = true
        case "checklist": PlaytestChecklist.loadIfNeeded(); go(.checklist); resetCursor = true      // P399
        case "messages": go(.messages); resetCursor = true                                        // P421
        case "compute": go(.compute); resetCursor = true                                          // P420
        case _ where id.hasPrefix("cl:"):
            if let i = Int(id.dropFirst(3)) {
                if back { g.closeMenu(); PlaytestChecklist.note(i, clock: g.clock); return }     // X: a voice note about it
                PlaytestChecklist.toggle(i)
            }
        case "cl_view":
            let v = PlaytestChecklist.viewSteps
            g.setRenderDistance(step(v, v.contains(g.world.renderDistance) ? g.world.renderDistance : 24))
        case "cl_sw": PlaytestChecklist.spaceWarp?.toggle()
        case _ where id.hasPrefix("clgo:"):
            g.closeMenu()
            PlaytestChecklist.go(String(id.dropFirst(5)), g)
            return
        case _ where id.hasPrefix("sc:"):
            g.closeMenu()
            g.shortcutTeleport(String(id.dropFirst(3)))
            return
        case "keys": go(.keys); binding = nil; resetCursor = true
        case "padmap": go(.padmap); padBinding = nil; resetCursor = true
        case _ where id.hasPrefix("pbind:"):
            padBinding = Int(id.dropFirst(6))
            padBindArmed = g.clock
        case "pbindreset": PadMap.reset(); g.onToast?("Buttons reset to defaults")
        case "playout":
            #if os(macOS)
            PadMap.halo.toggle()
            g.onToast?(PadMap.halo ? "Shooter layout: Y switches weapon, hold Y for inventory" : "Classic layout: Y opens the inventory")
            #endif
        case _ where id.hasPrefix("bind:"):
            binding = KeyBinds.Action(rawValue: String(id.dropFirst(5)))
        case "bindreset": KeyBinds.reset(); g.onToast?("Keys reset to defaults")
        case "worlds": go(.worlds); resetCursor = true
        case "back" where hostPageID != nil:
            hostPageID = nil; scroll = 0; resetCursor = true
        case "back":
            confirmReset = false; confirmMode = false; confirmQuit = false
            page = stack.popLast() ?? (page == .title ? .title : .main)
            editing = nil
            scroll = 0
            resetCursor = true
        case "create": go(.create); editing = nil; resetCursor = true
        case "netmenu": go(.net); resetCursor = true
        case "net_host":
            if g.coop.active { g.onToast?("End split screen first"); break }
            if let h = NetHost(g) { g.netHost = h; g.onToast?("Hosting: a friend can join at \(NetSock.localIP() ?? "this headset")") }
            else { g.onToast?("Couldn't open the network port") }
        case "net_stop": g.netHost?.stop(g); g.netHost = nil; g.onToast?("Stopped hosting")
        case "net_search":
            PauseMenu.foundLock.lock()
            let busy = PauseMenu.searching
            PauseMenu.searching = true
            PauseMenu.foundLock.unlock()
            guard !busy else { break }
            DispatchQueue.global().async {
                let f = NetSock.discover(seconds: 2.5)
                PauseMenu.foundLock.lock(); PauseMenu.found = f; PauseMenu.searching = false; PauseMenu.foundLock.unlock()
            }
        case _ where id.hasPrefix("net_join:"): g.appAction?("netjoin:" + String(id.dropFirst(9)))
        case "edit_addr":
            editing = 3
            if Prompt.pad || HudLayout.couch { g.openMenu(KeyboardMenu(game: g, target: self)) }
        case "net_addr":
            editing = nil
            let a = netAddr.trimmingCharacters(in: .whitespaces)
            if a.isEmpty { g.onToast?("Type the host's address first") } else { g.appAction?("netjoin:" + a) }
        case "net_leave": g.appAction?("netleave")
        case "newworld": g.appAction?("newworld")
        case "workshop": g.appAction?("workshop")
        case "edit_name", "edit_seed", "edit_rename":
            editing = id == "edit_name" ? 0 : (id == "edit_seed" ? 1 : 2)
            if Prompt.pad || HudLayout.couch { g.openMenu(KeyboardMenu(game: g, target: self)) }
        case "new_mode": newSurvival.toggle()
        case "new_diff": newDifficulty = step([0, 1, 2, 3, 4, 5], newDifficulty)          // P302: six levels
        case "new_terrain": newSmooth.toggle(); st.smoothTerrain = newSmooth
        case "new_create":
            let name = WorldStore.unique(WorldStore.clean(newName))
            g.appAction?("create:\(newSurvival ? 1 : 0):\(newDifficulty):\(newSmooth ? 1 : 0):\(name):\(newSeed)")
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
            if selWorld == currentWorld { g.saveNow(); SaveIO.flush() }      // chunk writes are queued: on disk before the copy
            if let n = WorldStore.copy(selWorld) { g.onToast?("Copied to \(n)"); page = stack.popLast() ?? .worlds; resetCursor = true }
            else { g.onToast?("Couldn't copy the world") }
        case "w_delete":
            if selWorld == currentWorld { g.onToast?("Load another world before deleting this one"); break }
            go(.confirm); resetCursor = true
        case "w_delete_yes":
            let ok = WorldStore.delete(selWorld)
            g.onToast?(ok ? (WorldStore.useTrash ? "Moved \(selWorld) to the Trash" : "Deleted \(selWorld) for good") : "Couldn't delete \(selWorld)")
            // Back to the worlds list (skip the world page).
            while let p = stack.popLast() { page = p; if p == .worlds { break } }
            if page != .worlds { page = .worlds }
            resetCursor = true
        case "totitle":
            g.saveNow()
            PauseMenu.savedNote = SaveBadge.failing ? "\(currentWorld) could not be saved: see the message" : "\(currentWorld) saved"
            stack = []
            page = .title
            resetCursor = true
        case "advancements": g.closeMenu(); g.openMenu(AdvancementMenu(game: g))
        case "stats": go(.stats); resetCursor = true                          // Q2c-console-57
        case "journal": g.closeMenu(); g.openJournal()
        case "worldmap": g.closeMenu(); g.openMenu(MapMenu(game: g))
        case "track": g.closeMenu(); g.openTrackMenu()               // D51 (Waymarks.swift)
        case "photo": g.closeMenu(); g.paused = false; g.togglePhotoMode()
        case "coop":
            if g.coop.active { g.closeMenu(); g.paused = false; g.coop.leave(g) }
            else if g.coop.secondPadAvailable { g.closeMenu(); g.paused = false; g.coop.join(g, controller: nil) }
            else { g.onToast?("Connect a second controller, then press its Menu button") }
        case "minimap": st.minimap.toggle()
        case "targetbar": st.targetBar.toggle()
        case "looknames": st.lookNames.toggle()
        case "splitlayout": st.splitSideBySide.toggle()
        case "brightness": st.brightness = step([0, 0.25, 0.5, 0.75, 1], st.brightness)
        case "commands": g.closeMenu(); g.openCommands()
        case "mode": go(.confirm); confirmMode = true; resetCursor = true          // Q2c-console-5: ask first
        case "mode_yes":
            g.toggleMode(); g.onModeChanged?(g.survival)
            g.onToast?(g.survival ? "Survival mode" : "Creative mode")        // P300 (b): the mode, no how-to
            confirmMode = false
            page = stack.popLast() ?? .main
            resetCursor = true
        // P369 (Oct 18 08:15, "I should be able to change the world settings"): the difficulty changes at any time and
        // applies at once (every damage path reads Game.diffLevel live; Difficulty.level follows it here and each tick).
        case "difficulty":
            g.diffLevel = step([0, 1, 2, 3, 4, 5], g.diffLevel)
            Difficulty.level = g.diffLevel
        case "fov": g.fovSetting = step([50, 60, 70, 80, 90, 100, 110], g.fovSetting)
        case "sens": g.sensitivity = step([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3], g.sensitivity)
        case "invert": g.invertY.toggle()
        case "autojump": g.autoJump.toggle()
        case "dead": g.deadZone = step(PauseMenu.zones, g.deadZone)
        case "lookdead": st.lookDead = step(PauseMenu.zones, st.lookDead)
        case "lookouter": st.lookOuter = step(PauseMenu.outers, st.lookOuter)
        case "moveouter": st.moveOuter = step(PauseMenu.outers, st.moveOuter)
        case "lookx": st.lookX = step(PauseMenu.sens, st.lookX)
        case "looky": st.lookY = step(PauseMenu.sens, st.lookY)
        case "accel": st.lookAccel = step([0, 1, 2, 3, 4, 5], st.lookAccel)
        case "aim": st.aimAssist.toggle()
        case "curve": st.lookCurve = step([0, 1, 2], st.lookCurve)
        case "rumble": st.rumble = step([0, 0.35, 0.7, 1], st.rumble); PadManager.shared.rumble(0.8, 0.15)
        case "padinfo": PadManager.shared.rumble(1, 0.3)
        case "southpaw": st.southpaw.toggle()
        case "sneaktoggle": st.sneakToggle.toggle()
        case "autosprint": st.autoSprint.toggle()
        case "flight": st.flightInverted.toggle()
        case "glyphs": st.glyphStyle = step([0, 1, 2], st.glyphStyle)
        case "rd":
            let opts = [2, 4, 6, 8, 10, 12, 16, 20, 24]
            // Steps from the player's choice (Auto Render Distance may have the world below it for now). A distance
            // that is not an option (an old save) moves to the next option up or down from it (playtest Oct 9: 9 -> 4).
            let cur = g.chosenRenderDistance
            let rd = opts.contains(cur) ? step(opts, cur) : (back ? (opts.last { $0 < cur } ?? opts[opts.count - 1]) : (opts.first { $0 > cur } ?? opts[0]))
            g.setRenderDistance(rd)
            UserDefaults.standard.set(rd, forKey: "renderDistance")
        case "ad":
            g.setActiveDistance(step(World.activeOptions, World.activeOptions.contains(PauseMenu.activeChoice(g)) ? PauseMenu.activeChoice(g) : 8))
        case "fullscreen": g.appAction?("fullscreen")
        case "launchfs": st.launchFullscreen.toggle()
        case "graphics": g.fancyGraphics.toggle()
        case "chipping": st.chipping.toggle()
        case _ where id.hasPrefix("fx"): if let b = Int(id.dropFirst(2)) { st.shaderFX ^= b }
        case "smooth":
            guard !g.smoothTerrain else { break }
            g.smoothTerrain.toggle(); SmoothTerrain.use(world: g.smoothTerrain, world: g.world)
            // R26 (Oct 13 evening: "his world loaded without smooth terrain after being smooth"): the switch lived only in
            // the game until the next autosave, so a headset taken off (the app killed, no quit save) reopened the world
            // in its old mode; and before the world-mode fix a world could look smooth only because the last world's
            // mode leaked into it, never saving "smooth" at all. The choice is written to this world's save at once.
            if g.persistent, let s = g.save { s.saveMeta(g.meta, background: true) }
            g.onToast?(g.smoothTerrain ? "Smooth terrain on: saved with this world" : "Block terrain: saved with this world")
        case "wscale": g.renderScale = step([1, 0.85, 0.7], g.renderScale)
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
        case "hints": st.buttonHints.toggle(); if st.buttonHints { st.hintSeconds = 0 }     // on again: another 3 h (P53)
        case "textbg": st.textBackground = step([0, 0.25, 0.5, 0.75], st.textBackground)
        case "bugnotes":
            if BugNotes.denied {
                g.onToast?("Allow Microphone and Speech Recognition for Sunderfall in System Settings > Privacy & Security")
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
        case "bugvideo": st.bugNoteVideo.toggle()
        case "flashes": st.screenEffects.toggle()
        case "narrator": st.narrator.toggle(); if st.narrator { Narrator.shared.say("Narrator on", clock: g.clock) }
        case "dir_on": st.directorOn.toggle(); if !st.directorOn { DirectorLLM.release() }      // P266 (h)
        case "dir_backend":
            st.directorBackend = step(Director.plannerChoices(), Director.effectiveBackend)      // Q2c-console-45
            DirectorPlanner.shared.reset(); Director.fallbackNote = ""
            if st.directorBackend != 1 { DirectorLLM.release() }
            if st.directorBackend == 2 { g.onToast?("Cloud planner: only a summary of your world is sent, nothing about you or this device") }
        case "dir_freq":
            let was = st.directorFreq
            st.directorFreq = step([0, 1, 2], st.directorFreq)
            Director.rescheduled(from: was)
        case "dir_early": st.directorEarly.toggle()
        case "dir_status", "dir_model", "dir_cloud": return
        case "dir_journal": g.closeMenu(); g.openJournal(tab: .events)
        case "about": g.closeMenu(); g.openMenu(AboutMenu(game: g))      // Q2 (AboutMenu.swift)
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
        case "perf": st.perfOverlay.toggle(); PerfOverlay.shared.reset()
        case "devtools": st.devTools.toggle()
        case "subtitles": st.subtitles.toggle()
        case "colorblind": st.colorblind.toggle()
        case "tutorial": st.tutorialHints.toggle()
        case "resethints": PauseMenu.resetHints(g)
        case "volume": g.volumeSetting = step([0, 0.1, 0.25, 0.5, 0.8, 1], g.volumeSetting)
        case "music": g.musicVolume = step([0, 0.25, 0.5, 0.75, 1], g.musicVolume)
        case "quit": go(.confirm); confirmQuit = true; confirmAt = CFAbsoluteTimeGetCurrent(); resetCursor = true    // Q2c-console-54
        case "quit_yes":
            guard CFAbsoluteTimeGetCurrent() - confirmAt >= 0.4 else { break }
            confirmQuit = false
            g.appAction?("quit")
        case "restorebackup": g.appAction?("restorebackup")
        default: g.appAction?(id)
        }
        g.sfx(.click, 0.5)
        if g.menu === self {
            let cur = g.menuCursor
            build()
            g.menuCursor = resetCursor ? 0 : min(cur, max(0, slots.count - 1))
        }
    }

    override var capturesText: Bool { ((page == .create || page == .rename || page == .net) && editing != nil) || binding != nil }
    override func typed(_ str: String) {
        guard let e = editing else { return }
        for c in str {
            if e == 3 {
                if c == "\u{8}" { if !netAddr.isEmpty { netAddr.removeLast() } }
                else if netAddr.count < 40 && (c.isNumber || c == "." || c.isLetter || c == "-") { netAddr.append(c) }
                continue
            }
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
        if hostPageID != nil { act("back", back: false); return true }
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
            PadMap.glyph(.b).s + " / " + Glyphs.key("Shift") + " Sneak,  " + PadMap.glyph(.r3).s + " Melee",
            PadMap.glyph(.l3).s + " / " + Glyphs.key("Ctrl") + " Sprint",
            Glyph.rt.s + " / " + Glyph.mouseL.s + " Attack, mine",
            Glyph.lt.s + " / " + Glyph.mouseR.s + " Use, place, eat",
            PadMap.glyph(.lb).s + PadMap.glyph(.rb).s + " / " + Glyphs.key("1-9") + " Hotbar",
            (PadMap.halo ? PadMap.glyph(.y).s + " Switch weapon (hold: inventory),  " + k(.inventory) + " Inventory"
                          : PadMap.glyph(.y).s + " / " + k(.inventory) + " Inventory"),
            PadMap.glyph(.x).s + " / " + Glyph.mouseM.s + " Pick block",
            PadMap.glyph(.ddown).s + " / " + k(.drop) + " Drop (hold: stack)",
            PadMap.glyph(.dright).s + " / " + k(.offhand) + " Swap off hand",
            PadMap.glyph(.dleft).s + " / " + k(.chat) + " Commands",
            PadMap.glyph(.dup).s + " / " + k(.fly) + " Fly (creative), " + Glyphs.key(KeyBinds.name(KeyBinds.key(.fastFly))) + " fast flight (sprint)",
            PadMap.glyph(.view).s + " / " + k(.camera) + " Camera",
            Glyph.menu.s + " / " + Glyphs.key("Esc") + " Pause",
            Glyph.share.s + " / " + Glyphs.key("F2") + " Screenshot",
            // Guns (Ballistics) and ship helms (ShipPlay).
            Glyph.rt.s + " / " + Glyph.mouseL.s + " Fire gun,  " + Glyph.lt.s + " / " + Glyph.mouseR.s + " Aim",
            PadMap.glyph(.x).s + " / " + k(.reload) + " Reload gun",
            "At a helm: " + Glyph.ls.s + " / " + Glyphs.key("WASD") + " Throttle, steer",
            "At a helm: " + PadMap.glyph(.a).s + Glyph.rt.s + " / " + Glyphs.key("Space") + " Climb,  " + Glyph.lt.s + " / " + Glyphs.key("Ctrl") + " Descend",
            "At a helm: " + PadMap.glyph(.b).s + " / " + Glyphs.key("Shift") + " Leave",
        ]
    }
}
