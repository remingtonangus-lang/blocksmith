import Foundation

// The painted block textures (TextureGen.mipChain: every layer, every mip level) cached on the headset's storage, so
// only the first launch of a build pays for painting them. Keyed by build commit, texture size and layer count; a
// cache from another build is deleted when the new one is written.
enum TextureCache {
    private static let magic: UInt32 = 0x42_53_54_43           // "BSTC"

    static func url(dir: String, size: Int = TextureGen.size, layers: Int = Tex.count) -> URL {
        URL(fileURLWithPath: dir).appendingPathComponent("textures-\(QuestBuild.commit)-\(size)px-\(layers).bin")
    }

    static func load(_ url: URL) -> [[UInt8]]? {
        guard let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count >= 8 else { return nil }
        return d.withUnsafeBytes { raw -> [[UInt8]]? in
            func u32(_ o: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
            guard u32(0) == Int(magic) else { return nil }
            let n = u32(4)
            guard n > 0, n < 32, d.count >= 8 + n * 4 else { return nil }
            var off = 8 + n * 4
            var levels: [[UInt8]] = []
            for i in 0..<n {
                let len = u32(8 + i * 4)
                guard off + len <= d.count else { return nil }
                levels.append([UInt8](UnsafeRawBufferPointer(rebasing: raw[off..<(off + len)])))
                off += len
            }
            return off == d.count ? levels : nil
        }
    }

    static func store(_ levels: [[UInt8]], _ url: URL) {
        var d = Data()
        func put(_ v: Int) { var x = UInt32(v); withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        put(Int(magic)); put(levels.count)
        for l in levels { put(l.count) }
        for l in levels { d.append(contentsOf: l) }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        where f.hasPrefix("textures-") && f.hasSuffix(".bin") && f != url.lastPathComponent {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
        do { try d.write(to: url, options: .atomic) } catch { print("textures: cache not written: \(error)") }
    }

    // Cached levels, or freshly painted ones (then cached).
    static func mipChain(dir: String) -> [[UInt8]] {
        let u = url(dir: dir)
        let t0 = CFAbsoluteTimeGetCurrent()
        if let l = load(u) {
            print(String(format: "textures: from cache %@ (%.0f ms)", u.lastPathComponent, (CFAbsoluteTimeGetCurrent() - t0) * 1000))
            return l
        }
        let l = TextureGen.mipChain()
        let t1 = CFAbsoluteTimeGetCurrent()
        store(l, u)
        print(String(format: "textures: painted in %.0f ms, cached in %.0f ms", (t1 - t0) * 1000, (CFAbsoluteTimeGetCurrent() - t1) * 1000))
        return l
    }
}
