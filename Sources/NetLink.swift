import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Darwin)
import Darwin
#endif

// The co-op network layer (backlog C14): plain POSIX sockets, no third-party code. A TCP link carries framed messages
// (u32 length, u8 type, payload) in both directions: a reader thread fills an inbox, a writer thread drains an outbox,
// and the game thread only ever touches the two locked queues (poll / send), so a slow network never stalls a frame.
// LAN discovery is a UDP beacon: the host broadcasts "BSMITH <port> <world>" once a second; a joining headset listens.

enum NetSock {
    #if canImport(Glibc)
    static let stream = Int32(SOCK_STREAM.rawValue), dgram = Int32(SOCK_DGRAM.rawValue)
    #else
    static let stream = SOCK_STREAM, dgram = SOCK_DGRAM
    #endif
    static let gamePort: UInt16 = 27515
    static let beaconPort: UInt16 = 27516

    static func addr(_ ip: UInt32, _ port: UInt16) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr.s_addr = ip.bigEndian
        return a
    }
    static func withSockaddr<T>(_ a: inout sockaddr_in, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: &a) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    }
    static func setOpt(_ fd: Int32, _ level: Int32, _ name: Int32, _ v: Int32 = 1) {
        var on = v
        _ = setsockopt(fd, level, name, &on, socklen_t(MemoryLayout<Int32>.size))
    }
    static func noDelay(_ fd: Int32) { setOpt(fd, Int32(IPPROTO_TCP), TCP_NODELAY) }
    static func noSigPipe(_ fd: Int32) {
        #if canImport(Darwin)
        setOpt(fd, SOL_SOCKET, SO_NOSIGPIPE)
        #endif
    }
    static func timeout(_ fd: Int32, seconds: Double) {
        var tv = timeval()
        tv.tv_sec = .init(seconds.rounded(.down))
        tv.tv_usec = .init((seconds - seconds.rounded(.down)) * 1_000_000)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    // A listening TCP socket on the game port (all interfaces), or nil.
    static func listen(port: UInt16) -> Int32? {
        let fd = socket(AF_INET, stream, 0)
        guard fd >= 0 else { return nil }
        setOpt(fd, SOL_SOCKET, SO_REUSEADDR)
        var a = addr(0, port)
        let ok = withSockaddr(&a) { bind(fd, $0, $1) } == 0
        guard ok, Glibc_listen(fd, 2) == 0 else { close(fd); return nil }
        timeout(fd, seconds: 0.25)                 // accept wakes four times a second (to notice a stop)
        return fd
    }

    static func accept(_ fd: Int32) -> Int32? { let c = Glibc_accept(fd); return c >= 0 ? c : nil }
    static func close(_ fd: Int32) { sysClose(fd) }

    // This device's address on the local network (the first IPv4 interface that isn't loopback), for the host to show.
    static func localIP() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            defer { p = a.pointee.ifa_next }
            guard let sa = a.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            if ip >> 24 == 127 { continue }
            return "\(ip >> 24 & 255).\(ip >> 16 & 255).\(ip >> 8 & 255).\(ip & 255)"
        }
        return nil
    }

    // Connects to ip:port (dotted quad), or nil.
    static func connect(_ host: String, port: UInt16) -> Int32? {
        var parts = host.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return nil }
        let ip = parts.reduce(0) { $0 << 8 | $1 }
        parts.removeAll()
        let fd = socket(AF_INET, stream, 0)
        guard fd >= 0 else { return nil }
        var a = addr(ip, port)
        guard withSockaddr(&a, { Glibc_connect(fd, $0, $1) }) == 0 else { close(fd); return nil }
        return fd
    }

    // The host's beacon: a broadcast UDP socket.
    static func beaconSocket() -> Int32? {
        let fd = socket(AF_INET, dgram, 0)
        guard fd >= 0 else { return nil }
        setOpt(fd, SOL_SOCKET, SO_BROADCAST)
        return fd
    }
    static func beacon(_ fd: Int32, _ text: String) {
        var a = addr(0xFFFF_FFFF, beaconPort)
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { b in withSockaddr(&a) { sendto(fd, b.baseAddress!, b.count, 0, $0, $1) } }
    }

    // Listens for beacons for up to `seconds`: (host ip, game port, world name) of each host heard.
    static func discover(seconds: Double) -> [(ip: String, port: UInt16, world: String)] {
        let fd = socket(AF_INET, dgram, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        setOpt(fd, SOL_SOCKET, SO_REUSEADDR)
        var a = addr(0, beaconPort)
        guard withSockaddr(&a, { bind(fd, $0, $1) }) == 0 else { return [] }
        timeout(fd, seconds: 0.2)
        var found: [(String, UInt16, String)] = []
        let end = Date().addingTimeInterval(seconds)
        var buf = [UInt8](repeating: 0, count: 512)
        while Date() < end {
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = buf.withUnsafeMutableBytes { b in
                withUnsafeMutablePointer(to: &from) { p in
                    p.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, b.baseAddress!, b.count, 0, $0, &len) }
                }
            }
            guard n > 0 else { continue }
            let text = String(decoding: buf[0..<n], as: UTF8.self)
            let f = text.split(separator: " ", maxSplits: 2).map(String.init)
            guard f.count >= 2, f[0] == "BSMITH", let port = UInt16(f[1]) else { continue }
            let ip = UInt32(bigEndian: from.sin_addr.s_addr)
            let ipText = "\(ip >> 24 & 255).\(ip >> 16 & 255).\(ip >> 8 & 255).\(ip & 255)"
            if !found.contains(where: { $0.0 == ipText }) { found.append((ipText, port, f.count > 2 ? f[2] : "?")) }
        }
        return found
    }
}

// Renamed libc entry points (Swift's own `listen` / `connect` names would shadow them inside NetSock).
@inline(__always) private func Glibc_listen(_ fd: Int32, _ n: Int32) -> Int32 { listen(fd, n) }
@inline(__always) private func Glibc_connect(_ fd: Int32, _ a: UnsafePointer<sockaddr>, _ l: socklen_t) -> Int32 { connect(fd, a, l) }
@inline(__always) private func sysClose(_ fd: Int32) { _ = close(fd) }
@inline(__always) private func Glibc_accept(_ fd: Int32) -> Int32 { accept(fd, nil, nil) }
@inline(__always) private func sysSend(_ fd: Int32, _ p: UnsafeRawPointer, _ n: Int, _ flags: Int32) -> Int { send(fd, p, n, flags) }

// One framed, threaded TCP connection.
final class NetLink {
    private let fd: Int32
    private let lock = NSLock()
    private let wake = NSCondition()
    private var inbox: [(UInt8, [UInt8])] = []
    private var outbox: [[UInt8]] = []
    private var outBytes = 0
    private(set) var closed = false
    private(set) var bytesIn = 0, bytesOut = 0
    static let maxFrame = 8 << 20

    init(fd: Int32) {
        self.fd = fd
        NetSock.noDelay(fd)
        NetSock.noSigPipe(fd)
        let r = Thread { [weak self] in self?.readLoop() }
        r.name = "blocksmith.net.read"; r.stackSize = 1 << 20
        r.start()
        let w = Thread { [weak self] in self?.writeLoop() }
        w.name = "blocksmith.net.write"; w.stackSize = 1 << 20
        w.start()
    }

    // Queues a message (any thread).
    func send(_ type: UInt8, _ payload: [UInt8]) {
        guard !closed else { return }
        var f = [UInt8]()
        f.reserveCapacity(payload.count + 5)
        let n = UInt32(payload.count + 1)
        f += [UInt8(n & 255), UInt8(n >> 8 & 255), UInt8(n >> 16 & 255), UInt8(n >> 24)]
        f.append(type)
        f += payload
        wake.lock()
        outbox.append(f)
        outBytes += f.count
        wake.signal()
        wake.unlock()
    }
    var queuedBytes: Int { wake.lock(); defer { wake.unlock() }; return outBytes }

    // The messages received since the last poll (game thread).
    func poll() -> [(UInt8, [UInt8])] {
        lock.lock(); defer { lock.unlock() }
        let m = inbox
        inbox.removeAll(keepingCapacity: true)
        return m
    }

    func close() {
        guard !closed else { return }
        closed = true
        _ = shutdown(fd, Int32(SHUT_RDWR))
        wake.lock(); wake.signal(); wake.unlock()
    }

    private func readAll(_ n: Int) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: n)
        var got = 0
        while got < n {
            let r = out.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + got, n - got, 0) }
            if r > 0 { got += r; continue }
            if r < 0 && (errno == EINTR || errno == EAGAIN) && !closed { continue }
            return nil
        }
        return out
    }

    private func readLoop() {
        while !closed {
            guard let h = readAll(4) else { break }
            let n = Int(h[0]) | Int(h[1]) << 8 | Int(h[2]) << 16 | Int(h[3]) << 24
            guard n >= 1 && n <= NetLink.maxFrame, let body = readAll(n) else { break }
            lock.lock()
            inbox.append((body[0], Array(body[1...])))
            bytesIn += n + 4
            lock.unlock()
        }
        closed = true
        wake.lock(); wake.signal(); wake.unlock()
    }

    private func writeLoop() {
        while true {
            wake.lock()
            while outbox.isEmpty && !closed { wake.wait() }
            if closed { wake.unlock(); break }
            let batch = outbox
            outbox.removeAll(keepingCapacity: true)
            outBytes = 0
            wake.unlock()
            for f in batch {
                var sent = 0
                while sent < f.count {
                    #if canImport(Darwin)
                    let flags: Int32 = 0
                    #else
                    let flags = Int32(MSG_NOSIGNAL)
                    #endif
                    let r = f.withUnsafeBytes { sysSend(fd, $0.baseAddress! + sent, f.count - sent, flags) }
                    if r > 0 { sent += r; continue }
                    if r < 0 && errno == EINTR { continue }
                    closed = true
                    break
                }
                bytesOut += f.count
                if closed { break }
            }
        }
        sysClose(fd)
    }
}

// Little-endian message building and reading.
struct NetOut {
    var b: [UInt8] = []
    mutating func u8(_ v: UInt8) { b.append(v) }
    mutating func bool(_ v: Bool) { b.append(v ? 1 : 0) }
    mutating func u16(_ v: UInt16) { b += [UInt8(v & 255), UInt8(v >> 8)] }
    mutating func u32(_ v: UInt32) { b += [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24)] }
    mutating func i32(_ v: Int) { u32(UInt32(bitPattern: Int32(truncatingIfNeeded: v))) }
    mutating func u64(_ v: UInt64) { u32(UInt32(v & 0xFFFF_FFFF)); u32(UInt32(v >> 32)) }
    mutating func f32(_ v: Float) { u32(v.bitPattern) }
    mutating func f64(_ v: Double) { u64(v.bitPattern) }
    mutating func v3(_ v: V3) { f32(v.x); f32(v.y); f32(v.z) }
    mutating func str(_ s: String) { let u = Array(s.utf8.prefix(65535)); u16(UInt16(u.count)); b += u }
    mutating func bytes(_ d: [UInt8]) { u32(UInt32(d.count)); b += d }
}

struct NetIn {
    let b: [UInt8]
    var p = 0
    init(_ b: [UInt8]) { self.b = b }
    var ok: Bool { p <= b.count }
    mutating func u8() -> UInt8 { defer { p += 1 }; return p < b.count ? b[p] : 0 }
    mutating func bool() -> Bool { u8() != 0 }
    mutating func u16() -> UInt16 { UInt16(u8()) | UInt16(u8()) << 8 }
    mutating func u32() -> UInt32 { UInt32(u16()) | UInt32(u16()) << 16 }
    mutating func i32() -> Int { Int(Int32(bitPattern: u32())) }
    mutating func u64() -> UInt64 { UInt64(u32()) | UInt64(u32()) << 32 }
    mutating func f32() -> Float { Float(bitPattern: u32()) }
    mutating func f64() -> Double { Double(bitPattern: u64()) }
    mutating func v3() -> V3 { V3(f32(), f32(), f32()) }
    mutating func str() -> String {
        let n = Int(u16())
        guard p + n <= b.count else { p = b.count + 1; return "" }
        defer { p += n }
        return String(decoding: b[p..<(p + n)], as: UTF8.self)
    }
    mutating func bytes() -> [UInt8] {
        let n = Int(u32())
        guard p + n <= b.count else { p = b.count + 1; return [] }
        defer { p += n }
        return Array(b[p..<(p + n)])
    }
}
