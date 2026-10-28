import Foundation

// P480 (Remington, Oct 27 21:12): "make it so that there is a bug/feature reporter. So someone playing the game can
// say, yeah, like this shit's happening... Then maybe make some cap limits. That way it can't be gamed. And then it
// somehow is sent to me."
//
// The pause menu's "Report a Bug or Idea" screen (ReportMenu) sends the player's words with a small picture of where
// they are (build, position, biome, what they hold: VoiceNoteContext) as one HTTPS POST of JSON to his receiver, a
// Google Apps Script web app that mails it to him and adds a row to a sheet. Its reply comes back after a 302 redirect
// that is followed with a GET. The receiver's address is not in this public repo: store and playtest builds get it at
// build time (quest/tools/build-apk.sh: SUNDERFALL_REPORT_URL or ~/ClaudeTools/secrets/sunderfall-report-url), the Mac
// app reads the same file; with no address the menu row is not shown.
//
// Limits on this end (the receiver has its own: 5 a device a UTC day, 60 in all): 3 to 2,000 characters, 5 sent a UTC
// day, 30 s between sends, the game state cut to 2,000 characters. A report that cannot be sent (no network) waits,
// at most 5, and goes the next time the screen is opened or a report is sent.
enum Reporter {
    // Set by the host app. `transport(url, body, done)` POSTs the body, follows the redirect and calls `done` (on any
    // thread) with the final HTTP status (or -1) and the reply text.
    static var url: String?
    static var version = "dev"
    static var transport: ((String, Data, @escaping (Int, String) -> Void) -> Void)?
    static var fps: () -> Double = { 0 }
    static var available: Bool { (url?.hasPrefix("https://") ?? false) && transport != nil }

    static let minChars = 3, maxChars = 2000, maxState = 2000, perDay = 5, gap: Double = 30, maxPending = 5
    enum Kind: String { case bug, feature }

    // A random per-install ID (letters and digits), so the receiver can count one device's reports. Nothing ties it
    // to the player or the headset; reinstalling makes a new one.
    static var device: String {
        let d = UserDefaults.standard
        if let id = d.string(forKey: "reportDevice"), !id.isEmpty { return id }
        let chars = Array("abcdefghijkmnpqrstuvwxyz23456789")
        let id = "sf-" + String((0..<16).map { _ in chars[Int.random(in: 0..<chars.count)] })
        d.set(id, forKey: "reportDevice")
        return id
    }

    // Today's UTC day and how many reports went today.
    static func utcDay(_ now: Date = Date()) -> Int { Int(now.timeIntervalSince1970 / 86400) }
    static var sentToday: Int {
        let d = UserDefaults.standard
        return d.integer(forKey: "reportDay") == utcDay() ? d.integer(forKey: "reportCount") : 0
    }
    static func countSent() {
        let d = UserDefaults.standard
        let n = sentToday + 1
        d.set(utcDay(), forKey: "reportDay"); d.set(n, forKey: "reportCount")
    }
    static var lastSent: Double = -1e9                 // ProcessInfo uptime of the last send (this run)

    // What the receiver gets: the words and the game state, as one JSON object.
    static func body(_ kind: Kind, _ text: String, state: [String: String]) -> Data? {
        var st = state
        func size(_ s: [String: String]) -> Int { (try? JSONSerialization.data(withJSONObject: s, options: [.sortedKeys]))?.count ?? 0 }
        // Over the limit: the longest values are cut first, then dropped.
        while size(st) > maxState, let (k, v) = st.max(by: { $0.value.count < $1.value.count }) {
            if v.count > 60 { st[k] = String(v.prefix(v.count / 2)) } else { st[k] = nil }
        }
        let obj: [String: Any] = ["kind": kind.rawValue, "text": String(text.prefix(maxChars)), "device": device,
                                  "version": version, "state": st]
        return try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    // The game state sent with a report: where and how the player is playing, nothing about them.
    static func state(_ g: Game) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in VoiceNoteContext.describe(g, build: version, fps: fps()) where k != "world" && k != "sounds" {
            out[k] = v
        }
        out["seed"] = "\(g.world.seed)"
        out["view"] = "\(g.world.renderDistance)"
        return out
    }

    // Why a report can't go now (nil: it can).
    static func refusal(_ text: String, now: Double = ProcessInfo.processInfo.systemUptime) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count < minChars { return "Write a few words first" }
        if sentToday >= perDay { return "That's \(perDay) reports today: send more tomorrow" }
        if now - lastSent < gap { return "Wait \(Int(gap - (now - lastSent)) + 1) s before sending another" }
        return nil
    }

    // MARK: sending

    enum Outcome: Equatable { case sent, kept, refused(String) }
    private static let lock = NSLock()
    private static var replies: [(Int, Outcome)] = []     // finished sends, read by the screen on the game thread
    private static var nextTicket = 1
    private(set) static var inFlight = 0

    // Reports waiting for a connection (their JSON bodies).
    static var pending: [Data] {
        get { (UserDefaults.standard.array(forKey: "reportPending") as? [Data]) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(maxPending)), forKey: "reportPending") }
    }

    // What the receiver's reply means for the player.
    static func outcome(status: Int, reply: String) -> Outcome {
        guard status >= 200 && status < 300, let d = reply.data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return .kept }
        if j["ok"] as? Bool == true { return .sent }
        switch j["message"] as? String ?? "" {
        case "daily limit": return .refused("The report box is full today: try again tomorrow")
        case "device limit": return .refused("That's \(perDay) reports today: send more tomorrow")
        case "busy": return .kept
        case "empty": return .refused("Write a few words first")
        default: return .refused("The report wasn't accepted")
        }
    }

    // Sends one body; the outcome arrives through `poll` under the returned ticket. A body that can't go (no network,
    // a server error) is kept for later.
    @discardableResult
    static func send(_ body: Data) -> Int {
        lock.lock(); let ticket = nextTicket; nextTicket += 1; inFlight += 1; lock.unlock()
        guard let u = url, let tr = transport else { finish(ticket, .kept, body); return ticket }
        tr(u, body) { status, reply in finish(ticket, outcome(status: status, reply: reply), body) }
        return ticket
    }
    private static func finish(_ ticket: Int, _ o: Outcome, _ body: Data) {
        lock.lock()
        inFlight -= 1
        replies.append((ticket, o))
        if o == .kept, !pending.contains(body) { pending = pending + [body] }      // (UserDefaults is thread-safe)
        lock.unlock()
    }
    // The finished sends since the last call (game thread).
    static func poll() -> [(Int, Outcome)] {
        lock.lock(); defer { lock.unlock() }
        let r = replies; replies.removeAll()
        return r
    }
    // Reports kept from before go now (one try each; one that fails again is kept again).
    static func flush() {
        guard available, inFlight == 0 else { return }
        let waiting = pending
        guard !waiting.isEmpty else { return }
        pending = []
        for b in waiting { send(b) }
    }
}

#if os(macOS)
extension Reporter {
    // The Mac app: the receiver's address from SUNDERFALL_REPORT_URL or ~/ClaudeTools/secrets/sunderfall-report-url;
    // URLSession follows the 302 with a GET by itself.
    static func installMac() {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ClaudeTools/secrets/sunderfall-report-url")
        let u = ProcessInfo.processInfo.environment["SUNDERFALL_REPORT_URL"]
            ?? (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u, u.hasPrefix("https://") else { return }
        url = u
        version = "mac " + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev")
        transport = { u, body, done in
            guard let to = URL(string: u) else { done(-1, ""); return }
            var req = URLRequest(url: to, timeoutInterval: 20)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            URLSession.shared.dataTask(with: req) { d, resp, _ in
                done((resp as? HTTPURLResponse)?.statusCode ?? -1, d.map { String(decoding: $0, as: UTF8.self) } ?? "")
            }.resume()
        }
    }
}
#endif

// The report screen: Bug or Idea, the player's words (the headset's system keyboard, or the on-screen keys), Send.
final class ReportMenu: Menu, CustomDrawnMenu {
    var kind: Reporter.Kind = .bug
    var text = ""
    var status = ""
    var statusGood = true
    var ticket: Int?
    var sentFlush = Set<Int>()
    static let bugB = 0, ideaB = 1, typeB = 2, sendB = 3, cancelB = 4
    static let boxY = 44, boxH = 92, lineH = 9

    init(game: Game) {
        super.init("Report a Bug or Idea", game: game)
        showInventoryLabel = false
        width = 284; height = 196
        func button(_ id: Int, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            let b = MenuSlot(x, y, nil, 0, .button(id)); b.w = w; b.h = h; slots.append(b)
        }
        button(ReportMenu.bugB, 8, 22, 60, 16)
        button(ReportMenu.ideaB, 72, 22, 60, 16)
        button(ReportMenu.typeB, 196, 22, 80, 16)
        button(ReportMenu.sendB, 8, 158, 130, 20)
        button(ReportMenu.cancelB, 146, 158, 130, 20)
        Reporter.flush()
    }

    override var capturesText: Bool { ticket == nil }
    override func typed(_ s: String) {
        for c in s {
            if c == "\u{8}" { if !text.isEmpty { text.removeLast() } }
            else if c == "\n" || c == "\r" || c == "\t" { if !text.isEmpty && text.last != " " { text.append(" ") } }
            else if text.count < Reporter.maxChars { text.append(c) }
        }
        if !status.isEmpty && ticket == nil { status = "" }
    }

    override func buttonPressed(_ i: Int) {
        switch i {
        case ReportMenu.bugB: kind = .bug
        case ReportMenu.ideaB: kind = .feature
        case ReportMenu.typeB: game.openMenu(KeyboardMenu(game: game, target: self))
        case ReportMenu.sendB: sendNow()
        default: game.closeMenu()
        }
        game.sfx(.click, 0.3)
    }

    func sendNow() {
        guard ticket == nil else { return }
        if let why = Reporter.refusal(text) { status = why; statusGood = false; return }
        guard let body = Reporter.body(kind, text.trimmingCharacters(in: .whitespacesAndNewlines), state: Reporter.state(game)) else {
            status = "The report couldn't be put together"; statusGood = false; return
        }
        Reporter.lastSent = ProcessInfo.processInfo.systemUptime
        Reporter.countSent()
        status = "Sending..."; statusGood = true
        ticket = Reporter.send(body)
    }

    override func tick() {
        for (t, o) in Reporter.poll() where t == ticket {
            ticket = nil
            switch o {
            case .sent:
                text = ""; status = "Sent. Thank you!"; statusGood = true
            case .kept:
                text = ""; status = "No connection: it will go the next time you open this screen"; statusGood = true
            case .refused(let why):
                status = why; statusGood = false
            }
        }
    }

    // The words, wrapped to the box, the last lines shown.
    var boxLines: [String] {
        let caret = ticket == nil && Int(game.clock * 2) % 2 == 0 ? "_" : ""
        let lines = Journal.wrap(text + caret, width: width - 24)
        return Array(lines.suffix(ReportMenu.boxH / ReportMenu.lineH - 1))
    }

    func drawLines(_ L: HudLayout, _ o: V2) -> [HudLine] {
        let s = L.s
        var out: [HudLine] = []
        let dark = V4(0.12, 0.1, 0.09, 1), mid = V4(0.3, 0.27, 0.24, 1)
        func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: V4) {
            out.append(HudLine(text: "", x: o.x + Float(x) * s, y: o.y + Float(y) * s, scale: s, bg: c, box: V2(Float(w) * s, Float(h) * s)))
        }
        func label(_ t: String, _ x: Int, _ y: Int, _ c: V4) {
            out.append(HudLine(text: t, x: o.x + Float(x) * s, y: o.y + Float(y) * s, scale: s, color: c))
        }
        let hover = game.menuHover
        for sl in slots {
            guard case .button(let id) = sl.kind else { continue }
            let chosen = (id == ReportMenu.bugB && kind == .bug) || (id == ReportMenu.ideaB && kind == .feature)
            let busy = id == ReportMenu.sendB && ticket != nil
            box(sl.x, sl.y, sl.w, sl.h, V4(0.22, 0.2, 0.18, 1))
            box(sl.x + 1, sl.y + 1, sl.w - 2, sl.h - 2, chosen ? V4(0.42, 0.62, 0.36, 1)
                : (hover === sl && !busy ? V4(0.86, 0.82, 0.72, 1) : V4(0.7, 0.67, 0.6, 1)))
            let t = ["Bug", "Idea", "Keyboard", busy ? "Sending..." : "Send", "Cancel"][id]
            label(t, sl.x + (sl.w - Font.width(t)) / 2, sl.y + sl.h / 2 - 3, busy ? mid : dark)
            if hover === sl && Prompt.pad {
                box(sl.x - 1, sl.y - 1, sl.w + 2, 1, V4(1, 0.85, 0.2, 1)); box(sl.x - 1, sl.y + sl.h, sl.w + 2, 1, V4(1, 0.85, 0.2, 1))
            }
        }
        label(kind == .bug ? "What went wrong? What were you doing?" : "What would you like in the game?", 8, ReportMenu.boxY - 9, mid)
        box(8, ReportMenu.boxY, width - 16, ReportMenu.boxH, V4(0.22, 0.2, 0.18, 1))
        box(9, ReportMenu.boxY + 1, width - 18, ReportMenu.boxH - 2, V4(0.95, 0.93, 0.87, 1))
        for (k, line) in boxLines.enumerated() { label(line, 12, ReportMenu.boxY + 4 + k * ReportMenu.lineH, dark) }
        let count = "\(text.count)/\(Reporter.maxChars)"
        label(count, width - 10 - Font.width(count), ReportMenu.boxY + ReportMenu.boxH + 2, mid)
        label("Sent with it: the version, where you are and", 8, ReportMenu.boxY + ReportMenu.boxH + 2, mid)
        label("what you hold. ID " + Reporter.device, 8, ReportMenu.boxY + ReportMenu.boxH + 11, mid)
        if !status.isEmpty {
            label(ShopMenu.fit(status, width - 16), 8, height - 13, statusGood ? V4(0.1, 0.3, 0.12, 1) : V4(0.55, 0.14, 0.1, 1))
        }
        return out
    }

    var legend: String {
        if Prompt.pad { return Prompt.line([(.select, "Choose"), (.back, "Leave")]) }
        return "Type your report   " + Glyph.mouseL.s + " Choose   " + Glyphs.key("Esc") + " Leave"
    }
}
