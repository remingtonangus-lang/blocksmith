import Foundation

enum Biome: Int { case ocean, beach, plains, forest, desert, snowy, mountains }

// Deterministic terrain: same seed + coordinates always produce the same chunk,
// so only player-modified chunks are ever written to disk.
final class WorldGen {
    let seed: UInt64
    let s32: UInt32
    let cont: Noise, hills: Noise, mount: Noise, ridge: Noise
    let temp: Noise, hum: Noise, cave1: Noise, cave2: Noise, cave3: Noise

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
    }

    func column(_ x: Int, _ z: Int) -> (height: Int, biome: Biome) {
        let fx = Float(x), fz = Float(z)
        let c = cont.fbm2(fx / 700, fz / 700, 4)
        let hl = hills.fbm2(fx / 160, fz / 160, 4)
        let m = mount.fbm2(fx / 380, fz / 380, 3)
        let rg = 1 - abs(ridge.noise2(fx / 110, fz / 110))
        var h: Float = 66 + c * 46 + hl * 12
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
        else if height > 108 { biome = .mountains }
        else if t < -0.2 { biome = .snowy }
        else if t > 0.2 && u < 0.02 { biome = .desert }
        else if u > 0.04 { biome = .forest }
        else { biome = .plains }
        return (height, biome)
    }

    func generate(cx: Int, cz: Int) -> [UInt8] {
        var b = [UInt8](repeating: AIR, count: CSQ * CH)
        var heights = [Int](repeating: 0, count: CSQ)
        let bx = cx * CS, bz = cz * CS
        for lz in 0..<CS {
            for lx in 0..<CS {
                let wx = bx + lx, wz = bz + lz
                let (h, biome) = column(wx, wz)
                heights[lx + lz * CS] = h
                var top = GRASS, filler = DIRT
                switch biome {
                case .ocean: top = h > SEA - 7 ? SAND : GRAVEL; filler = top
                case .beach, .desert: top = SAND; filler = SAND
                case .snowy: top = SNOWY_GRASS
                case .mountains:
                    top = h > 125 ? SNOW : (h > 116 ? STONE : GRASS)
                    filler = h > 116 ? STONE : DIRT
                default: break
                }
                for y in 0...h {
                    var id = STONE
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
        return b
    }

    private func carveCaves(_ b: inout [UInt8], _ bx: Int, _ bz: Int, _ heights: [Int]) {
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
                    if !carve && y < 45 {
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

    private func placeOres(_ b: inout [UInt8], _ bx: Int, _ bz: Int) {
        for y in 1..<128 {
            for lz in 0..<CS {
                for lx in 0..<CS {
                    let i = Chunk.index(lx, y, lz)
                    if b[i] != STONE { continue }
                    let wx = bx + lx, wz = bz + lz
                    let cell = hash3(wx >> 1, y >> 1, wz >> 1, s32 ^ 0xA5A5) % 10000
                    var ore = AIR
                    if cell < 12 { if y < 16 { ore = DIAMOND_ORE } }
                    else if cell < 30 { if y < 32 { ore = GOLD_ORE } }
                    else if cell < 100 { if y < 64 { ore = IRON_ORE } }
                    else if cell < 220 { ore = COAL_ORE }
                    if ore != AIR && hash3(wx, y, wz, s32 ^ 0x5A5A) % 100 < 60 { b[i] = ore }
                }
            }
        }
    }

    // Trees are chosen by a world-position hash, so trees straddling chunk borders
    // come out identical from both sides without needing neighbor data.
    private func placeTrees(_ b: inout [UInt8], _ cx: Int, _ cz: Int) {
        let bx = cx * CS, bz = cz * CS
        for tz in (bz - 3)..<(bz + CS + 3) {
            for tx in (bx - 3)..<(bx + CS + 3) {
                let hv = hash3(tx, 0, tz, s32 ^ 0x7777)
                let roll = hv % 1000
                if roll >= 28 { continue }
                let (h, biome) = column(tx, tz)
                if h >= CH - 12 || h <= SEA { continue }
                let lx = tx - bx, lz = tz - bz
                let inside = lx >= 0 && lx < CS && lz >= 0 && lz < CS
                if biome == .desert {
                    if roll < 4 && inside && b[Chunk.index(lx, h, lz)] == SAND {
                        let ch = 1 + Int(hv >> 12) % 3
                        for y in (h + 1)...(h + ch) { b[Chunk.index(lx, y, lz)] = CACTUS }
                    }
                    continue
                }
                let limit: UInt32
                switch biome {
                case .forest: limit = 28
                case .plains: limit = 3
                case .snowy: limit = 8
                case .mountains: limit = 4
                default: limit = 0
                }
                if roll >= limit { continue }
                if biome == .mountains && h > 116 { continue }
                let trunk = 4 + Int(hv >> 16) % 3
                if inside {
                    let g = b[Chunk.index(lx, h, lz)]
                    if g != GRASS && g != SNOWY_GRASS { continue }
                    b[Chunk.index(lx, h, lz)] = DIRT
                    for y in (h + 1)...(h + trunk) { b[Chunk.index(lx, y, lz)] = LOG }
                }
                let topY = h + trunk
                for dy in -2...1 {
                    let y = topY + dy
                    let r = dy >= 0 ? 1 : 2
                    for dz in -r...r {
                        for dx in -r...r {
                            if dy == 1 && abs(dx) + abs(dz) > 1 { continue }
                            if r == 2 && abs(dx) == 2 && abs(dz) == 2 && (hash3(tx + dx, y, tz + dz, s32) & 1) == 0 { continue }
                            let x = lx + dx, z = lz + dz
                            if x < 0 || x >= CS || z < 0 || z >= CS { continue }
                            let i = Chunk.index(x, y, z)
                            if b[i] == AIR { b[i] = LEAVES }
                        }
                    }
                }
            }
        }
    }
}
