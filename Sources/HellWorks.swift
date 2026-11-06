import Foundation
import simd

// P508 (Remington, Nov 1 16:26: "hell needs more base type things, make it so potions can spawn there and that some sort of
// material is required to make potions and maybe some sort of material required to build high tech stuff maybe make it
// only found in those bases. by base, i mean some different ideas completely different to the burgundy greywall base
// copy, keep that but add completely different ideas... its too empty now and so is hell"). The Brand Chapterhouse (the
// red walled compound) stays; between the chapterhouses and roosts stand the Hell Works, three designs of their own:
//   Cinder Distillery  the Order's brewers: a gold-banded basalt still-house under a stepped dome, two glass alembic
//                      towers with lava rising in them, benches of brewing stands, cauldrons, racks of finished tonics,
//                      and a sunken grotto whose walls are Brimsalt veins
//   Chain Gaol         a prison over the lava sea: a round warden's tower in the middle, four bridges out to barred cells
//                      on piers, iron cages hung on chains from the cavern roof, the warden's strongroom on top
//   Brimsalt Quarry    a rock mesa out of the lava, its top quarried into stepped terraces down to a seam of Brimsalt;
//                      charwood cranes over the pit, a foreman's hut and a rail run on the rim
// Brimsalt (the amber salt that crystallises where lava meets the hell rock) fuels the brewing stand, so every potion
// needs it, and grows only in these works' veins and chests. Tech Salvage (the Upgrade Bench's part, P508) is found only
// in their chests. Hell's own garrison holds them (the Brand Order, Slagthrowers, Searwings, Scorchlings).
// Ground a save generated before P508 gets none (structure-guard-p508.txt), so no half-built works stand at its edge.
enum P508Guard {
    static var nether: Set<Int64> = []
    static var deep: Set<Int64> = []
}

enum HellWorks {
    static let kind = "hell_works"
    static let names = ["Cinder Distillery", "Chain Gaol", "Brimsalt Quarry"]
    static let brimsalt = "brimsalt", vein = "brimsalt_vein"
    static let spacing = 18, deepSpacing = 22                    // chunks (the chapterhouse/roost grid is 27; the Deep's 44)
    static let reach = 3
    static var made = [0, 0, 0]                                   // (harness: works built, by design)
    static func blk(_ k: String, _ alt: BlockID = STONE) -> BlockID { Blocks.has(k) ? Blocks.id(k) : alt }

    static func variant(_ seed: UInt64) -> Int {
        var z = seed &+ 0x6A09_E667_F3BC_C909
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Int((z ^ (z >> 31)) % 3)
    }

    // The works' chunk in region (rx, rz), clear of the other hell sites, or nil.
    static func spot(_ worldSeed: UInt64, _ rx: Int, _ rz: Int, deep: Bool, guardSet: DeepGuard?) -> (Int, Int)? {
        let sp = deep ? deepSpacing : spacing
        var rng = SRng(worldSeed ^ 0x4E11_3083 &+ UInt64(bitPattern: Int64(rx)) &* 0x9E37_79B9 &+ UInt64(bitPattern: Int64(rz)) &* 0x85EB_CA6B)
        let cache = StructureCache(seed: worldSeed, types: [])
        for _ in 0..<10 {
            let cx = rx * sp + 3 + rng.int(sp - 6), cz = rz * sp + 3 + rng.int(sp - 6)
            if deep {
                guard BrimstoneKeep.clearOfFortresses(worldSeed, cx, cz, 8), guardSet?.clear(cx, cz, reach + 1) ?? true else { continue }
                var near = false
                let ks = BrimstoneKeep.spacing
                for kz in floorDiv(cz - 12, ks)...floorDiv(cz + 12, ks) { for kx in floorDiv(cx - 12, ks)...floorDiv(cx + 12, ks) {
                    if let (px, pz) = BrimstoneKeep.spot(worldSeed, kx, kz), abs(px - cx) < 10 && abs(pz - cz) < 10 { near = true }
                } }
                let bs = Bastion.deepSpacing
                for bz in floorDiv(cz - 10, bs)...floorDiv(cz + 10, bs) { for bx in floorDiv(cx - 10, bs)...floorDiv(cx + 10, bs) {
                    if let g = guardSet, let (px, pz) = Bastion.deepSpot(worldSeed, bx, bz, guardSet: g), abs(px - cx) < 8 && abs(pz - cz) < 8 { near = true }
                } }
                if near { continue }
            } else {
                // The Emberdeep's chapterhouses and roosts share one grid (Fortress.type / Bastion.type).
                var near = false
                let fs = Fortress.type.spacing
                for fz in floorDiv(cz - 10, fs)...floorDiv(cz + 10, fs) { for fx in floorDiv(cx - 10, fs)...floorDiv(cx + 10, fs) {
                    let (px, pz) = cache.candidate(Fortress.type, fx, fz)
                    if abs(px - cx) < 9 && abs(pz - cz) < 9 { near = true }
                } }
                if near { continue }
            }
            return (cx, cz)
        }
        return nil
    }

    static func type(worldSeed: UInt64, base: Int, deep: Bool, guardSet: DeepGuard? = nil) -> StructureType {
        let sp = deep ? deepSpacing : spacing
        return StructureType(name: kind, spacing: sp, separation: 4, salt: 0x4E11_3083, reach: reach) { seed, cx, cz in
            let rx = floorDiv(cx, sp), rz = floorDiv(cz, sp)
            guard let (kx, kz) = spot(worldSeed, rx, rz, deep: deep, guardSet: guardSet) else { return nil }
            if G20Guard.legacy(deep ? P508Guard.deep : P508Guard.nether, kx, kz, reach: reach + 1) { return nil }
            return start(variant(seed), ox: kx * CS + 8, oz: kz * CS + 8, base: base, seed: seed, deep: deep)
        }
    }
    static func start(_ v: Int, ox: Int, oz: Int, base: Int, seed: UInt64, deep: Bool = false) -> StructureStart {
        var rng = SRng(seed ^ 0x77E1)
        let f = base + rng.range(42, 50)
        let s = rng.next()
        let piece = Piece(min: IVec3(ox - 34, base + 1, oz - 34), max: IVec3(ox + 34, f + 38, oz + 34)) { w in
            build(&w, v, ox: ox, oz: oz, f: f, base: base, seed: s, deep: deep)
        }
        return StructureStart(kind: kind, pieces: [piece], anchor: IVec3(ox, f + 1, oz))
    }

    static func build(_ w: inout StructWriter, _ v: Int, ox: Int, oz: Int, f: Int, base: Int, seed: UInt64, deep: Bool) {
        var b = Builder(ox: ox, oz: oz, f: f, base: base, tag: deep ? "@deep" : "", rng: SRng(seed ^ 0xD157))
        switch v {
        case 0: b.distillery(&w)
        case 1: b.gaol(&w)
        default: b.quarry(&w)
        }
        made[v] += 1
    }

    // The palette and the little helpers every design uses.
    struct Builder {
        let ox: Int, oz: Int, f: Int, base: Int, tag: String
        var rng: SRng
        let basalt = HellWorks.blk("basalt"), smooth = HellWorks.blk("smooth_basalt", HellWorks.blk("basalt")), onyx = HellWorks.blk("blackstone")
        let dark = HellWorks.blk("polished_blackstone_bricks"), trim = HellWorks.blk("polished_blackstone", HellWorks.blk("blackstone"))
        let chisel = HellWorks.blk("chiseled_polished_blackstone", HellWorks.blk("blackstone")), gild = HellWorks.blk("gilded_blackstone", HellWorks.blk("blackstone"))
        let gold = HellWorks.blk("gold_block"), bone = HellWorks.blk("bone_block"), glass = HellWorks.blk("glass")
        let bars = HellWorks.blk("iron_bars"), chain = HellWorks.blk("chain", HellWorks.blk("iron_bars")), fence = HellWorks.blk("blackstone_wall", HellWorks.blk("iron_bars"))
        let lantern = HellWorks.blk("soul_lantern", HellWorks.blk("lantern")), hanging = HellWorks.blk("soul_lantern[hanging]", HellWorks.blk("lantern[hanging]", HellWorks.blk("lantern")))
        let fire = HellWorks.blk("campfire", HellWorks.blk("magma_block")), magma = HellWorks.blk("magma_block"), ladder = HellWorks.blk("ladder")
        let planks = HellWorks.blk("crimson_planks", HellWorks.blk("polished_blackstone")), slab = HellWorks.blk("polished_blackstone_slab", HellWorks.blk("polished_blackstone"))
        let stand = HellWorks.blk("brewing_stand", HellWorks.blk("polished_blackstone")), cauldron = HellWorks.blk("water_cauldron", HellWorks.blk("cauldron", STONE))
        let lavaPot = HellWorks.blk("lava_cauldron", HellWorks.blk("cauldron", STONE)), barrel = HellWorks.blk("barrel", HellWorks.blk("crimson_planks")), skull = HellWorks.blk("skeleton_skull", AIR)
        let rail = HellWorks.blk("rail", AIR), anvil = HellWorks.blk("anvil", HellWorks.blk("polished_blackstone")), vein = HellWorks.blk(HellWorks.vein, HellWorks.blk("magma_block"))

        init(ox: Int, oz: Int, f: Int, base: Int, tag: String, rng: SRng) {
            self.ox = ox; self.oz = oz; self.f = f; self.base = base; self.tag = tag; self.rng = rng
        }
        func at(_ w: inout StructWriter, _ dx: Int, _ y: Int, _ dz: Int, _ bl: BlockID) { w.set(ox + dx, y, oz + dz, bl) }
        func box(_ w: inout StructWriter, _ dx0: Int, _ y0: Int, _ dz0: Int, _ dx1: Int, _ y1: Int, _ dz1: Int, _ bl: BlockID) {
            w.fill(ox + dx0, y0, oz + dz0, ox + dx1, y1, oz + dz1, bl)
        }
        func mob(_ w: inout StructWriter, _ k: String, _ dx: Int, _ y: Int, _ dz: Int) {
            w.mob(k + tag, V3(Float(ox + dx) + 0.5, Float(y), Float(oz + dz) + 0.5))
        }
        mutating func chest(_ w: inout StructWriter, _ dx: Int, _ y: Int, _ dz: Int, _ table: String, facing: Int) {
            w.chest(ox + dx, y, oz + dz, loot: table, seed: rng.next(), facing: facing)
        }
        // A rounded hollow of air in the hell rock: rx by rz, its roof `low` over the floor at the rim, `high` in the middle.
        func hollow(_ w: inout StructWriter, rx: Int, rz: Int, low: Int, high: Int) {
            for dz in -rz...rz { for dx in -rx...rx {
                let qx = Float(dx) / Float(rx), qz = Float(dz) / Float(rz)
                let q: Float = qx * qx * qx * qx + qz * qz * qz * qz
                guard q <= 1 else { continue }
                let top = f + low + Int(Float(high - low) * sqrtf(1 - q))
                box(&w, dx, f + 1, dz, dx, top, dz, AIR)
            } }
        }
        func pier(_ w: inout StructWriter, _ dx: Int, _ y: Int, _ dz: Int) { w.pillarDown(ox + dx, y, oz + dz, basalt, minY: base + 1) }
        // A ring (Chebyshev or round) of blocks at one height.
        func ring(_ w: inout StructWriter, _ cx: Int, _ cz: Int, _ r: Int, _ y: Int, _ bl: BlockID) {
            for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r { at(&w, cx + dx, y, cz + dz, bl) } }
        }
        func disc(_ w: inout StructWriter, _ cx: Int, _ cz: Int, _ r: Float, _ y0: Int, _ y1: Int, _ bl: BlockID, shell: Float = 0) {
            let ri = Int(ceil(r))
            for dz in -ri...ri { for dx in -ri...ri {
                let d = sqrtf(Float(dx * dx + dz * dz))
                if d <= r && (shell == 0 || d > r - shell) { box(&w, cx + dx, y0, cz + dz, cx + dx, y1, cz + dz, bl) }
            } }
        }
        // The way in from the cavern: a causeway south to the hollow's edge, braziers along it.
        func causeway(_ w: inout StructWriter, from z0: Int, to z1: Int) {
            box(&w, -2, f - 1, z0, 2, f, z1, dark)
            box(&w, -2, f, z0, 2, f, z1, trim)
            box(&w, -2, f + 1, z0, 2, f + 5, z1, AIR)
            for dz in stride(from: z0, through: z1, by: 4) {
                at(&w, -3, f + 1, dz, chisel); at(&w, -3, f + 2, dz, fire); at(&w, 3, f + 1, dz, chisel); at(&w, 3, f + 2, dz, fire)
                pier(&w, -2, f - 2, dz); pier(&w, 2, f - 2, dz)
            }
        }

        // MARK: Cinder Distillery
        mutating func distillery(_ w: inout StructWriter) {
            hollow(&w, rx: 28, rz: 26, low: 14, high: 26)
            // A platform of basalt flagged in smooth basalt, gold-edged, on piers into the lava.
            box(&w, -22, f - 3, -23, 22, f, 18, basalt)
            box(&w, -21, f, -22, 21, f, 17, smooth)
            for i in stride(from: -22, through: 22, by: 2) { at(&w, i, f, -23, gild); at(&w, i, f, 18, gild) }
            for dz in stride(from: -23, through: 18, by: 6) { for dx in stride(from: -22, through: 22, by: 7) { pier(&w, dx, f - 4, dz) } }
            causeway(&w, from: 19, to: 30)

            // The still-house: smooth basalt walls banded in gold, a stepped onyx dome with a glass eye.
            let x0 = -15, x1 = 15, z0 = -16, z1 = -2
            box(&w, x0, f + 1, z0, x1, f + 8, z1, smooth)
            box(&w, x0 + 1, f + 1, z0 + 1, x1 - 1, f + 8, z1 - 1, AIR)
            for y in [f + 1, f + 5] { for dx in x0...x1 { at(&w, dx, y, z0, gold); at(&w, dx, y, z1, gold) }
                                      for dz in z0...z1 { at(&w, x0, y, dz, gold); at(&w, x1, y, dz, gold) } }
            for k in 0..<4 { box(&w, x0 + 2 * k, f + 9 + k, z0 + k, x1 - 2 * k, f + 9 + k, z1 - k, k % 2 == 0 ? onyx : dark) }
            box(&w, x0 + 9, f + 12, z0 + 4, x1 - 9, f + 12, z1 - 4, glass)
            box(&w, -1, f + 1, z1, 1, f + 4, z1, AIR)                                         // the door
            for dx in stride(from: x0 + 3, through: x1 - 3, by: 4) where abs(dx) > 2 { box(&w, dx, f + 3, z1, dx, f + 6, z1, bars) }
            // Benches of brewing stands down both sides, cauldrons along the back, the racks between.
            for dz in [z0 + 3, z1 - 4] {
                box(&w, x0 + 2, f + 1, dz, -2, f + 1, dz, slab); box(&w, 2, f + 1, dz, x1 - 2, f + 1, dz, slab)   // (a gap down the middle)
                for dx in stride(from: x0 + 3, through: x1 - 3, by: 3) where abs(dx) > 1 { at(&w, dx, f + 2, dz, stand) }
            }
            for dx in stride(from: x0 + 2, through: x1 - 2, by: 2) where abs(dx) > 1 { at(&w, dx, f + 1, z0 + 1, dx % 4 == 0 ? lavaPot : cauldron) }
            chest(&w, x0 + 1, f + 1, z0 + 6, "hell_distillery", facing: 2)
            chest(&w, x1 - 1, f + 1, z0 + 6, "hell_distillery", facing: 3)
            chest(&w, x0 + 1, f + 1, z1 - 2, "hell_distillery", facing: 2)
            for (dx, dz) in [(-8, -9), (0, -9), (8, -9)] { at(&w, dx, f + 8, dz, chain); at(&w, dx, f + 7, dz, hanging) }
            // The master's strongroom behind the back wall: bars, a gilded floor, the works' vault chest.
            box(&w, -4, f + 1, z0 - 5, 4, f + 6, z0, dark)
            box(&w, -3, f + 1, z0 - 4, 3, f + 5, z0 - 1, AIR)
            box(&w, -3, f, z0 - 4, 3, f, z0 - 1, gild)
            box(&w, -1, f + 1, z0, 1, f + 3, z0, bars)
            at(&w, 0, f + 1, z0, AIR); at(&w, 0, f + 2, z0, AIR)
            chest(&w, -2, f + 1, z0 - 4, "hell_works_vault", facing: 0)
            chest(&w, 2, f + 1, z0 - 4, "hell_distillery", facing: 0)
            // Two alembic towers by the door: glass columns with lava rising in them, gold caps, chains to the dome.
            for sx in [-1, 1] {
                let tx = 6 * sx, tz = 2
                disc(&w, tx, tz, 2.4, f + 1, f + 12, glass)
                disc(&w, tx, tz, 1.2, f + 1, f + 11, LAVA)
                disc(&w, tx, tz, 2.4, f + 13, f + 13, gold)
                disc(&w, tx, tz, 2.6, f + 1, f + 1, dark, shell: 0.9)
                at(&w, tx, f + 14, tz, fire)
            }
            // Chimneys off the dome's shoulders.
            for dx in [-12, 12] { box(&w, dx, f + 9, -13, dx + 1, f + 18, -12, dark); at(&w, dx, f + 19, -13, fire) }
            // The Brimsalt grotto: a sunken pit walled in its veins, a magma floor, a fence round it.
            box(&w, -14, f - 4, 5, -6, f, 13, basalt)
            box(&w, -13, f - 3, 6, -7, f, 12, AIR)
            box(&w, -13, f - 4, 6, -7, f - 4, 12, magma)
            for y in (f - 3)...f { for dz in 5...13 { for dx in -14...(-6) where dx == -14 || dx == -6 || dz == 5 || dz == 13 {
                if hashf(ox + dx, y, oz + dz, 0x5A17) < 0.55 { at(&w, dx, y, dz, vein) }
            } } }
            for dz in 6...12 { at(&w, -13, f - 3, dz, vein); at(&w, -7, f - 3, dz, vein) }
            for dz in 5...13 { at(&w, -14, f + 1, dz, fence); at(&w, -6, f + 1, dz, fence) }
            for dx in -13...(-7) { at(&w, dx, f + 1, 5, fence); at(&w, dx, f + 1, 13, fence) }
            at(&w, -10, f + 1, 13, AIR)
            box(&w, -10, f - 3, 12, -10, f, 12, ladder)
            w.spawner(ox - 10, f - 3, oz + 9, mob: "scorchling")
            // The cooling yard: barrels of the salt, an anvil, braziers, bone-block posts with lanterns.
            for (dx, dz) in [(8, 7), (9, 7), (8, 8), (11, 11), (12, 11)] { at(&w, dx, f + 1, dz, barrel) }
            at(&w, 12, f + 1, 7, anvil)
            chest(&w, 10, f + 1, 9, "hell_distillery", facing: 3)
            for (dx, dz) in [(-18, -2), (18, -2), (-18, 14), (18, 14), (-4, 16), (4, 16)] {
                box(&w, dx, f + 1, dz, dx, f + 3, dz, bone); at(&w, dx, f + 4, dz, lantern)
            }
            // The Order's brewers and their guards.
            mob(&w, "brand_squire", -6, f + 1, -9); mob(&w, "brand_squire", 6, f + 1, -9)
            mob(&w, "brand_squire", 0, f + 1, 8); mob(&w, "brand_knight", -2, f + 1, 17); mob(&w, "brand_knight", 2, f + 1, 17)
            mob(&w, "brand_champion", 0, f + 1, -18)
            mob(&w, "slagthrower", -10, f + 12, -9); mob(&w, "slagthrower", 10, f + 12, -9)
        }

        // MARK: Chain Gaol
        mutating func gaol(_ w: inout StructWriter) {
            hollow(&w, rx: 30, rz: 30, low: 18, high: 36)
            let roof = f + 30
            // The warden's tower: a round basalt drum from the lava floor, three floors, a crown of onyx merlons.
            disc(&w, 0, 0, 5.5, base + 1, f, basalt)
            disc(&w, 0, 0, 5.5, f + 1, f + 22, basalt, shell: 1.2)
            for y in [f + 6, f + 13, f + 20] { disc(&w, 0, 0, 5.5, y, y, dark, shell: 1.2) }
            for y in [f, f + 8, f + 16] { disc(&w, 0, 0, 4.4, y, y, trim) }
            disc(&w, 0, 0, 5.5, f + 23, f + 23, dark)
            // (Against the north wall, up through the hatches. Ledger 34: beside the north door, not in front of it: its
            // first three rungs hung on the doorway.)
            box(&w, 1, f + 1, -4, 1, f + 23, -4, ladder + 1)
            for a in stride(from: 0, to: 360, by: 30) {
                let r: Float = 5, t = Float(a) * .pi / 180
                at(&w, Int((cosf(t) * r).rounded()), f + 24, Int((sinf(t) * r).rounded()), onyx)
            }
            for (dx, dz) in [(5, 0), (-5, 0), (0, 5), (0, -5)] { box(&w, dx, f + 1, dz, dx, f + 3, dz, AIR) }   // doors onto the bridges
            for (dx, dz) in [(5, 0), (-5, 0), (0, -5), (0, 5)] { box(&w, dx, f + 10, dz, dx, f + 11, dz, bars) }   // slit windows
            // The warden's floor: his strongroom chest, a gilded seat, lanterns.
            chest(&w, -2, f + 17, 2, "hell_works_vault", facing: 0)
            chest(&w, 2, f + 17, 2, "hell_gaol", facing: 0)
            at(&w, 0, f + 17, 3, gild); at(&w, 0, f + 22, 0, chain); at(&w, 0, f + 21, 0, hanging)
            chest(&w, 2, f + 9, -2, "hell_gaol", facing: 2)
            // Four bridges out to the cell blocks on piers; the south one runs on to the cavern's edge.
            for (sx, sz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let len = 17
                for i in 6...len {
                    let x = sx * i, z = sz * i, px = sz, pz = sx            // across the bridge
                    for k in -1...1 { at(&w, x + px * k, f, z + pz * k, k == 0 ? trim : dark) }
                    at(&w, x + px * 2, f + 1, z + pz * 2, fence); at(&w, x - px * 2, f + 1, z - pz * 2, fence)
                    if i % 5 == 0 { pier(&w, x, f - 1, z) }
                }
                // The cell block: a 7 x 7 slab on a pier, two barred cells, a guard post.
                let cx = sx * 21, cz = sz * 21
                box(&w, cx - 3, f - 2, cz - 3, cx + 3, f, cz + 3, dark)
                pier(&w, cx, f - 3, cz); pier(&w, cx - 3, f - 3, cz - 3); pier(&w, cx + 3, f - 3, cz + 3)
                for side in [-1, 1] {
                    let ex = cx + (sz != 0 ? side * 2 : 0), ez = cz + (sx != 0 ? side * 2 : 0)
                    for dz in -1...1 { for dx in -1...1 where abs(dx) == 1 || abs(dz) == 1 { box(&w, ex + dx, f + 1, ez + dz, ex + dx, f + 3, ez + dz, bars) } }
                    box(&w, ex - 1, f + 4, ez - 1, ex + 1, f + 4, ez + 1, dark)
                    if side > 0 { chest(&w, ex, f + 1, ez, "hell_gaol", facing: sx != 0 ? 0 : 2) } else { at(&w, ex, f + 1, ez, skull) }
                }
                // (the passage between the two cells is the way through; braziers on the slab's corners)
                for (kx, kz) in [(-3, -3), (3, 3)] { at(&w, cx + kx, f + 1, cz + kz, chisel); at(&w, cx + kx, f + 2, cz + kz, fire) }
            }
            causeway(&w, from: 25, to: 32)
            // Iron cages hung on chains from the cavern roof between the bridges, some with a skull in them.
            for k in 0..<6 {
                let t = (Float(k) + 0.5) * .pi / 3
                let cx = Int((cosf(t) * 12).rounded()), cz = Int((sinf(t) * 12).rounded())
                let y0 = f + 5 + (k % 3) * 2
                box(&w, cx - 1, y0, cz - 1, cx + 1, y0, cz + 1, dark)
                for dz in -1...1 { for dx in -1...1 where abs(dx) == 1 || abs(dz) == 1 { box(&w, cx + dx, y0 + 1, cz + dz, cx + dx, y0 + 3, cz + dz, bars) } }
                box(&w, cx - 1, y0 + 4, cz - 1, cx + 1, y0 + 4, cz + 1, dark)
                if k % 2 == 0 { at(&w, cx, y0 + 1, cz, skull) }
                box(&w, cx, y0 + 5, cz, cx, roof + 4, cz, chain)
            }
            w.spawner(ox, f + 23, oz + 2, mob: "searwing")
            mob(&w, "brand_knight", 9, f + 1, 1); mob(&w, "brand_knight", -9, f + 1, -1); mob(&w, "brand_knight", 1, f + 1, 23)
            mob(&w, "brand_squire", 21, f + 1, 2); mob(&w, "brand_squire", -21, f + 1, -2); mob(&w, "brand_squire", 2, f + 1, -21)
            mob(&w, "brand_champion", 1, f + 17, -1)
            mob(&w, "slagthrower", 2, f + 24, 0)
        }

        // MARK: Brimsalt Quarry
        mutating func quarry(_ w: inout StructWriter) {
            hollow(&w, rx: 30, rz: 30, low: 16, high: 26)
            // The mesa: a rough round plug of basalt and onyx from the lava floor to the rim.
            for dz in -28...28 { for dx in -28...28 {
                let d = sqrtf(Float(dx * dx + dz * dz))
                let edge: Float = 27 + (hashf((ox + dx) / 3, 0, (oz + dz) / 3, 0x0A11) - 0.5) * 3
                guard d <= edge else { continue }
                let rock = hashf(ox + dx, 1, oz + dz, 0x0A12) < 0.3 ? onyx : basalt
                box(&w, dx, base + 1, dz, dx, f, dz, rock)
            } }
            // Terraces down into it, each riser seamed with Brimsalt, the seam thickest at the bottom.
            let steps: [(Float, Int)] = [(15, 0), (11, 4), (7, 8), (4, 12)]
            for (r, depth) in steps {
                let ri = Int(ceil(r))
                for dz in -ri...ri { for dx in -ri...ri {
                    let d = sqrtf(Float(dx * dx + dz * dz))
                    guard d <= r else { continue }
                    box(&w, dx, f - depth - 3, dz, dx, f, dz, AIR)
                    let floorB = d > r - 1.5 ? trim : onyx
                    at(&w, dx, f - depth - 4, dz, floorB)
                } }
            }
            for (r, depth) in steps {
                let ri = Int(ceil(r)) + 1
                for dz in -ri...ri { for dx in -ri...ri {
                    let d = sqrtf(Float(dx * dx + dz * dz))
                    guard d > r && d <= r + 1.2 else { continue }
                    for y in (f - depth - 3)...(f - depth) where hashf(ox + dx, y, oz + dz, 0x0A13) < (depth >= 12 ? 0.7 : 0.28) {
                        at(&w, dx, y, dz, vein)
                    }
                } }
            }
            box(&w, -2, f - 19, -2, 2, f - 17, 2, vein)                  // the mother seam under the pit floor
            box(&w, -1, f - 16, -1, 1, f - 16, 1, AIR)
            // Ramps down the terraces on the south side (a stair of slabs and blocks).
            for i in 0...12 {
                box(&w, -1, f - 16, 15 - i, 1, f - i - 1, 15 - i, basalt)
                box(&w, -1, f - i, 15 - i, 1, f - i, 15 - i, trim)
                box(&w, -1, f - i + 1, 15 - i, 1, f - i + 3, 15 - i, AIR)
            }
            box(&w, 0, f - 15, 2, 0, f - 12, 2, ladder)                  // (the last drop to the seam, against the ramp's foot)
            // Charwood cranes on the rim, chains down into the pit with a bucket on each.
            for (sx, sz) in [(1, -1), (-1, -1)] {
                let cx = 15 * sx, cz = 12 * sz
                box(&w, cx, f + 1, cz, cx, f + 12, cz, planks)
                box(&w, cx - 1, f + 1, cz - 1, cx + 1, f + 1, cz + 1, planks)
                let jx = -sx, jz = -sz
                for i in 1...7 { at(&w, cx + jx * i, f + 12, cz + jz * i, planks) }
                at(&w, cx - jx * 1, f + 12, cz - jz * 1, planks); at(&w, cx - jx * 1, f + 11, cz - jz * 1, gold)
                let hx = cx + jx * 7, hz = cz + jz * 7
                box(&w, hx, f - 3, hz, hx, f + 11, hz, chain)
                at(&w, hx, f - 4, hz, lavaPot)
            }
            // The foreman's hut on the rim (north-east), a rail run past it with the day's carts' rails, braziers.
            box(&w, 10, f + 1, 14, 16, f + 5, 19, planks)
            box(&w, 11, f + 1, 15, 15, f + 4, 18, AIR)
            box(&w, 10, f + 6, 14, 16, f + 6, 19, dark)
            box(&w, 10, f + 1, 16, 10, f + 3, 17, AIR)
            box(&w, 16, f + 2, 16, 16, f + 3, 17, bars)
            chest(&w, 15, f + 1, 15, "hell_works_vault", facing: 3)
            chest(&w, 15, f + 1, 18, "hell_quarry", facing: 3)
            at(&w, 12, f + 1, 18, anvil); at(&w, 13, f + 4, 16, hanging)
            box(&w, -14, f, 21, 8, f, 21, trim)
            for dx in -14...8 { at(&w, dx, f + 1, 21, rail) }
            for (dx, dz) in [(-13, 17), (-12, 17), (-9, 17), (5, 17), (6, 17)] { at(&w, dx, f + 1, dz, barrel) }
            chest(&w, -11, f + 1, 18, "hell_quarry", facing: 0)
            chest(&w, 3, f - 11, -4, "hell_quarry", facing: 1)
            for (dx, dz) in [(-19, -6), (19, -6), (-8, -19), (8, -19), (-19, 10)] {
                at(&w, dx, f + 1, dz, chisel); at(&w, dx, f + 2, dz, fire)
            }
            causeway(&w, from: 25, to: 31)
            w.spawner(ox - 2, f - 15, oz - 2, mob: "scorchling")
            mob(&w, "brand_squire", 8, f - 7, 0); mob(&w, "brand_squire", -6, f - 11, 2); mob(&w, "brand_squire", 0, f - 3, -14)
            mob(&w, "brand_knight", 15, f + 1, 13); mob(&w, "brand_knight", -2, f + 1, 22)
            mob(&w, "brand_champion", 13, f + 1, 16)
            mob(&w, "slagthrower", -15, f + 1, -12); mob(&w, "slagthrower", 15, f + 13, -12)
        }
    }
}

// MARK: Brimsalt: the vein block, the salt, its looks

extension BlockRegistry {
    func registerHellWorksBlocks() {
        guard !has(HellWorks.vein) else { return }
        var d = BlockDef(HellWorks.vein, "Brimsalt Vein")
        d.tex = [HellWorks.vein]
        d.hardness = 3.5; d.resistance = 6
        d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 2; d.sound = .stone; d.emit = 7
        add(d)
    }
}

extension ItemRegistry {
    func registerHellWorksItems() {
        guard !has(HellWorks.brimsalt) else { return }
        var d = ItemDef(HellWorks.brimsalt, "Brimsalt")
        d.sprite = Sprite(mask: "gem", base: 0xF0A040, extras: [:])
        add(d)
    }
}

extension TextureGen {
    static func hellWorksPainters(_ p: inout [String: Painter]) {
        // Dark basalt with amber salt crystals grown in its cracks, brightest at their hearts.
        p[HellWorks.vein] = { x, y in
            let cx = [4, 11, 7, 2, 13], cy = [3, 5, 11, 12, 13]
            for i in 0..<5 {
                let d = abs(x - cx[i]) + abs(y - cy[i])
                if d == 0 { return hex(0xFFE0A0) }
                if d == 1 { return hex(i % 2 == 0 ? 0xFFB050 : 0xF09038, 0.95 + 0.1 * r(x, y, 5120 + i)) }
                if d == 2 && r(x, y, 5130 + i) > 0.45 { return hex(0xB06020, 0.9 + 0.2 * r(x, y, 5140)) }
            }
            let n = r(x / 2, y / 2, 5101) * 0.6 + r(x, y, 5102) * 0.4
            return hex(0x2B2828, 0.8 + 0.35 * n)
        }
    }
}
