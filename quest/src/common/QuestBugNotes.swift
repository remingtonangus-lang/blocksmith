import Foundation

// Voice bug notes need the Mac's microphone + speech recognizer (Sources/BugNotes.swift); on the Quest the
// feature is off and the option reads "No mic access".
final class BugNotes {
    static let shared = BugNotes()
    enum Mode: Int { case off, always, pushToTalk }
    static let names = ["Off", "Always Listening", "Push-to-Talk"]
    static let pttKey: UInt16 = 98
    var listening: Bool { false }
    var recording: Bool { false }
    var frameTime: Double = 0
    var screenshotRequest: URL?
    static var denied: Bool { true }
    static var authorized: Bool { false }
    static func requestPermission(_ done: @escaping (Bool) -> Void) { done(false) }
    func tick(_ g: Game) {}
}
