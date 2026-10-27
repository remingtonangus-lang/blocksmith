import Foundation
import simd

// The Oct 12 noon voice notes (backlog P101-P105): run with the Oct 12 AM checks (--p12-only).
enum PlaytestOct12NoonTests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        twinBarrels(game, check)
        gunDamage(game, check)
        wallBreach(game, check)
        greywallArms(game, check)
        handling(check)
    }

    // P104: Greywall's troops carry Greywall's guns (Slate Rounds, never the Capital's), drop them, keep them through
    // a save, take them on load when saved with a Capital gun, and its bases' chests hold them.
    static func greywallArms(_ g: Game, _ check: (Bool, String) -> Void) {
        let p = g.player.pos + V3(0, 40, 0)
        var bad: [String] = [], seen: Set<String> = []
        for k in ["soldier_recruit", "soldier_trooper", "soldier_marksman", "soldier_ironclad", "soldier_officer", "soldier_crew"] {
            for t in [Greywall.Tier.outpost, .command] {
                for i in 0..<6 {
                    let q = p + V3(Float(i * 3), 0, Float(t.rawValue * 5))
                    guard let m = Mob.structureMob("\(k)@grey\(Greywall.leashTag(Int(q.x), Int(q.z), t))", at: q) else { bad.append("\(k): none"); continue }
                    let gs = Guns.all[m.soldierBrain.gun]
                    seen.insert(gs.key)
                    if !Guns.isGreyArm(m.soldierBrain.gun) || gs.ammo == "capital_rounds" { bad.append("\(k): \(gs.key)") }
                }
            }
        }
        // A kill drops Greywall's ammunition.
        let m = Mob.structureMob("soldier_recruit@grey", at: p)!
        g.mobs.mobs.append(m)
        let d0 = g.drops.items.count
        m.health = 0
        g.soldierDied(m)
        let dropped = g.drops.items.dropFirst(d0).map { Items.def($0.stack.item).name }
        g.mobs.mobs.removeAll { $0 === m }
        g.drops.items.removeAll()
        // Saved before P104 with the Capital's service rifle: rearmed on load; a Capital soldier keeps his.
        var rec = m.record
        rec.extra?["variant"] = Float(Guns.rifle)
        let back = Mob.from(rec)
        let cap = Mob(.soldierRecruit, at: p); cap.variant = Guns.rifle; cap.faction = Faction.steelhold.rawValue
        let capBack = Mob.from(cap.record)
        let chests = Greywall.loot.values.flatMap { $0.entries.map { $0.0 } }
        let capitalInChests = chests.filter { ["capital_rounds", "gun_rifle", "gun_smg", "gun_sidearm", "gun_shotgun"].contains($0) }
        let models = (Guns.slatefall...Guns.repeater).allSatisfy { !Guns.models[$0].isEmpty && TextureGen.painters()["item_" + Guns.all[$0].key] != nil }
        check(bad.isEmpty && seen.count >= 4 && dropped.contains("greywall_rounds") && back.map { Guns.isGreyArm($0.variant) } == true
              && capBack?.variant == Guns.rifle && capitalInChests.isEmpty && models,
              "P104 Greywall arms: 72 Greywall soldiers carry \(seen.sorted().joined(separator: ", ")) \(bad.isEmpty ? "" : "(wrong: \(bad.prefix(3)))"); "
              + "a kill drops \(dropped); saved with a Capital rifle it loads with \(back.map { Guns.all[$0.variant].key } ?? "nothing") "
              + "(a Capital soldier keeps \(capBack.map { Guns.all[$0.variant].key } ?? "nothing")); Capital kit in its chests \(capitalInChests); models and icons \(models)")
    }

    // P105: at least three pistols that differ in range, kick and damage, the harder-hitting ones kicking harder, the
    // same ladder across rifles; a soldier's aim opens by the kick except a Hannibal trooper's.
    static func handling(_ check: (Bool, String) -> Void) {
        func ladder(_ keys: [String]) -> (Bool, String) {
            let gs = keys.compactMap { k in Guns.all.first { $0.key == k } }
            var ok = gs.count == keys.count
            for i in 1..<gs.count where !(gs[i].damage > gs[i - 1].damage && gs[i].recoil > gs[i - 1].recoil) { ok = false }
            ok = ok && Set(gs.map { $0.range }).count >= 3
            return (ok, gs.map { "\($0.name) \(Int($0.damage))/\(String(format: "%.3f", $0.recoil))/\(Int($0.range))" }.joined(separator: " < "))
        }
        let pistols = ladder(["gun_needle", "gun_sidearm", "gun_revolver", "gun_breaker"])
        let rifles = ladder(["gun_rifle", "gun_slatefall", "gun_kessel", "gun_longwatch", "gun_sniper"])
        let reg = Mob(.soldierIronclad, at: .zero); reg.setTroop(.regular, rearm: false)
        let han = Mob(.soldierIronclad, at: .zero); han.setTroop(.hannibal, rearm: false)
        let br = Guns.all[Guns.breaker]
        let kicks = (reg.aimKick(br), han.aimKick(br))
        check(pistols.0 && rifles.0 && kicks.0 > 0.05 && kicks.1 == 0,
              "P105 handling: pistols \(pistols.1); rifles \(rifles.1); a regular's aim opens \(String(format: "%.3f", kicks.0)) with the Breaker, a Hannibal's \(kicks.1)")
    }

    // P101: a manned deck gun fires one barrel a pull, left then right a beat apart, then reloads; each barrel flashes.
    static func twinBarrels(_ g: Game, _ check: (Bool, String) -> Void) {
        let a = PlaytestOct12Tests.arena(g, dx: -70, dz: 70, r: 3)
        defer { a.restore(); g.arms.slugs.removeAll(); g.arms.breaches.removeAll() }
        let m = Mob(.deckGun, at: V3(Float(a.fx) + 0.5, Float(a.py + 1), Float(a.fz) + 0.5))
        m.faction = Faction.steelhold.rawValue
        g.mobs.mobs.append(m)
        defer { g.mobs.mobs.removeAll { $0 === m }; Turrets.shared.manned = nil }
        let t = Turrets.shared
        t.mount(g, m)
        g.flashes.removeAll()
        let s0 = g.arms.slugs.count, f0 = g.flashes.count
        t.shoot(g, m)
        let x1 = g.arms.slugs.last.map { simd_dot($0.pos - m.pos, V3(cosf(m.yaw), 0, -sinf(m.yaw))) } ?? 0
        let after1 = (g.arms.slugs.count - s0, t.loaded, t.reload)
        t.shoot(g, m)
        let x2 = g.arms.slugs.last.map { simd_dot($0.pos - m.pos, V3(cosf(m.yaw), 0, -sinf(m.yaw))) } ?? 0
        let after2 = (g.arms.slugs.count - s0, t.loaded, t.reload)
        let flashes = g.flashes.count - f0
        check(after1.0 == 1 && after1.1 == 1 && abs(after1.2 - Turrets.beat) < 0.01 && after2.0 == 2 && after2.1 == 0
              && after2.2 > 2 && x1 < -1 && x2 > 1 && flashes >= 2,
              "P101 twin barrels: the first pull fires \(after1.0) shell (left barrel, \(String(format: "%.1f", x1)) across), \(after1.1) left loaded, "
              + "\(String(format: "%.2f", after1.2)) s to the next; the second fires the right (\(String(format: "%.1f", x2))), then a "
              + "\(String(format: "%.1f", after2.2)) s reload; \(flashes) muzzle flashes")
    }

    // P102: heavy shells hurt deck guns past their plate (manned more than crewed), a hurt gun smokes, blackens and
    // droops a barrel, and a destroyed one leaves a wreck of blocks.
    static func gunDamage(_ g: Game, _ check: (Bool, String) -> Void) {
        let a = PlaytestOct12Tests.arena(g, dx: 90, dz: 90, r: 3)
        let w = g.world
        defer { a.restore(); g.arms.slugs.removeAll(); g.arms.breaches.removeAll() }
        let m = Mob(.deckGun, at: V3(Float(a.fx) + 0.5, Float(a.py + 1), Float(a.fz) + 0.5))
        m.faction = Faction.steelhold.rawValue
        m.yaw = 0
        g.mobs.mobs.append(m)
        defer { g.mobs.mobs.removeAll { $0 === m } }
        func shell(_ manned: Bool) {
            var s = Slug(pos: m.pos + V3(0, 3, 20), vel: V3(0, 0, -260), kind: .shell, damage: 0, fromPlayer: manned,
                         shooter: nil, by: manned ? "Player" : "Greywall gun", life: 12, gravity: 0)
            HeavyTurret.arm(&s)
            if manned { s.power = HeavyTurret.mannedPower; s.breach = HeavyTurret.mannedBreach }
            g.arms.detonate(s, at: m.pos + V3(0, HeavyTurret.trunnionY, 0.5), g)
            g.arms.breaches.removeAll()
        }
        let hp0 = m.health
        shell(false)
        let crew = hp0 - m.health
        let parts0 = deckGunParts(m).first.map { $0.color } ?? .zero
        m.health = hp0
        shell(true)
        let manned = hp0 - m.health
        let state1 = NavalGuns.state(m)
        var hits = 1
        while m.health > 0 && hits < 8 { shell(true); hits += 1 }
        let state2 = m.health > 0 ? NavalGuns.state(m) : 2
        m.health = max(1, m.health)
        m.health = 1; let burning = NavalGuns.state(m)
        let partsHurt = deckGunParts(m).first.map { $0.color } ?? .zero
        // Destroyed: its burnt hulk where it stood, no blocks put down (P473; the box round it saved and put back).
        let ox = Int(floor(m.pos.x)), oy = Int(floor(m.pos.y)), oz = Int(floor(m.pos.z))
        var before: [(IVec3, BlockID)] = []
        for z in (oz - 24)...(oz + 24) { for y in oy...(oy + 5) { for x in (ox - 24)...(ox + 24) { before.append((IVec3(x, y, z), w.block(x, y, z))) } } }
        m.health = 0
        g.soldierDied(m)
        var wreck = 0
        for (p, b) in before where w.block(p.x, p.y, p.z) != b { wreck += 1; w.setBlockAsync(p.x, p.y, p.z, b) }
        let hulk = Hulks.mobs.contains { $0 === m }
        Hulks.mobs.removeAll { $0 === m }
        check(manned >= 120 && crew >= 40 && manned > crew && hits <= 4 && state1 >= 1 && burning == 2 && partsHurt.x < parts0.x && wreck == 0 && hulk,
              "P102 gun damage: a manned shell on a turret's gunhouse takes \(manned) of \(hp0) (a crewed one \(crew)), it is "
              + "destroyed in \(hits) hits (state after one \(state1), \(state2) at the end), hurt plate darker (\(String(format: "%.2f", partsHurt.x)) < \(String(format: "%.2f", parts0.x))), "
              + "its hulk standing \(hulk), \(wreck) blocks put down where it stood")
    }

    // P103: a manned naval shell blows a breach through a 3-thick wall of Capital stone, carved over frames.
    static func wallBreach(_ g: Game, _ check: (Bool, String) -> Void) {
        let a = PlaytestOct12Tests.arena(g, dx: -90, dz: -90, r: 9)
        let w = g.world, stone = Blocks.has("capital_stone") ? Blocks.id("capital_stone") : STONE
        var placed: [IVec3] = []
        defer { for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }; a.restore(); g.drops.items.removeAll(); g.arms.breaches.removeAll() }
        let x0 = a.fx + 2
        for z in (a.fz - 6)...(a.fz + 6) { for y in (a.py + 1)...(a.py + 5) { for x in x0...(x0 + 2) { w.setBlock(x, y, z, stone); placed.append(IVec3(x, y, z)) } } }
        var s = Slug(pos: V3(Float(x0) - 10, Float(a.py) + 3.5, Float(a.fz) + 0.5), vel: V3(260, 0, 0), kind: .shell, damage: 0, fromPlayer: true,
                     shooter: nil, by: "Player", life: 12, gravity: 0)
        HeavyTurret.arm(&s)
        s.power = HeavyTurret.mannedPower; s.breach = HeavyTurret.mannedBreach
        g.arms.detonate(s, at: V3(Float(x0) - 0.3, Float(a.py) + 3.5, Float(a.fz) + 0.5), g)
        let jobs = g.arms.breaches.count
        var frames = 0
        while !g.arms.breaches.isEmpty && frames < 200 { NavalGuns.stepBreaches(g); frames += 1 }
        let gone = placed.filter { w.block($0.x, $0.y, $0.z) != stone }.count
        let through = (x0...(x0 + 2)).allSatisfy { w.block($0, a.py + 3, a.fz) != stone }
        // How wide the hole goes right through the wall at the impact's height (P70's blast alone: about 3).
        let wide = ((a.fz - 6)...(a.fz + 6)).filter { z in (x0...(x0 + 2)).allSatisfy { w.block($0, a.py + 3, z) != stone } }.count
        check(jobs == 1 && gone >= 80 && through && wide >= 7 && frames >= 2,
              "P103 breach: one manned shell opens \(gone) of \(placed.count) blocks of a 3-thick Capital stone wall, a hole \(wide) wide right through, "
              + "carved over \(frames) frames")
    }
}
