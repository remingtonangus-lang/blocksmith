import Foundation
import simd

// Oct 14 midday playtest items (docs/roadmap/backlog.md P250-P265); questcheck `--oct14-only [P2xx]`. `render` draws
// a frame from a point (the Quest renderer, next to `--render`'s PNG) when the harness has one.
enum PlaytestOct14Tests {
    static func run(_ g: Game, only: String?, render: ((String, V3, Float, Float) -> Void)?, check: (Bool, String) -> Void) {
        func on(_ id: String) -> Bool { only == nil || only == id }
        if on("P250") { p250(g, check: check) }
    }

    // P250: (a) the render distance the player sets holds unless frames really suffer and comes back when they stop;
    // (b) woods past the chunks stand as their canopy in leaf colours; (c) so the skyline carries on at the seam.
    static func p250(_ g: Game, check: (Bool, String) -> Void) {
        check(RenderDistanceGovernorTest.run() == 0, "P250 (a): the governor keeps 24 through a loading burst, drops on a real slump and climbs back to 24")
        guard let gen = g.world.gen as? WorldGen else { check(false, "P250: an overworld"); return }
        // A forest column and a plains column from the generator, then their middle-ring samples.
        var forest: (Int, Int)?, plains: (Int, Int)?
        search: for r in stride(from: 0, through: 4000, by: 64) { for a in 0..<16 {
            let t = Float(a) * .pi / 8
            let x = Int(cosf(t) * Float(r)), z = Int(sinf(t) * Float(r))
            let k = gen.columnData(x, z), b = gen.terrain.biome(k, k.h)
            if forest == nil && (b == .forest || b == .darkForest) && FarRing.canopy(gen, b, x, z, ground: k.h).cover > 0.4 { forest = (x, z) }
            if plains == nil && b == .plains && k.wl < k.h { plains = (x, z) }
            if forest != nil && plains != nil { break search }
        } }
        guard let f = forest, let p = plains else { check(false, "P250 (b): a forest and a plains column within 4000 blocks"); return }
        let fs = FarRing.sample(gen, f.0, f.1), ps = FarRing.sample(gen, p.0, p.1)
        let fk = gen.columnData(f.0, f.1), pk = gen.columnData(p.0, p.1)
        let fUp = fs.y - (Float(YOFF) + fk.h + 1), pUp = ps.y - (Float(YOFF) + pk.h + 1)
        let green = fs.c.y / max(0.01, (fs.c.x + fs.c.y + fs.c.z) / 3)
        check(fUp > 4 && pUp < 0.5, String(format: "P250 (b, c): a forest far off stands %.1f blocks over its ground as canopy (open plains %.1f)", fUp, pUp))
        check(fs.c.y < ps.c.y && green > 1.05, String(format: "P250 (b): in leaf colours, darker than the plains' grass (green %.2f vs %.2f)", fs.c.y, ps.c.y))
    }





}
