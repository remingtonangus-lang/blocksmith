import Foundation
import CVulkan

// Thin Vulkan helpers for the Quest renderer (and its Linux offscreen test on lavapipe). The instance and device are
// created by OpenXR (xrCreateVulkanInstanceKHR / xrCreateVulkanDeviceKHR) on the headset, or directly here for tests.

struct VkError: Error, CustomStringConvertible {
    let what: String
    let code: Int32
    var description: String { "\(what) failed (VkResult \(code))" }
}

@inline(__always) func vkCheck(_ r: VkResult, _ what: @autoclosure () -> String) throws {
    if r.rawValue < 0 { throw VkError(what: what(), code: r.rawValue) }
}

let VK_API_1_1: UInt32 = (1 << 22) | (1 << 12)

// Fixed-size C char arrays (tuples) to String.
func cString<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { raw in
        let b = raw.bindMemory(to: UInt8.self)
        let n = b.firstIndex(of: 0) ?? b.count
        return String(decoding: b[0..<n], as: UTF8.self)
    }
}

final class VkContext {
    let instance: VkInstance
    let physical: VkPhysicalDevice
    let device: VkDevice
    let queueFamily: UInt32
    let queue: VkQueue
    let pool: VkCommandPool
    var memProps = VkPhysicalDeviceMemoryProperties()
    var props = VkPhysicalDeviceProperties()
    var features = VkPhysicalDeviceFeatures()
    var enabledExtensions: Set<String> = []

    init(instance: VkInstance, physical: VkPhysicalDevice, device: VkDevice, queueFamily: UInt32, extensions: Set<String>) throws {
        self.instance = instance
        self.physical = physical
        self.device = device
        self.queueFamily = queueFamily
        enabledExtensions = extensions
        var q: VkQueue?
        vkGetDeviceQueue(device, queueFamily, 0, &q)
        guard let qq = q else { throw VkError(what: "vkGetDeviceQueue", code: -1) }
        queue = qq
        vkGetPhysicalDeviceMemoryProperties(physical, &memProps)
        vkGetPhysicalDeviceProperties(physical, &props)
        vkGetPhysicalDeviceFeatures(physical, &features)
        var ci = VkCommandPoolCreateInfo()
        ci.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
        ci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT.rawValue
        ci.queueFamilyIndex = queueFamily
        var p: VkCommandPool?
        try vkCheck(vkCreateCommandPool(device, &ci, nil, &p), "vkCreateCommandPool")
        pool = p!
    }

    var deviceName: String { cString(props.deviceName) }

    // Picks the graphics queue family of a physical device.
    static func graphicsFamily(_ pd: VkPhysicalDevice) -> UInt32? {
        var n: UInt32 = 0
        vkGetPhysicalDeviceQueueFamilyProperties(pd, &n, nil)
        var fams = [VkQueueFamilyProperties](repeating: VkQueueFamilyProperties(), count: Int(n))
        vkGetPhysicalDeviceQueueFamilyProperties(pd, &n, &fams)
        for (i, f) in fams.enumerated() where f.queueFlags & VK_QUEUE_GRAPHICS_BIT.rawValue != 0 { return UInt32(i) }
        return nil
    }

    static func deviceExtensions(_ pd: VkPhysicalDevice) -> Set<String> {
        var n: UInt32 = 0
        vkEnumerateDeviceExtensionProperties(pd, nil, &n, nil)
        var ext = [VkExtensionProperties](repeating: VkExtensionProperties(), count: Int(n))
        vkEnumerateDeviceExtensionProperties(pd, nil, &n, &ext)
        return Set(ext.map { cString($0.extensionName) })
    }

    // Standalone instance + device (Linux tests; the headset goes through OpenXR instead).
    static func standalone() throws -> VkContext {
        var app = VkApplicationInfo()
        app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
        app.apiVersion = VK_API_1_1
        var ici = VkInstanceCreateInfo()
        ici.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        var inst: VkInstance?
        try withUnsafePointer(to: &app) { ap in
            ici.pApplicationInfo = ap
            try vkCheck(vkCreateInstance(&ici, nil, &inst), "vkCreateInstance")
        }
        var n: UInt32 = 0
        vkEnumeratePhysicalDevices(inst, &n, nil)
        guard n > 0 else { throw VkError(what: "no Vulkan device", code: -1) }
        var pds = [VkPhysicalDevice?](repeating: nil, count: Int(n))
        vkEnumeratePhysicalDevices(inst, &n, &pds)
        let pd = pds[0]!
        guard let fam = graphicsFamily(pd) else { throw VkError(what: "no graphics queue", code: -1) }
        let (dev, exts) = try createDevice(pd, family: fam, wantExtensions: [])
        return try VkContext(instance: inst!, physical: pd, device: dev, queueFamily: fam, extensions: exts)
    }

    // A device with one graphics queue, multiview and the optional extensions the physical device has.
    static func createDevice(_ pd: VkPhysicalDevice, family: UInt32, wantExtensions: [String]) throws -> (VkDevice, Set<String>) {
        let avail = deviceExtensions(pd)
        let exts = wantExtensions.filter { avail.contains($0) }
        let arena = PtrArena()
        var ci = deviceCreateInfo(pd, family: family, extensions: exts, arena: arena)
        var dev: VkDevice?
        try vkCheck(vkCreateDevice(pd, &ci, nil, &dev), "vkCreateDevice")
        return (dev!, Set(exts))
    }

    // The VkDeviceCreateInfo (one graphics queue, multiview, anisotropy); its pointers live in `arena`.
    static func deviceCreateInfo(_ pd: VkPhysicalDevice, family: UInt32, extensions: [String], arena: PtrArena) -> VkDeviceCreateInfo {
        var qci = VkDeviceQueueCreateInfo()
        qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
        qci.queueFamilyIndex = family
        qci.queueCount = 1
        qci.pQueuePriorities = arena.ptr(Float(1))
        var mv = VkPhysicalDeviceMultiviewFeatures()
        mv.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MULTIVIEW_FEATURES
        mv.multiview = 1
        var have = VkPhysicalDeviceFeatures()
        vkGetPhysicalDeviceFeatures(pd, &have)
        var feats = VkPhysicalDeviceFeatures()
        feats.samplerAnisotropy = have.samplerAnisotropy
        var ci = VkDeviceCreateInfo()
        ci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
        ci.pNext = UnsafeRawPointer(arena.ptr(mv))
        ci.queueCreateInfoCount = 1
        ci.pQueueCreateInfos = arena.ptr(qci)
        ci.enabledExtensionCount = UInt32(extensions.count)
        ci.ppEnabledExtensionNames = extensions.isEmpty ? nil : arena.cstrs(extensions)
        ci.pEnabledFeatures = arena.ptr(feats)
        return ci
    }

    // MARK: Memory

    func memoryType(_ bits: UInt32, _ want: UInt32, avoid: UInt32 = 0) -> UInt32? {
        let types = withUnsafeBytes(of: memProps.memoryTypes) { Array($0.bindMemory(to: VkMemoryType.self)) }
        // First pass: exactly what we want without the avoided flags; then anything with the wanted flags.
        for pass in 0..<2 {
            for i in 0..<Int(memProps.memoryTypeCount) where bits & (1 << UInt32(i)) != 0 {
                let f = types[i].propertyFlags
                if f & want != want { continue }
                if pass == 0 && f & avoid != 0 { continue }
                return UInt32(i)
            }
        }
        return nil
    }

    func allocate(_ req: VkMemoryRequirements, _ want: UInt32, avoid: UInt32 = 0) throws -> VkDeviceMemory {
        guard let t = memoryType(req.memoryTypeBits, want, avoid: avoid) else { throw VkError(what: "no memory type for \(want)", code: -1) }
        var ai = VkMemoryAllocateInfo()
        ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        ai.allocationSize = req.size
        ai.memoryTypeIndex = t
        var m: VkDeviceMemory?
        try vkCheck(vkAllocateMemory(device, &ai, nil, &m), "vkAllocateMemory(\(req.size))")
        return m!
    }

    // MARK: One-shot commands

    func oneShot(_ body: (VkCommandBuffer) throws -> Void) throws {
        var ai = VkCommandBufferAllocateInfo()
        ai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        ai.commandPool = pool
        ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        ai.commandBufferCount = 1
        var cb: VkCommandBuffer?
        try vkCheck(vkAllocateCommandBuffers(device, &ai, &cb), "vkAllocateCommandBuffers")
        var bi = VkCommandBufferBeginInfo()
        bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT.rawValue
        vkBeginCommandBuffer(cb, &bi)
        try body(cb!)
        vkEndCommandBuffer(cb)
        var si = VkSubmitInfo()
        si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
        si.commandBufferCount = 1
        try withUnsafePointer(to: &cb) { p in
            si.pCommandBuffers = p
            try vkCheck(vkQueueSubmit(queue, 1, &si, nil), "vkQueueSubmit(one shot)")
        }
        vkQueueWaitIdle(queue)
        vkFreeCommandBuffers(device, pool, 1, &cb)
    }

    // MARK: Shaders

    func shaderModule(_ words: [UInt32]) throws -> VkShaderModule {
        var ci = VkShaderModuleCreateInfo()
        ci.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
        ci.codeSize = words.count * 4
        var m: VkShaderModule?
        try words.withUnsafeBufferPointer { p in
            ci.pCode = p.baseAddress
            try vkCheck(vkCreateShaderModule(device, &ci, nil, &m), "vkCreateShaderModule")
        }
        return m!
    }
}

// A buffer with its own memory. Host-visible buffers stay mapped for their lifetime.
final class VkBuf {
    let ctx: VkContext
    let buffer: VkBuffer
    let memory: VkDeviceMemory
    let size: Int
    let mapped: UnsafeMutableRawPointer?
    let coherent: Bool

    init(_ ctx: VkContext, size: Int, usage: UInt32, host: Bool) throws {
        self.ctx = ctx
        self.size = size
        var ci = VkBufferCreateInfo()
        ci.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        ci.size = VkDeviceSize(max(16, size))
        ci.usage = usage
        ci.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        var b: VkBuffer?
        try vkCheck(vkCreateBuffer(ctx.device, &ci, nil, &b), "vkCreateBuffer(\(size))")
        buffer = b!
        var req = VkMemoryRequirements()
        vkGetBufferMemoryRequirements(ctx.device, buffer, &req)
        let hv = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue, hc = VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue
        let dl = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue
        // Unified memory (the Quest): host-visible + coherent + device-local exists; lavapipe has host memory only.
        memory = try ctx.allocate(req, host ? (hv | hc) : dl)
        coherent = true
        try vkCheck(vkBindBufferMemory(ctx.device, buffer, memory, 0), "vkBindBufferMemory")
        if host {
            var p: UnsafeMutableRawPointer?
            try vkCheck(vkMapMemory(ctx.device, memory, 0, VkDeviceSize(VK_WHOLE_SIZE), 0, &p), "vkMapMemory")
            mapped = p
        } else {
            mapped = nil
        }
    }

    deinit {
        if mapped != nil { vkUnmapMemory(ctx.device, memory) }
        vkDestroyBuffer(ctx.device, buffer, nil)
        vkFreeMemory(ctx.device, memory, nil)
    }
}

// A 2D (array) image with a view.
final class VkImg {
    let ctx: VkContext
    let image: VkImage
    let memory: VkDeviceMemory?
    let view: VkImageView
    let width: Int, height: Int, layers: Int, levels: Int
    let format: VkFormat

    init(_ ctx: VkContext, width: Int, height: Int, layers: Int = 1, levels: Int = 1, format: VkFormat, usage: UInt32,
         aspect: UInt32 = VK_IMAGE_ASPECT_COLOR_BIT.rawValue, samples: VkSampleCountFlagBits = VK_SAMPLE_COUNT_1_BIT,
         transient: Bool = false, arrayView: Bool = true) throws {
        self.ctx = ctx
        self.width = width; self.height = height; self.layers = layers; self.levels = levels; self.format = format
        var ci = VkImageCreateInfo()
        ci.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
        ci.imageType = VK_IMAGE_TYPE_2D
        ci.format = format
        ci.extent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
        ci.mipLevels = UInt32(levels)
        ci.arrayLayers = UInt32(layers)
        ci.samples = samples
        ci.tiling = VK_IMAGE_TILING_OPTIMAL
        ci.usage = usage | (transient ? VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT.rawValue : 0)
        ci.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        ci.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        var img: VkImage?
        try vkCheck(vkCreateImage(ctx.device, &ci, nil, &img), "vkCreateImage(\(width)x\(height)x\(layers))")
        image = img!
        var req = VkMemoryRequirements()
        vkGetImageMemoryRequirements(ctx.device, image, &req)
        let lazy = VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT.rawValue, dl = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue
        let mem: VkDeviceMemory
        if transient, let t = ctx.memoryType(req.memoryTypeBits, lazy | dl) {
            var ai = VkMemoryAllocateInfo()
            ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
            ai.allocationSize = req.size
            ai.memoryTypeIndex = t
            var m: VkDeviceMemory?
            try vkCheck(vkAllocateMemory(ctx.device, &ai, nil, &m), "vkAllocateMemory(lazy)")
            mem = m!
        } else {
            mem = try ctx.allocate(req, dl)
        }
        memory = mem
        try vkCheck(vkBindImageMemory(ctx.device, image, mem, 0), "vkBindImageMemory")
        view = try VkImg.makeView(ctx, image, format: format, aspect: aspect, layers: layers, levels: levels, array: arrayView)
    }

    static func makeView(_ ctx: VkContext, _ image: VkImage, format: VkFormat, aspect: UInt32, layers: Int, levels: Int, array: Bool,
                         baseLayer: Int = 0) throws -> VkImageView {
        var vi = VkImageViewCreateInfo()
        vi.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
        vi.image = image
        vi.viewType = array ? VK_IMAGE_VIEW_TYPE_2D_ARRAY : VK_IMAGE_VIEW_TYPE_2D
        vi.format = format
        vi.subresourceRange = VkImageSubresourceRange(aspectMask: aspect, baseMipLevel: 0, levelCount: UInt32(levels),
                                                      baseArrayLayer: UInt32(baseLayer), layerCount: UInt32(layers))
        var v: VkImageView?
        try vkCheck(vkCreateImageView(ctx.device, &vi, nil, &v), "vkCreateImageView")
        return v!
    }

    deinit {
        vkDestroyImageView(ctx.device, view, nil)
        vkDestroyImage(ctx.device, image, nil)
        if let m = memory { vkFreeMemory(ctx.device, m, nil) }
    }
}

// Image layout transition (whole image).
func vkBarrier(_ cb: VkCommandBuffer, _ image: VkImage, from: VkImageLayout, to: VkImageLayout, aspect: UInt32 = VK_IMAGE_ASPECT_COLOR_BIT.rawValue,
               levels: Int = 1, layers: Int = 1, srcAccess: UInt32, dstAccess: UInt32, srcStage: UInt32, dstStage: UInt32,
               baseLevel: Int = 0) {
    var b = VkImageMemoryBarrier()
    b.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
    b.oldLayout = from
    b.newLayout = to
    b.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
    b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
    b.image = image
    b.subresourceRange = VkImageSubresourceRange(aspectMask: aspect, baseMipLevel: UInt32(baseLevel), levelCount: UInt32(levels),
                                                 baseArrayLayer: 0, layerCount: UInt32(layers))
    b.srcAccessMask = srcAccess
    b.dstAccessMask = dstAccess
    vkCmdPipelineBarrier(cb, srcStage, dstStage, 0, 0, nil, 0, nil, 1, &b)
}

// Stable copies of values and arrays for the pointer fields of Vulkan/OpenXR create-info structs; freed with the arena.
final class PtrArena {
    private var blocks: [UnsafeMutableRawPointer] = []
    deinit { for b in blocks { b.deallocate() } }
    func array<T>(_ a: [T]) -> UnsafePointer<T> {
        let p = UnsafeMutablePointer<T>.allocate(capacity: max(1, a.count))
        if !a.isEmpty { p.initialize(from: a, count: a.count) }
        blocks.append(UnsafeMutableRawPointer(p))
        return UnsafePointer(p)
    }
    func ptr<T>(_ v: T) -> UnsafePointer<T> { array([v]) }
    func mutablePtr<T>(_ v: T) -> UnsafeMutablePointer<T> { UnsafeMutablePointer(mutating: array([v])) }
    func cstr(_ s: String) -> UnsafePointer<CChar> {
        let u = Array(s.utf8CString)
        return array(u)
    }
    func cstrs(_ list: [String]) -> UnsafePointer<UnsafePointer<CChar>?> { array(list.map { Optional(cstr($0)) }) }
}
