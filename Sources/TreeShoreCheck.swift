import Foundation
import simd

// Ledger 274 (lane 1's find, Nov 18: a tree floating over the water at the headset spawn of seed 12345, near 4696
// 1746, a Polygons world): along shorelines no tree stands with nothing under its trunk's foot. Every trunk foot (a
// tree's log with no log of its own under it) is measured against the drawn ground under it: it must stand on the
// ground, not over water or over air.
//   questcheck --treeshore (BS_TREESHORE_TRACE=1 prints each floating foot)
enum TreeShoreCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let trace = Env.all["BS_TREESHORE_TRACE"] == "1"
        var shores = 0, feet = 0, floating: [String] = []
        // Shorelines: from the spawn lane 1 saw, then out along the coast of the same world and his world, every 300
        // blocks, keeping a spot where water and land meet within the loaded square.
        let worlds: [(UInt64, Int, Int)] = [(12345, 4696, 1746), (4259144782798118884, -2398, -3300)]
        for (seed, ox, oz) in worlds where shores < 20 {
            let w = World(seed: seed, device: g0.world.device, save: nil)
            w.makeFieldWorld()
            w.renderDistance = 2; w.activeDistance = 2
            var k = 0
            while shores < (seed == 12345 ? 12 : 20) && k < 120 {
                let a = Float(k) * 2.39996, r = Float(k == 0 ? 0 : 150 + 40 * k)
                let cx = ox + Int(cosf(a) * r), cz = oz + Int(sinf(a) * r)
                k += 1
                _ = w.loadSync(center: V3(Float(cx) + 0.5, 200, Float(cz) + 0.5), radius: 1)
                var water = 0, land = 0
                for z in stride(from: cz - 16, to: cz + 16, by: 2) { for x in stride(from: cx - 16, to: cx + 16, by: 2) {
                    var t = CH - 2
                    while t > 1 && w.block(x, t, z) == AIR { t -= 1 }
                    if Blocks.isLiquid(w.block(x, t, z)) { water += 1 } else { land += 1 }
                } }
                guard water >= 12 && land >= 12 else { w.unloadAll(); continue }
                shores += 1
                for z in (cz - 16)..<(cz + 16) { for x in (cx - 16)..<(cx + 16) {
                    guard w.chunkAt(x, z) != nil else { continue }
                    for y in (SEA - 8)...(SEA + 40) {
                        let b = w.block(x, y, z)
                        guard CapitalBase.isLog(b), TreeWood.isTree[Int(b)], !CapitalBase.isLog(w.block(x, y - 1, z)) else { continue }
                        // A trunk's foot, not a bough's underside: logs on up three high, and no log of the tree beside
                        // it a row down (a limb's piece hangs off its neighbour).
                        guard CapitalBase.isLog(w.block(x, y + 1, z)), CapitalBase.isLog(w.block(x, y + 2, z)) else { continue }
                        var limb = false
                        for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 { if CapitalBase.isLog(w.block(x + dx, y - 1, z + dz)) { limb = true } } }
                        if limb { continue }
                        feet += 1
                        // The drawn ground under the foot's middle.
                        let o = V3(Float(x) + 0.5, Float(y) + 0.25, Float(z) + 0.5)
                        let s = w.fieldDensity(at: o) > 0 ? Float(y) + 0.25 : w.fieldRaySegment(o, V3(0, -1, 0), from: 0, to: 4)?.at.y
                        let under = w.block(x, y - 1, z)
                        let gap = s.map { Float(y) - $0 } ?? 4
                        // (The mesher draws a living trunk's root flare down to the lowest drawn ground round its foot,
                        // up to 2.5 under it, ShapeTrunks: a foot on soil whose smooth ground dips a little shows rooted.)
                        if Blocks.isLiquid(under) || gap > 2.4 || (!Blocks.collide[Int(under)] && gap > 0.5) {
                            let line = String(format: "%@ foot at %d %d %d (seed %llu): ground %.2f under it, %@ below", Blocks.key(b), x, y - YOFF, z, seed, gap, Blocks.key(under))
                            floating.append(line)
                            if trace { print("treeshore: " + line) }
                        }
                    }
                } }
                w.unloadAll()
            }
        }
        check(shores >= 20 && feet >= 40 && floating.isEmpty,
              "treeshore: \(shores) shorelines, \(feet) trunk feet, \(floating.count) over water or air" + (floating.isEmpty ? "" : ": " + floating.prefix(4).joined(separator: "; ")))
    }
}
