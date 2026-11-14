import Foundation
import simd

// Nov 14 (Remington's answer to question 716, Nov 13 08:40: "Yes, everything collapses. So yeah, procedural shit has
// to obey physics too"; the world must not crumble on its own as it is made, and 72 fps holds; ledger 127).
//
// Until now ground fell when it was cut loose (GroundCollapse: a piece joined to nothing) or hung too far for its
// thickness within ten cells of a carve (GroundSettle.thinOverhangs). Ground that was still joined stood whatever was
// asked of it: a hill of earth over a cavern blasted out under it, a rock the size of a house left on a neck one
// cell thick. A structure in that state comes down since the physics revamp (StructureFlow: its weight must find a
// way to the ground through joints that can carry it). The ground is now weighed the same way.
//
// When ground is opened (dug, blasted, carved) the cells opened are noted. Once the carving there has been quiet for
// a moment, the ground in a box round them is read (a slice a frame) and weighed off the frame, twice: as it was
// before those cells were opened, and as it is now. Ground whose weight found a way down before and finds none now
// comes down (GroundCollapse.drop, in lots when it is large). Ground that had no way down even before, a natural
// overhang, an arch, a floating island the generator made, is left as it is: this change did not do it, so the
// world never crumbles on its own, at generation or beside a carve.
//
// Strengths are the materials' own (Structure.Mat): a joint hung or sideways carries StructureFlow.side (earth, sand
// and gravel about one cell and a quarter, rock fifteen); pressed down, ground carries what rock does (it does not
// crush under its own hill). So earth rooms up to about seventeen cells across and tunnels up to nine hold, wider
// ones cave in up to the surface; rock holds any span a carve makes and gives way at a neck. A built block under
// ground carries it (a prop in a tunnel). The box's outer cells are held by what lies past them.
// BS_GROUNDWEIGH=0: off. BS_GROUNDWEIGHLOG=1: a line a weighing.
final class GroundWeighState {
    var carved: [(IVec3, BlockID)] = []      // ground opened and not yet weighed
    var ticks = 0
    var lastCarve = 0, firstCarve = -1
    var job: GroundWeigh.Job?
}

enum GroundWeigh {
    static let enabled = ProcessInfo.processInfo.environment["BS_GROUNDWEIGH"] != "0"
    static let log = ProcessInfo.processInfo.environment["BS_GROUNDWEIGHLOG"] == "1"
    static let reach = 8                     // the box: the carve's cells and this far round them
    static let maxSide = 44                  // (at most this many cells a side: a naval crater and its surroundings)
    static let maxCarved = 20_000
    static var quietTicks = 20, longestWait = 144
    static var sliceSeconds = 0.0006, sliceFloor = 0.0002
    // (harness)
    static var weighed = 0, fell = 0, spared = 0, drops = 0
    static var lastCells = 0, lastSolveMs = 0.0, worstSolveMs = 0.0, worstSliceMs = 0.0, lastReadMs = 0.0

    final class Job {
        let lo: IVec3, hi: IVec3             // the box, both ends in
        var carved: [IVec3: BlockID]
        var cells: [IVec3] = []
        var weight: [Float] = [], bond: [Float] = [], crush: [Float] = []
        var ground: [UInt8] = [], held: [Bool] = [], open: [Bool] = []       // (open: carved, not ground any more)
        var x: Int, z: Int                   // the column the read has reached
        var read = false, solving = false, dirty = false
        var readSeconds = 0.0
        let lock = NSLock()
        var falls: [IVec3]? = nil            // (the worker's answer, under the lock)
        var sparedCount = 0, solveMs = 0.0
        init(lo: IVec3, hi: IVec3, carved: [IVec3: BlockID]) { self.lo = lo; self.hi = hi; self.carved = carved; x = lo.x; z = lo.z }
        @inline(__always) func inside(_ p: IVec3) -> Bool { p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y && p.z >= lo.z && p.z <= hi.z }
    }

    // What a cell of ground is made of, for the weighing. Pressed down it bears what rock bears.
    static let mats: [Structure.Mat] = (0..<Blocks.count).map { i in
        let m = Structure.material(i) ?? Structure.soil
        return Structure.Mat(weight: m.weight, bond: StructureFlow.side(m), reach: m.reach, crush: max(m.crushCap, 6000))
    }

    // A cell of ground was opened (FieldTerrain.fieldSphere, World.fieldBlockChanged). `was`: what it was made of.
    static func note(_ w: World, _ p: IVec3, _ was: BlockID) {
        guard enabled, w.fieldTerrain, w.frame == nil, !w.collapsing, !w.restoring, p.y > 1 else { return }
        let st = w.groundWeigh
        if st.carved.count >= maxCarved { st.carved.removeFirst(maxCarved / 4) }       // (forgotten: weighed as if always open)
        st.carved.append((p, was))
        st.lastCarve = st.ticks
        if st.firstCarve < 0 { st.firstCarve = st.ticks }
        if let j = st.job, j.inside(p) { j.dirty = true }
    }

    // Every frame (Game.tick, after GroundCollapse).
    static func tick(_ g: Game) {
        let w = g.world
        guard enabled, w.fieldTerrain else { return }
        let st = w.groundWeigh
        st.ticks += 1
        let paced = CraterJob.inTick && !(World.deterministic || Rand.deterministic)
        if st.job == nil {
            guard !st.carved.isEmpty else { return }
            guard st.ticks - st.lastCarve >= quietTicks || st.ticks - st.firstCarve >= longestWait else { return }
            start(w)
        }
        guard let j = st.job else { return }
        if !j.read {
            let room = paced ? max(sliceFloor, min(sliceSeconds, CraterJob.allowance())) : Double.infinity
            let t0 = CFAbsoluteTimeGetCurrent()
            let done = readStep(w, j, until: t0 + room)
            let dt = CFAbsoluteTimeGetCurrent() - t0
            if paced { CraterJob.spend(dt) }
            j.readSeconds += dt
            worstSliceMs = max(worstSliceMs, dt * 1000)
            guard done else { return }
            j.read = true
        }
        if !j.solving {
            j.solving = true
            if paced {
                DispatchQueue.global(qos: .utility).async { solve(j) }
                return
            }
            solve(j)
        }
        j.lock.lock(); let falls = j.falls; j.lock.unlock()
        guard let falls else { return }
        st.job = nil
        // (carved again inside the box while it was read or weighed: weighed again, with those cells, once quiet)
        if j.dirty { st.lastCarve = st.ticks; if st.firstCarve < 0 { st.firstCarve = st.ticks }; return }
        st.carved.removeAll { j.carved[$0.0] != nil }
        if st.carved.isEmpty { st.firstCarve = -1 } else { st.firstCarve = st.ticks }
        weighed += 1
        lastCells = j.cells.count; lastSolveMs = j.solveMs; lastReadMs = j.readSeconds * 1000
        worstSolveMs = max(worstSolveMs, j.solveMs)
        spared += j.sparedCount
        let t0 = CFAbsoluteTimeGetCurrent()
        let n = falls.isEmpty ? 0 : drop(g, falls)
        if paced && n > 0 { CraterJob.spend(CFAbsoluteTimeGetCurrent() - t0) }
        if log {
            print(String(format: "groundweigh: %d cells in a box %d x %d x %d round %d carved (read %.1f ms, worst slice %.2f ms; weighed %.1f ms off the frame): %@",
                         j.cells.count, j.hi.x - j.lo.x + 1, j.hi.y - j.lo.y + 1, j.hi.z - j.lo.z + 1, j.carved.count,
                         j.readSeconds * 1000, worstSliceMs, j.solveMs,
                         n == 0 ? "stands" + (j.sparedCount > 0 ? " (\(j.sparedCount) cells had no way down before either: left)" : "")
                                : "\(n) cells come down" + (j.sparedCount > 0 ? " (\(j.sparedCount) more had no way down before either: left)" : "")))
        }
    }

    // The next box: round the newest carved cell, every carved cell within two reaches of it, grown by the reach.
    private static func start(_ w: World) {
        let st = w.groundWeigh
        guard let c0 = st.carved.last?.0 else { return }
        let near = 2 * reach
        var lo = c0, hi = c0
        for (p, _) in st.carved where abs(p.x - c0.x) <= near && abs(p.y - c0.y) <= near && abs(p.z - c0.z) <= near {
            lo = IVec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)); hi = IVec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        lo = IVec3(lo.x - reach, lo.y - reach, lo.z - reach); hi = IVec3(hi.x + reach, hi.y + reach, hi.z + reach)
        // (never wider than maxSide: kept round the newest cell)
        func clamp(_ a: Int, _ b: Int, _ c: Int) -> (Int, Int) {
            guard b - a + 1 > maxSide else { return (a, b) }
            let l = max(a, min(c - maxSide / 2, b - maxSide + 1))
            return (l, l + maxSide - 1)
        }
        let (x0, x1) = clamp(lo.x, hi.x, c0.x), (y0, y1) = clamp(lo.y, hi.y, c0.y), (z0, z1) = clamp(lo.z, hi.z, c0.z)
        lo = IVec3(x0, max(1, y0), z0); hi = IVec3(x1, min(CH - 1, max(y1, 2)), z1)
        var inBox: [IVec3: BlockID] = [:]
        // (the cells in the box's inside: one on its outer layer is held by what lies past, opened or not)
        for (p, b) in st.carved where p.x > lo.x && p.x < hi.x && p.y > lo.y && p.y < hi.y && p.z > lo.z && p.z < hi.z { inBox[p] = b }
        guard !inBox.isEmpty else { st.carved.removeAll { $0.0 == c0 }; if st.carved.isEmpty { st.firstCarve = -1 }; return }
        st.job = Job(lo: lo, hi: hi, carved: inBox)
    }

    // Reads the box a column at a time; true when all of it is read.
    private static func readStep(_ w: World, _ j: Job, until deadline: Double) -> Bool {
        var k = ChunkCursor(w)
        let mats = GroundWeigh.mats, fieldBlocks = FieldMat.blocks
        var n = 0
        while j.z <= j.hi.z {
            while j.x <= j.hi.x {
                n += 1
                if n & 7 == 0 && CFAbsoluteTimeGetCurrent() > deadline { return false }
                let x = j.x, z = j.z
                j.x += 1
                let side = x == j.lo.x || x == j.hi.x || z == j.lo.z || z == j.hi.z
                guard let ch = k.chunk(x, z), !ch.hollow else {
                    // (not loaded: held by what lies there)
                    for y in j.lo.y...j.hi.y {
                        j.cells.append(IVec3(x, y, z)); j.weight.append(0); j.bond.append(1e6); j.crush.append(1e6)
                        j.ground.append(0); j.held.append(true); j.open.append(false)
                    }
                    continue
                }
                let ci = (x & 15, z & 15)
                for y in j.lo.y...j.hi.y {
                    let i = Chunk.index(ci.0, y, ci.1)
                    let p = IVec3(x, y, z)
                    let isGround = ch.blocks.ground(i)
                    var block: BlockID = AIR
                    var open = false
                    if isGround { block = fieldBlocks[Int(ch.blocks.material(i))] }
                    else if let b = j.carved[p] {
                        // (a prop set where the ground was dug stands in for it no more: the cell is the prop's)
                        if Structure.part(&k, x, y, z) != nil || Structure.anchor(&k, x, y, z) { continue }
                        block = b; open = true
                    }
                    else { continue }
                    let m = mats[Int(block)]
                    let shell = side || y == j.lo.y || y == j.hi.y
                    var gr: UInt8 = 0
                    if !shell && !open && y > 1 {
                        // (on a built block or bedrock: carried by it, a prop under a tunnel's roof)
                        let below = Chunk.index(ci.0, y - 1, ci.1)
                        if !ch.blocks.ground(below) && (Structure.part(&k, x, y - 1, z) != nil || Structure.anchor(&k, x, y - 1, z)) { gr = 1 }
                    }
                    j.cells.append(p); j.weight.append(m.weight); j.bond.append(m.bond); j.crush.append(m.crush)
                    j.ground.append(gr); j.held.append(shell && !open || y <= 1); j.open.append(open)
                }
            }
            j.x = j.lo.x
            j.z += 1
        }
        return true
    }

    // The weighing (a worker): as it is now; if anything has no way down, as it was before, and what had none then
    // either is left out.
    private static func solve(_ j: Job) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let n = j.cells.count
        // (a grid of the box for the columns standing alone: StructureFlow.slender)
        let sx = j.hi.x - j.lo.x + 1, sy = j.hi.y - j.lo.y + 1, sz = j.hi.z - j.lo.z + 1
        var grid = [Int32](repeating: -1, count: sx * sy * sz)
        @inline(__always) func slot(_ p: IVec3) -> Int { ((p.y - j.lo.y) * sz + (p.z - j.lo.z)) * sx + (p.x - j.lo.x) }
        for i in 0..<n { grid[slot(j.cells[i])] = Int32(i) }
        func piece(before: Bool) -> StructureFlow.Piece {
            var pc = StructureFlow.Piece()
            pc.cells = j.cells; pc.ground = j.ground; pc.held = j.held
            pc.weight = j.weight; pc.bond = j.bond; pc.crush = j.crush
            for i in 0..<n {
                if j.open[i] && !before { pc.weight[i] = 0; pc.bond[i] = 0; pc.crush[i] = 0; continue }
                if j.held[i] { continue }
                let c = j.cells[i]
                var beside = 0
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let q = IVec3(c.x + dx, c.y, c.z + dz)
                    guard j.inside(q) else { beside += 1; continue }
                    let o = grid[slot(q)]
                    if o >= 0 && (before || !j.open[Int(o)]) { beside += 1 }
                }
                pc.crush[i] *= StructureFlow.slender(beside)
            }
            return pc
        }
        var falls: [IVec3] = []
        var sparedCount = 0
        let now = StructureFlow.solve(piece(before: false))
        let down = now.falls.filter { !j.open[$0] }
        if !down.isEmpty {
            let was = StructureFlow.solve(piece(before: true))
            var hadNone = [Bool](repeating: false, count: n)
            for i in was.falls { hadNone[i] = true }
            for i in down { if hadNone[i] { sparedCount += 1 } else { falls.append(j.cells[i]) } }
        }
        j.lock.lock()
        j.sparedCount = sparedCount
        j.solveMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        j.falls = falls
        j.lock.unlock()
    }

    // What comes down, piece by joined piece; what hung beyond each and what stood on it is the ground checks' next
    // (GroundCollapse's queue). The count of cells dropped.
    private static func drop(_ g: Game, _ falls: [IVec3]) -> Int {
        let w = g.world
        var left = Set<IVec3>()
        for c in falls where w.isGround(c) { left.insert(c) }
        var total = 0
        while let s = left.first {
            var part: [IVec3] = [s], head = 0
            left.remove(s)
            while head < part.count {
                let c = part[head]; head += 1
                for d in World.allDirs { let q = c + d; if left.remove(q) != nil { part.append(q) } }
            }
            var lo = s, hi = s
            for c in part { lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)); hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z)) }
            if part.count > GroundCollapse.maxCells { GroundSettle.dropBig(g, part) } else { GroundCollapse.drop(g, part) }
            total += part.count
            drops += 1
            let ext = max(hi.x - lo.x, hi.z - lo.z)
            w.collapseQueue.append((IVec3((lo.x + hi.x) / 2, lo.y, (lo.z + hi.z) / 2), min(6, ext / 2 + 2)))
        }
        fell += total
        return total
    }

    // Checks: everything noted so far weighed now, on this thread.
    static func settle(_ g: Game) {
        let st = g.world.groundWeigh
        var n = 0
        while (!st.carved.isEmpty || st.job != nil) && n < 64 {
            st.lastCarve = st.ticks - quietTicks
            tick(g)
            n += 1
        }
    }
}
