import Foundation

// Surface generator: heights, rivers, lakes, climate and biomes come from Terrain (Terrain.swift); this
// class turns them into blocks:
//  - 3D density on a 4x8x4 lattice around the terrain height (overhangs and cliffs in the mountains, calm
//    banks along rivers and lakes);
//  - noise caves (cheese caverns, spaghetti tunnels, noodles), aquifers, lava below y -55;
//  - biome surface rules, 1.18 ore distributions, dungeons, geodes, cave biomes, per-biome trees
//    and vegetation, ocean plants, icebergs, ice spikes.
// Density and cave fields are sampled on global lattices, so neighbouring chunks agree exactly.
final class WorldGen: TerrainGenerator {
    let seed: UInt64
    let s32: UInt32
    let tempN: Noise, humN: Noise, contN: Noise, eroN: Noise, weirdN: Noise
    let ridgeN: Noise, detailN: Noise, dens1: Noise, dens2: Noise
    let cheeseN: Noise, spag1: Noise, spag2: Noise, noodle1: Noise, noodle2: Noise, spagMod: Noise, pocketNoise: Noise
    let flora: Noise, surfN: Noise
    let veinTog: Noise, veinA: Noise, veinB: Noise
    let bands: [BlockID]
    let terrain: Terrain
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
        pocketNoise = Noise(seed: seed &+ 0x1A7A)
        flora = Noise(seed: seed &+ 16); surfN = Noise(seed: seed &+ 17)
        veinTog = Noise(seed: seed &+ 30); veinA = Noise(seed: seed &+ 31); veinB = Noise(seed: seed &+ 32)
        terrain = Terrain(seed: seed)
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
        structures = StructureCache(seed: seed, types: OverworldStructures.types(self) + BigStructures.types(self) + [MilitaryBase.type(self), CapitalCity.type(self), AncientSpire.type(self)], fixed: Stronghold.starts(seed: seed))
    }

    // MARK: Cave climate

    // Underground climate (cave biomes, murk depths sites): five independent noises, unrelated to the surface.
    struct Climate { var t: Float; var h: Float; var c: Float; var e: Float; var w: Float }

    @inline(__always) static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float { Terrain.smooth(e0, e1, x) }

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

    // MARK: Columns

    // Surface fields at a column (bilinear between lattice nodes).
    func columnData(_ x: Int, _ z: Int) -> Terrain.Column { terrain.column(x, z) }

    func column(_ x: Int, _ z: Int) -> (height: Int, biome: Biome) {
        let k = terrain.column(x, z)
        return (YOFF + Int(floorf(k.h)), terrain.biome(k, k.h))
    }

    // MARK: Density

    private struct Col { var h: Float; var amp: Float; var s: Float }

    private func colInfo(_ n: Terrain.Node) -> Col {
        let ocean = n.h < SEA_D - 1 && n.wl <= SEA_D
        let wet = n.rv < 3 || n.wl > SEA_D + 0.01
        var amp: Float = ocean ? 0.15 : 0.2 + n.u * 0.35
        if wet { amp = 0.03 }
        return Col(h: n.h, amp: amp, s: 7 + n.u * 14)
    }

    private func colInfo(_ x: Int, _ z: Int) -> Col { colInfo(terrain.node(floorDiv(x, 4), floorDiv(z, 4))) }

    // Density at a lattice point (world x, internal y, world z): > 0 is solid.
    private func density(_ col: Col, _ x: Int, _ y: Int, _ z: Int) -> Float {
        let yd = Float(y - YOFF)
        let base = (col.h - yd) / col.s
        if base > 2.5 { return base }
        if base < -2.5 { return base }
        let fx = Float(x), fz = Float(z)
        let n = dens1.noise3(fx / 80, yd / 50, fz / 80) + dens2.noise3(fx / 28, yd / 18, fz / 28) * 0.5
        return base + n * col.amp
    }

    // Top solid internal y at a column (terrain only: no caves, trees or water), bit-identical to what
    // the chunk lattice produces, so structures can agree on ground height across chunks.
    func groundY(_ x: Int, _ z: Int) -> Int {
        let x0 = floorDiv(x, 4) * 4, z0 = floorDiv(z, 4) * 4
        let fx = Float(x - x0) / 4, fz = Float(z - z0) / 4
        let c00 = colInfo(x0, z0), c10 = colInfo(x0 + 4, z0), c01 = colInfo(x0, z0 + 4), c11 = colInfo(x0 + 4, z0 + 4)
        var y = min(CH - 2, YOFF + Int(max(max(c00.h, c10.h), max(c01.h, c11.h))) + 40)
        var cachedGY = -1
        var L0: (Float, Float, Float, Float) = (0, 0, 0, 0), L1: (Float, Float, Float, Float) = (0, 0, 0, 0)
        while y > 4 {
            let gy = min(Lattice.ny - 2, y >> 3)
            if gy != cachedGY {
                cachedGY = gy
                L0 = (density(c00, x0, gy * 8, z0), density(c10, x0 + 4, gy * 8, z0), density(c01, x0, gy * 8, z0 + 4), density(c11, x0 + 4, gy * 8, z0 + 4))
                let y1 = (gy + 1) * 8
                L1 = (density(c00, x0, y1, z0), density(c10, x0 + 4, y1, z0), density(c01, x0, y1, z0 + 4), density(c11, x0 + 4, y1, z0 + 4))
            }
            let fy = Float(y - gy * 8) / 8
            let x00 = L0.0 + (L0.1 - L0.0) * fx, x10 = L1.0 + (L1.1 - L1.0) * fx
            let x01 = L0.2 + (L0.3 - L0.2) * fx, x11 = L1.2 + (L1.3 - L1.2) * fx
            let y0 = x00 + (x10 - x00) * fy, y1v = x01 + (x11 - x01) * fy
            if y0 + (y1v - y0) * fz > 0 { return y }
            y -= 1
        }
        return 0
    }

    func bankWater(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ tops: inout [Int], _ wls: [Int], _ nodes: [Terrain.Node]) {
        let tops0 = tops
        // A column just across the border, blended from this chunk's own node grid (it spans 8 blocks past each
        // edge): bit-identical to terrain.column there, without its four fresh node evaluations per call (those made
        // generation 2.5x slower near lakes: bench gen.chunk_ms 2.08 -> 5.11, run 363).
        func across(_ lx: Int, _ lz: Int) -> Terrain.Column {
            let gx = (lx + 8) >> 2, gz = (lz + 8) >> 2
            let fx = Float((lx + 8) & 3) / 4, fz = Float((lz + 8) & 3) / 4
            return Terrain.blend(nodes[gx * 9 + gz], nodes[(gx + 1) * 9 + gz], nodes[gx * 9 + gz + 1], nodes[(gx + 1) * 9 + gz + 1], fx, fz)
        }
        for lz in 0..<CS { for lx in 0..<CS {
            let k = lx + lz * CS
            let myTop = tops0[k], myWl = wls[k]
            let level = max(myTop, myWl)
            var want = level
            // Lake water on the chunk's edge beside a lower dry column in the next chunk: that column can't see the
            // lake cheaply (above), so this column becomes the bank instead (gencheck run 357: 246 water-beside-air
            // leaks, every one on a chunk border).
            let edge = lx == 0 || lx == CS - 1 || lz == 0 || lz == CS - 1
            if edge && myWl > myTop && myWl > SEA {
                var spill = false, lowerWater = false
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = lx + dx, nz = lz + dz
                    guard nx < 0 || nx >= CS || nz < 0 || nz >= CS else { continue }
                    let nc = across(nx, nz)
                    let nTop = YOFF + Int(nc.h), nWl = YOFF + Int(floorf(nc.wl))
                    if nWl <= nTop && nTop < myWl { spill = true }
                    if nWl > nTop && nWl < myWl { lowerWater = true }
                }
                // Lake water a level above the sea (or a lower lake) across the border: the lower side can't see it
                // (its own water is at sea level, so it never asks across), so the lake's edge column becomes the
                // shallow flowing lip itself (gencheck run 362: all 228 leaks were "+x/+z: open 0 down to water").
                if lowerWater && !spill { b[Chunk.index(lx, myWl, lz)] = WATER_FLOW[2] }
                if spill {
                    let floorB = b[Chunk.index(lx, myTop, lz)]
                    let fill: BlockID = (floorB == AIR || Blocks.isLiquid(floorB)) ? DIRT : (floorB == GRASS ? DIRT : floorB)
                    for y in (myTop + 1)...myWl { b[Chunk.index(lx, y, lz)] = fill }
                    tops[k] = myWl
                    continue
                }
            }
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = lx + dx, nz = lz + dz
                var nTop: Int, nWl: Int
                if nx >= 0 && nx < CS && nz >= 0 && nz < CS {
                    nTop = tops0[nx + nz * CS]; nWl = wls[nx + nz * CS]
                } else {
                    // Across the chunk border from the 2D column blended from this chunk's node grid (cheap, so every
                    // border column asks: a dry column at sea level now sees a lake one block up across the border).
                    let nc = across(nx, nz)
                    nTop = YOFF + Int(nc.h)
                    nWl = YOFF + Int(floorf(nc.wl))
                }
                guard nWl > nTop, nWl > SEA, nWl > level else { continue }
                want = max(want, nWl)
            }
            guard want > level, want < CH - 2 else { continue }
            if myWl > myTop {
                // Water here, lower: a lip one level down, or a cascade down to this surface.
                if want == myWl + 1 { b[Chunk.index(lx, want, lz)] = WATER_FLOW[2] }
                else { for y in (myWl + 1)...want where b[Chunk.index(lx, y, lz)] == AIR { b[Chunk.index(lx, y, lz)] = WATER_FALL } }
            } else if want - myTop > 2 {
                // Dry and well below (a lake over a slope): the water spills down as a cascade, not a pillar of bank.
                for y in (myTop + 1)...want where b[Chunk.index(lx, y, lz)] == AIR { b[Chunk.index(lx, y, lz)] = WATER_FALL }
            } else {
                // Dry and just below: raise a bank to the water's level in the column's own top material.
                let topB = b[Chunk.index(lx, myTop, lz)]
                guard topB != AIR && !Blocks.isLiquid(topB) else { continue }
                let fill: BlockID = topB == GRASS ? DIRT : topB
                b[Chunk.index(lx, myTop, lz)] = fill
                for y in (myTop + 1)...want { b[Chunk.index(lx, y, lz)] = y == want ? topB : fill }
                tops[k] = want
            }
        } }
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

    // Harness self-check (--bench gen): the stone fill's per-column row interpolation must give exactly
    // Lattice.sample's value for every block. Returns the number of mismatching samples.
    func latticeRowMismatches(cx: Int, cz: Int) -> Int {
        let bx = cx * CS, bz = cz * CS
        let (lat, _) = lattice(bx, bz)
        var rowA = [Float](repeating: 0, count: Lattice.ny), rowB = [Float](repeating: 0, count: Lattice.ny)
        var bad = 0
        for lz in 0..<CS { for lx in 0..<CS {
            let wx = bx + lx, wz = bz + lz
            let llx = wx - (bx - 8), llz = wz - (bz - 8)
            let gx = llx >> 2, gz = llz >> 2
            let fx = Float(llx & 3) / 4, fz = Float(llz & 3) / 4
            for gy in 0..<Lattice.ny {
                let c0 = lat.at(gx, gy, gz), c1 = lat.at(gx + 1, gy, gz)
                let d0 = lat.at(gx, gy, gz + 1), d1 = lat.at(gx + 1, gy, gz + 1)
                rowA[gy] = c0 + (c1 - c0) * fx
                rowB[gy] = d0 + (d1 - d0) * fx
            }
            for y in 0..<CH {
                let gy = min(Lattice.ny - 2, y >> 3)
                let fy = Float(y - gy * 8) / 8
                let y0 = rowA[gy] + (rowA[gy + 1] - rowA[gy]) * fy
                let y1 = rowB[gy] + (rowB[gy + 1] - rowB[gy]) * fy
                if (y0 + (y1 - y0) * fz).bitPattern != lat.sample(wx, y, wz).bitPattern { bad += 1 }
            }
        } }
        return bad
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

    // Lattice nodes covering a chunk and its 8-block margin (9 x 9, x-major like the density lattice).
    func chunkNodes(_ bx: Int, _ bz: Int) -> [Terrain.Node] {
        var nodes = [Terrain.Node]()
        nodes.reserveCapacity(81)
        let gx0 = floorDiv(bx - 8, 4), gz0 = floorDiv(bz - 8, 4)
        for gx in 0..<9 { for gz in 0..<9 { nodes.append(terrain.node(gx0 + gx, gz0 + gz)) } }
        return nodes
    }

    // Column fields for the chunk's 256 columns from its node grid.
    func chunkColumns(_ nodes: [Terrain.Node]) -> [Terrain.Column] {
        var cols = [Terrain.Column]()
        cols.reserveCapacity(CSQ)
        for lz in 0..<CS { for lx in 0..<CS {
            let gx = (lx + 8) >> 2, gz = (lz + 8) >> 2
            let fx = Float((lx + 8) & 3) / 4, fz = Float((lz + 8) & 3) / 4
            cols.append(Terrain.blend(nodes[gx * 9 + gz], nodes[(gx + 1) * 9 + gz], nodes[gx * 9 + gz + 1], nodes[(gx + 1) * 9 + gz + 1], fx, fz))
        } }
        return cols
    }

    // Per-phase generation time (bench gen only, single-threaded): columns, stone, surface+water, caves, ores and
    // cave decoration, trees, vegetation and freeze.
    static var timing = false
    static var phaseMs = [Double](repeating: 0, count: 8)
    static let timingLock = NSLock()          // other worlds' workers may generate while the bench times (also startMs)
    static let phaseNames = ["columns", "stone", "surface", "caves", "ores", "trees", "plants", "starts"]

    func generate(cx: Int, cz: Int) -> [BlockID] {
        var tp: Double = WorldGen.timing ? CFAbsoluteTimeGetCurrent() : 0
        func mark(_ k: Int) {
            guard WorldGen.timing else { return }
            let n = CFAbsoluteTimeGetCurrent()
            WorldGen.timingLock.lock(); WorldGen.phaseMs[k] += (n - tp) * 1000; WorldGen.timingLock.unlock()
            tp = n
        }
        var b = [BlockID](repeating: AIR, count: CSQ * CH)
        let bx = cx * CS, bz = cz * CS
        let (lat, _) = lattice(bx, bz)
        // Per-column terrain fields and biome.
        let nodes = chunkNodes(bx, bz)
        let cols = chunkColumns(nodes)
        var biomes = [Biome](repeating: .plains, count: CSQ)
        var climates = [Climate](repeating: Climate(t: 0, h: 0, c: 0, e: 0, w: 0), count: CSQ)
        var maxTop = 0
        for lz in 0..<CS { for lx in 0..<CS {
            let k = cols[lx + lz * CS]
            climates[lx + lz * CS] = climate(bx + lx, bz + lz)
            // Surface and plants use a per-column dithered climate, so borders fray into a mixed band of
            // both biomes' ground cover rather than a crisp line.
            // Mostly a 5-block noise with a little per-column jitter: pure per-column noise speckled borders like
            // salt and pepper (run 362 snowy village: single white snow squares scattered through the grass).
            let wxf = Float(bx + lx), wzf = Float(bz + lz)
            let nT: Float = flora.noise2(wxf / 5 + 311, wzf / 5 - 173), nW: Float = flora.noise2(wxf / 5 - 529, wzf / 5 + 97)
            let jT: Float = hashf(bx + lx, 5, bz + lz, s32 ^ 0xD17) - 0.5, jW: Float = hashf(bx + lx, 6, bz + lz, s32 ^ 0xD18) - 0.5
            let dT: Float = (nT * 0.75 + jT * 0.35) * 0.07
            let dW: Float = (nW * 0.75 + jW * 0.35) * 0.09
            let dith = terrain.biome(k, k.h, dT: dT, dW: dW)
            let base = terrain.biome(k, k.h)
            biomes[lx + lz * CS] = dith.isDry == base.isDry ? dith : base
            maxTop = max(maxTop, YOFF + Int(k.h) + 40)
        } }
        maxTop = min(CH - 1, maxTop)

        mark(0)
        // 1. Stone / deeprock from density, bedrock floor.
        let deep = DEEPSLATE, magma = Blocks.id("magma_block")
        // Per column, the lattice is first interpolated along x at every lattice layer (two z rows), then
        // each block only lerps along y and z: the same operations in the same order as Lattice.sample
        // (bit-identical, groundY relies on it) without 8 lattice loads per block.
        var rowA = [Float](repeating: 0, count: Lattice.ny), rowB = [Float](repeating: 0, count: Lattice.ny)
        let topGY = min(Lattice.ny - 1, min(Lattice.ny - 2, maxTop >> 3) + 1)
        for lz in 0..<CS { for lx in 0..<CS {
            let wx = bx + lx, wz = bz + lz
            let llx = wx - (bx - 8), llz = wz - (bz - 8)
            let gx = llx >> 2, gz = llz >> 2
            let fx = Float(llx & 3) / 4, fz = Float(llz & 3) / 4
            for gy in 0...topGY {
                let c0 = lat.at(gx, gy, gz), c1 = lat.at(gx + 1, gy, gz)
                let d0 = lat.at(gx, gy, gz + 1), d1 = lat.at(gx + 1, gy, gz + 1)
                rowA[gy] = c0 + (c1 - c0) * fx
                rowB[gy] = d0 + (d1 - d0) * fx
            }
            for y in 0...maxTop {
                let i = Chunk.index(lx, y, lz)
                // No bedrock floor: the bottom layers are always solid hot rock, and digging through layer 0 drops into
                // the Deep below (DeepSeam.swift).
                if y < 3 { b[i] = EMBERSLATE; continue }
                let gy = min(Lattice.ny - 2, y >> 3)
                let fy = Float(y - gy * 8) / 8
                let y0 = rowA[gy] + (rowA[gy + 1] - rowA[gy]) * fy
                let y1 = rowB[gy] + (rowB[gy + 1] - rowB[gy]) * fy
                if y0 + (y1 - y0) * fz > 0 {
                    let yd = y - YOFF
                    if yd < -24 {
                        // The deeper, the hotter: emberslate creeps into the deeprock below -24 and owns it below -56,
                        // with the odd magma block.
                        let h = hash3(wx, y, wz, s32 ^ 0xE5B)
                        if Int(h % 32) < -24 - yd { b[i] = yd < -40 && h % 53 == 0 ? magma : EMBERSLATE; continue }
                    }
                    b[i] = yd < 0 || (yd < 8 && Int(hash3(wx, y, wz, s32 ^ 0xDEE) % 8) > yd) ? deep : STONE
                }
            }
        } }

        mark(1)
        // 2. Surface rules on the topmost solid block, water up to the local water level (sea, river, lake).
        var tops = [Int](repeating: 0, count: CSQ)
        var wls = [Int](repeating: SEA, count: CSQ)
        for lz in 0..<CS { for lx in 0..<CS {
            var y = maxTop
            while y > 0 && b[Chunk.index(lx, y, lz)] == AIR { y -= 1 }
            tops[lx + lz * CS] = y
            wls[lx + lz * CS] = YOFF + Int(floorf(cols[lx + lz * CS].wl))
        } }
        for lz in 0..<CS { for lx in 0..<CS {
            surface(&b, lx, lz, bx + lx, bz + lz, tops, biomes[lx + lz * CS], cols[lx + lz * CS], wls[lx + lz * CS])
        } }

        // Volcano lava: the crater lake fills to its level; channels down the flanks are one block of lava sunk
        // into the slope (bounded: static sources until something touches them).
        for lz in 0..<CS { for lx in 0..<CS {
            let k = cols[lx + lz * CS]
            guard k.vol > 0.2 else { continue }
            let top = tops[lx + lz * CS]
            if k.lava > 0 {
                let lv = YOFF + Int(floorf(k.lava))
                if top < lv { for y in (top + 1)...lv where b[Chunk.index(lx, y, lz)] == AIR { b[Chunk.index(lx, y, lz)] = LAVA } }
            } else if k.flow > 0.5 && top > 8 {
                b[Chunk.index(lx, top, lz)] = LAVA
                b[Chunk.index(lx, top - 1, lz)] = Blocks.id("magma_block")
            }
        } }

        // Shallow pools in the flat ground of swamps.
        let tops0 = tops
        for lz in 1..<(CS - 1) { for lx in 1..<(CS - 1) {
            let biome = biomes[lx + lz * CS]
            guard biome == .swamp || biome == .mangroveSwamp else { continue }
            let top = tops[lx + lz * CS]
            guard top >= wls[lx + lz * CS], flora.noise2(Float(bx + lx) / 11, Float(bz + lz) / 11) > 0.02 else { continue }   // more standing water (a swamp shot read as dry grass: critic, run 385)
            let held = [(1, 0), (-1, 0), (0, 1), (0, -1)].allSatisfy { d in tops0[lx + d.0 + (lz + d.1) * CS] >= top }
            if held { b[Chunk.index(lx, top, lz)] = WATER; tops[lx + lz * CS] = top - 1 }
        } }

        // River steps and lake edges: water filled per column to its own level stood as a one-block wall beside a
        // lower neighbour (gencheck "leak", ~1 per chunk). From the lower side: a column with water just below gets a
        // shallow flowing lip (or a falling cascade for a bigger drop), a dry one a bank up to the water.
        bankWater(&b, bx, bz, &tops, wls, nodes)

        mark(2)
        // 3. Caves, aquifers, lava.
        let caves = caveLattice(bx, bz, maxY: maxTop)
        var aquifer: [Int32] = []
        carveCaves(&b, caves, bx, bz, tops, wls, cols, &aquifer)
        carveRavines(&b, bx, bz, tops, wls, &aquifer)
        drainAquifers(&b, aquifer)
        lavaPockets(&b, bx, bz)
        supportFalling(&b, tops)

        mark(3)
        // 4. Ores, blobs, dungeons, geodes, cave biome decoration.
        let chunkSeed = UInt64(bitPattern: Int64(cx &* 341873128712 &+ cz &* 132897987541)) ^ seed
        var rng = SRng(chunkSeed)
        placeOres(&b, bx, bz, &rng, biomes)
        placeOreVeins(&b, bx, bz)
        placeGeode(&b, bx, bz, &rng)
        placeDungeons(&b, bx, bz, &rng)
        decorateCaves(&b, bx, bz, &rng, climates)
        clearIsolated(&b, tops)

        mark(4)
        // Structure starts near the chunk (layouts computed on first use; trees keep out of them). Timed on their own:
        // they were counted as tree time.
        if WorldGen.timing, let sc = structures { for t in sc.types { _ = sc.startsNear(cx: cx, cz: cz, t) }; mark(7) }
        // 5. Trees and vegetation.
        placeTrees(&b, cx, cz, lat)
        mark(5)
        placeVegetation(&b, bx, bz, biomes, &rng, cols: cols)
        freeze(&b, bx, bz, biomes, cols, tops)
        hardenLava(&b)
        mark(6)
        return b
    }

    // Lava the generator left touching water (an aquifer or sea over a lava pocket, a river or ravine cutting a lava
    // lake) hardens as the fluid tick would have made it: sources to obsidian, flowing lava to cobblestone. Nothing
    // ticked it at generation, so water sat on open lava (Quest v63 report). Within the chunk; the runtime tick
    // handles contact made later.
    func hardenLava(_ b: inout [BlockID]) {
        let fk = Blocks.fluidKind, lv = Blocks.fluidLevel
        b.withUnsafeMutableBufferPointer { p in
            for y in 0..<CH {
                for z in 0..<CS {
                    for x in 0..<CS {
                        let i = Chunk.index(x, y, z)
                        guard fk[Int(p[i])] == 2 else { continue }
                        let wet = (y + 1 < CH && fk[Int(p[i + CSQ])] == 1) || (y > 0 && fk[Int(p[i - CSQ])] == 1)
                            || (x > 0 && fk[Int(p[i - 1])] == 1) || (x < CS - 1 && fk[Int(p[i + 1])] == 1)
                            || (z > 0 && fk[Int(p[i - CS])] == 1) || (z < CS - 1 && fk[Int(p[i + CS])] == 1)
                        if wet { p[i] = lv[Int(p[i])] == 0 ? OBSIDIAN : COBBLE }
                    }
                }
            }
        }
    }

    // Single blocks the cave and ravine carvers left hanging with air on all six sides (gencheck floating_block: lone
    // stone and ore cells in cave air). Chunk interior only (a neighbour across the border isn't known here).
    private func clearIsolated(_ b: inout [BlockID], _ tops: [Int]) {
        let up = CSQ
        for lz in 1..<(CS - 1) { for lx in 1..<(CS - 1) {
            let top = tops[lx + lz * CS]
            guard top > 8 else { continue }
            for y in 6..<(top - 1) {
                let i = Chunk.index(lx, y, lz)
                let c = b[i]
                if c == AIR || b[i - up] != AIR || b[i + up] != AIR { continue }
                if b[i - 1] != AIR || b[i + 1] != AIR || b[i - CS] != AIR || b[i + CS] != AIR { continue }
                if Blocks.isLiquid(c) { continue }
                b[i] = AIR
            }
        } }
    }

    // MARK: Surface

    private func surface(_ b: inout [BlockID], _ lx: Int, _ lz: Int, _ wx: Int, _ wz: Int, _ tops: [Int], _ biome: Biome, _ k: Terrain.Column, _ wl: Int) {
        let top = tops[lx + lz * CS]
        guard top > 4 else { return }
        let n = surfN.noise2(Float(wx) / 12, Float(wz) / 12)
        let xa: Int = max(0, lx - 1) + lz * CS, xc: Int = min(CS - 1, lx + 1) + lz * CS
        let zd: Int = lx + max(0, lz - 1) * CS, ze: Int = lx + min(CS - 1, lz + 1) * CS
        let rise: Int = max(abs(tops[xa] - tops[xc]), abs(tops[zd] - tops[ze]))
        let steep = rise >= 4
        var topBlock = GRASS, filler = DIRT, depth = 3 + Int(hash3(wx, 0, wz, s32 ^ 0x51) % 2)
        var under: BlockID? = nil, underDepth = 0
        let g = Blocks.id
        let underwater = top < wl
        switch biome {
        case .desert: topBlock = SAND; filler = SAND; under = SANDSTONE; underDepth = 4
        case .beach, .snowyBeach:
            // Shingle on cold coasts, sand elsewhere.
            let shingle = k.ts < -0.05 && n > 0.15 - k.ts
            topBlock = shingle ? GRAVEL : SAND; filler = topBlock; under = SANDSTONE; underDepth = 2
        case .stonyShore: topBlock = n > 0.2 ? GRAVEL : (n < -0.35 ? g("andesite") : STONE); filler = STONE
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
        // Cliffs show bare rock whatever grows above and below them.
        if rise >= 7 && !underwater && !biome.isBadlands && topBlock != SAND {
            topBlock = n > 0.3 ? g("andesite") : STONE; filler = STONE
        }
        // Gravel and sand bars along river and lake shores.
        if !underwater && k.rv < 1.5 && top <= wl + 1 && abs(n) > 0.3 && !biome.isOcean && !biome.isBadlands && biome != .swamp && biome != .mangroveSwamp {
            topBlock = n > 0 ? SAND : GRAVEL; filler = topBlock
        }
        // Dry lake beds: salt crust and clay.
        if k.dry > 0.5 && !underwater { topBlock = n > -0.25 ? g("calcite") : g("clay"); filler = SAND }
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
        // Volcano cones (Landmarks.swift): basalt and tuff flanks streaked with blackstone, scoria near the crater.
        if k.vol > 0.35 && !underwater {
            let hot = k.lava > 0 || k.flow > 0.3
            // Old flows run down the fall line: dark streaks radiating from the crater, wobbling with the surface noise
            // (plain noise patches read as camouflage blotches on the cone: blind critic, volcano_far).
            var streak: Float = n
            if let v = terrain.nearestVolcano(Float(wx), Float(wz), cells: 1) {
                let dx = Float(wx) - v.x, dz = Float(wz) - v.z
                let ang: Float = atan2f(dz, dx)
                let wob: Float = n * 0.9 + (dx * dx + dz * dz).squareRoot() / 41
                streak = sinf(ang * 26 + wob) * 0.7 + n * 0.45
            }
            topBlock = hot ? (n > 0.1 ? g("magma_block") : g("blackstone")) : (streak > 0.6 ? g("blackstone") : (streak < -0.62 ? g("tuff") : g("basalt")))
            filler = n > 0 ? g("tuff") : g("basalt"); depth = 4; under = nil
        } else if k.vol > 0.1 && !underwater && n > 0.15 {
            topBlock = g("tuff")                                       // ash scattered over the foot
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
            else if k.cyn > 0.25 && y > top - 100 { b[i] = bands[(y + Int(n * 3)) & 63] }     // canyon walls: banded rock
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
        // Water up to the local water level (ice and snow come in the final freeze pass).
        if top < wl {
            for yy in (top + 1)...wl {
                let i = Chunk.index(lx, yy, lz)
                if b[i] == AIR { b[i] = WATER }
            }
        }
    }

    // Last decoration step, like the reference game's freeze_top_layer: snow on whatever is on top
    // (ground, leaves) and ice on still water where it is cold enough.
    // Snow follows the surface temperature (altitude lapse included), so snowlines climb in warm regions.
    private func freeze(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ biomes: [Biome], _ cols: [Terrain.Column], _ tops: [Int]) {
        let snowLayer = Blocks.id("snow"), ice = Blocks.id("ice")
        for lz in 0..<CS { for lx in 0..<CS {
            let biome = biomes[lx + lz * CS]
            var y = CH - 2
            while y > 1 && b[Chunk.index(lx, y, lz)] == AIR { y -= 1 }
            // Dither: the snowline frays over a band instead of ending in a sharp edge, in clumps a few blocks wide (a
            // per-column hash scattered single snow squares through the grass: run 362 snowy village).
            // Patches about 7 blocks across with only a trace of per-column jitter (at 4 blocks and 0.3 jitter a snowy
            // village edge was still a scatter of single white squares: eyes-on village2, run 377).
            let clump: Float = flora.noise2(Float(bx + lx) / 7 + 731, Float(bz + lz) / 7 + 419)
            let jit: Float = hashf(bx + lx, y, bz + lz, s32 ^ 0x5110) - 0.5
            let t = terrain.temperature(cols[lx + lz * CS], Float(y + 1 - YOFF)) + (clump * 0.9 + jit * 0.08) * 0.12
            let cold = t < -0.25 || (biome.snows(at: y + 1) && t < -0.15)
            guard cold else { continue }
            let kc = cols[lx + lz * CS]
            if kc.lava > 0 || kc.flow > 0.3 { continue }                // volcano heat: no snow on the crater or channels
            // Steep rock faces shed their snow.
            let xa = max(0, lx - 1) + lz * CS, xb = min(CS - 1, lx + 1) + lz * CS
            let za = lx + max(0, lz - 1) * CS, zb = lx + min(CS - 1, lz + 1) * CS
            let riseX = abs(tops[xa] - tops[xb]), riseZ = abs(tops[za] - tops[zb])
            let rise = max(riseX, riseZ)
            let rocky = b[Chunk.index(lx, y, lz)] == STONE || Blocks.key(b[Chunk.index(lx, y, lz)]) == "andesite"
            if rocky && rise >= 4 { continue }
            let i = Chunk.index(lx, y, lz)
            let top = b[i]
            if top == WATER { b[i] = ice; continue }
            if top == GRASS { b[i] = SNOWY_GRASS }
            let solidTop = Blocks.opaque[Int(top)] || Blocks.key(top).hasSuffix("_leaves")
            if solidTop && top != SNOW && top != ice && Blocks.key(top) != "packed_ice" && Blocks.key(top) != "powder_snow" {
                b[i + CSQ] = snowLayer
            }
        } }
    }

    // MARK: Caves

    private func carveCaves(_ b: inout [BlockID], _ cl: CaveLattice, _ bx: Int, _ bz: Int, _ tops: [Int], _ wls: [Int], _ cols: [Terrain.Column],
                            _ aquifer: inout [Int32]) {
        let lavaLevel = YOFF - 55
        for lz in 0..<CS { for lx in 0..<CS {
            let top = tops[lx + lz * CS]
            let wetColumn = top < wls[lx + lz * CS] + 2 || cols[lx + lz * CS].rv < 2.5
            let wx = bx + lx, wz = bz + lz
            let maxY = min(CH - 2, wetColumn ? top - 5 : top + 1)
            guard maxY > 6 else { continue }
            // Spaghetti tunnel width: a column constant (it was evaluated for every block of the column, ~38k noise
            // calls per chunk: the biggest share of generate's time in the CI profile).
            let spagT: Float = 0.05 + 0.025 * spagMod.noise2(Float(wx) / 40, Float(wz) / 40)
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
                    if abs(cl.sample(1, lx, y, lz)) < spagT && abs(cl.sample(2, lx, y, lz)) < spagT { carve = true }
                }
                if !carve && yd < 40 {
                    if abs(cl.sample(3, lx, y, lz)) < 0.022 && abs(cl.sample(4, lx, y, lz)) < 0.022 { carve = true }
                }
                guard carve else { continue }
                // Never open the sea floor: keep a shell under water.
                if y + 1 < CH && Blocks.isLiquid(b[i + CSQ]) { continue }
                if y <= lavaLevel { b[i] = LAVA; continue }
                // Aquifers: some 16-block cells below sea level hold water up to a local level; drainAquifers then
                // lets out whatever isn't held in a basin.
                if aquiferWet(wx, y, wz) { b[i] = WATER; aquifer.append(Int32(i)); continue }
                b[i] = AIR
            }
        } }
    }

    // Sealed lava pockets in the hot rock below -30, more of them deeper: rock that is solid on all six sides (never
    // beside a cave or the chunk edge, so nothing spills when the chunk loads) turns to lava. Mining into one lets it out.
    private func lavaPockets(_ b: inout [BlockID], _ bx: Int, _ bz: Int) {
        let top = YOFF - 30
        for y in 4..<top {
            let yd = y - YOFF
            let t: Float = 0.62 - Float(-30 - yd) * 0.006          // 0.62 at -30 ... 0.42 at -64
            for lz in 1..<(CS - 1) { for lx in 1..<(CS - 1) {
                let i = Chunk.index(lx, y, lz)
                guard b[i] == EMBERSLATE || b[i] == DEEPSLATE else { continue }
                let wx = bx + lx, wz = bz + lz
                guard pocketNoise.noise3(Float(wx) / 9, Float(y) / 6, Float(wz) / 9) > t else { continue }
                var sealed = true
                for o in [1, -1, CS, -CS, CSQ, -CSQ] {
                    let n = b[i + o]
                    if !(Blocks.opaque[Int(n)] || n == LAVA) { sealed = false; break }
                }
                if sealed { b[i] = LAVA }
            }
            }
        }
    }

    // Aquifer water stays only where it is held: a cell with open air beside or below it (or the chunk edge, whose
    // far side isn't known here) drains to air, and so does everything that leaned on it. What is left are pools in
    // real basins: no flat 16-block water slabs cut off by rock plugs at chunk edges, no stone plates left under the
    // water, nothing hanging or spilling when the chunk loads (Quest round 3: ugly cave pools).
    private func drainAquifers(_ b: inout [BlockID], _ cells: [Int32]) {
        if cells.isEmpty { return }
        var wet = [Bool](repeating: false, count: b.count)
        for c in cells where b[Int(c)] == WATER { wet[Int(c)] = true }
        func open(_ j: Int) -> Bool { b[j] == AIR }
        func exposed(_ i: Int) -> Bool {
            let x = i & 15, z = (i >> 4) & 15
            if x == 0 || x == 15 || z == 0 || z == 15 { return true }
            return open(i - 1) || open(i + 1) || open(i - CS) || open(i + CS) || (i >= CSQ && open(i - CSQ))
        }
        var stack = cells.map { Int($0) }.filter { wet[$0] && exposed($0) }
        while let i = stack.popLast() {
            guard wet[i] else { continue }
            wet[i] = false
            b[i] = AIR
            let x = i & 15, z = (i >> 4) & 15
            for j in [x > 0 ? i - 1 : -1, x < 15 ? i + 1 : -1, z > 0 ? i - CS : -1, z < 15 ? i + CS : -1, i + CSQ < b.count ? i + CSQ : -1]
            where j >= 0 && wet[j] { stack.append(j) }
        }
    }

    @inline(__always) func aquiferWet(_ wx: Int, _ y: Int, _ wz: Int) -> Bool {
        guard y < SEA - 8 else { return false }
        let ax = floorDiv(wx, 16), ay = y >> 4, az = floorDiv(wz, 16)
        let ah = hash3(ax, ay, az, s32 ^ 0xA0F1)
        return ah % 100 < 22 && y <= ay * 16 + Int(ah >> 8) % 12
    }

    // Ravines: long, narrow, tall cracks (about one per 150 chunks), wandering slowly in heading and depth.
    // Each 112-block region may hold one; its path depends only on the region, so chunks agree.
    private func carveRavines(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ tops: [Int], _ wls: [Int], _ aquifer: inout [Int32]) {
        let rsz = 112
        let lavaLevel = YOFF - 55
        for rz in (floorDiv(bz, rsz) - 1)...(floorDiv(bz + CS - 1, rsz) + 1) {
            for rx in (floorDiv(bx, rsz) - 1)...(floorDiv(bx + CS - 1, rsz) + 1) {
                var rng = SRng(UInt64(hash3(rx, 0x7A1, rz, s32 ^ 0x5A5A)) | 1)
                guard rng.int(3) == 0 else { continue }
                var px = Float(rx * rsz + rng.range(16, rsz - 16)), pz = Float(rz * rsz + rng.range(16, rsz - 16))
                var py = Float(YOFF + rng.range(-20, 50))
                var yaw = rng.float() * 2 * .pi, pitch = (rng.float() - 0.5) * 0.25
                let len = rng.range(70, 120)
                let wmax = 2.2 + rng.float() * 2.8
                var dyaw: Float = 0, dpitch: Float = 0
                for k in 0..<len {
                    let t = Float(k) / Float(len)
                    let r = 0.9 + wmax * sinf(Float.pi * t)
                    let hh = r * 3
                    px += cosf(yaw) * cosf(pitch); pz += sinf(yaw) * cosf(pitch); py += sinf(pitch)
                    dyaw = dyaw * 0.5 + (rng.float() - 0.5) * 0.25
                    dpitch = dpitch * 0.8 + (rng.float() - 0.5) * 0.08
                    yaw += dyaw * 0.25; pitch = pitch * 0.7 + dpitch
                    let ir = Int(r) + 1
                    let cx = Int(floorf(px)), cz = Int(floorf(pz))
                    if cx + ir < bx || cx - ir >= bx + CS || cz + ir < bz || cz - ir >= bz + CS { continue }
                    let y0 = max(6, Int(py - hh)), y1 = min(CH - 2, Int(py + hh))
                    guard y0 <= y1 else { continue }
                    for z in max(bz, cz - ir)...min(bz + CS - 1, cz + ir) {
                        for x in max(bx, cx - ir)...min(bx + CS - 1, cx + ir) {
                            let dx = Float(x) + 0.5 - px, dz = Float(z) + 0.5 - pz
                            let lx = x - bx, lz = z - bz
                            let top = tops[lx + lz * CS]
                            let wet = top < wls[lx + lz * CS] + 2
                            for y in y0...y1 {
                                if wet && y > top - 5 { break }
                                let dy = (Float(y) + 0.5 - py) / hh
                                let jag = (hashf(x, y, z, s32 ^ 0x5A5B) - 0.5) * 0.3
                                if (dx * dx + dz * dz) / (r * r) + dy * dy > 1 + jag { continue }
                                let i = Chunk.index(lx, y, lz)
                                let cur = b[i]
                                if cur == AIR || cur == BEDROCK || Blocks.isLiquid(cur) { continue }
                                if y + 1 < CH && Blocks.isLiquid(b[i + CSQ]) { continue }
                                if y <= lavaLevel { b[i] = LAVA; continue }
                                // Aquifers, as in the cave carver (drainAquifers keeps only basins).
                                if aquiferWet(x, y, z) { b[i] = WATER; aquifer.append(Int32(i)); continue }
                                b[i] = AIR
                            }
                        }
                    }
                }
            }
        }
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
            // Gravel blobs keep off cave ceilings: placed after the caves are carved, a blob over a cave hung there and
            // fell at the first block update (gencheck run 357: 623 gravel-over-air blocks in 288 chunks).
            if ore == GRAVEL && ly > 1 && b[Chunk.index(lx, ly - 1, lz)] == AIR { continue }
            if host == STONE || host == GRANITE_ID || host == DIORITE_ID || host == ANDESITE_ID { b[i] = ore }
            else if host == DEEPSLATE || host == TUFF_ID || host == EMBERSLATE { b[i] = deepOre }
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
        // Copper also feeds wiring (sparkstone ore is gone): two extra deep copper veins.
        for _ in 0..<2 { vein(&b, bx, bz, &rng, copper, dCopper, y: y(rng.range(-64, 15)), size: 10) }
        let lapis = g("lapis_ore"), dLapis = g("deepslate_lapis_ore")
        for _ in 0..<2 { vein(&b, bx, bz, &rng, lapis, dLapis, y: y(triangle(&rng, -32, 32)), size: 7) }
        for _ in 0..<4 { vein(&b, bx, bz, &rng, lapis, dLapis, y: y(rng.range(-64, 64)), size: 7) }
        let diamond = DIAMOND_ORE, dDiamond = g("deepslate_diamond_ore")
        // Titanium (save key diamond_ore): rarer than the reference diamond veins.
        for _ in 0..<5 { vein(&b, bx, bz, &rng, diamond, dDiamond, y: y(max(-64, triangle(&rng, -144, 16))), size: 3) }
        if rng.int(12) == 0 { vein(&b, bx, bz, &rng, diamond, dDiamond, y: y(max(-64, triangle(&rng, -144, 16))), size: 8) }
        for _ in 0..<2 { vein(&b, bx, bz, &rng, diamond, dDiamond, y: y(max(-64, triangle(&rng, -144, 16))), size: 6) }
        if biomes.contains(where: { $0.isPeak || $0 == .windsweptHills || $0 == .windsweptGravellyHills || $0 == .windsweptForest || $0 == .meadow || $0 == .grove }) {
            let em = g("emerald_ore")
            let dEm = Blocks.has("deepslate_emerald_ore") ? g("deepslate_emerald_ore") : em
            for _ in 0..<100 { vein(&b, bx, bz, &rng, em, dEm, y: y(triangle(&rng, -16, 480)), size: 3) }
        }
    }

    // Large ore veins: thin snaking ribbons where two noise fields are both near zero, in regions picked by a
    // third. Copper veins run through granite between y 0 and 50, iron veins through tuff between y -60 and -8.
    private func placeOreVeins(_ b: inout [BlockID], _ bx: Int, _ bz: Int) {
        let g = Blocks.id
        let copper: (BlockID, BlockID, BlockID) = (GRANITE_ID, g("copper_ore"), Blocks.has("raw_copper_block") ? g("raw_copper_block") : g("copper_ore"))
        let iron: (BlockID, BlockID, BlockID) = (TUFF_ID, g("deepslate_iron_ore"), Blocks.has("raw_iron_block") ? g("raw_iron_block") : g("deepslate_iron_ore"))
        let y0 = YOFF - 60, y1 = YOFF + 50
        let ny = (y1 - y0) / 4 + 2
        // 4-block lattice of the three fields, trilinear inside.
        var f = [Float](repeating: 0, count: 3 * 5 * 5 * ny)
        @inline(__always) func at(_ k: Int, _ gx: Int, _ gy: Int, _ gz: Int) -> Float { f[((k * 5 + gx) * ny + gy) * 5 + gz] }
        var any = false
        for gx in 0..<5 { for gz in 0..<5 { for gy in 0..<ny {
            let x = Float(bx + gx * 4), z = Float(bz + gz * 4), y = Float(y0 + gy * 4 - YOFF)
            let tg = veinTog.noise3(x / 150, y / 150, z / 150)
            f[((0 * 5 + gx) * ny + gy) * 5 + gz] = tg
            if abs(tg) > 0.3 { any = true }
            f[((1 * 5 + gx) * ny + gy) * 5 + gz] = veinA.noise3(x / 22, y / 22, z / 22)
            f[((2 * 5 + gx) * ny + gy) * 5 + gz] = veinB.noise3(x / 22 + 40, y / 22, z / 22)
        } } }
        guard any else { return }
        func sample(_ k: Int, _ lx: Int, _ ly: Int, _ lz: Int) -> Float {
            let gx = lx >> 2, gy = ly >> 2, gz = lz >> 2
            let fx = Float(lx & 3) / 4, fy = Float(ly & 3) / 4, fz = Float(lz & 3) / 4
            let a = at(k, gx, gy, gz) + (at(k, gx + 1, gy, gz) - at(k, gx, gy, gz)) * fx
            let c = at(k, gx, gy + 1, gz) + (at(k, gx + 1, gy + 1, gz) - at(k, gx, gy + 1, gz)) * fx
            let d = at(k, gx, gy, gz + 1) + (at(k, gx + 1, gy, gz + 1) - at(k, gx, gy, gz + 1)) * fx
            let e = at(k, gx, gy + 1, gz + 1) + (at(k, gx + 1, gy + 1, gz + 1) - at(k, gx, gy + 1, gz + 1)) * fx
            let p = a + (c - a) * fy, q = d + (e - d) * fy
            return p + (q - p) * fz
        }
        // Walk 4x4x4 cells; skip a cell unless the region field is strong at a corner and both ribbon fields
        // can cross zero inside it (trilinear values stay between the corner extremes).
        for cgx in 0..<4 { for cgz in 0..<4 { for cgy in 0..<(ny - 1) {
            var tmax: Float = 0, aLo: Float = 9, aHi: Float = -9, bLo: Float = 9, bHi: Float = -9
            for c in 0..<8 {
                let gx = cgx + (c & 1), gy = cgy + ((c >> 1) & 1), gz = cgz + (c >> 2)
                tmax = max(tmax, abs(at(0, gx, gy, gz)))
                let a = at(1, gx, gy, gz), bb = at(2, gx, gy, gz)
                aLo = min(aLo, a); aHi = max(aHi, a); bLo = min(bLo, bb); bHi = max(bHi, bb)
            }
            if tmax < 0.3 || aLo > 0.07 || aHi < -0.07 || bLo > 0.07 || bHi < -0.07 { continue }
            for dy in 0..<4 {
                let ly = cgy * 4 + dy, y = y0 + ly
                if y >= y1 || (y >= YOFF - 8 && y < YOFF) { continue }
                let kind = y < YOFF - 8 ? iron : copper
                for dz in 0..<4 { for dx in 0..<4 {
                    let lx = cgx * 4 + dx, lz = cgz * 4 + dz
                    guard abs(sample(0, lx, ly, lz)) > 0.3, abs(sample(1, lx, ly, lz)) < 0.07, abs(sample(2, lx, ly, lz)) < 0.07 else { continue }
                    let i = Chunk.index(lx, y, lz)
                    let host = b[i]
                    guard host == STONE || host == DEEPSLATE || host == GRANITE_ID || host == DIORITE_ID || host == ANDESITE_ID || host == TUFF_ID else { continue }
                    let h = hashf(bx + lx, y, bz + lz, s32 ^ 0x0E1)
                    if h < 0.62 { b[i] = kind.0 } else if h < 0.88 { continue } else if h < 0.995 { b[i] = kind.1 } else { b[i] = kind.2 }
                } }
            }
        } } }
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

    // Sand and gravel left as a cave or ravine ceiling turn to their stone (gencheck unsupported: beach sand over a
    // cave fell at the first block update, 100 in 288 chunks, run 371). Only near the surface, where they're laid.
    private func supportFalling(_ b: inout [BlockID], _ tops: [Int]) {
        let redSand = Blocks.id("red_sand"), redStone = Blocks.id("red_sandstone")
        for lz in 0..<CS { for lx in 0..<CS {
            let top = tops[lx + lz * CS]
            var y = min(CH - 2, top + 1)
            while y > max(1, top - 10) {
                let i = Chunk.index(lx, y, lz)
                let v = b[i]
                if (v == SAND || v == redSand || v == GRAVEL) && b[i - CSQ] == AIR {
                    b[i] = v == SAND ? SANDSTONE : (v == redSand ? redStone : STONE)
                }
                y -= 1
            }
        } }
    }

    // Cave biomes: lush caves (moss, azalea, cave vines), driprock caves, murk depths (murk).
    private func decorateCaves(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ rng: inout SRng, _ climates: [Climate]) {
        let g = Blocks.id
        // Ids looked up once (string dictionary lookups ran per cave cell).
        let id_azalea = g("azalea")
        let id_big_dripleaf = g("big_dripleaf")
        let id_cave_vines = g("cave_vines")
        let id_clay = g("clay")
        let id_dripstone_block = g("dripstone_block")
        let id_glow_lichen = g("glow_lichen")
        let id_hanging_roots = g("hanging_roots")
        let id_moss_block = g("moss_block")
        let id_moss_carpet = g("moss_carpet")
        let id_pointed_dripstone = g("pointed_dripstone")
        let id_sculk = g("sculk")
        let id_sculk_catalyst = g("sculk_catalyst")
        let id_sculk_sensor = g("sculk_sensor")
        let id_sculk_shrieker = g("sculk_shrieker")
        let id_sculk_vein = g("sculk_vein")
        let id_small_dripleaf = g("small_dripleaf")
        let id_spore_blossom = g("spore_blossom")
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
                    if Blocks.opaque[Int(below)] && h < 0.6 { b[i - CSQ] = id_sculk }
                    if Blocks.opaque[Int(below)] {
                        if h > 0.997 { b[i] = id_sculk_shrieker }
                        else if h > 0.993 { b[i] = id_sculk_sensor }
                        else if h > 0.9925 { b[i] = id_sculk_catalyst }
                        else if h > 0.75 && h < 0.85 { b[i] = id_sculk_vein }
                    }
                } else if lush {
                    if Blocks.opaque[Int(below)] && below != BEDROCK {
                        b[i - CSQ] = id_moss_block
                        if h < 0.08 { b[i] = id_azalea } else if h < 0.3 { b[i] = id_moss_carpet } else if h < 0.4 { b[i] = TALL_GRASS }
                        else if h < 0.43 { b[i] = id_small_dripleaf } else if h < 0.45 { b[i] = id_big_dripleaf }
                        else if h > 0.97 { b[i - CSQ] = id_clay }
                    } else if Blocks.opaque[Int(above)] && h > 0.985 {
                        b[i] = id_spore_blossom
                    } else if Blocks.opaque[Int(above)] && h > 0.9 {
                        b[i] = id_hanging_roots
                    } else if Blocks.opaque[Int(above)] && h < 0.12 {
                        var yy = y
                        let len = 1 + Int(h * 60)
                        while yy > y - len && b[Chunk.index(lx, yy, lz)] == AIR { b[Chunk.index(lx, yy, lz)] = id_cave_vines; yy -= 1 }
                    }
                } else if !dark && y < SEA - 20 && (Blocks.opaque[Int(below)] || Blocks.opaque[Int(above)]) && h > 0.996 {
                    b[i] = id_glow_lichen
                } else if drip {
                    if Blocks.opaque[Int(below)] && h < 0.25 { b[i - CSQ] = id_dripstone_block; if h < 0.06 { b[i] = id_pointed_dripstone } }
                    if Blocks.opaque[Int(above)] && h > 0.8 { b[i + CSQ] = id_dripstone_block; if h > 0.93 { b[i] = id_pointed_dripstone } }
                }
            }
        } }
    }

    // MARK: Tints

    // Grass, foliage and water colours blended in climate space: each column averages the colours of the
    // biomes a little warmer, colder, wetter and drier than itself, so tints fade across borders over tens of
    // blocks (wider where the climate changes slowly) instead of switching at a line.
    private static let tintOffsets: [(Float, Float, Float)] = [(0, 0, 2), (0.09, 0, 1), (-0.09, 0, 1), (0, 0.1, 1), (0, -0.1, 1),
                                                                (0.06, 0.07, 1), (-0.06, -0.07, 1), (0.06, -0.07, 1), (-0.06, 0.07, 1)]

    func tints(cx: Int, cz: Int) -> [UInt32] {
        var t = [UInt32](repeating: 0, count: 768)
        func byte(_ v: Float) -> UInt32 { UInt32(max(0, min(255, v.rounded()))) }
        func rgba(_ r: Float, _ g: Float, _ b: Float) -> UInt32 {
            let lo: UInt32 = byte(r) | (byte(g) << 8)
            return lo | (byte(b) << 16) | (255 << 24)
        }
        let cols = chunkColumns(chunkNodes(cx * CS, cz * CS))
        for i in 0..<CSQ {
            let k = cols[i]
            var gr: Float = 0, gg: Float = 0, gb: Float = 0, fr: Float = 0, fg: Float = 0, fb: Float = 0
            var wr: Float = 0, wg: Float = 0, wb: Float = 0, wsum: Float = 0
            for (dT, dW, wt) in WorldGen.tintOffsets {
                let info = terrain.biome(k, k.h, dT: dT, dW: dW).info
                gr += Float((info.grass >> 16) & 255) * wt; gg += Float((info.grass >> 8) & 255) * wt; gb += Float(info.grass & 255) * wt
                fr += Float((info.foliage >> 16) & 255) * wt; fg += Float((info.foliage >> 8) & 255) * wt; fb += Float(info.foliage & 255) * wt
                wr += Float((info.water >> 16) & 255) * wt; wg += Float((info.water >> 8) & 255) * wt; wb += Float(info.water & 255) * wt
                wsum += wt
            }
            let inv = 1 / wsum
            t[i] = rgba(gr * inv, gg * inv, gb * inv)
            t[256 + i] = rgba(fr * inv, fg * inv, fb * inv)
            t[512 + i] = rgba(wr * inv, wg * inv, wb * inv)
        }
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
