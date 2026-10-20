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
        @inline(__always) func open(_ j: Int) -> Bool {
            j >= 0 && j < n && fd[j] <= 0 && !collide[Int(b[j])] && !Blocks.isLiquid(b[j])
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
        var comp: [Int] = [], stack: [Int] = [], fix: [Int] = []
        for s in 0..<n where !seen[s] && Blocks.isLiquid(b[s]) {
            seen[s] = true
            comp.removeAll(keepingCapacity: true); stack.removeAll(keepingCapacity: true); fix.removeAll(keepingCapacity: true)
            stack.append(s)
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
                    if Blocks.isLiquid(b[j]) { if !seen[j] { seen[j] = true; stack.append(j) }; continue }
                    if k == 4 { tops += 1; if fd[j] > 0 { roofed += 1 }; continue }   // (a pool's top is open; air, a plant)
                    guard !collide[Int(b[j])] else { continue }
                    guard fd[j] < rim else { continue }
                    // A low rim with open air under it: the pool stands in a wall over a drop (15:38).
                    if k < 4 && open(j - CSQ) { overDrop = true }
                    if k == 5 {
                        if fd[j] <= 0 && !solid(j - CSQ) { floats = true }      // over open air
                        else if fd[j] <= 0 || open(j - CSQ) { fix.append(j) }   // a gap, or a thin floor over air
                    } else if fd[j] <= 0 {
                        fix.append(j); openSides += 1                          // open beside it
                    } else if open(j + CSQ) {
                        fix.append(j)                                          // a lip lower than the water's top
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
            if !big && held { for j in fix where !joins(j) { held = false; break } }
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
            for j in fix where fd[j] < rim && (!big || joins(j)) {
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
}
