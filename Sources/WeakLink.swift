import Foundation

// Item 8 (Nov 8): weak references that leave their target's reference counting on the fast path.
// A Swift `weak` reference gives its object a side table for life, and every retain and release of that object then
// takes the runtime's slow path. The worst-case soak's callgrind put 7% of all instructions there; BS_RCPROBE=1 named
// the objects: the World, the Game, the ShipManager and the ships with riders or turrets (RefcountProbe.swift).
//
// `@WeakLink var x: T?` reads like `weak var x: T?`: the holder keeps a strong reference to the object's small LifeLink,
// the object clears it first thing in its deinit, and the holder reads nil from then on. Clearing is not atomic with
// the last release, so it is for objects read on the thread that lets them go (the game thread); a worker's job
// reaches the World or the ShipManager through a JobGate instead.
final class LifeLink {
    unowned(unsafe) var object: AnyObject?
    init(_ o: AnyObject) { object = o }
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
    // For a closure: `{ [me = weakLink] in me.wrappedValue?.... }` in place of `[weak self]`.
    var weakLink: WeakLink<Self> { WeakLink(wrappedValue: self) }
}

// A worker's job that uses an object without holding it (`[unowned(unsafe) self, gate]`) runs between enter() and
// leave(); the object's deinit calls close() first, which turns new jobs away and waits for the ones running. (A job
// that itself let the object go would deinit it on its own thread: close() does not wait for that thread's own jobs.)
final class JobGate {
    private let cond = NSCondition()
    private var closed = false
    private var running: [UInt: Int] = [:]          // jobs inside, by thread
    private var inside = 0
    private static func me() -> UInt { UInt(bitPattern: Unmanaged.passUnretained(Thread.current).toOpaque()) }

    func enter() -> Bool {
        cond.lock(); defer { cond.unlock() }
        if closed { return false }
        inside += 1
        running[JobGate.me(), default: 0] += 1
        return true
    }
    func leave() {
        cond.lock()
        inside -= 1
        let t = JobGate.me()
        if let n = running[t], n > 1 { running[t] = n - 1 } else { running[t] = nil }
        cond.broadcast()
        cond.unlock()
    }
    func close() {
        cond.lock()
        closed = true
        let mine = running[JobGate.me()] ?? 0
        while inside > mine { cond.wait() }
        cond.unlock()
    }
}
