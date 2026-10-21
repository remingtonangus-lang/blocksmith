import Foundation
import simd

// P376 step 2 (P375 step 3): past the active distance a chunk keeps only its finished mesh. Once a chunk two or more
// chunks past the active distance is meshed (and every neighbour whose mesh could still need its blocks is too), its
// block and field data and its stored light are dropped: it becomes a shell (Chunk.hollow) holding its section meshes,
// heights, tints and horizon-culling band. Edits are saved first. A shell that comes back within that distance, or
// whose blocks a neighbour's mesh or an edit needs, is refilled from its save or the seed on a worker (a far edit:
// at once); until a remesh its light reads from the heights (World.lightAt's fallback).
// While nothing ticks out there (FarTicks.swift) the only reads of a shell are long sight lines (a raycast, a
// shot): it reads as stone up to its heights.
// Meshes are also cached to disk (MeshCache): a chunk that leaves the view writes its meshes; a chunk inside the view
// but past that distance which is missing (a world loaded, a teleport, a respawn, flight outrunning the generator) is
// installed straight from its cached meshes as a shell, with no generation or meshing.
// Chunks hold no entity lists here: block entities live in one world table (saved as one file) and mobs in one list,
// frozen past the active distance and drawn in their last pose (P339).
extension World {
    static var shells = ProcessInfo.processInfo.environment["BS_SHELLS"] != "0"
    static var hollowed = 0, refilled = 0, fromCache = 0          // (harness tallies)

    // Chunks within this many (Chebyshev) of a player keep their data.
    var keepDataDistance: Int { min(activeDistance, renderDistance) + 2 }

    // Whether chunk offset (dx, dz) lies in the shell band: past the keep distance and two chunks inside the mesh disc
    // (the ring meshed next as the player moves needs the blocks of the chunks inside it).
    @inline(__always) func inShellBand(_ dx: Int, _ dz: Int) -> Bool {
        max(abs(dx), abs(dz)) > keepDataDistance && World.inDisc(abs(dx) + 2, abs(dz) + 2, renderDistance, grow: 0)
    }

    // Offsets of chunk k from the player and from a second player (co-op), the nearer one in Chebyshev distance.
    func shellOffset(_ k: ChunkKey) -> (Int, Int) {
        let c = ChunkKey(x: floorDiv(Int(floor(activeCenter.x)), CS), z: floorDiv(Int(floor(activeCenter.z)), CS))
        let a = (k.x - c.x, k.z - c.z)
        guard let e = extraCenter else { return a }
        let b = (k.x - floorDiv(Int(floor(e.x)), CS), k.z - floorDiv(Int(floor(e.z)), CS))
        return max(abs(b.0), abs(b.1)) < max(abs(a.0), abs(a.1)) ? b : a
    }

    // Drops the data of every finished chunk in the shell band; asks back the data of shells within the keep distance.
    func reshell() {
        guard World.shells else { return }
        var refill: [ChunkKey] = []
        for (k, c) in chunks {
            let (dx, dz) = shellOffset(k)
            if c.hollow {
                if max(abs(dx), abs(dz)) <= keepDataDistance || c.needsMesh { refill.append(k) }
                continue
            }
            guard inShellBand(dx, dz), c.meshedOnce, !c.needsMesh, !c.meshInFlight else { continue }
            // A neighbour still to mesh reads this chunk's blocks.
            var ready = true
            for nz in -1...1 { for nx in -1...1 where nx != 0 || nz != 0 {
                if let n = chunks[ChunkKey(x: k.x + nx, z: k.z + nz)], !n.hollow, n.needsMesh || n.meshInFlight { ready = false }
            } }
            guard ready else { continue }
            hollow(c, k)
        }
        for k in refill { requestRefill(k) }
    }

    private func hollow(_ c: Chunk, _ k: ChunkKey) {
        if c.modified || c.fieldDirty {
            guard let save else { return }                 // (an unsaved world keeps edited chunks whole)
            if c.needsSave { save.saveChunkAsync(k, c.blocks) }
            if c.fieldDirty { save.saveFieldEdits(k, c.fieldEdits); c.fieldDirty = false }
        }
        c.hollowOcc = c.occluderTop
        c.blocks = BlockStore([])
        c.markSaved()
        for i in c.light.indices { c.light[i] = nil }
        c.fieldEdits = [:]
        c.hollow = true
        World.hollowed += 1
    }

    // The data back, generated or loaded on a worker (World.update installs it into the shell).
    func requestRefill(_ k: ChunkKey) { startGen(k) }

    // At once (an edit reaching a shell).
    @discardableResult func refillNow(_ c: Chunk) -> Chunk {
        guard c.hollow else { return c }
        let k = ChunkKey(x: c.cx, z: c.cz)
        refill(c, produceNow(k))
        return c
    }

    func refill(_ c: Chunk, _ p: Produced) {
        guard c.hollow, p.cached == nil else { return }
        c.blocks = p.ground.map { BlockStore(p.blocks, field: $0) } ?? BlockStore(p.blocks)
        c.blocks.emitMask = p.emitMask
        if p.ground != nil { fieldStamp &+= 1 }
        c.fieldEdits = p.field
        c.modified = c.modified || p.fromDisk
        c.markSaved()
        c.hollow = false
        for t in p.tracked { redstone.tracked.insert(t) }
        for q in p.springs { if Blocks.fluidKind[Int(rawBlock(q.x, q.y, q.z))] == 2 { lavaPending.insert(q) } else { fluidPending.insert(q) } }
        World.refilled += 1
    }

    // A missing chunk in the shell band with cached meshes: installed from them (on a worker: read and decoded).
    func installShell(_ k: ChunkKey, _ e: MeshCache.Entry) {
        let c = Chunk(cx: k.x, cz: k.z, blocks: [], height: e.height, tint: e.tint)
        c.world = self
        c.blocks = BlockStore([])
        c.hollow = true
        c.hollowOcc = e.occ
        c.modified = e.modified
        c.markSaved()
        for (sy, m) in e.sections.enumerated() {
            let s = c.sections[sy]
            s.opaqueBuf = cacheBuffer(m.opaque)
            s.opaqueQuads = m.counts[0]; s.solidQuads = m.counts[1]; s.farSkip = m.counts[2]; s.farExtra = m.counts[3]
            s.transBuf = cacheBuffer(m.trans); s.transQuads = m.counts[4]
            s.detailBuf = cacheBuffer(m.detail); s.detailQuads = m.counts[5]; s.detailSolid = m.counts[6]
            s.naturalCubes = m.counts[7]; s.groundQuads = m.counts[8]; s.blobQuads = m.counts[9]; s.solidFull = m.counts[10] != 0
            s.vis = m.vis; s.leafy = m.leafy
            s.meshedVersion = s.version
        }
        c.meshedOnce = true
        c.updateTopSec()
        c.tintBuf = c.tint.withUnsafeBytes { MeshArena.tints.alloc(device, $0) }
        chunks[k] = c
        World.fromCache += 1
    }

    private func cacheBuffer(_ words: [UInt32]) -> MeshSlice? {
        words.isEmpty ? nil : words.withUnsafeBytes { MeshArena.shared.alloc(device, $0) }
    }

    // An unloading chunk's finished meshes go to the disk cache.
    func cacheMeshes(_ k: ChunkKey, _ c: Chunk) {
        guard World.shells, let mc = meshCache, c.meshedOnce, !c.needsMesh, !c.meshInFlight else { return }
        mc.write(k, c, occ: c.hollow ? c.hollowOcc : c.occluderTop)
    }
}

// The disk cache of section meshes (one file a chunk, in the save's meshcache folder). Versioned: the file starts
// with a stamp of the format, the build (the executable's date) and the block and texture registries, so a mesh
// from another build or registry is never drawn; a chunk edited after load drops its file, and an unloading chunk
// writes it fresh. Writes run on a background queue from the section buffers (kept alive until written). The folder
// is held under `capBytes` (oldest files go first).
final class MeshCache {
    static let format: UInt32 = 3                       // 2: P381 adaptive ground; 3: P383 per-position ground vertices
    static let capBytes = 768 << 20
    let dir: URL
    private let queue = DispatchQueue(label: "meshcache", qos: .utility)
    private let lock = NSLock()
    private var have = Set<ChunkKey>()
    private var bytes = 0
    let stamp: UInt64

    struct SectionData {
        var opaque: [UInt32] = [], trans: [UInt32] = [], detail: [UInt32] = []
        var counts = [Int](repeating: 0, count: 11)
        var vis: UInt64 = ~0, leafy = true
    }
    struct Entry {
        var height: [Int16], tint: [UInt32], occ: Int, modified: Bool
        var sections: [SectionData]
    }

    init?(saveDir: URL) {
        dir = saveDir.appendingPathComponent("meshcache", isDirectory: true)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { return nil }
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        mix(UInt64(MeshCache.format)); mix(AdaptiveGround.enabled ? 1 : 0); mix(UInt64(Blocks.count)); mix(UInt64(Tex.count))
        for n in Tex.names { for b in n.utf8 { mix(UInt64(b)) } }
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        if let d = (try? FileManager.default.attributesOfItem(atPath: exe.path))?[.modificationDate] as? Date { mix(UInt64(d.timeIntervalSince1970)) }
        mix(UInt64(bitPattern: Int64(SectionMesh.layoutStamp)))
        stamp = h
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for f in files {
            let parts = f.lastPathComponent.split(separator: ".")
            guard parts.count == 4, parts[0] == "m", let x = Int(parts[1]), let z = Int(parts[2]) else { continue }
            have.insert(ChunkKey(x: x, z: z))
            bytes += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
    }

    func url(_ k: ChunkKey) -> URL { dir.appendingPathComponent("m.\(k.x).\(k.z).bin") }
    func has(_ k: ChunkKey) -> Bool { lock.lock(); defer { lock.unlock() }; return have.contains(k) }

    func drop(_ k: ChunkKey) {
        lock.lock()
        let had = have.remove(k) != nil
        lock.unlock()
        if had { let u = url(k); queue.async { try? FileManager.default.removeItem(at: u) } }
    }

    func write(_ k: ChunkKey, _ c: Chunk, occ: Int) {
        // The buffers stay alive in this closure until written (their slab space is reused only after).
        let secs = c.sections.map { s in (s.opaqueBuf, s.transBuf, s.detailBuf,
                                          [s.opaqueQuads, s.solidQuads, s.farSkip, s.farExtra, s.transQuads, s.detailQuads, s.detailSolid,
                                           s.naturalCubes, s.groundQuads, s.blobQuads, s.solidFull ? 1 : 0], s.vis, s.leafy) }
        let height = c.height, tint = c.tint, modified = c.modified
        let u = url(k), stamp = self.stamp
        lock.lock(); have.insert(k); lock.unlock()
        queue.async { [self] in
            var d = [UInt8]()
            d.reserveCapacity(64 << 10)
            func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
            func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
            func slice(_ m: MeshSlice?) {
                guard let m else { u32(0); return }
                u32(UInt32(m.length / 4))
                let p = UnsafeRawBufferPointer(start: m.buffer.contents() + m.offset, count: m.length)
                d.append(contentsOf: p)
            }
            u32(0x4D43_5342); u64(stamp)                      // "BSCM", stamp
            u32(UInt32(bitPattern: Int32(occ))); u32(modified ? 1 : 0)
            height.withUnsafeBytes { d.append(contentsOf: $0) }
            tint.withUnsafeBytes { d.append(contentsOf: $0) }
            u32(UInt32(secs.count))
            for (o, t, de, counts, vis, leafy) in secs {
                for n in counts { u32(UInt32(n)) }
                u64(vis); u32(leafy ? 1 : 0)
                slice(o); slice(t); slice(de)
            }
            do { try Data(d).write(to: u, options: .atomic) } catch { lock.lock(); have.remove(k); lock.unlock(); return }
            lock.lock(); bytes += d.count; let over = bytes > MeshCache.capBytes; lock.unlock()
            if over { trim() }
        }
    }

    // Oldest files go until the folder is three quarters of the cap.
    private func trim() {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? [])
            .map { f -> (URL, Date, Int) in
                let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return (f, v?.contentModificationDate ?? .distantPast, v?.fileSize ?? 0)
            }.sorted { $0.1 < $1.1 }
        var total = files.reduce(0) { $0 + $1.2 }
        for (f, _, n) in files where total > MeshCache.capBytes * 3 / 4 {
            try? fm.removeItem(at: f)
            total -= n
            let parts = f.lastPathComponent.split(separator: ".")
            if parts.count == 4, let x = Int(parts[1]), let z = Int(parts[2]) { lock.lock(); have.remove(ChunkKey(x: x, z: z)); lock.unlock() }
        }
        lock.lock(); bytes = total; lock.unlock()
    }

    // Worker side: the file decoded, or nil (missing, another build, damaged: dropped).
    func read(_ k: ChunkKey) -> Entry? {
        guard let data = try? Data(contentsOf: url(k)) else { drop(k); return nil }
        let b = [UInt8](data)
        var p = 0
        func u32() -> UInt32? {
            guard p + 4 <= b.count else { return nil }
            defer { p += 4 }
            return UInt32(b[p]) | UInt32(b[p + 1]) << 8 | UInt32(b[p + 2]) << 16 | UInt32(b[p + 3]) << 24
        }
        func u64() -> UInt64? { guard let lo = u32(), let hi = u32() else { return nil }; return UInt64(lo) | UInt64(hi) << 32 }
        func words(_ n: Int) -> [UInt32]? {
            guard n >= 0, p + n * 4 <= b.count else { return nil }
            var w = [UInt32](repeating: 0, count: n)
            w.withUnsafeMutableBytes { dst in b.withUnsafeBytes { src in dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[p..<(p + n * 4)])) } }
            p += n * 4
            return w
        }
        func fail() -> Entry? { drop(k); return nil }
        guard u32() == 0x4D43_5342, u64() == stamp, let occ = u32(), let mod = u32() else { return fail() }
        guard p + CSQ * 2 + CSQ * 3 * 4 <= b.count else { return fail() }
        var height = [Int16](repeating: 0, count: CSQ)
        height.withUnsafeMutableBytes { dst in b.withUnsafeBytes { src in dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[p..<(p + CSQ * 2)])) } }
        p += CSQ * 2
        guard let tint = words(CSQ * 3), let n = u32(), Int(n) == NSEC else { return fail() }
        var secs: [SectionData] = []
        for _ in 0..<NSEC {
            var s = SectionData()
            for i in 0..<11 { guard let v = u32() else { return fail() }; s.counts[i] = Int(v) }
            guard let vis = u64(), let lf = u32() else { return fail() }
            s.vis = vis; s.leafy = lf != 0
            guard let a = u32(), let o = words(Int(a)), let bn = u32(), let t = words(Int(bn)), let cn = u32(), let de = words(Int(cn)) else { return fail() }
            s.opaque = o; s.trans = t; s.detail = de
            secs.append(s)
        }
        return Entry(height: height, tint: tint, occ: Int(Int32(bitPattern: occ)), modified: mod != 0, sections: secs)
    }
}

extension SectionMesh {
    // Bumped whenever the vertex layout or a Section field the cache stores changes (MeshCache stamp).
    static let layoutStamp = 0x376_0002
}
