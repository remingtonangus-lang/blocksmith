import Foundation

// The pause menu's "VR Comfort & Controls" page (PauseMenu host page): turning, movement, vignette, ship reference,
// seated mode, handedness, refresh rate and foveation. Values are QuestSettings (saved), applied at once.
enum QuestOptions {
    struct Hooks {
        var recenter: () -> Void = {}
        var rates: () -> [Float] = { [72, 80, 90, 120] }
        var currentRate: () -> Float = { QuestSettings.refreshRate }
        var setRate: (Float) -> Void = { _ in }
        var foveated: () -> Bool = { false }
        var setFoveation: (Int) -> Void = { _ in }
        // S6: the head's height above the floor now (nil without a floor-level space), and closing the setup panel.
        var headHeight: () -> Float? = { nil }
        var finishSetup: () -> Void = {}
        var toast: (String) -> Void = { _ in }
        var game: () -> Game? = { nil }                 // Q2c-console-31: the world being played (its first difficulty)
    }
    // Q2c-console-31: the world being played, whose difficulty the setup page sets (P369: at any time, not only in its
    // first ten minutes).
    static func newWorld() -> Game? { hooks.game() }
    static var hooks = Hooks()

    static let snapAngles: [Float] = [15, 22.5, 30, 45, 60, 90]
    static let turnSpeeds: [Float] = [45, 60, 90, 120, 150, 180, 240]
    static let vignettes: [Float] = [0, 0.3, 0.6, 1]
    static let heldScales: [Float] = [0.8, 0.9, 1, 1.15, 1.3, 1.5]
    static func vignetteName(_ v: Float) -> String {
        v <= 0.01 ? "Off" : (v < 0.45 ? "Low" : (v < 0.8 ? "Medium" : "High"))
    }

    static func install(_ h: Hooks) {
        hooks = h
        Settings.onReset = { g in
            QuestSettings.reset(g)
            h.setRate(QuestSettings.refreshRate)
            if h.foveated() { h.setFoveation(QuestSettings.foveation) }
        }
        PauseMenu.hostEntry = ("VR Comfort & Controls...", "host:vr")
        // Rows with no meaning in the headset: window, display and frame-rate options (the runtime owns the display),
        // the field of view (the lenses set it), photo mode's free camera (the head is the camera) and split screen.
        // Bug Notes stays: the playtest build's voice notes (QuestVoiceNotes); store builds' stub has available = false.
        PauseMenu.hostHidden = ["photo", "coop", "fullscreen", "display", "launchfs", "vsync", "fps", "rscale", "wscale",
                                "graphics", "fov", "controls", "keys", "padmap",
                                // Q2c-console-1: a gamepad's stick tuning and prompt styles do nothing with Touch controllers
                                // (turning, walking and sprinting are the VR Comfort & Controls page's).
                                "lookx", "looky", "accel", "curve", "invert", "lookdead", "lookouter", "dead", "moveouter",
                                "aim", "southpaw", "sneaktoggle", "autosprint", "glyphs",
                                // Q2c-console-26: the laser replaces the crosshair; TV framing and split screen don't apply;
                                // the headset's brightness is its own (q_bright, below on the Video page too).
                                "crosshair", "couch", "safe", "splitlayout", "brightness",
                                // Q2c-console-27: no own-music folder and no system voice on the headset (the
                                // Soundtrack row stays: Sunderfall or Classic, P359).
                                "audio_music_folder", "audio_music_shuffle", "audio_music_vol", "narrator"]
        PauseMenu.hostVideoRows = { [("Brightness: \(PauseMenu.brightnessName(QuestSettings.brightness))", "q_bright")] }
        PauseMenu.hostHiddenCats = [.controls]                  // no keyboard or mouse in the headset
        PauseMenu.hostCatNames = [.controller: "Touch Controls"]
        PauseMenu.hostValues = ["q_firstdiff", "q_pos", "q_comfort", "q_preset", "q_turn", "q_snap", "q_tspeed", "q_move", "q_vig", "q_knock", "q_vib", "q_menusize", "q_hudsize", "q_ring", "q_saddle", "q_shake", "q_chase", "q_seated", "q_reclined", "q_swing", "q_held", "q_hand", "q_hz", "q_fov", "q_spacewarp", "q_tex", "q_view", "q_autord", "q_hud", "q_bright"]
        PauseMenu.hostHelp = [
            "host:vr": "Turning, movement, comfort vignette, seated play, refresh rate.",
            "host:setup": "Play position, comfort, dominant hand, controls and your height: the first-launch setup again.",
            "q_pos": "Standing: your real height and moves. Seated: the view is raised to standing eye height and leaning doesn't walk. Lying Down: also levels the world to your gaze.",
            "q_comfort": "Comfort: teleport, snap turns, a strong vignette, no shake or knockback. Moderate: stick walking, snap turns, a medium vignette, less knockback. Free: stick walking, smooth turning, no vignette.",
            "q_preset": "Default: the standard layout. Classic: the stick walks and snap-turns (no teleport). One Hand: the dominant stick also walks forward and back, and turns sideways.",
            "q_height": "Stand up straight, look ahead and select this: standing play then always recentres to this height.",
            "q_setup_done": "Start playing. All of this is in VR Comfort & Controls later.",
            "q_firstdiff": "Very Easy to Very Hard, or Peaceful (no monsters).",   // (P302: PauseMenu.describe shows the chosen level's line)
            "q_turn": "Snap turns in steps (most comfortable) or turn smoothly while the right stick is held.",
            "q_snap": "How far one snap turn goes.",
            "q_tspeed": "How fast smooth turning goes.",
            "q_move": "Smooth: the left stick walks. Teleport: push the left stick forward, aim the arc, release to jump there.",
            "q_vig": "Darkens the edges of the view while moving, turning, riding horses and riding ships. Higher is more comfortable.",
            "q_saddle": "Riding a horse or another mount, a boat or a minecart, the view eases over jumps, bucks and waves instead of following every bob; real climbs and drops are still followed.",
            "q_chase": "Taking the controls of a ship, airship, crawler, drop craft or boat moves your view out behind it, like a chase camera; back to first person when you let go. Off keeps you in first person.",
            "q_shake": "The view jolts a little when the Tidebreaker fires and blasts land nearby. Off keeps the view still (the controllers still rumble).",
            "q_ctrlhints": "Hold a controller up and look at it to see what each of its buttons does.",   // Q2c-console-70
            "q_minetoggle": "Hold: keep the trigger pulled to mine. Toggle: one pull at a block mines it to the end; look away or pull again to stop.",   // Q2c-console-61
            "q_knock": "How far hits and blasts push you: Reduced moves you 40% as far, Off not at all. Damage, the red flash and the thump in your hands stay.",   // Q2c-console-60
            "q_vib": "How strongly the Touch controllers vibrate: hits, mining, attacks, the bow, low health, explosions and menus. Off stops every buzz. Also in Options > Accessibility.",   // Q2c-console-35
            "q_ring": "A steady ring at your feet while a ship you stand on moves or turns: a fixed reference for your eyes.",
            "q_seated": "Seated: leaning doesn't walk you through the world, and recentring sets standing eye height.",
            "q_reclined": VRMelee.reclinedPostureHelp,
            "q_swing": VRMelee.optionHelp,
            "q_recenter": "Puts you back at the centre of your play space at the current height and facing (or hold the Menu button).",
            "q_held": "How big swords, tools, blocks and guns look in your hand (0.8x to 1.5x).",
            "q_hand": "Which hand aims, breaks and uses (the other hand moves). Left swaps every button, stick, trigger and grip between the hands; the Menu button stays on the left controller.",
            "q_hz": "Display refresh rate. Higher is smoother but uses more battery and heat.",
            "q_view": "How far the land is drawn, 8 to 24 chunks. Lower it when the game isn't keeping up; it applies at once.",
            "q_autord": "When frames are missed because the headset is at its limit, the render distance steps down for now, and back up to your setting once there is headroom again.",
            "host:touch": "Every Touch controller button and what it does.",
            "q_bright": "How much you see without light: Moody keeps caves near black, Bright lifts every shadow. Torches stay brighter either way.",
            "q_subs": "Shows captions for sounds, with the direction they come from (also in Options > Accessibility).",
            "q_menusize": "How big menus look in front of you (at the same distance): larger is easier to read, smaller keeps more of the world in view.",   // Q2c-console-49
            "q_hudsize": "How big the floating HUD (hotbar, health, messages) looks; the hotbar stays at the height HUD Position puts it.",
            "q_hud": "Where the HUD (hotbar, health, messages) floats: lower keeps more of the view clear.",
            "q_tex": "High: 128-pixel block textures (sharpest up close). Medium: 64 pixels, less memory. Applies at the next launch.",
            "q_fov": "Renders the edges of the view at lower resolution (fixed foveated rendering): faster, slightly softer edges.",
            "q_spacewarp": "The game draws every other frame and the headset makes the ones between (Application SpaceWarp): more room for long views, some smearing on fast moving things. Applies at the next launch.",
            "q_clouds": "The cloud layer in the sky. Off saves a little time on the headset each frame.",       // Q2c-console-6
            "q_hudfade": "The HUD rests translucent and comes up solid for a few seconds when you step the hotbar. Off keeps it solid.",
        ]
        PauseMenu.hostPage = { id in
            if id == "touch" {
                let sub = QuestSettings.leftHanded ? "Left-handed: the left hand aims, the right hand moves" : "Right hand aims; the left hand moves"
                return ("Touch Controls", sub, touchRowsHanded().map { ($0, "noop") } + [("Back to VR Comfort", "host:vr")])
            }
            if id == "setup" { return setupPage() }
            guard id == "vr" else { return nil }
            let S = QuestSettings.self
            func on(_ b: Bool) -> String { b ? "On" : "Off" }
            let fovNames = ["Off", "Low", "Medium", "High"]
            let fovNote = hooks.foveated() || S.foveation == 0 ? "" : " (next launch)"
            var rows: [(String, String)] = [
                ("Touch Controls...", "host:touch"),
                ("First-Launch Setup...", "host:setup"),
                ("Controls: \(presetName(S.controlPreset))", "q_preset"),
                ("Turning: \(S.reclined ? "Snap (lying down)" : (S.smoothTurn ? "Smooth" : "Snap"))", "q_turn"),
                S.smoothTurn && !S.reclined ? ("Smooth Turn Speed: \(Int(S.smoothTurnSpeed)) deg/s", "q_tspeed")
                             : ("Snap Angle: \(angle(S.snapAngle)) deg", "q_snap"),
                ("Movement: \(S.teleport ? "Teleport" : "Smooth")", "q_move"),
                ("Comfort Vignette: \(vignetteName(S.vignette))", "q_vig"),
                ("Knockback: \(S.knockback > 0.7 ? "Full" : (S.knockback > 0.05 ? "Reduced" : "Off"))", "q_knock"),     // Q2c-console-60
                ("Mining: \(S.mineToggle ? "Toggle" : "Hold")", "q_minetoggle"),                                       // Q2c-console-61
                ("Controller Hints: \(on(S.ctrlHints))", "q_ctrlhints"),                                                // Q2c-console-70
                ("Controller Vibration: \(Settings.shared.rumble == 0 ? "Off" : "\(Int((Settings.shared.rumble * 100).rounded()))%")", "q_vib"),
                ("Ship Deck Ring: \(on(S.deckRing > 0))", "q_ring"),
                ("Steady Ride: \(on(S.steadySaddle))", "q_saddle"),          // (Q2c-console-56: was Steady Saddle)
                ("Craft Bank: \(S.craftBankFull ? "Full" : "Gentle")", "q_bank"),                                     // P334 (d)
                ("Blast Shake: \(on(S.blastShake))", "q_shake"),
                ("Vehicle View: \(S.chaseView ? "Chase" : "First Person")", "q_chase"),
                ("Seated Mode: \(on(S.seated))", "q_seated"),
                ("Lying Down View: \(on(S.reclined))", "q_reclined"),
                ("Melee: \(S.swingMode ? "Swing" : "Reclined")", "q_swing"),
                ("Reload: \(S.buttonReload ? "Button" : "Hip Pouch")", "q_reload"),                                   // P286 (b)
                ("Recenter View", "q_recenter"),
                ("Held Item Size: \(String(format: "%gx", S.heldScale))", "q_held"),
                ("Dominant Hand: \(S.leftHanded ? "Left" : "Right")", "q_hand"),
                ("Refresh Rate: \(Int(hooks.currentRate())) Hz", "q_hz"),
                ("Foveated Rendering: \(fovNames[max(0, min(3, S.foveation))])\(fovNote)", "q_fov"),
                ("Space Warp: \(on(S.spaceWarp))\(S.spaceWarp != S.spaceWarpActive ? " (next launch)" : "")", "q_spacewarp"),     // P381 step 9
                ("HUD Position: \(S.hudDrop < 0.33 ? "Middle" : (S.hudDrop < 0.5 ? "Low" : "Lower"))", "q_hud"),
                ("HUD Size: \(S.hudScale < 0.95 ? "Small" : (S.hudScale < 1.05 ? "Normal" : "Large"))", "q_hudsize"),
                ("Menu Size: \(S.menuScale < 0.95 ? "Small" : (S.menuScale < 1.05 ? "Normal" : (S.menuScale < 1.2 ? "Large" : "Extra Large")))", "q_menusize"),
                ("Brightness: \(PauseMenu.brightnessName(S.brightness))", "q_bright"),
                ("View Distance: \(S.renderDistance) chunks", "q_view"),                                              // P415
                ("Auto Render Distance: \(on(S.autoRenderDistance))", "q_autord"),
                ("Clouds: \(on(S.clouds))", "q_clouds"),
                ("HUD Fade: \(on(S.hudFade))", "q_hudfade"),
                ("Texture Detail: \(S.textureRes >= 128 ? "High" : "Medium")\(S.textureRes != TextureGen.size ? " (next launch)" : "")", "q_tex"),
            ]
            if hooks.rates().count <= 1 { rows.removeAll { $0.1 == "q_hz" } }
            return ("VR Comfort & Controls", "Snap turning, teleport and a strong vignette are the gentlest", rows)
        }
        PauseMenu.hostAct = { id, back in act(id, back: back) }
    }

    // The Touch layout (right-handed; Dominant Hand swaps the hands).
    static let touchRows = [
        "Right laser: aim at blocks, menus",
    ] + VRMelee.touchRows + [
        "L trigger: use / place (hold to repeat)",
        "L grip: previous hotbar slot  R grip: next",
        "L stick: move, head-relative (teleport: aim)",
        "L stick pushed forward: sprint (hand ticks)",
        "L stick click: sneak (tap: stay sneaking)",
        "R stick: turn (reclined: up/down look)",
        "A: jump      B: back; hold: drop item",
        "X: pick block; hold: offhand",
        "Y: fly on / off; hold: inventory",
        "(World map: pause menu)",
        "Click R stick: weapon wheel (flick at a gun to take it)",
        "Menu: pause; hold: recenter view",
    ]

    // The Reclined posture picks Reclined melee, snap turning and a Medium vignette or stronger; turning it off again
    // restores the melee style from before.
    static func reclinedPosture(_ on: Bool) {
        let S = QuestSettings.self
        if on && !S.reclined {
            S.swingBeforeReclined = S.swingMode ? 1 : 0
            S.swingMode = false
            // Comfort defaults lying back (VRCombatFeel): snap turns and at least a Medium vignette (changeable after).
            S.smoothTurn = false
            S.vignette = max(S.vignette, 0.6)
        } else if !on && S.reclined {
            if S.swingBeforeReclined >= 0 { S.swingMode = S.swingBeforeReclined == 1 }
            S.swingBeforeReclined = -1
        }
        S.reclined = on
    }

    static func angle(_ a: Float) -> String { a == a.rounded() ? "\(Int(a))" : String(format: "%.1f", a) }

    static func step<T: Equatable>(_ opts: [T], _ cur: T, _ back: Bool) -> T {
        let i = opts.firstIndex(of: cur) ?? (back ? 0 : opts.count - 1)
        return opts[(i + (back ? opts.count - 1 : 1)) % opts.count]
    }

    static func act(_ id: String, back: Bool) {
        let S = QuestSettings.self
        switch id {
        case "q_firstdiff":
            guard let g = newWorld() else { break }
            g.diffLevel = step([0, 1, 2, 3, 4, 5], g.diffLevel, back)          // P302: six levels
            Difficulty.level = g.diffLevel
        case "q_turn":
            S.smoothTurn.toggle()
            if S.smoothTurn && S.controlPreset == 1 { S.controlPreset = 0 }       // (Classic means snap turns)
        case "q_pos":
            let next = step([0, 1, 2], playPosition, back)
            setPlayPosition(next)
        case "q_comfort": applyComfort(step([0, 1, 2], comfortPreset ?? (back ? 0 : 2), back))
        case "q_preset": applyControlPreset(step([0, 1, 2], S.controlPreset, back))
        case "q_height":
            if let h = hooks.headHeight(), h > 1.0 && h < 2.4 {
                S.standHeight = h
                hooks.recenter()
                hooks.toast(String(format: "Height measured: eyes %.2f m above the floor", h))
            } else {
                hooks.toast("Couldn't measure: stand up straight, look ahead and try again")
            }
        case "q_setup_done":
            QuestSettings.setupShown = true
            hooks.finishSetup()
        case "q_snap": S.snapAngle = step(snapAngles, S.snapAngle, back)
        case "q_tspeed": S.smoothTurnSpeed = step(turnSpeeds, S.smoothTurnSpeed, back)
        case "q_move":
            S.teleport.toggle()
            if S.teleport && S.controlPreset == 1 { S.controlPreset = 0 }
        case "q_vig": S.vignette = step(vignettes, vignettes.min { abs($0 - S.vignette) < abs($1 - S.vignette) } ?? 0.6, back)
        case "q_subs": Settings.shared.subtitles.toggle()          // Q2c-console-53 (the Accessibility row's value)
        case "q_minetoggle": S.mineToggle.toggle()
        case "q_ctrlhints": S.ctrlHints.toggle()
        case "q_knock":
            let o: [Float] = [1, 0.4, 0]
            S.knockback = step(o, o.min { abs($0 - S.knockback) < abs($1 - S.knockback) } ?? 0.4, back)
        case "q_vib":                       // Q2c-console-35: the shared Vibration value, with a sample buzz at the new strength
            let st = Settings.shared
            st.rumble = step([0, 0.35, 0.7, 1], [0, 0.35, 0.7, 1].min { abs($0 - st.rumble) < abs($1 - st.rumble) } ?? 0.7, back)
            PadManager.shared.rumble(0.8, 0.15)
        case "q_ring": S.deckRing = S.deckRing > 0 ? 0 : 1
        case "q_saddle": S.steadySaddle.toggle()
        case "q_bank": S.craftBankFull.toggle()
        case "q_shake": S.blastShake.toggle()
        case "q_chase": S.chaseView.toggle()
        case "q_seated": S.seated.toggle(); hooks.recenter()
        case "q_reclined": reclinedPosture(!S.reclined); hooks.recenter()
        case "q_swing": S.swingMode.toggle()
        case "q_reload": S.buttonReload.toggle()
        case "q_recenter": hooks.recenter()
        case "q_held": S.heldScale = step(heldScales, heldScales.min { abs($0 - S.heldScale) < abs($1 - S.heldScale) } ?? 1, back)
        case "q_hand": S.leftHanded.toggle()
        case "q_hz":
            let rates = hooks.rates()
            guard !rates.isEmpty else { return }
            let next = step(rates, hooks.currentRate(), back)
            S.refreshRate = next
            hooks.setRate(next)
        case "q_menusize":                  // Q2c-console-49
            let o: [Float] = [0.85, 1, 1.15, 1.25]
            S.menuScale = step(o, o.min { abs($0 - S.menuScale) < abs($1 - S.menuScale) } ?? 1, back)
        case "q_hudsize":
            let o: [Float] = [0.9, 1, 1.15]
            S.hudScale = step(o, o.min { abs($0 - S.hudScale) < abs($1 - S.hudScale) } ?? 1, back)
        case "q_hud": S.hudDrop = step([Float(0.25), 0.42, 0.6], [Float(0.25), 0.42, 0.6].min { abs($0 - S.hudDrop) < abs($1 - S.hudDrop) } ?? 0.42, back)
        case "q_bright": S.brightness = step([0, 0.25, 0.5, 0.75, 1], S.brightness, back)
        case "q_view":
            // P415: live; the active distance never goes past it (Game.setActiveDistance)
            S.renderDistance = step(S.viewSteps, S.renderDistance, back)
            if let g = hooks.game() { g.setRenderDistance(S.renderDistance); g.setActiveDistance(Game.savedActiveDistance) }
        case "q_autord": S.autoRenderDistance.toggle()
        case "q_clouds": S.clouds.toggle()
        case "q_hudfade": S.hudFade.toggle()
        case "q_tex": S.textureRes = S.textureRes >= 128 ? 64 : 128
        case "q_spacewarp": S.spaceWarp.toggle()
        case "q_fov":
            S.foveation = step([0, 1, 2, 3], S.foveation, back)
            if hooks.foveated() { hooks.setFoveation(S.foveation) }
        default: break
        }
    }

    // MARK: S6 first-launch setup and presets

    // Play position: 0 Standing, 1 Seated, 2 Lying Down (QuestSettings.seated / reclined).
    static var playPosition: Int { QuestSettings.reclined ? 2 : (QuestSettings.seated ? 1 : 0) }
    static let positionNames = ["Standing", "Seated", "Lying Down"]
    static func setPlayPosition(_ p: Int) {
        let S = QuestSettings.self
        reclinedPosture(p == 2)
        S.seated = p >= 1
        hooks.recenter()
    }

    // Comfort presets (0 Comfort, 1 Moderate, 2 Free) over the existing options; nil when the options match none
    // (shown as Custom). Moderate is the headset's defaults.
    static let comfortNames = ["Comfort", "Moderate", "Free"]
    static func applyComfort(_ c: Int) {
        let S = QuestSettings.self
        switch c {
        case 0:
            S.vignette = 1; S.smoothTurn = false; S.snapAngle = 45; S.teleport = true; S.steadySaddle = true; S.blastShake = false; S.knockback = 0
        case 1:
            S.vignette = 0.6; S.smoothTurn = false; S.snapAngle = 45; S.teleport = false; S.steadySaddle = true; S.blastShake = true; S.knockback = 0.4
        default:
            S.vignette = 0; S.smoothTurn = true; S.smoothTurnSpeed = 120; S.teleport = false; S.steadySaddle = false; S.blastShake = true; S.knockback = 1
        }
        if S.controlPreset == 1 && (S.teleport || S.smoothTurn) { S.controlPreset = 0 }
    }
    static var comfortPreset: Int? {
        let S = QuestSettings.self
        if S.teleport && !S.smoothTurn && S.vignette >= 0.8 && !S.blastShake { return 0 }
        if !S.teleport && !S.smoothTurn && abs(S.vignette - 0.6) < 0.05 && S.blastShake { return 1 }
        if !S.teleport && S.smoothTurn && S.vignette < 0.05 { return 2 }
        return nil
    }

    // S7: controller presets.
    static func presetName(_ p: Int) -> String { ["Default", "Classic", "One Hand"][max(0, min(2, p))] }
    static func applyControlPreset(_ p: Int) {
        let S = QuestSettings.self
        S.controlPreset = p
        if p == 1 { S.teleport = false; S.smoothTurn = false }       // Classic: the stick walks, the other snap-turns
    }

    // The Touch rows with the hands named as the player holds them (Dominant Hand: Left mirrors every binding).
    static func touchRowsHanded() -> [String] {
        var rows = touchRows
        if QuestSettings.controlPreset == 2 { rows.insert("One Hand: R stick forward/back walks too", at: 1) }
        return QuestSettings.leftHanded ? rows.map { mirrorHands($0) } : rows
    }
    // "Right" <-> "Left", A <-> X, B <-> Y as whole words (what the swapped hands press).
    static func mirrorHands(_ s: String) -> String { ContextPrompts.mirrorHands(s) }

    // The first-launch setup (PauseMenu host page "setup"): shown once, over the first world, and from the VR page.
    static func setupPage() -> (title: String, subtitle: String, rows: [(String, String)]) {
        let S = QuestSettings.self
        let h = S.standHeight
        let measured = h > 0 ? String(format: "%.2f m", h) : "not measured"
        var rows: [(String, String)] = [
            ("Play Position: \(positionNames[playPosition])", "q_pos"),
            ("Comfort: \(comfortPreset.map { comfortNames[$0] } ?? "Custom")", "q_comfort"),
            ("Dominant Hand: \(S.leftHanded ? "Left" : "Right")", "q_hand"),
            ("Controls: \(presetName(S.controlPreset))", "q_preset"),
            ("Measure Height (stand tall, press \(S.leftHanded ? "X" : "A")): \(measured)", "q_height"),
            // Q2c-console-53: reading, hearing and touch from the first minute.
            ("Menu Size: \(S.menuScale < 0.95 ? "Small" : (S.menuScale < 1.05 ? "Normal" : (S.menuScale < 1.2 ? "Large" : "Extra Large")))", "q_menusize"),
            ("Subtitles: \(Settings.shared.subtitles ? "On" : "Off")", "q_subs"),
            ("Controller Vibration: \(Settings.shared.rumble == 0 ? "Off" : "\(Int((Settings.shared.rumble * 100).rounded()))%")", "q_vib"),
            ("Start Playing", "q_setup_done"),
        ]
        if let g = newWorld() {
            rows.insert(("First World: \(Difficulty.name(g.diffLevel))", "q_firstdiff"), at: rows.count - 1)
            return ("Welcome to Sunderfall", "Pull the trigger on a row to change it. All of it can change later in VR Comfort & Controls.", rows)
        }
        return ("Welcome to Sunderfall", "Pull the trigger on a row to change it. All of it can change later in VR Comfort & Controls.", rows)
    }
}
