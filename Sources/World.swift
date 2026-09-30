import Foundation
import Metal
import simd

// Owns all loaded chunks of one dimension. Generation and meshing run on a concurrent background
// queue; results are applied on the main thread in update(). Chunk block arrays are Swift
// copy-on-write values, so handing snapshots to worker threads is safe.
final class World {
    let gen: TerrainGenerator
    let dim: Dim
    let seed: UInt64
    let device: MTLDevice
    let save: SaveManager?
    var chunks: [ChunkKey: Chunk] = [:]
    var blockEntities: [IVec3: BlockEntity] = [:]
    var portals = Set<IVec3>()
    var renderDistance: Int = 8 { didSet { lastCenter = nil; rebuildOffsets() } }

    private let workQueue = DispatchQueue(label: "blocksmith.world", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private var genResults: [(ChunkKey, Produced)] = []
    private var meshResults: [(ChunkKey, [(Int, Int, SectionMesh)])] = []
    private var genInFlight = Set<ChunkKey>()
    private var jobs = 0
    let maxJobs: Int
    private var lastCenter: ChunkKey?
    private var offsets: [(Int, Int, Int)] = []

    private(set) var meshedCount = 0
    var pendingJobs: Int { jobs }

    init(seed: UInt64, device: MTLDevice, save: SaveManager?, dim: Dim = .overworld) {
        self.seed = seed
        self.dim = dim
        switch dim {
        case .overworld: gen = WorldGen(seed: seed)
        case .nether: gen = NetherGen(seed: seed)
        case .end: gen = EndGen(seed: seed)
        }
        self.device = device
        self.save = save
        maxJobs = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
        rebuildOffsets()
        blockEntities = save?.loadBlockEntities() ?? [:]
        portals = Set(save?.loadPortals() ?? [])
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

    @inline(__always) func chunkAt(_ x: Int, _ z: Int) -> Chunk? {
        chunks[ChunkKey(x: floorDiv(x, CS), z: floorDiv(z, CS))]
    }

    func block(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        if y < 0 { return BEDROCK }
        if y >= CH { return AIR }
        guard let c = chunkAt(x, z) else { return AIR }
        return c.blocks[Chunk.index(mod(x, CS), y, mod(z, CS))]
    }

    func isLoaded(_ x: Int, _ z: Int) -> Bool { chunkAt(x, z) != nil }

    // Light at a block: (sky 0-15, block 0-15). Uses the mesher's stored light when available,
    // otherwise approximates from the heightmap.
    func lightAt(_ x: Int, _ y: Int, _ z: Int) -> (sky: Int, block: Int) {
        if y >= CH { return (15, 0) }
        if y < 0 { return (0, 0) }
        guard let c = chunkAt(x, z) else { return (15, 0) }
        let lx = mod(x, CS), lz = mod(z, CS)
        if c.lightValid[y >> 4] {
            let l = c.light[Chunk.index(lx, y, lz)]
            return (Int(l >> 4), Int(l & 15))
        }
        return (y > Int(c.height[lx + lz * CS]) ? 15 : 0, 0)
    }

    func topY(_ x: Int, _ z: Int) -> Int {
        guard let c = chunkAt(x, z) else { return -1 }
        return Int(c.height[mod(x, CS) + mod(z, CS) * CS])
    }

    // Changes a block and remeshes: the sections around the block synchronously (no holes, correct
    // AO), everything its light could reach in the background.
    func setBlock(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
        guard y >= 0 && y < CH, let c = chunkAt(x, z) else { return }
        let lx = mod(x, CS), lz = mod(z, CS)
        let oldH = Int(c.height[lx + lz * CS])
        c.blocks[Chunk.index(lx, y, lz)] = id
        c.modified = true
        c.recomputeHeight(lx, lz)
        let newH = Int(c.height[lx + lz * CS])
        var sync: [(Chunk, Int)] = []
        for dz in -1...1 {
            for dx in -1...1 {
                for dy in -1...1 {
                    let yy = y + dy
                    guard yy >= 0 && yy < CH, let n = chunkAt(x + dx, z + dz) else { continue }
                    let sy = yy >> 4
                    if !sync.contains(where: { $0.0 === n && $0.1 == sy }) { sync.append((n, sy)) }
                }
            }
        }
        for (n, sy) in sync {
            n.sections[sy].version += 1
            remeshSync(n, sy)
        }
        let lo = max(0, (min(y, oldH, newH) - 16) >> 4), hi = min(NSEC - 1, (max(y, oldH, newH) + 16) >> 4)
        let cx = floorDiv(x, CS), cz = floorDiv(z, CS)
        for dz in -1...1 {
            for dx in -1...1 {
                guard let n = chunks[ChunkKey(x: cx + dx, z: cz + dz)] else { continue }
                for sy in lo...hi where !sync.contains(where: { $0.0 === n && $0.1 == sy }) {
                    n.sections[sy].version += 1
                }
            }
        }
        scheduleFluid(around: IVec3(x, y, z))
    }

    // Bulk edits (fluids): no synchronous remesh; the surrounding sections re-mesh in the background.
    @discardableResult
    func setBlockAsync(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) -> Bool {
        guard y >= 0 && y < CH, let c = chunkAt(x, z) else { return false }
        let lx = mod(x, CS), lz = mod(z, CS)
        c.blocks[Chunk.index(lx, y, lz)] = id
        c.modified = true
        c.recomputeHeight(lx, lz)
        for dz in -1...1 {
            for dx in -1...1 {
                guard let n = chunkAt(x + dx * 16, z + dz * 16) else { continue }
                for sy in max(0, (y - 16) >> 4)...min(NSEC - 1, (y + 16) >> 4) { n.sections[sy].version += 1 }
            }
        }
        return true
    }

    // MARK: Collision (shared by the player, mobs and items)

    // World-space collision boxes of the block at a cell.
    @inline(__always) func collisionBoxes(_ x: Int, _ y: Int, _ z: Int, _ out: inout [(V3, V3)]) {
        let b = Int(block(x, y, z))
        if !Blocks.collide[b] { return }
        let o = V3(Float(x), Float(y), Float(z))
        if Blocks.fullCollide[b] { out.append((o, o + 1)); return }
        for bx in shapeBoxes(x, y, z, BlockID(b), collision: true) { out.append((o + bx.minV, o + bx.maxV)) }
    }

    // Model boxes of a block, resolving connecting blocks (fences, panes, walls) from their neighbours.
    func shapeBoxes(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID, collision: Bool) -> [Box] {
        let ck = Blocks.connectKind[Int(b)]
        if ck == 0 { return Blocks.boxes[Int(b)] }
        return BlockRegistry.connectBoxes(ck, n: Blocks.connects(ck, block(x, y, z - 1)), s: Blocks.connects(ck, block(x, y, z + 1)),
                                          w: Blocks.connects(ck, block(x - 1, y, z)), e: Blocks.connects(ck, block(x + 1, y, z)), collision: collision)
    }

    func collides(_ mn: V3, _ mx: V3) -> Bool {
        let eps: Float = 1e-4
        var boxes: [(V3, V3)] = []
        for y in Int(floor(mn.y))...Int(floor(mx.y - eps)) {
            for z in Int(floor(mn.z))...Int(floor(mx.z - eps)) {
                for x in Int(floor(mn.x))...Int(floor(mx.x - eps)) {
                    boxes.removeAll(keepingCapacity: true)
                    collisionBoxes(x, y, z, &boxes)
                    for (a, b) in boxes where a.x < mx.x - eps && b.x > mn.x + eps && a.y < mx.y - eps && b.y > mn.y + eps && a.z < mx.z - eps && b.z > mn.z + eps {
                        return true
                    }
                }
            }
        }
        return false
    }

    // How far an AABB can move along one axis (0 x, 1 y, 2 z) before touching a collision box.
    func sweep(_ mn: V3, _ mx: V3, axis a: Int, _ d: Float) -> Float {
        if d == 0 { return 0 }
        var lo = mn, hi = mx
        if d > 0 { hi[a] += d } else { lo[a] += d }
        let eps: Float = 1e-4
        var boxes: [(V3, V3)] = []
        for y in Int(floor(lo.y - 0.5))...Int(floor(hi.y)) {   // -0.5: fences etc. poke up to 1.5
            for z in Int(floor(lo.z))...Int(floor(hi.z - eps)) {
                for x in Int(floor(lo.x))...Int(floor(hi.x - eps)) {
                    collisionBoxes(x, y, z, &boxes)
                }
            }
        }
        var dd = d
        let b1 = (a + 1) % 3, b2 = (a + 2) % 3
        for (bmn, bmx) in boxes {
            if bmn[b1] >= mx[b1] - eps || bmx[b1] <= mn[b1] + eps { continue }
            if bmn[b2] >= mx[b2] - eps || bmx[b2] <= mn[b2] + eps { continue }
            if dd > 0 && bmn[a] >= mx[a] - eps { dd = min(dd, bmn[a] - mx[a]) }
            if dd < 0 && bmx[a] <= mn[a] + eps { dd = max(dd, bmx[a] - mn[a]) }
        }
        return dd
    }

    // Moves a body (feet-centred AABB) by delta with collision and optional step-up.
    // Returns which axes were blocked.
    func moveBody(_ pos: inout V3, halfW: Float, height: Float, _ delta: V3, step: Float, onGround: Bool) -> (x: Bool, y: Bool, z: Bool) {
        func box(_ p: V3) -> (V3, V3) { (V3(p.x - halfW, p.y, p.z - halfW), V3(p.x + halfW, p.y + height, p.z + halfW)) }
        func attempt(_ start: V3, _ d: V3) -> (V3, Bool, Bool, Bool) {
            var p = start
            var (mn, mx) = box(p)
            let dy = sweep(mn, mx, axis: 1, d.y)
            p.y += dy; (mn, mx) = box(p)
            let dx = sweep(mn, mx, axis: 0, d.x)
            p.x += dx; (mn, mx) = box(p)
            let dz = sweep(mn, mx, axis: 2, d.z)
            p.z += dz
            return (p, abs(dx - d.x) > 1e-5, abs(dy - d.y) > 1e-5, abs(dz - d.z) > 1e-5)
        }
        // Sub-step so the swept region stays small.
        let steps = max(1, Int(ceil(max(abs(delta.x), abs(delta.y), abs(delta.z)) / 0.9)))
        var bx = false, by = false, bz = false
        let sd = delta / Float(steps)
        for _ in 0..<steps {
            var (p, hx, hy, hz) = attempt(pos, sd)
            if step > 0 && (hx || hz) && (onGround || (hy && sd.y < 0)) {
                // Try stepping up (slabs, stairs): lift, move horizontally, drop back down.
                let up = sweep(box(pos).0, box(pos).1, axis: 1, step)
                var lifted = pos
                lifted.y += up
                let (p2, hx2, _, hz2) = attempt(lifted, V3(sd.x, 0, sd.z))
                let (mn2, mx2) = box(p2)
                let down = sweep(mn2, mx2, axis: 1, -up - max(0, -sd.y))
                var p3 = p2
                p3.y += down
                let gain = simd_length(V2(p3.x - pos.x, p3.z - pos.z)) - simd_length(V2(p.x - pos.x, p.z - pos.z))
                if gain > 1e-4 { p = p3; hx = hx2; hz = hz2; hy = true }
            }
            pos = p
            bx = bx || hx; by = by || hy; bz = bz || hz
        }
        return (bx, by, bz)
    }

    // MARK: Meshing

    private func neighbourhood(_ c: Chunk) -> ([[BlockID]], [[Int16]])? {
        var n9: [[BlockID]] = []
        var h9: [[Int16]] = []
        n9.reserveCapacity(9)
        h9.reserveCapacity(9)
        for dz in -1...1 {
            for dx in -1...1 {
                let nn: Chunk? = (dx == 0 && dz == 0) ? c : chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)]
                guard let n = nn else { return nil }
                n9.append(n.blocks)
                h9.append(n.height)
            }
        }
        return (n9, h9)
    }

    private func remeshSync(_ c: Chunk, _ sy: Int) {
        guard let nb = neighbourhood(c) else { return }
        apply(Mesher.buildSection(nb.0, nb.1, sy: sy), to: c, sy: sy, version: c.sections[sy].version)
    }

    private func makeBuffer(_ words: [UInt32]) -> MTLBuffer? {
        if words.isEmpty { return nil }
        return words.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }

    private func apply(_ m: SectionMesh, to c: Chunk, sy: Int, version: Int) {
        let s = c.sections[sy]
        if let l = m.light {
            let base = sy * 4096
            for i in 0..<4096 { c.light[base + i] = l[i] }
            c.lightValid[sy] = true
        }
        guard version == s.version else { return }
        s.opaqueBuf = makeBuffer(m.opaque)
        s.opaqueQuads = m.opaque.count / 8
        s.transBuf = makeBuffer(m.trans)
        s.transQuads = m.trans.count / 8
        s.meshedVersion = version
        if c.tintBuf == nil {
            c.tintBuf = c.tint.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        }
    }

    private func dirtySections(_ c: Chunk) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (sy, s) in c.sections.enumerated() where s.needsMesh { out.append((sy, s.version)) }
        return out
    }

    // MARK: Streaming (call once per frame)

    func update(center pos: V3) {
        let center = ChunkKey(x: floorDiv(Int(floor(pos.x)), CS), z: floorDiv(Int(floor(pos.z)), CS))

        lock.lock()
        let gr = genResults; genResults.removeAll(keepingCapacity: true)
        let mr = meshResults; meshResults.removeAll(keepingCapacity: true)
        lock.unlock()

        for (k, p) in gr {
            genInFlight.remove(k)
            jobs -= 1
            if chunks[k] != nil { continue }
            install(k, p)
        }
        for (k, list) in mr {
            jobs -= 1
            guard let c = chunks[k] else { continue }
            c.meshInFlight = false
            c.meshedOnce = true
            for (sy, version, mesh) in list { apply(mesh, to: c, sy: sy, version: version) }
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
                if c.meshedOnce { meshed += 1 }
                if jobs >= maxJobs { continue }
                if !c.meshInFlight && inMeshRadius(dx, dz) && c.needsMesh, let nb = neighbourhood(c) {
                    let (n9, h9) = nb
                    let todo = dirtySections(c)
                    c.meshInFlight = true
                    jobs += 1
                    workQueue.async { [self] in
                        var out: [(Int, Int, SectionMesh)] = []
                        for (sy, v) in todo { out.append((sy, v, Mesher.buildSection(n9, h9, sy: sy))) }
                        lock.lock(); meshResults.append((k, out)); lock.unlock()
                    }
                }
            } else if jobs < maxJobs && !genInFlight.contains(k) {
                genInFlight.insert(k)
                jobs += 1
                workQueue.async { [self] in
                    let r = produce(k)
                    lock.lock(); genResults.append((k, r)); lock.unlock()
                }
            }
        }
        meshedCount = meshed
    }

    // Loads a chunk from disk or generates it (thread-safe).
    struct Produced {
        var blocks: [BlockID]
        var height: [Int16]
        var tint: [UInt32]
        var fromDisk: Bool
        var entities: [(IVec3, BlockEntity)]
    }

    private func produce(_ k: ChunkKey) -> Produced {
        var fromDisk = false
        var blocks: [BlockID]
        var ents: [(IVec3, BlockEntity)] = []
        if let saved = save?.loadChunk(k) { blocks = saved; fromDisk = true }
        else {
            blocks = gen.generate(cx: k.x, cz: k.z)
            if let st = gen.structures { ents = st.place(into: &blocks, cx: k.x, cz: k.z) }
        }
        return Produced(blocks: blocks, height: Chunk.computeHeights(blocks), tint: gen.tints(cx: k.x, cz: k.z),
                        fromDisk: fromDisk, entities: ents)
    }

    private func install(_ k: ChunkKey, _ p: Produced) {
        let c = Chunk(cx: k.x, cz: k.z, blocks: p.blocks, height: p.height, tint: p.tint)
        c.modified = p.fromDisk
        chunks[k] = c
        // Generated chests/spawners; a regenerated chunk keeps any existing (already looted) entity.
        for (pos, be) in p.entities where blockEntities[pos] == nil { blockEntities[pos] = be }
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
        let res = UnsafeMutablePointer<Produced>.allocate(capacity: max(1, keys.count))
        defer { res.deallocate() }
        DispatchQueue.concurrentPerform(iterations: keys.count) { i in
            (res + i).initialize(to: produce(keys[i]))
        }
        for (i, k) in keys.enumerated() {
            install(k, (res + i).move())
        }
        let t1 = CFAbsoluteTimeGetCurrent()

        var toMesh: [(Chunk, Int, Int, [[BlockID]], [[Int16]])] = []
        for dz in -radius...radius { for dx in -radius...radius where inMeshRadius(dx, dz) {
            if let c = chunks[ChunkKey(x: cx + dx, z: cz + dz)], c.needsMesh, let nb = neighbourhood(c) {
                for (sy, v) in dirtySections(c) { toMesh.append((c, sy, v, nb.0, nb.1)) }
            }
        } }
        let meshes = UnsafeMutablePointer<SectionMesh>.allocate(capacity: max(1, toMesh.count))
        defer { meshes.deallocate() }
        DispatchQueue.concurrentPerform(iterations: toMesh.count) { i in
            let t = toMesh[i]
            (meshes + i).initialize(to: Mesher.buildSection(t.3, t.4, sy: t.1))
        }
        for (i, t) in toMesh.enumerated() {
            apply((meshes + i).move(), to: t.0, sy: t.1, version: t.2)
            t.0.meshedOnce = true
        }
        let t2 = CFAbsoluteTimeGetCurrent()
        return (t1 - t0, t2 - t1)
    }

    // Drops every chunk (after saving) — used when leaving a dimension.
    func unloadAll() {
        chunks.removeAll()
        lastCenter = nil
        fluidPending.removeAll()
    }

    func saveAll() {
        for (k, c) in chunks where c.modified { save?.saveChunk(k, c.blocks) }
        save?.saveBlockEntities(blockEntities)
        save?.savePortals(Array(portals))
    }

    // MARK: Raycast (voxel DDA + per-box tests for partial blocks)

    // Selection boxes (block-local, 0...1) of a block.
    func selectionBoxes(_ b: BlockID) -> [(V3, V3)] {
        let r = Blocks.render[Int(b)]
        if r == RenderType.cross.rawValue { return [(V3(0.125, 0, 0.125), V3(0.875, 0.8125, 0.875))] }
        if r == RenderType.model.rawValue && !Blocks.boxes[Int(b)].isEmpty {
            return Blocks.boxes[Int(b)].map { ($0.minV, $0.maxV) }
        }
        if r == RenderType.connect.rawValue {
            let ck = Blocks.connectKind[Int(b)]
            let bx = BlockRegistry.connectBoxes(ck, n: false, s: false, w: false, e: false, collision: false)
            return bx.map { ($0.minV, $0.maxV) }
        }
        return [(V3(0, 0, 0), V3(1, 1, 1))]
    }

    // Ray vs AABB: entry distance and the entry face normal.
    static func rayBox(_ o: V3, _ d: V3, _ mn: V3, _ mx: V3) -> (Float, IVec3)? {
        var t0: Float = -.greatestFiniteMagnitude, t1: Float = .greatestFiniteMagnitude
        var n = IVec3(0, 0, 0)
        for a in 0..<3 {
            if abs(d[a]) < 1e-9 {
                if o[a] < mn[a] || o[a] > mx[a] { return nil }
                continue
            }
            var ta = (mn[a] - o[a]) / d[a], tb = (mx[a] - o[a]) / d[a]
            var sign = -1
            if ta > tb { swap(&ta, &tb); sign = 1 }
            if ta > t0 {
                t0 = ta
                n = IVec3(a == 0 ? sign : 0, a == 1 ? sign : 0, a == 2 ? sign : 0)
            }
            t1 = min(t1, tb)
            if t0 > t1 { return nil }
        }
        if t1 < 0 { return nil }
        return (max(0, t0), n)
    }

    // Line of sight between two points (only full opaque blocks block it).
    func canSee(_ a: V3, _ b: V3) -> Bool {
        let d = b - a
        let len = simd_length(d)
        if len < 0.01 { return true }
        let steps = Int(len / 0.25) + 1
        for i in 1..<steps {
            let p = a + d * (Float(i) / Float(steps))
            if Blocks.opaque[Int(block(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))))] { return false }
        }
        return true
    }

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
            if Blocks.targetable(b) {
                if Blocks.render[Int(b)] == RenderType.cube.rawValue { return (IVec3(x, y, z), n) }
                let o = V3(Float(x), Float(y), Float(z))
                var best: (Float, IVec3)?
                for (mn, mx) in selectionBoxes(b) {
                    if let h = World.rayBox(origin, dir, o + mn, o + mx), h.0 <= maxDist, h.0 < (best?.0 ?? inf) { best = h }
                }
                if let h = best { return (IVec3(x, y, z), h.1) }
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

    // MARK: Fluids
    // Cellular fluids: sources (level 0) feed flowing levels 1...7 sideways, falling columns (8) downwards.
    // Water ticks every 0.2 s; lava every 1.5 s (0.5 s in the Nether) and reaches 3 blocks in the
    // Overworld (7 in the Nether). Only cells near a change are simulated.

    private(set) var fluidPending = Set<IVec3>()
    private(set) var lavaPending = Set<IVec3>()
    static let fluidBudget = 1024
    private static let sideDirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
    private static let allDirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
    var onFluidEvent: ((IVec3) -> Void)?     // lava/water reactions (sound)

    func scheduleFluid(around p: IVec3) {
        let fk = Blocks.fluidKind
        var water = false, lava = false
        for q in [p] + World.allDirs.map({ p + $0 }) {
            let k = fk[Int(block(q.x, q.y, q.z))]
            if k == 1 { water = true } else if k == 2 { lava = true }
        }
        if water { fluidPending.insert(p); for d in World.allDirs { fluidPending.insert(p + d) } }
        if lava { lavaPending.insert(p); for d in World.allDirs { lavaPending.insert(p + d) } }
    }

    // Fluids may replace air, plants, torches, fire and thinner flowing fluid of the same kind.
    private func fluidCanEnter(_ id: BlockID, level: Int, kind: UInt8) -> Bool {
        let l = Int(Blocks.fluidLevel[Int(id)])
        if l >= 0 { return Blocks.fluidKind[Int(id)] == kind && l > 0 && l < 8 && l > level }
        return id == AIR || Blocks.replaceable[Int(id)] || id == TORCH
    }

    private func setFluid(_ p: IVec3, _ id: BlockID) {
        if setBlockAsync(p.x, p.y, p.z, id) { scheduleFluid(around: p) }
    }

    func fluidTick(lava: Bool = false) {
        if lava { if lavaPending.isEmpty { return } } else if fluidPending.isEmpty { return }
        var batch: [IVec3] = []
        let src = lava ? lavaPending : fluidPending
        batch.reserveCapacity(min(src.count, World.fluidBudget))
        for p in src {
            batch.append(p)
            if batch.count >= World.fluidBudget { break }
        }
        if lava { for p in batch { lavaPending.remove(p) } } else { for p in batch { fluidPending.remove(p) } }
        let lvT = Blocks.fluidLevel, fkT = Blocks.fluidKind
        let kind: UInt8 = lava ? 2 : 1
        let flow = lava ? LAVA_FLOW : WATER_FLOW, fall = lava ? LAVA_FALL : WATER_FALL
        let stepLevel = lava && dim != .nether ? 2 : 1
        for p in batch {
            guard p.y >= 0 && p.y < CH && isLoaded(p.x, p.z) else { continue }
            let cur = block(p.x, p.y, p.z)
            guard fkT[Int(cur)] == kind else { continue }
            var lv = Int(lvT[Int(cur)])
            if lava {
                // Lava touching water hardens: source -> obsidian, flowing -> cobblestone.
                var touching = false
                for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(0, 1, 0)] where fkT[Int(block(p.x + d.x, p.y + d.y, p.z + d.z))] == 1 {
                    touching = true
                    break
                }
                if touching {
                    setBlockAsync(p.x, p.y, p.z, lv == 0 ? OBSIDIAN : COBBLE)
                    scheduleFluid(around: p)
                    onFluidEvent?(p)
                    continue
                }
            }
            if lv > 0 {
                var want: Int
                if lvT[Int(block(p.x, p.y + 1, p.z))] >= 0 && fkT[Int(block(p.x, p.y + 1, p.z))] == kind {
                    want = 8
                } else {
                    var best = 99, sources = 0
                    for d in World.sideDirs {
                        let nb = block(p.x + d.x, p.y, p.z + d.z)
                        guard fkT[Int(nb)] == kind else { continue }
                        let n = Int(lvT[Int(nb)])
                        if n == 0 { sources += 1 }
                        best = min(best, n == 8 ? 0 : n)
                    }
                    let below = block(p.x, p.y - 1, p.z)
                    if !lava && sources >= 2 && (Blocks.opaque[Int(below)] || (lvT[Int(below)] == 0 && fkT[Int(below)] == kind)) { want = 0 }
                    else if best + stepLevel > 7 { want = -1 }
                    else { want = best + stepLevel }
                }
                if want != lv {
                    setFluid(p, want < 0 ? AIR : (want == 8 ? fall : flow[want]))
                    if want < 0 { continue }
                    lv = want
                }
            }
            let below = block(p.x, p.y - 1, p.z)
            if lava && fkT[Int(below)] == 1 {
                // Lava pouring onto water makes stone.
                setBlockAsync(p.x, p.y - 1, p.z, STONE)
                scheduleFluid(around: IVec3(p.x, p.y - 1, p.z))
                onFluidEvent?(p)
                continue
            }
            if p.y > 0 && (fluidCanEnter(below, level: 0, kind: kind) || (fkT[Int(below)] == kind && lvT[Int(below)] > 0 && lvT[Int(below)] < 8)) {
                setFluid(IVec3(p.x, p.y - 1, p.z), fall)
                continue
            }
            if lvT[Int(below)] >= 0 { continue }
            let next = (lv == 8 ? 0 : lv) + stepLevel
            if next > 7 { continue }
            for d in World.sideDirs {
                let q = IVec3(p.x + d.x, p.y, p.z + d.z)
                if fluidCanEnter(block(q.x, q.y, q.z), level: next, kind: kind) { setFluid(q, flow[next]) }
            }
        }
    }

    // MARK: Fire
    // Scheduled (not random) ticks: fire ages and burns out, destroys flammable neighbours and spreads.

    private(set) var fires: [IVec3: Int] = [:]
    var onIgnite: ((IVec3, BlockID) -> Void)?   // flammable block destroyed (TNT gets primed by the game)

    func placeFire(_ p: IVec3) {
        guard Blocks.replaceable[Int(block(p.x, p.y, p.z))], !Blocks.isLiquid(block(p.x, p.y, p.z)) else { return }
        setBlock(p.x, p.y, p.z, FIRE)
        fires[p] = 0
    }

    func fireTick() {
        if fires.isEmpty { return }
        let fl = Blocks.flammable
        for (p, age) in fires {
            let b = block(p.x, p.y, p.z)
            if b != FIRE { fires.removeValue(forKey: p); continue }
            if !isLoaded(p.x, p.z) { continue }
            let below = block(p.x, p.y - 1, p.z)
            let eternal = below == NETHERRACK || Blocks.key(below) == "magma_block"
            var anyFlammable = false
            for d in World.allDirs {
                let q = p + d
                let nb = block(q.x, q.y, q.z)
                guard fl[Int(nb)] else { continue }
                anyFlammable = true
                if Int.random(in: 0..<5) == 0 {
                    onIgnite?(q, nb)
                    if Int.random(in: 0..<2) == 0 { setBlockAsync(q.x, q.y, q.z, FIRE); fires[q] = 0 } else { setBlockAsync(q.x, q.y, q.z, AIR) }
                }
            }
            // Spread to air next to flammable blocks nearby.
            if anyFlammable && Int.random(in: 0..<3) == 0 {
                let q = IVec3(p.x + Int.random(in: -1...1), p.y + Int.random(in: -1...2), p.z + Int.random(in: -1...1))
                if block(q.x, q.y, q.z) == AIR && World.allDirs.contains(where: { fl[Int(block(q.x + $0.x, q.y + $0.y, q.z + $0.z))] }) {
                    setBlockAsync(q.x, q.y, q.z, FIRE); fires[q] = 0
                }
            }
            let supported = Blocks.opaque[Int(below)] || anyFlammable
            if !eternal && (!supported || (age > 6 && Int.random(in: 0..<4) == 0 && !anyFlammable) || age > 30) {
                setBlockAsync(p.x, p.y, p.z, AIR)
                fires.removeValue(forKey: p)
            } else {
                fires[p] = age + 1
            }
        }
    }
}
