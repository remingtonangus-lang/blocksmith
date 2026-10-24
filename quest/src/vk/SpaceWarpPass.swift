import Foundation
import CVulkan

// P381 step 9 (Remington, Oct 19: "only if view 24 is still over the 72 fps budget: add Application SpaceWarp as an
// option, default off"): with XR_FB_space_warp the runtime renders every other displayed frame itself from the last
// one, its depth and its motion vectors, so the game draws 36 frames a second at the 72 Hz display. After the frame's
// pass this pass draws one triangle over each eye at the runtime's motion-vector size: the scene's depth copied down
// into the depth swapchain, and motion vectors of zero into the motion-vector swapchain (the world stands still; the
// player's own movement through it goes to the runtime as the app space's delta pose, XRSession.appSpaceDelta).
// P403 7b: the hands, what they hold and mobs are drawn again over that with their own motion (SceneRenderer
// .motionDraws, swmotion.vert); water and smoke carry none and hold still between real frames.
final class SpaceWarpPass {
    let scene: SceneRenderer
    let width: Int, height: Int
    private let renderPass: VkRenderPass
    private let pipeline: VkPipeline
    private var motionPipes: [SceneRenderer.Input: VkPipeline] = [:]      // P403 7b: per vertex layout
    private let depthFormat: VkFormat
    private var mvViews: [VkImageView] = [], depthViews: [VkImageView] = []
    private var framebuffers: [Int: VkFramebuffer] = [:]          // mv index << 16 | depth index

    init(scene: SceneRenderer, mvImages: [VkImage], depthImages: [VkImage], width: Int, height: Int, depthFormat: VkFormat) throws {
        self.scene = scene; self.width = width; self.height = height; self.depthFormat = depthFormat
        let ctx = scene.ctx
        let a = PtrArena()
        var color = VkAttachmentDescription()
        color.format = VK_FORMAT_R16G16B16A16_SFLOAT
        color.samples = VK_SAMPLE_COUNT_1_BIT
        color.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        color.storeOp = VK_ATTACHMENT_STORE_OP_STORE
        color.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        color.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        color.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        color.finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL          // what OpenXR expects back on release
        var depth = VkAttachmentDescription()
        depth.format = depthFormat
        depth.samples = VK_SAMPLE_COUNT_1_BIT
        depth.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        depth.storeOp = VK_ATTACHMENT_STORE_OP_STORE
        depth.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        depth.stencilStoreOp = VK_ATTACHMENT_STORE_OP_STORE
        depth.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        depth.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        var sub = VkSubpassDescription()
        sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
        sub.colorAttachmentCount = 1
        sub.pColorAttachments = a.ptr(VkAttachmentReference(attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL))
        sub.pDepthStencilAttachment = a.ptr(VkAttachmentReference(attachment: 1, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL))
        let fragTests = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT.rawValue | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT.rawValue
        let colorOut = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue
        // The scene pass's depth writes are read here (and the images' previous users finish first).
        let dep = VkSubpassDependency(srcSubpass: VK_SUBPASS_EXTERNAL, dstSubpass: 0, srcStageMask: colorOut | fragTests,
                                      dstStageMask: colorOut | fragTests | VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue,
                                      srcAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT.rawValue,
                                      dstAccessMask: VK_ACCESS_SHADER_READ_BIT.rawValue | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue
                                          | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT.rawValue | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT.rawValue,
                                      dependencyFlags: 0)
        var ci = VkRenderPassCreateInfo()
        ci.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
        ci.attachmentCount = 2
        ci.pAttachments = a.array([color, depth])
        ci.subpassCount = 1
        ci.pSubpasses = a.ptr(sub)
        ci.dependencyCount = 1
        ci.pDependencies = a.ptr(dep)
        var mv = VkRenderPassMultiviewCreateInfo()
        mv.sType = VK_STRUCTURE_TYPE_RENDER_PASS_MULTIVIEW_CREATE_INFO
        mv.subpassCount = 1
        mv.pViewMasks = a.ptr(UInt32(3))
        mv.correlationMaskCount = 1
        mv.pCorrelationMasks = a.ptr(UInt32(3))
        ci.pNext = UnsafeRawPointer(a.ptr(mv))
        var rp: VkRenderPass?
        try vkCheck(vkCreateRenderPass(ctx.device, &ci, nil, &rp), "vkCreateRenderPass(space warp)")
        renderPass = rp!
        pipeline = try scene.makePipeline(SceneRenderer.PipeDesc(vert: "swdepth.vert", frag: "swdepth.frag", depthTest: true, depthWrite: true,
                                                                 compare: VK_COMPARE_OP_ALWAYS, cull: VK_CULL_MODE_NONE), renderPass: renderPass)
        // P403 7b: the moving things' own motion over the copied depth (swmotion.vert: drawn 2 % nearer, no depth write).
        for input in [SceneRenderer.Input.simple, .mob, .entity] {
            motionPipes[input] = try scene.makePipeline(SceneRenderer.PipeDesc(vert: "swmotion.vert", frag: "swmotion.frag", input: input,
                                                                               depthWrite: false, compare: VK_COMPARE_OP_LESS_OR_EQUAL,
                                                                               cull: VK_CULL_MODE_NONE), renderPass: renderPass)
        }
        let hasStencil = depthFormat == VK_FORMAT_D24_UNORM_S8_UINT
        let dAspect = VK_IMAGE_ASPECT_DEPTH_BIT.rawValue | (hasStencil ? VK_IMAGE_ASPECT_STENCIL_BIT.rawValue : 0)
        mvViews = try mvImages.map { try VkImg.makeView(ctx, $0, format: VK_FORMAT_R16G16B16A16_SFLOAT, aspect: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, layers: 2, levels: 1, array: true) }
        depthViews = try depthImages.map { try VkImg.makeView(ctx, $0, format: depthFormat, aspect: dAspect, layers: 2, levels: 1, array: true) }
    }

    private func framebuffer(_ m: Int, _ d: Int) throws -> VkFramebuffer {
        if let f = framebuffers[m << 16 | d] { return f }
        let a = PtrArena()
        var ci = VkFramebufferCreateInfo()
        ci.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
        ci.renderPass = renderPass
        ci.attachmentCount = 2
        ci.pAttachments = a.array([Optional(mvViews[m]), Optional(depthViews[d])])
        ci.width = UInt32(width)
        ci.height = UInt32(height)
        ci.layers = 1                       // multiview
        var fb: VkFramebuffer?
        try vkCheck(vkCreateFramebuffer(scene.ctx.device, &ci, nil, &fb), "vkCreateFramebuffer(space warp)")
        framebuffers[m << 16 | d] = fb!
        return fb!
    }

    // Records the pass after the frame's scene pass ended (its depth in DEPTH_STENCIL_READ_ONLY_OPTIMAL).
    func record(_ s: SceneRenderer.Slot, _ t: RenderTarget, mvIndex: Int, depthIndex: Int) {
        guard mvIndex >= 0, mvIndex < mvViews.count, depthIndex >= 0, depthIndex < depthViews.count, let swSet = t.swSet,
              let fb = try? framebuffer(mvIndex, depthIndex) else { return }
        var clears = [VkClearValue(), VkClearValue()]
        clears[0].color.float32 = (0, 0, 0, 0)
        clears[1].depthStencil = VkClearDepthStencilValue(depth: 1, stencil: 0)
        var rb = VkRenderPassBeginInfo()
        rb.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
        rb.renderPass = renderPass
        rb.framebuffer = fb
        rb.renderArea = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(width), height: UInt32(height)))
        rb.clearValueCount = 2
        clears.withUnsafeBufferPointer { cp in
            rb.pClearValues = cp.baseAddress
            vkCmdBeginRenderPass(s.cmd, &rb, VK_SUBPASS_CONTENTS_INLINE)
        }
        var vp = VkViewport(x: 0, y: 0, width: Float(width), height: Float(height), minDepth: 0, maxDepth: 1)
        vkCmdSetViewport(s.cmd, 0, 1, &vp)
        var sc = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(width), height: UInt32(height)))
        vkCmdSetScissor(s.cmd, 0, 1, &sc)
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline)
        var s0: VkDescriptorSet? = s.set0
        vkCmdBindDescriptorSets(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.pipeLayout, 0, 1, &s0, 0, nil)
        var set: VkDescriptorSet? = swSet
        vkCmdBindDescriptorSets(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.pipeLayout, 2, 1, &set, 0, nil)
        vkCmdDraw(s.cmd, 3, 1, 0, 0)
        // P403 7b: the hands, what they hold, mobs: their own motion since the last drawn frame (the world holds still).
        var bound: SceneRenderer.Input? = nil
        for d in scene.motionDraws {
            guard let p = motionPipes[d.input], d.buffer != nil else { continue }
            if bound != d.input { vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, p); bound = d.input }
            scene.pushConstants(s, model: d.prev, extra: .zero)
            var b: VkBuffer? = d.buffer
            var o = VkDeviceSize(d.offset)
            vkCmdBindVertexBuffers(s.cmd, 0, 1, &b, &o)
            vkCmdDraw(s.cmd, UInt32(d.count), 1, 0, 0)
        }
        vkCmdEndRenderPass(s.cmd)
    }
}
