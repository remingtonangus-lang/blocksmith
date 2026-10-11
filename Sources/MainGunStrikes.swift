import Foundation
import simd

// Targets worth hitting with the Tidebreaker (the gap pass, EF2: "targets worth hitting: enemy ships, the Capital and
// military bases"). Ships already take the slug through the hull (ShipCombat). On land:
//   the blast is heard   the impact is a power-16 explosion on the noise bus (Game.baseNoise): a Capital citadel inside
//                        the blast goes to lockdown (alarm, turret crews, dropships, the Kestrel), one near it sends
//                        patrols and the crawler; Boreal Station's alarm goes off
//   the strike report    once the shockwave has passed, a report: what was hit (the citadel, a Capital city by name,
//                        Boreal Station) and how many of the Capital's soldiers fell
//   breaking a citadel   a citadel hit three times, or that has lost 16 of its garrison to the gun, is broken: no more
//                        dropships, its craters are never rebuilt; the player earns "Siege Breaker". Saved with the
//                        citadel's record (BaseRecord.strikes / lost / broken).
enum MainGunStrikes {
    struct Site { let key: String?; let name: String; var city = false }
    static let breakStrikes = 3, breakLosses = 16
    static var reports: [String] = []                  // harness
    static var brokenCount = 0

    // What a slug landing at p struck: the nearest citadel if p is inside its walls or within the shockwave of them
    // (its record is made if no player was near enough for it to be watched yet), a Capital city, Boreal Station.
    // Plans the structure regions `site` looks at round `p` (a worker, during the charge; the cache is locked).
    static func prewarm(_ sc: StructureCache, at p: V3) {
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        for kind in ["military_base", "capital_city", BorealStation.kind] { _ = sc.nearest(kind, x: x, z: z, maxRegions: 1) }
    }

    static func site(_ g: Game, at p: V3) -> Site? {
        guard g.world.dim == .overworld, let sc = g.world.gen.structures else { return nil }
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        if let s = sc.nearest("military_base", x: x, z: z, maxRegions: 1) {
            let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
            let reach = Float(CapitalBase.A) + MainGun.shockRadius * 0.5
            if abs(p.x - Float(cx)) < reach && abs(p.z - Float(cz)) < reach {
                let key = "citadel:\(cx),\(cz)"
                let b = g.bases
                if b.records[key] == nil { b.records[key] = BaseRecord(key: key, cx: cx, cz: cz, y0: s.min.y + 20, lastTick: g.clock) }
                return Site(key: key, name: "the Capital citadel")
            }
        }
        if let c = CapitalTown.city(g, x: x, z: z) { return Site(key: nil, name: c, city: true) }
        if let s = sc.nearest(BorealStation.kind, x: x, z: z, maxRegions: 1) {
            let cx = Float(s.min.x + s.max.x) / 2, cz = Float(s.min.z + s.max.z) / 2
            if abs(p.x - cx) < Float(BorealStation.yard) + MainGun.shockRadius * 0.5 && abs(p.z - cz) < Float(BorealStation.yard) + MainGun.shockRadius * 0.5 {
                return Site(key: nil, name: BorealStation.display)
            }
        }
        return nil
    }

    // The front has passed: count the fallen, credit the citadel, maybe break it, tell the player. Only a slug the
    // player fired (from the helm, or by the ship they're aboard) counts: a Meridian frigate shelling the player beside
    // a citadel still makes the citadel hear it (the noise bus), but breaks nothing and earns nothing.
    static func report(_ g: Game, _ w: Shockwave) {
        let dead = w.hit.filter { $0.health <= 0 }
        w.hit.removeAll()
        guard w.byPlayer else { return }
        // The Capital's own soldiers (another navy's crew or the Ashguard are not the Capital's garrison).
        let fallen = dead.filter { $0.kind.steelhold && !$0.kind.ash && $0.factionValue == .steelhold }.count
        let folk = dead.filter { $0.kind == .villager && $0.villager?.person != nil }.count
        var line: String
        if let site = w.site {
            line = "Tidebreaker hit on \(site.name): \(fallen) of the garrison down"
            if let key = site.key, var r = g.bases.records[key] {
                r.strikes = (r.strikes ?? 0) + 1
                r.lost = (r.lost ?? 0) + fallen
                if r.broken != true && ((r.strikes ?? 0) >= breakStrikes || (r.lost ?? 0) >= breakLosses) {
                    r.broken = true
                    brokenCount += 1
                    g.bases.note("\(key) broken by the Tidebreaker (\(r.strikes ?? 0) hits, \(r.lost ?? 0) lost)")
                    g.achieve("citadel_broken")
                    line = "The citadel is broken: \(r.lost ?? 0) of its garrison down. No more reinforcements, and its walls stay down"
                } else if r.broken != true {
                    line += " (hit \(r.strikes ?? 0) of \(breakStrikes) to break it)"
                } else {
                    line += " (already broken)"
                }
                g.bases.records[key] = r
            } else if site.city {
                line = shellCity(g, site.name, at: w.center, folk: folk, soldiers: fallen)
            }
        } else if fallen > 0 {
            line = "Tidebreaker: \(fallen) Capital soldiers down"
        } else {
            return
        }
        reports.append(line)
        if reports.count > 32 { reports.removeFirst() }
        g.onToast?(line)                                   // the player fired it: always told
    }

    // A Capital city shelled by the player: the city turns on them (its law and armed townsfolk fight, the rest flee;
    // the usual bounty), every townsperson killed is a murder on their honour and their head, and the Capital's
    // garrison is counted like a citadel's. Creative play: only the report.
    static var citiesShelled = 0
    static func shellCity(_ g: Game, _ city: String, at p: V3, folk: Int, soldiers: Int) -> String {
        citiesShelled += 1
        let killed = folk > 0 ? ", \(folk) of its people killed" : ""
        guard g.survival else { return "Tidebreaker hit on \(city): \(soldiers) of the garrison down\(killed)" }
        let witness = g.mobs.mobs.filter { TownLaw.isTownsperson($0) && TownLaw.town(of: $0, g) == city }
            .min { simd_length($0.pos - p) < simd_length($1.pos - p) }
        if let wtn = witness {
            TownLaw.turnHostile(g, city, at: wtn.pos, witness: wtn)
        } else {
            let fresh = !TownLaw.isHostile(city)
            TownLaw.state.hostile[city] = TownLaw.hostileSeconds
            TownLaw.state.heat[city] = TownLaw.hostileHeat
            if fresh { Honour.townTurned(g, city) }
        }
        if folk > 0 {
            Honour.change(g, -Float(min(40, 15 * folk)), "you shelled \(city)")
            Honour.addBounty(g, city, 1500 * folk)
        }
        return "Tidebreaker hit on \(city): \(soldiers) of the garrison down\(killed). \(city) has turned on you"
    }
}
