import Foundation
import Metal
import simd

// Structure overlap checks (Q2, scorecard "World gen: overlaps"; `questcheck --overlaps-only`, OVERLAP_SEEDS=N): every
// structure start of every kind in a 2048 x 2048 square round the spawn, on 12 seeds, piece against piece (as
// WorldAudit counts them on the Mac). No small kind may cut into a big kind it gives way to (StructureCache.yields);
// the pairs left over are printed for the next pass. On ground saved before the change (structure-guard-overlap.txt)
// a start that would now give way still stands, so a saved world keeps the structure it already half-generated.
enum OverlapTests {
    static func hit(_ a: IVec3, _ b: IVec3, _ c: IVec3, _ d: IVec3) -> Bool {
        a.x <= d.x && c.x <= b.x && a.y <= d.y && c.y <= b.y && a.z <= d.z && c.z <= b.z
    }

    static func run(check: (Bool, String) -> Void) {
        let n = Int(ProcessInfo.processInfo.environment["OVERLAP_SEEDS"] ?? "") ?? 12
        var pairs: [String: Int] = [:], yielding: [String] = [], total = 0, starts = 0
        var gaveWay: (UInt64, StructureType, Int, Int)?
        for i in 0..<n {
            let seed = UInt64(1000 + i * 7919)                 // WorldAudit's seeds
            let gen = WorldGen(seed: seed)
            guard let sc = gen.structures else { check(false, "overlaps: no structures"); return }
            let o = Game.spawnOrigin(seed: seed)
            let ox = o.0 * 16 + 8, oz = o.1 * 16 + 8
            var all: [StructureStart] = []
            for t in sc.types {
                let r = 64 / max(1, t.spacing) + 1
                let rx = floorDiv(o.0, t.spacing), rz = floorDiv(o.1, t.spacing)
                for dz in -r...r { for dx in -r...r {
                    guard let s = sc.start(t, regionX: rx + dx, regionZ: rz + dz) else {
                        // A start that gave way: remember one to replay on "saved" ground.
                        if gaveWay == nil, StructureCache.yields[t.name] != nil {
                            let (cx, cz) = sc.candidate(t, rx + dx, rz + dz)
                            if t.make(sc.seed &+ t.salt &+ UInt64(bitPattern: Int64(cx &* 31 &+ cz)), cx, cz) != nil { gaveWay = (seed, t, rx + dx, rz + dz) }
                        }
                        continue
                    }
                    guard abs(s.anchor.x - ox) <= 1024, abs(s.anchor.z - oz) <= 1024 else { continue }
                    all.append(s)
                } }
            }
            starts += all.count
            for a in 0..<all.count { for b in (a + 1)..<all.count {
                let s = all[a], t = all[b]
                guard hit(s.min, s.max, t.min, t.max),
                      s.pieces.contains(where: { p in t.pieces.contains { q in hit(p.min, p.max, q.min, q.max) } }) else { continue }
                total += 1
                pairs[[s.kind, t.kind].sorted().joined(separator: " + "), default: 0] += 1
                if StructureCache.yields[s.kind]?.contains(t.kind) == true || StructureCache.yields[t.kind]?.contains(s.kind) == true {
                    if yielding.count < 4 { yielding.append("\(s.kind) \(s.anchor.x),\(s.anchor.z) in \(t.kind) \(t.anchor.x),\(t.anchor.z) (seed \(seed))") }
                }
            } }
        }
        let left = pairs.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        check(yielding.isEmpty && total == 0, "overlaps: \(starts) starts on \(n) seeds, \(total) piece overlaps left (\(left.isEmpty ? "none" : left)); a small kind inside a big one it gives way to: \(yielding.isEmpty ? "none" : yielding.joined(separator: "; "))")

        // Saved ground keeps the start that now gives way.
        if let (seed, t, rx, rz) = gaveWay {
            let gen = WorldGen(seed: seed)
            guard let sc = gen.structures, let tt = sc.types.first(where: { $0.name == t.name }) else { return }
            let (cx, cz) = sc.candidate(tt, rx, rz)
            sc.legacyOverlap = [StructureCache.key(cx, cz)]
            check(sc.start(tt, regionX: rx, regionZ: rz) != nil, "overlaps: on ground saved before the change, a \(t.name) that now gives way still stands (seed \(seed), chunk \(cx),\(cz))")
        } else {
            check(true, "overlaps: no start gave way on these seeds (nothing to replay on saved ground)")
        }
    }
}
