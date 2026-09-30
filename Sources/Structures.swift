import Foundation

// Structures: placed per region on a grid (like the reference game's spacing/separation), built from
// deterministic pieces. When a chunk generates, every piece overlapping it writes its blocks clipped
// to that chunk, so structures spanning many chunks come out seamless.

// Deterministic RNG for structure layout / loot.
struct SRng {
    var s: UInt64
    init(_ seed: UInt64) { s = seed ^ 0x9E3779B97F4A7C15; if s == 0 { s = 1 } }
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    mutating func range(_ a: Int, _ b: Int) -> Int { a + int(b - a + 1) }
    mutating func float() -> Float { Float(next() % 1_000_000) / 1_000_000 }
    mutating func chance(_ p: Float) -> Bool { float() < p }
}

// Writes blocks for one chunk; everything outside the chunk is ignored.
struct StructWriter {
    let bx: Int, bz: Int
    var blocks: UnsafeMutablePointer<BlockID>
    var entities: [(IVec3, BlockEntity)] = []

    @inline(__always) func inside(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        x >= bx && x < bx + CS && z >= bz && z < bz + CS && y >= 0 && y < CH
    }
    func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        inside(x, y, z) ? blocks[Chunk.index(x - bx, y, z - bz)] : AIR
    }
    func set(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
        if inside(x, y, z) { blocks[Chunk.index(x - bx, y, z - bz)] = b }
    }
    func fill(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ b: BlockID) {
        let xa = max(x0, bx), xb = min(x1, bx + CS - 1)
        let za = max(z0, bz), zb = min(z1, bz + CS - 1)
        let ya = max(0, y0), yb = min(CH - 1, y1)
        guard xa <= xb, za <= zb, ya <= yb else { return }
        for y in ya...yb { for z in za...zb { for x in xa...xb { blocks[Chunk.index(x - bx, y, z - bz)] = b } } }
    }
    // Pillar from y down until a solid block (inside this chunk only).
    func pillarDown(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID, minY: Int) {
        guard inside(x, y, z) else { return }
        var yy = y
        while yy >= minY {
            let cur = blocks[Chunk.index(x - bx, yy, z - bz)]
            if Blocks.opaque[Int(cur)] && cur != b { break }
            blocks[Chunk.index(x - bx, yy, z - bz)] = b
            yy -= 1
        }
    }
    mutating func chest(_ x: Int, _ y: Int, _ z: Int, loot: String, seed: UInt64, facing: Int = 0) {
        guard inside(x, y, z) else { return }
        set(x, y, z, Blocks.id("chest") + BlockID(facing))
        let be = BlockEntity(.chest)
        var rng = SRng(seed)
        Loot.fill(be.container, table: loot, rng: &rng)
        entities.append((IVec3(x, y, z), be))
    }
    mutating func spawner(_ x: Int, _ y: Int, _ z: Int, mob: String) {
        guard inside(x, y, z) else { return }
        set(x, y, z, Blocks.id("spawner"))
        let be = BlockEntity(.spawner)
        be.mob = mob
        entities.append((IVec3(x, y, z), be))
    }
}

struct Piece {
    let min: IVec3
    let max: IVec3
    let build: (inout StructWriter) -> Void
    func overlaps(_ bx: Int, _ bz: Int) -> Bool { max.x >= bx && min.x < bx + CS && max.z >= bz && min.z < bz + CS }
}

final class StructureStart {
    let kind: String
    let pieces: [Piece]
    let min: IVec3
    let max: IVec3
    let anchor: IVec3                     // a representative walkable spot (start piece floor)
    init(kind: String, pieces: [Piece], anchor: IVec3) {
        self.kind = kind
        self.anchor = anchor
        self.pieces = pieces
        var a = IVec3(Int.max, Int.max, Int.max), b = IVec3(Int.min, Int.min, Int.min)
        for p in pieces {
            a = IVec3(Swift.min(a.x, p.min.x), Swift.min(a.y, p.min.y), Swift.min(a.z, p.min.z))
            b = IVec3(Swift.max(b.x, p.max.x), Swift.max(b.y, p.max.y), Swift.max(b.z, p.max.z))
        }
        min = a; max = b
    }
    func contains(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        x >= min.x && x <= max.x && y >= min.y && y <= max.y && z >= min.z && z <= max.z
    }
}

// A structure type: grid spacing/separation (chunks) and how to lay out a start in a region.
struct StructureType {
    let name: String
    let spacing: Int
    let separation: Int
    let salt: UInt64
    let reach: Int                        // max extent from the start chunk, in chunks
    let make: (_ seed: UInt64, _ chunkX: Int, _ chunkZ: Int) -> StructureStart?
}

final class StructureCache {
    private var cache: [String: StructureStart?] = [:]
    private let lock = NSLock()
    let seed: UInt64
    let types: [StructureType]
    init(seed: UInt64, types: [StructureType]) { self.seed = seed; self.types = types }

    // The structure start in the region containing chunk (rx, rz) for a type, if any.
    func start(_ t: StructureType, regionX rx: Int, regionZ rz: Int) -> StructureStart? {
        let key = "\(t.name):\(rx):\(rz)"
        lock.lock()
        if let c = cache[key] { lock.unlock(); return c }
        lock.unlock()
        var rng = SRng(seed &+ UInt64(bitPattern: Int64(rx)) &* 341873128712 &+ UInt64(bitPattern: Int64(rz)) &* 132897987541 &+ t.salt)
        let span = t.spacing - t.separation
        let cx = rx * t.spacing + rng.int(span), cz = rz * t.spacing + rng.int(span)
        let s = t.make(seed &+ t.salt &+ UInt64(bitPattern: Int64(cx &* 31 &+ cz)), cx, cz)
        lock.lock()
        cache[key] = s
        if cache.count > 4096 { cache.removeAll() }
        lock.unlock()
        return s
    }

    func startsNear(cx: Int, cz: Int, _ t: StructureType) -> [StructureStart] {
        var out: [StructureStart] = []
        let r = t.reach
        let rx0 = floorDiv(cx - r, t.spacing), rx1 = floorDiv(cx + r, t.spacing)
        let rz0 = floorDiv(cz - r, t.spacing), rz1 = floorDiv(cz + r, t.spacing)
        for rz in rz0...rz1 { for rx in rx0...rx1 { if let s = start(t, regionX: rx, regionZ: rz) { out.append(s) } } }
        return out
    }

    // Builds every structure piece overlapping this chunk into `blocks`; returns block entities.
    func place(into blocks: inout [BlockID], cx: Int, cz: Int) -> [(IVec3, BlockEntity)] {
        var ents: [(IVec3, BlockEntity)] = []
        blocks.withUnsafeMutableBufferPointer { buf in
            var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
            for t in types {
                for s in startsNear(cx: cx, cz: cz, t) {
                    for p in s.pieces where p.overlaps(cx * CS, cz * CS) { p.build(&w) }
                }
            }
            ents = w.entities
        }
        return ents
    }

    // Nearest structure start of a kind (searching regions outward), for locating / the snapshot harness.
    func nearest(_ kind: String, x: Int, z: Int, maxRegions: Int = 6) -> StructureStart? {
        guard let t = types.first(where: { $0.name == kind }) else { return nil }
        let rx = floorDiv(floorDiv(x, CS), t.spacing), rz = floorDiv(floorDiv(z, CS), t.spacing)
        var best: StructureStart?, bd = Int.max
        for r in 0...maxRegions {
            for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                guard let s = start(t, regionX: rx + dx, regionZ: rz + dz) else { continue }
                let cx = (s.min.x + s.max.x) / 2 - x, cz = (s.min.z + s.max.z) / 2 - z
                if cx * cx + cz * cz < bd { bd = cx * cx + cz * cz; best = s }
            } }
            if best != nil && r >= 1 { break }
        }
        return best
    }

    // Structure (of a kind) containing a world position — used for structure mob spawns.
    func structure(at x: Int, _ y: Int, _ z: Int, kind: String) -> StructureStart? {
        let cx = floorDiv(x, CS), cz = floorDiv(z, CS)
        for t in types where t.name == kind {
            for s in startsNear(cx: cx, cz: cz, t) where s.contains(x, y, z) { return s }
        }
        return nil
    }
}

// MARK: Loot tables (item, min, max, weight) with a number of rolls.

enum Loot {
    static let tables: [String: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)])] = [
        "fortress": (2...4, [("diamond", 1, 3, 5), ("iron_ingot", 1, 5, 5), ("gold_ingot", 1, 3, 15), ("golden_sword", 1, 1, 5),
                             ("golden_chestplate", 1, 1, 5), ("flint_and_steel", 1, 1, 5), ("nether_wart", 3, 7, 5),
                             ("saddle", 1, 1, 10), ("obsidian", 2, 4, 2)]),
        "dungeon": (1...3, [("saddle", 1, 1, 20), ("golden_apple", 1, 1, 15), ("iron_ingot", 1, 4, 10), ("gold_ingot", 1, 4, 5),
                            ("bread", 1, 1, 20), ("wheat", 1, 4, 20), ("gunpowder", 1, 4, 10), ("string", 1, 4, 10),
                            ("bucket", 1, 1, 10), ("redstone", 1, 4, 15), ("coal", 1, 4, 15), ("bone", 1, 8, 10),
                            ("rotten_flesh", 1, 8, 10), ("name_tag", 1, 1, 20), ("music_disc_13", 1, 1, 15)]),
        "stronghold_corridor": (2...3, [("ender_pearl", 1, 1, 10), ("diamond", 1, 3, 3), ("iron_ingot", 1, 5, 10), ("gold_ingot", 1, 3, 5),
                                        ("redstone", 4, 9, 5), ("bread", 1, 3, 15), ("apple", 1, 3, 15), ("iron_pickaxe", 1, 1, 5),
                                        ("iron_sword", 1, 1, 5), ("iron_chestplate", 1, 1, 5), ("iron_helmet", 1, 1, 5),
                                        ("iron_leggings", 1, 1, 5), ("iron_boots", 1, 1, 5), ("golden_apple", 1, 1, 1)]),
        "village": (3...8, [("diamond", 1, 3, 3), ("iron_ingot", 1, 5, 10), ("gold_ingot", 1, 3, 5), ("bread", 1, 3, 15),
                            ("apple", 1, 3, 15), ("iron_pickaxe", 1, 1, 5), ("iron_sword", 1, 1, 5), ("obsidian", 3, 7, 5),
                            ("oak_sapling", 3, 7, 5), ("iron_helmet", 1, 1, 5)]),
        "desert_pyramid": (2...4, [("diamond", 1, 3, 5), ("iron_ingot", 1, 5, 15), ("gold_ingot", 2, 7, 15), ("emerald", 1, 3, 15),
                                   ("bone", 4, 6, 25), ("spider_eye", 1, 3, 25), ("rotten_flesh", 3, 7, 25), ("saddle", 1, 1, 20),
                                   ("golden_apple", 1, 1, 20), ("gunpowder", 1, 8, 10)]),
        "mineshaft": (3...5, [("iron_ingot", 1, 5, 10), ("gold_ingot", 1, 3, 5), ("redstone", 4, 9, 5), ("lapis_lazuli", 4, 9, 5),
                              ("diamond", 1, 2, 3), ("coal", 3, 8, 10), ("bread", 1, 3, 15), ("melon_seeds", 2, 4, 10),
                              ("pumpkin_seeds", 2, 4, 10), ("beetroot_seeds", 2, 4, 10), ("rail", 4, 8, 1), ("torch", 1, 16, 15)]),
        "bastion": (3...5, [("gold_ingot", 3, 9, 10), ("gold_block", 1, 2, 5), ("netherite_scrap", 1, 1, 3), ("diamond", 1, 3, 3),
                            ("crying_obsidian", 3, 8, 10), ("spectral_arrow", 10, 22, 6), ("golden_carrot", 6, 17, 10),
                            ("iron_ingot", 2, 6, 10), ("obsidian", 4, 6, 10), ("magma_cream", 2, 6, 4)]),
    ]

    static func fill(_ c: ItemContainer, table: String, rng: inout SRng) {
        guard let t = tables[table] else { return }
        let entries = t.entries.filter { Items.has($0.0) }
        let total = entries.reduce(0) { $0 + $1.3 }
        guard total > 0 else { return }
        let rolls = rng.range(t.rolls.lowerBound, t.rolls.upperBound)
        for _ in 0..<rolls {
            var r = rng.int(total)
            for e in entries {
                r -= e.3
                if r < 0 {
                    var slot = rng.int(c.count)
                    for _ in 0..<c.count where !c[slot].isEmpty { slot = (slot + 1) % c.count }
                    c[slot] = ItemStack(Items.id(e.0), rng.range(e.1, e.2))
                    break
                }
            }
        }
    }
}
