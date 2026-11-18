import Foundation
import Metal
import simd

// Ledger 255's check (questcheck --shipleave-only; in the full suite after the garrison check): the Stormwarden Frigate on
// his world of that evening (seed 1794958869, a headset world), at the spot in the taiga where he flew her into the ground
// (6013 -797). From her helm on the bridge he leaves it:
//   crashed, her engines shaken loose, her keel in the ground -> on the ground beside her, clear of her hull, and a
//     second later still there, on his feet (his case: "Let me out of here");
//   still on the ground with her drive working (landed) -> beside her the same way;
//   wrecked on the ground -> beside her;
//   hanging 120 blocks up with her engines stopped -> over her side under his parachute, clear of her, coming down;
//   under way 120 blocks up with her drive -> on her bridge, aboard (as before).
// BS_OLDSHIPLEAVE=1: on the bridge every time (the check fails).
enum ShipLeaveCheck {
    static func run(device: MTLDevice, check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let newWorlds0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        let rules0 = (WorldRules.p44, TownSizes.on, World.fewerLakesUnsaved, World.lessWaterUnsaved)
        WorldRules.p44 = true; TownSizes.on = true; World.fewerLakesUnsaved = true; World.lessWaterUnsaved = true
        defer {
            FieldTerrain.newWorlds = newWorlds0
            (WorldRules.p44, TownSizes.on, World.fewerLakesUnsaved, World.lessWaterUnsaved) = rules0
        }
        let w = World(seed: 1794958869, device: device, save: nil)
        w.renderDistance = 8; w.activeDistance = 8
        w.makeFieldWorld()
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true; SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.survival = false                    // (creative, as he was)
        g.time = 0.25 * DAY_LENGTH
        let ships = w.ships
        let spot = V3(6013.5, 230, -797.5)
        g.player.pos = spot; g.player.flying = true; g.player.vel = .zero
        w.activeCenter = spot
        _ = w.loadSync(center: spot, radius: 8)
        ships.spawnCapital("warfrigate", home: IVec3(6013, 0, -797), yaw: 1.2, region: nil, sync: true)
        for _ in 0..<4 { g.player.pos = spot; g.player.vel = .zero; g.tick(0.05) }
        guard let s = ships.capitals.first(where: { $0.role == "warfrigate" }), let st = ships.capState[s.id], let stand = g.helmStand(s) else {
            check(false, "shipleave: a Stormwarden Frigate at his crash in the taiga (6013 -797)"); return
        }
        let engines0 = max(1, st.engines0)
        // Her pose: still or under way, her keel `keel` blocks over the ground under her (negative: dug in).
        func pose(keel: Float, speed: Float) {
            s.vel = .zero; s.angVel = .zero
            s.updateBounds()
            s.pos.y += keel - g.keelClearance(s)
            s.updateBounds()
            s.vel = s.dirToWorld(V3(0, 0, -1)) * speed
            let at = s.toWorld(stand)
            w.activeCenter = at
            _ = w.loadSync(center: at, radius: 8)
        }
        func ready(wrecked: Bool, engines: Bool) {
            s.wrecked = wrecked
            s.engines = engines ? engines0 : 0
            st.enginesShaken = !engines
            st.restartT = 0
            g.player.parachute = false; g.player.flying = false; g.player.vel = .zero
        }
        func outside(_ p: V3) -> Bool {
            let l = s.toLocal(p)
            return l.x < 0 || l.x > Float(s.grid.sx) || l.z < 0 || l.z > Float(s.grid.sz)
        }
        func ticks(_ n: Int) { for _ in 0..<n { g.tick(0.05) } }
        // He takes her helm and leaves it.
        func leave() -> (aboardFirst: Bool, note: String) {
            g.player.pos = s.toWorld(stand)
            g.startPiloting(s)
            let first = ships.pilot === s && !outside(g.player.pos)
            g.leaveHelm()
            return (first, String(format: "%.0f blocks from the helm", simd_length(g.player.pos - s.toWorld(stand))))
        }
        func onGround() -> (Bool, String) {
            let p = g.player.pos
            let free = !g.player.collides(at: p, w)
            let under = w.solidAt(Int(floor(p.x)), Int(floor(p.y - 0.05)), Int(floor(p.z)))
            let ok = outside(p) && free && under && ships.aboard == nil && ships.pilot == nil
            return (ok, "\(outside(p) ? "off her" : "on her"), \(free ? "free" : "in blocks"), ground under \(under ? "yes" : "no"), aboard \(ships.aboard?.name ?? "nothing")")
        }

        // (A) His case: flown into the ground, her engines shaken loose.
        pose(keel: -2, speed: 0); ready(wrecked: false, engines: false)
        let (a0, an) = leave()
        let (a1, at1) = onGround()
        ticks(20)
        let (_, at2) = onGround()
        let a3 = outside(g.player.pos) && ships.aboard == nil && !g.player.collides(at: g.player.pos, w) && g.player.onGround
        check(a0 && a1 && a3,
              "shipleave: off the helm of the Stormwarden crashed into the ground with her engines stopped he is on the ground beside her (\(an); \(at1)), and a second later still (\(at2), on his feet \(g.player.onGround))")
        // (B) Landed, her drive working.
        pose(keel: 0, speed: 0); ready(wrecked: false, engines: true)
        let (b0, bn) = leave()
        let (b1, bt) = onGround()
        check(b0 && b1, "shipleave: off the helm of the Stormwarden standing on the ground he is beside her (\(bn); \(bt))")
        // (C) Wrecked on the ground.
        pose(keel: -1, speed: 0); ready(wrecked: true, engines: false)
        let (c0, cn) = leave()
        let (c1, ct) = onGround()
        check(c0 && c1, "shipleave: off the helm of the wrecked Stormwarden he is beside her (\(cn); \(ct))")
        // (D) Hanging in the air with her engines stopped: over the side under his parachute.
        pose(keel: 120, speed: 0); ready(wrecked: false, engines: false)
        let (d0, dn) = leave()
        let y0 = g.player.pos.y
        let d1 = outside(g.player.pos) && g.player.parachute && ships.aboard == nil
        ticks(60)
        let sink = (y0 - g.player.pos.y) / 3
        let d2 = outside(g.player.pos) && ships.aboard == nil && g.player.parachute && sink > 2 && sink < 8
        check(d0 && d1 && d2, String(format: "shipleave: off the helm of the Stormwarden hanging 120 up with her engines stopped he bails out under his parachute (%@, %@), clear of her and still under it 3 s later, coming down at %.1f blocks a second (%@)",
                                    dn, d1 ? "yes" : "no", sink, d2 ? "yes" : "no"))
        // (E) Under way in the air with her drive: on her bridge, aboard.
        pose(keel: 120, speed: 10); ready(wrecked: false, engines: true)
        let (e0, en) = leave()
        let e1 = !outside(g.player.pos) && ships.aboard === s && !g.player.parachute
        check(e0 && e1, "shipleave: off the helm of the Stormwarden under way in the air he stays on her bridge (\(en), aboard \(ships.aboard?.name ?? "nothing"))")
        print("shipleave: ground \(Game.shipLeft.ground), chute \(Game.shipLeft.chute)" + String(format: ", %.1f s", CFAbsoluteTimeGetCurrent() - t0))
        if ships.pilot != nil { g.leaveHelm() }
        ships.remove(s)
        w.unloadAll()
    }
}
