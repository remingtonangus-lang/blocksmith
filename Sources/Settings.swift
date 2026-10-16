import Foundation

// A UserDefaults-backed option, cached in memory so it can be read every frame.
@propertyWrapper struct Pref<T> {
    let key: String
    private var value: T
    init(wrappedValue: T, _ key: String) {
        self.key = key
        value = (UserDefaults.standard.object(forKey: key) as? T) ?? wrappedValue
    }
    var wrappedValue: T {
        get { value }
        set { value = newValue; UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// Couch / controller / accessibility options added for TV play. Older options (FOV, sensitivity,
// invert Y, dead zone, volume...) still live on Game; GUI scale and couch mode on HudLayout.
final class Settings {
    static let shared = Settings()
    init() {
        // A saved Safe Area off the 0-10 step list (5% on Remington's Mac, from an older list) could never be stepped
        // back to (padtest audit, store audit): snap it to the next step.
        if ![0, 2, 4, 6, 8, 10].contains(safeArea) { safeArea = min(10, max(0, (safeArea + 1) / 2 * 2)) }
    }
    #if os(macOS)
    static let lookDeadKey = "padLookDead10", lookDeadDefault: Float = 0.10
    #else
    static let lookDeadKey = "padLookDead", lookDeadDefault: Float = 0.08
    #endif

    // Controller
    // Look feel follows Halo Infinite's controller defaults (PadLook): sensitivity 3/3, acceleration 3, power curve.
    @Pref("padLookSensH") var lookX: Float = 3       // right stick horizontal sensitivity, 1-10
    @Pref("padLookSensV") var lookY: Float = 3       // right stick vertical sensitivity, 1-10
    @Pref("padLookAccel5") var lookAccel: Float = 3  // look acceleration at the stick's edge, 0 (off) - 5
    // Mac default 0.10 (Halo-like); new key on the Mac so the old 0.08 default resets once. The Quest keeps 0.08.
    @Pref(Settings.lookDeadKey) var lookDead: Float = Settings.lookDeadDefault  // look stick centre dead zone
    @Pref("padLookOuter") var lookOuter: Float = 0.05 // look stick max input threshold (outer dead zone)
    @Pref("padMoveOuter") var moveOuter: Float = 0.05 // move stick max input threshold
    @Pref("padAimAssist") var aimAssist = true       // slow the view over mobs and hold the mined block
    @Pref("padRumble") var rumble: Float = 0.7       // vibration strength, 0 = off
    @Pref("padSouthpaw") var southpaw = false        // swap sticks (look left, move right)
    @Pref("padSneakToggle") var sneakToggle = false  // B toggles sneaking instead of holding
    @Pref("padAutoSprint") var autoSprint = true     // stick fully forward for a moment starts sprinting
    @Pref("padFlightInverted") var flightInverted = true   // aircraft: pull the stick back to climb
    @Pref("padLookCurve2") var lookCurve = 0         // right stick response: 0 default (power), 1 linear, 2 precise

    // Video
    @Pref("launchFullscreen") var launchFullscreen = true
    @Pref("vsync") var vsync = true
    @Pref("fpsCap") var fpsCap = 0                   // 0 = display refresh rate
    @Pref("display") var display = ""                // screen name to play on ("" = main screen)
    @Pref("renderScale") var renderScale: Float = 1  // whole-frame resolution scale (TVs at 4K: 0.75 saves a lot); Fancy world scale is Game.renderScale
    @Pref("musicSource") var musicSource = 0         // 0 built-in soundtrack, 1 My Music (CustomMusic folder), 2 mixed
    @Pref("musicShuffle") var musicShuffle = true
    @Pref("customMusicVolume") var customMusicVolume: Float = 1    // on top of Music
    @Pref("brightness") var brightness: Float = 0.5  // cave fill and light curve lift: 0 moody, 0.5 default, 1 bright (Shaders.caveFill)
    var brightnessOverride: Float?                  // harness --bright (not saved)
    var lightBrightness: Float { brightnessOverride ?? brightness }

    // Interface
    @Pref("safeArea") var safeArea = 0               // percent of the screen kept clear at each edge (TV overscan)
    @Pref("buttonHints") var buttonHints = true      // control legends under menus and contextual prompts in game
    @Pref("glyphStyle") var glyphStyle = 0           // 0 auto (last used device), 1 controller, 2 keyboard
    @Pref("textBackground") var textBackground: Float = 0   // dark box behind HUD text (0...0.8)
    @Pref("minimap") var minimap = true             // biome minimap in the top-right corner
    @Pref("chipping") var chipping = true           // mining chips pieces off a block until it breaks (World.chip)
    @Pref("crosshair") var crosshair = 0             // 0 classic, 1 bold (high contrast), 2 dot
    @Pref("splitSideBySide") var splitSideBySide = false   // split screen (Coop.swift): left / right instead of top / bottom

    // Accessibility
    // One subtitles setting for the whole game; stored here (key kept from the audio workstream). AudioSettings.subtitles
    // reads it (plus the harness override). Both used to forward to each other: infinite recursion, a hang every frame.
    @Pref("audio_subtitles") var subtitles = false
    @Pref("colorblind") var colorblind = false       // blue/orange instead of green/red cues
    @Pref("tutorialHints") var tutorialHints = true
    @Pref("tutorialStep") var tutorialStep = 0       // how far the first-steps hints have got
    @Pref("bugNotes") var bugNotes = 0               // voice bug notes: 0 off, 1 always listening, 2 push-to-talk (BugNotes.swift)
    @Pref("narrator") var narrator = false           // speak highlighted menu items and toasts
    @Pref("screenEffects") var screenEffects = true  // full-strength red damage flash and portal tint (off = faint)

    // Options > Interface > Reset Options: everything back to the defaults (key bindings included).
    func resetAll(_ g: Game) {
        lookX = 3; lookY = 3; lookAccel = 3; lookDead = Settings.lookDeadDefault; lookOuter = 0.05; moveOuter = 0.05; aimAssist = true; rumble = 0.7; southpaw = false; sneakToggle = false; autoSprint = true; lookCurve = 0; flightInverted = true
        launchFullscreen = true; vsync = true; fpsCap = 0; renderScale = 1; brightness = 0.5
        musicSource = 0; musicShuffle = true; customMusicVolume = 1
        safeArea = 0; buttonHints = true; glyphStyle = 0; textBackground = 0; crosshair = 0; minimap = true; splitSideBySide = false
        subtitles = false; colorblind = false; tutorialHints = true; screenEffects = true; narrator = false
        g.fovSetting = 70; g.sensitivity = 1; g.invertY = false; g.autoJump = false; g.deadZone = 0.08
        g.volumeSetting = 0.8; g.musicVolume = 1
        for c in SoundCategory.allCases { AudioSettings.set(c, c == .master ? 0.8 : 1) }
        g.fancyGraphics = true; g.renderScale = 1
        HudLayout.userScale = 0; HudLayout.couch = false
        KeyBinds.reset()
        PadMap.reset()
    }

    // Colour for "good / available" and "bad / unavailable" cues, colourblind-safe when asked.
    var goodColor: V4 { colorblind ? V4(0.35, 0.65, 1, 1) : V4(0.5, 1, 0.13, 1) }
    var badColor: V4 { colorblind ? V4(1, 0.6, 0.1, 1) : V4(1, 0.38, 0.38, 1) }

    static let fpsOptions = [0, 30, 60, 120]
    static let renderScaleOptions: [Float] = [1, 0.85, 0.75, 0.6, 0.5]
}

// Test harness helper: remembers the app's saved defaults and puts them back afterwards, so scripted
// menu tests never change the player's real options.
enum PrefsSandbox {
    private static var saved: [String: Any]?
    static var domain: String { Bundle.main.bundleIdentifier ?? "com.remington.blocksmith" }
    static func begin() {
        saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
    }
    static func end() {
        guard let s = saved else { return }
        UserDefaults.standard.setPersistentDomain(s, forName: domain)
        saved = nil
    }
}
