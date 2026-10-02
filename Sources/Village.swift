import Foundation

// Villages (grid spacing 34 chunks, separation 8) in plains, meadow, desert, savanna, taiga and snowy
// plains, in the matching style. A meeting point (well + bell) sits in the middle; dirt-path streets
// branch out over the terrain; buildings are placed along the streets facing them: houses of three
// sizes, farms, animal pens, a smithy, a library, a temple, job-site huts and lamp posts. Villagers
// (one per bed) and an iron golem are placed when their chunk generates.
enum Village {
    enum Style { case plains, desert, savanna, taiga, snowy }

    struct Mats {
        let planks: BlockID, log: BlockID, wall: BlockID, floor: BlockID, foundation: BlockID
        let stairs: BlockID, slab: BlockID, fence: BlockID, door: BlockID, path: BlockID, roofFlat: Bool
        let bed: String
    }

    static func mats(_ s: Style) -> Mats {
        let g = Blocks.id
        switch s {
        case .plains:
            return Mats(planks: g("oak_planks"), log: g("oak_log"), wall: g("oak_planks"), floor: g("oak_planks"), foundation: COBBLE,
                        stairs: g("oak_stairs"), slab: g("oak_slab"), fence: g("oak_fence"), door: g("oak_door"), path: g("dirt_path"), roofFlat: false, bed: "red_bed")
        case .desert:
            return Mats(planks: g("smooth_sandstone"), log: g("cut_sandstone"), wall: g("cut_sandstone"), floor: g("smooth_sandstone"), foundation: SANDSTONE,
                        stairs: g("sandstone_stairs"), slab: g("sandstone_slab"), fence: g("jungle_fence"), door: g("jungle_door"), path: g("smooth_sandstone"), roofFlat: true, bed: "green_bed")
        case .savanna:
            return Mats(planks: g("acacia_planks"), log: g("acacia_log"), wall: g("acacia_planks"), floor: g("acacia_planks"), foundation: g("orange_terracotta"),
                        stairs: g("acacia_stairs"), slab: g("acacia_slab"), fence: g("acacia_fence"), door: g("acacia_door"), path: g("dirt_path"), roofFlat: false, bed: "orange_bed")
        case .taiga:
            return Mats(planks: g("spruce_planks"), log: g("spruce_log"), wall: g("spruce_planks"), floor: g("spruce_planks"), foundation: COBBLE,
                        stairs: g("spruce_stairs"), slab: g("spruce_slab"), fence: g("spruce_fence"), door: g("spruce_door"), path: g("dirt_path"), roofFlat: false, bed: "brown_bed")
        case .snowy:
            return Mats(planks: g("spruce_planks"), log: g("spruce_log"), wall: SNOW, floor: g("spruce_planks"), foundation: g("packed_ice"),
                        stairs: g("spruce_stairs"), slab: g("spruce_slab"), fence: g("spruce_fence"), door: g("spruce_door"), path: g("dirt_path"), roofFlat: false, bed: "blue_bed")
        }
    }

    static func style(_ b: Biome) -> Style? {
        switch b {
        case .plains, .sunflowerPlains, .meadow: return .plains
        case .desert: return .desert
        case .savanna, .savannaPlateau: return .savanna
        case .taiga: return .taiga
        case .snowyPlains: return .snowy
        default: return nil
        }
    }

    enum Kind: CaseIterable { case smallHouse, mediumHouse, bigHouse, farm, pen, smithy, library, temple, jobHut }

    struct Lot {
        let kind: Kind
        let ax: Int, az: Int      // world position of local (0,0)
        let face: Int             // 0 door north, 1 south, 2 west, 3 east
        let w: Int, d: Int
        let y: Int                // floor level (internal)
        let seed: UInt64
        let job: String
    }

    static func size(_ k: Kind) -> (Int, Int) {
        switch k {
        case .smallHouse, .jobHut: return (5, 5)
        case .mediumHouse: return (7, 6)
        case .bigHouse: return (9, 7)
        case .farm: return (9, 7)
        case .pen: return (8, 8)
        case .smithy: return (8, 7)
        case .library: return (9, 7)
        case .temple: return (5, 9)
        }
    }

    static func type(_ gen: WorldGen) -> StructureType {
        StructureType(name: "village", spacing: 34, separation: 8, salt: 10387312, reach: 6) { [unowned gen] seed, cx, cz in
            let ox = cx * CS + 8, oz = cz * CS + 8
            guard let style = style(gen.column(ox, oz).biome) else { return nil }
            let cy = gen.groundY(ox, oz)
            guard cy >= SEA else { return nil }
            // Skip very broken ground (the street network would collapse into a handful of lots).
            var lo = cy, hi = cy
            for (dx, dz) in [(-20, 0), (20, 0), (0, -20), (0, 20), (-14, -14), (14, 14), (-14, 14), (14, -14)] {
                let y = gen.groundY(ox + dx, oz + dz)
                lo = min(lo, y); hi = max(hi, y)
            }
            guard hi - lo <= 12 else { return nil }
            return layout(gen, seed: seed, ox: ox, oz: oz, cy: cy, style: style)
        }
    }

    // MARK: Layout

    static func layout(_ gen: WorldGen, seed: UInt64, ox: Int, oz: Int, cy: Int, style: Style) -> StructureStart? {
        var rng = SRng(seed)
        let m = mats(style)
        var occupied = Set<IVec2Key>()
        func free(_ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int) -> Bool {
            for z in min(z0, z1)...max(z0, z1) { for x in min(x0, x1)...max(x0, x1) where occupied.contains(IVec2Key(x, z)) { return false } }
            return true
        }
        func claim(_ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int) {
            for z in min(z0, z1)...max(z0, z1) { for x in min(x0, x1)...max(x0, x1) { occupied.insert(IVec2Key(x, z)) } }
        }
        // Streets: arms from the plaza, with side branches.
        struct Road { let x: Int; let z: Int; let dx: Int; let dz: Int; let len: Int }
        var roads: [Road] = []
        claim(ox - 4, oz - 4, ox + 4, oz + 4)
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where rng.chance(0.85) {
            let len = rng.range(18, 40)
            roads.append(Road(x: ox + dx * 5, z: oz + dz * 5, dx: dx, dz: dz, len: len))
        }
        var i = 0
        while i < roads.count && roads.count < 12 {
            let r = roads[i]
            if r.len > 14 {
                for at in stride(from: 8, to: r.len - 4, by: 12) where rng.chance(0.55) {
                    let side = rng.chance(0.5) ? 1 : -1
                    let (bdx, bdz) = (r.dz * side, r.dx * side)
                    roads.append(Road(x: r.x + r.dx * at + bdx * 2, z: r.z + r.dz * at + bdz * 2, dx: bdx, dz: bdz, len: rng.range(10, 22)))
                }
            }
            i += 1
        }
        // Road columns with their ground heights (dropping roads that run into steep ground or water).
        var pathCols: [(Int, Int, Int)] = []
        var goodRoads: [Road] = []
        for r in roads {
            var cols: [(Int, Int, Int)] = []
            var lastY = cy
            var ok = true
            for s in 0..<r.len {
                let x = r.x + r.dx * s, z = r.z + r.dz * s
                let y = gen.groundY(x, z)
                if abs(y - lastY) > 2 || y < SEA - 1 { if s < 5 { ok = false }; break }
                lastY = y
                for w in -1...1 { cols.append((x + (r.dz != 0 ? w : 0), z + (r.dx != 0 ? w : 0), y)) }
            }
            guard ok, cols.count >= 15 else { continue }
            pathCols += cols
            goodRoads.append(Road(x: r.x, z: r.z, dx: r.dx, dz: r.dz, len: cols.count / 3))
            for c in cols { occupied.insert(IVec2Key(c.0, c.1)) }
        }
        guard !goodRoads.isEmpty else { return nil }
        // Buildings along the streets.
        var lots: [Lot] = []
        let weights: [(Kind, Int)] = [(.smallHouse, 30), (.mediumHouse, 20), (.bigHouse, 8), (.farm, 14), (.pen, 5), (.smithy, 4),
                                      (.library, 4), (.temple, 3), (.jobHut, 16)]
        let jobs = ["butcher", "cartographer", "fletcher", "shepherd", "mason", "leatherworker", "armorer", "fisherman", "toolsmith"]
        var haveSpecial = Set<String>()
        for r in goodRoads {
            var s = 2
            while s < r.len - 3 {
                for side in [-1, 1] {
                    var roll = rng.int(104)
                    var kind = Kind.smallHouse
                    for (k, wt) in weights { if roll < wt { kind = k; break }; roll -= wt }
                    if [.smithy, .library, .temple, .pen].contains(kind) && haveSpecial.contains("\(kind)") { kind = .smallHouse }
                    let (w, d) = size(kind)
                    // Lot faces the road: its local v axis points away from the street.
                    let px = r.x + r.dx * s, pz = r.z + r.dz * s
                    let nx = r.dz * side, nz = r.dx * side             // outward normal from road
                    let face: Int = nz == 1 ? 0 : (nz == -1 ? 1 : (nx == 1 ? 2 : 3))
                    let ux = face == 0 ? 1 : (face == 1 ? -1 : 0), uz = face == 2 ? -1 : (face == 3 ? 1 : 0)
                    let ax = px + nx * 2 - ux * (w / 2), az = pz + nz * 2 - uz * (w / 2)
                    let fx = ax + ux * (w - 1) + nx * (d - 1), fz = az + uz * (w - 1) + nz * (d - 1)
                    guard free(ax, az, fx, fz) else { continue }
                    // Ground under the corners: skip steep lots. The floor sits level with the street in front of the
                    // door (the road's edge column), so a walker steps straight in; the foundation fills or the
                    // clearing cuts the rest of the footprint to that level.
                    let ys = [gen.groundY(ax, az), gen.groundY(fx, fz), gen.groundY(ax + ux * (w - 1), az + uz * (w - 1)), gen.groundY(ax + nx * (d - 1), az + nz * (d - 1))]
                    guard let lo = ys.min(), let hi = ys.max(), hi - lo <= 4, lo >= SEA else { continue }
                    let street = gen.groundY(px + nx, pz + nz)
                    guard abs(street - hi) <= 4 && abs(street - lo) <= 4 else { continue }
                    // Two blocks spare on each side along the street too: neighbours stood wall to wall and their roof
                    // eaves ran into each other (blind critic, run 364 cherry-grove village).
                    claim(ax - nx - 2 * ux, az - nz - 2 * uz, fx + nx + 2 * ux, fz + nz + 2 * uz)
                    if [.smithy, .library, .temple, .pen].contains(kind) { haveSpecial.insert("\(kind)") }
                    // Walking level = street + 1: houses, farms and pens have their floor/ground block at y - 1; the
                    // smithy's stone floor is its own bottom layer, so it sits one lower.
                    let floorY = kind == .smithy ? street : street + 1
                    lots.append(Lot(kind: kind, ax: ax, az: az, face: face, w: w, d: d, y: floorY, seed: rng.next(), job: jobs[rng.int(jobs.count)]))
                }
                s += rng.range(7, 10)
            }
        }
        guard lots.count >= 6 else { return nil }
        var pieces: [Piece] = []
        let plaza = cy
        let styleV = style
        pieces.append(Piece(min: IVec3(ox - 5, plaza - 6, oz - 5), max: IVec3(ox + 5, plaza + 8, oz + 5)) { w in
            meetingPoint(&w, ox, plaza, oz, m, styleV)
        })
        // Roads as one piece per road (bounding box of its columns).
        var colsByRoad: [[(Int, Int, Int)]] = []
        var cur: [(Int, Int, Int)] = []
        for (k, c) in pathCols.enumerated() {
            cur.append(c)
            if cur.count >= 24 || k == pathCols.count - 1 { colsByRoad.append(cur); cur = [] }
        }
        for cols in colsByRoad {
            let xs = cols.map { $0.0 }, zs = cols.map { $0.1 }, yv = cols.map { $0.2 }
            pieces.append(Piece(min: IVec3(xs.min()!, yv.min()! - 3, zs.min()!), max: IVec3(xs.max()!, yv.max()! + 4, zs.max()!)) { w in
                for (x, z, y) in cols where w.inside(x, y, z) {
                    let cur = w.get(x, y, z)
                    if Blocks.isLiquid(cur) || cur == AIR { w.set(x, y, z, m.planks) } else { w.set(x, y, z, m.path) }
                    for k in 1...3 where Blocks.replaceable[Int(w.get(x, y + k, z))] && !Blocks.isLiquid(w.get(x, y + k, z)) { w.set(x, y + k, z, AIR) }
                    // Lamp posts now and then along the edge.
                    if hash3(x, y, z, 0x1A4F) % 97 == 0 {
                        w.set(x, y + 1, z, m.fence); w.set(x, y + 2, z, m.fence); w.set(x, y + 3, z, Blocks.id("lantern"))
                    }
                }
            })
        }
        for lot in lots {
            let (x0, z0, x1, z1) = bounds(lot)
            pieces.append(Piece(min: IVec3(x0 - 3, lot.y - 12, z0 - 3), max: IVec3(x1 + 3, lot.y + 14, z1 + 3)) { w in
                sealCaves(&w, x0 - 3, z0 - 3, x1 + 3, z1 + 3, top: lot.y + 6, floor: lot.y, depth: lot.y - 7)
                buildLot(&w, lot, m, styleV)
            })
        }
        return StructureStart(kind: "village", pieces: pieces, anchor: IVec3(ox + 6, plaza + 1, oz + 6))
    }

    // Cave pockets just under the ground round a house, filled with dirt (two villagers spent the whole behaviour sim
    // in a cave under the dirt beside a house with no way out: run 371). Below each column's surface only, never
    // water, never above the ground or the house floor (a neighbouring house in the margin keeps its rooms).
    static func sealCaves(_ w: inout StructWriter, _ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int, top: Int, floor: Int, depth: Int) {
        for z in z0...z1 { for x in x0...x1 where w.inside(x, top, z) {
            var y = top
            while y > depth && !Blocks.opaque[Int(w.get(x, y, z))] { y -= 1 }
            guard y > depth else {
                // A shaft or ravine mouth right beside the house: a two-block lid at the floor line (two blocks: never a
                // hanging wall).
                if w.get(x, floor - 1, z) == AIR && w.get(x, floor - 2, z) == AIR { w.set(x, floor - 1, z, DIRT); w.set(x, floor - 2, z, DIRT) }
                continue
            }
            // Each run of air filled only when it rests on a solid block within the depth (a run that goes deeper is
            // left alone: dirt hung over a deeper cave).
            var yy = min(y, floor) - 1
            while yy > depth {
                guard w.get(x, yy, z) == AIR else { yy -= 1; continue }
                var b = yy
                while b > depth && w.get(x, b, z) == AIR { b -= 1 }
                if b > depth && Blocks.collide[Int(w.get(x, b, z))] { for f in (b + 1)...yy { w.set(x, f, z, DIRT) } }
                yy = b - 1
            }
        } }
    }

    static func bounds(_ l: Lot) -> (Int, Int, Int, Int) {
        let a = world(l, 0, 0), b = world(l, l.w - 1, l.d - 1)
        return (min(a.0, b.0), min(a.1, b.1), max(a.0, b.0), max(a.1, b.1))
    }

    // Local (u along the street, v away from it) to world x, z.
    static func world(_ l: Lot, _ u: Int, _ v: Int) -> (Int, Int) {
        switch l.face {
        case 0: return (l.ax + u, l.az + v)
        case 1: return (l.ax - u, l.az - v)
        case 2: return (l.ax + v, l.az - u)
        default: return (l.ax - v, l.az + u)
        }
    }
    // World direction index (0 north -Z, 1 south +Z, 2 west -X, 3 east +X) of a local direction
    // (0 = +v away from street, 1 = -v toward street, 2 = +u, 3 = -u).
    static func dir(_ l: Lot, _ local: Int) -> Int {
        let table = [[1, 0, 3, 2], [0, 1, 2, 3], [3, 2, 0, 1], [2, 3, 1, 0]]
        return table[l.face][local]
    }

    // MARK: Buildings

    struct LB {
        let l: Lot
        func set(_ w: inout StructWriter, _ u: Int, _ dy: Int, _ v: Int, _ b: BlockID) {
            let (x, z) = Village.world(l, u, v)
            w.set(x, l.y + dy, z, b)
        }
        func fill(_ w: inout StructWriter, _ u0: Int, _ y0: Int, _ v0: Int, _ u1: Int, _ y1: Int, _ v1: Int, _ b: BlockID) {
            for dy in y0...y1 { for v in v0...v1 { for u in u0...u1 { set(&w, u, dy, v, b) } } }
        }
        // A torch on the wall behind it, facing the local direction (wall torch state = 1 + world facing): the house
        // torches stood in mid-air or on top of chests and job blocks.
        func wallTorch(facing local: Int) -> BlockID { TORCH + BlockID(1 + Village.dir(l, local)) }
        // Stairs whose high side points toward a local direction (world stairs state = facing index).
        func stair(_ base: BlockID, high local: Int, top: Bool = false) -> BlockID {
            base + BlockID(Village.dir(l, local) + (top ? 4 : 0))
        }
    }

    static func foundation(_ w: inout StructWriter, _ b: LB, _ m: Mats) {
        let l = b.l
        let clear = [Kind.farm, .pen].contains(l.kind) ? 3 : (l.kind == .temple ? 14 : (l.kind == .bigHouse ? 13 : 9))
        for v in 0..<l.d { for u in 0..<l.w {
            let (x, z) = world(l, u, v)
            w.pillarDown(x, l.y - 1, z, m.foundation, minY: l.y - 40)      // over deeper caves too (structcheck floating; 24 left 6-8 columns, run 357)
            for dy in 0...clear where w.inside(x, l.y + dy, z) && w.get(x, l.y + dy, z) != AIR { w.set(x, l.y + dy, z, AIR) }
        } }
    }

    // A walled room with log corners, windows, a door on the street side and a gable (or flat) roof.
    static func house(_ w: inout StructWriter, _ b: LB, _ m: Mats, wallH: Int, roof: Bool = true) {
        let l = b.l
        foundation(&w, b, m)
        // Floor level with the door sill (the walls stand on the foundation ring around it).
        b.fill(&w, 0, -1, 0, l.w - 1, -1, l.d - 1, m.foundation)
        b.fill(&w, 1, -1, 1, l.w - 2, -1, l.d - 2, m.floor)
        for v in 0..<l.d { for u in 0..<l.w {
            let edgeU = u == 0 || u == l.w - 1, edgeV = v == 0 || v == l.d - 1
            guard edgeU || edgeV else { continue }
            for dy in 0..<wallH {
                let corner = edgeU && edgeV
                var blk = corner ? m.log : m.wall
                let window = dy == 1 && !corner && ((edgeV && u % 2 == 0) || (edgeU && v % 2 == 0))
                if window { blk = Blocks.id("glass_pane") }
                b.set(&w, u, dy, v, blk)
            }
        } }
        // Door in the middle of the street wall, with a step.
        let du = l.w / 2
        b.set(&w, du, 0, 0, m.door + BlockID(dir(l, 1)))
        b.set(&w, du, 1, 0, m.door + BlockID(dir(l, 1) + 8))
        b.set(&w, du, -1, -1, m.foundation)
        for dy in 0...3 { b.set(&w, du, dy, -1, AIR) }          // nothing in front of the door (road lamp posts)
        // Roof.
        if !roof { return }
        if m.roofFlat {
            b.fill(&w, 0, wallH, 0, l.w - 1, wallH, l.d - 1, m.planks)
            for u in stride(from: 0, to: l.w, by: 2) { b.set(&w, u, wallH + 1, 0, m.slab); b.set(&w, u, wallH + 1, l.d - 1, m.slab) }
            return
        }
        // Gable along u: each row v gets the lower of the two slope heights; where they meet, a ridge.
        let d = l.d
        for v in -1...d {
            let hf = v + 1, hb = d - v
            let h = min(hf, hb)
            for u in -1...l.w {
                if hf == hb { b.set(&w, u, wallH + h, v, m.planks) }
                else { b.set(&w, u, wallH + h, v, b.stair(m.stairs, high: hf < hb ? 0 : 1)) }
            }
            // Gable end walls under the roof line.
            if v >= 0 && v < d && h > 0 { for u in [0, l.w - 1] { b.fill(&w, u, wallH, v, u, wallH + h - 1, v, m.planks) } }
        }
    }

    static func bed(_ w: inout StructWriter, _ b: LB, _ m: Mats, u: Int, v: Int) {
        // Foot at (u, v), head one further from the street.
        let d = dir(b.l, 0)
        let facing = [1, 0, 3, 2][d]      // bed facing index whose head offset points along world dir d
        let foot = Blocks.id(m.bed), head = Blocks.id(m.bed + "_head")
        b.set(&w, u, 0, v, foot + BlockID(facing))
        b.set(&w, u, 0, v + 1, head + BlockID(facing))
    }

    static func villager(_ w: inout StructWriter, _ b: LB, u: Int, v: Int, dy: Int = 0) {
        let (x, z) = world(b.l, u, v)
        w.mob("villager", V3(Float(x) + 0.5, Float(b.l.y + dy), Float(z) + 0.5))
    }

    static func buildLot(_ w: inout StructWriter, _ l: Lot, _ m: Mats, _ style: Style) {
        let b = LB(l: l)
        var rng = SRng(l.seed)
        let g = Blocks.id
        switch l.kind {
        case .smallHouse, .jobHut:
            house(&w, b, m, wallH: 4)
            bed(&w, b, m, u: 1, v: 2)
            b.set(&w, l.w - 2, 2, l.d - 2, b.wallTorch(facing: 1))                 // on the back wall (was on the chest)
            villager(&w, b, u: l.w - 2, v: 2)
            if l.kind == .jobHut {
                let job = ["butcher": "smoker", "cartographer": "cartography_table", "fletcher": "fletching_table", "shepherd": "loom",
                           "mason": "stonecutter", "leatherworker": "cauldron", "armorer": "blast_furnace", "fisherman": "barrel",
                           "toolsmith": "smithing_table"][l.job] ?? "barrel"
                b.set(&w, l.w - 2, 0, l.d - 2, g(job))
            } else {
                w.chest(world(l, l.w - 2, l.d - 2).0, l.y, world(l, l.w - 2, l.d - 2).1, loot: "village_house", seed: rng.next(), facing: dir(l, 1))
            }
        case .mediumHouse:
            house(&w, b, m, wallH: 4)
            bed(&w, b, m, u: 1, v: 2); bed(&w, b, m, u: l.w - 2, v: 2)
            b.set(&w, 3, 0, l.d - 2, g("crafting_table"))
            let c = world(l, 2, l.d - 2)
            w.chest(c.0, l.y, c.1, loot: "village_house", seed: rng.next(), facing: dir(l, 1))
            b.set(&w, 4, 0, l.d - 2, g("flower_pot"))
            b.set(&w, 1, 2, 1, b.wallTorch(facing: 2))                            // on the side wall (was in mid-air)
            villager(&w, b, u: 3, v: 2); villager(&w, b, u: 3, v: 3)
        case .bigHouse:
            house(&w, b, m, wallH: 8)
            b.fill(&w, 1, 4, 1, l.w - 2, 4, l.d - 2, m.floor)
            for dy in 0...4 { b.set(&w, l.w - 2, dy, 1, g("ladder") + BlockID(dir(l, 3))) }
            bed(&w, b, m, u: 1, v: 2); bed(&w, b, m, u: 3, v: 2)
            b.set(&w, 5, 0, l.d - 2, g("crafting_table"))
            let c = world(l, 1, l.d - 2)
            w.chest(c.0, l.y, c.1, loot: "village_house", seed: rng.next(), facing: dir(l, 1))
            b.set(&w, 4, 2, 1, b.wallTorch(facing: 0)); b.set(&w, 4, 6, l.d - 2, b.wallTorch(facing: 1))
            villager(&w, b, u: 4, v: 3); villager(&w, b, u: 2, v: 4, dy: 5); villager(&w, b, u: 5, v: 3)
        case .farm:
            foundation(&w, b, m)
            b.fill(&w, 0, -1, 0, l.w - 1, -1, l.d - 1, DIRT)
            let crop = style == .desert ? "wheat" : ["wheat", "carrots", "potatoes", "beetroots"][rng.int(4)]
            for v in 0..<l.d { for u in 0..<l.w {
                let edge = u == 0 || u == l.w - 1 || v == 0 || v == l.d - 1
                if edge { b.set(&w, u, -1, v, m.log) }
                else if u == l.w / 2 { b.set(&w, u, -1, v, WATER) }
                else {
                    b.set(&w, u, -1, v, g("farmland_moist"))
                    let stage = rng.int(crop == "beetroots" ? 4 : 8)
                    b.set(&w, u, 0, v, g(crop) + BlockID(stage))
                }
            } }
            b.set(&w, 0, 0, 0, g("composter"))
            villager(&w, b, u: 1, v: 1)
        case .pen:
            foundation(&w, b, m)
            for v in 0..<l.d { for u in 0..<l.w {
                b.set(&w, u, -1, v, style == .desert ? SAND : GRASS)
                if u == 0 || u == l.w - 1 || v == 0 || v == l.d - 1 { b.set(&w, u, 0, v, m.fence) }
            } }
            b.set(&w, l.w / 2, 0, 0, g(Blocks.key(m.fence).replacingOccurrences(of: "_fence", with: "_fence_gate")) + BlockID(dir(l, 1)))
            b.set(&w, 1, 0, l.d - 2, g("hay_block")); b.set(&w, 2, 0, l.d - 2, g("hay_block"))
            for k in 0..<3 {
                let (x, z) = world(l, 2 + k, 3)
                w.mob(["cow", "sheep", "pig"][(k + rng.int(3)) % 3], V3(Float(x) + 0.5, Float(l.y), Float(z) + 0.5))
            }
        case .smithy:
            foundation(&w, b, m)
            b.fill(&w, 0, -1, 0, l.w - 1, -1, l.d - 1, COBBLE)
            b.fill(&w, 0, 0, 0, l.w - 1, 0, l.d - 1, g("smooth_stone"))
            for v in 0..<l.d { for u in 0..<l.w where u == 0 || u == l.w - 1 || v == l.d - 1 {
                for dy in 1...3 { b.set(&w, u, dy, v, (u == 0 || u == l.w - 1) && (v == 0 || v == l.d - 1) ? m.log : COBBLE) }
            } }
            b.fill(&w, 0, 4, 0, l.w - 1, 4, l.d - 1, g("stone_slab"))
            b.fill(&w, 1, 0, l.d - 3, 2, 0, l.d - 2, LAVA)
            b.fill(&w, 1, 1, l.d - 3, 2, 1, l.d - 3, g("iron_bars"))
            b.set(&w, 4, 1, l.d - 2, g("furnace")); b.set(&w, 5, 1, l.d - 2, g("furnace"))
            b.set(&w, 3, 1, 2, g("grindstone"))
            let c = world(l, l.w - 2, l.d - 2)
            w.chest(c.0, l.y + 1, c.1, loot: "village", seed: rng.next(), facing: dir(l, 1))
            villager(&w, b, u: 4, v: 2, dy: 1)
        case .library:
            house(&w, b, m, wallH: 5)
            for u in 1..<(l.w - 1) where u != l.w / 2 { b.fill(&w, u, 0, l.d - 2, u, 2, l.d - 2, g("bookshelf")) }
            b.fill(&w, 1, 0, 2, 1, 2, l.d - 3, g("bookshelf"))
            b.set(&w, l.w / 2, 0, l.d - 3, g("lectern"))
            b.set(&w, l.w - 2, 3, 1, b.wallTorch(facing: 0))
            villager(&w, b, u: l.w / 2, v: 2)
        case .temple:
            house(&w, b, m, wallH: 11, roof: false)
            b.fill(&w, 0, 11, 0, l.w - 1, 11, l.d - 1, m.foundation)
            for (u, v) in [(0, 0), (l.w - 1, 0), (0, l.d - 1), (l.w - 1, l.d - 1)] { b.set(&w, u, 12, v, m.foundation) }
            b.fill(&w, 1, 4, 3, l.w - 2, 4, l.d - 2, m.floor)
            for dy in 0...4 { b.set(&w, 1, dy, 2, g("ladder") + BlockID(dir(l, 2))) }
            b.set(&w, l.w / 2, 0, l.d - 2, g("cauldron"))
            b.set(&w, l.w / 2, 5, l.d - 2, b.wallTorch(facing: 1))
            villager(&w, b, u: 2, v: 3)
        }
    }

    static func meetingPoint(_ w: inout StructWriter, _ ox: Int, _ y: Int, _ oz: Int, _ m: Mats, _ style: Style) {
        // Plaza of path blocks with a well in the middle and a bell beside it.
        for dz in -4...4 { for dx in -4...4 {
            w.pillarDown(ox + dx, y - 1, oz + dz, m.foundation, minY: y - 24)
            w.set(ox + dx, y, oz + dz, m.path)
            for k in 1...6 where w.get(ox + dx, y + k, oz + dz) != AIR { w.set(ox + dx, y + k, oz + dz, AIR) }
        } }
        for dz in -1...2 { for dx in -1...2 {
            let edge = dx == -1 || dx == 2 || dz == -1 || dz == 2
            w.set(ox + dx, y, oz + dz, edge ? m.foundation : WATER)
            w.set(ox + dx, y - 1, oz + dz, edge ? m.foundation : WATER)
            w.set(ox + dx, y - 2, oz + dz, m.foundation)
            if edge { w.set(ox + dx, y + 1, oz + dz, m.foundation) }
            if (dx == -1 || dx == 2) && (dz == -1 || dz == 2) {
                w.set(ox + dx, y + 2, oz + dz, m.fence); w.set(ox + dx, y + 3, oz + dz, m.fence)
            }
            w.set(ox + dx, y + 4, oz + dz, m.slab)
        } }
        w.set(ox + 3, y + 1, oz - 3, Blocks.id("bell"))
        w.mob("villager", V3(Float(ox) + 3.5, Float(y + 1), Float(oz) + 3.5))
        w.mob("iron_golem", V3(Float(ox) - 3.5, Float(y + 1), Float(oz) - 3.5))
        // Village animals (reference): a stray cat on the plaza; desert villages keep a camel.
        w.mob("cat", V3(Float(ox) - 3.5, Float(y + 1), Float(oz) + 3.5))
        if style == .desert { w.mob("camel", V3(Float(ox) + 3.5, Float(y + 1), Float(oz) - 1.5)) }
    }
}
