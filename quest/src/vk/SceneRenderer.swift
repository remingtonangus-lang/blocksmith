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
    var clouds = V4(0, 0, 0.45, 0)   // clouds.frag: eye in cloud space (xz), cover, storm flash (SkyLook.swift)
    var cloudFlash = V4(0, 0.3, 1, 0) // flash direction, storm darkness
    var wind = V4(1, 0, 0, 1)        // wind direction (xz), biome haze, cave dimming
    var fx = V4(Float(ShaderFX.all), 0, 0, 0)   // SH1: piece bits (ShaderFX), valley mist strength, mist top (world y), grade
    // SH1 sheen: a bit per texture layer that shines like metal or ice (ShaderFX.sheenBits), 2048 bits.
    var sheen: (U4, U4, U4, U4, U4, U4, U4, U4, U4, U4, U4, U4, U4, U4, U4, U4) =
        (U4(), U4(), U4(), U4(), U4(), U4(), U4(), U4(), U4(), U4(), U4(), U4(), U4(), U4(), U4(), U4())
    typealias U4 = SIMD4<UInt32>
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
    var swSet: VkDescriptorSet?                 // P381 step 9: the depth, sampled by the space warp pass
    var depthSampleView: VkImageView?
    deinit {
        if let d = depthSampleView { vkDestroyImageView(ctx.device, d, nil) }
        vkDestroyFramebuffer(ctx.device, framebuffer, nil)
        vkDestroyImageView(ctx.device, view, nil)
        if let f = fdmView { vkDestroyImageView(ctx.device, f, nil) }
    }
}

// P385: the cull walk's per-section marks (generation numbers) in memory of their own: as arrays held by the renderer
// every mark read or written in the walk was an exclusivity check and a uniqueness check on the host build.
final class RawMarks {
    let count: Int
    let visit, found, frustum: UnsafeMutablePointer<UInt32>
    let viewOK: UnsafeMutablePointer<UInt8>
    init(_ n: Int) {
        count = n
        let m = max(1, n)
        visit = .allocate(capacity: m); found = .allocate(capacity: m); frustum = .allocate(capacity: m); viewOK = .allocate(capacity: m)
        clear()
    }
    func clear() {
        let m = max(1, count)
        visit.initialize(repeating: 0, count: m); found.initialize(repeating: 0, count: m)
        frustum.initialize(repeating: 0, count: m); viewOK.initialize(repeating: 0, count: m)
    }
    deinit { visit.deallocate(); found.deallocate(); frustum.deallocate(); viewOK.deallocate() }
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
        var indirect: VkBuf!           // terrain draw commands (P146 batching)
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

    // P403 7b (Application SpaceWarp on by default): this frame's draws of things that move on their own (the hands and
    // what they hold, mobs, ships), drawn again by SpaceWarpPass into the motion vectors. prev maps a drawn
    // (camera-relative) vertex to where that point was at the last drawn frame. Collected only with space warp on.
    struct MotionDraw { var input: Input; var buffer: VkBuffer?; var offset: Int; var count: Int; var prev: float4x4 }
    private(set) var motionDraws: [MotionDraw] = []
    var spaceWarpOn = false                 // P426: this frame goes to the runtime with motion vectors (QuestApp, per frame)
    func addMotion(_ s: Slot, _ input: Input, buffer: VkBuffer? = nil, offset: Int, count: Int, prev: float4x4) {
        guard spaceWarp, spaceWarpOn, count > 0 else { return }
        motionDraws.append(MotionDraw(input: input, buffer: buffer ?? s.scratch.buffer, offset: offset, count: count, prev: prev))
    }
    // The prev matrix of a rigid thing at pose (pos camera-relative, rot) now and (wasPos camera-relative, wasRot) at
    // the last drawn frame.
    static func motion(pos: V3, rot: simd_quatf, wasPos: V3, wasRot: simd_quatf) -> float4x4 {
        let d = wasRot * rot.inverse
        var m = float4x4(d)
        let t = wasPos - d.act(pos)
        m.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
        return m
    }
    static func motion(moved d: V3) -> float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(-d.x, -d.y, -d.z, 1)
        return m
    }

    // Stats (last frame).
    private(set) var drawCalls = 0
    private(set) var drawnQuads = 0
    private(set) var visibleCount = 0
    private(set) var cullMs = 0.0
    var caveCulling = true
    // P339: sections hidden behind nearer hills are left out (horizonCull). BS_HORIZON=0 turns it off.
    var horizonCulling = ProcessInfo.processInfo.environment["BS_HORIZON"] != "0"
    private(set) var horizonSkipped = 0
    private static let hBins = 1024
    private var hTop = [Float](repeating: 0, count: SceneRenderer.hBins), hBot = [Float](repeating: 0, count: SceneRenderer.hBins)
    private var occluders: [(dmax: Float, b0: Int, b1: Int, top: Float, bot: Float)] = []
    // P376 step 5: occlusion culling (occlusionCull) of section boxes against nearer solid sections, on top of the
    // horizon culling. BS_OCCLUSION=0 turns it off. occlusionVP: world to clip of the frustum enclosing both eyes.
    var occlusionCulling = ProcessInfo.processInfo.environment["BS_OCCLUSION"] != "0"
    var occlusionVP: float4x4? = nil
    private(set) var occlusionSkipped = 0, occluderBoxes = 0, occlusionMs = 0.0
    static let oW = 192, oH = 112, oT = 8                    // the buffer, and its 8 x 8 tiles' nearest and farthest depth
    private var oDepth = [Float](repeating: .infinity, count: SceneRenderer.oW * SceneRenderer.oH)
    private var oTileMin = [Float](repeating: .infinity, count: (SceneRenderer.oW / 8) * (SceneRenderer.oH / 8))
    private var oTileMax = [Float](repeating: .infinity, count: (SceneRenderer.oW / 8) * (SceneRenderer.oH / 8))
    var maxSection = NSEC          // sections from here up are left out (the Ash Vault's sky, AshSky.swift)
    // The fog budget (the Ash Vault, gap pass D5/DE14): sections wholly past this distance are neither walked nor drawn
    // (they would come out the fog colour). 0: off. `fogCullOff` lets questcheck measure the battle without it.
    var fogCull: Float = 0
    static var fogCullOff = false
    @inline(__always) private func pastFog(_ mn: V3, _ eye: V3) -> Bool {
        guard fogCull > 0, !SceneRenderer.fogCullOff else { return false }
        let q = simd_clamp(eye, mn, mn + V3(16, 16, 16))
        return simd_length_squared(q - eye) > fogCull * fogCull
    }
    // The swapchain is sRGB: shaders compute display (gamma) values like the Mac, so they write them back to linear.
    var linearOutput = false
    static func isSRGB(_ f: VkFormat) -> Bool { f == VK_FORMAT_R8G8B8A8_SRGB || f == VK_FORMAT_B8G8R8A8_SRGB }

    // Fixed foveated rendering: the render pass takes the runtime's fragment density map as a third attachment.
    let foveated: Bool
    // P381 step 9 (Application SpaceWarp): the depth is kept after the pass and copied down for the runtime.
    let spaceWarp: Bool

    init(ctx: VkContext, device: QuestDevice, views: Int, colorFormat: VkFormat, foveated: Bool = false, spaceWarp: Bool = false) throws {
        self.ctx = ctx
        self.device = device
        self.views = views
        self.colorFormat = colorFormat
        self.foveated = foveated
        self.spaceWarp = spaceWarp
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
        depth.storeOp = spaceWarp ? VK_ATTACHMENT_STORE_OP_STORE : VK_ATTACHMENT_STORE_OP_DONT_CARE
        depth.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        depth.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        depth.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        depth.finalLayout = spaceWarp ? VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL : VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        var sub = VkSubpassDescription()
        sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
        sub.colorAttachmentCount = 1
        sub.pColorAttachments = a.ptr(VkAttachmentReference(attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL))
        sub.pDepthStencilAttachment = a.ptr(VkAttachmentReference(attachment: 1, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL))
        // External dependencies: the previous user of the colour image (compositor / last frame) and depth reuse.
        let fragTests = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT.rawValue | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT.rawValue
        let colorOut = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue
        let deps = [
            VkSubpassDependency(srcSubpass: VK_SUBPASS_EXTERNAL, dstSubpass: 0,
                                srcStageMask: colorOut | fragTests | (spaceWarp ? VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue : 0), dstStageMask: colorOut | fragTests,
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

    enum Input { case none, chunk, detail, ship, simple, mob, entity, hud }
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
        case .detail:
            // Realistic world: round shapes (DetailMesh, 16-byte vertices) with the same section records.
            bindings = [VkVertexInputBindingDescription(binding: 0, stride: 16, inputRate: vtx),
                        VkVertexInputBindingDescription(binding: 1, stride: 16, inputRate: inst)]
            attrs = [VkVertexInputAttributeDescription(location: 0, binding: 0, format: VK_FORMAT_R32G32B32A32_UINT, offset: 0),
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
            "detail": PipeDesc(vert: "chunk_detail.vert", frag: "chunk_solid.frag", input: .detail),
            "detailCut": PipeDesc(vert: "chunk_detail.vert", frag: "chunk_cut.frag", input: .detail, cull: none),
            // Translucent faces cull their backs from above the water: with no depth write and no per-face sorting, the
            // inner side faces of a pool's edge, a drop-off or a waterfall blended over the surface in front of them (the
            // "see-through glitch" at water edges, Quest v63). Under water the surface is seen from below: no culling.
            "water": PipeDesc(vert: "chunk.vert", frag: "water.frag", input: .chunk, blend: true, depthWrite: false, compare: le),
            "waterUnder": PipeDesc(vert: "chunk.vert", frag: "water.frag", input: .chunk, blend: true, depthWrite: false, compare: le, cull: none),
            "sky": PipeDesc(vert: "sky.vert", frag: "sky.frag", depthWrite: false, compare: le, cull: none),
            "clouds": PipeDesc(vert: "sky.vert", frag: "clouds.frag", blend: true, depthWrite: false, compare: le, cull: none),
            "star": PipeDesc(vert: "star.vert", frag: "star.frag", input: .simple, blend: true, depthWrite: false, compare: le, cull: none),
            "body": PipeDesc(vert: "body.vert", frag: "crack.frag", input: .entity, blend: true, depthWrite: false, compare: le, cull: none),
            "simple": PipeDesc(vert: "simple.vert", frag: "simple.frag", input: .simple, blend: true, depthWrite: false, compare: le, cull: none),
            "simpleSolid": PipeDesc(vert: "simple.vert", frag: "simple.frag", input: .simple, cull: none),
            // F4 middle ring (Sources/FarRing.swift): opaque, depth-tested and depth-writing, behind the loaded chunks.
            "far": PipeDesc(vert: "far.vert", frag: "simple.frag", input: .simple, cull: none),
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
        // LINEAR magnification for the shaders' sharp-bilinear texSharp (common.glsl): crisp texels with anti-aliased
        // edges; nearest made 6-12 px stair-steps at arm's length that crawl with head motion. Anisotropy 8 (was 4)
        // for the ground at a slant (tools/texsharp.py: far-ground PSNR 34.7 -> 39.6 dB with the Lanczos mips).
        si.magFilter = VK_FILTER_LINEAR
        si.minFilter = VK_FILTER_LINEAR
        si.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR
        si.addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT
        si.addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT
        si.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT
        si.maxLod = 16
        if ctx.features.samplerAnisotropy != 0 { si.anisotropyEnable = 1; si.maxAnisotropy = min(8, ctx.props.limits.maxSamplerAnisotropy) }
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
        // (BS_P401=0: a pregenerated chain staged whole, as before, for the before/after numbers)
        let batch = pregenerated != nil && !TextureCache.lean ? layers : 256
        var first = 0
        // P401: the pregenerated chain is staged a batch of layers at a time too (it was staged whole: a second 166 MB
        // copy beside the chain and the image at the launch's peak); each level's bytes for the batch are copied
        // straight from the chain into a staging buffer of about 22 MB.
        // (a chain made before a late texture name was registered covers fewer layers than the image: those stay blank)
        let filled = pregenerated.map { min(layers, ($0.first?.count ?? 0) / (size * size * 4)) } ?? layers
        while first < filled {
            let range = first..<min(filled, first + batch)
            let painted = pregenerated == nil ? TextureGen.mipChain(layers: range) : []
            // Level lvl's bytes for the batch, from the chain (pregenerated: every layer; painted: this batch's).
            func levelBytes(_ lvl: Int, _ body: (UnsafeRawBufferPointer) -> Void) {
                let sz = max(1, size >> lvl), per = sz * sz * 4
                if let pre = pregenerated {
                    pre[lvl].withUnsafeBytes { all in body(UnsafeRawBufferPointer(rebasing: all[(range.lowerBound * per)..<(range.upperBound * per)])) }
                } else {
                    painted[lvl].withUnsafeBytes { body($0) }
                }
            }
            let chainLevels = min(levels, pregenerated?.count ?? painted.count)
            // Held items' extrusion masks (ItemExtrude.swift) from the full-size level.
            levelBytes(0) { b in ItemMasks.record(b.bindMemory(to: UInt8.self), size: size, layers: range) }
            var total = 0
            for lvl in 0..<chainLevels { let sz = max(1, size >> lvl); total += sz * sz * 4 * range.count }
            let staging = try VkBuf(ctx, size: total, usage: VK_BUFFER_USAGE_TRANSFER_SRC_BIT.rawValue, host: true)
            var regions: [VkBufferImageCopy] = []
            var off = 0
            for lvl in 0..<chainLevels {
                let sz = max(1, size >> lvl)
                var n = 0
                levelBytes(lvl) { b in memcpy(staging.mapped! + off, b.baseAddress!, b.count); n = b.count }
                var r = VkBufferImageCopy()
                r.bufferOffset = VkDeviceSize(off)
                r.imageSubresource = VkImageSubresourceLayers(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, mipLevel: UInt32(lvl),
                                                              baseArrayLayer: UInt32(range.lowerBound), layerCount: UInt32(range.count))
                r.imageExtent = VkExtent3D(width: UInt32(sz), height: UInt32(sz), depth: 1)
                regions.append(r)
                off += n
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
        if batchable {
            s.indirect = try VkBuf(ctx, size: SceneRenderer.recordCap * 2 * MemoryLayout<VkDrawIndexedIndirectCommand>.stride,
                                   usage: VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT.rawValue, host: true)
        }
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
                              usage: VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue | (spaceWarp ? VK_IMAGE_USAGE_SAMPLED_BIT.rawValue : 0),
                              aspect: VK_IMAGE_ASPECT_DEPTH_BIT.rawValue,
                              transient: !spaceWarp && ProcessInfo.processInfo.environment["QUEST_NO_TRANSIENT"] == nil)
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
        if spaceWarp {
            let dv = try VkImg.makeView(ctx, depth.image, format: depthFormat, aspect: VK_IMAGE_ASPECT_DEPTH_BIT.rawValue, layers: views, levels: 1, array: true)
            t.depthSampleView = dv
            let set = try allocSet(set2Layout)
            let a2 = PtrArena()
            var w = VkWriteDescriptorSet()
            w.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            w.dstSet = set
            w.dstBinding = 0
            w.descriptorCount = 1
            w.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
            w.pImageInfo = a2.ptr(VkDescriptorImageInfo(sampler: try nearestSampler(), imageView: dv, imageLayout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL))
            vkUpdateDescriptorSets(ctx.device, 1, &w, 0, nil)
            t.swSet = set
        }
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
        motionDraws.removeAll(keepingCapacity: true)
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

    // P381 step 9: a nearest-filtering, clamped sampler (the space warp pass reads the depth with it).
    private var nearest: VkSampler?
    func nearestSampler() throws -> VkSampler {
        if let n = nearest { return n }
        var si = VkSamplerCreateInfo()
        si.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
        si.magFilter = VK_FILTER_NEAREST
        si.minFilter = VK_FILTER_NEAREST
        si.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST
        si.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        si.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        si.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        var smp: VkSampler?
        try vkCheck(vkCreateSampler(ctx.device, &si, nil, &smp), "vkCreateSampler(nearest)")
        nearest = smp
        return smp!
    }

    // P403 7b: the share of the target the eyes are drawn into this frame (DynamicResolution), and that rectangle.
    var viewScale: Float = 1
    func viewExtent(_ t: RenderTarget) -> (Int, Int) {
        viewScale >= 0.999 ? (t.width, t.height)
            : (max(16, Int(Float(t.width) * viewScale) & ~1), max(16, Int(Float(t.height) * viewScale) & ~1))
    }
    func beginPass(_ s: Slot, _ t: RenderTarget, clear: V3) {
        let (w, h) = viewExtent(t)
        var clears = [VkClearValue(), VkClearValue()]
        clears[0].color.float32 = (clear.x, clear.y, clear.z, 1)
        clears[1].depthStencil = VkClearDepthStencilValue(depth: 1, stencil: 0)
        var rb = VkRenderPassBeginInfo()
        rb.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
        rb.renderPass = renderPass
        rb.framebuffer = t.framebuffer
        rb.renderArea = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(w), height: UInt32(h)))
        rb.clearValueCount = 2
        clears.withUnsafeBufferPointer { cp in
            rb.pClearValues = cp.baseAddress
            vkCmdBeginRenderPass(s.cmd, &rb, VK_SUBPASS_CONTENTS_INLINE)
        }
        // Flipped viewport (negative height): clip space keeps the Mac's y-up convention and winding.
        var vp = VkViewport(x: 0, y: Float(h), width: Float(w), height: -Float(h), minDepth: 0, maxDepth: 1)
        vkCmdSetViewport(s.cmd, 0, 1, &vp)
        var sc = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(w), height: UInt32(h)))
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
        si.commandBufferCount = SceneRenderer.skipGPU ? 0 : 1      // (an empty batch still signals the slot's fence)
        var cb: VkCommandBuffer? = s.cmd
        try withUnsafePointer(to: &cb) { p in
            si.pCommandBuffers = p
            try vkCheck(vkQueueSubmit(ctx.queue, 1, &si, s.fence), "vkQueueSubmit")
        }
        s.inUse = true
    }

    // questcheck --perfscenes (QuestPerf): frames are recorded in full and their commands dropped, since lavapipe would
    // spend about a second a frame shading half a million quads on the CPU and the Quest's GPU is not measured here.
    static var skipGPU = false

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

    // The same from a vertex buffer of the caller's (P283: WorldRenderer's landmark shell).
    func drawBuffer(_ s: Slot, _ pipeName: String, _ buffer: VkBuffer?, offset: Int, count: Int) {
        guard count > 0, buffer != nil else { return }
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe(pipeName))
        var b: VkBuffer? = buffer
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

    func drawClouds(_ s: Slot) {
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe("clouds"))
        vkCmdDraw(s.cmd, 3, 1, 0, 0)
    }

    func drawSky(_ s: Slot) {
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe("sky"))
        vkCmdDraw(s.cmd, 3, 1, 0, 0)
    }

    // MARK: Terrain

    private var visible: [(Chunk, Int, Float)] = []
    private var visitGen: [UInt32] = []
    private var foundGen: [UInt32] = []          // P335: a section listed to draw (walked through, or only peeked at)
    private var gen: UInt32 = 0
    // P283: the walk's queue holds plain numbers (the column in chunkGrid, the offsets, the section, the face it came in
    // by and the faces it went out by) and the sections found are sorted as packed keys: a chunk reference in every queue
    // entry and in every swap of the sort cost a retain and a release each, a large part of the frame's cull.
    private struct CullNode { var col: Int32; var dx: Int16; var dz: Int16; var sy: Int16; var entry: Int8; var mask: UInt8 }
    private var bfs: [CullNode] = []
    private var found: [UInt64] = []             // distance bits << 32 | column << 8 | section
    private(set) var cullVisits = 0              // sections the last walk went through
    private var chunkGrid: [Chunk?] = []

    // P385: the cull table (the extension at the end of this file). Per loaded column in reach (toroidal: a column's
    // slot is its chunk coordinates modulo the span, so moving the eye a chunk re-reads only the columns that came into
    // reach) the facts the walk, the horizon and occlusion culls, the section records and the draw lists need, in plain
    // arrays: the walk took a retain and a release of a chunk, its section array and a section at every step, most of
    // the frame's cull. A column is re-read only when its chunk changed (Chunk.cullStamp, its blocks, detail level or
    // shell state), so each section's draw entries (its slab pair, vertex offset and counts) persist between frames.
    // BS_FASTCULL=0: the walk and draws as before.
    static var fastCull = ProcessInfo.processInfo.environment["BS_FASTCULL"] != "0"
    struct ColKey: Equatable { var stamp = -1, bv = -1, lod = -1, flags = -1 }
    struct ColInfo {
        var cx: Int32 = 0, cz: Int32 = 0, occTop: Int32 = -1, tintOff: UInt32 = 0
        var topSec: Int16 = 0, present = false, meshedOnce = false, lod1 = false
        var openLow: Int16 = 0                 // P392: the lowest sky-open section (NSEC: none)
    }
    struct SecInfo {
        var vis: UInt64 = 0
        var flags: UInt32 = 0                  // SecInfo.nonEmpty, .meshed, .deep, .solidFull
        var oPair: Int32 = -1, oVo: Int32 = 0, quads: Int32 = 0, solid: Int32 = 0, fSkip: Int32 = 0, fExtra: Int32 = 0
        var farCut: Int32 = 0, farTail: Int32 = 0
        var dPair: Int32 = -1, dVo: Int32 = 0, dQuads: Int32 = 0, dSolid: Int32 = 0, dSkip: Int32 = 0, dExtra: Int32 = 0
        var tPair: Int32 = -1, tVo: Int32 = 0, tQuads: Int32 = 0
        static let nonEmpty: UInt32 = 1, meshed: UInt32 = 2, deep: UInt32 = 4, solidFull: UInt32 = 8
    }
    private var tabSpan = 0
    private var tabChunk: [Chunk?] = []
    private var tabKey: [ColKey] = []
    private var tabCol: [ColInfo] = []
    private var tabSec: [SecInfo] = []
    private var tabSeen: [UInt32] = []          // (horizon cull: a column taken as an occluder this frame)
    private var slotX: [Int] = [], slotZ: [Int] = []
    private(set) var tableRefreshed = 0          // columns re-read last frame
    private var tableFrame = false               // this frame's list is `vl` (table slots), not `visible`
    private var vl: [Int32] = []                 // visible sections, near to far: slot * NSEC + sy
    private var slabIdx: [ObjectIdentifier: Int32] = [:]
    private var slabBufs: [QuestBuffer] = []
    private var pairIdx: [Int64: Int32] = [:]
    private var pairBufs: [(QuestBuffer, QuestBuffer)] = []
    private var pairK: [Int32] = []
    private var keysT: [Int32] = []
    // Where the cull's time went last frame (ms): the table, the walk (and its sort), horizon, occlusion, the list.
    private(set) var cullStageMs = [Double](repeating: 0, count: 5)
    // The walk's own facts per section, packed (vis bits; flags as SecInfo's): the full SecInfo table is several MB at
    // view 24 and the walk touched one entry per step, nearly every one a cache miss.
    private var tabVis: [UInt64] = []
    private var sealLow: [Int16] = []          // P392: per slot, sections under this are sealed this frame
    private var sealRow: [Int16] = []
    private var sealValid = false, sealEye = V3(0, 0, 0), sealPC = SIMD2<Int32>(0, 0), sealEyeLow = 0
    private var tabFl: [UInt8] = []
    // Columns held, for the frames where nothing was loaded or dropped and the eye stayed in its chunk: then only
    // their keys are compared (no lookups). BS_TABLEEPOCH=0: every column looked up every frame.
    static var epochTable = ProcessInfo.processInfo.environment["BS_TABLEEPOCH"] != "0"
    private struct LiveCol { var slot: Int; unowned(unsafe) var c: Chunk }
    private var tabLive: [LiveCol] = []
    private var tabEpoch = -1, tabPCX = Int.min, tabPCZ = Int.min, tabWorld: ObjectIdentifier?
    // The walk's marks (visited, listed, frustum tested and its answer), in plain memory.
    private var tMarks = RawMarks(0)
    private var noteBuf: [Int64] = []
    // The horizon cull's occluders not applied yet, kept by far distance (seq: the order they were taken).
    private struct HOcc { var dmax: Float; var b0: Int; var b1: Int; var top: Float; var bot: Float; var seq: Int32 }
    private var hOcc: [HOcc] = []
    private var hBatch: [HOcc] = []
    // The horizon cull's footprint of a column (angles and distances), once a frame per column.
    private var fpGen: [UInt32] = []
    private var fpV: [SIMD4<Float>] = []
    // The occluder boxes are drawn into the depth buffer on a worker while the walk runs (they need only the table).
    // BS_OCCPAR=0: drawn on the main thread after the horizon cull, as before.
    static var occParallel = ProcessInfo.processInfo.environment["BS_OCCPAR"] != "0"
    let occWork = FrameWork(label: "occlusion-raster")
    private(set) var occRasterMs = 0.0

    // Sections to draw, near to far (the Mac renderer's cave-culling walk, Renderer.encode).
    // P339 (full detail out to 24 chunks, Remington Oct 18: cost down by culling, never by lowering far detail): horizon
    // culling over the walk's found sections, nearest first. Each chunk whose columns are all solid for 16 cells under
    // `Chunk.occluderTop` (H) is an occluder over the azimuth bins wholly inside its footprint: a sight line in those bins
    // crossing it between the elevations of H and H - 16 (taken at the worse of its near and far distance) is stopped
    // inside that solid band. A section farther than the occluder's far corner whose whole box lies between those two
    // elevations in every bin it spans is hidden. Occluders apply only to sections past their far corner, so nothing
    // beside or above one is ever taken out; sections round the eye's column are never tested.
    private func horizonCull(eye: V3, R: Int, span: Int) {
        let B = SceneRenderer.hBins
        let toBin = Float(B) / (2 * Float.pi)
        for b in 0..<B { hTop[b] = -.infinity; hBot[b] = .infinity }
        occluders.removeAll(keepingCapacity: true)
        horizonSkipped = 0
        var applied = 0
        var seen = Set<Int>()
        // The footprint's azimuth range (bins, unwrapped round its centre) and its near and far horizontal distances.
        func footprint(_ x0: Float, _ z0: Float, _ w: Float) -> (a0: Float, a1: Float, dmin: Float, dmax: Float)? {
            let cx = x0 + w / 2, cz = z0 + w / 2
            let nx = max(x0, min(eye.x, x0 + w)), nz = max(z0, min(eye.z, z0 + w))
            let dmin = ((nx - eye.x) * (nx - eye.x) + (nz - eye.z) * (nz - eye.z)).squareRoot()
            if dmin < 1 { return nil }
            let ac = atan2(cz - eye.z, cx - eye.x)
            var a0 = Float.infinity, a1 = -Float.infinity, dmax: Float = 0
            for (x, z) in [(x0, z0), (x0 + w, z0), (x0, z0 + w), (x0 + w, z0 + w)] {
                var a = atan2(z - eye.z, x - eye.x) - ac
                if a > .pi { a -= 2 * .pi } else if a < -.pi { a += 2 * .pi }
                a0 = min(a0, a); a1 = max(a1, a)
                dmax = max(dmax, ((x - eye.x) * (x - eye.x) + (z - eye.z) * (z - eye.z)).squareRoot())
            }
            return ((ac + a0) * toBin, (ac + a1) * toBin, dmin, dmax)
        }
        var out = 0
        for k in 0..<found.count {
            let key = found[k]
            let col = Int((key >> 8) & 0xFF_FFFF), sy = Int(key & 0xFF)
            guard let c = chunkGrid[col] else { continue }
            let x0 = Float(c.cx * CS), z0 = Float(c.cz * CS)
            var hidden = false
            if let fp = footprint(x0, z0, 16) {
                // Occluders whose far corner is nearer than this section's nearest point.
                for o in occluders where o.dmax <= fp.dmin && o.dmax >= 0 {
                    for b in o.b0...o.b1 {
                        let m = ((b % B) + B) % B
                        if o.top > hTop[m] { hTop[m] = o.top; hBot[m] = o.bot }
                    }
                    applied += 1
                }
                if applied > 0 { occluders.removeAll { $0.dmax <= fp.dmin }; applied = 0 }
                let y0 = Float(sy * 16) - eye.y, y1 = y0 + 16
                let eMax = y1 > 0 ? y1 / fp.dmin : y1 / fp.dmax, eMin = y0 < 0 ? y0 / fp.dmin : y0 / fp.dmax
                let b0 = Int(floor(fp.a0)), b1 = Int(floor(fp.a1))
                if b1 - b0 < B / 4 {
                    hidden = true
                    for b in b0...b1 {
                        let m = ((b % B) + B) % B
                        if !(eMax < hTop[m] && eMin > hBot[m]) { hidden = false; break }
                    }
                }
                // This chunk as an occluder, once.
                if !seen.contains(col) {
                    seen.insert(col)
                    let H = c.occluderTop
                    if H > 0 {
                        let ht = Float(H) - eye.y, hb = ht - 16
                        let top = min(ht / fp.dmin, ht / fp.dmax), bot = max(hb / fp.dmin, hb / fp.dmax)
                        let ib0 = Int(ceil(fp.a0)), ib1 = Int(floor(fp.a1)) - 1
                        if ib1 >= ib0 && top > bot { occluders.append((fp.dmax, ib0, ib1, top, bot)) }
                    }
                }
            }
            if hidden { horizonSkipped += 1; continue }
            found[out] = key; out += 1
        }
        found.removeLast(found.count - out)
    }

    // P376 step 5: a small software depth buffer over the frustum enclosing both eyes. Occluders are the sections whose
    // every cell is opaque (Section.solidFull), runs of them up a column merged into one box, each shrunk by two blocks
    // a side (a smooth surface can sink into its outer cells), within `occluderChunks` of the eye; each is drawn into the
    // buffer conservatively: only pixels wholly inside its outline, at the depth of its farthest corner. A section is
    // hidden when its box, grown by two blocks a side (a smooth surface can rise out of it), covers only pixels already
    // nearer than its nearest corner. Sections round the eye, and any box reaching behind the near plane, stay.
    static let occluderChunks = 10
    private func occlusionCull(eye: V3, R: Int, span: Int) {
        occlusionSkipped = 0; occluderBoxes = 0
        let t0 = CFAbsoluteTimeGetCurrent()
        defer { occlusionMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000 }
        guard let vp = occlusionVP else { return }
        let W = SceneRenderer.oW, H = SceneRenderer.oH
        for i in 0..<(W * H) { oDepth[i] = .infinity }
        let near: Float = 0.5
        // Clip -> pixel space (x right, y down) and the view depth w.
        func project(_ p: V3) -> SIMD3<Float> {
            let c = vp * SIMD4<Float>(p.x, p.y, p.z, 1)
            if c.w <= near { return SIMD3(0, 0, -1) }
            return SIMD3((c.x / c.w * 0.5 + 0.5) * Float(W), (0.5 - c.y / c.w * 0.5) * Float(H), c.w)
        }
        var pts = [SIMD2<Float>](repeating: .zero, count: 8)
        var hull: [SIMD2<Float>] = []
        func corners(_ mn: V3, _ mx: V3, _ body: (Int, V3) -> Void) {
            for k in 0..<8 { body(k, V3(k & 1 == 0 ? mn.x : mx.x, k & 2 == 0 ? mn.y : mx.y, k & 4 == 0 ? mn.z : mx.z)) }
        }
        // Occluders.
        let oc = min(SceneRenderer.occluderChunks, R)
        for dz in -oc...oc { for dx in -oc...oc {
            guard let c = chunkGrid[(dx + R) + (dz + R) * span] else { continue }
            var sy = 0
            while sy <= c.topSec {
                guard c.sections[sy].solidFull else { sy += 1; continue }
                var top = sy
                while top + 1 <= c.topSec && c.sections[top + 1].solidFull { top += 1 }
                let mn = V3(Float(c.cx * CS) + 2, Float(sy * 16) + 2, Float(c.cz * CS) + 2)
                let mx = V3(Float(c.cx * CS) + 14, Float(top * 16) + 14, Float(c.cz * CS) + 14)
                sy = top + 1
                var dMax: Float = 0, behind = false
                corners(mn, mx) { k, p in
                    let q = project(p)
                    if q.z < 0 { behind = true } else { pts[k] = SIMD2(q.x, q.y); dMax = max(dMax, q.z) }
                }
                if behind { continue }
                // Convex hull of the 8 points (monotone chain), counter-clockwise in pixel space. (Sorted in place.)
                for i in 1..<8 {
                    let v = pts[i]; var j = i - 1
                    while j >= 0 && (pts[j].x > v.x || (pts[j].x == v.x && pts[j].y > v.y)) { pts[j + 1] = pts[j]; j -= 1 }
                    pts[j + 1] = v
                }
                let sorted = pts
                hull.removeAll(keepingCapacity: true)
                func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
                for p in sorted { while hull.count >= 2 && cross(hull[hull.count - 2], hull[hull.count - 1], p) <= 0 { hull.removeLast() }; hull.append(p) }
                let lower = hull.count + 1
                for p in sorted.reversed() { while hull.count >= lower && cross(hull[hull.count - 2], hull[hull.count - 1], p) <= 0 { hull.removeLast() }; hull.append(p) }
                hull.removeLast()
                guard hull.count >= 3 else { continue }
                occluderBoxes += 1
                // Each pixel row: the span inside the hull along both of its edges (y and y + 1), whole pixels only.
                var y0 = Float.infinity, y1 = -Float.infinity
                for p in hull { y0 = min(y0, p.y); y1 = max(y1, p.y) }
                let r0 = max(0, Int(ceil(y0))), r1 = min(H - 1, Int(floor(y1)) - 1)
                if r0 > r1 { continue }
                func spanAt(_ y: Float) -> (Float, Float) {
                    var lo = Float.infinity, hi = -Float.infinity
                    for e in 0..<hull.count {
                        let a = hull[e], b = hull[(e + 1) % hull.count]
                        if (a.y <= y && b.y >= y) || (b.y <= y && a.y >= y) {
                            if a.y == b.y { lo = min(lo, min(a.x, b.x)); hi = max(hi, max(a.x, b.x)) }
                            else { let x = a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x); lo = min(lo, x); hi = max(hi, x) }
                        }
                    }
                    return (lo, hi)
                }
                for r in r0...r1 {
                    let (l0, h0) = spanAt(Float(r)), (l1, h1) = spanAt(Float(r + 1))
                    let xa = max(0, Int(ceil(max(l0, l1)))), xb = min(W - 1, Int(floor(min(h0, h1))) - 1)
                    if xa > xb { continue }
                    let row = r * W
                    for x in xa...xb where oDepth[row + x] > dMax { oDepth[row + x] = dMax }
                }
            }
        } }
        guard occluderBoxes > 0 else { return }
        let T = SceneRenderer.oT, TW = W / T, TH = H / T
        for ty in 0..<TH { for tx in 0..<TW {
            var lo = Float.infinity, hi = -Float.infinity
            for y in (ty * T)..<(ty * T + T) { let row = y * W; for x in (tx * T)..<(tx * T + T) { let d = oDepth[row + x]; lo = min(lo, d); hi = max(hi, d) } }
            oTileMin[ty * TW + tx] = lo; oTileMax[ty * TW + tx] = hi
        } }
        let nearKeep: Float = 32 * 32                       // (sections within two chunks are never tested)
        // The sections.
        var out = 0
        for k in 0..<found.count {
            let key = found[k]
            let col = Int((key >> 8) & 0xFF_FFFF), sy = Int(key & 0xFF)
            guard let c = chunkGrid[col], Float(bitPattern: UInt32(key >> 32)) > nearKeep else { found[out] = key; out += 1; continue }
            let mn = V3(Float(c.cx * CS) - 2, Float(sy * 16) - 2, Float(c.cz * CS) - 2), mx = mn + V3(20, 20, 20)
            var dMin = Float.infinity, behind = false
            var xMin = Float.infinity, xMax = -Float.infinity, yMin = Float.infinity, yMax = -Float.infinity
            corners(mn, mx) { _, p in
                let q = project(p)
                if q.z < 0 { behind = true; return }
                dMin = min(dMin, q.z); xMin = min(xMin, q.x); xMax = max(xMax, q.x); yMin = min(yMin, q.y); yMax = max(yMax, q.y)
            }
            var hidden = !behind
            if hidden {
                let xa = max(0, Int(floor(xMin))), xb = min(W - 1, Int(ceil(xMax)) - 1)
                let ya = max(0, Int(floor(yMin))), yb = min(H - 1, Int(ceil(yMax)) - 1)
                if xa > xb || ya > yb { hidden = false }
                else {
                    // Tile by tile: a tile wholly in the rectangle decides at once when all its pixels are nearer (hidden
                    // there) or none is (visible); the rest pixel by pixel.
                    check: for ty in (ya / T)...(yb / T) { for tx in (xa / T)...(xb / T) {
                        let ti = ty * TW + tx
                        if oTileMax[ti] < dMin { continue }
                        let px0 = max(xa, tx * T), px1 = min(xb, tx * T + T - 1), py0 = max(ya, ty * T), py1 = min(yb, ty * T + T - 1)
                        if oTileMin[ti] >= dMin && px0 == tx * T && px1 == tx * T + T - 1 && py0 == ty * T && py1 == ty * T + T - 1 { hidden = false; break check }
                        for r in py0...py1 { let row = r * W; for x in px0...px1 where !(oDepth[row + x] < dMin) { hidden = false; break check } }
                    } }
                }
            }
            if hidden { occlusionSkipped += 1; continue }
            found[out] = key; out += 1
        }
        found.removeLast(found.count - out)
    }

    func cull(_ world: World, eye: V3, frustum: Frustum) {
        tableFrame = false
        for i in cullStageMs.indices { cullStageMs[i] = 0 }
        if SceneRenderer.fastCull && caveCulling && cullT(world, eye: eye, frustum: frustum) { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        visible.removeAll(keepingCapacity: true)
        deepSeaSkipped = 0
        let pcx = floorDiv(Int(floor(eye.x)), CS), pcz = floorDiv(Int(floor(eye.z)), CS)
        let pSec = Int(floor(eye.y / 16))
        if caveCulling, let startC = world.chunks[ChunkKey(x: pcx, z: pcz)], pSec >= 0 && pSec < NSEC, startC.meshedOnce {
            let R = world.renderDistance + 1, span = 2 * R + 1
            let need = span * span * NSEC
            if visitGen.count < need { visitGen = [UInt32](repeating: 0, count: need); foundGen = [UInt32](repeating: 0, count: need) }
            gen &+= 1
            if gen == 0 { gen = 1; for i in visitGen.indices { visitGen[i] = 0; foundGen[i] = 0 } }
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
            found.removeAll(keepingCapacity: true)
            bfs.append(CullNode(col: Int32(R + R * span), dx: 0, dz: 0, sy: Int16(pSec), entry: -1, mask: 0))
            visitGen[vidx(0, 0, pSec)] = gen
            var head = 0
            let r2 = world.renderDistance * world.renderDistance + world.renderDistance      // (World.inMeshRadius)
            let bx = Float(pcx * CS), bz = Float(pcz * CS), topCut = maxSection
            let smoothWalls = world.fieldTerrain || SmoothTerrain.enabled
            let allVis: UInt64 = (1 << 36) - 1
            let half = V3(8, 8, 8), side = V3(16, 16, 16)
            while head < bfs.count {
                let n = bfs[head]; head += 1
                guard let c = chunkGrid[Int(n.col)] else { continue }
                let sy = Int(n.sy), dx = Int(n.dx), dz = Int(n.dz), entry = Int(n.entry), mask = Int(n.mask)
                let sec = c.sections[sy]
                if sy < topCut && !sec.empty && foundGen[vidx(dx, dz, sy)] != gen {
                    foundGen[vidx(dx, dz, sy)] = gen
                    let mn = V3(bx + Float(dx * CS), Float(sy * 16), bz + Float(dz * CS))
                    let d = simd_length_squared(mn + half - eye)
                    found.append(UInt64(d.bitPattern) << 32 | UInt64(n.col) << 8 | UInt64(sy))
                }
                let vis = sec.meshedVersion == -1 ? ~UInt64(0) : sec.vis
                // P335: a section with ground in it and open cells beside it lists all 26 sections round it to draw: the
                // smooth ground of a section the walk never reaches (behind a corner, past an edge) reaches up to a block
                // into the open cells here, and showed the void through the floor or wall where it should have been.
                if smoothWalls && !sec.empty && vis != 0 && vis != allVis {
                    for oy in -1...1 { for oz in -1...1 { for ox in -1...1 where ox != 0 || oy != 0 || oz != 0 {
                        let ndx = dx + ox, ndz = dz + oz, nsy = sy + oy
                        if nsy < 0 || nsy >= NSEC || nsy >= topCut || abs(ndx) > R || abs(ndz) > R || ndx * ndx + ndz * ndz > r2 { continue }
                        let vi = vidx(ndx, ndz, nsy)
                        if foundGen[vi] == gen || visitGen[vi] == gen { continue }
                        let ncol = (ndx + R) + (ndz + R) * span
                        guard let pc = chunkGrid[ncol], pc.meshedOnce, !pc.sections[nsy].empty else { continue }
                        let nmn = V3(bx + Float(ndx * CS), Float(nsy * 16), bz + Float(ndz * CS))
                        if !frustum.visible(min: nmn, max: nmn + side) || pastFog(nmn, eye) { continue }
                        foundGen[vi] = gen
                        found.append(UInt64(simd_length_squared(nmn + half - eye).bitPattern) << 32 | UInt64(ncol) << 8 | UInt64(nsy))
                    } } }
                }
                for f in 0..<6 {
                    if mask & (1 << (f ^ 1)) != 0 { continue }
                    // P335 ("a piece of cave wall is not drawn, I can see through it into the void"): a smooth (field)
                    // surface is not on the block grid: a section's ground can rise into the open cells of the section
                    // beside it, and be seen from there, while the walk could not pass that way (no open path from where
                    // it came in to that face). A face the section's open cells touch at all now lists the section past
                    // it to draw (a peek), without walking on through it.
                    let through = entry < 0 || vis & (1 << UInt64(entry * 6 + f)) != 0
                    let peek = !through && smoothWalls && vis & (1 << UInt64(f * 6 + f)) != 0
                    if !through && !peek { continue }
                    var ndx = dx, ndz = dz, nsy = sy
                    switch f {
                    case 0: ndx += 1
                    case 1: ndx -= 1
                    case 2: nsy += 1
                    case 3: nsy -= 1
                    case 4: ndz += 1
                    default: ndz -= 1
                    }
                    if nsy < 0 || nsy >= NSEC || nsy > yLimit || abs(ndx) > R || abs(ndz) > R || ndx * ndx + ndz * ndz > r2 { continue }
                    let vi = vidx(ndx, ndz, nsy)
                    if visitGen[vi] == gen { continue }
                    let nmn = V3(bx + Float(ndx * CS), Float(nsy * 16), bz + Float(ndz * CS))
                    if !frustum.visible(min: nmn, max: nmn + side) || pastFog(nmn, eye) { continue }
                    let ncol = (ndx + R) + (ndz + R) * span
                    if f != 2 && f != 3 {
                        guard let nc = chunkGrid[ncol], nc.meshedOnce else { continue }
                        if underDeepWater(nc, nsy) { continue }
                    } else if underDeepWater(c, nsy) { continue }
                    if peek {
                        if let pc = chunkGrid[ncol], nsy < topCut, !pc.sections[nsy].empty, foundGen[vi] != gen {
                            foundGen[vi] = gen
                            found.append(UInt64(simd_length_squared(nmn + half - eye).bitPattern) << 32 | UInt64(ncol) << 8 | UInt64(nsy))
                        }
                        continue
                    }
                    visitGen[vi] = gen
                    bfs.append(CullNode(col: Int32(ncol), dx: Int16(ndx), dz: Int16(ndz), sy: Int16(nsy), entry: Int8(f ^ 1),
                                        mask: UInt8(mask | (1 << f))))
                }
            }
            cullVisits = bfs.count
            found.sort()
            // (P385 step 1: the same split as cullT's, the walk with its chunk lookups under "walk")
            let tw = CFAbsoluteTimeGetCurrent()
            cullStageMs[1] = (tw - t0) * 1000
            if horizonCulling { horizonCull(eye: eye, R: R, span: span) }
            let th = CFAbsoluteTimeGetCurrent()
            cullStageMs[2] = (th - tw) * 1000
            if occlusionCulling { occlusionCull(eye: eye, R: R, span: span) }
            cullStageMs[3] = (CFAbsoluteTimeGetCurrent() - th) * 1000
            for k in found {
                guard let c = chunkGrid[Int((k >> 8) & 0xFF_FFFF)] else { continue }
                visible.append((c, Int(k & 0xFF), Float(bitPattern: UInt32(k >> 32))))
            }
        } else {
            for (_, c) in world.chunks where c.meshedOnce {
                let dx = c.cx - pcx, dz = c.cz - pcz
                if !world.inMeshRadius(dx, dz) { continue }
                let cmn = V3(Float(c.cx * CS), 0, Float(c.cz * CS))
                if !frustum.visible(min: cmn, max: cmn + V3(16, Float(CH), 16)) { continue }
                for (sy, sec) in c.sections.enumerated() where !sec.empty && sy < maxSection {
                    let mn = V3(cmn.x, Float(sy * 16), cmn.z)
                    if !frustum.visible(min: mn, max: mn + V3(16, 16, 16)) || pastFog(mn, eye) || underDeepWater(c, sy) { continue }
                    visible.append((c, sy, simd_length_squared(mn + V3(8, 8, 8) - eye)))
                }
            }
            visible.sort { $0.2 < $1.2 }
        }
        visibleCount = visible.count
        cullMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }

    // P283 (questcheck --perfscenes): the culled sections' quads by kind, near (lod 0 and 2) and far (lod 1).
    func quadBreakdown() -> String {
        let visible = visibleList()
        var q = [[Int]](repeating: [0, 0, 0, 0, 0, 0], count: 2)
        for i in 0..<min(visible.count, SceneRenderer.recordCap) {
            let (c, sy, _) = visible[i]
            let s = c.sections[sy], f = c.lod == 1 ? 1 : 0
            q[f][0] += 1; q[f][1] += s.groundQuads; q[f][2] += s.blobQuads; q[f][3] += s.opaqueQuads - s.groundQuads - s.blobQuads
            q[f][4] += s.detailQuads; q[f][5] += s.transQuads
        }
        return "walk \(cullVisits) sections, \(sealedSkipped) sealed far caves (P392), \(horizonSkipped) behind hills, \(occlusionSkipped) occluded by \(occluderBoxes) solid boxes (\(String(format: "%.2f", occlusionMs)) ms), \(mergedSections) drawing merged ground; " + ["near", "far"].enumerated().map { i, n in
            "\(n) \(q[i][0]) sections: ground \(q[i][1]), leaf blobs \(q[i][2]), other opaque \(q[i][3]), detail \(q[i][4]), translucent \(q[i][5])"
        }.joined(separator: "; ")
    }

    // P384 step 1: the culled sections' quads by kind (MeshKind), within and past GroundMerge.farDistance (~180 blocks),
    // as meshed (full copies; the far switch's ground is in "ground far copy").
    func kindBreakdown() -> String {
        let visible = visibleList()
        var q = [SIMD16<Int32>](repeating: SIMD16<Int32>(), count: 2)
        var trans = [0, 0], secs = [0, 0], farExtra = [0, 0], farSkip = [0, 0], farCut = [0, 0], farTail = [0, 0], detExtra = [0, 0], detSkip = [0, 0]
        var buried = [SIMD16<Int32>(), SIMD16<Int32>()], buriedSecs = [0, 0]
        for i in 0..<min(visible.count, SceneRenderer.recordCap) {
            let (c, sy, _) = visible[i]
            let s = c.sections[sy], f = mergedFar(c, sy) ? 1 : 0
            q[f] &+= s.kinds; trans[f] += s.transQuads; secs[f] += 1
            if s.farExtra > 0 || s.farCut > 0 || s.farTail > 0 { farExtra[f] += s.farExtra; farSkip[f] += s.farSkip; farCut[f] += s.farCut; farTail[f] += s.farTail }
            if s.detailFarExtra > 0 { detExtra[f] += s.detailFarExtra; detSkip[f] += s.detailFarSkip }
            // (sections wholly under the chunk's lowest surface column: caves, drawn unless something culls them)
            let low = Int(c.height.min() ?? 0)
            if (sy + 1) * 16 <= low { buried[f] &+= s.kinds; buriedSecs[f] += 1 }
        }
        return ["within", "past"].enumerated().map { f, n in
            let parts = (0..<16).compactMap { k -> String? in MeshKind.names[k].isEmpty ? nil : "\(MeshKind.names[k]) \(q[f][k])" }
            let bur = (0..<16).compactMap { k -> String? in MeshKind.names[k].isEmpty || buried[f][k] == 0 ? nil : "\(MeshKind.names[k]) \(buried[f][k])" }
            return "\(n) \(Int(GroundMerge.farDistance)) blocks (\(secs[f]) sections): " + parts.joined(separator: ", ")
                + ", translucent \(trans[f]); far copies \(farExtra[f]) for \(farSkip[f]) solid + \(farCut[f]) cutout (+\(farTail[f]) far-only cutout), detail \(detExtra[f]) for \(detSkip[f])"
                + "; under the lowest surface: \(buriedSecs[f]) sections, " + bur.joined(separator: ", ")
        }.joined(separator: "\n    kinds ")
    }

    // F5 (Oct 13 evening: over open ocean the view must be the cheapest case): a far (LOD 1) section with a whole
    // section of water over it is under 16+ blocks of deep water, which water.frag draws with no transmittance past the
    // near ring, so its seabed (the bumpy, unmergeable part of far ocean) is neither drawn nor walked through, and the
    // walk stops at the first all-water section instead of descending through every one to the bed. A meshed section
    // with no faces and water in it is all water (any other block next to water has a face). BS_DEEPSEA=0 turns it off.
    static var deepSeaCull = ProcessInfo.processInfo.environment["BS_DEEPSEA"] != "0"
    private(set) var deepSeaSkipped = 0
    // P392 (view 24: cull the buried far caves): a section is sky-open when open air comes down to it from the sky
    // through the sections above it (each one's top face open and, for the ones it passes through, its top face joined
    // to its bottom face: Mesher.connectivity's bits), so a column's sky-open sections run from the top down to
    // ColInfo.openLow. A far section (its column's nearest point at least GroundMerge.farDistance from the eye, where
    // P384's far copies start) is sealed when neither it nor any of the 26 round it is sky-open: a cave under the
    // surface with no mouth beside it. A cave mouth seen from the surface keeps its own section and the ones round it
    // (an open face keeps its section and its neighbour). While the eye is above ground (`sealCull`, set by
    // WorldRenderer: a sky world, not underground, the eye's own section sky-open or beside one) sealed far sections are
    // not drawn; underground, or within the near ring, everything is as before. The walk still goes through them (it
    // only leaves them off its list): which sections it reaches, and by which faces, is exactly as before, so nothing
    // past a sealed section drops out with it (skipping the walk there left a patch of a far riverbed out).
    // BS_SEALCULL=0: off.
    static var sealedCulling = ProcessInfo.processInfo.environment["BS_SEALCULL"] != "0"
    var sealCull = false
    private(set) var sealedSkipped = 0
    private lazy var fluidKindT: [UInt8] = Blocks.fluidKind     // (the block registry is complete by the first cull)
    @inline(__always) private func underDeepWater(_ c: Chunk, _ sy: Int) -> Bool {
        guard SceneRenderer.deepSeaCull, c.lod == 1, sy + 1 < NSEC else { return false }
        let above = c.sections[sy + 1]
        guard above.empty, above.meshedVersion != -1 else { return false }
        let y = (sy + 1) * 16
        let fk = fluidKindT
        guard fk[Int(c.blocks[Chunk.index(8, y + 8, 8)])] == 1, fk[Int(c.blocks[Chunk.index(0, y, 0)])] == 1,
              fk[Int(c.blocks[Chunk.index(15, y + 15, 15)])] == 1 else { return false }
        deepSeaSkipped &+= 1
        return true
    }

    // Writes the section records for the culled list (camera-relative origins) into the slot.
    private var nRec = 0
    private var recEye = V3(0, 0, 0)
    // P375 (GroundMerge): whether a section is far enough that its merged ground differs from the full grid by under
    // a pixel: its box's nearest point at least GroundMerge.farDistance from the eye.
    @inline(__always) private func mergedFar(_ c: Chunk, _ sy: Int) -> Bool {
        let mn = V3(Float(c.cx * CS), Float(sy * 16), Float(c.cz * CS))
        let q = simd_clamp(recEye, mn, mn + V3(16, 16, 16))
        let f = GroundMerge.farDistance
        guard SceneRenderer.drawMerged else { return false }
        return simd_length_squared(q - recEye) >= f * f
    }
    private(set) var mergedSections = 0
    static var drawMerged = true                  // (questcheck --view --pixelpair: the full grid everywhere for the left shot)
    func writeRecords(_ s: Slot, eye: V3) {
        recEye = eye
        if tableFrame { writeRecordsT(s, eye: eye); return }
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
    private func drawSection(_ s: Slot, _ i: Int, _ slice: MeshSlice, _ tb: MeshSlice, first: Int, count: Int, stride: Int = 8) {
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
        vkCmdDrawIndexed(s.cmd, UInt32(count * 6), 1, UInt32(first * 6), Int32(slice.offset / stride), UInt32(i))
    }

    private func bindTerrainBuffers(_ s: Slot) {
        vkCmdBindIndexBuffer(s.cmd, quadIndex.buffer, 0, VK_INDEX_TYPE_UINT32)
        var b: VkBuffer? = s.records.buffer
        var o: VkDeviceSize = 0
        vkCmdBindVertexBuffers(s.cmd, 1, 1, &b, &o)
        boundVerts = nil; boundTints = nil
    }

    // P146 (raise the render distance past 16 on the Quest): at distance 23 the Oct 9 logs recorded 1669 sections, and
    // command recording (one vkCmdDrawIndexed per section per pass) took 11.9 ms of the frame. With multiDrawIndirect
    // the opaque passes write every section's draw into a buffer and issue one indirect draw per vertex slab and tint
    // slab pair (a few dozen in all), near to far within each. Water stays one draw per section (its far-to-near
    // blending order matters). `batchDraws` off (or a device without the features) keeps the per-section draws.
    static var batchDraws = true
    private lazy var batchable: Bool = ctx.features.multiDrawIndirect != 0 && ctx.features.drawIndirectFirstInstance != 0
    private(set) var batchedSections = 0
    private var batchKeys: [(QuestBuffer, QuestBuffer)] = []
    private var batchCount: [Int] = []
    private var batchStart: [Int] = []
    private var pendingDraws: [(Int, VkDrawIndexedIndirectCommand)] = []

    // P283: one walk of the visible list for the terrain's two passes (solid, cutout) and one for the round shapes'
    // two, not one a pass: each step cast two buffers and retained the section, the chunk and both buffers, 4 times
    // over 500+ sections (an eighth of the frame thread's samples on the homestead replay).
    private var pendingCut: [(Int, VkDrawIndexedIndirectCommand)] = []
    private var batchCut: [Int] = []
    private func drawOpaqueBatched(_ s: Slot) {
        let stride = MemoryLayout<VkDrawIndexedIndirectCommand>.stride
        let cap = s.indirect.size / stride
        let maxPer = max(1, Int(ctx.props.limits.maxDrawIndirectCount))
        let cmds = s.indirect.mapped!.bindMemory(to: VkDrawIndexedIndirectCommand.self, capacity: cap)
        var used = 0
        defer { indirectUsed = used }             // the far water batch (drawTranslucent) writes after these
        for half in 0..<2 {
            // Terrain solid and cutout, then the realistic world's round shapes (16-byte vertices) solid and cutout.
            let detail = half == 1
            if detail && !anyDetail { break }
            batchKeys.removeAll(keepingCapacity: true); batchCount.removeAll(keepingCapacity: true); batchCut.removeAll(keepingCapacity: true)
            pendingDraws.removeAll(keepingCapacity: true); pendingCut.removeAll(keepingCapacity: true)
            for i in 0..<nRec {
                let (c, sy, _) = visible[i]
                let sec = c.sections[sy]
                let quads = detail ? sec.detailQuads : sec.opaqueQuads
                guard quads > 0, let buf = detail ? sec.detailBuf : sec.opaqueBuf, let tb = c.tintBuf,
                      let vb = buf.buffer as? QuestBuffer, let tbuf = tb.buffer as? QuestBuffer else { continue }
                // (P384: the last farTail cutout quads are the far copies of things laid on the ground: far only)
                let tail = detail ? 0 : sec.farTail
                var total = min(quads - tail, SceneRenderer.maxQuads)
                let solid = min(detail ? sec.detailSolid : sec.solidQuads, total)
                var k = 0
                while k < batchKeys.count && !(batchKeys[k].0 === vb && batchKeys[k].1 === tbuf) { k += 1 }
                if k == batchKeys.count { batchKeys.append((vb, tbuf)); batchCount.append(0); batchCut.append(0) }
                let vo = Int32(buf.offset / (detail ? 16 : 8))
                // P375, P384: far, the far copies in place of what they stand for (the leading farSkip solid quads, and
                // the leading farCut cutout ones), for the opaque and the detail stream alike.
                let fSkip = detail ? sec.detailFarSkip : sec.farSkip, fExtra = detail ? sec.detailFarExtra : sec.farExtra
                var cutFrom = solid
                let cutSwitch = !detail && (sec.farCut > 0 || tail > 0)
                if (fExtra > 0 || cutSwitch) && solid >= fSkip && quads + fExtra <= SceneRenderer.maxQuads && mergedFar(c, sy) {
                    mergedSections += 1
                    if solid > fSkip {
                        batchCount[k] += 1
                        pendingDraws.append((k, VkDrawIndexedIndirectCommand(indexCount: UInt32((solid - fSkip) * 6), instanceCount: 1,
                                                                             firstIndex: UInt32(fSkip * 6), vertexOffset: vo, firstInstance: UInt32(i))))
                    }
                    if fExtra > 0 {
                        batchCount[k] += 1
                        pendingDraws.append((k, VkDrawIndexedIndirectCommand(indexCount: UInt32(fExtra * 6), instanceCount: 1, firstIndex: 0,
                                                                             vertexOffset: vo + Int32(quads * 4), firstInstance: UInt32(i))))
                    }
                    if !detail { cutFrom = min(total, solid + sec.farCut); total = min(quads, SceneRenderer.maxQuads) }
                    drawnQuads += fExtra - fSkip - (cutFrom - solid)
                } else if solid > 0 {
                    batchCount[k] += 1
                    pendingDraws.append((k, VkDrawIndexedIndirectCommand(indexCount: UInt32(solid * 6), instanceCount: 1, firstIndex: 0,
                                                                         vertexOffset: vo, firstInstance: UInt32(i))))
                }
                if total > cutFrom {
                    batchCut[k] += 1
                    pendingCut.append((k, VkDrawIndexedIndirectCommand(indexCount: UInt32((total - cutFrom) * 6), instanceCount: 1,
                                                                       firstIndex: UInt32(cutFrom * 6), vertexOffset: vo, firstInstance: UInt32(i))))
                }
                drawnQuads += total
            }
            for pass in 0..<2 {
                let pending = pass == 0 ? pendingDraws : pendingCut, counts = pass == 0 ? batchCount : batchCut
                if pending.isEmpty { continue }
                guard used + pending.count <= cap else { break }
                vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe(["solid", "cut", "detail", "detailCut"][half * 2 + pass]))

                // Each group's commands side by side (stable: near to far within a group).
                batchStart.removeAll(keepingCapacity: true)
                var at = used
                for n in counts { batchStart.append(at); at += n }
                for (k, cmd) in pending { cmds[batchStart[k]] = cmd; batchStart[k] += 1 }
                var start = used
                for k in 0..<batchKeys.count where counts[k] > 0 {
                    let (vb, tbuf) = batchKeys[k]
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
                    var left = counts[k], off = start
                    while left > 0 {
                        let n = min(left, maxPer)
                        vkCmdDrawIndexedIndirect(s.cmd, s.indirect.buffer, VkDeviceSize(off * stride), UInt32(n), UInt32(stride))
                        drawCalls += 1
                        left -= n; off += n
                    }
                    start += counts[k]
                }
                batchedSections += pending.count
                used = at
            }
        }
    }

    // Opaque terrain: solid faces first (no alpha test), then cutout faces, near to far.
    func drawOpaque(_ s: Slot) {
        drawCalls = 0; drawnQuads = 0; batchedSections = 0; indirectUsed = 0; mergedSections = 0
        bindTerrainBuffers(s)
        anyDetail = false
        if tableFrame {
            if SceneRenderer.batchDraws && batchable && s.indirect != nil { drawOpaqueBatchedT(s); return }
            visible = visibleList()               // (no indirect draws: the list as tuples, drawn as before)
            tableFrame = false
        }
        for i in 0..<nRec { let (c, sy, _) = visible[i]; if c.sections[sy].detailQuads > 0 { anyDetail = true; break } }
        if SceneRenderer.batchDraws && batchable && s.indirect != nil { drawOpaqueBatched(s); return }
        for pass in 0..<4 {
            let detail = pass >= 2
            if detail && !anyDetail { break }
            vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe(["solid", "cut", "detail", "detailCut"][pass]))
            for i in 0..<nRec {
                let (c, sy, _) = visible[i]
                let sec = c.sections[sy]
                let quads = detail ? sec.detailQuads : sec.opaqueQuads
                guard quads > 0, let buf = detail ? sec.detailBuf : sec.opaqueBuf, let tb = c.tintBuf else { continue }
                let tail = detail ? 0 : sec.farTail
                let total = min(quads - tail, SceneRenderer.maxQuads), solid = min(detail ? sec.detailSolid : sec.solidQuads, total)
                var first = pass & 1 == 0 ? 0 : solid, count = pass & 1 == 0 ? solid : total - solid
                let fSkip = detail ? sec.detailFarSkip : sec.farSkip, fExtra = detail ? sec.detailFarExtra : sec.farExtra
                let cutSwitch = !detail && (sec.farCut > 0 || tail > 0)
                if (fExtra > 0 || cutSwitch) && solid >= fSkip && quads + fExtra <= SceneRenderer.maxQuads && mergedFar(c, sy) {
                    if pass & 1 == 0 {
                        mergedSections += 1                // P375, P384: the far copies in place of what they stand for
                        if fExtra > 0 { drawSection(s, i, buf, tb, first: quads, count: fExtra, stride: detail ? 16 : 8) }
                        first = fSkip; count = solid - fSkip
                    } else if !detail {
                        first = min(total, solid + sec.farCut); count = min(quads, SceneRenderer.maxQuads) - first
                    }
                }
                if count <= 0 { continue }
                drawSection(s, i, buf, tb, first: first, count: count, stride: detail ? 16 : 8)
            }
        }
    }
    private var anyDetail = false

    // Water and other translucent faces, far to near.
    // F5 (Oct 13 evening: "the render distance struggles on the water"): over open sea every section at the surface
    // has water faces, and they were one vkCmdDrawIndexed each, the only terrain pass left unbatched (P146): ~1000 draw
    // records a frame at distance 20, the CPU cost that made the ocean the dearest view instead of the cheapest. Far
    // (LOD 1) sections' translucent faces now go out as indirect batches first (grouped by vertex and tint slab, far to
    // near within each group; far water is merged flat sea surface, which never overlaps itself, so the order between
    // groups does not show), then the near ones one by one, far to near, as before. `batchFarWater` off: all per section.
    static var batchFarWater = ProcessInfo.processInfo.environment["BS_WATERBATCH"] != "0"
    private var indirectUsed = 0
    private(set) var batchedWater = 0
    func drawTranslucent(_ s: Slot, underwater: Bool = false) {
        if tableFrame { drawTranslucentT(s, underwater: underwater); return }
        bindTerrainBuffers(s)
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe(underwater ? "waterUnder" : "water"))
        let farBatched = !underwater && SceneRenderer.batchFarWater && SceneRenderer.batchDraws && batchable && s.indirect != nil
            && drawFarTranslucentBatched(s)
        for i in stride(from: nRec - 1, through: 0, by: -1) {
            let (c, sy, _) = visible[i]
            if farBatched && c.lod == 1 { continue }
            let sec = c.sections[sy]
            guard sec.transQuads > 0, let buf = sec.transBuf, let tb = c.tintBuf else { continue }
            drawSection(s, i, buf, tb, first: 0, count: min(sec.transQuads, SceneRenderer.maxQuads))
        }
    }

    // The far sections' translucent faces as indirect draws; false (nothing drawn) when they don't fit the buffer.
    private func drawFarTranslucentBatched(_ s: Slot) -> Bool {
        batchedWater = 0
        let cmdStride = MemoryLayout<VkDrawIndexedIndirectCommand>.stride
        let cap = s.indirect.size / cmdStride
        let maxPer = max(1, Int(ctx.props.limits.maxDrawIndirectCount))
        let cmds = s.indirect.mapped!.bindMemory(to: VkDrawIndexedIndirectCommand.self, capacity: cap)
        batchKeys.removeAll(keepingCapacity: true); batchCount.removeAll(keepingCapacity: true)
        pendingDraws.removeAll(keepingCapacity: true)
        var quads = 0
        for i in stride(from: nRec - 1, through: 0, by: -1) {
            let (c, sy, _) = visible[i]
            guard c.lod == 1 else { continue }
            let sec = c.sections[sy]
            guard sec.transQuads > 0, let buf = sec.transBuf, let tb = c.tintBuf,
                  let vb = buf.buffer as? QuestBuffer, let tbuf = tb.buffer as? QuestBuffer else { continue }
            let count = min(sec.transQuads, SceneRenderer.maxQuads)
            var k = 0
            while k < batchKeys.count && !(batchKeys[k].0 === vb && batchKeys[k].1 === tbuf) { k += 1 }
            if k == batchKeys.count { batchKeys.append((vb, tbuf)); batchCount.append(0) }
            batchCount[k] += 1
            pendingDraws.append((k, VkDrawIndexedIndirectCommand(indexCount: UInt32(count * 6), instanceCount: 1, firstIndex: 0,
                                                                 vertexOffset: Int32(buf.offset / 8), firstInstance: UInt32(i))))
            quads += count
        }
        if pendingDraws.isEmpty { return true }
        let used = indirectUsed
        guard used + pendingDraws.count <= cap else { return false }
        batchStart.removeAll(keepingCapacity: true)
        var at = used
        for n in batchCount { batchStart.append(at); at += n }
        for (k, cmd) in pendingDraws { cmds[batchStart[k]] = cmd; batchStart[k] += 1 }
        var start = used
        for k in 0..<batchKeys.count {
            let (vb, tbuf) = batchKeys[k]
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
            var left = batchCount[k], off = start
            while left > 0 {
                let n = min(left, maxPer)
                vkCmdDrawIndexedIndirect(s.cmd, s.indirect.buffer, VkDeviceSize(off * cmdStride), UInt32(n), UInt32(cmdStride))
                drawCalls += 1
                left -= n; off += n
            }
            start += batchCount[k]
        }
        indirectUsed = at
        drawnQuads += quads
        batchedWater = pendingDraws.count
        return true
    }

    // F4 middle ring (Sources/FarRing.swift, WorldRenderer.drawFarRing): `quads` quads from a host-visible buffer of
    // SimpleVert (4 per quad, the shared quad index), with the ring's push constants (quest/shaders/far.vert).
    func drawFar(_ s: Slot, _ buf: VkBuf, quads: Int, params: float4x4) {
        guard quads > 0 else { return }
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe("far"))
        pushConstants(s, model: params, extra: V4(0, 0, 0, 0))
        var b: VkBuffer? = buf.buffer
        var o: VkDeviceSize = 0
        vkCmdBindVertexBuffers(s.cmd, 0, 1, &b, &o)
        vkCmdBindIndexBuffer(s.cmd, quadIndex.buffer, 0, VK_INDEX_TYPE_UINT32)
        vkCmdDrawIndexed(s.cmd, UInt32(min(quads, SceneRenderer.maxQuads) * 6), 1, 0, 0, 0)
        drawCalls += 1
        boundVerts = nil
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

// MARK: P385: the cull from the cull table

extension SceneRenderer {
    private func slabOf(_ m: MeshSlice?) -> Int32 {
        guard let m, let b = m.buffer as? QuestBuffer else { return -1 }
        let id = ObjectIdentifier(b)
        if let k = slabIdx[id] { return k }
        let k = Int32(slabBufs.count)
        slabBufs.append(b); slabIdx[id] = k
        return k
    }
    private func pairOf(_ vs: Int32, _ ts: Int32) -> Int32 {
        guard vs >= 0, ts >= 0 else { return -1 }
        let key = Int64(vs) << 32 | Int64(ts)
        if let k = pairIdx[key] { return k }
        let k = Int32(pairBufs.count)
        pairBufs.append((slabBufs[Int(vs)], slabBufs[Int(ts)])); pairIdx[key] = k; pairK.append(-1)
        return k
    }

    // A column's facts, read from its chunk.
    private func fillColumn(_ slot: Int, _ c: Chunk) {
        c.cullWatched = true
        var ci = ColInfo()
        ci.cx = Int32(c.cx); ci.cz = Int32(c.cz); ci.topSec = Int16(c.topSec)
        ci.present = true; ci.meshedOnce = c.meshedOnce; ci.lod1 = c.lod == 1
        ci.occTop = Int32(c.occluderTop)
        ci.tintOff = UInt32((c.tintBuf?.offset ?? 0) / 4)
        let secs = c.sections
        // P392: sky-open sections, from the top down (an unmeshed section counts as open all through).
        var low = NSEC
        for sy in stride(from: NSEC - 1, through: 0, by: -1) {
            let v = secs[sy].meshedVersion == -1 ? ~UInt64(0) : secs[sy].vis
            if v & (1 << 14) == 0 { break }            // (top face shut: no sky air comes in)
            low = sy
            if v & (1 << 15) == 0 { break }            // (top face not joined to the bottom: the sky stops here)
        }
        ci.openLow = Int16(low)
        tabCol[slot] = ci
        let ts = slabOf(c.tintBuf)
        let base = slot * NSEC
        for sy in 0..<NSEC {
            let s = secs[sy]
            var e = SecInfo()
            e.vis = s.meshedVersion == -1 ? ~UInt64(0) : s.vis
            if !s.empty { e.flags |= SecInfo.nonEmpty }
            if s.meshedVersion != -1 { e.flags |= SecInfo.meshed }
            if s.solidFull { e.flags |= SecInfo.solidFull }
            if deepWaterAbove(c, sy) { e.flags |= SecInfo.deep }
            if s.opaqueQuads > 0, let b = s.opaqueBuf {
                e.oPair = pairOf(slabOf(b), ts); e.oVo = Int32(b.offset / 8)
                e.quads = Int32(s.opaqueQuads); e.solid = Int32(s.solidQuads); e.fSkip = Int32(s.farSkip); e.fExtra = Int32(s.farExtra)
                e.farCut = Int32(s.farCut); e.farTail = Int32(s.farTail)
            }
            if s.detailQuads > 0, let b = s.detailBuf {
                e.dPair = pairOf(slabOf(b), ts); e.dVo = Int32(b.offset / 16)
                e.dQuads = Int32(s.detailQuads); e.dSolid = Int32(s.detailSolid); e.dSkip = Int32(s.detailFarSkip); e.dExtra = Int32(s.detailFarExtra)
            }
            if s.transQuads > 0, let b = s.transBuf {
                e.tPair = pairOf(slabOf(b), ts); e.tVo = Int32(b.offset / 8); e.tQuads = Int32(s.transQuads)
            }
            tabSec[base + sy] = e
            tabVis[base + sy] = e.vis; tabFl[base + sy] = UInt8(e.flags)
        }
    }

    // underDeepWater's test without its tally (the flag is kept in the table; the tally counts at use).
    private func deepWaterAbove(_ c: Chunk, _ sy: Int) -> Bool {
        guard c.lod == 1, sy + 1 < NSEC else { return false }
        let above = c.sections[sy + 1]
        guard above.empty, above.meshedVersion != -1 else { return false }
        let y = (sy + 1) * 16
        let fk = fluidKindT
        return fk[Int(c.blocks[Chunk.index(8, y + 8, 8)])] == 1 && fk[Int(c.blocks[Chunk.index(0, y, 0)])] == 1
            && fk[Int(c.blocks[Chunk.index(15, y + 15, 15)])] == 1
    }

    // Every column in reach checked against what its slot was filled from; changed ones re-read.
    private func refreshTable(_ world: World, pcx: Int, pcz: Int, R: Int, span: Int) {
        if tabSpan != span {
            tabSpan = span
            tabChunk = [Chunk?](repeating: nil, count: span * span)
            tabKey = [ColKey](repeating: ColKey(), count: span * span)
            tabCol = [ColInfo](repeating: ColInfo(), count: span * span)
            tabSec = [SecInfo](repeating: SecInfo(), count: span * span * NSEC)
            tabSeen = [UInt32](repeating: 0, count: span * span)
            tabVis = [UInt64](repeating: 0, count: span * span * NSEC)
            tabFl = [UInt8](repeating: 0, count: span * span * NSEC)
            fpGen = [UInt32](repeating: 0, count: span * span)
            fpV = [SIMD4<Float>](repeating: .zero, count: span * span)
            tabEpoch = -1; tabLive.removeAll()
        }
        if slotX.count != span { slotX = [Int](repeating: 0, count: span); slotZ = [Int](repeating: 0, count: span) }
        let wid = ObjectIdentifier(world)
        let lost = CullNotes.take(&noteBuf)                // (taken before any key is read: later changes note again)
        if SceneRenderer.epochTable && !lost && tabEpoch == world.chunksEpoch && tabPCX == pcx && tabPCZ == pcz && tabWorld == wid {
            var n = 0
            for key in noteBuf {
                let cx = Int(Int32(truncatingIfNeeded: key >> 32)), cz = Int(Int32(truncatingIfNeeded: key))
                let dx = cx - pcx, dz = cz - pcz
                guard abs(dx) <= R, abs(dz) <= R else { continue }
                let slot = slotX[dx + R] + slotZ[dz + R]
                guard let c = tabChunk[slot], c.cx == cx, c.cz == cz else { continue }
                let fl = (c.meshedOnce ? 1 : 0) | (c.hollow ? 2 : 0) | (c.tintBuf == nil ? 0 : 4)
                let k = ColKey(stamp: c.cullStamp, bv: c.blocksVersion, lod: c.lod, flags: fl)
                if tabKey[slot] == k { continue }
                tabKey[slot] = k
                fillColumn(slot, c)
                n += 1
            }
            tableRefreshed = n
            return
        }
        tabEpoch = world.chunksEpoch; tabPCX = pcx; tabPCZ = pcz; tabWorld = wid
        tabLive.removeAll(keepingCapacity: true)
        for i in 0..<span { slotX[i] = mod(pcx + i - R, span); slotZ[i] = mod(pcz + i - R, span) * span }
        var n = 0
        for dz in -R...R { for dx in -R...R {
            let slot = slotX[dx + R] + slotZ[dz + R]
            guard world.inMeshRadius(dx, dz), let c = world.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)] else {
                if tabCol[slot].present || tabChunk[slot] != nil { tabChunk[slot] = nil; tabKey[slot] = ColKey(); tabCol[slot].present = false }
                continue
            }
            tabLive.append(LiveCol(slot: slot, c: c))
            let fl = (c.meshedOnce ? 1 : 0) | (c.hollow ? 2 : 0) | (c.tintBuf == nil ? 0 : 4)
            let k = ColKey(stamp: c.cullStamp, bv: c.blocksVersion, lod: c.lod, flags: fl)
            if tabChunk[slot] === c && tabKey[slot] == k { continue }
            tabChunk[slot] = c; tabKey[slot] = k
            fillColumn(slot, c)
            n += 1
        } }
        tableRefreshed = n
    }

    // The list as (chunk, section, distance) tuples (diagnostics, and the per-section draws without indirect draws).
    func visibleList() -> [(Chunk, Int, Float)] {
        guard tableFrame else { return visible }
        var out: [(Chunk, Int, Float)] = []
        out.reserveCapacity(vl.count)
        for v in vl {
            let slot = Int(v) / NSEC, sy = Int(v) % NSEC
            if let c = tabChunk[slot] { out.append((c, sy, 0)) }
        }
        return out
    }

    // The walk, horizon and occlusion culls of `cull` over the table; false when the walk can't start (the eye outside
    // the loaded sections: the caller falls back to the full scan).
    func cullT(_ world: World, eye: V3, frustum: Frustum) -> Bool {
        let t0 = CFAbsoluteTimeGetCurrent()
        var tm = t0
        func stage(_ i: Int) { let t = CFAbsoluteTimeGetCurrent(); cullStageMs[i] += (t - tm) * 1000; tm = t }
        let pcx = floorDiv(Int(floor(eye.x)), CS), pcz = floorDiv(Int(floor(eye.z)), CS)
        let pSec = Int(floor(eye.y / 16))
        let R = world.renderDistance + 1, span = 2 * R + 1
        refreshTable(world, pcx: pcx, pcz: pcz, R: R, span: span)
        stage(0)
        let startSlot = slotX[R] + slotZ[R]
        guard pSec >= 0 && pSec < NSEC, tabCol[startSlot].present, tabCol[startSlot].meshedOnce else { return false }
        deepSeaSkipped = 0
        let rasterLate = occlusionCulling && occlusionVP != nil && !SceneRenderer.occParallel
        if occlusionCulling && occlusionVP != nil && SceneRenderer.occParallel {
            occWork.start { [self] in rasterOccluders(R: R) }
        }
        defer { occWork.finish() }                       // (never left running past the cull)
        let need = span * span * NSEC
        // (the walk's marks in plain memory, the table read through locals: as class properties every access in the loop
        // was an exclusivity check and a uniqueness check on the host build)
        if tMarks.count < need { tMarks = RawMarks(need) }
        gen &+= 1
        if gen == 0 {
            gen = 1
            for i in visitGen.indices { visitGen[i] = 0; foundGen[i] = 0 }
            tMarks.clear()
            for i in fpGen.indices { fpGen[i] = 0 }
        }
        let g = gen
        let vG = tMarks.visit, fG = tMarks.found, frG = tMarks.frustum, frO = tMarks.viewOK
        @inline(__always) func vidx(_ dx: Int, _ dz: Int, _ sy: Int) -> Int { ((dx + R) + (dz + R) * span) * NSEC + sy }
        let tc = tabCol, tv = tabVis, tf = tabFl, sX = slotX, sZ = slotZ, live = tabLive
        // P392: per column, the sections under which a far section is sealed (0: none are; see `sealedCulling`).
        // Worked out again only when a column was re-read, the eye changed chunk, or it moved half a block (the far
        // test then takes half a block more, so a stale eye never culls a section nearer than GroundMerge.farDistance).
        if sealLow.count != span * span {
            sealLow = [Int16](repeating: 0, count: span * span); sealRow = [Int16](repeating: 0, count: span * span)
            sealValid = false
        }
        var sealOn = false
        if sealCull && SceneRenderer.sealedCulling {
            // (the lowest sky-open section over a column and the eight round it, less one: the sections below it are
            // neither sky-open nor beside a sky-open one; a min over rows, then over columns, in offset order)
            let stale = !sealValid || tableRefreshed > 0 || sealPC != SIMD2(Int32(pcx), Int32(pcz))
                || simd_length_squared(eye - sealEye) > 0.25
            if stale {
                for dz in -R...R {
                    for dx in -R...R {
                        var m = Int16(NSEC)
                        for ox in max(-R, dx - 1)...min(R, dx + 1) {
                            let ns = sX[ox + R] + sZ[dz + R]
                            if tc[ns].present && tc[ns].openLow < m { m = tc[ns].openLow }
                        }
                        sealRow[(dx + R) + (dz + R) * span] = m
                    }
                }
                let fd2 = (GroundMerge.farDistance + 0.5) * (GroundMerge.farDistance + 0.5)
                for dz in -R...R {
                    for dx in -R...R {
                        var m = Int16(NSEC)
                        for oz in max(-R, dz - 1)...min(R, dz + 1) { m = min(m, sealRow[(dx + R) + (oz + R) * span]) }
                        let x0 = Float((pcx + dx) * CS), z0 = Float((pcz + dz) * CS)
                        let nx = max(x0, min(eye.x, x0 + 16)) - eye.x, nz = max(z0, min(eye.z, z0 + 16)) - eye.z
                        let slot = sX[dx + R] + sZ[dz + R]
                        if dx == 0 && dz == 0 { sealEyeLow = Int(m) - 1 }
                        sealLow[slot] = nx * nx + nz * nz >= fd2 ? max(0, m - 1) : 0
                    }
                }
                sealValid = true; sealEye = eye; sealPC = SIMD2(Int32(pcx), Int32(pcz))
            }
            sealOn = pSec >= sealEyeLow                     // (the eye in open air, or beside it)
        }
        if !sealOn && sealValid {
            for i in sealLow.indices { sealLow[i] = 0 }
            sealValid = false
        }
        let sl = sealLow
        var sealSkips = 0
        var topSec = 0
        for i in 0..<live.count where Int(tc[live[i].slot].topSec) > topSec { topSec = Int(tc[live[i].slot].topSec) }
        let yLimit = max(pSec, topSec + 1)
        var q = bfs, fd = found
        bfs = []; found = []
        q.removeAll(keepingCapacity: true)
        fd.removeAll(keepingCapacity: true)
        q.append(CullNode(col: Int32(startSlot), dx: 0, dz: 0, sy: Int16(pSec), entry: -1, mask: 0))
        vG[vidx(0, 0, pSec)] = g
        var head = 0
        let r2 = world.renderDistance * world.renderDistance + world.renderDistance      // (World.inMeshRadius)
        let bx = Float(pcx * CS), bz = Float(pcz * CS), topCut = maxSection
        let smoothWalls = world.fieldTerrain || SmoothTerrain.enabled
        let allVis: UInt64 = (1 << 36) - 1
        let half = V3(8, 8, 8), side = V3(16, 16, 16)
        let deepOn = SceneRenderer.deepSeaCull
        let flDeep = UInt8(SecInfo.deep), flNonEmpty = UInt8(SecInfo.nonEmpty)
        var deepSkips = 0
        @inline(__always) func deep(_ slot: Int, _ sy: Int) -> Bool {
            guard deepOn, tf[slot * NSEC + sy] & flDeep != 0 else { return false }
            deepSkips &+= 1
            return true
        }
        let fogOn = fogCull > 0 && !SceneRenderer.fogCullOff
        let fog2 = fogCull * fogCull
        // (a section's frustum and fog test once a frame: up to 26 neighbours ask for the same one)
        @inline(__always) func inView(_ vi: Int, _ nmn: V3) -> Bool {
            if frG[vi] == g { return frO[vi] != 0 }
            var ok = frustum.visible(min: nmn, max: nmn + side)
            if ok && fogOn { let c = simd_clamp(eye, nmn, nmn + side); ok = simd_length_squared(c - eye) <= fog2 }
            frG[vi] = g; frO[vi] = ok ? 1 : 0
            return ok
        }
        while head < q.count {
            let n = q[head]; head += 1
            let slot = Int(n.col)
            guard tc[slot].present else { continue }
            let sy = Int(n.sy), dx = Int(n.dx), dz = Int(n.dz), entry = Int(n.entry), mask = Int(n.mask)
            let si = slot * NSEC + sy
            let nonEmpty = tf[si] & flNonEmpty != 0
            let vme = vidx(dx, dz, sy)
            if sy < topCut && nonEmpty && fG[vme] != g && sy < Int(sl[slot]) { fG[vme] = g; sealSkips &+= 1 }
            if sy < topCut && nonEmpty && fG[vme] != g {
                fG[vme] = g
                let mn = V3(bx + Float(dx * CS), Float(sy * 16), bz + Float(dz * CS))
                let d = simd_length_squared(mn + half - eye)
                fd.append(UInt64(d.bitPattern) << 32 | UInt64(slot) << 8 | UInt64(sy))
            }
            let vis = tv[si]
            // P335: the 26 sections round a section with ground and open cells (as `cull`).
            if smoothWalls && nonEmpty && vis != 0 && vis != allVis {
                for oy in -1...1 { for oz in -1...1 { for ox in -1...1 where ox != 0 || oy != 0 || oz != 0 {
                    let ndx = dx + ox, ndz = dz + oz, nsy = sy + oy
                    if nsy < 0 || nsy >= NSEC || nsy >= topCut || abs(ndx) > R || abs(ndz) > R || ndx * ndx + ndz * ndz > r2 { continue }
                    let vi = vidx(ndx, ndz, nsy)
                    if fG[vi] == g || vG[vi] == g { continue }
                    let ns = sX[ndx + R] + sZ[ndz + R]
                    guard tc[ns].present, tc[ns].meshedOnce, tf[ns * NSEC + nsy] & flNonEmpty != 0 else { continue }
                    if nsy < Int(sl[ns]) { continue }
                    let nmn = V3(bx + Float(ndx * CS), Float(nsy * 16), bz + Float(ndz * CS))
                    if !inView(vi, nmn) { continue }
                    fG[vi] = g
                    fd.append(UInt64(simd_length_squared(nmn + half - eye).bitPattern) << 32 | UInt64(ns) << 8 | UInt64(nsy))
                } } }
            }
            for f in 0..<6 {
                if mask & (1 << (f ^ 1)) != 0 { continue }
                let through = entry < 0 || vis & (1 << UInt64(entry * 6 + f)) != 0
                let peek = !through && smoothWalls && vis & (1 << UInt64(f * 6 + f)) != 0
                if !through && !peek { continue }
                var ndx = dx, ndz = dz, nsy = sy
                switch f {
                case 0: ndx += 1
                case 1: ndx -= 1
                case 2: nsy += 1
                case 3: nsy -= 1
                case 4: ndz += 1
                default: ndz -= 1
                }
                if nsy < 0 || nsy >= NSEC || nsy > yLimit || abs(ndx) > R || abs(ndz) > R || ndx * ndx + ndz * ndz > r2 { continue }
                let vi = vidx(ndx, ndz, nsy)
                if vG[vi] == g { continue }
                let nmn = V3(bx + Float(ndx * CS), Float(nsy * 16), bz + Float(ndz * CS))
                if !inView(vi, nmn) { continue }
                let ns = sX[ndx + R] + sZ[ndz + R]
                if f != 2 && f != 3 {
                    guard tc[ns].present, tc[ns].meshedOnce else { continue }
                    if deep(ns, nsy) { continue }
                } else if deep(slot, nsy) { continue }
                if peek {
                    if tc[ns].present, nsy < topCut, nsy >= Int(sl[ns]), tf[ns * NSEC + nsy] & flNonEmpty != 0, fG[vi] != g {
                        fG[vi] = g
                        fd.append(UInt64(simd_length_squared(nmn + half - eye).bitPattern) << 32 | UInt64(ns) << 8 | UInt64(nsy))
                    }
                    continue
                }
                vG[vi] = g
                q.append(CullNode(col: Int32(ns), dx: Int16(ndx), dz: Int16(ndz), sy: Int16(nsy), entry: Int8(f ^ 1),
                                  mask: UInt8(mask | (1 << f))))
            }
        }
        deepSeaSkipped = deepSkips
        sealedSkipped = sealSkips
        cullVisits = q.count
        fd.sort()
        bfs = q; found = fd
        stage(1)
        if horizonCulling { horizonCullT(eye: eye) }
        stage(2)
        if occlusionCulling {
            let o0 = CFAbsoluteTimeGetCurrent()
            if rasterLate { rasterOccluders(R: R) }
            occWork.finish()
            testOccluded()
            occlusionMs = (CFAbsoluteTimeGetCurrent() - o0) * 1000      // (frame thread: the wait, or the raster, and the test)
        }
        stage(3)
        vl.removeAll(keepingCapacity: true)
        for k in found { vl.append(Int32(Int((k >> 8) & 0xFF_FFFF) * NSEC + Int(k & 0xFF))) }
        visible.removeAll(keepingCapacity: true)
        tableFrame = true
        visibleCount = vl.count
        stage(4)
        cullMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        return true
    }

    // horizonCull over the table (the same occluders and test).
    private func horizonCullT(eye: V3) {
        let B = SceneRenderer.hBins
        let toBin = Float(B) / (2 * Float.pi)
        // (the arrays as locals for the loop: no exclusivity or uniqueness check at each access on the host build)
        var top = hTop, bot = hBot, fd = found, fpg = fpGen, fpv = fpV, seen = tabSeen
        hTop = []; hBot = []; found = []; fpGen = []; fpV = []; tabSeen = []
        defer { hTop = top; hBot = bot; found = fd; fpGen = fpg; fpV = fpv; tabSeen = seen }
        for b in 0..<B { top[b] = -.infinity; bot[b] = .infinity }
        // Occluders not applied yet, by their far distance (equal ones in the order taken): a section applies those
        // nearer than itself, a prefix, in the order they were taken (as the unsorted list did).
        var occ = hOcc
        hOcc = []
        defer { hOcc = occ }
        occ.removeAll(keepingCapacity: true)
        var oHead = 0, seq: Int32 = 0
        var batch = hBatch
        hBatch = []
        defer { hBatch = batch }
        var skipped = 0
        let g = gen
        let tc = tabCol
        func footprint(_ x0: Float, _ z0: Float, _ w: Float) -> (a0: Float, a1: Float, dmin: Float, dmax: Float)? {
            let cx = x0 + w / 2, cz = z0 + w / 2
            let nx = max(x0, min(eye.x, x0 + w)), nz = max(z0, min(eye.z, z0 + w))
            let dmin = ((nx - eye.x) * (nx - eye.x) + (nz - eye.z) * (nz - eye.z)).squareRoot()
            if dmin < 1 { return nil }
            let ac = atan2(cz - eye.z, cx - eye.x)
            var a0 = Float.infinity, a1 = -Float.infinity, dmax: Float = 0
            func corner(_ x: Float, _ z: Float) {
                var a = atan2(z - eye.z, x - eye.x) - ac
                if a > .pi { a -= 2 * .pi } else if a < -.pi { a += 2 * .pi }
                a0 = min(a0, a); a1 = max(a1, a)
                dmax = max(dmax, ((x - eye.x) * (x - eye.x) + (z - eye.z) * (z - eye.z)).squareRoot())
            }
            corner(x0, z0); corner(x0 + w, z0); corner(x0, z0 + w); corner(x0 + w, z0 + w)
            return ((ac + a0) * toBin, (ac + a1) * toBin, dmin, dmax)
        }
        var out = 0
        for k in 0..<fd.count {
            let key = fd[k]
            let slot = Int((key >> 8) & 0xFF_FFFF), sy = Int(key & 0xFF)
            let ci = tc[slot]
            guard ci.present else { continue }
            var hidden = false
            // (the column's footprint once a frame: x = a0, y = a1, z = dmin, w = dmax; dmin < 0 for none)
            if fpg[slot] != g {
                fpg[slot] = g
                if let f = footprint(Float(Int(ci.cx) * CS), Float(Int(ci.cz) * CS), 16) { fpv[slot] = SIMD4(f.a0, f.a1, f.dmin, f.dmax) }
                else { fpv[slot] = SIMD4(0, 0, -1, 0) }
            }
            let fp = fpv[slot]
            if fp.z >= 0 {
                let fa0 = fp.x, fa1 = fp.y, dmin = fp.z, dmax = fp.w
                var p = oHead
                while p < occ.count && occ[p].dmax <= dmin { p += 1 }
                if p > oHead {
                    batch.removeAll(keepingCapacity: true)
                    for i in oHead..<p { batch.append(occ[i]) }
                    if batch.count > 1 { batch.sort { $0.seq < $1.seq } }
                    for o in batch where o.dmax >= 0 {
                        for b in o.b0...o.b1 {
                            let m = ((b % B) + B) % B
                            if o.top > top[m] { top[m] = o.top; bot[m] = o.bot }
                        }
                    }
                    oHead = p
                    if oHead > 256 && oHead * 2 > occ.count { occ.removeFirst(oHead); oHead = 0 }
                }
                let y0 = Float(sy * 16) - eye.y, y1 = y0 + 16
                let eMax = y1 > 0 ? y1 / dmin : y1 / dmax, eMin = y0 < 0 ? y0 / dmin : y0 / dmax
                let b0 = Int(floor(fa0)), b1 = Int(floor(fa1))
                if b1 - b0 < B / 4 {
                    hidden = true
                    for b in b0...b1 {
                        let m = ((b % B) + B) % B
                        if !(eMax < top[m] && eMin > bot[m]) { hidden = false; break }
                    }
                }
                if seen[slot] != g {
                    seen[slot] = g
                    let H = Int(ci.occTop)
                    if H > 0 {
                        let ht = Float(H) - eye.y, hb = ht - 16
                        let ot = min(ht / dmin, ht / dmax), ob = max(hb / dmin, hb / dmax)
                        let ib0 = Int(ceil(fa0)), ib1 = Int(floor(fa1)) - 1
                        if ib1 >= ib0 && ot > ob {
                            // (after every pending one with a far distance not over this one's)
                            var lo = oHead, hi = occ.count
                            while lo < hi { let mid = (lo + hi) / 2; if occ[mid].dmax <= dmax { lo = mid + 1 } else { hi = mid } }
                            occ.insert(HOcc(dmax: dmax, b0: ib0, b1: ib1, top: ot, bot: ob, seq: seq), at: lo)
                            seq += 1
                        }
                    }
                }
            }
            if hidden { skipped += 1; continue }
            fd[out] = key; out += 1
        }
        fd.removeLast(fd.count - out)
        horizonSkipped = skipped
    }

    // occlusionCull over the table (the same occluder boxes, buffer and test), in two halves: the occluder boxes drawn
    // into the depth buffer (from the table alone: on a worker while the walk runs), then the walk's sections tested.
    private func rasterOccluders(R: Int) {
        occluderBoxes = 0
        let t0 = CFAbsoluteTimeGetCurrent()
        defer { occRasterMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000 }
        guard let vp = occlusionVP else { return }
        let W = SceneRenderer.oW, H = SceneRenderer.oH
        // (locals for the loops: no exclusivity or uniqueness checks at each access on the host build)
        var od = oDepth, tmin = oTileMin, tmax = oTileMax
        oDepth = []; oTileMin = []; oTileMax = []
        defer { oDepth = od; oTileMin = tmin; oTileMax = tmax }
        let tc = tabCol, tf = tabFl, sX = slotX, sZ = slotZ
        var boxes = 0
        defer { occluderBoxes = boxes }
        for i in 0..<(W * H) { od[i] = .infinity }
        let near: Float = 0.5
        func project(_ p: V3) -> SIMD3<Float> {
            let c = vp * SIMD4<Float>(p.x, p.y, p.z, 1)
            if c.w <= near { return SIMD3(0, 0, -1) }
            return SIMD3((c.x / c.w * 0.5 + 0.5) * Float(W), (0.5 - c.y / c.w * 0.5) * Float(H), c.w)
        }
        var pts = [SIMD2<Float>](repeating: .zero, count: 8)
        var hull: [SIMD2<Float>] = []
        func corners(_ mn: V3, _ mx: V3, _ body: (Int, V3) -> Void) {
            for k in 0..<8 { body(k, V3(k & 1 == 0 ? mn.x : mx.x, k & 2 == 0 ? mn.y : mx.y, k & 4 == 0 ? mn.z : mx.z)) }
        }
        let oc = min(SceneRenderer.occluderChunks, R)
        for dz in -oc...oc { for dx in -oc...oc {
            let slot = sX[dx + R] + sZ[dz + R]
            let ci = tc[slot]
            guard ci.present else { continue }
            let base = slot * NSEC, topS = Int(ci.topSec)
            var sy = 0
            while sy <= topS {
                guard tf[base + sy] & UInt8(SecInfo.solidFull) != 0 else { sy += 1; continue }
                var top = sy
                while top + 1 <= topS && tf[base + top + 1] & UInt8(SecInfo.solidFull) != 0 { top += 1 }
                let ox = Float(Int(ci.cx) * CS), oz = Float(Int(ci.cz) * CS)
                let mn = V3(ox + 2, Float(sy * 16) + 2, oz + 2)
                let mx = V3(ox + 14, Float(top * 16) + 14, oz + 14)
                sy = top + 1
                var dMax: Float = 0, behind = false
                corners(mn, mx) { k, p in
                    let q = project(p)
                    if q.z < 0 { behind = true } else { pts[k] = SIMD2(q.x, q.y); dMax = max(dMax, q.z) }
                }
                if behind { continue }
                for i in 1..<8 {
                    let v = pts[i]; var j = i - 1
                    while j >= 0 && (pts[j].x > v.x || (pts[j].x == v.x && pts[j].y > v.y)) { pts[j + 1] = pts[j]; j -= 1 }
                    pts[j + 1] = v
                }
                let sorted = pts
                hull.removeAll(keepingCapacity: true)
                func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
                for p in sorted { while hull.count >= 2 && cross(hull[hull.count - 2], hull[hull.count - 1], p) <= 0 { hull.removeLast() }; hull.append(p) }
                let lower = hull.count + 1
                for p in sorted.reversed() { while hull.count >= lower && cross(hull[hull.count - 2], hull[hull.count - 1], p) <= 0 { hull.removeLast() }; hull.append(p) }
                hull.removeLast()
                guard hull.count >= 3 else { continue }
                boxes += 1
                var y0 = Float.infinity, y1 = -Float.infinity
                for p in hull { y0 = min(y0, p.y); y1 = max(y1, p.y) }
                let r0 = max(0, Int(ceil(y0))), r1 = min(H - 1, Int(floor(y1)) - 1)
                if r0 > r1 { continue }
                func spanAt(_ y: Float) -> (Float, Float) {
                    var lo = Float.infinity, hi = -Float.infinity
                    for e in 0..<hull.count {
                        let a = hull[e], b = hull[(e + 1) % hull.count]
                        if (a.y <= y && b.y >= y) || (b.y <= y && a.y >= y) {
                            if a.y == b.y { lo = min(lo, min(a.x, b.x)); hi = max(hi, max(a.x, b.x)) }
                            else { let x = a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x); lo = min(lo, x); hi = max(hi, x) }
                        }
                    }
                    return (lo, hi)
                }
                for r in r0...r1 {
                    let (l0, h0) = spanAt(Float(r)), (l1, h1) = spanAt(Float(r + 1))
                    let xa = max(0, Int(ceil(max(l0, l1)))), xb = min(W - 1, Int(floor(min(h0, h1))) - 1)
                    if xa > xb { continue }
                    let row = r * W
                    for x in xa...xb where od[row + x] > dMax { od[row + x] = dMax }
                }
            }
        } }
        guard boxes > 0 else { return }
        let T = SceneRenderer.oT, TW = W / T, TH = H / T
        for ty in 0..<TH { for tx in 0..<TW {
            var lo = Float.infinity, hi = -Float.infinity
            for y in (ty * T)..<(ty * T + T) { let row = y * W; for x in (tx * T)..<(tx * T + T) { let d = od[row + x]; lo = min(lo, d); hi = max(hi, d) } }
            tmin[ty * TW + tx] = lo; tmax[ty * TW + tx] = hi
        } }
    }

    private func testOccluded() {
        occlusionSkipped = 0
        guard occluderBoxes > 0, let vp = occlusionVP else { return }
        let W = SceneRenderer.oW, H = SceneRenderer.oH
        let near: Float = 0.5
        func project(_ p: V3) -> SIMD3<Float> {
            let c = vp * SIMD4<Float>(p.x, p.y, p.z, 1)
            if c.w <= near { return SIMD3(0, 0, -1) }
            return SIMD3((c.x / c.w * 0.5 + 0.5) * Float(W), (0.5 - c.y / c.w * 0.5) * Float(H), c.w)
        }
        func corners(_ mn: V3, _ mx: V3, _ body: (Int, V3) -> Void) {
            for k in 0..<8 { body(k, V3(k & 1 == 0 ? mn.x : mx.x, k & 2 == 0 ? mn.y : mx.y, k & 4 == 0 ? mn.z : mx.z)) }
        }
        let T = SceneRenderer.oT, TW = W / T
        let nearKeep: Float = 32 * 32
        let od = oDepth, tmin = oTileMin, tmax = oTileMax, tc = tabCol
        var fd = found
        found = []
        var skipped = 0
        defer { found = fd; occlusionSkipped = skipped }
        var out = 0
        for k in 0..<fd.count {
            let key = fd[k]
            let slot = Int((key >> 8) & 0xFF_FFFF), sy = Int(key & 0xFF)
            let ci = tc[slot]
            guard ci.present, Float(bitPattern: UInt32(key >> 32)) > nearKeep else { fd[out] = key; out += 1; continue }
            let mn = V3(Float(Int(ci.cx) * CS) - 2, Float(sy * 16) - 2, Float(Int(ci.cz) * CS) - 2), mx = mn + V3(20, 20, 20)
            var dMin = Float.infinity, behind = false
            var xMin = Float.infinity, xMax = -Float.infinity, yMin = Float.infinity, yMax = -Float.infinity
            corners(mn, mx) { _, p in
                let q = project(p)
                if q.z < 0 { behind = true; return }
                dMin = min(dMin, q.z); xMin = min(xMin, q.x); xMax = max(xMax, q.x); yMin = min(yMin, q.y); yMax = max(yMax, q.y)
            }
            var hidden = !behind
            if hidden {
                let xa = max(0, Int(floor(xMin))), xb = min(W - 1, Int(ceil(xMax)) - 1)
                let ya = max(0, Int(floor(yMin))), yb = min(H - 1, Int(ceil(yMax)) - 1)
                if xa > xb || ya > yb { hidden = false }
                else {
                    check: for ty in (ya / T)...(yb / T) { for tx in (xa / T)...(xb / T) {
                        let ti = ty * TW + tx
                        if tmax[ti] < dMin { continue }
                        let px0 = max(xa, tx * T), px1 = min(xb, tx * T + T - 1), py0 = max(ya, ty * T), py1 = min(yb, ty * T + T - 1)
                        if tmin[ti] >= dMin && px0 == tx * T && px1 == tx * T + T - 1 && py0 == ty * T && py1 == ty * T + T - 1 { hidden = false; break check }
                        for r in py0...py1 { let row = r * W; for x in px0...px1 where !(od[row + x] < dMin) { hidden = false; break check } }
                    } }
                }
            }
            if hidden { skipped += 1; continue }
            fd[out] = key; out += 1
        }
        fd.removeLast(fd.count - out)
    }

    fileprivate func writeRecordsT(_ s: Slot, eye: V3) {
        nRec = min(vl.count, SceneRenderer.recordCap)
        let recs = s.records.mapped!.bindMemory(to: SectionRec.self, capacity: max(1, nRec))
        for i in 0..<nRec {
            let v = Int(vl[i]), slot = v / NSEC, sy = v % NSEC
            let ci = tabCol[slot]
            recs[i] = SectionRec(x: Float(Int(ci.cx) * CS) - eye.x, y: Float(sy * 16) - eye.y, z: Float(Int(ci.cz) * CS) - eye.z, tint: ci.tintOff)
        }
    }

    private func bindPair(_ s: Slot, _ pr: Int32) {
        let (vb, tbuf) = pairBufs[Int(pr)]
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
    }

    // drawOpaqueBatched over the table (P385 step 2): each section's draw entries were made when its mesh came in
    // (fillColumn) and persist; a frame only sorts the visible ones into their slab pairs' lists.
    fileprivate func drawOpaqueBatchedT(_ s: Slot) {
        let stride = MemoryLayout<VkDrawIndexedIndirectCommand>.stride
        let cap = s.indirect.size / stride
        let maxPer = max(1, Int(ctx.props.limits.maxDrawIndirectCount))
        let cmds = s.indirect.mapped!.bindMemory(to: VkDrawIndexedIndirectCommand.self, capacity: cap)
        var used = 0
        defer { indirectUsed = used }
        // (the table and the lists as locals for the per-section loop: no exclusivity or uniqueness check at each access
        // on the host build)
        let ts = tabSec, tc = tabCol, vv = vl
        var anyDet = false
        for i in 0..<nRec where ts[Int(vv[i])].dQuads > 0 { anyDet = true; break }
        anyDetail = anyDet
        let mq = Int32(SceneRenderer.maxQuads)
        let mergeOn = SceneRenderer.drawMerged, re = recEye, mf = GroundMerge.farDistance
        for half in 0..<2 {
            let detail = half == 1
            if detail && !anyDet { break }
            var keysT = self.keysT, batchCount = self.batchCount, batchCut = self.batchCut
            var pendingDraws = self.pendingDraws, pendingCut = self.pendingCut, pairK = self.pairK
            self.keysT = []; self.batchCount = []; self.batchCut = []; self.pendingDraws = []; self.pendingCut = []; self.pairK = []
            keysT.removeAll(keepingCapacity: true); batchCount.removeAll(keepingCapacity: true); batchCut.removeAll(keepingCapacity: true)
            pendingDraws.removeAll(keepingCapacity: true); pendingCut.removeAll(keepingCapacity: true)
            var quadsDrawn = 0, merged = 0
            for i in 0..<nRec {
                let v = Int(vv[i])
                let e = ts[v]
                let pr = detail ? e.dPair : e.oPair
                let quads = detail ? e.dQuads : e.quads
                guard pr >= 0, quads > 0 else { continue }
                let tail = detail ? 0 : e.farTail
                var total = min(quads - tail, mq)
                let solid = min(detail ? e.dSolid : e.solid, total)
                var k = Int(pairK[Int(pr)])
                if k < 0 { k = keysT.count; pairK[Int(pr)] = Int32(k); keysT.append(pr); batchCount.append(0); batchCut.append(0) }
                let vo = detail ? e.dVo : e.oVo
                let fSkip = detail ? e.dSkip : e.fSkip, fExtra = detail ? e.dExtra : e.fExtra
                var cutFrom = solid
                let cutSwitch = !detail && (e.farCut > 0 || tail > 0)
                var far = false
                if (fExtra > 0 || cutSwitch) && solid >= fSkip && quads + fExtra <= mq && mergeOn {
                    // (mergedFar: past the merged ground distance)
                    let ci = tc[v / NSEC]
                    let mn = V3(Float(Int(ci.cx) * CS), Float((v % NSEC) * 16), Float(Int(ci.cz) * CS))
                    let qn = simd_clamp(re, mn, mn + V3(16, 16, 16))
                    far = simd_length_squared(qn - re) >= mf * mf
                }
                if far {
                    merged += 1
                    if solid > fSkip {
                        batchCount[k] += 1
                        pendingDraws.append((k, VkDrawIndexedIndirectCommand(indexCount: UInt32((solid - fSkip) * 6), instanceCount: 1,
                                                                             firstIndex: UInt32(fSkip * 6), vertexOffset: vo, firstInstance: UInt32(i))))
                    }
                    if fExtra > 0 {
                        batchCount[k] += 1
                        pendingDraws.append((k, VkDrawIndexedIndirectCommand(indexCount: UInt32(fExtra * 6), instanceCount: 1, firstIndex: 0,
                                                                             vertexOffset: vo + quads * 4, firstInstance: UInt32(i))))
                    }
                    if !detail { cutFrom = min(total, solid + e.farCut); total = min(quads, mq) }
                    quadsDrawn += Int(fExtra - fSkip - (cutFrom - solid))
                } else if solid > 0 {
                    batchCount[k] += 1
                    pendingDraws.append((k, VkDrawIndexedIndirectCommand(indexCount: UInt32(solid * 6), instanceCount: 1, firstIndex: 0,
                                                                         vertexOffset: vo, firstInstance: UInt32(i))))
                }
                if total > cutFrom {
                    batchCut[k] += 1
                    pendingCut.append((k, VkDrawIndexedIndirectCommand(indexCount: UInt32((total - cutFrom) * 6), instanceCount: 1,
                                                                       firstIndex: UInt32(cutFrom * 6), vertexOffset: vo, firstInstance: UInt32(i))))
                }
                quadsDrawn += Int(total)
            }
            for pr in keysT { pairK[Int(pr)] = -1 }
            drawnQuads += quadsDrawn; mergedSections += merged
            self.keysT = keysT; self.batchCount = batchCount; self.batchCut = batchCut
            self.pendingDraws = pendingDraws; self.pendingCut = pendingCut; self.pairK = pairK
            for pass in 0..<2 {
                let pending = pass == 0 ? pendingDraws : pendingCut, counts = pass == 0 ? batchCount : batchCut
                if pending.isEmpty { continue }
                guard used + pending.count <= cap else { break }
                vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe(["solid", "cut", "detail", "detailCut"][half * 2 + pass]))
                batchStart.removeAll(keepingCapacity: true)
                var at = used
                for n in counts { batchStart.append(at); at += n }
                for (k, cmd) in pending { cmds[batchStart[k]] = cmd; batchStart[k] += 1 }
                var start = used
                for k in 0..<keysT.count where counts[k] > 0 {
                    bindPair(s, keysT[k])
                    var left = counts[k], off = start
                    while left > 0 {
                        let n = min(left, maxPer)
                        vkCmdDrawIndexedIndirect(s.cmd, s.indirect.buffer, VkDeviceSize(off * stride), UInt32(n), UInt32(stride))
                        drawCalls += 1
                        left -= n; off += n
                    }
                    start += counts[k]
                }
                batchedSections += pending.count
                used = at
            }
        }
    }

    // drawTranslucent over the table: far (LOD 1) sections batched, then the near ones far to near, one draw each.
    fileprivate func drawTranslucentT(_ s: Slot, underwater: Bool) {
        bindTerrainBuffers(s)
        vkCmdBindPipeline(s.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe(underwater ? "waterUnder" : "water"))
        let farBatched = !underwater && SceneRenderer.batchFarWater && SceneRenderer.batchDraws && batchable && s.indirect != nil
            && drawFarTranslucentBatchedT(s)
        let mq = Int32(SceneRenderer.maxQuads)
        for i in stride(from: nRec - 1, through: 0, by: -1) {
            let v = Int(vl[i])
            if farBatched && tabCol[v / NSEC].lod1 { continue }
            let e = tabSec[v]
            guard e.tPair >= 0, e.tQuads > 0 else { continue }
            bindPair(s, e.tPair)
            let count = Int(min(e.tQuads, mq))
            drawCalls += 1; drawnQuads += count
            vkCmdDrawIndexed(s.cmd, UInt32(count * 6), 1, 0, e.tVo, UInt32(i))
        }
    }

    private func drawFarTranslucentBatchedT(_ s: Slot) -> Bool {
        batchedWater = 0
        let cmdStride = MemoryLayout<VkDrawIndexedIndirectCommand>.stride
        let cap = s.indirect.size / cmdStride
        let maxPer = max(1, Int(ctx.props.limits.maxDrawIndirectCount))
        let cmds = s.indirect.mapped!.bindMemory(to: VkDrawIndexedIndirectCommand.self, capacity: cap)
        keysT.removeAll(keepingCapacity: true); batchCount.removeAll(keepingCapacity: true)
        pendingDraws.removeAll(keepingCapacity: true)
        var quads = 0
        let mq = Int32(SceneRenderer.maxQuads)
        for i in stride(from: nRec - 1, through: 0, by: -1) {
            let v = Int(vl[i])
            guard tabCol[v / NSEC].lod1 else { continue }
            let e = tabSec[v]
            guard e.tPair >= 0, e.tQuads > 0 else { continue }
            let count = Int(min(e.tQuads, mq))
            var k = Int(pairK[Int(e.tPair)])
            if k < 0 { k = keysT.count; pairK[Int(e.tPair)] = Int32(k); keysT.append(e.tPair); batchCount.append(0) }
            batchCount[k] += 1
            pendingDraws.append((k, VkDrawIndexedIndirectCommand(indexCount: UInt32(count * 6), instanceCount: 1, firstIndex: 0,
                                                                 vertexOffset: e.tVo, firstInstance: UInt32(i))))
            quads += count
        }
        for pr in keysT { pairK[Int(pr)] = -1 }
        if pendingDraws.isEmpty { return true }
        let used = indirectUsed
        guard used + pendingDraws.count <= cap else { return false }
        batchStart.removeAll(keepingCapacity: true)
        var at = used
        for n in batchCount { batchStart.append(at); at += n }
        for (k, cmd) in pendingDraws { cmds[batchStart[k]] = cmd; batchStart[k] += 1 }
        var start = used
        for k in 0..<keysT.count {
            bindPair(s, keysT[k])
            var left = batchCount[k], off = start
            while left > 0 {
                let n = min(left, maxPer)
                vkCmdDrawIndexedIndirect(s.cmd, s.indirect.buffer, VkDeviceSize(off * cmdStride), UInt32(n), UInt32(cmdStride))
                drawCalls += 1
                left -= n; off += n
            }
            start += batchCount[k]
        }
        indirectUsed = at
        drawnQuads += quads
        batchedWater = pendingDraws.count
        return true
    }
}
