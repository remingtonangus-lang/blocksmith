import Foundation

// Item 11 (Nov 10, a saved world's launch under callgrind): chunk and ground files went through NSData's compression
// and came back as NSData, bridged to Data and then to bytes. On the headset (Linux Foundation) that bridge copies a
// byte at a time through the generic sequence path: 200 M instructions a chunk file, 30% of making a saved world's
// first ring. Here the bytes go to zlib and back directly (quest/src/common/Compression.swift, ZlibCodec), in the
// same "BSZ1" format, so files read and written either way are the same. The Mac keeps its own LZFSE path.
// BS_OLDSAVEBYTES=1: through NSData as before; BS_SAVEBYTESVERIFY=1: both ways, the results compared (verified/differ).
enum SaveBytes {
    static let oldWay = ProcessInfo.processInfo.environment["BS_OLDSAVEBYTES"] == "1"
    static let verify = ProcessInfo.processInfo.environment["BS_SAVEBYTESVERIFY"] == "1"
    private static let lock = NSLock()
    private(set) static var verified = 0, differ = 0

    private static func note(_ same: Bool) {
        lock.lock(); verified += 1; if !same { differ += 1 }; lock.unlock()
    }

    private static func oldInflate(_ d: Data) -> [UInt8]? {
        guard let raw = try? (d as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return [UInt8](raw)
    }

    private static func oldDeflate(_ d: Data) -> Data? { try? (d as NSData).compressed(using: .lzfse) as Data }

    static func decompress(_ d: [UInt8]) -> [UInt8]? {
        #if !canImport(Darwin)
        if !oldWay {
            let out = d.withUnsafeBytes { ZlibCodec.inflate($0) }
            if verify { note(out == oldInflate(Data(d))) }
            return out
        }
        #endif
        return oldInflate(Data(d))
    }

    static func decompress(_ d: Data) -> [UInt8]? {
        #if !canImport(Darwin)
        if !oldWay {
            let out = d.withUnsafeBytes { ZlibCodec.inflate($0) }
            if verify { note(out == oldInflate(d)) }
            return out
        }
        #endif
        return oldInflate(d)
    }

    static func compress(_ d: Data) -> Data? {
        #if !canImport(Darwin)
        if !oldWay {
            let out = d.withUnsafeBytes { ZlibCodec.deflate($0) }.map { Data($0) }
            if verify { note(out == oldDeflate(d)) }
            return out
        }
        #endif
        return oldDeflate(d)
    }
}
