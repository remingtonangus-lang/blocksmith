import Foundation
import simd

// P399: docs/status/device-checklist.md as a pause-menu page, so Remington can work through it in the headset.
// Playtest builds only (a tester tool, not player-facing: removed with this file when the release candidate is cut).
// The list is read from the .md at startup (the APK bundles a copy as assets/device-checklist.md, the Mac app as a
// resource, the host reads the repo), so editing the .md changes the page with no code change. Ticks are saved to
// checklist.json next to the bug notes, and every change appends a line to the checklist log there.
enum Playtest {
    // The store APK (STORE=1 build-apk.sh) leaves out PLAYTEST; playtest APKs, the Mac and the host keep it on.
    #if QUEST && !PLAYTEST
    static let enabled = false
    #else
    static let enabled = true
    #endif
}

enum PlaytestChecklist {
    struct Item {
        let section: Int
        let text: String
        let tags: String            // its P-numbers (or its section's), for the voice note
        let places: [String]        // Go targets (keys of `placeNames`)
    }
    private(set) static var sections: [String] = []
    private(set) static var items: [Item] = []
    private(set) static var ticked: Set<String> = []        // keyed by the item's text (survives reordering)
    private static var loaded = false
    // Where checklist.json and the log go: the Mac's bug-notes folder; the headset sets its voice-notes folder.
    static var dir: URL?
    // The headset's SpaceWarp setting (QuestSettings.spaceWarp, applies at the next launch); nil hides the row.
    static var spaceWarp: (get: () -> String, toggle: () -> Void)?
    // Starts a voice note now (the headset: a push-to-talk window); the note carries `noteTag` either way.
    static var startNote: (() -> Void)?
    private static var tag: (text: String, until: Double)?

    // The Go targets an item can name, found by words in its text.
    static let placeNames: [(key: String, name: String, words: [String])] = [
        ("gulch", "Stone Gulch", ["stone gulch"]),
        ("capital_city", "Capital City", ["capital city"]),
        ("military_base", "Capital Base", ["at the base", "capital base"]),
        ("monument", "Sunken Dreadnought", ["sunken dreadnought"]),
        ("frigate", "Frigate", ["frigate"]),
        ("village", "Village with Rail", ["railway", "rails ", "ride a train"]),
        ("ashvault", "Ash Vault", ["ash vault"]),
        ("hell", "Hell", ["hell made", "emberdeep"]),
    ]

    // MARK: Reading the list

    static func load(text: String) {
        (sections, items) = parse(text)
        loaded = true
        loadTicks()
    }

    static func loadIfNeeded() {
        guard !loaded else { return }
        var text: String?
        #if os(macOS)
        if let u = Bundle.main.url(forResource: "device-checklist", withExtension: "md") { text = try? String(contentsOf: u, encoding: .utf8) }
        if dir == nil { dir = BugNotes.dir }
        #endif
        if text == nil { text = try? String(contentsOfFile: "docs/status/device-checklist.md", encoding: .utf8) }
        load(text: text ?? "")
    }

    static func parse(_ text: String) -> ([String], [Item]) {
        var secs: [String] = [], out: [Item] = []
        var secTags = ""
        var cur: (text: String, sec: Int)?
        func flush() {
            guard let c = cur else { return }
            let t = c.text.trimmingCharacters(in: .whitespaces)
            let own = pNumbers(t)
            let low = t.lowercased()
            let places = placeNames.filter { p in p.words.contains { low.contains($0) } }.map { $0.key }
            out.append(Item(section: c.sec, text: t, tags: own.isEmpty ? secTags : own, places: places))
            cur = nil
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.hasPrefix("## ") {
                flush()
                let h = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                secs.append(h)
                secTags = pNumbers(h)
            } else if line.hasPrefix("- ") && !secs.isEmpty {
                flush()
                cur = (String(line.dropFirst(2)), secs.count - 1)
            } else if line.hasPrefix("  ") && cur != nil && !line.trimmingCharacters(in: .whitespaces).isEmpty {
                cur!.text += " " + line.trimmingCharacters(in: .whitespaces)
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            }
        }
        flush()
        return (secs, out)
    }

    static func pNumbers(_ s: String) -> String {
        var found: [String] = []
        let ch = Array(s)
        var i = 0
        while i < ch.count {
            if ch[i] == "P", i + 1 < ch.count, ch[i + 1].isNumber, i == 0 || !(ch[i - 1].isLetter || ch[i - 1].isNumber) {
                var j = i + 1
                while j < ch.count && ch[j].isNumber { j += 1 }
                let p = String(ch[i..<j])
                if !found.contains(p) { found.append(p) }
                i = j
            } else { i += 1 }
        }
        return found.joined(separator: ", ")
    }

    // MARK: Ticks

    private static var ticksURL: URL? { dir?.appendingPathComponent("vn-checklist.json") }
    private static var logURL: URL? { dir?.appendingPathComponent("vn-checklist-log.md") }

    static func isTicked(_ i: Int) -> Bool { i >= 0 && i < items.count && ticked.contains(items[i].text) }

    static func toggle(_ i: Int) {
        guard i >= 0 && i < items.count else { return }
        let t = items[i].text
        let now = !ticked.contains(t)
        if now { ticked.insert(t) } else { ticked.remove(t) }
        saveTicks()
        log("\(now ? "ticked" : "unticked"): \(items[i].tags.isEmpty ? "" : "[\(items[i].tags)] ")\(t)")
    }

    static func count(section s: Int) -> (done: Int, all: Int) {
        let its = items.filter { $0.section == s }
        return (its.filter { ticked.contains($0.text) }.count, its.count)
    }

    private static func loadTicks() {
        guard let u = ticksURL, let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let t = o["ticked"] as? [String] else { ticked = []; return }
        ticked = Set(t)
    }

    private static func saveTicks() {
        guard let u = ticksURL else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let o: [String: Any] = ["ticked": ticked.sorted(), "updated": stamp()]
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted]) { try? d.write(to: u, options: .atomic) }
    }

    // Forget the in-memory state (the harness checks a relaunch).
    static func reload() { loaded = false; sections = []; items = []; ticked = []; loadIfNeeded() }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    // One line per change in the checklist log; the Mac also gets it in bug-notes.md, which the lane reads.
    private static func log(_ what: String) {
        let line = "- \(stamp()) checklist \(what)\n"
        var files = [logURL].compactMap { $0 }
        #if os(macOS)
        files.append(BugNotes.mdURL)
        #endif
        for u in files {
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: u) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? line.write(to: u, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: Voice notes and Go

    // A voice note about item i: its P-numbers (and text) ride on the notes started in the next 60 s.
    static func note(_ i: Int, clock: Double) {
        guard i >= 0 && i < items.count else { return }
        let it = items[i]
        tag = ((it.tags.isEmpty ? "" : it.tags + ": ") + String(it.text.prefix(80)), clock + 60)
        startNote?()
    }

    static func noteTag(clock: Double) -> String? {
        guard let t = tag, clock < t.until else { return nil }
        return t.text
    }

    // P399 (5): the places reuse the Shortcuts teleport; Stone Gulch is the perf scene's spot (its seed's world),
    // the Ash Vault and hell hop into the Deep.
    static func go(_ key: String, _ g: Game) {
        switch key {
        case "gulch":
            if g.dim.dim != .overworld { g.changeDimension(to: .overworld, at: g.spawnPoint) }
            g.player.pos = g.settleSpawn(V3(6094.4, Float(g.world.gen.column(6094, 688).0 + 2), 688.6))
            g.player.vel = .zero
            g.player.airPeak = g.player.pos.y
            g.onToast?(g.world.seed == 13480747113613945685 ? "Stone Gulch" : "Stone Gulch's spot (the scene is on seed 13480747113613945685)")
        case "ashvault":
            let s = AshWar.sites.first { $0.kind == "staging" } ?? AshWar.sites[0]
            g.changeDimension(to: .deep, at: V3(Float(s.x) + 0.5, Float(AshWar.ground + 1), Float(s.z) + 0.5))
            g.player.pos = g.settleSpawn(g.player.pos)
        case "hell":
            g.changeDimension(to: .deep, at: V3(0.5, Float(DeepGen.hellBase + 60), 0.5), syncRadius: 2)
        default:
            if g.dim.dim != .overworld { g.changeDimension(to: .overworld, at: g.spawnPoint) }
            g.shortcutTeleport(key)
        }
    }

    // MARK: The page

    static let viewSteps = [8, 16, 24]

    static func rows(_ g: Game, width: Int) -> (subtitle: String, rows: [(String, String)]) {
        loadIfNeeded()
        var r: [(String, String)] = []
        let vd = g.world.renderDistance
        r.append(("View Distance (test): \(vd)", "cl_view"))
        if let sw = spaceWarp { r.append(("Space Warp: \(sw.get())", "cl_sw")) }
        let room = width - 24
        for (s, name) in sections.enumerated() {
            let c = count(section: s)
            r.append((fit("\(name)  -  \(c.done) of \(c.all) checked", room), "noop"))
            for (i, it) in items.enumerated() where it.section == s {
                r.append((fit((ticked.contains(it.text) ? "[X] " : "[  ] ") + it.text, room), "cl:\(i)"))
                for p in it.places {
                    let n = placeNames.first { $0.key == p }?.name ?? p
                    r.append(("      Go: \(n)", "clgo:\(p)"))
                }
            }
        }
        if items.isEmpty { r.append(("device-checklist.md not found in this build", "noop")) }
        r.append(("Back", "back"))
        let done = items.filter { ticked.contains($0.text) }.count
        return ("\(done) of \(items.count) checked  -  A: tick   X: voice note about it", r)
    }

    private static func fit(_ s: String, _ w: Int) -> String {
        guard Font.width(s) > w else { return s }
        var t = s
        while !t.isEmpty && Font.width(t + "...") > w { t.removeLast() }
        return t + "..."
    }

    static func help(_ id: String) -> String? {
        if id.hasPrefix("cl:"), let i = Int(id.dropFirst(3)), i < items.count { return items[i].text }
        if id == "cl_view" { return "Steps 8 / 16 / 24 for this session (frame-rate checks)." }
        if id == "cl_sw" { return "SpaceWarp on or off; applies at the next launch." }
        return nil
    }
}

// questcheck --checklist-only: the page from the repo's .md, two ticks, a relaunch, the ticks and log still there.
enum PlaytestChecklistCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("checklist-\(getpid())")
        try? FileManager.default.removeItem(at: tmp)
        PlaytestChecklist.dir = tmp
        PlaytestChecklist.reload()
        let n = PlaytestChecklist.items.count, secs = PlaytestChecklist.sections.count
        check(n >= 30 && secs >= 8, "checklist: \(n) items in \(secs) sections read from device-checklist.md")
        let m = PauseMenu(game: g)
        let cheats = g.cheatsAllowed
        m.page = .main; m.build()
        let at = m.rows.firstIndex { $0.1 == "checklist" }, sc = m.rows.firstIndex { $0.1 == "shortcuts" }
        check(at != nil && (sc == nil || at! < sc!), "checklist: pause menu row at \(at ?? -1), Shortcuts at \(sc ?? -1) (cheats \(cheats))")
        m.act("checklist", back: false)
        m.build()
        let ids = m.rows.map { $0.1 }
        let ticks = ids.filter { $0.hasPrefix("cl:") }.count
        check(m.page == .checklist && ticks == n && ids.first == "cl_view", "checklist: page with \(ticks) item rows, \(m.rows.count) rows; subtitle '\(m.subtitle)'")
        m.act("cl:0", back: false); m.act("cl:3", back: false); m.act("cl:5", back: false); m.act("cl:5", back: false)
        m.build()
        let shown = m.rows.filter { $0.0.hasPrefix("[X]") }.count
        PlaytestChecklist.reload()
        let kept = (0..<n).filter { PlaytestChecklist.isTicked($0) }
        let log = (try? String(contentsOf: tmp.appendingPathComponent("vn-checklist-log.md"), encoding: .utf8)) ?? ""
        let lines = log.split(separator: "\n").count
        check(shown == 2 && kept == [0, 3] && lines == 4, "checklist: 2 ticks shown, \(kept) kept after a relaunch, \(lines) log lines")
        let gos = PlaytestChecklist.items.flatMap { $0.places }
        let want = ["gulch", "capital_city", "ashvault", "monument", "frigate", "village", "hell", "military_base"]
        check(want.allSatisfy { gos.contains($0) }, "checklist: Go places \(Set(gos).sorted())")
        let v0 = g.world.renderDistance
        m.act("cl_view", back: false)
        let v1 = g.world.renderDistance
        g.setRenderDistance(v0)
        check(PlaytestChecklist.viewSteps.contains(v1), "checklist: view row steps \(v0) -> \(v1)")
        PlaytestChecklist.note(3, clock: g.clock)
        let tag = PlaytestChecklist.noteTag(clock: g.clock) ?? ""
        check(tag.contains("P"), "checklist: a voice note about item 3 is tagged '\(tag)'")
        m.page = .main; m.stack = []
        try? FileManager.default.removeItem(at: tmp)
    }
}
