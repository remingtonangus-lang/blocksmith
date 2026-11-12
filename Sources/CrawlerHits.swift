import Foundation
import simd

// Nov 12 playtest (06:35:59-06:36:06, manning a Capital base gun on foot at an Ironback Crawler: "when I shoot at
// the crawler it gets obliterated. When the capital shoots at it, nothing happens... I just took a few shots at the
// crawler and absolutely decimated it"; 06:34:36-06:34:47, driving one: "what caused it to get destroyed... the
// engine room is intact"). `questcheck --crawlerhits`: the same heavy shell, his or a crew's, fired into a crawler's
// flank one at a time, and what each does to it (blocks torn, wheels, drive engines, turret, why it stopped).
enum CrawlerHits {
    struct Row { var shots = 0; var torn: [Int] = []; var why = ""; var stopAt = -1; var wheels = ""; var engines = ""; var turret = "" }

    static func shell(from: V3, to: V3, his: Bool) -> Slug {
        let d = simd_normalize(to - from)
        var s = Slug(pos: from, vel: d * HeavyTurret.speed, kind: .shell, damage: 0, fromPlayer: his, shooter: nil,
                     by: his ? "Player" : "Capital Naval Gun", life: 3.5, gravity: 0)
        HeavyTurret.arm(&s)
        s.power = HeavyTurret.mannedPower; s.breach = HeavyTurret.mannedBreach      // (his: VehicleControls; a crew's: Soldiers)
        return s
    }

    // Fires up to `n` shells into a fresh crawler's flank; returns what each did.
    static func volley(_ g: Game, his: Bool, captured: Bool, n: Int = 8) -> Row? {
        let w = g.world
        let n1 = w.ships.list.count
        let home = g.player.pos + V3(0, 0, 140)
        w.ships.spawnCapital("crawler", home: IVec3(Int(home.x), 0, Int(home.z)), yaw: 0, region: nil, sync: true)
        guard let e = w.ships.list.dropFirst(n1).first(where: { $0.role == "crawler" }), let st = w.ships.capState[e.id] else { return nil }
        defer { w.ships.remove(e); w.ships.capState.removeValue(forKey: e.id); w.ships.shockwaves.removeAll(); g.arms.breaches.removeAll() }
        _ = w.loadSync(center: e.pos, radius: 3)
        if captured { e.captured = true; st.crewDone = Set(st.crewRoles.indices) }
        func hull() -> Int { w.ships.list.filter { $0.root === e.root }.reduce(0) { $0 + $1.blockCount } }
        func gun() -> Int { w.ships.turrets(of: e).reduce(0) { $0 + $1.blockCount } }
        var r = Row()
        let gun0 = gun(), eng0 = e.engines
        for k in 0..<n {
            let before = hull()
            // Its flank at mid height, a different spot along it each shot (a gunner walks his shots along the hull).
            let c = (e.worldMin + e.worldMax) * 0.5
            let along = (e.worldMax.z - e.worldMin.z) * (Float(k % 4) / 4 - 0.375)
            let to = V3(c.x, c.y, c.z + along)
            let from = to + V3(30, 2, 0)
            g.arms.spawn(shell(from: from, to: to, his: his))
            var frames = 0
            while !g.arms.slugs.isEmpty && frames < 200 { g.arms.update(1.0 / 72, g); frames += 1 }
            frames = 0
            while !g.arms.breaches.isEmpty && frames < 200 { NavalGuns.stepBreaches(g); frames += 1 }
            w.ships.capitalTick(1.0 / 72, game: g)
            r.shots = k + 1
            r.torn.append(before - hull())
            if (e.wrecked || !st.disabledWhy.isEmpty) && r.stopAt < 0 { r.stopAt = k + 1; r.why = st.disabledWhy.isEmpty ? "wrecked" : st.disabledWhy }
            if r.stopAt > 0 && k + 1 >= r.stopAt + 1 { break }
        }
        r.wheels = "\(st.wheels.count - st.wheelsLost)/\(st.wheels.count)"
        r.engines = "\(e.engines)/\(eng0)"
        r.turret = "\(gun())/\(gun0)"
        return r
    }

    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        g.survival = true
        var rows: [String: Row] = [:]
        for (his, captured) in [(true, false), (false, false), (true, true), (false, true)] {
            let name = (his ? "his shells" : "a crew's shells") + (captured ? " (his crawler)" : " (a Capital crawler)")
            guard let r = volley(g, his: his, captured: captured) else { check(false, "crawlerhits: a crawler spawns"); return }
            rows[name] = r
            print("crawlerhits: \(name): stopped after \(r.stopAt) (\(r.why)), torn per shot \(r.torn), wheels \(r.wheels), engines \(r.engines), turret blocks \(r.turret)")
        }
        // The same gun hits the same whoever fires it (P471's rule), and a crawler takes several heavy shells.
        let a = rows["his shells (a Capital crawler)"]!, b = rows["a crew's shells (a Capital crawler)"]!
        let c = rows["his shells (his crawler)"]!, d = rows["a crew's shells (his crawler)"]!
        func close(_ x: Row, _ y: Row) -> Bool { (x.stopAt < 0) == (y.stopAt < 0) && abs(x.stopAt - y.stopAt) <= 1 }
        check(close(a, b) && close(c, d) && close(a, c), "crawlerhits: the same heavy shell stops a crawler after as many hits whoever fires it (\(a.stopAt), \(b.stopAt), \(c.stopAt), \(d.stopAt); -1 still running after 8)")
        check([a, b, c, d].allSatisfy { $0.stopAt < 0 || $0.stopAt >= 3 }, "crawlerhits: a crawler takes three heavy shells or more before it stops (\(a.stopAt), \(b.stopAt), \(c.stopAt), \(d.stopAt))")
    }
}
