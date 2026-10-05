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
    }
    static var hooks = Hooks()

    static let snapAngles: [Float] = [15, 22.5, 30, 45, 60, 90]
    static let turnSpeeds: [Float] = [45, 60, 90, 120, 150, 180, 240]
    static let vignettes: [Float] = [0, 0.3, 0.6, 1]
    static func vignetteName(_ v: Float) -> String {
        v <= 0.01 ? "Off" : (v < 0.45 ? "Low" : (v < 0.8 ? "Medium" : "High"))
    }

    static func install(_ h: Hooks) {
        hooks = h
        PauseMenu.hostEntry = ("VR Comfort & Controls...", "host:vr")
        PauseMenu.hostValues = ["q_turn", "q_snap", "q_tspeed", "q_move", "q_dir", "q_vig", "q_ring", "q_seated", "q_hand", "q_hz", "q_fov"]
        PauseMenu.hostHelp = [
            "host:vr": "Turning, movement, comfort vignette, seated play, refresh rate.",
            "q_turn": "Snap turns in steps (most comfortable) or turn smoothly while the right stick is held.",
            "q_snap": "How far one snap turn goes.",
            "q_tspeed": "How fast smooth turning goes.",
            "q_move": "Smooth: the left stick walks. Teleport: push the left stick forward, aim the arc, release to jump there.",
            "q_dir": "Walk toward where the left controller points, or where you look.",
            "q_vig": "Darkens the edges of the view while moving, turning and riding ships. Higher is more comfortable.",
            "q_ring": "A steady ring at your feet while a ship you stand on moves or turns: a fixed reference for your eyes.",
            "q_seated": "Seated: leaning doesn't walk you through the world, and recentring sets standing eye height.",
            "q_recenter": "Puts you back at the centre of your play space at the current height and facing.",
            "q_hand": "Which hand aims, breaks and uses (the other hand moves).",
            "q_hz": "Display refresh rate. Higher is smoother but uses more battery and heat.",
            "q_fov": "Renders the edges of the view at lower resolution (fixed foveated rendering): faster, slightly softer edges.",
        ]
        PauseMenu.hostPage = { id in
            guard id == "vr" else { return nil }
            let S = QuestSettings.self
            func on(_ b: Bool) -> String { b ? "On" : "Off" }
            let fovNames = ["Off", "Low", "Medium", "High"]
            let fovNote = hooks.foveated() || S.foveation == 0 ? "" : " (next launch)"
            var rows: [(String, String)] = [
                ("Turning: \(S.smoothTurn ? "Smooth" : "Snap")", "q_turn"),
                S.smoothTurn ? ("Smooth Turn Speed: \(Int(S.smoothTurnSpeed)) deg/s", "q_tspeed")
                             : ("Snap Angle: \(angle(S.snapAngle)) deg", "q_snap"),
                ("Movement: \(S.teleport ? "Teleport" : "Smooth")", "q_move"),
                ("Move Direction: \(S.headLocomotion ? "Head" : "Controller")", "q_dir"),
                ("Comfort Vignette: \(vignetteName(S.vignette))", "q_vig"),
                ("Ship Deck Ring: \(on(S.deckRing > 0))", "q_ring"),
                ("Seated Mode: \(on(S.seated))", "q_seated"),
                ("Recenter View", "q_recenter"),
                ("Dominant Hand: \(S.leftHanded ? "Left" : "Right")", "q_hand"),
                ("Refresh Rate: \(Int(hooks.currentRate())) Hz", "q_hz"),
                ("Foveated Rendering: \(fovNames[max(0, min(3, S.foveation))])\(fovNote)", "q_fov"),
            ]
            if hooks.rates().count <= 1 { rows.removeAll { $0.1 == "q_hz" } }
            return ("VR Comfort & Controls", "Snap turning, teleport and a strong vignette are the gentlest", rows)
        }
        PauseMenu.hostAct = { id, back in act(id, back: back) }
    }

    static func angle(_ a: Float) -> String { a == a.rounded() ? "\(Int(a))" : String(format: "%.1f", a) }

    static func step<T: Equatable>(_ opts: [T], _ cur: T, _ back: Bool) -> T {
        let i = opts.firstIndex(of: cur) ?? (back ? 0 : opts.count - 1)
        return opts[(i + (back ? opts.count - 1 : 1)) % opts.count]
    }

    static func act(_ id: String, back: Bool) {
        let S = QuestSettings.self
        switch id {
        case "q_turn": S.smoothTurn.toggle()
        case "q_snap": S.snapAngle = step(snapAngles, S.snapAngle, back)
        case "q_tspeed": S.smoothTurnSpeed = step(turnSpeeds, S.smoothTurnSpeed, back)
        case "q_move": S.teleport.toggle()
        case "q_dir": S.headLocomotion.toggle()
        case "q_vig": S.vignette = step(vignettes, vignettes.min { abs($0 - S.vignette) < abs($1 - S.vignette) } ?? 0.6, back)
        case "q_ring": S.deckRing = S.deckRing > 0 ? 0 : 1
        case "q_seated": S.seated.toggle(); hooks.recenter()
        case "q_recenter": hooks.recenter()
        case "q_hand": S.leftHanded.toggle()
        case "q_hz":
            let rates = hooks.rates()
            guard !rates.isEmpty else { return }
            let next = step(rates, hooks.currentRate(), back)
            S.refreshRate = next
            hooks.setRate(next)
        case "q_fov":
            S.foveation = step([0, 1, 2, 3], S.foveation, back)
            if hooks.foveated() { hooks.setFoveation(S.foveation) }
        default: break
        }
    }
}
