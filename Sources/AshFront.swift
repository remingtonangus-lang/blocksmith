import Foundation
import simd

// P326 (Oct 15 18:49-19:04: the Ash Vault "looks too much like hell"; make it its own place, "the worst scenes of WWII
// for the Germans"). The vault is a battlefield of the last war under a grey, foggy sky (AshSky.swift):
//   Ground   no lava: the old lava rivers are mud creeks; grass, podzol, mud and coarse dirt over dirt; grey stone
//            pillars; dark forests of dark oak and spruce; no man's land outside the Ember Line (mud, shell holes,
//            stumps, dead trees, scraps of wire); a shell hole here and there everywhere else (VaultGround)
//   Scenes   crashed bombers and fighters, knocked-out tanks, an ambushed convoy, a broken farm wall where an attack
//            was cut down (AshFront.scene); fallen Allied soldiers lie at them and along the wire (AshFallen)
//   Bases    two flak batteries and a heavy-water plant join the army's camps, gun batteries and rail (AshSites.swift)
//   Saves    vault chunks a save had before (structure-guard-p326.txt) keep their shape and take the new ground's
//            materials as they load (VaultGround.migrate); new sites, scenes, shell holes and trees stay off them

// MARK: The vault's ground

final class VaultGround {
    let floorN: Noise, riverN: Noise, matN: Noise, woodN: Noise
    let s32: UInt32
    let guardSet = DeepGuard()           // vault chunks saved before P326 (structure-guard-p326.txt)
    let grass = Blocks.id("grass_block"), podzol = Blocks.id("podzol"), mud = Blocks.id("mud"), coarse = Blocks.id("coarse_dirt")
    let rooted = Blocks.has("rooted_dirt") ? Blocks.id("rooted_dirt") : Blocks.id("coarse_dirt")
    let moss = Blocks.has("moss_block") ? Blocks.id("moss_block") : Blocks.id("grass_block")
    let road = Blocks.id("polished_blackstone"), andesite = Blocks.id("andesite"), tuff = Blocks.id("tuff")
    let mossyCobble = Blocks.id("mossy_cobblestone")

    init(seed: UInt64, s32: UInt32) {
        // (the same seeds as DeepGen's floor, river and material noise: the shapes old saves were made with)
        floorN = Noise(seed: seed &+ 201)
        riverN = Noise(seed: seed &+ 203)
        matN = Noise(seed: seed &+ 205)
        woodN = Noise(seed: seed &+ 206)
        self.s32 = s32
    }

    // The rolling floor before the war's marks (blocks above floorBase, unrounded): flat round the army's sites, rolling
    // further out. `front: false`: as it was before P326's sites (old saves' ground).
    @inline(__always) func base(_ x: Int, _ z: Int, front: Bool = true) -> Float {
        let rough = max(0.15, min(1, (AshWar.clearance(x, z, front: front) - 12) / 90))
        let n = floorN.fbm2(Float(x) / 140, Float(z) / 140, 3) * 9 + floorN.noise2(Float(x) / 37, Float(z) / 37) * 2.5
        return n * rough
    }

    // The old lava rivers' beds, now mud creeks (a block lower than the floor; the old rivers ran two lower with lava in).
    func creek(_ x: Int, _ z: Int, front: Bool = true) -> Bool {
        abs(riverN.fbm2(Float(x) / 170, Float(z) / 170, 2)) < 0.022 && AshWar.clearance(x, z, front: front) > 14
    }

    // P377 step 4 (Oct 16 19:51, "walking around he can see where a raised block level used to be"): a field world's
    // creek as a smooth channel under the floor, 1 block at its middle and 0 at its banks, fading out near the army's
    // sites. The block creek's one-block cut, column by column, drew every creek in the field as a stepped groove with
    // a jagged rim winding over the grass. (Block worlds keep the cut: creek().)
    func creekDepth(_ x: Int, _ z: Int) -> Float {
        let n = abs(riverN.fbm2(Float(x) / 170, Float(z) / 170, 2))
        guard n < 0.045 else { return 0 }
        let c = AshWar.clearance(x, z)
        guard c > 14 else { return 0 }
        let t: Float = max(0, min(1, (0.045 - n) / 0.03)) * min(1, (c - 14) / 6)
        return t * t * (3 - 2 * t)
    }

    // No man's land: the belt outside the Ember Line's wire (432 out), faded at both edges. P346 (e): its own place, its
    // outer edge ragged (out to 535-615 by its own noise) instead of a ring.
    static let nmlOuter: Float = 575, nmlRagged: Float = 40
    func noMansLand(_ x: Int, _ z: Int) -> Float {
        let d = sqrtf(Float(x * x + z * z))
        let inner = AshLines.emberR + AshLines.emberHalf
        guard d > inner - 4 && d < VaultGround.nmlOuter + VaultGround.nmlRagged else { return 0 }
        let outer = VaultGround.nmlOuter + VaultGround.nmlRagged * riverN.noise2(Float(x) / 95 + 31, Float(z) / 95 - 17)
        let a: Float = min(1, (d - inner + 4) / 10), b: Float = min(1, (outer - d) / 30)
        return max(0, min(a, b))
    }

    // How deep in a dark forest (0 open ground, 1 deep in): woods by their own noise, kept off the army's sites and roads
    // and out of no man's land.
    func wood(_ x: Int, _ z: Int) -> Float {
        let n = woodN.fbm2(Float(x) / 150, Float(z) / 150, 3)
        let w = max(0, min(1, (n - 0.04) * 5))
        guard w > 0 else { return 0 }
        let c = AshWar.clearance(x, z)
        return w * max(0, min(1, (c - 6) / 14)) * (1 - noMansLand(x, z))
    }

    @inline(__always) func guardClear(_ x: Int, _ z: Int, _ r: Int) -> Bool {
        guardSet.chunks.isEmpty || guardSet.clear(floorDiv(x, CS), floorDiv(z, CS), r)
    }

    // A shell hole's depth under the floor at (x, z) (blocks; a little negative on a hole's rim): a dense field of them in
    // no man's land, one here and there elsewhere; never on a site, road, rail, the lines or a pillar, nor on ground a save
    // had already generated (its saved neighbour would show the cut).
    func crater(_ x: Int, _ z: Int) -> Float {
        var depth: Float = 0, rim: Float = 0
        for lat in 0..<2 {
            let cell = lat == 0 ? 11 : 26
            let gx = floorDiv(x, cell), gz = floorDiv(z, cell)
            for oz in -1...1 { for ox in -1...1 {
                let h = hash3(gx + ox, 31 + lat, gz + oz, s32 ^ 0xC2A7)
                let px = (gx + ox) * cell + Int(h % UInt32(cell)), pz = (gz + oz) * cell + Int((h >> 8) % UInt32(cell))
                let r: Float = lat == 0 ? 2.5 + Float((h >> 16) % 5) : 3 + Float((h >> 16) % 6)
                let dx = Float(x - px), dz = Float(z - pz)
                let d2: Float = dx * dx + dz * dz
                let reach = r * 1.35
                if d2 >= reach * reach { continue }
                if lat == 0 {
                    guard Float((h >> 20) & 255) / 256 < noMansLand(px, pz) * 0.85 else { continue }
                } else if (h >> 24) % 3 != 0 { continue }
                guard AshWar.clearance(px, pz) > r + 9, pillarDistance(px, pz) < -(r + 3), guardClear(px, pz, 1) else { continue }
                let d = d2.squareRoot()
                if d < r { depth = max(depth, r * 0.5 * (1 - (d / r) * (d / r))) }
                else { rim = max(rim, 0.6 * (1 - (d - r) / (reach - r))) }
            } }
        }
        return depth > 0 ? depth : -rim
    }

    // The floor's top block's height (internal y) as the generator lays it: shell holes in, creeks a block down.
    func top(_ x: Int, _ z: Int) -> Int {
        DeepGen.floorBase + Int((base(x, z) - crater(x, z)).rounded()) - (creek(x, z) ? 1 : 0)
    }

    // The floor's top block: the army's roads; mud in creeks and shell holes; churned mud and dirt in no man's land;
    // forest floor (podzol, moss, grass) in the woods; grass with coarse patches in the open.
    func surface(_ x: Int, _ z: Int, crater c: Float, creek: Bool, wood: Float, nml: Float) -> BlockID {
        if AshWar.isRoad(x, z) { return road }
        if creek || c > 1.0 { return mud }
        let m = matN.noise2(Float(x) / 19, Float(z) / 19)
        if c > 0.15 { return m > 0.2 ? coarse : mud }
        if nml > 0.4 { return m < -0.15 ? mud : (m < 0.35 ? coarse : rooted) }
        if wood > 0.3 { return m < 0.1 ? podzol : (m > 0.55 ? moss : grass) }
        return m > 0.45 ? coarse : (m < -0.5 ? podzol : grass)
    }

    // MARK: Pillars (moved from DeepGen; the same circles)

    // Rock pillars from floor to roof: one per 96-block cell (most cells), never on an army site or road. How far inside
    // a pillar (x, z) is (blocks, > 0 inside).
    func pillarDistance(_ x: Int, _ z: Int, front: Bool = true) -> Float {
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
            guard AshWar.clearance(px, pz, front: front) > r + 24 else { continue }
            best = max(best, r * wob - rr.squareRoot())
        } }
        return best
    }

    func pillar(_ x: Int, _ z: Int, front: Bool = true) -> Bool {
        let gx = floorDiv(x, 96), gz = floorDiv(z, 96)
        for oz in -1...1 { for ox in -1...1 {
            let h = hash3(gx + ox, 77, gz + oz, s32 ^ 0x9111)
            if h % 5 == 0 { continue }
            let px = (gx + ox) * 96 + 20 + Int(h >> 3 & 55), pz = (gz + oz) * 96 + 20 + Int(h >> 9 & 55)
            let r = 4 + Float(h >> 15 & 7)
            let dx = Float(x - px), dz = Float(z - pz)
            let wob = 1 + 0.25 * matN.noise2(Float(x) / 6, Float(z) / 6)
            if dx * dx + dz * dz < r * r * wob * wob, AshWar.clearance(px, pz, front: front) > r + 24 { return true }
        } }
        return false
    }

    // A pillar's rock: weathered grey bands of andesite, stone and tuff, mossy at the foot.
    func pillarBlock(_ x: Int, _ y: Int, _ z: Int, floor f: Int) -> BlockID {
        let h = hash3(x, y, z, s32)
        if y <= f + 3 && h % 3 == 0 { return moss }
        if y <= f + 6 && h % 7 == 0 { return mossyCobble }
        return (y + Int(h % 3)) % 9 < 2 ? andesite : (h % 13 == 0 ? tuff : STONE)
    }

    // MARK: Old saves

    // A vault chunk saved before P326: its shape stays (shell holes, forests, the scenes and the new sites never touch it),
    // its ground's materials turn into the new ground's: the old surface (ash plain blackstone, basalt, soul soil, magma)
    // into grass, podzol, mud or dirt with a few layers of dirt under it; the lava in the old rivers into mud (block
    // worlds) or out (field worlds: a dry creek); the black pads under the army's sites into trampled earth; the pillars'
    // hot bands into grey stone. `g`: a field world's saved ground (materials changed in place, never its shape).
    func migrate(_ b: inout [BlockID], _ g: inout FieldData?, cx: Int, cz: Int) {
        let bx = cx * CS, bz = cz * CS
        let blackstone = Blocks.id("blackstone"), basalt = Blocks.id("basalt"), soulSoil = Blocks.id("soul_soil")
        let magma = Blocks.id("magma_block"), smoothBasalt = Blocks.id("smooth_basalt")
        let shortGrass = Blocks.has("short_grass") ? Blocks.id("short_grass") : AIR
        var old = [Bool](repeating: false, count: Blocks.count)
        for v in [blackstone, basalt, soulSoil, magma, EMBERSLATE] { old[Int(v)] = true }
        let lo = DeepGen.coreTop + 1, hi = DeepGen.floorBase + 18
        let field = g != nil
        func at(_ i: Int) -> (BlockID, Bool) {
            if b[i] != AIR || g == nil { return (b[i], false) }
            if let gg = g, i < gg.fd.count, gg.fd[i] > 0 { return (FieldMat.blocks[Int(gg.fm[i])], true) }
            return (AIR, false)
        }
        func put(_ i: Int, _ v: BlockID, _ inField: Bool) {
            // (a material the field can't hold: packed mud as coarse dirt, mossy cobble as stone)
            if inField { let m = FieldMat.index[Int(v)]; g?.fm[i] = m != 0 ? m : FieldMat.index[Int(v == AshWar.padMud ? AshWar.padDirt : STONE)] } else { b[i] = v }
        }
        for lz in 0..<CS { for lx in 0..<CS {
            let wx = bx + lx, wz = bz + lz
            if AshWar.isRoad(wx, wz) { continue }
            if pillar(wx, wz, front: false) {
                let f = DeepGen.floorBase + Int(base(wx, wz, front: false).rounded())
                for y in lo..<(DeepGen.ceilingBase + 16) {
                    let i = Chunk.index(lx, y, lz)
                    let (v, inF) = at(i)
                    if v == basalt || v == magma || (v == EMBERSLATE && y > f) { put(i, pillarBlock(wx, y, wz, floor: f), inF) }
                }
                continue
            }
            if let s = AshWar.padSite(wx, wz) {
                // The site's pad: its black top (the old pad's own basalt cells, never the airfield's runway marks).
                let y0 = AshWar.ground, i = Chunk.index(lx, y0, lz)
                let (v, inF) = at(i)
                let oldBasalt = v == smoothBasalt && hash3(wx, 3, wz, 0xA5) % 5 == 0 && s.kind != "airfield"
                if v == blackstone || oldBasalt {
                    put(i, AshWar.padBlock(wx, wz), inF)
                    for y in (y0 - 3)..<y0 { let j = Chunk.index(lx, y, lz); let (u, uf) = at(j); if u == EMBERSLATE { put(j, DIRT, uf) } }
                }
                continue
            }
            let river = creek(wx, wz, front: false)
            let oldF = DeepGen.floorBase + Int(base(wx, wz, front: false).rounded()) - (river ? 2 : 0)
            if river {
                for y in max(lo, oldF - 1)...min(hi, oldF + 2) {
                    let i = Chunk.index(lx, y, lz)
                    if Blocks.fluidKind[Int(b[i])] == 2 { b[i] = field ? AIR : mud }
                }
            }
            // The ground's top near where the old floor was (a building on it is left alone: its blocks aren't old ground).
            let wd = wood(wx, wz), nml = noMansLand(wx, wz)
            let top = surface(wx, wz, crater: 0, creek: river, wood: wd, nml: nml)
            for y in stride(from: min(hi, oldF + 3), through: max(lo, oldF - 4), by: -1) {
                let i = Chunk.index(lx, y, lz)
                let (v, inF) = at(i)
                guard Blocks.opaque[Int(v)] else { continue }
                if old[Int(v)] {
                    put(i, top, inF)
                    let a = i + CSQ
                    if y + 1 < CH, (top == grass || top == podzol), shortGrass != AIR, b[a] == AIR, hash3(wx, 9, wz, s32 ^ 0x6A55) % 100 < 12,
                       !(g.map { a < $0.fd.count && $0.fd[a] > 0 } ?? false) { b[a] = shortGrass }
                }
                for k in 1...3 where y - k >= lo {
                    let j = i - k * CSQ
                    let (u, uf) = at(j)
                    if old[Int(u)] { put(j, top == mud ? mud : DIRT, uf) }
                }
                break
            }
        } }
    }
}

// MARK: Set pieces

struct AshScene {
    let kind: Int             // 0 a crashed bomber, 1 a crashed fighter, 2 knocked-out tanks, 3 an ambushed convoy, 4 the wall
    let x: Int, z: Int
    let r: Int
    let face: Int             // 0..3: -z, +x, +z, -x
    static let names = ["crashed bomber", "crashed fighter", "knocked-out tanks", "ambushed convoy", "the broken wall"]
}

enum AshFront {
    static let sceneSpacing = 8                // chunks (one region in four is empty)
    static let hull = Blocks.id("wreck_hull"), olive = Blocks.id("wreck_olive"), alu = Blocks.id("wreck_alu")

    static func scene(regionX rx: Int, regionZ rz: Int, ground g: VaultGround) -> AshScene? {
        let h = hash3(rx, 0x5CE, rz, g.s32 ^ 0x26A3)
        guard h % 4 != 0 else { return nil }
        let span = sceneSpacing * CS
        let x = rx * span + 26 + Int((h >> 4) % UInt32(span - 52)), z = rz * span + 26 + Int((h >> 12) % UInt32(span - 52))
        let kind = Int((h >> 20) % 5)
        let r = [17, 10, 16, 15, 15][kind]
        guard AshWar.clearance(x, z) > Float(r + 10), g.pillarDistance(x, z) < -Float(r + 6), g.guardClear(x, z, r / CS + 2) else { return nil }
        return AshScene(kind: kind, x: x, z: z, r: r, face: Int((h >> 28) % 4))
    }

    // Scenes whose footprint (plus `pad`) reaches the square [x0, x1] x [z0, z1].
    static func scenes(_ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int, pad: Int, ground g: VaultGround) -> [AshScene] {
        let span = sceneSpacing * CS
        var out: [AshScene] = []
        for rz in floorDiv(z0 - 40, span)...floorDiv(z1 + 40, span) { for rx in floorDiv(x0 - 40, span)...floorDiv(x1 + 40, span) {
            guard let s = scene(regionX: rx, regionZ: rz, ground: g) else { continue }
            let e = s.r + pad
            if s.x + e >= x0 && s.x - e <= x1 && s.z + e >= z0 && s.z - e <= z1 { out.append(s) }
        } }
        return out
    }

    static func sceneType(_ g: VaultGround) -> StructureType {
        StructureType(name: "ash_scene", spacing: sceneSpacing, separation: 0, salt: 0, reach: 2) { _, cx, cz in
            guard let s = scene(regionX: floorDiv(cx, sceneSpacing), regionZ: floorDiv(cz, sceneSpacing), ground: g) else { return nil }
            let lo = IVec3(s.x - s.r - 2, DeepGen.floorBase - 14, s.z - s.r - 2), hi = IVec3(s.x + s.r + 2, DeepGen.floorBase + 30, s.z + s.r + 2)
            return StructureStart(kind: "ash_scene", pieces: [Piece(min: lo, max: hi) { w in build(&w, s, g) }],
                                  anchor: IVec3(s.x, g.top(s.x, s.z) + 1, s.z))
        }
    }

    // The fallen at a scene (world x, z and heading), as AshFallen lays them.
    static func fallen(_ s: AshScene) -> [(Float, Float, Float)] {
        let (fx, fz) = [(0, -1), (1, 0), (0, 1), (-1, 0)][s.face]
        var spots: [(Float, Float)]
        switch s.kind {
        case 0: spots = [(-3.5, -7), (3, -8.5)]
        case 1: spots = [(2.5, -3.5)]
        case 2: spots = [(-4.5, -6), (5, 1.5), (-5, 9), (1.5, -12)]
        case 3: spots = [(-3, -10), (3, -7), (-3.5, -1), (4, 3), (-2.5, 8), (3, 11), (0.5, 14)]
        default:
            spots = []
            for row in 0..<3 { for col in 0..<7 {
                let h = hash3(s.x + col, row, s.z, 0xFA11)
                guard h % 10 < 7 else { continue }
                let ju = Float(h >> 4 & 15) / 15 - 0.5, jv = Float(h >> 8 & 15) / 15 - 0.5
                spots.append((Float(col) * 2.6 - 7.8 + ju, -1 - Float(row) * 2.7 + jv))
            } }
        }
        return spots.enumerated().map { (k, uv) in
            let x = Float(s.x) + 0.5 + uv.0 * Float(-fz) + uv.1 * Float(fx), z = Float(s.z) + 0.5 + uv.0 * Float(fx) + uv.1 * Float(fz)
            return (x, z, hashf(s.x + k, 7, s.z, 0xFA12) * 2 * .pi)
        }
    }

    static func build(_ w: inout StructWriter, _ s: AshScene, _ g: VaultGround) {
        let (fx, fz) = [(0, -1), (1, 0), (0, 1), (-1, 0)][s.face]
        func X(_ u: Int, _ v: Int) -> Int { s.x + u * (-fz) + v * fx }
        func Z(_ u: Int, _ v: Int) -> Int { s.z + u * fx + v * fz }
        let glass = Blocks.id("glass"), bars = Blocks.id("iron_bars"), coal = Blocks.id("coal_block")
        let fence = Blocks.has("dark_oak_fence") ? Blocks.id("dark_oak_fence") : bars
        let cobble = Blocks.id("cobblestone"), mossy = Blocks.id("mossy_cobblestone")
        let blockWorld = w.mark == nil
        var rng = SRng(UInt64(hash3(s.x, 0x5CE, s.z, g.s32)) | 1)
        func put(_ u: Int, _ y: Int, _ v: Int, _ b: BlockID) { w.set(X(u, v), y, Z(u, v), b) }
        // The lowest ground under a part's footprint: it sits there, sunk into the higher ground round it.
        func base(_ u0: Int, _ v0: Int, _ u1: Int, _ v1: Int) -> Int {
            var lo = Int.max
            for (u, v) in [(u0, v0), (u1, v0), (u0, v1), (u1, v1), ((u0 + u1) / 2, (v0 + v1) / 2)] { lo = min(lo, g.top(X(u, v), Z(u, v))) }
            return lo
        }
        // Paint scorched in patches.
        func burnt(_ b: BlockID, _ u: Int, _ y: Int, _ v: Int) -> BlockID { hash3(X(u, v), y, Z(u, v), 0x5C0C) % 3 == 0 ? hull : b }
        // Churned, sooty earth (block worlds; a field world's ground keeps its own smooth surface).
        func scar(_ u: Int, _ v: Int) {
            guard blockWorld else { return }
            let x = X(u, v), z = Z(u, v), t = g.top(x, z)
            let h = hash3(x, 5, z, 0x5CA2)
            w.set(x, t, z, h % 4 == 0 ? coal : (h % 4 == 1 ? g.mud : g.coarse))
            w.set(x, t + 1, z, AIR)
        }
        // Scattered pieces of the wreck on the ground round it.
        func debris(_ n: Int, _ r: Int, _ kinds: [BlockID]) {
            for _ in 0..<n {
                let u = rng.range(-r, r), v = rng.range(-r, r), k = kinds[rng.int(kinds.count)]
                put(u, g.top(X(u, v), Z(u, v)) + 1, v, k)
            }
        }
        // A burnt-out lorry facing along v: chassis, wheels, the cab's shell, the cargo bed's charred ribs.
        func lorry(_ cu: Int, _ cv: Int) {
            let y0 = base(cu - 1, cv - 3, cu + 1, cv + 3)
            for v in -3...3 { for u in -1...1 { put(cu + u, y0, cv + v, hull); put(cu + u, y0 + 1, cv + v, AIR); put(cu + u, y0 + 2, cv + v, AIR) } }
            for v in [-2, 2] { put(cu - 2, y0, cv + v, coal); put(cu + 2, y0, cv + v, coal) }
            for u in -1...1 { put(cu + u, y0 + 1, cv - 3, burnt(olive, u, y0 + 1, -3)); put(cu + u, y0 + 2, cv - 2, burnt(olive, u, y0 + 2, -2)) }
            put(cu - 1, y0 + 2, cv - 3, olive); put(cu + 1, y0 + 2, cv - 3, hull)
            for v in -1...3 { put(cu - 1, y0 + 1, cv + v, burnt(olive, -1, y0 + 1, v)); put(cu + 1, y0 + 1, cv + v, burnt(olive, 1, y0 + 1, v)) }
            for v in [0, 2] { put(cu - 1, y0 + 2, cv + v, fence); put(cu + 1, y0 + 2, cv + v, fence) }
        }
        // P346: the bomber, the fighter and the tanks are models (AshWrecks); here only the ground they scarred, a solid
        // core hidden inside each hull and, in the bomber, the chest with its spares.
        let spots = AshWrecks.spots(s, g)
        func core(_ sp: AshWrecks.Spot, along: [Int], heights: Int) {
            let bx = Int(floorf(sp.pos.x)), by = Int(floorf(sp.pos.y)), bz = Int(floorf(sp.pos.z))
            let fx2 = Int(roundf(-sinf(sp.yaw))), fz2 = Int(roundf(-cosf(sp.yaw)))
            for a in along { for dy in 0..<heights { w.set(bx - a * fx2, by + dy, bz - a * fz2, hull) } }
        }
        switch s.kind {
        case 0:
            // A bomber came down out of the fog and slid on its belly: the furrow behind it, its fuselage solid.
            for v in 4...17 { for u in -1...1 where rng.chance(0.75) { scar(u, v) } }
            if let sp = spots.first {
                core(sp, along: Array(-9...3), heights: 1)
                // The crew's stores, spilled at the break behind the wings (the spares are there).
                let bx = Int(floorf(sp.pos.x)), by = Int(floorf(sp.pos.y)), bz = Int(floorf(sp.pos.z))
                let fx2 = Int(roundf(-sinf(sp.yaw))), fz2 = Int(roundf(-cosf(sp.yaw)))
                w.chest(bx - 4 * fx2, by, bz - 4 * fz2, loot: "ash_bomber", seed: rng.next(), facing: 0)
            }
        case 1:
            // A fighter nosed into the ground: the gouge it made.
            for v in -6...(-2) { scar(0, v); if rng.chance(0.5) { scar(rng.chance(0.5) ? 1 : -1, v) } }
        case 2:
            // A tank troop caught on open ground: three knocked-out hulls, solid.
            for sp in spots { core(sp, along: Array(-1...1), heights: 1) }      // (inside the hull, under its deck)
            for _ in 0..<10 { scar(rng.range(-8, 8), rng.range(-14, 14)) }
        case 3:
            // An ambushed convoy on a dirt track: three burnt-out lorries, the middle one shoved off the track. P346 (f):
            // the track is two wheel ruts that thin out into the field at both ends (a 3-wide strip stopped dead).
            for v in -15...15 {
                let fade = Float(max(0, abs(v) - 9)) / 7
                for u in [-1, 1] where rng.chance(0.9 - 0.85 * fade) { scar(u, v) }
                if abs(v) < 8 && rng.chance(0.3) { scar(0, v) }
            }
            lorry(0, -9); lorry(3, 0); lorry(-1, 9)
            debris(10, 13, [hull, olive, fence, coal])
        default:
            // A farm wall where an attack was cut down: the broken wall, a gateway, a ruined cottage, a dead tree.
            for u in -12...12 {
                let x = X(u, 3), z = Z(u, 3), t = g.top(x, z)
                if abs(u) <= 1 { if abs(u) == 1 { put(u, t + 1, 3, cobble); put(u, t + 2, 3, cobble); put(u, t + 3, 3, mossy) }; continue }
                let h = hash3(x, 3, z, 0xA11)
                if h % 7 == 0 { continue }                                                       // a breach
                put(u, t + 1, 3, h % 3 == 0 ? mossy : cobble)
                if h % 5 > 1 { put(u, t + 2, 3, h % 2 == 0 ? mossy : cobble) }
            }
            for u in -14...(-9) { for v in -11...(-6) where u == -14 || u == -9 || v == -11 || v == -6 {
                let x = X(u, v), z = Z(u, v), t = g.top(x, z)
                let h = hash3(x, 11, z, 0xA12)
                let hgt = h % 4
                if hgt == 0 || (v == -6 && u == -11) { continue }
                for dy in 1...Int(hgt) { put(u, t + dy, v, h % 3 == 0 ? mossy : cobble) }
            } }
            let tree = TreeWriter(b: w.blocks, bx: w.bx, bz: w.bz)
            var trng = SRng(UInt64(hash3(s.x, 0xDEAD, s.z, g.s32)) | 1)
            let tx = X(10, -5), tz = Z(10, -5)
            TreePlacer.build(tree, .deadOak, tx, g.top(tx, tz) + 1, tz, &trng)
            for _ in 0..<8 { scar(rng.range(-10, 10), rng.range(-8, 2)) }
        }
    }
}

// MARK: The fallen

// Fallen Allied soldiers (P326 b: "dead Germans aren't scary, dead Allies are"): olive-drab bodies lying on their backs
// at the scenes and along the Ember Line's wire, as the dead lie after the fall (deathT past it). Not mobs: never
// updated, hit or saved; drawn with the mobs (writeMobVertices), rebuilt as the player moves about the vault.
enum AshFallen {
    static var mobs: [Mob] = []
    private static var built: [Int64: (bodies: [Mob], want: Int)] = [:]
    static let reach: Float = 80
    static let cap = 24
    static let wireR: Float = 446, wireStep: Float = 18

    // The fallen along the wire: a few in two segments of five (world x, z, heading).
    static func wire(_ i: Int) -> [(Float, Float, Float)] {
        let n = Int(2 * Float.pi * wireR / wireStep)
        let k = ((i % n) + n) % n
        let h = hash3(k, 0x7A11, 0, 0x5A1)
        guard h % 5 < 2 else { return [] }
        let da = 2 * Float.pi / Float(n)
        var out: [(Float, Float, Float)] = []
        for j in 0..<(1 + Int((h >> 4) % 3)) {
            let q = hash3(k, j, 0x7A12, 0x5A2)
            let a = (Float(k) + Float(q & 255) / 256) * da
            let r = 434 + Float((q >> 8) % 40)
            let x = sinf(a) * r, z = -cosf(a) * r
            if AshWar.roadDistance(Int(x), Int(z)) < 8 { continue }
            out.append((x, z, Float(q >> 16 & 255) / 256 * 2 * .pi))
        }
        return out
    }

    // Once a second (Game.ashTick).
    static func refresh(_ g: Game) {
        guard g.dim.dim == .deep, DeepGen.inVault(g.player.pos.y), let dg = g.world.gen as? DeepGen else {
            if !mobs.isEmpty || !built.isEmpty { mobs = []; built = [:] }
            AshWrecks.clear()
            return
        }
        let p = g.player.pos
        var want = Set<Int64>()
        func lay(_ key: Int64, _ spots: [(Float, Float, Float)]) {
            want.insert(key)
            if let b = built[key], b.bodies.count == b.want { return }
            built[key] = (spots.compactMap { body($0.0, $0.1, $0.2, g, dg) }, spots.count)
        }
        for s in AshFront.scenes(Int(p.x - reach), Int(p.z - reach), Int(p.x + reach), Int(p.z + reach), pad: 0, ground: dg.ground) {
            lay(StructureCache.key(s.x, s.z), AshFront.fallen(s))
        }
        let d = simd_length(V2(p.x, p.z))
        if d > wireR - reach - 20 && d < wireR + reach + 40 {
            let n = Int(2 * Float.pi * wireR / wireStep)
            let a = atan2f(p.x, -p.z), da = 2 * Float.pi / Float(n)
            let i0 = Int(floorf(a / da)), span = Int(ceilf(reach / (wireR * da))) + 1
            for i in (i0 - span)...(i0 + span) { lay(Int64(((i % n) + n) % n) | (1 << 40), wire(i)) }
        }
        built = built.filter { want.contains($0.key) }
        var all: [Mob] = []
        for (_, b) in built { all += b.bodies }
        all.sort { simd_length_squared($0.pos - p) < simd_length_squared($1.pos - p) }
        mobs = Array(all.prefix(cap))
        AshWrecks.refresh(g, dg)
    }

    // A body on the ground at (x, z) (the world's own ground there: an old save's floor too), nil while unloaded.
    static func body(_ x: Float, _ z: Float, _ yaw: Float, _ g: Game, _ dg: DeepGen) -> Mob? {
        let ix = Int(floorf(x)), iz = Int(floorf(z))
        guard g.world.isLoaded(ix, iz) else { return nil }
        let t = dg.ground.top(ix, iz)
        var y = -1
        for yy in stride(from: t + 6, through: max(1, t - 6), by: -1) where g.world.solidAt(ix, yy, iz) { y = yy + 1; break }
        guard y > 0 else { return nil }
        let m = Mob(.soldierTrooper, at: V3(x, Float(y), z))
        m.fallen = true
        m.lying = true                                          // P346: flat on his back (AshWrecks.fallenAlliedParts)
        m.yaw = yaw
        m.variant = Guns.rifle
        m.brain = SoldierBrain(gun: Guns.rifle)
        m.health = 0
        m.deathT = MobAnim.deathTime * 2
        m.onGround = true
        return m
    }
}
