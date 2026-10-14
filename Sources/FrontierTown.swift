import Foundation

// Frontier towns (docs/status/honour.md): what a town built after 2026-10-10 adds to the towns of people.
//   - Covered boardwalks: every shop front gets a plank walk the width of its false front, flush with the street, with
//     a slab awning over it on two posts (the old awning only covered the door).
//   - The sheriff's office: the medium house nearest the square becomes a stone-fronted office with the sheriff's desk,
//     two stone jail cells behind iron bars and open iron doors, a strongbox, a WANTED board and a town notice by the door.
// A town whose ground a save had already generated keeps its old lots (StructureCache.legacyFrontier, taken once per
// save like the other structure guards), so no house is finished half as an office across a chunk border.
extension Village {
    // Called by layout once the lots are placed (no random numbers drawn, so a town's streets and lots stay the same).
    static func frontierLots(_ lots: inout [Lot], ox: Int, oz: Int, bank: Bool = true, r20: Bool = false) {
        for i in lots.indices { lots[i].frontier = true }
        func d2(_ l: Lot) -> Int {
            let (x0, z0, x1, z1) = bounds(l)
            let cx = (x0 + x1) / 2 - ox, cz = (z0 + z1) / 2 - oz
            return cx * cx + cz * cz
        }
        // A medium house if the town has one, else a big one, else a small one (never a shop, farm or job hut).
        // (R20: the stone jail wants room for two proper cells, so a big house first.)
        let rank: [Kind: Int] = r20 ? [.bigHouse: 0, .mediumHouse: 1, .smallHouse: 2] : [.mediumHouse: 0, .bigHouse: 1, .smallHouse: 2]
        guard let i = lots.indices.filter({ rank[lots[$0].kind] != nil })
                .min(by: { (rank[lots[$0].kind]!, d2(lots[$0])) < (rank[lots[$1].kind]!, d2(lots[$1])) }) else { return }
        let l = lots[i]
        var office = Lot(kind: .office, ax: l.ax, az: l.az, face: l.face, w: l.w, d: l.d, y: l.y, seed: l.seed, job: "sheriff")
        office.frontier = true
        office.r20 = r20
        lots[i] = office
        // The bank: the next house nearest the square, at least 5 wide (TownServices.swift: emerald exchange, savings).
        guard bank else { return }
        // (a town whose only house became the office gives up a job hut: every frontier town has its bank).
        let bankRank = rank.merging([.jobHut: 3]) { a, _ in a }
        guard let j = lots.indices.filter({ bankRank[lots[$0].kind] != nil && lots[$0].w >= 5 && $0 != i })
                .min(by: { (bankRank[lots[$0].kind]!, d2(lots[$0])) < (bankRank[lots[$1].kind]!, d2(lots[$1])) }) else { return }
        let h = lots[j]
        var bankLot = Lot(kind: .bank, ax: h.ax, az: h.az, face: h.face, w: h.w, d: h.d, y: h.y, seed: h.seed, job: "banker")
        bankLot.frontier = true
        lots[j] = bankLot
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

    // The bank: a stone front like the office, a teller's counter with iron bars and the banker behind it, the vault at
    // the back (a gold and iron strongroom behind bars) and a lamp. The banker opens the bank (TownServices.swift).
    static func bankLot(_ w: inout StructWriter, _ b: LB, _ m0: Mats) {
        let l = b.l
        let m = varied(m0, l)
        let wallH = 5
        house(&w, b, m0, wallH: wallH)
        let stone = blk("stone_bricks", COBBLE)
        let du = l.w / 2
        for u in 1...(l.w - 2) where u != du { for dy in 1..<wallH where !(dy == 1 && u % 2 == 0) { b.set(&w, u, dy, 0, stone) } }
        falseFront(&w, b, m, wallH: wallH, band: blk("yellow_terracotta", stone))
        boardwalk(&w, b, m, wallH: wallH)
        sign(&w, b, u: du, dy: 2, v: -1, lines: ["", "BANK", "Savings and", "Exchange"])
        // (G14, R20) The exchange spelled out at the door, beside the window, with its rate (Exchange, TownServices).
        sign(&w, b, u: 1, dy: 1, v: -1, lines: Exchange.signLines)
        // The teller's counter across the room, bars over it, always a clear row in from the door (a small bank puts the
        // counter one row nearer the strongroom), a gap at the door's line to reach the teller and one at the wall side to
        // walk behind it; the lamp stands on its end, never in the way in.
        let cv = l.d >= 6 ? l.d - 4 : l.d - 3
        let counter = blk("polished_andesite", m.planks)
        let bars = blk("iron_bars", m.fence)
        for u in 1...(l.w - 3) {
            b.set(&w, u, 0, cv, counter)
            b.set(&w, u, 1, cv, u == 1 ? blk("lantern", AIR) : (u == du ? AIR : bars))
        }
        // The strongroom: the back row, gold and iron behind bars.
        for u in 1...(l.w - 2) where u % 2 == 1 && !(u == du && cv + 1 == l.d - 2) { b.set(&w, u, 0, l.d - 2, blk(u % 4 == 1 ? "gold_block" : "iron_block", stone)) }
        b.set(&w, 1, 2, 1, b.wallTorch(facing: 2))
        b.set(&w, l.w - 2, 2, 1, b.wallTorch(facing: 3))
        // H14: the banker's cot behind the counter, clear of the strongroom's bars and the walk-behind gap (a deep bank).
        if l.d >= 6, let u = stride(from: 2, through: l.w - 3, by: 2).first(where: { $0 != du }) { bed(&w, b, m, u: u, v: cv + 1) }
        let (x, z) = world(l, du, cv + 1)
        w.mob("villager:banker", V3(Float(x) + 0.5, Float(l.y), Float(z) + 0.5))
    }

    static func officeLot(_ w: inout StructWriter, _ b: LB, _ m0: Mats) {
        if b.l.r20 { jailLot(&w, b, m0); return }                  // R20's stone jail (TownJail.swift)
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
        sign(&w, b, u: du, dy: 2, v: -1, lines: ["", "JAIL", "Sheriff's Office", ""])
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
        // The cell block across the back (Oct 11 playtest P37/G14: one long barred row with glass windows, a hay bale
        // and a gap for a door read as a stall, not a jail). Now: stone walls, a stone floor and barred windows round
        // the back row, split into two cells by a stone wall where the office is wide enough, each with a front of bars
        // and an iron door (left open, so no one is shut in for good), a plank bunk, a bucket and a chain on the wall.
        let bars = blk("iron_bars", m.fence)
        let ironDoor = blk("iron_door", m.door)
        let floor = blk("cobblestone", COBBLE)
        let inner = l.w - 2                                        // cell row width (u 1...l.w-2)
        let split = inner >= 5 && cellV > 2 ? du : -1              // the partition column (the doorway's line), or none
        // The doors: one per cell, either side of the partition (the desk and chair leave those columns free).
        let doors: [Int] = split > 0 ? [split - 1, split + 1] : [l.w - 2]
        for v in cellV...(l.d - 1) {
            for u in 0...(l.w - 1) where u == 0 || u == l.w - 1 || v == l.d - 1 {
                // Stone walls round the cells (the log corners kept), a barred window over each bunk.
                let corner = (u == 0 || u == l.w - 1) && v == l.d - 1
                if corner { continue }
                for dy in 0..<wallH { b.set(&w, u, dy, v, dy == 2 && v == l.d - 1 && (u == 1 || u == l.w - 2) ? bars : stone) }
            }
        }
        for u in 1...(l.w - 2) {
            b.set(&w, u, -1, l.d - 2, floor)
            if cellV < l.d - 2 { for v in (cellV + 1)..<(l.d - 1) { b.set(&w, u, -1, v, floor) } }
            for dy in 0...2 {
                if u == split { b.set(&w, u, dy, cellV, stone); continue }
                if doors.contains(u) {
                    // Facing the street like the front door, shut (R20: an open cell read as a stall; nobody walks into
                    // one by mistake, and an arrest shuts the player in: TownJail.swift opens it on release).
                    let f = dir(l, 1)
                    b.set(&w, u, dy, cellV, dy == 0 ? ironDoor + BlockID(f) : (dy == 1 ? ironDoor + BlockID(f + 8) : bars))
                } else { b.set(&w, u, dy, cellV, bars) }
            }
            if u == split { for v in (cellV + 1)..<(l.d - 1) { for dy in 0..<wallH { b.set(&w, u, dy, v, stone) } } }
        }
        // In each cell: a bunk under the window and a chain hanging from the ceiling over it; a deeper cell gets a
        // bucket too (a one-row cell keeps its floor clear inside the door). (R20: the bucket went at l.d - 3, which is
        // the bar row itself here, so every cell front had a cauldron in its bars.)
        for (u, cell) in [(1, 0), (l.w - 2, 1)] where split > 0 || cell == 0 {
            b.set(&w, u, 0, l.d - 2, m.slab)
            for dy in 3..<wallH { b.set(&w, u, dy, l.d - 2, blk("chain", AIR)) }
            if cellV < l.d - 3 { b.set(&w, u, 0, l.d - 3, blk("cauldron", AIR)) }
        }
        b.set(&w, 1, 2, 1, b.wallTorch(facing: 2))
        b.set(&w, l.w - 2, 2, cellV - 1, b.wallTorch(facing: 3))
        // The strongbox of confiscated goods beside the second cell's door (theft from it is theft like any town container,
        // TownLaw); only where two cells leave the way to the doors clear.
        if split > 0 && du > 2 {
            let (x, z) = world(l, l.w - 2, 2)
            var rng = SRng(l.seed &+ 0x5E1F)
            w.chest(x, l.y, z, loot: "sheriff_locker", seed: rng.next(), facing: dir(l, 3))
        }
    }
}

// R20 streets (Village.layout): soft ground cut back over a street, and a walk from each door to the street where a
// shoulder gave out on a slope.
extension Village {
    static let streetCut: Set<BlockID> = {
        var s: Set<BlockID> = [GRASS, DIRT, SAND, GRAVEL, SNOW, SNOWY_GRASS]
        for n in ["coarse_dirt", "podzol", "snow", "rooted_dirt", "red_sand", "mud"] where Blocks.has(n) { s.insert(Blocks.id(n)) }
        return s
    }()

    static func doorWalks(_ gen: WorldGen, _ lots: [Lot], pathCols: [(Int, Int, Int)], shoulders: [IVec2Key: [(Int, Int, Int)]],
                          _ m: Mats) -> [Piece] {
        var road = Set<IVec2Key>()
        for c in pathCols { road.insert(IVec2Key(c.0, c.1)) }
        for (_, list) in shoulders { for c in list { road.insert(IVec2Key(c.0, c.1)) } }
        var out: [Piece] = []
        for l in lots where l.kind != .farm {
            // Out from the door's step (v -1, the house's own) toward the street, until a street column.
            var cols: [(Int, Int)] = []
            var reached = false
            for k in 2...6 {
                let (x, z) = world(l, l.w / 2, -k)
                if road.contains(IVec2Key(x, z)) { reached = true; break }
                cols.append((x, z))
            }
            guard reached, !cols.isEmpty else { continue }
            let y = l.kind == .smithy ? l.y : l.y - 1            // the street's level (the smithy's floor is its bottom layer)
            let xs = cols.map { $0.0 }, zs = cols.map { $0.1 }
            let walk = cols
            out.append(Piece(min: IVec3(xs.min()!, y - 4, zs.min()!), max: IVec3(xs.max()!, y + 3, zs.max()!)) { w in
                for (x, z) in walk where w.inside(x, y, z) {
                    let cur = w.get(x, y, z)
                    if Blocks.isLiquid(cur) { continue }
                    w.pillarDown(x, y - 1, z, m.foundation, minY: y - 4)
                    w.set(x, y, z, m.path)
                    for k in 1...3 {
                        let b = w.get(x, y + k, z)
                        if (Blocks.replaceable[Int(b)] && !Blocks.isLiquid(b)) || streetCut.contains(b) { w.set(x, y + k, z, AIR) }
                    }
                }
            })
        }
        return out
    }
}
