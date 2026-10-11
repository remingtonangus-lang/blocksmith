import Foundation
import simd
import CVulkan

// The L1 sky checks (docs/status/look-upgrade.md): clouds.frag through the Quest renderer on lavapipe, each view rendered
// with and without the cloud pass and compared pixel by pixel, plus the shared SkyState logic (wind, biome air, distant
// storm flashes). Writes sky_*.png next to the other render shots for a reviewer.
enum SkyTest {
    struct Stats { var changed: Float; var luma: Float; var r: Float; var b: Float; var cloudLuma: Float; var cloudR: Float; var cloudB: Float }

    static func run(game: Game, ctx: VkContext, dir: String, check: (Bool, String) -> Void) throws {
        let p = game.player
        let saved = (p.pos, p.flying, game.time, game.weather, game.sky)
        defer {
            (p.pos, p.flying, game.time, game.weather, game.sky) = saved
            WorldRenderer.debugSkip.remove("clouds")
        }
        p.flying = true
        p.pos.y += 30
        let w = 320, h = 320
        // Renders the view with and without clouds; stats over the left eye.
        func view(_ name: String, time: Double, pitch: Float, yaw: Float = 0.6, rain: Float = 0, thunder: Float = 0,
                  setup: () -> Void = {}) throws -> Stats {
            game.time = time * DAY_LENGTH
            game.weather.rain = rain; game.weather.raining = rain > 0
            game.weather.thunder = thunder; game.weather.thundering = thunder > 0
            game.sky.flashAge = 9                       // no flash unless the view asks for one
            setup()
            WorldRenderer.debugSkip.insert("clouds")
            try RenderTest.render(game: game, ctx: ctx, path: "\(dir)/sky_\(name)_off.png", width: w, height: h, yaw: yaw, pitch: pitch)
            let off = RenderTest.lastRGBA
            WorldRenderer.debugSkip.remove("clouds")
            setup()
            try RenderTest.render(game: game, ctx: ctx, path: "\(dir)/sky_\(name).png", width: w, height: h, yaw: yaw, pitch: pitch)
            let on = RenderTest.lastRGBA
            var st = Stats(changed: 0, luma: 0, r: 0, b: 0, cloudLuma: 0, cloudR: 0, cloudB: 0)
            var nc = 0
            for y in 0..<h { for x in 0..<w {
                let i = (y * w * 2 + x) * 4
                let r = Float(on[i]), g = Float(on[i + 1]), b = Float(on[i + 2])
                let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
                st.luma += l; st.r += r; st.b += b
                let dl = abs(Int(on[i]) - Int(off[i])) + abs(Int(on[i + 1]) - Int(off[i + 1])) + abs(Int(on[i + 2]) - Int(off[i + 2]))
                if dl > 18 { nc += 1; st.cloudLuma += l; st.cloudR += r; st.cloudB += b }
            } }
            let n = Float(w * h)
            st.luma /= n; st.r /= n; st.b /= n
            st.changed = Float(nc) / n
            if nc > 0 { st.cloudLuma /= Float(nc); st.cloudR /= Float(nc); st.cloudB /= Float(nc) }
            print(String(format: "sky: %@ clouds over %.0f%% of the view, mean luma %.0f (cloud pixels %.0f, r %.0f b %.0f), frame %.0f ms",
                         name, st.changed * 100, st.luma, st.cloudLuma, st.cloudR, st.cloudB, RenderTest.lastFrameMs))
            return st
        }
        game.sky.cover = 0.45; game.sky.targetCover = 0.45; game.sky.flashAge = 9
        let noon = try view("noon", time: 0.22, pitch: 0.75)
        check(noon.changed > 0.12 && noon.changed < 0.85,
              String(format: "sky: fair-weather clouds cover part of a noon sky (%.0f%%, want 12-85%%)", noon.changed * 100))
        check(noon.cloudLuma > 150, String(format: "sky: noon clouds are bright (cloud luma %.0f)", noon.cloudLuma))
        let overcast = try view("overcast", time: 0.22, pitch: 0.75, rain: 1)
        check(overcast.changed > noon.changed + 0.15 && overcast.changed > 0.6,
              String(format: "sky: rain closes the cover (%.0f%% vs %.0f%% fair)", overcast.changed * 100, noon.changed * 100))
        check(overcast.luma < noon.luma - 15, String(format: "sky: an overcast sky is darker (luma %.0f vs %.0f)", overcast.luma, noon.luma))
        let storm = try view("storm", time: 0.22, pitch: 0.75, rain: 1, thunder: 1)
        check(storm.luma < overcast.luma, String(format: "sky: a thunderstorm darkens the clouds further (luma %.0f vs %.0f)", storm.luma, overcast.luma))
        let look = V3(-sinf(0.6) * cosf(0.75), sinf(0.75), -cosf(0.6) * cosf(0.75))
        let flash = try view("storm_flash", time: 0.22, pitch: 0.75, rain: 1, thunder: 1) {
            game.sky.flashAt(look, strength: 1); game.sky.flashAge = 0
        }
        check(flash.luma > storm.luma + 8, String(format: "sky: a storm flash lights the clouds (luma %.0f vs %.0f)", flash.luma, storm.luma))
        // Sunset toward the sun (yaw: forward = (-sin yaw, -cos yaw); the sun sets toward -X).
        let sunset = try view("sunset", time: 0.485, pitch: 0.3, yaw: .pi / 2)
        check(sunset.changed > 0.05 && sunset.cloudR > sunset.cloudB + 12,
              String(format: "sky: sunset clouds are warm (r %.0f, b %.0f over %.0f%%)", sunset.cloudR, sunset.cloudB, sunset.changed * 100))
        // Toward the horizon (the last ~6 degrees above it) the deck must not alias into 1-pixel stripes: the mean
        // vertical second difference of luma there, minus the same without clouds (the dome's own gradient).
        func stripes(_ img: [UInt8], horizonRow: Int) -> Float {
            var sum: Float = 0, n: Float = 0
            func l(_ x: Int, _ y: Int) -> Float {
                let i = (y * w * 2 + x) * 4
                return 0.2126 * Float(img[i]) + 0.7152 * Float(img[i + 1]) + 0.0722 * Float(img[i + 2])
            }
            for y in max(0, horizonRow - 22)..<(horizonRow - 3) { for x in 0..<w { sum += abs(l(x, y) - 2 * l(x, y + 1) + l(x, y + 2)); n += 1 } }
            return sum / max(1, n)
        }
        for (name, rain) in [("horizon", Float(0)), ("horizon_overcast", Float(1))] {
            let pitch: Float = 0.08
            let hr = h / 2 + Int(Float(h / 2) * tanf(pitch))
            _ = try view(name, time: 0.22, pitch: pitch, rain: rain)
            let on = stripes(RenderTest.lastRGBA, horizonRow: hr)
            WorldRenderer.debugSkip.insert("clouds")
            try RenderTest.render(game: game, ctx: ctx, path: "\(dir)/sky_\(name)_off.png", width: w, height: h, yaw: 0.6, pitch: pitch)
            WorldRenderer.debugSkip.remove("clouds")
            let off = stripes(RenderTest.lastRGBA, horizonRow: hr)
            check(on - off < 2.5, String(format: "sky: no stripes toward the horizon (%@: roughness %.2f with clouds, %.2f without)", name, on, off))
        }
        // From a dark cave (the dome dimmed to 8 %%) the clouds up a shaft dim with it.
        do {
            WorldRenderer.testCaveK = 0
            defer { WorldRenderer.testCaveK = nil }
            let cave = try view("cave", time: 0.22, pitch: 0.75)
            check(cave.cloudLuma < 60 || cave.changed < 0.02,
                  String(format: "sky: clouds dim with the sky seen from a dark cave (cloud luma %.0f vs %.0f outside)", cave.cloudLuma, noon.cloudLuma))
        }
        let night = try view("night", time: 0.75, pitch: 0.75)
        check(night.changed > 0.03 && night.cloudLuma < noon.cloudLuma * 0.4,
              String(format: "sky: night clouds are dim shapes (cloud luma %.0f vs %.0f at noon, %.0f%%)", night.cloudLuma, noon.cloudLuma, night.changed * 100))
        // Cost: the cloud pass's share of a sky-filled frame on lavapipe (a CPU rasteriser: relative, not Quest ms).
        do {
            game.time = 0.22 * DAY_LENGTH; game.weather = Weather(); game.weather.rain = 0
            var offMs: [Double] = [], onMs: [Double] = []
            for _ in 0..<2 {
                WorldRenderer.debugSkip.insert("clouds")
                try RenderTest.render(game: game, ctx: ctx, path: "\(dir)/sky_cost.png", width: w, height: h, yaw: 0.6, pitch: 0.75)
                offMs.append(RenderTest.lastFrameMs)
                WorldRenderer.debugSkip.remove("clouds")
                try RenderTest.render(game: game, ctx: ctx, path: "\(dir)/sky_cost.png", width: w, height: h, yaw: 0.6, pitch: 0.75)
                onMs.append(RenderTest.lastFrameMs)
            }
            print(String(format: "sky: lavapipe frame with clouds %.1f ms, without %.1f ms (sky-filled view, %dx%d x2)",
                         onMs.min()!, offMs.min()!, w, h))
        }
        // Shared logic: one wind drives the drift; the biome air; distant flashes and their thunder during a storm.
        var s = SkyState()
        s.windAngle = 0.6
        game.sky = s
        game.weather = Weather(); game.weather.rain = 0; game.weather.thunder = 0
        for _ in 0..<200 { game.skyTick(0.05) }
        let dx = Float(game.sky.driftX), dz = Float(game.sky.driftZ)
        let dirOK = simd_dot(simd_normalize(V2(dx, dz)), V2(cosf(0.6), sinf(0.6))) > 0.99
        check(dirOK && hypotf(dx, dz) > 10 && hypotf(dx, dz) < 20,
              String(format: "sky: 10 s of fair weather drifts the clouds %.1f blocks along the wind", hypotf(dx, dz)))
        game.weather.rain = 1; game.weather.raining = true; game.weather.thunder = 1; game.weather.thundering = true
        let f0 = game.sky.distantFlashes
        for _ in 0..<1200 { game.skyTick(0.05) }
        let flashes = game.sky.distantFlashes - f0
        check(flashes >= 4 && flashes <= 25, "sky: a minute of thunderstorm flashes the distant clouds \(flashes) times")
        // Biome air as the game shows it: walk the sky state to the biome under a desert and a snow column and read
        // the noon horizon and zenith (Game.skyColor / skyZenith, both platforms).
        game.weather = Weather(); game.weather.rain = 0; game.weather.thunder = 0
        game.time = 0.25 * DAY_LENGTH
        func settle(_ b: Biome) -> (V3, V3, Float) {
            let (t, hz, c) = SkyState.air(b)
            game.sky.targetTint = t; game.sky.targetHaze = hz; game.sky.targetCover = c
            for _ in 0..<400 { game.sky.biomeTimer = 1; game.skyTick(0.05) }      // 20 s, the biome sample held
            return (game.skyColor, game.skyZenith, game.cloudCover)
        }
        let (plainH, plainZ, plainC) = settle(.plains)
        let (desH, desZ, desC) = settle(.desert)
        let (snowH, snowZ, _) = settle(.snowyPlains)
        let rb = { (c: V3) -> Float in c.x / c.z }
        check(rb(desH) > rb(plainH) + 0.08 && rb(desZ) > rb(plainZ) + 0.05 && desC < plainC,
              String(format: "sky: desert air is hazier and warmer with fewer clouds (horizon r/b %.2f vs %.2f plains, cover %.2f vs %.2f)", rb(desH), rb(plainH), desC, plainC))
        check(rb(snowH) < rb(plainH) - 0.03 && rb(snowZ) <= rb(plainZ),
              String(format: "sky: snow air is a colder blue (horizon r/b %.2f vs %.2f plains)", rb(snowH), rb(plainH)))
    }
}
