import Foundation
import simd

// P351 ("things fall, including trees, including maybe even unsupported blocks"): in a field world ground that is no
// longer joined to the rest falls. After a carve (digging, a blast: World.fieldSphere) the carve's centre is queued;
// once a frame one queued spot is checked: each piece of ground round the hole is flood-filled (6-connected ground
// cells) inside a box 12 cells each way. A fill that reaches the world's floor or unloaded ground is held up by the
// world and stops there; one that reaches the box's side or 1,500 cells carries on further (P380 (4), below). A fill
// that closes inside the box is a loose piece: it leaves the field and falls as broken rigid pieces of its rock
// (DebrisField: they tumble, land on the drawn ground, settle and fade).
// Cost: only near carves, one check a frame, each at most 1,500 cells (24,000 for the further fill, which in natural
// ground runs straight to its 40-cell reach).
// Trees cut at the base fall already (Felling, P298). World generation leaves no small floating ground (FieldTerrain
// .dropFloaters, run as each chunk's field is made). P380 (GroundSettle.swift): thin overhangs break off, objects that
// lost their support settle or fall, small floating pieces across chunk borders go, and a fill past 1,500 cells
// carries on to tell a truly loose big piece (it falls in large lots) from one the world holds.
// Store review (Nov 2, VRC.Quest.Performance.1; questcheck --framesoak naval: "ground collapse" 7-11 ms of a frame after
// shells landed on a shore): the fills marked their cells in hashed sets, tens of thousands of inserts a check (the
// further fill runs to its 40-cell reach in natural ground). CellMarks is a box of stamps round the check's centre,
// reused: marking and asking cost an index each, and nothing is cleared between fills (a new stamp is taken).
final class CellMarks {
    let side: Int
    private var stamp: [UInt32]
    private var gen: UInt32 = 0
    private var origin = IVec3(0, 0, 0)
    init(radius r: Int) { side = 2 * r + 3; stamp = [UInt32](repeating: 0, count: side * side * side) }
    func reset(around p: IVec3) {
        origin = IVec3(p.x - side / 2, p.y - side / 2, p.z - side / 2)
        gen &+= 1
        if gen == 0 { for i in stamp.indices { stamp[i] = 0 }; gen = 1 }
    }
    @inline(__always) private func index(_ c: IVec3) -> Int {
        let x = c.x - origin.x, y = c.y - origin.y, z = c.z - origin.z
        guard x >= 0, y >= 0, z >= 0, x < side, y < side, z < side else { return -1 }
        return (y * side + z) * side + x
    }
    // Marks the cell; false if it was marked already (or lies outside the box, which a fill never reaches).
    @inline(__always) func insert(_ c: IVec3) -> Bool {
        let i = index(c)
        guard i >= 0, stamp[i] != gen else { return false }
        stamp[i] = gen
        return true
    }
    @inline(__always) func contains(_ c: IVec3) -> Bool { let i = index(c); return i >= 0 && stamp[i] == gen }
}

enum GroundCollapse {
    static let reach = 12
    static let maxCells = 1500
    private static let seenMarks = CellMarks(radius: reach + 1), doneMarks = CellMarks(radius: reach + 1)

    // Store review (crawler soak, build 103): a check is 1-2.6 ms, and it came on frames already heavy with the drive and
    // the soldiers (ticks of 9-11 ms). It draws on the carving allowance (CraterJob.allowance): a frame with under
    // `wantSeconds` left waits, at most `maxWait` frames in a row, so the ground still comes down within a few frames.
    static var wantSeconds = 0.0012, maxWait = 6
    private static var waited = 0

    static func tick(_ g: Game) {
        let w = g.world
        guard w.fieldTerrain, !w.collapseQueue.isEmpty else { return }
        if waited < maxWait && !World.deterministic && !Rand.deterministic && CraterJob.allowance() < wantSeconds { waited += 1; return }
        waited = 0
        let began = CFAbsoluteTimeGetCurrent()
        defer { CraterJob.spend(CFAbsoluteTimeGetCurrent() - began) }
        guard let (p, r) = w.collapseQueue.popLast() else { return }
        if w.collapseQueue.count > 64 { w.collapseQueue.removeFirst(w.collapseQueue.count - 64) }
        let done = doneMarks, seen = seenMarks
        done.reset(around: p)
        // Seeds: the ground left round the hole (every ground cell within the carve's radius and a cell).
        var seeds: [IVec3] = []
        for dy in -r...r { for dz in -r...r { for dx in -r...r {
            let s = p + IVec3(dx, dy, dz)
            if w.isGround(s) { seeds.append(s) }
        } } }
        var dropped = false
        var seenList: [IVec3] = []
        for s in seeds {
            guard !done.contains(s) else { continue }
            seen.reset(around: p)
            _ = seen.insert(s)
            seenList.removeAll(keepingCapacity: true); seenList.append(s)
            var stack = [s], cells: [IVec3] = []
            var held = false, big = false
            while let c = stack.popLast() {
                cells.append(c)
                // (a piece past 1,500 cells, or one reaching past the box, may still be loose: P380 (4))
                if cells.count > maxCells || abs(c.x - p.x) >= reach || abs(c.y - p.y) >= reach || abs(c.z - p.z) >= reach { big = true; break }
                if c.y <= 1 || !w.isLoaded(c.x, c.z) { held = true; break }
                for e in World.allDirs {
                    let n = c + e
                    if !seen.contains(n) && w.isGround(n) { _ = seen.insert(n); seenList.append(n); stack.append(n) }
                }
            }
            for c in seenList { _ = done.insert(c) }
            if big {
                // P380 (4): past 1,500 cells (or the box) the fill carries on; a piece that closes is truly loose and
                // falls in lots, a small one whole.
                if let all = GroundSettle.bigPiece(w, from: s, around: p) {
                    for c in all { _ = done.insert(c) }; dropped = true
                    if all.count > maxCells { GroundSettle.dropBig(g, all) } else { drop(g, all) }
                } else {
                    for c in GroundSettle.lastHeld { _ = done.insert(c) }      // (held: the seeds in it are too)
                }
                continue
            }
            if held { continue }
            drop(g, cells)
            dropped = true
        }
        // P380 (1): ground near the carve hanging too far for its thickness breaks off; the rest is checked again.
        if GroundSettle.thinOverhangs(g, p, r) { w.collapseQueue.append((p, r + 2)); dropped = true }
        // P380 (3): what stood on the ground round the hole settles or falls.
        GroundSettle.objects(g, p, r + (dropped ? 3 : 0))
    }

    // A loose piece leaves the field and falls apart into its rock.
    static func drop(_ g: Game, _ cells: [IVec3]) {
        let w = g.world
        var lo = SIMD3<Int>(repeating: Int.max), hi = SIMD3<Int>(repeating: Int.min)
        var mats: [BlockID: Int] = [:]
        for c in cells {
            lo = simd_min(lo, SIMD3(c.x, c.y, c.z)); hi = simd_max(hi, SIMD3(c.x, c.y, c.z))
            mats[w.block(c.x, c.y, c.z), default: 0] += 1
        }
        let mat = mats.max { $0.value < $1.value || $0.value == $1.value && $0.key > $1.key }?.key ?? STONE
        w.collapsing = true
        for c in cells { w.setBlockAsync(c.x, c.y, c.z, AIR) }
        w.collapsing = false
        let size = V3(Float(hi.x - lo.x + 1), Float(hi.y - lo.y + 1), Float(hi.z - lo.z + 1))
        let centre = V3(Float(lo.x), Float(lo.y), Float(lo.z)) + size * 0.5
        let seed = UInt32(truncatingIfNeeded: lo.x &* 73856093 ^ lo.y &* 19349663 ^ lo.z &* 83492791)
        g.debris.bits(mat, at: centre, size: size, direction: V3(0, -1, 0), count: min(28, 4 + cells.count / 3), speed: 0.4, seed: seed)
        g.sfx(.place(soundMat(mat)), 1, at: centre)
        GroundCollapse.dropped += cells.count
    }
    static var dropped = 0                       // cells dropped (harness)
}

extension World {
    @inline(__always) func isGround(_ p: IVec3) -> Bool {
        guard p.y >= 0 && p.y < CH, let c = chunkAt(p.x, p.z) else { return false }
        return c.blocks.ground(Chunk.index(mod(p.x, CS), p.y, mod(p.z, CS)))
    }
}

extension FieldTerrain {
    // P351 step 3: ground the generator left floating inside one chunk (a lump in a ravine, a sliver under a carved
    // overhang): a piece of under 400 cells touching neither the chunk's sides nor its floor is taken out. Larger pieces
    // and pieces reaching a side are left (they may be held up next door, and the sky islands are designed).
    static var floatersDropped = 0                          // (harness tally, cells; not thread-exact)
    static func dropFloaters(_ f: inout FieldData) {
        let n = min(f.fd.count, CSQ * CH)
        guard n > 0 else { return }
        var mark = [UInt8](repeating: 0, count: n)          // 1 seen
        var stack: [Int] = [], comp: [Int] = [], seeds: [Int] = []
        stack.reserveCapacity(4096)
        let outsideV = FieldTerrain.outside
        var dropped = 0
        // P474: through raw buffers (the flood visits every cell of the chunk's ground; through the struct's array each
        // read checked it, about a tenth of the field split's time).
        let cs = CS, csq = CSQ
        f.fd.withUnsafeMutableBufferPointer { fd in mark.withUnsafeMutableBufferPointer { mk in
        for s in 0..<n where fd[s] > 0 && mk[s] == 0 {
            mk[s] = 1
            stack.removeAll(keepingCapacity: true); comp.removeAll(keepingCapacity: true)
            stack.append(s)
            var anchored = false, side = false, held = false
            while let i = stack.popLast() {
                if !anchored { comp.append(i) }
                let x = i & 15, z = (i >> 4) & 15, y = i / csq
                if x == 0 || x == 15 || z == 0 || z == 15 { anchored = true; side = true }
                if y <= 1 || comp.count >= 400 { anchored = true; held = true }
                for k in 0..<6 {
                    let j: Int
                    switch k {
                    case 0: if x == 15 { continue }; j = i + 1
                    case 1: if x == 0 { continue }; j = i - 1
                    case 2: if z == 15 { continue }; j = i + cs
                    case 3: if z == 0 { continue }; j = i - cs
                    case 4: j = i + csq
                    default: j = i - csq
                    }
                    guard j >= 0 && j < n else { continue }
                    if fd[j] > 0 && mk[j] == 0 { mk[j] = 1; stack.append(j) }
                }
            }
            if !anchored { for i in comp { fd[i] = outsideV; dropped += 1 } }
            else if side && !held { seeds.append(s) }              // P380 (2): checked once its neighbours exist
        }
        } }
        floatersDropped += dropped
        f.borderSeeds += seeds
    }
}
