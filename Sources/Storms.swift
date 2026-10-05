import Foundation
import simd

// Weather that affects the world (STATUS Future ideas #6; session H, docs/status/world-fx.md):
//   wind     one wind vector for everything (ship sails and windage, fire spread, rain and snow drift): it turns
//            slowly over the days, rain and thunder strengthen it and storms gust;
//   sea      in a storm the open sea runs in swells (Waves): ship buoyancy samples them, so hulls roll and pitch, and
//            the wind leans on their sides; the Fancy water shader draws the same swell with whitecaps;
//   floods   Flood.swift (a coarse water-level model);
//   fire     lightning sets fire round what it strikes (dry lightning in dry country too) and Fire.swift carries it
//            downwind; a strike on a ship bursts on its hull;
//   snow     layers pile up while it snows (deeper the longer it snows, drifting unevenly) and melt back afterwards.
final class WorldFX {
    let decals = WearDecals()
    var wear = WearStats()
    var flood = FloodModel()
    var wind = V3(4, 0, 2)
    var storm: Float = 0                // 0 calm ... 1 full gale
    var gust: Float = 0
    var snowDepth: Float = 1            // layers this snowfall may pile to (1...7)
    var snowTimer: Float = 0
    var snowCursor = 0
    var snowChanges = 0                 // block writes by snow (checks)
    var forcedWind: V3? = nil           // tests: a fixed wind
    var smokeTimer: Float = 0
    var stormMs = 0.0, stormWorstMs = 0.0
}

// Storm sea state for the ship physics (set once a frame by the game; read in ShipPhysics).
enum Waves {
    static var amp: Float = 0           // swell height (blocks) on the open sea
    static var dir = V2(1, 0)           // direction the swell runs (the wind's)
    static var t: Float = 0
    private static var openCache: [Int64: Float] = [:]
    static weak var world: World?

    // How exposed the water at a point is: open sea 1, rivers 0.3, other water (lakes) 0.2. Cached per 16 x 16.
    static func open(_ x: Float, _ z: Float) -> Float {
        guard let w = world else { return 0 }
        let cx = Int(floor(x)) >> 4, cz = Int(floor(z)) >> 4
        let key = Int64(cx) << 32 ^ Int64(UInt32(truncatingIfNeeded: cz))
        if let v = openCache[key] { return v }
        let b = w.gen.column(cx * 16 + 8, cz * 16 + 8).biome
        let v: Float = b.isOcean ? 1 : (b.isRiver ? 0.3 : 0.2)
        if openCache.count > 4096 { openCache.removeAll(keepingCapacity: true) }
        openCache[key] = v
        return v
    }

    // Swell height at a point (blocks, about -amp...amp): three travelling waves, 15 and 9 blocks long along the wind
    // and a cross swell.
    static func height(_ x: Float, _ z: Float) -> Float {
        if amp < 0.01 { return 0 }
        let along = x * dir.x + z * dir.y, across = z * dir.x - x * dir.y
        let w1 = sinf(along * 0.42 - t * 1.6)
        let w2 = sinf(along * 0.7 + across * 0.33 - t * 2.3)
        let w3 = sinf(across * 0.55 - t * 1.1 + 1.7)
        return amp * open(x, z) * (0.6 * w1 + 0.3 * w2 + 0.2 * w3)
    }

    // For the water shader: the swell direction in tenths of a degree (the quantum stormTick snaps it to) plus the
    // sea state (0...0.99) in the fraction.
    static var shaderParam: Float {
        if amp < 0.01 { return 0 }
        var deg = atan2f(dir.y, dir.x) * 180 / .pi
        if deg < 0 { deg += 360 }
        return (deg * 10).rounded() + min(0.99, amp / 1.4)
    }
}

extension Game {
    // Once a frame from weatherTick: wind, sea state, floods, storm audio cues.
    func stormTick(_ dt: Float) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let w = weather
        let target = wetWorld ? min(1, 0.4 * w.rain + 0.6 * w.thunder) : 0
        fx.storm += (target - fx.storm) * min(1, dt * 0.1)
        // Wind turns slowly over the days (as the ship sails always had it); rain and thunder strengthen it, storms gust.
        let tt = Float(time.truncatingRemainder(dividingBy: 86_400))
        let a = Float((time / 900).truncatingRemainder(dividingBy: 2 * .pi)) + Float(world.seed % 628) / 100
        let g = 0.5 + 0.5 * sinf(tt * 0.9 + 2.5 * sinf(tt * 0.23))      // 0...1, gusts every few seconds
        fx.gust = g * fx.storm
        // (Below the sky - the Emberdeep, the Hollow - only a steady draught: the overworld's weather doesn't reach.)
        let strength: Float = wetWorld ? 5 + 4 * w.rain + 5 * w.thunder + fx.gust * 8 : 3
        fx.wind = fx.forcedWind ?? V3(cosf(a), 0, sinf(a)) * strength
        world.wind = fx.wind
        if world.onGlassHeat == nil {
            world.onGlassHeat = { [weak self] p in
                guard let self else { return }
                let b = self.world.block(p.x, p.y, p.z)
                // Panes (not full cubes, so no crack stages): a third of the time the heat breaks them outright.
                if Blocks.render[Int(b)] != RenderType.cube.rawValue {
                    if Rand.int(in: 0..<3) == 0 { self.shatterGlass(p, from: V3(0, 1, 0)) }
                } else {
                    self.wearHit(p, level: self.world.damageLevel(p) + 1, normal: IVec3(0, 1, 0), async: true)
                }
            }
        }
        ParticleManager.drift = fx.wind * (0.08 + 0.3 * fx.storm)
        // The sea: swells build with the storm on open water.
        let hw = V2(fx.wind.x, fx.wind.z)
        if simd_length(hw) > 0.01 {
            // Quantized to 0.1 degree: the shader gets the same direction (dimTint.w), so hulls ride the drawn crests.
            var deg = atan2f(hw.y, hw.x) * 180 / .pi
            if deg < 0 { deg += 360 }
            let q = (deg * 10).rounded() / 10 * .pi / 180
            Waves.dir = V2(cosf(q), sinf(q))
        }
        Waves.amp = fx.storm * 1.3
        Waves.t = Float(time.truncatingRemainder(dividingBy: 1000))     // the water shader's clock (params.z): ships ride the crests drawn
        Waves.world = world
        fx.flood.update(dt, game: self)
        fireSmoke(dt)
        // Gusts howl in a storm (open ground only).
        if fx.storm > 0.3 && wetWorld && Rand.float(in: 0..<1) < dt * fx.storm * 0.25,
           skyExposed(Int(floor(player.pos.x)), Int(floor(player.pos.y + 1)), Int(floor(player.pos.z))) {
            let off = V3(-fx.wind.x, 2, -fx.wind.z) * 0.6
            sfx(.windGust, 0.4 + 0.5 * fx.storm, at: player.eye + off)
        }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        fx.stormMs = ms
        fx.stormWorstMs = max(fx.stormWorstMs, ms)
    }

    // Big fires send up plumes seen from afar (the ambient sampler only reaches 16 blocks): a few large dark puffs a
    // second from random burning cells within 128 blocks, more for bigger fires, leaning with the wind.
    func fireSmoke(_ dt: Float) {
        let fires = world.fires
        if fires.isEmpty || particles.list.count > ParticleManager.cap - 300 { return }
        fx.smokeTimer -= dt
        if fx.smokeTimer > 0 { return }
        fx.smokeTimer = max(0.04, 0.5 / Float(min(12, 1 + fires.count / 8)))
        guard let (p, _) = fires.pick() else { return }          // through Rand (replayable)
        let c = V3(Float(p.x) + 0.5, Float(p.y) + 1.2, Float(p.z) + 0.5)
        let d = simd_length(c - player.pos)
        if d > 128 || d < 6 { return }
        let g: Float = Rand.float(in: 0.1...0.22)
        particles.add(Particle(pos: c + V3(Rand.float(in: -0.5...0.5), 0, Rand.float(in: -0.5...0.5)),
                               vel: V3(0, Rand.float(in: 1.5...2.5), 0), life: Rand.float(in: 4...7), maxLife: 7,
                               layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 0.9...1.8),
                               gravity: -0.4, color: V3(g, g, g), collide: false))
    }

    // A storm's lightning picks the tallest point among a few nearby columns (trees, towers, masts).
    func lightningTarget(near x: Int, _ z: Int) -> (Int, Int) {
        var best = (x, z), top = world.topY(x, z)
        for _ in 0..<4 {
            let cx = x + Rand.int(in: -6...6), cz = z + Rand.int(in: -6...6)
            let y = world.topY(cx, cz)
            if y > top { top = y; best = (cx, cz) }
        }
        return best
    }

    // Fire round a strike: the struck block's open sides catch when it (or what it touches) burns; wood scorches.
    func lightningFires(_ at: V3) {
        let b = IVec3(Int(floor(at.x)), Int(floor(at.y)) - 1, Int(floor(at.z)))
        let struck = world.block(b.x, b.y, b.z)
        if Wear.kind[Int(struck)] == .wood { world.addScorch(b, to: 2) }
        guard Blocks.flammable[Int(struck)] else { return }
        var lit = 0
        for d in World.allDirs where lit < 4 {
            let q = b + d
            if world.block(q.x, q.y, q.z) == AIR && world.fires.count < World.fireCap { world.placeFire(q); lit += 1 }
        }
    }

    // A strike that lands on a ship's hull: a small burst that chips plating (ShipCombat).
    func lightningOnShips(_ at: V3) -> Bool {
        for s in world.ships.list where s.parent == nil {
            if at.x >= s.worldMin.x - 0.5 && at.x <= s.worldMax.x + 0.5 && at.z >= s.worldMin.z - 0.5 && at.z <= s.worldMax.z + 0.5
                && at.y <= s.worldMax.y + 40 {
                let top = V3(at.x, s.worldMax.y + 0.5, at.z)
                world.ships.blast(at: top, power: 1.6, game: self)
                return true
            }
        }
        return false
    }

    // MARK: Snow

    static let snowLayerIDs: [BlockID] = [AIR, Blocks.id("snow")] + (2...7).map { Blocks.id("snow_layers_\($0)") }

    @inline(__always) func snowLayers(_ id: BlockID) -> Int {
        if id == AIR { return 0 }
        if id == Game.snowLayerIDs[1] { return 1 }
        let base = Blocks.groupBase[Int(id)]
        if base == Game.snowLayerIDs[2] { return 2 + Int(id - base) }
        return -1
    }

    // 20 Hz: snow piles up while it snows and melts after, a whole chunk at a time (one remesh per chunk) cycling
    // through the chunks round the player about every 25 s.
    func snowTick(_ dt: Float) {
        guard wetWorld else { return }
        let snowing = weather.rain > 0.5
        // How deep this snowfall may get: about a layer every 40 s of heavy snow, settling back after.
        if snowing { fx.snowDepth = min(7, fx.snowDepth + dt * weather.rain / 40) }
        else { fx.snowDepth = max(1, fx.snowDepth - dt / 60) }
        fx.snowTimer += dt
        let r = min(6, world.renderDistance)
        let side = 2 * r + 1
        let perChunk: Float = 25 / Float(side * side)
        while fx.snowTimer >= perChunk {
            fx.snowTimer -= perChunk
            let i = fx.snowCursor % (side * side)
            fx.snowCursor = (fx.snowCursor + 1) % (side * side)
            let pcx = floorDiv(Int(floor(player.pos.x)), CS), pcz = floorDiv(Int(floor(player.pos.z)), CS)
            if let c = world.chunks[ChunkKey(x: pcx + i % side - r, z: pcz + i / side - r)] { snowChunk(c, snowing: snowing) }
        }
    }

    // Smooth value noise in 0...1 on a 7-block lattice (snow drift depth).
    static func driftNoise(_ x: Int, _ z: Int) -> Float {
        let fx = Float(x) / 7, fz = Float(z) / 7
        let x0 = Int(floorf(fx)), z0 = Int(floorf(fz))
        let tx = fx - Float(x0), tz = fz - Float(z0)
        let sx = tx * tx * (3 - 2 * tx), sz = tz * tz * (3 - 2 * tz)
        let a = hashf(x0, 0, z0, 0x5D0), b = hashf(x0 + 1, 0, z0, 0x5D0)
        let c = hashf(x0, 0, z0 + 1, 0x5D0), d = hashf(x0 + 1, 0, z0 + 1, 0x5D0)
        let top = a + (b - a) * sx, bottom = c + (d - c) * sx
        return top + (bottom - top) * sz
    }

    static let leavesT: [Bool] = (0..<Blocks.count).map { Blocks.key(Blocks.groupBase[$0]).hasSuffix("_leaves") }
    // Blocks snow settles on: solid cubes, leaves, and anything with a full top face (glass, top slabs, upside-down
    // stairs); not ice (it melts through) or barriers.
    static let snowBaseT: [Bool] = (0..<Blocks.count).map { i in
        if Blocks.opaque[i] || leavesT[i] { return true }
        let k = Blocks.key(Blocks.groupBase[i])
        if ["ice", "packed_ice", "blue_ice", "barrier", "frosted_ice"].contains(k) || Blocks.isLiquid(BlockID(i)) { return false }
        if Blocks.render[i] == RenderType.cube.rawValue && Blocks.fullCollide[i] { return true }
        return Blocks.boxes[i].contains { $0.x0 == 0 && $0.z0 == 0 && $0.x1 == 16 && $0.z1 == 16 && $0.y1 == 16 }
    }

    func snowChunk(_ c: Chunk, snowing: Bool) {
        let day = daylight
        // Biomes per 4 x 4 columns (the climate lookup is the expensive part of a pass: 13.7 ms worst at 256 a chunk).
        var biomes = [Biome?](repeating: nil, count: 16)
        var writes: [(Int, Int, Int, BlockID)] = []
        // Columns someone stands in: the snow doesn't grow into a solid height under them (layers 3+ collide; a pile
        // growing under a standing player or mob embedded its feet: code review).
        var occupied = Set<Int>()
        if snowing {
            let x0 = Float(c.cx * CS), z0 = Float(c.cz * CS)
            func mark(_ p: V3, _ hw: Float) {
                guard p.x > x0 - 2 && p.x < x0 + 18 && p.z > z0 - 2 && p.z < z0 + 18 else { return }
                for x in Int(floor(p.x - hw))...Int(floor(p.x + hw)) { for z in Int(floor(p.z - hw))...Int(floor(p.z + hw)) {
                    let lx = x - c.cx * CS, lz = z - c.cz * CS
                    if lx >= 0 && lx < CS && lz >= 0 && lz < CS { occupied.insert(lx + lz * CS) }
                } }
            }
            mark(player.pos, 0.3)
            for m in mobs.mobs { mark(m.pos, m.spec.halfW) }
        }
        for lz in 0..<CS { for lx in 0..<CS {
            let x = c.cx * CS + lx, z = c.cz * CS + lz
            var y = Int(c.height[lx + lz * CS])          // snow layers don't stop the sky: the block they lie on
            guard y > 0 && y < CH - 2 else { continue }
            // Glass (and other see-through solids) doesn't stop the sky column but does stop the snow: it settles on
            // the highest solid block above (it piled up on floors under glass roofs).
            // (Not its own deeper layers, which collide; only up to the chunk's highest stored block.)
            var yy = y + 2
            let scanTop = min(CH - 2, y + 40, c.blocks.storedCount / CSQ)
            while yy < scanTop {
                let b = c.blocks[Chunk.index(lx, yy, lz)]
                if Blocks.collide[Int(b)] && snowLayers(b) < 0 { y = yy }
                yy += 1
            }
            let cur = snowLayers(world.rawBlock(x, y + 1, z))
            if cur < 0 || (cur == 0 && !snowing) { continue }
            let top = world.rawBlock(x, y, z)
            let bi = (lx >> 2) + (lz >> 2) * 4
            let biome: Biome
            if let b = biomes[bi] { biome = b } else { biome = world.gen.column(c.cx * CS + (lx & ~3) + 2, c.cz * CS + (lz & ~3) + 2).biome; biomes[bi] = biome }
            let snowsHere = biome.snows(at: y)
            let light = world.lightAt(x, y + 1, z).block
            // Drifts: smooth over ~7 blocks (per-column randomness left 10 px steps between neighbours to jump), leaves
            // hold a single layer.
            let drift = Game.driftNoise(x, z)
            let leaves = Game.leavesT[Int(top)]
            var want = cur
            if snowing && snowsHere && light < 10 {
                guard cur > 0 || Game.snowBaseT[Int(top)] else { continue }
                let cap = leaves ? 1 : max(1, min(7, Int(fx.snowDepth * (0.55 + 0.9 * drift))))
                if cur < cap && Rand.float(in: 0..<1) < 0.6 && !(cur >= 2 && occupied.contains(lx + lz * CS)) { want = cur + 1 }
            } else if cur > 0 {
                // Melting: torches and lamps melt it all; otherwise the extra layers settle back as the snowfall's depth
                // falls (faster under the sun), down to the single layer snowy country keeps.
                let keep = light >= 12 ? 0 : max(1, min(7, Int(fx.snowDepth * (0.55 + 0.9 * drift))))
                let rate: Float = light >= 12 ? 1 : 0.15 + 0.35 * day
                if cur > keep && Rand.float(in: 0..<1) < rate { want = cur - 1 }
            }
            if want != cur {
                writes.append((lx, y + 1, lz, Game.snowLayerIDs[want]))
                fx.snowChanges += 1
            }
        } }
        world.bulkSet(c, writes)
    }
}

extension Game {
    // F3 line: wind, storm, fire, flood, damage (session H's systems at a glance).
    func worldFXDebugLine() -> String {
        let f = world.fireStats, fl = fx.flood
        return String(format: "Wind %.1f b/s  Storm %.2f  Swell %.2f  Fire %ld (%.2f ms)  Flood %ld blocks, %ld cells (%.2f ms)  Wear %ld/%ld",
                      simd_length(fx.wind), fx.storm, Waves.amp, f.burning, f.lastMs, fl.placed.count, fl.floodedCells, fl.lastMs,
                      world.damage.count, world.scorch.count)
    }
}

extension World {
    // Many writes inside one chunk (a snow pass): blocks, heights and wear cleared directly, then each touched section
    // (and the neighbours' sections next to an edge column) bumped once - no per-block redstone, gravity or remesh
    // bookkeeping. Only for blocks that don't fall, power or light anything (snow layers).
    func bulkSet(_ c: Chunk, _ writes: [(Int, Int, Int, BlockID)]) {
        if writes.isEmpty { return }
        var lo = CH, hi = 0
        var edgeX = [false, false], edgeZ = [false, false]
        for (lx, y, lz, id) in writes {
            guard y >= 0 && y < CH else { continue }
            c.blocks[Chunk.index(lx, y, lz)] = id
            c.recomputeHeight(lx, lz)
            if !damage.isEmpty || !scorch.isEmpty { clearWear(IVec3(c.cx * CS + lx, y, c.cz * CS + lz)) }
            lo = min(lo, y); hi = max(hi, y)
            if lx == 0 { edgeX[0] = true } else if lx == CS - 1 { edgeX[1] = true }
            if lz == 0 { edgeZ[0] = true } else if lz == CS - 1 { edgeZ[1] = true }
        }
        guard lo <= hi else { return }
        c.modified = true
        let s0 = max(0, (lo - 1) >> 4), s1 = min(NSEC - 1, (hi + 1) >> 4)
        for dz in -1...1 { for dx in -1...1 {
            if dx == -1 && !edgeX[0] || dx == 1 && !edgeX[1] || dz == -1 && !edgeZ[0] || dz == 1 && !edgeZ[1] { continue }
            guard let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)] else { continue }
            for sy in s0...s1 { n.sections[sy].version += 1 }
        } }
    }
}

extension Game {
    // Daylight from the sun alone (no overcast, no lightning): what the stars follow. Rain clouds hide them on top
    // (the overcast-dimmed daylight let them shine through a thunderstorm at noon: fx_wildfire, run 516).
    var clearSkyDaylight: Float {
        if !dim.dim.hasSky { return daylight }
        let t = simd_clamp((sunDir.y + 0.12) / 0.4, 0, 1)
        return 0.12 + 0.88 * t * t * (3 - 2 * t)
    }
}
