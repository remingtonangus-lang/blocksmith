import Foundation
import simd
import Metal

// P474 (generation speed at dropship speed): where one field chunk's making goes, pass by pass, on one thread (the
// workers' own code path: TerrainGenerator.generateField and World.produce's tail), over a square of chunks.
//   questcheck --genprof --seed S --at X,Z [--n 8]          (n x n chunks round the spot; each made twice, the second timed)
enum QuestGenProf {
    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        TextureGen.registerAll()
        let at = (arg("--at") ?? "0,0").split(separator: ",").compactMap { Double($0) }
        let n = Int(arg("--n") ?? "") ?? 8
        let w = World(seed: UInt64(arg("--seed") ?? "") ?? 12345, device: sharedSystemDevice, save: nil)
        w.makeFieldWorld()
        guard let wg = w.gen as? WorldGen else { print("genprof: not a WorldGen world"); return 1 }
        let c0x = floorDiv(Int(at[0]), CS) - n / 2, c0z = floorDiv(Int(at.count > 1 ? at[1] : 0), CS) - n / 2
        var keys: [ChunkKey] = []
        for dz in 0..<n { for dx in 0..<n { keys.append(ChunkKey(x: c0x + dx, z: c0z + dz)) } }
        // Warm: structure starts, caches, lazy tables (streaming spreads those over a region's chunks).
        for k in keys { _ = wg.generateField(cx: k.x, cz: k.z) }
        let names = ["generate", "structures", "orphans", "dropFloating", "clearFallenTops", "settleGrass", "split",
                     "merge", "heights", "tints", "tracked", "emitMask", "springs"]
        var ms = [Double](repeating: 0, count: names.count)
        WorldGen.timing = true
        for k in 0..<WorldGen.phaseMs.count { WorldGen.phaseMs[k] = 0 }
        var t = CFAbsoluteTimeGetCurrent()
        func lap(_ i: Int) { let now = CFAbsoluteTimeGetCurrent(); ms[i] += (now - t) * 1000; t = now }
        var hash: UInt64 = 0xcbf29ce484222325
        // (Per pass, the built layer after it: a run-to-run difference shows which pass made it.)
        var passHash = [UInt64](repeating: 0xcbf29ce484222325, count: names.count)
        func fnv(_ h: inout UInt64, _ b: [BlockID]) { for v in b { h = (h ^ UInt64(v)) &* 0x100000001b3 } }
        let tAll = CFAbsoluteTimeGetCurrent()
        for k in keys {
            t = CFAbsoluteTimeGetCurrent()
            var cd = [Float](repeating: .nan, count: CSQ * CH)
            var ad = [Float](repeating: .nan, count: CSQ * CH)
            var b = cd.withUnsafeMutableBufferPointer { c in ad.withUnsafeMutableBufferPointer { a in
                wg.generate(cx: k.x, cz: k.z, carved: c.baseAddress, added: a.baseAddress) } }
            lap(0)
            fnv(&passHash[0], b)
            for v in cd { passHash[0] = (passHash[0] ^ UInt64(v.bitPattern)) &* 0x100000001b3 }
            for v in ad { passHash[0] = (passHash[0] ^ UInt64(v.bitPattern)) &* 0x100000001b3 }
            t = CFAbsoluteTimeGetCurrent()
            var mark = [UInt8](repeating: 0, count: b.count)
            var ents: [(IVec3, BlockEntity)] = []
            if let st = wg.structures {
                let placed: ([(IVec3, BlockEntity)], [(String, V3)]) = mark.withUnsafeMutableBufferPointer { m in
                    st.place(into: &b, cx: k.x, cz: k.z, mark: m.baseAddress) }
                ents = placed.0
            }
            lap(1)
            fnv(&passHash[1], b); for v in mark { passHash[1] = (passHash[1] ^ UInt64(v)) &* 0x100000001b3 }
            t = CFAbsoluteTimeGetCurrent()
            ents += World.orphanEntities(b, k, have: ents); lap(2)
            _ = PlantSupport.dropFloating(&b); lap(3)
            FieldTerrain.clearFallenTops(&b); lap(4)
            WorldGen.settleGrass(&b); lap(5)
            fnv(&passHash[5], b)
            t = CFAbsoluteTimeGetCurrent()
            let ground = FieldTerrain.split(&b, cx: k.x, cz: k.z, gen: wg, built: mark, carved: cd, added: ad); lap(6)
            var merged = b
            FieldTerrain.merge(&merged, ground); lap(7)
            let heights = Chunk.computeHeights(merged); lap(8)
            _ = wg.tints(cx: k.x, cz: k.z); lap(9)
            _ = Circuit.trackedCells(b, cx: k.x, cz: k.z); lap(10)
            _ = BlockStore.emitMask(of: merged); lap(11)
            _ = World.springs(merged, k, heights); lap(12)
            // FNV-1a over every cell made (built layer, ground density and material): any change to what is made shows.
            for v in b { hash = (hash ^ UInt64(v)) &* 0x100000001b3 }
            for v in ground.fd { hash = (hash ^ UInt64(UInt8(bitPattern: v))) &* 0x100000001b3 }
            for v in ground.fm { hash = (hash ^ UInt64(v)) &* 0x100000001b3 }
            for v in ground.borderSeeds { hash = (hash ^ UInt64(truncatingIfNeeded: v)) &* 0x100000001b3 }
            fnv(&passHash[6], b)
            for v in ground.fd { passHash[7] = (passHash[7] ^ UInt64(UInt8(bitPattern: v))) &* 0x100000001b3 }
            for v in ground.fm { passHash[8] = (passHash[8] ^ UInt64(v)) &* 0x100000001b3 }
            for v in ground.borderSeeds { passHash[9] = (passHash[9] ^ UInt64(truncatingIfNeeded: v)) &* 0x100000001b3 }
        }
        let total = (CFAbsoluteTimeGetCurrent() - tAll) * 1000
        WorldGen.timing = false
        let c = Double(keys.count)
        print(String(format: "genprof: %d chunks, %.2f ms a chunk on one thread; cells hash %016llx", keys.count, total / c, hash))
        print(String(format: "genprof: hash after generate %016llx, structures %016llx, settle %016llx; split: blocks %016llx, density %016llx, material %016llx, seeds %016llx",
                     passHash[0], passHash[1], passHash[5], passHash[6], passHash[7], passHash[8], passHash[9]))
        for (i, nm) in names.enumerated() { print(String(format: "genprof:   %-16@ %6.2f ms", nm, ms[i] / c)) }
        for (i, nm) in WorldGen.phaseNames.enumerated() { print(String(format: "genprof:   generate.%-10@ %6.2f ms", nm, WorldGen.phaseMs[i] / c)) }
        // The middle ring's build at view 16, without and with the gap cover's inner quads (FarRing.Mesh.inner).
        for want in [false, true] {
            var memo: [Int64: FarRing.Sample] = [:]
            var inner: [ChunkKey: [SimpleVert]] = [:]
            let t0 = CFAbsoluteTimeGetCurrent()
            let v = FarRing.build(wg, cx: c0x * CS, cz: c0z * CS, rin: FarRing.loadedRadius(16), memo: &memo, inner: &inner, wantInner: want)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print(String(format: "genprof: far ring at view 16%@: %d quads, %d chunks covered, %d samples, %.0f ms",
                         want ? " with the gap cover" : "", v.count / 4, inner.count, memo.count, ms))
        }
        return 0
    }
}
