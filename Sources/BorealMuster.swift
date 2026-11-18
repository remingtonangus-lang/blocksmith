import Foundation
import simd

// Ledger 253 (Nov 17 evening playtest, 20:02:25-20:03:31, a Boreal Station at 1190 -1690 on seed 4259144782798118884:
// "Why is there no one here? ... No one's in this Boreal station ... there's just no troops there ... that's a big one
// for store release"): he walked the yard and the bunker with the alarm sounding and the ceiling guns firing, and not one
// soldier of the station's 25 was there. On the host the same station, reached the same ways (a fresh world, a world
// closed and opened again, flown in at his speed in real time, views 6 and 12, kept on disk), always holds all 25; the
// headset's own path to an empty station isn't known.
//
// So the station keeps count, and makes sure. Every garrison soldier that comes into the world inside a station's fence
// or bunker is counted for that station (admitted), and so is each that dies there (by him or not) and each taken out
// of the world without dying (stashed with unloaded ground, despawned, routed: TroopVanish's rules). Once a second, with
// a player within 120 blocks and the whole station loaded, a station with nobody of its garrison alive inside it or
// stashed there for 3 s, that he has not fought (fewer than 5 of its soldiers killed by him, never cleared, generator
// not blown) and that has not been mustered before, is garrisoned again from its plan: the same men at the same posts
// as generation puts them (BorealStation.garrisonPlan). The log line says what the count saw ("boreal: <key> had no
// garrison (admitted A, died D (by him P), left: rules); mustered N"), so the next headset log names the path.
// A station he cleared stays empty (P430 e). Mustered and fought stations are saved with the world.
// BS_OLDMUSTER=1: never mustered (the count still runs).
enum BorealMuster {
    static let oldMuster = Env.all["BS_OLDMUSTER"] == "1"
    static let near: Float = 120
    static let emptyFor: Float = 3
    static let foughtAt = 5                      // his kills there that make it a station he fought
    struct Tally { var admitted = 0, died = 0, byHim = 0; var left: [String: Int] = [:]; var empty: Float = 0 }
    static var musters = 0                       // (checks)
    static var lines: [String] = []              // (checks: every muster's line)

    static func soldier(_ m: Mob) -> Bool { m.kind.steelhold && m.kind != .deckGun && !m.kind.ashVehicle && Soldier.rank(m.kind) != nil }

    // The station whose fence or bunker holds p (its key and site), from the plan (no world scan).
    static func site(_ g: Game, _ p: V3) -> (String, BorealAlarmState.Site)? {
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures,
              let s = sc.nearestIfReady(BorealStation.kind, x: Int(floor(p.x)), z: Int(floor(p.z))) else { return nil }
        let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
        let site = BorealAlarmState.Site(cx: cx, cz: cz, S: s.min.y + BorealStation.depth + 4)
        guard BorealStation.insideSite(site, p) else { return nil }
        return ("boreal:\(cx),\(cz)", site)
    }

    // Game.tick: a structure mob just admitted.
    static func admitted(_ g: Game, _ m: Mob) {
        guard soldier(m), let (key, _) = site(g, m.pos) else { return }
        g.bases.boreal.tally[key, default: Tally()].admitted += 1
    }
    // Game.mobDied.
    static func died(_ g: Game, _ m: Mob) {
        guard soldier(m), let (key, _) = site(g, m.pos) else { return }
        let st = g.bases.boreal
        st.tally[key, default: Tally()].died += 1
        if m.killedByPlayer {
            st.tally[key, default: Tally()].byHim += 1
            st.kills[key, default: 0] += 1
        }
    }
    // TroopVanish.note: taken out of the world without dying, by `rule`.
    static func left(_ g: Game, _ m: Mob, _ rule: String) {
        guard soldier(m), let (key, _) = site(g, m.pos) else { return }
        g.bases.boreal.tally[key, default: Tally()].left[rule, default: 0] += 1
    }

    // borealAlarmTick, once a second for each station it knows (loaded round its centre).
    static func tick(_ g: Game, _ key: String, _ site: BorealAlarmState.Site, _ players: [V3], _ dt: Float) {
        let st = g.bases.boreal
        guard !st.mustered.contains(key), (st.kills[key] ?? 0) < foughtAt else { return }
        if let op = st.ops[key], op.cleared || op.blown { return }
        let c = V2(Float(site.cx), Float(site.cz))
        guard players.contains(where: { simd_length(V2($0.x, $0.z) - c) < near }) else { st.tally[key]?.empty = 0; return }
        // The whole station loaded with its blocks (not shells): its garrison would be in the world if it were anywhere.
        let w = g.world, R = BorealStation.yard + 2
        for dz in stride(from: -R, through: R + CS - 1, by: CS) { for dx in stride(from: -R, through: R + CS - 1, by: CS) {
            let x = site.cx + min(dx, R), z = site.cz + min(dz, R)
            guard let ch = w.chunks[ChunkKey(x: floorDiv(x, CS), z: floorDiv(z, CS))], !ch.hollow else { st.tally[key]?.empty = 0; return }
        } }
        let live = g.mobs.mobs.contains { soldier($0) && $0.health > 0 && BorealStation.insideSite(site, $0.pos) }
        let stashed = !live && g.mobs.stored.values.contains { rs in rs.contains { r in
            guard r.hp > 0, r.p.count == 3, let k = MobKind.named(r.k), k.steelhold, k != .deckGun, Soldier.rank(k) != nil else { return false }
            return BorealStation.insideSite(site, V3(r.p[0], r.p[1], r.p[2]))
        } }
        guard !live && !stashed else { st.tally[key]?.empty = 0; return }
        var t = st.tally[key] ?? Tally()
        t.empty += dt
        st.tally[key] = t
        guard t.empty >= emptyFor else { return }
        let left = t.left.isEmpty ? "none" : t.left.keys.sorted().map { "\($0) \(t.left[$0]!)" }.joined(separator: ", ")
        var line = "boreal: \(key) had no garrison (admitted \(t.admitted), died \(t.died) (by him \(t.byHim)), left: \(left))"
        if oldMuster {
            st.mustered.insert(key)             // (told once)
            line += "; not mustered (BS_OLDMUSTER)"
        } else {
            let n = muster(g, site)
            st.mustered.insert(key)
            musters += 1
            line += "; mustered \(n)"
        }
        print(line)
        st.log.append(line)
        lines.append(line)
    }

    // The station's soldiers at their posts, as generation puts them. Returns how many came.
    static func muster(_ g: Game, _ site: BorealAlarmState.Site) -> Int {
        let grey = (g.world.gen as? WorldGen).map { WorldRules.p69($0, floorDiv(site.cx, CS), floorDiv(site.cz, CS), reach: 4) } ?? false
        var n = 0
        for (name, dx, y, dz) in BorealStation.garrisonPlan(grey: grey, S: site.S) {
            let at = g.world.freeSpawn(V3(Float(site.cx + dx) + 0.5, Float(y), Float(site.cz + dz) + 0.5))
            guard let m = Mob.structureMob(name, at: at) else { continue }
            g.mobs.admit(m, g.world)
            n += 1
        }
        g.mobs.rebuildIndex()
        return n
    }
}
