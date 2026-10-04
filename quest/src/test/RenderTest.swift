import Foundation
import simd
import Metal
import CVulkan

// Offscreen stereo render of the real world on any Vulkan device (lavapipe on Linux/CI): both eyes side by side into
// a PNG. Exercises the Quest renderer end to end (multiview, pipelines, textures, culling) without a headset.
enum RenderTest {
    static func render(game: Game, ctx: VkContext, path: String, width: Int = 640, height: Int = 640,
                       yaw: Float = 0, pitch: Float = -0.15, fovDeg: Float = 90) throws {
        let scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
        try scene.uploadTextures()
        let wr = WorldRenderer(scene: scene, game: game)
        let img = try VkImg(ctx, width: width, height: height, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        let target = try scene.makeTarget(image: img.image, width: width, height: height)
        // Stereo rig: 64 mm apart, symmetric field of view, head at the player's eye.
        let t = tanf(fovDeg * .pi / 360)
        let proj = XRMath.projection(tanLeft: -t, tanRight: t, tanUp: t, tanDown: -t, near: 0.05, far: Float(game.world.renderDistance * 16 + 96))
        let head = simd_quatf(angle: yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: pitch, axis: V3(1, 0, 0))
        var vps: [float4x4] = []
        for e in [-0.032, 0.032] as [Float] {
            let off = head.act(V3(e, 0, 0))
            vps.append(proj * XRMath.inversePose(head, off))
        }
        let center = game.player.eye
        game.player.yaw = yaw; game.player.pitch = pitch
        let cam = EyeCamera(center: center, viewProj: vps, cullViewProj: proj * XRMath.inversePose(head, .zero), yaw: yaw, pitch: pitch)
        let readback = try VkBuf(ctx, size: width * height * 4 * 2, usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue, host: true)
        var ms: [Double] = []
        for _ in 0..<3 {
            let s = scene.beginFrame()
            let a = CFAbsoluteTimeGetCurrent()
            wr.record(s, target, cam)
            vkCmdEndRenderPass(s.cmd)
            vkBarrier(s.cmd, img.image, from: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, layers: 2,
                      srcAccess: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue, dstAccess: VK_ACCESS_TRANSFER_READ_BIT.rawValue,
                      srcStage: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue, dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
            var r = VkBufferImageCopy()
            r.imageSubresource = VkImageSubresourceLayers(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, mipLevel: 0, baseArrayLayer: 0, layerCount: 2)
            r.imageExtent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
            vkCmdCopyImageToBuffer(s.cmd, img.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &r)
            try scene.submit(s)
            scene.waitIdle()
            ms.append((CFAbsoluteTimeGetCurrent() - a) * 1000)
        }
        print(String(format: "rendertest: %d sections visible, %d draws, %d quads; cull %.2f ms, CPU record %.2f ms, frame (lavapipe) %.0f ms",
                     scene.visibleCount, scene.drawCalls, scene.drawnQuads, scene.cullMs, wr.frameCPUMs, ms.last!))
        // Side by side, left eye first.
        let src = readback.mapped!.bindMemory(to: UInt8.self, capacity: width * height * 8)
        var out = [UInt8](repeating: 0, count: width * 2 * height * 4)
        for y in 0..<height { for e in 0..<2 { for x in 0..<width {
            let si = (e * width * height + y * width + x) * 4, di = (y * width * 2 + e * width + x) * 4
            out[di] = src[si]; out[di + 1] = src[si + 1]; out[di + 2] = src[si + 2]; out[di + 3] = 255
        } } }
        try PNG.encode(rgba: out, width: width * 2, height: height).write(to: URL(fileURLWithPath: path))
        print("rendertest: wrote \(path)")
        scene.waitIdle()
    }
}
