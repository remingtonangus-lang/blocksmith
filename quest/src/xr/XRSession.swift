import Foundation
import simd
import CVulkan
import COpenXR

struct XrError: Error, CustomStringConvertible {
    let what: String
    let code: Int32
    var description: String { "\(what) failed (XrResult \(code))" }
}

@inline(__always) func xrCheck(_ r: XrResult, _ what: @autoclosure () -> String) throws {
    if r.rawValue < 0 { throw XrError(what: what(), code: r.rawValue) }
}

// Copies a string into a fixed-size C char array field (tuple).
func setCString<T>(_ field: inout T, _ s: String) {
    withUnsafeMutableBytes(of: &field) { raw in
        let n = min(raw.count - 1, s.utf8.count)
        for (i, b) in s.utf8.prefix(n).enumerated() { raw[i] = b }
        raw[n] = 0
    }
}

// What the platform hands the XR layer (Android: the JavaVM and the activity for the loader and instance).
struct XRPlatform {
    var javaVM: UnsafeMutableRawPointer?
    var activity: UnsafeMutableRawPointer?
}

// One controller's state this frame (tracking space, before the game's yaw/position transform).
struct XRHand {
    var aimValid = false
    var aimPos = V3.zero
    var aimRot = simd_quatf()
    var gripValid = false
    var gripPos = V3.zero
    var gripRot = simd_quatf()
    var stick = V2.zero
    var trigger: Float = 0
    var squeeze: Float = 0
    var stickClick = false
    var button1 = false            // A (right) / X (left)
    var button2 = false            // B (right) / Y (left)
    var menu = false               // left menu button
    var thumbRest = false
}

// The OpenXR side of the Quest app: instance (Khronos loader), system, Vulkan through XR_KHR_vulkan_enable2, the
// session state machine, a two-layer (multiview) colour swapchain, LOCAL_FLOOR space, Touch controller actions and
// haptics, display refresh rate, foveation and performance levels where the runtime offers them.
final class XRSession {
    private(set) var instance: XrInstance?
    private(set) var systemId: XrSystemId = 0
    private(set) var session: XrSession?
    private(set) var appSpace: XrSpace?
    private(set) var viewSpace: XrSpace?
    private(set) var vk: VkContext!
    private(set) var swapchain: XrSwapchain?
    private(set) var swapImages: [VkImage] = []
    private(set) var densityMaps: [VkImage?] = []        // per swapchain image (foveated swapchains)
    private(set) var foveated = false
    private var foveationProfile: XrFoveationProfileFB?
    private(set) var width = 0, height = 0
    private(set) var colorFormat = VK_FORMAT_R8G8B8A8_SRGB
    private(set) var exts = Set<String>()
    private(set) var state = XR_SESSION_STATE_UNKNOWN
    private(set) var running = false
    private(set) var exitRequested = false
    private(set) var floorSpace = true          // appSpace origin on the floor (LOCAL_FLOOR / STAGE); else LOCAL
    private(set) var refreshRate: Float = 72
    private(set) var runtimeName = ""
    var focused: Bool { state == XR_SESSION_STATE_FOCUSED }
    var resolutionScale: Float = 1

    // Actions
    private var actionSet: XrActionSet?
    private var aAim: XrAction?, aGrip: XrAction?, aStick: XrAction?, aTrigger: XrAction?, aSqueeze: XrAction?
    private var aStickClick: XrAction?, aButton1: XrAction?, aButton2: XrAction?, aMenu: XrAction?, aThumbRest: XrAction?
    private var aHaptic: XrAction?
    private var handPaths: [XrPath] = [0, 0]
    private var aimSpaces: [XrSpace?] = [nil, nil]
    private var gripSpaces: [XrSpace?] = [nil, nil]
    private(set) var hands = [XRHand(), XRHand()]       // 0 left, 1 right

    // Frame
    private(set) var views = [XrView](repeating: XrView(), count: 2)
    private(set) var predictedTime: XrTime = 0
    private(set) var headPos = V3.zero
    private(set) var headRot = simd_quatf()

    // MARK: Setup

    init(platform: XRPlatform) throws {
        #if os(Android)
        var initLoader: PFN_xrVoidFunction?
        try xrCheck(xrGetInstanceProcAddr(nil, "xrInitializeLoaderKHR", &initLoader), "xrGetInstanceProcAddr(xrInitializeLoaderKHR)")
        if let f = initLoader {
            let fn = unsafeBitCast(f, to: PFN_xrInitializeLoaderKHR.self)
            var li = XrLoaderInitInfoAndroidKHR()
            li.type = XR_TYPE_LOADER_INIT_INFO_ANDROID_KHR
            li.applicationVM = platform.javaVM
            li.applicationContext = platform.activity
            try withUnsafePointer(to: &li) { p in
                try xrCheck(fn(UnsafeRawPointer(p).assumingMemoryBound(to: XrLoaderInitInfoBaseHeaderKHR.self)), "xrInitializeLoaderKHR")
            }
        }
        #endif
        var n: UInt32 = 0
        try xrCheck(xrEnumerateInstanceExtensionProperties(nil, 0, &n, nil), "xrEnumerateInstanceExtensionProperties")
        var proto = XrExtensionProperties()
        proto.type = XR_TYPE_EXTENSION_PROPERTIES
        var props = [XrExtensionProperties](repeating: proto, count: Int(n))
        try xrCheck(xrEnumerateInstanceExtensionProperties(nil, n, &n, &props), "xrEnumerateInstanceExtensionProperties")
        let avail = Set(props.map { cString($0.extensionName) })
        print("xr: runtime extensions: \(avail.sorted().joined(separator: " "))")
        guard avail.contains("XR_KHR_vulkan_enable2") else { throw XrError(what: "XR_KHR_vulkan_enable2 missing", code: -1) }
        var want = ["XR_KHR_vulkan_enable2"]
        #if os(Android)
        want.append("XR_KHR_android_create_instance")
        #endif
        for e in ["XR_EXT_local_floor", "XR_FB_display_refresh_rate", "XR_EXT_performance_settings", "XR_FB_foveation",
                  "XR_FB_foveation_configuration", "XR_FB_swapchain_update_state", "XR_FB_foveation_vulkan", "XR_FB_color_space",
                  "XR_KHR_android_thread_settings"]
            where avail.contains(e) { want.append(e) }
        exts = Set(want)
        let a = PtrArena()
        var ci = XrInstanceCreateInfo()
        ci.type = XR_TYPE_INSTANCE_CREATE_INFO
        setCString(&ci.applicationInfo.applicationName, "Blocksmith")
        ci.applicationInfo.applicationVersion = 1
        setCString(&ci.applicationInfo.engineName, "Blocksmith")
        ci.applicationInfo.engineVersion = 1
        ci.applicationInfo.apiVersion = (1 << 48) | (0 << 32) | 34          // OpenXR 1.0
        ci.enabledExtensionCount = UInt32(want.count)
        ci.enabledExtensionNames = a.cstrs(want)
        #if os(Android)
        var ai = XrInstanceCreateInfoAndroidKHR()
        ai.type = XR_TYPE_INSTANCE_CREATE_INFO_ANDROID_KHR
        ai.applicationVM = platform.javaVM
        ai.applicationActivity = platform.activity
        ci.next = UnsafeRawPointer(a.ptr(ai))
        #endif
        var inst: XrInstance?
        try xrCheck(xrCreateInstance(&ci, &inst), "xrCreateInstance")
        instance = inst
        var ip = XrInstanceProperties()
        ip.type = XR_TYPE_INSTANCE_PROPERTIES
        if xrGetInstanceProperties(inst, &ip).rawValue >= 0 {
            runtimeName = cString(ip.runtimeName)
            print("xr: runtime \(runtimeName) \(ip.runtimeVersion >> 48).\((ip.runtimeVersion >> 32) & 0xFFFF).\(ip.runtimeVersion & 0xFFFFFFFF)")
        }
        var gi = XrSystemGetInfo()
        gi.type = XR_TYPE_SYSTEM_GET_INFO
        gi.formFactor = XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY
        try xrCheck(xrGetSystem(inst, &gi, &systemId), "xrGetSystem")
        try createVulkan()
        try createSession()
        try createSpaces()
        try createActions()
    }

    func proc<T>(_ name: String, _ type: T.Type) -> T? {
        var f: PFN_xrVoidFunction?
        guard xrGetInstanceProcAddr(instance, name, &f).rawValue >= 0, let fn = f else { return nil }
        return unsafeBitCast(fn, to: type)
    }

    private func createVulkan() throws {
        guard let getReq = proc("xrGetVulkanGraphicsRequirements2KHR", PFN_xrGetVulkanGraphicsRequirements2KHR.self),
              let createInst = proc("xrCreateVulkanInstanceKHR", PFN_xrCreateVulkanInstanceKHR.self),
              let getDev = proc("xrGetVulkanGraphicsDevice2KHR", PFN_xrGetVulkanGraphicsDevice2KHR.self),
              let createDev = proc("xrCreateVulkanDeviceKHR", PFN_xrCreateVulkanDeviceKHR.self) else {
            throw XrError(what: "vulkan_enable2 entry points", code: -1)
        }
        var req = XrGraphicsRequirementsVulkanKHR()
        req.type = XR_TYPE_GRAPHICS_REQUIREMENTS_VULKAN_KHR
        try xrCheck(getReq(instance, systemId, &req), "xrGetVulkanGraphicsRequirements2KHR")
        let a = PtrArena()
        var app = VkApplicationInfo()
        app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
        app.pApplicationName = a.cstr("Blocksmith")
        app.pEngineName = a.cstr("Blocksmith")
        app.apiVersion = VK_API_1_1
        var vici = VkInstanceCreateInfo()
        vici.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        vici.pApplicationInfo = a.ptr(app)
        var xci = XrVulkanInstanceCreateInfoKHR()
        xci.type = XR_TYPE_VULKAN_INSTANCE_CREATE_INFO_KHR
        xci.systemId = systemId
        xci.pfnGetInstanceProcAddr = vkGetInstanceProcAddr
        xci.vulkanCreateInfo = a.ptr(vici)
        var vkInst: VkInstance?
        var vkr = VK_SUCCESS
        try xrCheck(createInst(instance, &xci, &vkInst, &vkr), "xrCreateVulkanInstanceKHR")
        try vkCheck(vkr, "vkCreateInstance (through OpenXR)")
        var dgi = XrVulkanGraphicsDeviceGetInfoKHR()
        dgi.type = XR_TYPE_VULKAN_GRAPHICS_DEVICE_GET_INFO_KHR
        dgi.systemId = systemId
        dgi.vulkanInstance = vkInst
        var pd: VkPhysicalDevice?
        try xrCheck(getDev(instance, &dgi, &pd), "xrGetVulkanGraphicsDevice2KHR")
        guard let phys = pd, let fam = VkContext.graphicsFamily(phys) else { throw XrError(what: "no Vulkan graphics queue", code: -1) }
        let avail = VkContext.deviceExtensions(phys)
        var devExts: [String] = []
        if exts.contains("XR_FB_foveation_vulkan") && avail.contains("VK_EXT_fragment_density_map") { devExts.append("VK_EXT_fragment_density_map") }
        let vdci = VkContext.deviceCreateInfo(phys, family: fam, extensions: devExts, arena: a)
        var xdci = XrVulkanDeviceCreateInfoKHR()
        xdci.type = XR_TYPE_VULKAN_DEVICE_CREATE_INFO_KHR
        xdci.systemId = systemId
        xdci.pfnGetInstanceProcAddr = vkGetInstanceProcAddr
        xdci.vulkanPhysicalDevice = phys
        xdci.vulkanCreateInfo = a.ptr(vdci)
        var dev: VkDevice?
        try xrCheck(createDev(instance, &xdci, &dev, &vkr), "xrCreateVulkanDeviceKHR")
        try vkCheck(vkr, "vkCreateDevice (through OpenXR)")
        vk = try VkContext(instance: vkInst!, physical: phys, device: dev!, queueFamily: fam, extensions: Set(devExts))
        print("xr: Vulkan device \(vk.deviceName), queue family \(fam), extensions \(devExts)")
    }

    private func createSession() throws {
        let a = PtrArena()
        var gb = XrGraphicsBindingVulkanKHR()
        gb.type = XR_TYPE_GRAPHICS_BINDING_VULKAN_KHR
        gb.instance = vk.instance
        gb.physicalDevice = vk.physical
        gb.device = vk.device
        gb.queueFamilyIndex = vk.queueFamily
        gb.queueIndex = 0
        var sci = XrSessionCreateInfo()
        sci.type = XR_TYPE_SESSION_CREATE_INFO
        sci.next = UnsafeRawPointer(a.ptr(gb))
        sci.systemId = systemId
        var s: XrSession?
        try xrCheck(xrCreateSession(instance, &sci, &s), "xrCreateSession")
        session = s
    }

    private func createSpaces() throws {
        func space(_ t: XrReferenceSpaceType) -> XrSpace? {
            var ci = XrReferenceSpaceCreateInfo()
            ci.type = XR_TYPE_REFERENCE_SPACE_CREATE_INFO
            ci.referenceSpaceType = t
            ci.poseInReferenceSpace = XrPosef(orientation: XrQuaternionf(x: 0, y: 0, z: 0, w: 1), position: XrVector3f(x: 0, y: 0, z: 0))
            var sp: XrSpace?
            return xrCreateReferenceSpace(session, &ci, &sp).rawValue >= 0 ? sp : nil
        }
        // LOCAL_FLOOR (XR_EXT_local_floor): floor height, recentres with the user; else STAGE; else LOCAL (eye height).
        let localFloor = XrReferenceSpaceType(rawValue: 1000426000)     // XR_REFERENCE_SPACE_TYPE_LOCAL_FLOOR_EXT
        if exts.contains("XR_EXT_local_floor"), let s = space(localFloor) { appSpace = s; print("xr: LOCAL_FLOOR space") }
        else if let s = space(XR_REFERENCE_SPACE_TYPE_STAGE) { appSpace = s; print("xr: STAGE space") }
        else { appSpace = space(XR_REFERENCE_SPACE_TYPE_LOCAL); floorSpace = false; print("xr: LOCAL space") }
        viewSpace = space(XR_REFERENCE_SPACE_TYPE_VIEW)
        guard appSpace != nil else { throw XrError(what: "xrCreateReferenceSpace", code: -1) }
    }

    // MARK: Swapchain

    func createSwapchain() throws {
        var n: UInt32 = 0
        try xrCheck(xrEnumerateViewConfigurationViews(instance, systemId, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, 0, &n, nil), "xrEnumerateViewConfigurationViews")
        var vproto = XrViewConfigurationView()
        vproto.type = XR_TYPE_VIEW_CONFIGURATION_VIEW
        var cv = [XrViewConfigurationView](repeating: vproto, count: Int(n))
        try xrCheck(xrEnumerateViewConfigurationViews(instance, systemId, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, n, &n, &cv), "xrEnumerateViewConfigurationViews")
        guard cv.count >= 2 else { throw XrError(what: "stereo view configuration", code: -1) }
        width = Int(Float(cv[0].recommendedImageRectWidth) * resolutionScale) & ~7
        height = Int(Float(cv[0].recommendedImageRectHeight) * resolutionScale) & ~7
        width = min(width, Int(cv[0].maxImageRectWidth)); height = min(height, Int(cv[0].maxImageRectHeight))
        var fc: UInt32 = 0
        try xrCheck(xrEnumerateSwapchainFormats(session, 0, &fc, nil), "xrEnumerateSwapchainFormats")
        var fmts = [Int64](repeating: 0, count: Int(fc))
        try xrCheck(xrEnumerateSwapchainFormats(session, fc, &fc, &fmts), "xrEnumerateSwapchainFormats")
        let prefs: [VkFormat] = [VK_FORMAT_R8G8B8A8_SRGB, VK_FORMAT_B8G8R8A8_SRGB, VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_B8G8R8A8_UNORM]
        guard let f = prefs.first(where: { fmts.contains(Int64($0.rawValue)) }) else { throw XrError(what: "no usable swapchain format in \(fmts)", code: -1) }
        colorFormat = f
        var sci = XrSwapchainCreateInfo()
        sci.type = XR_TYPE_SWAPCHAIN_CREATE_INFO
        sci.usageFlags = XrSwapchainUsageFlags(XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT | XR_SWAPCHAIN_USAGE_SAMPLED_BIT)
        sci.format = Int64(f.rawValue)
        sci.sampleCount = 1
        sci.width = UInt32(width)
        sci.height = UInt32(height)
        sci.faceCount = 1
        sci.arraySize = 2
        sci.mipCount = 1
        // Fixed foveated rendering: a fragment density map per image (XR_FB_foveation_vulkan), level from the options.
        let wantFov = QuestSettings.foveation > 0 && exts.contains("XR_FB_foveation") && exts.contains("XR_FB_foveation_vulkan")
            && exts.contains("XR_FB_swapchain_update_state") && vk.enabledExtensions.contains("VK_EXT_fragment_density_map")
        var fci = XrSwapchainCreateInfoFoveationFB()
        fci.type = XR_TYPE_SWAPCHAIN_CREATE_INFO_FOVEATION_FB
        fci.flags = XrSwapchainCreateFoveationFlagsFB(XR_SWAPCHAIN_CREATE_FOVEATION_FRAGMENT_DENSITY_MAP_BIT_FB)
        var sc: XrSwapchain?
        if wantFov {
            try withUnsafeMutablePointer(to: &fci) { fp in
                sci.next = UnsafeRawPointer(fp)
                try xrCheck(xrCreateSwapchain(session, &sci, &sc), "xrCreateSwapchain(foveated \(width)x\(height)x2)")
            }
            sci.next = nil
        } else {
            try xrCheck(xrCreateSwapchain(session, &sci, &sc), "xrCreateSwapchain(\(width)x\(height)x2)")
        }
        foveated = wantFov
        swapchain = sc
        var ic: UInt32 = 0
        try xrCheck(xrEnumerateSwapchainImages(sc, 0, &ic, nil), "xrEnumerateSwapchainImages")
        var imgs = [XrSwapchainImageVulkanKHR](repeating: XrSwapchainImageVulkanKHR(type: XR_TYPE_SWAPCHAIN_IMAGE_VULKAN_KHR, next: nil, image: nil), count: Int(ic))
        var fovImgs = [XrSwapchainImageFoveationVulkanFB](repeating: XrSwapchainImageFoveationVulkanFB(), count: Int(ic))
        try fovImgs.withUnsafeMutableBufferPointer { fp in
            if foveated {
                for i in 0..<Int(ic) {
                    fp[i].type = XR_TYPE_SWAPCHAIN_IMAGE_FOVEATION_VULKAN_FB
                    imgs[i].next = UnsafeMutableRawPointer(fp.baseAddress! + i)
                }
            }
            try imgs.withUnsafeMutableBufferPointer { p in
                try xrCheck(xrEnumerateSwapchainImages(sc, ic, &ic, UnsafeMutableRawPointer(p.baseAddress!).assumingMemoryBound(to: XrSwapchainImageBaseHeader.self)),
                            "xrEnumerateSwapchainImages")
            }
        }
        swapImages = imgs.compactMap { $0.image }
        densityMaps = foveated ? fovImgs.map { $0.image } : []
        if foveated && (densityMaps.contains { $0 == nil }) { print("xr: foveation: density maps missing, off"); foveated = false; densityMaps = [] }
        if foveated {
            print("xr: foveated swapchain, density maps \(fovImgs.first.map { "\($0.width)x\($0.height)" } ?? "?")")
            applyFoveation(level: QuestSettings.foveation)
        }
        print("xr: swapchain \(width)x\(height) x2 layers, format \(f.rawValue), \(swapImages.count) images (recommended \(cv[0].recommendedImageRectWidth)x\(cv[0].recommendedImageRectHeight))")
    }

    // Sets the fixed foveation level (1 low ... 3 high) on the swapchain.
    func applyFoveation(level: Int) {
        guard foveated, let create = proc("xrCreateFoveationProfileFB", PFN_xrCreateFoveationProfileFB.self),
              let update = proc("xrUpdateSwapchainFB", PFN_xrUpdateSwapchainFB.self) else { return }
        var lp = XrFoveationLevelProfileCreateInfoFB()
        lp.type = XR_TYPE_FOVEATION_LEVEL_PROFILE_CREATE_INFO_FB
        lp.level = XrFoveationLevelFB(rawValue: UInt32(max(0, min(3, level))))
        lp.verticalOffset = 0
        lp.dynamic = XR_FOVEATION_DYNAMIC_DISABLED_FB
        var profile: XrFoveationProfileFB?
        var r = XR_ERROR_RUNTIME_FAILURE
        withUnsafeMutablePointer(to: &lp) { lpp in
            var pci = XrFoveationProfileCreateInfoFB()
            pci.type = XR_TYPE_FOVEATION_PROFILE_CREATE_INFO_FB
            pci.next = UnsafeMutableRawPointer(lpp)
            r = create(session, &pci, &profile)
        }
        guard r.rawValue >= 0, let prof = profile else { print("xr: foveation profile failed (\(r.rawValue))"); return }
        var st = XrSwapchainStateFoveationFB()
        st.type = XR_TYPE_SWAPCHAIN_STATE_FOVEATION_FB
        st.profile = prof
        let ur = withUnsafePointer(to: &st) { sp in update(swapchain, UnsafeRawPointer(sp).assumingMemoryBound(to: XrSwapchainStateBaseHeaderFB.self)) }
        if let old = foveationProfile, let destroy = proc("xrDestroyFoveationProfileFB", PFN_xrDestroyFoveationProfileFB.self) { _ = destroy(old) }
        foveationProfile = prof
        print("xr: foveation level \(level) (\(ur.rawValue >= 0 ? "applied" : "update failed \(ur.rawValue)"))")
    }

    // MARK: Actions

    private func path(_ s: String) -> XrPath {
        var p: XrPath = 0
        _ = xrStringToPath(instance, s, &p)
        return p
    }

    private func createActions() throws {
        var asci = XrActionSetCreateInfo()
        asci.type = XR_TYPE_ACTION_SET_CREATE_INFO
        setCString(&asci.actionSetName, "gameplay")
        setCString(&asci.localizedActionSetName, "Gameplay")
        try xrCheck(xrCreateActionSet(instance, &asci, &actionSet), "xrCreateActionSet")
        handPaths = [path("/user/hand/left"), path("/user/hand/right")]
        func action(_ name: String, _ type: XrActionType) throws -> XrAction? {
            var ci = XrActionCreateInfo()
            ci.type = XR_TYPE_ACTION_CREATE_INFO
            setCString(&ci.actionName, name)
            setCString(&ci.localizedActionName, name)
            ci.actionType = type
            ci.countSubactionPaths = 2
            var act: XrAction?
            try handPaths.withUnsafeBufferPointer { hp in
                ci.subactionPaths = hp.baseAddress
                try xrCheck(xrCreateAction(actionSet, &ci, &act), "xrCreateAction(\(name))")
            }
            return act
        }
        aAim = try action("aim", XR_ACTION_TYPE_POSE_INPUT)
        aGrip = try action("grip", XR_ACTION_TYPE_POSE_INPUT)
        aStick = try action("stick", XR_ACTION_TYPE_VECTOR2F_INPUT)
        aTrigger = try action("trigger", XR_ACTION_TYPE_FLOAT_INPUT)
        aSqueeze = try action("squeeze", XR_ACTION_TYPE_FLOAT_INPUT)
        aStickClick = try action("stick_click", XR_ACTION_TYPE_BOOLEAN_INPUT)
        aButton1 = try action("button_lower", XR_ACTION_TYPE_BOOLEAN_INPUT)
        aButton2 = try action("button_upper", XR_ACTION_TYPE_BOOLEAN_INPUT)
        aMenu = try action("menu", XR_ACTION_TYPE_BOOLEAN_INPUT)
        aThumbRest = try action("thumbrest", XR_ACTION_TYPE_BOOLEAN_INPUT)
        aHaptic = try action("haptic", XR_ACTION_TYPE_VIBRATION_OUTPUT)
        let b: [(XrAction?, String)] = [
            (aAim, "/user/hand/left/input/aim/pose"), (aAim, "/user/hand/right/input/aim/pose"),
            (aGrip, "/user/hand/left/input/grip/pose"), (aGrip, "/user/hand/right/input/grip/pose"),
            (aStick, "/user/hand/left/input/thumbstick"), (aStick, "/user/hand/right/input/thumbstick"),
            (aTrigger, "/user/hand/left/input/trigger/value"), (aTrigger, "/user/hand/right/input/trigger/value"),
            (aSqueeze, "/user/hand/left/input/squeeze/value"), (aSqueeze, "/user/hand/right/input/squeeze/value"),
            (aStickClick, "/user/hand/left/input/thumbstick/click"), (aStickClick, "/user/hand/right/input/thumbstick/click"),
            (aButton1, "/user/hand/left/input/x/click"), (aButton1, "/user/hand/right/input/a/click"),
            (aButton2, "/user/hand/left/input/y/click"), (aButton2, "/user/hand/right/input/b/click"),
            (aMenu, "/user/hand/left/input/menu/click"),
            (aThumbRest, "/user/hand/left/input/thumbrest/touch"), (aThumbRest, "/user/hand/right/input/thumbrest/touch"),
            (aHaptic, "/user/hand/left/output/haptic"), (aHaptic, "/user/hand/right/output/haptic"),
        ]
        let binds = b.map { XrActionSuggestedBinding(action: $0.0, binding: path($0.1)) }
        var sb = XrInteractionProfileSuggestedBinding()
        sb.type = XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING
        sb.interactionProfile = path("/interaction_profiles/oculus/touch_controller")
        sb.countSuggestedBindings = UInt32(binds.count)
        try binds.withUnsafeBufferPointer { bp in
            sb.suggestedBindings = bp.baseAddress
            try xrCheck(xrSuggestInteractionProfileBindings(instance, &sb), "xrSuggestInteractionProfileBindings(touch)")
        }
        // Generic fallback (simulators, other runtimes): poses, select = trigger, menu.
        let simple: [(XrAction?, String)] = [
            (aAim, "/user/hand/left/input/aim/pose"), (aAim, "/user/hand/right/input/aim/pose"),
            (aGrip, "/user/hand/left/input/grip/pose"), (aGrip, "/user/hand/right/input/grip/pose"),
            (aButton1, "/user/hand/left/input/select/click"), (aButton1, "/user/hand/right/input/select/click"),
            (aMenu, "/user/hand/left/input/menu/click"),
            (aHaptic, "/user/hand/left/output/haptic"), (aHaptic, "/user/hand/right/output/haptic"),
        ]
        let sbinds = simple.map { XrActionSuggestedBinding(action: $0.0, binding: path($0.1)) }
        sb.interactionProfile = path("/interaction_profiles/khr/simple_controller")
        sb.countSuggestedBindings = UInt32(sbinds.count)
        sbinds.withUnsafeBufferPointer { bp in
            sb.suggestedBindings = bp.baseAddress
            _ = xrSuggestInteractionProfileBindings(instance, &sb)
        }
        for h in 0..<2 {
            var sci = XrActionSpaceCreateInfo()
            sci.type = XR_TYPE_ACTION_SPACE_CREATE_INFO
            sci.subactionPath = handPaths[h]
            sci.poseInActionSpace = XrPosef(orientation: XrQuaternionf(x: 0, y: 0, z: 0, w: 1), position: XrVector3f(x: 0, y: 0, z: 0))
            sci.action = aAim
            try xrCheck(xrCreateActionSpace(session, &sci, &aimSpaces[h]), "xrCreateActionSpace(aim)")
            sci.action = aGrip
            try xrCheck(xrCreateActionSpace(session, &sci, &gripSpaces[h]), "xrCreateActionSpace(grip)")
        }
        var att = XrSessionActionSetsAttachInfo()
        att.type = XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO
        att.countActionSets = 1
        var sets: [XrActionSet?] = [actionSet]
        try sets.withUnsafeMutableBufferPointer { sp in
            att.actionSets = UnsafePointer(sp.baseAddress)
            try xrCheck(xrAttachSessionActionSets(session, &att), "xrAttachSessionActionSets")
        }
    }

    private func boolState(_ a: XrAction?, _ h: Int) -> Bool {
        var gi = XrActionStateGetInfo()
        gi.type = XR_TYPE_ACTION_STATE_GET_INFO
        gi.action = a
        gi.subactionPath = handPaths[h]
        var st = XrActionStateBoolean()
        st.type = XR_TYPE_ACTION_STATE_BOOLEAN
        return xrGetActionStateBoolean(session, &gi, &st).rawValue >= 0 && st.isActive != 0 && st.currentState != 0
    }
    private func floatState(_ a: XrAction?, _ h: Int) -> Float {
        var gi = XrActionStateGetInfo()
        gi.type = XR_TYPE_ACTION_STATE_GET_INFO
        gi.action = a
        gi.subactionPath = handPaths[h]
        var st = XrActionStateFloat()
        st.type = XR_TYPE_ACTION_STATE_FLOAT
        return xrGetActionStateFloat(session, &gi, &st).rawValue >= 0 && st.isActive != 0 ? st.currentState : 0
    }
    private func vecState(_ a: XrAction?, _ h: Int) -> V2 {
        var gi = XrActionStateGetInfo()
        gi.type = XR_TYPE_ACTION_STATE_GET_INFO
        gi.action = a
        gi.subactionPath = handPaths[h]
        var st = XrActionStateVector2f()
        st.type = XR_TYPE_ACTION_STATE_VECTOR2F
        return xrGetActionStateVector2f(session, &gi, &st).rawValue >= 0 && st.isActive != 0 ? V2(st.currentState.x, st.currentState.y) : .zero
    }
    private func locate(_ space: XrSpace?, _ time: XrTime) -> (Bool, V3, simd_quatf) {
        var loc = XrSpaceLocation()
        loc.type = XR_TYPE_SPACE_LOCATION
        guard xrLocateSpace(space, appSpace, time, &loc).rawValue >= 0 else { return (false, .zero, simd_quatf()) }
        let need = XrSpaceLocationFlags(XR_SPACE_LOCATION_POSITION_VALID_BIT | XR_SPACE_LOCATION_ORIENTATION_VALID_BIT)
        let ok = loc.locationFlags & need == need
        let p = loc.pose
        return (ok, V3(p.position.x, p.position.y, p.position.z), simd_quatf(ix: p.orientation.x, iy: p.orientation.y, iz: p.orientation.z, r: p.orientation.w))
    }

    // Syncs the actions and reads both controllers for the predicted display time.
    func pollInput() {
        guard running, focused else { hands = [XRHand(), XRHand()]; return }
        var active = XrActiveActionSet(actionSet: actionSet, subactionPath: 0)
        var si = XrActionsSyncInfo()
        si.type = XR_TYPE_ACTIONS_SYNC_INFO
        si.countActiveActionSets = 1
        withUnsafePointer(to: &active) { ap in
            si.activeActionSets = ap
            _ = xrSyncActions(session, &si)
        }
        for h in 0..<2 {
            var s = XRHand()
            (s.aimValid, s.aimPos, s.aimRot) = locate(aimSpaces[h], predictedTime)
            (s.gripValid, s.gripPos, s.gripRot) = locate(gripSpaces[h], predictedTime)
            s.stick = vecState(aStick, h)
            s.trigger = floatState(aTrigger, h)
            s.squeeze = floatState(aSqueeze, h)
            s.stickClick = boolState(aStickClick, h)
            s.button1 = boolState(aButton1, h)
            s.button2 = boolState(aButton2, h)
            s.menu = h == 0 && boolState(aMenu, h)
            s.thumbRest = boolState(aThumbRest, h)
            hands[h] = s
        }
    }

    // Vibrates a controller (hand 0 left, 1 right): amplitude 0...1, seconds.
    func haptic(_ hand: Int, amplitude: Float, seconds: Float, frequency: Float) {
        guard running, focused else { return }
        var gi = XrHapticActionInfo()
        gi.type = XR_TYPE_HAPTIC_ACTION_INFO
        gi.action = aHaptic
        gi.subactionPath = handPaths[hand]
        var v = XrHapticVibration()
        v.type = XR_TYPE_HAPTIC_VIBRATION
        v.amplitude = max(0, min(1, amplitude))
        v.duration = XrDuration(Double(seconds) * 1e9)
        v.frequency = frequency               // 0 = XR_FREQUENCY_UNSPECIFIED
        withUnsafePointer(to: &v) { vp in
            _ = xrApplyHapticFeedback(session, &gi, UnsafeRawPointer(vp).assumingMemoryBound(to: XrHapticBaseHeader.self))
        }
    }

    // MARK: Events

    // Drains the event queue; handles the session lifecycle. Returns false once the app should quit.
    func pollEvents() -> Bool {
        var buf = XrEventDataBuffer()
        while true {
            buf.type = XR_TYPE_EVENT_DATA_BUFFER
            buf.next = nil
            let r = xrPollEvent(instance, &buf)
            if r != XR_SUCCESS { break }
            switch buf.type {
            case XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING:
                print("xr: instance loss pending")
                exitRequested = true
            case XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED:
                let ev = withUnsafeBytes(of: &buf) { $0.load(as: XrEventDataSessionStateChanged.self) }
                state = ev.state
                print("xr: session state \(ev.state.rawValue)")
                switch ev.state {
                case XR_SESSION_STATE_READY:
                    var bi = XrSessionBeginInfo()
                    bi.type = XR_TYPE_SESSION_BEGIN_INFO
                    bi.primaryViewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO
                    if xrBeginSession(session, &bi).rawValue >= 0 { running = true; sessionStarted() }
                case XR_SESSION_STATE_STOPPING:
                    _ = xrEndSession(session)
                    running = false
                case XR_SESSION_STATE_EXITING, XR_SESSION_STATE_LOSS_PENDING:
                    exitRequested = true
                default: break
                }
            case XR_TYPE_EVENT_DATA_REFERENCE_SPACE_CHANGE_PENDING:
                onRecenter?()
            default: break
            }
        }
        return !exitRequested
    }
    var onRecenter: (() -> Void)?
    private(set) var availableRates: [Float] = []

    // Asks the runtime for a display refresh rate (the nearest offered one not above `want`); true when granted.
    func setRefreshRate(_ want: Float) -> Bool {
        guard let request = proc("xrRequestDisplayRefreshRateFB", PFN_xrRequestDisplayRefreshRateFB.self), !availableRates.isEmpty else { return false }
        let pick = availableRates.contains(want) ? want : (availableRates.filter { $0 <= want }.max() ?? 72)
        guard request(session, pick).rawValue >= 0 else { return false }
        refreshRate = pick
        return true
    }

    // After xrBeginSession: refresh rate, CPU/GPU levels.
    private func sessionStarted() {
        if exts.contains("XR_FB_display_refresh_rate"),
           let enumerate = proc("xrEnumerateDisplayRefreshRatesFB", PFN_xrEnumerateDisplayRefreshRatesFB.self) {
            var n: UInt32 = 0
            _ = enumerate(session, 0, &n, nil)
            var rates = [Float](repeating: 0, count: Int(n))
            _ = enumerate(session, n, &n, &rates)
            availableRates = rates
            _ = setRefreshRate(QuestSettings.refreshRate)
            print("xr: refresh rates \(rates), using \(refreshRate) Hz")
        }
        if exts.contains("XR_EXT_performance_settings"),
           let setLevel = proc("xrPerfSettingsSetPerformanceLevelEXT", PFN_xrPerfSettingsSetPerformanceLevelEXT.self) {
            _ = setLevel(session, XR_PERF_SETTINGS_DOMAIN_CPU_EXT, XR_PERF_SETTINGS_LEVEL_SUSTAINED_HIGH_EXT)
            _ = setLevel(session, XR_PERF_SETTINGS_DOMAIN_GPU_EXT, XR_PERF_SETTINGS_LEVEL_SUSTAINED_HIGH_EXT)
            print("xr: CPU/GPU performance level sustained high")
        }
        #if os(Android)
        // The frame thread (game tick + rendering) tells the runtime it is the app's main and render thread, so the
        // scheduler favours it over the chunk workers, sound synthesis and horizon sampling (questcheck: a worker-busy
        // moment could hold the tick off a core for ~3 ms).
        if exts.contains("XR_KHR_android_thread_settings"),
           let setThread = proc("xrSetAndroidApplicationThreadKHR", PFN_xrSetAndroidApplicationThreadKHR.self) {
            let tid = UInt32(gettid())
            let a = setThread(session, XR_ANDROID_THREAD_TYPE_APPLICATION_MAIN_KHR, tid)
            let r = setThread(session, XR_ANDROID_THREAD_TYPE_RENDERER_MAIN_KHR, tid)
            print("xr: frame thread \(tid) registered (main \(a.rawValue), renderer \(r.rawValue))")
        }
        #endif
    }

    // MARK: Frames

    struct Frame {
        var shouldRender: Bool
        var displayTime: XrTime
        var period: Double            // seconds per display frame
        var imageIndex: Int
    }

    // xrWaitFrame + xrBeginFrame + view poses; acquires the swapchain image when this frame is rendered.
    func beginFrame() throws -> Frame {
        var wi = XrFrameWaitInfo()
        wi.type = XR_TYPE_FRAME_WAIT_INFO
        var fs = XrFrameState()
        fs.type = XR_TYPE_FRAME_STATE
        try xrCheck(xrWaitFrame(session, &wi, &fs), "xrWaitFrame")
        var bi = XrFrameBeginInfo()
        bi.type = XR_TYPE_FRAME_BEGIN_INFO
        try xrCheck(xrBeginFrame(session, &bi), "xrBeginFrame")
        predictedTime = fs.predictedDisplayTime
        var f = Frame(shouldRender: fs.shouldRender != 0, displayTime: fs.predictedDisplayTime,
                      period: Double(fs.predictedDisplayPeriod) * 1e-9, imageIndex: -1)
        if f.shouldRender {
            var li = XrViewLocateInfo()
            li.type = XR_TYPE_VIEW_LOCATE_INFO
            li.viewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO
            li.displayTime = fs.predictedDisplayTime
            li.space = appSpace
            var vs = XrViewState()
            vs.type = XR_TYPE_VIEW_STATE
            var n: UInt32 = 2
            for i in 0..<2 { views[i].type = XR_TYPE_VIEW; views[i].next = nil }
            let r = xrLocateViews(session, &li, &vs, 2, &n, &views)
            let need = XrViewStateFlags(XR_VIEW_STATE_POSITION_VALID_BIT | XR_VIEW_STATE_ORIENTATION_VALID_BIT)
            if r.rawValue < 0 || vs.viewStateFlags & need != need { f.shouldRender = false }
        }
        if f.shouldRender {
            let p0 = views[0].pose, p1 = views[1].pose
            headPos = (V3(p0.position.x, p0.position.y, p0.position.z) + V3(p1.position.x, p1.position.y, p1.position.z)) * 0.5
            headRot = simd_quatf(ix: p0.orientation.x, iy: p0.orientation.y, iz: p0.orientation.z, r: p0.orientation.w)
            var ai = XrSwapchainImageAcquireInfo()
            ai.type = XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO
            var idx: UInt32 = 0
            try xrCheck(xrAcquireSwapchainImage(swapchain, &ai, &idx), "xrAcquireSwapchainImage")
            var wi2 = XrSwapchainImageWaitInfo()
            wi2.type = XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO
            wi2.timeout = XrDuration(Int64.max)
            try xrCheck(xrWaitSwapchainImage(swapchain, &wi2), "xrWaitSwapchainImage")
            f.imageIndex = Int(idx)
        }
        return f
    }

    // Releases the image (after the frame's commands were submitted) and ends the frame with the projection layer.
    func endFrame(_ f: Frame) throws {
        let a = PtrArena()
        var layers: [UnsafePointer<XrCompositionLayerBaseHeader>?] = []
        if f.shouldRender && f.imageIndex >= 0 {
            var ri = XrSwapchainImageReleaseInfo()
            ri.type = XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO
            try xrCheck(xrReleaseSwapchainImage(swapchain, &ri), "xrReleaseSwapchainImage")
            var pv = [XrCompositionLayerProjectionView](repeating: XrCompositionLayerProjectionView(), count: 2)
            for i in 0..<2 {
                pv[i].type = XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW
                pv[i].pose = views[i].pose
                pv[i].fov = views[i].fov
                pv[i].subImage.swapchain = swapchain
                pv[i].subImage.imageRect = XrRect2Di(offset: XrOffset2Di(x: 0, y: 0), extent: XrExtent2Di(width: Int32(width), height: Int32(height)))
                pv[i].subImage.imageArrayIndex = UInt32(i)
            }
            var layer = XrCompositionLayerProjection()
            layer.type = XR_TYPE_COMPOSITION_LAYER_PROJECTION
            layer.space = appSpace
            layer.viewCount = 2
            layer.views = a.array(pv)
            let lp = a.ptr(layer)
            layers.append(UnsafeRawPointer(lp).assumingMemoryBound(to: XrCompositionLayerBaseHeader.self))
        }
        var ei = XrFrameEndInfo()
        ei.type = XR_TYPE_FRAME_END_INFO
        ei.displayTime = f.displayTime
        ei.environmentBlendMode = XR_ENVIRONMENT_BLEND_MODE_OPAQUE
        ei.layerCount = UInt32(layers.count)
        try layers.withUnsafeBufferPointer { lp in
            ei.layers = lp.baseAddress
            try xrCheck(xrEndFrame(session, &ei), "xrEndFrame")
        }
    }

    // Per-eye field-of-view tangents of the located views.
    func fovTangents(_ i: Int) -> (Float, Float, Float, Float) {
        let f = views[i].fov
        return (tanf(f.angleLeft), tanf(f.angleRight), tanf(f.angleUp), tanf(f.angleDown))
    }
    func eyePose(_ i: Int) -> (V3, simd_quatf) {
        let p = views[i].pose
        return (V3(p.position.x, p.position.y, p.position.z), simd_quatf(ix: p.orientation.x, iy: p.orientation.y, iz: p.orientation.z, r: p.orientation.w))
    }

    func requestExit() {
        if let s = session { _ = xrRequestExitSession(s) }
    }
}
