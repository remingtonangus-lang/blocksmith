import Foundation
import simd
import CVulkan

// Draws the game world for one frame through SceneRenderer, in the Mac renderer's Fast-path order (Renderer.encode):
// terrain (solid, cutout), mobs, entities and particles, the target outline, sky dome / stars / sun and moon (after the
// opaque geometry, only where the depth buffer is still clear), then water and translucent blocks far to near.
final class WorldRenderer {
    let scene: SceneRenderer
    let game: Game
    private var caveK: Float = -1
    private var sheenBits: [UInt32] = []                      // SH1: ShaderFX.sheenBits, built once the textures exist
    var extraOpaque: ((SceneRenderer.Slot, V3) -> Void)?     // hands, rays, panels (the XR layer)
    var extraOverlay: ((SceneRenderer.Slot, V3) -> Void)?    // drawn last (panels over everything)
    var prePass: ((SceneRenderer.Slot) -> Void)?              // offscreen passes before the world pass (the HUD panel)
    private(set) var frameCPUMs = 0.0
    private(set) var lastMobVerts = 0     // mob vertices written in the last frame
    // Where the record time goes, summed until the next perf line (QuestApp FrameStats). P385 step 1: the frame's
    // uniforms (cave light, fog, sky), the cull's parts (the cull table, the walk with its sort, horizon culling,
    // occlusion culling, the list), the section records, the HUD panel, the terrain draw lists, the middle ring, ships,
    // landmarks, mobs (with the wait on their worker), entities, particles, the sky, water and glass, and the rest of the
    // UI (outline, hands, panels).
    static let stageNames = ["uniforms", "table", "walk", "horizon", "occlusion", "list", "records", "hud", "terrain", "ring",
                             "ships", "landmarks", "mobs", "entities", "particles", "sky", "translucent", "ui"]
    private var stageSums = [Double](repeating: 0, count: 18), stageFrames = 0
    // P420: this frame's record stages (ms), for the pause menu's Compute page (ComputeCost).
    private var stagePrev = [Double](repeating: 0, count: 18)
    private(set) var stageFrame = [Double](repeating: 0, count: 18)
    private(set) var stageWorst = 0.0                       // the slowest frame's record since the last take (ms)
    private var tableReads = 0, rasterSum = 0.0              // columns the cull table re-read; occluder raster (worker) ms
    func takeStages() -> String {
        let n = Double(max(1, stageFrames))
        let parts = zip(WorldRenderer.stageNames, stageSums).map { "\($0) " + String(format: "%.2f", $1 * 1000 / n) }
        let extra = String(format: " | table re-read %.1f columns a frame, occluder raster %.2f ms a frame; taken back from the workers: mobs %d, raster %d of %d frames",
                           Double(tableReads) / n, rasterSum / n, mobWork.takeTookBack(), scene.occWork.takeTookBack(), stageFrames)
        for i in stageSums.indices { stageSums[i] = 0; stagePrev[i] = 0 }
        stageFrames = 0; stageWorst = 0; tableReads = 0; rasterSum = 0
        return parts.joined(separator: ", ") + extra
    }
    // P385 step 3: the mobs' vertices are written on a worker while the frame thread culls and draws the terrain (they read the
    // mobs, the light and the model tables, none of which the cull touches), into a vertex buffer of the slot's own,
    // and drawn when the frame reaches them (FrameWork: taken back by the frame thread if the worker hasn't begun).
    // BS_MOBTHREAD=0: written in place, as before.
    static var mobThread = ProcessInfo.processInfo.environment["BS_MOBTHREAD"] != "0"
    static let mobBufBytes = 10 << 20
    private let mobWork = FrameWork(label: "mobverts")
    private var mobBufs: [ObjectIdentifier: VkBuf] = [:]
    private var mobPending: VkBuf?
    private var mobCount = 0
    private func startMobs(_ s: SceneRenderer.Slot, _ eye: V3, _ frustum: Frustum) {
        mobPending = nil
        guard WorldRenderer.mobThread, !WorldRenderer.debugSkip.contains("mobs") else { return }
        guard !game.mobs.mobs.isEmpty || !game.mobs.corpses.isEmpty || !Hunting.bodyMobs.isEmpty || !AshFallen.mobs.isEmpty || !AshWrecks.mobs.isEmpty || !AshWrecks.skinMobs.isEmpty else { return }
        let id = ObjectIdentifier(s)
        if mobBufs[id] == nil { mobBufs[id] = try? VkBuf(scene.ctx, size: WorldRenderer.mobBufBytes, usage: VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.rawValue, host: true) }
        guard let b = mobBufs[id], let p = b.mapped else { return }
        let cap = WorldRenderer.mobBufBytes / MemoryLayout<MobVert>.stride
        let ptr = p.bindMemory(to: MobVert.self, capacity: cap)
        let mobs = game.mobs.mobs, corpses = game.mobs.corpses, rag = game.debris.ragdolls
        let daylight = game.renderDaylight, world = game.world, maxD = mobMaxDist
        mobPending = b
        Mob.settleLooks(mobs, world)                                                       // P411
        MobMotion.on = scene.spaceWarpOn; MobMotion.ranges.removeAll(keepingCapacity: true)    // P403 7b
        mobWork.start { [self] in
            mobCount = writeMobVertices(mobs, eye: eye, daylight: daylight, world: world, into: ptr, capacity: cap,
                                        cull: frustum, maxDist: maxD, corpses: corpses, ragdolls: rag)
        }
    }
    private func joinMobs() {
        if mobPending != nil { mobWork.finish() }
    }
    private var camYaw: Float = 0, camPitch: Float = 0
    // Debugging aid: QUEST_SKIP=mobs,entities,... leaves passes out.
    static var debugSkip = Set((ProcessInfo.processInfo.environment["QUEST_SKIP"] ?? "").split(separator: ",").map(String.init))

    let ships: ShipDraw
    // Volcano and Ancient Spire impostors past the render distance (Sources/LandmarkRender.swift on the HUD host).
    var landmarkHost: Renderer?
    private var landmarkVerts: [SimpleVert] = []
    private(set) var landmarkCount = 0
    private(set) var landmarkMs = 0.0
    // F4 middle ring (Sources/FarRing.swift): two host-visible vertex buffers, one drawn while a new build goes into
    // the other (only once the other has been out of use for 3 frames: both frames in flight are done with it).
    private(set) var farRingOn = false           // this frame's uniforms showed it (open overworld sky)
    private var farBufs: [VkBuf?] = [nil, nil]
    private var farLive = -1, farQuads = 0, farGen = -1, farFrame = 0
    private var farUsed = [-10, -10]
    private var farOrigin = (0, 0), farSeed: UInt64 = 0
    private(set) var farRingQuads = 0            // drawn last frame (perf lines)
    private var farCover: Float = 0              // P250 (c): the meshed radius the ring sinks inside (every 6 frames)

    init(scene: SceneRenderer, game: Game) {
        self.scene = scene
        self.game = game
        ships = ShipDraw(scene: scene)
    }

    // Skylight around the eye, smoothed (Renderer.updateCave): fog and sky darken underground, and the eye darkness
    // (misc.y) brings in the cave fill. Eye adaptation is one continuous fade: the eye block plus four open neighbours
    // two blocks out (a cave mouth starts the fade before you are inside it, a 1-block overhang doesn't flick it), eased
    // over ~0.7 s by real time. It was the eye block alone at 4 % a frame (~0.3 s), against a narrow skylight 12-6 ramp:
    // walking in, the walls went dark before the fill came on, then the fill snapped in bright (Quest v63 report).
    private var caveClock = 0.0
    private var fogClock = 0.0, fogEase: Float = -1, fogStartEase: Float = 0      // P437: the eased fog reach (uniforms)
    private var fogDim = Dim.overworld
    private func updateCave(_ eye: V3) {
        guard game.dim.dim.hasSky else { caveK = 1; return }
        let w = game.world
        let x = Int(floor(eye.x)), y = Int(floor(eye.y)), z = Int(floor(eye.z))
        var sum = Float(w.lightAt(x, y, z).sky) * 2, n: Float = 2
        func add(_ bx: Int, _ bz: Int) {
            if Blocks.opaque[Int(w.block(bx, y, bz))] { return }          // inside a wall says nothing about the sky
            sum += Float(w.lightAt(bx, y, bz).sky); n += 1
        }
        add(x + 2, z); add(x - 2, z); add(x, z + 2); add(x, z - 2)
        let target = sum / (n * 15)
        let now = CFAbsoluteTimeGetCurrent()
        let dt = Float(min(0.1, max(0, now - caveClock)))
        caveClock = now
        caveK = caveK < 0 ? target : caveK + (target - caveK) * (1 - expf(-dt / 0.7))
    }
    var caveScale: Float { 0.08 + 0.92 * min(1, max(0, WorldRenderer.testCaveK ?? caveK) * 1.6) }
    // Underground (P113, Oct 12 PM: "looking down a long cave, the sky shows at the far end"): rock well over the eye and
    // little skylight round it. A tunnel running past the loaded ground, or past the cave fog's section cull, left a hole
    // the sky pass filled with the blue sky dome (sun and clouds). Underground the sky pass draws only the dark fog
    // colour and the fog closes before the cull at any skylight.
    private(set) var underground = false
    private func updateUnderground(_ eye: V3) {
        guard game.dim.dim.hasSky, !game.player.headInWater else { underground = false; return }
        let top = game.world.topY(Int(floor(eye.x)), Int(floor(eye.z)))
        // R18 (Oct 13 evening, again: "sky and far trees visible from underground"): skylight alone missed caves lit
        // by a shaft or a ravine nearby (eye skylight over 0.45), so there was no cave fog cap: the far ring drops its
        // unlit cave walls (Mesher.farDarkCull) and the surface's trees showed through the rock. Rock overhead decides
        // too: most of five columns round the eye with 8+ solid natural blocks over it within 64 is underground.
        underground = (top > Int(floor(eye.y)) + 6 && caveK < 0.45) || (caveK < 0.7 && rockOverhead(eye))
    }
    private func rockOverhead(_ eye: V3) -> Bool {
        let w = game.world
        let x = Int(floor(eye.x)), y = Int(floor(eye.y)), z = Int(floor(eye.z))
        var covered = 0
        for (dx, dz) in [(0, 0), (5, 0), (-5, 0), (0, 5), (0, -5)] {
            var n = 0
            var yy = y + 2
            while yy < min(CH, y + 64) && n < 8 {
                let b = Int(w.block(x + dx, yy, z + dz))
                if Blocks.opaque[b] && SmoothTerrain.natural[b] { n += 1 }
                yy += 2
            }
            if n >= 8 { covered += 1 }
            if covered >= 3 { return true }
        }
        return false
    }
    static var testCaveK: Float?           // SkyTest: a dark-cave eye without building a cave

    func uniforms(_ cam: EyeCamera) -> (FrameUniforms, V3) {
        let p = game.player
        let eye = cam.center
        let rd = Float(game.world.renderDistance)
        let underwater = p.headInWater
        let sky = game.skyColor * caveScale
        let hasSky = game.dim.dim.hasSky
        let uwSee: Float = 18 + 38 * game.daylight * caveScale
        var fogEnd: Float = underwater ? uwSee : (game.dim.dim == .nether ? min(rd * 16 - 12, 96) : rd * 16 - 12)
        // P211 redo (Oct 14, "no fog at all unless it's foggy weather"): in clear air the fog is only a thin band at the
        // very edge of the drawn world (the last 6 %), so the cut-off never shows and nothing nearer is greyed.
        // P425 (Remington, Oct 24: "instead of the far background, just make it fog"): with Auto View Distance the
        // drawn edge fades into haze over its last 30 % (the view may sit at 8-16 chunks) and the far ring stays off.
        let autoView = QuestSettings.autoViewDistance && game.dim.dim == .overworld
        let clearStart: Float = autoView ? 0.7 : 0.94
        var fogStart: Float = underwater ? 1 : fogEnd * (game.dim.dim == .overworld ? clearStart : 0.8)
        var fogColor = underwater ? game.underwaterFog : (underground ? sky * min(1, 0.25 / max(caveScale, 0.25)) : sky)
        if p.headInLava { fogEnd = game.effects.has(.fireResistance) ? 6 : 2.5; fogStart = 0.2; fogColor = Game.lavaFog }
        let vaultSky = game.inVaultSky && !underwater && !p.headInLava       // the Ash Vault's own sky (AshSky.swift)
        let hellSky = game.inHellSky && !underwater && !p.headInLava         // P342 (b): hell's own (HellSky.swift)
        // P323 (b): the vault's haze up to its roof (above y 128 the roof is drawn, but the air is the vault's).
        if game.inVaultHaze && !underwater && !p.headInLava { fogStart = AshSky.fogStart; fogEnd = min(fogEnd, game.vaultFogEnd); fogColor = sky }
        if let bf = game.blindFog { fogEnd = min(fogEnd, bf); fogStart = bf * 0.2; fogColor = V3(0, 0, 0) }
        if !underwater, hasSky, let cap = World.caveSight(caveK: underground ? 0 : caveK), cap < fogEnd { fogEnd = cap; fogStart = min(fogStart, cap * 0.55) }
        // F4: the middle ring (Sources/FarRing.swift) shows past the loaded chunks whenever the view reaches them (the
        // overworld's open sky: no cave, weather, blindness, vault or underwater fog cut it short). The fog then runs
        // out to the ring's rim, so chunks and ring share one fog (no fog wall at the loaded edge with clearer land
        // beyond) and the rim melts into the horizon shell.
        let baseEnd: Float = rd * 16 - 12
        // (P472: at a big hull's helm, or flying, the ring shows under Auto View Distance too: Game.helmFarView.)
        farRingOn = FarRing.enabled && (!autoView || game.helmFarView) && game.dim.dim == .overworld && !underwater && !p.headInLava && !vaultSky && !underground
            && game.blindFog == nil && fogEnd >= baseEnd - 0.01 && game.world.gen is WorldGen
        // (Only once a ring is up: until its first build lands the loaded edge keeps the usual fog.)
        if farRingOn && farLive >= 0 && farSeed == game.world.seed { fogEnd = max(fogEnd, FarRing.outer - 16); fogStart = fogEnd * clearStart }
        // O7: fog banks (WeatherWar.swift). P365 (g): applied after the middle ring (the ring stays up under a bank),
        // so the reach closes in smoothly from the ring's rim instead of snapping from the ring to the loaded edge when
        // the bank begins and back when it lifts.
        if !underwater, hasSky, let wf = game.weatherFogEnd, wf < fogEnd {
            fogEnd = wf; fogStart = min(fogStart, wf * game.weatherFogStartK)
            if let tint = game.stormFogTint { fogColor = fogColor * 0.35 + tint * 0.65 * max(0.25, game.daylight) }   // D49
            fogColor = fogColor * (1 - 0.5 * WeatherWar.fog) + V3(0.6, 0.62, 0.64) * (0.5 * WeatherWar.fog * game.daylight)
        }
        // P437 (Oct 24 16:05, "the fog should slowly drift in, not just appear like that... also just disappeared in
        // like a second"): the reach jumped whenever its inputs did (Auto View Distance stepping the drawn edge in or out,
        // a cave mouth's cap, the bank's height cut-off while climbing or dropping). It now eases to where it is going
        // over a few seconds; underwater, lava, blindness and the vault haze still change at once.
        let fogNow = CFAbsoluteTimeGetCurrent()
        let fogDt = Float(min(0.1, max(0, fogNow - fogClock)))
        fogClock = fogNow
        if fogEase < 0 || underwater || p.headInLava || game.blindFog != nil || game.inVaultHaze || game.dim.dim != fogDim {
            fogEase = fogEnd; fogStartEase = fogStart; fogDim = game.dim.dim
        } else {
            let k = 1 - expf(-fogDt / 3)
            fogEase += (fogEnd - fogEase) * k
            fogStartEase += (fogStart - fogStartEase) * k
            fogEnd = fogEase; fogStart = min(fogStartEase, fogEnd)
        }
        let daylight = game.renderDaylight
        let nv = game.nightVision
        let ambient = 1 - (1 - game.dimAmbient) * (1 - 0.85 * nv)
        let sd = vaultSky ? AshSky.sunDir : (hellSky ? HellSky.sunDir : game.sunDir)
        let dusk = vaultSky || hellSky ? 0 : max(0, 1 - abs(sd.y - 0.02) / 0.22)
        let skyGlow = vaultSky ? AshSky.glow : (hellSky ? HellSky.glow : (dusk * 0.9 + 0.12 * daylight) * (1 - min(1, game.weather.rain)))
        let fogGlow: Float = (!underwater && !underground && hasSky && game.blindFog == nil) ? min(0.99, skyGlow) : 0
        var u = FrameUniforms()
        u.viewProj = (cam.viewProj[0], cam.viewProj.count > 1 ? cam.viewProj[1] : cam.viewProj[0])
        u.invViewProj = (u.viewProj.0.inverse, u.viewProj.1.inverse)
        u.fogColor = V4(fogColor, fogStart)
        u.params = V4(fogEnd, daylight, Float(game.time.truncatingRemainder(dividingBy: 1000)), underwater ? 1 : 0)
        u.waves = V4(game.weather.swell, game.wetWorld ? min(1, game.weather.rain) : 0, 0, 0)
        u.sunDir = V4(sd, ambient)
        u.eye = V4(eye, fogGlow)
        u.zenith = V4(game.skyZenith * caveScale, Float(game.dayFraction * 2 * .pi))
        u.horizon = V4(underground ? fogColor : sky, skyGlow)
        u.starRot = rotationZ(Float(game.dayFraction * 2 * .pi))
        u.starTint = V4(1, 1, 1, game.starAlpha)                 // faint at sunset, full once the sun is well down
        // Clouds (clouds.frag, drawn over the stars, sun and moon): the eye in cloud space, cover and storm flashes.
        let sk = game.sky
        let cx = Double(eye.x) + sk.driftX, cz = Double(eye.z) + sk.driftZ
        u.clouds = V4(Float(cx), Float(cz), game.cloudCover, sk.flash)
        u.cloudFlash = V4(sk.flashDir, min(1, game.weather.rain * 0.55 + game.weather.thunder * 0.45))
        u.wind = V4(sk.wind.x, sk.wind.y, sk.haze, caveScale)
        // SH1: the shader pieces switched on, and the valley mist over open overworld sky, its top a few blocks over the
        // sea. P253: only in foggy weather (it lay in the low ground every dawn, dusk and night under a clear sky).
        let df = Float(game.dayFraction)
        let mist: Float = hasSky && !underground && !underwater ? game.valleyMist : 0
        // Colour grade: warm round sunrise and sunset, cool through the night, nudged by the biome's temperature (deserts
        // warmer, snow cooler); none underground or out of the overworld's sky.
        let warmT: Float = df < 0.07 ? 0.8 * (1 - df / 0.07) : (df > 0.42 && df < 0.55 ? 0.8 * (1 - abs(df - 0.48) / 0.07) : 0)
        let nightT: Float = df > 0.52 && df < 0.98 ? -0.55 * min(1, min(df - 0.52, 0.98 - df) / 0.06) : 0
        let biomeT: Float = max(-0.2, min(0.25, (game.audio.biomeHere.info.temp - 0.7) * 0.25))
        let grade: Float = hasSky && !underground && !underwater && game.dim.dim == .overworld ? max(-1, min(1, max(0, warmT) + nightT + biomeT)) : 0
        u.fx = V4(Float(Settings.shared.shaderFX), mist, Float(SEA + 8), grade)
        if sheenBits.isEmpty { sheenBits = ShaderFX.sheenBits() }
        withUnsafeMutableBytes(of: &u.sheen) { raw in
            let p = raw.bindMemory(to: UInt32.self)
            for i in 0..<min(p.count, sheenBits.count) { p[i] = sheenBits[i] }
        }
        let skyKind: Float = underwater || underground || game.blindFog != nil ? 0 : (hasSky || vaultSky || hellSky ? 1 : (game.dim.dim == .end ? 2 : 0))
        // Eye darkness: skylight 13.5+ around the eye (daylight, near the surface) 0 ... 4.5 or less (caves, deep dives) 1;
        // a wide ramp so the fill grows in step with the walls darkening.
        let ek = simd_clamp((caveK - 0.3) / 0.6, 0, 1)
        let dark = 1 - ek * ek * (3 - 2 * ek)
        u.misc = V4(skyKind, game.dim.dim.hasSky ? dark : 1, scene.linearOutput ? 2.2 : 1, QuestSettings.brightness)
        // Mobs, dropped items and the held item are lit on the CPU (writeMobVertices): give them the same cave fill as
        // the terrain around them (chunk.vert: (0.06 + 0.3 Brightness) x 2, by eye darkness). The Quest never set these
        // (the Mac's Renderer does), so mobs kept the 0.21 default fill and looked black against filled cave walls.
        let eyeDark: Float = game.dim.dim.hasSky ? dark : 1
        MobLight.fill = (0.06 + 0.3 * QuestSettings.brightness) * 2 * eyeDark
        MobLight.nightVision = nv
        let clear = game.blindFog != nil ? V3(0, 0, 0) : (p.headInLava ? Game.lavaFog : (underwater ? game.underwaterFog : (underground ? fogColor : sky)))
        return (u, clear)
    }

    // Records the whole world pass into `t` (the caller submits).
    func record(_ s: SceneRenderer.Slot, _ t: RenderTarget, _ cam: EyeCamera) {
        let t0 = CFAbsoluteTimeGetCurrent()
        var tm = t0
        func stage(_ i: Int) { let n = CFAbsoluteTimeGetCurrent(); stageSums[i] += n - tm; tm = n }
        defer {
            joinMobs()                                           // (never left running into the next frame)
            stageFrames += 1
            for i in stageSums.indices { stageFrame[i] = (stageSums[i] - stagePrev[i]) * 1000; stagePrev[i] = stageSums[i] }
            frameCPUMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            stageWorst = max(stageWorst, frameCPUMs)
        }
        updateCave(cam.center)
        updateUnderground(cam.center)
        let (u, clear) = uniforms(cam)
        scene.maxSection = game.skyCutSection         // the vault's roof, and hell's (P342), are left to the sky
        scene.fogCull = game.inVaultSky && !game.player.headInWater && !game.player.headInLava ? AshSky.fogEnd + 8 : 0
        if game.dim.dim.hasSky, !game.player.headInWater, let cap = World.caveSight(caveK: underground ? 0 : caveK) {
            scene.fogCull = scene.fogCull > 0 ? min(scene.fogCull, cap + 4) : cap + 4      // far sections past the cave fog
        }
        scene.sealCull = game.dim.dim.hasSky && !underground          // (P392: the buried far caves left out above ground)
        scene.setUniforms(s, u)
        scene.resetScratch()
        let eye = cam.center
        let frustum = Frustum(cam.cullViewProj * translationMatrix(-eye))
        scene.occlusionVP = cam.cullViewProj * translationMatrix(-eye)          // (P376 step 5)
        stage(0)
        startMobs(s, eye, frustum)
        stage(12)
        scene.cull(game.world, eye: eye, frustum: frustum)
        // (the cull's own split, the rest of the cull call under "list"; all of it under "walk" when the table is off)
        let cs = scene.cullStageMs, cullSec = CFAbsoluteTimeGetCurrent() - tm, csSum = cs.reduce(0, +)
        if csSum > 0 {
            for i in 0..<5 { stageSums[1 + i] += cs[i] / 1000 }
            stageSums[5] += max(0, cullSec - csSum / 1000)
            tableReads += scene.tableRefreshed; rasterSum += scene.occRasterMs
        } else { stageSums[2] += cullSec }
        tm = CFAbsoluteTimeGetCurrent()
        scene.writeRecords(s, eye: eye)
        stage(6)
        // (the mob worker is joined in drawMobs: the panel, the terrain, the ring, ships and landmarks don't touch the
        // mob models' shared state, so the worker has until then)
        if !WorldRenderer.debugSkip.contains("prepass") { prePass?(s) }
        stage(7)
        scene.beginPass(s, t, clear: clear)
        let skip = WorldRenderer.debugSkip
        if !skip.contains("opaque") { scene.drawOpaque(s) }
        stage(8)
        if !skip.contains("far") { drawFarRing(s, eye) }
        stage(9)
        if !skip.contains("ships") { ships.drawOpaque(s, ships: game.world.ships, eye: eye, u: u, frustum: frustum) }
        stage(10)
        if !skip.contains("landmarks") { drawLandmarks(s, eye, far: cam.far, fogColor: V3(u.fogColor.x, u.fogColor.y, u.fogColor.z)) }
        stage(11)
        if !skip.contains("mobs") { drawMobs(s, eye, frustum) }
        stage(12)
        camYaw = cam.yaw; camPitch = cam.pitch
        particleSec = 0
        if !skip.contains("entities") { drawEntities(s, eye) }
        stageSums[13] -= particleSec; stageSums[14] += particleSec
        stage(13)
        if !skip.contains("outline") { drawOutline(s, eye) }
        if !skip.contains("extra") { extraOpaque?(s, eye) }
        stage(17)
        if !skip.contains("ships") { ships.drawBeforeWater(s, ships: game.world.ships, world: game.world, eye: eye, frustum: frustum) }
        stage(10)
        if !skip.contains("sky") { drawSkyLayer(s, eye) }
        stage(15)
        if !skip.contains("landmarks") && !skip.contains("smoke") { drawLandmarkSmoke(s) }
        stage(11)
        if !skip.contains("trans") { scene.drawTranslucent(s, underwater: game.player.headInWater) }
        stage(16)
        if !skip.contains("ships") { ships.drawTranslucent(s, ships: game.world.ships, eye: eye, u: u, frustum: frustum) }
        stage(10)
        if !skip.contains("overlay") { extraOverlay?(s, eye) }
        stage(17)
    }
    private var particleSec = 0.0

    // F4: the middle ring after the opaque terrain (the loaded chunks win the depth test; far.vert sinks the ring under
    // them) and before the landmarks and the sky (its depth hides the horizon shell and the sky dome behind it).
    private func drawFarRing(_ s: SceneRenderer.Slot, _ eye: V3) {
        farFrame += 1
        farRingQuads = 0
        guard farRingOn else { return }
        let ring = FarRing.shared
        ring.request(game, eye: eye)
        if let m = ring.current(), m.seed == game.world.seed, m.gen != farGen, m.quads > 0 {
            let k = farLive < 0 ? 0 : 1 - farLive
            let bytes = m.verts.count * MemoryLayout<SimpleVert>.stride
            if farFrame - farUsed[k] >= 3 {
                if farBufs[k] == nil || farBufs[k]!.size < bytes {
                    // Room for a bigger ring (a higher render distance) up front: replaced only when a build outgrows it.
                    farBufs[k] = nil
                    farBufs[k] = try? VkBuf(scene.ctx, size: max(bytes * 5 / 4, 1 << 21), usage: VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.rawValue, host: true)
                }
                if let b = farBufs[k], let p = b.mapped {
                    m.verts.withUnsafeBytes { src in _ = memcpy(p, src.baseAddress!, bytes) }
                    farLive = k; farQuads = m.quads; farGen = m.gen; farOrigin = (m.cx, m.cz); farSeed = m.seed
                }
            }
        }
        guard farLive >= 0, farSeed == game.world.seed, farQuads > 0, let b = farBufs[farLive] else { return }
        farUsed[farLive] = farFrame
        let pcx = floorDiv(Int(floor(eye.x)), CS), pcz = floorDiv(Int(floor(eye.z)), CS)
        let ox: Float = Float(farOrigin.0) - eye.x, oz: Float = Float(farOrigin.1) - eye.z
        let lx: Float = Float(pcx * CS + CS / 2) - eye.x, lz: Float = Float(pcz * CS + CS / 2) - eye.z
        // P250 (c): sunk only inside the chunks that are meshed now, not the nominal render distance: while chunks
        // stream in (fast flight, a distance raised, a world opening) the ring keeps its true height where they are
        // still missing, instead of a 12-block pit with sloped walls showing through the gap (his 11:58 "slopes").
        if farFrame % 6 == 1 || farCover <= 0 {
            farCover = FarRing.meshedRadius(game.world, game.world.renderDistance, center: ChunkKey(x: pcx, z: pcz))
        }
        let rin = farCover
        let params = float4x4(columns: (V4(ox, -eye.y, oz, 0), V4(lx, lz, rin, 12), V4(0, 0, 0, 0), V4(0, 0, 0, 0)))
        scene.drawFar(s, b, quads: farQuads, params: params)
        farRingQuads = farQuads
    }

    // Opaque cones / spires (depth-writing, so the sky goes behind them) here; their blended smoke after the sky
    // (drawLandmarkSmoke: it writes no depth, so the sky drawn after it covered every volcano plume on the Quest).
    private var landmarkSmoke: (buffer: VkBuffer?, offset: Int, count: Int)?      // (nil buffer: the scratch ring)
    private func drawLandmarks(_ s: SceneRenderer.Slot, _ eye: V3, far: Float, fogColor: V3) {
        landmarkSmoke = nil                         // before the guard: never a stale offset from an earlier frame
        // (Not underground: past the cave fog's section cull the far-plane impostors showed down long tunnels, R18.)
        guard let host = landmarkHost, far > 0, game.dim.dim.hasSky, !game.player.headInWater, !underground else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        defer { landmarkMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000 }
        // With the middle ring up (F4) the impostors and the horizon shell still go on the far-plane shell, now behind
        // the ring (the far plane moved out past its rim): its depth hides them wherever it has ground, the volcano
        // plumes and peaks still rise over it, and past its rim the shell carries the horizon on.
        // P283: rebuilt every 6th frame (every 2nd while a volcano's smoke rises in it), or once the eye has moved a block
        // or the far plane changed (it cost 1.2 ms of every frame's record, rebuilt each frame): the shell sits near the
        // far plane, where a block of eye travel moves it a twentieth of a degree.
        // Behind the middle ring (F4) the nearest of it shows past the ring's rim, 1024 blocks out: 3 blocks of travel
        // there is a sixth of a degree, so a flight at full speed rebuilds it every third frame, not every frame.
        lmFrameNo += 1
        // P374: standing still, the shell only follows the sun and the weather: every half second (each build cost
        // 3 ms of a frame at Stone Gulch, 0.55 ms a frame on average at a 6-frame beat).
        let every = !TickProf.lighter ? 1 : (Renderer.plumeRising ? 2 : 36)
        let move: Float = TickProf.lighter && FarRing.enabled ? 9 : 1
        // (P374: an empty build, no horizon or landmark in range, waits its turn like any other: it was redone every
        // frame, 0.5 ms of each frame's record at the camp and Stone Gulch.)
        // P385: while smoke rises (every 2nd frame) only the landmarks and the smoke are rebuilt, over the horizon ground
        // of the last full build; the ground itself at the standing beat (36 frames), or once the eye moved or the far
        // plane changed. BS_LMSPLIT=0: whole builds, as before.
        let moved = simd_length_squared(eye - lmEye) > move || far != lmFar
        if moved || lmFrameNo - lmBuilt >= every {
            let full = moved || !WorldRenderer.lmSplit || lmFrameNo - lmFull >= (TickProf.lighter ? 36 : 1)
            landmarkVerts.removeAll(keepingCapacity: true)
            if !full { landmarkVerts.append(contentsOf: lmHorizon) }
            var smokeStart = 0
            host.buildLandmarks(&landmarkVerts, smokeStart: &smokeStart, game: game, eye: eye, far: far, fog: fogColor,
                                rd: Float(game.world.renderDistance), horizon: full)
            if full {
                lmHorizon.removeAll(keepingCapacity: true)
                lmHorizon.append(contentsOf: landmarkVerts[0..<Renderer.horizonEnd])
                lmEye = eye; lmFar = far; lmFull = lmFrameNo
            }
            lmSmokeStart = smokeStart; lmBuilt = lmFrameNo
        }
        let smokeStart = lmSmokeStart
        let stride = MemoryLayout<SimpleVert>.stride
        // P283: a build goes into one of three vertex buffers of its own (one out of use for 3 frames: both frames in
        // flight are done with it) and is drawn from there until the next, instead of copying the whole shell into the
        // frame's scratch ring every frame (0.4 ms of each frame's record on the replay).
        if lmBuilt == lmFrameNo { lmLive = TickProf.lighter ? lmStore(landmarkVerts) : -1 }
        if lmLive >= 0, let b = lmBufs[lmLive] {
            lmUsed[lmLive] = lmFrameNo
            if smokeStart > 0 { scene.drawBuffer(s, "simpleSolid", b.buffer, offset: 0, count: smokeStart) }
            if landmarkVerts.count > smokeStart { landmarkSmoke = (b.buffer, smokeStart * stride, landmarkVerts.count - smokeStart) }
        } else if let off = scene.push(s, landmarkVerts) {
            if smokeStart > 0 { scene.drawScratch(s, "simpleSolid", offset: off, count: smokeStart) }
            if landmarkVerts.count > smokeStart { landmarkSmoke = (nil, off + smokeStart * stride, landmarkVerts.count - smokeStart) }
        }
        landmarkCount = landmarkVerts.count
    }
    private var lmFrameNo = 0, lmBuilt = -100, lmSmokeStart = 0, lmEye = V3(1e9, 0, 0), lmFar: Float = 0
    private var lmFull = -100, lmHorizon: [SimpleVert] = []
    static var lmSplit = ProcessInfo.processInfo.environment["BS_LMSPLIT"] != "0"
    private var lmBufs: [VkBuf?] = [nil, nil, nil], lmUsed = [-10, -10, -10], lmLive = -1
    // The build into a buffer none of the frames in flight reads (index), or -1 (drawn from the scratch ring this time).
    private func lmStore(_ verts: [SimpleVert]) -> Int {
        guard !verts.isEmpty else { return -1 }
        let bytes = verts.count * MemoryLayout<SimpleVert>.stride
        guard let k = (0..<3).first(where: { $0 != lmLive && lmFrameNo - lmUsed[$0] >= 3 }) else { return -1 }
        if lmBufs[k] == nil || lmBufs[k]!.size < bytes {
            lmBufs[k] = nil
            lmBufs[k] = try? VkBuf(scene.ctx, size: max(bytes * 5 / 4, 1 << 20), usage: VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.rawValue, host: true)
        }
        guard let b = lmBufs[k], let p = b.mapped else { return -1 }
        verts.withUnsafeBytes { src in _ = memcpy(p, src.baseAddress!, bytes) }
        return k
    }

    private func drawLandmarkSmoke(_ s: SceneRenderer.Slot) {
        guard let sm = landmarkSmoke else { return }
        landmarkSmoke = nil
        if let b = sm.buffer { scene.drawBuffer(s, "simple", b, offset: sm.offset, count: sm.count) }
        else { scene.drawScratch(s, "simple", offset: sm.offset, count: sm.count) }
    }

    private func drawSkyLayer(_ s: SceneRenderer.Slot, _ eye: V3) {
        let underwater = game.player.headInWater
        let hasSky = game.dim.dim.hasSky
        scene.drawSky(s)
        let daylight = game.renderDaylight
        if !underwater && hasSky && simd_clamp((0.6 - daylight) / 0.35, 0, 1) > 0 { scene.drawStars(s) }
        if !underwater && hasSky {
            let sd = game.sunDir
            let dusk = max(0, 1 - abs(sd.y - 0.02) / 0.22)
            let (ptr, off, cap) = scene.reserve(s, EntityVert.self, max: 12)
            guard cap >= 12 else { return }
            var bw = EntityWriter(out: ptr, capacity: 12)
            func body(_ dir: V3, _ size: Float, _ layer: Int, _ color: V4) {
                // P202 (Oct 13 18:34, "the moon is visible through the ground"): the bodies sit on the far plane, so past
                // the drawn terrain (high up, far valleys, the horizon band) nothing hid one below the horizon. They
                // fade out as they set and are not drawn under it.
                let vis = simd_clamp((dir.y + 0.07) / 0.1, 0, 1)
                guard vis > 0 else { return }
                var color = color; color.w *= vis
                let c = dir * 90
                let r = simd_normalize(simd_cross(dir, V3(0, 0, 1))) * size
                let up = simd_normalize(simd_cross(r, dir)) * size
                bw.quad([c - r - up, c + r - up, c + r + up, c - r + up], [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)], layer, color)
            }
            body(sd, 7, Int(Tex.id("sun")), V4(1, 1 - 0.3 * dusk, 1 - 0.55 * dusk, 1))
            body(-sd, 5, Int(Tex.id("moon_\(game.moonPhase)")), V4(1, 1, 1, 1))
            scene.commit(off, bw.n, EntityVert.self)
            scene.drawScratch(s, "body", offset: off, count: bw.n)
            if QuestSettings.clouds && !WorldRenderer.debugSkip.contains("clouds") && game.dim.dim == .overworld && game.blindFog == nil {
                scene.drawClouds(s)
            }
        } else if !underwater && !game.player.headInLava, let body = game.ownSkyBody {
            // The Cinder Sun over the Ash Vault (big, dull and red through the haze), hell's Ember Moon (P342).
            let (ptr, off, cap) = scene.reserve(s, EntityVert.self, max: 6)
            guard cap >= 6 else { return }
            var bw = EntityWriter(out: ptr, capacity: 6)
            let d = body.dir, c = d * 90
            let r = simd_normalize(simd_cross(d, V3(0, 0, 1))) * body.size
            let up = simd_normalize(simd_cross(r, d)) * body.size
            bw.quad([c - r - up, c + r - up, c + r + up, c - r + up], [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)], Int(Tex.id("moon_0")), body.tint)
            scene.commit(off, bw.n, EntityVert.self)
            scene.drawScratch(s, "body", offset: off, count: bw.n)
        }
    }

    // Off-screen mobs past 64 blocks and mobs beyond the fog are skipped, as on the Mac (Renderer.mobMaxDist): every
    // loaded mob was rebuilt each frame, ~200 at render distance 14.
    // Past the vault's fog (scene.fogCull) a unit is the fog colour: not drawn.
    var mobMaxDist: Float {
        // P339: mobs are drawn out to the whole view (past the active distance in their last pose).
        let rd = Float(game.world.renderDistance * CS + 24)
        return scene.fogCull > 0 && !SceneRenderer.fogCullOff ? min(rd, scene.fogCull) : rd
    }
    private func drawMobs(_ s: SceneRenderer.Slot, _ eye: V3, _ frustum: Frustum) {
        let tp = game.cameraMode != 0
        let others = game.coop.active || game.netGuest != nil          // C14: the other player's body
        // P385: the worker's mobs (startMobs), then the player's body and the other players' after them in its buffer.
        if let b = mobPending, let p = b.mapped {
            joinMobs()
            mobPending = nil
            let cap = WorldRenderer.mobBufBytes / MemoryLayout<MobVert>.stride
            let ptr = p.bindMemory(to: MobVert.self, capacity: cap)
            var n = mobCount
            if tp { n += writePlayerModel(game, eye: eye, daylight: game.renderDaylight, into: ptr + n, capacity: cap - n) }
            if others {
                n += game.coop.writeOthers(game, eye: eye, daylight: game.renderDaylight, into: ptr + n, capacity: cap - n)
                n += NetCoop.writeRemote(game, eye: eye, daylight: game.renderDaylight, into: ptr + n, capacity: cap - n)
            }
            lastMobVerts = n
            scene.drawBuffer(s, "mob", b.buffer, offset: 0, count: n)
            addMobMotion(s, b.buffer, offset: 0)
            return
        }
        guard !game.mobs.mobs.isEmpty || !game.mobs.corpses.isEmpty || !Hunting.bodyMobs.isEmpty || !AshFallen.mobs.isEmpty || !AshWrecks.mobs.isEmpty || !AshWrecks.skinMobs.isEmpty || tp || others else { return }   // (P326: the vault's fallen with no mob about)
        let (ptr, off, cap) = scene.reserve(s, MobVert.self)
        guard cap > 36 else { return }
        Mob.settleLooks(game.mobs.mobs, game.world)                                         // P411
        MobMotion.on = scene.spaceWarpOn; MobMotion.ranges.removeAll(keepingCapacity: true)    // P403 7b
        var n = writeMobVertices(game.mobs.mobs, eye: eye, daylight: game.renderDaylight, world: game.world, into: ptr, capacity: cap,
                                 cull: frustum, maxDist: mobMaxDist, corpses: game.mobs.corpses,
                                 ragdolls: game.debris.ragdolls)
        if tp { n += writePlayerModel(game, eye: eye, daylight: game.renderDaylight, into: ptr + n, capacity: cap - n) }
        if others {
            n += game.coop.writeOthers(game, eye: eye, daylight: game.renderDaylight, into: ptr + n, capacity: cap - n)
            n += NetCoop.writeRemote(game, eye: eye, daylight: game.renderDaylight, into: ptr + n, capacity: cap - n)
        }
        lastMobVerts = n
        scene.commit(off, n, MobVert.self)
        scene.drawScratch(s, "mob", offset: off, count: n)
        addMobMotion(s, nil, offset: off)
    }
    // P403 7b: each moving mob's vertices again, into the space warp's motion vectors (MobMotion).
    private func addMobMotion(_ s: SceneRenderer.Slot, _ buffer: VkBuffer?, offset: Int) {
        guard MobMotion.on else { return }
        let st = MemoryLayout<MobVert>.stride
        for r in MobMotion.ranges {
            scene.addMotion(s, .mob, buffer: buffer, offset: offset + Int(r.start) * st, count: Int(r.count), prev: SceneRenderer.motion(moved: r.moved))
        }
        MobMotion.ranges.removeAll(keepingCapacity: true)
    }

    private func drawEntities(_ s: SceneRenderer.Slot, _ eye: V3) {
        let (ptr, off, cap) = scene.reserve(s, EntityVert.self)
        guard cap > 64 else { return }
        var wr = EntityWriter(out: ptr, capacity: cap)
        let yaw = camYaw, pitch = camPitch
        let look = V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
        let right = V3(cosf(yaw), 0, -sinf(yaw))
        let up = simd_normalize(simd_cross(right, look))
        let w = game.world, daylight = game.daylight
        game.drops.write(&wr, eye: eye, right: right, up: -up, world: w, daylight: daylight, time: Float(game.clock))
        game.projectiles.write(&wr, eye: eye, world: w, daylight: daylight)
        game.tnts.write(&wr, eye: eye, world: w, daylight: daylight)
        game.writeEndEntities(&wr, eye: eye, right: right, up: -up)
        game.writeFangs(&wr, eye: eye)
        game.writeBeams(&wr, eye: eye)
        game.writeFalling(&wr, eye: eye)
        w.ships.writeShells(&wr, eye: eye)
        game.writeDecor(&wr, eye: eye)
        game.writeBobber(&wr, eye: eye, right: right, up: -up)
        game.writeLeads(&wr, eye: eye)
        game.writeBanners(&wr, eye: eye)
        game.writeRockets(&wr, eye: eye)
        game.writeArms(&wr, eye: eye)
        game.writeLecternBooks(&wr, eye: eye)
        game.writeShelves(&wr, eye: eye)
        game.writeFelled(&wr, eye: eye)                                       // (P297 d: round felled trunks)
        game.debris.write(&wr, eye: eye, world: w, daylight: daylight)      // (R15: ragdolls and debris in every world)
        let tp0 = CFAbsoluteTimeGetCurrent()
        game.particles.write(&wr, eye: eye, right: right, up: -up, world: w, daylight: daylight)
        particleSec = CFAbsoluteTimeGetCurrent() - tp0
        let nItems = wr.n
        game.writeShadows(&wr, eye: eye)
        game.writeHalos(&wr, eye: eye, right: right, up: -up)          // SH1 light halos
        game.writeWeather(&wr, eye: eye)
        if let m = game.mining, game.mineProgress > 0, w.damageLevel(m) == 0, game.targetGround?.cell != m {      // (P297 b: not on polygon ground)
            let layer = HudTex.destroy(Int(game.mineProgress * 10))
            let o = V3(Float(m.x), Float(m.y), Float(m.z)) - eye
            let CT = Mesher.cornerTable
            let uvs = [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)]
            for (bmn, bmx) in w.selectionBoxes(w.block(m.x, m.y, m.z)) {
                let a = o + bmn - V3(repeating: 0.002), b = o + bmx + V3(repeating: 0.002)
                for f in 0..<6 {
                    var ps: [V3] = []
                    for k in 0..<4 {
                        let ci = (f * 4 + k) * 3
                        ps.append(V3(CT[ci] == 1 ? b.x : a.x, CT[ci + 1] == 1 ? b.y : a.y, CT[ci + 2] == 1 ? b.z : a.z))
                    }
                    wr.quad(ps, uvs, layer, V4(1, 1, 1, 0.9))
                }
            }
        }
        scene.commit(off, wr.n, EntityVert.self)
        let stride = MemoryLayout<EntityVert>.stride
        scene.drawScratch(s, "entity", offset: off, count: nItems)
        if wr.n > nItems { scene.drawScratch(s, "crack", offset: off + nItems * stride, count: wr.n - nItems) }
    }

    // Target block outline: thin dark boxes (quads, so they read in the headset where 1-pixel lines shimmer).
    private func drawOutline(_ s: SceneRenderer.Slot, _ eye: V3) {
        let pe = game.player.eye
        let eyeCell = IVec3(Int(floor(pe.x)), Int(floor(pe.y)), Int(floor(pe.z)))
        guard let t = game.target, t.hit != eyeCell || game.targetGround != nil else { return }
        var verts: [SimpleVert] = []
        let col = V4(0.02, 0.02, 0.02, 0.75)
        // P297 (b): polygon ground has no block outline: a thin ring lies on the surface where you aim, and while you dig
        // a pale arc runs round it as the ground gives (no crack box either).
        if let ring = game.groundMarkRing() {
            let n = ring.count
            let done = game.mining == t.hit ? Int(game.mineProgress * Float(n)) : 0
            for k in 0..<n {
                let p0 = ring[k] - eye, p1 = ring[(k + 1) % n] - eye
                let dir = simd_normalize(p1 - p0)
                var side = simd_cross(dir, simd_normalize((p0 + p1) * 0.5))
                if simd_length_squared(side) < 1e-6 { side = simd_cross(dir, V3(0, 1, 0)) }
                let lit = k < done
                side = simd_normalize(side) * (lit ? 0.011 : 0.007)
                let c = lit ? V4(0.92, 0.9, 0.84, 0.85) : col
                let q = [p0 - side, p1 - side, p1 + side, p0 + side]
                for i in [0, 1, 2, 0, 2, 3] { verts.append(SimpleVert(pos: V4(q[i], 1), color: c)) }
            }
            if let off = scene.push(s, verts) { scene.drawScratch(s, "simple", offset: off, count: verts.count) }
            return
        }
        let o = V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) - eye
        let edges = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
        for (bmn, bmx) in game.world.selectionBoxes(game.world.block(t.hit.x, t.hit.y, t.hit.z)) {
            let a = o + bmn - V3(repeating: 0.004), b = o + bmx + V3(repeating: 0.004)
            let cs = [V3(a.x, a.y, a.z), V3(b.x, a.y, a.z), V3(b.x, a.y, b.z), V3(a.x, a.y, b.z),
                      V3(a.x, b.y, a.z), V3(b.x, b.y, a.z), V3(b.x, b.y, b.z), V3(a.x, b.y, b.z)]
            let mid = (a + b) * 0.5
            for k in stride(from: 0, to: edges.count, by: 2) {
                let p0 = cs[edges[k]], p1 = cs[edges[k + 1]]
                // A ribbon around the edge, facing the camera (width 1.2 cm, pushed slightly outward).
                let dir = simd_normalize(p1 - p0)
                let center = (p0 + p1) * 0.5
                var side = simd_cross(dir, simd_normalize(center))
                if simd_length_squared(side) < 1e-6 { side = simd_cross(dir, V3(0, 1, 0)) }
                side = simd_normalize(side) * 0.006
                let out = simd_normalize(center - mid) * 0.002
                let q = [p0 - side + out, p1 - side + out, p1 + side + out, p0 + side + out]
                for i in [0, 1, 2, 0, 2, 3] { verts.append(SimpleVert(pos: V4(q[i], 1), color: col)) }
            }
        }
        if let off = scene.push(s, verts) { scene.drawScratch(s, "simple", offset: off, count: verts.count) }
    }
}
