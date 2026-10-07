import Foundation
import simd
import Metal
import CVulkan

// Uniforms for every world shader (quest/shaders/common.glsl `Frame`, std140).
struct FrameUniforms {
    var viewProj: (float4x4, float4x4) = (matrix_identity_float4x4, matrix_identity_float4x4)
    var invViewProj: (float4x4, float4x4) = (matrix_identity_float4x4, matrix_identity_float4x4)
    var fogColor = V4(0.6, 0.75, 1, 80)
    var params = V4(200, 1, 0, 0)
    var sunDir = V4(0, 1, 0, 0)
    var eye = V4(0, 0, 0, 0)
    var zenith = V4(0.3, 0.5, 0.9, 0)
    var horizon = V4(0.6, 0.75, 1, 0)
    var starRot = matrix_identity_float4x4
    var starTint = V4(1, 1, 1, 0)
    var misc = V4(0, 1, 0, 0)
    var waves = V4(1, 0, 0, 0)       // x = ocean swell scale (Weather.swell)
}

// One frame's camera: the head centre in world space and each eye's camera-relative view-projection.
struct EyeCamera {
    var center: V3
    var viewProj: [float4x4]           // per view (1 or 2), camera-relative (world - center)
    var cullViewProj: float4x4         // a frustum enclosing every view, camera-relative
    var yaw: Float                     // head yaw/pitch (for the sun/moon billboards and listeners)
    var pitch: Float
    var far: Float = 0                 // far plane (0: unknown, no landmark impostors)
}

// A render target: one colour image (array of `views` layers) + its framebuffer and depth.
final class RenderTarget {
    let image: VkImage
    let view: VkImageView
    let depth: VkImg
    let framebuffer: VkFramebuffer
    let width: Int, height: Int
    let ctx: VkContext
    init(ctx: VkContext, image: VkImage, view: VkImageView, depth: VkImg, framebuffer: VkFramebuffer, width: Int, height: Int) {
        self.ctx = ctx; self.image = image; self.view = view; self.depth = depth; self.framebuffer = framebuffer
        self.width = width; self.height = height
    }
    var fdmView: VkImageView?
    deinit {
        vkDestroyFramebuffer(ctx.device, framebuffer, nil)
        vkDestroyImageView(ctx.device, view, nil)
        if let f = fdmView { vkDestroyImageView(ctx.device, f, nil) }
    }
}

final class SceneRenderer {
    let ctx: VkContext
    let views: Int
    let colorFormat: VkFormat
    let depthFormat: VkFormat
    private(set) var renderPass: VkRenderPass!
    private(set) var set0Layout: VkDescriptorSetLayout!
    private(set) var set1Layout: VkDescriptorSetLayout!
    private(set) var set2Layout: VkDescriptorSetLayout!
    private(set) var pipeLayout: VkPipelineLayout!
    private var descPool: VkDescriptorPool!
    private var pipes: [String: VkPipeline] = [:]
    private(set) var texture: VkImg!
    private(set) var sampler: VkSampler!
    private var quadIndex: VkBuf!
    private var starBuf: VkBuf!
    private var starVerts = 0
    static let maxQuads = 1 << 17
    let device: QuestDevice

    // Per frame-in-flight resources.
    final class Slot {
        var ubo: VkBuf!
        var records: VkBuf!            // section records (instance data)
        var scratch: VkBuf!            // per-frame vertices (stars, sun/moon, mobs, entities, lines)
        var set0: VkDescriptorSet!
        var cmd: VkCommandBuffer!
        var fence: VkFence!
        var submitted = 0              // MeshArena frame number
        var inUse = false
        var queryBase: UInt32 = 0
        var timed = false
    }
    private var slots: [Slot] = []
    private var slotIdx = 0
    static let recordCap = 1 << 16
    static let scratchSize = 12 << 20
    // The last MB is kept for the hands and the held item (priority writers): a busy frame (mobs, particles, items)
    // used to fill the ring first and the held tool silently vanished until the scene got quieter (Quest round 3).
    static let handTail = 1 << 20
    private(set) var scratchFull = 0               // frames something didn't fit (logged once)
    private var tintSets: [ObjectIdentifier: VkDescriptorSet] = [:]
    private var queryPool: VkQueryPool?
    private var tsPeriod: Double = 0           // ns per timestamp tick
    private(set) var gpuMs = 0.0               // last completed frame's GPU time

    // Stats (last frame).
    private(set) var drawCalls = 0
    private(set) var drawnQuads = 0
    private(set) var visibleCount = 0
    private(set) var cullMs = 0.0
    var caveCulling = true
    // The swapchain is sRGB: shaders compute display (gamma) values like the Mac, so they write them back to linear.
    var linearOutput = false
    static func isSRGB(_ f: VkFormat) -> Bool { f == VK_FORMAT_R8G8B8A8_SRGB || f == VK_FORMAT_B8G8R8A8_SRGB }

    // Fixed foveated rendering: the render pass takes the runtime's fragment density map as a third attachment.
    let foveated: Bool

    init(ctx: VkContext, device: QuestDevice, views: Int, colorFormat: VkFormat, foveated: Bool = false) throws {
        self.ctx = ctx
        self.device = device
        self.views = views
        self.colorFormat = colorFormat
        self.foveated = foveated
        depthFormat = SceneRenderer.pickDepth(ctx)
        try makeLayouts()
        try makeRenderPass()
        try makePipelines()
        try makeStaticBuffers()
        for i in 0..<2 { let sl = try makeSlot(); sl.queryBase = UInt32(i * 2); slots.append(sl) }
        // A 1x1 placeholder array until the block textures are uploaded (the loading scene binds set 0 too).
        let ph = try VkImg(ctx, width: 1, height: 1, layers: 1, format: VK_FORMAT_R8G8B8A8_UNORM,
                           usage: VK_IMAGE_USAGE_SAMPLED_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_DST_BIT.rawValue)
        try ctx.oneShot { cb in
            vkBarrier(cb, ph.image, from: VK_IMAGE_LAYOUT_UNDEFINED, to: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                      srcAccess: 0, dstAccess: VK_ACCESS_SHADER_READ_BIT.rawValue,
                      srcStage: VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue, dstStage: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue)
        }
        texture = ph
        for sl in slots { writeSet0(sl) }
        // GPU timestamps (frame GPU time in the perf log). Not on llvmpipe: its timestamp queries crash the queue thread
        // after a few frames (CI run 1; reproduced locally with alternating targets and validation clean).
        let soft = ctx.deviceName.contains("llvmpipe")
        if ctx.props.limits.timestampComputeAndGraphics != 0 && !soft && ProcessInfo.processInfo.environment["QUEST_NO_QUERIES"] == nil {
            var qi = VkQueryPoolCreateInfo()
            qi.sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO
            qi.queryType = VK_QUERY_TYPE_TIMESTAMP
            qi.queryCount = 4
            var qp: VkQueryPool?
            if vkCreateQueryPool(ctx.device, &qi, nil, &qp) == VK_SUCCESS { queryPool = qp; tsPeriod = Double(ctx.props.limits.timestampPeriod) }
        }
    }

    static func pickDepth(_ ctx: VkContext) -> VkFormat {
        for f in [VK_FORMAT_D32_SFLOAT, VK_FORMAT_D24_UNORM_S8_UINT, VK_FORMAT_D16_UNORM] {
            var p = VkFormatProperties()
            vkGetPhysicalDeviceFormatProperties(ctx.physical, f, &p)
            if p.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue != 0 { return f }
        }
        return VK_FORMAT_D16_UNORM
    }

    // MARK: Layouts, render pass, pipelines

    private func makeLayouts() throws {
        let d = ctx.device
        func layout(_ bindings: [VkDescriptorSetLayoutBinding]) throws -> VkDescriptorSetLayout {
            let a = PtrArena()
            var ci = VkDescriptorSetLayoutCreateInfo()
            ci.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
            ci.bindingCount = UInt32(bindings.count)
            ci.pBindings = a.array(bindings)
            var l: VkDescriptorSetLayout?
            try vkCheck(vkCreateDescriptorSetLayout(d, &ci, nil, &l), "vkCreateDescriptorSetLayout")
            return l!
        }
        let vf = VK_SHADER_STAGE_VERTEX_BIT.rawValue | VK_SHADER_STAGE_FRAGMENT_BIT.rawValue
        set0Layout = try layout([
            VkDescriptorSetLayoutBinding(binding: 0, descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: 1, stageFlags: vf, pImmutableSamplers: nil),
            VkDescriptorSetLayoutBinding(binding: 1, descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, descriptorCount: 1, stageFlags: vf, pImmutableSamplers: nil),
        ])
        set1Layout = try layout([
            VkDescriptorSetLayoutBinding(binding: 0, descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, descriptorCount: 1,
                                         stageFlags: VK_SHADER_STAGE_VERTEX_BIT.rawValue, pImmutableSamplers: nil),
        ])
        set2Layout = try layout([
            VkDescriptorSetLayoutBinding(binding: 0, descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, descriptorCount: 1,
                                         stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT.rawValue, pImmutableSamplers: nil),
        ])
        let a = PtrArena()
        var pl = VkPipelineLayoutCreateInfo()
        pl.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
        pl.setLayoutCount = 3
        pl.pSetLayouts = a.array([set0Layout, set1Layout, set2Layout])
        pl.pushConstantRangeCount = 1
        pl.pPushConstantRanges = a.ptr(VkPushConstantRange(stageFlags: vf, offset: 0, size: 96))
        var p: VkPipelineLayout?
        try vkCheck(vkCreatePipelineLayout(d, &pl, nil, &p), "vkCreatePipelineLayout")
        pipeLayout = p!
        let sizes = [
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: 16),
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, descriptorCount: 64),
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, descriptorCount: 256),
        ]
        var pci = VkDescriptorPoolCreateInfo()
        pci.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
        pci.maxSets = 320
        pci.poolSizeCount = UInt32(sizes.count)
        pci.pPoolSizes = a.array(sizes)
        var pool: VkDescriptorPool?
        try vkCheck(vkCreateDescriptorPool(d, &pci, nil, &pool), "vkCreateDescriptorPool")
        descPool = pool!
    }

    func allocSet(_ layout: VkDescriptorSetLayout) throws -> VkDescriptorSet {
        let a = PtrArena()
        var ai = VkDescriptorSetAllocateInfo()
        ai.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
        ai.descriptorPool = descPool
        ai.descriptorSetCount = 1
        ai.pSetLayouts = a.ptr(Optional(layout))
        var s: VkDescriptorSet?
        try vkCheck(vkAllocateDescriptorSets(ctx.device, &ai, &s), "vkAllocateDescriptorSets")
        return s!
    }

    private func makeRenderPass() throws {
        let a = PtrArena()
        var color = VkAttachmentDescription()
        color.format = colorFormat
        color.samples = VK_SAMPLE_COUNT_1_BIT
        color.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        color.storeOp = VK_ATTACHMENT_STORE_OP_STORE
        color.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        color.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        color.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        color.finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL     // what OpenXR expects back on release
        var depth = VkAttachmentDescription()
        depth.format = depthFormat
        depth.samples = VK_SAMPLE_COUNT_1_BIT
        depth.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        depth.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        depth.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        depth.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        depth.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        depth.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        var sub = VkSubpassDescription()
        sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
        sub.colorAttachmentCount = 1
        sub.pColorAttachments = a.ptr(VkAttachmentReference(attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL))
        sub.pDepthStencilAttachment = a.ptr(VkAttachmentReference(attachment: 1, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL))
        // External dependencies: the previous user of the colour image (compositor / last frame) and depth reuse.
        let fragTests = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT.rawValue | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT.rawValue
        let colorOut = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue
        let deps = [
            VkSubpassDependency(srcSubpass: VK_SUBPASS_EXTERNAL, dstSubpass: 0, srcStageMask: colorOut | fragTests, dstStageMask: colorOut | fragTests,
                                srcAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT.rawValue,
                                dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue | VK_ACCESS_COLOR_ATTACHMENT_READ_BIT.rawValue
                                    | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT.rawValue | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT.rawValue,
                                dependencyFlags: 0),
            VkSubpassDependency(srcSubpass: 0, dstSubpass: VK_SUBPASS_EXTERNAL, srcStageMask: colorOut, dstStageMask: VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT.rawValue | VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue,
                                srcAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue, dstAccessMask: VK_ACCESS_TRANSFER_READ_BIT.rawValue, dependencyFlags: 0),
        ]
        var fdmAtt = VkAttachmentDescription()
        fdmAtt.format = VK_FORMAT_R8G8_UNORM
        fdmAtt.samples = VK_SAMPLE_COUNT_1_BIT
        fdmAtt.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        fdmAtt.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        fdmAtt.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        fdmAtt.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        fdmAtt.initialLayout = VK_IMAGE_LAYOUT_FRAGMENT_DENSITY_MAP_OPTIMAL_EXT
        fdmAtt.finalLayout = VK_IMAGE_LAYOUT_FRAGMENT_DENSITY_MAP_OPTIMAL_EXT
        var ci = VkRenderPassCreateInfo()
        ci.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
        ci.attachmentCount = foveated ? 3 : 2
        ci.pAttachments = a.array(foveated ? [color, depth, fdmAtt] : [color, depth])
        ci.subpassCount = 1
        ci.pSubpasses = a.ptr(sub)
        ci.dependencyCount = UInt32(deps.count)
        ci.pDependencies = a.array(deps)
        // Multiview: both eyes (array layers 0 and 1) in one pass.
        var mv = VkRenderPassMultiviewCreateInfo()
        mv.sType = VK_STRUCTURE_TYPE_RENDER_PASS_MULTIVIEW_CREATE_INFO
        mv.subpassCount = 1
        mv.pViewMasks = a.ptr(UInt32((1 << views) - 1))
        mv.correlationMaskCount = 1
        mv.pCorrelationMasks = a.ptr(UInt32((1 << views) - 1))
        if foveated {
            var fd = VkRenderPassFragmentDensityMapCreateInfoEXT()
            fd.sType = VK_STRUCTURE_TYPE_RENDER_PASS_FRAGMENT_DENSITY_MAP_CREATE_INFO_EXT
            fd.fragmentDensityMapAttachment = VkAttachmentReference(attachment: 2, layout: VK_IMAGE_LAYOUT_FRAGMENT_DENSITY_MAP_OPTIMAL_EXT)
            mv.pNext = UnsafeRawPointer(a.ptr(fd))
        }
        ci.pNext = UnsafeRawPointer(a.ptr(mv))
        var rp: VkRenderPass?
        try vkCheck(vkCreateRenderPass(ctx.device, &ci, nil, &rp), "vkCreateRenderPass")
        renderPass = rp!
    }

    enum Input { case none, chunk, ship, simple, mob, entity, hud }
    struct PipeDesc {
        var vert: String, frag: String
        var input: Input = .none
        var blend = false
        var depthTest = true, depthWrite = true
        var compare = VK_COMPARE_OP_LESS
        var cull = VK_CULL_MODE_BACK_BIT
        var topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
        var colorWrite = true
    }

    private var modules: [String: VkShaderModule] = [:]
    private func module(_ name: String) throws -> VkShaderModule {
        if let m = modules[name] { return m }
        let m = try ctx.shaderModule(QuestSPIRV.words(name))
        modules[name] = m
        return m
    }

    func makePipeline(_ p: PipeDesc, renderPass rp: VkRenderPass? = nil) throws -> VkPipeline {
        let a = PtrArena()
        let main = a.cstr("main")
        var stages = [VkPipelineShaderStageCreateInfo(), VkPipelineShaderStageCreateInfo()]
        stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT
        stages[0].module = try module(p.vert)
        stages[0].pName = main
        stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT
        stages[1].module = try module(p.frag)
        stages[1].pName = main
        var bindings: [VkVertexInputBindingDescription] = []
        var attrs: [VkVertexInputAttributeDescription] = []
        let vtx = VK_VERTEX_INPUT_RATE_VERTEX, inst = VK_VERTEX_INPUT_RATE_INSTANCE
        let f4 = VK_FORMAT_R32G32B32A32_SFLOAT
        switch p.input {
        case .none: break
        case .chunk:
            bindings = [VkVertexInputBindingDescription(binding: 0, stride: 8, inputRate: vtx),
                        VkVertexInputBindingDescription(binding: 1, stride: 16, inputRate: inst)]
            attrs = [VkVertexInputAttributeDescription(location: 0, binding: 0, format: VK_FORMAT_R32G32_UINT, offset: 0),
                     VkVertexInputAttributeDescription(location: 1, binding: 1, format: VK_FORMAT_R32G32B32_SFLOAT, offset: 0),
                     VkVertexInputAttributeDescription(location: 2, binding: 1, format: VK_FORMAT_R32_UINT, offset: 12)]
        case .ship:
            bindings = [VkVertexInputBindingDescription(binding: 0, stride: 8, inputRate: vtx)]
            attrs = [VkVertexInputAttributeDescription(location: 0, binding: 0, format: VK_FORMAT_R32G32_UINT, offset: 0)]
        case .simple:
            bindings = [VkVertexInputBindingDescription(binding: 0, stride: 32, inputRate: vtx)]
            attrs = [VkVertexInputAttributeDescription(location: 0, binding: 0, format: f4, offset: 0),
                     VkVertexInputAttributeDescription(location: 1, binding: 0, format: f4, offset: 16)]
        case .hud:
            bindings = [VkVertexInputBindingDescription(binding: 0, stride: 48, inputRate: vtx)]
            attrs = [VkVertexInputAttributeDescription(location: 0, binding: 0, format: VK_FORMAT_R32G32_SFLOAT, offset: 0),
                     VkVertexInputAttributeDescription(location: 1, binding: 0, format: VK_FORMAT_R32G32_SFLOAT, offset: 8),
                     VkVertexInputAttributeDescription(location: 2, binding: 0, format: f4, offset: 16),
                     VkVertexInputAttributeDescription(location: 3, binding: 0, format: f4, offset: 32)]
        case .mob, .entity:
            bindings = [VkVertexInputBindingDescription(binding: 0, stride: 48, inputRate: vtx)]
            attrs = [VkVertexInputAttributeDescription(location: 0, binding: 0, format: f4, offset: 0),
                     VkVertexInputAttributeDescription(location: 1, binding: 0, format: f4, offset: 16),
                     VkVertexInputAttributeDescription(location: 2, binding: 0, format: f4, offset: 32)]
        }
        var vi = VkPipelineVertexInputStateCreateInfo()
        vi.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
        vi.vertexBindingDescriptionCount = UInt32(bindings.count)
        vi.pVertexBindingDescriptions = bindings.isEmpty ? nil : a.array(bindings)
        vi.vertexAttributeDescriptionCount = UInt32(attrs.count)
        vi.pVertexAttributeDescriptions = attrs.isEmpty ? nil : a.array(attrs)
        var ia = VkPipelineInputAssemblyStateCreateInfo()
        ia.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
        ia.topology = p.topology
        var vp = VkPipelineViewportStateCreateInfo()
        vp.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
        vp.viewportCount = 1
        vp.scissorCount = 1
        var rs = VkPipelineRasterizationStateCreateInfo()
        rs.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
        rs.polygonMode = VK_POLYGON_MODE_FILL
        rs.cullMode = p.cull.rawValue
        rs.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE
        rs.lineWidth = 1
        var ms = VkPipelineMultisampleStateCreateInfo()
        ms.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
        ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT
        var ds = VkPipelineDepthStencilStateCreateInfo()
        ds.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
        ds.depthTestEnable = p.depthTest ? 1 : 0
        ds.depthWriteEnable = p.depthWrite ? 1 : 0
        ds.depthCompareOp = p.compare
        var att = VkPipelineColorBlendAttachmentState()
        att.colorWriteMask = p.colorWrite ? 0xF : 0
        if p.blend {
            att.blendEnable = 1
            att.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA
            att.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
            att.colorBlendOp = VK_BLEND_OP_ADD
            att.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE
            att.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
            att.alphaBlendOp = VK_BLEND_OP_ADD
        }
        var cb = VkPipelineColorBlendStateCreateInfo()
        cb.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
        cb.attachmentCount = 1
        cb.pAttachments = a.ptr(att)
        let dyn = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR]
        var dy = VkPipelineDynamicStateCreateInfo()
        dy.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
        dy.dynamicStateCount = UInt32(dyn.count)
        dy.pDynamicStates = a.array(dyn)
        var ci = VkGraphicsPipelineCreateInfo()
        ci.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
        ci.stageCount = 2
        ci.pStages = a.array(stages)
        ci.pVertexInputState = a.ptr(vi)
        ci.pInputAssemblyState = a.ptr(ia)
        ci.pViewportState = a.ptr(vp)
        ci.pRasterizationState = a.ptr(rs)
        ci.pMultisampleState = a.ptr(ms)
        ci.pDepthStencilState = a.ptr(ds)
        ci.pColorBlendState = a.ptr(cb)
        ci.pDynamicState = a.ptr(dy)
        ci.layout = pipeLayout
        ci.renderPass = rp ?? renderPass
        ci.subpass = 0
        var pipe: VkPipeline?
        try vkCheck(vkCreateGraphicsPipelines(ctx.device, nil, 1, &ci, nil, &pipe), "vkCreateGraphicsPipelines(\(p.vert)/\(p.frag))")
        return pipe!
    }

    private func makePipelines() throws {
        let none = VK_CULL_MODE_NONE
        let le = VK_COMPARE_OP_LESS_OR_EQUAL
        let defs: [String: PipeDesc] = [
            "solid": PipeDesc(vert: "chunk.vert", frag: "chunk_solid.frag", input: .chunk),
            "cut": PipeDesc(vert: "chunk.vert", frag: "chunk_cut.frag", input: .chunk),
            // Translucent faces cull their backs from above the water: with no depth write and no per-face sorting, the
            // inner side faces of a pool's edge, a drop-off or a waterfall blended over the surface in front of them (the
            // "see-through glitch" at water edges, Quest v63). Under water the surface is seen from below: no culling.
            "water": PipeDesc(vert: "chunk.vert", frag: "water.frag", input: .chunk, blend: true, depthWrite: false, compare: le),
            "waterUnder": PipeDesc(vert: "chunk.vert", frag: "water.frag", input: .chunk, blend: true, depthWrite: false, compare: le, cull: none),
            "sky": PipeDesc(vert: "sky.vert", frag: "sky.frag", depthWrite: false, compare: le, cull: none),
            "star": PipeDesc(vert: "star.vert", frag: "star.frag", input: .simple, blend: true, depthWrite: false, compare: le, cull: none),
            "body": PipeDesc(vert: "body.vert", frag: "crack.frag", input: .entity, blend: true, depthWrite: false, compare: le, cull: none),
            "simple": PipeDesc(vert: "simple.vert", frag: "simple.frag", input: .simple, blend: true, depthWrite: false, compare: le, cull: none),
            "simpleSolid": PipeDesc(vert: "simple.vert", frag: "simple.frag", input: .simple, cull: none),
            "lines": PipeDesc(vert: "simple.vert", frag: "simple.frag", input: .simple, blend: true, depthWrite: false, compare: le, cull: none,
                              topology: VK_PRIMITIVE_TOPOLOGY_LINE_LIST),
            "mob": PipeDesc(vert: "mob.vert", frag: "mob.frag", input: .mob, cull: none),
            "entity": PipeDesc(vert: "entity.vert", frag: "entity.frag", input: .entity, cull: none),
            "crack": PipeDesc(vert: "entity.vert", frag: "crack.frag", input: .entity, blend: true, depthWrite: false, compare: le, cull: none),
            "panel": PipeDesc(vert: "panel.vert", frag: "panel.frag", blend: true, depthWrite: false, compare: le, cull: none),
            "shipSolid": PipeDesc(vert: "ship.vert", frag: "ship_solid.frag", input: .ship),
            "shipCut": PipeDesc(vert: "ship.vert", frag: "ship_cut.frag", input: .ship),
            "shipTrans": PipeDesc(vert: "ship.vert", frag: "ship_trans.frag", input: .ship, blend: true, depthWrite: false, compare: le, cull: none),
            "shipMask": PipeDesc(vert: "simple.vert", frag: "simple.frag", input: .simple, cull: none, colorWrite: false),
            "panelVignette": PipeDesc(vert: "simple.vert", frag: "simple.frag", input: .simple, blend: true, depthTest: false, depthWrite: false, cull: none),
            "panelTop": PipeDesc(vert: "panel.vert", frag: "panel.frag", blend: true, depthTest: false, depthWrite: false, cull: none),
        ]
        for (k, d) in defs { pipes[k] = try makePipeline(d) }
    }

    func pipe(_ name: String) -> VkPipeline { pipes[name]! }

    // MARK: Static resources

    private func makeStaticBuffers() throws {
        // Shared quad index buffer: 4 vertices -> 2 CCW triangles.
        quadIndex = try VkBuf(ctx, size: SceneRenderer.maxQuads * 6 * 4, usage: VK_BUFFER_USAGE_INDEX_BUFFER_BIT.rawValue, host: true)
        let ip = quadIndex.mapped!.bindMemory(to: UInt32.self, capacity: SceneRenderer.maxQuads * 6)
        for q in 0..<SceneRenderer.maxQuads {
            let b = UInt32(q * 4), o = q * 6
            ip[o] = b; ip[o + 1] = b + 1; ip[o + 2] = b + 2; ip[o + 3] = b; ip[o + 4] = b + 2; ip[o + 5] = b + 3
        }
        // Star field (same seeds as the Mac renderer).
        var stars: [SimpleVert] = []
        for i in 0..<1400 {
            let u1 = hashf(i, 1, 0, 4242) * 2 - 1, u2 = hashf(i, 2, 0, 4242) * 2 * .pi
            let rr = (1 - u1 * u1).squareRoot()
            let dir = V3(rr * cosf(u2), u1, rr * sinf(u2))
            let size: Float = (0.1 + 0.16 * hashf(i, 3, 0, 4242) * hashf(i, 4, 0, 4242)) * 1.6
            let b: Float = 0.45 + 0.55 * hashf(i, 5, 0, 4242)
            let warm = hashf(i, 6, 0, 4242)
            let col = V4(b * (0.85 + 0.15 * warm), b * 0.9, b * (1 - 0.15 * warm), 1)
            let c = dir * 90
            let ref = abs(dir.y) > 0.9 ? V3(1, 0, 0) : V3(0, 1, 0)
            let r = simd_normalize(simd_cross(dir, ref)) * size
            let up = simd_normalize(simd_cross(r, dir)) * size
            let lo: V3 = c - up, hi: V3 = c + up
            let q: [V3] = [lo - r, lo + r, hi + r, hi - r]
            for k in [0, 1, 2, 0, 2, 3] { stars.append(SimpleVert(pos: V4(q[k], 1), color: col)) }
        }
        starVerts = stars.count
        starBuf = try VkBuf(ctx, size: stars.count * 32, usage: VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.rawValue, host: true)
        _ = stars.withUnsafeBytes { memcpy(starBuf.mapped!, $0.baseAddress!, $0.count) }
        var si = VkSamplerCreateInfo()
        si.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
        si.magFilter = VK_FILTER_NEAREST
        si.minFilter = VK_FILTER_LINEAR
        si.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR
        si.addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT
        si.addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT
        si.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT
        si.maxLod = 16
        if ctx.features.samplerAnisotropy != 0 { si.anisotropyEnable = 1; si.maxAnisotropy = min(4, ctx.props.limits.maxSamplerAnisotropy) }
        var s: VkSampler?
        try vkCheck(vkCreateSampler(ctx.device, &si, nil, &s), "vkCreateSampler")
        sampler = s!
    }

    // Block texture array: every layer TextureGen paints, with the CPU-built mip chain (uploaded in batches).
    // `pregenerated`: TextureGen.mipChain() for every layer, built on a loading thread (the queue stays on this one).
    func uploadTextures(pregenerated: [[UInt8]]? = nil) throws {
        TextureGen.registerAll()
        let layers = Tex.count, size = TextureGen.size
        var levels = 1
        while (size >> (levels - 1)) > 1 { levels += 1 }
        let t0 = CFAbsoluteTimeGetCurrent()
        let img = try VkImg(ctx, width: size, height: size, layers: layers, levels: levels, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_SAMPLED_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_DST_BIT.rawValue)
        try ctx.oneShot { cb in
            vkBarrier(cb, img.image, from: VK_IMAGE_LAYOUT_UNDEFINED, to: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, levels: levels, layers: layers,
                      srcAccess: 0, dstAccess: VK_ACCESS_TRANSFER_WRITE_BIT.rawValue,
                      srcStage: VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue, dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
        }
        var bytes = 0
        let batch = 256
        var first = 0
        while first < layers {
            let range = pregenerated != nil ? 0..<layers : first..<min(layers, first + batch)
            let data = pregenerated ?? TextureGen.mipChain(layers: range)
            var total = 0
            for (lvl, d) in data.enumerated() where lvl < levels { total += d.count }
            let staging = try VkBuf(ctx, size: total, usage: VK_BUFFER_USAGE_TRANSFER_SRC_BIT.rawValue, host: true)
            var regions: [VkBufferImageCopy] = []
            var off = 0, sz = size
            for (lvl, d) in data.enumerated() where lvl < levels {
                _ = d.withUnsafeBytes { memcpy(staging.mapped! + off, $0.baseAddress!, $0.count) }
                var r = VkBufferImageCopy()
                r.bufferOffset = VkDeviceSize(off)
                r.imageSubresource = VkImageSubresourceLayers(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, mipLevel: UInt32(lvl),
                                                              baseArrayLayer: UInt32(range.lowerBound), layerCount: UInt32(range.count))
                r.imageExtent = VkExtent3D(width: UInt32(sz), height: UInt32(sz), depth: 1)
                regions.append(r)
                off += d.count
                sz = max(1, sz / 2)
            }
            bytes += total
            try ctx.oneShot { cb in
                vkCmdCopyBufferToImage(cb, staging.buffer, img.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, UInt32(regions.count), regions)
            }
            first = range.upperBound
        }
        try ctx.oneShot { cb in
            vkBarrier(cb, img.image, from: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, to: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, levels: levels, layers: layers,
                      srcAccess: VK_ACCESS_TRANSFER_WRITE_BIT.rawValue, dstAccess: VK_ACCESS_SHADER_READ_BIT.rawValue,
                      srcStage: VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue, dstStage: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue)
        }
        waitIdle()                          // frames in flight may still sample the placeholder
        texture = img
        print(String(format: "textures: %d layers at %d px, RGBA8, %.1f MB with mips (%.0f ms)", layers, size,
                     Double(bytes) / 1_048_576, (CFAbsoluteTimeGetCurrent() - t0) * 1000))
        for s in slots { writeSet0(s) }
    }

    private func makeSlot() throws -> Slot {
        let s = Slot()
        s.ubo = try VkBuf(ctx, size: MemoryLayout<FrameUniforms>.stride, usage: VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue, host: true)
        s.records = try VkBuf(ctx, size: SceneRenderer.recordCap * 16, usage: VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.rawValue, host: true)
        s.scratch = try VkBuf(ctx, size: SceneRenderer.scratchSize, usage: VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.rawValue, host: true)
        s.set0 = try allocSet(set0Layout)
        var ai = VkCommandBufferAllocateInfo()
        ai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        ai.commandPool = ctx.pool
        ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        ai.commandBufferCount = 1
        var cb: VkCommandBuffer?
        try vkCheck(vkAllocateCommandBuffers(ctx.device, &ai, &cb), "vkAllocateCommandBuffers")
        s.cmd = cb!
        var fi = VkFenceCreateInfo()
        fi.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
        fi.flags = VK_FENCE_CREATE_SIGNALED_BIT.rawValue
        var f: VkFence?
        try vkCheck(vkCreateFence(ctx.device, &fi, nil, &f), "vkCreateFence")
        s.fence = f!
        return s
    }

    private func writeSet0(_ s: Slot) {
        let a = PtrArena()
        let bi = VkDescriptorBufferInfo(buffer: s.ubo.buffer, offset: 0, range: VkDeviceSize(MemoryLayout<FrameUniforms>.stride))
        let ii = VkDescriptorImageInfo(sampler: sampler, imageView: texture?.view, imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
        var w = [VkWriteDescriptorSet(), VkWriteDescriptorSet()]
        w[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        w[0].dstSet = s.set0
        w[0].dstBinding = 0
        w[0].descriptorCount = 1
        w[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        w[0].pBufferInfo = a.ptr(bi)
        w[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        w[1].dstSet = s.set0
        w[1].dstBinding = 1
        w[1].descriptorCount = 1
        w[1].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
        w[1].pImageInfo = a.ptr(ii)
        vkUpdateDescriptorSets(ctx.device, 2, w, 0, nil)
    }

    // A storage-buffer set for a tint slab (cached; slabs live for the process).
    private func tintSet(_ b: QuestBuffer) -> VkDescriptorSet? {
        let k = ObjectIdentifier(b)
        if let s = tintSets[k] { return s }
        guard let s = try? allocSet(set1Layout) else { return nil }
        let a = PtrArena()
        var w = VkWriteDescriptorSet()
        w.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        w.dstSet = s
        w.dstBinding = 0
        w.descriptorCount = 1
        w.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
        w.pBufferInfo = a.ptr(VkDescriptorBufferInfo(buffer: b.vkBuffer, offset: 0, range: VkDeviceSize(VK_WHOLE_SIZE)))
        vkUpdateDescriptorSets(ctx.device, 1, &w, 0, nil)
        tintSets[k] = s
        return s
    }

    // MARK: Targets

    // Framebuffer for an image with `views` layers (an OpenXR swapchain image or an offscreen test image).
    func makeTarget(image: VkImage, width: Int, height: Int, densityMap: VkImage? = nil) throws -> RenderTarget {
        let view = try VkImg.makeView(ctx, image, format: colorFormat, aspect: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, layers: views, levels: 1, array: true)
        var fdmView: VkImageView?
        if foveated, let dm = densityMap {
            fdmView = try VkImg.makeView(ctx, dm, format: VK_FORMAT_R8G8_UNORM, aspect: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, layers: views, levels: 1, array: true)
        }
        let depth = try VkImg(ctx, width: width, height: height, layers: views, format: depthFormat,
                              usage: VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue,
                              aspect: VK_IMAGE_ASPECT_DEPTH_BIT.rawValue, transient: ProcessInfo.processInfo.environment["QUEST_NO_TRANSIENT"] == nil)
        let a = PtrArena()
        var ci = VkFramebufferCreateInfo()
        ci.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
        ci.renderPass = renderPass
        let atts: [VkImageView?] = fdmView != nil ? [view, depth.view, fdmView] : [view, depth.view]
        guard !foveated || fdmView != nil else { throw VkError(what: "foveated target without a density map", code: -1) }
        ci.attachmentCount = UInt32(atts.count)
        ci.pAttachments = a.array(atts)
        ci.width = UInt32(width)
        ci.height = UInt32(height)
        ci.layers = 1                       // multiview: the layer count comes from the view mask
        var fb: VkFramebuffer?
        try vkCheck(vkCreateFramebuffer(ctx.device, &ci, nil, &fb), "vkCreateFramebuffer")
        let t = RenderTarget(ctx: ctx, image: image, view: view, depth: depth, framebuffer: fb!, width: width, height: height)
        t.fdmView = fdmView
        return t
    }

    // MARK: Frame

    // Waits for the next slot's previous use (and tells MeshArena which frame finished), returns it ready to record.
    func beginFrame() -> Slot {
        let s = slots[slotIdx]
        slotIdx = (slotIdx + 1) % slots.count
        if s.inUse {
            var f: VkFence? = s.fence
            vkWaitForFences(ctx.device, 1, &f, 1, UInt64.max)
            MeshArena.frameCompleted(s.submitted)
            QuestGraveyard.frameCompleted(s.submitted)
            s.inUse = false
            if s.timed, let qp = queryPool {
                var ts = [UInt64](repeating: 0, count: 2)
                if vkGetQueryPoolResults(ctx.device, qp, s.queryBase, 2, 16, &ts, 8, VK_QUERY_RESULT_64_BIT.rawValue) == VK_SUCCESS, ts[1] > ts[0] {
                    gpuMs = Double(ts[1] - ts[0]) * tsPeriod / 1e6
                }
            }
        }
        var f: VkFence? = s.fence
        vkResetFences(ctx.device, 1, &f)
        vkResetCommandBuffer(s.cmd, 0)
        var bi = VkCommandBufferBeginInfo()
        bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT.rawValue
        vkBeginCommandBuffer(s.cmd, &bi)
        if let qp = queryPool {
            vkCmdResetQueryPool(s.cmd, qp, s.queryBase, 2)
            vkCmdWriteTimestamp(s.cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, qp, s.queryBase)
            s.timed = true
        }
        return s
    }

    func beginPass(_ s: Slot, _ t: RenderTarget, clear: V3) {
        var clears = [VkClearValue(), VkClearValue()]
        clears[0].color.float32 = (clear.x, clear.y, clear.z, 1)
        clears[1].depthStencil = VkClearDepthStencilValue(depth: 1, stencil: 0)
        var rb = VkRenderPassBeginInfo()
        rb.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
        rb.renderPass = renderPass
        rb.framebuffer = t.framebuffer
        rb.renderArea = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(t.width), height: UInt32(t.height)))
        rb.clearValueCount = 2
        clears.withUnsafeBufferPointer { cp in
            rb.pClearValues = cp.baseAddress
            vkCmdBeginRenderPass(s.cmd, &rb, VK_SUBPASS_CONTENTS_INLINE)
        }
        // Flipped viewport (negative height): clip space keeps the Mac's y-up convention and winding.
        var vp = VkViewport(x: 0, y: Float(t.height), width: Float(t.width), height: -Float(t.height), minDepth: 0, maxDepth: 1)
        vkCmdSetViewport(s.cmd, 0, 1, &vp)
        var sc = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(t.width), height: UInt32(t.height)))
        vkCmdSetScissor(s.cmd, 0, 1, &sc)
        var set: VkDescriptorSet? = s.set0
        vkCmdBindDescriptorSets(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeLayout, 0, 1, &set, 0, nil)
    }

    func endPassAndSubmit(_ s: Slot, wait: VkSemaphore? = nil) throws {
        vkCmdEndRenderPass(s.cmd)
        try submit(s)
    }

    func submit(_ s: Slot) throws {
        if let qp = queryPool { vkCmdWriteTimestamp(s.cmd, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, qp, s.queryBase + 1) }
        vkEndCommandBuffer(s.cmd)
        s.submitted = MeshArena.frameSubmitted()
        QuestGraveyard.frameSubmitted(s.submitted)
        var si = VkSubmitInfo()
        si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
        si.commandBufferCount = 1
        var cb: VkCommandBuffer? = s.cmd
        try withUnsafePointer(to: &cb) { p in
            si.pCommandBuffers = p
            try vkCheck(vkQueueSubmit(ctx.queue, 1, &si, s.fence), "vkQueueSubmit")
        }
        s.inUse = true
    }

    func waitIdle() {
        vkDeviceWaitIdle(ctx.device)
        for s in slots where s.inUse { MeshArena.frameCompleted(s.submitted); QuestGraveyard.frameCompleted(s.submitted); s.inUse = false }
    }

    func setUniforms(_ s: Slot, _ u: FrameUniforms) {
        var v = u
        _ = withUnsafeBytes(of: &v) { memcpy(s.ubo.mapped!, $0.baseAddress!, $0.count) }
    }

    // Scratch vertices for this frame (returns the byte offset, or nil when full).
    private var scratchOff = 0
    func resetScratch() { scratchOff = 0 }
    func push<T>(_ s: Slot, _ items: [T], priority: Bool = false) -> Int? {
        if items.isEmpty { return nil }
        let n = items.count * MemoryLayout<T>.stride
        let off = (scratchOff + 255) & ~255
        guard off + n <= SceneRenderer.scratchSize - (priority ? 0 : SceneRenderer.handTail) else {
            if scratchFull == 0 { print("SceneRenderer: scratch ring full (\(off + n) bytes)") }
            scratchFull += 1
            return nil
        }
        _ = items.withUnsafeBytes { memcpy(s.scratch.mapped! + off, $0.baseAddress!, n) }
        scratchOff = off + n
        return off
    }
    // Raw room in the scratch ring for writers (EntityWriter / mob vertices): pointer, byte offset, capacity in items.
    func reserve<T>(_ s: Slot, _ type: T.Type, max cap: Int = Int.max, priority: Bool = false) -> (UnsafeMutablePointer<T>, Int, Int) {
        let off = (scratchOff + 255) & ~255
        let room = max(0, SceneRenderer.scratchSize - (priority ? 0 : SceneRenderer.handTail) - off) / MemoryLayout<T>.stride
        return ((s.scratch.mapped! + off).bindMemory(to: T.self, capacity: max(1, room)), off, min(room, cap))
    }
    func commit<T>(_ off: Int, _ count: Int, _ type: T.Type) { scratchOff = off + count * MemoryLayout<T>.stride }

    func drawScratch(_ s: Slot, _ pipeName: String, offset: Int, count: Int) {
        guard count > 0 else { return }
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe(pipeName))
        var b: VkBuffer? = s.scratch.buffer
        var o = VkDeviceSize(offset)
        vkCmdBindVertexBuffers(s.cmd, 0, 1, &b, &o)
        vkCmdDraw(s.cmd, UInt32(count), 1, 0, 0)
    }

    func drawStars(_ s: Slot) {
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe("star"))
        var b: VkBuffer? = starBuf.buffer
        var o: VkDeviceSize = 0
        vkCmdBindVertexBuffers(s.cmd, 0, 1, &b, &o)
        vkCmdDraw(s.cmd, UInt32(starVerts), 1, 0, 0)
    }

    func drawSky(_ s: Slot) {
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe("sky"))
        vkCmdDraw(s.cmd, 3, 1, 0, 0)
    }

    // MARK: Terrain

    private var visible: [(Chunk, Int, Float)] = []
    private var visitGen: [UInt32] = []
    private var gen: UInt32 = 0
    private var bfs: [(Chunk, Int, Int, Int, Int, Int)] = []
    private var chunkGrid: [Chunk?] = []

    // Sections to draw, near to far (the Mac renderer's cave-culling walk, Renderer.encode).
    func cull(_ world: World, eye: V3, frustum: Frustum) {
        let t0 = CFAbsoluteTimeGetCurrent()
        visible.removeAll(keepingCapacity: true)
        let pcx = floorDiv(Int(floor(eye.x)), CS), pcz = floorDiv(Int(floor(eye.z)), CS)
        let pSec = Int(floor(eye.y / 16))
        if caveCulling, let startC = world.chunks[ChunkKey(x: pcx, z: pcz)], pSec >= 0 && pSec < NSEC, startC.meshedOnce {
            let R = world.renderDistance + 1, span = 2 * R + 1
            let need = span * span * NSEC
            if visitGen.count < need { visitGen = [UInt32](repeating: 0, count: need) }
            gen &+= 1
            if gen == 0 { gen = 1; for i in visitGen.indices { visitGen[i] = 0 } }
            func vidx(_ dx: Int, _ dz: Int, _ sy: Int) -> Int { ((dx + R) + (dz + R) * span) * NSEC + sy }
            if chunkGrid.count != span * span { chunkGrid = [Chunk?](repeating: nil, count: span * span) }
            var topSec = 0
            for dz in -R...R { for dx in -R...R {
                let c = world.inMeshRadius(dx, dz) ? world.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)] : nil
                chunkGrid[(dx + R) + (dz + R) * span] = c
                if let c, c.topSec > topSec { topSec = c.topSec }
            } }
            let yLimit = max(pSec, topSec + 1)
            bfs.removeAll(keepingCapacity: true)
            bfs.append((startC, 0, 0, pSec, -1, 0))
            visitGen[vidx(0, 0, pSec)] = gen
            var head = 0
            let dirs = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
            while head < bfs.count {
                let (c, dx, dz, sy, entry, dirMask) = bfs[head]; head += 1
                let sec = c.sections[sy]
                let mn = V3(Float(c.cx * CS), Float(sy * 16), Float(c.cz * CS))
                if !sec.empty { visible.append((c, sy, simd_length_squared(mn + V3(8, 8, 8) - eye))) }
                let vis = sec.meshedVersion == -1 ? ~UInt64(0) : sec.vis
                for f in 0..<6 {
                    if dirMask & (1 << (f ^ 1)) != 0 { continue }
                    if entry >= 0 && vis & (1 << UInt64(entry * 6 + f)) == 0 { continue }
                    let (ox, oy, oz) = dirs[f]
                    let ndx = dx + ox, ndz = dz + oz, nsy = sy + oy
                    if nsy < 0 || nsy >= NSEC || nsy > yLimit || !world.inMeshRadius(ndx, ndz) || abs(ndx) > R || abs(ndz) > R { continue }
                    let vi = vidx(ndx, ndz, nsy)
                    if visitGen[vi] == gen { continue }
                    let nmn = V3(Float((pcx + ndx) * CS), Float(nsy * 16), Float((pcz + ndz) * CS))
                    if !frustum.visible(min: nmn, max: nmn + V3(16, 16, 16)) { continue }
                    guard let nc = ox == 0 && oz == 0 ? c : chunkGrid[(ndx + R) + (ndz + R) * span], nc.meshedOnce else { continue }
                    visitGen[vi] = gen
                    bfs.append((nc, ndx, ndz, nsy, f ^ 1, dirMask | (1 << f)))
                }
            }
        } else {
            for (_, c) in world.chunks where c.meshedOnce {
                let dx = c.cx - pcx, dz = c.cz - pcz
                if !world.inMeshRadius(dx, dz) { continue }
                let cmn = V3(Float(c.cx * CS), 0, Float(c.cz * CS))
                if !frustum.visible(min: cmn, max: cmn + V3(16, Float(CH), 16)) { continue }
                for (sy, sec) in c.sections.enumerated() where !sec.empty {
                    let mn = V3(cmn.x, Float(sy * 16), cmn.z)
                    if !frustum.visible(min: mn, max: mn + V3(16, 16, 16)) { continue }
                    visible.append((c, sy, simd_length_squared(mn + V3(8, 8, 8) - eye)))
                }
            }
        }
        visible.sort { $0.2 < $1.2 }
        visibleCount = visible.count
        cullMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }

    // Writes the section records for the culled list (camera-relative origins) into the slot.
    private var nRec = 0
    func writeRecords(_ s: Slot, eye: V3) {
        nRec = min(visible.count, SceneRenderer.recordCap)
        let recs = s.records.mapped!.bindMemory(to: SectionRec.self, capacity: max(1, nRec))
        for i in 0..<nRec {
            let (c, sy, _) = visible[i]
            recs[i] = SectionRec(x: Float(c.cx * CS) - eye.x, y: Float(sy * 16) - eye.y, z: Float(c.cz * CS) - eye.z,
                                 tint: UInt32((c.tintBuf?.offset ?? 0) / 4))
        }
    }

    private var boundVerts: QuestBuffer?
    private var boundTints: QuestBuffer?
    private func drawSection(_ s: Slot, _ i: Int, _ slice: MeshSlice, _ tb: MeshSlice, first: Int, count: Int) {
        guard let vb = slice.buffer as? QuestBuffer, let tbuf = tb.buffer as? QuestBuffer else { return }
        drawCalls += 1; drawnQuads += count
        if tbuf !== boundTints, let set = tintSet(tbuf) {
            var ss: VkDescriptorSet? = set
            vkCmdBindDescriptorSets(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeLayout, 1, 1, &ss, 0, nil)
            boundTints = tbuf
        }
        if vb !== boundVerts {
            var b: VkBuffer? = vb.vkBuffer
            var o: VkDeviceSize = 0
            vkCmdBindVertexBuffers(s.cmd, 0, 1, &b, &o)
            boundVerts = vb
        }
        vkCmdDrawIndexed(s.cmd, UInt32(count * 6), 1, UInt32(first * 6), Int32(slice.offset / 8), UInt32(i))
    }

    private func bindTerrainBuffers(_ s: Slot) {
        vkCmdBindIndexBuffer(s.cmd, quadIndex.buffer, 0, VK_INDEX_TYPE_UINT32)
        var b: VkBuffer? = s.records.buffer
        var o: VkDeviceSize = 0
        vkCmdBindVertexBuffers(s.cmd, 1, 1, &b, &o)
        boundVerts = nil; boundTints = nil
    }

    // Opaque terrain: solid faces first (no alpha test), then cutout faces, near to far.
    func drawOpaque(_ s: Slot) {
        drawCalls = 0; drawnQuads = 0
        bindTerrainBuffers(s)
        for pass in 0..<2 {
            vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe(pass == 0 ? "solid" : "cut"))
            for i in 0..<nRec {
                let (c, sy, _) = visible[i]
                let sec = c.sections[sy]
                guard sec.opaqueQuads > 0, let buf = sec.opaqueBuf, let tb = c.tintBuf else { continue }
                let total = min(sec.opaqueQuads, SceneRenderer.maxQuads), solid = min(sec.solidQuads, total)
                let first = pass == 0 ? 0 : solid, count = pass == 0 ? solid : total - solid
                if count <= 0 { continue }
                drawSection(s, i, buf, tb, first: first, count: count)
            }
        }
    }

    // Water and other translucent faces, far to near.
    func drawTranslucent(_ s: Slot, underwater: Bool = false) {
        bindTerrainBuffers(s)
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe(underwater ? "waterUnder" : "water"))
        for i in stride(from: nRec - 1, through: 0, by: -1) {
            let (c, sy, _) = visible[i]
            let sec = c.sections[sy]
            guard sec.transQuads > 0, let buf = sec.transBuf, let tb = c.tintBuf else { continue }
            drawSection(s, i, buf, tb, first: 0, count: min(sec.transQuads, SceneRenderer.maxQuads))
        }
    }

    func pushShip(_ s: Slot, model: float4x4, origin: V4, fog: V4) {
        var pc = (model, origin, fog)
        withUnsafeBytes(of: &pc) { raw in
            vkCmdPushConstants(s.cmd, pipeLayout, VK_SHADER_STAGE_VERTEX_BIT.rawValue | VK_SHADER_STAGE_FRAGMENT_BIT.rawValue, 0, 96, raw.baseAddress)
        }
    }

    // Binds a mesh slice's buffer at vertex binding 0 and draws `count` quads from `first` (ships, props).
    func drawQuads(_ s: Slot, _ slice: MeshSlice, first: Int, count: Int) {
        guard count > 0, let vb = slice.buffer as? QuestBuffer else { return }
        var b: VkBuffer? = vb.vkBuffer
        var o = VkDeviceSize(slice.offset)
        vkCmdBindVertexBuffers(s.cmd, 0, 1, &b, &o)
        vkCmdBindIndexBuffer(s.cmd, quadIndex.buffer, 0, VK_INDEX_TYPE_UINT32)
        vkCmdDrawIndexed(s.cmd, UInt32(count * 6), 1, UInt32(first * 6), 0, 0)
        drawCalls += 1
        boundVerts = nil
    }

    func pushConstants(_ s: Slot, model: float4x4, extra: V4) {
        var pc = (model, extra)
        withUnsafeBytes(of: &pc) { raw in
            vkCmdPushConstants(s.cmd, pipeLayout, VK_SHADER_STAGE_VERTEX_BIT.rawValue | VK_SHADER_STAGE_FRAGMENT_BIT.rawValue, 0, 80, raw.baseAddress)
        }
    }
}
