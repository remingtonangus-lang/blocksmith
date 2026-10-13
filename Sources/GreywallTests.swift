import Foundation
import Metal
import simd

// Greywall Command checks (backlog A1; `questcheck --greywall-only`, and part of every questcheck run):
//   faction    a base's troops come out as Greywall soldiers (their own faction, names and ranks), keep it through a
//              save, and take a Capital soldier for a foe
//   rarity     over a wide square of regions on three seeds: about seven regions in ten hold a base, none within
//              600 blocks of spawn, the bigger tiers rarer and further out, every tier present somewhere
//   each tier  a real base of every tier, generated through the world's own structure path: StructCheck's walk model
//              finds no issue, a walker from outside the gate reaches the keep's comms room, a tower roof and the
//              wall walk (the fortress's command hall, the command fortress's war room too), the garrison has its
//              full count, the chests hold the tier's loot (command chests from the garrison up, vaults from the
//              fortress up), the alarm lamps, alarm panels and the map table are in place
enum GreywallTests {
    static func run(device: MTLDevice, game: Game, check: (Bool, String) -> Void) {
        let fly0 = game.player.flying, menu0 = game.menu
        defer { game.player.flying = fly0; game.menu = menu0 }       // (the turret check flies; the war table opens a report)
        faction(game, check)
        alarm(game, check)
        capture(game, check)
        turret(game, check)
        let seeds: [UInt64] = (arg("--greywall-seeds") ?? "12345,777,424242").split(separator: ",").compactMap { UInt64($0) }
        var found: [Greywall.Tier: [(UInt64, StructureStart)]] = [:]
        var regions = 0, bases = 0, nearSpawn = 0
        var nearest = Int.max
        var byTier: [Greywall.Tier: Int] = [:]
        var tooClose: [String] = []
        let t0 = CFAbsoluteTimeGetCurrent()
        let R = 6
        for seed in seeds {
            let world = World(seed: seed, device: device, save: nil)
            guard let sc = world.gen.structures, let type = sc.types.first(where: { $0.name == Greywall.kind }) else {
                check(false, "greywall \(seed): no structure type"); continue
            }
            let o = Game.spawnOrigin(seed: seed)
            let orx = floorDiv(floorDiv(o.0, CS), Greywall.spacing), orz = floorDiv(floorDiv(o.1, CS), Greywall.spacing)
            for rz in (orz - R)...(orz + R) { for rx in (orx - R)...(orx + R) {
                regions += 1
                guard let s = sc.start(type, regionX: rx, regionZ: rz) else { continue }
                bases += 1
                let t = Greywall.Tier.of(s)
                byTier[t, default: 0] += 1
                let (x, z) = Greywall.centre(s)
                let d = Int(simd_length(V2(Float(x - o.0), Float(z - o.1))))
                nearest = min(nearest, d)
                if d < t.minDist { tooClose.append("\(t) at \(d)") }
                if d < 600 { nearSpawn += 1 }
                // (bases from different seeds: outposts, most of the bases, from all three, the others from two where found)
                if (found[t]?.count ?? 0) < (t == .outpost ? 3 : 2) && !(found[t] ?? []).contains(where: { $0.0 == seed }) {
                    found[t, default: []].append((seed, s))
                }
            } }
        }
        let frac = Float(bases) / Float(max(1, regions))
        let tiers = Greywall.Tier.allCases.map { "\($0): \(byTier[$0] ?? 0)" }.joined(separator: ", ")
        check(frac > 0.3 && frac < 0.8 && nearSpawn == 0 && tooClose.isEmpty && nearest < 3000,
              String(format: "greywall rarity: %d bases in %d regions of 64x64 chunks (%.0f%%), nearest to spawn %d blocks, none closer than its tier allows (%@); %@ (%.1f s)",
                     bases, regions, frac * 100, nearest, tooClose.isEmpty ? "ok" : tooClose.joined(separator: ", "), tiers, CFAbsoluteTimeGetCurrent() - t0))
        let counts = Greywall.Tier.allCases.map { byTier[$0] ?? 0 }
        check(counts.allSatisfy { $0 > 0 } && counts[0] > counts[1] && counts[1] > counts[3],
              "greywall rarity: every tier is found and the bigger ones are rarer (\(tiers))")

        PathFinder.doors = true
        defer { PathFinder.doors = false }
        for t in Greywall.Tier.allCases {
            guard let list = found[t], !list.isEmpty else { check(false, "greywall \(t): none found to check"); continue }
            for (seed, s) in list { base(device, seed, s, t, check) }
        }
    }

    static func faction(_ g: Game, _ check: (Bool, String) -> Void) {
        let p = g.player.pos + V3(6, 0, 0)
        guard let grey = Mob.structureMob("soldier_trooper@grey", at: p), let gun = Mob.structureMob("deck_gun@grey", at: p),
              let capital = Mob.structureMob("soldier_trooper", at: p + V3(8, 0, 0)) else {
            check(false, "greywall faction: troop keys parse"); return
        }
        check(grey.factionValue == .greywall && gun.factionValue == .greywall && grey.spec.name == "Greywall Rifleman"
              && Faction.greywall.name == "Greywall Command" && Mob.crewNames[.greywall]?.count == 6,
              "greywall faction: a base's trooper is a \(grey.spec.name) of \(grey.factionValue.name), its deck gun \(gun.factionValue.name)")
        var d: [String: Float] = [:]
        grey.saveExtra(&d)
        let back = Mob(Soldier.garrison(.soldierTrooper, at: p), at: p)
        back.loadExtra(d)
        check(back.factionValue == .greywall && back.spec.name == "Greywall Rifleman", "greywall faction: a Greywall soldier keeps his colours through a save (\(back.spec.name))")
        g.mobs.mobs.append(grey); g.mobs.mobs.append(capital)
        defer { g.mobs.mobs.removeAll { $0 === grey || $0 === capital } }
        let foe = g.world.ships.nearestFoe(of: .greywall, near: grey.pos, range: 40, game: g)
        let back2 = g.world.ships.nearestFoe(of: .steelhold, near: capital.pos, range: 40, game: g)
        check(foe?.mob === capital && back2?.mob === grey, "greywall faction: Greywall and Capital soldiers are each other's foes")
    }

    static func base(_ device: MTLDevice, _ seed: UInt64, _ s: StructureStart, _ t: Greywall.Tier, _ check: (Bool, String) -> Void) {
        let world = World(seed: seed, device: device, save: nil)
        let (cx, cz) = Greywall.centre(s)
        let S = Greywall.yardY(s)
        let tag = "greywall \(seed) \(t)"
        let tg = CFAbsoluteTimeGetCurrent()
        let r = StructCheck.check(world, s, typeName: Greywall.kind, seed: seed)
        let ms = (CFAbsoluteTimeGetCurrent() - tg) * 1000
        let byClass = Dictionary(grouping: r.issues, by: { $0.cls }).map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", ")
        let guns = t.deckGuns ? t.towers.count : 0
        check(r.issues.isEmpty, String(format: "%@ at %d %d: structcheck %d doors, %d chests, %d mobs, issues: %@ (%.0f ms)",
                                       tag, cx, cz, r.doors, r.pois, r.mobs, byClass.isEmpty ? "none" : byClass, ms))
        for i in r.issues.prefix(8) { print("  \(i.cls) at \(i.pos.x - cx) \(i.pos.y - S) \(i.pos.z - cz) (relative): \(i.detail)") }
        let ours = world.pendingMobs.filter { $0.0.contains("@grey") && s.contains(Int(floor($0.1.x)), Int(floor($0.1.y)), Int(floor($0.1.z))) }
        let others = Set(world.pendingMobs.filter { !$0.0.contains("@grey") && s.contains(Int(floor($0.1.x)), Int(floor($0.1.y)), Int(floor($0.1.z))) }.map { $0.0 })
        check(ours.count == t.troops + guns, "\(tag): \(ours.count) troops and guns posted (\(t.troops) soldiers + \(guns) deck guns)\(others.isEmpty ? "" : "; others in the box: " + others.sorted().joined(separator: ", "))")

        // The keep where the plan puts it.
        let kx = t.keepX, kz = t.keepZ, kc = t.keepC
        let floorKey = Blocks.key(world.block(cx, S, cz + kc))
        check(floorKey == "bunker_floor", "\(tag): the keep's floor where the plan puts it (\(floorKey))")

        // Walk in from outside the gate.
        let a = s.anchor
        let seedCells: [IVec3] = StructCheck.standNear(world, a.x, a.y, a.z, up: 2, down: 4).map { [IVec3(a.x, $0.0, a.z)] } ?? []
        let e = t.half + Greywall.margin
        let walk = StructCheck.walkOrder(world, seeds: seedCells, lo: IVec3(cx - e, S - 8, cz - e), hi: IVec3(cx + e, S + t.wallH + 14, cz + e), jump: true).seen
        let rooms = Greywall.rooms(t)
        var probes: [(String, Int, Int, Int)] = []
        for rm in rooms { probes.append((rm.use, rm.door.0, 1, rm.door.1 + (rm.door.1 < kc ? -1 : 1))) }
        if let tw = t.towers.first { let c = Greywall.tower(t, tw.0, tw.1); probes.append(("tower roof", c.x - tw.0, t.wallH + 6, c.z - tw.1)) }
        probes.append(("wall walk", 0, t.wallH + 1, -(t.half - 1)))
        if t.floors > 1 { probes.append(("command hall", 2, 6, kc - kz + 4)) }
        if t.bunker { probes.append(("war room", kx / 2, -5, kc - kz + 4)); probes.append(("bunker vault", -(kx / 2), -5, kc)) }
        var reached: [String] = [], missed: [String] = []
        for (n, dx, y, dz) in probes {
            if walk.contains(StructCheck.key(cx + dx, S + y, cz + dz)) { reached.append(n) } else { missed.append(n) }
        }
        check(!seedCells.isEmpty && missed.isEmpty,
              "\(tag): walking in from the gate reaches \(reached.count)/\(probes.count) places (\(missed.isEmpty ? reached.joined(separator: ", ") : "missed " + missed.joined(separator: ", ")))")

        // Loot by tier, alarms, the map table.
        var tables: [String: Int] = [:]
        var lamps = 0, panels = 0, maps = 0, turrets = 0, flags = 0
        let turretBase = Blocks.groupBase[Int(Blocks.id("wall_turret"))], flagID = Blocks.id("greywall_flag")
        let lampBase = Blocks.groupBase[Int(Blocks.id("alarm_lamp"))], panelBase = Blocks.groupBase[Int(Blocks.id("alarm_panel"))]
        let mapID = Blocks.id("greywall_map_table")
        for z in (cz - e)...(cz + e) { for x in (cx - e)...(cx + e) { for y in (S - 8)...(S + t.wallH + 12) {
            let b = world.block(x, y, z)
            if Blocks.groupBase[Int(b)] == lampBase { lamps += 1 }
            if Blocks.groupBase[Int(b)] == panelBase { panels += 1 }
            if b == mapID { maps += 1 }
            if Blocks.groupBase[Int(b)] == turretBase { turrets += 1 }
            if b == flagID { flags += 1 }
            if let be = world.blockEntities[IVec3(x, y, z)] {
                let names = Set(be.container.slots.filter { !$0.isEmpty }.map { Items.key($0.item) })
                if names.contains("radar_module") { tables["command", default: 0] += 1 }
                if names.contains("gold_block") { tables["vault", default: 0] += 1 }
            }
        } } }
        let chests = r.pois
        let needCommand = t.rawValue >= 1, needVault = t.rawValue >= 2
        check(chests >= [3, 5, 9, 12][t.rawValue] && (!needCommand || (tables["command"] ?? 0) > 0)
              && (!needVault || (tables["vault"] ?? 0) > 0),
              "\(tag): \(chests) chests (\(tables.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")))")
        check(lamps >= [8, 14, 22, 28][t.rawValue] && panels >= 1 + t.towers.count && maps >= 1,
              "\(tag): \(lamps) alarm lamps, \(panels) alarm panels, \(maps) map tables")
        let planned = Greywall.turrets(t).count + Greywall.corridorTurrets(t).count
        check(turrets == planned && flags == 4, "\(tag): \(turrets) wall and corridor turrets (\(planned) planned), the flag on the keep (\(flags) cells)")
        // What the alarm, the capture and the turrets will find on this generated base (Greywall.scan, as in play): a
        // command console to hold above all (an outpost had none: it could never be taken, A1 verifier).
        var site = GreywallAlarmState.Site(cx: cx, cz: cz, S: S, tier: t)
        let scanned = Greywall.scan(world, &site)
        check(scanned && !site.consoles.isEmpty && site.lamps.count == lamps && site.panels.count == panels
              && site.turrets.count == turrets && site.flags.count == flags,
              "\(tag): the base's scan finds \(site.consoles.count) command consoles, \(site.lamps.count) lamps, \(site.panels.count) panels, \(site.turrets.count) turrets, \(site.flags.count) flag cells")
    }

    // A1b on a stand-in base in the air over the player: a shot inside sets the alarm off and lights its lamps, the
    // garrison stands to, a fortress calls squads in at the gate while a panel stands, none once every panel is
    // broken, and it stands down 45 s after the last noise. A leashed soldier holds at the wall and walks back in.
    static func alarm(_ g: Game, _ check: (Bool, String) -> Void) {
        let p0 = g.player.pos, mobs0 = g.mobs.mobs, surv0 = g.survival, toast0 = g.onToast, sites0 = g.greywallAlarm.sites
        let log0 = g.greywallAlarm.log.count
        var said: [String] = []
        g.onToast = { said.append($0) }
        let cx = Int(floor(p0.x)), cz = Int(floor(p0.z)), S = Int(floor(p0.y)) + 40
        var placed: [IVec3] = []
        defer {
            for q in placed { g.world.setBlock(q.x, q.y, q.z, AIR) }
            g.player.pos = p0; g.mobs.mobs = mobs0; g.survival = surv0; g.onToast = toast0; g.greywallAlarm.sites = sites0
        }
        let t = Greywall.Tier.fortress
        var site = GreywallAlarmState.Site(cx: cx, cz: cz, S: S, tier: t)
        let lamp = Blocks.id("alarm_lamp"), panel = Blocks.id("alarm_panel")
        for i in 0..<3 {
            let l = IVec3(cx + i - 1, S + 3, cz - 4), q = IVec3(cx + i - 1, S + 1, cz - 4)
            g.world.setBlock(l.x, l.y, l.z, lamp); g.world.setBlock(q.x, q.y, q.z, panel)
            placed += [l, q]; site.lamps.append(l); site.panels.append(q)
        }
        let key = "greywall:\(cx),\(cz)"
        g.greywallAlarm.sites[key] = site
        g.player.pos = V3(Float(cx) + 0.5, Float(S + 1), Float(cz) + 0.5)
        g.survival = true
        guard let guardMob = Mob.structureMob("soldier_trooper@grey\(Greywall.leashTag(cx, cz, t))", at: V3(Float(cx) + 6.5, Float(S + 1), Float(cz) + 0.5)) else {
            check(false, "greywall alarm: a leashed trooper parses"); return
        }
        g.mobs.mobs = [guardMob]
        g.bases.noises = [BaseNoise(pos: V3(Float(cx) + 2, Float(S + 1), Float(cz)), kind: .gunshot, power: 1, hostile: true)]
        g.greywallAlarmTick(g.bases, 1)
        g.bases.noises = []
        let on = g.greywallAlarm.sites[key]?.on ?? false
        let lit = site.lamps.filter { let b = g.world.block($0.x, $0.y, $0.z); return b >= Blocks.id("alarm_lamp_lit") && b < Blocks.id("alarm_lamp_lit") + 4 }.count
        check(on && lit == 3 && guardMob.aggro && said.contains { $0.contains("alarm") },
              "greywall alarm: a shot inside the walls sets it off: \(lit)/3 lamps lit, the garrison stands to (\(guardMob.aggro)), \"\(said.first ?? "")\"")
        for _ in 0..<30 { g.greywallAlarmTick(g.bases, 1) }
        // T6: the squad comes by truck up the approach: drive it in, unload, and away.
        let trucked = !g.greywallAlarm.trucks.isEmpty
        var truckTime: Float = 0
        while !g.greywallAlarm.trucks.isEmpty && truckTime < 60 { g.greywallTrucksTick(0.05); truckTime += 0.05 }
        let squads = g.greywallAlarm.sites[key]?.squads ?? 0
        let arrived = g.mobs.mobs.filter { $0 !== guardMob && $0.factionValue == .greywall }
        let leashed = arrived.allSatisfy { $0.leash != nil }
        check(squads >= 1 && arrived.count == 3 * squads && leashed,
              "greywall alarm: the fortress calls a squad in at the gate (\(squads) squads, \(arrived.count) soldiers, leashed \(leashed))")
        check(trucked && g.greywallAlarm.trucks.isEmpty && !g.mobs.mobs.contains { $0.kind == .ashTruck }
              && arrived.allSatisfy { simd_length(V2($0.pos.x - Float(cx), $0.pos.z - Float(cz + t.half + 6))) < 8 },
              String(format: "greywall alarm: the squad comes by truck to the gate, jumps down and the truck drives off (%.1f s; squad at %@, gate stop %ld,%ld)", truckTime,
                     arrived.map { String(format: "%.0f,%.0f,%.0f", $0.pos.x, $0.pos.y, $0.pos.z) }.joined(separator: " "), cx, cz + t.half + 6))
        for q in site.panels { g.world.setBlock(q.x, q.y, q.z, AIR) }
        for _ in 0..<50 { g.greywallAlarmTick(g.bases, 1) }
        let after = g.greywallAlarm.sites[key]?.squads ?? 0
        check(after == squads && (g.greywallAlarm.sites[key]?.panelsDown ?? false),
              "greywall alarm: with every panel broken no more squads come (\(squads) then \(after))")
        // Stand down: nobody fighting (the soldiers lose sight), 45 s of quiet.
        for m in g.mobs.mobs { m.health = 0 }
        for _ in 0..<50 { g.greywallAlarmTick(g.bases, 1) }
        let dark = site.lamps.allSatisfy { let b = g.world.block($0.x, $0.y, $0.z); return b >= lamp && b < lamp + 4 }
        check(!(g.greywallAlarm.sites[key]?.on ?? true) && dark, "greywall alarm: it stands down after 45 s of quiet and the lamps go dark (\(dark))")
        let log = g.greywallAlarm.log.dropFirst(log0).joined(separator: "; ")
        print("  greywall alarm log: \(log)")

        // The leash: a step out past the wall is refused; a soldier carried out walks back in.
        let m = guardMob
        m.health = 20
        m.pos = V3(Float(cx + t.half + 3) + 0.5, Float(S + 1), Float(cz) + 0.5)
        m.yaw = 0; m.strafe = 0
        m.face(V3(Float(cx + 200), m.pos.y, Float(cz)))
        let held = m.applyLeash(m.spec.speed)
        m.pos = V3(Float(cx + t.half + 9) + 0.5, Float(S + 1), Float(cz) + 0.5)
        let back = m.applyLeash(m.spec.speed)
        // Carried out past the east wall it heads round the outside to the front (the gate side), not into the wall.
        let toward = simd_dot(m.forward, V3(0, 0, 1)) > 0.9
        var steps = 0
        while steps < 600 && m.applyLeash(m.spec.speed) > 0 && (abs(m.pos.x - Float(cx)) > Float(t.half + 4) || abs(m.pos.z - Float(cz)) > Float(t.half + 4)) {
            m.pos += m.forward * 0.25; steps += 1
        }
        let front = m.pos.z > Float(cz + t.half) && steps < 600
        check(held == 0 && back > 0 && toward && front,
              String(format: "greywall leash: a step out past the wall is held (%.2f), a soldier outside walks round to the gate side (%.2f, south %@) and is back at the front after %d steps (%@)", held, back, toward ? "yes" : "no", steps, front ? "yes" : "no"))
    }

    // A1c: a cleared base held at its command console for 10 s is the player's: the alarm silent for good, the deck
    // guns gone, the respawn point in its yard, kept through a save; a soldier standing stops it; the map table's radar
    // net marks other bases.
    static func capture(_ g: Game, _ check: (Bool, String) -> Void) {
        let p0 = g.player.pos, mobs0 = g.mobs.mobs, surv0 = g.survival, toast0 = g.onToast, sites0 = g.greywallAlarm.sites
        let taken0 = g.greywallAlarm.taken, spawn0 = g.spawnPoint
        var said: [String] = []
        g.onToast = { said.append($0) }
        defer {
            g.player.pos = p0; g.mobs.mobs = mobs0; g.survival = surv0; g.onToast = toast0; g.greywallAlarm.sites = sites0
            g.greywallAlarm.taken = taken0; g.spawnPoint = spawn0
        }
        let cx = Int(floor(p0.x)) + 1000, cz = Int(floor(p0.z)), S = Int(floor(p0.y))
        let t = Greywall.Tier.garrison
        var site = GreywallAlarmState.Site(cx: cx, cz: cz, S: S, tier: t)
        site.consoles = [IVec3(cx, S + 1, cz - 3)]
        let key = "greywall:\(cx),\(cz)"
        g.survival = true
        let at = V3(Float(cx) + 0.5, Float(S + 1), Float(cz - 2) + 0.5)
        let players = [at]
        let foe = Mob.structureMob("soldier_trooper@grey", at: at + V3(4, 0, 0))!
        let gun = Mob.structureMob("deck_gun@grey", at: at + V3(-6, 0, 0))!
        g.mobs.mobs = [foe, gun]
        var early = false
        for _ in 0..<12 { early = early || g.greywallCaptureTick(&site, key, players, 1) }
        check(!early && site.hold == 0, "greywall capture: a soldier still standing keeps the base from being taken")
        foe.health = 0
        var tookAt = -1
        for i in 0..<12 where tookAt < 0 { if g.greywallCaptureTick(&site, key, players, 1) { tookAt = i + 1 } }
        let gunGone = !g.mobs.mobs.contains { $0 === gun }
        let sp = g.spawnPoint
        let inYard = Greywall.inside(site, sp)
        var d: [String: String] = g.saveExtra()
        g.greywallAlarm.taken = []
        g.loadExtra(d)
        let kept = g.greywallAlarm.taken.contains(key)
        d.removeAll()
        check(tookAt == 10 && gunGone && inYard && kept && said.contains { $0.contains("yours") },
              "greywall capture: held at the console the base is taken after \(tookAt) s, its guns gone (\(gunGone)), the respawn in its yard (\(inYard)), kept through a save (\(kept))")
        // Walking off the console part-way restarts it.
        var s2 = GreywallAlarmState.Site(cx: cx + 300, cz: cz, S: S, tier: t)
        s2.consoles = [IVec3(cx + 300, S + 1, cz - 3)]
        let at2 = V3(Float(cx + 300) + 0.5, Float(S + 1), Float(cz - 2) + 0.5)
        for _ in 0..<5 { _ = g.greywallCaptureTick(&s2, "x", [at2], 1) }
        _ = g.greywallCaptureTick(&s2, "x", [at2 + V3(8, 0, 6)], 1)
        check(s2.hold == 0, "greywall capture: walking off the console stops the count")

        // The radar net from a real base: the others within 3,000 blocks go on the map.
        if let sc = g.world.gen.structures, let s = sc.nearest(Greywall.kind, x: Int(p0.x), z: Int(p0.z), maxRegions: 2) {
            let (bx, bz) = Greywall.centre(s)
            let net = g.greywallRadarNet(from: bx, bz)
            let marked = net.filter { o in let (x, z) = Greywall.centre(o); return MapCache.shared.marks.contains { $0.kind == Greywall.kind && $0.x == x && $0.z == z } }
            check(!net.isEmpty && marked.count == net.count,
                  "greywall radar net: from the base at \(bx) \(bz), \(net.count) others within 3,000 blocks, \(marked.count) marked on the map")
        } else { check(false, "greywall radar net: no base near spawn to test from") }
    }

    // Objective 4: a wall turret winds up before it fires (the telegraph), needs a clear line, fires slower damaged, is
    // shot to damaged then a wreck that never fires, and stands down on a base the player has taken.
    static func turret(_ g: Game, _ check: (Bool, String) -> Void) {
        let p0 = g.player.pos, surv0 = g.survival, alive0 = g.alive, sites0 = g.greywallAlarm.sites, taken0 = g.greywallAlarm.taken
        let cx = Int(floor(p0.x)), cz = Int(floor(p0.z)), S = Int(floor(p0.y)) + 50
        let tp = IVec3(cx, S + 2, cz - 10)                         // facing south (+z), toward the player
        var placed = [tp]
        defer {
            for q in placed { g.world.setBlock(q.x, q.y, q.z, AIR) }
            g.player.pos = p0; g.survival = surv0; g.alive = alive0; g.greywallAlarm.sites = sites0; g.greywallAlarm.taken = taken0
            g.greywallAlarm.guns = [:]
        }
        g.survival = true; g.alive = true
        g.player.pos = V3(Float(cx) + 0.5, Float(S + 1), Float(cz) + 0.5); g.player.flying = true; g.player.vel = .zero
        let gun = Blocks.id("wall_turret")
        g.world.setBlock(tp.x, tp.y, tp.z, gun + 1)
        var site = GreywallAlarmState.Site(cx: cx, cz: cz, S: S, tier: .garrison)
        site.turrets = [tp]
        let key = "greywall:\(cx),\(cz)"
        g.greywallAlarm.sites = [key: site]
        func run(_ secs: Float) -> (first: Float, shots: Int) {
            let n0 = g.arms.slugs.count
            var t: Float = 0, first: Float = -1
            while t < secs {
                g.player.pos = V3(Float(cx) + 0.5, Float(S + 1), Float(cz) + 0.5); g.player.vel = .zero
                g.greywallTurretsTick(0.05); t += 0.05
                if first < 0 && g.arms.slugs.count > n0 { first = t }
            }
            let n = g.arms.slugs.count - n0
            g.arms.slugs.removeSubrange(n0..<g.arms.slugs.count)
            return (first, n)
        }
        g.greywallAlarm.guns = [:]
        let a = run(3)
        check(a.first >= 0.85 && a.first < 1.3 && a.shots >= 3, String(format: "greywall turret: winds up %.2f s before its first round, %d rounds in 3 s", a.first, a.shots))
        // A wall in the way: silent.
        for dx in -1...1 { for dy in -1...2 { let q = IVec3(cx + dx, S + dy, cz - 5); g.world.setBlock(q.x, q.y, q.z, STONE); placed.append(q) } }
        g.greywallAlarm.guns = [:]
        let blocked = run(3)
        for q in placed.dropFirst() { g.world.setBlock(q.x, q.y, q.z, AIR) }
        check(blocked.shots == 0, "greywall turret: a wall between holds its fire (\(blocked.shots) rounds)")
        // Shot up: damaged (slower wind-up), then a wreck.
        let at = V3(Float(tp.x) + 0.5, Float(tp.y) + 0.5, Float(tp.z) + 0.9)
        for _ in 0..<GreywallAlarmState.turretHits { _ = g.greywallBlockShot(tp, g.world.block(tp.x, tp.y, tp.z), at: at) }
        let dmgKey = Blocks.key(Blocks.groupBase[Int(g.world.block(tp.x, tp.y, tp.z))])
        g.greywallAlarm.guns[tp] = nil
        let d = run(3)
        for _ in 0..<GreywallAlarmState.turretHits { _ = g.greywallBlockShot(tp, g.world.block(tp.x, tp.y, tp.z), at: at) }
        let wreckKey = Blocks.key(Blocks.groupBase[Int(g.world.block(tp.x, tp.y, tp.z))])
        let w = run(3)
        check(dmgKey == "wall_turret_damaged" && d.first > a.first + 0.3 && wreckKey == "wall_turret_wreck" && w.shots == 0,
              String(format: "greywall turret: six hits leave it %@ (wind-up %.2f s), six more a %@ that fires %d rounds", dmgKey, d.first, wreckKey, w.shots))
        // A taken base's turrets stand down.
        g.world.setBlock(tp.x, tp.y, tp.z, gun + 1)
        g.greywallAlarm.taken = [key]
        g.greywallAlarm.guns = [:]
        let tk = run(3)
        check(tk.shots == 0, "greywall turret: the turrets of a base you hold stand down (\(tk.shots) rounds)")
    }
}
