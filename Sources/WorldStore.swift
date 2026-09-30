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
            var survival: Bool?, seed: UInt64?, dim: String?
            if let d = try? Data(contentsOf: meta), let m = try? JSONDecoder().decode(WorldMeta.self, from: d) {
                survival = m.survival ?? false
                seed = m.seed
                dim = m.dimension.map { "\($0)" }
            }
            out.append(Info(name: n, lastPlayed: date, survival: survival, seed: seed, dimension: dim))
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

    static func describe(_ i: Info) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let mode = i.survival.map { $0 ? "Survival" : "Creative" } ?? "New"
        let when = i.lastPlayed == .distantPast ? "never played" : f.string(from: i.lastPlayed)
        return "\(mode) - last played \(when)"
    }
}
