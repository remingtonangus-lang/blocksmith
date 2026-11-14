import Foundation

// Nov 14 (Remington, 22:20: "the trees stumps and branches, they procedurally change shape depending on what blocks are
// around them meaning when I break a wood tree, the other wood around it morphs into different things like branches, or
// if it's a really thick tree the whole tree turns into three separate logs instead of one. Ways to fix this are to make
// stumps not change shape ever"; ledger 123). A trunk's drawn shape is grown from the logs round it each time its
// section is drawn (ShapeTrunks): take a log away and what is left is measured again as a shorter, crownless, thinner or
// thicker thing. Case by case fixes went in before (P433's one or two cell cuts, the stump notes of Nov 13, the wide
// trunk with a log out); the cause was whole.
//
// A log taken out of wood that stands on leaves its ghost in the cell: nothing is there for the game (air to walk
// through, to build in, to save as a block), but the trunks are grown as if the log still stood, so every log left
// keeps the foot, height, girth, taper, crown and limbs it had. A ghost is not drawn; a log beside one shows a flat
// cut end. A ghost remembers whether its trunk had a crown (the leaves fall with a felled tree). Ghosts go when
// something is built in their cell (a log put back there is a log again), when a sapling grows into a tree there, and
// when no log is left that they could shape. At most 8,000 are kept (the oldest chunk's go first). Saved with the world (tree-ghosts.json).
// BS_OLDTREEMORPH=1: none are made or read.
final class TreeGhosts {
    static let on = ProcessInfo.processInfo.environment["BS_OLDTREEMORPH"] != "1"
    static let crownBit: UInt32 = 1 << 16
    static var noted = 0, pruned = 0                 // (harness)
    typealias Map = [IVec3: UInt32]                  // world cell -> the log that stood there | crownBit

    private let lock = NSLock()
    private var byChunk: [ChunkKey: Map] = [:]
    private var total = 0
    private var order: [ChunkKey] = []               // chunks by when a ghost was last made in them, oldest first
    static let most = 8000
    var dirty = false

    var count: Int { lock.lock(); defer { lock.unlock() }; return total }

    @inline(__always) private static func key(_ c: IVec3) -> ChunkKey { ChunkKey(x: floorDiv(c.x, CS), z: floorDiv(c.z, CS)) }

    func get(_ c: IVec3) -> UInt32? {
        lock.lock(); defer { lock.unlock() }
        if total == 0 { return nil }
        return byChunk[TreeGhosts.key(c)]?[c]
    }

    // The ghosts of a chunk and the eight round it (a section's trunks read that far), nil when there are none.
    func near(_ cx: Int, _ cz: Int) -> Map? {
        lock.lock(); defer { lock.unlock() }
        if total == 0 { return nil }
        var out: Map? = nil
        for dz in -1...1 { for dx in -1...1 {
            guard let m = byChunk[ChunkKey(x: cx + dx, z: cz + dz)], !m.isEmpty else { continue }
            if out == nil { out = m } else { out!.merge(m) { a, _ in a } }
        } }
        return out
    }

    private var forgot: [ChunkKey] = []              // chunks whose ghosts the cap took: their trunks are drawn again
    private var pending: [IVec3] = []                // cells where a log went: their ghosts are checked on a later tick
    private var pendingHead = 0
    static let floodsPerTick = 2
    var waiting: Int { lock.lock(); defer { lock.unlock() }; return pending.count - pendingHead }

    private func put(_ c: IVec3, _ v: UInt32) {
        lock.lock(); defer { lock.unlock() }
        let k = TreeGhosts.key(c)
        if byChunk[k]?[c] == nil { total += 1; TreeGhosts.noted += 1 }
        byChunk[k, default: [:]][c] = v
        if order.last != k { order.removeAll { $0 == k }; order.append(k) }
        // (a long war in a forest: bounded; the chunk whose ghosts are oldest forgets them)
        while total > TreeGhosts.most, let old = order.first, old != k {
            order.removeFirst()
            if let m = byChunk.removeValue(forKey: old) { total -= m.count; TreeGhosts.pruned += m.count; forgot.append(old) }
        }
        dirty = true
    }
    // A tree grows: the ghosts in its trunk's columns and the columns beside them go (the new wood is measured
    // fresh; a stump two blocks off keeps its shape).
    func clear(columns cols: Set<SIMD2<Int>>) {
        lock.lock(); defer { lock.unlock() }
        if total == 0 || cols.isEmpty { return }
        var chunks: Set<ChunkKey> = []
        for c in cols { for dz in -1...1 { for dx in -1...1 { chunks.insert(ChunkKey(x: floorDiv(c.x + dx, CS), z: floorDiv(c.y + dz, CS))) } } }
        for k in chunks {
            guard let m = byChunk[k] else { continue }
            let keep = m.filter { g in
                for dz in -1...1 { for dx in -1...1 where cols.contains(SIMD2(g.key.x + dx, g.key.z + dz)) { return false } }
                return true
            }
            if keep.count != m.count { total -= m.count - keep.count; TreeGhosts.pruned += m.count - keep.count; byChunk[k] = keep.isEmpty ? nil : keep; dirty = true }
        }
    }
    private func drop(_ cells: [IVec3]) {
        lock.lock(); defer { lock.unlock() }
        for c in cells {
            let k = TreeGhosts.key(c)
            if byChunk[k]?.removeValue(forKey: c) != nil { total -= 1; TreeGhosts.pruned += 1 }
            if byChunk[k]?.isEmpty == true { byChunk[k] = nil }
        }
        dirty = true
    }

    // The trunk through `c` has leaves round its top (ShapeTrunks' own test of a living tree), or a ghost of it says so.
    private func crowned(_ w: World, _ c: IVec3) -> Bool {
        let isLog = ShapeTrunks.isLog, leafT = Mesher.leafT
        var top = c.y
        while top < c.y + 64 {
            let up = IVec3(c.x, top + 1, c.z)
            if isLog[Int(w.block(up.x, up.y, up.z))] { top += 1; continue }
            if let g = get(up) { if g & TreeGhosts.crownBit != 0 { return true }; top += 1; continue }
            break
        }
        var y = c.y - 1
        while y > c.y - 64, let g = get(IVec3(c.x, y, c.z)) { if g & TreeGhosts.crownBit != 0 { return true }; y -= 1 }
        for dy in -2...6 { for dz in -4...4 { for dx in -4...4 where leafT[Int(w.block(c.x + dx, top + dy, c.z + dz))] { return true } } }
        return false
    }

    // Logs about to be taken (a felled tree's, before its leaves go): each leaves its ghost, the crown read while it stands.
    func note(_ w: World, _ cells: [IVec3]) {
        guard TreeGhosts.on else { return }
        for c in cells {
            let b = w.block(c.x, c.y, c.z)
            guard ShapeTrunks.isLog[Int(b)], get(c) == nil, woodBeside(w, c) else { continue }
            put(c, UInt32(b) | (crowned(w, c) ? TreeGhosts.crownBit : 0))
        }
    }

    // Wood or a ghost in one of the 26 cells round c.
    private func woodBeside(_ w: World, _ c: IVec3) -> Bool {
        let isTrunk = ShapeTrunks.isTrunk
        for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 || dz != 0 {
            if isTrunk[Int(w.block(c.x + dx, c.y + dy, c.z + dz))] { return true }
            if get(IVec3(c.x + dx, c.y + dy, c.z + dz)) != nil { return true }
        } } }
        return false
    }

    // The ghosts joined to c through ghosts (26-connected; c's own cell counted as one), and whether a standing log
    // touches any of them. Land not loaded beside them counts as wood (a ghost is never dropped on what cannot be read),
    // and so does a piece too big to walk. One lock for the whole walk.
    private func component(_ w: World, from c: IVec3, seen: inout Set<IVec3>, cap: Int = 600) -> (cells: [IVec3], wood: Bool) {
        let isTrunk = ShapeTrunks.isTrunk
        lock.lock(); defer { lock.unlock() }
        @inline(__always) func ghost(_ q: IVec3) -> Bool { byChunk[TreeGhosts.key(q)]?[q] != nil }
        var queue = [c], head = 0, cells: [IVec3] = []
        seen.insert(c)
        if ghost(c) { cells.append(c) }
        var wood = false, walked = 0
        while head < queue.count {
            let p = queue[head]; head += 1
            walked += 1
            if walked > cap { return (cells, true) }
            for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 || dz != 0 {
                let q = IVec3(p.x + dx, p.y + dy, p.z + dz)
                if seen.contains(q) { continue }
                if ghost(q) { seen.insert(q); queue.append(q); cells.append(q); continue }
                if wood { continue }
                if isTrunk[Int(w.block(q.x, q.y, q.z))] || !w.isLoaded(q.x, q.z) { wood = true }
            } } }
        }
        return (cells, wood)
    }

    // World.setBlock and setBlockAsync, before the write: `old` at (x, y, z) becomes `id`. Cheap: a blast or a felled
    // tree takes a hundred logs in a frame, so whether the ghosts round a log that went still shape any wood is asked
    // later (tick).
    func blockChanging(_ w: World, _ x: Int, _ y: Int, _ z: Int, _ old: BlockID, _ id: BlockID) {
        let isTrunk = ShapeTrunks.isTrunk
        let c = IVec3(x, y, z)
        if ShapeTrunks.isLog[Int(old)] && !isTrunk[Int(id)] {
            // A log goes. Into air (or water, fire): its ghost stays while a log it shaped stands.
            let open = id == AIR || !Blocks.collide[Int(id)]
            let had = get(c) != nil
            if open && !had && woodBeside(w, c) { put(c, UInt32(old) | (crowned(w, c) ? TreeGhosts.crownBit : 0)) }
            if !open && had { drop([c]) }
            if count == 0 { return }
            lock.lock(); pending.append(c); lock.unlock()
            return
        }
        if count == 0 { return }
        // Something built in a ghost's cell, or a log put back there: the ghost goes, the others stay (his own log set
        // down against a stump leaves the stump as it is; a sapling grown there clears its ground first, Game.growTree).
        if id != AIR && (Blocks.collide[Int(id)] || isTrunk[Int(id)]), get(c) != nil { drop([c]) }
    }

    // Each tick: a few of the cells where a log went are looked at; ghosts that no standing wood touches any more
    // go (they shape nothing). And the chunks the cap emptied are drawn again. `all`: every waiting cell (checks, saving).
    func tick(_ w: World, all: Bool = false) {
        lock.lock()
        let gone = forgot; forgot.removeAll()
        if pendingHead == pending.count { pending.removeAll(keepingCapacity: true); pendingHead = 0 }
        let idle = pendingHead == pending.count
        lock.unlock()
        for k in gone { for dz in -1...1 { for dx in -1...1 {
            guard let ch = w.chunks[ChunkKey(x: k.x + dx, z: k.z + dz)] else { continue }
            for sec in ch.sections where sec.meshedVersion != -1 { sec.version += 1 }
        } } }
        if idle { return }
        var seen: Set<IVec3> = []
        var floods = 0
        while all || floods < TreeGhosts.floodsPerTick {
            lock.lock()
            guard pendingHead < pending.count else { lock.unlock(); break }
            let c = pending[pendingHead]; pendingHead += 1
            lock.unlock()
            if seen.contains(c) { continue }
            if count == 0 { continue }
            let comp = component(w, from: c, seen: &seen)
            floods += 1
            if !comp.wood && !comp.cells.isEmpty { drop(comp.cells) }
        }
    }

    // MARK: Save

    func encoded() -> [[Int]] {
        lock.lock(); defer { lock.unlock() }
        var out: [[Int]] = []
        out.reserveCapacity(total)
        for (_, m) in byChunk { for (c, v) in m { out.append([c.x, c.y, c.z, Int(v & 0xFFFF), v & TreeGhosts.crownBit != 0 ? 1 : 0]) } }
        return out
    }
    // (saved by the block's key, not its number: block numbers move between builds)
    func encodedNamed() -> [TreeGhostSave] {
        encoded().map { TreeGhostSave(x: $0[0], y: $0[1], z: $0[2], block: Blocks.key(BlockID($0[3])), crown: $0[4] != 0) }
    }
    func load(_ rows: [TreeGhostSave]) {
        lock.lock(); defer { lock.unlock() }
        byChunk = [:]; total = 0; order = []
        for r in rows where Blocks.has(r.block) {
            let b = Blocks.id(r.block)
            guard ShapeTrunks.isLog[Int(b)] else { continue }
            let c = IVec3(r.x, r.y, r.z)
            let k = TreeGhosts.key(c)
            if byChunk[k]?[c] == nil { total += 1 }
            byChunk[k, default: [:]][c] = UInt32(b) | (r.crown ? TreeGhosts.crownBit : 0)
            if !order.contains(k) { order.append(k) }
        }
        dirty = false
    }
}

struct TreeGhostSave: Codable {
    var x: Int, y: Int, z: Int
    var block: String
    var crown: Bool
}
