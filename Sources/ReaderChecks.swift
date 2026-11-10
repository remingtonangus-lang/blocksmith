import Foundation
import simd

// The code reader's Nov 10 batch (freezes and stalls), measured: questcheck --reader. Each case runs the new way and,
// with its BS_OLD... toggle, the old way (the harness runs it twice). 1 (a crewman's backwards deck range) is
// CrewLookout.check, in the full suite; 4 (a Hollow rift loading on the frame) is in --triptest.
enum ReaderChecks {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        helm(g, check)
        tnt(g, check)
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
        var worst = 0.0, over = 0, frames = 0
        var t: Float = 0
        while t < 12 && (frames < 20 || !g.tnts.list.isEmpty) {
            g.menu = nil; g.alive = true; g.health = 20
            let a = CFAbsoluteTimeGetCurrent()
            g.tick(1.0 / 72)
            let ms = (CFAbsoluteTimeGetCurrent() - a) * 1000
            worst = max(worst, ms); if ms > 13.9 { over += 1 }
            frames += 1; t += 1.0 / 72
        }
        var left = 0
        for y in 0..<5 { for z in 0..<10 { for x in 0..<10 where w.block(c.x + x, y0 + y, c.z + z) == tnt { left += 1 } } }
        print(String(format: "reader: 500 TNT lit (%@): %d frames, worst tick %.0f ms, %d over 13.9 ms, %d blasts moved to a later frame, %d TNT left, %.1f s",
                     TNTManager.oldAll ? "BS_OLDTNT" : "new", frames, worst, over, TNTManager.deferred, left, Double(t)))
        check(g.tnts.list.isEmpty && left < 50,
              String(format: "reader tnt: a 500-block stack goes off (%d left) and the worst frame is %.0f ms", left, worst))
    }
}
