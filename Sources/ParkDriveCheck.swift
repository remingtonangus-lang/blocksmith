import Foundation
import simd

// Nov 16 evening playtest, the Proving Grounds' vehicle park (21:01-21:09: "the follow camera is inverted", "the camera's
// not facing the correct way... where I'm pointing is not where it's aiming", "the cans are turned the wrong way",
// "propellers facing the wrong way", "like 270 degrees, I should be at the 180", "much of the planes don't work"):
// questcheck --parkdrive builds the grounds as the world does and takes every one of the hundred vehicles from its helm
// where it stands, the way he does (walking up from its sign, looking at it), and checks:
//   view     his look once at the helm, and the chase view's own line (behind the hull, looking on), both along the helm's
//            forward;
//   throttle full ahead moves it forward (along the helm's forward), a plane leaves the deck, an airship or a helicopter
//            climbs when asked;
//   guns     each hull gun's muzzle points out of the hull; looking ahead (or 60 degrees off, for a turret), the shells go
//            where he looks.
// Each vehicle is taken off the deck after its run (the next one's plot stays as built).
enum ParkDriveCheck {
    static var shot: ((Game, String, V3, Float, Float) -> Void)?
    static func yawOf(_ v: V3) -> Float { atan2f(-v.x, -v.z) }
    static func off(_ a: Float, _ b: Float) -> Float { abs(remainderf(a - b, 2 * .pi)) * 180 / .pi }
    static func flat(_ v: V3) -> V3 { let f = V3(v.x, 0, v.z); return simd_length(f) > 1e-4 ? simd_normalize(f) : V3(0, 0, -1) }

    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, ships = w.ships
        let wasSurvival = g.survival
        g.survival = false
        ships.encounters = false
        defer { g.survival = wasSurvival }
        let only = Env.all["PARK_ONLY"].map { Set($0.split(separator: ",").compactMap { Int($0) }) }
        let o = IVec3(Int(floor(g.player.pos.x)) + 3000, ProvingGrounds.deckY, Int(floor(g.player.pos.z)) + 3000)
        g.player.pos = ProvingGrounds.start(o); g.player.flying = true
        let held0 = w.heldDeck
        w.heldDeck = ProvingGrounds.held(o)
        defer { w.heldDeck = held0 }
        let b = ProvingGrounds.plan(o)
        while !b.done {
            if let (c, r) = b.needs[b.next] { _ = w.loadSync(center: c, radius: r) }
            b.run(g, budget: 0)
        }
        // (PARK_SHOTS="i,j": a picture of each named vehicle as it stands, with --render PATH; PARK_LIST=1: every plan's size)
        if Env.all["PARK_LIST"] != nil {
            for pl in ProvingGrounds.park.plots { let p = VehicleZoo.plan(pl.index); print("parklist \(pl.index) \(p.cells.count) blocks at \(pl.at.x),\(pl.at.z) size \(pl.size.x)x\(pl.size.z): \(p.name)") }
        }
        if let list = Env.all["PARK_SHOTS"], let shot = shot {
            for i in list.split(separator: ",").compactMap({ Int($0) }) {
                guard let pl = ProvingGrounds.park.plots.first(where: { $0.index == i }) else { continue }
                let c = V3(Float(o.x + pl.at.x) + Float(pl.size.x) / 2, Float(o.y + pl.at.y), Float(o.z + pl.at.z) + Float(pl.size.z) / 2)
                let r = Float(max(pl.size.x, pl.size.z)) * 0.9 + 6
                for (k, a) in [Float(0.6), 2.5].enumerated() {
                    let eye = c + V3(-sinf(a) * r, Float(pl.size.y) + 4, -cosf(a) * r)
                    let d = c - eye
                    shot(g, String(format: "park-%03d-%d", i, k), eye, atan2f(-d.x, -d.z), asinf(d.y / simd_length(d)))
                }
            }
        }
        var bad = [String: [Int]]()
        var planesDown = 0, planes = 0
        var sightBlocked = [String: [Int]]()
        var fails = 0
        for pl in ProvingGrounds.park.plots where only?.contains(pl.index) ?? true {
            let p = VehicleZoo.plan(pl.index)
            guard p.drives || p.guns > 0 else { continue }
            if p.family == .plane && p.drives { planes += 1 }
            let shift = o + pl.at - pl.lo
            let helm = p.helm + shift
            _ = w.loadSync(center: V3(Float(helm.x), Float(helm.y), Float(helm.z)), radius: 3)
            let n0 = ships.list.count
            // He walks up from the sign to the north of the plot: on the deck, looking south at it.
            g.player.flying = false
            g.player.pos = V3(Float(helm.x) + 0.5, Float(o.y), Float(o.z + pl.at.z) - 3)
            g.player.yaw = .pi; g.player.pitch = 0
            let (made, msg) = ships.assemble(at: helm, game: g)
            guard let s = made else { check(false, String(format: "parkdrive %03d %@: did not assemble (%@)", pl.index, p.name, msg)); continue }
            var notes: [String] = [], ok = true
            func fail(_ k: String, _ m: String) { ok = false; notes.append("FAIL " + m); bad[k, default: []].append(pl.index) }
            g.startPiloting(s)
            var mi = MoveInput()
            func run(_ secs: Float) {
                for _ in 0..<Int(secs * 60) {
                    g.shipPlayerUpdate(1.0 / 60, mi)
                    ships.update(1.0 / 60, game: g)
                }
            }
            run(0.25)
            let fwd = flat(s.dirToWorld(s.fwd))
            // View: his look, and the chase view's line from where it sits to him.
            let look = off(g.player.yaw, yawOf(fwd))
            if look > 20 { fail("look", String(format: "at the helm he looks %.0f degrees off its forward", look)) }
            if let c = g.chaseOffset, simd_length(V2(c.x, c.z)) > 0.5 {
                let cam = off(yawOf(-c), yawOf(fwd))
                if cam > 20 { fail("chase", String(format: "the chase view looks on %.0f degrees off its forward", cam)) }
            }
            // (ledger 249) Sight: from his eye at the helm, the hull's own solid blocks (glass aside) on his line ahead in the
            // first 8 blocks. A truck's load box stood at its bow, over his eyes.
            do {
                let eyeL = s.toLocal(g.player.eye), fl = s.toLocal(g.player.eye + fwd) - eyeL
                var t: Float = 0.3, hidden = false
                while t < 8 && !hidden {
                    let q = eyeL + fl * t
                    let b = s.grid.get(Int(floorf(q.x)), Int(floorf(q.y)), Int(floorf(q.z)))
                    if b != AIR && Blocks.opaque[Int(b)] { hidden = true }
                    t += 0.2
                }
                if hidden {
                    sightBlocked[p.family.rawValue, default: []].append(pl.index)
                    if p.family == .truck { fail("sight", "the hull's own blocks stand over his eyes ahead of the helm") }
                }
            }
            // Guns: muzzles out of the hull; looking ahead, the shells go where he looks.
            let centre = (s.localMin + s.localMax) * 0.5
            for (c, d) in s.cannons {
                let out = simd_dot(V2(d.x, d.z), V2(c.x + 0.5 - centre.x, c.z + 0.5 - centre.z))
                if out < -0.01 { fail("muzzle", String(format: "a hull gun at %.0f,%.0f,%.0f points into the hull", c.x, c.y, c.z)) }
            }
            if p.guns > 0 {
                func shoot(_ yaw: Float, _ what: String) {
                    g.player.yaw = yaw; g.player.pitch = 0
                    run(3)
                    for t in [s] + ships.turrets(of: s) { t.reload = 0 }
                    let before = ships.shells.count
                    _ = g.shipInteract(breakHeld: true, breakNow: true, useNow: false, sneak: false, dt: 1.0 / 60)
                    let new = ships.shells.suffix(max(0, ships.shells.count - before))
                    if new.isEmpty { fail("fire", "\(what): nothing fired"); return }
                    // (a hull gun laid along the forward goes where he looks; a broadside gun out along its own muzzle)
                    let hull = s.cannons.map { c -> Float in
                        let dw = flat(s.dirToWorld(c.1))
                        return simd_dot(dw, fwd) > 0.7 ? yaw : yawOf(dw)
                    }
                    var worst: Float = 0
                    for (k, sh) in new.enumerated() { worst = max(worst, off(yawOf(sh.vel), k < hull.count ? hull[k] : yaw)) }
                    if worst > 12 { fail("aim", String(format: "%@: shells go %.0f degrees off where they should", what, worst)) }
                    for sh in ships.shells { sh.life = 0 }
                    ships.shells.removeAll()
                }
                if !s.cannons.isEmpty { shoot(yawOf(fwd), "hull guns, looking ahead") }
                if ships.turrets(of: s).contains(where: { !$0.cannons.isEmpty }) {
                    for t in [s] { t.cannons = [] }          // (the turret's own shells only)
                    shoot(yawOf(fwd) - .pi / 3, "turret, looking 60 off to the right")
                }
            }
            // Throttle: full ahead moves it forward; an aircraft leaves the deck, a climber climbs.
            if p.drives {
                let a = s.pos
                if p.family == .heli { run(4) }
                if p.expectClimb {
                    mi.jump = true; run(3); mi.jump = false
                    if s.pos.y - a.y < 1 { fail("climb", String(format: "asked to climb for 3 s it rose %.1f", s.pos.y - a.y)) }
                }
                let a2 = s.pos
                g.player.yaw = yawOf(fwd)
                mi.forward = 1; run(p.family == .plane ? 8 : 3); mi.forward = 0
                let d = s.pos - a2
                let along = simd_dot(V2(d.x, d.z), V2(fwd.x, fwd.z))
                // (planes: taking off from the deck is a flight rule for Fable (a wheel-less build sits on its belly, a
                // player's wing-and-propeller build has no lift model to rise on): counted on their own line, failing only
                // with PARK_PLANES=1)
                let plane = p.family == .plane
                if plane && (along < 2 || s.pos.y - a.y < 2) { planesDown += 1 }
                if plane && Env.all["PARK_PLANES"] == nil { notes.append(String(format: "ran %.0f, rose %.1f", along, s.pos.y - a.y)) }
                else if along < 2 { fail("throttle", String(format: "full ahead it went %.1f along its forward (%.1f in all; %d props, %d wheels, %d engines, throttle %.2f, %.0f t, contacts %d, asleep %d, submerged %.1f)",
                                                          along, simd_length(V2(d.x, d.z)), s.props.count, s.wheels.count, s.engines, s.throttleEase, s.mass, s.contacts, s.asleep ? 1 : 0, s.submerged)) }
                else { notes.append(String(format: "ran %.0f ahead", along)) }
                if plane && Env.all["PARK_PLANES"] != nil && s.pos.y - a.y < 2 { fail("takeoff", String(format: "a plane at full ahead for 8 s rose %.1f (ran %.0f)", s.pos.y - a.y, along)) }
            }
            g.leaveHelm()
            ships.aboard = nil
            for t in ships.list.dropFirst(n0) { ships.remove(t) }
            for sh in ships.shells { sh.life = 0 }
            ships.shells.removeAll()
            if !ok { fails += 1 }
            check(ok, String(format: "parkdrive %03d ", pl.index) + p.name + ": " + notes.joined(separator: "; "))
        }
        print("parkdrive planes: \(planesDown) of \(planes) don't leave the deck at full ahead for 8 s")
        print("parkdrive sight: his view ahead from the helm hidden by the hull's own blocks: " + (sightBlocked.isEmpty ? "none" : sightBlocked.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.count) (\($0.value.map { String($0 + 1) }.joined(separator: ",")))" }.joined(separator: ", ")))
        let sum = bad.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.count)" }.joined(separator: ", ")
        print("parkdrive: \(fails) vehicles flagged" + (sum.isEmpty ? "" : " (" + sum + ")"))
    }
}
