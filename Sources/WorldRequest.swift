import Foundation
import Metal

// A world to open or create, from a menu action (QuestApp.appAction; the Mac's AppDelegate parses the same action).
// Shared so questcheck tests the exact create path the headset runs.
struct WorldRequest {
    var name: String?; var seed: UInt64?; var survival: Bool?; var difficulty: Int?; var smooth: Bool? = nil   // (difficulty: a P302 level, 0...5)
    var join: String? = nil          // C14: a host's address (Play Together); the world is the host's, nothing is saved

    // A guest's world from the host's welcome: the host's seed and rules, a game that never saves.
    static func guestGame(_ gu: NetGuest, device: MTLDevice, renderDistance: Int) -> Game {
        World.fewerLakesUnsaved = gu.fewerLakes             // the host's terrain (P44 water), set before World.init
        World.lessWaterUnsaved = gu.lessWater               // (H8 water)
        let wasField = FieldTerrain.unsaved
        FieldTerrain.unsaved = gu.field                     // (PG1 rewrite: the host's ground is a field: the guest's is too)
        let world = World(seed: gu.seed, device: device, save: nil)
        World.fewerLakesUnsaved = false; World.lessWaterUnsaved = false; FieldTerrain.unsaved = wasField
        world.renderDistance = renderDistance
        let game = Game(world: world, save: nil, persistent: false)
        game.survival = gu.survival
        game.diffLevel = Difficulty.clamp(gu.difficulty)          // P302: the host sends its level
        game.smoothTerrain = gu.smooth
        SmoothTerrain.use(world: game.smoothTerrain, world: game.world)
        game.time = gu.time
        game.player.pos = gu.spawn
        game.spawnPoint = gu.spawn
        gu.attach(game)
        game.netGuest = gu
        return game
    }

    // create:<survival 0/1>:<difficulty>:<smooth terrain 0/1>:<name>:<seed text> (PauseMenu's Create New World).
    static func create(action id: String) -> WorldRequest? {
        guard id.hasPrefix("create:") else { return nil }
        let parts = id.split(separator: ":", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6 else { return nil }
        return WorldRequest(name: parts[4], seed: seedValue(parts[5]), survival: parts[1] == "1", difficulty: Int(parts[2]) ?? 3,
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
            if let sv = survival { game.survival = sv }
            if let d = difficulty { game.diffLevel = Difficulty.clamp(d) }     // P302: a level (0...5)
            game.smoothTerrain = smooth ?? Settings.shared.smoothTerrain     // (PG6: a new world is Polygons unless chosen)
            // (PG1 rewrite: its ground is a density field.) Before spawnPoint: settling the spawn loads chunks, and
            // makeFieldWorld only marks a world with none loaded, so a new world came out with block ground.
            if game.smoothTerrain { game.world.makeFieldWorld() }
            game.player.pos = game.spawnPoint
        }
        SmoothTerrain.use(world: game.smoothTerrain, world: game.world)
        if meta == nil { game.placeSpawnCamp() }              // P402: a new survival world starts by an abandoned camp
        // P107: a new world's meta (seed, options, the terrain mode) is on disk from the start, so a world closed before
        // its first autosave still reopens as itself.
        if meta == nil && game.persistent { game.saveNow() }
    }
}
