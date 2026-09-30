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
    // Added after v0.1: optional so older world.json files still decode.
    var survival: Bool?
    var health: Int?
    var hunger: Int?
    var saturation: Float?
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
        // v2 chunks: 16-bit block states, 384 tall (v1 "chunks/" from the 8-bit engine is ignored).
        chunkDir = dir.appendingPathComponent("chunks2", isDirectory: true)
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
    func loadChunk(_ k: ChunkKey) -> [BlockID]? {
        guard let d = try? Data(contentsOf: chunkURL(k)) else { return nil }
        guard let raw = try? (d as NSData).decompressed(using: .lzfse) as Data else { return nil }
        guard raw.count == CSQ * CH * 2 else { return nil }
        var out = [BlockID](repeating: 0, count: CSQ * CH)
        out.withUnsafeMutableBytes { dst in raw.copyBytes(to: dst.bindMemory(to: UInt8.self)) }
        let n = Blocks.count
        for i in 0..<out.count where Int(out[i]) >= n { out[i] = 0 }   // unknown states (downgrade) -> air
        return out
    }

    func saveChunk(_ k: ChunkKey, _ blocks: [BlockID]) {
        let raw = blocks.withUnsafeBytes { Data($0) }
        guard let c = try? (raw as NSData).compressed(using: .lzfse) as Data else { return }
        try? c.write(to: chunkURL(k), options: .atomic)
    }
}
