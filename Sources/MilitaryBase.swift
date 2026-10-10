import Foundation
import simd

// Military bases: very rare (one per 40x40-chunk region at most) on fairly level land (plains, savanna, desert,
// snowy plains, badlands, meadows, forests, taiga). Since 2026-10-04 they are The Capital's citadels (CapitalBase.swift);
// this file keeps the structure type, the steel block family the ships and vehicles use, and their textures.
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
        // One candidate per 40x40-chunk region (64 left most players never meeting one: Remington playtest 2).
        // The Capital citadel (CapitalBase.swift) under the old key: 113 across, so it reaches 4 chunks from its start.
        StructureType(name: "military_base", spacing: 40, separation: 14, salt: 70411993, reach: 4) { [unowned gen] seed, cx0, cz0 in
            // Open, fairly flat ground over the whole footprint.
            func site(_ cx: Int, _ cz: Int) -> Int? {
                let x = cx * CS + 8, z = cz * CS + 8
                guard MilitaryBase.biomes.contains(gen.column(x, z).biome) else { return nil }
                let y = gen.groundY(x, z)
                guard y > SEA + 1 else { return nil }
                let R = CapitalBase.podium
                for (dx, dz) in [(-R, -R), (R, -R), (-R, R), (R, R), (0, -R), (0, R), (-R, 0), (R, 0)] {
                    let gy = gen.column(x + dx, z + dz).height          // 2D height: cheap enough for a 40-chunk grid
                    if abs(gy - y) > 12 || gy <= SEA { return nil }
                    if gen.column(x + dx, z + dz).biome.isOcean { return nil }
                }
                return y
            }
            // The region's first spot (where citadels always stood); if that ground is unfit, up to six more spots in
            // the same placement square (so the spacing holds), but only on ground no saved world had generated yet:
            // only ~1 region in 4 had a citadel and Remington's nearest was 773 blocks out (task 23).
            // Another structure under the site (seed 424242: a citadel flattened a desert pyramid and buried its
            // treasure room under the plaza, store audit). Only on ground no saved world has seen (clear), so
            // citadels in explored land never move.
            func crowded(_ cx: Int, _ cz: Int) -> Bool {
                guard let sc = gen.structures else { return false }
                let bx = cx * CS + 8, bz = cz * CS + 8, r = CapitalBase.A + 24
                for k in ["temple", "village", "pillager_outpost", "mansion", "trail_ruins"] {
                    if let o = sc.nearest(k, x: bx, z: bz, maxRegions: 1), abs(o.anchor.x - bx) < r, abs(o.anchor.z - bz) < r { return true }
                }
                return false
            }
            var cx = cx0, cz = cz0
            var found = site(cx, cz)
            if found != nil, let sc = gen.structures, sc.clear(cx: cx0, cz: cz0, reach: 5), crowded(cx0, cz0) { found = nil }
            if found == nil, let sc = gen.structures {
                let rx = floorDiv(cx0, 40), rz = floorDiv(cz0, 40)
                let s32 = UInt32(truncatingIfNeeded: seed)
                for k in 1...6 {
                    let ax = rx * 40 + Int(hashf(rx, rz, 7100 + k, s32) * 25.99), az = rz * 40 + Int(hashf(rx, rz, 7200 + k, s32) * 25.99)
                    guard sc.clear(cx: ax, cz: az, reach: 5), !crowded(ax, az), let y = site(ax, az) else { continue }
                    cx = ax; cz = az; found = y
                    break
                }
            }
            guard let y = found, WorldRules.citadelAllowed(gen, cx, cz) else { return nil }   // not on top of spawn
            let x = cx * CS + 8, z = cz * CS + 8
            let y0 = y + 1
            let e = CapitalBase.A + 8               // the site plus the ring where cut trees' leaves are cleared
            let piece = Piece(min: IVec3(x - e, y0 - 20, z - e), max: IVec3(x + e, y0 + 80, z + e), build: { w in CapitalBase.build(&w, x, y0, z, seed) })
            return StructureStart(kind: "military_base", pieces: [piece], anchor: IVec3(x, y0 + 1, z + CapitalBase.podium + 8))
        }
    }
}
