import Foundation
import simd

// P503 (Oct 31 16:22:21-52, the Field Hospital's tower top shot out from under it with the deck gun: "this building
// should have fallen because there's not enough structure under it... even if there's a block connecting it
// somewhere, the whole thing should have still fallen down because of gravity and block connection physics").
// P388's check carries each block's weight to the ground joint by joint, and a reinforced slab's joints carry hundreds
// of blocks each, so a cabin left on one corner of its tower was held. What holds a building up is also where its
// weight stands. After a blast that broke built blocks (World.tipQueue: Explosion.explode, a breach's CraterJob), the
// piece over each level of the hole is weighed: its blocks joined as P388 joins them (faces and edges) over that level,
// up to 5,000 blocks and 30 out (a larger piece is held by the world), against what it stands on there: its blocks
// resting on a block under the level, or on the ground or into it at a side. When the piece's centre of weight lies
// more than a block out past what it stands on, and its weight times that lever turns harder than those blocks'
// bonds hold, it tips: it comes down whole as one body (Game.topple, P407: its own mesh, turning as it falls). One
// check a frame.
enum StructureTip {
    static let limit = 5000, out = 30
    // What a footing block's joint holds against turning, over its bond (what it holds hanging): the bond acts half a
    // block from the joint's edge it turns about.
    static let turnHold: Float = 0.5
    static var checks = 0, tipped = 0, worstMs: Double = 0      // (harness tallies)

    static func tick(_ g: Game) {
        let w = g.world
        guard Structure.enabled, let (p, r) = w.tipQueue.popLast() else { return }
        if w.tipQueue.count > 16 { w.tipQueue.removeFirst(w.tipQueue.count - 16) }
        guard w.activeHere(p) else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        if let piece = check(w, at: p, r: r) {
            g.topple(piece)
            tipped += 1
        }
        checks += 1
        worstMs = max(worstMs, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }

    // The piece that tips at the hole round p (radius r), lowest first; nil when what stands there holds.
    // The built piece at and over the hole's floor joined to the blocks round it is filled once (nil past the bound:
    // held by the world, or into unloaded ground or a docked vessel); then level by level up the hole, the part of it
    // over the level joined to the hole (two towers met below the level are two pieces there) is weighed.
    static func check(_ w: World, at p: IVec3, r: Int) -> [IVec3]? {
        let r = max(1, min(r, 8))
        let floorY = max(1, p.y - r)
        let R = Structure.gridR, G = Structure.gridW
        @inline(__always) func slot(_ q: IVec3) -> Int { (q.x - p.x + R) + (q.y - p.y + R) * G + (q.z - p.z + R) * G * G }
        var cells: [IVec3] = [], mats: [Structure.Mat] = []
        defer { for q in cells { Structure.grid[slot(q)] = -1 } }
        func add(_ q: IVec3) -> Bool {
            guard abs(q.x - p.x) <= out, abs(q.y - p.y) <= out, abs(q.z - p.z) <= out, q.y >= floorY, Structure.grid[slot(q)] < 0,
                  let m = Structure.part(w, q.x, q.y, q.z) else { return true }
            if Structure.helm[Int(w.builtBlock(q.x, q.y, q.z))] { return false }
            Structure.grid[slot(q)] = Int32(cells.count)
            cells.append(q); mats.append(m)
            return true
        }
        @inline(__always) func near(_ q: IVec3) -> Bool { abs(q.x - p.x) <= r + 1 && abs(q.y - p.y) <= r + 1 && abs(q.z - p.z) <= r + 1 }
        for y in stride(from: floorY, through: min(CH - 2, p.y + r + 1), by: 1) {
            for z in (p.z - r - 1)...(p.z + r + 1) { for x in (p.x - r - 1)...(p.x + r + 1) { if !add(IVec3(x, y, z)) { return nil } } }
        }
        var head = 0
        while head < cells.count {
            let c = cells[head]; head += 1
            if cells.count > limit || abs(c.x - p.x) >= out || abs(c.y - p.y) >= out || abs(c.z - p.z) >= out { return nil }
            for d in Structure.nbrs {
                let q = c + d
                guard w.isLoaded(q.x, q.z) else { return nil }
                if !add(q) { return nil }
            }
        }
        let n = cells.count
        guard n >= 4 else { return nil }
        // What each block stands on: the ground under it or into it at a side (`ground`), or a built block under it,
        // straight or at an edge (`onBlock`: its footing when it is at the level weighed).
        var ground = [Bool](repeating: false, count: n), onBlock = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let c = cells[i]
            for d in Structure.nbrs where d.y == -1 {
                let q = c + d
                if Structure.anchor(w, q.x, q.y, q.z) { ground[i] = true; break }
                if Structure.part(w, q.x, q.y, q.z) != nil { onBlock[i] = true }
            }
            if !ground[i] { for d in World.allDirs where d.y == 0 && Structure.anchor(w, c.x + d.x, c.y, c.z + d.z) { ground[i] = true; break } }
        }
        var mark = [Int32](repeating: -1, count: n)
        var comp: [Int] = []
        let top = min(p.y + r, cells.reduce(floorY) { max($0, $1.y) })
        for yc in stride(from: floorY, through: top, by: 1) {
            for s in 0..<n where cells[s].y >= yc && mark[s] != Int32(yc) && near(cells[s]) {
                comp.removeAll(keepingCapacity: true)
                mark[s] = Int32(yc); comp.append(s)
                var h = 0
                while h < comp.count {
                    let c = cells[comp[h]]; h += 1
                    for d in Structure.nbrs {
                        let q = c + d
                        guard q.y >= yc, abs(q.x - p.x) <= R, abs(q.y - p.y) <= R, abs(q.z - p.z) <= R else { continue }
                        let j = Int(Structure.grid[slot(q)])
                        if j >= 0 && mark[j] != Int32(yc) { mark[j] = Int32(yc); comp.append(j) }
                    }
                }
                guard comp.count >= 4 else { continue }
                if tips(comp.map { (cells[$0], mats[$0], ground[$0] || cells[$0].y == yc && onBlock[$0]) }) {
                    return comp.map { cells[$0] }.sorted { $0.y < $1.y }
                }
            }
        }
        return nil
    }

    // Does a piece tip off what it stands on (each block: where it is, its material, whether it is a footing)?
    static func tips(_ piece: [(IVec3, Structure.Mat, Bool)]) -> Bool {
        var weight: Float = 0, mx: Float = 0, mz: Float = 0
        var lo = SIMD2<Int>(Int.max, Int.max), hi = SIMD2<Int>(Int.min, Int.min)
        var hold: Float = 0, feet = 0
        for (c, m, foot) in piece {
            weight += m.weight
            mx += m.weight * (Float(c.x) + 0.5); mz += m.weight * (Float(c.z) + 0.5)
            if foot {
                feet += 1; hold += m.bond
                lo = simd_min(lo, SIMD2(c.x, c.z)); hi = simd_max(hi, SIMD2(c.x + 1, c.z + 1))
            }
        }
        guard weight > 0 else { return false }
        if feet == 0 { return true }                              // (hangs from nothing: P388's check takes it too)
        let cx = mx / weight, cz = mz / weight
        let dx = max(0, Float(lo.x) - cx, cx - Float(hi.x)), dz = max(0, Float(lo.y) - cz, cz - Float(hi.y))
        let lever = (dx * dx + dz * dz).squareRoot()
        return lever > 1 && weight * lever > hold * turnHold
    }
}

extension World {
    // P503: a blast broke built blocks round p (radius r): what stood over it is weighed (StructureTip).
    func queueTipCheck(_ p: IVec3, _ r: Int) {
        guard Structure.enabled, frame == nil, World.reachesWorld(V3(Float(p.x), Float(p.y), Float(p.z)), Float(r)) else { return }
        if let last = tipQueue.last, last.0 == p { return }
        tipQueue.append((p, r))
    }
}

// questcheck --tipcheck (and the full suite): on flat made ground, a 5 x 5 hollow tower of Capital stone 12 high with a
// 9 x 9 cabin on it. A blast takes its top course but one corner: the cabin tips and comes down whole. The same blast
// sparing a corner post at each corner, or one side's wall: it stands. Then the check's cost on a Greywall keep.
enum StructureTipCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 4242, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 3; w.activeDistance = 3
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        let at = V3(40, 200, 40)
        g.player.pos = at
        _ = w.loadSync(center: at, radius: 3)
        let stone = Blocks.has("capital_stone") ? Blocks.id("capital_stone") : STONE
        let ground = FieldMat.index[Int(STONE)]
        func top(_ x: Int, _ z: Int) -> Int { var y = CH - 2; while y > 1 && !w.groundAt(x, y, z) { y -= 1 }; return y }
        // A flat patch of made ground round (x, z): its top at the returned height - 1, open air 30 over it.
        func flat(_ x: Int, _ z: Int) -> Int {
            let y = top(x, z) + 1
            for dz in -7...7 { for dx in -7...7 {
                guard let c = w.chunkAt(x + dx, z + dz) else { continue }
                for yy in (y - 4)..<(y + 30) {
                    let i = Chunk.index(mod(x + dx, CS), yy, mod(z + dz, CS))
                    if yy >= y && c.blocks.raw(i) != AIR { c.blocks[i] = AIR }
                    c.blocks.setDensity(i, yy < y ? 32 : -32, material: yy < y ? ground : nil)
                }
            } }
            return y
        }
        // The tower and its cabin; the blast takes the tower's top course but `keep`.
        func tower(_ x0: Int, _ z0: Int, keep: (Int, Int) -> Bool) -> (tipped: Bool, left: Int) {
            let y = flat(x0 + 2, z0 + 2)
            for k in 0..<12 { for dz in 0..<5 { for dx in 0..<5 where dx == 0 || dx == 4 || dz == 0 || dz == 4 { w.setBlock(x0 + dx, y + k, z0 + dz, stone) } } }
            for k in 12..<16 { for dz in -2..<7 { for dx in -2..<7 where k == 12 || k == 15 || dx == -2 || dx == 6 || dz == -2 || dz == 6 { w.setBlock(x0 + dx, y + k, z0 + dz, stone) } } }
            while !w.loadQueue.isEmpty { Structure.tick(g) }
            for dz in 0..<5 { for dx in 0..<5 where (dx == 0 || dx == 4 || dz == 0 || dz == 4) && !keep(dx, dz) { w.setBlock(x0 + dx, y + 11, z0 + dz, AIR) } }
            while !w.loadQueue.isEmpty { Structure.tick(g) }
            let t0 = tipped
            w.queueTipCheck(IVec3(x0 + 2, y + 11, z0 + 2), 3)
            StructureTip.tick(g)
            var left = 0
            for k in 12..<16 { for dz in -2..<7 { for dx in -2..<7 where w.builtBlock(x0 + dx, y + k, z0 + dz) == stone { left += 1 } } }
            for s in w.ships.list where s.name == Game.toppledName { w.ships.remove(s) }
            Felling.falls.removeAll()
            return (tipped > t0, left)
        }
        var tipped: Int { StructureTip.tipped }
        let corner = tower(20, 20) { dx, dz in dx == 0 && dz == 0 }
        let posts = tower(20, 40) { dx, dz in (dx == 0 || dx == 4) && (dz == 0 || dz == 4) }
        let side = tower(40, 20) { _, dz in dz == 0 }
        check(corner.tipped && corner.left == 0 && !posts.tipped && posts.left > 200 && !side.tipped && side.left > 200,
              "P503: a cabin on one corner of its shot-out tower tipped \(corner.tipped) (\(corner.left) of its blocks left up); on four corner posts it stood (tipped \(posts.tipped), \(posts.left) left), on one side's wall it stood (tipped \(side.tipped), \(side.left) left)")
        // Cost: the check at a blast on a big keep's wall runs to its bound and stops.
        var ms = 0.0
        let kx = 20, kz = 60, ky = flat(kx + 6, kz + 6)
        for k in 0..<24 { for dz in 0..<13 { for dx in 0..<13 where k % 6 == 0 || dx == 0 || dx == 12 || dz == 0 || dz == 12 { w.setBlock(kx + dx, ky + k, kz + dz, stone) } } }
        while !w.loadQueue.isEmpty { Structure.tick(g) }
        let t0 = CFAbsoluteTimeGetCurrent()
        let held = StructureTip.check(w, at: IVec3(kx, ky + 3, kz + 6), r: 4) == nil
        ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        check(held && ms < 40, String(format: "P503: a blast on a whole keep's wall leaves it standing (%@), the check took %.1f ms", held ? "held" : "TIPPED", ms))
    }
}
