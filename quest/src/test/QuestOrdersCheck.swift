import Foundation
import simd
import Metal

// P456 (Oct 25 14:02-14:03, New World (4): intercepted orders read at -2686 5980 sent him 1,128 m north to grid -26xx
// 48xx, "the orders were not accurate. There's nothing here"; "there should also be different types of orders"). Reads
// orders at his spot and at a ring of other spots and checks that each points at a place really built there (its
// blocks in the loaded world round the mark), and that they come in more kinds than the Capital's bases.
//   questcheck --orderscheck
enum QuestOrdersCheck {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        TextureGen.registerAll()
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "ok  " : "FAIL") orderscheck: \(what)"); if !ok { fails += 1 } }

        let w = World(seed: 4797859299361840175, device: sharedSystemDevice, save: nil)
        FieldTerrain.newWorlds = true; w.makeFieldWorld()
        w.renderDistance = 4
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true
        SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.menu = nil
        g.player.flying = true
        guard let sc = w.gen.structures else { print("orderscheck: no structures"); return 1 }

        // His citadel: every start near his spot, where the old orders put the mark and what is built there.
        let home = V3(-2686.2, 77.5 + Float(YOFF), 5980.1)
        if let t = sc.types.first(where: { $0.name == "military_base" }) {
            let rx = floorDiv(floorDiv(Int(home.x), CS), t.spacing), rz = floorDiv(floorDiv(Int(home.z), CS), t.spacing)
            for dz in -3...3 { for dx in -3...3 {
                guard let s = sc.start(t, regionX: rx + dx, regionZ: rz + dz) else { continue }
                let old = IVec3((s.min.x + s.max.x) / 2, 0, (s.min.z + s.max.z) / 2), c = sc.siteCentre(s)
                print("orderscheck: citadel start anchor \(s.anchor.x) \(s.anchor.y) \(s.anchor.z), bounds \(s.min.x)..\(s.max.x) x \(s.min.z)..\(s.max.z), \(s.pieces.count) pieces; old mark \(old.x) \(old.z) (lays \(sc.builds(s, at: old))), site \(c.x) \(c.z) (lays \(sc.builds(s, at: c)))")
            } }
        }

        // What is built round a mark in the loaded world: blocks that are neither ground, trees nor plants.
        func built(_ x: Int, _ z: Int) -> Int {
            _ = w.loadSync(center: V3(Float(x), 100, Float(z)), radius: 2)
            var n = 0
            for zz in stride(from: z - 24, through: z + 24, by: 2) { for xx in stride(from: x - 24, through: x + 24, by: 2) {
                for y in 1..<(CH - 1) {
                    let b = w.builtBlock(xx, y, zz)
                    if b == AIR || SmoothTerrain.natural[Int(b)] || CapitalBase.isLog(b) || CapitalBase.isLeaf(b) || Blocks.replaceable[Int(b)] || Blocks.isLiquid(b) { continue }
                    n += 1
                }
            } }
            return n
        }

        var kinds = Set<String>()
        let spots: [V3] = [home] + (0..<7).map { i in
            let a = Float(i) * 2 * .pi / 7
            return home + V3(cosf(a) * 1500, 0, sinf(a) * 1500)
        }
        for (i, p) in spots.enumerated() {
            g.player.pos = p
            if i == 1 { MapCache.shared.discover(g, kind: "military_base", x: 0, z: 0, silent: true) }   // (past the first orders)
            let skipped0 = Game.ordersSkipped
            guard let ot = g.ordersTarget() else { check(false, "orders read at \(Int(p.x)) \(Int(p.z)) point somewhere"); continue }
            let (t, text) = ot
            let n = built(t.x, t.z)
            kinds.insert(t.kind)
            let d = Int(simd_length(V2(Float(t.x) - p.x, Float(t.z) - p.z)))
            check(n > 150, "orders read at \(Int(p.x)) \(Int(p.z)): \"\(text)\" at \(t.x) \(t.z), \(d) blocks off; \(n) built blocks round the mark (\(Game.ordersSkipped - skipped0) passed over)")
            print("orderscheck:   \(g.ordersPages(t)[0].replacingOccurrences(of: "\n", with: " / "))")
        }
        check(kinds.count >= 3, "orders come in \(kinds.count) kinds (\(kinds.sorted().joined(separator: ", ")))")
        print(fails == 0 ? "orderscheck: all passed" : "orderscheck: \(fails) failed")
        return fails == 0 ? 0 : 1
    }
}
