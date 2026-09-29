import Foundation
import Metal

// Owns all loaded chunks. Generation and meshing run on a concurrent background queue;
// results are applied on the main thread in update(). Chunk block arrays are Swift
// copy-on-write values, so handing snapshots to worker threads is safe.
final class World {
    let gen: WorldGen
    let seed: UInt64
    let device: MTLDevice
    let save: SaveManager?
    var chunks: [ChunkKey: Chunk] = [:]
    var renderDistance: Int = 8 { didSet { lastCenter = nil; rebuildOffsets() } }

    private let workQueue = DispatchQueue(label: "blocksmith.world", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private var genResults: [(ChunkKey, [UInt8], Bool)] = []
    private var meshResults: [(ChunkKey, Int, MeshData)] = []
    private var genInFlight = Set<ChunkKey>()
    private var jobs = 0
    let maxJobs: Int
    private var lastCenter: ChunkKey?
    private var offsets: [(Int, Int, Int)] = [] // dx, dz, dist2 sorted by distance (square R+1)

    // Stats for the debug overlay
    private(set) var meshedCount = 0
    var pendingJobs: Int { jobs }

    init(seed: UInt64, device: MTLDevice, save: SaveManager?) {
        self.seed = seed
        self.gen = WorldGen(seed: seed)
        self.device = device
        self.save = save
        maxJobs = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
        rebuildOffsets()
    }

    private func rebuildOffsets() {
        let r = renderDistance + 1
        var o: [(Int, Int, Int)] = []
        for dz in -r...r { for dx in -r...r { o.append((dx, dz, dx * dx + dz * dz)) } }
        o.sort { $0.2 < $1.2 }
        offsets = o
    }

    @inline(__always) func inMeshRadius(_ dx: Int, _ dz: Int) -> Bool {
        dx * dx + dz * dz <= renderDistance * renderDistance + renderDistance
    }

    // MARK: Block access

    func block(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        if y < 0 { return BEDROCK }
        if y >= CH { return AIR }
        guard let c = chunks[ChunkKey(x: floorDiv(x, CS), z: floorDiv(z, CS))] else { return AIR }
        return c.blocks[Chunk.index(mod(x, CS), y, mod(z, CS))]
    }

    func isLoaded(_ x: Int, _ z: Int) -> Bool {
        chunks[ChunkKey(x: floorDiv(x, CS), z: floorDiv(z, CS))] != nil
    }

    func setBlock(_ x: Int, _ y: Int, _ z: Int, _ id: UInt8) {
        guard y >= 0 && y < CH else { return }
        let cx = floorDiv(x, CS), cz = floorDiv(z, CS)
        guard let c = chunks[ChunkKey(x: cx, z: cz)] else { return }
        let lx = mod(x, CS), lz = mod(z, CS)
        c.blocks[Chunk.index(lx, y, lz)] = id
        c.modified = true
        var dirty = [c]
        // Neighbours sample our edge for culling, AO (diagonals) and skylight.
        let ex = lx == 0 ? -1 : (lx == CS - 1 ? 1 : 0)
        let ez = lz == 0 ? -1 : (lz == CS - 1 ? 1 : 0)
        if ex != 0, let n = chunks[ChunkKey(x: cx + ex, z: cz)] { dirty.append(n) }
        if ez != 0, let n = chunks[ChunkKey(x: cx, z: cz + ez)] { dirty.append(n) }
        if ex != 0 && ez != 0, let n = chunks[ChunkKey(x: cx + ex, z: cz + ez)] { dirty.append(n) }
        for d in dirty {
            d.meshVersion += 1
            remeshSync(d)
        }
    }

    // MARK: Meshing helpers

    private func neighbourhood(_ c: Chunk) -> [[UInt8]]? {
        var n9: [[UInt8]] = []
        n9.reserveCapacity(9)
        for dz in -1...1 {
            for dx in -1...1 {
                if dx == 0 && dz == 0 { n9.append(c.blocks); continue }
                guard let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)] else { return nil }
                n9.append(n.blocks)
            }
        }
        return n9
    }

    private func remeshSync(_ c: Chunk) {
        guard let n9 = neighbourhood(c) else { return }
        apply(Mesher.build(n9), to: c, version: c.meshVersion)
    }

    private func makeBuffer(_ words: [UInt32]) -> MTLBuffer? {
        if words.isEmpty { return nil }
        return words.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }

    private func apply(_ m: MeshData, to c: Chunk, version: Int) {
        c.opaqueBuf = makeBuffer(m.opaque)
        c.opaqueQuads = m.opaque.count / 8
        c.waterBuf = makeBuffer(m.water)
        c.waterQuads = m.water.count / 8
        c.minY = Float(min(m.minY, m.maxY))
        c.maxY = Float(m.maxY)
        c.meshedVersion = version
    }

    // MARK: Streaming (call once per frame)

    func update(center pos: V3) {
        let center = ChunkKey(x: floorDiv(Int(floor(pos.x)), CS), z: floorDiv(Int(floor(pos.z)), CS))

        lock.lock()
        let gr = genResults; genResults.removeAll(keepingCapacity: true)
        let mr = meshResults; meshResults.removeAll(keepingCapacity: true)
        lock.unlock()

        for (k, blocks, fromDisk) in gr {
            genInFlight.remove(k)
            jobs -= 1
            if chunks[k] != nil { continue }
            let c = Chunk(cx: k.x, cz: k.z, blocks: blocks)
            c.modified = fromDisk
            chunks[k] = c
        }
        for (k, version, mesh) in mr {
            jobs -= 1
            guard let c = chunks[k] else { continue }
            c.meshInFlight = false
            if version == c.meshVersion { apply(mesh, to: c, version: version) }
        }

        if center != lastCenter {
            lastCenter = center
            let limit = renderDistance + 2
            var gone: [ChunkKey] = []
            for (k, c) in chunks where abs(k.x - center.x) > limit || abs(k.z - center.z) > limit {
                if c.modified { save?.saveChunk(k, c.blocks) }
                gone.append(k)
            }
            for k in gone { chunks.removeValue(forKey: k) }
        }

        // Nearest-first scheduling: generate missing chunks, mesh chunks whose 8 neighbours exist.
        var meshed = 0
        for (dx, dz, _) in offsets {
            let k = ChunkKey(x: center.x + dx, z: center.z + dz)
            if let c = chunks[k] {
                if c.meshedVersion >= 0 { meshed += 1 }
                if jobs >= maxJobs { continue }
                if c.needsMesh && !c.meshInFlight && inMeshRadius(dx, dz), let n9 = neighbourhood(c) {
                    c.meshInFlight = true
                    jobs += 1
                    let version = c.meshVersion
                    workQueue.async { [self] in
                        let m = Mesher.build(n9)
                        lock.lock(); meshResults.append((k, version, m)); lock.unlock()
                    }
                }
            } else if jobs < maxJobs && !genInFlight.contains(k) {
                genInFlight.insert(k)
                jobs += 1
                workQueue.async { [self] in
                    var fromDisk = false
                    let blocks: [UInt8]
                    if let saved = save?.loadChunk(k) { blocks = saved; fromDisk = true }
                    else { blocks = gen.generate(cx: k.x, cz: k.z) }
                    lock.lock(); genResults.append((k, blocks, fromDisk)); lock.unlock()
                }
            }
        }
        meshedCount = meshed
    }

    // Blocking load of everything around a point (used by --snapshot and first spawn).
    func loadSync(center pos: V3, radius: Int) -> (gen: Double, mesh: Double) {
        let cx = floorDiv(Int(floor(pos.x)), CS), cz = floorDiv(Int(floor(pos.z)), CS)
        let r = radius + 1
        var keys: [ChunkKey] = []
        for dz in -r...r { for dx in -r...r {
            let k = ChunkKey(x: cx + dx, z: cz + dz)
            if chunks[k] == nil { keys.append(k) }
        } }
        let t0 = CFAbsoluteTimeGetCurrent()
        let res = UnsafeMutablePointer<[UInt8]>.allocate(capacity: max(1, keys.count))
        let disk = UnsafeMutablePointer<Bool>.allocate(capacity: max(1, keys.count))
        defer { res.deallocate(); disk.deallocate() }
        let g = gen, sv = save
        DispatchQueue.concurrentPerform(iterations: keys.count) { i in
            let k = keys[i]
            if let s = sv?.loadChunk(k) { (res + i).initialize(to: s); disk[i] = true }
            else { (res + i).initialize(to: g.generate(cx: k.x, cz: k.z)); disk[i] = false }
        }
        for (i, k) in keys.enumerated() {
            let c = Chunk(cx: k.x, cz: k.z, blocks: (res + i).move())
            c.modified = disk[i]
            chunks[k] = c
        }
        let t1 = CFAbsoluteTimeGetCurrent()

        var toMesh: [(Chunk, [[UInt8]])] = []
        for dz in -radius...radius { for dx in -radius...radius where inMeshRadius(dx, dz) {
            if let c = chunks[ChunkKey(x: cx + dx, z: cz + dz)], c.needsMesh, let n9 = neighbourhood(c) {
                toMesh.append((c, n9))
            }
        } }
        let meshes = UnsafeMutablePointer<MeshData>.allocate(capacity: max(1, toMesh.count))
        defer { meshes.deallocate() }
        DispatchQueue.concurrentPerform(iterations: toMesh.count) { i in
            (meshes + i).initialize(to: Mesher.build(toMesh[i].1))
        }
        for (i, (c, _)) in toMesh.enumerated() { apply((meshes + i).move(), to: c, version: c.meshVersion) }
        let t2 = CFAbsoluteTimeGetCurrent()
        return (t1 - t0, t2 - t1)
    }

    func saveAll() {
        for (k, c) in chunks where c.modified { save?.saveChunk(k, c.blocks) }
    }

    // MARK: Raycast (voxel DDA). Returns the first targetable block and the face normal hit.

    func raycast(_ origin: V3, _ dir: V3, maxDist: Float) -> (hit: IVec3, normal: IVec3)? {
        var x = Int(floor(origin.x)), y = Int(floor(origin.y)), z = Int(floor(origin.z))
        let sx = dir.x > 0 ? 1 : -1, sy = dir.y > 0 ? 1 : -1, sz = dir.z > 0 ? 1 : -1
        let inf = Float.greatestFiniteMagnitude
        let tdx = dir.x != 0 ? abs(1 / dir.x) : inf
        let tdy = dir.y != 0 ? abs(1 / dir.y) : inf
        let tdz = dir.z != 0 ? abs(1 / dir.z) : inf
        func first(_ o: Float, _ d: Float, _ i: Int) -> Float {
            if d == 0 { return inf }
            return d > 0 ? (Float(i + 1) - o) / d : (o - Float(i)) / -d
        }
        var tmx = first(origin.x, dir.x, x), tmy = first(origin.y, dir.y, y), tmz = first(origin.z, dir.z, z)
        var n = IVec3(0, 0, 0)
        var t: Float = 0
        let kind = Blocks.kind
        while t <= maxDist {
            let b = block(x, y, z)
            let k = kind[Int(b)]
            if k == BlockKind.solid.rawValue || k == BlockKind.cutout.rawValue {
                return (IVec3(x, y, z), n)
            }
            if tmx < tmy && tmx < tmz {
                x += sx; t = tmx; tmx += tdx; n = IVec3(-sx, 0, 0)
            } else if tmy < tmz {
                y += sy; t = tmy; tmy += tdy; n = IVec3(0, -sy, 0)
            } else {
                z += sz; t = tmz; tmz += tdz; n = IVec3(0, 0, -sz)
            }
            if y < -1 || y > CH { return nil }
        }
        return nil
    }
}
