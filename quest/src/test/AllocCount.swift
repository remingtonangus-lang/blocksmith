import Foundation

// Heap allocations made by the calling thread so far, when questcheck runs with quest/tools/alloccount.c preloaded
// (nil otherwise): the hot-path budget is no per-frame allocations, and this counts them per tick and per frame.
// With BS_ALLOC_TRACE=<dir> set, traced() records the call stack of every allocation in its body to <dir>/<name>.trace
// (symbolized by quest/tools/alloctrace.py).
enum AllocCount {
    private typealias Count = @convention(c) () -> Int
    private typealias Arm = @convention(c) (Int32) -> Void
    private typealias Dump = @convention(c) (UnsafePointer<CChar>) -> Void
    private static func sym<T>(_ name: String, _ t: T.Type) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: 0), name).map { unsafeBitCast($0, to: T.self) }
    }
    private static let count = sym("bs_alloc_count", Count.self)
    private static let arm = sym("bs_alloc_arm", Arm.self)
    private static let dump = sym("bs_alloc_dump", Dump.self)
    static var now: Int? { count?() }

    static func traced<R>(_ name: String, _ body: () throws -> R) rethrows -> R {
        guard let dir = ProcessInfo.processInfo.environment["BS_ALLOC_TRACE"], let arm, let dump else { return try body() }
        arm(1)
        defer { arm(0); dump(dir + "/" + name + ".trace") }
        return try body()
    }
}
