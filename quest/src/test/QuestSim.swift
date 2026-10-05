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
        wr.extraOpaque = { s, eye in controls.drawOpaque(s, eye: eye) }
        wr.extraOverlay = { s, eye in controls.drawOverlay(s, eye: eye) }
        wr.prePass = { s in controls.recordPanel(s) }
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
                rig.update(xr: sim, game: game)
                controls.update(dt: dt)
                game.tick(Double(dt))
                game.world.update(center: game.player.pos)
                controls.afterTick(dt: dt)
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

        // 5. Break: the right trigger breaks the targeted block (creative).
        if let t = game.target?.hit {
            let before = game.world.block(t.x, t.y, t.z)
            frames(6) { _ in idleHands(); sim.hands[1].aimRot = down; sim.hands[1].trigger = 1 }
            frames(10) { _ in idleHands(); sim.hands[1].aimRot = down }
            let after = game.world.block(t.x, t.y, t.z)
            check(before != AIR && after != before, "VR break: right trigger broke \(Blocks.name(before)) at \(t) (now \(Blocks.name(after)))")
        }

        // 6. Place: right grip with a block in hand places it against the targeted face.
        game.inventory.held = ItemStack(Items.id("gold_block"), 64)
        frames(3) { _ in idleHands(); sim.hands[1].aimRot = down }
        if let t = game.target {
            let at = IVec3(t.hit.x + t.normal.x, t.hit.y + t.normal.y, t.hit.z + t.normal.z)
            frames(4) { _ in idleHands(); sim.hands[1].aimRot = down; sim.hands[1].squeeze = 1 }
            frames(6) { _ in idleHands(); sim.hands[1].aimRot = down }
            check(game.world.block(at.x, at.y, at.z) == Blocks.id("gold_block"), "VR place: right grip placed a gold block at \(at)")
        } else { check(false, "VR place: no target") }

        // 7. Inventory: Y (left upper button) opens it; the panel sits in front; the laser drives the mouse.
        frames(3) { _ in idleHands(); sim.hands[0].button2 = true }
        frames(3) { _ in idleHands() }
        check(game.menu != nil, "VR inventory: Y opened \(game.menu.map { String(describing: type(of: $0)) } ?? "nothing")")
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

        // 8c. Holding Y opens the world map (a tap still opens the inventory, checked above).
        frames(72) { _ in idleHands(); sim.hands[0].button2 = true }
        let mapOpen = game.menu is MapMenu
        frames(3) { _ in idleHands() }
        check(mapOpen && !(game.menu is InventoryMenu || game.menu is CreativeMenu), "VR map: holding Y opened \(mapOpen ? "the world map" : String(describing: game.menu.map { type(of: $0) }))")
        if game.menu != nil { game.closeMenu() }
        frames(3) { _ in idleHands() }

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
        QuestSettings.snapAngle = snap0

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

        frames(3) { _ in idleHands(); sim.hands[1].aimRot = down }
        try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out)
        // Getting hurt: a red glow at the edges of the view (not a tinted HUD panel).
        game.hurtFlash = 0.35
        try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out.replacingOccurrences(of: ".png", with: "_hurt.png"))
        game.hurtFlash = 0
        PadManager.shared.touch = nil
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
        frames(3) { _ in idleHands(); sim.hands[0].button2 = true }
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
        check(hint.contains("Open"), "VR ship: hint on the chest: \(hint)")
        // Look at the chest for the snapshot (the laser, its dot, the hint label and the deck ring in view).
        let headRot0 = sim.headRot
        frames(2) { _ in
            aimAtChest()
            let c = ship.toWorld(V3(Float(chestCell.x) + 0.5, Float(chestCell.y) + 0.5, Float(chestCell.z) + 0.5))
            sim.headRot = simd_quatf(from: V3(0, 0, -1), to: rig.yawRot.inverse.act(simd_normalize(c - rig.headWorld)))
        }
        try snapshot()
        sim.headRot = headRot0
        frames(4) { _ in aimAtChest(); sim.hands[1].squeeze = 1 }
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
