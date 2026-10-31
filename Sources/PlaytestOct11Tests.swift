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
        footsteps(check)
        lavaAtBorder(game, check)
        noMurkDepths(game, check)
        unstuckNearby(game, check)
        heldUseRepeat(game, check)
        horses(game, check)
        dayClears(game, check)
        armourVsGuns(game, check)
        vrGunAim(game, check)
        consoleRadar(game, check)
        sheriffGuardsGun(game, check)
        grassPatches(check)
        difficultyLevels(game, check)
        capitalAmmo(check)
        rarity(check)
        nightManners(game, check)
        mobVariety(game, check)
        noOverlap(game, check)
        shotsDrawFolk(game, check)
        tonics(check)
        townSpacing(game, check)
        vrReload(game, check)
        caveLava(check)
        reckoning(game, check)
        garrisonRow(game, check)
        roadsAndRiders(game, check)
        horseItems(game, check)
        vehicleWorks(game, check)
        vrScope(check)
        G20Tests.run(check)
        G20Tests.glint(game, check)
        G20Tests.powderwightAndEmerald(game, check)
        G20Tests.townsMelee(game, check)
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

        // P28: a tile says how many you can make (48 planks: 6 chests).
        let inv = game.inventory.main.slots
        defer { game.inventory.main.slots = inv }
        for i in 0..<game.inventory.main.count { game.inventory.main[i] = .empty }
        game.inventory.main[0] = ItemStack(Items.id("oak_planks"), 48)
        let book = CraftingBookMenu(game: game)
        book.query = "chest"; book.refresh()
        let L = HudLayout(1280, 800).fitted(book)
        let texts = book.drawLines(L, book.origin(L)).map { $0.text }
        // (P213: the count sits top left as "x6", clear of the item's own stack number.)
        check(texts.contains("x6"),
              "P28 crafting counts: with 48 planks the chest tile reads x6 (\(texts.filter { $0.hasPrefix("x") && Int($0.dropFirst()) != nil }.prefix(8).joined(separator: " ")))")
    }

    // A step's character: the share of its energy below 250 Hz (mud is mostly low thud), above 2 kHz (dry grit and
    // click), and its decay (s to 3% of the peak; squelches ring on).
    static func stepShape(_ x: [Float]) -> (low: Float, high: Float, decay: Float) {
        let sr = Float(SoundBank.rate)
        let aL = 1 - expf(-2 * .pi * 250 / sr), aH = 1 - expf(-2 * .pi * 2000 / sr)
        var lp: Float = 0, lp2: Float = 0, eLow: Float = 0, eHigh: Float = 0, eAll: Float = 1e-12
        for v in x {
            lp += (v - lp) * aL; lp2 += (v - lp2) * aH
            eLow += lp * lp; eHigh += (v - lp2) * (v - lp2); eAll += v * v
        }
        let pk = x.map { abs($0) }.max() ?? 0
        let last = x.lastIndex { abs($0) > pk * 0.03 } ?? 0
        let first = x.firstIndex { abs($0) >= pk * 0.99 } ?? 0
        return (eLow / eAll, eHigh / eAll, Float(last - first) / sr)
    }

    // P14: footsteps on ordinary ground must not sound like walking through mud (Oct 11 playtest 09:13, again after the
    // Oct 10 audit's relative check passed): each dry step is far from the mud step on low thud and ring.
    static func footsteps(_ check: (Bool, String) -> Void) {
        let mud = stepShape(SoundBank.render(.step(.mud), variant: 0))
        var worst = "", ok = true, lines: [String] = []
        for m: SoundMat in [.dirt, .grass, .stone, .sand, .gravel, .wood, .deepslate, .snow] {
            var low: Float = 0, high: Float = 0, decay: Float = 0
            for v in 0..<3 {
                let sh = stepShape(SoundBank.render(.step(m), variant: v))
                low += sh.low / 3; high += sh.high / 3; decay = max(decay, sh.decay)
            }
            lines.append(String(format: "%@ low %.2f high %.2f %.0f ms", "\(m)", low, high, decay * 1000))
            // P457: the steps are Remington's approved recordings now (grass and dirt carry the boot's own thud, so the
            // synthesized steps' 30% low-thud bound is gone); each still has grit mud has none of and stops short.
            if high < 0.12 || high < mud.high * 4 || decay > 0.16 { ok = false; worst += (worst.isEmpty ? "" : ", ") + "\(m)" }
        }
        print("p14 steps: mud low \(String(format: "%.2f", mud.low)) high \(String(format: "%.2f", mud.high)) \(Int(mud.decay * 1000)) ms; " + lines.joined(separator: "; "))
        check(ok, "P14 footsteps: dry steps are crisp, not muddy (grit >= 12% and 4x mud's, ring <= 160 ms\(worst.isEmpty ? "" : "; \(worst) fail"))")
    }

    // P18: lava at a chunk's edge beside air in the next chunk flows when the chunks meet (World.borderSprings; the
    // per-chunk spring scan never saw across the border, so such lava stood still for good).
    static func lavaAtBorder(_ game: Game, _ check: (Bool, String) -> Void) {
        let w = game.world, p0 = game.player.pos
        let cx = (Int(floorf(p0.x)) + 380) >> 4, cz = (Int(floorf(p0.z)) + 40) >> 4
        _ = w.loadSync(center: V3(Float(cx * 16 + 16), p0.y, Float(cz * 16 + 8)), radius: 2)
        guard let c = w.chunks[ChunkKey(x: cx, z: cz)], let n = w.chunks[ChunkKey(x: cx + 1, z: cz)] else { check(false, "P18 lava at a border: chunks"); return }
        // Underground (the border check runs up to the taller column + 2): lava on c's east edge, an air pocket on n's
        // west edge beside it, both written raw (no fluid update), the originals put back after.
        let lz = 8, y = max(6, min(Int(c.height[15 + lz * CS]), Int(n.height[lz * CS])) - 12)
        let ia = Chunk.index(15, y, lz), ib = Chunk.index(0, y, lz)
        // Everything the lava could reach in 6 ticks, put back raw afterwards.
        var keep: [(Int, Int, Int, BlockID)] = []
        for dz in -6...6 { for dy in -6...1 { for dx in -5...7 {
            let x = cx * 16 + 15 + dx, z = cz * 16 + lz + dz
            keep.append((x, y + dy, z, w.block(x, y + dy, z)))
        } } }
        defer { for (x, yy, z, id) in keep { w.chunkAt(x, z)?.blocks[Chunk.index(x & 15, yy, z & 15)] = id } }
        // A closed stone cell round the two blocks (a cave or an aquifer beside them let the lava fall away or harden).
        for dz in -1...1 { for dy in -1...1 { for dx in -1...2 where !(dz == 0 && dy == 0 && (dx == 0 || dx == 1)) {
            let x = cx * 16 + 15 + dx, z = cz * 16 + lz + dz
            w.chunkAt(x, z)?.blocks[Chunk.index(x & 15, y + dy, z & 15)] = STONE
        } } }
        c.blocks[ia] = LAVA; n.blocks[ib] = AIR
        // (P376: fluid past the active distance is parked; 380 blocks off, the cell is centred on by hand.)
        let active0 = w.activeCenter
        w.activeCenter = V3(Float(cx * 16 + 16), Float(y), Float(cz * 16 + lz))
        defer { w.activeCenter = active0 }
        let before = w.lavaPending.count
        w.borderSprings(n)
        let queued = w.lavaPending.count > before
        for _ in 0..<6 { w.fluidTick(lava: true) }
        let spilled = Blocks.fluidKind[Int(w.builtBlock(cx * 16 + 16, y, cz * 16 + lz))] == 2
        check(queued && spilled, "P18 lava at a chunk border: queued when the chunks meet (\(queued)), spilled into the next chunk (\(spilled))")
    }

    // P19: no copy of the reference's deep dark: under low-erosion country (where the murk depths were) the generator
    // lays no murk, no Buried Citadel is placed, and the cave biome is never the murk depths.
    static func noMurkDepths(_ game: Game, _ check: (Bool, String) -> Void) {
        guard let wg = game.world.gen as? WorldGen else { check(false, "P19 no murk depths: generator"); return }
        let murk = Set(["sculk", "sculk_vein", "sculk_sensor", "sculk_shrieker", "sculk_catalyst"].filter { Blocks.has($0) }.map { Blocks.id($0) })
        var spot: (Int, Int)?
        search: for r in stride(from: 0, through: 6000, by: 96) { for a in 0..<16 {
            let x = Int(cosf(Float(a) * .pi / 8) * Float(r)), z = Int(sinf(Float(a) * .pi / 8) * Float(r))
            if wg.climate(x, z).e < -0.7 { spot = (x, z); break search }
        } }
        guard let (x, z) = spot else { check(false, "P19 no murk depths: no low-erosion country within 6,000 blocks to test"); return }
        var found = 0
        for dz in -1...1 { for dx in -1...1 {
            let b = wg.generate(cx: (x >> 4) + dx, cz: (z >> 4) + dz)
            found += b.reduce(0) { $0 + (murk.contains($1) ? 1 : 0) }
        } }
        let citadel = BigStructures.types(wg).contains { $0.name == "ancient_city" }
        check(found == 0 && !citadel && !GameBlocks.stalkerCalls,
              "P19 no murk depths: \(found) murk blocks in 9 chunks of low-erosion country at \(x), \(z); Buried Citadel \(citadel ? "still placed" : "gone"); shriekers call no stalker")
    }

    // P20: a player embedded in rock with a cave beside them steps into the cave, not up through the rock above.
    static func unstuckNearby(_ game: Game, _ check: (Bool, String) -> Void) {
        let w = game.world, p0 = game.player.pos
        let x0 = ((Int(floorf(p0.x)) + 420) & ~15) + 8, z0 = ((Int(floorf(p0.z)) + 40) & ~15) + 8
        _ = w.loadSync(center: V3(Float(x0), p0.y, Float(z0)), radius: 2)
        let y0 = min(CH - 40, w.topY(x0, z0) + 20)
        var placed: [IVec3] = []
        for dy in -2...12 { for dz in -3...3 { for dx in -3...3 {
            w.setBlock(x0 + dx, y0 + dy, z0 + dz, STONE); placed.append(IVec3(x0 + dx, y0 + dy, z0 + dz))
        } } }
        defer { for q in placed { w.setBlock(q.x, q.y, q.z, AIR) } }
        // A two-high pocket one block east; the player inside the rock beside it.
        w.setBlock(x0 + 1, y0, z0, AIR); w.setBlock(x0 + 1, y0 + 1, z0, AIR)
        let pl = Player()
        pl.pos = V3(Float(x0) + 0.5, Float(y0), Float(z0) + 0.5)
        pl.update(dt: 1.0 / 60, input: MoveInput(), world: w)
        let moved = pl.pos - V3(Float(x0) + 0.5, Float(y0), Float(z0) + 0.5)
        check(simd_length(moved) < 1.6 && !pl.collides(at: pl.pos, w),
              String(format: "P20 unstuck: embedded beside a cave, the player moves %.1f blocks into it (up %.1f), not up through the rock", simd_length(moved), moved.y))
    }

    // P25: holding use (a trigger resting or stuck down) and stepping the hotbar onto a block doesn't place it; a fresh
    // press places, and a hold that began with the block keeps placing it.
    static func heldUseRepeat(_ game: Game, _ check: (Bool, String) -> Void) {
        let w = game.world, p0 = game.player.pos
        let x0 = ((Int(floorf(p0.x)) - 300) & ~15) + 8, z0 = ((Int(floorf(p0.z)) + 40) & ~15) + 8
        _ = w.loadSync(center: V3(Float(x0), p0.y, Float(z0)), radius: 2)
        let y0 = min(CH - 30, w.topY(x0, z0) + 12)
        var placed: [IVec3] = []
        for dz in -4...4 { for dx in -4...4 { w.setBlock(x0 + dx, y0, z0 + dz, STONE); placed.append(IVec3(x0 + dx, y0, z0 + dz)) } }
        let was = (game.survival, game.paused, game.selected, game.player.pos, game.player.yaw, game.player.pitch, game.player.flying)
        let inv = game.inventory.main.slots
        defer {
            for dy in 0...8 { for dz in -4...4 { for dx in -4...4 { w.setBlock(x0 + dx, y0 + dy, z0 + dz, AIR) } } }
            game.inventory.main.slots = inv
            game.survival = was.0; game.paused = was.1; game.selected = was.2
            game.player.pos = was.3; game.player.yaw = was.4; game.player.pitch = was.5; game.player.flying = was.6
            PadManager.shared.simulated = nil
        }
        _ = placed
        // Planks, not his crafting table: a placed table becomes the target and a held press opens it instead of repeating.
        let table = Items.id("oak_planks")
        game.survival = true; game.paused = false; game.menu = nil
        game.inventory.main[0] = .empty
        game.inventory.main[1] = ItemStack(table, 16)
        game.selected = 0
        game.player.flying = false
        game.player.pos = V3(Float(x0) + 0.5, Float(y0 + 1), Float(z0) + 0.5); game.player.vel = .zero
        // A stone wall three blocks ahead (-z): each placement lands on the face toward the player, one closer each time.
        for dy in 1...3 { for dx in -1...1 { w.setBlock(x0 + dx, y0 + dy, z0 - 3, STONE) } }
        game.player.yaw = 0; game.player.pitch = -0.25
        // Each placement is taken away again at once, so every repeat aims at the same clear wall face (a block placed
        // in front of it moved the aim and the next placement onto other faces, or onto none).
        func frames(_ n: Int, lt: Float) {
            for _ in 0..<n {
                var p = PadSnapshot(); p.lt = lt; PadManager.shared.simulated = p; game.tick(1.0 / 60)
                for dy in 1...3 { for dz in -2...0 { for dx in -1...1 where !w.isAir(x0 + dx, y0 + dy, z0 + dz) { w.setBlock(x0 + dx, y0 + dy, z0 + dz, AIR) } } }
            }
        }
        frames(20, lt: 1)                                 // held with an empty hand
        game.select(1)                                    // the hotbar steps onto the tables, trigger still down
        frames(60, lt: 1)
        let afterStep = game.inventory.main[1].count
        frames(5, lt: 0)
        frames(40, lt: 1)                                 // a fresh press, held: places, then repeats
        let afterPress = game.inventory.main[1].count
        check(afterStep == 16 && afterPress <= 14,
              "P25 held use: stepping onto a block with the trigger down places none (\(16 - afterStep) placed); a fresh press held places \(afterStep - afterPress)")
    }

    // P26: a horse's slowest roll outruns a sprint; bond to level 4 takes about 90 minutes of riding; the owner's blow
    // finishes a downed horse; a called horse pulls up beside you.
    static func horses(_ game: Game, _ check: (Bool, String) -> Void) {
        let h = Mob(.horse, at: game.player.pos + V3(30, 0, 0))
        h.variant = h.variant & ~(15 << 4)                     // the slowest speed roll
        let slow = h.horseSpeed
        let ride4 = HorseFeel.levelXP[3] * HorseFeel.ridePerPoint
        h.downed = HorseLife.downTime; h.health = 1
        Mob.playerMelee = true
        h.hit(from: game.player.pos, damage: 6)
        Mob.playerMelee = false
        let finished = h.downed > 0 && h.downed <= 0.01
        check(slow >= 8 && ride4 >= 50_000 && finished,
              String(format: "P26 horses: slowest gallop %.1f b/s (sprint 5.6); level 4 after %.0f blocks of riding (about %.0f min at 10 b/s); a downed horse struck by its owner is put down (%@)",
                     slow, ride4, ride4 / 600, finished ? "yes" : "no"))
    }

    // P27: by day a spider out under the sky behind the player slips away within a minute; at night it stays.
    static func dayClears(_ game: Game, _ check: (Bool, String) -> Void) {
        let w = game.world, was = game.time
        defer { game.time = was }
        let back = -simd_normalize(V3(game.player.look.x, 0, game.player.look.z) + V3(1e-4, 0, 0))
        var at = game.player.pos + back * 20
        _ = w.loadSync(center: at, radius: 1)
        at.y = Float(w.topY(Int(floor(at.x)), Int(floor(at.z))) + 1)
        func clearedAfter(_ frac: Double) -> Float {
            game.time = frac * DAY_LENGTH
            let sp = Mob(.spider, at: at)
            var t: Float = 0
            while t < 60 { if game.mobs.shouldDespawn(sp, simd_length(sp.pos - game.player.pos), 0.05, game) { return t }; t += 0.05 }
            return -1
        }
        let day = clearedAfter(0.25), night = clearedAfter(0.75)
        check(day >= 0 && night < 0, String(format: "P27 day clears the surface: a spider out of sight under the noon sky is gone after %.0f s; at midnight it stays (%@)",
                                              day, night < 0 ? "stays" : "gone"))
    }

    // P30: in full titanium, rifle rounds still hurt (each one landing) and wear the armour hard.
    static func armourVsGuns(_ game: Game, _ check: (Bool, String) -> Void) {
        let was = (game.survival, game.health, game.absorption, game.inventory.armor.slots)
        defer { game.survival = was.0; game.health = was.1; game.absorption = was.2; game.inventory.armor.slots = was.3 }
        game.survival = true; game.health = 20; game.absorption = 0
        for (i, k) in ["diamond_boots", "diamond_leggings", "diamond_chestplate", "diamond_helmet"].enumerated() { game.inventory.armor[i] = ItemStack(Items.id(k), 1) }
        let wear0 = game.inventory.armor.slots.map { $0.damage }.reduce(0, +)
        for _ in 0..<5 { game.bulletHit = true; game.damage(4, "was shot", type: .projectile); game.bulletHit = false }
        let lost = 20 - game.health
        let wear = game.inventory.armor.slots.map { $0.damage }.reduce(0, +) - wear0
        check(lost >= 5 && lost < 20 && wear >= 5,
              "P30 armour vs guns: five 4-damage rounds into full titanium cost \(lost) half-hearts (was 0) and \(wear) armour wear")
    }

    // P32: in VR a round leaves the aiming hand along its ray (it flew from the eye, above the sights).
    static func vrGunAim(_ game: Game, _ check: (Bool, String) -> Void) {
        let gi = Guns.all.firstIndex { $0.key == "gun_rifle" } ?? 0
        let held0 = game.inventory.held
        let two0 = game.vrTwoHanded
        defer { game.inventory.held = held0; game.vrAim = nil; game.vrTwoHanded = two0 }
        var gun = ItemStack(Items.id("gun_rifle"), 1); gun.tag = 10
        game.inventory.held = gun
        let hand = game.player.eye + V3(0.25, -0.45, -0.2), dir = simd_normalize(V3(0.1, 0.05, -1))
        game.vrAim = (hand, dir)
        // Braced on its foregrip with the other hand (P499: one-handed, a shouldered gun throws its rounds wide).
        game.vrTwoHanded = true
        let n0 = game.arms.slugs.count
        game.fireHeldGun(gi)
        guard let s = game.arms.slugs.last, game.arms.slugs.count > n0 else { check(false, "P32 VR gun aim: no round fired"); return }
        let off = simd_length(s.pos - (hand + dir * 0.3)), ang = acosf(min(1, simd_dot(simd_normalize(s.vel), dir))) * 180 / .pi
        check(off < 0.01 && ang < 0.05, String(format: "P32/P43 VR gun aim: braced, the round leaves the hand (%.2f off) exactly along the hand's ray (%.2f degrees off)", off, ang))
        // One-handed: rounds go wide (up to about 7 degrees), never 0 every time.
        game.vrTwoHanded = false
        var wide: Float = 0
        for _ in 0..<8 {
            let n1 = game.arms.slugs.count
            game.fireHeldGun(gi)
            if game.arms.slugs.count > n1, let r = game.arms.slugs.last { wide = max(wide, acosf(min(1, simd_dot(simd_normalize(r.vel), dir))) * 180 / .pi) }
        }
        check(wide > 0.3 && wide < 8, String(format: "P499 VR gun aim: fired one-handed a rifle's rounds go wide (up to %.1f degrees in 8 shots)", wide))
    }

    // P36: a citadel's command console, used, puts the Capital sites and patrols on the radar readout for 30 s.
    static func consoleRadar(_ game: Game, _ check: (Bool, String) -> Void) {
        guard Blocks.has("command_console") else { check(false, "P36 console: no command_console block"); return }
        let p = IVec3(Int(floorf(game.player.pos.x)) + 2, Int(floorf(game.player.pos.y)) + 1, Int(floorf(game.player.pos.z)))
        let was = game.world.block(p.x, p.y, p.z)
        defer { game.world.setBlock(p.x, p.y, p.z, was); game.consoleRadarUntil = -1; Game.radarCache.time = -1 }
        game.world.setBlock(p.x, p.y, p.z, Blocks.id("command_console"))
        let used = game.isInteractive(p) && game.consoleUse(p)
        let lines = game.radarLines(HudLayout(1280, 800)).map { $0.text }
        check(used && lines.contains("Citadel console") && lines.count >= 2,
              "P36 console: using a command console shows the radar readout (\(lines.dropFirst().prefix(4).joined(separator: "; ")))")
    }

    // G15: a sheriff takes many iron-sword blows and, struck, skips the warning shot.
    static func sheriffGuardsGun(_ game: Game, _ check: (Bool, String) -> Void) {
        let base = game.player.pos + V3(3, 0, 0)
        let m = Mob(.villager, at: base); m.home = base
        Townsfolk.setup(m, game: game)
        guard var v = m.villager else { check(false, "G15 sheriff: no townsperson"); return }
        TownLaw.deputize(&v); m.villager = v
        let mobs0 = game.mobs.mobs
        defer { game.mobs.mobs = mobs0 }
        game.mobs.mobs = [m]
        let blows = Int((Float(m.health) / (6 / m.townStats.toughness)).rounded(.up))
        game.townAlarm(m)
        check(blows >= 6 && m.town.warned, "G15 sheriff: an iron sword needs \(blows) blows (was 5) and his first round after you strike him is meant (no warning: \(m.town.warned))")
    }

    // G18: plains grass grows in patches: more cover than the calm v78 ground, clumped (a grass block's neighbours carry
    // grass far more often than the field's average), with a few tall tufts.
    static func grassPatches(_ check: (Bool, String) -> Void) {
        let gen = WorldGen(seed: 12345)
        var tops = 0, short = 0, tall = 0, pairs = 0, both = 0
        let tallID = Blocks.id("tall_grass")
        var found = 0
        outer: for r in stride(from: 0, to: 4000, by: 64) { for (dx, dz) in [(1, 0), (0, 1), (-1, 0), (0, -1)] {
            let wx = dx * r, wz = dz * r
            guard gen.column(wx, wz).biome == .plains else { continue }
            let cx = floorDiv(wx, CS), cz = floorDiv(wz, CS)
            for oz in 0..<2 { for ox in 0..<2 {
                let b = gen.generate(cx: cx + ox, cz: cz + oz)
                var g = [Bool](repeating: false, count: CSQ), top = [Bool](repeating: false, count: CSQ)
                for lz in 0..<CS { for lx in 0..<CS {
                    guard gen.column((cx + ox) * CS + lx, (cz + oz) * CS + lz).biome == .plains else { continue }
                    var y = CH - 2
                    while y > 1 && b[Chunk.index(lx, y, lz)] == AIR { y -= 1 }
                    let at = b[Chunk.index(lx, y, lz)]
                    if at == TALL_GRASS { short += 1; g[lx + lz * CS] = true } else if at == tallID + 1 { tall += 1; g[lx + lz * CS] = true }
                } }
                for lz in 0..<CS { for lx in 0..<CS where gen.column((cx + ox) * CS + lx, (cz + oz) * CS + lz).biome == .plains {
                    var y = CH - 2
                    while y > 1 && !Blocks.opaque[Int(b[Chunk.index(lx, y, lz)])] { y -= 1 }
                    if b[Chunk.index(lx, y, lz)] == GRASS { tops += 1; top[lx + lz * CS] = true }
                } }
                for lz in 0..<CS { for lx in 0..<(CS - 1) where top[lx + lz * CS] && top[lx + 1 + lz * CS] && g[lx + lz * CS] {
                    pairs += 1; if g[lx + 1 + lz * CS] { both += 1 }
                } }
            } }
            found += 1
            if found >= 6 { break outer }
        } }
        let share = Float(short + tall) / Float(max(1, tops)), clump = Float(both) / Float(max(1, pairs))
        check(found >= 3 && share > 0.08 && share < 0.35 && clump > share * 1.5 && tall > 0,
              String(format: "G18 grass patches: %.0f%% of plains grass blocks carry grass (calm v78 ground ~4%%), %.0f%% of a grass block's neighbours do (clumped), %d tall tufts in %d areas", share * 100, clump * 100, tall, found))
    }

    // G19: Easy, Normal and Hard differ in monster toughness, speed and numbers and in hunger, and the pause menu won't
    // change a made world's level.
    static func difficultyLevels(_ game: Game, _ check: (Bool, String) -> Void) {
        let was = (game.difficulty, Difficulty.level, game.menu)
        let paused0 = game.paused
        defer { game.difficulty = was.0; Difficulty.level = was.1; game.paused = paused0 }
        var blows: [Int] = [], caps: [Int] = []
        // (P302: levels 2-4 are Easy, Normal and Hard. P435: on Easy no monster rolls tougher than plain: a tough roll
        // takes more blows from Normal up.)
        for lv in 2...4 {
            Difficulty.level = lv
            let z = Mob(.zombie, at: game.player.pos + V3(0, 0, -40))
            z.vary.tough = 1.5
            var n = 0
            while z.health > 0 && n < 200 { z.health -= Difficulty.scaleHit(6, z); n += 1 }
            blows.append(n)
            caps.append(game.mobs.cap(.monster, game.world))
        }
        let hunger = (2...4).map { Difficulty.rows[$0].hunger }, speed = (2...4).map { Difficulty.rows[$0].speed }
        game.difficulty = 2
        let menu = PauseMenu(game: game)
        game.menu = menu
        menu.act("difficulty", back: false)
        let locked = game.diffLevel == 4          // P369: the row now steps the level (Normal -> Hard), no lock
        game.menu = was.2
        check(blows[0] < blows[1] && blows[1] <= blows[2] && caps[0] < caps[1] && caps[1] < caps[2]
                && hunger[0] < hunger[1] && hunger[1] < hunger[2] && speed[0] < speed[2] && locked,
              "G19 difficulty: a zombie takes \(blows) blows of 6 on easy/normal/hard, monster cap \(caps), hunger x\(hunger), speed x\(speed); the pause menu changes it (\(locked))")
    }

    // P40: the Capital's guns fire capital rounds, which no shop sells; frontier rifle rounds cost real money; a gunsmith
    // outside a Capital city doesn't offer the Capital's guns.
    static func capitalAmmo(_ check: (Bool, String) -> Void) {
        let capGuns = ["gun_rifle", "gun_smg", "gun_sidearm"]
        let usesOwn = capGuns.allSatisfy { k in Guns.all.first { $0.key == k }?.ammo == "capital_rounds" }
        let sold = Economy.stock.values.contains { $0.contains { $0.0 == "capital_rounds" } } && !Economy.capitalOnly.contains("capital_rounds")      // R8: Capital cities sell them
        let price = Economy.value["rifle_rounds"] ?? 0
        let gated = capGuns.allSatisfy { Economy.capitalOnly.contains($0) }
        check(usesOwn && !sold && price >= 25 && gated && Items.has("capital_rounds"),
              "P40 ammo: Capital guns load capital rounds (\(usesOwn)), sold only in Capital cities (\(!sold)); rifle rounds cost \(Money.format(price)) each; Capital guns only in Capital towns (\(gated))")
    }

    // P44: with the real shares, Capital city and citadel regions that keep a site come to about one each per 4,000 x
    // 4,000 blocks (each kept region still needs fit ground, about half of them), over a 40,000-block square.
    static func rarity(_ check: (Bool, String) -> Void) {
        let s32 = UInt32(truncatingIfNeeded: UInt64(12345))
        var cities = 0, citadels = 0
        for rz in -22..<22 { for rx in -22..<22 where hashf(rx, 7351, rz, s32 ^ 0xCA91) < WorldRules.capitalKeepP44 { cities += 1 } }
        for rz in -31..<31 { for rx in -31..<31 where hashf(rx, 7361, rz, s32 ^ 0xC17A) < WorldRules.citadelKeepP44 { citadels += 1 } }
        // 44 x 44 regions of 896 blocks and 62 x 62 of 640: both about 39,700 blocks square, 98 squares of 4,000.
        let perCity = Float(cities) / 2 / 98, perCitadel = Float(citadels) / 2 / 98
        check(perCity > 0.5 && perCity < 1.6 && perCitadel > 0.5 && perCitadel < 1.6,
              String(format: "P44 rarity: about %.1f Capital cities and %.1f citadels per 4,000 x 4,000 blocks (%d and %d kept regions)", perCity, perCitadel, cities, citadels))
    }

    // P58: past dusk nobody says the evening lines (closing up, off to bed); every such line is a real take, and the chef
    // falls back to the closed lines. P59: sleeping in a town bed that isn't yours costs honour once a night; your own
    // placed bed costs nothing.
    static func nightManners(_ game: Game, _ check: (Bool, String) -> Void) {
        let texts = Set(TownVoice.takes.map { $0.text })
        let real = TownVoice.eveningOnly.allSatisfy { texts.contains($0) }
        let chefLate = (TownVoice.index["chef_m"]?[.night] ?? []).filter { !TownVoice.eveningOnly.contains(TownVoice.takes[$0].text) }
        let windows = !TownVoice.isLate(0.55) && TownVoice.isLate(0.75) && !TownVoice.isLate(0.1)
        let g = game, savedTime = g.time, savedSurv = g.survival, h0 = Honour.value
        defer { g.time = savedTime; g.survival = savedSurv; TownLaw.forceTown = nil; TownLaw.reset(); Honour.value = h0 }
        TownLaw.reset(); TownLaw.forceTown = true; g.survival = true; g.time = 3.7 * DAY_LENGTH
        let bed = IVec3(Int(floorf(g.player.pos.x)) + 3, Int(floorf(g.player.pos.y)), Int(floorf(g.player.pos.z)))
        let a = Honour.value
        TownLaw.sleptIn(g, bed)
        let b = Honour.value
        TownLaw.sleptIn(g, bed)                                  // the same night again: no second charge
        let c = Honour.value
        let mine = bed + IVec3(0, 0, 5)
        TownLaw.placed(g, mine)
        TownLaw.sleptIn(g, mine + IVec3(1, 0, 0))                 // the head half of a bed you placed
        let d = Honour.value
        // (P468's second book gave the chef night lines of his own; with none he falls back to the closed lines.)
        check(real && windows && b < a && c == b && d == c,
              "P58/P59 night manners: evening-only lines are real takes (\(real)), the chef has \(chefLate.count) lines late, late window ok (\(windows)); a town bed costs \(b - a) honour once a night (again: \(c - b)), your own bed \(d - c)")
    }

    // P55: monsters vary one from the next (speed, hit, toughness, archers' aim); animals and townsfolk don't.
    static func mobVariety(_ game: Game, _ check: (Bool, String) -> Void) {
        let was = MobVary.on
        MobVary.on = true
        defer { MobVary.on = was }
        let zs = (0..<60).map { _ in Mob(.zombie, at: game.player.pos) }
        let sp = zs.map { $0.vary.speed }, dm = zs.map { $0.vary.damage }, tg = zs.map { $0.vary.tough }
        let sk = (0..<60).map { _ in Mob(.skeleton, at: game.player.pos).vary.aim }
        let cow = Mob(.cow, at: game.player.pos).vary
        func range(_ a: [Float]) -> Float { (a.max() ?? 0) - (a.min() ?? 0) }
        let hits = zs.map { $0.vary.hit(4) }
        // (R-batch, Oct 14: animals vary a little too, never into a monster's builds.)
        let cowMild = cow.build == .middling && cow.aim == 0 && cow.speed >= 0.75 && cow.speed <= 1.35 && cow.tough >= 0.8 && cow.tough <= 1.3
        check(range(sp) > 0.3 && range(dm) > 0.5 && range(tg) > 0.4 && range(sk) > 0.08 && cowMild
              && Set(hits).count >= 3,
              String(format: "P55 mob variety: zombie speed x%.2f-%.2f, hit x%.2f-%.2f (a 4 lands as %@), toughness x%.2f-%.2f; skeleton aim spread %.2f-%.2f; a cow varies only a little (speed x%.2f, toughness x%.2f)",
                     sp.min()!, sp.max()!, dm.min()!, dm.max()!, Set(hits).sorted().map(String.init).joined(separator: "/"), tg.min()!, tg.max()!, sk.min()!, sk.max()!, cow.speed, cow.tough))
    }

    // P60: two zombies standing in each other, and a voidwalker standing in the player, are eased apart within a second.
    static func noOverlap(_ game: Game, _ check: (Bool, String) -> Void) {
        let saved = game.mobs.mobs, alive0 = game.alive, riding0 = game.riding, pos0 = game.player.pos
        defer { game.mobs.mobs = saved; game.alive = alive0; game.riding = riding0; game.player.pos = pos0 }
        game.alive = true; game.riding = nil                     // (the player shoves only while alive and on foot)
        // In the air, player included (an earlier check can leave the player in a pocket a voidwalker can't be eased
        // out into): nothing to push them into.
        var p = pos0
        p.y = Float(game.world.topY(Int(floor(p.x)), Int(floor(p.z))) + 24)
        game.player.pos = p
        let at = V3(p.x + 4, p.y, p.z)
        let a = Mob(.zombie, at: at), b = Mob(.zombie, at: at + V3(0.05, 0, 0)), e = Mob(.enderman, at: p + V3(0.1, 0, 0))
        game.mobs.mobs = [a, b, e]
        for _ in 0..<30 { game.mobs.separate(1.0 / 30, game) }
        let ab = simd_length(V2(a.pos.x - b.pos.x, a.pos.z - b.pos.z)), ep = simd_length(V2(e.pos.x - p.x, e.pos.z - p.z))
        check(ab >= a.halfW + b.halfW - 0.02 && ep >= e.halfW + game.player.halfW - 0.02,
              String(format: "P60 no overlap: two zombies %.2f apart (need %.2f), a voidwalker %.2f from the player (need %.2f)", ab, a.halfW + b.halfW, ep, e.halfW + game.player.halfW))
    }

    // P63: a shot in town sends the sheriff and the four nearest grown townsfolk to look, and they walk that way.
    static func shotsDrawFolk(_ game: Game, _ check: (Bool, String) -> Void) {
        let mobs0 = game.mobs.mobs
        defer { game.mobs.mobs = mobs0; TownLaw.forceTown = nil }
        TownLaw.forceTown = true
        let p = game.player.pos
        var folk: [Mob] = []
        for i in 0..<7 {
            let at = p + V3(Float(6 + i * 3), 0, 0)
            let m = Mob(.villager, at: at); m.home = at
            Townsfolk.setup(m, game: game)
            if i == 6, var v = m.villager { TownLaw.deputize(&v); m.villager = v }
            folk.append(m)
        }
        game.mobs.mobs = folk
        TownLaw.gunfire(game, at: p)
        let going = folk.filter { $0.town.investigate != nil }
        let sheriff = folk[6].town.investigate != nil, nearest = folk.prefix(4).allSatisfy { $0.town.investigate != nil }
        let d0 = simd_length(folk[0].pos - p)
        _ = folk[0].villagerDay(0.05, game)
        let heads = simd_dot(folk[0].forward, simd_normalize(p - folk[0].pos)) > 0.5 || simd_length(folk[0].pos - p) < 4
        check(going.count == 5 && sheriff && nearest && heads,
              "P63 gunfire: \(going.count) townsfolk come to look (the sheriff: \(sheriff), the four nearest: \(nearest)); the nearest, \(Int(d0)) blocks off, turns toward the shot (\(heads))")
    }

    // P42: our own tonic names (no "Potion of"), and the doctor's rarer stock turns up in only some shops.
    static func tonics(_ check: (Bool, String) -> Void) {
        let names = Potions.types.indices.compactMap { i -> String? in
            let t = Potions.types[i]
            return t.effects.isEmpty ? nil : Potions.displayName(0, t)
        }
        let original = !names.contains { $0.contains("Potion of") }
        let regen = (0..<400).filter { Economy.carries("potion_regeneration", keeper: $0 * 7919) }.count
        let heal = (0..<400).allSatisfy { Economy.carries("potion_healing", keeper: $0 * 7919) }
        check(original && heal && regen > 100 && regen < 180,
              "P42 tonics: \(names.prefix(4).joined(separator: ", ")), ...; Second Wind in \(regen) of 400 doctors' shops, Mending in all (\(heal))")
    }

    // P62: wide towns (new ground) space their buildings out: fewer lots along the same streets, and nearly every site
    // that makes a town still does.
    static func townSpacing(_ game: Game, _ check: (Bool, String) -> Void) {
        guard let gen = game.world.gen as? WorldGen else { return }
        var n = [0, 0], lots = [0, 0]
        var cur = 0
        Village.planLog = { _, _, _, _, k in lots[cur] += k }
        defer { Village.planLog = nil }
        for i in 0..<80 {
            let ox = (i % 20) * 544 + 8 - 5000, oz = (i / 20) * 544 + 8 - 5000
            let cy = gen.groundY(ox, oz)
            guard cy >= SEA else { continue }
            for w in 0..<2 {
                cur = w
                if Village.layout(gen, seed: UInt64(i) &* 0x9E3779B97F4A7C15, ox: ox, oz: oz, cy: cy, style: .plains, frontier: true,
                                  townsGap: true, wide: w == 1) != nil { n[w] += 1 }
            }
        }
        let per = (0..<2).map { n[$0] > 0 ? Float(lots[$0]) / Float(n[$0]) : 0 }
        check(n[0] > 5 && Float(n[1]) >= Float(n[0]) * 0.7 && per[1] < per[0] * 0.9,
              String(format: "P62 town spacing: %d of %d sites still make a town; %.1f lots a town, was %.1f (more room between buildings)", n[1], n[0], per[1], per[0]))
    }

    // P56: VR manual reload: the off hand at the hip takes a magazine, the gun hand's grip takes it in and the gun is full.
    static func vrReload(_ game: Game, _ check: (Bool, String) -> Void) {
        let held0 = game.inventory.held, inv = game.inventory.main.slots, surv = game.survival, yaw0 = game.player.yaw
        defer { game.inventory.main.slots = inv; game.inventory.held = held0; game.survival = surv; game.arms.magInHand = false; game.player.yaw = yaw0 }
        game.survival = true
        game.player.yaw = 0
        var gun = ItemStack(Items.id("gun_rifle"), 1); gun.tag = 0
        game.inventory.held = gun
        let slot = (0..<36).first { $0 != game.selected && game.inventory.main[$0].isEmpty } ?? 20
        game.inventory.main[slot] = ItemStack(Items.id("capital_rounds"), 64)
        let head = game.player.eye, gunHand = head + V3(0.2, -0.35, -0.35)
        let hip = head + V3(-0.25, -0.8, 0.05), mid = head + V3(0.1, -0.1, -0.5)
        let away = VRReload.tick(game, offHand: mid, gunHand: gunHand, head: head, grip: true, gripWas: false)
        let grab = VRReload.tick(game, offHand: hip, gunHand: gunHand, head: head, grip: true, gripWas: false)
        // Carried up on the far side (mid-chest is inside P286's wider 0.38 m well reach: it seated there already).
        let carry = head + V3(-0.35, -0.2, -0.3)
        let held = VRReload.tick(game, offHand: carry, gunHand: gunHand, head: head, grip: true, gripWas: true)
        let ins = VRReload.tick(game, offHand: gunHand + V3(0, -0.08, 0.02), gunHand: gunHand, head: head, grip: true, gripWas: true)
        let full = game.held.tag == Guns.magSize(game.held)
        check(away == .none && grab == .grabbed && held == .none && ins == .inserted && full,
              "P56 VR reload: a grip away from the hip takes nothing (\(away)); at the hip a magazine (\(grab)), carried (\(held)); at the gun it slots in (\(ins)): \(game.held.tag) / \(Guns.magSize(game.held))")
    }

    // P39: lava stays easy to find: cupped single sources on cave floors between -50 and -8, never spilling.
    static func caveLava(_ check: (Bool, String) -> Void) {
        let gen = WorldGen(seed: 12345)
        var cupped = 0, chunks = 0
        for cz in 0..<4 { for cx in 0..<4 {
            let b = gen.generate(cx: cx * 3, cz: cz * 3 - 5)
            chunks += 1
            for y in (YOFF - 50)..<(YOFF - 8) { for lz in 1..<(CS - 1) { for lx in 1..<(CS - 1) {
                let i = Chunk.index(lx, y, lz)
                guard b[i] == LAVA, b[i + CSQ] == AIR else { continue }
                if [1, -1, CS, -CS, -CSQ].allSatisfy({ Blocks.opaque[Int(b[i + $0])] }) { cupped += 1 }
            } } }
        } }
        check(cupped >= 4, "P39 lava: \(cupped) cupped lava sources on cave floors (-50 to -8) in \(chunks) chunks")
    }

    // P46 / P98: after the Ashguard falls, every faction's war bands set out at once from far off and hunt the player
    // across the surface; underground they lose the trail; a death pushes them back; it ends only when every band is
    // dead, and then the land is at peace (Marauder patrols, bounty hunters, town raids stop).
    static func reckoning(_ g: Game, _ check: (Bool, String) -> Void) {
        let mobs0 = g.mobs.mobs, victory0 = g.ashVictory, survival0 = g.survival, diff0 = g.difficulty, money0 = g.money
        let pos0 = g.player.pos, fly0 = g.player.flying
        defer {
            g.mobs.mobs = mobs0; g.ashVictory = victory0; g.survival = survival0; g.difficulty = diff0; g.money = money0
            g.alive = true; Reckoning.reset(); g.player.pos = pos0; g.player.flying = fly0
        }
        let w = g.world
        _ = w.loadSync(center: pos0, radius: 5)
        let px = Int(floor(pos0.x)), pz = Int(floor(pos0.z))
        g.player.pos = V3(pos0.x, Float(w.topY(px, pz) + 1), pos0.z)
        g.mobs.mobs = []; g.ashVictory = true; g.survival = true; g.difficulty = 2; g.alive = true
        Reckoning.reset()
        let p = V2(g.player.pos.x, g.player.pos.z)
        func dists() -> [Float] { Reckoning.hunts.map { simd_length($0.pos - p) } }
        Reckoning.tick(g, 1)
        let warned = Reckoning.stage == 1 && Reckoning.timer == Reckoning.warning
        Reckoning.tick(g, Reckoning.warning + 1)
        let sides = Set(Reckoning.hunts.map { $0.side })
        let units = Reckoning.hunts.reduce(0) { $0 + $1.left }
        let far = dists().allSatisfy { $0 >= Reckoning.start.lowerBound - 1 && $0 <= Reckoning.start.upperBound + 1 }
        let begun = Reckoning.stage == 2 && sides.count == Reckoning.Side.allCases.count && units >= 80 && far
        // They close in from every side at once, and come in out of sight, capped.
        for _ in 0..<40 { Reckoning.tick(g, 10) }
        let closing = dists().filter { $0 < Reckoning.near * 1.5 }.count
        let inn = Reckoning.members(g)
        let capped = !inn.isEmpty && inn.count <= Reckoning.liveCap
        let hidden = inn.allSatisfy { simd_length(V2($0.pos.x, $0.pos.z) - p) > 30 } && inn.allSatisfy { $0.aggro }
        // Underground (in the rock below the surface): the trail is lost, the units stand down.
        g.player.pos.y = Float(w.topY(px, pz) - 12)
        Reckoning.tick(g, 1)
        let lostTrail = Reckoning.underground && Reckoning.hunts.allSatisfy { $0.trail != nil } && Reckoning.members(g).allSatisfy { !$0.aggro }
        g.player.pos.y = Float(w.topY(px, pz) + 1)
        Reckoning.tick(g, 1)
        let back = !Reckoning.underground && Reckoning.hunts.allSatisfy { $0.trail == nil }
        // They track the player: moved 400 blocks east, the bands not yet in turn after him.
        let east = p + V2(400, 0)
        let out = Reckoning.hunts.filter { $0.live.isEmpty }
        let before = out.map { simd_length($0.pos - east) }
        g.player.pos.x += 400
        Reckoning.tick(g, 20)
        let after = out.map { simd_length($0.pos - east) }
        g.player.pos.x -= 400
        let tracks = !out.isEmpty && zip(before, after).allSatisfy { $1 < $0 - 20 }
        // A death sends the units back into their bands and pushes the bands out.
        let left0 = Reckoning.hunts.reduce(0) { $0 + $1.left }
        g.alive = false
        Reckoning.tick(g, 1)
        g.alive = true
        let pushed = Reckoning.members(g).isEmpty && dists().allSatisfy { $0 >= Reckoning.deathPush - 1 }
            && Reckoning.hunts.reduce(0) { $0 + $1.left } == left0
        // Saved and loaded: the same bands with the same units.
        var d: [String: String] = [:]
        Reckoning.save(&d); Reckoning.load(d, game: g)
        let kept = Reckoning.stage == 2 && Reckoning.hunts.count == sides.count + 3 && Reckoning.hunts.reduce(0) { $0 + $1.left } == left0
        // A P46 save mid-waves becomes the hunt; a won one stays won.
        Reckoning.load(["reckoning": "1,2,0,1"], game: g)
        let legacy = Reckoning.stage == 2 && Reckoning.hunts.count == 8
        Reckoning.load(["reckoning": "2,4,0,0"], game: g)
        let legacyWon = Reckoning.won
        Reckoning.load(d, game: g)
        // Every band dead: peace and the reward.
        for h in Reckoning.hunts { h.waiting = []; for m in h.live { m.health = 0 } }
        Reckoning.tick(g, 1)
        let won = Reckoning.won && g.money == money0 + Reckoning.reward
        check(warned && begun && closing >= 3 && capped && hidden && lostTrail && back && tracks && pushed && kept && legacy && legacyWon && won,
              "P98 the Reckoning: a warning (\(warned)); \(Reckoning.Side.allCases.count) sides, \(units) units in bands 450-700 out (\(begun)); "
              + "\(closing) bands closed in, \(inn.count) units in (cap \(Reckoning.liveCap), out of sight \(hidden)); underground loses the trail (\(lostTrail)), "
              + "back up picks it up (\(back)); they track him (\(tracks)); a death pushes them out (\(pushed)); save keeps them (\(kept)); "
              + "P46 saves (\(legacy), \(legacyWon)); all dead: peace and the reward (\(won))")
    }

    // P48: citadels on new ground get a row of shops below the gate; the garrison leaves a visitor there alone until a
    // weapon stays out too long.
    static func garrisonRow(_ g: Game, _ check: (Bool, String) -> Void) {
        guard let gen = g.world.gen as? WorldGen else { return }
        var rows = 0, sites = 0, keepers = Set<String>(), guards = 0
        for i in 0..<24 {
            let x = (i % 6) * 640 + 8 - 2000, z = (i / 6) * 640 + 8 - 2000
            guard gen.groundY(x, z) > SEA + 1 else { continue }
            sites += 1
            let ps = GarrisonTown.pieces(gen, x, z, UInt64(i) &* 0x9E3779B97F4A7C15)
            guard !ps.isEmpty else { continue }
            rows += 1
            guard keepers.isEmpty else { continue }
            // Build the row into the chunks it touches and collect the people it places.
            var chunks = Set<Int64>()
            for p in ps { for cz in floorDiv(p.min.z, CS)...floorDiv(p.max.z, CS) { for cx in floorDiv(p.min.x, CS)...floorDiv(p.max.x, CS) {
                chunks.insert(Int64(cx) << 32 | Int64(UInt32(bitPattern: Int32(cz))))
            } } }
            for k in chunks {
                let cx = Int(k >> 32), cz = Int(Int32(truncatingIfNeeded: k))
                var blocks = gen.generate(cx: cx, cz: cz)
                blocks.withUnsafeMutableBufferPointer { buf in
                    var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
                    for p in ps where p.overlaps(cx * CS, cz * CS) { p.build(&w) }
                    for (n, _) in w.mobs {
                        if n.hasPrefix("villager:shop_") { keepers.insert(String(n.dropFirst(14))) }
                        if n == "soldier_trooper" { guards += 1 }
                    }
                }
            }
        }
        // The guards' patience.
        let mobs0 = g.mobs.mobs, held0 = g.inventory.held, survival0 = g.survival
        defer {
            g.mobs.mobs = mobs0; g.inventory.held = held0; g.survival = survival0
            GarrisonTown.forceRow = nil; GarrisonTown.opened = false; GarrisonTown.inRow = false; GarrisonTown.tense = 0
        }
        g.survival = true
        GarrisonTown.forceRow = true; GarrisonTown.opened = false; GarrisonTown.tense = 0
        let s = Mob(.soldierTrooper, at: g.player.pos + V3(6, 0, 0))
        g.mobs.mobs = [s]
        g.inventory.held = ItemStack()
        GarrisonTown.tick(g, 1)
        let calm = GarrisonTown.shelters(g, s)
        var held = false
        if Items.has("gun_sidearm") {
            g.inventory.held = ItemStack(Items.id("gun_sidearm"), 1)
            GarrisonTown.tick(g, 1); GarrisonTown.tick(g, 1)
            held = !GarrisonTown.opened && GarrisonTown.warned
            for _ in 0..<3 { GarrisonTown.tick(g, 1) }
        }
        let fire = GarrisonTown.opened && s.aggro && !GarrisonTown.shelters(g, s)
        check(rows >= 3 && Float(rows) >= Float(sites) * 0.4 && keepers.isSuperset(of: ["general", "saloon"]) && guards == 2 && calm && held && fire,
              "P48 garrison row: \(rows) of \(sites) citadel sites get a row (shops \(keepers.sorted().joined(separator: ", ")), \(guards) guards); calm while hands are empty (\(calm)), a warning (\(held)), then the garrison opens fire (\(fire))")
    }

    // P51: roads join neighbouring towns over new ground; a rider held at gunpoint throws down their satchel, which is a
    // crime (a bounty and a posse with six-irons); bounty hunters carry a gun; dying to them pays the bounty off with
    // every cent you had.
    static func roadsAndRiders(_ g: Game, _ check: (Bool, String) -> Void) {
        guard let gen = g.world.gen as? WorldGen else { return }
        // Roads.
        let p440 = WorldRules.p44
        WorldRules.p44 = true
        var segs: [Roads.Seg] = []
        for rz in -3...3 { for rx in -3...3 { for (dx, dz) in [(1, 0), (0, 1)] { if let sgm = Roads.segment(gen, rx, rz, dx, dz) { segs.append(sgm) } } } }
        var paved = 0, cols = 0
        if let sgm = segs.first {
            let mid = Roads.point(sgm, 0.5)
            let cx = floorDiv(Int(mid.x), CS), cz = floorDiv(Int(mid.y), CS)
            var blocks = gen.generate(cx: cx, cz: cz)
            // (PG5: in a Polygons world the path goes down as packed earth, StructWriter.roadID, and sand roads as sandstone.)
            let surfaces: Set<BlockID> = [Blocks.id("dirt_path"), StructWriter.roadID, Blocks.has("sandstone") ? Blocks.id("sandstone") : AIR,
                                          Blocks.has("smooth_sandstone") ? Blocks.id("smooth_sandstone") : AIR]
            let before = blocks
            blocks.withUnsafeMutableBufferPointer { buf in
                var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
                Roads.draw(gen, &w, cx, cz)
                for lz in 0..<CS { for lx in 0..<CS {
                    let x = cx * CS + lx, z = cz * CS + lz
                    guard Roads.distance(sgm, V2(Float(x) + 0.5, Float(z) + 0.5)).0 <= Roads.halfWidth else { continue }
                    cols += 1
                    if (40..<(CH - 1)).contains(where: { surfaces.contains(w.get(x, $0, z)) && before[Chunk.index(lx, $0, lz)] != w.get(x, $0, z) }) { paved += 1 }
                } }
            }
        }
        WorldRules.p44 = p440
        // A rider, held up.
        let mobs0 = g.mobs.mobs, money0 = g.money, held0 = g.inventory.held, honour0 = Honour.value, law0 = TownLaw.state
        let survival0 = g.survival, pos0 = g.player.pos, yaw0 = g.player.yaw, pitch0 = g.player.pitch
        let alive0 = g.alive, riding0 = g.riding, aim0 = g.vrAim
        defer {
            g.alive = alive0; g.riding = riding0; g.vrAim = aim0
            g.mobs.mobs = mobs0; g.money = money0; g.inventory.held = held0; Honour.value = honour0; TownLaw.state = law0
            g.survival = survival0; g.player.pos = pos0; g.player.yaw = yaw0; g.player.pitch = pitch0; Riders.forceRoad = nil; Riders.along = 50...80
        }
        g.survival = true; g.mobs.mobs = []; g.money = 0; TownLaw.state.bounty = [:]
        g.alive = true; g.riding = nil; g.vrAim = nil            // (whatever an earlier check left: on foot, aiming with the view)
        // Up in the open air (whatever ground an earlier check left the player on: nothing between gun and rider).
        g.player.pos.y = Float(g.world.topY(Int(floor(pos0.x)), Int(floor(pos0.z))) + 24)
        let p = g.player.pos
        Riders.forceRoad = (Roads.Seg(a: V2(p.x - 120, p.z), b: V2(p.x + 120, p.z), phase: 0), 0.5)
        Riders.along = 10...16                 // (inside the host check's loaded ground)
        var rider: Mob?
        FactionRaids.lastAssault = -1e9                    // (P215: no posse within 90 minutes of any check's assault)
        for _ in 0..<6 where rider == nil { rider = Riders.send(g) }
        var robbedOK = false, posse = 0, gunmen = true, mounted = false, robWhy = ""
        if let r = rider, let h = r.mount, Items.has("gun_sidearm") {
            mounted = h.kind == .horse && h.saddled
            h.pos = p + V3(8, 0, 0); r.pos = h.pos + V3(0, h.height * 0.8, 0)
            g.inventory.held = ItemStack(Items.id("gun_sidearm"), 1)
            let d = r.eye - g.player.eye
            g.player.yaw = atan2f(-d.x, -d.z); g.player.pitch = asinf(d.y / simd_length(d))
            let aimed = Riders.aimedAt(r, g)
            for _ in 0..<4 { _ = Riders.step(r, 0.5, g) }
            robbedOK = r.posse == Riders.robbed && g.money > 0 && BountyHunters.totalBounty >= Riders.robBounty
            if !robbedOK { robWhy = "aimed \(aimed), robbed \(r.posse == Riders.robbed), money \(g.money), bounty \(BountyHunters.totalBounty), dim \(g.dim.dim)" }
            let gm = g.mobs.mobs.filter { $0.posse == 3 }
            posse = gm.count
            gunmen = gm.allSatisfy { $0.townWeapon == .revolver && $0.town.anger > 0 }
        }
        // Killed with the posse on you: they collect.
        BountyHunters.claim(g)
        let collected = g.money == 0 && BountyHunters.totalBounty == 0
        // Bounty hunters: the first one carries a six-iron.
        g.mobs.mobs = []
        Honour.value = -90; TownLaw.state.huntersDay = nil; TownLaw.inTown = nil
        let chance0 = BountyHunters.chancePerSecond
        BountyHunters.chancePerSecond = 1
        BountyHunters.send(g)
        BountyHunters.chancePerSecond = chance0
        let gunHunter = g.mobs.mobs.contains { $0.customName == BountyHunters.name && ($0.brain?.gun ?? -1) == Guns.revolver }   // (R21: the leader)
        check(segs.count >= 3 && cols > 0 && paved * 10 >= cols * 6 && mounted && robbedOK && posse >= 2 && gunmen && collected && gunHunter,
              "P51 roads and riders: \(segs.count) roads near the origin, \(paved) of \(cols) road columns paved; a rider on horseback (\(mounted)) held up throws down the satchel and a bounty (\(robbedOK)\(robWhy.isEmpty ? "" : ": " + robWhy)); a posse of \(posse) with six-irons (\(gunmen)); dying to them pays it off (\(collected)); a hunter with a gun (\(gunHunter))")
    }

    // P49 horse items: half as much stamina again; a monster beside the horse makes it shy briefly (no throw, never at
    // a gallop) instead of rearing the rider to a stop.
    static func horseItems(_ g: Game, _ check: (Bool, String) -> Void) {
        let h = Mob(.horse, at: g.player.pos + V3(3, 0, 0))
        h.owner = true; h.saddled = true
        h.shy(g)
        let short = h.hs.rear > 0 && h.hs.rear <= 0.5 && !h.hs.rearThrow
        h.hs.rear = 0; h.hs.spookCool = 0; h.hs.gait = .gallop
        h.shy(g)
        let gallop = h.hs.rear == 0
        check(HorseFeel.staminaMax[0] >= 150 && short && gallop,
              "P49 horses: stamina \(Int(HorseFeel.staminaMax[0]))-\(Int(HorseFeel.staminaMax[3])) (was 100-150); a monster beside it: a short shy, no throw (\(short)); none at a gallop (\(gallop))")
    }

    // P54 prototype: the Vehicle Works names what a Field Tank still needs, and with the parts (here: creative) rolls one
    // out on clear ground beside it, wheels on the ground.
    static func vehicleWorks(_ g: Game, _ check: (Bool, String) -> Void) {
        guard Blocks.has(VehicleWorks.key) else { check(false, "P54 vehicle works: block missing"); return }
        let survival0 = g.survival, inv = g.inventory.main.slots, pos0 = g.player.pos
        var toast = ""
        let toast0 = g.onToast
        defer { g.survival = survival0; g.inventory.main.slots = inv; g.player.pos = pos0; g.onToast = toast0 }
        g.onToast = { toast = $0 }
        g.survival = true
        for i in 0..<36 { g.inventory.main[i] = .empty }
        let w = g.world
        // A works on a flat platform in the air beside the player (clear yard all round).
        let base = IVec3(Int(floor(pos0.x)) + 4, min(CH - 20, Int(floor(pos0.y)) + 30), Int(floor(pos0.z)))
        for z in (base.z - 10)...(base.z + 10) { for x in (base.x - 12)...(base.x + 12) {
            w.setBlockAsync(x, base.y - 1, z, STONE)
            for y in base.y...(base.y + 8) where !w.isAir(x, y, z) { w.setBlockAsync(x, y, z, AIR) }
        } }
        w.setBlock(base.x, base.y, base.z, Blocks.id(VehicleWorks.key))
        g.player.pos = V3(Float(base.x) - 2.5, Float(base.y), Float(base.z) + 0.5)
        let ships0 = w.ships.list.count
        // (P459: the Works always opens its list, every row with its whole bill.)
        VehicleWorks.use(g, base)
        let wm = g.menu as? VehicleWorksMenu
        let bill = wm?.rows.first?.detail ?? ""
        wm?.pressed(0)
        let asked = toast.contains("needs") && w.ships.list.count == ships0 && bill.contains("Still needs 96 ")
        g.closeMenu()
        g.survival = false
        VehicleWorks.use(g, base)
        (g.menu as? VehicleWorksMenu)?.pressed(0)
        if g.menu != nil { g.closeMenu() }
        let made = w.ships.list.filter { $0.name == "Field Tank" }
        var rolled = false, wheelsDown = false
        if let t = made.last {
            rolled = t.pos.x > Float(base.x) + 3
            wheelsDown = abs(t.toWorld(V3(0, t.localMin.y, 0)).y - (Float(base.y) + 0.6)) < 0.7
            w.ships.remove(t)
        }
        for z in (base.z - 10)...(base.z + 10) { for x in (base.x - 12)...(base.x + 12) {
            for y in (base.y - 1)...(base.y + 8) where !w.isAir(x, y, z) { w.setBlockAsync(x, y, z, AIR) }
        } }
        check(asked && made.count == 1 && rolled && wheelsDown,
              "P54 vehicle works: short of parts it says so (\(asked): \(bill)); with them a Field Tank rolls out beside it (\(made.count), on the far side: \(rolled)), wheels on the ground (\(wheelsDown))")
    }

    // G21: the Farsight raised to the eye zooms 4x; the crosshair sits where the hand's ray (the round's line) meets
    // the view.
    static func vrScope(_ check: (Bool, String) -> Void) {
        let head = V3(0, 1.6, 0), fwd = V3(0, 0, -1)
        let atEye = VRScope.raised(heldKey: VRScope.gun, head: head, headForward: fwd, aimOrigin: head + V3(0.05, -0.08, 0.1), aimDir: fwd)
        let atHip = VRScope.raised(heldKey: VRScope.gun, head: head, headForward: fwd, aimOrigin: head + V3(0.25, -0.6, -0.1), aimDir: fwd)
        let rifle = VRScope.raised(heldKey: "gun_rifle", head: head, headForward: fwd, aimOrigin: head + V3(0.05, -0.08, 0.1), aimDir: fwd)
        let vp = perspectiveRH(fovy: 1.6, aspect: 1, near: 0.05, far: 500)
        let centre = VRScope.reticle(viewProj: vp, center: .zero, aimOrigin: .zero, aimDir: fwd) ?? V2(9, 9)
        let right = VRScope.reticle(viewProj: vp, center: .zero, aimOrigin: .zero, aimDir: simd_normalize(V3(0.05, 0, -1))) ?? V2(-9, 0)
        check(atEye && !atHip && !rifle && simd_length(centre) < 0.01 && right.x > 0.02 && VRScope.zoom(1) == 4 && VRScope.zoom(0) == 1,
              String(format: "G21 VR scope: up at the eye %@, at the hip %@, another gun %@; crosshair on the round's line (%.3f, %.3f), right of it for a ray to the right (%.3f); zoom x%.0f", atEye ? "yes" : "no", atHip ? "yes" : "no", rifle ? "yes" : "no", centre.x, centre.y, right.x, VRScope.zoom(1)))
    }
}
