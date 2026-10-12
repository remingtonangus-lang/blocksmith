import Foundation

// Trees for every surface biome and the ground vegetation pass.
// Tree candidates sit on a jittered 3-block grid; a candidate's biome, height and shape come only
// from world position (climate noise + the global density lattice), so trees straddling chunk borders
// are identical from both sides. Each chunk writes only its own blocks.
enum TreeKind {
    case oak, fancyOak, birch, tallBirch, spruce, pine, megaSpruce, megaPine, jungle, megaJungle, jungleBush
    case acacia, darkOak, swampOak, mangrove, cherry, hugeRed, hugeBrown, iceSpike, smallOak, paleOak
    case shrubOak, shrubSpruce, shrubAcacia
    // L1 trees (docs/status/look-upgrade.md part 3): woodland litter and the rare old giants.
    case deadOak, deadSpruce, stumpOak, stumpSpruce, stumpBirch, fallenOak, ancientOak
}

struct TreeWriter {
    let b: UnsafeMutablePointer<BlockID>
    let bx: Int, bz: Int
    @inline(__always) func inside(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        x >= bx && x < bx + CS && z >= bz && z < bz + CS && y > 0 && y < CH
    }
    func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID { inside(x, y, z) ? b[Chunk.index(x - bx, y, z - bz)] : AIR }
    // Logs replace air, plants, leaves and snow; leaves only fill air, plants and snow layers.
    func log(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
        guard inside(x, y, z) else { return }
        let i = Chunk.index(x - bx, y, z - bz)
        let c = b[i]
        if c == AIR || Blocks.replaceable[Int(c)] && !Blocks.isLiquid(c) || Mesher.leafT[Int(c)] { b[i] = id }
    }
    func leaf(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
        guard inside(x, y, z) else { return }
        let i = Chunk.index(x - bx, y, z - bz)
        let c = b[i]
        if c == AIR || (Blocks.replaceable[Int(c)] && !Blocks.isLiquid(c)) { b[i] = id }
    }
    func force(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) { if inside(x, y, z) { b[Chunk.index(x - bx, y, z - bz)] = id } }
}

enum TreePlacer {
    static func choose(_ biome: Biome, _ roll: Float, _ pick: Float, _ y: Int) -> TreeKind? {
        guard let k = chooseLiving(biome, roll, pick, y) else { return nil }
        // A few of the trees a wood would grow are instead dead snags, stumps, fallen trunks or, rarely, an ancient oak
        // (a second roll from the same pick, so it stays a pure function of position).
        let e = (pick * 7919).truncatingRemainder(dividingBy: 1)
        let woods = biome == .forest || biome == .flowerForest || biome == .darkForest || biome == .birchForest
            || biome == .oldGrowthBirchForest || biome == .windsweptForest
        switch k {
        case .oak, .fancyOak:
            let open = biome == .plains || biome == .sunflowerPlains || biome == .meadow
            if e < (open ? 0.05 : (woods ? 0.012 : 0)) { return .ancientOak }
            guard woods else { return k }
            if e < 0.042 { return .deadOak }
            if e < 0.062 { return .stumpOak }
            if e < 0.082 { return .fallenOak }
            return k
        case .birch:
            return woods && e < 0.02 ? .stumpBirch : k
        case .spruce, .pine:
            // Litter in the conifer woods only (never the lone spruces of snowy plains, hills or groves).
            let taiga = biome == .taiga || biome == .snowyTaiga || biome == .oldGrowthPineTaiga || biome == .oldGrowthSpruceTaiga
            guard taiga || biome == .windsweptForest else { return k }
            if e < 0.03 { return .deadSpruce }
            if e < 0.05 { return .stumpSpruce }
            return k
        default: return k
        }
    }

    private static func chooseLiving(_ biome: Biome, _ roll: Float, _ pick: Float, _ y: Int) -> TreeKind? {
        func p(_ v: Float) -> Bool { roll < v }
        switch biome {
        case .forest: return p(0.35) ? (pick < 0.1 ? .fancyOak : (pick < 0.8 ? .oak : .birch)) : nil
        case .flowerForest: return p(0.16) ? (pick < 0.1 ? .fancyOak : (pick < 0.55 ? .oak : .birch)) : nil
        case .birchForest: return p(0.35) ? .birch : nil
        case .oldGrowthBirchForest: return p(0.35) ? .tallBirch : nil
        case .darkForest:
            guard p(0.62) else { return nil }
            return pick < 0.07 ? (pick < 0.035 ? .hugeRed : .hugeBrown) : (pick < 0.75 ? .darkOak : (pick < 0.88 ? .oak : .birch))
        case .taiga, .snowyTaiga, .grove: return p(biome == .grove ? 0.3 : 0.35) ? (pick < 0.66 ? .spruce : .pine) : nil
        case .windsweptForest: return p(0.15) ? (pick < 0.5 ? .spruce : .oak) : nil
        case .oldGrowthPineTaiga: return p(0.35) ? (pick < 0.3 ? .megaPine : (pick < 0.7 ? .pine : .spruce)) : nil
        case .oldGrowthSpruceTaiga: return p(0.35) ? (pick < 0.3 ? .megaSpruce : .spruce) : nil
        case .savanna, .windsweptSavanna: return p(0.035) ? (pick < 0.8 ? .acacia : .oak) : (p(0.06) ? .shrubAcacia : nil)
        case .savannaPlateau: return p(0.07) ? (pick < 0.8 ? .acacia : .oak) : nil
        case .jungle:
            guard p(0.7) else { return nil }
            return pick < 0.1 ? .megaJungle : (pick < 0.4 ? .jungle : (pick < 0.9 ? .jungleBush : .fancyOak))
        case .sparseJungle: return p(0.1) ? (pick < 0.5 ? .jungle : .jungleBush) : nil
        case .bambooJungle: return p(0.35) ? (pick < 0.2 ? .jungle : .jungleBush) : nil
        case .woodedBadlands: return y > YOFF + 94 && p(0.15) ? .smallOak : nil
        case .windsweptHills, .windsweptGravellyHills: return p(0.02) ? (pick < 0.7 ? .oak : .spruce) : nil
        case .meadow: return p(0.002) ? (pick < 0.5 ? .fancyOak : .birch) : (p(0.008) ? .shrubOak : nil)
        case .cherryGrove: return p(0.18) ? .cherry : nil
        case .paleGarden: return p(0.32) ? (pick < 0.85 ? .paleOak : .darkOak) : nil
        case .swamp: return p(0.07) ? .swampOak : nil
        case .mangroveSwamp: return p(0.35) ? .mangrove : nil
        case .mushroomFields: return p(0.02) ? (pick < 0.5 ? .hugeRed : .hugeBrown) : nil
        case .plains, .sunflowerPlains: return p(0.002) ? (pick < 0.33 ? .fancyOak : .oak) : (p(0.007) ? .shrubOak : nil)
        case .snowyPlains: return p(0.004) ? .spruce : (p(0.012) ? .shrubSpruce : nil)
        case .iceSpikes: return p(0.035) ? .iceSpike : nil
        default: return nil
        }
    }

    static func place(_ b: inout [BlockID], _ cx: Int, _ cz: Int, gen: WorldGen, top: (Int, Int, Int) -> Int?) {
        let bx = cx * CS, bz = cz * CS
        let cell = 3, margin = 7
        // Surface structure footprints (plus a margin): no trees growing through manors, outposts, temples...
        var keepOut: [(IVec3, IVec3)] = []
        if let sc = gen.structures {
            for t in sc.types { for st in sc.startsNear(cx: cx, cz: cz, t) { keepOut.append((st.min, st.max)) } }
            for st in sc.fixed where st.max.x >= bx - 16 && st.min.x < bx + CS + 16 && st.max.z >= bz - 16 && st.min.z < bz + CS + 16 { keepOut.append((st.min, st.max)) }
        }
        func blocked(_ x: Int, _ y: Int, _ z: Int, reach: Int = 4, tall: Int = 14) -> Bool {
            keepOut.contains { mn, mx in x >= mn.x - reach && x <= mx.x + reach && z >= mn.z - reach && z <= mx.z + reach && y + tall >= mn.y && y - 2 <= mx.y }
        }
        b.withUnsafeMutableBufferPointer { buf in
            let w = TreeWriter(b: buf.baseAddress!, bx: bx, bz: bz)
            var sites: [(TreeKind, Int, Int, Int)] = []
            sites.reserveCapacity(64)
            for gz in floorDiv(bz - margin, cell)...floorDiv(bz + CS - 1 + margin, cell) {
                for gx in floorDiv(bx - margin, cell)...floorDiv(bx + CS - 1 + margin, cell) {
                    let hv = hash3(gx, 0, gz, gen.s32 ^ 0x7EE5)
                    let tx = gx * cell + Int(hv % 3), tz = gz * cell + Int((hv >> 2) % 3)
                    if tx < bx - margin || tx >= bx + CS + margin || tz < bz - margin || tz >= bz + CS + margin { continue }
                    let roll = Float((hv >> 4) & 0xFFFF) / 65536
                    if roll > 0.7 { continue }
                    // Each tree samples the climate with its own small offset, so species and density mix
                    // across a border (ecotone) instead of changing at a line; glades thin forests in patches.
                    let k = gen.terrain.column(tx, tz)
                    let dT = (hashf(tx, 2, tz, gen.s32 ^ 0x7EE8) - 0.5) * 0.16
                    let dW = (hashf(tx, 3, tz, gen.s32 ^ 0x7EE9) - 0.5) * 0.18
                    let dith = gen.terrain.biome(k, k.h, dT: dT, dW: dW)
                    let base = gen.terrain.biome(k, k.h)
                    let biome = dith.isDry == base.isDry ? dith : base
                    let glade = gen.flora.noise2(Float(tx) / 70 + 300, Float(tz) / 70)
                    let r2 = roll / max(0.3, 0.8 + 0.9 * glade)
                    let pick = hashf(tx, 1, tz, gen.s32 ^ 0x7EE6)
                    let hint = YOFF + Int(k.h) + 30
                    guard k.rv > 1.2, let kind = choose(biome, r2, pick, YOFF + Int(k.h)), let gy = top(tx, tz, hint),
                          gy >= SEA, gy - YOFF >= Int(floorf(k.wl)) else { continue }
                    if !keepOut.isEmpty && (kind == .ancientOak ? blocked(tx, gy, tz, reach: 8, tall: 18) : blocked(tx, gy, tz)) { continue }
                    // Soil check where we can see it (inside this chunk).
                    if w.inside(tx, gy, tz) {
                        let soil = Blocks.key(w.get(tx, gy, tz))
                        let ok = ["grass_block", "snowy_grass_block", "dirt", "podzol", "coarse_dirt", "mud", "mycelium", "moss_block", "pale_moss_block", "snow_block", "packed_ice", "red_sand"].contains(soil)
                        if !ok { continue }
                        let above = w.get(tx, gy + 1, tz)
                        if above != AIR && !Blocks.replaceable[Int(above)] && !Blocks.key(above).hasSuffix("_carpet") { continue }
                    }
                    sites.append((kind, tx, gy, tz))
                }
            }
            // Build only after every site passed its soil test on the bare terrain: a test that saw an earlier tree's
            // root, stump or fallen trunk would refuse a tree in one chunk and grow it in the next (half a tree, its
            // limbs hanging in the air: gencheck trunk_floating).
            for (kind, tx, gy, tz) in sites {
                var rng = SRng(UInt64(hash3(tx, gy, tz, gen.s32 ^ 0x7EE7)) | 1)
                build(w, kind, tx, gy + 1, tz, &rng)
            }
        }
    }

    static func blob(_ w: TreeWriter, _ x: Int, _ y: Int, _ z: Int, rx: Float, ry: Float, _ leaf: BlockID, _ rng: inout SRng) {
        let ix = Int(rx.rounded(.up)), iy = Int(ry.rounded(.up))
        // Crowns of trees in the 7-block margin mostly miss this chunk: skip them (and the outside voxels) before the
        // per-voxel hash (tree placement was half of world generation's time: bench gen phases, run 365).
        if x + ix < w.bx || x - ix >= w.bx + CS || z + ix < w.bz || z - ix >= w.bz + CS { return }
        for dy in -iy...iy { for dz in -ix...ix { for dx in -ix...ix {
            let qx = x + dx, qz = z + dz
            if qx < w.bx || qx >= w.bx + CS || qz < w.bz || qz >= w.bz + CS { continue }
            let e = Float(dx * dx + dz * dz) / (rx * rx) + Float(dy * dy) / (ry * ry)
            if e > 1 + (hashf(x + dx, y + dy, z + dz, 0x1EAF) - 0.5) * 0.3 { continue }
            w.leaf(x + dx, y + dy, z + dz, leaf)
        } } }
    }

    static func vines(_ w: TreeWriter, _ x: Int, _ y: Int, _ z: Int, _ r: Int, _ rng: inout SRng) {
        let vine = Blocks.id("vine")
        for _ in 0..<r * 3 {
            let dx = rng.range(-r - 1, r + 1), dz = rng.range(-r - 1, r + 1)
            guard abs(dx) == r + 1 || abs(dz) == r + 1 else { continue }
            let len = rng.range(1, 5)
            for k in 0..<len where w.get(x + dx, y - k, z + dz) == AIR { w.leaf(x + dx, y - k, z + dz, vine) }
        }
    }

    static func build(_ w: TreeWriter, _ kind: TreeKind, _ x: Int, _ y: Int, _ z: Int, _ rng: inout SRng) {
        let g = Blocks.id
        func trunk(_ h: Int, _ log: BlockID, wide: Bool = false) {
            for k in 0..<h {
                w.log(x, y + k, z, log)
                if wide { w.log(x + 1, y + k, z, log); w.log(x, y + k, z + 1, log); w.log(x + 1, y + k, z + 1, log) }
            }
            if w.inside(x, y - 1, z) && Blocks.key(w.get(x, y - 1, z)).contains("grass") { w.force(x, y - 1, z, DIRT) }
        }
        // The classic small-tree crown: two wide layers then two narrow ones, random corners.
        func crown(_ top: Int, _ leaf: BlockID, wide: Int = 2) {
            for dy in -3...0 {
                let r = dy <= -2 ? wide : 1
                for dz in -r...r { for dx in -r...r {
                    let corner = abs(dx) == r && abs(dz) == r
                    if corner && (dy == 0 || hashf(x + dx, top + dy, z + dz, 0xC0) < 0.5) { continue }
                    w.leaf(x + dx, top + dy, z + dz, leaf)
                } }
            }
        }
        // A connected limb from (sx, sy, sz) out along (dx, dz) for `len` steps, rising `rise` blocks evenly (one log per
        // step, never a gap: gencheck trunk_floating). Returns the tip.
        func limb(_ sx: Int, _ sy: Int, _ sz: Int, _ dx: Float, _ dz: Float, _ len: Int, rise: Int, _ log: BlockID) -> (Int, Int, Int) {
            var tip = (sx, sy, sz)
            for i in 1...max(1, len) {
                let t = Float(i)
                let lx = sx + Int((dx * t).rounded()), lz = sz + Int((dz * t).rounded())
                let ly = sy + Int((Float(rise) * t / Float(max(1, len))).rounded())
                if ly > tip.1 { for yy in (tip.1 + 1)...ly { w.log(tip.0, yy, tip.2, log) } }    // climb first: no vertical gap
                w.log(lx, ly, lz, log)
                tip = (lx, ly, lz)
            }
            return tip
        }
        // Root flare: a few logs hugging the trunk's foot, only where the ground under them is solid in this chunk
        // (never a root over a drop).
        func roots(_ log: BlockID, wide: Bool = false, chance: Float = 0.55) {
            let span = wide ? 1 : 0
            for (dx, dz) in [(-1, 0), (1 + span, 0), (0, -1), (0, 1 + span)] where rng.chance(chance) {
                for o in 0...span {
                    let rx = x + dx + (dz != 0 ? o : 0), rz = z + dz + (dx != 0 ? o : 0)
                    let tall = wide && rng.chance(0.4)        // drawn before the chunk-local test: every chunk's rng agrees
                    guard w.inside(rx, y - 1, rz), Blocks.opaque[Int(w.get(rx, y - 1, rz))], !Mesher.leafT[Int(w.get(rx, y - 1, rz))] else { continue }
                    w.log(rx, y, rz, log)
                    if tall { w.log(rx, y + 1, rz, log) }
                }
            }
        }
        switch kind {
        case .oak, .smallOak:
            // Four oaks (L1): a round dome with a low limb, a tall narrow one, a wide spreading one with three limbs,
            // and a forked twin leader. Small oaks (badlands) only the first two.
            let shape = kind == .smallOak ? rng.int(2) : rng.int(4)
            switch shape {
            case 0:
                let h = kind == .smallOak ? rng.range(3, 4) : rng.range(4, 6)
                trunk(h, LOG)
                blob(w, x, y + h, z, rx: 2.4 + rng.float() * 0.5, ry: 2.3, LEAVES, &rng)
                if h >= 5 {
                    let a = rng.float() * 2 * .pi
                    let tip = limb(x, y + h - 3, z, cosf(a), sinf(a), 2, rise: 1, LOG)
                    blob(w, tip.0, tip.1 + 1, tip.2, rx: 1.6, ry: 1.2, LEAVES, &rng)
                    roots(LOG, chance: 0.35)
                }
            case 1:
                let h = kind == .smallOak ? rng.range(4, 5) : rng.range(6, 8)
                trunk(h, LOG)
                blob(w, x, y + h - 1, z, rx: 1.9, ry: 2.8, LEAVES, &rng)
                w.leaf(x, y + h + 2, z, LEAVES)
            case 2:
                let h = rng.range(4, 5)
                trunk(h, LOG)
                let a0 = rng.float() * 2 * .pi
                for i in 0..<3 {
                    let a = a0 + Float(i) * 2.1 + rng.float() * 0.5
                    let tip = limb(x, y + h - 1, z, cosf(a), sinf(a), rng.range(2, 3), rise: 2, LOG)
                    blob(w, tip.0, tip.1 + 1, tip.2, rx: 2.3, ry: 1.5, LEAVES, &rng)
                }
                blob(w, x, y + h + 1, z, rx: 2.0, ry: 1.4, LEAVES, &rng)
                roots(LOG)
            default:
                let h = rng.range(3, 4)
                trunk(h, LOG)
                let a = rng.float() * 2 * .pi
                for s in [Float(1), -1] {
                    let tip = limb(x, y + h - 1, z, cosf(a) * s, sinf(a) * s, 2, rise: 3, LOG)
                    w.log(tip.0, tip.1 + 1, tip.2, LOG)
                    blob(w, tip.0, tip.1 + 2, tip.2, rx: 2.2, ry: 1.7, LEAVES, &rng)
                }
                roots(LOG, chance: 0.4)
            }
        case .birch, .tallBirch:
            // Four birches: the classic, a slender tall one with a narrow crown, a twin pair from one root, and one with a
            // kink partway up. Tall (old-growth) birches keep their height.
            let tall = kind == .tallBirch
            switch rng.int(4) {
            case 0:
                let h = tall ? rng.range(10, 14) : rng.range(6, 8)
                trunk(h, BIRCH_LOG); crown(y + h, BIRCH_LEAVES)
            case 1:
                let h = tall ? rng.range(12, 15) : rng.range(7, 9)
                trunk(h, BIRCH_LOG)
                blob(w, x, y + h - 1, z, rx: 1.6, ry: 3.2, BIRCH_LEAVES, &rng)
                w.leaf(x, y + h + 2, z, BIRCH_LEAVES)
            case 2:
                let h = tall ? rng.range(10, 13) : rng.range(5, 7)
                trunk(h, BIRCH_LOG); crown(y + h, BIRCH_LEAVES)
                let (dx, dz) = [(1, 0), (-1, 0), (0, 1), (0, -1)][rng.int(4)]
                // The twin forks off the foot of the trunk one block up (joined to it, never standing over a drop; the
                // same in every chunk, since it doesn't look at the ground).
                let h2 = h - rng.range(1, 2)
                for k in 1..<h2 { w.log(x + dx, y + k, z + dz, BIRCH_LOG) }
                blob(w, x + dx * 2, y + h2, z + dz * 2, rx: 1.7, ry: 1.8, BIRCH_LEAVES, &rng)
            default:
                let h = tall ? rng.range(10, 13) : rng.range(6, 8)
                let kinkAt = h / 2
                let (dx, dz) = [(1, 0), (-1, 0), (0, 1), (0, -1)][rng.int(4)]
                for k in 0..<kinkAt { w.log(x, y + k, z, BIRCH_LOG) }
                for k in (kinkAt - 1)..<h { w.log(x + dx, y + k, z + dz, BIRCH_LOG) }
                blob(w, x + dx, y + h, z + dz, rx: 2.0, ry: 2.2, BIRCH_LEAVES, &rng)
            }
        case .fancyOak:
            let h = rng.range(6, 10)
            trunk(h, LOG)
            blob(w, x, y + h - 1, z, rx: 3.2, ry: 2.4, LEAVES, &rng)
            for _ in 0..<rng.range(2, 4) {
                let a = rng.float() * 2 * .pi, len = Float(rng.range(2, 3))
                let bxo = Int((cosf(a) * len).rounded()), bzo = Int((sinf(a) * len).rounded())
                let by = y + h - rng.range(2, 4)
                // A connected limb out to the tip (one log per step, rising one at the tip); a log at len / 2 and
                // one at len left a gap for len 3 (gencheck trunk_floating: floating branch tips).
                let steps = max(1, max(abs(bxo), abs(bzo)))
                for i in 1...steps {
                    let t = Float(i) / Float(steps)
                    w.log(x + Int((Float(bxo) * t).rounded()), by + (i == steps ? 1 : 0), z + Int((Float(bzo) * t).rounded()), LOG)
                }
                blob(w, x + bxo, by + 2, z + bzo, rx: 2.2, ry: 1.6, LEAVES, &rng)
            }
        case .spruce, .pine:
            let variant = rng.int(4)              // spruce: classic, narrow, wide and ragged, high-crowned; pine: two
            let h = kind == .pine ? rng.range(7, 11) + (variant >= 2 ? 2 : 0) : rng.range(6, 9) + (variant == 3 ? 3 : 0)
            trunk(h, SPRUCE_LOG)
            if h >= 9 { roots(SPRUCE_LOG, chance: 0.3) }
            w.leaf(x, y + h, z, SPRUCE_LEAVES)
            if kind == .pine {
                let tiers = variant >= 2 ? [(0, 1), (-1, 1), (-2, 2), (-3, 1), (-4, 2), (-5, 1)] : [(0, 1), (-1, 2), (-2, 1), (-3, 2), (-4, 1)]
                for (dy, r) in tiers {
                    for dz in -r...r { for dx in -r...r where dx * dx + dz * dz <= r * r + (r > 1 ? 0 : 1) {
                        w.leaf(x + dx, y + h + dy, z + dz, SPRUCE_LEAVES)
                    } }
                }
            } else {
                // The tier under the tip is a leafy cross (a bare trunk block between the tip and the first tier read as a
                // stump poking out of every snowy crown: blind critic, run 395 snowy).
                let pattern = [[1, 2, 1, 2, 3, 2, 3], [1, 1, 1, 2, 1, 2, 2], [1, 2, 2, 3, 2, 3, 3], [1, 2, 1, 2, 3, 2, 3]][variant]
                var yy = y + h - 1, k = 0
                let bare = variant == 3 ? y + h / 2 : y + 2         // high-crowned: a bare lower trunk
                while yy >= bare {
                    // Wide and ragged: some tiers a step narrower, so the cone has gaps and shoulders.
                    let r = max(1, pattern[min(k, pattern.count - 1)] - (variant == 2 && k > 1 && hashf(x, yy, z, 0x5B) < 0.3 ? 1 : 0))
                    let round: Int = k == 0 ? 1 : r * r + 1
                    if r > 0 {
                        for dz in -r...r { for dx in -r...r where dx * dx + dz * dz <= round { w.leaf(x + dx, yy, z + dz, SPRUCE_LEAVES) } }
                    } else { w.leaf(x, yy, z, SPRUCE_LEAVES) }
                    yy -= 1; k += 1
                }
            }
        case .megaSpruce, .megaPine:
            let h = rng.range(13, 25)
            trunk(h, SPRUCE_LOG, wide: true)
            let crownStart = kind == .megaPine ? h - rng.range(4, 6) : h / 3
            for k in crownStart...h + 1 {
                let fromTop = h + 1 - k
                let r = min(5, fromTop / 2 + (fromTop % 2 == 0 ? 0 : 1))
                for dz in -r...r + 1 { for dx in -r...r + 1 {
                    let ddx = Float(dx) - 0.5, ddz = Float(dz) - 0.5
                    if ddx * ddx + ddz * ddz <= Float(r * r) + 0.5 { w.leaf(x + dx, y + k, z + dz, SPRUCE_LEAVES) }
                } }
            }
            // Podzol around the base.
            for dz in -3...4 { for dx in -3...4 where hashf(x + dx, y, z + dz, 0x9D) < 0.6 {
                let key = Blocks.key(w.get(x + dx, y - 1, z + dz))
                if key == "grass_block" || key == "dirt" { w.force(x + dx, y - 1, z + dz, g("podzol")) }
            } }
        case .jungle:
            let h = rng.range(4, 10)
            trunk(h, g("jungle_log"))
            crown(y + h, g("jungle_leaves"))
            vines(w, x, y + h - 2, z, 2, &rng)
        case .megaJungle:
            let h = rng.range(10, 25)
            let log = g("jungle_log"), leaf = g("jungle_leaves")
            trunk(h, log, wide: true)
            blob(w, x, y + h, z, rx: 4.5, ry: 2, leaf, &rng)
            var by = y + h - 4
            while by > y + 4 {
                let a = rng.float() * 2 * .pi
                let ex = x + Int((cosf(a) * 4).rounded()), ez = z + Int((sinf(a) * 4).rounded())
                // A connected limb from the (2x2) trunk out to the tip, rising one at the tip (the half-way log and
                // the tip log left gaps: gencheck trunk_floating).
                let steps = max(1, max(abs(ex - x), abs(ez - z)))
                for i in 1...steps {
                    let t = Float(i) / Float(steps)
                    let lx = x + Int((Float(ex - x) * t).rounded()), lz = z + Int((Float(ez - z) * t).rounded())
                    w.log(lx, by + (i == steps ? 1 : 0), lz, log)
                }
                blob(w, ex, by + 2, ez, rx: 2.5, ry: 1.2, leaf, &rng)
                by -= rng.range(3, 5)
            }
            vines(w, x, y + h - 1, z, 4, &rng)
        case .jungleBush:
            w.log(x, y, z, g("jungle_log"))
            blob(w, x, y + 1, z, rx: 2.4, ry: 1.3, LEAVES, &rng)
        case .acacia:
            let log = g("acacia_log"), leaf = g("acacia_leaves")
            let straight = rng.range(2, 4), lean = rng.range(1, 3)
            let (dx, dz) = [(1, 0), (-1, 0), (0, 1), (0, -1)][rng.int(4)]
            trunk(straight, log)
            var cx = x, cy = y + straight, cz = z
            for _ in 0..<lean { cx += dx; cz += dz; w.log(cx, cy, cz, log); cy += 1 }
            w.log(cx, cy, cz, log)
            for dz2 in -3...3 { for dx2 in -3...3 where !(abs(dx2) == 3 && abs(dz2) == 3) { w.leaf(cx + dx2, cy + 1, cz + dz2, leaf) } }
            for dz2 in -1...1 { for dx2 in -1...1 { w.leaf(cx + dx2, cy + 2, cz + dz2, leaf) } }
            if rng.chance(0.6) {
                // A second, shorter branch the other way.
                var ox = x, oy = y + straight - 1, oz = z
                for _ in 0..<rng.range(1, 2) { ox -= dx; oz -= dz; oy += 1; w.log(ox, oy, oz, log) }
                for dz2 in -2...2 { for dx2 in -2...2 where !(abs(dx2) == 2 && abs(dz2) == 2) { w.leaf(ox + dx2, oy + 1, oz + dz2, leaf) } }
            }
        case .darkOak:
            let h = rng.range(6, 8)
            let log = g("dark_oak_log"), leaf = g("dark_oak_leaves")
            trunk(h, log, wide: true)
            for dy in -1...1 {
                let r = dy == 1 ? 2 : (dy == 0 ? 4 : 3)
                for dz in -r...r + 1 { for dx in -r...r + 1 {
                    let ddx = Float(dx) - 0.5, ddz = Float(dz) - 0.5
                    if ddx * ddx + ddz * ddz <= Float(r * r) + 1 { w.leaf(x + dx, y + h + dy, z + dz, leaf) }
                } }
            }
        case .paleOak:
            // Ashbark: a 2x2 dark-oak-like trunk, flat pale crown, hanging moss curtains; sometimes a heart in the trunk.
            let h = rng.range(6, 9)
            let log = g("pale_oak_log"), leaf = g("pale_oak_leaves"), moss = g("pale_hanging_moss")
            trunk(h, log, wide: true)
            if rng.chance(0.12) { w.force(x + rng.int(2), y + rng.range(2, max(2, h - 3)), z + rng.int(2), g("creaking_heart")) }
            for dy in -1...1 {
                let r = dy == 1 ? 2 : 3
                for dz in -r...r + 1 { for dx in -r...r + 1 {
                    let ddx = Float(dx) - 0.5, ddz = Float(dz) - 0.5
                    if ddx * ddx + ddz * ddz <= Float(r * r) + 1 { w.leaf(x + dx, y + h + dy, z + dz, leaf) }
                } }
            }
            for _ in 0..<10 {
                let dx = rng.range(-3, 4), dz = rng.range(-3, 4)
                let len = rng.range(1, 4)
                for k in 0..<len where w.get(x + dx, y + h - 2 - k, z + dz) == AIR { w.leaf(x + dx, y + h - 2 - k, z + dz, moss) }
            }
        case .swampOak:
            let h = rng.range(5, 6)
            trunk(h, LOG)
            for dy in -3...0 {
                let r = dy <= -2 ? 3 : 2
                for dz in -r...r { for dx in -r...r where !(abs(dx) == r && abs(dz) == r) { w.leaf(x + dx, y + h + dy, z + dz, LEAVES) } }
            }
            vines(w, x, y + h - 3, z, 3, &rng)
        case .mangrove:
            let lift = rng.range(1, 3), h = rng.range(5, 8)
            let log = g("mangrove_log"), leaf = g("mangrove_leaves"), root = g("mangrove_roots")
            for k in lift..<(lift + h) { w.log(x, y + k, z, log) }
            // Prop roots arching down to the mud.
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1)] where rng.chance(0.75) {
                let reach = rng.range(1, 3)
                for k in 0...reach {
                    let rx = x + dx * k, rz = z + dz * k
                    var ry = y + lift - k
                    w.log(rx, ry, rz, root)
                    if k == reach { while ry > y - 3 && (w.get(rx, ry - 1, rz) == AIR || Blocks.isLiquid(w.get(rx, ry - 1, rz))) { ry -= 1; w.force(rx, ry, rz, root) } }
                }
            }
            blob(w, x, y + lift + h - 1, z, rx: 3, ry: 2, leaf, &rng)
        case .cherry:
            let h = rng.range(4, 6)
            let log = g("cherry_log"), leaf = g("cherry_leaves")
            trunk(h, log)
            for side in [-1, 1] {
                let alongX = rng.chance(0.5)
                var bxp = x, byp = y + h - 1, bzp = z
                for _ in 0..<rng.range(2, 3) {
                    if alongX { bxp += side } else { bzp += side }
                    byp += 1
                    w.log(bxp, byp, bzp, log)
                }
                blob(w, bxp, byp + 1, bzp, rx: 3.3, ry: 1.8, leaf, &rng)
            }
        case .hugeRed, .hugeBrown:
            let h = rng.range(5, 7)
            let stem = g("mushroom_stem")
            for k in 0..<h { w.log(x, y + k, z, stem) }
            if kind == .hugeBrown {
                let cap = g("brown_mushroom_block")
                for dz in -3...3 { for dx in -3...3 where !(abs(dx) == 3 && abs(dz) == 3) { w.leaf(x + dx, y + h, z + dz, cap) } }
            } else {
                let cap = g("red_mushroom_block")
                for dz in -1...1 { for dx in -1...1 { w.leaf(x + dx, y + h, z + dz, cap) } }
                for dy in 1...3 { for dz in -2...2 { for dx in -2...2 where (abs(dx) == 2 || abs(dz) == 2) && !(abs(dx) == 2 && abs(dz) == 2) {
                    w.leaf(x + dx, y + h - dy, z + dz, cap)
                } } }
            }
        case .shrubOak, .shrubSpruce, .shrubAcacia:
            // A knee-high woody shrub: one log and a low, lopsided leaf mound.
            let log = kind == .shrubSpruce ? SPRUCE_LOG : (kind == .shrubAcacia ? g("acacia_log") : LOG)
            let leaf = kind == .shrubSpruce ? SPRUCE_LEAVES : (kind == .shrubAcacia ? g("acacia_leaves") : LEAVES)
            w.log(x, y, z, log)
            blob(w, x + rng.range(-1, 1) / 2, y + 1, z + rng.range(-1, 1) / 2, rx: 1.4 + rng.float() * 0.8, ry: 0.9, leaf, &rng)
        case .deadOak, .deadSpruce:
            // A dead snag: bare trunk, a broken top and one or two bare stub limbs.
            let log = kind == .deadOak ? LOG : SPRUCE_LOG
            let h = rng.range(3, 6)
            trunk(h, log)
            for _ in 0..<rng.range(1, 2) where h >= 4 {
                let a = rng.float() * 2 * .pi
                _ = limb(x, y + rng.range(2, h - 1), z, cosf(a), sinf(a), rng.range(1, 2), rise: 1, log)
            }
            roots(log, chance: 0.3)
        case .stumpOak, .stumpSpruce, .stumpBirch:
            let log = kind == .stumpOak ? LOG : (kind == .stumpSpruce ? SPRUCE_LOG : BIRCH_LOG)
            let h = rng.range(1, 2)
            trunk(h, log)
            if rng.chance(0.5) { w.leaf(x, y + h, z, g("moss_carpet")) }
        case .fallenOak:
            // A fallen trunk of bark-all-round wood along the ground (each length only where the ground under it is solid
            // and it lies in air; decided per block, so both chunks of a trunk on a border agree), a stump at its root.
            let wood = g("oak_wood")
            w.log(x, y, z, LOG)
            let (dx, dz) = [(1, 0), (-1, 0), (0, 1), (0, -1)][rng.int(4)]
            let len = rng.range(4, 6)
            for i in 2..<(2 + len) {
                let fx = x + dx * i, fz = z + dz * i
                guard w.inside(fx, y, fz) else { continue }
                let under = w.get(fx, y - 1, fz), at = w.get(fx, y, fz)
                if Blocks.opaque[Int(under)] && !Mesher.leafT[Int(under)] && (at == AIR || Blocks.replaceable[Int(at)] && !Blocks.isLiquid(at)) {
                    w.force(fx, y, fz, wood)
                    if hashf(fx, y, fz, 0xFA11) < 0.3, w.get(fx, y + 1, fz) == AIR { w.leaf(fx, y + 1, fz, g("moss_carpet")) }
                }
            }
        case .ancientOak:
            // A rare old giant: a 2x2 trunk 9-12 tall with a flared foot, four or five heavy limbs and a broad crown.
            // Kept inside the 7-block placement margin (limb 3-4 + crown 3), so no chunk ever cuts one.
            let h = rng.range(9, 12)
            trunk(h, LOG, wide: true)
            roots(LOG, wide: true, chance: 0.8)
            let a0 = rng.float() * 2 * .pi
            let n = rng.range(4, 5)
            for i in 0..<n {
                let a = a0 + Float(i) * 2 * .pi / Float(n) + rng.float() * 0.4
                let sy = y + h - rng.range(2, 5)
                let tip = limb(x + (cosf(a) > 0 ? 1 : 0), sy, z + (sinf(a) > 0 ? 1 : 0), cosf(a), sinf(a), rng.range(3, 4), rise: 2, LOG)
                blob(w, tip.0, tip.1 + 1, tip.2, rx: 2.6, ry: 1.9, LEAVES, &rng)      // 2.8 reached 8 out now and then
            }
            blob(w, x, y + h + 1, z, rx: 3.0, ry: 2.2, LEAVES, &rng)
            blob(w, x + 1, y + h + 1, z + 1, rx: 3.0, ry: 2.2, LEAVES, &rng)
        case .iceSpike:
            let ice = g("packed_ice")
            let giant = rng.int(60) == 0
            let h = giant ? rng.range(30, 50) : rng.range(5, 15)
            let base = giant ? 3 : 1 + rng.int(2)
            for k in 0..<h {
                let r = max(0, Int(Float(base) * (1 - Float(k) / Float(h)) + 0.5))
                for dz in -r...r { for dx in -r...r where dx * dx + dz * dz <= r * r { w.log(x + dx, y + k - 1, z + dz, ice) } }
            }
        }
    }
}

extension WorldGen {
    // A reef at a column: the nearest coral head (one per 9-block cell, three in four cells hold one), its species,
    // height there (a dome with a rough top), an optional cap species, a branching finger, or the rim species when
    // the column lies just outside a head. World coordinates only, so heads cross chunk borders whole.
    func reef(_ wx: Int, _ wz: Int) -> (kind: Int, height: Int, cap: Int, finger: Int, rim: Int) {
        let cell = 9
        let gx = floorDiv(wx, cell), gz = floorDiv(wz, cell)
        var best: (d: Float, r: Float, k: Int, cap: Int, tall: Float, hx: Int, hz: Int) = (1e9, 0, 0, -1, 0, 0, 0)
        for dz in -1...1 { for dx in -1...1 {
            let cx = gx + dx, cz = gz + dz
            guard hashf(cx, 41, cz, s32 ^ 0x2EEF) < 0.78 else { continue }
            let ox = Float(cx * cell) + 1.5 + hashf(cx, 42, cz, s32 ^ 0x2EEF) * Float(cell - 3)
            let oz = Float(cz * cell) + 1.5 + hashf(cx, 43, cz, s32 ^ 0x2EEF) * Float(cell - 3)
            let rad = 1.6 + hashf(cx, 44, cz, s32 ^ 0x2EEF) * 2.6
            // Slightly oval heads: the distance is stretched along a per-head axis.
            let ang = hashf(cx, 45, cz, s32 ^ 0x2EEF) * .pi
            let ux = Float(wx) + 0.5 - ox, uz = Float(wz) + 0.5 - oz
            let a = ux * cosf(ang) + uz * sinf(ang), bb = -ux * sinf(ang) + uz * cosf(ang)
            let d = sqrtf(a * a * 0.7 + bb * bb * 1.3) / rad
            if d < best.d {
                let k = Int(hashf(cx, 46, cz, s32 ^ 0x2EEF) * 5) % 5
                let capH = hashf(cx, 47, cz, s32 ^ 0x2EEF)
                best = (d, rad, k, capH < 0.35 ? (k + 1 + Int(capH * 40) % 4) % 5 : -1, 1.5 + rad * 1.1, cx, cz)
            }
        } }
        guard best.d < 1.45 else { return (0, 0, -1, 0, -1) }
        if best.d >= 1 { return (best.k, 0, -1, 0, best.d < 1.3 ? best.k : (best.cap >= 0 ? best.cap : best.k)) }
        let rough = hashf(wx, 48, wz, s32 ^ 0x2EEF)
        let hgt = max(1, Int((best.tall * (1 - best.d * best.d) + rough * 1.2).rounded(.down)))
        // Fingers on the branching kinds (tube 0, fire 3, horn 4), on about a third of a head's top columns.
        let branching = best.k == 0 || best.k == 3 || best.k == 4
        let finger = branching && rough > 0.62 && best.d < 0.8 ? 1 + Int(hashf(wx, 49, wz, s32 ^ 0x2EEF) * 3) : 0
        return (best.k, hgt, best.cap, finger, -1)
    }

    // Ground plants, flowers, sugar cane, cacti, water plants and icebergs, per column (own chunk only).
    func placeVegetation(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ biomes: [Biome], _ rng: inout SRng, cols: [Terrain.Column]? = nil) {
        let g = Blocks.id
        let grassy: Set<BlockID> = [GRASS, SNOWY_GRASS, DIRT, g("podzol"), g("coarse_dirt"), g("moss_block")]
        // Looked up once: these ran per column (several string dictionary lookups each).
        let iceID = g("ice"), snowLayerID = g("snow"), clayID = g("clay"), mudID = g("mud"), seagrassID = g("seagrass"), redSandID = g("red_sand")
        // Playtest Oct 9 PM #3 ("too much vegetation; grass about 1/8; cactus far too common; review all plants"):
        // `calm` scales each plant against the v78 densities (old = 1). Measured per biome in
        // docs/status/evidence/2026-10-09-pm/plants.md; check: `--questbugs --only pm9b`.
        let old = plantsBeforePM9
        func calm(_ v: Float) -> Float { old ? 1 : v }
        func flowerFor(_ biome: Biome, _ h: Float, _ wx: Int, _ wz: Int) -> BlockID {
            let pick = Int(h * 997) % 100
            switch biome {
            case .flowerForest:
                let all = ["dandelion", "poppy", "allium", "azure_bluet", "red_tulip", "orange_tulip", "white_tulip", "pink_tulip",
                           "oxeye_daisy", "cornflower", "lily_of_the_valley"]
                let c = flora.noise2(Float(wx) / 24 + 90, Float(wz) / 24 + 90)
                return g(all[max(0, min(all.count - 1, Int((c + 0.6) / 1.2 * Float(all.count))))])
            case .meadow:
                return g(["allium", "azure_bluet", "oxeye_daisy", "cornflower", "dandelion", "poppy"][pick % 6])
            case .swamp: return g("blue_orchid")
            case .forest, .birchForest, .oldGrowthBirchForest: return g(["dandelion", "poppy", "lily_of_the_valley"][pick % 3])
            case .cherryGrove: return g("pink_petals")
            default:
                if pick < 45 { return YELLOW_FLOWER }
                if pick < 80 { return RED_FLOWER }
                return g(["azure_bluet", "oxeye_daisy", "cornflower", "red_tulip", "orange_tulip", "white_tulip", "pink_tulip"][pick % 7])
            }
        }
        for lz in 0..<CS { for lx in 0..<CS {
            let biome = biomes[lx + lz * CS]
            let wx = bx + lx, wz = bz + lz
            var y = CH - 2
            while y > 1 && b[Chunk.index(lx, y, lz)] == AIR { y -= 1 }
            let i = Chunk.index(lx, y, lz)
            let ground = b[i]
            let h = hashf(wx, 7, wz, s32 ^ 0x3C3C)
            let h2 = hashf(wx, 9, wz, s32 ^ 0x3C3D)
            guard y + 3 < CH else { continue }
            // Water columns: plants on the floor, lily pads on the surface.
            if ground == WATER || ground == iceID {
                var fy = y
                while fy > 1 && (b[Chunk.index(lx, fy, lz)] == WATER) { fy -= 1 }
                let depth = y - fy
                let floor = b[Chunk.index(lx, fy, lz)]
                guard floor == SAND || floor == GRAVEL || floor == DIRT || floor == clayID || floor == mudID else { continue }
                if biome == .warmOcean && depth > 2 {
                    // Reefs (Oct 11 playtest P22, "the coral is very low effort": every column drew its own random
                    // species and pillar height, a speckle of one-block posts). Now coral heads: domed mounds of one
                    // species each, a second species capping some, branching fingers on the branching kinds, fans
                    // round the rim, sand lanes and seagrass between the heads.
                    let species = ["tube", "brain", "bubble", "fire", "horn"]
                    let r = reef(wx, wz)
                    let room = depth - 2
                    if r.height > 0 && room > 0 {
                        let hgt = min(r.height, room)
                        for k in 1...hgt { b[Chunk.index(lx, fy + k, lz)] = g("\(species[k == hgt && r.cap >= 0 ? r.cap : r.kind])_coral_block") }
                        var top = fy + hgt
                        // Branching kinds (tube, horn, fire): thin fingers off the top of the head.
                        if r.finger > 0 && top + r.finger <= fy + room {
                            for k in 1...r.finger { b[Chunk.index(lx, top + k, lz)] = g("\(species[r.kind])_coral_block") }
                            top += r.finger
                        }
                        if top + 1 <= fy + room + 1 && h < 0.55 { b[Chunk.index(lx, top + 1, lz)] = g("\(species[r.cap >= 0 && h < 0.3 ? r.cap : r.kind])_coral") }
                    } else if r.rim >= 0 && h < 0.6 {
                        b[Chunk.index(lx, fy + 1, lz)] = g("\(species[r.rim])_coral")              // fans round a head
                    } else if h < 0.3 + 0.4 * max(0, flora.noise2(Float(wx) / 14 + 300, Float(wz) / 14 + 300)) {
                        b[Chunk.index(lx, fy + 1, lz)] = seagrassID                               // meadows in the lanes
                    }
                } else if (biome.isOcean || biome.isRiver) && biome != .frozenOcean && biome != .deepFrozenOcean {
                    let kelpPatch = flora.noise2(Float(wx) / 18 + 700, Float(wz) / 18 + 700) > 0.2
                    if kelpPatch && h < 0.12 && depth > 3 && biome != .warmOcean && !biome.isRiver {
                        let len = min(depth - 2, 1 + Int(h2 * h2 * Float(depth)))
                        for k in 1...len { b[Chunk.index(lx, fy + k, lz)] = g("kelp") }
                    } else {
                        // Seagrass grows in meadows (dense where a low-frequency noise is high, a few strands elsewhere)
                        // instead of 40 % of every seabed column (underwater.png: a uniform field of sticks).
                        let meadow = flora.noise2(Float(wx) / 22 + 410, Float(wz) / 22 + 410)
                        let t: Float = max(0, min(1, (meadow + 0.05) / 0.35))
                        let chance: Float = 0.04 + 0.5 * t * t
                        // Two blocks deep at least: in one-deep shallows the seagrass took the only water block and stood
                        // dry in a hole in the surface (kelpcheck: ~300 per 1369 chunks, all at sea level).
                        if h2 < chance && depth >= 2 { b[Chunk.index(lx, fy + 1, lz)] = seagrassID }
                    }
                } else if biome == .swamp || biome == .mangroveSwamp {
                    // Pads grow in rafts (a patch noise), a few strays elsewhere: open ponds still show water.
                    let raft = flora.noise2(Float(wx) / 9 + 57, Float(wz) / 9 - 113)
                    let padChance: Float = raft > 0.15 ? 0.45 : 0.04
                    if depth <= 3 && h < padChance && ground == WATER { b[Chunk.index(lx, y + 1, lz)] = g("lily_pad") }
                    else if h > 0.8 && depth >= 2 { b[Chunk.index(lx, fy + 1, lz)] = seagrassID }
                }
                continue
            }
            let above = Chunk.index(lx, y + 1, lz)
            guard b[above] == AIR || b[above] == snowLayerID else { continue }
            if b[above] == snowLayerID { continue }
            // Sugar cane beside water.
            if (ground == GRASS || ground == SAND || ground == DIRT) && h < 0.12 * calm(0.4) {
                let nearWater = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { d in
                    let nx = lx + d.0, nz = lz + d.1
                    return nx >= 0 && nx < CS && nz >= 0 && nz < CS && b[Chunk.index(nx, y, nz)] == WATER
                }
                if nearWater {
                    for k in 1...(1 + Int(h2 * 3)) { b[Chunk.index(lx, y + k, lz)] = g("sugar_cane") }
                    continue
                }
            }
            switch biome {
            case .desert, .badlands, .erodedBadlands, .woodedBadlands:
                if ground == SAND || ground == redSandID {
                    // Cactus: one every ~16-20 blocks of desert (it was one every ~11, in clumps of 1-3 tall).
                    if h < (biome == .desert ? 0.008 : 0.004) * calm(0.35) {
                        let clear = [(1, 0), (-1, 0), (0, 1), (0, -1)].allSatisfy { d in
                            let nx = lx + d.0, nz = lz + d.1
                            return nx < 0 || nx >= CS || nz < 0 || nz >= CS || b[Chunk.index(nx, y + 1, nz)] == AIR
                        }
                        if clear {
                            let len = 1 + Int(h2 * 3)
                            for k in 1...len { b[Chunk.index(lx, y + k, lz)] = CACTUS }
                            if hashf(wx, 11, wz, s32 ^ 0x3C3E) < 0.25 { b[Chunk.index(lx, y + len + 1, lz)] = g("cactus_flower") }
                        }
                    } else if h >= 0.008 && h < 0.008 + 0.007 * calm(0.75) { b[above] = g("dead_bush") }
                    else if h >= 0.015 && h < 0.015 + 0.015 * calm(0.3) { b[above] = g("short_dry_grass") }
                    else if h >= 0.03 && h < 0.03 + 0.006 * calm(0.3) { b[above] = g("tall_dry_grass") }
                } else if grassy.contains(ground) && h < 0.1 * calm(0.11) { b[above] = TALL_GRASS }
                continue
            case .mushroomFields:
                if h < 0.012 * calm(0.75) { b[above] = h2 < 0.5 ? g("red_mushroom") : g("brown_mushroom") }
                continue
            default: break
            }
            guard grassy.contains(ground) else { continue }
            var grassP: Float = 0.1, flowerP: Float = 0.004, fernP: Float = 0, tallP: Float = 0
            switch biome {
            case .plains, .sunflowerPlains: grassP = 0.3; flowerP = 0.012; tallP = 0.04
            case .meadow: grassP = 0.45; flowerP = 0.1; tallP = 0.08
            case .forest, .birchForest, .oldGrowthBirchForest: grassP = 0.14; flowerP = 0.01
            case .flowerForest: grassP = 0.1; flowerP = 0.35
            case .darkForest: grassP = 0.12; flowerP = 0
            case .paleGarden: grassP = 0.06; flowerP = 0
            case .taiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga: grassP = 0.06; fernP = 0.12; tallP = 0.02
            case .jungle, .sparseJungle, .bambooJungle: grassP = 0.25; fernP = 0.1; tallP = 0.03
            case .savanna, .savannaPlateau, .windsweptSavanna: grassP = 0.3; tallP = 0.06
            case .swamp: grassP = 0.12; flowerP = 0.01
            case .cherryGrove: grassP = 0.12; flowerP = 0.2
            case .windsweptHills, .windsweptForest, .windsweptGravellyHills: grassP = 0.06
            case .beach, .stonyShore, .snowyBeach, .river, .frozenRiver: grassP = 0.02
            default: grassP = 0.04; flowerP = 0
            }
            if biome.snows(at: y + 1) { continue }
            // Riverside: lusher grass and ferns along channels and lake shores.
            if let cols, cols[lx + lz * CS].rv < 2.5 { grassP += 0.2; tallP += 0.06; fernP += 0.04 }
            // Specials.
            if (biome == .taiga || biome == .oldGrowthPineTaiga || biome == .oldGrowthSpruceTaiga) && h > 0.995 {
                b[above] = g("sweet_berry_bush_3"); continue
            }
            if (biome == .jungle || biome == .bambooJungle || biome == .sparseJungle) && h > 0.996 { b[above] = g("melon"); continue }
            if biome == .bambooJungle && h2 < 0.25 {
                for k in 1...(3 + Int(h * 10)) where y + k < CH - 1 { b[Chunk.index(lx, y + k, lz)] = g("bamboo") }
                continue
            }
            if biome == .sunflowerPlains && h > 0.97 {
                b[above] = g("sunflower"); b[Chunk.index(lx, y + 2, lz)] = g("sunflower") + 1; continue
            }
            if (biome == .darkForest || biome == .oldGrowthSpruceTaiga) && h > 1 - 0.015 * calm(0.5) {
                b[above] = h2 < 0.5 ? g("red_mushroom") : g("brown_mushroom"); continue
            }
            if biome == .paleGarden {
                if h > 0.985 { b[above] = g("closed_eyeblossom"); continue }
                let patch = flora.noise2(Float(wx) / 9 + 300, Float(wz) / 9 + 300)
                if patch > 0.25 { b[i] = g("pale_moss_block"); if h2 < 0.45 { b[above] = g("pale_moss_carpet") }; continue }
            }
            if h > 0.9993 && ground == GRASS { b[above] = g("pumpkin"); continue }
            // Newer ground cover: leaf litter under forests, wildflowers, bushes, firefly bushes by swamps.
            switch biome {
            case .forest, .darkForest, .birchForest, .oldGrowthBirchForest, .windsweptForest:
                let litter: Float = 0.06 * calm(0.35), wild: Float = 0.02 * calm(0.6)
                if h > 1 - litter { b[above] = g("leaf_litter"); continue }
                if (biome == .birchForest || biome == .oldGrowthBirchForest) && h > 1 - litter - wild { b[above] = g("wildflowers"); continue }
            case .meadow:
                if h > 0.93 { b[above] = g("wildflowers"); continue }
            case .plains, .sunflowerPlains, .windsweptHills:
                if h > 0.993 { b[above] = g("bush"); continue }
            case .swamp, .mangroveSwamp:
                if h > 1 - 0.025 * calm(0.4) { b[above] = g("firefly_bush"); continue }
            case .jungle, .sparseJungle, .bambooJungle:
                if h > 1 - 0.05 * calm(0.4) { b[above] = g("bush"); continue }
            case .savanna, .savannaPlateau, .windsweptSavanna:
                if h > 1 - 0.03 * calm(0.3) { b[above] = g("short_dry_grass"); continue }
            default: break
            }
            // A calmer ground (playtest v78: "too noisy"): no tall grass, about a third of the short grass, half the
            // flowers and ferns (themed biomes keep their relative richness).
            let rawGrass = grassP, rawTall = tallP
            grassP *= 0.35; flowerP *= 0.5; fernP *= 0.5; tallP = 0
            // PM9: short grass about 1/8 again (0.11: measured 0.10-0.12 over nine biomes), ferns ~1/3; flowers stay
            // (themed flower biomes a little calmer).
            grassP *= calm(0.11); fernP *= calm(0.35)
            // G18 (Oct 11 playtest: "plain grass looks barren"): the calm speckle stays between them, but grass now grows
            // in patches (a low-frequency noise): thick in a patch's heart, with a few tall tufts there, thinning to
            // the calm ground at its edge. Clumps read as a meadow where the old uniform speckle read as noise (v78).
            if !old && rawGrass > 0.05 {
                let patch = flora.noise2(Float(wx) / 11 + 520, Float(wz) / 11 - 340)
                let t = max(0, min(1, (patch - 0.02) / 0.28)), t2 = t * t
                grassP += (t + t2) * rawGrass * 1.0
                if t > 0.8 { tallP = max(rawTall, 0.03) * 0.5 }
            }
            if biome == .flowerForest || biome == .cherryGrove || biome == .meadow { flowerP *= calm(0.7) }
            if h < flowerP {
                if biome == .flowerForest && h2 < 0.15 {
                    let tall = ["lilac", "rose_bush", "peony"][Int(h2 * 20) % 3]
                    b[above] = g(tall); b[Chunk.index(lx, y + 2, lz)] = g(tall) + 1
                } else { b[above] = flowerFor(biome, h2, wx, wz) }
            } else if h < flowerP + tallP {
                b[above] = g("tall_grass"); b[Chunk.index(lx, y + 2, lz)] = g("tall_grass") + 1
            } else if h < flowerP + tallP + fernP {
                if h2 < 0.3 { b[above] = g("large_fern"); b[Chunk.index(lx, y + 2, lz)] = g("large_fern") + 1 } else { b[above] = g("fern") }
            } else if h < flowerP + tallP + fernP + grassP {
                b[above] = TALL_GRASS
            }
        } }
        // Fallen trunks on forest floors, lying along x or z, sometimes with moss or mushrooms on top.
        let fallen: [Biome: String] = [.forest: "oak_log", .flowerForest: "oak_log", .birchForest: "birch_log", .oldGrowthBirchForest: "birch_log",
                                       .darkForest: "dark_oak_log", .taiga: "spruce_log", .oldGrowthPineTaiga: "spruce_log",
                                       .oldGrowthSpruceTaiga: "spruce_log", .snowyTaiga: "spruce_log", .jungle: "jungle_log", .windsweptForest: "spruce_log"]
        if rng.chance(0.3) {
            let lx0 = rng.range(2, 9), lz0 = rng.range(2, 9), len = rng.range(3, 5), alongX = rng.chance(0.5)
            if let key = fallen[biomes[lx0 + lz0 * CS]], Blocks.has(key + (alongX ? "[x]" : "[z]")) {
                let log = g(key + (alongX ? "[x]" : "[z]"))
                var y = CH - 2
                while y > 1 && !Blocks.opaque[Int(b[Chunk.index(lx0, y, lz0)])] { y -= 1 }
                var ok = y > SEA
                for k in 0..<len where ok {
                    let lx = lx0 + (alongX ? k : 0), lz = lz0 + (alongX ? 0 : k)
                    let ground = b[Chunk.index(lx, y, lz)], above = b[Chunk.index(lx, y + 1, lz)]
                    if !Blocks.opaque[Int(ground)] || !(above == AIR || Blocks.replaceable[Int(above)]) || Blocks.isLiquid(above) { ok = false }
                }
                if ok {
                    for k in 0..<len {
                        let lx = lx0 + (alongX ? k : 0), lz = lz0 + (alongX ? 0 : k)
                        b[Chunk.index(lx, y + 1, lz)] = log
                        let top = Chunk.index(lx, y + 2, lz)
                        if b[top] == AIR || Blocks.replaceable[Int(b[top])] {
                            let h = hashf(bx + lx, y, bz + lz, s32 ^ 0xFA11)
                            b[top] = h < 0.3 ? g("moss_carpet") : (h < 0.4 ? g("brown_mushroom") : (h < 0.45 ? g("red_mushroom") : AIR))
                        }
                    }
                }
            }
        }
        // Boulders of mossy cobble, cobble and andesite in rocky, cold and upland country.
        let rocky: Set<Biome> = [.taiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga, .snowyPlains, .snowyTaiga, .windsweptHills,
                                 .windsweptGravellyHills, .windsweptForest, .grove, .meadow, .stonyShore, .plains]
        if rng.chance(0.4) {
            let lx0 = rng.range(3, 12), lz0 = rng.range(3, 12)
            let biome = biomes[lx0 + lz0 * CS]
            if rocky.contains(biome) && (biome != .plains || rng.chance(0.2)) {
                var y = CH - 2
                while y > 1 && !Blocks.opaque[Int(b[Chunk.index(lx0, y, lz0)])] { y -= 1 }
                let r = 1.1 + rng.float() * 1.3
                let mats = [g("mossy_cobblestone"), COBBLE, g("andesite"), g("mossy_cobblestone")]
                let ground = Blocks.key(b[Chunk.index(lx0, y, lz0)])
                if y > SEA && (ground.contains("grass") || ground == "podzol" || ground == "dirt" || ground == "coarse_dirt" || ground == "stone" || ground == "gravel") {
                    for dy in -1...2 { for dz in -3...3 { for dx in -3...3 {
                        let lx = lx0 + dx, lz = lz0 + dz, yy = y + dy
                        guard lx >= 0 && lx < CS && lz >= 0 && lz < CS && yy < CH - 1 else { continue }
                        let e = Float(dx * dx + dz * dz) / (r * r) + Float(dy * dy) / (r * r * 0.7)
                        if e > 1 + (hashf(bx + lx, yy, bz + lz, s32 ^ 0xB01D) - 0.5) * 0.6 { continue }
                        let i = Chunk.index(lx, yy, lz)
                        if b[i] == AIR || Blocks.replaceable[Int(b[i])] || dy <= 0 {
                            b[i] = mats[Int(hashf(bx + lx, yy, bz + lz, s32 ^ 0xB01E) * 4) % 4]
                            // No grass or flowers left standing on the boulder's rim (gencheck plant_soil).
                            let up = Chunk.index(lx, yy + 1, lz)
                            if StructWriter.soilPlant[Int(b[up])] { b[up] = AIR }
                        }
                    } } }
                }
            }
        }
        // Icebergs in frozen oceans (1 in 12 chunks).
        if biomes.contains(where: { $0 == .frozenOcean || $0 == .deepFrozenOcean }) && rng.int(12) == 0 {
            let cxr = rng.range(4, 11), czr = rng.range(4, 11)
            let ice = g("packed_ice"), blue = g("blue_ice")
            let hgt = rng.range(6, 16), r = Float(rng.range(3, 6))
            for dy in -8...hgt { for dz in -6...6 { for dx in -6...6 {
                let lx = cxr + dx, lz = czr + dz, y = SEA + dy
                guard lx >= 0 && lx < CS && lz >= 0 && lz < CS && y > 0 && y < CH else { continue }
                let rr = dy > 0 ? r * (1 - Float(dy) / Float(hgt + 1)) : r * (1 + Float(dy) / 10)
                if Float(dx * dx + dz * dz) <= rr * rr {
                    let i = Chunk.index(lx, y, lz)
                    if b[i] == WATER || b[i] == AIR || b[i] == g("ice") { b[i] = hashf(lx, y, lz, 0x1CE) < 0.1 ? blue : ice }
                }
            } } }
        }
    }
}
