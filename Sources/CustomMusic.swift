import Foundation
import AVFoundation

// Your own music (Options > Audio > Soundtrack): audio files in ~/Library/Application Support/Blocksmith/Music play
// instead of the built-in composer (My Music) or take turns with it (Mixed). Nothing ships in the repository: the
// folder is the player's own, on their Mac. Shuffle, a volume of its own on top of Music, and Skip Track (Y on the
// pause menu, the Skip Music Track key, or Options > Audio).
final class CustomMusic {
    static let extensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf"]
    static var folderOverride: URL?             // --musiccheck's temporary folder
    static var folder: URL {
        folderOverride ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Blocksmith/Music", isDirectory: true)
    }

    let node = AVAudioPlayerNode()
    private unowned let engine: AVAudioEngine
    private(set) var files: [URL] = []
    private var scannedAt: Double = -1000
    private var order: [Int] = []
    private var next = 0
    private var shuffled = false                // the order was built shuffled (a change starts a new round)
    private var generation = 0                // a skipped or stopped track's completion is ignored
    private(set) var playing = false
    private(set) var title: String?
    var volume: Float = 1 { didSet { if abs(volume - oldValue) > 0.001 { node.volume = volume } } }

    init(engine: AVAudioEngine, format: AVAudioFormat) {
        self.engine = engine
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    // The folder's audio files, sorted by name (rescanned at most every 20 s; the folder is made if missing, so it is
    // there to find).
    func scan(force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        guard force || now - scannedAt > 20 else { return }
        scannedAt = now
        let fm = FileManager.default
        let dir = CustomMusic.folder
        if !fm.fileExists(atPath: dir.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        let found = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let list = found.filter { CustomMusic.extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if list != files { files = list; order = []; next = 0 }
    }

    var available: Bool { scan(); return !files.isEmpty }

    // Starts the next track (shuffled or in name order). False when there is nothing playable.
    @discardableResult
    func playNext(shuffle: Bool) -> Bool {
        scan()
        guard !files.isEmpty else { return false }
        for _ in 0..<files.count {
            if next >= order.count || shuffle != shuffled {
                order = shuffle ? Array(files.indices).shuffledRand() : Array(files.indices)
                next = 0
                shuffled = shuffle
            }
            let url = files[order[next]]
            next += 1
            guard let f = try? AVAudioFile(forReading: url) else { continue }      // unreadable: try the next one
            stop()
            generation += 1
            let gen = generation
            // Each file brings its own sample rate and channel count: reconnect the player for it.
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: f.processingFormat)
            node.volume = volume
            node.scheduleFile(f, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let s = self, s.generation == gen else { return }
                    s.playing = false
                }
            }
            if engine.isRunning { node.play() }
            playing = true
            title = url.deletingPathExtension().lastPathComponent
            return true
        }
        return false
    }

    func stop() {
        generation += 1
        if playing || node.isPlaying { node.stop() }
        playing = false
    }

    // The output device changed (the engine restarted): the scheduled file is gone, so the next track starts soon.
    func restart() { stop() }

    // The folder's state for the options page.
    var summary: String {
        scan()
        return files.isEmpty ? "folder empty" : "\(files.count) track\(files.count == 1 ? "" : "s")"
    }
}

// --musiccheck: a temporary folder with three short generated tones and a text file. The folder lists the three in
// name order, shuffle plays each once per round, an unreadable file is skipped, and the soundtrack director plays the
// folder in My Music mode and moves on with Skip Track. (No music in the repository: the tones are made here.)
enum MusicCheck {
    static func run(_ g: Game) -> Int {
        var fails = 0
        func check(_ ok: Bool, _ what: String) {
            print("musiccheck: \(ok ? "PASS" : "FAIL") \(what)")
            if !ok { fails += 1 }
        }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("blocksmith-music-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir); CustomMusic.folderOverride = nil }
        // Three half-second tones (44.1 kHz stereo WAV) and two files that are not music.
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        for (i, name) in ["b tone.wav", "a tone.wav", "c tone.wav"].enumerated() {
            guard let f = try? AVAudioFile(forWriting: dir.appendingPathComponent(name), settings: fmt.settings),
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 22050) else { check(false, "writing \(name)"); continue }
            buf.frameLength = 22050
            let hz = Float(330 + 110 * i)
            for c in 0..<2 { for n in 0..<22050 { buf.floatChannelData![c][n] = 0.1 * sinf(Float(n) / 44100 * hz * 2 * .pi) } }
            try? f.write(from: buf)
        }
        try? "not music".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try? "garbage".write(to: dir.appendingPathComponent("broken.mp3"), atomically: true, encoding: .utf8)
        CustomMusic.folderOverride = dir
        let engine = AVAudioEngine()
        let cm = CustomMusic(engine: engine, format: fmt)
        cm.scan(force: true)
        let names = cm.files.map { $0.lastPathComponent }
        check(names == ["a tone.wav", "b tone.wav", "broken.mp3", "c tone.wav"], "the folder lists its audio files in name order, not the text file (\(names))")
        // In order: a, b, (broken skipped), c, then a again.
        var seen: [String] = []
        for _ in 0..<4 { if cm.playNext(shuffle: false) { seen.append(cm.title ?? "?") } }
        check(seen == ["a tone", "b tone", "c tone", "a tone"], "in name order an unreadable file is skipped (\(seen))")
        cm.stop()
        check(!cm.playing, "stop ends the track")
        // Shuffled: each playable track once in a round of four picks (the broken one is passed over).
        var round = Set<String>()
        var picks = 0
        while picks < 3 { if cm.playNext(shuffle: true) { round.insert(cm.title ?? "?") }; picks += 1 }
        check(round.count == 3, "shuffle plays every track once a round (\(round.sorted()))")
        cm.stop()
        // The director: My Music plays the folder; Skip Track moves on.
        if let snd = g.sound, let custom = snd.custom {
            let st = Settings.shared
            let keepSrc = st.musicSource
            st.musicSource = 1
            custom.scan(force: true)
            g.music.wait = 0; g.music.silence = 0; g.music.customOn = false; g.music.mood = nil
            snd.music?.stop(fade: 0.01)
            g.musicTick(0.05)
            check(g.music.customOn && custom.playing, "My Music: the director plays a track from the folder (\(custom.title ?? "none"))")
            let first = custom.title
            g.skipMusicTrack()
            for _ in 0..<40 { g.musicTick(0.05) }
            check(custom.playing && custom.title != nil, "Skip Track starts another (\(first ?? "-") then \(custom.title ?? "none"))")
            custom.stop(); g.music.customOn = false
            st.musicSource = keepSrc
        } else {
            print("musiccheck: no audio output here; the director part is skipped")
        }
        print("musiccheck: \(fails == 0 ? "PASS" : "\(fails) FAILED")")
        return fails
    }
}

