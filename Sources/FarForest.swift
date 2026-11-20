import Foundation
import simd

// Ledger 361 (Nov 18, Remington: "build our own compression models for far distance that balances detail with
// simplicity"): the woods past the loaded chunks, one low-poly stand-in per real tree. The tree pass (TreePlacer.place)
// is a pure function of position: a 3-block lattice, one hash per cell, the column's biome and a glade noise. `site`
// asks the same questions without the chunk, so a stand-in stands where the chunk will grow that tree, of that kind:
// walking toward a far wood, each stand-in is replaced by its own tree at the loaded edge. (The chunk's last word, the
// soil under the trunk, a building's footprint, a railway beside it, is not asked: a few stand-ins have no tree.)
//
// A conifer is a four-sided pyramid, a broadleaf a tapered box, each over a crossed trunk near the loaded edge; with
// distance the wood thins to one stand-in in four, drawn wider, so a far wood keeps its cover with a quarter of the
// quads. They are quads in the far ring's own vertex list (FarRing.build), lit and fogged by its shader: no texture,
// no extra draw call. Trees are kept per 128-block cell between builds (touched only by the one build running).
final class FarForest {
    static let reach: Float = 560                  // blocks from the ring's centre
    static let cell = 128
    static let maxQuads = 80_000                   // of the ring's draw (SceneRenderer.maxQuads is 131,072)

    struct Tree {
        var x: Int32, z: Int32
        var y: Float                               // the ground's top
        var h: Float, r: Float                     // height over the ground, the crown's half width
        var base: Float                            // where the crown begins, as a share of h
        var cone: Bool
        var leaf: V3, top: V3, bark: V3
        var hv: UInt32
        var snowy = false
        var kind: TreeKind = .oak
        var size: Float = 1
        var tint = V3(1, 1, 1)                     // ledger 362: the column's foliage colour over the pictures' (tinted kinds)
        var shade: Float = 1                       // ledger 362: the wood's shade folded into `tint` (checks divide it out)
    }

    let seed: UInt64
    private var cells: [Int64: [Tree]] = [:]
    init(seed: UInt64) { self.seed = seed }

    // (height, crown half width, crown start, cone, leaf tint or 0 for the biome's own)
    static func shape(_ k: TreeKind) -> (h: Float, r: Float, base: Float, cone: Bool, leaf: UInt32)? {
        switch k {
        case .oak, .swampOak: return (6.5, 2.6, 0.45, false, 0)
        case .smallOak: return (5, 2.1, 0.4, false, 0)
        case .fancyOak: return (11, 4, 0.45, false, 0)
        case .ancientOak: return (19, 7, 0.4, false, 0)
        case .birch: return (7.5, 2.4, 0.45, false, 0x80A755)
        case .tallBirch: return (11.5, 2.4, 0.6, false, 0x80A755)
        case .spruce: return (9.5, 2.7, 0.2, true, 0x619961)
        case .pine: return (10.5, 2.3, 0.5, true, 0x619961)
        case .megaSpruce: return (23, 4.6, 0.25, true, 0x619961)
        case .megaPine: return (23, 4, 0.6, true, 0x619961)
        case .jungle: return (9.5, 2.6, 0.55, false, 0)
        case .megaJungle: return (25, 5.5, 0.7, false, 0)
        case .acacia: return (7.5, 3.6, 0.72, false, 0)
        case .darkOak: return (8.5, 4, 0.45, false, 0)
        case .mangrove: return (8.5, 3, 0.5, false, 0)
        case .cherry: return (7.5, 3.6, 0.45, false, 0xE7A8C7)
        case .paleOak: return (8.5, 4, 0.45, false, 0xA3ABA0)
        case .saltpalm: return (8.5, 2.6, 0.78, false, 0)
        case .jungleBush: return (2.5, 1.6, 0.2, false, 0)        // (ledger 362: the undergrowth)
        default: return nil                        // stumps, snags, fallen trunks, ice spikes
        }
    }

    // The tree the chunk's tree pass would grow from lattice cell (gx, gz), if any: TreePlacer.place's own steps.
    static func site(_ gen: WorldGen, _ gx: Int, _ gz: Int) -> Tree? {
        let hv = hash3(gx, 0, gz, gen.s32 ^ 0x7EE5)
        let roll = Float((hv >> 4) & 0xFFFF) / 65536
        if roll > 0.7 { return nil }
        let tx = gx * 3 + Int(hv % 3), tz = gz * 3 + Int((hv >> 2) % 3)
        let k = gen.terrain.column(tx, tz)
        guard k.rv > 1.2 else { return nil }
        let dT = (hashf(tx, 2, tz, gen.s32 ^ 0x7EE8) - 0.5) * 0.16
        let dW = (hashf(tx, 3, tz, gen.s32 ^ 0x7EE9) - 0.5) * 0.18
        let dith = gen.terrain.biome(k, k.h, dT: dT, dW: dW)
        let base = gen.terrain.biome(k, k.h)
        let biome = dith.isDry == base.isDry ? dith : base
        let glade = gen.flora.noise2(Float(tx) / 70 + 300, Float(tz) / 70)
        let r2 = roll / max(0.3, 0.8 + 0.9 * glade)
        let pick = hashf(tx, 1, tz, gen.s32 ^ 0x7EE6)
        let gy = YOFF + Int(k.h)
        guard let kind = TreePlacer.choose(biome, r2, pick, gy), let sh = shape(kind) else { return nil }
        guard gy >= SEA, Int(k.h) >= Int(floorf(k.wl)), !(k.vol > 0.2 && k.lava > k.h) else { return nil }
        func rgb(_ v: UInt32) -> V3 { V3(Float((v >> 16) & 255), Float((v >> 8) & 255), Float(v & 255)) / 255 }
        // Leaf art is darker than its tint (FarRing.canopy); each tree a little lighter or darker than the next.
        let vary: Float = 0.9 + 0.2 * Float((hv >> 24) & 0xFF) / 255
        let leaf = sh.cone ? darkConifer * (1.05 * vary) : rgb(sh.leaf != 0 ? sh.leaf : biome.info.foliage) * (0.5 * vary)
        var top = leaf * 1.12
        let t = gen.terrain.temperature(k, k.h + 1)
        let cold = k.lava <= 0 && k.flow <= 0.3 && k.vol <= 0.3 && (t < -0.25 || (biome.snows(at: gy + 1) && t < -0.15))
        if cold { top = simd_mix(leaf, FarRing.snow, V3(repeating: 0.85)) }
        let pale = kind == .birch || kind == .tallBirch || kind == .paleOak
        let bark: V3 = pale ? V3(0.74, 0.74, 0.7) * 0.8 : V3(0.36, 0.27, 0.18) * 0.8
        let size: Float = 0.9 + 0.2 * Float((hv >> 12) & 0xFF) / 255
        var tree = Tree(x: Int32(tx), z: Int32(tz), y: Float(YOFF) + floorf(k.h) + 1, h: sh.h * size, r: sh.r, base: sh.base,
                        cone: sh.cone, leaf: leaf, top: top, bark: bark, hv: hv, snowy: cold, kind: kind, size: 1)
        if FarForest.cards && FarSprites.tinted(kind) { tree.tint = gen.foliageTint(k) / simd_max(FarSprites.captureTint, V3(repeating: 0.02)) }
        // The pictures are of a tree alone in the sun; in a wood its neighbours shade it (measured against the real
        // trees at view 20: a thick snowy taiga's crowns a fifth darker than the cards, open woods the same).
        if FarForest.cards && FarForest.woodShade { tree.shade = 1 - 0.22 * FarRing.canopy(gen, biome, tx, tz, ground: k.h).cover; tree.tint *= tree.shade }
        return tree
    }

    private func trees(_ gen: WorldGen, _ kx: Int, _ kz: Int) -> [Tree] {
        let key = (Int64(kx) << 32) | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: kz)))
        if let t = cells[key] { return t }
        if cells.count > 400 { cells.removeAll(keepingCapacity: true) }
        var out: [Tree] = []
        let c = FarForest.cell
        // (Lattice cell g holds the trees of blocks 3g ... 3g + 2.)
        for gz in floorDiv(kz * c + 2, 3)...floorDiv(kz * c + c - 1, 3) {
            for gx in floorDiv(kx * c + 2, 3)...floorDiv(kx * c + c - 1, 3) {
                if let t = FarForest.site(gen, gx, gz) { out.append(t) }
            }
        }
        cells[key] = out
        return out
    }

    // The real tree's own outline. A kind's crown is baked once per variant from the blocks the tree builder lays
    // (TreePlacer.build): layer by layer, the leaves' centre and the radius of a disc of their area. A stand-in is that
    // outline turned about its axis with a few sides, reduced to the points that matter most (the widest tier, the
    // waist, the tip), so a far spruce keeps its tiers and a far oak its round head.
    struct Model {
        var rings: [(y: Float, r: Float, cx: Float, cz: Float)] = []      // y over the ground, every leaf layer
        var trunk: Float = 0                                              // the lowest leaf layer
        var tiers: [[(y: Float, r: Float, cx: Float, cz: Float)]] = []    // reduced to 5, 4 and 3 points
    }
    static let variants = 4
    // Ledger 362: far trees as pictures of the real trees (FarSprites) when the pictures are there; BS_FARSHAPES=1
    // keeps the lathed shapes of ledger 361 (before).
    static var cards: Bool { FarSprites.ready && Env.all["BS_FARSHAPES"] == nil }
    private(set) var lastCards = 0
    static let woodShade = Env.all["BS_NOFARWOODSHADE"] == nil
    // One quad a tree (quest/shaders/farcard.vert): the foot, the corner, the frame's side, the set's first layer, the
    // tree's own quarter turn and the frame centre's height over the foot. Returns the number of quads.
    func emitCards(_ gen: WorldGen, cx: Int, cz: Int, rin: Float, skip: Float = .infinity, into out: inout [SimpleVert]) -> Int {
        var n = 0
        // Ledger 391b (Neon's review 06#4): rin - 24 is measured from the ring's 128-block build cell's centre, and he
        // stands up to 90 blocks off it: on his far side the cards began well out past the drawn land. From the ring's
        // own inner edge (skip) instead; farcard.vert hides those under the live disc. BS_OLDFARGAP=1: rin - 24.
        let from = FarForest.oldGap || !skip.isFinite ? rin - 24 : max(0, skip)
        for l in lists { for t in l {
            let x = Float(Int(t.x) - cx) + 0.5, z = Float(Int(t.z) - cz) + 0.5
            let d: Float = (x * x + z * z).squareRoot()
            if d < from || d > FarForest.reach { continue }
            guard let ki = FarSprites.index(t.kind) else { continue }
            let fr = FarSprites.frame(t.kind)
            let base = Float(FarSprites.base(ki, variant: Int((t.hv >> 8) & 0xFF), snowy: t.snowy))
            // pos.w: the corner, the quarter turn, the frame's side and its centre's rise in quarter blocks
            let w: Float = Float(Int(t.hv & 3) * 4 + Int((fr.side * 4).rounded()) * 16 + Int((fr.rise * 4).rounded()) * 4096)
            let c = V4(base, t.tint.x, t.tint.y, t.tint.z)
            for k in 0..<4 { out.append(SimpleVert(pos: V4(x, t.y, z, w + Float(k)), color: c)) }
            n += 1
        } }
        lastCards = n
        return n
    }
    // Ledger 391 (Remington, Nov 20 17:03, his far scenery play: "a big gap between actually drawn land and the
    // compression that has nothing that can be seen"): inside the loaded disc a chunk not drawn yet is covered by the
    // ring's own ground (the gap cover) but stood bare: the cards began 24 blocks inside the disc's edge and the
    // shader hid any inside it. While the view climbs or he flies, that band was flat ground with no wood. Now the
    // trees inside the disc are cards too, by chunk; WorldRenderer.drawGaps draws a gap chunk's with its ground.
    // BS_OLDFARGAP=1: bare, as before.
    static let oldGap = Env.all["BS_OLDFARGAP"] == "1"
    func innerCards(cx: Int, cz: Int, rin: Float) -> [ChunkKey: [SimpleVert]] {
        var out: [ChunkKey: [SimpleVert]] = [:]
        if FarForest.oldGap || !FarForest.cards { return out }
        let to = rin - 24
        for l in lists { for t in l {
            let x = Float(Int(t.x) - cx) + 0.5, z = Float(Int(t.z) - cz) + 0.5
            let d: Float = (x * x + z * z).squareRoot()
            if d >= to || d < 40 { continue }         // (not right by him: a picture up close reads as one)
            guard let ki = FarSprites.index(t.kind) else { continue }
            let fr = FarSprites.frame(t.kind)
            let base = Float(FarSprites.base(ki, variant: Int((t.hv >> 8) & 0xFF), snowy: t.snowy))
            let w: Float = Float(Int(t.hv & 3) * 4 + Int((fr.side * 4).rounded()) * 16 + Int((fr.rise * 4).rounded()) * 4096)
            let c = V4(base, t.tint.x, t.tint.y, t.tint.z)
            let k = ChunkKey(x: floorDiv(Int(t.x), CS), z: floorDiv(Int(t.z), CS))
            for q in 0..<4 { out[k, default: []].append(SimpleVert(pos: V4(x, t.y, z, w + Float(q)), color: c)) }
        } }
        return out
    }
    static let deep = Env.all["BS_FARDEEP"] != nil          // (before: stand-ins all the way in under the loaded chunks)
    // A conifer's needles as the near trees draw them in shade (measured off a render: darker and yellower than the tint).
    static let darkConifer = V3(0.115, 0.175, 0.1)
    private var models: [Int: Model] = [:]
    private var scratch: [BlockID] = []

    private func model(_ kind: TreeKind, _ hv: UInt32) -> Model {
        let v = Int((hv >> 8) % UInt32(FarForest.variants))
        let key = kind.hashValue &* 31 &+ v
        if let m = models[key] { return m }
        let m = FarForest.bake(kind, variant: v, scratch: &scratch)
        models[key] = m
        return m
    }

    static func bake(_ kind: TreeKind, variant: Int, scratch b: inout [BlockID]) -> Model {
        let y0 = 80, top = 150
        if b.count != CS * CS * CH { b = [BlockID](repeating: AIR, count: CS * CS * CH) }
        for i in Chunk.index(0, y0, 0)..<Chunk.index(0, top, 0) { b[i] = AIR }
        let dirt = Blocks.id("dirt")
        for z in 0..<CS { for x in 0..<CS { b[Chunk.index(x, y0, z)] = dirt } }
        var rng = SRng(UInt64(variant) &* 0x9E37 &+ 77)
        b.withUnsafeMutableBufferPointer { buf in
            TreePlacer.build(TreeWriter(b: buf.baseAddress!, bx: 0, bz: 0), kind, 8, y0 + 1, 8, &rng)
        }
        var m = Model()
        let leafT = Mesher.leafT
        for y in (y0 + 1)..<top {
            var n: Float = 0, sx: Float = 0, sz: Float = 0
            for z in 0..<CS { for x in 0..<CS where leafT[Int(b[Chunk.index(x, y, z)])] { n += 1; sx += Float(x); sz += Float(z) } }
            guard n > 0 else { continue }
            // (a leaf blob rounds its blocks' corners off: a disc of the layer's area, a little proud)
            m.rings.append((Float(y - y0 - 1) + 0.5, (n / .pi).squareRoot() * 1.06, sx / n - 8, sz / n - 8))
        }
        guard let first = m.rings.first, let last = m.rings.last else { return m }
        m.trunk = first.y - 0.5
        // The outline's points, closed at both ends; then the reduced tiers: the point farthest from the outline so
        // far (as a polyline in y and r) is added until there are enough.
        let all = [(first.y - 0.7, Float(0), first.cx, first.cz)] + m.rings.map { ($0.y, $0.r, $0.cx, $0.cz) } + [(last.y + 0.8, Float(0), last.cx, last.cz)]
        for want in [5, 4, 3] {
            var keep = [0, all.count - 1]
            while keep.count < min(want, all.count) {
                var best = -1, err: Float = -1
                for i in 0..<all.count where !keep.contains(i) {
                    let k = keep.firstIndex { $0 > i }!
                    let a = all[keep[k - 1]], c = all[keep[k]]
                    let t = (all[i].0 - a.0) / max(0.001, c.0 - a.0)
                    let e = abs(all[i].1 - (a.1 + (c.1 - a.1) * t))
                    if e > err { err = e; best = i }
                }
                guard best >= 0 else { break }
                keep.append(best); keep.sort()
            }
            m.tiers.append(keep.map { (y: all[$0].0, r: all[$0].1, cx: all[$0].2, cz: all[$0].3) })
        }
        return m
    }

    // The stand-ins between `from` and the planned reach, as quads relative to the centre. Three bands past the loaded
    // edge: to 80 blocks the outline at 5 points and 5 sides over a trunk, to 140 at 4 points and 4 sides, then the
    // same while the wood thins to one in four, drawn wider. `plan` (before the ground is built) finds how far the
    // quad budget carries them: `planReach`, at most `reach`. Past it the ring's canopy lift is the wood, as before
    // the layer, so a thick wood is whole trees near and one mass far, never a sparse scatter or a cut edge.
    private var lists: [[Tree]] = []
    private(set) var planReach: Float = FarForest.reach
    private var full: Float = 0, thin: Float = 0, fine: Float = 0, far: Float = 0, thin0: Float = 0, edge: Float = 0
    private(set) var kmin: Float = 0.25               // the share of a wood's trees still standing at the far end
    private func keepAt(_ d: Float) -> Float { 1 - (1 - kmin) * min(1, max(0, (d - thin0) / (thin - thin0))) }
    // (under the loaded chunks a stand-in only shows while the view distance steps down: the second band's detail)
    private func bandAt(_ d: Float) -> Int { d < edge ? 1 : (d < fine ? 0 : (d < full ? 1 : (d < far ? 2 : 3))) }
    private func cost(_ t: Tree, _ d: Float, _ m: Model) -> Int {
        let b = bandAt(d)
        if b == 3 { return (t.cone ? 3 : 6) + (m.trunk > 6 ? 3 : 0) }
        return (b == 0 ? 22 : (b == 1 ? 12 : 8)) + (b >= 1 && m.trunk > 3.5 ? 3 : 0) + (b == 0 && t.snowy ? 5 : 0)
    }

    func plan(_ gen: WorldGen, cx: Int, cz: Int, rin: Float, from: Float) {
        // (No stand-ins deep under the loaded chunks: a dense taiga spent half the budget where nobody sees them, and
        // its woods ended 96 blocks past the edge. 40 blocks in covers the view distance stepping down.)
        let from = FarForest.deep ? from : max(from, rin - 40)
        let c = FarForest.cell
        let R = Int(FarForest.reach)
        fine = rin + 40; edge = rin
        let clear = FarTrack.clear(gen, cx: cx, cz: cz)
        lists.removeAll(keepingCapacity: true)
        var byRing = [Int](repeating: 0, count: R / 16 + 2)
        var all: [(Float, Tree)] = []
        for kz in floorDiv(cz - R, c)...floorDiv(cz + R, c) {
            for kx in floorDiv(cx - R, c)...floorDiv(cx + R, c) {
                var l = trees(gen, kx, kz)
                if !clear.isEmpty { l.removeAll { clear.contains(FarTrack.key(Int($0.x) >> 2, Int($0.z) >> 2)) } }
                for t in l {
                    let x = Float(Int(t.x) - cx) + 0.5, z = Float(Int(t.z) - cz) + 0.5
                    let d: Float = (x * x + z * z).squareRoot()
                    if d < from || d > FarForest.reach { continue }
                    all.append((d, t))
                }
                lists.append(l)
            }
        }
        // How soon the wood thins, and to what share, is set by the budget: an open wood keeps every tree to 140
        // blocks past the edge and one in four beyond; a taiga thins from 40 blocks to one in ten, each drawn wider, so
        // its cover holds out to the full reach.
        // Ledger 362: as cards every tree in reach is drawn, one quad each: nothing to budget.
        if FarForest.cards { planReach = FarForest.reach; full = FarForest.reach; far = full; thin0 = full; thin = full + 1; kmin = 1; return }
        // The ladder gives up detail before it gives up trees: a wood reads by how thick it stands, so the bands of
        // finer stand-ins shorten first (a far conifer is 3 quads), and only then does the wood thin, late and little.
        let ladder: [(Float, Float, Float, Float)] = [(140, 200, 200, 0.5), (100, 160, 200, 0.5), (60, 100, 200, 0.6), (40, 40, 200, 0.75),
                                                      (40, 40, 120, 0.6), (40, 40, 60, 0.45), (40, 40, 40, 0.3), (40, 40, 40, 0.15)]
        for (off, farOff, thinOff, km) in ladder {
            full = rin + off; far = rin + farOff; thin0 = rin + thinOff; thin = thin0 + 160; kmin = km
            for i in byRing.indices { byRing[i] = 0 }
            for (d, t) in all where Float((t.hv >> 20) & 0xFF) / 256 < keepAt(d) { byRing[Int(d) / 16] += cost(t, d, model(t.kind, t.hv)) }
            if byRing.reduce(0, +) <= FarForest.maxQuads { break }
        }
        var sum = 0
        planReach = FarForest.reach
        for (i, n) in byRing.enumerated() {
            sum += n
            if sum > FarForest.maxQuads { planReach = max(rin + 96, Float(i * 16)); break }
        }
    }

    func emit(_ gen: WorldGen, cx: Int, cz: Int, rin: Float, from: Float, into out: inout [SimpleVert]) {
        lastCards = 0
        if FarForest.cards { lastQuads = 0; lastSqueeze = 1; return }
        func nq(_ nx: Float, _ nz: Float) -> Float { ((nx * 0.5 + 0.5) * 1023).rounded() + ((nz * 0.5 + 0.5) * 1023).rounded() * 1024 }
        lastSqueeze = planReach / FarForest.reach
        let from = FarForest.deep ? from : max(from, rin - 40)
        let reachNow = planReach
        var quads = 0
        out.reserveCapacity(out.count + 4 * (FarForest.maxQuads + 4096))
        let snow = FarRing.snow
        for l in lists {
            for t in l {
                let x = Float(Int(t.x) - cx) + 0.5, z = Float(Int(t.z) - cz) + 0.5
                let d: Float = (x * x + z * z).squareRoot()
                if d < from || d > reachNow { continue }
                // (over the last 96 blocks of the reach the trees thin away as the ring's canopy mass rises)
                let keep: Float = keepAt(d) * min(1, max(0.02, (reachNow - d) / 96))
                if Float((t.hv >> 20) & 0xFF) / 256 >= keep { continue }
                if quads >= FarForest.maxQuads + 4096 { lastQuads = quads; return }
                let m = model(t.kind, t.hv)
                guard m.tiers.count == 3 else { continue }
                // Four bands: 5 points and 5 sides near, 4 and 4, 3 and 4, and far off 3 sides (a conifer one cone from
                // its widest tier to its tip), so a thick wood's every hill keeps trees to the full reach.
                let band = bandAt(d)
                let pts = m.tiers[min(band, 2)]
                let sides = band == 0 ? 5 : (band == 3 ? 3 : 4)
                let k0 = band == 3 && t.cone ? 1 : 0
                let wide: Float = min(1.5, 1 / keepAt(d).squareRoot())
                let turn: Float = Float(t.hv & 0xFF) / 256 * 2 * .pi
                let hTop: Float = max(1, pts[pts.count - 1].y)
                // One ring of vertices per outline point; a quad between each pair of neighbours on two rings.
                for k in k0..<(pts.count - 1) {
                    let a = pts[k], b = pts[k + 1]
                    // The surface's lean: up where the outline widens downward (a snow-catching top), down under it.
                    let dy: Float = (b.y - a.y) * t.size, dr: Float = (b.r - a.r) * wide
                    let ln: Float = max(0.001, (dy * dy + dr * dr).squareRoot())
                    let ny: Float = -dr / ln, nr: Float = dy / ln
                    func colour(_ p: (y: Float, r: Float, cx: Float, cz: Float)) -> V4 {
                        // Darker under the crown and inside, as the real leaves' own shade; snow where it faces up.
                        let shade: Float = 0.74 + 0.26 * min(1, max(0, p.y / hTop))
                        let c = t.leaf * shade
                        return V4(c, 0)
                    }
                    var ca = colour(a), cb = colour(b)
                    // Snow on the crown's top: the last segment, up to the tip. A real snowy conifer is dark needles with
                    // white lying on top, so near (band 0) the cap is its own ring with a hard edge, and far off only the
                    // tip lightens: white blended down the whole segment read as a grey tree.
                    var cap: (y: Float, r: Float, cx: Float, cz: Float)? = nil
                    if t.snowy && (k > 0 || band == 3) && b.r == 0 {
                        if band == 0 {
                            let f: Float = pts.count > 3 ? 0.28 : 0.55
                            cap = (a.y + (b.y - a.y) * f, a.r * (1 - f), a.cx + (b.cx - a.cx) * f, a.cz + (b.cz - a.cz) * f)
                        } else {
                            let lit: Float = (t.hv >> 16) & 1 == 0 ? 0.6 : 0.3
                            cb = V4(simd_mix(V3(cb.x, cb.y, cb.z), snow, V3(repeating: band == 3 ? lit * 0.6 + 0.1 : lit)), 0)
                        }
                    }
                    for sd in 0..<sides {
                        let a0: Float = turn + Float(sd) / Float(sides) * 2 * .pi, a1: Float = turn + Float(sd + 1) / Float(sides) * 2 * .pi
                        let c0 = cosf(a0), s0 = sinf(a0), c1 = cosf(a1), s1 = sinf(a1)
                        let am: Float = (a0 + a1) * 0.5
                        let q = nq(cosf(am) * nr * 0.9, sinf(am) * nr * 0.9)
                        let ra = a.r * wide, rb = b.r * wide
                        let ya: Float = t.y + a.y * t.size, yb: Float = t.y + b.y * t.size
                        out.append(SimpleVert(pos: V4(x + a.cx + c0 * ra, ya, z + a.cz + s0 * ra, q), color: ca))
                        out.append(SimpleVert(pos: V4(x + a.cx + c1 * ra, ya, z + a.cz + s1 * ra, q), color: ca))
                        out.append(SimpleVert(pos: V4(x + b.cx + c1 * rb, yb, z + b.cz + s1 * rb, q), color: cb))
                        out.append(SimpleVert(pos: V4(x + b.cx + c0 * rb, yb, z + b.cz + s0 * rb, q), color: cb))
                        if let m = cap {
                            // (the cap: the same faces from the snow line to the tip, white, a hair proud of the needles)
                            let rm = m.r * wide + 0.08, ym: Float = t.y + m.y * t.size
                            let w0 = V4(simd_mix(V3(ca.x, ca.y, ca.z), snow, V3(repeating: 0.8)), 0), w1 = V4(simd_mix(V3(cb.x, cb.y, cb.z), snow, V3(repeating: 0.9)), 0)
                            out.append(SimpleVert(pos: V4(x + m.cx + c0 * rm, ym, z + m.cz + s0 * rm, q), color: w0))
                            out.append(SimpleVert(pos: V4(x + m.cx + c1 * rm, ym, z + m.cz + s1 * rm, q), color: w0))
                            out.append(SimpleVert(pos: V4(x + b.cx + c1 * rb, yb + 0.08, z + b.cz + s1 * rb, q), color: w1))
                            out.append(SimpleVert(pos: V4(x + b.cx + c0 * rb, yb + 0.08, z + b.cz + s0 * rb, q), color: w1))
                        }
                    }
                    quads += sides + (cap != nil ? sides : 0)
                }
                if band >= 1 && m.trunk > (band == 3 ? 6 : 3.5) {
                    // A tall bare trunk under a far crown: three sides, or the crown hangs in the air.
                    let w: Float = (t.h > 15 ? 1.0 : 0.5) * wide
                    let bc = V4(t.bark, 0)
                    let yb: Float = t.y - 3, y0: Float = t.y + m.trunk + 1
                    for sd in 0..<3 {
                        let a0: Float = turn + Float(sd) / 3 * 2 * .pi, a1: Float = turn + Float(sd + 1) / 3 * 2 * .pi
                        let am: Float = (a0 + a1) * 0.5
                        let q = nq(cosf(am) * 0.9, sinf(am) * 0.9)
                        out.append(SimpleVert(pos: V4(x + cosf(a0) * w, yb, z + sinf(a0) * w, q), color: bc)); out.append(SimpleVert(pos: V4(x + cosf(a1) * w, yb, z + sinf(a1) * w, q), color: bc))
                        out.append(SimpleVert(pos: V4(x + cosf(a1) * w, y0, z + sinf(a1) * w, q), color: bc)); out.append(SimpleVert(pos: V4(x + cosf(a0) * w, y0, z + sinf(a0) * w, q), color: bc))
                    }
                    quads += 3
                }
                if band == 0 {
                    let w: Float = t.h > 15 ? 0.9 : 0.45
                    let bc = V4(t.bark, 0)
                    let yb: Float = t.y - 3, y0: Float = t.y + (m.trunk + 1) * t.size
                    let qx = nq(0.6, 0), qz = nq(0, 0.6)
                    out.append(SimpleVert(pos: V4(x - w, yb, z, qz), color: bc)); out.append(SimpleVert(pos: V4(x + w, yb, z, qz), color: bc))
                    out.append(SimpleVert(pos: V4(x + w, y0, z, qz), color: bc)); out.append(SimpleVert(pos: V4(x - w, y0, z, qz), color: bc))
                    out.append(SimpleVert(pos: V4(x, yb, z - w, qx), color: bc)); out.append(SimpleVert(pos: V4(x, yb, z + w, qx), color: bc))
                    out.append(SimpleVert(pos: V4(x, y0, z + w, qx), color: bc)); out.append(SimpleVert(pos: V4(x, y0, z - w, qx), color: bc))
                    quads += 2
                }
            }
        }
        if Env.all["BS_FARDEBUG"] != nil {
            var by = [Int](repeating: 0, count: 40), all = [Int](repeating: 0, count: 40)
            for l in lists { for t in l {
                let x = Float(Int(t.x) - cx) + 0.5, z = Float(Int(t.z) - cz) + 0.5
                let d: Float = (x * x + z * z).squareRoot()
                if d >= 640 { continue }
                all[Int(d) / 16] += 1
                if d < from || d > reachNow { continue }
                let keep: Float = keepAt(d) * min(1, max(0.02, (reachNow - d) / 96))
                if Float((t.hv >> 20) & 0xFF) / 256 < keep { by[Int(d) / 16] += 1 }
            } }
            print("fardebug rin \(rin) from \(from) reach \(reachNow) full \(full) far \(far) thin \(thin0)-\(thin) kmin \(kmin) centre \(cx),\(cz)\n all \(all)\n drawn \(by)")
        }
        lastQuads = quads
    }
    private(set) var lastQuads = 0
    var lastTrack = 0                              // (FarTrack's quads in the same build)
    private(set) var lastSqueeze: Float = 1
}
