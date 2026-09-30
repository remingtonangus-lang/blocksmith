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
    fileprivate let cls: Int          // size class (log2), -1 = dedicated buffer
    init(buffer: MTLBuffer, offset: Int, length: Int, cls: Int) {
        self.buffer = buffer; self.offset = offset; self.length = length; self.cls = cls
    }
    deinit { if cls >= 0 { MeshArena.shared.release(buffer, offset, cls) } }
}

final class MeshArena {
    static let shared = MeshArena()
    static let slabSize = 4 << 20
    static let minClass = 8                          // 256 bytes
    private let lock = NSLock()
    private var device: MTLDevice?
    private var free: [Int: [(MTLBuffer, Int)]] = [:]
    private var slab: MTLBuffer?
    private var bump = 0
    private(set) var slabBytes = 0

    func alloc(_ device: MTLDevice, _ bytes: UnsafeRawBufferPointer) -> MeshSlice? {
        let n = bytes.count
        if n == 0 { return nil }
        var cls = MeshArena.minClass
        while (1 << cls) < n { cls += 1 }
        if (1 << cls) > MeshArena.slabSize / 4 {
            guard let b = device.makeBuffer(bytes: bytes.baseAddress!, length: n, options: .storageModeShared) else { return nil }
            return MeshSlice(buffer: b, offset: 0, length: n, cls: -1)
        }
        lock.lock()
        var spot: (MTLBuffer, Int)?
        if var list = free[cls], let s = list.popLast() { free[cls] = list; spot = s }
        if spot == nil {
            let size = 1 << cls
            if slab == nil || bump + size > MeshArena.slabSize {
                slab = device.makeBuffer(length: MeshArena.slabSize, options: .storageModeShared)
                bump = 0
                slabBytes += MeshArena.slabSize
            }
            if let s = slab { spot = (s, bump); bump += size }
        }
        lock.unlock()
        guard let (buf, off) = spot else { return nil }
        memcpy(buf.contents() + off, bytes.baseAddress!, n)
        return MeshSlice(buffer: buf, offset: off, length: n, cls: cls)
    }

    fileprivate func release(_ b: MTLBuffer, _ off: Int, _ cls: Int) {
        lock.lock()
        free[cls, default: []].append((b, off))
        lock.unlock()
    }
}
