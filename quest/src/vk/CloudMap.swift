import Foundation
import simd
import CVulkan

/// The cloud map (Nov 16, ledger 171): the two cloud decks painted into an image of the sky dome a strip a frame,
/// and read back by the world pass with one texture read a pixel (cloudbake.frag, clouds_map.frag).
///
/// Why: counted at the forest spot of the Nov 15 capture (47 fps, GPU-bound on pixels), half the picture is sky, and
/// clouds.frag runs about 610 shader operations on every sky pixel of both eyes, every frame: more than any pixel of
/// land. The decks change slowly (wind drift, the sun) and a texel of the map stands for a fixed point of the cumulus
/// deck, so walking or flying under it only moves where a pixel reads the map: nothing has to be repainted for that.
/// A sixteenth of the map is repainted each frame (the light, the cover and the high cirrus follow within 16 frames).
///
/// Two maps: the one shown is refreshed in place; when the eye has drifted far from its origin (or climbed), the other
/// is painted round the new origin over 16 frames and then shown. Until a map is whole, after a teleport, and while a
/// storm flash lights the clouds from inside, the world pass draws clouds.frag itself as before.
/// BS_CLOUDMAP=0: never (the old path). BS_CLOUDMAPSIZE (2048), BS_CLOUDMAPSTRIPS (16; 1 = whole map every frame, for
/// the harness's one-frame pictures).
final class CloudMap {
    static var on = Env.all["BS_CLOUDMAP"] != "0"
    static let size = max(256, Int(Env.all["BS_CLOUDMAPSIZE"] ?? "") ?? 2048)
    // (a change of the strip count starts every map over: a map part painted in strips of one size and finished or
    // refreshed in another would be read with rows never painted. Only the checks change it.)
    static var strips = max(1, Int(Env.all["BS_CLOUDMAPSTRIPS"] ?? "") ?? 16) { didSet { if strips != oldValue { epoch += 1 } } }
    static var epoch = 0
    static var framesMappedAll = 0         // (checks: frames any map was read, all renderers)
    // (checks: a map begun this far from the eye, so a picture reads it from off its origin as play does after a walk;
    // BS_CLOUDMAPOFF=dx,dz for the harness's views)
    static var testOffset: V2 = {
        let v = (Env.all["BS_CLOUDMAPOFF"] ?? "").split(separator: ",").compactMap { Float($0) }
        return v.count == 2 ? V2(v[0], v[1]) : V2(0, 0)
    }()
    static let deckY: Float = 340          // clouds.frag CUMULUS_Y

    private struct Map {
        var origin = V2(0, 0)              // cloud space (world xz + wind drift)
        var height: Float = 0              // the deck over the eye when it was begun
        var whole = false
        var painted = 0.0                  // when a strip was last painted (seconds)
    }
    let scene: SceneRenderer
    private let images: [VkImg]
    private var sets: [VkDescriptorSet] = []
    private var framebuffers: [VkFramebuffer] = []
    private var passKeep: VkRenderPass!        // keeps what the image holds (strips)
    private var pipeline: VkPipeline!
    private var sampler: VkSampler!
    private var maps = [Map(), Map()]
    private var shown = -1                     // the map the world pass reads, or none
    private var painting = -1                  // a map being painted whole (not yet shown), and its next strip
    private var strip = 0
    private var refresh = 0                    // the shown map's next strip
    private var pixAngle: Float = 0            // the world pass's pixel angle this frame (cloudbake.frag)
    private var seenEpoch = 0                  // (CloudMap.epoch as last seen: a change starts the maps over)
    private(set) var stripsPainted = 0, mapsBegun = 0, framesMapped = 0, framesDirect = 0

    init(scene: SceneRenderer) throws {
        self.scene = scene
        let ctx = scene.ctx, n = CloudMap.size
        let usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_SAMPLED_BIT.rawValue
        images = try (0..<2).map { _ in try VkImg(ctx, width: n, height: n, format: VK_FORMAT_R8G8B8A8_UNORM, usage: usage, arrayView: false) }
        let passClear = try CloudMap.makePass(ctx, keep: false)
        passKeep = try CloudMap.makePass(ctx, keep: true)
        let a = PtrArena()
        for img in images {
            var fci = VkFramebufferCreateInfo()
            fci.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
            fci.renderPass = passKeep
            fci.attachmentCount = 1
            fci.pAttachments = a.ptr(Optional(img.view))
            fci.width = UInt32(n); fci.height = UInt32(n); fci.layers = 1
            var fb: VkFramebuffer?
            try vkCheck(vkCreateFramebuffer(ctx.device, &fci, nil, &fb), "vkCreateFramebuffer(cloud map)")
            framebuffers.append(fb!)
        }
        pipeline = try scene.makePipeline(SceneRenderer.PipeDesc(vert: "sky.vert", frag: "cloudbake.frag", depthTest: false, depthWrite: false,
                                                                 cull: VK_CULL_MODE_NONE), renderPass: passKeep)
        var si = VkSamplerCreateInfo()
        si.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
        si.magFilter = VK_FILTER_LINEAR; si.minFilter = VK_FILTER_LINEAR
        si.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST
        si.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        si.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        si.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        var sm: VkSampler?
        try vkCheck(vkCreateSampler(ctx.device, &si, nil, &sm), "vkCreateSampler(cloud map)")
        sampler = sm!
        for img in images {
            let set = try scene.allocSet(scene.set2Layout)
            var w = VkWriteDescriptorSet()
            w.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            w.dstSet = set
            w.dstBinding = 0
            w.descriptorCount = 1
            w.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
            w.pImageInfo = a.ptr(VkDescriptorImageInfo(sampler: sampler, imageView: img.view, imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL))
            vkUpdateDescriptorSets(ctx.device, 1, &w, 0, nil)
            sets.append(set)
        }
        // Both start out empty and readable.
        try ctx.oneShot { cb in
            for fb in self.framebuffers {
                var clear = VkClearValue()
                clear.color.float32 = (0, 0, 0, 0)
                var rb = VkRenderPassBeginInfo()
                rb.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
                rb.renderPass = passClear
                rb.framebuffer = fb
                rb.renderArea = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(n), height: UInt32(n)))
                rb.clearValueCount = 1
                withUnsafePointer(to: &clear) { cp in
                    rb.pClearValues = cp
                    vkCmdBeginRenderPass(cb, &rb, VK_SUBPASS_CONTENTS_INLINE)
                }
                vkCmdEndRenderPass(cb)
            }
        }
        vkDestroyRenderPass(ctx.device, passClear, nil)
    }

    private static func makePass(_ ctx: VkContext, keep: Bool) throws -> VkRenderPass {
        let a = PtrArena()
        var color = VkAttachmentDescription()
        color.format = VK_FORMAT_R8G8B8A8_UNORM
        color.samples = VK_SAMPLE_COUNT_1_BIT
        color.loadOp = keep ? VK_ATTACHMENT_LOAD_OP_LOAD : VK_ATTACHMENT_LOAD_OP_CLEAR
        color.storeOp = VK_ATTACHMENT_STORE_OP_STORE
        color.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        color.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        color.initialLayout = keep ? VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL : VK_IMAGE_LAYOUT_UNDEFINED
        color.finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
        var sub = VkSubpassDescription()
        sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
        sub.colorAttachmentCount = 1
        sub.pColorAttachments = a.ptr(VkAttachmentReference(attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL))
        let deps = [
            VkSubpassDependency(srcSubpass: VK_SUBPASS_EXTERNAL, dstSubpass: 0, srcStageMask: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue,
                                dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue, srcAccessMask: VK_ACCESS_SHADER_READ_BIT.rawValue,
                                dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue | VK_ACCESS_COLOR_ATTACHMENT_READ_BIT.rawValue, dependencyFlags: 0),
            VkSubpassDependency(srcSubpass: 0, dstSubpass: VK_SUBPASS_EXTERNAL, srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue,
                                dstStageMask: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue, srcAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue,
                                dstAccessMask: VK_ACCESS_SHADER_READ_BIT.rawValue, dependencyFlags: 0),
        ]
        var ci = VkRenderPassCreateInfo()
        ci.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
        ci.attachmentCount = 1
        ci.pAttachments = a.ptr(color)
        ci.subpassCount = 1
        ci.pSubpasses = a.ptr(sub)
        ci.dependencyCount = UInt32(deps.count)
        ci.pDependencies = a.array(deps)
        var rp: VkRenderPass?
        try vkCheck(vkCreateRenderPass(ctx.device, &ci, nil, &rp), "vkCreateRenderPass(cloud map)")
        return rp!
    }

    /// Can a pixel be read from this map with the eye at `c` (cloud space), the deck `hu` over it?
    private func reads(_ m: Map, _ c: V2, _ hu: Float, within: Float, lo: Float, hi: Float) -> Bool {
        m.whole && simd_length(c - m.origin) <= within * m.height && hu >= lo * m.height && hu <= hi * m.height
    }

    private func begin(_ i: Int, _ c: V2, _ hu: Float) {
        maps[i] = Map(origin: c + CloudMap.testOffset, height: hu, whole: false, painted: 0)
        painting = i; strip = 0; mapsBegun += 1
    }

    /// Once a frame the clouds are drawn, before the world pass (the frame's uniforms are set): paints this frame's
    /// strip, and answers which map the world pass reads (its set and its origin and height for clouds_map.frag), or
    /// nil for clouds.frag itself. `c` is the eye in cloud space (u.clouds.xy), `eyeY` its world height, `flash` the
    /// storm flash (u.clouds.w).
    /// `pixAngle`: the angle a pixel of the world pass spans at the middle of the view (the bake fades detail to it).
    func record(_ s: SceneRenderer.Slot, cloud c: V2, eyeY: Float, flash: Float, pixAngle: Float = 0, now: Double = CFAbsoluteTimeGetCurrent()) -> (VkDescriptorSet, V4)? {
        self.pixAngle = pixAngle
        let hu = CloudMap.deckY - eyeY
        if seenEpoch != CloudMap.epoch { seenEpoch = CloudMap.epoch; shown = -1; painting = -1; strip = 0; refresh = 0 }
        guard hu > 0 else { framesDirect += 1; return nil }             // above the deck nothing is drawn
        // A flash lights the clouds from inside for a few frames: the shader itself, and a map being painted starts over.
        if flash > 0.001 { painting = -1; framesDirect += 1; return nil }
        if shown >= 0 && (!reads(maps[shown], c, hu, within: 0.6, lo: 0.75, hi: 1.3) || now - maps[shown].painted > 3) { shown = -1 }
        if painting >= 0 && !(simd_length(c - maps[painting].origin) <= 0.6 * maps[painting].height) { painting = -1 }   // (a teleport mid-way)
        if painting < 0 {
            if shown < 0 { begin(0, c, hu) }
            else if !reads(maps[shown], c + CloudMap.testOffset, hu, within: 0.25, lo: 0.87, hi: 1.15) { begin(1 - shown, c, hu) }   // drifted: round the new origin
        }
        if painting >= 0 {
            paint(s, painting, strip)
            strip += 1
            if shown >= 0 { maps[shown].painted = now }       // (still shown meanwhile: stale only when no frame draws clouds)
            if strip >= CloudMap.strips {
                maps[painting].whole = true; maps[painting].painted = now
                shown = painting; painting = -1; refresh = 0
            }
        } else if shown >= 0 {
            paint(s, shown, refresh)
            refresh = (refresh + 1) % CloudMap.strips
            maps[shown].painted = now
        }
        guard shown >= 0 else { framesDirect += 1; return nil }
        framesMapped += 1
        CloudMap.framesMappedAll += 1
        let m = maps[shown]
        return (sets[shown], V4(m.origin.x, m.origin.y, m.height, 0))
    }

    private func paint(_ s: SceneRenderer.Slot, _ i: Int, _ k: Int) {
        let n = CloudMap.size, rows = (n + CloudMap.strips - 1) / CloudMap.strips
        let y0 = min(n, k * rows), y1 = min(n, y0 + rows)
        guard y1 > y0 else { return }
        stripsPainted += 1
        var rb = VkRenderPassBeginInfo()
        rb.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
        rb.renderPass = passKeep
        rb.framebuffer = framebuffers[i]
        rb.renderArea = VkRect2D(offset: VkOffset2D(x: 0, y: Int32(y0)), extent: VkExtent2D(width: UInt32(n), height: UInt32(y1 - y0)))
        vkCmdBeginRenderPass(s.cmd, &rb, VK_SUBPASS_CONTENTS_INLINE)
        var vp = VkViewport(x: 0, y: 0, width: Float(n), height: Float(n), minDepth: 0, maxDepth: 1)
        vkCmdSetViewport(s.cmd, 0, 1, &vp)
        var sc = rb.renderArea
        vkCmdSetScissor(s.cmd, 0, 1, &sc)
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline)
        var set: VkDescriptorSet? = s.set0
        vkCmdBindDescriptorSets(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.pipeLayout, 0, 1, &set, 0, nil)
        let m = maps[i]
        scene.pushConstants(s, model: matrix_identity_float4x4, extra: V4(m.origin.x, m.origin.y, m.height, pixAngle))
        vkCmdDraw(s.cmd, 3, 1, 0, 0)
        vkCmdEndRenderPass(s.cmd)
    }

    /// For the checks and the perf line.
    var line: String { "cloud map: \(framesMapped) frames from the map, \(framesDirect) from the shader, \(stripsPainted) strips painted, \(mapsBegun) maps begun" }
}
