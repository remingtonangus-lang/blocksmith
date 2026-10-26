import Foundation

// P457's check (questcheck --musictakes): every Sunderfall track file plays for a state, the busy states have about
// seven takes, a state's takes come round without repeating soon, every take has its loudness gain, and the director
// plays another take of the same state when one ends.
enum MusicTakesCheck {
    final class FakeDeck: TrackDeck {
        let names: Set<String>
        var playing: String?
        var played: [String] = []
        init(_ n: Set<String>) { names = n }
        var available: Bool { true }
        var current: String? { playing }
        var volume: Float = 1
        func play(_ name: String, gain: Float, fade: Float) { if names.contains(name) { playing = name; played.append(name) } }
        func stop(fade: Float) { playing = nil }
        func update(_ dt: Float) {}
    }

    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let dir = FileManager.default.currentDirectoryPath + "/Resources/Music/sunderfall"
        let files = Set(((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".m4a") }.map { String($0.dropLast(4)) })
        let stray = files.filter { !Soundtrack.tracks.contains(Soundtrack.state(of: $0)) }.sorted()
        check(files.count >= 100 && stray.isEmpty, "musictakes: \(files.count) track files, each plays for a state (not: \(stray))")
        let busy = ["overworld_daytime", "overworld_night", "caves", "village", "combat"].map { ($0, Soundtrack.takes($0, in: files).count) }
        check(busy.allSatisfy { $0.1 >= 7 }, "musictakes: the busy states have seven takes or more \(busy)")
        let deck = FakeDeck(files)
        let d = SoundtrackDirector()
        let caves = (0..<20).map { _ in d.nextTake("caves", deck) }
        let soon = (0..<16).allSatisfy { i in Set(caves[i..<(i + 5)]).count == 5 }
        check(soon && Set(caves).count >= 8, "musictakes: caves' takes come round without one again within five plays (\(Set(caves).count) of 9 in 20): \(caves.prefix(6).joined(separator: " "))")
        let noGain = files.filter { SoundtrackGains.table[$0] == nil }.sorted()
        check(noGain.isEmpty, "musictakes: every take has its loudness gain (missing \(noGain.count): \(noGain.prefix(4)))")
        // The director with the game: a track plays; when it ends, after its quiet another take of the same state.
        let had = AudioSettings.volume(.music)
        if had <= 0 { AudioSettings.set(.music, 1) }
        for _ in 0..<400 { g.soundtrackTick(0.05, deck) }
        let first = deck.played.last
        deck.playing = nil
        for _ in 0..<2400 { g.soundtrackTick(0.05, deck) }
        let second = deck.played.last
        if had <= 0 { AudioSettings.set(.music, had) }
        let same = first.map(Soundtrack.state(of:)) == second.map(Soundtrack.state(of:))
        check(first != nil && deck.played.count >= 2 && same && first != second,
              "musictakes: \(first ?? "nothing") played, ended, then \(second ?? "nothing") (\(deck.played.count) starts)")
    }
}
