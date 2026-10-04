import Foundation
#if !canImport(Darwin)
import CZlib

// NSData.compressed/decompressed (Save.swift's chunk files) for Android/Linux, where swift-corelibs-foundation has
// no Compression framework. Every algorithm maps to zlib deflate behind a "BSZ1" + length header, so Quest saves
// are self-consistent (they are not readable by the Mac's LZFSE path, and vice versa).
extension NSData {
    enum CompressionAlgorithm { case lzfse, lz4, lzma, zlib }
    struct CompressionError: Error {}

    func compressed(using _: CompressionAlgorithm) throws -> NSData {
        let src = self as Data
        var bound = compressBound(uLong(src.count))
        var out = [UInt8](repeating: 0, count: Int(bound) + 12)
        let rc: Int32 = src.withUnsafeBytes { s in
            out.withUnsafeMutableBytes { o in
                compress2(o.baseAddress!.advanced(by: 12).assumingMemoryBound(to: Bytef.self), &bound,
                          s.baseAddress?.assumingMemoryBound(to: Bytef.self), uLong(src.count), 3)
            }
        }
        guard rc == Z_OK else { throw CompressionError() }
        out[0] = 0x42; out[1] = 0x53; out[2] = 0x5A; out[3] = 0x31      // "BSZ1"
        let n = UInt64(src.count)
        for i in 0..<8 { out[4 + i] = UInt8(truncatingIfNeeded: n >> (8 * UInt64(i))) }
        return Data(out[0..<(12 + Int(bound))]) as NSData
    }

    func decompressed(using _: CompressionAlgorithm) throws -> NSData {
        let src = self as Data
        guard src.count >= 12, src[src.startIndex] == 0x42, src[src.startIndex + 1] == 0x53,
              src[src.startIndex + 2] == 0x5A, src[src.startIndex + 3] == 0x31 else { throw CompressionError() }
        var n: UInt64 = 0
        for i in 0..<8 { n |= UInt64(src[src.startIndex + 4 + i]) << (8 * UInt64(i)) }
        guard n < 1 << 30 else { throw CompressionError() }
        var outLen = uLong(n)
        var out = [UInt8](repeating: 0, count: Swift.max(1, Int(n)))
        let rc: Int32 = src.withUnsafeBytes { s in
            out.withUnsafeMutableBytes { o in
                uncompress(o.baseAddress!.assumingMemoryBound(to: Bytef.self), &outLen,
                           s.baseAddress!.advanced(by: 12).assumingMemoryBound(to: Bytef.self), uLong(src.count - 12))
            }
        }
        guard rc == Z_OK, outLen == uLong(n) else { throw CompressionError() }
        return Data(out[0..<Int(n)]) as NSData
    }
}
#endif
