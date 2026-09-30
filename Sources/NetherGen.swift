import Foundation

// The Nether: a 128-tall cavern (displayed y 0...127 = internal 64...191) with a lava sea at y 31,
// bedrock floor and roof, five biomes, glowstone clusters, quartz/gold ore, ancient debris and fungus trees.
final class NetherGen: TerrainGenerator {
    let seed: UInt64
    let s32: UInt32
    let d1: Noise, d2: Noise, bT: Noise, bH: Noise, deco: Noise
    static let base = YOFF          // internal y of displayed y 0
    static let lavaLevel = 31
    let structures: StructureCache?

    init(seed: UInt64) {
        self.seed = seed
        s32 = UInt32(truncatingIfNeeded: seed ^ (seed >> 32)) ^ 0x4E7E4
        d1 = Noise(seed: seed &+ 101)
        d2 = Noise(seed: seed &+ 102)
        bT = Noise(seed: seed &+ 103)
        bH = Noise(seed: seed &+ 104)
        deco = Noise(seed: seed &+ 105)
        structures = StructureCache(seed: seed, types: [Fortress.type, Bastion.type])
    }

    func biome(_ x: Int, _ z: Int) -> Biome {
        let t = bT.fbm2(Float(x) / 220, Float(z) / 220, 2)
        let h = bH.fbm2(Float(x) / 220, Float(z) / 220, 2)
        // Nearest of five biome "points" in (t, h) space, like the multi-noise biome source.
        let pts: [(Float, Float, Biome)] = [(0, 0, .netherWastes), (0, -0.35, .soulSandValley), (0.3, 0, .crimsonForest),
                                            (0, 0.35, .warpedForest), (-0.35, 0.1, .basaltDeltas)]
        var best = Biome.netherWastes, bd = Float.greatestFiniteMagnitude
        for (pt, ph, b) in pts {
            let d = (t - pt) * (t - pt) + (h - ph) * (h - ph)
            if d < bd { bd = d; best = b }
        }
        return best
    }

    func column(_ x: Int, _ z: Int) -> (height: Int, biome: Biome) { (NetherGen.base + 32, biome(x, z)) }

    func tints(cx: Int, cz: Int) -> [UInt32] {
        [UInt32](repeating: 0xFF3A7ABF, count: 768)
    }

    // Density at displayed y (0...127): > 0 is solid.
    private func density(_ x: Float, _ y: Float, _ z: Float) -> Float {
        var d = d1.noise3(x / 72, y / 36, z / 72) * 0.9 + d2.noise3(x / 24, y / 16, z / 24) * 0.35
        // Solid near the floor and roof, open in the middle.
        let fromMid = (y - 64) / 64
        d += fromMid * fromMid * 1.1 - 0.12
        if y < 12 { d += (12 - y) * 0.08 }
        if y > 112 { d += (y - 112) * 0.08 }
        return d
    }

    func generate(cx: Int, cz: Int) -> [BlockID] {
        var b = [BlockID](repeating: AIR, count: CSQ * CH)
        let bx = cx * CS, bz = cz * CS
        let base = NetherGen.base
        // Density on a 4 x 8 x 4 lattice, trilinearly interpolated (fast and smooth).
        let lx = 5, ly = 17, lz = 5
        var lat = [Float](repeating: 0, count: lx * ly * lz)
        for k in 0..<lz { for j in 0..<ly { for i in 0..<lx {
            lat[i + j * lx + k * lx * ly] = density(Float(bx + i * 4), Float(j * 8), Float(bz + k * 4))
        } } }
        let netherrack = NETHERRACK, lava = LAVA, bedrock = BEDROCK
        for z in 0..<CS {
            for x in 0..<CS {
                let i0 = x / 4, k0 = z / 4
                let fx = Float(x % 4) / 4, fz = Float(z % 4) / 4
                for y in 0..<128 {
                    let j0 = min(15, y / 8)
                    let fy = Float(y - j0 * 8) / 8
                    func L(_ i: Int, _ j: Int, _ k: Int) -> Float { lat[i + j * lx + k * lx * ly] }
                    let c00 = L(i0, j0, k0) + (L(i0 + 1, j0, k0) - L(i0, j0, k0)) * fx
                    let c10 = L(i0, j0 + 1, k0) + (L(i0 + 1, j0 + 1, k0) - L(i0, j0 + 1, k0)) * fx
                    let c01 = L(i0, j0, k0 + 1) + (L(i0 + 1, j0, k0 + 1) - L(i0, j0, k0 + 1)) * fx
                    let c11 = L(i0, j0 + 1, k0 + 1) + (L(i0 + 1, j0 + 1, k0 + 1) - L(i0, j0 + 1, k0 + 1)) * fx
                    let c0 = c00 + (c10 - c00) * fy, c1 = c01 + (c11 - c01) * fy
                    let d = c0 + (c1 - c0) * fz
                    let wx = bx + x, wz = bz + z
                    var id: BlockID = AIR
                    if y < 5 && (y == 0 || hash3(wx, y, wz, s32) % 5 < UInt32(5 - y)) { id = bedrock }
                    else if y > 122 && (y == 127 || hash3(wx, y, wz, s32 ^ 1) % 5 < UInt32(y - 122)) { id = bedrock }
                    else if d > 0 { id = netherrack }
                    else if y <= NetherGen.lavaLevel { id = lava }
                    b[Chunk.index(x, base + y, z)] = id
                }
            }
        }
        decorate(&b, cx, cz)
        return b
    }

    private func decorate(_ b: inout [BlockID], _ cx: Int, _ cz: Int) {
        let bx = cx * CS, bz = cz * CS
        let base = NetherGen.base
        let netherrack = NETHERRACK
        let soulSand = Blocks.id("soul_sand"), soulSoil = Blocks.id("soul_soil"), basalt = Blocks.id("basalt")
        let blackstone = Blocks.id("blackstone"), magma = Blocks.id("magma_block"), gravel = GRAVEL
        let crimsonNy = Blocks.id("crimson_nylium"), warpedNy = Blocks.id("warped_nylium")
        let quartz = Blocks.id("nether_quartz_ore"), gold = Blocks.id("nether_gold_ore"), debris = Blocks.id("ancient_debris")
        let glow = LAMP
        func at(_ x: Int, _ y: Int, _ z: Int) -> BlockID { y < 0 || y >= 128 ? BEDROCK : b[Chunk.index(x, base + y, z)] }
        func set(_ x: Int, _ y: Int, _ z: Int, _ v: BlockID) { if y >= 0 && y < 128 { b[Chunk.index(x, base + y, z)] = v } }

        for z in 0..<CS {
            for x in 0..<CS {
                let wx = bx + x, wz = bz + z
                let bio = biome(wx, wz)
                for y in 1..<127 {
                    let cur = at(x, y, z)
                    guard cur == netherrack else { continue }
                    let above = at(x, y + 1, z)
                    let h = hash3(wx, y, wz, s32 ^ 0x77)
                    // Surface layers per biome.
                    if above == AIR {
                        switch bio {
                        case .soulSandValley: set(x, y, z, h % 3 == 0 ? soulSoil : soulSand)
                        case .crimsonForest: set(x, y, z, crimsonNy)
                        case .warpedForest: set(x, y, z, warpedNy)
                        case .basaltDeltas: set(x, y, z, h % 4 == 0 ? magma : (h % 4 == 1 ? blackstone : basalt))
                        default:
                            if y >= NetherGen.lavaLevel - 1 && y <= NetherGen.lavaLevel + 3 && deco.noise2(Float(wx) / 12, Float(wz) / 12) > 0.25 {
                                set(x, y, z, h % 2 == 0 ? gravel : soulSand)
                            }
                        }
                        continue
                    }
                    if bio == .basaltDeltas && h % 7 == 0 { set(x, y, z, basalt); continue }
                    if bio == .soulSandValley && h % 9 == 0 { set(x, y, z, soulSoil); continue }
                    // Ores inside netherrack.
                    let cell = hash3(wx >> 1, y >> 1, wz >> 1, s32 ^ 0xA5) % 1000
                    if cell < 16 && h % 100 < 55 { set(x, y, z, quartz) }
                    else if cell < 26 && h % 100 < 55 { set(x, y, z, gold) }
                    else if y >= 8 && y <= 22 && hash3(wx, y, wz, s32 ^ 0xDEB) % 2600 == 0 { set(x, y, z, debris) }
                    else if y >= 27 && y <= 36 && cell > 990 { set(x, y, z, magma) }
                }
            }
        }
        // Glowstone clusters hanging from ceilings: grown by attaching to the ceiling or existing glowstone.
        for k in 0..<2 {
            let h = hash3(cx, k, cz, s32 ^ 0x6C0)
            if h % 3 == 0 { continue }
            let x0 = 3 + Int(h % 10), z0 = 3 + Int((h >> 4) % 10)
            var y0 = 120
            while y0 > 40 && !(at(x0, y0, z0) == AIR && at(x0, y0 + 1, z0) == netherrack) { y0 -= 1 }
            if y0 <= 40 { continue }
            set(x0, y0, z0, glow)
            for i in 0..<120 {
                let hh = hash3(x0 * 31 + i, y0, z0 * 17 - i, s32 ^ 0x6C1)
                let x = x0 + Int(hh % 7) - 3, z = z0 + Int((hh >> 4) % 7) - 3, y = y0 - Int((hh >> 8) % 8)
                if x < 0 || x >= 16 || z < 0 || z >= 16 || at(x, y, z) != AIR { continue }
                var touching = 0
                for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                    let nx = x + dx, nz = z + dz
                    if nx < 0 || nx >= 16 || nz < 0 || nz >= 16 { continue }
                    if at(nx, y + dy, nz) == glow { touching += 1 }
                }
                if touching == 1 { set(x, y, z, glow) }
            }
        }
        // Fungus trees, roots and vines in the forests (kept inside the chunk).
        for z in 1..<15 {
            for x in 1..<15 {
                let wx = bx + x, wz = bz + z
                let bio = biome(wx, wz)
                guard bio == .crimsonForest || bio == .warpedForest else { continue }
                let crimson = bio == .crimsonForest
                let ny = crimson ? crimsonNy : warpedNy
                for y in 32..<120 where at(x, y, z) == ny && at(x, y + 1, z) == AIR {
                    let h = hash3(wx, y, wz, s32 ^ 0xF6)
                    if h % 100 < 3 && x > 2 && x < 13 && z > 2 && z < 13 {
                        let height = 4 + Int(h >> 8) % 8
                        var free = true
                        for dy in 1...(height + 2) where at(x, y + dy, z) != AIR { free = false; break }
                        if !free { continue }
                        let stem = Blocks.id(crimson ? "crimson_stem" : "warped_stem")
                        let wart = Blocks.id(crimson ? "nether_wart_block" : "warped_wart_block")
                        for dy in 1...height { set(x, y + dy, z, stem) }
                        let top = y + height
                        for dy in -2...1 {
                            let r = dy == 1 ? 1 : 2
                            for dz in -r...r { for dx in -r...r {
                                if abs(dx) == 2 && abs(dz) == 2 { continue }
                                if dy < 0 && abs(dx) < 2 && abs(dz) < 2 { continue }
                                let hh = hash3(wx + dx, top + dy, wz + dz, s32 ^ 0xF7)
                                if at(x + dx, top + dy, z + dz) == AIR { set(x + dx, top + dy, z + dz, hh % 12 == 0 ? Blocks.id("shroomlight") : wart) }
                            } }
                        }
                    } else if h % 100 < 30 {
                        let pl = h % 7 == 0 ? (crimson ? "crimson_fungus" : "warped_fungus") : (crimson ? "crimson_roots" : "warped_roots")
                        set(x, y + 1, z, Blocks.id(pl))
                    }
                }
                if crimson {
                    for y in 40..<124 where at(x, y, z) == netherrack && at(x, y - 1, z) == AIR && hash3(wx, y, wz, s32 ^ 0xF8) % 12 == 0 {
                        let len = 1 + Int(hash3(wx, y, wz, s32 ^ 0xF9) % 6)
                        for i in 1...len where at(x, y - i, z) == AIR { set(x, y - i, z, Blocks.id("weeping_vines")) }
                    }
                }
            }
        }
    }
}

// The End: the central island (~100 blocks across) floating over the void, a 1000-block gap, then
// endless outer islands. Ten obsidian spikes ring the centre (radius 42, heights 76…103, the two
// smallest caged in iron bars) with an end crystal on each; the bedrock exit fountain sits at 0,0.
final class EndGen: TerrainGenerator {
    let seed: UInt64
    let n: Noise, isl: Noise
    private(set) var structures: StructureCache? = nil
    struct Spike { let x: Int; let z: Int; let radius: Int; let height: Int; let guarded: Bool }
    let spikes: [Spike]

    init(seed: UInt64) {
        self.seed = seed
        n = Noise(seed: seed &+ 201)
        isl = Noise(seed: seed &+ 202)
        // Spike sizes are shuffled per world like the reference game (radius 2 + i/3, height 76 + 3i).
        var order = Array(0..<10)
        var rng = SRng(seed ^ 0xE5D)
        for i in stride(from: 9, to: 0, by: -1) { order.swapAt(i, rng.int(i + 1)) }
        var sp: [Spike] = []
        for i in 0..<10 {
            let a = 2 * (-Double.pi + Double.pi / 10 * Double(i))
            let k = order[i]
            sp.append(Spike(x: Int(floor(42 * cos(a))), z: Int(floor(42 * sin(a))), radius: 2 + k / 3, height: 76 + k * 3, guarded: k == 1 || k == 2))
        }
        spikes = sp
        let fountainY = surface(0, 0) ?? (YOFF + 60)
        structures = StructureCache(seed: seed, types: [], fixed: [EndGen.centre(spikes: sp, fountainY: fountainY)])
    }

    func column(_ x: Int, _ z: Int) -> (height: Int, biome: Biome) { (surface(x, z) ?? 0, .theEnd) }
    func tints(cx: Int, cz: Int) -> [UInt32] { [UInt32](repeating: 0xFF3A7ABF, count: 768) }

    // Island top (internal y) at a column, nil over the void; `depth` is how far the island hangs down.
    func island(_ x: Int, _ z: Int) -> (top: Int, depth: Int)? {
        let wx = Float(x), wz = Float(z)
        let d = (wx * wx + wz * wz).squareRoot()
        if d < 130 {
            let edge = 92 + n.noise2(wx / 30, wz / 30) * 10
            if d > edge { return nil }
            let k = 1 - d / edge
            let top = YOFF + 56 + Int(n.noise2(wx / 40, wz / 40) * 3 + k * 8)
            return (top, Int(k * k * 50) + 3)
        }
        if d < 1000 { return nil }
        // Outer islands: blobs from low-frequency noise, thicker in the middle.
        let v = isl.fbm2(wx / 180, wz / 180, 3) + isl.noise2(wx / 45, wz / 45) * 0.25
        let t: Float = 0.22
        if v < t { return nil }
        let k = min(1, (v - t) * 4)
        let top = YOFF + 58 + Int(n.noise2(wx / 60, wz / 60) * 6 + k * 6)
        return (top, Int(k * 30) + 2)
    }

    func surface(_ x: Int, _ z: Int) -> Int? { island(x, z)?.top }

    func generate(cx: Int, cz: Int) -> [BlockID] {
        var b = [BlockID](repeating: AIR, count: CSQ * CH)
        let endStone = Blocks.id("end_stone")
        for z in 0..<CS {
            for x in 0..<CS {
                guard let i = island(cx * CS + x, cz * CS + z) else { continue }
                for y in max(0, i.top - i.depth)...i.top { b[Chunk.index(x, y, z)] = endStone }
            }
        }
        // Chorus plants on the outer islands.
        let d2 = (cx * CS) * (cx * CS) + (cz * CS) * (cz * CS)
        if d2 > 1000 * 1000 {
            for k in 0..<3 {
                let x = Int(hash3(cx, k, cz, 0xC0 ^ UInt32(truncatingIfNeeded: seed)) % 12) + 2
                let z = Int(hash3(cx, k + 7, cz, 0xC1 ^ UInt32(truncatingIfNeeded: seed)) % 12) + 2
                guard let i = island(cx * CS + x, cz * CS + z), hashf(cx, k, cz, 0xC2) < 0.6 else { continue }
                EndGen.chorus(&b, x, i.top + 1, z, hash3(cx, k, cz, 0xC3))
            }
        }
        return b
    }

    // A small branching chorus tree (plant stems with a flower on top), kept inside the chunk.
    static func chorus(_ b: inout [BlockID], _ x: Int, _ y: Int, _ z: Int, _ h: UInt32) {
        guard Blocks.has("chorus_plant") else { return }
        let plant = Blocks.id("chorus_plant"), flower = Blocks.id("chorus_flower")
        let height = 3 + Int(h % 4)
        for i in 0..<height where y + i < CH { b[Chunk.index(x, y + i, z)] = plant }
        let top = y + height
        guard top + 2 < CH else { return }
        for (k, d) in [(1, 0), (-1, 0), (0, 1), (0, -1)].enumerated() where (h >> UInt32(k + 3)) & 1 == 1 {
            let bx = x + d.0, bz = z + d.1
            guard bx >= 0 && bx < CS && bz >= 0 && bz < CS else { continue }
            b[Chunk.index(bx, top - 1, bz)] = plant
            b[Chunk.index(bx, top, bz)] = plant
            b[Chunk.index(bx, top + 1, bz)] = flower
        }
        b[Chunk.index(x, top, z)] = flower
    }

    // Spikes, crystals and the (inactive) exit fountain as one fixed structure.
    static func centre(spikes: [Spike], fountainY fy: Int) -> StructureStart {
        var pieces: [Piece] = []
        for s in spikes {
            let top = YOFF + s.height
            pieces.append(Piece(min: IVec3(s.x - s.radius - 2, YOFF, s.z - s.radius - 2), max: IVec3(s.x + s.radius + 2, top + 4, s.z + s.radius + 2)) { w in
                let obs = OBSIDIAN
                for z in (s.z - s.radius)...(s.z + s.radius) { for x in (s.x - s.radius)...(s.x + s.radius) {
                    let dx = x - s.x, dz = z - s.z
                    if dx * dx + dz * dz <= s.radius * s.radius + 1 { w.fill(x, YOFF + 40, z, x, top, z, obs) }
                } }
                w.set(s.x, top + 1, s.z, BEDROCK)
                w.set(s.x, top + 2, s.z, FIRE)
                if s.guarded {
                    let bars = Blocks.id("iron_bars")
                    for y in (top + 1)...(top + 3) { for z in (s.z - 2)...(s.z + 2) { for x in (s.x - 2)...(s.x + 2) {
                        let edge = abs(x - s.x) == 2 || abs(z - s.z) == 2 || y == top + 3
                        if edge { w.set(x, y, z, bars) }
                    } } }
                }
                w.mob("end_crystal", V3(Float(s.x) + 0.5, Float(top + 2), Float(s.z) + 0.5))
            })
        }
        pieces.append(Piece(min: IVec3(-4, fy - 4, -4), max: IVec3(4, fy + 6, 4)) { w in
            EndGen.fountain(&w, fy, active: false)
        })
        return StructureStart(kind: "end_centre", pieces: pieces, anchor: IVec3(0, fy + 1, 0))
    }

    // The bedrock exit portal: a bowl of radius 3 with a 4-tall centre column and torches.
    static func fountain(_ w: inout StructWriter, _ fy: Int, active: Bool) {
        fountainBlocks(fy, active: active) { x, y, z, b in w.set(x, y, z, b) }
    }

    static func fountainBlocks(_ fy: Int, active: Bool, _ set: (Int, Int, Int, BlockID) -> Void) {
        let portal = Blocks.id("end_portal")
        for z in -4...4 { for x in -4...4 {
            let r2 = x * x + z * z
            if r2 > 12 { continue }
            set(x, fy - 1, z, BEDROCK)
            if r2 >= 9 { set(x, fy, z, BEDROCK) }
            else { set(x, fy, z, active && r2 > 0 ? portal : (r2 == 0 ? BEDROCK : AIR)) }
            for y in (fy + 1)...(fy + 4) where r2 > 0 { set(x, y, z, AIR) }
        } }
        for y in (fy + 1)...(fy + 3) { set(0, y, 0, BEDROCK) }
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { set(dx, fy + 2, dz, Blocks.id("torch")) }
    }
}
