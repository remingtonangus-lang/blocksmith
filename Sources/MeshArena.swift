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
    // A freed slice waits this long before reuse: up to 3 frames still in flight on the GPU may be
    // reading the old mesh (reusing it at once showed as a one-frame flicker of garbage triangles).
    static let reuseDelay = 0.25
    private let lock = NSLock()
    private var device: MTLDevice?
    // Per size class: FIFO of freed slices (buffer, offset, time freed), consumed from `head`.
    private struct FreeList { var items: [(MTLBuffer, Int, Double)] = []; var head = 0 }
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

    func alloc(_ device: MTLDevice, _ bytes: UnsafeRawBufferPointer) -> MeshSlice? {
        let n = bytes.count
        if n == 0 { return nil }
        let cls = MeshArena.sizeClass(n)
        let size = MeshArena.sizes[cls]
        if size < n || size > slabSize / 4 {
            guard let b = device.makeBuffer(bytes: bytes.baseAddress!, length: n, options: .storageModeShared) else { return nil }
            return MeshSlice(buffer: b, offset: 0, length: n, cls: -1, arena: self)
        }
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        var spot: (MTLBuffer, Int)?
        let h = free[cls].head
        if h < free[cls].items.count && now - free[cls].items[h].2 > MeshArena.reuseDelay {
            let s = free[cls].items[h]
            spot = (s.0, s.1)
            free[cls].head = h + 1
            if free[cls].head > 256 && free[cls].head * 2 > free[cls].items.count {
                free[cls].items.removeFirst(free[cls].head)
                free[cls].head = 0
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
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        free[cls].items.append((b, off, now))
        lock.unlock()
    }
}
