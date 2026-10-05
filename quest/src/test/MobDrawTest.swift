import Foundation
import simd
import Metal
import CVulkan

// Every mob kind must put pixels on screen through the Quest renderer (the Mac's --mobcheck, Sources/MobRenderCheck.swift,
// for the Vulkan path): each kind floats a few blocks in front of a level camera, alone; its frame is compared with the
// empty frame, and a kind that changes almost nothing is reported invisible.
enum MobDrawTest {
    static func run(game: Game, ctx: VkContext, check: (Bool, String) -> Void) throws {
        let w = 256, h = 160
        let scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
        try scene.uploadTextures()
        let wr = WorldRenderer(scene: scene, game: game)
        let img = try VkImg(ctx, width: w, height: h, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        let target = try scene.makeTarget(image: img.image, width: w, height: h)
        let readback = try VkBuf(ctx, size: w * h * 4 * 2, usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue, host: true)
        let p = game.player
        let saved = game.mobs.mobs
        let keepPos = p.pos, keepYaw = p.yaw, keepPitch = p.pitch, keepFly = p.flying
        p.flying = true
        p.pos.y += 6                                                       // above the trees around the spawn
        p.pitch = 0
        let t = tanf(45 * .pi / 180)
        let proj = XRMath.projection(tanLeft: -t * 1.6, tanRight: t * 1.6, tanUp: t, tanDown: -t, near: 0.05, far: 200)
        let head = simd_quatf(angle: p.yaw, axis: V3(0, 1, 0))
        let cam = EyeCamera(center: p.eye, viewProj: [proj * XRMath.inversePose(head, .zero), proj * XRMath.inversePose(head, .zero)],
                            cullViewProj: proj * XRMath.inversePose(head, .zero), yaw: p.yaw, pitch: 0)
        func frame() throws -> [UInt8] {
            let s = scene.beginFrame()
            wr.record(s, target, cam)
            vkCmdEndRenderPass(s.cmd)
            vkBarrier(s.cmd, img.image, from: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, layers: 2,
                      srcAccess: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue, dstAccess: VK_ACCESS_TRANSFER_READ_BIT.rawValue,
                      srcStage: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue, dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
            var r = VkBufferImageCopy()
            r.imageSubresource = VkImageSubresourceLayers(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, mipLevel: 0, baseArrayLayer: 0, layerCount: 1)
            r.imageExtent = VkExtent3D(width: UInt32(w), height: UInt32(h), depth: 1)
            vkCmdCopyImageToBuffer(s.cmd, img.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &r)
            try scene.submit(s)
            scene.waitIdle()
            let src = readback.mapped!.bindMemory(to: UInt8.self, capacity: w * h * 4)
            return Array(UnsafeBufferPointer(start: src, count: w * h * 4))
        }
        func changed(_ a: [UInt8], _ b: [UInt8]) -> Int {
            var n = 0, i = 0
            while i + 3 < a.count {
                let d = max(abs(Int(a[i]) - Int(b[i])), abs(Int(a[i + 1]) - Int(b[i + 1])), abs(Int(a[i + 2]) - Int(b[i + 2])))
                if d > 24 { n += 1 }
                i += 4
            }
            return n
        }
        let fwd = V3(-sinf(p.yaw), 0, -cosf(p.yaw))
        game.mobs.mobs.removeAll()
        _ = try frame()
        let base = try frame()
        var invisible: [String] = [], noParts: [String] = []
        var drawn = 0
        let t0 = CFAbsoluteTimeGetCurrent()
        for k in MobKind.allCases {
            let m = Mob(k, at: p.pos)
            let size: Float = max(m.height, 0.4)                          // small ones (tadpoles) closer
            m.pos = p.eye + fwd * (1.5 + size * 2.5) - V3(0, m.height * 0.5, 0)
            m.yaw = p.yaw + .pi * 0.75                                   // three-quarter view
            if mobModelParts(m).isEmpty { noParts.append("\(k)"); continue }
            game.mobs.mobs = [m]
            let c = changed(base, try frame())
            if c < 20 { invisible.append("\(k) (\(c) px)") } else { drawn += 1 }
        }
        game.mobs.mobs = saved
        p.pos = keepPos; p.yaw = keepYaw; p.pitch = keepPitch; p.flying = keepFly
        print(String(format: "mobdraw: %d kinds drawn in %.1f s", drawn, CFAbsoluteTimeGetCurrent() - t0)
              + (noParts.isEmpty ? "" : ", no model parts (not checked): \(noParts.joined(separator: ", "))"))
        check(invisible.isEmpty && drawn > 50, "every mob kind draws through the Quest renderer (\(drawn) drawn"
              + (invisible.isEmpty ? ")" : "; invisible: \(invisible.joined(separator: ", ")))"))
        scene.waitIdle()
        withExtendedLifetime((img, target, readback)) {}
    }
}
