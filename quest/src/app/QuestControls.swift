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
    unowned let app: QuestApp
    let game: Game
    let hudHost: Renderer
    private(set) var panel: HudPanel?
    static let panelW = 1280, panelH = 800

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

    // Panel placement
    private enum PanelMode { case hud, menu }
    private var mode = PanelMode.hud
    private var panelCenter = V3.zero          // world
    private var panelYaw: Float = 0
    private var panelPitch: Float = 0
    private var panelSize = V2(1.3, 0.8125)
    private var hudYaw: Float = 0
    private var panelHitUV: V2?
    private var prevTrigger = false, prevGrip = false
    private var lastHoverSlot = -1

    init(app: QuestApp, game: Game) {
        self.app = app
        self.game = game
        hudHost = Renderer(game: game)
        game.screen = V2(Float(QuestControls.panelW), Float(QuestControls.panelH))
        Renderer.questHideCrosshair = true
        do { panel = try HudPanel(scene: app.scene, width: QuestControls.panelW, height: QuestControls.panelH) }
        catch { print("hud panel: \(error)") }
        hudYaw = game.player.yaw
    }

    // MARK: Per frame, before Game.tick

    func update(dt: Float) {
        let xr = app.xr, rig = app.rig
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
                    rig.bodyYaw -= (tx > 0 ? 1 : -1) * QuestSettings.snapAngle * .pi / 180
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
        } else {
            panelHitUV = nil
            prevTrigger = R.trigger > 0.6; prevGrip = R.squeeze > 0.6
            // Locomotion frame: the head (or the moving hand) yaw; the game moves relative to the aim yaw.
            let moveYaw: Float
            if QuestSettings.headLocomotion || !L.aimValid { moveYaw = rig.headYaw }
            else { moveYaw = XRMath.yawPitch(rig.toWorldRot(L.aimRot)).0 }
            aimGame()
            let d = moveYaw - game.player.yaw
            let s = L.stick
            // Stick (x right, y forward) turned from the locomotion frame into the aim frame.
            p.lx = s.x * cosf(d) + s.y * sinf(d)
            p.ly = -s.x * sinf(d) + s.y * cosf(d)
        }
        PadManager.shared.touch = p
        lastFeet = game.player.pos
    }

    // After Game.tick: the camera follows the moved player; head-space audio; vignette from motion.
    func afterTick(dt: Float) {
        let rig = app.rig
        rig.refresh(game: game)
        game.sound?.setListener(eye: rig.headWorld, yaw: rig.headYaw, pitch: rig.headPitch, cave: game.sound?.cave ?? 0,
                                underwater: game.player.headInWater)
        let moved = simd_length(V2(game.player.pos.x - lastFeet.x, game.player.pos.z - lastFeet.z)) / max(dt, 1e-3)
        let vy = abs(game.player.pos.y - lastFeet.y) / max(dt, 1e-3)
        let speed = moved + vy * 0.5
        var want: Float = min(1, max(0, (speed - 1.2) / 6))
        if game.riding != nil || game.world.ships.aboard != nil { want = min(1, want + 0.2) }
        want = max(want, turnFlash)
        turnFlash = max(0, turnFlash - dt * 5)
        vignette += (want - vignette) * min(1, dt * (want > vignette ? 10 : 3))
        // Panel follows the menu state.
        if game.menu != nil || game.paused {
            if mode != .menu { placeMenuPanel() }
        } else if mode != .hud { mode = .hud }
        if mode == .hud { placeHudPanel(dt) }
    }

    private func roomScale() {
        let rig = app.rig
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
            // Distance to the hit block's box along the ray (the cell centre is close enough for picking).
            let c = V3(Float(hit.hit.x) + 0.5, Float(hit.hit.y) + 0.5, Float(hit.hit.z) + 0.5)
            best = min(best, max(0.3, simd_dot(c - aimOrigin, aimDir) - 0.3))
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

    // MARK: Panels

    private func placeMenuPanel() {
        mode = .menu
        let rig = app.rig
        let yaw = rig.headYaw
        let fwd = V3(-sinf(yaw), 0, -cosf(yaw))
        panelCenter = rig.headWorld + fwd * 1.15 + V3(0, -0.1, 0)
        panelYaw = yaw
        panelPitch = 0
        panelSize = V2(1.5, 1.5 * Float(QuestControls.panelH) / Float(QuestControls.panelW))
    }

    // HUD: in the lower view, turning with the head once it looks more than 25 degrees away.
    private func placeHudPanel(_ dt: Float) {
        let rig = app.rig
        var diff = rig.headYaw - hudYaw
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        if abs(diff) > 25 * .pi / 180 { hudYaw += diff * min(1, dt * 3) }
        let fwd = V3(-sinf(hudYaw), 0, -cosf(hudYaw))
        panelCenter = rig.headWorld + fwd * 1.25 + V3(0, -0.42, 0)
        panelYaw = hudYaw
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
            if trig && !prevTrigger { input.leftClicked = true; app.xr.haptic(aimHand, amplitude: 0.3, seconds: 0.02, frequency: 300) }
            if grip && !prevGrip { input.rightClicked = true; app.xr.haptic(aimHand, amplitude: 0.3, seconds: 0.02, frequency: 300) }
            input.leftDown = trig
            input.rightDown = grip
            if game.menuCursor != lastHoverSlot { lastHoverSlot = game.menuCursor; app.xr.haptic(aimHand, amplitude: 0.12, seconds: 0.01, frequency: 320) }
        } else {
            input.leftDown = false; input.rightDown = false
        }
        prevTrigger = trig; prevGrip = grip
    }

    // MARK: Drawing

    // HUD pass (before the world pass): the game's 2D HUD / menus into the panel image.
    func recordPanel(_ s: SceneRenderer.Slot) {
        guard let panel else { return }
        hudHost.fps = app.stats.fps
        hudHost.gpuFrameMs = app.scene.gpuMs
        hudHost.drawnChunks = app.scene.visibleCount
        let verts = hudHost.buildHUD(Float(panel.width), Float(panel.height))
        panel.record(s, verts)
    }

    func drawOpaque(_ s: SceneRenderer.Slot, eye: V3) {
        let xr = app.xr, rig = app.rig
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

    // Panels and the comfort vignette, over everything.
    func drawOverlay(_ s: SceneRenderer.Slot, eye: V3) {
        if let panel, (!game.hideHUD || game.menu != nil) {
            let (rx, uy, n) = panelAxes()
            let c = panelCenter - eye
            let m = float4x4(columns: (V4(rx * panelSize.x, 0), V4(uy * panelSize.y, 0), V4(n, 0), V4(c, 1)))
            let inMenu = mode == .menu
            panel.draw(s, model: m, alpha: inMenu ? 1 : 0.95, onTop: true)
        }
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
