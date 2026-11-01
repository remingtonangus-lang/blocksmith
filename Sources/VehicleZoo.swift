import Foundation
import simd

// P505 (Remington, Nov 1 10:35-10:36: "make it create 100 different flying and driving vehicles of different shapes and
// sizes within the current game blocks and test for functionality and weapons logic... That way if players try to make
// their own vehicles... there will be few errors"): questcheck --vehiclezoo [N] [--zoofrom K] builds N vehicles (100 by
// default) out of the game's own blocks, the way a player would: block by block in the world, a helm placed, then
// assembled from the helm. They vary as players' builds do: cars, trucks, odd wheel layouts, tracked tanks, boats,
// gunboats, airships, planes, helicopters and hybrids, in many sizes and materials, built facing any of the four ways,
// with decorations (fences, glass, slabs, chests, torches) and some made wrong (no engine, no wheels). Each is flown or
// driven from its helm through the game's own controls, and checked:
//   assembly   the helm assembles every block built (and a made-wrong one still assembles, or says why not);
//   function   a car rolls ahead along its helm's facing and turns; a boat floats and moves; an airship climbs and
//              moves; a plane flies on; a helicopter lifts; a build with no drive stays put and nothing breaks;
//   weapons    its guns fire from the helm (shells leave the muzzles and fly on), turrets come round to the look;
//   sanity     no NaN, nothing falls through the course, nothing flips on flat ground, physics within budget;
//   docking    docked at the end, its blocks are put back into the world.
// One course in the sky (a road, a water basin, open air) is built once; each vehicle is removed after its run.
enum VehicleZoo {
    enum Family: String, CaseIterable { case car, truck, odd, tank, boat, gunboat, airship, plane, heli, hybrid }
    enum Medium { case road, water, air }

    struct Plan {
        var name: String
        var family: Family
        var medium: Medium
        var cells: [(IVec3, BlockID)] = []
        var helm = IVec3(0, 1, 0)
        var drives = true               // has what it needs to move (false: made wrong on purpose)
        var guns = 0                    // cannons on the hull and its turrets
        var turrets = 0
        var launch: Float = 0           // a plane's speed when let go in the air
        var expectClimb = false         // airships and helicopters
    }

    static func key(_ n: String, _ f: String = "oak_planks") -> BlockID { Blocks.has(n) ? Blocks.id(n) : Blocks.id(f) }

    // The i-th design: its family from i, its size, materials and layout from a hash of i.
    static func plan(_ i: Int) -> Plan {
        let fam = Family.allCases[i % Family.allCases.count]
        var rng = SRng(UInt64(0x505_0000 + i * 7919))
        func r(_ n: Int) -> Int { Int(rng.next() % UInt64(max(1, n))) }
        let mats = ["oak_planks", "spruce_planks", "iron_block", "stone_bricks", "birch_planks", "cobblestone", "smooth_stone",
                    "dark_oak_planks", "white_wool", "copper_block", "polished_andesite", "acacia_planks"]
        let hull = key(mats[r(mats.count)]), trim = key(mats[r(mats.count)])
        let glass = key("glass"), fence = key("oak_fence"), slab = key("oak_slab"), wheel = key("ship_wheel"), engine = key("ship_engine")
        let helmS = key("ship_helm[south]"), prop = key("ship_propeller[south]"), cannon = key("ship_cannon[south]")
        let ring = key("ship_turret_ring"), balloon = key("ship_balloon"), wing = key("ship_wing"), track = key("ship_track")
        let rotor = key("ship_rotor"), tailProp = key("ship_propeller[east]"), barrel = key("ship_gun_barrel[south]")
        var p = Plan(name: "", family: fam, medium: .road)
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
            let c = IVec3(x, y, z)
            if let k = p.cells.firstIndex(where: { $0.0 == c }) { p.cells[k].1 = b } else { p.cells.append((c, b)) }
        }
        func box(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ z0: Int, _ z1: Int, _ b: BlockID) {
            for y in y0...y1 { for z in z0...z1 { for x in x0...x1 { put(x, y, z, b) } } }
        }
        // A turret on a ring at (x, y, z): a block or three over it, one to three cannons, maybe barrels on them.
        // (Its top kept clear of the hull: a turret touching the hull is part of the hull, as the game builds them.)
        func turret(_ x: Int, _ y: Int, _ z: Int, wideOK: Bool = true) {
            put(x, y, z, ring)
            let wide = wideOK && r(2) == 1
            box(wide ? x - 1 : x, wide ? x + 1 : x, y + 1, y + 1, z, z, trim)
            let n = wide ? 1 + r(3) : 1
            for k in 0..<n {
                let gx = n == 1 ? x : x - 1 + k
                put(gx, y + 2, z, cannon); p.guns += 1
                if r(2) == 0 { for t in 1...(1 + r(2)) { put(gx, y + 2, z - t, barrel) } }
            }
            p.turrets += 1
        }
        switch fam {
        case .car, .truck, .odd, .hybrid:
            // A chassis L long, W wide (x 0..W-1, z 0..L-1, bow at z 0), wheels beside it or under it.
            let truck = fam == .truck
            let L = truck ? 10 + r(8) : 4 + r(7), W = 3 + r(truck ? 3 : 4)
            let under = r(2) == 0                       // wheels under the chassis (it rides a block higher)
            let fy = under ? 1 : 0
            box(0, W - 1, fy, fy, 0, L - 1, hull)
            var axles = truck ? [1, L / 2, L - 2] : [1, L - 2]
            if fam == .odd {
                switch r(4) {
                case 0:                                  // a trike: one wheel in the middle at the front
                    put(W / 2, fy - (under ? 1 : 0), -1 + (under ? 1 : 0), wheel)
                    axles = [L - 2]
                case 1: axles = [1, L / 2, L - 2]       // three axles on a short car
                case 2: axles = [L - 2]; put(W / 2, fy, -1, trim)     // one axle and a skid at the nose
                default: axles = [0, 1, L - 2, L - 1]    // doubled wheels front and back
                }
            }
            for z in axles {
                if under { put(0, 0, z, wheel); put(W - 1, 0, z, wheel) } else { put(-1, 0, z, wheel); put(W, 0, z, wheel) }
            }
            let hz = max(1, L - 3)
            p.helm = IVec3(W / 2, fy + 1, hz)
            put(W / 2, fy + 1, hz, helmS)
            let engines = 1 + r(truck ? 3 : 2)
            for k in 0..<engines { put(min(W - 1, k), fy + 1, L - 1, engine) }
            // Body: a windscreen, side rails or a cabin, a load box on a truck.
            if r(2) == 0 { for x in 0..<W where x != W / 2 || hz != 1 { put(x, fy + 1, 0, glass) } }
            if r(2) == 0 { for z in 1..<(L - 1) where z != hz { put(0, fy + 1, z, r(3) == 0 ? slab : fence); put(W - 1, fy + 1, z, fence) } }
            if truck { box(0, W - 1, fy + 1, fy + 2 + r(2), 1, max(1, L / 2 - 1), trim) }
            if r(3) == 0 { put(W - 1, fy + 1, max(1, hz - 1), key("chest")) }
            if r(4) == 0 { put(0, fy + 1, hz, key("torch")) }
            // Guns: a hull cannon on the nose, or a turret on the roof.
            switch r(4) {
            case 0: put(W / 2, fy + 1, 0, cannon); p.guns += 1
            case 1: if L >= 6 && !truck { turret(W / 2, fy + 1, L / 2 - 1, wideOK: W >= 5) }
            default: break
            }
            if fam == .odd && r(5) == 0 {
                // Made wrong: no engine (it shouldn't move, and nothing should break).
                p.cells.removeAll { $0.1 == engine }
                p.drives = false
            }
            if fam == .hybrid {
                switch r(3) {
                case 0:
                    // A flying car: balloons on a frame over it and a pusher propeller at the back (over a turret's
                    // cannons, with a block of air between: an envelope touching the turret made it part of the hull).
                    let ey = fy + (p.turrets > 0 ? 5 : 3)
                    box(0, W - 1, ey, ey, 0, L - 1, balloon)
                    for (x, z) in [(0, 0), (W - 1, 0), (0, L - 1), (W - 1, L - 1)] { for y in (fy + 1)..<ey { put(x, y, z, trim) } }
                    put(W / 2, fy, L, prop)
                    p.medium = .air; p.expectClimb = true
                case 1:
                    // Wings on a car (players do this): it still drives.
                    for z in (L / 2 - 1)...(L / 2) where !axles.contains(z) { for x in 1...3 { put(-x, fy, z, wing); put(W - 1 + x, fy, z, wing) } }
                default:
                    // An amphibian: walls round the chassis to hold air, a propeller under the stern, on the water.
                    // (Built of wood, as the boats are: an iron or stone car with a one-block wall sank, as it should.)
                    let wood = key(["oak_planks", "spruce_planks", "birch_planks"][r(3)])
                    p.cells = p.cells.map { ($0.0, $0.1 == hull || $0.1 == trim ? wood : $0.1) }
                    for z in 0..<L { put(0, fy + 1, z, wood); put(W - 1, fy + 1, z, wood) }
                    for x in 0..<W { put(x, fy + 1, L - 1, wood) }
                    put(W / 2, fy + 1, L - 1, engine)
                    put(W / 2, fy, L, prop)
                    p.medium = .water
                }
            }
            p.name = "\(fam.rawValue) \(W)x\(L)" + (under ? " (wheels under)" : "") + (p.drives ? "" : " (no engine)")
        case .tank:
            let L = 6 + r(6), W = 4 + r(3)
            box(1, W - 2, 1, 1, 0, L - 1, hull)
            box(0, 0, 0, 1, 0, L - 1, track); box(W - 1, W - 1, 0, 1, 0, L - 1, track)
            box(1, W - 2, 2, 2, 1, L - 2, trim)
            p.helm = IVec3(W / 2, 2, L - 2); put(W / 2, 2, L - 2, helmS)
            for k in 0...(r(2)) { put(1 + k, 2, L - 1, engine) }
            turret(W / 2, 3, L / 2 - 1)
            if L >= 11 && r(2) == 0 { turret(W / 2, 3, 1) }
            p.name = "tank \(W)x\(L), \(p.turrets) turret\(p.turrets == 1 ? "" : "s")"
        case .boat, .gunboat:
            // (Wood: an iron raft with walls a block high sinks, as it should; that isn't what this looks for.)
            let woods = ["oak_planks", "spruce_planks", "birch_planks", "dark_oak_planks", "acacia_planks", "jungle_planks"]
            let hull = key(woods[r(woods.count)]), trim = key(woods[r(woods.count)])
            let L = 7 + r(10), W = 3 + r(4), wallTop = 1 + r(2)
            box(0, W - 1, 0, 0, 0, L - 1, hull)
            for y in 1...wallTop { for z in 0..<L { for x in 0..<W where x == 0 || x == W - 1 || z == 0 || z == L - 1 { put(x, y, z, y == 1 ? hull : trim) } } }
            p.helm = IVec3(W / 2, 1, L - 3); put(W / 2, 1, L - 3, helmS)
            put(W / 2, 1, L - 2, engine)
            let props = W >= 5 && r(2) == 0 ? [1, W - 2] : [W / 2]
            for x in props { put(x, 0, L, prop) }
            if r(2) == 0 { for y in 1...(2 + r(3)) { put(W / 2, y, 2, key("oak_log")) } }
            if fam == .gunboat {
                // A pedestal mid-ships up to the walls' top, the ring on it, the turret clear above the walls.
                let tz = L / 2
                for y in 1...wallTop { put(W / 2, y, tz, trim) }
                turret(W / 2, wallTop + 1, tz, wideOK: W >= 5)
                if r(2) == 0 {                           // a broadside: cannons on both sides facing out
                    for z in stride(from: 2, to: L - 3, by: 2) { put(-1, 1, z, key("ship_cannon[west]")); put(W, 1, z, key("ship_cannon[east]")); p.guns += 2 }
                }
            }
            p.medium = .water
            p.name = "\(fam.rawValue) \(W)x\(L), \(props.count) propeller\(props.count == 1 ? "" : "s")"
        case .airship:
            let L = 5 + r(8), W = 3 + r(4)
            box(0, W - 1, 0, 0, 0, L - 1, hull)
            for z in 0..<L { for x in 0..<W where x == 0 || x == W - 1 || z == 0 || z == L - 1 { put(x, 1, z, fence) } }
            // The envelope: an ellipsoid of balloons on posts, or a flat layer straight on the deck's posts.
            let ry = 2 + r(2)
            let cx = Float(W - 1) / 2, cz = Float(L - 1) / 2
            for (x, z) in [(0, 0), (W - 1, 0), (0, L - 1), (W - 1, L - 1)] { for y in 1...3 { put(x, y, z, trim) } }
            if r(2) == 0 {
                for y in 4...(4 + ry * 2) { for z in -1...L { for x in -1...W {
                    let ex = (Float(x) - cx) / (cx + 1.6), ey = (Float(y) - Float(4 + ry)) / (Float(ry) + 0.6), ez = (Float(z) - cz) / (cz + 1.6)
                    if ex * ex + ey * ey + ez * ez <= 1 { put(x, y, z, balloon) }
                } } }
            } else {
                box(0, W - 1, 4, 4, 0, L - 1, balloon)
            }
            // A mast mid-deck up into the envelope (the corner posts end under an ellipsoid's rounded corners: it
            // came away from the deck, 59 of 218 blocks assembled).
            for y in 1...4 where !(y == 1 && p.cells.contains { $0.0 == IVec3(W / 2, 1, L / 2) }) { put(W / 2, y, L / 2, trim) }
            p.helm = IVec3(W / 2, 1, L - 2); put(W / 2, 1, L - 2, helmS)
            put(W / 2, 1, L - 3, engine)
            for x in (W >= 5 ? [0, W - 1] : [W / 2]) { put(x, 0, L, prop) }
            if r(3) == 0 { put(W / 2, 0, -1, cannon); p.guns += 1 }
            p.medium = .air; p.expectClimb = true
            p.name = "airship \(W)x\(L)"
        case .plane:
            let L = 7 + r(6), span = 4 + r(6)
            box(0, 2, 0, 0, 0, L - 1, hull)
            let wz = 2 + r(2)
            for x in 1...span { for z in wz...(wz + 1 + r(2)) { put(-x, 0, z, wing); put(2 + x, 0, z, wing) } }
            for x in 1...(1 + span / 3) { put(-x, 0, L - 1, wing); put(2 + x, 0, L - 1, wing) }
            put(1, 1, L - 1, trim); put(1, 2, L - 1, trim)
            for x in (r(2) == 0 ? [1] : [0, 2]) { put(x, 0, -1, prop) }
            for k in 0...(r(2)) { put(k, 1, 1, engine) }
            p.helm = IVec3(1, 1, wz + 1); put(1, 1, wz + 1, helmS)
            if r(2) == 0 { put(1, 1, wz, glass) }
            if r(2) == 0 { put(1, -1, 1, wheel); put(0, -1, wz + 1, wheel); put(2, -1, wz + 1, wheel) }
            if r(3) == 0 { put(-span, 0, wz, cannon); put(2 + span, 0, wz, cannon); p.guns += 2 }
            p.medium = .air; p.launch = 18
            p.name = "plane span \(span * 2 + 3), \(L) long"
        case .heli:
            let L = 4 + r(4), W = 3 + r(2)
            box(0, W - 1, 0, 0, 0, L - 1, hull)
            box(0, W - 1, 3, 3, 0, L - 1, trim)
            for (x, z) in [(0, 0), (W - 1, 0), (0, L - 1), (W - 1, L - 1)] { for y in 1...2 { put(x, y, z, trim) } }
            p.helm = IVec3(W / 2, 1, 1); put(W / 2, 1, 1, helmS)
            put(W / 2, 1, L - 1, engine)
            put(W / 2, 4, L / 2, rotor)
            let boom = 3 + r(5)
            for z in L..<(L + boom) { put(W / 2, 3, z, trim) }
            if r(4) != 0 { put(W / 2 + 1, 3, L + boom - 1, tailProp) }
            if r(3) == 0 { put(W / 2, 0, -1, cannon); p.guns += 1 }
            // (On the road, as a player builds one on the ground: built in the air it fell while its rotor spun up.)
            p.medium = .road; p.expectClimb = true
            p.name = "helicopter \(W)x\(L), boom \(boom)"
        }
        // Built facing any of the four ways (a player's helm points wherever he set it).
        let q = r(4)
        if q != 0 {
            let rot = Quat(angle: Float(q) * .pi / 2, axis: V3(0, 1, 0))
            func turn(_ c: IVec3) -> IVec3 {
                let d = rot.act(V3(Float(c.x), Float(c.y), Float(c.z)))
                return IVec3(Int(d.x.rounded()), Int(d.y.rounded()), Int(d.z.rounded()))
            }
            p.cells = p.cells.map { (turn($0.0), ShipParts.rotate($0.1, q)) }
            p.helm = turn(p.helm)
            p.name += ", built facing \(["north", "west", "south", "east"][q])"
        }
        return p
    }

    // MARK: The course

    static let courseY = 300                       // well over any land (internal y)
    // Road: a square x, z -road...road at courseY (vehicles stand on it, built in the middle); basin: x basinX0...basinX1,
    // z -basinZ...basinZ, walled, water courseY-10...-1 (boats built in its middle). Ten deep: an iron-heavy gunboat drew
    // more than the three it had and dragged its keel on the floor. Wide both ways: the first road and basin were long
    // strips 29 and 30 wide, so whatever was built facing east or west ran off the road or into the basin's wall in its
    // 4 s ahead (pinned on the wall it couldn't turn: "steered 0 degrees"; a broadside touching the wall took the wall).
    static let basinDepth = 10
    // (A fast car covers 55 blocks in its 4 s ahead and 45 more in its 2 s turning: the road is 130 out each way. The air
    // ones are let go high and off to the north, clear of it: a plane that sank onto the road couldn't be steered.)
    static let road = 130, basinX0 = 150, basinX1 = 250, basinZ = 50
    static func buildCourse(_ w: World, _ o: IVec3) {
        let stone = key("smooth_stone", "stone"), water = WATER
        for z in (o.z - road)...(o.z + road) {
            for x in (o.x - road)...(o.x + road) {
                if w.rawBlock(x, o.y, z) != stone { w.setBlockAsync(x, o.y, z, stone) }
                for y in (o.y + 1)...(o.y + 24) where w.rawBlock(x, y, z) != AIR { w.setBlockAsync(x, y, z, AIR) }
            }
        }
        for z in (o.z - basinZ)...(o.z + basinZ) {
            for x in (o.x + basinX0)...(o.x + basinX1) {
                if w.rawBlock(x, o.y - basinDepth - 1, z) != stone { w.setBlockAsync(x, o.y - basinDepth - 1, z, stone) }
                let edge = x == o.x + basinX0 || x == o.x + basinX1 || abs(z - o.z) == basinZ
                for y in (o.y - basinDepth)...(o.y - 1) {
                    let want = edge ? stone : water
                    if w.rawBlock(x, y, z) != want { w.setBlockAsync(x, y, z, want) }
                }
                for y in o.y...(o.y + 24) where w.rawBlock(x, y, z) != AIR { w.setBlockAsync(x, y, z, AIR) }
            }
        }
    }
    static func onRoad(_ p: V3, _ o: IVec3) -> Bool { abs(p.x - Float(o.x)) < Float(road - 1) && abs(p.z - Float(o.z)) < Float(road - 1) }

    // MARK: A run

    struct Result { var ok: Bool; var line: String }

    static func test(_ g: Game, _ i: Int, _ o: IVec3) -> Result {
        let w = g.world, ships = w.ships
        let p = plan(i)
        // The course's own blocks: the road, the basin's floor and walls (its water is liquid; a docked hull's blocks in
        // the basin count as the vehicle's: they were counted as the course, so half a docked boat looked lost).
        func course(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            let inBasin = x >= o.x + basinX0 && x <= o.x + basinX1 && abs(z - o.z) <= basinZ
            return (y == o.y && abs(x - o.x) <= road && abs(z - o.z) <= road) || (inBasin && y == o.y - basinDepth - 1)
                || (inBasin && (x == o.x + basinX0 || x == o.x + basinX1 || abs(z - o.z) == basinZ) && y >= o.y - basinDepth && y <= o.y - 1)
        }
        // Where it is built: on the road, afloat in the basin, or in the air beside the road.
        let base: IVec3
        switch p.medium {
        case .road: base = IVec3(o.x, o.y + 1, o.z)
        case .water: base = IVec3(o.x + (basinX0 + basinX1) / 2, o.y - 1, o.z)
        case .air: base = IVec3(o.x, o.y + 45, o.z - 220)
        }
        // The lowest built layer sits on the road (a wheel or a track under the chassis, or the chassis itself).
        let lowY = p.cells.map { $0.0.y }.min() ?? 0
        let shift = IVec3(base.x, base.y - lowY, base.z)
        // Clear the space, then build block by block.
        let lo = p.cells.reduce(IVec3(99, 99, 99)) { IVec3(min($0.x, $1.0.x), min($0.y, $1.0.y), min($0.z, $1.0.z)) } + shift
        let hi = p.cells.reduce(IVec3(-99, -99, -99)) { IVec3(max($0.x, $1.0.x), max($0.y, $1.0.y), max($0.z, $1.0.z)) } + shift
        for y in lo.y...(hi.y + 2) { for z in (lo.z - 2)...(hi.z + 2) { for x in (lo.x - 2)...(hi.x + 2) {
            let b = w.rawBlock(x, y, z)
            if b != AIR && !Blocks.isLiquid(b) && !course(x, y, z) { w.setBlockAsync(x, y, z, AIR) }
        } } }
        for (c, b) in p.cells { w.setBlockAsync(c.x + shift.x, c.y + shift.y, c.z + shift.z, b) }
        let built = p.cells.count
        let helm = p.helm + shift
        let n0 = ships.list.count
        let (made, msg) = ships.assemble(at: helm, game: g)
        guard let s = made else { return Result(ok: false, line: "\(p.name): did not assemble (\(msg))") }
        var notes: [String] = []
        var ok = true
        func fail(_ m: String) { ok = false; notes.append("FAIL " + m) }
        let parts = ([s] + ships.turrets(of: s)).reduce(0) { $0 + $1.blockCount }
        if parts != built { fail("assembled \(parts) of \(built) blocks (\(msg))") }
        if ships.turrets(of: s).count != p.turrets { fail("\(ships.turrets(of: s).count) turrets, built \(p.turrets)") }
        defer {
            g.leaveHelm()
            ships.aboard = nil
            for t in ships.list.dropFirst(n0) { ships.remove(t) }
            for sh in ships.shells { sh.life = 0 }
            ships.shells.removeAll()
        }
        g.startPiloting(s)
        // (He sits facing the way the helm points: a helicopter's pedals turn it toward his look, so a look left at
        // north turned one built facing south round, and "full ahead" flew it backwards off the way it was built.)
        g.player.yaw = s.yaw; g.player.pitch = 0
        var mi = MoveInput()
        var worstMs = 0.0
        func run(_ secs: Float) {
            let dt: Float = 1.0 / 60
            for _ in 0..<Int(secs * 60) {
                let t0 = CFAbsoluteTimeGetCurrent()
                g.shipPlayerUpdate(dt, mi)
                ships.update(dt, game: g)
                worstMs = max(worstMs, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                if !s.pos.x.isFinite || !s.pos.y.isFinite || !s.pos.z.isFinite { return }
            }
        }
        if p.launch > 0 { s.vel = s.dirToWorld(s.fwd) * p.launch }
        run(p.family == .heli ? 5 : 1.5)                  // (a helicopter's rotor spins up for a few seconds first)
        let fwd0 = s.dirToWorld(s.fwd), start = s.pos, yaw0 = s.yaw
        // Function.
        if p.expectClimb {
            mi.jump = true; run(3); mi.jump = false
            let rise = s.pos.y - start.y
            if rise < 1 { fail(String(format: "asked to climb for 3 s it rose %.1f", rise)) } else { notes.append(String(format: "climbed %.1f", rise)) }
        }
        let a = s.pos
        mi.forward = 1; run(p.medium == .air && p.launch > 0 ? 3 : 4)
        let d = s.pos - a
        let along = simd_dot(V2(d.x, d.z), simd_normalize(V2(fwd0.x, fwd0.z) + V2(1e-5, 0))), flat = simd_length(V2(d.x, d.z))
        if p.drives {
            if along < 3 {
                fail(String(format: "full ahead for 4 s it went %.1f along its helm's facing (%.1f in all; %d wheels, %d props, %d engines, grounded %@, %d contacts, throttle %.2f, %.0f t)",
                            along, flat, s.wheels.count, s.props.count, s.engines, s.grounded ? "yes" : "no", s.contacts, s.throttleEase, s.mass))
            }
            else { notes.append(String(format: "ran %.0f ahead", along)) }
        } else if flat > 2 {
            fail(String(format: "with no engine it moved %.1f", flat))
        } else { notes.append("stood still with no engine") }
        mi.strafe = 1; run(2); mi.strafe = 0; mi.forward = 0
        var turned = abs(remainderf(s.yaw - yaw0, 2 * .pi)) * 180 / .pi
        if p.drives && turned < 8 && p.family != .heli {
            // (a helicopter's stick slides it sideways; others steer)
            fail(String(format: "steered right for 2 s it turned %.0f degrees (yaw rate %.2f, steer %.2f, %.0f t, submerged %.0f, grounded %@, %d contacts, speed %.1f)",
                        turned, simd_dot(s.angVel, s.dirToWorld(V3(0, 1, 0))), s.steerEase, s.mass, s.submerged, s.grounded ? "yes" : "no", s.contacts, simd_length(s.vel)))
        }
        turned = max(turned, 0)
        // Sanity.
        let up = s.dirToWorld(V3(0, 1, 0)).y
        if !s.pos.x.isFinite || !s.pos.y.isFinite || !s.pos.z.isFinite { fail("its position went NaN") }
        switch p.medium {
        case .road:
            if !onRoad(s.pos, o) { fail(String(format: "ran off the course's road (at %.0f, %.0f from the start)", s.pos.x - Float(o.x), s.pos.z - Float(o.z))) }
            if s.worldMin.y < Float(o.y) - 0.6 && onRoad(s.pos, o) { fail(String(format: "sank into the road (lowest %.2f, road top %d)", s.worldMin.y, o.y + 1)) }
            if up < 0.5 && onRoad(s.pos, o) { fail(String(format: "rolled over on the flat road (up %.2f)", up)) }
        case .water:
            if s.pos.y < Float(o.y - 4) { fail(String(format: "sank (centre %.1f, water top %d)", s.pos.y, o.y - 1)) }
            if up < 0.5 { fail(String(format: "capsized (up %.2f)", up)) }
        case .air: break
        }
        if worstMs > 25 { fail(String(format: "a physics step took %.1f ms", worstMs)) }
        // Weapons: fired from the helm the way he fires them, shells leave and fly; turrets come round to his look.
        if p.guns > 0 {
            let before = ships.shells.count
            for t in [s] + ships.turrets(of: s) { t.reload = 0 }
            _ = g.shipInteract(breakHeld: true, breakNow: true, useNow: false, sneak: false, dt: 1.0 / 60)
            let fired = ships.shells.count - before
            let muzzles = ships.shells.suffix(max(0, fired)).map { $0.pos }
            run(0.6)
            let flew = zip(ships.shells.suffix(max(0, fired)), muzzles).map { simd_length($0.0.pos - $0.1) }.max() ?? 0
            if fired == 0 { fail("its \(p.guns) gun\(p.guns == 1 ? "" : "s") fired nothing from the helm") }
            else if flew < 5 && ships.shells.count >= before + fired { fail(String(format: "%d shells fired but none flew 5 blocks (%.1f)", fired, flew)) }
            else { notes.append("\(fired) shell\(fired == 1 ? "" : "s") away") }
            for t in ships.turrets(of: s) {
                let y0 = t.turretYaw
                g.player.yaw = s.yaw + .pi / 2
                run(3)
                let moved = abs(remainderf(t.turretYaw - y0, 2 * .pi)) * 180 / .pi
                if moved < 30 {
                    fail(String(format: "its turret came round %.0f degrees to a look 90 off (yaw %.2f -> %.2f, wants %@, aim point %@, look yaw %.2f vs hull %.2f)",
                                moved, y0, t.turretYaw, t.aimYaw.map { String(format: "%.2f", $0) } ?? "nil",
                                t.aimAt.map { String(format: "%.0f,%.0f,%.0f", $0.x - s.pos.x, $0.y - s.pos.y, $0.z - s.pos.z) } ?? "nil", g.player.yaw, s.yaw))
                }
                break
            }
        }
        // Docking puts its blocks back.
        g.leaveHelm()
        ships.aboard = nil
        if p.medium != .air {
            mi = MoveInput()
            for _ in 0..<60 { ships.update(1.0 / 60, game: g); let hv = (s.vel.x * s.vel.x + s.vel.z * s.vel.z).squareRoot(); if hv < 0.3 && abs(s.vel.y) < 0.3 { break } }
            let docked = ships.disassemble(s, game: g)
            if !docked.hasPrefix("Docked") { fail("docking said: \(docked)") }
            var back = 0
            let c = IVec3(Int(floor(s.pos.x)), Int(floor(s.pos.y)), Int(floor(s.pos.z)))
            let r = 24
            for y in (c.y - 6)...(c.y + 16) { for z in (c.z - r)...(c.z + r) { for x in (c.x - r)...(c.x + r) {
                let b = w.rawBlock(x, y, z)
                if b != AIR && !Blocks.isLiquid(b) && !course(x, y, z) { back += 1 }
            } } }
            if back < built * 9 / 10 { fail("docked, \(back) of its \(built) blocks are back in the world") }
            // Clear what came back.
            for y in (c.y - 6)...(c.y + 16) { for z in (c.z - r)...(c.z + r) { for x in (c.x - r)...(c.x + r) {
                let b = w.rawBlock(x, y, z)
                if b != AIR && !Blocks.isLiquid(b) && !course(x, y, z) { w.setBlockAsync(x, y, z, AIR) }
            } } }
        }
        return Result(ok: ok, line: "\(p.name), \(built) blocks: " + notes.joined(separator: "; "))
    }

    static func run(_ g: Game, count: Int, from: Int = 0, _ check: (Bool, String) -> Void) {
        let w = g.world
        let wasSurvival = g.survival
        g.survival = false
        defer { g.survival = wasSurvival }
        w.ships.encounters = false
        let o = IVec3(Int(floor(g.player.pos.x)), courseY, Int(floor(g.player.pos.z)))
        g.player.pos = V3(Float(o.x) + 0.5, Float(o.y + 2), Float(o.z) + 0.5)
        _ = w.loadSync(center: V3(Float(o.x + 60), Float(o.y), Float(o.z - 50)), radius: 13)
        buildCourse(w, o)
        var passed = 0, byFamily: [String: (Int, Int)] = [:]
        let t0 = CFAbsoluteTimeGetCurrent()
        for i in from..<(from + count) {
            let r = test(g, i, o)
            if plan(i).guns > 0 { buildCourse(w, o) }              // (shells landing on the course)
            let fam = plan(i).family.rawValue
            byFamily[fam, default: (0, 0)].1 += 1
            if r.ok { passed += 1; byFamily[fam, default: (0, 0)].0 += 1 }
            check(r.ok, String(format: "vehiclezoo %03d ", i) + r.line)
        }
        let fams = byFamily.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.0)/\($0.value.1)" }.joined(separator: ", ")
        print(String(format: "vehiclezoo: %d of %d vehicles work (%@) in %.0f s", passed, count, fams, CFAbsoluteTimeGetCurrent() - t0))
    }
}
