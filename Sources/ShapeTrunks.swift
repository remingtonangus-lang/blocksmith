import Foundation
import simd

// Realistic world (docs/design/realistic-world.md 1.4): round trunks and limbs grown from the log graph, for every
// trunk-class block (ShapeClass.trunk: logs, wood, stems, their stripped forms). Runs on the mesh workers inside
// Mesher.buildSection; draws into the section's detail stream (DetailMesh).
//
// From the logs in a window round the section:
//  - trunk columns: vertical runs of logs standing on the ground (or 3+ long). A column with leaves round its top is a
//    living tree: it tapers with height, leans a little (world-position noise), flares into roots where it meets the
//    ground and closes in a rounded cap under its crown. A column with no crown (a building's post, a stump) is timber:
//    straight, nearly the full block, flat cut ends showing the rings.
//  - 2x2 columns are one fat trunk round their shared centre.
//  - branches: logs joined to a living column through other logs (26-connected, breadth-first from the trunk): each is
//    a limb from its parent's centre to its own, thinner the further out it is, ending in a tapered tip. So branches
//    leave the trunk at an angle and fork, whatever shape the generator gave the tree.
//  - any other log (a log cabin wall, a fallen trunk, a pile): a round log along its own axis.
// Every number comes from the blocks within 10 of a log and from world-position noise, so two sections meeting at a
// joint compute the same ring there (no seams). Logs stay blocks for gameplay (chopping, collision, saves).
// P297 (Oct 15 11:50-11:54, polygon world: "logs are far too thick", "roots not going in the ground", a floating log in a
// crown): trunks are as thick as trees that height are (radius 0.2-0.36, was 0.33-0.44); a stump and a fallen trunk on
// natural ground keep a tree's thickness (only built timber, a cabin's walls and posts, nearly fills its block); roots,
// root flares, stumps and fallen trunks reach down to the drawn ground; a log in a crown that no limb walk reaches is a
// thin bough, not a thick cut log.
enum ShapeTrunks {
    static let axisOf: [UInt8] = (0..<Blocks.count).map { i in
        let k = Blocks.key(BlockID(i))
        return k.hasSuffix("[x]") ? 0 : (k.hasSuffix("[z]") ? 2 : 1)
    }
    static let isTrunk: [Bool] = ShapeClass.kind.map { $0 == .trunk }
    // P433: a tree's root block (ShapeClass: a see-through wood block named *_roots, mangrove roots): trunk-class, but
    // never a column of its own: a root grows out of the trunk through the limb walk (col 3) and runs into the ground.
    static let isRoot: [Bool] = (0..<Blocks.count).map { ShapeClass.kind[$0] == .trunk && !Blocks.opaque[$0] && Blocks.key(BlockID($0)).hasSuffix("_roots") }
    static let isLog: [Bool] = (0..<Blocks.count).map { ShapeClass.kind[$0] == .trunk && !isRoot[$0] }

    // Window: section-local -M ... 15 + M on each axis (inside the mesher's 48^3 region).
    static let M = 10
    static let W = 16 + 2 * M

    final class Scratch {
        let n = ShapeTrunks.W * ShapeTrunks.W * ShapeTrunks.W
        let rad: UnsafeMutablePointer<Float>      // radius per log cell (0: not a log)
        let par: UnsafeMutablePointer<Int32>      // parent cell index (-1 none)
        let dist: UnsafeMutablePointer<Int16>     // graph steps from a living column (-1 unreached)
        let col: UnsafeMutablePointer<UInt8>      // 1 living column cell, 2 timber column cell
        let kids: UnsafeMutablePointer<UInt8>     // children count
        let queue = GrowBuf<Int32>(4096)
        init() {
            rad = .allocate(capacity: n); par = .allocate(capacity: n); dist = .allocate(capacity: n)
            col = .allocate(capacity: n); kids = .allocate(capacity: n)
        }
        deinit { rad.deallocate(); par.deallocate(); dist.deallocate(); col.deallocate(); kids.deallocate() }
        static var current: Scratch {
            let d = Thread.current.threadDictionary
            if let s = d["blocksmith.trunkScratch"] as? Scratch { return s }
            let s = Scratch()
            d["blocksmith.trunkScratch"] = s
            return s
        }
    }

    @inline(__always) static func wi(_ x: Int, _ y: Int, _ z: Int) -> Int { (x + M) + (z + M) * W + (y + M) * W * W }

    // Is there a trunk-class block in the owned 16^3?
    static func any(_ ctx: DetailContext) -> Bool {
        for y in 0..<16 { for z in 0..<16 { for x in 0..<16 where isTrunk[Int(ctx.R[ctx.ri(x, y, z)])] { return true } } }
        return false
    }

    static func emit(_ ctx: DetailContext) {
        guard any(ctx) else { return }
        let s = Scratch.current
        let n = s.n
        s.rad.initialize(repeating: 0, count: n); s.par.initialize(repeating: -1, count: n)
        s.dist.initialize(repeating: -1, count: n); s.col.initialize(repeating: 0, count: n); s.kids.initialize(repeating: 0, count: n)
        let leafT = Mesher.leafT, opaqueT = Blocks.opaque, collideT = Blocks.collide
        @inline(__always) func log(_ x: Int, _ y: Int, _ z: Int) -> Bool { isTrunk[Int(ctx.block(x, y, z))] }
        @inline(__always) func logC(_ x: Int, _ y: Int, _ z: Int) -> Bool { isLog[Int(ctx.block(x, y, z))] }
        // P433: root cells are limb cells of the tree (col 3): the walk below grows them out of the trunk's foot.
        for y in -M..<(16 + M) { for z in -M..<(16 + M) { for x in -M..<(16 + M) where isRoot[Int(ctx.block(x, y, z))] { s.col[wi(x, y, z)] = 3 } } }

        // 1. Columns: vertical runs of logs standing on the ground, each measured over its whole height (full-height
        // reads, so every section that sees a run gives it the same foot, top, radius and taper).
        for z in -M..<(16 + M) { for x in -M..<(16 + M) {
            var y = -M
            while y < 16 + M {
                guard logC(x, y, z), y == -M || !logC(x, y - 1, z) else { y += 1; continue }
                var bot = y
                while bot > y - 64 && isLog[Int(ctx.column(x, bot - 1, z))] { bot -= 1 }
                var top = y
                while top < y + 64 && isLog[Int(ctx.column(x, top + 1, z))] { top += 1 }
                // P433 (Remington, Oct 24: "this giant log, which isn't the same log I hit, it morphed into something
                // else... the log just got wider"; "clearly algorithmically generated when they break"): a log struck
                // out of a trunk left two runs, and each was measured and classed on its own: the stump below lost
                // sight of the crown and became a post nearly a block wide, the part above hung in the air as cut
                // timber. A cut of one or two cells with the same upright trunk going on past it is one column still
                // (the same foot, top, height, taper and crown as before the blow); only the missing cells aren't drawn,
                // and the trunk shows a cut end at each side of the gap (ShapeTrunks.column).
                while bot > y - 60 {
                    let c = cutBelow(ctx, x, bot, z)
                    if c < 0 { break }
                    bot = c
                    while bot > y - 64 && isLog[Int(ctx.column(x, bot - 1, z))] { bot -= 1 }
                }
                while top < y + 60 {
                    let c = cutAbove(ctx, x, top, z)
                    if c < 0 { break }
                    top = c
                    while top < y + 64 && isLog[Int(ctx.column(x, top + 1, z))] { top += 1 }
                }
                let H = top - bot + 1
                let under = Int(ctx.column(x, bot - 1, z))
                // P433: a trunk lifted on its roots (a mangrove) stands on them.
                let onRoots = rootFoot(ctx, x, bot, z)
                let grounded = onRoots || !isTrunk[under] && !leafT[under] && (opaqueT[under] || collideT[under])
                let vertical = axisOf[Int(ctx.column(x, bot, z))] == 1
                // PG4 ("birch trees get real birch shapes, not random procedural sticks"): an upright run of 3+ that
                // springs from the side of another trunk (a birch's twin stem, the upper half of a kinked birch) is a
                // trunk of its own too, joined at its foot (column), not a chain of ever thinner limbs.
                let joined = !grounded && vertical && H >= 3 && !leafT[under] && sideLog(ctx, x, bot, z) != nil
                var kind: UInt8 = 0
                if grounded || joined {
                    // A living tree has leaves round the top of its column (or where its lean carries the crown).
                    var crown = false
                    // P398 (a): an acacia's 2-log foot leans on diagonally (its crown sits on the lean): a living
                    // trunk too, so the leaning logs become its limbs instead of a stack of cut stumps.
                    if H >= 3 && vertical || H == 2 && vertical && leansOn(ctx, x, top, z) {
                        scan: for dy in -2...6 { for dz in -4...4 { for dx in -4...4 where leafT[Int(ctx.column(x + dx, top + dy, z + dz))] { crown = true; break scan } } }
                    }
                    if crown { kind = 1 }
                    else if joined { kind = 0 }
                    else if H <= 2 && rootBeside(ctx, x, bot, z) && !fallenRun(ctx, x, bot, z) { kind = 3 }     // a root beside a trunk's foot (upright or lying)
                    else if !vertical || H == 1 && lyingBeside(ctx, x, bot, z) { kind = 0 }   // a log lying on the ground
                    else if vertical && onRoots { kind = 4 }                           // P433: a mangrove's stump on its roots
                    else if H <= 2 && SmoothTerrain.natural[under] { kind = 4 }    // P297: a tree's stump on the ground
                    // P433: a taller crownless trunk on natural ground with nothing built against it is a felled
                    // tree's stump too (its top fell away as one body), as thick as the tree it was; a post of a
                    // building (a log with a wall or floor beside it) keeps its full timber.
                    else if vertical && SmoothTerrain.natural[under] && !builtBeside(ctx, x, bot, top, z) { kind = 4 }
                    else { kind = 2 }                                               // a post (built timber)
                    if kind != 0 {
                        let rb: Float = kind == 1 ? treeRadius(H) : (kind == 4 ? treeRadius(max(5, H + 4)) : 0.45)
                        for yy in max(y, -M)...min(top, 15 + M) where logC(x, yy, z) {      // (P433: not the cut's cells)
                            let i = wi(x, yy, z)
                            s.col[i] = kind
                            let t = (Float(yy - bot) + 0.5) / Float(H)
                            s.rad[i] = kind == 1 ? rb * (1 - 0.45 * t) : (kind == 3 ? 0.3 : rb)
                            if kind == 1 { s.dist[i] = 0 }
                        }
                    }
                }
                y = top + 1
            }
        } }

        // 2. Branches: breadth-first from the living columns through touching logs (up to M steps).
        let q = s.queue
        q.count = 0
        for i in 0..<n where s.dist[i] == 0 { q.append(Int32(i)) }
        var head = 0
        while head < q.count {
            let i = Int(q.ptr[head]); head += 1
            let d = s.dist[i]
            if d >= Int16(M) { continue }
            let x = i % W - M, z = (i / W) % W - M, y = i / (W * W) - M
            for (dx, dy, dz) in ShapeTrunks.steps {
                let nx = x + dx, ny = y + dy, nz = z + dz
                guard nx >= -M && ny >= -M && nz >= -M && nx < 16 + M && ny < 16 + M && nz < 16 + M else { continue }
                let j = wi(nx, ny, nz)
                guard s.dist[j] < 0 && (s.col[j] == 0 || s.col[j] == 3) && log(nx, ny, nz) && !fallenRun(ctx, nx, ny, nz) else { continue }
                // Breadth-first with face steps before edge and corner steps: a cell takes the nearest joint as its parent.
                s.dist[j] = d + 1
                s.par[j] = Int32(i)
                s.kids[i] &+= 1
                let pr = s.rad[i] > 0 ? s.rad[i] : 0.2
                // (P398 a: the trunk leaning on up from its column's top keeps the trunk's thickness)
                var lean = dy == 1 && (dx != 0 || dz != 0)
                if lean && d == 0 { lean = !log(x, y + 1, z) }
                else if lean, s.par[i] >= 0 {
                    let gp = Int(s.par[i])
                    let px = gp % W - M, pz = (gp / W) % W - M, py = gp / (W * W) - M
                    lean = y - py == 1 && (x != px || z != pz)
                }
                // (P433: a root block's run keeps more of its width each step: prop roots are near the trunk's thickness)
                let rootCell = isRoot[Int(ctx.block(nx, ny, nz))]
                s.rad[j] = rootCell ? max(0.1, min(0.24, pr * (d == 0 ? 0.72 : 0.84)))
                    : max(0.07, s.col[j] == 3 ? pr * 0.7 : (lean ? pr * 0.92 : (d == 0 ? min(0.3, pr * 0.62) : pr * 0.8)))
                q.append(Int32(j))
            }
        }

        // 3. Geometry for the owned logs.
        // Mid sections (lod 2) use fewer sides and leave out the joint knobs and tips; far ones (lod 1) fewer still.
        let sides = ctx.lod == 0 ? 9 : (ctx.lod == 2 ? 6 : 5)
        let limbSides = ctx.lod == 0 ? 6 : (ctx.lod == 2 ? 5 : 4)
        for y in 0..<16 { for z in 0..<16 { for x in 0..<16 {
            let b = ctx.R[ctx.ri(x, y, z)]
            guard isTrunk[Int(b)] else { continue }
            let i = wi(x, y, z)
            // (P433: a root block wears its tree's bark, not its own see-through root texture)
            let base = Int(Blocks.groupBase[Int(isRoot[Int(b)] ? treeOf(ctx, s, i) : b)])
            let bark = Int(Blocks.tex[base * 6]), rings = Int(Blocks.tex[base * 6 + 2])
            if isRoot[Int(b)] && !(s.dist[i] > 0 && s.par[i] >= 0) {
                rootStub(ctx, x, y, z, bark: bark, sides: limbSides)                 // (a root left when its tree is gone)
            } else if s.col[i] == 1 || s.col[i] == 2 || s.col[i] == 4 {
                column(ctx, s, x, y, z, bark: bark, rings: rings, sides: sides)
            } else if s.dist[i] > 0 && s.par[i] >= 0 {
                limb(ctx, s, i, x, y, z, bark: bark, rings: rings, sides: limbSides)
            } else if leafy(ctx, x, y, z) {
                bough(ctx, x, y, z, axis: timberAxis(ctx, b, x, y, z), bark: bark, sides: limbSides)
            } else {
                timber(ctx, x, y, z, axis: timberAxis(ctx, b, x, y, z), bark: bark, rings: rings, sides: sides)
            }
        } } }
    }

    // P433: a cut in an upright trunk: 1-2 air cells under `bot` (over `top`) with an upright log past them. The log
    // cell past the cut, or -1.
    static func cutBelow(_ ctx: DetailContext, _ x: Int, _ bot: Int, _ z: Int) -> Int {
        guard axisOf[Int(ctx.column(x, bot, z))] == 1 else { return -1 }
        var c = bot - 1, gap = 0
        while gap < 2 && ctx.column(x, c, z) == AIR { gap += 1; c -= 1 }
        guard gap > 0 else { return -1 }
        let b = ctx.column(x, c, z)
        return isLog[Int(b)] && axisOf[Int(b)] == 1 ? c : -1
    }
    static func cutAbove(_ ctx: DetailContext, _ x: Int, _ top: Int, _ z: Int) -> Int {
        guard axisOf[Int(ctx.column(x, top, z))] == 1 else { return -1 }
        var c = top + 1, gap = 0
        while gap < 2 && ctx.column(x, c, z) == AIR { gap += 1; c += 1 }
        guard gap > 0 else { return -1 }
        let b = ctx.column(x, c, z)
        return isLog[Int(b)] && axisOf[Int(b)] == 1 ? c : -1
    }
    // P433: something built (not ground, log, leaf or plant) against a run's side at any of its heights.
    static func builtBeside(_ ctx: DetailContext, _ x: Int, _ bot: Int, _ top: Int, _ z: Int) -> Bool {
        for yy in bot...top { for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let b = Int(ctx.column(x + dx, yy, z + dz))
            if b == 0 || isTrunk[b] || Mesher.leafT[b] || SmoothTerrain.natural[b] { continue }
            let k = ShapeClass.kind[b]
            if k == .foliage || k == .terrain { continue }
            if Blocks.collide[b] || Blocks.opaque[b] { return true }
        } }
        return false
    }

    // P433: a trunk's foot held up by root blocks: one straight under it, or under a face side (a mangrove's prop roots
    // leave the foot log diagonally down).
    static func rootFoot(_ ctx: DetailContext, _ x: Int, _ bot: Int, _ z: Int) -> Bool {
        if isRoot[Int(ctx.column(x, bot - 1, z))] { return true }
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where isRoot[Int(ctx.column(x + dx, bot - 1, z + dz))] { return true }
        return false
    }
    // P433: the log a root cell grows from (up its parents to the first non-root cell), or the cell's own block.
    static func treeOf(_ ctx: DetailContext, _ s: Scratch, _ i: Int) -> BlockID {
        var j = i, n = 0
        while n < 16 {
            let p = Int(s.par[j])
            guard p >= 0 else { break }
            let b = ctx.block(p % W - M, p / (W * W) - M, (p / W) % W - M)
            if !isRoot[Int(b)] { return b }
            j = p; n += 1
        }
        // (no tree reached: the wood the root block is named for, mangrove roots -> mangrove log)
        let own = ctx.block(i % W - M, i / (W * W) - M, (i / W) % W - M)
        let k = Blocks.key(own)
        if let r = k.range(of: "_roots"), Blocks.has(String(k[..<r.lowerBound]) + "_log") { return Blocks.id(String(k[..<r.lowerBound]) + "_log") }
        return own
    }
    // P433: a root block no tree reaches (its trunk chopped away): a short root arching from the cell down into the ground.
    // (A stack of them is one root standing down into the ground: the hook only on the top cell, the tip only on the bottom one.)
    static func rootStub(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int, bark: Int, sides: Int) {
        let c = SIMD3<Float>(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
        let up = isRoot[Int(ctx.block(x, y + 1, z))], down = isRoot[Int(ctx.block(x, y - 1, z))]
        let th = ctx.hash(x, y, z, 0x2033) * 6.28
        let out = SIMD3<Float>(cosf(th), 0, sinf(th))
        let r: Float = 0.13
        if up {
            tube(ctx, c + SIMD3(0, 0.5, 0), c, r, r, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: x &* 7 &+ y &* 13 &+ z))
        } else {
            tube(ctx, c + SIMD3(0, 0.2, 0) - out * 0.3, c, 0.04, r, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: x &* 7 &+ y &* 13 &+ z))
        }
        if down {
            tube(ctx, c, c - SIMD3(0, 0.5, 0), r, r, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: x &* 5 &+ z))
        } else {
            let ground = ctx.groundTop(x, y - 1, z, reach: 2) ?? Float(y)
            tube(ctx, c, SIMD3(c.x, min(c.y - 0.6, ground - 0.3), c.z) + out * 0.35, r, 0.08, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: x &* 5 &+ z))
        }
    }

    // P398 (a): a log leans on from a column's top: a log one up and to the side (an acacia's lean), none straight up.
    static func leansOn(_ ctx: DetailContext, _ x: Int, _ top: Int, _ z: Int) -> Bool {
        guard !isTrunk[Int(ctx.column(x, top + 1, z))] else { return false }
        for dz in -1...1 { for dx in -1...1 where (dx != 0 || dz != 0) && isTrunk[Int(ctx.column(x + dx, top + 1, z + dz))] { return true } }
        return false
    }

    // P297 (d): a living trunk's radius at its foot by its height (5 tall: 0.24, 10: 0.31, 14+: 0.37), the taper takes
    // it to about half at the crown. (Was 0.25 + 0.016 H up to 0.44: a 5-block oak 2/3 of a block across.)
    @inline(__always) static func treeRadius(_ H: Int) -> Float { 0.17 + 0.014 * Float(min(H, 14)) }
    // Fallen trunks and the boughs nothing reaches.
    static let fallenRadius: Float = 0.26
    // P297 (a): leaves round a log (3x3x3): a log in a crown.
    static func leafy(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        var n = 0
        for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where Mesher.leafT[Int(ctx.block(x + dx, y + dy, z + dz))] {
            n += 1
            if n >= 3 { return true }
        } } }
        return false
    }

    // Neighbour steps, faces first, then edges, then corners (the breadth-first walk prefers the closest joint).
    static let steps: [(Int, Int, Int)] = {
        var r: [(Int, Int, Int)] = []
        for k in 1...3 { for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where abs(dx) + abs(dy) + abs(dz) == k { r.append((dx, dy, dz)) } } } }
        return r
    }()

    // A short log beside a trunk's foot (the generator's root flare): a log beside it at the same height whose column
    // stands 4+ tall.
    static func rootBeside(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 {
            var h = 0
            while h < 4 && isTrunk[Int(ctx.column(x + dx, y + h, z + dz))] { h += 1 }
            if h >= 4 { return true }
        } }
        return false
    }
    // PG4: the trunk log a run's foot grows out of sideways: a face neighbour at the foot's height or one below
    // (offset from the foot, in blocks), nil when there is none.
    static func sideLog(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int) -> SIMD3<Int>? {
        for dy in [0, -1] { for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where isTrunk[Int(ctx.column(x + dx, y + dy, z + dz))] {
            return SIMD3(dx, dy, dz)
        } }
        return nil
    }
    // A single upright log with a log beside it at its height and none above or below: one block of a log lying on the
    // ground (the generators write fallen trunks in the upright state).
    static func lyingBeside(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where isTrunk[Int(ctx.column(x + dx, y, z + dz))] { return true }
        return false
    }
    // The axis a lone log lies along: its own axis state, or (upright state, nothing above or below) the way its
    // neighbours run.
    static func timberAxis(_ ctx: DetailContext, _ b: BlockID, _ x: Int, _ y: Int, _ z: Int) -> Int {
        let a = Int(axisOf[Int(b)])
        if a != 1 { return a }
        if isTrunk[Int(ctx.block(x, y + 1, z))] || isTrunk[Int(ctx.block(x, y - 1, z))] { return 1 }
        if isTrunk[Int(ctx.block(x + 1, y, z))] || isTrunk[Int(ctx.block(x - 1, y, z))] { return 0 }
        if isTrunk[Int(ctx.block(x, y, z + 1))] || isTrunk[Int(ctx.block(x, y, z - 1))] { return 2 }
        return 1
    }

    // MARK: Columns

    // The column's centre line at a height (section-local x, z of the cell's centre plus a lean that wanders with world
    // height): living trees only.
    @inline(__always) static func lean(_ ctx: DetailContext, _ cx: Float, _ cz: Float, _ y: Float, living: Bool) -> SIMD2<Float> {
        guard living else { return SIMD2(cx, cz) }
        let p = SIMD3<Float>(cx, y, cz)
        return SIMD2(cx + 0.07 * ctx.noise(p, 0.23, 0x1EA1), cz + 0.07 * ctx.noise(p, 0.23, 0x1EA2))
    }

    static func column(_ ctx: DetailContext, _ s: Scratch, _ x: Int, _ y: Int, _ z: Int, bark: Int, rings: Int, sides: Int) {
        let i = wi(x, y, z)
        let living = s.col[i] == 1, stump = s.col[i] == 4
        // 2x2 trunks: one fat trunk round the cluster's centre, drawn by its lowest corner. Only living columns make the
        // cluster: a root flare beside a 2x2 foot is a column too (kind 3), and counting it made a block-wide square of
        // trunk + roots look like a second and third 2x2, each drawn as a fat trunk stub a block off the real one.
        // (Remington, Oct 20: "why's that stump fucked up": two fat cut-off stubs at a dark oak's foot.)
        var cx = Float(x) + 0.5, cz = Float(z) + 0.5, scale: Float = 1
        func colAt(_ a: Int, _ b: Int) -> Bool { a >= -M && b >= -M && a < 16 + M && b < 16 + M && s.col[wi(a, y, b)] == 1 }
        if living {
            for (ox, oz) in [(0, 0), (-1, 0), (0, -1), (-1, -1)] {
                let ax = x + ox, az = z + oz
                if colAt(ax, az) && colAt(ax + 1, az) && colAt(ax, az + 1) && colAt(ax + 1, az + 1) {
                    if ox != 0 || oz != 0 { return }              // another corner draws it
                    cx = Float(x) + 1; cz = Float(z) + 1; scale = 2.15
                    break
                }
            }
        }
        let r = s.rad[i] * scale
        let below = y - 1 >= -M ? s.col[wi(x, y - 1, z)] != 0 : true
        let above = y + 1 < 16 + M ? s.col[wi(x, y + 1, z)] != 0 : true
        let rBelow = below && y - 1 >= -M ? s.rad[wi(x, y - 1, z)] * scale : r
        let rAbove = above && y + 1 < 16 + M ? s.rad[wi(x, y + 1, z)] * scale : r
        let r0 = (r + rBelow) * 0.5, r1 = (r + rAbove) * 0.5
        let y0 = Float(y), y1 = Float(y + 1)
        var prof: [(Float, Float)] = []              // (height, radius) from the bottom up
        // PG4: a living trunk whose foot is on another trunk's side (no ground under it) grows out of that trunk: no
        // root flare, its foot sunk into a short bough from the other trunk's centre.
        let footCell = Int(ctx.block(x, y - 1, z))
        let onGround = !isTrunk[footCell] && (Blocks.opaque[footCell] || Blocks.collide[footCell])
        var flatFoot = !below
        // P433: a trunk lifted on its roots (a mangrove): its foot closes in a rounded bark underside between the roots,
        // not a flat cut end or a bough from a neighbouring trunk.
        let lifted = !below && !onGround && (living || stump) && rootFoot(ctx, x, y, z)
        if lifted {
            prof.append((y0 - 0.3, r * 0.45)); prof.append((y0 - 0.08, r * 0.9)); prof.append((y0 + 0.25, r))
            flatFoot = false
        } else if !below && living && !onGround, let o = sideLog(ctx, x, y, z) {
            let from = SIMD3<Float>(Float(x + o.x) + 0.5, Float(y + o.y) + 0.5, Float(z + o.z) + 0.5)
            let to = SIMD3<Float>(cx, y0 + 0.35, cz)
            tube(ctx, from, to, r * 0.95, r, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: x &* 31 &+ z))
            prof.append((y0 + 0.2, r))
            flatFoot = false
        } else if !below && (living || stump) && onGround {
            // Root flare into the ground (the smooth ground covers its foot).
            // (The flare is a fixed width past the trunk, so a wide 2x2 foot doesn't spread into a skirt.)
            // P297 (a): down to the drawn ground's lowest point round the foot (a trunk on a slope stood on its uphill
            // side with its foot showing over the downhill one).
            // (Straight down below the flare, so a deep foot reads as the trunk going into the ground, not a cone.)
            var foot = y0 - 0.5
            if let lo = ctx.groundTop(x, y, z, reach: 3, lowest: true) { foot = max(y0 - 2.5, min(foot, lo - 0.3)) }
            if foot < y0 - 0.55 { prof.append((foot, r + 0.24)) }
            prof.append((y0 - 0.5, r + 0.3)); prof.append((y0 + 0.02, r + 0.19)); prof.append((y0 + 0.3, r + 0.09)); prof.append((y0 + 0.7, r + 0.02))
            flatFoot = false
        } else {
            prof.append((y0, r0))
        }
        // P433: a living trunk's top at a cut (the struck cell's air over it, the trunk going on past it) is a flat
        // cut end showing the rings, not the rounded tip under a crown.
        let cutTop = !above && living && !isTrunk[Int(ctx.column(x, y + 1, z))] && cutAbove(ctx, x, y, z) >= 0
        if above {
            prof.append((y1, r1))
        } else if living && !cutTop {
            prof.append((y1 - 0.15, r * 0.8)); prof.append((y1 + 0.05, r * 0.45)); prof.append((y1 + 0.15, 0.02))
        } else {
            prof.append((y1, r0))
        }
        let roots = !below && (living || stump) && onGround
        let wrap = max(1, (2 * .pi * r).rounded())          // bark repeats round the trunk (one count for every ring)
        var prev: [SIMD3<Float>] = [], prevN: [SIMD3<Float>] = [], bottom: [SIMD3<Float>] = []
        for (k, (h, rr)) in prof.enumerated() {
            let c = lean(ctx, cx, cz, h, living: living)
            var ps: [SIMD3<Float>] = [], ns: [SIMD3<Float>] = []
            for a in 0...sides {
                let th = Float(a % sides) / Float(sides) * 2 * .pi
                let d = SIMD3<Float>(cosf(th), 0, sinf(th))
                var rad = rr
                let wpt = SIMD3<Float>(c.x, h, c.y) + d * rr
                rad *= 1 + (living ? 0.07 : 0.03) * ctx.noise(wpt, 2.1, 0xBA4C)
                if roots && k < 4 { rad = r + (rad - r) * (1 + 1.6 * max(0, cosf(th * 3 + ctx.hash(x, 0, z, 0x2007) * 6.28))) }
                ps.append(SIMD3(c.x, h, c.y) + d * rad)
                ns.append(d)
            }
            if k > 0 {
                let (h0, rr0) = prof[k - 1]
                let slope = (rr0 - rr) / max(0.05, h - h0)
                for a in 0..<sides {
                    let u0 = Float(a) / Float(sides) * wrap, u1 = Float(a + 1) / Float(sides) * wrap
                    let n00 = simd_normalize(prevN[a] + SIMD3(0, slope, 0)), n01 = simd_normalize(prevN[a + 1] + SIMD3(0, slope, 0))
                    let n10 = simd_normalize(ns[a] + SIMD3(0, slope, 0)), n11 = simd_normalize(ns[a + 1] + SIMD3(0, slope, 0))
                    let top = h > y1 + 0.01 && !above
                    let lay = top && h - h0 < 0.12 && !living ? rings : bark
                    // Counter-clockwise from outside (the angle runs clockwise seen from outside, so a+1 comes first):
                    // bottom a+1, bottom a, top a, top a+1. PG4 (Oct 13 21:34, "it's constantly showing you the inside
                    // of the trunk"): these went round the other way, so back-face culling kept each trunk's far inside
                    // wall and dropped its near bark.
                    ctx.vertex(prev[a + 1], n01, SIMD2(u1, -h0), layer: lay)
                    ctx.vertex(prev[a], n00, SIMD2(u0, -h0), layer: lay)
                    ctx.vertex(ps[a], n10, SIMD2(u0, -h), layer: lay)
                    ctx.vertex(ps[a + 1], n11, SIMD2(u1, -h), layer: lay)
                }
            }
            if k == 0 { bottom = ps }
            prev = ps; prevN = ns
        }
        if lifted {
            let c = lean(ctx, cx, cz, prof[0].0, living: living)
            cap(ctx, center: SIMD3(c.x, prof[0].0, c.y), pts: bottom.reversed(), normal: SIMD3(0, -1, 0), layer: bark)
        }
        // A cut top (timber, a stump, a living trunk at a struck cell): a flat end showing the rings.
        if !above && (!living || cutTop) {
            let c = SIMD2<Float>(cx, cz)
            cap(ctx, center: SIMD3(c.x, y1, c.y), pts: prev, normal: SIMD3(0, 1, 0), layer: rings)
        }
        if flatFoot {
            var ps: [SIMD3<Float>] = []
            for a in 0...sides {
                let th = Float(a % sides) / Float(sides) * 2 * .pi
                ps.append(SIMD3(cx + cosf(th) * r0, y0, cz + sinf(th) * r0))
            }
            cap(ctx, center: SIMD3(cx, y0, cz), pts: ps.reversed(), normal: SIMD3(0, -1, 0), layer: rings)
        }
    }

    // A flat end: a fan of triangles (degenerate quads) from the centre, rings texture projected across it.
    static func cap(_ ctx: DetailContext, center: SIMD3<Float>, pts: [SIMD3<Float>], normal: SIMD3<Float>, layer: Int) {
        // Texture: the end texture projected along the normal's axis, centred on the block.
        let ax = abs(normal.x) > 0.5 ? 0 : (abs(normal.y) > 0.5 ? 1 : 2)
        func uv(_ p: SIMD3<Float>) -> SIMD2<Float> {
            let q = p - floor(center)
            switch ax { case 0: return SIMD2(q.z, -q.y); case 1: return SIMD2(q.x, q.z); default: return SIMD2(q.x, -q.y) }
        }
        for a in 0..<(pts.count - 1) {
            ctx.vertex(center, normal, uv(center), layer: layer)
            ctx.vertex(pts[a + 1], normal, uv(pts[a + 1]), layer: layer)
            ctx.vertex(pts[a], normal, uv(pts[a]), layer: layer)
            ctx.vertex(pts[a], normal, uv(pts[a]), layer: layer)
        }
    }

    // MARK: Limbs

    // The centre of window cell j.
    @inline(__always) static func centre(_ j: Int) -> SIMD3<Float> {
        SIMD3(Float(j % W - M) + 0.5, Float(j / (W * W) - M) + 0.5, Float((j / W) % W - M) + 0.5)
    }

    // U1 ("polygon trees with real round branches"; diagonal branches read as ladders): where a limb passes through a
    // cell on its way out. A branch the generator stepped diagonally goes x, then y, then x... one face at a time, and a
    // tube from each cell's centre to the next drew that staircase. A limb cell's joint is the midpoint between its
    // centre and its parent's, so the joints of a staircase lie on its diagonal and the tubes between them run straight.
    // On a trunk the joint is the trunk's (leaning) centre line.
    static func joint(_ ctx: DetailContext, _ s: Scratch, _ j: Int) -> SIMD3<Float> {
        var c = centre(j)
        if s.col[j] == 1 || s.col[j] == 2 || s.col[j] == 4 {
            let l = lean(ctx, c.x, c.z, c.y, living: s.col[j] == 1)
            c.x = l.x; c.z = l.y
            return c
        }
        let p = Int(s.par[j])
        guard p >= 0 else { return c }
        let pc = s.col[p] == 1 || s.col[p] == 2 || s.col[p] == 4 ? joint(ctx, s, p) : centre(p)
        return (c + pc) * 0.5
    }

    static func limb(_ ctx: DetailContext, _ s: Scratch, _ i: Int, _ x: Int, _ y: Int, _ z: Int, bark: Int, rings: Int, sides: Int) {
        let p = Int(s.par[i])
        // P297 (a): a root (the generator's log beside a trunk's foot) leaves the trunk low and runs down into the drawn
        // ground, its tip under the surface. (It was a level limb at mid-block ending in a point in the air.)
        if s.col[i] == 3 && s.kids[i] == 0 {
            root(ctx, s, i, p, x, y, z, bark: bark, sides: sides)
            return
        }
        let a = joint(ctx, s, p)
        // Through the cell to its own joint, or (a twig's last cell, nothing growing on) to its centre.
        let b = s.kids[i] > 0 ? joint(ctx, s, i) : SIMD3<Float>(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
        let ra = s.col[p] != 0 ? min(s.rad[p], s.rad[i] * 1.25) : s.rad[p]
        let rb = s.rad[i]
        tube(ctx, a, b, ra, rb, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: i))
        // Knuckle where limbs meet, so joints read as wood growing on, not pipes meeting.
        if ctx.lod != 0 { return }
        if s.kids[i] > 0 { knob(ctx, b, rb * 1.05, bark: bark, sides: sides) }
        else if s.col[i] == 3 {
            // A root: it turns down into the ground.
            let d = simd_normalize(simd_normalize(b - a) + SIMD3(0, -1.3, 0))
            knob(ctx, b, rb * 1.02, bark: bark, sides: sides)
            tube(ctx, b, b + d * 0.55, rb, rb * 0.5, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: i) ^ 0x2007)
        } else {
            // A tip: the limb runs on past the block's centre and tapers off.
            let d = simd_normalize(b - a)
            tube(ctx, b, b + d * 0.38, rb, 0.02, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: i) ^ 0x7177)
        }
    }

    static func root(_ ctx: DetailContext, _ s: Scratch, _ i: Int, _ p: Int, _ x: Int, _ y: Int, _ z: Int, bark: Int, sides: Int) {
        let pj = joint(ctx, s, p)
        let ground = ctx.groundTop(x, y - 1, z, reach: 2) ?? Float(y)
        let rb = s.rad[i]
        // From low on the trunk (a quarter block up its foot cell) out to the root's cell, where it meets the ground.
        // (P433: a root block's run leaves its parent root where that one's limb ends.)
        let fromRoot = s.col[p] == 3
        let a = fromRoot ? pj : SIMD3<Float>(pj.x, Float(Int(floor(pj.y))) + 0.3, pj.z)
        var b = SIMD3<Float>(Float(x) + 0.5, min(Float(y) + 0.45, ground + rb * 0.35), Float(z) + 0.5)
        b.y = max(b.y, a.y - 1.2)
        let ra = min(s.rad[p], rb * 1.4)
        tube(ctx, a, b, ra, rb, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: i))
        if ctx.lod != 0 { return }
        knob(ctx, b, rb * 1.02, bark: bark, sides: sides)
        // On out and down under the surface.
        var out = SIMD3<Float>(b.x - a.x, 0, b.z - a.z)
        out = simd_length(out) > 1e-4 ? simd_normalize(out) : SIMD3(1, 0, 0)
        let tip = b + out * 0.4 + SIMD3(0, -max(0.45, b.y - ground + 0.35), 0)
        tube(ctx, b, tip, rb, rb * 0.35, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: i) ^ 0x2007)
    }

    // P297 (a): a log in a crown that no limb walk reaches (a bough cut off from its tree by the window, a crown over a
    // felled trunk's stump): a thin branch along its axis tapering at both ends, never a thick cut log hanging in the
    // leaves.
    static func bough(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int, axis: Int, bark: Int, sides: Int) {
        let c = SIMD3<Float>(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
        var d = SIMD3<Float>(0, 0, 0); d[axis] = 1
        var step = SIMD3<Int>(0, 0, 0); step[axis] = 1
        let on = isTrunk[Int(ctx.block(x + step.x, y + step.y, z + step.z))]
        let back = isTrunk[Int(ctx.block(x - step.x, y - step.y, z - step.z))]
        let r: Float = 0.11
        tube(ctx, c - d * 0.5, c, back ? r : 0.03, r, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: x &* 7 &+ y &* 13 &+ z))
        tube(ctx, c, c + d * 0.5, r, on ? r : 0.03, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: x &* 11 &+ y &* 3 &+ z))
    }

    // A tapered tube from a (radius ra) to b (radius rb), bark wrapped round it.
    static func tube(_ ctx: DetailContext, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ ra: Float, _ rb: Float, bark: Int, sides: Int, salt: UInt32) {
        let ax = b - a
        let len = simd_length(ax)
        guard len > 1e-3 else { return }
        let d = ax / len
        let ref = abs(d.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let e1 = simd_normalize(simd_cross(ref, d)), e2 = simd_cross(d, e1)
        let slope = (ra - rb) / len
        let U = max(1, (2 * .pi * max(ra, rb)).rounded())
        for k in 0..<sides {
            let t0 = Float(k) / Float(sides) * 2 * .pi, t1 = Float(k + 1) / Float(sides) * 2 * .pi
            let r0 = e1 * cosf(t0) + e2 * sinf(t0), r1 = e1 * cosf(t1) + e2 * sinf(t1)
            let n0 = simd_normalize(r0 + d * slope), n1 = simd_normalize(r1 + d * slope)
            let u0 = Float(k) / Float(sides) * U, u1 = Float(k + 1) / Float(sides) * U
            ctx.vertex(a + r0 * ra, n0, SIMD2(u0, 0), layer: Int(bark))
            ctx.vertex(a + r1 * ra, n1, SIMD2(u1, 0), layer: Int(bark))
            ctx.vertex(b + r1 * rb, n1, SIMD2(u1, -len), layer: Int(bark))
            ctx.vertex(b + r0 * rb, n0, SIMD2(u0, -len), layer: Int(bark))
        }
    }

    // A small rounded lump (an octahedron-ish ball) where limbs join.
    static func knob(_ ctx: DetailContext, _ c: SIMD3<Float>, _ r: Float, bark: Int, sides: Int) {
        let rows = 2
        for j in 0..<rows {
            let p0 = Float(j) / Float(rows) * .pi - .pi / 2, p1 = Float(j + 1) / Float(rows) * .pi - .pi / 2
            for k in 0..<sides {
                let t0 = Float(k) / Float(sides) * 2 * .pi, t1 = Float(k + 1) / Float(sides) * 2 * .pi
                func pt(_ ph: Float, _ th: Float) -> SIMD3<Float> { SIMD3(cosf(ph) * cosf(th), sinf(ph), cosf(ph) * sinf(th)) }
                let a = pt(p0, t0), b = pt(p0, t1), cc = pt(p1, t1), d = pt(p1, t0)
                // (Counter-clockwise from outside, as the trunk walls: PG4.)
                ctx.vertex(c + b * r, b, SIMD2(Float(k + 1) * 0.3, p0), layer: bark)
                ctx.vertex(c + a * r, a, SIMD2(Float(k) * 0.3, p0), layer: bark)
                ctx.vertex(c + d * r, d, SIMD2(Float(k) * 0.3, p1), layer: bark)
                ctx.vertex(c + cc * r, cc, SIMD2(Float(k + 1) * 0.3, p1), layer: bark)
            }
        }
    }

    // MARK: Timber

    // A log on its own (a cabin wall, a fallen trunk, a pile): round along its axis, flat cut ends where the run stops.
    // P441 (Oct 24 20:53: "this log spawned hovering"; 20:51: "see how that turned into branches... no more algorithmic
    // log generation like that"): a log lying on the ground in a run of 3 or more along its axis is a fallen trunk. Lying
    // against a tree's foot it was taken for one of the tree's roots or limbs and drawn thin at the block's middle
    // height, over the drawn ground; now it is never reached from a tree and lies bedded in the ground (timber).
    static func fallenRun(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        let b = ctx.block(x, y, z)
        let a = Int(axisOf[Int(b)])
        guard isTrunk[Int(b)], a != 1, SmoothTerrain.natural[Int(ctx.block(x, y - 1, z))] else { return false }
        let sx = a == 0 ? 1 : 0, sz = a == 2 ? 1 : 0
        var n = 1
        for sgn in [1, -1] {
            for k in 1...2 {
                let c = ctx.block(x + sx * k * sgn, y, z + sz * k * sgn)
                guard isTrunk[Int(c)] && Int(axisOf[Int(c)]) == a else { break }
                n += 1
            }
        }
        return n >= 3
    }

    static func timber(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int, axis: Int, bark: Int, rings: Int, sides: Int) {
        let o = SIMD3<Float>(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
        var d = SIMD3<Float>(0, 0, 0); d[axis] = 1
        var step = SIMD3<Int>(0, 0, 0); step[axis] = 1
        let next = ctx.block(x + step.x, y + step.y, z + step.z), prev = ctx.block(x - step.x, y - step.y, z - step.z)
        var r: Float = 0.46
        var a = o - d * 0.5, b = o + d * 0.5
        // PG4 ("fallen logs sit on the ground, none floating"): a lying log on natural ground with nothing stacked on it
        // (a fallen trunk, not a cabin's bottom course) beds into the ground; the drawn ground dips below the block
        // tops round it, and a round log only touched them along one line.
        // P297 (d, a): a fallen trunk is a tree's thickness (built timber keeps nearly the whole block, so a cabin's walls
        // stay closed), and it lies along the drawn ground itself, bedded a little: each end at the ground between this
        // block and the next (the same height the next block's piece starts at, so the trunk bends with the slope unbroken).
        if axis != 1 && SmoothTerrain.natural[Int(ctx.block(x, y - 1, z))] && !isTrunk[Int(ctx.block(x, y + 1, z))] {
            r = fallenRadius
            let lift = r * 0.8
            let g0 = ctx.groundTop(x, y - 1, z, reach: 2) ?? Float(y)
            func end(_ nb: BlockID, _ sx: Int) -> Float {
                var g = g0
                if isTrunk[Int(nb)], let gn = ctx.groundTop(x + step.x * sx, y - 1, z + step.z * sx, reach: 2) { g = (g0 + gn) * 0.5 }
                return max(Float(y) - 1, min(Float(y) + 0.5, g + lift))
            }
            a.y = end(prev, -1); b.y = end(next, 1)
        }
        tube(ctx, a, b, r, r, bark: bark, sides: sides, salt: 0)
        let e1v: SIMD3<Float> = axis == 1 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        let e2v = simd_cross(d, e1v)
        func ring(_ c: SIMD3<Float>) -> [SIMD3<Float>] {
            (0...sides).map { k in let t = Float(k % sides) / Float(sides) * 2 * .pi; return c + (e1v * cosf(t) + e2v * sinf(t)) * r }
        }
        if !(isTrunk[Int(next)] && axisOf[Int(next)] == UInt8(axis)) { cap(ctx, center: b, pts: ring(b).reversed(), normal: d, layer: rings) }
        if !(isTrunk[Int(prev)] && axisOf[Int(prev)] == UInt8(axis)) { cap(ctx, center: a, pts: ring(a), normal: -d, layer: rings) }
    }
}
