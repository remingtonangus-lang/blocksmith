import Foundation
import simd

// The Ashguard's units (task 22): Cinder tanks, half-tracks, field guns and supply trucks (vehicle mobs drawn from
// parts), their soldiers (Steelhold ranks in Ashguard black, faction .ashguard) and the Ash Marshal (an officer-rank
// boss). Everything is black with red markings; no real-world insignia. Sites place them by name (AshSites.swift):
// "kind[:fuel][@ash][^heading]".

extension MobKind {
    var ash: Bool { (rawValue >= MobKind.ashTank.rawValue && rawValue <= MobKind.ashMarshal.rawValue) || self == .ashBehemoth || self == .ashChancellor }
    var ashVehicle: Bool { self == .ashTank || self == .ashHalftrack || self == .ashArtillery || self == .ashTruck || self == .ashBehemoth }
    var ashArmoured: Bool { ashVehicle }

    var ashSpec: Spec {
        switch self {
        case .ashTank:
            return Spec(name: "Cinder Tank", halfW: 1.7, height: 2.6, health: 180, speed: 2.4, behavior: .monster,
                        drops: [("iron_ingot", 3, 7), ("gunpowder", 2, 5), ("rocket_ammo", 0, 2)], xp: 60, call: .gun(12), fireImmune: true)
        case .ashHalftrack:
            return Spec(name: "Half-track", halfW: 1.3, height: 2.3, health: 110, speed: 4.4, behavior: .monster,
                        drops: [("iron_ingot", 2, 4), ("rifle_rounds", 4, 12)], xp: 30, call: .gun(12), fireImmune: true)
        case .ashArtillery:
            return Spec(name: "Ember Field Gun", halfW: 1.1, height: 1.8, health: 70, speed: 0, behavior: .monster,
                        drops: [("iron_ingot", 1, 3), ("gunpowder", 2, 6)], xp: 25, call: .gun(12), fireImmune: true)
        case .ashTruck:
            return Spec(name: "Army Truck", halfW: 1.2, height: 2.4, health: 40, speed: 3.6, behavior: .monster,
                        drops: [("iron_ingot", 0, 2), ("bread", 1, 4), ("rifle_rounds", 2, 8)], xp: 8, call: .gun(12))
        case .ashBehemoth:
            return Spec(name: "Ashguard Behemoth", halfW: 2.4, height: 3.5, health: 700, speed: 1.4, behavior: .monster,
                        drops: [("iron_ingot", 8, 16), ("netherite_scrap", 1, 3), ("heavy_rounds", 6, 14), ("gunpowder", 4, 10)], xp: 220,
                        call: .gun(12), fireImmune: true)
        case .ashChancellor:
            return Spec(name: "The Ash Chancellor", halfW: 0.36, height: 2.0, health: 420, speed: 2.8, behavior: .monster,
                        drops: [("diamond", 4, 9), ("gold_ingot", 8, 16), ("netherite_scrap", 2, 4), ("gun_sturmwind", 1, 1)], xp: 500,
                        call: .gun(11), fireImmune: true)
        default:
            return Spec(name: "The Ash Marshal", halfW: 0.38, height: 2.1, health: 380, speed: 3.0, behavior: .monster,
                        drops: [("gold_ingot", 4, 9), ("diamond", 2, 5), ("heavy_rounds", 4, 10), ("arc_cell", 2, 4), ("marshal_cap", 1, 1)], xp: 250,
                        call: .gun(11), fireImmune: true)
        }
    }
}

extension Mob {
    static let ashNames = ["Ashguard Rifleman", "Ashguard Stormer", "Ashguard Sharpshooter", "Ashguard Heavy", "Ashguard Officer", "Ashguard Driver"]

    var ashArmor: (Int, Float) {
        switch kind {
        case .ashTank: return (12, 4)
        case .ashHalftrack: return (8, 2)
        case .ashArtillery: return (6, 0)
        case .ashTruck: return (4, 0)
        case .ashBehemoth: return (16, 6)
        default: return (8, 2)
        }
    }

    // Joins the Ashguard: faction, names, the Marshal's size. Deep-down soldiers are tougher (power, like the Deep's
    // monsters). `loading`: a saved soldier keeps the health it was saved with.
    func ashSetup(loading: Bool = false) {
        faction = Faction.ashguard.rawValue
        // The army carries its own period-style arms (AshArms.swift); a soldier saved with a Capital gun swaps it on load.
        if Soldier.rank(kind) != nil && !Guns.isAshArm(variant) {
            variant = Soldier.ashGun(kind, roll: Rand.float(in: 0..<1))
            if let b = brain { b.gun = variant; b.mag = Guns.all[variant].mag }
        }
        if kind == .ashMarshal { scale = 1.12; return }
        if kind == .ashChancellor || kind == .ashBehemoth { persistent = true; return }
        if !kind.ash, let r = Soldier.rank(kind) {
            spec.name = Mob.ashNames[r]
            power = 1.4
            // The Deep expansion: a harder army than any surface garrison (DeepExpansionTests.army): veterans with twice
            // the health (a loaded soldier keeps the health it was saved with) and heavier plate (steelholdArmor). Twice,
            // not 7/4, since surface soldiers got class plate (TroopClasses, A2): deep balance keeps them a third harder.
            let old = spec.health
            spec.health = old * 2
            if !loading && health >= old { health = spec.health }
        }
    }

    // A structure mob by name: "kind[:fuel][@ash|@deep|@grey][^heading]" (AshSites.unit), or a plain kind key.
    static func structureMob(_ name: String, at p: V3) -> Mob? {
        var n = Substring(name)
        var heading: Float?
        if let i = n.firstIndex(of: "^") { heading = Float(n[n.index(after: i)...]); n = n[..<i] }
        var leash: V3?
        if let i = n.firstIndex(of: "~") {          // "~cx,cz,half": a Greywall base's leash (GreywallAlarm.swift)
            let v = n[n.index(after: i)...].split(separator: ",").compactMap { Float($0) }
            if v.count == 3 { leash = V3(v[0] + 0.5, v[1] + 0.5, v[2]) }
            n = n[..<i]
        }
        var ash = false, deep = false, boreal = false
        if n.hasSuffix("@boreal") { boreal = true; n = n.dropLast(7) }   // P460: a Boreal Station's own vehicles
        if n.hasSuffix("@ash") { ash = true; n = n.dropLast(4) }
        if n.hasSuffix("@deep") { deep = true; n = n.dropLast(5) }       // a Brimstone Keep's monsters: Deep strength
        var grey = false, corsair = false, marauder = false
        if n.hasSuffix("@marauder") { marauder = true; n = n.dropLast(9) }   // P366 (b): a watchtower camp's gunmen
        if n.hasSuffix("@grey") { grey = true; n = n.dropLast(5) }
        // P504 (Nov 1 09:33, Remington: "Boreal station and frigate are their own troops"): a Boreal Station's garrison is
        // the Meridian Navy's (olive fatigues, gunmetal plate, amber visors; its heavies Aegis Marines in shield plate).
        var meridian = false
        if n.hasSuffix("@meridian") { meridian = true; n = n.dropLast(9) }
        if n.hasSuffix("@corsair") { corsair = true; n = n.dropLast(8) }   // T15: a corsair camp's crew (Pirates.swift)       // a Greywall Command base's troops (Greywall.swift)
        var tag = ""
        if let i = n.firstIndex(of: ":") { tag = String(n[n.index(after: i)...]); n = n[..<i] }
        guard let k0 = MobKind.named(String(n)) else { return nil }
        let m = Mob(Soldier.garrison(k0, at: p), at: p)
        m.persistent = true
        if ash { m.ashSetup() }
        if grey { m.greySetup() }
        if meridian { m.faction = Faction.meridian.rawValue }
        if corsair { Corsairs.dress(m) }
        if marauder { Marauders.dress(m); m.persistent = false; m.home = p }
        m.leash = leash
        if grey { m.greyTroop(tier: leash.flatMap { l in Greywall.Tier.allCases.first { $0.half == Int(l.z) } } ?? .outpost, at: p) }
        if deep { m.power = MobManager.depthPower(.deep, p.y) }
        if let h = heading { m.yaw = -h * .pi / 180; m.soldierBrain.turret = m.yaw }
        if tag == "fuel" { m.variant = 1 }
        if boreal { m.borealSetup() }
        if tag == "light" && k0 == .deckGun { m.variant = HeavyTurret.lightVariant }
        if k0 == .deckGun, let v = HeavyTurret.smallTags[tag] { m.variant = v }        // P222: the Capital's small guns
        if tag == "heavy" && grey { m.setTroop(.hannibal) }                           // P503: a garrison's watch-room heavy
        if tag == "heavy" && !grey && !ash { m.setTroop(.hannibal, rearm: false) }     // T7: a Capital fortress heavy     // T6: a light coastal gun
        if k0 == .minecart { CapitalRail.setupCar(m, tag: tag) }                // P92 trains
        if tag == "warden" { m.makeKeepWarden() }
        if tag == "operator" { m.makeGunOperator(at: p) }                          // P471: a gun room's operator
        if tag == "prisoner" || tag == "prisoner_sit" { Prisoners.setup(m, sitting: tag == "prisoner_sit") }   // P347
        if ash, let r = AshArmy.role(tag) { m.ashTakeRole(r) }
        if k0 == .villager && !tag.isEmpty { Townsfolk.setup(m, tag: tag, game: nil) }
        return m
    }

    // P460: one of a Boreal Station's own vehicles, in winter white with its blue band (ashVehicleParts), crewed by the
    // station's own (P504: the Meridian Navy's). Kept through a save by its faction field, the Capital's as the station's
    // vehicles always were (MobSave): that marks them Boreal.
    var boreal: Bool { kind.ashVehicle && faction == Faction.steelhold.rawValue }
    func borealSetup() {
        faction = Faction.steelhold.rawValue
        spec.name = kind == .ashTank ? "Boreal Tank" : (kind == .ashHalftrack ? "Boreal Half-track" : (variant == 1 ? "Boreal Fuel Truck" : "Boreal Truck"))
        persistent = true
    }

    var ashTurretY: Float {
        switch kind {
        case .ashTank: return 33.5 / 16
        case .ashBehemoth: return 46 / 16
        case .ashHalftrack: return 30 / 16
        default: return 14 / 16
        }
    }

    // Spotting: the player seen by any unit marks them for the guns (artillery) and wakes the units around.
    func ashSpotted(_ g: Game) {
        g.ashSpot = g.player.pos
        g.ashSpotSeen = g.clock
        guard g.clock - g.ashAlertClock > 1 else { return }
        g.ashAlertClock = g.clock
        for m in g.mobs.mobs where m !== self && m.health > 0 && m.faction == Faction.ashguard.rawValue
            && simd_length_squared(m.pos - pos) < 56 * 56 {
            let b = m.soldierBrain
            if !m.aggro { m.aggro = true; b.react = max(b.react, 0.5) }
            if b.seenAgo > 1 { b.lastSeen = g.player.eye; b.seenAgo = min(b.seenAgo, 2) }
            m.lockTime = max(m.lockTime, 20)
        }
    }

    func ashSoldierAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        let b = soldierBrain
        // AI LOD (the gap pass, D5): a calm soldier far from the player, with nowhere to go, thinks four times a second
        // and keeps walking the way it was meanwhile.
        if !aggro && dist > AshArmy.lodRange && b.order == nil && hurt <= 0 {
            b.lodAcc += dt
            if b.lodAcc < AshArmy.lodStep { AshArmy.lodSkipped += 1; return b.lodSpeed }
        } else if aggro && dist > AshArmy.fightLodRange && !b.sees && b.seenAgo > 1 && hurt <= 0 && b.role != AshArmy.mortar {
            // In a fight but out of sight and far: ten thoughts a second, still moving the way it was.
            b.lodAcc += dt
            if b.lodAcc < AshArmy.fightLodStep { AshArmy.lodSkipped += 1; return b.lodSpeed }
        }
        let step = max(dt, b.lodAcc)
        b.lodAcc = 0
        // Reinforcements run in to the last contact before they go to ground and fight (a squad that stopped to trade
        // shots at 50 blocks never arrived); a calm patrol walks its leg between two sites the same way. Both are
        // steered (Mob.update's path following) to a waypoint 16 blocks along the line: the path finder searches a
        // short reach, and a partial path to the far end made them give the run up at once. The last 20 blocks are
        // the ordinary order walk (a patrol turns at the end: ashRoleAI).
        let running = b.orderRun || (b.leg != nil && !aggro)
        if b.extra && running, let o = b.order {
            let flat = V2(o.x - pos.x, o.z - pos.z), d = simd_length(flat)
            let wp = pos + V3(flat.x / max(d, 0.01), 0, flat.y / max(d, 0.01)) * min(16, d)
            if d > 20 && !gaveUp(wp) && unreachableTimer <= 0 {
                face(wp)
                moving = true
                b.lodSpeed = spec.speed * (b.orderRun ? 0.95 : 0.6)
                return b.lodSpeed
            }
            if b.orderRun {
                b.orderRun = false; b.order = nil
                // Arrived (or no way round found): hunt from the last contact.
                if !aggro { aggro = true; b.lastSeen = o + V3(0, 1.6, 0); b.seenAgo = min(b.seenAgo, 5); lockTime = max(lockTime, 20) }
            } else if d > 20, let leg = b.leg {
                // A patrol with no way on: back the other way.
                b.order = simd_length(V2(o.x - leg.1.x, o.z - leg.1.z)) < 4 ? leg.0 : leg.1
                unreachableTimer = 0
            }
        }
        if let sp = ashRoleAI(step, g, dist: dist, canTarget: canTarget) { b.lodSpeed = sp; return sp }
        let sp = soldierAI(step, g, dist: dist, canTarget: canTarget)
        if canTarget, b.sees, b.seenAgo < 0.1 { ashSpotted(g); ashCallArmour(g) }
        b.lodSpeed = sp
        return sp
    }

    // MARK: The Marshal

    // An officer with an SMG and a heavy coat; at two thirds and one third of his health he calls his guard, and while
    // he can see the player he calls down marked barrages (a red flare 2 s before each shell lands: keep moving).
    func ashMarshalAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        let b = soldierBrain
        if b.clock == 0 {
            // Reloaded mid-fight: the guard calls already made follow from his health.
            let f = Float(health) / Float(spec.health)
            b.ashCalls = f < 0.34 ? 2 : (f < 0.67 ? 1 : 0)
        }
        let sp = soldierAI(dt, g, dist: dist, canTarget: canTarget)
        guard canTarget, aggro, health > 0 else { return sp }
        if b.sees && b.seenAgo < 0.1 { ashSpotted(g) }
        let frac = Float(health) / Float(spec.health)
        if (b.ashCalls == 0 && frac < 0.67) || (b.ashCalls == 1 && frac < 0.34) {
            b.ashCalls += 1
            ashCallGuard(g)
        }
        b.ashTimer -= dt
        if b.sees && b.ashTimer <= 0 && dist > 5 {
            b.ashTimer = g.difficulty >= 3 ? 9 : 12
            g.ashMarkBarrage("The Ash Marshal marks your position: move!", from: self, by: spec.name)
        }
        return sp
    }

    // Four of his guard run in through the bunker door (a toast and the alarm).
    func ashCallGuard(_ g: Game) {
        let ranks: [MobKind] = [.soldierTrooper, .soldierIronclad, .soldierTrooper, .soldierMarksman]
        let w = g.world
        for (i, k) in ranks.enumerated() {
            // Out of a side door: an open spot a few blocks from him (on the floor, two blocks of air).
            var p = pos
            for r in [3, 4, 5, 2] {
                let a = Float(i) * .pi / 2 + Float(r)
                let x = Int(floor(pos.x + cosf(a) * Float(r))), z = Int(floor(pos.z + sinf(a) * Float(r))), y = Int(floor(pos.y))
                if !w.solidAt(x, y, z) && w.builtBlock(x, y, z) == AIR && !w.solidAt(x, y + 1, z) && w.builtBlock(x, y + 1, z) == AIR && w.solidAt(x, y - 1, z) {
                    p = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
                    break
                }
            }
            let m = Mob(k, at: p)
            m.ashSetup()
            m.persistent = true
            m.aggro = true
            m.soldierBrain.lastSeen = g.player.eye
            m.soldierBrain.seenAgo = 0
            m.lockTime = 30
            g.mobs.mobs.append(m)
        }
        g.sfx(.gun(10), 1.6, at: pos)
        g.onToast?("\(spec.name) calls his guard")
    }

    // MARK: Vehicles

    func ashVehicleAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        let b = soldierBrain
        faceGoal = nil
        strafe = 0
        AshArmour.shedEffects(g)                                   // (P449: plates that came off, any hull's)
        b.reload -= dt
        b.shotTimer -= dt
        b.kick = max(0, b.kick - dt * 2.5)
        // Burning wrecks-to-be: smoke under 40% health.
        if health * 5 < spec.health * 2 && Rand.float(in: 0..<1) < dt * 5 { g.particles.smoke(at: pos + V3(0, height * 0.8, 0)) }
        // P344: his (taken, or left empty by its crew): driven from his seat, else parked with no crew to move it.
        if AshSeat.shared.vehicle === self { return ashSeatDrive(dt, g, AshSeat.shared) }
        if tamed { aggro = false; return 0 }
        if g.ashVehicleLife(self, dist: dist) { return 0 }                          // knocked out: empty, his to take (P324)
        // P324: half of them patrol a loop round where they stood while calm (a leg given up after 40 s).
        b.patrolT += dt
        if !aggro && (b.order == nil || b.patrolT > 40), dist < 90, let p = g.ashPatrolPoint(self) { b.order = p; b.patrolT = 0 }
        if kind == .ashTruck {
            guard let o = b.order, !aggro else { return 0 }
            let flat = simd_length(V2(o.x - pos.x, o.z - pos.z))
            if flat < 8 { b.order = nil; return 0 }
            return ashDrive(dt, g, wantYaw: atan2f(-(o.x - pos.x), -(o.z - pos.z)), flat: flat, near: 0, far: 6, circle: false)
        }
        if !canTarget {
            // Stood down (victory) or no target: guns home, engines idle.
            aggro = aggro && g.alive && !g.ashVictory
            b.sees = false
            ashSlew(dt, toYaw: yaw, pitch: 0)
            if !aggro { return 0 }
        } else if !aggro && dist > 90 {
            return 0                                              // a quiet unit far off costs nothing
        }
        let pivot = pos + V3(0, ashTurretY, 0)
        let sight: Float = kind == .ashArtillery ? 48 : (kind == .ashTank || kind == .ashBehemoth ? 72 : 56)
        b.losTimer -= dt
        if b.losTimer <= 0 {
            b.losTimer = 0.35 + Rand.float(in: 0..<0.1)
            b.sees = canTarget && dist < sight && g.world.canSee(pivot + V3(0, 0.7, 0), g.player.eye)
        }
        if b.sees {
            if !aggro { aggro = true; g.sfx(.gun(10), 1.1, at: pivot) }
            b.lastSeen = g.player.eye - V3(0, 0.5, 0)
            b.seenAgo = 0
            if !boreal { ashSpotted(g) }                          // (the Ashguard's spotting net, not the Capital's)
        } else {
            b.seenAgo += dt
            // Stands down 45 s after the last sighting, its own or (a field gun firing on reports) any unit's.
            if aggro && b.seenAgo > 45 && (kind != .ashArtillery || g.clock - g.ashSpotSeen > 45) { aggro = false }
        }
        // Sent somewhere (a reinforcement column, an officer's call for armour: AshArmy.swift): drive there until the
        // player is in sight.
        if let o = b.order, kind != .ashArtillery {
            let flat = simd_length(V2(o.x - pos.x, o.z - pos.z))
            if b.sees || flat < 8 { b.order = nil }
            else {
                ashSlew(dt, toYaw: atan2f(-(o.x - pos.x), -(o.z - pos.z)), pitch: 0)
                return ashDrive(dt, g, wantYaw: atan2f(-(o.x - pos.x), -(o.z - pos.z)), flat: flat, near: 0, far: 6, circle: false)
            }
        }
        switch kind {
        case .ashArtillery: ashArtillery(dt, g, pivot); return 0
        case .ashHalftrack: return ashHalftrack(dt, g, pivot, dist)
        default: return ashTank(dt, g, pivot, dist)
        }
    }

    // P344: his at the controls. The stick sends the hull the way it is pushed, from his view (P461); the turret, the pintle gun or
    // the field gun lays on his view at its own traverse rate; the trigger fires the seat's gun.
    private func ashSeatDrive(_ dt: Float, _ g: Game, _ seat: AshSeat) -> Float {
        let b = soldierBrain
        aggro = false
        b.order = nil
        let view = g.player.yaw, up = g.player.pitch
        switch kind {
        case .ashTank:
            ashSlew(dt, toYaw: view, pitch: max(-0.14, min(0.35, up)))
            if seat.fireTap && b.reload <= 0 {
                b.reload = 4
                // P435 (Oct 24 15:49, the tank's cannon "does not do enough damage... nowhere near enough"): his main
                // gun's round was the crew's (power 1.3, the burst breaking nothing). Now a 75 mm round: a burst that
                // blows out walls (stone and brick a block or two deep), and against a vehicle it strikes, a hit
                // that holes its plate (Slug.antiTank: a Cinder Tank in two).
                ashCannon(g, power: AshSeat.tankPower, speed: 70, gravity: 9, len: 6.1, spread: 0.004, mine: true, antiTank: AshSeat.tankAntiTank)
                AshSeat.shots += 1
            } else if seat.fireHeld && b.reload > 0.4 && b.shotTimer <= 0 {
                let (m, d) = ashMuzzle(3.4)
                ashSeatBullet(g, from: m + V3(cosf(b.turret), 0, -sinf(b.turret)) * 0.35, dir: d)
                b.shotTimer = 0.11
            }
        case .ashHalftrack where seat.gunner:
            ashSlew(dt, toYaw: view, pitch: max(-0.4, min(0.6, up)))
            if seat.fireHeld && b.shotTimer <= 0 {
                let (m, d) = ashMuzzle(1.2)
                ashSeatBullet(g, from: m, dir: d)
                b.shotTimer = 0.1
            }
        case .ashArtillery:
            ashSlew(dt, toYaw: view, pitch: max(0, min(1.2, up)))
            if seat.fireTap && b.reload <= 0 {
                b.reload = 5
                ashCannon(g, power: AshSeat.gunPower, speed: AshSeat.gunSpeed, gravity: AshSeat.gunGravity, len: 3.9, spread: 0.006, mine: true, antiTank: AshSeat.gunAntiTank)
                AshSeat.shots += 1
            }
            return 0                                               // a field gun is laid, not driven
        default:
            ashSlew(dt, toYaw: yaw, pitch: 0)                      // the pintle gun rides fore and aft
        }
        let turn: Float = kind == .ashHalftrack ? 1.4 : (kind == .ashTruck ? 1.2 : 1.0)
        let sp = AshSeat.seatSpeed(kind)
        // P461 (Oct 25 16:47: "Controlling the tank is weird. It is very unintuitive"): the stick drove the hull's own
        // way (up: ahead along the hull wherever he looked; sideways: turn) while the turret followed his head, so
        // looking off to the side and pushing ahead went the hull's way, not his. Now the stick says where to go as it
        // does on foot: pushed any way, the hull turns toward that way (from where he looks) and drives off along it;
        // a tank pivots on its tracks when it is far round and slows into the turn, wheels steer while they roll; a way
        // more than about 125 degrees round the back reverses toward it instead of turning about.
        let stick = V2(seat.steer, seat.drive)
        let push = min(1, simd_length(stick))
        var drive: Float = 0, swing: Float = 0
        if push > 0.15 {
            let look = g.player.moveYaw ?? view
            var d = look - atan2f(stick.x, stick.y) - yaw
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            if abs(d) > 2.2 {
                d += d > 0 ? -.pi : .pi
                drive = -push
            } else {
                drive = push * (kind == .ashTank ? max(0, cosf(d)) : max(0.4, cosf(d)))
            }
            swing = d
        }
        AshSeat.lastDrive = drive
        let top = seat.sprint && drive > 0.3 ? sp.sprint : sp.cruise
        // (The throttle eases toward what the stick asks: a 40 tonne tank doesn't reach 36 km/h in a frame.)
        let want = drive >= 0 ? top * drive : sp.cruise * 0.5 * drive
        soldierBrain.seatSpeed += max(-9 * dt, min((kind == .ashTank ? 3.2 : 5) * dt, want - soldierBrain.seatSpeed))
        let speed = soldierBrain.seatSpeed
        // Turning toward the way asked: a tank pivots on its tracks; wheels need the hull rolling.
        let roll: Float = kind == .ashTank ? 1 : min(1, abs(speed) / 2)
        let step = turn * roll * dt
        yaw += max(-step, min(step, swing))
        walkPhase += speed * dt
        return speed
    }

    private func ashSeatBullet(_ g: Game, from: V3, dir: V3) {
        g.arms.spawn(Slug(pos: from, vel: Guns.scatter(dir, 0.012) * 150, kind: .bullet, damage: 5, fromPlayer: true,
                          shooter: ObjectIdentifier(self), by: "Player", life: 0.6, gravity: 1.5))
        g.sfx(.gun(Guns.rifle), 0.9, at: from)
    }

    // Turret / gun laying toward a world yaw and pitch at the unit's traverse rates.
    private func ashSlew(_ dt: Float, toYaw want: Float, pitch: Float) {
        let b = soldierBrain
        let rate: Float = kind == .ashHalftrack ? 2.6 : (kind == .ashArtillery ? 0.6 : (kind == .ashBehemoth ? 0.5 : 0.9))
        var d = want - b.turret
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        b.turret += max(-rate * dt, min(rate * dt, d))
        b.pitch += max(-0.6 * dt, min(0.6 * dt, pitch - b.pitch))
        if kind == .ashArtillery { yaw = b.turret }               // a field gun turns on its trails
    }

    private func ashTurretOff(_ want: Float) -> Float {
        var d = want - soldierBrain.turret
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return abs(d)
    }

    // Low-arc (direct) or high-arc (indirect) launch pitch for speed v under gravity gr.
    private func ashPitch(_ from: V3, _ to: V3, v: Float, gr: Float, high: Bool) -> Float? {
        let dx = simd_length(V2(to.x - from.x, to.z - from.z)), dy = to.y - from.y
        let v2 = v * v
        let disc = v2 * v2 - gr * (gr * dx * dx + 2 * dy * v2)
        guard disc >= 0, dx > 0.5 else { return nil }
        let r = sqrtf(disc)
        return atanf((high ? v2 + r : v2 - r) / (gr * dx))
    }

    private func ashMuzzle(_ len: Float) -> (V3, V3) {
        let b = soldierBrain
        let fwd = V3(-sinf(b.turret) * cosf(b.pitch), sinf(b.pitch), -cosf(b.turret) * cosf(b.pitch))
        let centre = pos + V3(0, ashTurretY, 0) + V3(-sinf(yaw), 0, -cosf(yaw)) * (kind == .ashTank ? 2.0 / 16 : 0)
        return (centre + fwd * len, fwd)
    }

    private func ashBullet(_ g: Game, from: V3, at t: V3, spread: Float) {
        let d = Guns.scatter(simd_normalize(t - from), spread)
        let dmg: Float = 1.5 * Soldier.difficultyScale(g.difficulty) + 0.5
        g.arms.spawn(Slug(pos: from, vel: d * 150, kind: .bullet, damage: dmg, fromPlayer: false, shooter: ObjectIdentifier(self),
                          by: spec.name, life: 0.6, gravity: 1.5))
        g.sfx(.gun(Guns.rifle), 0.9, at: from)
    }

    private func ashCannon(_ g: Game, power: Float, speed v: Float, gravity gr: Float, len: Float, spread: Float, mine: Bool = false,
                           antiTank: Float = 0) {
        let (muzzle, fwd) = ashMuzzle(len)
        var s = Slug(pos: muzzle, vel: Guns.scatter(fwd, spread) * v, kind: .shell, damage: 0, fromPlayer: mine,
                     shooter: ObjectIdentifier(self), by: mine ? "Player" : spec.name, life: 6, gravity: gr)
        s.power = power
        s.breaks = mine                      // P435: his shells break what they burst against (the crews' still don't)
        s.antiTank = antiTank
        g.arms.spawn(s)
        for _ in 0..<4 { g.particles.smoke(at: muzzle + fwd * Rand.float(in: 0...1), dark: false) }
        g.addFlash(at: muzzle + fwd * 0.4, color: V3(6, 3.5, 1.6), radius: 7, life: 0.08)
        g.sfx(kind == .ashTank ? .tankCannon : .gun(9), kind == .ashBehemoth ? 1.5 : (kind == .ashTank ? 1.3 : 1.1), at: muzzle)
        soldierBrain.kick = 1
    }

    // Cinder tank: closes to 12-26 blocks, turret on the target, main gun every few seconds, a coaxial MG in bursts.
    private func ashTank(_ dt: Float, _ g: Game, _ pivot: V3, _ dist: Float) -> Float {
        let b = soldierBrain
        guard aggro, let t = b.lastSeen, b.seenAgo < 10 else { return 0 }
        let toT = t - pivot
        let flat = simd_length(V2(toT.x, toT.z))
        let wantYaw = atan2f(-toT.x, -toT.z)
        let big = kind == .ashBehemoth
        let v: Float = big ? 76 : 70, gr: Float = 9
        let pitch = max(-0.14, min(0.35, ashPitch(pivot, t, v: v, gr: gr, high: false) ?? 0.1))
        ashSlew(dt, toYaw: wantYaw, pitch: pitch)
        let off = ashTurretOff(wantYaw)
        // Laid on: a 0.6 s tell (the breech clank and a glow at the muzzle) before the main gun fires.
        if b.sees && off < 0.05 && abs(pitch - b.pitch) < 0.04 && b.reload <= 0 && flat > 5 {
            if b.charge == 0 { g.sfx(.gun(12), 1, at: pivot) }
            b.charge += dt
            if b.charge >= (big ? 0.9 : 0.6) {
                b.charge = 0
                b.reload = (big ? [13, 12, 10, 8] : [10, 9, 7.5, 5.5])[max(0, min(3, g.difficulty))]
                ashCannon(g, power: big ? 1.9 : 1.3, speed: v, gravity: gr, len: big ? 7.6 : 6.1, spread: 0.02)
                if big { b.ashTimer = 1.6 }                     // the coaxial gun follows
            }
        } else if b.charge > 0 && (!b.sees || off > 0.2) {
            b.charge = 0
        }
        if big && b.ashTimer > 0 {
            b.ashTimer -= dt
            if b.ashTimer <= 0 && b.sees { ashCannon(g, power: 1.0, speed: v, gravity: gr, len: 4.6, spread: 0.03) }
        }
        ashMG(dt, g, t, dist: flat, off: off, len: big ? 4.4 : 3.4, range: 44)
        return ashDrive(dt, g, wantYaw: wantYaw, flat: flat, near: big ? 14 : 12, far: big ? 30 : 26, circle: false)
    }

    // Half-track: fast, circles at 12-24 blocks, a pintle MG that swings all round.
    private func ashHalftrack(_ dt: Float, _ g: Game, _ pivot: V3, _ dist: Float) -> Float {
        let b = soldierBrain
        guard aggro, let t = b.lastSeen, b.seenAgo < 10 else { return 0 }
        let toT = t - pivot
        let flat = simd_length(V2(toT.x, toT.z))
        let wantYaw = atan2f(-toT.x, -toT.z)
        let pitch = atan2f(toT.y, max(1, flat))
        ashSlew(dt, toYaw: wantYaw, pitch: max(-0.4, min(0.6, pitch)))
        ashMG(dt, g, t, dist: flat, off: ashTurretOff(wantYaw), len: 1.2, range: 50)
        ashSalvo(dt, g, t, flat: flat)
        return ashDrive(dt, g, wantYaw: wantYaw, flat: flat, near: 12, far: 24, circle: true)
    }

    // P324: the half-track's rocket rack: four rockets a salvo, from 14 blocks out, about every 9 s.
    private func ashSalvo(_ dt: Float, _ g: Game, _ t: V3, flat: Float) {
        let b = soldierBrain
        b.salvoCD -= dt
        if b.salvoLeft == 0 {
            guard b.sees, flat > 14, flat < 60, b.salvoCD <= 0 else { return }
            b.salvoLeft = AshCommandeer.salvo
            b.salvoCD = 0
        }
        guard b.salvoCD <= 0 else { return }
        let back = V3(sinf(yaw), 0, cosf(yaw))
        let side = V3(cosf(yaw), 0, -sinf(yaw)) * (b.salvoLeft % 2 == 0 ? 0.5 : -0.5)
        let from = pos + V3(0, height + 0.3, 0) + back * (halfW * 0.6) + side
        let aim = t + V3(0, flat * 0.012, 0)
        let dir = Guns.scatter(simd_normalize(aim - from), 0.045)
        let speed: Float = 42
        var s = Slug(pos: from + dir * 0.6, vel: dir * speed, kind: .rocket, damage: 0, fromPlayer: false,
                     shooter: ObjectIdentifier(self), by: spec.name, life: 70 / speed, gravity: 0.6)
        s.power = 1.5
        g.arms.spawn(s)
        g.particles.smoke(at: from, dark: false)
        g.sfx(.gun(4), 0.9, at: from)
        b.salvoLeft -= 1
        b.salvoCD = b.salvoLeft > 0 ? 0.28 : Rand.float(in: AshCommandeer.salvoEvery)
        if b.salvoLeft == 0 { AshCommandeer.salvos += 1 }
    }

    private func ashMG(_ dt: Float, _ g: Game, _ t: V3, dist: Float, off: Float, len: Float, range: Float) {
        let b = soldierBrain
        guard b.sees, dist < range, off < 0.2 else { b.burst = 0; return }
        if b.burst == 0 {
            guard b.shotTimer <= 0 else { return }
            b.burst = kind == .ashHalftrack ? 10 : 7
        }
        if b.shotTimer <= 0 {
            let (muzzle, _) = ashMuzzle(len)
            ashBullet(g, from: kind == .ashTank ? muzzle + V3(cosf(b.turret), 0, -sinf(b.turret)) * 0.35 : muzzle, at: t,
                      spread: 0.035 + dist * 0.0008)
            b.burst -= 1
            b.shotTimer = b.burst > 0 ? 0.11 : Rand.float(in: 2.0...3.2)
        }
    }

    // Hull driving: turn toward the goal, drive to the band, back off when close; half-tracks circle inside it. Stops
    // short of drops and lava.
    // P449 (Oct 25 09:03, a Cinder Tank: "make it so it can drive through shit"): a moving hull breaks what stands in
    // front of it, from a hand over the ground to its roof: a tank (and the Behemoth) shoves through trees (the trunk
    // snapped at the hull, the tree above falling: Felling), fences, timber walls, glass, leaves and brush; a half-track
    // or a truck through leaves, brush, glass and panes. The ground, stone and brick stop it as before. What it breaks
    // is gone (nothing to pick up: P452), a few cells a frame. Returns the speed it was given.
    // Both, for a hull on the move (Animals.swift, every vehicle, his or the army's).
    func ashRolls(_ g: Game, _ speed: Float, _ dt: Float) -> Float {
        ashTracks(g, speed)
        // P464 (Oct 25 19:34, the truck: "this thing should probably have wheels on, right? It's as if I'm running"):
        // the wheels turn with the ground it covers (radius 6/16 block); his run down whoever stands in the way.
        wheelRoll = (wheelRoll + speed * dt / 0.375).truncatingRemainder(dividingBy: 2 * .pi)
        if AshSeat.shared.vehicle === self { g.ashRunOver(self, speed) }
        return ashPlough(g, speed)
    }

    // P449 (Oct 25 09:02, the Ash Vault: the tank should leave "tracks behind it where it drove"): a tracked hull (the
    // Cinder Tank, the Behemoth, a half-track's rear tracks) churns the ground under its two tracks: grass, snowy grass,
    // podzol, mycelium and dirt turn to coarse dirt, and the snow, grass and flowers on them are crushed flat, two dark
    // lines behind it wherever it went.
    private static let churn: [Bool] = (0..<Blocks.count).map {
        ["grass_block", "snowy_grass_block", "podzol", "mycelium", "dirt", "rooted_dirt"].contains(Blocks.key(BlockID($0)))
    }
    func ashTracks(_ g: Game, _ speed: Float) {
        guard abs(speed) > 0.3, kind == .ashTank || kind == .ashHalftrack || kind == .ashBehemoth, onGround,
              Blocks.has("coarse_dirt") else { return }
        let w = g.world
        let coarse = Blocks.id("coarse_dirt")
        let side = V3(-forward.z, 0, forward.x)
        let gauge: Float = kind == .ashBehemoth ? 1.8 : (kind == .ashTank ? 1.15 : 0.85)
        let back: Float = kind == .ashHalftrack ? 1.4 : 0                         // (a half-track's tracks are aft)
        for s: Float in [-1, 1] { for along: Float in [-1, 0, 1] {
            let q = pos + side * (s * gauge) - forward * (back + along * 0.9)
            let x = Int(floor(q.x)), z = Int(floor(q.z))
            var y = Int(floor(pos.y + 0.2))
            if !w.solidAt(x, y - 1, z) && w.solidAt(x, y - 2, z) { y -= 1 }
            let under = w.materialAt(x, y - 1, z)                                  // (a field world's ground too)
            if Mob.churn[Int(under)] { _ = w.setBlockAsync(x, y - 1, z, coarse); AshSeat.tracked += 1 }
            let on = w.builtBlock(x, y, z)
            if on != AIR && !Blocks.collide[Int(on)] && !Blocks.isLiquid(on) && w.blockEntities[IVec3(x, y, z)] == nil { _ = w.setBlockAsync(x, y, z, AIR) }
        } }
    }

    func ashPlough(_ g: Game, _ speed: Float) -> Float {
        guard abs(speed) > 0.8, kind != .ashArtillery else { return speed }
        let w = g.world
        let tank = kind == .ashTank || kind == .ashBehemoth
        let dir = forward * (speed > 0 ? 1 : -1), side = V3(-dir.z, 0, dir.x)
        // The hull's half length (the models run longer than the hit box is wide).
        let reach: Float = (kind == .ashBehemoth ? 4.4 : (tank ? 3.4 : 3.0)) + 0.4
        let y0 = Int(floor(pos.y + 0.4)), y1 = Int(floor(pos.y + spec.height))
        var gone = 0
        var o: Float = -halfW
        while o <= halfW + 0.01 && gone < 6 {
            let q = pos + dir * reach + side * o
            let x = Int(floor(q.x)), z = Int(floor(q.z))
            for y in y0...max(y0, y1) where gone < 6 {
                let b = w.block(x, y, z)
                guard b != AIR, !Blocks.isLiquid(b), w.blockEntities[IVec3(x, y, z)] == nil else { continue }
                let hard = Blocks.hardness[Int(b)]
                guard hard >= 0, !SmoothTerrain.natural[Int(b)] || CapitalBase.isLog(b) || CapitalBase.isLeaf(b) else { continue }
                let wood = Blocks.tool[Int(b)] == ToolType.axe.rawValue && hard <= 3
                guard hard <= 0.6 || CapitalBase.isLeaf(b) || (tank && wood) else { continue }
                let p = IVec3(x, y, z)
                g.particles.blockBreak(b, at: p)
                if gone == 0 { g.blockSound(g.audioBreakSound(b), at: p) }
                _ = w.setBlockAsync(x, y, z, AIR)
                g.debris.blockChanged(p)
                if CapitalBase.isLog(b) { g.fellCheck(p, b) }
                gone += 1
                AshSeat.ploughed += 1
            }
            o += 0.5
        }
        return speed
    }

    private func ashDrive(_ dt: Float, _ g: Game, wantYaw: Float, flat: Float, near: Float, far: Float, circle: Bool) -> Float {
        var goal = wantYaw
        var speed: Float = 0
        if flat > far { speed = spec.speed }
        else if flat < near { speed = -spec.speed * 0.6 }
        else if circle { goal = wantYaw + .pi / 2 * (soldierBrain.strafeDir); speed = spec.speed * 0.7 }
        var d = goal - yaw
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        let turn: Float = kind == .ashHalftrack ? 1.4 : (kind == .ashBehemoth ? 0.35 : 0.7)
        yaw += max(-turn * dt, min(turn * dt, d))
        if abs(d) > 0.6 { speed *= 0.3 }
        if speed != 0 {
            let w = g.world
            let ahead = pos + forward * ((halfW + 1) * (speed > 0 ? 1 : -1))
            let x = Int(floor(ahead.x)), z = Int(floor(ahead.z)), y = Int(floor(pos.y))
            let floorBlk = w.builtBlock(x, y - 1, z)
            let drop = !w.solidAt(x, y - 1, z) && !w.solidAt(x, y - 2, z)
            if drop || Blocks.isLiquid(floorBlk) || Blocks.isLiquid(w.builtBlock(x, y, z)) {
                speed = 0
                if circle { soldierBrain.strafeDir = -soldierBrain.strafeDir }
            }
        }
        if circle && Rand.float(in: 0..<1) < dt * 0.15 { soldierBrain.strafeDir = -soldierBrain.strafeDir }
        walkPhase += speed * dt
        return speed
    }

    // Field gun: high-arc fire at whatever the Ashguard has spotted (its own sight, or another unit's report), 20-170
    // blocks off. Helpless up close.
    private func ashArtillery(_ dt: Float, _ g: Game, _ pivot: V3) {
        let b = soldierBrain
        var target: V3?
        if b.sees { target = b.lastSeen }
        else if aggro, let s = g.ashSpot, g.clock - g.ashSpotSeen < 6 { target = s }
        guard let t0 = target else { b.charge = 0; return }
        let v: Float = 46, gr: Float = 12
        let flat0 = simd_length(V2(t0.x - pivot.x, t0.z - pivot.z))
        guard flat0 > 20 && flat0 < 170 else { b.charge = 0; return }
        let t = t0 + V3(g.player.vel.x, 0, g.player.vel.z) * (flat0 / v) * 0.5
        // High arc (over walls and pillars); close in, where that would be near vertical, the flat one.
        guard let hi = ashPitch(pivot, t, v: v, gr: gr, high: true), let lo = ashPitch(pivot, t, v: v, gr: gr, high: false) else { return }
        // The flat shot only when it still gives a fair warning (a 40-block flat shot lands in under a second).
        let loFlight = flat0 / max(1, v * cosf(lo))
        let pitch = hi > 1.25 && loFlight >= AshArmy.minWarning + 0.1 ? lo : hi
        let toT = t - pivot
        let wantYaw = atan2f(-toT.x, -toT.z)
        ashSlew(dt, toYaw: wantYaw, pitch: pitch)
        // Every shell is fair (the gap pass, DE10): one that would land in under 1.6 s is never fired, and each one
        // fired marks where it will land (red smoke, then a whistle 1.5 s out: AshArmy.swift).
        let flight = flat0 / max(1, v * cosf(pitch))
        if ashTurretOff(wantYaw) < 0.03 && abs(pitch - b.pitch) < 0.03 && b.reload <= 0 && flight >= AshArmy.minWarning + 0.1 {
            b.charge += dt
            if b.charge > 0.7 {
                b.charge = 0
                b.reload = g.difficulty >= 3 ? 6 : 8
                ashCannon(g, power: 1.5, speed: v, gravity: gr, len: 3.9, spread: 0.012)
                g.ashStrikes.append(AshStrike(at: t, t: flight, power: 0, from: ObjectIdentifier(self), by: spec.name, shell: false))
            }
        }
    }
}

// MARK: Models (1/16 block, origin at the feet, facing -Z; hull yaw is the mob's, turrets turn by brain.turret)

func ashVehicleParts(_ m: Mob) -> [Part] {
    // P460: a Boreal Station's vehicles in the Capital's winter colours: white and pale grey, a blue band, white lamps.
    let snow = m.boreal
    let black = snow ? V3(0.62, 0.64, 0.66) : V3(0.075, 0.075, 0.082), plate = snow ? V3(0.5, 0.52, 0.54) : V3(0.11, 0.11, 0.12)
    let dark = snow ? V3(0.07, 0.075, 0.08) : V3(0.035, 0.035, 0.04)
    let red = snow ? V3(0.12, 0.26, 0.5) : V3(0.62, 0.06, 0.04), steel = V3(0.2, 0.2, 0.22)
    let glow = snow ? V3(1.9, 2.1, 2.6) : V3(2.6, 0.25, 0.12)
    let b = m.brain
    let ty = (b?.turret ?? m.yaw) - m.yaw
    let pitch = b?.pitch ?? 0
    let kick = (b?.kick ?? 0) * 5
    var p: [Part] = []
    // Level of detail while the mob pass draws (SoldierRig.eye, the soldiers' mid distance): past 34 blocks the small
    // parts (wheels, links, grilles, dischargers) go; the hull, turret, gun and markings stay. The citadel battle's
    // vehicles stay inside the mob vertex budget (questcheck's "ash vault draw").
    let fine: Bool = { guard SoldierRig.drawing, let e = SoldierRig.eye else { return true }; return simd_length_squared(m.pos - e) < 34 * 34 }()
    func turned(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, pivot: V3, gun: Bool = false, pat: Float = 7) {
        var q = box(x, y, z, w, h, d, c, pat)
        q.pivot = pivot
        q.rotY = ty
        if gun { q.rotX = pitch }
        p.append(q)
    }
    let ember = snow ? V3(0.78, 0.63, 0.29) : V3(0.85, 0.41, 0.12)   // P360 (b): the ember mark's orange (was a white disc); P460: the Capital's gold
    // The ember mark on a flank: an orange plate with the black bar.
    func mark(_ x: Float, _ y: Float, _ z: Float, side: Float, size: Float) {
        p.append(box(x - (side < 0 ? 0.4 : 0), y, z, 0.4, size, size, ember))
        p.append(box(x - (side < 0 ? 0.8 : -0.4), y + size * 0.15, z + size * 0.38, 0.4, size * 0.7, size * 0.24, dark))
    }
    func turnedMark(_ x: Float, _ y: Float, _ z: Float, side: Float, size: Float, pivot: V3) {
        turned(x - (side < 0 ? 0.4 : 0), y, z, 0.4, size, size, ember, pivot: pivot, pat: 0)
        turned(x - (side < 0 ? 0.8 : -0.4), y + size * 0.15, z + size * 0.38, 0.4, size * 0.7, size * 0.24, dark, pivot: pivot, pat: 0)
    }
    // P464: a road wheel (x0 its inner face, width wide, centre z) turning with the ground covered: an octagon of two
    // squares, a hub and a pale tread bar that shows it roll (the bar and hub only near).
    func wheel(_ x0: Float, _ z: Float, width: Float = 4) {
        let pv = V3(x0 + width / 2, 6, z), a = -m.wheelRoll
        for k in 0..<(fine ? 2 : 1) {
            var q = box(x0, 0, z - 6, width, 12, 12, dark, 4); q.pivot = pv; q.rotX = a + Float(k) * .pi / 4; p.append(q)
        }
        guard fine else { return }
        let out: Float = x0 < 0 ? x0 - 0.5 : x0 + width - 0.5
        var h = box(out, 3, z - 3, 1, 6, 6, steel, 8); h.pivot = pv; h.rotX = a; p.append(h)
        var t = box(out + (x0 < 0 ? -0.1 : 0.1), 0.4, z - 0.8, 1, 11.2, 1.6, V3(0.3, 0.29, 0.27), 4); t.pivot = pv; t.rotX = a; p.append(t)
    }
    // P344 (e): a crewed vehicle shows its crew (none once it is his).
    let coat = snow ? V3(0.7, 0.72, 0.74) : V3(0.17, 0.165, 0.15), skin = V3(0.72, 0.56, 0.46), helm = snow ? V3(0.82, 0.83, 0.84) : V3(0.1, 0.1, 0.105)
    switch m.kind {
    case .ashTank:
        // A heavy tank in the period's style: a slab hull with a near-vertical front plate, big interleaved road wheels,
        // a flat-sided superstructure over the tracks, a boxy turret with a long gun and a double-baffle muzzle brake.
        for s: Float in [-1, 1] {
            let xo: Float = s < 0 ? -27 : 17
            p.append(box(xo, 0, -42, 10, 13, 84, dark, 4))                                    // track
            for k in 0..<8 where fine {                                                        // interleaved road wheels
                let outer = k % 2 == 0
                let x: Float = s < 0 ? (outer ? -28.0 : -27.5) : (outer ? 27.0 : 26.9)
                p.append(box(x, 1.5, Float(k) * 9.5 - 40, outer ? 1.0 : 0.6, 11, 11, steel * (outer ? 1 : 0.8), 8))
                if outer { p.append(box(s < 0 ? -28.4 : 27.9, 6, Float(k) * 9.5 - 35.6, 0.5, 2.2, 2.2, dark)) }
            }
            p.append(box(s < 0 ? -28 : 18, 4, -46, 10, 10, 6, steel, 8))                      // drive sprocket
            p.append(box(s < 0 ? -21 : 18, 20, 40.6, 3, 2, 0.6, glow, 9))                     // tail lights
            mark(s < 0 ? -28.4 : 28.4, 19.5, 6, side: s, size: 8)
        }
        p.append(box(-17, 6, -42, 34, 12, 84, black, 7))                                       // lower hull
        p.append(box(-28, 18, -36, 56, 10, 74, plate, 7))                                      // superstructure over the tracks
        p.append(box(-28, 10, -44, 56, 18, 8, plate, 7))                                       // near-vertical front plate
        if fine {
            p.append(box(-24, 12, -44.8, 48, 5, 0.8, dark, 4))                                 // spare track links
            for k in 0..<8 { p.append(box(-23 + Float(k) * 6, 12, -45.2, 0.6, 5, 0.4, steel)) }
            p.append(box(-21, 22, -44.6, 9, 2, 0.6, V3(0.03, 0.03, 0.03)))                     // driver's visor
            p.append(box(8, 20.5, -44.8, 5, 5, 1, steel, 8))                                   // hull MG ball
            p.append(box(9.8, 22.3, -48.6, 1.4, 1.4, 4, dark, 8))
            for x: Float in [-16, -6, 4] { p.append(box(x, 28, 22, 8, 0.6, 12, dark)) }       // engine deck grilles
        }
        p.append(box(-28.4, 25, -30, 56.8, 2, 20, red))                                        // red band on both flanks
        for x: Float in [-15, 11] {                                                            // exhaust stacks with guards
            p.append(box(x, 14, 38, 4, 13, 4, steel, 8))
            if fine { p.append(box(x + 0.5, 27, 38.5, 3, 0.6, 3, V3(0.02, 0.02, 0.02))) }
        }
        let pv = V3(0, 33.5, -2)
        turned(-19, 28, -20, 38, 14, 34, black, pivot: pv)                                     // boxy turret
        turned(-18, 42, -18, 36, 0.8, 30, plate, pivot: pv)                                    // roof
        turned(-15, 30, 14, 30, 9, 8, plate, pivot: pv)                                        // stowage bin
        turned(-19.4, 37, -14, 38.8, 2, 20, red, pivot: pv, pat: 0)                            // turret band
        turned(-14, 42.8, 2, 9, 4, 9, plate, pivot: pv)                                        // commander's cupola
        if !m.tamed {                                                                          // the commander, head out
            turned(-12, 46.8, 4.5, 5, 4, 4, coat, pivot: pv, pat: 0)
            turned(-11.5, 50.8, 4.5, 4, 4, 4, skin, pivot: pv, pat: 0)
            turned(-12, 53.6, 4, 5, 1.6, 5, helm, pivot: pv, pat: 0)
        }
        if fine {
            turnedMark(-19.4, 30, -6, side: -1, size: 6, pivot: pv); turnedMark(19.4, 30, -6, side: 1, size: 6, pivot: pv)
            turned(-13, 46.8, 3, 7, 0.8, 7, dark, pivot: pv)
            for s: Float in [-1, 1] { turned(s < 0 ? -21 : 19, 36, -16, 2, 2, 2.5, steel, pivot: pv, pat: 8) }   // smoke dischargers
            turned(12, 42, 10, 0.6, 22, 0.6, steel, pivot: pv)                                 // antenna
        }
        turned(-10, 29, -25, 20, 11, 5, plate, pivot: pv, gun: true)                           // mantlet
        turned(-1.6, 32.9, -96 + kick, 3.2, 3.2, 72, steel, pivot: pv, gun: true, pat: 8)      // long gun
        turned(-3, 31.5, -100.4 + kick, 6, 6, 2.0, dark, pivot: pv, gun: true, pat: 8)         // double-baffle muzzle brake
        if fine {
            turned(-3, 31.5, -97.2 + kick, 6, 6, 1.4, dark, pivot: pv, gun: true, pat: 8)
            turned(5, 31, -28, 1.5, 1.5, 4, dark, pivot: pv, gun: true)                        // coaxial MG
        }
        if let c = b?.charge, c > 0 { turned(-1.2, 33.3, -100.8, 2.4, 2.4, 0.5, V3(1.5 + c * 3, 0.5, 0.15), pivot: pv, gun: true, pat: 9) }
    case .ashBehemoth:
        // The Behemoth: a super-heavy tank twice the Cinder's mass, skirted tracks, a huge rounded turret with a main gun
        // and a shorter coaxial gun.
        for s: Float in [-1, 1] {
            p.append(box(s < 0 ? -38 : 26, 0, -58, 12, 16, 116, dark, 4))                    // tracks
            p.append(box(s < 0 ? -39.5 : 37.5, 4, -56, 2, 13, 112, plate, 7))                  // side skirts
            for k in 0..<9 { p.append(box(s < 0 ? -40 : 39.5, 6, Float(k) * 12.5 - 52, 0.5, 6, 0.8, steel)) }
            p.append(box(s < 0 ? -40 : 39.5, 18, -40, 0.5, 2.5, 80, red))
            mark(s < 0 ? -40 : 40, 7, 10, side: s, size: 9)
            p.append(box(s < 0 ? -30 : 26, 26, 56.6, 4, 2.5, 0.6, glow, 9))
        }
        p.append(box(-26, 10, -56, 52, 20, 112, black, 7))                                     // hull
        p.append(box(-38, 16, -62, 76, 12, 8, plate, 7))                                       // stepped front
        p.append(box(-38, 28, -58, 76, 6, 6, plate, 7))
        p.append(box(-38, 29, -52, 76, 8, 104, plate, 7))                                      // superstructure
        p.append(box(-14, 30, -62.6, 10, 2.5, 0.6, V3(0.03, 0.03, 0.03)))                      // driver's visor
        for x: Float in [-24, -12, 0, 12] { p.append(box(x, 37, 26, 10, 0.6, 18, dark)) }      // engine deck
        for x: Float in [-20, 16] { p.append(box(x, 30, 50, 5, 14, 5, steel, 8)) }
        let pv = V3(0, 46, 0)
        turned(-24, 37, -30, 48, 18, 50, black, pivot: pv)                                     // turret
        turned(-22, 55, -26, 44, 1, 42, plate, pivot: pv)
        turned(-24.4, 48, -20, 48.8, 2.5, 30, red, pivot: pv, pat: 0)
        turnedMark(-24.4, 39, -2, side: -1, size: 8, pivot: pv); turnedMark(24.4, 39, -2, side: 1, size: 8, pivot: pv)
        turned(-16, 55, 4, 10, 5, 10, plate, pivot: pv)                                        // cupola
        turned(14, 55, 14, 0.7, 26, 0.7, steel, pivot: pv)
        turned(-13, 39, -36, 26, 15, 6, plate, pivot: pv, gun: true)                           // mantlet
        turned(-2.4, 44, -122 + kick, 4.8, 4.8, 86, steel, pivot: pv, gun: true, pat: 8)       // main gun
        turned(-3.4, 43, -124 + kick, 6.8, 6.8, 3, dark, pivot: pv, gun: true, pat: 8)         // muzzle ring
        turned(6, 41.5, -74 + kick * 0.5, 2.6, 2.6, 38, steel, pivot: pv, gun: true, pat: 8)   // coaxial gun
        if let c = b?.charge, c > 0 { turned(-1.6, 44.8, -124.6, 3.2, 3.2, 0.5, V3(1.5 + c * 3, 0.5, 0.15), pivot: pv, gun: true, pat: 9) }
    case .ashHalftrack:
        // An armoured half-track: wheels at the front, tracks behind, an angular hull with stepped plates, an open top
        // and a shielded machine gun.
        for s: Float in [-1, 1] {
            wheel(s < 0 ? -20 : 14, -34, width: 6)                                             // front wheels
            p.append(box(s < 0 ? -20 : 12, 0, -8, 8, 10, 42, dark, 4))                         // rear tracks
            for k in 0..<4 where fine { p.append(box(s < 0 ? -20.6 : 19.6, 1.5, Float(k) * 9.5 - 6, 1, 7, 7, steel * (k % 2 == 0 ? 1 : 0.8), 8)) }
            p.append(box(s < 0 ? -21 : 15, 12, -42, 6, 1.5, 16, black, 7))                    // fenders
            // Stepped side plates: lower, then a narrower upper course leaning in.
            p.append(box(s < 0 ? -17 : 13, 10, -26, 4, 7, 62, black, 7))
            p.append(box(s < 0 ? -16 : 13, 17, -26, 3, 8, 62, plate, 7))
            p.append(box(s < 0 ? -16.4 : 16, 21, -20, 0.4, 2, 40, red))
            mark(s < 0 ? -16.4 : 16.4, 18, 14, side: s, size: 5)
        }
        p.append(box(-12, 8, -46, 24, 6, 20, black, 7))                                       // engine nose, stepped
        p.append(box(-11, 14, -44, 22, 3, 18, plate, 7))
        p.append(box(-10, 17, -38, 20, 3, 12, plate, 7))
        if fine { p.append(box(-9, 9, -46.8, 18, 5, 1, dark)) }                                // radiator louvres
        p.append(box(-14, 17, -27, 28, 9, 2, plate, 7))                                        // cab front plate
        p.append(box(-11, 22, -27.6, 7, 1.2, 0.6, V3(0.03, 0.03, 0.03))); p.append(box(4, 22, -27.6, 7, 1.2, 0.6, V3(0.03, 0.03, 0.03)))
        p.append(box(-13, 10, -25, 26, 5, 60, dark))                                           // troop compartment floor
        if fine { p.append(box(-13, 15, -16, 3, 4, 46, plate)); p.append(box(10, 15, -16, 3, 4, 46, plate)) }   // bench seats
        p.append(box(-13, 10, 35, 26, 15, 2, plate, 7))                                        // rear doors
        if fine { p.append(box(-0.3, 12, 36.8, 0.6, 10, 0.6, dark)) }
        p.append(box(-12, 16, 37, 3, 2, 0.6, glow, 9)); p.append(box(9, 16, 37, 3, 2, 0.6, glow, 9))
        let pv = V3(0, 30, -12)
        turned(-1, 25, -13, 2, 6, 2, steel, pivot: pv, pat: 8)                                 // pintle
        if !m.tamed {                                                                          // driver and gunner
            p.append(box(-12, 17, -24, 6, 7, 4, coat)); p.append(box(-11.5, 24, -23.5, 5, 4.5, 4.5, skin))
            p.append(box(-12, 28, -24, 6, 1.6, 5.5, helm))
            turned(-3, 19, -8, 6, 8, 4, coat, pivot: pv, pat: 0); turned(-2.5, 27, -7.5, 5, 4.5, 4.5, skin, pivot: pv, pat: 0)
            turned(-3, 31, -8, 6, 1.6, 5.5, helm, pivot: pv, pat: 0)
        }
        turned(-7, 26, -15, 14, 9, 1, plate, pivot: pv)                                        // gun shield
        turned(-1.1, 28.6, -30, 2.2, 2.4, 16, dark, pivot: pv, gun: true, pat: 8)              // perforated jacket
        for z: Float in [-28.0, -24.5, -21.0] where fine { turned(-1.15, 29.2, z, 2.3, 0.6, 1.6, V3(0.02, 0.02, 0.02), pivot: pv, gun: true) }
        turned(-0.7, 28.8, -32, 1.4, 1.8, 2.2, steel, pivot: pv, gun: true, pat: 8)
        turned(-1.8, 26, -12, 3.6, 3, 2, steel, pivot: pv, gun: true, pat: 8)                  // receiver
    case .ashArtillery:
        // A heavy flak gun on a cross-shaped platform: four outriggers with levelling pads, a tall pedestal, a shield
        // and a long barrel with a muzzle brake and recoil cylinders.
        p.append(box(-28, 0, -2, 56, 3, 4, black, 7)); p.append(box(-2, 0, -28, 4, 3, 56, black, 7))
        for (x, z) in [(-30, -3), (26, -3), (-3, -30), (-3, 26)] as [(Float, Float)] { p.append(box(x, 0, z, 4, 1.2, 6, steel, 8)) }
        p.append(box(-6, 3, -6, 12, 6, 12, plate, 7))                                          // pedestal
        p.append(box(-9, 9, -7, 18, 5, 14, black, 7))                                          // upper carriage
        p.append(box(-9, 9, -7, 2, 10, 14, black, 7)); p.append(box(7, 9, -7, 2, 10, 14, black, 7))   // trunnion cheeks
        p.append(box(-17, 10, -13, 13, 15, 1.5, black, 7)); p.append(box(4, 10, -13, 13, 15, 1.5, black, 7))   // split shield
        p.append(box(-17, 22, -13.6, 34, 2, 0.6, red))
        p.append(box(-17.4, 13, -12, 0.4, 6, 6, ember)); p.append(box(-17.8, 14, -9.7, 0.4, 4, 1.4, dark))
        p.append(box(9, 3, 8, 8, 5, 6, plate, 7))                                              // ready rounds
        p.append(box(-14, 6, 6, 4, 1, 4, dark)); p.append(box(10, 6, -10, 4, 1, 4, dark))     // layers' seats
        let pv = V3(0, 14, -2)
        var q = box(-3, 11, -14, 6, 6, 26, plate, 7); q.pivot = pv; q.rotX = pitch; p.append(q)          // cradle
        q = box(-1.2, 15.8, -30, 2.4, 2, 20, steel, 8); q.pivot = pv; q.rotX = pitch; p.append(q)       // recoil cylinders
        q = box(-1.4, 12.6, -64 + kick, 2.8, 2.8, 52, steel, 8); q.pivot = pv; q.rotX = pitch; p.append(q)
        q = box(-2.3, 11.7, -67 + kick, 4.6, 4.6, 3, dark, 8); q.pivot = pv; q.rotX = pitch; p.append(q)  // muzzle brake
    default:
        // Supply truck (canvas tilt) or fuel truck (tank with red bands).
        for z: Float in [-36, 10, 24] { wheel(-17, z); wheel(13, z) }
        p.append(box(-12, 6, -42, 24, 4, 82, steel, 8))                                // chassis
        p.append(box(-12, 8, -50, 24, 11, 9, black, 7))                                // hood
        p.append(box(-14, 8, -42, 28, 18, 16, black, 7))                               // cab
        p.append(box(-12, 19, -42.6, 24, 5, 1, V3(0.08, 0.09, 0.1), 11))
        p.append(box(-9, 9, -50.8, 18, 8, 1, dark))
        if m.variant == 2 {
            // Greywall Command's truck (T6): field-grey tilt over the bed, a pale band, no red.
            let grey = V3(0.3, 0.32, 0.31), band = V3(0.62, 0.63, 0.6)
            p.append(box(-14, 10, -24, 28, 4, 62, plate, 7))
            p.append(box(-14, 14, -24, 28, 22, 60, grey, 6))
            p.append(box(-14.4, 28, -18, 28.8, 3, 48, band, 6))
        } else if m.variant == 1 {
            p.append(box(-12, 10, -24, 24, 20, 60, black, 7))
            p.append(box(-12.4, 22, -20, 24.8, 2, 52, red)); p.append(box(-12.4, 14, -20, 24.8, 2, 52, red))
            p.append(box(-4, 14, 36.2, 8, 8, 0.6, red))
        } else {
            p.append(box(-14, 10, -24, 28, 4, 62, plate, 7))
            p.append(box(-14, 14, -24, 28, 22, 60, snow ? V3(0.56, 0.58, 0.58) : V3(0.09, 0.09, 0.1), 6))      // the tilt (P460: white canvas)
            p.append(box(-14.4, 28, -18, 28.8, 3, 48, red, 6))
        }
        p.append(box(-14, 10, 38, 3, 2, 0.6, glow, 9)); p.append(box(11, 10, 38, 3, 2, 0.6, glow, 9))
    }
    AshArmour.strip(m, &p)                                                                     // P449: plates shot off
    if m.wreck == 7 { BoatLooks.rock(&p, pitch: m.boatRock.x, roll: m.boatRock.y) }          // P449: over his truck's hull
    return p
}
