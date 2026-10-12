import Foundation
import simd

// P106 (Oct 12 12:12-12:34, top priority): polygon terrain round 2. Checks and surveys for the smooth mesher
// (SmoothTerrain.swift): `--smooth2-only`.
enum SmoothRound2Tests {
    // Which opaque cube blocks line caves without smoothing (SmoothTerrain.natural false): the "some cave areas did
    // not smooth" part. Generated chunks only (no structures), every face a solid shares with open air below the sea.
    static func caveSurvey(seeds: [UInt64] = [12345, 424242, 777], chunks r: Int = 3) -> (natural: Int, other: [String: Int]) {
        let nat = SmoothTerrain.natural, opaque = Blocks.opaque
        var other: [String: Int] = [:], natural = 0
        for seed in seeds {
            let gen = WorldGen(seed: seed)
            for cz in -r...r { for cx in -r...r {
                let b = gen.generate(cx: cx, cz: cz)
                for y in 8..<SEA { for z in 1..<(CS - 1) { for x in 1..<(CS - 1) {
                    let id = b[Chunk.index(x, y, z)]
                    guard opaque[Int(id)] && Blocks.render[Int(id)] == RenderType.cube.rawValue else { continue }
                    var open = false
                    for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] where b[Chunk.index(x + dx, y + dy, z + dz)] == AIR { open = true; break }
                    guard open else { continue }
                    if nat[Int(id)] { natural += 1 } else { other[Blocks.key(Blocks.groupBase[Int(id)]), default: 0] += 1 }
                } } }
            } }
        }
        return (natural, other)
    }

    // Vertex positions (1/16 block, section-local) of a section's opaque mesh.
    static func verts(_ m: SectionMesh) -> [SIMD3<Int32>] {
        stride(from: 0, to: m.opaque.count, by: 2).map { i in
            let w0 = m.opaque[i]
            return SIMD3<Int32>(Int32(w0 & 511), Int32((w0 >> 9) & 511), Int32((w0 >> 18) & 511))
        }
    }

    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let s = caveSurvey()
        let built: Set<String> = ["cobblestone", "mossy_cobblestone", "obsidian"]   // dungeons; obsidian stays cubic (portal frames)
        let wild = s.other.filter { !built.contains($0.key) }
        let total = s.natural + wild.values.reduce(0, +)
        let left = s.other.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        check(Float(wild.values.reduce(0, +)) < Float(total) * 0.002,
              "P106 caves: \(s.natural) of \(total) natural cave-wall blocks mesh smooth; still cubes: \(left.isEmpty ? "none" : left) (dungeon cobble and obsidian by design)")

        let w = g.world, was = SmoothTerrain.enabled, relax0 = SmoothTerrain.relax
        SmoothTerrain.enabled = true
        defer { SmoothTerrain.enabled = was; SmoothTerrain.relax = relax0 }
        // A stepped stone hill in the air across a chunk corner (a terrace every two blocks, the "you can tell it used to
        // be blocks" case, with a 3x3 top), high over the player.
        let p0 = g.player.pos
        let cx0 = (Int(floor(p0.x)) & ~15) + 16, cz0 = (Int(floor(p0.z)) & ~15) + 16
        _ = w.loadSync(center: V3(Float(cx0), p0.y, Float(cz0)), radius: 2)
        let by = min(CH - 40, ((w.topY(cx0, cz0) + 24) & ~15))
        let stone = Blocks.id("stone")
        var placed: [IVec3] = []
        for dz in -15...15 { for dx in -15...15 {
            let h = max(0, 9 - max(abs(dx), abs(dz)) / 2)
            for y in 0...h { w.setBlock(cx0 + dx, by + y, cz0 + dz, stone); placed.append(IVec3(cx0 + dx, by + y, cz0 + dz)) }
        } }
        defer { for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }; w.damage.removeAll() }
        func mesh(_ x: Int, _ z: Int, _ sy: Int) -> SectionMesh? {
            guard let c = w.chunkAt(x, z), let nb = w.neighbourhood(c) else { return nil }
            return Mesher.buildSection(nb.0, nb.1, sy: sy, damage: w.damageList(c))
        }
        let sy = by >> 4
        // 1. Terraces: how far the hill's top vertices stray from the even 1-in-2 slope through its steps (a stepped
        // surface zigzags round it), round 1 against relaxed. Ridges, the top and the foot are left out.
        func terraces(_ r: Int) -> (Float, Int) {
            SmoothTerrain.relax = r
            var rs: [Float] = []
            for (x, z) in [(cx0 - 1, cz0 - 1), (cx0, cz0 - 1), (cx0 - 1, cz0), (cx0, cz0)] {
                guard let m = mesh(x, z, sy) else { continue }
                let ox = Float(floorDiv(x, CS) * CS) - Float(cx0) - 0.5, oz = Float(floorDiv(z, CS) * CS) - Float(cz0) - 0.5
                for (i, v) in verts(m).enumerated() where (m.opaque[i * 2] >> 27) & 7 == 2 {
                    let ax = abs(ox + Float(v.x) / 16), az = abs(oz + Float(v.z) / 16)
                    let d = max(ax, az), y = Float(v.y) / 16
                    if d < 3 || d > 13 || abs(ax - az) < 1.5 || y < 1.5 { continue }
                    rs.append(y + d / 2)
                }
            }
            if rs.count < 2 { return (1, rs.count) }
            let mean = rs.reduce(0, +) / Float(rs.count)
            let v = rs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(rs.count)
            return (v.squareRoot(), rs.count)
        }
        let t0 = terraces(0), t2 = terraces(relax0 > 0 ? relax0 : 4)
        check(t2.1 > 100 && t2.0 < t0.0 * 0.6,
              "P106 relaxed surface: a stepped hill's top strays \(String(format: "%.3f", t0.0)) blocks (rms) from an even slope in round 1, \(String(format: "%.3f", t2.0)) relaxed (\(t2.1) vertices)")
        SmoothTerrain.relax = relax0 > 0 ? relax0 : 4
        // 2. No seams: a dual vertex two sections both compute (their shared ring) lands in the same place in both.
        var shared = 0, worst: Float = 0
        for (ax, az, dx, dz) in [(cx0 - 1, cz0 - 1, 16, 0), (cx0 - 1, cz0 - 1, 0, 16), (cx0 - 1, cz0 - 1, 16, 16)] {
            var cells: [[SIMD3<Int>: SIMD3<Float>]] = [[:], [:]]
            for (k, (x, z)) in [(ax, az), (ax + dx, az + dz)].enumerated() {
                let o = SIMD3<Int>(floorDiv(x, CS) * CS, sy * 16, floorDiv(z, CS) * CS)
                SmoothTerrain.vertexHook = { a, b, c, p in cells[k][SIMD3<Int>(a, b, c) &+ o] = p + SIMD3<Float>(Float(o.x), Float(o.y), Float(o.z)) }
                _ = mesh(x, z, sy)
                SmoothTerrain.vertexHook = nil
            }
            for (cell, p) in cells[0] { if let q = cells[1][cell] { shared += 1; worst = max(worst, simd_length(p - q)) } }
        }
        check(shared > 20 && worst < 1e-4, "P106 seams: \(shared) dual vertices two sections both compute, worst mismatch \(worst) blocks")
        // 3. Digging: a chipped block stays smooth (no cube sub-faces) and its top corner sinks as the chips come off.
        let top = IVec3(cx0, by + 9, cz0)
        let corner = SIMD3<Int>(mod(top.x, CS), mod(top.y, 16), mod(top.z, CS))     // the dual cell over its +x+z top corner
        func topY() -> (Float, Int) {
            var y: Float = 0
            SmoothTerrain.vertexHook = { a, b, c, p in if SIMD3<Int>(a, b, c) == corner { y = p.y } }
            let m = mesh(top.x, top.z, top.y >> 4)
            SmoothTerrain.vertexHook = nil
            guard let m else { return (0, 0) }
            let lx = Int32(mod(top.x, CS) * 16), lz = Int32(mod(top.z, CS) * 16)
            let cube = verts(m).filter { $0.x % 4 == 0 && $0.y % 4 == 0 && $0.z % 4 == 0 && abs($0.x - lx - 8) <= 8 && abs($0.z - lz - 8) <= 8 }.count
            return (y, cube)
        }
        let whole = topY()
        w.chip(top, level: 5, face: 2)
        let dug = topY()
        check(whole.0 > 0 && dug.0 < whole.0 - 0.15 && dug.1 <= whole.1,
              "P106 digging: the hill top's corner sits at \(String(format: "%.2f", whole.0)) whole and \(String(format: "%.2f", dug.0)) chipped five eighths (blocks over the section), "
              + "grid-corner vertices \(whole.1) -> \(dug.1) (no cube of chips)")
        // 4. Cost: meshing the hill's four sections, round 1 against relaxed (background threads; one section each).
        func cost(_ r: Int) -> (Double, Int) {
            SmoothTerrain.relax = r
            var quads = 0
            let t = CFAbsoluteTimeGetCurrent()
            for _ in 0..<3 { for (x, z) in [(cx0 - 1, cz0 - 1), (cx0, cz0 - 1), (cx0 - 1, cz0), (cx0, cz0)] { quads += (mesh(x, z, sy)?.opaque.count ?? 0) / 8 } }
            return ((CFAbsoluteTimeGetCurrent() - t) * 1000 / 12, quads / 3)
        }
        let c0 = cost(0), c2 = cost(relax0 > 0 ? relax0 : 4)
        check(c2.1 == c0.1 && c2.0 < c0.0 * 2 + 0.5,
              "P106 cost: \(String(format: "%.2f", c0.0)) ms a section round 1, \(String(format: "%.2f", c2.0)) ms relaxed (debug build); quads \(c0.1) -> \(c2.1)")
    }
}
