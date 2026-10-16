import Foundation

// The Deep (task 22): a whole 384-tall world under the surface's old floor, reached by digging through it (DeepSeam.swift).
// Internal y, bottom to top:
//   0...3      the molten core (lava)
//   4...floor  the Ash Vault's floor rock under its ground (P326, AshFront.swift: grass, mud, dark forests, shell holes,
//              no man's land, mud creeks where lava rivers ran) at ~y 30
//   ...ceiling the Ash Vault: a ~135-block-high open cavern under its own grey, foggy sky (AshSky.swift), grey stone
//              pillars, lumenstone hanging from the roof; the Ashguard army holds it (AshWar.swift), its headquarters at
//              x 0, z 0
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
    let ground: VaultGround                 // P326: the vault floor's shape, materials, woods and scenes (AshFront.swift)
    let keepGuard = DeepGuard()
    let vaultGuard = DeepGuard()           // vault chunks saved before its towns, rail and airfield (AshVault.swift)

    init(seed: UInt64) {
        self.seed = seed
        let s = UInt32(truncatingIfNeeded: seed ^ (seed >> 32)) ^ 0xDEE9
        s32 = s
        ember = EmberGen(seed: seed, base: DeepGen.hellBase, height: DeepGen.hellHeight, cap: EMBERSLATE, structures: false)
        floorN = Noise(seed: seed &+ 201)
        ceilN = Noise(seed: seed &+ 202)
        riverN = Noise(seed: seed &+ 203)
        pocketN = Noise(seed: seed &+ 204)
        matN = Noise(seed: seed &+ 205)
        let vg = VaultGround(seed: seed, s32: s)
        ground = vg
        structures = StructureCache(seed: seed, types: [Fortress.deepType, BrimstoneKeep.type(worldSeed: seed, guardSet: keepGuard), Bastion.deepType(worldSeed: seed, guardSet: keepGuard)] + AshWar.types + [AshFront.sceneType(vg)],
                                    fixed: AshWar.starts(seed: seed, guardSet: vaultGuard))
    }

    // MARK: The Ash Vault's shape

    // Floor top (internal y). Flat around the army's sites, rolling further out, shell holes in it (P326); a creek's bed
    // is a block lower still (VaultGround.top).
    func floorY(_ x: Int, _ z: Int) -> Int {
        DeepGen.floorBase + Int((ground.base(x, z) - ground.crater(x, z)).rounded())
    }

    func ceilingY(_ x: Int, _ z: Int) -> Int {
        DeepGen.ceilingBase + Int((ceilN.fbm2(Float(x) / 90, Float(z) / 90, 3) * 14).rounded())
    }

    // Rock pillars from floor to roof (VaultGround: one per 96-block cell, never on an army site or road).
    func pillarDistance(_ x: Int, _ z: Int) -> Float { ground.pillarDistance(x, z) }
    func pillar(_ x: Int, _ z: Int) -> Bool { ground.pillar(x, z) }
    // P326: the old lava rivers' beds, now mud creeks.
    func creek(_ x: Int, _ z: Int) -> Bool { ground.creek(x, z) }

    func column(_ x: Int, _ z: Int) -> (height: Int, biome: Biome) { (floorY(x, z), ember.biome(x, z)) }
    // P326: the vault's grass and leaves a dark, tired green (grass, foliage, then the water the creeks once had).
    func tints(cx: Int, cz: Int) -> [UInt32] {
        [UInt32](repeating: 0xFF3E6A5A, count: 256) + [UInt32](repeating: 0xFF2E5040, count: 256) + [UInt32](repeating: 0xFF3A7ABF, count: 256)
    }

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
            var f = Float(DeepGen.floorBase) + ground.base(wx, wz) - ground.crater(wx, wz)
            if creek(wx, wz) { f -= 1 }
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
        let seal = SEALROCK, vg = ground
        let gold = Blocks.id("deepslate_gold_ore"), diamond = Blocks.id("deepslate_diamond_ore"), debris = Blocks.id("ancient_debris")
        var floors = [Int](repeating: 0, count: CSQ), ceils = [Int](repeating: 0, count: CSQ)
        for lz in 0..<CS { for lx in 0..<CS {
            let wx = bx + lx, wz = bz + lz
            // P326: the floor as a battlefield: shell holes, mud creeks where the lava rivers ran, living ground on dirt.
            let cr = vg.crater(wx, wz)
            var f = DeepGen.floorBase + Int((vg.base(wx, wz) - cr).rounded())
            let c = ceilingY(wx, wz)
            let river = vg.creek(wx, wz)
            let solidColumn = pillar(wx, wz)
            if river { f -= 1 }
            let top = vg.surface(wx, wz, crater: cr, creek: river, wood: vg.wood(wx, wz), nml: vg.noMansLand(wx, wz))
            let sub = top == vg.mud ? vg.mud : (top == vg.road ? rock : DIRT)
            floors[lx + lz * CS] = f; ceils[lx + lz * CS] = c
            for y in 0..<CH {
                let i = Chunk.index(lx, y, lz)
                if y <= DeepGen.coreTop { b[i] = lava; continue }
                if y >= DeepGen.hellBase && y < DeepGen.crustTop { continue }          // the hell band (filled below)
                if DeepSeal.inBand(y) { b[i] = seal; continue }                         // the barrier, unbroken
                if y > f && y < c && !solidColumn { continue }
                // Rock: emberslate with magma deep down, deep ores and (crusts only) sealed lava pockets.
                let h = hash3(wx, y, wz, s32)
                var v = rock
                if y == f && !solidColumn {
                    v = top
                } else if y < f && y >= f - 3 && !solidColumn {
                    v = sub
                } else if y == c && !solidColumn {
                    v = matN.noise2(Float(wx) / 23 + 50, Float(wz) / 23) > 0.2 ? basalt : blackstone
                } else if solidColumn && y > f && y < c {
                    // Pillars: weathered grey stone, mossy at the foot, no ore studding their faces.
                    v = vg.pillarBlock(wx, y, wz, floor: f)
                } else if h % 47 == 0 && (y > c || y < f - 8) {
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
        vegetation(&b, cx: cx, cz: cz, floors)
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

    // P326 (a): the vault's living ground: grass and ferns, dead bushes and scraps of wire in no man's land; dark forests
    // of dark oak and spruce with dead trees and stumps among them; stumps and snags out in no man's land; now and then a
    // lone tree. Tree sites sit on a jittered 4-block grid and depend only on their position (the trees across a chunk
    // border are the same from both sides); none on a site, road, creek, shell hole, pillar or scene, nor reaching
    // ground a save had already generated.
    private func vegetation(_ b: inout [BlockID], cx: Int, cz: Int, _ floors: [Int]) {
        let vg = ground, bx = cx * CS, bz = cz * CS
        let shortGrass = Blocks.has("short_grass") ? Blocks.id("short_grass") : AIR, fern = Blocks.has("fern") ? Blocks.id("fern") : AIR
        let deadBush = Blocks.has("dead_bush") ? Blocks.id("dead_bush") : AIR, wire = Blocks.has("ash_wire") ? Blocks.id("ash_wire") : AIR
        for lz in 0..<CS { for lx in 0..<CS {
            let f = floors[lx + lz * CS]
            guard f + 1 < CH, b[Chunk.index(lx, f + 1, lz)] == AIR else { continue }
            let t = b[Chunk.index(lx, f, lz)]
            let wx = bx + lx, wz = bz + lz
            let h = hash3(wx, 9, wz, s32 ^ 0x6A55) % 1000
            var plant = AIR
            if t == vg.grass || t == vg.podzol || t == vg.moss {
                let w = vg.wood(wx, wz)
                if h < UInt32(110 + 200 * w) { plant = h % 5 == 0 && w > 0.2 ? fern : shortGrass }
            } else if t == vg.coarse || t == vg.rooted || t == vg.mud {
                if h < 22 && t != vg.mud { plant = deadBush }
                else if h >= 990 && vg.noMansLand(wx, wz) > 0.3 { plant = wire }
            }
            if plant != AIR { b[Chunk.index(lx, f + 1, lz)] = plant }
        } }
        let cell = 4, margin = 7
        let keepOut = AshFront.scenes(bx - margin, bz - margin, bx + CS - 1 + margin, bz + CS - 1 + margin, pad: 6, ground: vg)
        b.withUnsafeMutableBufferPointer { buf in
            let w = TreeWriter(b: buf.baseAddress!, bx: bx, bz: bz)
            var sites: [(TreeKind, Int, Int, Int)] = []
            for gz in floorDiv(bz - margin, cell)...floorDiv(bz + CS - 1 + margin, cell) {
                for gx in floorDiv(bx - margin, cell)...floorDiv(bx + CS - 1 + margin, cell) {
                    let hv = hash3(gx, 0, gz, s32 ^ 0x7EE5)
                    let tx = gx * cell + Int(hv % 4), tz = gz * cell + Int((hv >> 2) % 4)
                    if tx < bx - margin || tx >= bx + CS + margin || tz < bz - margin || tz >= bz + CS + margin { continue }
                    let roll = Float((hv >> 4) & 0xFFFF) / 65536, pick = hashf(tx, 1, tz, s32 ^ 0x7EE6)
                    let wd = vg.wood(tx, tz)
                    var kind: TreeKind? = nil
                    if wd > 0.2 && roll < 0.5 * wd {
                        kind = pick < 0.5 ? .darkOak : (pick < 0.82 ? .spruce : (pick < 0.9 ? .deadOak : (pick < 0.95 ? .stumpOak : .fallenOak)))
                    } else if roll < 0.03 && vg.noMansLand(tx, tz) > 0.3 {
                        kind = pick < 0.45 ? .deadOak : (pick < 0.8 ? .stumpOak : .deadSpruce)
                    } else if roll < 0.004 {
                        kind = pick < 0.5 ? .darkOak : .deadOak
                    }
                    guard let k = kind, AshWar.clearance(tx, tz) > 9, !vg.creek(tx, tz), vg.crater(tx, tz) <= 0,
                          vg.pillarDistance(tx, tz) < -5, vg.guardClear(tx, tz, 1) else { continue }
                    if keepOut.contains(where: { abs(tx - $0.x) <= $0.r + 6 && abs(tz - $0.z) <= $0.r + 6 }) { continue }
                    let gy = vg.top(tx, tz)
                    let soil = vg.surface(tx, tz, crater: 0, creek: false, wood: wd, nml: vg.noMansLand(tx, tz))
                    guard soil != vg.mud && soil != vg.road else { continue }
                    sites.append((k, tx, gy, tz))
                }
            }
            for (k, tx, gy, tz) in sites {
                var rng = SRng(UInt64(hash3(tx, gy, tz, s32 ^ 0x7EE7)) | 1)
                TreePlacer.build(w, k, tx, gy + 1, tz, &rng)
            }
        }
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
