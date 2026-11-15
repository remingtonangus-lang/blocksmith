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
    // Ground opened and not yet weighed. `prop`: not ground but a built block taken from under ground (it carried the
    // ground over it before).
    var carved: [(p: IVec3, was: BlockID, prop: Bool)] = []
    var ticks = 0
    var lastCarve = 0, firstCarve = -1
    var job: GroundWeigh.Job?
    // What a weighing found without a way down, coming down a few lots a frame (bottom first).
    var pending: [[IVec3]] = []
    var pendingOf: [IVec3] = []              // (the carved cells of the weighing they came from)
    var pendingFell = 0, pendingSpared = 0
    var seeds = Set<IVec3>()                 // (where the older ground checks look afterwards: a fallen cell per eight cells of it)
    var seedLots = Set<IVec3>()
    var objectLooks: [IVec3] = []            // (fallen cells round which what stood on the ground is still to fall)
    var own = false                          // (its own drops: noted by itself, with the rest)
    init() { _ = GroundWeigh.mats }          // (built at load, not in the first weighing's frame)
    var busy: Bool { !carved.isEmpty || job != nil || !pending.isEmpty || !objectLooks.isEmpty }
}

enum GroundWeigh {
    static let enabled = Env.all["BS_GROUNDWEIGH"] != "0"
    static let log = Env.all["BS_GROUNDWEIGHLOG"] == "1"
    // (to tell the parts' costs apart in a soak: BS_GWSEEDS=0 no look by the older checks after a fall, BS_GWNOTEOLD=0
    // their drops not noted, BS_GWPROPS=0 props not noted, BS_GWQUEUE=dispatch the weighing on a utility queue)
    static let seedsOn = Env.all["BS_GWSEEDS"] != "0"
    static let oldSeeds = Env.all["BS_GWSEEDS"] == "old"
    static let noteOld = Env.all["BS_GWNOTEOLD"] != "0"
    static let propsOn = Env.all["BS_GWPROPS"] != "0"
    static let onPool = Env.all["BS_GWQUEUE"] != "dispatch"
    static let reach = 8                     // the box: the carve's cells and this far round them
    static let maxSide = 44                  // (at most this many cells a side: a naval crater and its surroundings)
    static let maxCarved = 60_000
    static var quietTicks = 20, longestWait = 144
    static var sliceSeconds = 0.0003, sliceFloor = 0.0001
    static var objectSeconds = 0.0004
    static let lot = 4                       // what comes down goes in lots of this many cells a side
    // (harness)
    static var weighed = 0, fell = 0, spared = 0, drops = 0
    static var lastCells = 0, lastSolveMs = 0.0, worstSolveMs = 0.0, worstSliceMs = 0.0, lastReadMs = 0.0, worstDropMs = 0.0

    final class Job {
        let lo: IVec3, hi: IVec3             // the box, both ends in
        var carved: [IVec3: BlockID]
        var props: Set<IVec3>                // (built blocks taken from under ground: they carried it before)
        var cells: [IVec3] = []
        var weight: [Float] = [], bond: [Float] = [], crush: [Float] = []
        var ground: [UInt8] = [], held: [Bool] = [], open: [Bool] = []       // (open: carved, not ground any more)
        var groundWas: [UInt8] = []          // (as it stood before: on a prop since taken, too)
        var x: Int, z: Int                   // the column the read has reached
        var read = false, solving = false, changed = false
        var readSeconds = 0.0
        let lock = NSLock()
        var falls: [IVec3]? = nil            // (the worker's answer, under the lock)
        var sparedCount = 0, solveMs = 0.0
        init(lo: IVec3, hi: IVec3, carved: [IVec3: BlockID], props: Set<IVec3>) { self.lo = lo; self.hi = hi; self.carved = carved; self.props = props; x = lo.x; z = lo.z }
        @inline(__always) func inside(_ p: IVec3) -> Bool { p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y && p.z >= lo.z && p.z <= hi.z }
    }

    // What a cell of ground is made of, for the weighing. Pressed down it bears what rock bears.
    static let mats: [Structure.Mat] = (0..<Blocks.count).map { i in
        let m = Structure.material(i) ?? Structure.soil
        return Structure.Mat(weight: m.weight, bond: StructureFlow.side(m), reach: m.reach, crush: max(m.crushCap, 6000))
    }

    // A cell of ground was opened (FieldTerrain.fieldSphere, World.fieldBlockChanged). `was`: what it was made of.
    // Ground the older checks let fall (a piece cut loose, a thin overhang) is noted too: it stood before the carve.
    static func note(_ w: World, _ p: IVec3, _ was: BlockID, prop: Bool = false) {
        guard enabled, w.fieldTerrain, w.frame == nil, !w.restoring, p.y > 1 else { return }
        let st = w.groundWeigh
        guard !st.own, noteOld || !w.collapsing else { return }
        if st.carved.count >= maxCarved { st.carved.removeFirst(maxCarved / 4) }       // (forgotten: weighed as if always open)
        st.carved.append((p, was, prop))
        st.lastCarve = st.ticks
        if st.firstCarve < 0 { st.firstCarve = st.ticks }
    }
    // A built block was taken from a field world: if ground lay on it, it was that ground's prop.
    static func propTaken(_ w: World, _ p: IVec3, _ old: BlockID) {
        guard enabled, propsOn, w.frame == nil, !w.restoring, Structure.table[Int(old)] != nil, w.groundAt(p.x, p.y + 1, p.z) else { return }
        note(w, p, old, prop: true)
    }
    // Ground or a built block was set inside the box of a weighing under way: its answer is of a world that is gone.
    @inline(__always) static func placed(_ w: World, _ p: IVec3) {
        if let j = w.groundWeigh.job, j.inside(p) { j.changed = true }
    }

    // Every frame (Game.tick, after GroundCollapse).
    static var worstTickMs = 0.0             // (all of it that runs on the frame, a tick)
    static func tick(_ g: Game) {
        let w = g.world
        guard enabled, w.fieldTerrain else { return }
        let st = w.groundWeigh
        st.ticks += 1
        guard st.busy else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        step(g, w, st)
        worstTickMs = max(worstTickMs, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }
    private static func step(_ g: Game, _ w: World, _ st: GroundWeighState) {
        let paced = CraterJob.inTick && !(World.deterministic || Rand.deterministic)
        if !st.pending.isEmpty { dropStep(g, paced); return }
        if let c = st.objectLooks.last, !paced || CraterJob.allowance() >= objectSeconds {
            st.objectLooks.removeLast()
            let t0 = CFAbsoluteTimeGetCurrent()
            GroundSettle.objects(g, c, 3)
            if paced { CraterJob.spend(CFAbsoluteTimeGetCurrent() - t0) }
            return
        }
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
                // (on one of the world's workers: below the frame's threads, and held back with them after late frames)
                if onPool { JobPool.shared.add { solve(j) } } else { DispatchQueue.global(qos: .utility).async { solve(j) } }
                return
            }
            solve(j)
        }
        j.lock.lock(); let falls = j.falls; j.lock.unlock()
        guard let falls else { return }
        st.job = nil
        // (ground or a block set inside the box meanwhile: weighed again from the start, after a wait of its own, so
        // a hand that keeps building there costs a box every two seconds and no more. Ground carved meanwhile is in the
        // list for the next weighing; what this one found is acted on: more carving takes support away, it adds none.)
        if j.changed { st.lastCarve = st.ticks; st.firstCarve = st.ticks; return }
        weighed += 1
        lastCells = j.cells.count; lastSolveMs = j.solveMs; lastReadMs = j.readSeconds * 1000
        worstSolveMs = max(worstSolveMs, j.solveMs)
        spared += j.sparedCount
        let live = falls.filter { w.isGround($0) }
        if log {
            print(String(format: "groundweigh: %d cells in a box %d x %d x %d round %d carved (read %.1f ms, worst slice %.2f ms; weighed %.1f ms off the frame): %@",
                         j.cells.count, j.hi.x - j.lo.x + 1, j.hi.y - j.lo.y + 1, j.hi.z - j.lo.z + 1, j.carved.count + j.props.count,
                         j.readSeconds * 1000, worstSliceMs, j.solveMs,
                         live.isEmpty ? "stands" + (j.sparedCount > 0 ? " (\(j.sparedCount) cells had no way down before either: left)" : "")
                                : "\(live.count) cells come down" + (j.sparedCount > 0 ? " (\(j.sparedCount) more had no way down before either: left)" : "")))
        }
        if live.isEmpty {
            // (it stands: these cells are done with)
            st.carved.removeAll { $0.prop ? j.props.contains($0.p) : j.carved[$0.p] != nil }
            if st.carved.isEmpty { st.firstCarve = -1 } else { st.firstCarve = st.ticks }
            return
        }
        // It comes down, in lots from the bottom up, a few a frame. The carved cells stay in the list and the fallen
        // ground joins them: what stood on it or hung from it is weighed next, against the ground as it first was,
        // and so on up to the surface (each round a box round the newest fall).
        var lots: [IVec3: [IVec3]] = [:]
        for c in live { lots[IVec3(floorDiv(c.x, lot), floorDiv(c.y, lot), floorDiv(c.z, lot)), default: []].append(c) }
        st.pending = lots.sorted { $0.key.y != $1.key.y ? $0.key.y > $1.key.y : ($0.key.z != $1.key.z ? $0.key.z > $1.key.z : $0.key.x > $1.key.x) }.map { $0.value }
        st.pendingOf = Array(j.carved.keys) + Array(j.props)
        st.pendingFell = 0; st.pendingSpared = j.sparedCount
        drops += 1
        dropStep(g, paced)
    }

    // A few lots of what is coming down (the last of `pending` first: the lowest).
    private static func dropStep(_ g: Game, _ paced: Bool) {
        let w = g.world, st = w.groundWeigh
        let t0 = CFAbsoluteTimeGetCurrent()
        let room = paced ? max(sliceFloor, min(sliceSeconds, CraterJob.allowance())) : Double.infinity
        while let part = st.pending.popLast() {
            let cells = part.filter { w.isGround($0) }
            if !cells.isEmpty {
                for c in cells { st.carved.append((c, w.block(c.x, c.y, c.z), false)) }
                st.own = true
                GroundCollapse.drop(g, cells)
                st.own = false
                st.pendingFell += cells.count
                fell += cells.count
                let c = cells[0]
                if st.seedLots.insert(IVec3(floorDiv(c.x, 8), floorDiv(c.y, 8), floorDiv(c.z, 8))).inserted { st.seeds.insert(c) }
            }
            if CFAbsoluteTimeGetCurrent() - t0 > room { break }
        }
        let dt = CFAbsoluteTimeGetCurrent() - t0
        if paced { CraterJob.spend(dt) }
        worstDropMs = max(worstDropMs, dt * 1000)
        guard st.pending.isEmpty else { return }
        // What stood on it (blocks, plants, trees) falls: a look a tick, below. What hung from it is this weighing's
        // own next round. (Not the older loose-ground check: looked at from a fallen cell, its thin-overhang rule,
        // blind to the material, took 1,096 cells of standing ground for one cell fallen in the worst-case soak, and
        // the debris of it doubled that scene's particle time. BS_GWSEEDS=old: that look, as the first cut had it.)
        if seedsOn {
            let order = st.seeds.sorted(by: { $0.y != $1.y ? $0.y < $1.y : ($0.z != $1.z ? $0.z < $1.z : $0.x < $1.x) })
            if oldSeeds { for k in order { w.collapseQueue.append((k, 3)) } } else { st.objectLooks.append(contentsOf: order) }
        }
        st.seeds.removeAll(); st.seedLots.removeAll()
        if st.pendingFell == 0 {
            // (nothing of it was ground any more: done with, or the same answer would come for ever)
            let gone = Set(st.pendingOf)
            st.carved.removeAll { gone.contains($0.p) }
        }
        st.pendingOf = []
        st.lastCarve = st.ticks
        st.firstCarve = st.carved.isEmpty ? -1 : st.ticks
    }

    // The next box: round the newest carved cell, every carved cell within two reaches of it, grown by the reach.
    private static func start(_ w: World) {
        let st = w.groundWeigh
        guard let c0 = st.carved.last?.p else { return }
        let near = 2 * reach
        var lo = c0, hi = c0
        for (p, _, _) in st.carved where abs(p.x - c0.x) <= near && abs(p.y - c0.y) <= near && abs(p.z - c0.z) <= near {
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
        var props = Set<IVec3>()
        for (p, b, prop) in st.carved where p.x > lo.x && p.x < hi.x && p.y > lo.y && p.y < hi.y && p.z > lo.z && p.z < hi.z {
            if prop { props.insert(p) } else { inBox[p] = b }
        }
        guard !inBox.isEmpty || !props.isEmpty else { st.carved.removeAll { $0.p == c0 }; if st.carved.isEmpty { st.firstCarve = -1 }; return }
        let j = Job(lo: lo, hi: hi, carved: inBox, props: props)
        // (room for half the box at once: grown as they filled, the arrays were copied a dozen times in the read's slices)
        let room = (hi.x - lo.x + 1) * (hi.y - lo.y + 1) * (hi.z - lo.z + 1) / 2
        j.cells.reserveCapacity(room); j.weight.reserveCapacity(room); j.bond.reserveCapacity(room); j.crush.reserveCapacity(room)
        j.ground.reserveCapacity(room); j.groundWas.reserveCapacity(room); j.held.reserveCapacity(room); j.open.reserveCapacity(room)
        st.job = j
    }

    // Reads the box a column at a time; true when all of it is read.
    private static func readStep(_ w: World, _ j: Job, until deadline: Double) -> Bool {
        var k = ChunkCursor(w)
        let mats = GroundWeigh.mats, fieldBlocks = FieldMat.blocks
        var n = 0
        while j.z <= j.hi.z {
            while j.x <= j.hi.x {
                n += 1
                if n > 1 && CFAbsoluteTimeGetCurrent() > deadline { return false }      // (a look at the clock a column)
                let x = j.x, z = j.z
                j.x += 1
                let side = x == j.lo.x || x == j.hi.x || z == j.lo.z || z == j.hi.z
                guard let ch = k.chunk(x, z), !ch.hollow else {
                    // (not loaded: held by what lies there)
                    for y in j.lo.y...j.hi.y {
                        j.cells.append(IVec3(x, y, z)); j.weight.append(0); j.bond.append(1e6); j.crush.append(1e6)
                        j.ground.append(0); j.groundWas.append(0); j.held.append(true); j.open.append(false)
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
                        if carries(&k, x, y, z) { continue }
                        block = b; open = true
                    }
                    else { continue }
                    let m = mats[Int(block)]
                    let shell = side || y == j.lo.y || y == j.hi.y
                    var gr: UInt8 = 0, was: UInt8 = 0
                    if !shell && y > 1 {
                        // (on a built block or bedrock: carried by it, a prop under a tunnel's roof; not on water)
                        let below = Chunk.index(ci.0, y - 1, ci.1)
                        if !ch.blocks.ground(below) {
                            if carries(&k, x, y - 1, z) { gr = 1; was = 1 }
                            else if j.props.contains(IVec3(x, y - 1, z)) { was = 1 }
                        }
                    }
                    // (ground nothing breaks, bedrock and the like, holds)
                    let fast = Blocks.hardness[Int(block)] < 0
                    j.cells.append(p); j.weight.append(m.weight); j.bond.append(m.bond); j.crush.append(m.crush)
                    j.ground.append(open ? 0 : gr); j.groundWas.append(was); j.held.append((shell || fast) && !open || y <= 1); j.open.append(open)
                }
            }
            j.x = j.lo.x
            j.z += 1
        }
        return true
    }

    // Does the cell hold a built block that carries ground laid on it? (Not a liquid: Structure.anchor's raft rule.)
    @inline(__always) private static func carries(_ k: inout ChunkCursor, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        let b = k.built(x, y, z)
        guard b != AIR, !Blocks.isLiquid(b) else { return false }
        return Structure.part(&k, x, y, z) != nil || Structure.anchor(&k, x, y, z)
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
            pc.cells = j.cells; pc.ground = before ? j.groundWas : j.ground; pc.held = j.held
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

    // Checks: everything noted so far weighed now, on this thread.
    static func settle(_ g: Game) {
        let st = g.world.groundWeigh
        var n = 0
        while st.busy && n < 4096 {
            if let j = st.job, j.solving {
                // (weighed on a worker when the run is paced: waited for)
                j.lock.lock(); let ready = j.falls != nil; j.lock.unlock()
                if !ready { Thread.sleep(forTimeInterval: 0.001); continue }
            }
            st.lastCarve = st.ticks - quietTicks
            tick(g)
            n += 1
        }
    }
}
