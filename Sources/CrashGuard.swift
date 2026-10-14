import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Darwin)
import Darwin
#endif

// S4 (store readiness): crash handling. A session marker (session.lock in the data folder) is written at launch and
// removed on a clean exit or while the app is paused (the system may end a paused app; that is not a crash). Found at
// the next launch, it means the last session died: the player is told, and the pause menu offers to put back the
// world's newest rolling backup (SaveIO.snapshot). A fatal signal also appends a line to crash.log beside it.
enum CrashGuard {
    private(set) static var crashed = false
    static var told = false
    private static var lockPath = ""
    private static var logFD: Int32 = -1

    static func begin(root: String) {
        lockPath = root + "/session.lock"
        crashed = FileManager.default.fileExists(atPath: lockPath)
        if crashed { print("crash guard: the last session ended unexpectedly") }
        mark(true)
        logFD = open(root + "/crash.log", O_WRONLY | O_CREAT | O_APPEND, 0o644)
        for s in [SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP] { signal(s, CrashGuard.onSignal) }
    }

    // On while the app runs in front; off when it pauses or exits cleanly.
    static func mark(_ running: Bool) {
        guard !lockPath.isEmpty else { return }
        if running { FileManager.default.createFile(atPath: lockPath, contents: Data(ISO8601DateFormatter().string(from: Date()).utf8)) }
        else { try? FileManager.default.removeItem(atPath: lockPath) }
    }

    // Async-signal-safe: a fixed message through write(2), then the default action (the system's own crash report).
    private static let onSignal: @convention(c) (Int32) -> Void = { sig in
        if CrashGuard.logFD >= 0 {
            var msg: [UInt8] = Array("blocksmith: fatal signal ".utf8)
            if sig >= 10 { msg.append(UInt8(48 + sig / 10)) }
            msg.append(UInt8(48 + sig % 10)); msg.append(10)
            _ = msg.withUnsafeBytes { write(CrashGuard.logFD, $0.baseAddress, $0.count) }
        }
        signal(sig, SIG_DFL)
        raise(sig)
    }

    // Puts the newest backup's files back into the world folder (the world must not be open). True when it did.
    static func restore(dir: URL) -> Bool {
        let fm = FileManager.default
        let src = dir.appendingPathComponent("backups/auto-1", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(atPath: src.path), !files.isEmpty else { return false }
        for f in files {
            let to = dir.appendingPathComponent(f)
            try? fm.removeItem(at: to)
            do { try fm.copyItem(at: src.appendingPathComponent(f), to: to) } catch { SaveIO.report("Restoring \(f) failed: \(error.localizedDescription)"); return false }
        }
        crashed = false
        return true
    }
}
