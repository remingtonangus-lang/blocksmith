import Foundation

// Quest-only options (UserDefaults, like the game's own). Shown in the pause menu's Quest page.
enum QuestSettings {
    private static let d = UserDefaults.standard
    private static func float(_ k: String, _ def: Float) -> Float { d.object(forKey: k) == nil ? def : d.float(forKey: k) }
    private static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) == nil ? def : d.integer(forKey: k) }
    private static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }

    static var refreshRate: Float { get { float("quest.refreshRate", 72) } set { d.set(newValue, forKey: "quest.refreshRate") } }
    static var renderDistance: Int { get { int("quest.renderDistance", 6) } set { d.set(newValue, forKey: "quest.renderDistance") } }
    static var resolutionScale: Float { get { float("quest.resolutionScale", 1.0) } set { d.set(newValue, forKey: "quest.resolutionScale") } }
    // Turning: 0 snap, 1 smooth.
    static var smoothTurn: Bool { get { bool("quest.smoothTurn", false) } set { d.set(newValue, forKey: "quest.smoothTurn") } }
    static var snapAngle: Float { get { float("quest.snapAngle", 45) } set { d.set(newValue, forKey: "quest.snapAngle") } }
    static var smoothTurnSpeed: Float { get { float("quest.smoothTurnSpeed", 120) } set { d.set(newValue, forKey: "quest.smoothTurnSpeed") } }
    // Comfort vignette strength 0 (off) ... 1.
    static var vignette: Float { get { float("quest.vignette", 0.6) } set { d.set(newValue, forKey: "quest.vignette") } }
    // Movement follows the head (true) or the left controller (false).
    static var headLocomotion: Bool { get { bool("quest.headLocomotion", false) } set { d.set(newValue, forKey: "quest.headLocomotion") } }
    // Seated: the game's eye height (1.62 blocks) whatever the real head height.
    static var seated: Bool { get { bool("quest.seated", false) } set { d.set(newValue, forKey: "quest.seated") } }
    static var leftHanded: Bool { get { bool("quest.leftHanded", false) } set { d.set(newValue, forKey: "quest.leftHanded") } }
    static var foveation: Int { get { int("quest.foveation", 2) } set { d.set(newValue, forKey: "quest.foveation") } }
    static var textureRes: Int { get { int("quest.textureRes", 64) } set { d.set(newValue, forKey: "quest.textureRes") } }
}
