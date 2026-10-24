import Foundation
import simd
import CVulkan

// Touch controllers -> the game. Everything goes through the game's own controller and mouse paths, so no gameplay
// code changes:
//  - The right-hand ray (left-handed: the left) is cast into the world; the game's look direction is then aimed from
//    the player's eye at the point the ray hits, so the game's targeting, mining, using and shooting pick exactly what
//    the laser points at.
//  - The left stick moves relative to the head yaw only (Player.moveYaw): the controllers' pointing never steers
//    walking, flying, swimming or ladders. The right stick turns the body (snap or smooth); reclined, its up/down
//    tips the view in steps.
//  - Buttons: right trigger = RT (mine / fire; Reclined melee: also attacks; Swing melee: only a blade that hits a mob does),
//    left trigger = LT (use / place / aim), A jump, B back (hold: drop), X pick block / reload, Y fly toggle
//    (hold: inventory), left grip = previous hotbar slot, right grip = next, right stick click hold = the
//    weapon wheel (the grips step the hotbar), left stick click = sneak (tap latches), the stick clicked while
//    pushed = sprint (1.6x, a tick on the left hand, edge streaks), menu = pause (hold: recentre the view).
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
    // Q2c-console-70: the card over a controller held up and looked at: the hand looked at and for how long, the hand
    // whose card is shown (kept while it fades out), the card recorded in the panel, and its alpha.
    private var ctrlPanel: HudPanel?
    private var ctrlLookHand = -1, ctrlLook: Float = 0, ctrlShowHand = -1, ctrlRecorded = -1, ctrlAlpha: Float = 0
    private func controllerGaze(_ hands: [XRHand], dt: Float, inMenu: Bool) {
        var want = -1
        if QuestSettings.ctrlHints && !inMenu && game.alive && laserFade > 0.5 {
            let rig = app.rig
            let fwd = simd_normalize(rig.toWorldDir(rig.headRot.act(V3(0, 0, -1))))
            var best: Float = 0.5
            let lost = (app.input as? HandedInput)?.lost ?? [false, false]
            for h in 0..<min(2, hands.count) where hands[h].gripValid && !lost[h] {
                let d = rig.toWorld(hands[h].gripPos) - rig.headWorld, l = simd_length(d)
                guard l > 0.12 && l < best, simd_dot(d / l, fwd) > 0.92 else { continue }
                best = l; want = h
            }
        }
        if want != ctrlLookHand { ctrlLookHand = want; ctrlLook = 0 } else if want >= 0 { ctrlLook += dt }
        let show = want >= 0 && ctrlLook > 0.33
        if show { ctrlShowHand = want }
        ctrlAlpha += ((show ? 1 : 0) - ctrlAlpha) * min(1, dt * (show ? 8 : 6))
    }
    // The buttons of the controller in logical hand `h`, named for the physical controller (Dominant Hand Left swaps
    // the actions; the Menu button is always on the physical left controller).
    private func ctrlLines(_ h: Int) -> [String] {
        var lines = h == aimHand
            ? ["Right controller", "Trigger: mine, attack, fire", "Grip: next hotbar slot", "A: jump", "B: back (hold: drop item)", "Stick: turn (click: weapon wheel)"]
            : ["Left controller", "Trigger: use, place, eat", "Grip: previous hotbar slot", "X: pick block (hold: off hand)", "Y: hold for inventory (tap: fly)", "Stick: move (click: sneak)"]
        if QuestSettings.leftHanded { lines = lines.map { ContextPrompts.mirrorHands($0) } }
        if (QuestSettings.leftHanded ? 1 - h : h) == 0 { lines.append("Menu: pause (hold: recenter)") }
        return lines
    }
    private(set) var hint: String?
    private var offTracked = false
    private var offRelAvg = V3(0, -0.8, 0)      // R1: the off hand against the head, smoothed over ~0.5 s
    private var wellCued = false
    private var laserFade: Float = 1            // R12: the laser fades out during a swing
    private var braceRot: simd_quatf?          // R6: the braced rifle's world rotation (barrel between the hands)
    private var hintShown: String?
    private var hintKey = ""
    static var keyboardHook: ((Bool) -> Void)?
    static let hintW = 640, hintH = 48
    static let panelW = 1024, panelH = 640
    // The panels' size and distance in metres: the HUD below the view, menus in front (questcheck's VR text check).
    static let hudWidthM: Float = 1.25, hudDistM: Float = 1.25, menuWidthM: Float = 1.5, menuDistM: Float = 1.15

    private var snapArmed = true
    private var flickArmed = true
    private var flyPulse = 0
    private var yBlock = false
    private var bHold: Float = 0, bPulse = 0
    private var l3Hold: Float = 0               // s the left stick click has been held (sneak)
    private var lastAimHand: XRHand?               // drawHeld: the last tracked aim pose
    // P403 7b (space warp motion vectors): each hand's grip pose and the held item's pose (world) at the last drawn
    // frame, and this frame's hand vertex ranges in drawOpaque's buffer.
    private var drawnGrip: [(V3, simd_quatf)?] = [nil, nil], drawnAim: (V3, simd_quatf)?
    private var handRanges: [(start: Int, count: Int, prev: float4x4)] = []
    private func motionPrev(_ pos: V3, _ rot: simd_quatf, was: (V3, simd_quatf)?, eye: V3) -> float4x4? {
        guard app.scene.spaceWarp, let w = was, simd_length_squared(w.0 - eye - pos) < 4 else { return nil }
        return SceneRenderer.motion(pos: pos, rot: rot, wasPos: w.0 - eye, wasRot: w.1)
    }
    private var sneakLatch = false              // tapped: sneak until the next tap
    private var l3Rode = false                  // the left stick click began while riding
    private var prevStickClickL = false
    private var clickSprint = false             // this stick click began with the stick pushed out: sprint, not sneak
    private var prevClickSprint = false         // (riding: one spur per click)
    private var sprintPulse = 0
    private var sprintCool: Float = 0
    private var hungryToast: Float = 0
    private var sprintFx: Float = 0             // speed streaks 0...1 (eased in and out)
    private var bBlock = false                  // B went down in a menu: its release outside isn't a sneak / dismount
    private var prevGripL = false, prevGripR = false
    // P303: grips and triggers with press / release thresholds (VRButton), per logical hand (0 move, 1 aim).
    private var gripBtn = [VRButton(), VRButton()], trigBtn = [VRButton(), VRButton()]
    private var prevLRel: V3?                      // D10: the left hand against the head last frame (shoves)
    // P371: the right grip held on the thing in the hand (a tap still steps the hotbar, on release), and the hand's
    // speed in the world, smoothed over a few frames.
    private var rHoldAt: Double = -1
    private var prevRWorld: V3?
    private var velR = V3(0, 0, 0)
    // P53 (Oct 11 evening playtest): the HUD panel rests translucent (hudFade, QuestSettings) and comes up solid for a
    // few seconds after a grip steps the hotbar, or while hurt; it eases between the two.
    private var hudSolid: Float = 0
    private(set) var hudAlpha: Float = 0.95
    static let hudRest: Float = 0.45
    private func hudFadeTick(_ dt: Float) {
        hudSolid = max(0, hudSolid - dt)
        if game.hurtFlash > 0 || game.health <= 6 { hudSolid = max(hudSolid, 1) }
        if let p = game.pickups.last, game.clock - p.at < 0.2 { hudSolid = max(hudSolid, 2) }      // Q2c-console-50
        let want: Float = !QuestSettings.hudFade || hudSolid > 0 ? 0.95 : QuestControls.hudRest
        hudAlpha += (want - hudAlpha) * min(1, dt * (want > hudAlpha ? 10 : 2))
    }
    // Swing melee (swingContact): last frame's blade capsule (world), its tip relative to the head (tracking space), the
    // mobs this swing already hit, and the slow-touch buzz timer.
    private var bladeA = V3.zero, bladeB = V3.zero, bladeTipRel = V3.zero
    private var bladeTravel: Float = 0                 // the tip's path since this swing began (P136)
    private var bladeValid = false
    private var bladeHits: [ObjectIdentifier] = []
    private var bladeHitAt: [Double] = []               // when each bladeHits mob was hit (VRMelee.rehit)
    private var touchBuzz: Float = 0
    private var blockFelt = 0                          // P308: the last SwordPlay.blockFelt felt
    private var scrapeBuzz: Float = 0                  // the blade knocking into stone: haptic rate limit
    private var bladeTrail = BladeTrail()              // the fading ribbon behind a fast blade (VRCombatFeel.swift)
    private(set) var parriesLanded = 0                 // (harness)
    var trailPeak = 0                                  // (harness) most trail segments seen
    var heldQuads = 0                                  // (harness) quads in the last held item model (P17)
    private(set) var bladeContacts = 0                 // (harness) hits landed by the blade
    private var lastHurtFlash: Float = 0
    // Q2c-console-61: Mining: Toggle: one pull at a block keeps the trigger "held" for it until it breaks, the laser
    // leaves it, the trigger is pulled again, the held item changes or a menu opens. A creature under the laser or a gun
    // in hand leaves the trigger alone.
    private var mineLatch: IVec3?, mineLatchItem: ItemID = 0, mineTrigDown = false, mineCancelHeld = false
    private func mineToggleUpdate(_ R: XRHand, inMenu: Bool, _ p: inout PadSnapshot) {
        let down = trigBtn[1].down
        let pressed = down && !mineTrigDown
        mineTrigDown = down
        guard QuestSettings.mineToggle, !inMenu, game.alive, game.heldGun == nil else { mineLatch = nil; mineCancelHeld = false; return }
        let t = game.target?.hit
        // A creature between the laser and the block: the trigger is its own again (no auto-swinging at it).
        let mobFirst = game.target.map { tg in
            game.mobs.raycast(game.player.eye, game.player.look, maxDist: 4.5).map { $0.1 < simd_length(game.hitPoint(tg) - game.player.eye) } ?? false
        } ?? false
        if let l = mineLatch, t != l || game.held.item != mineLatchItem || mobFirst {
            mineLatch = nil                                 // broken (the target moved on), looked away, another item, a creature
        }
        if pressed {
            if mineLatch != nil {
                mineLatch = nil; mineCancelHeld = true      // a second pull stops it (and this pull doesn't mine)
                app.input.haptic(aimHand, amplitude: 0.2, seconds: 0.03, frequency: 120)
            } else if let t, !mobFirst {
                mineLatch = t; mineLatchItem = game.held.item
                app.input.haptic(aimHand, amplitude: 0.25, seconds: 0.03, frequency: 220)
            }
        }
        if !down { mineCancelHeld = false }
        if mineCancelHeld { p.rt = 0 } else if mineLatch != nil { p.rt = 1 }
    }
    // Q2c-console-42: a controller that stops being tracked is named (and its return felt); both put down: paused.
    private var lostSecs: [Float] = [0, 0], lostSaid = [false, false], bothLost: Float = 0
    private func controllerWatch(_ hi: HandedInput, dt: Float) {
        for l in 0..<2 {
            let name = (QuestSettings.leftHanded ? 1 - l : l) == 1 ? "Right" : "Left"      // the physical controller
            if hi.lost[l] {
                lostSecs[l] += dt
                guard !hi.lost[1 - l] else { continue }                    // both gone: the pause below says it
                if lostSecs[l] > 2 && !lostSaid[l] {
                    lostSaid[l] = true
                    game.onToast?("\(name) controller lost: bring it into view of the headset, or check its battery")
                }
            } else {
                if lostSaid[l] {
                    game.onToast?("\(name) controller is back")
                    hi.haptic(l, amplitude: 0.35, seconds: 0.08, frequency: 160)
                }
                lostSecs[l] = 0; lostSaid[l] = false
            }
        }
        bothLost = hi.lost[0] && hi.lost[1] ? bothLost + dt : 0
        if bothLost > 3 && !game.paused && game.menu == nil && game.credits == nil && game.alive {
            game.paused = true
            PauseMenu.autoReason = "Paused: controllers put down"         // Q2c-console-44
            (game.menu as? PauseMenu)?.build()
            game.onToast?("Controllers put down: paused")
        }
    }
    private var lastHeartBeats = 0, dubIn: Float = 0        // Q2c-console-34
    // The bow (bowUpdate): an arrow nocked by the drawing hand, the draw (0...1), the haptic ramp's last step.
    private(set) var bowNocked = false
    private(set) var bowPose: VRBow.Pose?               // tracking space, while a bow is held
    private var bowTick: Float = 0, bowHum: Float = 0
    private var bowNockT: Float = 1                     // seconds since the arrow was nocked (it slides onto the string)
    private var bowDrawLast: Float = 0                  // last frame's draw (creaks as it crosses VRBow.creaks)
    private var bowReleaseT: Float = 1, bowReleaseDraw: Float = 0   // the string shivering after a shot
    private var hotbarHover: Int?
    private var yHold: Float = 0, yLong = false, yPulse = 0
    // Holding Y this long opens the inventory (a tap calls the horse or toggles flying): 0.35 s felt slow on the headset
    // (Oct 11 Quest playtest P9); 0.2 s still tells a tap from a hold.
    static let inventoryHold: Float = 0.2
    private var menuHold: Float = 0, menuLong = false, menuPulse = 0
    private var xHold: Float = 0, xLong = false, xPulse = 0, swapPulse = 0
    private var prevSelTrig = false
    private var vignette: Float = 0            // current strength 0...1
    private var rideYaw: Float?, rideVel = V2.zero, rideTurn: Float = 0, rideAccel: Float = 0   // the ridden horse (vignette)
    private(set) var wallFade: Float = 0       // the view fading to black with the head inside a solid block, 0...1
    private var turnFlash: Float = 0
    private var lastFeet = V3.zero
    private var relocateFade: Float = 0                // Q2c-console-62: 1 right after a sudden jump, fading to 0

    // Aim (world space, this frame)
    private(set) var aimOrigin = V3.zero
    private(set) var aimDir = V3(0, 0, -1)
    private var dryFelt: Double = -10                 // P301 (b): the last dry click felt in the gun hand
    private(set) var aimHit: V3?
    // S7: logical hands. Dominant Hand: Left is applied below this layer (HandedInput swaps the controllers), so hand 1
    // is always the aiming hand and hand 0 the moving one, and haptics to them reach the right physical controller.
    private let aimHand = 1
    private let moveHand = 0

    // Panel placement. Panels live in tracking space (the user's room), which the rig carries with the player: on a
    // moving ship, while turning or walking they stay put around the user instead of being left behind in the world.
    private enum PanelMode { case hud, menu }
    private var mode = PanelMode.hud
    private var panelCenterT = V3.zero         // level space (QuestRig.toLevel)
    private var panelYawT: Float = 0           // tracking-space yaw
    private var panelPitch: Float = 0
    private var panelSize = V2(1.3, 0.8125)
    private var hudYawT: Float = 0             // tracking-space yaw the HUD faces (lazily follows the head)
    private var hudPosT: V3?                   // smoothed HUD centre (level space)
    private var seenRecenters = 0
    private var panelCenter: V3 { app.rig.levelToWorld(panelCenterT) }
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
    private var lastHoverSlot = -1, hoverRest: Float = 1
    private var hipWas = false, hipAt: Double = -100          // P257: the off hand reached the hip (and when)
    private var hipReady = false                              // P286: a magazine is there to take (the hand shows it)

    // Forget held and latched buttons (the Touch matrix starts each cell clean).
    func clearLatches() { sneakLatch = false; l3Rode = false; l3Hold = 0; bHold = 0; bPulse = 0; bBlock = false }

    init(app: QuestHost, game: Game, panel: HudPanel?) {
        self.app = app
        self.game = game
        hudHost = Renderer(game: game)
        game.bufferAttacks = true                       // trigger attacks wait for the cooldown: full-strength hits
        // TV-style HUD scale (bigger text) unless the player picked one: the panel is read at arm's length.
        QuestSettings.platformDefaults()
        game.screen = V2(Float(QuestControls.panelW), Float(QuestControls.panelH))
        Renderer.questHideCrosshair = true
        self.panel = panel
        if let p = panel { hintPanel = try? HudPanel(scene: p.scene, width: QuestControls.hintW, height: QuestControls.hintH, maxVerts: 4096) }
        if let p = panel { ctrlPanel = try? HudPanel(scene: p.scene, width: 512, height: 192, maxVerts: 8192) }        // Q2c-console-70
        // Prompts name the Touch controls: the game's LT (use) is the left trigger, RT the right one.
        Glyphs.labelOverride = { g in
            switch g {
            case .lt: return "L Trigger"
            case .rt: return "R Trigger"
            case .lb: return "L Grip"
            case .rb: return "R Stick"
            // The pad's D-pad and stick clicks are Touch buttons here (drawn as a D-pad they read as nothing: the
            // horse's "<D-pad up> calls it" was blank to him, Oct 11 playtest P26).
            case .dup: return "Y"
            case .ddown: return "Hold B"
            case .dright: return "Hold X"
            case .y: return "Hold Y"
            case .l3: return "L Stick"
            default: return nil
            }
        }
        hudYawT = 0
    }

    // MARK: Per frame, before Game.tick

    func update(dt: Float) {
        let xr = app.input, rig = app.rig
        // S7/S8: swapped hands, the One Hand stick and lost controllers (HandedInput) before anything reads them.
        if let hi = xr as? HandedInput {
            hi.refresh(dt: dt, walk: game.menu == nil && !game.paused && !WeaponWheel.shared.open)
            if hi.lost[aimHand] { lastAimHand = nil }      // a lost controller: no laser or held item from a stale pose
            controllerWatch(hi, dt: dt)
        }
        ContextPrompts.vrMirror = QuestSettings.leftHanded
        let hands = xr.hands
        let L = hands[moveHand], R = hands[aimHand]
        let inMenu = game.menu != nil || game.paused
        // P303 (b): grip and trigger states with hysteresis. A hand that isn't tracked (or a lost controller, whose
        // inputs HandedInput zeroes) lets go of whatever it held; a menu or the pause lets go too.
        gripBtn[0].update(L.squeeze); gripBtn[1].update(R.squeeze)
        trigBtn[0].update(L.trigger); trigBtn[1].update(R.trigger)
        if inMenu || !game.alive { HandGrab.letGo(game, hand: 0); HandGrab.letGo(game, hand: 1) }
        controllerGaze(hands, dt: dt, inMenu: inMenu)                // Q2c-console-70
        hudFadeTick(dt)
        // Text boxes (command console, signs, world names) bring up the system keyboard (Android hook; nil in the sim).
        QuestControls.keyboardHook?(game.menu.map { $0.capturesText && !($0 is KeyboardMenu) } ?? false)

        // The weapon wheel (a right stick click opens it) takes the right stick to pick a gun: no turning meanwhile.
        WeaponWheel.clickToOpen = true                     // P208: click to open, flick to pick (CombatHUD.swift)
        let wheel = !inMenu && WeaponWheel.shared.open
        // P334: at a dropship's helm the right stick flies the craft (turn and climb), so it doesn't turn the view.
        let vtolHelm = game.world.ships.pilot.map { VehicleControls.kind($0) == .vtol } ?? false
        // Turning (never inside a menu: the panel stays put).
        if !inMenu && !wheel && !vtolHelm {
            let tx = R.stick.x
            if QuestSettings.smoothTurn && !QuestSettings.reclined {      // (lying down always snap-turns: S6)
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
        // Right stick up/down: only in Reclined Mode, where it looks up/down in snapped steps (like snap turn).
        let ty = R.stick.y
        // P325: at a warship's helm it pitches the bow instead (VehicleControls.read).
        let warHelm = game.world.ships.pilot.map { VehicleControls.kind($0) == .warship } ?? false
        VehicleControls.vrPitch = warHelm && !inMenu ? ty : nil
        if wheel || inMenu { flickArmed = false; snapArmed = false }
        else if warHelm || vtolHelm { flickArmed = false }
        else if flickArmed && abs(ty) > 0.75 && abs(R.stick.x) < 0.5 {
            flickArmed = false
            if QuestSettings.reclined {
                rig.stepPitch((ty > 0 ? 1 : -1) * QuestSettings.pitchStep * .pi / 180)
                turnFlash = max(turnFlash, 0.6)
            }
        } else if abs(ty) < 0.3 { flickArmed = true }
        game.padHotbarScroll = false

        // Roomscale: the head's walk since last frame moves the player through collision.
        roomScale()

        // Aim from the aiming hand.
        // A tracking blip keeps the last tracked hand pose (the head fallback drew the laser straight out of the eye, where
        // it can't be seen: one way it vanished).
        if let A = R.aimValid ? R : lastAimHand {
            aimOrigin = rig.toWorld(A.aimPos)
            aimDir = simd_normalize(rig.toWorldDir(A.aimRot.act(V3(0, 0, -1))))
        } else {
            aimOrigin = rig.headWorld
            aimDir = simd_normalize(rig.toWorldDir(rig.headRot.act(V3(0, 0, -1))))
        }
        // D8: the left hand's ray, for a second revolver in it (DualWield).
        DualWield.leftAim = L.aimValid ? (rig.toWorld(L.aimPos), simd_normalize(rig.toWorldDir(L.aimRot.act(V3(0, 0, -1))))) : nil
        // P159: a long gun braced with the other hand on its front grip and that trigger held aims between the hands.
        // R6 (Oct 13, after P32/G21/P159/P82: "two-handed aiming doesn't work"): the brace only turned the shot, while the
        // drawn rifle stayed on the right hand's ray, and the next frame judged the front hand against that ray again, so
        // as soon as he lined up the drawn gun the brace dropped. Now the brace holds while the left trigger stays down
        // and the hands stay a rifle's length apart and roughly ahead, and the drawn gun lies along the line between the
        // hands (braceRot), as a real rifle does. The 3.2x model's foregrip sits up to a metre ahead (far = 1.05).
        game.vrTwoHanded = false
        let wasBraced = braceRot != nil
        braceRot = nil
        // P282 (b): mounted, the left hand is on the reins or the paddle: a long gun fires from the right hand alone.
        if let gi = game.heldGun, R.aimValid, L.aimValid, gi < CapitalArms.models.count, CapitalArms.models[gi].shouldered, !inMenu, !game.mountedOneHand {
            let front = rig.toWorld(L.gripPos)
            let hold = max(L.trigger, L.squeeze)           // the left trigger, or the grip squeezed round the foregrip
            var d: V3? = VRTwoHand.braced(rear: aimOrigin, rearForward: aimDir, front: front, frontTrigger: hold, shouldered: true)
            if d == nil && wasBraced && hold > 0.3 {
                let span = front - aimOrigin, len = simd_length(span)
                if len > 0.1 && len < 1.2 && simd_dot(span / len, aimDir) > 0.4 { d = span / len }
            }
            if let d {
                let up0 = rig.toWorldRot(R.aimRot).act(V3(0, 1, 0))
                var x = simd_cross(up0, -d)
                if simd_length(x) < 1e-3 { x = simd_cross(V3(0, 1, 0), -d) }
                x = simd_normalize(x)
                let y = simd_cross(-d, x)
                braceRot = simd_quatf(float3x3(columns: (x, y, -d)))
                aimDir = d; game.vrTwoHanded = true
                if !wasBraced { app.input.haptic(moveHand, amplitude: 0.35, seconds: 0.04, frequency: 160) }
            }
        }

        // Pad for the game.
        var p = PadSnapshot()
        // Melee (docs/status/vr-melee.md). Both modes: the right trigger mines, fires and uses; hand movement alone never
        // does anything. Swing: a weapon, tool or fist hurts a mob only by physically hitting it (swingContact), and the
        // trigger never attacks. Reclined: no swinging, the trigger attacks what the laser picks.
        let held = game.held
        game.swingMelee = QuestSettings.swingMode
        game.steadySaddle = QuestSettings.steadySaddle
        Capital.fullBank = QuestSettings.craftBankFull                     // P334 (d)
        game.knockbackScale = QuestSettings.knockback               // Q2c-console-60
        game.vrShake = QuestSettings.blastShake
        game.vrHead = rig.headWorld
        p.rt = trigBtn[1].padValue                         // P303 (c): the game's 0.5 cut follows the trigger's state
        mineToggleUpdate(R, inMenu: inMenu, &p)             // Q2c-console-61
        p.lt = trigBtn[0].padValue                          // use / place (hold to repeat)
        // Only real melee weapons hit by contact; with anything else (fist, blocks, torches, food) the trigger attacks.
        if !inMenu && game.alive && game.meleeContactOnly && game.heldGun == nil { swingContact(R, dt: dt) } else { game.vrBlade = nil; bladeValid = false; bladeTrail.clear(); laserFade = min(1, laserFade + dt * 3) }
        // P300 (a): no melee tutorial toasts ("an enemy rearing back is about to strike" showed with no one near); a
        // mob's rear-back pose and grunt are the cue to dodge or parry.
        // The bow: drawn by pulling its string back with the other hand (bowUpdate); the left trigger nocks and looses.
        // Aimed at a body to skin (Hunting.swift), the left trigger skins instead of nocking.
        if !inMenu && game.alive && !held.isEmpty && Items.key(held.item) == "bow"
            && (Hunting.bodies.isEmpty || Hunting.body(game, under: game.player.eye, game.player.look) == nil) { p.lt = bowUpdate(R, L, dt: dt) } else { bowReset() }
        // Getting hurt: a thump in both hands.
        if game.hurtFlash > lastHurtFlash + 0.05 {
            app.input.haptic(0, amplitude: 0.7, seconds: 0.09, frequency: 90)
            app.input.haptic(1, amplitude: 0.7, seconds: 0.09, frequency: 90)
        }
        lastHurtFlash = game.hurtFlash
        // Q2c-console-34: near death, a lub-dub heartbeat in both hands with each beat (Feedback.tick times them).
        if Feedback.heartBeats != lastHeartBeats {
            lastHeartBeats = Feedback.heartBeats
            dubIn = 0.2
            app.input.haptic(0, amplitude: 0.45, seconds: 0.06, frequency: 70)
            app.input.haptic(1, amplitude: 0.45, seconds: 0.06, frequency: 70)
        }
        if dubIn > 0 {
            dubIn -= dt
            if dubIn <= 0 && Feedback.heartPulse > 0 {
                app.input.haptic(0, amplitude: 0.3, seconds: 0.05, frequency: 60)
                app.input.haptic(1, amplitude: 0.3, seconds: 0.05, frequency: 60)
            }
        }
        // Grips step the hotbar: left = previous slot, right = next (a press; at a ship's helm the left grip descends).
        let lGrip = gripBtn[0].down, rGrip = gripBtn[1].down
        // P177: a grip with the hand on a small creature picks it up (let go to throw it); on a carcass, drags it
        // (HandGrab.swift). Those grips don't step the hotbar.
        var handGrab = false
        if !inMenu {
            if L.gripValid, HandGrab.tick(game, hand: 0, at: rig.toWorld(L.gripPos), grip: lGrip, gripWas: prevGripL, empty: true, dt: dt) {
                handGrab = true
            } else if !L.gripValid { HandGrab.letGo(game, hand: 0) }
            if R.gripValid, HandGrab.tick(game, hand: 1, at: rig.toWorld(R.gripPos), grip: rGrip, gripWas: prevGripR, empty: game.held.isEmpty, dt: dt) {
                handGrab = true
            } else if !R.gripValid { HandGrab.letGo(game, hand: 1) }
            if handGrab && ((lGrip && !prevGripL) || (rGrip && !prevGripR)) { app.input.haptic(lGrip && !prevGripL ? moveHand : aimHand, amplitude: 0.45, seconds: 0.05, frequency: 140) }
        }
        // Riding: a hand reaching down to the horse's flank behind the saddle and gripping opens the saddlebags
        // (HorseLife.reachesSaddlebag) instead of stepping the hotbar.
        var bagGrip = false
        if !inMenu, !handGrab, let h = game.riding, MountMenu.opens(h), h.tamed {
            for (hd, now, was, i) in [(L, lGrip, prevGripL, moveHand), (R, rGrip, prevGripR, aimHand)]
                where now && !was && hd.gripValid && HorseLife.reachesSaddlebag(h, hand: rig.toWorld(hd.gripPos)) {
                game.openMenu(MountMenu(game: game, mob: h))
                app.input.haptic(i, amplitude: 0.4, seconds: 0.04, frequency: 200)
                HorseLife.bagReaches += 1
                bagGrip = true
                break
            }
        }
        // P207: the right hand on the chest pocket (left breast, under the collar) and gripped opens the journal.
        if !inMenu && !bagGrip && !handGrab && rGrip && !prevGripR && R.gripValid && game.alive {
            let hw = rig.headWorld, yaw = rig.headYaw
            let fwd = V3(-sinf(yaw), 0, -cosf(yaw)), right = V3(cosf(yaw), 0, -sinf(yaw))
            let pocket = hw + V3(0, -0.32, 0) + fwd * 0.12 - right * 0.11
            if simd_length(rig.toWorld(R.gripPos) - pocket) < 0.13 {
                game.openJournal()
                app.input.haptic(aimHand, amplitude: 0.4, seconds: 0.04, frequency: 200)
                bagGrip = true
            }
        }
        // D6: the gun hand at a holster (hip or chest) and gripped draws or holsters a handgun (Holsters.swift).
        if !inMenu && !bagGrip && !handGrab && rGrip && !prevGripR && R.gripValid && game.alive,
           Holsters.grip(game, Holsters.zone(head: rig.headWorld, yaw: rig.headYaw, hand: rig.toWorld(R.gripPos))) {
            app.input.haptic(aimHand, amplitude: 0.6, seconds: 0.05, frequency: 160)
            bagGrip = true
        }
        // P56: with a gun out, the off hand at the hip takes a magazine and slots it into the gun (VRReload); that grip
        // doesn't step the hotbar.
        var magGrip = false
        // D7: the off hand to the gun and gripped works a bolt, pump or hammer (GunActions); swing play only.
        GunActions.manual = QuestSettings.swingMode
        VRReload.buttonMode = QuestSettings.buttonReload                 // P286 (b)
        // P301 (a): a pistol's slide: the off hand grips the rear serrations as drawn, pulls back along the barrel and lets
        // go (GunActions.slideTick). A tick in both hands as it takes, a hard stop at the back, a heavy clack home.
        if !inMenu && !bagGrip && !handGrab && game.heldGun != nil && L.gripValid && R.gripValid {
            let ev = GunActions.slideTick(game, hand: rig.toWorld(L.gripPos), grip: lGrip, gripWas: prevGripL,
                                          serrations: drawnBolt(), forward: aimDir)
            switch ev {
            case .grabbed: app.input.haptic(moveHand, amplitude: 0.4, seconds: 0.03, frequency: 240)
            case .back:
                app.input.haptic(moveHand, amplitude: 0.7, seconds: 0.04, frequency: 160)
                app.input.haptic(aimHand, amplitude: 0.4, seconds: 0.03, frequency: 160)
            case .chambered:
                app.input.haptic(moveHand, amplitude: 0.9, seconds: 0.07, frequency: 110)
                app.input.haptic(aimHand, amplitude: 0.8, seconds: 0.07, frequency: 110)
            case .home: app.input.haptic(aimHand, amplitude: 0.3, seconds: 0.03, frequency: 300)
            case .none: break
            }
            if ev != .none || GunActions.slideHeld { magGrip = true }            // that grip is the slide's, not the hotbar's
        } else { GunActions.slideHeld = false }
        // P301 (b): a dry click is felt in the gun hand too: one dead tick.
        if GunActions.dryAt != dryFelt {
            dryFelt = GunActions.dryAt
            app.input.haptic(aimHand, amplitude: 0.35, seconds: 0.015, frequency: 320)
        }
        if !inMenu && !bagGrip && !handGrab && !magGrip && game.heldGun != nil && L.gripValid && R.gripValid && lGrip && !prevGripL
            && !game.arms.magInHand && !GunActions.cocked
            && VRReload.toGun(rig.toWorld(L.gripPos), gunHand: rig.toWorld(R.gripPos), forward: aimDir) < VRReload.wellReach + 0.08
            && GunActions.work(game) {
            app.input.haptic(moveHand, amplitude: 0.8, seconds: 0.06, frequency: 110)
            app.input.haptic(aimHand, amplitude: 0.5, seconds: 0.05, frequency: 110)
            magGrip = true
        }
        if !inMenu && !bagGrip && !handGrab && !magGrip && game.heldGun != nil && L.gripValid && R.gripValid {
            // R1 (Oct 13, fifth report after P74/P109/P162/P176: "the left grip is dead while I hold a gun"): a relaxed arm
            // hangs right in the hip zone, so after the first shot (the magazine no longer full) every grip with the
            // hand at rest took a magazine instead of stepping the hotbar. Only a hand that has just reached there
            // (moved against the head in the last half second) takes one; a resting hand steps the hotbar.
            let rel = rig.toWorld(L.gripPos) - rig.headWorld
            if !offTracked { offRelAvg = rel; offTracked = true }          // (a hand already at the side when the gun comes out rests)
            offRelAvg += (rel - offRelAvg) * min(1, dt * 4)
            // P257 (b, d, e): the hand arriving at the hip ticks it once when there is a magazine to take, and for two
            // seconds after arriving its grip is the pouch's even if the hand has stopped (reach, pause, squeeze).
            let fwdL = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
            let inHip = VRReload.atHip(head: rig.headWorld, hand: rig.toWorld(L.gripPos), forward: fwdL)
            // P286 (a): a firmer tick, and the hand shows a brass magazine while one is there to take (hipReady).
            let canTake = !VRReload.buttonMode && VRReload.canTake(game)
            let entered = inHip && !hipWas
            if entered {
                hipAt = game.clock
                if canTake { app.input.haptic(moveHand, amplitude: 0.5, seconds: 0.03, frequency: 300) }
            }
            hipWas = inHip
            hipReady = canTake && inHip && game.clock - hipAt < VRReload.fresh + 2
            let resting = simd_length(rel - offRelAvg) < 0.06 && !(inHip && game.clock - hipAt < VRReload.fresh)
            let ev = VRReload.tick(game, offHand: rig.toWorld(L.gripPos), gunHand: rig.toWorld(R.gripPos), head: rig.headWorld,
                                   grip: lGrip, gripWas: prevGripL, gunForward: aimDir, resting: resting, well: drawnWell(), entered: entered)
            switch ev {
            case .grabbed: app.input.haptic(moveHand, amplitude: 0.35, seconds: 0.03, frequency: 220)
            case .inserted:
                app.input.haptic(moveHand, amplitude: 1, seconds: 0.09, frequency: 120)
                app.input.haptic(aimHand, amplitude: 1, seconds: 0.09, frequency: 120)
            default: break
            }
            // Only a grip that took or slotted a magazine (P74, Oct 12 playtest: a hand resting at the side is "at the
            // hip", so with a gun out and a full magazine every left grip was refused and the hotbar never stepped).
            // P162 (Oct 13: "while reloading, the left grip can't step the hotbar"): only the press that took or seated a
            // magazine is the reload's; holding one no longer swallows the next press (that press puts it back and steps).
            magGrip = ev == .grabbed || ev == .inserted || ev == .kept
            // R7: a magazine in hand near the well ticks the off hand once (the snap is close).
            if game.arms.magInHand, let w = drawnWell() {
                let close = simd_length(rig.toWorld(L.gripPos) - w) < VRReload.wellSnap + 0.12
                if close && !wellCued { app.input.haptic(moveHand, amplitude: 0.3, seconds: 0.02, frequency: 250) }
                wellCued = close
            } else { wellCued = false }
        } else if game.heldGun == nil { game.arms.magInHand = false; offTracked = false; hipReady = false }
        // P372: a hand gripping an emplacement gun's handles takes the gun; the right hand aims it while held, and
        // letting go of both grips steps off.
        if !inMenu && !bagGrip && !handGrab && !magGrip && game.alive && Turrets.shared.manned == nil && game.world.ships.pilot == nil {
            for (hd, now, was, i) in [(L, lGrip, prevGripL, moveHand), (R, rGrip, prevGripR, aimHand)] where now && !was && hd.gripValid {
                let hand = rig.toWorld(hd.gripPos)
                guard let gun = game.mobs.mobs.first(where: { Turrets.canMan($0) && simd_length_squared($0.pos - hand) < 30 * 30
                                                           && simd_length(GunParts.handlePoint($0) - hand) < 0.75 }) else { continue }
                if game.survival && gun.deckGunCrewed(game) { app.input.haptic(i, amplitude: 0.2, seconds: 0.03, frequency: 80); bagGrip = true; break }
                Turrets.shared.mount(game, gun)
                Turrets.shared.byGrip = true
                app.input.haptic(i, amplitude: 0.6, seconds: 0.06, frequency: 120)
                bagGrip = true
                break
            }
        }
        if Turrets.shared.byGrip && Turrets.shared.manned != nil {
            Turrets.shared.handAim = R.gripValid ? aimDir : nil
            if !lGrip && !rGrip { Turrets.shared.leave(game) }
            bagGrip = true
        }
        // (A grip squeezed round the braced rifle's foregrip holds the gun, R6: it doesn't step the hotbar.)
        if !inMenu && !bagGrip && !magGrip && !handGrab && game.world.ships.pilot == nil {
            if lGrip && !prevGripL && braceRot == nil { game.select(game.selected - 1); app.input.haptic(moveHand, amplitude: 0.25, seconds: 0.02, frequency: 300) }
            // P371: with something other than a gun in the hand, the right grip's step waits for its release (a tap);
            // held and swung, it throws the thing instead.
            if rGrip && !prevGripR {
                if !game.held.isEmpty && game.heldGun == nil && R.gripValid { rHoldAt = game.clock }
                else { game.select(game.selected + 1); app.input.haptic(aimHand, amplitude: 0.25, seconds: 0.02, frequency: 300) }
            }
            if (lGrip && !prevGripL) || (rGrip && !prevGripR) { hudSolid = 4 }
        }
        if R.gripValid {
            let p = rig.toWorld(R.gripPos)
            if let q = prevRWorld, dt > 0 { velR += ((p - q) / dt - velR) * 0.5 }
            prevRWorld = p
        } else { prevRWorld = nil; velR = .zero }
        if rHoldAt >= 0 && !rGrip {
            let held = game.clock - rHoldAt
            rHoldAt = -1
            if !inMenu && game.menu == nil && R.gripValid && held > 0.15 && simd_length(velR) > 2.5 {
                if ThrownHeld.throwHeld(game, from: rig.toWorld(R.gripPos), vel: velR * 1.6) {
                    app.input.haptic(aimHand, amplitude: 0.7, seconds: 0.05, frequency: 120)
                }
            } else if held < 0.4 && game.menu == nil {
                game.select(game.selected + 1); app.input.haptic(aimHand, amplitude: 0.25, seconds: 0.02, frequency: 300)
            }
        }
        // D10: the left hand thrust hard into a creature shoves it (and breaks a raised guard).
        if L.gripValid {
            let rel = rig.toWorld(L.gripPos) - rig.headWorld
            if !inMenu, let pr = prevLRel, dt > 0, Guards.shove(game, hand: rig.toWorld(L.gripPos), vel: (rel - pr) / dt) {
                app.input.haptic(moveHand, amplitude: 0.9, seconds: 0.07, frequency: 90)
            }
            prevLRel = rel
        } else { prevLRel = nil }
        prevGripL = lGrip; prevGripR = rGrip
        // A stick click with the stick pushed out is the push itself clicking (Touch sticks click when shoved forward):
        // it sprints. Only a click with the stick near the centre sneaks (that click held sneaking, which blocks sprint).
        if L.stickClick && !prevStickClickL { clickSprint = simd_length(L.stick) > 0.45 }
        if !L.stickClick { clickSprint = false }
        prevStickClickL = L.stickClick
        let sneakClick = L.stickClick && !clickSprint
        // Any seat that sneak leaves: a mount, a boat or cart, the ship's helm, a deck gun.
        let seated = game.riding != nil || game.world.ships.pilot != nil || Turrets.shared.manned != nil
        p.a = R.button1
        // B: a tap is sneak / back (sent when it is let go); held, it drops the held item (the pad's D-pad down; keep
        // holding for the whole stack).
        if inMenu {
            p.b = R.button2
            bHold = 0; bPulse = 0
            bBlock = bBlock || R.button2                    // the B that backs out of a menu isn't also a sneak tap
        } else {
            if !R.button2 { bBlock = false }
            if R.button2 && !bBlock { bHold += dt } else if !R.button2 {
                if bHold > 0 && bHold <= 0.4 { bPulse = 3 }
                bHold = 0
            }
            // Taking a seat ends a latched sneak (it would leave the seat on the next tick).
            if seated { sneakLatch = false }
            p.b = bPulse > 0 || sneakClick || sneakLatch      // sneak (Game reads the pad's B as sneak)
            if bPulse > 0 { bPulse -= 1 }
            p.down = bHold > 0.4
        }
        // X: a tap is pick block / reload (sent when it is let go); held, it swaps the offhand (the pad's D-pad right).
        if inMenu {
            p.x = L.button1
            xHold = 0; xLong = false; xPulse = 0
        } else {
            if L.button1 { xHold += dt } else {
                if xHold > 0 && !xLong { xPulse = 3 }
                xHold = 0; xLong = false
            }
            if xHold > 0.4 && !xLong { xLong = true; swapPulse = 3 }
            p.x = xPulse > 0
            if xPulse > 0 { xPulse -= 1 }
            p.right = swapPulse > 0
            if swapPulse > 0 { swapPulse -= 1 }
        }
        // Y: a tap toggles flying (the pad's D-pad up, sent when it is let go); held, it opens the inventory.
        if inMenu {
            yBlock = yBlock && L.button2                        // the Y that opened the inventory doesn't also click in it
            p.y = L.button2 && !yBlock
            yHold = 0; yLong = false; yPulse = 0; flyPulse = 0
        } else {
            if L.button2 { yHold += dt } else {
                if yHold > 0 && !yLong { flyPulse = 3 }
                yHold = 0; yLong = false
            }
            if yHold > QuestControls.inventoryHold && !yLong { yLong = true; yBlock = true; yPulse = 3 }
            p.up = flyPulse > 0
            if flyPulse > 0 { flyPulse -= 1 }
            p.y = yPulse > 0
            if yPulse > 0 { yPulse -= 1 }
        }
        p.lb = gripBtn[0].down && game.world.ships.pilot != nil      // (the helm's descend; the hotbar no longer scrolls)
        p.rb = R.stickClick
        // Left stick click: sneak. Held, you sneak while it is held; a tap (under 0.3 s) latches sneaking until the next
        // tap (cleared by flying or water, where holding it descends). A click with the stick pushed out sprints.
        if inMenu {
            l3Hold = 0; sneakLatch = false
        } else {
            if sneakClick { if l3Hold == 0 { l3Rode = seated }; l3Hold += dt } else {
                // A click that began in a seat was the sneak that got off (the held click already leaves): it doesn't
                // latch, or the player stayed sneaking on foot and the next horse threw them off at once, or the next
                // use of the helm took the ship apart (questcheck touch matrix, Q2).
                if l3Hold > 0 && l3Hold < 0.3 && !l3Rode { sneakLatch.toggle() }
                l3Hold = 0
            }
            if game.player.flying || game.player.inWater { sneakLatch = false }
            if sneakClick && l3Hold >= 0.3 { sneakLatch = false }
        }
        p.l3 = false                                    // (sprint sets it below)
        // Menu: a tap pauses (sent when it is let go); held 0.7 s it recentres the view (reclined: world, horizon,
        // HUD and menus level to the current gaze, pitch included).
        if L.menu { menuHold += dt } else {
            if menuHold > 0 && menuHold < 0.7 { menuPulse = 3 }
            menuHold = 0; menuLong = false
        }
        if menuHold >= 0.7 && !menuLong {
            menuLong = true
            app.rig.needsRecenter = true
            game.onToast?(QuestSettings.reclined ? "View levelled to your gaze" : "View recentred")
            app.input.haptic(moveHand, amplitude: 0.4, seconds: 0.05, frequency: 200)
        }
        p.menu = menuPulse > 0
        if menuPulse > 0 { menuPulse -= 1 }
        if wheel { p.rx = R.stick.x; p.ry = R.stick.y }
        if inMenu {
            // Menus: the left stick moves the pad cursor as on the Mac; the laser is the mouse.
            p.lx = L.stick.x; p.ly = L.stick.y
            p.rx = R.stick.x; p.ry = R.stick.y          // scrolling lists, flipping crafting-book pages, panning the map
            p.lt = trigBtn[0].padValue; p.rt = 0
            p.lb = gripBtn[0].down; p.rb = false
            game.vrPinch = gripBtn[0].down && gripBtn[1].down ? simd_length(rig.toWorld(L.gripPos) - rig.toWorld(R.gripPos)) : nil
            game.vrAim = (aimOrigin, aimDir)                // P309 (b): a stack thrown out of the window leaves this hand
            menuPointer(R)
            teleAiming = false; teleArc.removeAll(); teleTarget = nil
        } else {
            panelHitUV = nil
            game.vrPinch = nil
            prevTrigger = trigBtn[1].down; prevGrip = gripBtn[1].down
            // Locomotion frame: the head yaw only (snap/smooth turns included). The right hand aims, the left hand
            // just holds the stick: neither controller's pointing direction steers walking or swimming.
            rig.updateMoveYaw(dt: dt)
            let moveYaw = rig.moveYaw
            if bowNocked, let bp = bowPose {
                // Drawing the bow: the laser runs along the nocked arrow, from the grip.
                aimOrigin = rig.toWorld(bp.grip)
                aimDir = simd_normalize(rig.toWorldDir(bp.dir))
            }
            aimGame()
            let cp = cosf(rig.headPitch)
            game.player.moveLook = V3(-sinf(moveYaw) * cp, sinf(rig.headPitch), -cosf(moveYaw) * cp)
            game.player.moveYaw = moveYaw                   // Player turns the stick by this, not by the aim yaw
            hotbarHover = nil
            if game.world.ships.pilot != nil {
                // At the helm the stick is throttle and steering: raw, whatever way the hand or head points.
                p.lx = L.stick.x; p.ly = L.stick.y
                if vtolHelm { p.rx = R.stick.x; p.ry = R.stick.y }          // P334: a VTOL's turn and climb
                teleAiming = false; teleArc.removeAll(); teleTarget = nil
            } else if QuestSettings.teleport && game.riding == nil {
                teleport(L)
            } else {
                // Raw stick (x right, y forward): Player.moveYaw is the head, so nothing the aim does matters.
                p.lx = L.stick.x; p.ly = L.stick.y
            }
            // Sprint: click the left stick while it is pushed (any direction; Touch sticks also click when shoved
            // hard). It holds until the stick comes back to the middle. A full push alone used to auto-sprint, so the
            // plain walk at full push never existed and a sprint felt no faster than walking (playtest v78); now the
            // click is a clear 1.6x jump (Player: VR sprint 6.9 b/s), with a haptic tick and speed streaks.
            let st = L.stick, sm = simd_length(st)
            sprintCool -= dt
            let fed = !(game.survival && game.hunger <= 6)          // too hungry to sprint (reference)
            // Riding a horse every click is a spur (up a gait: HorseFeel.swift), sprinting or not.
            let spurring = game.riding.map { $0.gaited && $0.tamed } ?? false
            if clickSprint && !prevClickSprint && spurring && sm > 0.3 && sprintCool <= 0 {
                sprintPulse = 3; sprintCool = 0.2
                app.input.haptic(moveHand, amplitude: 0.7, seconds: 0.06, frequency: 90)
            } else if clickSprint && sm > 0.3 && fed && !game.player.sprinting && sprintCool <= 0 && game.world.ships.pilot == nil && !spurring {
                sprintPulse = 3; sprintCool = 0.3
                sneakLatch = false
                app.input.haptic(moveHand, amplitude: 0.6, seconds: 0.08, frequency: 120)
            }
            prevClickSprint = clickSprint
            // P300 (b): no sprint how-to toasts (the speed and the haptic pulse show it).
            hungryToast -= dt
            if clickSprint && sm > 0.3 && !fed && !spurring && hungryToast <= 0 { hungryToast = 15; game.onToast?("Too hungry to sprint") }
            p.l3 = sprintPulse > 0
            if sprintPulse > 0 { sprintPulse -= 1 }
        }
        PadManager.shared.touch = p
        lastFeet = game.player.pos
    }

    // The held gun model's offset in the hand's frame (drawHeld): the screen model's sight is at its origin, so the
    // eyepiece of the drawn gun sits at the hand plus this shift.
    static func heldGunShift(_ gi: Int) -> V3 {
        let gk: Float = 3.2 * QuestSettings.heldScale
        let ads = V3(0, -0.085, -0.44)
        let grip = CapitalArms.models[gi].grip * (0.0125 * gk)
        return -ads - grip + V3(0, 0.015, 0.06)
    }

    // R7: the held gun's magazine well where it is drawn (world space), from the model's magAt.
    private func drawnWell() -> V3? {
        guard let gi = game.heldGun, gi < CapitalArms.models.count else { return nil }
        return drawnPoint(CapitalArms.models[gi].magAt)
    }

    // P301: the held gun's charging point (a pistol's rear slide serrations) where it is drawn (world space).
    private func drawnBolt() -> V3? {
        guard let gi = game.heldGun, gi < CapitalArms.models.count else { return nil }
        return drawnPoint(CapitalArms.models[gi].bolt)
    }

    // A point of the held gun model (gun pixels) where it is drawn in the aiming hand.
    private func drawnPoint(_ at: V3) -> V3? {
        guard let gi = game.heldGun, gi < CapitalArms.models.count, let hd = lastAimHand else { return nil }
        let gm = CapitalArms.models[gi]
        let k: Float = 0.0125 * 3.2 * QuestSettings.heldScale
        let local = (at - gm.grip) * k + V3(0, 0.015, 0.06)
        return app.rig.toWorld(hd.aimPos) + (braceRot ?? app.rig.toWorldRot(hd.aimRot)).act(local)
    }

    // G21: the Farsight raised to the eye (VRScope): eased 0...1, the views zoom with it.
    private(set) var scopeT: Float = 0
    private var scopeUp = false
    private func scopeTick(_ dt: Float) {
        let rig = app.rig
        var up = false
        if game.menu == nil && !game.paused, let aim = game.vrAim {
            let fwd = rig.toWorldRot(rig.headRot).act(V3(0, 0, -1))
            // R6: judged at the drawn scope's eyepiece, not at the hand. The model is drawn 3.2x with its sight about half a
            // metre behind the grip, so with the scope at his eye the hand was far past the 0.24 m reach and it never zoomed.
            var eyepiece = aim.origin
            if let gi = game.heldGun, gi < CapitalArms.models.count, let hd = lastAimHand {
                eyepiece = rig.toWorld(hd.aimPos) + (braceRot ?? rig.toWorldRot(hd.aimRot)).act(QuestControls.heldGunShift(gi))
            }
            up = VRScope.raisedBraced(held: game.held, braced: braceRot != nil, head: rig.headWorld, headForward: fwd,
                                      rearHand: aim.origin, eyepiece: eyepiece, barrel: aim.dir)
        }
        // P270 (d): a short tick in the rear hand as the scope engages.
        if up && !scopeUp { app.input.haptic(aimHand, amplitude: 0.3, seconds: 0.025, frequency: 220) }
        scopeUp = up
        scopeT = up ? min(1, scopeT + dt * 6) : max(0, scopeT - dt * 8)
        rig.zoom = VRScope.zoom(scopeT, full: VRScope.scopeZoom(game.held) ?? VRScope.zoom)
    }

    // After Game.tick: the camera follows the moved player; head-space audio; vignette from motion.
    func afterTick(dt: Float) {
        let rig = app.rig
        scopeTick(dt)
        // Q2c-console-62: a jump of more than 3 blocks inside the game tick (pearl, portal, respawn, bed, command, helm)
        // fades in from dark over a quarter second; a second jump during the fade restarts it rather than flickering.
        // (The teleport locomotion moves the feet before lastFeet is taken, so it keeps its own blink.)
        if simd_length(game.player.pos - lastFeet) > 3 { relocateFade = 1 }
        relocateFade = max(0, relocateFade - dt * 4)
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
        rig.smoothSteps(game: game, dt: dt, aboard: ship != nil)
        carryShip = ship
        carryYaw = ship?.yaw ?? 0
        carryRot = ship?.rot ?? simd_quatf()
        if let s = ship { carryLocal = s.toLocal(game.player.pos) }
        rig.chaseTick(QuestSettings.chaseView && game.alive ? (game.chaseOffset ?? .zero) : .zero, dt: dt)      // P100
        rig.refresh(game: game)
        // Head inside a solid block (seated leaning, roomscale while flying, standing up under a low ceiling): the view
        // fades to black instead of showing the world from inside a wall (the usual VR answer: no x-ray, no disorienting
        // inside-out view), and clears as the head comes out.
        let hw = rig.headWorld
        let hb = Int(game.world.block(Int(floor(hw.x)), Int(floor(hw.y)), Int(floor(hw.z))))
        let inWall: Float = game.alive && Blocks.opaque[hb] && Blocks.fullCollide[hb] ? 1 : 0
        wallFade += (inWall - wallFade) * min(1, dt * (inWall > wallFade ? 14 : 8))
        if wallFade < 0.005 { wallFade = 0 }
        game.sound?.setListener(eye: rig.headWorld, yaw: rig.headYaw, pitch: rig.headPitch, cave: game.sound?.cave ?? 0,
                                underwater: game.player.headInWater)
        // Comfort vignette: the player's own movement (relative to the deck when aboard: a ship cruising steadily is
        // comfortable, its turns, pitching and speed changes are not), snap / smooth turns.
        let moved = simd_length(V2(game.player.pos.x - lastFeet.x, game.player.pos.z - lastFeet.z)) / max(dt, 1e-3)
        let vy = abs(game.player.pos.y - lastFeet.y) / max(dt, 1e-3)
        let speed = relMoved >= 0 ? relMoved : moved + vy * 0.5
        // A sprint doesn't tunnel the view harder than a walk (the narrower view hid the speed-up: playtest v78).
        var want: Float = min(1, max(0, (min(speed, 4.4) - 1.2) / 6))
        if ship != nil {
            want = max(want, min(1, shipTurnRate * 2.5), min(1, max(0, shipAccel - 0.5) / 6))
            let shipSpeed = simd_length(carryVel)
            // P261 (b): the deck heaving under him (the vignette while piloting answers it too).
            if game.world.ships.pilot != nil { want = max(want, min(0.6, max(0, abs(carryVel.y) - 0.4) * 0.35)) }
            // At the helm of a fast ship (the frigate cruises at 42 b/s) the ground streaming past narrows the view too
            // (audit 25b6 #5); scaled by the Comfort Vignette setting like every other term (0 = off).
            if game.world.ships.pilot != nil { want = max(want, ShipComfort.vignette(speed: shipSpeed)) }
            deckReference += ((shipSpeed > 0.5 || shipTurnRate > 0.05 ? 1 : 0) - deckReference) * min(1, dt * 2)
        } else {
            deckReference = max(0, deckReference - dt * 2)
            if let h = game.riding, h.gaited {
                // A horse: its turns and speed changes darken the edges more than a steady run (RideComfort).
                var dy = h.yaw - (rideYaw ?? h.yaw)
                while dy > .pi { dy -= 2 * .pi }
                while dy < -.pi { dy += 2 * .pi }
                let v = V2(h.vel.x, h.vel.z)
                let k = min(1, dt * 8)
                rideTurn += (abs(dy) / max(dt, 1e-3) - rideTurn) * k
                rideAccel += ((rideYaw == nil ? 0 : simd_length(v - rideVel) / max(dt, 1e-3)) - rideAccel) * k
                rideYaw = h.yaw; rideVel = v
                // (in place of the walking term: a horse's steady run is lighter than the same speed on foot)
                want = RideComfort.vignette(speed: simd_length(v), turnRate: rideTurn, accel: rideAccel)
            } else {
                rideYaw = nil; rideTurn = 0; rideAccel = 0
                if game.riding != nil { want = min(1, want + 0.2) }
            }
        }
        want = max(want, min(0.8, rig.chaseSpeed * 0.08))      // the chase view easing out or back in (P100)
        // P322 (e): jet flight narrows the view with its speed and its turns (in step with the thrust easing in and out).
        if game.player.jetThrust || game.player.jetBoost > 0 {
            let fly = simd_length(game.player.vel)
            want = max(want, min(0.85, max(0, fly - 3) / 14 + game.player.jetBoost * 0.15))
        }
        want = max(want, turnFlash)
        turnFlash = max(0, turnFlash - dt * 5)
        vignette += (want - vignette) * min(1, dt * (want > vignette ? 10 : 3))
        let sprintOn = game.player.sprinting && game.player.onGround && !game.player.flying && game.menu == nil && game.riding == nil
        sprintFx = sprintOn ? min(1, sprintFx + dt * 4) : max(0, sprintFx - dt * 6)
        updateHint()
        // After a recentre (the Meta button, Recenter View) the panels come back in front of the user.
        if rig.recenters != seenRecenters {
            seenRecenters = rig.recenters
            hudYawT = rig.headYaw - rig.bodyYaw
            hudPosT = nil
            if mode == .menu { placeMenuPanel() }
        }
        // Panel follows the menu state.
        if game.menu != nil || game.paused {
            if mode != .menu { placeMenuPanel() }
            panelSize = QuestControls.menuPanelSize          // Q2c-console-49: Menu Size applies to the open menu at once
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
            // Within reach of a helm the player can take (dropships, frigates, any vessel): use takes command.
            if h == nil, let s = game.commandeerable() {
                h = use + " Take command"
                key = "c\(s.id)"
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

    // Vertex scratch for the per-frame overlay geometry (controllers, laser, arc, rings, screen effects): taken, filled,
    // pushed to the GPU scratch and handed back, so drawing allocates nothing once warm (questcheck's allocation trace).
    private var vertScratch: [SimpleVert] = []
    private func takeVerts() -> [SimpleVert] {
        var v = vertScratch
        vertScratch = []
        v.removeAll(keepingCapacity: true)
        return v
    }
    private func giveVerts(_ v: [SimpleVert]) { if v.capacity >= vertScratch.capacity { vertScratch = v } }
    static let quadOrder = [0, 1, 2, 0, 2, 3]
    static let faceShades: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
    // Controller model boxes (centre, half size): grip, pointer nose, top plate.
    static let controllerParts: [(V3, V3)] = [(V3(0, 0, 0.02), V3(0.018, 0.026, 0.05)), (V3(0, 0.012, -0.05), V3(0.012, 0.012, 0.03)),
                                              (V3(0, 0.03, 0.0), V3(0.035, 0.008, 0.035))]
    // Two triangles a b c, a c d.
    @inline(__always) static func quad(_ v: inout [SimpleVert], _ a: V4, _ b: V4, _ c: V4, _ d: V4, _ ca: V4, _ cb: V4, _ cc: V4, _ cd: V4) {
        v.append(SimpleVert(pos: a, color: ca)); v.append(SimpleVert(pos: b, color: cb)); v.append(SimpleVert(pos: c, color: cc))
        v.append(SimpleVert(pos: a, color: ca)); v.append(SimpleVert(pos: c, color: cc)); v.append(SimpleVert(pos: d, color: cd))
    }
    @inline(__always) static func quad(_ v: inout [SimpleVert], _ a: V3, _ b: V3, _ c: V3, _ d: V3, _ col: V4) {
        quad(&v, V4(a, 1), V4(b, 1), V4(c, 1), V4(d, 1), col, col, col, col)
    }

    // The arc (green when it ends on a place to stand, red otherwise) and a ring where the feet will land.
    private func drawTeleport(_ s: SceneRenderer.Slot, eye: V3) {
        guard teleAiming, teleArc.count > 1 else { return }
        let ok = teleTarget != nil
        let col = ok ? V4(0.45, 1, 0.6, 0.85) : V4(1, 0.4, 0.35, 0.7)
        var v = takeVerts()
        defer { giveVerts(v) }
        let headDir = simd_normalize(app.rig.headWorld - teleArc[teleArc.count / 2])
        for i in 0..<(teleArc.count - 1) {
            let a = teleArc[i] - eye, b = teleArc[i + 1] - eye
            let side = simd_normalize(simd_cross(teleArc[i + 1] - teleArc[i], headDir) + V3(1e-5, 0, 0)) * 0.012
            let ca = V4(col.x, col.y, col.z, col.w * Float(i + 1) / Float(teleArc.count))
            QuestControls.quad(&v, a - side, b - side, b + side, a + side, ca)
        }
        if let t = teleTarget {
            let c = (t.ship.map { $0.toWorld(t.local) } ?? t.local) + V3(0, 0.03, 0) - eye
            let seg = 24
            for i in 0..<seg {
                let a0 = Float(i) / Float(seg) * 2 * .pi, a1 = Float(i + 1) / Float(seg) * 2 * .pi
                let d0 = V3(cosf(a0), 0, sinf(a0)), d1 = V3(cosf(a1), 0, sinf(a1))
                QuestControls.quad(&v, c + d0 * 0.3, c + d1 * 0.3, c + d1 * 0.38, c + d0 * 0.38, col)
            }
        }
        if let off = app.scene.push(s, v) { app.scene.drawScratch(s, "simple", offset: off, count: v.count) }
    }

    private func roomScale() {
        let rig = app.rig
        // P226 (Oct 13 21:40, "I can't get crouch under here"): ducking for real (the head 40 cm or more below standing
        // eye height) crouches the body too, so it fits under a low gap as the stick's sneak does, and drops to a crawl
        // into one lower still (Player.update, P179). Seated play has no real duck.
        game.player.ducking = !QuestSettings.seated && !QuestSettings.reclined && game.riding == nil
            && rig.trackingHead.y + rig.heightOffset < QuestRig.eyeHeight - 0.4
        if QuestSettings.seated || QuestSettings.reclined {
            // Seated: leaning moves only the view (up to 35 cm from the centre), never the player.
            var d = rig.trackingHead - rig.anchor
            d.y = 0
            let l = simd_length(d)
            if l > 0.35 { rig.anchor += d * (1 - 0.35 / l) }
            rig.refresh(game: game)
            return
        }
        let d = rig.trackingHead - rig.anchor
        var delta = rig.toWorldDir(V3(d.x, 0, d.z))
        if simd_length_squared(delta) > 1e-8, game.menu == nil {
            let pl = game.player
            // Sneaking: a physical step doesn't carry the body off a ledge either (P126).
            if pl.sneaking && pl.onGround && !pl.flying && game.riding == nil { delta = pl.edgeClamp(delta, game.world) }
            var pos = pl.pos
            if pl.flying || game.riding != nil || game.world.ships.aboard != nil {
                if game.riding == nil { pos += delta }
            } else {
                game.world.mobsSolid = true        // P311 (a): a real step doesn't carry him through a mob either
                _ = game.world.moveBody(&pos, halfW: pl.halfW, height: pl.height, delta, step: pl.onGround ? 0.6 : 0, onGround: pl.onGround)
                game.world.mobsSolid = false
            }
            if game.riding == nil { pl.pos = pos }
        }
        rig.absorbHeadOffset()
        rig.refresh(game: game)
    }

    // Points the game's look at whatever the hand ray hits (blocks and mobs within reach, else far along the ray).
    private func aimGame() {
        // Gliding steers with the look: the head, not the hand's laser (pointing at something mid-flight yanked the
        // flight path).
        if game.player.gliding {
            game.player.yaw = app.rig.headYaw
            game.player.pitch = max(-1.55, min(1.55, app.rig.headPitch))
            aimHit = nil
            game.vrAim = nil
            return
        }
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
        game.vrAim = (aimOrigin, aimDir)                // the crossbow shoots from the aiming hand (GameCombat)
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
        panelCenterT = rig.levelHead + fwd * QuestControls.menuDistM + V3(0, -0.1, 0)
        panelYawT = yaw
        panelPitch = 0
        panelSize = QuestControls.menuPanelSize
    }
    // Q2c-console-49: Menu Size and HUD Size scale the panels' width at the same distance (the laser's hit test reads
    // the same panelSize).
    static var menuPanelSize: V2 {
        let w = menuWidthM * QuestSettings.menuScale
        return V2(w, w * Float(panelH) / Float(panelW))
    }
    static var hudPanelSize: V2 {
        let w = hudWidthM * QuestSettings.hudScale
        return V2(w, w * Float(panelH) / Float(panelW))
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
        let drop = QuestSettings.hudDrop
        // `drop` is where the hotbar sits below eye level (0.42 at 1.25 m is ~18 degrees): the panel is raised to match.
        let Lh = HudLayout(Float(QuestControls.panelW), Float(QuestControls.panelH))
        let panelH = QuestControls.hudPanelSize.y
        let hotbarBelowCentre = ((Lh.hotbarY0 + Lh.slot / 2) / Float(QuestControls.panelH) - 0.5) * panelH
        let want = rig.levelHead + fwd * QuestControls.hudDistM + V3(0, -drop + hotbarBelowCentre, 0)
        var pos = hudPosT ?? want
        pos += (want - pos) * min(1, dt * 12)
        if simd_length(want - pos) > 0.5 { pos = want }
        hudPosT = pos
        panelCenterT = pos
        panelYawT = hudYawT
        panelPitch = -atan2f(drop, 1.25) * 0.7              // the hotbar end tilted to face the eyes
        panelSize = QuestControls.hudPanelSize
    }

    // Panel axes (world): right, up, normal toward the viewer.
    private func panelAxes() -> (V3, V3, V3) {
        let q = simd_quatf(angle: panelYaw, axis: V3(0, 1, 0)) * simd_quatf(angle: panelPitch, axis: V3(1, 0, 0))
        return (q.act(V3(1, 0, 0)), q.act(V3(0, 1, 0)), q.act(V3(0, 0, 1)))
    }

    // Swing melee (VRMelee): the held weapon, tool or fist is a capsule along the drawn blade (a little longer and
    // thicker). Swept from last frame's pose to this one it hits the first mob it touches, if the tip moves at
    // VRMelee.minTipSpeed or more relative to the head (walking, turning or a mob walking into a still blade is no hit),
    // within VRMelee.reach of the eyes and in sight. Each mob once per swing (the swing ends when the tip slows below
    // VRMelee.rearmSpeed). A hit: a strong buzz scaled by power and crit sparks where it landed; a slower touch: a light
    // tick. Blocks are never touched: the trigger mines.
    private func swingContact(_ R: XRHand, dt: Float) {
        let rig = app.rig
        game.swingPower = 0; game.swingMob = nil                  // never a stale hit from a frame interact didn't run
        game.vrBlade = nil
        guard dt > 1e-3, R.aimValid else { bladeValid = false; return }
        let (h, tool) = heldSize()
        let (base, tip, radius) = VRMelee.blade(handPos: R.aimPos, handRot: R.aimRot, size: h, tool: tool)
        let a1 = rig.toWorld(base), b1 = rig.toWorld(tip)
        game.vrBlade = (a1, b1)                                    // P308: a blade held across a strike blocks it
        // P308: each block lands in both hands.
        if SwordPlay.blockFelt != blockFelt {
            blockFelt = SwordPlay.blockFelt
            app.input.haptic(aimHand, amplitude: 0.9, seconds: 0.06, frequency: 300)
            app.input.haptic(moveHand, amplitude: 0.45, seconds: 0.05, frequency: 300)
        }
        let tipRel = tip - rig.trackingHead
        let a0 = bladeA, b0 = bladeB, prevRel = bladeTipRel
        bladeA = a1; bladeB = b1; bladeTipRel = tipRel
        touchBuzz = max(0, touchBuzz - dt)
        guard bladeValid else { bladeValid = true; return }
        // A jump of more than 1.5 m (teleport, respawn, boarding) is not a swing.
        guard simd_length(a1 - a0) < 1.5 else { bladeTrail.clear(); return }
        let speed = simd_length(tipRel - prevRel) / dt
        laserFade = speed > VRMelee.rearmSpeed ? max(0, laserFade - dt * 12) : min(1, laserFade + dt * 3)
        bladeTrail.add(base: a1, tip: b1, speed: speed, now: game.clock)
        trailPeak = max(trailPeak, bladeTrail.segmentCount(now: game.clock))
        if speed < VRMelee.rearmSpeed { bladeHits.removeAll(keepingCapacity: true); bladeHitAt.removeAll(keepingCapacity: true); bladeTravel = 0 }
        else { bladeTravel += simd_length(tipRel - prevRel) }
        // Several hits a second: a mob can take the blade again VRMelee.rehit after its last hit.
        while let t = bladeHitAt.first, game.clock - t >= VRMelee.rehit { bladeHits.removeFirst(); bladeHitAt.removeFirst() }
        // The blade knocking into stone or wood: a dull knock in the hand (blocks are never broken by a swing).
        scrapeBuzz = max(0, scrapeBuzz - dt)
        if speed >= VRMelee.minTipSpeed && scrapeBuzz <= 0
            && Blocks.collide[Int(game.world.block(Int(floor(b1.x)), Int(floor(b1.y)), Int(floor(b1.z))))] {
            scrapeBuzz = 0.2
            app.input.haptic(aimHand, amplitude: 0.45, seconds: 0.03, frequency: 240)
        }
        // Hostiles take a casual swing; villagers, townsfolk, golems, animals and pets only with the trigger held.
        guard let (m, point) = game.bladeContact(a0: a0, b0: b0, a1: a1, b1: b1, radius: radius, eye: rig.headWorld, except: bladeHits,
                                                 deliberate: trigBtn[1].down) else { return }
        if speed >= VRMelee.minTipSpeed {
            let along = simd_normalize(b1 - b0 + V3(0, 1e-4, 0))
            // Into a mob winding up, at its arms or weapon: a parry (no damage; it staggers back).
            if game.tryParry(m, at: point, along: along) {
                bladeHits.append(ObjectIdentifier(m)); bladeHitAt.append(game.clock)
                parriesLanded += 1
                app.input.haptic(aimHand, amplitude: 1, seconds: 0.05, frequency: 340)
                app.input.haptic(moveHand, amplitude: 0.5, seconds: 0.05, frequency: 340)
                return
            }
            // P308 (a): how it struck: a cut across the blade, a drag along it, a thrust; square into the body or a graze.
            let bladeDir = simd_normalize(b1 - a1 + V3(0, 1e-5, 0))
            let into = simd_normalize(m.pos + V3(0, m.height * 0.5, 0) - point + V3(0, 1e-5, 0))
            let pow = VRMelee.power(speed) * VRMelee.travelBonus(bladeTravel) * SwordPlay.cut(blade: bladeDir, motion: along, into: into)
            game.swingPower = pow
            game.swingMob = m
            bladeHits.append(ObjectIdentifier(m)); bladeHitAt.append(game.clock)
            bladeContacts += 1
            game.swingPoint = point          // the contact flash and sparks there once the hit lands (Game.bladeFlash)
            game.swingDir = along
            // Flesh thuds, armour rings, bone and stone knock (HitFeel).
            let (amp, secs, freq) = HitFeel.of(m).haptic(power: pow)
            app.input.haptic(aimHand, amplitude: amp, seconds: secs, frequency: freq)
        } else if touchBuzz <= 0 {
            touchBuzz = 0.3
            app.input.haptic(aimHand, amplitude: 0.15, seconds: 0.02, frequency: 250)
        }
    }

    // The bow in the aiming hand, drawn by the other hand: its trigger with the hand at the string (VRBow.nockRange of
    // the resting nock) nocks an arrow; pulling back draws it (the string and arrow follow the hand, the drawing hand
    // feels a ramping tension); letting go of the trigger looses it along the arrow, from the drawing hand through the
    // grip. Returns the game's use trigger (held while nocked: Game charges and fires the bow from game.vrBow).
    private func bowUpdate(_ R: XRHand, _ L: XRHand, dt: Float) -> Float {
        guard R.aimValid else { bowReset(); return 0 }
        let rig = app.rig, rot = R.aimRot
        let grip = R.aimPos + rot.act(V3(0, 0.01, -0.03))
        let trig = trigBtn[0].down
        let hasArrow = !game.survival || game.arrowSlot() != nil
        if trig && !bowNocked && L.aimValid && hasArrow {
            if simd_length(L.aimPos - VRBow.restNock(grip: grip, handRot: rot)) < VRBow.nockRange {
                bowNocked = true; bowTick = 0; bowHum = 0; bowNockT = 0; bowDrawLast = 0
                app.input.haptic(moveHand, amplitude: 0.35, seconds: 0.03, frequency: 220)
                game.sfx(.bowNock, 0.6, at: rig.toWorld(grip))
            }
        }
        let wasNocked = bowNocked
        let pose = VRBow.pose(grip: grip, handRot: rot, drawHand: bowNocked && L.aimValid ? L.aimPos : nil)
        bowPose = pose
        game.vrBow = (draw: pose.draw, origin: rig.toWorld(pose.grip) + rig.toWorldDir(pose.dir) * 0.1, dir: simd_normalize(rig.toWorldDir(pose.dir)))
        bowNockT += dt; bowReleaseT += dt
        if bowNocked {
            // The limbs creak as the draw passes 35, 65 and 90 % (louder the further it bends).
            if VRBow.creak(from: bowDrawLast, to: pose.draw) != nil { game.sfx(.bowCreak, 0.3 + 0.4 * pose.draw, at: rig.toWorld(grip)) }
            bowDrawLast = pose.draw
            // Tension: a tick in the drawing hand at every tenth of the draw, stronger and deeper as it bends; a steady
            // hum in both hands at full draw.
            if pose.draw >= bowTick + 0.1 {
                bowTick = floorf(pose.draw * 10) / 10
                app.input.haptic(moveHand, amplitude: 0.12 + 0.5 * pose.draw, seconds: 0.025, frequency: 120 + 140 * pose.draw)
            } else if pose.draw < bowTick - 0.15 { bowTick = floorf(pose.draw * 10) / 10 }
            bowHum -= dt
            if pose.draw >= 1 && bowHum <= 0 {
                bowHum = 0.12
                app.input.haptic(moveHand, amplitude: 0.3, seconds: 0.12, frequency: 90)
                app.input.haptic(aimHand, amplitude: 0.2, seconds: 0.12, frequency: 90)
            }
        }
        if !trig && bowNocked {
            bowNocked = false                               // looses this frame (the game sees the use trigger let go)
            if pose.draw >= 0.1 {
                app.input.haptic(aimHand, amplitude: 0.8, seconds: 0.06, frequency: 140)
                // The string shivers (drawBow) and the bow hand feels it buzz out.
                bowReleaseT = 0; bowReleaseDraw = pose.draw
                app.input.haptic(aimHand, amplitude: 0.35 * pose.draw, seconds: 0.25, frequency: 210)
            }
        }
        return wasNocked && trig ? 1 : 0
    }

    private func bowReset() {
        bowNocked = false; bowPose = nil
        game.vrBow = nil
    }

    // (harness) this frame's blade capsule in world space.
    var bladeWorld: (V3, V3) { (bladeA, bladeB) }

    // The held item's drawn size (drawHeld): the icon's half size, and whether it is held as a tool by the handle.
    func heldSize() -> (Float, Bool) {
        let held = game.held
        if held.isEmpty { return (0, false) }
        let k = Items.key(held.item)
        let big = k.hasSuffix("_sword") || k == "trident" || k == "mace" || k.hasSuffix("_spear")
        let tool = held.def.tool != .none || held.def.attack > 1.5 || k.hasSuffix("bow") || k == "fishing_rod"
        let size: Float = big ? 0.55 : (tool ? 0.47 : 0.2)              // x1.3 (store pass: still read small)
        return (size * QuestSettings.heldScale, big || tool)
    }

    // Touch-select: pointing the laser at a hotbar slot on the HUD panel and pulling the trigger picks it (the trigger
    // does not break blocks meanwhile). Returns true while the laser is over the hotbar.
    private func hotbarPointer(_ R: XRHand) -> Bool {
        let trig = trigBtn[1].down
        defer { prevSelTrig = trig }
        guard mode == .hud, game.menu == nil, game.world.ships.pilot == nil else { hotbarHover = nil; return false }
        let (rx, uy, n) = panelAxes()
        let denom = simd_dot(aimDir, n)
        guard denom < -1e-3 else { hotbarHover = nil; return false }
        let t = simd_dot(panelCenter - aimOrigin, n) / denom
        guard t > 0 else { hotbarHover = nil; return false }
        let hit = aimOrigin + aimDir * t
        let px = (simd_dot(hit - panelCenter, rx) / panelSize.x + 0.5) * Float(QuestControls.panelW)
        let py = (0.5 - simd_dot(hit - panelCenter, uy) / panelSize.y) * Float(QuestControls.panelH)
        let L = HudLayout(Float(QuestControls.panelW), Float(QuestControls.panelH))
        let i = Int(floor((px - L.hotbarX0) / L.slot))
        guard i >= 0 && i < 9 && py >= L.hotbarY0 - L.slot * 0.5 && py < L.hotbarY0 + L.slot * 1.5 else { hotbarHover = nil; return false }
        if hotbarHover != i { hotbarHover = i; app.input.haptic(aimHand, amplitude: 0.12, seconds: 0.01, frequency: 320) }
        if trig && !prevSelTrig {
            game.select(i)
            app.input.haptic(aimHand, amplitude: 0.3, seconds: 0.02, frequency: 300)
        }
        return true
    }

    // The laser on the menu panel drives the game's mouse.
    private var lastLaser = V2(-100, -100)
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
        // R4 (Oct 13, after P73/P195: "pointing at the map and pulling the trigger doesn't set a waypoint"): the analog
        // trigger hovering around one threshold read as press, release, press within a pull, and the map's tap toggles a
        // pin (the second click took the first one away again). Pressed past 0.6, let go under 0.35.
        let trig = trigBtn[1].down, grip = gripBtn[1].down          // (P303: VRButton's thresholds)
        if let uv {
            let mx = uv.x * Float(QuestControls.panelW), my = uv.y * Float(QuestControls.panelH)
            // P176 (Oct 13: "I'm not able to use the left slider still"): the left stick moves the menu cursor and
            // parks the mouse at -1; comparing the laser with that every frame counted as a laser move and snapped the
            // cursor straight back under the laser. Only the laser itself moving (2 px) takes the cursor back.
            let laserMoved = abs(mx - lastLaser.x) + abs(my - lastLaser.y) > 2
            lastLaser = V2(mx, my)
            if laserMoved || (input.mouseX >= 0 && trig && !prevTrigger) {
                if abs(mx - input.mouseX) + abs(my - input.mouseY) > 0.5 { input.mouseMoved = true }
                input.mouseX = mx; input.mouseY = my
            } else if input.mouseX >= 0 {
                input.mouseX = mx; input.mouseY = my
            }
            if trig && !prevTrigger && input.mouseX < 0 { input.mouseX = mx; input.mouseY = my; input.mouseMoved = true }
            // R5 (Oct 13, after P10/P129: stairs crafted by accident): a laser sweeping across a crafting result while the
            // trigger comes down took it. A result or output only takes a click once the laser has rested on it 0.15 s.
            var sweep = false
            if let h = game.menuHover { switch h.kind { case .result, .output: sweep = hoverRest < 0.15; default: break } }
            if trig && !prevTrigger && !sweep { input.leftClicked = true; app.input.haptic(aimHand, amplitude: 0.3, seconds: 0.02, frequency: 300) }
            if grip && !prevGrip { input.rightClicked = true; app.input.haptic(aimHand, amplitude: 0.3, seconds: 0.02, frequency: 300) }
            input.leftDown = trig
            input.rightDown = grip
            if game.menuCursor != lastHoverSlot { lastHoverSlot = game.menuCursor; hoverRest = 0; app.input.haptic(aimHand, amplitude: 0.12, seconds: 0.01, frequency: 320) } else { hoverRest += 1.0 / 72 }
        } else {
            input.leftDown = false; input.rightDown = false
            // P309 (b): the laser off the panel altogether, out into the world: a pull throws the carried stack that
            // way (the grip one item), from the hand (Game.throwAway).
            let m = game.menu
            if !game.carried.isEmpty && m != nil && !(m is PauseMenu) && !(m is KeyboardMenu) && ((trig && !prevTrigger) || (grip && !prevGrip)) {
                let c = game.carried
                if trig && !prevTrigger { game.throwAway(c); game.carried = .empty }
                else { game.throwAway(c.with(count: 1)); game.carried = c.count > 1 ? c.with(count: c.count - 1) : .empty }
                app.input.haptic(aimHand, amplitude: 0.35, seconds: 0.03, frequency: 220)
            }
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
        // Q2c-console-70: the controller card, recorded when the hand (or the dominant hand setting) changes.
        let ck = ctrlShowHand + (QuestSettings.leftHanded ? 10 : 0)
        if let cp = ctrlPanel, ctrlShowHand >= 0, ck != ctrlRecorded {
            cp.record(s, QuestLabel.card(ctrlLines(ctrlShowHand), width: Float(cp.width), height: Float(cp.height), scale: 2))
            ctrlRecorded = ck
        }
    }

    func drawOpaque(_ s: SceneRenderer.Slot, eye: V3) {
        let xr = app.input, rig = app.rig
        var v = takeVerts()
        let CT = Mesher.cornerTable
        let shades = QuestControls.faceShades
        // P276 (c): a worn chest piece shows on the VR forearms as a gauntlet: a bracer behind each grip with a cuff,
        // in the piece's ArmorLook.style colour and trim (the same finish as on the figure).
        let chestPiece = game.inventory.armor[1]
        let ck = chestPiece.isEmpty ? "" : Items.key(chestPiece.item)
        let gauntlet: ArmorLook.Style? = ck.isEmpty || ck == "elytra" || ck == "jetpack" ? nil : ArmorLook.style(chestPiece)
        // Controllers: a grip block and a pointer nose, in each hand's grip pose.
        handRanges.removeAll(keepingCapacity: true)
        for h in 0..<2 {
            let hd = xr.hands[h]
            guard hd.gripValid else { drawnGrip[h] = nil; continue }
            let pos = rig.toWorld(hd.gripPos) - eye
            let rot = rig.toWorldRot(hd.gripRot)
            let h0 = v.count
            defer {
                if let m = motionPrev(pos, rot, was: drawnGrip[h], eye: eye) { handRanges.append((h0, v.count - h0, m)) }
                drawnGrip[h] = (pos + eye, rot)
            }
            let base = h == aimHand ? V3(0.25, 0.27, 0.32) : V3(0.3, 0.3, 0.34)
            // A magazine in the off hand (VRReload): a dark steel box under the grip.
            // P260 (c): at the controls each hand holds one: a throttle lever (moving hand) or a helm grip (aiming hand),
            // a dark grip rising out of the fist with a brass cap.
            let pilot = game.world.ships.pilot != nil, lever = h == moveHand
            for pi in 0..<8 {
                let c: V3, half: V3
                switch pi {
                case 0, 1, 2: (c, half) = QuestControls.controllerParts[pi]
                case 6:
                    guard gauntlet != nil else { continue }
                    (c, half) = (V3(0, -0.012, 0.125), V3(0.032, 0.031, 0.05))         // the bracer down the forearm
                case 7:
                    guard gauntlet != nil else { continue }
                    (c, half) = (V3(0, -0.012, 0.072), V3(0.036, 0.035, 0.008))        // the cuff at the wrist
                case 3:
                    guard lever && (game.arms.magInHand || hipReady) else { continue }
                    (c, half) = (V3(0, -0.05, -0.01), V3(0.014, 0.045, 0.024))
                case 4:
                    guard pilot else { continue }
                    (c, half) = (V3(0, lever ? 0.07 : 0.055, -0.012), V3(lever ? 0.009 : 0.013, lever ? 0.075 : 0.06, lever ? 0.009 : 0.013))
                default:
                    guard pilot else { continue }
                    (c, half) = (V3(0, lever ? 0.15 : 0.12, -0.012), V3(lever ? 0.017 : 0.022, 0.011, lever ? 0.017 : 0.022))
                }
                let col: V3
                switch pi {
                case 0: col = base
                case 1: col = base * 1.4
                case 2: col = V3(0.12, 0.12, 0.14)
                // P286: brass while one waits at the hip, green beside the well, dark steel in hand otherwise.
                case 3: col = !game.arms.magInHand ? V3(0.85, 0.66, 0.28) : (wellCued ? V3(0.3, 0.75, 0.38) : V3(0.2, 0.2, 0.22))
                case 4: col = V3(0.16, 0.12, 0.09)
                case 6: col = gauntlet?.color ?? base
                case 7: col = gauntlet?.trim ?? (gauntlet?.color ?? base) * 0.78
                default: col = V3(0.78, 0.6, 0.26)
                }
                for f in 0..<6 {
                    for k in QuestControls.quadOrder {
                        let ci = (f * 4 + k) * 3
                        let lp = c + V3(Float(CT[ci] * 2 - 1) * half.x, Float(CT[ci + 1] * 2 - 1) * half.y, Float(CT[ci + 2] * 2 - 1) * half.z)
                        v.append(SimpleVert(pos: V4(rot.act(lp) + pos, 1), color: V4(col * shades[f], 1)))
                    }
                }
            }
        }
        if let off = app.scene.push(s, v, priority: true) {
            app.scene.drawScratch(s, "simpleSolid", offset: off, count: v.count)
            let st = MemoryLayout<SimpleVert>.stride
            for r in handRanges { app.scene.addMotion(s, .simple, offset: off + r.start * st, count: r.count, prev: r.prev) }
        }
        giveVerts(v)
        drawHeld(s, eye: eye)
        drawTeleport(s, eye: eye)
        // Laser: to the hit point (menus, a target within reach) or a 3 m beam fading to a faint end. Always drawn
        // (Quest round 4: it vanished at times): a tracking blip keeps the last aim (aimOrigin/aimDir hold it), it has
        // priority room in the scratch ring, and with nothing hit it no longer fades out to nothing within 0.6 m.
        let inMenu = game.menu != nil || game.paused
        if (xr.hands[aimHand].aimValid || lastAimHand != nil) && (inMenu || laserFade > 0.02) {
            let o = aimOrigin - eye
            let len: Float = aimHit.map { max(0.05, simd_length($0 - aimOrigin)) } ?? (inMenu ? 1.5 : 3)
            let end = o + aimDir * len
            let side0 = simd_normalize(simd_cross(aimDir, simd_normalize(o + aimDir * 0.5 + V3(0.0001, 0, 0))))
            let side = side0 * 0.002
            let hot = inMenu ? (panelHitUV != nil) : (game.target != nil)
            // R12 (Oct 13, after P77/P170: "the sword still strobes when swung"; the ribbon was already off): the laser
            // from the sword hand swept across blocks every frame, flipping between a 3 m white beam and a short cyan
            // one, a white strobe along the blade. During a swing (the tip moving past the re-arm speed) the laser fades
            // out, and comes back once the hand is still.
            let k = inMenu ? 1 : laserFade
            let c0 = (hot ? V4(0.55, 0.9, 1, 0.85) : V4(1, 1, 1, 0.6)) * V4(1, 1, 1, k)
            let c1 = V4(c0.x, c0.y, c0.z, (aimHit == nil ? 0.2 : c0.w / max(k, 1e-3)) * k)
            var lv = takeVerts()
            defer { giveVerts(lv) }
            QuestControls.quad(&lv, V4(o - side, 1), V4(end - side, 1), V4(end + side, 1), V4(o + side, 1), c0, c1, c1, c0)
            if let hp = aimHit {
                // A small dot where the ray lands.
                let c = hp - eye - aimDir * 0.01
                let r = simd_normalize(simd_cross(aimDir, V3(0, 1, 0) + V3(0.001, 0, 0))) * 0.012
                let u = simd_normalize(simd_cross(r, aimDir)) * 0.012
                QuestControls.quad(&lv, c - r - u, c + r - u, c + r + u, c - r + u, V4(c0.x, c0.y, c0.z, 0.9))
            }
            if let off = app.scene.push(s, lv, priority: true) { app.scene.drawScratch(s, "simple", offset: off, count: lv.count) }
        }
    }

    // The held item in the aiming hand: guns as their solid models (barrel along the ray), blocks as small cubes,
    // other items as two-layer sprites leaning forward like they're gripped.
    private func drawHeld(_ s: SceneRenderer.Slot, eye: V3) {
        // A frame without a valid aim pose (tracking blip) keeps the last one instead of hiding the tool.
        if app.input.hands[aimHand].aimValid { lastAimHand = app.input.hands[aimHand] }
        guard let hd = lastAimHand, game.menu == nil, !game.paused, game.sleeping == 0 else { drawnAim = nil; return }
        let held = game.held
        if held.isEmpty || scopeT > 0.5 { drawnAim = nil; return }            // (G21: looking through the scope, the rifle is out of view)
        let rig = app.rig
        let pos = rig.toWorld(hd.aimPos) - eye
        let rot = braceRot ?? rig.toWorldRot(hd.aimRot)
        let prev = motionPrev(pos, rot, was: drawnAim, eye: eye)       // P403 7b
        drawnAim = (pos + eye, rot)
        let pe = game.player.eye
        let l = game.world.lightAt(Int(floor(pe.x)), Int(floor(pe.y)), Int(floor(pe.z)))
        let skyK: Float = 0.12 + 0.88 * game.renderDaylight
        let light = max(0.15, max(Float(l.sky) / 15 * skyK, Float(l.block) / 15), game.nightVision * 0.9)
        if let gi = game.heldGun {
            let (ptr, off, cap) = app.scene.reserve(s, MobVert.self, priority: true)
            guard cap > 1536 else { return }      // up to ~1300 with upgrade parts (Upgrades.gunParts)
            // Larger than life (rifle ~1.2 m, sidearm ~0.33 m): 3.2x the screen model. Empty: no magazine, red light.
            let gk: Float = 3.2 * QuestSettings.heldScale
            let n = Guns.writeFirstPerson(gi, aim: 1, kick: game.arms.kick, lower: 0, bob: .zero, light: light,
                                          rounds: game.arms.reload > 0 ? 0 : game.held.tag, scale: gk, upgrades: game.held.ench,
                                          slide: GunActions.slideDrawn(gi), spin: game.arms.barrel, into: ptr)
            let shift = QuestControls.heldGunShift(gi)
            // P413: the kick in the hand follows the gun ("it has to have recoil"): the muzzle climbs and the gun
            // shoves back, a sidearm a little, a shotgun or launcher hard. The model's own kick was the same for all.
            let rk: Float = game.arms.kick * min(2.5, max(0.6, 0.5 + Guns.all[gi].recoil * 25))
            let krot = rot * Quat(angle: rk * 0.12, axis: V3(1, 0, 0))
            let kpos = pos + krot.act(V3(0, 0.01 * rk, 0.05 * rk))
            for i in 0..<n {
                let v = ptr[i].pos
                let local = V3(v.x, v.y, v.z) + shift      // the grip sits in the hand
                let w = krot.act(local) + kpos
                ptr[i].pos = V4(w.x, w.y, w.z, v.w)
            }
            app.scene.commit(off, n, MobVert.self)
            app.scene.drawScratch(s, "mob", offset: off, count: n)
            if let m = prev { app.scene.addMotion(s, .mob, offset: off, count: n, prev: m) }
            return
        }
        if let bp = bowPose { drawBow(s, eye: eye, bp, light: light, prev: prev); return }
        let (ptr, off, cap) = app.scene.reserve(s, EntityVert.self, max: 2400, priority: true)
        guard cap >= 96 else { return }
        var wr = EntityWriter(out: ptr, capacity: cap)
        if let b = held.def.block, !Blocks.flatIcon(b) {
            let t = Blocks.tint[Int(b)]
            let tint = t == 1 || t == 3 ? V3(0.57, 0.74, 0.35) : (t == 2 ? V3(0.47, 0.67, 0.18) : V3(1, 1, 1))
            wr.cube(center: .zero, half: 0.085, yaw: 0, block: b, light: light, tint: tint)
            for i in 0..<wr.n {
                let v = ptr[i].pos
                let w = rot.act(V3(v.x, v.y, v.z) + V3(0, 0.03, -0.11)) + pos
                ptr[i].pos = V4(w.x, w.y, w.z, v.w)
            }
        } else {
            let layer = Items.texLayer(held.item) ?? Int(Blocks.tex[Int(held.def.block ?? 0) * 6])
            let r = rot.act(simd_normalize(V3(0, 0.15, -1))), up0 = rot.act(simd_normalize(V3(0, 1, 0.15)))
            let side0 = rot.act(V3(1, 0, 0))
            // The flat face is rolled ~40 degrees toward the eye (above and inside the hand): held straight it was seen
            // almost edge-on and read as a thin sliver. The top leans outward, away from the face.
            let sg: Float = aimHand == 0 ? -1 : 1, ca: Float = 0.766, sa: Float = 0.643
            let side = side0 * ca - up0 * (sa * sg), up = up0 * ca + side0 * (sa * sg)
            // Larger than life (Remington, v61 and the store pass: real size read too small): a sword's icon diagonal
            // ~1.55 m, other tools / bows ~1.3 m, everything else a 40 cm icon.
            // Tools and weapons are held by the handle: the icon's grip texel (~3/16 in, 4/16 up) sits in the hand.
            let (h, tool) = heldSize()
            let c = tool ? pos + rot.act(V3(0, 0.01, -0.03)) + r * (0.62 * h) + up * (0.5 * h)
                                : pos + rot.act(V3(0, 0.07, -0.12))
            // One texel (h/8) thick and closed: both faces plus a wall round every opaque texel (ItemExtrude.swift; the
            // five stacked sprites it replaced read as five pieces and went see-through edge-on: Oct 11 playtest P17).
            heldQuads = wr.extrudedItem(center: c, half: h, right: r, up: up, normal: side, thick: h / 8, layer: layer, light: light)
            // Upgrades show on the model (Upgrades.accents): a grip wrap, a band on the head, a line on the edge.
            Upgrades.writeAccents(&wr, held, center: c, half: h, right: r, up: up, normal: side, thick: h * 2.6 / 32, light: light)
        }
        app.scene.commit(off, wr.n, EntityVert.self)
        app.scene.drawScratch(s, "entity", offset: off, count: wr.n)
        if let m = prev { app.scene.addMotion(s, .entity, offset: off, count: wr.n, prev: m) }
    }

    // The bow as solid geometry (VRBow.Pose, tracking space): limbs standing across the arrow and bending back to the
    // string, the string from both tips to the nock, and the nocked arrow from the nock through the grip.
    private func drawBow(_ s: SceneRenderer.Slot, eye: V3, _ bp: VRBow.Pose, light: Float, prev: float4x4? = nil) {
        let rig = app.rig
        var v = takeVerts()
        defer { giveVerts(v) }
        let side = simd_normalize(simd_cross(bp.dir, bp.up))
        func w(_ p: V3) -> V3 { rig.toWorld(p) - eye }
        // A four-sided beam from a to b (tracking space), half sizes along `side` and the beam's other cross axis.
        func beam(_ a: V3, _ b: V3, _ hs: Float, _ hn: Float, _ col: V3) {
            let ax = b - a
            guard simd_length_squared(ax) > 1e-8 else { return }
            var n = simd_cross(ax, side)
            n = simd_length_squared(n) > 1e-10 ? simd_normalize(n) : bp.dir
            let sd = simd_normalize(simd_cross(n, ax))
            let A = w(a), B = w(b)
            let rs = rig.toWorldDir(sd) * hs, rn = rig.toWorldDir(n) * hn
            func face(_ o: V3, _ e: V3, _ k: Float) {
                let c = V4(col * (k * light), 1)
                QuestControls.quad(&v, V4(A + o - e, 1), V4(B + o - e, 1), V4(B + o + e, 1), V4(A + o + e, 1), c, c, c, c)
            }
            face(rs, rn, 1); face(-rs, rn, 0.7); face(rn, rs, 0.85); face(-rn, rs, 0.6)
        }
        let wood = V3(0.46, 0.3, 0.15), wrap = V3(0.25, 0.16, 0.1)
        let seg = 10
        for i in 0..<seg {
            let u0 = -1 + 2 * Float(i) / Float(seg), u1 = -1 + 2 * Float(i + 1) / Float(seg)
            let taper = 1 - 0.45 * max(abs(u0), abs(u1))
            beam(bp.limb(u0), bp.limb(u1), 0.022 * taper, 0.013 * taper, abs(u0 + u1) < 0.3 ? wrap : wood)
        }
        let str = V3(0.85, 0.83, 0.78)
        // After a shot the string's middle shivers sideways (VRBow.stringWobble).
        let shiver = bp.nock + side * VRBow.stringWobble(bowReleaseT, draw: bowReleaseDraw)
        beam(bp.tipTop, shiver, 0.0035, 0.0035, str)
        beam(shiver, bp.tipBottom, 0.0035, 0.0035, str)
        if bowNocked {
            // The arrow slides back onto the string as it is nocked (VRBow.nockSlide).
            let nk = bp.nock + bp.dir * VRBow.nockSlide(bowNockT)
            let tip = nk + bp.dir * VRBow.arrowLength
            beam(nk, tip - bp.dir * 0.07, 0.006, 0.006, V3(0.62, 0.5, 0.34))
            beam(tip - bp.dir * 0.07, tip, 0.015, 0.006, V3(0.55, 0.57, 0.6))
            beam(nk + bp.dir * 0.02, nk + bp.dir * 0.13, 0.004, 0.02, V3(0.9, 0.9, 0.88))
        }
        if let off = app.scene.push(s, v, priority: true) {
            app.scene.drawScratch(s, "simpleSolid", offset: off, count: v.count)
            if let m = prev { app.scene.addMotion(s, .simple, offset: off, count: v.count, prev: m) }    // P403 7b
        }
    }

    // The blade trail (BladeTrail): a pale ribbon from base to tip over the last few fast frames, fading with age.
    // P170 (Oct 13: "the sword still strobes when swung", after P77 smoothed and dimmed it): the ribbon is off; a swing
    // reads from the blade itself, its sound and the haptics. (BladeTrail still tracks the swing for the tests.)
    static var bladeTrailShown = false
    private func drawBladeTrail(_ s: SceneRenderer.Slot, eye: V3) {
        guard QuestControls.bladeTrailShown, bladeValid, game.menu == nil else { return }
        var v = takeVerts()
        defer { giveVerts(v) }
        bladeTrail.segments(now: game.clock) { a0, b0, a1, b1, al0, al1 in
            let c0 = V4(0.92, 0.95, 1, al0), c1 = V4(0.92, 0.95, 1, al1)
            let m0 = c0 * V4(1, 1, 1, 0.25), m1 = c1 * V4(1, 1, 1, 0.25)       // fainter toward the hand
            QuestControls.quad(&v, V4(a0 - eye, 1), V4(b0 - eye, 1), V4(b1 - eye, 1), V4(a1 - eye, 1), m0, c0, c1, m1)
        }
        if v.isEmpty { return }
        if let off = app.scene.push(s, v) { app.scene.drawScratch(s, "panelVignette", offset: off, count: v.count) }
    }

    // Aboard a moving ship: a faint level ring with a forward notch at the user's feet, fixed to the user's body
    // (not the hull), a stable reference while the deck turns and pitches.
    private func drawDeckReference(_ s: SceneRenderer.Slot, eye: V3) {
        let a = deckReference * QuestSettings.deckRing
        guard a > 0.02 else { return }
        let rig = app.rig
        let c = V3(rig.headWorld.x, game.player.pos.y + 0.03, rig.headWorld.z) - eye
        var v = takeVerts()
        defer { giveVerts(v) }
        let seg = 40
        let r0: Float = 0.42, r1: Float = 0.47
        let col = V4(0.75, 0.92, 1, 0.38 * a)
        for i in 0..<seg {
            let a0 = Float(i) / Float(seg) * 2 * .pi, a1 = Float(i + 1) / Float(seg) * 2 * .pi
            let d0 = V3(cosf(a0), 0, sinf(a0)), d1 = V3(cosf(a1), 0, sinf(a1))
            QuestControls.quad(&v, c + d0 * r0, c + d1 * r0, c + d1 * r1, c + d0 * r1, col)
        }
        // Forward notch (the body's facing).
        let f = rig.yawRot.act(V3(0, 0, -1)), r = rig.yawRot.act(V3(1, 0, 0))
        QuestControls.quad(&v, c + f * r1 - r * 0.03, c + f * r1 + r * 0.03, c + f * (r1 + 0.12) + r * 0.03, c + f * (r1 + 0.12) - r * 0.03, col)
        if let off = app.scene.push(s, v) { app.scene.drawScratch(s, "panelVignette", offset: off, count: v.count) }
    }

    // Panels and the comfort vignette, over everything.
    func drawOverlay(_ s: SceneRenderer.Slot, eye: V3) {
        if wallFade > 0 {                          // under the panels: menus stay readable with the head in a wall
            var v = takeVerts()
            let c = V4(0, 0, 0, min(1, wallFade))
            QuestControls.quad(&v, V4(-1, -1, 0, 2), V4(1, -1, 0, 2), V4(1, 1, 0, 2), V4(-1, 1, 0, 2), c, c, c, c)
            if let off = app.scene.push(s, v) { app.scene.drawScratch(s, "panelVignette", offset: off, count: v.count) }
            giveVerts(v)
        }
        if let panel, (!game.hideHUD || game.menu != nil) {
            let (rx, uy, n) = panelAxes()
            let c = panelCenter - eye
            let m = float4x4(columns: (V4(rx * panelSize.x, 0), V4(uy * panelSize.y, 0), V4(n, 0), V4(c, 1)))
            let inMenu = mode == .menu
            panel.draw(s, model: m, alpha: inMenu ? 1 : hudAlpha, onTop: true)
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
        // Q2c-console-70: the card above the controller he is looking at, facing him, about 20 cm wide.
        if let cp = ctrlPanel, ctrlAlpha > 0.02, ctrlShowHand >= 0, ctrlRecorded == ctrlShowHand + (QuestSettings.leftHanded ? 10 : 0),
           ctrlShowHand < app.input.hands.count, app.input.hands[ctrlShowHand].gripValid {
            let head = app.rig.headWorld
            let p = app.rig.toWorld(app.input.hands[ctrlShowHand].gripPos)
            let toHead = simd_normalize(head - p)
            let right = simd_normalize(simd_cross(V3(0, 1, 0), toHead) + V3(1e-5, 0, 0))
            let up = simd_cross(toHead, right)
            let wid: Float = 0.2, hgt = wid * Float(cp.height) / Float(cp.width)
            let c = p + up * (0.07 + hgt * 0.5) + toHead * 0.03 - eye
            let m = float4x4(columns: (V4(right * wid, 0), V4(up * hgt, 0), V4(toHead, 0), V4(c, 1)))
            cp.draw(s, model: m, alpha: ctrlAlpha, onTop: true)
        }
        drawDeckReference(s, eye: eye)
        drawBladeTrail(s, eye: eye)
        var v = takeVerts()
        defer { giveVerts(v) }
        screenEffects(&v)
        let k = vignette * QuestSettings.vignette
        if k > 0.02 && scopeT < 0.5 { ring(&v, k, V3(0, 0, 0)) }
        if scopeT > 0.02 { drawScope(&v) }
        if let off = app.scene.push(s, v) { app.scene.drawScratch(s, "panelVignette", offset: off, count: v.count) }
    }

    // Speed streaks in clip space (w = 2): 28 thin wedges in the outer ring, each sliding outward and fading on its own
    // phase. Kept faint: they read as motion at the edge without cluttering the view.
    private func speedStreaks(_ v: inout [SimpleVert], _ k: Float, _ t: Float) {
        let n = 28
        for i in 0..<n {
            let h = hashf(i, 7, 31, 0x5bd1)
            let a = (Float(i) + h * 0.6) / Float(n) * 2 * .pi
            let ph = (t * (1.6 + h) + h * 5).truncatingRemainder(dividingBy: 1)
            let r0: Float = 1.3 + ph * 0.9, r1: Float = r0 + 0.35 + h * 0.25
            let wdt: Float = 0.006 + 0.004 * h
            let d = V2(cosf(a), sinf(a)), n2 = V2(-d.y, d.x) * (wdt * r0)
            let alpha: Float = 0.16 * k * sinf(ph * .pi)
            let c0 = V4(1, 1, 1, 0), c1 = V4(1, 1, 1, alpha)
            let p0 = d * r0, p1 = d * r1
            QuestControls.quad(&v, V4(p0.x - n2.x, p0.y - n2.y, 0, 2), V4(p0.x + n2.x, p0.y + n2.y, 0, 2),
                               V4(p1.x + n2.x, p1.y + n2.y, 0, 2), V4(p1.x - n2.x, p1.y - n2.y, 0, 2), c0, c0, c1, c1)
        }
    }

    // G21: the scope's lens: black all round a round clear lens centred where the round lands, a thin crosshair with
    // an open centre and a red dot, fading in with scopeT.
    private func drawScope(_ v: inout [SimpleVert]) {
        var c = V2.zero
        if let cam = app.rig.lastCam, let aim = game.vrAim {
            var n = 0
            for vp in cam.viewProj { if let r = VRScope.reticle(viewProj: vp, center: cam.center, aimOrigin: aim.origin, aimDir: aim.dir) { c += r; n += 1 } }
            if n > 0 { c /= Float(n) }
        }
        c = simd_clamp(c, V2(repeating: -0.5), V2(repeating: 0.5))
        let a = scopeT
        let black = V4(0, 0, 0, a), edge = V4(0.02, 0.02, 0.02, a)
        let R = VRScope.lensRadius, seg = 48
        for i in 0..<seg {
            let a0 = Float(i) / Float(seg) * 2 * .pi, a1 = Float(i + 1) / Float(seg) * 2 * .pi
            let d0 = V2(cosf(a0), sinf(a0)), d1 = V2(cosf(a1), sinf(a1))
            // A soft rim (the tube's edge), then black out to well past the view's corners.
            for (ra, rb, ca, cb) in [(R * 0.94, R, V4(0, 0, 0, 0), edge), (R, 4, black, black)] {
                let p0 = c + d0 * ra, p1 = c + d1 * ra, p2 = c + d1 * rb, p3 = c + d0 * rb
                QuestControls.quad(&v, V4(p0.x, p0.y, 0, 2), V4(p1.x, p1.y, 0, 2), V4(p2.x, p2.y, 0, 2), V4(p3.x, p3.y, 0, 2), ca, ca, cb, cb)
            }
        }
        let line = V4(0, 0, 0, 0.85 * a), w: Float = 0.004, gap: Float = 0.05
        func bar(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) {
            QuestControls.quad(&v, V4(c.x + x0, c.y + y0, 0, 2), V4(c.x + x1, c.y + y0, 0, 2), V4(c.x + x1, c.y + y1, 0, 2), V4(c.x + x0, c.y + y1, 0, 2), line, line, line, line)
        }
        bar(-R, -w, -gap, w); bar(gap, -w, R, w); bar(-w, -R, w, -gap); bar(-w, gap, w, R)
        let dot = V4(0.9, 0.08, 0.05, a), d: Float = 0.006
        QuestControls.quad(&v, V4(c.x - d, c.y - d, 0, 2), V4(c.x + d, c.y - d, 0, 2), V4(c.x + d, c.y + d, 0, 2), V4(c.x - d, c.y + d, 0, 2), dot, dot, dot, dot)
    }

    // A ring in clip space (w = 2): clear in the middle, `color` at the edge; k 0...1 narrows the clear middle.
    private func ring(_ v: inout [SimpleVert], _ k: Float, _ color: V3, maxAlpha: Float = 1) {
        let seg = 32
        let r0: Float = 1.25 - 0.55 * k, r1: Float = r0 + 0.35, r2: Float = 3
        let alpha = min(maxAlpha, k * 1.2)
        for i in 0..<seg {
            let a0 = Float(i) / Float(seg) * 2 * .pi, a1 = Float(i + 1) / Float(seg) * 2 * .pi
            let d0 = V2(cosf(a0), sinf(a0)), d1 = V2(cosf(a1), sinf(a1))
            for j in 0..<2 {
                let ra = j == 0 ? r0 : r1, rb = j == 0 ? r1 : r2
                let ca = V4(color.x, color.y, color.z, (j == 0 ? 0 : 1) * alpha), cb = V4(color.x, color.y, color.z, alpha)
                let p0 = d0 * ra, p1 = d1 * ra, p2 = d1 * rb, p3 = d0 * rb
                QuestControls.quad(&v, V4(p0.x, p0.y, 0, 2), V4(p1.x, p1.y, 0, 2), V4(p2.x, p2.y, 0, 2), V4(p3.x, p3.y, 0, 2), ca, ca, cb, cb)
            }
        }
    }

    // Burning (P114, Oct 12 PM: "a fire burning animation, that way I know when I fall in lava"): flame tongues licking
    // up from the bottom of the view, each flickering on its own, orange at the root and yellow, fading, at the tip.
    private func flames(_ v: inout [SimpleVert], _ t: Float, _ fx: Float) {
        // R17 (Oct 13 evening: "an on-fire overlay on the Quest"): taller and denser, so burning is unmistakable.
        let n = 22
        for i in 0..<n {
            let h = hashf(i, 3, 17, 0xF1A3)
            let x: Float = -1.35 + 2.7 * (Float(i) + 0.5) / Float(n) + (h - 0.5) * 0.08
            let lick: Float = 0.5 + 0.5 * sinf(t * (7 + 5 * h) + h * 11)
            let tall: Float = (0.55 + 0.6 * h) * (0.7 + 0.45 * lick)
            let half: Float = 0.1 + 0.05 * h
            let sway: Float = 0.06 * sinf(t * 5.3 + h * 7)
            let y0: Float = -1.35, y1: Float = y0 + tall
            let a: Float = 0.75 * max(0.3, fx)
            let root = V4(1, 0.38, 0.04, a), mid = V4(1, 0.62, 0.1, a * 0.85), tip = V4(1, 0.9, 0.35, 0)
            let ym: Float = y0 + tall * 0.45
            QuestControls.quad(&v, V4(x - half, y0, 0, 2), V4(x + half, y0, 0, 2), V4(x + half * 0.7 + sway * 0.5, ym, 0, 2),
                               V4(x - half * 0.7 + sway * 0.5, ym, 0, 2), root, root, mid, mid)
            QuestControls.quad(&v, V4(x - half * 0.7 + sway * 0.5, ym, 0, 2), V4(x + half * 0.7 + sway * 0.5, ym, 0, 2),
                               V4(x + sway + 0.004, y1, 0, 2), V4(x + sway - 0.004, y1, 0, 2), mid, mid, tip, tip)
        }
    }

    // The Mac HUD's full-screen effects, over the whole view instead of the HUD panel (extract_hud.py turns them off
    // there): water, lava, sleep and portal tints; getting hurt, burning and freezing as edge glows (a full-view red
    // flash is harsh in a headset).
    private func screenEffects(_ v: inout [SimpleVert]) {
        let g = game
        let fx: Float = Settings.shared.screenEffects ? 1 : 0.3
        func tint(_ c: V4) { QuestControls.quad(&v, V4(-1, -1, 0, 2), V4(1, -1, 0, 2), V4(1, 1, 0, 2), V4(-1, 1, 0, 2), c, c, c, c) }
        if g.player.headInWater { tint(V4(0.05, 0.15, 0.45, 0.18)) }
        if g.player.headInLava { tint(V4(0.9, 0.3, 0.02, 0.45)) }
        if g.portalTime > 0 { tint(V4(0.45, 0.1, 0.8, min(0.7, g.portalTime / 4 * 0.7) * fx)) }
        if g.sleeping > 0 { tint(V4(0.02, 0.02, 0.06, min(1, g.sleeping / 1.5))) }
        if relocateFade > 0.01 { tint(V4(0, 0, 0, relocateFade)) }                         // Q2c-console-62
        if g.hurtFlash > 0 { ring(&v, min(1, g.hurtFlash * 2.5), V3(0.75, 0.02, 0.02), maxAlpha: 0.6 * fx) }
        if Feedback.heartPulse > 0.01 { ring(&v, Feedback.heartPulse * 0.45, V3(0.5, 0, 0.02), maxAlpha: 0.35 * fx) }   // Q2c-console-34
        if g.freeze > 0 { ring(&v, min(1, g.freeze / 7) * 0.7, V3(0.85, 0.93, 1), maxAlpha: 0.55) }
        // Sprinting (VR has no FOV kick): faint streaks rushing outward at the edges of the view.
        if sprintFx > 0.01 { speedStreaks(&v, sprintFx * fx, Float(g.clock)) }
        if g.onFire > 0 && g.menu == nil {
            let flicker = 0.75 + 0.25 * sinf(Float(g.clock) * 9)
            ring(&v, 0.55 * flicker, V3(1, 0.45, 0.05), maxAlpha: 0.5)
            flames(&v, Float(g.clock), fx)
        }
    }
}
