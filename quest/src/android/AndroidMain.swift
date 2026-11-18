import Foundation
import CAndroidGlue
import CVulkan
import COpenXR

// NativeActivity entry (android_native_app_glue calls android_main on its own thread). Sets up logging and the data
// folder, then runs the OpenXR frame loop while the activity is resumed; saves when paused or finishing.

private final class AndroidState {
    var resumed = false
    var destroyRequested = false
    var outputRedirected = false
    var app: QuestApp?
}
private let state = AndroidState()

// stdout / stderr -> logcat (tag Blocksmith), line by line, and to `logFile` (the app's external files folder, so a
// whole session can be pulled with adb after the fact; the previous launch's log is kept as blocksmith.prev.log).
private func redirectOutputToLogcat(logFile: String?) {
    var fd: Int32 = -1                  // plain POSIX file (Bionic's FILE is opaque to Swift)
    if let path = logFile {
        let prev = path.replacingOccurrences(of: ".log", with: ".prev.log")
        _ = unlink(prev); _ = rename(path, prev)
        fd = creat(path, 0o644)          // = open(O_WRONLY|O_CREAT|O_TRUNC); Bionic's variadic open is not imported
    }
    let cap = 8 << 20
    var written = 0
    setvbuf(stdout, nil, _IOLBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { return }
    dup2(fds[1], 1)
    dup2(fds[1], 2)
    let readFD = fds[0]
    let t = Thread {
        var buf = [UInt8](repeating: 0, count: 4096)
        var line = [UInt8]()
        while true {
            let n = read(readFD, &buf, buf.count)
            if n <= 0 { break }
            for i in 0..<n {
                if buf[i] == 10 {
                    line.append(0)
                    line.withUnsafeBufferPointer { p in
                        p.baseAddress!.withMemoryRebound(to: CChar.self, capacity: p.count) {
                            _ = __android_log_write(Int32(ANDROID_LOG_INFO.rawValue), "Blocksmith", $0)
                        }
                    }
                    if fd >= 0 && written < cap {
                        line[line.count - 1] = 10                  // the terminator becomes the newline
                        written += line.count
                        _ = line.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
                    }
                    line.removeAll(keepingCapacity: true)
                } else if line.count < 4000 { line.append(buf[i]) }
            }
        }
    }
    t.name = "blocksmith.log"
    t.start()
}

private func handleCmd(_ app: UnsafeMutablePointer<android_app>?, _ cmd: Int32) {
    switch cmd {
    case Int32(APP_CMD_RESUME):
        state.resumed = true
        QuestAudioOutput.shared.pause(false)
        BugNotes.shared.setPaused(false)
        CrashGuard.mark(true)                     // S4
        print("android: resumed")
    case Int32(APP_CMD_PAUSE):
        state.resumed = false
        QuestAudioOutput.shared.pause(true)
        BugNotes.shared.setPaused(true)
        state.app?.saveNow()
        CrashGuard.mark(false)                    // S4: a paused app may be ended by the system: not a crash
        print("android: paused")
    case Int32(APP_CMD_LOW_MEMORY):
        print("android: low memory")
    case Int32(APP_CMD_SAVE_STATE):
        state.app?.saveNow()
    case Int32(APP_CMD_DESTROY):
        state.destroyRequested = true
        BugNotes.shared.shutdown()
        print("android: destroy")
    default: break
    }
}

// The system soft keyboard (command box): shown / hidden by the controls, its key presses arrive as AKeyEvents from the
// activity's input queue and are typed into the game's text capture.
private func keyChar(_ code: Int32, shift: Bool) -> String? {
    switch code {
    case 29...54: return String(UnicodeScalar(UInt8((shift ? 65 : 97) + code - 29)))          // A-Z
    case 7...16:
        if shift { return Array(")!@#$%^&*(")[Int(code - 7)].description }
        return String(code - 7)
    case 62: return " "
    case 66, 160: return "\n"
    case 67: return "\u{8}"
    case 76: return shift ? "?" : "/"
    case 69: return shift ? "_" : "-"
    case 56: return shift ? ">" : "."
    case 55: return shift ? "<" : ","
    case 70: return shift ? "+" : "="
    case 74: return shift ? ":" : ";"
    case 75: return shift ? "\"" : "'"
    case 77: return "@"
    case 81: return "+"
    case 155: return "*"
    case 68: return shift ? "~" : "`"
    default: return nil
    }
}

private func handleInput(_ app: UnsafeMutablePointer<android_app>?, _ event: OpaquePointer?) -> Int32 {
    guard let event, AInputEvent_getType(event) == Int32(AINPUT_EVENT_TYPE_KEY),
          AKeyEvent_getAction(event) == Int32(AKEY_EVENT_ACTION_DOWN),
          let game = state.app?.game, game.menu?.capturesText == true,
          let c = keyChar(AKeyEvent_getKeyCode(event), shift: AKeyEvent_getMetaState(event) & 1 != 0) else { return 0 }
    game.input.typed += c
    return 1
}

private var keyboardShown = false
private func setSoftKeyboard(_ activity: UnsafeMutablePointer<ANativeActivity>, _ show: Bool) {
    guard show != keyboardShown else { return }
    keyboardShown = show
    if show { ANativeActivity_showSoftInput(activity, UInt32(ANATIVEACTIVITY_SHOW_SOFT_INPUT_FORCED)) }
    else { ANativeActivity_hideSoftInput(activity, 0) }
}

@_cdecl("android_main")
public func android_main(_ app: UnsafeMutablePointer<android_app>?) {
    guard let app else { return }
    // Android may keep the process and start a new android_main for the next launch: start from a clean lifecycle
    // state (a leftover destroyRequested ended the new launch at once), and redirect the output only once.
    state.resumed = false
    state.destroyRequested = false
    state.app = nil
    let activity = app.pointee.activity!
    let extPath = activity.pointee.externalDataPath.map { String(cString: $0) }
    if let e = extPath { try? FileManager.default.createDirectory(atPath: e, withIntermediateDirectories: true) }
    if !state.outputRedirected {
        state.outputRedirected = true
        redirectOutputToLogcat(logFile: extPath.map { $0 + "/blocksmith.log" })
    }
    var dataPath = activity.pointee.internalDataPath.map { String(cString: $0) } ?? "/data/local/tmp/blocksmith"
    var meshPath = (dataPath as NSString).deletingLastPathComponent + "/no_backup/meshcache"
    // Ledger 291 (Nov 18, his Nov 17 evening playtest: the gate's route ran on a launch he made, teleporting him for 7
    // minutes; the gate's clean-up can't reach a headset whose USB went): the debug properties (route, env) count only
    // on the launch the gate made: tools/headset_gate.sh sets debug.sunderfall.stamp to the headset's clock just before
    // it starts the app; a stamp more than 15 minutes old, or one a launch already used (<data>/gate-stamp-used), and
    // they are ignored. Android may keep the process for the next launch: the environment and the route are read again.
    let stamp = Env.androidProperty("debug.sunderfall.stamp").trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    let stampFile = dataPath + "/gate-stamp-used"
    let usedStamp = (try? String(contentsOfFile: stampFile, encoding: .utf8)) ?? ""
    let age = Int(stamp).map { Int(Date().timeIntervalSince1970) - $0 }
    let gateLaunch = age.map { $0 >= -120 && $0 <= 900 } == true && usedStamp != stamp
    let anyProps = !Env.androidProperty("debug.sunderfall.route").trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")).isEmpty
        || !Env.androidProperty("debug.sunderfall.env").trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")).isEmpty
    if gateLaunch { try? stamp.write(toFile: stampFile, atomically: true, encoding: .utf8) }
    else if anyProps { print("gate: debug properties ignored (stamp '\(stamp)', age \(age.map { "\($0) s" } ?? "none"), \(usedStamp == stamp && !stamp.isEmpty ? "already used" : "not the gate's launch"))") }
    Env.propsAllowed = gateLaunch
    Env.all = Env.load()
    QuestRoute.shared = QuestRoute.make()
    // Ledger 288 (store review: the headset gate plays as Meta's reviewer does): BS_REVIEWER=1 (a debug property, set
    // by tools/headset_gate.sh) runs on a fresh install's data: options, worlds, mesh cache and crash notes in a
    // folder emptied at each launch (<data>/reviewer), none of the player's read or written. Unset, nothing changes.
    let reviewer = Env.all["BS_REVIEWER"] == "1"
    if reviewer {
        dataPath += "/reviewer"; meshPath = dataPath + "/no_backup/meshcache"
        try? FileManager.default.removeItem(atPath: dataPath)
        print("reviewer: fresh data in \(dataPath) (default options, no worlds; the player's own are untouched)")
    }
    QuestPaths.setDataRoot(dataPath)
    SceneRenderer.pipelineCacheDir = dataPath + "/cache"   // ledger 296: compiled pipelines kept between launches
    // The world meshes outside the backed-up files (ChunkShells MeshCache.outside): <app data>/no_backup, which
    // Android's backup leaves out.
    MeshCache.outside = URL(fileURLWithPath: meshPath, isDirectory: true)
    CrashGuard.begin(root: dataPath)
    print("Blocksmith Quest \(QuestBuild.commit) (\(QuestBuild.milestone)) starting; data in \(dataPath)")
    if let ext = extPath, !reviewer { QuestSettings.loadOverrides(ext + "/quest-settings.txt") }
    // Imported textures (assets/texpack.bin, tools/texpack.py); read before the loading thread paints the layers.
    if TextureImport.pack == nil { TextureImport.load(readAsset(activity.pointee.assetManager, "texpack.bin")) }
    // Townsfolk voice takes (assets/voices.bin, tools/townvoice_gen.py).
    if TownVoice.loaded == 0 { TownVoice.load(readAsset(activity.pointee.assetManager, "voices.bin")) }
    // Recorded sounds that replace synthesized ones (RealSounds.swift): assets/sounds/real/*.ogg (Resources/Sounds/real),
    // then side-loaded files, which win: adb push step_grass.wav /sdcard/Android/data/com.blocksmith.quest/files/Sounds/
    registerRealSounds(activity.pointee.assetManager)
    registerSoundtrack(activity.pointee.assetManager)          // P359: assets/music (MediaTrackDecoder.swift)
    RealSounds.addFolder(dataPath + "/Sounds")
    if let ext = extPath { RealSounds.addFolder(ext + "/Sounds") }
    // Voice bug notes (playtest builds; a no-op stub in store builds): recordings under files/voicenotes.
    // (ledger 288: a reviewer run's notes go to its own folder, emptied at each launch, never into his playtest notes)
    if let ext = extPath {
        let files = reviewer ? ext + "/reviewer" : ext
        if reviewer { try? FileManager.default.removeItem(atPath: files) }
        BugNotes.shared.setup(activity: UnsafeMutableRawPointer(activity), files: files)
    }
    // P480: the bug and idea reporter posts through java.net on a worker thread (quest/c/report/reportpost.c).
    if !QuestBuild.reportURL.isEmpty {
        Reporter.url = QuestBuild.reportURL
        Reporter.version = "0.\(QuestBuild.versionCode) (\(QuestBuild.commit), \(QuestBuild.milestone))"
        let act = UnsafeMutableRawPointer(activity)
        Reporter.transport = { url, body, done in
            Thread.detachNewThread {
                var reply = [CChar](repeating: 0, count: 4096)
                let json = String(decoding: body, as: UTF8.self)
                let status = bs_report_post(act.assumingMemoryBound(to: ANativeActivity.self), url, json, &reply, Int32(reply.count))
                done(Int(status), String(cString: reply))
            }
        }
    }
    app.pointee.onAppCmd = { a, cmd in handleCmd(a, cmd) }
    app.pointee.onInputEvent = { a, e in handleInput(a, e) }
    keyboardShown = false
    QuestControls.keyboardHook = { show in setSoftKeyboard(activity, show) }

    var xr: XRSession?
    var failed = false
    while true {
        // Block on events while paused (nothing to render); poll while the XR session needs frames.
        let active = !failed && (state.resumed || (xr?.running ?? false))
        var events: Int32 = 0
        var source: UnsafeMutableRawPointer?
        while ALooper_pollOnce(active ? 0 : 250, nil, &events, &source) >= 0 {
            if let s = source {
                let ps = s.assumingMemoryBound(to: android_poll_source.self)
                ps.pointee.process?(app, ps)
            }
            if app.pointee.destroyRequested != 0 { state.destroyRequested = true }
        }
        if state.destroyRequested { break }
        if xr == nil && state.resumed && !failed {
            do {
                let platform = XRPlatform(javaVM: UnsafeMutableRawPointer(activity.pointee.vm), activity: UnsafeMutableRawPointer(activity.pointee.clazz))
                let x = try XRSession(platform: platform)
                xr = x
                state.app = try QuestApp(xr: x)
                QuestEntitlement.start(vm: UnsafeMutableRawPointer(activity.pointee.vm), activity: UnsafeMutableRawPointer(activity.pointee.clazz))   // S5
            } catch {
                print("FATAL: OpenXR / Vulkan setup failed: \(error)")
                failed = true
                xr = nil
                ANativeActivity_finish(activity)       // back to Home instead of an empty immersive app
            }
        }
        guard let qa = state.app else { continue }
        if !qa.frame() {
            print("android: XR session ended; finishing")
            qa.shutdown()
            ANativeActivity_finish(activity)
            state.app = nil
            break
        }
    }
    state.app?.shutdown()
    state.app = nil
    xr = nil                                       // the OpenXR session and Vulkan device go before the process does
    print("android: main loop done; exiting the process")
    // A relaunch in this same process would find process-wide state (the mesh arena's buffers, caches) tied to the
    // Vulkan device just destroyed: every launch starts in a fresh process instead (the manifest's configChanges keep
    // the activity from being recreated mid-session, so this only runs when the app really ends).
    exit(0)
}

// A file from the APK's assets/ folder, or nil.
// Lists assets/sounds/real (names only); RealSounds reads each file when its sound first loads (off the audio thread).
private func registerRealSounds(_ mgr: OpaquePointer?) {
    guard let mgr, let dir = AAssetManager_openDir(mgr, "sounds/real") else { return }
    var names: [String] = []
    while let n = AAssetDir_getNextFileName(dir) { names.append(String(cString: n)) }
    AAssetDir_close(dir)
    if names.isEmpty { return }
    // (P390: the APK carries them as Ogg Vorbis, tools/sfxpack.py, each decoded once when its sound first loads)
    RealSounds.setAssets(names, reader: { name in readAsset(mgr, "sounds/real/" + name) },
                         decoder: { name in MediaTrackDecoder.decodeAll(mgr, "sounds/real/" + name) })
}

private func readAsset(_ mgr: OpaquePointer?, _ name: String) -> Data? {
    guard let mgr, let a = AAssetManager_open(mgr, name, Int32(AASSET_MODE_BUFFER)) else { return nil }
    defer { AAsset_close(a) }
    let len = Int(AAsset_getLength64(a))
    guard len > 0, let buf = AAsset_getBuffer(a) else { return nil }
    return Data(bytes: buf, count: len)
}
