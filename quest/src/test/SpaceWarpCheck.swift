import Foundation
import simd
import Metal
import CVulkan

// P403 7b (questcheck --spacewarp): Application SpaceWarp's motion-vector pass on any Vulkan device. A cow 4 m ahead
// is drawn two frames running with space warp on, 0.3 m further east the second time; the motion vectors read back
// must move where the cow is (eastward on screen) and stay zero on the still ground around it.
enum SpaceWarpCheck {
    static func run(ctx: VkContext) -> Int32 {
        do { return try check(ctx, scale: 1) | check(ctx, scale: 0.8) | dynres() } catch { print("FAIL spacewarp: \(error)"); return 1 }
    }
    // P403 7b: DynamicResolution against a GPU that pays for pixels (40 ms at full size) and one that pays for
    // triangles (40 ms at any size), both over a 27.8 ms budget: the first settles at the largest scale that fits,
    // the second drops once, finds nothing gained, and goes back to full resolution.
    private static func dynres() -> Int32 {
        var a = DynamicResolution(), b = DynamicResolution()
        var sa: Float = 1, sb: Float = 1, minB: Float = 1
        for _ in 0..<600 {
            sa = a.observe(gpuMs: 40 * Double(sa * sa), budgetMs: 27.8, enabled: true, fps: 36)
            sb = b.observe(gpuMs: 40, budgetMs: 27.8, enabled: true, fps: 36)
            minB = min(minB, sb)
        }
        print(String(format: "dynres: pixel-bound settles at %.2f (%d drops), triangle-bound at %.2f (lowest %.2f, %d taken back)",
                     sa, a.drops, sb, minB, b.takenBack))
        var ok = sa >= 0.74 && sa <= 0.81 && sb == 1 && b.takenBack >= 1
        // P498: his Oct 30 captures at 72 Hz, nearly all pixels (31-175k quads): the grove at 15:15 (GPU 20.0 ms at
        // full size) and the village at 15:01 (25.9 ms, the worst), walking: each frame's time swings +-15 % round a
        // scene that drifts +-10 % every few seconds. Frames over the 13.9 ms budget in the last 15 of 20 s, and how
        // soon the first frame fits. The grove must hold; the village is reported (at 70 % its pixels alone are the
        // budget, so the ground shader's own cost has to come down too).
        for (name, full) in [("grove 15:15", 19.97), ("village 15:01", 25.89)] {
            var c = DynamicResolution(), sc: Float = 1, rng: UInt64 = 0x9E3779B97F4A7C15
            var late = 0, over = 0, first = -1, lo: Float = 1
            for f in 0..<(72 * 20) {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                let jitter = 0.85 + 0.3 * Double(rng >> 11) / Double(1 << 53)
                let drift = 1 + 0.1 * sin(Double(f) / 72 * 1.3)
                let px = Double(sc * sc)
                let gpu = full * (0.08 + 0.92 * px) * jitter * drift
                if gpu <= 1000.0 / 72 && first < 0 { first = f }
                if f >= 72 * 5 { late += 1; if gpu > 1000.0 / 72 { over += 1 } }
                sc = c.observe(gpuMs: gpu, budgetMs: 1000.0 / 72, enabled: true, fps: 72)
                lo = min(lo, sc)
            }
            print("dynres: \(name) " + String(format: "(%.1f ms full) walking at 72 Hz: first frame in the budget after %.2f s, then %d of %d frames over (%.0f%%), scale %.2f (lowest %.2f), %d drops, %d taken back",
                         full, Double(first) / 72, over, late, Double(over) * 100 / Double(late), sc, lo, c.drops, c.takenBack))
            if full < 21 { ok = ok && first >= 0 && first < 72 && Double(over) / Double(late) < 0.1 && c.takenBack == 0 }
        }
        print(ok ? "dynres: ok" : "FAIL dynres")
        return ok ? 0 : 1
    }
    private static func check(_ ctx: VkContext, scale: Float) throws -> Int32 {
        let w = World(seed: 12345, device: sharedSystemDevice, save: nil, dim: .overworld)
        w.renderDistance = 2
        let g = Game(world: w, save: nil, persistent: false)
        _ = w.loadSync(center: g.player.pos, radius: 2)
        g.mobs.mobs.removeAll()
        let scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM, spaceWarp: true)
        scene.spaceWarpOn = true                  // (P426: the Options switch, on for the check)
        try scene.uploadTextures()
        let wr = WorldRenderer(scene: scene, game: g)
        scene.viewScale = scale
        let size = 256, mvSize = 128
        let img = try VkImg(ctx, width: size, height: size, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue)
        let target = try scene.makeTarget(image: img.image, width: size, height: size)
        let mv = try VkImg(ctx, width: mvSize, height: mvSize, layers: 2, format: VK_FORMAT_R16G16B16A16_SFLOAT,
                           usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        let df = VK_FORMAT_D32_SFLOAT
        let dimg = try VkImg(ctx, width: mvSize, height: mvSize, layers: 2, format: df, usage: VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue,
                             aspect: VK_IMAGE_ASPECT_DEPTH_BIT.rawValue)
        let pass = try SpaceWarpPass(scene: scene, mvImages: [mv.image], depthImages: [dimg.image], width: mvSize, height: mvSize, depthFormat: df)
        let readback = try VkBuf(ctx, size: mvSize * mvSize * 8, usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue, host: true)
        defer { scene.waitIdle(); withExtendedLifetime((img, target, mv, dimg, pass, readback)) {} }
        // Eye level over the ground, looking north and a little down at a cow standing 4 m ahead.
        let ground = Float(w.topY(Int(floor(g.player.pos.x)), Int(floor(g.player.pos.z)) - 4) + 1)
        let eye = V3(g.player.pos.x, ground + 1.62, g.player.pos.z)
        g.player.pos = eye - V3(0, g.player.eyeHeight, 0)
        let cow = Mob(.cow, at: V3(eye.x, ground, eye.z - 4))
        g.mobs.mobs.append(cow)
        let t: Float = 1
        let proj = XRMath.projection(tanLeft: -t, tanRight: t, tanUp: t, tanDown: -t, near: 0.05, far: 96)
        let head = simd_quatf(angle: -0.25, axis: V3(1, 0, 0))
        let vps = [-0.032, 0.032].map { (e: Float) in proj * XRMath.inversePose(head, head.act(V3(e, 0, 0))) }
        let cam = EyeCamera(center: g.player.eye, viewProj: vps, cullViewProj: proj * XRMath.inversePose(head, .zero), yaw: 0, pitch: -0.25, far: 96)
        var motion: [Float] = []
        for fi in 0..<2 {
            if fi == 1 { cow.pos.x += 0.3 }
            cow.vel = .zero
            let s = scene.beginFrame()
            wr.record(s, target, cam)
            vkCmdEndRenderPass(s.cmd)
            pass.record(s, target, mvIndex: 0, depthIndex: 0)
            if fi == 1 {
                vkBarrier(s.cmd, mv.image, from: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, layers: 2,
                          srcAccess: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue, dstAccess: VK_ACCESS_TRANSFER_READ_BIT.rawValue,
                          srcStage: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue, dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
                var r = VkBufferImageCopy()
                r.imageSubresource = VkImageSubresourceLayers(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, mipLevel: 0, baseArrayLayer: 0, layerCount: 1)
                r.imageExtent = VkExtent3D(width: UInt32(mvSize), height: UInt32(mvSize), depth: 1)
                vkCmdCopyImageToBuffer(s.cmd, mv.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &r)
            }
            try scene.submit(s)
            scene.waitIdle()
            if fi == 1 {
                let p = readback.mapped!.bindMemory(to: UInt16.self, capacity: mvSize * mvSize * 4)
                motion = (0..<(mvSize * mvSize)).map { Float(Float16(bitPattern: p[$0 * 4])) }
            }
        }
        let moving = motion.filter { $0 > 0.01 }.count, backward = motion.filter { $0 < -0.01 }.count
        let drawn = scene.motionDraws.count
        print("spacewarp (eyes at \(Int(scale * 100))%): \(drawn) motion draws, \(moving) of \(mvSize * mvSize) motion-vector pixels move east, \(backward) west")
        // The cow covers a few hundred of the 16k pixels; the ground and sky around it stay still.
        let ok = drawn >= 1 && moving > 30 && moving < mvSize * mvSize / 3 && backward == 0
        print(ok ? "spacewarp: ok" : "FAIL spacewarp: the moved cow's motion vectors are missing or spill")
        return ok ? 0 : 1
    }
}
