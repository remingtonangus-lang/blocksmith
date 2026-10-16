import Foundation
import simd

// The Capital's citadels (Future ideas #1; they replace the Steelhold fortresses, keeping the structure key
// "military_base", the soldier and turret mob keys and the steelhold_* loot tables so old worlds load). An original
// look: an opulent, authoritarian, sleek white garrison. 113 blocks across:
//   terraces    two garden steps round an octagonal plaza podium (hedges, flowers, birches), a grand stair and gate
//               pylons on the south side
//   plaza       a reflecting pool, birch rows, two barbettes carrying twin 42 cm turrets (HeavyTurret)
//   hall        an octagonal two-storey-high hall (foyer, barracks, armory, mess) with a roof garden; a vault under it
//   tower       a rounded 48-high tower of white piers and smoked glass, nine floors, a setback garden terrace at
//               the sixth with a landing pad cantilevered to the north, a crown with a beacon mast (a landmark)
//   side towers two rounded towers east and west, joined to the main tower by an enclosed glass skyway and an open
//               upper bridge to their roof gardens
// (Until task 23 a Capital frigate was stationed over every citadel; the frigate is now the Meridian Navy's.)

extension BlockRegistry {
    func registerCapitalArchitecture() {
        if !has("capital_stone") {
            var d = BlockDef("capital_stone", "Capital Stone")
            d.tex = ["capital_stone"]; d.hardness = 2.5; d.resistance = 9; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone
            add(d)
            family("capital_stone", "capital_stone", "Capital Stone", h: 2.5, tool: .pickaxe, req: true, snd: .stone, stairs: true, slab: true, fence: false, wall: false)
        }
        if !has("capital_stone_trim") {
            var d = BlockDef("capital_stone_trim", "Capital Grey Stone")
            d.tex = ["capital_stone_trim"]; d.hardness = 2.5; d.resistance = 9; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone
            add(d)
        }
        if !has("capital_window") {
            var d = BlockDef("capital_window", "Capital Window")
            d.tex = ["capital_window"]; d.opaque = false; d.layer = .cutout; d.cullSame = true
            d.hardness = 0.6; d.resistance = 2; d.sound = .glass
            add(d)
        }
    }
}

extension TextureGen {
    static func capitalArchitecturePainters(_ p: inout [String: Painter]) {
        // Honed white stone: very faint large-scale clouding and a hairline joint on two edges.
        p["capital_stone"] = { x, y in
            if y == 15 || x == 15 { return hex(0xD6D9DC) }
            return hex(0xF0F1F2, 0.975 + 0.02 * r(x / 5, y / 5, 2401) + 0.01 * r(x, y, 2402))
        }
        p["capital_stone_trim"] = { x, y in
            if y == 15 { return hex(0x9EA3A8) }
            if y == 0 { return hex(0xD0D4D8) }
            return hex(0xBEC3C8, 0.97 + 0.03 * r(x / 3, y, 2403))
        }
        // Tall window: pale sky-tinted glass with a slim white mullion on one side.
        p["capital_window"] = { x, y in
            if x == 0 { return hex(0xF4F6F8) }
            if x == 15 { return hex(0xC8CDD2) }
            if abs(x - y / 2 - 2) <= 0 { return hex(0xDDEBF5, 1, 0.45) }
            return V4(0.62, 0.74, 0.84, 0.32)
        }
    }
}

enum CapitalBase {
    static let A = 56                      // half-size of the whole site
    // Leaf and log states (tree clean-up round the site), built once.
    static let leafTable: [Bool] = (0..<Blocks.count).map { Blocks.key(Blocks.groupBase[$0]).hasSuffix("_leaves") }
    static let logTable: [Bool] = (0..<Blocks.count).map { i in
        let k = Blocks.key(Blocks.groupBase[i])
        return k.hasSuffix("_log") || k.hasSuffix("_wood") || k.hasSuffix("_stem")
    }
    @inline(__always) static func isLeaf(_ b: BlockID) -> Bool { Int(b) < leafTable.count && leafTable[Int(b)] }
    @inline(__always) static func isLog(_ b: BlockID) -> Bool { Int(b) < logTable.count && logTable[Int(b)] }
    static let podium = 44                 // plaza octagon half-size

    // Rounded square (superellipse, exponent 4): soft rounded corners.
    @inline(__always) static func rounded(_ dx: Int, _ dz: Int, _ a: Float) -> Bool {
        let u = Float(dx) / a, v = Float(dz) / a
        let u2 = u * u, v2 = v * v
        return u2 * u2 + v2 * v2 <= 1
    }
    // Octagon: a square with chamfered corners.
    @inline(__always) static func octagon(_ dx: Int, _ dz: Int, _ a: Int, _ c: Int) -> Bool {
        abs(dx) <= a && abs(dz) <= a && abs(dx) + abs(dz) <= 2 * a - c
    }

    // Soldier posts (kind, dx, dy above the plaza floor, dz). Mob keys unchanged (their looks are the soldiers').
    static func garrison() -> [(String, Int, Int, Int)] {
        var out: [(String, Int, Int, Int)] = []
        // Gate and plaza.
        out += [("soldier_recruit", -3, -3, 53), ("soldier_recruit", 3, -3, 53), ("soldier_trooper", 0, 1, 42), ("soldier_recruit", -16, 1, 36),
                ("soldier_recruit", 16, 1, 36), ("soldier_trooper", -36, 1, 20), ("soldier_trooper", 36, 1, 20), ("soldier_recruit", 0, 1, -36),
                ("soldier_marksman", -30, 1, 22), ("soldier_marksman", 30, 1, 22)]
        // Hall: foyer, barracks (west), armory (east), mess (north).
        out += [("soldier_trooper", 0, 1, 22), ("soldier_recruit", -4, 1, 20), ("soldier_recruit", -20, 1, -4), ("soldier_recruit", -18, 1, 8),
                ("soldier_trooper", 20, 1, -6), ("soldier_trooper", 18, 1, 8), ("soldier_recruit", 0, 1, -22), ("soldier_ironclad", 12, 1, 14)]
        // Roof garden, tower floors, skyways, setback terrace and pad, side towers.
        out += [("soldier_marksman", -14, 8, 14), ("soldier_marksman", 14, 8, -14), ("soldier_trooper", 0, 8, 16),
                ("soldier_trooper", 1, 14, -2), ("soldier_recruit", -3, 20, -3), ("soldier_ironclad", 2, 26, -3), ("soldier_marksman", 18, 26, 0),
                ("soldier_marksman", -18, 26, 0), ("soldier_trooper", -2, 32, 0), ("soldier_marksman", 0, 38, -17), ("soldier_trooper", 1, 39, 8),
                ("soldier_ironclad", 0, 50, 2), ("soldier_marksman", 36, 39, 0), ("soldier_marksman", -36, 39, 0),
                ("soldier_recruit", 36, 1, 2), ("soldier_recruit", -36, 1, -2)]
        // Vault under the hall.
        out += [("soldier_ironclad", 2, -4, 16)]
        return out
    }

    static func build(_ w: inout StructWriter, _ cx: Int, _ y0: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        func g(_ n: String, _ f: BlockID = STONE) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let white = g("capital_stone", g("white_concrete")), grey = g("capital_stone_trim", g("light_gray_concrete"))
        let plate = g("capital_plate", white), glass = g("capital_window", GLASS), smoked = g("capital_glass", GLASS)
        let L = g("light_panel"), C = g("command_console"), Cr = g("ammo_crate")
        let S = g("capital_stone_stairs", white), Sl = g("capital_stone_slab", white)
        let hedge = g("oak_leaves", LEAVES), bloom = g("flowering_azalea_leaves", hedge), grass = GRASS, moss = g("moss_block", GRASS)
        let birch = BIRCH_LOG, birchL = BIRCH_LEAVES, water = WATER, ladder = g("ladder"), bars = g("iron_bars"), wool = g("white_wool")
        let flowers: [BlockID] = ["white_tulip", "oxeye_daisy", "lily_of_the_valley", "azure_bluet", "allium"].filter { Blocks.has($0) }.map { Blocks.id($0) }
        let A = CapitalBase.A, PO = CapitalBase.podium
        let P1 = y0 + 4                       // plaza floor
        let P2 = P1 + 7                       // hall roof (roof garden floor, tower floor 0)
        let top = P2 + 48                     // tower roof
        func X(_ d: Int) -> Int { cx + d }
        func Z(_ d: Int) -> Int { cz + d }
        // Visit the columns of a box that fall in this chunk (dx, dz relative to the centre): the big shapes below
        // are tested cell by cell, so they only run over the 16 x 16 the writer can actually write.
        func columns(_ x0: Int, _ x1: Int, _ z0: Int, _ z1: Int, _ body: (Int, Int) -> Void) {
            let xa = max(cx + x0, w.bx), xb = min(cx + x1, w.bx + CS - 1)
            let za = max(cz + z0, w.bz), zb = min(cz + z1, w.bz + CS - 1)
            guard xa <= xb, za <= zb else { return }
            for z in za...zb { for x in xa...xb { body(x - cx, z - cz) } }
        }
        func put(_ dx: Int, _ y: Int, _ dz: Int, _ b: BlockID) { w.set(cx + dx, y, cz + dz, b) }
        func tree(_ dx: Int, _ y: Int, _ dz: Int, _ h: Int) {
            for k in 0..<h { put(dx, y + k, dz, birch) }
            for ly in (y + h - 2)...(y + h + 1) { for ox in -2...2 { for oz in -2...2 {
                let r = ox * ox + oz * oz + (ly - (y + h - 1)) * (ly - (y + h - 1))
                if r <= 5 && !(ox == 0 && oz == 0 && ly < y + h) { put(dx + ox, ly, dz + oz, birchL) }
            } } }
        }

        // MARK: Site, terraces, podium
        w.fill(X(-A), y0 + 1, Z(-A), X(A), top + 16, Z(A), AIR)
        // Leaves left hanging just outside the site by trees whose trunks stood inside it (the clear above took the
        // trunks: flat leaf plates in mid-air round the citadel, BUGS, seed 12345 citadel at -392 88). Within 8 blocks of
        // the site, a leaf with no log within 3 blocks across and 6 below goes; a search reaching into another chunk
        // (unreadable here) counts as held, so a living crown is never cut. The piece box reaches A + 8 for this.
        let ring = A + 8
        columns(-ring, ring, -ring, ring) { dx, dz in
            guard max(abs(dx), abs(dz)) > A else { return }
            let x = cx + dx, z = cz + dz
            for y in (y0 + 1)...(top + 16) {
                guard CapitalBase.isLeaf(w.get(x, y, z)) else { continue }
                var held = false
                search: for oy in -6...1 { for oz in -3...3 { for ox in -3...3 {
                    let q = (x + ox, y + oy, z + oz)
                    if !w.inside(q.0, q.1, q.2) || CapitalBase.isLog(w.get(q.0, q.1, q.2)) { held = true; break search }
                } } }
                if !held { w.set(x, y, z, AIR) }
            }
        }
        columns(-A, A, -A, A) { dx, dz in
            let x = cx + dx, z = cz + dz
            w.pillarDown(x, y0, z, DIRT, minY: y0 - 48)
            if CapitalBase.octagon(dx, dz, PO, 14) {
                for y in (y0 - 6)...P1 { w.set(x, y, z, white) }
                w.set(x, P1, z, (abs(dx) + abs(dz)) % 8 == 0 || dx == 0 || dz == 0 ? grey : white)   // paving lines
            } else if CapitalBase.octagon(dx, dz, PO + 4, 16) {
                // First garden step: planter with a hedge along the plaza's edge.
                for y in (y0 - 2)...(P1 - 2) { w.set(x, y, z, white) }
                w.set(x, P1 - 2, z, CapitalBase.octagon(dx, dz, PO + 3, 16) ? grass : grey)     // planter with a grey kerb
            } else if CapitalBase.octagon(dx, dz, PO + 8, 18) {
                for y in (y0 - 2)...y0 { w.set(x, y, z, white) }
                w.set(x, y0, z, grass)
            } else {
                w.set(x, y0, z, grass)
            }
        }
        // Hedges and flowers on the garden steps (the plaza rim and the lower ring).
        columns(-A, A, -A, A) { dx, dz in
            let inner = CapitalBase.octagon(dx, dz, PO + 1, 14) && !CapitalBase.octagon(dx, dz, PO, 14)
            let outer = CapitalBase.octagon(dx, dz, PO + 5, 16) && !CapitalBase.octagon(dx, dz, PO + 4, 16)
            if abs(dx) <= 5 && dz > 0 { return }                                   // the grand stair
            if inner { put(dx, P1 - 1, dz, (dx + dz) % 7 == 0 ? bloom : hedge) }
            if outer { put(dx, y0 + 1, dz, hedge) }
            let ring2 = CapitalBase.octagon(dx, dz, PO + 7, 18) && !CapitalBase.octagon(dx, dz, PO + 6, 18)
            if ring2 && !flowers.isEmpty && hashf(dx, dz, 3, 0xCA91) < 0.35 { put(dx, y0 + 1, dz, flowers[Int(hashf(dx, dz, 4, 0xCA92) * Float(flowers.count)) % flowers.count]) }
            let ring1 = CapitalBase.octagon(dx, dz, PO + 3, 16) && !CapitalBase.octagon(dx, dz, PO + 2, 16)
            if ring1 && !flowers.isEmpty && hashf(dx, dz, 5, 0xCA93) < 0.3 { put(dx, P1 - 1, dz, flowers[Int(hashf(dx, dz, 6, 0xCA94) * Float(flowers.count)) % flowers.count]) }
        }
        // Birches on the lower terrace ring.
        for k in 0..<16 {
            let a = Float(k) / 16 * 2 * .pi + 0.2
            let dx = Int((Float(PO + 6) * cosf(a)).rounded()), dz = Int((Float(PO + 6) * sinf(a)).rounded())
            if abs(dx) <= 8 && dz > 0 { continue }
            tree(dx, y0 + 1, dz, 5)
        }
        // Grand stair (south), gate pylons, the approach path.
        for dz in (PO + 1)...A { w.fill(X(-5), y0, Z(dz), X(5), y0, Z(dz), grey) }
        for i in 0..<4 {
            let dz = PO + 4 - i
            w.fill(X(-5), y0 - 2, Z(dz), X(5), y0 + i, Z(dz), white)
            w.fill(X(-5), y0 + 1 + i, Z(dz), X(5), y0 + 1 + i, Z(dz), S)            // ascending north
        }
        for sx in [-1, 1] {
            let px = sx * 7
            w.fill(X(px - 1), y0 + 1, Z(PO + 6), X(px + 1), y0 + 12, Z(PO + 8), white)
            w.fill(X(px - 1), y0 + 13, Z(PO + 6), X(px + 1), y0 + 13, Z(PO + 8), grey)
            w.fill(X(px), y0 + 4, Z(PO + 9), X(px), y0 + 10, Z(PO + 9), L)
            put(px, y0 + 14, PO + 7, L)
        }

        // MARK: Plaza: reflecting pool, birch rows, barbettes
        w.fill(X(-11), P1, Z(31), X(11), P1, Z(41), grey)
        w.fill(X(-10), P1, Z(32), X(10), P1, Z(40), water)
        w.fill(X(-10), P1 - 1, Z(32), X(10), P1 - 1, Z(40), grey)
        // Low hedges flank the pool's ends (the walks round its sides to the hall door stay open).
        for dz in [30, 42] { for dx in -10...10 where abs(dx) >= 6 { put(dx, P1 + 1, dz, hedge) } }
        for dz in stride(from: 31, through: 41, by: 5) { for sx in [-1, 1] { tree(sx * 15, P1 + 1, dz, 5) } }
        for sx in [-1, 1] {
            // Barbette: a grey ring with a white band, the turret sits on its top (y P1 + 5).
            let bx = sx * 30, bz = 32
            columns(bx - 8, bx + 8, bz - 8, bz + 8) { dx, dz in
                let r2 = (dx - bx) * (dx - bx) + (dz - bz) * (dz - bz)
                if r2 <= 56 { for y in (P1 + 1)...(P1 + 4) { put(dx, y, dz, y == P1 + 3 ? white : grey) } }
                if r2 <= 64 && r2 > 56 { put(dx, P1 + 1, dz, grey) }
            }
            // Steps up to the barbette top on its inner side.
            for i in 0..<4 { put(bx - sx * (8 + 3 - i), P1 + 1 + i, bz, grey); put(bx - sx * (8 + 3 - i), P1 + 1 + i, bz + 1, grey) }
            w.mob("deck_gun", V3(Float(X(bx)) + 0.5, Float(P1 + 5), Float(Z(bz)) + 0.5))
        }

        // MARK: Hall
        let HA = 28, HC = 10
        columns(-HA, HA, -HA, HA) { dx, dz in
            guard CapitalBase.octagon(dx, dz, HA, HC) else { return }
            let x = cx + dx, z = cz + dz
            let wall = !CapitalBase.octagon(dx, dz, HA - 1, HC)
            for y in (P1 + 1)..<P2 {
                if wall {
                    // White piers every 3 with tall glass between them; a grey band at the top.
                    let pier = (abs(dx) + abs(dz)) % 3 == 0 || abs(abs(dx) - abs(dz)) <= 0
                    w.set(x, y, z, y == P2 - 1 ? grey : (pier || y == P1 + 1 ? white : glass))
                } else { w.set(x, y, z, AIR) }
            }
            w.set(x, P2, z, wall ? grey : white)
            if !wall && (dx % 6 == 0 && dz % 6 == 0) { w.set(x, P2 - 1, z, L) }
        }
        // Doorways: south (foyer), east and west, north.
        w.fill(X(-2), P1 + 1, Z(HA - 1), X(2), P1 + 4, Z(HA), AIR)
        w.fill(X(-HA), P1 + 1, Z(-1), X(-HA + 1), P1 + 3, Z(1), AIR); w.fill(X(HA - 1), P1 + 1, Z(-1), X(HA), P1 + 3, Z(1), AIR)
        w.fill(X(-1), P1 + 1, Z(-HA), X(1), P1 + 3, Z(-HA + 1), AIR)
        // A solid white transom over each doorway up to the grey band (the cut left pier stubs hanging over the door
        // under a strip of glass: blind critic, citadel_plaza).
        w.fill(X(-3), P1 + 5, Z(HA - 1), X(3), P2 - 2, Z(HA), white)
        w.fill(X(-HA), P1 + 4, Z(-2), X(-HA + 1), P2 - 2, Z(2), white); w.fill(X(HA - 1), P1 + 4, Z(-2), X(HA), P2 - 2, Z(2), white)
        w.fill(X(-2), P1 + 4, Z(-HA), X(2), P2 - 2, Z(-HA + 1), white)
        // Foyer: reception consoles, planters.
        for dx in -3...3 where abs(dx) > 1 { put(dx, P1 + 1, 17, C) }
        for sx in [-1, 1] { put(sx * 6, P1 + 1, 24, grass); put(sx * 6, P1 + 2, 24, hedge); put(sx * 9, P1 + 1, 24, grass); put(sx * 9, P1 + 2, 24, bloom) }
        // West barracks: bunks in rows, lockers.
        for dz in stride(from: -12, through: 10, by: 4) { for dx in stride(from: -24, through: -14, by: 5) where CapitalBase.octagon(dx - 2, dz, HA - 2, HC) {
            w.fill(X(dx), P1 + 1, Z(dz), X(dx + 1), P1 + 1, Z(dz), wool)
            w.fill(X(dx), P1 + 3, Z(dz), X(dx + 1), P1 + 3, Z(dz), wool)
            put(dx + 2, P1 + 1, dz, grey); put(dx + 2, P1 + 2, dz, grey); put(dx + 2, P1 + 3, dz, grey)
        } }
        w.chest(X(-12), P1 + 1, Z(-14), loot: "steelhold_supply", seed: rng.next(), facing: 1)
        // East armory: crate stacks, weapon chests, guns on the wall.
        for dz in stride(from: -12, through: 8, by: 5) { w.fill(X(22), P1 + 1, Z(dz), X(23), P1 + 2, Z(dz + 1), Cr) }
        for (i, dz) in [-10, -2, 6].enumerated() { w.chest(X(16), P1 + 1, Z(dz), loot: "steelhold_armory", seed: rng.next(), facing: i % 2 == 0 ? 2 : 3) }
        for dz in stride(from: -8, through: 8, by: 2) where rng.chance(0.7) {
            let rack: [Int] = [Guns.rifle, Guns.rifle, Guns.smg, Guns.smg, Guns.shotgun, Guns.sniper]
            let gun = Guns.all[rack[rng.int(6)]]
            if Items.has(gun.key) { w.frame(X(27), P1 + 3, Z(dz), state: 2, item: ItemStack(Items.id(gun.key), 1)) }
        }
        // North mess: long tables with benches.
        for dx in stride(from: -12, through: 12, by: 6) where abs(dx) > 2 {
            w.fill(X(dx), P1 + 1, Z(-24), X(dx), P1 + 1, Z(-14), g("capital_stone_slab[top]", Sl))
            w.fill(X(dx - 1), P1 + 1, Z(-24), X(dx - 1), P1 + 1, Z(-14), Sl)
            w.fill(X(dx + 1), P1 + 1, Z(-24), X(dx + 1), P1 + 1, Z(-14), Sl)
        }
        w.chest(X(-8), P1 + 1, Z(-25), loot: "steelhold_supply", seed: rng.next(), facing: 1)
        // Vault under the hall, by a ladder from the foyer.
        w.fill(X(-6), P1 - 5, Z(10), X(6), P1 - 1, Z(20), white)
        w.fill(X(-5), P1 - 4, Z(11), X(5), P1 - 2, Z(19), AIR)
        for y in (P1 - 4)...P1 { put(0, y, 20, ladder) }
        put(0, P1 + 1, 20, AIR)
        for (dx, dz) in [(-4, 12), (4, 12)] { w.chest(X(dx), P1 - 4, Z(dz), loot: "steelhold_vault", seed: rng.next(), facing: 1) }
        w.chest(X(-4), P1 - 4, Z(18), loot: "steelhold_command", seed: rng.next(), facing: 0)
        w.fill(X(-5), P1 - 2, Z(15), X(5), P1 - 2, Z(15), L)

        // MARK: Roof garden on the hall
        columns(-HA, HA, -HA, HA) { dx, dz in
            guard CapitalBase.octagon(dx, dz, HA, HC) else { return }
            if !CapitalBase.octagon(dx, dz, HA - 1, HC) { put(dx, P2 + 1, dz, grey); return }     // parapet
            let r2 = dx * dx + dz * dz
            // Two rings of planters round the tower with a walk between, lawns in the corners.
            if (r2 >= 144 && r2 <= 196) || (r2 >= 400 && r2 <= 484 && abs(dx) > 3 && abs(dz) > 3) {
                put(dx, P2 + 1, dz, grass)
                let edge = r2 <= 150 || r2 >= 478 || (r2 >= 190 && r2 <= 196) || (r2 >= 400 && r2 <= 406)
                if edge { put(dx, P2 + 2, dz, (dx * 3 + dz) % 11 == 0 ? bloom : hedge) }
            } else if r2 > 500 { put(dx, P2 + 1, dz, moss) }
        }
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi + 0.39
            tree(Int((17 * cosf(a)).rounded()), P2 + 1, Int((17 * sinf(a)).rounded()), 4)
        }

        // MARK: Towers
        // One tower: rounded plan of half-size `a` (smaller above `setY`), floors every 6 from `y0t`, white piers and
        // smoked-glass bays, a ladder shaft on the north side of the core.
        func tower(_ tx: Int, _ tz: Int, _ a: Float, _ a2: Float, _ y0t: Int, _ setY: Int, _ yTop: Int) {
            let R = Int(a) + 1
            columns(tx - R, tx + R, tz - R, tz + R) { dx, dz in
                let lx = dx - tx, lz = dz - tz
                for y in y0t...yTop {
                    let ar = y > setY ? a2 : a
                    guard CapitalBase.rounded(lx, lz, ar) else { continue }
                    let shell = !CapitalBase.rounded(lx + 1, lz, ar) || !CapitalBase.rounded(lx - 1, lz, ar)
                        || !CapitalBase.rounded(lx, lz + 1, ar) || !CapitalBase.rounded(lx, lz - 1, ar)
                    if y == y0t && !shell { continue }                  // the storey below stands on the plaza / hall floor
                    let floorLevel = (y - y0t) % 6 == 0
                    var b: BlockID = AIR
                    if floorLevel { b = shell ? grey : white }
                    else if shell { b = (lx + lz) % 3 == 0 || lx == 0 || lz == 0 ? white : smoked }
                    if y == yTop { b = shell ? grey : white }
                    put(dx, y, dz, b)
                }
            }
            // Ladder shaft and its openings through every floor; ceiling lights.
            for y in y0t...(yTop - 1) { put(tx, y, tz - Int(a2) + 2, ladder + 1); put(tx, y, tz - Int(a2) + 1, white) }
            var y = y0t + 6
            while y < yTop { put(tx + 2, y - 1, tz + 2, L); put(tx - 2, y - 1, tz - 2, L); y += 6 }
        }
        // Floors every 6 from P1 + 1 put floor 0 at the hall roof (P2) and the skyway floor at P2 + 18.
        tower(0, 0, 9.5, 7.5, P1 + 1, P2 + 30, top)
        for sx in [-1, 1] { tower(sx * 36, 0, 6.5, 6.5, P1 + 1, P1 + 37, P1 + 37) }
        // Lobby in the hall: the tower's ground storey opens to the foyer, the east and the west.
        w.fill(X(-2), P1 + 1, Z(8), X(2), P1 + 4, Z(10), AIR)
        w.fill(X(-10), P1 + 1, Z(-1), X(-8), P1 + 3, Z(1), AIR); w.fill(X(8), P1 + 1, Z(-1), X(10), P1 + 3, Z(1), AIR)
        // Door onto the roof garden (south) at floor 0.
        w.fill(X(-1), P2 + 1, Z(8), X(1), P2 + 3, Z(10), AIR)
        // Side towers' doors at the plaza (toward the centre) and their roof gardens.
        for sx in [-1, 1] {
            w.fill(X(min(sx * 29, sx * 31)), P1 + 1, Z(-1), X(max(sx * 29, sx * 31)), P1 + 3, Z(1), AIR)
            columns(sx * 36 - 6, sx * 36 + 6, -6, 6) { dx, dz in
                let lx = dx - sx * 36
                guard CapitalBase.rounded(lx, dz, 6.5) else { return }
                let rim = !CapitalBase.rounded(lx, dz, 5.5)
                if rim { put(dx, P1 + 38, dz, grey) } else if lx * lx + dz * dz >= 9 { put(dx, P1 + 38, dz, grass) }
            }
            tree(sx * 36 + 2, P1 + 39, 2, 3)
            // The ladder carries on through the roof onto the garden.
            put(sx * 36, P1 + 37, -4, ladder + 1); put(sx * 36, P1 + 38, -4, ladder + 1); put(sx * 36, P1 + 38, -5, white)
            put(sx * 36, P1 + 39, -4, AIR)
            for k in 0..<4 { put(sx * 36 - 3 + k, P1 + 39, -3, hedge) }
            // A smaller landing pad cantilevered off the side tower's outer face at its top floor, with braces.
            let py = P1 + 31
            columns(min(sx * 41, sx * 53), max(sx * 41, sx * 53), -6, 6) { dx, dz in
                let lx = dx - sx * 47
                let r2 = lx * lx + dz * dz
                guard r2 <= 25 || (sx * (dx - sx * 36) >= 5 && sx * (dx - sx * 36) <= 7 && abs(dz) <= 1) else { return }
                put(dx, py, dz, r2 >= 16 && r2 <= 25 ? grey : white)
                if r2 >= 16 && r2 <= 25 && (dx + dz) % 3 == 0 { put(dx, py + 1, dz, L) }
            }
            w.fill(X(min(sx * 42, sx * 43)), py + 1, Z(-1), X(max(sx * 42, sx * 43)), py + 3, Z(1), AIR)
            for k in 1...5 { put(sx * (48 - k), py - k, 0, grey) }          // brace from the pad's underside to the wall
            // Chests on the side towers' upper floor.
            w.chest(X(sx * 36 + 3), P1 + 32, Z(3), loot: "steelhold_armory", seed: rng.next(), facing: 0)
        }

        // MARK: Skyways
        // Enclosed glass skyway at the main tower's floor 3 (P2 + 18) to each side tower (its floor P1 + 25),
        // and an open bridge from the setback terrace (P2 + 30) to the side towers' roof gardens (P1 + 37).
        for sx in [-1, 1] {
            let xa = min(sx * 10, sx * 29), xb = max(sx * 10, sx * 29)
            let fy = P2 + 18
            w.fill(X(xa), fy, Z(-2), X(xb), fy, Z(2), grey)
            w.fill(X(xa), fy + 1, Z(-2), X(xb), fy + 3, Z(-2), glass); w.fill(X(xa), fy + 1, Z(2), X(xb), fy + 3, Z(2), glass)
            w.fill(X(xa), fy + 4, Z(-2), X(xb), fy + 4, Z(2), white)
            w.fill(X(xa), fy + 1, Z(-1), X(xb), fy + 3, Z(1), AIR)
            for x in stride(from: xa, through: xb, by: 4) { w.fill(X(x), fy + 1, Z(-2), X(x), fy + 3, Z(-2), white); w.fill(X(x), fy + 1, Z(2), X(x), fy + 3, Z(2), white) }
            for x in stride(from: xa + 2, through: xb, by: 4) { put(x, fy + 3, 0, L) }
            // Planters hung along the skyway's flanks.
            w.fill(X(xa + 1), fy, Z(-3), X(xb - 1), fy, Z(-3), grey); w.fill(X(xa + 1), fy, Z(3), X(xb - 1), fy, Z(3), grey)
            w.fill(X(xa + 1), fy + 1, Z(-3), X(xb - 1), fy + 1, Z(-3), hedge); w.fill(X(xa + 1), fy + 1, Z(3), X(xb - 1), fy + 1, Z(3), hedge)
            // Openings in the towers where it meets them.
            w.fill(X(min(sx * 7, sx * 10)), fy + 1, Z(-1), X(max(sx * 7, sx * 10)), fy + 3, Z(1), AIR)
            w.fill(X(min(sx * 28, sx * 31)), fy + 1, Z(-1), X(max(sx * 28, sx * 31)), fy + 3, Z(1), AIR)
            // Upper open bridge with glass parapets.
            let uy = P2 + 30
            let ua = min(sx * 10, sx * 29), ub = max(sx * 10, sx * 29)
            w.fill(X(ua), uy, Z(-1), X(ub), uy, Z(1), white)
            w.fill(X(ua), uy + 1, Z(-2), X(ub), uy + 1, Z(-2), glass); w.fill(X(ua), uy + 1, Z(2), X(ub), uy + 1, Z(2), glass)
            w.fill(X(ua), uy - 1, Z(0), X(ub), uy - 1, Z(0), grey)
            w.fill(X(min(sx * 7, sx * 10)), uy + 1, Z(-1), X(max(sx * 7, sx * 10)), uy + 3, Z(1), AIR)
            w.fill(X(min(sx * 29, sx * 31)), uy + 1, Z(-1), X(max(sx * 29, sx * 31)), uy + 2, Z(1), AIR)
        }

        // MARK: Setback terrace garden, landing pad, crown
        let ST = P2 + 30
        columns(-10, 10, -10, 10) { dx, dz in
            guard CapitalBase.rounded(dx, dz, 9.5), !CapitalBase.rounded(dx, dz, 7.5) else { return }
            // A planter round the edge (the parapet), a walk inside it on the floor.
            guard !CapitalBase.rounded(dx, dz, 8.7) else { return }
            put(dx, ST + 1, dz, grass)
            put(dx, ST + 2, dz, (dx * dz) % 5 == 0 ? bloom : hedge)
        }
        // Doors from floor 5 onto the terrace on all four sides (the north one leads onto the landing pad).
        for (ox, oz) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
            // East, west and north run through the parapet planter onto the bridges and the pad; south stays closed.
            let reach = oz == 1 ? 8 : 10
            let x0 = ox == 0 ? -1 : ox * 6, x1 = ox == 0 ? 1 : ox * reach
            let z0 = oz == 0 ? -1 : oz * 6, z1 = oz == 0 ? 1 : oz * reach
            w.fill(X(min(x0, x1)), ST + 1, Z(min(z0, z1)), X(max(x0, x1)), ST + 3, Z(max(z0, z1)), AIR)
        }
        // Landing pad: a disc cantilevered north off the terrace, a ring and a chevron marking, edge lights, braces.
        let padZ = -21, padR = 10
        columns(-padR - 1, padR + 1, padZ - padR - 1, padZ + padR + 1) { dx, dz in
            let r2 = dx * dx + (dz - padZ) * (dz - padZ)
            guard r2 <= padR * padR else { return }
            var b: BlockID = white
            if r2 >= (padR - 1) * (padR - 1) { b = grey }
            if r2 >= 30 && r2 <= 42 { b = grey }
            let cz2 = dz - padZ
            if abs(dx) <= 3 && (cz2 == -abs(dx) || cz2 == -abs(dx) + 1) { b = grey }
            put(dx, ST, dz, b)
            if r2 >= (padR - 1) * (padR - 1) && (dx + dz) % 4 == 0 { put(dx, ST + 1, dz, L) }
        }
        w.fill(X(-1), ST, Z(-11), X(1), ST, Z(-8), grey)
        for k in 1...7 { for sx in [-1, 1] { put(sx * 4, ST - k, -9 - k, grey) } }
        // Crown: a chamfered cap, a beacon mast with lights (seen from far off).
        columns(-8, 8, -8, 8) { dx, dz in
            if CapitalBase.rounded(dx, dz, 6.5) { put(dx, top + 1, dz, grey) }
            if CapitalBase.rounded(dx, dz, 4.5) { put(dx, top + 2, dz, white) }
            if CapitalBase.rounded(dx, dz, 2.5) { put(dx, top + 3, dz, white) }
        }
        for y in (top + 4)...(top + 12) { put(0, y, 0, y % 3 == 0 ? L : grey) }
        put(0, top + 13, 0, L)
        // Command floor (floor 8): consoles, command chests, a map table.
        let cmd = P2 + 42
        for k in -4...4 where abs(k) > 1 { put(k, cmd + 1, 5, C); put(k, cmd + 1, -5, C) }
        w.fill(X(-1), cmd + 1, Z(-1), X(1), cmd + 1, Z(1), C)
        w.chest(X(-5), cmd + 1, Z(2), loot: "steelhold_command", seed: rng.next(), facing: 3)
        w.chest(X(5), cmd + 1, Z(-2), loot: "steelhold_command", seed: rng.next(), facing: 2)
        // Quarters and a lounge on the floors between: beds of white wool, planters, bars at the shaft.
        for f in 1...4 {
            let fy = P2 + 6 * f
            if f == 3 { continue }                                   // the skyway floor stays a concourse
            w.fill(X(3), fy + 1, Z(3), X(4), fy + 1, Z(3), wool); w.fill(X(-4), fy + 1, Z(3), X(-3), fy + 1, Z(3), wool)
            put(5, fy + 1, -2, grass); put(5, fy + 2, -2, hedge)
        }
        _ = bars; _ = plate

        // MARK: Garrison
        for (k, dx, dy, dz) in CapitalBase.garrison() {
            w.mob(k, V3(Float(X(dx)) + 0.5, Float(P1 + dy), Float(Z(dz)) + 0.5))
        }
    }
}
