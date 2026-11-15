import Foundation
import simd

// Checks for the Nov 14 evening playtest's fixes (Opus lane) that need no world of their own (questcheck suite).
enum Nov14EveningChecks {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        townSeats(check)
        facingStates(check)
        furniture(check)
        treeCatalogue(check)
        hullChip(g, check)
        check(Game.travelNews("Fort Red Station marked on the map") && Game.travelNews("You found the Fort & Ash Rail Road: 2 stations, marked on your map")
              && Game.travelNews("Entering Savenonia") && !Game.travelNews("Engines hit: going down") && !Game.travelNews("Intel: this base is a Radar Station"),
              "Nov 14 HUD: at the helm the map's and the borders' news waits in the journal; hits, orders and intel still show")
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
