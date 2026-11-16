import Foundation
import simd

// Ledger 213 (Fable's C, the boathouse's posts): a log aimed down through shallow water at a lake bed goes into the
// water cell on the bed, as anywhere off the water; it went into the dry cell over the water (or sank into the bed),
// because the placing row (ledger 131) took a wet cell for a full one. Both ways run here (BS_OLDWETROW=1: before).
extension Nov15EveningChecks {
    static func wetRow(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        let old0 = Game.oldWetRow
        defer { FieldTerrain.newWorlds = field0; Game.oldWetRow = old0 }
        let w = World(seed: BuildersGrounds.seed, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 2; w.activeDistance = 2
        let g = Game(world: w, save: nil, persistent: false)
        g.survival = false
        let s = g.findSpawn()
        let log = Blocks.id("spruce_log")
        // He hovers 2 over the water, a little to the side, and looks down at the bed's middle: the cell the log would
        // go in, and where the drawn bed is in its cell.
        func cell(_ x: Int, _ z: Int, _ bed: Int, _ top: Int) -> (IVec3?, Float, String) {
            g.player.pos = V3(Float(x) + 0.5, Float(top + 3), Float(z) + 2.2)
            g.player.flying = true
            let aim = V3(Float(x) + 0.5, Float(bed) + 0.9, Float(z) + 0.5)
            let dv = aim - g.player.eye
            g.player.yaw = atan2f(-dv.x, -dv.z); g.player.pitch = atan2f(dv.y, simd_length(V2(dv.x, dv.z)))
            guard let t = w.raycast(g.player.eye, g.player.look, maxDist: 8) else { return (nil, 0, "no aim") }
            g.target = t
            g.aimGround()
            guard let tt = g.target else { return (nil, 0, "no aim after the ground's choice") }
            let c = g.placeCell(tt, for: log)
            let frac = (g.targetGround?.at.y ?? Float(bed)) - Float(bed)
            return (c, frac, "\(c.y - bed) over the bed (\(Blocks.key(w.block(c.x, c.y, c.z))))")
        }
        // Water 2 to 5 deep, nearest the spawn (read from the generator first), where the drawn bed fills more than
        // half of its cell (a thinner one takes the log into the bed by ledger 131's rule, wet or dry).
        var spot: (Int, Int, Int, Int)?
        var tried = 0
        search: for r in stride(from: 0, through: 600, by: 8) {
            for dz in stride(from: -r, through: r, by: 8) { for dx in stride(from: -r, through: r, by: 8) where max(abs(dx), abs(dz)) == r {
                let x = Int(s.x) + dx, z = Int(s.z) + dz
                let h = w.gen.column(x, z).height
                guard h <= SEA - 3 && h >= SEA - 6 else { continue }
                _ = w.loadSync(center: V3(Float(x), 100, Float(z)), radius: 1)
                let bed = BuildersGrounds.groundY(w, x, z)
                guard Blocks.isLiquid(w.block(x, bed + 1, z)), Blocks.isLiquid(w.block(x, bed + 2, z)) else { continue }
                var top = bed + 1
                while Blocks.isLiquid(w.block(x, top + 1, z)) { top += 1 }
                tried += 1
                Game.oldWetRow = false
                let (_, frac, _) = cell(x, z, bed, top)
                if frac >= 0.55 && frac < 1 { spot = (x, z, bed, top); break search }
                if tried > 60 { break search }
            } }
        }
        guard let (x, z, bed, top) = spot else { check(false, "Ledger 213 wet row: no shallow water within 600 of the spawn with a bed drawn over half its cell (\(tried) tried)"); return }
        func probe() -> (IVec3?, String) { let r = cell(x, z, bed, top); return (r.0, r.2) }
        Game.oldWetRow = true
        let (c0, before) = probe()
        Game.oldWetRow = false
        let (c1, after) = probe()
        let want = IVec3(x, bed + 1, z)
        check(c1 == want && c0 != want,
              "Ledger 213 wet row: a log aimed down through \(top - bed) of water at a lake bed (\(x), \(bed - YOFF), \(z)): before (BS_OLDWETROW) it went \(before), now \(after)")
    }
}
