import Foundation

enum Biome: Int { case ocean, beach, plains, forest, desert, snowy, mountains }

// Deterministic terrain: same seed + coordinates always produce the same chunk,
// so only player-modified chunks are ever written to disk.
final class WorldGen {
    let seed: UInt64
    let s32: UInt32
    let cont: Noise, hills: Noise, mount: Noise, ridge: Noise
    let temp: Noise, hum: Noise, cave1: Noise, cave2: Noise, cave3: Noise, flora: Noise

    init(seed: UInt64) {
        self.seed = seed
        s32 = UInt32(truncatingIfNeeded: seed ^ (seed >> 32))
        cont = Noise(seed: seed &+ 1)
        hills = Noise(seed: seed &+ 2)
        mount = Noise(seed: seed &+ 3)
        ridge = Noise(seed: seed &+ 4)
        temp = Noise(seed: seed &+ 5)
        hum = Noise(seed: seed &+ 6)
        cave1 = Noise(seed: seed &+ 7)
        cave2 = Noise(seed: seed &+ 8)
        cave3 = Noise(seed: seed &+ 9)
        flora = Noise(seed: seed &+ 10)
    }

    func column(_ x: Int, _ z: Int) -> (height: Int, biome: Biome) {
        let fx = Float(x), fz = Float(z)
        let c = cont.fbm2(fx / 700, fz / 700, 4)
        let hl = hills.fbm2(fx / 160, fz / 160, 4)
        let m = mount.fbm2(fx / 380, fz / 380, 3)
        let rg = 1 - abs(ridge.noise2(fx / 110, fz / 110))
        var h: Float = Float(YOFF) + 66 + c * 46 + hl * 12
        if m > 0.12 {
            let k = min(1, (m - 0.12) * 3.5)
            h += k * k * (20 + rg * rg * 55)
        }
        let height = max(4, min(CH - 12, Int(h)))
        let t = temp.fbm2(fx / 520, fz / 520, 3)
        let u = hum.fbm2(fx / 430, fz / 430, 3)
        let biome: Biome
        if height < SEA { biome = .ocean }
        else if height <= SEA + 2 && t > -0.25 && m < 0.1 { biome = .beach }
        else if height > 108 + YOFF { biome = .mountains }
        else if t < -0.2 { biome = .snowy }
        else if t > 0.2 && u < 0.02 { biome = .desert }
        else if u > 0.04 { biome = .forest }
        else { biome = .plains }
        return (height, biome)
    }

    func generate(cx: Int, cz: Int) -> [BlockID] {
        var b = [BlockID](repeating: AIR, count: CSQ * CH)
        var heights = [Int](repeating: 0, count: CSQ)
        var biomes = [Biome](repeating: .plains, count: CSQ)
        let bx = cx * CS, bz = cz * CS
        for lz in 0..<CS {
            for lx in 0..<CS {
                let wx = bx + lx, wz = bz + lz
                let (h, biome) = column(wx, wz)
                heights[lx + lz * CS] = h
                biomes[lx + lz * CS] = biome
                var top = GRASS, filler = DIRT
                switch biome {
                case .ocean: top = h > SEA - 7 ? SAND : GRAVEL; filler = top
                case .beach, .desert: top = SAND; filler = SAND
                case .snowy: top = SNOWY_GRASS
                case .mountains:
                    top = h > 125 + YOFF ? SNOW : (h > 116 + YOFF ? STONE : GRASS)
                    filler = h > 116 + YOFF ? STONE : DIRT
                default: break
                }
                for y in 0...h {
                    var id = y < YOFF - 4 + Int(hash3(wx, y, wz, s32 ^ 0xDEE) % 8) ? DEEPSLATE : STONE
                    if y == 0 { id = BEDROCK }
                    else if y < 4 && hash3(wx, y, wz, s32) % 3 == 0 { id = BEDROCK }
                    else if y == h { id = top }
                    else if y > h - 4 { id = filler }
                    else if biome == .desert && y > h - 8 { id = SANDSTONE }
                    b[Chunk.index(lx, y, lz)] = id
                }
                if h < SEA {
                    for y in (h + 1)...SEA { b[Chunk.index(lx, y, lz)] = WATER }
                }
            }
        }
        carveCaves(&b, bx, bz, heights)
        placeOres(&b, bx, bz)
        placeTrees(&b, cx, cz)
        placePlants(&b, bx, bz, heights, biomes)
        return b
    }

    private func carveCaves(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ heights: [Int]) {
        for lz in 0..<CS {
            for lx in 0..<CS {
                let h = heights[lx + lz * CS]
                if h < SEA + 3 { continue } // keep oceans/beaches sealed for now
                let wx = Float(bx + lx), wz = Float(bz + lz)
                let top = min(h, CH - 2)
                for y in 5...top {
                    let fy = Float(y)
                    let a = cave1.noise3(wx / 38, fy / 26, wz / 38)
                    let c = cave2.noise3(wx / 38, fy / 26, wz / 38)
                    var carve = a * a + c * c < 0.0045            // spaghetti tunnels
                    if !carve && y < 45 + YOFF && y > 12 {
                        carve = cave3.noise3(wx / 70, fy / 34, wz / 70) > 0.42 // caverns
                    }
                    if carve {
                        let i = Chunk.index(lx, y, lz)
                        if b[i] != WATER && b[i] != BEDROCK { b[i] = AIR }
                    }
                }
            }
        }
    }

    private func placeOres(_ b: inout [BlockID], _ bx: Int, _ bz: Int) {
        let stone = STONE, deep = DEEPSLATE
        let coal = COAL_ORE, iron = IRON_ORE, gold = GOLD_ORE, diamond = DIAMOND_ORE
        let dCoal = Blocks.id("deepslate_coal_ore"), dIron = Blocks.id("deepslate_iron_ore")
        let dGold = Blocks.id("deepslate_gold_ore"), dDiamond = Blocks.id("deepslate_diamond_ore")
        let lapis = Blocks.id("lapis_ore"), dLapis = Blocks.id("deepslate_lapis_ore")
        let red = Blocks.id("redstone_ore"), dRed = Blocks.id("deepslate_redstone_ore")
        let copper = Blocks.id("copper_ore"), dCopper = Blocks.id("deepslate_copper_ore")
        for y in 1..<(YOFF + 192) {
            let my = y - YOFF   // displayed y
            for lz in 0..<CS {
                for lx in 0..<CS {
                    let i = Chunk.index(lx, y, lz)
                    let host = b[i]
                    if host != stone && host != deep { continue }
                    let wx = bx + lx, wz = bz + lz
                    let cell = hash3(wx >> 1, y >> 1, wz >> 1, s32 ^ 0xA5A5) % 10000
                    var ore: BlockID = AIR, dOre: BlockID = AIR
                    if cell < 14 { if my < 16 { ore = diamond; dOre = dDiamond } }
                    else if cell < 34 { if my < 32 { ore = gold; dOre = dGold } }
                    else if cell < 52 { if my < 32 { ore = lapis; dOre = dLapis } }
                    else if cell < 90 { if my < 16 { ore = red; dOre = dRed } }
                    else if cell < 190 { if my < 72 { ore = iron; dOre = dIron } }
                    else if cell < 260 { if my > -16 && my < 112 { ore = copper; dOre = dCopper } }
                    else if cell < 400 { if my > 0 { ore = coal; dOre = dCoal } }
                    if ore != AIR && hash3(wx, y, wz, s32 ^ 0x5A5A) % 100 < 60 { b[i] = host == deep ? dOre : ore }
                }
            }
        }
    }

    // Biome colours for grass, foliage and water (RGBA8, 256 each), used by the shader tint.
    func tints(cx: Int, cz: Int) -> [UInt32] {
        var t = [UInt32](repeating: 0, count: 768)
        func rgba(_ h: UInt32) -> UInt32 { // 0xRRGGBB -> little-endian RGBA8 (unpack_unorm4x8)
            ((h >> 16) & 255) | (((h >> 8) & 255) << 8) | ((h & 255) << 16) | (255 << 24)
        }
        for lz in 0..<CS {
            for lx in 0..<CS {
                let (_, biome) = column(cx * CS + lx, cz * CS + lz)
                let g: UInt32, f: UInt32, w: UInt32
                switch biome {
                case .ocean: g = 0x8EB971; f = 0x71A74D; w = 0x3F76E4
                case .beach: g = 0x91BD59; f = 0x77AB2F; w = 0x3F76E4
                case .plains: g = 0x91BD59; f = 0x77AB2F; w = 0x3F76E4
                case .forest: g = 0x79C05A; f = 0x59AE30; w = 0x3F76E4
                case .desert: g = 0xBFB755; f = 0xAEA42A; w = 0x32A598
                case .snowy: g = 0x80B497; f = 0x60A17B; w = 0x3D57D6
                case .mountains: g = 0x8AB689; f = 0x6DA36B; w = 0x3F76E4
                }
                let i = lx + lz * CS
                t[i] = rgba(g); t[256 + i] = rgba(f); t[512 + i] = rgba(w)
            }
        }
        return t
    }

    // Tall grass everywhere green, flowers mostly in meadow patches with one dominant colour each.
    private func placePlants(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ heights: [Int], _ biomes: [Biome]) {
        for lz in 0..<CS {
            for lx in 0..<CS {
                let h = heights[lx + lz * CS]
                if h + 1 >= CH || b[Chunk.index(lx, h, lz)] != GRASS || b[Chunk.index(lx, h + 1, lz)] != AIR { continue }
                let wx = bx + lx, wz = bz + lz
                let hv = hash3(wx, 1, wz, s32 ^ 0x3C3C)
                let roll = Float(hv & 0xFFFF) / 65536
                let meadow = flora.noise2(Float(wx) / 48 + 300, Float(wz) / 48 + 300)
                let grassP: Float, flowerP: Float
                switch biomes[lx + lz * CS] {
                case .plains: grassP = 0.3; flowerP = meadow > 0.2 ? 0.09 : 0.006
                case .forest: grassP = 0.16; flowerP = meadow > 0.25 ? 0.05 : 0.003
                case .mountains: grassP = 0.1; flowerP = 0.004
                default: continue
                }
                var id = AIR
                if roll < flowerP {
                    let c = flora.noise2(Float(wx) / 20 + 500, Float(wz) / 20 + 500)
                    let mix = (hv >> 16) & 255
                    let pick = mix < 50 ? Int(mix % 3) : (c < -0.12 ? 0 : (c < 0.12 ? 1 : 2))
                    id = [BLUE_FLOWER, YELLOW_FLOWER, RED_FLOWER][pick]
                } else if roll < flowerP + grassP {
                    id = TALL_GRASS
                }
                if id != AIR { b[Chunk.index(lx, h + 1, lz)] = id }
            }
        }
    }

    // Trees sit on a jittered 5x5 grid (one candidate per cell, so trunks never touch and
    // there is no visible lattice); a low-frequency noise field sets local density, giving
    // clearings and thickets. Everything is decided from world position + column() only, so
    // trees straddling chunk borders come out identical from both sides.
    private enum TreeKind { case oak, bigOak, birch, spruce }

    private func placeTrees(_ b: inout [BlockID], _ cx: Int, _ cz: Int) {
        let bx = cx * CS, bz = cz * CS
        let cell = 5, margin = 3
        func put(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
            let lx = x - bx, lz = z - bz
            if lx < 0 || lx >= CS || lz < 0 || lz >= CS || y < 1 || y >= CH { return }
            let i = Chunk.index(lx, y, lz)
            if b[i] == AIR { b[i] = id }
        }
        for gz in floorDiv(bz - margin, cell)...floorDiv(bz + CS - 1 + margin, cell) {
            for gx in floorDiv(bx - margin, cell)...floorDiv(bx + CS - 1 + margin, cell) {
                let hv = hash3(gx, 0, gz, s32 ^ 0x7777)
                let tx = gx * cell + Int(hv & 3), tz = gz * cell + Int((hv >> 2) & 3)
                let lx = tx - bx, lz = tz - bz
                if lx < -margin || lx >= CS + margin || lz < -margin || lz >= CS + margin { continue }
                let roll = Float((hv >> 4) & 0xFFFF) / 65536
                if roll > 0.75 { continue }
                let (h, biome) = column(tx, tz)
                if h <= SEA || h >= CH - 16 { continue }
                let inside = lx >= 0 && lx < CS && lz >= 0 && lz < CS
                let density = flora.noise2(Float(tx) / 64, Float(tz) / 64) * 0.7 + 0.5
                let pick = (hv >> 20) & 255
                var kind = TreeKind.oak
                switch biome {
                case .desert:
                    if roll < 0.1 && inside && b[Chunk.index(lx, h, lz)] == SAND {
                        let ch = 1 + Int(hv >> 28) % 3
                        for y in (h + 1)...(h + ch) { b[Chunk.index(lx, y, lz)] = CACTUS }
                    }
                    continue
                case .forest:
                    if roll > 0.15 + 0.55 * density { continue }
                    let grove = flora.noise2(Float(tx) / 40 + 100, Float(tz) / 40 + 100)
                    let birchShare: UInt32 = grove > 0.12 ? 170 : 30
                    kind = pick < birchShare ? .birch : (pick < birchShare + 25 ? .bigOak : .oak)
                case .plains:
                    if roll > (density > 0.75 ? 0.12 : 0.02) { continue }
                    kind = pick < 60 ? .bigOak : (pick < 90 ? .birch : .oak)
                case .snowy:
                    if roll > 0.08 + 0.35 * density { continue }
                    kind = pick < 40 ? .oak : .spruce
                case .mountains:
                    if h > 116 + YOFF || roll > 0.1 { continue }
                    kind = pick < 90 ? .oak : .spruce
                default:
                    continue
                }

                let trunk: Int
                let log: BlockID
                switch kind {
                case .oak: trunk = 4 + Int(hv >> 28) % 3; log = LOG
                case .bigOak: trunk = 6 + Int(hv >> 28) % 3; log = LOG
                case .birch: trunk = 5 + Int(hv >> 28) % 3; log = BIRCH_LOG
                case .spruce: trunk = 6 + Int(hv >> 28) % 4; log = SPRUCE_LOG
                }
                if inside {
                    let gi = Chunk.index(lx, h, lz)
                    if b[gi] == GRASS || b[gi] == SNOWY_GRASS { b[gi] = DIRT }
                    for y in (h + 1)...(h + trunk) {
                        let i = Chunk.index(lx, y, lz)
                        if b[i] == AIR || Blocks.layer[Int(b[i])] == RenderLayer.cutout.rawValue { b[i] = log }
                    }
                }
                let topY = h + trunk
                func jitter(_ dx: Int, _ y: Int, _ dz: Int) -> Float { hashf(tx + dx, y, tz + dz, s32 ^ 0x1234) }

                switch kind {
                case .oak, .birch:
                    let leaf = kind == .oak ? LEAVES : BIRCH_LEAVES
                    let low = (kind == .oak && trunk >= 6) ? -3 : -2
                    for dy in low...1 {
                        let y = topY + dy
                        let r = dy >= 0 ? 1 : 2
                        for dz in -r...r {
                            for dx in -r...r {
                                if dy == 1 && abs(dx) + abs(dz) > 1 { continue }
                                if r == 2 && abs(dx) == 2 && abs(dz) == 2 {
                                    if kind == .birch || jitter(dx, y, dz) < 0.5 { continue }
                                }
                                if dy == 0 && abs(dx) == 1 && abs(dz) == 1 && jitter(dx, y, dz) < 0.3 { continue }
                                put(tx + dx, y, tz + dz, leaf)
                            }
                        }
                    }
                case .bigOak:
                    let cy = topY - 1
                    for dy in -3...2 {
                        for dz in -3...3 {
                            for dx in -3...3 {
                                let e = Float(dx * dx + dz * dz) / 9.5 + Float(dy * dy) / (dy < 0 ? 7.5 : 5.0)
                                if e > 1 + (jitter(dx, cy + dy, dz) - 0.5) * 0.35 { continue }
                                put(tx + dx, cy + dy, tz + dz, LEAVES)
                            }
                        }
                    }
                    // A couple of short side branches poking out of the crown.
                    for k in 0..<2 {
                        let dir = Int((hv >> (8 + k * 3)) & 3)
                        let ox = [1, -1, 0, 0][dir], oz = [0, 0, 1, -1][dir]
                        let y = topY - 2 + k
                        let lxb = lx + ox, lzb = lz + oz
                        if lxb >= 0 && lxb < CS && lzb >= 0 && lzb < CS {
                            let i = Chunk.index(lxb, y, lzb)
                            if b[i] == AIR || b[i] == LEAVES { b[i] = LOG }
                        }
                    }
                case .spruce:
                    put(tx, topY + 1, tz, SPRUCE_LEAVES)
                    let pattern = [1, 1, 2, 1, 2, 3]
                    var y = topY
                    var k = 0
                    while y >= h + 3 {
                        let r = k < pattern.count ? pattern[k] : (k % 2 == 0 ? 2 : 3)
                        let lim = r * r + (k == 0 ? 0 : 1)
                        for dz in -r...r {
                            for dx in -r...r where dx * dx + dz * dz <= lim {
                                put(tx + dx, y, tz + dz, SPRUCE_LEAVES)
                            }
                        }
                        y -= 1
                        k += 1
                    }
                }
            }
        }
    }
}
