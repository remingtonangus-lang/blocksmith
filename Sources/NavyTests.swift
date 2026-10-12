import Foundation
import simd

// Navy checks (backlog A3; `questcheck --navy-only`, and part of every questcheck run): an Aegis Marine's shield soaks,
// flares, pops and recharges after its delay; a Pulse Charge pops shields in its radius and holds them down; arc beams
// tear shields at triple; the Pulse Charge is crafted and thrown; a hunting Meridian frigate lowers a boarding party
// with a shielded Aegis Marine; a captured frigate's pilot reads the radar.
enum NavyTests {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        shield(g, check)
        pulse(g, check)
        radar(g, check)
        boarding(g, check)
    }

    static func aegis(_ g: Game, _ at: V3) -> Mob {
        let m = Mob(.soldierIronclad, at: at)
        m.faction = Faction.meridian.rawValue
        m.navyTick(0, g)
        return m
    }

    static func shield(_ g: Game, _ check: (Bool, String) -> Void) {
        let at = g.player.pos + V3(30, 40, 0)
        let m = aegis(g, at)
        let h0 = m.health
        check(m.isAegis && m.shield == Navy.shieldMax && m.troopClass == .hannibal && m.spec.name == "Aegis Marine",
              "navy: a Meridian heavy is an \(m.spec.name) with a \(Int(m.shield)) shield over Hannibal plate")
        m.invulnerable = 0
        m.hit(from: at + V3(3, 0, 0), damage: 15)
        let soaked = m.health == h0 && m.shield == Navy.shieldMax - 15 && m.shieldFx == 1
        m.navyTick(0.05, g)
        m.invulnerable = 0
        m.hit(from: at + V3(3, 0, 0), damage: 35)                     // 25 left: pops, 10 through
        let popped = m.shield == 0 && m.health < h0 && m.shieldFx == 2
        check(soaked && popped, "navy: the shield soaks a 15 hit whole (flare), a 35 pops it and the rest goes through (\(h0) -> \(m.health) health)")
        var t: Float = 0
        m.navyTick(0.05, g)
        while m.shield == 0 && t < 10 { m.navyTick(0.05, g); t += 0.05 }
        var full: Float = 0
        while m.shield < Navy.shieldMax && full < 10 { m.navyTick(0.05, g); full += 0.05 }
        check(t >= Navy.rechargeDelay - 0.1 && t < Navy.rechargeDelay + 0.2 && abs(full - Navy.shieldMax / Navy.rechargeRate) < 0.3,
              String(format: "navy: the shield starts back %.1f s after the last hit and is full %.1f s later", t, full))
        var d: [String: Float] = [:]
        m.shield = 22
        m.saveExtra(&d)
        let back = Mob(.soldierIronclad, at: at); back.loadExtra(d)
        check(back.shieldMax == Navy.shieldMax && back.shield == 22, "navy: the shield is kept through a save (\(Int(back.shield)))")
    }

    static func pulse(_ g: Game, _ check: (Bool, String) -> Void) {
        let at = g.player.pos + V3(30, 40, 10)
        let near = aegis(g, at), far = aegis(g, at + V3(9, 0, 0))
        let mobs0 = g.mobs.mobs
        g.mobs.mobs = [near, far]
        defer { g.mobs.mobs = mobs0 }
        g.pulseBurst(at: at + V3(1.5, 1, 0))
        check(near.shield == 0 && near.shieldLock == Navy.pulseLock && far.shield == Navy.shieldMax,
              "navy: a Pulse Charge pops a shield 1.5 blocks off and leaves one 7.5 off")
        var t: Float = 0
        while near.shield == 0 && t < 20 { near.navyTick(0.05, g); t += 0.05 }
        check(t >= Navy.pulseLock - 0.1, String(format: "navy: a pulsed shield stays down %.1f s", t))
        // Arc beams: triple on the shield.
        let a = aegis(g, at + V3(0, 0, 6))
        g.mobs.mobs = [a]
        let o = a.pos + V3(-6, 1, 0)
        g.arms.beam(g, from: o, dir: simd_normalize(a.pos + V3(0, 1, 0) - o), range: 20, damage: 6, fromPlayer: true, shooter: nil, by: "test")
        check(abs(a.shield - (Navy.shieldMax - 18)) < 0.6, String(format: "navy: an arc beam of 6 takes %.0f off a shield", Navy.shieldMax - a.shield))
        // Crafted, and thrown: it bursts where it lands.
        let grid: [ItemID] = [Items.id("radar_module"), Items.id("copper_ingot"), Items.id("copper_ingot"), Items.id("redstone"), Items.id("redstone"), 0, 0, 0, 0]
        let craft = Recipes.match(grid, 3, 3)?.result
        check(craft.map { Items.key($0.item) } == Navy.pulseKey && craft?.count == 2, "navy: a radar module, two copper and two redstone make two Pulse Charges")
        let held0 = g.inventory.main[g.inventory.selected], surv0 = g.survival, pos0 = g.player.pos
        defer { g.inventory.main[g.inventory.selected] = held0; g.survival = surv0; g.player.pos = pos0 }
        g.survival = true
        g.player.pos = at + V3(-8, 0, 20); g.player.vel = .zero
        // (a stone floor under them: it bursts where it lands)
        let fy = Int(floor(g.player.pos.y)) - 1, fx = Int(floor(g.player.pos.x)), fz = Int(floor(g.player.pos.z))
        var floor: [IVec3] = []
        for z in (fz - 12)...(fz + 1) { for x in (fx - 3)...(fx + 3) where g.world.block(x, fy, z) == AIR { g.world.setBlock(x, fy, z, STONE); floor.append(IVec3(x, fy, z)) } }
        defer { for q in floor { g.world.setBlock(q.x, q.y, q.z, AIR) } }
        let tgt = aegis(g, g.player.pos + V3(0, 0, -5))
        g.mobs.mobs = [tgt]
        g.inventory.main[g.inventory.selected] = ItemStack(Items.id(Navy.pulseKey), 2)
        g.player.yaw = 0; g.player.pitch = -0.6
        let thrown = g.pulseChargeUse()
        let n0 = g.arms.slugs.count
        for _ in 0..<60 { g.arms.update(0.05, g) }
        check(thrown && g.inventory.main[g.inventory.selected].count == 1 && n0 >= 1 && tgt.shield == 0,
              "navy: a thrown Pulse Charge (one used) bursts and pops the shield of the marine it lands by (\(Int(tgt.shield)))")
    }

    static func radar(_ g: Game, _ check: (Bool, String) -> Void) {
        // The contacts a captured frigate's pilot reads, from spawn: bases within 1,500 blocks, nearest first.
        let cs = g.frigateContacts()
        let p = V2(g.player.pos.x, g.player.pos.z)
        let inRange = cs.allSatisfy { simd_length(V2(Float($0.x), Float($0.z)) - p) <= Navy.radarRange }
        let sorted = zip(cs, cs.dropFirst()).allSatisfy { simd_length(V2(Float($0.0.x), Float($0.0.z)) - p) <= simd_length(V2(Float($0.1.x), Float($0.1.z)) - p) }
        check(!cs.isEmpty && inRange && sorted && cs.contains { $0.kind == Greywall.kind },
              "navy: the frigate radar lists \(cs.count) contacts within 1,500 blocks, nearest first (\(cs.prefix(4).map { "\($0.name) \(g.radarBearing($0))" }.joined(separator: "; ")))")
        // ...and the bases on it go on the map.
        let marks0 = MapCache.shared.marks, toast0 = g.onToast
        g.onToast = { _ in }
        MapCache.shared.replaceMarks([])
        g.markRadarSites(cs)
        let bases = cs.filter { !$0.kind.hasPrefix("vessel_") }
        let marked = bases.filter { c in MapCache.shared.marks.contains { $0.kind == c.kind && abs($0.x - c.x) < 24 && abs($0.z - c.z) < 24 } }
        MapCache.shared.replaceMarks(marks0); g.onToast = toast0
        check(!bases.isEmpty && marked.count == bases.count, "navy: the \(bases.count) bases on the frigate radar go on the map (\(marked.count) marked)")
    }

    static func boarding(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let home = g.player.pos, surv0 = g.survival, mobs0 = g.mobs.mobs
        defer { g.player.pos = home; g.survival = surv0; g.mobs.mobs = mobs0; _ = w.loadSync(center: home, radius: 8) }
        let n0 = w.ships.list.count
        w.ships.spawnCapital("capfrigate", home: IVec3(Int(home.x) + 200, 0, Int(home.z)), yaw: 0.7, region: nil, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "capfrigate" }), let st = w.ships.capState[s.id] else {
            check(false, "navy boarding: the Meridian frigate spawns"); return
        }
        defer { w.ships.remove(s); w.ships.capState.removeValue(forKey: s.id) }
        let a = FrigateBoarding.anchor(s)
        _ = w.loadSync(center: a, radius: 3)
        g.survival = true
        g.player.pos = V3(a.x + 20, Float(w.topY(Int(floor(a.x + 20)), Int(floor(a.z))) + 1), a.z)
        g.mobs.mobs = []
        st.target = CapTarget(point: g.player.pos, vel: .zero, player: true)
        var counts: [Int] = []
        for _ in 0..<3 {
            st.partyCD = 0
            w.ships.boardingParty(s, st, 0.05, g)
            counts.append(g.mobs.mobs.count)
        }
        let aegis = g.mobs.mobs.filter { $0.isAegis }
        let grounded = g.mobs.mobs.allSatisfy { abs($0.pos.y - g.player.pos.y) < 12 }
        check(counts == [3, 6, 6] && aegis.count == 2 && aegis.allSatisfy { $0.shield == Navy.shieldMax } && grounded,
              "navy boarding: a hunting frigate lowers two parties of three (\(counts)), each led by a shielded Aegis Marine, then no more")
    }
}
