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
enum Collapse {
    static let cap = 6000               // cells one support search may visit
    static let maxDebris = 32           // free-moving debris bodies at once
    static let minPiece = 3             // smaller falling pieces break into items / dust
    static let unit: Int32 = 840        // a block's whole reach in the support search's cost units (840 = 1..8 x 14 divide it)

    static let dirs6 = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]

    // Built (structural) cell: collides, isn't terrain, isn't a fluid.
    @inline(__always) static func built(_ b: BlockID) -> Bool {
        b != AIR && Blocks.collide[Int(b)] && !BlockMaterial.anchors(b) && !Blocks.isLiquid(b)
    }

    struct Result {
        var falling: [[IVec3]] = []       // connected pieces that fall
        var tip: [(cells: [IVec3], axis: V3)] = []   // pieces that tip over a neck (spin axis)
        var visited = 0
    }

    // What fails around `holes` (cells just emptied). Reads the world only.
    // `seeds`: built cells to check besides those next to the holes (a whole scene, for the harness's oracle).
    static func analyze(_ w: World, around holes: [IVec3], seeds extra: [IVec3] = [], cap: Int = Collapse.cap) -> Result {
        var res = Result()
        var seen = Set<IVec3>()
        var seeds: [IVec3] = extra
        for h in holes {
            for d in dirs6 {
                let c = h + d
                if !seen.contains(c) && built(w.rawBlock(c.x, c.y, c.z)) { seeds.append(c) }
            }
            if seeds.count > 256 { break }
        }
        let holeSet = Set(holes)
        for s in seeds where !seen.contains(s) {
            // The structure: built cells connected to s.
            var comp: [IVec3] = [s]
            var inComp = Set<IVec3>([s])
            var anchored: [IVec3] = []           // cells resting on or against terrain
            var head = 0
            var open = true
            while head < comp.count {
                let c = comp[head]; head += 1
                var anchor = false
                for d in dirs6 {
                    let n = c + d
                    let b = w.rawBlock(n.x, n.y, n.z)
                    if BlockMaterial.anchors(b) && d.y <= 0 { anchor = true }
                    if built(b) && !inComp.contains(n) {
                        inComp.insert(n)
                        comp.append(n)
                    }
                }
                if anchor { anchored.append(c) }
                if comp.count > cap { open = false; break }
            }
            seen.formUnion(inComp)
            res.visited += comp.count
            if !open {
                // A structure bigger than one search (a citadel): the search's edge is taken as held (whatever lies
                // beyond it stands), so only failures near the damage are found, never the whole building's.
                for c in comp where dirs6.contains(where: { d in
                    let n = c + d
                    return !inComp.contains(n) && built(w.rawBlock(n.x, n.y, n.z))
                }) { anchored.append(c) }
            }
            if anchored.isEmpty {
                res.falling.append(comp)
                continue
            }
            // Reach to support (Dijkstra): resting on the cell below is free; a step sideways or hanging down into a cell
            // costs Collapse.unit / that cell's strength, and a cell whose cost passes one unit is beyond reach. (For one
            // material that is the plain step count against its reach; a light panel or a window set into a steel
            // deck fails only where the steel itself would, not at the panel's own short reach from the wall.)
            let n = comp.count
            var index: [IVec3: Int32] = [:]
            index.reserveCapacity(n)
            for (i, c) in comp.enumerated() { index[c] = Int32(i) }
            var step = [Int32](repeating: 0, count: n)
            for i in 0..<n {
                let c = comp[i]
                let r = max(0.25, BlockMaterial.strength(w.rawBlock(c.x, c.y, c.z)))
                step[i] = Int32((Float(Collapse.unit) / r).rounded())
            }
            var dist = [Int32](repeating: Int32.max, count: n)
            var heap = Heap()
            for a in anchored {
                guard let i = index[a] else { continue }
                if dist[Int(i)] != 0 { dist[Int(i)] = 0; heap.push(0, i) }
            }
            while let top = heap.pop() {
                let d = top.0, i = Int(top.1)
                if d > dist[i] { continue }
                let c = comp[i]
                for dd in dirs6 {
                    guard let j32 = index[c + dd] else { continue }
                    let j = Int(j32)
                    let nd = dd.y > 0 ? d : d + step[j]
                    if nd < dist[j] { dist[j] = nd; heap.push(nd, j32) }
                }
            }
            var failed = Set<IVec3>()
            for i in 0..<n where dist[i] > Collapse.unit { failed.insert(comp[i]) }
            if !failed.isEmpty {
                // What only hung on the failed cells goes with them: re-measure the rest without them.
                let rest = comp.filter { !failed.contains($0) }
                let restSet = Set(rest)
                var held = Set<IVec3>(anchored.filter { restSet.contains($0) })
                var q = Array(held)
                while let c = q.popLast() {
                    for d in dirs6 {
                        let n = c + d
                        if restSet.contains(n) && !held.contains(n) { held.insert(n); q.append(n) }
                    }
                }
                for c in rest where !held.contains(c) { failed.insert(c) }
                res.falling.append(contentsOf: pieces(Array(failed)))
                continue
            }
            // Necks: the narrowest built layer at the damage, against what stands above it (not in a structure bigger
            // than the search: what stands above the neck isn't all known).
            if open, let t = neck(w, comp: inComp, holes: holeSet) { res.tip.append(t) }
        }
        return res
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
    static func neck(_ w: World, comp: Set<IVec3>, holes: Set<IVec3>) -> (cells: [IVec3], axis: V3)? {
        guard let y0 = holes.map({ $0.y }).min(), let y1 = holes.map({ $0.y }).max() else { return nil }
        var hc = V3(0, 0, 0)
        for h in holes { hc += V3(Float(h.x), Float(h.y), Float(h.z)) + 0.5 }
        hc /= Float(holes.count)
        for y in max(0, y0 - 1)...(y1 + 1) {
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
