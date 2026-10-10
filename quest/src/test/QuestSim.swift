import Foundation
import simd
import Metal
import CVulkan

// Headless test of the VR play path: scripted head and controller poses (SimXR) drive the real QuestRig,
// QuestControls, Game.tick and renderer. Checks locomotion, snap turning, roomscale, hand-ray aiming, breaking and
// placing, opening the inventory and pointing at it with the laser; renders the inventory panel and the world to PNG.
final class SimXR: XRInput {
    var hands = [XRHand(), XRHand()]
    var headPos = V3(0, 1.7, 0)
    var headRot = simd_quatf()
    var floorSpace: Bool { true }
    var hapticCount = 0
    func eyePose(_ i: Int) -> (V3, simd_quatf) { (headPos + headRot.act(V3(i == 0 ? -0.032 : 0.032, 0, 0)), headRot) }
    func fovTangents(_ i: Int) -> (Float, Float, Float, Float) { (-1, 1, 1, -1) }
    func haptic(_ hand: Int, amplitude: Float, seconds: Float, frequency: Float) { hapticCount += 1 }
}

final class SimHost: QuestHost {
    weak var controls: QuestControls?
    func controlsPanelCenter() -> V3 { controls?.panelWorldCenter ?? .zero }
    func controlsHint() -> String? { controls?.hint }
    let sim = SimXR()
    let rig = QuestRig()
    let scene: SceneRenderer
    var input: XRInput { sim }
    var fps: Double { 72 }
    init(scene: SceneRenderer) { self.scene = scene }
}

enum QuestSim {
    static func run(game: Game, ctx: VkContext, out: String, check: (Bool, String) -> Void) throws {
        let scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
        try scene.uploadTextures()
        let host = SimHost(scene: scene)
        let sim = host.sim, rig = host.rig
        let controls = QuestControls(app: host, game: game, panel: try HudPanel(scene: scene, width: QuestControls.panelW, height: QuestControls.panelH))
        host.controls = controls
        let wr = WorldRenderer(scene: scene, game: game)
        wr.extraOpaque = { s, eye in AllocCount.measure("drawOpaque") { controls.drawOpaque(s, eye: eye) } }
        wr.extraOverlay = { s, eye in AllocCount.measure("drawOverlay") { controls.drawOverlay(s, eye: eye) } }
        wr.prePass = { s in AllocCount.measure("recordPanel") { controls.recordPanel(s) } }
        game.paused = false
        game.survival = false
        game.player.flying = false
        rig.needsRecenter = true
        rig.bodyYaw = 0
        game.player.yaw = 0
        let dt: Float = 1.0 / 72
        ShipManager.stepRate = 72; ShipManager.stepSlack = 0.2 / 72       // as QuestApp: one ship step per frame
        func idleHands() {
            for h in 0..<2 {
                var hd = XRHand()
                hd.aimValid = true; hd.gripValid = true
                hd.aimPos = sim.headPos + V3(h == 0 ? -0.2 : 0.2, -0.45, -0.3)
                hd.gripPos = hd.aimPos
                hd.aimRot = simd_quatf(); hd.gripRot = simd_quatf()
                sim.hands[h] = hd
            }
        }
        func frames(_ n: Int, _ body: (Int) -> Void = { _ in }) {
            for i in 0..<n {
                body(i)
                AllocCount.measure("rig.update") { rig.update(xr: sim, game: game) }
                AllocCount.measure("controls.update") { controls.update(dt: dt) }
                game.tick(Double(dt))
                game.world.update(center: game.player.pos)
                AllocCount.measure("controls.afterTick") { controls.afterTick(dt: dt) }
            }
        }
        // A 41 x 41 stone platform 30 blocks above the spawn, so locomotion doesn't depend on the terrain (jungle trees).
        let base = game.player.pos
        let py = Int(base.y) + 30
        for dz in -20...20 { for dx in -20...20 {
            game.world.setBlock(Int(base.x) + dx, py, Int(base.z) + dz, STONE)
            for k in 1...4 { game.world.setBlock(Int(base.x) + dx, py + k, Int(base.z) + dz, AIR) }
        } }
        game.player.pos = V3(Float(Int(base.x)) + 0.5, Float(py + 1), Float(Int(base.z)) + 0.5)
        game.player.vel = .zero
        // Settle on the platform.
        idleHands()
        frames(72)
        PadManager.shared.touch = nil

        // 1. Walk: left stick forward for 2 s with the left controller pointing -Z: the player goes -Z.
        let p0 = game.player.pos
        frames(144) { _ in idleHands(); sim.hands[0].stick = V2(0, 1) }
        frames(10) { _ in idleHands() }
        let d = game.player.pos - p0
        check(-d.z > 3 && abs(d.x) < 1.5, String(format: "VR walk: left stick forward moved (%.2f, %.2f) (want -Z)", d.x, d.z))
        // 1b. Sprint through the device path (playtest v78: "no faster than walking"): in each direction a full push
        // walks; clicking the pushed stick sprints, at least 1.5x that walk, and keeps sprinting after the click is let go.
        let sprintFrom = game.player.pos
        for (name, dir) in [("forward", V2(0.2, 0.88)), ("back", V2(0, -0.9)), ("left", V2(-0.9, 0)), ("right", V2(0.64, 0.64))] {
            game.player.pos = sprintFrom; game.player.vel = .zero
            frames(20) { _ in idleHands() }
            frames(12) { _ in idleHands(); sim.hands[0].stick = dir }
            let w0 = game.player.pos
            var walkSprinted = false
            frames(72) { _ in idleHands(); sim.hands[0].stick = dir; walkSprinted = walkSprinted || game.player.sprinting }
            let walk = simd_length(V2(game.player.pos.x - w0.x, game.player.pos.z - w0.z))
            game.player.pos = sprintFrom; game.player.vel = .zero
            frames(20) { _ in idleHands() }
            frames(12) { i in idleHands(); sim.hands[0].stick = dir; sim.hands[0].stickClick = i < 4 }
            let s0 = game.player.pos
            var sprinted = true
            frames(72) { _ in idleHands(); sim.hands[0].stick = dir; sprinted = sprinted && game.player.sprinting }
            let run = simd_length(V2(game.player.pos.x - s0.x, game.player.pos.z - s0.z))
            check(!walkSprinted, "VR walk (\(name)): a full push alone must walk, not sprint")
            check(sprinted && !game.player.sneaking, "VR sprint (\(name)): click held the sprint \(sprinted), sneaking \(game.player.sneaking)")
            check(run >= walk * 1.5, String(format: "VR sprint (%@): %.2f blocks in 1 s vs walk %.2f (x%.2f, want >= 1.5)", name, run, walk, run / max(walk, 0.01)))
        }
        frames(10) { _ in idleHands() }
        game.player.pos = sprintFrom; game.player.vel = .zero      // back where the walk ended: the aim checks need its view
        frames(10) { _ in idleHands() }

        QuestSettings.smoothTurn = false   // smooth is the default; these checks are for the snap comfort option
        // 2. Snap turn: right stick right turns the body 45 degrees clockwise (yaw decreases).
        let y0 = rig.bodyYaw
        frames(3) { _ in idleHands(); sim.hands[1].stick = V2(1, 0) }
        frames(3) { _ in idleHands() }
        let turned = (y0 - rig.bodyYaw) * 180 / .pi
        check(abs(turned - 45) < 1, String(format: "VR snap turn: %.1f degrees", turned))
        // Walking now goes along the turned direction (-Z turned 45 degrees right = toward +X, -Z).
        let p1 = game.player.pos
        frames(100) { _ in idleHands(); sim.hands[0].stick = V2(0, 1) }
        frames(10) { _ in idleHands() }
        let d1 = game.player.pos - p1
        check(d1.x > 1 && -d1.z > 1, String(format: "VR walk after the turn moved (%.2f, %.2f) (want +X -Z)", d1.x, d1.z))

        // 3. Roomscale: stepping 0.5 m to the right (tracking +X) moves the player 0.5 along the body's right.
        let p2 = game.player.pos
        sim.headPos.x += 0.5
        frames(2) { _ in idleHands() }
        let right = rig.yawRot.act(V3(1, 0, 0))
        let moved = simd_dot(game.player.pos - p2, right)
        check(abs(moved - 0.5) < 0.12, String(format: "VR roomscale: stepped %.2f m along the body's right (want 0.5)", moved))

        // 4. Aim: the right ray pointing down-forward picks the block it hits (not what the head looks at).
        sim.headRot = simd_quatf()                           // head looks straight ahead (horizontal)
        let down = simd_quatf(angle: -0.9, axis: V3(1, 0, 0))
        frames(3) { _ in idleHands(); sim.hands[1].aimRot = down }
        let o = rig.toWorld(sim.hands[1].aimPos)
        let dir = simd_normalize(rig.toWorldDir(down.act(V3(0, 0, -1))))
        let want = game.world.raycast(o, dir, maxDist: 8)
        check(want != nil && game.target?.hit == want?.hit,
              "VR aim: game target \(game.target.map { "\($0.hit)" } ?? "nil") = hand ray hit \(want.map { "\($0.hit)" } ?? "nil")")

        // 5. Break: the right trigger breaks the targeted block (creative; Swing Mode off).
        QuestSettings.swingMode = false
        var brokenCell: IVec3?
        if let t = game.target?.hit {
            brokenCell = t
            let before = game.world.block(t.x, t.y, t.z)
            frames(6) { _ in idleHands(); sim.hands[1].aimRot = down; sim.hands[1].trigger = 1 }
            frames(10) { _ in idleHands(); sim.hands[1].aimRot = down }
            let after = game.world.block(t.x, t.y, t.z)
            check(before != AIR && after != before, "VR break: right trigger broke \(Blocks.name(before)) at \(t) (now \(Blocks.name(after)))")
        }

        // 5b. Swing melee (Oct 10 redesign, docs/status/vr-melee.md): hand movement alone never breaks or uses anything;
        // only the sword's blade physically hitting a mob, fast enough and within reach, hurts it.
        QuestSettings.swingMode = true
        if let c = brokenCell { game.world.setBlock(c.x, c.y, c.z, STONE) }        // fill the hole the trigger test left
        swingMelee(game: game, host: host, controls: controls, py: py, down: down, frames: frames, check: check)
        if let c = brokenCell { game.world.setBlock(c.x, c.y, c.z, STONE) }        // the platform stays whole for the next checks

        // 6. Place: the left trigger with a block in hand places it against the targeted face.
        game.inventory.held = ItemStack(Items.id("gold_block"), 64)
        frames(3) { _ in idleHands(); sim.hands[1].aimRot = down }
        if let t = game.target {
            let at = IVec3(t.hit.x + t.normal.x, t.hit.y + t.normal.y, t.hit.z + t.normal.z)
            frames(4) { _ in idleHands(); sim.hands[1].aimRot = down; sim.hands[0].trigger = 1 }
            frames(6) { _ in idleHands(); sim.hands[1].aimRot = down }
            check(game.world.block(at.x, at.y, at.z) == Blocks.id("gold_block"), "VR place: left trigger placed a gold block at \(at)")
        } else { check(false, "VR place: no target") }

        let standPos = game.player.pos
        // 7. Inventory: holding Y (left upper button) opens it (a tap toggles flying); the panel sits in front; the laser drives the mouse.
        frames(36) { _ in idleHands(); sim.hands[0].button2 = true }
        frames(3) { _ in idleHands() }
        check(game.menu != nil, "VR inventory: Y hold opened \(game.menu.map { String(describing: type(of: $0)) } ?? "nothing")")
        // Point the right ray at the panel centre (1.15 m ahead, 0.1 m down of the head when it opened).
        let haptics0 = sim.hapticCount
        var hitTarget = V3.zero
        frames(4) { _ in
            idleHands()
            let hand = sim.headPos + V3(0.2, -0.45, -0.3)
            let target = sim.headPos + V3(0, -0.1, -1.15)
            hitTarget = target
            sim.hands[1].aimPos = hand
            sim.hands[1].aimRot = simd_quatf(from: V3(0, 0, -1), to: simd_normalize(target - hand))
        }
        _ = hitTarget
        let mx = game.input.mouseX, my = game.input.mouseY
        let cx = Float(QuestControls.panelW) / 2, cy = Float(QuestControls.panelH) / 2
        check(abs(mx - cx) < 30 && abs(my - cy) < 30, String(format: "VR laser on the menu panel: mouse at (%.0f, %.0f) (want ~%.0f, %.0f)", mx, my, cx, cy))
        frames(2) { i in
            idleHands()
            let hand = sim.headPos + V3(0.2, -0.45, -0.3)
            sim.hands[1].aimPos = hand
            sim.hands[1].aimRot = simd_quatf(from: V3(0, 0, -1), to: simd_normalize(sim.headPos + V3(0, -0.1, -1.15) - hand))
            sim.hands[1].trigger = i == 0 ? 1 : 0
        }
        check(sim.hapticCount > haptics0, "VR laser click buzzes the controller (\(sim.hapticCount - haptics0) pulses)")

        // Render the inventory panel over the world, then close it and render play.
        try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out.replacingOccurrences(of: ".png", with: "_menu.png"))
        frames(3) { _ in idleHands(); sim.hands[1].button2 = true }      // B closes
        frames(3) { _ in idleHands() }
        check(game.menu == nil, "VR inventory: B closed it")

        // 7b. A town shop on the menu panel (Shops.swift): the general store's counter, keeper in front, at noon.
        do {
            let savedTime = game.time
            game.time = 0.25 * DAY_LENGTH
            let fw = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
            let keeper = TownTests.keeper(game, .general, at: game.player.pos + fw * 2)
            keeper.face(game.player.pos)
            let savedMobs = game.mobs.mobs
            game.mobs.mobs.append(keeper); game.mobs.rebuildIndex()
            _ = game.talkToTownsperson(keeper)
            frames(3) { _ in idleHands() }
            check(game.menu is ShopMenu, "VR shop: talking to the storekeeper opens \(game.menu.map { String(describing: type(of: $0)) } ?? "nothing")")
            try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out.replacingOccurrences(of: ".png", with: "_shop.png"))
            frames(3) { _ in idleHands(); sim.hands[1].button2 = true }
            frames(3) { _ in idleHands() }
            check(game.menu == nil, "VR shop: B closed it")
            game.mobs.mobs = savedMobs; game.mobs.rebuildIndex()
            game.time = savedTime
        }

        // 8. Riding a moving ship (the Skyward Frigate, no crew): the player stays aboard, the rig turns with the hull,
        // the HUD and menu panels stay with the user, the hull moves on every frame, and grip opens a chest on deck.
        try shipRide(game: game, host: host, frames: frames, check: check) {
            try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out.replacingOccurrences(of: ".png", with: "_ship.png"))
        }

        // 8b. Weapon wheel: hold the right stick click, push the stick toward a gun, let go: it is equipped and the body
        // did not snap-turn meanwhile.
        let rifle = Items.id("gun_rifle"), sniper = Items.id("gun_sniper")
        game.inventory.main[0] = ItemStack(rifle, 1)
        game.inventory.main[1] = ItemStack(sniper, 1)
        game.select(0)
        frames(3) { _ in idleHands() }
        let yW = rig.bodyYaw
        var opened = false
        frames(30) { _ in idleHands(); sim.hands[1].stickClick = true }
        opened = WeaponWheel.shared.open
        frames(20) { _ in idleHands(); sim.hands[1].stickClick = true; sim.hands[1].stick = V2(0, -1) }   // the second of two: down
        frames(3) { _ in idleHands() }
        check(opened && Items.key(game.held.item) == "gun_sniper" && abs(rig.bodyYaw - yW) < 1e-4,
              "VR weapon wheel: opened \(opened), picked \(Items.key(game.held.item)), body turned \(rig.bodyYaw - yW) rad")
        game.inventory.main[0] = .empty; game.inventory.main[1] = .empty

        // 8c. Tapping Y toggles flying.
        let flew = game.player.flying
        let flyPos = game.player.pos
        frames(3) { _ in idleHands(); sim.hands[0].button2 = true }
        frames(6) { _ in idleHands() }
        check(game.player.flying != flew, "VR fly: a Y tap toggled flying (\(flew) -> \(game.player.flying)) y \(flyPos.y) -> \(game.player.pos.y)")
        game.player.flying = flew
        game.player.pos = flyPos; game.player.vel = .zero

        // 8d. Holding X swaps the offhand (a torch from the hand to the offhand).
        let torch = Items.id("torch")
        game.inventory.held = ItemStack(torch, 8)
        game.inventory.offhand[0] = .empty
        frames(50) { _ in idleHands(); sim.hands[0].button1 = true }
        frames(5) { _ in idleHands() }
        check(game.inventory.offhand[0].item == torch, "VR offhand: holding X swapped the torch to the offhand (offhand \(Items.key(game.inventory.offhand[0].item)))")
        game.inventory.offhand[0] = .empty

        // 9. The pause menu's VR page: the snap angle option changes the next snap turn.
        QuestOptions.install(QuestOptions.Hooks(recenter: { rig.needsRecenter = true }))
        let pm = PauseMenu(game: game)
        game.openMenu(pm)
        game.paused = true
        check(pm.rows.contains { $0.1 == "host:vr" } && !pm.rows.contains { $0.1 == "photo" },
              "VR options: the pause menu lists \(PauseMenu.hostEntry?.0 ?? "-") (and no Photo Mode)")
        frames(30) { _ in idleHands(); sim.hands[1].stick = V2(0, -1) }      // the right stick scrolls the list
        check(pm.scroll > 0, "VR menus: the right stick scrolls the pause menu (scroll \(pm.scroll))")
        frames(3) { _ in idleHands() }
        pm.act("host:vr", back: false)
        pm.act("host:touch", back: false)
        check(pm.title == "Touch Controls" && pm.rows.count > 8, "VR options: the Touch Controls page lists \(pm.rows.count) rows")
        frames(2) { _ in idleHands() }
        try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out.replacingOccurrences(of: ".png", with: "_touch.png"))
        pm.act("host:vr", back: false)
        let snap0 = QuestSettings.snapAngle
        pm.act("q_snap", back: false)
        check(pm.title == "VR Comfort & Controls" && QuestSettings.snapAngle == 60 && pm.rows.contains { $0.0.hasPrefix("Snap Angle: 60") },
              "VR options: Snap Angle \(QuestOptions.angle(snap0)) -> \(QuestOptions.angle(QuestSettings.snapAngle)) (page \(pm.title))")
        pm.act("back", back: false)
        game.closeMenu(); game.paused = false
        frames(3) { _ in idleHands() }
        let yS = rig.bodyYaw
        frames(3) { _ in idleHands(); sim.hands[1].stick = V2(1, 0) }
        frames(3) { _ in idleHands() }
        var turnedS = (yS - rig.bodyYaw) * 180 / .pi
        if turnedS < -180 { turnedS += 360 }; if turnedS > 180 { turnedS -= 360 }
        check(abs(turnedS - 60) < 1, String(format: "VR options: the next snap turn went %.1f degrees", turnedS))
        QuestSettings.snapAngle = snap0; QuestSettings.smoothTurn = true

        // 9b. Gliding steers with the head: the look follows it even with the hand pointing elsewhere.
        let headDown = simd_quatf(angle: -0.5, axis: V3(1, 0, 0))
        frames(2) { _ in
            idleHands(); sim.headRot = headDown
            sim.hands[1].aimRot = simd_quatf(angle: 0.6, axis: V3(1, 0, 0))
            game.player.gliding = true
        }
        let glidePitch = game.player.pitch
        game.player.gliding = false
        sim.headRot = simd_quatf()
        frames(2) { _ in idleHands() }
        check(abs(glidePitch + 0.5) < 0.05, String(format: "VR gliding: the look follows the head (pitch %.2f, head -0.50)", glidePitch))

        // 9b2. Head in a wall: a solid block where the head is fades the view to black; gone, the view clears.
        game.player.pos = standPos; game.player.vel = .zero
        frames(8) { _ in idleHands() }
        let hw = rig.headWorld
        let hc = (Int(floor(hw.x)), Int(floor(hw.y)), Int(floor(hw.z)))
        let hwBefore = game.world.block(hc.0, hc.1, hc.2)
        game.world.setBlock(hc.0, hc.1, hc.2, STONE)
        frames(12) { _ in idleHands() }
        let fadeIn = controls.wallFade
        game.world.setBlock(hc.0, hc.1, hc.2, hwBefore)
        frames(30) { _ in idleHands() }
        check(fadeIn > 0.8 && controls.wallFade < 0.05,
              String(format: "VR head in a wall: the view fades (%.2f) and clears once out (%.2f)", fadeIn, controls.wallFade)
              + " alive \(game.alive) fly \(game.player.flying) menu \(game.menu.map { "\(type(of: $0))" } ?? "none") paused \(game.paused) before \(hwBefore) head \(hw) now \(rig.headWorld) feet \(game.player.pos)")

        // 9c. Death and respawn: the death screen opens as the menu panel in front, its button (laser + trigger)
        // respawns, the HUD comes back and the camera follows the player to the spawn.
        game.survival = true
        game.player.flying = false
        frames(2) { _ in idleHands() }
        game.damage(1000, "the harness", bypassArmor: true)
        frames(30) { _ in idleHands() }
        let died = game.menu is DeathMenu
        let deathPanel = simd_length(host.controlsPanelCenter() - rig.headWorld)
        if let dm = game.menu as? DeathMenu { dm.buttonPressed(0) }
        frames(10) { _ in idleHands() }
        let backAlive = game.menu == nil && game.health > 0
        let camOK = simd_length(rig.headWorld - game.player.eye) < 0.6
        check(died && deathPanel < 1.5 && backAlive && camOK,
              String(format: "VR death: death screen %@ (panel %.2f m away), respawned %@, camera at the player %@",
                     died ? "shown" : "missing", deathPanel, backAlive ? "yes" : "no", camOK ? "yes" : "no"))
        game.survival = false

        // 9d. Stepping onto a slab: the camera rises over a few frames, not in one (the world jumping is a VR discomfort).
        do {
            let c = V3(Float(Int(base.x)) + 0.5, Float(py + 1), Float(Int(base.z)) + 0.5)
            game.player.pos = c; game.player.vel = .zero
            rig.bodyYaw = 0
            let slab = Blocks.has("stone_slab") ? Blocks.id("stone_slab") : Blocks.id("oak_slab")
            for dz in 2...8 { for dx in -1...1 { game.world.setBlock(Int(c.x) + dx, py + 1, Int(c.z) - dz, slab) } }
            frames(20) { _ in idleHands() }
            var lastY = rig.headWorld.y, maxStep: Float = 0
            let y0 = game.player.pos.y
            for _ in 0..<60 {
                frames(1) { _ in idleHands(); sim.hands[0].stick = V2(0, 0.6) }
                maxStep = max(maxStep, abs(rig.headWorld.y - lastY)); lastY = rig.headWorld.y
            }
            frames(10) { _ in idleHands() }
            let rose = game.player.pos.y - y0
            check(rose > 0.4 && maxStep < 0.2, String(format: "VR step smoothing: stepped up %.2f, largest camera move in one frame %.2f", rose, maxStep))
            for dz in 2...8 { for dx in -1...1 { game.world.setBlock(Int(c.x) + dx, py + 1, Int(c.z) - dz, AIR) } }
        }

        // 10. Teleport: the left stick held forward aims an arc at the platform ahead; releasing jumps there.
        QuestSettings.teleport = true
        game.player.pos = V3(Float(Int(base.x)) + 0.5, Float(py + 1), Float(Int(base.z)) + 0.5)   // platform centre
        game.player.vel = .zero
        frames(30) { _ in idleHands() }
        let tp0 = game.player.pos
        // Aim along world +X, 14 degrees up (the arc lands ~11 blocks out, on the platform).
        func aimTele() {
            idleHands()
            let w = simd_normalize(V3(1, 0.25, 0))
            sim.hands[0].aimRot = simd_quatf(from: V3(0, 0, -1), to: rig.yawRot.inverse.act(w))
            sim.hands[0].stick = V2(0, 1)
        }
        frames(10) { _ in aimTele() }
        let aiming = controls.teleAiming
        print("questsim: teleport arc \(controls.teleArcCount) points, target \(controls.teleTargetText)")
        frames(3) { _ in idleHands() }
        let jump = simd_length(V2(game.player.pos.x - tp0.x, game.player.pos.z - tp0.z))
        check(aiming && controls.teleports == 1 && jump > 2 && jump <= QuestControls.teleportRange + 1,
              String(format: "VR teleport: arc aimed (%@), released, landed %.1f blocks away (%d jumps, on ground %@)",
                     aiming ? "yes" : "no", jump, controls.teleports, game.player.onGround ? "yes" : "no"))
        QuestSettings.teleport = false

        // Lying down: Reclined Mode + holding Menu levels world, horizon, HUD and walking to the gaze (pitch included);
        // a Menu tap still pauses.
        do {
            QuestSettings.reclined = true
            let keepHead = (sim.headPos, sim.headRot)
            sim.headPos = V3(0.1, 0.35, 0.2)
            sim.headRot = simd_quatf(angle: 0.3, axis: V3(0, 1, 0)) * simd_quatf(angle: 1.35, axis: V3(1, 0, 0))   // ~77 deg up
            let rc0 = rig.recenters
            frames(60) { _ in idleHands(); sim.hands[0].menu = true }
            frames(4) { _ in idleHands() }
            check(rig.recenters == rc0 + 1 && !game.paused, "VR reclined: holding Menu recentred once (\(rig.recenters - rc0)) without pausing (\(game.paused))")
            check(abs(rig.headPitch) < 0.03, String(format: "VR reclined: the gaze is level after the recentre (pitch %.3f)", rig.headPitch))
            let gaze = V3(-sinf(rig.headYaw), 0, -cosf(rig.headYaw))
            frames(20) { _ in idleHands() }
            let toHud = simd_normalize(controls.panelWorldCenter - rig.headWorld)
            check(simd_dot(toHud, gaze) > 0.8 && toHud.y < 0 && toHud.y > -0.6,
                  String(format: "VR reclined: the HUD sits ahead and below the levelled gaze (dot %.2f, down %.2f)", simd_dot(toHud, gaze), toHud.y))
            let r0 = game.player.pos
            frames(72) { i in idleHands(); sim.hands[0].stick = V2(0, 1); sim.hands[0].aimRot = simd_quatf(angle: Float(i) * 0.2, axis: V3(0, 1, 0)) }
            frames(10) { _ in idleHands() }
            let mv = game.player.pos - r0
            let flat = simd_normalize(V3(mv.x, 0, mv.z))
            check(simd_length(V2(mv.x, mv.z)) > 2 && simd_dot(flat, gaze) > 0.95,
                  String(format: "VR reclined: the stick walks along the levelled gaze (moved %.2f, %.2f; dot %.2f)", mv.x, mv.z, simd_dot(flat, gaze)))
            frames(3) { _ in idleHands(); sim.hands[0].menu = true }
            frames(4) { _ in idleHands() }
            check(game.paused, "VR reclined: a Menu tap pauses")
            frames(3) { _ in idleHands(); sim.hands[0].menu = true }
            frames(4) { _ in idleHands() }
            game.paused = false; game.menu = nil
            QuestSettings.reclined = false
            (sim.headPos, sim.headRot) = keepHead
            rig.needsRecenter = true
            frames(4) { _ in idleHands() }
        }

        frames(3) { _ in idleHands(); sim.hands[1].aimRot = down }
        try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out)
        // The held sword with Swing Mode off, the hand raised in front of the face (v63: tools must show in the hand).
        do {
            let keep = (game.inventory.held, QuestSettings.swingMode)
            game.inventory.held = ItemStack(Items.id("iron_sword"), 1)
            QuestSettings.swingMode = false
            let raised = simd_quatf(angle: 0.35, axis: V3(1, 0, 0))
            frames(3) { _ in
                idleHands()
                sim.hands[1].aimPos = sim.headPos + V3(0.18, -0.22, -0.3); sim.hands[1].gripPos = sim.hands[1].aimPos
                sim.hands[1].aimRot = raised; sim.hands[1].gripRot = raised
            }
            try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out.replacingOccurrences(of: ".png", with: "_held.png"))
            // Natural carry pose (hand at the hip, pointing ahead): the sword and the rifle as a player sees them.
            for (key, name) in [("iron_sword", "_carry_sword.png"), ("gun_rifle", "_carry_gun.png")] {
                game.inventory.held = ItemStack(Items.id(key), 1)
                let carry = simd_quatf(angle: -0.25, axis: V3(1, 0, 0))
                frames(3) { _ in
                    idleHands()
                    sim.hands[1].aimPos = sim.headPos + V3(0.2, -0.45, -0.3); sim.hands[1].gripPos = sim.hands[1].aimPos
                    sim.hands[1].aimRot = carry; sim.hands[1].gripRot = carry
                }
                try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out.replacingOccurrences(of: ".png", with: name))
            }
            (game.inventory.held, QuestSettings.swingMode) = keep
        }
        // Getting hurt: a red glow at the edges of the view (not a tinted HUD panel).
        game.hurtFlash = 0.35
        try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out.replacingOccurrences(of: ".png", with: "_hurt.png"))
        game.hurtFlash = 0
        PadManager.shared.touch = nil
        AllocCount.report("questsim allocations (frame thread)")
    }

    // Swing melee and the bow through the device path (QuestControls.swingContact / bowUpdate). Creative, on the
    // stone platform, the head level.
    static func swingMelee(game: Game, host: SimHost, controls: QuestControls, py: Int, down: simd_quatf,
                           frames: (Int, (Int) -> Void) -> Void, check: (Bool, String) -> Void) {
        let sim = host.sim, rig = host.rig
        func idleHands() {
            for h in 0..<2 {
                var hd = XRHand()
                hd.aimValid = true; hd.gripValid = true
                hd.aimPos = sim.headPos + V3(h == 0 ? -0.2 : 0.2, -0.45, -0.3)
                hd.gripPos = hd.aimPos
                hd.aimRot = simd_quatf(); hd.gripRot = simd_quatf()
                sim.hands[h] = hd
            }
        }
        let keepHeld = game.inventory.held
        defer { game.inventory.held = keepHeld; QuestSettings.leftHanded = false }
        func platformWhole() -> Bool {
            let fx = Int(floorf(game.player.pos.x)), fz = Int(floorf(game.player.pos.z))
            for dz in -4...4 { for dx in -4...4 where game.world.block(fx + dx, py, fz + dz) != STONE { return false } }
            return true
        }
        func ahead(_ d: Float, side: Float = 0) -> V3 {
            let f0 = rig.toWorldDir(V3(0, 0, -1)), r0 = rig.toWorldDir(V3(1, 0, 0))
            let f = simd_normalize(V3(f0.x, 0, f0.z)), r = simd_normalize(V3(r0.x, 0, r0.z))
            return V3(rig.headWorld.x, game.player.pos.y, rig.headWorld.z) + f * d + r * side
        }
        func husk(_ at: V3) -> Mob {
            let z = Mob(.husk, at: at)
            z.equip = nil
            game.mobs.mobs.append(z)
            return z
        }
        func remove(_ z: Mob) { game.mobs.mobs.removeAll { $0 === z } }
        // The right hand with the blade held level ahead (tilted down 0.75 rad), at x across the body (tracking).
        let tilt = simd_quatf(angle: -0.75, axis: V3(1, 0, 0))
        func pose(_ x: Float) {
            idleHands()
            sim.hands[1].aimPos = sim.headPos + V3(x, -0.35, -0.3); sim.hands[1].aimRot = tilt
            sim.hands[1].gripPos = sim.hands[1].aimPos; sim.hands[1].gripRot = tilt
        }
        game.inventory.held = ItemStack(Items.id("iron_sword"), 1)

        // (a) Waving the sword fast with the trigger released, the laser on the platform and a husk 2.5 blocks to the
        // side: nothing breaks, the husk isn't touched.
        do {
            let at = ahead(0, side: 2.5)
            let z = husk(at)
            let h0 = z.health, c0 = controls.bladeContacts
            frames(36) { i in
                idleHands(); z.pos = at; z.vel = .zero
                sim.hands[1].aimRot = down
                sim.hands[1].aimPos += V3(i % 2 == 0 ? 0.09 : -0.09, 0, 0)          // 6.5 m/s back and forth
            }
            check(platformWhole() && z.health == h0 && controls.bladeContacts == c0,
                  "VR swing: fast air swings near a husk, trigger released: platform whole \(platformWhole()), husk \(z.health) HP")
            remove(z)
        }
        // (b) Walking with the sword out (hand still relative to the head): nothing breaks.
        let walkFrom = game.player.pos
        frames(72) { _ in idleHands(); sim.hands[1].aimRot = down; sim.hands[0].stick = V2(0, 1) }
        frames(10) { _ in idleHands(); sim.hands[1].aimRot = down }
        check(platformWhole(), "VR swing: walking with the sword out breaks nothing")
        game.player.pos = walkFrom; game.player.vel = .zero
        frames(6) { _ in idleHands() }

        // (c) A fast swing across a husk 1.6 blocks ahead: the blade hits it (once), with a haptic buzz.
        func swingAcross(_ dist: Float, step: Float) -> (Int, Int, Int) {
            frames(8) { _ in pose(0.6) }                                         // settle at the start, then the husk
            let at = ahead(dist)
            let z = husk(at)
            let h0 = z.health, c0 = controls.bladeContacts, hp0 = sim.hapticCount
            let n = Int((1.2 / step).rounded())
            frames(n + 1) { i in z.pos = at; z.vel = .zero; pose(0.6 - step * Float(i)) }
            let r = (h0 - z.health, controls.bladeContacts - c0, sim.hapticCount - hp0)
            remove(z)
            frames(4) { _ in pose(-0.6) }
            return r
        }
        let fast = swingAcross(1.6, step: 0.3)                                   // ~20 m/s at the hand
        check(fast.0 > 0 && fast.1 == 1 && fast.2 > 0, "VR swing: a fast blade swing through a husk 1.6 ahead: \(fast.0) damage, \(fast.1) contact (want 1), haptics \(fast.2)")
        // (d) The same path slowly (0.3 m/s): a touch, no damage.
        let slow = swingAcross(1.6, step: 0.004)
        check(slow.0 == 0 && slow.1 == 0, "VR swing: a slow blade touch does no damage (\(slow.0) damage, \(slow.1) contacts)")
        // (e) Out of reach: a husk 3.8 blocks ahead is not hit by the same fast swing.
        let far = swingAcross(3.8, step: 0.3)
        check(far.0 == 0, "VR swing: a husk 3.8 blocks ahead is out of reach (\(far.0) damage)")
        check(platformWhole(), "VR swing: the platform is whole after all the swings")
        frames(6) { _ in idleHands() }

        // (f) The bow, both hands: the drawing hand at the string with its trigger nocks; pulling back draws the string
        // and arrow to the hand with ramping haptics; letting go shoots along the arrow (from the hand through the grip).
        game.inventory.held = ItemStack(Items.id("bow"), 1)
        for left in [false, true] {
            QuestSettings.leftHanded = left
            let bowH = left ? 0 : 1, drawH = 1 - bowH, sx: Float = left ? -1 : 1
            let name = left ? "left-handed" : "right-handed"
            let gripRest = sim.headPos + V3(0.2 * sx, -0.3, -0.45)
            func hands(_ drawPos: V3, _ trig: Bool) {
                idleHands()
                sim.hands[bowH].aimPos = gripRest; sim.hands[bowH].gripPos = gripRest
                sim.hands[drawH].aimPos = drawPos; sim.hands[drawH].gripPos = drawPos
                sim.hands[drawH].trigger = trig ? 1 : 0
            }
            let grip = gripRest + V3(0, 0.01, -0.03)
            let atString = VRBow.restNock(grip: grip, handRot: simd_quatf())
            frames(6) { _ in hands(atString, false) }
            frames(2) { _ in hands(atString, true) }
            let nocked = controls.bowNocked
            let hp0 = sim.hapticCount
            let back = sim.headPos + V3(0.15 * sx, -0.27, 0.13)
            frames(30) { i in hands(atString + (back - atString) * Float(i + 1) / 30, true) }
            let pose = controls.bowPose
            let ramps = sim.hapticCount - hp0
            let wantDir = simd_normalize(grip - back)
            let before = game.projectiles.arrows.count
            frames(2) { _ in hands(back, false) }
            let shot = game.projectiles.arrows.count > before ? game.projectiles.arrows.last : nil
            let wdir = simd_normalize(rig.toWorldDir(wantDir))
            let v = shot?.vel ?? .zero
            check(nocked, "VR bow (\(name)): the drawing hand's trigger at the string nocks an arrow")
            if let p = pose {
                check(p.draw > 0.7 && simd_length(p.nock - back) < 0.03 && simd_dot(p.dir, wantDir) > 0.995 && ramps >= 4,
                      String(format: "VR bow (%@): pulled back: draw %.2f, string at the hand %.3f m, arrow dir dot %.3f, %d haptic ticks",
                             name, p.draw, simd_length(p.nock - back), simd_dot(p.dir, wantDir), ramps))
            } else { check(false, "VR bow (\(name)): no bow pose while drawn") }
            check(shot != nil && simd_dot(simd_normalize(v), wdir) > 0.97 && simd_length(v) > 35,
                  String(format: "VR bow (%@): release shot along the arrow (dot %.3f, %.1f b/s)", name, simd_dot(simd_normalize(v + V3(0, 1e-6, 0)), wdir), simd_length(v)))
            if let a = shot { game.projectiles.arrows.removeAll { $0 === a } }
            frames(4) { _ in idleHands() }
        }
        QuestSettings.leftHanded = false
        frames(4) { _ in idleHands() }
    }

    static func shipRide(game: Game, host: SimHost, frames: (Int, (Int) -> Void) -> Void, check: (Bool, String) -> Void,
                         snapshot: () throws -> Void) throws {
        let sim = host.sim, rig = host.rig
        func idleHands() {
            for h in 0..<2 {
                var hd = XRHand()
                hd.aimValid = true; hd.gripValid = true
                hd.aimPos = sim.headPos + V3(h == 0 ? -0.2 : 0.2, -0.45, -0.3)
                hd.gripPos = hd.aimPos
                hd.aimRot = simd_quatf(); hd.gripRot = simd_quatf()
                sim.hands[h] = hd
            }
        }
        let ships = game.world.ships
        ships.encounters = false
        // Swing Mode off (5b left it on): snapping the aim onto the chest in one frame reads as a swing, and since round 4
        // a swing breaks what the laser picks (it broke the chest).
        let swingKeep = QuestSettings.swingMode
        QuestSettings.swingMode = false
        defer { QuestSettings.swingMode = swingKeep }
        if game.menu != nil { game.closeMenu() }
        game.inventory.held = .empty
        let pp = game.player.pos
        let ship = ships.spawnVessel("frigate", home: IVec3(Int(pp.x), Int(pp.y) + 14, Int(pp.z) - 40), game: nil)
        // A deck cell near the middle: solid, two air above.
        let g = ship.grid
        var deck: IVec3?
        let cx = g.sx / 2, cz = g.sz / 2
        search: for r in 0..<max(g.sx, g.sz) {
            for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                let x = cx + dx, z = cz + dz
                var y = g.sy - 1
                while y > 0 && g.get(x, y, z) == AIR { y -= 1 }
                if Blocks.fullCollide[Int(g.get(x, y, z))] && g.get(x, y + 1, z) == AIR && g.get(x, y + 2, z) == AIR
                    && g.get(x + 1, y + 1, z) == AIR && Blocks.fullCollide[Int(g.get(x + 1, y, z))] {
                    deck = IVec3(x, y, z); break search
                }
            } }
        }
        guard let d = deck else { check(false, "VR ship: no deck cell on the frigate"); return }
        let chestCell = IVec3(d.x + 1, d.y + 1, d.z)
        ships.setBlock(ship, chestCell, Blocks.id("chest"))
        game.player.pos = ship.toWorld(V3(Float(d.x) + 0.5, Float(d.y) + 1.02, Float(d.z) + 0.5))
        game.player.vel = .zero
        game.player.flying = false
        frames(20) { _ in idleHands() }
        check(ships.aboard === ship, "VR ship: standing on the frigate's deck (aboard \(ships.aboard?.name ?? "nothing"))")

        // Cruise and turn for 3 s.
        ship.autopilot = V3(0.6, 0.7, 0)
        let yaw0 = ship.yaw, body0 = rig.bodyYaw
        var stalls = 0, moving = 0, hudDev: Float = 0, offDeck = 0
        var last = ship.pos
        let hudDist0 = simd_length(host.controlsPanelCenter() - rig.headWorld)
        for _ in 0..<216 {
            frames(1) { _ in idleHands() }
            let mv = simd_length(ship.pos - last)
            if simd_length(ship.vel) > 0.3 { moving += 1; if mv < 1e-5 { stalls += 1 } }
            last = ship.pos
            hudDev = max(hudDev, abs(simd_length(host.controlsPanelCenter() - rig.headWorld) - hudDist0))
            if ships.aboard !== ship { offDeck += 1 }
        }
        var dShip = ship.yaw - yaw0, dBody = rig.bodyYaw - body0
        for _ in 0..<2 { if dShip > .pi { dShip -= 2 * .pi }; if dShip < -.pi { dShip += 2 * .pi }; if dBody > .pi { dBody -= 2 * .pi }; if dBody < -.pi { dBody += 2 * .pi } }
        check(offDeck == 0, "VR ship: stayed aboard while it cruised and turned (\(offDeck) frames off)")
        check(abs(dShip) > 0.2 && abs(dShip - dBody) < 0.03,
              String(format: "VR ship: the rig turned with the hull (ship %.2f rad, body %.2f rad)", dShip, dBody))
        check(moving > 100 && stalls == 0, "VR ship: the hull moved on every displayed frame (\(stalls) still frames of \(moving))")
        check(hudDev < 0.08, String(format: "VR ship: the HUD stayed with the user (distance to the head varied %.3f m)", hudDev))

        // Inventory aboard: the menu panel stays in front of the user while the ship keeps moving and turning.
        frames(36) { _ in idleHands(); sim.hands[0].button2 = true }
        frames(3) { _ in idleHands() }
        let menuDist0 = simd_length(host.controlsPanelCenter() - rig.headWorld)
        frames(144) { _ in idleHands() }
        let menuDist1 = simd_length(host.controlsPanelCenter() - rig.headWorld)
        check(game.menu != nil && abs(menuDist1 - menuDist0) < 0.05 && menuDist1 < 1.5,
              String(format: "VR ship: the inventory panel stayed in front (%.2f m -> %.2f m from the head)", menuDist0, menuDist1))
        // The laser still lands on its centre (aimed at the panel as it is now).
        frames(4) { _ in
            idleHands()
            let hand = sim.headPos + V3(0.2, -0.45, -0.3)
            let target = sim.headPos + V3(0, -0.1, -1.15)
            sim.hands[1].aimPos = hand
            sim.hands[1].aimRot = simd_quatf(from: V3(0, 0, -1), to: simd_normalize(target - hand))
        }
        let mx = game.input.mouseX, my = game.input.mouseY
        check(abs(mx - Float(QuestControls.panelW) / 2) < 40 && abs(my - Float(QuestControls.panelH) / 2) < 40,
              String(format: "VR ship: laser on the moving menu panel at (%.0f, %.0f)", mx, my))
        frames(3) { _ in idleHands(); sim.hands[1].button2 = true }
        frames(3) { _ in idleHands() }

        // The chest on deck: point at it, the hint names the grip, grip opens it.
        ship.autopilot = V3(0.3, 0.3, 0)
        func aimAtChest() {
            idleHands()
            let c = ship.toWorld(V3(Float(chestCell.x) + 0.5, Float(chestCell.y) + 0.4, Float(chestCell.z) + 0.5))
            let handT = sim.hands[1].aimPos
            let dirW = simd_normalize(c - rig.toWorld(handT))
            let dirT = rig.yawRot.inverse.act(dirW)
            sim.hands[1].aimRot = simd_quatf(from: V3(0, 0, -1), to: dirT)
        }
        frames(6) { _ in aimAtChest() }
        let hint = host.controlsHint() ?? "none"
        let st = ships.target.map { "\($0.ship.name) \($0.cell) b\($0.ship.grid.get($0.cell.x, $0.cell.y, $0.cell.z))" } ?? "nil"
        check(hint.contains("Open"), "VR ship: hint on the chest: \(hint) (menu \(game.menu != nil), pilot \(ships.pilot?.name ?? "nil"), "
              + "ship target \(st), world target \(game.target.map { "\($0.hit)" } ?? "nil"), chest b\(ship.grid.get(chestCell.x, chestCell.y, chestCell.z)), "
              + "commandeerable \(game.commandeerable()?.name ?? "nil"), kinematic \(ship.kinematic), wrecked \(ship.wrecked), aboard \(ships.aboard?.name ?? "nil"))")
        // Look at the chest for the snapshot (the laser, its dot, the hint label and the deck ring in view).
        let headRot0 = sim.headRot
        frames(2) { _ in
            aimAtChest()
            let c = ship.toWorld(V3(Float(chestCell.x) + 0.5, Float(chestCell.y) + 0.5, Float(chestCell.z) + 0.5))
            sim.headRot = simd_quatf(from: V3(0, 0, -1), to: rig.yawRot.inverse.act(simd_normalize(c - rig.headWorld)))
        }
        try snapshot()
        sim.headRot = headRot0
        frames(4) { _ in aimAtChest(); sim.hands[0].trigger = 1 }
        frames(4) { _ in aimAtChest() }
        check(game.menu is ChestMenu, "VR ship: grip opened the chest on the moving deck (\(game.menu.map { String(describing: type(of: $0)) } ?? "nothing"))")
        if game.menu != nil { game.closeMenu() }
        ship.autopilot = nil
        ships.remove(ship)
        frames(3) { _ in idleHands() }
    }

    static func render(scene: SceneRenderer, wr: WorldRenderer, rig: QuestRig, sim: SimXR, game: Game, path: String, size: Int = 640) throws {
        let ctx = scene.ctx
        let img = try VkImg(ctx, width: size, height: size, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        let target = try scene.makeTarget(image: img.image, width: size, height: size)
        let readback = try VkBuf(ctx, size: size * size * 8, usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue, host: true)
        let s = scene.beginFrame()
        wr.record(s, target, rig.camera(xr: sim, far: Float(game.world.renderDistance * 16 + 96)))
        vkCmdEndRenderPass(s.cmd)
        vkBarrier(s.cmd, img.image, from: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, layers: 2,
                  srcAccess: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue, dstAccess: VK_ACCESS_TRANSFER_READ_BIT.rawValue,
                  srcStage: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue, dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
        var r = VkBufferImageCopy()
        r.imageSubresource = VkImageSubresourceLayers(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, mipLevel: 0, baseArrayLayer: 0, layerCount: 2)
        r.imageExtent = VkExtent3D(width: UInt32(size), height: UInt32(size), depth: 1)
        vkCmdCopyImageToBuffer(s.cmd, img.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &r)
        try scene.submit(s)
        scene.waitIdle()
        withExtendedLifetime((img, target)) {}          // the GPU used them until waitIdle
        let src = readback.mapped!.bindMemory(to: UInt8.self, capacity: size * size * 8)
        var outPx = [UInt8](repeating: 0, count: size * 2 * size * 4)
        for y in 0..<size { for e in 0..<2 { for x in 0..<size {
            let si = (e * size * size + y * size + x) * 4, di = (y * size * 2 + e * size + x) * 4
            outPx[di] = src[si]; outPx[di + 1] = src[si + 1]; outPx[di + 2] = src[si + 2]; outPx[di + 3] = 255
        } } }
        try PNG.encode(rgba: outPx, width: size * 2, height: size).write(to: URL(fileURLWithPath: path))
        print("questsim: wrote \(path)")
    }
}
