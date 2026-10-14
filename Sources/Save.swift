import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Darwin)
import Darwin
#endif

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
        self.init(dir: WorldStore.url(name))
    }

    // Save folder for another dimension inside this world's folder.
    func sub(_ folder: String) -> SaveManager {
        let m = SaveManager(dir: dir.appendingPathComponent(folder, isDirectory: true))
        m.overworldFloor = false
        m.deepSeal = folder == Dim.deep.folder
        return m
    }
    // The surface's chunks lost their bedrock floor (task 22, the Deep below): saved chunks still holding the old
    // floor (bedrock in internal layers 0-4) get emberslate there as they load, like freshly generated ones.
    var overworldFloor = true
    // The Deep's chunks saved before the Sealrock existed get it stamped in as they load (DeepSeal.stamp).
    var deepSeal = false
    // PG1 rewrite: a field world's save (World.fieldTerrain): its chunk files hold only the built layer.
    var fieldWorld = false

    init(dir d: URL) {
        dir = d
        // chunks3: name-paletted 16-bit states, 384 tall (older chunk folders from previous engines are ignored).
        chunkDir = dir.appendingPathComponent("chunks3", isDirectory: true)
        try? FileManager.default.createDirectory(at: chunkDir, withIntermediateDirectories: true)
    }

    var metaURL: URL { dir.appendingPathComponent("world.json") }

    // The chunks this world had generated when it first loaded with task 23's structures (Capital cities, denser
    // citadels): taken once from the chunk folder and kept in structure-guard.txt ("x,z" per line), so the set never
    // grows with chunks generated afterwards (those already have the new structures). A new world's guard is empty.
    // A terrain change for new worlds only (P44 water): true for a world made with it (the marker is written when
    // the world is new: no meta and no chunks yet), false for one made before.
    func newTerrain(_ marker: String) -> Bool {
        let url = dir.appendingPathComponent(marker)
        if FileManager.default.fileExists(atPath: url.path) { return true }
        let chunks = ((try? FileManager.default.contentsOfDirectory(atPath: chunkDir.path)) ?? []).contains { $0.hasPrefix("c.") }
        if FileManager.default.fileExists(atPath: metaURL.path) || chunks { return false }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "new terrain since Oct 13 (P44 water)\n".write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    // The save whose guard was read last (StructureCache.legacyC13 takes R20's guard from it).
    static weak var guarding: SaveManager?
    func structureGuard(file: String = "structure-guard.txt") -> Set<Int64> {
        SaveManager.guarding = self
        let url = dir.appendingPathComponent(file)
        var out = Set<Int64>()
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            for line in s.split(separator: "\n") {
                let p = line.split(separator: ",")
                if p.count == 2, let x = Int(p[0]), let z = Int(p[1]) { out.insert(StructureCache.key(x, z)) }
            }
            return out
        }
        var lines: [String] = []
        for f in (try? FileManager.default.contentsOfDirectory(atPath: chunkDir.path)) ?? [] where f.hasPrefix("c.") && f.hasSuffix(".lz") {
            let p = f.dropFirst(2).dropLast(3).split(separator: ".", omittingEmptySubsequences: false)
            // "c.-1.-21.lz": the split keeps the signs ("-1", "-21").
            guard p.count == 2, let x = Int(p[0]), let z = Int(p[1]) else { continue }
            out.insert(StructureCache.key(x, z))
            lines.append("\(x),\(z)")
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return out
    }

    func loadMeta() -> WorldMeta? {
        SaveIO.flush()              // a background autosave of this world still writing (SaveIO.writeJSON)
        guard let d = try? Data(contentsOf: metaURL) else { return nil }
        guard let m = try? SaveIO.decoder().decode(WorldMeta.self, from: d) else {
            // S1: a damaged world.json made the world open as a brand new one (the seed lost, the next save writing over
            // the player's world). It is kept as world.json.corrupt and the newest backup copy is used instead.
            SaveIO.quarantine(metaURL, what: "world file")
            if let b = SaveIO.latestBackup(dir, "world.json"), let bd = try? Data(contentsOf: b),
               let bm = try? SaveIO.decoder().decode(WorldMeta.self, from: bd) {
                SaveIO.report("The world was restored from its last backup copy")
                return bm
            }
            return nil
        }
        if !backupChecked { backupChecked = true; SaveMigration.backupIfNeeded(dir: dir, meta: m) }
        return m
    }
    private var backupChecked = false

    func saveMeta(_ m0: WorldMeta, background: Bool = false) {
        var m = m0
        m.extra = (m.extra ?? [:]).merging(["format": String(SaveMigration.format)]) { _, n in n }
        if background { SaveIO.writeJSON(m, to: metaURL, pretty: true) } else { SaveIO.storeJSON(m, to: metaURL, pretty: true) }
        SaveIO.snapshot(dir)                   // S3 (queued after the writes above)
    }

    var blockEntityURL: URL { dir.appendingPathComponent("blockentities.json") }

    func loadBlockEntities() -> [IVec3: BlockEntity] {
        guard let d = try? Data(contentsOf: blockEntityURL) else { return [:] }
        guard let s = try? JSONDecoder().decode(BlockEntitySave.self, from: d) else {
            // S1: chests and furnaces that won't decode are kept as .corrupt (and the backup copy is loaded), not
            // silently replaced by an empty list on the next save.
            SaveIO.quarantine(blockEntityURL, what: "chest and furnace file")
            if let b = SaveIO.latestBackup(dir, "blockentities.json"), let bd = try? Data(contentsOf: b),
               let bs = try? JSONDecoder().decode(BlockEntitySave.self, from: bd) {
                SaveIO.report("Chests and furnaces were restored from the last backup copy")
                var out: [IVec3: BlockEntity] = [:]
                for (k, v) in bs.entries {
                    let p = k.split(separator: ",").compactMap { Int($0) }
                    if p.count == 3 { out[IVec3(p[0], p[1], p[2])] = v }
                }
                return out
            }
            return [:]
        }
        var out: [IVec3: BlockEntity] = [:]
        for (k, v) in s.entries {
            let p = k.split(separator: ",").compactMap { Int($0) }
            if p.count == 3 { out[IVec3(p[0], p[1], p[2])] = v }
        }
        return out
    }

    // F1 (Oct 13 evening: "~1 s freezes"): the autosave encoded every block entity of the world as JSON on the frame
    // thread. Now copies (BlockEntity.snapshot: plain fields and the slots) are taken here and encoded on the save queue.
    func saveBlockEntities(_ m: [IVec3: BlockEntity], background: Bool = false) {
        var e: [String: BlockEntity] = [:]
        e.reserveCapacity(m.count)
        for (k, v) in m { e["\(k.x),\(k.y),\(k.z)"] = background ? v.snapshot() : v }
        SaveIO.write(BlockEntitySave(entries: e), to: blockEntityURL, background: background)
    }

    func loadPortals() -> [IVec3] {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("portals.json")),
              let a = try? JSONDecoder().decode([[Int]].self, from: d) else { return [] }
        return a.filter { $0.count == 3 }.map { IVec3($0[0], $0[1], $0[2]) }
    }

    func savePortals(_ p: [IVec3]) {
        SaveIO.storeJSON(p.map { [$0.x, $0.y, $0.z] }, to: dir.appendingPathComponent("portals.json"))
    }

    func chunkURL(_ k: ChunkKey) -> URL { chunkDir.appendingPathComponent("c.\(k.x).\(k.z).lz") }

    // Chunk file: lzfse( u32 paletteCount, palette names (u16 length + utf8), u16 palette index per block ).
    // Block names instead of raw IDs keep saves valid when the block registry grows.
    // Thread-safe: called from world worker threads.
    func loadChunk(_ k: ChunkKey) -> [BlockID]? {
        if let queued = SaveIO.pending(chunkURL(k).path) { return queued }     // written in the background, not on disk yet
        guard let d = try? Data(contentsOf: chunkURL(k)) else { return nil }
        guard var out = SaveManager.decodeBlocks([UInt8](d)) else {
            // S1: a chunk file that won't decode was regenerated from the seed and the next save wrote over the player's
            // building. It is kept as .corrupt beside the chunks.
            SaveIO.quarantine(chunkURL(k), what: "piece of the world (chunk \(k.x), \(k.z))")
            return nil
        }
        // (Old saves' floors and seals; a field world was made with them, and its floor is ground in its field.)
        if fieldWorld { return out }
        if overworldFloor { SaveManager.stripBedrockFloor(&out); HellGate.stamp(&out) }
        if deepSeal { DeepSeal.stamp(&out); AshFinal.stamp(&out, cx: k.x, cz: k.z) }
        return out
    }

    // The chunk file's bytes (also the co-op wire format, NetCoop.swift) to blocks, or nil.
    static func decodeBlocks(_ d: [UInt8]) -> [BlockID]? {
        guard let raw = try? (Data(d) as NSData).decompressed(using: .lzfse) as Data else { return nil }
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
            palette.append(SaveMigration.blockID(name) ?? AIR)
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

    static func stripBedrockFloor(_ b: inout [BlockID]) {
        for i in 0..<(CSQ * 5) where b[i] == BEDROCK { b[i] = EMBERSLATE }
    }

    // Queues a chunk write on the background save queue (the main thread only hands over the array).
    func saveChunkAsync(_ k: ChunkKey, _ blocks: BlockStore) {
        let url = chunkURL(k)
        SaveIO.enqueue(url.path, blocks) { [self] in
            saveChunk(k, blocks.rawFull())
            if blocks.isField { saveField(k, blocks.field) }        // PG1: the ground beside the built layer
        }
    }

    func saveChunk(_ k: ChunkKey, _ blocks: [BlockID]) {
        guard let c = SaveManager.encodeBlocks(blocks) else { SaveIO.report("Couldn't pack chunk \(k.x), \(k.z) for saving"); return }
        SaveIO.store(Data(c), to: chunkURL(k))
    }

    static func encodeBlocks(_ blocks: [BlockID]) -> [UInt8]? {
        // Palette through a flat table (block id -> palette index + 1) instead of a dictionary per block.
        var map = [UInt16](repeating: 0, count: max(Blocks.count, 1) + 1)
        var names: [String] = []
        var idx = [UInt16](repeating: 0, count: blocks.count)
        for i in 0..<blocks.count {
            let b = Int(blocks[i])
            if b < map.count, map[b] != 0 { idx[i] = map[b] - 1; continue }
            let m = UInt16(names.count)
            if b < map.count { map[b] = m + 1 }
            names.append(Blocks.saveKey(BlockID(b)))
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
        guard let c = try? (d as NSData).compressed(using: .lzfse) as Data else { return nil }
        return [UInt8](c)
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
        return queued[path]?.blocks.rawFull()
    }
    static func pendingStore(_ path: String) -> BlockStore? {
        lock.lock(); defer { lock.unlock() }
        return queued[path]?.blocks
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

    // S2 (store readiness: "save errors are shown to the player, not swallowed by try?"): problems noted here from any
    // thread; Game.tick hands them to the toast line (takeProblems), each message once a minute at most.
    private static var problems: [String] = []
    private static var lastSaid: [String: Double] = [:]
    static func report(_ msg: String) {
        print("save problem: " + msg)
        lock.lock(); defer { lock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        if let t = lastSaid[msg], now - t < 60 { return }
        lastSaid[msg] = now
        if problems.count < 8 { problems.append(msg) }
    }
    static func takeProblems() -> [String] {
        lock.lock(); defer { lock.unlock() }
        if problems.isEmpty { return [] }
        let p = problems
        problems.removeAll()
        return p
    }

    // S3: a write a dead battery can't half-finish: the bytes go to a temporary file beside the target, are flushed to
    // the storage (fsync) and only then renamed over it (one atomic step). A failure is reported (S2), never swallowed,
    // and the old file stays as it was.
    static func store(_ data: Data, to url: URL) {
        let tmp = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".tmp")
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: tmp.path) { try? fm.removeItem(at: tmp) }
            guard fm.createFile(atPath: tmp.path, contents: nil) else {
                throw NSError(domain: "save", code: 1, userInfo: [NSLocalizedDescriptionKey: "can't create a file (is the storage full?)"])
            }
            let h = try FileHandle(forWritingTo: tmp)
            h.write(data)
            h.synchronizeFile()
            h.closeFile()
            if rename(tmp.path, url.path) != 0 {
                throw NSError(domain: "save", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            report("Couldn't save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
    static func storeJSON<T: Encodable>(_ value: T, to url: URL, pretty: Bool = false) {
        let enc = encoder()
        if pretty { enc.outputFormatting = [.prettyPrinted, .sortedKeys] }
        do { store(try enc.encode(value), to: url) } catch { report("Couldn't encode \(url.lastPathComponent): \(error.localizedDescription)") }
    }

    // S1: a file that will not decode is kept beside the world as <name>.corrupt (the next save writes a fresh file;
    // the broken one is never overwritten) and the player is told.
    static func quarantine(_ url: URL, what: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        var dest = url.appendingPathExtension("corrupt")
        var n = 1
        while fm.fileExists(atPath: dest.path) { n += 1; dest = url.appendingPathExtension("corrupt\(n)") }
        do { try fm.moveItem(at: url, to: dest) } catch { report("A damaged \(what) couldn't be set aside: \(error.localizedDescription)"); return }
        report("A damaged \(what) was kept as \(dest.lastPathComponent); a backup is in the world's backups folder")
    }

    // S3: rolling snapshots of the world's small files (player, inventory, chests, mobs, ships, maps) in
    // <world>/backups/auto-1...3, newest first, taken at most every 5 minutes on the save queue after the files are
    // written. Chunks are left out (many, and regenerated or rewritten as they change).
    private static var lastSnapshot: [String: Double] = [:]
    static let snapshotFiles = ["world.json", "blockentities.json", "mobs.json", "ships.json", "maps.json", "populated.json",
                                "hives.json", "portals.json", "xporbs.json", "mapfog.json", "mapmarks.json"]
    static func snapshot(_ dir: URL) {
        let key = dir.standardizedFileURL.path
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let due = now - (lastSnapshot[key] ?? 0) > 300
        if due { lastSnapshot[key] = now }
        lock.unlock()
        guard due else { return }
        queue.async {
            let fm = FileManager.default
            let root = dir.appendingPathComponent("backups", isDirectory: true)
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
            let a3 = root.appendingPathComponent("auto-3"), a2 = root.appendingPathComponent("auto-2"), a1 = root.appendingPathComponent("auto-1")
            try? fm.removeItem(at: a3)
            try? fm.moveItem(at: a2, to: a3)
            try? fm.moveItem(at: a1, to: a2)
            let tmp = root.appendingPathComponent(".auto-new")
            try? fm.removeItem(at: tmp)
            do {
                try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
                for f in snapshotFiles where fm.fileExists(atPath: dir.appendingPathComponent(f).path) {
                    try fm.copyItem(at: dir.appendingPathComponent(f), to: tmp.appendingPathComponent(f))
                }
                try fm.moveItem(at: tmp, to: a1)
            } catch {
                report("Couldn't make the world's backup copy: \(error.localizedDescription)")
            }
        }
    }
    // The newest snapshot's copy of a file, if any (S1: a damaged world.json is read from it).
    static func latestBackup(_ dir: URL, _ file: String) -> URL? {
        for n in 1...3 {
            let u = dir.appendingPathComponent("backups/auto-\(n)/\(file)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    // F1: work for the save queue (encoding from value snapshots the frame thread no longer touches).
    static func run(_ work: @escaping () -> Void) { queue.async(execute: work) }
    // A value snapshot written as JSON: on the save queue (the autosave) or right here (quit, pause, world switch).
    static func write<T: Encodable>(_ value: T, to url: URL, background: Bool) {
        if background { writeJSON(value, to: url); return }
        storeJSON(value, to: url)
    }

    // Encodes and writes a value snapshot (structs only: nothing the frame thread keeps mutating) on the save queue,
    // after any chunk writes already queued. The autosave's JSON encoding ran on the frame thread: the Oct 9 Quest
    // playtest logged a ~190 ms tick once a minute, every minute.
    // P107 (Oct 12 PM, "a smooth world reloaded as blocks"): one infinite or NaN float (a position, the absorption) made
    // JSONEncoder throw, so world.json was silently never written and the world reopened as a new one (no terrain
    // option). Non-finite floats are written as strings and read back.
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL, pretty: Bool = false) {
        queue.async { storeJSON(value, to: url, pretty: pretty) }
    }
}
