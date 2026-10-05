import Foundation

// Quest-only options (UserDefaults, like the game's own). Shown in the pause menu's Quest page.
enum QuestSettings {
    private static let d = UserDefaults.standard
    private static func float(_ k: String, _ def: Float) -> Float { d.object(forKey: k) == nil ? def : d.float(forKey: k) }
    private static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) == nil ? def : d.integer(forKey: k) }
    private static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }

    static var refreshRate: Float { get { float("quest.refreshRate", 72) } set { d.set(newValue, forKey: "quest.refreshRate") } }
    // The pause menu's Render Distance row saves under the game's own key, so a change made in the headset sticks.
    static var renderDistance: Int { get { int("renderDistance", 8) } set { d.set(newValue, forKey: "renderDistance") } }
    static var resolutionScale: Float { get { float("quest.resolutionScale", 1.0) } set { d.set(newValue, forKey: "quest.resolutionScale") } }
    // Turning: 0 snap, 1 smooth.
    static var smoothTurn: Bool { get { bool("quest.smoothTurn", false) } set { d.set(newValue, forKey: "quest.smoothTurn") } }
    static var snapAngle: Float { get { float("quest.snapAngle", 45) } set { d.set(newValue, forKey: "quest.snapAngle") } }
    static var smoothTurnSpeed: Float { get { float("quest.smoothTurnSpeed", 120) } set { d.set(newValue, forKey: "quest.smoothTurnSpeed") } }
    // Comfort vignette strength 0 (off) ... 1.
    static var vignette: Float { get { float("quest.vignette", 0.6) } set { d.set(newValue, forKey: "quest.vignette") } }
    // Movement: false smooth (left stick walks), true teleport (push the stick forward to aim an arc, release to jump there).
    static var teleport: Bool { get { bool("quest.teleport", false) } set { d.set(newValue, forKey: "quest.teleport") } }
    // Movement follows the head (true) or the left controller (false).
    static var headLocomotion: Bool { get { bool("quest.headLocomotion", false) } set { d.set(newValue, forKey: "quest.headLocomotion") } }
    // Seated: the game's eye height (1.62 blocks) whatever the real head height.
    static var seated: Bool { get { bool("quest.seated", false) } set { d.set(newValue, forKey: "quest.seated") } }
    static var leftHanded: Bool { get { bool("quest.leftHanded", false) } set { d.set(newValue, forKey: "quest.leftHanded") } }
    // Aboard a moving ship: strength of the reference ring at the feet (0 off ... 1).
    static var deckRing: Float { get { float("quest.deckRing", 1) } set { d.set(newValue, forKey: "quest.deckRing") } }
    static var foveation: Int { get { int("quest.foveation", 0) } set { d.set(newValue, forKey: "quest.foveation") } }
    static var textureRes: Int { get { int("quest.textureRes", 128) } set { d.set(newValue, forKey: "quest.textureRes") } }
}

extension QuestSettings {
    // Overrides from a text file (one `key = value` per line, keys as above without "quest.", e.g. `refreshRate = 90`),
    // read at start-up from the app's external files folder so options can be changed over adb without a rebuild:
    //   adb push quest-settings.txt /sdcard/Android/data/com.blocksmith.quest/files/
    static func loadOverrides(_ path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var applied: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, !kv[0].isEmpty else { continue }
            let key = kv[0] == "renderDistance" ? "renderDistance" : "quest." + kv[0], v = kv[1]
            if let b = ["true": true, "false": false, "on": true, "off": false][v.lowercased()] { d.set(b, forKey: key) }
            else if let i = Int(v) { d.set(i, forKey: key) }
            else if let f = Float(v) { d.set(f, forKey: key) }
            else { d.set(v, forKey: key) }
            applied.append("\(kv[0])=\(v)")
        }
        if !applied.isEmpty { print("settings: overrides from \(path): \(applied.joined(separator: ", "))") }
    }
}
