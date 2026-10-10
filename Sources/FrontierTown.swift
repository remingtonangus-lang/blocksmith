import Foundation

// Frontier towns (docs/status/honour.md): what a town built after 2026-10-10 adds to the towns of people.
//   - Covered boardwalks: every shop front gets a plank walk the width of its false front, flush with the street, with
//     a slab awning over it on two posts (the old awning only covered the door).
//   - The sheriff's office: the medium house nearest the square becomes a stone-fronted office with the sheriff's desk,
//     a jail cell behind iron bars (its door left open), a WANTED board and a town notice by the door.
// A town whose ground a save had already generated keeps its old lots (StructureCache.legacyFrontier, taken once per
// save like the other structure guards), so no house is finished half as an office across a chunk border.
extension Village {
    // Called by layout once the lots are placed (no random numbers drawn, so a town's streets and lots stay the same).
    static func frontierLots(_ lots: inout [Lot], ox: Int, oz: Int) {
        for i in lots.indices { lots[i].frontier = true }
        func d2(_ l: Lot) -> Int {
            let (x0, z0, x1, z1) = bounds(l)
            let cx = (x0 + x1) / 2 - ox, cz = (z0 + z1) / 2 - oz
            return cx * cx + cz * cz
        }
        // A medium house if the town has one, else a big one, else a small one (never a shop, farm or job hut).
        let rank: [Kind: Int] = [.mediumHouse: 0, .bigHouse: 1, .smallHouse: 2]
        guard let i = lots.indices.filter({ rank[lots[$0].kind] != nil })
                .min(by: { (rank[lots[$0].kind]!, d2(lots[$0])) < (rank[lots[$1].kind]!, d2(lots[$1])) }) else { return }
        let l = lots[i]
        var office = Lot(kind: .office, ax: l.ax, az: l.az, face: l.face, w: l.w, d: l.d, y: l.y, seed: l.seed, job: "sheriff")
        office.frontier = true
        lots[i] = office
    }

    // A plank boardwalk in front of a false front, flush with the street, under a slab awning on two posts.
    static func boardwalk(_ w: inout StructWriter, _ b: LB, _ m: Mats, wallH: Int) {
        let l = b.l
        for u in -1...l.w {
            let (x, z) = world(l, u, -1)
            // Only on ground (a lower street beside a sloping lot keeps its path; no plank hangs over it).
            guard w.inside(x, l.y - 1, z) else { continue }
            let ground = Blocks.collide[Int(w.get(x, l.y - 2, z))]
            if ground { w.set(x, l.y - 1, z, m.planks) }
            // Clear lamp posts and plants under the awning, never a higher street's own path (no notch in it).
            for dy in 0..<(wallH - 1) {
                let cur = w.get(x, l.y + dy, z), k = Blocks.key(Blocks.groupBase[Int(cur)])
                if !Blocks.collide[Int(cur)] || k.contains("fence") || k.contains("lantern") { w.set(x, l.y + dy, z, AIR) }
            }
            // The awning's two posts stand only on ground (no post hangs over a lower street).
            if (u == -1 || u == l.w) && ground && !Blocks.collide[Int(w.get(x, l.y, z))] {
                for dy in 0..<(wallH - 1) { w.set(x, l.y + dy, z, m.fence) }
            }
            b.set(&w, u, wallH - 1, -1, m.slab)
        }
    }

    static func officeLot(_ w: inout StructWriter, _ b: LB, _ m0: Mats) {
        let l = b.l
        let m = varied(m0, l)
        let wallH = 5
        house(&w, b, m0, wallH: wallH)
        let stone = blk("stone_bricks", COBBLE)
        // A stone front (the door, its windows and the log corners kept).
        let du = l.w / 2
        for u in 1...(l.w - 2) where u != du { for dy in 1..<wallH where !(dy == 1 && u % 2 == 0) { b.set(&w, u, dy, 0, stone) } }
        falseFront(&w, b, m, wallH: wallH, band: blk("light_gray_terracotta", stone))
        boardwalk(&w, b, m, wallH: wallH)
        sign(&w, b, u: du, dy: 2, v: -1, lines: ["", "Sheriff", "and Jail", ""])
        sign(&w, b, u: 1, dy: 1, v: -1, lines: ["WANTED", "Dead or Alive", "Reward", "$50"])
        sign(&w, b, u: l.w - 2, dy: 1, v: -1, lines: ["NOTICE", "No guns drawn", "in town", "- The Law"])
        // The sheriff's desk by the window with his chair behind it (a small office has no room for the chair), a lamp, a filing shelf.
        let desk = blk("stripped_\(Blocks.key(m.log).replacingOccurrences(of: "stripped_", with: ""))", m.planks)
        b.set(&w, 1, 0, 1, desk)
        if du > 2 { b.set(&w, 2, 0, 1, desk) }                // (in a small office the doorway is at u 2)
        b.set(&w, 1, 1, 1, blk("lantern", AIR))
        let cellV = l.d - 3
        if cellV > 2 { b.set(&w, 1, 0, 2, b.stair(m.stairs, high: 0)) }
        if du > 2 { b.set(&w, l.w - 2, 0, 1, blk("bookshelf", m.planks)) }   // (a small office keeps the way to its cell clear)
        // The jail cell across the back: iron bars with the cell door left open, a hay bunk, a bucket.
        let bars = blk("iron_bars", m.fence)
        for u in 1...(l.w - 2) where u != l.w - 2 { for dy in 0...2 { b.set(&w, u, dy, cellV, bars) } }
        b.set(&w, 1, 0, l.d - 2, blk("hay_block", m.planks))
        b.set(&w, 3, 0, l.d - 2, blk("cauldron", AIR))
        b.set(&w, 1, 2, 1, b.wallTorch(facing: 2))
        b.set(&w, l.w - 2, 2, l.d - 2, b.wallTorch(facing: 1))
    }
}
