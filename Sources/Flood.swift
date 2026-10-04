import Foundation
import simd

// Rain that floods low ground and swells rivers (STATUS Future ideas #6; session H, docs/status/world-fx.md).
// Per-block water flow at landscape scale is far too expensive, so this is a coarse water-level model: a 64 x 64 grid
// of 4 x 4-block cells round the player (+-128 blocks). Each cell knows its lowest ground, any natural water surface
// (river, lake: its base level) and whether it is open sea (a sink held at sea level). Rain adds depth, the soil soaks
// up the first half block (then everything runs off), water flows between neighbouring cells by level difference
// (rivers carry it down to the sea), and evaporation and drying soil take it back when the rain stops.
// The model writes its level into the world as `flood_water` sources (a water block of its own, so a flood saved
// mid-storm is still recognised and recedes after a reload), filling each column above its ground up to the cell's
// level, a bounded number of blocks per update, and takes them away again top-down as the level falls.
final class FloodModel {
    static let cellSize = 4
    static let n = 64
    static let updateEvery: Float = 0.5        // seconds of game time per model step
    static let blockBudget = 320               // block writes per step
    // Rates (blocks of water per second at full rain): exaggerated so a storm floods in minutes, not days.
    static let rainRate: Float = 0.0012
    static let soak: Float = 0.004             // what dry soil takes in, falling as it saturates
    static let soilCap: Float = 0.5            // blocks of water the soil holds
    static let evap: Float = 0.0015
    static let flowK: Float = 0.45             // share of a level difference passed per second

    let N = FloodModel.n
    var ox = Int.min, oz = Int.min             // world corner of cell (0, 0)
    var ground: [Float]                         // lowest ground surface in the cell (top of the floor block)
    var nat: [Float]                            // natural water surface, -1 none
    var sink: [Bool]
    var rains: [Bool]                           // precipitation here is rain (not snow, not a dry biome)
    var h: [Float]                              // flood depth above the base level
    var wet: [Float]                            // water the soil holds
    var known: [Bool]
    var fillTop: [Int]                          // world y the cell's columns are filled below (exclusive), 0 none
    var flow: [Float]                           // scratch
    var placed = Set<IVec3>()
    var timer: Float = 0
    var sampleCursor = 0
    var refreshCursor = 0
    // Stats for checks and the benchmark.
    var lastMs = 0.0, worstMs = 0.0
    var peakPlaced = 0
    var writes = 0
    var forcedRain: Float? = nil                // tests: rain intensity regardless of the weather

    static let flood: BlockID = Blocks.id("flood_water")
    static let edge: BlockID = Blocks.id("flood_water_edge")
    @inline(__always) static func isFlood(_ b: BlockID) -> Bool { b == flood || b == edge }
    // Cells a column scan passes through to find the ground: air, fluids, plants, leaves, snow layers, fire.
    static let passT: [Bool] = {
        var t = [Bool](repeating: false, count: Blocks.count)
        for i in 0..<Blocks.count {
            let k = Blocks.key(Blocks.groupBase[i])
            t[i] = i == 0 || Blocks.isLiquid(BlockID(i)) || !Blocks.collide[i] || k.hasSuffix("_leaves") || k.hasPrefix("snow_layers") || k == "snow"
        }
        return t
    }()

    init() {
        let c = FloodModel.n * FloodModel.n
        ground = [Float](repeating: 0, count: c); nat = [Float](repeating: -1, count: c)
        sink = [Bool](repeating: false, count: c); rains = [Bool](repeating: false, count: c)
        h = [Float](repeating: 0, count: c); wet = [Float](repeating: 0, count: c)
        known = [Bool](repeating: false, count: c); fillTop = [Int](repeating: 0, count: c)
        flow = [Float](repeating: 0, count: c)
    }

    var floodedCells: Int { var k = 0; for i in 0..<(N * N) where fillTop[i] > 0 { k += 1 }; return k }
    var maxDepth: Float {
        var m: Float = 0
        for i in 0..<(N * N) where known[i] && !sink[i] { m = max(m, h[i]) }
        return m
    }

    // MARK: Window

    // Keeps the player inside the middle half of the window; cells that scroll out take their water with them.
    private func recentre(_ g: Game) {
        let cs = FloodModel.cellSize
        let px = Int(floor(g.player.pos.x)), pz = Int(floor(g.player.pos.z))
        let span = N * cs
        let wantX = floorDiv(px - span / 2, 64) * 64, wantZ = floorDiv(pz - span / 2, 64) * 64
        if ox != Int.min && abs(px - (ox + span / 2)) < span / 4 && abs(pz - (oz + span / 2)) < span / 4 { return }
        if ox == wantX && oz == wantZ { return }
        let dx = ox == Int.min ? N : (wantX - ox) / cs, dz = oz == Int.min ? N : (wantZ - oz) / cs
        func shifted<T>(_ a: [T], _ empty: T) -> [T] {
            var out = [T](repeating: empty, count: N * N)
            for j in 0..<N { for i in 0..<N {
                let si = i + dx, sj = j + dz
                if si >= 0 && si < N && sj >= 0 && sj < N { out[i + j * N] = a[si + sj * N] }
            } }
            return out
        }
        // Water in cells leaving the window drains away.
        if ox != Int.min {
            for j in 0..<N { for i in 0..<N {
                let ni = i - dx, nj = j - dz
                if ni >= 0 && ni < N && nj >= 0 && nj < N { continue }
                let k = i + j * N
                if fillTop[k] > 0 { drain(g.world, cell: k, to: 0, budget: Int.max) }
            } }
        }
        ground = shifted(ground, 0); nat = shifted(nat, -1); sink = shifted(sink, false); rains = shifted(rains, false)
        h = shifted(h, 0); wet = shifted(wet, 0); known = shifted(known, false); fillTop = shifted(fillTop, 0)
        ox = wantX; oz = wantZ
    }

    // MARK: Sampling

    // Ground, natural water and sea for one cell from its 16 columns (flood water counts as air).
    private func sample(_ g: Game, _ k: Int) -> Bool {
        let w = g.world
        let cs = FloodModel.cellSize
        let x0 = ox + (k % N) * cs, z0 = oz + (k / N) * cs
        guard w.chunkAt(x0, z0) != nil, w.chunkAt(x0 + cs - 1, z0 + cs - 1) != nil else { return false }
        let pass = FloodModel.passT
        var gmin = Float.greatestFiniteMagnitude, water = -1, waterCols = 0, ourTop = 0
        for dz in 0..<cs { for dx in 0..<cs {
            let x = x0 + dx, z = z0 + dz
            guard let c = w.chunkAt(x, z) else { return false }
            var y = Int(c.height[mod(x, CS) + mod(z, CS) * CS]) + 1
            var colWater = -1
            while y > 1 {
                let b = w.rawBlock(x, y, z)
                if FloodModel.isFlood(b) { ourTop = max(ourTop, y + 1); y -= 1; continue }
                if !pass[Int(b)] { break }
                if Blocks.fluidKind[Int(b)] == 1 && colWater < 0 { colWater = y }
                y -= 1
            }
            gmin = min(gmin, Float(y + 1))
            if colWater >= 0 { waterCols += 1; water = max(water, colWater) }
        } }
        ground[k] = gmin
        nat[k] = waterCols >= 4 ? Float(water) + 0.875 : -1
        let cx = x0 + cs / 2, cz = z0 + cs / 2
        let biome = w.gen.column(cx, cz).biome
        sink[k] = nat[k] >= 0 && water <= SEA + 1 && biome.isOcean
        rains[k] = g.precipitation(cx, Int(gmin), cz) == 1
        // Flood water already standing here (a save made mid-flood): take it on as depth so it recedes.
        // (Only on a cell's first sample: a refresh must not pump a receding flood back up.)
        if ourTop > 0 && !known[k] {
            fillTop[k] = ourTop
            h[k] = max(h[k], Float(ourTop) - base(k))
            for dz in 0..<cs { for dx in 0..<cs { for y in stride(from: Int(gmin), to: ourTop, by: 1) where FloodModel.isFlood(w.rawBlock(x0 + dx, y, z0 + dz)) {
                placed.insert(IVec3(x0 + dx, y, z0 + dz))
            } } }
        }
        known[k] = true
        return true
    }

    @inline(__always) private func base(_ k: Int) -> Float { nat[k] >= 0 ? max(nat[k], ground[k]) : ground[k] }

    // MARK: Step

    func update(_ dt: Float, game g: Game) {
        guard g.wetWorld else { return }
        timer += dt
        guard timer >= FloodModel.updateEvery else { return }
        let step = timer
        timer = 0
        let rain = forcedRain ?? (g.weather.rain > 0.2 ? g.weather.rain * (1 + 0.5 * g.weather.thunder) : 0)
        // A dry day with no water about (the usual case): only a trickle of sampling (16 new cells a step), enough to
        // find flood water standing in a save made mid-flood, which wakes the model (a flight re-centres the window
        // every few seconds, and 200 column scans a step cost 1-3 ms for nothing).
        let idle = rain <= 0 && placed.isEmpty && !h.contains(where: { $0 > 0 }) && !wet.contains(where: { $0 > 0 })
        let t0 = CFAbsoluteTimeGetCurrent()
        recentre(g)
        // New cells: up to 200 samples a step until the window is known (cells over unloaded chunks wait). Known
        // cells: a slow refresh, 24 a step, so dams and channels dug by the player count (it starved while any
        // cell sat over an unloaded chunk: code review).
        var budget = idle ? 16 : 200, tries = 0
        while budget > 0 && tries < N * N {
            let k = sampleCursor
            sampleCursor = (sampleCursor + 1) % (N * N)
            tries += 1
            if !known[k] && sample(g, k) { budget -= 1 }
        }
        if idle { lastMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000; return }
        var refresh = 24
        tries = 0
        while refresh > 0 && tries < N * N {
            let k = refreshCursor
            refreshCursor = (refreshCursor + 1) % (N * N)
            tries += 1
            if known[k] { _ = sample(g, k); refresh -= 1 }
        }
        simulate(step, rain: rain)
        apply(g.world, budget: FloodModel.blockBudget)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        lastMs = ms
        worstMs = max(worstMs, ms)
        peakPlaced = max(peakPlaced, placed.count)
    }

    // One model step: rain in, soak, evaporate, flow between cells (two half steps), sea cells held at sea level.
    func simulate(_ dt: Float, rain: Float) {
        let NN = N * N
        for k in 0..<NN where known[k] {
            if sink[k] { h[k] = 0; continue }
            if rain > 0 && rains[k] { h[k] += FloodModel.rainRate * rain * dt }
            if nat[k] < 0 {
                // The soil takes water until it holds soilCap; it dries out again slowly.
                let room = max(0, 1 - wet[k] / FloodModel.soilCap)
                let take = min(h[k], FloodModel.soak * room * dt)
                h[k] -= take
                wet[k] = min(FloodModel.soilCap, wet[k] + take)
                if rain <= 0 { wet[k] = max(0, wet[k] - FloodModel.soak * 0.25 * dt) }
            }
            if rain <= 0 { h[k] = max(0, h[k] - FloodModel.evap * dt) }
        }
        let sub = 2
        let hdt = dt / Float(sub)
        for _ in 0..<sub {
            for k in 0..<NN { flow[k] = 0 }
            // Each neighbouring pair once (east and south); water only moves from a cell that has some.
            func pair(_ k: Int, _ m: Int) {
                guard known[m] else { return }
                let d = (base(k) + h[k]) - (base(m) + h[m])
                if d > 0.01 && h[k] > 0 {
                    let q = min(h[k] * 0.24, d * FloodModel.flowK * hdt)
                    flow[k] -= q; flow[m] += q
                } else if d < -0.01 && h[m] > 0 {
                    let q = min(h[m] * 0.24, -d * FloodModel.flowK * hdt)
                    flow[m] -= q; flow[k] += q
                }
            }
            for j in 0..<N { for i in 0..<N {
                let k = i + j * N
                guard known[k] else { continue }
                if i + 1 < N { pair(k, k + 1) }
                if j + 1 < N { pair(k, k + N) }
            } }
            for k in 0..<NN where known[k] {
                h[k] = sink[k] ? 0 : max(0, h[k] + flow[k])
            }
        }
    }

    // MARK: Blocks

    // Target: every column filled from its own ground up to the cell's level (a block counts once the level is past
    // its middle); hysteresis keeps the surface from flickering.
    private func target(_ k: Int) -> Int {
        let level = base(k) + h[k]
        let floorY = Int(ground[k])
        if h[k] < 0.15 { return 0 }
        // The first block once the water is two thirds of a block deep (a thinner sheet is left to the soil and the
        // shader's rain rings), then each block once the level is past its middle.
        let top = Int(floor(level + (h[k] < 1 ? 0.35 : 0.5)))         // filled below this y
        return top > floorY ? top : 0
    }

    func apply(_ w: World, budget: Int) {
        var left = budget
        for k in 0..<(N * N) where known[k] && left > 0 {
            let t = target(k)
            let cur = fillTop[k]
            if t > cur { left -= fill(w, cell: k, to: t, budget: left) }
            else if t < cur - 1 || (t == 0 && cur > 0) { left -= drain(w, cell: k, to: t, budget: left) }
        }
    }

    // Fills the cell's columns up to y (exclusive): air and soft blocks above each column's ground.
    private func fill(_ w: World, cell k: Int, to top: Int, budget: Int) -> Int {
        let cs = FloodModel.cellSize
        let x0 = ox + (k % N) * cs, z0 = oz + (k / N) * cs
        var used = 0
        let from = max(Int(ground[k]), fillTop[k] > 0 ? fillTop[k] : Int(ground[k]))
        for y in stride(from: from, to: top, by: 1) {
            for dz in 0..<cs { for dx in 0..<cs {
                let x = x0 + dx, z = z0 + dz
                let b = w.rawBlock(x, y, z)
                guard b == AIR || (Blocks.replaceable[Int(b)] && !Blocks.isLiquid(b)) else { continue }
                // Only over this column's own ground (water never hangs over a drop inside the cell).
                let below = w.rawBlock(x, y - 1, z)
                guard !FloodModel.passT[Int(below)] || Blocks.fluidKind[Int(below)] == 1 else { continue }
                let id = isShore(w, x, y, z, cell: k) ? FloodModel.edge : FloodModel.flood
                if w.setBlockAsync(x, y, z, id) { placed.insert(IVec3(x, y, z)); used += 1; writes += 1 }
            } }
            fillTop[k] = y + 1
            if used >= budget { return used }
        }
        fillTop[k] = top
        return used
    }

    // A flood block is shoreline when open ground beside it (air or a plant, in another cell) won't be filled at its
    // height: it is placed as the half-height edge state, which the mesher slopes down toward the open side.
    private func isShore(_ w: World, _ x: Int, _ y: Int, _ z: Int, cell k: Int) -> Bool {
        let cs = FloodModel.cellSize
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, nz = z + dz
            let nb = w.rawBlock(nx, y, nz)
            guard nb == AIR || (Blocks.replaceable[Int(nb)] && !Blocks.isLiquid(nb)) else { continue }
            let ci = floorDiv(nx - ox, cs), cj = floorDiv(nz - oz, cs)
            guard ci >= 0 && ci < N && cj >= 0 && cj < N else { return true }
            let m = ci + cj * N
            if m == k { continue }
            if !known[m] || target(m) <= y { return true }
        }
        return false
    }

    // Takes the cell's flood water away from the top down to y (exclusive).
    @discardableResult
    private func drain(_ w: World, cell k: Int, to bottom: Int, budget: Int) -> Int {
        let cs = FloodModel.cellSize
        let x0 = ox + (k % N) * cs, z0 = oz + (k / N) * cs
        var used = 0
        var y = fillTop[k] - 1
        let lowest = max(bottom, Int(ground[k]) - 1)
        while y >= lowest {
            for dz in 0..<cs { for dx in 0..<cs {
                let p = IVec3(x0 + dx, y, z0 + dz)
                guard placed.contains(p) else { continue }
                placed.remove(p)
                if FloodModel.isFlood(w.rawBlock(p.x, p.y, p.z)) {
                    w.setBlockAsync(p.x, p.y, p.z, AIR)
                    used += 1; writes += 1
                }
            } }
            fillTop[k] = y
            y -= 1
            if used >= budget { return used }
        }
        fillTop[k] = bottom
        return used
    }
}
