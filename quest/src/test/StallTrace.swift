import Foundation
#if os(Linux)
import Glibc
// glibc's backtrace(3) (execinfo.h, not in the Glibc module)
@_silgen_name("backtrace") private func c_backtrace(_ buf: UnsafeMutablePointer<UnsafeMutableRawPointer?>, _ n: Int32) -> Int32
#endif

// Nov 11: where a slow frame's time went, on the host (Linux) checks. The VR fuzz's stall oracle says which frame was
// slow and which TickProf stage it was in; a stage is often a long list of systems (TownLaw.tick runs some thirty once
// a second), so this samples the frame's own call stack. A watcher thread looks every 2 ms and, once the frame's tick
// has run past `after` ms, signals the main thread, whose handler copies its stack (backtrace) into a fixed buffer:
// no allocation in the handler. A frame that ends under the budget throws its samples away; a slow frame keeps them.
// BS_STALLTRACE=FILE writes the kept stacks as offsets into the executable; quest/tools/stalltrace.py names them
// (llvm-symbolizer + swift-demangle) and adds them up by function. Off unless the variable is set.
enum StallTrace {
    static let path = ProcessInfo.processInfo.environment["BS_STALLTRACE"]
    static var on: Bool { armedOK }
    private static var armedOK = false

    #if os(Linux)
    static let depth = 48, cap = 6000                  // stacks kept (slow frames' samples), each up to `depth` frames
    static var buf: UnsafeMutablePointer<UnsafeMutableRawPointer?> = .allocate(capacity: 1)
    static var lens: UnsafeMutablePointer<Int32> = .allocate(capacity: 1)
    static var frameOf: UnsafeMutablePointer<Int32> = .allocate(capacity: 1)
    static var kept = 0            // samples kept from slow frames
    static var used = 0            // samples taken (kept + this frame's)
    static var startNs: UInt64 = 0 // the frame's start, 0 between frames (the watcher's flag)
    static var frame: Int32 = 0
    static var mainThread = pthread_self()
    static var after: UInt64 = 12_000_000              // ns into a frame before sampling starts
    static var afterNs: UInt64 { after }
    static var baseAddr: UInt = 0
    static var slowFrames: [(Int32, Double, String)] = []

    @inline(__always) static func nowNs() -> UInt64 {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        return UInt64(ts.tv_sec) * 1_000_000_000 + UInt64(ts.tv_nsec)
    }

    static func install() {
        guard let path, !armedOK else { return }
        _ = path
        buf = .allocate(capacity: depth * cap); buf.initialize(repeating: nil, count: depth * cap)
        lens = .allocate(capacity: cap); lens.initialize(repeating: 0, count: cap)
        frameOf = .allocate(capacity: cap); frameOf.initialize(repeating: 0, count: cap)
        if let a = ProcessInfo.processInfo.environment["BS_STALLTRACE_AFTER"], let ms = Double(a) { after = UInt64(ms * 1e6) }
        // The executable's load address (the first mapping of /proc/self/exe), so the offsets symbolize offline.
        if let maps = try? String(contentsOfFile: "/proc/self/maps", encoding: .utf8),
           let exe = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe") {
            for line in maps.split(separator: "\n") where line.hasSuffix(exe) {
                if let dash = line.firstIndex(of: "-") { baseAddr = UInt(line[line.startIndex..<dash], radix: 16) ?? 0 }
                break
            }
        }
        var warm = [UnsafeMutableRawPointer?](repeating: nil, count: 8)
        _ = c_backtrace(&warm, 8)                        // (the unwinder loads itself on first use, never in the handler)
        mainThread = pthread_self()
        used = 0; kept = 0; startNs = 0; frame = 0             // (every global the handler reads, made before it runs)
        _ = depth; _ = cap; _ = buf; _ = lens; _ = frameOf
        signal(SIGPROF) { _ in
            let i = StallTrace.used
            guard StallTrace.startNs != 0, i < StallTrace.cap else { return }
            StallTrace.lens[i] = c_backtrace(StallTrace.buf + i * StallTrace.depth, Int32(StallTrace.depth))
            StallTrace.frameOf[i] = StallTrace.frame
            StallTrace.used = i + 1
        }
        let t = Thread {
            while true {
                usleep(2000)
                let s = StallTrace.startNs
                if s != 0 && StallTrace.nowNs() - s > StallTrace.after { pthread_kill(StallTrace.mainThread, SIGPROF) }
            }
        }
        t.qualityOfService = .userInteractive
        t.start()
        armedOK = true
        print("stalltrace: sampling frames past \(after / 1_000_000) ms into \(path)")
    }

    @inline(__always) static func begin(_ f: Int) {
        guard armedOK else { return }
        frame = Int32(truncatingIfNeeded: f)
        startNs = nowNs()
    }

    // The frame is over: its samples are kept when it was slow (by the caller's own clock), else dropped.
    @inline(__always) static func end(slow: Bool, ms: Double, what: @autoclosure () -> String) {
        guard armedOK else { return }
        startNs = 0
        if slow && used > kept { kept = used; slowFrames.append((frame, ms, what())) } else { used = kept }
    }

    // Writes "frame F ms M what" lines, then one "s F off off off..." line a sample (offsets in hex from the load address).
    static func write() {
        guard armedOK, let path else { return }
        startNs = 0
        var out = "base \(String(baseAddr, radix: 16))\n"
        for (f, ms, w) in slowFrames { out += "frame \(f) \(String(format: "%.1f", ms)) \(w)\n" }
        for i in 0..<kept {
            out += "s \(frameOf[i])"
            for k in 0..<Int(lens[i]) {
                let a = UInt(bitPattern: buf[i * depth + k])
                out += " " + String(a &- baseAddr, radix: 16)
            }
            out += "\n"
        }
        try? out.write(toFile: path, atomically: true, encoding: .utf8)
        print("stalltrace: \(kept) samples from \(slowFrames.count) slow frames written to \(path)")
    }
    #else
    static func install() {}
    static let afterNs: UInt64 = 12_000_000
    @inline(__always) static func begin(_ f: Int) {}
    @inline(__always) static func end(slow: Bool, ms: Double, what: @autoclosure () -> String) {}
    static func write() {}
    #endif
}
