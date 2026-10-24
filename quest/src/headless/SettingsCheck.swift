import Foundation
import Metal

// Options persist and Reset Options resets them (Q2, scorecard "Consistency: settings persist"; `questcheck
// --settings-only`, and part of every questcheck run). Three fresh processes share one data root, as three launches
// of the game would: the first writes a non-default value for every option (every @Pref of Settings, found with
// Mirror, the older options on Game, HudLayout, the volume sliders and a key binding, and the headset's VR options);
// the second checks each one came back and runs Options > Interface > Reset Options; the third checks every option is
// back at its default.
enum SettingsCheck {
    // Options that are progress rather than settings: Reset Options leaves them.
    static let progress: Set<String> = ["tutorialStep"]

    static func prefs(_ s: Settings) -> [(String, Any)] {
        Mirror(reflecting: s).children.compactMap { ($0.value as? AnyPref).map { ($0.prefKey, $0.anyValue) } }
    }
    // Every option by its saved key, read the way the game reads it: Settings' @Prefs, the older options on Game,
    // HudLayout, the volume sliders and a key binding, and the headset's own (QuestSettings.snapshot).
    static func all(_ s: Settings, _ g: Game) -> [(String, Any)] {
        var r = prefs(s)
        r += [("fov", g.fovSetting), ("sensitivity", g.sensitivity), ("invertY", g.invertY), ("autoJump", g.autoJump),
              ("moveDeadZone", g.deadZone), ("volume", g.volumeSetting), ("musicVolume", g.musicVolume), ("fancyGraphics", g.fancyGraphics),
              ("fancyWorldScale", g.renderScale), ("guiScale", HudLayout.userScale), ("couchMode", HudLayout.couch)]
        for c in SoundCategory.allCases where c != .master && c != .music { r.append((c.key, AudioSettings.volume(c))) }
        r.append(("key.jump", KeyBinds.key(.jump)))
        return r + QuestSettings.snapshot()
    }
    // A value off the default, of the type the game stores.
    static func other(_ v: Any) -> Any {
        switch v {
        case let b as Bool: return !b
        case let i as Int: return i >= 24 ? i - 2 : i + 2    // (Safe Area steps by 2; View Distance tops out at 24)
        case let k as UInt16: return Int(k) + 1              // a key code
        case let f as Float: return f + 0.25
        case let s as String: return s + "check"
        default: return v
        }
    }
    static func desc(_ v: Any) -> String { "\(v)" }

    // A launch: the options as the game builds them at start-up (the headset's defaults and reset hook as
    // QuestControls and QuestOptions.install set them).
    static func launch() -> (Settings, Game) {
        QuestSettings.platformDefaults()
        Settings.onReset = { g in QuestSettings.reset(g) }
        let w = World(seed: 7, device: sharedSystemDevice, save: nil)
        w.renderDistance = 2
        return (Settings.shared, Game(world: w, save: nil, persistent: false))
    }

    // One phase, in a child process whose data root is `root`.
    static func phase(_ p: String, root: String) -> Int32 {
        QuestPaths.setDataRoot(root)
        let d = UserDefaults.standard
        let file = root + "/settings-check.txt"
        let (s, g) = launch()
        let opts = all(s, g)
        var bad: [String] = []
        switch p {
        case "write":
            var lines: [String] = []
            for (k, v) in opts {
                let o = other(v)
                if desc(o) == desc(v) { bad.append("\(k): no off-default value for a \(type(of: v))") }
                d.set(o, forKey: k)
                lines.append("\(k)\t\(desc(v))\t\(desc(o))")
            }
            try? lines.joined(separator: "\n").write(toFile: file, atomically: true, encoding: .utf8)
            d.synchronize()
            print((bad.isEmpty ? "ok   " : "FAIL ") + "settings: every option has an off-default value to test (\(opts.count))" + (bad.isEmpty ? "" : ": " + bad.joined(separator: ", ")))
        case "read", "verify":
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { print("FAIL settings: no record from the write phase"); return 1 }
            let now = Dictionary(opts.map { ($0.0, desc($0.1)) }, uniquingKeysWith: { a, _ in a })
            var n = 0
            for line in text.split(separator: "\n") {
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count == 3 else { continue }
                if p == "verify" && progress.contains(f[0]) { continue }
                n += 1
                let want = p == "verify" ? f[1] : f[2]
                if now[f[0]] != want { bad.append("\(f[0]) \(now[f[0]] ?? "missing") (want \(want))") }
            }
            if p == "read" {
                s.resetAll(g)
                d.synchronize()
                // The running game takes the reset at once, not only on the next launch.
                let live = Dictionary(all(s, g).map { ($0.0, desc($0.1)) }, uniquingKeysWith: { a, _ in a })
                var stale: [String] = []
                for line in text.split(separator: "\n") {
                    let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    if f.count == 3, !progress.contains(f[0]), live[f[0]] != f[1] { stale.append("\(f[0]) \(live[f[0]] ?? "missing") (want \(f[1]))") }
                }
                print((stale.isEmpty ? "ok   " : "FAIL ") + "settings: Reset Options takes effect in the running game" + (stale.isEmpty ? "" : ": " + stale.prefix(12).joined(separator: ", ")))
                if !stale.isEmpty { bad.append("(live reset)") }
            }
            print((bad.isEmpty ? "ok   " : "FAIL ") + (p == "read" ? "settings: every option survives a relaunch" : "settings: Reset Options puts every option back to its default, after a relaunch too")
                  + " (\(n) options)" + (bad.isEmpty ? "" : ": " + bad.prefix(12).joined(separator: ", ")))
        default:
            return 2
        }
        return bad.isEmpty ? 0 : 1
    }

    // The driver: the three launches, each a child questcheck.
    static func run(check: (Bool, String) -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("settings-check-\(getpid())").path
        try? FileManager.default.removeItem(atPath: root)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        for p in ["write", "read", "verify"] {
            let pr = Process()
            pr.executableURL = exe
            pr.arguments = ["--settings-phase", p, root]
            let pipe = Pipe()
            pr.standardOutput = pipe; pr.standardError = pipe
            do { try pr.run() } catch { check(false, "settings: could not launch the \(p) phase (\(error))"); return }
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            pr.waitUntilExit()
            let lines = out.split(separator: "\n")
            for l in lines where l.hasPrefix("settings write") { print(l) }
            let res = lines.filter { $0.hasPrefix("ok   settings") || $0.hasPrefix("FAIL") }
            for l in res { check(l.hasPrefix("ok"), String(l.dropFirst(5))) }
            if pr.terminationStatus != 0 && res.isEmpty || p != "write" && res.isEmpty {
                check(false, "settings: the \(p) launch failed (exit \(pr.terminationStatus)): \(out.suffix(400))"); return
            }
        }
    }
}
