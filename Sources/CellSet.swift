import Foundation

// Store review (Nov 2, callgrind of the citadel soak): the building checks (Structure.analyse, Structure.loose) filled
// tens of thousands of cells into Set<IVec3>, hashed with SipHash, and looked up each cell's chunk in the world's
// dictionary several times over: 20M instructions a check, a check a frame after every shell, 12 ms on the host.

// A set of cells for one fill at a time: open addressing on a packed key, emptied by a generation stamp (no clearing,
// no allocation once grown). Frame thread only (each user keeps its own).
final class CellSet {
    private var keys: [Int64]
    private var gens: [UInt32]
    private var gen: UInt32 = 1
    private var mask: Int
    private(set) var count = 0
    init(capacity: Int = 4096) {
        var n = 16
        while n < capacity * 2 { n <<= 1 }
        keys = [Int64](repeating: 0, count: n); gens = [UInt32](repeating: 0, count: n); mask = n - 1
    }
    func removeAll() {
        gen &+= 1; count = 0
        if gen == 0 { for i in gens.indices { gens[i] = 0 }; gen = 1 }
    }
    @inline(__always) private static func key(_ c: IVec3) -> Int64 {
        (Int64(c.x) & 0x3FF_FFFF) | ((Int64(c.z) & 0x3FF_FFFF) << 26) | ((Int64(c.y) & 0xFFF) << 52)
    }
    @inline(__always) private func slot(_ k: Int64) -> Int {
        Int(truncatingIfNeeded: (UInt64(bitPattern: k) &* 0x9E37_79B9_7F4A_7C15) >> 40) & mask
    }
    @inline(__always) func contains(_ c: IVec3) -> Bool {
        let k = CellSet.key(c)
        var i = slot(k)
        while gens[i] == gen {
            if keys[i] == k { return true }
            i = (i + 1) & mask
        }
        return false
    }
    // Adds the cell; false if it was in already.
    @discardableResult @inline(__always) func insert(_ c: IVec3) -> Bool {
        if (count + 1) * 2 > mask + 1 { grow() }
        let k = CellSet.key(c)
        var i = slot(k)
        while gens[i] == gen {
            if keys[i] == k { return false }
            i = (i + 1) & mask
        }
        gens[i] = gen; keys[i] = k; count += 1
        return true
    }
    private func grow() {
        let oldK = keys, oldG = gens, g = gen
        let n = (mask + 1) * 2
        keys = [Int64](repeating: 0, count: n); gens = [UInt32](repeating: 0, count: n); mask = n - 1; gen = 1; count = 0
        for i in oldK.indices where oldG[i] == g {
            var j = slot(oldK[i])
            while gens[j] == gen { j = (j + 1) & mask }
            gens[j] = gen; keys[j] = oldK[i]; count += 1
        }
    }
}

// The world's chunks read through the last one met: a fill steps to a neighbour cell, nearly always in the same chunk.
struct ChunkCursor {
    let w: World
    private var cx = Int.min, cz = Int.min
    private var c: Chunk?
    init(_ w: World) { self.w = w }
    @inline(__always) mutating func chunk(_ x: Int, _ z: Int) -> Chunk? {
        let kx = x >> 4, kz = z >> 4                 // (floorDiv by CS = 16)
        if kx != cx || kz != cz { cx = kx; cz = kz; c = w.chunks[ChunkKey(x: kx, z: kz)] }
        return c
    }
    @inline(__always) mutating func loaded(_ x: Int, _ z: Int) -> Bool { w.frame != nil || chunk(x, z) != nil }
    // As World.builtBlock.
    @inline(__always) mutating func built(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        if w.frame != nil || !w.fieldTerrain { return w.block(x, y, z) }
        if y < 0 || y >= CH { return y < 0 ? BEDROCK : AIR }
        guard let ch = chunk(x, z), !ch.hollow else { return AIR }
        return ch.blocks.raw(Chunk.index(x & 15, y, z & 15))
    }
    // As World.groundAt.
    @inline(__always) mutating func ground(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard w.fieldTerrain, w.frame == nil, y >= 0 && y < CH, let ch = chunk(x, z) else { return false }
        if ch.hollow { return y <= Int(ch.height[(x & 15) + (z & 15) * CS]) }
        return ch.blocks.ground(Chunk.index(x & 15, y, z & 15))
    }
}
