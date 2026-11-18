import Foundation
import Metal
import simd

// Ledger 253's check (questcheck --garrison-only; in the full suite after the Boreal Station checks): Boreal Stations on
// five headset (field) worlds, his Nov 17 one first. Each is reached as he reaches one: from 220 blocks out, flown in at
// 8 blocks a second at view 6 through Game.tick (the land streamed as he goes), and stood in at the gate: its garrison is
// there (20 or more inside the fence and bunker) and nothing was mustered. Then the garrison is taken out of the world
// without a death or a stash (the empty station he found): within seconds (15 at most) the station holds its planned
// garrison again, once, and the log line names what the count saw. On the first world: a station whose men he killed stays empty.
// BS_OLDMUSTER=1: the emptied station stays empty (the check fails).
enum BorealMusterCheck {
    static let seeds: [(UInt64, Int, Int)] = [(4259144782798118884, 1191, -1687), (12345, 0, 0), (3084501862406496736, 0, 0),
                                               (7780452129890778212, 0, 0), (1794958869, 0, 0)]

    static func run(device: MTLDevice, check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let newWorlds0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        // The headset's world rules, as questcheck --headset sets them (the host checks turn them off for their fixtures,
        // and a station sits elsewhere under them: his seed's is at 1128 -1784 there, not 1192 -1704).
        let rules0 = (WorldRules.p44, TownSizes.on, World.fewerLakesUnsaved, World.lessWaterUnsaved)
        WorldRules.p44 = true; TownSizes.on = true; World.fewerLakesUnsaved = true; World.lessWaterUnsaved = true
        // (His kills at the first station move the factions' standing and his honour, which the checks after this one
        // fight under: put back. The full suite's troop behaviour and soldier gun checks found no fighting once.)
        let rep0 = FactionRep.rep, hunters0 = FactionRep.nextHunters, honour0 = TownLaw.state.honour, repText0 = FactionRep.encode()
        defer {
            FieldTerrain.newWorlds = newWorlds0
            (WorldRules.p44, TownSizes.on, World.fewerLakesUnsaved, World.lessWaterUnsaved) = rules0
            if FactionRep.encode() != repText0 { print("garrison: left the factions' standing at \(FactionRep.encode()) (was \(repText0)); put back") }
            FactionRep.rep = rep0; FactionRep.nextHunters = hunters0; TownLaw.state.honour = honour0
        }
        for (i, (seed, sx, sz)) in seeds.enumerated() {
            let w = World(seed: seed, device: device, save: nil)
            w.renderDistance = 6; w.activeDistance = 6
            w.makeFieldWorld()
            let g = Game(world: w, save: nil, persistent: false)
            g.smoothTerrain = true; SmoothTerrain.use(world: true, world: w)
            g.paused = false; g.survival = false
            g.time = 0.25 * DAY_LENGTH
            guard let sc = w.gen.structures, let s = sc.nearest(BorealStation.kind, x: sx, z: sz, maxRegions: 4) ?? sc.nearest(BorealStation.kind, x: sx, z: sz, maxRegions: 40) else {
                check(false, "garrison \(seed): a Boreal Station near \(sx),\(sz)"); continue
            }
            let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
            if i == 0 { check(cx == 1192 && cz == -1704, "garrison \(seed): his station is the one at 1192 -1704 (\(cx) \(cz))") }
            let S = s.min.y + BorealStation.depth + 4
            let site = BorealAlarmState.Site(cx: cx, cz: cz, S: S)
            let key = "boreal:\(cx),\(cz)"
            func garrison() -> [Mob] { g.mobs.mobs.filter { BorealMuster.soldier($0) && $0.health > 0 && BorealStation.insideSite(site, $0.pos) } }
            func play(_ secs: Float) {
                for k in 0..<Int(secs * 20) {
                    if k % 20 == 0 { _ = w.loadSync(center: g.player.pos, radius: 6) }     // (the harness outruns the workers)
                    g.tick(0.05)
                }
            }
            // In from 220 blocks south, flying, as he came.
            let from = V3(Float(cx) + 0.5, Float(S + 30), Float(cz + 220) + 0.5), to = V3(Float(cx) + 0.5, Float(S + 30), Float(cz + 40) + 0.5)
            g.player.pos = from; g.player.flying = true; g.player.vel = .zero
            w.activeCenter = from
            _ = w.loadSync(center: from, radius: 6)
            play(1)
            let legs = Int(simd_length(to - from) / 0.4)
            for k in 0..<legs {
                g.player.pos = from + (to - from) * (Float(k + 1) / Float(legs)); g.player.vel = .zero
                if k % 20 == 0 { _ = w.loadSync(center: g.player.pos, radius: 6) }
                g.tick(0.05)
            }
            g.player.pos = V3(Float(cx) + 0.5, Float(S + 1), Float(cz + 36) + 0.5); g.player.flying = false
            play(6)
            let m0 = BorealMuster.musters
            let there = garrison().count
            let t = g.bases.boreal.tally[key]
            check(there >= 20 && !g.bases.boreal.mustered.contains(key),
                  "garrison \(seed): flown in to the station at \(cx),\(cz), \(there) of its soldiers are there (admitted \(t?.admitted ?? 0)); none mustered")
            // Gone with no death and no stash (the station he found empty): mustered once from its plan.
            // (twice, a second apart: a soldier's stashed record restored in that second, or one who had stepped outside
            // the fence and back, is taken too: the station must stand empty, as he found it)
            func empty() {
                let gone = Set(garrison().map { ObjectIdentifier($0) })
                g.mobs.mobs.removeAll { gone.contains(ObjectIdentifier($0)) }
                for (k, rs) in g.mobs.stored {
                    g.mobs.stored[k] = rs.filter { r in
                        guard r.p.count == 3, let mk = MobKind.named(r.k), mk.steelhold, Soldier.rank(mk) != nil else { return true }
                        return !BorealStation.insideSite(site, V3(r.p[0], r.p[1], r.p[2]))
                    }
                }
                g.mobs.rebuildIndex()
            }
            // (cleared again each second until the muster: a stray who walks in, or a stashed record restored, would keep
            // the station from standing empty, as he found it)
            var strays: [String] = []
            empty()
            for _ in 0..<15 where BorealMuster.musters == m0 {
                play(1)
                if BorealMuster.musters == m0 { strays += garrison().map { $0.kind.key }; empty() }
            }
            play(1)
            let back = garrison().count
            let line = BorealMuster.lines.last ?? ""
            // (what the count saw, when it fails: soldiers' records stashed inside the station, its ground loaded, its state)
            let stashed = g.mobs.stored.values.reduce(0) { $0 + $1.filter { r in
                guard r.hp > 0, r.p.count == 3, let k = MobKind.named(r.k), k.steelhold, Soldier.rank(k) != nil else { return false }
                return BorealStation.insideSite(site, V3(r.p[0], r.p[1], r.p[2]))
            }.count }
            let st = g.bases.boreal
            let why = "stashed \(stashed), site known \(st.sites[key] != nil), mustered \(st.mustered.contains(key)), kills \(st.kills[key] ?? 0), "
                + "op \(st.ops[key].map { "cleared \($0.cleared) blown \($0.blown)" } ?? "none"), empty for \(st.tally[key]?.empty ?? -1) s, strays taken \(strays.isEmpty ? "none" : strays.joined(separator: ", "))"
            check(back >= 20 && BorealMuster.musters == m0 + 1 && line.contains(key),
                  "garrison \(seed): emptied, the station is garrisoned again: \(back) soldiers (\(line); \(why))")
            play(4)
            check(BorealMuster.musters == m0 + 1, "garrison \(seed): mustered once (\(BorealMuster.musters - m0))")
            if i == 0 {
                // His kills: a station he cleared stays empty (P430 e).
                for m in garrison() { m.killedByPlayer = true; m.health = 0; g.mobDied(m) }
                g.mobs.mobs.removeAll { $0.health <= 0 }
                g.bases.boreal.mustered.remove(key)
                play(6)
                check(garrison().count < 5 && BorealMuster.musters == m0 + 1,
                      "garrison \(seed): a station whose men he killed (\(g.bases.boreal.kills[key] ?? 0)) is not mustered again (\(garrison().count) stragglers there)")
                // Saved with the world: mustered and his kills.
                let d = g.saveExtra()
                check(d["borealKills"]?.contains(key) == true, "garrison \(seed): his kills there are saved (\(d["borealKills"] ?? "none"))")
            }
            w.unloadAll()
        }
        print(String(format: "garrison: %.1f s", CFAbsoluteTimeGetCurrent() - t0))
    }
}
