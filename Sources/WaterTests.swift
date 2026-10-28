import Foundation
import simd

// --water-only (questcheck): P44 surface water. A world made since has about half the lakes and fewer river
// reaches than the same seed's old terrain; a world saved before keeps its old water.
enum WaterTests {
    static func run(check: (Bool, String) -> Void) {
        var lakes = [0, 0], rivers = [0, 0]
        for seed: UInt64 in [12345, 777, 31415] {
            for (k, fewer) in [false, true].enumerated() {
                let t = Terrain(seed: seed)
                t.fewerLakes = fewer
                for j in -20..<20 { for i in -20..<20 {
                    if t.lake(i, j).valid { lakes[k] += 1 }
                    if !t.rbase(i, j).ocean && t.rdown(i, j) >= 0 && t.racc(i, j) >= t.riverAccMin { rivers[k] += 1 }
                } }
            }
        }
        check(lakes[1] * 10 <= lakes[0] * 7 && lakes[1] > 0, "P44: lakes in new worlds \(lakes[1]) against \(lakes[0]) before (three seeds, 40 x 40 nodes)")
        check(rivers[1] * 10 <= rivers[0] * 9 && rivers[1] > 0, "P44: river reaches in new worlds \(rivers[1]) against \(rivers[0]) before")
        // The marker: a new save takes the new water, one with chunks already on disk keeps the old.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p44water-\(Int.random(in: 0...999999))")
        let fresh = SaveManager(dir: dir.appendingPathComponent("fresh"))
        let made = fresh.newTerrain("terrain-p44-water.txt"), again = fresh.newTerrain("terrain-p44-water.txt")
        let old = SaveManager(dir: dir.appendingPathComponent("old"))
        try? FileManager.default.createDirectory(at: old.chunkDir, withIntermediateDirectories: true)
        try? Data([1]).write(to: old.chunkDir.appendingPathComponent("c.0.0.lz"))
        check(made && again && !old.newTerrain("terrain-p44-water.txt"), "P44: new worlds get the new water, saved worlds keep theirs")
        try? FileManager.default.removeItem(at: dir)
    }
}
