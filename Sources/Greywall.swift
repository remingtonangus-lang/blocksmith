import Foundation
import simd

// The Greywall Command (backlog A1): a military power of its own, apart from the Capital, that holds walled bases in
// the wilds. Grey cast concrete, steel doors, blue corner lamps and red alarm lamps (the Boreal Station kit). Four
// tiers, each larger, rarer, better held and better stocked:
//   outpost           a walled blockhouse: a curtain wall, one corner tower, a two-storey keep (8 troops; P255)
//   garrison          a higher wall, two towers, a gatehouse, a bigger keep with barracks, armoury, mess, comms (14)
//   fortress          a double wall, four towers with deck guns, a two-storey keep with a vault and a command hall,
//                     a motor pool (24)
//   command fortress  the fortress grown again, with a command level dug under the keep: a war room and a second
//                     vault (36)
// Their troops are the soldier mob kinds wearing Greywall colours (Mob.faction = .greywall): they shoot the player on
// sight and fight the Capital's and every other faction's units. Placement: at most one base per 64 x 64-chunk region,
// seven regions in ten, never within 600 blocks of spawn, the bigger tiers only further out. Only on ground no save had
// generated before (structure-guard-greywall.txt), so an explored world never grows half a fortress.
enum Greywall {
    static let kind = "greywall_base"
    static let display = "Greywall Command"
    static let spacing = 64, separation = 16
    static let presence: Float = 0.7
    // P255 (Oct 14 12:05-12:09, "keep the little base as a variant, as long as it's not replacing the big ones"): the big
    // bases (garrison and up) keep their regions; outposts are extra, in a share of the regions that had none.
    static let outpostShare: Float = 0.2
    // P484: blocks between a base's wall and a town's plan (its troops shoot whoever comes in sight, from the town too).
    static let townBerth = 160

    enum Tier: Int, CaseIterable {
        case outpost = 0, garrison, fortress, command
        var name: String { ["Greywall Outpost", "Greywall Garrison", "Greywall Fortress", "Greywall Command Fortress"][rawValue] }
        // P255: an outpost a little bigger (half 14 -> 18, its keep 13 -> 15 wide, walls 5 -> 6) with two floors.
        var half: Int { [18, 22, 30, 38][rawValue] }             // outer wall half-size (outer face)
        var wallH: Int { [6, 7, 9, 10][rawValue] }               // wall height above the yard
        var troops: Int { [8, 14, 24, 36][rawValue] }
        var minDist: Int { [600, 600, 1500, 3000][rawValue] }    // blocks from spawn
        var weight: Float { [0, 0.6, 0.3, 0.1][rawValue] }       // (outposts come in regions of their own: outpostShare)
        var keepX: Int { [7, 8, 11, 13][rawValue] }              // keep half-sizes (outer walls)
        var keepZ: Int { [7, 6, 8, 10][rawValue] }
        var keepC: Int { [-2, -3, -2, -3][rawValue] }            // keep centre (dz)
        var floors: Int { rawValue == 1 ? 1 : 2 }                // (P255: the outpost's keep has an upper floor)
        // P499 (Oct 30 15:06, "where are the bases with the second floors? I haven't seen any of them"): the garrison,
        // the commonest base, was the one tier whose keep had a single floor; on ground no save had before P499 its keep
        // has the outpost's upper floor too (a watch room, the stair at the corridor's west end).
        func floors(upper: Bool) -> Int { upper ? 2 : floors }
        var towers: [(Int, Int)] {                               // corner signs (sx, sz)
            switch self {
            case .outpost: return [(1, -1)]
            case .garrison: return [(1, -1), (-1, -1)]
            default: return [(1, -1), (-1, -1), (1, 1), (-1, 1)]
            }
        }
        var innerWall: Bool { rawValue >= 2 }
        var inner: Int { half - 9 }                              // inner wall half-size (fortress and up)
        var gatehouse: Bool { rawValue >= 1 }
        var bunker: Bool { self == .command }
        var deckGuns: Bool { true }                              // P255: a gun on every tower (was fortress and up)
        // The tier a base's footprint says it is (the start's bounds: half + margin each side).
        static func of(_ s: StructureStart) -> Tier {
            let span = (s.max.x - s.min.x) / 2 - margin
            return Tier.allCases.min(by: { abs($0.half - span) < abs($1.half - span) }) ?? .outpost
        }
    }
    static let margin = 8

    // The tier rolled for a region, capped by how far it lies from spawn (nil: no base there).
    // P255: a big base's region rolls garrison, fortress or command (stepping down by distance, never to an outpost).
    static func tier(roll: Float, dist: Int) -> Tier? {
        var acc: Float = 0
        var t = Tier.garrison
        for c in Tier.allCases where c.weight > 0 { acc += c.weight; if roll < acc { t = c; break }; t = c }
        while dist < t.minDist {
            guard let lower = Tier(rawValue: t.rawValue - 1), lower != .outpost else { return nil }
            t = lower
        }
        return t
    }

    // MARK: Plan (relative to the base centre; y rows above the yard block S)

    struct Room { let x0, z0, x1, z1: Int; let use: String; let door: (Int, Int) }
    // The keep's ground-floor rooms: north and south of a two-wide corridor (rows kc, kc+1).
    static func rooms(_ t: Tier) -> [Room] {
        let kx = t.keepX, kz = t.keepZ, kc = t.keepC
        let n0 = kc - (kz - 1), n1 = kc - 2, s0 = kc + 3, s1 = kc + (kz - 1)
        var r: [Room] = []
        if t.rawValue <= 1 {
            r.append(Room(x0: -(kx - 1), z0: n0, x1: -1, z1: n1, use: "barracks", door: (-1, kc - 1)))
            r.append(Room(x0: 1, z0: n0, x1: kx - 1, z1: n1, use: "armory", door: (1, kc - 1)))
        } else {
            r.append(Room(x0: -(kx - 1), z0: n0, x1: -5, z1: n1, use: "barracks", door: (-5, kc - 1)))
            r.append(Room(x0: -3, z0: n0, x1: 3, z1: n1, use: "armory", door: (0, kc - 1)))
            r.append(Room(x0: 5, z0: n0, x1: kx - 1, z1: n1, use: "vault", door: (5, kc - 1)))
        }
        r.append(Room(x0: -(kx - 1), z0: s0, x1: -3, z1: s1, use: "mess", door: (-3, kc + 2)))
        r.append(Room(x0: 3, z0: s0, x1: kx - 1, z1: s1, use: "comms", door: (3, kc + 2)))
        return r
    }
    static func tower(_ t: Tier, _ sx: Int, _ sz: Int) -> (x: Int, z: Int) { (sx * (t.half - 2), sz * (t.half - 2)) }

    // Where the garrison stands (mob key, dx, row above S, dz), in the order troops are posted: the first t.troops.
    static func posts(_ t: Tier, upper: Bool = false) -> [(String, Int, Int, Int)] {
        let H = t.half, W = t.wallH, kx = t.keepX, kz = t.keepZ, kc = t.keepC
        var p: [(String, Int, Int, Int)] = []
        let rs = rooms(t)
        func room(_ u: String) -> Room? { rs.first { $0.use == u } }
        func mid(_ r: Room) -> (Int, Int) { ((r.x0 + r.x1) / 2, (r.z0 + r.z1 + 1) / 2) }
        // The gate, the keep door, the comms room's officer, a corridor guard, a tower lookout, the barracks.
        p.append(("soldier_recruit", -2, 1, H - 4)); p.append(("soldier_recruit", 2, 1, H - 4))
        p.append(("soldier_trooper", 3, 1, kc + kz + 2))
        if let c = room("comms") { let m = mid(c); p.append(("soldier_officer", m.0, 1, m.1)) }
        p.append(("soldier_trooper", t.floors(upper: upper) > 1 && t.keepX < 10 ? 3 : -3, 1, kc))      // (P255: off the outpost's stair)
        if upper && t == .garrison { p.append(("soldier_trooper", 2, 6, kc - kz + 3)) }               // (P499: the watch room)
        // P503 (Oct 31 16:28:57 in a garrison's keep: "There should be people on the second floor, like a Hannibal troop
        // or something"): a Hannibal heavy holds the watch room with him.
        if upper && t == .garrison { p.append(("soldier_ironclad:heavy", -2, 6, kc - kz + 3)) }
        // P504 (Nov 1 07:38:14, 07:59:47: "There should be a bunch of guys on the second floor of the Greywall station...
        // They should be Hannibal troops or something up here"): a second heavy beside him.
        if upper && t == .garrison { p.append(("soldier_ironclad:heavy", 0, 6, kc - kz + 3)) }
        // P199 (Oct 13: "a guy spawned inside the gun"): the tower lookout stands inside the tower, not on the roof the
        // deck gun takes up.
        if let tw = t.towers.first { let c = tower(t, tw.0, tw.1); p.append(("soldier_marksman", c.x - tw.0, W + 1, c.z - tw.1)) }
        // Garrison and up: the walls, the rooms, the yard.
        p.append(("soldier_marksman", 0, W + 1, -(H - 1)))
        if let b = room("barracks") { let m = mid(b); p.append(("soldier_recruit", m.0, 1, m.1)) }
        if let a = room("armory") { let m = mid(a); p.append(("soldier_trooper", m.0, 1, m.1)) }
        if let m0 = room("mess") { p.append(("soldier_recruit", m0.x1, 1, m0.z1)) }
        p.append(("soldier_marksman", H - 1, W + 1, 0)); p.append(("soldier_marksman", -(H - 1), W + 1, 0))
        p.append(("soldier_trooper", -(kx + 3), 1, kc + kz + 3)); p.append(("soldier_trooper", kx + 3, 1, kc - kz - 2))
        for tw in t.towers.dropFirst() { let c = tower(t, tw.0, tw.1); p.append(("soldier_marksman", c.x - tw.0, W + 1, c.z - tw.1)) }
        // Fortress and up: heavy troops at the gates, the vault's guard, the command hall.
        p.append(("soldier_ironclad", -2, 1, H - 6)); p.append(("soldier_ironclad", 2, 1, H - 6))
        if let v = room("vault") { let m = mid(v); p.append(("soldier_ironclad", m.0, 1, m.1)) }
        p.append(("soldier_officer", 2, 6, kc - kz + 3))
        p.append(("soldier_trooper", -(kx - 3), 6, kc + kz - 2)); p.append(("soldier_trooper", kx - 3, 6, kc + kz - 2))
        p.append(("soldier_recruit", -2, 1, t.inner + 2)); p.append(("soldier_recruit", 2, 1, t.inner + 2))
        p.append(("soldier_trooper", H - 6, 1, -6)); p.append(("soldier_trooper", -(H - 6), 1, 6))
        p.append(("soldier_marksman", H / 2, W + 1, H - 1)); p.append(("soldier_marksman", -(H / 2), W + 1, H - 1))
        p.append(("soldier_recruit", 0, 1, kc + kz + 5)); p.append(("soldier_crew", H - 5, 1, 0))
        // The command fortress: the war room and its vault under the keep, more men on the walls and in the yard.
        p.append(("soldier_officer", kx / 2, -5, kc - kz + 3)); p.append(("soldier_ironclad", -(kx / 2), -5, kc - 2))
        p.append(("soldier_ironclad", kx / 2 + 2, -5, kc + kz - 3)); p.append(("soldier_trooper", 3, -5, kc + 4))
        p.append(("soldier_marksman", H / 2, W + 1, -(H - 1))); p.append(("soldier_marksman", -(H / 2), W + 1, -(H - 1)))
        p.append(("soldier_marksman", H - 1, W + 1, H / 2)); p.append(("soldier_marksman", -(H - 1), W + 1, -(H / 2)))
        p.append(("soldier_trooper", -(H - 6), 1, -(H - 8))); p.append(("soldier_trooper", H - 6, 1, H - 8))
        p.append(("soldier_recruit", -6, 1, kc + kz + 4)); p.append(("soldier_recruit", 6, 1, kc + kz + 4))
        return Array(p.prefix(t.troops))
    }

    // Wall turrets (dx, dz, facing out: 0 north, 1 south, 2 west, 3 east) in merlon gaps (odd along the outer ring):
    // two flanking the gate from the garrison up, the back wall from the fortress, the sides on the command fortress.
    static func turrets(_ t: Tier) -> [(Int, Int, Int)] {
        let H = t.half, q = (H / 2) | 1
        var out: [(Int, Int, Int)] = []
        if t.rawValue >= 1 { out += [(-7, H, 1), (7, H, 1)] }
        if t.rawValue >= 2 { out += [(-q, -H, 0), (q, -H, 0)] }
        if t.rawValue >= 3 { out += [(-H, -q, 2), (H, q, 3)] }
        return out
    }

    // Corridor turrets (T6, fortress and up): one at each end of the keep's ground-floor corridor, under the ceiling,
    // looking down its length: (dx, y, dz, facing). The west end's alarm lamp is on row kc, so the turret takes kc+1;
    // the east end the other way round.
    static func corridorTurrets(_ t: Tier) -> [(Int, Int, Int, Int)] {
        guard t.rawValue >= 2 else { return [] }
        let kx = t.keepX, kc = t.keepC
        return [(-(kx - 1), 4, kc + 1, 3), (kx - 1, 4, kc, 2)]
    }

    // MARK: Placement

    static func type(_ gen: WorldGen) -> StructureType {
        StructureType(name: kind, spacing: spacing, separation: separation, salt: 77310491, reach: 4) { [unowned gen] seed, cx0, cz0 in
            let rx = floorDiv(cx0, spacing), rz = floorDiv(cz0, spacing)
            let s32 = UInt32(truncatingIfNeeded: gen.seed)
            let pres = hashf(rx, rz, 9100, s32)
            guard pres < presence + outpostShare else { return nil }
            let outpostRegion = pres >= presence                              // P255: an outpost of its own
            guard WorldRules.keepP95(gen, WorldRules.greywallKeepP95, rx: rx, rz: rz, salt: 9150,
                                     centre: (rx * spacing + (spacing - separation) / 2, rz * spacing + (spacing - separation) / 2),
                                     reach: (spacing - separation) / 2 + 8) else { return nil }
            let o = Game.spawnOrigin(seed: gen.seed)
            func dist(_ cx: Int, _ cz: Int) -> Int {
                Int(simd_length(V2(Float(cx * CS + 8 - o.0), Float(cz * CS + 8 - o.1))))
            }
            let roll = hashf(rx, rz, 9101, s32)
            func site(_ cx: Int, _ cz: Int, _ t: Tier) -> Int? {
                let x = cx * CS + 8, z = cz * CS + 8
                let c0 = gen.column(x, z)
                guard !c0.biome.isOcean, c0.biome != .river, c0.biome != .frozenRiver else { return nil }
                let y = gen.groundY(x, z)
                guard y > SEA + 2, y + t.wallH + 24 < CH - 2 else { return nil }
                let R = t.half, h = R / 2
                for (dx, dz) in [(-R, -R), (R, -R), (-R, R), (R, R), (0, -R), (0, R), (-R, 0), (R, 0),
                                 (-h, -h), (h, h), (-h, h), (h, -h), (0, h), (0, -h), (h, 0), (-h, 0)] {
                    let c = gen.column(x + dx, z + dz)
                    if abs(c.height - y) > 6 || c.height <= SEA || c.biome.isOcean || c.biome == .river || c.biome == .frozenRiver { return nil }
                }
                return y
            }
            // P69's berth is decided once per region (every candidate inside its reach; verifier, PR #56).
            let span = spacing - separation, apart = WorldRules.p69(gen, rx * spacing + span / 2, rz * spacing + span / 2, reach: span / 2 + 5)
            func crowded(_ cx: Int, _ cz: Int, _ t: Tier) -> Bool {
                guard let sc = gen.structures else { return false }
                let bx = cx * CS + 8, bz = cz * CS + 8
                // P484 (Oct 28 18:19, a garrison's troops shooting into a town: "shouldn't be a Greywall garrison right
                // beside a village like this"): on ground no save had generated before P484, a town is given a wide berth.
                let berth = sc.clear(cx: cx, cz: cz, reach: (t.half + townBerth) / CS + 1, guardSet: sc.legacyP484)
                for k in ["village", "temple", "pillager_outpost", "mansion", "ruined_portal", "trail_ruins", "military_base",
                          "capital_city", "great_ruin", BorealStation.kind] {
                    guard let o = sc.nearest(k, x: bx, z: bz, maxRegions: 1) else { continue }
                    var m = apart && WorldRules.capitalKinds.contains(k) ? t.half + Greywall.margin + WorldRules.capitalApartP69 : t.half + 16   // (P69: the whole box)
                    if berth && k == "village" { m = max(m, t.half + townBerth) }
                    if o.max.x >= bx - m && o.min.x <= bx + m && o.max.z >= bz - m && o.min.z <= bz + m { return true }
                }
                return false
            }
            func usable(_ cx: Int, _ cz: Int) -> (Int, Tier)? {
                guard let t = outpostRegion ? (dist(cx, cz) >= Tier.outpost.minDist ? .outpost : nil) : tier(roll: roll, dist: dist(cx, cz)) else { return nil }
                if let sc = gen.structures, !sc.clear(cx: cx, cz: cz, reach: 4, guardSet: sc.legacyGreywall) { return nil }
                guard let y = site(cx, cz, t), !crowded(cx, cz, t) else { return nil }
                return (y, t)
            }
            var cx = cx0, cz = cz0
            var found = usable(cx, cz)
            if found == nil {
                for k in 1...6 {
                    let ax = rx * spacing + Int(hashf(rx, rz, 9200 + k, s32) * Float(spacing - separation - 1))
                    let az = rz * spacing + Int(hashf(rx, rz, 9300 + k, s32) * Float(spacing - separation - 1))
                    if let f = usable(ax, az) { cx = ax; cz = az; found = f; break }
                }
            }
            guard let (S, t) = found else { return nil }
            let x = cx * CS + 8, z = cz * CS + 8
            let e = t.half + margin
            let bank = WorldRules.p69(gen, cx, cz, reach: 4)          // P91 banks, on ground first generated with them
            let p471 = gen.structures.map { $0.clear(cx: cx, cz: cz, reach: e / CS + 1, guardSet: $0.legacyP471) } ?? true   // (gun rooms)
            let upper = t == .garrison && (gen.structures.map { $0.clear(cx: cx, cz: cz, reach: e / CS + 1, guardSet: $0.legacyP499) } ?? true)
            // T6: a shore base (sea within 40 blocks beyond a wall) mounts coastal guns on its sea walls.
            var shore: [Int] = []
            if t.rawValue >= 1 {
                for (k, d) in [(0, (0, -1)), (1, (0, 1)), (2, (-1, 0)), (3, (1, 0))] {
                    for out in stride(from: t.half + 12, through: t.half + 40, by: 7) {
                        var sea = 0
                        for side in [-8, 0, 8] {
                            let px = x + d.0 * out + (d.0 == 0 ? side : 0), pz = z + d.1 * out + (d.1 == 0 ? side : 0)
                            if gen.column(px, pz).biome.isOcean { sea += 1 }
                        }
                        if sea >= 2 { shore.append(k); break }
                    }
                }
            }
            let piece = Piece(min: IVec3(x - e, S - 12, z - e), max: IVec3(x + e, S + t.wallH + 16, z + e),
                              build: { w in Greywall.build(&w, x, S, z, t, seed, bank: bank, shore: shore, p471: p471, upper: upper) })
            let start = StructureStart(kind: kind, pieces: [piece], anchor: IVec3(x, S + 1, z + t.half + 3))
            // P476/P483 ("I can't see the base if it's been turned into a compression... Include the base in its
            // compression"): the curtain wall, the corner towers and the keep for the far land (LandmarkRender).
            let h = t.half, W = t.wallH
            for (a, b) in [((-h, -h), (h, -h + 1)), ((-h, h - 1), (h, h)), ((-h, -h), (-h + 1, h)), ((h - 1, -h), (h, h))] {
                start.far.append((IVec3(x + a.0, S, z + a.1), IVec3(x + b.0, S + W, z + b.1), .stone))
            }
            for (sx, sz) in t.towers {
                let c = tower(t, sx, sz)
                start.far.append((IVec3(x + c.x - 3, S, z + c.z - 3), IVec3(x + c.x + 3, S + W + 6, z + c.z + 3), .stone))
            }
            start.far.append((IVec3(x - t.keepX, S, z + t.keepC - t.keepZ), IVec3(x + t.keepX, S + W + 4, z + t.keepC + t.keepZ), .stone))
            return start
        }
    }

    // The yard row S of a base, from its plan (the piece starts at S - 12).
    static func yardY(_ s: StructureStart) -> Int { s.min.y + 12 }
    static func centre(_ s: StructureStart) -> (Int, Int) { ((s.min.x + s.max.x) / 2, (s.min.z + s.max.z) / 2) }

    // MARK: Build

    static func build(_ w: inout StructWriter, _ cx: Int, _ S: Int, _ cz: Int, _ t: Tier, _ seed: UInt64, bank: Bool = false, shore: [Int] = [], p471: Bool = false,
                      upper: Bool = false) {
        // (`bank`: ground first generated with the Oct 12 rules: the earth bank, P91, and Greywall's own equipment, P68)
        // (`upper`: a garrison's keep with an upper floor, P499)
        let floors = t.floors(upper: upper)
        var rng = SRng(seed)
        func g(_ n: String, _ f: BlockID = STONE) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let con = g("bunker_concrete"), dark = g("bunker_concrete_dark", con), tile = g("bunker_floor", con)
        let steel = g("steel_plating"), hazard = g("hazard_plating", steel), grate = g("steel_grating", steel)
        let panel = g("light_panel"), console = g("command_console", steel), crate = g("ammo_crate", steel)
        let glass = g("armored_glass", GLASS), rail = g("station_railing", g("iron_bars"))
        let lamp = g("corner_lamp", panel), cab = g("data_cabinet", console), door = g("bulkhead_door", g("iron_door"))
        let alarm = g("alarm_lamp", lamp), alarmPanel = g("alarm_panel", console), mapTable = g("greywall_map_table", console)
        let yardB = g("coarse_dirt", DIRT), path = GRAVEL, wool = g("gray_wool", g("white_wool")), barrel = g("barrel", crate)
        let ladder = g("ladder"), stairsW = g("bunker_concrete_stairs[west]", con)
        let slab = g("bunker_concrete_slab", con), steelSlabTop = g("steel_plating_slab[top]", steel)
        let gold = g("gold_block", steel)
        let term = bank ? g("greywall_terminal", console) : console, rack = bank ? g("greywall_server", cab) : cab
        let tf = bank && Blocks.has("greywall_terminal") ? 1 : 0             // (terminals face like the cabinets; the console doesn't)
        let H = t.half, W = t.wallH, kx = t.keepX, kz = t.keepZ, kc = t.keepC
        func put(_ dx: Int, _ y: Int, _ dz: Int, _ b: BlockID) { w.set(cx + dx, S + y, cz + dz, b) }
        func fill(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ b: BlockID) {
            w.fill(cx + x0, S + y0, cz + z0, cx + x1, S + y1, cz + z1, b)
        }
        func columns(_ x0: Int, _ x1: Int, _ z0: Int, _ z1: Int, _ body: (Int, Int) -> Void) {
            let xa = max(cx + x0, w.bx), xb = min(cx + x1, w.bx + CS - 1)
            let za = max(cz + z0, w.bz), zb = min(cz + z1, w.bz + CS - 1)
            guard xa <= xb, za <= zb else { return }
            for z in za...zb { for x in xa...xb { body(x - cx, z - cz) } }
        }
        // A bulkhead door in a wall: f 0 for a wall along x (the passage runs along z), 2 for a wall along z.
        func doorAt(_ dx: Int, _ y: Int, _ dz: Int, _ f: BlockID) { put(dx, y, dz, door + f); put(dx, y + 1, dz, door + f + 8) }
        // A lamp on a wall facing away from it: the wall's side (0 -z, 1 +z, 2 -x, 3 +x) -> facing.
        func wallLamp(_ b: BlockID, _ dx: Int, _ y: Int, _ dz: Int, wall s: Int) { put(dx, y, dz, b + BlockID([1, 0, 3, 2][s])) }

        // MARK: Site: clear, level, tidy the trees round it
        let E = H + 2
        columns(-E, E, -E, E) { dx, dz in
            let x = cx + dx, z = cz + dz
            w.fill(x, S + 1, z, x, S + W + 16, z, AIR)
            w.groundDown(x, S - 1, z, DIRT, minY: S - 30, reach: 30)     // P289: a plug over a cave, no dirt pillars
            w.set(x, S, z, yardB)
        }
        let ring = H + margin
        columns(-ring, ring, -ring, ring) { dx, dz in
            guard max(abs(dx), abs(dz)) > E else { return }
            let x = cx + dx, z = cz + dz
            for y in (S + 1)...(S + W + 16) {
                guard CapitalBase.isLeaf(w.get(x, y, z)) else { continue }
                var held = false
                search: for oy in -6...1 { for oz in -3...3 { for ox in -3...3 {
                    let q = (x + ox, y + oy, z + oz)
                    if !w.inside(q.0, q.1, q.2) || CapitalBase.isLog(w.get(q.0, q.1, q.2)) { held = true; break search }
                } } }
                if !held { w.set(x, y, z, AIR) }
            }
        }
        if bank { w.berm(cx, cz, half: E, floor: S, reach: 6) }          // P91: banked into the land round it
        // A gravel road from the gate to the keep door (and on out a little).
        columns(-1, 1, kc + kz + 1, E) { dx, dz in w.set(cx + dx, S, cz + dz, path) }
        // Outside the gate the road climbs or drops to the ground one block a step (the site allows six either way), cut
        // into a hill or banked up over a hollow, so the gate is always walkable from the land around.
        columns(-2, 2, E + 1, ring) { dx, dz in
            let x = cx + dx, z = cz + dz
            guard w.inside(x, S, z) else { return }
            var top = S - 12
            for y in stride(from: S + 14, through: S - 12, by: -1) where Blocks.collide[Int(w.get(x, y, z))] && !CapitalBase.isLeaf(w.get(x, y, z)) {
                top = y; break
            }
            let k = dz - E
            let h = S + max(-k, min(k, top - S))
            w.fill(x, h + 1, z, x, S + 16, z, AIR)
            w.groundDown(x, h - 1, z, DIRT, minY: h - 14)
            w.set(x, h, z, abs(dx) <= 1 ? path : DIRT)
        }

        // MARK: Curtain walls: two thick, crenellated, a walkway on the inner ring
        func curtain(_ R: Int, _ h: Int, merlons: Bool) {
            columns(-R, R, -R, R) { dx, dz in
                let m = max(abs(dx), abs(dz))
                guard m >= R - 1 else { return }
                let gate = dz > 0 && abs(dx) <= 1 && abs(dz) >= R - 1
                for y in 1...h where !(gate && y <= 4) { put(dx, y, dz, y == 1 ? dark : con) }
                if merlons && m == R {
                    let along = abs(dz) == R ? dx : dz
                    if (along % 2 + 2) % 2 == 0 { put(dx, h + 1, dz, con) }
                }
            }
        }
        curtain(H, W, merlons: true)
        if t.innerWall { curtain(t.inner, W - 3, merlons: true) }
        // Red alarm lamps along the inner face of the curtain wall, every twelve blocks, under the walkway lip.
        for k in stride(from: -(H - 6), through: H - 6, by: 12) {
            wallLamp(alarm, k, W - 1, -(H - 2), wall: 0)
            wallLamp(alarm, -(H - 2), W - 1, k, wall: 2); wallLamp(alarm, H - 2, W - 1, k, wall: 3)
            if abs(k) > 3 { wallLamp(alarm, k, W - 1, H - 2, wall: 1) }
        }

        // MARK: Gatehouse: two buttresses flanking the gate, a lamp over it
        if t.gatehouse {
            for sx in [-1, 1] {
                for dx in 2...4 { for dz in H...(H + 1) { for y in 1...(W + 3) { put(sx * dx, y, dz, y == 1 ? dark : con) } } }
                put(sx * 3, W + 4, H + 1, panel)
                wallLamp(alarm, sx * 2, 4, H - 2, wall: 1)
            }
        }
        wallLamp(lamp, 0, 5, H - 2, wall: 1)

        // MARK: Towers on the corners: a ladder to the walkway level and the roof, a parapet
        for (sx, sz) in t.towers {
            let c = tower(t, sx, sz)
            let R = W + 5                                            // roof row
            for oz in -3...3 { for ox in -3...3 {
                let edge = max(abs(ox), abs(oz)) == 3
                for y in 1...R {
                    if edge {
                        let slit = y == W + 2 && (ox == 0 || oz == 0)
                        put(c.x + ox, y, c.z + oz, y == 1 ? dark : (slit ? glass : con))
                    } else {
                        put(c.x + ox, y, c.z + oz, y == W || y == R ? ((ox == 0 && oz == 0) ? panel : con) : AIR)
                    }
                }
                put(c.x + ox, 0, c.z + oz, tile)
                if edge && ((ox + oz) % 2 + 2) % 2 == 0 { put(c.x + ox, R + 1, c.z + oz, con) }
            } }
            // The ladder in the outer corner, through both floors.
            let lx = c.x + 2 * sx, lz = c.z + 2 * sz
            for y in 1...R { put(lx, y, lz, ladder + BlockID(sx > 0 ? 2 : 3)) }
            // Doors: the yard at the foot, the walkway on both walls.
            doorAt(c.x - 3 * sx, 1, c.z - sz, 2)
            for y in (W + 1)...(W + 2) { put(c.x - 3 * sx, y, c.z + sz, AIR); put(c.x + sx, y, c.z - 3 * sz, AIR) }
            wallLamp(alarmPanel, c.x - 2 * sx, 2, c.z + 2 * sz, wall: sz > 0 ? 1 : 0)
            wallLamp(alarm, c.x, R - 1, c.z + 4 * sz, wall: sz < 0 ? 1 : 0)
            if t.deckGuns { w.mob("deck_gun:light@grey", V3(Float(cx + c.x) + 0.5, Float(S + R + 1), Float(cz + c.z) + 0.5)) }   // (P210)
            // P471 (Oct 26 19:53, at a tower's foot: "this should be a computer room right here. There should be a guy in
            // here, and you should have to get in the chair and operate the computer in order to control the gun"): on
            // ground no save had before, a gunned tower's foot is its gun room: a terminal and two server racks on the outer
            // wall, a chair at the terminal and the operator in it, who works the gun on the roof (Mob.makeGunOperator,
            // Game.stationGunUse).
            let gunned = t.deckGuns || shore.contains { k in (k == 0 && sz < 0) || (k == 1 && sz > 0) || (k == 2 && sx < 0) || (k == 3 && sx > 0) }
            if p471 && gunned {
                let face = BlockID(sx > 0 ? 2 : 3)                  // (the screens toward the room)
                put(c.x + 2 * sx, 1, c.z, term + (tf == 1 ? face : 0))
                for oz in [-sz, -2 * sz] { put(c.x + 2 * sx, 1, c.z + oz, rack + face) }
                put(c.x + sx, 1, c.z, g(sx > 0 ? "oak_chair[east]" : "oak_chair[west]", AIR))
                w.mob("soldier_trooper:operator@grey\(leashTag(cx, cz, t))^\(sx > 0 ? 90 : -90)",
                      V3(Float(cx + c.x + sx) + 0.5, Float(S + 1), Float(cz + c.z) + 0.5))
            }
        }

        // MARK: Keep
        let floorsH = 5 * floors
        let kz0 = kc - kz, kz1 = kc + kz
        columns(-kx, kx, kz0, kz1) { dx, dz in
            let x = cx + dx, z = cz + dz
            let edge = abs(dx) == kx || dz == kz0 || dz == kz1
            w.set(x, S, z, edge ? con : tile)
            for y in 1...floorsH {
                if edge {
                    let window = (y == 2 || y == 3 || y == 7 || y == 8) && ((dx + dz) % 3 + 3) % 3 == 0 && abs(dx) < kx - 1 && dz > kz0 + 1 && dz < kz1 - 1
                        || (y == 2 || y == 3 || y == 7 || y == 8) && abs(dx) == kx && ((dz - kc) % 3 + 3) % 3 == 0 && dz > kz0 + 1 && dz < kz1 - 1
                    w.set(x, S + y, z, y == 1 || y == 6 ? dark : (window ? glass : con))
                } else if y % 5 == 0 {
                    // Ceiling / upper floor: light panels on a 3-grid.
                    let lit = (dx % 3 + 3) % 3 == 0 && ((dz - kc) % 3 + 3) % 3 == 1
                    w.set(x, S + y, z, lit ? panel : (y == 5 && floors > 1 ? tile : con))
                } else {
                    w.set(x, S + y, z, AIR)
                }
            }
            w.set(x, S + floorsH, z, edge ? con : w.get(x, S + floorsH, z))
            if edge && ((dx + dz) % 2 + 2) % 2 == 0 { w.set(x, S + floorsH + 1, z, con) }
        }
        // Ground-floor partitions: the corridor walls (rows kc-1, kc+2), the entrance passage, the room walls.
        let rs = rooms(t)
        for dx in -(kx - 1)...(kx - 1) {
            for y in 1...4 { put(dx, y, kc - 1, y == 1 ? dark : con) }
            if abs(dx) >= 2 { for y in 1...4 { put(dx, y, kc + 2, y == 1 ? dark : con) } }
        }
        for dz in (kc + 2)...(kc + kz - 1) { for y in 1...4 { put(-2, y, dz, y == 1 ? dark : con); put(2, y, dz, y == 1 ? dark : con) } }
        let northWalls = t.rawValue <= 1 ? [0] : [-4, 4]
        for x in northWalls { for dz in (kc - kz + 1)...(kc - 2) { for y in 1...4 { put(x, y, dz, y == 1 ? dark : con) } } }
        for r in rs { doorAt(r.door.0, 1, r.door.1, 0) }
        doorAt(0, 1, kz1, 0)
        for y in 1...2 { put(-1, y, kz1, con); put(1, y, kz1, con) }
        put(0, 3, kz1 + 1, lamp + 1)
        wallLamp(alarm, -2, 4, kz1 + 1, wall: 0); wallLamp(alarm, 2, 4, kz1 + 1, wall: 0)
        // D35: security cameras over the entrance and down the corridor (BaseSecurity.swift).
        if Blocks.has(BaseSecurity.camera) {
            let cam = Blocks.id(BaseSecurity.camera)
            wallLamp(cam, -4, 4, kz1 + 1, wall: 0); wallLamp(cam, 4, 4, kz1 + 1, wall: 0)
            wallLamp(cam, kx - 1, 3, kc, wall: 3)
        }
        // The corridor: an alarm panel by the entrance, red lamps at both ends, blue lamps along it.
        wallLamp(alarmPanel, -4, 2, kc + 1, wall: 1)
        wallLamp(alarm, -(kx - 1), 4, kc, wall: 2); wallLamp(alarm, kx - 1, 4, kc + 1, wall: 3)
        for dx in stride(from: -(kx - 3), through: kx - 3, by: 4) where abs(dx) > 1 { wallLamp(lamp, dx, 4, kc, wall: 0) }

        // Rooms.
        for r in rs {
            switch r.use {
            case "barracks":
                for x in stride(from: r.x0, through: r.x1 - 1, by: 3) {
                    put(x, 1, r.z0, wool); put(x + 1, 1, r.z0, wool); put(x, 3, r.z0, wool); put(x + 1, 3, r.z0, wool)
                    put(x, 2, r.z0, steel)
                }
                w.chest(cx + r.x0, S + 1, cz + r.z1, loot: "greywall_supply", seed: rng.next(), facing: 3)
            case "armory":
                for x in stride(from: r.x0, through: r.x1, by: 2) where x != r.door.0 {
                    w.chest(cx + x, S + 1, cz + r.z0, loot: "greywall_armory", seed: rng.next(), facing: 1)
                    put(x, 2, r.z0, crate)
                    if t.rawValue == 0 { break }
                }
                put(r.x1, 1, r.z1 == r.z0 ? r.z0 : r.z0 + 1, crate)
            case "vault":
                for dz in r.z0...r.z1 { for dx in r.x0...r.x1 { put(dx, 0, dz, steel) } }
                for x in [r.x0, r.x1] { for dz in r.z0...r.z1 { for y in 1...4 { put(x == r.x0 ? x - 1 : x + 1, y, dz, steel) } } }
                w.chest(cx + r.x1, S + 1, cz + r.z0, loot: "greywall_vault", seed: rng.next(), facing: 1)
                w.chest(cx + r.x1 - 2, S + 1, cz + r.z0, loot: "greywall_vault", seed: rng.next(), facing: 1)
                put(r.x1, 1, r.z1, gold); put(r.x1 - 1, 1, r.z1, gold)
                wallLamp(alarm, r.x0, 4, r.z0, wall: 0)
            case "mess":
                let tz = (r.z0 + r.z1) / 2
                for dx in (r.x0 + 1)...max(r.x0 + 1, r.x1 - 1) where r.z1 > r.z0 {
                    put(dx, 1, tz, steelSlabTop)
                    if tz + 1 <= r.z1 { put(dx, 1, tz + 1, slab) }
                }
                w.sundryBarrel(cx + r.x0, S + 1, cz + r.z1, seed: seed)                   // P133
                w.chest(cx + r.x0, S + 1, cz + r.z0, loot: "greywall_supply", seed: rng.next(), facing: 3)
            case "comms":
                // The map table in the middle, consoles and data cabinets on the back wall, the command chest.
                let m = ((r.x0 + r.x1) / 2, (r.z0 + r.z1 + 1) / 2)          // the officer's spot (posts)
                for dx in r.x0...r.x1 where dx != m.0 && dx != r.door.0 { put(dx, 1, r.z1, dx % 2 == 0 || dx == r.x1 ? term : rack + 0) }   // (always a console at the east end: an outpost's room has one cell to spare)
                put(m.0 + 1, 1, m.1, mapTable)
                w.chest(cx + r.x1, S + 1, cz + r.z0, loot: t.rawValue >= 1 ? "greywall_charge" : "greywall_armory", seed: rng.next(), facing: 2)   // (P504: its one charge)
                wallLamp(alarmPanel, r.x0, 2, r.z1, wall: 1)
            default: break
            }
        }
        // P476 (Remington, Oct 29 13:33: "obsidian grade armour is whatever would make it annoying to get through a wall
        // instead of just finding the keycard"): the vault and the comms room behind their locked doors are walled,
        // floored and roofed in armour (Armour); the ceiling lights and the doors stay. P501 (Oct 31, "the armor on the
        // base is still here. Get rid of that"): in the keep's own blocks, their armoured twins (Armour.twin), not a
        // dark plate of their own.
        do {
            for r in rs where r.use == "vault" || r.use == "comms" {
                for dz in (r.z0 - 1)...(r.z1 + 1) { for dx in (r.x0 - 1)...(r.x1 + 1) { for y in 0...5 {
                    if dx >= r.x0 && dx <= r.x1 && dz >= r.z0 && dz <= r.z1 && y >= 1 && y <= 4 { continue }
                    let at = w.get(cx + dx, S + y, cz + dz)
                    if at == AIR || Blocks.emit[Int(at)] > 0 || Blocks.key(Blocks.groupBase[Int(at)]).hasSuffix("door") { continue }
                    put(dx, y, dz, Armour.twin(at))
                } } }
            }
        }

        // MARK: Upper floor (fortress and up, and the outpost: P255): up a stair at the corridor's west end
        if floors > 1 {
            // (The outpost's keep is narrow: its mess is under the stair's whole run, so a two-wide stair walled its door
            // off. There the stair takes the corridor's north row only and the south row walks on to the mess door.)
            let narrow = rs.contains { $0.use == "mess" && $0.door.0 > -(kx - 1) && $0.door.0 <= -(kx - 1) + 4 }
            let rows = narrow ? kc...kc : kc...(kc + 1)
            for k in 1...4 {
                let dx = -(kx - 1) + k
                for dz in rows {
                    if k < 4 { fill(dx, 1, dz, dx, 4 - k, dz, con) }
                    put(dx, 5 - k, dz, stairsW)
                    put(dx, 5, dz, AIR)
                }
            }
            for dz in rows { fill(-(kx - 1), 1, dz, -(kx - 1), 5, dz, con) }
            // A rail round the stairwell on the upper floor (two high on the open side).
            for k in 1...5 { put(-(kx - 1) + k, 6, kc - 1, rail); put(-(kx - 1) + k, 6, rows.upperBound + 1, rail) }
            for dz in rows { put(-(kx - 1) + 5, 6, dz, rail) }
            let nz = kz0 + 1
            if t.rawValue >= 2 {
                // Command hall: the command console and map table at the north wall, officers' bunks, the command chests.
                for dx in -3...3 { put(dx, 6, nz, dx == 0 ? term + BlockID(tf) : rack + 1) }
                put(0, 6, nz + 2, mapTable)
                w.chest(cx + 5, S + 6, cz + nz, loot: "greywall_command", seed: rng.next(), facing: 1)
                w.chest(cx - 5, S + 6, cz + nz, loot: "greywall_command", seed: rng.next(), facing: 1)
            } else {
                // P255: the outpost's upper floor: a watch room with a radio console and racks at the north wall, a
                // supply chest, a store barrel and the sentries' bunks.
                for dx in -2...2 { put(dx, 6, nz, dx == 0 ? term + BlockID(tf) : rack + 1) }
                w.chest(cx + 4, S + 6, cz + nz, loot: "greywall_supply", seed: rng.next(), facing: 1)
                w.materials(cx - 3, S + 6, cz + nz, seed: seed)
            }
            for x in stride(from: kx - 5, through: kx - 2, by: 3) {
                put(x, 6, kz1 - 1, wool); put(x + 1, 6, kz1 - 1, wool)
            }
            wallLamp(alarmPanel, kx - 1, 7, kc, wall: 3)
            wallLamp(alarm, 0, 9, kz1 - 1, wall: 1)
            for dx in stride(from: -(kx - 3), through: kx - 3, by: 4) { wallLamp(lamp, dx, 9, nz, wall: 0) }
        }

        // MARK: Command level (the command fortress): a war room and a vault dug under the keep, down a stair at the
        // corridor's east end.
        if t.bunker {
            columns(-kx, kx, kz0, kz1) { dx, dz in
                let x = cx + dx, z = cz + dz
                let edge = abs(dx) == kx || dz == kz0 || dz == kz1
                w.set(x, S - 7, z, con)
                w.set(x, S - 6, z, edge ? con : tile)
                for y in (S - 5)...(S - 2) { w.set(x, y, z, edge ? (y == S - 5 ? dark : con) : AIR) }
                let lit = !edge && (dx % 3 + 3) % 3 == 0 && ((dz - kc) % 3 + 3) % 3 == 1
                w.set(x, S - 1, z, lit ? panel : con)
            }
            // The stair: five steps down eastward from the ground floor, the landing at the east wall.
            // (Each step's top is one lower than the last; the shaft is open above it through the ground floor.)
            for j in 0...4 {
                let dx = kx - 6 + j
                for dz in kc...(kc + 1) {
                    for y in (-j)...0 { put(dx, y, dz, AIR) }
                    put(dx, -1 - j, dz, stairsW)
                }
            }
            // The partition: war room east, vault west, a door between.
            for dz in (kz0 + 1)...(kz1 - 1) { for y in -5...(-2) { put(0, y, dz, y == -5 ? dark : steel) } }
            doorAt(0, -5, kc - 3, 2)
            // War room: the war table, consoles round the north wall, the command chest, alarm panel.
            put(kx / 2, -5, kc - 1, mapTable)
            for dx in 2...(kx - 1) { put(dx, -5, kz0 + 1, dx % 2 == 0 ? term + BlockID(tf) : rack + 1) }
            w.chest(cx + kx - 1, S - 5, cz + kz1 - 1, loot: "greywall_command", seed: rng.next(), facing: 0)
            let safeSeed = seed ^ UInt64(bitPattern: Int64(cx &* 73856093 ^ cz &* 19349663))
            w.safeKey(cx + kx - 1, S - 5, cz + kz1 - 1, baseSeed: safeSeed)          // P248: the vault safe's key
            wallLamp(alarmPanel, 1, -4, kz1 - 1, wall: 1)
            wallLamp(alarm, kx - 1, -2, kz0 + 1, wall: 0)
            // Vault: steel floor, gold, two vault chests.
            for dz in (kz0 + 1)...(kz1 - 1) { for dx in -(kx - 1)...(-1) { put(dx, -6, dz, steel) } }
            for dz in [kz0 + 1, kz1 - 1] {
                w.chest(cx - (kx - 1), S - 5, cz + dz, loot: "greywall_vault", seed: rng.next(), facing: 3)
                put(-(kx - 1), -5, dz + (dz == kz0 + 1 ? 1 : -1), gold)
            }
            w.safe(cx - (kx - 1), S - 5, cz + kc, seed: safeSeed &+ 1, facing: 3, grey: true)          // P248 (BaseSafes.swift)
            wallLamp(alarm, -(kx - 1), -2, kc, wall: 2)
        }

        // MARK: Wall turrets (garrison and up) in merlon gaps on the outer ring, facing out; the flag on the keep roof
        let turret = g("wall_turret", con)
        for (dx, dz, f) in turrets(t) { put(dx, W + 1, dz, turret + BlockID(f)) }
        for (dx, y, dz, f) in corridorTurrets(t) { put(dx, y, dz, turret + BlockID(f)) }
        // Coastal guns (T6) on each sea wall: two light quick-firers on the walkway, looking out to sea, and where the
        // towers carry no deck guns, a heavy gun on each tower roof of that side.
        // P458 (Oct 25 16:22, on a Greywall wall: "There shouldn't be whole ass naval guns on the side of the base...
        // someone has to be inside the naval gun... someone on a computer underneath the gun in a room underneath the
        // gun"): the towers' guns have their gun rooms and operators (P471); on ground no save had before, the walkway's
        // two are wall turrets looking out to sea, like the other walls' (no crewed gun with nobody in it).
        let headings = [0, -180, -90, 90]
        let walls = Set(turrets(t).map { IVec3($0.0, 0, $0.1) })
        for k in shore {
            for along in [-(H / 3), H / 3] {
                let (dx, dz) = k == 0 ? (along, -(H - 1)) : k == 1 ? (along, H - 1) : k == 2 ? (-(H - 1), along) : (H - 1, along)
                if k == 1 && abs(dx) <= 4 { continue }               // (never over the gate)
                if p471 {
                    let (tx, tz) = k == 0 ? (along, -H) : k == 1 ? (along, H) : k == 2 ? (-H, along) : (H, along)
                    if !walls.contains(IVec3(tx, 0, tz)) { put(tx, W + 1, tz, turret + BlockID(k)) }
                    continue
                }
                w.mob("deck_gun:light@grey^\(headings[k])", V3(Float(cx + dx) + 0.5, Float(S + W + 1), Float(cz + dz) + 0.5))
            }
            if !t.deckGuns {
                for (sx, sz) in t.towers where (k == 0 && sz < 0) || (k == 1 && sz > 0) || (k == 2 && sx < 0) || (k == 3 && sx > 0) {
                    let c = tower(t, sx, sz)
                    w.mob("deck_gun:light@grey^\(headings[k])", V3(Float(cx + c.x) + 0.5, Float(S + W + 6), Float(cz + c.z) + 0.5))   // (P210)
                }
            }
        }
        // P252: a flak gun on the keep roof (garrison and up) at its west end, facing out.
        if t.rawValue >= 1 {
            w.mob("deck_gun:flak@grey^-90", V3(Float(cx - (kx - 3)) + 0.5, Float(S + floorsH + 1), Float(cz + kc) + 0.5))
        }
        let flag = g("greywall_flag", wool)
        let fx = kx - 1, fz = kz0 + 1
        for y in (floorsH + 1)...(floorsH + 6) { put(fx, y, fz, rail) }
        for y in (floorsH + 5)...(floorsH + 6) { for dx in 1...2 { put(fx - dx, y, fz, flag) } }

        // MARK: Yard: a motor pool (fortress and up) against the east wall, crates and barrels, floodlights
        if t.innerWall {
            let x0 = t.inner + 2, x1 = H - 3
            for dz in -7...7 { for dx in x0...x1 {
                put(dx, 0, dz, hazard)
                let post = (dx == x0 || dx == x1) && (dz == -7 || dz == 7 || dz == 0)
                for y in 1...4 { put(dx, y, dz, post ? steel : AIR) }
                put(dx, 5, dz, (dx + dz) % 4 == 0 ? panel : grate)
            } }
            for dz in stride(from: -5, through: 5, by: 5) {
                put(x1, 1, dz, crate); put(x1, 2, dz, crate); w.sundryBarrel(cx + x1 - 1, S + 1, cz + dz, seed: seed)
                w.materials(cx + x1, S + 1, cz + dz + 1, seed: seed)                                   // P254: a store barrel
            }
        }
        for (sx, sz) in [(-1, -1), (1, 1)] {
            let x = sx * (H - 4), z = sz * (H - 5)
            if t.towers.contains(where: { $0.0 == sx && $0.1 == sz }) { continue }
            put(x, 1, z, crate); w.sundryBarrel(cx + x + sx, S + 1, cz + z, seed: seed); put(x, 2, z, crate)
            w.materials(cx + x, S + 1, cz + z - sz, seed: seed)                                        // P254: a store barrel
        }
        for k in [-(H / 2), H / 2] { put(k, 1, H - 3, steel); put(k, 2, H - 3, steel); put(k, 3, H - 3, panel) }

        // MARK: Garrison
        let tag = leashTag(cx, cz, t)
        for (k, dx, y, dz) in posts(t, upper: upper) { w.mob("\(k)@grey\(tag)", V3(Float(cx + dx) + 0.5, Float(S + y), Float(cz + dz) + 0.5)) }
    }

    // MARK: Loot

    static let loot: [String: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)])] = [
        "greywall_supply": (4...8, [("capital_ration", 2, 6, 14), ("bread", 2, 6, 15), ("cooked_beef", 2, 5, 10), ("iron_ingot", 2, 6, 10),
                                    ("gunpowder", 2, 8, 10), ("greywall_rounds", 8, 32, 14), ("coal", 4, 12, 8), ("compass", 1, 1, 2),
                                    ("map", 1, 1, 2), ("field_stim", 1, 1, 2), ("greywall_field_notes", 1, 1, 6)]),
        "greywall_armory": (3...6, [("gun_slatefall", 1, 1, 12), ("gun_repeater", 1, 1, 5),
                                    ("greywall_rounds", 16, 48, 22), ("heavy_rounds", 4, 12, 8),
                                    ("iron_chestplate", 1, 1, 4), ("iron_helmet", 1, 1, 4), ("shield", 1, 1, 3), ("firing_mechanism", 1, 2, 6)]),
        // P256: no Capital guns or rounds in Greywall's chests (the Fernblick, launcher and arc gun were the Capital's).
        "greywall_command": (4...7, [("diamond", 2, 6, 8), ("emerald", 3, 8, 6), ("gun_kessel", 1, 1, 6), ("gun_repeater", 1, 1, 5),
                                     ("greywall_rounds", 16, 40, 6), ("heavy_rounds", 6, 15, 8), ("field_stim", 1, 2, 5),
                                     ("experience_bottle", 3, 8, 6), ("targeting_optic", 1, 1, 5), ("radar_module", 1, 1, 4),
                                     ("diamond_chestplate@20-30", 1, 1, 3), ("greywall_field_notes", 1, 1, 6)]),
        "greywall_vault": (5...9, [("diamond", 3, 8, 10), ("gold_ingot", 6, 16, 10), ("emerald", 4, 12, 8), ("gun_repeater", 1, 1, 6),
                                   ("gun_slatefall", 1, 1, 6), ("greywall_rounds", 24, 64, 8), ("heavy_rounds", 8, 16, 8), ("netherite_scrap", 1, 2, 3),
                                   ("diamond_sword@25-35", 1, 1, 3), ("combat_stim", 1, 1, 2), ("radar_module", 1, 1, 5)]),
    ]
}

// MARK: Faction troops

extension Mob {
    // A Greywall soldier (structure mob key suffix "@grey"): its colours, its ranks' names (crewNames), its faction.
    func greySetup() {
        faction = Faction.greywall.rawValue
        persistent = true
    }
}

// MARK: Blocks and textures

extension BlockRegistry {
    func registerGreywallBlocks() {
        // Alarm lamp: a red caged lamp on a wall; dark while the base is quiet, lit (alarm_lamp_lit) when it is alerted.
        let cage: [Box] = [Box(5, 9, 12, 11, 15, 16), Box(5, 9, 0, 11, 15, 4), Box(12, 9, 5, 16, 15, 11), Box(0, 9, 5, 4, 15, 11)]
        for lit in [false, true] {
            let n = lit ? "alarm_lamp_lit" : "alarm_lamp"
            guard !has(n) else { continue }
            var d = BlockDef(n, lit ? "Alarm Lamp (lit)" : "Alarm Lamp")
            d.tex = [lit ? "alarm_lamp_lit_side" : "alarm_lamp_side"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = false
            d.collide = false; d.noCollideBoxes = true; d.hardness = 1; d.sound = .glass; d.emit = lit ? 10 : 2
            d.hidden = lit
            addFacing(d, front: lit ? "alarm_lamp_lit" : "alarm_lamp", boxesFor: { k in [cage[k]] })
        }
        // Alarm panel: a wall box with a big red button; a base with every panel down can't call for help (A1b).
        if !has("alarm_panel") {
            var d = BlockDef("alarm_panel", "Alarm Panel")
            d.tex = ["alarm_panel_side"]; d.hardness = 2; d.resistance = 6; d.tool = .pickaxe; d.sound = .stone; d.emit = 3
            addFacing(d, front: "alarm_panel")
        }
        // Wall turret: a squat steel mount with a gun head; shot up it goes damaged (sparking, slower) then a wreck.
        let base = Box(3, 0, 3, 13, 5, 13), head = Box(4, 5, 4, 12, 11, 12)
        let barrels = [Box(7, 7, 0, 9, 9, 4), Box(7, 7, 12, 9, 9, 16), Box(0, 7, 7, 4, 9, 9), Box(12, 7, 7, 16, 9, 9)]
        for (n, label, k) in [("wall_turret", "Wall Turret", 0), ("wall_turret_damaged", "Wall Turret (damaged)", 1), ("wall_turret_wreck", "Wall Turret (wrecked)", 2)] {
            guard !has(n) else { continue }
            var d = BlockDef(n, label)
            d.tex = [n + "_side"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = false
            d.hardness = 6; d.resistance = 12; d.tool = .pickaxe; d.harvestLevel = 1; d.requiresTool = true; d.sound = .metal
            d.hidden = k > 0
            addFacing(d, front: n, boxesFor: { f in k == 2 ? [base] : [base, head, barrels[f]] })
        }
        // The base's flag on the keep roof, and the one that replaces it when the player takes the base.
        for (n, label) in [("greywall_flag", "Greywall Flag"), ("taken_flag", "Your Flag")] where !has(n) {
            var d = BlockDef(n, label)
            d.tex = [n]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = false
            d.collide = false; d.noCollideBoxes = true; d.hardness = 0.8; d.sound = .wool
            d.boxes = [Box(0, 0, 7, 16, 16, 9)]
            add(d)
        }
        // Map table: the comms room's plotting table (the radar network, A1c).
        if !has("greywall_map_table") {
            var d = BlockDef("greywall_map_table", "Command Map Table")
            d.tex = ["greywall_map_table_side", "greywall_map_table_side", "greywall_map_table_top", "steel_plating",
                     "greywall_map_table_side", "greywall_map_table_side"]
            d.hardness = 3; d.tool = .pickaxe; d.sound = .stone; d.emit = 4
            add(d)
        }
        // P68 (playtest 09:18, "computer room ... like chess"): Greywall's own equipment, on ground first generated
        // with it: a flat-screen terminal (a widescreen of windows, text and graphs) and a server rack (LED rows).
        if !has("greywall_terminal") {
            var d = BlockDef("greywall_terminal", "Greywall Terminal")
            d.tex = ["greywall_terminal_side", "greywall_terminal_side", "greywall_terminal_top", "steel_plating",
                     "greywall_terminal_side", "greywall_terminal_side"]
            d.hardness = 3; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone; d.emit = 5
            addFacing(d, front: "greywall_terminal_front")
        }
        if !has("greywall_server") {
            var d = BlockDef("greywall_server", "Server Rack")
            d.tex = ["greywall_server_side", "greywall_server_side", "greywall_terminal_top", "steel_plating",
                     "greywall_server_side", "greywall_server_side"]
            d.hardness = 4; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone; d.emit = 3
            addFacing(d, front: "greywall_server_front")
        }
    }
}

extension TextureGen {
    static func greywallPainters(_ p: inout [String: Painter]) {
        func lamp(_ lit: Bool) -> Painter {
            { x, y in
                if x < 2 || x > 13 || y < 2 || y > 13 { return hex(0x2A2E33) }
                if x == 7 || x == 8 || y == 7 || y == 8 { return hex(0x3A3F45) }        // the cage bars
                let cx = Float(x) - 7.5, cy = Float(y) - 7.5
                let d: Float = sqrtf(cx * cx + cy * cy)
                return lit ? (d < 2.5 ? hex(0xFFE0D0) : hex(0xFF3A22, 1.05 - d * 0.03)) : hex(0x6A1E18, 1 - d * 0.03)
            }
        }
        p["alarm_lamp"] = lamp(false)
        p["alarm_lamp_lit"] = lamp(true)
        p["alarm_lamp_side"] = { x, y in y > 8 ? hex(0x5A1A14) : hex(0x3A4048, 0.95 + 0.05 * r(x, y, 4201)) }
        p["alarm_lamp_lit_side"] = { x, y in y > 8 ? hex(0xE8402A) : hex(0x3A4048, 0.95 + 0.05 * r(x, y, 4201)) }
        // Alarm panel: a grey steel box, a red mushroom button in a yellow guard, a row of status lamps.
        p["alarm_panel"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x30353C) }
            let cx = Float(x) - 7.5, cy = Float(y) - 8.5
            let d: Float = sqrtf(cx * cx + cy * cy)
            if d < 3.2 { return hex(0xD0281C, 1.1 - d * 0.06) }
            if d < 4.6 { return hex(0xD8A820) }
            if y == 2 && x % 3 == 1 { return hex([0x40C060, 0x5AB4FF, 0xE0B020, 0xD03A2A, 0x40C060][(x / 3) % 5]) }
            return hex(0x6A737C, 0.95 + 0.05 * r(x, y, 4202))
        }
        p["alarm_panel_side"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x30353C) }
            return hex(0x5E666F, 0.95 + 0.05 * r(x, y, 4203))
        }
        // Wall turret: dark steel, a muzzle and a red sensor eye on the front; damaged scorched with a cracked eye.
        func turretFront(_ state: Int) -> Painter {
            { x, y in
                let k: Float = 0.93 + 0.07 * r(x, y, 4210)
                let cx = Float(x) - 7.5, cy = Float(y) - 7.5
                let d: Float = sqrtf(cx * cx + cy * cy)
                if state == 2 { return hex(r(x, y, 4211) < 0.4 ? 0x1E1C1A : 0x3A3632, k) }
                if d < 1.6 { return hex(0x101214) }                                    // the muzzle
                if x >= 10 && x <= 12 && y >= 3 && y <= 5 { return state == 1 ? hex(0x5A1A14) : hex(0xFF3A22) }   // sensor
                if state == 1 && r(x, y, 4212) < 0.3 { return hex(0x2A2624, k) }      // scorch
                if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x2A2F35) }
                return hex(0x4C545C, k)
            }
        }
        func turretSide(_ state: Int) -> Painter {
            { x, y in
                let k: Float = 0.93 + 0.07 * r(x, y, 4213)
                if state == 2 { return hex(r(x, y, 4214) < 0.45 ? 0x1E1C1A : 0x3A3632, k) }
                if state == 1 && r(x, y, 4215) < 0.25 { return hex(0x2A2624, k) }
                if y % 5 == 0 || x == 0 || x == 15 { return hex(0x30363C) }
                return hex(0x55606A, k)
            }
        }
        p["wall_turret"] = turretFront(0); p["wall_turret_side"] = turretSide(0)
        p["wall_turret_damaged"] = turretFront(1); p["wall_turret_damaged_side"] = turretSide(1)
        p["wall_turret_wreck"] = turretFront(2); p["wall_turret_wreck_side"] = turretSide(2)
        // Flags: the Greywall grey with a charcoal band and a white chevron; yours deep blue with a gold band.
        p["greywall_flag"] = { x, y in
            let k: Float = 0.95 + 0.05 * r(x, y, 4216)
            if y >= 6 && y <= 9 { return abs(x - 8) + abs(y - 8) < 3 ? hex(0xE8E8E8) : hex(0x2C3036, k) }
            return hex(0x7A848C, k)
        }
        p["taken_flag"] = { x, y in
            let k: Float = 0.95 + 0.05 * r(x, y, 4217)
            if y >= 6 && y <= 9 { return hex(0xE0B030, k) }
            return hex(0x1E3A78, k)
        }
        // Map table: a pale plotting chart (coast, contours, a grid, red and blue markers) in a steel frame.
        p["greywall_map_table_top"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x3A4048) }
            if (x == 4 && y == 5) || (x == 11 && y == 10) { return hex(0xD03A2A) }
            if x == 9 && y == 4 { return hex(0x3A7AD0) }
            if x % 5 == 0 || y % 5 == 0 { return hex(0x9AA6AE) }
            let land = Float(x) * 0.6 + sinf(Float(y) * 0.7) * 2 < 7
            let k: Float = 0.96 + 0.04 * r(x, y, 4204)
            return land ? hex(0xC8C29A, k) : hex(0x8FB0C4, k)
        }
        // P68: the terminal's widescreen: a title bar, a list of text lines on the left, a bar graph and a status
        // pane on the right, a thin bezel, the stand's lip and two status LEDs below.
        p["greywall_terminal_front"] = { x, y in
            if y >= 12 { return y == 13 && (x == 3 || x == 12) ? hex(x == 3 ? 0x40E080 : 0xE0B030) : hex(0x3A4048, 0.96 + 0.04 * r(x, y, 4231)) }
            if x == 0 || x == 15 || y == 0 || y == 11 { return hex(0x14181C) }
            if y == 1 { return hex(x < 11 ? 0x2A6FB0 : 0x1C4E80) }                                        // title bar
            if x == 7 { return hex(0x0E1C2A) }                                                             // pane divider
            if x < 7 {
                let len = 2 + Int(r(y, 0, 4232) * 4)                                                       // text lines
                return y % 2 == 0 && x >= 2 && x < 1 + len ? hex(0x9AD0F4, 0.85 + 0.15 * r(x, y, 4233)) : hex(0x0B1826)
            }
            if y >= 6 {
                let h = 1 + Int(r(x, 7, 4234) * 4.99)                                                      // bar graph
                return 10 - y < h && x % 2 == 0 ? hex(x == 12 ? 0xE07A30 : 0x3ACFA0) : hex(0x0B1826)
            }
            if y == 3 && x >= 9 && x <= 13 { return hex(0x2A6FB0) }                                        // status pane
            if y == 4 && x >= 9 && x <= 11 { return hex(0x6AE0B0) }
            return hex(0x0B1826)
        }
        p["greywall_terminal_side"] = { x, y in
            if x == 0 || x == 15 || y == 15 || y == 0 { return hex(0x23272C) }
            if y % 3 == 0 && x >= 3 && x <= 12 && y < 12 { return hex(0x1E2226) }                          // vent slots
            return hex(0x343940, 0.96 + 0.04 * r(x, y, 4235))
        }
        p["greywall_terminal_top"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x23272C) }
            if y >= 9 && y <= 13 && x >= 2 && x <= 13 {                                                    // a flat keyboard
                if y == 13 { return x >= 5 && x <= 10 ? hex(0x4A5058) : hex(0x1A1D21) }                    // the space bar
                return (x + (y % 2)) % 3 == 0 ? hex(0x1A1D21) : hex(0x4A5058, 0.95 + 0.05 * r(x, y, 4236))
            }
            return hex(0x2E3238, 0.96 + 0.04 * r(x, y, 4237))
        }
        // The server rack: four drive bays of blinking LEDs behind a smoked door, a handle on the right.
        p["greywall_server_front"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x14181C) }
            if x == 14 { return y >= 5 && y <= 10 ? hex(0x8A929C) : hex(0x1C2025) }                       // handle
            if y % 4 == 0 { return hex(0x0E1114) }                                                         // bay seams
            if y % 4 == 2 && x >= 2 && x <= 12 && x % 2 == 0 {
                let v = r(x, y, 4238)
                return v < 0.55 ? hex(0x3AE07A) : (v < 0.8 ? hex(0x3A9AE0) : (v < 0.9 ? hex(0xE0B030) : hex(0x14321E)))
            }
            return hex(0x22272D, 0.95 + 0.05 * r(x, y, 4239))
        }
        p["greywall_server_side"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x23272C) }
            if x % 4 == 2 && y >= 2 && y <= 13 { return hex(0x1E2226) }                                    // perforations
            return hex(0x30353B, 0.96 + 0.04 * r(x, y, 4240))
        }
        p["greywall_map_table_side"] = { x, y in
            if y <= 1 { return hex(0x3A4048) }
            if x <= 1 || x >= 14 { return hex(0x4A5158) }
            return hex(0x6A737C, 0.95 + 0.05 * r(x, y, 4205))
        }
    }
}
