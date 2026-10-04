import Foundation
import simd
import CVulkan

// The game's 2D HUD and menus (the Mac's buildHUD, extracted) rendered into an offscreen image every frame, then
// shown in the world as a textured panel (SceneRenderer "panel" pipelines). Pixel space, origin top-left.
final class HudPanel {
    let scene: SceneRenderer
    let width: Int, height: Int
    let image: VkImg
    private var renderPass: VkRenderPass!
    private var framebuffer: VkFramebuffer!
    private var pipeline: VkPipeline!
    private(set) var set2: VkDescriptorSet!
    private var sampler: VkSampler!
    private var vbufs: [VkBuf] = []
    private var vidx = 0
    static let maxVerts = 1 << 17

    init(scene: SceneRenderer, width: Int, height: Int) throws {
        self.scene = scene
        self.width = width
        self.height = height
        let ctx = scene.ctx
        image = try VkImg(ctx, width: width, height: height, format: VK_FORMAT_R8G8B8A8_UNORM,
                          usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_SAMPLED_BIT.rawValue, arrayView: false)
        let a = PtrArena()
        var color = VkAttachmentDescription()
        color.format = VK_FORMAT_R8G8B8A8_UNORM
        color.samples = VK_SAMPLE_COUNT_1_BIT
        color.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        color.storeOp = VK_ATTACHMENT_STORE_OP_STORE
        color.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        color.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        color.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        color.finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
        var sub = VkSubpassDescription()
        sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
        sub.colorAttachmentCount = 1
        sub.pColorAttachments = a.ptr(VkAttachmentReference(attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL))
        let deps = [
            VkSubpassDependency(srcSubpass: VK_SUBPASS_EXTERNAL, dstSubpass: 0, srcStageMask: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue,
                                dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue, srcAccessMask: VK_ACCESS_SHADER_READ_BIT.rawValue,
                                dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue, dependencyFlags: 0),
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
        try vkCheck(vkCreateRenderPass(ctx.device, &ci, nil, &rp), "vkCreateRenderPass(hud)")
        renderPass = rp!
        var fci = VkFramebufferCreateInfo()
        fci.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
        fci.renderPass = renderPass
        fci.attachmentCount = 1
        fci.pAttachments = a.ptr(Optional(image.view))
        fci.width = UInt32(width)
        fci.height = UInt32(height)
        fci.layers = 1
        var fb: VkFramebuffer?
        try vkCheck(vkCreateFramebuffer(ctx.device, &fci, nil, &fb), "vkCreateFramebuffer(hud)")
        framebuffer = fb!
        pipeline = try makeHudPipeline()
        var si = VkSamplerCreateInfo()
        si.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
        si.magFilter = VK_FILTER_LINEAR
        si.minFilter = VK_FILTER_LINEAR
        si.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST
        si.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        si.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        si.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        var s: VkSampler?
        try vkCheck(vkCreateSampler(ctx.device, &si, nil, &s), "vkCreateSampler(hud)")
        sampler = s!
        set2 = try scene.allocSet(scene.set2Layout)
        var w = VkWriteDescriptorSet()
        w.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        w.dstSet = set2
        w.dstBinding = 0
        w.descriptorCount = 1
        w.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
        w.pImageInfo = a.ptr(VkDescriptorImageInfo(sampler: sampler, imageView: image.view, imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL))
        vkUpdateDescriptorSets(ctx.device, 1, &w, 0, nil)
        for _ in 0..<2 {
            vbufs.append(try VkBuf(ctx, size: HudPanel.maxVerts * MemoryLayout<HudVert>.stride, usage: VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.rawValue, host: true))
        }
        // Start out transparent (sampled before the first HUD frame).
        try ctx.oneShot { cb in self.clearPass(cb) }
    }

    private func makeHudPipeline() throws -> VkPipeline {
        // Same layout as the world (set 0 binding 1 = the block texture array); its own render pass (no multiview).
        let d = SceneRenderer.PipeDesc(vert: "hud.vert", frag: "hud.frag", input: .hud, blend: true, depthTest: false, depthWrite: false,
                                       cull: VK_CULL_MODE_NONE)
        return try scene.makePipeline(d, renderPass: renderPass)
    }

    private func clearPass(_ cb: VkCommandBuffer) {
        var clear = VkClearValue()
        clear.color.float32 = (0, 0, 0, 0)
        var rb = VkRenderPassBeginInfo()
        rb.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
        rb.renderPass = renderPass
        rb.framebuffer = framebuffer
        rb.renderArea = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(width), height: UInt32(height)))
        rb.clearValueCount = 1
        withUnsafePointer(to: &clear) { cp in
            rb.pClearValues = cp
            vkCmdBeginRenderPass(cb, &rb, VK_SUBPASS_CONTENTS_INLINE)
        }
        vkCmdEndRenderPass(cb)
    }

    // Records the HUD pass (outside the world render pass, before it).
    func record(_ s: SceneRenderer.Slot, _ verts: [HudVert]) {
        let vb = vbufs[vidx]
        vidx = (vidx + 1) % vbufs.count
        let n = min(verts.count, HudPanel.maxVerts)
        _ = verts.withUnsafeBytes { memcpy(vb.mapped!, $0.baseAddress!, n * MemoryLayout<HudVert>.stride) }
        var clear = VkClearValue()
        clear.color.float32 = (0, 0, 0, 0)
        var rb = VkRenderPassBeginInfo()
        rb.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
        rb.renderPass = renderPass
        rb.framebuffer = framebuffer
        rb.renderArea = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(width), height: UInt32(height)))
        rb.clearValueCount = 1
        withUnsafePointer(to: &clear) { cp in
            rb.pClearValues = cp
            vkCmdBeginRenderPass(s.cmd, &rb, VK_SUBPASS_CONTENTS_INLINE)
        }
        var vp = VkViewport(x: 0, y: 0, width: Float(width), height: Float(height), minDepth: 0, maxDepth: 1)
        vkCmdSetViewport(s.cmd, 0, 1, &vp)
        var sc = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(width), height: UInt32(height)))
        vkCmdSetScissor(s.cmd, 0, 1, &sc)
        if n > 0 {
            vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline)
            var set: VkDescriptorSet? = s.set0
            vkCmdBindDescriptorSets(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.pipeLayout, 0, 1, &set, 0, nil)
            var screen = V4(Float(width), Float(height), 0, 0)
            vkCmdPushConstants(s.cmd, scene.pipeLayout, VK_SHADER_STAGE_VERTEX_BIT.rawValue | VK_SHADER_STAGE_FRAGMENT_BIT.rawValue, 0, 16, &screen)
            var b: VkBuffer? = vb.buffer
            var o: VkDeviceSize = 0
            vkCmdBindVertexBuffers(s.cmd, 0, 1, &b, &o)
            vkCmdDraw(s.cmd, UInt32(n), 1, 0, 0)
        }
        vkCmdEndRenderPass(s.cmd)
    }

    // Draws the panel image as a quad (model maps the unit square, x right / y up, to the world, camera-relative).
    func draw(_ s: SceneRenderer.Slot, model: float4x4, alpha: Float, onTop: Bool) {
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.pipe(onTop ? "panelTop" : "panel"))
        var set: VkDescriptorSet? = set2
        vkCmdBindDescriptorSets(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.pipeLayout, 2, 1, &set, 0, nil)
        scene.pushConstants(s, model: model, extra: V4(alpha, 0, 0, 0))
        vkCmdDraw(s.cmd, 6, 1, 0, 0)
    }
}
