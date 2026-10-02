import Foundation

// Trees for every surface biome and the ground vegetation pass.
// Tree candidates sit on a jittered 3-block grid; a candidate's biome, height and shape come only
// from world position (climate noise + the global density lattice), so trees straddling chunk borders
// are identical from both sides. Each chunk writes only its own blocks.
enum TreeKind {
    case oak, fancyOak, birch, tallBirch, spruce, pine, megaSpruce, megaPine, jungle, megaJungle, jungleBush
    case acacia, darkOak, swampOak, mangrove, cherry, hugeRed, hugeBrown, iceSpike, smallOak, paleOak
    case shrubOak, shrubSpruce, shrubAcacia
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
        if c == AIR || Blocks.replaceable[Int(c)] && !Blocks.isLiquid(c) || Blocks.key(c).hasSuffix("_leaves") { b[i] = id }
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
        func blocked(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            keepOut.contains { mn, mx in x >= mn.x - 4 && x <= mx.x + 4 && z >= mn.z - 4 && z <= mx.z + 4 && y + 14 >= mn.y && y - 2 <= mx.y }
        }
        b.withUnsafeMutableBufferPointer { buf in
            let w = TreeWriter(b: buf.baseAddress!, bx: bx, bz: bz)
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
                    let biome = gen.terrain.biome(k, k.h, dT: dT, dW: dW)
                    let glade = gen.flora.noise2(Float(tx) / 70 + 300, Float(tz) / 70)
                    let r2 = roll / max(0.3, 0.8 + 0.9 * glade)
                    let pick = hashf(tx, 1, tz, gen.s32 ^ 0x7EE6)
                    let hint = YOFF + Int(k.h) + 30
                    guard k.rv > 1.2, let kind = choose(biome, r2, pick, YOFF + Int(k.h)), let gy = top(tx, tz, hint),
                          gy >= SEA, gy - YOFF >= Int(floorf(k.wl)) else { continue }
                    if !keepOut.isEmpty && blocked(tx, gy, tz) { continue }
                    // Soil check where we can see it (inside this chunk).
                    if w.inside(tx, gy, tz) {
                        let soil = Blocks.key(w.get(tx, gy, tz))
                        let ok = ["grass_block", "snowy_grass_block", "dirt", "podzol", "coarse_dirt", "mud", "mycelium", "moss_block", "pale_moss_block", "snow_block", "packed_ice", "red_sand"].contains(soil)
                        if !ok { continue }
                        let above = w.get(tx, gy + 1, tz)
                        if above != AIR && !Blocks.replaceable[Int(above)] && !Blocks.key(above).hasSuffix("_carpet") { continue }
                    }
                    var rng = SRng(UInt64(hash3(tx, gy, tz, gen.s32 ^ 0x7EE7)) | 1)
                    build(w, kind, tx, gy + 1, tz, &rng)
                }
            }
        }
    }

    static func blob(_ w: TreeWriter, _ x: Int, _ y: Int, _ z: Int, rx: Float, ry: Float, _ leaf: BlockID, _ rng: inout SRng) {
        let ix = Int(rx.rounded(.up)), iy = Int(ry.rounded(.up))
        for dy in -iy...iy { for dz in -ix...ix { for dx in -ix...ix {
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
        switch kind {
        case .oak, .smallOak:
            let h = kind == .smallOak ? rng.range(3, 4) : rng.range(4, 6)
            trunk(h, LOG); crown(y + h, LEAVES)
        case .birch, .tallBirch:
            let h = kind == .tallBirch ? rng.range(10, 14) : rng.range(5, 7)
            trunk(h, BIRCH_LOG); crown(y + h, BIRCH_LEAVES)
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
            let h = kind == .pine ? rng.range(7, 11) : rng.range(6, 9)
            trunk(h, SPRUCE_LOG)
            w.leaf(x, y + h, z, SPRUCE_LEAVES)
            if kind == .pine {
                for (dy, r) in [(0, 1), (-1, 2), (-2, 1), (-3, 2), (-4, 1)] {
                    for dz in -r...r { for dx in -r...r where dx * dx + dz * dz <= r * r + (r > 1 ? 0 : 1) {
                        w.leaf(x + dx, y + h + dy, z + dz, SPRUCE_LEAVES)
                    } }
                }
            } else {
                let pattern = [0, 1, 2, 1, 2, 3, 2, 3]
                var yy = y + h - 1, k = 0
                while yy >= y + 2 {
                    let r = pattern[min(k, pattern.count - 1)]
                    if r > 0 {
                        for dz in -r...r { for dx in -r...r where dx * dx + dz * dz <= r * r + 1 { w.leaf(x + dx, yy, z + dz, SPRUCE_LEAVES) } }
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
    // Ground plants, flowers, sugar cane, cacti, water plants and icebergs, per column (own chunk only).
    func placeVegetation(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ biomes: [Biome], _ rng: inout SRng, cols: [Terrain.Column]? = nil) {
        let g = Blocks.id
        let grassy: Set<BlockID> = [GRASS, SNOWY_GRASS, DIRT, g("podzol"), g("coarse_dirt"), g("moss_block")]
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
            if ground == WATER || ground == Blocks.id("ice") {
                var fy = y
                while fy > 1 && (b[Chunk.index(lx, fy, lz)] == WATER) { fy -= 1 }
                let depth = y - fy
                let floor = b[Chunk.index(lx, fy, lz)]
                guard floor == SAND || floor == GRAVEL || floor == DIRT || floor == g("clay") || floor == g("mud") else { continue }
                if biome == .warmOcean && depth > 2 {
                    if h < 0.25 {
                        let c = ["tube", "brain", "bubble", "fire", "horn"][Int(h2 * 5) % 5]
                        let reefH = 1 + Int(h * 12)
                        for k in 1...min(reefH, depth - 2) { b[Chunk.index(lx, fy + k, lz)] = g("\(c)_coral_block") }
                        b[Chunk.index(lx, fy + min(reefH, depth - 2) + 1, lz)] = g("\(c)_coral")
                    } else if h < 0.4 { b[Chunk.index(lx, fy + 1, lz)] = g(["tube", "brain", "bubble", "fire", "horn"][Int(h2 * 5) % 5] + "_coral") }
                    else if h < 0.6 { b[Chunk.index(lx, fy + 1, lz)] = g("seagrass") }
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
                        if h2 < chance { b[Chunk.index(lx, fy + 1, lz)] = g("seagrass") }
                    }
                } else if biome == .swamp || biome == .mangroveSwamp {
                    if depth <= 2 && h < 0.08 && ground == WATER { b[Chunk.index(lx, y + 1, lz)] = g("lily_pad") }
                    else if h > 0.8 { b[Chunk.index(lx, fy + 1, lz)] = g("seagrass") }
                }
                continue
            }
            let above = Chunk.index(lx, y + 1, lz)
            guard b[above] == AIR || b[above] == g("snow") else { continue }
            if b[above] == g("snow") { continue }
            // Sugar cane beside water.
            if (ground == GRASS || ground == SAND || ground == DIRT) && h < 0.12 {
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
                if ground == SAND || ground == g("red_sand") {
                    if h < (biome == .desert ? 0.008 : 0.004) {
                        let clear = [(1, 0), (-1, 0), (0, 1), (0, -1)].allSatisfy { d in
                            let nx = lx + d.0, nz = lz + d.1
                            return nx < 0 || nx >= CS || nz < 0 || nz >= CS || b[Chunk.index(nx, y + 1, nz)] == AIR
                        }
                        if clear {
                            let len = 1 + Int(h2 * 3)
                            for k in 1...len { b[Chunk.index(lx, y + k, lz)] = CACTUS }
                            if hashf(wx, 11, wz, s32 ^ 0x3C3E) < 0.25 { b[Chunk.index(lx, y + len + 1, lz)] = g("cactus_flower") }
                        }
                    } else if h < 0.015 { b[above] = g("dead_bush") }
                    else if h < 0.03 { b[above] = g("short_dry_grass") }
                    else if h < 0.036 { b[above] = g("tall_dry_grass") }
                } else if grassy.contains(ground) && h < 0.1 { b[above] = TALL_GRASS }
                continue
            case .mushroomFields:
                if h < 0.012 { b[above] = h2 < 0.5 ? g("red_mushroom") : g("brown_mushroom") }
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
            if (biome == .darkForest || biome == .oldGrowthSpruceTaiga) && h > 0.985 {
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
                if h > 0.94 { b[above] = g("leaf_litter"); continue }
                if (biome == .birchForest || biome == .oldGrowthBirchForest) && h > 0.92 { b[above] = g("wildflowers"); continue }
            case .meadow:
                if h > 0.93 { b[above] = g("wildflowers"); continue }
            case .plains, .sunflowerPlains, .windsweptHills:
                if h > 0.985 { b[above] = g("bush"); continue }
            case .swamp, .mangroveSwamp:
                if h > 0.975 { b[above] = g("firefly_bush"); continue }
            case .jungle, .sparseJungle, .bambooJungle:
                if h > 0.95 { b[above] = g("bush"); continue }
            case .savanna, .savannaPlateau, .windsweptSavanna:
                if h > 0.97 { b[above] = g("short_dry_grass"); continue }
            default: break
            }
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
