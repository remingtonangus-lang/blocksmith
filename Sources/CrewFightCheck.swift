import Foundation
import simd

// P471 (Oct 26 19:46, aboard a frigate: "These guys aren't even shooting at me. We're just standing here... Even after I
// shot a round, he equipped his gun, but he's not shooting me"): `questcheck --crewfight` puts him on a Meridian
// frigate's deck by its crew in survival and reports what each crewman near him does.
enum CrewFightCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let home = g.player.pos
        g.paused = false; g.menu = nil
        g.player.flying = true
        let n0 = w.ships.list.count
        w.ships.spawnCapital("capfrigate", home: IVec3(Int(floor(home.x)), 0, Int(floor(home.z)) + 60), yaw: 0, region: nil, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "capfrigate" }), let st = w.ships.capState[s.id] else {
            check(false, "crewfight: the frigate spawns"); return
        }
        g.player.pos = s.pos + V3(0, 30, 0)
        _ = w.loadSync(center: s.pos, radius: 6)
        for _ in 0..<(3 * 72) { g.tick(1.0 / 72) }
        let crew = st.crewMobs.values.filter { $0.health > 0 && $0.deck === s }
        print("crewfight: frigate at \(Int(s.pos.x)) \(Int(s.pos.y)) \(Int(s.pos.z)), \(crew.count) crew of \(st.crew.count) posts")
        // Beside the crewman with the most open deck round him: the first spot 5 blocks off he can see from his eye.
        var spot: V3?, who: Mob?
        search: for m in crew.sorted(by: { $0.pos.y > $1.pos.y }) {
            for k in 0..<8 {
                let a = Float(k) * .pi / 4
                let p = m.pos + V3(cosf(a) * 5, 0, sinf(a) * 5)
                if w.canSee(m.eye, p + V3(0, 1.6, 0)) && w.ships.segmentHit(p + V3(0, 0.2, 0), V3(0, 1, 0), 1.6, except: -1) == nil
                    && w.ships.segmentHit(p + V3(0, 0.4, 0), V3(0, -1, 0), 0.8, except: -1) != nil { spot = p; who = m; break search }
            }
        }
        guard let p = spot, let m = who else { check(false, "crewfight: no open deck beside a crewman"); return }
        g.survival = true
        g.player.pos = p
        g.health = 20; g.alive = true
        // An ally's crew holds fire; a round fired past one of them ends it (P471: "he equipped his gun, but he's not
        // shooting me").
        let f = s.factionValue
        let rep0 = FactionRep.rep[f.rawValue]
        FactionRep.rep[f.rawValue] = FactionRep.allyAt + 20
        var held = 0, after = 0
        Game.onDamage = { a, _ in held += a }
        for _ in 0..<(3 * 72) { g.tick(1.0 / 72); g.health = 20; g.alive = true }
        let gi = Guns.all.firstIndex { $0.key == "gun_rifle" } ?? 0
        let held0 = g.inventory.held
        var gun = ItemStack(Items.id("gun_rifle"), 1); gun.tag = 10
        g.inventory.held = gun
        let chest = m.pos + V3(0, m.height * 0.6, 0)
        let side = simd_normalize(simd_cross(chest - g.player.eye, V3(0, 1, 0)))
        g.vrAim = (g.player.eye, simd_normalize(chest + side * 1.5 - g.player.eye))
        g.arms.lastNoise = -100
        let shots0 = g.arms.slugs.count
        g.fireHeldGun(gi)
        g.vrAim = nil; g.inventory.held = held0
        print("crewfight: the round past him: fired \(g.arms.slugs.count - shots0), provoked \(m.provokedAt == g.clock), allied after \(g.repAllied(m)), aggro \(m.aggro), "
              + "\(String(format: "%.1f", simd_length(chest - g.player.eye))) blocks off")
        Game.onDamage = { a, _ in after += a }
        for _ in 0..<(8 * 72) { g.tick(1.0 / 72); g.health = 20; g.alive = true }
        Game.onDamage = nil
        check(held == 0 && after > 0, "crewfight: an ally's crewman holds fire (\(held) damage in 3 s) until a round goes past him (then \(after) damage in 8 s)")
        if let r = rep0 { FactionRep.rep[f.rawValue] = r } else { FactionRep.rep.removeValue(forKey: f.rawValue) }
        var damage = 0
        Game.onDamage = { a, _ in damage += a }
        for i in 0..<(10 * 72) {
            g.tick(1.0 / 72)
            g.health = 20; g.alive = true
            if i % 72 == 0 {
                for c in crew where simd_length(c.pos - g.player.pos) < 24 {
                    let b = c.soldierBrain
                    print(String(format: "crewfight:   %ds %@%@ %.1f off: aggro %@ sees %@ mag %d react %.2f post %@ free %@ station %d gun %d canSee %@ clearShot %@",
                                 i / 72, c === m ? "*" : " ", c.kind.name, simd_length(c.pos - g.player.pos), c.aggro ? "y" : "n", b.sees ? "y" : "n", b.mag, b.react,
                                 c.crewPost == nil ? "-" : "y", c.crewFree ? "y" : "n", b.station.rawValue, b.gun,
                                 w.canSee(c.eye, g.player.eye) ? "y" : "n", w.clearShot(SoldierRig.muzzleWorld(c), g.player.eye - V3(0, 0.3, 0)) ? "y" : "n"))
                }
            }
        }
        Game.onDamage = nil
        check(damage > 0, "crewfight: on the frigate's deck by its crew in survival he takes \(damage) damage in 10 s")
        g.survival = false
        w.ships.remove(s); w.ships.capState.removeValue(forKey: s.id)
    }
}
