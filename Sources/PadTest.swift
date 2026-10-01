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
        // Holding the D-pad repeats: ~0.9 s held should move several rows, not one.
        let startRow = pm.scroll + g.menuCursor
        var hold = PadSnapshot(); hold.down = true
        for _ in 0..<54 { frame(g, hold) }
        frame(g)
        check(pm.scroll + g.menuCursor - startRow >= 5, "holding D-pad down repeats (\(pm.scroll + g.menuCursor - startRow) rows)")
        tap(g, "down*20")
        check(pm.scroll > 0, "long Controller page scrolls with the cursor")
        tap(g, "b")
        check(pm.page == .main, "B returns to the pause menu")

        // Key bindings: A arms a row, the next key press binds it, B backs out.
        pm.go(.keys); pm.build(); g.menuCursor = 0
        tap(g, "a")
        check(pm.binding == .forward, "A on Walk Forward waits for a key")
        g.input.pressed.insert(4)            // H
        frame(g)
        check(KeyBinds.key(.forward) == 4 && pm.binding == nil, "the next key press becomes the binding (\(KeyBinds.name(KeyBinds.key(.forward))))")
        check(Prompt.keyGlyph(.move).contains("H"), "keyboard prompts follow the new binding")
        KeyBinds.reset()
        tap(g, "b")
        check(pm.page == .main, "B leaves Key Bindings")

        // Button mapping: arm Jump / Select with A, press X, and X becomes the jump button.
        pm.go(.padmap); pm.build(); g.menuCursor = 0
        tap(g, "a")
        check(pm.padBinding == 0, "A on Jump / Select waits for a button")
        tap(g, "x")
        check(PadMap.map[0] == 2 && PadMap.map[2] == 0, "pressing X swaps Jump onto X (Pick Block onto A)")
        check(PadMap.apply(pad("x")).a && Prompt.g(.jump, pad: true) == Glyph.x.s, "X now jumps and prompts show X")
        PadMap.reset()
        tap(g, "b")
        check(pm.page == .main, "B leaves Button Mapping")

        // Worlds list: create page + on-screen keyboard.
        try? fm.createDirectory(at: tmp.appendingPathComponent("Beta"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: tmp.appendingPathComponent("Alpha"), withIntermediateDirectories: true)
        try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: tmp.appendingPathComponent("Beta").path)
        tap(g, "down*7 a")
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
        check(WorldStore.clean(" ..my/world:1 ") == "my-world-1" && WorldStore.clean("   ") == "New World", "world names are made file-system safe")
        check(WorldStore.unique("Gamma") == "Gamma (2)" && WorldStore.unique("Delta") == "Delta", "new world names never collide")
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

        // Chest: LT takes everything, LT on an inventory stack stores every stack of that item.
        g.survival = true
        let box = ItemContainer(27)
        box[0] = ItemStack(Items.id("cobblestone"), 20)
        box[5] = ItemStack(Items.id("dirt"), 10)
        for i in 0..<36 { g.inventory.main[i] = .empty }
        let chest = ChestMenu(game: g, container: box, title: "Chest")
        g.openMenu(chest)
        g.menuCursor = 0
        tap(g, "lt")
        check(box[0].isEmpty && box[5].isEmpty, "LT takes everything from a chest")
        if let i = chest.slots.firstIndex(where: { $0.isPlayerInv && Items.key($0.stack.item) == "cobblestone" }) {
            g.menuCursor = i
            tap(g, "lt")
            let left = (0..<36).filter { Items.key(g.inventory.main[$0].item) == "cobblestone" }.count
            check(left == 0 && (0..<27).contains { Items.key(box[$0].item) == "cobblestone" }, "LT on an inventory stack stores every stack of it")
        } else { check(false, "taken items reached the inventory") }
        g.closeMenu()
        g.survival = false

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

        // Vehicles: a car piloted with the pad (RT throttle, LT reverse, B leaves), gauges on the HUD.
        do {
            PadManager.shared.forcePad(true)
            let keep = (g.player.pos, g.player.yaw, g.player.pitch, g.player.flying)
            let helm = ShipTest.place(g.world, "car", near: g.player.pos)
            let (carOpt, msg) = g.world.ships.assemble(at: helm, game: g)
            if let car = carOpt {
                g.startPiloting(car)
                var rt = PadSnapshot(); rt.rt = 1
                for _ in 0..<5 { frame(g, rt) }
                check(g.world.ships.pilot === car && car.throttle > 0.9, "RT is the throttle on a land vehicle")
                check(ContextPrompts.items(g).contains { $0.contains("Throttle") }, "piloting shows vehicle prompts")
                check(CombatHUD.shared.lines(g, HudLayout(1280, 800)).contains { $0.text.contains("km/h") }, "vehicle gauges show speed")
                var lt = PadSnapshot(); lt.lt = 1
                frame(g, lt)
                check(car.throttle < -0.9, "LT reverses")
                // Keyboard: the forward key is the throttle too, the strafe keys steer.
                g.input.keys.insert(KeyBinds.key(.forward)); g.input.keys.insert(KeyBinds.key(.left))
                for _ in 0..<3 { frame(g) }
                check(car.throttle > 0.9 && car.steer < -0.5, "W throttles and A steers a land vehicle (\(car.throttle), \(car.steer))")
                g.input.keys.remove(KeyBinds.key(.forward)); g.input.keys.remove(KeyBinds.key(.left))
                // A hull hit (the vehicle lost blocks since last frame) is felt.
                PadManager.shared.rumbleLog.removeAll()
                Feedback.lastShipBlocks = [car.id: car.blockCount + 6]
                Feedback.vehicleTick(g)
                check(!PadManager.shared.rumbleLog.isEmpty, "a hull hit on the vehicle rumbles")
                tap(g, "b")
                check(g.world.ships.pilot == nil, "B leaves the helm")
                g.world.ships.remove(car)
            } else { check(false, "test car assembles (\(msg))") }
            (g.player.pos, g.player.yaw, g.player.pitch, g.player.flying) = keep
            g.player.vel = .zero
        }

        // Deck gun: LT takes it, RT fires both barrels after the loading delay, B steps off.
        do {
            let keep = (g.player.pos, g.player.yaw, g.player.pitch)
            g.player.flying = true
            g.player.pos = V3(g.player.pos.x, Float(CH - 40), g.player.pos.z)
            let fwd = V3(-sinf(g.player.yaw), 0, -cosf(g.player.yaw))
            let gunMob = Mob(.deckGun, at: g.player.eye + fwd * 2.5 - V3(0, 1.2, 0))
            gunMob.persistent = true
            g.mobs.mobs.append(gunMob)
            let c = gunMob.pos + V3(0, gunMob.height * 0.5, 0) - g.player.eye
            g.player.pitch = asinf(c.y / simd_length(c))
            tap(g, "lt")
            check(Turrets.shared.manned === gunMob, "LT mans a deck gun")
            check(ContextPrompts.items(g).contains { $0.contains("Fire") || $0.contains("Reloading") }, "deck gun prompts")
            for _ in 0..<40 { frame(g) }
            let before = g.arms.slugs.count
            tap(g, "rt")
            check(g.arms.slugs.count >= before + 2, "RT fires the deck gun (\(g.arms.slugs.count - before) shells)")
            tap(g, "b")
            check(!Turrets.shared.active, "B steps off the gun")
            g.mobs.mobs.removeAll { $0 === gunMob }
            g.arms.slugs.removeAll()
            (g.player.pos, g.player.yaw, g.player.pitch) = keep
        }

        // Guns: weapon wheel (hold RB), quick RB tap, reload on X, ADS snap onto a nearby enemy.
        if Items.has("gun_rifle") && Items.has("gun_shotgun") {
            g.survival = false
            for i in 0..<36 { g.inventory.main[i] = .empty }
            g.inventory.main[0] = ItemStack(Items.id("gun_rifle"), 1)
            g.inventory.main[14] = ItemStack(Items.id("gun_shotgun"), 1)
            g.selected = 0
            var rb = PadSnapshot(); rb.rb = true
            for _ in 0..<20 { frame(g, rb) }
            check(WeaponWheel.shared.open && WeaponWheel.shared.entries.count == 2, "holding RB opens the weapon wheel")
            rb.ry = -1
            for _ in 0..<3 { frame(g, rb) }
            frame(g)
            check(Items.key(g.inventory.main[g.selected].item) == "gun_shotgun" && !WeaponWheel.shared.open, "pointing down and letting go equips the shotgun")
            let sel = g.selected
            tap(g, "rb")
            check(g.selected == (sel + 1) % 9, "a quick RB tap still steps the hotbar")
            g.select(sel)
            // Reload: empty shotgun, shells in the pack.
            g.survival = true
            var sg = g.inventory.main[g.selected]; sg.tag = 0; g.inventory.main[g.selected] = sg
            g.inventory.main[20] = ItemStack(Items.id("shotgun_shells"), 12)
            tap(g, "x")
            check(g.arms.reload > 0, "X reloads a gun")
            for _ in 0..<200 { frame(g) }
            check(g.inventory.main[g.selected].tag == Guns.all[Guns.shotgun].mag, "the reload fills the magazine (\(g.inventory.main[g.selected].tag))")
            check(ContextPrompts.items(g).contains { $0.contains("Reload") }, "gun prompts list reload")
            // ADS aim assist: a zombie 7 degrees to the side gets pulled toward the crosshair.
            g.survival = false
            let keep = (g.player.pos, g.player.yaw, g.player.pitch, g.player.flying)
            g.player.flying = true
            g.player.pos = V3(g.player.pos.x, Float(CH - 40), g.player.pos.z)
            g.player.pitch = 0
            let side = g.player.yaw - 0.12
            let z = Mob(.zombie, at: g.player.eye + V3(-sinf(side), 0, -cosf(side)) * 10 - V3(0, 1.1, 0))
            g.mobs.mobs.append(z)
            let off0 = abs(AimAssist.wrap(AimAssist.angles(g, z).yaw - g.player.yaw))
            var lt = PadSnapshot(); lt.lt = 1
            for _ in 0..<12 { frame(g, lt) }
            let off1 = abs(AimAssist.wrap(AimAssist.angles(g, z).yaw - g.player.yaw))
            frame(g)
            check(off1 < off0 * 0.6, String(format: "aiming down sights snaps toward the enemy (%.3f -> %.3f rad)", off0, off1))
            g.mobs.mobs.removeAll { $0 === z }
            (g.player.pos, g.player.yaw, g.player.pitch, g.player.flying) = keep
            for i in 0..<36 { g.inventory.main[i] = .empty }
        }

        // World map: M opens it, RT / LT zoom, the stick pans, A recentres, B closes; holding View opens it too
        // while a tap still cycles the camera.
        do {
            g.menu = nil
            MapCache.shared.prefill(g.world.gen, x: Int(g.player.pos.x), z: Int(g.player.pos.z), radius: 160, step: 8)
            g.input.pressed.insert(46)           // M
            frame(g)
            if let mm = g.menu as? MapMenu {
                check(true, "M opens the world map")
                let z0 = mm.zoom
                tap(g, "rt")
                check(mm.zoom == max(0, z0 - 1), "RT zooms the map in")
                tap(g, "lt lt")
                check(mm.zoom == min(MapMenu.zooms.count - 1, z0 + 1), "LT zooms out")
                let cx0 = mm.cx
                var r = PadSnapshot(); r.lx = 1
                for _ in 0..<15 { frame(g, r) }
                frame(g)
                check(mm.cx > cx0 + 10, "the left stick pans the map")
                tap(g, "a")
                check(abs(mm.cx - g.player.pos.x) < 1, "A recentres on the player")
                let lines = mm.drawLines(HudLayout(1280, 800).fitted(mm), V2(100, 100))
                check(lines.count > 80, "the map draws terrain runs and markers (\(lines.count))")
                check(Prompt.menuLegend(mm, g).contains("Zoom"), "map legend")
                tap(g, "b")
                check(g.menu == nil, "B closes the map")
            } else { check(false, "M opens the world map") }
            var v = PadSnapshot(); v.view = true
            for _ in 0..<30 { frame(g, v) }
            check(g.menu is MapMenu, "holding View opens the map")
            frame(g)
            g.closeMenu()
            let cam = g.cameraMode
            tap(g, "view")
            check(g.cameraMode == (cam + 1) % 3 && g.menu == nil, "a quick View tap still cycles the camera")
            g.cameraMode = cam
            MapCache.shared.resetMarks()
            MapCache.shared.discover(g, kind: "military_base", x: Int(g.player.pos.x) + 40, z: Int(g.player.pos.z))
            check(MapCache.shared.marks.count == 1, "a nearby base is marked on the map")
            MapCache.shared.discover(g, kind: "military_base", x: Int(g.player.pos.x) + 45, z: Int(g.player.pos.z))
            check(MapCache.shared.marks.count == 1, "the same base isn't marked twice")
            check(MapCache.shade(.ocean, height: 40) != MapCache.shade(.desert, height: 140), "biomes get distinct map colours")
            MapCache.shared.discover(g, kind: "vessel_frigate", x: Int(g.player.pos.x) - 300, z: Int(g.player.pos.z))
            check(MapCache.shared.marks.count == 2 && MapCache.style("vessel_frigate").letter == "F", "vessel patrols are marked with their own letter")
            MapCache.shared.resetMarks()
        }

        // Damage direction indicator.
        g.survival = true
        let rightV = V3(cosf(g.player.yaw), 0, -sinf(g.player.yaw))
        g.hurtPlayer(1, from: g.player.pos + rightV * 3, cause: "test")
        check(CombatHUD.shared.hits.last.map { simd_dot($0.dir, rightV) > 0.9 } ?? false, "a hit from the right marks the right side")
        g.health = 20

        // Rumble requests (logged instead of vibrating while simulated).
        g.survival = true
        PadManager.shared.rumbleLog.removeAll()
        g.damage(2, "test")
        check(!PadManager.shared.rumbleLog.isEmpty, "taking damage rumbles")
        let log = { PadManager.shared.rumbleLog }
        PadManager.shared.rumbleLog.removeAll()
        Feedback.sound(g, .gun(2), 1, at: nil)
        check((log().last ?? 0) > 0.4, "a shotgun blast rumbles hard")
        PadManager.shared.rumbleLog.removeAll()
        Feedback.sound(g, .gun(1), 1, at: nil)
        check((log().last ?? 1) < 0.3 && !log().isEmpty, "chatter gun shots are light ticks")
        PadManager.shared.rumbleLog.removeAll()
        Feedback.sound(g, .gunReload(0), 1, at: nil)
        check(!log().isEmpty, "seating a magazine ticks")
        PadManager.shared.rumbleLog.removeAll()
        Feedback.sound(g, .explode, 1, at: g.player.eye + V3(60, 0, 0))
        check(log().isEmpty, "a far explosion doesn't rumble")
        Feedback.sound(g, .explode, 1, at: g.player.eye + V3(3, 0, 0))
        check((log().last ?? 0) > 0.4, "a close explosion rumbles")

        // Block-targeting assist: two stone blocks in the sky; the highlight holds across the shared edge.
        do {
            let keep = (g.player.pos, g.player.yaw, g.player.pitch, g.player.flying)
            PadManager.shared.forcePad(true)
            g.player.flying = true
            let bx = Int(floor(keep.0.x)), bz = Int(floor(keep.0.z))
            g.player.pos = V3(Float(bx) + 0.5, Float(CH - 40), Float(bz) + 0.5)
            let ey = Int(floor(g.player.eye.y))
            let A = IVec3(bx, ey, bz - 3), B = IVec3(bx + 1, ey, bz - 3)
            g.world.setBlock(A.x, A.y, A.z, STONE)
            g.world.setBlock(B.x, B.y, B.z, STONE)
            func aim(_ px: Float) {
                let d = simd_normalize(V3(px, Float(ey) + 0.5, Float(A.z) + 1) - g.player.eye)
                g.player.yaw = atan2f(-d.x, -d.z)
                g.player.pitch = asinf(d.y)
            }
            func pick() -> IVec3? { AimAssist.sticky(g, g.world.raycast(g.player.eye, g.player.look, maxDist: 5), reach: 5)?.hit }
            AimAssist.last = nil
            aim(Float(A.x) + 0.5)
            check(pick() == A, "aiming at a block targets it")
            aim(Float(B.x) + 0.06)
            check(pick() == A, "the highlight holds just past the block edge")
            aim(Float(B.x) + 0.5)
            check(pick() == B, "moving well onto the neighbour switches to it")
            g.world.setBlock(A.x, A.y, A.z, AIR)
            g.world.setBlock(B.x, B.y, B.z, AIR)
            AimAssist.last = nil
            (g.player.pos, g.player.yaw, g.player.pitch, g.player.flying) = keep
        }

        check(Narrator.plain(Glyph.a.s + " Select   " + Glyph.lb.s + Glyph.rb.s + " Page") == "A Select left bumper right bumper Page",
              "narrator speaks glyphs as button names")

        // Subtitles: a sound to the player's right gets a caption with a right arrow.
        Settings.shared.subtitles = true
        let right = V3(cosf(g.player.yaw), 0, -sinf(g.player.yaw))
        g.sfx(.mobZombie, 1, at: g.player.eye + right * 6)
        let cap = Subtitles.shared.entries.first { $0.label == "Zombie groans" }
        check(cap?.side == 1, "subtitles caption a zombie on the right with a right arrow")
        Settings.shared.subtitles = false
        // One setting, two menus: Options > Audio ("audio_subs") and Options > Accessibility ("subtitles") toggle
        // the same value, and reading it returns (the two used to forward to each other forever).
        let subsMenu = PauseMenu(game: g)
        subsMenu.act("audio_subs", back: false)
        check(Settings.shared.subtitles && AudioSettings.subtitles, "Audio menu turns subtitles on for both settings")
        subsMenu.act("subtitles", back: false)
        check(!Settings.shared.subtitles && !AudioSettings.subtitles, "Accessibility menu turns them off again")
        check(ContextPrompts.items(g).allSatisfy { !$0.isEmpty }, "contextual prompts build (\(ContextPrompts.items(g).count) shown)")

        // Layout: a two-column-free options panel fits a 1080p TV in couch mode with a safe area.
        let couch = HudLayout.couch, safe = Settings.shared.safeArea
        HudLayout.couch = true
        Settings.shared.safeArea = 6
        let L = HudLayout(1920, 1080).fitted(pm)
        check(Float(pm.height) * L.s <= 1080 - 2 * L.insetY && Float(pm.width) * L.s <= 1920, "options panel fits a 1080p TV (scale \(Int(L.s)))")
        HudLayout.couch = couch
        Settings.shared.safeArea = safe

        // Duplicate keys / ids across workstreams, help text and stepping for every option (Audit.swift).
        let (bad, warns) = Audit.run(g)
        for w in warns { print("padtest: audit warning: \(w)") }
        for b in bad { check(false, "audit: \(b)") }
        check(bad.isEmpty, "audit: settings keys, bindings, button mapping, option rows, mob keys (\(bad.count) problems)")

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
        for (i, n) in ["Castle Build", "Survival Island", "Couch World", "Sparkstone Lab"].enumerated() {
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
        case "confirm": pm.go(.worlds); pm.build(); pm.selWorld = "Sparkstone Lab"; pm.go(.confirm); pm.build()
        case "controls": pm.go(.controls); pm.build()
        case "padmap": PadMap.map = [2, 1, 0] + Array(3..<PadMap.count); pm.go(.padmap); pm.build(); cursor = 0
        case "title": pm.page = .title; pm.build()
        case "map":
            MapCache.shared.prefill(g.world.gen, x: Int(g.player.pos.x), z: Int(g.player.pos.z), radius: 700, step: 8)
            MapCache.shared.resetMarks()
            MapCache.shared.discover(g, kind: "military_base", x: Int(g.player.pos.x) + 180, z: Int(g.player.pos.z) - 90)
            MapCache.shared.discover(g, kind: "village", x: Int(g.player.pos.x) - 220, z: Int(g.player.pos.z) + 60)
            g.menu = nil
            g.paused = false
            let mm = MapMenu(game: g)
            mm.zoom = 2
            g.menu = mm
        case "combat", "vehicle":
            // Survival HUD with the minimap, armour wear, two damage marks and either the weapon wheel or a car's gauges.
            g.menu = nil
            g.paused = false
            HudExtras.enabled = true
            MapCache.shared.prefill(g.world.gen, x: Int(g.player.pos.x), z: Int(g.player.pos.z), radius: 72, step: 4)
            g.survival = true
            g.health = 13
            for (i, n) in ["iron_helmet", "iron_chestplate", "iron_leggings", "iron_boots"].enumerated() where Items.has(n) {
                g.inventory.armor[i] = ItemStack(Items.id(n), 1)
                g.inventory.armor[i].damage = [20, 140, 60, 170][i]
            }
            let r = V3(cosf(g.player.yaw), 0, -sinf(g.player.yaw)), f = V3(-sinf(g.player.yaw), 0, -cosf(g.player.yaw))
            CombatHUD.shared.hurt(g, from: g.player.pos + r * 4, amount: 4)
            CombatHUD.shared.hurt(g, from: g.player.pos - f * 4 - r * 2, amount: 2)
            if name == "combat" {
                for (i, n) in ["gun_rifle", "gun_shotgun", "gun_smg", "gun_sniper", "gun_launcher"].enumerated() where Items.has(n) {
                    g.inventory.main[[0, 1, 12, 20, 30][i]] = ItemStack(Items.id(n), 1)
                }
                g.select(0)
                WeaponWheel.shared.showForSnapshot(g, pick: 1)
            } else {
                let helm = ShipTest.place(g.world, "car", near: g.player.pos)
                if let car = g.world.ships.assemble(at: helm, game: g).0 {
                    g.startPiloting(car)
                    car.throttle = 0.7
                    car.vel = f * 9
                }
            }
        default: pm.go(.options); pm.cat = .video; pm.build(); cursor = 1
        }
        WorldStore.base = old
        try? fm.removeItem(at: tmp)
        if let m = g.menu, cursor < m.slots.count { g.menuCursor = cursor; g.menuHover = m.slots[cursor] }
        g.input.mouseX = -1
    }
}
