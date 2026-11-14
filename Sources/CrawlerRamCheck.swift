import Foundation
import simd

// Ledger 124 (Nov 14: "one block of ground damage... consistent with our physics engine... a frigate crashing into a
// small building obliterated the building and damages the frigate a little"). `questcheck --crawlerram`: a crawler
// driven at 12 blocks a second through a stone-brick hut standing in its way. The hut is broken through, the crawler
// pays for it in plate (a few, not a hull) and in speed for the moment, and its wheels dig nothing out of the ground.
enum CrawlerRamCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, ships = w.ships
        let at = IVec3(Int(floor(g.player.pos.x)) + 700, 0, Int(floor(g.player.pos.z)) + 300)
        _ = w.loadSync(center: V3(Float(at.x), 100, Float(at.z)), radius: 5)
        let before = Set(ships.capitals.map { $0.id })
        ships.spawnCapital("crawler", home: IVec3(at.x, w.topY(at.x, at.z) + 1, at.z), yaw: 0, region: nil, sync: true)
        guard let s = ships.capitals.first(where: { !before.contains($0.id) }), let st = ships.capState[s.id] else {
            check(false, "crawlerram: a crawler was built"); return
        }
        defer { ships.remove(s) }
        // A hut of stone bricks across its bow, 10 blocks ahead: 9 wide, 6 high, 7 deep, walls one block thick, a roof.
        let fwd3 = s.dirToWorld(V3(0, 0, -1))
        let fwd = simd_normalize(V3(fwd3.x, 0, fwd3.z))
        let side = V3(-fwd.z, 0, fwd.x)
        let bow = s.toWorld(V3((s.localMin.x + s.localMax.x) * 0.5, s.localMin.y, s.localMin.z))
        let brick = Blocks.id("stone_bricks")
        var hut: [IVec3] = []
        var feet: [SIMD2<Int>: Int] = [:]
        for d in 10...16 { for a in -4...4 { for h in 0...5 {
            guard d == 10 || d == 16 || abs(a) == 4 || h == 5 else { continue }
            let p = bow + fwd * Float(d) + side * Float(a)
            let x = Int(floor(p.x)), z = Int(floor(p.z))
            let top = feet[SIMD2(x, z)] ?? w.topY(x, z)       // (the ground there before any brick stood on it)
            feet[SIMD2(x, z)] = top
            let c = IVec3(x, top + 1 + h, z)
            hut.append(c)
        } } }
        // (set from the ground up, a column at a time, so each stands on the one under it)
        var placed = Set<IVec3>()
        for c in hut.sorted(by: { $0.y < $1.y }) where placed.insert(c).inserted { w.setBlock(c.x, c.y, c.z, brick) }
        let stood = placed.filter { w.block($0.x, $0.y, $0.z) == brick }.count
        let hull0 = s.blockCount
        let from = s.pos
        let dug0 = ShipManager.rutDug, rammed0 = ShipManager.crawlerRammed, torn0 = ShipManager.crawlerTorn
        st.testTurn = 0; st.testSpeed = 12
        var slowest = Float.infinity, t: Float = 0
        while t < 7 {
            ships.update(1.0 / 60, game: g)
            if t > 1 { slowest = min(slowest, simd_length(V2(s.vel.x, s.vel.z))) }
            t += 1.0 / 60
        }
        st.testTurn = nil; st.testSpeed = nil
        let left = placed.filter { w.block($0.x, $0.y, $0.z) == brick }.count
        let drove = simd_length(V2(s.pos.x - from.x, s.pos.z - from.z))
        let rammed = ShipManager.crawlerRammed - rammed0, torn = ShipManager.crawlerTorn - torn0
        let lost = hull0 - s.blockCount
        check(stood > 100 && drove > 30 && rammed >= 20 && torn >= 1 && lost >= 1 && lost <= 30 && slowest < 11.5 && ShipManager.rutDug == dug0,
              String(format: "crawlerram: through a stone-brick hut of %d blocks at 12 blocks a second: %d left standing in its way of %d its bow met, "
                     + "the crawler paid %d plates (%d of its %d blocks gone), slowed to %.1f, drove %.0f blocks; its wheels dug %d cells out of the ground",
                     stood, left, rammed, torn, lost, hull0, slowest, drove, ShipManager.rutDug - dug0))
    }
}
