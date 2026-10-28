import Foundation
import simd

// Hired companions (backlog O2). Townsfolk and calm Capital soldiers can be taken on as gunhands who follow the player
// and fight beside them:
//   hiring     sneak and use a townsperson (not a shopkeeper, banker, lawman, child or elder) to hire them for $30, or
//              a Capital soldier who isn't fighting you for $60. A townsperson takes up a carbine. At most three.
//   following  a companion keeps within a few blocks of the player (it jogs to catch up, and past 48 blocks it simply
//              arrives), and fires on any hostile within 20 blocks it can see: monsters and soldiers hunting the
//              player. Its rounds count as the player's (the kill and its loot are yours; they never hit you).
//   gear       use a companion holding a troop class armour piece (Regular, Spec Ops, Hannibal: TroopClasses.swift)
//              and they wear it, with the life the piece had; use one holding a gun (not a launcher) and they carry
//              it. Hand them armour of another class and they change into it.
//   parting    sneak and use your companion to let them go; they head home.
// Saved with the mob ("hired"); the name stays on its customName.
enum Companions {
    static let max = 3
    static let townsfolkFee = 3000, soldierFee = 6000         // cents
    static let follow: Float = 4, catchUp: Float = 10, arrive: Float = 48
    static let sight: Float = 20
    static let hireable: Set<String> = ["", "farmer", "craftsman", "worker", "camper", "miner"]
}

extension Game {
    var companions: [Mob] { mobs.mobs.filter { $0.hired && $0.health > 0 } }

    // Use on a mob (Farming.useItemOnMob, and with a gun in hand from Game.interact): hire, gear, or part.
    func companionUse(_ m: Mob) -> Bool {
        let sneak = input.shift || player.sneaking
        if m.hired {
            if sneak {
                m.hired = false
                mobs.mobs.removeAll { $0 === m }
                onToast?("\(m.customName ?? "Your companion") heads home.")
                return true
            }
            return companionGear(m)
        }
        guard sneak, !m.baby, survival else { return false }
        let soldier = m.kind == .soldierTrooper || m.kind == .soldierRecruit || m.kind == .soldierMarksman || m.kind == .soldierOfficer
        let fee: Int
        if m.kind == .villager {
            guard let v = m.villager, v.person != nil, v.shop == nil, Companions.hireable.contains(v.role ?? "") else { return false }
            fee = Companions.townsfolkFee
        } else if soldier && m.factionValue == .steelhold && !m.aggro {
            fee = Companions.soldierFee
        } else { return false }
        guard companions.count < Companions.max else { onToast?("You can't lead more than \(Companions.max) companions."); return true }
        guard money >= fee else { onToast?("Hiring them takes \(Money.format(fee)).");  return true }
        money -= fee
        let c = enlist(m)
        sfx(.levelUp, 0.6, at: c.pos)
        onToast?("\(c.customName ?? "They") joins you for \(Money.format(fee)).")
        return true
    }

    // A townsperson or soldier taken on as a companion (hired, or a volunteer: VehicleGunners): the companion it is now.
    @discardableResult
    func enlist(_ m: Mob) -> Mob {
        let name = m.villager?.person ?? m.customName ?? m.spec.name
        let c: Mob
        if m.kind == .villager {
            // A townsperson takes up a carbine and joins as a gunhand (a soldier's body and rig, the person's name).
            c = Mob(.soldierRecruit, at: m.pos)
            c.yaw = m.yaw
            c.variant = Guns.sturmwind                    // P256: a frontier carbine (the Service Rifle is the Capital's)
            mobs.mobs.removeAll { $0 === m }
            mobs.mobs.append(c)
        } else {
            c = m
        }
        c.faction = Faction.none.rawValue
        c.hired = true
        c.persistent = true
        c.aggro = false
        c.leash = nil
        c.crewPost = nil
        c.customName = name
        if c.troop < 0 { c.troop = 0 }
        let b = c.soldierBrain
        b.mag = Guns.all[b.gun].mag
        return c
    }

    // Gear handed over: a troop class armour piece or a gun.
    private func companionGear(_ m: Mob) -> Bool {
        let key = Items.key(held.item)
        let name = m.customName ?? "Your companion"
        for c in TroopClass.allCases {
            for seg in 0..<3 where key == c.item(seg) {
                if m.troopClass != c {
                    // A new class: its other pieces start bare.
                    m.troop = Int8(c.rawValue)
                    m.troopSeg = SIMD3(0, 0, 0)
                }
                let dur = Items.def(held.item).durability
                let frac = dur > 0 ? Float(dur - held.damage) / Float(dur) : 1
                m.troopSeg[seg] = c.segMax[seg] * max(0.05, frac)
                consumeHeld()
                sfx(.armorEquip(0), 0.8, at: m.pos)
                onToast?("\(name) puts on the \(Items.def(Items.id(key)).display).")
                return true
            }
        }
        if let gi = Guns.index(held.item) {
            guard Guns.all[gi].shot != .rocket else { onToast?("\(name) won't fire a launcher this close to you."); return true }
            let b = m.soldierBrain
            b.gun = gi; b.mag = Guns.all[gi].mag; b.reload = 0
            m.variant = gi
            consumeHeld()
            sfx(.gunReload(Guns.all[gi].sound), 0.7, at: m.pos)
            onToast?("\(name) takes the \(Guns.all[gi].name).")
            return true
        }
        onToast?("\(name): \"Lead on.\"")
        return true
    }
}

extension Mob {
    // A companion's whole AI (from soldierAI): follow the player, fire on what threatens them. Returns the walk speed.
    func companionAI(_ dt: Float, _ g: Game) -> Float {
        let b = soldierBrain
        // P478: at the gun of his vehicle (VehicleGunners): the gun is the work; they ride where they stand.
        if VehicleGunners.place(self) { aggro = false; return 0 }
        let gs = Guns.all[max(0, min(Guns.all.count - 1, b.gun))]
        b.clock += dt
        b.aimHold -= dt
        b.recoil = max(0, b.recoil - dt * 7)
        b.shotTimer -= dt
        b.losTimer -= dt
        if b.reload > 0 {
            b.reload -= dt
            if b.reload <= 0 { b.mag = gs.mag }
        }
        aggro = false
        let pp = g.player.pos
        let toP = V2(pp.x - pos.x, pp.z - pos.z)
        let dp = simd_length(toP)
        // Left far behind (a ride, a ship, a fall): they arrive.
        if dp > Companions.arrive || abs(pp.y - pos.y) > 24 {
            let a = Float(ObjectIdentifier(self).hashValue & 7) * 0.8
            pos = pp + V3(cosf(a) * 2, 0.2, sinf(a) * 2)
            vel = .zero
            return 0
        }
        // The nearest threat in sight: a monster, or a soldier hunting the player.
        if b.losTimer <= 0 {
            b.losTimer = 0.25
            var best: Mob?, bd = Companions.sight
            for m in g.mobs.mobs where m !== self && m.health > 0 && !m.hired && m.kind.hostile {
                if Soldier.rank(m.kind) != nil && !m.aggro { continue }
                if m.kind == .creeper && simd_length(m.pos - pp) < 3 { continue }       // (not into a creeper by the player)
                let d = simd_length(m.pos - pos)
                guard d < bd, g.world.canSee(eye, m.pos + V3(0, m.height * 0.6, 0)) else { continue }
                bd = d; best = m
            }
            companionFoe = best
        }
        if let f = companionFoe, f.health > 0, dp < Companions.catchUp {
            let aim = f.pos + V3(0, f.height * 0.6, 0)
            face(aim)
            b.aimHold = 1.2
            let d = aim - eye
            b.pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
            companionFire(g, b, gs, at: aim)
            return dp > Companions.follow * 1.6 ? spec.speed * 0.5 : 0
        }
        companionFoe = nil
        if dp > Companions.follow {
            face(pp)
            return spec.speed * (dp > Companions.catchUp ? 1.3 : 0.9)
        }
        return 0
    }

    private func companionFire(_ g: Game, _ b: SoldierBrain, _ gs: GunSpec, at t: V3) {
        guard b.reload <= 0 else { return }
        if b.mag <= 0 {
            b.reload = gs.reload
            b.reloadTotal = b.reload
            g.sfx(.gunReload(gs.sound), 0.6, at: eye)
            return
        }
        guard b.shotTimer <= 0 else { return }
        let muzzle = SoldierRig.muzzleWorld(self)
        guard g.world.clearShot(muzzle, t) else { return }
        // Never across the player: hold the shot while they stand in the line of fire.
        let dir = simd_normalize(t - muzzle)
        let toP = g.player.eye - V3(0, 0.5, 0) - muzzle
        let along = simd_dot(toP, dir)
        if along > 0 && along < simd_length(t - muzzle) && simd_length(toP - dir * along) < 1.2 { return }
        let scale: Float = gs.pellets > 1 ? 0.6 : 1
        switch gs.shot {
        case .bullet:
            for _ in 0..<gs.pellets {
                g.arms.spawn(Slug(pos: muzzle, vel: Guns.scatter(dir, 0.02 + gs.spread * 0.5) * gs.speed, kind: .bullet, damage: gs.damage * scale,
                                  fromPlayer: true, shooter: ObjectIdentifier(self), by: customName ?? "Companion", life: gs.range / gs.speed, gravity: 1.5))
            }
        case .beam:
            g.arms.beam(g, from: muzzle, dir: Guns.scatter(dir, 0.02), range: gs.range, damage: gs.damage, fromPlayer: true, shooter: self, by: customName ?? "Companion")
        case .rocket:
            return
        }
        g.sfx(.gun(gs.sound), 0.9, at: muzzle)
        g.addFlash(at: muzzle + dir * 0.3, color: V3(4, 3, 1.6), radius: 6, life: 0.06)
        b.mag -= 1
        b.recoil = 1
        b.shotTimer = gs.auto ? gs.interval * 2 : max(gs.interval, 0.6) + Rand.float(in: 0...0.4)
    }
}
