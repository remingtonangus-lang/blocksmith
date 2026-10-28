import Foundation

// P480: questcheck --reportcheck. The bug and idea reporter with a stand-in receiver (no network): the pause row, the
// local limits, what is sent (the receiver's fields and sizes), a report kept with no connection and sent later, the
// receiver's refusals, and the screen's drawing staying inside its panel with a full 2,000 characters.
enum ReporterTests {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let d = UserDefaults.standard
        let keys = ["reportDay", "reportCount", "reportPending", "reportDevice"]
        for k in keys { d.removeObject(forKey: k) }
        let url0 = Reporter.url, tr0 = Reporter.transport
        defer { Reporter.url = url0; Reporter.transport = tr0; for k in keys { d.removeObject(forKey: k) } }

        // No receiver address: no row.
        Reporter.url = nil; Reporter.transport = nil
        g.paused = false
        let pm0 = PauseMenu(game: g); pm0.build()
        check(!pm0.rows.contains { $0.1 == "report" }, "reportcheck: no Report row without an address")

        var bodies: [Data] = []
        var reply: (Int, String) = (200, "{\"ok\":true,\"message\":\"thanks\"}")
        Reporter.url = "https://example.invalid/exec"
        Reporter.transport = { _, body, done in bodies.append(body); done(reply.0, reply.1) }
        let pm = PauseMenu(game: g); pm.build()
        check(pm.rows.contains { $0.1 == "report" }, "reportcheck: the pause menu has Report a Bug or Idea")

        let m = ReportMenu(game: g)
        g.openMenu(m)
        m.typed("hi")
        m.sendNow()
        check(bodies.isEmpty && !m.statusGood, "reportcheck: two letters are refused here (\(m.status))")
        m.typed(String(repeating: "x", count: 2500))
        check(m.text.count == Reporter.maxChars, "reportcheck: the words stop at \(Reporter.maxChars) (\(m.text.count))")
        m.text = ""
        m.typed("The horse \"Clover\" fell through the ground\nnear the bridge \u{e9}")
        m.buttonPressed(ReportMenu.bugB)
        m.sendNow(); m.tick()
        var fields: [String: Any] = [:]
        if let b = bodies.first, let j = (try? JSONSerialization.jsonObject(with: b)) as? [String: Any] { fields = j }
        let st = fields["state"] as? [String: String] ?? [:]
        let stSize = (try? JSONSerialization.data(withJSONObject: st))?.count ?? 0
        let dev = fields["device"] as? String ?? ""
        check(bodies.count == 1 && fields["kind"] as? String == "bug"
              && (fields["text"] as? String ?? "").hasPrefix("The horse \"Clover\" fell through the ground near the bridge")
              && dev.hasPrefix("sf-") && dev.count <= 64 && dev.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
              && fields["version"] is String && st["position"] != nil && st["biome"] != nil && st["seed"] != nil
              && st["world"] == nil && stSize <= Reporter.maxState,
              "reportcheck: one POST with kind, text, device \(dev), version and a \(stSize)-byte state (keys \(st.keys.sorted().joined(separator: ",")))")
        check(m.status.hasPrefix("Sent") && m.text.isEmpty && Reporter.sentToday == 1, "reportcheck: the reply 'thanks' reads Sent (\(m.status), \(Reporter.sentToday) today)")

        m.typed("Second report straight away")
        m.sendNow()
        check(bodies.count == 1 && m.status.hasPrefix("Wait"), "reportcheck: a second send within 30 s waits (\(m.status))")

        // No connection: kept, then sent the next time the screen opens.
        Reporter.lastSent = -1e9
        reply = (-1, "")
        m.sendNow(); m.tick()
        check(Reporter.pending.count == 1 && m.status.hasPrefix("No connection"), "reportcheck: no connection keeps the report (\(Reporter.pending.count) waiting: \(m.status))")
        reply = (200, "{\"ok\":true,\"message\":\"thanks\"}")
        let before = bodies.count
        let m2 = ReportMenu(game: g)
        _ = Reporter.poll()
        check(bodies.count == before + 1 && Reporter.pending.isEmpty, "reportcheck: the kept report goes when the screen opens again (\(bodies.count - before) sent, \(Reporter.pending.count) waiting)")

        // The receiver's limit, and this end's 5 a day.
        Reporter.lastSent = -1e9
        reply = (200, "{\"ok\":false,\"message\":\"device limit\"}")
        m2.typed("Third report about the trees"); m2.buttonPressed(ReportMenu.ideaB)
        m2.sendNow(); m2.tick()
        let lastKind = (bodies.last.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["kind"] as? String
        check(!m2.statusGood && m2.status.contains("tomorrow") && Reporter.pending.isEmpty && lastKind == "feature",
              "reportcheck: the receiver's device limit is shown and not retried (\(m2.status), kind \(lastKind ?? "?"))")
        d.set(Reporter.utcDay(), forKey: "reportDay"); d.set(Reporter.perDay, forKey: "reportCount")
        Reporter.lastSent = -1e9
        let n = bodies.count
        m2.sendNow()
        check(bodies.count == n && m2.status.contains("today"), "reportcheck: the 6th report of a day stays here (\(m2.status))")

        // A huge state is cut to the limit; the screen with 2,000 characters stays inside its panel.
        let big = Reporter.body(.bug, "words", state: ["a": String(repeating: "y", count: 5000), "b": "short", "c": String(repeating: "z", count: 900)])
        let bigState = (big.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["state"] as? [String: String] ?? [:]
        let bigSize = (try? JSONSerialization.data(withJSONObject: bigState))?.count ?? 99999
        check(bigSize <= Reporter.maxState && bigState["b"] == "short", "reportcheck: a 5,900-character state is cut to \(bigSize)")
        m2.text = String(repeating: "Wide words and W ", count: 200).prefix(2000).description
        m2.status = "That's 5 reports today: send more tomorrow"
        let L = HudLayout(1280, 800).fitted(m2)
        let o = m2.origin(L)
        var bad: [String] = []
        for l in m2.drawLines(L, o) {
            let w = l.box?.x ?? Float(Font.width(l.text)) * l.scale
            let x1 = l.x + w, y1 = l.y + (l.box?.y ?? 8 * l.scale)
            if l.x < o.x - 0.5 || x1 > o.x + Float(m2.width) * L.s + 0.5 || l.y < o.y - 0.5 || y1 > o.y + Float(m2.height) * L.s + 0.5 {
                bad.append("'\(l.text.prefix(30))'")
            }
        }
        check(bad.isEmpty, "reportcheck: the report screen draws inside its panel (outside: \(bad.joined(separator: " ")))")
        g.closeMenu()
    }
}
