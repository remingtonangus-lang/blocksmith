import Foundation

// The Deep (task 22): a whole 384-tall world under the surface's old floor, reached by digging through it (DeepSeam.swift).
// Internal y, bottom to top:
//   0...3      the molten core (lava)
//   4...floor  the Ash Vault's floor rock, an ash plain at ~y 30 with lava rivers
//   ...ceiling the Ash Vault: a ~100-block-high open cavern, rock pillars, lumenstone hanging from the roof; the
//              Ashguard army holds it (AshWar.swift), its headquarters at x 0, z 0
//   ...199     the lower crust: hot rock, sealed lava pockets, deep ores
//   200...327  the hell band: the Emberdeep's terrain (EmberGen at base 200) with fortresses
//   328...383  the upper crust, continuous with the surface's emberslate floor above
final class DeepGen: TerrainGenerator {
    static let hellBase = 200
    static let crustTop = hellBase + 128          // first layer of the upper crust
    static let coreTop = 3
    static let floorBase = 30
    static let ceilingBase = 134
    static func inHell(_ y: Float) -> Bool { y >= Float(hellBase) && y < Float(crustTop) }
    static func inVault(_ y: Float) -> Bool { y < Float(ceilingBase + 16) }

    let seed: UInt64
    let s32: UInt32
    let ember: EmberGen
    let floorN: Noise, ceilN: Noise, riverN: Noise, pocketN: Noise, matN: Noise
    let structures: StructureCache?

    init(seed: UInt64) {
        self.seed = seed
        s32 = UInt32(truncatingIfNeeded: seed ^ (seed >> 32)) ^ 0xDEE9
        ember = EmberGen(seed: seed, base: DeepGen.hellBase, cap: EMBERSLATE, structures: false)
        floorN = Noise(seed: seed &+ 201)
        ceilN = Noise(seed: seed &+ 202)
        riverN = Noise(seed: seed &+ 203)
        pocketN = Noise(seed: seed &+ 204)
        matN = Noise(seed: seed &+ 205)
        structures = StructureCache(seed: seed, types: [Fortress.deepType] + AshWar.types, fixed: AshWar.starts(seed: seed))
    }

    // MARK: The Ash Vault's shape

    // Floor top (internal y). Flat around the army's sites, rolling further out.
    func floorY(_ x: Int, _ z: Int) -> Int {
        let rough = max(0.15, min(1, (AshWar.clearance(x, z) - 12) / 90))
        let n = floorN.fbm2(Float(x) / 140, Float(z) / 140, 3) * 9 + floorN.noise2(Float(x) / 37, Float(z) / 37) * 2.5
        return DeepGen.floorBase + Int((n * rough).rounded())
    }

    func ceilingY(_ x: Int, _ z: Int) -> Int {
        DeepGen.ceilingBase + Int((ceilN.fbm2(Float(x) / 90, Float(z) / 90, 3) * 14).rounded())
    }

    // Rock pillars from floor to roof: one per 96-block cell (most cells), never on an army site or road.
    func pillar(_ x: Int, _ z: Int) -> Bool {
        let gx = floorDiv(x, 96), gz = floorDiv(z, 96)
        for oz in -1...1 { for ox in -1...1 {
            let h = hash3(gx + ox, 77, gz + oz, s32 ^ 0x9111)
            if h % 5 == 0 { continue }
            let px = (gx + ox) * 96 + 20 + Int(h >> 3 & 55), pz = (gz + oz) * 96 + 20 + Int(h >> 9 & 55)
            let r = 4 + Float(h >> 15 & 7)
            let dx = Float(x - px), dz = Float(z - pz)
            let wob = 1 + 0.25 * matN.noise2(Float(x) / 6, Float(z) / 6)
            if dx * dx + dz * dz < r * r * wob * wob, AshWar.clearance(px, pz) > r + 24 { return true }
        } }
        return false
    }

    func lavaRiver(_ x: Int, _ z: Int) -> Bool {
        abs(riverN.fbm2(Float(x) / 170, Float(z) / 170, 2)) < 0.022 && AshWar.clearance(x, z) > 14
    }

    func column(_ x: Int, _ z: Int) -> (height: Int, biome: Biome) { (floorY(x, z), ember.biome(x, z)) }
    func tints(cx: Int, cz: Int) -> [UInt32] { [UInt32](repeating: 0xFF3A7ABF, count: 768) }

    // MARK: Generation

    func generate(cx: Int, cz: Int) -> [BlockID] {
        var b = [BlockID](repeating: AIR, count: CSQ * CH)
        let bx = cx * CS, bz = cz * CS
        let rock = EMBERSLATE, lava = LAVA, glow = LAMP
        let blackstone = Blocks.id("blackstone"), basalt = Blocks.id("basalt"), magma = Blocks.id("magma_block")
        let soulSoil = Blocks.id("soul_soil"), road = Blocks.id("polished_blackstone")
        let gold = Blocks.id("deepslate_gold_ore"), diamond = Blocks.id("deepslate_diamond_ore"), debris = Blocks.id("ancient_debris")
        var floors = [Int](repeating: 0, count: CSQ), ceils = [Int](repeating: 0, count: CSQ)
        for lz in 0..<CS { for lx in 0..<CS {
            let wx = bx + lx, wz = bz + lz
            var f = floorY(wx, wz)
            let c = ceilingY(wx, wz)
            let river = lavaRiver(wx, wz)
            let solidColumn = pillar(wx, wz)
            if river { f -= 2 }
            floors[lx + lz * CS] = f; ceils[lx + lz * CS] = c
            for y in 0..<CH {
                let i = Chunk.index(lx, y, lz)
                if y <= DeepGen.coreTop { b[i] = lava; continue }
                if y >= DeepGen.hellBase && y < DeepGen.crustTop { continue }          // the hell band (filled below)
                if y > f && y < c && !solidColumn {
                    if river && y == f + 1 { b[i] = lava }
                    continue
                }
                // Rock: emberslate with magma, deep ores and (crusts only) sealed lava pockets.
                let h = hash3(wx, y, wz, s32)
                var v = rock
                if y == f && !solidColumn {
                    let m = matN.noise2(Float(wx) / 19, Float(wz) / 19)
                    v = river ? magma : (AshWar.isRoad(wx, wz) ? road : (m > 0.35 ? basalt : (m < -0.45 ? soulSoil : blackstone)))
                } else if y == c && !solidColumn {
                    v = matN.noise2(Float(wx) / 23 + 50, Float(wz) / 23) > 0.2 ? basalt : blackstone
                } else if solidColumn && y > f && y < c {
                    // Pillars: banded hot rock, no ore studding their faces.
                    v = (y + Int(h % 3)) % 9 < 2 ? basalt : (h % 61 == 0 ? magma : rock)
                } else if h % 47 == 0 {
                    v = magma
                } else {
                    let cell = hash3(wx >> 1, y >> 1, wz >> 1, s32 ^ 0xA5) % 1000
                    if cell < 9 && h % 100 < 55 { v = gold }
                    else if cell > 995 && h % 100 < 50 { v = diamond }
                    else if h % 3100 == 0 && y > c { v = debris }
                }
                b[i] = v
            }
        } }
        ember.fill(&b, cx: cx, cz: cz)
        crustPockets(&b, bx, bz, floors, ceils)
        // The vault's roof: basalt stalactites and lumenstone clusters (its only light besides lava and the army's lamps).
        for lz in 0..<CS { for lx in 0..<CS {
            let wx = bx + lx, wz = bz + lz
            let c = ceils[lx + lz * CS], f = floors[lx + lz * CS]
            guard b[Chunk.index(lx, c - 1, lz)] == AIR else { continue }
            let h = hash3(wx, 5, wz, s32 ^ 0x57A1)
            if h % 37 == 0 {
                let len = 1 + Int(h >> 8 % 6)
                for i in 1...len where c - i > f + 6 { b[Chunk.index(lx, c - i, lz)] = basalt }
            } else if h % 211 == 0 && lx > 1 && lx < 14 && lz > 1 && lz < 14 {
                let len = 2 + Int(h >> 8 % 4)
                for i in 1...len {
                    b[Chunk.index(lx, c - i, lz)] = glow
                    let s = hash3(wx, i, wz, s32 ^ 0x57A2)
                    let (dx, dz) = [(1, 0), (-1, 0), (0, 1), (0, -1)][Int(s % 4)]
                    if i < len && b[Chunk.index(lx + dx, c - i, lz + dz)] == AIR { b[Chunk.index(lx + dx, c - i, lz + dz)] = glow }
                }
            }
        } }
        return b
    }

    // Sealed lava pockets in the crusts above the vault and below the surface: rock solid on all six sides turns to lava,
    // more of it the deeper the crust (mining into one lets it out).
    private func crustPockets(_ b: inout [BlockID], _ bx: Int, _ bz: Int, _ floors: [Int], _ ceils: [Int]) {
        let ranges = [(DeepGen.ceilingBase - 10, DeepGen.hellBase + 4), (DeepGen.crustTop, CH - 4)]
        for (y0, y1) in ranges {
            for y in y0..<y1 {
                let t: Float = y < DeepGen.hellBase ? 0.42 : 0.5
                for lz in 1..<(CS - 1) { for lx in 1..<(CS - 1) {
                    let i = Chunk.index(lx, y, lz)
                    guard b[i] == EMBERSLATE, y > ceils[lx + lz * CS] + 1 else { continue }
                    let wx = bx + lx, wz = bz + lz
                    guard pocketN.noise3(Float(wx) / 9, Float(y) / 6, Float(wz) / 9) > t else { continue }
                    var sealed = true
                    for o in [1, -1, CS, -CS, CSQ, -CSQ] where !(Blocks.opaque[Int(b[i + o])] || b[i + o] == LAVA) { sealed = false; break }
                    if sealed { b[i] = LAVA }
                }
                }
            }
        }
    }
}
