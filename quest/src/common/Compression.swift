import Foundation
#if !canImport(Darwin)
import CZlib

// NSData.compressed/decompressed (Save.swift's chunk files) for Android/Linux, where swift-corelibs-foundation has
// no Compression framework. Every algorithm maps to zlib deflate behind a "BSZ1" + length header, so Quest saves
// are self-consistent (they are not readable by the Mac's LZFSE path, and vice versa).
// Item 11 (Nov 10, the launch's callgrind): the zlib work on plain bytes. Handing the result back as NSData cost far
// more than the inflating: on Linux and Android an NSData bridged to Data is copied a byte at a time through the
// sequence path (200 M instructions a chunk file, 30% of a saved world's first ring). SaveBytes calls these directly.
enum ZlibCodec {
    static func deflate(_ s: UnsafeRawBufferPointer) -> [UInt8]? {
        var bound = compressBound(uLong(s.count))
        var out = [UInt8](repeating: 0, count: Int(bound) + 12)
        let rc: Int32 = out.withUnsafeMutableBytes { o in
            compress2(o.baseAddress!.advanced(by: 12).assumingMemoryBound(to: Bytef.self), &bound,
                      s.baseAddress?.assumingMemoryBound(to: Bytef.self), uLong(s.count), 3)
        }
        guard rc == Z_OK else { return nil }
        out[0] = 0x42; out[1] = 0x53; out[2] = 0x5A; out[3] = 0x31      // "BSZ1"
        let n = UInt64(s.count)
        for i in 0..<8 { out[4 + i] = UInt8(truncatingIfNeeded: n >> (8 * UInt64(i))) }
        out.removeLast(out.count - (12 + Int(bound)))
        return out
    }

    static func inflate(_ s: UnsafeRawBufferPointer) -> [UInt8]? {
        guard s.count >= 12, s[0] == 0x42, s[1] == 0x53, s[2] == 0x5A, s[3] == 0x31 else { return nil }
        var n: UInt64 = 0
        for i in 0..<8 { n |= UInt64(s[4 + i]) << (8 * UInt64(i)) }
        guard n < 1 << 30 else { return nil }
        var outLen = uLong(n)
        var out = [UInt8](repeating: 0, count: Swift.max(1, Int(n)))
        let rc: Int32 = out.withUnsafeMutableBytes { o in
            uncompress(o.baseAddress!.assumingMemoryBound(to: Bytef.self), &outLen,
                       s.baseAddress!.advanced(by: 12).assumingMemoryBound(to: Bytef.self), uLong(s.count - 12))
        }
        guard rc == Z_OK, outLen == uLong(n) else { return nil }
        if n == 0 { out.removeAll() }
        return out
    }
}

extension NSData {
    enum CompressionAlgorithm { case lzfse, lz4, lzma, zlib }
    struct CompressionError: Error {}

    func compressed(using _: CompressionAlgorithm) throws -> NSData {
        guard let out = (self as Data).withUnsafeBytes({ ZlibCodec.deflate($0) }) else { throw CompressionError() }
        return Data(out) as NSData
    }

    func decompressed(using _: CompressionAlgorithm) throws -> NSData {
        guard let out = (self as Data).withUnsafeBytes({ ZlibCodec.inflate($0) }) else { throw CompressionError() }
        return Data(out) as NSData
    }
}
#endif
