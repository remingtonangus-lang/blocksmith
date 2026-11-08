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
    // P375 (view 24 on the Quest: 1,000-1,600 draws, each indirect batch is one vertex slab): 32 MB slabs there, so the
    // ~600 MB of meshes at view 24 sit in ~20 slabs and the batched terrain passes take ~20 draws each, not ~150.
    #if os(macOS)
    static let shared = MeshArena(slabSize: 4 << 20)
    #else
    static let shared = MeshArena(slabSize: 32 << 20)
    #endif
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
    // Ledger 43 (Nov 6): a new slab was made on the frame when the last one filled: 20.6 ms for one hand-over of
    // meshes on the host (--triptest, the Emberdeep's ground coming in), the Vulkan allocation plus the first write
    // into each of its fresh pages. The next slab is now made on a worker, its pages touched there, once the one in
    // use is three quarters carved (BS_SLABAHEAD=0: as before).
    static var ahead = ProcessInfo.processInfo.environment["BS_SLABAHEAD"] != "0"
    private var spare: MTLBuffer?
    private var spareAsked = false
    private(set) var spareUsed = 0
    // P415: each slab's bytes in live slices, so a slab nothing uses any more can be given back (trim).
    private var slabs: [ObjectIdentifier: (buf: MTLBuffer, live: Int)] = [:]
    private(set) var slabBytes = 0
    private(set) var slabCount = 0, slabMsWorst = 0.0, slabMsTotal = 0.0     // (P400 harness: new slabs and their cost)

    // Bytes in live slices (memsim: against slabBytes, how much of the slabs is used).
    var liveBytes: Int { lock.lock(); defer { lock.unlock() }; return slabs.values.reduce(0) { $0 + $1.live } }
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

    // (more: a second run of bytes copied straight after the first, so a section's near and far parts are not first
    // joined into a new array: World.apply's `opaque + farGround` was 1.6% of the worst-case soak's instructions)
    func alloc(_ device: MTLDevice, _ bytes: UnsafeRawBufferPointer, _ more: UnsafeRawBufferPointer? = nil) -> MeshSlice? {
        let n0 = bytes.count, n1 = more?.count ?? 0, n = n0 + n1
        if n == 0 { return nil }
        var cls = MeshArena.sizeClass(n)
        let size = MeshArena.sizes[cls]
        if size < n || size > slabSize / 4 {
            if n1 == 0 {
                guard let b = device.makeBuffer(bytes: bytes.baseAddress!, length: n, options: .storageModeShared) else { return nil }
                return MeshSlice(buffer: b, offset: 0, length: n, cls: -1, arena: self)
            }
            guard let b = device.makeBuffer(length: n, options: .storageModeShared) else { return nil }
            if n0 > 0 { memcpy(b.contents(), bytes.baseAddress!, n0) }
            memcpy(b.contents() + n0, more!.baseAddress!, n1)
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
        // P401: then a free slice of any larger class, cut to size; the rest goes back as smaller free slices (the
        // size classes drift as the land streams, and freed big slices sat unused while new slabs were made: 409 of
        // 1,344 MB of meshes free at the Ash Vault battle).
        if spot == nil && cls + 3 < MeshArena.sizes.count {
            for c in (cls + 3)..<MeshArena.sizes.count {
                guard let (b, off) = take(c, completed: completed) else { continue }
                spot = (b, off)
                var rest = MeshArena.sizes[c] - size, at = off + size
                while rest >= MeshArena.sizes[0] {
                    var k = MeshArena.sizeClass(rest)
                    if MeshArena.sizes[k] > rest { k -= 1 }
                    free[k].items.append((b, at, 0))
                    at += MeshArena.sizes[k]; rest -= MeshArena.sizes[k]
                }
                break
            }
        }
        if spot == nil {
            if slab == nil || bump + size > slabSize {
                let t0 = CFAbsoluteTimeGetCurrent()
                if let s = spare { slab = s; spare = nil; spareUsed += 1 }
                else { slab = device.makeBuffer(length: slabSize, options: .storageModeShared) }
                if let b = slab { slabs[ObjectIdentifier(b)] = (b, 0) }
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                slabCount += 1; slabMsWorst = max(slabMsWorst, ms); slabMsTotal += ms
                bump = 0
                slabBytes += slabSize
            }
            if let s = slab { spot = (s, bump); bump += size }
            if MeshArena.ahead && spare == nil && !spareAsked && bump > slabSize / 4 * 3 { spareAsked = true; makeSpare(device) }
        }
        if let sp = spot { slabs[ObjectIdentifier(sp.0)]?.live += MeshArena.sizes[cls] }
        lock.unlock()
        guard let (buf, off) = spot else { return nil }
        if n0 > 0 { memcpy(buf.contents() + off, bytes.baseAddress!, n0) }
        if n1 > 0 { memcpy(buf.contents() + off + n0, more!.baseAddress!, n1) }
        return MeshSlice(buffer: buf, offset: off, length: n, cls: cls, arena: self)
    }

    // (the next slab, made and its pages touched off the frame; called with the lock held)
    private func makeSpare(_ device: MTLDevice) {
        let size = slabSize
        DispatchQueue.global(qos: .utility).async { [self] in
            let b = device.makeBuffer(length: size, options: .storageModeShared)
            if let b = b {
                let p = b.contents()
                var i = 0
                while i < size { p.storeBytes(of: 0, toByteOffset: i, as: UInt8.self); i += 4096 }
            }
            lock.lock(); spare = b; spareAsked = false; lock.unlock()
        }
    }

    fileprivate func release(_ b: MTLBuffer, _ off: Int, _ cls: Int) {
        let f = MeshArena.fences
        // Frames up to `submitted` may still read it; if they have all completed it is free right away.
        let after = f.completed >= f.submitted ? 0 : f.submitted
        lock.lock()
        free[cls].items.append((b, off, after))
        slabs[ObjectIdentifier(b)]?.live -= MeshArena.sizes[cls]
        lock.unlock()
    }

    // P415: gives back every slab no live slice uses (and no frame in flight may still read): after the view distance
    // is lowered, the far meshes' memory goes back to the system instead of waiting in the free lists. Returns bytes.
    @discardableResult func trim() -> Int {
        let completed = MeshArena.fences.completed
        lock.lock(); defer { lock.unlock() }
        var empty = Set<ObjectIdentifier>()
        for (id, e) in slabs where e.live <= 0 && e.buf !== slab { empty.insert(id) }
        if empty.isEmpty { return 0 }
        for c in 0..<free.count {
            for i in free[c].head..<free[c].items.count where free[c].items[i].2 > completed {
                empty.remove(ObjectIdentifier(free[c].items[i].0))
            }
        }
        if empty.isEmpty { return 0 }
        for c in 0..<free.count where free[c].items.count > free[c].head {
            let kept = free[c].items[free[c].head...].filter { !empty.contains(ObjectIdentifier($0.0)) }
            free[c].items = Array(kept); free[c].head = 0
        }
        for id in empty { slabs.removeValue(forKey: id) }
        let bytes = empty.count * slabSize
        slabBytes -= bytes
        return bytes
    }
}
