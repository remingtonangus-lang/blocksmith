import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Darwin)
import Darwin
#endif

// The painted block textures (TextureGen.mipChain: every layer, every mip level) cached on the headset's storage, so
// only the first launch of a build pays for painting them. Keyed by build commit, texture size, layer count and texpack hash; a
// cache from another build is deleted when the new one is written.
enum TextureCache {
    private static let magic: UInt32 = 0x42_53_54_43           // "BSTC"

    static func url(dir: String, size: Int = TextureGen.size, layers: Int = Tex.count) -> URL {
        // + the imported texture pack's content hash, so new art invalidates the cache (no pack: the old key).
        let pack = TextureImport.hash.map { "-p" + $0 } ?? ""
        return URL(fileURLWithPath: dir).appendingPathComponent("textures-\(QuestBuild.commit)-\(size)px-\(layers)\(pack).bin")
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

    // P401: written straight from the levels to a temporary file, then renamed (the levels were first copied into one
    // 166 MB Data, which sat beside them while the launch went on: the first launch of a build's memory peak).
    static let lean = ProcessInfo.processInfo.environment["BS_P401"] != "0"     // (BS_P401=0: as before, for the numbers)
    static func store(_ levels: [[UInt8]], _ url: URL) {
        if !lean {
            var d = Data()
            func put(_ v: Int) { var x = UInt32(v); withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
            put(Int(magic)); put(levels.count)
            for l in levels { put(l.count) }
            for l in levels { d.append(contentsOf: l) }
            try? d.write(to: url, options: .atomic)
            return
        }
        var head: [UInt32] = [magic, UInt32(levels.count)]
        for l in levels { head.append(UInt32(l.count)) }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        where f.hasPrefix("textures-") && f.hasSuffix(".bin") && f != url.lastPathComponent {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
        let tmp = url.path + ".part"
        guard let fp = fopen(tmp, "wb") else { print("textures: cache not written (\(tmp))"); return }
        var ok = head.withUnsafeBytes { fwrite($0.baseAddress!, 1, $0.count, fp) == $0.count }
        for l in levels where ok { ok = l.withUnsafeBytes { $0.count == 0 || fwrite($0.baseAddress!, 1, $0.count, fp) == $0.count } }
        ok = fclose(fp) == 0 && ok
        if !ok || rename(tmp, url.path) != 0 { unlink(tmp); print("textures: cache not written (\(url.lastPathComponent))") }
    }

    static var backgroundStore = ProcessInfo.processInfo.environment["BS_TEXCACHEBG"] != "0"
    // Cached levels, or freshly painted ones (then cached). The imported pack's pixels are released afterwards.
    static func mipChain(dir: String) -> [[UInt8]] {
        defer { TextureImport.release() }
        let u = url(dir: dir)
        let t0 = CFAbsoluteTimeGetCurrent()
        if let l = load(u) {
            print(String(format: "textures: from cache %@ (%.0f ms)", u.lastPathComponent, (CFAbsoluteTimeGetCurrent() - t0) * 1000))
            return l
        }
        let l = TextureGen.mipChain()
        let t1 = CFAbsoluteTimeGetCurrent()
        // P400 step 4: the cache is written behind the load (2.4-2.9 s on the host, all of it on the launch's path before).
        if backgroundStore {
            DispatchQueue.global(qos: .utility).async {
                let t2 = CFAbsoluteTimeGetCurrent()
                store(l, u)
                print(String(format: "textures: cached in %.0f ms (behind the load)", (CFAbsoluteTimeGetCurrent() - t2) * 1000))
            }
            print(String(format: "textures: painted in %.0f ms", (t1 - t0) * 1000))
            return l
        }
        store(l, u)
        print(String(format: "textures: painted in %.0f ms, cached in %.0f ms", (t1 - t0) * 1000, (CFAbsoluteTimeGetCurrent() - t1) * 1000))
        return l
    }
}
