import Foundation
import CVulkan

// On-device screenshots for the voice bug notes: a small PNG of what the left eye sees (the HUD panel included, it is
// drawn in the eye pass). `request` may come from any thread; the frame thread records the capture after the eye
// pass (`service`), picks it up a frame or two later once that frame's fence has signalled (`collect`, no extra GPU
// wait) and a utility queue converts, encodes and writes the PNG. One capture at a time; nothing is allocated on the
// frame thread unless a capture is pending (the staging image/buffer are made on the first one and reused).
enum QuestScreenshot {
    private static let lock = NSLock()
    private static var pendingPath: String?        // requested, not recorded yet
    private static var busy = false                // from request until the PNG is written
    private static var written: String?
    private static let queue = DispatchQueue(label: "blocksmith.screenshot", qos: .utility)

    // Tests: the output width and the CPU fallback (full-size copy, downscaled on the CPU) on a device that can blit.
    static var targetWidth = 640
    static var forceCopy = false
    private(set) static var lastMeanLuma = 0       // 0...255, the last written image's mean (tests: not blank)

    static func request(path: String) {
        lock.lock(); defer { lock.unlock() }
        if busy { return }
        busy = true
        pendingPath = path
    }

    static var lastWritten: String? {
        lock.lock(); defer { lock.unlock() }
        return written
    }

    // Blocks until the queued PNG writes are done (tests).
    static func waitForWrites() { queue.sync {} }

    // MARK: Frame thread

    private final class Staging {
        let srcW: Int, srcH: Int, format: VkFormat
        let w: Int, h: Int                         // output size
        let blit: Bool
        let forced: Bool                           // made with forceCopy
        let linear: Bool                          // linear filter for the blit
        let image: VkImg?                          // the blit's small RGBA8 image
        let buffer: VkBuf                          // host-visible readback (w x h, or srcW x srcH for the fallback)
        init(ctx: VkContext, srcW: Int, srcH: Int, format: VkFormat, w: Int, h: Int, forceCopy: Bool) throws {
            self.srcW = srcW; self.srcH = srcH; self.format = format; self.w = w; self.h = h; forced = forceCopy
            // The blit converts: an sRGB source goes to an sRGB image (bytes stay display values), BGRA to RGBA.
            let dstFormat = SceneRenderer.isSRGB(format) ? VK_FORMAT_R8G8B8A8_SRGB : VK_FORMAT_R8G8B8A8_UNORM
            var sp = VkFormatProperties(), dp = VkFormatProperties()
            vkGetPhysicalDeviceFormatProperties(ctx.physical, format, &sp)
            vkGetPhysicalDeviceFormatProperties(ctx.physical, dstFormat, &dp)
            let canBlit = sp.optimalTilingFeatures & VK_FORMAT_FEATURE_BLIT_SRC_BIT.rawValue != 0
                && dp.optimalTilingFeatures & VK_FORMAT_FEATURE_BLIT_DST_BIT.rawValue != 0
            let useBlit = canBlit && !forceCopy
            blit = useBlit
            linear = sp.optimalTilingFeatures & VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT.rawValue != 0
            if useBlit {
                image = try VkImg(ctx, width: w, height: h, format: dstFormat,
                                  usage: VK_IMAGE_USAGE_TRANSFER_DST_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue
                                      | VK_IMAGE_USAGE_SAMPLED_BIT.rawValue, arrayView: false)
                buffer = try VkBuf(ctx, size: w * h * 4, usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue, host: true)
            } else {
                image = nil
                buffer = try VkBuf(ctx, size: srcW * srcH * 4, usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue, host: true)
            }
            print("screenshot: staging \(w)x\(h) from \(srcW)x\(srcH) format \(format.rawValue), " + (useBlit ? "GPU blit" : "full copy + CPU downscale"))
        }
    }

    private struct InFlight {
        let path: String
        let slot: SceneRenderer.Slot
        let ctx: VkContext
        let staging: Staging
        let t0: Double
    }

    private static var staging: Staging?
    private static var inFlight: InFlight?

    // After the eye pass's vkCmdEndRenderPass, before submit: records the capture of layer 0 (left eye) of `image` if
    // one is pending. The image is in COLOR_ATTACHMENT_OPTIMAL (the render pass finalLayout) and is left there.
    static func service(_ s: SceneRenderer.Slot, ctx: VkContext, image: VkImage, format: VkFormat, width: Int, height: Int) {
        lock.lock()
        let pending = pendingPath
        pendingPath = nil
        lock.unlock()
        guard let path = pending else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        let fourByte: [VkFormat] = [VK_FORMAT_R8G8B8A8_SRGB, VK_FORMAT_B8G8R8A8_SRGB, VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_B8G8R8A8_UNORM]
        guard fourByte.contains(format), width > 0, height > 0 else {
            print("screenshot: format \(format.rawValue) not supported, skipped")
            finish(nil)
            return
        }
        let w = min(targetWidth, width)
        let h = max(1, (height * w + width / 2) / width)
        let st: Staging
        if let old = staging, old.srcW == width, old.srcH == height, old.format == format, old.w == w, old.h == h,
           old.forced == forceCopy {
            st = old
        } else {
            do { st = try Staging(ctx: ctx, srcW: width, srcH: height, format: format, w: w, h: h, forceCopy: forceCopy) }
            catch { print("screenshot: staging: \(error)"); finish(nil); return }
            staging = st
        }
        record(s.cmd, st, image: image)
        inFlight = InFlight(path: path, slot: s, ctx: ctx, staging: st, t0: t0)
    }

    private static func record(_ cb: VkCommandBuffer, _ st: Staging, image: VkImage) {
        let transfer = VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue
        let colorOut = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue
        let tRead = VK_ACCESS_TRANSFER_READ_BIT.rawValue, tWrite = VK_ACCESS_TRANSFER_WRITE_BIT.rawValue
        let layer0 = VkImageSubresourceLayers(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, mipLevel: 0, baseArrayLayer: 0, layerCount: 1)
        // Left eye: COLOR_ATTACHMENT_OPTIMAL -> TRANSFER_SRC_OPTIMAL after the pass's colour writes.
        vkBarrier(cb, image, from: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, layers: 1,
                  srcAccess: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue, dstAccess: tRead, srcStage: colorOut, dstStage: transfer)
        var r = VkBufferImageCopy()
        r.imageSubresource = layer0
        if let small = st.image {
            // Small image: (previous contents discarded) -> TRANSFER_DST, blit, -> TRANSFER_SRC, copy to the buffer.
            vkBarrier(cb, small.image, from: VK_IMAGE_LAYOUT_UNDEFINED, to: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                      srcAccess: 0, dstAccess: tWrite, srcStage: transfer, dstStage: transfer)
            var b = VkImageBlit()
            b.srcSubresource = layer0
            b.srcOffsets = (VkOffset3D(x: 0, y: 0, z: 0), VkOffset3D(x: Int32(st.srcW), y: Int32(st.srcH), z: 1))
            b.dstSubresource = layer0
            b.dstOffsets = (VkOffset3D(x: 0, y: 0, z: 0), VkOffset3D(x: Int32(st.w), y: Int32(st.h), z: 1))
            vkCmdBlitImage(cb, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, small.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &b,
                           st.linear ? VK_FILTER_LINEAR : VK_FILTER_NEAREST)
            vkBarrier(cb, small.image, from: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                      srcAccess: tWrite, dstAccess: tRead, srcStage: transfer, dstStage: transfer)
            r.imageExtent = VkExtent3D(width: UInt32(st.w), height: UInt32(st.h), depth: 1)
            vkCmdCopyImageToBuffer(cb, small.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, st.buffer.buffer, 1, &r)
        } else {
            r.imageExtent = VkExtent3D(width: UInt32(st.srcW), height: UInt32(st.srcH), depth: 1)
            vkCmdCopyImageToBuffer(cb, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, st.buffer.buffer, 1, &r)
        }
        // Left eye back to COLOR_ATTACHMENT_OPTIMAL (what the render pass leaves and OpenXR expects on release).
        vkBarrier(cb, image, from: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, to: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, layers: 1,
                  srcAccess: 0, dstAccess: VK_ACCESS_COLOR_ATTACHMENT_READ_BIT.rawValue | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue
                      | VK_ACCESS_SHADER_READ_BIT.rawValue,
                  srcStage: transfer, dstStage: VK_PIPELINE_STAGE_ALL_COMMANDS_BIT.rawValue)
        // The buffer's transfer writes visible to the host once the frame's fence has signalled.
        var mb = VkMemoryBarrier()
        mb.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER
        mb.srcAccessMask = tWrite
        mb.dstAccessMask = VK_ACCESS_HOST_READ_BIT.rawValue
        vkCmdPipelineBarrier(cb, transfer, VK_PIPELINE_STAGE_HOST_BIT.rawValue, 0, 1, &mb, 0, nil, 0, nil)
    }

    // Right after scene.beginFrame() (`began`: the slot it returned; nil after a waitIdle): once the capture's frame
    // has completed (its fence signalled, or beginFrame just waited on it), hands the readback to the utility queue.
    static func collect(began: SceneRenderer.Slot?) {
        guard let f = inFlight else { return }
        if began !== f.slot {
            guard vkGetFenceStatus(f.ctx.device, f.slot.fence) == VK_SUCCESS else { return }
        }
        inFlight = nil
        let st = f.staging
        let bgra = !st.blit && (st.format == VK_FORMAT_B8G8R8A8_SRGB || st.format == VK_FORMAT_B8G8R8A8_UNORM)
        queue.async {
            guard let mapped = st.buffer.mapped else { QuestScreenshot.finish(nil); return }
            let sw = st.blit ? st.w : st.srcW, sh = st.blit ? st.h : st.srcH
            let src = UnsafePointer(mapped.bindMemory(to: UInt8.self, capacity: sw * sh * 4))
            let (rgba, mean) = QuestScreenshot.downscale(src, srcW: sw, srcH: sh, bgra: bgra, w: st.w, h: st.h)
            let png = PNG.encode(rgba: rgba, width: st.w, height: st.h)
            let url = URL(fileURLWithPath: f.path)
            do {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: url)
                print(String(format: "screenshot: wrote %@ (%dx%d, %.0f ms)", f.path, st.w, st.h, (CFAbsoluteTimeGetCurrent() - f.t0) * 1000))
                QuestScreenshot.lastMeanLuma = mean
                QuestScreenshot.finish(f.path)
            } catch {
                print("screenshot: \(f.path): \(error)")
                QuestScreenshot.finish(nil)
            }
        }
    }

    private static func finish(_ path: String?) {
        lock.lock()
        if let p = path { written = p }
        busy = false
        lock.unlock()
    }

    // Box-filtered RGBA8 (alpha 255) from 4-byte texels (BGRA swapped); sRGB bytes are display values already.
    // Also returns the mean luma (0...255).
    private static func downscale(_ p: UnsafePointer<UInt8>, srcW: Int, srcH: Int, bgra: Bool, w: Int, h: Int) -> ([UInt8], Int) {
        var out = [UInt8](repeating: 255, count: w * h * 4)
        let ri = bgra ? 2 : 0, bi = bgra ? 0 : 2
        var lumaSum = 0
        for y in 0..<h {
            let y0 = y * srcH / h, y1 = max(y0 + 1, (y + 1) * srcH / h)
            for x in 0..<w {
                let x0 = x * srcW / w, x1 = max(x0 + 1, (x + 1) * srcW / w)
                var r = 0, g = 0, b = 0
                for sy in y0..<y1 {
                    var i = (sy * srcW + x0) * 4
                    for _ in x0..<x1 {
                        r += Int(p[i + ri]); g += Int(p[i + 1]); b += Int(p[i + bi])
                        i += 4
                    }
                }
                let n = (y1 - y0) * (x1 - x0)
                let o = (y * w + x) * 4
                out[o] = UInt8(r / n); out[o + 1] = UInt8(g / n); out[o + 2] = UInt8(b / n)
                lumaSum += (r * 3 + g * 6 + b) / (10 * n)
            }
        }
        return (out, lumaSum / max(1, w * h))
    }
}
