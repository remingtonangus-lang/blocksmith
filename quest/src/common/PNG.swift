import Foundation
import CZlib

// Minimal RGBA8 PNG encoder (screenshots on the headset, render tests on Linux).
enum PNG {
    static func encode(rgba: [UInt8], width: Int, height: Int) -> Data {
        var raw = [UInt8](repeating: 0, count: (width * 4 + 1) * height)
        for y in 0..<height {
            raw[y * (width * 4 + 1)] = 0
            for i in 0..<(width * 4) { raw[y * (width * 4 + 1) + 1 + i] = rgba[y * width * 4 + i] }
        }
        var bound = compressBound(uLong(raw.count))
        var z = [UInt8](repeating: 0, count: Int(bound))
        _ = raw.withUnsafeBufferPointer { s in z.withUnsafeMutableBufferPointer { d in
            compress2(d.baseAddress, &bound, s.baseAddress, uLong(raw.count), 6) } }
        z.removeSubrange(Int(bound)...)
        var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        func chunk(_ type: String, _ body: [UInt8]) {
            var len = UInt32(body.count).bigEndian
            out.append(Data(bytes: &len, count: 4))
            let t = Array(type.utf8)
            out.append(contentsOf: t)
            out.append(contentsOf: body)
            var c = crc32(0, t, 4)
            c = body.withUnsafeBufferPointer { crc32(c, $0.baseAddress, uInt(body.count)) }
            var crc = UInt32(c).bigEndian
            out.append(Data(bytes: &crc, count: 4))
        }
        func be(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
        chunk("IHDR", be(width) + be(height) + [8, 6, 0, 0, 0])
        chunk("IDAT", z)
        chunk("IEND", [])
        return out
    }
}
