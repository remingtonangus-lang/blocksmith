#if !VOICE_NOTES
import Foundation

// Store builds (STORE=1 quest/tools/build-apk.sh) and the Linux host build: no voice bug notes, no microphone code,
// and the Options row is hidden. Playtest APKs compile quest/src/android/QuestVoiceNotes.swift instead.
final class BugNotes {
    static let shared = BugNotes()
    enum Mode: Int { case off, always, pushToTalk }
    static let names = ["Off", "Always Listening", "Push-to-Talk"]
    static let pttKey: UInt16 = 98
    static let available = false
    static let hint = ""
    var listening: Bool { false }
    var recording: Bool { false }
    var frameTime: Double = 0
    var screenshotRequest: URL?
    static var denied: Bool { true }
    static var authorized: Bool { false }
    static func requestPermission(_ done: @escaping (Bool) -> Void) { done(false) }
    func setup(activity: UnsafeMutableRawPointer, dir: String) {}
    func setPaused(_ p: Bool) {}
    func shutdown() {}
    func tick(_ g: Game) {}
}
#endif
