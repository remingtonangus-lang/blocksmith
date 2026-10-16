import Foundation
import Metal

// Section meshes are small (often a few hundred bytes) and there are ~100k of them at render
// distance 24; one MTLBuffer each costs at least a 16 KB page, which was most of the resident
// memory. Meshes are carved instead from 4 MB shared slabs in power-of-two size classes with
// free lists; a slice returns itself to the arena when its section drops it.
final class MeshSlice {
    let buffer: MTLBuffer
    let offset: Int
    let length: Int
    fileprivate let cls: Int          // index into MeshArena.sizes, -1 = dedicated buffer
    fileprivate let arena: MeshArena
    fileprivate init(buffer: MTLBuffer, offset: Int, length: Int, cls: Int, arena: MeshArena) {
        self.buffer = buffer; self.offset = offset; self.length = length; self.cls = cls; self.arena = arena
    }
    deinit { if cls >= 0 { arena.release(buffer, offset, cls) } }
}

final class MeshArena {
    static let shared = MeshArena(slabSize: 4 << 20)
    // Chunk tint tables (3 KB each) live in their own big slab so the renderer binds one tint buffer
    // for all sections and passes each chunk's offset in its draw record.
    static let tints = MeshArena(slabSize: 16 << 20)
    let slabSize: Int
    init(slabSize: Int) { self.slabSize = slabSize }
    // Size classes in quarter steps between powers of two (256, 320, 384, 448, 512, 640, ...): at most
    // ~20% slack per slice instead of up to 50% with plain powers of two. All are multiples of 64 bytes.
    static let sizes: [Int] = (8..<24).flatMap { e in [4, 5, 6, 7].map { $0 << (e - 2) } }
    @inline(__always) static func sizeClass(_ n: Int) -> Int {
        var lo = 0, hi = sizes.count - 1
        while lo < hi { let mid = (lo + hi) / 2; if sizes[mid] >= n { hi = mid } else { lo = mid + 1 } }
        return lo
    }

    // GPU frame fences. A slice freed while frame N (the last one submitted) may still be drawing it is
    // reused only once frame N has completed; with nothing in flight (headless, or the GPU caught up) it
    // is reusable at once. (Reusing freed meshes unconditionally could overwrite a mesh an in-flight frame
    // was still drawing; a fixed time delay instead made bursts of edits allocate fresh slabs.)
    private static let fenceLock = NSLock()
    private static var submittedFrames = 0
    private static var completedFrames = 0
    // Call right before committing a frame's command buffer; pass the result to frameCompleted().
    static func frameSubmitted() -> Int {
        fenceLock.lock(); defer { fenceLock.unlock() }
        submittedFrames += 1
        return submittedFrames
    }
    static func frameCompleted(_ n: Int) {
        fenceLock.lock(); completedFrames = max(completedFrames, n); fenceLock.unlock()
    }
    private static var fences: (submitted: Int, completed: Int) {
        fenceLock.lock(); defer { fenceLock.unlock() }
        return (submittedFrames, completedFrames)
    }

    private let lock = NSLock()
    // Per size class: FIFO of freed slices (buffer, offset, frame that must complete first), from `head`.
    private struct FreeList { var items: [(MTLBuffer, Int, Int)] = []; var head = 0 }
    private var free = [FreeList](repeating: FreeList(), count: MeshArena.sizes.count)
    private var slab: MTLBuffer?
    private var bump = 0
    private(set) var slabBytes = 0

    // Bytes sitting in free lists (fragmentation), for --bench.
    var freeBytes: Int {
        lock.lock(); defer { lock.unlock() }
        var n = 0
        for c in 0..<free.count { n += (free[c].items.count - free[c].head) * MeshArena.sizes[c] }
        return n
    }

    // Pops a reusable slice of class c (caller holds the lock).
    private func take(_ c: Int, completed: Int) -> (MTLBuffer, Int)? {
        let h = free[c].head
        guard h < free[c].items.count, free[c].items[h].2 <= completed else { return nil }
        let s = free[c].items[h]
        free[c].head = h + 1
        if free[c].head == free[c].items.count {
            free[c].items.removeAll(keepingCapacity: true); free[c].head = 0
        } else if free[c].head > 256 && free[c].head * 2 > free[c].items.count {
            free[c].items.removeFirst(free[c].head); free[c].head = 0
        }
        return (s.0, s.1)
    }

    func alloc(_ device: MTLDevice, _ bytes: UnsafeRawBufferPointer) -> MeshSlice? {
        let n = bytes.count
        if n == 0 { return nil }
        var cls = MeshArena.sizeClass(n)
        let size = MeshArena.sizes[cls]
        if size < n || size > slabSize / 4 {
            guard let b = device.makeBuffer(bytes: bytes.baseAddress!, length: n, options: .storageModeShared) else { return nil }
            return MeshSlice(buffer: b, offset: 0, length: n, cls: -1, arena: self)
        }
        let completed = MeshArena.fences.completed
        lock.lock()
        // Own class first, then up to two classes larger (<= ~50% slack) before carving new space.
        var spot = take(cls, completed: completed)
        if spot == nil {
            for c in (cls + 1)...min(cls + 2, MeshArena.sizes.count - 1) {
                if let s = take(c, completed: completed) { spot = s; cls = c; break }
            }
        }
        if spot == nil {
            if slab == nil || bump + size > slabSize {
                slab = device.makeBuffer(length: slabSize, options: .storageModeShared)
                bump = 0
                slabBytes += slabSize
            }
            if let s = slab { spot = (s, bump); bump += size }
        }
        lock.unlock()
        guard let (buf, off) = spot else { return nil }
        memcpy(buf.contents() + off, bytes.baseAddress!, n)
        return MeshSlice(buffer: buf, offset: off, length: n, cls: cls, arena: self)
    }

    fileprivate func release(_ b: MTLBuffer, _ off: Int, _ cls: Int) {
        let f = MeshArena.fences
        // Frames up to `submitted` may still read it; if they have all completed it is free right away.
        let after = f.completed >= f.submitted ? 0 : f.submitted
        lock.lock()
        free[cls].items.append((b, off, after))
        lock.unlock()
    }
}
