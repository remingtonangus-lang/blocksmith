import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

// Accessibility > Narrator: reads the highlighted menu row or slot, screen titles and toasts aloud with the
// system voice. Button glyphs are spoken as their names ("A", "LB"...). Off in the test harness.
final class Narrator {
    static let shared = Narrator()
    #if canImport(AVFoundation)
    private var synth: AVSpeechSynthesizer?
    #endif
    private var last = ""
    private var lastAt: Double = 0
    var lastDesc = ""
    weak var lastMenu: Menu?
    var lastToast: Double = -100

    var enabled: Bool { Settings.shared.narrator && HudExtras.enabled }

    static let glyphNames: [UInt32: String] = [
        Glyph.a.rawValue: "A", Glyph.b.rawValue: "B", Glyph.x.rawValue: "X", Glyph.y.rawValue: "Y",
        Glyph.lb.rawValue: "left bumper", Glyph.rb.rawValue: "right bumper", Glyph.lt.rawValue: "left trigger", Glyph.rt.rawValue: "right trigger",
        Glyph.ls.rawValue: "left stick", Glyph.rs.rawValue: "right stick", Glyph.l3.rawValue: "left stick click", Glyph.r3.rawValue: "right stick click",
        Glyph.menu.rawValue: "menu", Glyph.view.rawValue: "view", Glyph.share.rawValue: "share", Glyph.dpad.rawValue: "d-pad",
        Glyph.dup.rawValue: "d-pad up", Glyph.ddown.rawValue: "d-pad down", Glyph.dleft.rawValue: "d-pad left", Glyph.dright.rawValue: "d-pad right",
        Glyph.dpadH.rawValue: "d-pad left or right", Glyph.dpadV.rawValue: "d-pad up or down",
        Glyph.mouseL.rawValue: "left click", Glyph.mouseR.rawValue: "right click", Glyph.mouseM.rawValue: "middle click",
    ]

    // Plain text for speech: glyphs become words, key caps lose their markers.
    static func plain(_ s: String) -> String {
        var out = ""
        let ps: [UInt32: String] = [Glyph.a.rawValue: "cross", Glyph.b.rawValue: "circle", Glyph.x.rawValue: "square", Glyph.y.rawValue: "triangle"]
        for u in s.unicodeScalars {
            if PadManager.shared.style == .playstation, let n = ps[u.value] { out += " " + n + " " }
            else if let n = glyphNames[u.value] { out += " " + n + " " }
            else if Glyphs.isGlyph(Int(u.value)) { continue }
            else { out.unicodeScalars.append(u) }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    func say(_ text: String, clock: Double, interrupt: Bool = true) {
        guard enabled else { return }
        let t = Narrator.plain(text)
        guard !t.isEmpty, t != last || clock - lastAt > 2 else { return }
        last = t
        lastAt = clock
        #if canImport(AVFoundation)      // the Quest port has no system voice yet
        if synth == nil { synth = AVSpeechSynthesizer() }
        guard let s = synth else { return }
        if interrupt && s.isSpeaking { s.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: t)
        u.rate = 0.5
        s.speak(u)
        #endif
    }

    // What the highlighted element is, in words.
    static func describe(_ m: Menu, _ h: MenuSlot) -> String {
        if let pm = m as? PauseMenu, let i = pm.slots.firstIndex(where: { $0 === h }), let r = pm.row(forSlot: i) { return r.0 }
        if let km = m as? KeyboardMenu, let i = km.slots.firstIndex(where: { $0 === h }), i < km.keys.count {
            let k = km.keys[i]
            return k == " " ? "space" : k
        }
        if m is CreativeMenu, case .button(let i) = h.kind, let t = CreativeMenu.Tab(rawValue: i - CreativeMenu.tabButton) { return t.name + " tab" }
        if h.isButton { return "" }
        let st = h.stack
        if st.isEmpty { return "empty" }
        return st.count > 1 ? "\(st.count) \(st.displayName)" : st.displayName
    }

    // Per frame (from HudExtras.tick).
    func tick(_ g: Game) {
        guard enabled else { lastDesc = ""; lastMenu = nil; return }
        if g.toastTime != lastToast {
            lastToast = g.toastTime
            if !g.toastText.isEmpty { say(g.toastText, clock: g.clock, interrupt: false) }
        }
        guard let m = g.menu else { lastMenu = nil; lastDesc = ""; return }
        var parts: [String] = []
        let fresh = m !== lastMenu
        if fresh {
            lastMenu = m
            if !m.title.isEmpty { parts.append(m.title) }
        }
        // Compare by text: pause pages rebuild their buttons every few frames.
        let d = (g.menuHover.map { Narrator.describe(m, $0) } ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "_ "))   // no blinking caret
        if d != lastDesc || fresh {
            lastDesc = d
            if !d.isEmpty { parts.append(d) }
        }
        if !parts.isEmpty { say(parts.joined(separator: ". "), clock: g.clock) }
    }
}
