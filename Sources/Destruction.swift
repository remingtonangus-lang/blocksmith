import Foundation
import simd

// Destruction physics (Future ideas #7): structures fail and fall as rigid bodies.
//
// After an explosion (or a falling piece breaking what it hits) the blocks round the damage are checked, never the
// whole world: a flood fill through built blocks (anything that isn't terrain: BlockMaterial.anchors) from the cells next
// to the hole, capped at Collapse.cap cells (the edge of a search that hits the cap is taken as held). A piece that no longer touches
// the ground falls. In a piece that does, each block's reach to its support is measured (resting on a block below costs
// nothing, every step sideways or hanging down costs 1 / the strength of the block stepped into, BlockMaterial.strength)
// and a block whose reach passes 1 gives way, with whatever hangs from it. A neck the blast narrowed (a tower's base) fails when
// what stands on it outweighs what it can bear (BlockMaterial.load) or its centre of mass is past the neck's edge: all
// of it above the neck tips over as one body.
// Falling parts become free-moving structures (Ship, debris = true: the ship physics with gravity and terrain contacts),
// tumble, crash (breaking weak blocks and hurting what they hit), and once at rest are laid back into the world as
// ordinary blocks (ShipManager.bake), so they cost nothing afterwards. At most Collapse.maxDebris bodies live at once
// (the oldest is laid down early); pieces of one or two blocks just break.
// World block reads with the last chunk kept (bulk reads over a small region: laying debris down).
final class BlockReader {
    let w: World
    private var lastKey = ChunkKey(x: Int.min, z: Int.min)
    private var lastChunk: Chunk?
    init(_ w: World) { self.w = w }
    @inline(__always) private func chunk(_ x: Int, _ z: Int) -> Chunk? {
        let k = ChunkKey(x: floorDiv(x, CS), z: floorDiv(z, CS))
        if k != lastKey { lastKey = k; lastChunk = w.chunks[k] }
        return lastChunk
    }
    func loaded(_ c: IVec3) -> Bool { chunk(c.x, c.z) != nil }
    func block(_ c: IVec3) -> BlockID {
        if c.y < 0 { return BEDROCK }
        if c.y >= CH { return AIR }
        guard let ch = chunk(c.x, c.z) else { return AIR }
        return ch.blocks[Chunk.index(mod(c.x, CS), c.y, mod(c.z, CS))]
    }
}

enum Collapse {
    static let cap = 6000               // cells one support search may visit
    static let maxDebris = 32           // free-moving debris bodies at once
    static let minPiece = 3             // smaller falling pieces break into items / dust
    static let unit: Int32 = 840        // a block's whole reach in the support search's cost units (840 = 1..8 x 14 divide it)

    static let dirs6 = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
    // Edge neighbours: a thin cell (a diagonal brace, a stair run) is joined to what it touches edge to edge.
    static let dirs12: [IVec3] = {
        var out: [IVec3] = []
        for a in [-1, 1] { for b in [-1, 1] {
            out.append(IVec3(a, b, 0)); out.append(IVec3(a, 0, b)); out.append(IVec3(0, a, b))
        } }
        return out
    }()

    // Built (structural) cell: collides, isn't terrain, isn't a fluid.
    @inline(__always) static func built(_ b: BlockID) -> Bool {
        b != AIR && Blocks.collide[Int(b)] && !BlockMaterial.anchors(b) && !Blocks.isLiquid(b)
    }

    struct Result {
        var falling: [[IVec3]] = []       // connected pieces that fall
        var tip: [(cells: [IVec3], axis: V3)] = []   // pieces that tip over a neck (spin axis)
        var visited = 0
    }

    // A cell -> index table (open addressing on packed coordinates): the support search's sets and maps (Set<IVec3>
    // hashing cost ~13 us a cell, run of ea6ff02: a 1000-block tower took 13.6 ms).
    struct CellTable {
        var keys: [Int64]
        var vals: [Int32]
        var mask: Int
        var count = 0
        static let empty = Int64.min
        init(capacity n: Int) {
            var c = 1024
            while c < n * 2 { c <<= 1 }
            keys = [Int64](repeating: CellTable.empty, count: c)
            vals = [Int32](repeating: -1, count: c)
            mask = c - 1
        }
        @inline(__always) static func pack(_ c: IVec3) -> Int64 {
            let x = Int64(c.x & 0xFFFFFF), z = Int64(c.z & 0xFFFFFF), y = Int64(c.y & 0xFFF)
            return (x << 36) | (z << 12) | y
        }
        @inline(__always) func slot(_ k: Int64) -> Int {
            let h = UInt64(bitPattern: k) &* 0x9E37_79B9_7F4A_7C15
            return Int(truncatingIfNeeded: h >> 34) & mask
        }
        func get(_ c: IVec3) -> Int32? {
            let k = CellTable.pack(c)
            var i = slot(k)
            while keys[i] != CellTable.empty {
                if keys[i] == k { return vals[i] }
                i = (i + 1) & mask
            }
            return nil
        }
        // Inserts c -> v unless present; true if it was new.
        mutating func insert(_ c: IVec3, _ v: Int32) -> Bool {
            if (count + 1) * 2 > keys.count { grow() }
            let k = CellTable.pack(c)
            var i = slot(k)
            while keys[i] != CellTable.empty {
                if keys[i] == k { return false }
                i = (i + 1) & mask
            }
            keys[i] = k
            vals[i] = v
            count += 1
            return true
        }
        private mutating func grow() {
            let ok = keys, ov = vals
            keys = [Int64](repeating: CellTable.empty, count: ok.count * 2)
            vals = [Int32](repeating: -1, count: ok.count * 2)
            mask = keys.count - 1
            for i in 0..<ok.count where ok[i] != CellTable.empty {
                var j = slot(ok[i])
                while keys[j] != CellTable.empty { j = (j + 1) & mask }
                keys[j] = ok[i]
                vals[j] = ov[i]
            }
        }
    }

    // What fails around `holes` (cells just emptied). Reads the world only.
    // `seeds`: built cells to check besides those next to the holes (a whole scene, for the harness's oracle).
    // `restore`: cells read as holding these blocks instead of what the world has (the holes filled back in, to ask
    // what stood before the damage; no necks are judged then).
    static func analyze(_ w: World, around holes: [IVec3], seeds extra: [IVec3] = [], cap: Int = Collapse.cap,
                        restore: [IVec3: BlockID] = [:]) -> Result {
        var res = Result()
        // Block reads with the last chunk kept (the search reads neighbours of neighbours: mostly the same chunk).
        var lastKey = ChunkKey(x: Int.min, z: Int.min)
        var lastChunk: Chunk?
        func block(_ c: IVec3) -> BlockID {
            if !restore.isEmpty, let b = restore[c] { return b }
            if c.y < 0 { return BEDROCK }
            if c.y >= CH { return AIR }
            let k = ChunkKey(x: floorDiv(c.x, CS), z: floorDiv(c.z, CS))
            if k != lastKey { lastKey = k; lastChunk = w.chunks[k] }
            guard let ch = lastChunk else { return AIR }
            return ch.blocks[Chunk.index(mod(c.x, CS), c.y, mod(c.z, CS))]
        }
        var seeds: [IVec3] = extra
        for h in holes {
            for d in dirs6 {
                let c = h + d
                if built(block(c)) { seeds.append(c) }
            }
            if seeds.count > 256 + extra.count { break }
        }
        let holeSet = Set(holes)
        let up = IVec3(0, 1, 0)
        // Wrecks lie as rigid hulks (Wrecks.swift): their blocks hold up what rests on them and never fail.
        let wrecks = w.ships.wrecks.map { (IVec3($0.lo[0], $0.lo[1], $0.lo[2]), IVec3($0.hi[0], $0.hi[1], $0.hi[2])) }
        func inWreck(_ c: IVec3) -> Bool {
            for (lo, hi) in wrecks where c.x >= lo.x && c.x <= hi.x && c.z >= lo.z && c.z <= hi.z {
                if c.y >= lo.y && c.y <= hi.y { return true }
            }
            return false
        }
        // Every cell visited in this call: its index in `cells`; `compOf` says which search found it.
        var table = CellTable(capacity: min(max(cap, 1024) + 64, 4 * cap + seeds.count))
        var cells: [IVec3] = []
        var compOf: [Int32] = []
        var compId: Int32 = -1
        var links: [Int32: [Int32]] = [:]       // edge-to-edge joins of thin cells (both ways)
        for s in seeds where table.get(s) == nil {
            compId += 1
            // The structure: built cells connected to s (cells another, capped, search already took count as held).
            let start = cells.count
            _ = table.insert(s, Int32(start))
            cells.append(s)
            compOf.append(compId)
            var anchoredFlag: [Bool] = [false]
            var head = start
            var open = true
            while head < cells.count {
                let c = cells[head]
                var anchor = !wrecks.isEmpty && inWreck(c)
                var faces = 0
                for d in dirs6 {
                    let n = c + d
                    let b = block(n)
                    if BlockMaterial.anchors(b) && d.y <= 0 { anchor = true }
                    guard built(b) else { continue }
                    faces += 1
                    if let j = table.get(n) {
                        if compOf[Int(j)] != compId { anchor = true }
                        continue
                    }
                    _ = table.insert(n, Int32(cells.count))
                    cells.append(n)
                    compOf.append(compId)
                    anchoredFlag.append(false)
                }
                if faces <= 1 {
                    // A thin cell: joined edge to edge too (a diagonal brace under a landing pad stood as loose blocks).
                    let me = Int32(head)
                    for d in dirs12 {
                        let n = c + d
                        let b = block(n)
                        if BlockMaterial.anchors(b) && d.y <= 0 { anchor = true }
                        guard built(b) else { continue }
                        var j: Int32
                        if let have = table.get(n) {
                            if compOf[Int(have)] != compId { anchor = true; continue }
                            j = have
                        } else {
                            j = Int32(cells.count)
                            _ = table.insert(n, j)
                            cells.append(n)
                            compOf.append(compId)
                            anchoredFlag.append(false)
                        }
                        links[me, default: []].append(j)
                        links[j, default: []].append(me)
                    }
                }
                anchoredFlag[head - start] = anchor
                head += 1
                if cells.count - start > cap { open = false; break }
            }
            let n = cells.count - start
            res.visited += n
            if !open {
                // A structure bigger than one search (a citadel): the search's edge is taken as held (whatever lies
                // beyond it stands), so only failures near the damage are found, never the whole building's.
                for i in 0..<n where !anchoredFlag[i] {
                    let c = cells[start + i]
                    for d in dirs6 {
                        let q = c + d
                        if table.get(q) == nil && built(block(q)) { anchoredFlag[i] = true; break }
                    }
                }
            }
            if !anchoredFlag.contains(true) {
                res.falling.append(Array(cells[start..<(start + n)]))
                continue
            }
            // Reach to support (Dijkstra): resting on the cell below is free; a step sideways or hanging down into a cell
            // costs Collapse.unit / that cell's strength, and a cell whose cost passes one unit is beyond reach. (For one
            // material that is the plain step count against its reach; a light panel or a window set into a steel
            // deck fails only where the steel itself would, not at the panel's own short reach from the wall.)
            var step = [Int32](repeating: 0, count: n)
            for i in 0..<n {
                let r = max(0.25, BlockMaterial.strength(block(cells[start + i])))
                step[i] = Int32((Float(Collapse.unit) / r).rounded())
            }
            var dist = [Int32](repeating: Int32.max, count: n)
            var heap = Heap()
            for i in 0..<n where anchoredFlag[i] { dist[i] = 0; heap.push(0, Int32(i)) }
            while let top = heap.pop() {
                let d = top.0, i = Int(top.1)
                if d > dist[i] { continue }
                let c = cells[start + i]
                for dd in dirs6 {
                    guard let g = table.get(c + dd), compOf[Int(g)] == compId else { continue }
                    let j = Int(g) - start
                    let nd = dd.y > 0 ? d : d + step[j]
                    if nd < dist[j] { dist[j] = nd; heap.push(nd, Int32(j)) }
                }
                if let ex = links[Int32(start + i)] {
                    for g in ex where compOf[Int(g)] == compId {
                        let j = Int(g) - start
                        let nd = d + step[j]
                        if nd < dist[j] { dist[j] = nd; heap.push(nd, Int32(j)) }
                    }
                }
            }
            var failed = Set<IVec3>()
            for i in 0..<n where dist[i] > Collapse.unit { failed.insert(cells[start + i]) }
            if !failed.isEmpty {
                // What only hung on the failed cells goes with them: whatever no longer connects to a held cell.
                var held = [Bool](repeating: false, count: n)
                var q: [Int] = []
                for i in 0..<n where anchoredFlag[i] && !failed.contains(cells[start + i]) { held[i] = true; q.append(i) }
                while let i = q.popLast() {
                    let c = cells[start + i]
                    for dd in dirs6 {
                        guard let g = table.get(c + dd), compOf[Int(g)] == compId else { continue }
                        let j = Int(g) - start
                        if !held[j] && !failed.contains(cells[start + j]) { held[j] = true; q.append(j) }
                    }
                    for g in links[Int32(start + i)] ?? [] where compOf[Int(g)] == compId {
                        let j = Int(g) - start
                        if !held[j] && !failed.contains(cells[start + j]) { held[j] = true; q.append(j) }
                    }
                }
                for i in 0..<n where !held[i] { failed.insert(cells[start + i]) }
                res.falling.append(contentsOf: pieces(Array(failed)))
                continue
            }
            // Necks: a layer the damage narrowed, against what stands above it (not in a structure bigger than the
            // search: what stands above the neck isn't all known). Only layers holding a hole under one of its cells.
            guard open && restore.isEmpty else { continue }
            var layers = Set<Int>()
            for h in holeSet {
                if let g = table.get(h + up), compOf[Int(g)] == compId { layers.insert(h.y) }
            }
            if layers.isEmpty { continue }
            let comp = Set(cells[start..<(start + n)])
            if let t = neck(w, comp: comp, holes: holeSet, layers: layers.sorted()) { res.tip.append(t) }
        }
        return res
    }

    // Stand-ins for emptied cells when asking what stood before the damage. Every hole held a block (blasts, mining and
    // smashing only empty solid cells): one beside built blocks holds what its strongest built neighbour is made of (a
    // wall's hole was most likely the wall's own material), one beside terrain only was terrain (stone), and a crater's
    // inner cells take the material of the filled cells round them, from the rim in (left empty, a blast through a
    // bridge would read as a cut already made, and the cut bridge would stand).
    static func standIns(_ w: World, _ holes: [IVec3]) -> [IVec3: BlockID] {
        var out: [IVec3: BlockID] = [:]
        var left = Array(holes.prefix(4000))
        let holeSet = Set(left)
        var pass = 0
        while !left.isEmpty && pass < 24 {
            var next: [IVec3] = []
            var fills: [(IVec3, BlockID)] = []
            for h in left {
                var best: BlockID = AIR, bestS: Float = -1, ground = false
                for d in dirs6 {
                    let n = h + d
                    let b = out[n] ?? (holeSet.contains(n) ? AIR : w.rawBlock(n.x, n.y, n.z))
                    if BlockMaterial.anchors(b) { ground = true; continue }
                    guard built(b) else { continue }
                    let st = BlockMaterial.strength(b)
                    if st > bestS { best = b; bestS = st }
                }
                if best == AIR && ground { best = STONE }
                if best != AIR { fills.append((h, best)) } else { next.append(h) }
            }
            if fills.isEmpty { break }
            for (h, b) in fills { out[h] = b }       // after the pass: a fill spreads one cell a pass, evenly
            left = next
            pass += 1
        }
        return out
    }

    // A binary min-heap of (cost, cell index) for the support search.
    struct Heap {
        var cost: [Int32] = []
        var item: [Int32] = []
        mutating func push(_ c: Int32, _ i: Int32) {
            cost.append(c); item.append(i)
            var k = cost.count - 1
            while k > 0 {
                let p = (k - 1) / 2
                if cost[p] <= cost[k] { break }
                cost.swapAt(p, k); item.swapAt(p, k)
                k = p
            }
        }
        mutating func pop() -> (Int32, Int32)? {
            guard let c0 = cost.first, let i0 = item.first else { return nil }
            let lc = cost.removeLast(), li = item.removeLast()
            if !cost.isEmpty {
                cost[0] = lc; item[0] = li
                var k = 0
                let n = cost.count
                while true {
                    let l = 2 * k + 1, r = l + 1
                    var m = k
                    if l < n && cost[l] < cost[m] { m = l }
                    if r < n && cost[r] < cost[m] { m = r }
                    if m == k { break }
                    cost.swapAt(m, k); item.swapAt(m, k)
                    k = m
                }
            }
            return (c0, i0)
        }
    }

    // Splits cells into 6-connected pieces.
    static func pieces(_ cells: [IVec3]) -> [[IVec3]] {
        var left = Set(cells)
        var out: [[IVec3]] = []
        while let s = left.first {
            left.remove(s)
            var p = [s]
            var i = 0
            while i < p.count {
                let c = p[i]; i += 1
                for d in dirs6 where left.contains(c + d) { left.remove(c + d); p.append(c + d) }
            }
            out.append(p)
        }
        return out
    }

    // A tower (or anything tall) standing on a narrowed layer at the holes: everything of comp above the layer, when it
    // outweighs what the layer bears or its centre of mass hangs past the layer's edge; the axis it tips about.
    static func neck(_ w: World, comp: Set<IVec3>, holes: Set<IVec3>, layers: [Int]) -> (cells: [IVec3], axis: V3)? {
        guard !holes.isEmpty else { return nil }
        var hc = V3(0, 0, 0)
        for h in holes { hc += V3(Float(h.x), Float(h.y), Float(h.z)) + 0.5 }
        hc /= Float(holes.count)
        for y in layers {
            // Cells of the layer that have built cells above them.
            let layer = comp.filter { $0.y == y }
            if layer.isEmpty { continue }
            var above: [IVec3] = []
            var inAbove = Set<IVec3>()
            for c in layer {
                let u = c + IVec3(0, 1, 0)
                if comp.contains(u) && !inAbove.contains(u) { inAbove.insert(u); above.append(u) }
            }
            if above.isEmpty { continue }
            var i = 0
            while i < above.count && above.count <= 20000 {
                let c = above[i]; i += 1
                for d in dirs6 {
                    let n = c + d
                    if n.y > y && comp.contains(n) && !inAbove.contains(n) { inAbove.insert(n); above.append(n) }
                }
            }
            if above.count > 20000 || above.count < 8 { continue }
            // Only the layer's cells that carry it.
            let carriers = layer.filter { inAbove.contains($0 + IVec3(0, 1, 0)) }
            // The damage must have narrowed this layer (a quarter of what carried it gone): one mined block, or a
            // blast beside an L-shaped house, never brings down a building that leaned or was loaded that way whole.
            var lost = 0
            for h in holes where h.y == y && inAbove.contains(h + IVec3(0, 1, 0)) { lost += 1 }
            let narrowed = lost * 4 >= carriers.count + lost
            var bear: Float = 0
            var lo = V2(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude), hi = -lo
            var cen = V2(0, 0)
            for c in carriers {
                bear += BlockMaterial.load(w.rawBlock(c.x, c.y, c.z))
                lo = simd_min(lo, V2(Float(c.x), Float(c.z))); hi = simd_max(hi, V2(Float(c.x) + 1, Float(c.z) + 1))
                cen += V2(Float(c.x), Float(c.z)) + 0.5
            }
            cen /= Float(max(1, carriers.count))
            var weight: Float = 0
            var com = V3(0, 0, 0)
            for c in above {
                let m = BlockMaterial.mass(w.rawBlock(c.x, c.y, c.z))
                weight += m / 2.3
                com += (V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5) * m
            }
            com /= max(0.001, weight * 2.3)
            let c2 = V2(com.x, com.z)
            // Past the edge, or far off the middle of what is left under it (a tower that lost one side of its base
            // leans on the other: it goes over toward the gap).
            let reach = simd_length(hi - lo) * 0.5
            let past = c2.x < lo.x - 0.3 || c2.x > hi.x + 0.3 || c2.y < lo.y - 0.3 || c2.y > hi.y + 0.3 || simd_length(c2 - cen) > reach * 0.3
            if !narrowed || (weight <= bear && !past) { continue }
            // Tips toward the side the layer lost (away from what's left of it, toward the blast).
            var lean = V2(com.x, com.z) - cen
            if simd_length(lean) < 0.3 { lean = V2(hc.x, hc.z) - cen }
            if simd_length(lean) < 0.01 { lean = V2(1, 0) }
            lean = simd_normalize(lean)
            // Rotating about this axis carries the top toward `lean`.
            let axis = V3(lean.y, 0, -lean.x)
            return (above, axis)
        }
        return nil
    }
}
