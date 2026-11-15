import Foundation
import simd

// FAILURES.md 2, on a Capital citadel as the world makes it (Fable, Nov 15: "a host check that rides a capital elevator up
// and down 5 times with a rider"): the side tower's lift, from the plaza to the gun room, found where the generator put
// it. He stands in the car and sends it to the top floor, then back to the ground, five times over. Every trip: the car
// arrives at the landing it was sent to, he stays in it the whole way (never outside the shaft, never dropping away
// from its floor or lifted off it by more than half a block), takes no harm, and at the end the doors there are open
// and those he left are shut. questcheck --capitallift, and the full suite.
enum CapitalElevatorCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, p = g.player
        guard Elevators.has(), let st = w.gen.structures?.nearest("military_base", x: Int(p.pos.x), z: Int(p.pos.z), maxRegions: 16) else {
            check(false, "capital lift: no citadel within 16 regions"); return
        }
        let home = p.pos, surv0 = g.survival, fly0 = p.flying, yaw0 = p.yaw, pitch0 = p.pitch
        defer {
            p.pos = home; p.vel = .zero; g.survival = surv0; p.flying = fly0; p.yaw = yaw0; p.pitch = pitch0
            g.closeMenu()
        }
        let cx = (st.min.x + st.max.x) / 2, cz = (st.min.z + st.max.z) / 2
        let mid = V3(Float(cx) + 0.5, Float(st.min.y + 40), Float(cz) + 0.5)
        p.pos = mid; p.flying = true; p.vel = .zero
        _ = w.loadSync(center: mid, radius: 5)
        // The lifts the generator built: every car floor in the site, by its shaft.
        var shafts: [Int64: Elevators.Run] = [:]
        let floorID = Blocks.id(Elevators.floorKey)
        for y in st.min.y...min(CH - 1, st.max.y) { for z in st.min.z...st.max.z { for x in st.min.x...st.max.x
            where Blocks.groupBase[Int(w.block(x, y, z))] == floorID {
            guard let r = Elevators.run(w, near: IVec3(x, y, z)) else { continue }
            shafts[r.shaft.key] = r
        } } }
        guard let r = shafts.values.max(by: { $0.shaft.landings.count < $1.shaft.landings.count }), r.shaft.landings.count >= 3, let car0 = r.shaft.car else {
            check(false, "capital lift: the citadel at \(cx) \(cz) has no lift with three landings or more (\(shafts.count) found)"); return
        }
        let s = r.shaft, ground = s.landings.first!, top = s.landings.last!
        print("capital lift: the citadel at \(cx) \(cz): \(shafts.count) lifts, the tallest with \(s.landings.count) landings (\(s.landings.map { $0 - ground })), car at \(car0 - ground), depth \(s.d)")
        g.survival = true; g.alive = true; g.health = 20; g.paused = false; g.menu = nil
        p.flying = false
        // (in the car at the ground floor first, if it stands elsewhere: called down empty)
        if car0 != ground {
            Elevators.request(g, r, ground)
            for _ in 0..<(72 * 40) { g.tick(1.0 / 72); if r.phase == 0 && r.shaft.car == ground { break } }
        }
        func inShaft() -> Bool {
            // (the car's cells: W across, d deep, from its front-left cell)
            let lx = (p.pos.x - Float(s.a.x)) * Float(s.u.x) + (p.pos.z - Float(s.a.z)) * Float(s.u.z) + (s.u.x + s.u.z < 0 ? 1 : 0)
            let lz = (p.pos.x - Float(s.a.x)) * Float(s.n.x) + (p.pos.z - Float(s.a.z)) * Float(s.n.z) + (s.n.x + s.n.z < 0 ? 1 : 0)
            return lx > 0.1 && lx < Float(Elevators.W) - 0.1 && lz > 0.1 && lz < Float(s.d) - 0.1
        }
        var trips: [String] = [], allOK = r.shaft.car == ground
        let c0 = Elevators.center(s, ground)
        p.pos = V3(c0.x, Float(ground + 1), c0.z); p.vel = .zero
        for _ in 0..<36 { g.tick(1.0 / 72) }
        for k in 0..<10 {
            let from = k % 2 == 0 ? ground : top, to = k % 2 == 0 ? top : ground
            let hp0 = g.health
            Elevators.request(g, r, to)
            var frames = 0, outside = 0, gapDev: Float = 0, gap0: Float? = nil, moved = false
            while frames < 72 * 60 {
                g.tick(1.0 / 72); frames += 1
                if !inShaft() { outside += 1 }
                if let sh = r.ship, !sh.hidden {
                    moved = true
                    let gap = p.pos.y - sh.worldMin.y
                    if let a = gap0 { gapDev = max(gapDev, abs(gap - a)) } else { gap0 = gap }
                }
                if r.phase == 0 && r.shaft.car == to && frames > 36 { break }
            }
            let at = p.pos.y - Float(to + 1)
            let openThere = Elevators.doorsAt(w, r.shaft, to), shutBehind = Elevators.doorsAt(w, r.shaft, from)
            let ok = r.shaft.car == to && moved && outside == 0 && gapDev < 0.5 && abs(at) < 0.3 && g.health >= hp0 && openThere == 2 && shutBehind == 0
            if !ok { allOK = false }
            trips.append(String(format: "%@%@ %.1f s%@", ok ? "" : "FAILED ", to == top ? "up" : "down", Float(frames) / 72,
                                ok ? "" : String(format: " (car at %@, rode %@, %d ticks outside the shaft, off its floor by %.2f, %.2f off the landing, health %.0f of %.0f, doors there %d, behind %d)",
                                                 r.shaft.car.map { "\($0 - ground)" } ?? "moving", moved ? "yes" : "no", outside, gapDev, at, Float(g.health), Float(hp0), openThere, shutBehind)))
        }
        check(allOK, "capital lift: he rides the citadel's lift from the ground floor to the top (\(top - ground) up) and back five times, in the car the whole way, arriving each time with the doors open there and shut behind: " + trips.joined(separator: "; "))
        Elevators.runs.removeAll()
    }
}
