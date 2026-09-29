import Foundation

struct WorldMeta: Codable {
    var seed: UInt64
    var x: Float
    var y: Float
    var z: Float
    var yaw: Float
    var pitch: Float
    var time: Double
    var flying: Bool
    var hotbar: [UInt8]
    var selected: Int
    var renderDistance: Int
}

// Layout: ~/Library/Application Support/Blocksmith/Worlds/<name>/
//   world.json          player + world settings
//   chunks/c.X.Z.lz     only chunks the player modified (terrain is regenerated from the seed)
final class SaveManager {
    let dir: URL
    let chunkDir: URL

    init(name: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Blocksmith/Worlds/\(name)", isDirectory: true)
        chunkDir = dir.appendingPathComponent("chunks", isDirectory: true)
        try? FileManager.default.createDirectory(at: chunkDir, withIntermediateDirectories: true)
    }

    var metaURL: URL { dir.appendingPathComponent("world.json") }

    func loadMeta() -> WorldMeta? {
        guard let d = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(WorldMeta.self, from: d)
    }

    func saveMeta(_ m: WorldMeta) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(m) { try? d.write(to: metaURL, options: .atomic) }
    }

    func chunkURL(_ k: ChunkKey) -> URL { chunkDir.appendingPathComponent("c.\(k.x).\(k.z).lz") }

    // Thread-safe: called from world worker threads.
    func loadChunk(_ k: ChunkKey) -> [UInt8]? {
        guard let d = try? Data(contentsOf: chunkURL(k)) else { return nil }
        guard let raw = try? (d as NSData).decompressed(using: .lzfse) as Data else { return nil }
        guard raw.count == CSQ * CH else { return nil }
        return [UInt8](raw)
    }

    func saveChunk(_ k: ChunkKey, _ blocks: [UInt8]) {
        let raw = Data(blocks)
        guard let c = try? (raw as NSData).compressed(using: .lzfse) as Data else { return }
        try? c.write(to: chunkURL(k), options: .atomic)
    }
}
