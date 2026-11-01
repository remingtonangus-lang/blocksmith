import Foundation
import simd

// P507 (Nov 1 12:19:00-12:19:38 at a Fuel Depot: "we got fuel leaking out every single corner of [the] container... it's
// not flowing out like it should"): questcheck --depotleak finds a Greywall base's Fuel Depot, loads it, runs the
// fluids for a minute and counts the fuel outside its three storage tanks (none should get out of a whole tank), and
// the tanks' fuel still in them.
enum DepotLeakCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        guard g.dim.dim == .overworld, let gen = w.gen as? WorldGen, let sc = gen.structures,
              let gt = sc.types.first(where: { $0.name == Greywall.kind }) else { check(false, "depotleak: needs the overworld's structures"); return }
        let px = Int(floor(g.player.pos.x)), pz = Int(floor(g.player.pos.z))
        let rx0 = floorDiv(px, Greywall.spacing * CS), rz0 = floorDiv(pz, Greywall.spacing * CS)
        var found: Depots.Site?
        search: for r in 0...8 { for rz in (rz0 - r)...(rz0 + r) { for rx in (rx0 - r)...(rx0 + r) where max(abs(rx - rx0), abs(rz - rz0)) == r {
            guard let base = sc.start(gt, regionX: rx, regionZ: rz), let s = Depots.site(gen, sc, base), s.fuel else { continue }
            found = s; break search
        } } }
        guard let s = found else { check(false, "depotleak: a Fuel Depot within eight regions"); return }
        let mid = V3(Float(s.x0 + s.x1) / 2, Float(s.S + 6), Float(s.z0 + s.z1) / 2)
        let home = g.player.pos, active0 = w.activeCenter
        defer { g.player.pos = home; w.activeCenter = active0 }
        g.player.pos = mid; w.activeCenter = mid
        _ = w.loadSync(center: mid, radius: 4)
        func fuelCount() -> (inTanks: Int, out: Int, at: [String]) {
            var inT = 0, out = 0, at: [String] = []
            for z in (s.z0 - 4)...(s.z1 + 4) { for x in (s.x0 - 4)...(s.x1 + 4) { for y in s.S...(s.S + 14) {
                guard Blocks.fluidKind[Int(w.builtBlock(x, y, z))] == 3 else { continue }
                // In a tank: within 5.2 of one of the three tanks' axes (local a 8, b 8 / 21 / 34).
                let a = s.side > 0 ? x - s.x0 : s.x1 - x, b = z - s.z0
                let inside = [8, 21, 34].contains { tb in
                    let d = (Float(a - 8) * Float(a - 8) + Float(b - tb) * Float(b - tb)).squareRoot()
                    return d <= 5.2
                }
                if inside { inT += 1 } else { out += 1; if at.count < 4 { at.append("\(a),\(y - s.S),\(b)") } }
            } } }
            return (inT, out, at)
        }
        let before = fuelCount()
        // (every fuel cell looked at, as if it had just changed: a hole anywhere in a tank shows)
        for z in (s.z0 - 4)...(s.z1 + 4) { for x in (s.x0 - 4)...(s.x1 + 4) { for y in s.S...(s.S + 14)
            where Blocks.fluidKind[Int(w.builtBlock(x, y, z))] == 3 { w.scheduleFluid(around: IVec3(x, y, z)) } } }
        for _ in 0..<300 { w.fluidTick() }
        let after = fuelCount()
        check(before.inTanks > 300 && after.out == 0 && after.inTanks >= before.inTanks - 4,
              "depotleak: a Fuel Depot at \(s.x0) \(s.z0) holds its fuel (\(before.inTanks) cells in its tanks; after a minute of fluids \(after.inTanks) in them and \(after.out) outside"
              + (after.at.isEmpty ? ")" : ": at a,y,b " + after.at.joined(separator: "; ") + ")"))
    }
}
