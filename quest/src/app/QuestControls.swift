import Foundation
import simd
import CVulkan

// Touch controllers -> the game. Everything goes through the game's own controller and mouse paths, so no gameplay
// code changes:
//  - The right-hand ray (left-handed: the left) is cast into the world; the game's look direction is then aimed from
//    the player's eye at the point the ray hits, so the game's targeting, mining, using and shooting pick exactly what
//    the laser points at.
//  - The left stick moves relative to the head (or the left controller); it is pre-rotated into the aim frame the
//    game moves in. The right stick turns the body (snap or smooth); its flicks up/down are D-pad up (fly) / down (drop).
//  - Buttons: right trigger = RT (break / attack / fire), right grip or left trigger = LT (use / place / aim),
//    A jump, B sneak / back, X pick block / reload, Y inventory, left grip = LB, right stick click = RB (hotbar
//    right, hold for the weapon wheel), left stick click = sprint, menu = pause.
//  - Menus and the HUD are world-space panels (HudPanel); in a menu the laser is the mouse (trigger = left click,
//    grip = right click).
//  - Physically walking moves the player through collision (roomscale); snap turns and fast movement darken the
//    edges of the view (comfort vignette).
final class QuestControls {
    unowned let app: QuestHost
    let game: Game
    let hudHost: Renderer
    private(set) var panel: HudPanel?
    // The interact hint beside the laser dot ("Grip Open" on a chest), its own small panel.
    private var hintPanel: HudPanel?
    private(set) var hint: String?
    private var hintShown: String?
    private var hintKey = ""
    static let hintW = 640, hintH = 48
    static let panelW = 1024, panelH = 640

    private var snapArmed = true
    private var flickArmed = true
    private var flick = 0                      // 1 up, -1 down (a short D-pad press)
    private var flickTime: Float = 0
    private var vignette: Float = 0            // current strength 0...1
    private var turnFlash: Float = 0
    private var lastFeet = V3.zero

    // Aim (world space, this frame)
    private(set) var aimOrigin = V3.zero
    private(set) var aimDir = V3(0, 0, -1)
    private(set) var aimHit: V3?
    private var aimHand: Int { QuestSettings.leftHanded ? 0 : 1 }
    private var moveHand: Int { QuestSettings.leftHanded ? 1 : 0 }

    // Panel placement. Panels live in tracking space (the user's room), which the rig carries with the player: on a
    // moving ship, while turning or walking they stay put around the user instead of being left behind in the world.
    private enum PanelMode { case hud, menu }
    private var mode = PanelMode.hud
    private var panelCenterT = V3.zero         // tracking space
    private var panelYawT: Float = 0           // tracking-space yaw
    private var panelPitch: Float = 0
    private var panelSize = V2(1.3, 0.8125)
    private var hudYawT: Float = 0             // tracking-space yaw the HUD faces (lazily follows the head)
    private var hudPosT: V3?                   // smoothed HUD centre (tracking space)
    private var panelCenter: V3 { app.rig.toWorld(panelCenterT) }
    var panelWorldCenter: V3 { panelCenter }           // (harness)
    private var panelYaw: Float { panelYawT + app.rig.bodyYaw }

    // The ship the player rides (aboard or at the helm): its turns turn the rig, its motion drives the vignette.
    private weak var carryShip: Ship?
    private var carryYaw: Float = 0
    private var carryRot = simd_quatf()
    private var carryVel = V3.zero
    private var carryLocal = V3.zero           // the player's feet in the ship's frame last frame
    private(set) var shipTurnRate: Float = 0   // rad/s (yaw, pitch and roll together)
    private(set) var deckReference: Float = 0  // 0...1: the comfort reference ring under the feet aboard a moving ship

    // Teleport movement (Quest option): the arc from the moving hand while its stick is pushed forward.
    private(set) var teleAiming = false
    private var teleArc: [V3] = []                     // world points
    private var teleTarget: (ship: Ship?, local: V3)?   // feet: world point, or a point in a ship's frame (it moves)
    private(set) var teleports = 0
    var teleArcCount: Int { teleArc.count }                                    // (harness)
    var teleTargetText: String { teleTarget.map { "\($0.ship == nil ? "ground" : "ship") \($0.local)" } ?? "none" }
    static let teleportRange: Float = 14
    private var panelHitUV: V2?
    private var prevTrigger = false, prevGrip = false
    private var lastHoverSlot = -1

    init(app: QuestHost, game: Game, panel: HudPanel?) {
        self.app = app
        self.game = game
        hudHost = Renderer(game: game)
        // TV-style HUD scale (bigger text) unless the player picked one: the panel is read at arm's length.
        if UserDefaults.standard.object(forKey: "couchMode") == nil { HudLayout.couch = true }
        game.screen = V2(Float(QuestControls.panelW), Float(QuestControls.panelH))
        Renderer.questHideCrosshair = true
        self.panel = panel
        if let p = panel { hintPanel = try? HudPanel(scene: p.scene, width: QuestControls.hintW, height: QuestControls.hintH, maxVerts: 4096) }
        // Prompts name the Touch controls: the game's LT (use) is the grip, RT the trigger.
        Glyphs.labelOverride = { g in
            switch g {
            case .lt: return "Grip"
            case .rt: return "Trigger"
            case .lb: return "L Grip"
            case .rb: return "R Stick"
            default: return nil
            }
        }
        hudYawT = 0
    }

    // MARK: Per frame, before Game.tick

    func update(dt: Float) {
        let xr = app.input, rig = app.rig
        let hands = xr.hands
        let L = hands[moveHand], R = hands[aimHand]
        let inMenu = game.menu != nil || game.paused

        // Turning (never inside a menu: the panel stays put).
        if !inMenu {
            let tx = R.stick.x
            if QuestSettings.smoothTurn {
                if abs(tx) > 0.15 {
                    let k = (abs(tx) - 0.15) / 0.85 * (tx > 0 ? 1 : -1)
                    rig.bodyYaw -= k * QuestSettings.smoothTurnSpeed * .pi / 180 * dt
                    turnFlash = max(turnFlash, abs(k) * 0.8)
                }
            } else {
                if snapArmed && abs(tx) > 0.75 {
                    let step = (tx > 0 ? 1 : -1) * QuestSettings.snapAngle * .pi / 180
                    rig.bodyYaw -= step                  // the HUD (tracking space) turns with the body
                    snapArmed = false
                    turnFlash = 1
                } else if abs(tx) < 0.3 { snapArmed = true }
            }
            rig.bodyYaw = rig.bodyYaw.truncatingRemainder(dividingBy: 2 * .pi)
        }
        // Right stick flicks up/down: D-pad up (fly) / down (drop), a 3-frame press.
        let ty = R.stick.y
        if flickArmed && abs(ty) > 0.8 && abs(R.stick.x) < 0.5 { flick = ty > 0 ? 1 : -1; flickTime = 0.05; flickArmed = false }
        else if abs(ty) < 0.3 { flickArmed = true }
        if flickTime > 0 { flickTime -= dt } else { flick = 0 }

        // Roomscale: the head's walk since last frame moves the player through collision.
        roomScale()

        // Aim from the aiming hand.
        if R.aimValid {
            aimOrigin = rig.toWorld(R.aimPos)
            aimDir = simd_normalize(rig.toWorldDir(R.aimRot.act(V3(0, 0, -1))))
        } else {
            aimOrigin = rig.headWorld
            aimDir = simd_normalize(rig.toWorldDir(rig.headRot.act(V3(0, 0, -1))))
        }

        // Pad for the game.
        var p = PadSnapshot()
        p.rt = R.trigger
        p.lt = max(R.squeeze, L.trigger)
        p.a = R.button1
        p.b = R.button2
        p.x = L.button1
        p.y = L.button2
        p.lb = L.squeeze > 0.6
        p.rb = R.stickClick
        p.l3 = L.stickClick
        p.menu = L.menu
        p.up = flick == 1
        p.down = flick == -1
        if inMenu {
            // Menus: the left stick moves the pad cursor as on the Mac; the laser is the mouse.
            p.lx = L.stick.x; p.ly = L.stick.y
            p.lt = L.trigger; p.rt = 0
            p.lb = L.squeeze > 0.6; p.rb = false
            menuPointer(R)
            teleAiming = false; teleArc.removeAll(); teleTarget = nil
        } else {
            panelHitUV = nil
            prevTrigger = R.trigger > 0.6; prevGrip = R.squeeze > 0.6
            // Locomotion frame: the head (or the moving hand) yaw; the game moves relative to the aim yaw.
            let moveYaw: Float
            if QuestSettings.headLocomotion || !L.aimValid { moveYaw = rig.headYaw }
            else { moveYaw = XRMath.yawPitch(rig.toWorldRot(L.aimRot)).0 }
            aimGame()
            if game.world.ships.pilot != nil {
                // At the helm the stick is throttle and steering: raw, whatever way the hand or head points.
                p.lx = L.stick.x; p.ly = L.stick.y
                teleAiming = false; teleArc.removeAll(); teleTarget = nil
            } else if QuestSettings.teleport && game.riding == nil {
                teleport(L)
            } else {
                let d = moveYaw - game.player.yaw
                let s = L.stick
                // Stick (x right, y forward) turned from the locomotion frame into the aim frame.
                p.lx = s.x * cosf(d) + s.y * sinf(d)
                p.ly = -s.x * sinf(d) + s.y * cosf(d)
            }
        }
        PadManager.shared.touch = p
        lastFeet = game.player.pos
    }

    // After Game.tick: the camera follows the moved player; head-space audio; vignette from motion.
    func afterTick(dt: Float) {
        let rig = app.rig
        let ships = game.world.ships
        let ship = ships.pilot ?? ships.aboard
        // Ship riding: the deck turned under the player this tick (ShipPhysics carried the feet and the game's yaw);
        // the tracking space turns with it so the deck stays still around the user. Only yaw: the view keeps a level
        // horizon while the hull pitches and rolls.
        var shipAccel: Float = 0
        var relMoved: Float = -1
        if let s = ship, s === carryShip {
            var d = s.yaw - carryYaw
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            rig.bodyYaw = (rig.bodyYaw + d).truncatingRemainder(dividingBy: 2 * .pi)
            let dq = s.rot * carryRot.inverse
            let ang = 2 * acosf(min(1, abs(dq.real)))
            shipTurnRate += (ang / max(dt, 1e-3) - shipTurnRate) * min(1, dt * 8)
            let v = s.velocity(at: game.player.pos)
            shipAccel = simd_length(v - carryVel) / max(dt, 1e-3)
            carryVel = v
            relMoved = simd_length(s.toLocal(game.player.pos) - carryLocal) / max(dt, 1e-3)
        } else {
            shipTurnRate = 0
            carryVel = ship?.velocity(at: game.player.pos) ?? .zero
        }
        carryShip = ship
        carryYaw = ship?.yaw ?? 0
        carryRot = ship?.rot ?? simd_quatf()
        if let s = ship { carryLocal = s.toLocal(game.player.pos) }
        rig.refresh(game: game)
        game.sound?.setListener(eye: rig.headWorld, yaw: rig.headYaw, pitch: rig.headPitch, cave: game.sound?.cave ?? 0,
                                underwater: game.player.headInWater)
        // Comfort vignette: the player's own movement (relative to the deck when aboard: a ship cruising steadily is
        // comfortable, its turns, pitching and speed changes are not), snap / smooth turns.
        let moved = simd_length(V2(game.player.pos.x - lastFeet.x, game.player.pos.z - lastFeet.z)) / max(dt, 1e-3)
        let vy = abs(game.player.pos.y - lastFeet.y) / max(dt, 1e-3)
        let speed = relMoved >= 0 ? relMoved : moved + vy * 0.5
        var want: Float = min(1, max(0, (speed - 1.2) / 6))
        if ship != nil {
            want = max(want, min(1, shipTurnRate * 2.5), min(1, max(0, shipAccel - 0.5) / 6))
            let shipSpeed = simd_length(carryVel)
            deckReference += ((shipSpeed > 0.5 || shipTurnRate > 0.05 ? 1 : 0) - deckReference) * min(1, dt * 2)
        } else {
            deckReference = max(0, deckReference - dt * 2)
            if game.riding != nil { want = min(1, want + 0.2) }
        }
        want = max(want, turnFlash)
        turnFlash = max(0, turnFlash - dt * 5)
        vignette += (want - vignette) * min(1, dt * (want > vignette ? 10 : 3))
        updateHint()
        // Panel follows the menu state.
        if game.menu != nil || game.paused {
            if mode != .menu { placeMenuPanel() }
        } else if mode != .hud { mode = .hud }
        if mode == .hud { placeHudPanel(dt) }
    }

    // What the use button (grip) does to the block under the laser, when that is more than placing: open a chest,
    // barrel or furnace, use a door, lever or bench, steer a ship. A light buzz when a new one comes under the laser.
    private func updateHint() {
        var h: String?
        var key = ""
        let use = Prompt.g(.use, pad: true)
        if game.menu == nil && !game.paused {
            if let st = game.world.ships.target {
                let b = st.ship.grid.get(st.cell.x, st.cell.y, st.cell.z)
                key = "s\(st.cell)"
                if ShipParts.kinds[Int(b)] == .helm && st.ship.helm == st.cell {
                    h = use + (st.ship.root.kinematic ? " Helm (locked)" : " Steer")
                } else if st.ship.blockEntities[st.cell] != nil || Blocks.key(Blocks.groupBase[Int(b)]).hasSuffix("chest") {
                    h = use + " Open " + Blocks.name(b)
                }
            } else if let t = game.target, game.isInteractive(t.hit) || game.isCircuitInteractive(t.hit) {
                let b = game.world.block(t.hit.x, t.hit.y, t.hit.z)
                let k = Blocks.key(Blocks.groupBase[Int(b)])
                key = "w\(t.hit)"
                let opens = ["chest", "barrel", "box", "furnace", "smoker", "hopper", "dispenser", "dropper", "crafting", "table",
                             "anvil", "loom", "grindstone", "stonecutter", "brewing", "beacon", "crafter", "lectern"].contains { k.contains($0) }
                h = use + (opens ? " Open " : " Use ") + Blocks.name(b)
            }
        }
        if h != nil && key != hintKey { app.input.haptic(aimHand, amplitude: 0.18, seconds: 0.015, frequency: 220) }
        hintKey = h == nil ? "" : key
        hint = h
    }

    // Teleport: hold the left stick forward to aim a falling arc from the hand; release to land where it ends (the top
    // of a block with room to stand, on the ground or a ship's deck, within 14 blocks). A short vignette blink hides the
    // jump.
    private func teleport(_ L: XRHand) {
        let sy = L.stick.y
        if sy > 0.6 && L.aimValid {
            teleAiming = true
            computeArc(L)
        } else if teleAiming && sy < 0.3 {
            teleAiming = false
            if let t = teleTarget {
                let feet = t.ship.map { $0.toWorld(t.local) } ?? t.local
                game.player.pos = feet
                game.player.vel = .zero
                game.player.airPeak = feet.y
                turnFlash = 1
                teleports += 1
                app.input.haptic(moveHand, amplitude: 0.35, seconds: 0.04, frequency: 160)
                app.rig.refresh(game: game)
            }
            teleTarget = nil
            teleArc.removeAll()
        }
    }

    private func computeArc(_ L: XRHand) {
        let rig = app.rig, w = game.world
        var p = rig.toWorld(L.aimPos)
        var v = simd_normalize(rig.toWorldDir(L.aimRot.act(V3(0, 0, -1)))) * 11
        let start = p
        let g: Float = 14, step: Float = 0.035
        teleArc.removeAll(keepingCapacity: true)
        teleArc.append(p)
        teleTarget = nil
        func standable(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            let a = w.block(x, y, z), b = w.block(x, y + 1, z)
            return !Blocks.collide[Int(a)] && !Blocks.collide[Int(b)] && Blocks.fluidKind[Int(a)] != 2
        }
        for _ in 0..<70 {
            let q = p + v * step
            v.y -= g * step
            let seg = q - p, len = simd_length(seg)
            guard len > 1e-4 else { break }
            let dir = seg / len
            var best: Float = len + 1
            var landing: (Ship?, V3)?
            if let h = w.raycast(p, dir, maxDist: len) {
                let t = simd_dot(V3(Float(h.hit.x) + 0.5, Float(h.hit.y) + 0.5, Float(h.hit.z) + 0.5) - p, dir)
                best = max(0, t)
                if h.normal == IVec3(0, 1, 0) && standable(h.hit.x, h.hit.y + 1, h.hit.z) {
                    landing = (nil, V3(Float(h.hit.x) + 0.5, Float(h.hit.y + 1) + 0.01, Float(h.hit.z) + 0.5))
                }
            }
            for s in w.ships.list where s.worldMax.x > min(p.x, q.x) - 1 && s.worldMin.x < max(p.x, q.x) + 1
                && s.worldMax.y > min(p.y, q.y) - 1 && s.worldMin.y < max(p.y, q.y) + 1
                && s.worldMax.z > min(p.z, q.z) - 1 && s.worldMin.z < max(p.z, q.z) + 1 {
                if let h = s.raycast(p, dir, maxDist: len, world: w), h.t < best {
                    best = h.t
                    let c = h.cell, gr = s.grid
                    if h.normal == IVec3(0, 1, 0) && !Blocks.collide[Int(gr.get(c.x, c.y + 1, c.z))] && !Blocks.collide[Int(gr.get(c.x, c.y + 2, c.z))] {
                        landing = (s, V3(Float(c.x) + 0.5, Float(c.y + 1) + 0.01, Float(c.z) + 0.5))
                    } else { landing = nil }
                }
            }
            if best <= len {
                let end = p + dir * best
                teleArc.append(end)
                if let l = landing {
                    let feet = l.0.map { $0.toWorld(l.1) } ?? l.1
                    if simd_length(V2(feet.x - start.x, feet.z - start.z)) <= QuestControls.teleportRange { teleTarget = (l.0, l.1) }
                }
                return
            }
            p = q
            teleArc.append(p)
            if p.y < start.y - 40 { break }
        }
    }

    // The arc (green when it ends on a place to stand, red otherwise) and a ring where the feet will land.
    private func drawTeleport(_ s: SceneRenderer.Slot, eye: V3) {
        guard teleAiming, teleArc.count > 1 else { return }
        let ok = teleTarget != nil
        let col = ok ? V4(0.45, 1, 0.6, 0.85) : V4(1, 0.4, 0.35, 0.7)
        var v: [SimpleVert] = []
        let headDir = simd_normalize(app.rig.headWorld - teleArc[teleArc.count / 2])
        for i in 0..<(teleArc.count - 1) {
            let a = teleArc[i] - eye, b = teleArc[i + 1] - eye
            let side = simd_normalize(simd_cross(teleArc[i + 1] - teleArc[i], headDir) + V3(1e-5, 0, 0)) * 0.012
            let ca = V4(col.x, col.y, col.z, col.w * Float(i + 1) / Float(teleArc.count))
            let q = [a - side, b - side, b + side, a + side]
            for k in [0, 1, 2, 0, 2, 3] { v.append(SimpleVert(pos: V4(q[k], 1), color: ca)) }
        }
        if let t = teleTarget {
            let c = (t.ship.map { $0.toWorld(t.local) } ?? t.local) + V3(0, 0.03, 0) - eye
            let seg = 24
            for i in 0..<seg {
                let a0 = Float(i) / Float(seg) * 2 * .pi, a1 = Float(i + 1) / Float(seg) * 2 * .pi
                let d0 = V3(cosf(a0), 0, sinf(a0)), d1 = V3(cosf(a1), 0, sinf(a1))
                let q = [c + d0 * 0.3, c + d1 * 0.3, c + d1 * 0.38, c + d0 * 0.38]
                for k in [0, 1, 2, 0, 2, 3] { v.append(SimpleVert(pos: V4(q[k], 1), color: col)) }
            }
        }
        if let off = app.scene.push(s, v) { app.scene.drawScratch(s, "simple", offset: off, count: v.count) }
    }

    private func roomScale() {
        let rig = app.rig
        if QuestSettings.seated {
            // Seated: leaning moves only the view (up to 35 cm from the centre), never the player.
            var d = rig.trackingHead - rig.anchor
            d.y = 0
            let l = simd_length(d)
            if l > 0.35 { rig.anchor += d * (1 - 0.35 / l) }
            rig.refresh(game: game)
            return
        }
        let d = rig.trackingHead - rig.anchor
        let delta = rig.toWorldDir(V3(d.x, 0, d.z))
        if simd_length_squared(delta) > 1e-8, game.menu == nil {
            let pl = game.player
            var pos = pl.pos
            if pl.flying || game.riding != nil || game.world.ships.aboard != nil {
                if game.riding == nil { pos += delta }
            } else {
                _ = game.world.moveBody(&pos, halfW: pl.halfW, height: pl.height, delta, step: pl.onGround ? 0.6 : 0, onGround: pl.onGround)
            }
            if game.riding == nil { pl.pos = pos }
        }
        rig.absorbHeadOffset()
        rig.refresh(game: game)
    }

    // Points the game's look at whatever the hand ray hits (blocks and mobs within reach, else far along the ray).
    private func aimGame() {
        let w = game.world
        let reach: Float = 8
        var best: Float = 60
        if let hit = w.raycast(aimOrigin, aimDir, maxDist: reach) {
            // Where the ray enters the hit block's selection boxes, a hair inside, so the game's ray from the eye
            // through that point picks the same block.
            let c = V3(Float(hit.hit.x), Float(hit.hit.y), Float(hit.hit.z))
            var tEnter: Float = .greatestFiniteMagnitude
            for (mn, mx) in w.selectionBoxes(w.block(hit.hit.x, hit.hit.y, hit.hit.z)) {
                if let t = QuestControls.rayBox(aimOrigin, aimDir, c + mn, c + mx) { tEnter = min(tEnter, t) }
            }
            if tEnter == .greatestFiniteMagnitude { tEnter = simd_dot(c + V3(0.5, 0.5, 0.5) - aimOrigin, aimDir) }
            best = min(best, max(0.05, tEnter + 0.02))
        }
        // Ship blocks (decks, chests and helms on ships): the game targets them from the eye too (shipInteract).
        for s in w.ships.list where aimOrigin.x > s.worldMin.x - reach && aimOrigin.x < s.worldMax.x + reach
            && aimOrigin.y > s.worldMin.y - reach && aimOrigin.y < s.worldMax.y + reach
            && aimOrigin.z > s.worldMin.z - reach && aimOrigin.z < s.worldMax.z + reach {
            if let h = s.raycast(aimOrigin, aimDir, maxDist: reach, world: w), h.t + 0.02 < best { best = max(0.05, h.t + 0.02) }
        }
        if let (_, t) = game.mobs.raycast(aimOrigin, aimDir, maxDist: reach), t < best { best = t }
        let p = aimOrigin + aimDir * best
        aimHit = best < 60 ? p : nil
        let eye = game.player.eye
        var d = p - eye
        if simd_length_squared(d) < 1e-4 { d = aimDir }
        d = simd_normalize(d)
        game.player.yaw = atan2f(-d.x, -d.z)
        game.player.pitch = asinf(max(-0.999, min(0.999, d.y)))
    }

    // Entry distance of a ray into a box (slab test), nil if it misses.
    static func rayBox(_ o: V3, _ d: V3, _ mn: V3, _ mx: V3) -> Float? {
        var t0: Float = 0, t1: Float = .greatestFiniteMagnitude
        for a in 0..<3 {
            if abs(d[a]) < 1e-7 {
                if o[a] < mn[a] || o[a] > mx[a] { return nil }
                continue
            }
            var ta = (mn[a] - o[a]) / d[a], tb = (mx[a] - o[a]) / d[a]
            if ta > tb { swap(&ta, &tb) }
            t0 = max(t0, ta); t1 = min(t1, tb)
            if t0 > t1 { return nil }
        }
        return t0
    }

    // MARK: Panels

    private func placeMenuPanel() {
        mode = .menu
        let rig = app.rig
        let yaw = rig.headYaw - rig.bodyYaw                  // tracking space
        let fwd = V3(-sinf(yaw), 0, -cosf(yaw))
        panelCenterT = rig.trackingHead + fwd * 1.15 + V3(0, -0.1, 0)
        panelYawT = yaw
        panelPitch = 0
        panelSize = V2(1.5, 1.5 * Float(QuestControls.panelH) / Float(QuestControls.panelW))
    }

    // HUD: in the lower view, turning with the head once it looks more than 25 degrees away.
    // Body-locked in tracking space: follows the head's position smoothly and its yaw lazily.
    private func placeHudPanel(_ dt: Float) {
        let rig = app.rig
        var diff = (rig.headYaw - rig.bodyYaw) - hudYawT
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        if abs(diff) > 25 * .pi / 180 { hudYawT += diff * min(1, dt * 3) }
        hudYawT = hudYawT.truncatingRemainder(dividingBy: 2 * .pi)
        let fwd = V3(-sinf(hudYawT), 0, -cosf(hudYawT))
        let want = rig.trackingHead + fwd * 1.25 + V3(0, -0.42, 0)
        var pos = hudPosT ?? want
        pos += (want - pos) * min(1, dt * 12)
        if simd_length(want - pos) > 0.5 { pos = want }
        hudPosT = pos
        panelCenterT = pos
        panelYawT = hudYawT
        panelPitch = -0.32
        panelSize = V2(1.25, 1.25 * Float(QuestControls.panelH) / Float(QuestControls.panelW))
    }

    // Panel axes (world): right, up, normal toward the viewer.
    private func panelAxes() -> (V3, V3, V3) {
        let q = simd_quatf(angle: panelYaw, axis: V3(0, 1, 0)) * simd_quatf(angle: panelPitch, axis: V3(1, 0, 0))
        return (q.act(V3(1, 0, 0)), q.act(V3(0, 1, 0)), q.act(V3(0, 0, 1)))
    }

    // The laser on the menu panel drives the game's mouse.
    private func menuPointer(_ R: XRHand) {
        let (rx, uy, n) = panelAxes()
        let denom = simd_dot(aimDir, n)
        var uv: V2?
        if denom < -1e-3 {
            let t = simd_dot(panelCenter - aimOrigin, n) / denom
            if t > 0 {
                let hit = aimOrigin + aimDir * t
                let u = simd_dot(hit - panelCenter, rx) / panelSize.x + 0.5
                let v = 0.5 - simd_dot(hit - panelCenter, uy) / panelSize.y
                if u >= -0.05 && u <= 1.05 && v >= -0.05 && v <= 1.05 { uv = V2(u, v); aimHit = hit }
            }
        }
        panelHitUV = uv
        let input = game.input
        let trig = R.trigger > 0.6, grip = R.squeeze > 0.6
        if let uv {
            let mx = uv.x * Float(QuestControls.panelW), my = uv.y * Float(QuestControls.panelH)
            if abs(mx - input.mouseX) + abs(my - input.mouseY) > 0.5 { input.mouseMoved = true }
            input.mouseX = mx; input.mouseY = my
            if trig && !prevTrigger { input.leftClicked = true; app.input.haptic(aimHand, amplitude: 0.3, seconds: 0.02, frequency: 300) }
            if grip && !prevGrip { input.rightClicked = true; app.input.haptic(aimHand, amplitude: 0.3, seconds: 0.02, frequency: 300) }
            input.leftDown = trig
            input.rightDown = grip
            if game.menuCursor != lastHoverSlot { lastHoverSlot = game.menuCursor; app.input.haptic(aimHand, amplitude: 0.12, seconds: 0.01, frequency: 320) }
        } else {
            input.leftDown = false; input.rightDown = false
        }
        prevTrigger = trig; prevGrip = grip
    }

    // MARK: Drawing

    // HUD pass (before the world pass): the game's 2D HUD / menus into the panel image.
    func recordPanel(_ s: SceneRenderer.Slot) {
        guard let panel else { return }
        hudHost.fps = app.fps
        hudHost.gpuFrameMs = app.scene.gpuMs
        hudHost.drawnChunks = app.scene.visibleCount
        let verts = hudHost.buildHUD(Float(panel.width), Float(panel.height))
        panel.record(s, verts)
        if let hp = hintPanel, let h = hint, h != hintShown {
            hp.record(s, QuestLabel.verts(h, width: Float(hp.width), height: Float(hp.height), scale: 4))
            hintShown = h
        }
    }

    func drawOpaque(_ s: SceneRenderer.Slot, eye: V3) {
        let xr = app.input, rig = app.rig
        var v: [SimpleVert] = []
        let CT = Mesher.cornerTable
        let shades: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
        // Controllers: a grip block and a pointer nose, in each hand's grip pose.
        for h in 0..<2 {
            let hd = xr.hands[h]
            guard hd.gripValid else { continue }
            let pos = rig.toWorld(hd.gripPos) - eye
            let rot = rig.toWorldRot(hd.gripRot)
            let base = h == aimHand ? V3(0.25, 0.27, 0.32) : V3(0.3, 0.3, 0.34)
            let parts: [(V3, V3, V3)] = [(V3(0, 0, 0.02), V3(0.018, 0.026, 0.05), base),
                                         (V3(0, 0.012, -0.05), V3(0.012, 0.012, 0.03), base * 1.4),
                                         (V3(0, 0.03, 0.0), V3(0.035, 0.008, 0.035), V3(0.12, 0.12, 0.14))]
            for (c, half, col) in parts {
                for f in 0..<6 {
                    for k in [0, 1, 2, 0, 2, 3] {
                        let ci = (f * 4 + k) * 3
                        let lp = c + V3(Float(CT[ci] * 2 - 1) * half.x, Float(CT[ci + 1] * 2 - 1) * half.y, Float(CT[ci + 2] * 2 - 1) * half.z)
                        v.append(SimpleVert(pos: V4(rot.act(lp) + pos, 1), color: V4(col * shades[f], 1)))
                    }
                }
            }
        }
        if let off = app.scene.push(s, v) { app.scene.drawScratch(s, "simpleSolid", offset: off, count: v.count) }
        drawHeld(s, eye: eye)
        drawTeleport(s, eye: eye)
        // Laser: to the hit point (menus, a target within reach) or a short fading stub.
        let inMenu = game.menu != nil || game.paused
        if xr.hands[aimHand].aimValid {
            let o = aimOrigin - eye
            let len: Float = aimHit.map { simd_length($0 - aimOrigin) } ?? (inMenu ? 1.5 : 0.6)
            let end = o + aimDir * len
            let side0 = simd_normalize(simd_cross(aimDir, simd_normalize(o + aimDir * 0.5)))
            let side = side0 * 0.0015
            let hot = inMenu ? (panelHitUV != nil) : (game.target != nil)
            let c0 = hot ? V4(0.55, 0.9, 1, 0.85) : V4(1, 1, 1, 0.45)
            let c1 = V4(c0.x, c0.y, c0.z, aimHit == nil ? 0 : c0.w)
            var lv: [SimpleVert] = []
            let q = [(o - side, c0), (end - side, c1), (end + side, c1), (o + side, c0)]
            for k in [0, 1, 2, 0, 2, 3] { lv.append(SimpleVert(pos: V4(q[k].0, 1), color: q[k].1)) }
            if let hp = aimHit {
                // A small dot where the ray lands.
                let c = hp - eye - aimDir * 0.01
                let r = simd_normalize(simd_cross(aimDir, V3(0, 1, 0) + V3(0.001, 0, 0))) * 0.012
                let u = simd_normalize(simd_cross(r, aimDir)) * 0.012
                let dq = [c - r - u, c + r - u, c + r + u, c - r + u]
                for k in [0, 1, 2, 0, 2, 3] { lv.append(SimpleVert(pos: V4(dq[k], 1), color: V4(c0.x, c0.y, c0.z, 0.9))) }
            }
            if let off = app.scene.push(s, lv) { app.scene.drawScratch(s, "simple", offset: off, count: lv.count) }
        }
    }

    // The held item in the aiming hand: guns as their solid models (barrel along the ray), blocks as small cubes,
    // other items as two-layer sprites leaning forward like they're gripped.
    private func drawHeld(_ s: SceneRenderer.Slot, eye: V3) {
        let hd = app.input.hands[aimHand]
        guard hd.aimValid, game.menu == nil, !game.paused, game.sleeping == 0 else { return }
        let held = game.held
        if held.isEmpty { return }
        let rig = app.rig
        let pos = rig.toWorld(hd.aimPos) - eye
        let rot = rig.toWorldRot(hd.aimRot)
        let pe = game.player.eye
        let l = game.world.lightAt(Int(floor(pe.x)), Int(floor(pe.y)), Int(floor(pe.z)))
        let skyK: Float = 0.12 + 0.88 * game.daylight
        let light = max(0.15, max(Float(l.sky) / 15 * skyK, Float(l.block) / 15), game.nightVision * 0.9)
        if let gi = game.heldGun {
            let (ptr, off, cap) = app.scene.reserve(s, MobVert.self)
            guard cap > 1024 else { return }
            let n = Guns.writeFirstPerson(gi, aim: 1, kick: game.arms.kick, lower: 0, bob: .zero, light: light, into: ptr)
            let ads = V3(0, -0.085, -0.44)
            for i in 0..<n {
                let v = ptr[i].pos
                let local = V3(v.x, v.y, v.z) - ads + V3(0, 0.035, 0.06)      // the grip sits in the hand
                let w = rot.act(local) + pos
                ptr[i].pos = V4(w.x, w.y, w.z, v.w)
            }
            app.scene.commit(off, n, MobVert.self)
            app.scene.drawScratch(s, "mob", offset: off, count: n)
            return
        }
        let (ptr, off, cap) = app.scene.reserve(s, EntityVert.self, max: 96)
        guard cap >= 96 else { return }
        var wr = EntityWriter(out: ptr, capacity: cap)
        if let b = held.def.block, !Blocks.flatIcon(b) {
            let t = Blocks.tint[Int(b)]
            let tint = t == 1 || t == 3 ? V3(0.57, 0.74, 0.35) : (t == 2 ? V3(0.47, 0.67, 0.18) : V3(1, 1, 1))
            wr.cube(center: .zero, half: 0.06, yaw: 0, block: b, light: light, tint: tint)
            for i in 0..<wr.n {
                let v = ptr[i].pos
                let w = rot.act(V3(v.x, v.y, v.z) + V3(0, 0.02, -0.09)) + pos
                ptr[i].pos = V4(w.x, w.y, w.z, v.w)
            }
        } else {
            let layer = Items.texLayer(held.item) ?? Int(Blocks.tex[Int(held.def.block ?? 0) * 6])
            let r = rot.act(simd_normalize(V3(0, 0.15, -1))), up = rot.act(simd_normalize(V3(0, 1, 0.15)))
            let side = rot.act(V3(1, 0, 0))
            let c = pos + rot.act(V3(0, 0.07, -0.12))
            for (i, o) in [Float(0), 0.006].enumerated() {
                wr.sprite(center: c + side * o, half: 0.12, right: r, up: up, layer: layer, light: light * (i == 0 ? 1 : 0.7))
            }
        }
        app.scene.commit(off, wr.n, EntityVert.self)
        app.scene.drawScratch(s, "entity", offset: off, count: wr.n)
    }

    // Aboard a moving ship: a faint level ring with a forward notch at the user's feet, fixed to the user's body
    // (not the hull), a stable reference while the deck turns and pitches.
    private func drawDeckReference(_ s: SceneRenderer.Slot, eye: V3) {
        let a = deckReference * QuestSettings.deckRing
        guard a > 0.02 else { return }
        let rig = app.rig
        let c = V3(rig.headWorld.x, game.player.pos.y + 0.03, rig.headWorld.z) - eye
        var v: [SimpleVert] = []
        let seg = 40
        let r0: Float = 0.42, r1: Float = 0.47
        let col = V4(0.75, 0.92, 1, 0.38 * a)
        func quad(_ q: [V3]) { for k in [0, 1, 2, 0, 2, 3] { v.append(SimpleVert(pos: V4(q[k], 1), color: col)) } }
        for i in 0..<seg {
            let a0 = Float(i) / Float(seg) * 2 * .pi, a1 = Float(i + 1) / Float(seg) * 2 * .pi
            let d0 = V3(cosf(a0), 0, sinf(a0)), d1 = V3(cosf(a1), 0, sinf(a1))
            quad([c + d0 * r0, c + d1 * r0, c + d1 * r1, c + d0 * r1])
        }
        // Forward notch (the body's facing).
        let f = rig.yawRot.act(V3(0, 0, -1)), r = rig.yawRot.act(V3(1, 0, 0))
        quad([c + f * r1 - r * 0.03, c + f * r1 + r * 0.03, c + f * (r1 + 0.12) + r * 0.03, c + f * (r1 + 0.12) - r * 0.03])
        if let off = app.scene.push(s, v) { app.scene.drawScratch(s, "panelVignette", offset: off, count: v.count) }
    }

    // Panels and the comfort vignette, over everything.
    func drawOverlay(_ s: SceneRenderer.Slot, eye: V3) {
        if let panel, (!game.hideHUD || game.menu != nil) {
            let (rx, uy, n) = panelAxes()
            let c = panelCenter - eye
            let m = float4x4(columns: (V4(rx * panelSize.x, 0), V4(uy * panelSize.y, 0), V4(n, 0), V4(c, 1)))
            let inMenu = mode == .menu
            panel.draw(s, model: m, alpha: inMenu ? 1 : 0.95, onTop: true)
        }
        if let hp = hintPanel, let h = hint, let hit = aimHit, game.menu == nil {
            // Beside the dot, a little above, facing the head; about 3 degrees tall wherever it is.
            let head = app.rig.headWorld
            let dist = max(0.3, simd_length(hit - head))
            let toHead = simd_normalize(head - hit)
            let right = simd_normalize(simd_cross(V3(0, 1, 0), toHead) + V3(1e-5, 0, 0))
            let up = simd_cross(toHead, right)
            let hgt = dist * 0.055
            let wpx = min(Float(hp.width), QuestLabel.width(h, scale: 4))
            let wid = hgt * Float(hp.width) / Float(hp.height)
            let c = hit + toHead * 0.05 + up * hgt * 1.1 + right * (wid * wpx / Float(hp.width) * 0.5 + hgt * 0.4) - eye
            let m = float4x4(columns: (V4(right * wid, 0), V4(up * hgt, 0), V4(toHead, 0), V4(c, 1)))
            hp.draw(s, model: m, alpha: 1, onTop: true)
        }
        drawDeckReference(s, eye: eye)
        let k = vignette * QuestSettings.vignette
        guard k > 0.02 else { return }
        // A ring in clip space (w = 2): clear in the middle, dark at the edge.
        var v: [SimpleVert] = []
        let seg = 32
        let r0: Float = 1.25 - 0.55 * k, r1: Float = r0 + 0.35, r2: Float = 3
        for i in 0..<seg {
            let a0 = Float(i) / Float(seg) * 2 * .pi, a1 = Float(i + 1) / Float(seg) * 2 * .pi
            let d0 = V2(cosf(a0), sinf(a0)), d1 = V2(cosf(a1), sinf(a1))
            let ring: [(Float, Float)] = [(r0, 0), (r1, 1), (r2, 1)]
            for j in 0..<2 {
                let (ra, aa) = ring[j], (rb, ab) = ring[j + 1]
                let p = [(d0 * ra, aa), (d1 * ra, aa), (d1 * rb, ab), (d0 * rb, ab)]
                for t in [0, 1, 2, 0, 2, 3] {
                    v.append(SimpleVert(pos: V4(p[t].0.x, p[t].0.y, 0, 2), color: V4(0, 0, 0, p[t].1 * min(1, k * 1.2))))
                }
            }
        }
        if let off = app.scene.push(s, v) { app.scene.drawScratch(s, "panelVignette", offset: off, count: v.count) }
    }
}
