import Foundation
import simd
import Metal
import CVulkan

// P403 7b (questcheck --spacewarp): Application SpaceWarp's motion-vector pass on any Vulkan device. A cow 4 m ahead
// is drawn two frames running with space warp on, 0.3 m further east the second time; the motion vectors read back
// must move where the cow is (eastward on screen) and stay zero on the still ground around it.
enum SpaceWarpCheck {
    static func run(ctx: VkContext) -> Int32 {
        do { return try check(ctx) } catch { print("FAIL spacewarp: \(error)"); return 1 }
    }
    private static func check(_ ctx: VkContext) throws -> Int32 {
        let w = World(seed: 12345, device: sharedSystemDevice, save: nil, dim: .overworld)
        w.renderDistance = 2
        let g = Game(world: w, save: nil, persistent: false)
        _ = w.loadSync(center: g.player.pos, radius: 2)
        g.mobs.mobs.removeAll()
        let scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM, spaceWarp: true)
        try scene.uploadTextures()
        let wr = WorldRenderer(scene: scene, game: g)
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
        print("spacewarp: \(drawn) motion draws, \(moving) of \(mvSize * mvSize) motion-vector pixels move east, \(backward) west")
        // The cow covers a few hundred of the 16k pixels; the ground and sky around it stay still.
        let ok = drawn >= 1 && moving > 30 && moving < mvSize * mvSize / 3 && backward == 0
        print(ok ? "spacewarp: ok" : "FAIL spacewarp: the moved cow's motion vectors are missing or spill")
        return ok ? 0 : 1
    }
}
