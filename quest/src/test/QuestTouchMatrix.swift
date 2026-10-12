import Foundation
import simd
import Metal
import CVulkan

// Input conflicts on the headset (scorecard "Input conflicts": Quest Touch bindings were not covered; the Mac's
// --inputmatrix does the gamepad). In each context (on foot, riding a horse, in a boat, at a deck gun, swimming, flying in creative, the
// inventory open) every Touch control is tapped and held through the real VR path (SimXR -> QuestRig ->
// QuestControls -> Game.tick, as QuestSim), and the game state it changed is recorded (menu, pause, hotbar, camera,
// mount, flight, sneak, jump, dropped items). A press that changes two things at once is a conflict. Runs with
// `questcheck --questsim` (lavapipe).
enum QuestTouchMatrix {
    struct State {
        var menu = "", paused = false, selected = 0, camera = 0, riding = false, flying = false
        var sneaking = false, items = 0, carried = 0, y: Float = 0, wheel = false, gun = false
    }
    static func state(_ g: Game) -> State {
        var s = State()
        s.menu = g.menu.map { "\(type(of: $0))" } ?? ""
        s.paused = g.paused; s.selected = g.selected; s.camera = g.cameraMode
        s.riding = g.riding != nil
        s.flying = g.player.flying; s.sneaking = g.player.sneaking
        // Drops near the player and what it carries: a drop is both (an item placed or used only lowers what it carries).
        s.items = g.drops.items.filter { simd_length($0.pos - g.player.pos) < 6 }.count
        s.carried = g.inventory.main.slots.reduce(0) { $0 + ($1.isEmpty ? 0 : $1.count) }
        s.y = g.player.pos.y
        s.wheel = WeaponWheel.shared.open
        s.gun = Turrets.shared.manned != nil
        return s
    }
    static func diff(_ a: State, _ b: State, swimming: Bool) -> [String] {
        var e: [String] = []
        if a.menu != b.menu { e.append(b.menu.isEmpty ? "close \(a.menu)" : "open \(b.menu)") }
        if a.paused != b.paused && a.menu == b.menu { e.append(b.paused ? "pause" : "unpause") }
        if a.selected != b.selected { e.append("hotbar") }
        if a.camera != b.camera { e.append("camera") }
        if a.riding != b.riding { e.append(b.riding ? "mount" : "dismount") }
        if a.gun != b.gun { e.append(b.gun ? "man gun" : "leave gun") }
        if a.flying != b.flying { e.append("flight") }
        if a.sneaking != b.sneaking && !swimming && !a.flying { e.append("sneak") }
        if b.items > a.items && b.carried < a.carried { e.append("drop item") }
        else if b.carried < a.carried { e.append("use item") }
        if b.wheel != a.wheel { e.append("weapon wheel") }
        if b.y - a.y > 0.4 && !a.riding && !swimming && !a.flying { e.append("jump/rise") }
        return e
    }
    // The Touch controls: (name, set it on the two hands).
    static let controls: [(String, (inout XRHand, inout XRHand) -> Void)] = [
        ("A", { _, r in r.button1 = true }), ("B", { _, r in r.button2 = true }),
        ("X", { l, _ in l.button1 = true }), ("Y", { l, _ in l.button2 = true }),
        ("right trigger", { _, r in r.trigger = 1 }), ("left trigger", { l, _ in l.trigger = 1 }),
        ("right grip", { _, r in r.squeeze = 1 }), ("left grip", { l, _ in l.squeeze = 1 }),
        ("right stick click", { _, r in r.stickClick = true }), ("left stick click", { l, _ in l.stickClick = true }),
        ("menu", { l, _ in l.menu = true }),
    ]

    static func run(game g: Game, ctx: VkContext, check: (Bool, String) -> Void) throws {
        let scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
        try scene.uploadTextures()
        let host = SimHost(scene: scene)
        let sim = host.sim, rig = host.rig
        let qc = QuestControls(app: host, game: g, panel: try HudPanel(scene: scene, width: QuestControls.panelW, height: QuestControls.panelH))
        host.controls = qc
        let w = g.world
        let keepSurvival = g.survival, keepPos = g.player.pos, keepSel = g.selected
        let keep0 = g.inventory.main[0]
        var placed: [(IVec3, BlockID)] = []
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { placed.append((IVec3(x, y, z), w.block(x, y, z))); w.setBlock(x, y, z, b) }
        defer {
            if g.menu != nil { g.closeMenu() }
            g.riding = nil; g.paused = false; g.survival = keepSurvival; g.player.flying = false
            g.player.pos = keepPos; g.player.vel = .zero; g.selected = keepSel; g.inventory.main[0] = keep0
            for (p, b) in placed.reversed() { w.setBlock(p.x, p.y, p.z, b) }
            g.mobs.mobs.removeAll { $0.kind == .horse && $0.owner == true || $0.kind == .boat || $0.kind == .deckGun }; Turrets.shared.manned = nil
            PadManager.shared.touch = nil
            scene.waitIdle()
        }
        let dt: Float = 1.0 / 72
        func idle() -> (XRHand, XRHand) {
            var h = [XRHand(), XRHand()]
            for i in 0..<2 {
                h[i].aimValid = true; h[i].gripValid = true
                h[i].aimPos = sim.headPos + V3(i == 0 ? -0.2 : 0.2, -0.45, -0.3); h[i].gripPos = h[i].aimPos
                // Pointing down at the floor ahead: nothing to break or use in reach but the floor.
                h[i].aimRot = simd_quatf(angle: -0.9, axis: V3(1, 0, 0)); h[i].gripRot = h[i].aimRot
            }
            return (h[0], h[1])
        }
        func frame(_ press: ((inout XRHand, inout XRHand) -> Void)? = nil) {
            var (l, r) = idle()
            press?(&l, &r)
            sim.hands[0] = l; sim.hands[1] = r
            rig.update(xr: sim, game: g)
            qc.update(dt: dt)
            g.tick(Double(dt))
            qc.afterTick(dt: dt)
        }
        // A floor of stone with a pool at one end, high over the spawn.
        let bx = Int(floor(keepPos.x)) - 30, bz = Int(floor(keepPos.z)) - 30
        let py = min(CH - 12, w.topY(bx, bz) + 30)
        for z in (bz - 8)...(bz + 8) { for x in (bx - 8)...(bx + 8) {
            let pool = x >= bx + 3 && x <= bx + 7 && z >= bz - 2 && z <= bz + 2
            let rim = !pool && x >= bx + 2 && z >= bz - 3 && z <= bz + 3      // (or the pool runs over the floor)
            put(x, py, z, STONE)
            for y in (py + 1)...(py + 5) { put(x, y, z, AIR) }
            if rim { put(x, py + 1, z, STONE) }
            if pool { put(x, py, z, WATER); put(x, py - 1, z, STONE); put(x, py + 1, z, WATER) }
        } }
        let start = V3(Float(bx) + 0.5, Float(py + 1), Float(bz) + 0.5)
        let poolAt = V3(Float(bx + 5) + 0.5, Float(py) + 0.2, Float(bz) + 0.5)
        var horse: Mob?, gun: Mob?
        var why = "", toast = ""
        let toast0 = g.onToast
        g.onToast = { t in toast = t; toast0?(t) }
        defer { g.onToast = toast0 }
        func reset() {
            qc.clearLatches()                  // (no latch or hold carried over from the last control)
            for _ in 0..<3 { if g.menu != nil { g.closeMenu() }; frame() }
            if let h = horse { h.health = 0; g.mobs.mobs.removeAll { $0 === h }; horse = nil }
            Turrets.shared.manned = nil
            if let gm = gun { g.mobs.mobs.removeAll { $0 === gm }; gun = nil }
            g.riding = nil; g.paused = false; g.cameraMode = 0; g.player.flying = false; g.player.sneaking = false
            g.survival = true
            g.inventory.main[0] = ItemStack(Items.id("cobblestone"), 16); g.selected = 0
            g.player.pos = start; g.player.vel = .zero
            rig.needsRecenter = true
            for _ in 0..<30 { frame() }
        }
        let contexts: [(String, () -> Bool)] = [
            ("on foot", { true }),
            ("riding horse", {
                let m = Mob(.horse, at: start + V3(1.5, 0, 0)); m.saddled = true; m.owner = true
                g.mobs.mobs.append(m); horse = m
                g.riding = m; g.player.pos = m.pos + V3(0, m.height * 0.75, 0)
                for i in 0..<5 {
                    frame()
                    if g.riding == nil { why = "thrown at frame \(i): pad b \(PadManager.shared.touch?.b ?? false), sneaking \(g.player.sneaking), toast '\(toast)'"; break }
                }
                return g.riding != nil
            }),
            ("in a boat", {
                let m = Mob(.boat, at: poolAt + V3(0, 0.6, 0)); g.mobs.mobs.append(m); horse = m
                g.riding = m; g.player.pos = m.pos + V3(0, 0.4, 0)
                for _ in 0..<5 { frame() }
                return g.riding === m
            }),
            ("at a deck gun", {
                let m = Mob(.deckGun, at: start + V3(-4, 0, -4)); g.mobs.mobs.append(m); gun = m
                Turrets.shared.mount(g, m)
                for _ in 0..<5 { frame() }
                return Turrets.shared.manned === m
            }),
            ("swimming", {
                g.player.pos = poolAt
                for _ in 0..<20 { frame() }
                return g.player.inWater
            }),
            ("flying (creative)", {
                g.survival = false; g.player.flying = true; g.player.pos = start + V3(0, 2, 0)
                for _ in 0..<5 { frame() }
                return g.player.flying
            }),
            ("inventory open", {
                g.openInventory()
                for _ in 0..<6 { frame() }
                return g.menu != nil
            }),
        ]
        var conflicts: [String] = [], failed: [String] = [], rows: [String] = []
        for (name, press) in controls {
            var row: [String] = []
            for (cname, setup) in contexts {
                var parts: [String] = []
                for hold in [false, true] {
                    reset()
                    guard setup() else { failed.append("\(cname) before \(name) \(hold ? "hold" : "tap") (\(why))"); parts.append("(context failed)"); continue }
                    let swimming = g.player.inWater
                    let s0 = state(g)
                    for _ in 0..<(hold ? 58 : 2) { frame(press) }
                    for _ in 0..<12 { frame() }
                    let e = diff(s0, state(g), swimming: swimming)
                    parts.append((hold ? "hold " : "") + (e.isEmpty ? "-" : e.joined(separator: " + ")))
                    if e.count >= 2 { conflicts.append("\(cname), \(name) \(hold ? "hold" : "tap"): \(e.joined(separator: " + "))") }
                }
                row.append("\(cname): " + parts.joined(separator: "; "))
            }
            rows.append("\(name) | " + row.joined(separator: " | "))
        }
        for r in rows { print("touchmatrix " + r) }
        for c in conflicts { print("touchmatrix CONFLICT: " + c) }
        let ctxFailed = Set(failed)
        check(ctxFailed.isEmpty, "touch matrix: every context set up (\(contexts.count))\(ctxFailed.isEmpty ? "" : "; failed: " + ctxFailed.sorted().joined(separator: ", "))")
        check(conflicts.isEmpty, "touch matrix: no Touch press does two things at once (\(controls.count) controls x tap/hold x \(contexts.count) contexts)\(conflicts.isEmpty ? "" : ": " + conflicts.prefix(6).joined(separator: "; "))")
    }
}
