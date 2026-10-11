import Foundation
import simd

// The Ash Vault gap pass (docs/status/the-deep-expansion.md "Gap pass" D2), run with DeepExpansionTests:
//   layout    the four towns and the airfield as generated (buildings, signs, mortar pits, roles, bombers, runway
//             lamps, AA pits), every rail line laid end to end (track on every cell, powered rails, halts with boards
//             and carts) and no patrol camp on a town or a line
//   ride      a cart from the citadel halt rolls up the north line
//   war       the alarm (spotted -> Alert, watched -> Alarm -> Total War, kills, falls unseen, saved), reinforcement
//             squads with their roles walking to the last contact, armour at Total War, patrols turning at their ends,
//             mortar crews and field guns marking every shell 1.5 s+ ahead, medics healing, MG gunners suppressing,
//             officers calling armour, wrecks burning with the crew bailing out, the unit cap
//   battle    the biggest fight (the citadel at Total War): Game.tick ms and the units in it (D5, DE14)
enum AshVaultGapTests {
    static var battle: (units: Int, avg: Double, p95: Double, worst: Double, skipped: Int) = (0, 0, 0, 0, 0)

    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        layout(check)
        rails(check)
        let home = g.player.pos, homeDim = g.dim.dim, wasSurvival = g.survival, wasDiff = g.difficulty
        // The army fights only until the Marshal falls; the balance duels before this kill him.
        let wasVictory = g.ashVictory
        g.ashVictory = false
        defer {
            g.ashVictory = wasVictory
            g.mobs.mobs.removeAll(); g.survival = wasSurvival; g.difficulty = wasDiff; g.alive = true; g.health = 20
            g.ashAlarm = 0; g.ashAlarmLevel = 0; g.ashStrikes.removeAll(); g.ashWrecks.removeAll(); g.ashSpot = nil
            g.onToast = nil
            if g.dim.dim != homeDim { g.changeDimension(to: homeDim, at: home) }
            g.player.pos = home; g.player.vel = .zero
            _ = g.world.loadSync(center: home, radius: 4)
        }
        ride(g, check)
        war(g, check)
        biggestBattle(g, check)
        print(String(format: "ash vault gap: checks took %.1f s", CFAbsoluteTimeGetCurrent() - t0))
    }

    // Chunks of the vault as generated (terrain + structures) over a box, and the structure mobs in it.
    final class Patch {
        var chunks: [Int64: [BlockID]] = [:]
        var mobs: [(String, V3)] = []
        var entities: [(IVec3, BlockEntity)] = []
        init(_ dg: DeepGen, x0: Int, z0: Int, x1: Int, z1: Int) {
            guard let sc = dg.structures else { return }
            for cz in floorDiv(z0, CS)...floorDiv(z1, CS) { for cx in floorDiv(x0, CS)...floorDiv(x1, CS) {
                var b = dg.generate(cx: cx, cz: cz)
                let (e, ms) = sc.place(into: &b, cx: cx, cz: cz)
                chunks[StructureCache.key(cx, cz)] = b
                mobs += ms
                entities += e
            } }
        }
        func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
            guard let b = chunks[StructureCache.key(floorDiv(x, CS), floorDiv(z, CS))] else { return AIR }
            return b[Chunk.index(x - floorDiv(x, CS) * CS, y, z - floorDiv(z, CS) * CS)]
        }
        func count(_ id: BlockID, _ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int, _ y0: Int, _ y1: Int) -> Int {
            var n = 0
            for z in z0...z1 { for x in x0...x1 { for y in y0...y1 where get(x, y, z) == id { n += 1 } } }
            return n
        }
        func signs(_ word: String) -> Int { entities.filter { $0.1.kind == .sign && $0.1.lines.contains { $0.contains(word) } }.count }
    }

    static func layout(_ check: (Bool, String) -> Void) {
        let dg = DeepGen(seed: 12345)
        let y0 = AshWar.ground
        let plating = Blocks.id("ash_plating"), concrete = Blocks.id("ash_concrete"), mortar = Blocks.id("ash_mortar")
        var bad: [String] = []
        for s in AshWar.townSites {
            let p = Patch(dg, x0: s.x - s.r, z0: s.z - s.r, x1: s.x + s.r, z1: s.z + s.r)
            let inside = p.mobs.filter { abs(Int($0.1.x) - s.x) <= s.r && abs(Int($0.1.z) - s.z) <= s.r }.map { $0.0 }
            let soldiers = inside.filter { $0.hasPrefix("soldier_") }.count
            let roles = ["mortar", "medic", "mg"].allSatisfy { r in inside.contains { $0.contains(":\(r)") } }
            let walls = p.count(plating, s.x - s.r, s.z - s.r, s.x + s.r, s.z + s.r, y0 + 1, y0 + 8)
                + p.count(concrete, s.x - s.r, s.z - s.r, s.x + s.r, s.z + s.r, y0 + 1, y0 + 8)
            let name = AshWar.townName(s)
            let ok = soldiers >= 12 && roles && walls > 1500 && p.count(mortar, s.x - s.r, s.z - s.r, s.x + s.r, s.z + s.r, y0 + 1, y0 + 1) == 1
                && p.signs(name.uppercased()) == 1 && p.signs("RADIO ROOM") == 1 && p.signs("MESS HALL") == 1 && p.signs("Ashguard Rail") >= 1
                && inside.contains("ash_truck^\(AshWar.Frame(s).heading)")
            if !ok { bad.append("\(name): \(soldiers) soldiers, roles \(roles), walls \(walls), signs \(p.signs(name.uppercased()))/\(p.signs("Ashguard Rail"))") }
        }
        let a = AshWar.airfield
        let p = Patch(dg, x0: a.x - a.r, z0: a.z - a.r, x1: a.x + a.r, z1: a.z + a.r)
        let lamp = Blocks.id("ash_lamp")
        let runwayLamps = p.count(lamp, a.x - 46, a.z - 57, a.x - 28, a.z + 57, y0, y0)
        let glass = p.count(GLASS, a.x - a.r, a.z - a.r, a.x + a.r, a.z + a.r, y0 + 1, y0 + 16)
        let bombers = p.count(Blocks.id("ash_mark"), a.x - 25, a.z - 50, a.x + 12, a.z + 30, y0 + 3, y0 + 3) / 4
        let airMobs = p.mobs.filter { abs(Int($0.1.x) - a.x) <= a.r && abs(Int($0.1.z) - a.z) <= a.r }.map { $0.0 }
        let airOK = runwayLamps >= 36 && glass >= 40 && bombers >= 3 && airMobs.filter { $0.hasPrefix("soldier_") }.count >= 14
            && airMobs.contains { $0.hasPrefix("ash_truck:fuel") } && p.signs("CONTROL") == 1 && p.signs("HANGAR") == 2
        if !airOK { bad.append("airfield: lamps \(runwayLamps), glass \(glass), bombers \(bombers), soldiers \(airMobs.count)") }
        // No patrol camp on a town, the airfield or a line.
        var campClash = 0
        for rz in -3...3 { for rx in -3...3 {
            guard let c = AshWar.camp(regionX: rx, regionZ: rz) else { continue }
            if AshWar.railDistance(c.x, c.z) < 20 || (AshWar.townSites + [a]).contains(where: { abs(c.x - $0.x) < $0.r + c.r && abs(c.z - $0.z) < $0.r + c.r }) { campClash += 1 }
        } }
        check(bad.isEmpty && campClash == 0,
              "ash vault: four towns (barracks, mess, radio room, quarters, depot, signal tower, mortar pit, 12+ soldiers with mortar/medic/MG roles, signs) and the airfield (runway \(runwayLamps) lamps, \(bombers) bombers, tower, AA pits), camps clear (\(campClash))\(bad.isEmpty ? "" : ": " + bad.joined(separator: "; "))")
    }

    // Every rail line laid end to end: track on every cell, a powered rail every 20, solid under it, headroom over it,
    // ten halts with their boards and a cart each.
    static func rails(_ check: (Bool, String) -> Void) {
        let dg = DeepGen(seed: 12345)
        let y0 = AshWar.ground
        var cells = 0, laid = 0, powered = 0, bed = 0, clear = 0
        var boards = 0, carts = 0, stops = 0, buffers = 0
        var counted = Set<IVec3>()
        for (i, r) in AshWar.railRuns.enumerated() {
            let p0 = AshWar.cell(r, r.a), p1 = AshWar.cell(r, r.b)
            let patch = Patch(dg, x0: min(p0.x, p1.x) - 5, z0: min(p0.z, p1.z) - 5, x1: max(p0.x, p1.x) + 5, z1: max(p0.z, p1.z) + 5)
            for t in r.a...r.b {
                let (x, z) = AshWar.cell(r, t)
                // The line ends (bar the airfield line's corner) carry a buffer stop.
                if (t == r.a && i != 4) || (t == r.b && i != 5) {
                    stops += 1
                    if patch.get(x, y0 + 1, z) == Blocks.id("ash_concrete") { buffers += 1 }
                    continue
                }
                cells += 1
                let b = patch.get(x, y0 + 1, z)
                if Rails.isRail(b) { laid += 1 }
                if Circuit.kind(b) == .poweredRail { powered += 1 }
                if Blocks.collide[Int(patch.get(x, y0, z))] { bed += 1 }
                if patch.get(x, y0 + 2, z) == AIR && patch.get(x, y0 + 3, z) == AIR { clear += 1 }
            }
            for (pos, be) in patch.entities where be.kind == .sign && be.lines.first == "Ashguard Rail" && !counted.contains(pos) {
                counted.insert(pos); boards += 1
            }
            carts += patch.mobs.filter { $0.0 == "minecart" && AshWar.railShape(Int(floor($0.1.x)), Int(floor($0.1.z))) != nil }
                .filter { m in AshWar.halts.contains { $0.run == i && abs((r.alongX ? Int(floor(m.1.x)) : Int(floor(m.1.z))) - ($0.from + $0.dir * AshWar.haltLength / 2)) == 0 } }.count
        }
        check(laid == cells && powered >= cells / 20 - 6 && bed == cells && clear >= cells - 4 && boards == AshWar.halts.count && carts == AshWar.halts.count
              && buffers == stops && stops == 10,
              "ash vault rail: \(AshWar.railRuns.count) runs, \(laid) of \(cells) cells laid (\(powered) powered), bed under \(bed), headroom \(clear); \(boards) halt boards, \(carts) carts waiting (\(AshWar.halts.count) halts); \(buffers) of \(stops) buffer stops")
    }

    static func ground(_ w: World, _ x: Int, _ z: Int) -> Float {
        for y in stride(from: AshWar.ground + 12, through: AshWar.ground - 8, by: -1)
            where Blocks.collide[Int(w.block(x, y - 1, z))] && w.block(x, y, z) == AIR && w.block(x, y + 1, z) == AIR { return Float(y) }
        return Float(AshWar.ground + 1)
    }

    // A cart from the citadel halt on the north line: pushed off, the powered rails carry it 40+ blocks up the line.
    static func ride(_ g: Game, _ check: (Bool, String) -> Void) {
        let y = Float(AshWar.ground + 1)
        g.changeDimension(to: .deep, at: V3(6.5, y, -70.5))
        let w = g.world
        _ = w.loadSync(center: V3(6.5, y, -90), radius: 5)
        g.mobs.mobs.removeAll(); w.pendingMobs.removeAll()
        g.survival = false; g.alive = true; g.paused = false; g.menu = nil
        let cart = Mob(.minecart, at: V3(6.5, y, -57.5))
        g.mobs.mobs.append(cart)
        g.riding = cart
        cart.vel = V3(0, 0, -3)
        var e: Float = 0, off = false
        while e < 12 {
            g.tick(0.05)
            w.pendingMobs.removeAll()
            if !Rails.isRail(w.block(6, AshWar.ground + 1, Int(floor(cart.pos.z)))) { off = true }
            e += 0.05
        }
        g.riding = nil
        let went = -57.5 - cart.pos.z
        check(went > 40 && !off && abs(cart.pos.x - 6.5) < 0.2, String(format: "ash vault rail: a cart from the citadel halt rolls %.0f blocks up the north line in 12 s (on the rails %@)", went, off ? "no" : "yes"))
    }

    static func war(_ g: Game, _ check: (Bool, String) -> Void) {
        // The south road beyond the towns' ring: open, levelled ground (DeepTests.war's road).
        g.changeDimension(to: .deep, at: V3(0.5, 100, 600.5))
        let w = g.world
        let y = ground(w, 0, 600)
        _ = w.loadSync(center: V3(0.5, y, 610.5), radius: 5)
        g.mobs.mobs.removeAll(); w.pendingMobs.removeAll()
        g.survival = true; g.alive = true; g.paused = false; g.menu = nil; g.difficulty = 2
        g.player.flying = false
        let stand = V3(0.5, y, 600.5)
        g.player.pos = stand
        var toasts: [String] = []
        g.onToast = { toasts.append($0) }
        g.ashAlarm = 0; g.ashAlarmLevel = 0; g.ashSquadsSent = 0; g.ashReinforceT = 999; g.ashPatrolT = 999; g.ashSpot = nil
        g.ashSpotSeen = -999
        func tick(_ secs: Float, seen: Bool = false, each: (() -> Void)? = nil) {
            var e: Float = 0
            while e < secs {
                if seen { g.ashSpot = g.player.pos; g.ashSpotSeen = g.clock }
                g.ashArmyTick(0.05)
                each?()
                e += 0.05
                g.clock += 0.05
            }
        }
        // The alarm: spotted -> Alert at once; watched 40 s -> past Alarm; kills push it on; unseen it falls; saved.
        tick(0.2, seen: true)
        let alert = g.ashAlarmLevel == 1 && toasts.contains { $0.hasPrefix("Alarm: Alert") }
        tick(22, seen: true)
        let alarm = g.ashAlarmLevel == 2 && toasts.contains { $0.hasPrefix("Alarm raised") }
        let dead = Mob.structureMob("soldier_trooper@ash", at: stand + V3(30, 0, 0))!
        dead.killedByPlayer = true
        for _ in 0..<3 { g.ashAlarmKill(dead) }
        let tank = Mob.structureMob("ash_tank@ash", at: stand + V3(30, 0, 0))!
        tank.killedByPlayer = true
        g.ashAlarmKill(tank)
        tick(0.1)
        let total = g.ashAlarmLevel == 3 && toasts.contains { $0.hasPrefix("Alarm: Total War") }
        let saved = g.saveExtra()
        let before = g.ashAlarm
        g.ashAlarm = 0
        g.loadExtra(saved)
        let keeps = abs(g.ashAlarm - before) < 0.01 && g.ashAlarmLevel == 3
        tick(40)
        let stillTotal = g.ashAlarmLevel == 3
        tick(70)
        let fell = g.ashAlarmLevel == 2 && toasts.contains { $0.contains("Still searching") }
        check(alert && alarm && total && keeps && stillTotal && fell,
              "ash vault alarm: spotted -> Alert (\(alert)), watched 22 s -> Alarm (\(alarm)), kills -> Total War (\(total)) with siren and radio lines, kept through a save (\(keeps)), holds 30 s unseen then falls (\(fell))")

        // Reinforcements at Alarm: a squad with its roles runs from the nearest garrison toward the last contact.
        g.mobs.mobs.removeAll()
        g.ashAlarm = 2.5; g.ashAlarmLevel = 2; g.ashSquadsSent = 0; g.ashReinforceT = 0
        g.ashSpot = stand; g.ashSpotSeen = -999
        tick(0.05)
        let squad = g.mobs.mobs.filter { $0.brain?.extra == true }
        let roles = Set(squad.compactMap { $0.brain?.role })
        let mgGun = squad.first { $0.brain?.role == AshArmy.mg }?.brain?.gun == Guns.smg
        let far0 = squad.map { simd_length($0.pos - stand) }.max() ?? 0
        var e: Float = 0
        while e < 12 { g.health = 20; g.alive = true; g.tick(0.05); g.player.pos = stand; g.player.vel = .zero; w.pendingMobs.removeAll(); e += 0.05 }
        let near1 = squad.filter { $0.health > 0 }.map { simd_length($0.pos - stand) }.min() ?? 999
        check(squad.count == 5 && roles.isSuperset(of: [0, AshArmy.mg, AshArmy.medic]) && mgGun && squad.contains { $0.kind == .soldierOfficer }
              && far0 > 18 && near1 < far0 - 8 && toasts.contains { $0.contains("moving to the last contact") },
              "ash vault reinforcements: at Alarm a squad of \(squad.count) (officer, MG gunner, medic, rifleman) leaves \(far0 > 18 ? "the loaded edge" : "too close") and closes from \(Int(far0)) to \(Int(near1)) blocks in 12 s")
        // Total War: armour comes too.
        g.mobs.mobs.removeAll()
        g.ashAlarm = 3.5; g.ashAlarmLevel = 3; g.ashSquadsSent = 1; g.ashReinforceT = 0
        tick(0.05)
        let armour = g.mobs.mobs.contains { $0.kind.ashVehicle && $0.brain?.order != nil }
        // The unit cap: with 64 Ashguard near, nothing more is sent.
        g.mobs.mobs.removeAll()
        for i in 0..<64 { let m = Mob(.soldierRecruit, at: stand + V3(Float(i % 8) * 2 - 8, 0, Float(i / 8) * 2 + 20)); m.ashSetup(); g.mobs.mobs.append(m) }
        let capped0 = AshArmy.capped
        let sent = g.ashSendSquad(patrol: false, armour: false)
        check(armour && !sent && AshArmy.capped > capped0, "ash vault reinforcements: armour rolls at Total War (\(armour)); the unit cap (\(AshArmy.unitCap)) holds back a squad with 64 near (\(!sent))")

        // A patrol at Quiet walks between the two sites nearest and turns at the end of its leg.
        g.mobs.mobs.removeAll()
        g.ashAlarm = 0; g.ashAlarmLevel = 0; g.ashPatrolT = 0
        tick(0.05)
        let patrol = g.mobs.mobs.filter { $0.brain?.leg != nil }
        var turned = false
        if let p = patrol.first, let leg = p.brain?.leg, let o = p.brain?.order {
            p.pos = V3(o.x, p.pos.y, o.z)
            _ = p.ashRoleAI(0.05, g, dist: 40, canTarget: true)
            if let o2 = p.brain?.order { turned = simd_length(V2(o2.x - leg.0.x, o2.z - leg.0.z)) < 4 }
        }
        check(patrol.count >= 3 && patrol.allSatisfy { $0.brain?.ready == true } && turned && patrol.contains { $0.brain?.role == AshArmy.medic },
              "ash vault patrols: a squad of \(patrol.count) on its leg between the two nearest sites, weapons at the ready, turning at the end (\(turned))")

        // Mortars and field guns: every shell marked 1.5 s+ before it lands, then the shell.
        g.mobs.mobs.removeAll(); g.ashStrikes.removeAll()
        let crew = Mob.structureMob("soldier_trooper:mortar@ash", at: stand + V3(0, 0, 70))!
        g.mobs.mobs.append(crew)
        g.ashSpot = stand; g.ashSpotSeen = g.clock
        crew.soldierBrain.ashTimer = 0
        _ = crew.ashRoleAI(0.05, g, dist: 70, canTarget: true)
        let mortarStrike = g.ashStrikes.first
        let warning = (mortarStrike?.t ?? 0) + AshArmy.fallTime
        var whistled = false, shellOut = false
        let slugs0 = g.arms.slugs.count
        tick(4) {
            if g.ashStrikes.first?.whistled == true { whistled = true }
            if g.arms.slugs.count > slugs0 { shellOut = true }
        }
        let gun = Mob.structureMob("ash_artillery@ash^0", at: stand + V3(0, 0, 80))!
        g.mobs.mobs.append(gun)
        gun.aggro = true
        g.ashStrikes.removeAll()
        var markers: [Float] = []
        e = 0
        while e < 20 {
            g.ashSpot = stand; g.ashSpotSeen = g.clock
            let n0 = g.ashStrikes.count
            _ = gun.ashVehicleAI(0.05, g, dist: 80, canTarget: true)
            if g.ashStrikes.count > n0, let m = g.ashStrikes.last { markers.append(m.t) }
            g.clock += 0.05; e += 0.05
        }
        // 21 blocks off: no flat shot without a fair warning.
        gun.pos = stand + V3(0, 0, 21)
        gun.soldierBrain.reload = 0
        let close0 = g.ashStrikes.count
        e = 0
        while e < 12 {
            g.ashSpot = stand; g.ashSpotSeen = g.clock
            _ = gun.ashVehicleAI(0.05, g, dist: 21, canTarget: true)
            g.clock += 0.05; e += 0.05
        }
        // Close in it lobs high rather than fire a flat shot that lands in under a second.
        let heldFire = g.ashStrikes.dropFirst(close0).allSatisfy { $0.t >= 1.6 }
        check(mortarStrike != nil && warning >= AshArmy.minWarning && whistled && shellOut && !markers.isEmpty && markers.allSatisfy { $0 >= 1.6 } && heldFire,
              String(format: "ash vault shells: a mortar crew fires on the spotted position (marked %.1f s ahead, whistle, shell); a field gun's %d shells each marked %.1f s+ ahead; close in only fair shots (%@)",
                     warning, markers.count, markers.min() ?? 0, heldFire ? "yes" : "no"))

        // Medics, MG gunners, officers calling armour.
        g.mobs.mobs.removeAll(); g.ashStrikes.removeAll()
        let medic = Mob.structureMob("soldier_recruit:medic@ash", at: stand + V3(30, 0, 0))!
        let hurtOne = Mob.structureMob("soldier_trooper@ash", at: stand + V3(36, 0, 0))!
        hurtOne.health = hurtOne.spec.health / 3
        g.mobs.mobs += [medic, hurtOne]
        let h0 = hurtOne.health, healed0 = AshArmy.healed
        e = 0
        while e < 8 {
            let sp = medic.ashRoleAI(0.05, g, dist: 30, canTarget: false) ?? 0
            if sp > 0 { medic.pos += medic.forward * sp * 0.05 }
            e += 0.05
        }
        let healed = hurtOne.health > h0 + hurtOne.spec.health / 5 && AshArmy.healed > healed0
        let gunner = Mob.structureMob("soldier_trooper:mg@ash", at: stand + V3(0, 0, 20))!
        g.mobs.mobs.append(gunner)
        gunner.aggro = true
        let gb = gunner.soldierBrain
        gb.lastSeen = stand + V3(10, 1.4, 0); gb.seenAgo = 0.5; gb.sees = false; gb.react = 0; gb.shotTimer = 0
        // The player ducked behind a wall from where he was seen (10 blocks along, in the open): out of sight, the gunner
        // hoses that spot (in view, the ordinary AI takes over).
        var wall: [(Int, Int, Int, BlockID)] = []
        let wz = Int(floor(stand.z)) + 10
        for dx in -2...2 { for dy in 0...4 {
            let x = Int(floor(stand.x)) + dx, y = Int(floor(stand.y)) + dy
            wall.append((x, y, wz, g.world.block(x, y, wz))); g.world.setBlock(x, y, wz, STONE)
        } }
        let s0 = g.arms.slugs.count, mag0 = gb.mag
        for _ in 0..<20 { _ = gunner.ashRoleAI(0.05, g, dist: 20, canTarget: true) }
        let suppressed = gb.mag < mag0 || g.arms.slugs.count > s0
        for (x, y, z, b) in wall { g.world.setBlock(x, y, z, b) }
        let officer = Mob(.soldierOfficer, at: stand + V3(10, 0, 30))
        officer.ashSetup()
        let idle = Mob.structureMob("ash_tank@ash^0", at: stand + V3(40, 0, 80))!
        g.mobs.mobs += [officer, idle]
        g.ashArmourCall = -999
        officer.ashCallArmour(g)
        let called = idle.aggro && idle.brain?.order != nil
        check(healed && gb.gun == Guns.smg && suppressed && called,
              "ash vault squads: a medic patches a soldier from \(h0) to \(hurtOne.health) health; an MG gunner keeps firing at the last spot (\(suppressed)); an officer calls the idle tank (\(called))")

        // A wrecked tank: debris, a fire that burns on, two crew out fighting.
        g.mobs.mobs.removeAll()
        let wreck = Mob.structureMob("ash_tank@ash^0", at: stand + V3(0, 0, 30))!
        g.mobs.mobs.append(wreck)
        let bailed0 = AshArmy.bailedOut
        wreck.killedByPlayer = true
        g.ashUnitDied(wreck)
        let crewOut = g.mobs.mobs.filter { $0.kind == .soldierCrew && $0.aggro && $0.fire > 0 }
        check(crewOut.count == 2 && AshArmy.bailedOut == bailed0 + 2 && !g.ashWrecks.isEmpty && toasts.contains { $0.contains("bails out") },
              "ash vault vehicles: a wrecked tank burns (\(g.ashWrecks.count) wreck fires) and its crew of \(crewOut.count) bails out fighting")
        g.mobs.mobs.removeAll(); g.ashWrecks.removeAll()
    }

    // The biggest battle: the player at the citadel's north gate at Total War, every Ashguard unit loaded around it
    // awake and fighting. Game.tick timed over 30 s of play.
    // The battle's setting (also rendered by questcheck --render for the draw side): the player at the north gate at
    // Total War, the loaded garrisons awake and on him.
    @discardableResult
    static func battleScene(_ g: Game) -> V3 {
        let y = Float(AshWar.ground + 1)
        let stand = V3(0.5, y, -47.5)
        g.changeDimension(to: .deep, at: stand)
        let w = g.world
        _ = w.loadSync(center: stand, radius: 6)
        g.mobs.mobs.removeAll()
        g.survival = true; g.alive = true; g.paused = false; g.menu = nil; g.difficulty = 2
        g.player.pos = stand; g.player.flying = false
        g.ashVictory = false
        g.ashAlarm = 3.5; g.ashAlarmLevel = 3; g.ashSquadsSent = 0; g.ashReinforceT = 0
        // Let the loaded chunks' garrisons arrive.
        for _ in 0..<20 { g.health = 20; g.tick(0.05); g.player.pos = stand; g.player.vel = .zero }
        for m in g.mobs.mobs where m.faction == Faction.ashguard.rawValue && simd_length(m.pos - stand) < 60 {
            m.aggro = true
            m.brain?.lastSeen = g.player.eye
        }
        return stand
    }

    static func biggestBattle(_ g: Game, _ check: (Bool, String) -> Void) {
        let stand = battleScene(g)
        let skipped0 = AshArmy.lodSkipped
        var times: [Double] = []
        var peak = 0
        let dt: Double = 1 / 72
        for _ in 0..<(72 * 30) {
            g.health = 20; g.alive = true
            g.ashSpot = stand; g.ashSpotSeen = g.clock
            let t0 = CFAbsoluteTimeGetCurrent()
            g.tick(dt)
            times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            g.player.pos = stand; g.player.vel = .zero
            peak = max(peak, g.mobs.mobs.filter { $0.health > 0 && $0.faction == Faction.ashguard.rawValue }.count)
        }
        let sorted = times.sorted()
        let avg = times.reduce(0, +) / Double(times.count)
        battle = (peak, avg, sorted[sorted.count * 95 / 100], sorted.last ?? 0, AshArmy.lodSkipped - skipped0)
        let near = g.mobs.mobs.filter { $0.health > 0 && $0.faction == Faction.ashguard.rawValue && simd_length_squared($0.pos - stand) < 128 * 128 }.count
        let extras = g.mobs.mobs.filter { $0.health > 0 && $0.brain?.extra == true }.count
        print(String(format: "ash vault battle: %d Ashguard units at peak (%d within 128 at the end), Game.tick avg %.2f ms, p95 %.2f ms, worst %.2f ms over %d ticks; far-AI ticks skipped %d",
                     peak, near, avg, battle.p95, battle.worst, times.count, battle.skipped))
        // The garrisons are fixed by the layout (114 round the citadel); the caps hold what the war adds on top: no squad
        // joins past 64 units near the player, and reinforcements never pass 24 alive.
        check(peak >= 40 && extras <= AshArmy.extrasCap && avg < 8 && battle.p95 < 14,
              String(format: "ash vault perf: the biggest battle (citadel, Total War) %d units, Game.tick avg %.2f ms, p95 %.2f ms (budget 8 / 14: the 72 Hz frame is 13.9 ms); reinforcements %d (cap %d)", peak, avg, battle.p95, extras, AshArmy.extrasCap))
    }
}
