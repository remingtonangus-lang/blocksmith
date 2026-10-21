import Foundation
import simd

// P389 ("objects are one piece, broken where hit"): a lamp post, a sign, a barrel, a stump... is one designed shape, not
// cells with bites. This file finds the objects in the block grid: the cells an object can be made of, the connected
// group a struck cell belongs to, and what that group is (WorldObjects.classify, also the census's rule).
enum WorldObjects {
    enum Kind: UInt8, CaseIterable {
        case none, other, building, tree
        case lampPost, fencePost, fenceRun, sign, barrel, crate, chest, stump, log, deadTree, driprock, hay, lantern,
             gourd, pot, bench, cart, statue, well, workblock, bell, banner, campfire, anvil, cauldron
        case table, parasol                       // (appended: the raw values are saved)
        var name: String {
            switch self {
            case .none: return "none"
            case .other: return "other"
            case .building: return "building"
            case .tree: return "tree"
            case .lampPost: return "lamp post"
            case .fencePost: return "fence post"
            case .fenceRun: return "fence run"
            case .sign: return "sign"
            case .barrel: return "barrel"
            case .crate: return "crate"
            case .chest: return "chest"
            case .stump: return "stump"
            case .log: return "fallen log"
            case .deadTree: return "dead tree"
            case .driprock: return "driprock"
            case .hay: return "hay bale"
            case .lantern: return "lantern or torch"
            case .gourd: return "pumpkin or melon"
            case .pot: return "pot"
            case .bench: return "bench or table"
            case .cart: return "cart"
            case .statue: return "statue"
            case .well: return "well"
            case .workblock: return "workblock"
            case .bell: return "bell"
            case .banner: return "banner"
            case .campfire: return "campfire"
            case .anvil: return "anvil"
            case .cauldron: return "cauldron"
            case .table: return "cafe table"
            case .parasol: return "parasol"
            }
        }
    }

    // Words of block groups that belong to buildings, ground cover or lines, never to an object.
    static let notObject = ["rail", "carpet", "redstone_wire", "pressure_plate", "button", "door", "trapdoor", "stairs", "slab",
                            "pane", "glass", "ladder", "vine", "scaffolding", "snow", "path", "farmland", "water", "lava", "fire",
                            "cobweb", "lever", "tripwire", "piston", "bed", "frame", "painting", "barrier", "bars",
                            "structure_void", "moss_carpet", "lily_pad", "kelp", "seagrass", "coral", "sea_pickle", "web",
                            "window", "grate", "litter", "flower", "dripleaf", "azalea", "petal", "bush", "fern", "grass",
                            "sapling", "roots", "sprout", "vine", "lichen", "moss", "spore"]
    // Built full blocks that stand alone as things (the rest of the built blocks are walls and floors).
    static let builtThings = ["barrel", "crate", "lamp", "lantern", "glowstone", "light_panel", "bulb", "hay", "target", "bookshelf", "composter",
                              "beehive", "furnace", "crafting_table", "smoker", "loom", "fletching", "cartography", "smithing",
                              "jukebox", "note_block", "pumpkin", "melon", "chest", "tnt", "dispenser", "dropper", "observer"]

    // The cells an object can be made of (by block state).
    static let candidate: [Bool] = (0..<Blocks.count).map { i in
        let b = BlockID(i)
        guard b != AIR, Blocks.render[i] != RenderType.none.rawValue, Blocks.render[i] != RenderType.liquid.rawValue else { return false }
        let g = ShapeClass.group(b)
        if g.contains("pointed_dripstone") { return true }
        if notObject.contains(where: { g.contains($0) }) || g == "light" { return false }
        // (plants and bushes drawn from boxes are vegetation, not things)
        if ShapeClass.kind[i] == .model && (soundMat(b) == .plant || soundMat(b) == .leaves || soundMat(b) == .grass) { return false }
        switch ShapeClass.kind[i] {
        case .model, .trunk, .organic: return true
        case .built: return builtThings.contains(where: { g.contains($0) })
        default: return false
        }
    }
    static let isPost: [Bool] = (0..<Blocks.count).map { i in
        let g = ShapeClass.group(BlockID(i))
        return Blocks.render[i] == RenderType.connect.rawValue || g.hasSuffix("_wall") || g.contains("chain") || g.contains("bars")
            || g.contains("plating") || g.contains("post")
    }
    static let isLight: [Bool] = (0..<Blocks.count).map { i in
        let g = ShapeClass.group(BlockID(i))
        return Blocks.emit[i] > 0 && (g.contains("lantern") || g.contains("lamp") || g.contains("torch") || g.contains("glowstone")
                                       || g.contains("candle") || g.contains("froglight") || g.contains("bulb"))
    }

    struct Group {
        var cells: [IVec3] = []
        var blocks: [BlockID] = []
        var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
        var full = true                         // the flood reached the group's end (not cut at the limit)
        var size: IVec3 { IVec3(hi.x - lo.x + 1, hi.y - lo.y + 1, hi.z - lo.z + 1) }
        // What it is made of: group names with counts, sorted ("lantern + oak_fence x2").
        var signature: String {
            var n: [String: Int] = [:]
            for b in blocks { n[ShapeClass.group(b), default: 0] += 1 }
            return n.keys.sorted().map { n[$0]! > 1 ? "\($0) x\(n[$0]!)" : $0 }.joined(separator: " + ")
        }
    }

    // The built-layer block (field worlds: never the ground).
    @inline(__always) static func cell(_ w: World, _ p: IVec3) -> BlockID { w.builtBlock(p.x, p.y, p.z) }

    // The connected group of object cells (6-neighbours) round `from`, at most `limit` cells.
    static func group(_ w: World, from: IVec3, limit: Int) -> Group {
        var g = Group()
        guard candidate[Int(cell(w, from))] else { return g }
        var seen: Set<IVec3> = [from]
        var stack = [from]
        while let p = stack.popLast() {
            if g.cells.count >= limit { g.full = false; break }
            let b = cell(w, p)
            g.cells.append(p); g.blocks.append(b)
            g.lo = IVec3(min(g.lo.x, p.x), min(g.lo.y, p.y), min(g.lo.z, p.z))
            g.hi = IVec3(max(g.hi.x, p.x), max(g.hi.y, p.y), max(g.hi.z, p.z))
            // (logs join their diagonal neighbours too: a branch leaves its trunk at an angle)
            let log = ShapeClass.kind[Int(b)] == .trunk
            for d in log ? WorldObjects.near26 : WorldObjects.near6 {
                let q = IVec3(p.x + d.x, p.y + d.y, p.z + d.z)
                guard q.y > 0 && q.y < CH - 1, !seen.contains(q) else { continue }
                let qb = cell(w, q)
                guard candidate[Int(qb)], !log || d.x * d.x + d.y * d.y + d.z * d.z == 1 || ShapeClass.kind[Int(qb)] == .trunk else { continue }
                seen.insert(q); stack.append(q)
            }
        }
        if g.full { extend(w, &g) }
        return g
    }

    private static func add(_ g: inout Group, _ p: IVec3, _ b: BlockID) {
        g.cells.append(p); g.blocks.append(b)
        g.lo = IVec3(min(g.lo.x, p.x), min(g.lo.y, p.y), min(g.lo.z, p.z))
        g.hi = IVec3(max(g.hi.x, p.x), max(g.hi.y, p.y), max(g.hi.z, p.z))
    }

    // Cells that are no object on their own but belong to one: a cafe table's cloth on its post, a parasol's canopy
    // (wool and its carpet ring) on its pole, a street lamp's stone column under its light (a free-standing column of
    // 1-4 built blocks with the light on top and solid ground under it).
    static func extend(_ w: World, _ g: inout Group) {
        let have = Set(g.cells)
        let n0 = g.cells.count
        for k in 0..<n0 {
            let p = g.cells[k], b = g.blocks[k]
            let above = IVec3(p.x, p.y + 1, p.z)
            if Blocks.render[Int(b)] == RenderType.connect.rawValue && !have.contains(above) && !g.cells.contains(above) {
                let ab = cell(w, above), name = ShapeClass.group(ab)
                if name.contains("carpet") { add(&g, above, ab) }
                else if name.contains("wool") {
                    add(&g, above, ab)
                    for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 {
                        let q = IVec3(above.x + dx, above.y, above.z + dz), qb = cell(w, q), qn = ShapeClass.group(qb)
                        if (qn.contains("carpet") || qn.contains("wool")) && !g.cells.contains(q) { add(&g, q, qb) }
                    } }
                }
            }
            if isLight[Int(b)] && free(w, p, have) && !have.contains(IVec3(p.x, p.y - 1, p.z)) {
                var col: [IVec3] = []
                var y = p.y - 1
                while col.count < 4 {
                    let q = IVec3(p.x, y, p.z), qb = cell(w, q)
                    guard Blocks.opaque[Int(qb)] && !candidate[Int(qb)] && !SmoothTerrain.natural[Int(qb)] && free(w, q, have) else { break }
                    col.append(q); y -= 1
                }
                if !col.isEmpty && w.solidAt(p.x, y, p.z) { for q in col { add(&g, q, cell(w, q)) } }
            }
        }
    }

    // Nothing solid beside the cell (the group's own cells aside): it stands free.
    private static func free(_ w: World, _ p: IVec3, _ have: Set<IVec3>) -> Bool {
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let q = IVec3(p.x + dx, p.y, p.z + dz)
            if !have.contains(q) && Blocks.collide[Int(cell(w, q))] { return false }
        }
        return true
    }

    // The group a struck cell belongs to: its own (an object cell), else a column's or canopy's (a stone column under a
    // street lamp, a parasol's canopy). Nil when the cell belongs to no object.
    static func objectGroup(_ w: World, at p: IVec3, limit: Int) -> Group? {
        if candidate[Int(cell(w, p))] { return group(w, from: p, limit: limit) }
        for dy in [1, 2, 3, 4, -1] {
            let q = IVec3(p.x, p.y + dy, p.z)
            guard candidate[Int(cell(w, q))] else { continue }
            let g = group(w, from: q, limit: limit)
            if g.cells.contains(p) { return g }
        }
        return nil
    }

    static let near6 = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
    static let near26: [IVec3] = {
        var o: [IVec3] = []
        for y in -1...1 { for z in -1...1 { for x in -1...1 where x != 0 || y != 0 || z != 0 { o.append(IVec3(x, y, z)) } } }
        return o
    }()

    // What a group of object cells is.
    static func classify(_ w: World, _ g: Group) -> Kind {
        guard !g.cells.isEmpty else { return .none }
        let s = g.size
        if !g.full || g.cells.count > 40 || max(s.x, s.z) > 7 || s.y > 9 {
            return g.blocks.allSatisfy({ Blocks.render[Int($0)] == RenderType.connect.rawValue }) ? .fenceRun : .building
        }
        let groups = g.blocks.map { ShapeClass.group($0) }
        let kinds = g.blocks.map { ShapeClass.kind[Int($0)] }
        func all(_ f: (String) -> Bool) -> Bool { groups.allSatisfy(f) }
        func any(_ f: (String) -> Bool) -> Bool { groups.contains(where: f) }
        let have = Set(g.cells)
        // Logs and stems: a tree when leaves touch it, else a stump, a fallen log or a dead standing trunk.
        if kinds.allSatisfy({ $0 == .trunk }) {
            // (a log post that a wall or roof meets beside or above is the building's frame)
            for p in g.cells {
                for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(0, 1, 0)] {
                    let q = IVec3(p.x + d.x, p.y + d.y, p.z + d.z)
                    guard !have.contains(q) else { continue }
                    let qb = cell(w, q)
                    if Blocks.collide[Int(qb)] && !candidate[Int(qb)] && !Mesher.leafT[Int(qb)] && ShapeClass.kind[Int(qb)] != .foliage
                        && !SmoothTerrain.natural[Int(qb)] { return .building }
                }
            }
            // (leaves within 2 across and 3 up of any of its logs: a crown, however the branches lie)
            for p in g.cells {
                for dy in -1...3 { for dz in -2...2 { for dx in -2...2 {
                    let q = cell(w, IVec3(p.x + dx, p.y + dy, p.z + dz))
                    if Mesher.leafT[Int(q)] || ShapeClass.kind[Int(q)] == .foliage { return .tree }
                } } }
            }
            if s.y >= 3 { return .deadTree }
            if s.y <= 2 && max(s.x, s.z) >= 4 { return .log }
            return .stump
        }
        if all({ $0.contains("pointed_dripstone") }) { return .driprock }
        if any({ $0.contains("sign") }) && g.cells.count <= 3 { return .sign }
        if any({ $0.contains("banner") }) && g.cells.count <= 3 { return .banner }
        let lights = g.blocks.filter { isLight[Int($0)] }.count
        let posts = g.blocks.filter { isPost[Int($0)] }.count
        let column = g.blocks.filter { !candidate[Int($0)] && Blocks.opaque[Int($0)] }.count      // (a lamp's stone column)
        let cloth = g.blocks.filter { ShapeClass.group($0).contains("carpet") }.count
        let wool = g.blocks.filter { ShapeClass.group($0).contains("wool") }.count
        if lights > 0 && posts + column > 0 && lights + posts + column == g.cells.count && s.x <= 3 && s.z <= 3 { return .lampPost }
        if posts > 0 && wool > 0 && posts + wool + cloth == g.cells.count { return .parasol }
        if posts > 0 && cloth > 0 && posts + cloth == g.cells.count { return .table }
        if lights == g.cells.count && g.cells.count <= 2 {
            // (a light set into a wall or ceiling, built in on two sides or more, is the building's)
            for p in g.cells {
                var walls = 0
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let q = IVec3(p.x + dx, p.y, p.z + dz)
                    if !have.contains(q) && Blocks.opaque[Int(cell(w, q))] { walls += 1 }
                }
                if walls >= 2 { return .building }
            }
            return .lantern
        }
        if posts == g.cells.count {
            return s.x == 1 && s.z == 1 ? .fencePost : .fenceRun
        }
        if all({ $0.contains("barrel") }) { return .barrel }
        if all({ $0.contains("crate") || $0.contains("barrel") }) { return .crate }
        if all({ $0.contains("chest") }) { return .chest }
        if all({ $0.contains("hay") }) { return .hay }
        if all({ $0.contains("pumpkin") || $0.contains("melon") }) { return .gourd }
        if all({ $0.contains("pot") }) { return .pot }
        if all({ $0.contains("bell") || isPostName($0) }) && any({ $0.contains("bell") }) { return .bell }
        if all({ $0.contains("campfire") }) { return .campfire }
        if all({ $0.contains("anvil") }) { return .anvil }
        if all({ $0.contains("cauldron") }) { return .cauldron }
        if all({ $0.contains("bench") || $0.contains("table") || $0.contains("chair") || $0.contains("stool") }) { return .bench }
        if any({ $0.contains("cart") || $0.contains("wheel") }) { return .cart }
        if any({ $0.contains("statue") || $0.contains("skull") || $0.contains("head") }) { return .statue }
        if any({ $0.contains("well") }) { return .well }
        if g.cells.count == 1 && kinds[0] == .built { return .workblock }
        return .other
    }
    private static func isPostName(_ g: String) -> Bool { g.hasSuffix("_fence") || g.hasSuffix("_wall") || g.contains("chain") }
}

// MARK: Shape: parts, cuts, support (pure geometry: runs on the object worker)

extension WorldObjects {
    // One part of an object as it is drawn now: a full cube, a model box, a fence's post or rail. `box` in 1/16 of its
    // cell; `boxIndex` the block's model box it came from (-1: the cube or a connect box, its faces the block's own).
    struct Part: Codable {
        var cell: Int
        var box: [Int]                 // x0 y0 z0 x1 y1 z1 (1/16)
        var boxIndex: Int
        var cube: Bool
        // A round shape (a log drawn as a round trunk, a gourd or bale drawn rounded): [axis 0 x 1 y 2 z, radius,
        // rounded ends 0/1]: the box cut to an octagon round its axis (and its ends' edges bevelled), the convex form
        // closest to what ShapeTrunks / ShapeOrganic draw there.
        // Or ShapeOrganic's soft box: [3, its six side radii (+X -X +Y -Y +Z -Z), squash, settle (blocks)].
        var round: [Float]? = nil
        var lo: V3 { V3(Float(box[0]), Float(box[1]), Float(box[2])) / 16 }
        var hi: V3 { V3(Float(box[3]), Float(box[4]), Float(box[5])) / 16 }
        var volume: Float { let s = hi - lo; return s.x * s.y * s.z }
    }

    // A piece of what is left: a convex part of one Part (the whole of it until a cut reaches it). The poly's frame is
    // the object's (its origin cell's corner at 0); poly.origin is its cell's corner there, so its outer faces take
    // the block texture exactly as the block mesher maps it.
    struct Frag {
        var part: Int
        var poly: Fracture.Poly
    }

    // A blow: where it landed on the object (object frame), the outward normal there, its radius, its seed.
    struct Cut: Codable {
        var c: [Float]
        var n: [Float]
        var r: Float
        var s: UInt32
        var contact: SIMD3<Float> { SIMD3(c[0], c[1], c[2]) }
        var normal: SIMD3<Float> { SIMD3(n[0], n[1], n[2]) }
    }

    // The parts of the cells as the mesher draws them (fences joined to their neighbours as they stand now).
    static func makeParts(_ w: World, cells: [IVec3], blocks: [BlockID], kind: Kind = .other) -> [Part] {
        var out: [Part] = []
        for (k, p) in cells.enumerated() {
            let b = blocks[k], bi = Int(b)
            let rt = Blocks.render[bi]
            // Round shapes where the detail stream draws them so (polygon worlds): logs as round trunks, organic blocks
            // rounded (ShapeTrunks, ShapeOrganic).
            if Mesher.detailMeshes && rt == RenderType.cube.rawValue && Mesher.detailT[bi] {
                let sk = ShapeClass.kind[bi]
                if sk == .trunk {
                    let a = Int(ShapeTrunks.axisOf[bi])
                    let r: Float = kind == .stump ? ShapeTrunks.treeRadius(5) : (kind == .log || a != 1 ? ShapeTrunks.fallenRadius : 0.3)
                    var bx = [8 - Int(r * 16), 8 - Int(r * 16), 8 - Int(r * 16), 8 + Int(r * 16), 8 + Int(r * 16), 8 + Int(r * 16)]
                    bx[a] = 0; bx[a + 3] = 16
                    out.append(Part(cell: k, box: bx, boxIndex: -1, cube: false, round: [Float(a), r, 0]))
                } else {
                    // ShapeOrganic's soft box, from the same neighbours. (Its settle into smooth ground reads the smooth
                    // vertex grid, which field worlds don't have: a struck gourd keeps its cell's floor; the slot stays
                    // in the saved part for that.)
                    let (form, _, _) = ShapeOrganic.formAt(b, p.x, p.y, p.z) { w.block($0, $1, $2) }
                    out.append(Part(cell: k, box: [0, 0, 0, 16, 16, 16], boxIndex: -1, cube: false,
                                    round: [3] + form.r + [form.squash, 0]))
                }
                continue
            }
            if rt == RenderType.cube.rawValue {
                out.append(Part(cell: k, box: [0, 0, 0, 16, 16, 16], boxIndex: -1, cube: true))
                continue
            }
            var boxes: [(Box, Int)] = []
            if rt == RenderType.connect.rawValue {
                let ck = Blocks.connectKind[bi]
                let bs = BlockRegistry.connectBoxes(ck, n: Blocks.connects(ck, w.block(p.x, p.y, p.z - 1)), s: Blocks.connects(ck, w.block(p.x, p.y, p.z + 1)),
                                                    w: Blocks.connects(ck, w.block(p.x - 1, p.y, p.z)), e: Blocks.connects(ck, w.block(p.x + 1, p.y, p.z)),
                                                    collision: false)
                boxes = bs.map { ($0, -1) }
            } else {
                boxes = Blocks.boxes[bi].enumerated().map { ($0.element, $0.offset) }
            }
            for (bx, i) in boxes where bx.x1 > bx.x0 && bx.y1 > bx.y0 && bx.z1 > bx.z0 {
                out.append(Part(cell: k, box: [Int(bx.x0), Int(bx.y0), Int(bx.z0), Int(bx.x1), Int(bx.y1), Int(bx.z1)], boxIndex: i, cube: false))
            }
        }
        return out
    }

    // The untouched object: one piece per part, each in its cell's frame (vertices from the cell's corner).
    static func wholeFrags(_ parts: [Part], cells: [IVec3], origin: IVec3, ws: Fracture.Workspace) -> [Frag] {
        parts.enumerated().map { (i, pt) in
            let c = cells[pt.cell]
            var poly = Fracture.Poly.box(min: pt.lo, max: pt.hi)
            let lo = pt.lo
            for v in 0..<poly.verts.count { poly.verts[v] += lo }
            for f in 0..<poly.planes.count {
                let pl = poly.planes[f]
                poly.planes[f].w = pl.w + simd_dot(SIMD3(pl.x, pl.y, pl.z), lo)
            }
            poly.mass.centroid += lo
            let corner = V3(Float(c.x - origin.x), Float(c.y - origin.y), Float(c.z - origin.z))
            poly.origin = corner
            if let rd = pt.round, rd.count == 9 {
                return Frag(part: i, poly: softHull(poly, rd, corner: corner, ws: ws))
            }
            if let rd = pt.round, rd.count == 3 {
                // The octagon round the axis through the cell's middle (its four diagonal sides), the ends' edges
                // bevelled for a gourd or bale.
                let a = Int(rd[0]), r = rd[1], u = (a + 1) % 3, v = (a + 2) % 3
                let mid = corner + V3(0.5, 0.5, 0.5)
                var planes: [(SIMD3<Float>, UInt8)] = []
                for (su, sv) in [(1, 1), (1, -1), (-1, 1), (-1, -1)] as [(Float, Float)] {
                    var n = SIMD3<Float>(repeating: 0); n[u] = su; n[v] = sv
                    planes.append((simd_normalize(n), UInt8(u * 2 + (su > 0 ? 0 : 1))))
                }
                if rd[2] > 0 {
                    for s in [1, -1] as [Float] { for (t, st) in [(u, 1), (u, -1), (v, 1), (v, -1)] as [(Int, Float)] {
                        var n = SIMD3<Float>(repeating: 0); n[a] = s; n[t] = st
                        planes.append((simd_normalize(n), UInt8(t * 2 + (st > 0 ? 0 : 1))))
                    } }
                }
                for (n, tag) in planes {
                    // (the diagonal sides at the radius; the bevels at 0.9 of the corner's reach)
                    let reach: Float = abs(n[a]) > 0.1 ? 0.9 * (0.5 + r) / Float(2).squareRoot() : r
                    if let q = Fracture.clip(poly, plane: SIMD4(n.x, n.y, n.z, simd_dot(n, mid) + reach), tag: tag, workspace: ws) { poly = q }
                }
            }
            return Frag(part: i, poly: poly)
        }
    }

    // Directions the soft box's hull is cut along: 6 rings of 12 and the two poles.
    static let softDirs: [SIMD3<Float>] = {
        var o: [SIMD3<Float>] = [SIMD3(0, 1, 0), SIMD3(0, -1, 0)]
        for el in [-60, -35, -12, 12, 35, 60] as [Float] {
            let e = el * .pi / 180
            for k in 0..<12 {
                let a = (Float(k) + (Int(el) % 2 == 0 ? 0 : 0.5)) * .pi / 6
                o.append(SIMD3(cosf(e) * cosf(a), sinf(e), cosf(e) * sinf(a)))
            }
        }
        return o
    }()

    // The cell's cube cut to the convex hull of ShapeOrganic's soft box (each side rounded by its radius; a gourd's top
    // sunk by its squash), moved down by its settle: planes tangent to it along softDirs.
    static func softHull(_ box: Fracture.Poly, _ rd: [Float], corner: V3, ws: Fracture.Workspace) -> Fracture.Poly {
        let r = Array(rd[1...6]), squash = rd[7], dy = rd[8]
        var poly = box
        if abs(dy) > 1e-4 {
            for v in 0..<poly.verts.count { poly.verts[v].y += dy }
            for f in 0..<poly.planes.count { poly.planes[f].w += poly.planes[f].y * dy }
            poly.mass.centroid.y += dy
        }
        let c = corner + V3(0.5, 0.5 + dy, 0.5)
        for d in softDirs {
            // the inner box's support plus the corner ellipsoid's (radii by side), about the middle
            var e = d
            if e.y > 0 { e.y *= 1 - 2 * squash }
            var h: Float = 0, q: Float = 0
            for a in 0..<3 {
                let lo = r[a * 2 + 1], hi = 1 - r[a * 2]
                let ext = e[a] > 0 ? hi - 0.5 : lo - 0.5
                h += ext * e[a]
                let rho = e[a] > 0 ? r[a * 2] : r[a * 2 + 1]
                q += rho * rho * e[a] * e[a]
            }
            h += q.squareRoot()
            let tag = UInt8(Fracture.dominantFace(d))
            if let p = Fracture.clip(poly, plane: SIMD4(d.x, d.y, d.z, simd_dot(d, c) + h), tag: tag, workspace: ws) { poly = p }
        }
        return poly
    }

    @inline(__always) static func bounds(_ p: Fracture.Poly) -> (V3, V3) {
        var lo = V3(repeating: .greatestFiniteMagnitude), hi = V3(repeating: -.greatestFiniteMagnitude)
        for v in p.verts { lo = simd_min(lo, v); hi = simd_max(hi, v) }
        return (lo + p.origin, hi + p.origin)
    }

    struct CutOutcome {
        var frags: [Frag]
        var removed: [Frag]            // what the blow took out (flies as debris)
    }

    // Takes the blow's bite (Fracture.bitePlanes: a rough flattened ellipsoid into the material at the contact) out of
    // every piece it reaches: what is outside the bite stays as convex pieces (one per bite plane at most), what is
    // inside comes away.
    static let crumb: Float = 3e-4
    static func applyCut(_ frags: [Frag], _ cut: Cut, ws: Fracture.Workspace, planes: inout [SIMD4<Float>]) -> CutOutcome {
        Fracture.bitePlanes(contact: cut.contact, normal: cut.normal, radius: cut.r, seed: cut.s, into: &planes)
        let reach = min(max(cut.r, 0.04), 1.5) * 1.7
        let c = cut.contact
        var keep: [Frag] = [], gone: [Frag] = []
        keep.reserveCapacity(frags.count + 8)
        for f in frags {
            let (lo, hi) = bounds(f.poly)
            let q = simd_clamp(c, lo, hi)
            if simd_length_squared(q - c) > reach * reach { keep.append(f); continue }
            var rest: Fracture.Poly? = f.poly
            for pl in planes {
                guard let r = rest else { break }
                // the part of the piece outside this plane stays; the rest goes on to the next plane
                let outside = Fracture.clip(r, plane: -pl, workspace: ws)
                if let out = outside {
                    // (a crumb left round the bite goes with it: the pieces would multiply blow by blow)
                    if out.mass.volume < crumb && out.mass.volume < r.mass.volume * 0.999 { gone.append(Frag(part: f.part, poly: out)) }
                    else { keep.append(Frag(part: f.part, poly: out)) }
                }
                // (wholly outside, or a cut the clipper gave up on: none of it goes on)
                if let out = outside, out.mass.volume >= r.mass.volume * 0.999 { rest = nil; break }
                rest = Fracture.clip(r, plane: pl, workspace: ws)
            }
            if let r = rest { gone.append(Frag(part: f.part, poly: r)) }
        }
        return CutOutcome(frags: keep, removed: gone)
    }

    // Two pieces touch when no face plane of either has the other wholly outside it (by more than eps).
    static func touch(_ a: Fracture.Poly, _ b: Fracture.Poly, eps: Float = 0.004) -> Bool {
        func apart(_ p: Fracture.Poly, _ q: Fracture.Poly) -> Bool {
            let d = q.origin - p.origin
            for pl in p.planes {
                let n = SIMD3(pl.x, pl.y, pl.z)
                var all = true
                for v in q.verts where simd_dot(n, v + d) <= pl.w + eps { all = false; break }
                if all { return true }
            }
            return false
        }
        return !apart(a, b) && !apart(b, a)
    }

    // A face of something solid outside the object that the object rests on or hangs from (object frame): a point on
    // it, the axis (0 x, 1 y, 2 z), which side the object is on (+1: the object is on the + side), its square.
    struct Support { var at: Float; var axis: Int; var side: Float; var lo: V3; var hi: V3 }

    // The pieces held up: those joined (through touching pieces) to one resting on a support.
    static func held(_ frags: [Frag], support: [Support]) -> [Bool] {
        let n = frags.count
        var on = [Bool](repeating: false, count: n)
        var stack: [Int] = []
        let bs = frags.map { bounds($0.poly) }
        for i in 0..<n {
            let (lo, hi) = bs[i]
            for s in support {
                let a = s.axis
                let edge = s.side > 0 ? lo[a] : hi[a]
                guard abs(edge - s.at) < 0.02 else { continue }
                let b1 = (a + 1) % 3, b2 = (a + 2) % 3
                if hi[b1] > s.lo[b1] && lo[b1] < s.hi[b1] && hi[b2] > s.lo[b2] && lo[b2] < s.hi[b2] { on[i] = true; stack.append(i); break }
            }
        }
        while let i = stack.popLast() {
            for j in 0..<n where !on[j] {
                let (alo, ahi) = bs[i], (blo, bhi) = bs[j]
                guard ahi.x + 0.01 >= blo.x && bhi.x + 0.01 >= alo.x && ahi.y + 0.01 >= blo.y && bhi.y + 0.01 >= alo.y
                        && ahi.z + 0.01 >= blo.z && bhi.z + 0.01 >= alo.z else { continue }
                if touch(frags[i].poly, frags[j].poly) { on[j] = true; stack.append(j) }
            }
        }
        return on
    }

    // Nearest piece along a ray (object frame) among those `take` accepts: (index, distance, outward normal).
    static func ray(_ frags: [Frag], take: (Frag) -> Bool, _ o: SIMD3<Float>, _ d: SIMD3<Float>, maxDist: Float) -> (Int, Float, SIMD3<Float>)? {
        var best: (Int, Float, SIMD3<Float>)?
        for (i, f) in frags.enumerated() where take(f) {
            let lo = o - f.poly.origin
            var t0: Float = 0, t1 = maxDist
            var nrm = SIMD3<Float>(0, 1, 0)
            var hit = true
            for pl in f.poly.planes {
                let n = SIMD3(pl.x, pl.y, pl.z)
                let dn = simd_dot(n, d), dist = pl.w - simd_dot(n, lo)
                if abs(dn) < 1e-9 { if dist < 0 { hit = false; break }; continue }
                let t = dist / dn
                if dn < 0 { if t > t0 { t0 = t; nrm = n } } else { t1 = min(t1, t) }
                if t0 > t1 { hit = false; break }
            }
            if hit && t0 < (best?.1 ?? .greatestFiniteMagnitude) { best = (i, t0, nrm) }
        }
        return best
    }
}
