import Foundation
import simd

// Boreal Station (task 4): the Capital's snowbound listening post in the far north, built for a cold, clean,
// utilitarian feel: grey cast-concrete corridors, small blue lamps in the upper corners, steel bulkhead doors,
// everything under snow. An original layout:
//   surface   a fenced, snow-covered yard (half-size 30): a concrete blockhouse over the stairwell, a gatehouse at the
//             south gate, a lattice radar mast with a tilted dish, a watchtower, fuel tanks, a vehicle shed, floodlights
//   stairwell a switchback stair (two flights of eight) from the blockhouse down 16 blocks
//   bunker    a 47 x 47 concrete monolith 16 blocks down: a two-storey uplink hall (screen wall, core, catwalk) in a
//             ring corridor, four wings (control room, data archive, holding cells, the stair hall) and four corner
//             rooms (armory, generator hall, mess, barracks), every passage closed by a bulkhead door
// Garrisoned by the Capital's soldiers (same mob keys and steelhold_* loot as the citadels). Only in snowy biomes.

extension BlockRegistry {
    func registerBorealBlocks() {
        func block(_ n: String, _ disp: String, h: Float, snd: SoundMat = .stone) {
            guard !has(n) else { return }
            var d = BlockDef(n, disp)
            d.tex = [n]; d.hardness = h; d.resistance = 30; d.tool = .pickaxe; d.requiresTool = true; d.sound = snd
            add(d)
        }
        block("bunker_concrete", "Station Concrete", h: 3)
        block("bunker_concrete_dark", "Dark Station Concrete", h: 3)
        block("bunker_floor", "Station Floor Tiles", h: 3)
        if !has("bunker_concrete_stairs") {
            family("bunker_concrete", "bunker_concrete", "Station Concrete", h: 3, tool: .pickaxe, req: true, snd: .stone, stairs: true, slab: true, fence: false, wall: false)
        }
        // Station railing: plain grey steel rails (bars that connect like iron bars).
        if !has("station_railing") {
            var d = BlockDef("station_railing", "Steel Railing")
            d.tex = ["station_railing"]; d.render = .connect; d.connect = 2; d.layer = .cutout; d.opaque = false
            d.hardness = 5; d.resistance = 30; d.tool = .pickaxe; d.requiresTool = true; d.skyStop = false
            add(d)
        }
        // Corner lamp: a small blue lamp on a wall just under the ceiling; the facing is the way its lens looks.
        if !has("corner_lamp") {
            var d = BlockDef("corner_lamp", "Corner Lamp")
            d.tex = ["corner_lamp_side"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = false
            d.collide = false; d.noCollideBoxes = true; d.hardness = 1; d.sound = .glass; d.emit = 12
            let lens: [Box] = [Box(5, 11, 13, 11, 16, 16), Box(5, 11, 0, 11, 16, 3), Box(13, 11, 5, 16, 16, 11), Box(0, 11, 5, 3, 16, 11)]
            addFacing(d, front: "corner_lamp", boxesFor: { k in [lens[k]] })
        }
        // Data cabinet: tape reels and status lamps on the front.
        if !has("data_cabinet") {
            var d = BlockDef("data_cabinet", "Data Cabinet")
            d.tex = ["data_cabinet_side", "data_cabinet_side", "data_cabinet_top", "data_cabinet_top", "data_cabinet_side", "data_cabinet_side"]
            d.hardness = 4; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone; d.emit = 3
            addFacing(d, front: "data_cabinet_front")
        }
        // Bulkhead door: grey steel, opens by hand like a wooden door (states as the other doors: facing + open*4 + upper*8).
        if !has("bulkhead_door") {
            for upper in [false, true] { for open in [false, true] { for f in 0..<4 {
                let k = f + (open ? 4 : 0) + (upper ? 8 : 0)
                var d = BlockDef(k == 0 ? "bulkhead_door" : "bulkhead_door[\(k)]", "Bulkhead Door")
                d.tex = [upper ? "bulkhead_door_top" : "bulkhead_door_bottom"]; d.render = .model; d.layer = .cutout; d.opaque = false
                d.boxes = [BlockRegistry.panel(open ? [2, 3, 1, 0][f] : [0, 1, 2, 3][f])]
                d.hardness = 5; d.resistance = 30; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone
                d.group = "bulkhead_door"; d.hidden = k != 0; d.shape = "door"; d.skyStop = false
                add(d)
            } } }
        }
    }
}

extension TextureGen {
    static func borealPainters(_ p: inout [String: Painter]) {
        // Station concrete: cool grey cast panels, a seam on two edges, four form-tie holes, faint mottling.
        p["bunker_concrete"] = { x, y in
            if x == 0 { return hex(0x6E767E) }
            if y == 15 { return hex(0x737B83) }
            if (x == 3 || x == 12) && (y == 4 || y == 11) { return hex(0x5C636A) }
            let k: Float = 0.95 + 0.04 * r(x / 4, y / 4, 4101) + 0.03 * r(x, y, 4102)
            return hex(0x8693A2, k)
        }
        // The darker lower wall band, with a lighter lip along its top.
        p["bunker_concrete_dark"] = { x, y in
            if y == 0 { return hex(0x7A838B) }
            if y == 1 { return hex(0x4A5158) }
            if x == 0 { return hex(0x4E555C) }
            return hex(0x56616D, 0.94 + 0.05 * r(x / 3, y / 2, 4103) + 0.03 * r(x, y, 4104))
        }
        // Floor: 8 px tiles with dark joints, each tile its own shade.
        p["bunker_floor"] = { x, y in
            if x % 8 == 0 || y % 8 == 0 { return hex(0x5A6168) }
            let tile: Float = 0.94 + 0.06 * r(x / 8, y / 8, 4105)
            return hex(0x7A8591, tile * (0.97 + 0.03 * r(x, y, 4106)))
        }
        // Railing: a handrail along the top, a mid rail, slim posts; the rest clear.
        p["station_railing"] = { x, y in
            if y <= 1 { return hex(y == 0 ? 0xA8B2BC : 0x6E7882) }
            if y == 8 || ((x == 1 || x == 14) && y > 1) { return hex(0x8A949E, 0.95 + 0.05 * r(x, y, 4113)) }
            if x == 7 || x == 8 { return hex(0x7C8690) }
            return V4(0, 0, 0, 0)
        }
        // Corner lamp: a pale blue lens in a dark steel frame (front), plain frame round the sides.
        p["corner_lamp"] = { x, y in
            if x < 2 || x > 13 || y < 2 || y > 13 { return hex(0x2A3038) }
            let cx = Float(x) - 7.5, cy = Float(y) - 7.5
            let d: Float = sqrtf(cx * cx + cy * cy)
            return d < 2.5 ? hex(0xE4F4FF) : hex(0x5AB4FF, 1.05 - d * 0.03)
        }
        p["corner_lamp_side"] = { x, y in
            if y > 9 { return hex(0x78C4FF) }
            return hex(0x3A414A, 0.95 + 0.05 * r(x, y, 4107))
        }
        // Data cabinet: two tape reels behind glass, then a row of status lamps and a vent grille.
        p["data_cabinet_front"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x30353C) }
            if y <= 7 {
                for cx in [4, 11] {
                    let dx = Float(x - cx), dy = Float(y - 4)
                    let d: Float = sqrtf(dx * dx + dy * dy)
                    if d < 1.2 { return hex(0xB8C0C8) }
                    if d < 3.1 { return hex(r(x, y, 4108) > 0.8 ? 0x2A2E33 : 0x4A3A2A) }
                }
                return hex(0x1C2228)
            }
            if y == 9 && x % 2 == 1 {
                let lamps: [UInt32] = [0x5AB4FF, 0x40C060, 0xE0B020, 0x5AB4FF, 0xD03A2A, 0x5AB4FF, 0x40C060]
                return hex(lamps[(x / 2) % lamps.count])
            }
            if y >= 11 && y <= 13 { return hex(x % 2 == 0 ? 0x2C3137 : 0x4E555D) }
            return hex(0x5A6169, 0.95 + 0.05 * r(x, y, 4109))
        }
        p["data_cabinet_side"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x30353C) }
            if (x == 3 || x == 12) && y >= 3 && y <= 12 && y % 2 == 0 { return hex(0x2A2F35) }
            return hex(0x5A6169, 0.95 + 0.05 * r(x, y, 4110))
        }
        p["data_cabinet_top"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x30353C) }
            return hex(0x535A62, 0.95 + 0.05 * r(x, y, 4111))
        }
        // Bulkhead door: ribbed grey steel; the upper half has a small dark window and a blue status lamp, the lower
        // half a hazard band at the foot.
        func door(_ x: Int, _ y: Int, _ upper: Bool) -> V4 {
            if x == 0 || x == 15 { return hex(0x3E444B) }
            if upper {
                if y == 0 { return hex(0x3E444B) }
                if x >= 5 && x <= 10 && y >= 3 && y <= 8 {
                    if x == 5 || x == 10 || y == 3 || y == 8 { return hex(0x2C3137) }
                    return x + y == 11 || x + y == 12 ? hex(0x6A8094) : hex(0x1E2A36)
                }
                if x == 12 && y == 11 { return hex(0x8AD0FF) }
            } else {
                if y == 15 { return hex(0x3E444B) }
                if y >= 12 { return ((x + y) / 3) % 2 == 0 ? hex(0xD8A820) : hex(0x26272A) }
                if x == 12 && y >= 2 && y <= 5 { return hex(0x2E3339) }          // handle
            }
            let rib = y % 4 == 3
            return hex(rib ? 0x555C63 : 0x737A82, 0.96 + 0.04 * r(x, y + (upper ? 16 : 0), 4112))
        }
        p["bulkhead_door_top"] = { x, y in door(x, y, true) }
        p["bulkhead_door_bottom"] = { x, y in door(x, y, false) }
    }
}

enum BorealStation {
    static let kind = "boreal_station"
    static let display = "Boreal Station"
    static let yard = 30                     // fence half-size
    static let B = 24                        // bunker monolith half-size (rooms inside +-23)
    static let depth = 16                    // bunker floor block = surface block - 16
    static let biomes: Set<Biome> = [.snowyPlains, .snowyTaiga, .iceSpikes, .grove, .snowySlopes]

    // MARK: Bunker layout (relative to the centre; rows above the floor block; open rows 1...h)
    enum Use: UInt8 { case corridor = 1, hall, control, archive, cells, armory, generator, mess, barracks, stair }
    struct Room { let x0, z0, x1, z1, h: Int; let use: Use }
    static let rooms: [Room] = {
        var r: [Room] = []
        r.append(Room(x0: -7, z0: -7, x1: 7, z1: 7, h: 9, use: .hall))
        // Ring corridor (cells with max(|dx|, |dz|) in 11...13) as four strips.
        r.append(Room(x0: -13, z0: -13, x1: 13, z1: -11, h: 4, use: .corridor))
        r.append(Room(x0: -13, z0: 11, x1: 13, z1: 13, h: 4, use: .corridor))
        r.append(Room(x0: -13, z0: -10, x1: -11, z1: 10, h: 4, use: .corridor))
        r.append(Room(x0: 11, z0: -10, x1: 13, z1: 10, h: 4, use: .corridor))
        // Hall to ring.
        r.append(Room(x0: -1, z0: -10, x1: 1, z1: -8, h: 4, use: .corridor))
        r.append(Room(x0: -1, z0: 8, x1: 1, z1: 10, h: 4, use: .corridor))
        r.append(Room(x0: -10, z0: -1, x1: -8, z1: 1, h: 4, use: .corridor))
        r.append(Room(x0: 8, z0: -1, x1: 10, z1: 1, h: 4, use: .corridor))
        // Ring to the wings and corner rooms.
        r.append(Room(x0: -1, z0: -15, x1: 1, z1: -14, h: 4, use: .corridor))
        r.append(Room(x0: -15, z0: -1, x1: -14, z1: 1, h: 4, use: .corridor))
        r.append(Room(x0: 14, z0: -1, x1: 15, z1: 1, h: 4, use: .corridor))
        r.append(Room(x0: -6, z0: 14, x1: -4, z1: 15, h: 4, use: .corridor))
        for sx in [-1, 1] { for sz in [-1, 1] {
            r.append(Room(x0: sx < 0 ? -15 : 14, z0: sz < 0 ? -12 : 10, x1: sx < 0 ? -14 : 15, z1: sz < 0 ? -10 : 12, h: 4, use: .corridor))
        } }
        r.append(Room(x0: -6, z0: -23, x1: 6, z1: -16, h: 4, use: .control))
        r.append(Room(x0: -23, z0: -6, x1: -16, z1: 6, h: 4, use: .archive))
        r.append(Room(x0: 16, z0: -6, x1: 23, z1: 6, h: 4, use: .cells))
        r.append(Room(x0: 16, z0: -23, x1: 23, z1: -9, h: 5, use: .armory))
        r.append(Room(x0: 16, z0: 9, x1: 23, z1: 23, h: 6, use: .generator))
        r.append(Room(x0: -23, z0: 9, x1: -16, z1: 23, h: 4, use: .mess))
        r.append(Room(x0: -23, z0: -23, x1: -16, z1: -9, h: 4, use: .barracks))
        r.append(Room(x0: -6, z0: 16, x1: -5, z1: 21, h: 4, use: .stair))      // the stair hall's bottom landing
        return r
    }()
    // Bulkheads: a wall of steel across a passage with a door in its middle (x, z of the door; along = the passage
    // runs along z). The passages are three wide (one cell each side of the door).
    static let bulkheads: [(x: Int, z: Int, alongZ: Bool)] = [
        (0, -9, true), (0, 9, true), (-9, 0, false), (9, 0, false),          // hall
        (0, -15, true), (-15, 0, false), (15, 0, false), (-5, 15, true),     // wings
        (-15, -11, false), (15, -11, false), (-15, 11, false), (15, 11, false),
    ]
    static let NX = 2 * B + 1, NY = 13           // rows 0...12 above the floor block

    // Open-space mask: room use per cell (0 = solid), rows 0...12 (row 0 is the floor block row, never open).
    static let mask: [UInt8] = {
        var m = [UInt8](repeating: 0, count: NX * NX * NY)
        func i(_ dx: Int, _ ly: Int, _ dz: Int) -> Int { ((dz + B) * NX + (dx + B)) * NY + ly }
        for rm in rooms {
            for dz in rm.z0...rm.z1 { for dx in rm.x0...rm.x1 { for ly in 1...rm.h { m[i(dx, ly, dz)] = rm.use.rawValue } } }
        }
        for b in bulkheads {
            for k in -1...1 {
                let (dx, dz) = b.alongZ ? (b.x + k, b.z) : (b.x, b.z + k)
                for ly in 1...4 where k != 0 || ly >= 3 { m[i(dx, ly, dz)] = 0 }
            }
        }
        return m
    }()
    @inline(__always) static func open(_ dx: Int, _ ly: Int, _ dz: Int) -> UInt8 {
        guard abs(dx) <= B, abs(dz) <= B, ly >= 0, ly < NY else { return 0 }
        return mask[((dz + B) * NX + (dx + B)) * NY + ly]
    }
    @inline(__always) static func isBulkhead(_ dx: Int, _ dz: Int) -> Bool {
        bulkheads.contains { b in b.alongZ ? (b.z == dz && abs(dx - b.x) <= 1) : (b.x == dx && abs(dz - b.z) <= 1) }
    }

    // Hall catwalk (floor block row 5): a U round the north, east and west walls, open to the south; reached by a
    // stair along the west wall.
    @inline(__always) static func catwalk(_ dx: Int, _ dz: Int) -> Bool {
        guard abs(dx) <= 7, abs(dz) <= 7, dz <= 1 else { return false }
        return dz <= -5 || abs(dx) >= 5
    }
    @inline(__always) static func hallStair(_ dx: Int, _ dz: Int) -> Int? {      // the stair's row (1...5) at a cell
        guard dx >= -7 && dx <= -6 && dz >= 2 && dz <= 6 else { return nil }
        return 7 - dz
    }

    // MARK: Placement

    static func type(_ gen: WorldGen) -> StructureType {
        // At most one per 28 x 28-chunk region, on fairly level snowy ground. The region's first candidate, else up to
        // eight more spots in the same placement square (snowy biomes are patchy), never next to another structure,
        // and never on ground a saved world had generated before stations existed.
        StructureType(name: kind, spacing: 28, separation: 8, salt: 51829377, reach: 3) { [unowned gen] seed, cx0, cz0 in
            func site(_ cx: Int, _ cz: Int) -> Int? {
                let x = cx * CS + 8, z = cz * CS + 8
                guard BorealStation.biomes.contains(gen.column(x, z).biome) else { return nil }
                let y = gen.groundY(x, z)
                guard y > SEA + 2 else { return nil }
                let R = BorealStation.yard
                for (dx, dz) in [(-R, -R), (R, -R), (-R, R), (R, R), (0, -R), (0, R), (-R, 0), (R, 0), (-15, -15), (15, 15), (-15, 15), (15, -15)] {
                    let c = gen.column(x + dx, z + dz)
                    if abs(c.height - y) > 7 || c.height <= SEA || c.biome.isOcean || c.biome == .river || c.biome == .frozenRiver { return nil }
                }
                return y
            }
            func crowded(_ cx: Int, _ cz: Int) -> Bool {
                guard let sc = gen.structures else { return false }
                let bx = cx * CS + 8, bz = cz * CS + 8
                for k in ["village", "temple", "pillager_outpost", "mansion", "ruined_portal", "trail_ruins", "military_base", "capital_city", "great_ruin"] {
                    guard let o = sc.nearest(k, x: bx, z: bz, maxRegions: 1) else { continue }
                    let m = BorealStation.yard + 12
                    if o.max.x >= bx - m && o.min.x <= bx + m && o.max.z >= bz - m && o.min.z <= bz + m { return true }
                }
                return false
            }
            func usable(_ cx: Int, _ cz: Int) -> Int? {
                if let sc = gen.structures, !sc.clear(cx: cx, cz: cz, reach: 3, guardSet: sc.legacyStations) { return nil }
                guard let y = site(cx, cz), !crowded(cx, cz) else { return nil }
                return y
            }
            var cx = cx0, cz = cz0
            var found = usable(cx, cz)
            if found == nil {
                let rx = floorDiv(cx0, 28), rz = floorDiv(cz0, 28)
                let s32 = UInt32(truncatingIfNeeded: seed)
                for k in 1...8 {
                    let ax = rx * 28 + Int(hashf(rx, rz, 8100 + k, s32) * 19.99), az = rz * 28 + Int(hashf(rx, rz, 8200 + k, s32) * 19.99)
                    if let y = usable(ax, az) { cx = ax; cz = az; found = y; break }
                }
            }
            guard let S = found else { return nil }
            let x = cx * CS + 8, z = cz * CS + 8
            let e = BorealStation.yard + 8
            let piece = Piece(min: IVec3(x - e, S - depth - 4, z - e), max: IVec3(x + e, S + 32, z + e),
                              build: { w in BorealStation.build(&w, x, S, z, seed) })
            return StructureStart(kind: kind, pieces: [piece], anchor: IVec3(x - 5, S + 1, z + yard + 2))
        }
    }

    // Garrison: (mob key, dx, row above the bunker floor or nil for the surface, dz).
    static let garrison: [(String, Int, Int, Int)] = [
        ("soldier_recruit", -3, 1, 4), ("soldier_recruit", 3, 1, -3), ("soldier_marksman", 6, 6, -6),
        ("soldier_trooper", 12, 1, 0), ("soldier_trooper", -12, 1, -6), ("soldier_trooper", 0, 1, 12), ("soldier_recruit", -6, 1, -12),
        ("soldier_trooper", 0, 1, -19), ("soldier_recruit", -3, 1, -21),
        ("soldier_recruit", -21, 1, 0), ("soldier_recruit", 17, 1, 0),
        ("soldier_ironclad", 19, 1, -16), ("soldier_recruit", 17, 1, 21),
        ("soldier_recruit", -16, 1, 15), ("soldier_recruit", -19, 1, -12), ("soldier_trooper", -18, 1, -20),
    ]
    static let surfaceGarrison: [(String, Int, Int, Int)] = [
        ("soldier_recruit", -3, 1, 32), ("soldier_recruit", -7, 1, 32), ("soldier_trooper", 0, 1, 0),
        ("soldier_marksman", -21, 10, 20), ("soldier_recruit", 18, 1, -10),
    ]

    // The surface row S (blockhouse floor) and the bunker floor row F of a generated station; nil until its chunks exist.
    static func levels(_ world: World, _ s: StructureStart) -> (S: Int, F: Int)? {
        let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
        for y in stride(from: CH - 2, to: 1, by: -1) where Blocks.key(world.block(cx - 6, y, cz + 22)) == "bunker_floor" { return (y, y - depth) }
        return nil
    }
    // Camera spots for pictures (golden shots, QuestSim): name, feet position, yaw (forward = (-sin, -cos)), pitch, day time.
    static func views(_ world: World, _ s: StructureStart) -> [(String, V3, Float, Float, Double)] {
        guard let (S, F) = levels(world, s) else { return [] }
        let cx = Float((s.min.x + s.max.x) / 2) + 0.5, cz = Float((s.min.z + s.max.z) / 2) + 0.5
        return [
            ("boreal_station", V3(cx - 4, Float(S + 26), cz + 52), 0.08, -0.42, 0.27),
            ("boreal_gate", V3(cx - 5.5, Float(S + 1), cz + 36), 0, 0.02, 0.3),
            ("boreal_corridor", V3(cx - 12, Float(F + 1), cz + 10), 0, 0, 0.3),
            ("boreal_hall", V3(cx, Float(F + 1), cz + 6.5), 0, 0.12, 0.3),
            ("boreal_stairs", V3(cx - 6, Float(F + 1), cz + 16), -.pi / 2, 0.3, 0.3),
            ("boreal_radar", V3(cx + 10, Float(S + 12), cz - 4), -0.52, 0.42, 0.3),
        ]
    }

    // MARK: Build

    static func build(_ w: inout StructWriter, _ cx: Int, _ S: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        func g(_ n: String, _ f: BlockID = STONE) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let con = g("bunker_concrete"), dark = g("bunker_concrete_dark", con), tile = g("bunker_floor", con)
        let steel = g("steel_plating"), grate = g("steel_grating", steel), hazard = g("hazard_plating", steel)
        let panel = g("light_panel"), console = g("command_console", steel), crate = g("ammo_crate", steel)
        let glass = g("armored_glass", GLASS), bars = g("station_railing", g("iron_bars")), chain = g("chain", g("iron_bars"))
        let lamp = g("corner_lamp", panel), cab = g("data_cabinet", console), door = g("bulkhead_door", g("iron_door"))
        let snowB = SNOW, snowL = g("snow", AIR), wool = g("white_wool"), barrel = g("barrel", crate)
        let conSlabTop = g("bunker_concrete_slab[top]", con), steelSlabTop = g("steel_plating_slab[top]", steel)
        let stairN = g("bunker_concrete_stairs", con)
        let ladder = g("ladder")
        let F = S - depth                       // bunker floor block row
        func X(_ d: Int) -> Int { cx + d }
        func Z(_ d: Int) -> Int { cz + d }
        func put(_ dx: Int, _ y: Int, _ dz: Int, _ b: BlockID) { w.set(cx + dx, y, cz + dz, b) }
        func columns(_ x0: Int, _ x1: Int, _ z0: Int, _ z1: Int, _ body: (Int, Int) -> Void) {
            let xa = max(cx + x0, w.bx), xb = min(cx + x1, w.bx + CS - 1)
            let za = max(cz + z0, w.bz), zb = min(cz + z1, w.bz + CS - 1)
            guard xa <= xb, za <= zb else { return }
            for z in za...zb { for x in xa...xb { body(x - cx, z - cz) } }
        }
        let Y = yard

        // MARK: Site: clear the yard, level it, clean up leaves left hanging round it
        columns(-Y - 2, Y + 2, -Y - 2, Y + 2) { dx, dz in
            let x = cx + dx, z = cz + dz
            w.fill(x, S + 1, z, x, S + 32, z, AIR)
            w.pillarDown(x, S - 1, z, DIRT, minY: S - 30)
            w.set(x, S, z, snowB)
        }
        let ring = Y + 8
        columns(-ring, ring, -ring, ring) { dx, dz in
            guard max(abs(dx), abs(dz)) > Y + 2 else { return }
            let x = cx + dx, z = cz + dz
            for y in (S + 1)...(S + 32) {
                guard CapitalBase.isLeaf(w.get(x, y, z)) else { continue }
                var held = false
                search: for oy in -6...1 { for oz in -3...3 { for ox in -3...3 {
                    let q = (x + ox, y + oy, z + oz)
                    if !w.inside(q.0, q.1, q.2) || CapitalBase.isLog(w.get(q.0, q.1, q.2)) { held = true; break search }
                } } }
                if !held { w.set(x, y, z, AIR) }
            }
        }

        // MARK: Bunker monolith, rooms, surfaces
        columns(-B, B, -B, B) { dx, dz in
            let x = cx + dx, z = cz + dz
            w.pillarDown(x, F - 3, z, STONE, minY: 2)
            for ly in -2...12 {
                let y = F + ly
                let u = open(dx, ly, dz)
                if u != 0 { w.set(x, y, z, AIR); continue }
                let above = open(dx, ly + 1, dz), below = open(dx, ly - 1, dz)
                var b = con
                if above != 0 {
                    b = above == Use.generator.rawValue || above == Use.archive.rawValue ? grate : (above == Use.cells.rawValue ? dark : tile)
                } else if below != 0 {
                    // Ceiling: light panels on the centre line of corridors (every fourth cell) and on a 4-grid in rooms.
                    let interior = open(dx - 1, ly - 1, dz) != 0 && open(dx + 1, ly - 1, dz) != 0 && open(dx, ly - 1, dz - 1) != 0 && open(dx, ly - 1, dz + 1) != 0
                    let corridor = below == Use.corridor.rawValue
                    let onGrid = corridor ? ((dx + dz) % 3 + 3) % 3 == 0 : ((dx % 3 + 3) % 3 == 0 && (dz % 3 + 3) % 3 == 0)
                    b = interior && onGrid ? panel : con
                } else if ly == 1 && (open(dx - 1, 1, dz) != 0 || open(dx + 1, 1, dz) != 0 || open(dx, 1, dz - 1) != 0 || open(dx, 1, dz + 1) != 0) {
                    b = dark                                           // lower wall band
                }
                w.set(x, y, z, b)
            }
            // Blue corner lamps: under the ceiling, on a wall every sixth cell along it and in every room corner.
            for ly in 3...9 {
                let u = open(dx, ly, dz)
                let topRow = open(dx, ly + 1, dz) == 0
                guard u != 0, topRow || (ly == 3 && open(dx, 5, dz) != 0), !isBulkhead(dx, dz) else { continue }
                let walls = [open(dx, ly, dz - 1) == 0, open(dx, ly, dz + 1) == 0, open(dx - 1, ly, dz) == 0, open(dx + 1, ly, dz) == 0]
                let corner = (walls[0] || walls[1]) && (walls[2] || walls[3])
                for (s, wall) in walls.enumerated() where wall {
                    let along = s < 2 ? dx : dz
                    guard corner || ((along % 3) + 3) % 3 == 0 else { continue }
                    // Lens looks away from the wall: wall at -z -> faces south (1), +z -> north (0), -x -> east (3), +x -> west (2).
                    w.set(x, F + ly, z, lamp + BlockID([1, 0, 3, 2][s]))
                    break
                }
            }
        }
        // MARK: Stairwell: bottom landing (bunker), two flights of eight, top landing in the blockhouse
        // Shaft x -6...5, z 16...21 inside walls at x -7 / 6 and z 15 / 22, from the bunker floor up to the surface.
        w.fill(X(-7), F + 1, Z(15), X(6), S, Z(22), con)
        w.fill(X(-6), F + 1, Z(16), X(-5), S - 1, Z(21), AIR)              // west column: bottom landing (and headroom)
        w.fill(X(-4), F + 1, Z(16), X(3), S + 5, Z(17), AIR)               // lane A
        w.fill(X(4), F + 9, Z(16), X(5), S + 5, Z(21), AIR)                // east landing
        w.fill(X(-4), F + 9, Z(20), X(3), S + 5, Z(21), AIR)               // lane B above its fill
        for i in 0..<8 {
            let ax = -4 + i, ay = F + 1 + i
            w.fill(X(ax), F + 1, Z(16), X(ax), ay - 1, Z(17), con)
            w.fill(X(ax), ay, Z(16), X(ax), ay, Z(17), g("bunker_concrete_stairs[east]", con))
            let bx = 3 - i, by = F + 9 + i
            w.fill(X(bx), F + 9, Z(20), X(bx), by - 1, Z(21), con)
            w.fill(X(bx), by, Z(20), X(bx), by, Z(21), g("bunker_concrete_stairs[west]", con))
        }
        put(-4, S, 16, con); put(-4, S, 17, con)                             // floor over the top of lane A
        // Lights down the shaft, blue lamps on the landings.
        for y in stride(from: F + 4, through: S - 2, by: 4) {
            put(-7, y, 18, panel); put(6, y + 2, 18, panel)                   // set into the side walls
            for dx in [-2, 2] { put(dx, y, 18, panel); put(dx, y + 2, 19, panel) }   // the middle wall, both lanes
        }
        for dz in [16, 21] { put(-6, F + 4, dz, lamp + 3); put(-5, S - 2, dz == 16 ? 16 : 21, lamp + BlockID(dz == 16 ? 1 : 0)) }

        // Bulkheads: steel across the passage, a door in the middle, a light panel above it.
        for b in bulkheads {
            for k in -1...1 {
                let (dx, dz) = b.alongZ ? (b.x + k, b.z) : (b.x, b.z + k)
                for ly in 1...4 where k != 0 || ly >= 3 { put(dx, F + ly, dz, ly == 4 && k == 0 ? panel : (ly == 1 ? hazard : steel)) }
            }
            let f: BlockID = b.alongZ ? 0 : 2
            put(b.x, F + 1, b.z, door + f); put(b.x, F + 2, b.z, door + f + 8)
        }

        // MARK: Uplink hall
        // Floor lamps set into the tiles on a 3-grid (the ceiling is too high to light the floor), then the screen
        // wall (north), the core in the middle, a console ring round it.
        for dz in -6...6 { for dx in -6...6 where dx % 3 == 0 && dz % 3 == 0 && max(abs(dx), abs(dz)) > 2 { put(dx, F, dz, panel) } }
        for dx in -5...5 where abs(dx) > 1 { for ly in 2...4 { put(dx, F + ly, -8, console) } }
        for ly in 1...9 { put(0, F + ly, 0, ly == 1 ? hazard : (ly % 3 == 0 ? panel : steel)) }
        for dz in -2...2 { for dx in -2...2 where max(abs(dx), abs(dz)) == 2 && !(dz == 2 && abs(dx) <= 1) { put(dx, F + 1, dz, console) } }
        // Catwalk with a rail, and its stair up the west wall.
        for dz in -7...7 { for dx in -7...7 {
            if catwalk(dx, dz) {
                put(dx, F + 5, dz, tile)                        // station floor plate (the ship grating reads purple from below)
                var edge = false
                for (ox, oz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = dx + ox, nz = dz + oz
                    if abs(nx) <= 7 && abs(nz) <= 7 && !catwalk(nx, nz) && hallStair(nx, nz) == nil { edge = true }
                }
                if edge { put(dx, F + 6, dz, bars) }
            } else if let row = hallStair(dx, dz) {
                for ly in 1..<row { put(dx, F + ly, dz, con) }
                put(dx, F + row, dz, stairN)
                if dx == -6 {                                                  // a parapet with a rail on its open side
                    for ly in 1...row { put(-5, F + ly, dz, con) }
                    put(-5, F + row + 1, dz, bars)
                }
            }
        } }
        for (dx, dz) in [(-4, -7), (4, -7)] { put(dx, F + 6, dz, console) }

        // MARK: Control room (north): screen wall, two rows of desks, the command chest
        for dx in -5...5 { for ly in 2...3 { put(dx, F + ly, -24, console) } }
        for dz in [-20, -18] { for dx in -4...4 where dx != 0 { put(dx, F + 1, dz, console) } }
        w.chest(X(5), F + 1, Z(-23), loot: "steelhold_command", seed: rng.next(), facing: 1)
        w.chest(X(-5), F + 1, Z(-23), loot: "steelhold_supply", seed: rng.next(), facing: 1)

        // MARK: Data archive (west): cabinet rows, two tall
        for dz in -5...5 where dz != 0 {
            for ly in 1...2 {
                put(-23, F + ly, dz, cab + 3)                  // against the west wall, facing east
                put(-19, F + ly, dz, cab + 2); put(-18, F + ly, dz, cab + 3)
            }
        }
        w.chest(X(-16), F + 1, Z(-6), loot: "steelhold_command", seed: rng.next(), facing: 2)

        // MARK: Holding cells (east): a walk along the bars, three cells
        for dz in -6...6 { for ly in 1...4 { put(18, F + ly, dz, ly == 4 ? con : bars) } }
        for dz in [-3, 3] { for dx in 19...23 { for ly in 1...4 { put(dx, F + ly, dz, con) } } }
        for dz in [-5, -1, 1, 5] { put(21, F + 5, dz, panel) }
        for dz in [-4, 0, 4] { put(17, F + 5, dz, panel) }
        for dz in [-5, 0, 5] { put(22, F + 1, dz, steelSlabTop); put(23, F + 3, dz, chain); put(23, F + 2, dz, chain) }

        // MARK: Armory (north-east): crate stacks, weapon chests, guns on the north wall
        for dz in stride(from: -21, through: -11, by: 3) { w.fill(X(22), F + 1, Z(dz), X(23), F + 2, Z(dz + 1), crate) }
        for dz in [-21, -18, -15] { w.chest(X(16), F + 1, Z(dz), loot: "steelhold_armory", seed: rng.next(), facing: 3) }
        for dx in 17...21 where rng.chance(0.75) {
            let rack: [Int] = [Guns.rifle, Guns.rifle, Guns.smg, Guns.smg, Guns.shotgun, Guns.sniper]
            let gun = Guns.all[rack[rng.int(6)]]
            if Items.has(gun.key) { w.frame(X(dx), F + 2, Z(-23), state: 1, item: ItemStack(Items.id(gun.key), 1)) }
        }
        for dx in 17...21 { put(dx, F, -16, hazard) }

        // MARK: Generator hall (south-east): the machine, cable chains, fuel barrels
        w.fill(X(18), F + 1, Z(13), X(21), F + 1, Z(19), hazard)
        w.fill(X(18), F + 2, Z(13), X(21), F + 4, Z(19), steel)
        for dz in stride(from: 14, through: 18, by: 2) { put(18, F + 3, dz, panel); put(21, F + 3, dz, panel) }
        for dx in 19...20 { put(dx, F + 3, 13, panel); put(dx, F + 3, 19, panel) }
        for (dx, dz) in [(18, 13), (21, 13), (18, 19), (21, 19)] { put(dx, F + 5, dz, chain); put(dx, F + 6, dz, chain) }
        for dz in 10...12 { put(23, F + 1, dz, barrel) }
        w.chest(X(16), F + 1, Z(22), loot: "steelhold_supply", seed: rng.next(), facing: 3)

        // MARK: Mess (south-west): two long tables with slab benches, the galley along the south wall
        for tx in [-21, -18] {
            for dz in 11...20 {
                put(tx, F + 1, dz, steelSlabTop)
                put(tx - 1, F + 1, dz, g("bunker_concrete_slab", con)); put(tx + 1, F + 1, dz, g("bunker_concrete_slab", con))
            }
        }
        for dx in (-23)...(-17) { put(dx, F + 1, 23, dx % 2 == 0 ? g("smoker", barrel) : barrel) }
        w.chest(X(-16), F + 1, Z(23), loot: "steelhold_supply", seed: rng.next(), facing: 0)

        // MARK: Barracks (north-west): bunks along both walls, lockers on the north wall
        for dz in stride(from: -22, through: -10, by: 3) {
            for bx in [-23, -17] {
                put(bx, F + 1, dz, wool); put(bx + 1, F + 1, dz, wool)
                put(bx, F + 3, dz, wool); put(bx + 1, F + 3, dz, wool)
                put(bx + (bx < -20 ? 0 : 1), F + 2, dz, steel)
            }
        }
        for dx in (-21)...(-19) { put(dx, F + 1, -23, steel); put(dx, F + 2, -23, steel) }
        w.chest(X(-20), F + 1, Z(-9), loot: "steelhold_supply", seed: rng.next(), facing: 0)

        // MARK: Blockhouse over the stairwell
        let bh0 = -8, bh1 = 7, bz0 = 14, bz1 = 23
        for dz in bz0...bz1 { for dx in bh0...bh1 {
            let wall = dx == bh0 || dx == bh1 || dz == bz0 || dz == bz1
            if wall {
                put(dx, S, dz, con)
                for y in (S + 1)...(S + 5) {
                    let window = y == S + 3 && (dx + dz) % 3 == 0 && !(dz == bz1 && dx >= -7 && dx <= -4)
                    put(dx, y, dz, y == S + 1 ? dark : (window ? glass : con))
                }
            } else if !(dx >= -4 && dx <= 5 && dz >= 16 && dz <= 21) || (dz >= 18 && dz <= 19 && dx <= 3) {
                put(dx, S, dz, tile)
            }
            put(dx, S + 6, dz, wall ? con : ((dx % 3 + 3) % 3 == 0 && (dz % 3 + 3) % 3 == 1 ? panel : con))
        } }
        put(-7 + 1, S + 6, 18, panel)
        // Rails round the shaft openings.
        for y in (S + 1)...(S + 2) {                                        // two high: no jumping onto them
            for dx in -3...5 { for dz in [15, 18, 19, 22] { put(dx, y, dz, bars) } }
            for dz in 16...21 { put(6, y, dz, bars) }
            put(-4, y, 16, bars); put(-4, y, 17, bars)
        }
        // Entrance: a pair of bulkhead doors in the south wall, a canopy, floodlights.
        for dx in [-6, -5] { put(dx, S + 1, bz1, door + 1); put(dx, S + 2, bz1, door + 9) }
        for dx in (-7)...(-4) { put(dx, S + 3, bz1 + 1, conSlabTop) }
        put(-7, S + 4, bz1 + 1, panel); put(-4, S + 4, bz1 + 1, panel)
        for (dx, dz) in [(-7, 16), (6, 21), (-7, 21), (6, 16)] { put(dx, S + 5, dz, lamp + BlockID(dx < 0 ? 3 : 2)) }
        // Antenna mast on the roof.
        for y in (S + 7)...(S + 14) { put(4, y, 20, bars) }
        put(4, S + 15, 20, panel)

        // MARK: Yard: the road, the fence, the gate
        columns(-Y, Y, -Y, Y) { dx, dz in
            let road = dx >= -7 && dx <= -4 && dz > bz1
            let apron = dx >= bh0 - 2 && dx <= bh1 + 2 && dz >= bz0 - 2 && dz <= bz1 + 2 && !(dx >= bh0 && dx <= bh1 && dz >= bz0 && dz <= bz1)
            if road || apron { put(dx, S, dz, con) }
        }
        columns(-Y, Y, -Y, Y) { dx, dz in
            guard max(abs(dx), abs(dz)) == Y else { return }
            if dz == Y && dx >= -8 && dx <= -3 { return }                     // the gate
            let post = (dx + dz) % 5 == 0 || abs(dx) == Y && abs(dz) == Y
            for y in (S + 1)...(S + 3) { put(dx, y, dz, post ? con : bars) }
            if abs(dx) == Y && abs(dz) == Y {
                for y in (S + 4)...(S + 5) { put(dx, y, dz, steel) }
                put(dx, S + 6, dz, panel)
            }
        }
        for dx in [-9, -2] { for y in (S + 1)...(S + 4) { put(dx, y, Y, y == S + 4 ? panel : hazard) } }
        // Gatehouse inside the gate (east of the road): a concrete hut with glass on three sides.
        for dz in (Y - 4)...(Y - 1) { for dx in -1...3 {
            let wall = dx == -1 || dx == 3 || dz == Y - 4 || dz == Y - 1
            for y in (S + 1)...(S + 3) {
                if !wall { put(dx, y, dz, AIR); continue }
                put(dx, y, dz, y == S + 2 && (dx == -1 || dz == Y - 1) && !(dx == -1 && dz == Y - 3) ? glass : con)
            }
            put(dx, S + 4, dz, con)
        } }
        put(-1, S + 1, Y - 3, door + 2); put(-1, S + 2, Y - 3, door + 10)
        put(1, S + 4, Y - 2, panel)

        // MARK: Radar mast with its dish (north-east yard)
        let mx = 18, mz = -18
        for y in (S + 1)...(S + 14) {
            for (ox, oz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] { put(mx + ox, y, mz + oz, steel) }
            if (y - S) % 4 == 0 { for (ox, oz) in [(0, -1), (0, 1), (-1, 0), (1, 0)] { put(mx + ox, y, mz + oz, bars) } }
        }
        for oz in -2...2 { for ox in -2...2 {
            put(mx + ox, S + 15, mz + oz, grate)
            if max(abs(ox), abs(oz)) == 2 { put(mx + ox, S + 16, mz + oz, bars) }
        } }
        for y in (S + 16)...(S + 19) { put(mx, y, mz, steel) }
        // Dish: a bowl of radius 5 tilted to look south and up. The surface is sampled on a fine (u, v) grid over the
        // disc and each sample fills its block, so the bowl is one clean shell with no holes or doubled lumps; the
        // outer ring is steel (the rim), a steel feed arm runs out along the axis.
        do {
            let n = simd_normalize(V3(0, 0.75, 0.66))
            let e1 = V3(1, 0, 0), e2 = simd_normalize(simd_cross(n, e1))
            let white = g("white_concrete", con)
            let c = V3(Float(mx) + 0.5, Float(S + 22) + 0.5, Float(mz) + 0.5)
            var u: Float = -5
            while u <= 5 {
                var v: Float = -5
                while v <= 5 {
                    let r2 = u * u + v * v
                    if r2 <= 25 {
                        let q: V3 = c + u * e1 + v * e2 + (r2 / 30) * n
                        put(Int(floorf(q.x)), Int(floorf(q.y)), Int(floorf(q.z)), r2 >= 20 ? steel : white)
                    }
                    v += 0.25
                }
                u += 0.25
            }
            put(mx, S + 20, mz, steel); put(mx, S + 21, mz, steel)
            for t in 2...4 { let q = c + Float(t) * n; put(Int(floorf(q.x)), Int(floorf(q.y)), Int(floorf(q.z)), steel) }
            let h = c + 5 * n
            put(Int(floorf(h.x)), Int(floorf(h.y)), Int(floorf(h.z)), panel)
        }

        // MARK: Watchtower (south-west corner of the yard)
        let tx = -21, tz = 21
        for y in (S + 1)...(S + 8) {
            put(tx, y, tz, con)
            for (ox, oz) in [(-2, -2), (2, -2), (-2, 2), (2, 2)] { put(tx + ox, y, tz + oz, steel) }
        }
        for y in (S + 1)...(S + 9) { put(tx, y, tz + 1, ladder + 1) }
        for oz in -2...2 { for ox in -2...2 {
            let edge = max(abs(ox), abs(oz)) == 2
            if !(ox == 0 && oz == 1) { put(tx + ox, S + 9, tz + oz, con) }
            for y in (S + 10)...(S + 12) {
                put(tx + ox, y, tz + oz, edge ? (y == S + 11 ? glass : con) : AIR)
            }
            put(tx + ox, S + 13, tz + oz, ox == 0 && oz == 0 ? panel : con)
        } }

        // MARK: Fuel tanks (west yard) and the vehicle shed (east yard)
        for (fx, fz) in [(-22, -14), (-22, -4)] {
            for oz in -3...3 { for ox in -3...3 where ox * ox + oz * oz <= 8 {
                for y in (S + 1)...(S + 5) { put(fx + ox, y, fz + oz, y == S + 3 ? hazard : steel) }
            } }
        }
        for dz in 4...14 { for dx in 14...24 {
            let back = dx == 24 || dz == 4 || dz == 14
            for y in (S + 1)...(S + 4) { put(dx, y, dz, back ? con : AIR) }
            put(dx, S + 5, dz, back ? con : steel)
            if !back { put(dx, S, dz, con) }
        } }
        for dz in stride(from: 6, through: 12, by: 3) { put(23, S + 1, dz, crate); put(23, S + 2, dz, crate); put(22, S + 1, dz, barrel) }
        put(19, S + 4, 9, panel)

        // MARK: Snow: a layer on every open top (the plowed road keeps less), drifts banked against walls
        columns(-Y - 2, Y + 2, -Y - 2, Y + 2) { dx, dz in
            let x = cx + dx, z = cz + dz
            var y = S + 30
            while y > S - 1 && w.get(x, y, z) == AIR { y -= 1 }
            let top = w.get(x, y, z)
            guard Blocks.opaque[Int(top)] && Blocks.fullCollide[Int(top)] else { return }
            if y == S && top == con && hashf(dx, dz, 41, 0xB0E) < 0.7 { return }
            if y == S && top == snowB {
                // A drift against a wall to the north or west (prevailing wind from the south-east).
                let north = w.inside(x, S + 1, z - 1) && Blocks.fullCollide[Int(w.get(x, S + 1, z - 1))] && w.get(x, S + 1, z - 1) != snowB
                let west = w.inside(x - 1, S + 1, z) && Blocks.fullCollide[Int(w.get(x - 1, S + 1, z))] && w.get(x - 1, S + 1, z) != snowB
                if (north || west) && hashf(dx, dz, 43, 0xB0E) < 0.6 { w.set(x, S + 1, z, snowB); y = S + 1 }
            }
            if y + 1 < CH { w.set(x, y + 1, z, snowL) }
        }

        // MARK: Garrison
        for (k, dx, ly, dz) in garrison { w.mob(k, V3(Float(X(dx)) + 0.5, Float(F + ly), Float(Z(dz)) + 0.5)) }
        for (k, dx, ly, dz) in surfaceGarrison { w.mob(k, V3(Float(X(dx)) + 0.5, Float(S + ly), Float(Z(dz)) + 0.5)) }
        w.mob("deck_gun", V3(Float(X(4)) + 0.5, Float(S + 7), Float(Z(16)) + 0.5))
    }
}
