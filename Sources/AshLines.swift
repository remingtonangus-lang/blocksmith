import Foundation
import simd

// The Ashguard's fortified lines (backlog B7, docs/status/the-last-war.md). Two belts round the citadel at x 0, z 0:
//   the Ember Line   a ring 404-432 blocks out (between the depots and the outposts): two rows of tank-trap teeth
//                    outside, a belt of barbed wire, a sandbagged trench, and concrete MG bunkers every 15 degrees
//   the Last Line    a square belt 54-66 blocks out (Chebyshev distance) round the citadel's wall: the same layers,
//                    eight MG bunkers, and on every road a gate with a dug-in tank behind an earth berm
// Both lines open at the four roads into checkpoints. The ground (teeth, wire, trench) is carved per column as a chunk
// generates (DeepGen.generate); bunkers and checkpoints are structure starts built by AshWar.build. A vault an old world
// already explored keeps its ground.
enum AshLines {
    static let emberR: Float = 418, emberHalf: Float = 14
    static let lastR = 60, lastHalf = 6

    enum Cut { case none, tooth, wire, post, trench, parapet }

    // Distance (blocks) to the nearest line band, 0 inside one: the vault floor flattens there and keeps pillars and
    // lava rivers away (AshWar.clearance).
    @inline(__always) static func distance(_ x: Int, _ z: Int) -> Float {
        let d = sqrtf(Float(x * x + z * z))
        let a = abs(d - emberR) - emberHalf
        let c = max(abs(x), abs(z))
        let b = Float(abs(c - lastR) - lastHalf)
        return max(0, min(a, b))
    }

    // What the ground holds at this column. `u` is the distance outward from the line's centre, `t` the position
    // along it.
    static func cut(_ x: Int, _ z: Int) -> Cut {
        if AshWar.roadDistance(x, z) < 6 { return .none }                  // the roads stay open (checkpoints there)
        let c = max(abs(x), abs(z))
        if abs(c - lastR) <= lastHalf {
            let u = c - lastR
            let t = abs(x) >= abs(z) ? z : x
            return layer(u: Float(u), t: t, teeth: (3, 6), wire: (1, 3))
        }
        let d = sqrtf(Float(x * x + z * z))
        let u = d - emberR
        guard abs(u) <= emberHalf else { return .none }
        let t = Int(floor(atan2f(Float(x), Float(-z)) * emberR))
        return layer(u: u, t: t, teeth: (9, 13), wire: (5, 7))
    }

    private static func layer(u: Float, t: Int, teeth: (Float, Float), wire: (Float, Float)) -> Cut {
        if u >= teeth.0 && u < teeth.1 {
            // Two staggered rows of teeth two blocks apart, one tooth every third block (infantry weaves through).
            let row = Int(floor(u - teeth.0))
            guard row % 2 == 0 else { return .none }
            return ((t + row) % 3 + 3) % 3 == 0 ? .tooth : .none
        }
        if u >= wire.0 && u < wire.1 { return (t % 5 + 5) % 5 == 0 && u < wire.0 + 1 ? .post : .wire }
        if u >= -2 && u < 0 { return .trench }
        if u >= 0 && u < 1 { return .parapet }
        return .none
    }

    // Carves one column of a freshly generated vault chunk (DeepGen.generate). `f` is the floor's top (internal y).
    static func carve(_ b: inout [BlockID], _ lx: Int, _ lz: Int, _ wx: Int, _ wz: Int, f: Int) {
        let k = cut(wx, wz)
        guard k != .none, f > 6, f + 3 < CH else { return }
        switch k {
        case .tooth:
            b[Chunk.index(lx, f + 1, lz)] = AshLines.concrete
            b[Chunk.index(lx, f + 2, lz)] = AshLines.concrete
        case .wire:
            b[Chunk.index(lx, f + 1, lz)] = AshLines.wire
        case .post:
            b[Chunk.index(lx, f + 1, lz)] = AshLines.post
            b[Chunk.index(lx, f + 2, lz)] = AshLines.post
        case .trench:
            b[Chunk.index(lx, f, lz)] = AIR
            b[Chunk.index(lx, f - 1, lz)] = AIR
            b[Chunk.index(lx, f - 2, lz)] = AshLines.duckboard
        case .parapet:
            b[Chunk.index(lx, f + 1, lz)] = AshLines.bags
        case .none: break
        }
    }

    static let concrete = Blocks.id("ash_concrete"), wire = Blocks.id("ash_wire"), bags = Blocks.id("ash_sandbags")
    static let post = Blocks.has("iron_bars") ? Blocks.id("iron_bars") : Blocks.id("ash_plating")
    static let duckboard = Blocks.id("polished_blackstone")

    // MARK: Bunkers and checkpoints

    // Twenty MG bunkers on the Ember Line (every 15 degrees but the four roads), eight on the Last Line, straddling the
    // trench and facing out; a checkpoint where each road crosses each line.
    static let bunkers: [AshSite] = {
        var s: [AshSite] = []
        for k in 0..<24 where k % 6 != 0 {
            let a = Float(k) * 15 * .pi / 180
            s.append(AshSite(kind: "bunker", x: Int((sinf(a) * (emberR - 1)).rounded()), z: Int((-cosf(a) * (emberR - 1)).rounded()), r: 5, face: k * 15))
        }
        let c = lastR - 2
        for (x, z, f) in [(30, -c, 0), (-30, -c, 0), (c, 30, 90), (c, -30, 90), (30, c, 180), (-30, c, 180), (-c, 30, 270), (-c, -30, 270)] {
            s.append(AshSite(kind: "bunker", x: x, z: z, r: 5, face: f))
        }
        return s
    }()

    static let gates: [AshSite] = {
        var s: [AshSite] = []
        let e = Int(emberR)
        for (x, z, f) in [(0, -e, 0), (e, 0, 90), (0, e, 180), (-e, 0, 270)] { s.append(AshSite(kind: "checkpoint", x: x, z: z, r: 9, face: f)) }
        for (x, z, f) in [(0, -lastR, 0), (lastR, 0, 90), (0, lastR, 180), (-lastR, 0, 270)] { s.append(AshSite(kind: "lastgate", x: x, z: z, r: 7, face: f)) }
        return s
    }()

    static var sites: [AshSite] { bunkers + gates }
}
