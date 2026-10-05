import Foundation

// Heap allocations made by the calling thread so far, when questcheck runs with quest/tools/alloccount.c preloaded
// (nil otherwise): the hot-path budget is no per-frame allocations, and this counts them per tick and per frame.
enum AllocCount {
    private typealias Fn = @convention(c) () -> Int
    private static let fn: Fn? = dlsym(UnsafeMutableRawPointer(bitPattern: 0), "bs_alloc_count").map { unsafeBitCast($0, to: Fn.self) }
    static var now: Int? { fn?() }
}
