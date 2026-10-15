import Foundation

// R22 (Oct 13 evening playtest: "a sweep for floating generation: pillars, rails, ... Capital trim over a void"):
// support columns under structures run down to real ground.
//
// The cause, every time: StructWriter.pillarDown stops at its `minY`, and the generators gave it a guess of how deep
// the ground could be (5, 8, 10, 20, 24, 30, 48 blocks under the floor). Wherever the ground was deeper (a ravine or a
// cave mouth under a Capital walkway, a steep jungle slope under a temple, a trestle over a gorge) the column ended
// in mid-air: the trim columns over a void at seed 424242 (-768, 40, 1054) stop exactly 30 under the walkway, the
// Capital city's cap. A column also stopped on the first opaque block, which could be a tree's branch or a huge
// mushroom's cap hanging over open ground.
//
// groundDown keeps each caller's reach as the usual depth and carries on past it, up to `reach` blocks under the start,
// until it meets ground (an opaque solid that is not part of a tree or a huge mushroom). It reads and writes one
// column of this chunk only, so every chunk decides the same whichever generates first. Saved chunks are never
// regenerated, so only columns in new ground grow longer; nothing already explored is cut.
extension StructWriter {
    static let groundReach = 96

    // Opaque solids a support column runs on through: tree parts and huge mushrooms (held up by a trunk or stem
    // somewhere else, or not at all).
    static let notGround: [Bool] = (0..<Blocks.count).map { i in
        let k = Blocks.key(Blocks.groupBase[i])
        return k.hasSuffix("_log") || k.hasSuffix("_wood") || k.hasSuffix("_stem") || k.hasSuffix("_hyphae")
            || k.hasSuffix("mushroom_block") || k.hasSuffix("_leaves") || k == "bamboo"
    }

    @inline(__always) static func holdsColumn(_ b: BlockID) -> Bool {
        let i = Int(b)
        return Blocks.opaque[i] && Blocks.collide[i] && !notGround[i]
    }

    // A support column of `b` from y down to the ground (inside this chunk only): through air, water, lava, plants,
    // leaves and tree parts; `minY` is the usual depth, never the limit.
    // P289 ("very perfect pillars" in a lush cave under a station): `reach` caps how far past it a column may run. A
    // wide footprint (a yard, a plaza) passes its usual depth: over a cave its columns stop as a plug, a cave roof,
    // instead of each one dropping a lone straight column to the cave floor wherever air ran straight down.
    func groundDown(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID, minY: Int, reach: Int = StructWriter.groundReach) {
        guard inside(x, y, z) else { return }
        let bottom = max(1, min(minY, y - reach))
        var yy = y
        while yy >= bottom {
            let i = Chunk.index(x - bx, yy, z - bz)
            let cur = blocks[i]
            if cur != b && StructWriter.holdsColumn(cur) { break }
            blocks[i] = b
            yy -= 1
        }
    }

    // True when the block under (x, y, z) holds what stands on it without falling (not sand or gravel over a hollow):
    // the rail lines lay their ballast only there.
    func firmUnder(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        let below = get(x, y - 1, z)
        return Blocks.collide[Int(below)] && Blocks.fluidKind[Int(below)] == 0
    }
}

// R22 checks on a bare chunk buffer (no world needed): `GroundSupport.check { ok, what in ... }`.
enum GroundSupport {
    static func check(_ check: (Bool, String) -> Void) {
        var b = [BlockID](repeating: AIR, count: CSQ * CH)
        let log = Blocks.has("oak_log") ? Blocks.id("oak_log") : LOG
        // Ground 70 blocks under a walkway (a ravine): the old 30-block reach stopped in mid-air.
        for z in 0..<CS { for x in 0..<CS { b[Chunk.index(x, 100, z)] = STONE } }
        b[Chunk.index(3, 150, 3)] = log                                          // a branch hanging in the way
        b.withUnsafeMutableBufferPointer { p in
            let w = StructWriter(bx: 0, bz: 0, blocks: p.baseAddress!)
            w.groundDown(3, 169, 3, COBBLE, minY: 169 - 30)
            w.groundDown(5, 169, 5, COBBLE, minY: 169 - 30)
        }
        let reached = (101...169).allSatisfy { b[Chunk.index(3, $0, 3)] == COBBLE && b[Chunk.index(5, $0, 5)] == COBBLE }
        check(reached && b[Chunk.index(3, 100, 3)] == STONE, "R22 support columns: run past their usual reach and through a branch down to the ground (reached \(reached))")
        // Grass on ground a structure cleared, a tall flower over air, grass on dirt.
        var c = [BlockID](repeating: AIR, count: CSQ * CH)
        c[Chunk.index(4, 200, 4)] = TALL_GRASS                                      // over air
        c[Chunk.index(6, 199, 6)] = DIRT; c[Chunk.index(6, 200, 6)] = TALL_GRASS     // on its soil
        c[Chunk.index(8, 199, 8)] = WATER; c[Chunk.index(8, 200, 8)] = TALL_GRASS    // on water
        let lilac = Blocks.has("lilac") ? Blocks.id("lilac") : TALL_GRASS
        let upper = Blocks.has("lilac[upper]") ? Blocks.id("lilac[upper]") : lilac
        c[Chunk.index(10, 200, 10)] = lilac; c[Chunk.index(10, 201, 10)] = upper     // both halves over air
        _ = PlantSupport.dropFloating(&c)
        let gone = c[Chunk.index(4, 200, 4)] == AIR && c[Chunk.index(8, 200, 8)] == AIR
            && c[Chunk.index(10, 200, 10)] == AIR && c[Chunk.index(10, 201, 10)] == AIR
        check(gone && c[Chunk.index(6, 200, 6)] == TALL_GRASS, "R22 floating grass: plants over air or water go at generation, a tall flower with its base; grass on dirt stays")
    }
}
