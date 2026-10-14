import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Darwin)
import Darwin
#endif

// S5 (store readiness): the paid-app entitlement check through the headset's platform library. The library is loaded
// at run time (dlopen), so nothing links against it and builds without it still work. Off until the store app ID
// exists: set `appID`, add the platform loader library to the APK, and the check runs at launch. A user who does not
// own the app sees a message and the app closes; a check that cannot run (library missing, offline) lets play go on.
enum QuestEntitlement {
    static let appID: String? = nil                    // the store's app ID, once the app is registered
    private(set) static var denied = false
    private(set) static var checked = false
    private static var popMessage: (@convention(c) () -> UnsafeMutableRawPointer?)?
    private static var messageType: (@convention(c) (UnsafeMutableRawPointer?) -> UInt32)?
    private static var isError: (@convention(c) (UnsafeMutableRawPointer?) -> Bool)?
    private static var freeMessage: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
    static let entitlementMessage: UInt32 = 0x186B58B1   // the platform's "is the viewer entitled" reply

    // `vm`: the JavaVM, `activity`: the activity object (as XRPlatform receives them).
    static func start(vm: UnsafeMutableRawPointer?, activity: UnsafeMutableRawPointer?) {
        guard let id = appID, let vm, let activity else { return }
        guard let lib = dlopen("libovrplatformloader.so", RTLD_NOW) else { print("entitlement: platform library missing"); checked = true; return }
        typealias Init = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32
        typealias Req = @convention(c) () -> UInt64
        guard let i = dlsym(lib, "ovr_PlatformInitializeAndroid"), let r = dlsym(lib, "ovr_Entitlement_GetIsViewerEntitled"),
              let p = dlsym(lib, "ovr_PopMessage"), let t = dlsym(lib, "ovr_Message_GetType"),
              let e = dlsym(lib, "ovr_Message_IsError"), let f = dlsym(lib, "ovr_FreeMessage") else { checked = true; return }
        popMessage = unsafeBitCast(p, to: (@convention(c) () -> UnsafeMutableRawPointer?).self)
        messageType = unsafeBitCast(t, to: (@convention(c) (UnsafeMutableRawPointer?) -> UInt32).self)
        isError = unsafeBitCast(e, to: (@convention(c) (UnsafeMutableRawPointer?) -> Bool).self)
        freeMessage = unsafeBitCast(f, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
        // This thread's JNIEnv: JavaVM is a pointer to the invoke table; AttachCurrentThread is its fifth entry.
        typealias Attach = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?, UnsafeMutableRawPointer?) -> Int32
        let table = vm.assumingMemoryBound(to: UnsafePointer<UnsafeRawPointer?>.self).pointee
        guard let attachPtr = table[4] else { checked = true; return }
        var env: UnsafeMutableRawPointer?
        _ = unsafeBitCast(attachPtr, to: Attach.self)(vm, &env, nil)
        let rc = id.withCString { unsafeBitCast(i, to: Init.self)($0, activity, env) }
        if rc != 0 { print("entitlement: platform init failed (\(rc))"); checked = true; return }
        _ = unsafeBitCast(r, to: Req.self)()
    }

    // Once a frame until the reply arrives.
    static func poll() {
        guard !checked, let pop = popMessage else { return }
        while let m = pop() {
            if messageType?(m) == entitlementMessage {
                checked = true
                denied = isError?(m) ?? false
                print("entitlement: \(denied ? "not entitled" : "entitled")")
            }
            freeMessage?(m)
        }
    }
}
