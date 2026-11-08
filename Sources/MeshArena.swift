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
    fileprivate let reserved: Int     // bytes held in the slab (>= length), 0 = dedicated buffer
    fileprivate let arena: MeshArena
    fileprivate init(buffer: MTLBuffer, offset: Int, length: Int, reserved: Int, arena: MeshArena) {
        self.buffer = buffer; self.offset = offset; self.length = length; self.reserved = reserved; self.arena = arena
    }
    deinit { if reserved > 0 { arena.release(buffer, offset, reserved) } }
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
    // Ledger 60 (item 10, Nov 8): free space was kept per size class and never joined again: a freed slice went back
    // as itself, and a big one was cut into small ones for good, so after two real-time hours 369 of the 608 MB of
    // slabs sat free in pieces too small for the meshes asked for, while new slabs were made. Each slab now keeps its
    // free runs by start and by end, so a freed slice joins the free runs on both sides of it; a run at the end of
    // the slab being carved goes back to it; the class lists only point at runs (an entry whose run has since been
    // joined or used is stale and skipped). BS_OLDARENA=1: as before (no joining).
    static var joins = ProcessInfo.processInfo.environment["BS_OLDARENA"] != "1"
    fileprivate final class Slab {
        let buf: MTLBuffer
        var live = 0                                   // bytes in live slices
        var starts: [Int: (len: Int, after: Int)] = [:]   // free runs: start -> length, frame that must complete first
        var ends: [Int: Int] = [:]                     // free runs: end -> start
        init(_ b: MTLBuffer) { buf = b }
    }
    // Per size class: FIFO of free runs at least that class's size (and under the next one's), from `head`.
    private struct FreeList { var items: [(Slab, Int, Int)] = []; var head = 0 }
    private var free = [FreeList](repeating: FreeList(), count: MeshArena.sizes.count)
    private var slab: Slab?
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
    private var slabs: [ObjectIdentifier: Slab] = [:]
    private(set) var slabBytes = 0
    private(set) var slabCount = 0, slabMsWorst = 0.0, slabMsTotal = 0.0     // (P400 harness: new slabs and their cost)

    // Bytes in live slices (memsim: against slabBytes, how much of the slabs is used).
    var liveBytes: Int { lock.lock(); defer { lock.unlock() }; return slabs.values.reduce(0) { $0 + $1.live } }
    // Bytes in free runs (fragmentation), for --bench and the memsim.
    var freeBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return slabs.values.reduce(0) { n, s in s.starts.values.reduce(n) { $0 + $1.len } }
    }
    // Slabs with no live slice (memsim: what the periodic trim can give back).
    var emptySlabs: Int { lock.lock(); defer { lock.unlock() }; return slabs.values.reduce(0) { $0 + ($1.live <= 0 && $1 !== slab ? 1 : 0) } }
    // Nov 8 (item 10, a real-time hour's memsim): slabs left wholly empty were given back only when the view was lowered,
    // so the mesh memory sat at its high mark (544 MB with 77-398 MB live). World.update trims every ~8 s in play,
    // keeping one empty slab. BS_SLABTRIM=0 for before.
    static var trimsInPlay = ProcessInfo.processInfo.environment["BS_SLABTRIM"] != "0"
    private(set) var trimmedInPlay = 0

    // The largest free run (memsim: whether the free bytes are in pieces).
    var largestFree: Int {
        lock.lock(); defer { lock.unlock() }
        return slabs.values.reduce(0) { n, s in s.starts.values.reduce(n) { max($0, $1.len) } }
    }

    // (the class a free run of n bytes is listed under: the largest size it holds)
    @inline(__always) private static func floorClass(_ n: Int) -> Int {
        let k = sizeClass(n)
        return sizes[k] > n ? k - 1 : k
    }

    // Lists a free run (caller holds the lock).
    private func addFree(_ s: Slab, _ at: Int, _ n: Int, after: Int) {
        s.starts[at] = (n, after); s.ends[at + n] = at
        if n >= MeshArena.sizes[0] { free[MeshArena.floorClass(n)].items.append((s, at, n)) }
    }

    // Pops a reusable free run of class c (caller holds the lock): (slab, start, length).
    private func take(_ c: Int, completed: Int) -> (Slab, Int, Int)? {
        var h = free[c].head
        var got: (Slab, Int, Int)?
        while h < free[c].items.count {
            let (s, at, n) = free[c].items[h]
            guard let r = s.starts[at], r.len == n else { h += 1; continue }     // (stale: joined or used since)
            if r.after > completed { break }
            h += 1
            s.starts[at] = nil; s.ends[at + n] = nil
            got = (s, at, n)
            break
        }
        free[c].head = h
        if free[c].head == free[c].items.count {
            free[c].items.removeAll(keepingCapacity: true); free[c].head = 0
        } else if free[c].head > 256 && free[c].head * 2 > free[c].items.count {
            free[c].items.removeFirst(free[c].head); free[c].head = 0
        }
        return got
    }

    // (more: a second run of bytes copied straight after the first, so a section's near and far parts are not first
    // joined into a new array: World.apply's `opaque + farGround` was 1.6% of the worst-case soak's instructions)
    func alloc(_ device: MTLDevice, _ bytes: UnsafeRawBufferPointer, _ more: UnsafeRawBufferPointer? = nil) -> MeshSlice? {
        let n0 = bytes.count, n1 = more?.count ?? 0, n = n0 + n1
        if n == 0 { return nil }
        let cls = MeshArena.sizeClass(n)
        let size = MeshArena.sizes[cls]
        if size < n || size > slabSize / 4 {
            if n1 == 0 {
                guard let b = device.makeBuffer(bytes: bytes.baseAddress!, length: n, options: .storageModeShared) else { return nil }
                return MeshSlice(buffer: b, offset: 0, length: n, reserved: 0, arena: self)
            }
            guard let b = device.makeBuffer(length: n, options: .storageModeShared) else { return nil }
            if n0 > 0 { memcpy(b.contents(), bytes.baseAddress!, n0) }
            memcpy(b.contents() + n0, more!.baseAddress!, n1)
            return MeshSlice(buffer: b, offset: 0, length: n, reserved: 0, arena: self)
        }
        let completed = MeshArena.fences.completed
        lock.lock()
        // A free run of this class or larger (the smallest class first); what is left of a larger run stays free.
        var spot: (Slab, Int)?
        var held = size
        for c in cls..<MeshArena.sizes.count {
            guard let (s, at, len) = take(c, completed: completed) else { continue }
            spot = (s, at)
            // (BS_OLDARENA: a run up to two classes larger is used whole, as the old free lists did)
            if !MeshArena.joins && c <= cls + 2 { held = len; break }
            let rest = len - held
            if rest >= 64 { addFree(s, at + held, rest, after: 0) } else { held = len }
            break
        }
        if spot == nil {
            if slab == nil || bump + size > slabSize {
                // (the tail of the slab given up is a free run too)
                if let s = slab, slabSize - bump >= 64 { addFree(s, bump, slabSize - bump, after: 0) }
                let t0 = CFAbsoluteTimeGetCurrent()
                var b: MTLBuffer?
                if let sp = spare { b = sp; spare = nil; spareUsed += 1 }
                else { b = device.makeBuffer(length: slabSize, options: .storageModeShared) }
                slab = b.map { Slab($0) }
                if let s = slab { slabs[ObjectIdentifier(s.buf)] = s }
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                slabCount += 1; slabMsWorst = max(slabMsWorst, ms); slabMsTotal += ms
                bump = 0
                slabBytes += slabSize
            }
            if let s = slab { spot = (s, bump); bump += size }
            if MeshArena.ahead && spare == nil && !spareAsked && bump > slabSize / 4 * 3 { spareAsked = true; makeSpare(device) }
        }
        if let sp = spot { sp.0.live += held }
        lock.unlock()
        guard let (s, off) = spot else { return nil }
        let buf = s.buf
        if n0 > 0 { memcpy(buf.contents() + off, bytes.baseAddress!, n0) }
        if n1 > 0 { memcpy(buf.contents() + off + n0, more!.baseAddress!, n1) }
        return MeshSlice(buffer: buf, offset: off, length: n, reserved: held, arena: self)
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

    fileprivate func release(_ b: MTLBuffer, _ off: Int, _ n: Int) {
        let f = MeshArena.fences
        // Frames up to `submitted` may still read it; if they have all completed it is free right away.
        let after = f.completed >= f.submitted ? 0 : f.submitted
        lock.lock(); defer { lock.unlock() }
        guard let s = slabs[ObjectIdentifier(b)] else { return }
        s.live -= n
        var at = off, len = n, aft = after
        if MeshArena.joins {
            // Joined with the free runs just before and just after it (the later of their frames to wait for).
            if let p = s.ends[at], let r = s.starts[p] {
                s.ends[at] = nil; s.starts[p] = nil
                at = p; len += r.len; aft = max(aft, r.after)
            }
            if let r = s.starts[at + len] {
                s.starts[at + len] = nil; s.ends[at + len + r.len] = nil
                len += r.len; aft = max(aft, r.after)
            }
            // A run ending where the slab being carved is carved to goes back to it (once no frame may read it).
            if s === slab && at + len == bump && aft <= f.completed { bump = at; return }
            addFree(s, at, len, after: aft)
        } else {
            s.starts[at] = (len, aft)
            free[MeshArena.floorClass(len)].items.append((s, at, len))
        }
    }

    // P415: gives back every slab no live slice uses (and no frame in flight may still read): after the view distance
    // is lowered, the far meshes' memory goes back to the system instead of waiting in the free lists. Returns bytes.
    // keep: how many empty slabs stay for the next meshes (the periodic trim in play keeps one, so walking back and
    // forth past a slab's worth of meshes does not make and free a 32 MB buffer each time).
    @discardableResult func trim(keep: Int = 0) -> Int {
        let completed = MeshArena.fences.completed
        lock.lock(); defer { lock.unlock() }
        var empty = Set<ObjectIdentifier>()
        for (id, s) in slabs where s.live <= 0 && s !== slab && !s.starts.values.contains(where: { $0.after > completed }) {
            empty.insert(id)
        }
        if empty.count <= keep { return 0 }
        for _ in 0..<keep { empty.removeFirst() }
        for c in 0..<free.count where free[c].items.count > free[c].head {
            let kept = free[c].items[free[c].head...].filter { !empty.contains(ObjectIdentifier($0.0.buf)) }
            free[c].items = Array(kept); free[c].head = 0
        }
        for id in empty { slabs.removeValue(forKey: id) }
        let bytes = empty.count * slabSize
        slabBytes -= bytes
        return bytes
    }
    func trimInPlay() { trimmedInPlay += trim(keep: 1) }
}
