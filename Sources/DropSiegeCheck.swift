import Foundation
import simd

// Ledger 206: questcheck --dropsiege. Five minutes of a siege at the citadel nearest the spawn, as his Nov 15 21:09 one
// went: he stands off 110 blocks; a blast in the plaza every 40 s (lockdown, reinforcements) and a heavy blast 100 out
// every 25 s (his crawler's shells: the far-noise call). Every dropship that comes within 500 blocks is followed from
// the moment it is first seen: there are at most two, each first seen standing on a pad (none built in the air), and
// at least one flies. The suite runs it as its own process.
enum DropSiegeCheck {
    static func run(_ g: Game) -> Int32 {
        let w = g.world
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "PASS" : "FAIL") drop \(what)"); fflush(stdout); if !ok { fails += 1 } }
        guard let sc = w.gen.structures,
              let s = sc.nearest("military_base", x: Int(g.player.pos.x), z: Int(g.player.pos.z), maxRegions: 6) else {
            check(false, "no citadel within 6 regions of the spawn"); return 1
        }
        let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
        let key = "citadel:\(cx),\(cz)"
        g.survival = false
        g.player.flying = true
        let centre0 = V3(Float(cx) + 0.5, Float(s.min.y + 24), Float(cz) + 0.5)
        _ = w.loadSync(center: centre0, radius: 9)
        let stand = V3(centre0.x - 110, Float(max(w.topY(cx - 110, cz), SEA)) + 25, centre0.z)
        func pin() { g.player.pos = stand; g.player.vel = .zero }
        pin()
        var t: Float = 0
        func sim(_ secs: Float, _ each: () -> Void = {}) { var e: Float = 0; while e < secs { g.tick(0.05); pin(); e += 0.05; t += 0.05; each() } }
        sim(3)
        guard let r0 = g.bases.records[key] else { check(false, "the citadel at \(cx) \(cz) has no record after 3 s"); return 1 }
        print("drop: citadel at \(cx) \(cz), he stands 110 west; pads: \(r0.dropPads.map { $0.map { "\(Int($0[0])),\(Int($0[1]) - YOFF),\(Int($0[2]))" }.joined(separator: " ") } ?? "none")")
        var seen: [Int: (pos: V3, parked: Bool, at: Float)] = [:]
        var nextBlast: Float = t + 5, nextFar: Float = t + 12, nextLog: Float = t + 30
        let launched0 = CitadelDrops.launched
        sim(300) {
            if t >= nextBlast, let r = g.bases.records[key] {
                nextBlast += 40
                Explosion.explode(at: r.plaza + V3(9, 0.5, -6), power: 2.5, game: g)
            }
            if t >= nextFar {
                nextFar += 25
                g.baseNoise(at: centre0 + V3(100, 0, -30), kind: .explosion, power: 4)
            }
            for d in w.ships.list where d.role == "dropship" && d.parent == nil && seen[d.id] == nil
                && simd_length(V2(d.pos.x - centre0.x, d.pos.z - centre0.z)) < 500 {
                seen[d.id] = (d.pos, w.ships.capState[d.id]?.parked ?? false, t)
            }
            if t >= nextLog {
                nextLog += 30
                let r = g.bases.records[key]
                let flying = w.ships.list.filter { $0.role == "dropship" && $0.parent == nil && !(w.ships.capState[$0.id]?.parked ?? true) }.count
                print(String(format: "drop: t %3.0f alert %@ dropships seen %d (from the air %d), flying %d, launched %d, called %d",
                             t, "\(r?.alert ?? .calm)", seen.count, seen.values.filter { !$0.parked }.count, flying,
                             CitadelDrops.launched - launched0, r?.dropships ?? -1))
            }
        }
        let fromAir = seen.values.filter { !$0.parked }
        let pads = g.bases.records[key]?.dropPads ?? []
        let onPads = seen.values.filter { v in v.parked && pads.contains { simd_length(V2(v.pos.x - $0[0], v.pos.z - $0[2])) < 2 } }.count
        for (id, v) in seen.sorted(by: { $0.value.at < $1.value.at }) {
            print(String(format: "drop:   dropship %d first seen at t %.0f, %@ at %.0f %.0f %.0f", id, v.at, v.parked ? "parked" : "in the air", v.pos.x, v.pos.y - Float(YOFF), v.pos.z))
        }
        let launched = CitadelDrops.launched - launched0
        if CitadelDrops.old {
            print("drop: (before) \(seen.count) dropships in 5 minutes, \(fromAir.count) built in the air")
            return 0
        }
        check(pads.count == CitadelDrops.fleet && onPads == CitadelDrops.fleet,
              "the citadel has \(pads.count) dropship pads, \(onPads) dropships first seen parked on them (\(CitadelDrops.parkedBuilt) parked in all)")
        check(seen.count <= CitadelDrops.fleet && fromAir.isEmpty && onPads == seen.count && launched >= 1,
              "over a 5-minute siege \(seen.count) dropships in all (at most \(CitadelDrops.fleet)), \(onPads) first seen on a pad, \(fromAir.count) built in the air, \(launched) launched")
        return fails == 0 ? 0 : 1
    }
}
