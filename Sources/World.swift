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
        scheduleFluid(around: IVec3(x, y, z))
        // Light spreads up to 15 blocks, so every neighbour may change: remesh the rest in the background.
        for dz in -1...1 {
            for dx in -1...1 where dx != 0 || dz != 0 {
                guard let n = chunks[ChunkKey(x: cx + dx, z: cz + dz)] else { continue }
                if !dirty.contains(where: { $0 === n }) { n.meshVersion += 1 }
            }
        }
    }

    // Fast path for bulk edits (fluids): no synchronous remesh; the chunk (and the neighbours whose
    // border it touches) are re-meshed by the background scheduler. Returns false if not loaded.
    @discardableResult
    func setBlockAsync(_ x: Int, _ y: Int, _ z: Int, _ id: UInt8) -> Bool {
        guard y >= 0 && y < CH else { return false }
        let cx = floorDiv(x, CS), cz = floorDiv(z, CS)
        guard let c = chunks[ChunkKey(x: cx, z: cz)] else { return false }
        let lx = mod(x, CS), lz = mod(z, CS)
        c.blocks[Chunk.index(lx, y, lz)] = id
        c.modified = true
        c.meshVersion += 1
        let ex = lx == 0 ? -1 : (lx == CS - 1 ? 1 : 0)
        let ez = lz == 0 ? -1 : (lz == CS - 1 ? 1 : 0)
        if ex != 0 { chunks[ChunkKey(x: cx + ex, z: cz)]?.meshVersion += 1 }
        if ez != 0 { chunks[ChunkKey(x: cx, z: cz + ez)]?.meshVersion += 1 }
        if ex != 0 && ez != 0 { chunks[ChunkKey(x: cx + ex, z: cz + ez)]?.meshVersion += 1 }
        return true
    }

    // MARK: Fluids
    // Cellular water: sources (level 0) feed flowing water 1...7 sideways, falling columns (8) downwards.
    // Only cells near a change are simulated: edits enqueue themselves + neighbours, and every cell
    // that changes during a tick enqueues its neighbours for the next one.

    private(set) var fluidPending = Set<IVec3>()
    static let fluidBudget = 1024
    private static let sideDirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]

    func scheduleFluid(around p: IVec3) {
        let lv = Blocks.fluidLevel
        var any = lv[Int(block(p.x, p.y, p.z))] >= 0
        if !any {
            for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
                let q = p + d
                if lv[Int(block(q.x, q.y, q.z))] >= 0 { any = true; break }
            }
        }
        if !any { return }
        fluidPending.insert(p)
        for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
            fluidPending.insert(p + d)
        }
    }

    // Water may replace air, plants/torches and thinner flowing water.
    private func fluidCanEnter(_ id: UInt8, level: Int) -> Bool {
        if id == AIR || Blocks.isPlant(id) { return true }
        let l = Int(Blocks.fluidLevel[Int(id)])
        return l > 0 && l < 8 && l > level
    }

    private func setFluid(_ p: IVec3, _ id: UInt8) {
        if setBlockAsync(p.x, p.y, p.z, id) { scheduleFluid(around: p) }
    }

    func fluidTick() {
        if fluidPending.isEmpty { return }
        var batch: [IVec3] = []
        batch.reserveCapacity(min(fluidPending.count, World.fluidBudget))
        for p in fluidPending {
            batch.append(p)
            if batch.count >= World.fluidBudget { break }
        }
        for p in batch { fluidPending.remove(p) }
        let lvT = Blocks.fluidLevel
        for p in batch {
            guard p.y >= 0 && p.y < CH && isLoaded(p.x, p.z) else { continue }
            var lv = Int(lvT[Int(block(p.x, p.y, p.z))])
            if lv < 0 { continue }
            if lv > 0 {
                // Re-derive what this non-source cell should be from its surroundings.
                var want: Int
                if lvT[Int(block(p.x, p.y + 1, p.z))] >= 0 {
                    want = 8
                } else {
                    var best = 99, sources = 0
                    for d in World.sideDirs {
                        let n = Int(lvT[Int(block(p.x + d.x, p.y, p.z + d.z))])
                        if n < 0 { continue }
                        if n == 0 { sources += 1 }
                        best = min(best, n == 8 ? 0 : n)
                    }
                    let below = block(p.x, p.y - 1, p.z)
                    if sources >= 2 && (Blocks.opaque[Int(below)] || lvT[Int(below)] == 0) { want = 0 }
                    else if best >= 7 { want = -1 }
                    else { want = best + 1 }
                }
                if want != lv {
                    setFluid(p, want < 0 ? AIR : (want == 8 ? WATER_FALL : WATER_FLOW[want]))
                    if want < 0 { continue }
                    lv = want
                }
            }
            // Spread: fall if possible, otherwise flow sideways (only when standing on something solid).
            let below = block(p.x, p.y - 1, p.z)
            if p.y > 0 && (below == AIR || Blocks.isPlant(below) || (lvT[Int(below)] > 0 && lvT[Int(below)] < 8)) {
                setFluid(IVec3(p.x, p.y - 1, p.z), WATER_FALL)
                continue
            }
            if lvT[Int(below)] >= 0 { continue }
            let next = (lv == 8 ? 0 : lv) + 1
            if next > 7 { continue }
            for d in World.sideDirs {
                let q = IVec3(p.x + d.x, p.y, p.z + d.z)
                if fluidCanEnter(block(q.x, q.y, q.z), level: next) { setFluid(q, WATER_FLOW[next]) }
            }
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
        while t <= maxDist {
            let b = block(x, y, z)
            if Blocks.targetable(b) { return (IVec3(x, y, z), n) }
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
