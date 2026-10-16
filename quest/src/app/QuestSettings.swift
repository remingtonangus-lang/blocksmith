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
    // Steady Saddle: while riding, the view eases over the horse's jumps and bucks (Game.steadySaddle).
    static var steadySaddle: Bool { get { bool("quest.steadySaddle", true) } set { store(newValue, "quest.steadySaddle") } }
    // Blast Shake: the Tidebreaker's and explosions' eye jolt in the headset (Game.vrShake); haptics stay.
    static var blastShake: Bool { get { bool("quest.blastShake", true) } set { store(newValue, "quest.blastShake") } }
    // Vehicle View (P100): taking the controls of a ship, frigate, Sky Skiff, crawler, drop craft or boat moves the view
    // out behind it (a chase view, eased, with the vignette), back to first person on leaving; off stays in first person.
    static var chaseView: Bool { get { bool("quest.chaseView", true) } set { store(newValue, "quest.chaseView") } }
    // Movement: false smooth (left stick walks), true teleport (push the stick forward to aim an arc, release to jump there).
    static var teleport: Bool { get { bool("quest.teleport", false) } set { store(newValue, "quest.teleport") } }
    // Movement follows the head (true) or the left controller (false).
    static var headLocomotion: Bool { get { bool("quest.headLocomotion", false) } set { store(newValue, "quest.headLocomotion") } }
    // Seated: the game's eye height (1.62 blocks) whatever the real head height.
    static var seated: Bool { get { bool("quest.seated", false) } set { store(newValue, "quest.seated") } }
    // Reclined (lying down): recentring also levels the view to the current gaze pitch; implies seated.
    static var reclined: Bool { get { bool("quest.reclined", false) } set { store(newValue, "quest.reclined") } }
    // Melee style (docs/status/vr-melee.md): true Swing (the blade must physically hit a mob), false Reclined (no
    // swinging: the right trigger attacks). The right trigger mines in both. The key is the old Swing Mode on/off, so
    // saved settings and `swingMode = off` overrides carry over (off = Reclined).
    static var swingMode: Bool { get { bool("quest.swingMode", true) } set { store(newValue, "quest.swingMode") } }
    // P286 (b): reload with X only (no hip pouch; X reloads faster: VRReload.buttonMode).
    static var buttonReload: Bool { get { bool("quest.buttonReload", false) } set { store(newValue, "quest.buttonReload") } }
    // The melee style before the Reclined posture switched it to Reclined (-1 none): turning the posture off restores it.
    static var swingBeforeReclined: Int { get { int("quest.swingBeforeReclined", -1) } set { store(newValue, "quest.swingBeforeReclined") } }
    static var leftHanded: Bool { get { bool("quest.leftHanded", false) } set { store(newValue, "quest.leftHanded") } }
    // S7: controller preset: 0 Default, 1 Classic (stick walks, snap turns: no teleport, no smooth turning), 2 One Hand
    // (the dominant stick also walks; HandedInput). Dominant Hand (leftHanded) swaps the hands under any preset.
    static var controlPreset: Int { get { int("quest.controlPreset", 0) } set { store(newValue, "quest.controlPreset") } }
    // S6: the standing eye height measured in the first-launch setup (metres above the floor; 0 not measured). Standing
    // play recentres to it, so a recentre while crouched or leaning still puts the view at a standing height.
    static var standHeight: Float { get { float("quest.standHeight", 0) } set { store(newValue, "quest.standHeight") } }
    // S6: the first-launch setup panel was shown (progress, not an option: Reset Options doesn't bring it back).
    static var setupShown: Bool { get { bool("quest.setupShown", false) } set { store(newValue, "quest.setupShown") } }
    // Aboard a moving ship: strength of the reference ring at the feet (0 off ... 1).
    // The held item's size (VR option "Held Item Size", audit 25b6 #4): multiplies swords, tools, blocks and guns.
    static var heldScale: Float { get { max(0.8, min(1.5, float("quest.heldScale", 1))) } set { store(newValue, "quest.heldScale") } }
    static var deckRing: Float { get { float("quest.deckRing", 1) } set { store(newValue, "quest.deckRing") } }
    // Lower the render distance when frames are missed at the frame budget (this session only).
    static var clouds: Bool { get { bool("quest.clouds", true) } set { store(newValue, "quest.clouds") } }
    // P53: the HUD panel sits translucent and comes up solid for a few seconds when a grip steps the hotbar.
    static var hudFade: Bool { get { bool("quest.hudFade", true) } set { store(newValue, "quest.hudFade") } }
    static var autoRenderDistance: Bool { get { bool("quest.autoRenderDistance", true) } set { store(newValue, "quest.autoRenderDistance") } }
    // How far below eye level the HUD panel sits, metres at 1.25 m (0.25 middle, 0.42 low, 0.6 lower).
    static var hudDrop: Float { get { float("quest.hudDrop", 0.42) } set { store(newValue, "quest.hudDrop") } }
    // Q2c-console-70: a card of a controller's buttons when it is held up and looked at.
    static var ctrlHints: Bool { get { bool("quest.ctrlHints", true) } set { store(newValue, "quest.ctrlHints") } }
    // Q2c-console-61: one pull keeps mining the block under the laser (false: hold the trigger, the default).
    static var mineToggle: Bool { get { bool("quest.mineToggle", false) } set { store(newValue, "quest.mineToggle") } }
    // Q2c-console-60: how far hits and blasts push him (1 full, 0.4 reduced, 0 off); Reduced matches the Moderate preset.
    static var knockback: Float { get { float("quest.knockback", 0.4) } set { store(newValue, "quest.knockback") } }
    // Q2c-console-49: the menu panel's and the floating HUD's size (x their default width, at the same distance).
    static var menuScale: Float { get { float("quest.menuScale", 1) } set { store(newValue, "quest.menuScale") } }
    static var hudScale: Float { get { float("quest.hudScale", 1) } set { store(newValue, "quest.hudScale") } }
    static var foveation: Int { get { int("quest.foveation", 0) } set { store(newValue, "quest.foveation") } }
    // Texture pixels per face: 128 by default, the imported art's own resolution (tools/texpack.py packs it at 128).
    // 64 was the default for a day and halved the art's detail: "everything's blurry, too compressed" (playtest
    // Oct 10, docs/status/texture-sharpness.md). The 64 that default left in saved settings moves to 128 once
    // (quest.tex128); picking Medium again afterwards sticks.
    static var textureRes: Int {
        get {
            if !d.bool(forKey: "quest.tex128") {
                d.set(true, forKey: "quest.tex128"); d.set(true, forKey: "quest.tex64")
                if d.object(forKey: "quest.textureRes") != nil && d.integer(forKey: "quest.textureRes") < 128 { store(128, "quest.textureRes") }
            }
            return int("quest.textureRes", 128)
        }
        set { store(newValue, "quest.textureRes") }
    }
}

extension QuestSettings {
    // Every Quest option with its value now (Reset Options and `questcheck --settings-only` walk this list: a new
    // option goes here too). The tutorials-shown and voice-notes-asked flags are progress, not options.
    static func snapshot() -> [(String, Any)] {
        [("quest.refreshRate", refreshRate), ("renderDistance", renderDistance), ("quest.resolutionScale", resolutionScale),
         ("quest.smoothTurn2", smoothTurn), ("quest.brightness", brightness), ("quest.pitchStep", pitchStep), ("quest.snapAngle", snapAngle),
         ("quest.smoothTurnSpeed", smoothTurnSpeed), ("quest.vignette", vignette), ("quest.steadySaddle", steadySaddle),
         ("quest.blastShake", blastShake), ("quest.chaseView", chaseView), ("quest.teleport", teleport), ("quest.headLocomotion", headLocomotion), ("quest.seated", seated),
         ("quest.reclined", reclined), ("quest.swingMode", swingMode), ("quest.buttonReload", buttonReload), ("quest.swingBeforeReclined", swingBeforeReclined),
         ("quest.leftHanded", leftHanded), ("quest.controlPreset", controlPreset), ("quest.standHeight", standHeight), ("quest.heldScale", heldScale), ("quest.deckRing", deckRing), ("quest.clouds", clouds),
         ("quest.hudFade", hudFade), ("quest.autoRenderDistance", autoRenderDistance), ("quest.hudDrop", hudDrop), ("quest.menuScale", menuScale), ("quest.hudScale", hudScale), ("quest.knockback", knockback), ("quest.mineToggle", mineToggle), ("quest.ctrlHints", ctrlHints),
         ("quest.foveation", foveation), ("quest.textureRes", textureRes)]
    }
    // The headset's own defaults for shared options: the TV-style HUD scale (bigger text), since the panel is read at
    // arm's length, unless the player picked one.
    static func platformDefaults() {
        if d.object(forKey: "couchMode") == nil { HudLayout.couch = true }
        // Q2c-console-11: messages on a dark band by default in the headset (bare white text washed out over snow and sky).
        if d.object(forKey: "textBackground") == nil { Settings.shared.textBackground = 0.5 }
    }
    // Options > Interface > Reset Options in the headset: the shared options (Settings.resetAll) and then every Quest
    // option above back to its default, the render distance included; couch mode back to the headset's default (the
    // shared reset turns it off, the Mac's default).
    static func reset(_ g: Game) {
        for (k, _) in snapshot() { d.removeObject(forKey: k) }
        clearCache()
        d.removeObject(forKey: "couchMode")
        d.removeObject(forKey: "textBackground")           // (Q2c-console-11: back to the headset's 50%, not the Mac's Off)
        platformDefaults()
        g.setRenderDistance(renderDistance)
    }

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
            let key = kv[0] == "renderDistance" || kv[0] == "directorCloud" ? kv[0] : (kv[0] == "smoothTerrain" ? "smoothTerrainPG6" : "quest." + kv[0]), v = kv[1]
            if let b = ["true": true, "false": false, "on": true, "off": false][v.lowercased()] { d.set(b, forKey: key) }
            else if let i = Int(v) { d.set(i, forKey: key) }
            else if let f = Float(v) { d.set(f, forKey: key) }
            else { d.set(v, forKey: key) }
            if key == "quest.textureRes" { d.set(true, forKey: "quest.tex64"); d.set(true, forKey: "quest.tex128") }   // an explicit pick skips the migration
            applied.append("\(kv[0])=\(v)")
        }
        clearCache()
        if !applied.isEmpty { print("settings: overrides from \(path): \(applied.joined(separator: ", "))") }
    }
}
