import Foundation

// Overworld generator modelled on the reference game's 1.18+ design (own noises and numbers):
//  - five climate parameters per column: temperature, humidity, continentalness, erosion and
//    weirdness (peaks & valleys = 1 - |3|w| - 2|), which pick the biome from multi-noise style tables;
//  - terrain height from continentalness/erosion/PV (oceans, coasts, rivers along weirdness zero
//    lines, plateaus, windswept hills, peaks up to ~y 250) shaped by 3D density for overhangs;
//  - noise caves (cheese caverns, spaghetti tunnels, noodles), aquifers, lava below y -55;
//  - biome surface rules, 1.18 ore distributions, dungeons, geodes, cave biomes, per-biome trees
//    and vegetation, ocean plants, icebergs, ice spikes.
// Density and cave fields are sampled on global lattices, so neighbouring chunks agree exactly.
final class WorldGen: TerrainGenerator {
    let seed: UInt64
    let s32: UInt32
    let tempN: Noise, humN: Noise, contN: Noise, eroN: Noise, weirdN: Noise
    let ridgeN: Noise, detailN: Noise, dens1: Noise, dens2: Noise
    let cheeseN: Noise, spag1: Noise, spag2: Noise, noodle1: Noise, noodle2: Noise, spagMod: Noise
    let flora: Noise, surfN: Noise
    let bands: [BlockID]
    private(set) var structures: StructureCache? = nil

    init(seed: UInt64) {
        self.seed = seed
        s32 = UInt32(truncatingIfNeeded: seed ^ (seed >> 32))
        tempN = Noise(seed: seed &+ 1); humN = Noise(seed: seed &+ 2); contN = Noise(seed: seed &+ 3)
        eroN = Noise(seed: seed &+ 4); weirdN = Noise(seed: seed &+ 5)
        ridgeN = Noise(seed: seed &+ 6); detailN = Noise(seed: seed &+ 7)
        dens1 = Noise(seed: seed &+ 8); dens2 = Noise(seed: seed &+ 9)
        cheeseN = Noise(seed: seed &+ 10); spag1 = Noise(seed: seed &+ 11); spag2 = Noise(seed: seed &+ 12)
        noodle1 = Noise(seed: seed &+ 13); noodle2 = Noise(seed: seed &+ 14); spagMod = Noise(seed: seed &+ 15)
        flora = Noise(seed: seed &+ 16); surfN = Noise(seed: seed &+ 17)
        // Badlands terracotta bands: orange base with bands of other colours (fixed per world).
        var rng = SRng(seed ^ 0xBAD1)
        let colors = ["white", "orange", "yellow", "brown", "red", "light_gray"].map { Blocks.id("\($0)_terracotta") }
        var bs = [BlockID](repeating: Blocks.id("terracotta"), count: 64)
        var i = 0
        while i < 64 {
            i += rng.range(1, 5)
            let c = colors[rng.int(colors.count)]
            for k in 0..<rng.range(1, 3) where i + k < 64 { bs[i + k] = c }
            i += 2
        }
        bands = bs
        structures = StructureCache(seed: seed, types: OverworldStructures.types(self), fixed: Stronghold.starts(seed: seed))
    }

    // MARK: Climate and height

    struct Climate { var t: Float; var h: Float; var c: Float; var e: Float; var w: Float }

    @inline(__always) static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    func climate(_ x: Int, _ z: Int) -> Climate {
        let fx = Float(x), fz = Float(z)
        func n(_ v: Float) -> Float { max(-1, min(1, v)) }
        let t = n(tempN.fbm2(fx / 900, fz / 900, 3) * 2.6)
        let h = n(humN.fbm2(fx / 620, fz / 620, 3) * 2.6)
        let c = max(-1.2, min(1, contN.fbm2(fx / 820, fz / 820, 5) * 2.6 + 0.12))
        let e = n(eroN.fbm2(fx / 660, fz / 660, 4) * 2.4)
        let w = n(weirdN.fbm2(fx / 330, fz / 330, 3) * 2.6)
        return Climate(t: t, h: h, c: c, e: e, w: w)
    }

    struct Shape { var h: Float; var mount: Float; var river: Float }

    // Surface height (displayed y) before 3D shaping.
    func shape(_ k: Climate, _ x: Int, _ z: Int) -> Shape {
        let c = k.c
        var h: Float
        if c < -1.05 {
            h = 25 + 45 * WorldGen.smooth(-1.05, -1.12, c)                 // mushroom islands
        } else {
            let pts: [(Float, Float)] = [(-1.05, 22), (-0.455, 30), (-0.19, 46), (-0.11, 60), (-0.05, 64), (0.03, 67), (0.3, 76), (1.0, 96)]
            h = pts.last!.1
            for i in 1..<pts.count where c <= pts[i].0 {
                let a = pts[i - 1], b = pts[i]
                h = a.1 + (b.1 - a.1) * (c - a.0) / (b.0 - a.0)
                break
            }
        }
        let fx = Float(x), fz = Float(z)
        let inland = WorldGen.smooth(-0.11, 0.25, c)
        let pv = 1 - abs(3 * abs(k.w) - 2)
        let pvn = (pv + 1) / 2
        let m = WorldGen.smooth(0.1, -0.7, k.e) * inland
        let ridge = 1 - abs(ridgeN.noise2(fx / 70, fz / 70))
        h += m * (12 + 150 * powf(pvn, 1.6) + ridge * ridge * ridge * 28 * pvn)
        let hill = (1 - m) * inland * WorldGen.smooth(0.2, 0.75, pv) * WorldGen.smooth(0.5, -0.2, k.e)
        h += hill * 30
        h += detailN.fbm2(fx / 90, fz / 90, 3) * (3 + 7 * inland)
        let flat = WorldGen.smooth(0.45, 0.62, k.e) * (1 - m)
        h += (63 + (h - 63) * 0.25 - h) * flat
        let rv = WorldGen.smooth(0.075, 0.018, abs(k.w)) * WorldGen.smooth(-0.19, -0.1, c) * (1 - min(1, m * 1.6))
        if h > 57 { h += (57 - h) * rv }
        return Shape(h: h, mount: m, river: rv)
    }

    // Multi-noise style biome choice.
    func biome(_ k: Climate, _ s: Shape) -> Biome {
        func band(_ v: Float, _ edges: [Float]) -> Int { var i = 0; while i < edges.count && v > edges[i] { i += 1 }; return i }
        let ti = band(k.t, [-0.45, -0.15, 0.2, 0.55])
        let hi = band(k.h, [-0.35, -0.1, 0.1, 0.3])
        let ei = band(k.e, [-0.78, -0.375, -0.2225, 0.05, 0.45, 0.55])
        let pv = 1 - abs(3 * abs(k.w) - 2)
        let wPos = k.w > 0
        if k.c < -1.05 { return .mushroomFields }
        if k.c < -0.455 { return [Biome.deepFrozenOcean, .deepColdOcean, .deepOcean, .deepLukewarmOcean, .warmOcean][ti] }
        if k.c < -0.19 { return [Biome.frozenOcean, .coldOcean, .ocean, .lukewarmOcean, .warmOcean][ti] }
        if s.river > 0.5 && s.h < 62 { return ti == 0 ? .frozenRiver : .river }
        if k.c < -0.11 && s.h < 66 {
            if ei <= 2 { return .stonyShore }
            return ti == 0 ? .snowyBeach : (ti == 4 ? .desert : .beach)
        }
        // Peaks and slopes.
        if s.mount > 0.55 && pv > 0.55 {
            if ti <= 2 { return wPos ? .jaggedPeaks : .frozenPeaks }
            return ti == 3 ? .stonyPeaks : .badlands
        }
        if s.mount > 0.4 && pv > 0.1 {
            if ti <= 1 { return hi <= 1 ? .snowySlopes : .grove }
            if ti == 4 { return .badlands }
        }
        // Swamps on the flattest ground near the coast.
        if ei == 6 && k.c < 0.1 && ti >= 1 && ti <= 4 { return ti >= 3 ? .mangroveSwamp : .swamp }
        // Windswept.
        if ei == 5 && pv > -0.2 {
            if ti <= 1 { return hi <= 1 ? .windsweptGravellyHills : .windsweptHills }
            if ti == 2 { return hi >= 3 ? .windsweptForest : .windsweptHills }
            return .windsweptSavanna
        }
        let plateau = pv > 0.25 && ei >= 1 && ei <= 3 && k.c > 0.03
        if ti == 4 && (plateau || (ei <= 3 && pv > -0.2)) {
            if hi >= 3 { return .woodedBadlands }
            return wPos && hi <= 1 ? .erodedBadlands : .badlands
        }
        if plateau {
            switch ti {
            case 0: return hi <= 2 ? .snowyPlains : .snowyTaiga
            case 1: return [Biome.meadow, .meadow, .forest, .taiga, .oldGrowthSpruceTaiga][hi]
            case 2: return hi <= 1 ? (wPos ? .cherryGrove : .meadow) : (hi == 2 ? .meadow : (hi == 3 ? .forest : .darkForest))
            case 3: return hi <= 1 ? .savannaPlateau : (hi == 4 ? .jungle : .forest)
            default: return .badlands
            }
        }
        switch ti {
        case 0:
            if hi == 0 && wPos { return .iceSpikes }
            return hi <= 2 ? .snowyPlains : (hi == 3 ? .snowyTaiga : .taiga)
        case 1:
            if hi == 4 { return wPos ? .oldGrowthPineTaiga : .oldGrowthSpruceTaiga }
            return [Biome.plains, .plains, .forest, .taiga, .taiga][hi]
        case 2:
            switch hi {
            case 0: return .flowerForest
            case 1: return wPos ? .sunflowerPlains : .plains
            case 2: return .forest
            case 3: return wPos ? .oldGrowthBirchForest : .birchForest
            default: return .darkForest
            }
        case 3:
            switch hi {
            case 0, 1: return .savanna
            case 2: return wPos ? .plains : .forest
            case 3: return wPos ? .sparseJungle : .jungle
            default: return wPos ? .bambooJungle : .jungle
            }
        default:
            return .desert
        }
    }

    func column(_ x: Int, _ z: Int) -> (height: Int, biome: Biome) {
        let k = climate(x, z)
        let s = shape(k, x, z)
        return (YOFF + Int(s.h.rounded()), biome(k, s))
    }

    // MARK: Density

    private struct Col { var h: Float; var mount: Float; var ocean: Bool }

    private func colInfo(_ x: Int, _ z: Int) -> Col {
        let k = climate(x, z)
        let s = shape(k, x, z)
        return Col(h: s.h, mount: s.mount, ocean: k.c < -0.19)
    }

    // Density at a lattice point (world x, internal y, world z): > 0 is solid.
    private func density(_ col: Col, _ x: Int, _ y: Int, _ z: Int) -> Float {
        let yd = Float(y - YOFF)
        let s: Float = 7 + col.mount * 18
        let base = (col.h - yd) / s
        if base > 2.5 { return base }
        if base < -2.5 { return base }
        let amp: Float = (col.ocean ? 0.15 : 0.25) + col.mount * 0.45
        let fx = Float(x), fz = Float(z)
        let n = dens1.noise3(fx / 80, yd / 50, fz / 80) + dens2.noise3(fx / 28, yd / 18, fz / 28) * 0.5
        return base + n * amp
    }

    // Lattice of density corners around a chunk (x/z step 4 from bx-8 to bx+24, y step 8).
    private struct Lattice {
        static let nx = 9, ny = CH / 8 + 1
        var d: [Float]
        let bx: Int, bz: Int
        @inline(__always) func at(_ gx: Int, _ gy: Int, _ gz: Int) -> Float { d[(gx * Lattice.ny + gy) * Lattice.nx + gz] }
        // Trilinear density at world x,z (within the lattice) and internal y.
        func sample(_ x: Int, _ y: Int, _ z: Int) -> Float {
            let lx = x - (bx - 8), lz = z - (bz - 8)
            let gx = lx >> 2, gz = lz >> 2, gy = min(Lattice.ny - 2, y >> 3)
            let fx = Float(lx & 3) / 4, fz = Float(lz & 3) / 4, fy = Float(y - gy * 8) / 8
            let c000 = at(gx, gy, gz), c100 = at(gx + 1, gy, gz), c010 = at(gx, gy + 1, gz), c110 = at(gx + 1, gy + 1, gz)
            let c001 = at(gx, gy, gz + 1), c101 = at(gx + 1, gy, gz + 1), c011 = at(gx, gy + 1, gz + 1), c111 = at(gx + 1, gy + 1, gz + 1)
            let x00 = c000 + (c100 - c000) * fx, x10 = c010 + (c110 - c010) * fx
            let x01 = c001 + (c101 - c001) * fx, x11 = c011 + (c111 - c011) * fx
            let y0 = x00 + (x10 - x00) * fy, y1 = x01 + (x11 - x01) * fy
            return y0 + (y1 - y0) * fz
        }
        // Topmost solid internal y at a column (ignores caves); nil if none above the floor.
        func top(_ x: Int, _ z: Int, from: Int) -> Int? {
            var y = min(CH - 2, from)
            while y > 4 { if sample(x, y, z) > 0 { return y }; y -= 1 }
            return nil
        }
    }

    private func lattice(_ bx: Int, _ bz: Int) -> (Lattice, [Col]) {
        var cols: [Col] = []
        cols.reserveCapacity(Lattice.nx * Lattice.nx)
        for gx in 0..<Lattice.nx { for gz in 0..<Lattice.nx { cols.append(colInfo(bx - 8 + gx * 4, bz - 8 + gz * 4)) } }
        var d = [Float](repeating: 0, count: Lattice.nx * Lattice.ny * Lattice.nx)
        for gx in 0..<Lattice.nx {
            for gy in 0..<Lattice.ny {
                for gz in 0..<Lattice.nx {
                    let col = cols[gx * Lattice.nx + gz]
                    d[(gx * Lattice.ny + gy) * Lattice.nx + gz] = density(col, bx - 8 + gx * 4, gy * 8, bz - 8 + gz * 4)
                }
            }
        }
        return (Lattice(d: d, bx: bx, bz: bz), cols)
    }

    // MARK: Caves

    // Cave field lattice inside the chunk: 4-block cells, 5 fields.
    private struct CaveLattice {
        static let ny = CH / 4 + 1
        var f: [Float]     // [field][gx][gy][gz]
        @inline(__always) func at(_ k: Int, _ gx: Int, _ gy: Int, _ gz: Int) -> Float { f[((k * 5 + gx) * CaveLattice.ny + gy) * 5 + gz] }
        func sample(_ k: Int, _ lx: Int, _ y: Int, _ lz: Int) -> Float {
            let gx = lx >> 2, gz = lz >> 2, gy = min(CaveLattice.ny - 2, y >> 2)
            let fx = Float(lx & 3) / 4, fz = Float(lz & 3) / 4, fy = Float(y & 3) / 4
            let a = at(k, gx, gy, gz) + (at(k, gx + 1, gy, gz) - at(k, gx, gy, gz)) * fx
            let b = at(k, gx, gy + 1, gz) + (at(k, gx + 1, gy + 1, gz) - at(k, gx, gy + 1, gz)) * fx
            let c = at(k, gx, gy, gz + 1) + (at(k, gx + 1, gy, gz + 1) - at(k, gx, gy, gz + 1)) * fx
            let d = at(k, gx, gy + 1, gz + 1) + (at(k, gx + 1, gy + 1, gz + 1) - at(k, gx, gy + 1, gz + 1)) * fx
            let e = a + (b - a) * fy, g = c + (d - c) * fy
            return e + (g - e) * fz
        }
    }

    private func caveLattice(_ bx: Int, _ bz: Int, maxY: Int) -> CaveLattice {
        var f = [Float](repeating: 0, count: 5 * 5 * CaveLattice.ny * 5)
        let topGY = min(CaveLattice.ny - 1, maxY / 4 + 2)
        for gx in 0..<5 {
            for gz in 0..<5 {
                let x = Float(bx + gx * 4), z = Float(bz + gz * 4)
                for gy in 0...topGY {
                    let y = Float(gy * 4 - YOFF)
                    let base = (gx * CaveLattice.ny + gy) * 5 + gz
                    let stride = 5 * CaveLattice.ny * 5
                    f[base] = cheeseN.noise3(x / 70, y / 38, z / 70)
                    f[base + stride] = spag1.noise3(x / 48, y / 32, z / 48)
                    f[base + stride * 2] = spag2.noise3(x / 48 + 50, y / 32, z / 48)
                    f[base + stride * 3] = noodle1.noise3(x / 22, y / 16, z / 22)
                    f[base + stride * 4] = noodle2.noise3(x / 22 + 30, y / 16, z / 22)
                }
            }
        }
        return CaveLattice(f: f)
    }

    // MARK: Generation

    func generate(cx: Int, cz: Int) -> [BlockID] {
        var b = [BlockID](repeating: AIR, count: CSQ * CH)
        let bx = cx * CS, bz = cz * CS
        let (lat, _) = lattice(bx, bz)
        // Per-column climate, shape and biome.
        var biomes = [Biome](repeating: .plains, count: CSQ)
        var climates = [Climate](repeating: Climate(t: 0, h: 0, c: 0, e: 0, w: 0), count: CSQ)
        var shapes = [Shape](repeating: Shape(h: 0, mount: 0, river: 0), count: CSQ)
        var maxTop = 0
        for lz in 0..<CS { for lx in 0..<CS {
            let k = climate(bx + lx, bz + lz), s = shape(k, bx + lx, bz + lz)
            climates[lx + lz * CS] = k; shapes[lx + lz * CS] = s
            biomes[lx + lz * CS] = biome(k, s)
            maxTop = max(maxTop, YOFF + Int(s.h) + 40)
        } }
        maxTop = min(CH - 1, maxTop)

        // 1. Stone / deepslate from density, bedrock floor.
        let deep = DEEPSLATE
        for lz in 0..<CS { for lx in 0..<CS {
            let wx = bx + lx, wz = bz + lz
            for y in 0...maxTop {
                let i = Chunk.index(lx, y, lz)
                if y < 5 {
                    if y == 0 || hash3(wx, y, wz, s32) % 5 >= UInt32(y) { b[i] = BEDROCK; continue }
                }
                if lat.sample(wx, y, wz) > 0 {
                    let yd = y - YOFF
                    b[i] = yd < 0 || (yd < 8 && Int(hash3(wx, y, wz, s32 ^ 0xDEE) % 8) > yd) ? deep : STONE
                }
            }
        } }

        // 2. Surface rules on the topmost solid block, water / ice up to sea level.
        var tops = [Int](repeating: 0, count: CSQ)
        for lz in 0..<CS { for lx in 0..<CS {
            var y = maxTop
            while y > 0 && b[Chunk.index(lx, y, lz)] == AIR { y -= 1 }
            tops[lx + lz * CS] = y
        } }
        for lz in 0..<CS { for lx in 0..<CS {
            surface(&b, lx, lz, bx + lx, bz + lz, tops, biomes[lx + lz * CS], climates[lx + lz * CS], shapes[lx + lz * CS])
        } }

        // 3. Caves, aquifers, lava.
        let caves = caveLattice(bx, bz, maxY: maxTop)
        carveCaves(&b, caves, bx, bz, tops, biomes)

        // 4. Ores, blobs, dungeons, geodes, cave biome decoration.
        let chunkSeed = UInt64(bitPattern: Int64(cx &* 341873128712 &+ cz &* 132897987541)) ^ seed
        var rng = SRng(chunkSeed)
        placeOres(&b, bx, bz, &rng, biomes)
        placeGeode(&b, bx, bz, &rng)
        placeDungeons(&b, bx, bz, &rng)
        decorateCaves(&b, bx, bz, &rng, climates)

        // 5. Trees and vegetation.
        placeTrees(&b, cx, cz, lat)
        placeVegetation(&b, bx, bz, biomes, &rng)
        return b
    }

    // MARK: Surface

    private func surface(_ b: inout [BlockID], _ lx: Int, _ lz: Int, _ wx: Int, _ wz: Int, _ tops: [Int], _ biome: Biome, _ k: Climate, _ s: Shape) {
        let top = tops[lx + lz * CS]
        guard top > 4 else { return }
        let n = surfN.noise2(Float(wx) / 12, Float(wz) / 12)
        let steep: Bool = {
            let a = tops[max(0, lx - 1) + lz * CS], c = tops[min(CS - 1, lx + 1) + lz * CS]
            let d = tops[lx + max(0, lz - 1) * CS], e = tops[lx + min(CS - 1, lz + 1) * CS]
            return max(abs(a - c), abs(d - e)) >= 4
        }()
        let underwater = top < SEA
        var topBlock = GRASS, filler = DIRT, depth = 3 + Int(hash3(wx, 0, wz, s32 ^ 0x51) % 2)
        var under: BlockID? = nil, underDepth = 0
        let g = Blocks.id
        switch biome {
        case .desert: topBlock = SAND; filler = SAND; under = SANDSTONE; underDepth = 4
        case .beach, .snowyBeach: topBlock = SAND; filler = SAND; under = SANDSTONE; underDepth = 2
        case .stonyShore: topBlock = n > 0.2 ? GRAVEL : STONE; filler = STONE
        case .badlands, .erodedBadlands, .woodedBadlands:
            // Red sand on low flat ground, bare terracotta bands on slopes and higher up.
            let high = biome == .woodedBadlands && top > YOFF + 97
            if high { topBlock = n > 0 ? g("coarse_dirt") : GRASS; filler = DIRT }
            else if !steep && top < YOFF + 72 + Int(n * 6) { topBlock = g("red_sand"); filler = g("red_sand"); depth = 1 + (n > 0.3 ? 1 : 0) }
            else { topBlock = bands[(top + Int(n * 3)) & 63]; filler = topBlock; depth = 1 }
        case .mushroomFields: topBlock = g("mycelium")
        case .oldGrowthPineTaiga, .oldGrowthSpruceTaiga:
            topBlock = n > 0.25 ? g("coarse_dirt") : (n < -0.1 ? g("podzol") : GRASS)
        case .windsweptGravellyHills: topBlock = n > -0.1 ? GRAVEL : STONE; filler = n > -0.1 ? GRAVEL : STONE
        case .jaggedPeaks, .frozenPeaks:
            topBlock = biome == .frozenPeaks && n > 0.3 ? g("packed_ice") : SNOW; filler = steep ? STONE : SNOW; depth = 2
        case .stonyPeaks: topBlock = n > 0.25 ? g("calcite") : STONE; filler = STONE
        case .snowySlopes: topBlock = n > 0.35 ? g("powder_snow") : SNOW; filler = SNOW; depth = 2
        case .grove: topBlock = SNOWY_GRASS
        case .mangroveSwamp: topBlock = g("mud"); filler = g("mud")
        case .swamp: topBlock = GRASS
        case .windsweptSavanna: topBlock = n > 0.3 ? g("coarse_dirt") : (n < -0.35 ? STONE : GRASS)
        case .dripstoneCaves, .lushCaves, .deepDark: break
        default: break
        }
        if steep && [.windsweptHills, .windsweptForest, .stonyPeaks, .jaggedPeaks, .frozenPeaks, .grove, .snowySlopes].contains(biome) && n > -0.2 {
            topBlock = STONE; filler = STONE
        }
        if underwater && !biome.isOcean && !biome.isRiver && biome != .swamp && biome != .mangroveSwamp {
            topBlock = n > 0 ? SAND : GRAVEL; filler = topBlock
        }
        if biome.isOcean || biome.isRiver {
            let depthBelow = SEA - top
            if biome == .warmOcean || biome == .lukewarmOcean || biome == .deepLukewarmOcean {
                topBlock = SAND; filler = SAND
            } else if biome.isRiver {
                topBlock = n > 0.35 ? g("clay") : (n > -0.2 ? SAND : GRAVEL); filler = topBlock
            } else {
                topBlock = depthBelow > 18 || biome == .coldOcean || biome == .frozenOcean || biome.isDeepOcean ? GRAVEL : SAND
                if n > 0.45 { topBlock = g("clay") }
                filler = topBlock
            }
        }
        // Badlands: terracotta bands under the surface layer.
        let isBad = biome.isBadlands
        var y = top
        var placed = 0
        while y > 4 {
            let i = Chunk.index(lx, y, lz)
            let cur = b[i]
            if cur != STONE && cur != DEEPSLATE { break }
            if placed == 0 { b[i] = topBlock }
            else if placed < depth { b[i] = filler }
            else if let u = under, placed < depth + underDepth { b[i] = u }
            else if isBad && y > YOFF + 40 { b[i] = bands[(y + Int(n * 3)) & 63] }
            else { break }
            placed += 1
            y -= 1
        }
        // Eroded badlands hoodoos.
        if biome == .erodedBadlands && !underwater {
            let spire = abs(surfN.noise2(Float(wx) / 5, Float(wz) / 5))
            if spire > 0.35 {
                let hgt = Int((spire - 0.35) * 60)
                if hgt > 0 && top + 1 <= CH - 2 { for yy in (top + 1)...min(CH - 2, top + hgt) { b[Chunk.index(lx, yy, lz)] = bands[yy & 63] } }
            }
        }
        // Water and ice.
        if top < SEA {
            let frozen = biome.snows(at: SEA)
            for yy in (top + 1)...SEA {
                let i = Chunk.index(lx, yy, lz)
                if b[i] == AIR { b[i] = WATER }
            }
            if frozen && (biome.isOcean || biome.isRiver || biome == .snowyBeach || biome.snows(at: SEA)) {
                b[Chunk.index(lx, SEA, lz)] = g("ice")
            }
        } else if biome.snows(at: top + 1) && top + 1 < CH {
            // Snow cover.
            let i = Chunk.index(lx, top, lz)
            if b[i] == GRASS { b[i] = SNOWY_GRASS }
            if b[i] != SNOW && b[i] != g("powder_snow") && b[i] != g("packed_ice") { b[Chunk.index(lx, top + 1, lz)] = g("snow") }
        }
    }

    // MARK: Caves

    private func carveCaves(_ b: inout [BlockID], _ cl: CaveLattice, _ bx: Int, _ bz: Int, _ tops: [Int], _ biomes: [Biome]) {
        let lavaLevel = YOFF - 55
        for lz in 0..<CS { for lx in 0..<CS {
            let top = tops[lx + lz * CS]
            let wetColumn = top < SEA + 2
            let wx = bx + lx, wz = bz + lz
            let maxY = min(CH - 2, wetColumn ? top - 5 : top + 1)
            guard maxY > 6 else { continue }
            for y in 6...maxY {
                let i = Chunk.index(lx, y, lz)
                let cur = b[i]
                if cur == AIR || cur == WATER || cur == BEDROCK || Blocks.isLiquid(cur) { continue }
                let yd = y - YOFF
                var carve = false
                // Cheese caverns, biggest deep down, fading out toward the surface.
                let cheese = cl.sample(0, lx, y, lz) + (yd < 30 ? 0 : -Float(yd - 30) / 90)
                if cheese > 0.3 { carve = true }
                if !carve {
                    let t: Float = 0.05 + 0.025 * spagMod.noise2(Float(wx) / 40, Float(wz) / 40)
                    if abs(cl.sample(1, lx, y, lz)) < t && abs(cl.sample(2, lx, y, lz)) < t { carve = true }
                }
                if !carve && yd < 40 {
                    if abs(cl.sample(3, lx, y, lz)) < 0.022 && abs(cl.sample(4, lx, y, lz)) < 0.022 { carve = true }
                }
                guard carve else { continue }
                // Never open the sea floor: keep a shell under water.
                if y + 1 < CH && Blocks.isLiquid(b[i + CSQ]) { continue }
                if y <= lavaLevel { b[i] = LAVA; continue }
                // Aquifers: some 16-block cells below sea level hold water up to a local level.
                let ax = floorDiv(wx, 16), ay = y >> 4, az = floorDiv(wz, 16)
                let ah = hash3(ax, ay, az, s32 ^ 0xA0F1)
                if y < SEA - 8 && ah % 100 < 22 && y <= ay * 16 + Int(ah >> 8) % 12 { b[i] = WATER; continue }
                b[i] = AIR
            }
        } }
    }

    // MARK: Ores

    private func vein(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ rng: inout SRng, _ ore: BlockID, _ deepOre: BlockID, y: Int, size: Int) {
        let cxr = rng.int(16), czr = rng.int(16)
        // Scattered blob along a short random segment.
        let len = Float(size) / 8
        let a = rng.float() * 2 * .pi
        let dx = cosf(a) * len, dz = sinf(a) * len, dy = (rng.float() - 0.5) * len
        let r = max(0.8, powf(Float(size), 0.33) * 0.7)
        for k in 0..<size {
            let t = Float(k) / Float(max(1, size - 1)) - 0.5
            let px = Float(cxr) + dx * t + (rng.float() - 0.5) * r * 2
            let py = Float(y) + dy * t + (rng.float() - 0.5) * r * 2
            let pz = Float(czr) + dz * t + (rng.float() - 0.5) * r * 2
            let lx = Int(floor(px)), ly = Int(floor(py)), lz = Int(floor(pz))
            guard lx >= 0 && lx < CS && lz >= 0 && lz < CS && ly > 0 && ly < CH else { continue }
            let i = Chunk.index(lx, ly, lz)
            let host = b[i]
            if host == STONE || host == GRANITE_ID || host == DIORITE_ID || host == ANDESITE_ID { b[i] = ore }
            else if host == DEEPSLATE || host == TUFF_ID { b[i] = deepOre }
        }
    }

    private func triangle(_ rng: inout SRng, _ lo: Int, _ hi: Int) -> Int {
        let a = rng.range(lo, (lo + hi) / 2), c = rng.range(0, (hi - lo) / 2)
        return a + c
    }

    private func placeOres(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ rng: inout SRng, _ biomes: [Biome]) {
        let g = Blocks.id
        func y(_ d: Int) -> Int { d + YOFF }
        // Stone variants and dirt/gravel blobs.
        for _ in 0..<2 { vein(&b, bx, bz, &rng, GRANITE_ID, GRANITE_ID, y: y(rng.range(0, 60)), size: 64) }
        for _ in 0..<2 { vein(&b, bx, bz, &rng, DIORITE_ID, DIORITE_ID, y: y(rng.range(0, 60)), size: 64) }
        for _ in 0..<2 { vein(&b, bx, bz, &rng, ANDESITE_ID, ANDESITE_ID, y: y(rng.range(0, 60)), size: 64) }
        if rng.int(6) == 0 { vein(&b, bx, bz, &rng, GRANITE_ID, GRANITE_ID, y: y(rng.range(64, 128)), size: 64) }
        for _ in 0..<2 { vein(&b, bx, bz, &rng, TUFF_ID, TUFF_ID, y: y(rng.range(-64, 0)), size: 64) }
        for _ in 0..<7 { vein(&b, bx, bz, &rng, DIRT, DIRT, y: y(rng.range(0, 160)), size: 33) }
        for _ in 0..<14 { vein(&b, bx, bz, &rng, GRAVEL, GRAVEL, y: y(rng.range(-64, 320)), size: 33) }
        // 1.18+ ore distributions (count per chunk, height distribution, vein size).
        let coal = COAL_ORE, dCoal = g("deepslate_coal_ore")
        for _ in 0..<30 { vein(&b, bx, bz, &rng, coal, dCoal, y: y(rng.range(136, 320)), size: 17) }
        for _ in 0..<20 { vein(&b, bx, bz, &rng, coal, dCoal, y: y(triangle(&rng, 0, 192)), size: 17) }
        let iron = IRON_ORE, dIron = g("deepslate_iron_ore")
        for _ in 0..<90 { vein(&b, bx, bz, &rng, iron, dIron, y: y(triangle(&rng, 80, 384)), size: 9) }
        for _ in 0..<10 { vein(&b, bx, bz, &rng, iron, dIron, y: y(triangle(&rng, -24, 56)), size: 9) }
        for _ in 0..<10 { vein(&b, bx, bz, &rng, iron, dIron, y: y(rng.range(-64, 72)), size: 4) }
        let copper = g("copper_ore"), dCopper = g("deepslate_copper_ore")
        for _ in 0..<16 { vein(&b, bx, bz, &rng, copper, dCopper, y: y(triangle(&rng, -16, 112)), size: 10) }
        let gold = GOLD_ORE, dGold = g("deepslate_gold_ore")
        for _ in 0..<4 { vein(&b, bx, bz, &rng, gold, dGold, y: y(triangle(&rng, -64, 32)), size: 9) }
        if rng.int(2) == 0 { vein(&b, bx, bz, &rng, gold, dGold, y: y(rng.range(-64, -48)), size: 9) }
        if biomes.contains(where: { $0.isBadlands }) {
            for _ in 0..<50 { vein(&b, bx, bz, &rng, gold, dGold, y: y(rng.range(32, 256)), size: 9) }
        }
        let red = g("redstone_ore"), dRed = g("deepslate_redstone_ore")
        for _ in 0..<4 { vein(&b, bx, bz, &rng, red, dRed, y: y(rng.range(-64, 15)), size: 8) }
        for _ in 0..<8 { vein(&b, bx, bz, &rng, red, dRed, y: y(max(-64, triangle(&rng, -96, -32))), size: 8) }
        let lapis = g("lapis_ore"), dLapis = g("deepslate_lapis_ore")
        for _ in 0..<2 { vein(&b, bx, bz, &rng, lapis, dLapis, y: y(triangle(&rng, -32, 32)), size: 7) }
        for _ in 0..<4 { vein(&b, bx, bz, &rng, lapis, dLapis, y: y(rng.range(-64, 64)), size: 7) }
        let diamond = DIAMOND_ORE, dDiamond = g("deepslate_diamond_ore")
        for _ in 0..<7 { vein(&b, bx, bz, &rng, diamond, dDiamond, y: y(max(-64, triangle(&rng, -144, 16))), size: 4) }
        if rng.int(9) == 0 { vein(&b, bx, bz, &rng, diamond, dDiamond, y: y(max(-64, triangle(&rng, -144, 16))), size: 12) }
        for _ in 0..<4 { vein(&b, bx, bz, &rng, diamond, dDiamond, y: y(max(-64, triangle(&rng, -144, 16))), size: 8) }
        if biomes.contains(where: { $0.isPeak || $0 == .windsweptHills || $0 == .windsweptGravellyHills || $0 == .windsweptForest || $0 == .meadow || $0 == .grove }) {
            let em = g("emerald_ore")
            let dEm = Blocks.has("deepslate_emerald_ore") ? g("deepslate_emerald_ore") : em
            for _ in 0..<100 { vein(&b, bx, bz, &rng, em, dEm, y: y(triangle(&rng, -16, 480)), size: 3) }
        }
    }

    // Amethyst geode: 1 in 24 chunks, y -58...30.
    private func placeGeode(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ rng: inout SRng) {
        guard rng.int(24) == 0 else { return }
        let cxr = rng.range(5, 10), czr = rng.range(5, 10), cy = YOFF + rng.range(-58, 30)
        let r = Float(rng.range(4, 5))
        let g = Blocks.id
        let crack = rng.chance(0.95)
        let crackDir = rng.int(4)
        for dy in -6...6 { for dz in -6...6 { for dx in -6...6 {
            let lx = cxr + dx, lz = czr + dz, y = cy + dy
            guard lx >= 0 && lx < CS && lz >= 0 && lz < CS && y > 5 && y < CH - 1 else { continue }
            let d = (Float(dx * dx + dy * dy + dz * dz)).squareRoot() + (hashf(bx + lx, y, bz + lz, s32 ^ 0x6E0) - 0.5) * 0.8
            let i = Chunk.index(lx, y, lz)
            if d > r + 1.6 { continue }
            if b[i] == AIR || Blocks.isLiquid(b[i]) { continue }
            if d > r + 0.8 { b[i] = g("smooth_basalt") }
            else if d > r { b[i] = g("calcite") }
            else if d > r - 0.9 { b[i] = hashf(bx + lx, y, bz + lz, s32 ^ 0x6E1) < 0.08 ? g("budding_amethyst") : g("amethyst_block") }
            else { b[i] = AIR }
        } } }
        // Clusters on the inner wall, and a crack to one side.
        for _ in 0..<6 {
            let lx = cxr + rng.range(-2, 2), lz = czr + rng.range(-2, 2), y = cy - Int(r) + 2
            if lx >= 0 && lx < CS && lz >= 0 && lz < CS && b[Chunk.index(lx, y, lz)] == AIR { b[Chunk.index(lx, y, lz)] = g("amethyst_cluster") }
        }
        if crack {
            let (ddx, ddz) = [(1, 0), (-1, 0), (0, 1), (0, -1)][crackDir]
            for k in Int(r - 1)...Int(r + 2) { for dy in -1...1 {
                let lx = cxr + ddx * k, lz = czr + ddz * k, y = cy + dy
                if lx >= 0 && lx < CS && lz >= 0 && lz < CS { b[Chunk.index(lx, y, lz)] = AIR }
            } }
        }
    }

    // Monster rooms: 8 attempts per chunk; valid when the floor and ceiling are solid and 1-5 wall
    // openings lead out. Cobblestone/mossy walls, a zombie/skeleton/spider spawner, 1-2 chests.
    private func placeDungeons(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ rng: inout SRng) {
        for _ in 0..<8 {
            let cx = rng.range(4, 11), cz = rng.range(4, 11), y = rng.range(8, SEA - 6)
            let rx = rng.range(2, 3), rz = rng.range(2, 3)
            var openings = 0, ok = true
            for dz in -rz - 1...rz + 1 { for dx in -rx - 1...rx + 1 where ok {
                let f = b[Chunk.index(cx + dx, y - 1, cz + dz)], c = b[Chunk.index(cx + dx, y + 4, cz + dz)]
                if !Blocks.opaque[Int(f)] || !Blocks.opaque[Int(c)] { ok = false }
                let edge = abs(dx) == rx + 1 || abs(dz) == rx + 1
                if edge && b[Chunk.index(cx + dx, y, cz + dz)] == AIR && b[Chunk.index(cx + dx, y + 1, cz + dz)] == AIR { openings += 1 }
            } }
            guard ok && openings >= 1 && openings <= 5 else { continue }
            for dy in -1...4 { for dz in -rz - 1...rz + 1 { for dx in -rx - 1...rx + 1 {
                let i = Chunk.index(cx + dx, y + dy, cz + dz)
                let wall = abs(dx) == rx + 1 || abs(dz) == rz + 1 || dy == -1 || dy == 4
                if wall {
                    if dy == -1 { b[i] = rng.chance(0.25) ? COBBLE : Blocks.id("mossy_cobblestone") }
                    else if b[i] != AIR || dy == 4 { b[i] = COBBLE }
                } else { b[i] = AIR }
            } } }
            // Spawner and chests get their block entities from World.orphanEntities (mob and loot
            // are derived from the position, so every thread agrees).
            b[Chunk.index(cx, y, cz)] = Blocks.id("spawner")
            for _ in 0..<rng.range(1, 2) {
                let side = rng.int(4)
                let (px, pz) = [(rx, 0), (-rx, 0), (0, rz), (0, -rz)][side]
                b[Chunk.index(cx + px, y, cz + pz)] = Blocks.id("chest")
            }
            return
        }
    }

    // Cave biomes: lush caves (moss, azalea, cave vines), dripstone caves, deep dark (sculk).
    private func decorateCaves(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ rng: inout SRng, _ climates: [Climate]) {
        let g = Blocks.id
        for lz in 0..<CS { for lx in 0..<CS {
            let k = climates[lx + lz * CS]
            let lush = k.h > 0.55, drip = k.c > 0.75, dark = k.e < -0.6
            guard lush || drip || dark else { continue }
            for y in 8..<(SEA - 10) {
                let i = Chunk.index(lx, y, lz)
                guard b[i] == AIR else { continue }
                let below = b[i - CSQ], above = b[i + CSQ]
                let h = hashf(bx + lx, y, bz + lz, s32 ^ 0xCA7)
                if dark && y < YOFF {
                    if Blocks.opaque[Int(below)] && h < 0.6 { b[i - CSQ] = g("sculk") }
                    if Blocks.opaque[Int(below)] && h > 0.995 { b[i] = g("sculk_shrieker") }
                } else if lush {
                    if Blocks.opaque[Int(below)] && below != BEDROCK {
                        b[i - CSQ] = g("moss_block")
                        if h < 0.08 { b[i] = g("azalea") } else if h < 0.3 { b[i] = g("moss_carpet") } else if h < 0.4 { b[i] = TALL_GRASS }
                    } else if Blocks.opaque[Int(above)] && h < 0.12 {
                        var yy = y
                        let len = 1 + Int(h * 60)
                        while yy > y - len && b[Chunk.index(lx, yy, lz)] == AIR { b[Chunk.index(lx, yy, lz)] = g("cave_vines"); yy -= 1 }
                    }
                } else if drip {
                    if Blocks.opaque[Int(below)] && h < 0.25 { b[i - CSQ] = g("dripstone_block"); if h < 0.06 { b[i] = g("pointed_dripstone") } }
                    if Blocks.opaque[Int(above)] && h > 0.8 { b[i + CSQ] = g("dripstone_block"); if h > 0.93 { b[i] = g("pointed_dripstone") } }
                }
            }
        } }
    }

    // MARK: Tints

    func tints(cx: Int, cz: Int) -> [UInt32] {
        var t = [UInt32](repeating: 0, count: 768)
        func rgba(_ h: UInt32) -> UInt32 { ((h >> 16) & 255) | (((h >> 8) & 255) << 8) | ((h & 255) << 16) | (255 << 24) }
        for lz in 0..<CS { for lx in 0..<CS {
            let info = column(cx * CS + lx, cz * CS + lz).biome.info
            let i = lx + lz * CS
            t[i] = rgba(info.grass); t[256 + i] = rgba(info.foliage); t[512 + i] = rgba(info.water)
        } }
        return t
    }

    // MARK: Trees and vegetation (see WorldGenTrees.swift)

    private func placeTrees(_ b: inout [BlockID], _ cx: Int, _ cz: Int, _ lat: Lattice) {
        TreePlacer.place(&b, cx, cz, gen: self, top: { x, z, hint in lat.top(x, z, from: hint) })
    }
}

// Block ids used by the ore pass.
let GRANITE_ID = Blocks.id("granite")
let DIORITE_ID = Blocks.id("diorite")
let ANDESITE_ID = Blocks.id("andesite")
let TUFF_ID = Blocks.id("tuff")
