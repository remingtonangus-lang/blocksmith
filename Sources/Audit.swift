import Foundation

// Duplicate keys and IDs across workstreams: saved-setting keys, key bindings against the fixed keys,
// the controller button mapping, options-menu rows (ids, labels, help, value stepping), mob save keys
// and names, item names. --padtest runs it so a clash fails CI; warnings are printed only.
protocol PrefKeyed { var prefKey: String { get } }
extension Pref: PrefKeyed { var prefKey: String { key } }

enum Audit {
    // UserDefaults keys stored outside Settings (Game, HudLayout, renderer, worlds, bindings).
    static let otherKeys = ["fancyGraphics", "fancyWorldScale", "invertY", "autoJump", "deadZone", "fov", "sensitivity",
                            "guiScale", "couchMode", "renderDistance", "lastWorld", "padMap", "padLayout", "dynamicResolution",
                            "volume", "musicVolume"]                  // ("audio_subtitles" is Settings.subtitles now)
    // Keys the game reads directly: Esc, Enter, F1 HUD, F2 screenshot, F3 debug, F7 bug notes, / commands, 1-9 hotbar.
    static let fixedKeys: [UInt16] = [Key.esc, Key.enter, Key.f1, Key.f2, Key.f3, 98, Key.slash] + Key.digits

    static func dups<T: Hashable>(_ xs: [T]) -> [T] {
        var seen = Set<T>(), d: [T] = []
        for x in xs where !seen.insert(x).inserted && !d.contains(x) { d.append(x) }
        return d
    }

    // (failures, warnings)
    static func run(_ g: Game) -> ([String], [String]) {
        var fail: [String] = [], warn: [String] = []

        // Saved-setting keys: every @Pref, the older stores, volume sliders and key bindings.
        var keys = Mirror(reflecting: Settings.shared).children.compactMap { ($0.value as? PrefKeyed)?.prefKey }
        if keys.count < 20 { fail.append("settings mirror found only \(keys.count) keys") }
        keys += otherKeys
        keys += SoundCategory.allCases.filter { $0 != .master && $0 != .music }.map { $0.key }
        keys += KeyBinds.Action.allCases.map { "key." + $0.rawValue }
        for k in dups(keys) { fail.append("settings key \"\(k)\" is used twice") }

        // Keyboard: defaults distinct, never on a fixed key; current bindings distinct.
        let defaults = KeyBinds.Action.allCases.map { $0.defaultKey }
        for k in dups(defaults) { fail.append("two actions default to key \(KeyBinds.name(k))") }
        for a in KeyBinds.Action.allCases where fixedKeys.contains(a.defaultKey) {
            fail.append("\(a.title) defaults to reserved key \(KeyBinds.name(a.defaultKey))")
        }
        for k in dups(KeyBinds.Action.allCases.map { KeyBinds.key($0) }) { fail.append("two actions bound to \(KeyBinds.name(k))") }
        for t in dups(KeyBinds.Action.allCases.map { $0.title }) { fail.append("key binding title \"\(t)\" twice") }

        // Controller mapping: a permutation, one label per logical button.
        if PadMap.actions.count != PadMap.count || PadMap.glyphs.count != PadMap.count { fail.append("PadMap tables differ in length") }
        if Set(PadMap.map) != Set(0..<PadMap.count) { fail.append("button mapping is not a permutation") }
        for t in dups(PadMap.actions) { fail.append("button mapping label \"\(t)\" twice") }

        // Options pages: unique ids and labels per page, help text on every setting, every value row steps.
        let pm = PauseMenu(game: g)
        pm.page = .options
        let skipStep: Set<String> = ["fullscreen", "display", "bugnotes", "rd", "narrator"]   // window / mic / world reload / speech
        var allIDs: [String: [String]] = [:]
        for c in PauseMenu.Cat.allCases {
            pm.cat = c; pm.scroll = 0; pm.build()
            let rows = pm.rows
            for d in dups(rows.map { $0.1 }) { fail.append("\(c.name): row id \(d) twice") }
            for d in dups(rows.map { $0.0 }) { fail.append("\(c.name): row \"\(d)\" twice") }
            for (label, id) in rows {
                allIDs[id, default: []].append(label)
                let nav = ["back", "padinfo", "keys", "controls", "padmap", "audio_test"].contains(id)
                if !nav && !id.hasPrefix("vol:") && PauseMenu.help[id] == nil { fail.append("\(c.name): \"\(label)\" has no help text") }
                guard PauseMenu.isValue(id), !skipStep.contains(id) else { continue }
                // Step forward: the label must change; keep stepping until it comes back (the value is restored).
                pm.act(id, back: false); pm.build()
                let after = pm.rows.first { $0.1 == id }?.0 ?? ""
                if after == label { fail.append("\(c.name): \"\(label)\" does not change when stepped") }
                var n = 0
                while (pm.rows.first { $0.1 == id }?.0 ?? label) != label && n < 24 { pm.act(id, back: false); pm.build(); n += 1 }
                if n >= 24 { fail.append("\(c.name): \"\(label)\" never cycles back") }
            }
        }
        // The same id on two pages must show the same setting (same label).
        for (id, labels) in allIDs where Set(labels).count > 1 && id != "back" { fail.append("row id \(id) means different things: \(Set(labels).sorted())") }

        // Mobs: save keys unique (saves), display names unique (subtitles, death messages).
        for k in dups(MobKind.allCases.map { $0.key }) { fail.append("mob save key \"\(k)\" twice") }
        for n in dups(MobKind.allCases.map { $0.spec.name }) { warn.append("mob name \"\(n)\" shared") }
        // Items: display names shared by different items make creative search ambiguous.
        let names = Items.defs.map { $0.display }
        let shared = dups(names)
        if !shared.isEmpty { warn.append("\(shared.count) item names shared, e.g. \(shared.prefix(6).joined(separator: ", "))") }
        return (fail, warn)
    }
}
