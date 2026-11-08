import Foundation

// Item 8 (Nov 8): weak references that leave their target's reference counting on the fast path.
// A Swift `weak` reference gives its object a side table for life, and every retain and release of that object then
// takes the runtime's slow path. The worst-case soak's callgrind put 7% of all instructions there; BS_RCPROBE=1 named
// the objects: the World, the Game, the ShipManager and the ships with riders or turrets (RefcountProbe.swift).
//
// `@WeakLink var x: T?` reads like `weak var x: T?`, from any thread. The holder keeps a strong reference to the
// object's small LifeLink; the object clears the link first thing in its deinit. A read takes the link's lock, takes a
// strong reference and then looks at the object's reference-count word: if the object had already begun going away
// (its last reference let go on another thread, before its deinit reached the link) the read gives the reference back
// and returns nil, as a weak load does. The deinit's clear waits for a read under way, so the object's memory is still
// there while a read looks at it. A closure takes `[me = weakLink]` in place of `[weak self]`.
final class LifeLink {
    private let lock = NSLock()
    private var target: UnsafeMutableRawPointer?        // (the object's address, not a reference)
    init(_ o: AnyObject) { target = Unmanaged.passUnretained(o).toOpaque() }
    var object: AnyObject? {
        lock.lock(); defer { lock.unlock() }
        guard let p = target else { return nil }
        return LifeLink.take(p)
    }
    // (the object's deinit)
    func clear() { lock.lock(); target = nil; lock.unlock() }

    // Takes a strong reference, then looks at the 64-bit runtimes' inline reference-count word: bit 32 = deinit begun
    // (the reference is given back: nil); bit 63 = the count lives elsewhere (a side table: a `weak` reference was made
    // to it after all), when this can't tell and says alive. Taken after the last release, the bit is already set;
    // taken before, there was no last release. (Never inlined or optimized: the look stays after the take.)
    @inline(never) @_optimize(none)
    private static func take(_ p: UnsafeMutableRawPointer) -> AnyObject? {
        let u = Unmanaged<AnyObject>.fromOpaque(p)
        _ = u.retain()
        let bits = p.load(fromByteOffset: MemoryLayout<Int>.size, as: UInt64.self)
        if bits >> 63 == 0 && (bits >> 32) & 1 != 0 { u.release(); return nil }
        return u.takeRetainedValue()
    }
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
