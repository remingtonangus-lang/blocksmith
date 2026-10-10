import Foundation

// Quest-only options (UserDefaults, like the game's own). Shown in the pause menu's Quest page.
enum QuestSettings {
    private static let d = UserDefaults.standard
    // Values read once and kept (the controls read several options every frame; UserDefaults.object(forKey:)
    // allocated each time: questcheck's allocation trace). Every write goes through the setters below, which
    // refresh the cache; loadOverrides clears it. renderDistance is the game's own key, written by its pause menu,
    // so it is always read through.
    private static var floats: [String: Float] = [:], ints: [String: Int] = [:], bools: [String: Bool] = [:]
    private static let lock = NSLock()            // read on the frame and loading threads
    private static func float(_ k: String, _ def: Float) -> Float {
        lock.lock(); defer { lock.unlock() }
        if let v = floats[k] { return v }
        let v = d.object(forKey: k) == nil ? def : d.float(forKey: k)
        floats[k] = v
        return v
    }
    private static func int(_ k: String, _ def: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        if let v = ints[k] { return v }
        let v = d.object(forKey: k) == nil ? def : d.integer(forKey: k)
        ints[k] = v
        return v
    }
    private static func bool(_ k: String, _ def: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let v = bools[k] { return v }
        let v = d.object(forKey: k) == nil ? def : d.bool(forKey: k)
        bools[k] = v
        return v
    }
    private static func store(_ v: Float, _ k: String) { d.set(v, forKey: k); lock.lock(); floats[k] = v; lock.unlock() }
    private static func store(_ v: Int, _ k: String) { d.set(v, forKey: k); lock.lock(); ints[k] = v; lock.unlock() }
    private static func store(_ v: Bool, _ k: String) { d.set(v, forKey: k); lock.lock(); bools[k] = v; lock.unlock() }
    static func clearCache() { lock.lock(); floats.removeAll(); ints.removeAll(); bools.removeAll(); lock.unlock() }

    // 90 Hz by default (comfort: smoother motion; device v13 used ~2.9 ms CPU and ~2.9 ms GPU of the 11.1 ms budget).
    static var refreshRate: Float { get { float("quest.refreshRate", 90) } set { store(newValue, "quest.refreshRate") } }
    // The pause menu's Render Distance row saves under the game's own key, so a change made in the headset sticks.
    // 16 by default (Oct 10 performance pass: water-tick, mob path and mob drawing costs cut, far detail from 5 chunks;
    // the rd 16 Quest-proxy bench holds frame p99 <= 13.9 ms on all six routes; docs/status/performance.md). Saved
    // distances under 16 are raised once (12 was the default; the comfort guard's step-downs also leaked into saves);
    // the comfort guard still steps down for the session if the headset misses frames.
    static var renderDistance: Int {
        get {
            if !d.bool(forKey: "quest.rd16") {
                d.set(true, forKey: "quest.rd16")
                d.set(true, forKey: "quest.rd12")
                if d.object(forKey: "renderDistance") != nil && d.integer(forKey: "renderDistance") < 16 { d.set(16, forKey: "renderDistance") }
            }
            return d.object(forKey: "renderDistance") == nil ? 16 : d.integer(forKey: "renderDistance")
        }
        set { d.set(newValue, forKey: "renderDistance") }
    }
    static var resolutionScale: Float { get { float("quest.resolutionScale", 1.0) } set { store(newValue, "quest.resolutionScale") } }
    // Turning: snap by default (smooth turning is an option, and makes some people sick).
    // Voice bug notes (playtest builds): set once the first launch has turned them on and asked for the microphone.
    static var voiceNotesAsked: Bool { get { bool("quest.voiceNotesAsked", false) } set { store(newValue, "quest.voiceNotesAsked") } }
    static var smoothTurn: Bool { get { bool("quest.smoothTurn2", false) } set { store(newValue, "quest.smoothTurn2") } }
    // Cave fill and light-curve lift (Mac Options > Video > Brightness): 0 moody ... 1 bright; Quest default is a notch up.
    static var brightness: Float { get { float("quest.brightness", 0.75) } set { store(newValue, "quest.brightness") } }
    // Reclined look up/down step (right stick up/down), degrees.
    static var pitchStep: Float { get { float("quest.pitchStep", 15) } set { store(newValue, "quest.pitchStep") } }
    static var snapAngle: Float { get { float("quest.snapAngle", 45) } set { store(newValue, "quest.snapAngle") } }
    static var smoothTurnSpeed: Float { get { float("quest.smoothTurnSpeed", 90) } set { store(newValue, "quest.smoothTurnSpeed") } }
    // Comfort vignette strength 0 (off) ... 1.
    static var vignette: Float { get { float("quest.vignette", 0.6) } set { store(newValue, "quest.vignette") } }
    // Movement: false smooth (left stick walks), true teleport (push the stick forward to aim an arc, release to jump there).
    static var teleport: Bool { get { bool("quest.teleport", false) } set { store(newValue, "quest.teleport") } }
    // Movement follows the head (true) or the left controller (false).
    static var headLocomotion: Bool { get { bool("quest.headLocomotion", false) } set { store(newValue, "quest.headLocomotion") } }
    // Seated: the game's eye height (1.62 blocks) whatever the real head height.
    static var seated: Bool { get { bool("quest.seated", false) } set { store(newValue, "quest.seated") } }
    // Reclined (lying down): recentring also levels the view to the current gaze pitch; implies seated.
    static var reclined: Bool { get { bool("quest.reclined", false) } set { store(newValue, "quest.reclined") } }
    // Swing Mode: a full-arm swing breaks / attacks (on); off: the right trigger does.
    static var swingMode: Bool { get { bool("quest.swingMode", true) } set { store(newValue, "quest.swingMode") } }
    static var leftHanded: Bool { get { bool("quest.leftHanded", false) } set { store(newValue, "quest.leftHanded") } }
    // Aboard a moving ship: strength of the reference ring at the feet (0 off ... 1).
    static var deckRing: Float { get { float("quest.deckRing", 1) } set { store(newValue, "quest.deckRing") } }
    // Lower the render distance when frames are missed at the frame budget (this session only).
    static var autoRenderDistance: Bool { get { bool("quest.autoRenderDistance", true) } set { store(newValue, "quest.autoRenderDistance") } }
    // How far below eye level the HUD panel sits, metres at 1.25 m (0.25 middle, 0.42 low, 0.6 lower).
    static var hudDrop: Float { get { float("quest.hudDrop", 0.42) } set { store(newValue, "quest.hudDrop") } }
    static var foveation: Int { get { int("quest.foveation", 0) } set { store(newValue, "quest.foveation") } }
    // Texture pixels per face: 64 by default (imported art is packed at 64 by tools/texpack.py; a quarter of the
    // memory of 128). A saved 128 from before is moved to 64 once; picking High again afterwards sticks.
    static var textureRes: Int {
        get {
            if !d.bool(forKey: "quest.tex64") {
                d.set(true, forKey: "quest.tex64")
                if d.object(forKey: "quest.textureRes") != nil && d.integer(forKey: "quest.textureRes") > 64 { store(64, "quest.textureRes") }
            }
            return int("quest.textureRes", 64)
        }
        set { store(newValue, "quest.textureRes") }
    }
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
            let key = kv[0] == "renderDistance" || kv[0] == "smoothTerrain" ? kv[0] : "quest." + kv[0], v = kv[1]
            if let b = ["true": true, "false": false, "on": true, "off": false][v.lowercased()] { d.set(b, forKey: key) }
            else if let i = Int(v) { d.set(i, forKey: key) }
            else if let f = Float(v) { d.set(f, forKey: key) }
            else { d.set(v, forKey: key) }
            if key == "quest.textureRes" { d.set(true, forKey: "quest.tex64") }   // an explicit pick skips the 64 migration
            applied.append("\(kv[0])=\(v)")
        }
        clearCache()
        if !applied.isEmpty { print("settings: overrides from \(path): \(applied.joined(separator: ", "))") }
    }
}
