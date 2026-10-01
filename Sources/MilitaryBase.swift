import Foundation
import simd

// Steelhold fortresses: very rare square steel bases (one per 64x64-chunk region at most) on fairly level land
// (plains, savanna, desert, snowy plains, badlands, meadows, forests, taiga). 63 blocks across with four corner towers, three levels and a roof:
//   basement   supply depot, generator and a barred vault
//   ground     entrance hall, barracks, armory, mess hall, workshop around two crossing corridors
//   upper      the command room in the middle, officers' quarters, comms, medbay and a second barracks
//   roof       parapets, marksman posts, and a deck gun on top of every corner tower
// Garrisoned by about two dozen Steelhold soldiers of all four ranks (Soldiers.swift).
extension BlockRegistry {
    func registerMilitaryBlocks() {
        func steel(_ n: String, _ disp: String, side: String? = nil, top: String? = nil, h: Float = 12, emit: UInt8 = 0) {
            guard !has(n) else { return }
            var d = BlockDef(n, disp)
            let s = side ?? n
            d.tex = [s, s, top ?? s, top ?? s, s, s]
            d.hardness = h; d.resistance = 600; d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 2
            d.sound = .stone; d.emit = emit
            add(d)
        }
        steel("steel_plating", "Steel Plating")
        steel("steel_grating", "Steel Floor Plate")
        steel("hazard_plating", "Hazard Plating")
        steel("light_panel", "Light Panel", h: 3, emit: 15)
        steel("command_console", "Command Console", side: "command_console_side", top: "command_console_top", h: 6, emit: 7)
        steel("ammo_crate", "Ammo Crate", side: "ammo_crate_side", top: "ammo_crate_top", h: 4)
        if !has("armored_glass") {
            var d = BlockDef("armored_glass", "Armored Glass")
            d.tex = ["armored_glass"]; d.opaque = false; d.layer = .cutout; d.cullSame = true
            d.hardness = 10; d.resistance = 600; d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 2; d.sound = .glass
            add(d)
        }
        family("steel_plating", "steel_plating", "Steel Plating", h: 12, tool: .pickaxe, req: true, snd: .stone, stairs: true, slab: true, fence: false, wall: false)
    }
}

extension TextureGen {
    static func militaryPainters(_ p: inout [String: Painter]) {
        p["steel_plating"] = { x, y in
            if x == 0 || y == 0 { return hex(0x6E747C) }
            if x == 15 || y == 15 { return hex(0x34383D) }
            let rivet = (x == 2 || x == 13) && (y == 2 || y == 13)
            if rivet { return hex(0x8A9098) }
            if (x == 3 || x == 14) && (y == 3 || y == 14) { return hex(0x3A3E44) }
            return hex(0x585E66, 0.93 + 0.05 * r(0, y, 1901) + 0.04 * r(x, y, 1902))
        }
        p["steel_grating"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x3A3E43) }
            // Raised diamond tread.
            let u = (x + y) % 6, v = (x - y + 32) % 6
            let tread = (u == 0 && x % 2 == 0) || (v == 0 && x % 2 == 1)
            return hex(tread ? 0x7A8088 : 0x4D5359, 0.95 + 0.06 * r(x, y, 1903))
        }
        p["hazard_plating"] = { x, y in
            if y == 0 || y == 15 { return hex(0x34383D) }
            let stripe = ((x + y) / 4) % 2 == 0
            return hex(stripe ? 0xE0B020 : 0x26272A, 0.92 + 0.08 * r(x, y, 1904))
        }
        p["light_panel"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x3A3E43) }
            if x == 1 || y == 1 || x == 14 || y == 14 { return hex(0x9AA4AE) }
            return hex(y % 4 == 0 ? 0xD8EEFF : 0xF2FAFF)
        }
        p["command_console_side"] = { x, y in
            if x == 0 || x == 15 || y == 15 { return hex(0x2C3035) }
            if y >= 2 && y <= 8 && x >= 2 && x <= 13 {
                // Screen: a map grid with a few blips.
                if x == 2 || x == 13 || y == 2 || y == 8 { return hex(0x101418) }
                if (x + 1) % 4 == 0 || y == 5 { return hex(0x1E6B4A) }
                if r(x, y, 1905) > 0.9 { return hex(0x7CFFB0) }
                return hex(0x0F3A2A, 0.9 + 0.1 * r(x, y, 1906))
            }
            if y >= 10 && y <= 12 && x % 3 == 1 { let lamps: [UInt32] = [0xD03A2A, 0xE0B020, 0x3AA0E0, 0x40C060]; return hex(lamps[(x / 3) % 4]) }
            return hex(0x454A51, 0.95 + 0.05 * r(x, y, 1907))
        }
        p["command_console_top"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x2C3035) }
            if y >= 9 && x >= 2 && x <= 13 && y <= 13 { return hex((x + y) % 2 == 0 ? 0x22262B : 0x5A6068) }
            if y >= 2 && y <= 6 && x >= 3 && x <= 12 { return hex(0x1A4A6A, 0.85 + 0.25 * r(x, y, 1908)) }
            return hex(0x454A51)
        }
        p["ammo_crate_side"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 || x == 7 || x == 8 { return hex(0x3B4526) }
            if y == 6 || y == 9 { return hex(0xC8A830) }
            return hex(0x55643A, 0.9 + 0.1 * r(x / 2, y, 1909))
        }
        p["ammo_crate_top"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x3B4526) }
            if (x == 4 || x == 11) && y > 3 && y < 12 { return hex(0x2C3420) }
            return hex(0x5A6A3C, 0.9 + 0.1 * r(x, y / 2, 1910))
        }
        p["armored_glass"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x50565E) }
            if x == y || x == 15 - y { return hex(0x8A96A4, 1, 0.55) }
            return r(x, y, 1911) > 0.97 ? hex(0xFFFFFF, 1, 0.5) : V4(0.7, 0.8, 0.9, 0.0)
        }
    }
}

extension StructWriter {
    // An item frame (state = wall side, see Decor.swift) holding an item.
    mutating func frame(_ x: Int, _ y: Int, _ z: Int, state: Int, item: ItemStack) {
        guard inside(x, y, z), Blocks.has("item_frame") else { return }
        set(x, y, z, Blocks.id("item_frame") + BlockID(state))
        let be = BlockEntity(.frame)
        be.container[0] = item
        entities.append((IVec3(x, y, z), be))
    }
}

enum MilitaryBase {
    static let R = 31                 // outer wall half-size
    static let biomes: Set<Biome> = [.plains, .sunflowerPlains, .savanna, .savannaPlateau, .desert, .snowyPlains, .badlands, .meadow,
                                     .forest, .birchForest, .taiga, .snowyTaiga]

    static func g(_ n: String) -> BlockID { Blocks.has(n) ? Blocks.id(n) : STONE }

    static func type(_ gen: WorldGen) -> StructureType {
        StructureType(name: "military_base", spacing: 64, separation: 20, salt: 70411993, reach: 3) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            guard MilitaryBase.biomes.contains(gen.column(x, z).biome) else { return nil }
            // Open, fairly flat ground over the whole footprint.
            let y = gen.groundY(x, z)
            guard y > SEA + 1 else { return nil }
            let R = MilitaryBase.R
            for (dx, dz) in [(-R, -R), (R, -R), (-R, R), (R, R), (0, -R), (0, R), (-R, 0), (R, 0)] {
                let gy = gen.groundY(x + dx, z + dz)
                if abs(gy - y) > 12 || gy <= SEA { return nil }
                if gen.column(x + dx, z + dz).biome.isOcean { return nil }
            }
            let y0 = y + 1
            let e = R + 10
            let piece = Piece(min: IVec3(x - e, y0 - 20, z - e), max: IVec3(x + e, y0 + 24, z + e), build: { w in MilitaryBase.build(&w, x, y0, z, seed) })
            return StructureStart(kind: "military_base", pieces: [piece], anchor: IVec3(x, y0 + 1, z + R + 6))
        }
    }

    // Soldier posts: (kind, dx, dy, dz) relative to the centre at ground-floor level.
    static func garrison() -> [(String, Int, Int, Int)] {
        var out: [(String, Int, Int, Int)] = []
        // Sentries walking the apron outside the walls.
        let o = R + 5
        out += [("soldier_recruit", -o, 1, -10), ("soldier_recruit", o, 1, 10), ("soldier_trooper", 10, 1, -o), ("soldier_recruit", -12, 1, o)]
        // Gate guards and entrance hall.
        out += [("soldier_recruit", -4, 1, 26), ("soldier_recruit", 4, 1, 26), ("soldier_trooper", 0, 1, 18)]
        // Ground floor: barracks (NW), armory (NE), mess (SW), workshop (SE), corridors.
        out += [("soldier_recruit", -18, 1, -18), ("soldier_recruit", -12, 1, -22), ("soldier_recruit", -22, 1, -10), ("soldier_trooper", -10, 1, -12)]
        out += [("soldier_trooper", 16, 1, -16), ("soldier_trooper", 22, 1, -10)]
        out += [("soldier_recruit", -16, 1, 16), ("soldier_recruit", -10, 1, 22)]
        out += [("soldier_trooper", 16, 1, 18), ("soldier_recruit", 0, 1, -24)]
        // Upper floor: command room, quarters, comms, barracks.
        out += [("soldier_ironclad", 0, 7, 0), ("soldier_marksman", 4, 7, 4), ("soldier_trooper", -16, 7, -16), ("soldier_trooper", 16, 7, -16),
                ("soldier_recruit", 16, 7, 16), ("soldier_trooper", 20, 7, 20)]
        // Basement depot and vault.
        out += [("soldier_trooper", -14, -5, 10), ("soldier_ironclad", 18, -5, 18), ("soldier_recruit", 10, -5, -14)]
        // Roof: a marksman over each wall, patrols.
        out += [("soldier_marksman", 0, 13, -27), ("soldier_marksman", 0, 13, 27), ("soldier_marksman", -27, 13, 0), ("soldier_marksman", 27, 13, 0),
                ("soldier_recruit", -12, 13, -12), ("soldier_trooper", 12, 13, 12)]
        return out
    }

    static func build(_ w: inout StructWriter, _ cx: Int, _ y0: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let P = g("steel_plating"), F = g("steel_grating"), Hz = g("hazard_plating"), Gl = g("armored_glass"), L = g("light_panel")
        let C = g("command_console"), Cr = g("ammo_crate"), S = g("steel_plating_stairs"), Sl = g("steel_plating_slab")
        let SlTop = Blocks.has("steel_plating_slab[top]") ? Blocks.id("steel_plating_slab[top]") : P
        let bars = g("iron_bars"), wool = g("gray_wool"), white = g("white_wool"), gravel = GRAVEL
        let R = MilitaryBase.R, T = 4                                   // T: tower half-size
        let yB = y0 - 6, yU = y0 + 6, yR = y0 + 12, yT = y0 + 18          // floor levels
        func X(_ d: Int) -> Int { cx + d }
        func Z(_ d: Int) -> Int { cz + d }
        // Apron: cleared, levelled ground around the walls; a plated road to the gate.
        let A = R + 9
        w.fill(X(-A), y0 + 1, Z(-A), X(A), y0 + 30, Z(A), AIR)
        for dz in -A...A { for dx in -A...A where abs(dx) > R + T || abs(dz) > R + T { w.pillarDown(X(dx), y0, Z(dz), DIRT, minY: y0 - 12) } }
        w.fill(X(-A), y0, Z(-A), X(A), y0, Z(A), gravel)
        w.fill(X(-3), y0, Z(R), X(3), y0, Z(A), F)
        for k in stride(from: R + 2, through: A, by: 3) { w.set(X(-4), y0, Z(k), Hz); w.set(X(4), y0, Z(k), Hz) }
        // Foundations under the whole footprint.
        for dz in -(R + T)...(R + T) { for dx in -(R + T)...(R + T) { w.pillarDown(X(dx), yB - 1, Z(dz), P, minY: yB - 24) } }
        // Main block: solid steel, then hollow levels.
        w.fill(X(-R), yB - 1, Z(-R), X(R), yR, Z(R), P)
        for (floorY, top) in [(yB, y0 - 1), (y0, yU - 1), (yU, yR - 1)] {
            w.fill(X(-R + 1), floorY + 1, Z(-R + 1), X(R - 1), top, Z(R - 1), AIR)
            w.fill(X(-R + 1), floorY, Z(-R + 1), X(R - 1), floorY, Z(R - 1), F)
        }
        w.fill(X(-R + 1), yR, Z(-R + 1), X(R - 1), yR, Z(R - 1), F)
        // Exterior: hazard bands, buttress ribs, window slits.
        for y in [y0, yR] {
            w.fill(X(-R), y, Z(-R), X(R), y, Z(-R), Hz); w.fill(X(-R), y, Z(R), X(R), y, Z(R), Hz)
            w.fill(X(-R), y, Z(-R), X(-R), y, Z(R), Hz); w.fill(X(R), y, Z(-R), X(R), y, Z(R), Hz)
        }
        for k in stride(from: -R + 8, through: R - 8, by: 8) where abs(k) > 4 {
            for (x, z) in [(X(k), Z(-R - 1)), (X(k), Z(R + 1)), (X(-R - 1), Z(k)), (X(R + 1), Z(k))] { w.fill(x, y0, z, x, yR + 1, z, P) }
        }
        for k in stride(from: -R + 6, through: R - 7, by: 5) where abs(k) > 5 && abs(k) < R - 5 {
            for (wy0, wy1) in [(y0 + 3, y0 + 4), (yU + 3, yU + 4)] {
                w.fill(X(k), wy0, Z(-R), X(k + 1), wy1, Z(-R), Gl); w.fill(X(k), wy0, Z(R), X(k + 1), wy1, Z(R), Gl)
                w.fill(X(-R), wy0, Z(k), X(-R), wy1, Z(k + 1), Gl); w.fill(X(R), wy0, Z(k), X(R), wy1, Z(k + 1), Gl)
            }
        }
        // Roof parapet with crenels, and the corner towers.
        w.fill(X(-R), yR + 1, Z(-R), X(R), yR + 2, Z(R), P)
        w.fill(X(-R + 1), yR + 1, Z(-R + 1), X(R - 1), yR + 2, Z(R - 1), AIR)
        for k in stride(from: -R + 2, through: R - 2, by: 3) {
            for (x, z) in [(X(k), Z(-R)), (X(k), Z(R)), (X(-R), Z(k)), (X(R), Z(k))] { w.set(x, yR + 2, z, AIR) }
        }
        for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] {
            let tx = X(sx * R), tz = Z(sz * R)
            w.fill(tx - T, yB - 1, tz - T, tx + T, yT, tz + T, P)
            w.fill(tx - T, yT, tz - T, tx + T, yT, tz + T, Hz)
            // Guard rooms on every level open into the building's corner rooms.
            for (floorY, top) in [(yB, y0 - 1), (y0, yU - 1), (yU, yR - 1)] {
                w.fill(tx - T + 1, floorY + 1, tz - T + 1, tx + T - 1, top, tz + T - 1, AIR)
            }
            for y in [y0 + 3, yU + 3] {
                w.fill(tx + sx * T, y, tz - 1, tx + sx * T, y + 1, tz + 1, Gl)
                w.fill(tx - 1, y, tz + sz * T, tx + 1, y + 1, tz + sz * T, Gl)
            }
            // Upper tower room above the roof, stairs up to the gun deck, doorway from the roof.
            w.fill(tx - T + 1, yR + 1, tz - T + 1, tx + T - 1, yT - 1, tz + T - 1, AIR)
            w.fill(tx - T + 1, yR, tz - T + 1, tx + T - 1, yR, tz + T - 1, F)
            let dx = -sx, dz = -sz                                      // towards the building centre
            w.fill(tx + dx * T, yR + 1, tz - 1, tx + dx * T, yR + 3, tz + 1, AIR)
            w.fill(tx - 1, yR + 1, tz + dz * T, tx + 1, yR + 3, tz + dz * T, AIR)
            let sz0 = tz - sz * (T - 1)                                 // outer wall row inside the tower
            for i in 0..<6 {
                let x = tx - sx * 3 + sx * i
                let st = S + BlockID(sx > 0 ? 3 : 2)
                w.set(x, yR + 1 + i, sz0 - sz * 0, st)
                if i >= 2 { w.fill(x, yR + 2 + i, sz0, x, min(yT + 2, yR + 3 + i), sz0, AIR) }
            }
            w.set(tx, yT - 1, tz, L)
            // Gun deck: parapet ring and the deck gun.
            w.fill(tx - T, yT + 1, tz - T, tx + T, yT + 1, tz + T, P)
            w.fill(tx - T + 1, yT + 1, tz - T + 1, tx + T - 1, yT + 1, tz + T - 1, AIR)
            for (x, z) in [(tx - T, tz - T), (tx + T, tz - T), (tx - T, tz + T), (tx + T, tz + T)] { w.set(x, yT + 2, z, L) }
            w.mob("deck_gun", V3(Float(tx) + 0.5, Float(yT + 1), Float(tz) + 0.5))
        }
        // The gate: a hazard-framed opening on the south wall with a raised portcullis.
        w.fill(X(-3), y0, Z(R), X(3), y0 + 6, Z(R + 1), Hz)
        w.fill(X(-2), y0 + 1, Z(R - 1), X(2), y0 + 4, Z(R + 1), AIR)
        w.fill(X(-2), y0 + 5, Z(R + 1), X(2), y0 + 5, Z(R + 1), bars)
        w.fill(X(-2), y0, Z(R - 1), X(2), y0, Z(R + 1), F)
        w.set(X(-3), y0 + 5, Z(R + 2), L); w.set(X(3), y0 + 5, Z(R + 2), L)
        // Interior plan on each level: crossing corridors 5 wide, four quadrant rooms with doorways.
        for (floorY, top) in [(yB, y0 - 1), (y0, yU - 1), (yU, yR - 1)] {
            let y1 = floorY + 1
            w.fill(X(-3), y1, Z(-R + 1), X(-3), top, Z(R - 1), P); w.fill(X(3), y1, Z(-R + 1), X(3), top, Z(R - 1), P)
            w.fill(X(-R + 1), y1, Z(-3), X(R - 1), top, Z(-3), P); w.fill(X(-R + 1), y1, Z(3), X(R - 1), top, Z(3), P)
            w.fill(X(-2), y1, Z(-R + 1), X(2), top, Z(R - 1), AIR)
            w.fill(X(-R + 1), y1, Z(-2), X(R - 1), top, Z(2), AIR)
            for k in [-16, -9, 9, 16] {
                w.fill(X(-3), y1, Z(k - 1), X(-3), y1 + 2, Z(k + 1), AIR); w.fill(X(3), y1, Z(k - 1), X(3), y1 + 2, Z(k + 1), AIR)
                w.fill(X(k - 1), y1, Z(-3), X(k + 1), y1 + 2, Z(-3), AIR); w.fill(X(k - 1), y1, Z(3), X(k + 1), y1 + 2, Z(3), AIR)
            }
            // Ceiling lights over the corridors and rooms.
            for k in stride(from: -R + 4, through: R - 4, by: 6) {
                w.set(X(0), top + 1, Z(k), L); w.set(X(k), top + 1, Z(0), L)
                for j in [-16, 16] { w.set(X(j), top + 1, Z(k), L) }
            }
            // Hazard stripes where the corridors cross.
            for k in -2...2 { w.set(X(k), floorY, Z(-3), Hz); w.set(X(k), floorY, Z(3), Hz); w.set(X(-3), floorY, Z(k), Hz); w.set(X(3), floorY, Z(k), Hz) }
        }
        // Stairs: ground -> upper (north corridor, climbing north), upper -> roof (west corridor, climbing west),
        // ground -> basement (east corridor, going down eastwards).
        for i in 0..<6 {
            w.fill(X(-1), y0 + 1 + i, Z(-10 - i), X(1), y0 + 1 + i, Z(-10 - i), S)
            if i >= 2 { w.fill(X(-1), y0 + 2 + i, Z(-10 - i), X(1), yU + 2, Z(-10 - i), AIR) }
            w.fill(X(-8 - i), yU + 1 + i, Z(-1), X(-8 - i), yU + 1 + i, Z(1), S + 2)
            if i >= 2 { w.fill(X(-8 - i), yU + 2 + i, Z(-1), X(-8 - i), yR + 2, Z(1), AIR) }
            w.fill(X(8 + i), y0 - i, Z(-1), X(8 + i), y0 - i, Z(1), S + 2)
            w.fill(X(8 + i), y0 - i + 1, Z(-1), X(8 + i), y0 + 3, Z(1), AIR)
        }
        // Railings round the stair wells.
        w.fill(X(-2), yU + 1, Z(-15), X(-2), yU + 1, Z(-12), bars); w.fill(X(2), yU + 1, Z(-15), X(2), yU + 1, Z(-12), bars)
        w.fill(X(-13), yR + 1, Z(-2), X(-10), yR + 1, Z(-2), bars); w.fill(X(-13), yR + 1, Z(2), X(-10), yR + 1, Z(2), bars)

        // Ground floor rooms.
        // NW barracks: two-tier bunks in rows, lockers along the wall.
        for z in stride(from: -R + 3, through: -7, by: 4) {
            for x in stride(from: -R + 3, through: -8, by: 5) {
                w.fill(X(x), y0 + 1, Z(z), X(x + 1), y0 + 1, Z(z), wool)
                w.fill(X(x), y0 + 3, Z(z), X(x + 1), y0 + 3, Z(z), wool)
                w.fill(X(x + 2), y0 + 1, Z(z), X(x + 2), y0 + 3, Z(z), P)
                w.set(X(x - 1), y0 + 1, Z(z), Sl)
            }
        }
        for x in stride(from: -R + 2, through: -6, by: 2) { w.set(X(x), y0 + 1, Z(-R + 1), g("barrel")) }
        w.chest(X(-5), y0 + 1, Z(-R + 1), loot: "steelhold_supply", seed: rng.next(), facing: 1)
        // NE armory: crate stacks, weapon chests, an anvil.
        for x in stride(from: 6, through: R - 3, by: 4) {
            w.fill(X(x), y0 + 1, Z(-R + 1), X(x + 1), y0 + 2, Z(-R + 1), Cr)
            w.fill(X(x), y0 + 1, Z(-6), X(x + 1), y0 + 1, Z(-6), Cr)
        }
        for z in stride(from: -R + 5, through: -9, by: 6) { w.fill(X(R - 1), y0 + 1, Z(z), X(R - 1), y0 + 3, Z(z), bars) }
        for (i, z) in [-24, -18, -12].enumerated() {
            w.chest(X(14 + i * 4), y0 + 1, Z(z), loot: "steelhold_armory", seed: rng.next(), facing: rng.int(4))
        }
        w.set(X(8), y0 + 1, Z(-12), g("anvil"))
        // Weapon racks: guns hung in frames above the crates on the north wall (punch one to take it).
        let windows = Set(stride(from: -R + 6, through: R - 7, by: 5).filter { abs($0) > 5 && abs($0) < R - 5 }.flatMap { [$0, $0 + 1] })
        for x in stride(from: 6, through: R - 3, by: 2) where !windows.contains(x) && rng.chance(0.75) {
            let gun = Guns.all[[Guns.rifle, Guns.rifle, Guns.smg, Guns.smg, Guns.shotgun, Guns.sniper][rng.int(6)]]
            if Items.has(gun.key) { w.frame(X(x), y0 + 3, Z(-R + 1), state: 1, item: ItemStack(Items.id(gun.key), 1)) }
        }
        // SW mess hall: long tables with benches, a food chest.
        for z in stride(from: 8, through: R - 4, by: 6) {
            w.fill(X(-R + 4), y0 + 1, Z(z), X(-8), y0 + 1, Z(z), SlTop)
            w.fill(X(-R + 4), y0 + 1, Z(z - 1), X(-8), y0 + 1, Z(z - 1), Sl)
            w.fill(X(-R + 4), y0 + 1, Z(z + 1), X(-8), y0 + 1, Z(z + 1), Sl)
        }
        w.fill(X(-R + 1), y0 + 1, Z(6), X(-R + 1), y0 + 1, Z(12), g("furnace"))
        w.chest(X(-R + 1), y0 + 1, Z(14), loot: "steelhold_supply", seed: rng.next(), facing: 3)
        // SE workshop: benches, furnaces, a smithing corner, painted bay floor.
        w.fill(X(6), y0, Z(6), X(R - 2), y0, Z(R - 2), Hz)
        w.fill(X(8), y0, Z(8), X(R - 4), y0, Z(R - 4), F)
        w.fill(X(R - 1), y0 + 1, Z(6), X(R - 1), y0 + 1, Z(16), g("crafting_table"))
        w.fill(X(R - 1), y0 + 1, Z(18), X(R - 1), y0 + 1, Z(24), g("furnace"))
        w.set(X(R - 1), y0 + 1, Z(26), g("smithing_table")); w.set(X(R - 2), y0 + 1, Z(R - 1), g("anvil"))
        w.chest(X(10), y0 + 1, Z(R - 1), loot: "steelhold_supply", seed: rng.next(), facing: 0)

        // Upper floor: the command room in the middle (consoles round the walls, a plotting table).
        w.fill(X(-7), yU + 1, Z(-7), X(7), yR - 1, Z(7), P)
        w.fill(X(-6), yU + 1, Z(-6), X(6), yR - 1, Z(6), AIR)
        for (dx, dz) in [(0, -7), (0, 7), (-7, 0), (7, 0)] {
            let wx: Int = dz == 0 ? 0 : 1, wz: Int = dx == 0 ? 0 : 1
            w.fill(X(dx) - wx, yU + 1, Z(dz) - wz, X(dx) + wx, yU + 3, Z(dz) + wz, AIR)
        }
        for k in -5...5 where abs(k) > 1 {
            w.set(X(k), yU + 1, Z(-6), C); w.set(X(k), yU + 1, Z(6), C); w.set(X(-6), yU + 1, Z(k), C); w.set(X(6), yU + 1, Z(k), C)
            w.set(X(k), yU + 3, Z(-7), Gl); w.set(X(k), yU + 3, Z(7), Gl)
        }
        w.fill(X(-1), yU + 1, Z(-1), X(1), yU + 1, Z(1), C)
        w.fill(X(-1), yU + 2, Z(-1), X(1), yU + 2, Z(1), Gl)
        w.fill(X(-3), yR, Z(-3), X(3), yR, Z(3), Gl)                     // skylight
        w.chest(X(-5), yU + 1, Z(-5), loot: "steelhold_command", seed: rng.next(), facing: 1)
        w.chest(X(5), yU + 1, Z(5), loot: "steelhold_command", seed: rng.next(), facing: 0)
        // NW officers' quarters, NE comms, SW medbay, SE barracks.
        for z in stride(from: -R + 3, through: -10, by: 7) {
            w.fill(X(-R + 2), yU + 1, Z(z), X(-R + 3), yU + 1, Z(z), white)
            w.fill(X(-R + 1), yU + 1, Z(z + 2), X(-R + 1), yU + 3, Z(z + 3), g("bookshelf"))
        }
        w.chest(X(-10), yU + 1, Z(-R + 1), loot: "steelhold_armory", seed: rng.next(), facing: 1)
        for x in stride(from: 6, through: R - 2, by: 2) { w.set(X(x), yU + 1, Z(-R + 1), C) }
        for z in stride(from: -R + 3, through: -6, by: 3) { w.set(X(R - 1), yU + 1, Z(z), C); w.set(X(R - 1), yU + 3, Z(z), L) }
        for z in stride(from: 8, through: R - 3, by: 4) {
            w.fill(X(-R + 2), yU + 1, Z(z), X(-R + 3), yU + 1, Z(z), white)
            w.set(X(-R + 4), yU + 1, Z(z), Sl)
        }
        w.set(X(-8), yU + 1, Z(R - 1), g("brewing_stand"))
        w.chest(X(-6), yU + 1, Z(R - 1), loot: "steelhold_supply", seed: rng.next(), facing: 0)
        for z in stride(from: 7, through: R - 3, by: 4) {
            for x in stride(from: 8, through: R - 4, by: 5) {
                w.fill(X(x), yU + 1, Z(z), X(x + 1), yU + 1, Z(z), wool)
                w.fill(X(x), yU + 3, Z(z), X(x + 1), yU + 3, Z(z), wool)
                w.fill(X(x + 2), yU + 1, Z(z), X(x + 2), yU + 3, Z(z), P)
            }
        }

        // Basement: supply depot, generator, and the barred vault in the south-east.
        for x in stride(from: -R + 3, through: -6, by: 3) {
            for z in stride(from: -R + 3, through: -6, by: 4) where hashf(x, yB, z, 0x5EE1) < 0.8 {
                w.fill(X(x), yB + 1, Z(z), X(x + 1), yB + 1 + Int(hashf(x, z, 1, 0x5EE2) * 3), Z(z + 1), Cr)
            }
        }
        for (i, z) in [-24, -16].enumerated() { w.chest(X(-R + 1), yB + 1, Z(z), loot: i == 0 ? "steelhold_supply" : "steelhold_armory", seed: rng.next(), facing: 3) }
        w.fill(X(-R + 4), yB + 1, Z(8), X(-8), yB + 1, Z(R - 4), AIR)
        w.fill(X(-18), yB + 1, Z(14), X(-14), yB + 4, Z(18), P)
        w.fill(X(-17), yB + 1, Z(15), X(-15), yB + 3, Z(17), g("redstone_block"))
        for (x, z) in [(-19, 13), (-13, 13), (-19, 19), (-13, 19)] { w.fill(X(x), yB + 1, Z(z), X(x), yB + 4, Z(z), L) }
        w.chest(X(-R + 1), yB + 1, Z(10), loot: "steelhold_supply", seed: rng.next(), facing: 3)
        for x in stride(from: 6, through: R - 3, by: 3) { w.fill(X(x), yB + 1, Z(-R + 1), X(x + 1), yB + 3, Z(-R + 1), Cr) }
        w.chest(X(R - 1), yB + 1, Z(-12), loot: "steelhold_supply", seed: rng.next(), facing: 2)
        w.fill(X(12), yB + 1, Z(12), X(12), y0 - 1, Z(R - 1), bars)
        w.fill(X(12), yB + 1, Z(12), X(R - 1), y0 - 1, Z(12), bars)
        w.fill(X(12), yB + 1, Z(20), X(12), yB + 3, Z(21), AIR)
        w.chest(X(R - 2), yB + 1, Z(R - 2), loot: "steelhold_vault", seed: rng.next(), facing: 0)
        w.chest(X(R - 4), yB + 1, Z(R - 2), loot: "steelhold_vault", seed: rng.next(), facing: 0)
        w.chest(X(R - 2), yB + 1, Z(R - 5), loot: "steelhold_command", seed: rng.next(), facing: 2)

        // Roof: an observation mast and sandbag-like crate nests at the marksman posts.
        w.fill(X(0), yR + 1, Z(0), X(0), yR + 7, Z(0), P)
        w.set(X(0), yR + 8, Z(0), L)
        for (dx, dz) in [(0, -27), (0, 27), (-27, 0), (27, 0)] {
            let ox: Int = dx == 0 ? 1 : 0, oz: Int = dz == 0 ? 1 : 0
            let sx = dx.signum(), sz = dz.signum()
            for k in -2...2 { w.set(X(dx + ox * k - sx), yR + 1, Z(dz + oz * k - sz), Cr) }
        }

        // The garrison.
        for (k, dx, dy, dz) in garrison() {
            w.mob(k, V3(Float(X(dx)) + 0.5, Float(y0 + dy), Float(Z(dz)) + 0.5))
        }
    }
}
