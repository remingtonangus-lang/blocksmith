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
        // P456: every vessel he can drive or ride has its music: the crawler shares the frigate's, planes fly to the flight
        // theme, and boats, trucks and balloons leave the land or sea's own.
        func craft(_ role: String?, _ setup: (Ship) -> Void = { _ in }) -> String {
            let s = Ship(id: -1, grid: ShipGrid(sx: 1, sy: 1, sz: 1))
            s.role = role
            setup(s)
            return Soundtrack.vehicle(s) ?? "-"
        }
        let crafts = ["crawler": craft("crawler") { $0.wheels = [V3(0, 0, 0)] }, "carriage": craft("carriage"),
                      "capfrigate": craft("capfrigate") { $0.kinematic = true }, "frigate": craft("frigate"),
                      "ashtankb": craft("ashtankb") { $0.wheels = [V3(0, 0, 0)] }, "dropship": craft("dropship") { $0.kinematic = true },
                      "plane": craft(nil) { $0.wings = [V3(0, 0, 0)] }, "heli": craft(nil) { $0.rotors = [V3(0, 0, 0)] },
                      "sub": craft(nil) { $0.ballast = 2 }, "boat": craft(nil), "truck": craft("ashtruck") { $0.wheels = [V3(0, 0, 0)] },
                      "balloon": craft(nil) { $0.balloons = 1 }]
        let wantCraft = ["crawler": "frigate_command", "carriage": "frigate_command", "capfrigate": "frigate_command",
                         "frigate": "frigate_command", "ashtankb": "frigate_command", "dropship": "drop_ship_flight",
                         "plane": "drop_ship_flight", "heli": "helicopter", "sub": "submarine", "boat": "-", "truck": "-", "balloon": "-"]
        check(crafts == wantCraft, "musictakes: each craft's music \(crafts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
        // P474: Creative plays more than its own three takes over an hour (on the surface, nothing near).
        let surv = g.survival, clk = g.clock
        g.survival = false
        var heard = Set<String>()
        for k in 0..<60 { g.clock = Double(k) * 60; heard.insert(g.soundtrackState()) }
        g.survival = surv; g.clock = clk
        check(heard.contains("creative_mode") && heard.count >= 2, "musictakes: an hour in Creative plays \(heard.sorted())")
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
