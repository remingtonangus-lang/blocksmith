import Foundation

// Save-format migration (round 3+). Saved names (chunk palettes, ship grids, item stacks) go through `block`/`item`
// before the "unknown -> AIR / empty" fallback, so a renamed internal key keeps old saves intact: add `old: new` to
// the alias tables. A world whose world.json lacks extra["format"] >= `format` is copied once to
// <Worlds parent>/Backups/<folder>-before-r3-<yyyyMMdd-HHmmss> before anything loads (outside the world list).
enum SaveMigration {
    static let format = 3

    // old block key (without a [state] suffix) -> new block key
    static var blockAliases: [String: String] = ["redstone_ore": "copper_ore", "deepslate_redstone_ore": "deepslate_copper_ore"]
    // old item key -> new item key
    static var itemAliases: [String: String] = [:]

    // Resolves a saved block-state name to a registered one (or nil). Keeps a `[state]` suffix when the alias target
    // has that state, else falls back to the target's default state.
    static func block(_ name: String) -> String? {
        if Blocks.has(name) { return name }
        let base: String, suffix: String
        if let b = name.firstIndex(of: "[") { base = String(name[..<b]); suffix = String(name[b...]) } else { base = name; suffix = "" }
        guard let to = blockAliases[base] else { return nil }
        if !suffix.isEmpty && Blocks.has(to + suffix) { return to + suffix }
        if Blocks.has(to) { return to }
        return Blocks.has("#group:" + to) ? "#group:" + to : nil
    }

    static func blockID(_ name: String) -> BlockID? { block(name).map { Blocks.id($0) } }

    static func item(_ name: String) -> String? {
        if Items.has(name) { return name }
        guard let to = itemAliases[name], Items.has(to) else { return nil }
        return to
    }

    static func itemID(_ name: String) -> ItemID? { item(name).map { Items.id($0) } }

    static func needsMigration(_ m: WorldMeta) -> Bool { (Int(m.extra?["format"] ?? "") ?? 0) < format }

    static func backupRoot(for worldDir: URL) -> URL {
        worldDir.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
    }

    // Copies an old-format world folder once. Returns the backup folder when one was made.
    @discardableResult
    static func backupIfNeeded(dir: URL, meta: WorldMeta) -> URL? {
        guard needsMigration(meta) else { return nil }
        let fm = FileManager.default
        let root = backupRoot(for: dir)
        let folder = dir.standardizedFileURL.lastPathComponent
        let prefix = folder + "-before-r3-"
        if let have = try? fm.contentsOfDirectory(atPath: root.path), have.contains(where: { $0.hasPrefix(prefix) }) { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let dest = root.appendingPathComponent(prefix + f.string(from: Date()), isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try fm.copyItem(at: dir, to: dest)
        } catch {
            print("save migration: backup of \(folder) failed: \(error)")
            return nil
        }
        print("save migration: backed up \(folder) to \(dest.path)")
        return dest
    }
}
