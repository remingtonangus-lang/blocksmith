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
    var extraOpaque: ((SceneRenderer.Slot, V3) -> Void)?     // hands, rays, panels (the XR layer)
    var extraOverlay: ((SceneRenderer.Slot, V3) -> Void)?    // drawn last (panels over everything)
    var prePass: ((SceneRenderer.Slot) -> Void)?              // offscreen passes before the world pass (the HUD panel)
    private(set) var frameCPUMs = 0.0
    private var camYaw: Float = 0, camPitch: Float = 0

    init(scene: SceneRenderer, game: Game) {
        self.scene = scene
        self.game = game
    }

    // Skylight at the eye, smoothed (Renderer.updateCave): fog and sky darken underground.
    private func updateCave(_ eye: V3) {
        guard game.dim.dim.hasSky else { caveK = 1; return }
        let target = Float(game.world.lightAt(Int(floor(eye.x)), Int(floor(eye.y)), Int(floor(eye.z))).sky) / 15
        caveK = caveK < 0 ? target : caveK + (target - caveK) * 0.04
    }
    var caveScale: Float { 0.08 + 0.92 * min(1, max(0, caveK) * 1.6) }

    func uniforms(_ cam: EyeCamera) -> (FrameUniforms, V3) {
        let p = game.player
        let eye = cam.center
        let rd = Float(game.world.renderDistance)
        let underwater = p.headInWater
        let sky = game.skyColor * caveScale
        let hasSky = game.dim.dim.hasSky
        let uwSee: Float = 18 + 38 * game.daylight * caveScale
        var fogEnd: Float = underwater ? uwSee : (game.dim.dim == .nether ? min(rd * 16 - 12, 96) : rd * 16 - 12)
        var fogStart: Float = underwater ? 1 : fogEnd * 0.62
        var fogColor = underwater ? game.underwaterFog : sky
        if p.headInLava { fogEnd = game.effects.has(.fireResistance) ? 6 : 2.5; fogStart = 0.2; fogColor = Game.lavaFog }
        if let bf = game.blindFog { fogEnd = min(fogEnd, bf); fogStart = bf * 0.2; fogColor = V3(0, 0, 0) }
        let daylight = game.daylight
        let nv = game.nightVision
        let ambient = 1 - (1 - game.dim.dim.ambient) * (1 - 0.85 * nv)
        let sd = game.sunDir
        let dusk = max(0, 1 - abs(sd.y - 0.02) / 0.22)
        let skyGlow = (dusk * 0.9 + 0.12 * daylight) * (1 - min(1, game.weather.rain))
        let fogGlow: Float = (!underwater && hasSky && game.blindFog == nil) ? min(0.99, skyGlow) : 0
        var u = FrameUniforms()
        u.viewProj = (cam.viewProj[0], cam.viewProj.count > 1 ? cam.viewProj[1] : cam.viewProj[0])
        u.invViewProj = (u.viewProj.0.inverse, u.viewProj.1.inverse)
        u.fogColor = V4(fogColor, fogStart)
        u.params = V4(fogEnd, daylight, Float(game.time.truncatingRemainder(dividingBy: 1000)), underwater ? 1 : 0)
        u.sunDir = V4(sd, ambient)
        u.eye = V4(eye, fogGlow)
        u.zenith = V4(game.skyZenith * caveScale, Float(game.dayFraction * 2 * .pi))
        u.horizon = V4(sky, skyGlow)
        u.starRot = rotationZ(Float(game.dayFraction * 2 * .pi))
        u.starTint = V4(1, 1, 1, simd_clamp((0.6 - daylight) / 0.35, 0, 1))
        let skyKind: Float = underwater || game.blindFog != nil ? 0 : (hasSky ? 1 : (game.dim.dim == .end ? 2 : 0))
        u.misc = V4(skyKind, 1, scene.linearOutput ? 2.2 : 1, 0)
        let clear = game.blindFog != nil ? V3(0, 0, 0) : (p.headInLava ? Game.lavaFog : (underwater ? game.underwaterFog : sky))
        return (u, clear)
    }

    // Records the whole world pass into `t` (the caller submits).
    func record(_ s: SceneRenderer.Slot, _ t: RenderTarget, _ cam: EyeCamera) {
        let t0 = CFAbsoluteTimeGetCurrent()
        updateCave(cam.center)
        let (u, clear) = uniforms(cam)
        scene.setUniforms(s, u)
        scene.resetScratch()
        let eye = cam.center
        let frustum = Frustum(cam.cullViewProj * translationMatrix(-eye))
        scene.cull(game.world, eye: eye, frustum: frustum)
        scene.writeRecords(s, eye: eye)
        prePass?(s)
        scene.beginPass(s, t, clear: clear)
        scene.drawOpaque(s)
        drawMobs(s, eye)
        camYaw = cam.yaw; camPitch = cam.pitch
        drawEntities(s, eye)
        drawOutline(s, eye)
        extraOpaque?(s, eye)
        drawSkyLayer(s, eye)
        scene.drawTranslucent(s)
        extraOverlay?(s, eye)
        frameCPUMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }

    private func drawSkyLayer(_ s: SceneRenderer.Slot, _ eye: V3) {
        let underwater = game.player.headInWater
        let hasSky = game.dim.dim.hasSky
        scene.drawSky(s)
        let daylight = game.daylight
        if !underwater && hasSky && simd_clamp((0.6 - daylight) / 0.35, 0, 1) > 0 { scene.drawStars(s) }
        if !underwater && hasSky {
            let sd = game.sunDir
            let dusk = max(0, 1 - abs(sd.y - 0.02) / 0.22)
            let (ptr, off, cap) = scene.reserve(s, EntityVert.self, max: 12)
            guard cap >= 12 else { return }
            var bw = EntityWriter(out: ptr, capacity: 12)
            func body(_ dir: V3, _ size: Float, _ layer: Int, _ color: V4) {
                let c = dir * 90
                let r = simd_normalize(simd_cross(dir, V3(0, 0, 1))) * size
                let up = simd_normalize(simd_cross(r, dir)) * size
                bw.quad([c - r - up, c + r - up, c + r + up, c - r + up], [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)], layer, color)
            }
            body(sd, 7, Int(Tex.id("sun")), V4(1, 1 - 0.3 * dusk, 1 - 0.55 * dusk, 1))
            body(-sd, 5, Int(Tex.id("moon_\(game.moonPhase)")), V4(1, 1, 1, 1))
            scene.commit(off, bw.n, EntityVert.self)
            scene.drawScratch(s, "body", offset: off, count: bw.n)
        }
    }

    private func drawMobs(_ s: SceneRenderer.Slot, _ eye: V3) {
        let tp = game.cameraMode != 0
        guard !game.mobs.mobs.isEmpty || tp else { return }
        let (ptr, off, cap) = scene.reserve(s, MobVert.self)
        guard cap > 36 else { return }
        var n = writeMobVertices(game.mobs.mobs, eye: eye, daylight: game.daylight, world: game.world, into: ptr, capacity: cap)
        if tp { n += writePlayerModel(game, eye: eye, daylight: game.daylight, into: ptr + n, capacity: cap - n) }
        scene.commit(off, n, MobVert.self)
        scene.drawScratch(s, "mob", offset: off, count: n)
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
        game.particles.write(&wr, eye: eye, right: right, up: -up, world: w, daylight: daylight)
        let nItems = wr.n
        game.writeShadows(&wr, eye: eye)
        game.writeWeather(&wr, eye: eye)
        if let m = game.mining, game.mineProgress > 0, w.damageLevel(m) == 0 {
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
        guard let t = game.target, t.hit != eyeCell else { return }
        let o = V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) - eye
        var verts: [SimpleVert] = []
        let col = V4(0.02, 0.02, 0.02, 0.75)
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
