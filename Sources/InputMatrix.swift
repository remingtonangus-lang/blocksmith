import Foundation
import simd

// --inputmatrix OUT.md (snapshot sub-mode): docs/STORE_QUALITY.md objective 3, input conflicts. Generated, not
// hand-written: in each context (on foot, riding a horse, driving a car, inventory open) every controller button is
// tapped and held through the real Game.tick (PadManager.simulated, as --padtest does), and the game state it
// changed is recorded (menu, pause, hotbar, camera, mount, helm, flight, sneak, jump, dropped items...). A button
// that changes two things at once in one context is a conflict (Remington: B opened the inventory and dismounted).
// The keyboard table comes from KeyBinds (duplicate default keys are conflicts too). Quest Touch bindings live in
// quest/src/app/QuestControls.swift and are not covered here (it only builds for Android/Linux).
enum InputMatrix {
    static let buttons = ["a", "b", "x", "y", "lb", "rb", "lt", "rt", "l3", "r3", "menu", "view", "up", "down", "left", "right"]

    struct State {
        var menu = "", paused = false, selected = 0, camera = 0, riding = false, helm = false, flying = false
        var sneaking = false, items = 0, y: Float = 0, aim = false
    }

    static func state(_ g: Game) -> State {
        var s = State()
        s.menu = g.menu.map { "\(type(of: $0))" } ?? ""
        s.paused = g.paused; s.selected = g.selected; s.camera = g.cameraMode
        s.riding = g.riding != nil; s.helm = g.world.ships.pilot != nil
        s.flying = g.player.flying; s.sneaking = g.player.sneaking
        s.items = g.drops.items.count; s.y = g.player.pos.y
        return s
    }

    static func diff(_ a: State, _ b: State) -> [String] {
        var e: [String] = []
        if a.menu != b.menu { e.append(b.menu.isEmpty ? "close \(a.menu)" : "open \(b.menu)") }
        if a.paused != b.paused && a.menu == b.menu { e.append(b.paused ? "pause" : "unpause") }   // a menu that pauses is one action
        if a.selected != b.selected { e.append("hotbar") }
        if a.camera != b.camera { e.append("camera") }
        if a.riding != b.riding { e.append(b.riding ? "mount" : "dismount") }
        if a.helm != b.helm { e.append(b.helm ? "take helm" : "leave helm") }
        if a.flying != b.flying { e.append("flight") }
        if a.sneaking != b.sneaking { e.append("sneak") }
        if b.items > a.items { e.append("drop item") }
        if b.y - a.y > 0.4 && !a.helm && !a.riding { e.append("jump/rise") }
        return e
    }

    static func run(game g: Game, at start: V3, out: String) -> Int {
        let w = g.world
        _ = w.loadSync(center: start, radius: 4)
        g.survival = true
        g.paused = false
        func frame(_ p: PadSnapshot = PadSnapshot()) { PadManager.shared.simulated = p; g.tick(1.0 / 60) }
        func reset() {
            for _ in 0..<3 { if g.menu != nil { g.menu = nil }; frame() }
            if w.ships.pilot != nil { g.leaveHelm() }
            for s in w.ships.list { w.ships.remove(s) }
            w.ships.pilot = nil; w.ships.aboard = nil
            g.riding = nil
            g.paused = false; g.cameraMode = 0; g.player.flying = false; g.player.sneaking = false
            g.player.pos = start; g.player.vel = .zero
            for _ in 0..<30 { frame() }               // settle on the ground
        }
        var horse: Mob?
        let contexts: [(String, () -> Bool)] = [
            ("on foot", { true }),
            ("riding horse", {
                let m = Mob(.horse, at: start + V3(1.5, 0, 0)); m.saddled = true; m.owner = true
                g.mobs.mobs.append(m); horse = m
                g.riding = m; g.player.pos = m.pos + V3(0, m.height * 0.75, 0)
                for _ in 0..<5 { frame() }
                return g.riding != nil
            }),
            ("driving car", {
                guard case let (car?, _) = w.ships.assemble(at: ShipTest.place(w, "car", near: start), game: g) else { return false }
                g.startPiloting(car)
                for _ in 0..<5 { frame() }
                return w.ships.pilot != nil
            }),
            ("inventory open", {
                for _ in 0..<48 { frame(PadTest.pad("y")) }   // Halo layout: hold Y (Classic: tap)
                for _ in 0..<6 { frame() }
                return g.menu != nil
            }),
        ]
        var md = "# Input binding matrix (Blocksmith --inputmatrix)\n\nController layout: \(PadMap.layoutName). Each cell: what a tap / a 0.8 s hold changed.\n\n"
        md += "| button | " + contexts.map { $0.0 }.joined(separator: " | ") + " |\n|---|" + contexts.map { _ in "---|" }.joined() + "\n"
        var conflicts: [String] = []
        var cells: [String: [String]] = [:]
        for b in buttons {
            var row: [String] = []
            for (cname, setup) in contexts {
                var parts: [String] = []
                for hold in [false, true] {
                    reset()
                    if let h = horse { h.health = 0; horse = nil }
                    guard setup() else { parts.append("(context failed)"); continue }
                    let s0 = state(g)
                    let n = hold ? 48 : 1
                    for _ in 0..<n { frame(PadTest.pad(b)) }
                    for _ in 0..<12 { frame() }
                    let e = diff(s0, state(g))
                    parts.append((hold ? "hold: " : "") + (e.isEmpty ? "-" : e.joined(separator: " + ")))
                    if e.count >= 2 { conflicts.append("\(cname), \(b) \(hold ? "hold" : "tap"): \(e.joined(separator: " + "))") }
                }
                cells["\(cname)|\(b)"] = parts
                row.append(parts.joined(separator: "; "))
            }
            md += "| \(b) | " + row.joined(separator: " | ") + " |\n"
            print("inputmatrix \(b): " + row.joined(separator: " | "))
        }
        PadManager.shared.simulated = nil
        reset()
        // Keyboard defaults: one action per key.
        var byKey: [UInt16: [String]] = [:]
        for a in KeyBinds.Action.allCases { byKey[a.defaultKey, default: []].append(a.title) }
        let keyDupes = byKey.values.filter { $0.count > 1 }
        md += "\n## Keyboard defaults\n\n\(KeyBinds.Action.allCases.count) rebindable actions; duplicate default keys: \(keyDupes.isEmpty ? "none" : keyDupes.map { $0.joined(separator: " / ") }.joined(separator: "; "))\n"
        md += "\n## Conflicts (one press, two effects)\n\n" + (conflicts.isEmpty ? "none\n" : conflicts.map { "- " + $0 }.joined(separator: "\n") + "\n")
        try? md.write(toFile: out, atomically: true, encoding: .utf8)
        for c in conflicts { print("inputmatrix CONFLICT: " + c) }
        print("inputmatrix: \(conflicts.count) controller conflicts, \(keyDupes.count) keyboard duplicates -> \(out)")
        return conflicts.count + keyDupes.count
    }
}
