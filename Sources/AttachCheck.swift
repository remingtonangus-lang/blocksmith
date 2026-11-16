import Foundation

// Ledger 201 (Nov 15 20:41, the Builders' Grounds' Stone Gate: "lanterns aren't attached to the goddamn block... That's the
// kind of thing the agent's supposed to spot when it's building"): the gate's two lanterns hung under the arch's middle,
// a top-half slab, so their chains stopped half a block short of it. The game's support rule (PlantSupport) takes any
// solid neighbour, so nothing ever said so. This is the look of it: a lantern, a torch or a sign touches what holds it.
// Each of its boxes that reaches a side of its cell must meet, on that side, a box of the neighbour that reaches the
// same plane and overlaps it; one such contact is enough.
enum Attach {
    // The fittings that hang on, stand on or lean against a neighbour.
    static let fitting: [Bool] = (0..<Blocks.count).map { i in
        let s = Blocks.shape[i], k = Blocks.key(Blocks.groupBase[i])
        return s == "lantern" || s == "torch" || k.hasSuffix("torch") || k.hasSuffix("_sign") || k.hasSuffix("_wall_sign")
    }

    // A block's shape in 1/16: a cube's whole cell, a model's boxes, nothing for air, liquids and plants.
    static func boxes(_ b: BlockID) -> [Box] {
        let i = Int(b)
        if b == AIR || Blocks.isLiquid(b) || Blocks.isPlant(b) { return [] }
        if Blocks.render[i] == RenderType.cube.rawValue { return [Box(0, 0, 0, 16, 16, 16)] }
        let bx = Blocks.boxes[i]
        if bx.isEmpty { return Blocks.collide[i] ? [Box(0, 0, 0, 16, 16, 16)] : [] }
        return bx
    }

    @inline(__always) static func overlap(_ a0: UInt8, _ a1: UInt8, _ b0: UInt8, _ b1: UInt8) -> Bool { max(a0, b0) < min(a1, b1) }

    // Whether the fitting at `p` touches what holds it (`at` reads a cell). A fitting reaching no side of its cell
    // floats by its own shape and fails.
    static func flush(_ at: (IVec3) -> BlockID, _ p: IVec3) -> Bool {
        for b in boxes(at(p)) {
            if b.y0 == 0 && boxes(at(p + IVec3(0, -1, 0))).contains(where: { $0.y1 == 16 && overlap(b.x0, b.x1, $0.x0, $0.x1) && overlap(b.z0, b.z1, $0.z0, $0.z1) }) { return true }
            if b.y1 == 16 && boxes(at(p + IVec3(0, 1, 0))).contains(where: { $0.y0 == 0 && overlap(b.x0, b.x1, $0.x0, $0.x1) && overlap(b.z0, b.z1, $0.z0, $0.z1) }) { return true }
            if b.x0 == 0 && boxes(at(p + IVec3(-1, 0, 0))).contains(where: { $0.x1 == 16 && overlap(b.y0, b.y1, $0.y0, $0.y1) && overlap(b.z0, b.z1, $0.z0, $0.z1) }) { return true }
            if b.x1 == 16 && boxes(at(p + IVec3(1, 0, 0))).contains(where: { $0.x0 == 0 && overlap(b.y0, b.y1, $0.y0, $0.y1) && overlap(b.z0, b.z1, $0.z0, $0.z1) }) { return true }
            if b.z0 == 0 && boxes(at(p + IVec3(0, 0, -1))).contains(where: { $0.z1 == 16 && overlap(b.y0, b.y1, $0.y0, $0.y1) && overlap(b.x0, b.x1, $0.x0, $0.x1) }) { return true }
            if b.z1 == 16 && boxes(at(p + IVec3(0, 0, 1))).contains(where: { $0.z0 == 0 && overlap(b.y0, b.y1, $0.y0, $0.y1) && overlap(b.x0, b.x1, $0.x0, $0.x1) }) { return true }
        }
        return false
    }

    // Every fitting in a set of cells that does not touch its support: "key at x y z" lines.
    static func loose(_ cells: [IVec3], _ at: (IVec3) -> BlockID) -> [String] {
        cells.filter { fitting[Int(at($0))] && !flush(at, $0) }.map { "\(Blocks.key(at($0))) at \($0.x) \($0.y) \($0.z)" }
    }
}
