import Foundation
import simd

// The Ashguard's units (task 22): Cinder tanks, half-tracks, field guns and supply trucks (vehicle mobs drawn from
// parts), their soldiers (Steelhold ranks in Ashguard black, faction .ashguard) and the Ash Marshal (an officer-rank
// boss). Everything is black with red markings; no real-world insignia. Sites place them by name (AshSites.swift):
// "kind[:fuel][@ash][^heading]".

extension MobKind {
    var ash: Bool { rawValue >= MobKind.ashTank.rawValue && rawValue <= MobKind.ashMarshal.rawValue }
    var ashVehicle: Bool { self == .ashTank || self == .ashHalftrack || self == .ashArtillery || self == .ashTruck }
    var ashArmoured: Bool { ashVehicle }

    var ashSpec: Spec {
        switch self {
        case .ashTank:
            return Spec(name: "Cinder Tank", halfW: 1.7, height: 2.6, health: 180, speed: 2.4, behavior: .monster,
                        drops: [("iron_ingot", 3, 7), ("gunpowder", 2, 5), ("rocket_ammo", 0, 2)], xp: 60, call: .gun(12), fireImmune: true)
        case .ashHalftrack:
            return Spec(name: "Ashguard Half-track", halfW: 1.3, height: 2.3, health: 110, speed: 4.4, behavior: .monster,
                        drops: [("iron_ingot", 2, 4), ("rifle_rounds", 4, 12)], xp: 30, call: .gun(12), fireImmune: true)
        case .ashArtillery:
            return Spec(name: "Ashguard Field Gun", halfW: 1.1, height: 1.8, health: 70, speed: 0, behavior: .monster,
                        drops: [("iron_ingot", 1, 3), ("gunpowder", 2, 6)], xp: 25, call: .gun(12), fireImmune: true)
        case .ashTruck:
            return Spec(name: "Ashguard Truck", halfW: 1.2, height: 2.4, health: 40, speed: 0, behavior: .monster,
                        drops: [("iron_ingot", 0, 2), ("bread", 1, 4), ("rifle_rounds", 2, 8)], xp: 8, call: .gun(12))
        default:
            return Spec(name: "The Ash Marshal", halfW: 0.38, height: 2.1, health: 220, speed: 3.0, behavior: .monster,
                        drops: [("gold_ingot", 4, 9), ("diamond", 2, 5), ("heavy_rounds", 4, 10), ("arc_cell", 2, 4)], xp: 250,
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
        default: return (8, 2)
        }
    }

    // Joins the Ashguard: faction, names, the Marshal's size. Deep-down soldiers are tougher (power, like the Deep's
    // monsters).
    func ashSetup() {
        faction = Faction.ashguard.rawValue
        if kind == .ashMarshal { scale = 1.12; return }
        if !kind.ash, let r = Soldier.rank(kind) {
            spec.name = Mob.ashNames[r]
            power = 1.4
        }
    }

    // A structure mob by name: "kind[:fuel][@ash][^heading]" (AshSites.unit), or a plain kind key.
    static func structureMob(_ name: String, at p: V3) -> Mob? {
        var n = Substring(name)
        var heading: Float?
        if let i = n.firstIndex(of: "^") { heading = Float(n[n.index(after: i)...]); n = n[..<i] }
        var ash = false
        if n.hasSuffix("@ash") { ash = true; n = n.dropLast(4) }
        var tag = ""
        if let i = n.firstIndex(of: ":") { tag = String(n[n.index(after: i)...]); n = n[..<i] }
        guard let k0 = MobKind.named(String(n)) else { return nil }
        let m = Mob(Soldier.garrison(k0, at: p), at: p)
        m.persistent = true
        if ash { m.ashSetup() }
        if let h = heading { m.yaw = -h * .pi / 180; m.soldierBrain.turret = m.yaw }
        if tag == "fuel" { m.variant = 1 }
        if k0 == .villager && !tag.isEmpty { Townsfolk.setup(m, tag: tag, game: nil) }
        return m
    }

    var ashTurretY: Float {
        switch kind {
        case .ashTank: return 33.5 / 16
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
        let sp = soldierAI(dt, g, dist: dist, canTarget: canTarget)
        if canTarget, let b = brain, b.sees, b.seenAgo < 0.1 { ashSpotted(g) }
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
        var i = 0
        while i < g.ashStrikes.count {
            g.ashStrikes[i].t -= dt
            let s = g.ashStrikes[i]
            if s.t <= 0 {
                var shell = Slug(pos: s.at + V3(0, 26, 0), vel: V3(0, -55, 0), kind: .shell, damage: 0, fromPlayer: false,
                                 shooter: ObjectIdentifier(self), by: spec.name, life: 2, gravity: 9)
                shell.power = 1.5
                g.arms.spawn(shell)
                g.ashStrikes.remove(at: i)
                continue
            }
            if Rand.float(in: 0..<1) < dt * 14 {
                g.particles.add(Particle(pos: s.at + V3(Rand.float(in: -0.3...0.3), 0.2, Rand.float(in: -0.3...0.3)), vel: V3(0, 2.5, 0), life: 0.5,
                                         maxLife: 0.5, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: 0.18, gravity: -1,
                                         color: V3(2.6, 0.3, 0.15), collide: false, glow: true))
            }
            i += 1
        }
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
            let p = g.player.pos
            let lead = V3(g.player.vel.x, 0, g.player.vel.z) * 1.2
            for k in 0..<3 {
                let off = k == 0 ? V3.zero : V3(Rand.float(in: -4...4), 0, Rand.float(in: -4...4))
                g.ashStrikes.append((at: p + lead + off, t: 2 + Float(k) * 0.45))
            }
            g.sfx(.gun(10), 1.2, at: p)
            g.onToast?("The Ash Marshal marks your position: move!")
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
                if w.block(x, y, z) == AIR && w.block(x, y + 1, z) == AIR && Blocks.collide[Int(w.block(x, y - 1, z))] {
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
        g.onToast?("The Ash Marshal calls his guard")
    }

    // MARK: Vehicles

    func ashVehicleAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        let b = soldierBrain
        faceGoal = nil
        strafe = 0
        b.reload -= dt
        b.shotTimer -= dt
        b.kick = max(0, b.kick - dt * 2.5)
        // Burning wrecks-to-be: smoke under 40% health.
        if health * 5 < spec.health * 2 && Rand.float(in: 0..<1) < dt * 5 { g.particles.smoke(at: pos + V3(0, height * 0.8, 0)) }
        if kind == .ashTruck { return 0 }
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
        let sight: Float = kind == .ashArtillery ? 48 : (kind == .ashTank ? 72 : 56)
        b.losTimer -= dt
        if b.losTimer <= 0 {
            b.losTimer = 0.35 + Rand.float(in: 0..<0.1)
            b.sees = canTarget && dist < sight && g.world.canSee(pivot + V3(0, 0.7, 0), g.player.eye)
        }
        if b.sees {
            if !aggro { aggro = true; g.sfx(.gun(10), 1.1, at: pivot) }
            b.lastSeen = g.player.eye - V3(0, 0.5, 0)
            b.seenAgo = 0
            ashSpotted(g)
        } else {
            b.seenAgo += dt
            if aggro && b.seenAgo > 45 { aggro = false }
        }
        switch kind {
        case .ashArtillery: ashArtillery(dt, g, pivot); return 0
        case .ashHalftrack: return ashHalftrack(dt, g, pivot, dist)
        default: return ashTank(dt, g, pivot, dist)
        }
    }

    // Turret / gun laying toward a world yaw and pitch at the unit's traverse rates.
    private func ashSlew(_ dt: Float, toYaw want: Float, pitch: Float) {
        let b = soldierBrain
        let rate: Float = kind == .ashHalftrack ? 2.6 : (kind == .ashArtillery ? 0.6 : 0.9)
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

    private func ashCannon(_ g: Game, power: Float, speed v: Float, gravity gr: Float, len: Float, spread: Float) {
        let (muzzle, fwd) = ashMuzzle(len)
        var s = Slug(pos: muzzle, vel: Guns.scatter(fwd, spread) * v, kind: .shell, damage: 0, fromPlayer: false,
                     shooter: ObjectIdentifier(self), by: spec.name, life: 6, gravity: gr)
        s.power = power
        g.arms.spawn(s)
        for _ in 0..<4 { g.particles.smoke(at: muzzle + fwd * Rand.float(in: 0...1), dark: false) }
        g.addFlash(at: muzzle + fwd * 0.4, color: V3(6, 3.5, 1.6), radius: 7, life: 0.08)
        g.sfx(.gun(9), kind == .ashTank ? 1.3 : 1.1, at: muzzle)
        soldierBrain.kick = 1
    }

    // Cinder tank: closes to 12-26 blocks, turret on the target, main gun every few seconds, a coaxial MG in bursts.
    private func ashTank(_ dt: Float, _ g: Game, _ pivot: V3, _ dist: Float) -> Float {
        let b = soldierBrain
        guard aggro, let t = b.lastSeen, b.seenAgo < 10 else { return 0 }
        let toT = t - pivot
        let flat = simd_length(V2(toT.x, toT.z))
        let wantYaw = atan2f(-toT.x, -toT.z)
        let v: Float = 70, gr: Float = 9
        let pitch = max(-0.14, min(0.35, ashPitch(pivot, t, v: v, gr: gr, high: false) ?? 0.1))
        ashSlew(dt, toYaw: wantYaw, pitch: pitch)
        let off = ashTurretOff(wantYaw)
        // Laid on: a 0.6 s tell (the breech clank and a glow at the muzzle) before the main gun fires.
        if b.sees && off < 0.05 && abs(pitch - b.pitch) < 0.04 && b.reload <= 0 && flat > 5 {
            if b.charge == 0 { g.sfx(.gun(12), 1, at: pivot) }
            b.charge += dt
            if b.charge >= 0.6 {
                b.charge = 0
                b.reload = [10, 9, 7.5, 5.5][max(0, min(3, g.difficulty))]
                ashCannon(g, power: 1.3, speed: v, gravity: gr, len: 5.2, spread: 0.02)
            }
        } else if b.charge > 0 && (!b.sees || off > 0.2) {
            b.charge = 0
        }
        ashMG(dt, g, t, dist: flat, off: off, len: 3.4, range: 44)
        return ashDrive(dt, g, wantYaw: wantYaw, flat: flat, near: 12, far: 26, circle: false)
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
        return ashDrive(dt, g, wantYaw: wantYaw, flat: flat, near: 12, far: 24, circle: true)
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
    private func ashDrive(_ dt: Float, _ g: Game, wantYaw: Float, flat: Float, near: Float, far: Float, circle: Bool) -> Float {
        var goal = wantYaw
        var speed: Float = 0
        if flat > far { speed = spec.speed }
        else if flat < near { speed = -spec.speed * 0.6 }
        else if circle { goal = wantYaw + .pi / 2 * (soldierBrain.strafeDir); speed = spec.speed * 0.7 }
        var d = goal - yaw
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        let turn: Float = kind == .ashHalftrack ? 1.4 : 0.7
        yaw += max(-turn * dt, min(turn * dt, d))
        if abs(d) > 0.6 { speed *= 0.3 }
        if speed != 0 {
            let w = g.world
            let ahead = pos + forward * ((halfW + 1) * (speed > 0 ? 1 : -1))
            let x = Int(floor(ahead.x)), z = Int(floor(ahead.z)), y = Int(floor(pos.y))
            let floorBlk = w.block(x, y - 1, z), lower = w.block(x, y - 2, z)
            let drop = !Blocks.collide[Int(floorBlk)] && !Blocks.collide[Int(lower)]
            if drop || Blocks.isLiquid(floorBlk) || Blocks.isLiquid(w.block(x, y, z)) {
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
        let pitch = hi > 1.25 ? lo : hi
        let toT = t - pivot
        let wantYaw = atan2f(-toT.x, -toT.z)
        ashSlew(dt, toYaw: wantYaw, pitch: pitch)
        if ashTurretOff(wantYaw) < 0.03 && abs(pitch - b.pitch) < 0.03 && b.reload <= 0 {
            b.charge += dt
            if b.charge > 0.7 {
                b.charge = 0
                b.reload = g.difficulty >= 3 ? 6 : 8
                ashCannon(g, power: 1.5, speed: v, gravity: gr, len: 3.9, spread: 0.012)
            }
        }
    }
}

// MARK: Models (1/16 block, origin at the feet, facing -Z; hull yaw is the mob's, turrets turn by brain.turret)

func ashVehicleParts(_ m: Mob) -> [Part] {
    let black = V3(0.075, 0.075, 0.082), plate = V3(0.11, 0.11, 0.12), dark = V3(0.035, 0.035, 0.04)
    let red = V3(0.62, 0.06, 0.04), steel = V3(0.2, 0.2, 0.22), glow = V3(2.6, 0.25, 0.12)
    let b = m.brain
    let ty = (b?.turret ?? m.yaw) - m.yaw
    let pitch = b?.pitch ?? 0
    let kick = (b?.kick ?? 0) * 5
    var p: [Part] = []
    func turned(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, pivot: V3, gun: Bool = false, pat: Float = 7) {
        var q = box(x, y, z, w, h, d, c, pat)
        q.pivot = pivot
        q.rotY = ty
        if gun { q.rotX = pitch }
        p.append(q)
    }
    switch m.kind {
    case .ashTank:
        // Tracks with road wheels and fenders, a low hull with a sloped glacis, a cast turret with a long gun.
        for s: Float in [-1, 1] {
            let x0: Float = s < 0 ? -27 : 17
            p.append(box(x0, 0, -44, 10, 16, 88, dark, 4))
            for k in 0..<5 { p.append(box(s < 0 ? -27.6 : 26.6, 3, Float(k) * 16 - 37, 1, 10, 10, steel, 8)) }
            p.append(box(s < 0 ? -28 : 16, 16, -46, 12, 2, 92, black, 7))
            p.append(box(s < 0 ? -20.5 : 17.5, 20, 42, 3, 2, 0.6, glow, 9))          // tail lights
        }
        p.append(box(-17, 6, -42, 34, 14, 84, black, 7))
        p.append(box(-24, 18, -36, 48, 8, 76, plate, 7))
        p.append(box(-22, 12, -46, 44, 8, 10, plate, 7))                               // glacis
        p.append(box(-24.4, 21, -8, 48.8, 2, 22, red))                                 // ember band on both flanks
        p.append(box(-6, 15, -46.6, 12, 4, 0.8, red))                                  // front plate marking
        for x: Float in [-16, -6, 4] { p.append(box(x, 26, 24, 8, 1, 12, dark)) }     // engine grilles
        p.append(box(-15, 20, 40, 4, 7, 4, steel, 8)); p.append(box(11, 20, 40, 4, 7, 4, steel, 8))
        let pv = V3(0, 33.5, -2)
        turned(-15, 26, -18, 30, 14, 32, black, pivot: pv)
        turned(-13, 28, 14, 26, 10, 8, plate, pivot: pv)                               // bustle
        turned(-15.4, 35, -12, 30.8, 2, 22, red, pivot: pv, pat: 0)                    // turret band
        turned(-11, 40, 2, 9, 5, 9, plate, pivot: pv)                                  // cupola
        turned(-10, 45, 3, 7, 1, 7, dark, pivot: pv)
        turned(9, 40, 10, 0.6, 24, 0.6, steel, pivot: pv)                              // antenna
        turned(-7, 29, -23, 14, 9, 6, plate, pivot: pv, gun: true)                     // mantlet
        turned(-1.6, 31.9, -80 + kick, 3.2, 3.2, 58, steel, pivot: pv, gun: true, pat: 8)
        turned(-2.6, 30.9, -86 + kick, 5.2, 5.2, 7, dark, pivot: pv, gun: true, pat: 8)  // muzzle brake
        turned(4, 30, -26, 1.5, 1.5, 4, dark, pivot: pv, gun: true)                    // coaxial MG
        if let c = b?.charge, c > 0 { turned(-1.2, 32.3, -86.6, 2.4, 2.4, 0.5, V3(1.5 + c * 3, 0.5, 0.15), pivot: pv, gun: true, pat: 9) }
    case .ashHalftrack:
        for s: Float in [-1, 1] {
            p.append(box(s < 0 ? -20 : 14, 0, -38, 6, 12, 12, dark, 4))                 // front wheels
            p.append(box(s < 0 ? -20.5 : 19.5, 3, -35, 1, 6, 6, steel, 8))
            p.append(box(s < 0 ? -20 : 12, 0, -6, 8, 11, 40, dark, 4))                  // rear tracks
            p.append(box(s < 0 ? -21 : 14, 12, -40, 7, 2, 16, black, 7))                // fenders
        }
        p.append(box(-12, 10, -46, 24, 12, 20, black, 7))                              // engine hood
        p.append(box(-9, 11, -46.8, 18, 9, 1, dark))                                   // radiator
        p.append(box(-16, 10, -26, 32, 9, 16, black, 7))                               // cab
        p.append(box(-16, 19, -26, 32, 5, 2, plate, 7))
        p.append(box(-13, 19.5, -26.6, 26, 4, 1, V3(0.08, 0.09, 0.1), 11))             // vision slits
        p.append(box(-16, 10, -10, 32, 4, 46, plate, 7))                               // troop bed
        p.append(box(-16, 14, -10, 2, 12, 46, black, 7)); p.append(box(14, 14, -10, 2, 12, 46, black, 7))
        p.append(box(-16, 14, 34, 32, 12, 2, black, 7))
        p.append(box(-16.5, 22, -4, 33, 2, 30, red))
        p.append(box(-19, 14, 35, 3, 2, 0.6, glow, 9)); p.append(box(16, 14, 35, 3, 2, 0.6, glow, 9))
        let pv = V3(0, 30, 8)
        turned(-1, 24, 7, 2, 6, 2, steel, pivot: pv, pat: 8)                           // pintle post
        turned(-6, 27, 4, 12, 8, 1, plate, pivot: pv)                                  // gun shield
        turned(-1, 29, -10, 2, 2.4, 20, steel, pivot: pv, gun: true, pat: 8)
    case .ashArtillery:
        for s: Float in [-1, 1] {
            p.append(box(s < 0 ? -18 : 14, 0, -9, 4, 18, 18, dark, 4))                 // wheels
            p.append(box(s < 0 ? -18.6 : 17.6, 6, -3, 1, 6, 6, steel, 8))
        }
        p.append(box(-14, 7, -2, 28, 3, 4, steel, 8))                                  // axle
        p.append(box(-9, 2, -1, 3, 6, 41, black, 7)); p.append(box(6, 2, -1, 3, 6, 41, black, 7))   // split trails, hinged on the axle
        p.append(box(-11, 0, 38, 22, 4, 3, dark))                                      // spade
        p.append(box(-16, 8, -9, 32, 20, 2, black, 7))                                 // shield
        p.append(box(-16, 23, -9.6, 32, 2, 0.6, red))
        p.append(box(8, 0, 18, 8, 6, 6, plate, 7))                                     // ready rounds
        let pv = V3(0, 14, -2)
        var q = box(-4, 10, -12, 8, 8, 22, plate, 7); q.pivot = pv; q.rotX = pitch; p.append(q)          // cradle
        q = box(-1.6, 12.4, -60 + kick, 3.2, 3.2, 50, steel, 8); q.pivot = pv; q.rotX = pitch; p.append(q)
        q = box(-2.5, 11.5, -64 + kick, 5, 5, 5, dark, 8); q.pivot = pv; q.rotX = pitch; p.append(q)
    default:
        // Supply truck (canvas tilt) or fuel truck (tank with red bands).
        for z: Float in [-36, 10, 24] {
            p.append(box(-17, 0, z - 6, 4, 12, 12, dark, 4)); p.append(box(13, 0, z - 6, 4, 12, 12, dark, 4))
        }
        p.append(box(-12, 6, -42, 24, 4, 82, steel, 8))                                // chassis
        p.append(box(-12, 8, -50, 24, 11, 9, black, 7))                                // hood
        p.append(box(-14, 8, -42, 28, 18, 16, black, 7))                               // cab
        p.append(box(-12, 19, -42.6, 24, 5, 1, V3(0.08, 0.09, 0.1), 11))
        p.append(box(-9, 9, -50.8, 18, 8, 1, dark))
        if m.variant == 1 {
            p.append(box(-12, 10, -24, 24, 20, 60, black, 7))
            p.append(box(-12.4, 22, -20, 24.8, 2, 52, red)); p.append(box(-12.4, 14, -20, 24.8, 2, 52, red))
            p.append(box(-4, 14, 36.2, 8, 8, 0.6, red))
        } else {
            p.append(box(-14, 10, -24, 28, 4, 62, plate, 7))
            p.append(box(-14, 14, -24, 28, 22, 60, V3(0.09, 0.09, 0.1), 6))
            p.append(box(-14.4, 28, -18, 28.8, 3, 48, red, 6))
        }
        p.append(box(-14, 10, 38, 3, 2, 0.6, glow, 9)); p.append(box(11, 10, 38, 3, 2, 0.6, glow, 9))
    }
    return p
}
