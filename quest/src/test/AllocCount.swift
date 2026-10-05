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

    private static let traceDir = ProcessInfo.processInfo.environment["BS_ALLOC_TRACE"]
    static func traced<R>(_ name: String, _ body: () throws -> R) rethrows -> R {
        try counted(name, body).0
    }
    // The body's result and how many allocations it made (the trace dump's own excluded).
    private static func counted<R>(_ name: String, _ body: () throws -> R) rethrows -> (R, Int) {
        let a = now ?? 0
        guard let dir = traceDir, let arm, let dump else { let r = try body(); return (r, (now ?? 0) - a) }
        arm(1)
        let r = try body()
        let n = (now ?? 0) - a
        arm(0)
        dump(dir + "/" + name + ".trace")
        return (r, n)
    }

    // Per-name totals of allocations (count, calls) for a report: measure("x") { ... } then report().
    private static var totals: [String: (Int, Int)] = [:]
    static func measure<R>(_ name: String, _ body: () throws -> R) rethrows -> R {
        guard now != nil else { return try body() }
        let (r, n) = try counted(name, body)
        let t = totals[name] ?? (0, 0)
        totals[name] = (t.0 + n, t.1 + 1)
        return r
    }
    static func report(_ title: String) {
        guard !totals.isEmpty else { return }
        print(title + ": " + totals.sorted { $0.key < $1.key }.map { String(format: "%@ %.1f/call (%d calls)", $0.key, Double($0.value.0) / Double(max(1, $0.value.1)), $0.value.1) }.joined(separator: ", "))
        totals.removeAll()
    }
}
