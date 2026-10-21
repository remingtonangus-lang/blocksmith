import Foundation
import simd
import Metal
import CVulkan

// Offscreen stereo render of the real world on any Vulkan device (lavapipe on Linux/CI): both eyes side by side into
// a PNG. Exercises the Quest renderer end to end (multiview, pipelines, textures, culling) without a headset.
enum RenderTest {
    static var landmarkVerts = 0          // impostor vertices in the last rendered frame
    static var drawnQuads = 0             // world quads drawn in the last rendered frame
    static var recordMs = 0.0             // CPU time recording the last frame's world
    static var lastRGBA: [UInt8] = []     // the last frame, both eyes side by side (width * 2 x height)
    static var lastFrameMs: Double = 0    // its lavapipe frame time
    // The last frame's draw load: sections, draw calls, terrain quads, CPU record ms, and mobs within the mob distance.
    static var lastStats: (sections: Int, draws: Int, quads: Int, recordMs: Double, mobsDrawn: Int, mobVerts: Int) = (0, 0, 0, 0, 0, 0)
    static var lastStages = ""            // where the record time went (WorldRenderer stages, ms per frame over the 3)
    static func render(game: Game, ctx: VkContext, path: String, width: Int = 640, height: Int = 640,
                       yaw: Float = 0, pitch: Float = -0.15, fovDeg: Float = 90) throws {
        let scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
        try scene.uploadTextures()
        let wr = WorldRenderer(scene: scene, game: game)
        wr.landmarkHost = Renderer(game: game)
        let img = try VkImg(ctx, width: width, height: height, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        // Two framebuffers on the image, alternated like the swapchain's.
        let targets = [try scene.makeTarget(image: img.image, width: width, height: height),
                       try scene.makeTarget(image: img.image, width: width, height: height)]
        // Stereo rig: 64 mm apart, symmetric field of view, head at the player's eye.
        let t = tanf(fovDeg * .pi / 360)
        // (As QuestApp.farPlane: the F4 middle ring reaches FarRing.outer in the overworld.)
        let ringFar: Float = FarRing.enabled && game.dim.dim == .overworld ? FarRing.outer + 96 : 0
        let far = max(Float(game.world.renderDistance * 16 + 96), ringFar)
        let tv = t * Float(height) / Float(width)           // (square pixels for a non-square shot)
        let proj = XRMath.projection(tanLeft: -t, tanRight: t, tanUp: tv, tanDown: -tv, near: 0.05, far: far)
        let head = simd_quatf(angle: yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: pitch, axis: V3(1, 0, 0))
        var vps: [float4x4] = []
        for e in [-0.032, 0.032] as [Float] {
            let off = head.act(V3(e, 0, 0))
            vps.append(proj * XRMath.inversePose(head, off))
        }
        let center = game.player.eye
        game.player.yaw = yaw; game.player.pitch = pitch
        let cam = EyeCamera(center: center, viewProj: vps, cullViewProj: proj * XRMath.inversePose(head, .zero), yaw: yaw, pitch: pitch, far: far)
        let readback = try VkBuf(ctx, size: width * height * 4 * 2, usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue, host: true)
        var ms: [Double] = []
        for fi in 0..<3 {
            let s = scene.beginFrame()
            let a = CFAbsoluteTimeGetCurrent()
            let al0 = AllocCount.now
            if fi == 2 { AllocCount.traced("record") { wr.record(s, targets[fi % 2], cam) } } else { wr.record(s, targets[fi % 2], cam) }
            if fi == 2, let x = al0, let y = AllocCount.now { print("render: world record allocations per frame (steady): \(y - x)") }
            vkCmdEndRenderPass(s.cmd)
            // A pending bug-note screenshot, as QuestApp records it (left eye back in COLOR_ATTACHMENT_OPTIMAL after).
            QuestScreenshot.service(s, ctx: ctx, image: img.image, format: VK_FORMAT_R8G8B8A8_UNORM, width: width, height: height)
            vkBarrier(s.cmd, img.image, from: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, layers: 2,
                      srcAccess: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue, dstAccess: VK_ACCESS_TRANSFER_READ_BIT.rawValue,
                      srcStage: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue, dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
            var r = VkBufferImageCopy()
            r.imageSubresource = VkImageSubresourceLayers(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, mipLevel: 0, baseArrayLayer: 0, layerCount: 2)
            r.imageExtent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
            vkCmdCopyImageToBuffer(s.cmd, img.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &r)
            try scene.submit(s)
            scene.waitIdle()
            QuestScreenshot.collect(began: nil)
            ms.append((CFAbsoluteTimeGetCurrent() - a) * 1000)
        }
        print(String(format: "rendertest: %d sections visible, %d draws, %d quads; cull %.2f ms, CPU record %.2f ms, frame (lavapipe) %.0f ms",
                     scene.visibleCount, scene.drawCalls, scene.drawnQuads, scene.cullMs, wr.frameCPUMs, ms.last!))
        let md = wr.mobMaxDist
        lastStages = wr.takeStages() + ", mob vertices \(wr.lastMobVerts)"
        lastStats = (scene.visibleCount, scene.drawCalls, scene.drawnQuads, wr.frameCPUMs,
                     game.mobs.mobs.filter { $0.health > 0 && simd_length($0.pos - center) < md }.count, wr.lastMobVerts)
        landmarkVerts = wr.landmarkCount
        drawnQuads = scene.drawnQuads; recordMs = wr.frameCPUMs
        if wr.landmarkCount > 0 { print(String(format: "rendertest: landmark impostors %d vertices, %.2f ms", wr.landmarkCount, wr.landmarkMs)) }
        if wr.farRingQuads > 0 || scene.deepSeaSkipped > 0 || scene.batchedWater > 0 {
            print(String(format: "rendertest: far ring %d quads (build %.0f ms), deep-sea sections skipped %d, far water sections batched %d",
                         wr.farRingQuads, FarRing.shared.lastBuildMs, scene.deepSeaSkipped, scene.batchedWater))
        }
        // Side by side, left eye first.
        let src = readback.mapped!.bindMemory(to: UInt8.self, capacity: width * height * 8)
        var out = [UInt8](repeating: 0, count: width * 2 * height * 4)
        for y in 0..<height { for e in 0..<2 { for x in 0..<width {
            let si = (e * width * height + y * width + x) * 4, di = (y * width * 2 + e * width + x) * 4
            out[di] = src[si]; out[di + 1] = src[si + 1]; out[di + 2] = src[si + 2]; out[di + 3] = 255
        } } }
        lastRGBA = out
        lastFrameMs = ms.last!
        try PNG.encode(rgba: out, width: width * 2, height: height).write(to: URL(fileURLWithPath: path))
        print("rendertest: wrote \(path)")
        scene.waitIdle()
        withExtendedLifetime((img, targets, readback)) {}
    }
}

// P385 step 5: a steady 360 degree head turn as a shot sequence (questcheck --view OUT.png --turnshots N): one renderer
// for all N frames, as in play, the head turned 360/N degrees a frame from the starting yaw, each frame drawn once (no
// warm-up at its yaw, so a section the cull lists a frame late shows as missing in that frame's shot), frame k to
// OUT-kkk.png. Prints each frame's sections, quads and CPU record time.
extension RenderTest {
    static func renderTurn(game: Game, ctx: VkContext, path: String, width: Int, height: Int, yaw: Float, pitch: Float,
                           fovDeg: Float, frames: Int) throws {
        let scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
        try scene.uploadTextures()
        let wr = WorldRenderer(scene: scene, game: game)
        wr.landmarkHost = Renderer(game: game)
        let img = try VkImg(ctx, width: width, height: height, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        let targets = [try scene.makeTarget(image: img.image, width: width, height: height),
                       try scene.makeTarget(image: img.image, width: width, height: height)]
        let t = tanf(fovDeg * .pi / 360)
        let ringFar: Float = FarRing.enabled && game.dim.dim == .overworld ? FarRing.outer + 96 : 0
        let far = max(Float(game.world.renderDistance * 16 + 96), ringFar)
        let tv = t * Float(height) / Float(width)
        let proj = XRMath.projection(tanLeft: -t, tanRight: t, tanUp: tv, tanDown: -tv, near: 0.05, far: far)
        let readback = try VkBuf(ctx, size: width * height * 4 * 2, usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue, host: true)
        let center = game.player.eye
        let base = path.hasSuffix(".png") ? String(path.dropLast(4)) : path
        var recMs: [Double] = []
        // Two frames at the starting yaw first (the far ring and landmark shells built), then the turn.
        for fi in -2..<frames {
            let y = yaw + 2 * .pi * Float(max(0, fi)) / Float(frames)
            let head = simd_quatf(angle: y, axis: V3(0, 1, 0)) * simd_quatf(angle: pitch, axis: V3(1, 0, 0))
            var vps: [float4x4] = []
            for e in [-0.032, 0.032] as [Float] { vps.append(proj * XRMath.inversePose(head, head.act(V3(e, 0, 0)))) }
            game.player.yaw = y; game.player.pitch = pitch
            let cam = EyeCamera(center: center, viewProj: vps, cullViewProj: proj * XRMath.inversePose(head, .zero), yaw: y, pitch: pitch, far: far)
            let s = scene.beginFrame()
            wr.record(s, targets[(fi + 2) % 2], cam)
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
            guard fi >= 0 else { continue }
            recMs.append(wr.frameCPUMs)
            let src = readback.mapped!.bindMemory(to: UInt8.self, capacity: width * height * 8)
            var out = [UInt8](repeating: 0, count: width * 2 * height * 4)
            for yy in 0..<height { for e in 0..<2 { for x in 0..<width {
                let si = (e * width * height + yy * width + x) * 4, di = (yy * width * 2 + e * width + x) * 4
                out[di] = src[si]; out[di + 1] = src[si + 1]; out[di + 2] = src[si + 2]; out[di + 3] = 255
            } } }
            let name = base + String(format: "-%03d.png", fi)
            try PNG.encode(rgba: out, width: width * 2, height: height).write(to: URL(fileURLWithPath: name))
            print(String(format: "turn %03d: yaw %.1f, %d sections, %d draws, %d quads, CPU record %.2f ms (cull %.2f)",
                         fi, Double(y) * 180 / .pi, scene.visibleCount, scene.drawCalls, scene.drawnQuads, wr.frameCPUMs, scene.cullMs))
        }
        let mean = recMs.reduce(0, +) / Double(max(1, recMs.count))
        print(String(format: "turn: %d frames, CPU record mean %.2f ms, worst %.2f ms; stages ", recMs.count, mean, recMs.max() ?? 0) + wr.takeStages())
        scene.waitIdle()
        withExtendedLifetime((img, targets, readback)) {}
    }
}
