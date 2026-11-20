import Foundation
import simd

// Ledger 362: far trees as pictures of the real trees. Each kind is photographed by the game's own renderer from
// `yaws` sides (tools/far_sprites.sh: one generated tree alone in the air, the real mesh, textures and light), and the
// pictures are texture layers `far_<kind>_<variant>[_s]_<yaw>` (Resources/Textures). FarForest draws a far tree as
// one card that turns about its trunk to face the eye and shows the picture taken from that side.
enum FarSprites {
    // Ledger 362: the elevation (degrees) from which the cards show the pictures taken from 40 degrees up. BS_FARUPDEG.
    static let upFrom: Float = Env.all["BS_FARUPDEG"].flatMap { Float($0) } ?? 16
    static let yaws = 8
    static let variants = 2
    // (name, kind, snowy pictures too)
    // (every kind that can stand where it snows has its snowy twin; the hot lands' kinds never do)
    static let kinds: [(String, TreeKind, Bool)] = [
        ("oak", .oak, true), ("small_oak", .smallOak, true), ("fancy_oak", .fancyOak, true), ("ancient_oak", .ancientOak, true),
        ("swamp_oak", .swampOak, true), ("birch", .birch, true), ("tall_birch", .tallBirch, true),
        ("spruce", .spruce, true), ("pine", .pine, true), ("mega_spruce", .megaSpruce, true), ("mega_pine", .megaPine, true),
        ("jungle", .jungle, false), ("mega_jungle", .megaJungle, false), ("acacia", .acacia, false), ("dark_oak", .darkOak, true),
        ("mangrove", .mangrove, false), ("cherry", .cherry, true), ("pale_oak", .paleOak, true), ("saltpalm", .saltpalm, false),
        // (the undergrowth: without it a far jungle's floor was bare bright grass under the trees)
        ("jungle_bush", .jungleBush, false),
    ]
    static func kind(_ name: String) -> TreeKind? { kinds.first { $0.0 == name }?.1 }
    static func index(_ k: TreeKind) -> Int? { kinds.firstIndex { $0.1 == k } }

    // The pictures (Resources/farpack.bin, a TexPack of 128 px tiles; the Quest build carries it as an asset). A set is
    // one tree's `pics` pictures in a row: 4 level (from 20, 110, 200 and 290 degrees round the trunk), then 2 from 40
    // degrees above (20 and 200). The sets of a kind: variant 0, variant 1, then the snowy twins where it has them.
    static var pack: TexPack?
    static let px = 96
    static let pics = 6
    static let above: Float = 40
    static func load(_ d: Data?) {
        guard let d, let p = TexPack(d) else { print("far sprites: no farpack.bin, the far layer keeps its shapes"); return }
        pack = p
        if let t = p.image("far_tint", size: 1)?.first { captureTint = V3(t.x, t.y, t.z) }
        print("far sprites: \(p.entries.count) pictures at \(p.tile) px")
    }
    static var ready: Bool { pack != nil }
    private static let bases: [Int] = {
        var b: [Int] = [], n = 0
        for k in kinds { b.append(n); n += variants * (k.2 ? 2 : 1) }
        return b + [n]
    }()
    static var sets: Int { bases[kinds.count] }
    static var layers: Int { sets * pics }
    // The first layer of a tree's set.
    static func base(_ ki: Int, variant: Int, snowy: Bool) -> Int {
        (bases[ki] + variant % variants + (snowy && kinds[ki].2 ? variants : 0)) * pics
    }
    // Every layer's pixels at `n` px (RGBA8, layer-major), box-filtered from the pack; a missing picture is clear.
    static func pixels(size n: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: layers * n * n * 4)
        guard let p = pack else { return out }
        for (ki, k) in kinds.enumerated() { for snowy in (k.2 ? [false, true] : [false]) { for v in 0..<variants {
            let b = base(ki, variant: v, snowy: snowy)
            for pic in 0..<pics {
                let src = pic < 4 ? pic : 4 + (pic - 4) * 2
                guard let img = p.image(layerName(k.0, variant: v, snowy: snowy, yaw: src), size: n) else { continue }
                let o = (b + pic) * n * n * 4
                for i in 0..<(n * n) {
                    let c = img[i]
                    out[o + i * 4] = UInt8(max(0, min(255, c.x * 255 + 0.5))); out[o + i * 4 + 1] = UInt8(max(0, min(255, c.y * 255 + 0.5)))
                    out[o + i * 4 + 2] = UInt8(max(0, min(255, c.z * 255 + 0.5))); out[o + i * 4 + 3] = UInt8(max(0, min(255, c.w * 255 + 0.5)))
                }
            }
        } } }
        return out
    }
    // The variant's own tree, as the scene tool and the frame measure build it (blocks of one chunk, the foot at 8, y, 8).
    static func blocks(_ kind: TreeKind, variant: Int, y: Int, into b: inout [BlockID]) {
        if b.count != CS * CS * CH { b = [BlockID](repeating: AIR, count: CS * CS * CH) }
        for i in 0..<b.count { b[i] = AIR }
        var rng = SRng(UInt64(variant) &* 0x9E37 &+ 77)
        b.withUnsafeMutableBufferPointer { buf in
            TreePlacer.build(TreeWriter(b: buf.baseAddress!, bx: 0, bz: 0), kind, 8, y, 8, &rng)
        }
    }
    // The square a kind's pictures frame, in blocks: its side (the tallest and widest variant with a block to spare)
    // and how far over the tree's foot its centre is (half the tallest variant's height). It is centred on the trunk.
    private static var frames: [Int: (side: Float, rise: Float)] = [:]
    private static var tintedKinds: [Int: Bool] = [:]
    // Does the kind's leaf take the biome's foliage colour (oak, jungle ...) or its own (spruce, birch, cherry)?
    static func tinted(_ kind: TreeKind) -> Bool {
        _ = frame(kind)
        guard let ki = index(kind) else { return false }
        lock.lock(); defer { lock.unlock() }
        return tintedKinds[ki] ?? false
    }
    // The foliage colour where the pictures were taken (the pack's `far_tint` tile): a tinted kind's card is scaled
    // by the tree's own foliage colour over this one.
    static var captureTint: V3 = V3(0.4, 0.6, 0.3)
    private static let lock = NSLock()
    static func frame(_ kind: TreeKind) -> (side: Float, rise: Float) {
        guard let ki = index(kind) else { return (16, 8) }
        lock.lock(); defer { lock.unlock() }
        if let f = frames[ki] { return f }
        var b: [BlockID] = []
        var side: Float = 4, top: Float = 2
        var tint = false
        let y0 = 100
        for v in 0..<variants {
            blocks(kind, variant: v, y: y0, into: &b)
            for z in 0..<CS { for x in 0..<CS { for y in y0..<(y0 + 60) where b[Chunk.index(x, y, z)] != AIR {
                let dx = abs(Float(x) - 8) + 1, dz = abs(Float(z) - 8) + 1
                top = max(top, Float(y - y0) + 1.5)
                let id = Int(b[Chunk.index(x, y, z)])
                if Mesher.leafT[id] && Blocks.tint[id] == 2 { tint = true }
                side = max(side, 2 * max(dx, dz) * 1.45 + 1)      // (seen cornerwise a crown is 1.41 wider)
            } } }
        }
        // (from 40 degrees above the square must still hold the foot and the top)
        let f = (max(side, top + 3), top * 0.5)
        frames[ki] = f
        tintedKinds[ki] = tint
        return f
    }
    static func layerName(_ kind: String, variant: Int, snowy: Bool, yaw: Int) -> String { "far_\(kind)_\(variant)\(snowy ? "_s" : "")_\(yaw)" }
}
