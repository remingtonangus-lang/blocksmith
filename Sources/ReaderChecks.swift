import Foundation
import simd

// The code reader's Nov 10 batch (freezes and stalls), measured: questcheck --reader. Each case runs the new way and,
// with its BS_OLD... toggle, the old way (the harness runs it twice). 1 (a crewman's backwards deck range) is
// CrewLookout.check, in the full suite; 4 (a Hollow rift loading on the frame) is in --triptest.
enum ReaderChecks {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        helm(g, check)
        tnt(g, check)
        taken(g, check)
    }

    // Batch 3.4: a crawler he took, a hole knocked in her and a diamond left in one of her chests, saved and built again
    // the way a reload builds her (Capital.restoreTaken): the hole and the diamond are still there, and the chest
    // isn't refilled.
    static func taken(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, ships = w.ships
        let at = IVec3(Int(floor(g.player.pos.x)) + 600, 0, Int(floor(g.player.pos.z)))
        _ = w.loadSync(center: V3(Float(at.x), 100, Float(at.z)), radius: 2)
        let before = Set(ships.capitals.map { $0.id })
        ships.spawnCapital("crawler", home: IVec3(at.x, w.topY(at.x, at.z) + 1, at.z), yaw: 0, region: nil, sync: true)
        guard let s = ships.capitals.first(where: { !before.contains($0.id) }) else { check(false, "reader taken: a crawler was built"); return }
        s.captured = true
        // the hole: the first solid cell on the grid's middle column from the top
        let gr = s.grid
        var hole: IVec3?
        for y in stride(from: gr.sy - 1, through: 0, by: -1) where gr.get(gr.sx / 2, y, gr.sz / 2) != AIR { hole = IVec3(gr.sx / 2, y, gr.sz / 2); break }
        if let h = hole { gr.set(h.x, h.y, h.z, AIR) }
        let chest = s.blockEntities.keys.sorted { ($0.y, $0.z, $0.x) < ($1.y, $1.z, $1.x) }.first
        let diamond = Items.id("diamond")
        if let c = chest, let be = s.blockEntities[c] {
            for i in 0..<be.container.count { be.container.slots[i] = .empty }
            be.container.slots[0] = ItemStack(diamond, 1)
        }
        ships.save(background: false)
        guard let dir = w.save?.dir, let d = try? Data(contentsOf: dir.appendingPathComponent("takencaps.json")),
              let caps = try? JSONDecoder().decode([ShipManager.TakenCap].self, from: d),
              let c = caps.first(where: { $0.name == s.name && $0.kind == "crawler" }) else {
            check(false, "reader taken: the taken crawler is in the save"); return
        }
        ships.remove(s)
        let before2 = Set(ships.capitals.map { $0.id })
        let p = V3(c.pos[0], c.pos[1], c.pos[2])
        ships.spawnCapital(c.kind, home: IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))), yaw: 0, region: nil, sync: true,
                           faction: Faction(rawValue: c.faction), taken: (p, Quat(vector: V4(c.rot[0], c.rot[1], c.rot[2], c.rot[3])), c.name),
                           takenSave: c)
        guard let r = ships.capitals.first(where: { !before2.contains($0.id) }) else { check(false, "reader taken: she was built again"); return }
        let holeKept = hole.map { r.grid.get($0.x, $0.y, $0.z) == AIR } ?? false
        var chestItems: [String] = []
        if let c = chest, let be = r.blockEntities[c] {
            for st in be.container.slots where !st.isEmpty { chestItems.append("\(Items.key(st.item)) x\(st.count)") }
        }
        let kept = chestItems == ["diamond x1"]
        print("reader: taken crawler after a reload (\(ShipManager.oldTakenGrid ? "BS_OLDTAKENGRID" : "new")): hole \(holeKept ? "still there" : "filled in"), chest \(chestItems.isEmpty ? "empty" : chestItems.joined(separator: ", "))")
        check(ShipManager.oldTakenGrid || holeKept && kept,
              "reader taken: a taken crawler keeps the hole knocked in her (\(holeKept)) and what he left in her chest (\(chestItems))")
        ships.remove(r)
    }

    // 3: a helm set on a building over the move limit: how long "Too big to move" takes on the frame.
    static func helm(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let c = IVec3(Int(floor(g.player.pos.x)) + 400, 0, Int(floor(g.player.pos.z)) + 400)
        _ = w.loadSync(center: V3(Float(c.x), 100, Float(c.z)), radius: 3)
        let y0 = w.topY(c.x, c.z) + 1
        let brick = Blocks.id("stone_bricks")
        // 48 x 28 x 48 = 64,512 blocks: past the 60,000 a vehicle may have.
        w.editBatch {
            for y in 0..<28 { for z in -24..<24 { for x in -24..<24 { w.setBlock(c.x + x, y0 + y, c.z + z, brick) } } }
        }
        let h = IVec3(c.x, y0 + 28, c.z)
        w.setBlock(h.x, h.y, h.z, Blocks.id("ship_helm"))
        var placed = 0
        for y in 0..<28 { for z in -24..<24 { for x in -24..<24 where w.rawBlock(c.x + x, y0 + y, c.z + z) == brick { placed += 1 } } }
        print("reader: helm building: \(placed) of 64512 bricks in place (id \(brick)), under the helm \(Blocks.key(w.rawBlock(h.x, h.y - 1, h.z))), helm \(Blocks.key(w.rawBlock(h.x, h.y, h.z)))")
        var worst = 0.0
        var said = ""
        for _ in 0..<3 {
            let t0 = CFAbsoluteTimeGetCurrent()
            let (s, msg) = w.ships.assemble(at: h, game: nil)
            worst = max(worst, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
            said = s == nil ? msg : "it moved"
        }
        print(String(format: "reader: helm on a 64,512-block building (%@): %.0f ms a try, worst of 3 (%@)",
                     ShipManager.oldAssemble ? "BS_OLDASSEMBLE" : "new", worst, said))
        check(said.hasPrefix("Too big") && (ShipManager.oldAssemble || worst < 250),
              String(format: "reader helm: a helm on a building past the limit says \"Too big to move\" in %.0f ms (%@)", worst, said))
        w.editBatch {
            for y in 0...28 { for z in -24..<24 { for x in -24..<24 { w.setBlock(c.x + x, y0 + y, c.z + z, AIR) } } }
        }
    }

    // 2: a 10 x 10 x 5 stack of TNT lit at one corner: the slowest frames while it goes off.
    static func tnt(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let c = IVec3(Int(floor(g.player.pos.x)) - 400, 0, Int(floor(g.player.pos.z)) + 400)
        _ = w.loadSync(center: V3(Float(c.x), 100, Float(c.z)), radius: 3)
        let y0 = w.topY(c.x, c.z) + 1
        let tnt = Blocks.id("tnt")
        w.editBatch {
            for y in 0..<5 { for z in 0..<10 { for x in 0..<10 { w.setBlock(c.x + x, y0 + y, c.z + z, tnt) } } }
        }
        let pos0 = g.player.pos, surv0 = g.survival
        defer { g.player.pos = pos0; g.survival = surv0 }
        g.survival = false
        g.player.pos = V3(Float(c.x) - 40, Float(y0 + 20), Float(c.z) + 5)
        g.player.flying = true
        w.setBlock(c.x, y0, c.z, AIR)
        g.tnts.prime(at: IVec3(c.x, y0, c.z), fuse: 0.1)
        TNTManager.deferred = 0
        var worst = 0.0, over = 0, frames = 0, worstAt = 0, worstWhat = ""
        var t: Float = 0
        while t < 12 && (frames < 20 || !g.tnts.list.isEmpty) {
            g.menu = nil; g.alive = true; g.health = 20
            let a = CFAbsoluteTimeGetCurrent()
            g.tick(1.0 / 72)
            let ms = (CFAbsoluteTimeGetCurrent() - a) * 1000
            if ms > worst { worst = ms; worstAt = frames; worstWhat = TickProf.summary() }
            if ms > 13.9 { over += 1 }
            frames += 1; t += 1.0 / 72
        }
        var left = 0
        for y in 0..<5 { for z in 0..<10 { for x in 0..<10 where w.block(c.x + x, y0 + y, c.z + z) == tnt { left += 1 } } }
        print(String(format: "reader: 500 TNT lit (%@): %d frames, worst tick %.0f ms (frame %d, slowest stage %@), %d over 13.9 ms, %d blasts moved to a later frame, %d TNT left, %.1f s",
                     TNTManager.oldAll ? "BS_OLDTNT" : "new", frames, worst, worstAt, worstWhat, over, TNTManager.deferred, left, Double(t)))
        check(g.tnts.list.isEmpty && left < 50,
              String(format: "reader tnt: a 500-block stack goes off (%d left) and the worst frame is %.0f ms", left, worst))
    }
}
