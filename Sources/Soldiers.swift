import Foundation
import simd

// The Capital garrison (save keys from the Steelhold days): six soldier ranks, and the heavy deck guns on the
// fortress corners. Models, stances and the crew-station pose hooks: SoldierRig.swift.
//  Trooper  (recruit)  20 HP, rifle or chatter gun; short bursts from mid range, falls back when hurt.
//  Vanguard (trooper)  30 HP, cuirass; shotgun (rushes in) or rifle (strafes); lobs grenades at players in cover.
//  Marksman            26 HP; farsight rifle from long range with an aiming laser before each shot; backs away.
//  Bulwark  (ironclad) 60 HP, full plate, shrugs off knockback; skybreaker or arc lance; advances, enrages.
//  Officer             28 HP, sidearm; points the squad at the threat and quickens everyone's reaction.
//  Pilot    (crew)     18 HP, sidearm or chatter gun; vehicle drivers, gunners and pilots.
// They alert each other, chase the last place they saw the player, and reload between magazines.
// Deck guns traverse slowly, solve a ballistic arc, glow while charging, then fire twin shells.

final class SoldierBrain {
    var gun: Int { didSet { let g = Guns.current(gun); if g != gun { gun = g; mag = min(mag, Guns.all[g].mag) } } }   // (P217: retired guns swap)
    var mag: Int
    var reload: Float = 0
    var burst = 0
    var shotTimer: Float = 0
    var react: Float = 1
    var aimTime: Float = 0
    var glinted = false            // an Ashguard sharpshooter has shown its scope's glint on this target (G5)
    var strafeTimer: Float = 0
    var strafeDir: Float = 1
    var lastSeen: V3?
    var seenAgo: Float = 99
    var sees = false
    var losTimer: Float = 0
    var grenadeCD: Float = Rand.float(in: 4...10)
    var retreat: Float = 0
    var retreatCD: Float = 0
    var pitch: Float = 0            // deck gun barrel elevation / soldier aim elevation
    var charge: Float = 0
    var kick: Float = 0             // deck gun barrel recoil 1 -> 0
    var kickSide: Float = 0         // ... of the left (-1) or right (1) barrel only, or both (0)
    var turret: Float = 0           // Ashguard vehicles: turret / gun world yaw (AshUnits.swift)
    var ashTimer: Float = 5         // the Ash Marshal: seconds to his next marked barrage
    var ashCalls = 0                // ... and how often he has called his guard
    var crewed = false              // deck gun: a live soldier stands at it in the gunner stance
    var cover: V3?                  // a spot out of the player's sight to reload in
    var coverSearch: Float = 0
    var flank: V3?                  // where a flanking trooper / relocating marksman is heading
    var flankTimer: Float = Rand.float(in: 2...5)
    // Animation state (SoldierRig.swift).
    var clock: Float = 0             // seconds alive (idle breathing, glances, parade-rest cycle)
    var aimHold: Float = 0           // keeps the weapon shouldered this long after seeing the target / firing
    var recoil: Float = 0            // 1 at a shot, decays fast
    var reloadTotal: Float = 1       // length of the current reload
    var throwT: Float = 0            // grenade throw left (0.7 s)
    var pointT: Float = 0            // officer pointing the squad at the threat
    var station = StationPose.none   // crew station pose (vehicles / ships)
    var homing = false               // calm: walking back to the post after straying
    var seat: Float = 0.45           // seat top above the feet (blocks), seated stations
    // Citadel orders (CapitalBases.swift): walk to `order` (running if orderRun), take `orderStation` there facing
    // `orderFace`; `ready` carries the weapon at low ready (patrols, lockdown) instead of shouldered for the march.
    var order: V3?
    var orderStation = StationPose.none
    var orderRun = false
    var orderFace: V3?
    // P194: a deck gun's own gunner: where it stands behind its gun (kept through a save, MobSave), and the gun's
    // next look for a new one when the post is empty.
    var gunPost: V3?
    var gunnerCD: Float = 0
    var ready = false
    // The Ash Vault's squads (AshArmy.swift): a role (mortar crew, medic, MG gunner), whether this is a patrol or
    // reinforcement (an extra, counted against the unit cap), the far-AI tick accumulator, a medic's patient and a
    // patrol's two ends.
    var role = 0
    var extra = false
    var lodAcc: Float = 0
    var lodSpeed: Float = 0
    var healScan: Float = 0
    weak var patient: Mob?
    var leg: (V3, V3)?
    var spun = false                 // Ashsaw gunner: the bolt is racked for the next burst (a readable click first)
    // R23 (Oct 13 evening: "factions kept apart and fighting each other; base troops hunting him instead of spinning in
    // place"): a rival faction's soldier or vessel in range (looked for a few times a second, not every frame) and
    // whether it is in sight; the search for a player out of sight (the spot being searched, how many so far, seconds
    // on this one); the alarm source this soldier was last sent to (a citadel lockdown sends it once, not every
    // second); and a sentry's watch heading (glances round it instead of turning a little further every few seconds).
    var foe: CapTarget?
    var foeSees = false
    var foeTimer: Float = Rand.float(in: 0..<0.5)
    var hunt: V3?
    var huntP = V3(0, 0, 0)          // where the player was when that spot was picked
    var huntN = 0
    var huntT: Float = 0
    var huntWait: Float = 0          // seconds left looking round a reached spot
    var huntArrived = false
    var alarmSrc: V3?
    var watchYaw: Float?
    init(gun: Int) { let g = Guns.current(gun); self.gun = g; mag = g >= 0 ? Guns.all[g].mag : 0 }
}

enum Soldier {
    struct Rank {
        let near: Float, far: Float     // preferred distance band (overridden per gun below)
        let sight: Float
        let spread: Float               // aim error (radians)
        let burst: ClosedRange<Int>
        let gap: ClosedRange<Float>     // pause between bursts
        let react: Float                // delay before the first shot after spotting
        let strafe: Float               // 0...1 how much they sidestep
        let damage: Float               // multiplier on the gun's damage
        let armor: Int
        let toughness: Float
    }
    static let ranks: [Rank] = [
        Rank(near: 8, far: 14, sight: 26, spread: 0.07, burst: 3...5, gap: 1.0...1.8, react: 0.9, strafe: 0.3, damage: 0.8, armor: 4, toughness: 0),
        Rank(near: 7, far: 12, sight: 32, spread: 0.045, burst: 4...6, gap: 0.8...1.4, react: 0.7, strafe: 0.8, damage: 0.9, armor: 10, toughness: 2),
        Rank(near: 16, far: 40, sight: 60, spread: 0.012, burst: 1...1, gap: 1.6...2.4, react: 0.4, strafe: 0.2, damage: 0.75, armor: 8, toughness: 0),
        Rank(near: 8, far: 20, sight: 40, spread: 0.03, burst: 1...2, gap: 1.8...2.6, react: 0.8, strafe: 0, damage: 0.9, armor: 14, toughness: 4),
        Rank(near: 6, far: 14, sight: 34, spread: 0.04, burst: 1...3, gap: 0.6...1.2, react: 0.5, strafe: 0.4, damage: 0.85, armor: 6, toughness: 0),
        Rank(near: 6, far: 14, sight: 28, spread: 0.06, burst: 1...3, gap: 0.7...1.4, react: 0.8, strafe: 0.5, damage: 0.7, armor: 4, toughness: 0),
    ]
    // Voice (SoldierVoice / footsteps) per rank: officers speak like vanguards, pilots like troopers.
    static func voice(_ r: Int) -> Int { [0, 1, 2, 3, 1, 0][max(0, min(5, r))] }

    static func rank(_ k: MobKind) -> Int? {
        switch k {
        case .soldierRecruit: return 0
        case .soldierTrooper: return 1
        case .soldierMarksman: return 2
        case .soldierIronclad: return 3
        case .soldierOfficer, .ashMarshal, .ashChancellor: return 4
        case .soldierCrew: return 5
        default: return nil
        }
    }

    // Which gun a new soldier carries.
    static func pickGun(_ k: MobKind) -> Int {
        let r = Rand.float(in: 0..<1)
        switch k {
        case .soldierRecruit: return r < 0.6 ? Guns.rifle : Guns.smg
        case .soldierTrooper: return r < 0.5 ? Guns.shotgun : Guns.rifle
        case .soldierMarksman: return r < 0.8 ? Guns.sniper : Guns.rifle
        case .soldierOfficer: return Guns.pistol
        case .ashMarshal: return Guns.sturmwind
        case .ashChancellor: return Guns.sturmwind
        case .soldierCrew: return r < 0.7 ? Guns.pistol : Guns.smg
        default: return r < 0.5 ? Guns.launcher : Guns.arc
        }
    }

    // The Ashguard's loadouts (AshArms.swift): riflemen a bolt rifle or carbine, stormers a carbine or machine pistol,
    // sharpshooters the bolt rifle, heavies the Ashsaw, officers and drivers a machine pistol, the Marshal a carbine.
    static func ashGun(_ k: MobKind, roll r: Float) -> Int {
        switch k {
        case .soldierRecruit: return r < 0.6 ? Guns.kessel : Guns.sturmwind
        case .soldierTrooper: return r < 0.55 ? Guns.sturmwind : Guns.hagel
        case .soldierMarksman: return Guns.kessel
        case .soldierIronclad: return Guns.kessel
        case .ashMarshal: return Guns.sturmwind
        case .ashChancellor: return Guns.sturmwind
        default: return Guns.sturmwind
        }
    }

    // Preferred distance band for a gun (the rank's own for its main weapon).
    static func band(_ rank: Int, _ gun: Int) -> (Float, Float) {
        switch gun {
        case Guns.kessel: return rank == 2 ? (16, 40) : (12, 28)
        case Guns.hagel, Guns.needle: return (5, 11)
        case Guns.slatefall: return (8, 20)
        case Guns.repeater: return (10, 24)
        case Guns.longwatch: return (16, 40)
        case Guns.breaker: return (4, 12)
        case Guns.sturmwind: return (8, 18)
        case Guns.ashsaw: return (10, 26)
        case Guns.shotgun: return (2.5, 6)
        case Guns.smg: return (5, 10)
        case Guns.launcher: return (10, 26)
        case Guns.arc: return (6, 18)
        case Guns.pistol: return (4, 12)
        case Guns.rifle where rank == 2: return (12, 26)
        default: return (ranks[rank].near, ranks[rank].far)
        }
    }

    // Garrison posts: about one vanguard post in four is held by an officer instead (stable per post). Structures
    // can also place "soldier_officer" / "soldier_crew" directly.
    static func garrison(_ k: MobKind, at p: V3) -> MobKind {
        guard k == .soldierTrooper else { return k }
        return hash3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)), 0x0FF1) % 4 == 0 ? .soldierOfficer : k
    }

    // Reference-style difficulty scaling of their damage against the player.
    static let difficultyTable: [Float] = [0, 0.5, 0.75, 1]
    static func difficultyScale(_ d: Int) -> Float { difficultyTable[max(0, min(3, d))] }
}

extension MobKind {
    var militarySpec: Spec {
        switch self {
        case .soldierRecruit:
            return Spec(name: "Capital Trooper", halfW: 0.3, height: 1.9, health: 20, speed: 3.0, behavior: .monster,
                        drops: [("capital_rounds", 2, 6), ("iron_nugget", 0, 3)], xp: 8, call: .gun(11))
        case .soldierTrooper:
            return Spec(name: "Capital Vanguard", halfW: 0.32, height: 1.95, health: 30, speed: 3.2, behavior: .monster,
                        drops: [("capital_rounds", 1, 6), ("shotgun_shells", 0, 3), ("bread", 0, 1)], xp: 12, call: .gun(11))
        case .soldierMarksman:
            return Spec(name: "Capital Marksman", halfW: 0.3, height: 1.9, health: 26, speed: 2.8, behavior: .monster,
                        drops: [("heavy_rounds", 1, 3), ("iron_nugget", 0, 2)], xp: 14, call: .gun(11))
        case .soldierIronclad:
            return Spec(name: "Capital Bulwark", halfW: 0.42, height: 2.25, health: 60, speed: 2.0, behavior: .monster,
                        drops: [("iron_ingot", 1, 4), ("rocket_ammo", 0, 2), ("arc_cell", 0, 3)], xp: 30, call: .gun(11), fireImmune: true)
        case .soldierOfficer:
            return Spec(name: "Capital Officer", halfW: 0.3, height: 1.95, health: 28, speed: 3.0, behavior: .monster,
                        drops: [("capital_rounds", 2, 6), ("gold_nugget", 0, 3)], xp: 16, call: .gun(11))
        case .soldierCrew:
            return Spec(name: "Capital Pilot", halfW: 0.3, height: 1.9, health: 18, speed: 3.1, behavior: .monster,
                        drops: [("capital_rounds", 1, 4), ("iron_nugget", 0, 2)], xp: 8, call: .gun(11))
        default:
            // A true-scale twin 42 cm turret (HeavyTurret): 14 m wide, 5.5 m tall gunhouse on a barbette.
            return Spec(name: "Twin 42 cm Turret", halfW: 7, height: 5.5, health: 400, speed: 0, behavior: .monster,
                        drops: [("iron_ingot", 4, 9), ("gunpowder", 2, 6), ("rocket_ammo", 1, 3)], xp: 40, call: .gun(12), fireImmune: true)
        }
    }
}

extension Mob {
    var soldierBrain: SoldierBrain {
        if let b = brain { return b }
        let b = SoldierBrain(gun: kind == .deckGun ? -1 : (variant >= 0 && variant < Guns.all.count ? variant : Guns.rifle))
        brain = b
        return b
    }

    // Base armour of the garrison ranks (added to any worn pieces).
    var steelholdArmor: (Int, Float) {
        if kind == .deckGun { return (20, 8) }
        if kind.ash { return ashArmor }
        guard let r = Soldier.rank(kind) else { return (0, 0) }
        // Ashguard plate: +5 armour, +2 toughness over the Capital rank's (AshUnits.ashSetup).
        if faction == Faction.ashguard.rawValue { return (Soldier.ranks[r].armor + 5, Soldier.ranks[r].toughness + 2) }
        return (Soldier.ranks[r].armor, Soldier.ranks[r].toughness)
    }

    // Knockback taken (ironclads barely budge, deck guns not at all).
    // 1 - knockback resistance (reference: iron golems and deep stalkers 1, siegebeasts 0.75, tuskers 0.6).
    var knockbackTaken: Float {
        switch kind {
        case .soldierIronclad: return 0.15
        case .deckGun, .ironGolem, .warden, .ashTank, .ashHalftrack, .ashArtillery, .ashTruck, .ashBehemoth: return 0
        case .ashMarshal, .ashChancellor: return 0.3
        case .ravager: return 0.25
        case .hoglin, .zoglin: return 0.4
        default: return 1
        }
    }

    // Wakes every soldier within `r` and tells them where the player was.
    func alertGarrison(_ g: Game, _ at: V3, radius r: Float = 24) {
        // Only its own side wakes (T6: a Greywall alert roused every faction's soldiers near the base, the Capital's
        // crawler crew and the navy's marines alike).
        for m in g.mobs.mobs where m.kind.steelhold && m !== self && m.health > 0 && m.faction == faction && m.posse == posse && simd_length(m.pos - pos) < r {
            let b = m.soldierBrain
            if !m.aggro { m.aggro = true; b.react = max(b.react, 0.6) }
            if kind == .soldierOfficer { b.react = min(b.react, 0.35) }      // an officer's call: quicker to fire
            if b.seenAgo > 1 { b.lastSeen = at; b.seenAgo = min(b.seenAgo, 2) }
            m.lockTime = max(m.lockTime, 20)
        }
    }

    // Called from monsterAI for the four ranks; returns the walk speed.
    func soldierAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        if hired { return companionAI(dt, g) }                       // O2: a companion (Companions.swift)
        var canTarget = canTarget && !g.repAllied(self)               // O3: an ally's soldiers hold fire
        // R23: an alerted soldier (an alarm, a lockdown, a comrade's call: lockTime) hunts the player out to 64 blocks;
        // senseTarget lets go past the rank's follow range (26-40), and the alerted garrison stood at its posts.
        if !canTarget && aggro && lockTime > 0 && dist < 64 && g.survival && g.alive && !g.repAllied(self)
            && faction != Faction.ashguard.rawValue { canTarget = true }      // (the Ashguard stand down on their own: ashVictory)
        if posse == 3 && BountyHunters.holdOff { canTarget = false }  // R21: bounty hunters wait on the surface while he's below
        navyTick(dt, g)                                               // an Aegis Marine's shield (Navy.swift)
        var sp = soldierAIStep(dt, g, dist: dist, canTarget: canTarget)
        if isAegis { sp *= 1.33 }                                     // T8: an Aegis Marine moves a third faster
        if troop == Int8(TroopClass.hannibal.rawValue) { sp = hannibalJets(dt, g, dist: dist, canTarget: canTarget, speed: sp) }
        return leash == nil ? sp : applyLeash(sp)
    }
    // P192 (Oct 13: "make it so the Hannibal troops can fly"): a Hannibal trooper in a fight lifts off on the jump
    // jets in its power suit when the player is above it, out of its sight or well off: it climbs 3-6 blocks over
    // the higher of the two, hovers and closes in firing for three to five seconds, then drops back down; 8-14 s
    // between lifts. Flame from the two back nozzles and a roar while they burn.
    func hannibalJets(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool, speed: Float) -> Float {
        jetCD -= dt
        let b = soldierBrain
        if jet <= 0 && jetCD <= 0 && aggro && canTarget && onGround && !Blocks.isLiquid(g.world.block(Int(floor(pos.x)), Int(floor(pos.y + 0.2)), Int(floor(pos.z)))) && dist < 48 && b.reload <= 0 {
            let above = g.player.pos.y - pos.y > 2.5
            if above || dist > 16 || (!b.sees && dist < 32) {
                jet = Rand.float(in: 3...5)
                jetY = max(pos.y, g.player.pos.y) + Rand.float(in: 3...6)
                jetCD = Rand.float(in: 8...14)
                vel.y = 4
                onGround = false
                g.sfx(.fireworkLaunch, 0.9, at: eye)
            }
        }
        guard jet > 0 else { return speed }
        let back = V3(sinf(yaw), 0, cosf(yaw)), right = V3(cosf(yaw), 0, -sinf(yaw))
        for side: Float in [-1, 1] where Rand.float(in: 0..<1) < dt * 40 {
            let n = pos + back * 0.35 + right * (0.18 * side) + V3(0, 0.9, 0)
            g.particles.add(Particle(pos: n, vel: V3(Rand.float(in: -0.3...0.3), Rand.float(in: -5 ... -3), Rand.float(in: -0.3...0.3)),
                                     life: Rand.float(in: 0.12...0.25), maxLife: 0.25, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1,
                                     size: Rand.float(in: 0.1...0.16), gravity: 0, color: V3(1, 0.6, 0.18), collide: false, glow: true))
        }
        // In the air it closes to its firing band instead of standing off.
        return dist > 10 ? max(speed, spec.speed * 1.2) : speed
    }

    private func soldierAIStep(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        guard let r = Soldier.rank(kind) else { return 0 }
        let rank = Soldier.ranks[r]
        let b = soldierBrain
        let gs = Guns.all[b.gun]
        let w = g.world
        if home == nil { home = pos }
        b.clock += dt
        b.aimHold -= dt
        b.recoil = max(0, b.recoil - dt * 7)
        b.throwT = max(0, b.throwT - dt)
        b.pointT = max(0, b.pointT - dt)
        b.shotTimer -= dt
        b.grenadeCD -= dt
        b.retreat -= dt
        b.retreatCD -= dt
        b.seenAgo += dt
        b.strafeTimer -= dt
        if b.reload > 0 {
            b.reload -= dt
            if b.reload <= 0 { b.mag = b.role == AshArmy.mg ? AshArmy.beltMag : gs.mag }     // the MG gunner: a belt
        }
        // Line of sight, a few times a second.
        let target = g.player.eye - V3(0, 0.3, 0)
        b.losTimer -= dt
        if b.losTimer <= 0 {
            b.losTimer = 0.2 + Rand.float(in: 0..<0.1)
            b.sees = canTarget && dist < rank.sight * WeatherWar.sight && w.canSee(eye, g.player.eye)    // O7: fog and storms
        }
        let sees = b.sees && canTarget
        // No player in sight: fire on an enemy faction's vessel or crawler in range (frigates, crawlers: CapitalShips.swift).
        // P163 (Oct 13: "two different bases beside each other, and they're not attacking each other"): rival soldiers
        // are noticed out to 64 blocks (was 1.5 x the rank's sight, 30-45); one beyond firing range is advanced on.
        // R23: the search runs a few times a second (it scanned every ship and mob every frame for every soldier), and
        // a rival nearer than the player is fought even with the player in sight: troops of two factions that meet
        // round him fight each other first instead of only ever turning on him together. One out of sight is closed on
        // (the path finder takes it round the wall) rather than stared at.
        b.foeTimer -= dt
        if b.foeTimer <= 0 && factionValue != .none {          // (bounty hunters, posse 3, belong to no faction)
            b.foeTimer = 0.4 + Rand.float(in: 0..<0.2)
            let f = w.ships.nearestFoe(of: factionValue, near: pos, range: max(rank.sight * 1.5, 64), game: g)
            b.foe = (f?.ship != nil || f?.mob != nil) ? f : nil
            if let fp = b.foe?.point { b.foeSees = w.canSee(eye, fp) }
        }
        if let fm = b.foe?.mob, fm.health <= 0 { b.foe = nil; b.foeTimer = min(b.foeTimer, 0.1) }
        if b.foe?.ship == nil && b.foe?.mob == nil { b.foe = nil }
        if var foe = b.foe {
            if let fm = foe.mob { foe.point = fm.pos + V3(0, fm.height * 0.6, 0) }
            let fd: Float = simd_length(foe.point - eye)
            if !sees || fd + 4 < dist { b.foe = foe } else { b.foe = nil; b.foeTimer = max(b.foeTimer, 0.3) }
        }
        if let foe = b.foe {
            aggro = true
            b.react -= dt
            face(foe.point)
            if foe.mob != nil && (simd_length(foe.point - eye) > rank.sight * 0.9 || !b.foeSees) { return spec.speed * 0.85 }
            let tp = foe.point - eye
            b.pitch += (max(-0.9, min(1.2, atan2f(tp.y, simd_length(V2(tp.x, tp.z))))) - b.pitch) * min(1, dt * 8)
            soldierFire(dt, g, b, gs, rank: r, dist: min(simd_length(tp), rank.sight - 1), target: foe.point)
            return 0
        }
        if sees {
            // Noticed up close, in front, or once alerted.
            let toP = simd_normalize(V3(g.player.pos.x - pos.x, 0, g.player.pos.z - pos.z) + V3(1e-4, 0, 0))
            if !aggro && (dist < 10 || simd_dot(toP, forward) > 0.2 || hurt > 0) {
                aggro = true
                b.react = rank.react
                shout(g, .soldier(Soldier.voice(r), .alert), 1.1, at: eye)
                if Rand.float(in: 0..<1) < 0.5 { g.sfx(.gun(11), 0.6, at: eye) }
                if r == 4 { b.pointT = 1.4 }
                alertGarrison(g, g.player.pos)
            }
            if aggro {
                b.aimHold = 1.2
                if b.seenAgo > 3 { b.react = max(b.react, rank.react) }
                b.lastSeen = g.player.pos
                b.seenAgo = 0
            }
        }
        if hurt > 0.35 && !aggro { aggro = true; if b.foe == nil { alertGarrison(g, g.player.pos) } }   // (R23: a rival's round isn't the player's)
        // Pilots and passengers stay in their seats (aircraft, vehicles: FlightCrew in Aircraft.swift). Passengers
        // with a long arm are door gunners: turned in the seat (FlightCrew), they fire at the player in sight.
        if b.station == .seated || b.station == .passenger {
            strafe = 0
            if b.station == .passenger && sees && aggro && b.gun != Guns.pistol {
                b.react -= dt
                let tp = target - eye
                let flat: Float = simd_length(V2(tp.x, tp.z))
                b.pitch += (max(-0.9, min(1.0, atan2f(tp.y, flat))) - b.pitch) * min(1, dt * 8)
                soldierFire(dt, g, b, gs, rank: r, dist: dist, target: target)
            }
            return 0
        }
        // Turret crews stay at their guns whatever happens round them.
        if b.orderStation == .gunner, let sp = followOrder(g) { return sp }
        guard aggro && canTarget else {
            b.aimTime = 0; b.glinted = false
            b.hunt = nil
            // R23: lost him for good (no sighting for 45 s, nobody calling it in): stand down, so the next sighting is
            // called out again and the post duty below walks it back to its post.
            if aggro && lockTime <= 0 && b.seenAgo > 45 && b.order == nil { aggro = false; b.lastSeen = nil }
            if let sp = followOrder(g) { return sp }
            // Garrison duty: stroll near the post; marksmen keep watch, and so does a vehicle's crew at its post in the
            // hull's frame (a stroll round `home`, where it spawned in the world, pulled it off its post as the vehicle
            // drove away: ridecheck crew, a trooper 1.9 blocks off post 0, runs 605 and 634).
            let aboard = crewPost != nil && deck != nil
            if r == 2 || aboard {
                if aboard { wanderGoal = nil; moving = false }
                if aiTimer <= 0 {
                    aiTimer = Rand.float(in: 2...5)
                    // R23: a sentry glances round its watch heading; adding a random turn to the last one walked its
                    // heading round and round (a marksman on a tower turning in place all day).
                    if aboard { yaw += Rand.float(in: -1.2...1.2) } else {
                        if b.watchYaw == nil { b.watchYaw = yaw }
                        yaw = (b.watchYaw ?? yaw) + Rand.float(in: -0.7...0.7)
                    }
                }
                return 0
            }
            // Strolls stay within 7 of the post; one who strayed past 12 (a chase, a push) walks back to within 5. A
            // stroll goal out past the old 10-block line flipped it between the goal and home every tick (behaviour
            // sim on a citadel: 19 of 42 soldiers spinning).
            // R23: about one trooper post in three walks a wider beat (14 round the post) so the base is patrolled
            // between the posts, not just stood at them.
            if let h = home {
                let beat = (r == 0 || r == 1) && hash3(Int(floor(h.x)), Int(floor(h.y)), Int(floor(h.z)), 0xBEA7) % 3 == 0
                strollArea = (h, beat ? 14 : 7)
                let off = simd_length(V2(h.x - pos.x, h.z - pos.z))
                if off > (beat ? 20 : 12) { b.homing = true }
                if b.homing && gaveUp(h) { b.homing = false; home = pos }        // can't get back: this is the post now
                if b.homing {
                    if off > (beat ? 8 : 5) { wanderGoal = nil; moving = true; face(h); return spec.speed * 0.5 }
                    b.homing = false; moving = false; aiTimer = Rand.float(in: 1...3)
                }
            }
            wander()
            return moving ? spec.speed * 0.45 : 0
        }
        b.react -= dt
        b.coverSearch -= dt
        b.flankTimer -= dt
        if b.mag <= 0 && b.reload <= 0 {
            b.reload = gs.reload * (r == 3 ? 1.3 : 1)
            b.reloadTotal = b.reload
            g.sfx(.gunReload(gs.sound), 0.6, at: eye)
            if Rand.float(in: 0..<1) < 0.5 { shout(g, .soldier(Soldier.voice(r), .reload), 0.9, at: eye) }
        }
        if b.reload <= 0 { b.cover = nil }
        let (near, far) = Soldier.band(r, b.gun)
        var speed: Float = 0
        // Recruits fall back when badly hurt; marksmen back off from anyone who gets close.
        if r == 0 && health < spec.health * 3 / 10 && b.retreatCD <= 0 { b.retreat = 4; b.retreatCD = 12 }
        if r == 2 && sees && dist < 9 && b.retreatCD <= 0 { b.retreat = 2.5; b.retreatCD = 5 }
        if b.retreat > 0 {
            face(pos * 2 - g.player.pos)
            return spec.speed * 1.15
        }
        // Reloading: duck out of sight first (ironclads don't bother).
        if b.reload > 0 && r != 3 {
            if b.cover == nil && b.coverSearch <= 0 && sees { b.cover = findCover(g, from: g.player.eye); b.coverSearch = 1 }
            if let c = b.cover {
                if simd_length(V2(c.x - pos.x, c.z - pos.z)) > 0.6 { face(c); return spec.speed * 1.1 }
                face(g.player.pos)
                return 0
            }
        }
        if sees {
            face(g.player.pos)
            let tp = g.player.eye - V3(0, 0.3, 0) - eye
            b.pitch += (max(-0.9, min(0.9, atan2f(tp.y, simd_length(V2(tp.x, tp.z))))) - b.pitch) * min(1, dt * 8)
            if b.reload > 0 {
                speed = dist < far ? -spec.speed * 0.7 : 0                       // give ground while reloading
            } else if let f = b.flank, b.flankTimer > 0 {
                // Flank / relocate while facing the target: walk the offset with forward + sideways steps.
                var d = f - pos
                d.y = 0
                let l = simd_length(d)
                if l < 1 { b.flank = nil } else {
                    let right = V3(cosf(yaw), 0, -sinf(yaw))
                    speed = simd_dot(d / l, forward) * spec.speed
                    strafe = simd_dot(d / l, right) * spec.speed
                }
            } else if dist > far {
                speed = spec.speed
            } else if dist < near {
                speed = -spec.speed * 0.8
            } else if rank.strafe > 0 {
                if b.strafeTimer <= 0 { b.strafeTimer = Rand.float(in: 0.8...2.2); b.strafeDir = Rand.float(in: 0..<1) < 0.5 ? -1 : 1 }
                strafe = b.strafeDir * spec.speed * 0.75 * rank.strafe
            }
            if b.gun == Guns.shotgun && dist > near { speed = spec.speed * 1.25 }   // shotgunners rush in
            if r == 3 && health < spec.health / 2 { speed = max(speed, spec.speed * 0.6) }
            // Rifle troopers swing round the target's side every few seconds (Spec Ops flank wider and quietly, below).
            let tc = troopClass
            if r == 1 && tc != .specOps && b.gun != Guns.shotgun && b.flankTimer <= 0 && b.reload <= 0 {
                b.flankTimer = Rand.float(in: 4...7)
                let toMe = simd_normalize(V3(pos.x - g.player.pos.x, 0, pos.z - g.player.pos.z) + V3(1e-4, 0, 0))
                let side = V3(-toMe.z, 0, toMe.x) * (Rand.float(in: 0..<1) < 0.5 ? -1 : 1)
                b.flank = g.player.pos + simd_normalize(toMe + side * 1.4) * min(dist, (near + far) / 2)
                if Rand.float(in: 0..<1) < 0.5 { shout(g, .soldier(Soldier.voice(r), .attack), 0.9, at: eye) }      // "flanking!"
            }
            // Troop classes: Spec Ops swing wide round the target's flank, quietly; Hannibal troopers push in firing.
            if tc == .specOps && r != 2 && b.flankTimer <= 0 && b.reload <= 0 {
                b.flankTimer = Rand.float(in: 3...5)
                let toMe = simd_normalize(V3(pos.x - g.player.pos.x, 0, pos.z - g.player.pos.z) + V3(1e-4, 0, 0))
                let side = V3(-toMe.z, 0, toMe.x) * (Rand.float(in: 0..<1) < 0.5 ? -1 : 1)
                b.flank = g.player.pos + simd_normalize(toMe * 0.4 + side * 1.6) * min(dist, (near + far) / 2)
            }
            if tc == .hannibal && b.reload <= 0 && dist > 4 { speed = max(speed, spec.speed * 0.55); strafe *= 0.3 }
            let shotsBefore = b.mag
            soldierFire(dt, g, b, gs, rank: r, dist: dist, target: target)
            // Marksmen move to a new spot after a shot now and then.
            if r == 2 && b.mag < shotsBefore && Rand.float(in: 0..<1) < 0.5 {
                let right = V3(cosf(yaw), 0, -sinf(yaw))
                b.flank = pos + right * (Rand.float(in: 0..<1) < 0.5 ? -5 : 5)
                b.flankTimer = 2.5
                if Rand.float(in: 0..<1) < 0.3 { shout(g, .soldier(Soldier.voice(r), .retreat), 0.8, at: eye) }     // "moving!"
            }
        } else {
            b.aimTime = 0
            // Suppressing fire: automatic guns keep shooting where the player ducked out of sight.
            if let ls = b.lastSeen, b.seenAgo < 2.5, b.gun == Guns.rifle || b.gun == Guns.smg || b.gun == Guns.sturmwind || b.gun == Guns.hagel || b.gun == Guns.slatefall || b.gun == Guns.repeater || r == 3,
               b.reload <= 0, b.react <= 0, b.shotTimer <= 0, b.mag > 0, simd_length(ls - pos) < rank.sight {
                suppress(g, b, gs, at: ls + V3(0, 1.2, 0), rank: rank)
            }
            // A last sighting it can't get to (the path finder gave it up) is dropped for the search below.
            if let ls = b.lastSeen, gaveUp(ls) { b.lastSeen = nil }
            if let ls = b.lastSeen, b.seenAgo < 14 {
                // Troopers flush players out of cover with a grenade, everyone closes in on the last sighting.
                let d = simd_length(ls - pos)
                if (r == 1 || troop == 2) && b.grenadeCD <= 0 && b.seenAgo < 5 && d > 5 && d < 22 {
                    throwGrenade(g, at: ls)
                    b.grenadeCD = Rand.float(in: 9...14)
                }
                face(ls)
                speed = d > 2 ? spec.speed : 0
                if d <= 2 { b.lastSeen = nil; b.hunt = nil }
            } else if lockTime > 0 && dist < 64 && canTarget {
                // P197 (Oct 13: "the men are just spinning around... bunched at the front"): an alerted garrison
                // hunts the raider the whole time instead of milling round the last sighting: each soldier heads for
                // its own spot a few blocks round where the player is now (spread by who it is), then the next.
                // R23 (reported again): the search spot was written into lastSeen and only moved on every 9 s of the
                // clock, so a soldier that reached it dropped it (d <= 2), had the same spot handed straight back,
                // and walked through it and back (yaw flipping 180 degrees) until the 9 s ran out: spinning in place.
                // Now the spot is its own, and reaching it (or giving it up, or 12 s on it, or the player moving 12
                // blocks since) moves the search on to the next spot round the player, a golden-angle step further round.
                b.lastSeen = nil
                b.huntT += dt
                let pp = g.player.pos
                var next = b.hunt == nil || b.huntT > 12
                if let hs = b.hunt {
                    let here: Float = simd_length(V2(hs.x - pos.x, hs.z - pos.z))
                    let moved: Float = simd_length(V2(b.huntP.x - pp.x, b.huntP.z - pp.z))
                    // At the spot: a second or so looking round it (standing, no turning to a point at its feet), then on.
                    if here < 1.8 && !b.huntArrived { b.huntArrived = true; b.huntWait = Rand.float(in: 0.8...1.6) }
                    if b.huntArrived { b.huntWait -= dt; if b.huntWait <= 0 { next = true } }
                    if moved > 12 || gaveUp(hs) { next = true }
                }
                if !next && b.huntArrived { return 0 }
                if next {
                    b.huntArrived = false
                    b.huntT = 0
                    b.huntP = pp
                    let h = ObjectIdentifier(self).hashValue
                    let a0: Float = Float(h & 1023) / 1023 * 2 * .pi
                    // (a spot at least 3 blocks off, so it is walked to: one at its feet was re-picked every tick)
                    for _ in 0..<4 {
                        b.huntN += 1
                        let a: Float = a0 + Float(b.huntN) * 2.39996
                        let rr: Float = (3 + Float((h >> 10) & 7)) * (b.huntN % 3 == 0 ? 0.5 : 1)
                        let c = V3(pp.x + cosf(a) * rr, pp.y, pp.z + sinf(a) * rr)
                        b.hunt = c
                        if simd_length(V2(c.x - pos.x, c.z - pos.z)) >= 3 { break }
                    }
                    if b.huntN % 4 == 1 && Rand.float(in: 0..<1) < 0.5 { shout(g, .soldier(Soldier.voice(r), .alert), 0.8, at: eye) }   // "search the area!"
                }
                if let hs = b.hunt { face(hs) }
                speed = spec.speed * 0.9
            } else {
                b.hunt = nil
                wander()
                speed = moving ? spec.speed * 0.5 : 0
            }
        }
        return speed * vary.speed                                    // R16: this soldier's own stride
    }

    func soldierFire(_ dt: Float, _ g: Game, _ b: SoldierBrain, _ gs: GunSpec, rank r: Int, dist: Float, target: V3) {
        guard b.reload <= 0, b.react <= 0, dist < Soldier.ranks[r].sight else { b.aimTime = 0; return }
        if b.mag <= 0 {
            b.reload = gs.reload * (r == 3 ? 1.3 : 1)
            b.reloadTotal = b.reload
            g.sfx(.gunReload(gs.sound), 0.6, at: eye)
            if Rand.float(in: 0..<1) < 0.4 { shout(g, .soldier(Soldier.voice(r), .reload), 0.9, at: eye) }
            return
        }
        guard b.shotTimer <= 0 else { return }
        // An Ashsaw gunner racks the bolt before each burst: a loud clack, then the rip 0.45 s later.
        if b.gun == Guns.ashsaw && b.burst <= 0 && !b.spun {
            b.spun = true
            b.shotTimer = 0.45
            b.aimHold = max(b.aimHold, 1.5)
            g.sfx(.gun(14), 1.1, at: eye)
            return
        }
        // Marksmen hold a laser on the target before every shot. An Ashguard sharpshooter's scope glints for as long
        // before its first shot at a target (G5: an unarmoured arrival in the vault died 92 blocks out in 4 s with no
        // sign of where the shots came from).
        var glintDone = false
        if b.gun == Guns.sniper || (kind == .soldierMarksman && !b.glinted && faction == Faction.ashguard.rawValue) {
            b.aimTime += dt
            if b.aimTime < 1.1 { return }
            b.aimTime = 0
            glintDone = true
        }
        let rank = Soldier.ranks[r]
        let enraged = r == 3 && health < spec.health / 2
        b.aimHold = max(b.aimHold, 1.5)
        let muzzle = SoldierRig.muzzleWorld(self)
        // Clear line of fire from the muzzle (the sight check is from the eye, every 0.2-0.3 s, through opaque blocks
        // only): a wall, window, door or fence between the gun and the target holds the shot.
        guard g.world.clearShot(muzzle, target) else { b.aimTime = 0; return }
        if glintDone { b.glinted = true }          // (a glint held up by a wall doesn't use up the warning)
        var aimAt = target
        let flight = gs.speed > 0 ? simd_length(target - muzzle) / gs.speed : 0
        aimAt += g.player.vel * flight * 0.8
        if b.gun == Guns.launcher { aimAt = g.player.pos + V3(0, 0.3, 0) + g.player.vel * flight * 0.6 }
        let dir = simd_normalize(aimAt - muzzle)
        // Soldiers' shotgun pellets hit softer (a point-blank volley shouldn't one-shot a full-health player).
        // The Ashguard are veterans (the Deep's harder army, docs/status/deep-balance.md): 60 % more damage and a
        // tighter group than the same rank on the surface.
        let veteran = faction == Faction.ashguard.rawValue
        let scale = Soldier.difficultyScale(g.difficulty) * rank.damage * (gs.pellets > 1 ? 0.6 : 1) * (veteran ? 1.6 : 1) * vary.damage
        switch gs.shot {
        case .bullet:
            for _ in 0..<gs.pellets {
                // P105: a gun's kick opens the aim (a heavy pistol or marksman's rifle more than a carbine), except for
                // a Hannibal trooper: the power suit takes it.
                let kick = aimKick(gs)
                let hunter: Float = posse == 3 ? 0.7 : 1                 // R21: bounty hunters shoot straighter than the ranks
                let d = Guns.scatter(dir, (rank.spread + gs.spread * 0.5 + kick) * (veteran ? 0.6 : 1) * (b.gun == Guns.ashsaw ? 1.8 : 1) * hunter)
                g.arms.spawn(Slug(pos: muzzle, vel: d * gs.speed, kind: .bullet, damage: gs.damage * scale, fromPlayer: false,
                                  shooter: ObjectIdentifier(self), by: spec.name, life: gs.range / gs.speed, gravity: 1.5))
            }
        case .rocket:
            var s = Slug(pos: muzzle + dir * 0.5, vel: Guns.scatter(dir, rank.spread) * gs.speed, kind: .rocket, damage: 0, fromPlayer: false,
                         shooter: ObjectIdentifier(self), by: spec.name, life: gs.range / gs.speed, gravity: 0.6)
            s.power = 1.8
            s.breaks = customName == FactionRaids.rocketeerName              // P215: a raider's rockets hole houses
            g.arms.spawn(s)
        case .beam:
            g.arms.beam(g, from: muzzle, dir: Guns.scatter(dir, rank.spread), range: gs.range, damage: gs.damage * scale, fromPlayer: false, shooter: self, by: spec.name)
        }
        let quiet = TroopClass.suppressed(self)                       // Spec Ops suppressors: hushed, no alarm noise
        g.sfx(.gun(gs.sound), quiet ? 0.35 : 1, at: muzzle)
        if factionValue != .steelhold && !quiet { g.baseNoise(at: muzzle, kind: .gunshot) }      // other factions' fire carries to citadels
        g.particles.add(Particle(pos: muzzle + dir * 0.2, vel: dir * 0.5, life: 0.06, maxLife: 0.06, layer: Int(Tex.id("smoke")), uv0: V2(0, 0),
                                 uvSize: 1, size: 0.14, gravity: 0, color: gs.shot == .beam ? V3(0.8, 2, 2.4) : V3(2.4, 1.7, 0.6), collide: false, glow: true))
        g.addFlash(at: muzzle + dir * 0.3, color: gs.shot == .beam ? V3(1.2, 2.6, 3.2) : V3(4, 3, 1.6), radius: 6, life: 0.06)   // lights the terrain (Fancy)
        b.mag -= 1
        b.recoil = 1
        // The Ashsaw fires in long ripping bursts (with a long pause between them: the moment to move).
        if b.burst <= 0 { b.burst = b.gun == Guns.ashsaw ? Rand.int(in: 7...11) : (troop == 3 ? Rand.int(in: 6...10) : Rand.int(in: rank.burst)) }
        b.burst -= 1
        if b.burst <= 0 { b.spun = false }
        let rate: Float = enraged ? 0.6 : 1
        b.shotTimer = b.burst > 0 ? gs.interval * (b.gun == Guns.ashsaw ? 1 : 1.4) * rate
                                  : Rand.float(in: rank.gap) * rate * (b.gun == Guns.ashsaw ? 1.3 : 1)
    }

    // A short burst into the player's last position (wider spread; it pins them behind cover).
    private func suppress(_ g: Game, _ b: SoldierBrain, _ gs: GunSpec, at t: V3, rank: Soldier.Rank) {
        let muzzle = SoldierRig.muzzleWorld(self)
        guard g.world.clearShot(muzzle, t) else { return }           // suppressing fire never goes through a wall either
        b.aimHold = max(b.aimHold, 1.2)
        b.recoil = 1
        let dir = simd_normalize(t - muzzle)
        let scale = Soldier.difficultyScale(g.difficulty) * rank.damage
        if gs.shot == .bullet {
            g.arms.spawn(Slug(pos: muzzle, vel: Guns.scatter(dir, rank.spread + 0.05) * gs.speed, kind: .bullet, damage: gs.damage * scale,
                              fromPlayer: false, shooter: ObjectIdentifier(self), by: spec.name, life: gs.range / gs.speed, gravity: 1.5))
            b.shotTimer = gs.interval * 2.5
        } else if gs.shot == .rocket {
            var s = Slug(pos: muzzle + dir * 0.5, vel: dir * gs.speed, kind: .rocket, damage: 0, fromPlayer: false,
                         shooter: ObjectIdentifier(self), by: spec.name, life: gs.range / gs.speed, gravity: 0.6)
            s.power = 1.8
            g.arms.spawn(s)
            b.shotTimer = 3
        } else {
            g.arms.beam(g, from: muzzle, dir: Guns.scatter(dir, 0.03), range: gs.range, damage: gs.damage * scale, fromPlayer: false, shooter: self, by: spec.name)
            b.shotTimer = 2.5
        }
        b.mag -= 1
        g.sfx(.gun(gs.sound), TroopClass.suppressed(self) ? 0.35 : 1, at: muzzle)
        g.addFlash(at: muzzle + dir * 0.3, color: gs.shot == .beam ? V3(1.2, 2.6, 3.2) : V3(4, 3, 1.6), radius: 6, life: 0.06)
    }

    // A nearby standing spot the player can't see (sampled in a ring of 2-6 blocks).
    // The nearest standable cell within 6 blocks that the threat can't see (14 random rays at random radii missed
    // the few cells behind a 3-wide wall often enough to fail the reload-in-cover check: run 371).
    private func findCover(_ g: Game, from threat: V3) -> V3? {
        let w = g.world
        let y = Int(floor(pos.y + 0.1))
        let bx = Int(floor(pos.x)), bz = Int(floor(pos.z))
        var spots: [(Float, V3)] = []
        for dz in -6...6 { for dx in -6...6 where dx * dx + dz * dz <= 36 && (dx != 0 || dz != 0) {
            let x = bx + dx, z = bz + dz
            for dy in [0, 1, -1] {
                let fy = y + dy
                guard Blocks.collide[Int(w.block(x, fy - 1, z))], !Blocks.collide[Int(w.block(x, fy, z))], !Blocks.collide[Int(w.block(x, fy + 1, z))] else { continue }
                let spot = V3(Float(x) + 0.5, Float(fy), Float(z) + 0.5)
                spots.append((simd_length(spot - pos), spot))
                break
            }
        } }
        spots.sort { $0.0 < $1.0 }
        // Sight checks nearest first (short rays; a search runs at most once a second per reloading soldier).
        for (_, spot) in spots.prefix(120) where !w.canSee(spot + V3(0, 1.5, 0), threat) { return spot }
        return nil
    }

    // A soldier's callout; Spec Ops keep quiet (backlog A2: they flank and hunt without shouting).
    func shout(_ g: Game, _ snd: Snd, _ v: Float, at p: V3) {
        if troopClass != .specOps { g.sfx(snd, v, at: p) }
    }

    private func throwGrenade(_ g: Game, at t: V3) {
        let from = eye + forward * 0.4
        var d = t - from
        let horiz = simd_length(V2(d.x, d.z))
        // Lob at 45 degrees: v^2 = g x / sin(2a) with a little height correction.
        let grav: Float = 20
        let v = sqrtf(grav * max(2, horiz + max(0, d.y) * 0.5))
        d.y = 0
        let flat = horiz > 0.01 ? d / horiz : forward
        var s = Slug(pos: from, vel: (flat + V3(0, 1, 0)) * (v * 0.7071), kind: .grenade, damage: 0, fromPlayer: false,
                     shooter: ObjectIdentifier(self), by: spec.name, life: 2.6, gravity: grav)
        s.power = 2
        g.arms.spawn(s)
        shout(g, .soldier(Soldier.voice(Soldier.rank(kind) ?? 1), .grenade), 1.1, at: eye)
        soldierBrain.throwT = 0.7
    }

    // MARK: Deck gun

    func updateDeckGun(_ dt: Float, _ g: Game) {
        NavalGuns.hurtEffects(self, dt, g)
        if Turrets.shared.manned === self { vel = .zero; soldierBrain.kick = max(0, soldierBrain.kick - dt * 1.5); return }   // the player has it (VehicleControls.swift)
        let b = soldierBrain
        vel = .zero
        attackCooldown = max(attackCooldown, -1)
        if fire > 0 { fire -= dt }
        b.reload -= dt
        b.kick = max(0, b.kick - dt * 1.5)
        // P210: a Greywall base's guns placed before the small tower gun are swapped for it.
        if factionValue == .greywall && variant != HeavyTurret.lightVariant { variant = HeavyTurret.lightVariant }
        let light = HeavyTurret.scale(self) != 1
        let pivot = pos + V3(0, HeavyTurret.trunnionY * HeavyTurret.scale(self), 0)
        let player = g.player.eye - V3(0, 0.6, 0)
        let to = player - pivot
        let dist = simd_length(to)
        // Unprovoked the turrets guard the citadel's grounds; provoked (hit, or the garrison alerted) they reach their full
        // range. They shelled players 220 blocks off in a nearby village without a reason (agent bots died, run 482).
        let engage: Float = aggro ? HeavyTurret.range : HeavyTurret.guardRange
        let canTarget = g.survival && g.alive && dist < engage
        b.losTimer -= dt
        if b.losTimer <= 0 {
            b.losTimer = 0.4
            b.sees = canTarget && g.world.canSee(pivot + V3(0, 0.8, 0), g.player.eye)
            b.crewed = deckGunCrewed(g)
            if !b.crewed && factionValue != .greywall { claimGunner(g) }
        }
        if b.sees && canTarget {
            if !aggro { aggro = true; g.sfx(.gun(10), 1.5, at: pivot); alertGarrison(g, g.player.pos, radius: 40) }
            b.lastSeen = player
            b.seenAgo = 0
        } else {
            b.seenAgo += dt
            if aggro && b.seenAgo > 60 { aggro = false }             // stands down a minute after losing the target
            // An enemy faction's vessel in range instead (CapitalShips.swift).
            if let foe = g.world.ships.nearestFoe(of: factionValue, near: pivot, range: HeavyTurret.range * 1.5, game: g), foe.ship != nil || foe.mob != nil {
                b.lastSeen = foe.point
                b.seenAgo = 0
            }
        }
        // Spotting still raises the alarm (above), but only a live gunner lays and fires the gun: an empty turret kept
        // shelling the player after the whole garrison was dead (Quest round 4).
        guard b.crewed, let tgt = b.lastSeen, b.seenAgo < 3 else { b.charge = 0; return }
        // Ballistic solution (low arc) for the heavy shells, half-leading the target.
        let v: Float = HeavyTurret.speed, grav: Float = HeavyTurret.gravity
        var aimP = tgt
        let flat0 = simd_length(V2(aimP.x - pivot.x, aimP.z - pivot.z))
        aimP += g.player.vel * (flat0 / v) * 0.5
        let dx = simd_length(V2(aimP.x - pivot.x, aimP.z - pivot.z)), dy = aimP.y - pivot.y
        let disc = v * v * v * v - grav * (grav * dx * dx + 2 * dy * v * v)
        var wantPitch: Float = 0.75
        if disc >= 0 && dx > 0.5 { wantPitch = atanf((v * v - sqrtf(disc)) / (grav * dx)) }
        wantPitch = max(HeavyTurret.pitchMin, min(HeavyTurret.pitchMax, wantPitch))
        let wantYaw = atan2f(-(aimP.x - pivot.x), -(aimP.z - pivot.z))
        var dyaw = wantYaw - yaw
        while dyaw > .pi { dyaw -= 2 * .pi }
        while dyaw < -.pi { dyaw += 2 * .pi }
        let turn: Float = HeavyTurret.traverse * dt * (light ? 4 : 1)   // a 1,000-tonne gunhouse traverses slowly
        yaw += max(-turn, min(turn, dyaw))
        b.pitch += max(-0.15 * dt, min(0.15 * dt, wantPitch - b.pitch))
        walkPhase += abs(max(-turn, min(turn, dyaw)))
        let aligned = abs(dyaw) < 0.04 && abs(wantPitch - b.pitch) < 0.03 && dx > 24
        if aligned && b.reload <= 0 {
            if b.charge == 0 { g.sfx(.gun(12), 1.2, at: pivot) }
            b.charge += dt
            if b.charge >= (light ? 0.4 : 1.2) {
                b.charge = 0
                b.reload = (g.difficulty >= 3 ? HeavyTurret.reload * 0.8 : HeavyTurret.reload) * (light ? 0.25 : 1)
                let fwd = V3(-sinf(yaw) * cosf(b.pitch), sinf(b.pitch), -cosf(yaw) * cosf(b.pitch))
                for sx: Float in [-1, 1] {
                    let muzzle = HeavyTurret.muzzle(self, sx)
                    var s = Slug(pos: muzzle, vel: Guns.scatter(fwd, 0.006) * v, kind: .shell, damage: 0, fromPlayer: false,
                                 shooter: ObjectIdentifier(self), by: spec.name, life: 3.5, gravity: grav)   // ~900 blocks at 260 m/s, then it's gone
                    HeavyTurret.arm(&s)
                    if light { s.power = 1.1 }
                    g.arms.spawn(s)
                    HeavyTurret.flash(g, muzzle, fwd, smoke: light ? 2 : 6)
                }
                g.sfx(.gun(9), 2, at: pivot)
                b.kick = 1; b.kickSide = 0
            }
        } else if !aligned {
            b.charge = max(0, b.charge - dt * 2)
        }
    }
}

extension Mob {
    // A live soldier posted at this deck gun (CapitalBases sends two per barbette, ~9 blocks behind it, as gunners).
    // P194 (Oct 13: "give each gun a seat under it with a gunner in it; kill him to take the gun"): an unmanned
    // Capital deck gun calls the nearest rifleman of its garrison to its breech, on a floor just behind the gun (4.5,
    // 6.5 or 9 blocks back, the first with standing room), where he stands at the gun's two handles. While he lives
    // the gun is his: the player can't take it (Game.useMob) and it fires on its own; kill him and it is free until
    // the next man is called (a look every 6 s, only soldiers already on that floor within 16 blocks).
    func claimGunner(_ g: Game) {
        let b = soldierBrain
        b.gunnerCD -= 0.4
        guard b.gunnerCD <= 0 else { return }
        b.gunnerCD = 6
        let back = V3(sinf(yaw), 0, cosf(yaw))
        var spot: V3?
        search: for k: Float in [4.5, 6.5, 9] {
            let p = pos + back * k
            let x = Int(floor(p.x)), z = Int(floor(p.z)), y0 = Int(floor(pos.y))
            for dy in [0, -1, 1] {
                let y = y0 + dy
                let under = g.world.block(x, y - 1, z), a = g.world.block(x, y, z), c = g.world.block(x, y + 1, z)
                if Blocks.collide[Int(under)] && !Blocks.isLiquid(under) && !Blocks.collide[Int(a)] && !Blocks.collide[Int(c)] && !Blocks.isLiquid(a) {
                    spot = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5); break search
                }
            }
        }
        guard let s = spot else { return }
        var best: Mob?, bd: Float = 16 * 16
        for m in g.mobs.mobs where m !== self && m.health > 0 && m.faction == faction && m.deck == nil
            && m.kind != .deckGun && m.kind != .soldierOfficer && m.kind != .soldierMarksman && Soldier.rank(m.kind) != nil {
            let br = m.soldierBrain
            guard br.orderStation == .none, abs(m.pos.y - s.y) < 2.5 else { continue }
            let d = V2(m.pos.x - s.x, m.pos.z - s.z), d2 = simd_length_squared(d)
            if d2 < bd { bd = d2; best = m }
        }
        guard let m = best else { return }
        m.takeGunPost(s, face: pos)
    }

    func takeGunPost(_ s: V3, face: V3) {
        let br = soldierBrain
        br.gunPost = s
        br.order = s
        br.orderStation = .gunner
        br.orderFace = face
        br.orderRun = false
        persistent = true
    }

    func deckGunCrewed(_ g: Game) -> Bool {
        // (A Greywall base's tower guns are worked by any of its soldiers posted beside them: the tower's lookout.)
        let grey = factionValue == .greywall
        for m in g.mobs.mobs where m.health > 0 && Soldier.rank(m.kind) != nil && (m.brain?.orderStation == .gunner || grey && m.factionValue == .greywall) {
            let d = V2(m.pos.x - pos.x, m.pos.z - pos.z)
            if simd_length_squared(d) < 13 * 13 && abs(m.pos.y - pos.y) < 8 { return true }
        }
        return false
    }
}

extension Game {
    // Guns and ammo from a fallen soldier; deck guns burst into smoke and scrap.
    func soldierDied(_ m: Mob) {
        guard m.kind.steelhold else { return }
        repSoldierKilled(m)                                            // O3: the faction remembers (FactionRep.swift)
        let at = m.pos + V3(0, 0.6, 0)
        if m.kind == .deckGun {
            particles.explosion(at: m.pos + V3(0, 1, 0), power: 3)
            sfx(.explode, 1.2, at: at)
            NavalGuns.wreck(m, self)                                    // P102: a wreck where it stood
            return
        }
        m.troopLoot(self)                                              // the plate it still wore (TroopClasses.swift)
        BountyHunters.loot(self, m, at: at)                            // R21: a bounty hunter's poster and purse
        // P206 (Oct 13 18:42, "I never found the key to unlock the computer on the second floor"): a Greywall base's
        // officer carries its code book, which opens the keep's map table without taking the base.
        if m.factionValue == .greywall && m.kind == .soldierOfficer && m.leash != nil && Items.has("greywall_codebook") {
            drops.spawn(ItemStack(Items.id("greywall_codebook"), 1), at: at)
        }
        let b = m.soldierBrain
        guard b.gun >= 0, b.gun < Guns.all.count else { return }
        let gs = Guns.all[b.gun]
        let looting = m.killedByPlayer ? Float(m.lootingLevel) : 0
        if Items.has(gs.ammo) { drops.spawn(ItemStack(Items.id(gs.ammo), Rand.int(in: gs.mag <= 6 ? 1...3 : 4...12)), at: at) }
        if m.killedByPlayer && Rand.float(in: 0..<1) < 0.25 + 0.05 * looting && Items.has(gs.key) {
            var s = ItemStack(Items.id(gs.key), 1)
            s.damage = Rand.int(in: gs.durability / 4...gs.durability * 3 / 4)
            s.tag = max(0, b.mag)
            s.grade = GunGrade.roll(GunGrade.soldierWeights[Int(m.troop)] ?? [74, 20, 5, 1], Rand.float(in: 0..<1), Rand.float(in: 0..<1))   // T7
            drops.spawn(s, at: at)
        }
    }

    func writeSoldierLasers(_ wr: inout EntityWriter, eye: V3) {
        for m in mobs.of(.soldierMarksman) {
            guard let b = m.brain, b.aimTime > 0 else { continue }
            let k = min(1, b.aimTime / 1.1)
            let from = SoldierRig.muzzleWorld(m)
            if m.faction == Faction.ashguard.rawValue && b.gun != Guns.sniper {
                // The scope's glint: a short bright flare at the sight, pulsing (G5), not a laser.
                let d = simd_normalize(player.eye - from), side = simd_normalize(simd_cross(d, V3(0, 1, 0))) * 0.35 * (0.6 + 0.4 * sinf(b.aimTime * 18))
                Armory.streak(&wr, eye, from - side, from + side, 0.05 + 0.05 * k, V4(3.2, 3.0, 2.4, 0.9))
                Armory.streak(&wr, eye, from - V3(0, 0.25, 0), from + V3(0, 0.25, 0), 0.04 + 0.04 * k, V4(3.2, 3.0, 2.4, 0.9))
                continue
            }
            Armory.streak(&wr, eye, from, player.eye - V3(0, 0.3, 0), 0.012 + 0.012 * k, V4(2.6, 0.15, 0.1, 0.5 + 0.5 * k))
        }
    }
}

// MARK: Models

// The jointed Capital uniform models and their stances (SoldierRig.swift).
func soldierParts(_ m: Mob, swing: Float) -> [Part] { SoldierRig.build(m).parts }

// The twin 42 cm heavy-gun turret, true to scale (1 block = 1 m; parts in 1/16 block). An original model after
// WWII battleship twin turrets (the H-class 42 cm design, a scaled-up Bismarck-type turret): a long flat-roofed
// gunhouse with an inclined face plate and chamfered front corners, a rear overhang, rangefinder hoods on both
// flanks, roof periscope hoods, two 20 m barrels (L/48) 4.5 m apart through armoured gun ports, on a barbette
// ring (the barbette itself is built in blocks under it). Origin: the barbette top centre; the guns face -Z.
enum HeavyTurret {
    static let trunnionY: Float = 3                 // gun trunnions above the barbette top (blocks)
    static let trunnionZ: Float = -6                // ... and ahead of the turret centre
    static let barrel: Float = 21                   // trunnion to muzzle
    static let spacing: Float = 2.25                // half the distance between the barrels
    static let speed: Float = 260, gravity: Float = 3  // flat direct fire: ~2 m of drop at 220 m (Quest round 4)
    static let pitchMin: Float = -0.09, pitchMax: Float = 0.52     // -5 to +30 degrees
    static let traverse: Float = 0.2                // radians per second
    static let reload: Float = 9
    static let range: Float = 220                   // once provoked
    static let guardRange: Float = 72               // unprovoked: the citadel's grounds
    static let power: Float = 2.4                   // TNT-like burst, about a 3-block crater
    // Manned by the player (P70, playtest 09:19: "this naval gun needs to do way more damage", on a crawler and a
    // citadel tower): a far bigger burst that bites through armoured stone (blocks count at most `mannedBreach` blast
    // resistance: Capital stone is 9), and a ship hull hit tears like a power-11 charge.
    static let mannedPower: Float = 5, mannedBreach: Float = 3, mannedShipPower: Float = 11

    // Two calibres (T6, Greywall's shore bases): the heavy gun, and a light quick-firer (deck_gun variant 9) built at
    // 0.4 scale that fires small shells four times as often and turns four times as fast.
    static let lightVariant = 9
    // P210 (Oct 13 18:46, "the tower guns sit off their towers and are far too big for the base"): Greywall's light
    // guns are smaller still (0.26: a 3.3-block gunhouse with 5.5-block barrels), sized for a 7-block tower roof and
    // the wall walk; every Greywall tower carries one of those instead of the 13-block battleship turret.
    static func scale(_ m: Mob) -> Float {
        guard m.kind == .deckGun && m.variant == lightVariant else { return 1 }
        return m.factionValue == .greywall ? 0.26 : 0.4
    }
    static func muzzle(_ m: Mob, _ sx: Float) -> V3 {
        let p = m.brain?.pitch ?? 0
        let k = scale(m)
        let fwd = V3(-sinf(m.yaw) * cosf(p), sinf(p), -cosf(m.yaw) * cosf(p))
        let side = V3(cosf(m.yaw), 0, -sinf(m.yaw))
        let flat = V3(-sinf(m.yaw), 0, -cosf(m.yaw))
        let trunnion = m.pos + V3(0, trunnionY * k, 0) + flat * (-trunnionZ * k) + side * (sx * spacing * k)
        return trunnion + fwd * (barrel * k)
    }
    // A muzzle flash at one barrel: a glow, a light and a smoke cloud.
    static func flash(_ g: Game, _ muzzle: V3, _ fwd: V3, smoke: Int) {
        for _ in 0..<smoke { g.particles.smoke(at: muzzle + fwd * Rand.float(in: 0...2), dark: false) }
        g.particles.add(Particle(pos: muzzle, vel: fwd, life: 0.08, maxLife: 0.08, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1,
                                 size: 0.5, gravity: 0, color: V3(2.6, 1.8, 0.7), collide: false, glow: true))
        g.addFlash(at: muzzle + fwd * 0.5, color: V3(6, 4, 2), radius: 10, life: 0.1)
    }
    // A heavy shell: bursts like TNT where it lands, breaking blocks and hurting everything near.
    static func arm(_ s: inout Slug) {
        s.power = power
        s.breaks = true
    }
}

// P70 (playtest 09:19, "let's not just copy and paste the same naval gun"): each gun has one of four looks, from its
// faction and where it stands: the Capital's three (the twin-gun turret with rangefinder hoods, a taller monitor turret
// with a roof rangefinder bar and an anti-air mount, an open casemate with a sloped shield and an exposed breech deck)
// and Greywall's own (a low faceted slate turret with a sensor mast, hazard bands and muzzle-braked barrels). The
// barrels, their pivots and muzzles are the same in every look (HeavyTurret.muzzle).
enum DeckGunLook: Int { case turret = 0, monitor, casemate, greywall }

func deckGunLook(_ m: Mob) -> DeckGunLook {
    if m.factionValue == .greywall { return .greywall }
    if m.variant == 0 { m.variant = 1 + Int(hashf(Int(floor(m.pos.x)), Int(floor(m.pos.z)), 7070, 0xDEC) * 2.999) }
    return DeckGunLook(rawValue: (m.variant - 1) % 3) ?? .turret
}

func deckGunParts(_ m: Mob) -> [Part] {
    let look = deckGunLook(m)
    var grey = V3(0.56, 0.58, 0.6), dark = V3(0.2, 0.21, 0.23), mid = V3(0.42, 0.44, 0.47), deck = V3(0.32, 0.33, 0.35)
    if look == .greywall { grey = V3(0.33, 0.37, 0.41); mid = V3(0.25, 0.28, 0.31); dark = V3(0.12, 0.13, 0.15); deck = V3(0.22, 0.24, 0.26) }
    if look == .casemate { grey = V3(0.5, 0.52, 0.47); mid = V3(0.38, 0.4, 0.36) }      // (field drab)
    // P102: a hurt gun's plate blackens (smoking, then burning: NavalGuns.state) and its right barrel droops.
    let hurt = NavalGuns.state(m)
    if hurt > 0 { let f: Float = hurt == 2 ? 0.5 : 0.78; grey *= f; mid *= f; deck *= f }
    let hazard = V3(0.85, 0.66, 0.12)
    let pitch0 = m.brain?.pitch ?? 0
    var pitch = pitch0
    let charge = m.brain?.charge ?? 0
    let kick0 = (m.brain?.kick ?? 0) * 19               // 1.2 m recoil after a salvo
    let kickSide = m.brain?.kickSide ?? 0
    let tz: Float = HeavyTurret.trunnionZ * 16, ty: Float = HeavyTurret.trunnionY * 16
    var p: [Part] = [
        // Barbette ring skirt and the turret's rotating base.
        box(-100, -6, -100, 200, 8, 200, deck),
        box(-104, 2, -96, 208, 6, 230, dark),
    ]
    switch look {
    case .turret:
        p += [
            // Gunhouse: the main armoured box, roof, rear overhang.
            box(-108, 8, -96, 216, 72, 236, grey),
            box(-104, 80, -100, 208, 8, 236, mid),
            box(-100, 20, 140, 200, 56, 20, grey * 0.94),
            // The face plate leaning back in three steps, narrower than the flanks (chamfered front corners).
            box(-92, 8, -124, 184, 32, 28, grey * 0.97), box(-96, 40, -114, 192, 24, 18, grey * 0.97), box(-100, 64, -104, 200, 16, 8, grey * 0.97),
            // Rangefinder hoods on both flanks at the rear, and their arms.
            box(-140, 52, 80, 32, 18, 40, mid), box(108, 52, 80, 32, 18, 40, mid),
            box(-144, 56, 84, 6, 10, 32, dark), box(138, 56, 84, 6, 10, 32, dark),
            // Roof periscope hoods and the commander's cupola.
            box(-60, 88, -40, 18, 8, 22, mid), box(42, 88, -40, 18, 8, 22, mid), box(-14, 88, 60, 28, 12, 28, mid),
            box(-12, 96, 58, 24, 2, 4, V3(0.1, 0.12, 0.14)),
        ]
    case .monitor:
        p += [
            // A taller, narrower gunhouse with a flat face and a stepped back.
            box(-96, 8, -100, 192, 80, 220, grey),
            box(-92, 88, -96, 184, 8, 212, mid),
            box(-90, 8, -116, 180, 64, 16, grey * 0.96),
            box(-84, 20, 120, 168, 60, 24, grey * 0.92),
            // The rangefinder bar right across the roof, its two lens hoods past the flanks.
            // (both kept below the gunner's eye forward and behind where the gunner stands: Turrets.tick)
            box(-150, 96, -84, 300, 10, 16, mid), box(-160, 94, -86, 12, 14, 20, dark), box(148, 94, -86, 12, 14, 20, dark),
            // An anti-air mount at the back of the roof: a ring, a small twin gun pointing up, a shield.
            box(-26, 96, 66, 52, 6, 46, dark), box(-14, 102, 74, 28, 14, 30, mid),
            box(-10, 116, 70, 4, 24, 4, dark), box(6, 116, 70, 4, 24, 4, dark), box(-22, 102, 62, 44, 14, 4, grey * 0.9),
            // Ladder rungs up the back.
            box(-8, 24, 144, 16, 3, 3, dark), box(-8, 44, 144, 16, 3, 3, dark), box(-8, 64, 144, 16, 3, 3, dark),
        ]
    case .casemate:
        p += [
            // A sloped shield over the guns and an open breech deck behind it, a rail round the back.
            box(-110, 8, -110, 220, 40, 30, grey), box(-104, 48, -100, 208, 22, 24, grey * 0.96), box(-96, 70, -90, 192, 12, 18, grey * 0.92),
            box(-120, 8, -80, 20, 56, 120, grey * 0.95), box(100, 8, -80, 20, 56, 120, grey * 0.95),
            box(-110, 8, -80, 220, 10, 220, deck * 1.1),
            box(-112, 18, 136, 224, 4, 4, dark), box(-112, 18, -80, 4, 4, 220, dark), box(108, 18, -80, 4, 4, 220, dark),
            box(-112, 8, 136, 4, 12, 4, dark), box(108, 8, 136, 4, 12, 4, dark),
            // Shell racks and a loader's seat on the open deck.
            box(-90, 18, 80, 40, 24, 30, V3(0.3, 0.27, 0.2)), box(50, 18, 80, 40, 24, 30, V3(0.3, 0.27, 0.2)),
            box(-10, 18, 60, 20, 14, 20, dark),
        ]
    case .greywall:
        p += [
            // A low faceted gunhouse: four plates sloping back to a flat roof, panel seams, a slab rear.
            box(-110, 8, -90, 220, 52, 226, grey),
            box(-100, 60, -76, 200, 14, 200, grey * 0.95), box(-86, 74, -60, 172, 8, 170, mid),
            box(-96, 8, -120, 192, 22, 30, grey * 0.98), box(-90, 30, -108, 180, 18, 20, grey * 0.96), box(-84, 48, -94, 168, 12, 16, grey * 0.94),
            box(-111, 34, -90, 222, 2, 226, dark), box(-1, 60, -76, 2, 14, 200, dark),
            box(-106, 12, 136, 212, 44, 14, mid),
            // Hazard bands at the barbette and on the rear slab.
            box(-105, 4, -97, 210, 3, 232, hazard), box(-106, 46, 150, 212, 4, 1, hazard),
            // The sensor mast with its dish and a beacon.
            box(60, 82, 60, 6, 70, 6, dark), box(44, 150, 54, 38, 20, 4, mid), box(61, 152, 50, 4, 4, 4, V3(1.4, 0.3, 0.2)),
            // A sighting block offset to the left.
            box(-70, 82, 10, 34, 16, 30, mid), box(-66, 88, 8, 26, 6, 2, V3(0.2, 0.55, 0.75)),
        ]
    }
    for x: Float in [-36, 36] {
        let pv = V3(x, ty, tz)
        pitch = hurt == 2 && x > 0 ? min(pitch0, -0.14) : pitch0
        let kick = kickSide == 0 || (kickSide < 0) == (x < 0) ? kick0 : 0      // (P101: one barrel at a time when manned)
        // Gun port mantlet (moves with the gun), the barrel in three tapering sections, a muzzle ring.
        p.append(Part(mn: V3(x - 22, ty - 22, tz - 30), mx: V3(x + 22, ty + 22, tz + 4), pivot: pv, rotX: pitch, color: dark))
        p.append(Part(mn: V3(x - 13, ty - 13, tz - 140 + kick), mx: V3(x + 13, ty + 13, tz - 30 + kick), pivot: pv, rotX: pitch, color: mid))
        p.append(Part(mn: V3(x - 10.5, ty - 10.5, tz - 260 + kick), mx: V3(x + 10.5, ty + 10.5, tz - 140 + kick), pivot: pv, rotX: pitch, color: mid * 0.95))
        p.append(Part(mn: V3(x - 8.5, ty - 8.5, tz - 330 + kick), mx: V3(x + 8.5, ty + 8.5, tz - 260 + kick), pivot: pv, rotX: pitch, color: mid * 0.9))
        if look == .greywall {
            // A fume extractor midway and a slotted muzzle brake.
            p.append(Part(mn: V3(x - 14, ty - 14, tz - 200 + kick), mx: V3(x + 14, ty + 14, tz - 170 + kick), pivot: pv, rotX: pitch, color: dark))
            p.append(Part(mn: V3(x - 14, ty - 9, tz - 344 + kick), mx: V3(x + 14, ty + 9, tz - 326 + kick), pivot: pv, rotX: pitch, color: dark))
            p.append(Part(mn: V3(x - 14.5, ty - 3, tz - 340 + kick), mx: V3(x + 14.5, ty + 3, tz - 336 + kick), pivot: pv, rotX: pitch, color: V3(0.03, 0.03, 0.04)))
        } else {
            p.append(Part(mn: V3(x - 10, ty - 10, tz - 340 + kick), mx: V3(x + 10, ty + 10, tz - 330 + kick), pivot: pv, rotX: pitch, color: dark))
        }
        if look == .casemate {
            // The recoil cylinders above each barrel.
            p.append(Part(mn: V3(x - 6, ty + 13, tz - 110 + kick), mx: V3(x + 6, ty + 21, tz - 20 + kick), pivot: pv, rotX: pitch, color: dark))
        }
        p.append(Part(mn: V3(x - 4, ty - 4, tz - 340.5 + kick), mx: V3(x + 4, ty + 4, tz - 339.5 + kick), pivot: pv, rotX: pitch, color: V3(0.03, 0.03, 0.04)))
        if charge > 0 {
            p.append(Part(mn: V3(x - 5, ty - 5, tz - 341), mx: V3(x + 5, ty + 5, tz - 340.6), pivot: pv, rotX: pitch, color: V3(1.5 + charge, 0.8, 0.2)))
        }
    }
    // A light coastal gun (T6) is the same gun built at 0.4 scale.
    let k = HeavyTurret.scale(m)
    if k != 1 { for i in p.indices { p[i].mn *= k; p[i].mx *= k; p[i].pivot *= k } }
    return p
}

// The navies' and the Legion's own crews (Oct 11 playtest, G13: "ships should not carry Capital soldiers"): a soldier
// crewing a vessel of another faction goes by that faction's ranks (and wears its livery, SoldierRig.Livery), by rank
// (Soldier.rank: recruit, trooper, marksman, ironclad, officer, crew). The Ashguard renames its own (AshUnits.swift).
extension Mob {
    static let crewNames: [Faction: [String]] = [
        .meridian: ["Meridian Rating", "Meridian Marine", "Meridian Gunner", "Aegis Marine", "Meridian Lieutenant", "Meridian Helmsman"],
        .stormwarden: ["Stormwarden Deckhand", "Stormwarden Boarder", "Stormwarden Gunner", "Stormwarden Breacher", "Stormwarden Mate", "Stormwarden Helmsman"],
        .greywall: ["Greywall Sentry", "Greywall Rifleman", "Greywall Marksman", "Greywall Heavy", "Greywall Officer", "Greywall Crewman"],
        .ironback: ["Ironback Legionary", "Ironback Vanguard", "Ironback Sharpshooter", "Ironback Bulwark", "Ironback Centurion", "Ironback Driver"],
    ]

    func crewSetup() {
        guard !kind.ash, faction != Faction.ashguard.rawValue, let r = Soldier.rank(kind) else { return }
        if let names = Mob.crewNames[factionValue] { spec.name = names[r] } else { spec.name = kind.spec.name }
    }
}

extension Game {
    // R23 (Oct 13 evening, "factions kept apart"): whether `p` is in, or within `pad` of, another faction's base: a
    // Capital citadel (not cleared) for anyone but the Capital, a Greywall base (not one the player took) for anyone but
    // Greywall. Troops of `f` are never set down there (ShipManager.callDropship, front battles), so a base's garrison
    // is never mixed with a rival's dropship squad standing among it.
    func foreignBase(_ p: V3, for f: Faction, pad: Float = 24) -> Bool {
        let b = bases
        if f != .steelhold {
            let half = Float(CapitalBase.A) + pad
            for r in b.records.values where r.cleared != true && abs(p.x - Float(r.cx)) < half && abs(p.z - Float(r.cz)) < half { return true }
        }
        if f != .greywall {
            let st = b.greywall
            for (key, s) in st.sites where !st.taken.contains(key) && Greywall.inside(s, p, pad: pad) { return true }
        }
        return false
    }
}
