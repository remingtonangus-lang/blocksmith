import Foundation

// The Deep (task 22): a whole 384-tall world under the surface's old floor, reached by digging through it (DeepSeam.swift).
// Internal y, bottom to top:
//   0...3      the molten core (lava)
//   4...floor  the Ash Vault's floor rock, an ash plain at ~y 30 with lava rivers
//   ...ceiling the Ash Vault: a ~135-block-high open cavern under its own ember-haze sky (AshSky.swift), rock pillars,
//              lumenstone hanging from the roof; the Ashguard army holds it (AshWar.swift), its headquarters at x 0, z 0
//   ...191     the lower crust: hot rock, sealed lava pockets, deep ores
//   192...199  the Sealrock (DeepSeal.swift): only Sunderite breaks it
//   200...375  the hell band: the Emberdeep's terrain stretched to 176 tall (EmberGen at base 200, height 176; its lower
//              64 blocks, the lava sea and its shores, exactly the Emberdeep's) with fortresses, bastions and keeps; the
//              gap pass (D1) raised it from 128: caverns over 100 blocks high, lumenstone hanging in a far-off roof
//   376...383  the upper crust, continuous with the surface's emberslate floor above
final class DeepGen: TerrainGenerator {
    static let hellBase = 200
    static let hellHeight = 176                    // was 128 before the gap pass (docs/status/cloud-gap-pass.md, D1)
    static let crustTop = hellBase + hellHeight   // first layer of the upper crust
    static let coreTop = 3
    static let floorBase = 30
    static let ceilingBase = 168                   // was 134 before the Deep expansion (a taller vault)
    static func inHell(_ y: Float) -> Bool { y >= Float(hellBase) && y < Float(crustTop) }
    static func inVault(_ y: Float) -> Bool { y < Float(ceilingBase + 16) }

    let seed: UInt64
    let s32: UInt32
    let ember: EmberGen
    let floorN: Noise, ceilN: Noise, riverN: Noise, pocketN: Noise, matN: Noise
    let structures: StructureCache?
    let keepGuard = DeepGuard()
    let vaultGuard = DeepGuard()           // vault chunks saved before its towns, rail and airfield (AshVault.swift)

    init(seed: UInt64) {
        self.seed = seed
        s32 = UInt32(truncatingIfNeeded: seed ^ (seed >> 32)) ^ 0xDEE9
        ember = EmberGen(seed: seed, base: DeepGen.hellBase, height: DeepGen.hellHeight, cap: EMBERSLATE, structures: false)
        floorN = Noise(seed: seed &+ 201)
        ceilN = Noise(seed: seed &+ 202)
        riverN = Noise(seed: seed &+ 203)
        pocketN = Noise(seed: seed &+ 204)
        matN = Noise(seed: seed &+ 205)
        structures = StructureCache(seed: seed, types: [Fortress.deepType, BrimstoneKeep.type(worldSeed: seed, guardSet: keepGuard), Bastion.deepType(worldSeed: seed, guardSet: keepGuard)] + AshWar.types,
                                    fixed: AshWar.starts(seed: seed, guardSet: vaultGuard))
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
    // PG1 rewrite: how far inside a pillar (x, z) is (blocks, > 0 inside), the same circles `pillar` tests.
    func pillarDistance(_ x: Int, _ z: Int) -> Float {
        let gx = floorDiv(x, 96), gz = floorDiv(z, 96)
        var best: Float = -99
        for oz in -1...1 { for ox in -1...1 {
            let h = hash3(gx + ox, 77, gz + oz, s32 ^ 0x9111)
            if h % 5 == 0 { continue }
            let px = (gx + ox) * 96 + 20 + Int(h >> 3 & 55), pz = (gz + oz) * 96 + 20 + Int(h >> 9 & 55)
            let r = 4 + Float(h >> 15 & 7)
            let dx = Float(x - px), dz = Float(z - pz)
            let rr: Float = dx * dx + dz * dz
            if rr > (r * 1.5 + 4) * (r * 1.5 + 4) { continue }
            let wob = 1 + 0.25 * matN.noise2(Float(x) / 6, Float(z) / 6)
            guard AshWar.clearance(px, pz) > r + 24 else { continue }
            best = max(best, r * wob - rr.squareRoot())
        } }
        return best
    }

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

    // PG1 rewrite: the Ash Vault's ground continuous: blocks over the floor's surface and under the roof's (the same
    // noise as floorY / ceilingY before rounding), the hell band's lattice; pillars and the seal rounded (NaN).
    // The lava core under it (open) and the Sealrock band over it (solid) as flat layers, the pillars as their circles,
    // the crust over the hell band solid, the sealed lava pockets in the crusts by their own noise (crustPockets).
    func groundField(cx: Int, cz: Int) -> [Float]? {
        var g = [Float](repeating: .nan, count: CSQ * CH)
        let bx = cx * CS, bz = cz * CS
        let core = Float(DeepGen.coreTop + 1), sealLo = Float(DeepSeal.bottom), sealHi = Float(DeepSeal.top)
        for lz in 0..<CS { for lx in 0..<CS {
            let wx = bx + lx, wz = bz + lz
            let pd = pillarDistance(wx, wz)
            let rough = max(0.15, min(1, (AshWar.clearance(wx, wz) - 12) / 90))
            let n = floorN.fbm2(Float(wx) / 140, Float(wz) / 140, 3) * 9 + floorN.noise2(Float(wx) / 37, Float(wz) / 37) * 2.5
            var f = Float(DeepGen.floorBase) + n * rough
            if lavaRiver(wx, wz) { f -= 2 }
            let c = Float(DeepGen.ceilingBase) + ceilN.fbm2(Float(wx) / 90, Float(wz) / 90, 3) * 14
            for y in 0..<DeepGen.hellBase {
                let yc = Float(y), i = Chunk.index(lx, y, lz)
                if y <= DeepGen.coreTop { g[i] = yc + 0.5 - core; continue }
                if DeepSeal.inBand(y) { g[i] = min(yc + 0.5 - sealLo, sealHi - yc - 0.5); continue }
                // (surfaces at f + 1 and c, as rounded)
                g[i] = min(max(f + 0.5 - yc, yc - c + 0.5, pd), yc + 0.5 - core)
            }
            for y in DeepGen.crustTop..<CH { g[Chunk.index(lx, y, lz)] = Float(y - DeepGen.crustTop) + 1.5 }
        } }
        ember.bandField(&g, cx: cx, cz: cz)
        // Sealed lava pockets: open where crustPockets' noise passes its threshold (its distance by the noise's gradient).
        let ranges = [(DeepGen.ceilingBase - 10, DeepGen.hellBase + 4), (DeepGen.crustTop, CH - 4)]
        for (y0, y1) in ranges {
            for y in y0..<y1 where !DeepSeal.inBand(y) {
                let t: Float = y < DeepGen.hellBase ? 0.42 : 0.5
                for lz in 1..<(CS - 1) { for lx in 1..<(CS - 1) {
                    let i = Chunk.index(lx, y, lz)
                    let wx = Float(bx + lx), wz = Float(bz + lz), fy = Float(y)
                    guard !g[i].isNaN, fy > Float(ceilingY(bx + lx, bz + lz)) + 1 else { continue }
                    let v = pocketN.noise3(wx / 9, fy / 6, wz / 9)
                    guard v > t - 0.3 else { continue }
                    let gx = pocketN.noise3((wx + 0.5) / 9, fy / 6, wz / 9) - pocketN.noise3((wx - 0.5) / 9, fy / 6, wz / 9)
                    let gy = pocketN.noise3(wx / 9, (fy + 0.5) / 6, wz / 9) - pocketN.noise3(wx / 9, (fy - 0.5) / 6, wz / 9)
                    let gz = pocketN.noise3(wx / 9, fy / 6, (wz + 0.5) / 9) - pocketN.noise3(wx / 9, fy / 6, (wz - 0.5) / 9)
                    let l = (gx * gx + gy * gy + gz * gz).squareRoot()
                    let dist: Float = l > 1e-5 ? (t - v) / l : (v > t ? -1 : 1)
                    g[i] = min(g[i], max(-1.5, min(1.5, dist)))
                } }
            }
        }
        return g
    }

    func generate(cx: Int, cz: Int) -> [BlockID] { generate(cx: cx, cz: cz, field: false) }
    // PG1 rewrite: a field world's chunk: the hell band's caps continuous (EmberGen.fieldBlocks).
    func fieldBlocks(cx: Int, cz: Int) -> [BlockID] { generate(cx: cx, cz: cz, field: true) }

    private func generate(cx: Int, cz: Int, field: Bool) -> [BlockID] {
        var b = [BlockID](repeating: AIR, count: CSQ * CH)
        let bx = cx * CS, bz = cz * CS
        let rock = EMBERSLATE, lava = LAVA, glow = LAMP
        let blackstone = Blocks.id("blackstone"), basalt = Blocks.id("basalt"), magma = Blocks.id("magma_block")
        let soulSoil = Blocks.id("soul_soil"), road = Blocks.id("polished_blackstone")
        let seal = SEALROCK
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
                if DeepSeal.inBand(y) { b[i] = seal; continue }                         // the barrier, unbroken
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
        ember.fill(&b, cx: cx, cz: cz, smoothCaps: field)
        sunderSeam(&b, cx: cx, cz: cz)
        crustPockets(&b, bx, bz, floors, ceils)
        // The Ashguard's lines (teeth, wire, trench) where they cross this chunk.
        for lz in 0..<CS { for lx in 0..<CS {
            let wx = bx + lx, wz = bz + lz
            guard AshLines.distance(wx, wz) == 0, !pillar(wx, wz) else { continue }
            AshLines.carve(&b, lx, lz, wx, wz, f: floors[lx + lz * CS])
        } }
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

    // P323 (c, Oct 15 18:49: "I dug down looking for that special rock", and never found the way in): one chunk in five
    // has a short seam of Sunderite Ore in the hell band's floor, the few layers just above the Sealrock, so whoever digs
    // down to the rock that won't break finds the ore that breaks it beside it, glowing in the dark (the keeps'
    // strongrooms still hold the worked chain).
    static let seamShare: UInt32 = 5
    private func sunderSeam(_ b: inout [BlockID], cx: Int, cz: Int) {
        let h = hash3(cx, 0x5EA, cz, s32 ^ 0x5D2)
        guard h % DeepGen.seamShare == 0 else { return }
        let ore = Blocks.id("sunderite_ore")
        let n = 3 + Int((h >> 4) % 4)
        var x = 2 + Int((h >> 8) % 12), z = 2 + Int((h >> 12) % 12), y = DeepGen.hellBase + Int((h >> 16) % 4)
        for k in 0..<n {
            let i = Chunk.index(x, y, z)
            if b[i] == EMBERSLATE || b[i] == NETHERRACK { b[i] = ore }
            let s = hash3(cx &* 16 &+ k, y, cz, s32 ^ 0x5D3)
            switch s % 6 {
            case 0: x = min(14, x + 1)
            case 1: x = max(1, x - 1)
            case 2: z = min(14, z + 1)
            case 3: z = max(1, z - 1)
            case 4: y = min(DeepGen.hellBase + 5, y + 1)
            default: y = max(DeepGen.hellBase, y - 1)
            }
        }
    }

    // P323 (a): which layer of the Deep a height is in, by name (the voice notes' and bug notes' place line read the hell
    // band's biome at every height, so a note from the vault said "Basalt Deltas"); nil in the hell band itself.
    func layerName(_ x: Int, _ y: Int, _ z: Int) -> String? {
        if y <= DeepGen.coreTop { return "Molten Core" }
        if y < DeepSeal.bottom { return y < ceilingY(x, z) ? "Ash Vault" : "Lower Crust" }
        if DeepSeal.inBand(y) { return "Sealrock" }
        if y >= DeepGen.crustTop { return "Upper Crust" }
        return nil
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
