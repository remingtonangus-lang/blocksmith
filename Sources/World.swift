import Foundation
import Metal
import simd

// Owns all loaded chunks of one dimension. Generation and meshing run on a concurrent background
// queue; results are applied on the main thread in update(). Chunk block arrays are Swift
// copy-on-write values, so handing snapshots to worker threads is safe.
final class World {
    var damage: [IVec3: UInt8] = [:]      // progressive block damage (chip, damageList)
    let gen: TerrainGenerator
    let dim: Dim
    let seed: UInt64
    let device: MTLDevice
    let save: SaveManager?
    var chunks: [ChunkKey: Chunk] = [:]
    var blockEntities: [IVec3: BlockEntity] = [:]
    var pendingMobs: [(String, V3)] = []
    var rainLevel: Float = 0                        // set by the game: rain puts out exposed fires
    var gravityQueue: [IVec3] = []                  // cells to check for sand/gravel/anvils that should fall
    static let fallingIDs: [Bool] = {
        var t = [Bool](repeating: false, count: Blocks.count)
        for i in 0..<Blocks.count {
            let k = Blocks.key(Blocks.groupBase[i])
            if ["sand", "red_sand", "gravel", "anvil", "chipped_anvil", "damaged_anvil", "dragon_egg", "suspicious_sand", "suspicious_gravel", "scaffolding"].contains(k)
                || k.hasSuffix("_concrete_powder") { t[i] = true }
        }
        return t
    }()          // structure mobs waiting for the game to spawn them
    lazy var redstone = Circuit(world: self)
    var portals = Set<IVec3>()
    lazy var ships = ShipManager(world: self)       // free-moving block structures (Ships.swift)
    var frame: Ship?                                // while set, block and collision queries are in this ship's space
    var renderDistance: Int = 8 { didSet { lastCenter = nil; rebuildOffsets() } }

    // Workers: maxJobs run at once; up to maxQueued jobs are handed over per frame so workers never sit
    // idle between frames (handing over only maxJobs capped streaming at ~maxJobs x 60 jobs per second;
    // 8 per worker covers a 16 ms frame of ~2 ms jobs).
    private let workQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "blocksmith.world"
        q.qualityOfService = .userInitiated
        return q
    }()
    private var maxQueued: Int { maxJobs * 8 }
    private let lock = NSLock()
    private var genResults: [(ChunkKey, Produced)] = []
    private var meshResults: [(ChunkKey, [(Int, Int, SectionMesh)])] = []
    private var genInFlight = Set<ChunkKey>()
    private var jobs = 0
    let maxJobs: Int
    private var lastCenter: ChunkKey?
    // Split-screen co-op (Coop.swift): the second player's position, streamed around like the first (nil when alone).
    var extraCenter: V3?
    private var lastExtra: ChunkKey?
    private var scanExtra: ChunkKey?
    private var offsets: [(Int, Int, Int)] = []

    private(set) var meshedCount = 0
    var pendingJobs: Int { jobs }

    // Perf counters (--bench, F3). Worker totals are updated under `lock`; updateSeconds is the last
    // update() call on the main thread.
    struct PerfStats {
        var genChunks = 0, genSeconds = 0.0
        var meshJobs = 0, meshSections = 0, meshSeconds = 0.0
        var updateSeconds = 0.0
    }
    private var perfShared = PerfStats()
    private var lastUpdateSeconds = 0.0
    var perf: PerfStats {
        lock.lock(); var p = perfShared; lock.unlock()
        p.updateSeconds = lastUpdateSeconds
        return p
    }

    static var alive = 0            // live World objects (leak check in --bench)
    static let registry = NSHashTable<World>.weakObjects()
    deinit { World.alive -= 1 }
    var debugState: String { "jobs \(jobs), queue ops \(workQueue.operationCount), gen in flight \(genInFlight.count), results \(genResults.count)/\(meshResults.count), chunks \(chunks.count)" }

    init(seed: UInt64, device: MTLDevice, save: SaveManager?, dim: Dim = .overworld) {
        World.alive += 1
        self.seed = seed
        self.dim = dim
        switch dim {
        case .overworld: gen = WorldGen(seed: seed)
        case .nether: gen = EmberGen(seed: seed)
        case .end: gen = HollowGen(seed: seed)
        }
        self.device = device
        self.save = save
        maxJobs = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
        workQueue.maxConcurrentOperationCount = maxJobs
        rebuildOffsets()
        blockEntities = save?.loadBlockEntities() ?? [:]
        portals = Set(save?.loadPortals() ?? [])
        World.registry.add(self)
    }

    // Chunks to load: the meshed disc grown by one chunk (every meshed chunk needs its 8 neighbours).
    // A disc instead of the old square skips ~20% of the chunks (the corners were never drawn).
    private var scanCenter: ChunkKey?
    private var scanEpoch = -1

    private func rebuildOffsets() {
        scanEpoch = -1
        let r = renderDistance + 1
        var o: [(Int, Int, Int)] = []
        for dz in -r...r { for dx in -r...r where World.inDisc(dx, dz, renderDistance, grow: 1) { o.append((dx, dz, dx * dx + dz * dz)) } }
        o.sort { $0.2 < $1.2 }
        offsets = o
    }

    // Whether (dx, dz) lies within `grow` chunks (Chebyshev) of the mesh disc of radius r.
    @inline(__always) static func inDisc(_ dx: Int, _ dz: Int, _ r: Int, grow: Int) -> Bool {
        let ax = max(0, abs(dx) - grow), az = max(0, abs(dz) - grow)
        return ax * ax + az * az <= r * r + r
    }

    // Chunks farther than 8 chunks are meshed at LOD 1.
    static var lodNear = 8                      // harness --nolod raises it (far detail off)
    @inline(__always) func lodFor(_ dx: Int, _ dz: Int) -> Int { max(abs(dx), abs(dz)) > World.lodNear ? 1 : 0 }
    // With one chunk of hysteresis: walking back and forth across the boundary doesn't re-mesh the ring each time.
    @inline(__always) func lodFor(_ dx: Int, _ dz: Int, current: Int) -> Int {
        let d = max(abs(dx), abs(dz))
        return current == 0 ? (d > World.lodNear + 1 ? 1 : 0) : (d > World.lodNear ? 1 : 0)
    }

    @inline(__always) func inMeshRadius(_ dx: Int, _ dz: Int) -> Bool {
        dx * dx + dz * dz <= renderDistance * renderDistance + renderDistance
    }

    // MARK: Block access

    @inline(__always) func chunkAt(_ x: Int, _ z: Int) -> Chunk? {
        chunks[ChunkKey(x: floorDiv(x, CS), z: floorDiv(z, CS))]
    }

    func block(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        if let s = frame { return s.frameBlock(x, y, z, self) }
        return rawBlock(x, y, z)
    }

    // The world's own block, ignoring any ship frame.
    @inline(__always) func rawBlock(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        if y < 0 { return BEDROCK }
        if y >= CH { return AIR }
        guard let c = chunkAt(x, z) else { return AIR }
        return c.blocks[Chunk.index(mod(x, CS), y, mod(z, CS))]
    }

    func isLoaded(_ x: Int, _ z: Int) -> Bool { frame != nil || chunkAt(x, z) != nil }

    // Light at a block: (sky 0-15, block 0-15). Uses the mesher's stored light when available,
    // otherwise approximates from the heightmap.
    func lightAt(_ x: Int, _ y: Int, _ z: Int) -> (sky: Int, block: Int) {
        if y >= CH { return (15, 0) }
        if y < 0 { return (0, 0) }
        guard let c = chunkAt(x, z) else { return (15, 0) }
        let lx = mod(x, CS), lz = mod(z, CS)
        if let sl = c.light[y >> 4] {
            let l = sl[lx + lz * CS + (y & 15) * CSQ]
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
        if !damage.isEmpty { damage.removeValue(forKey: IVec3(x, y, z)) }
        let lx = mod(x, CS), lz = mod(z, CS)
        let oldH = Int(c.height[lx + lz * CS])
        let old = c.blocks[Chunk.index(lx, y, lz)]
        c.blocks[Chunk.index(lx, y, lz)] = id
        if !redstone.isBusy && old != id { redstone.blockChanged(IVec3(x, y, z), old, id) }
        if old != id { queueSupportChecks(x, y, z, old, id) }
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

    // Cells whose support may have changed: this one and the one above (falling blocks, standing plants), the one below
    // (hanging plants), and the four beside it when a solid block went (vines clinging to it). Game.gravityTick.
    @inline(__always) func queueSupportChecks(_ x: Int, _ y: Int, _ z: Int, _ old: BlockID, _ new: BlockID) {
        gravityQueue.append(IVec3(x, y, z)); gravityQueue.append(IVec3(x, y + 1, z)); gravityQueue.append(IVec3(x, y - 1, z))
        if Blocks.collide[Int(old)] && !Blocks.collide[Int(new)] {
            gravityQueue.append(IVec3(x + 1, y, z)); gravityQueue.append(IVec3(x - 1, y, z))
            gravityQueue.append(IVec3(x, y, z + 1)); gravityQueue.append(IVec3(x, y, z - 1))
        }
    }

    // Bulk edits (fluids): no synchronous remesh; the surrounding sections re-mesh in the background.
    @discardableResult
    func setBlockAsync(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) -> Bool {
        guard y >= 0 && y < CH, let c = chunkAt(x, z) else { return false }
        if !damage.isEmpty { damage.removeValue(forKey: IVec3(x, y, z)) }
        let lx = mod(x, CS), lz = mod(z, CS)
        let old = c.blocks[Chunk.index(lx, y, lz)]
        c.blocks[Chunk.index(lx, y, lz)] = id
        if !redstone.isBusy && old != id { redstone.blockChanged(IVec3(x, y, z), old, id) }
        if old != id { queueSupportChecks(x, y, z, old, id) }
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
        if Blocks.fullCollide[b] {
            // A chipped block gives up the whole layers it has lost (you sink into a block chipped from the top).
            if !damage.isEmpty, let dv = damage[IVec3(x, y, z)] {
                let (mn, mx) = Mesher.chipBox(face: Int(dv >> 5), level: Int(dv & 31), x: x, y: y, z: z)
                out.append((o + mn, o + mx)); return
            }
            out.append((o, o + 1)); return
        }
        for bx in shapeBoxes(x, y, z, BlockID(b), collision: true) { out.append((o + bx.minV, o + bx.maxV)) }
    }

    // Model boxes of a block, resolving connecting blocks (fences, panes, walls) from their neighbours.
    func shapeBoxes(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID, collision: Bool) -> [Box] {
        let ck = Blocks.connectKind[Int(b)]
        if ck == 0 { return collision ? Blocks.collBoxes[Int(b)] : Blocks.boxes[Int(b)] }
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
        if frame == nil && !ships.isEmpty && ships.overlaps(mn, mx) { return true }
        return false
    }

    // How far an AABB can move along one axis (0 x, 1 y, 2 z) before touching a collision box.
    private var sweepScratch: [(V3, V3)] = []
    // Chunks of this world that turned dirty since update last drained the list (main thread). The quiet-frame re-check
    // walks this instead of every loaded chunk (bench: update p50 0.015 -> 0.27 / 0.89 ms at rd 16 / 24, growing with
    // the chunk count, while random ticks and fluids touched a few blocks every frame). Per world: harness probes run
    // more than one world in a process.
    var dirtyChunks: [Chunk] = []
    func sweep(_ mn: V3, _ mx: V3, axis a: Int, _ d: Float) -> Float {
        if d == 0 { return 0 }
        var lo = mn, hi = mx
        if d > 0 { hi[a] += d } else { lo[a] += d }
        let eps: Float = 1e-4
        // Main thread only (bodies, mobs, ships): the box list keeps its storage between calls (a new array per sweep,
        // several sweeps per walking mob per frame: bench mobs.per_mob_us 1.6 -> 7.8 us). Swapped out, so a nested
        // call can't share it.
        var boxes = sweepScratch
        sweepScratch = []
        boxes.removeAll(keepingCapacity: true)
        defer { sweepScratch = boxes }
        let y0 = Int(floor(lo.y - 0.5)), y1 = Int(floor(hi.y))     // -0.5: fences etc. poke up to 1.5
        let plain = frame == nil
        for z in Int(floor(lo.z))...Int(floor(hi.z - eps)) {
            for x in Int(floor(lo.x))...Int(floor(hi.x - eps)) {
                // One chunk lookup per column (it was a dictionary lookup per block); empty cells skip straight on.
                if plain {
                    guard let c = chunkAt(x, z) else {
                        if y0 < 0 { for y in y0...min(y1, -1) { collisionBoxes(x, y, z, &boxes) } }   // bedrock below 0
                        continue
                    }
                    let lx = mod(x, CS), lz = mod(z, CS)
                    for y in y0...y1 {
                        if y >= 0 && y < CH && !Blocks.collide[Int(c.blocks[Chunk.index(lx, y, lz)])] { continue }
                        collisionBoxes(x, y, z, &boxes)
                    }
                } else {
                    for y in y0...y1 { collisionBoxes(x, y, z, &boxes) }
                }
            }
        }
        if plain && !ships.isEmpty { ships.boxes(lo, hi, &boxes) }
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

    private func neighbourhood(_ c: Chunk) -> ([BlockStore], [[Int16]])? {
        var n9: [BlockStore] = []
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

    // Harness edits made with setBlockAsync over an area: remesh it now so its meshes and stored light are current
    // (a demo car built in a freshly dug pit was lit as if the pit were still rock: blind critic, run 385 ship_car).
    func remeshArea(x0: Int, z0: Int, x1: Int, z1: Int, y0: Int, y1: Int) {
        for cz in floorDiv(z0, CS)...floorDiv(z1, CS) { for cx in floorDiv(x0, CS)...floorDiv(x1, CS) {
            guard let c = chunks[ChunkKey(x: cx, z: cz)] else { continue }
            for sy in max(0, y0 >> 4)...min(NSEC - 1, y1 >> 4) { remeshSync(c, sy) }
        } }
    }

    // Harness: a section meshed at full detail and at far detail, (opaque quads, cutout quads) each.
    func lodQuads(_ c: Chunk, _ sy: Int) -> [(Int, Int)] {
        guard let nb = neighbourhood(c) else { return [] }
        return [0, 1].map { lod in
            let m = Mesher.buildSection(nb.0, nb.1, sy: sy, lod: lod)
            let q = m.opaque.count / 8
            return (m.solidQuads, q - m.solidQuads)
        }
    }

    private func remeshSync(_ c: Chunk, _ sy: Int) {
        guard let nb = neighbourhood(c) else { return }
        apply(Mesher.buildSection(nb.0, nb.1, sy: sy, lod: c.lod, damage: damageList(c)), to: c, sy: sy, version: c.sections[sy].version)
    }

    // MARK: Progressive block damage

    // Chipped blocks: world cell -> face << 5 | level (1...7 of 8 chipped away). Cleared when the block changes;
    // not saved (a chipped block comes back whole after the chunk reloads).
    func damageLevel(_ p: IVec3) -> Int { Int((damage[p] ?? 0) & 31) }

    // The damaged blocks a chunk's sections need (its own and one chunk round), relative to its corner.
    func damageList(_ c: Chunk) -> [(Int, Int, Int, UInt8)] {
        if damage.isEmpty { return [] }
        let bx = c.cx * CS, bz = c.cz * CS
        var out: [(Int, Int, Int, UInt8)] = []
        for (p, v) in damage {
            let dx = p.x - bx, dz = p.z - bz
            if dx >= -16 && dx < 32 && dz >= -16 && dz < 32 { out.append((dx, p.y, dz, v)) }
        }
        return out
    }

    // The same without the immediate remesh (explosions chip dozens at once): the sections remesh in the background.
    func chipAsync(_ p: IVec3, level: Int, face: Int) {
        let cur = damage[p]
        let lv = max(level, Int((cur ?? 0) & 31))
        guard lv > 0 && lv < 8, p.y >= 0 && p.y < CH else { return }
        if damage.count > 4096 && cur == nil { return }
        let f = cur.map { Int($0 >> 5) } ?? face
        damage[p] = UInt8((f & 7) << 5 | min(7, lv))
        for dz in -1...1 { for dx in -1...1 {
            guard let n = chunkAt(p.x + dx * 16, p.z + dz * 16) else { continue }
            for sy in max(0, (p.y - 16) >> 4)...min(NSEC - 1, (p.y + 16) >> 4) { n.sections[sy].version += 1 }
        } }
    }

    // Chips a block to `level` (keeps the face of the first hit); remeshes around it now.
    func chip(_ p: IVec3, level: Int, face: Int) {
        let cur = damage[p]
        let lv = max(level, Int((cur ?? 0) & 31))
        guard lv > 0 && lv < 8 else { return }
        if damage.count > 4096 && cur == nil { return }
        let f = cur.map { Int($0 >> 5) } ?? face
        let v = UInt8((f & 7) << 5 | min(7, lv))
        if cur == v { return }
        damage[p] = v
        remeshArea(x0: p.x - 1, z0: p.z - 1, x1: p.x + 1, z1: p.z + 1, y0: p.y - 1, y1: p.y + 1)
    }

    private func makeBuffer(_ words: [UInt32]) -> MeshSlice? {
        if words.isEmpty { return nil }
        return words.withUnsafeBytes { MeshArena.shared.alloc(device, $0) }
    }

    private func apply(_ m: SectionMesh, to c: Chunk, sy: Int, version: Int) {
        let s = c.sections[sy]
        if let l = m.light { c.light[sy] = l }
        guard version == s.version else { return }
        s.opaqueBuf = makeBuffer(m.opaque)
        s.opaqueQuads = m.opaque.count / 8
        s.solidQuads = m.solidQuads
        s.transBuf = makeBuffer(m.trans)
        s.transQuads = m.trans.count / 8
        s.meshedVersion = version
        s.vis = m.vis
        if sy >= c.topSec { c.updateTopSec() }            // a mesh below the top section cannot move it
        if c.tintBuf == nil {
            c.tintBuf = c.tint.withUnsafeBytes { MeshArena.tints.alloc(device, $0) }
        }
    }

    private func dirtySections(_ c: Chunk) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (sy, s) in c.sections.enumerated() where s.needsMesh { out.append((sy, s.version)) }
        return out
    }

    // MARK: Streaming (call once per frame)

    // Agent runs / replays: wait for last frame's jobs and apply every result in chunk order, so streaming (and
    // the light that meshing computes) never depends on timing.
    static var deterministic = false

    func update(center pos: V3) {
        let tUpdate = CFAbsoluteTimeGetCurrent()
        defer { lastUpdateSeconds = CFAbsoluteTimeGetCurrent() - tUpdate }
        let center = ChunkKey(x: floorDiv(Int(floor(pos.x)), CS), z: floorDiv(Int(floor(pos.z)), CS))

        if World.deterministic { workQueue.waitUntilAllOperationsAreFinished() }
        lock.lock()
        // Taken by swap: copying then removeAll(keepingCapacity:) on the shared buffer allocated a fresh one of the full
        // capacity twice a frame, results or not, while the workers waited on this lock.
        var gr: [(ChunkKey, Produced)] = []
        var mr: [(ChunkKey, [(Int, Int, SectionMesh)])] = []
        if !genResults.isEmpty { swap(&gr, &genResults) }
        if !meshResults.isEmpty { swap(&mr, &meshResults) }
        lock.unlock()
        if World.deterministic {
            gr.sort { (a: (ChunkKey, Produced), b: (ChunkKey, Produced)) -> Bool in a.0.x != b.0.x ? a.0.x < b.0.x : a.0.z < b.0.z }
            mr.sort { (a: (ChunkKey, [(Int, Int, SectionMesh)]), b: (ChunkKey, [(Int, Int, SectionMesh)])) -> Bool in
                a.0.x != b.0.x ? a.0.x < b.0.x : a.0.z < b.0.z
            }
        }

        // Results are applied within a per-frame budget; the rest wait for the next frame.
        let budget = 0.004
        var gi = 0, mi = 0
        while gi < gr.count && (gi == 0 || World.deterministic || CFAbsoluteTimeGetCurrent() - tUpdate < budget) {
            let (k, p) = gr[gi]; gi += 1
            genInFlight.remove(k)
            jobs -= 1
            if chunks[k] != nil { continue }
            install(k, p)
        }
        while mi < mr.count && (mi == 0 || World.deterministic || CFAbsoluteTimeGetCurrent() - tUpdate < budget) {
            let (k, list) = mr[mi]; mi += 1
            jobs -= 1
            guard let c = chunks[k] else { continue }
            c.meshInFlight = false
            c.meshedOnce = true
            for (sy, version, mesh) in list { apply(mesh, to: c, sy: sy, version: version) }
        }
        if gi < gr.count || mi < mr.count {
            lock.lock()
            genResults.insert(contentsOf: gr[gi...], at: 0)
            meshResults.insert(contentsOf: mr[mi...], at: 0)
            lock.unlock()
        }

        let extra: ChunkKey? = extraCenter.map { ChunkKey(x: floorDiv(Int(floor($0.x)), CS), z: floorDiv(Int(floor($0.z)), CS)) }
        // Offset of a chunk from the nearer centre (Chebyshev), for LOD.
        func nearOff(_ k: ChunkKey) -> (Int, Int) {
            let a = (k.x - center.x, k.z - center.z)
            guard let e = extra else { return a }
            let b = (k.x - e.x, k.z - e.z)
            return max(abs(b.0), abs(b.1)) < max(abs(a.0), abs(a.1)) ? b : a
        }
        if center != lastCenter || extra != lastExtra {
            lastCenter = center
            lastExtra = extra
            // Unload outside the load disc grown by one more chunk (hysteresis when walking back and forth).
            var gone: [ChunkKey] = []
            for (k, c) in chunks where !World.inDisc(k.x - center.x, k.z - center.z, renderDistance, grow: 2)
                && !(extra.map { World.inDisc(k.x - $0.x, k.z - $0.z, renderDistance, grow: 2) } ?? false) {
                if c.needsSave { save?.saveChunkAsync(k, c.blocks) }
                gone.append(k)
            }
            for k in gone { chunks.removeValue(forKey: k) }
            // Chunks crossing the LOD boundary get remeshed at their new detail level.
            for (k, c) in chunks {
                let (ox, oz) = nearOff(k)
                let want = lodFor(ox, oz, current: c.lod)
                if want != c.lod {
                    c.lod = want
                    for s in c.sections where !(s.meshedVersion == -1) { s.version += 1 }
                }
            }
        }

        // Nothing new since the last scan (same centre, no results, no invalidated sections): the scan
        // would schedule nothing, so skip it (it walks ~1000-2000 chunks at rd 16-24).
        let quiet = gr.isEmpty && mr.isEmpty && center == scanCenter && extra == scanExtra
        if quiet && MeshEpoch.value == scanEpoch { return }
        if quiet {
            // Only block or light edits since the last scan (flowing water, a placed block): re-check just the chunks
            // they touched instead of walking the whole disc (bench: 0.26 ms a frame at rd 16 while lava settled).
            // Only the chunks marked dirty since (dirtyChunks), not every loaded chunk.
            var list = dirtyChunks
            dirtyChunks = []
            var i = 0
            while i < list.count {
                let c = list[i]
                guard c.dirty else { i += 1; continue }
                let k = ChunkKey(x: c.cx, z: c.cz)
                guard chunks[k] === c else { c.dirty = false; i += 1; continue }   // unloaded since
                if jobs >= maxQueued {
                    // The rest stay dirty and listed; the epoch still differs, so next frame.
                    dirtyChunks.insert(contentsOf: list[i...], at: 0)
                    return
                }
                i += 1
                c.dirty = false
                guard !c.meshInFlight && c.needsMesh else { continue }
                let near = inMeshRadius(k.x - center.x, k.z - center.z) || (extra.map { inMeshRadius(k.x - $0.x, k.z - $0.z) } ?? false)
                if near, let nb = neighbourhood(c) { scheduleMesh(k, c, nb) }
            }
            list.removeAll()
            scanEpoch = MeshEpoch.value
            return
        }
        // Same centres as the last scan: no chunk's LOD can have changed, so once the job queue is full the rest of
        // the walk can't schedule anything (it walked ~1000-2000 offsets a frame while chunks streamed in at rd 16-24).
        let sameCentres = center == scanCenter && extra == scanExtra
        scanCenter = center
        scanExtra = extra

        // Nearest-first scheduling: generate missing chunks, mesh chunks whose 8 neighbours exist (round each centre).
        var meshed = 0
        var cutShort = false
        let centres: [ChunkKey] = extra.map { [center, $0] } ?? [center]
        scan: for (dx, dz, _) in offsets {
        if sameCentres && jobs >= maxQueued { cutShort = true; break scan }
        for (ci, cen) in centres.enumerated() {
            let k = ChunkKey(x: cen.x + dx, z: cen.z + dz)
            if let c = chunks[k] {
                if c.meshedOnce && ci == 0 { meshed += 1 }
                let (ox, oz) = ci == 0 && extra == nil ? (dx, dz) : nearOff(k)
                let wantLod = lodFor(ox, oz, current: c.lod)
                if wantLod != c.lod && !c.meshInFlight {
                    c.lod = wantLod
                    for s in c.sections where s.meshedVersion != -1 { s.version += 1 }
                }
                if jobs >= maxQueued { continue }
                if !c.meshInFlight && inMeshRadius(dx, dz) && c.needsMesh, let nb = neighbourhood(c) {
                    c.dirty = false
                    scheduleMesh(k, c, nb)
                }
            } else if jobs < maxQueued && !genInFlight.contains(k) {
                genInFlight.insert(k)
                jobs += 1
                workQueue.addOperation { [weak self] in
                    guard let self else { return }
                    let t0 = CFAbsoluteTimeGetCurrent()
                    let r = self.produce(k)
                    let el = CFAbsoluteTimeGetCurrent() - t0
                    lock.lock()
                    genResults.append((k, r))
                    perfShared.genChunks += 1; perfShared.genSeconds += el
                    lock.unlock()
                }
            }
        }
        }
        if !cutShort { meshedCount = meshed }   // (F3 only: a cut-short walk keeps the last full count)
        scanEpoch = MeshEpoch.value         // after the loop: its own LOD re-mesh bumps are already scheduled
        // The full scan handled what it could; keep only chunks still dirty and loaded listed (bounded by the chunk count,
        // and no unloaded chunk kept alive by the list).
        if !dirtyChunks.isEmpty {
            dirtyChunks.removeAll { c in !c.dirty || chunks[ChunkKey(x: c.cx, z: c.cz)] !== c }
        }
    }

    // Hands a chunk's out-of-date sections to a mesh worker.
    private func scheduleMesh(_ k: ChunkKey, _ c: Chunk, _ nb: ([BlockStore], [[Int16]])) {
        let (n9, h9) = nb
        let todo = dirtySections(c)
        let lod = c.lod
        let dl = damageList(c)
        c.meshInFlight = true
        jobs += 1
        // Weak: a finished operation can linger in a worker's autorelease pool and would keep the World alive.
        workQueue.addOperation { [weak self] in
            guard let self else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            var out: [(Int, Int, SectionMesh)] = []
            for (sy, v) in todo { out.append((sy, v, Mesher.buildSection(n9, h9, sy: sy, lod: lod, damage: dl))) }
            let el = CFAbsoluteTimeGetCurrent() - t0
            self.lock.lock()
            self.meshResults.append((k, out))
            self.perfShared.meshJobs += 1; self.perfShared.meshSections += todo.count; self.perfShared.meshSeconds += el
            self.lock.unlock()
        }
    }

    // Loads a chunk from disk or generates it (thread-safe).
    struct Produced {
        var blocks: [BlockID]
        var height: [Int16]
        var tint: [UInt32]
        var fromDisk: Bool
        var entities: [(IVec3, BlockEntity)]
        var mobs: [(String, V3)]
        var tracked: [IVec3] = []            // circuit components needing periodic work (found off the main thread)
        var emitMask: UInt32 = ~0            // sections holding light emitters (BlockStore.emitMask)
        var springs: [IVec3] = []            // underground water sources open to cave air (flow once loaded)
    }

    // Underground water sources beside or over cave air, at least 5 below the column's top: scheduled for a fluid
    // update on install so they spill into the cave as a waterfall (reference: aquifer fluid ticks on generation),
    // instead of standing as a wall of water until something touches them (gencheck leak, about 200 per 288 chunks).
    // Chunk interior only; at most 64 per chunk.
    static func springs(_ b: [BlockID], _ k: ChunkKey, _ h: [Int16]) -> [IVec3] {
        var out: [IVec3] = []
        for c in 0..<CSQ {
            let lx = c & 15, lz = c >> 4
            let top = Int(h[c]) - 4
            guard top > 2 else { continue }
            for y in 2..<top {
                let i = c + y * CSQ
                guard b[i] == WATER || b[i] == LAVA else { continue }    // lava pools spill into caves as lavafalls too
                let open = b[i - CSQ] == AIR || (lx > 0 && b[i - 1] == AIR) || (lx < 15 && b[i + 1] == AIR)
                    || (lz > 0 && b[i - CS] == AIR) || (lz < 15 && b[i + CS] == AIR)
                if open { out.append(IVec3(k.x * CS + lx, y, k.z * CS + lz)); if out.count >= 64 { return out } }
            }
        }
        return out
    }

    private func produce(_ k: ChunkKey) -> Produced {
        var fromDisk = false
        var blocks: [BlockID]
        var ents: [(IVec3, BlockEntity)] = []
        var mobs: [(String, V3)] = []
        if let saved = save?.loadChunk(k) { blocks = saved; fromDisk = true }
        else {
            blocks = gen.generate(cx: k.x, cz: k.z)
            if let st = gen.structures { (ents, mobs) = st.place(into: &blocks, cx: k.x, cz: k.z) }
            ents += World.orphanEntities(blocks, k, have: ents)
        }
        let heights = Chunk.computeHeights(blocks)
        return Produced(blocks: blocks, height: heights, tint: gen.tints(cx: k.x, cz: k.z),
                        fromDisk: fromDisk, entities: ents, mobs: mobs, tracked: Circuit.trackedCells(blocks, cx: k.x, cz: k.z),
                        emitMask: BlockStore.emitMask(of: blocks), springs: fromDisk ? [] : World.springs(blocks, k, heights))
    }

    // Generated spawners/chests without a block entity (dungeons): mob and loot come from the position.
    static func orphanEntities(_ blocks: [BlockID], _ k: ChunkKey, have: [(IVec3, BlockEntity)]) -> [(IVec3, BlockEntity)] {
        let spawner = Blocks.id("spawner"), chestBase = Blocks.id("chest")
        let known = Set(have.map { $0.0 })
        var out: [(IVec3, BlockEntity)] = []
        for i in 0..<blocks.count {
            let b = blocks[i]
            guard b == spawner || Blocks.groupBase[Int(b)] == chestBase else { continue }
            let x = i & 15, z = (i >> 4) & 15, y = i >> 8
            let p = IVec3(k.x * CS + x, y, k.z * CS + z)
            if known.contains(p) { continue }
            let h = hash3(p.x, p.y, p.z, 0xD06E)
            if b == spawner {
                let be = BlockEntity(.spawner)
                be.mob = ["zombie", "zombie", "skeleton", "spider"][Int(h % 4)]
                out.append((p, be))
            } else {
                let be = BlockEntity(.chest)
                var rng = SRng(UInt64(h) | 1)
                Loot.fill(be.container, table: "dungeon", rng: &rng)
                out.append((p, be))
            }
        }
        return out
    }

    private func install(_ k: ChunkKey, _ p: Produced) {
        let c = Chunk(cx: k.x, cz: k.z, blocks: p.blocks, height: p.height, tint: p.tint)
        c.world = self
        c.blocks.emitMask = p.emitMask
        c.modified = p.fromDisk
        if p.fromDisk { c.savedBlocks = c.blocks }
        chunks[k] = c
        for t in p.tracked { redstone.tracked.insert(t) }
        // Lava springs go to the lava queue: the water tick skips lava, so generated lavafalls never started.
        for q in p.springs { if rawBlock(q.x, q.y, q.z) == LAVA { lavaPending.insert(q) } else { fluidPending.insert(q) } }
        // Generated chests/spawners; a regenerated chunk keeps any existing (already looted) entity.
        for (pos, be) in p.entities where blockEntities[pos] == nil { blockEntities[pos] = be }
        // Structure mobs (bastion boarlings...) appear once: the chunk is saved so it never regenerates.
        if !p.mobs.isEmpty {
            c.modified = true
            for (name, at) in p.mobs { pendingMobs.append((name, freeSpawn(at, wide: name == "iron_golem" || name == "ravager"))) }
        }
    }

    // Blocking load of everything around a point (used by --snapshot and first spawn).
    func loadSync(center pos: V3, radius: Int) -> (gen: Double, mesh: Double) {
        let cx = floorDiv(Int(floor(pos.x)), CS), cz = floorDiv(Int(floor(pos.z)), CS)
        let r = radius + 1
        var keys: [ChunkKey] = []
        for dz in -r...r { for dx in -r...r where World.inDisc(dx, dz, radius, grow: 1) {
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

        var toMesh: [(Chunk, Int, Int, [BlockStore], [[Int16]])] = []
        for dz in -radius...radius { for dx in -radius...radius where World.inDisc(dx, dz, radius, grow: 0) && inMeshRadius(dx, dz) {
            if let c = chunks[ChunkKey(x: cx + dx, z: cz + dz)], c.needsMesh, let nb = neighbourhood(c) {
                c.lod = lodFor(dx, dz)
                for (sy, v) in dirtySections(c) { toMesh.append((c, sy, v, nb.0, nb.1)) }
            }
        } }
        let dls = toMesh.map { damageList($0.0) }
        let meshes = UnsafeMutablePointer<SectionMesh>.allocate(capacity: max(1, toMesh.count))
        defer { meshes.deallocate() }
        DispatchQueue.concurrentPerform(iterations: toMesh.count) { i in
            let t = toMesh[i]
            (meshes + i).initialize(to: Mesher.buildSection(t.3, t.4, sy: t.1, lod: t.0.lod, damage: dls[i]))
        }
        for (i, t) in toMesh.enumerated() {
            apply((meshes + i).move(), to: t.0, sy: t.1, version: t.2)
            t.0.meshedOnce = true
        }
        let t2 = CFAbsoluteTimeGetCurrent()
        return (t1 - t0, t2 - t1)
    }

    // A structure mob placed inside a wall, floor or furniture (structcheck mob_in_block) moves to the nearest
    // cell where a two-block body fits: straight up first, then one and two blocks around.
    // wide: a body over a block across (iron golems, siegebeasts) stands on a cell corner with all four cells round it
    // clear (a golem placed in a one-block gap between a house and the bank stood in both walls: behaviour sim, run 377).
    func freeSpawn(_ p: V3, wide: Bool = false) -> V3 {
        func clear(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            for k in 0...1 {
                let b = Int(block(x, y + k, z))
                if Blocks.collide[b] && (Blocks.fullCollide[b] || !Blocks.boxes[b].isEmpty) {
                    var top: Float = 0
                    for bx in Blocks.boxes[b] { top = max(top, bx.maxV.y) }
                    if Blocks.fullCollide[b] || top > (k == 0 ? 0.2 : 0.01) { return false }
                }
            }
            return true
        }
        let x = Int(floor(p.x)), y = Int(floor(p.y + 0.01)), z = Int(floor(p.z))
        if wide {
            func clear4(_ cx: Int, _ cy: Int, _ cz: Int) -> Bool {
                clear(cx - 1, cy, cz - 1) && clear(cx, cy, cz - 1) && clear(cx - 1, cy, cz) && clear(cx, cy, cz)
                    && Blocks.collide[Int(block(cx - 1, cy - 1, cz - 1))] && Blocks.collide[Int(block(cx, cy - 1, cz))]
            }
            let rx = Int((p.x).rounded()), rz = Int((p.z).rounded())
            for r in 0...3 { for dy in [0, 1, -1, 2] { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                if clear4(rx + dx, y + dy, rz + dz) { return V3(Float(rx + dx), Float(y + dy), Float(rz + dz)) }
            } } } }
            return p
        }
        if clear(x, y, z) { return p }
        for dy in 1...4 where clear(x, y + dy, z) { return V3(p.x, Float(y + dy), p.z) }
        for r in 1...2 { for dy in -1...2 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
            let fx = x + dx, fy = y + dy, fz = z + dz
            if clear(fx, fy, fz) && Blocks.collide[Int(block(fx, fy - 1, fz))] { return V3(Float(fx) + 0.5, Float(fy), Float(fz) + 0.5) }
        } } } }
        return p
    }

    // Generates and installs every chunk of a rectangle (chunk coordinates, inclusive) without meshing: the
    // structure, world-gen and bot checkers only need blocks.
    func loadBlocks(cx0: Int, cz0: Int, cx1: Int, cz1: Int) {
        var keys: [ChunkKey] = []
        for cz in cz0...cz1 { for cx in cx0...cx1 {
            let k = ChunkKey(x: cx, z: cz)
            if chunks[k] == nil { keys.append(k) }
        } }
        guard !keys.isEmpty else { return }
        let res = UnsafeMutablePointer<Produced>.allocate(capacity: keys.count)
        defer { res.deallocate() }
        DispatchQueue.concurrentPerform(iterations: keys.count) { i in
            (res + i).initialize(to: produce(keys[i]))
        }
        for (i, k) in keys.enumerated() { install(k, (res + i).move()) }
    }

    // Drops every chunk (after saving) — used when leaving a dimension.
    func unloadAll() {
        chunks.removeAll()
        lastCenter = nil
        fluidPending.removeAll()
    }

    func saveAll() {
        // Only chunks changed since their last save, written on the background save queue.
        for (k, c) in chunks where c.needsSave {
            save?.saveChunkAsync(k, c.blocks)
            c.savedBlocks = c.blocks
        }
        save?.saveBlockEntities(blockEntities)
        save?.savePortals(Array(portals))
        ships.save()
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
    // Water ticks every 0.2 s; lava every 1.5 s (0.5 s in the Emberdeep) and reaches 3 blocks in the
    // Surface (7 in the Emberdeep). Only cells near a change are simulated.

    private(set) var fluidPending = Set<IVec3>()
    private(set) var lavaPending = Set<IVec3>()
    static let fluidBudget = 1024
    private static let sideDirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
    static let allDirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
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
            if rainLevel > 0.5 && !eternal, let c = chunks[ChunkKey(x: floorDiv(p.x, CS), z: floorDiv(p.z, CS))],
               p.y >= Int(c.height[mod(p.x, CS) + mod(p.z, CS) * CS]), Rand.int(in: 0..<3) == 0 {
                let b = gen.column(p.x, p.z).biome
                if !(b == .desert || b.isBadlands || b == .savanna || b == .savannaPlateau) {
                    setBlockAsync(p.x, p.y, p.z, AIR); fires.removeValue(forKey: p); continue
                }
            }
            var anyFlammable = false
            for d in World.allDirs {
                let q = p + d
                let nb = block(q.x, q.y, q.z)
                // Blocks holding items (barrels, chiseled bookshelves, lecterns) don't burn away: their contents were
                // left behind with no block to open.
                guard fl[Int(nb)], blockEntities[q] == nil else { continue }
                anyFlammable = true
                if Rand.int(in: 0..<5) == 0 {
                    onIgnite?(q, nb)
                    if Rand.int(in: 0..<2) == 0 { setBlockAsync(q.x, q.y, q.z, FIRE); fires[q] = 0 } else { setBlockAsync(q.x, q.y, q.z, AIR) }
                }
            }
            // Spread to air next to flammable blocks nearby.
            if anyFlammable && Rand.int(in: 0..<3) == 0 {
                let q = IVec3(p.x + Rand.int(in: -1...1), p.y + Rand.int(in: -1...2), p.z + Rand.int(in: -1...1))
                if block(q.x, q.y, q.z) == AIR && World.allDirs.contains(where: { fl[Int(block(q.x + $0.x, q.y + $0.y, q.z + $0.z))] }) {
                    setBlockAsync(q.x, q.y, q.z, FIRE); fires[q] = 0
                }
            }
            let supported = Blocks.opaque[Int(below)] || anyFlammable
            if !eternal && (!supported || (age > 6 && Rand.int(in: 0..<4) == 0 && !anyFlammable) || age > 30) {
                setBlockAsync(p.x, p.y, p.z, AIR)
                fires.removeValue(forKey: p)
            } else {
                fires[p] = age + 1
            }
        }
    }
}
