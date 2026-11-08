import Foundation

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
    var object: AnyObject? {
        LifeLink.retain(address)                    // (not inlined: the look below can't move above it)
        // The 64-bit runtimes' inline count word: bit 32 = deinit begun (a test reads 0x100000003 in a deinit); bit
        // 63 = the count lives elsewhere (a side table: a `weak` reference was made to it after all), when this
        // can't tell and says alive. Taken after the last release, the bit is already set; taken before, there was
        // no last release.
        let bits = address.load(fromByteOffset: MemoryLayout<Int>.size, as: UInt64.self)
        if bits >> 63 == 0 && (bits >> 32) & 1 != 0 { Unmanaged<AnyObject>.fromOpaque(address).release(); return nil }
        return Unmanaged<AnyObject>.fromOpaque(address).takeRetainedValue()
    }
    @inline(never) private static func retain(_ p: UnsafeMutableRawPointer) { _ = Unmanaged<AnyObject>.fromOpaque(p).retain() }
}

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
