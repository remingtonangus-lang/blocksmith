import Foundation
import simd

// Checks for the Nov 14 evening playtest's fixes (Opus lane) that need no world of their own (questcheck suite).
enum Nov14EveningChecks {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        townSeats(check)
        facingStates(check)
        furniture(check)
        sprayedWall(g, check)
        treeCatalogue(check)
        hullChip(g, check)
        seaIce(g, check)
        farTower(g, check)
        var horses = 0, packs = 0
        for _ in 0..<4000 { if let (k, _, _) = MobManager.pickAnimal(.plains) { packs += 1; if k == .horse { horses += 1 } } }
        check(MobManager.oldHorsePacks || (packs > 0 && Float(horses) / Float(packs) < 0.06),
              "Nov 14 horses: a plains pack is horses about one time in 25 (\(horses) of \(packs)), not one in ten")
        check(Game.travelNews("Fort Red Station marked on the map") && Game.travelNews("You found the Fort & Ash Rail Road: 2 stations, marked on your map")
              && Game.travelNews("Entering Savenonia") && !Game.travelNews("Engines hit: going down") && !Game.travelNews("Intel: this base is a Radar Station"),
              "Nov 14 HUD: at the helm the map's and the borders' news waits in the journal; hits, orders and intel still show")
    }

    // Nov 14 (21:02:44, "the shot went through the Capitol Tower"): past the loaded land a Tidebreaker slug strikes the
    // far citadel drawn there (FarCitadel.solid), its tower's cells solid, the air over it and a blast hole it holds not.
    static func farTower(_ g: Game, _ check: (Bool, String) -> Void) {
        guard let st = g.world.gen.structures?.nearest("military_base", x: Int(g.player.pos.x), z: Int(g.player.pos.z), maxRegions: 16) else {
            check(false, "Nov 14 far tower: no citadel near the suite's spot"); return
        }
        let cx = (st.min.x + st.max.x) / 2, cz = (st.min.z + st.max.z) / 2, key = "citadel:\(cx),\(cz)"
        let sync0 = FarCitadel.sync
        FarCitadel.sync = true
        let m = FarCitadel.model(st, key: key, damage: [])
        FarCitadel.sync = sync0
        guard let model = m else { check(false, "Nov 14 far tower: the far citadel model was not made"); return }
        // The tallest solid column of the model (its great tower).
        var best = (n: -1, x: 0, z: 0)
        for z in 0..<model.nz { for x in 0..<model.nx {
            var top = -1
            for y in 0..<model.ny where model.grid[(y * model.nz + z) * model.nx + x] != 0 { top = y }
            if top > best.n { best = (top, x, z) }
        } }
        let F = FarCitadel.cell
        let wx = Float(model.origin.x + best.x * F) + 1, wz = Float(model.origin.z + best.z * F) + 1
        let top = Float(model.origin.y + best.n * F)
        var y = top
        while y > Float(model.origin.y) && !FarCitadel.solid(V3(wx, y, wz), g) { y -= 1 }
        let inTower = FarCitadel.solid(V3(wx, y, wz), g), overIt = FarCitadel.solid(V3(wx, top + 12, wz), g)
        let r0 = g.bases.records[key]
        var r = r0 ?? BaseRecord(key: key, cx: cx, cz: cz, y0: st.min.y + 20, lastTick: g.clock)
        r.damage.append([wx, y, wz, 6])
        g.bases.records[key] = r
        let holed = FarCitadel.solid(V3(wx, y, wz), g)
        g.bases.records[key] = r0
        check(FarCitadel.oldFarShot || (inTower && !overIt && !holed),
              String(format: "Nov 14 far tower: a far shot meets the citadel's tower at %.0f %.0f %.0f (%@), not the air 12 over it (%@), nor a blast hole there (%@)",
                     wx, y - Float(YOFF), wz, inTower ? "yes" : "no", overIt ? "solid" : "clear", holed ? "solid" : "clear"))
    }

    // Nov 14 (a cold sea: "Make it like ice panes except they're flat, not vertical"): open water freezes to a sheet two
    // sixteenths thick that is water underneath; broken, the water stays.
    static func seaIce(_ g: Game, _ check: (Bool, String) -> Void) {
        let s = Game.seaIceID, w = g.world
        guard s != AIR else { check(false, "Nov 14 ice: no sheet ice block"); return }
        let bx = Blocks.boxes[Int(s)]
        let p = IVec3(Int(floor(g.player.pos.x)) + 3, 320, Int(floor(g.player.pos.z)) + 3)
        let old = (0..<3).map { w.block(p.x, p.y - $0, p.z) }
        defer { for k in 0..<3 { w.setBlock(p.x, p.y - k, p.z, old[k]) } }
        w.setBlock(p.x, p.y - 2, p.z, STONE); w.setBlock(p.x, p.y - 1, p.z, WATER); w.setBlock(p.x, p.y, p.z, s)
        g.breakBlock(p, s, drop: true)
        let after = w.block(p.x, p.y, p.z)
        check(Game.oldIce || (Game.waterIceID == s && bx.count == 1 && bx[0].y0 == 14 && bx[0].y1 == 16 && Blocks.fluidKind[Int(s)] == 1
                              && !Blocks.opaque[Int(s)] && after == WATER),
              "Nov 14 ice: open water freezes to a flat sheet 2/16 thick over water (box y \(bx.first.map { "\($0.y0)-\($0.y1)" } ?? "none")), broken it leaves water (\(Blocks.key(after)))")
    }

    // Nov 14 ("Bullets should be doing micro damage to the hulls"): forty rifle rounds into a Salvaged Fighter's hull
    // each chip it (counted on the hull bar), no block goes; small arms alone stop at a tenth of the hull.
    static func hullChip(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let fp = w.ships.spawn(AshWrecks.salvagedFighter(), at: g.player.pos + V3(0, 8, 24), yaw: 0, name: "Chip Test", role: "capplane")
        fp.initialBlocks = fp.blockCount
        defer { w.ships.remove(fp, turrets: false) }
        let blocks0 = fp.blockCount, bar0 = CombatHUD.shared.integrity(fp), hits0 = ShipManager.chipHits
        let target = fp.pos
        let from = target + V3(-14, 0.2, 0)
        for k in 0..<40 {
            let d = simd_normalize(target + V3(0, Float(k % 3) * 0.1, 0) - from)
            g.arms.spawn(Slug(pos: from, vel: d * 150, kind: .bullet, damage: 5, fromPlayer: true, shooter: nil, by: "Player", life: 0.6, gravity: 0))
        }
        for _ in 0..<40 { g.arms.update(1.0 / 60, g) }
        let hits = ShipManager.chipHits - hits0, bar1 = CombatHUD.shared.integrity(fp)
        check(hits >= 30 && fp.blockCount == blocks0 && bar1 < bar0 && bar0 - bar1 < 0.1 && abs(fp.chip - Float(hits) * 0.05) < 0.01,
              String(format: "Nov 14 hulls: %d of 40 rifle rounds chip the fighter's hull (%.2f blocks' worth), no block lost (%d of %d), its bar %.1f%% -> %.1f%%",
                     hits, fp.chip, fp.blockCount, blocks0, bar0 * 100, bar1 * 100))
        w.ships.chip(fp, 1e7)
        check(fp.hullBlocks >= fp.initialBlocks * 9 / 10 - 1 && fp.blockCount == blocks0,
              "Nov 14 hulls: small arms alone take at most a tenth of a hull (\(fp.hullBlocks) of \(fp.initialBlocks) left after a flood of rounds)")
    }

    // 21:17 ("we should add desks to the game", "Different types of tables"): every wood with seats has a table, a round
    // table, a side table and a desk, each with a recipe; a town's desk has its knee space toward the chair (its back
    // panel away from it) for every lot facing.
    static func furniture(_ check: (Bool, String) -> Void) {
        var missing: [String] = [], woods = 0
        let made = Set(Recipes.all.map { Items.key($0.result.item) })
        for w in BlockRegistry.doorWoods where Blocks.has("\(w)_chair") {
            woods += 1
            for k in ["table", "round_table", "side_table", "desk"] where !Blocks.has("\(w)_\(k)") || !made.contains("\(w)_\(k)") { missing.append("\(w)_\(k)") }
        }
        var wrong = 0
        let worldDir = [V2(0, -1), V2(0, 1), V2(-1, 0), V2(1, 0)]
        for face in 0..<4 {
            let l = Village.Lot(kind: .office, ax: 0, az: 0, face: face, w: 7, d: 6, y: 0, seed: 1, job: "")
            guard let d = Village.LB(l: l).desk(Village.mats(.plains), front: 0) else { wrong += 1; continue }
            let panel = Blocks.boxes[Int(d)].filter { $0.y0 == 5 }
            guard let p = panel.first else { wrong += 1; continue }
            let c = V2(Float(Int(p.x0) + Int(p.x1)) / 2 - 8, Float(Int(p.z0) + Int(p.z1)) / 2 - 8)
            if simd_dot(simd_normalize(c), worldDir[Village.dir(l, 0)]) > -0.9 { wrong += 1 }
        }
        check(missing.isEmpty && woods > 5 && wrong == 0,
              "Nov 14 furniture: \(woods) woods each have a table, round table, side table and desk with recipes (\(missing.count) missing\(missing.isEmpty ? "" : ": " + missing.prefix(4).joined(separator: ", "))); a town desk faces its chair for every lot facing (\(wrong) wrong)")
    }

    // 20:49:21 ("I can't break through that?"): a magazine of carbine rounds sprayed over the middle of a wall of Dark
    // Station Concrete (each round somewhere in its 3x3 middle) breaks through it; before, the wear spread over the
    // cells broke few or none.
    static func sprayedWall(_ g: Game, _ check: (Bool, String) -> Void) {
        func spray(splash: Bool) -> Int {
            let w = g.world
            let p0 = g.player.pos
            let c = IVec3(Int(floor(p0.x)) + 20, 300, Int(floor(p0.z)) + 20)
            let con = Blocks.id("bunker_concrete_dark")
            var cells: [IVec3] = []
            for dy in -2...2 { for dx in -2...2 { let q = IVec3(c.x + dx, c.y + dy, c.z); w.setBlock(q.x, q.y, q.z, con); cells.append(q) } }
            let splash0 = BlockWear.splash
            BlockWear.splash = splash
            defer { for q in cells { w.setBlock(q.x, q.y, q.z, AIR) }; BlockWear.marks = [:]; BlockWear.splash = splash0 }
            BlockWear.marks = [:]
            let from = V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 6.5)
            var rng = SRng(77)
            for _ in 0..<30 {
                let tx = Float(c.x) + 0.5 + Float(rng.int(3) - 1) + Float(rng.int(100)) / 100 - 0.5
                let ty = Float(c.y) + 0.5 + Float(rng.int(3) - 1) + Float(rng.int(100)) / 100 - 0.5
                let d = simd_normalize(V3(tx, ty, Float(c.z) + 1) - from)
                g.arms.spawn(Slug(pos: from, vel: d * 150, kind: .bullet, damage: 5.5, fromPlayer: true, shooter: nil, by: "Player", life: 0.6, gravity: 0))
                for _ in 0..<3 { g.arms.update(1.0 / 60, g) }
            }
            return cells.filter { w.block($0.x, $0.y, $0.z) == AIR }.count
        }
        let old = spray(splash: false), now = spray(splash: true)
        check(BlockWear.oldSplash || (now >= 2 && now > old && now <= 14),
              "Nov 14 concrete: 30 carbine rounds sprayed over a concrete wall's middle break \(now) of its 25 blocks, a hole through it (\(old) with each round's wear on its own cell only)")
    }

    // The chair's class: every block with four facings has them in a row (state k = its plain state + k), as placing,
    // sitting and building count on; the seats were interleaved chair, bench, chair[south], bench[south]...
    static func facingStates(_ check: (Bool, String) -> Void) {
        var groups = 0, wrong: [String] = []
        for i in 0..<Blocks.count where Blocks.groupBase[i] == BlockID(i) {
            let k = Blocks.key(BlockID(i))
            guard Blocks.has(k + "[south]"), Blocks.shape[i].isEmpty else { continue }      // (as placing turns them: Game.useItem)
            groups += 1
            for (f, d) in ["south", "west", "east"].enumerated() where Blocks.has("\(k)[\(d)]") {
                if Blocks.id("\(k)[\(d)]") != BlockID(i + f + 1) { wrong.append("\(k)[\(d)]"); break }
            }
        }
        check(wrong.isEmpty && groups > 20, "Nov 14 chair (the class): every four-facing block's facings follow its plain state in order (\(groups) blocks, \(wrong.count) out of order\(wrong.isEmpty ? "" : ": " + wrong.prefix(4).joined(separator: ", ")))")
    }

    // Nov 15 (Fable's list, 1): the tree catalogue holds exactly 100 designs, names and ids unique, every log joined to
    // the foot, every limb tip in leaves, nothing low off the trunk or past the placement margin.
    static func treeCatalogue(_ check: (Bool, String) -> Void) {
        let bad = TreeShapes.catalogueProblems()
        check(bad.isEmpty && TreeShapes.catalogue.count == 100,
              "Nov 15 trees: the catalogue holds \(TreeShapes.catalogue.count) designs (want 100) in \(TreeShapes.all.count) species, \(bad.count) problems\(bad.isEmpty ? "" : ": " + bad.prefix(4).joined(separator: "; "))")
    }

    // 21:17, Elk Hollow's sheriff's office: "This chair's not facing the right way". Every town seat asked for with its
    // back toward a local direction is a chair (not a bench) whose back slats stand on that side, for every lot facing
    // and every wood.
    static func townSeats(_ check: (Bool, String) -> Void) {
        var wrong: [String] = [], tried = 0
        let worldDir = [V2(0, -1), V2(0, 1), V2(-1, 0), V2(1, 0)]       // 0 north, 1 south, 2 west, 3 east
        for style in [Village.Style.plains, .desert, .savanna, .taiga, .snowy] {
            let m = Village.mats(style)
            for face in 0..<4 { for local in 0..<4 {
                let l = Village.Lot(kind: .office, ax: 0, az: 0, face: face, w: 7, d: 6, y: 0, seed: 1, job: "")
                let id = Village.LB(l: l).seat(m, "chair", back: local)
                tried += 1
                let key = Blocks.key(Blocks.groupBase[Int(id)])
                guard key.hasSuffix("_chair") else { wrong.append("\(style) face \(face) back \(local): \(Blocks.name(id))"); continue }
                // The back slats: the boxes above the seat (y 10...16), their middle against the block's middle.
                let back = Blocks.boxes[Int(id)].filter { $0.y0 >= 10 }
                guard !back.isEmpty else { wrong.append("\(key): no back"); continue }
                var c = V2(0, 0)
                for b in back { c += V2(Float(Int(b.x0) + Int(b.x1)) / 2 - 8, Float(Int(b.z0) + Int(b.z1)) / 2 - 8) }
                c /= Float(back.count)
                let want = worldDir[Village.dir(l, local)]
                if simd_dot(simd_normalize(c), want) < 0.9 { wrong.append("\(style) face \(face) back \(local): slats toward \(c)") }
            } }
        }
        check(wrong.isEmpty && tried == 80,
              "Nov 14 chair: every town chair (5 woods x 4 lot facings x 4 sides) is a chair with its back where it was asked for (\(wrong.count) wrong of \(tried)\(wrong.isEmpty ? "" : ": " + wrong.prefix(3).joined(separator: "; ")))")
    }
}
