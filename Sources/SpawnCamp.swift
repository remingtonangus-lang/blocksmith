import Foundation
import simd

// P402 (2): the first hour teaches itself (NO TEXT: the world shows a new player what to do). A new survival world
// starts beside an abandoned camp: a lit campfire (smoke and light that draw the eye), a workbench (crafting), a chest
// of starter things (a wooden axe and pickaxe, bread, torches) and a lean-to's broken frame of logs and planks (wood
// builds shelter). If trees stand off the camp, torches along the way lead to the nearest one (wood first). Placed
// once, when the world is made (WorldRequest.setUp, App.makeGame); built blocks, so the player can take it all apart.
extension Game {
    struct CampLayout { var fire: IVec3; var bench: IVec3; var chest: IVec3; var frame: [IVec3]; var path: [IVec3]; var tree: IVec3? }

    @discardableResult
    func placeSpawnCamp() -> CampLayout? {
        guard survival, ["campfire", "crafting_table", "chest", "oak_log", "oak_planks"].allSatisfy({ Blocks.has($0) }) else { return nil }
        let w = world
        let p = player.pos
        _ = w.loadSync(center: p, radius: 2)
        let sx = Int(floor(p.x)), sz = Int(floor(p.z))
        // The nearest tree (a log standing on others or the ground, leaves above) within 28 blocks.
        var tree: IVec3? = nil, best = Int.max
        for dz in -28...28 { for dx in -28...28 where dx * dx + dz * dz < best && dx * dx + dz * dz <= 28 * 28 {
            let x = sx + dx, z = sz + dz
            let top = w.topY(x, z)
            for y in stride(from: top, through: max(1, top - 12), by: -1) {
                let k = Blocks.key(Blocks.groupBase[Int(w.block(x, y, z))])
                if k.hasSuffix("_log") || k.hasSuffix("_stem") { tree = IVec3(x, y, z); best = dx * dx + dz * dz; break }
            }
        } }
        // The ground cell over which a camp piece stands: dry, open, within a few blocks of the spawn's height.
        // (read as settleSpawn does: the field's ground and the built layer, so it holds in field worlds too)
        let sy = Int(floor(p.y))
        func ground(_ x: Int, _ z: Int) -> Int? {
            // (grass and flowers count as open: the camp's blocks replace them)
            func open(_ y: Int) -> Bool {
                let b = w.builtBlock(x, y, z)
                return (b == AIR || Blocks.replaceable[Int(b)] && !Blocks.isLiquid(b)) && !w.groundAt(x, y, z)
            }
            for y in stride(from: sy + 3, through: sy - 4, by: -1) {
                guard open(y), open(y + 1) else { continue }
                let below = w.builtBlock(x, y - 1, z)
                if below == AIR || open(y - 1) {
                    if w.groundAt(x, y - 1, z) { return y }
                    continue
                }
                let k = Blocks.key(Blocks.groupBase[Int(below)])
                // (not on a tree: its leaves, logs or a mangrove's roots)
                if Blocks.fullCollide[Int(below)] && Blocks.fluidKind[Int(below)] == 0 && !k.hasSuffix("leaves") && !k.contains("roots")
                    && !k.hasSuffix("_log") && !k.hasSuffix("_wood") { return y }
                return nil
            }
            return nil
        }
        // The camp 4 blocks ahead of the spawn (the way a new player first faces), turned off toward the tree.
        let fwd = V2(-sinf(player.yaw), -cosf(player.yaw))
        var dir = fwd
        if let t = tree {
            let d = V2(Float(t.x - sx), Float(t.z - sz))
            if simd_length(d) > 0.5 { dir = simd_normalize(fwd * 1.6 + simd_normalize(d)) }
        }
        // (the first spot, from 4 blocks straight ahead turning out to either side and nearer or farther, where the fire,
        // the bench and the chest all stand on dry ground; else the spot that fits the most pieces)
        func axes(_ d: V2) -> (IVec3, IVec3) {
            abs(d.x) > abs(d.y) ? (IVec3(0, 0, 1), IVec3(d.x > 0 ? 1 : -1, 0, 0)) : (IVec3(1, 0, 0), IVec3(0, 0, d.y > 0 ? 1 : -1))
        }
        var pick: (Int, Int, Int, V2)? = nil, pickScore = 0
        search: for r in [4, 3, 5, 6, 2] as [Float] { for turn in [0, 30, -30, 60, -60, 90, -90, 135, -135, 180] as [Float] {
            let a = turn * .pi / 180
            let d = V2(dir.x * cosf(a) - dir.y * sinf(a), dir.x * sinf(a) + dir.y * cosf(a))
            let x = sx + Int((d.x * r).rounded()), z = sz + Int((d.y * r).rounded())
            guard let y = ground(x, z) else { continue }
            let (sd, aw) = axes(d)
            func o(_ a: Int, _ b: Int) -> IVec3 { IVec3(aw.x * a + sd.x * b, 0, aw.z * a + sd.z * b) }
            // (a piece counts where it stands level with the fire, give or take a block)
            func fits(_ q: IVec3) -> Bool { ground(x + q.x, z + q.z).map { abs($0 - y) <= 1 } ?? false }
            let core = [o(0, 2), o(0, -2)].filter(fits).count
            let rest = [o(2, 1), o(2, -1), o(2, 0), o(3, -1)].filter(fits).count
            let score = 1 + core * 10 + rest
            if score > pickScore { pick = (x, y, z, d); pickScore = score }
            if core == 2 && rest >= 3 { break search }
        } }
        guard let (cx, fy, cz, cdir) = pick else { return nil }
        // (sideways to the camp's axis: bench one side of the fire, chest the other)
        let (side, away) = axes(cdir)
        func at(_ o: IVec3) -> IVec3? {
            let x = cx + o.x, z = cz + o.z
            guard let y = ground(x, z), abs(y - fy) <= 1 else { return nil }
            return IVec3(x, y, z)
        }
        let fire = IVec3(cx, fy, cz)
        w.setBlock(fire.x, fire.y, fire.z, Blocks.id("campfire"))
        var layout = CampLayout(fire: fire, bench: fire, chest: fire, frame: [], path: [], tree: tree)
        if let b = at(IVec3(2 * side.x, 0, 2 * side.z)) { w.setBlock(b.x, b.y, b.z, Blocks.id("crafting_table")); layout.bench = b }
        if let c = at(IVec3(-2 * side.x, 0, -2 * side.z)) {
            w.setBlock(c.x, c.y, c.z, Blocks.id("chest"))
            let be = w.entity(c, .chest)
            w.blockEntities[c] = be
            let stock: [(String, Int)] = [("wooden_axe", 1), ("wooden_pickaxe", 1), ("bread", 3), ("torch", 6), ("oak_log", 2)]
            for (k, (key, n)) in stock.enumerated() where Items.has(key) && k < be.container.slots.count {
                be.container[k] = ItemStack(Items.id(key), n)
            }
            layout.chest = c
        }
        // The lean-to's broken frame behind the fire: two posts (one fallen short), a plank or two of its roof.
        let log = Blocks.id("oak_log"), plank = Blocks.id("oak_planks")
        for (o, h) in [(IVec3(2 * away.x + side.x, 0, 2 * away.z + side.z), 2), (IVec3(2 * away.x - side.x, 0, 2 * away.z - side.z), 1)] as [(IVec3, Int)] {
            guard let b = at(o) else { continue }
            for k in 0..<h { w.setBlock(b.x, b.y + k, b.z, log); layout.frame.append(IVec3(b.x, b.y + k, b.z)) }
        }
        if let b = at(IVec3(2 * away.x, 0, 2 * away.z)) { w.setBlock(b.x, b.y, b.z, plank); layout.frame.append(b) }
        if let b = at(IVec3(3 * away.x - side.x, 0, 3 * away.z - side.z)) { w.setBlock(b.x, b.y, b.z, plank); layout.frame.append(b) }
        // A lit way to the tree: a torch every 4 blocks from the camp, stopping 3 short of the trunk.
        if let t = tree, Blocks.has("torch") {
            let a = V2(Float(cx) + 0.5, Float(cz) + 0.5), e = V2(Float(t.x) + 0.5, Float(t.z) + 0.5)
            let len = simd_length(e - a)
            if len > 7 {
                let u = (e - a) / len
                var s: Float = 3
                while s < len - 3 {
                    let q = a + u * s
                    let x = Int(floor(q.x)), z = Int(floor(q.y))
                    if let y = ground(x, z) { w.setBlock(x, y, z, TORCH); layout.path.append(IVec3(x, y, z)) }
                    s += 4
                }
            }
        }
        // (the ground rises to each piece's floor, as under a block the player places: no gap under the bench or chest)
        for c in [layout.fire, layout.bench, layout.chest] + layout.frame + layout.path { w.meetGround(c.x, c.y, c.z, w.builtBlock(c.x, c.y, c.z)) }
        return layout
    }
}
