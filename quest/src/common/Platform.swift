import Foundation

// Platform pieces the shared game code expects from Darwin (quest/mac-only.txt lists the Mac files they replace).

#if !canImport(Darwin)
// CoreFoundation's clock (seconds since 2001-01-01), which swift-corelibs-foundation doesn't export.
@inline(__always) func CFAbsoluteTimeGetCurrent() -> Double {
    var ts = timespec()
    clock_gettime(CLOCK_REALTIME, &ts)
    return Double(ts.tv_sec) - 978_307_200 + Double(ts.tv_nsec) * 1e-9
}
#endif

// Command-line option value (App.swift on the Mac). The Quest app has no command line: always nil there.
func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

#if !canImport(Darwin)
// Weak object set (World.registry); swift-corelibs-foundation has no NSHashTable.
final class NSHashTable<T: AnyObject> {
    private struct Weak { weak var o: T? }
    private var items: [Weak] = []
    private let lock = NSLock()
    static func weakObjects() -> NSHashTable<T> { NSHashTable<T>() }
    func add(_ o: T?) {
        guard let o else { return }
        lock.lock(); items.removeAll { $0.o == nil }; items.append(Weak(o: o)); lock.unlock()
    }
    func remove(_ o: T?) {
        lock.lock(); items.removeAll { $0.o == nil || $0.o === o }; lock.unlock()
    }
    var allObjects: [T] { lock.lock(); defer { lock.unlock() }; return items.compactMap { $0.o } }
    var count: Int { allObjects.count }
}
#endif

#if !canImport(Darwin)
extension FileManager {
    // No Trash on Android/Linux: WorldStore.delete then removes the world for good.
    func trashItem(at url: URL, resultingItemURL: UnsafeMutablePointer<NSURL?>?) throws {
        throw CocoaError(.featureUnsupported)
    }
}
#endif

// Where saves and options live. On the Quest: the app's internal data folder (ANativeActivity.internalDataPath),
// set before anything touches UserDefaults or FileManager (swift-corelibs-foundation derives its folders from
// HOME / XDG_* when first used).
enum QuestPaths {
    static var root = ""
    static func setDataRoot(_ path: String) {
        root = path
        for (k, sub) in [("HOME", ""), ("XDG_DATA_HOME", "/data"), ("XDG_CONFIG_HOME", "/config"), ("XDG_CACHE_HOME", "/cache"), ("TMPDIR", "/tmp")] {
            let p = path + sub
            try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
            setenv(k, p, 1)
        }
        WorldStore.base = URL(fileURLWithPath: path + "/Worlds", isDirectory: true)
        try? FileManager.default.createDirectory(at: WorldStore.base, withIntermediateDirectories: true)
        WorldStore.useTrash = false
    }
}
