import Foundation
import simd

// The Ash Vault's army at war (the gap pass, docs/status/the-deep-expansion.md "Gap pass" D2):
//   Alarm          a vault-wide level (Quiet, Alert, Alarm, Total War): spotted lifts it to Alert at once, being watched
//                  (more so near the citadel) and killing their units raise it; unseen for 30 s it falls slowly. Each
//                  step sounds the siren and a radio line. Saved.
//   Reinforcements at Alarm and Total War, squads (officer, MG gunner, riflemen, medic) leave the nearest garrison for
//                  your last known position; at Total War every other one brings a half-track, later a tank.
//   Patrols        at Quiet and Alert, foot squads walk between the two sites nearest you and back.
//   Roles          mortar crews lob shells at whatever the army has spotted; medics heal the wounded; MG gunners keep
//                  firing at the last spot they saw you for 3 s; officers who see you call the nearest idle tank.
//   Fair shells    every mortar, field-gun and Marshal shell is marked: red smoke where it lands and a falling whistle
//                  1.5 s or more before it does.
//   Wrecks         a wrecked tank or half-track throws plate debris, burns for 20 s, and its crew bails out fighting.
//   Unit cap / LOD at most 64 Ashguard units near you before more are sent, 24 of them extras (patrols and
//                  reinforcements); calm soldiers more than 64 blocks off think four times a second.
struct AshStrike {
    var at: V3
    var t: Float                    // seconds until the shell drops in (it falls its last 26 blocks in AshArmy.fallTime)
    var power: Float = 1.5
    var from: ObjectIdentifier?
    var by = "Ashguard"
    var shell = true                // false: only the marker for a field gun's own shell, already in flight
    var whistled = false
}

enum AshArmy {
    static let fallTime: Float = 0.47
    static let minWarning: Float = 1.5
    static let unitCap = 64
    static let extrasCap = 24
    static let lodRange: Float = 64
    static let lodStep: Float = 0.25
    static var lodSkipped = 0                       // far-AI ticks skipped (the perf check)
    static let levels = ["Quiet", "Alert", "Alarm", "Total War"]
    static let fightLodRange: Float = 40, fightLodStep: Float = 0.1
    static let beltMag = 90                        // the squad MG: a belt-fed light gun (the SMG's action), 90 rounds a belt
    static let radioUp = ["",
                          "Radio: \"All posts, intruder in the vault. Eyes open.\"",
                          "Radio: \"Alarm, alarm! Squads to the last contact. Mortars, fire on spotting.\"",
                          "Radio: \"Total war. Every unit, every gun. Armour rolls now.\""]
    static let radioDown = ["Radio: \"Stand down. Back to your posts.\"",
                            "Radio: \"Contact lost. Hold at Alert.\"",
                            "Radio: \"Still searching. Stay at Alarm.\""]
    static let chatter = ["Radio: \"...Cinderhold to citadel. Quiet shift. Lamp four is out again.\"",
                          "Radio: \"...Slagford reporting. The shell train is late.\"",
                          "Radio: \"...Emberwatch, two men down with the heat. Requesting the medic.\"",
                          "Radio: \"...Last Lamp, nothing from the surface. Nothing for eleven years.\"",
                          "Radio: \"...Airfield One. Engines turned over. Still no orders to fly.\"",
                          "Radio: \"...citadel to all towns. The Marshal reminds you the surface is lost.\""]
    // Squad roles (SoldierBrain.role).
    static let mortar = 1, medic = 2, mg = 3
    static func role(_ tag: String) -> Int? {
        switch tag {
        case "mortar": return mortar
        case "medic": return medic
        case "mg": return mg
        default: return nil
        }
    }
    // Where a squad comes from, by name.
    static func siteName(_ s: AshSite) -> String {
        switch s.kind {
        case "hq": return "the citadel"
        case "town": return AshWar.townName(s)
        case "airfield": return AshWar.airfieldName
        case "motorpool": return "the motor pool"
        case "staging": return "the tank column"
        default: return "the \(s.kind)"
        }
    }
}

extension Mob {
    func ashTakeRole(_ r: Int) {
        let b = soldierBrain
        b.role = r
        if r == AshArmy.mg { b.gun = Guns.sturmwind; b.mag = AshArmy.beltMag }
    }

    // Role behaviour before the ordinary soldier AI; nil = carry on as an ordinary soldier.
    func ashRoleAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float? {
        let b = soldierBrain
        // A patrol walks its leg; at one end it turns for the other.
        if let leg = b.leg, !aggro, let o = b.order, simd_length(V2(o.x - pos.x, o.z - pos.z)) < 2.5 {
            b.order = simd_length(V2(o.x - leg.1.x, o.z - leg.1.z)) < 4 ? leg.0 : leg.1
            b.ready = true
        }
        switch b.role {
        case AshArmy.mortar:
            // Up close the crew fights; otherwise it stays at the tube and fires on what the army has spotted.
            // Nothing the tube can reach (closer than 24 or no fresh spot): the crew fights with its rifles.
            guard !VaultObjectives.done("guns"), canTarget, !g.ashVictory, let spot = g.ashSpot, g.clock - g.ashSpotSeen < VaultObjectives.spotWindow,
                  g.ashTubeNear(pos) else { return aggro ? nil : 0 }                // P318: a spiked tube doesn't fire
            let flat = simd_length(V2(spot.x - pos.x, spot.z - pos.z))
            guard flat > 24 && flat < 170, dist > 18 || !aggro else { return nil }
            moving = false; wanderGoal = nil; strafe = 0
            b.ashTimer -= dt
            face(spot)
            // The loader (a recruit) fires only when the gunner is down (no other crew within 4 blocks).
            let gunner = Soldier.rank(kind) != 0
                || !g.mobs.mobs.contains { $0 !== self && $0.health > 0 && $0.brain?.role == AshArmy.mortar && simd_length_squared($0.pos - pos) < 16 }
            if b.ashTimer <= 0 && gunner {
                b.ashTimer = (g.difficulty >= 3 ? 6 : 8) + Rand.float(in: 0...2)
                let spread = 1.5 + flat * 0.03
                let at = V3(spot.x + Rand.float(in: -spread...spread), spot.y, spot.z + Rand.float(in: -spread...spread))
                let flight = max(AshArmy.minWarning + 0.4, 2.2 + flat / 80)
                g.ashStrikes.append(AshStrike(at: at, t: flight - AshArmy.fallTime, power: 1.0, from: ObjectIdentifier(self), by: spec.name))
                g.sfx(.gun(9), 0.6, at: pos + V3(0, 1, 0))
                g.particles.smoke(at: pos + V3(0, 1.6, 0))
            }
            return 0
        case AshArmy.medic:
            // Out of the fight for a moment (not seen in 1.5 s, not hit): run to the worst wounded within 14 and patch
            // them up (8 % of their health a second).
            b.healScan -= dt
            if b.healScan <= 0 {
                b.healScan = 1
                var worst: Mob?, frac: Float = 0.6
                for m in g.mobs.mobs where m !== self && m.health > 0 && m.faction == Faction.ashguard.rawValue && Soldier.rank(m.kind) != nil
                    && m.kind != .ashMarshal && simd_length_squared(m.pos - pos) < 196 {
                    let f = Float(m.health) / Float(m.spec.health)
                    if f < frac { frac = f; worst = m }
                }
                b.patient = worst
            }
            guard let p = b.patient, p.health > 0, p.health < p.spec.health, b.seenAgo > 1.5, hurt <= 0 else { return nil }
            let d = simd_length(V2(p.pos.x - pos.x, p.pos.z - pos.z))
            face(p.pos)
            if d > 1.8 { moving = true; return spec.speed * 0.95 }
            moving = false
            b.ashTimer += dt * Float(p.spec.health) * 0.08
            if b.ashTimer >= 1 {
                let n = Int(b.ashTimer)
                p.health = min(p.spec.health, p.health + n)
                b.ashTimer -= Float(n)
                AshArmy.healed += n
                if Rand.float(in: 0..<1) < 0.5 { g.particles.hearts(at: p.pos + V3(0, p.height, 0)) }
            }
            if p.health >= p.spec.health { b.patient = nil }
            return 0
        case AshArmy.mg:
            // Suppressing fire: for 3 s after losing sight, the gunner keeps hosing the last spot.
            guard aggro, canTarget, !b.sees, b.seenAgo < 3, let t = b.lastSeen, b.reload <= 0, b.mag > 0 else { return nil }
            // Still looking for the target while hosing the spot: back in view, the ordinary AI aims at it again.
            b.losTimer -= dt
            if b.losTimer <= 0 {
                b.losTimer = 0.25
                if g.world.canSee(eye, g.player.eye) { b.sees = true; b.seenAgo = 0; b.lastSeen = g.player.eye; return nil }
            }
            b.seenAgo += dt
            b.shotTimer -= dt
            face(t)
            let gs = Guns.all[b.gun]
            soldierFire(dt, g, b, gs, rank: Soldier.rank(kind) ?? 1, dist: simd_length(t - eye), target: t)
            return 0
        default:
            return nil
        }
    }

    // An officer who sees the player calls the nearest idle tank (at most every 45 s across the army).
    func ashCallArmour(_ g: Game) {
        guard Soldier.rank(kind) == 4, g.clock - g.ashArmourCall > 45, !g.ashVictory else { return }
        // One look round the army: found or not, the next call waits (an officer in sight with no tank near looked
        // every frame).
        g.ashArmourCall = g.clock
        var tank: Mob?, best: Float = 200 * 200
        for m in g.mobs.mobs where m.kind == .ashTank && m.health > 0 && !m.aggro {
            let d = simd_length_squared(m.pos - pos)
            if d < best { best = d; tank = m }
        }
        guard let tank else { g.ashArmourCall = g.clock - 30; return }      // nothing near: look again in 15 s
        let tb = tank.soldierBrain
        tb.order = g.player.pos
        tb.lastSeen = g.player.eye
        tank.aggro = true
        tank.lockTime = max(tank.lockTime, 30)
        AshArmy.armourCalls += 1
        g.sfx(.gun(11), 1.0, at: eye)
        g.onToast?("An Ashguard officer radios for armour")
    }
}

extension AshArmy {
    static var healed = 0                          // health given back by medics (the check)
    static var armourCalls = 0
    static var squadsSent = 0
    static var patrolsSent = 0
    static var bailedOut = 0
    static var gunsWrecked = 0                     // (harness: gun mounts broken up, P459)
}

extension Game {
    // Every frame in the Deep (deepTick): marked shells, wrecks burning, and once a second the alarm and what follows.
    func ashArmyTick(_ dt: Float) {
        ashShellTick(dt)
        ashWreckTick(dt)
        guard alive, !ashVictory else {
            if ashVictory { ashAlarm = 0; ashAlarmLevel = 0 }
            return
        }
        ashAlarmTick(dt)
    }

    func ashShellTick(_ dt: Float) {
        var i = 0
        while i < ashStrikes.count {
            ashStrikes[i].t -= dt
            let s = ashStrikes[i]
            let left = s.t + (s.shell ? AshArmy.fallTime : 0)
            if !s.whistled && left <= AshArmy.minWarning {
                ashStrikes[i].whistled = true
                sfx(.shellIncoming, 1.2, at: s.at + V3(0, 4, 0))
            }
            if s.t <= 0 {
                if s.shell {
                    var shell = Slug(pos: s.at + V3(0, 26, 0), vel: V3(0, -55, 0), kind: .shell, damage: 0, fromPlayer: false,
                                     shooter: s.from, by: s.by, life: 2, gravity: 9)
                    shell.power = s.power
                    arms.spawn(shell)
                }
                ashStrikes.remove(at: i)
                continue
            }
            // The red smoke marker where it will land.
            if Rand.float(in: 0..<1) < dt * 14 {
                particles.add(Particle(pos: s.at + V3(Rand.float(in: -0.3...0.3), 0.2, Rand.float(in: -0.3...0.3)), vel: V3(0, 2.5, 0), life: 0.5,
                                       maxLife: 0.5, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: 0.18, gravity: -1,
                                       color: V3(2.6, 0.3, 0.15), collide: false, glow: true))
            }
            i += 1
        }
    }

    func ashWreckTick(_ dt: Float) {
        var i = 0
        while i < ashWrecks.count {
            ashWrecks[i].t -= dt
            let w = ashWrecks[i]
            if w.t <= 0 { ashWrecks.remove(at: i); continue }
            if Rand.float(in: 0..<1) < dt * 6 { particles.smoke(at: w.at + V3(Rand.float(in: -1...1), Rand.float(in: 0.5...1.5), Rand.float(in: -1...1))) }
            if Rand.float(in: 0..<1) < dt * 10 { particles.flame(at: w.at + V3(Rand.float(in: -0.8...0.8), Rand.float(in: 0.3...1.2), Rand.float(in: -0.8...0.8))) }
            i += 1
        }
    }

    // A vehicle brewed up (ashUnitDied): plate debris, a fire that burns on, and the crew out of the hatches.
    // P464 (Oct 25 19:36, "This tank should get destroyed as if it were made out of blocks... They don't get destroyed
    // like that?"): the hull comes apart: its biggest pieces (hull, turret, gun, track runs, wheels...) as they stood,
    // each broken in two or three and thrown out from the blast, tumbling down and lying about (the debris bodies,
    // in the plating's metal), instead of the model vanishing in the smoke.
    func ashBreakUp(_ m: Mob, _ plate: BlockID) {
        let parts = mobModelParts(m)
        guard !parts.isEmpty else { return }
        let k = (m.sized ? 1 : m.scale) / 16
        let cy = cosf(m.yaw), sy = sinf(m.yaw)
        let mid = m.pos + V3(0, m.height * 0.4, 0)
        let big = parts.map { p -> (Part, Float) in let s = p.mx - p.mn; return (p, s.x * s.y * s.z) }
            .sorted { $0.1 > $1.1 }.prefix(m.kind == .ashBehemoth ? 18 : 12)
        var seed = UInt32(truncatingIfNeeded: Int(m.pos.x * 7 + m.pos.z * 13) &* 2654435761)
        for (p, _) in big {
            let size = (p.mx - p.mn) * k
            guard min(size.x, min(size.y, size.z)) > 0.04 else { continue }
            let q = p.place((p.mn + p.mx) * 0.5, p.rotation) * k
            let at = m.pos + V3(cy * q.x + sy * q.z, q.y, -sy * q.x + cy * q.z)
            let out = at - mid + V3(0, 0.6, 0)
            let dir = simd_length(out) > 1e-3 ? simd_normalize(out) : V3(0, 1, 0)
            let vol = size.x * size.y * size.z
            seed = seed &* 1664525 &+ 1013904223
            debris.bits(plate, at: at, size: SIMD3(size.x, size.y, size.z), direction: dir, count: vol > 1.5 ? 3 : 2,
                        speed: 5 + 4 / (1 + vol), seed: seed)
        }
    }

    // P459 (Oct 25 16:26-16:30, his flak gun on a Capital gun: "I wish these guns actually had blocks that they're made
    // up of... It should have been obliterated"; "I can't seem to destroy the little guns here"): a gun mount destroyed
    // no longer just vanishes. It bursts (smoke, a flash, no blocks broken) and its biggest pieces (shield, barrels,
    // cradle, mount) fly off as debris in its own plate: white for the Capital's, grey for Greywall's, steel otherwise.
    func gunWrecked(_ m: Mob) {
        let key: String
        switch m.factionValue {
        case .steelhold, .meridian: key = "white_concrete"
        case .greywall: key = "light_gray_concrete"
        default: key = "iron_block"
        }
        guard Blocks.has(key) else { return }
        let at = m.pos + V3(0, m.height * 0.5, 0)
        particles.explosion(at: at, power: 1.4)
        for _ in 0..<6 { particles.smoke(at: at + V3(Rand.float(in: -0.8...0.8), Rand.float(in: 0...1.2), Rand.float(in: -0.8...0.8))) }
        sfx(.debrisRain, 0.9, at: at)
        // P473 (Oct 26 19:42: "The gun is the structure. It doesn't have to turn into a bunch of blocks afterwards"): it
        // stays as its burnt hulk (NavalGuns.wreck); a few fittings fly. On a ship's deck it still comes apart.
        if m.deck == nil { ashShed(m, Blocks.id(key), count: 4) } else { ashBreakUp(m, Blocks.id(key)) }
        AshArmy.gunsWrecked += 1
    }

    func ashWreck(_ m: Mob) {
        let plate = Blocks.id(m.boreal && Blocks.has("bunker_concrete") ? "bunker_concrete" : "ash_plating")   // (P460: white plate)
        let c = IVec3(Int(floor(m.pos.x)), Int(floor(m.pos.y + 1)), Int(floor(m.pos.z)))
        for _ in 0..<6 { particles.blockBreak(plate, at: IVec3(c.x + Rand.int(in: -1...1), c.y + Rand.int(in: 0...1), c.z + Rand.int(in: -1...1))) }
        sfx(.debrisRain, 1.0, at: m.pos)
        ashWrecks.append((at: m.pos, t: 20))
        if ashWrecks.count > 12 { ashWrecks.removeFirst() }
        // Fire on the ground beside the hull where there's room.
        let w = world
        for (dx, dz) in [(2, 0), (-2, 0), (0, 2)] {
            let x = c.x + dx, z = c.z + dz, y = c.y - 1
            if w.isAir(x, y, z) && w.solidAt(x, y - 1, z) { w.setBlock(x, y, z, FIRE) }
        }
        // P473 (Oct 26 19:27: wrecks that "still look decent"): the vehicle stays as its burnt hulk, a few fittings thrown
        // off; on a ship's deck (a crawler's cargo) it still comes apart.
        if m.deck == nil { ashShed(m, plate, count: 5); Hulks.add(m) } else { ashBreakUp(m, plate) }
        guard m.kind == .ashTank || m.kind == .ashHalftrack else { return }
        let n = m.kind == .ashTank ? 2 : 1
        for i in 0..<n {
            let side: Float = i == 0 ? 1 : -1
            let off = V3(cosf(m.yaw) * 2.2 * side, 0, -sinf(m.yaw) * 2.2 * side)
            let crew = Mob(.soldierCrew, at: m.pos + off)
            if !m.boreal { crew.ashSetup() }               // (P460: a Boreal tank's crew are the Capital's)
            crew.aggro = true
            crew.fire = 3                                  // out of a burning hull
            crew.health = max(1, crew.spec.health * 2 / 3)
            crew.soldierBrain.lastSeen = player.eye
            crew.soldierBrain.seenAgo = 0
            crew.soldierBrain.extra = true
            crew.lockTime = 20
            mobs.mobs.append(crew)
            AshArmy.bailedOut += 1
        }
        onToast?("The crew bails out of the burning \(m.kind == .ashTank ? "tank" : "half-track")")
    }

    func ashAlarmTick(_ dt: Float) {
        let inVault = dim.dim == .deep && DeepGen.inVault(player.pos.y)
        let seen = clock - ashSpotSeen < 0.6
        if seen && inVault {
            ashUnseen = 0
            if ashAlarm < 1 { ashAlarm = 1 }                       // spotted at all: Alert
            var rise: Float = 0.05
            if simd_length(V2(player.pos.x, player.pos.z)) < 140 { rise += 0.05 }   // closing on the citadel
            ashAlarm += rise * dt
        } else {
            ashUnseen += dt
            if ashUnseen > 30 { ashAlarm -= 0.012 * dt }
        }
        ashAlarm = max(0, min(3.99, ashAlarm))
        let lvl = Int(ashAlarm)
        if lvl != ashAlarmLevel { ashAnnounce(lvl, up: lvl > ashAlarmLevel) }
        guard inVault else { return }
        // Once a second: squads and patrols left far behind (over 160 blocks) stand down and go.
        if Int(clock) != Int(clock - Double(dt)) {
            let p = player.pos
            mobs.mobs.removeAll { $0.brain?.extra == true && simd_length_squared($0.pos - p) > 160 * 160 }
            ashClearedTick()
        }
        // Reinforcements, patrols, the radio rooms.
        ashReinforceT -= dt
        ashPatrolT -= dt
        ashRadioT -= dt
        if lvl >= 2 && ashReinforceT <= 0 {
            ashReinforceT = lvl == 3 ? 35 : 55
            let allowed = (lvl == 2 ? 2 : 5) + (difficulty >= 3 ? 1 : 0)
            if ashSquadsSent < allowed && difficulty > 0 {
                if ashSendSquad(patrol: false, armour: lvl == 3 && ashSquadsSent % 2 == 1) { ashSquadsSent += 1 }
            }
        }
        if lvl <= 1 && ashPatrolT <= 0 {
            ashPatrolT = lvl == 1 ? 50 : 75
            var walking = 0
            for m in mobs.mobs where m.health > 0 && m.brain?.leg != nil { walking += 1 }
            if walking < 8 && difficulty > 0 { _ = ashSendSquad(patrol: true, armour: false) }
        }
        if ashRadioT <= 0 {
            for s in AshWar.townSites where simd_length(AshWar.radioRoom(s) - player.pos) < 12 {
                ashRadioT = 25
                let line = AshArmy.chatter[Int(clock / 25) % AshArmy.chatter.count]
                sfx(.gun(11), 0.8, at: AshWar.radioRoom(s))
                onToast?(line)
                break
            }
        }
    }

    // The alarm on the HUD in the vault once it is above Quiet: the level by name, the bar filling toward Total War.
    func ashAlarmBar() -> (String, Float, V4)? {
        guard dim.dim == .deep, !ashVictory, ashAlarmLevel >= 1, DeepGen.inVault(player.pos.y) else { return nil }
        let c: [V4] = [V4(0.5, 0.5, 0.5, 1), V4(0.9, 0.7, 0.15, 1), V4(0.95, 0.35, 0.1, 1), V4(0.95, 0.08, 0.05, 1)]
        return ("Ashguard alarm: \(AshArmy.levels[ashAlarmLevel])", ashAlarm / 4, c[ashAlarmLevel])
    }

    func ashAnnounce(_ lvl: Int, up: Bool) {
        ashAlarmLevel = lvl
        if lvl == 0 { ashSquadsSent = 0 }
        if up {
            sfx(.gun(11), 1.0, at: player.eye)          // P319: from Alarm up the garrison sirens wail (AshSiren.swift)
            onToast?("\(AshArmy.levels[lvl] == "Alarm" ? "Alarm raised" : "Alarm: " + AshArmy.levels[lvl]). \(AshArmy.radioUp[lvl])")
        } else {
            sfx(.gun(11), 0.8, at: player.eye)
            onToast?("\(AshArmy.levels[lvl] == "Alarm" ? "Alarm raised" : "Alarm: " + AshArmy.levels[lvl]). \(AshArmy.radioDown[lvl])")
        }
    }

    // Kills raise the alarm (ashUnitDied).
    func ashAlarmKill(_ m: Mob) {
        guard m.killedByPlayer, !ashVictory else { return }
        ashAlarm = min(3.99, max(ashAlarm, 1) + (m.kind.ashVehicle ? 0.5 : 0.2))
        ashUnseen = 0
    }

}

extension AshArmy {
    // P307 (b): the sites that send squads, their key and how many squads each has in it over the whole game.
    static let senders = ["hq", "motorpool", "staging", "town", "supply", "airfield", "fueldepot"]
    static func siteKey(_ s: AshSite) -> String { "\(s.kind)@\(s.x),\(s.z)" }
    static func squadBudget(_ s: AshSite) -> Int {
        switch s.kind {
        case "hq": return 8
        case "supply", "fueldepot": return 3
        default: return 4
        }
    }
    static let sendReach: Float = 400           // a reinforcement comes only from a garrison this near the last contact
    // A patrol walks only between two sites this near the player. P499 (host check): 300 left the vault's middle
    // ground (its sites 210 and 340 blocks off) with no patrol at all; 400, as far as a reinforcement comes.
    static let patrolReach: Float = 400
}

extension Game {
    // P307 (b) (Oct 15 12:13, "if I'm clearing a base, it should be cleared; when I kill somebody, no one else is gonna
    // bother me"): once a second, a sending site by the player with its ground loaded and not one of its own soldiers
    // (patrols and squads passing through don't count) left alive for 3 s is cleared for good: it sends no patrol or
    // squad again. Its garrison came with the ground and never comes back.
    func ashClearedTick() {
        let p = player.pos
        for s in AshWar.sites where AshArmy.senders.contains(s.kind) {
            let r = Float(s.r)
            let cx = Float(s.x) + 0.5, cz = Float(s.z) + 0.5
            guard max(abs(p.x - cx), abs(p.z - cz)) < r + 48 else { continue }
            let key = AshArmy.siteKey(s)
            guard !ashCleared.contains(key) else { continue }
            guard world.isLoaded(s.x - s.r, s.z - s.r), world.isLoaded(s.x + s.r, s.z + s.r),
                  world.isLoaded(s.x - s.r, s.z + s.r), world.isLoaded(s.x + s.r, s.z - s.r) else { ashEmptyFor[key] = 0; continue }
            let pad = r + 10
            let manned = mobs.mobs.contains { m in
                m.health > 0 && m.faction == Faction.ashguard.rawValue && m.brain?.extra != true
                    && abs(m.pos.x - cx) < pad && abs(m.pos.z - cz) < pad
            }
            if manned { ashEmptyFor[key] = 0; continue }
            let t = (ashEmptyFor[key] ?? 0) + 1
            ashEmptyFor[key] = t
            if t >= 3 { ashCleared.insert(key); ashEmptyFor[key] = nil }
        }
    }

    // A squad on foot (and at Total War a vehicle) sent from the garrison nearest the player's last known spot: a
    // reinforcement runs there; a patrol walks between the two sites nearest the player. False when the cap, the
    // ground or the army's own losses stop it.
    // P307 (a): it enters the loaded ground out of every player's sight (Game.spawnHidden), 40-96 blocks out on the
    // way from its site (it used to pick a spot 28-52 blocks off with a clear line to the player: in plain view).
    // P307 (b): only an uncleared garrison within reach with squads left in its budget sends one; out in the far vault
    // with no garrison near, nobody comes.
    @discardableResult
    func ashSendSquad(patrol: Bool, armour: Bool) -> Bool {
        let target = patrol ? player.pos : (ashSpot ?? player.pos)
        var near = 0, extras = 0
        for m in mobs.mobs where m.health > 0 && m.faction == Faction.ashguard.rawValue && simd_length_squared(m.pos - player.pos) < 128 * 128 {
            near += 1
            if m.brain?.extra == true { extras += 1 }
        }
        let size = [3, 4, 5, 6][max(0, min(3, difficulty))]
        guard near + size <= AshArmy.unitCap, extras + size <= AshArmy.extrasCap else { AshArmy.capped += 1; return false }
        func dist(_ s: AshSite) -> Float { hypotf(Float(s.x) - target.x, Float(s.z) - target.z) }
        let reach = patrol ? AshArmy.patrolReach : AshArmy.sendReach
        let garrisons = AshWar.sites.filter { s in
            AshArmy.senders.contains(s.kind) && !ashCleared.contains(AshArmy.siteKey(s))
                && (ashSiteSquads[AshArmy.siteKey(s)] ?? 0) < AshArmy.squadBudget(s) && dist(s) < reach
        }
        let byDist = garrisons.sorted { dist($0) < dist($1) }
        guard let from = byDist.first, !patrol || byDist.count > 1 else { return false }
        var dir = V2(Float(from.x) - target.x, Float(from.z) - target.z)
        let len = simd_length(dir)
        dir = len > 1 ? dir / len : V2(1, 0)
        // A spot on the floor toward that garrison, as far out as the site (96 at most) down to 40 (or half the way to
        // a site nearer than that), that no player can see: they march in from out of view.
        let far = min(96, max(20, len))
        let nearest = min(40, far * 0.5)
        var spawn: V3?
        var r = far
        search: while r >= nearest {
            for side: Float in [0, 8, -8, 16, -16] {
                let x = Int(floor(target.x + dir.x * r - dir.y * side)), z = Int(floor(target.z + dir.y * r + dir.x * side))
                guard world.isLoaded(x, z) else { continue }
                for y in stride(from: Int(target.y) + 12, through: Int(target.y) - 12, by: -1)
                    where world.solidAt(x, y - 1, z) && world.isAir(x, y, z) && world.isAir(x, y + 1, z) {
                    let p = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
                    if spawnHidden(p, min: nearest, near: 56, clear: 128) { spawn = p; break search }
                    break
                }
            }
            r -= 8
        }
        guard let at = spawn else { return false }
        ashSiteSquads[AshArmy.siteKey(from), default: 0] += 1
        let ends: (V3, V3)? = patrol && byDist.count > 1
            ? (V3(Float(byDist[0].x) + 0.5, at.y, Float(byDist[0].z) + 0.5), V3(Float(byDist[1].x) + 0.5, at.y, Float(byDist[1].z) + 0.5)) : nil
        var kinds: [(MobKind, Int)] = [(.soldierOfficer, 0), (.soldierTrooper, AshArmy.mg), (.soldierRecruit, AshArmy.medic)]
        while kinds.count < size { kinds.append((kinds.count % 2 == 0 ? .soldierTrooper : .soldierRecruit, 0)) }
        for (i, (k, role)) in kinds.enumerated() {
            let a = Float(i) * 2.1
            let m = Mob(k, at: at + V3(cosf(a) * 1.6, 0, sinf(a) * 1.6))
            m.ashSetup()
            if role != 0 { m.ashTakeRole(role) }
            m.persistent = true                     // kept by the war, not the spawner; far stragglers go in ashAlarmTick
            let b = m.soldierBrain
            b.extra = true
            if let e = ends {
                b.leg = e
                b.order = e.1 + V3(cosf(a) * 2, 0, sinf(a) * 2)
                b.ready = true
            } else {
                b.order = target + V3(cosf(a) * 2.5, 0, sinf(a) * 2.5)
                b.orderRun = true
                m.home = target
            }
            mobs.mobs.append(m)
        }
        if armour {
            let v = Mob(ashSquadsSent >= 3 ? .ashTank : .ashHalftrack, at: at + V3(dir.y * 5, 0, -dir.x * 5))
            v.ashSetup()
            v.persistent = true
            let b = v.soldierBrain
            b.extra = true
            b.order = target
            v.aggro = true
            v.yaw = atan2f(dir.x, dir.y)
            b.turret = v.yaw
            mobs.mobs.append(v)
        }
        if patrol {
            AshArmy.patrolsSent += 1
        } else {
            AshArmy.squadsSent += 1
            sfx(.gun(11), 0.9, at: player.eye)
            onToast?("Radio: \"Squad from \(AshArmy.siteName(from)) moving to the last contact\(armour ? ", armour with them" : "").\"")
        }
        return true
    }
}

extension AshArmy {
    static var capped = 0                       // squads the unit cap held back
}
