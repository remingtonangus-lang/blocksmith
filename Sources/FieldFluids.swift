import Foundation

// P378 step 2 (Oct 17 15:38 voice note: "water clinging to the wall"): the generator lays water and lava on the block
// world's ground; the field draws that ground smoothed, so a pool cut into a steep wall could end up with its rim
// rounded off below the water's top (or open: a block corner the field cut away). Its sources never flow (a source
// stays put), and its surface was drawn as a sheet standing out of the wall, its sides as vertical faces over nothing.
// When a chunk's field is made, the drawn ground is made to hold every pool the generator meant, cell by cell round it:
//   - a side open (no ground, nothing solid built), or a lip: ground beside it lower than the water's drawn top (7/8 of
//     the cell: 3/8 block of ground past the cell's middle, 12 in 1/32) with open air over it, or a gap or thin floor
//     under it, is raised to that height (its rim, of the rock beside it), where it joins ground already there (thin
//     ground beside a pool drew its water as a sheet or a sheer face standing over the ground: 15:38, 15:56);
//   - a body over open air, in a wall over a drop (a low rim with open air under it), in a crack in the wall (ground
//     straight over most of its top and on every side: it becomes rock), or with a rim that would join no ground,
//     isn't a pool and is taken out: water on a wall isn't there (15:38).
// Only small bodies (64 cells or fewer, not reaching the chunk's side) are taken out; lakes, the sea and lava seas
// keep their water and have their rims raised where a rim joins ground.
extension FieldTerrain {
    static var perchedDropped = 0, rimsRaised = 0           // (harness tallies, cells; not thread-exact)
    static let rim: Int8 = 12

    // Harness (questcheck --poollog): each body taken out, at its first cell, with the rule that took it.
    static var poolLog: [String]? = CommandLine.arguments.contains("--poollog") ? [] : nil
    static let poolLock = NSLock()

    static func holdPools(_ b: inout [BlockID], _ fd: inout [Int8], _ fm: inout [UInt8], cx: Int = 0, cz: Int = 0) {
        let n = min(b.count, fd.count, fm.count)
        guard n > 0 else { return }
        let collide = Blocks.collide
        // P474 (generation speed): the registry's tables read once, not per cell (every Blocks.isLiquid in the scan
        // of a chunk's 98,304 cells retained and released the table: about two fifths of a field chunk's making).
        let fluidLevel = Blocks.fluidLevel, fluidKind = Blocks.fluidKind
        @inline(__always) func liquid(_ id: BlockID) -> Bool { fluidLevel[Int(id)] >= 0 }
        @inline(__always) func open(_ j: Int) -> Bool {
            j >= 0 && j < n && fd[j] <= 0 && !collide[Int(b[j])] && !liquid(b[j])
        }
        @inline(__always) func solid(_ j: Int) -> Bool { j >= 0 && j < n && (fd[j] > 0 || collide[Int(b[j])]) }
        // A cell's 6 neighbours inside the chunk (columns: x and z within 0...15).
        @inline(__always) func around(_ j: Int, _ f: (Int) -> Void) {
            let x = j & 15, z = (j >> 4) & 15
            if x < 15 { f(j + 1) }; if x > 0 { f(j - 1) }
            if z < 15 { f(j + CS) }; if z > 0 { f(j - CS) }
            if j + CSQ < n { f(j + CSQ) }; if j - CSQ >= 0 { f(j - CSQ) }
        }
        var seen = [Bool](repeating: false, count: n)
        var comp: [Int] = [], stack: [Int] = [], fix: [(j: Int, side: Bool)] = []
        for s in 0..<n where !seen[s] && liquid(b[s]) {
            seen[s] = true
            comp.removeAll(keepingCapacity: true); stack.removeAll(keepingCapacity: true); fix.removeAll(keepingCapacity: true)
            stack.append(s)
            let lava = fluidKind[Int(b[s])] == 2
            var side = false, floats = false, overDrop = false, tops = 0, roofed = 0, openSides = 0
            while let i = stack.popLast() {
                comp.append(i)
                let x = i & 15, z = (i >> 4) & 15
                if x == 0 || x == 15 || z == 0 || z == 15 { side = true }
                for k in 0..<6 {
                    let step: Int, inside: Bool
                    switch k {
                    case 0: step = 1; inside = x < 15
                    case 1: step = -1; inside = x > 0
                    case 2: step = CS; inside = z < 15
                    case 3: step = -CS; inside = z > 0
                    case 4: step = CSQ; inside = true
                    default: step = -CSQ; inside = true
                    }
                    guard inside else { continue }
                    let j = i + step
                    guard j >= 0 && j < n else { continue }
                    if liquid(b[j]) { if !seen[j] { seen[j] = true; stack.append(j) }; continue }
                    if k == 4 { tops += 1; if fd[j] > 0 { roofed += 1 }; continue }   // (a pool's top is open; air, a plant)
                    guard !collide[Int(b[j])] else { continue }
                    guard fd[j] < rim else { continue }
                    // A low rim with open air under it: the pool stands in a wall over a drop (15:38).
                    if k < 4 && open(j - CSQ) { overDrop = true }
                    if k == 5 {
                        if fd[j] <= 0 && !solid(j - CSQ) { floats = true }      // over open air
                        else if fd[j] <= 0 || open(j - CSQ) { fix.append((j, false)) }   // a gap, or a thin floor over air
                    } else if fd[j] <= 0 {
                        fix.append((j, true)); openSides += 1                  // open beside it
                    } else if open(j + CSQ) {
                        fix.append((j, true))                                  // a lip lower than the water's top
                    }
                }
            }
            // A rim joins ground already there (a raised cell with none beside it would float).
            @inline(__always) func joins(_ j: Int) -> Bool {
                if fd[j] > 0 { return true }
                var any = false
                around(j) { m in if fd[m] > 0 || collide[Int(b[m])] { any = true } }
                return any
            }
            // Larger bodies (lakes, the sea, lava seas) and ones reaching the chunk's side (the rest unseen) are never
            // taken out; their rims are raised where they join ground (the lava sea's edge at 15:56 stood as a sheer step).
            let big = comp.count > 64 || side
            // Ground straight over most of its top and on every side: water in a crack in the wall, not a pool (15:38:
            // the dark slot along the cave wall held a row of springs, drawn as a strip of water on the wall). A pool
            // under a low cave roof opens to the cave on a side and stays.
            var held = !floats && !overDrop && !(roofed * 2 >= tops && openSides == 0)
            if !big && held { for (j, _) in fix where !joins(j) { held = false; break } }
            if !big && !held, poolLog != nil {
                let i = comp[0], why = floats ? "floats" : overDrop ? "over a drop" : roofed * 2 >= tops && openSides == 0 ? "crack" : "no join"
                poolLock.lock()
                poolLog!.append("\(cx * CS + (i & 15)) \(i / CSQ) \(cz * CS + ((i >> 4) & 15)) \(comp.count) \(why) tops \(tops) roofed \(roofed) open \(openSides)")
                poolLock.unlock()
            }
            if !big && !held {
                // A sealed pocket (a crack in the wall) becomes the rock round it: its walls are thinner than a cell,
                // which the drawn ground can't hold, so emptied it showed as a dark slot (15:38) or a hole (15:56).
                let sealed = !floats && !overDrop && roofed * 2 >= tops && openSides == 0
                for i in comp {
                    b[i] = AIR; perchedDropped += 1
                    guard sealed else { continue }
                    var count: [UInt8: Int] = [:]
                    around(i) { m in if fd[m] > 0 && fm[m] != 0 { count[fm[m], default: 0] += 1 } }
                    if let best = count.max(by: { $0.value < $1.value })?.key { fm[i] = best; fd[i] = 32 }
                }
                continue
            }
            for (j, side) in fix where fd[j] < rim && (!big || joins(j)) {
                // P412 (a): beside a big body (the sea, a lake) a lip or a low bank with ground under it stays as it is:
                // the drawn level runs on over ground lying under it (Mesher's fluid nets), so the shore is the
                // ground's own curve. Raised to the top, every such cell was a step of sand along the sea's edge and
                // a patch of sand flush with the water on a shelf (22:10, 22:24). A side open under it (a drop) is
                // still raised: a wall, not a bank.
                if big && side && solid(j - CSQ) { continue }
                // P462 (Oct 25 16:44, a volcano's crater: "One cave is at its opening and the lava kind of just ignores
                // it, doesn't flow into it... Not confined by its pre-generated boundaries"): lava's open sides stay
                // open. A rim raised there walled a cave's mouth off from the lake; now the lake spills into it (its
                // edge cells are springs, World.springs) and runs down as a lavafall. Lips with ground in them are
                // still raised (the sheet standing over thin ground, 15:56).
                if lava && side && fd[j] <= 0 { continue }
                if fd[j] <= 0 || fm[j] == 0 {
                    // The rock beside it (the commonest material among its neighbours).
                    var count: [UInt8: Int] = [:]
                    around(j) { m in if fd[m] > 0 && fm[m] != 0 { count[fm[m], default: 0] += 1 } }
                    if let best = count.max(by: { $0.value < $1.value })?.key { fm[j] = best }
                    if fm[j] == 0 { continue }
                }
                fd[j] = rim
                rimsRaised += 1
            }
        }
    }

    // P489 (night lane, Oct 30): the generator lays its seas, lakes and lava seas on the block world's ground, and the
    // field smooths that ground: a seabed cell the drawn ground now fills only a little (a quarter block or less), and a
    // cell of the old ground the smoothing left empty inside a reef or under a lava sea, was left as air under the fluid.
    // Each one filled from the water over it as soon as its chunk woke near the player: flying at 20 b/s, 3,600 cells
    // flowed in 40 s (water running down into the seabed, through the reefs and the lava seas), every step re-meshing
    // the surface sections of land already drawn, and the sea grass over those cells popped off as its floor turned to
    // water. Such cells hold their fluid as the chunk is made:
    //   - an open cell (air, or ground filling a quarter block or less) under a source of water or lava, with something
    //     under it (ground, a solid block, the same fluid);
    //   - a small enclosed pocket of open cells (64 or fewer, not reaching the chunk's side, none higher than the source
    //     it touches) whose walls are ground, solid blocks or the same fluid. (P489 part 2: the height limit. Water
    //     doesn't climb, but a pocket open to it filled up past the water's own level: in questcheck --basetest a
    //     Capital citadel's patrol came back a man short with part 1 alone, and is whole again with the limit.)
    // A shore's cells under open air are left as they were (the sea runs onto the drawn beach: P363 (d), P412 (a)), and
    // a cave under a lake's floor still takes its waterfall (the pocket reaches far).
    static var pocketsFilled = 0                           // (harness tally, cells; not thread-exact)

    static func fillPockets(_ b: inout [BlockID], _ fd: [Int8]) {
        let n = min(b.count, fd.count)
        guard n > CSQ else { return }
        let fluidLevel = Blocks.fluidLevel, fluidKind = Blocks.fluidKind, collide = Blocks.collide
        @inline(__always) func open(_ j: Int) -> Bool { b[j] == AIR && fd[j] <= 8 }
        // Ground past a quarter block, a solid block, or the same fluid: what holds a fluid cell over it.
        @inline(__always) func holds(_ j: Int, _ kind: UInt8) -> Bool {
            fd[j] > 8 || collide[Int(b[j])] || (fluidLevel[Int(b[j])] >= 0 && fluidKind[Int(b[j])] == kind)
        }
        var filled = 0
        // Under a source, top down (a cell filled here holds the one over it only if it was already a source).
        for i in stride(from: n - CSQ - 1, through: CSQ, by: -1) where open(i) {
            let up = b[i + CSQ]
            guard up == WATER || up == LAVA, holds(i - CSQ, fluidKind[Int(up)]) else { continue }
            b[i] = up; filled += 1
        }
        // Enclosed pockets. Open air over the highest thing in its column is sky, never a pocket: a flood that meets it
        // stops there (a sea's surface and every shore start one).
        var top = [Int](repeating: -1, count: CSQ)
        for i in stride(from: n - 1, through: 0, by: -1) where top[i & (CSQ - 1)] < 0 && !open(i) { top[i & (CSQ - 1)] = i }
        let nbr = [1, -1, CS, -CS, CSQ, -CSQ]
        var seen = [Bool](repeating: false, count: n)
        var comp: [Int] = [], stack: [Int] = []
        for s in 0..<n where b[s] == WATER || b[s] == LAVA {
            let src = b[s], kind = fluidKind[Int(src)]
            let sx = s & 15, sz = (s >> 4) & 15
            for k in 0..<6 where k != 4 {                       // (over a fluid: air, or the pocket's own top cell)
                let j: Int
                switch k {
                case 0: guard sx < 15 else { continue }; j = s + 1
                case 1: guard sx > 0 else { continue }; j = s - 1
                case 2: guard sz < 15 else { continue }; j = s + CS
                case 3: guard sz > 0 else { continue }; j = s - CS
                default: j = s - CSQ
                }
                guard j >= 0 && j < n, !seen[j], open(j), j < top[j & (CSQ - 1)] else { continue }
                let level = s / CSQ                             // (no higher than the source: water doesn't climb)
                seen[j] = true
                comp.removeAll(keepingCapacity: true); stack.removeAll(keepingCapacity: true)
                stack.append(j)
                var ok = true
                while ok, let i = stack.popLast() {
                    comp.append(i)
                    let x = i & 15, z = (i >> 4) & 15
                    if comp.count > 64 || x == 0 || x == 15 || z == 0 || z == 15 || i < CSQ || i + CSQ >= n || i > top[i & (CSQ - 1)]
                        || i / CSQ > level {
                        ok = false; break
                    }
                    for o in nbr {
                        let m = i + o
                        if open(m) { if !seen[m] { seen[m] = true; stack.append(m) } }
                        else if holds(m, kind) || fluidLevel[Int(b[m])] < 0 { continue }   // (a wall; a plant or a fitting)
                        else { ok = false; break }                                          // (another fluid)
                    }
                }
                guard ok else { continue }
                for i in comp { b[i] = src }
                filled += comp.count
            }
        }
        pocketsFilled &+= filled
    }
}

