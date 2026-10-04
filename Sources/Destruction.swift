import Foundation
import simd

// Destruction physics (Future ideas #7): structures fail and fall as rigid bodies.
//
// After an explosion (or a falling piece breaking what it hits) the blocks round the damage are checked, never the
// whole world: a flood fill through built blocks (anything that isn't terrain: BlockMaterial.anchors) from the cells next
// to the hole, capped at Collapse.cap cells (a bigger structure is taken as standing). A piece that no longer touches
// the ground falls. In a piece that does, each block's reach to its support is measured (resting on a block below costs
// nothing, every step sideways or hanging down costs one) and a block further out than its material spans
// (BlockMaterial.strength) gives way, with whatever hangs from it. A neck the blast narrowed (a tower's base) fails when
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
            if !open { continue }                 // too big to be loose: taken as standing
            if anchored.isEmpty {
                res.falling.append(comp)
                continue
            }
            // Reach to support (0-1 breadth-first): resting on the cell below is free, sideways or hanging costs 1.
            var dist: [IVec3: Int] = [:]
            dist.reserveCapacity(comp.count)
            var dq: [IVec3] = []                  // cost-1 cells in order (a queue read from dh)
            var dh = 0
            var front: [IVec3] = anchored         // cost-0 cells, taken first
            for a in anchored { dist[a] = 0 }
            while !front.isEmpty || dh < dq.count {
                let c: IVec3
                if let f = front.popLast() { c = f } else { c = dq[dh]; dh += 1 }
                let dc = dist[c] ?? 0
                for d in dirs6 {
                    let n = c + d
                    guard inComp.contains(n) else { continue }
                    let cost = d.y > 0 ? 0 : 1
                    let nd = dc + cost
                    if let old = dist[n], old <= nd { continue }
                    dist[n] = nd
                    if cost == 0 { front.append(n) } else { dq.append(n) }
                }
            }
            var failed = Set<IVec3>()
            for c in comp {
                let reach = Int(BlockMaterial.strength(w.rawBlock(c.x, c.y, c.z)).rounded(.down))
                if (dist[c] ?? Int.max) > reach { failed.insert(c) }
            }
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
            // Necks: the narrowest built layer at the damage, against what stands above it.
            if let t = neck(w, comp: inComp, holes: holeSet) { res.tip.append(t) }
        }
        return res
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
            var bear: Float = 0
            var lo = V2(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude), hi = -lo
            for c in carriers {
                bear += BlockMaterial.load(w.rawBlock(c.x, c.y, c.z))
                lo = simd_min(lo, V2(Float(c.x), Float(c.z))); hi = simd_max(hi, V2(Float(c.x) + 1, Float(c.z) + 1))
            }
            var weight: Float = 0
            var com = V3(0, 0, 0)
            for c in above {
                let m = BlockMaterial.mass(w.rawBlock(c.x, c.y, c.z))
                weight += m / 2.3
                com += (V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5) * m
            }
            com /= max(0.001, weight * 2.3)
            let c2 = V2(com.x, com.z)
            let past = c2.x < lo.x - 0.3 || c2.x > hi.x + 0.3 || c2.y < lo.y - 0.3 || c2.y > hi.y + 0.3
            if weight <= bear && !past { continue }
            // Tips toward the side the layer lost (away from what's left of it, toward the blast).
            let mid = (lo + hi) * 0.5
            var lean = V2(com.x, com.z) - mid
            if simd_length(lean) < 0.3 { lean = V2(hc.x, hc.z) - mid }
            if simd_length(lean) < 0.01 { lean = V2(1, 0) }
            lean = simd_normalize(lean)
            // Rotating about this axis carries the top toward `lean`.
            let axis = V3(lean.y, 0, -lean.x)
            return (above, axis)
        }
        return nil
    }
}
