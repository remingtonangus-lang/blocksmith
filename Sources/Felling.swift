import Foundation
import simd

// P298 (Oct 15 11:53-11:54, "break the base and the tree falls over, and carry the logs as whole objects").
//   the cut     breaking a log under a tree (logs above it with their leaves, resting on nothing else) fells it: the
//               trunk and crown come loose as one body (a Ship named Felled Tree, held upright by nothing) and topple
//               away from the woodsman with a creak, then land with a crash and a rustle of leaves.
//   the crown   stays on the fallen tree, branches and leaves (P478; it used to drop away once the tree lay still).
//   the trunk   a fallen trunk is chopped where it lies (each log mined drops a log), or, up to 24 logs, picked up
//               with an empty hand (use) and carried in front of you as a whole; use again sets it down (thrown a
//               little the way you look). Logs float.
// Small cuts (under 3 logs or no leaves: stumps, beams, a log cabin wall standing on its sill) don't fell anything.
enum Felling {
    static let name = "Felled Tree"
    static let maxLogs = 260, maxLeaves = 900
    static let carryMax = 24
    final class Fall {
        @WeakLink var ship: Ship? = nil
        var age: Float = 0
        var still: Float = 0
        var landed = false
        var lastVel = V3(0, 0, 0)
        // P441 (Oct 24 20:51: "the old version of it kind of hovers there for a second"): the body stays hidden and still
        // until the world has redrawn the sections it left (and its own mesh is in), then is let go as it was thrown.
        var wait: [(Chunk, Int, Int)] = []
        var launch = (V3(0, 0, 0), V3(0, 0, 0))
        var held: Float = -1
        var pushed = false
        var weight: Float = 0, sinceBlow: Float = 1   // (StructureImpact)
        var patient = false                     // (Nov 13, a collapse's pieces: no push, the workers' redraw is waited for)
        var over = V3(0, 0, 0)                  // (the axis a felled tree goes over about, away from the woodsman)
        init(_ s: Ship) { ship = s }
    }
    static var falls: [Fall] = []
    @WeakLink static var carried: Ship? = nil
    static var felled = 0                        // (counter)
    static var toppled = 0                       // (counter: P407's whole pieces)
    static var letLate = 0                       // (counter: bodies let go at the 4 s limit with the world not yet redrawn)
    static let oldPush = ProcessInfo.processInfo.environment["BS_OLDFELLPUSH"] == "1"
    static var pushWorstMs = 0.0, pushWorstSections = 0      // (harness: the most a frame's pushed remeshes took, and how many)
    static var worstMs = 0.0, worstSplit = ""   // (the soak: the slowest topple and its parts)

    static func isFelled(_ s: Ship) -> Bool { s.root.name == name }
    // (P504) Two cells of one trunk's section: within its 2x2 (a block apart on each axis at most).
    static func sameTrunk(_ a: IVec3, _ b: IVec3) -> Bool { abs(a.x - b.x) <= 1 && abs(a.z - b.z) <= 1 }
    // P478: whether a leaf is this tree's: no log of another tree (outside `logs`, above `above`, within 6 of them) is
    // nearer to it than the nearest of `logs`.
    static func ownLeaf(_ w: World, logs: Set<IVec3>, above: Int) -> (IVec3) -> Bool {
        guard let f = logs.first else { return { _ in true } }
        var lo = f, hi = f
        for c in logs { lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)); hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z)) }
        var others: [IVec3] = []
        for y in stride(from: max(above + 1, lo.y - 6), through: min(CH - 1, hi.y + 6), by: 1) { for z in (lo.z - 6)...(hi.z + 6) { for x in (lo.x - 6)...(hi.x + 6) {
            let c = IVec3(x, y, z)
            if !logs.contains(c) && CapitalBase.isLog(w.block(x, y, z)) { others.append(c) }
        } } }
        if others.isEmpty { return { _ in true } }
        let own = Array(logs)
        func d2(_ a: IVec3, _ b: IVec3) -> Int { let d = a - b; return d.x * d.x + d.y * d.y + d.z * d.z }
        return { q in
            var a = Int.max, b = Int.max
            for c in own { a = min(a, d2(q, c)) }
            for c in others { b = min(b, d2(q, c)); if b < a { return false } }
            return a <= b
        }
    }

    // The standing tree's girth from its tallest upright run of logs (ShapeTrunks.treeRadius, as the world drew it).
    static func girthOf(_ logs: Set<IVec3>) -> Float {
        var best = 0
        for c in logs where !logs.contains(IVec3(c.x, c.y - 1, c.z)) {
            var n = 1
            while logs.contains(IVec3(c.x, c.y + n, c.z)) { n += 1 }
            best = max(best, n)
        }
        return best >= 3 ? ShapeTrunks.treeRadius(best + 1) : ShapeTrunks.fallenRadius
    }

    // P297 (d): where the world draws trunks round and thin (ShapeTrunks: polygon and smooth worlds), a felled tree's
    // logs are too: its hull mesh leaves them out (ShipMesh.build) and Game.writeFelled draws them as bark cylinders of
    // the standing tree's girth. As cubes, a broken tree turned into a log far thicker than the tree it was.
    static var roundTrunks = false
    static func roundFor(_ w: World) -> Bool { Mesher.detailMeshes && (SmoothTerrain.enabled || w.fieldTerrain) }
    // Per felled ship: its log cells with the radius each is drawn at (rebuilt when its block count changes).
    static var trunkCells: [Int: (count: Int, cells: [(IVec3, BlockID, Float)])] = [:]
    // P441 (Oct 24 20:51: "see how that turned into branches? We don't want that"): the girth of the tree each felled
    // body came from (by ship id; its pieces and its bare trunk inherit it). A piece too short to read as a trunk
    // (under 3 logs upright) was drawn at a limb's 0.13.
    static var girth: [Int: Float] = [:]
    static func inherit(_ from: Ship, _ to: Ship) { if let r = girth[from.id] ?? girth[from.root.id] { girth[to.id] = r } }

    // Nov 13 (playtest 12:33-12:35, Taiga and the Ash Vault; ledger 111-115). Switches, each =1 for the code before:
    //   BS_OLDSTUMPGIRTH   a stump left by a felled tree drawn by its own height (a post 0.9 across when no root shows)
    //   BS_OLDFELLSEED     the body is the logs above the cut only (limbs at the cut's height abort the fall)
    //   BS_OLDLEAFREST     a felled tree rests on its crown's leaves, and hangs in the trunks beside it for good
    static let stumpGirth = ProcessInfo.processInfo.environment["BS_OLDSTUMPGIRTH"] != "1"
    static let newSeed = ProcessInfo.processInfo.environment["BS_OLDFELLSEED"] != "1"
    static let woodRests = ProcessInfo.processInfo.environment["BS_OLDLEAFREST"] != "1"
    static var slipped = 0                       // (counter: bodies let through the trunks they hung in)

    // The stump a felled tree leaves keeps the girth it stood with: by column, the standing trunk's foot, height and
    // foot radius (so the stump's taper is the tree's own), and for a four-log trunk the corner of its square. Read by
    // the mesh workers (ShapeTrunks.emit), so under a lock; in memory only (a saved stump is told by the soil the
    // generator leaves under a tree's foot, ShapeTrunks.emit).
    struct Stump { var bot: Int, h: Int; var rb: Float; var wide: Bool; var ox: Int, oz: Int }
    private static let stumpLock = NSLock()
    private static var stumps: [Int64: Stump] = [:]
    @inline(__always) private static func stumpKey(_ x: Int, _ z: Int) -> Int64 { Int64(x) << 32 ^ Int64(UInt32(truncatingIfNeeded: z)) }
    static func noteStump(_ x: Int, _ z: Int, _ st: Stump) {
        stumpLock.lock()
        if stumps.count > 4096 { stumps.removeAll(keepingCapacity: true) }
        stumps[stumpKey(x, z)] = st
        stumpLock.unlock()
    }
    static func stump(_ x: Int, _ z: Int) -> Stump? {
        stumpLock.lock(); defer { stumpLock.unlock() }
        return stumps.isEmpty ? nil : stumps[stumpKey(x, z)]
    }
    // (a stump's foot log broken: the note goes, so a log set down there later is a log)
    static func stumpBroken(_ p: IVec3) {
        stumpLock.lock()
        if let st = stumps[stumpKey(p.x, p.z)], st.bot == p.y { stumps[stumpKey(p.x, p.z)] = nil }
        stumpLock.unlock()
    }
    // The stumps under the logs about to leave the world (`logs`, the cut at `cut`): every upright log left under one
    // of them (straight under, or under the cut or a cell struck out earlier).
    static func noteStumps(_ w: World, logs: Set<IVec3>, cut: IVec3?) {
        guard stumpGirth else { return }
        @inline(__always) func upright(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            let b = w.block(x, y, z)
            return CapitalBase.isLog(b) && ShapeTrunks.axisOf[Int(b)] == 1
        }
        for c in logs {
            var y = c.y - 1
            if logs.contains(IVec3(c.x, y, c.z)) { continue }
            if !upright(c.x, y, c.z) {
                // (the cut, or one cell struck out before, with the stump under it)
                guard IVec3(c.x, y, c.z) == cut || w.block(c.x, y, c.z) == AIR else { continue }
                y -= 1
                guard upright(c.x, y, c.z) else { continue }
            }
            var bot = y
            while bot > 1 && upright(c.x, bot - 1, c.z) { bot -= 1 }
            var top = c.y
            while logs.contains(IVec3(c.x, top + 1, c.z)) { top += 1 }
            let h = top - bot + 1
            guard h >= 3 else { continue }
            // (a four-log trunk: the square of logs at the body's lowest level here)
            var wide = false, ox = 0, oz = 0
            for (ax, az) in [(c.x, c.z), (c.x - 1, c.z), (c.x, c.z - 1), (c.x - 1, c.z - 1)] {
                if logs.contains(IVec3(ax, c.y, az)) && logs.contains(IVec3(ax + 1, c.y, az)) && logs.contains(IVec3(ax, c.y, az + 1)) && logs.contains(IVec3(ax + 1, c.y, az + 1)) {
                    wide = true; ox = ax; oz = az
                    break
                }
            }
            noteStump(c.x, c.z, Stump(bot: bot, h: h, rb: ShapeTrunks.treeRadius(h), wide: wide, ox: ox, oz: oz))
        }
    }

    // Whether a felled body has a log in it (by ship; redone when its block count changes): one that has rests on its
    // wood, its leaves giving way; a clump of leaves alone lies on the ground as it is.
    private static var woodOf: [Int: (count: Int, wood: Bool)] = [:]
    static func hasWood(_ s: Ship) -> Bool {
        if let c = woodOf[s.id], c.count == s.blockCount { return c.wood }
        if woodOf.count > 512 { woodOf.removeAll(keepingCapacity: true) }
        let wood = s.grid.blocks.contains { ShapeTrunks.isLog[Int($0)] }
        woodOf[s.id] = (s.blockCount, wood)
        return wood
    }

    // What such a body meets the ground with: every log in it (a trunk inside its crown is no exposed cell of the hull,
    // Ship.hull, so with the leaves giving way nothing held it: it sank into the ground), and whatever else is not leaf.
    private static var woodHulls: [Int: (count: Int, cells: [V3])] = [:]
    static func woodHull(_ s: Ship) -> [V3] {
        if let c = woodHulls[s.id], c.count == s.blockCount { return c.cells }
        if woodHulls.count > 512 { woodHulls.removeAll(keepingCapacity: true) }
        let g = s.grid
        var cells: [V3] = []
        for i in 0..<g.blocks.count where ShapeTrunks.isLog[Int(g.blocks[i])] {
            cells.append(V3(Float(i % g.sx) + 0.5, Float(i / (g.sx * g.sz)) + 0.5, Float((i / g.sx) % g.sz) + 0.5))
        }
        for c in s.hull {
            let b = g.get(Int(floor(c.x)), Int(floor(c.y)), Int(floor(c.z)))
            if !ShapeTrunks.isLog[Int(b)] && !CapitalBase.isLeaf(b) { cells.append(c) }
        }
        woodHulls[s.id] = (s.blockCount, cells)
        return cells
    }

    // The world's lighting of a round shape (quest/shaders/chunk_detail.vert: sky curve and tint, warm block light, the
    // sun on its side), so a felled trunk drawn by the entity pass keeps the colour it had standing (Oct 24 20:49: "the
    // log turns into a different color": it was lit flat, a third brighter, its bark stretched round it once).
    static func shade(_ n: V3, sky s: Int, block b: Int, day: Float, sun: V3) -> V3 {
        func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = simd_clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t) }
        let skyL = Float(s) / 15, blkL = Float(b) / 15
        let sky = skyL * (0.35 + 0.65 * skyL) * day
        let k = smooth(0.30, 0.62, day)
        let skyTint = simd_mix(V3(0.6, 0.7, 1.0), V3(1, 1, 1), V3(repeating: k))
        let blk0 = blkL / (4 - 3 * blkL), inv = 1 - blk0
        let blk = min(1, (blk0 + (1 - inv * inv * inv * inv - blk0) * 0.6) * 1.05)
        let warm = simd_mix(V3(1.06, 0.82, 0.56), V3(1.0, 0.95, 0.86), V3(repeating: blk * blk))
        let lit = simd_max(simd_max(skyTint * sky, warm * blk), V3(repeating: 0.055))
        let base = n.x * n.x * 0.80 + n.z * n.z * 0.68 + n.y * n.y * (n.y > 0 ? 1.0 : 0.55)
        let w0: Float = 0.85 * smooth(0, 0.45, day) * skyL * skyL
        let w = w0 * simd_clamp((sky - blk) * 4 + 0.5, 0, 1)
        guard w > 0 else { return lit * base }
        let l = simd_normalize(sun + V3(0, 1e-4, 0))
        let g = simd_clamp(l.y * 2.2, 0, 1)
        let sunC = simd_mix(V3(1.22, 0.80, 0.48), V3(1.04, 1.0, 0.93), V3(repeating: g))
        let d = V3(0.84, 0.92, 1.08) * 0.6 + sunC * (0.54 * max(0, simd_dot(n, l)))
        return lit * simd_mix(V3(repeating: base), d, V3(repeating: w))
    }
}

extension Game {
    // Game.breakBlock: a log was cut at p.
    func fellCheck(_ p: IVec3, _ cut: BlockID) {
        guard CapitalBase.isLog(cut), dim.dim == .overworld || dim.dim == .deep else { return }
        Felling.stumpBroken(p)
        let start = IVec3(p.x, p.y + 1, p.z)
        guard CapitalBase.isLog(world.block(start.x, start.y, start.z)) else { return }
        guard let logs = Felling.newSeed ? fellBody(p) : fellBodyOld(p) else { return }
        Felling.roundTrunks = Felling.roundFor(world)
        fellLoose(p, logs)
    }

    // Nov 13 (ledger 113; his Forest notes of Nov 12, "that turned into two trees... three trees", and the Taiga's of
    // Nov 13): what comes loose with a cut at p. The old walk took the logs above the cut only and gave up when one of
    // them stood on a log at the cut's height: a limb leaving the trunk at the cut's own level (a field oak's lowest
    // boughs) kept the whole tree up, and the load check then dropped trunk and limbs as two or three bodies; a tree
    // whose bough touched its neighbour's never fell, or took the neighbour's boughs along.
    //  - A log is held when the logs straight under it stand on the ground (another tree's trunk, a cabin wall, a
    //    stump): held logs are never part of the body. The trunk above the cut is not held, nor a bough.
    //  - The body is every log joined to the cut trunk through logs that are not held, the cut's level and a little
    //    below it included (a bough leaving at the cut, a drooping tip).
    //  - Where the walk meets another standing trunk, a log goes with the cut tree only if the cut trunk is no further
    //    from it than that one (as a leaf does: ownLeaf).
    //  - A four-log trunk goes over when half its section is cut through (P504): a corner holds while the logs under
    //    it reach the ground unbroken.
    func fellBody(_ p: IVec3) -> Set<IVec3>? {
        let w = world
        let start = IVec3(p.x, p.y + 1, p.z)
        @inline(__always) func isLog(_ c: IVec3) -> Bool { CapitalBase.isLog(w.block(c.x, c.y, c.z)) }
        // The trunk's section: `start` alone, or the four columns of a four-log trunk (a square of logs with `start`'s
        // column in it at one of the three levels above the cut: a corner struck out at one level is still a corner).
        var cols = [(p.x, p.z)]
        find: for dy in 0...2 {
            for (ox, oz) in [(0, 0), (-1, 0), (0, -1), (-1, -1)] {
                let q = [(p.x + ox, p.z + oz), (p.x + ox + 1, p.z + oz), (p.x + ox, p.z + oz + 1), (p.x + ox + 1, p.z + oz + 1)]
                if q.allSatisfy({ isLog(IVec3($0.0, start.y + dy, $0.1)) }) { cols = q; break find }
            }
        }
        let wide = cols.count == 4
        let section = cols.map { IVec3($0.0, start.y, $0.1) }.filter { isLog($0) }
        @inline(__always) func inSection(_ x: Int, _ z: Int) -> Bool { cols.contains { $0.0 == x && $0.1 == z } }
        // (down through logs to what they stand on; `through`: a four-log trunk's own stump counts as cut)
        func held(_ q: IVec3, through: Bool) -> Bool {
            var y = q.y - 1
            while y > 0 {
                if q.x == p.x && y == p.y && q.z == p.z { return false }
                if through && y == p.y && inSection(q.x, q.z) { return false }
                let b = w.block(q.x, y, q.z)
                if CapitalBase.isLog(b) { y -= 1; continue }
                return Blocks.collide[Int(b)] && !CapitalBase.isLeaf(b)
            }
            return true
        }
        if wide {
            var holding = 0
            for c in section where held(c, through: false) { holding += 1 }
            if holding * 2 > cols.count { return nil }
        }
        var others: [(Int, Int)] = []                 // (columns of other standing trunks the walk met)
        var sumX = 0, sumZ = 0
        for c in cols { sumX += c.0; sumZ += c.1 }
        let ax: Float = Float(sumX) / Float(cols.count), az: Float = Float(sumZ) / Float(cols.count)
        func walk(own: Bool) -> Set<IVec3>? {
            var logs = Set(section)
            var queue = section
            while let c = queue.popLast() {
                for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0 && dz == 0) {
                    let q = IVec3(c.x + dx, c.y + dy, c.z + dz)
                    guard q != p, q.y >= p.y - 3, !logs.contains(q), isLog(q) else { continue }
                    if held(q, through: wide) {
                        if !own && !inSection(q.x, q.z) && !others.contains(where: { $0.0 == q.x && $0.1 == q.z }) { others.append((q.x, q.z)) }
                        continue
                    }
                    if own {
                        let ex: Float = Float(q.x) - ax, ez: Float = Float(q.z) - az
                        let d0: Float = ex * ex + ez * ez
                        var nearer = false
                        for o in others {
                            let ox = o.0 - q.x, oz = o.1 - q.z
                            if Float(ox * ox + oz * oz) < d0 { nearer = true; break }
                        }
                        if nearer { continue }
                    }
                    logs.insert(q); queue.append(q)
                    if logs.count > Felling.maxLogs { return nil }
                } } }
            }
            return logs
        }
        guard var logs = walk(own: false) else { return nil }
        if !others.isEmpty { guard let l = walk(own: true) else { return nil }; logs = l }
        return logs
    }

    // (the walk before Nov 13: BS_OLDFELLSEED=1)
    func fellBodyOld(_ p: IVec3) -> Set<IVec3>? {
        let start = IVec3(p.x, p.y + 1, p.z)
        var logs: Set<IVec3> = [start]
        var queue = [start]
        while let c = queue.popLast() {
            for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0 && dz == 0) {
                let q = IVec3(c.x + dx, c.y + dy, c.z + dz)
                guard q.y > p.y, !logs.contains(q), CapitalBase.isLog(world.block(q.x, q.y, q.z)) else { continue }
                logs.insert(q); queue.append(q)
                if logs.count > Felling.maxLogs { return nil }
            } } }
        }
        // Resting on anything else (a wall, the ground beside the cut, another tree's log): it stands.
        // P504 (Nov 1 07:25, his Ash Vault dark oak at 2914 -33 -3051: "This tree should have fallen"): a thick trunk (a
        // dark oak's 2x2) stood until every one of its feet was cut, on one log in four. Cut through half its section
        // (two feet of four) it goes over; the logs left at the cut's level stay as the stump.
        var section = 0, holding = 0
        for c in logs where c.y == p.y + 1 && Felling.sameTrunk(c, p) {
            section += 1
            if CapitalBase.isLog(world.block(c.x, p.y, c.z)) { holding += 1 }
        }
        let cutThrough = section >= 2 && holding * 2 <= section
        for c in logs {
            let below = IVec3(c.x, c.y - 1, c.z)
            if logs.contains(below) || below == p { continue }
            let b = world.block(below.x, below.y, below.z)
            if Blocks.collide[Int(b)] && !CapitalBase.isLog(b) && !CapitalBase.isLeaf(b) { return nil }
            if CapitalBase.isLog(b) && below.y <= p.y && !(cutThrough && below.y == p.y && c.y == p.y + 1 && Felling.sameTrunk(below, p)) { return nil }
        }
        return logs
    }

    // The logs come loose with their crown as one body.
    // (P441, Oct 24 20:50: "this log is floating... it should be able to sit on whatever's under it": a spruce's top of
    // one or two logs in its crown stayed in the air; with its leaves any part of a tree comes down)
    func fellLoose(_ p: IVec3, _ logs: Set<IVec3>) {
        let start = IVec3(p.x, p.y + 1, p.z)
        // The crown: leaves joined to the logs (6-connected through leaves, within 5 of a log), and only its own.
        // P478 (Oct 27 18:46, "trees disappear when they hit another root"): crowns in a wood grow through each other,
        // and the body took every leaf it could reach, half its neighbours' crowns with it; that weight pulled it over
        // onto the next trunk, where it hung, and the trees round it were left with holes. A leaf goes with the cut tree
        // only when none of another tree's logs is nearer to it.
        let mine = Felling.ownLeaf(world, logs: logs, above: p.y)
        var leaves: Set<IVec3> = []
        var lq: [IVec3] = []
        for c in logs { for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
            let q = c + d
            if !leaves.contains(q) && CapitalBase.isLeaf(world.block(q.x, q.y, q.z)) && mine(q) { leaves.insert(q); lq.append(q) }
        } }
        guard leaves.count >= 4 || logs.count >= 3 && leaves.count >= 1 else { return }
        var head = 0
        while head < lq.count && leaves.count < Felling.maxLeaves {
            let c = lq[head]; head += 1
            for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
                let q = c + d
                guard q.y > p.y, !leaves.contains(q), CapitalBase.isLeaf(world.block(q.x, q.y, q.z)) else { continue }
                guard logs.contains(where: { abs($0.x - q.x) + abs($0.y - q.y) + abs($0.z - q.z) <= 5 }), mine(q) else { continue }
                leaves.insert(q); lq.append(q)
            }
        }
        Felling.noteStumps(world, logs: logs, cut: p)
        // The body: its cells relative to the block above the cut, then out of the world.
        let bp = Blueprint()
        var lo = IVec3(Int.max, Int.max, Int.max)
        for c in logs.union(leaves) {
            bp.cells[ivSub(c, start)] = world.block(c.x, c.y, c.z)
            lo = IVec3(min(lo.x, c.x - start.x), min(lo.y, c.y - start.y), min(lo.z, c.z - start.z))
        }
        // (ledger 45: no circuit marks a block when no circuit part is near the tree)
        let quiet0 = world.circuitQuiet
        if Explosion.circuitCalm && !world.circuitNear(Array(logs) + Array(leaves), margin: 3) { world.circuitQuiet = true }
        for c in leaves { world.setBlockAsync(c.x, c.y, c.z, AIR) }
        for c in logs { world.setBlockAsync(c.x, c.y, c.z, AIR) }
        world.circuitQuiet = quiet0
        let s = world.ships.spawn(bp, at: V3(Float(start.x), Float(start.y), Float(start.z)), yaw: 0, name: Felling.name, role: "")
        s.role = nil
        // Local cell (c - start - lo) sits where it stood: world = pos + (l - com).
        s.pos = V3(Float(start.x + lo.x), Float(start.y + lo.y), Float(start.z + lo.z)) + s.com
        s.prevPos = s.pos
        s.updateBounds()
        s.initialBlocks = s.blockCount
        // It goes over away from the woodsman (a nudge at the top; gravity does the rest).
        var away = V3(Float(p.x) + 0.5 - player.pos.x, 0, Float(p.z) + 0.5 - player.pos.z)
        if simd_length(away) < 0.1 { away = V3(-sinf(player.yaw), 0, -cosf(player.yaw)) }
        away = simd_normalize(away)
        s.angVel = simd_cross(V3(0, 1, 0), away) * 0.35
        s.vel = away * 0.4
        Felling.girth[s.id] = Felling.girthOf(logs)
        Felling.falls.append(hold(s, cells: logs.union(leaves)))
        Felling.felled += 1
        let mid = s.pos
        sfx(.hullCreak, 1.3, at: mid)
        sfx(.breakBlock(.wood), 1.2, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
    }

    // P407: a piece the load check found held by nothing (Structure.drop, Structure.loose) comes down whole: one body,
    // drawn with its own mesh the whole way (a tree keeps its leaf blobs and round trunk, a tower its walls), tipping
    // away from him. A tree takes its crown along and lies as a felled trunk once still; anything else lies where it lands.
    static let toppledName = "Toppled"
    static let toppledWreck = "Toppled wreck"
    static var ridersTaken = 0                                // (checks)
    static let ridersOn = ProcessInfo.processInfo.environment["BS_OLDRIDERS"] != "1"
    static let rides: [Bool] = (0..<Blocks.count).map { i in
        let b = BlockID(i)
        guard b != AIR, !Blocks.collide[i], !Blocks.isLiquid(b), !CapitalBase.isLeaf(b), Blocks.hardness[i] >= 0 else { return false }
        let k = Blocks.key(b)
        return !k.contains("fire") && !k.contains("portal")
    }
    func topple(_ cells: [IVec3], away awayDir: V3? = nil) {
        guard let start = cells.min(by: { ($0.y, $0.x, $0.z) < ($1.y, $1.x, $1.z) }) else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        var tCopy = t0, tTake = t0, tSpawn = t0
        defer {
            let t4 = CFAbsoluteTimeGetCurrent(), ms = (t4 - t0) * 1000
            if ms > Felling.worstMs {
                Felling.worstMs = ms
                Felling.worstSplit = String(format: "%d blocks: crown and copy %.1f, taken out %.1f, body made %.1f, held %.1f", cells.count,
                                            (tCopy - t0) * 1000, (tTake - tCopy) * 1000, (tSpawn - tTake) * 1000, (t4 - tSpawn) * 1000)
            }
        }
        let logs = cells.filter { CapitalBase.isLog(world.block($0.x, $0.y, $0.z)) }
        var leaves: Set<IVec3> = []
        if !logs.isEmpty {
            let body = Set(cells)
            let mine = Felling.ownLeaf(world, logs: Set(logs), above: start.y - 1)        // (P478: its own crown only)
            var lq: [IVec3] = []
            for c in logs { for d in World.allDirs {
                let q = c + d
                if !body.contains(q) && !leaves.contains(q) && CapitalBase.isLeaf(world.block(q.x, q.y, q.z)) && mine(q) { leaves.insert(q); lq.append(q) }
            } }
            var head = 0
            while head < lq.count && leaves.count < Felling.maxLeaves {
                let c = lq[head]; head += 1
                for d in World.allDirs {
                    let q = c + d
                    guard !leaves.contains(q), !body.contains(q), CapitalBase.isLeaf(world.block(q.x, q.y, q.z)) else { continue }
                    guard logs.contains(where: { abs($0.x - q.x) + abs($0.y - q.y) + abs($0.z - q.z) <= 5 }), mine(q) else { continue }
                    leaves.insert(q); lq.append(q)
                }
            }
        }
        // Nov 13 (his note 13:05:46, a circuit board on a platform he brought down: "all the wire despawned when it
        // fell"): what sits on a falling piece or hangs on its side without a body of its own (wire, a torch, a lever,
        // a sign, a carpet's flowers) was left in the air and popped off. It rides the piece down. BS_OLDRIDERS=1: before.
        var riders: [IVec3] = []
        if logs.isEmpty && Game.ridersOn {
            let body = Set(cells)
            var seen = Set<IVec3>()
            let rides = Game.rides
            for c in cells {
                let up = IVec3(c.x, c.y + 1, c.z)
                let ub = world.block(up.x, up.y, up.z)
                if !body.contains(up), rides[Int(ub)] || CapitalBase.isLeaf(ub), seen.insert(up).inserted { riders.append(up) }      // (a hedge on a roof garden too)
                for d in World.allDirs where d.y == 0 {
                    let q = c + d
                    guard !body.contains(q), rides[Int(world.block(q.x, q.y, q.z))] else { continue }
                    // (a torch or a ladder on a wall that stays, beside the piece, stays: nothing solid may touch it but the piece)
                    guard !World.allDirs.contains(where: { e in
                        let n = q + e
                        return !body.contains(n) && Blocks.collide[Int(world.block(n.x, n.y, n.z))]
                    }) else { continue }
                    if seen.insert(q).inserted { riders.append(q) }
                }
            }
        }
        Game.ridersTaken += riders.count
        let bp = Blueprint()
        var lo = IVec3(Int.max, Int.max, Int.max)
        for c in leaves.union(cells).union(riders) {
            bp.cells[ivSub(c, start)] = world.block(c.x, c.y, c.z)
            lo = IVec3(min(lo.x, c.x - start.x), min(lo.y, c.y - start.y), min(lo.z, c.z - start.z))
        }
        tCopy = CFAbsoluteTimeGetCurrent()
        // (taken out quietly: what it leaves behind was checked already)
        let restoring0 = world.restoring                     // (a collapse's loose blocks: StructureCollapse set it)
        world.restoring = true
        let quiet0 = world.circuitQuiet                      // (ledger 45)
        if Explosion.circuitCalm && !world.circuitNear(cells + Array(leaves), margin: 3) { world.circuitQuiet = true }
        for c in riders { world.setBlockAsync(c.x, c.y, c.z, AIR) }
        for c in leaves { world.setBlockAsync(c.x, c.y, c.z, AIR) }
        for c in cells { world.setBlockAsync(c.x, c.y, c.z, AIR) }
        world.circuitQuiet = quiet0
        world.restoring = restoring0
        GroundCollapse.builtGone(world, cells)      // (Nov 13: ground that lay on it)
        tTake = CFAbsoluteTimeGetCurrent()
        let tree = logs.count == cells.count
        let s = world.ships.spawn(bp, at: V3(Float(start.x), Float(start.y), Float(start.z)), yaw: 0,
                                  name: tree ? Felling.name : Game.toppledName, role: "")
        s.role = nil
        s.pos = V3(Float(start.x + lo.x), Float(start.y + lo.y), Float(start.z + lo.z)) + s.com
        s.prevPos = s.pos
        s.updateBounds()
        s.initialBlocks = s.blockCount
        tSpawn = CFAbsoluteTimeGetCurrent()
        var away = awayDir ?? V3(s.pos.x - player.pos.x, 0, s.pos.z - player.pos.z)      // (P507: a crawler's push, its way)
        if simd_length(away) < 0.1 { away = V3(-sinf(player.yaw), 0, -cosf(player.yaw)) }
        away = simd_normalize(away)
        s.angVel = simd_cross(V3(0, 1, 0), away) * (tree ? (awayDir != nil ? 0.7 : 0.35) : 0.15)
        s.vel = away * 0.2
        if tree { Felling.girth[s.id] = Felling.girthOf(Set(logs)) }
        Felling.falls.append(hold(s, cells: leaves.union(cells).union(riders)))
        // (every piece of a structure, not only a collapse's: one the check near a change cut loose off the citadel
        // after it meshed its sections on the frame, 17 and 41 ms in two of four runs. A tree's sections are light.)
        if StructureCollapse.patientPieces && !tree { Felling.falls.last?.patient = true }
        Felling.toppled += 1
        sfx(.hullCreak, tree ? 1.3 : 0.8, at: s.pos)
    }

    // P441: the fall of a body just taken out of the world, held hidden and still until the world has redrawn the cells
    // it left (the sections and versions after the removal) and its own mesh is built.
    func hold(_ s: Ship, cells: Set<IVec3>) -> Felling.Fall {
        let f = Felling.Fall(s)
        var seen = Set<Int64>()
        for c in cells {
            guard let ch = world.chunkAt(c.x, c.z), c.y >= 0 && c.y < CH else { continue }
            let sy = c.y >> 4
            let key = Int64(ch.cx) << 40 ^ Int64(ch.cz) << 16 ^ Int64(sy)
            if seen.insert(key).inserted { f.wait.append((ch, sy, ch.sections[sy].version)) }
        }
        f.launch = (s.vel, s.angVel)
        if Felling.isFelled(s) && simd_length(s.angVel) > 0 { f.over = simd_normalize(s.angVel) }
        s.vel = .zero; s.angVel = .zero
        s.hidden = true; s.kinematic = true
        f.held = 0
        return f
    }

    // Every frame (Game.advance): falling trees land and shed their leaves; a carried trunk follows the hands.
    func fellingTick(_ dt: Float) {
        StructureImpact.thisFrame = 0
        guard dt > 0 else { return }
        Felling.roundTrunks = Felling.roundFor(world)
        let live = world.ships.list
        Felling.falls.removeAll { f in f.ship.map { s in !live.contains { $0 === s } } ?? true }
        // (Nov 10, the code reader's TNT stack: 2,000 TNT felled a wood's worth of trees at once and their pushed
        // sections were all meshed on one frame, felling 12.3 ms. Past 2 ms of pushes a frame the rest wait for the next;
        // a body still waits up to 4 s for its tree to be drawn without it. BS_OLDFELLPUSH=1: every push on the frame.)
        var pushT = 0.0, pushN = 0
        defer { if pushT * 1000 > Felling.pushWorstMs { Felling.pushWorstMs = pushT * 1000; Felling.pushWorstSections = pushN } }
        for f in Felling.falls {
            guard let s = f.ship else { continue }
            if f.held >= 0 {
                // P447 (Oct 25 08:48-08:52, a piece broken off: "the existing piece stays standing and then eventually
                // disappears. But the piece that broke off... it's almost like it duplicated"): the body was let go after
                // 1.5 s whether or not the world had redrawn the tree without it, and with the workers behind (P446) both
                // showed for many seconds. A section still waiting after a few frames is meshed on the edit lane, and the
                // body waits up to 4 s for it (a section unloaded meanwhile counts as drawn).
                f.held += dt
                let drawn = f.wait.allSatisfy { $0.0.sections[$0.1].meshedVersion >= $0.2 || self.world.chunks[ChunkKey(x: $0.0.cx, z: $0.0.cz)] !== $0.0 }
                if !drawn && !f.pushed && !f.patient && f.held > 0.1 && (Felling.oldPush || pushT < 0.002) {
                    f.pushed = true
                    let w = world
                    let t0 = CFAbsoluteTimeGetCurrent()
                    w.editBatch { for (ch, sy, v) in f.wait where ch.sections[sy].meshedVersion < v && w.chunks[ChunkKey(x: ch.cx, z: ch.cz)] === ch { w.remeshSync(ch, sy) } }
                    pushT += CFAbsoluteTimeGetCurrent() - t0
                    pushN += f.wait.count
                }
                let built = !s.mesh.busy && !s.mesh.sections.isEmpty
                if !(drawn && built) && f.held < 4 { s.vel = .zero; s.angVel = .zero; continue }
                if !drawn { Felling.letLate += 1 }
                s.hidden = false; s.kinematic = false
                (s.vel, s.angVel) = f.launch
                f.held = -1
            }
            f.age += dt
            // P478 (Oct 27 18:46, "trees disappear when they hit another root"): at his spot the spruce cut at its foot
            // dropped onto the ground under the cut and stood there upright for good, 4 degrees over and a body: the
            // landing took the nudge's spin out and its round foot held it. A cut tree goes over: until it is 15 degrees
            // over (past its foot, where its weight takes it) it is kept turning away from the woodsman.
            if f.age < 5 && simd_length(f.over) > 0 {
                let lean = acosf(max(-1, min(1, s.rot.act(V3(0, 1, 0)).y)))
                if lean < 0.26 {
                    let have = simd_dot(s.angVel, f.over), want = 0.35 + 2 * lean
                    if have < want { s.angVel += f.over * min(want - have, dt * 3) }
                }
            }
            let dv = simd_length(s.vel - f.lastVel)
            // Nov 13 (StructureImpact): a falling piece of a structure breaks the built blocks it lands on, and goes on down.
            f.sinceBlow += dt
            if !Felling.isFelled(s) && f.age > 0.2 && s.contacts > 0 && dv > 2.5 && f.sinceBlow >= StructureImpact.cooldown && StructureImpact.enabled {
                if f.weight <= 0 { f.weight = StructureImpact.weight(s) }
                if StructureImpact.strike(self, s, weight: f.weight, vIn: f.lastVel, dv: dv) { f.sinceBlow = 0; f.still = 0 }
            }
            f.lastVel = s.vel
            if !f.landed && f.age > 0.4 && s.contacts > 0 && dv > 2.5 {
                f.landed = true
                sfx(.shipCollideHard, min(2, 0.8 + dv / 6), at: s.pos)
                sfx(.plantBrush, 1.4, at: s.pos)
                let d = simd_length(player.pos - s.pos)
                if d < 30 { addShake(0.35 * (1 - d / 30)) }
            }
            let resting = simd_length(s.vel) < 0.4 && simd_length(s.angVel) < 0.25
            f.still = resting ? f.still + dt : 0
            // P478 (Oct 27 18:47: "I don't want the branches and shit to disappear after the log falls"): the crown stays
            // on the fallen tree; it used to drop away once the tree lay still, leaving the bare trunk.
            if (f.still > 1.5 && f.age > 2) || f.age > 9 { f.age = -1 }
        }
        Felling.falls.removeAll { $0.ship == nil || $0.age < 0 }
        // The carried trunk: held 2 blocks ahead at chest height, out of everyone's way.
        if let s = Felling.carried {
            guard alive, world.ships.list.contains(where: { $0 === s }) else { dropCarried(throwing: false); return }
            let flat = simd_normalize(V3(player.look.x, 0, player.look.z) + V3(0.0001, 0, 0))
            let want = player.eye + flat * 2.2 + V3(0, -0.7, 0)
            s.kinematic = true
            s.vel = (want - s.pos) * min(12, 1 / dt)
            // Turned across the view, lying level.
            let yaw = player.yaw + .pi / 2
            let target = Quat(angle: yaw, axis: V3(0, 1, 0)) * Felling.lying(s)
            s.rot = simd_slerp(s.rot, target, min(1, dt * 8))
            s.angVel = .zero
        }
    }

    // Ship interaction (use) on a felled trunk: pick it up (empty hand or a non-block item), or set the carried one down.
    func fellUse(_ s: Ship, sneak: Bool) -> Bool {
        if let c = Felling.carried, c === s.root { dropCarried(throwing: true); return true }
        guard Felling.isFelled(s), !sneak, held.def.block == nil, Felling.carried == nil else { return false }
        let r = s.root
        guard !Felling.falls.contains(where: { $0.ship === r }) else { return false }      // (still falling)
        guard r.blockCount <= Felling.carryMax else {
            sfx(.hit(.wood), 0.8, at: r.pos)                  // too heavy: a dull knock (chop it down to size)
            return true
        }
        Felling.carried = r
        ShipManager.ghosts.insert(r.id)
        sfx(.hit(.wood), 1, at: r.pos)
        sfx(.place(.wood), 0.8, at: r.pos)
        return true
    }

    // P297 (d): felled trunks as round bark cylinders (entity pass, both renderers): each log cell a segment along its
    // axis, ring caps where the log ends, lit by the light where it lies.
    func writeFelled(_ wr: inout EntityWriter, eye: V3) {
        guard Felling.roundTrunks else { return }
        let ships = world.ships.list.filter { Felling.isFelled($0) && !$0.hidden }
        if ships.isEmpty { if !Felling.trunkCells.isEmpty { Felling.trunkCells.removeAll() }; return }
        let n = 9                                            // (the world's near trunks: ShapeTrunks.column)
        let texT = Blocks.tex
        let sun = sunDir
        for s in ships where simd_length(s.pos - eye) < 112 {
            let g = s.grid
            if Felling.trunkCells[s.id]?.count != s.blockCount {
                // The trunk (vertical runs of 3 or more) at the standing tree's girth, limbs as limbs.
                var cells: [(IVec3, BlockID, Float)] = []
                for i in 0..<g.blocks.count where ShapeTrunks.isTrunk[Int(g.blocks[i])] {
                    let c = IVec3(i % g.sx, i / (g.sx * g.sz), (i / g.sx) % g.sz)
                    let b = g.blocks[i]
                    var run = 1
                    if ShapeTrunks.axisOf[Int(b)] == 1 {
                        var y = c.y - 1
                        while y >= 0 && ShapeTrunks.isTrunk[Int(g.get(c.x, y, c.z))] && ShapeTrunks.axisOf[Int(g.get(c.x, y, c.z))] == 1 { run += 1; y -= 1 }
                        y = c.y + 1
                        while y < g.sy && ShapeTrunks.isTrunk[Int(g.get(c.x, y, c.z))] && ShapeTrunks.axisOf[Int(g.get(c.x, y, c.z))] == 1 { run += 1; y += 1 }
                    }
                    cells.append((c, b, run >= 3 ? ShapeTrunks.treeRadius(run + 1) : 0.13))
                }
                // A piece with no upright run of 3 is a cut length of trunk, not a limb: drawn at its tree's girth.
                if !cells.contains(where: { $0.2 > 0.13 }), let r = Felling.girth[s.id] ?? Felling.girth[s.root.id] {
                    for k in cells.indices where ShapeTrunks.axisOf[Int(cells[k].1)] == 1 { cells[k].2 = r }
                }
                Felling.trunkCells[s.id] = (s.blockCount, cells)
            }
            guard let cells = Felling.trunkCells[s.id]?.cells else { continue }
            for (c, b, r) in cells {
                let ax = Int(ShapeTrunks.axisOf[Int(b)])
                let d = ax == 0 ? V3(1, 0, 0) : (ax == 1 ? V3(0, 1, 0) : V3(0, 0, 1))
                let u = ax == 1 ? V3(1, 0, 0) : V3(0, 1, 0), v = simd_cross(d, u)
                let mid = V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5
                let wc = s.toWorld(mid)
                let l = world.lightAt(Int(floor(wc.x)), Int(floor(wc.y)), Int(floor(wc.z)))
                let sky = Int(l.sky), blk = Int(l.block)
                let bark = Int(texT[Int(b) * 6 + (ax == 0 ? 2 : 0)]), ring = Int(texT[Int(b) * 6 + ax * 2])
                let wrap = max(1, (2 * .pi * r).rounded())    // bark repeats round it as on a standing trunk
                let a0 = mid - d * 0.5, a1 = mid + d * 0.5
                func w(_ p: V3) -> V3 { s.toWorld(p) - eye }
                for k in 0..<n {
                    let t0 = Float(k) / Float(n) * 2 * .pi, t1 = Float(k + 1) / Float(n) * 2 * .pi
                    let o0 = (u * cosf(t0) + v * sinf(t0)) * r, o1 = (u * cosf(t1) + v * sinf(t1)) * r
                    let nrm = s.rot.act(simd_normalize(o0 + o1))
                    let sh = Felling.shade(nrm, sky: sky, block: blk, day: daylight, sun: sun)
                    let col = V4(sh.x, sh.y, sh.z, 1)
                    let ua = Float(k) / Float(n) * wrap, ub = Float(k + 1) / Float(n) * wrap
                    wr.quad4(w(a0 + o0), w(a0 + o1), w(a1 + o1), w(a1 + o0), V2(ua, 1), V2(ub, 1), V2(ub, 0), V2(ua, 0), bark, col)
                }
                // Ring caps where the log ends along its axis.
                for (end, sgn) in [(a0, Float(-1)), (a1, Float(1))] {
                    let nb = c + IVec3(ax == 0 ? Int(sgn) : 0, ax == 1 ? Int(sgn) : 0, ax == 2 ? Int(sgn) : 0)
                    let nbB = g.get(nb.x, nb.y, nb.z)
                    if ShapeTrunks.isTrunk[Int(nbB)] && ShapeTrunks.axisOf[Int(nbB)] == UInt8(ax) { continue }
                    let sh = Felling.shade(s.rot.act(d * sgn), sky: sky, block: blk, day: daylight, sun: sun)
                    for k in 0..<n {
                        let t0 = Float(k) / Float(n) * 2 * .pi, t1 = Float(k + 1) / Float(n) * 2 * .pi
                        let o0 = u * cosf(t0) + v * sinf(t0), o1 = u * cosf(t1) + v * sinf(t1)
                        let c0 = V2(0.5, 0.5), p0 = V2(0.5 + 0.5 * cosf(t0), 0.5 + 0.5 * sinf(t0)), p1 = V2(0.5 + 0.5 * cosf(t1), 0.5 + 0.5 * sinf(t1))
                        // (Wound to face out of the log at both ends: the foot's cap faced in and drew black.)
                        if sgn > 0 { wr.quad4(w(end), w(end + o0 * r), w(end + o1 * r), w(end), c0, p0, p1, c0, ring, V4(sh.x, sh.y, sh.z, 1)) }
                        else { wr.quad4(w(end), w(end + o1 * r), w(end + o0 * r), w(end), c0, p1, p0, c0, ring, V4(sh.x, sh.y, sh.z, 1)) }
                    }
                }
            }
        }
    }

    func dropCarried(throwing: Bool) {
        guard let s = Felling.carried else { return }
        Felling.carried = nil
        ShipManager.ghosts.remove(s.id)
        s.kinematic = false
        s.vel = throwing ? player.look * 3 + player.vel : .zero
        sfx(.place(.wood), 0.9, at: s.pos)
    }
}

extension Felling {
    // The turn that lays a trunk along its length, level (its longest side along x).
    static func lying(_ s: Ship) -> Quat {
        let e = s.localMax - s.localMin
        if e.y >= e.x && e.y >= e.z { return Quat(angle: .pi / 2, axis: V3(0, 0, 1)) }     // upright trunk: on its side
        if e.z > e.x { return Quat(angle: .pi / 2, axis: V3(0, 1, 0)) }
        return Quat(angle: 0, axis: V3(0, 1, 0))
    }
}

extension ShipManager {
    // Ships nothing collides with (a trunk being carried).
    static var ghosts = Set<Int>()
}
