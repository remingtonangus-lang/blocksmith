import Foundation
import simd
#if canImport(Compression)
import Compression
#else
import CZlib
#endif

// Resources/texpack.bin (tools/texpack.py): the imported PNG textures pre-decoded for the Quest build, which has no
// ImageIO. Format (little endian): "BSTP", u32 version, u32 tile size, u32 count; version 2 then has u32 body length
// and the body as one zlib stream, version 1 the body stored. Body: per entry u16 name length, UTF-8 name,
// tile*tile*4 RGBA8 (straight alpha, rows top to bottom). Foundation + zlib only, so the Quest build and the Mac
// harness (`--texpacktest`) share it. The Mac game itself keeps reading the PNGs (TextureImport.swift).
struct TexPack {
    let tile: Int
    let entries: [String: Range<Int>]        // name -> byte range of its RGBA8 pixels in `data`
    let data: Data
    let hash: String                         // short content hash (FNV-1a 64), keys the Quest texture cache

    init?(_ d: Data) {
        let raw = [UInt8](d)
        guard raw.count >= 16, raw[0] == 0x42, raw[1] == 0x53, raw[2] == 0x54, raw[3] == 0x50 else { return nil }
        func u32(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        let version = u32(raw, 4), n = u32(raw, 8), count = u32(raw, 12)
        guard version == 1 || version == 2, n > 0, n <= 1024 else { return nil }
        let b: [UInt8]
        var off: Int
        if version == 2 {
            guard raw.count >= 20, let body = TexPack.unzip(Array(raw[20...]), size: u32(raw, 16)) else { return nil }
            b = body; off = 0
        } else {
            b = raw; off = 16
        }
        var map: [String: Range<Int>] = [:]
        for _ in 0..<count {
            guard off + 2 <= b.count else { return nil }
            let len = Int(b[off]) | Int(b[off + 1]) << 8
            off += 2
            guard off + len + n * n * 4 <= b.count,
                  let name = String(bytes: b[off..<(off + len)], encoding: .utf8) else { return nil }
            off += len
            map[name] = off..<(off + n * n * 4)
            off += n * n * 4
        }
        guard off == b.count else { return nil }
        var h: UInt64 = 0xcbf29ce484222325
        for x in raw { h = (h ^ UInt64(x)) &* 0x100000001b3 }
        tile = n; entries = map; data = Data(b); self.hash = String(h, radix: 16)
    }

    // A zlib stream (RFC 1950) of known unpacked size; nil if it doesn't unpack to exactly that.
    static func unzip(_ src: [UInt8], size: Int) -> [UInt8]? {
        guard size >= 0, size < 1 << 30, src.count > 2 else { return nil }
        var out = [UInt8](repeating: 0, count: max(1, size))
        #if canImport(Compression)
        // Apple's COMPRESSION_ZLIB is raw DEFLATE: skip the 2-byte zlib header (the Adler-32 trailer is ignored).
        let got = src.withUnsafeBufferPointer { s in out.withUnsafeMutableBufferPointer { o in
            compression_decode_buffer(o.baseAddress!, o.count, s.baseAddress! + 2, s.count - 2, nil, COMPRESSION_ZLIB) } }
        guard got == size else { return nil }
        #else
        var len = uLong(out.count)
        let rc: Int32 = src.withUnsafeBufferPointer { s in out.withUnsafeMutableBufferPointer { o in
            uncompress(o.baseAddress!, &len, s.baseAddress!, uLong(s.count)) } }
        guard rc == Z_OK, Int(len) == size else { return nil }
        #endif
        return size == 0 ? [] : out
    }

    // The layer `name` at size x size (RGBA 0...1, straight alpha), or nil. Box-filtered (alpha-weighted) when the
    // pack's tiles are larger, nearest-neighbour when smaller (keeps pixel edges and cutouts crisp).
    func image(_ name: String, size: Int) -> [V4]? {
        guard let r = entries[name] else { return nil }
        let n = tile
        return data.withUnsafeBytes { raw -> [V4] in
            let p = raw.baseAddress!.assumingMemoryBound(to: UInt8.self) + r.lowerBound
            var out = [V4](repeating: V4(0, 0, 0, 0), count: size * size)
            for y in 0..<size { for x in 0..<size {
                let x0 = x * n / size, x1 = max(x0 + 1, (x + 1) * n / size)
                let y0 = y * n / size, y1 = max(y0 + 1, (y + 1) * n / size)
                var acc = V4(0, 0, 0, 0)
                for sy in y0..<y1 { for sx in x0..<x1 {
                    let i = (sy * n + sx) * 4
                    let a = Float(p[i + 3])
                    acc += V4(Float(p[i]) * a, Float(p[i + 1]) * a, Float(p[i + 2]) * a, a * 255)
                } }
                let c: V4 = acc / Float((x1 - x0) * (y1 - y0) * 255 * 255)
                out[y * size + x] = c.w > 0.001 ? V4(c.x / c.w, c.y / c.w, c.z / c.w, c.w) : V4(0, 0, 0, 0)
            } }
            return out
        }
    }

    // Harness check (Mac `--texpacktest [path]`): the pack parses and every entry names a registered texture layer.
    static func selfTest(path: String) -> Int32 {
        guard let d = FileManager.default.contents(atPath: path) else { print("texpacktest: no \(path)"); return 1 }
        guard let pack = TexPack(d) else { print("texpacktest: \(path) is not a valid texture pack"); return 1 }
        TextureGen.registerAll()
        let known = Set(Tex.names)
        let unknown = pack.entries.keys.filter { !known.contains($0) }.sorted()
        for name in pack.entries.keys.sorted().prefix(1) {
            let px = pack.image(name, size: TextureGen.size)
            if px?.count != TextureGen.size * TextureGen.size { print("texpacktest: \(name) did not resample"); return 1 }
        }
        print("texpacktest: \(pack.entries.count) textures at \(pack.tile) px, hash \(pack.hash), \(unknown.count) unknown names")
        for u in unknown { print("  unknown: \(u)") }
        return unknown.isEmpty ? 0 : 2
    }
}
