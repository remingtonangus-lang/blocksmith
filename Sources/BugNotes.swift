import Foundation
import AVFoundation
import Speech
import simd

// Voice bug notes (Options > Interface > Bug Notes): say a bug out loud while playing and it lands in
// ~/Documents/Blocksmith/BugNotes/bug-notes.md with the game state, a screenshot taken when you started talking
// and the audio as .m4a. Modes: always listening (voice-activity detection splits notes) or push-to-talk
// (F7, or click both sticks L3 + R3). Transcription is on-device only (Speech framework, en-US); if this Mac
// can't recognise on-device the note is still saved with its audio. The game is never paused.
// Game audio: the mic runs on its own AVAudioEngine (the game's engine is untouched) with an adaptive level
// threshold, so steady game sound raises the noise floor instead of opening notes.
// See BUGNOTES.md for how a session turns the file into fixes; `--bugnotetest` checks the pipeline in CI.
final class BugNotes {
    static let shared = BugNotes()
    enum Mode: Int { case off = 0, always = 1, pushToTalk = 2 }
    static let names = ["Off", "Always Listening", "Push-to-Talk"]
    static let pttKey: UInt16 = 98                  // F7

    static var dir: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Blocksmith/BugNotes", isDirectory: true)
    static var mdURL: URL { dir.appendingPathComponent("bug-notes.md") }

    var forcedMode: Mode?                           // harness
    var mode: Mode { forcedMode ?? Mode(rawValue: Settings.shared.bugNotes) ?? .off }

    weak var game: Game?
    private var engine: AVAudioEngine?
    private(set) var listening = false              // mic running
    private(set) var recording = false              // inside a note
    private(set) var level: Float = 0               // last input RMS (HUD dot)
    private(set) var saved = 0                      // entries written this run
    private var preroll: [AVAudioPCMBuffer] = []
    private var note: [AVAudioPCMBuffer] = []
    private var aboveTime = 0.0, voicedTime = 0.0, silentTime = 0.0, noteTime = 0.0, tailTime = 0.0
    private var noiseFloor: Float = 0.004
    private var pttHeld = false
    private var endRequested = false
    private var context: [(String, String)] = []
    private var stamp = ""
    private var tasks: [Int: (SFSpeechRecognizer, SFSpeechRecognitionTask)] = [:]
    private var nextTask = 0

    var screenshotRequest: URL?                     // the renderer saves the next frame here
    var captureScreenshot: ((URL) -> Void)?         // harness: render directly
    var transcriber: (([AVAudioPCMBuffer], @escaping (String?) -> Void) -> Void)?   // harness stub
    var frameTime: Double = 0                       // seconds per frame (renderer)

    // MARK: Permissions

    static var micDenied: Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .audio)
        return s == .denied || s == .restricted
    }
    static var speechDenied: Bool {
        let s = SFSpeechRecognizer.authorizationStatus()
        return s == .denied || s == .restricted
    }
    static var denied: Bool { micDenied || speechDenied }
    static var authorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    static func requestPermission(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { mic in
            SFSpeechRecognizer.requestAuthorization { sp in
                DispatchQueue.main.async { done(mic && sp == .authorized) }
            }
        }
    }

    // MARK: Per frame (HudExtras.tick)

    func tick(_ g: Game) {
        game = g
        let want = mode != .off && HudExtras.enabled && BugNotes.authorized
        if want && engine == nil { start() } else if !want && engine != nil { stop() }
        guard listening, mode == .pushToTalk else { return }
        let raw = PadManager.shared.lastRaw
        let held = g.input.down(BugNotes.pttKey) || (raw.l3 && raw.r3)
        if held && !pttHeld && !recording { begin() }
        if !held && pttHeld && recording { endRequested = true; tailTime = 0 }
        pttHeld = held
    }

    private func start() {
        let e = AVAudioEngine()
        let input = e.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { game?.onToast?("Bug Notes: no microphone found"); Settings.shared.bugNotes = 0; return }
        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, _ in
            guard let mono = BugNotes.mono(buf) else { return }
            let r = BugNotes.rms(mono)
            DispatchQueue.main.async { self?.feed(mono, rms: r) }
        }
        do { try e.start() } catch {
            input.removeTap(onBus: 0)
            game?.onToast?("Bug Notes: couldn't start the microphone")
            return
        }
        engine = e
        listening = true
    }

    private func stop() {
        if recording { end() }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        listening = false
        preroll.removeAll()
    }

    // MARK: Segmentation

    // One mono buffer from the mic (or the harness), on the main thread.
    func feed(_ buf: AVAudioPCMBuffer, rms: Float) {
        let dur = Double(buf.frameLength) / buf.format.sampleRate
        level = rms
        let threshold = max(0.015, noiseFloor * 3.5)
        if !recording {
            preroll.append(buf)
            var kept = 0.0
            var i = preroll.count
            while i > 0 && kept < 0.45 { i -= 1; kept += Double(preroll[i].frameLength) / preroll[i].format.sampleRate }
            if i > 0 { preroll.removeFirst(i) }
            guard mode == .always else { return }
            if rms > threshold { aboveTime += dur } else {
                aboveTime = 0
                noiseFloor = noiseFloor * 0.97 + rms * 0.03      // game audio and room noise raise the floor
            }
            if aboveTime >= 0.2 { begin() }
            return
        }
        note.append(buf)
        noteTime += dur
        if rms > threshold * 0.7 { voicedTime += dur; silentTime = 0 } else { silentTime += dur }
        if mode == .always && (silentTime >= 1.2 || noteTime > 45) { end() }
        if mode == .pushToTalk && endRequested { tailTime += dur; if tailTime >= 0.25 || noteTime > 90 { end() } }
    }

    private func begin() {
        recording = true
        endRequested = false
        note = preroll
        preroll.removeAll()
        noteTime = note.reduce(0) { $0 + Double($1.frameLength) / $1.format.sampleRate }
        voicedTime = 0; silentTime = 0; aboveTime = 0
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        stamp = f.string(from: Date())
        context = game.map { BugNotes.describe($0, frameTime: frameTime) } ?? []
        try? FileManager.default.createDirectory(at: BugNotes.dir, withIntermediateDirectories: true)
        let shot = BugNotes.dir.appendingPathComponent("note-\(stamp).png")
        if let c = captureScreenshot { c(shot) } else { screenshotRequest = shot }
    }

    private func end() {
        recording = false
        let bufs = note, ctx = context, st = stamp
        note.removeAll()
        let shot = BugNotes.dir.appendingPathComponent("note-\(st).png")
        // Too little voice in always-listening mode: a cough or a game noise, not a note.
        if mode == .always && voicedTime < 0.35 { try? FileManager.default.removeItem(at: shot); return }
        let audio = BugNotes.dir.appendingPathComponent("note-\(st).m4a")
        let wroteAudio = BugNotes.writeM4A(bufs, to: audio)
        transcribe(bufs) { [weak self] text in
            guard let self else { return }
            BugNotes.append(stamp: st, transcript: text, context: ctx,
                            screenshot: FileManager.default.fileExists(atPath: shot.path) || self.screenshotRequest == shot ? shot.lastPathComponent : nil,
                            audio: wroteAudio ? audio.lastPathComponent : nil)
            self.saved += 1
            self.game?.onToast?("Note saved")
        }
    }

    // MARK: Transcription (on-device only)

    private func transcribe(_ bufs: [AVAudioPCMBuffer], _ done: @escaping (String?) -> Void) {
        if let stub = transcriber { stub(bufs) { t in DispatchQueue.main.async { done(t) } }; return }
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), rec.isAvailable, rec.supportsOnDeviceRecognition else {
            done(nil); return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = false
        req.addsPunctuation = true
        for b in bufs { req.append(b) }
        req.endAudio()
        let id = nextTask
        nextTask += 1
        var finished = false
        let finish: (String?) -> Void = { [weak self] t in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                self?.tasks[id] = nil
                done(t)
            }
        }
        let task = rec.recognitionTask(with: req) { result, error in
            if let r = result, r.isFinal { finish(r.bestTranscription.formattedString) }
            else if error != nil { finish(nil) }
        }
        tasks[id] = (rec, task)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { finish(nil) }
    }

    // MARK: Entry

    static var build: String { Bundle.main.infoDictionary?["BlocksmithCommit"] as? String ?? "unknown" }

    // Game state for the entry, captured when the note starts.
    static func describe(_ g: Game, frameTime: Double) -> [(String, String)] {
        let p = g.player
        let bx = Int(floor(p.pos.x)), by = Int(floor(p.pos.y)), bz = Int(floor(p.pos.z))
        var yawDeg = Double(-p.yaw * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if yawDeg < 0 { yawDeg += 360 }
        let dirs = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        let facing = dirs[Int((yawDeg + 22.5) / 45) % 8]
        let world = g.save?.dir.lastPathComponent ?? "(test world)"
        let biome = g.world.gen.column(bx, bz).biome.displayName
        var target = "nothing"
        if let t = g.target {
            let b = g.world.block(t.hit.x, t.hit.y, t.hit.z)
            target = "\(Blocks.name(b)) at \(t.hit.x) \(t.hit.y - YOFF) \(t.hit.z)"
        }
        let frac = g.dayFraction
        let hour = (frac * 24 + 6).truncatingRemainder(dividingBy: 24)
        let clock = String(format: "%02d:%02d", Int(hour), Int(hour * 60) % 60)
        let weather = g.weather.thundering ? "thunderstorm" : (g.weather.raining ? "rain" : "clear")
        let ms = frameTime * 1000
        let pads = PadManager.shared
        return [
            ("Build", build),
            ("World", "\(world) (seed \(g.world.seed))"),
            ("Dimension", "\(g.dim.dim)"),
            ("Position", String(format: "x %.1f, y %.1f, z %.1f (block %ld %ld %ld)", p.pos.x, p.pos.y - Float(YOFF), p.pos.z, bx, by - YOFF, bz)
                + String(format: ", facing %@ (yaw %.0f°, pitch %.0f°)", facing, yawDeg, Double(p.pitch * 180 / .pi))),
            ("Biome", biome),
            ("Looking at", target),
            ("Mode", "\(g.survival ? "Survival" : "Creative"), \(Game.difficultyNames[g.difficulty])\(p.flying ? ", flying" : "")\(g.menu.map { ", screen open: \(type(of: $0))" } ?? "")"),
            ("Time / weather", "day \(Int(g.time / DAY_LENGTH) + 1), \(clock), \(weather)"),
            ("Frame time", ms > 0 ? String(format: "%.1f ms (%.0f fps)", ms, 1000 / ms) : "n/a"),
            ("Input", pads.connected ? "\(pads.name), last used \(pads.usingPad ? "controller" : "keyboard/mouse")" : "keyboard/mouse"),
        ]
    }

    static func append(stamp: String, transcript: String?, context: [(String, String)], screenshot: String?, audio: String?) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shown = text.isEmpty ? "(no transcript - listen to the audio)" : text
        let when = stamp.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: ":")
        var s = "\n## \(when) - \(text.isEmpty ? "untranscribed note" : String(text.prefix(60)))\n\n"
        s += "- **Transcript:** \(shown)\n"
        s += "- **Status:** open\n"
        for (k, v) in context { s += "- **\(k):** \(v)\n" }
        if let sh = screenshot { s += "- **Screenshot:** ![screenshot](\(sh))\n" }
        if let a = audio { s += "- **Audio:** [\(a)](\(a))\n" }
        if !fm.fileExists(atPath: mdURL.path) {
            let head = "# Blocksmith bug notes\n\nSpoken while playing (Options > Interface > Bug Notes). Newest at the bottom.\n"
                + "Each entry: transcript, game state, screenshot and audio. Set Status to fixed (with the commit) once handled;\n"
                + "see BUGNOTES.md in the repo.\n"
            try? head.write(to: mdURL, atomically: true, encoding: .utf8)
        }
        if let h = try? FileHandle(forWritingTo: mdURL) {
            h.seekToEndOfFile()
            h.write(s.data(using: .utf8) ?? Data())
            try? h.close()
        }
    }

    // MARK: Audio helpers

    static func mono(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let src = b.floatChannelData, let fmt = AVAudioFormat(standardFormatWithSampleRate: b.format.sampleRate, channels: 1),
              let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: b.frameLength), let dst = out.floatChannelData else { return nil }
        let n = Int(b.frameLength), ch = Int(b.format.channelCount)
        let k = 1 / Float(max(1, ch))
        for i in 0..<n {
            var v: Float = 0
            for c in 0..<ch { v += src[c][i] }
            dst[0][i] = v * k
        }
        out.frameLength = b.frameLength
        return out
    }

    static func rms(_ b: AVAudioPCMBuffer) -> Float {
        guard let d = b.floatChannelData, b.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(b.frameLength) { sum += d[0][i] * d[0][i] }
        return sqrtf(sum / Float(b.frameLength))
    }

    static func writeM4A(_ bufs: [AVAudioPCMBuffer], to url: URL) -> Bool {
        guard let f = bufs.first?.format else { return false }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: f.sampleRate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            for b in bufs { try file.write(from: b) }
        } catch { return false }
        return true
    }

    // MARK: Harness (--bugnotetest)

    // Feeds a synthesized "voice" (harmonics with a syllable rhythm between quiet noise) through the same
    // segmentation, audio, screenshot and markdown path with a stub transcriber, then checks the entry.
    static func selfTest(_ g: Game, screenshot: @escaping (URL) -> Void) {
        let fm = FileManager.default
        let old = dir
        let tmp = fm.temporaryDirectory.appendingPathComponent("blocksmith-bugnotes-\(getpid())", isDirectory: true)
        try? fm.removeItem(at: tmp)
        dir = tmp
        let bn = BugNotes.shared
        bn.game = g
        bn.forcedMode = .always
        bn.captureScreenshot = screenshot
        bn.transcriber = { bufs, done in done("the zombie walked through the fence (\(bufs.count) buffers)") }
        defer { dir = old; bn.forcedMode = nil; bn.captureScreenshot = nil; bn.transcriber = nil; try? fm.removeItem(at: tmp) }

        let rate = 16000.0, chunk = 1600
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { PadTest.check(false, "bug notes: audio format"); return }
        var t = 0
        func segment(_ seconds: Double, voice: Bool) {
            let total = Int(seconds * rate)
            var done = 0
            while done < total {
                let n = min(chunk, total - done)
                guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)), let d = b.floatChannelData else { return }
                for i in 0..<n {
                    let x = Double(t + i) / rate
                    var v = Float.random(in: -0.002...0.002)
                    if voice {
                        let w: Double = 2 * Double.pi * x
                        let env: Double = 0.55 + 0.45 * sin(w * 4)               // syllables
                        let h1: Double = 0.16 * sin(w * 180)
                        let h2: Double = 0.08 * sin(w * 360)
                        let h3: Double = 0.04 * sin(w * 540)
                        v += Float(env * (h1 + h2 + h3))
                    }
                    d[0][i] = v
                }
                b.frameLength = AVAudioFrameCount(n)
                t += n
                done += n
                bn.feed(b, rms: rms(b))
            }
        }
        let before = bn.saved
        segment(0.8, voice: false)
        segment(0.12, voice: true)            // a click: too short to open a note
        segment(0.8, voice: false)
        segment(1.8, voice: true)
        segment(1.8, voice: false)
        let deadline = Date().addingTimeInterval(10)
        while bn.saved == before && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

        let md = (try? String(contentsOf: mdURL, encoding: .utf8)) ?? ""
        let entries = md.components(separatedBy: "\n## ").count - 1
        PadTest.check(bn.saved - before == 1 && entries == 1, "bug notes: one spoken note -> one entry (got \(entries))")
        PadTest.check(md.contains("**Transcript:** the zombie walked through the fence"), "bug notes: transcript in the entry")
        for k in ["Build", "World", "Dimension", "Position", "Biome", "Looking at", "Mode", "Time / weather", "Frame time", "Screenshot", "Audio"] {
            PadTest.check(md.contains("- **\(k):**"), "bug notes: entry has \(k)")
        }
        let files = (try? fm.contentsOfDirectory(atPath: tmp.path)) ?? []
        let m4a = files.first { $0.hasSuffix(".m4a") }
        let size = m4a.flatMap { (try? fm.attributesOfItem(atPath: tmp.appendingPathComponent($0).path))?[.size] as? Int } ?? 0
        PadTest.check(size > 1000, "bug notes: audio saved as .m4a (\(size) bytes)")
        PadTest.check(files.contains { $0.hasSuffix(".png") }, "bug notes: screenshot saved")
        print("bug notes entry:\n" + md)
    }
}
