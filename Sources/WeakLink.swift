import Foundation
#if !canImport(Darwin)
import Synchronization
#endif

// Item 8 (Nov 8): weak references that leave their target's reference counting on the fast path.
// A Swift `weak` reference gives its object a side table for life, and every retain and release of that object then
// takes the runtime's slow path. The worst-case soak's callgrind put 7% of all instructions there; BS_RCPROBE=1 named
// the objects: the World, the Game, the ShipManager and the ships with riders or turrets (RefcountProbe.swift).
//
// `@WeakLink var x: T?` reads like `weak var x: T?`, from any thread. The holder keeps a strong reference to the
// object's small LifeLink, which holds the object `unowned`: that keeps its allocation (not its life) while links
// exist, counted in the object's own reference-count word (no side table). A read takes a strong reference, then looks
// at that word: if the object's deinit has begun (its last reference let go, on any thread) it gives the reference back
// and returns nil, as a weak load does. A closure takes `[me = weakLink]` in place of `[weak self]`.
// (Nov 8: a first link cleared in the deinit raced the last release on a worker, build 241's suite crashed; the
// runtime's own swift_tryRetain is reserved and returned false through @_silgen_name, build 243; a lock round each
// read cost 3% of the worst-case soak, build 244.)
final class LifeLink {
    private unowned(safe) let keep: AnyObject       // (never read: it keeps the allocation while links exist)
    private let address: UnsafeMutableRawPointer
    init(_ o: AnyObject) { keep = o; address = Unmanaged.passUnretained(o).toOpaque() }
    // Ledger 128 (Nov 14): the read no longer counts itself onto an object whose deinit has begun. Before, it took its
    // reference first and looked second; when the object's deinit ended inside those few instructions (a worker put
    // aside by the scheduler between the two holds the window open for milliseconds) the runtime found a count it did
    // not expect on a dead object and stopped the game: "Object of class World deallocated with non-zero retain count
    // 2", which the full check run met about once in four (a world let go on the main thread while a worker's job read
    // its link). Now one compare-and-swap on the count word does both: only a word that says alive is raised.
    // BS_OLDWEAKLINK=1: as before. `--weaklinktest` makes and lets go objects under three readers.
    // (the word's layout is the 64-bit runtimes'; an object that got a side table, from a `weak` reference made to it
    // after all, still takes the old read below: no linked class has one)
    static var old = ProcessInfo.processInfo.environment["BS_OLDWEAKLINK"] == "1" || MemoryLayout<Int>.size != 8
    var object: AnyObject? {
        if !LifeLink.old {
            let word = address + MemoryLayout<Int>.size
            #if canImport(Darwin)
            var bits = word.load(as: UInt64.self)
            #else
            let atom = word.assumingMemoryBound(to: Atomic<UInt64>.self)
            var bits = atom.pointee.load(ordering: .relaxed)
            #endif
            // (bit 63: the count lives in a side table; a count near its top: both left to the runtime, below)
            while bits >> 63 == 0 && (bits >> 33) & 0x3FFF_FFFF < 0x3FFF_0000 {
                if (bits >> 32) & 1 != 0 { return nil }
                let more = bits &+ (1 << 33)            // (one more strong reference: the count starts at bit 33)
                #if canImport(Darwin)
                if lifeLinkSwap(Int64(bitPattern: bits), Int64(bitPattern: more), word) { return Unmanaged<AnyObject>.fromOpaque(address).takeRetainedValue() }
                bits = word.load(as: UInt64.self)
                #else
                let (done, now) = atom.pointee.compareExchange(expected: bits, desired: more, ordering: .sequentiallyConsistent)
                if done { return Unmanaged<AnyObject>.fromOpaque(address).takeRetainedValue() }
                bits = now
                #endif
            }
        }
        LifeLink.retain(address)                    // (not inlined: the look below can't move above it)
        // The 64-bit runtimes' inline count word: bit 32 = deinit begun (a test reads 0x100000003 in a deinit); bit
        // 63 = the count lives elsewhere (a side table: a `weak` reference was made to it after all), when this
        // can't tell and says alive. Taken after the last release, the bit is already set; taken before, there was
        // no last release.
        let bits = address.load(fromByteOffset: MemoryLayout<Int>.size, as: UInt64.self)
        if bits >> 63 == 0 && (bits >> 32) & 1 != 0 { Unmanaged<AnyObject>.fromOpaque(address).release(); return nil }
        return Unmanaged<AnyObject>.fromOpaque(address).takeRetainedValue()
    }
    // Has the object been given a side table (a `weak` reference made to it)? Then its links take the old read.
    static func sideTable(_ o: AnyObject) -> Bool {
        let bits = Unmanaged.passUnretained(o).toOpaque().load(fromByteOffset: MemoryLayout<Int>.size, as: UInt64.self)
        return bits >> 63 != 0 && UInt32(truncatingIfNeeded: bits) != UInt32.max       // (not an immortal one)
    }
    @inline(never) private static func retain(_ p: UnsafeMutableRawPointer) { _ = Unmanaged<AnyObject>.fromOpaque(p).retain() }
}

#if canImport(Darwin)
@_silgen_name("OSAtomicCompareAndSwap64Barrier") private func lifeLinkSwap(_ old: Int64, _ new: Int64, _ at: UnsafeMutableRawPointer) -> Bool
#endif

protocol LifeLinked: AnyObject { var lifeLink: LifeLink { get } }

@propertyWrapper struct WeakLink<T: LifeLinked> {
    private var link: LifeLink?
    init() { link = nil }
    init(wrappedValue: T?) { link = wrappedValue?.lifeLink }
    var wrappedValue: T? {
        get { guard let o = link?.object else { return nil }; return unsafeDowncast(o, to: T.self) }
        set { link = newValue?.lifeLink }
    }
}

extension LifeLinked {
    var weakLink: WeakLink<Self> { WeakLink(wrappedValue: self) }
}
