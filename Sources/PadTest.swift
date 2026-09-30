import Foundation
import simd

// Harness: `--padtest` drives the real Game.tick with a simulated controller (PadManager.simulated) through
// the pause menu, options pages, on-screen keyboard, worlds list (copy / rename / delete with confirmation),
// inventory, creative palette and gameplay buttons, printing PASS / FAIL per check. Options are restored and
// worlds live in a temporary folder, so running it never touches the player's settings or saves.
enum PadTest {
    static var failures = 0
    static var passes = 0

    static func check(_ ok: Bool, _ what: String) {
        if ok { passes += 1 } else { failures += 1 }
        print("padtest \(ok ? "PASS" : "FAIL") \(what)")
    }

    static func frame(_ g: Game, _ p: PadSnapshot = PadSnapshot()) {
        PadManager.shared.simulated = p
        g.tick(1.0 / 60)
    }

    static func pad(_ name: String) -> PadSnapshot {
        var p = PadSnapshot()
        switch name {
        case "a": p.a = true
        case "b": p.b = true
        case "x": p.x = true
        case "y": p.y = true
        case "lb": p.lb = true
        case "rb": p.rb = true
        case "lt": p.lt = 1
        case "rt": p.rt = 1
        case "l3": p.l3 = true
        case "r3": p.r3 = true
        case "menu": p.menu = true
        case "view": p.view = true
        case "share": p.share = true
        case "up": p.up = true
        case "down": p.down = true
        case "left": p.left = true
        case "right": p.right = true
        default: print("padtest: unknown button \(name)")
        }
        return p
    }

    // Presses each space-separated button for one frame, releasing between presses. "down*3" repeats.
    static func tap(_ g: Game, _ script: String) {
        for tok in script.split(separator: " ") {
            let parts = tok.split(separator: "*")
            let n = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            for _ in 0..<n {
                frame(g, pad(String(parts[0])))
                frame(g)
            }
        }
    }

    static func run(_ g: Game) {
        PrefsSandbox.begin()
        let fm = FileManager.default
        let oldBase = WorldStore.base
        let tmp = fm.temporaryDirectory.appendingPathComponent("blocksmith-padtest-\(getpid())", isDirectory: true)
        try? fm.removeItem(at: tmp)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        WorldStore.base = tmp
        WorldStore.useTrash = false
        defer {
            WorldStore.base = oldBase
            WorldStore.useTrash = true
            try? fm.removeItem(at: tmp)
            PrefsSandbox.end()
        }
        let t0 = CFAbsoluteTimeGetCurrent()

        // Pause / resume with the Menu button.
        g.menu = nil
        g.paused = false
        frame(g)
        tap(g, "menu")
        check(g.paused && g.menu is PauseMenu, "Menu button pauses the game")
        tap(g, "menu")
        check(!g.paused && g.menu == nil, "Menu button resumes")
        check(PadManager.shared.usingPad, "pad input switches prompts to controller glyphs")

        // Options pages and settings.
        tap(g, "menu")
        guard let pm = g.menu as? PauseMenu else { check(false, "pause menu open"); return }
        check(g.menuCursor == 0, "cursor starts on Back to Game")
        tap(g, "down a")
        check(pm.page == .options && pm.cat == .controller, "A on Options opens the Controller page")
        check(Prompt.menuLegend(pm, g).contains(Glyph.a.s), "legend shows the A glyph")
        tap(g, "rb")
        check(pm.cat == .video, "RB switches to the Video page")
        tap(g, "lb*2")
        check(pm.cat == .controls, "LB twice reaches Keyboard & Mouse")
        let inv = g.invertY
        tap(g, "down right")
        check(g.invertY != inv, "D-pad right toggles Invert Y")
        tap(g, "left")
        check(g.invertY == inv, "D-pad left toggles it back")
        let sens = g.sensitivity
        tap(g, "up a")
        check(g.sensitivity > sens, "A steps Mouse Sensitivity up")
        tap(g, "x")
        check(g.sensitivity == sens, "X steps it back down")
        tap(g, "rb")
        let lx = Settings.shared.lookX
        tap(g, "down right")
        check(Settings.shared.lookX > lx, "Look Speed X steps up on the Controller page")
        tap(g, "left")
        tap(g, "down*20")
        check(pm.scroll > 0, "long Controller page scrolls with the cursor")
        tap(g, "b")
        check(pm.page == .main, "B returns to the pause menu")

        // Key bindings: A arms a row, the next key press binds it, B backs out.
        pm.go(.keys); pm.build(); g.menuCursor = 0
        tap(g, "a")
        check(pm.binding == .forward, "A on Walk Forward waits for a key")
        g.input.pressed.insert(5)            // G
        frame(g)
        check(KeyBinds.key(.forward) == 5 && pm.binding == nil, "the next key press becomes the binding (\(KeyBinds.name(KeyBinds.key(.forward))))")
        check(Prompt.keyGlyph(.move).contains("G"), "keyboard prompts follow the new binding")
        KeyBinds.reset()
        tap(g, "b")
        check(pm.page == .main, "B leaves Key Bindings")

        // Worlds list: create page + on-screen keyboard.
        try? fm.createDirectory(at: tmp.appendingPathComponent("Beta"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: tmp.appendingPathComponent("Alpha"), withIntermediateDirectories: true)
        try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: tmp.appendingPathComponent("Beta").path)
        tap(g, "down*6 a")
        check(pm.page == .worlds, "Worlds... opens the worlds list")
        check(pm.rows.count == 5 && pm.rows[2].1 == "world:Alpha", "worlds list is newest first")
        tap(g, "a")
        check(pm.page == .create, "Create New World... opens the create page")
        tap(g, "a")
        check(g.menu is KeyboardMenu, "A on Name opens the on-screen keyboard")
        tap(g, "x*12")
        tap(g, "down*2 right*5 a up right*2 a")
        tap(g, "menu")
        check(g.menu === pm && pm.newName == "hi", "typed \"hi\" with the keyboard (got \"\(pm.newName)\")")
        tap(g, "b b")
        check(pm.page == .worlds, "B twice leaves the create page")

        // Copy, delete (with cancel), rename.
        tap(g, "down*2 a")
        check(pm.page == .world && pm.selWorld == "Alpha", "A on a world opens its actions")
        tap(g, "down*2 a")
        check(WorldStore.exists("Alpha Copy") && pm.page == .worlds, "Copy makes \"Alpha Copy\"")
        let beta = pm.rows.firstIndex { $0.1 == "world:Beta" } ?? 0
        tap(g, "down*\(beta) a down*3 a")
        check(pm.page == .confirm && g.menuCursor == 0, "Delete asks for confirmation with Cancel selected")
        tap(g, "a")
        check(WorldStore.exists("Beta") && pm.page == .world, "Cancel keeps the world")
        tap(g, "down*3 a down a")
        check(!WorldStore.exists("Beta") && pm.page == .worlds, "confirmed Delete removes the world")
        let copyRow = pm.rows.firstIndex { $0.1 == "world:Alpha Copy" } ?? 0
        tap(g, "down*\(copyRow) a down a")
        check(pm.page == .rename, "Rename... opens the rename page")
        tap(g, "menu")
        for _ in 0..<24 { pm.typed("\u{8}") }
        pm.typed("Gamma")
        tap(g, "down a")
        check(WorldStore.exists("Gamma") && !WorldStore.exists("Alpha Copy"), "Save renames the world")
        g.closeMenu()
        g.paused = false
        frame(g)

        // Inventory with the pad.
        g.survival = true
        g.inventory.main[0] = ItemStack(Items.id("cobblestone"), 10)
        g.inventory.main[1] = .empty
        g.selected = 0
        tap(g, "y")
        check(g.menu is InventoryMenu, "Y opens the inventory")
        tap(g, "a")
        check(g.carried.count == 10, "A picks up the hovered stack")
        tap(g, "right x")
        check(g.inventory.main[1].count == 1, "X places one item")
        tap(g, "a")
        check(g.inventory.main[1].count == 10 && g.carried.isEmpty, "A places the rest")
        check(Prompt.menuLegend(g.menu!, g).contains("Pick up"), "legend describes the hovered slot")
        tap(g, "b")
        check(g.menu == nil, "B closes the inventory")

        // Creative palette paging.
        g.survival = false
        tap(g, "y")
        if let c = g.menu as? CreativeMenu {
            tap(g, "rt")
            check(c.scroll == min(c.maxScroll, c.rows), "RT pages the creative palette")
            tap(g, "lt")
            check(c.scroll == 0, "LT pages back")
            tap(g, "rb")
            check(c.tab == .building && c.all.count > 20 && c.all.count < CreativeMenu.every.count, "RB opens the Building tab (\(c.all.count) items)")
            tap(g, "lb*2")
            check(c.tab == .search, "LB wraps around to Search")
            c.typed("pick")
            check(!c.all.isEmpty && c.all.allSatisfy { Items.def($0).display.lowercased().contains("pick") || Items.key($0).contains("pick") }, "search filters by name (\(c.all.count) hits)")
            tap(g, "y")
            check(g.menu is KeyboardMenu, "Y in Search opens the on-screen keyboard")
            tap(g, "menu")
            let counts = CreativeMenu.Tab.allCases.map { CreativeMenu.items($0, query: "").count }
            print("padtest: creative tab sizes " + zip(CreativeMenu.Tab.allCases, counts).map { "\($0.0.short) \($0.1)" }.joined(separator: ", "))
        } else { check(false, "Y opens the creative palette") }
        g.closeMenu()

        // Gameplay buttons.
        g.selected = 0
        tap(g, "rb")
        check(g.selected == 1, "RB selects the next hotbar slot")
        tap(g, "lb")
        g.inventory.main[0] = ItemStack(Items.id("cobblestone"), 5)
        g.inventory.offhand[0] = .empty
        tap(g, "right")
        check(g.inventory.offhand[0].count == 5 && g.inventory.main[0].isEmpty, "D-pad right swaps to the off hand")
        tap(g, "right")
        tap(g, "down")
        check(g.inventory.main[0].count == 4, "D-pad down drops one item")
        tap(g, "left")
        check(g.menu is CommandMenu, "D-pad left opens the command console")
        tap(g, "b")
        let yaw = g.player.yaw
        var look = PadSnapshot(); look.rx = 1
        for _ in 0..<20 { frame(g, look) }
        frame(g)
        check(g.player.yaw < yaw - 0.3, "right stick turns the view")

        // Rumble requests (logged instead of vibrating while simulated).
        g.survival = true
        PadManager.shared.rumbleLog.removeAll()
        g.damage(2, "test")
        check(!PadManager.shared.rumbleLog.isEmpty, "taking damage rumbles")

        // Subtitles: a sound to the player's right gets a caption with a right arrow.
        Settings.shared.subtitles = true
        let right = V3(cosf(g.player.yaw), 0, -sinf(g.player.yaw))
        g.sfx(.mobZombie, 1, at: g.player.eye + right * 6)
        let cap = Subtitles.shared.entries.first { $0.label == "Zombie groans" }
        check(cap?.side == 1, "subtitles caption a zombie on the right with a right arrow")
        Settings.shared.subtitles = false
        check(ContextPrompts.items(g).allSatisfy { !$0.isEmpty }, "contextual prompts build (\(ContextPrompts.items(g).count) shown)")

        // Layout: a two-column-free options panel fits a 1080p TV in couch mode with a safe area.
        let couch = HudLayout.couch, safe = Settings.shared.safeArea
        HudLayout.couch = true
        Settings.shared.safeArea = 6
        let L = HudLayout(1920, 1080).fitted(pm)
        check(Float(pm.height) * L.s <= 1080 - 2 * L.insetY && Float(pm.width) * L.s <= 1920, "options panel fits a 1080p TV (scale \(Int(L.s)))")
        HudLayout.couch = couch
        Settings.shared.safeArea = safe

        print(String(format: "padtest: %d passed, %d failed (%.0f ms)", passes, failures, (CFAbsoluteTimeGetCurrent() - t0) * 1000))

        // Leave the Controller options page open for the snapshot.
        g.survival = false
        g.health = 20
        g.menu = nil
        g.paused = false
        g.paused = true
        if let p = g.menu as? PauseMenu { p.go(.options); p.cat = .controller; p.build(); g.menuCursor = 2; g.menuHover = p.slots[2] }
        PadManager.shared.forcePad(true)
    }

    // `--padview NAME`: sets up a screen for a snapshot (with pad glyphs): keyboard, worlds, world, confirm,
    // controls, options (Video page).
    static func view(_ g: Game, _ name: String) {
        PadManager.shared.forcePad(true)
        g.menu = nil
        g.paused = false
        g.paused = true                  // opens the pause menu (didSet only fires on a change)
        guard let pm = g.menu as? PauseMenu else { print("padview: no pause menu"); return }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("blocksmith-padview-\(getpid())", isDirectory: true)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let old = WorldStore.base
        WorldStore.base = tmp
        for (i, n) in ["Castle Build", "Survival Island", "Couch World", "Redstone Lab"].enumerated() {
            try? fm.createDirectory(at: tmp.appendingPathComponent(n), withIntermediateDirectories: true)
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: Double(-3600 * (i + 1)))], ofItemAtPath: tmp.appendingPathComponent(n).path)
        }
        var cursor = 0
        switch name {
        case "keyboard":
            pm.go(.create); pm.newName = "Couch Wor"; pm.editing = 0; pm.build()
            let km = KeyboardMenu(game: g, target: pm)
            g.menu = km
            cursor = 25
        case "worlds": pm.go(.worlds); pm.build(); cursor = 3
        case "world": pm.go(.worlds); pm.build(); pm.selWorld = "Survival Island"; pm.go(.world); pm.build(); cursor = 1
        case "confirm": pm.go(.worlds); pm.build(); pm.selWorld = "Redstone Lab"; pm.go(.confirm); pm.build()
        case "controls": pm.go(.controls); pm.build()
        case "title": pm.page = .title; pm.build()
        default: pm.go(.options); pm.cat = .video; pm.build(); cursor = 1
        }
        WorldStore.base = old
        try? fm.removeItem(at: tmp)
        if let m = g.menu, cursor < m.slots.count { g.menuCursor = cursor; g.menuHover = m.slots[cursor] }
        g.input.mouseX = -1
    }
}
