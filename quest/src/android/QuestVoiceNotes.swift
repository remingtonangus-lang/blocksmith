#if VOICE_NOTES
import Foundation
import CAndroidGlue

// Voice bug notes on the Quest, dev/playtest builds only. `STORE=1 quest/tools/build-apk.sh` leaves this file, the
// mic C code (quest/c/voice) and the RECORD_AUDIO permission out and compiles quest/src/common/QuestBugNotes.swift's
// stub instead; quest/tools/storecheck.sh proves the store APK has none of it.
// While the game is open the mic listens (Options > Interface > Bug Notes: Always Listening, Push-to-Talk with both
// sticks clicked, or Off). Only speech is kept: VoiceSegmenter (Sources/VoiceNoteCore.swift) opens a note after
// 0.12 s of voice, with 0.5 s before and 1 s after; silence is never written. Each note is
//   files/voicenotes/vn-YYYYMMDD-HHMMSS-mmm.aac    AAC-LC 16 kHz mono 24 kb/s ADTS (~11 MB per hour of talk; flushed
//                                                    as it goes, so a crash loses well under a second)
//   files/voicenotes/vn-...jsonl                    start line (build, game state, recent events, levels), a state
//                                                    line every 5 s, an end line
//   files/voicenotes/vn-...png                      what the player saw when the note started (QuestScreenshot)
// The folder is capped at 2 GB (oldest deleted first). tools/quest-bugnotes.py pulls and transcribes them.
// The mic uses the VOICE_COMMUNICATION preset (echo cancellation removes the game's own sound from the speakers),
// and the segmenter's threshold also follows the mixer's output level (QuestAudioOutput.level).
final class BugNotes {
    static let shared = BugNotes()
    enum Mode: Int { case off = 0, always = 1, pushToTalk = 2 }
    static let names = ["Off", "Always Listening", "Push-to-Talk"]
    static let pttKey: UInt16 = 98
    static let available = true
    static let hint = "Playtest build: records only your speech (silence is skipped) on the headset with the game state and a screenshot, for bug reports. Off records nothing."
    static let rate: Int32 = 16000
    static let bitrate: Int32 = 24000
    static let maxBytes: Int64 = 2 << 30

    var frameTime: Double = 0
    var screenshotRequest: URL?
    private(set) var listening = false
    private(set) var recording = false
    var mode: Mode { Mode(rawValue: Settings.shared.bugNotes) ?? .off }

    private var activity: UnsafeMutablePointer<ANativeActivity>?
    private var dir = ""
    private var paused = true
    private var permission = false
    private var pending: ((Bool) -> Void)?
    private var pendingAt = 0.0, pendingPaused = false, permPoll = 0.0
    private var firstLaunch = false, setupAt = 0.0
    private weak var game: Game?
    private let events = VoiceEvents()
    private var open: String?
    private var lastState = 0.0, lastShot = -100.0
    private let io = DispatchQueue(label: "blocksmith.voicenotes", qos: .utility)

    // Shared with the audio thread, under `lock`.
    private let lock = NSLock()
    private var run = false
    private var threadAlive = false
    private var sharedMode = Mode.off
    private var ptt = false
    private var level: Float = 0
    private var started: [String] = []
    private var ended: [(stamp: String, keep: Bool, length: Double, voiced: Double)] = []
    private var failed: String?

    static var denied: Bool { false }
    static var authorized: Bool { shared.permission }

    // From android_main, before the first frame.
    func setup(activity raw: UnsafeMutableRawPointer, dir d: String) {
        activity = raw.assumingMemoryBound(to: ANativeActivity.self)
        dir = d
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        permission = activity.map { bs_mic_permission($0) == 1 } ?? false
        firstLaunch = !QuestSettings.voiceNotesAsked
        setupAt = CFAbsoluteTimeGetCurrent()
        print("voicenotes: dir \(d), mic permission \(permission), mode \(mode)")
        io.async { VoiceNoteContext.enforceCap(dir: d, maxBytes: BugNotes.maxBytes) }
    }

    // App lifecycle: the mic is released while the app is paused (headset off, system menu, permission dialog).
    func setPaused(_ p: Bool) {
        paused = p
        if p { pendingPaused = true }
    }

    func shutdown() {
        lock.lock(); run = false; lock.unlock()
    }

    static func requestPermission(_ done: @escaping (Bool) -> Void) { shared.request(done) }

    private func request(_ done: @escaping (Bool) -> Void) {
        guard let a = activity else { done(false); return }
        if bs_mic_permission(a) == 1 { permission = true; done(true); return }
        guard bs_mic_request(a) == 0 else { done(false); return }
        pending = done
        pendingAt = CFAbsoluteTimeGetCurrent()
        pendingPaused = false
        print("voicenotes: asked for microphone permission")
    }

    func tick(_ g: Game) {
        game = g
        events.observe(g)
        let wall = CFAbsoluteTimeGetCurrent()
        // Permission dialog result: NativeActivity gets no callback, so poll while it is open; the answer is final
        // once the app resumes after the dialog paused it.
        if let done = pending, let a = activity, wall - permPoll > 0.5 {
            permPoll = wall
            let ok = bs_mic_permission(a) == 1
            if ok || (pendingPaused && !paused) || wall - pendingAt > 120 {
                pending = nil
                permission = ok
                print("voicenotes: microphone permission \(ok ? "granted" : "not granted")")
                done(ok)
            }
        }
        // First launch of a playtest build: turn notes on (disclosed in a message) and ask for the mic, once.
        if firstLaunch && !paused && wall - setupAt > 6 && g.menu == nil {
            firstLaunch = false
            QuestSettings.voiceNotesAsked = true
            Settings.shared.bugNotes = Mode.always.rawValue
            let on = "Voice bug notes are ON (playtest build): your speech is recorded on the headset with the game state. Options > Interface > Bug Notes"
            if permission { g.onToast?(on) } else {
                request { ok in
                    if ok { g.onToast?(on) } else {
                        Settings.shared.bugNotes = Mode.off.rawValue
                        g.onToast?("Voice bug notes off: no microphone permission")
                    }
                }
            }
        }
        let m = mode
        let want = m != .off && permission && !paused && HudExtras.enabled
        let raw = PadManager.shared.lastRaw
        lock.lock()
        sharedMode = m
        ptt = raw.l3 && raw.r3
        let s = started, e = ended, f = failed
        started.removeAll(); ended.removeAll(); failed = nil
        let go = want && f == nil
        run = go
        let spawn = go && !threadAlive
        if spawn { threadAlive = true }          // the thread clears it when it exits
        lock.unlock()
        if let f { print("voicenotes: \(f)"); g.onToast?("Bug Notes: \(f)"); Settings.shared.bugNotes = Mode.off.rawValue }
        if spawn {
            let t = Thread { [weak self] in self?.audioLoop() }
            t.name = "voicenotes"
            t.qualityOfService = .utility
            t.start()
        }
        listening = go
        for st in s { noteStarted(st, g, wall) }
        for x in e { noteEnded(x) }
        recording = open != nil
        if let o = open, wall - lastState >= 5 {
            lastState = wall
            let line = VoiceNoteContext.json([("event", "state"), ("time", BugNotes.iso()), ("context", context(g)),
                                              ("events", events.recent(g, seconds: 5))])
            append(o, line)
        }
    }

    private func context(_ g: Game) -> [(String, String)] {
        let fps = frameTime > 0 ? 1 / frameTime : 0
        var c = VoiceNoteContext.describe(g, build: "0.\(QuestBuild.versionCode) (\(QuestBuild.commit), \(QuestBuild.milestone))", fps: fps)
        lock.lock(); let lv = level; lock.unlock()
        c.append(("levels", String(format: "mic %.0f dBFS, game sound %.0f dBFS", BugNotes.db(lv), BugNotes.db(QuestAudioOutput.level))))
        return c
    }

    private func noteStarted(_ st: String, _ g: Game, _ wall: Double) {
        open = st
        lastState = wall
        var shot: String?
        if wall - lastShot > 10 {
            lastShot = wall
            shot = "vn-\(st).png"
            QuestScreenshot.request(path: dir + "/" + shot!)
        }
        let line = VoiceNoteContext.json([("event", "start"), ("time", BugNotes.iso()), ("stamp", st),
                                          ("audio", "vn-\(st).aac"), ("screenshot", shot ?? ""), ("context", context(g)),
                                          ("events", events.recent(g))])
        append(st, line)
    }

    private func noteEnded(_ x: (stamp: String, keep: Bool, length: Double, voiced: Double)) {
        if open == x.stamp { open = nil }
        let d = dir, st = x.stamp
        if !x.keep {
            io.async { for ext in ["aac", "jsonl", "png"] { try? FileManager.default.removeItem(atPath: "\(d)/vn-\(st).\(ext)") } }
            return
        }
        append(st, VoiceNoteContext.json([("event", "end"), ("time", BugNotes.iso()), ("length", x.length), ("voiced", x.voiced)]))
        io.async { VoiceNoteContext.enforceCap(dir: d, maxBytes: BugNotes.maxBytes) }
    }

    private func append(_ stamp: String, _ line: String) {
        let path = "\(dir)/vn-\(stamp).jsonl"
        io.async {
            let data = Data((line + "\n").utf8)
            if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(data); h.closeFile() }
            else { FileManager.default.createFile(atPath: path, contents: data) }
        }
    }

    static func db(_ rms: Float) -> Double { Double(20 * log10f(max(rms, 1e-5))) }

    private static let isoFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return f
    }()
    static func iso() -> String { isoFormat.string(from: Date()) }

    // MARK: Audio thread

    private func audioLoop() {
        defer { lock.lock(); threadAlive = false; lock.unlock() }
        // VOICE_COMMUNICATION (echo cancelled), else VOICE_RECOGNITION, else the default input.
        var mic: UnsafeMutableRawPointer? = bs_mic_open(BugNotes.rate, 7) ?? bs_mic_open(BugNotes.rate, 6) ?? bs_mic_open(BugNotes.rate, 1)
        guard mic != nil else { lock.lock(); failed = "couldn't open the microphone"; lock.unlock(); return }
        let rate = Int(max(8000, bs_mic_rate(mic)))
        let frame = rate / 50
        let dt = Double(frame) / Double(rate)
        let preFrames = Int((VoiceSegmenter.preroll / dt).rounded())
        var buf = [Int16](repeating: 0, count: frame)
        var pre = [[Int16]](repeating: [Int16](repeating: 0, count: frame), count: preFrames)
        var preLen = [Int](repeating: 0, count: preFrames)
        var preHead = 0, preCount = 0
        var seg = VoiceSegmenter()
        var enc: UnsafeMutableRawPointer?
        var stamp = ""
        var length = 0.0, pttTail = 0.0
        var lastMode = Mode.off
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmmss-SSS"
        print("voicenotes: listening at \(rate) Hz")

        func openNote() {
            stamp = fmt.string(from: Date())
            enc = bs_aac_open("\(dir)/vn-\(stamp).aac", Int32(rate), BugNotes.bitrate)
            length = 0
            guard let e = enc else { return }
            for k in 0..<preCount {
                let i = (preHead - preCount + k + preFrames) % preFrames
                pre[i].withUnsafeBufferPointer { _ = bs_aac_write(e, $0.baseAddress, Int32(preLen[i])) }
                length += Double(preLen[i]) / Double(rate)
            }
            preCount = 0
            lock.lock(); started.append(stamp); lock.unlock()
        }
        func closeNote(keep: Bool, voiced: Double) {
            guard let e = enc else { return }
            bs_aac_close(e)
            enc = nil
            lock.lock(); ended.append((stamp, keep, length, voiced)); lock.unlock()
        }

        while true {
            lock.lock(); let go = run, m = sharedMode, held = ptt; lock.unlock()
            if !go { break }
            lastMode = m
            let n = Int(buf.withUnsafeMutableBufferPointer { bs_mic_read(mic, $0.baseAddress, Int32(frame), 200_000_000) })
            if n < 0 {
                // Device route changed or the stream died: reopen.
                bs_mic_close(mic)
                Thread.sleep(forTimeInterval: 0.5)
                mic = bs_mic_open(BugNotes.rate, 7) ?? bs_mic_open(BugNotes.rate, 6)
                if mic == nil { break }
                continue
            }
            if n == 0 { continue }
            var sum: Float = 0
            for i in 0..<n { let v = Float(buf[i]) / 32768; sum += v * v }
            let rms = (sum / Float(n)).squareRoot()
            let fdt = Double(n) / Double(rate)
            lock.lock(); level = rms; lock.unlock()
            let ev: VoiceSegmenter.Event
            if m == .always {
                ev = seg.push(rms: rms, ref: QuestAudioOutput.level, dt: fdt)
            } else {
                // Push-to-talk: both sticks clicked; 0.3 s of tail after release.
                if held { pttTail = 0 } else if enc != nil { pttTail += fdt }
                ev = held && enc == nil ? .start : (enc != nil && pttTail >= 0.3 ? .end(keep: true) : .none)
            }
            switch ev {
            case .start: openNote()
            case .split: closeNote(keep: true, voiced: seg.voicedTime); openNote()
            case .end(let keep): closeNote(keep: keep, voiced: seg.voicedTime)
            case .none: break
            }
            if let e = enc {
                buf.withUnsafeBufferPointer { _ = bs_aac_write(e, $0.baseAddress, Int32(n)) }
                length += fdt
            } else {
                buf.withUnsafeBufferPointer { src in pre[preHead].withUnsafeMutableBufferPointer { dst in
                    for i in 0..<n { dst[i] = src[i] } } }
                preLen[preHead] = n
                preHead = (preHead + 1) % preFrames
                preCount = min(preCount + 1, preFrames)
            }
        }
        // A note cut off by pausing or turning notes off is kept if it already had enough voice.
        closeNote(keep: lastMode == .pushToTalk || seg.voicedTime >= seg.minVoiced, voiced: seg.voicedTime)
        bs_mic_close(mic)
        print("voicenotes: microphone closed")
    }

}
#endif
