import Foundation

// The saved-worlds folder: listing (newest first, with mode and last-played time), rename, copy and delete.
// Deleted worlds go to the Trash so a mistake can still be undone from Finder.
enum WorldStore {
    static var useTrash = true     // the test harness deletes for real instead
    static var base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Blocksmith/Worlds", isDirectory: true)

    struct Info {
        let name: String
        let lastPlayed: Date
        let survival: Bool?
        let seed: UInt64?
        let dimension: String?
        var smooth = false        // Terrain: Smooth (test)
        var difficulty: Int? = nil    // Q2c-console-8: what the list says about each world
        var day: Int? = nil
        var storyDone = false
        var played: Double? = nil     // Q2c-console-59: play time (seconds) from the world's statistics
    }

    static func url(_ name: String) -> URL { base.appendingPathComponent(name, isDirectory: true) }
    static func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(name).path) }

    static func list() -> [Info] {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: base.path)) ?? []).filter { !$0.hasPrefix(".") }
        var out: [Info] = []
        for n in names {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url(n).path, isDirectory: &isDir), isDir.boolValue else { continue }
            let meta = url(n).appendingPathComponent("world.json")
            let date = ((try? fm.attributesOfItem(atPath: meta.path))?[.modificationDate] as? Date)
                ?? ((try? fm.attributesOfItem(atPath: url(n).path))?[.modificationDate] as? Date) ?? .distantPast
            var survival: Bool?, seed: UInt64?, dim: String?, smooth = false
            var diff: Int?, day: Int?, done = false, played: Double?
            if let d = try? Data(contentsOf: meta), let m = try? SaveIO.decoder().decode(WorldMeta.self, from: d) {
                survival = m.survival ?? false
                seed = m.seed
                dim = m.dimension.map { $0.rawValue }
                smooth = m.extra?["terrain"] == "smooth"
                diff = m.extra?["difficulty"].flatMap { Int($0) }
                day = m.time.isFinite ? Int(m.time / DAY_LENGTH) + 1 : nil
                done = m.extra?["ashVictory"] == "1"
                played = Stats.playedIn(m.extra?["stats"])
            }
            var info = Info(name: n, lastPlayed: date, survival: survival, seed: seed, dimension: dim, smooth: smooth)
            info.difficulty = diff; info.day = day; info.storyDone = done; info.played = played
            out.append(info)
        }
        return out.sorted { $0.lastPlayed != $1.lastPlayed ? $0.lastPlayed > $1.lastPlayed : $0.name < $1.name }
    }

    // A file-system-safe world name (no slashes/colons, trimmed, not empty, at most 32 characters).
    static func clean(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        if s.count > 32 { s = String(s.prefix(32)) }
        return s.isEmpty ? "New World" : s
    }

    // `name`, or `name (2)`, `name (3)`... whichever is free.
    static func unique(_ name: String) -> String {
        if !exists(name) { return name }
        var i = 2
        while exists("\(name) (\(i))") { i += 1 }
        return "\(name) (\(i))"
    }

    @discardableResult
    static func rename(_ from: String, to raw: String) -> String? {
        let to = clean(raw)
        if to == from { return to }
        guard exists(from), !exists(to) else { return nil }
        do { try FileManager.default.moveItem(at: url(from), to: url(to)) } catch { return nil }
        if UserDefaults.standard.string(forKey: "lastWorld") == from { UserDefaults.standard.set(to, forKey: "lastWorld") }
        return to
    }

    @discardableResult
    static func copy(_ name: String) -> String? {
        let to = unique(name + " Copy")
        guard exists(name) else { return nil }
        do { try FileManager.default.copyItem(at: url(name), to: url(to)) } catch { return nil }
        // Touch world.json so the copy sorts first.
        for u in [url(to).appendingPathComponent("world.json"), url(to)] {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: u.path)
        }
        return to
    }

    @discardableResult
    static func delete(_ name: String) -> Bool {
        guard exists(name) else { return false }
        let fm = FileManager.default
        if useTrash, (try? fm.trashItem(at: url(name), resultingItemURL: nil)) != nil { return true }
        return (try? fm.removeItem(at: url(name))) != nil
    }

    // Q2c-console-8: "Survival, Normal, polygon terrain - day 27 - in the Emberdeep - story finished - last played
    // Oct 14, 12:20"; what an old save doesn't record is left out.
    static func describe(_ i: Info) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, HH:mm"
        var kind = [i.survival.map { $0 ? "Survival" : "Creative" } ?? "New"]
        if let d = i.difficulty, d >= 0, d < Game.difficultyNames.count { kind.append(Game.difficultyNames[d]) }
        kind.append(i.smooth ? "polygon terrain" : "block terrain")
        var parts = [kind.joined(separator: ", ")]
        if let d = i.day { parts.append("day \(d)") }
        if let dm = i.dimension, let dd = Dim(rawValue: dm), dd != .overworld { parts.append("in " + dd.displayName.replacingOccurrences(of: "The ", with: "the ")) }
        if i.storyDone { parts.append("story finished") }
        if let p = i.played, p >= 60 { parts.append(Stats.duration(p) + " played") }        // Q2c-console-59
        parts.append(i.lastPlayed == .distantPast ? "never played" : "last played " + f.string(from: i.lastPlayed))
        return parts.joined(separator: " - ")
    }

    // The worlds list row: the name, its mode and day, shortened to fit a menu row.
    static func rowLabel(_ i: Info, open: Bool) -> String {
        var tail = i.survival.map { $0 ? "Survival" : "Creative" } ?? "New"
        if let d = i.day { tail += ", day \(d)" }
        if let p = i.played, p >= 60 { tail += ", " + (p < 3600 ? "\(Int(p / 60)) min" : "\(Int(p / 3600)) h") }   // Q2c-console-59
        if open { tail += " (open)" }
        var name = i.name
        let room = 214
        while name.count > 3 && Font.width(name + " - " + tail) > room { name = String(name.dropLast(2)) + "." }
        return name + " - " + tail
    }
}
