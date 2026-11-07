import Foundation
import simd

// P380 (finishing P351, physics) in field worlds:
//   (1) thin overhangs: after a carve, ground near it that hangs too far from its support for its thickness breaks off
//       and falls. Each column's runs of ground are found in a box round the carve; a run whose foot rests on the box's
//       floor, the world's floor, a built block or the box's side (held by what lies beyond) is a pillar; a hanging run
//       is held by the runs beside it that share a height. A hanging run more than 2 x its thickness + 1 cells (along
//       the runs) from the nearest pillar breaks off: one cell of ground spans 3, two span 5, three span 7.
//   (2) generation: a small floating piece (under 400 cells) that crosses a chunk border is taken out once the chunks
//       round it exist (FieldTerrain.dropFloaters notes the pieces that reached its chunk's side; World.install asks).
//   (3) objects: after a carve, built blocks round it that lost what held them settle or fall: plants pop (the gravity
//       queue's PlantSupport check), sand and gravel fall, a tree whose foot is gone falls as a felled tree (Felling), and
//       any other built piece of under 600 blocks resting on nothing (no ground or other block below or beside it)
//       falls block by block and lands where it comes down (FallingBlock).
//   (4) pieces over 1,500 cells: the fill carries on to 24,000 cells and 40 cells out; a piece that closes inside that
//       is truly loose and falls broken into several large pieces (8 x 8 x 8 cell lots, each its own fall); one that
//       reaches further is held by the world and stays.
enum GroundSettle {
    static let box = 10                         // (1) the run box's half size round the carve
    static let near = 4                         // (1) a breaking run is within the carve's radius + this
    static let bigCells = 24_000, bigReach = 40 // (4)
    static let lot = 8                          // (4) a big loose piece falls as lots this big
    static let objectCells = 600                // (3)
    static var overhangDrops = 0, bigDrops = 0, objectFalls = 0, treeFalls = 0, borderDrops = 0   // (harness tallies)
    static var borderCheck = true               // (harness: off to compare)

    // MARK: (1) Thin overhangs

    struct Run { let x: Int; let z: Int; let y0: Int; let y1: Int; var dist = Int.max }

    // The runs in the box round p that break off; their cells drop (grouped by touching runs). True when any did.
    static func thinOverhangs(_ g: Game, _ p: IVec3, _ r: Int) -> Bool {
        let w = g.world
        let B = box, yLo = max(1, p.y - B), yHi = min(CH - 1, p.y + B)
        var runs: [Run] = []
        var at: [Int: [Int]] = [:]              // column key -> run indices
        @inline(__always) func key(_ x: Int, _ z: Int) -> Int { (x - p.x + B) + (z - p.z + B) * (2 * B + 1) }
        for z in (p.z - B)...(p.z + B) { for x in (p.x - B)...(p.x + B) {
            guard w.isLoaded(x, z) else { continue }
            var y = yHi
            while y >= yLo {
                guard w.groundAt(x, y, z) else { y -= 1; continue }
                let top = y
                while y >= yLo && w.groundAt(x, y, z) { y -= 1 }
                let bottom = y + 1
                var run = Run(x: x, z: z, y0: bottom, y1: top)
                let edge = abs(x - p.x) == B || abs(z - p.z) == B
                // A pillar: its foot on the box's floor, the world's floor or a built block, or on the box's side.
                if bottom <= yLo || edge || w.solidAt(x, bottom - 1, z) { run.dist = 0 }
                at[key(x, z), default: []].append(runs.count)
                runs.append(run)
            }
        } }
        guard !runs.isEmpty else { return false }
        // Breadth first from the pillars through runs side by side that share a height.
        var queue = runs.indices.filter { runs[$0].dist == 0 }, head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let a = runs[i]
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = a.x + dx, nz = a.z + dz
                guard abs(nx - p.x) <= B && abs(nz - p.z) <= B, let list = at[key(nx, nz)] else { continue }
                for j in list where runs[j].dist == Int.max && runs[j].y0 <= a.y1 && runs[j].y1 >= a.y0 {
                    runs[j].dist = a.dist + 1; queue.append(j)
                }
            }
        }
        // Too far for its thickness, near the carve (a natural overhang elsewhere in the box is not this edit's doing).
        let reachNear = r + near
        var breaking = Set<Int>()
        for (i, a) in runs.enumerated() where a.dist != Int.max && a.dist > 2 * (a.y1 - a.y0 + 1) + 1 {
            if abs(a.x - p.x) <= reachNear && abs(a.z - p.z) <= reachNear && a.y0 <= p.y + reachNear && a.y1 >= p.y - reachNear { breaking.insert(i) }
        }
        guard !breaking.isEmpty else { return false }
        // Group the breaking runs that touch, and drop each group as one piece.
        var done = Set<Int>()
        for s in breaking where !done.contains(s) {
            var group: [Int] = [s], k = 0
            done.insert(s)
            while k < group.count {
                let a = runs[group[k]]; k += 1
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    guard let list = at[key(a.x + dx, a.z + dz)] else { continue }
                    for j in list where breaking.contains(j) && !done.contains(j) && runs[j].y0 <= a.y1 && runs[j].y1 >= a.y0 {
                        done.insert(j); group.append(j)
                    }
                }
            }
            var cells: [IVec3] = []
            for i in group { let a = runs[i]; for y in a.y0...a.y1 { cells.append(IVec3(a.x, y, a.z)) } }
            GroundCollapse.drop(g, cells)
            overhangDrops += cells.count
            // What hung beyond the piece (outside the check's reach) is checked for being loose now.
            let xs = group.map { runs[$0].x }, zs = group.map { runs[$0].z }, ys = group.map { runs[$0].y0 }
            let ext = max(xs.max()! - xs.min()!, zs.max()! - zs.min()!)
            w.collapseQueue.append((IVec3((xs.max()! + xs.min()!) / 2, ys.min()!, (zs.max()! + zs.min()!) / 2), min(6, ext / 2 + 2)))
        }
        return true
    }

    // MARK: (4) Big pieces

    // A fill that passed 1,500 cells: carried on (to 24,000 cells, 40 out). Nil: held by the world; else the cells of a
    // loose piece, which falls in lots.
    private static let bigMarks = CellMarks(radius: bigReach + 1)       // (store review: GroundCollapse's CellMarks)
    // The cells a held fill went through (bigPiece returned nil): one piece with what holds it, so GroundCollapse skips
    // the seeds among them. (Store review, build 96's crawler soak: "ground collapse" up to 8.3 ms of a frame; a
    // rut's every ground seed in natural ground ran its own further fill to the 40-cell reach, the same piece each time.)
    static var lastHeld: [IVec3] = []
    // held: cells of ground already found held this check (ledger 41): meeting one, the piece is held too.
    static func bigPiece(_ w: World, from s: IVec3, around p: IVec3, held: CellMarks? = nil) -> [IVec3]? {
        let seen = bigMarks
        seen.reset(around: p)
        _ = seen.insert(s)
        var stack = [s], cells: [IVec3] = []
        while let c = stack.popLast() {
            cells.append(c)
            if abs(c.x - p.x) >= bigReach || abs(c.y - p.y) >= bigReach || abs(c.z - p.z) >= bigReach || c.y <= 1
                || cells.count > bigCells || !w.isLoaded(c.x, c.z) {
                lastHeld.removeAll(keepingCapacity: true); lastHeld += cells; lastHeld += stack
                return nil
            }
            for e in World.allDirs {
                let n = c + e
                if let h = held, h.contains(n) {
                    lastHeld.removeAll(keepingCapacity: true); lastHeld += cells; lastHeld += stack
                    return nil
                }
                if w.isGround(n) && seen.insert(n) { stack.append(n) }
            }
        }
        return cells
    }

    static func dropBig(_ g: Game, _ cells: [IVec3]) {
        var lots: [IVec3: [IVec3]] = [:]
        for c in cells { lots[IVec3(floorDiv(c.x, lot), floorDiv(c.y, lot), floorDiv(c.z, lot)), default: []].append(c) }
        for (_, part) in lots.sorted(by: { $0.key.y < $1.key.y }) { GroundCollapse.drop(g, part) }
        bigDrops += 1
    }

    // MARK: (3) Objects

    static let fallSkip: [Bool] = (0..<Blocks.count).map { i in
        let b = BlockID(i)
        return b == AIR || Blocks.isLiquid(b) || !Blocks.collide[i] || CapitalBase.isLeaf(b) || Blocks.hardness[i] < 0
    }

    private static let objDone = CellSet(capacity: 4096), objSeen = CellSet(capacity: 1024)
    static var objLaps = ""                          // (perf scenes: the last call's scan, floods and falls)
    static func objects(_ g: Game, _ p: IVec3, _ r: Int) {
        let w = g.world
        let R = r + 2
        let t0 = CFAbsoluteTimeGetCurrent()
        var t1 = t0, floodS = 0.0, scanned = 0, nBases = 0, flooded = 0, fell = 0
        defer {
            let t3 = CFAbsoluteTimeGetCurrent()
            let scanMs: Double = (t1 - t0) * 1000, floodMs: Double = floodS * 1000
            let fallMs: Double = (t3 - t1) * 1000 - floodMs
            objLaps = String(format: "scan %.1f (%d queued, %d bases), floods %.1f (%d cells), falls %.1f (%d)", scanMs, scanned, nBases, floodMs, flooded, fallMs, fell)
        }
        var bases: [IVec3] = []
        for y in stride(from: max(1, p.y - R), through: min(CH - 2, p.y + R + 2), by: 1) { for z in (p.z - R)...(p.z + R) { for x in (p.x - R)...(p.x + R) {
            let b = w.builtBlock(x, y, z)
            guard b != AIR, !Blocks.isLiquid(b) else { continue }
            let q = IVec3(x, y, z)
            w.gravityQueue.append(q)                         // plants pop, sand and gravel fall (Game.gravityTick)
            scanned += 1
            if !fallSkip[Int(b)] && !w.solidAt(x, y - 1, z) { bases.append(q) }
        } } }
        t1 = CFAbsoluteTimeGetCurrent(); nBases = bases.count
        // (store review: the kept cell sets, as the border flood, instead of hashed Set<IVec3>s merged per base)
        let done = objDone, seen = objSeen
        done.removeAll()
        var seenList: [IVec3] = []
        for s in bases where !done.contains(s) {
            let tf = CFAbsoluteTimeGetCurrent()
            // The built piece standing here (6-connected solid built blocks, leaves aside), and whether anything holds it.
            seen.removeAll(); seen.insert(s)
            seenList.removeAll(keepingCapacity: true); seenList.append(s)
            var stack = [s], cells: [IVec3] = []
            var held = false
            while let c = stack.popLast() {
                cells.append(c)
                if cells.count > objectCells || abs(c.x - p.x) > 20 || abs(c.y - p.y) > 20 || abs(c.z - p.z) > 20 { held = true; break }
                for e in World.allDirs {
                    let n = c + e
                    if seen.contains(n) { continue }
                    guard w.isLoaded(n.x, n.z) else { held = true; break }
                    let b = w.builtBlock(n.x, n.y, n.z)
                    if !fallSkip[Int(b)] { seen.insert(n); seenList.append(n); stack.append(n); continue }
                    // Something holding it: ground (below or beside), or the world's floor.
                    if e.y <= 0 && (w.groundAt(n.x, n.y, n.z) || n.y <= 0) { held = true; break }
                }
                if held { break }
            }
            for q in seenList { done.insert(q) }
            flooded += seenList.count
            floodS += CFAbsoluteTimeGetCurrent() - tf
            if held { continue }
            fell += 1
            let logs = cells.filter { CapitalBase.isLog(w.builtBlock($0.x, $0.y, $0.z)) }
            if logs.count >= 3, let foot = logs.min(by: { $0.y < $1.y }) {
                // A tree whose foot is gone: it falls as a felled tree (its crown with it).
                let before = Felling.felled
                g.fellCheck(IVec3(foot.x, foot.y - 1, foot.z), w.builtBlock(foot.x, foot.y, foot.z))
                if Felling.felled > before { treeFalls += 1; continue }
            }
            // Anything else falls block by block, lowest first, and lands where it comes down.
            // (Ledger 44: one remesh for the whole piece, editBatch; each block's own took 4.4-4.7 ms for 5-6 pieces of
            // a crater's rim in the taiga24 battle, build 212.)
            // (Item 61, ledger 45's bloom: with no circuit part near, without the circuit's marks round each cell.)
            let quiet0 = w.circuitQuiet
            if Explosion.circuitCalm && !w.circuitNear(cells, margin: 3) { w.circuitQuiet = true }
            w.editBatch {
                for c in cells.sorted(by: { $0.y < $1.y }) {
                    let b = w.builtBlock(c.x, c.y, c.z)
                    guard !fallSkip[Int(b)] else { continue }
                    w.setBlock(c.x, c.y, c.z, AIR)
                    g.falling.append(FallingBlock(V3(Float(c.x) + 0.5, Float(c.y), Float(c.z) + 0.5), b))
                }
            }
            w.circuitQuiet = quiet0
            objectFalls += 1
        }
    }

    // MARK: (2) Floating pieces across chunk borders

    // After a chunk is installed: each chunk here and round it whose small side-reaching pieces wait for their
    // neighbours (Chunk.borderSeeds) is checked once all eight neighbours exist.
    // Store review (Nov 2, VRC.Quest.Performance.1; questcheck --framesoak, callgrind): run inside each chunk's install
    // on the frame thread, the flood fills (up to 400 cells a seed, in hashed sets) were the largest part of the
    // hand-over (single installs of 8 ms in the Ash Vault battle and the jungle walk). With `spread` on (the headset,
    // QuestApp; questcheck --framesoak) the chunks are queued and `borderStep` works through them within a slice of each
    // frame: a generation leftover goes a few frames later instead of the frame rate dipping as land comes in.
    static var spread = false, stepSeconds = 0.0008
    private static var queued: [ChunkKey] = []
    private static var queuedSet = Set<ChunkKey>()
    @WeakLink private static var queuedWorld: World?
    static func borderStep(_ w: World) {
        guard spread, !queued.isEmpty else { return }
        if queuedWorld !== w { queued.removeAll(); queuedSet.removeAll(); queuedWorld = w; return }
        let t0 = CFAbsoluteTimeGetCurrent()
        var i = 0
        while i < queued.count && CFAbsoluteTimeGetCurrent() - t0 < stepSeconds {
            let k = queued[i]; i += 1
            queuedSet.remove(k)
            borderCheckNow(w, k)
        }
        queued.removeFirst(i)
    }
    static func borderCheck(_ w: World, around k: ChunkKey) {
        guard w.fieldTerrain, borderCheck else { return }
        if spread {
            if queuedWorld !== w { queued.removeAll(); queuedSet.removeAll(); queuedWorld = w }
            for dz in -1...1 { for dx in -1...1 {
                let kk = ChunkKey(x: k.x + dx, z: k.z + dz)
                guard let c = w.chunks[kk], !c.borderSeeds.isEmpty, !c.hollow, queuedSet.insert(kk).inserted else { continue }
                queued.append(kk)
            } }
            return
        }
        for dz in -1...1 { for dx in -1...1 { borderCheckNow(w, ChunkKey(x: k.x + dx, z: k.z + dz)) } }
    }
    private static let borderDone = CellSet(capacity: 8192), borderSeen = CellSet(capacity: 1024)
    // One chunk's waiting seeds, if all eight neighbours are in.
    private static func borderCheckNow(_ w: World, _ kk: ChunkKey) {
        // P488: generation's own leftovers, not an edit: the sections round what is taken out mesh in the queue's order
        // (P446). Marked as edits, every chunk installed beside a loose piece sent its neighbours' sections ahead of
        // the queue: flying at 60 b/s, a fifth of all meshing was these, the chunks under him re-meshed again and again.
        let was = World.backgroundEdits
        World.backgroundEdits = true
        defer { World.backgroundEdits = was }
        do {
            guard let c = w.chunks[kk], !c.borderSeeds.isEmpty, !c.hollow else { return }
            var ready = true
            for ez in -1...1 { for ex in -1...1 where w.chunks[ChunkKey(x: kk.x + ex, z: kk.z + ez)] == nil { ready = false } }
            guard ready else { return }
            let seeds = c.borderSeeds
            c.borderSeeds = []
            // (store review, callgrind of the battle soak: still 12M instructions a chunk, most of it hashing cells into
            // Set<IVec3> and merging them; open-addressed cell sets kept between calls, frame thread only)
            let done = borderDone, seen = borderSeen
            done.removeAll()
            var seenList: [IVec3] = []
            for i in seeds {
                let s = IVec3(kk.x * CS + i & 15, i / CSQ, kk.z * CS + (i >> 4) & 15)
                guard !done.contains(s), w.isGround(s) else { continue }
                seen.removeAll(); seen.insert(s)
                seenList.removeAll(keepingCapacity: true); seenList.append(s)
                var stack = [s], cells: [IVec3] = []
                var held = false
                // (store review, callgrind of the soak: each seed filled its 400 cells into hashed sets, 1.8M instructions
                // a chunk, the whole 0.8 ms budget of every frame while land came in; ground that reaches ground an
                // earlier seed found held is held too, and those were most of them)
                // (item 7, callgrind of the worst-case soak: a chunk lookup a cell and six more for its neighbours;
                // the chunk is kept between cells now, BS_OLDLOOKUPS=1 as before)
                var k = ChunkCursor(w)
                @inline(__always) func ground(_ n: IVec3) -> Bool {
                    if World.oldLookups { return w.isGround(n) }
                    guard n.y >= 0 && n.y < CH, let c = k.chunk(n.x, n.z) else { return false }
                    return c.blocks.ground(Chunk.index(n.x & 15, n.y, n.z & 15))
                }
                flood: while let q = stack.popLast() {
                    cells.append(q)
                    if q.y <= 1 || cells.count >= 400 { held = true; break }
                    guard let cq = World.oldLookups ? w.chunkAt(q.x, q.z) : k.chunk(q.x, q.z), !cq.hollow else { held = true; break }
                    for e in World.allDirs {
                        let n = q + e
                        if seen.contains(n) || !ground(n) { continue }
                        if done.contains(n) { held = true; break flood }        // (a loose piece's cells went: ground no more)
                        seen.insert(n); seenList.append(n); stack.append(n)
                    }
                }
                for q in seenList { done.insert(q) }
                if held { continue }
                w.fieldRemove(cells)
                borderDrops += cells.count
            }
        }
    }
}

extension World {
    // Ground cells taken out of the field quietly (generation's leftovers, not a player's doing): no drops, no debris.
    func fieldRemove(_ cells: [IVec3]) {
        var touched: [(Chunk, Int)] = []
        for p in cells {
            guard let c = chunkAt(p.x, p.z) else { continue }
            let i = Chunk.index(mod(p.x, CS), p.y, mod(p.z, CS))
            c.blocks.setDensity(i, FieldTerrain.outside, material: nil, follow: true)
            c.recomputeHeight(mod(p.x, CS), mod(p.z, CS))
            c.modified = true
            if !touched.contains(where: { $0.0 === c && $0.1 == p.y >> 4 }) { touched.append((c, p.y >> 4)) }
        }
        for (c, sy) in touched {
            for dz in -1...1 { for dx in -1...1 {
                guard let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)] else { continue }
                for s in max(0, sy - 1)...min(NSEC - 1, sy + 1) { n.sections[s].version += 1 }
            } }
        }
        fieldStamp &+= 1
    }
}
