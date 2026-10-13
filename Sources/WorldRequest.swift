import Foundation

// A world to open or create, from a menu action (QuestApp.appAction; the Mac's AppDelegate parses the same action).
// Shared so questcheck tests the exact create path the headset runs.
struct WorldRequest {
    var name: String?; var seed: UInt64?; var survival: Bool?; var difficulty: Int?; var smooth: Bool? = nil

    // create:<survival 0/1>:<difficulty>:<smooth terrain 0/1>:<name>:<seed text> (PauseMenu's Create New World).
    static func create(action id: String) -> WorldRequest? {
        guard id.hasPrefix("create:") else { return nil }
        let parts = id.split(separator: ":", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6 else { return nil }
        return WorldRequest(name: parts[4], seed: seedValue(parts[5]), survival: parts[1] == "1", difficulty: Int(parts[2]) ?? 2,
                            smooth: parts[3] == "1")
    }

    // The seed field's text as a seed: a number, else FNV-1a of the text.
    static func seedValue(_ text: String) -> UInt64? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if let v = UInt64(t) { return v }
        if let v = Int64(t) { return UInt64(bitPattern: v) }
        var h: UInt64 = 0xcbf29ce484222325
        for b in t.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    // A saved world's state, or a new world's options, then the terrain mode, before the first meshes (loadSync).
    func setUp(_ game: Game, meta: WorldMeta?) {
        if let m = meta { game.apply(m) } else {
            game.player.pos = game.spawnPoint
            if let sv = survival { game.survival = sv }
            if let d = difficulty { game.difficulty = d }
            game.smoothTerrain = smooth ?? false
        }
        SmoothTerrain.use(world: game.smoothTerrain, world: game.world)
        // P107: a new world's meta (seed, options, the terrain mode) is on disk from the start, so a world closed before
        // its first autosave still reopens as itself.
        if meta == nil && game.persistent { game.saveNow() }
    }
}
