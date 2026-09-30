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

    // Controller
    @Pref("padLookX") var lookX: Float = 1           // right stick horizontal speed multiplier
    @Pref("padLookY") var lookY: Float = 1           // right stick vertical speed multiplier
    @Pref("padLookAccel") var lookAccel: Float = 0.5 // extra turn speed while the stick is held at the edge (0 = off)
    @Pref("padAimAssist") var aimAssist = true       // slow the view over mobs and hold the mined block
    @Pref("padRumble") var rumble: Float = 0.7       // vibration strength, 0 = off
    @Pref("padSouthpaw") var southpaw = false        // swap sticks (look left, move right)
    @Pref("padSneakToggle") var sneakToggle = false  // B / RS click toggles sneaking instead of holding
    @Pref("padAutoSprint") var autoSprint = true     // stick fully forward for a moment starts sprinting

    // Video
    @Pref("launchFullscreen") var launchFullscreen = true
    @Pref("vsync") var vsync = true
    @Pref("fpsCap") var fpsCap = 0                   // 0 = display refresh rate
    @Pref("renderScale") var renderScale: Float = 1  // drawable resolution scale (TVs at 4K: 0.75 saves a lot)

    // Interface
    @Pref("safeArea") var safeArea = 0               // percent of the screen kept clear at each edge (TV overscan)
    @Pref("buttonHints") var buttonHints = true      // control legends under menus and contextual prompts in game
    @Pref("glyphStyle") var glyphStyle = 0           // 0 auto (last used device), 1 controller, 2 keyboard
    @Pref("textBackground") var textBackground: Float = 0   // dark box behind HUD text (0...0.8)

    // Accessibility
    @Pref("subtitles") var subtitles = false
    @Pref("colorblind") var colorblind = false       // blue/orange instead of green/red cues
    @Pref("tutorialHints") var tutorialHints = true
    @Pref("tutorialStep") var tutorialStep = 0       // how far the first-steps hints have got

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
