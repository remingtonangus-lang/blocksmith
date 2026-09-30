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
    var hotbar: [UInt16]?          // pre-inventory saves
    var inventory: PlayerInventory.Saved?
    var dimension: Dim?
    var spawn: [Float]?
    var xpLevel: Int?
    var xpPoints: Int?
    var selected: Int
    var renderDistance: Int
    // Added after v0.1: optional so older world.json files still decode.
    var survival: Bool?
    var health: Int?
    var hunger: Int?
    var saturation: Float?
    var dragonKilled: Bool? = nil
    var gateways: Int? = nil       // hollow rifts opened (one per dragon kill, up to 20)
    var seenCredits: Bool? = nil
    var effects: [EffectSet.Saved]? = nil
    var absorption: Float? = nil
    var enchantSeed: UInt64? = nil
    var extra: [String: String]? = nil  // misc later additions (raids, villages...)
}

// Layout: ~/Library/Application Support/Blocksmith/Worlds/<name>/
//   world.json          player + world settings
//   chunks/c.X.Z.lz     only chunks the player modified (terrain is regenerated from the seed)
final class SaveManager {
    let dir: URL
    let chunkDir: URL

    convenience init(name: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(dir: base.appendingPathComponent("Blocksmith/Worlds/\(name)", isDirectory: true))
    }

    // Save folder for another dimension inside this world's folder.
    func sub(_ folder: String) -> SaveManager { SaveManager(dir: dir.appendingPathComponent(folder, isDirectory: true)) }

    init(dir d: URL) {
        dir = d
        // chunks3: name-paletted 16-bit states, 384 tall (older chunk folders from previous engines are ignored).
        chunkDir = dir.appendingPathComponent("chunks3", isDirectory: true)
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

    var blockEntityURL: URL { dir.appendingPathComponent("blockentities.json") }

    func loadBlockEntities() -> [IVec3: BlockEntity] {
        guard let d = try? Data(contentsOf: blockEntityURL),
              let s = try? JSONDecoder().decode(BlockEntitySave.self, from: d) else { return [:] }
        var out: [IVec3: BlockEntity] = [:]
        for (k, v) in s.entries {
            let p = k.split(separator: ",").compactMap { Int($0) }
            if p.count == 3 { out[IVec3(p[0], p[1], p[2])] = v }
        }
        return out
    }

    func saveBlockEntities(_ m: [IVec3: BlockEntity]) {
        var e: [String: BlockEntity] = [:]
        for (k, v) in m { e["\(k.x),\(k.y),\(k.z)"] = v }
        if let d = try? JSONEncoder().encode(BlockEntitySave(entries: e)) { try? d.write(to: blockEntityURL, options: .atomic) }
    }

    func loadPortals() -> [IVec3] {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("portals.json")),
              let a = try? JSONDecoder().decode([[Int]].self, from: d) else { return [] }
        return a.filter { $0.count == 3 }.map { IVec3($0[0], $0[1], $0[2]) }
    }

    func savePortals(_ p: [IVec3]) {
        if let d = try? JSONEncoder().encode(p.map { [$0.x, $0.y, $0.z] }) {
            try? d.write(to: dir.appendingPathComponent("portals.json"), options: .atomic)
        }
    }

    func chunkURL(_ k: ChunkKey) -> URL { chunkDir.appendingPathComponent("c.\(k.x).\(k.z).lz") }

    // Chunk file: lzfse( u32 paletteCount, palette names (u16 length + utf8), u16 palette index per block ).
    // Block names instead of raw IDs keep saves valid when the block registry grows.
    // Thread-safe: called from world worker threads.
    func loadChunk(_ k: ChunkKey) -> [BlockID]? {
        if let queued = SaveIO.pending(chunkURL(k).path) { return queued }     // written in the background, not on disk yet
        guard let d = try? Data(contentsOf: chunkURL(k)) else { return nil }
        guard let raw = try? (d as NSData).decompressed(using: .lzfse) as Data else { return nil }
        let bytes = [UInt8](raw)
        var p = 0
        func u16() -> Int { defer { p += 2 }; return p + 1 < bytes.count ? Int(bytes[p]) | Int(bytes[p + 1]) << 8 : 0 }
        guard bytes.count >= 4 else { return nil }
        let n = Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
        p = 4
        var palette: [BlockID] = []
        for _ in 0..<n {
            let len = u16()
            guard p + len <= bytes.count else { return nil }
            let name = String(decoding: bytes[p..<(p + len)], as: UTF8.self)
            p += len
            palette.append(Blocks.has(name) ? Blocks.id(name) : AIR)
        }
        guard bytes.count - p == CSQ * CH * 2 else { return nil }
        var out = [BlockID](repeating: 0, count: CSQ * CH)
        for i in 0..<out.count {
            let idx = Int(bytes[p]) | Int(bytes[p + 1]) << 8
            p += 2
            out[i] = idx < palette.count ? palette[idx] : AIR
        }
        return out
    }

    // Queues a chunk write on the background save queue (the main thread only hands over the array).
    func saveChunkAsync(_ k: ChunkKey, _ blocks: BlockStore) {
        let url = chunkURL(k)
        SaveIO.enqueue(url.path, blocks) { [self] in saveChunk(k, blocks.full()) }
    }

    func saveChunk(_ k: ChunkKey, _ blocks: [BlockID]) {
        // Palette through a flat table (block id -> palette index + 1) instead of a dictionary per block.
        var map = [UInt16](repeating: 0, count: max(Blocks.count, 1) + 1)
        var names: [String] = []
        var idx = [UInt16](repeating: 0, count: blocks.count)
        for i in 0..<blocks.count {
            let b = Int(blocks[i])
            if b < map.count, map[b] != 0 { idx[i] = map[b] - 1; continue }
            let m = UInt16(names.count)
            if b < map.count { map[b] = m + 1 }
            names.append(Blocks.key(BlockID(b)))
            idx[i] = m
        }
        var d = Data()
        let n = UInt32(names.count)
        d.append(contentsOf: [UInt8(n & 255), UInt8((n >> 8) & 255), UInt8((n >> 16) & 255), UInt8(n >> 24)])
        for name in names {
            let u = Array(name.utf8)
            d.append(contentsOf: [UInt8(u.count & 255), UInt8(u.count >> 8)])
            d.append(contentsOf: u)
        }
        idx.withUnsafeBytes { d.append(contentsOf: $0) }
        guard let c = try? (d as NSData).compressed(using: .lzfse) as Data else { return }
        try? c.write(to: chunkURL(k), options: .atomic)
    }
}

// Background chunk writes. Queued arrays stay readable (loadChunk) until they are on disk, so a chunk that
// unloads and comes straight back never reads a stale file. flush() waits for every queued write (quit).
enum SaveIO {
    private static let queue = DispatchQueue(label: "blocksmith.save", qos: .utility)
    private static let lock = NSLock()
    private static var queued: [String: (id: Int, blocks: BlockStore)] = [:]
    private static var nextID = 0

    static func pending(_ path: String) -> [BlockID]? {
        lock.lock(); defer { lock.unlock() }
        return queued[path]?.blocks.full()
    }

    static func enqueue(_ path: String, _ blocks: BlockStore, _ write: @escaping () -> Void) {
        lock.lock()
        nextID += 1
        let id = nextID
        queued[path] = (id, blocks)
        lock.unlock()
        queue.async {
            write()
            lock.lock()
            if queued[path]?.id == id { queued[path] = nil }     // a newer write of the same chunk keeps its entry
            lock.unlock()
        }
    }

    static func flush() { queue.sync {} }
}
