import Foundation
import simd

// Outposts and liberation (backlog O1), `questcheck --liberation-only`: an outlaw camp with its outlaws dead is freed
// when the player walks in (a map mark, a reward, a trader), and its fire carries the player to another freed camp.
enum LiberationTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        guard let sc = g.world.gen.structures, let t = sc.types.first(where: { $0.name == "wild_camp" }) else { check(false, "liberation: no camps"); return }
        var camp: StructureStart?
        search: for r in 0...8 { for rz in -r...r { for rx in -r...r where max(abs(rx), abs(rz)) == r {
            if let s = sc.start(t, regionX: rx, regionZ: rz), s.kind == "camp_outlaws" { camp = s; break search }
        } } }
        guard let s = camp else { check(false, "liberation: no outlaw camp within 8 regions"); return }
        let marks0 = MapCache.shared.marks, mobs0 = g.mobs.mobs, pos0 = g.player.pos, money0 = g.money, surv0 = g.survival
        defer { MapCache.shared.replaceMarks(marks0); g.mobs.mobs = mobs0; g.player.pos = pos0; g.money = money0; g.survival = surv0 }
        g.survival = true
        let c = V3(Float(s.anchor.x) + 0.5, Float(s.anchor.y), Float(s.anchor.z) + 0.5)
        g.player.pos = c + V3(3, 0, 3)
        // An outlaw still standing keeps the camp; once it is gone the camp is freed.
        let outlaw = Mob(.vindicator, at: c + V3(-2, 0, 1))
        g.mobs.mobs = [outlaw]
        Liberation.lastScan = -10; g.liberationTick()
        let heldWhileGuarded = !Liberation.freed(s.anchor.x, s.anchor.z)
        outlaw.health = 0
        g.mobs.mobs = []
        Liberation.lastScan = -10; g.liberationTick()
        let freed = Liberation.freed(s.anchor.x, s.anchor.z)
        let trader = g.mobs.mobs.contains { $0.kind == .villager }
        check(heldWhileGuarded && freed && trader && g.money == money0 + Liberation.reward,
              "liberation: the outlaw camp at \(s.anchor.x), \(s.anchor.z) holds while an outlaw stands (\(heldWhileGuarded)), is freed once clear (\(freed)) with a trader (\(trader)) and the reward")
        // A second freed camp 600 blocks east: the first one's fire offers it, and a second use goes there.
        MapCache.shared.discover(g, kind: Liberation.kind, x: s.anchor.x + 600, z: s.anchor.z, name: "Freed camp")
        let fire = IVec3(s.anchor.x, s.anchor.y, s.anchor.z + 2)
        Liberation.offer = nil
        let offered = g.campTravelUse(fire) && Liberation.offer != nil
        let went = g.campTravelUse(fire)
        let d = simd_length(V2(g.player.pos.x - Float(s.anchor.x + 600), g.player.pos.z - Float(s.anchor.z)))
        check(offered && went && d < 5, String(format: "liberation: a freed camp's fire offers the other freed camp, then rides there (%.1f blocks off)", d))
    }
}
