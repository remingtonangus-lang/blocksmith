import Foundation
import simd

// F4 (Oct 13 evening playtest, Remington's idea: "full chunks out to 20, then cheap rings out to 40 or more"): the
// middle ring. Past the loaded chunks the ground goes on as a low-poly height field at its true world position, out
// to `outer` blocks: one vertex every 8 blocks next to the loaded edge, 16 farther, 32 at the rim, coloured per vertex
// from the same column function and map colours as the horizon shell (HorizonRing), lakes and seas as flat quads at
// their water level, volcano crater lakes as lava. No entities, no blocks, no textures: one draw call.
//
// The Quest draws it (WorldRenderer.drawFarRing, quest/shaders/far.vert) right after the opaque terrain with depth
// testing, so the loaded chunks hide it wherever they stand; the vertex shader sinks every vertex inside the loaded
// disc out of sight (a dozen blocks, ramped over the last 24 blocks of the disc) and keeps the edge band 2 blocks under
// its true height, so the seam has no crack and never pokes through real ground. The fog runs out to the ring's rim
// while it shows (WorldRenderer.uniforms), so the chunks and the ring share one fog and the rim melts into the horizon
// shell, which is drawn behind it on the far plane.
//
// Built on a background queue whenever the player crosses a 128-block cell (or the render distance changes) and
// swapped in whole; column samples are kept between builds (a move re-samples only the new strip). Vertices are
// relative to the build centre (`cx`, `cz`), four per quad (the shared quad index buffer draws them).
final class FarRing {
    static let shared = FarRing()
    // BS_FARRING=0 turns the ring off (before/after measurements).
    static var enabled = ProcessInfo.processInfo.environment["BS_FARRING"] != "0"
    static let outer: Float = 1024                 // blocks: the rim (64 chunks)
    static let cell = 128                          // rebuild cell
    static let spacings = [8, 16, 32]

    struct Mesh {
        var seed: UInt64 = 0
        var cx = 0, cz = 0                         // world position of the vertices' origin
        var rd = 0                                 // render distance it was cut for
        var gen = 0                                // build counter (the renderer uploads each one once)
        var blocky = false                         // terraced block columns (block world) or the smooth field
        var verts: [SimpleVert] = []
        var quads: Int { verts.count / 4 }
    }

    // kind: 0 ground, 1 water, 2 lava. `side`: the colour of the ground's flanks seen from the side in a block world
    // (dirt under grass, rock on cliffs: P250 b).
    struct Sample { var y: Float; var c: V3; var kind: Float; var side: V3 = V3(0, 0, 0) }

    private let lock = NSLock()
    private var mesh: Mesh?
    private var building = false
    private var want = (Int.min, Int.min, -1, false)
    private var seed: UInt64 = 0
    private var builds = 0
    private var memo: [Int64: Sample] = [:]        // touched only by the one build running (`building`)
    private var memoSeed: UInt64 = 0
    private(set) var lastBuildMs = 0.0

    func current() -> Mesh? {
        lock.lock(); defer { lock.unlock() }
        return mesh
    }

    // The radius around the player chunk's centre that is surely inside the loaded (meshed) disc, in blocks: chunk
    // (dx, dz) is meshed when dx^2 + dz^2 <= r^2 + r (World.inMeshRadius), and a point lies within 11.3 blocks of its
    // chunk's centre.
    static func loadedRadius(_ rd: Int) -> Float {
        let r2: Float = Float(rd * rd + rd)
        return 16 * r2.squareRoot() - 12
    }

    // P250 (c): the radius (blocks, round the player chunk's centre) that is meshed right now: the loaded radius, cut
    // to the nearest chunk still missing or unmeshed (World.meshedReach) while chunks stream in. A point within 11.3
    // blocks of a chunk's centre lies in that chunk, so everything inside 16 * sqrt(gap) - 12 is in meshed chunks.
    static func meshedRadius(_ w: World, _ rd: Int, center: ChunkKey) -> Float {
        let gap = w.meshedReach(center)
        return min(loadedRadius(rd), max(0, 16 * Float(gap).squareRoot() - 12))
    }

    // Starts a build when the player has moved into another cell, the render distance changed or the world changed.
    func request(_ g: Game, eye: V3) {
        guard FarRing.enabled, let gen = g.world.gen as? WorldGen else { return }
        let kx = Int(floor(eye.x / Float(FarRing.cell))), kz = Int(floor(eye.z / Float(FarRing.cell)))
        let rd = g.world.renderDistance
        // A block world's ring is terraced columns, a Polygons world's the smooth field (PG1 rewrite: a field world is
        // never blocks). Part of the key (P250 b): toggling Smooth Terrain, or another world with the same seed, rebuilds.
        let blocky = !SmoothTerrain.enabled && !g.world.fieldTerrain
        lock.lock()
        let same = want == (kx, kz, rd, blocky) && seed == g.world.seed
        if same || building { lock.unlock(); return }
        building = true
        want = (kx, kz, rd, blocky)
        seed = g.world.seed
        let fresh = mesh?.seed != seed || mesh?.blocky != blocky
        let sd = seed
        builds += 1
        let n = builds
        lock.unlock()
        let cx = kx * FarRing.cell + FarRing.cell / 2, cz = kz * FarRing.cell + FarRing.cell / 2
        let work = { [weak self] in
            guard let self else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            if self.memoSeed != sd || self.memo.count > 150_000 { self.memo.removeAll(keepingCapacity: true); self.memoSeed = sd }
            var out = Mesh(seed: sd, cx: cx, cz: cz, rd: rd, gen: n, blocky: blocky)
            out.verts = FarRing.build(gen, cx: cx, cz: cz, rin: FarRing.loadedRadius(rd), memo: &self.memo, blocky: blocky)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            self.lock.lock()
            // A build for a world left meanwhile is dropped (the next request starts the new world's).
            if sd == self.seed { self.mesh = out } else { self.want = (Int.min, Int.min, -1, false) }
            self.lastBuildMs = ms
            self.building = false
            self.lock.unlock()
        }
        // The first ring of a world is built here and now (at load, like HorizonRing); later ones in the background
        // while the old ring stays up.
        if fresh { work() } else { DispatchQueue.global(qos: .utility).async(execute: work) }
    }

    // One column: its top (ground, water surface or crater lava) and colour.
    static func sample(_ gen: WorldGen, _ x: Int, _ z: Int) -> Sample {
        let k = gen.columnData(x, z)
        let b = gen.terrain.biome(k, k.h)
        let top = YOFF + Int(floorf(k.h))
        let wl = YOFF + Int(floorf(k.wl))
        func rgb(_ v: UInt32) -> V3 { V3(Float((v >> 16) & 255), Float((v >> 8) & 255), Float(v & 255)) / 255 }
        if k.vol > 0.2 && k.lava > k.h {
            return Sample(y: Float(YOFF) + floorf(k.lava) + 1, c: V3(0.95, 0.42, 0.1), kind: 2)
        }
        // P250 (b, c): the generator's final freeze (WorldGen.freeze) puts snow on the ground and ice on still water
        // wherever the surface temperature is cold enough, whatever the biome; the ring showed green grass and open sea
        // past snowy, iced chunks (a hard seam at the loaded edge on his 11:58 flight). Same test, without the dither.
        func cold(_ y: Int) -> Bool {
            guard k.lava <= 0 && k.flow <= 0.3 && k.vol <= 0.3 else { return false }     // volcano heat
            let t = gen.terrain.temperature(k, Float(y + 1 - YOFF))
            return t < -0.25 || (b.snows(at: y + 1) && t < -0.15)
        }
        if wl > top {
            if cold(wl) { return Sample(y: Float(wl) + 1, c: FarRing.ice, kind: 0, side: FarRing.ice * 0.92) }
            return Sample(y: Float(wl) + 0.875, c: rgb(b.info.water), kind: 1)
        }
        // Map colours are the raw biome tints; the blocks' own textures darken them (grass, sand and stone art average
        // about 0.8), so the ring matches the textured ground at the seam.
        var c = rgb(MapCache.shade(b, height: top)) * 0.8
        // P250 (b): the flanks of a terrace. Grass, mycelium, petals and snow over soil show dirt from the side (with
        // a little of the top's fringe); sand, stone, terracotta and peaks are the same material all the way down.
        let soil = !(b.isOcean || b.isRiver || b.isBeach || b == .desert || b.isBadlands || b == .stonyPeaks
                     || b == .windsweptGravellyHills || b.isPeak || b == .iceSpikes)
        var side = soil ? simd_mix(dirt, c, V3(repeating: 0.25)) : c * 0.92
        // Cliffs and steep mountain faces are bare rock, as the generator places them (WorldGen.surface: a rise of 7
        // over two blocks anywhere but badlands and sand, 4 in the mountain biomes), instead of green slopes. k.slope is
        // the smooth pre-erosion slope (over 3 blocks, on a 4-block grid), gentler than the blocks' local rise, so the
        // thresholds sit lower: 2 anywhere, 1.3 in the mountain biomes, 1.2 for a bank's rock walls.
        let mountain: Bool
        switch b {
        case .windsweptHills, .windsweptForest, .stonyPeaks, .jaggedPeaks, .frozenPeaks, .grove, .snowySlopes: mountain = true
        default: mountain = false
        }
        if k.slope >= 2 && !b.isBadlands && b != .desert && !b.isBeach || k.slope >= 1.3 && mountain {
            c = rock; side = rock * 0.92
        } else {
            if k.slope >= 1.2 && soil { side = rock * 0.95 }        // a steep bank: the terrace walls cut into rock
            // Snow on the ground (steep rock faces shed it, as in the freeze); snowy grass shows dirt under a white rim.
            if cold(top) {
                c = snow
                if soil { side = simd_mix(side, snow, V3(repeating: 0.3)) }
            }
        }
        let vw: Float = k.vol > 0.05 ? min(1, k.vol * 3) : 0
        let rw: Float = max(0, vw * 2 - 1)
        if rw > 0 {                                                                 // volcano rock (HorizonRing)
            c = simd_mix(c, V3(0.2, 0.19, 0.19), V3(repeating: rw)); side = simd_mix(side, V3(0.2, 0.19, 0.19), V3(repeating: rw))
        }
        // P250 (b, c): woods stand as their canopy, in leaf colours (a forest was a bare green slope past the chunks,
        // and the trees stopped at the loaded edge).
        let w = canopy(gen, b, x, z, ground: k.h)
        c = simd_mix(c, w.leaf, V3(repeating: w.cover * (1 - rw)))
        side = simd_mix(side, w.leaf * 0.9, V3(repeating: w.cover * (1 - rw)))     // a wood's terrace walls are leaves
        return Sample(y: Float(YOFF) + k.h + 1 + w.height * (1 - rw), c: c, kind: 0, side: side)
    }

    // P250: a column's woods as seen from afar: how much of the ground the crowns cover (0 ... 1), how far the canopy's
    // top stands over the ground where it does, and the leaves' colour. From the tree pass's own odds per biome
    // (TreePlacer: one candidate every 3x3 blocks, a crown about 5x5) and its glades, so a wood far off covers what the
    // chunks grow there.
    static func canopy(_ gen: WorldGen, _ b: Biome, _ x: Int, _ z: Int, ground: Float) -> (cover: Float, height: Float, leaf: V3) {
        func rgb(_ v: UInt32) -> V3 { V3(Float((v >> 16) & 255), Float((v >> 8) & 255), Float(v & 255)) / 255 }
        var p: Float = 0, h: Float = 0
        var leaf = rgb(b.info.foliage)
        switch b {
        case .forest: p = 0.35; h = 7
        case .flowerForest: p = 0.16; h = 7
        case .birchForest: p = 0.35; h = 7; leaf = rgb(0x80A755)
        case .oldGrowthBirchForest: p = 0.35; h = 11; leaf = rgb(0x80A755)
        case .darkForest: p = 0.62; h = 8
        case .taiga, .snowyTaiga, .grove: p = b == .grove ? 0.3 : 0.35; h = 9; leaf = rgb(0x619961)
        case .windsweptForest: p = 0.15; h = 8
        case .oldGrowthPineTaiga, .oldGrowthSpruceTaiga: p = 0.35; h = 14; leaf = rgb(0x619961)
        case .savanna, .windsweptSavanna: p = 0.05; h = 7
        case .savannaPlateau: p = 0.07; h = 7
        case .jungle: p = 0.7; h = 12
        case .sparseJungle: p = 0.1; h = 9
        case .bambooJungle: p = 0.35; h = 9
        case .woodedBadlands: p = ground > 94 ? 0.15 : 0; h = 5
        case .cherryGrove: p = 0.18; h = 8; leaf = rgb(0xE7A8C7)
        case .paleGarden: p = 0.32; h = 9; leaf = rgb(0xA3ABA0)
        case .swamp: p = 0.07; h = 7
        case .mangroveSwamp: p = 0.35; h = 9
        default: return (0, 0, leaf)
        }
        let glade = gen.flora.noise2(Float(x) / 70 + 300, Float(z) / 70)
        let odds = min(0.7, p * max(0.3, 0.8 + 0.9 * glade))
        let cover = 1 - expf(-odds * 25 / 9)
        // Snow on the conifers of the cold woods; leaf art is darker than its tint (holes, shading).
        if b == .snowyTaiga || b == .grove { leaf = simd_mix(leaf, V3(0.93, 0.95, 0.97), V3(repeating: 0.45)) }
        return (cover, h * min(1, cover * 1.4), leaf * 0.62)
    }
    static let dirt = V3(0.525, 0.376, 0.263) * 0.8        // the dirt texture's average, darkened like the map colours
    static let rock = V3(0.6, 0.6, 0.59) * 0.8             // stone (0x9A9A96, the map's peak colour)
    static let snow = V3(0.93, 0.95, 0.96) * 0.92          // snow (0xEEF2F6; its art is brighter than grass or stone)
    static let ice = V3(0.62, 0.76, 0.95) * 0.8            // ice

    // The quads, band by band (squares round the centre, 8 / 16 / 32 blocks apart), cut to a disc of `outer` and with
    // the cells deep inside the loaded disc (whatever the player's offset from the centre within the cell) left out.
    // P229 (Oct 13 21:44, "the far chunks must still look like blocks from a distance"): in a block world each cell is a
    // flat-topped column at a whole-block height with straight sides down to its lower neighbours, a terraced, blocky
    // skyline; Polygons (Smooth) worlds keep the smooth height field.
    static func build(_ gen: WorldGen, cx: Int, cz: Int, rin: Float, memo: inout [Int64: Sample], blocky: Bool = false) -> [SimpleVert] {
        func a32(_ v: Float) -> Int { (Int(v.rounded(.up)) + 31) / 32 * 32 }
        let e0 = a32(rin + 64)
        let e1 = max(e0 + 128, a32(rin + 320), 640)
        let e2 = a32(FarRing.outer)
        let edges = [e0, e1, max(e2, e1 + 64)]
        // The player is within 64 blocks (each axis) of the centre: cells within rin - 91 are always under chunks. P250
        // (c): the ring reaches in to 55% of the loaded radius anyway, so when the governor lowers the distance and the
        // outer chunks unload before the next ring is built, the old ring still covers the gap (24 -> 14 is 0.58).
        let skip: Float = min(rin - 100, rin * 0.55)
        let rim: Float = FarRing.outer
        func S(_ x: Int, _ z: Int) -> Sample {
            let key = (Int64(x) << 32) | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: z)))
            if let s = memo[key] { return s }
            let s = sample(gen, x, z)
            memo[key] = s
            return s
        }
        var out: [SimpleVert] = []
        out.reserveCapacity(blocky ? 160_000 : 64_000)
        let up: Float = 512 + 512 * 1024                                   // normal (0, 1, 0)
        func nq(_ nx: Float, _ nz: Float) -> Float { ((nx * 0.5 + 0.5) * 1023).rounded() + ((nz * 0.5 + 0.5) * 1023).rounded() * 1024 }
        // A cell's column top: the sample at its centre, floored to a whole block (water and lava keep their surface).
        func top(_ x: Int, _ z: Int, _ s: Int) -> Sample {
            var smp = S(cx + x + s / 2, cz + z + s / 2)
            if smp.kind == 0 { smp.y = smp.y.rounded(.down) }
            return smp
        }
        func column(_ x0: Int, _ z0: Int, _ s: Int, _ out: inout [SimpleVert]) {
            let t = top(x0, z0, s)
            let fx0 = Float(x0), fz0 = Float(z0), fx1 = Float(x0 + s), fz1 = Float(z0 + s)
            let c = V4(t.c, t.kind)
            out.append(SimpleVert(pos: V4(fx0, t.y, fz0, up), color: c)); out.append(SimpleVert(pos: V4(fx1, t.y, fz0, up), color: c))
            out.append(SimpleVert(pos: V4(fx1, t.y, fz1, up), color: c)); out.append(SimpleVert(pos: V4(fx0, t.y, fz1, up), color: c))
            guard t.kind == 0 else { return }
            // Sides down to each lower neighbour (2 blocks further, so a coarser neighbour never leaves a slit), in the
            // column's flank colour (dirt under grass, rock on cliffs).
            let side = V4(t.side, 0)
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nb = top(x0 + dx * s, z0 + dz * s, s)
                guard nb.y < t.y else { continue }
                let lo = nb.y - 2
                let q = nq(Float(dx), Float(dz))
                let (ax, az, bx, bz): (Float, Float, Float, Float)
                switch (dx, dz) {
                case (1, 0): (ax, az, bx, bz) = (fx1, fz1, fx1, fz0)
                case (-1, 0): (ax, az, bx, bz) = (fx0, fz0, fx0, fz1)
                case (0, 1): (ax, az, bx, bz) = (fx0, fz1, fx1, fz1)
                default: (ax, az, bx, bz) = (fx1, fz0, fx0, fz0)
                }
                out.append(SimpleVert(pos: V4(ax, t.y, az, q), color: side)); out.append(SimpleVert(pos: V4(bx, t.y, bz, q), color: side))
                out.append(SimpleVert(pos: V4(bx, lo, bz, q), color: side)); out.append(SimpleVert(pos: V4(ax, lo, az, q), color: side))
            }
        }
        for (band, s) in spacings.enumerated() {
            let e = edges[band], ein = band == 0 ? 0 : edges[band - 1]
            let n = e / s
            let coarse = 2 * s
            // Height at a band vertex: on the band's outer square edge, a vertex between two of the next band's
            // vertices takes the mean of its neighbours along the edge, so it lies on the coarser band's edge (no cracks).
            // PG3: the real silhouette. A coarse vertex alone misses a peak or ridge between vertices, so the far
            // skyline sagged; a vertex is pulled most of the way up to the highest ground on the 8-block grid within
            // half its spacing. Vertices on a band's inner or outer square (shared with the next band) look only 8
            // blocks round, the same from both bands, so the seams still meet.
            func peaked(_ ox: Int, _ oz: Int, _ r: Int) -> Sample {
                var smp = S(cx + ox, cz + oz)
                guard !blocky && smp.kind == 0 else { return smp }
                var peak = smp.y
                for dz in stride(from: -r, through: r, by: 8) { for dx in stride(from: -r, through: r, by: 8) where dx != 0 || dz != 0 {
                    let q = S(cx + ox + dx, cz + oz + dz)
                    if q.kind == 0 { peak = max(peak, q.y) }
                } }
                smp.y += (peak - smp.y) * 0.6
                return smp
            }
            let rWide = max(8, s / 2)
            func ring(_ ox: Int, _ oz: Int) -> Bool { abs(ox) == e || abs(oz) == e || (band > 0 && (abs(ox) == ein || abs(oz) == ein)) }
            func height(_ ox: Int, _ oz: Int) -> Sample {
                let edge = ring(ox, oz)
                var smp = peaked(ox, oz, edge ? 8 : rWide)
                guard band < spacings.count - 1 else { return smp }
                if abs(ox) == e && oz % coarse != 0 {
                    let a = peaked(ox, oz - s, 8), b = peaked(ox, oz + s, 8)
                    smp.y = (a.y + b.y) * 0.5
                } else if abs(oz) == e && ox % coarse != 0 {
                    let a = peaked(ox - s, oz, 8), b = peaked(ox + s, oz, 8)
                    smp.y = (a.y + b.y) * 0.5
                }
                return smp
            }
            func vert(_ ox: Int, _ oz: Int) -> SimpleVert {
                let smp = height(ox, oz)
                var nx: Float = 0, nz: Float = 0
                if smp.kind == 0 {
                    let hx0 = S(cx + ox - s, cz + oz), hx1 = S(cx + ox + s, cz + oz)
                    let hz0 = S(cx + ox, cz + oz - s), hz1 = S(cx + ox, cz + oz + s)
                    let gx: Float = hx0.y - hx1.y, gz: Float = hz0.y - hz1.y
                    let nv = simd_normalize(V3(gx, Float(2 * s), gz))
                    nx = nv.x; nz = nv.z
                }
                let qx: Float = ((nx * 0.5 + 0.5) * 1023).rounded()
                let qz: Float = ((nz * 0.5 + 0.5) * 1023).rounded()
                return SimpleVert(pos: V4(Float(ox), smp.y, Float(oz), qx + qz * 1024), color: V4(smp.c, smp.kind))
            }
            for j in -n..<n {
                for i in -n..<n {
                    let x0 = i * s, z0 = j * s, x1 = x0 + s, z1 = z0 + s
                    // Inside the finer band's square: drawn there.
                    if band > 0 && x0 >= -ein && x1 <= ein && z0 >= -ein && z1 <= ein { continue }
                    let mx: Float = Float(x0) + Float(s) * 0.5, mz: Float = Float(z0) + Float(s) * 0.5
                    let r: Float = (mx * mx + mz * mz).squareRoot()
                    if r > rim - Float(s) * 0.5 { continue }
                    if band == 0 {
                        let fx: Float = max(abs(Float(x0)), abs(Float(x1))), fz: Float = max(abs(Float(z0)), abs(Float(z1)))
                        if (fx * fx + fz * fz).squareRoot() < skip { continue }
                    }
                    if blocky {
                        column(x0, z0, s, &out)
                    } else {
                        out.append(vert(x0, z0)); out.append(vert(x1, z0)); out.append(vert(x1, z1)); out.append(vert(x0, z1))
                    }
                }
            }
        }
        return out
    }
}
