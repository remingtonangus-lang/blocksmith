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
        for _ in 0..<(90 * 72) { g.tick(1.0 / 72) }
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
        for i in 0..<(80 * 72) {
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
        check(after.count * 10 >= before.count * 9, "nothing but him kills the garrison (\(after.count) of \(before.count) alive after 80 s with him not firing)")
        check(garrison.count >= 6, "the station is held (\(garrison.count) soldiers)")
        check(alive.count * 10 >= garrison.count * 9, "left alone for 90 s the garrison stands (\(alive.count) of \(garrison.count) alive)")
        print(fails == 0 ? "stationcheck: all passed" : "stationcheck: \(fails) failed")
        return fails == 0 ? 0 : 1
    }
}
