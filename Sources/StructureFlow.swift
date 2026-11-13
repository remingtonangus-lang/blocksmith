import Foundation
import simd

// Physics revamp, part 1 (Remington, Nov 12 18:28, a shelled Capital citadel at Beach -2902 79 2601: "This entire thing
// should collapse. Even though it's still technically connected, this wouldn't realistically be able to sustain that
// much weight"; Nov 12: "Complete revamp. Add proper physics to everything without reducing efficiency or frame rate").
//
// Why it stood: every load check so far reads a bounded piece round a change (Structure.analyse: 1,536 blocks 16 out;
// StructureTip: 9,000 blocks) and calls anything larger "held by the world", because the check runs inside a frame. A
// citadel tower is tens of thousands of blocks, so however much of it was shot away, the rest was held.
//
// The whole structure is weighed here instead, any size, as one question: can every block's weight find a way to the
// ground through joints that can carry it?
//   - every block has its weight (Structure.Mat.weight);
//   - a joint carries so much and no more: pressed straight down, the weaker block's crushing strength (Mat.crushCap);
//     hanging (the lower block from the upper) or sideways, the weaker bond (what Structure's own joints hold); along
//     an edge, half of that;
//   - a block on the ground (or into it at a side) hands the ground what its material can bear.
// That is a flow of weight through a network of joints (a maximum flow). When all of it reaches the ground the
// structure stands. When some cannot, the joints that are full are exactly the ones that fail (the minimum cut), and
// everything on the near side of them, whose weight has no way down, comes down: a tower's top on a neck shot too
// thin, a floor hung from too few bars, a heavy load on a wooden frame.
// It is a pure function of a captured piece (arrays), so it runs on a worker thread; the game applies what falls a
// slice a frame (StructureCollapse, to come). Reach (how far a material corbels) stays Structure.analyse's rule near a
// change: a flow has no lever arm.
enum StructureFlow {
    // A captured piece: blocks joined at faces and edges (as Structure joins them).
    struct Piece {
        var cells: [IVec3] = []
        var weight: [Float] = []        // (tenths of a tonne, as Structure.Mat)
        var bond: [Float] = []          // (what a joint of it carries hung or sideways: `side`)
        var crush: [Float] = []
        var ground: [UInt8] = []        // 0: on nothing; 1: stands on ground; 2: into ground at a side only
        var capped = false              // (the fill stopped at its bound: the far blocks are taken as held)
        var held: [Bool] = []           // (a block at the fill's bound: held by what lies past it)
    }
    struct Result {
        var blocks = 0
        var weight: Double = 0          // the piece's whole weight
        var unrouted: Double = 0        // the weight that finds no way to the ground
        var falls: [Int] = []           // indices into Piece.cells: what comes down
        var cut = 0                     // (joints full at the break)
        var phases = 0
        var ms = 0.0
    }

    static let dirs: [IVec3] = Structure.nbrs                    // 6 faces, then 12 edges
    static let edgeShare: Float = 0.5
    // What a joint carries hung or sideways, as a share of the bond Structure's check near a change goes by. That
    // check counts blocks of reach as well; a flow has no lever arm, so a whole structure's weight across one joint
    // (a tower's top on its sky bridge) is held to a quarter of it: a concrete joint carries a hundred blocks of
    // concrete (a 24-block balcony with room to spare), not four hundred. BS_SHEAR=1: the whole bond.
    static var shear: Float = Float(ProcessInfo.processInfo.environment["BS_SHEAR"] ?? "") ?? 0.25
    // (and never less than the check near a change allows: a material that corbels `reach` blocks out carries that
    // many of its own blocks on a joint, with a quarter to spare)
    @inline(__always) static func side(_ m: Structure.Mat) -> Float { max(m.bond * shear, m.weight * Float(m.reach) * 1.25) }
    // A block standing alone, nothing built against any of its four sides, is a slender column: it buckles long before
    // it crushes, and bears this share of its crushing strength (one neighbour: a wall's end, halfway). A wall, a pier
    // two blocks thick or a block in a floor bears all of it. So a storey shot out to a few posts gives way where the
    // same posts inside their walls did not. BS_SLENDER=1: no such rule.
    static var slenderShare: Float = Float(ProcessInfo.processInfo.environment["BS_SLENDER"] ?? "") ?? 0.5
    @inline(__always) static func slender(_ beside: Int) -> Float { beside >= 2 ? 1 : (beside == 1 ? (1 + slenderShare) / 2 : slenderShare) }
    // (weights and strengths as whole numbers: 1/16 of a weight unit)
    static let unit: Float = 16

    // What the joint from block i to its neighbour j in direction d (i hands weight to j) carries.
    @inline(__always) static func jointCap(_ d: IVec3, bi: Float, bj: Float, ci: Float, cj: Float) -> Float {
        let face = abs(d.x) + abs(d.y) + abs(d.z) == 1
        let k: Float = face ? 1 : edgeShare
        if d.y < 0 { return min(ci, cj) * k }         // pressed down (straight, or down a slope)
        return min(bi, bj) * k                        // hung from above, or sideways (Piece.bond: `side`)
    }

    // Capture: the piece of built blocks at p (Structure.part), filled over faces and edges up to `limit` blocks. It
    // reads the world, so it runs on the main thread, a slice at a time (`step`); a block past the limit, or beside a
    // chunk that is not loaded, is held by what lies past it. A piece with a helm is a docked vessel (`vessel`).
    struct Capture {
        var piece = Piece()
        var vessel = false
        private var index: [IVec3: Int32] = [:]
        private var queue: [IVec3] = []
        private var head = 0
        let limit: Int
        init(at p: IVec3, limit: Int = 400_000) {
            self.limit = limit; queue = [p]; index[p] = 0
            // (room for a citadel at the start: growing the index mid-fill rehashes it, 10 ms and more in one slice)
            index.reserveCapacity(min(limit, 160_000))
        }
        func contains(_ q: IVec3) -> Bool { index[q] != nil }
        var count: Int { queue.count }
        // One slice, until `deadline` (CFAbsoluteTime); true when the piece is whole.
        mutating func step(_ w: World, until deadline: Double = .infinity) -> Bool {
            var k = ChunkCursor(w)
            let helm = Structure.helm
            var n = 0
            while head < queue.count {
                n += 1
                if n & 31 == 0 && CFAbsoluteTimeGetCurrent() > deadline { return false }
                let q = queue[head]; head += 1
                // (every queued cell stays a cell of the piece: a block gone since it was queued weighs nothing and joins nothing)
                let m = Structure.part(&k, q.x, q.y, q.z)
                piece.cells.append(q)
                piece.weight.append(m?.weight ?? 0); piece.bond.append(m.map(StructureFlow.side) ?? 0); piece.crush.append(m?.crushCap ?? 0)
                guard m != nil else { piece.ground.append(0); piece.held.append(false); continue }
                if helm[Int(k.built(q.x, q.y, q.z))] { vessel = true }
                var g: UInt8 = 0
                if Structure.anchor(&k, q.x, q.y - 1, q.z) { g = 1 }
                else {
                    for d in World.allDirs where d.y == 0 { if Structure.anchor(&k, q.x + d.x, q.y, q.z + d.z) { g = 2; break } }
                }
                piece.ground.append(g)
                var atBound = false, beside = 0
                for d in dirs {
                    let c = q + d
                    let side = d.y == 0 && abs(d.x) + abs(d.z) == 1
                    if index[c] != nil { if side { beside += 1 }; continue }
                    guard k.loaded(c.x, c.z) else { atBound = true; piece.capped = true; continue }
                    guard Structure.part(&k, c.x, c.y, c.z) != nil else { continue }
                    if side { beside += 1 }
                    if queue.count >= limit { atBound = true; piece.capped = true; continue }
                    index[c] = Int32(queue.count)
                    queue.append(c)
                }
                piece.crush[piece.crush.count - 1] *= StructureFlow.slender(beside)
                piece.held.append(atBound)
            }
            return true
        }
        // Blocks changed since they were read (a shell landing while a slice waits): each one read, with the six
        // beside it, is read again where it stands (a block gone weighs nothing and joins nothing; one put in beside
        // the piece is the next weighing's). Cells still queued are read when the fill reaches them.
        mutating func refresh(_ w: World, _ changed: [IVec3]) {
            var k = ChunkCursor(w)
            for c in changed { for d in [IVec3(0, 0, 0)] + World.allDirs {
                let q = c + d
                guard let i32 = index[q] else { continue }
                let i = Int(i32)
                guard i < piece.cells.count else { continue }
                let m = Structure.part(&k, q.x, q.y, q.z)
                var beside = 0
                for e in World.allDirs where e.y == 0 { if Structure.part(&k, q.x + e.x, q.y, q.z + e.z) != nil { beside += 1 } }
                piece.weight[i] = m?.weight ?? 0; piece.bond[i] = m.map(StructureFlow.side) ?? 0; piece.crush[i] = (m?.crushCap ?? 0) * StructureFlow.slender(beside)
                var g: UInt8 = 0
                if m != nil {
                    if Structure.anchor(&k, q.x, q.y - 1, q.z) { g = 1 }
                    else { for e in World.allDirs where e.y == 0 { if Structure.anchor(&k, q.x + e.x, q.y, q.z + e.z) { g = 2; break } } }
                }
                piece.ground[i] = g
            } }
        }
    }
    static func capture(_ w: World, at p: IVec3, limit: Int = 400_000) -> Piece? {
        var k = ChunkCursor(w)
        guard Structure.part(&k, p.x, p.y, p.z) != nil else { return nil }
        var c = Capture(at: p, limit: limit)
        _ = c.step(w)
        return c.piece
    }

    // The flow. `scale` multiplies every weight (the harness: how many times its own weight a piece carries).
    static func solve(_ piece: Piece, scale: Float = 1) -> Result {
        let t0 = CFAbsoluteTimeGetCurrent()
        let n = piece.cells.count
        var res = Result()
        res.blocks = n
        guard n > 0 else { return res }
        let D = dirs.count
        // neighbours
        var index: [IVec3: Int32] = [:]
        index.reserveCapacity(n)
        for i in 0..<n { index[piece.cells[i]] = Int32(i) }
        let nb = UnsafeMutablePointer<Int32>.allocate(capacity: n * D)
        let cap = UnsafeMutablePointer<Int32>.allocate(capacity: n * D)      // residual of i -> nb[i, d]
        let toT = UnsafeMutablePointer<Int32>.allocate(capacity: n)          // residual of i -> ground
        let excess = UnsafeMutablePointer<Int64>.allocate(capacity: n)       // weight at i not yet handed on
        let level = UnsafeMutablePointer<Int32>.allocate(capacity: n)
        let iter = UnsafeMutablePointer<Int32>.allocate(capacity: n)
        defer { nb.deallocate(); cap.deallocate(); toT.deallocate(); excess.deallocate(); level.deallocate(); iter.deallocate() }
        let big: Int32 = Int32.max / 4
        @inline(__always) func q16(_ v: Float) -> Int32 { Int32(min(Float(big), (v * unit).rounded())) }
        // (the opposite direction's slot)
        var opp = [Int](repeating: 0, count: D)
        for d in 0..<D { opp[d] = dirs.firstIndex(of: IVec3(-dirs[d].x, -dirs[d].y, -dirs[d].z))! }
        var total: Int64 = 0
        for i in 0..<n {
            let c = piece.cells[i]
            for d in 0..<D {
                let j = index[c + dirs[d]] ?? -1
                nb[i * D + d] = j
                cap[i * D + d] = j < 0 ? 0 : q16(jointCap(dirs[d], bi: piece.bond[i], bj: piece.bond[Int(j)], ci: piece.crush[i], cj: piece.crush[Int(j)]))
            }
            let g = piece.ground[i]
            toT[i] = piece.held[i] ? big : (g == 1 ? q16(piece.crush[i]) : (g == 2 ? q16(piece.bond[i]) : 0))
            let wgt = Int64((piece.weight[i] * scale * unit).rounded())
            excess[i] = wgt
            total += wgt
        }
        res.weight = Double(total) / Double(unit)
        // First, straight down: each block's weight goes to the block under it, top to bottom, as far as the joints
        // allow (in a sound building that is nearly all of it; what is left is the weight over openings).
        let order = (0..<n).sorted { piece.cells[$0].y > piece.cells[$1].y }
        let down = dirs.firstIndex(of: IVec3(0, -1, 0))!, up = opp[down]
        var routed: Int64 = 0
        for i in order where excess[i] > 0 {
            let t = min(excess[i], Int64(toT[i]))
            if t > 0 { toT[i] -= Int32(t); excess[i] -= t; routed += t }
            let j = Int(nb[i * D + down])
            guard excess[i] > 0, j >= 0 else { continue }
            // (j comes later in the order: it hands the weight on, to the ground or further down)
            let f = min(excess[i], Int64(cap[i * D + down]))
            guard f > 0 else { continue }
            cap[i * D + down] -= Int32(f); cap[j * D + up] += Int32(f)
            excess[i] -= f; excess[j] += f
        }
        // Then what is left, by shortest ways first (Dinic): levels from the ground back through joints with room, and
        // each block with weight left pushes it down the levels.
        var bfs = [Int32](repeating: 0, count: n)
        var stack: [Int32] = []
        stack.reserveCapacity(256)
        while true {
            // levels: distance to the ground through residual joints (searched backwards from the ground)
            for i in 0..<n { level[i] = -1 }
            var qh = 0, qt = 0
            for i in 0..<n where toT[i] > 0 { level[i] = 1; bfs[qt] = Int32(i); qt += 1 }
            while qh < qt {
                let j = Int(bfs[qh]); qh += 1
                for d in 0..<D {
                    let i = Int(nb[j * D + d])           // i -> j is the joint i's slot opp[d]
                    guard i >= 0, level[i] < 0, cap[i * D + opp[d]] > 0 else { continue }
                    level[i] = level[j] + 1
                    bfs[qt] = Int32(i); qt += 1
                }
            }
            var pushed: Int64 = 0
            for i in 0..<n { iter[i] = 0 }
            for s in 0..<n where excess[s] > 0 && level[s] > 0 {
                // (depth-first along falling levels, one way at a time, the bottleneck pushed)
                while excess[s] > 0 {
                    stack.removeAll(keepingCapacity: true)
                    stack.append(Int32(s))
                    var found = false
                    while let top = stack.last {
                        let v = Int(top)
                        if level[v] == 1 && toT[v] > 0 { found = true; break }
                        var advanced = false
                        while iter[v] < Int32(D) {
                            let d = Int(iter[v]), j = Int(nb[v * D + d])
                            if j >= 0 && cap[v * D + d] > 0 && level[j] == level[v] - 1 { stack.append(Int32(j)); advanced = true; break }
                            iter[v] += 1
                        }
                        if !advanced { level[v] = -1; stack.removeLast() }       // (a dead end this phase)
                    }
                    guard found else { break }
                    var f = min(excess[s], Int64(toT[Int(stack.last!)]))
                    for k in 0..<(stack.count - 1) {
                        let v = Int(stack[k]), d = Int(iter[v])
                        f = min(f, Int64(cap[v * D + d]))
                    }
                    for k in 0..<(stack.count - 1) {
                        let v = Int(stack[k]), d = Int(iter[v]), j = Int(nb[v * D + d])
                        cap[v * D + d] -= Int32(f); cap[j * D + opp[d]] += Int32(f)
                    }
                    toT[Int(stack.last!)] -= Int32(f)
                    excess[s] -= f; pushed += f
                }
            }
            res.phases += 1
            routed += pushed
            if pushed == 0 { break }
        }
        res.unrouted = Double(total - routed) / Double(unit)
        if routed < total {
            // What comes down: every block the left-over weight can still reach through joints with room (they are
            // all on the near side of the full joints: none of them has a way to the ground).
            var mark = [Bool](repeating: false, count: n)
            var qh = 0, qt = 0
            for i in 0..<n where excess[i] > 0 { mark[i] = true; bfs[qt] = Int32(i); qt += 1 }
            while qh < qt {
                let v = Int(bfs[qh]); qh += 1
                for d in 0..<D {
                    let j = Int(nb[v * D + d])
                    guard j >= 0 else { continue }
                    if cap[v * D + d] > 0 { if !mark[j] { mark[j] = true; bfs[qt] = Int32(j); qt += 1 } }
                    else if !mark[j] { res.cut += 1 }
                }
            }
            res.falls = (0..<n).filter { mark[$0] }
        }
        res.ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        return res
    }

    // How many times its own weight the piece carries before something gives (the harness; 64 = more than it tries).
    static func safety(_ piece: Piece) -> Float {
        var lo: Float = 0, hi: Float = 64
        if solve(piece, scale: hi).falls.isEmpty { return hi }
        for _ in 0..<9 {
            let mid = (lo + hi) / 2
            if solve(piece, scale: mid).falls.isEmpty { lo = mid } else { hi = mid }
        }
        return lo
    }
}
