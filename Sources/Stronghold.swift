import Foundation

// Strongholds: 128 per world in eight rings around the origin (3, 6, 10, 15, 21, 28, 36, 9 — the
// reference game's distribution; the first ring 1280–2816 blocks out). Each is a branching network of
// stone-brick corridors on a 12-block grid: the spiral-stair start, crossings, libraries, prison cells,
// chest corridors and exactly one portal room (the farthest leaf) with twelve hollow gate frames
// (each 10% pre-filled with an eye) around a lava pool and a silverfish spawner.
enum Stronghold {
    static let cell = 12
    enum Kind { case start, corridor, crossing, library, prison, chest, portal }
    struct Node { var kind: Kind; var links: [Bool] }
    static let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    static func positions(seed: UInt64) -> [(Int, Int)] {
        var rng = SRng(seed ^ 0x57A0)
        var out: [(Int, Int)] = []
        let counts = [3, 6, 10, 15, 21, 28, 36, 9]
        var angle = Double(rng.float()) * 2 * .pi
        for (ring, n) in counts.enumerated() {
            for _ in 0..<n {
                let spread = 32.0
                let dist = (4 * spread + spread * Double(ring) * 6) + (Double(rng.float()) - 0.5) * spread * 2.5
                let cx = Int((cos(angle) * dist).rounded()), cz = Int((sin(angle) * dist).rounded())
                out.append((cx * CS + 4, cz * CS + 4))
                angle += 2 * .pi / Double(n)
            }
            angle += Double(rng.float()) * 2 * .pi
        }
        return out
    }

    static func starts(seed: UInt64) -> [StructureStart] {
        positions(seed: seed).enumerated().map { i, p in
            var rng = SRng(seed &+ UInt64(i) &* 7_777_777 &+ 0x5701)
            return layout(&rng, ox: p.0, oz: p.1)
        }
    }

    static func mat(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        let h = hashf(x, y, z, 0x5B41)
        if h < 0.6 { return Blocks.id("stone_bricks") }
        if h < 0.8 { return Blocks.id("mossy_stone_bricks") }
        if h < 0.95 { return Blocks.id("cracked_stone_bricks") }
        return Blocks.id("infested_stone_bricks")
    }

    static func layout(_ rng: inout SRng, ox: Int, oz: Int) -> StructureStart {
        var nodes: [IVec2Key: Node] = [IVec2Key(0, 0): Node(kind: .start, links: [false, false, false, false])]
        var frontier = [IVec2Key(0, 0)]
        let target = rng.range(18, 30)
        var tries = 0
        while nodes.count < target && tries < 500 {
            tries += 1
            let from = frontier[rng.int(frontier.count)]
            let d = rng.int(4)
            let to = IVec2Key(from.x + dirs[d].0, from.z + dirs[d].1)
            if abs(to.x) > 5 || abs(to.z) > 5 || nodes[to] != nil { continue }
            let r = rng.int(10)
            let kind: Kind = r < 5 ? .corridor : (r < 7 ? .crossing : (r < 8 ? .prison : .chest))
            nodes[to] = Node(kind: kind, links: [false, false, false, false])
            nodes[from]!.links[d] = true
            nodes[to]!.links[d ^ 1] = true
            frontier.append(to)
        }
        // The farthest leaf becomes the portal room; other leaves may be libraries.
        func isLeaf(_ k: IVec2Key, _ n: Node) -> Bool { k != IVec2Key(0, 0) && n.links.filter { $0 }.count == 1 }
        func rank(_ k: IVec2Key) -> Int { (k.x * k.x + k.z * k.z) * 10_000 + (k.x + 50) * 100 + (k.z + 50) }
        let leaves: [IVec2Key] = nodes.filter { isLeaf($0.key, $0.value) }.map { $0.key }.sorted { rank($0) > rank($1) }
        if let far = leaves.first { nodes[far]!.kind = .portal }
        else {
            // Degenerate layout: hang the portal room off the start.
            nodes[IVec2Key(1, 0)] = Node(kind: .portal, links: [false, true, false, false])
            nodes[IVec2Key(0, 0)]!.links[0] = true
        }
        for k in leaves.dropFirst() where rng.chance(0.35) { nodes[k]!.kind = .library }

        let y = YOFF + rng.range(-10, 30)
        let seed = rng.next()
        var pieces: [Piece] = []
        var portalAt = IVec3(ox, y, oz)
        for (k, n) in nodes {
            let cx = ox + k.x * cell, cz = oz + k.z * cell
            if n.kind == .portal { portalAt = IVec3(cx, y, cz) }
            let pseed = seed &+ UInt64(bitPattern: Int64(k.x &* 92821 &+ k.z &* 68917))
            pieces.append(Piece(min: IVec3(cx - 6, y - 1, cz - 6), max: IVec3(cx + 6, y + 40, cz + 6)) { w in
                build(&w, n, cx: cx, cz: cz, y: y, seed: pseed)
            })
        }
        return StructureStart(kind: "stronghold", pieces: pieces, anchor: IVec3(portalAt.x, portalAt.y + 1, portalAt.z - 5))
    }

    // Stone-brick shell over the plan (walls 1 thick) with the inside carved out.
    static func shell(_ w: inout StructWriter, _ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int) {
        for y in y0...y1 { for z in z0...z1 { for x in x0...x1 where w.inside(x, y, z) {
            let wall = x == x0 || x == x1 || z == z0 || z == z1 || y == y0 || y == y1
            w.set(x, y, z, wall ? mat(x, y, z) : AIR)
        } } }
    }

    static func build(_ w: inout StructWriter, _ n: Node, cx: Int, cz: Int, y: Int, seed: UInt64) {
        var rng = SRng(seed)
        let half = cell / 2
        // Corridors out to each linked neighbour (3 wide, 3 tall inside).
        for d in 0..<4 where n.links[d] {
            let (dx, dz) = dirs[d]
            if dx != 0 {
                let a = dx > 0 ? cx : cx - half, b = dx > 0 ? cx + half : cx
                shell(&w, a, y, cz - 2, b, y + 4, cz + 2)
            } else {
                let a = dz > 0 ? cz : cz - half, b = dz > 0 ? cz + half : cz
                shell(&w, cx - 2, y, a, cx + 2, y + 4, b)
            }
            // Open the corridor's end at the cell edge: both neighbours' corridor shells put an end wall on the same
            // plane, which sealed every room off from the next (structcheck: all 80 stronghold POIs unreachable).
            let ex = cx + dx * half, ez = cz + dz * half
            let ox: Int = dz != 0 ? 1 : 0, oz: Int = dx != 0 ? 1 : 0
            w.fill(ex - ox, y + 1, ez - oz, ex + ox, y + 3, ez + oz, AIR)
        }
        func openings(_ r: Int, _ top: Int) {
            for d in 0..<4 where n.links[d] {
                let (dx, dz) = dirs[d]
                let px = cx + dx * r, pz = cz + dz * r
                w.fill(px - (dz != 0 ? 1 : 0), y + 1, pz - (dx != 0 ? 1 : 0), px + (dz != 0 ? 1 : 0), y + min(3, top), pz + (dx != 0 ? 1 : 0), AIR)
            }
        }
        switch n.kind {
        case .corridor:
            shell(&w, cx - 2, y, cz - 2, cx + 2, y + 4, cz + 2)
            openings(2, 3)
            if rng.chance(0.3) { w.set(cx + 1, y + 3, cz + 1, Blocks.id("torch")) }
        case .chest:
            shell(&w, cx - 3, y, cz - 3, cx + 3, y + 5, cz + 3)
            openings(3, 3)
            w.chest(cx + 2, y + 1, cz + 2, loot: "stronghold_corridor", seed: rng.next(), facing: 2)
            w.set(cx - 2, y + 3, cz - 2, Blocks.id("torch"))
        case .start, .crossing:
            shell(&w, cx - 5, y, cz - 5, cx + 5, y + 8, cz + 5)
            openings(5, 3)
            if n.kind == .start {
                // Spiral stair up the middle toward the surface.
                let st = Blocks.id("stone_brick_stairs")
                for i in 0..<30 {
                    let yy = y + 1 + i
                    let a = i % 4
                    let (sx, sz) = [(0, -1), (1, 0), (0, 1), (-1, 0)][a]
                    w.set(cx, yy, cz, Blocks.id("stone_bricks"))
                    if yy > y + 7 { w.fill(cx - 2, yy, cz - 2, cx + 2, yy, cz + 2, AIR); w.set(cx, yy, cz, Blocks.id("stone_bricks")) }
                    w.set(cx + sx, yy, cz + sz, st + BlockID([0, 3, 1, 2][a]))
                }
            } else {
                // Crossing: a pillar in the middle with torches, sometimes a fountain.
                if rng.chance(0.5) {
                    w.fill(cx - 1, y + 1, cz - 1, cx + 1, y + 7, cz + 1, Blocks.id("stone_bricks"))
                    for (tx, tz) in [(-2, 0), (2, 0), (0, -2), (0, 2)] { w.set(cx + tx, y + 4, cz + tz, Blocks.id("torch")) }
                } else {
                    w.fill(cx - 2, y + 1, cz - 2, cx + 2, y + 1, cz + 2, Blocks.id("stone_brick_slab"))
                    w.fill(cx - 1, y + 1, cz - 1, cx + 1, y + 1, cz + 1, WATER)
                    w.set(cx, y + 2, cz, Blocks.id("chiseled_stone_bricks"))
                    w.set(cx, y + 3, cz, WATER)
                }
            }
        case .prison:
            shell(&w, cx - 5, y, cz - 5, cx + 5, y + 5, cz + 5)
            openings(5, 3)
            let bars = Blocks.id("iron_bars")
            for side in [-1, 1] {
                for x in stride(from: cx - 4, through: cx + 4, by: 3) {
                    w.fill(x, y + 1, cz + side * 3, x + 1, y + 3, cz + side * 3, bars)
                }
                w.fill(cx - 4, y + 1, cz + side * 4, cx + 4, y + 4, cz + side * 4, AIR)
            }
        case .library:
            shell(&w, cx - 5, y, cz - 5, cx + 5, y + 10, cz + 5)
            openings(5, 3)
            let shelf = Blocks.id("bookshelf"), web = Blocks.id("cobweb")
            for z in (cz - 4)...(cz + 4) { for x in (cx - 4)...(cx + 4) {
                let wallRow = abs(x - cx) == 4 || abs(z - cz) == 4
                let shelfRow = (z - cz) % 3 == 0 && abs(x - cx) <= 2
                if (wallRow && !(abs(x - cx) <= 1 || abs(z - cz) <= 1)) || shelfRow {
                    w.fill(x, y + 1, z, x, y + (wallRow ? 7 : 3), z, shelf)
                }
                if hashf(x, y, z, 0xB00C) < 0.08 { w.set(x, y + 8, z, web) }
            } }
            // Balcony walkway with the library chest.
            w.fill(cx - 4, y + 5, cz - 4, cx + 4, y + 5, cz - 3, Blocks.id("oak_planks"))
            // A ladder up to it against the shelf row underneath (the balcony chest had no way up).
            for yy in (y + 1)...(y + 5) { w.set(cx, yy, cz - 2, Blocks.id("ladder") + 2) }
            w.chest(cx + 3, y + 6, cz - 4, loot: "stronghold_library", seed: rng.next(), facing: 1)
            w.chest(cx - 3, y + 1, cz + 3, loot: "stronghold_library", seed: rng.next(), facing: 0)
        case .portal:
            shell(&w, cx - 5, y, cz - 6, cx + 5, y + 9, cz + 6)
            // The room is 13 long in z: its z walls sit at +-6, so cut there too (a portal room linked along z stayed
            // sealed: structcheck, 2 of 9 strongholds reached only the portal room).
            openings(5, 3)
            openings(6, 3)
            let frame = Blocks.id("end_portal_frame")
            let pz = cz + 2
            // Raised platform, lava pool under the portal, stairs up from the entrance side.
            w.fill(cx - 3, y + 1, pz - 3, cx + 3, y + 3, pz + 3, Blocks.id("stone_bricks"))
            w.fill(cx - 1, y + 3, pz - 1, cx + 1, y + 3, pz + 1, LAVA)
            for i in -1...1 {
                w.set(cx + i, y + 4, pz - 2, frame + (rng.chance(0.1) ? 1 : 0))
                w.set(cx + i, y + 4, pz + 2, frame + (rng.chance(0.1) ? 1 : 0))
                w.set(cx - 2, y + 4, pz + i, frame + (rng.chance(0.1) ? 1 : 0))
                w.set(cx + 2, y + 4, pz + i, frame + (rng.chance(0.1) ? 1 : 0))
            }
            let st = Blocks.id("stone_brick_stairs")
            for (i, yy) in [(0, 1), (1, 2), (2, 3)] { w.fill(cx - 1, y + yy, pz - 6 + i, cx + 1, y + yy, pz - 6 + i, st + 1) }
            w.spawner(cx, y + 4, pz - 3, mob: "silverfish")
            for (tx, tz) in [(-4, -5), (4, -5), (-4, 5), (4, 5)] { w.set(cx + tx, y + 3, cz + tz, Blocks.id("torch")) }
            // Iron-bar windows along the sides.
            for z in stride(from: cz - 4, through: cz + 4, by: 2) {
                w.fill(cx - 5, y + 5, z, cx - 5, y + 6, z, Blocks.id("iron_bars"))
                w.fill(cx + 5, y + 5, z, cx + 5, y + 6, z, Blocks.id("iron_bars"))
            }
        }
    }
}
