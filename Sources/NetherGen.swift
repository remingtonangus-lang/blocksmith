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
        structures = StructureCache(seed: seed, types: [Fortress.type])
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

// The End (phase D fills in pillars, the exit portal, outer islands and cities).
final class EndGen: TerrainGenerator {
    let seed: UInt64
    let n: Noise
    init(seed: UInt64) { self.seed = seed; n = Noise(seed: seed &+ 201) }
    func column(_ x: Int, _ z: Int) -> (height: Int, biome: Biome) { (YOFF + 60, .theEnd) }
    func tints(cx: Int, cz: Int) -> [UInt32] { [UInt32](repeating: 0xFF3A7ABF, count: 768) }
    func generate(cx: Int, cz: Int) -> [BlockID] {
        var b = [BlockID](repeating: AIR, count: CSQ * CH)
        let endStone = Blocks.id("end_stone")
        for z in 0..<CS {
            for x in 0..<CS {
                let wx = Float(cx * CS + x), wz = Float(cz * CS + z)
                let d = (wx * wx + wz * wz).squareRoot()
                let edge = 90 + n.noise2(wx / 30, wz / 30) * 12
                if d > edge { continue }
                let k = 1 - d / edge
                let top = YOFF + 56 + Int(n.noise2(wx / 40, wz / 40) * 4 + k * 6)
                let depth = Int(k * 40) + 3
                for y in max(0, top - depth)...top { b[Chunk.index(x, y, z)] = endStone }
            }
        }
        return b
    }
}
