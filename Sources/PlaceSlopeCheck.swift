import Foundation
import simd

// Bug hunt a (Fable, Nov 18: "placing on sloped smooth ground"): in a Polygons world as the headset makes it, the
// player stands on sloped ground at 48 spots in 8 regions far apart (different biomes) and places one of every
// placeable class on the slope in front of him, aimed at the drawn ground the way his hand points: a cube, a slab,
// stairs, a door, a fence, a torch, a sign, a rail, a bed, a chest, a plant. Each one must land in the cell the aim
// shows (the column the ray meets the ground in, the row at that height), and nothing may float over the drawn ground
// or sink under it; what rests on its floor has the ground closed up under it (World.floorGap).
//   questcheck --placeslope (BS_PLACESLOPE_TRACE=1 prints every placement)
enum PlaceSlopeCheck {
    static let trace = Env.all["BS_PLACESLOPE_TRACE"] == "1"

    struct Tally { var aimed = 0, placed = 0, wrongCell = 0, float = 0, sink = 0, gap = 0, refused = 0; var notes: [String] = [] }

    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 4259144782798118884, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 2; w.activeDistance = 2
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        let p = g.player
        let classes: [(String, String)] = [("cube", "stone"), ("slab", "stone_slab"), ("stairs", "oak_stairs"), ("door", "oak_door"),
                                           ("fence", "oak_fence"), ("torch", "torch"), ("sign", "oak_sign"), ("rail", "rail"),
                                           ("bed", "red_bed"), ("chest", "chest"), ("table", "crafting_table"), ("furnace", "furnace"),
                                           ("plant", "poppy")]
        var tally: [String: Tally] = [:]
        for (n, _) in classes { tally[n] = Tally() }
        func top(_ x: Int, _ z: Int) -> Int {
            var t = CH - 2
            while t > 1 && !w.groundAt(x, t, z) { t -= 1 }
            return t
        }
        // The drawn ground's height over a point (nil: none within 6 under the top).
        func surface(_ x: Float, _ z: Float, from y: Float) -> Float? {
            w.fieldRaySegment(V3(x, y, z), V3(0, -1, 0), from: 0, to: 6).map { $0.at.y }
        }
        let regions: [(Int, Int)] = [(-2398, -3300), (-5024, -1693), (1137, -1587), (-4569, -315), (3200, 2400), (-800, 5200), (6100, -900), (-6400, 3900), (4800, -5200), (-3000, -6100)]
        var spots = 0
        for (ri, (rx, rz)) in regions.enumerated() {
            _ = w.loadSync(center: V3(Float(rx) + 0.5, 200, Float(rz) + 0.5), radius: 2)
            var used = 0
            // Stand spots: columns with ground a block or two higher or lower two blocks off (a slope), dry, open.
            var k = 0
            while used < 7 && k < 600 {
                let sx = rx - 18 + Int(hash3(ri, k, 0, 0x51E) % 37), sz = rz - 18 + Int(hash3(ri, k, 1, 0x51E) % 37)
                k += 1
                let ty = top(sx, sz)
                guard !Blocks.isLiquid(w.block(sx, ty + 1, sz)) else { continue }
                var slope = 0
                for (dx, dz) in [(2, 0), (-2, 0), (0, 2), (0, -2)] { slope = max(slope, abs(top(sx + dx, sz + dz) - ty)) }
                guard slope >= 1 && slope <= 3 else { continue }
                // Clear what grows or stands round it (a bare slope: the check is about the ground).
                for y in (ty - 4)...(ty + 8) { for z in (sz - 5)...(sz + 5) { for x in (sx - 5)...(sx + 5) where !w.groundAt(x, y, z) {
                    let b = w.block(x, y, z)
                    if b != AIR && !Blocks.isLiquid(b) { w.setBlock(x, y, z, AIR) }
                } } }
                // Targets: sloped columns 2 to 4 off round him, each its own.
                var targets: [IVec3] = []
                for r in 2...4 { for (dx, dz) in [(1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)] {
                    let tx = sx + dx * r, tz = sz + dz * r
                    let h = top(tx, tz)
                    guard !Blocks.isLiquid(w.block(tx, h + 1, tz)), abs(h - ty) <= 2 else { continue }
                    var s = 0
                    for (ex, ez) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { s = max(s, abs(top(tx + ex, tz + ez) - h)) }
                    guard s >= 1, !targets.contains(where: { abs($0.x - tx) + abs($0.z - tz) < 2 }) else { continue }
                    targets.append(IVec3(tx, h, tz))
                } }
                guard targets.count >= 4 else { continue }
                used += 1; spots += 1
                for (ti, t) in targets.enumerated() where ti < classes.count {
                    let (cls, key) = classes[(ti + spots) % classes.count]
                    guard Items.has(key), Blocks.has(key) else { continue }
                    var tl = tally[cls]!
                    p.pos = V3(Float(sx) + 0.5, Float(ty + 1) + 0.01, Float(sz) + 0.5)
                    p.vel = .zero; p.flying = false
                    w.activeCenter = p.pos
                    guard let sy = surface(Float(t.x) + 0.5, Float(t.z) + 0.5, from: Float(t.y) + 3) else { continue }
                    let aimAt = V3(Float(t.x) + 0.5, sy, Float(t.z) + 0.5)
                    func face() { let d = simd_normalize(aimAt - p.eye); p.yaw = atan2f(-d.x, -d.z); p.pitch = asinf(d.y) }
                    face()
                    g.inventory.held = ItemStack(Items.id(key), 1)
                    if g.menu != nil { g.closeMenu() }                     // (a sign placed opens its writing screen)
                    g.mobs.mobs.removeAll()
                    g.input.rightClicked = false; g.input.rightDown = false
                    g.tick(1.0 / 60); face(); g.tick(1.0 / 60); face()     // (the view settles onto a turn over a tick: aim twice)
                    // (what the aim meets: the drawn ground, near the column aimed at; a slope nearer him can take it)
                    guard let tg = g.target, let gh = g.targetGround, gh.cell == tg.hit, abs(tg.hit.x - t.x) <= 1, abs(tg.hit.z - t.z) <= 1,
                          w.groundAt(tg.hit.x, tg.hit.y, tg.hit.z) else {
                        if trace { print("placeslope: no aim at \(t.x) \(t.y - YOFF) \(t.z) from \(p.eye.x) \(p.eye.y - Float(YOFF)) \(p.eye.z): menu \(g.menu == nil ? "none" : "open"), cine \(g.cine.active), target \(g.target.map { "\($0.hit.x) \($0.hit.y - YOFF) \($0.hit.z)" } ?? "none"), ground \(g.targetGround.map { "\($0.at)" } ?? "none")") }
                        continue
                    }
                    let hitAt = gh.at
                    tl.aimed += 1
                    var before: [IVec3: BlockID] = [:]
                    for y in (t.y - 2)...(t.y + 3) { for z in (t.z - 2)...(t.z + 2) { for x in (t.x - 2)...(t.x + 2) { before[IVec3(x, y, z)] = w.builtBlock(x, y, z) } } }
                    g.lastRefusal = ""
                    let eye0 = p.eye, want = g.placeCell(tg, for: Blocks.id(key))
                    let direct = w.fieldRaySegment(p.eye, p.look, from: 0, to: 6)
                    g.input.rightClicked = true; g.input.rightDown = true
                    g.tick(1.0 / 60)
                    g.input.rightClicked = false; g.input.rightDown = false
                    let tgClick = g.target
                    // (the aim the click used: the view settles a few hundredths between ticks, and at a cell's edge the
                    // target moves with it)
                    let ghClick = g.targetGround.flatMap { gc in tgClick.map { gc.cell == $0.hit } == true ? gc : nil } ?? gh
                    g.tick(1.0 / 60)
                    let base = Blocks.groupBase[Int(Blocks.id(key))]
                    let mine = before.keys.filter { c in
                        let b = w.builtBlock(c.x, c.y, c.z)
                        return b != before[c]! && b != AIR && Blocks.groupBase[Int(b)] == base
                    }
                    guard let low = mine.min(by: { $0.y < $1.y }) else {
                        tl.refused += 1
                        if tl.notes.count < 6 { tl.notes.append("refused at \(t.x) \(t.y - YOFF) \(t.z) (\(g.lastRefusal))") }
                        tally[cls] = tl; continue
                    }
                    tl.placed += 1
                    var bad: [String] = []
                    // (a) the cell the aim shows: the column the ray met the ground in, the row at the height it met it
                    let hx = Int(floor(ghClick.at.x)), hz = Int(floor(ghClick.at.z))
                    let hy = Int(floor(ghClick.at.y))
                    // (ledger 276: what stands on its floor goes over the point aimed at on ground that faces up (40
                    // degrees or less from it, as a full block always did); against steep ground, or a torch, sign, rail
                    // or plant aimed at the ground's side, the cell past the face aimed at is the aim too)
                    let rowKind = Game.takesGroundRow(Blocks.id(key), old: false) && ghClick.normal.y >= 0.5
                    let past = tgClick.map { $0.hit + $0.normal } ?? (tg.hit + tg.normal)
                    if (low.x != hx || low.z != hz || (low.y != hy && low.y != hy + 1)) && (rowKind || low != past) {
                        tl.wrongCell += 1; bad.append(String(format: "went in %d %d %d, aimed at the ground at %.2f %.2f %.2f", low.x, low.y - YOFF, low.z, ghClick.at.x, ghClick.at.y - Float(YOFF), ghClick.at.z))
                        if trace { print(String(format: "placeslope:   ground normal %.2f %.2f %.2f; target %d %d %d face %d %d %d, placeCell said %d %d %d, ray meets ground at %@, eye moved %.2f; at the click the target was %@", gh.normal.x, gh.normal.y, gh.normal.z, tg.hit.x, tg.hit.y - YOFF, tg.hit.z, tg.normal.x, tg.normal.y, tg.normal.z, want.x, want.y - YOFF, want.z, direct.map { String(format: "%.2f %.2f %.2f", $0.at.x, $0.at.y - Float(YOFF), $0.at.z) } ?? "none", simd_length(p.eye - eye0), tgClick.map { "\($0.hit.x) \($0.hit.y - YOFF) \($0.hit.z) face \($0.normal.x) \($0.normal.y) \($0.normal.z)" } ?? "none")) }
                    }
                    // (b) floats or sinks: each bottom piece (nothing of its own under it) against the drawn ground; set down
                    // on the ground's top only (one put against the side of a bank hangs off it, as a block does)
                    let onTop = (tgClick?.normal.y ?? 0) == 1 || rowKind
                    for c in mine where onTop && !mine.contains(IVec3(c.x, c.y - 1, c.z)) {
                        let b = w.builtBlock(c.x, c.y, c.z)
                        guard !Blocks.collide[Int(w.builtBlock(c.x, c.y - 1, c.z))] else { continue }   // (stood on a block)
                        let boxes = Blocks.boxes[Int(b)]
                        let y0: Float = boxes.isEmpty ? 0 : Float(boxes.map { Int($0.y0) }.min()!) / 16
                        let seat = GroundDrape.seat[Int(b)]
                        if seat == 2 { continue }                                                         // (laid on it, bent)
                        let plant = Blocks.render[Int(b)] == RenderType.cross.rawValue
                        if plant { continue }                                                             // (seated by the mesher)
                        let bottom = Float(c.y) + y0 + (seat == 1 ? w.groundSeat(c.x, c.y, c.z) : 0)
                        if World.restsOnFloor[Int(b)] {
                            let gp = w.floorGap(c.x, c.y, c.z)
                            if gp > 0.1 { tl.gap += 1; bad.append(String(format: "%@ at %d %d %d: ground %.2f under its floor", Blocks.key(b), c.x, c.y - YOFF, c.z, gp)) }
                            if World.isStation[Int(b)] {
                                let sk = w.floorSink(c.x, c.y, c.z)
                                if sk > 0.1 { tl.sink += 1; bad.append(String(format: "%@ at %d %d %d: corners sunk %.2f into the ground", Blocks.key(b), c.x, c.y - YOFF, c.z, sk)) }
                            }
                            continue
                        }
                        guard let mid = surface(Float(c.x) + 0.5, Float(c.z) + 0.5, from: Float(c.y) + 1.5) else { continue }
                        if bottom - mid > 0.2 { tl.float += 1; bad.append(String(format: "%@ at %d %d %d floats %.2f over the ground", Blocks.key(b), c.x, c.y - YOFF, c.z, bottom - mid)) }
                        if mid - bottom > 0.2 { tl.sink += 1; bad.append(String(format: "%@ at %d %d %d sunk %.2f under the ground", Blocks.key(b), c.x, c.y - YOFF, c.z, mid - bottom)) }
                    }
                    if trace || (!bad.isEmpty && tl.notes.count < 6) {
                        let line = "\(cls) at \(t.x) \(t.y - YOFF) \(t.z): " + (bad.isEmpty ? "ok" : bad.joined(separator: "; "))
                        if trace { print("placeslope: " + line) }
                        if !bad.isEmpty { tl.notes.append(line) }
                    }
                    // (taken out again, the ground left as the placing left it)
                    for c in before.keys where w.builtBlock(c.x, c.y, c.z) != before[c]! { w.setBlock(c.x, c.y, c.z, before[c]!) }
                    tally[cls] = tl
                }
            }
        }
        g.inventory.held = .empty
        check(spots >= 40, "placeslope: \(spots) sloped spots in \(regions.count) regions (want 40 or more)")
        for (cls, _) in classes {
            let t = tally[cls]!
            // (ledger 273 holds floating and sinking at 0, ledger 275 the gaps under what rests on its floor, ledger 276
            // the cell the aim shows)
            check(t.aimed >= 8 && t.placed + t.refused == t.aimed && t.refused * 4 <= t.aimed && t.float == 0 && t.sink == 0 && t.gap == 0 && t.wrongCell == 0,
                  "placeslope \(cls): \(t.placed) of \(t.aimed) placed on sloped ground (\(t.refused) refused), \(t.float) floating, \(t.sink) sunk, \(t.gap) with a gap under, \(t.wrongCell) in another cell than aimed"
                  + (t.notes.isEmpty ? "" : "; " + t.notes.prefix(4).joined(separator: "; ")))
        }
    }
}
