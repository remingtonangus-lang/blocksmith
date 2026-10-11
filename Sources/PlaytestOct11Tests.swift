import Foundation
import simd

// Checks for the Oct 11 Quest playtest items (docs/roadmap/backlog.md P1-P38). The Mac runs them in --questbugs, the
// Quest host check in questcheck (--p11-only stops after them).
enum PlaytestOct11Tests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        iceInWater(game, check)
        dripstone(game, check)
        farCaveFaces(game, check)
        coordsAndHunger(game, check)
        droppedStacks(game, check)
        signText(check)
        craftTiles(game, check)
    }

    // A test basin in the air beside the player: a stone floor and rim round `size` x `size` water cells, one section.
    static func basin(_ game: Game, dx: Int, size: Int = 7, fill: (Int, Int, Int) -> BlockID) -> (x0: Int, yS: Int, z0: Int, undo: () -> Void) {
        let w = game.world, p0 = game.player.pos
        let x0 = ((Int(floorf(p0.x)) + dx) & ~15) + 4, z0 = ((Int(floorf(p0.z)) + 40) & ~15) + 4
        _ = w.loadSync(center: V3(Float(x0), p0.y, Float(z0)), radius: 2)
        let yS = min(CH - 40, ((w.topY(x0, z0) + 24) & ~15) + 10)
        var placed: [IVec3] = []
        for dz in -1...size { for dx in -1...size {
            let inside = dx >= 0 && dx < size && dz >= 0 && dz < size
            w.setBlock(x0 + dx, yS - 4, z0 + dz, STONE); placed.append(IVec3(x0 + dx, yS - 4, z0 + dz))
            for y in (yS - 3)...yS {
                w.setBlock(x0 + dx, y, z0 + dz, inside ? fill(dx, y - yS, dz) : STONE); placed.append(IVec3(x0 + dx, y, z0 + dz))
            }
        } }
        return (x0, yS, z0, { for q in placed.reversed() { w.setBlock(q.x, q.y, q.z, AIR) } })
    }

    // Quad centres (1/16 block, section-local y) of one section's mesh, with the tint (3 = water).
    static func quads(_ game: Game, x: Int, y: Int, z: Int) -> [(c: V3, tint: UInt32)]? {
        let w = game.world
        guard let c = w.chunkAt(x, z), let nb = w.neighbourhood(c) else { return nil }
        let m = Mesher.buildSection(nb.0, nb.1, sy: y >> 4)
        var out: [(c: V3, tint: UInt32)] = []
        for arr in [m.opaque, m.trans] {
            var i = 0
            while i + 7 < arr.count {
                var s = V3(0, 0, 0)
                for k in 0..<4 {
                    let w0 = arr[i + k * 2]
                    s += V3(Float(w0 & 511), Float((w0 >> 9) & 511), Float((w0 >> 18) & 511))
                }
                out.append((s / 4, (arr[i] >> 30) & 3))
                i += 8
            }
        }
        return out
    }

    // P1: ice floating in water shows no water faces against it (the flowing sides showed through the clear ice).
    static func iceInWater(_ game: Game, _ check: (Bool, String) -> Void) {
        let ice = Blocks.id("ice")
        let b = basin(game, dx: 300) { dx, dy, dz in dx == 3 && dz == 3 && dy >= -1 ? ice : WATER }
        defer { b.undo() }
        let ix = b.x0 + 3, iz = b.z0 + 3
        guard let q = quads(game, x: ix, y: b.yS, z: iz) else { check(false, "P1 ice in water: mesh setup"); return }
        // The ice cells' faces in section-local 1/16 units.
        let lx = Float((ix & 15) * 16), lz = Float((iz & 15) * 16), ly0 = Float(((b.yS - 1) & 15) * 16), ly1 = Float(((b.yS & 15) + 1) * 16)
        func onIce(_ c: V3) -> Bool {
            let inX = c.x > lx && c.x < lx + 16, inZ = c.z > lz && c.z < lz + 16, inY = c.y > ly0 && c.y < ly1
            return ((c.x == lx || c.x == lx + 16) && inY && inZ) || ((c.z == lz || c.z == lz + 16) && inY && inX) || (c.y == ly0 && inX && inZ)
        }
        let waterOnIce = q.filter { $0.tint == 3 && onIce($0.c) }.count
        let waterAll = q.filter { $0.tint == 3 }.count
        check(waterOnIce == 0 && waterAll > 20, "P1 ice in water: \(waterOnIce) water faces against the ice (of \(waterAll) water faces)")
    }

    // P3: pointed driprock growing up from a floor points up; one hanging from a ceiling points down (the texture's
    // wide end, v 0, at the block it grows from).
    static func dripstone(_ game: Game, _ check: (Bool, String) -> Void) {
        let w = game.world, drip = Blocks.id("pointed_dripstone"), p0 = game.player.pos
        let x = ((Int(floorf(p0.x)) + 340) & ~15) + 6, z = ((Int(floorf(p0.z)) + 40) & ~15) + 6
        _ = w.loadSync(center: V3(Float(x), p0.y, Float(z)), radius: 2)
        let y = min(CH - 40, ((w.topY(x, z) + 24) & ~15) + 4)     // floor y, ceiling y + 5, both in one section
        let cells = [(y, STONE), (y + 1, drip), (y + 2, drip), (y + 4, drip), (y + 5, STONE)]
        for (cy, b) in cells { w.setBlock(x, cy, z, b) }
        defer { for (cy, _) in cells { w.setBlock(x, cy, z, AIR) } }
        guard let c = w.chunkAt(x, z), let nb = w.neighbourhood(c) else { check(false, "P3 driprock: mesh setup"); return }
        let m = Mesher.buildSection(nb.0, nb.1, sy: y >> 4)
        let layer = UInt32(Blocks.tex[Int(drip) * 6 + 2])
        // The v at each drip cell's top corners.
        var topV: [Int: Set<UInt32>] = [:]
        for arr in [m.opaque, m.trans] {
            for q in stride(from: 0, to: arr.count - 7, by: 8) where (arr[q + 1] >> 10) & 1023 == layer {
                let ys = (0..<4).map { Int((arr[q + $0 * 2] >> 9) & 511) }
                let top = ys.max()!, cell = ys.min()! / 16
                for k in 0..<4 where ys[k] == top { topV[cell, default: []].insert((arr[q + k * 2 + 1] >> 5) & 31) }
            }
        }
        let ly = y & 15
        let up1 = topV[ly + 1] ?? [], up2 = topV[ly + 2] ?? [], hang = topV[ly + 4] ?? []
        check(up1 == [16] && up2 == [16] && hang == [0],
              "P3 driprock: floor ones point up (top v \(up1.sorted()), \(up2.sorted())), the hanging one points down (top v \(hang.sorted()))")
    }

    // P4: far (lod 1) sections drop unlit cave walls (Mesher.farDarkCull), so from a cave the surface's trees showed
    // through far cave ceilings. A dark eye's fog now closes (and sections are culled) before the far ring.
    static func farCaveFaces(_ game: Game, _ check: (Bool, String) -> Void) {
        let ring = Float(World.lodNear * 16)
        let dark = World.caveSight(caveK: 0.02), dusk = World.caveSight(caveK: 0.05), lit = World.caveSight(caveK: 0.6)
        check(dark != nil && dark! < ring && dusk != nil && lit == nil,
              "P4 cave sight: a dark cave's fog ends at \(dark.map { Int($0) } ?? -1) blocks, inside the far ring at \(Int(ring)); none in daylight")
    }

    // P11: the minimap line shows the height too. P12/P38: hunger comes mainly from sprinting, fighting and jumping.
    static func coordsAndHunger(_ game: Game, _ check: (Bool, String) -> Void) {
        let line = Minimap.coordsLine(game)
        let y = Int(floor(game.player.pos.y - Float(YOFF + game.dim.dim.yShift)))
        check(line.contains("Y \(y)") && line.hasPrefix("X ") && line.contains("Z "), "P11 coordinates: \"\(line)\" shows the height")
        // A sprint of 1,000 blocks on the ground, with a jump every 10 blocks.
        let points = (1000 * HungerRates.sprint + 100 * HungerRates.sprintJump) / 4
        check(points <= 13 && HungerRates.sprint < 0.1 && HungerRates.heal < 6,
              String(format: "P12 hunger: 1,000 blocks of sprinting with 100 jumps costs %.1f food points (the reference's 30), walking costs none", points))
    }

    // P5: a dropped stack draws as a pile (more copies for bigger stacks, spread far enough apart to read).
    static func droppedStacks(_ game: Game, _ check: (Bool, String) -> Void) {
        let n = [1, 2, 16, 17, 33, 64].map { ItemEntityManager.copies($0) }
        let mgr = game.drops
        let saved = mgr.items
        defer { mgr.items = saved }
        mgr.items.removeAll()
        let at = game.player.pos + V3(2, 1, 0)
        mgr.spawn(ItemStack(Items.id("cobblestone"), 64), at: at, vel: V3(0, 0, 0))
        mgr.spawn(ItemStack(Items.id("bread"), 20), at: at + V3(0, 0, 2), vel: V3(0, 0, 0))
        var buf = [EntityVert](repeating: EntityVert(pos: V4(0, 0, 0, 0), uv: V4(0, 0, 0, 0), color: V4(0, 0, 0, 0)), count: 4096)
        var spreadCube: Float = 0, quads = 0
        buf.withUnsafeMutableBufferPointer { bp in
            var wr = EntityWriter(out: bp.baseAddress!, capacity: bp.count)
            mgr.write(&wr, eye: game.player.eye, right: V3(1, 0, 0), up: V3(0, -1, 0), world: game.world, daylight: 1, time: 0)
            quads = wr.n / 6
            // The cobblestone pile's vertices: how far apart its copies sit (x/z extent past one 0.25 cube).
            let pts = (0..<min(wr.n, 5 * 36)).map { bp[$0].pos }
            let xs = pts.map { $0.x }, zs = pts.map { $0.z }
            spreadCube = max((xs.max() ?? 0) - (xs.min() ?? 0), (zs.max() ?? 0) - (zs.min() ?? 0))
        }
        check(n == [1, 2, 2, 3, 4, 5] && spreadCube > 0.45 && quads >= 5 * 6 + 3,
              String(format: "P5 dropped stacks: copies %@ for 1/2/16/17/33/64; a 64 stack of blocks spans %.2f blocks (one is 0.35); %d quads drawn",
                     n.map(String.init).joined(separator: "/"), spreadCube, quads))
    }

    // P6: sign text stays on the board. Generated signs (town buildings, notices, posters) set lines with no width
    // limit, so every line shrinks to fit its board when drawn.
    static func signText(_ check: (Bool, String) -> Void) {
        var worst: Float = 0, worstLine = ""
        let samples = ["Welcome to", "Savings and Exchange", "Dead or Alive", "No guns drawn", "General Store and Trading Post",
                       String(repeating: "W", count: 30), "Blacksmith", "MMMMMMMMMMMMMMM"]
        for line in samples {
            for hanging in [false, true] {
                let wpx = Float(Font.width(line))
                // Drawn width in blocks over the board's width (1 block standing, 14/16 hanging).
                let blocks = wpx * Game.signLineFit(wpx, hanging: hanging) / (hanging ? 115 : 90)
                let r = blocks / (hanging ? 0.875 : 1)
                if r > worst { worst = r; worstLine = line }
            }
        }
        check(worst <= 0.95, String(format: "P6 sign text: the widest line (\"%@\") fills %.0f%% of its board", worstLine, worst * 100))
    }

    // P10: the crafting book's recipe tiles are big enough for a controller or VR pointer (were 20 px in 8 x 5), with
    // gaps between them, clear of the detail panel and the page buttons.
    static func craftTiles(_ game: Game, _ check: (Bool, String) -> Void) {
        let cb = CraftingBookMenu(game: game)
        let tiles = cb.slots.filter { if case .button(let id) = $0.kind { return id >= CraftingBookMenu.tileBase && id < CraftingBookMenu.tileBase + CraftingBookMenu.perPage } else { return false } }
        let minSide = tiles.map { min($0.w, $0.h) }.min() ?? 0
        var overlap = false
        for a in tiles { for b in tiles where a !== b {
            if a.x < b.x + b.w + 1 && b.x < a.x + a.w + 1 && a.y < b.y + b.h + 1 && b.y < a.y + a.h + 1 { overlap = true }
        } }
        let right = tiles.map { $0.x + $0.w }.max() ?? 999, bottom = tiles.map { $0.y + $0.h }.max() ?? 999
        check(tiles.count == CraftingBookMenu.perPage && tiles.count <= 25 && minSide >= 30 && !overlap && right < 192 && bottom < 164,
              "P10 crafting tiles: \(tiles.count) tiles of \(minSide) px (were 40 of 20), gaps between them, clear of the panel (right \(right), bottom \(bottom))")
    }
}
