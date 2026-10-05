import Foundation
import simd

// Checks and shots for material damage and weather (session H, docs/status/world-fx.md):
//   Blocksmith --snapshot snaps/fx.png --fxtest cracks,fire,flood,snow,storm,wildfire [--out snaps]
// Scenes (each one prints PASS / FAIL lines, writes fx_<scene>_*.png and a row of timings to snaps/fxtest.md):
//   cracks  stone, brick, metal, glass and wood at every damage stage on a pad (decals vs chips, glass shatters)
//   fire    a wooden house set alight on its upwind side in a strong wind (spreads downwind, scorches, chars to
//           charcoal, cap and tick cost), lightning on a tree, the burning-cell cap on a plank field
//   flood   heavy rain on a river valley: the coarse model floods the low ground, then the water recedes
//   snow    a snowstorm on the snowy plains: layers pile up unevenly, then melt back
//   storm   a gunboat on the open sea: calm, then a full storm (roll, pitch, still afloat, upright), lightning on it
//   wildfire a dry thunderstorm over the savanna in a gale (lightning fires, cap and tick cost under load)
enum WorldFXTest {
    static var fails = 0
    static var report: [String] = []

    static func check(_ ok: Bool, _ what: String, _ detail: String = "") {
        print("fxtest \(ok ? "PASS" : "FAIL"): \(what)\(detail.isEmpty ? "" : " (\(detail))")")
        report.append("- \(ok ? "PASS" : "**FAIL**"): \(what)\(detail.isEmpty ? "" : " (\(detail))")")
        if !ok { fails += 1 }
    }
    static func note(_ s: String) { print("fxtest: \(s)"); report.append("- \(s)") }

    static func run(_ list: String, game g: Game, renderer r: Renderer, w: Int, h: Int, out: String) -> Int {
        fails = 0
        report = ["# World fx checks (material damage and weather)", ""]
        let scenes = list.split(separator: ",").map(String.init)
        let home = g.player.pos
        PrefsSandbox.begin()                    // chipping is switched on for the checks; the saved options come back after
        defer { PrefsSandbox.end() }
        g.paused = false
        g.player.flying = true
        g.survival = false
        Settings.shared.chipping = true
        for s in scenes {
            report.append("")
            report.append("## \(s)")
            let t0 = CFAbsoluteTimeGetCurrent()
            g.player.pos = home
            switch s {
            case "cracks": cracks(g, r, w, h, out)
            case "fire": fire(g, r, w, h, out)
            case "flood": flood(g, r, w, h, out)
            case "snow": snow(g, r, w, h, out)
            case "storm": storm(g, r, w, h, out)
            case "wildfire": wildfire(g, r, w, h, out)
            default: check(false, "unknown fxtest scene \(s)")
            }
            note(String(format: "scene %@ took %.1f s", s, CFAbsoluteTimeGetCurrent() - t0))
        }
        try? report.joined(separator: "\n").write(toFile: out + "/fxtest.md", atomically: true, encoding: .utf8)
        print("fxtest: \(fails) failed check(s); report \(out)/fxtest.md")
        return fails
    }

    // MARK: Helpers

    static func look(_ g: Game, from p: V3, at q: V3) {
        g.player.pos = p
        let d = q - (p + V3(0, g.player.eye.y - g.player.pos.y, 0))
        g.player.yaw = atan2f(-d.x, -d.z)
        g.player.pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
        g.player.vel = .zero
    }

    // Loads and meshes round the camera, then writes the shot and measures the frame (encode + GPU, median).
    @discardableResult
    static func shot(_ g: Game, _ r: Renderer, _ w: Int, _ h: Int, _ path: String, frames: Int = 0) -> Double {
        _ = g.world.loadSync(center: g.player.pos, radius: g.world.renderDistance)
        g.fx.decals.builtAt = -1e9                  // the harness clock stands still: let the decals rebuild
        _ = r.renderToPNG(path: path, width: w, height: h)
        _ = r.renderToPNG(path: path, width: w, height: h)
        let ms = frames > 0 ? r.medianFrame(frames, width: w, height: h) * 1000 : 0
        print("fxtest: wrote \(path)\(frames > 0 ? String(format: " (frame %.2f ms)", ms) : "")")
        return ms
    }

    static func put(_ wd: World, _ x: Int, _ y: Int, _ z: Int, _ name: String) {
        wd.setBlockAsync(x, y, z, Blocks.has(name) ? Blocks.id(name) : STONE)
    }

    // MARK: cracks

    static func cracks(_ g: Game, _ r: Renderer, _ w: Int, _ h: Int, _ out: String) {
        let wd = g.world
        let x0 = Int(floor(g.player.pos.x)), z0 = Int(floor(g.player.pos.z))
        let y = ShipTest.levelPad(wd, x0, z0, half: 12)
        // Rows (toward -z, facing a camera at +z): stone, bricks, iron, steel plating, glass, oak planks; columns
        // are damage levels 0...7 hit from the camera's side (+z face).
        let rows = ["stone", "bricks", "iron_block", "steel_plating", "glass", "oak_planks"]
        for (ri, name) in rows.enumerated() {
            for k in 0..<8 { put(wd, x0 - 8 + k * 2, y + ri, z0 - 6, name) }
        }
        _ = wd.loadSync(center: g.player.pos, radius: 4)
        for (ri, _) in rows.enumerated() {
            for k in 1..<8 { wd.chip(IVec3(x0 - 8 + k * 2, y + ri, z0 - 6), level: k, face: 4) }
        }
        // Scorch stages and charcoal on a wood row in front.
        for k in 0..<4 { put(wd, x0 - 8 + k * 2, y, z0 - 2, "oak_planks") }
        put(wd, x0, y, z0 - 2, "charcoal_block")
        put(wd, x0 + 2, y, z0 - 2, "smoldering_charcoal")
        _ = wd.loadSync(center: g.player.pos, radius: 4)
        for k in 1..<4 { wd.addScorch(IVec3(x0 - 8 + k * 2, y, z0 - 2), to: k) }

        // Oracles: what meshes chipped and what shows a decal.
        let stone3 = IVec3(x0 - 8 + 3 * 2, y, z0 - 6), stone6 = IVec3(x0 - 8 + 6 * 2, y, z0 - 6)
        check(wd.visualDamage(stone3) == nil, "stone at level 3 is whole (cracks only)")
        check(wd.visualDamage(stone6) != nil, "stone at level 6 is chipped")
        check(wd.visualDamage(IVec3(x0 - 8 + 7 * 2, y + 2, z0 - 6)) == nil, "iron never chips (dents)")
        check(wd.visualDamage(IVec3(x0 - 8 + 7 * 2, y + 3, z0 - 6)) == nil, "steel plating never chips (dents)")
        check(wd.visualDamage(IVec3(x0 - 8 + 5 * 2, y + 5, z0 - 6)) != nil, "oak planks chip as before")
        g.fx.decals.version = -1
        g.fx.decals.builtAt = -1e9
        let cam = V3(Float(x0) + 0.5, Float(y) + 2.6, Float(z0) + 5.5)
        look(g, from: cam, at: V3(Float(x0) - 1, Float(y) + 2, Float(z0) - 6))
        var wr = EntityWriterProbe()
        let quads = wr.count(g, eye: g.player.eye)
        check(quads >= 30, "damage decals are drawn", "\(quads) decal quads")
        let byLayer = Dictionary(grouping: g.fx.decals.quads, by: { $0.layer }).mapValues { $0.count }
        let crackN = Wear.crackLayers.reduce(0) { $0 + (byLayer[Int32($1)] ?? 0) }
        let dentN = Wear.dentLayers.reduce(0) { $0 + (byLayer[Int32($1)] ?? 0) }
        let scorchN = Wear.scorchLayers.reduce(0) { $0 + (byLayer[Int32($1)] ?? 0) }
        check(crackN > 0 && dentN > 0 && scorchN > 0, "crack, dent and scorch decals all present", "cracks \(crackN), dents \(dentN), scorch \(scorchN)")
        let ms = shot(g, r, w, h, out + "/fx_cracks.png", frames: 20)
        note(String(format: "frame with %ld decal quads: %.2f ms", quads, ms))
        // Glass: a hit at level 3 shatters it into shards.
        let glass = IVec3(x0 - 8, y + 4, z0 - 6)
        let before = g.fx.wear.shattered
        g.wearHit(glass, level: 3, normal: IVec3(0, 0, 1))
        g.particles.update(0.08, wd)
        check(wd.block(glass.x, glass.y, glass.z) == AIR && g.fx.wear.shattered == before + 1, "glass shatters at the third crack")
        check(g.particles.list.contains { $0.layer == Wear.shardLayer }, "glass leaves shard particles")
        shot(g, r, w, h, out + "/fx_shatter.png")
        // A blast next to the wall: soot on the rim, glass bursts, iron dents.
        let blast = V3(Float(x0) + 0.5, Float(y) + 1.5, Float(z0) - 3.5)
        let sootBefore = wd.scorch.count
        Explosion.explode(at: blast, power: 3, game: g)
        _ = wd.loadSync(center: g.player.pos, radius: 4)
        check(wd.scorch.count > sootBefore, "a blast leaves soot round its crater", "\(wd.scorch.count - sootBefore) blocks")
        g.particles.update(0.1, wd)
        shot(g, r, w, h, out + "/fx_blast.png")
    }

    // MARK: fire

    static func fire(_ g: Game, _ r: Renderer, _ w: Int, _ h: Int, _ out: String) {
        let wd = g.world
        let x0 = Int(floor(g.player.pos.x)) + 40, z0 = Int(floor(g.player.pos.z))
        let y = ShipTest.levelPad(wd, x0, z0, half: 14)
        g.weather.raining = false; g.weather.rain = 0; g.weather.thundering = false; g.weather.thunder = 0
        g.fx.forcedWind = V3(13, 0, 0)          // a strong wind toward +x
        g.stormTick(0.05)
        // A cabin 9 long (x), 7 deep, 4 high: log corners, plank walls, plank roof, a door gap.
        for dx in 0..<9 { for dz in 0..<7 { for dy in 0..<5 {
            let edgeX = dx == 0 || dx == 8, edgeZ = dz == 0 || dz == 6
            let p = (x0 - 4 + dx, y + dy, z0 - 3 + dz)
            if dy == 4 { put(wd, p.0, p.1, p.2, "oak_planks"); continue }
            if edgeX && edgeZ { put(wd, p.0, p.1, p.2, "oak_log"); continue }
            if edgeX || edgeZ {
                if dz == 0 && dx == 4 && dy < 2 { continue }                  // door
                put(wd, p.0, p.1, p.2, dy == 2 && (dx == 2 || dx == 6) ? "glass" : "oak_planks")
            }
        } } }
        _ = wd.loadSync(center: V3(Float(x0), Float(y), Float(z0)), radius: 4)
        // Light the upwind (-x) wall from outside.
        for dz in 0..<5 { wd.placeFire(IVec3(x0 - 5, y, z0 - 2 + dz)) }
        wd.fireStats = FireStats()
        let cam = V3(Float(x0) + 4, Float(y) + 6, Float(z0) + 18)
        look(g, from: cam, at: V3(Float(x0), Float(y) + 2, Float(z0)))
        shot(g, r, w, h, out + "/fx_fire_0.png")
        var tick = 0
        func burn(_ n: Int) { for _ in 0..<n { wd.fireTick(); tick += 1 } }
        // A few seconds of smoke plumes and ambient flames before a shot.
        func plume() { for _ in 0..<60 { g.fireSmoke(0.05); g.ambientParticles(0.05); g.particles.update(0.05, wd) } }
        burn(25)
        plume()
        let ms1 = shot(g, r, w, h, out + "/fx_fire_1.png", frames: 20)
        burn(40)
        plume()
        shot(g, r, w, h, out + "/fx_fire_2.png")
        burn(60)
        shot(g, r, w, h, out + "/fx_fire_3.png")
        let st = wd.fireStats
        var charcoal = 0, scorched = 0
        for dx in -6...10 { for dz in -6...6 { for dy in -1...6 {
            let b = wd.rawBlock(x0 - 4 + dx, y + dy, z0 - 3 + dz)
            if b == Wear.charcoal || b == Wear.smolder { charcoal += 1 }
        } } }
        scorched = wd.scorch.count
        note(String(format: "%ld fire ticks: peak %ld burning, charred %ld, burned away %ld, spreads downwind %ld / upwind %ld, tick mean %.3f ms, worst %.3f ms",
                    tick, st.peak, st.charred, st.burnedAway, st.downwind, st.upwind, st.meanMs, st.worstMs))
        note(String(format: "frame while the house burns: %.2f ms", ms1))
        check(st.peak > 5, "the house catches fire", "peak \(st.peak)")
        check(scorched > 0 || st.charred > 0, "wood scorches before it burns", "\(scorched) scorched")
        check(charcoal > 0 || st.charred > 0, "wood chars to charcoal", "\(charcoal) charcoal blocks, \(st.charred) charred")
        check(st.downwind > st.upwind, "fire spreads with the wind", "downwind \(st.downwind), upwind \(st.upwind)")
        check(st.worstMs < 8, "fire tick stays cheap", String(format: "worst %.3f ms", st.worstMs))

        // Lightning on a tree: fire round the strike.
        let tx = x0 + 30, tz = z0
        let ty = ShipTest.levelPad(wd, tx, tz, half: 4)
        for dy in 0..<6 { put(wd, tx, ty + dy, tz, "oak_log") }
        for dx in -2...2 { for dz in -2...2 { for dy in 4...6 where !(dx == 0 && dz == 0 && dy < 6) { put(wd, tx + dx, ty + dy, tz + dz, "oak_leaves") } } }
        let firesBefore = wd.fires.count
        g.strike(V3(Float(tx) + 0.5, Float(wd.topY(tx, tz) + 1), Float(tz) + 0.5))
        check(wd.fires.count > firesBefore, "lightning sets the struck tree alight", "\(wd.fires.count - firesBefore) fires")

        // The burning-cell cap: a plank field lit all over in a gale.
        let fx0 = x0 - 60, fz0 = z0 + 60
        let fy = ShipTest.levelPad(wd, fx0, fz0, half: 30)
        for dx in -30...30 { for dz in -30...30 { put(wd, fx0 + dx, fy - 1, fz0 + dz, "oak_planks") } }
        _ = wd.loadSync(center: V3(Float(fx0), Float(fy), Float(fz0)), radius: 5)
        for dx in stride(from: -30, through: 30, by: 2) { for dz in stride(from: -30, through: 30, by: 2) { wd.placeFire(IVec3(fx0 + dx, fy, fz0 + dz)) } }
        wd.fireStats = FireStats()
        for _ in 0..<20 { wd.fireTick() }
        let cs = wd.fireStats
        note(String(format: "plank field: %ld burning (cap %ld), capped spreads %ld, tick mean %.3f ms, worst %.3f ms", cs.burning, World.fireCap, cs.capped, cs.meanMs, cs.worstMs))
        check(wd.fires.count <= World.fireCap, "burning cells stay under the cap", "\(wd.fires.count)")
        check(cs.worstMs < 25, "fire tick at the cap stays bounded", String(format: "worst %.3f ms", cs.worstMs))
        g.fx.forcedWind = nil
    }

    // MARK: flood

    static func flood(_ g: Game, _ r: Renderer, _ w: Int, _ h: Int, _ out: String) {
        let wd = g.world
        guard let river = Snapshot.findBiome(wd.gen, "river") else { check(false, "a river to flood"); return }
        g.player.pos = river + V3(0, 30, 0)
        _ = wd.loadSync(center: g.player.pos, radius: max(8, wd.renderDistance))
        let fm = g.fx.flood
        let cam = river + V3(-26, 34, 30)
        look(g, from: cam, at: river)
        shot(g, r, w, h, out + "/fx_flood_0.png")
        // Heavy rain for 10 minutes of model time (the model steps every 0.5 s).
        fm.forcedRain = 1.4
        func runModel(_ seconds: Float) { for _ in 0..<Int(seconds / FloodModel.updateEvery) { fm.update(FloodModel.updateEvery, game: g) } }
        runModel(300)
        let mid = fm.placed.count
        runModel(300)
        let peak = fm.placed.count
        let depth = fm.maxDepth
        let ms = shot(g, r, w, h, out + "/fx_flood_1.png", frames: 20)
        var shore = 0
        for p in fm.placed where wd.rawBlock(p.x, p.y, p.z) == FloodModel.edge { shore += 1 }
        note("\(shore) of the flood blocks are shoreline (half height)")
        note(String(format: "after 10 min of heavy rain: %ld flood blocks (%ld at 5 min), %ld cells flooded, deepest %.2f, model step worst %.2f ms, frame %.2f ms",
                    peak, mid, fm.floodedCells, depth, fm.worstMs, ms))
        check(peak > 40, "heavy rain floods the low ground", "\(peak) blocks")
        check(peak >= mid, "the flood rises while it rains", "\(mid) -> \(peak)")
        // Oracle: every flood block stands on ground or water (none hang in the air).
        var floating = 0
        for p in fm.placed where !Blocks.collide[Int(wd.rawBlock(p.x, p.y - 1, p.z))] && Blocks.fluidKind[Int(wd.rawBlock(p.x, p.y - 1, p.z))] != 1 { floating += 1 }
        check(floating == 0, "no flood water hangs in the air", "\(floating)")
        // Oracle: full-height flood sources standing beside open air at their own height (a water wall; the shoreline
        // should be the half-height edge state).
        var walls = 0
        for p in fm.placed where wd.rawBlock(p.x, p.y, p.z) == FloodModel.flood {
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where wd.rawBlock(p.x + dx, p.y, p.z + dz) == AIR { walls += 1; break }
        }
        // Oracle: the per-block fluid sim leaves flood water alone (an edit beside a flood must not turn it into
        // ordinary water the model can't drain).
        let probe = Array(fm.placed.prefix(400))
        for p in probe { wd.scheduleFluid(around: p) }
        for _ in 0..<12 { wd.fluidTick() }
        var converted = 0
        for p in probe where !FloodModel.isFlood(wd.rawBlock(p.x, p.y, p.z)) { converted += 1 }
        check(converted == 0, "the fluid sim leaves flood water alone", "\(converted) of \(probe.count) changed")
        let wallShare = Float(walls) / Float(max(1, fm.placed.count))
        check(wallShare < 0.03, "flood shorelines are sloped, not walls", String(format: "%ld full sources beside air (%.1f%%)", walls, wallShare * 100))
        check(fm.worstMs < 12, "flood model step stays cheap", String(format: "worst %.2f ms", fm.worstMs))
        // The rain stops. A fresh model stands in for loading a save made mid-flood: it has to find the flood water
        // standing in the world (flood_water blocks) and drain it like its own. 30 minutes.
        let standing = Array(fm.placed)
        func inWorld() -> Int { standing.reduce(0) { $0 + (FloodModel.isFlood(wd.rawBlock($1.x, $1.y, $1.z)) ? 1 : 0) } }
        let fresh = FloodModel()
        fresh.forcedRain = 0
        g.fx.flood = fresh
        func runFresh(_ seconds: Float) { for _ in 0..<Int(seconds / FloodModel.updateEvery) { fresh.update(FloodModel.updateEvery, game: g) } }
        runFresh(150)                           // idle sampling (16 cells a step) until it finds flood water
        check(fresh.placed.count > peak / 2, "a reloaded flood is recognised", "\(fresh.placed.count) of \(peak) blocks adopted")
        runFresh(750)
        let half = inWorld()
        shot(g, r, w, h, out + "/fx_flood_2.png")
        runFresh(900)
        let after = inWorld()
        shot(g, r, w, h, out + "/fx_flood_3.png")
        note("receding: \(peak) -> \(half) after 15 min -> \(after) after 30 min")
        check(after < max(1, peak / 4), "the flood recedes after the rain", "\(peak) -> \(after)")
        g.fx.flood = FloodModel()
    }

    // MARK: wildfire

    // A dry thunderstorm over the savanna in a gale: lightning starts the fires (no rain falls there to put them out),
    // the wind drives them through the grass. Soak test for the cap and the fire tick under sustained load.
    static func wildfire(_ g: Game, _ r: Renderer, _ w: Int, _ h: Int, _ out: String) {
        let wd = g.world
        guard let land = Snapshot.findBiome(wd.gen, "savanna", interior: true) else { check(false, "a savanna to burn"); return }
        g.player.pos = land + V3(0, 40, 0)
        _ = wd.loadSync(center: g.player.pos, radius: max(6, wd.renderDistance))
        g.weather.raining = true; g.weather.rain = 1; g.weather.thundering = true; g.weather.thunder = 1
        g.weather.rainTime = 100_000; g.weather.thunderTime = 100_000      // the weather cycle must not end the storm early
        g.fx.forcedWind = V3(-10, 0, 6)
        wd.fireStats = FireStats()
        g.lightningTimer = 0
        var strikes = 0
        var ticks: [Double] = []
        let dt: Float = 0.05
        var fireT: Float = 0
        func run(_ seconds: Float) {
            for _ in 0..<Int(seconds / dt) {
                let b0 = g.bolts.count
                g.weatherTick(dt)
                wd.rainLevel = g.weather.rain
                if g.bolts.count > b0 { strikes += 1 }
                g.particles.update(dt, wd)
                fireT += dt
                if fireT >= 1.5 {
                    fireT = 0
                    let t0 = CFAbsoluteTimeGetCurrent()
                    wd.fireTick()
                    ticks.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                }
            }
        }
        run(240)
        let mid = wd.fires.count
        look(g, from: land + V3(-30, 45, 30), at: land)
        g.particles.update(0.05, wd)
        // Midday, between strikes (the first shot caught a lightning flash: a white-out under a night-dark sky).
        let keepTime = g.time
        g.time = 0.28 * DAY_LENGTH
        g.lightningFlash = 0; g.flashes.removeAll(); g.bolts.removeAll()
        let ms = shot(g, r, w, h, out + "/fx_wildfire.png", frames: 10)
        g.time = keepTime
        // The storm passes: the fires are left to burn out on their own.
        g.weather.thundering = false; g.weather.thunder = 0; g.weather.raining = false; g.weather.rain = 0
        run(600)
        ticks.sort()
        let st = wd.fireStats
        let p95 = ticks.isEmpty ? 0 : ticks[min(ticks.count - 1, ticks.count * 95 / 100)]
        note(String(format: "dry storm, 4 min: %ld strikes, %ld burning (peak %ld, cap %ld), %ld burned away, %ld charred; 10 min later %ld burning; fire tick p95 %.3f ms, worst %.3f ms; frame %.2f ms",
                    strikes, mid, st.peak, World.fireCap, st.burnedAway, st.charred, wd.fires.count, p95, st.worstMs, ms))
        check(strikes > 3, "dry lightning strikes in dry country", "\(strikes)")
        check(st.peak > 0, "dry lightning starts fires", "peak \(st.peak)")
        check(st.peak <= World.fireCap, "a wildfire stays under the burning-cell cap", "peak \(st.peak)")
        check(p95 < 4, "fire tick stays cheap under a wildfire", String(format: "p95 %.3f ms", p95))
        g.fx.forcedWind = nil
    }

    // MARK: snow

    static func snow(_ g: Game, _ r: Renderer, _ w: Int, _ h: Int, _ out: String) {
        let wd = g.world
        guard let field = Snapshot.findBiome(wd.gen, "snowy_plains", interior: true) else { check(false, "snowy plains to snow on"); return }
        g.player.pos = field + V3(0, 6, 0)
        _ = wd.loadSync(center: g.player.pos, radius: max(6, wd.renderDistance))
        let cx = Int(floor(field.x)), cz = Int(floor(field.z))
        func depth() -> Float {
            var sum = 0, n = 0
            for dz in stride(from: -24, through: 24, by: 2) { for dx in stride(from: -24, through: 24, by: 2) {
                let x = cx + dx, z = cz + dz
                guard let c = wd.chunkAt(x, z) else { continue }
                let y = Int(c.height[mod(x, CS) + mod(z, CS) * CS])
                let l = g.snowLayers(wd.rawBlock(x, y + 1, z))
                if l >= 0 { sum += l; n += 1 }
            } }
            return n > 0 ? Float(sum) / Float(n) : 0
        }
        let cam = field + V3(-10, 6, 12)
        look(g, from: cam, at: field + V3(4, 0, -6))
        let d0 = depth()
        shot(g, r, w, h, out + "/fx_snow_0.png")
        // A cow standing in the field: the snow must not grow into a solid height under it.
        let cowX = cx + 3, cowZ = cz - 4
        let cowY = wd.topY(cowX, cowZ) + 1
        let cow = Mob(.cow, at: V3(Float(cowX) + 0.5, Float(cowY), Float(cowZ) + 0.5))
        g.mobs.mobs.append(cow)
        g.weather.raining = true; g.weather.rain = 1
        var worst = 0.0
        var passes: [Double] = []
        func run(_ seconds: Float) {
            for _ in 0..<Int(seconds / 0.05) {
                let c0 = g.fx.snowCursor
                let t0 = CFAbsoluteTimeGetCurrent()
                g.snowTick(0.05)
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                worst = max(worst, ms)
                if g.fx.snowCursor != c0 { passes.append(ms) }
            }
        }
        g.fx.snowChanges = 0
        run(240)
        let d1 = depth()
        let under = g.snowLayers(wd.rawBlock(cowX, wd.topY(cowX, cowZ) + 1, cowZ))
        check(under <= 2, "snow doesn't bury a standing cow's feet", "\(under) layers under it")
        g.mobs.mobs.removeAll { $0 === cow }
        let drops = Mining.drops(Game.snowLayerIDs[5], ItemStack.empty).reduce(0) { $0 + $1.count }
        check(drops > 0, "deep snow drops snowballs", "\(drops) from 5 layers")
        shot(g, r, w, h, out + "/fx_snow_1.png")
        g.weather.raining = false; g.weather.rain = 0
        g.time = 0.25 * DAY_LENGTH
        run(600)
        let d2 = depth()
        shot(g, r, w, h, out + "/fx_snow_2.png")
        passes.sort()
        let p95 = passes.isEmpty ? 0 : passes[min(passes.count - 1, passes.count * 95 / 100)]
        let mean = passes.isEmpty ? 0 : passes.reduce(0, +) / Double(passes.count)
        note(String(format: "snow depth (layers, mean over 625 columns): %.2f -> %.2f after 4 min of snow -> %.2f after 10 min of sun; %ld block writes; %ld chunk passes: mean %.3f ms, p95 %.3f ms, worst %.2f ms",
                    d0, d1, d2, g.fx.snowChanges, passes.count, mean, p95, worst))
        check(d1 >= d0 + 1.5, "snow piles up in layers while it snows", String(format: "%.2f -> %.2f", d0, d1))
        check(d2 <= d1 - 1, "snow melts back after the storm", String(format: "%.2f -> %.2f", d1, d2))
        // Gated on the 95th percentile: the worst of thousands of passes is the shared runner's noise (4 -> 11 ms on
        // the same code, runs 473-500).
        check(p95 < 3, "snow chunk pass stays cheap", String(format: "p95 %.3f ms, worst %.2f ms", p95, worst))
    }

    // MARK: storm

    static func storm(_ g: Game, _ r: Renderer, _ w: Int, _ h: Int, _ out: String) {
        let wd = g.world
        guard let sea = Snapshot.findBiome(wd.gen, "ocean") else { check(false, "an ocean for the storm"); return }
        g.player.pos = sea + V3(0, 8, 0)
        _ = wd.loadSync(center: g.player.pos, radius: max(6, wd.renderDistance))
        wd.ships.encounters = false
        let helm = ShipTest.place(wd, "gunboat", near: sea)
        let (gbOpt, msg) = wd.ships.assemble(at: helm, game: g)
        guard let boat = gbOpt else { check(false, "gunboat assembles", msg); return }
        func tilt(_ s: Ship) -> Float { acosf(min(1, max(-1, s.dirToWorld(V3(0, 1, 0)).y))) * 180 / .pi }
        var tiltLow: Float = 180                 // the least tilt over the last half of a run (rolling, not just listing)
        func sail(_ seconds: Float) -> (Float, Float, Double) {
            var maxTilt: Float = 0, minY = Float.greatestFiniteMagnitude
            tiltLow = 180
            let steps = Int(seconds * 60)
            var worst = 0.0
            let dt: Float = 1.0 / 60
            for i in 0..<steps {
                g.time += Double(dt)                    // the swell travels with game time
                g.stormTick(dt)
                let t0 = CFAbsoluteTimeGetCurrent()
                wd.ships.update(dt, game: g)
                worst = max(worst, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                maxTilt = max(maxTilt, tilt(boat))
                if i > steps / 2 { tiltLow = min(tiltLow, tilt(boat)) }
                minY = min(minY, boat.pos.y)
            }
            return (maxTilt, minY, worst)
        }
        g.weather.raining = false; g.weather.rain = 0; g.weather.thundering = false; g.weather.thunder = 0
        g.fx.storm = 0
        let (calmTilt, _, _) = sail(10)
        g.weather.raining = true; g.weather.rain = 1; g.weather.thundering = true; g.weather.thunder = 1
        g.fx.storm = 1
        let y0 = boat.pos.y
        let (stormTilt, minY, worst) = sail(25)
        let swing = stormTilt - tiltLow
        check(swing > 3, "the ship rolls back and forth (not just listing)", String(format: "tilt %.1f-%.1f deg", tiltLow, stormTilt))
        let up = boat.dirToWorld(V3(0, 1, 0)).y
        note(String(format: "gunboat: max tilt %.1f deg calm, %.1f deg in the storm (swell %.2f), lowest %.2f vs start %.2f, upright %.2f, ship step worst %.2f ms",
                    calmTilt, stormTilt, Waves.amp, minY, y0, up, worst))
        check(stormTilt > max(3, calmTilt * 2), "a storm rolls and pitches the ship", String(format: "%.1f vs %.1f deg", stormTilt, calmTilt))
        check(up > 0.3 && minY > y0 - 4, "the ship rides it out (afloat, not capsized)", String(format: "up %.2f", up))
        // Lightning on the ship: the strike bursts on the hull (a storm can wreck a vessel).
        let blocksBefore = boat.blockCount
        g.strike(V3(boat.pos.x, boat.worldMax.y + 1, boat.pos.z))
        note("lightning on the gunboat: \(blocksBefore) -> \(boat.blockCount) hull blocks")
        check(boat.blockCount < blocksBefore, "lightning bursts on a ship's hull", "\(blocksBefore) -> \(boat.blockCount)")
        ShipTest.chase(g, boat, dist: 16, height: 6)
        let ms = shot(g, r, w, h, out + "/fx_storm_ship.png", frames: 20)
        note(String(format: "storm frame: %.2f ms", ms))
        g.weather.raining = false; g.weather.rain = 0; g.weather.thundering = false; g.weather.thunder = 0
        g.fx.storm = 0
        Waves.amp = 0
    }
}

// Counts the decal quads the renderer would write this frame (without a GPU buffer).
struct EntityWriterProbe {
    mutating func count(_ g: Game, eye: V3) -> Int {
        let cap = 6 * WearDecals.maxQuads + 6
        let buf = UnsafeMutablePointer<EntityVert>.allocate(capacity: cap)
        defer { buf.deallocate() }
        var wr = EntityWriter(out: buf, capacity: cap)
        g.writeWear(&wr, eye: eye)
        return wr.n / 6
    }
}
