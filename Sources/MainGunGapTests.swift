import Foundation
import simd

// The Tidebreaker, the gap pass (docs/status/cloud-gap-pass.md, area F), run at the end of MainGunTests:
//   EF4  Blast Shake (VR comfort page): the eye jolt is there with it on and gone with it off
//   EF2  a slug into a Capital citadel: the citadel hears it (lockdown), the strike report counts the garrison the
//        shockwave killed, and the third hit breaks it (no dropships, no rebuilding, "Siege Breaker"); saved
extension MainGunTests {
    static func gap(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        // Blast Shake.
        do {
            let was = g.vrShake
            g.shake = 0.8
            g.vrShake = true
            let on = simd_length(g.shakeVR)
            g.vrShake = false
            let off = simd_length(g.shakeVR)
            g.vrShake = was
            g.shake = 0
            check(on > 0.001 && off == 0, String(format: "maingun gap: Blast Shake on jolts the eyes (%.1f mm), off keeps them still (%.1f mm)", on * 1000, off * 1000))
        }
        // A citadel struck three times.
        guard let sc = w.gen.structures,
              let s = sc.nearest("military_base", x: Int(g.player.pos.x), z: Int(g.player.pos.z), maxRegions: 2) else {
            check(false, "maingun gap: a citadel to strike"); return
        }
        let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2, y0 = s.min.y + 20
        let centre = V3(Float(cx) + 0.5, Float(y0 + 5), Float(cz) + 0.5)
        _ = w.loadSync(center: centre, radius: 6)
        w.pendingMobs.removeAll()
        let savedMobs = g.mobs.mobs, wasSurvival = g.survival, wasToast = g.onToast, hadAdv = g.advancements.contains("adventure/break_citadel")
        var toasts: [String] = []
        g.onToast = { toasts.append($0) }
        g.survival = false
        g.player.flying = true
        g.player.pos = centre + V3(0, 30, 150)                  // outside the walls, near enough to see it
        let key = "citadel:\(cx),\(cz)"
        let ships0 = w.ships.list.count
        defer {
            for e in w.ships.list.dropFirst(ships0) { w.ships.remove(e) }
            g.mobs.mobs = savedMobs; g.survival = wasSurvival; g.onToast = wasToast
            g.bases.records[key] = nil
            w.ships.shockwaves.removeAll()
            if !hadAdv { g.advancements.remove("adventure/break_citadel") }
        }
        func strike(_ n: Int, byPlayer: Bool = true, foreign: Bool = false) -> Int {
            let x = Int(centre.x) + (n - 1) * 14, z = Int(centre.z)
            let p = V3(Float(x) + 0.5, Float(w.topY(x, z) + 1), Float(z) + 0.5)
            var squad: [Mob] = []
            for k in 0..<6 {
                let a = Float(k) * 1.047
                let q = p + V3(cosf(a) * 8, 0, sinf(a) * 8)
                let m = Mob(Soldier.garrison(.soldierRecruit, at: q), at: V3(q.x, Float(w.topY(Int(floor(q.x)), Int(floor(q.z))) + 1), q.z))
                if foreign { m.faction = Faction.meridian.rawValue }   // another navy's crew: not the Capital's garrison
                squad.append(m)
            }
            g.mobs.mobs = squad
            w.ships.mainGunImpact(at: p, owner: -1, game: g)
            w.ships.shockwaves.last?.byPlayer = byPlayer             // as if fired from the player's helm (or an AI's)
            var f = 0
            let wv = w.ships.shockwaves.last                         // (this strike's wave, whatever else is added after it)
            while !(wv?.reported ?? true) && f < 600 { w.ships.updateShockwaves(1.0 / 72, game: g); f += 1 }
            w.ships.shockwaves.removeAll()
            return squad.filter { $0.health <= 0 }.count
        }
        MainGunStrikes.reports.removeAll()                       // (the list keeps the last 32: a full list never grows)
        w.ships.pendingCraters.removeAll(); w.ships.pendingAlong.removeAll()                       // (earlier off-world hits dug as their ground loads: their own waves)
        let reports0 = MainGunStrikes.reports.count
        let dead1 = strike(1)
        g.basesTick(1.1)                                           // the citadel hears the blast
        let r1 = g.bases.records[key]
        let first = MainGunStrikes.reports.count > reports0 ? MainGunStrikes.reports.last! : "none"
        check(r1?.alert == .lockdown && r1?.strikes == 1 && (r1?.lost ?? 0) == dead1 && dead1 > 0 && first.contains("citadel") && first.contains("\(dead1) of the garrison"),
              "maingun gap: a slug into a citadel puts it on lockdown and reports the garrison it killed (\"\(first)\"; alert \(r1?.alert.name ?? "none"), strikes \(r1?.strikes ?? -1), lost \(r1?.lost ?? -1), killed \(dead1), site \(MainGunStrikes.site(g, at: centre)?.key ?? "none") vs \(key))")
        check(toasts.contains(first), "maingun gap: the strike report is shown to the player near it")
        // A Meridian frigate's slug (not the player's): heard, but no strike, no report, no credit.
        let reportsAI = MainGunStrikes.reports.count
        _ = strike(2, byPlayer: false)
        let rAI = g.bases.records[key]
        check(rAI?.strikes == 1 && rAI?.lost == r1?.lost && MainGunStrikes.reports.count == reportsAI,
              "maingun gap: an AI frigate's slug on the citadel isn't credited to the player (strikes \(rAI?.strikes ?? 0))")
        // Another navy's crew killed by the player's slug: not counted as the Capital's garrison.
        let deadForeign = strike(2, foreign: true)
        let r2 = g.bases.records[key]
        check(deadForeign > 0 && r2?.lost == r1?.lost && (MainGunStrikes.reports.last ?? "").contains("0 of the garrison"),
              "maingun gap: \(deadForeign) Meridian crew killed don't count as the citadel's losses (\(r2?.lost ?? -1) lost)")
        let broken0 = MainGunStrikes.brokenCount
        _ = strike(3)
        let r3 = g.bases.records[key]
        check(r3?.broken == true && MainGunStrikes.brokenCount == broken0 + 1 && g.advancements.contains("adventure/break_citadel")
              && (MainGunStrikes.reports.last ?? "").contains("broken"),
              "maingun gap: the third hit breaks the citadel (\(r3?.strikes ?? 0) hits, \(r3?.lost ?? 0) of its garrison lost) and earns Siege Breaker")
        if var r = r3 {
            r.dropshipCD = 0; r.dropships = 0
            let dmg = r.damage.count
            g.baseRebuild(&r, g.bases, 5, away: 0)
            check(r.damage.count == dmg && r.rebuilt == 0, "maingun gap: a broken citadel's craters aren't rebuilt (\(dmg) blasts kept)")
            let data = try? JSONEncoder().encode(r)
            let back = data.flatMap { try? JSONDecoder().decode(BaseRecord.self, from: $0) }
            check(back?.broken == true && back?.strikes == r.strikes && back?.lost == r.lost, "maingun gap: the citadel stays broken through a save")
        }
        // A Capital city shelled by the player turns on them: hostile, bounty, honour lost for the townsfolk killed.
        if let cs = sc.nearest("capital_city", x: Int(g.player.pos.x), z: Int(g.player.pos.z), maxRegions: 3),
           let plan = cs.plan as? CapitalCity.Plan {
            let a = CapitalCity.N * CapitalCity.lot
            let cp = V3(Float(plan.ox + a), 80, Float(plan.oz + a))
            let site = MainGunStrikes.site(g, at: cp)
            let city = site?.name ?? "?"
            let law = TownLaw.state, hon = Honour.value
            g.survival = true
            let line = MainGunStrikes.shellCity(g, city, at: cp, folk: 2, soldiers: 1)
            check(site?.city == true && TownLaw.isHostile(city) && Honour.bounty(city) == 500 + 3000 && Honour.value < hon && line.contains("turned on you"),
                  "maingun gap: shelling \(city) turns it on you (bounty \(Money.format(Honour.bounty(city))), honour \(Int(hon)) -> \(Int(Honour.value))): \"\(line)\"")
            TownLaw.state = law; Honour.value = hon
            g.survival = false
        } else {
            check(false, "maingun gap: a Capital city to shell")
        }
        // An old save's citadel record (no strike fields) still loads.
        let old = #"{"key":"citadel:1,2","cx":1,"cz":2,"y0":60}"#
        let rec = try? JSONDecoder().decode(BaseRecord.self, from: Data(old.utf8))
        check(rec != nil && rec?.broken == nil, "maingun gap: an old citadel record loads")
    }
}
