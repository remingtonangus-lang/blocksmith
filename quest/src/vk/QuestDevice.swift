import Foundation
import Metal
import CVulkan

// MTLDevice for the shared code (World / MeshArena) backed by Vulkan: every "MTLBuffer" is a persistently mapped,
// host-coherent VkBuffer usable as a vertex, index or storage buffer, so section meshes written by the mesher on the
// worker threads are drawn straight from their slabs with no copies (the Quest's memory is unified).
final class QuestBuffer: MTLBuffer {
    let buf: VkBuf
    var label: String?
    init(_ b: VkBuf) { buf = b }
    // Metal keeps a buffer alive while a command buffer uses it; Vulkan doesn't: a dropped buffer (a replaced section
    // mesh with its own buffer, a closed world) waits for the frames that may still read it.
    deinit { QuestGraveyard.retire(buf) }
    var length: Int { buf.size }
    func contents() -> UnsafeMutableRawPointer { buf.mapped! }
    var vkBuffer: VkBuffer { buf.buffer }
}

final class QuestDevice: MTLDevice {
    let ctx: VkContext
    private let lock = NSLock()
    private(set) var allocatedBytes = 0
    init(_ ctx: VkContext) { self.ctx = ctx }
    var name: String { ctx.deviceName }

    func makeBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer? {
        let usage = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.rawValue | VK_BUFFER_USAGE_INDEX_BUFFER_BIT.rawValue
            | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT.rawValue | VK_BUFFER_USAGE_TRANSFER_SRC_BIT.rawValue
        guard let b = try? VkBuf(ctx, size: length, usage: usage, host: true) else { return nil }
        lock.lock(); allocatedBytes += length; lock.unlock()
        return QuestBuffer(b)
    }
}

// Vulkan objects released by the game while frames in flight may still use them; freed once those frames completed.
enum QuestGraveyard {
    private static let lock = NSLock()
    private static var items: [(AnyObject, Int)] = []
    private static var submitted = 0, completed = 0

    static func retire(_ o: AnyObject) {
        lock.lock()
        if completed >= submitted { lock.unlock(); return }          // nothing in flight: free now (o dies here)
        items.append((o, submitted))
        lock.unlock()
    }
    static func frameSubmitted(_ n: Int) { lock.lock(); submitted = max(submitted, n); lock.unlock() }
    static func frameCompleted(_ n: Int) {
        lock.lock()
        completed = max(completed, n)
        var keep: [(AnyObject, Int)] = []
        var drop: [AnyObject] = []
        for it in items { if it.1 <= completed { drop.append(it.0) } else { keep.append(it) } }
        items = keep
        lock.unlock()
        _ = drop                       // released here, outside the lock
    }
    static var pending: Int { lock.lock(); defer { lock.unlock() }; return items.count }
}
