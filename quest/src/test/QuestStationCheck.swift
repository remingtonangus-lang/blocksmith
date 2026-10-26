import Foundation
import simd
import Metal

// P454 (Oct 25 14:05-14:10, the Boreal Station at -2430 5560 in New World (4): "there's dead soldiers at the bottom of
// the ramp"; "somehow all the guards in the boreal station just died... I never killed these guys"). The station's
// garrison left to itself for a minute and a half with him watching from high above: who hurts them, and how many are
// still standing.
//   questcheck --stationcheck
enum QuestStationCheck {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        TextureGen.registerAll()
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "ok  " : "FAIL") stationcheck: \(what)"); if !ok { fails += 1 } }

        let w = World(seed: 4797859299361840175, device: sharedSystemDevice, save: nil)
        FieldTerrain.newWorlds = true; w.makeFieldWorld()
        w.renderDistance = 5
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true
        SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.menu = nil
        guard let sc = w.gen.structures, let st = sc.nearest(BorealStation.kind, x: -2430, z: 5560, maxRegions: 2) else {
            print("stationcheck: no station"); return 1
        }
        let p0 = st.pieces.first
        let c = IVec3(((p0?.min.x ?? st.min.x) + (p0?.max.x ?? st.max.x)) / 2, 0, ((p0?.min.z ?? st.min.z) + (p0?.max.z ?? st.max.z)) / 2)
        print("stationcheck: station at \(c.x) \(c.z), anchor y \(st.anchor.y)")
        g.player.flying = true
        g.player.pos = V3(Float(c.x) + 0.5, Float(st.anchor.y) + 45, Float(c.z) + 0.5)
        _ = w.loadSync(center: g.player.pos, radius: 5)
        for _ in 0..<72 { g.tick(1.0 / 72) }

        func nearStation(_ m: Mob) -> Bool { max(abs(m.pos.x - Float(c.x)), abs(m.pos.z - Float(c.z))) < Float(BorealStation.yard + 24) }
        let garrison = g.mobs.mobs.filter { $0.health > 0 && $0.kind.steelhold && nearStation($0) }
        print("stationcheck: \(garrison.count) soldiers about the station; \(g.mobs.mobs.filter { nearStation($0) }.count) mobs in all")
        var hits: [String: (n: Int, dmg: Int)] = [:]
        var firstHits: [String] = []
        Mob.onHit = { m, src, d in
            guard m.kind.steelhold, nearStation(m) else { return }
            // Who: the nearest other mob to the source, or what is there.
            var who = "nothing near (\(Blocks.key(w.block(Int(floor(src.x)), Int(floor(src.y)), Int(floor(src.z))))))"
            var best: Float = 2.5
            for o in g.mobs.mobs where o !== m {
                let dd = simd_length(o.pos + V3(0, o.height * 0.6, 0) - src)
                if dd < best { best = dd; who = "\(o.kind.name) [\(o.factionValue)]" }
            }
            if simd_length(src - m.pos) < 0.05 { who = "itself (no source)" }
            hits[who, default: (0, 0)].n += 1; hits[who, default: (0, 0)].dmg += d
            if firstHits.count < 12 { firstHits.append(String(format: "%@ hit for %d by %@ at %.1f %.1f %.1f (it stood at %.1f %.1f %.1f)",
                                                                m.kind.name, d, who, src.x, src.y, src.z, m.pos.x, m.pos.y, m.pos.z)) }
        }
        let gun0 = garrison.first { $0.kind == .deckGun }
        for i in 0..<(90 * 72) {
            g.tick(1.0 / 72)
            if let gun = gun0, i % (15 * 72) == 0 {
                // (P454: who is up on the roof by the gun, and whether one has taken it)
                let up = g.mobs.mobs.filter { $0.health > 0 && $0 !== gun && Soldier.rank($0.kind) != nil && simd_length(V2($0.pos.x - gun.pos.x, $0.pos.z - gun.pos.z)) < 16 && $0.pos.y > gun.pos.y - 3 }
                print(String(format: "stationcheck:   %ds: gun at %.1f %.1f %.1f yaw %.0f crewed %@; up by it: %@", i / 72, gun.pos.x, gun.pos.y, gun.pos.z, gun.yaw * 57.3,
                             gun.soldierBrain.crewed ? (g.stationPowerOut(at: gun.pos) ? "yes (power out)" : "yes") : (g.stationPowerOut(at: gun.pos) ? "no (power out)" : "no"),
                             up.map { String(format: "%@ %.1f %.1f %.1f st %d", $0.kind.name, $0.pos.x - gun.pos.x, $0.pos.y - gun.pos.y, $0.pos.z - gun.pos.z, $0.soldierBrain.orderStation.rawValue) }.joined(separator: "; ")))
            }
        }
        Mob.onHit = nil
        let alive = garrison.filter { $0.health > 0 }
        for s in firstHits { print("stationcheck:   \(s)") }
        for (k, v) in hits.sorted(by: { $0.value.dmg > $1.value.dmg }) { print("stationcheck: hurt by \(k): \(v.n) hits, \(v.dmg) damage") }
        for m in garrison where m.health <= 0 { print(String(format: "stationcheck:   down: %@ at %.1f %.1f %.1f", m.kind.name, m.pos.x, m.pos.y, m.pos.z)) }
        // Then with him in the yard, seen and the alarm up, and later at the foot of the stair, never firing a shot
        // (kept alive): whatever hurts the soldiers now isn't him.
        hits = [:]; firstHits = []
        g.survival = true
        g.player.flying = false
        let yard = V3(Float(c.x) + 0.5, Float(st.anchor.y), Float(c.z) + 12.5)
        g.player.pos = w.freeSpawn(yard)
        g.spawnPoint = g.player.pos             // (a death here respawns him here: at the world spawn the station unloaded)
        let before = g.mobs.mobs.filter { $0.health > 0 && $0.kind.steelhold && nearStation($0) }
        Mob.onHit = { m, src, d in
            guard m.kind.steelhold, nearStation(m) else { return }
            var who = "nothing near (\(Blocks.key(w.block(Int(floor(src.x)), Int(floor(src.y)), Int(floor(src.z))))))"
            var best: Float = 2.5
            if simd_length(g.player.eye - src) < best { best = simd_length(g.player.eye - src); who = "the player" }
            for o in g.mobs.mobs where o !== m {
                let dd = simd_length(o.pos + V3(0, o.height * 0.6, 0) - src)
                if dd < best { best = dd; who = "\(o.kind.name) [\(o.factionValue)]" }
            }
            if simd_length(src - m.pos) < 0.05 { who = "itself (no source)" }
            hits[who, default: (0, 0)].n += 1; hits[who, default: (0, 0)].dmg += d
            if firstHits.count < 16 { firstHits.append(String(format: "%@ hit for %d by %@ at %.1f %.1f %.1f (it stood at %.1f %.1f %.1f)",
                                                                m.kind.name, d, who, src.x, src.y, src.z, m.pos.x, m.pos.y, m.pos.z)) }
        }
        var low = 20
        var blows: [String: (n: Int, sum: Int, big: Int)] = [:]
        var bigOnes: [String] = []
        Game.onDamage = { amt, cause in
            blows[cause, default: (0, 0, 0)].n += 1; blows[cause, default: (0, 0, 0)].sum += amt
            blows[cause, default: (0, 0, 0)].big = max(blows[cause, default: (0, 0, 0)].big, amt)
            if amt >= 6 && bigOnes.count < 12 {
                bigOnes.append(String(format: "%d (%@) at %.1f %.1f %.1f, clock %.2f", amt, cause, g.player.pos.x, g.player.pos.y, g.player.pos.z, g.clock))
            }
        }
        // P454 part 2: the roof gun has a gunner by it and lays on him (seconds crewed; a shot is a reload restarting).
        let roofGuns = before.filter { $0.kind == .deckGun }
        var crewedTicks = 0, gunShots = 0
        var lastReload = roofGuns.map { $0.soldierBrain.reload }
        for i in 0..<(80 * 72) {
            for (k, gun) in roofGuns.enumerated() where gun.health > 0 {
                let br = gun.soldierBrain
                if br.crewed { crewedTicks += 1 }
                if br.reload > lastReload[k] + 0.5 { gunShots += 1 }
                lastReload[k] = br.reload
            }
            if i == 40 * 72 { g.player.pos = w.freeSpawn(V3(Float(c.x - 5) + 0.5, Float(st.anchor.y - BorealStation.depth + 1), Float(c.z + 17) + 0.5)) }
            g.tick(1.0 / 72)
            low = min(low, g.health)
            if !g.alive { g.respawn() }
            g.health = 20
        }
        Mob.onHit = nil
        Game.onDamage = nil
        for (k, v) in blows.sorted(by: { $0.value.sum > $1.value.sum }) { print("stationcheck: he took \(v.sum) in \(v.n) blows (biggest \(v.big)) from \"\(k)\"") }
        for b in bigOnes { print("stationcheck:   a blow of \(b)") }
        let after = before.filter { $0.health > 0 }
        for s in firstHits { print("stationcheck:   \(s)") }
        for (k, v) in hits.sorted(by: { $0.value.dmg > $1.value.dmg }) { print("stationcheck: with him there, hurt by \(k): \(v.n) hits, \(v.dmg) damage") }
        for m in before where m.health <= 0 { print(String(format: "stationcheck:   down: %@ at %.1f %.1f %.1f", m.kind.name, m.pos.x, m.pos.y, m.pos.z)) }
        print("stationcheck: with him there 80 s: \(after.count) of \(before.count) soldiers alive; his health fell as low as \(low) in a tick")
        print(String(format: "stationcheck: %d roof gun(s): crewed %.0f s of 80, %d shots at him", roofGuns.count, Float(crewedTicks) / 72, gunShots))
        check(!roofGuns.isEmpty && crewedTicks > 40 * 72, "the station's roof gun has a gunner by it (crewed \(crewedTicks / 72) s of 80)")
        let heavies = before.filter { $0.pos.y >= Float(st.anchor.y) - 3 && $0.troopClass == .hannibal }.count
        check(heavies >= 1, "elite troops hold the surface (\(heavies) in Hannibal plate)")
        check(after.count * 10 >= before.count * 9, "nothing but him kills the garrison (\(after.count) of \(before.count) alive after 80 s with him not firing)")
        check(garrison.count >= 6, "the station is held (\(garrison.count) soldiers)")
        // P465: no gun on a whole tower falls (GunParts.supported).
        let guns = garrison.filter { $0.kind == .deckGun }
        check(GunParts.falls == 0, "no gun with its tower standing fell (\(GunParts.falls) fell; \(guns.filter { $0.health > 0 }.count) of \(guns.count) guns stand)")
        check(alive.count * 10 >= garrison.count * 9, "left alone for 90 s the garrison stands (\(alive.count) of \(garrison.count) alive)")
        // P454 part 2: coming at it over open ground, the roof gun shells him (it lays only past 24 blocks).
        if let gun = g.mobs.mobs.first(where: { $0.kind == .deckGun && $0.health > 0 && nearStation($0) }) {
            var spot: V3?
            for (dx, dz) in [(0, 50), (50, 0), (0, -50), (-50, 0), (35, 35), (-35, 35), (35, -35), (-35, -35)] {
                let p = w.freeSpawn(V3(gun.pos.x + Float(dx), Float(st.anchor.y), gun.pos.z + Float(dz)))
                if w.canSee(gun.pos + V3(0, 1.5, 0), p + V3(0, 1.6, 0)) { spot = p; break }
            }
            if let p = spot {
                g.player.pos = p
                g.spawnPoint = p
                var shots = 0, last = gun.soldierBrain.reload
                for i in 0..<(30 * 72) {
                    g.tick(1.0 / 72)
                    if i % (5 * 72) == 0 {
                        let br = gun.soldierBrain
                        let to = g.player.eye - gun.pos
                        print(String(format: "stationcheck:     %ds: power %@, crewed %@, sees %@, aggro %@, seen %.1f s ago, yaw %.0f (him at %.0f), pitch %.2f, reload %.1f, him %.0f off",
                                     i / 72, g.stationPowerOut(at: gun.pos) ? "out" : "on", br.crewed ? "yes" : "no", br.sees ? "yes" : "no", gun.aggro ? "yes" : "no",
                                     br.seenAgo, gun.yaw * 57.3, atan2f(-to.x, -to.z) * 57.3, br.pitch, br.reload, simd_length(V2(to.x, to.z))))
                    }
                    let r = gun.soldierBrain.reload
                    if r > last + 0.5 { shots += 1 }
                    last = r
                    if !g.alive { g.respawn(); g.player.pos = p }
                    g.health = 20
                }
                print(String(format: "stationcheck: from %.0f blocks off in the open the roof gun fired %d times in 30 s", simd_length(V2(p.x - gun.pos.x, p.z - gun.pos.z)), shots))
                check(shots >= 1, "the roof gun fires on him as he comes over open ground (\(shots) shots in 30 s)")
            } else { print("stationcheck: no open ground in sight of the roof gun 50 blocks off") }
        }
        print(fails == 0 ? "stationcheck: all passed" : "stationcheck: \(fails) failed")
        return fails == 0 ? 0 : 1
    }
}
