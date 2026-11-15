import Foundation
import simd

// Ledgers 130 and 131 (`questcheck --placerow`), in a field world of seed 4242 on a made flat of earth:
//   (6) ledger 133: stone set on a wall top and broken leaves no lump that cannot be broken;
//   (7) a sliver of ground no cell holds is cleared by a blow;
//   (1) a block built out from a wall's top, a block and a half over the ground, leaves the ground as it is (it rose
//       to meet it before: BS_OLDMEET=1);
//   (2) a block set down on the ground with a gap under it still has the ground rise to its floor;
//   (3) aimed at the ground beside a built block, a block joins that block's row whether the surface at the aim
//       stands low or high in its cell;
//   (4) aimed into a hole that still holds a little ground, the block takes the hole's cell;
//   (5) with nothing built beside it, the row whose floor is nearest the surface.
enum PlaceRowTests {
    static func run(_ g0: Game, check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 4242, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 3; w.activeDistance = 3
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        let at = V3(8, 200, 8)
        g.player.pos = at
        _ = w.loadSync(center: at, radius: 3)
        let dirt = FieldMat.index[Int(DIRT)]
        func set(_ x: Int, _ y: Int, _ z: Int, _ mat: UInt8?) {
            guard let c = w.chunkAt(x, z) else { return }
            c.blocks.setDensity(Chunk.index(mod(x, CS), y, mod(z, CS)), mat != nil ? 32 : -32, material: mat)
        }
        var top = CH - 2
        while top > 1 && !w.groundAt(0, top, 0) { top -= 1 }
        let H = top + 6                                  // the flat's top ground cell
        for z in -12...12 { for x in -12...12 {
            for y in (top - 6)...H { set(x, y, z, dirt) }
            for y in (H + 1)...(H + 10) { set(x, y, z, nil); if w.builtBlock(x, y, z) != AIR { w.setBlock(x, y, z, AIR) } }
        } }
        g.player.pos = V3(20, Float(H) + 6, 20)          // (well off the cells below)
        let planks = Blocks.id("oak_planks")
        func ground(_ x: Int, _ z: Int) -> Float {
            w.fieldRaySegment(V3(Float(x) + 0.5, Float(H) + 8, Float(z) + 0.5), V3(0, -1, 0), from: 0, to: 16).map { $0.at.y } ?? -1
        }
        // (1) a wall two high at (0, 0); a block built out from its top over (1, 0)
        w.setBlock(0, H + 1, 0, planks); w.setBlock(0, H + 2, 0, planks)
        let before = ground(1, 0)
        w.setBlock(1, H + 2, 0, planks)
        let rose = w.meetGround(1, H + 2, 0, planks)
        let after = ground(1, 0)
        check(World.oldMeet ? true : (rose == 0 && abs(after - before) < 0.01),
              String(format: "placerow (1): a block built out from a wall's top over the ground leaves the ground as it is (%d cells turned to ground; the ground under it %.2f before, %.2f after; its floor at %d)", rose, before - Float(YOFF), after - Float(YOFF), H + 2 - YOFF))
        // (2) a block set down on the ground at (4, 4), in the cell over the top ground cell: its floor is met
        for z in 3...5 { for x in 3...5 {                 // (the flat's top cell thin here: the surface 0.3 under the row)
            if let c = w.chunkAt(x, z) { c.blocks.setDensity(Chunk.index(mod(x, CS), H, mod(z, CS)), 8, material: dirt) }
        } }
        let g0y = ground(4, 4)
        w.setBlock(4, H + 1, 4, planks)
        w.meetGround(4, H + 1, 4, planks)
        let gap = w.floorGap(4, H + 1, 4)
        // (on this made flat, coarse cells with no fine samples, the rise stops 0.16 short, and 0.23 before the change)
        check(Float(H + 1) - g0y > 0.15 && gap < (Float(H + 1) - g0y) * 0.6, String(format: "placerow (2): a block set down on the ground still has the ground rise toward its floor (the ground stood %.2f under the floor, now %.2f)", Float(H + 1) - g0y, gap))
        // (3) beside the wall's foot (0, H + 1, 0), aimed at the ground of (-1, 0): the surface low in the cell over the
        // flat, or high in the flat's top cell, the block joins row H + 1
        func aim(_ x: Int, _ z: Int, _ y: Float) -> (cell: IVec3, sunk: Bool)? {
            let cell = IVec3(x, Int(floor(y)), z)
            g.targetGround = (cell, V3(Float(x) + 0.5, y, Float(z) + 0.5), V3(0, 1, 0))
            return g.groundRowCell((hit: cell, normal: IVec3(0, 1, 0)), for: planks)
        }
        let lowAim = aim(-1, 0, Float(H) + 0.3), highAim = aim(-1, 0, Float(H) + 0.8), overAim = aim(-1, 0, Float(H + 1) + 0.2)
        check(Game.oldPlaceRow ? true : (lowAim?.cell.y == H + 1 && highAim?.cell.y == H + 1 && overAim?.cell.y == H + 1),
              "placerow (3): beside a built block a block joins its row (row \(H + 1 - YOFF)): the surface low in the cell under it -> \(lowAim.map { String($0.cell.y - YOFF) } ?? "nil"), high in it -> \(highAim.map { String($0.cell.y - YOFF) } ?? "nil"), low in the row's own cell -> \(overAim.map { String($0.cell.y - YOFF) } ?? "nil")")
        // (4) a hole: the top cell of (8, 8) dug down to a fifth of a block of ground; the block takes that cell
        let hole = aim(8, 8, Float(H) + 0.2)
        check(Game.oldPlaceRow ? true : (hole?.cell.y == H), "placerow (4): aimed into a hole that still holds a little ground the block takes the hole's cell (row \(H - YOFF)): \(hole.map { "row \($0.cell.y - YOFF)\($0.sunk ? ", its ground cleared first" : "")" } ?? "nil")")
        // (5) nothing built beside: the nearest row
        let n0 = aim(-8, -8, Float(H) + 0.3), n1 = aim(-8, -8, Float(H) + 0.7)
        check(Game.oldPlaceRow ? true : (n0?.cell.y == H && n1?.cell.y == H + 1), "placerow (5): on open ground the row whose floor is nearest the surface: surface 0.3 up its cell -> row \(n0.map { String($0.cell.y - YOFF) } ?? "nil") (the cell itself, \(H - YOFF)), 0.7 up -> row \(n1.map { String($0.cell.y - YOFF) } ?? "nil") (the one over it)")
        g.targetGround = nil
        // (6) ledger 133: stone set on a wall's top (as the game places it: the cell, then its swell toward the aim),
        // broken as Creative breaks it; what is left hanging in cells with no ground is a sliver, and a blow clears it
        let stone = FieldMat.index[Int(STONE)]
        let cx = -6, cz = 6
        w.setBlock(cx, H + 1, cz, planks); w.setBlock(cx, H + 2, cz, planks)
        func lumps() -> (n: Int, at: V3?) {
            var n = 0, first: V3?
            for iy in 0..<24 { for iz in 0..<24 { for ix in 0..<24 {
                let p = V3(Float(cx) - 1 + (Float(ix) + 0.5) * 0.125, Float(H) + 2.3 + (Float(iy) + 0.5) * 0.125, Float(cz) - 1 + (Float(iz) + 0.5) * 0.125)
                let c = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
                guard w.builtBlock(c.x, c.y, c.z) == AIR, w.fieldDensity(at: p) > 0 else { continue }
                n += 1
                if first == nil { first = p }
            } } }
            return (n, first)
        }
        let clean = lumps().n
        let cell = IVec3(cx, H + 3, cz)
        w.editBatch {
            w.setBlock(cell.x, cell.y, cell.z, STONE)
            w.fieldSphere(V3(Float(cx) + 0.5, Float(H + 3) + 0.45, Float(cz) + 0.5), radius: 0.62, carve: false, material: stone, keepSolid: true, remesh: true)
        }
        let placed = lumps().n
        g.player.pitch = -Float.pi / 2
        g.breakAndShape(cell, w.block(cell.x, cell.y, cell.z), at: V3(Float(cx) + 0.5, Float(H + 4) - 0.25, Float(cz) + 0.5), drop: false)
        let left = lumps()
        var blows = 0, now = left
        while let p = now.at, blows < 6, !Game.oldSliver {
            g.clearSliver(at: p); blows += 1
            now = lumps()
        }
        let holdsGround = left.at.map { w.groundAt(Int(floor($0.x)), Int(floor($0.y)), Int(floor($0.z))) }
        check(clean == 0 && placed > 0 && now.n == 0,
              "placerow (6): stone set on a wall's top and broken: \(placed) sample points of ground once placed, \(left.n) left by the break\(holdsGround.map { $0 ? " (in a cell that holds ground)" : " (in a cell that holds none: a sliver)" } ?? ""), \(now.n) after \(blows) blows on what was left (clean before: \(clean))")
        // (7) ledger 133: a sliver, a lump of ground between cell middles so that no cell holds ground: the aim names an
        // air cell (nothing to break before); a blow on it clears it
        let sp = V3(6.0, Float(H) + 2.6, -6.0)
        w.fieldSphere(sp, radius: 0.5, carve: false, material: stone, remesh: true)
        func sliver() -> (n: Int, cells: Int, at: V3?) {
            var n = 0, first: V3?, cells = 0
            for iy in 0..<16 { for iz in 0..<16 { for ix in 0..<16 {
                let p = sp + V3((Float(ix) - 7.5) * 0.125, (Float(iy) - 7.5) * 0.125, (Float(iz) - 7.5) * 0.125)
                if w.fieldDensity(at: p) > 0 { n += 1; if first == nil { first = p } }
            } } }
            for dy in -1...0 { for dz in -1...0 { for dx in -1...0 where w.groundAt(6 + dx, H + 2 + dy + 1, -6 + dz) { cells += 1 } } }
            return (n, cells, first)
        }
        let s0 = sliver()
        var s1 = s0, sBlows = 0
        while let p = s1.at, sBlows < 4 { g.clearSliver(at: p); sBlows += 1; s1 = sliver() }
        check(s0.n > 0 && s0.cells == 0 && s1.n == 0,
              "placerow (7): a sliver of ground between cell middles (\(s0.n) sample points, \(s0.cells) of the 8 cells round it hold ground) is cleared by \(sBlows) blows (\(s1.n) points left)")
        // (8) ledger 136: rock he places is a built cube, loose ground still joins the ground
        let rx = 10, rz = -10
        w.placeCube = !Game.oldRockLump
        w.setBlock(rx, H + 1, rz, STONE)
        w.placeCube = false
        w.setBlock(rx + 2, H + 1, rz, DIRT)
        let rockBuilt = w.builtBlock(rx, H + 1, rz) == STONE && !w.groundAt(rx, H + 1, rz)
        let dirtGround = w.builtBlock(rx + 2, H + 1, rz) == AIR && w.groundAt(rx + 2, H + 1, rz)
        let basalt = Blocks.has("basalt") ? Blocks.id("basalt") : STONE, sand = Blocks.has("sand") ? Blocks.id("sand") : DIRT
        let kinds = !FieldTerrain.loose[Int(STONE)] && !FieldTerrain.loose[Int(basalt)] && FieldTerrain.loose[Int(sand)] && FieldTerrain.loose[Int(DIRT)]
        w.setBlock(rx, H + 1, rz, AIR)
        let gone = w.builtBlock(rx, H + 1, rz) == AIR && !w.groundAt(rx, H + 1, rz)
        check(Game.oldRockLump ? true : (rockBuilt && dirtGround && kinds && gone),
              "placerow (8): placed stone is a built cube (\(rockBuilt)), placed earth joins the ground (\(dirtGround)); stone and basalt are rock, sand and earth loose (\(kinds)); the cube broken leaves nothing (\(gone))")
        // (9) ledger 159: a corner cell between two built blocks, its ground dug to a slope
        notch(g, w, H, planks, check: check)
        // (11) ledger 159: the target hold (AimAssist.sticky) never keeps a block's top while he aims past its edge
        hold(g, w, H, planks, check: check)
        // (10) ledger 160: the bowl a blow leaves closes round a block put back in it; a dug cell beside it stays open
        back(g, w, H, planks, check: check)
    }
    static func notch(_ g: Game, _ w: World, _ H: Int, _ planks: BlockID, check: (Bool, String) -> Void) {
        let nx = -8, nz = 8                                // the corner cell (nx, H, nz); planks west and north of it
        func sink(_ x: Int, _ z: Int) {
            w.editBatch {
                w.fieldSphere(V3(Float(x) + 0.5, Float(H) + 0.5, Float(z) + 0.5), radius: 0.56, carve: true, material: nil, remesh: false)
                w.placeCube = true; w.setBlock(x, H, z, planks); w.placeCube = false
            }
        }
        for (x, z) in [(nx - 1, nz - 1), (nx, nz - 1), (nx + 1, nz - 1), (nx - 1, nz), (nx - 1, nz + 1)] { sink(x, z) }
        // the pit he dug beside them: Creative blows on the cells south-east of the corner, and one on the corner itself
        g.player.pitch = -Float.pi / 2
        for (x, y, z) in [(nx + 1, H, nz + 1), (nx + 1, H - 1, nz + 1), (nx, H, nz + 1), (nx + 1, H, nz), (nx, H, nz)] {
            g.breakAndShape(IVec3(x, y, z), w.block(x, y, z), at: V3(Float(x) + 0.5, Float(y) + 0.8, Float(z) + 0.5), drop: false)
        }
        var tally: [String: Int] = [:], n = 0, inCorner = 0, over = 0
        let p = g.player
        p.flying = true
        for (ex, ez) in [(Float(nx) + 2.6, Float(nz) + 2.2), (Float(nx) + 0.5, Float(nz) + 3.0), (Float(nx) + 3.0, Float(nz) + 0.5), (Float(nx) + 1.6, Float(nz) + 1.6)] {
            for iu in 0..<5 { for iv in 0..<5 { for h in 0..<3 {
                let q = V3(Float(nx) + 0.1 + Float(iu) * 0.2, Float(H) + 0.1 + Float(h) * 0.35, Float(nz) + 0.1 + Float(iv) * 0.2)
                p.pos = V3(ex, Float(H) + 1.0, ez)
                let dv = q - p.eye
                p.yaw = atan2f(-dv.x, -dv.z); p.pitch = atan2f(dv.y, simd_length(V2(dv.x, dv.z)))
                guard let t = w.raycast(p.eye, p.look, maxDist: 6) else { continue }
                g.target = t
                g.aimGround()
                guard let tt = g.target, let tg = g.targetGround, tg.cell == tt.hit else { continue }
                // (aims whose surface point lies in the corner cell's column)
                guard Int(floor(tg.at.x)) == nx, Int(floor(tg.at.z)) == nz else { continue }
                let at = g.placeCell(tt, for: planks)
                n += 1
                if at == IVec3(nx, H, nz) { inCorner += 1 }
                if at == IVec3(nx, H + 1, nz) { over += 1 }
                tally["\(at.x - nx),\(at.y - H),\(at.z - nz)", default: 0] += 1
                if ProcessInfo.processInfo.environment["BS_NOTCHTRACE"] == "1" {
                    print(String(format: "  notch: surface %.2f %.2f %.2f n %.2f %.2f %.2f hit %d,%d,%d axis %d,%d,%d -> %d,%d,%d", tg.at.x - Float(nx), tg.at.y - Float(H), tg.at.z - Float(nz), tg.normal.x, tg.normal.y, tg.normal.z, tt.hit.x - nx, tt.hit.y - H, tt.hit.z - nz, tt.normal.x, tt.normal.y, tt.normal.z, at.x - nx, at.y - H, at.z - nz))
                }
            } } }
        }
        g.target = nil; g.targetGround = nil
        check(Game.oldNotch ? true : (n >= 20 && inCorner == n),
              "placerow (9): aimed at the dug ground of a corner cell between two built blocks, the block takes that cell: \(inCorner) of \(n) aims (\(over) went over it; cells from the corner: \(tally.sorted { $0.value > $1.value }.map { "\($0.key) x\($0.value)" }.joined(separator: ", ")))")
    }
    static func back(_ g: Game, _ w: World, _ H: Int, _ planks: BlockID, check: (Bool, String) -> Void) {
        func surf(_ x: Float, _ z: Float) -> Float {
            let o = V3(x, Float(H) + 3, z)
            if w.fieldDensity(at: o) > 0 { return o.y }
            return w.fieldRaySegment(o, V3(0, -1, 0), from: 0, to: 8).map { $0.at.y } ?? -1
        }
        // the ring: eight points three quarters of a block from the cell's middle
        func ring(_ x: Int, _ z: Int, skip: (Int, Int)? = nil) -> [Float] {
            var out: [Float] = []
            for sz in -1...1 { for sx in -1...1 where (sx != 0 || sz != 0) && !(skip.map { $0.0 == sx && $0.1 == sz } ?? false) {
                out.append(surf(Float(x) + 0.5 + Float(sx) * 0.75, Float(z) + 0.5 + Float(sz) * 0.75))
            } }
            return out
        }
        func blow(_ x: Int, _ z: Int) {
            g.breakAndShape(IVec3(x, H, z), w.block(x, H, z), at: V3(Float(x) + 0.5, Float(H) + 0.9, Float(z) + 0.5), drop: false)
        }
        func put(_ x: Int, _ z: Int) -> Int {
            var n = 0
            w.editBatch {
                if w.groundAt(x, H, z) { w.fieldSphere(V3(Float(x) + 0.5, Float(H) + 0.5, Float(z) + 0.5), radius: 0.56, carve: true, material: nil, remesh: false) }
                w.placeCube = true; w.setBlock(x, H, z, planks); w.placeCube = false
                n = w.groundBack(x, H, z, planks)
            }
            return n
        }
        g.player.pitch = -Float.pi / 2
        // (a) one blow, the block put back
        let ax = 8, az = -6
        let a0 = ring(ax, az)
        blow(ax, az)
        let a1 = ring(ax, az)
        let an = put(ax, az)
        let a2 = ring(ax, az)
        let dug = zip(a0, a1).map { $0 - $1 }.max() ?? 0, left = zip(a0, a2).map { $0 - $1 }.max() ?? 0, over = zip(a0, a2).map { $1 - $0 }.max() ?? 0
        check(World.oldBack ? true : (dug > 0.2 && left < 0.15 && over < 0.15),
              String(format: "placerow (10a): a blow rounds the ground beside its cell down by up to %.2f; a block put back in the cell has the ground stand up to it again (now %.2f under where it was at worst, %.2f over; %d samples raised)", dug, left, over, an))
        // (b) two cells dug side by side (a trench), the block put in one: the other stays open
        let bx = 8, bz = 0
        blow(bx, bz); blow(bx + 1, bz)
        let open0 = surf(Float(bx) + 1.5, Float(bz) + 0.5)
        _ = put(bx, bz)
        let open1 = surf(Float(bx) + 1.5, Float(bz) + 0.5)
        let far = ring(bx, bz, skip: nil)
        check(World.oldBack ? true : (open1 - open0 < 0.1 && open1 < Float(H) + 0.45),
              String(format: "placerow (10b): the cell he dug beside it stays open (its middle %.2f under the level before the block, %.2f after; the ground on the block's other sides %.2f under at worst)", Float(H) + 1 - open0, Float(H) + 1 - open1, Float(H) + 1 - (far.min() ?? 0)))
    }
    static func hold(_ g: Game, _ w: World, _ H: Int, _ planks: BlockID, check: (Bool, String) -> Void) {
        // a plank at (hx, H + 1, hz), a second one two cells on and one down (the far wall of a gap); the aim passes a
        // twelfth of a block past the first one's edge, down into the gap, onto the second
        let hx = -10, hz = -2
        w.setBlock(hx, H + 1, hz, planks); w.setBlock(hx + 2, H + 1, hz, planks)
        let p = g.player
        p.flying = true
        p.pos = V3(Float(hx) - 1.0, Float(H) + 1.6, Float(hz) + 0.5)
        p.pos.y += Float(H) + 3.24 - p.eye.y                                    // (the eye at H + 3.24: 0.08 over the first plank's far edge)
        let q = V3(Float(hx) + 2.0, Float(H) + 1.5, Float(hz) + 0.5)           // on the far plank's near side
        let dv = q - p.eye
        p.yaw = atan2f(-dv.x, -dv.z); p.pitch = atan2f(dv.y, simd_length(V2(dv.x, dv.z)))
        let ray = w.raycast(p.eye, p.look, maxDist: 6)
        let first = (hit: IVec3(hx, H + 1, hz), normal: IVec3(0, 1, 0))
        let pass = World.rayBox(p.eye, p.look, V3(Float(hx) - 0.12, Float(H + 1) - 0.12, Float(hz) - 0.12), V3(Float(hx) + 1.12, Float(H + 2) + 0.12, Float(hz) + 1.12)) != nil
        let mining0 = g.mining
        g.mining = nil
        AimAssist.last = first
        let free = AimAssist.sticky(g, ray, reach: 6)
        g.mining = first.hit
        AimAssist.last = first
        let held = AimAssist.sticky(g, ray, reach: 6)
        g.mining = mining0; AimAssist.last = nil
        let on = Settings.shared.aimAssist && PadManager.shared.usingPad
        check(AimAssist.oldSticky || !on ? true : (ray?.hit == IVec3(hx + 2, H + 1, hz) && pass && free?.hit == ray?.hit && held?.hit == first.hit),
              "placerow (11): aimed past a block's edge into a gap (within an eighth of a block of it: \(pass)), the target is what the aim meets (\(free.map { "\($0.hit.x - hx),\($0.hit.y - H - 1),\($0.hit.z - hz)" } ?? "nil"), wanted 2,0,0), not the block before; while that block is being mined the hold keeps it (\(held.map { "\($0.hit.x - hx),\($0.hit.y - H - 1),\($0.hit.z - hz)" } ?? "nil"), wanted 0,0,0); assist on: \(on)")
    }
}
