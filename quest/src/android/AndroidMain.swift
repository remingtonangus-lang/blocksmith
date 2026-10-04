import Foundation
import CAndroidGlue
import CVulkan
import COpenXR

// NativeActivity entry (android_native_app_glue calls android_main on its own thread). Sets up logging and the data
// folder, then runs the OpenXR frame loop while the activity is resumed; saves when paused or finishing.

private final class AndroidState {
    var resumed = false
    var destroyRequested = false
    var app: QuestApp?
}
private let state = AndroidState()

// stdout / stderr -> logcat (tag Blocksmith), line by line.
private func redirectOutputToLogcat() {
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
                        p.baseAddress!.withMemoryRebound(to: CChar.self, capacity: p.count) { _ = __android_log_write(Int32(ANDROID_LOG_INFO.rawValue), "Blocksmith", $0) }
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
        print("android: resumed")
    case Int32(APP_CMD_PAUSE):
        state.resumed = false
        QuestAudioOutput.shared.pause(true)
        state.app?.saveNow()
        print("android: paused")
    case Int32(APP_CMD_SAVE_STATE):
        state.app?.saveNow()
    case Int32(APP_CMD_DESTROY):
        state.destroyRequested = true
        print("android: destroy")
    default: break
    }
}

@_cdecl("android_main")
public func android_main(_ app: UnsafeMutablePointer<android_app>?) {
    guard let app else { return }
    redirectOutputToLogcat()
    let activity = app.pointee.activity!
    let dataPath = activity.pointee.internalDataPath.map { String(cString: $0) } ?? "/data/local/tmp/blocksmith"
    QuestPaths.setDataRoot(dataPath)
    print("Blocksmith Quest \(QuestBuild.commit) (\(QuestBuild.milestone)) starting; data in \(dataPath)")
    if let ext = activity.pointee.externalDataPath.map({ String(cString: $0) }) {
        QuestSettings.loadOverrides(ext + "/quest-settings.txt")
    }
    app.pointee.onAppCmd = { a, cmd in handleCmd(a, cmd) }

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
    print("android: main loop done")
}
