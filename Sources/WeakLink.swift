import Foundation

// Item 8 (Nov 8): weak references that leave their target's reference counting on the fast path.
// A Swift `weak` reference gives its object a side table for life, and every retain and release of that object then
// takes the runtime's slow path. The worst-case soak's callgrind put 7% of all instructions there; BS_RCPROBE=1 named
// the objects: the World, the Game, the ShipManager and the ships with riders or turrets (RefcountProbe.swift).
//
// `@WeakLink var x: T?` reads like `weak var x: T?`, from any thread: the holder keeps a strong reference to the
// object's small LifeLink, which holds the object `unowned` (its allocation, not its life: the unowned count sits in
// the object's own reference-count word, no side table) and hands out a strong reference only while the object is
// not going away (the runtime's swift_tryRetain, as a weak load does). A closure takes `[me = weakLink]` in place of
// `[weak self]`.
@_silgen_name("swift_tryRetain") private func swiftTryRetain(_ object: UnsafeMutableRawPointer) -> Bool

final class LifeLink {
    private unowned(safe) let keep: AnyObject       // (never read: it only keeps the allocation while links exist)
    private let address: UnsafeMutableRawPointer
    init(_ o: AnyObject) { keep = o; address = Unmanaged.passUnretained(o).toOpaque() }
    var object: AnyObject? {
        guard swiftTryRetain(address) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(address).takeRetainedValue()
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
