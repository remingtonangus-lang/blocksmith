import Foundation

// `--questbugs --only voice`: the Quest voice bug notes' shared logic (Sources/VoiceNoteCore.swift). The recorder
// itself (AAudio + AAC, quest/src/android/QuestVoiceNotes.swift) runs on the headset only.
enum VoiceNoteTests {
    // Simulated 20 ms mic frames: `mic(t)` and the game's output level `ref(t)`; returns the segmenter's events.
    static func simulate(seconds: Double, mic: (Double) -> Float, ref: (Double) -> Float) -> [VoiceSegmenter.Event] {
        var seg = VoiceSegmenter()
        var out: [VoiceSegmenter.Event] = []
        var t = 0.0
        while t < seconds {
            let e = seg.push(rms: mic(t), ref: ref(t), dt: 0.02)
            if e != .none { out.append(e) }
            t += 0.02
        }
        return out
    }

    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        var rng = SplitMix(seed: 7)
        func noise(_ a: Float) -> Float { a * (0.7 + 0.6 * Float(rng.next() % 1000) / 1000) }
        // Speech: syllables ~0.18 s at -26..-20 dBFS with short gaps, the way a remark sounds to a headset mic.
        func speech(_ t: Double) -> Float {
            let ph = t.truncatingRemainder(dividingBy: 0.26)
            return ph < 0.18 ? 0.05 + 0.05 * Float(abs(sin(t * 7))) : 0.006
        }
        // Game sound: music bed with explosions every 7 s; the mic hears it at 0.35x after echo cancellation.
        func music(_ t: Double) -> Float { t.truncatingRemainder(dividingBy: 7) < 0.4 ? 0.6 : 0.12 + 0.04 * Float(sin(t)) }

        let quiet = simulate(seconds: 60, mic: { _ in noise(0.002) }, ref: { _ in 0 })
        check(quiet.isEmpty, "voice: a quiet room for 60 s opens no note (\(quiet.count) events)")

        let loud = simulate(seconds: 120, mic: { t in 0.35 * music(t) + noise(0.002) }, ref: music)
        check(loud.filter { $0 == .start }.isEmpty, "voice: 120 s of music and explosions without talking opens no note (\(loud.count) events)")

        // Talk for 4 s at t=20 while the game plays.
        var seg = VoiceSegmenter()
        var events: [(Double, VoiceSegmenter.Event)] = []
        var t = 0.0, noteLength = 0.0
        while t < 40 {
            let talking = t >= 20 && t < 24
            let m = 0.35 * music(t) + noise(0.002) + (talking ? speech(t) : 0)
            let e = seg.push(rms: m, ref: music(t), dt: 0.02)
            if e != .none { events.append((t, e)) }
            if case .end = e { noteLength = seg.segmentTime }
            t += 0.02
        }
        let starts = events.filter { $0.1 == .start }
        let kept = events.contains { $0.1 == .end(keep: true) }
        let startAt = starts.first?.0 ?? -1
        check(starts.count == 1 && kept && startAt >= 20 && startAt < 20.25,
              String(format: "voice: 4 s of speech over game sound makes one kept note, opened %.2f s in (%d starts)", startAt - 20, starts.count))
        check(noteLength >= 4.5 && noteLength <= 6,
              String(format: "voice: the note runs speech + 1 s padding (%.1f s; with 0.5 s pre-roll in the file)", noteLength))

        let cough = simulate(seconds: 10, mic: { t in t >= 5 && t < 5.2 ? 0.2 : noise(0.002) }, ref: { _ in 0 })
        check(!cough.contains(.end(keep: true)), "voice: a 0.2 s cough is not kept (\(cough))")

        let long = simulate(seconds: 140, mic: { t in t >= 5 && t < 135 ? speech(t) : noise(0.002) }, ref: { _ in 0 })
        check(long.filter { $0 == .split }.count == 2 && long.last == .end(keep: true),
              "voice: 130 s of talk is split into 60 s files (\(long.filter { $0 == .split }.count) splits)")

        // Storage cap: oldest files go first.
        let dir = NSTemporaryDirectory() + "voicecap-\(getpid())"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for (i, n) in ["vn-20261009-100000-000", "vn-20261009-110000-000", "vn-20261009-120000-000"].enumerated() {
            FileManager.default.createFile(atPath: "\(dir)/\(n).aac", contents: Data(count: 400 + i))
        }
        let deleted = VoiceNoteContext.enforceCap(dir: dir, maxBytes: 1000)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: dir).sorted()) ?? []
        check(deleted == 1 && left.first == "vn-20261009-110000-000.aac", "voice: the 2 GB cap deletes the oldest recording first (\(left))")

        // Sidecar: game state with the fields a note needs, valid JSON.
        let ctx = VoiceNoteContext.describe(game, build: "test", fps: 72)
        let keys = Set(ctx.map { $0.0 })
        let need: Set = ["build", "dimension", "position", "facing", "biome", "held", "mount", "fps", "looking at"]
        check(need.isSubset(of: keys), "voice: the sidecar has \(need.subtracting(keys).isEmpty ? "every context field" : "missing \(need.subtracting(keys))")")
        let line = VoiceNoteContext.json([("event", "start"), ("length", 4.5), ("context", ctx), ("events", ["took 3 damage", "quote \" and \\ back"])])
        let parsed = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        check((parsed?["context"] as? [String: String])?["fps"] == "72" && (parsed?["events"] as? [String])?.count == 2,
              "voice: sidecar lines are valid JSON")

        // Recent events come from state changes.
        let ev = VoiceEvents()
        let hp = game.health
        ev.observe(game)
        game.health = max(1, hp - 3)
        for _ in 0..<30 { game.tick(0.05); ev.observe(game) }
        let recent = ev.recent(game)
        game.health = hp
        check(recent.contains { $0.contains("took 3 damage") }, "voice: recent events record damage (\(recent))")
    }
}

// Small deterministic generator for the simulated noise.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
