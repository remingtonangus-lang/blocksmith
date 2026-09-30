import Foundation

// Nether fortress: a network on a 10-block grid. Open "bridge" cells (5-wide decks with railings,
// support pillars down to the ground) lead from the start crossing to an enclosed "castle" part
// (7-wide corridors with fence windows, chests). Leaves become blaze spawner platforms (bridge) and
// nether wart rooms (castle). Fortresses and bastions share a 27-chunk grid (separation 4); a start
// is a fortress 2 times in 5.
enum Fortress {
    static let cell = 10
    enum Kind { case bridge, castle, blaze, wart }
    struct Node { var kind: Kind; var links: [Bool] }   // links: +x, -x, +z, -z
    static let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    static let type = StructureType(name: "fortress", spacing: 27, separation: 4, salt: 30084232, reach: 6) { seed, cx, cz in
        var rng = SRng(seed)
        if rng.int(5) >= 2 { return nil }            // 3 in 5: a bastion slot
        return layout(&rng, originX: cx * CS + 8, originZ: cz * CS + 8)
    }

    static func layout(_ rng: inout SRng, originX ox: Int, originZ oz: Int) -> StructureStart {
        var nodes: [IVec2Key: Node] = [:]
        let maxR = 5
        nodes[IVec2Key(0, 0)] = Node(kind: .bridge, links: [false, false, false, false])
        var frontier = [IVec2Key(0, 0)]
        let target = rng.range(22, 38)
        var tries = 0
        while nodes.count < target && tries < 600 && !frontier.isEmpty {
            tries += 1
            let from = frontier[rng.int(frontier.count)]
            let d = rng.int(4)
            let to = IVec2Key(from.x + dirs[d].0, from.z + dirs[d].1)
            if abs(to.x) > maxR || abs(to.z) > maxR || nodes[to] != nil { continue }
            let far = abs(to.x) + abs(to.z)
            let parent = nodes[from]!.kind
            // Bridges near the start, castle further out; castle never leads back to bridges.
            let kind: Kind = parent == .castle || (far >= 3 && rng.chance(0.45)) ? .castle : .bridge
            nodes[to] = Node(kind: kind, links: [false, false, false, false])
            nodes[from]!.links[d] = true
            nodes[to]!.links[d ^ 1] = true
            frontier.append(to)
        }
        // Leaves become special rooms: at least one blaze platform.
        let leaves = nodes.filter { $0.key != IVec2Key(0, 0) && $0.value.links.filter { $0 }.count == 1 }.map { $0.key }
            .sorted { ($0.x, $0.z) < ($1.x, $1.z) }
        var blazes = 0
        for k in leaves {
            if nodes[k]!.kind == .bridge && (blazes == 0 || rng.chance(0.5)) { nodes[k]!.kind = .blaze; blazes += 1 }
            else if nodes[k]!.kind == .castle && rng.chance(0.5) { nodes[k]!.kind = .wart }
        }
        if blazes == 0, let k = leaves.first { nodes[k]!.kind = .blaze }

        let y = YOFF + rng.range(48, 70)
        var pieces: [Piece] = []
        let seed = rng.next()
        for (k, n) in nodes {
            let cxw = ox + k.x * cell, czw = oz + k.z * cell
            let r = 6
            let pseed = seed &+ UInt64(bitPattern: Int64(k.x &* 7919 &+ k.z &* 104729))
            pieces.append(Piece(min: IVec3(cxw - r, y - 60, czw - r), max: IVec3(cxw + r, y + 8, czw + r)) { w in
                build(&w, n, cx: cxw, cz: czw, y: y, seed: pseed)
            })
        }
        return StructureStart(kind: "fortress", pieces: pieces)
    }

    // Blocks of one cell. Arms run from the centre to the cell edge (5 cells) along linked directions.
    static func build(_ w: inout StructWriter, _ n: Node, cx: Int, cz: Int, y: Int, seed: UInt64) {
        let brick = Blocks.id("nether_bricks"), fence = Blocks.id("nether_brick_fence")
        let half = cell / 2
        // Rectangles (x0, z0, x1, z1) covering the cell's floor plan with a given half-width.
        func plan(_ hw: Int, room: Int) -> [(Int, Int, Int, Int)] {
            var out = [(cx - room, cz - room, cx + room, cz + room)]
            for d in 0..<4 where n.links[d] {
                let (dx, dz) = dirs[d]
                if dx != 0 { out.append(dx > 0 ? (cx, cz - hw, cx + half, cz + hw) : (cx - half + 1, cz - hw, cx, cz + hw)) }
                else { out.append(dz > 0 ? (cx - hw, cz, cx + hw, cz + half) : (cx - hw, cz - half + 1, cx + hw, cz)) }
            }
            return out
        }
        func isIn(_ x: Int, _ z: Int, _ rs: [(Int, Int, Int, Int)]) -> Bool {
            rs.contains { x >= $0.0 && x <= $0.2 && z >= $0.1 && z <= $0.3 }
        }
        var rng = SRng(seed)
        switch n.kind {
        case .bridge, .blaze:
            let room = n.kind == .blaze ? 4 : 2
            let deck = plan(2, room: room)
            for r in deck {
                w.fill(r.0, y - 1, r.1, r.2, y, r.3, brick)
                w.fill(r.0, y + 1, r.1, r.2, y + 5, r.3, AIR)
            }
            // Railings: deck blocks with a non-deck neighbour get a brick lip and a fence on top.
            for z in (cz - half)...(cz + half) { for x in (cx - half)...(cx + half) where isIn(x, z, deck) {
                let edge = !isIn(x + 1, z, deck) || !isIn(x - 1, z, deck) || !isIn(x, z + 1, deck) || !isIn(x, z - 1, deck)
                let atCellEdge = abs(x - cx) >= half || (x - cx) == -(half - 1) || abs(z - cz) >= half || (z - cz) == -(half - 1)
                if edge && !atCellEdge { w.set(x, y + 1, z, brick); w.set(x, y + 2, z, fence) }
            } }
            // Support pillars under the centre room corners and arches under arms.
            for (px, pz) in [(cx - room, cz - room), (cx + room, cz - room), (cx - room, cz + room), (cx + room, cz + room)] {
                w.pillarDown(px, y - 2, pz, brick, minY: YOFF)
            }
            for d in 0..<4 where n.links[d] {
                let (dx, dz) = dirs[d]
                for s in [-2, 2] {
                    let x = cx + dx * 3 + (dz != 0 ? s : 0), z = cz + dz * 3 + (dx != 0 ? s : 0)
                    w.set(x, y - 2, z, brick); w.set(x, y - 3, z, brick)
                }
            }
            if n.kind == .blaze {
                w.fill(cx - 1, y + 1, cz - 1, cx + 1, y + 1, cz + 1, brick)
                let stairs = Blocks.id("nether_brick_stairs")
                w.set(cx, y + 1, cz - 2, stairs + 1); w.set(cx, y + 1, cz + 2, stairs)
                w.set(cx - 2, y + 1, cz, stairs + 3); w.set(cx + 2, y + 1, cz, stairs + 2)
                w.spawner(cx, y + 2, cz, mob: "blaze")
            }
        case .castle, .wart:
            let room = n.kind == .wart ? 4 : 2
            let outer = plan(3, room: room + 1), inner = plan(2, room: room)
            let h = n.kind == .wart ? 7 : 5
            for r in outer { w.fill(r.0, y - 1, r.1, r.2, y + h + 1, r.3, brick) }
            for r in inner { w.fill(r.0, y + 1, r.1, r.2, y + h, r.3, AIR) }
            // Fence windows in the side walls of arms and the room.
            for z in (cz - half)...(cz + half) { for x in (cx - half)...(cx + half) where isIn(x, z, outer) && !isIn(x, z, inner) {
                let nearOpen = isIn(x + 1, z, inner) || isIn(x - 1, z, inner) || isIn(x, z + 1, inner) || isIn(x, z - 1, inner)
                if nearOpen && (x + z) & 1 == 0 && abs(x - cx) < half && abs(z - cz) < half && abs(x - cx) + abs(z - cz) > 2 {
                    w.set(x, y + 2, z, fence); w.set(x, y + 3, z, fence)
                }
            } }
            for (px, pz) in [(cx - room - 1, cz - room - 1), (cx + room + 1, cz - room - 1), (cx - room - 1, cz + room + 1), (cx + room + 1, cz + room + 1)] {
                w.pillarDown(px, y - 2, pz, brick, minY: YOFF)
            }
            if n.kind == .wart {
                // Two soul sand beds of nether wart with a brick border, stairs up to them.
                let soul = Blocks.id("soul_sand"), wart = Blocks.id("nether_wart")
                for side in [-1, 1] {
                    let bz = cz + side * 3
                    w.fill(cx - 3, y + 1, bz - 0, cx + 3, y + 1, bz, soul)
                    for x in (cx - 3)...(cx + 3) { w.set(x, y + 2, bz, wart + BlockID(rng.int(4))) }
                    w.fill(cx - 4, y + 1, bz + side, cx + 4, y + 1, bz + side, brick)
                }
            } else if rng.chance(0.2) {
                // Chest tucked in the corner of the room.
                let facing = rng.int(4)
                w.chest(cx - room, y + 1, cz - room, loot: "fortress", seed: rng.next(), facing: facing)
            }
        }
    }
}

struct IVec2Key: Hashable { let x: Int; let z: Int; init(_ x: Int, _ z: Int) { self.x = x; self.z = z } }
