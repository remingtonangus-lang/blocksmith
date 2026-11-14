import Foundation
import simd

// P503 (Oct 31 16:22:21-52, the Field Hospital's tower top shot out from under it with the deck gun: "this building
// should have fallen because there's not enough structure under it... even if there's a block connecting it
// somewhere, the whole thing should have still fallen down because of gravity and block connection physics").
// P388's check carries each block's weight to the ground joint by joint, and a reinforced slab's joints carry hundreds
// of blocks each, so a cabin left on one corner of its tower was held. What holds a building up is also where its
// weight stands. After a blast that broke built blocks (World.tipQueue: Explosion.explode, a breach's CraterJob), the
// piece over each level of the hole is weighed: its blocks joined as P388 joins them (faces and edges) over that level,
// up to 5,000 blocks and 30 out (a larger piece is held by the world), against what it stands on there: its blocks
// resting on a block under the level, or on the ground or into it at a side. When the piece's centre of weight lies
// more than a block out past what it stands on, and its weight times that lever turns harder than those blocks'
// bonds hold, it tips: it comes down whole as one body (Game.topple, P407: its own mesh, turning as it falls). One
// check a frame.
enum StructureTip {
    // P510 (Nov 1 20:24:13, a citadel side tower shot out at its foot: "Is the tower not gonna fall or what? Look at this
    // thing. Not falling"): the tower is joined to the citadel by its skyway and bridge, so its piece ran past the
    // bound and was held by the world. The piece is filled now to `side` round the hole across (any height up to `up`):
    // what goes on past that is held by the joints where it crosses (a skyway's tube, a bridge), which hold the piece
    // as an overhang's root does, their bonds times their arms (cantilever). A piece over 9,000 blocks is held.
    static let limit = 9000, side = 18, up = Structure.gridR - 2
    // What a footing block's joint holds against turning, over its bond (what it holds hanging): the bond acts half a
    // block from the joint's edge it turns about.
    static let turnHold: Float = 0.5
    static var checks = 0, tipped = 0, snapped = 0, worstMs: Double = 0      // (harness tallies)
    static var lastWeighed = ""                                             // (the harness: the last piece weighed)
    static var worstSplit = ""                                              // (the soak: the slowest check's parts)
    private static var fillAt = 0.0, groundAt = 0.0, levelsAt = 0.0
    static var describe = false                                             // (the harness: note every piece weighed)

    // Store review (VRC.Quest.Performance.1, build 109's citadel soak: a 6,380-block check was 9.7 ms of one frame, the
    // weighing 5.2 and the overhangs 4.5, on top of a bowl's carving): in the game's tick a check waits for a frame with
    // the carving allowance (CraterJob.allowance) left whole, at most `maxWait` frames, and the overhangs beside the
    // hole are weighed a frame after the piece over it. Both spend the allowance. (A harness calling tick itself, and a
    // seeded run, weigh both at once as before.)
    static var wantSeconds = 0.0012, maxWait = 8
    private static var waited = 0
    private static var overhangs: (IVec3, Int)? = nil
    static func tick(_ g: Game) {
        let w = g.world
        guard Structure.enabled else { return }
        let split = CraterJob.inTick && !(World.deterministic || Rand.deterministic)
        if split && (overhangs != nil || !w.tipQueue.isEmpty) {
            if let go = FrameGovernor.lump(.tip, atLeast: wantSeconds) { if !go { return } }
            else if CraterJob.allowance() < wantSeconds && waited < maxWait { waited += 1; return }
            waited = 0
        }
        if let (p, r) = overhangs {
            overhangs = nil
            guard w.activeHere(p) else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            if let piece = cantilever(w, at: p, r: r) { g.topple(piece); snapped += 1 }
            let dt = CFAbsoluteTimeGetCurrent() - t0
            CraterJob.spend(dt); FrameGovernor.learn(.tip, dt)
            if dt * 1000 > worstMs { worstMs = dt * 1000; worstSplit = String(format: "the overhangs %.1f", dt * 1000) }
            return
        }
        guard let (p, r) = w.tipQueue.popLast() else { return }
        if w.tipQueue.count > 16 { w.tipQueue.removeFirst(w.tipQueue.count - 16) }
        guard w.activeHere(p) else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        var cells = 0
        if let piece = check(w, at: p, r: r, count: &cells) {
            g.topple(piece)
            tipped += 1
        } else if split {
            overhangs = (p, r)
        } else if let piece = cantilever(w, at: p, r: r) {
            g.topple(piece)
            snapped += 1
        }
        checks += 1
        let t1 = CFAbsoluteTimeGetCurrent(), ms = (t1 - t0) * 1000
        CraterJob.spend(t1 - t0); FrameGovernor.learn(.tip, t1 - t0)
        if ms > worstMs {
            worstMs = ms
            worstSplit = String(format: "%d blocks: fill %.1f, footings %.1f, levels %.1f, overhangs or the fall %.1f", cells, (fillAt - t0) * 1000,
                                (groundAt - fillAt) * 1000, (levelsAt - groundAt) * 1000, (t1 - max(levelsAt, groundAt)) * 1000)
        }
    }

    // The piece that tips at the hole round p (radius r), lowest first; nil when what stands there holds.
    // The built piece at and over the hole's floor joined to the blocks round it is filled once (nil past the bound:
    // held by the world, or into unloaded ground or a docked vessel); then level by level up the hole, the part of it
    // over the level joined to the hole (two towers met below the level are two pieces there) is weighed.
    static func check(_ w: World, at p: IVec3, r: Int) -> [IVec3]? { var n = 0; return check(w, at: p, r: r, count: &n) }
    // Nov 9 (frame rate, the worst-case soak: a 6,381-block citadel piece took 3.2-4.5 ms of the frame thread's own time
    // in every run): the fill asked the world again for every open or natural cell each time it met one (up to 18
    // times), and the footings asked it again for the blocks under each block, most of them blocks of the piece itself.
    // Each cell the fill meets that isn't of the piece is marked in the grid now (cleared after), and a block under
    // another that is of the piece is known to be built on without asking (no block the piece can hold is ground,
    // water or bedrock: `partAnchors`). BS_TIPOLD=1: as before; BS_TIPVERIFY=1: both, every difference printed.
    static let tipOld = ProcessInfo.processInfo.environment["BS_TIPOLD"] == "1"
    static let tipVerify = ProcessInfo.processInfo.environment["BS_TIPVERIFY"] == "1"
    static var verified = 0, verifyDiffs = 0
    static let partAnchors: Bool = (0..<Blocks.count).contains { i in
        Structure.table[i] != nil && (Blocks.isLiquid(BlockID(i)) || Blocks.hardness[i] < 0 && Blocks.collide[i])
    }
    static func check(_ w: World, at p: IVec3, r: Int, count: inout Int) -> [IVec3]? {
        if tipVerify {
            var n0 = 0
            let a = check(w, at: p, r: r, count: &n0, marks: false)
            let b = check(w, at: p, r: r, count: &count, marks: true)
            verified += 1
            if a != b || n0 != count { verifyDiffs += 1; print("tipverify: DIFFERS at \(p) r \(r): \(n0) vs \(count) cells, \(a?.count ?? -1) vs \(b?.count ?? -1) tipping") }
            return b
        }
        return check(w, at: p, r: r, count: &count, marks: !tipOld && !partAnchors)
    }
    static func check(_ w: World, at p: IVec3, r: Int, count: inout Int, marks: Bool) -> [IVec3]? {
        let began = CFAbsoluteTimeGetCurrent()
        fillAt = 0; groundAt = 0
        defer {
            // (a check that stopped in its fill, past the bound: all of it the fill's)
            let now = CFAbsoluteTimeGetCurrent()
            if fillAt < began { fillAt = now }
            if groundAt < fillAt { groundAt = now }
            levelsAt = now
        }
        let r = max(1, min(r, 8))
        let floorY = max(1, p.y - r)
        let R = Structure.gridR, G = Structure.gridW, grid = Structure.grid
        @inline(__always) func slot(_ q: IVec3) -> Int { (q.x - p.x + R) + (q.y - p.y + R) * G + (q.z - p.z + R) * G * G }
        // (store review: the fill read each cell's chunk out of the world's table, some 160,000 lookups for a
        // citadel tower; a cursor keeps the chunk it last read, as Structure's fills do)
        var k = ChunkCursor(w)
        var cells: [IVec3] = [], mats: [Structure.Mat] = []
        var links: [Float] = []                                   // per cell: the bonds of its joints out past `side`
        var open: [Int32] = []                                    // (marks: the cells met that aren't of the piece, -2)
        defer { for q in cells { grid[slot(q)] = -1 }; for i in open { grid[Int(i)] = -1 } }
        func add(_ q: IVec3) -> Bool {
            guard abs(q.x - p.x) <= side, abs(q.y - p.y) <= up, abs(q.z - p.z) <= side, q.y >= floorY else { return true }
            let si = slot(q)
            guard grid[si] == -1 else { return true }
            guard let m = Structure.part(&k, q.x, q.y, q.z) else {
                if marks { grid[si] = -2; open.append(Int32(si)) }
                return true
            }
            if Structure.helm[Int(k.built(q.x, q.y, q.z))] { return false }
            grid[slot(q)] = Int32(cells.count)
            cells.append(q); mats.append(m); links.append(0)
            return true
        }
        @inline(__always) func near(_ q: IVec3) -> Bool { abs(q.x - p.x) <= r + 1 && abs(q.y - p.y) <= r + 1 && abs(q.z - p.z) <= r + 1 }
        for y in stride(from: floorY, through: min(CH - 2, p.y + r + 1), by: 1) {
            for z in (p.z - r - 1)...(p.z + r + 1) { for x in (p.x - r - 1)...(p.x + r + 1) { if !add(IVec3(x, y, z)) { return nil } } }
        }
        var head = 0
        while head < cells.count {
            let c = cells[head]; head += 1
            if cells.count > limit || abs(c.y - p.y) >= up { return nil }
            let rim = abs(c.x - p.x) >= side || abs(c.z - p.z) >= side
            for d in Structure.nbrs {
                let q = c + d
                guard k.loaded(q.x, q.z) else { return nil }
                if rim && (abs(q.x - p.x) > side || abs(q.z - p.z) > side) {
                    // A block's hold across is its strongest joint there (one bond, as a footing block's is; an edge
                    // joint half): the edge joints beside a face joint add nothing to what turns it (they made a
                    // 15-long skyway hold a 900-block tower off its end, Nov 1 20:24).
                    if q.y >= floorY, let mq = Structure.part(&k, q.x, q.y, q.z) {
                        let edge = abs(d.x) + abs(d.y) + abs(d.z) == 2
                        links[head - 1] = max(links[head - 1], min(mats[head - 1].bond, mq.bond) * (edge ? 0.5 : 1))
                    }
                    continue
                }
                if !add(q) { return nil }
            }
        }
        let n = cells.count
        count = n
        fillAt = CFAbsoluteTimeGetCurrent()
        guard n >= 4 else { return nil }
        // What each block stands on: the ground under it or into it at a side (`ground`), or a built block under it,
        // straight or at an edge (`onBlock`: its footing when it is at the level weighed).
        var ground = [Bool](repeating: false, count: n), onBlock = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let c = cells[i]
            for d in Structure.nbrs where d.y == -1 {
                let q = c + d
                // (a block of the piece: built on, never ground; a cell the fill met that isn't: not built on)
                let g: Int32 = marks && q.y >= floorY && abs(q.x - p.x) <= side && abs(q.z - p.z) <= side ? grid[slot(q)] : -1
                if g >= 0 { onBlock[i] = true; continue }
                if Structure.anchor(&k, q.x, q.y, q.z) { ground[i] = true; break }
                if g == -1 && Structure.part(&k, q.x, q.y, q.z) != nil { onBlock[i] = true }
            }
            if !ground[i] { for d in World.allDirs where d.y == 0 && Structure.anchor(&k, c.x + d.x, c.y, c.z + d.z) { ground[i] = true; break } }
        }
        groundAt = CFAbsoluteTimeGetCurrent()
        // Level by level up the hole, the part of the piece over the level joined to the hole is weighed. (Store
        // review, citadel soak: a fill per level, up to 17 levels of a 9,000-block piece, made the check 11 ms. The
        // levels are joined top down instead, each level's cells into the pieces over it (a union-find keeping each
        // piece's weight, centre, feet and links), and the pieces over a level read straight off it.)
        let top = min(p.y + r, cells.reduce(floorY) { max($0, $1.y) })
        let maxY = cells.reduce(floorY) { max($0, $1.y) }
        var byLevel = [[Int32]](repeating: [], count: maxY - floorY + 1)
        for i in 0..<n { byLevel[cells[i].y - floorY].append(Int32(i)) }
        let nearIdx = (0..<n).filter { near(cells[$0]) }
        // (Nov 9, callgrind of the worst-case soak: as arrays captured by find and union, every write to them took a
        // uniqueness check through the closures' boxes, and finding the pieces' roots was 60% of the check: buffers now,
        // the same values)
        var bufs: [UnsafeMutableRawPointer] = []
        defer { for b in bufs { b.deallocate() } }
        func buf<T>(_ v: T) -> UnsafeMutablePointer<T> {
            let b = UnsafeMutablePointer<T>.allocate(capacity: n)
            b.initialize(repeating: v, count: n)
            bufs.append(UnsafeMutableRawPointer(b))
            return b
        }
        let parent = buf(Int32(-1))
        let size = buf(Int32(0))
        let weight = buf(Float(0)), mx = buf(Float(0)), mz = buf(Float(0))
        let gFeet = buf(Int32(0)), gHold = buf(Float(0))
        let gLo = buf(SIMD2<Int32>(Int32.max, Int32.max)), gHi = buf(SIMD2<Int32>(Int32.min, Int32.min))
        let linkHead = buf(Int32(-1)), linkTail = buf(Int32(-1)), linkNext = buf(Int32(-1))
        let lvStamp = buf(Int32.min), evStamp = buf(Int32.min)
        let lvFeet = buf(Int32(0)), lvHold = buf(Float(0))
        let lvLo = buf(SIMD2<Int32>.zero), lvHi = buf(SIMD2<Int32>.zero)
        func find(_ i: Int32) -> Int32 {
            var a = i
            while parent[Int(a)] != a { let gp = parent[Int(parent[Int(a)])]; parent[Int(a)] = gp; a = gp }
            return a
        }
        func union(_ a0: Int32, _ b0: Int32) {
            var a = find(a0), b = find(b0)
            if a == b { return }
            if size[Int(a)] < size[Int(b)] { swap(&a, &b) }
            let ai = Int(a), bi = Int(b)
            parent[bi] = a; size[ai] += size[bi]
            weight[ai] += weight[bi]; mx[ai] += mx[bi]; mz[ai] += mz[bi]
            gFeet[ai] += gFeet[bi]; gHold[ai] += gHold[bi]
            gLo[ai] = simd_min(gLo[ai], gLo[bi]); gHi[ai] = simd_max(gHi[ai], gHi[bi])
            if linkHead[bi] >= 0 {
                if linkHead[ai] < 0 { linkHead[ai] = linkHead[bi] } else { linkNext[Int(linkTail[ai])] = linkHead[bi] }
                linkTail[ai] = linkTail[bi]
            }
        }
        var found: [IVec3]? = nil
        for yc in stride(from: maxY, through: floorY, by: -1) {
            let level = byLevel[yc - floorY]
            for i32 in level {
                let i = Int(i32), c = cells[i], m = mats[i]
                parent[i] = i32; size[i] = 1
                weight[i] = m.weight; mx[i] = m.weight * (Float(c.x) + 0.5); mz[i] = m.weight * (Float(c.z) + 0.5)
                if ground[i] { gFeet[i] = 1; gHold[i] = m.bond; gLo[i] = SIMD2(Int32(c.x), Int32(c.z)); gHi[i] = SIMD2(Int32(c.x + 1), Int32(c.z + 1)) }
                if links[i] > 0 { linkHead[i] = i32; linkTail[i] = i32 }
            }
            for i32 in level {
                let c = cells[Int(i32)]
                for d in Structure.nbrs {
                    let q = c + d
                    guard q.y >= yc, abs(q.x - p.x) <= R, abs(q.y - p.y) <= R, abs(q.z - p.z) <= R else { continue }
                    let j = grid[slot(q)]
                    if j >= 0 && parent[Int(j)] >= 0 { union(i32, j) }
                }
            }
            guard yc <= top else { continue }
            // (this level's footings: its blocks standing on a block under it)
            let stamp = Int32(yc)
            for i32 in level where onBlock[Int(i32)] && !ground[Int(i32)] {
                let c = cells[Int(i32)], ri = Int(find(i32))
                if lvStamp[ri] != stamp { lvStamp[ri] = stamp; lvFeet[ri] = 0; lvHold[ri] = 0; lvLo[ri] = SIMD2(Int32.max, Int32.max); lvHi[ri] = SIMD2(Int32.min, Int32.min) }
                lvFeet[ri] += 1; lvHold[ri] += mats[Int(i32)].bond
                lvLo[ri] = simd_min(lvLo[ri], SIMD2(Int32(c.x), Int32(c.z))); lvHi[ri] = simd_max(lvHi[ri], SIMD2(Int32(c.x + 1), Int32(c.z + 1)))
            }
            for s0 in nearIdx where cells[s0].y >= yc {
                let ri = Int(find(Int32(s0)))
                if evStamp[ri] == stamp { continue }
                evStamp[ri] = stamp
                guard size[ri] >= 4 else { continue }
                var feet = gFeet[ri], hold = gHold[ri], lo = gLo[ri], hi = gHi[ri]
                if lvStamp[ri] == stamp { feet += lvFeet[ri]; hold += lvHold[ri]; lo = simd_min(lo, lvLo[ri]); hi = simd_max(hi, lvHi[ri]) }
                // (what holds it where it goes on past the fill: its joints there, as an overhang's root)
                var linkHold: Float = 0
                var llo = SIMD2<Int>(Int.max, Int.max), lhi = SIMD2<Int>(Int.min, Int.min)
                if linkHead[ri] >= 0 {
                    var sum = 0, cnt = 0, e = linkHead[ri]
                    while e >= 0 { sum += cells[Int(e)].y; cnt += 1; e = linkNext[Int(e)] }
                    let mid = Float(sum) / Float(cnt)
                    e = linkHead[ri]
                    while e >= 0 {
                        let c = cells[Int(e)]
                        linkHold += links[Int(e)] * (0.5 + abs(Float(c.y) - mid))
                        llo = simd_min(llo, SIMD2(c.x, c.z)); lhi = simd_max(lhi, SIMD2(c.x + 1, c.z + 1))
                        e = linkNext[Int(e)]
                    }
                }
                if tips(count: Int(size[ri]), weight: weight[ri], mx: mx[ri], mz: mz[ri], feet: Int(feet), hold: hold,
                        lo: SIMD2(Int(lo.x), Int(lo.y)), hi: SIMD2(Int(hi.x), Int(hi.y)), linkHold: linkHold, linkLo: llo, linkHi: lhi) {
                    // (the lowest level that tips wins: later, lower levels overwrite this)
                    let root = Int32(ri)
                    var piece: [IVec3] = []
                    for y in yc...maxY { for j in byLevel[y - floorY] where find(j) == root { piece.append(cells[Int(j)]) } }
                    found = piece
                    break
                }
            }
        }
        return found
    }

    // P510 (Nov 1 20:23:46, shooting out a citadel side tower's top: "by that logic, the helicopter pad should also
    // come crashing down because how the hell is that even supported?"): P388 carries a hanging piece's weight joint by
    // joint, and one concrete joint carries a whole landing pad, so a pad shot loose all but one block stayed up. What
    // holds an overhang is how hard its joints resist it turning down about its root. After a blast, beyond each side of
    // the hole (the four ways across it), the built piece out there joined to the hole is filled (up to 2,000 blocks
    // and 24 out: a larger one is held); one that stands on nothing of its own (no ground under or beside it) hangs from
    // the joints across that side. Its weight times its centre's distance out past them turns it down; each joint holds
    // its bond (half for an edge joint) times its arm, half a block plus its height off the joints' middle (a deep
    // root, a brace under the pad, holds far more than one course), over two. One the blast cut a joint of that turns
    // harder than its joints hold comes away and falls whole.
    static let hangLimit = 2000, hangOut = 24
    // Nov 4 (frame rate, the worst-case soak: one blast's overhang check took 16 ms of a frame): the fill kept what it
    // had met in a set of cells and asked the world again for every neighbour of every cell (18 each, an air cell beside
    // the piece asked once per block beside it), then again for each block's material and each neighbour when it summed
    // the joints. It now marks each cell it meets, in the piece or not built on, in a box reused from check to check (a
    // new mark each side, so it's never cleared), and keeps each block's material with it. (BS_HANGOLD=1: as before.)
    static let hangOld = ProcessInfo.processInfo.environment["BS_HANGOLD"] == "1"
    private static let hangR = hangOut + 1, hangW = 2 * hangR + 1
    private static let hangGrid: UnsafeMutablePointer<UInt32> = {
        let n = hangW * hangW * hangW
        let b = UnsafeMutablePointer<UInt32>.allocate(capacity: n)
        b.initialize(repeating: 0, count: n)
        return b
    }()
    private static var hangMark: UInt32 = 0
    static func cantilever(_ w: World, at p: IVec3, r: Int) -> [IVec3]? {
        if hangOld { return cantileverOld(w, at: p, r: r) }
        let r = max(1, min(r, 8))
        var k = ChunkCursor(w)
        let grid = hangGrid, R = hangR, W = hangW
        @inline(__always) func slot(_ q: IVec3) -> Int { (q.x - p.x + R) + (q.y - p.y + R) * W + (q.z - p.z + R) * W * W }
        // (a cell's mark this side: 2 x side's mark in the piece, + 1 not built on; anything else not met yet)
        if hangMark > UInt32.max / 2 - 8 { grid.update(repeating: 0, count: W * W * W); hangMark = 0 }
        var piece: [IVec3] = [], mats: [Structure.Mat] = []
        piece.reserveCapacity(hangLimit); mats.reserveCapacity(hangLimit)
        for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
            @inline(__always) func beyond(_ q: IVec3) -> Int { (q.x - p.x) * d.x + (q.z - p.z) * d.z }
            hangMark += 1
            let inPiece = hangMark * 2, notBuilt = hangMark * 2 + 1
            piece.removeAll(keepingCapacity: true); mats.removeAll(keepingCapacity: true)
            var ok = true
            func add(_ q: IVec3) {
                guard ok, beyond(q) >= 1 else { return }
                let i = slot(q), g = grid[i]
                if g == inPiece || g == notBuilt { return }
                guard let m = Structure.part(&k, q.x, q.y, q.z) else { grid[i] = notBuilt; return }
                if piece.count >= hangLimit || abs(q.x - p.x) > hangOut || abs(q.y - p.y) > hangOut || abs(q.z - p.z) > hangOut || !k.loaded(q.x, q.z)
                    || Structure.helm[Int(k.built(q.x, q.y, q.z))] { ok = false; return }
                grid[i] = inPiece; piece.append(q); mats.append(m)
                if Structure.anchor(&k, q.x, q.y - 1, q.z) { ok = false; return }
                for n in World.allDirs where n.y == 0 && Structure.anchor(&k, q.x + n.x, q.y, q.z + n.z) { ok = false; return }
            }
            for y in (p.y - r - 1)...(p.y + r + 1) { for b in 1...(r + 1) { for a in (-r - 1)...(r + 1) {
                let q = d.x != 0 ? IVec3(p.x + d.x * b, y, p.z + a) : IVec3(p.x + a, y, p.z + d.z * b)
                add(q)
            } } }
            var head = 0
            while ok && head < piece.count {
                let c = piece[head]; head += 1
                for n in Structure.nbrs { add(c + n) }
            }
            guard ok, piece.count >= 4 else { continue }
            var joints: [(y: Int, at: Int, hold: Float)] = []
            var cut = false
            var weight: Float = 0, wOut: Float = 0
            for (ci, c) in piece.enumerated() {
                let m = mats[ci]
                weight += m.weight
                wOut += m.weight * Float(beyond(c))
                for n in Structure.nbrs {
                    let q = c + n
                    let g = grid[slot(q)]
                    if g == inPiece { continue }
                    if g != notBuilt, let mq = Structure.part(&k, q.x, q.y, q.z) {
                        let edge = abs(n.x) + abs(n.y) + abs(n.z) == 2
                        joints.append((c.y, beyond(c), min(m.bond, mq.bond) * (edge ? 0.5 : 1)))
                    } else if !cut && beyond(q) <= beyond(c) {
                        let o = V3(Float(q.x - p.x), Float(q.y - p.y), Float(q.z - p.z))
                        if simd_length(o) <= Float(r) + 0.5 { cut = true }
                    }
                }
            }
            guard cut, weight > 0 else { continue }
            if joints.isEmpty { continue }
            let root = Float(joints.reduce(Int.max) { min($0, $1.at) }) - 0.5
            let moment = wOut - weight * root
            let mid = Float(joints.reduce(0) { $0 + $1.y }) / Float(joints.count)
            let hold = joints.reduce(Float(0)) { $0 + $1.hold * (0.5 + abs(Float($1.y) - mid)) } * turnHold
            if moment > hold { return piece.sorted { $0.y < $1.y } }
        }
        return nil
    }
    static func cantileverOld(_ w: World, at p: IVec3, r: Int) -> [IVec3]? {
        let r = max(1, min(r, 8))
        var k = ChunkCursor(w)                                             // (as check's fill)
        for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
            @inline(__always) func beyond(_ q: IVec3) -> Int { (q.x - p.x) * d.x + (q.z - p.z) * d.z }
            // The far side's built cells at the hole, then all of that side's piece joined to them.
            var piece: [IVec3] = [], seen = Set<IVec3>()
            var ok = true
            func add(_ q: IVec3) {
                guard ok, beyond(q) >= 1, !seen.contains(q), Structure.part(&k, q.x, q.y, q.z) != nil else { return }
                if piece.count >= hangLimit || abs(q.x - p.x) > hangOut || abs(q.y - p.y) > hangOut || abs(q.z - p.z) > hangOut || !k.loaded(q.x, q.z)
                    || Structure.helm[Int(k.built(q.x, q.y, q.z))] { ok = false; return }
                seen.insert(q); piece.append(q)
                // (standing on its own: ground under or beside it; then it's no overhang)
                if Structure.anchor(&k, q.x, q.y - 1, q.z) { ok = false; return }
                for n in World.allDirs where n.y == 0 && Structure.anchor(&k, q.x + n.x, q.y, q.z + n.z) { ok = false; return }
            }
            for y in (p.y - r - 1)...(p.y + r + 1) { for b in 1...(r + 1) { for a in (-r - 1)...(r + 1) {
                let q = d.x != 0 ? IVec3(p.x + d.x * b, y, p.z + a) : IVec3(p.x + a, y, p.z + d.z * b)
                add(q)
            } } }
            var head = 0
            while ok && head < piece.count {
                let c = piece[head]; head += 1
                for n in Structure.nbrs { add(c + n) }
            }
            guard ok, piece.count >= 4 else { continue }
            // Its joints across the side (to built cells this side of it) and whether the blast cut one there.
            var joints: [(y: Int, at: Int, hold: Float)] = []
            var cut = false
            var weight: Float = 0, wOut: Float = 0
            for c in piece {
                guard let m = Structure.part(&k, c.x, c.y, c.z) else { continue }
                weight += m.weight
                wOut += m.weight * Float(beyond(c))
                for n in Structure.nbrs {
                    let q = c + n
                    guard !seen.contains(q) else { continue }
                    if let mq = Structure.part(&k, q.x, q.y, q.z) {
                        let edge = abs(n.x) + abs(n.y) + abs(n.z) == 2
                        joints.append((c.y, beyond(c), min(m.bond, mq.bond) * (edge ? 0.5 : 1)))
                    } else if !cut && beyond(q) <= beyond(c) {
                        let o = V3(Float(q.x - p.x), Float(q.y - p.y), Float(q.z - p.z))
                        if simd_length(o) <= Float(r) + 0.5 { cut = true }           // (open where the blast was)
                    }
                }
            }
            guard cut, weight > 0 else { continue }
            if joints.isEmpty { continue }                                // (hangs from nothing: P388's check drops it)
            // (the root: the face its nearest joints are on)
            let root = Float(joints.reduce(Int.max) { min($0, $1.at) }) - 0.5
            let moment = wOut - weight * root
            let mid = Float(joints.reduce(0) { $0 + $1.y }) / Float(joints.count)
            let hold = joints.reduce(Float(0)) { $0 + $1.hold * (0.5 + abs(Float($1.y) - mid)) } * turnHold
            if moment > hold { return piece.sorted { $0.y < $1.y } }
        }
        return nil
    }

    // Does a piece tip off what it stands on? From its sums: its weight, weight times x and z (block middles), its
    // feet, what they hold and the box they stand in. (`linkHold`: what its joints out past the fill hold, over
    // `linkLo`...`linkHi` across; with no feet it hangs from them)
    static func tips(count: Int, weight: Float, mx: Float, mz: Float, feet: Int, hold: Float, lo lo0: SIMD2<Int>, hi hi0: SIMD2<Int>,
                     linkHold: Float, linkLo: SIMD2<Int>, linkHi: SIMD2<Int>) -> Bool {
        guard weight > 0 else { return false }
        if feet == 0 && linkHold == 0 { return true }            // (hangs from nothing: P388's check takes it too)
        var lo = lo0, hi = hi0
        if feet == 0 { lo = linkLo; hi = linkHi }                // (hangs from where it goes on: a tower off its skyway)
        let cx = mx / weight, cz = mz / weight
        let dx = max(0, Float(lo.x) - cx, cx - Float(hi.x)), dz = max(0, Float(lo.y) - cz, cz - Float(hi.y))
        let lever = (dx * dx + dz * dz).squareRoot()
        let tipped = lever > 1 && weight * lever > (hold + linkHold) * turnHold
        // (the harness's note; a string per piece weighed cost the frame, so only when asked)
        if describe || tipped {
            lastWeighed = "\(count) blocks, \(feet) feet: " + String(format: "weight %.0f, lever %.1f, its feet hold %.0f, the joints on past it %.0f", weight, lever, hold, linkHold)
        }
        return tipped
    }
}

extension World {
    // P503: a blast broke built blocks round p (radius r): what stood over it is weighed (StructureTip).
    func queueTipCheck(_ p: IVec3, _ r: Int) {
        guard Structure.enabled, frame == nil, World.reachesWorld(V3(Float(p.x), Float(p.y), Float(p.z)), Float(r)) else { return }
        if let last = tipQueue.last, last.0 == p { return }
        tipQueue.append((p, r))
    }
}

// questcheck --tipcheck (and the full suite): on flat made ground, a 5 x 5 hollow tower of Capital stone 12 high with a
// 9 x 9 cabin on it. A blast takes its top course but one corner: the cabin tips and comes down whole. The same blast
// sparing a corner post at each corner, or one side's wall: it stands. Then the check's cost on a Greywall keep.
enum StructureTipCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        StructureTip.describe = true
        defer { FieldTerrain.newWorlds = field0; StructureTip.describe = false }
        let w = World(seed: 4242, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 3; w.activeDistance = 3
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        let at = V3(40, 200, 40)
        g.player.pos = at
        w.activeCenter = at                    // (Game.tick sets it; without, everything past 56 of 0, 0 was never checked)
        _ = w.loadSync(center: at, radius: 3)
        let stone = Blocks.has("capital_stone") ? Blocks.id("capital_stone") : STONE
        let ground = FieldMat.index[Int(STONE)]
        func top(_ x: Int, _ z: Int) -> Int { var y = CH - 2; while y > 1 && !w.groundAt(x, y, z) { y -= 1 }; return y }
        // A flat patch of made ground round (x, z): its top at the returned height - 1, open air 30 over it.
        func flat(_ x: Int, _ z: Int) -> Int {
            let y = top(x, z) + 1
            for dz in -7...7 { for dx in -7...7 {
                guard let c = w.chunkAt(x + dx, z + dz) else { continue }
                for yy in (y - 4)..<(y + 30) {
                    let i = Chunk.index(mod(x + dx, CS), yy, mod(z + dz, CS))
                    if yy >= y && c.blocks.raw(i) != AIR { c.blocks[i] = AIR }
                    c.blocks.setDensity(i, yy < y ? 32 : -32, material: yy < y ? ground : nil)
                }
            } }
            return y
        }
        // The tower and its cabin; the blast takes the tower's top course but `keep`.
        func tower(_ x0: Int, _ z0: Int, keep: (Int, Int) -> Bool) -> (tipped: Bool, left: Int) {
            let y = flat(x0 + 2, z0 + 2)
            for k in 0..<12 { for dz in 0..<5 { for dx in 0..<5 where dx == 0 || dx == 4 || dz == 0 || dz == 4 { w.setBlock(x0 + dx, y + k, z0 + dz, stone) } } }
            for k in 12..<16 { for dz in -2..<7 { for dx in -2..<7 where k == 12 || k == 15 || dx == -2 || dx == 6 || dz == -2 || dz == 6 { w.setBlock(x0 + dx, y + k, z0 + dz, stone) } } }
            while !w.loadQueue.isEmpty { Structure.tick(g) }
            for dz in 0..<5 { for dx in 0..<5 where (dx == 0 || dx == 4 || dz == 0 || dz == 4) && !keep(dx, dz) { w.setBlock(x0 + dx, y + 11, z0 + dz, AIR) } }
            while !w.loadQueue.isEmpty { Structure.tick(g) }
            let t0 = tipped
            w.queueTipCheck(IVec3(x0 + 2, y + 11, z0 + 2), 3)
            StructureTip.tick(g)
            var left = 0
            for k in 12..<16 { for dz in -2..<7 { for dx in -2..<7 where w.builtBlock(x0 + dx, y + k, z0 + dz) == stone { left += 1 } } }
            for s in w.ships.list where s.name == Game.toppledName { w.ships.remove(s) }
            Felling.falls.removeAll()
            return (tipped > t0, left)
        }
        var tipped: Int { StructureTip.tipped }
        let corner = tower(20, 20) { dx, dz in dx == 0 && dz == 0 }
        let posts = tower(20, 40) { dx, dz in (dx == 0 || dx == 4) && (dz == 0 || dz == 4) }
        let side = tower(40, 20) { _, dz in dz == 0 }
        check(corner.tipped && corner.left == 0 && !posts.tipped && posts.left > 200 && !side.tipped && side.left > 200,
              "P503: a cabin on one corner of its shot-out tower tipped \(corner.tipped) (\(corner.left) of its blocks left up); on four corner posts it stood (tipped \(posts.tipped), \(posts.left) left), on one side's wall it stood (tipped \(side.tipped), \(side.left) left)")
        // P510: a landing pad off a tower's top on a three-wide arm with a brace under it. Its arm shot through at the
        // wall but for the brace, it snaps off and falls; only the arm's middle shot out, it holds.
        func padTower(_ x0: Int, _ z0: Int, armCut: [Int]) -> (snapped: Bool, left: Int) {
            let y = flat(x0 + 2, z0 + 2), py = y + 17
            for k in 0..<18 { for dz in 0..<5 { for dx in 0..<5 where k == 17 || dx == 0 || dx == 4 || dz == 0 || dz == 4 { w.setBlock(x0 + dx, y + k, z0 + dz, stone) } } }
            for dz in 1...3 { for dx in 5...6 { w.setBlock(x0 + dx, py, z0 + dz, stone) } }
            for dz in -4...4 { for dx in -4...4 where dx * dx + dz * dz <= 16 { w.setBlock(x0 + 11 + dx, py, z0 + 2 + dz, stone) } }
            for k in 1...5 { w.setBlock(x0 + 10 - k, py - k, z0 + 2, stone) }
            while !w.loadQueue.isEmpty { Structure.tick(g) }
            for dz in armCut { w.setBlock(x0 + 5, py, z0 + dz, AIR) }
            while !w.loadQueue.isEmpty { Structure.tick(g) }
            let s0 = StructureTip.snapped
            w.queueTipCheck(IVec3(x0 + 5, py, z0 + 2), 1)
            StructureTip.tick(g)
            var left = 0
            for dz in -4...4 { for dx in -4...4 where w.builtBlock(x0 + 11 + dx, py, z0 + 2 + dz) == stone { left += 1 } }
            for s in w.ships.list where s.name == Game.toppledName { w.ships.remove(s) }
            Felling.falls.removeAll()
            return (StructureTip.snapped > s0, left)
        }
        let loose = padTower(40, 40, armCut: [1, 2, 3]), braced = padTower(60, 20, armCut: [2])
        check(loose.snapped && loose.left == 0 && !braced.snapped && braced.left > 40,
              "P510: a landing pad's arm shot through at the wall, its brace left: it snaps off and falls (\(loose.snapped), \(loose.left) of its blocks left up); the arm's middle shot out: it holds (snapped \(braced.snapped), \(braced.left) left)")
        // P510: a tower joined by a skyway (a tube five wide and high, glass sides) to another 22 off. Its foot shot out
        // all round, it comes away from the skyway and falls; shot out but for two opposite walls, it stands.
        _ = w.loadSync(center: V3(70, 200, 66), radius: 3)
        func skywayTower(_ x0: Int, _ z0: Int, keepWalls: Bool) -> (tipped: Bool, left: Int) {
            let y = flat(x0 + 3, z0 + 3), yB = flat(x0 + 25, z0 + 3)
            let pane = Blocks.has("capital_window") ? Blocks.id("capital_window") : GLASS
            for k in 0..<30 { for dz in 0..<7 { for dx in 0..<7 where k % 6 == 5 || dx == 0 || dx == 6 || dz == 0 || dz == 6 { w.setBlock(x0 + dx, y + k, z0 + dz, stone) } } }
            for yy in yB..<(y + 26) { for dz in 0..<7 { for dx in 0..<7 where dx == 0 || dx == 6 || dz == 0 || dz == 6 || (yy - yB) % 6 == 5 { w.setBlock(x0 + 22 + dx, yy, z0 + dz, stone) } } }
            for x in (x0 + 7)...(x0 + 21) { for dz in 1...5 { for k in 18...22 {
                let wall = dz == 1 || dz == 5
                if k == 18 || k == 22 { w.setBlock(x, y + k, z0 + dz, stone) } else if wall { w.setBlock(x, y + k, z0 + dz, pane) }
            } } }
            while !w.loadQueue.isEmpty { Structure.tick(g) }
            for k in 0...2 { for dz in 0..<7 { for dx in 0..<7 where (dx == 0 || dx == 6 || dz == 0 || dz == 6) && !(keepWalls && (dx == 0 || dx == 6)) {
                w.setBlock(x0 + dx, y + k, z0 + dz, AIR)
            } } }
            while !w.loadQueue.isEmpty { Structure.tick(g) }
            let t0 = tipped
            StructureTip.lastWeighed = "nothing weighed"
            w.queueTipCheck(IVec3(x0 + 3, y + 1, z0 + 3), 3)
            StructureTip.tick(g)
            print("tipcheck: skyway tower (walls kept \(keepWalls)): \(StructureTip.lastWeighed)")
            var left = 0
            for k in 3..<30 { for dz in 0..<7 { for dx in 0..<7 where w.builtBlock(x0 + dx, y + k, z0 + dz) == stone { left += 1 } } }
            for s in w.ships.list where s.name == Game.toppledName { w.ships.remove(s) }
            Felling.falls.removeAll()
            return (tipped > t0, left)
        }
        let cutAll = skywayTower(56, 56, keepWalls: false), cutSides = skywayTower(56, 72, keepWalls: true)
        check(cutAll.tipped && cutAll.left == 0 && !cutSides.tipped && cutSides.left > 600,
              "P510: a tower joined to another by a skyway, its foot shot out all round: it comes away and falls (\(cutAll.tipped), \(cutAll.left) of its blocks left up); its foot shot out but for two opposite walls: it stands (tipped \(cutSides.tipped), \(cutSides.left) left)")
        // Cost: the check at a blast on a big keep's wall runs to its bound and stops.
        var ms = 0.0
        let kx = 20, kz = 60, ky = flat(kx + 6, kz + 6)
        for k in 0..<24 { for dz in 0..<13 { for dx in 0..<13 where k % 6 == 0 || dx == 0 || dx == 12 || dz == 0 || dz == 12 { w.setBlock(kx + dx, ky + k, kz + dz, stone) } } }
        while !w.loadQueue.isEmpty { Structure.tick(g) }
        let t0 = CFAbsoluteTimeGetCurrent()
        let held = StructureTip.check(w, at: IVec3(kx, ky + 3, kz + 6), r: 4) == nil
        ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        check(held && ms < 40, String(format: "P503: a blast on a whole keep's wall leaves it standing (%@), the check took %.1f ms", held ? "held" : "TIPPED", ms))
        // Nov 4: the overhang check at blasts on the keep (its wall low and high, its top floor's middle, its top course's
        // corner), as it is and as it was before (BS_HANGOLD): the same pieces, and what each took.
        let spots = [IVec3(kx, ky + 4, kz + 6), IVec3(kx, ky + 15, kz + 6), IVec3(kx + 6, ky + 18, kz + 6), IVec3(kx + 12, ky + 23, kz + 12)]
        var same = true, newMs = 0.0, oldMs = 0.0, pieces: [Int] = []
        for _ in 0..<3 { for q in spots {
            let a0 = CFAbsoluteTimeGetCurrent()
            let a = StructureTip.cantilever(w, at: q, r: 4)
            let a1 = CFAbsoluteTimeGetCurrent()
            let b = StructureTip.cantileverOld(w, at: q, r: 4)
            let b1 = CFAbsoluteTimeGetCurrent()
            newMs = max(newMs, (a1 - a0) * 1000); oldMs = max(oldMs, (b1 - a1) * 1000)
            if a?.count != b?.count || a.map({ Set($0) }) != b.map({ Set($0) }) { same = false }
            if pieces.count < spots.count { pieces.append(a?.count ?? 0) }
        } }
        // (CI's host job runs an unoptimized build, about 4x slower: 12.6 ms there, against 18.9 the old way)
        let want: Double = _isDebugAssertConfiguration() ? 16 : 4
        check(same && newMs < want, String(format: "Nov 4: the overhang check at four blasts on the keep finds the same pieces as before (%@, %@ falling), its slowest %.2f ms (before %.2f; want under %.0f)",
                                         same ? "same" : "DIFFERENT", "\(pieces)", newMs, oldMs, want))
    }
}
