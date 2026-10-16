import Foundation

// P292 (c): hell's own fortress and roost, in place of the copies: the reference nether fortress's network of bridges
// and corridors (and its G20 rebuild, the Ash Foundry, which was the Ashguard's: they live below the Sealrock), and the
// bastion slot's Boarling Mound (the boarlings are retired, HellOwn.swift).
//
// The Brand Chapterhouse ("fortress" slot, Fortress.type / deepType): the Brand Order's house in hell. A walled compound on
// an onyxstone platform raised on piers over the lava. A red ember-brick curtain wall with a walk behind its crenels,
// four square corner towers (ladders inside, landings onto the walk, a roof deck; the north-west one a tall bell tower
// where the Searwings roost), a gatehouse on the south side with a raised portcullis, and a causeway of braziers out from
// it. Round the courtyard: the chapter hall in the north (pillars, a dais and the commander's seat, the order's
// chests), the forge in the east (a lava trough, a blast furnace and anvil, a caged Slagthrower that feeds the fire, a
// chimney), the barracks in the west (bunks and lockers). In the courtyard: a brazier well, two Brimroot beds, a
// scorchling pit, lantern posts.
//
// The Searwing Roost ("bastion" slot, Bastion.type / deepType): a tall spire of onyxstone and basalt on a rock islet that
// the Searwings have taken. A stair winds up round its outside past ledges with nests of charwood and fronds, to the
// treasure nest on top (the old bastion loot: gold, netherite scrap); a scorchling den in its roots.
//
// Ground a save generated before P292 keeps the design it had (P292Guard, as G20Guard), so nothing is left half built.
enum P292Guard {
    static var nether: Set<Int64> = []           // structure-guard-p292.txt (World.init)
    static var deep: Set<Int64> = []
}

enum BrandChapterhouse {
    static let name = "Brand Chapterhouse"
    // What a chapterhouse (and the old fortress designs) are floored with: a spawn on these inside a "fortress" start
    // is the garrison's (Mob.trySpawnEmberdeep), standing on them there is "Fortified" (Advancements).
    static let floorKeys: Set<String> = ["polished_blackstone", "polished_blackstone_bricks", "chiseled_polished_blackstone",
                                         "red_nether_bricks", "nether_bricks", "steel_plating"]
    static let floor: [Bool] = (0..<Blocks.count).map { floorKeys.contains(Blocks.key(Blocks.groupBase[$0])) }
    static func isFloor(_ b: BlockID) -> Bool { Int(b) < floor.count && floor[Int(b)] }

    // Draws its floor height from the caller's generator (the slot's own).
    static func start(_ rng: inout SRng, ox: Int, oz: Int, base: Int) -> StructureStart {
        let f = base + rng.range(40, 54)
        let s = rng.next()
        let piece = Piece(min: IVec3(ox - 30, f - 4, oz - 26), max: IVec3(ox + 30, f + 30, oz + 33)) { w in
            build(&w, ox: ox, oz: oz, f: f, base: base, seed: s)
        }
        return StructureStart(kind: "fortress", pieces: [piece], anchor: IVec3(ox, f + 1, oz + 25))
    }

    static func build(_ w: inout StructWriter, ox: Int, oz: Int, f: Int, base: Int, seed: UInt64) {
        func g(_ k: String, _ alt: BlockID = STONE) -> BlockID { Blocks.has(k) ? Blocks.id(k) : alt }
        let dark = g("polished_blackstone_bricks"), trim = g("polished_blackstone", dark), chisel = g("chiseled_polished_blackstone", trim)
        let red = g("red_nether_bricks", dark), gild = g("gilded_blackstone", trim), basalt = g("basalt", dark), onyx = g("blackstone", dark)
        let bars = g("iron_bars"), post = g("blackstone_wall", onyx), chain = g("chain", bars)
        let lantern = g("lantern"), hanging = g("lantern[hanging]", lantern), pod = g("shroomlight", LAMP)
        let fire = g("campfire", g("magma_block")), magma = g("magma_block"), ladder = g("ladder")
        let soul = g("soul_sand"), wart = g("nether_wart"), planks = g("crimson_planks", trim), hay = g("hay_block", planks)
        let tag = base == YOFF ? "" : "@deep"
        var rng = SRng(seed ^ 0xC4A9)
        func at(_ dx: Int, _ y: Int, _ dz: Int, _ b: BlockID) { w.set(ox + dx, y, oz + dz, b) }
        func box(_ dx0: Int, _ y0: Int, _ dz0: Int, _ dx1: Int, _ y1: Int, _ dz1: Int, _ b: BlockID) {
            w.fill(ox + dx0, y0, oz + dz0, ox + dx1, y1, oz + dz1, b)
        }
        func mob(_ k: String, _ dx: Int, _ y: Int, _ dz: Int) { w.mob(k + tag, V3(Float(ox + dx) + 0.5, Float(y), Float(oz + dz) + 0.5)) }
        func brazier(_ dx: Int, _ dz: Int) { at(dx, f + 1, dz, chisel); at(dx, f + 2, dz, fire) }

        // The hollow it stands in: a rounded vault of air over the platform (high in the middle), the causeway's cut.
        for dz in -26...26 { for dx in -30...30 {
            let qx = Float(dx) / 30, qz = Float(dz) / 26
            let q: Float = qx * qx * qx * qx + qz * qz * qz * qz
            guard q <= 1 else { continue }
            let top = f + 18 + Int(12 * sqrtf(1 - q))
            box(dx, f + 1, dz, dx, top, dz, AIR)
        } }
        box(-3, f + 1, 19, 3, f + 7, 33, AIR)
        // The platform: four courses of dark brick, flagged on top, on basalt piers down to the lava floor.
        box(-24, f - 3, -20, 24, f, 20, dark)
        box(-20, f, -16, 20, f, 16, trim)
        for dz in stride(from: -20, through: 20, by: 5) { for dx in stride(from: -24, through: 24, by: 6) {
            w.pillarDown(ox + dx, f - 4, oz + dz, basalt, minY: base + 1)
        } }
        // The way in: a runner of dark brick from the gate to the well, chiselled crossings.
        box(-1, f, -5, 1, f, 16, dark)
        for dz in [0, 8] { box(-1, f, dz, 1, f, dz, chisel) }

        // Curtain walls: two thick, a dark footing, red ember brick, a flagged walk at f+8 behind crenels.
        for (dx0, dz0, dx1, dz1) in [(-22, -18, 22, -17), (-22, 17, 22, 18), (-22, -18, -21, 18), (21, -18, 22, 18)] {
            box(dx0, f + 1, dz0, dx1, f + 2, dz1, dark)
            box(dx0, f + 3, dz0, dx1, f + 7, dz1, red)
            box(dx0, f + 8, dz0, dx1, f + 8, dz1, trim)
        }
        for i in stride(from: -22, through: 22, by: 2) { at(i, f + 9, -18, red); at(i, f + 9, 18, red) }
        for i in stride(from: -18, through: 18, by: 2) { at(-22, f + 9, i, red); at(22, f + 9, i, red) }
        // Ember pods set in the inner faces; lanterns on the walk.
        for i in stride(from: -15, through: 15, by: 6) { at(i, f + 5, -17, pod); at(i, f + 5, 17, pod) }
        for i in stride(from: -12, through: 12, by: 6) { at(-21, f + 5, i, pod); at(21, f + 5, i, pod) }
        for i in stride(from: -16, through: 16, by: 8) { at(i, f + 10, -18, lantern); at(i, f + 10, 18, lantern) }

        // Corner towers: 7 square, a door from the courtyard, a ladder up the outer wall, a landing onto the walk, a roof
        // deck with crenels. The north-west one goes on up into a belfry and spire: the Searwings' roost.
        for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] {
            let tx = 21 * sx, tz = 17 * sz
            let bell = sx < 0 && sz < 0
            let roof = bell ? f + 19 : f + 13
            box(tx - 3, f + 1, tz - 3, tx + 3, roof, tz + 3, dark)
            box(tx - 2, f + 1, tz - 2, tx + 2, roof - 1, tz + 2, AIR)
            for y in stride(from: f + 3, through: roof - 1, by: 3) {                            // red bands round the shaft
                for dz in -3...3 { for dx in -3...3 where max(abs(dx), abs(dz)) == 3 { at(tx + dx, y, tz + dz, red) } }
            }
            box(tx - 2, f + 8, tz - 2, tx + 2, f + 8, tz + 2, trim)                              // the landing
            if bell { box(tx - 2, f + 13, tz - 2, tx + 2, f + 13, tz + 2, trim) }
            at(tx - 2 * sx, f + 1, tz - 3 * sz, AIR); at(tx - 2 * sx, f + 2, tz - 3 * sz, AIR)  // the door
            for z in [tz, tz + sz] { at(tx - 3 * sx, f + 9, z, AIR); at(tx - 3 * sx, f + 10, z, AIR) }  // onto the walks
            for x in [tx, tx + sx] { at(x, f + 9, tz - 3 * sz, AIR); at(x, f + 10, tz - 3 * sz, AIR) }
            let lz = tz + 2 * sz, face = ladder + (sz > 0 ? 0 : 1)                                // against the outer wall
            for y in (f + 1)...roof { at(tx, y, lz, face) }
            if !bell {
                for dz in -3...3 { for dx in -3...3 where max(abs(dx), abs(dz)) == 3 && (dx + dz) % 2 == 0 { at(tx + dx, f + 14, tz + dz, red) } }
                at(tx, f + 14, tz, lantern)
            } else {
                // The belfry: corner piers, the bell, a dark spire; Searwings come and go from it.
                for (dx, dz) in [(-3, -3), (3, -3), (-3, 3), (3, 3)] { box(tx + dx, f + 20, tz + dz, tx + dx, f + 22, tz + dz, dark) }
                at(tx, f + 20, tz, g("bell", gild))
                box(tx - 3, f + 23, tz - 3, tx + 3, f + 23, tz + 3, dark)
                box(tx - 2, f + 24, tz - 2, tx + 2, f + 24, tz + 2, red)
                box(tx - 1, f + 25, tz - 1, tx + 1, f + 25, tz + 1, red)
                at(tx, f + 26, tz, gild)
                at(tx, f + 22, tz, chain); at(tx, f + 21, tz, chain)
                w.spawner(ox + tx + 2, f + 20, oz + tz - 2, mob: "searwing")
            }
        }

        // The gatehouse: a dark block over the gate, a 3-wide passage, the portcullis raised, the walk carried through.
        box(-5, f + 1, 15, 5, f + 11, 20, dark)
        box(-5, f + 3, 20, 5, f + 9, 20, red)
        box(-1, f + 1, 15, 1, f + 4, 20, AIR)
        box(-1, f + 4, 19, 1, f + 4, 19, bars)
        box(-5, f + 9, 17, 5, f + 10, 17, AIR)
        for i in stride(from: -5, through: 5, by: 2) { at(i, f + 12, 20, red); at(i, f + 12, 15, red) }
        for i in [-5, 5] { at(i, f + 12, 17, red); at(i, f + 12, 18, red) }
        for dx in [-3, 3] { at(dx, f + 3, 20, pod) }
        at(0, f + 6, 20, gild)
        // The causeway: a dark deck on basalt piers, a low onyx parapet, braziers every fourth block.
        box(-2, f - 1, 21, 2, f, 31, dark)
        box(-2, f, 21, 2, f, 31, trim)
        for dz in 21...31 { at(-3, f + 1, dz, post); at(3, f + 1, dz, post) }
        for dz in [23, 27, 31] { brazier(-3, dz); brazier(3, dz); for dx in [-2, 2] { w.pillarDown(ox + dx, f - 2, oz + dz, basalt, minY: base + 1) } }
        for dx in [-3, 3] { box(dx, f - 1, 21, dx, f, 31, dark) }

        // The chapter hall (north): red brick on dark quoins, a flat roof with a parapet, pillars, a dais with the
        // commander's seat, the order's chests, lanterns on chains.
        box(-12, f + 1, -16, 12, f + 9, -6, red)
        box(-11, f + 1, -16, 11, f + 9, -7, AIR)
        for dx in [-12, 12] { box(dx, f + 1, -6, dx, f + 9, -6, dark) }
        box(-12, f + 10, -16, 12, f + 10, -6, dark)
        for dx in stride(from: -12, through: 12, by: 2) { at(dx, f + 11, -6, red) }
        box(-1, f + 1, -6, 1, f + 4, -6, AIR)
        at(-2, f + 5, -6, pod); at(2, f + 5, -6, pod)
        for dx in stride(from: -9, through: 9, by: 3) where dx != 0 { box(dx, f + 3, -6, dx, f + 6, -6, bars) }  // tall barred windows
        for (dx, dz) in [(-7, -9), (7, -9), (-7, -13), (7, -13)] { box(dx, f + 1, dz, dx, f + 9, dz, trim); at(dx, f + 9, dz, chisel) }
        box(-1, f, -12, 1, f, -7, planks)
        box(-5, f + 1, -16, 5, f + 1, -13, trim)
        box(-1, f + 2, -16, 1, f + 4, -16, gild)
        at(0, f + 2, -15, gild); at(-1, f + 2, -15, chisel); at(1, f + 2, -15, chisel)
        w.chest(ox - 4, f + 2, oz - 15, loot: "fortress", seed: rng.next(), facing: 1)
        w.chest(ox + 4, f + 2, oz - 15, loot: "fortress", seed: rng.next(), facing: 1)
        for (dx, dz) in [(-4, -10), (4, -10), (0, -14)] { at(dx, f + 9, dz, chain); at(dx, f + 8, dz, hanging) }

        // The forge (east): a dark hall open to the courtyard, a chimney, a lava trough, the smith's blocks, the caged
        // Slagthrower whose slag keeps the trough hot.
        box(13, f + 1, -4, 20, f + 7, 10, dark)
        box(14, f + 1, -3, 20, f + 7, 9, AIR)
        box(13, f + 8, -4, 20, f + 8, 10, trim)
        box(13, f + 1, 0, 13, f + 4, 5, AIR)
        for dz in [-4, 10] { box(13, f + 1, dz, 13, f + 7, dz, red) }
        box(19, f + 1, -3, 20, f + 14, -2, dark)
        box(19, f + 9, -3, 20, f + 14, -2, red)
        at(19, f + 15, -3, fire)
        box(18, f, 1, 19, f, 5, LAVA)
        for dz in 0...6 { at(17, f + 1, dz, trim); at(20, f + 1, dz, trim) }
        for dx in [18, 19] { at(dx, f + 1, 0, trim); at(dx, f + 1, 6, trim) }
        at(18, f + 1, -3, g("blast_furnace", g("furnace"))); at(17, f + 1, -3, g("blast_furnace", g("furnace")))
        at(15, f + 1, 1, g("anvil", trim)); at(15, f + 1, -1, g("smithing_table", trim))
        w.chest(ox + 20, f + 1, oz + 8, loot: "fortress", seed: rng.next(), facing: 2)
        for (dx, dz) in [(15, 6), (17, 6), (15, 7), (17, 7), (15, 8), (16, 8), (17, 8)] { box(dx, f + 1, dz, dx, f + 3, dz, bars) }
        box(15, f + 4, 6, 17, f + 4, 8, dark)
        w.spawner(ox + 16, f + 1, oz + 7, mob: "slagthrower")
        at(16, f + 7, 2, chain); at(16, f + 6, 2, hanging)

        // The barracks (west): bunks of hay two high along the back wall, lockers, barred windows.
        box(-20, f + 1, -4, -13, f + 6, 10, red)
        box(-20, f + 1, -3, -14, f + 6, 9, AIR)
        box(-20, f + 7, -4, -13, f + 7, 10, dark)
        for dz in [-4, 10] { box(-13, f + 1, dz, -13, f + 6, dz, dark) }
        box(-13, f + 1, 2, -13, f + 3, 3, AIR)
        for dz in [-1, 6] { box(-13, f + 3, dz, -13, f + 4, dz, bars) }
        for dz in [-3, -2, 0, 1, 4, 5, 7, 8] { at(-20, f + 1, dz, hay); at(-20, f + 3, dz, hay) }
        w.chest(ox - 15, f + 1, oz - 3, loot: "fortress", seed: rng.next(), facing: 3)
        at(-15, f + 1, 9, gild)
        at(-17, f + 6, 3, chain); at(-17, f + 5, 3, hanging)

        // The courtyard: the brazier well, Brimroot beds, the scorchling pit, lantern posts.
        for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 { at(dx, f + 1, dz + 2, chisel) } }
        at(0, f, 2, magma); at(0, f + 1, 2, fire)
        for bx in [-8, 6] {
            box(bx - 1, f + 1, 5, bx + 3, f + 1, 10, trim)
            box(bx, f, 6, bx + 2, f, 9, soul)
            box(bx, f + 1, 6, bx + 2, f + 1, 9, AIR)
            for dz in 6...9 { for dx in bx...(bx + 2) { at(dx, f + 1, dz, wart + BlockID(rng.int(4))) } }
        }
        box(6, f - 2, -4, 10, f, 0, AIR)
        box(6, f - 3, -4, 10, f - 3, 0, magma)
        for dz in -5...1 { for dx in 5...11 where dx == 5 || dx == 11 || dz == -5 || dz == 1 { at(dx, f + 1, dz, bars) } }
        w.spawner(ox + 8, f - 2, oz - 2, mob: "scorchling")
        for (dx, dz) in [(-10, 13), (10, 13), (-10, -3), (-4, 13), (4, 13)] { box(dx, f + 1, dz, dx, f + 3, dz, post); at(dx, f + 4, dz, lantern) }

        // The garrison: knights at the gate, squires about the courtyard and barracks, Slagthrowers on the walk, a
        // knight at the forge and a champion before the dais.
        mob("brand_knight", -2, f + 1, 14); mob("brand_knight", 2, f + 1, 14)
        mob("brand_squire", -5, f + 1, 3); mob("brand_squire", 5, f + 1, 12)
        mob("brand_squire", -17, f + 1, 1); mob("brand_squire", -16, f + 1, 6)
        mob("slagthrower", -12, f + 9, -17); mob("slagthrower", 12, f + 9, 17)
        mob("brand_knight", 15, f + 1, 4)
        mob("brand_champion", 0, f + 1, -10)
    }
}

enum SearwingRoost {
    static let name = "Searwing Roost"
    static let tall = 44

    static func start(ox: Int, oz: Int, y: Int, base: Int, seed: UInt64) -> StructureStart {
        let piece = Piece(min: IVec3(ox - 16, y - 12, oz - 16), max: IVec3(ox + 16, y + tall + 8, oz + 16)) { w in
            build(&w, ox: ox, oz: oz, y: y, base: base, seed: seed)
        }
        return StructureStart(kind: "bastion", pieces: [piece], anchor: IVec3(ox + 9, y + 1, oz - 2))
    }

    // The spire's radius at height h over the islet (rough, the same in every chunk).
    static func radius(_ h: Int, _ x: Int, _ z: Int) -> Float {
        let taper: Float = 7.2 - Float(h) * 0.12
        let wob: Float = (hashf(x / 2, h / 3, z / 2, 0x5E1) - 0.5) * 1.2
        return max(1.6, taper + wob)
    }

    static func build(_ w: inout StructWriter, ox: Int, oz: Int, y: Int, base: Int, seed: UInt64) {
        func g(_ k: String, _ alt: BlockID = STONE) -> BlockID { Blocks.has(k) ? Blocks.id(k) : alt }
        let onyx = g("blackstone"), basalt = g("basalt", onyx), dark = g("polished_blackstone_bricks", onyx)
        let trim = g("polished_blackstone", dark), gild = g("gilded_blackstone", onyx), soil = g("soul_soil", onyx)
        let stem = g("crimson_stem", onyx), frond = g("nether_wart_block", onyx), pod = g("shroomlight", LAMP), gold = g("gold_block")
        let tag = base == YOFF ? "" : "@deep"
        var rng = SRng(seed ^ 0x5EA2)
        func rock(_ x: Int, _ yy: Int, _ z: Int) -> BlockID {
            let h = hashf(x, yy, z, 0x2005)
            return h < 0.55 ? onyx : (h < 0.85 ? basalt : (h < 0.97 ? dark : gild))
        }
        func mob(_ k: String, _ x: Float, _ yy: Int, _ z: Float) { w.mob(k + tag, V3(Float(ox) + x, Float(yy), Float(oz) + z)) }
        // Clear round it, a rounded top; the islet: a rough disc of rock and ash soil on piers.
        for dz in -15...15 { for dx in -15...15 {
            let d: Float = sqrtf(Float(dx * dx + dz * dz))
            guard d <= 15 else { continue }
            let top = y + tall + 4 - Int(max(0, d - 8) * 0.8)
            w.fill(ox + dx, y + 1, oz + dz, ox + dx, top, oz + dz, AIR)
            let edge: Float = 11.5 + (hashf(dx / 2, 0, dz / 2, 0x15E) - 0.5) * 3
            guard d <= edge else { continue }
            w.fill(ox + dx, y - 2, oz + dz, ox + dx, y, oz + dz, rock(ox + dx, y, oz + dz))
            if d > 8 && hashf(ox + dx, y, oz + dz, 0x501) < 0.35 { w.set(ox + dx, y, oz + dz, soil) }
            if (dx * 7 + dz * 3) % 5 == 0 && d < edge - 1 { w.pillarDown(ox + dx, y - 3, oz + dz, basalt, minY: base + 1) }
        } }
        // The spire, with a stair winding up its outside (a step of three blocks' arc for every block of height).
        let turn: Float = 0.34
        for h in 0...tall {
            let yy = y + h
            for dz in -9...9 { for dx in -9...9 {
                let d: Float = sqrtf(Float(dx * dx + dz * dz))
                let r = radius(h, ox + dx, oz + dz)
                if d <= r { w.set(ox + dx, yy, oz + dz, rock(ox + dx, yy, oz + dz)) }
            } }
            guard h >= 1 && h < tall else { continue }
            let a0: Float = Float(h) * turn
            let r0 = max(1.6, 7.2 - Float(h) * 0.12) + 0.6
            for s in 0..<8 {
                let a: Float = a0 + turn * Float(s) / 7
                for k in 0..<3 {
                    let rr: Float = r0 + Float(k)
                    let sx = Int((cosf(a) * rr).rounded()), sz = Int((sinf(a) * rr).rounded())
                    w.set(ox + sx, yy, oz + sz, trim)
                    w.set(ox + sx, yy + 1, oz + sz, AIR); w.set(ox + sx, yy + 2, oz + sz, AIR)
                }
            }
        }
        // Nests on ledges up the stair: a bowl of charred stems lined with ash soil, fronds round the rim; a Searwing
        // perched on each; ember pods under the ledge.
        func nest(_ h: Int, _ a: Float, _ big: Bool) {
            let r0 = max(1.6, 7.2 - Float(h) * 0.12) + 3.5
            let cx = Int((cosf(a) * r0).rounded()), cz = Int((sinf(a) * r0).rounded())
            let yy = y + h
            let rad = big ? 3 : 2
            let band: Float = r0 - 0.4                                     // the stair runs through the nest's inner side
            for dz in -rad...rad { for dx in -rad...rad {
                let q = dx * dx + dz * dz
                guard q <= rad * rad + 1 else { continue }
                let ax = Float(cx + dx), az = Float(cz + dz)
                let rim = q >= rad * rad - 1 && sqrtf(ax * ax + az * az) > band
                w.set(ox + cx + dx, yy, oz + cz + dz, q >= rad * rad - 1 ? stem : soil)
                if rim { w.set(ox + cx + dx, yy + 1, oz + cz + dz, (dx + dz) % 2 == 0 ? frond : stem) }
                else { w.set(ox + cx + dx, yy + 1, oz + cz + dz, AIR); w.set(ox + cx + dx, yy + 2, oz + cz + dz, AIR) }
            } }
            w.set(ox + cx, yy - 1, oz + cz, pod)
            mob("searwing", Float(cx) + 0.5, yy + 2, Float(cz) + 0.5)
        }
        for (i, h) in [9, 19, 29, 37].enumerated() { nest(h, (Float(h) + 0.5) * turn, i == 1) }
        // The treasure nest on the summit: the stair's last steps lead onto it.
        let top = y + tall
        for dz in -3...3 { for dx in -3...3 {
            let q = dx * dx + dz * dz
            guard q <= 10 else { continue }
            w.set(ox + dx, top, oz + dz, q >= 6 ? stem : soil)
            w.set(ox + dx, top + 1, oz + dz, q >= 6 ? ((dx + dz) % 2 == 0 ? frond : stem) : AIR)
            w.set(ox + dx, top + 2, oz + dz, AIR); w.set(ox + dx, top + 3, oz + dz, AIR)
        } }
        let ta: Float = (Float(tall - 1) + 0.5) * turn
        let gx = Int((cosf(ta) * 3).rounded()), gz = Int((sinf(ta) * 3).rounded())
        w.set(ox + gx, top + 1, oz + gz, AIR)                                                  // the gap the stair comes in by
        w.chest(ox - 1, top + 1, oz - 1, loot: "bastion", seed: rng.next(), facing: 1)
        w.chest(ox + 1, top + 1, oz + 1, loot: "bastion", seed: rng.next(), facing: 0)
        w.set(ox + 1, top + 1, oz - 1, gold)
        if rng.chance(0.5) { w.set(ox - 1, top + 1, oz + 1, gold) }
        for (dx, dz) in [(-3, 0), (3, 0), (0, -3), (0, 3)] { w.set(ox + dx, top - 1, oz + dz, pod) }
        w.spawner(ox, top + 1, oz, mob: "searwing")
        mob("searwing", 0.5, top + 3, 2.5); mob("searwing", -1.5, top + 4, -2.5)
        // The den in the roots: a low cave into the spire's foot with a scorchling spawner.
        let da: Float = rng.float() * 2 * Float.pi
        for k in 3...8 {
            let rr: Float = 9.5 - Float(k)
            let dx = Int((cosf(da) * rr).rounded()), dz = Int((sinf(da) * rr).rounded())
            w.fill(ox + dx - 1, y + 1, oz + dz - 1, ox + dx + 1, y + 3, oz + dz + 1, AIR)
        }
        w.spawner(ox + Int((cosf(da) * 2).rounded()), y + 1, oz + Int((sinf(da) * 2).rounded()), mob: "scorchling")
        mob("scorchling", Float(Int((cosf(da) * 9).rounded())) + 0.5, y + 1, Float(Int((sinf(da) * 9).rounded())) + 0.5)
    }
}
